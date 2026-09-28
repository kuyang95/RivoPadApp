import Foundation

nonisolated enum HWPXParagraphWriter {
    static func rewrite(_ package: HWPXDocumentPackage, edited: [HWPDocumentBlock]) throws -> Data {
        try HWPParagraphEditing.validate(originals: package.blocks, edited: edited)
        let oldByID = Dictionary(uniqueKeysWithValues: package.blocks.map { ($0.id, $0) })
        let retained = Set(edited.map(\.id))
        var insertions: [String: [HWPDocumentBlock]] = [:], anchor = ""
        for block in edited {
            if oldByID[block.id] != nil { if ![.header, .footer].contains(block.region.kind) { anchor = block.id } }
            else { insertions[anchor, default: []].append(block) }
        }
        var replacements: [String: Data] = [:]
        var nextID: UInt32 = 0
        for section in package.sections {
            for range in try HWPXParagraphXMLPatcher.paragraphRanges(in: section.xml) {
                nextID = max(nextID, UInt32(try HWPFormattingXML.attribute((section.xml as NSString).substring(with: range), "id") ?? "0") ?? 0)
            }
        }
        for section in package.sections {
            let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: section.xml)
            guard ranges.count == section.blocks.count else { throw HWPDocumentEditingError.staleDocument }
            let xml = section.xml as NSString
            let paragraphs = zip(section.blocks, ranges).map { ($0.0.id, xml.substring(with: $0.1)) }
            let byID = Dictionary(uniqueKeysWithValues: paragraphs)
            var result = xml
            for index in ranges.indices.reversed() {
                let original = section.blocks[index]
                let paragraph = xml.substring(with: ranges[index])
                let additions = insertions[original.id] ?? []
                guard !retained.contains(original.id) || !additions.isEmpty else { continue }
                if !retained.contains(original.id) {
                    let tokens = try HWPXParagraphXMLPatcher.tagTokens(in: paragraph)
                    let safe: Set<String> = ["p", "run", "t", "tab", "linebreak", "hyphen", "hypen", "nbspace", "fwspace", "linesegarray", "lineseg"]
                    guard tokens.allSatisfy({ safe.contains($0.localName) }) else { throw HWPDocumentEditingError.unsupportedEdit }
                }
                var replacement = retained.contains(original.id) ? paragraph : ""
                for added in additions {
                    guard let originID = added.sourceParagraphID, let template = byID[originID],
                          let origin = oldByID[originID], nextID < UInt32.max else { throw HWPDocumentEditingError.staleDocument }
                    nextID += 1
                    let prefix = try HWPFormattingXML.prefix(template)
                    let paraStyle = try HWPFormattingXML.attribute(template, "paraPrIDRef") ?? "0"
                    let style = try HWPFormattingXML.attribute(template, "styleIDRef") ?? "0"
                    let run = try HWPFormattingXML.elements(template, name: "run").first?.xml ?? "<run/>"
                    let charStyle = try HWPFormattingXML.attribute(run, "charPrIDRef") ?? "0"
                    let content = HWPXParagraphXMLPatcher.encodedTextContent(origin.text, prefix: prefix)
                    replacement += "<\(prefix)p id=\"\(nextID)\" paraPrIDRef=\"\(HWPFormattingXML.escaped(paraStyle))\" styleIDRef=\"\(HWPFormattingXML.escaped(style))\" pageBreak=\"0\" columnBreak=\"0\" merged=\"0\"><\(prefix)run charPrIDRef=\"\(HWPFormattingXML.escaped(charStyle))\"><\(prefix)t xml:space=\"preserve\">\(content)</\(prefix)t></\(prefix)run></\(prefix)p>"
                }
                result = result.replacingCharacters(in: ranges[index], with: replacement) as NSString
            }
            let payload = Data((result as String).utf8)
            guard payload.count <= HWPXTextExtractor.maximumEntryBytes else { throw HWPDocumentEditingError.limitExceeded }
            replacements[section.path] = payload
        }
        let archive = try HWPXEditingArchive(data: package.sourceData)
        let base = try HWPXDocumentPackage.load(from: archive.repack(replacing: replacements))
        return try base.serializedData(applying: HWPParagraphEditing.rebased(edited, onto: base.blocks))
    }
}
