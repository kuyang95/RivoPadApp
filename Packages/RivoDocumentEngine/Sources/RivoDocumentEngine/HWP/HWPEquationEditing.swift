import Foundation

public nonisolated enum HWPEquationEditing {
    public struct Selection: Identifiable, Sendable {
        public let id = UUID()
        public let blockID: String
        public let text: String
        public let caret: Int
        public let width: Double
    
    public init(blockID: String, text: String, caret: Int, width: Double) {
        self.blockID = blockID
        self.text = text
        self.caret = caret
        self.width = width
    }
}

    public struct Request: Sendable {
        public let selection: Selection
        public let script: String
        public let fontSizePoints: Double

        public var isValid: Bool {
            let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed.utf16.count <= 32_768
                && fontSizePoints.isFinite && (6...144).contains(fontSizePoints)
        }
    
    public init(selection: Selection, script: String, fontSizePoints: Double) {
        self.selection = selection
        self.script = script
        self.fontSizePoints = fontSizePoints
    }
}

    public struct Target: Identifiable, Sendable {
        public let ownerID: String
        public let objectID: String
        public let script: String
        public let fontSizePoints: Double
        public let colorRGB: UInt32
        public let baselinePercent: Double
        public let fontName: String?
        public let widthPoints: Double
        public let heightPoints: Double
        public var id: String { objectID }
    
    public init(ownerID: String, objectID: String, script: String, fontSizePoints: Double, colorRGB: UInt32, baselinePercent: Double, fontName: String? = nil, widthPoints: Double, heightPoints: Double) {
        self.ownerID = ownerID
        self.objectID = objectID
        self.script = script
        self.fontSizePoints = fontSizePoints
        self.colorRGB = colorRGB
        self.baselinePercent = baselinePercent
        self.fontName = fontName
        self.widthPoints = widthPoints
        self.heightPoints = heightPoints
    }
}

    public struct Update: Sendable {
        public let script: String
        public let fontSizePoints: Double

        public var isValid: Bool {
            let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed.utf16.count <= 32_768
                && fontSizePoints.isFinite && (6...144).contains(fontSizePoints)
        }
    
    public init(script: String, fontSizePoints: Double) {
        self.script = script
        self.fontSizePoints = fontSizePoints
    }
}

    public enum Action: Sendable { case update(Update), delete }

    public static func selection(blocks: [HWPDocumentBlock], selectedID: String?, range: NSRange,
                          layouts: [HWPDocumentPageLayout]) -> Selection? {
        guard let value = HWPShapeEditing.selection(blocks: blocks, selectedID: selectedID,
            range: range, layouts: layouts) else { return nil }
        return Selection(blockID: value.blockID, text: value.text, caret: value.caret, width: value.width)
    }

    public static func target(owner: HWPDocumentBlock, object: HWPDocumentCanvasObject) -> Target? {
        guard owner.region.kind == .body, owner.tableLocation == nil,
              case .equation(let equation) = object.content else { return nil }
        return Target(ownerID: owner.id, objectID: object.id, script: equation.script,
            fontSizePoints: equation.fontSizePoints, colorRGB: equation.colorRGB,
            baselinePercent: equation.baselinePercent, fontName: equation.fontName,
            widthPoints: object.placement.widthPoints, heightPoints: object.placement.heightPoints)
    }

    @MainActor public static func inserting(_ request: Request, source: HWPTableStructureDocument,
                                     drafts: [HWPDocumentBlock]) async throws -> HWPTableStructureDocument.Result {
        guard request.isValid, drafts.count <= HWPXDocumentPackage.maximumBlocks - 2,
              let index = drafts.firstIndex(where: { $0.id == request.selection.blockID }),
              drafts[index].text == request.selection.text,
              selection(blocks: drafts, selectedID: request.selection.blockID,
                  range: NSRange(location: request.selection.caret, length: 0), layouts: source.layouts) != nil else {
            throw HWPDocumentEditingError.staleDocument
        }
        let (prepared, changed, ownerIndex) = try await Task.detached(priority: .userInitiated) {
            let base = try HWPTableStructureDocument.load(source.serialized(drafts))
            guard base.blocks.indices.contains(index), base.blocks[index].text == request.selection.text,
                  let split = HWPParagraphEditing.apply(.split(.init(location: request.selection.caret, length: 0)),
                    draft: base.blocks[index], to: base.blocks),
                  let suffix = split.blocks.first(where: { $0.id == split.focusedID }),
                  let second = HWPParagraphEditing.apply(.split(.init(location: 0, length: 0)),
                    draft: suffix, to: split.blocks) else { throw HWPDocumentEditingError.unsupportedEdit }
            var blocks = second.blocks
            guard let ownerIndex = blocks.firstIndex(where: { $0.id == suffix.id }) else {
                throw HWPDocumentEditingError.staleDocument
            }
            for command in [HWPFormattingCommand.clearCharacterFormatting, .alignment(.leading),
                            .paragraph(left: 0, right: 0, indent: 0, before: 0, after: 0, linePercent: 160)] {
                blocks[ownerIndex] = HWPDocumentFormatting.apply(command, to: blocks[ownerIndex],
                    range: NSRange(location: 0, length: 0))
            }
            let prepared = try HWPTableStructureDocument.load(base.serialized(blocks))
            let bytes = try HWPEquationEditingWriter.insert(request, into: prepared, ownerIndex: ownerIndex)
            return (prepared, try HWPTableStructureDocument.load(bytes), ownerIndex)
        }.value
        guard changed.blocks.indices.contains(ownerIndex),
              changed.blocks[ownerIndex].canvasObjects.contains(where: { if case .equation = $0.content { return true }; return false }),
              let layout = changed.layouts.first(where: {
                  $0.sectionIndex == HWPPageSetup.sectionIndex(changed.blocks[ownerIndex].sectionPath)
              }) else { throw HWPDocumentEditingError.cannotSave }
        let height = changed.blocks[ownerIndex].canvasObjects.compactMap { object -> Double? in
            if case .equation = object.content { return object.placement.heightPoints }
            return nil
        }.max() ?? max(28, request.fontSizePoints * 2.4)
        let final = try await finalized(changed: changed, before: prepared.blocks,
            ownerIndex: ownerIndex, minimumHeight: height, layout: layout)
        return .init(document: final, focusedID: final.blocks[ownerIndex].id)
    }

    @MainActor public static func applying(_ action: Action, target: Target, source: HWPTableStructureDocument,
                                    drafts: [HWPDocumentBlock]) async throws -> HWPTableStructureDocument.Result {
        guard let ownerIndex = drafts.firstIndex(where: { $0.id == target.ownerID }),
              let current = drafts[ownerIndex].canvasObjects.first(where: { $0.id == target.objectID }),
              Self.target(owner: drafts[ownerIndex], object: current)?.script == target.script else {
            throw HWPDocumentEditingError.staleDocument
        }
        if case .update(let update) = action, !update.isValid { throw HWPDocumentEditingError.limitExceeded }
        let (base, changed) = try await Task.detached(priority: .userInitiated) {
            let base = try HWPTableStructureDocument.load(source.serialized(drafts))
            guard base.blocks.indices.contains(ownerIndex),
                  base.blocks[ownerIndex].canvasObjects.contains(where: { $0.id == target.objectID }) else {
                throw HWPDocumentEditingError.staleDocument
            }
            let data = try HWPEquationEditingWriter.apply(action, target: target, to: base, ownerIndex: ownerIndex)
            return (base, try HWPTableStructureDocument.load(data))
        }.value
        if drafts[ownerIndex].layoutContainerID != nil {
            switch action {
            case .delete:
                guard !changed.blocks[ownerIndex].canvasObjects.contains(where: { $0.id == target.objectID }) else {
                    throw HWPDocumentEditingError.cannotSave
                }
            case .update(let update):
                guard changed.blocks[ownerIndex].canvasObjects.contains(where: {
                    if case .equation(let equation) = $0.content {
                        return equation.script == update.script
                            && abs(equation.fontSizePoints - update.fontSizePoints) < 0.02
                    }
                    return false
                }) else { throw HWPDocumentEditingError.cannotSave }
            }
            return .init(document: changed, focusedID: changed.blocks[ownerIndex].id)
        }
        guard changed.blocks.indices.contains(ownerIndex),
              let page = changed.layouts.first(where: {
                  $0.sectionIndex == HWPPageSetup.sectionIndex(changed.blocks[ownerIndex].sectionPath)
              }) else { throw HWPDocumentEditingError.cannotSave }
        let minimum = action.minimumHeight(fallback: target.heightPoints)
        let final = try await finalized(changed: changed, before: base.blocks,
            ownerIndex: ownerIndex, minimumHeight: minimum, layout: page)
        switch action {
        case .delete:
            guard !final.blocks[ownerIndex].canvasObjects.contains(where: { $0.id == target.objectID }) else {
                throw HWPDocumentEditingError.cannotSave
            }
        case .update(let update):
            guard final.blocks[ownerIndex].canvasObjects.contains(where: {
                if case .equation(let equation) = $0.content {
                    return equation.script == update.script && abs(equation.fontSizePoints - update.fontSizePoints) < 0.02
                }
                return false
            }) else { throw HWPDocumentEditingError.cannotSave }
        }
        return .init(document: final, focusedID: final.blocks[ownerIndex].id)
    }

    @MainActor private static func finalized(changed: HWPTableStructureDocument, before: [HWPDocumentBlock],
                                             ownerIndex: Int, minimumHeight: Double,
                                             layout: HWPDocumentPageLayout) async throws -> HWPTableStructureDocument {
        var flowed = changed.blocks
        let owner = flowed[ownerIndex]
        let bodyWidth = layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints
            - owner.presentation.leftMarginPoints - owner.presentation.rightMarginPoints
        let y = before.indices.contains(ownerIndex) ? before[ownerIndex].lineLayouts.first?.verticalPositionPoints ?? 0 : 0
        flowed[ownerIndex] = owner.withLayout(lines: HWPFlowLayout.measure(owner,
            width: max(bodyWidth, 1), startY: y,
            pageHeight: layout.heightPoints - layout.topMarginPoints - layout.bottomMarginPoints,
            minimumHeight: minimumHeight))
        flowed = HWPFlowLayout.reflowingBody(flowed, before: before, startingAt: flowed[ownerIndex].id,
            layouts: changed.layouts)
        let output = try await Task.detached(priority: .userInitiated) {
            try HWPTableStructureDocument.load(changed.serialized(flowed))
        }.value
        guard output.blocks.count == flowed.count,
              zip(output.blocks, flowed).allSatisfy({ HWPDocumentFormatting.matches($0, $1) }) else {
            throw HWPDocumentEditingError.cannotSave
        }
        return output
    }
}

private extension HWPEquationEditing.Action {
    func minimumHeight(fallback: Double) -> Double {
        switch self {
        case .delete: 0
        case .update(let update): max(fallback, update.fontSizePoints * 2.4)
        }
    }
}
