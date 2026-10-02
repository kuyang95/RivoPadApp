import Foundation

public nonisolated struct HWPTextMatch: Identifiable, Equatable, Sendable {
    public let blockID: String
    public let sourceText: String
    public let range: NSRange
    public let isReplaceable: Bool
    public var id: String { "\(blockID):\(range.location):\(range.length)" }

    public init(blockID: String, sourceText: String, range: NSRange, isReplaceable: Bool) {
        self.blockID = blockID
        self.sourceText = sourceText
        self.range = range
        self.isReplaceable = isReplaceable
    }
}

public nonisolated enum HWPFindReplaceError: LocalizedError {
    case staleMatch, tooManyMatches, invalidReplacement
    public var errorDescription: String? {
        switch self {
        case .staleMatch: return DocumentEngineLocalization.string("검색한 내용이 변경되었습니다. 다시 찾은 뒤 바꿔 주세요.")
        case .tooManyMatches: return DocumentEngineLocalization.string("검색 결과가 너무 많습니다. 찾을 내용을 더 구체적으로 입력해 주세요.")
        case .invalidReplacement: return DocumentEngineLocalization.string("바꿀 내용에 입력할 수 없는 문자가 있습니다.")
        }
    }
}

public nonisolated enum HWPFindReplace {
    public static let maximumMatches = 20_000
    public struct Scan: Sendable {
        public var matches: [HWPTextMatch] = []
        public var exceedsLimit = false
    
    public init(matches: [HWPTextMatch] = [], exceedsLimit: Bool = false) {
        self.matches = matches
        self.exceedsLimit = exceedsLimit
    }
}
    public struct Proposal: Sendable {
        public let blocks: [HWPDocumentBlock]
        public let changedIDs: [String]
        public let replacementCount: Int
        public let skippedCount: Int
    
    public init(blocks: [HWPDocumentBlock], changedIDs: [String], replacementCount: Int, skippedCount: Int) {
        self.blocks = blocks
        self.changedIDs = changedIDs
        self.replacementCount = replacementCount
        self.skippedCount = skippedCount
    }
}

    public static func isSearchable(_ block: HWPDocumentBlock) -> Bool {
        block.region.kind == .body && block.layoutContainerID == nil
    }

    public static func scan(_ blocks: [HWPDocumentBlock], query: String, matchCase: Bool = false) -> Scan {
        guard !query.isEmpty else { return Scan() }
        var result = Scan()
        for block in blocks where isSearchable(block) {
            let source = block.text as NSString
            var offset = 0
            let boundaries = Set(block.text.indices.map { $0.utf16Offset(in: block.text) } + [source.length])
            let options: NSString.CompareOptions = matchCase ? [.diacriticInsensitive] : [.caseInsensitive, .diacriticInsensitive]
            while offset < source.length {
                let range = source.range(of: query, options: options,
                    range: NSRange(location: offset, length: source.length - offset))
                guard range.location != NSNotFound, range.length > 0 else { break }
                offset = NSMaxRange(range)
                // Never target half an emoji, a surrogate or a composed syllable.
                guard boundaries.contains(range.location), boundaries.contains(offset) else { continue }
                guard result.matches.count < maximumMatches else { result.exceedsLimit = true; return result }
                result.matches.append(HWPTextMatch(blockID: block.id, sourceText: block.text, range: range,
                    isReplaceable: block.isEditable && block.images.isEmpty && block.canvasObjects.isEmpty))
            }
        }
        return result
    }

    /// All ranges refer to the same pre-edit snapshot. Replacement text is not
    /// searched again, even when it contains the query itself.
    public static func propose(blocks: [HWPDocumentBlock], query: String, matchCase: Bool = false,
                        replacement: String, selected: HWPTextMatch? = nil) throws -> Proposal {
        let value = HWPInlineTextInput.normalized(replacement)
        guard HWPInlineTextInput.accepts(value, replacing: NSRange(location: 0, length: 0), in: "") else {
            throw HWPFindReplaceError.invalidReplacement
        }
        let scan = scan(blocks, query: query, matchCase: matchCase)
        if selected == nil, scan.exceedsLimit { throw HWPFindReplaceError.tooManyMatches }
        let matches: [HWPTextMatch]
        if let selected {
            guard let fresh = scan.matches.first(where: { $0.id == selected.id }), fresh == selected else {
                throw HWPFindReplaceError.staleMatch
            }
            matches = [fresh]
        } else { matches = scan.matches }
        let grouped = Dictionary(grouping: matches.filter(\.isReplaceable), by: \.blockID)
        var result = blocks, ids: [String] = [], count = 0
        for index in blocks.indices {
            guard let targets = grouped[blocks[index].id] else { continue }
            let ranges = targets.map(\.range)
            let expectedLength = blocks[index].text.utf16.count - ranges.reduce(0) { $0 + $1.length }
                + ranges.count * value.utf16.count
            guard expectedLength <= 100_000 else { throw HWPDocumentEditingError.limitExceeded }
            let updated = replacing(ranges, in: blocks[index], with: value)
            guard updated.text != blocks[index].text else { continue }
            result[index] = updated
            ids.append(updated.id)
            count += targets.filter { ($0.sourceText as NSString).substring(with: $0.range) != value }.count
        }
        return Proposal(blocks: result, changedIDs: ids, replacementCount: count,
            skippedCount: matches.filter { !$0.isReplaceable }.count)
    }

    /// Keep untouched character styles exactly; new text inherits the first
    /// matched character's style. Walk the old runs once, without fuzzy diffing.
    private static func replacing(_ ranges: [NSRange], in block: HWPDocumentBlock, with value: String) -> HWPDocumentBlock {
        let runs = HWPDocumentFormatting.runs(in: block)
        var output: [HWPDocumentTextRun] = []
        var cursor = 0, runIndex = 0, runStart = 0
        func append(_ run: HWPDocumentTextRun) {
            guard !run.text.isEmpty else { return }
            if let last = output.last, last.withText("") == run.withText("") { output[output.count - 1].text += run.text }
            else { output.append(run) }
        }
        func advance(to target: Int, preserving: Bool) {
            while cursor < target, runIndex < runs.count {
                let run = runs[runIndex], length = run.text.utf16.count
                let end = min(target, runStart + length)
                if preserving, end > cursor {
                    append(run.withText((run.text as NSString).substring(with: NSRange(location: cursor - runStart, length: end - cursor))))
                }
                cursor = end
                if cursor == runStart + length { runStart += length; runIndex += 1 }
            }
        }
        for range in ranges {
            advance(to: range.location, preserving: true)
            while runIndex < runs.count - 1, runs[runIndex].text.isEmpty { runIndex += 1 }
            let template = runs[min(runIndex, runs.count - 1)]
            append(template.withText(value))
            advance(to: NSMaxRange(range), preserving: false)
        }
        advance(to: block.text.utf16.count, preserving: true)
        if output.isEmpty { output = [runs[0].withText("")] }
        var style = block.presentation
        style.textRuns = output
        return HWPDocumentFormatting.replacingPresentation(of: block, with: style, text: output.map(\.text).joined())
    }
}
