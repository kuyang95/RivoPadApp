import Foundation

public nonisolated enum HWPParagraphEdit: Sendable {
    case split(NSRange)
    case mergeBackward
    case insertPageBreak(NSRange)
    case removePageBreak

    public var changesPageBreak: Bool {
        switch self { case .insertPageBreak, .removePageBreak: true; default: false }
    }
}

public nonisolated struct HWPParagraphEditResult: Sendable {
    public let blocks: [HWPDocumentBlock]
    public let focusedID: String
    public let caret: Int

    public init(blocks: [HWPDocumentBlock], focusedID: String, caret: Int) {
        self.blocks = blocks
        self.focusedID = focusedID
        self.caret = caret
    }
}

/// Structural operations use UTF-16 selections, like UIKit and HWP character records.
public nonisolated enum HWPParagraphEditing {
    public static func supports(_ block: HWPDocumentBlock) -> Bool {
        block.isEditable && block.region.kind == .body && block.tableLocation == nil
            && block.layoutContainerID == nil && block.images.isEmpty && block.canvasObjects.isEmpty
            && (block.presentation.list?.isSimple ?? !block.lineLayouts.contains(where: { $0.listMarker != nil }))
    }

    public static func supportsCellParagraph(_ block: HWPDocumentBlock) -> Bool {
        block.isEditable && block.region.kind == .body && block.tableLocation != nil
            && block.layoutContainerID == nil && block.images.isEmpty && block.canvasObjects.isEmpty
            && (block.presentation.list?.isSimple ?? !block.lineLayouts.contains(where: { $0.listMarker != nil }))
    }

    public static func supportsStructure(_ block: HWPDocumentBlock) -> Bool {
        supports(block) || supportsCellParagraph(block)
    }

    private static func sameContainer(_ a: HWPDocumentBlock, _ b: HWPDocumentBlock) -> Bool {
        guard a.sectionPath.lowercased() == b.sectionPath.lowercased(), a.region == b.region else { return false }
        switch (a.tableLocation, b.tableLocation) {
        case (nil, nil): return true
        case (.some, .some): return HWPCellFormatting.sameCell(a, b)
        default: return false
        }
    }

    public static func apply(_ operation: HWPParagraphEdit, draft: HWPDocumentBlock,
                      to blocks: [HWPDocumentBlock]) -> HWPParagraphEditResult? {
        guard supportsStructure(draft), let index = blocks.firstIndex(where: { $0.id == draft.id }) else { return nil }
        var result = blocks
        switch operation {
        case .split(let range), .insertPageBreak(let range):
            let pageBreak = operation.changesPageBreak
            if pageBreak, draft.tableLocation != nil { return nil }
            if !pageBreak, draft.text.isEmpty, draft.presentation.list != nil, range == NSRange(location: 0, length: 0) {
                result[index] = HWPDocumentFormatting.apply(.list(nil), to: draft, range: range)
                return HWPParagraphEditResult(blocks: HWPListFormatting.renumbering(result), focusedID: draft.id, caret: 0)
            }
            let length = draft.text.utf16.count
            let boundaries = Set(draft.text.indices.map { $0.utf16Offset(in: draft.text) } + [length])
            guard blocks.count < 20_000, range.location >= 0, range.length >= 0,
                  range.location <= length, range.length <= length - range.location,
                  boundaries.contains(range.location), boundaries.contains(NSMaxRange(range)) else { return nil }
            if pageBreak, range == NSRange(location: 0, length: 0),
               blocks[..<index].contains(where: { $0.sectionPath == draft.sectionPath && $0.region.kind == .body && $0.tableLocation == nil }) {
                guard !draft.presentation.pageBreakBefore else { return nil }
                result[index] = withPageBreak(true, in: draft)
                return HWPParagraphEditResult(blocks: result, focusedID: draft.id, caret: 0)
            }
            let left = slice(draft, range: NSRange(location: 0, length: range.location))
            let right = slice(draft, range: NSRange(location: NSMaxRange(range), length: length - NSMaxRange(range)))
            var style = right.presentation
            style.pageBreakBefore = pageBreak
            let insertedLocation = draft.tableLocation.map { $0.withParagraph($0.paragraph + 1) }
            let inserted = HWPDocumentBlock(id: "hwp-new-\(UUID().uuidString)", sectionPath: draft.sectionPath,
                paragraphIndex: min(0, blocks.map(\.paragraphIndex).min() ?? 0) - 1,
                text: right.text, tableLocation: insertedLocation, isEditable: true, presentation: style,
                region: draft.region, layoutContainerID: draft.layoutContainerID,
                sourceParagraphID: draft.sourceParagraphID ?? draft.id)
            result[index] = left
            // Header/footer children are serialized inside their body owner.
            // A new body paragraph follows that complete owner subtree.
            var insertion = index + 1
            while insertion < result.count, result[insertion].sectionPath == draft.sectionPath,
                  [.header, .footer].contains(result[insertion].region.kind) { insertion += 1 }
            result.insert(inserted, at: insertion)
            if let cell = draft.tableLocation {
                for position in result.indices where position != insertion
                    && (result[position].tableLocation?.paragraph ?? -1) > cell.paragraph
                    && sameContainer(result[position], draft) {
                    let location = result[position].tableLocation!
                    result[position] = result[position].withLayout(
                        tableLocation: location.withParagraph(location.paragraph + 1))
                }
            }
            return HWPParagraphEditResult(blocks: HWPListFormatting.renumbering(result), focusedID: inserted.id, caret: 0)
        case .mergeBackward:
            if draft.presentation.pageBreakBefore {
                result[index] = withPageBreak(false, in: draft)
                return HWPParagraphEditResult(blocks: result, focusedID: draft.id, caret: 0)
            }
            if draft.presentation.list != nil {
                result[index] = HWPDocumentFormatting.apply(.list(nil), to: draft, range: NSRange(location: 0, length: 0))
                return HWPParagraphEditResult(blocks: HWPListFormatting.renumbering(result), focusedID: draft.id, caret: 0)
            }
            var previousIndex = index - 1
            while previousIndex >= 0, [.header, .footer].contains(blocks[previousIndex].region.kind),
                  blocks[previousIndex].sectionPath == draft.sectionPath { previousIndex -= 1 }
            guard previousIndex >= 0, !draft.keepsParagraphBoundary, supportsStructure(blocks[previousIndex]),
                  sameContainer(blocks[previousIndex], draft) else { return nil }
            let previous = blocks[previousIndex]
            guard previous.text.utf16.count + draft.text.utf16.count <= 100_000 else { return nil }
            var style = previous.presentation
            style.textRuns = HWPDocumentFormatting.runs(in: previous).filter { !$0.text.isEmpty }
                + HWPDocumentFormatting.runs(in: draft).filter { !$0.text.isEmpty }
            if style.textRuns.isEmpty { style.textRuns = HWPDocumentFormatting.runs(in: previous) }
            result[previousIndex] = HWPDocumentFormatting.replacingPresentation(of: previous,
                with: style, text: previous.text + draft.text)
            result.remove(at: index)
            if let cell = draft.tableLocation {
                for position in result.indices where (result[position].tableLocation?.paragraph ?? -1) > cell.paragraph
                    && sameContainer(result[position], draft) {
                    let location = result[position].tableLocation!
                    result[position] = result[position].withLayout(
                        tableLocation: location.withParagraph(location.paragraph - 1))
                }
            }
            return HWPParagraphEditResult(blocks: HWPListFormatting.renumbering(result), focusedID: previous.id, caret: previous.text.utf16.count)
        case .removePageBreak:
            guard draft.presentation.pageBreakBefore else { return nil }
            result[index] = withPageBreak(false, in: draft)
            return HWPParagraphEditResult(blocks: result, focusedID: draft.id, caret: 0)
        }
    }

    private static func withPageBreak(_ flag: Bool, in block: HWPDocumentBlock) -> HWPDocumentBlock {
        var style = block.presentation; style.pageBreakBefore = flag
        return HWPDocumentFormatting.replacingPresentation(of: block, with: style, text: block.text)
    }

    /// Removing a break must begin layout before its old page boundary, so the
    /// paragraph rejoins the preceding content instead of keeping cached y=0.
    @MainActor public static func reflow(_ proposal: HWPParagraphEditResult, before: [HWPDocumentBlock],
                       draft: HWPDocumentBlock, operation: HWPParagraphEdit,
                       layouts: [HWPDocumentPageLayout]) -> [HWPDocumentBlock] {
        let breakChanged = operation.changesPageBreak || (draft.presentation.pageBreakBefore && {
            if case .mergeBackward = operation { return true }; return false
        }())
        if breakChanged, let layout = layouts.first(where: { $0.sectionIndex == HWPPageSetup.sectionIndex(draft.sectionPath) }) {
            let before = HWPFlowLayout.resolvingMissingLines(before.filter { $0.sectionPath == draft.sectionPath }, layout: layout)
            let section = HWPFlowLayout.resolvingMissingLines(proposal.blocks.filter { $0.sectionPath == draft.sectionPath }, layout: layout)
            guard let first = section.first(where: { $0.region.kind == .body && $0.tableLocation == nil && $0.layoutContainerID == nil }) else { return proposal.blocks }
            let flowed = HWPFlowLayout.reflowingBody(section, before: before, startingAt: first.id,
                layouts: [layout.pageSetupFlowLayout], reflowingTables: true)
            var offset = 0
            return proposal.blocks.map { block in
                guard block.sectionPath == draft.sectionPath else { return block }
                defer { offset += 1 }; return flowed[offset]
            }
        }
        let start: String
        switch operation { case .split, .insertPageBreak: start = draft.id; case .mergeBackward, .removePageBreak: start = proposal.focusedID }
        if draft.tableLocation != nil {
            return HWPTableEditing.reflow(proposal.blocks, before: before, startingAt: start, layouts: layouts)
        }
        return HWPFlowLayout.reflowingBody(proposal.blocks, before: before, startingAt: start, layouts: layouts)
    }

    public static func slice(_ block: HWPDocumentBlock, range: NSRange) -> HWPDocumentBlock {
        let source = block.text as NSString
        var offset = 0
        var runs = HWPDocumentFormatting.runs(in: block).compactMap { run -> HWPDocumentTextRun? in
            let runRange = NSRange(location: offset, length: run.text.utf16.count)
            offset += runRange.length
            let intersection = NSIntersectionRange(range, runRange)
            return intersection.length > 0 ? run.withText(source.substring(with: intersection)) : nil
        }
        if runs.isEmpty { runs = [HWPDocumentFormatting.run(at: max(0, range.location - 1), in: block).withText("")] }
        var style = block.presentation
        style.textRuns = runs
        return HWPDocumentFormatting.replacingPresentation(of: block, with: style, text: source.substring(with: range))
    }

    /// Retain the parser's new ordinals and container identities after inserting raw paragraphs.
    public static func rebased(_ edited: [HWPDocumentBlock], onto parsed: [HWPDocumentBlock]) throws -> [HWPDocumentBlock] {
        guard edited.count == parsed.count else { throw HWPDocumentEditingError.cannotSave }
        return try zip(edited, parsed).map { draft, base in
            guard sameContainer(draft, base) else {
                throw HWPDocumentEditingError.cannotSave
            }
            return HWPDocumentBlock(id: base.id, sectionPath: base.sectionPath, paragraphIndex: base.paragraphIndex,
                text: draft.text, tableLocation: draft.tableLocation, isEditable: base.isEditable,
                presentation: draft.presentation, region: base.region, images: base.images,
                lineLayouts: draft.lineLayouts, canvasObjects: base.canvasObjects, layoutContainerID: base.layoutContainerID, keepsParagraphBoundary: base.keepsParagraphBoundary)
        }
    }

    /// Only ordered insertions and deletions of plain body paragraphs are accepted.
    public static func validate(originals: [HWPDocumentBlock], edited: [HWPDocumentBlock]) throws {
        let oldIDs = Set(originals.map(\.id)), newIDs = Set(edited.map(\.id))
        guard newIDs.count == edited.count, oldIDs.count == originals.count, edited.count <= 20_000,
              originals.filter({ newIDs.contains($0.id) }).map(\.id) == edited.filter({ oldIDs.contains($0.id) }).map(\.id) else {
            throw HWPDocumentEditingError.staleDocument
        }
        let byID = Dictionary(uniqueKeysWithValues: originals.map { ($0.id, $0) })
        for removed in originals where !newIDs.contains(removed.id) {
            guard supportsStructure(removed), !removed.keepsParagraphBoundary else { throw HWPDocumentEditingError.unsupportedEdit }
        }
        var anchor: HWPDocumentBlock?
        for block in edited {
            if let original = byID[block.id] {
                guard sameContainer(original, block) else { throw HWPDocumentEditingError.staleDocument }
                if ![.header, .footer].contains(original.region.kind) { anchor = original }
            } else {
                guard let origin = block.sourceParagraphID.flatMap({ byID[$0] }),
                      supportsStructure(origin), supportsStructure(block),
                      let anchor, supportsStructure(anchor), sameContainer(anchor, block),
                      sameContainer(origin, block) else { throw HWPDocumentEditingError.unsupportedEdit }
            }
        }
        for members in Dictionary(grouping: originals.filter { $0.tableLocation != nil }, by: { block in
            let cell = block.tableLocation!
            return "\(block.sectionPath.lowercased()):\(cell.table):\(String(describing: cell.parent)):\(cell.row):\(cell.column)"
        }).values {
            guard edited.contains(where: { candidate in
                members.contains(where: { sameContainer($0, candidate) })
            }) else { throw HWPDocumentEditingError.unsupportedEdit }
        }
    }
}

private extension HWPDocumentTableLocation {
    nonisolated func withParagraph(_ value: Int) -> HWPDocumentTableLocation {
        HWPDocumentTableLocation(table: table, row: row, column: column, paragraph: value,
            rowSpan: rowSpan, columnSpan: columnSpan, boxStyle: boxStyle,
            cellWidthPoints: cellWidthPoints, cellHeightPoints: cellHeightPoints,
            cellMarginLeftPoints: cellMarginLeftPoints, cellMarginRightPoints: cellMarginRightPoints,
            cellMarginTopPoints: cellMarginTopPoints, cellMarginBottomPoints: cellMarginBottomPoints,
            cellVerticalAlignment: cellVerticalAlignment, tablePageBoundaryMode: tablePageBoundaryMode,
            repeatsHeaderRow: repeatsHeaderRow, tablePlacement: tablePlacement, tableAnchor: tableAnchor,
            parent: parent, backgroundZones: backgroundZones)
    }
}
