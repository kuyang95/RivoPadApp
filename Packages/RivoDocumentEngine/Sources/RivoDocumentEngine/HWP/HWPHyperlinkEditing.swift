import Foundation

public nonisolated enum HWPHyperlinkEditing {
    public struct Selection: Identifiable, Sendable {
        public let blockID: String
        public let text: String
        public let range: NSRange
        public let target: String?
        public var id: String { "\(blockID):\(range.location):\(range.length)" }
    
    public init(blockID: String, text: String, range: NSRange, target: String? = nil) {
        self.blockID = blockID
        self.text = text
        self.range = range
        self.target = target
    }
}

    public enum Action: Sendable { case set(String), remove }

    public struct Span: Hashable, Sendable {
        public let range: NSRange
        public let target: String
    
    public init(range: NSRange, target: String) {
        self.range = range
        self.target = target
    }
}

    public static func selection(blocks: [HWPDocumentBlock], selectedID: String?, range: NSRange) -> Selection? {
        guard let id = selectedID, let block = blocks.first(where: { $0.id == id }),
              HWPParagraphEditing.supports(block), block.region.kind == .body,
              block.layoutContainerID == nil, block.canvasObjects.isEmpty,
              range.location >= 0, range.length >= 0,
              range.location <= block.text.utf16.count,
              range.length <= block.text.utf16.count - range.location else { return nil }
        let boundaries = Set(block.text.indices.map { $0.utf16Offset(in: block.text) } + [block.text.utf16.count])
        guard boundaries.contains(range.location), boundaries.contains(NSMaxRange(range)) else { return nil }
        if range.length > 0 {
            let selected = spans(in: block).filter { NSIntersectionRange($0.range, range).length > 0 }
            let target = selected.count == 1 && selected[0].range.location <= range.location
                && NSMaxRange(selected[0].range) >= NSMaxRange(range) ? selected[0].target : nil
            return Selection(blockID: block.id, text: block.text, range: range, target: target)
        }
        if let span = spans(in: block).first(where: {
            range.location >= $0.range.location && range.location <= NSMaxRange($0.range)
        }) {
            return Selection(blockID: block.id, text: block.text, range: span.range, target: span.target)
        }
        return nil
    }

    public static func normalizedTarget(_ value: String) -> String? {
        var target = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, target.utf16.count <= 2_048,
              target.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              }) else { return nil }
        if !target.contains(":") { target = "https://" + target }
        guard let components = URLComponents(string: target),
              let scheme = components.scheme?.lowercased(),
              ["http", "https", "mailto", "tel"].contains(scheme),
              components.url != nil else { return nil }
        if ["http", "https"].contains(scheme), components.host?.isEmpty != false { return nil }
        return target
    }

    public static func spans(in block: HWPDocumentBlock) -> [Span] {
        var result: [Span] = [], offset = 0
        for run in HWPDocumentFormatting.runs(in: block) {
            let length = run.text.utf16.count
            if let target = run.hyperlink, !target.isEmpty, length > 0 {
                if let last = result.last, last.target == target, NSMaxRange(last.range) == offset {
                    result[result.count - 1] = Span(range: NSRange(location: last.range.location,
                        length: last.range.length + length), target: target)
                } else {
                    result.append(Span(range: NSRange(location: offset, length: length), target: target))
                }
            }
            offset += length
        }
        return result
    }

    public static func applying(_ action: Action, to block: HWPDocumentBlock, range: NSRange) throws -> HWPDocumentBlock {
        let target: String?
        switch action {
        case .set(let value):
            guard let normalized = normalizedTarget(value) else { throw HWPDocumentEditingError.invalidDocument }
            target = normalized
        case .remove: target = nil
        }
        guard range.length > 0, range.location >= 0, NSMaxRange(range) <= block.text.utf16.count else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        var style = block.presentation, offset = 0
        style.textRuns = HWPDocumentFormatting.runs(in: block).flatMap { run -> [HWPDocumentTextRun] in
            let source = run.text as NSString
            let runRange = NSRange(location: offset, length: source.length)
            offset += source.length
            let overlap = NSIntersectionRange(runRange, range)
            guard overlap.length > 0 else { return [run] }
            let start = overlap.location - runRange.location, end = start + overlap.length
            var pieces: [HWPDocumentTextRun] = []
            if start > 0 { pieces.append(run.withText(source.substring(to: start))) }
            var changed = run.withText(source.substring(with: NSRange(location: start, length: overlap.length)))
            changed.hyperlink = target
            if target != nil { changed.textColorRGB = 0x0000EE; changed.isUnderlined = true }
            pieces.append(changed)
            if end < source.length { pieces.append(run.withText(source.substring(from: end))) }
            return pieces
        }
        return HWPDocumentFormatting.replacingPresentation(of: block, with: style)
    }

    @MainActor public static func applying(_ action: Action, selection: Selection,
                                    source: HWPTableStructureDocument,
                                    drafts: [HWPDocumentBlock]) async throws -> HWPTableStructureDocument.Result {
        guard let index = drafts.firstIndex(where: { $0.id == selection.blockID }),
              drafts[index].text == selection.text,
              Self.selection(
                  blocks: drafts,
                  selectedID: selection.blockID,
                  range: selection.range
              ) != nil else {
            throw HWPDocumentEditingError.staleDocument
        }
        let result = try await Task.detached(priority: .userInitiated) {
            let base = try HWPTableStructureDocument.load(source.serialized(drafts))
            guard base.blocks.indices.contains(index) else { throw HWPDocumentEditingError.staleDocument }
            var blocks = base.blocks
            blocks[index] = try applying(action, to: blocks[index], range: selection.range)
            let output = try HWPTableStructureDocument.load(base.serialized(blocks))
            guard output.blocks.indices.contains(index),
                  spans(in: output.blocks[index]) == spans(in: blocks[index]) else {
                throw HWPDocumentEditingError.cannotSave
            }
            return output
        }.value
        return .init(document: result, focusedID: result.blocks[index].id)
    }
}
