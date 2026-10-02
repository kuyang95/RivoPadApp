import Foundation

public nonisolated enum HWPXLineLayoutWriter {
    public static func apply(_ data: Data, originals: [HWPDocumentBlock], edited: [HWPDocumentBlock]) throws -> Data {
        let changes = Dictionary(uniqueKeysWithValues: zip(originals, edited).filter {
            !$1.lineLayouts.isEmpty && ($0.text != $1.text || HWP5FormattingWriter.lineData($0.lineLayouts) != HWP5FormattingWriter.lineData($1.lineLayouts))
        }.map { ($0.0.id, $0.1.lineLayouts) })
        guard !changes.isEmpty else { return data }
        let package = try HWPXDocumentPackage.load(from: data)
        var replacements: [String: Data] = [:]
        for section in package.sections {
            let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: section.xml)
            let xml = section.xml as NSString
            var patches: [(NSRange, String)] = []
            for index in ranges.indices.reversed() {
                guard let lines = changes[section.blocks[index].id] else { continue }
                let paragraph = xml.substring(with: ranges[index])
                let prefix = try HWPFormattingXML.prefix(paragraph)
                let cache = lines.map { line in
                    "<\(prefix)lineseg textpos=\"\(line.startCharacter)\" vertpos=\"\(Int((line.verticalPositionPoints * 100).rounded()))\" vertsize=\"\(Int((line.lineHeightPoints * 100).rounded()))\" textheight=\"\(Int((line.textHeightPoints * 100).rounded()))\" baseline=\"\(Int((line.baselinePoints * 100).rounded()))\" spacing=\"\(Int((line.lineSpacingPoints * 100).rounded()))\" horzpos=\"\(Int((line.columnStartPoints * 100).rounded()))\" horzsize=\"\(Int((line.widthPoints * 100).rounded()))\" flags=\"\(line.flags)\"/>"
                }.joined()
                // Nested cell paragraphs own their own caches. Remove only this paragraph's cache.
                var depth = 0, start: Int?, ownRanges: [NSRange] = []
                for token in try HWPXParagraphXMLPatcher.tagTokens(in: paragraph) {
                    if token.localName == "p", !token.isSelfClosing { depth += token.isClosing ? -1 : 1 }
                    if token.localName == "linesegarray", depth == 1 {
                        if token.isSelfClosing { ownRanges.append(token.range) }
                        else if token.isClosing, let begin = start { ownRanges.append(NSRange(location: begin, length: NSMaxRange(token.range) - begin)); start = nil }
                        else if !token.isClosing { start = token.range.location }
                    }
                }
                for range in ownRanges {
                    patches.append((NSRange(location: ranges[index].location + range.location, length: range.length), ""))
                }
                let tokens = try HWPXParagraphXMLPatcher.tagTokens(in: paragraph)
                guard let closing = tokens.last(where: { $0.localName == "p" && $0.isClosing }) else {
                    // A self-closing empty paragraph has no nested cache to preserve.
                    let replacement = try HWPFormattingXML.append("<\(prefix)linesegarray>\(cache)</\(prefix)linesegarray>", to: paragraph)
                    patches.append((ranges[index], replacement))
                    continue
                }
                patches.append((NSRange(location: ranges[index].location + closing.range.location, length: 0),
                    "<\(prefix)linesegarray>\(cache)</\(prefix)linesegarray>"))
            }
            var result = xml as String
            for (range, value) in patches.sorted(by: { $0.0.location > $1.0.location }) {
                result = (result as NSString).replacingCharacters(in: range, with: value)
            }
            if result != section.xml { replacements[section.path] = Data(result.utf8) }
        }
        return try HWPXEditingArchive(data: data).repack(replacing: replacements)
    }
}
