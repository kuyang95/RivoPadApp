import Foundation

nonisolated enum HWPPageNumberWriter {
    static func apply(_ request: HWPPageNumberRequest, to source: HWPTableStructureDocument) throws -> Data {
        try HWPPageNumberEditing.validate(request, layouts: source.layouts)
        switch source {
        case .hwpx(let package): return try hwpx(request, package: package)
        case .hwp(_, let data): return try hwp(request, data: data, layouts: source.layouts)
        }
    }
    private static func hwpx(_ request: HWPPageNumberRequest, package: HWPXDocumentPackage) throws -> Data {
        var replacements: [String: Data] = [:], found: Set<Int> = []
        for section in package.sections {
            guard let index = HWPPageSetup.sectionIndex(section.path), request.sections.contains(index) else { continue }
            var xml = section.xml
            let numbers = try HWPFormattingXML.elements(xml, name: "pagenum")
            let sections = try HWPFormattingXML.elements(xml, name: "secpr")
            guard numbers.count <= 1, sections.count <= 1,
                  let firstRun = try HWPFormattingXML.elements(xml, name: "run").first else { throw HWPDocumentEditingError.unsupportedEdit }
            let prefix = try HWPFormattingXML.prefix(firstRun.xml)
            let style = request.style(for: index, layouts: package.pageLayouts)
            // A section-wide edit cannot preserve a later paragraph's local
            // numbering override until per-page controls are represented.
            if let existing = numbers.first {
                guard let firstParagraph = try HWPFormattingXML.elements(xml, name: "p").first,
                      NSLocationInRange(existing.range.location, firstParagraph.range) else {
                    throw HWPDocumentEditingError.unsupportedEdit
                }
            }
            if style != nil, !(try HWPFormattingXML.elements(xml, name: "newnum")).isEmpty {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            var number = numbers.first?.xml ?? "<\(prefix)pageNum/>"
            number = try HWPFormattingXML.setAttribute(number, "pos", style?.position ?? "NONE")
            if let style {
                number = try HWPFormattingXML.setAttribute(number, "formatType", "DIGIT")
                number = try HWPFormattingXML.setAttribute(number, "sideChar", style.sideCharacter)
            }
            if let old = numbers.first {
                xml = (xml as NSString).replacingCharacters(in: old.range, with: number)
            } else if style != nil {
                xml = try insertAtRunStart("<\(prefix)ctrl>\(number)</\(prefix)ctrl>", xml: xml)
            }
            if let style {
                let oldSection = try HWPFormattingXML.elements(xml, name: "secpr").first
                var properties = oldSection?.xml ?? "<\(prefix)secPr/>"
                var start = try HWPFormattingXML.elements(properties, name: "startnum").first?.xml
                    ?? "<\(prefix)startNum pageStartsOn=\"BOTH\" page=\"0\" pic=\"0\" tbl=\"0\" equation=\"0\"/>"
                start = try HWPFormattingXML.setAttribute(start, "page", String(style.startsAt ?? 0))
                properties = try HWPFormattingXML.replaceOrAppend(properties, name: "startnum", replacement: start)
                // Keep header/footer visibility and all unrelated section properties.
                if let visibility = try HWPFormattingXML.elements(properties, name: "visibility").first {
                    let visible = try HWPFormattingXML.setAttribute(visibility.xml, "hideFirstPageNum", "0")
                    properties = (properties as NSString).replacingCharacters(in: visibility.range, with: visible)
                }
                if let oldSection { xml = (xml as NSString).replacingCharacters(in: oldSection.range, with: properties) }
                else { xml = try insertAtRunStart(properties, xml: xml) }
            }
            replacements[section.path] = Data(xml.utf8); found.insert(index)
        }
        guard found == request.sections else { throw HWPDocumentEditingError.staleDocument }
        return try HWPXEditingArchive(data: package.sourceData).repack(replacing: replacements)
    }
    private static func insertAtRunStart(_ content: String, xml: String) throws -> String {
        guard let run = try HWPFormattingXML.elements(xml, name: "run").first,
              let token = try HWPXParagraphXMLPatcher.tagTokens(in: run.xml).first, !token.isSelfClosing else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        return (xml as NSString).replacingCharacters(in: NSRange(location: run.range.location + NSMaxRange(token.range), length: 0), with: content)
    }
    private static func hwp(_ request: HWPPageNumberRequest, data: Data, layouts: [HWPDocumentPageLayout]) throws -> Data {
        let container = try OLECompoundFile(data: data)
        let flags = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36)
        guard flags & 0x6796 == 0 else { throw HWPDocumentEditingError.protectedDocument }
        let compressed = flags & 1 != 0
        var replacements: [String: Data] = [:], found: Set<Int> = []
        for path in container.streamNames where path.hasPrefix("bodytext/section") {
            guard let index = HWPPageSetup.sectionIndex(path), request.sections.contains(index) else { continue }
            let stored = try container.stream(named: path)
            let expanded = try compressed ? HWP5TextExtractor.inflateRawDeflate(stored, maximumBytes: HWP5TextExtractor.maximumSectionBytes) : stored
            var records = try HWP5DocumentRewriter.parseRecords(expanded)
            func controls(_ id: UInt32) -> [Int] {
                records.indices.filter { records[$0].tag == 0x47 && (try? records[$0].payload.hwpWriterUInt32(at: 0)) == id }
            }
            let sectionControls = controls(0x7365_6364), numbers = controls(0x7067_6E70)
            guard sectionControls.count == 1, let section = sectionControls.first, records[section].payload.count >= 22,
                  records[section].level == 1, numbers.count <= 1,
                  numbers.allSatisfy({ records[$0].level == 1 && records[$0].payload.count >= 16 }) else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            let style = request.style(for: index, layouts: layouts)
            if let existing = numbers.first {
                let owner = records.indices.prefix(existing).last { records[$0].tag == 0x42 && records[$0].level == 0 }
                let sectionOwner = records.indices.prefix(section).last { records[$0].tag == 0x42 && records[$0].level == 0 }
                guard owner == sectionOwner else { throw HWPDocumentEditingError.unsupportedEdit }
            }
            if style != nil, !controls(0x6E77_6E6F).isEmpty { throw HWPDocumentEditingError.unsupportedEdit }
            if let style {
                records[section].payload.hwpWriterSetUInt16(UInt16(style.startsAt ?? 0), at: 20)
                let properties = try records[section].payload.hwpWriterUInt32(at: 4)
                records[section].payload.hwpWriterSetUInt32(properties & ~0x20, at: 4)
            }
            var number = numbers.first.map { records[$0].payload } ?? Data(repeating: 0, count: 16)
            number.hwpWriterSetUInt32(0x7067_6E70, at: 0)
            let oldFlags = try number.hwpWriterUInt32(at: 4)
            let position = style.flatMap { HWPPageNumberEditing.positions.firstIndex(of: $0.position) }.map { $0 + 1 } ?? 0
            number.hwpWriterSetUInt32((oldFlags & ~0xFFF) | UInt32(position << 8), at: 4)
            if let style {
                for offset in [8, 10, 12] { number.hwpWriterSetUInt16(0, at: offset) }
                number.hwpWriterSetUInt16(style.sideCharacter == "-" ? 45 : 0, at: 14)
            }
            if let old = numbers.first { records[old].payload = number }
            else if style != nil {
                // Anchor in the existing section-control paragraph. Appending before
                // its paragraph terminator preserves every visible text offset.
                guard let owner = records.indices.prefix(section).last(where: { records[$0].tag == 0x42 && records[$0].level == 0 }) else {
                    throw HWPDocumentEditingError.unsupportedEdit
                }
                let end = records.indices.dropFirst(owner + 1).first { records[$0].level == 0 } ?? records.endIndex
                guard let textIndex = (owner + 1..<end).first(where: { records[$0].tag == 0x43 && records[$0].level == 1 }),
                      records[textIndex].payload.count >= 2, records[textIndex].payload.suffix(2) == Data([13, 0]),
                      records[owner].payload.count >= 22 else { throw HWPDocumentEditingError.unsupportedEdit }
                var anchor = Data(); anchor.hwpWriterAppendUInt16(21); anchor.hwpWriterAppendUInt32(0x7067_6E70)
                anchor.append(Data(repeating: 0, count: 8)); anchor.hwpWriterAppendUInt16(21)
                records[textIndex].payload.insert(contentsOf: anchor, at: records[textIndex].payload.count - 2)
                let count = try records[owner].payload.hwpWriterUInt32(at: 0)
                guard count & 0x7FFF_FFFF <= 0x7FFF_FFF7 else { throw HWPDocumentEditingError.limitExceeded }
                records[owner].payload.hwpWriterSetUInt32(count + 8, at: 0)
                let mask = try records[owner].payload.hwpWriterUInt32(at: 4)
                records[owner].payload.hwpWriterSetUInt32(mask | (1 << 21), at: 4)
                records.insert(.init(tag: 0x47, level: 1, payload: number), at: end)
            }
            let payload = records.reduce(into: Data()) { $0.append($1.serialized()) }
            replacements[path] = try compressed ? HWP5DocumentRewriter.rawDeflate(payload) : payload
            found.insert(index)
        }
        guard found == request.sections else { throw HWPDocumentEditingError.staleDocument }
        return try container.serialized(replacing: replacements)
    }
}
