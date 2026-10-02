import Foundation

/// Reorders, inserts and removes direct paragraphs inside an existing text box.
/// Retained paragraph XML/records are moved as a unit so tables, shapes and
/// equations anchored inside them remain byte-for-byte intact.
public nonisolated enum HWPTextBoxStructureWriter {
    public typealias Record = HWP5DocumentRewriter.Record

    public static func apply(_ paragraphs: [HWPTextBoxEditing.Paragraph],
                      target: HWPTextBoxEditing.Target,
                      to source: HWPTableStructureDocument) throws -> Data {
        switch source {
        case .hwpx(let package): return try applyHWPX(paragraphs, target: target, package: package)
        case .hwp(_, let data): return try applyHWP(paragraphs, target: target, data: data)
        }
    }

    private static let textContainerNames = ["rect", "ellipse", "polygon", "container"]

    private static func applyHWPX(_ paragraphs: [HWPTextBoxEditing.Paragraph],
                                  target: HWPTextBoxEditing.Target,
                                  package: HWPXDocumentPackage) throws -> Data {
        guard let owner = package.blocks.first(where: { $0.id == target.ownerID }),
              let section = package.sections.first(where: { $0.path == owner.sectionPath }),
              let paragraphIndex = section.blocks.firstIndex(where: { $0.id == owner.id }),
              let objectIndex = owner.canvasObjects.firstIndex(where: { $0.id == target.objectID }) else {
            throw HWPDocumentEditingError.staleDocument
        }
        let textObjectOrdinal = owner.canvasObjects[..<objectIndex].filter { $0.textContainerID != nil }.count
        let ownerRanges = try HWPXParagraphXMLPatcher.paragraphRanges(in: section.xml)
        guard ownerRanges.indices.contains(paragraphIndex) else { throw HWPDocumentEditingError.staleDocument }
        let ownerXML = (section.xml as NSString).substring(with: ownerRanges[paragraphIndex])
        let candidates = try textContainerNames.flatMap { try HWPFormattingXML.elements(ownerXML, name: $0) }
            .filter { (try? HWPFormattingXML.elements($0.xml, name: "sublist").isEmpty) == false }
            .sorted { $0.range.location < $1.range.location }
        guard candidates.indices.contains(textObjectOrdinal) else { throw HWPDocumentEditingError.staleDocument }
        let container = candidates[textObjectOrdinal]
        guard let subList = try HWPFormattingXML.elements(container.xml, name: "sublist").first else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        let paragraphElements = try directParagraphs(in: subList.xml)
        guard paragraphElements.count == target.entries.count, !paragraphElements.isEmpty else {
            throw HWPDocumentEditingError.staleDocument
        }
        let sourceXML = Dictionary(uniqueKeysWithValues: zip(target.entries.map(\.id), paragraphElements.map(\.xml)))
        var nextID = try nextObjectID(package)
        let template = paragraphElements[0].xml
        let replacements = try paragraphs.map { paragraph -> String in
            if let sourceID = paragraph.sourceID, let xml = sourceXML[sourceID] { return xml }
            defer { nextID &+= 1 }
            return try newHWPXParagraph(text: paragraph.text, template: template, id: nextID)
        }.joined()
        let first = paragraphElements[0].range
        let last = paragraphElements[paragraphElements.count - 1].range
        let directRange = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        let updatedSubList = (subList.xml as NSString).replacingCharacters(in: directRange, with: replacements)
        let updatedContainer = (container.xml as NSString).replacingCharacters(in: subList.range, with: updatedSubList)
        let updatedOwner = (ownerXML as NSString).replacingCharacters(in: container.range, with: updatedContainer)
        let updatedSection = (section.xml as NSString).replacingCharacters(in: ownerRanges[paragraphIndex], with: updatedOwner)
        return try HWPXEditingArchive(data: package.sourceData).repack(replacing: [section.path: Data(updatedSection.utf8)])
    }

    private static func directParagraphs(in xml: String) throws -> [HWPFormattingXML.Element] {
        let all = try HWPFormattingXML.elements(xml, name: "p")
        return all.filter { candidate in
            !all.contains { other in
                other.range.location < candidate.range.location
                    && NSMaxRange(other.range) > NSMaxRange(candidate.range)
            }
        }
    }

    private static func newHWPXParagraph(text: String, template: String, id: UInt32) throws -> String {
        let prefix = try HWPFormattingXML.prefix(template)
        let paraID = HWPFormattingXML.escaped(try HWPFormattingXML.attribute(template, "paraPrIDRef") ?? "0")
        let styleID = HWPFormattingXML.escaped(try HWPFormattingXML.attribute(template, "styleIDRef") ?? "0")
        let run = try HWPFormattingXML.elements(template, name: "run").first?.xml
        let charID = HWPFormattingXML.escaped(try run.flatMap { try HWPFormattingXML.attribute($0, "charPrIDRef") } ?? "0")
        let encoded = HWPXParagraphXMLPatcher.encodedTextContent(text, prefix: prefix)
        return "<\(prefix)p id=\"\(id)\" paraPrIDRef=\"\(paraID)\" styleIDRef=\"\(styleID)\" pageBreak=\"0\" columnBreak=\"0\" merged=\"0\"><\(prefix)run charPrIDRef=\"\(charID)\"><\(prefix)t xml:space=\"preserve\">\(encoded)</\(prefix)t></\(prefix)run></\(prefix)p>"
    }

    private static func nextObjectID(_ package: HWPXDocumentPackage) throws -> UInt32 {
        var maximum: UInt32 = 0
        for section in package.sections {
            for token in try HWPXParagraphXMLPatcher.tagTokens(in: section.xml) where !token.isClosing {
                let opening = (section.xml as NSString).substring(with: token.range)
                maximum = max(maximum, UInt32(try HWPFormattingXML.attribute(opening, "id") ?? "0") ?? 0)
            }
        }
        guard maximum < UInt32.max else { throw HWPDocumentEditingError.limitExceeded }
        return maximum + 1
    }

    private static func applyHWP(_ paragraphs: [HWPTextBoxEditing.Paragraph],
                                 target: HWPTextBoxEditing.Target, data: Data) throws -> Data {
        let container = try OLECompoundFile(data: data)
        let flags = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36)
        guard flags & 0x6796 == 0 else { throw HWPDocumentEditingError.protectedDocument }
        let compressed = flags & 1 != 0
        let locations = try paragraphLocations(container: container, compressed: compressed,
            ordinals: Set(target.entries.map(\.paragraphIndex)))
        guard let path = target.entries.first.flatMap({ locations[$0.paragraphIndex]?.path }),
              target.entries.allSatisfy({ locations[$0.paragraphIndex]?.path == path }) else {
            throw HWPDocumentEditingError.staleDocument
        }
        var records = try HWP5DocumentRewriter.parseRecords(expanded(container.stream(named: path), compressed: compressed))
        let ranges = try target.entries.map { entry -> Range<Int> in
            guard let start = locations[entry.paragraphIndex]?.record else { throw HWPDocumentEditingError.staleDocument }
            let level = records[start].level
            let end = records.indices.dropFirst(start + 1).first { records[$0].level <= level } ?? records.endIndex
            return start..<end
        }
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        guard zip(sorted, sorted.dropFirst()).allSatisfy({ pair in
            pair.0.upperBound == pair.1.lowerBound
        }) else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        let groups = Dictionary(uniqueKeysWithValues: zip(target.entries.map(\.id), ranges.map { Array(records[$0]) }))
        guard let template = ranges.first.map({ Array(records[$0]) }) else { throw HWPDocumentEditingError.staleDocument }
        var nextID = records.filter { $0.tag == 0x42 && $0.payload.count >= 22 }.compactMap {
            try? $0.payload.hwpWriterUInt32(at: 18)
        }.max() ?? 0
        guard nextID < UInt32.max else { throw HWPDocumentEditingError.limitExceeded }
        var replacement: [Record] = []
        for paragraph in paragraphs {
            if let sourceID = paragraph.sourceID, let group = groups[sourceID] { replacement.append(contentsOf: group) }
            else {
                nextID &+= 1
                replacement.append(contentsOf: try newHWPParagraph(text: paragraph.text,
                    template: template, paragraphID: nextID))
            }
        }
        records.replaceSubrange(sorted[0].lowerBound..<sorted[sorted.count - 1].upperBound, with: replacement)
        let stream = try encoded(records, compressed: compressed)
        return try container.serialized(replacing: [path: stream])
    }

    private struct ParagraphLocation { let path: String; let record: Int }

    private static func paragraphLocations(container: OLECompoundFile, compressed: Bool,
                                           ordinals: Set<Int>) throws -> [Int: ParagraphLocation] {
        let paths = container.streamNames.filter { $0.hasPrefix("bodytext/section") }
            .sorted { (HWPPageSetup.sectionIndex($0) ?? 0) < (HWPPageSetup.sectionIndex($1) ?? 0) }
        var ordinal = 0, result: [Int: ParagraphLocation] = [:]
        for path in paths {
            let records = try HWP5DocumentRewriter.parseRecords(expanded(container.stream(named: path), compressed: compressed))
            for (index, record) in records.enumerated() where record.tag == 0x42 {
                if ordinals.contains(ordinal) { result[ordinal] = ParagraphLocation(path: path, record: index) }
                ordinal += 1
            }
        }
        guard result.count == ordinals.count else { throw HWPDocumentEditingError.staleDocument }
        return result
    }

    private static func newHWPParagraph(text: String, template: [Record],
                                        paragraphID: UInt32) throws -> [Record] {
        guard let sourceHeader = template.first(where: { $0.tag == 0x42 }), sourceHeader.payload.count >= 22 else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        var textData = Data()
        for unit in text.utf16 {
            if unit == 9 {
                for value in [UInt16](arrayLiteral: 9, 0, 0, 0, 0, 0, 0, 9) { textData.hwpWriterAppendUInt16(value) }
            } else if unit == 10 { textData.hwpWriterAppendUInt16(10) }
            else if unit < 32 { throw HWPDocumentEditingError.unsupportedEdit }
            else { textData.hwpWriterAppendUInt16(unit) }
        }
        textData.hwpWriterAppendUInt16(13)
        var header = sourceHeader.payload
        let high = try header.hwpWriterUInt32(at: 0) & 0x8000_0000
        header.hwpWriterSetUInt32(high | UInt32(textData.count / 2), at: 0)
        var mask: UInt32 = 0
        if text.contains("\t") { mask |= 1 << 9 }
        if text.contains("\n") { mask |= 1 << 10 }
        header.hwpWriterSetUInt32(mask, at: 4)
        header[11] = 0
        header.hwpWriterSetUInt16(1, at: 12)
        header.hwpWriterSetUInt16(0, at: 14)
        header.hwpWriterSetUInt16(0, at: 16)
        header.hwpWriterSetUInt32(paragraphID, at: 18)
        let charShape = template.first(where: { $0.tag == 0x44 && $0.payload.count >= 8 })
            .flatMap { try? $0.payload.hwpWriterUInt32(at: 4) } ?? 0
        var character = Data()
        character.hwpWriterAppendUInt32(0)
        character.hwpWriterAppendUInt32(charShape)
        return [Record(tag: 0x42, level: sourceHeader.level, payload: header),
                Record(tag: 0x43, level: sourceHeader.level + 1, payload: textData),
                Record(tag: 0x44, level: sourceHeader.level + 1, payload: character)]
    }

    private static func expanded(_ data: Data, compressed: Bool) throws -> Data {
        try compressed ? HWP5TextExtractor.inflateRawDeflate(data,
            maximumBytes: HWP5TextExtractor.maximumSectionBytes) : data
    }

    private static func encoded(_ records: [Record], compressed: Bool) throws -> Data {
        let bytes = records.reduce(into: Data()) { $0.append($1.serialized()) }
        guard bytes.count <= HWP5TextExtractor.maximumSectionBytes else { throw HWPDocumentEditingError.limitExceeded }
        return try compressed ? HWP5DocumentRewriter.rawDeflate(bytes) : bytes
    }
}
