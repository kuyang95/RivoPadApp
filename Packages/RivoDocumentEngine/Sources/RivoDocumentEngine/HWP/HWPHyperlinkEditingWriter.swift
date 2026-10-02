import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public nonisolated enum HWPHyperlinkEditingWriter {
    public typealias Record = HWP5DocumentRewriter.Record

    public static func applyHWP(to data: Data, originals: [HWPDocumentBlock], edited: [HWPDocumentBlock]) throws -> Data {
        let desired = Dictionary(uniqueKeysWithValues: zip(originals, edited).compactMap { before, after in
            let oldSpans = HWPHyperlinkEditing.spans(in: before), newSpans = HWPHyperlinkEditing.spans(in: after)
            return oldSpans == newSpans ? nil : (after.paragraphIndex, after)
        })
        guard !desired.isEmpty else { return data }
        let container = try OLECompoundFile(data: data)
        let header = try container.stream(named: "FileHeader")
        let compressed = try header.hwpWriterUInt32(at: 36) & 1 != 0
        let paths = container.streamNames.filter { $0.hasPrefix("bodytext/section") }
            .sorted { (Int($0.dropFirst(16)) ?? 0) < (Int($1.dropFirst(16)) ?? 0) }
        var replacements: [String: Data] = [:], ordinal = 0, applied: Set<Int> = []
        for path in paths {
            let stored = try container.stream(named: path)
            let expanded = try compressed
                ? HWP5TextExtractor.inflateRawDeflate(stored, maximumBytes: HWP5TextExtractor.maximumSectionBytes)
                : stored
            let sourceRecords = try HWP5DocumentRewriter.parseRecords(expanded)
            var output: [Record] = [], index = 0, changed = false
            while index < sourceRecords.count {
                guard sourceRecords[index].tag == 0x42 else { output.append(sourceRecords[index]); index += 1; continue }
                var end = index + 1
                while end < sourceRecords.count, sourceRecords[end].tag != 0x42 { end += 1 }
                let paragraphIndex = ordinal; ordinal += 1
                guard let block = desired[paragraphIndex] else {
                    output.append(contentsOf: sourceRecords[index..<end]); index = end; continue
                }
                let rewritten = try rewriteHWPParagraph(Array(sourceRecords[index..<end]), desired: block)
                output.append(contentsOf: rewritten); applied.insert(paragraphIndex); changed = true; index = end
            }
            if changed {
                let payload = output.reduce(into: Data()) { $0.append($1.serialized()) }
                replacements[path] = try compressed ? HWP5DocumentRewriter.rawDeflate(payload) : payload
            }
        }
        guard applied == Set(desired.keys) else { throw HWPDocumentEditingError.staleDocument }
        let result = try container.serialized(replacing: replacements)
        let saved = try HWP5StructuredDocumentParser.parse(from: result)
        for block in saved.blocks {
            if let expected = desired[block.paragraphIndex],
               HWPHyperlinkEditing.spans(in: block) != HWPHyperlinkEditing.spans(in: expected) {
                throw HWPDocumentEditingError.cannotSave
            }
        }
        return result
    }

    private static func rewriteHWPParagraph(_ source: [Record], desired: HWPDocumentBlock) throws -> [Record] {
        guard var header = source.first, header.payload.count >= 18,
              let textIndex = source.firstIndex(where: { $0.tag == 0x43 && $0.level == header.level + 1 }) else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        let oldUnits = try hwpUnits(source[textIndex].payload)
        let spans = HWPHyperlinkEditing.spans(in: desired)
        var output = source
        output[textIndex].payload = try hwpText(desired.text, spans: spans)
        header.payload.hwpWriterSetUInt32(UInt32(output[textIndex].payload.count / 2), at: 0)
        var mask = try header.payload.hwpWriterUInt32(at: 4)
        if spans.isEmpty { mask &= ~UInt32(1 << 3) } else { mask |= UInt32(1 << 3) }
        header.payload.hwpWriterSetUInt32(mask, at: 4)
        output[0] = header

        if let shapeIndex = output.firstIndex(where: { $0.tag == 0x44 && $0.level == header.level + 1 }) {
            var payload = output[shapeIndex].payload
            guard payload.count.isMultiple(of: 8) else { throw HWPDocumentEditingError.invalidDocument }
            for offset in stride(from: 0, to: payload.count, by: 8) {
                let raw = Int(try payload.hwpWriterUInt32(at: offset))
                let visible = visibleOffset(in: oldUnits, raw: raw)
                payload.hwpWriterSetUInt32(UInt32(rawOffset(in: desired.text, visible: visible, spans: spans,
                    startsAtBoundary: true)), at: offset)
            }
            output[shapeIndex].payload = payload
        }
        if let lineIndex = output.firstIndex(where: { $0.tag == 0x45 && $0.level == header.level + 1 }) {
            var payload = output[lineIndex].payload
            guard payload.count.isMultiple(of: 36) else { throw HWPDocumentEditingError.invalidDocument }
            for offset in stride(from: 0, to: payload.count, by: 36) {
                let raw = Int(try payload.hwpWriterUInt32(at: offset))
                let visible = visibleOffset(in: oldUnits, raw: raw)
                payload.hwpWriterSetUInt32(UInt32(rawOffset(in: desired.text, visible: visible, spans: spans,
                    startsAtBoundary: false)), at: offset)
            }
            output[lineIndex].payload = payload
        }

        var filtered: [Record] = [], index = 0
        while index < output.count {
            let record = output[index]
            if record.tag == 0x47, record.level == header.level + 1,
               record.payload.count >= 4, try record.payload.hwpWriterUInt32(at: 0) == 0x2568_6C6B {
                let controlLevel = record.level; index += 1
                while index < output.count, output[index].level > controlLevel { index += 1 }
            } else { filtered.append(record); index += 1 }
        }
        for span in spans {
            filtered.append(Record(tag: 0x47, level: header.level + 1,
                payload: hyperlinkControl(span.target)))
        }
        return filtered
    }

    private static func hwpText(_ text: String, spans: [HWPHyperlinkEditing.Span]) throws -> Data {
        var units: [UInt16] = []
        let source = Array(text.utf16)
        for position in 0...source.count {
            for span in spans where NSMaxRange(span.range) == position {
                units += [4, 0x6C6B, 0x0068, 0, 0, 0, 0, 4]
            }
            for span in spans where span.range.location == position {
                units += [3, 0x6C6B, 0x2568, 0, 0, 0, 0, 3]
            }
            guard position < source.count else { continue }
            if source[position] == 9 { units += [9, 0, 0, 0, 0, 0, 0, 9] }
            else { units.append(source[position]) }
        }
        units.append(13)
        guard units.count * 2 <= HWP5TextExtractor.maximumSectionBytes else { throw HWPDocumentEditingError.limitExceeded }
        var result = Data(); for unit in units { result.hwpWriterAppendUInt16(unit) }
        return result
    }

    private static func hwpUnits(_ data: Data) throws -> [UInt16] {
        guard data.count.isMultiple(of: 2) else { throw HWPDocumentEditingError.invalidDocument }
        return stride(from: 0, to: data.count, by: 2).map { UInt16(data[$0]) | UInt16(data[$0 + 1]) << 8 }
    }

    private static func visibleOffset(in units: [UInt16], raw target: Int) -> Int {
        var raw = 0, visible = 0
        while raw < min(target, units.count) {
            let code = units[raw]
            if code == 9 { raw += min(8, units.count - raw); visible += 1 }
            else if (1...23).contains(code), code != 10, code != 13 { raw += min(8, units.count - raw) }
            else { raw += 1; if code != 13 { visible += 1 } }
        }
        return visible
    }

    private static func rawOffset(in text: String, visible: Int, spans: [HWPHyperlinkEditing.Span],
                                  startsAtBoundary: Bool) -> Int {
        let prefix = (text as NSString).substring(to: min(visible, text.utf16.count))
        var raw = visible + prefix.filter { $0 == "\t" }.count * 7
        for span in spans {
            if span.range.location < visible || (startsAtBoundary && span.range.location == visible) { raw += 8 }
            if NSMaxRange(span.range) <= visible { raw += 8 }
        }
        return raw
    }

    private static func hyperlinkControl(_ target: String) -> Data {
        let command = commandTarget(target)
        var payload = Data(); payload.hwpWriterAppendUInt32(0x2568_6C6B)
        payload.hwpWriterAppendUInt32(0x0000_A800); payload.append(0)
        let units = Array(command.utf16); payload.hwpWriterAppendUInt16(UInt16(units.count))
        for unit in units { payload.hwpWriterAppendUInt16(unit) }
        var hash: UInt32 = 0x811C_9DC5
        for byte in command.utf8 { hash ^= UInt32(byte); hash = hash &* 0x0100_0193 }
        payload.hwpWriterAppendUInt32(hash == 0 ? 1 : hash); payload.hwpWriterAppendUInt32(0)
        return payload
    }

    public static func applyHWPX(to data: Data, originals: [HWPDocumentBlock], edited: [HWPDocumentBlock]) throws -> Data {
        let desired = Dictionary(uniqueKeysWithValues: zip(originals, edited).compactMap { before, after in
            HWPHyperlinkEditing.spans(in: before) == HWPHyperlinkEditing.spans(in: after) ? nil : (after.id, after)
        })
        guard !desired.isEmpty else { return data }
        let package = try HWPXDocumentPackage.load(from: data)
        let archive = try HWPXEditingArchive(data: data)
        var replacements: [String: Data] = [:]
        var nextID = try nextObjectID(package)
        for section in package.sections where section.blocks.contains(where: { desired[$0.id] != nil }) {
            var xml = section.xml
            let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: xml)
            guard ranges.count == section.blocks.count else { throw HWPDocumentEditingError.staleDocument }
            for index in section.blocks.indices.reversed() {
                guard let requested = desired[section.blocks[index].id] else { continue }
                let source = (xml as NSString).substring(with: ranges[index])
                let updated = try paragraph(source, desired: requested, nextID: &nextID)
                xml = (xml as NSString).replacingCharacters(in: ranges[index], with: updated)
            }
            replacements[section.path] = Data(xml.utf8)
        }
        let result = try archive.repack(replacing: replacements)
        let saved = try HWPXDocumentPackage.load(from: result)
        for block in saved.blocks {
            if let requested = desired[block.id],
               HWPHyperlinkEditing.spans(in: block) != HWPHyperlinkEditing.spans(in: requested) {
                throw HWPDocumentEditingError.cannotSave
            }
        }
        return result
    }

    private static func paragraph(_ source: String, desired: HWPDocumentBlock,
                                  nextID: inout UInt32) throws -> String {
        var xml = source
        for name in ["fieldbegin", "fieldend"] {
            for element in try HWPFormattingXML.elements(xml, name: name).reversed() {
                xml = (xml as NSString).replacingCharacters(in: element.range, with: "")
            }
        }
        let runs = try HWPFormattingXML.elements(xml, name: "run")
        let desiredRuns = HWPDocumentFormatting.runs(in: desired)
        var desiredBoundaries: [(NSRange, String?)] = [], desiredOffset = 0
        for run in desiredRuns {
            let length = run.text.utf16.count
            desiredBoundaries.append((NSRange(location: desiredOffset, length: length), run.hyperlink))
            desiredOffset += length
        }
        guard desiredOffset == desired.text.utf16.count else { throw HWPDocumentEditingError.staleDocument }
        struct LinkedRun { let element: HWPFormattingXML.Element; let prefix: String; let style: String; let target: String }
        var linked: [LinkedRun] = [], visibleOffset = 0
        for run in runs {
            let text = try HWPXMLVisibleText.read(run.xml)
            let length = text.utf16.count
            guard length > 0 else { continue }
            let range = NSRange(location: visibleOffset, length: length)
            visibleOffset += length
            let intersecting = desiredBoundaries.filter { NSIntersectionRange($0.0, range).length > 0 }
            let targets = Set(intersecting.map(\.1))
            guard targets.count == 1 else { throw HWPDocumentEditingError.unsupportedEdit }
            guard let target = targets.first ?? nil else { continue }
            let prefix = try HWPFormattingXML.prefix(run.xml)
            let style = try HWPFormattingXML.attribute(run.xml, "charPrIDRef") ?? "0"
            linked.append(.init(element: run, prefix: prefix, style: style, target: target))
        }
        guard visibleOffset == desired.text.utf16.count else { throw HWPDocumentEditingError.staleDocument }
        var insertions: [Int: String] = [:], index = 0
        while index < linked.count {
            let first = linked[index]
            var end = index
            while end + 1 < linked.count, linked[end + 1].target == first.target { end += 1 }
            guard nextID < UInt32.max else { throw HWPDocumentEditingError.limitExceeded }
            let id = nextID; nextID += 1
            let command = HWPFormattingXML.escaped(commandTarget(first.target))
            let begin = "<\(first.prefix)run charPrIDRef=\"\(first.style)\"><\(first.prefix)ctrl><\(first.prefix)fieldBegin id=\"\(id)\" type=\"HYPERLINK\" name=\"\" editable=\"1\" dirty=\"0\" zorder=\"-1\" fieldid=\"\(id)\" metaTag=\"\"><\(first.prefix)parameters cnt=\"1\" name=\"\"><\(first.prefix)stringParam name=\"Command\">\(command)</\(first.prefix)stringParam></\(first.prefix)parameters></\(first.prefix)fieldBegin></\(first.prefix)ctrl></\(first.prefix)run>"
            let last = linked[end]
            let finish = "<\(last.prefix)run charPrIDRef=\"\(last.style)\"><\(last.prefix)ctrl><\(last.prefix)fieldEnd beginIDRef=\"\(id)\" fieldid=\"\(id)\"/></\(last.prefix)ctrl></\(last.prefix)run>"
            insertions[first.element.range.location, default: ""] += begin
            insertions[NSMaxRange(last.element.range), default: ""] += finish
            index = end + 1
        }
        for (location, value) in insertions.sorted(by: { $0.key > $1.key }) {
            xml = (xml as NSString).replacingCharacters(in: NSRange(location: location, length: 0), with: value)
        }
        return xml
    }

    private static func commandTarget(_ target: String) -> String {
        target.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ":", with: "\\:") + ";1;0;0;"
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
}

