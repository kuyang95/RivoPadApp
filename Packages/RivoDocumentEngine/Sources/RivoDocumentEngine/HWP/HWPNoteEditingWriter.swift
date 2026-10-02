import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public nonisolated enum HWPNoteEditingWriter {
    public typealias Record = HWP5DocumentRewriter.Record
    private static let paragraphHeader: UInt32 = 0x42
    private static let paragraphText: UInt32 = 0x43
    private static let characterShape: UInt32 = 0x44
    private static let lineSegment: UInt32 = 0x45
    private static let controlHeader: UInt32 = 0x47
    private static let listHeader: UInt32 = 0x48
    private static let automaticNumberID: UInt32 = 0x6174_6E6F

    public static func applyHWPX(_ action: HWPNoteEditing.Action,
                          package: HWPXDocumentPackage) throws -> Data {
        var xmlByPath = Dictionary(uniqueKeysWithValues: package.sections.map { ($0.path, $0.xml) })
        switch action {
        case .insert(let kind, let rawText, let insertion):
            let text = try HWPNoteEditing.validatedText(rawText)
            guard let section = package.sections.first(where: { $0.path == insertion.sectionPath }),
                  let hostIndex = section.blocks.firstIndex(where: {
                      $0.id == insertion.blockID && $0.text == insertion.text && $0.region.kind == .body
                  }), HWPParagraphEditing.supports(section.blocks[hostIndex]) else {
                throw HWPDocumentEditingError.staleDocument
            }
            var xml = section.xml
            let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: xml)
            guard ranges.indices.contains(hostIndex) else { throw HWPDocumentEditingError.staleDocument }
            let source = (xml as NSString).substring(with: ranges[hostIndex])
            let marker = "\u{F8FF}\u{F8FE}\u{F8FD}"
            guard !source.contains(marker), insertion.caret <= insertion.text.utf16.count else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            let marked = (insertion.text as NSString).replacingCharacters(
                in: NSRange(location: insertion.caret, length: 0), with: marker)
            let edited = HWPTextRunEditing.replacingText(in: section.blocks[hostIndex], with: marked)
            var paragraph = try HWPXParagraphXMLPatcher.apply(
                originalXML: source, originalBlocks: [section.blocks[hostIndex]], editedBlocks: [edited])
            guard let markerRange = paragraph.range(of: marker) else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            let prefix = try HWPFormattingXML.prefix(paragraph)
            let paraID = HWPFormattingXML.escaped(try HWPFormattingXML.attribute(paragraph, "paraPrIDRef") ?? "0")
            let styleID = HWPFormattingXML.escaped(try HWPFormattingXML.attribute(paragraph, "styleIDRef") ?? "0")
            let run = try HWPFormattingXML.elements(paragraph, name: "run").first
            let charID = HWPFormattingXML.escaped(try run.flatMap {
                try HWPFormattingXML.attribute($0.xml, "charPrIDRef")
            } ?? "0")
            var nextID = try nextXMLID(package)
            guard nextID < UInt32.max - 2 else { throw HWPDocumentEditingError.limitExceeded }
            nextID += 1; let instance = nextID
            nextID += 1; let paragraphID = nextID
            let number = try noteNumber(before: ranges[hostIndex].location, kind: kind,
                                        sectionPath: section.path, package: package)
            let encoded = HWPXParagraphXMLPatcher.encodedTextContent(text, prefix: prefix)
            let note = "<\(prefix)ctrl><\(prefix)\(kind.rawValue) number=\"\(number)\" suffixChar=\"41\" instid=\"\(instance)\"><\(prefix)subList id=\"\" textDirection=\"HORIZONTAL\" lineWrap=\"BREAK\" vertAlign=\"TOP\" linkListIDRef=\"0\" linkListNextIDRef=\"0\" textWidth=\"0\" textHeight=\"0\" hasTextRef=\"0\" hasNumRef=\"0\"><\(prefix)p id=\"\(paragraphID)\" paraPrIDRef=\"\(paraID)\" styleIDRef=\"\(styleID)\" pageBreak=\"0\" columnBreak=\"0\" merged=\"0\"><\(prefix)run charPrIDRef=\"\(charID)\"><\(prefix)ctrl><\(prefix)autoNum num=\"\(number)\" numType=\"\(kind.xmlNumberType)\"><\(prefix)autoNumFormat type=\"DIGIT\" userChar=\"\" prefixChar=\"\" suffixChar=\")\" supscript=\"0\"/></\(prefix)autoNum></\(prefix)ctrl><\(prefix)t xml:space=\"preserve\">\(encoded)</\(prefix)t></\(prefix)run></\(prefix)p></\(prefix)subList></\(prefix)\(kind.rawValue)></\(prefix)ctrl>"
            let markerNS = NSRange(markerRange, in: paragraph)
            let replacement = "</\(prefix)t>\(note)<\(prefix)t xml:space=\"preserve\">"
            paragraph = (paragraph as NSString).replacingCharacters(in: markerNS, with: replacement)
            xml = (xml as NSString).replacingCharacters(in: ranges[hostIndex], with: paragraph)
            xmlByPath[section.path] = xml

        case .update(let note, let rawText):
            let text = try HWPNoteEditing.validatedText(rawText)
            guard var xml = xmlByPath[note.sectionPath] else { throw HWPDocumentEditingError.staleDocument }
            let element = try noteElement(note, xml: xml)
            let paragraphs = try HWPFormattingXML.elements(element.xml, name: "p")
            let texts = try HWPFormattingXML.elements(element.xml, name: "t")
            guard paragraphs.count == 1, texts.count == 1 else { throw HWPDocumentEditingError.unsupportedEdit }
            let prefix = try HWPFormattingXML.prefix(element.xml)
            let encoded = HWPXParagraphXMLPatcher.encodedTextContent(text, prefix: prefix)
            let replacement = try replacingElementContent(texts[0].xml, with: encoded)
            var changed = element.xml as NSString
            changed = changed.replacingCharacters(in: texts[0].range, with: replacement) as NSString
            xml = (xml as NSString).replacingCharacters(in: element.range, with: changed as String)
            xmlByPath[note.sectionPath] = xml

        case .delete(let note):
            guard var xml = xmlByPath[note.sectionPath] else { throw HWPDocumentEditingError.staleDocument }
            let element = try noteElement(note, xml: xml)
            let controls = try HWPFormattingXML.elements(xml, name: "ctrl").filter {
                $0.range.location <= element.range.location && NSMaxRange($0.range) >= NSMaxRange(element.range)
            }
            guard let owner = controls.min(by: { $0.range.length < $1.range.length }) else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            xml = (xml as NSString).replacingCharacters(in: owner.range, with: "")
            xmlByPath[note.sectionPath] = xml
        }

        var counters: [HWPNoteKind: Int] = [:]
        for section in package.sections {
            guard let source = xmlByPath[section.path] else { continue }
            let normalized = try renumberXML(source, counters: &counters)
            guard normalized.utf8.count <= HWPXTextExtractor.maximumEntryBytes else {
                throw HWPDocumentEditingError.limitExceeded
            }
            xmlByPath[section.path] = normalized
        }
        let replacements: [String: Data] = Dictionary(
            uniqueKeysWithValues: package.sections.compactMap { section -> (String, Data)? in
            guard let xml = xmlByPath[section.path], xml != section.xml else { return nil }
            return (section.path, Data(xml.utf8))
            }
        )
        let data = try HWPXEditingArchive(data: package.sourceData).repack(replacing: replacements)
        let saved = try HWPXDocumentPackage.load(from: data)
        try verify(action, before: package.blocks, after: saved.blocks)
        return data
    }

    private static func noteElement(_ note: HWPNoteEditing.Note, xml: String) throws -> HWPFormattingXML.Element {
        let elements = try HWPFormattingXML.elements(xml, name: note.kind.rawValue.lowercased())
        guard elements.indices.contains(note.index) else { throw HWPDocumentEditingError.staleDocument }
        let element = elements[note.index]
        let text = try HWPNoteXMLText.read(element.xml)
        guard text == note.text else { throw HWPDocumentEditingError.staleDocument }
        return element
    }

    private static func replacingElementContent(_ xml: String, with encoded: String) throws -> String {
        let tokens = try HWPXParagraphXMLPatcher.tagTokens(in: xml)
        guard let first = tokens.first else { throw HWPDocumentEditingError.invalidDocument }
        if first.isSelfClosing {
            let start = (xml as NSString).substring(with: first.range)
            return String(start.dropLast(2)) + ">" + encoded + "</\(first.qualifiedName)>"
        }
        guard let last = tokens.last(where: { $0.isClosing && $0.localName == first.localName }) else {
            throw HWPDocumentEditingError.invalidDocument
        }
        return (xml as NSString).replacingCharacters(
            in: NSRange(location: NSMaxRange(first.range), length: last.range.location - NSMaxRange(first.range)),
            with: encoded)
    }

    private static func noteNumber(before location: Int, kind: HWPNoteKind,
                                   sectionPath: String, package: HWPXDocumentPackage) throws -> Int {
        var count = 0
        for section in package.sections {
            if section.path == sectionPath {
                count += try HWPFormattingXML.elements(section.xml, name: kind.rawValue.lowercased())
                    .filter { $0.range.location < location }.count
                break
            }
            count += try HWPFormattingXML.elements(section.xml, name: kind.rawValue.lowercased()).count
        }
        return count + 1
    }

    private static func renumberXML(_ source: String,
                                    counters: inout [HWPNoteKind: Int]) throws -> String {
        var xml = source
        for kind in HWPNoteKind.allCases {
            let elements = try HWPFormattingXML.elements(xml, name: kind.rawValue.lowercased())
            counters[kind, default: 0] += elements.count
            let start = counters[kind, default: 0] - elements.count
            for (offset, element) in elements.enumerated().reversed() {
                let number = start + offset + 1
                var changed = try HWPFormattingXML.setAttribute(element.xml, "number", String(number))
                let automatic = try HWPFormattingXML.elements(changed, name: "autonum")
                    .first(where: { (try? HWPFormattingXML.attribute($0.xml, "numType")) == kind.xmlNumberType })
                if let automatic {
                    let updated = try HWPFormattingXML.setAttribute(automatic.xml, "num", String(number))
                    changed = (changed as NSString).replacingCharacters(in: automatic.range, with: updated)
                }
                xml = (xml as NSString).replacingCharacters(in: element.range, with: changed)
            }
        }
        return xml
    }

    private static func nextXMLID(_ package: HWPXDocumentPackage) throws -> UInt32 {
        var maximum: UInt32 = 0
        for section in package.sections {
            for token in try HWPXParagraphXMLPatcher.tagTokens(in: section.xml) where !token.isClosing {
                let tag = (section.xml as NSString).substring(with: token.range)
                for name in ["id", "instid", "instId"] {
                    if let value = try HWPFormattingXML.attribute(tag, name), let number = UInt32(value) {
                        maximum = max(maximum, number)
                    }
                }
            }
        }
        return maximum
    }

    public static func applyHWP(_ action: HWPNoteEditing.Action, data: Data,
                         blocks: [HWPDocumentBlock]) throws -> Data {
        let container = try OLECompoundFile(data: data)
        let flags = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36)
        guard flags & 0x6796 == 0 else { throw HWPDocumentEditingError.protectedDocument }
        let compressed = flags & 1 != 0
        let paths = container.streamNames.filter { $0.hasPrefix("bodytext/section") }
            .sorted { sectionIndex($0) < sectionIndex($1) }
        var recordsByPath: [String: [Record]] = [:]
        var paragraphIndexByPath: [String: [Int: Int]] = [:]
        var ordinal = 0, nextInstance: UInt32 = 0, nextParagraphID: UInt32 = 0
        for path in paths {
            let stored = try container.stream(named: path)
            let bytes = try compressed
                ? HWP5TextExtractor.inflateRawDeflate(stored, maximumBytes: HWP5TextExtractor.maximumSectionBytes)
                : stored
            let records = try HWP5DocumentRewriter.parseRecords(bytes)
            recordsByPath[path] = records
            var map: [Int: Int] = [:]
            for index in records.indices where records[index].tag == paragraphHeader {
                map[ordinal] = index
                if records[index].payload.count >= 22 {
                    nextParagraphID = max(nextParagraphID, try records[index].payload.hwpWriterUInt32(at: 18))
                }
                ordinal += 1
            }
            paragraphIndexByPath[path] = map
            for record in records where record.tag == controlHeader && record.payload.count >= 8 {
                nextInstance = max(nextInstance, try record.payload.hwpWriterUInt32(at: 4))
            }
        }
        let targetPath: String
        let targetOrdinal: Int
        switch action {
        case .insert(_, _, let insertion):
            guard let block = blocks.first(where: {
                $0.id == insertion.blockID && $0.text == insertion.text && $0.sectionPath == insertion.sectionPath
            }), block.isEditable else { throw HWPDocumentEditingError.staleDocument }
            targetPath = block.sectionPath.lowercased(); targetOrdinal = block.paragraphIndex
        case .update(let note, _), .delete(let note):
            guard let block = blocks.first(where: {
                $0.id == note.blockID && $0.text == note.text && $0.sectionPath == note.sectionPath
                    && $0.region.kind == note.kind.region
            }) else { throw HWPDocumentEditingError.staleDocument }
            targetPath = block.sectionPath.lowercased(); targetOrdinal = block.paragraphIndex
        }
        guard let actualPath = paths.first(where: { $0.lowercased() == targetPath }),
              var records = recordsByPath[actualPath],
              let targetRecord = paragraphIndexByPath[actualPath]?[targetOrdinal] else {
            throw HWPDocumentEditingError.staleDocument
        }

        switch action {
        case .insert(let kind, let rawText, let insertion):
            let text = try HWPNoteEditing.validatedText(rawText)
            guard nextInstance < UInt32.max, nextParagraphID < UInt32.max else {
                throw HWPDocumentEditingError.limitExceeded
            }
            let ownerLevel = records[targetRecord].level
            let ownerEnd = paragraphEnd(records, header: targetRecord)
            let templateShape = try firstCharacterShape(records, header: targetRecord, end: ownerEnd)
            _ = try insertAnchor(kind.controlID, caret: insertion.caret,
                                 records: &records, header: targetRecord, end: ownerEnd)
            nextInstance += 1; nextParagraphID += 1
            let number = countNotes(beforePath: actualPath, beforeRecord: ownerEnd,
                                    kind: kind, paths: paths, recordsByPath: recordsByPath) + 1
            let inserted = try noteRecords(kind: kind, text: text, number: number,
                                           instance: nextInstance, paragraphID: nextParagraphID,
                                           level: ownerLevel, templateHeader: records[targetRecord].payload,
                                           templateShape: templateShape)
            records.insert(contentsOf: inserted, at: paragraphEnd(records, header: targetRecord))

        case .update(let note, let rawText):
            let text = try HWPNoteEditing.validatedText(rawText)
            let context = try noteContext(records, paragraphHeaderIndex: targetRecord, kind: note.kind)
            try rewriteNoteText(text, kind: note.kind, number: note.index + 1,
                                records: &records, context: context)

        case .delete(let note):
            let context = try noteContext(records, paragraphHeaderIndex: targetRecord, kind: note.kind)
            try removeAnchor(note.kind.controlID, sibling: context.siblingIndex,
                             records: &records, header: context.ownerHeader, end: context.controlEnd)
            records.removeSubrange(context.control..<context.controlEnd)
        }
        recordsByPath[actualPath] = records

        var counters: [HWPNoteKind: Int] = [:]
        for path in paths {
            guard var section = recordsByPath[path] else { continue }
            try renumberHWP(&section, counters: &counters)
            recordsByPath[path] = section
        }
        var replacements: [String: Data] = [:]
        for path in paths {
            guard let section = recordsByPath[path] else { continue }
            let bytes = section.reduce(into: Data()) { $0.append($1.serialized()) }
            guard bytes.count <= HWP5TextExtractor.maximumSectionBytes else {
                throw HWPDocumentEditingError.limitExceeded
            }
            replacements[path] = try compressed ? HWP5DocumentRewriter.rawDeflate(bytes) : bytes
        }
        let result = try container.serialized(replacing: replacements)
        let saved = try HWP5StructuredDocumentParser.parse(from: result)
        try verify(action, before: blocks, after: saved.blocks)
        return result
    }

    private struct HWPContext {
        let control: Int, controlEnd: Int, ownerHeader: Int
        let paragraphHeader: Int, paragraphEnd: Int, siblingIndex: Int
    }

    private static func noteContext(_ records: [Record], paragraphHeaderIndex: Int,
                                    kind: HWPNoteKind) throws -> HWPContext {
        let paragraphLevel = records[paragraphHeaderIndex].level
        guard let control = records.indices.prefix(paragraphHeaderIndex).reversed().first(where: { index in
            guard records[index].tag == controlHeader, records[index].level < paragraphLevel,
                  records[index].payload.count >= 4,
                  (try? records[index].payload.hwpWriterUInt32(at: 0)) == kind.controlID else { return false }
            let end = records.indices.dropFirst(index + 1).first { records[$0].level <= records[index].level }
                ?? records.endIndex
            return paragraphHeaderIndex < end
        }) else { throw HWPDocumentEditingError.unsupportedEdit }
        let controlLevel = records[control].level
        let controlEnd = records.indices.dropFirst(control + 1).first { records[$0].level <= controlLevel }
            ?? records.endIndex
        let nested = records.indices[control..<controlEnd].filter {
            records[$0].tag == paragraphHeader && records[$0].level == controlLevel + 1
        }
        guard nested == [paragraphHeaderIndex],
              let owner = records.indices.prefix(control).reversed().first(where: {
                  records[$0].tag == paragraphHeader && records[$0].level + 1 == controlLevel
              }) else { throw HWPDocumentEditingError.unsupportedEdit }
        let sibling = records.indices[owner..<control].filter {
            records[$0].tag == controlHeader && records[$0].level == controlLevel
                && records[$0].payload.count >= 4
                && (try? records[$0].payload.hwpWriterUInt32(at: 0)) == kind.controlID
        }.count
        return HWPContext(control: control, controlEnd: controlEnd, ownerHeader: owner,
                          paragraphHeader: paragraphHeaderIndex,
                          paragraphEnd: paragraphEnd(records, header: paragraphHeaderIndex),
                          siblingIndex: sibling)
    }

    private static func paragraphEnd(_ records: [Record], header: Int) -> Int {
        let level = records[header].level
        return records.indices.dropFirst(header + 1).first {
            records[$0].tag == paragraphHeader && records[$0].level <= level
        } ?? records.endIndex
    }

    private static func firstCharacterShape(_ records: [Record], header: Int, end: Int) throws -> Data {
        let level = records[header].level + 1
        if let index = records.indices[header..<end].first(where: {
            records[$0].tag == characterShape && records[$0].level == level && records[$0].payload.count >= 8
        }) { return Data(records[index].payload.prefix(8)) }
        var shape = Data(); shape.hwpWriterAppendUInt32(0); shape.hwpWriterAppendUInt32(0)
        return shape
    }

    private static func noteRecords(kind: HWPNoteKind, text: String, number: Int,
                                    instance: UInt32, paragraphID: UInt32, level: UInt32,
                                    templateHeader: Data, templateShape: Data) throws -> [Record] {
        guard templateHeader.count >= 22, templateShape.count >= 8,
              number <= Int(UInt16.max) else { throw HWPDocumentEditingError.limitExceeded }
        var control = Data(); control.hwpWriterAppendUInt32(kind.controlID)
        control.hwpWriterAppendUInt32(instance); control.hwpWriterAppendUInt32(0x0029_0000)
        control.hwpWriterAppendUInt32(0)
        var list = Data(); list.hwpWriterAppendUInt32(1); list.hwpWriterAppendUInt32(0)
        let payload = try noteText(text)
        var header = templateHeader
        header.hwpWriterSetUInt32(0x8000_0000 | UInt32(payload.count / 2), at: 0)
        header.hwpWriterSetUInt32(1 << 18, at: 4)
        header[11] = 0
        header.hwpWriterSetUInt16(1, at: 12); header.hwpWriterSetUInt16(0, at: 14)
        header.hwpWriterSetUInt16(0, at: 16); header.hwpWriterSetUInt32(paragraphID, at: 18)
        var shape = Data(templateShape.prefix(8)); shape.hwpWriterSetUInt32(0, at: 0)
        var automatic = Data(); automatic.hwpWriterAppendUInt32(automaticNumberID)
        automatic.hwpWriterAppendUInt32(kind.automaticNumberType)
        automatic.hwpWriterAppendUInt16(UInt16(number)); automatic.hwpWriterAppendUInt16(0)
        automatic.hwpWriterAppendUInt16(0); automatic.hwpWriterAppendUInt16(0x29)
        return [
            .init(tag: controlHeader, level: level + 1, payload: control),
            .init(tag: listHeader, level: level + 2, payload: list),
            .init(tag: paragraphHeader, level: level + 2, payload: header),
            .init(tag: paragraphText, level: level + 3, payload: payload),
            .init(tag: characterShape, level: level + 3, payload: shape),
            .init(tag: controlHeader, level: level + 3, payload: automatic)
        ]
    }

    private static func noteText(_ text: String) throws -> Data {
        var units: [UInt16] = [18, 0x6E6F, 0x6174, 0, 0, 0, 0, 18]
        for unit in text.utf16 {
            if unit == 9 { units += [9, 0, 0, 0, 0, 0, 0, 9] }
            else if unit == 10 { units.append(10) }
            else { units.append(unit) }
        }
        units.append(13)
        guard units.count * 2 <= HWP5TextExtractor.maximumSectionBytes else {
            throw HWPDocumentEditingError.limitExceeded
        }
        var data = Data(); for unit in units { data.hwpWriterAppendUInt16(unit) }
        return data
    }

    private static func rewriteNoteText(_ text: String, kind: HWPNoteKind, number: Int,
                                        records: inout [Record], context: HWPContext) throws {
        let level = records[context.paragraphHeader].level + 1
        guard let textIndex = records.indices[context.paragraphHeader..<context.paragraphEnd].first(where: {
            records[$0].tag == paragraphText && records[$0].level == level
        }) else { throw HWPDocumentEditingError.unsupportedEdit }
        let payload = try noteText(text)
        records[textIndex].payload = payload
        var header = records[context.paragraphHeader].payload
        header.hwpWriterSetUInt32(0x8000_0000 | UInt32(payload.count / 2), at: 0)
        header.hwpWriterSetUInt32(1 << 18, at: 4); header.hwpWriterSetUInt16(0, at: 16)
        records[context.paragraphHeader].payload = header
        if let shape = records.indices[context.paragraphHeader..<context.paragraphEnd].first(where: {
            records[$0].tag == characterShape && records[$0].level == level
        }) { records[shape].payload = Data(records[shape].payload.prefix(8)) }
        if let automatic = records.indices[context.paragraphHeader..<min(context.paragraphEnd, records.count)].first(where: {
            records[$0].tag == controlHeader && records[$0].level == level
                && records[$0].payload.count >= 10
                && (try? records[$0].payload.hwpWriterUInt32(at: 0)) == automaticNumberID
        }) { records[automatic].payload.hwpWriterSetUInt16(UInt16(number), at: 8) }
        let lineIndices = records.indices[context.paragraphHeader..<min(context.paragraphEnd, records.count)].filter {
            records[$0].tag == lineSegment && records[$0].level == level
        }
        for index in lineIndices.reversed() { records.remove(at: index) }
    }

    private static func insertAnchor(_ identifier: UInt32, caret: Int, records: inout [Record],
                                     header: Int, end: Int) throws -> Int {
        let level = records[header].level + 1
        let anchor: [UInt16] = [17, UInt16(identifier & 0xFFFF), UInt16(identifier >> 16), 0, 0, 0, 0, 17]
        guard let textIndex = records.indices[header..<end].first(where: {
            records[$0].tag == paragraphText && records[$0].level == level
        }) else {
            let count = try records[header].payload.hwpWriterUInt32(at: 0) & 0x7FFF_FFFF
            guard caret == 0, count <= 1 else { throw HWPDocumentEditingError.unsupportedEdit }
            records.insert(.init(tag: paragraphText, level: level, payload: data(anchor + [13])),
                           at: header + 1)
            try repairOwner(records: &records, header: header, end: end + 1,
                            removed: nil, insertedAt: nil)
            return 0
        }
        var units = try units(records[textIndex].payload)
        let raw = try rawPosition(units, visible: caret)
        units.insert(contentsOf: anchor, at: raw)
        records[textIndex].payload = data(units)
        try repairOwner(records: &records, header: header, end: end, removed: nil, insertedAt: raw)
        return raw
    }

    private static func removeAnchor(_ identifier: UInt32, sibling: Int, records: inout [Record],
                                     header: Int, end: Int) throws {
        let level = records[header].level + 1
        guard let textIndex = records.indices[header..<end].first(where: {
            records[$0].tag == paragraphText && records[$0].level == level
        }) else { throw HWPDocumentEditingError.unsupportedEdit }
        var units = try units(records[textIndex].payload), cursor = 0, match = 0, found: Int?
        while cursor < units.count {
            let code = units[cursor], size = controlSize(code)
            guard cursor + size <= units.count else { throw HWPDocumentEditingError.invalidDocument }
            if code == 17, size == 8 {
                let value = UInt32(units[cursor + 1]) | UInt32(units[cursor + 2]) << 16
                if value == identifier {
                    if match == sibling { found = cursor; break }
                    match += 1
                }
            }
            cursor += size
        }
        guard let found else { throw HWPDocumentEditingError.unsupportedEdit }
        units.removeSubrange(found..<(found + 8)); records[textIndex].payload = data(units)
        try repairOwner(records: &records, header: header, end: end, removed: found, insertedAt: nil)
    }

    private static func repairOwner(records: inout [Record], header: Int, end: Int,
                                    removed: Int?, insertedAt: Int?) throws {
        let level = records[header].level + 1
        guard let text = records.indices[header..<min(end, records.count)].first(where: {
            records[$0].tag == paragraphText && records[$0].level == level
        }) else { throw HWPDocumentEditingError.unsupportedEdit }
        let textUnits = try units(records[text].payload)
        var head = records[header].payload
        let high = try head.hwpWriterUInt32(at: 0) & 0x8000_0000
        head.hwpWriterSetUInt32(high | UInt32(textUnits.count), at: 0)
        var mask: UInt32 = 0, cursor = 0
        while cursor < textUnits.count {
            let code = textUnits[cursor], size = controlSize(code)
            if code > 0 && code < 32 && code != 13 { mask |= 1 << UInt32(code) }
            cursor += size
        }
        head.hwpWriterSetUInt32(mask, at: 4)
        for index in records.indices[header..<min(end, records.count)] where records[index].level == level {
            if records[index].tag == characterShape {
                let stride = 8
                guard records[index].payload.count.isMultiple(of: stride) else {
                    throw HWPDocumentEditingError.invalidDocument
                }
                var entries: [Data] = []
                for offset in Swift.stride(from: 0, to: records[index].payload.count, by: stride) {
                    var entry = records[index].payload.subdata(in: offset..<(offset + stride))
                    var position = Int(try entry.hwpWriterUInt32(at: 0))
                    if let insertedAt, position > insertedAt { position += 8 }
                    if let removed {
                        position = position <= removed ? position : position < removed + 8 ? removed : position - 8
                    }
                    entry.hwpWriterSetUInt32(UInt32(position), at: 0)
                    if entries.last.flatMap({ try? $0.hwpWriterUInt32(at: 0) }) == UInt32(position) { entries.removeLast() }
                    entries.append(entry)
                }
                records[index].payload = entries.reduce(into: Data()) { $0.append($1) }
                head.hwpWriterSetUInt16(UInt16(entries.count), at: 12)
            }
        }
        for index in records.indices[header..<min(end, records.count)] where
            records[index].tag == lineSegment && records[index].level == level {
            guard records[index].payload.count.isMultiple(of: 36) else {
                throw HWPDocumentEditingError.invalidDocument
            }
            var payload = records[index].payload
            for offset in Swift.stride(from: 0, to: payload.count, by: 36) {
                var position = Int(try payload.hwpWriterUInt32(at: offset))
                if let insertedAt, position > insertedAt { position += 8 }
                if let removed {
                    position = position <= removed ? position : position < removed + 8 ? removed : position - 8
                }
                payload.hwpWriterSetUInt32(UInt32(position), at: offset)
            }
            records[index].payload = payload
        }
        records[header].payload = head
    }

    private static func rawPosition(_ units: [UInt16], visible target: Int) throws -> Int {
        var raw = 0, visible = 0
        while raw < units.count {
            if visible == target { return raw }
            let code = units[raw], size = controlSize(code)
            guard raw + size <= units.count else { throw HWPDocumentEditingError.invalidDocument }
            if code > 31 || [9, 10, 24, 30, 31].contains(code) { visible += 1 }
            raw += size
        }
        guard visible == target else { throw HWPDocumentEditingError.staleDocument }
        return raw
    }

    private static func controlSize(_ code: UInt16) -> Int {
        (1...23).contains(code) && code != 10 && code != 13 ? 8 : 1
    }
    private static func units(_ payload: Data) throws -> [UInt16] {
        guard payload.count.isMultiple(of: 2) else { throw HWPDocumentEditingError.invalidDocument }
        return stride(from: 0, to: payload.count, by: 2).map {
            UInt16(payload[$0]) | UInt16(payload[$0 + 1]) << 8
        }
    }
    private static func data(_ units: [UInt16]) -> Data {
        var result = Data(); for unit in units { result.hwpWriterAppendUInt16(unit) }; return result
    }

    private static func countNotes(beforePath: String, beforeRecord: Int, kind: HWPNoteKind,
                                   paths: [String], recordsByPath: [String: [Record]]) -> Int {
        var count = 0
        for path in paths {
            guard let records = recordsByPath[path] else { continue }
            if path == beforePath {
                count += records.indices.prefix(beforeRecord).filter {
                    records[$0].tag == controlHeader && records[$0].payload.count >= 4
                        && (try? records[$0].payload.hwpWriterUInt32(at: 0)) == kind.controlID
                }.count
                break
            }
            count += records.filter {
                $0.tag == controlHeader && $0.payload.count >= 4
                    && (try? $0.payload.hwpWriterUInt32(at: 0)) == kind.controlID
            }.count
        }
        return count
    }

    private static func renumberHWP(_ records: inout [Record],
                                    counters: inout [HWPNoteKind: Int]) throws {
        for index in records.indices where records[index].tag == controlHeader
            && records[index].payload.count >= 4 {
            guard let kind = HWPNoteKind.allCases.first(where: {
                (try? records[index].payload.hwpWriterUInt32(at: 0)) == $0.controlID
            }) else { continue }
            counters[kind, default: 0] += 1
            let level = records[index].level
            let end = records.indices.dropFirst(index + 1).first { records[$0].level <= level } ?? records.endIndex
            if let automatic = records.indices[index..<end].first(where: {
                records[$0].tag == controlHeader && records[$0].payload.count >= 10
                    && (try? records[$0].payload.hwpWriterUInt32(at: 0)) == automaticNumberID
            }) {
                records[automatic].payload.hwpWriterSetUInt16(UInt16(counters[kind]!), at: 8)
            }
        }
    }

    private static func verify(_ action: HWPNoteEditing.Action,
                               before: [HWPDocumentBlock], after: [HWPDocumentBlock]) throws {
        let oldNotes = before.filter { $0.region.kind == .footnote || $0.region.kind == .endnote }
        let newNotes = after.filter { $0.region.kind == .footnote || $0.region.kind == .endnote }
        switch action {
        case .insert(let kind, let text, _):
            guard newNotes.count == oldNotes.count + 1,
                  newNotes.filter({ $0.region.kind == kind.region }).contains(where: { $0.text == text }) else {
                throw HWPDocumentEditingError.cannotSave
            }
        case .update(let note, let text):
            guard newNotes.count == oldNotes.count,
                  newNotes.filter({ $0.region.kind == note.kind.region }).contains(where: { $0.text == text }) else {
                throw HWPDocumentEditingError.cannotSave
            }
        case .delete:
            guard newNotes.count + 1 == oldNotes.count else { throw HWPDocumentEditingError.cannotSave }
        }
    }

    private static func sectionIndex(_ path: String) -> Int {
        Int(path.lowercased().components(separatedBy: "section").last ?? "") ?? .max
    }
}

private nonisolated final class HWPNoteXMLText: NSObject, XMLParserDelegate {
    private var value = "", depth = 0

    static func read(_ xml: String) throws -> String {
        let wrapped = "<root xmlns:hp=\"urn:hancom:hwpml:paragraph\">\(xml)</root>"
        let reader = HWPNoteXMLText()
        let parser = XMLParser(data: Data(wrapped.utf8))
        parser.delegate = reader
        parser.shouldProcessNamespaces = true
        guard parser.parse() else { throw HWPDocumentEditingError.invalidDocument }
        return reader.value
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let name = String((qName ?? elementName).split(separator: ":").last ?? "").lowercased()
        if name == "t" { depth += 1 }
        else if depth > 0, name == "tab" { value += "\t" }
        else if depth > 0, name == "linebreak" { value += "\n" }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let name = String((qName ?? elementName).split(separator: ":").last ?? "").lowercased()
        if name == "t", depth > 0 { depth -= 1 }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if depth > 0 { value += string }
    }
}