public nonisolated final class HWPXMLVisibleText: NSObject, XMLParserDelegate {
    private var text = "", textDepth = 0
    public static func read(_ xml: String) throws -> String {
        let wrapped = "<root xmlns:hp=\"urn:hancom:hwpml:paragraph\">\(xml)</root>"
        let reader = HWPXMLVisibleText(), parser = XMLParser(data: Data(wrapped.utf8))
        parser.delegate = reader; parser.shouldProcessNamespaces = true
        guard parser.parse() else { throw HWPDocumentEditingError.invalidDocument }
        return reader.text
    }
    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let name = String((qName ?? elementName).split(separator: ":").last ?? "").lowercased()
        if name == "t" { textDepth += 1 }
        else if name == "tab" { text += "\t" }
        else if name == "linebreak" { text += "\n" }
        else if name == "hyphen" || name == "hypen" { text += "-" }
        else if name == "nbspace" { text += "\u{00A0}" }
        else if name == "fwspace" { text += "\u{3000}" }
    }
    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = String((qName ?? elementName).split(separator: ":").last ?? "").lowercased()
        if name == "t", textDepth > 0 { textDepth -= 1 }
    }
    public func parser(_ parser: XMLParser, foundCharacters string: String) { if textDepth > 0 { text += string } }
    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { if textDepth > 0 { text += String(decoding: CDATABlock, as: UTF8.self) } }
}
