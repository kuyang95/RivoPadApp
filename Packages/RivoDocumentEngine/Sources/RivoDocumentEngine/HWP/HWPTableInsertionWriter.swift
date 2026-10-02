import Foundation

public nonisolated enum HWPTableInsertionWriter {
    public typealias Record = HWP5DocumentRewriter.Record
    public typealias Request = HWPTableInsertion.Request
    public static func apply(_ request: Request, to source: HWPTableStructureDocument, ownerIndex: Int) throws -> Data {
        guard request.isValid, source.blocks.indices.contains(ownerIndex), source.blocks[ownerIndex].text.isEmpty,
              HWPParagraphEditing.supports(source.blocks[ownerIndex]) else { throw HWPDocumentEditingError.unsupportedEdit }
        switch source {
        case .hwpx(let package): return try hwpx(request, package: package, owner: source.blocks[ownerIndex])
        case .hwp(_, let data): return try hwp(request, data: data, owner: source.blocks[ownerIndex])
        }
    }
    private static func unit(_ value: Double) -> String { String(Int((value * 100).rounded())) }
    private static func hwpx(_ request: Request, package: HWPXDocumentPackage, owner: HWPDocumentBlock) throws -> Data {
        guard let section = package.sections.first(where: { $0.path == owner.sectionPath }),
              let index = section.blocks.firstIndex(where: { $0.id == owner.id }) else { throw HWPDocumentEditingError.staleDocument }
        let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: section.xml)
        guard ranges.indices.contains(index) else { throw HWPDocumentEditingError.staleDocument }
        let paragraph = (section.xml as NSString).substring(with: ranges[index])
        let prefix = try HWPFormattingXML.prefix(paragraph)
        guard let run = try HWPFormattingXML.elements(paragraph, name: "run").first else { throw HWPDocumentEditingError.unsupportedEdit }
        let paraID = HWPFormattingXML.escaped(try HWPFormattingXML.attribute(paragraph, "paraPrIDRef") ?? "0")
        let styleID = HWPFormattingXML.escaped(try HWPFormattingXML.attribute(paragraph, "styleIDRef") ?? "0")
        let charID = HWPFormattingXML.escaped(try HWPFormattingXML.attribute(run.xml, "charPrIDRef") ?? "0")
        var nextID: UInt32 = 0
        for section in package.sections {
            for token in try HWPXParagraphXMLPatcher.tagTokens(in: section.xml) where !token.isClosing {
                let opening = (section.xml as NSString).substring(with: token.range)
                nextID = max(nextID, UInt32(try HWPFormattingXML.attribute(opening, "id") ?? "0") ?? 0)
            }
        }
        guard nextID < UInt32.max - UInt32(request.rows * request.columns + 1) else { throw HWPDocumentEditingError.limitExceeded }
        nextID += 1; let tableID = nextID
        let archive = try HWPXEditingArchive(data: package.sourceData)
        var header = String(decoding: try archive.data(at: "Contents/header.xml"), as: UTF8.self)
        let headerPrefix = try HWPFormattingXML.prefix(header)
        let definitions = try HWPFormattingXML.dictionary(header, name: "borderfill")
        let borderID = (definitions.keys.compactMap(Int.init).max() ?? 0) + 1
        guard borderID < 65_535 else { throw HWPDocumentEditingError.limitExceeded }
        var border = try HWPFormattingXML.elements(LegacyHWPXConverter.headerXML, name: "borderfill")[0].xml
            .replacingOccurrences(of: "hh:", with: headerPrefix)
        border = try HWPFormattingXML.setAttribute(border, "id", String(borderID))
        for side in ["leftBorder", "rightBorder", "topBorder", "bottomBorder"] {
            border = try HWPFormattingXML.replaceOrAppend(border, name: side.lowercased(), replacement:
                "<\(headerPrefix)\(side) type=\"SOLID\" width=\"0.3 mm\" color=\"#000000\"/>")
        }
        header = try HWPFormattingXML.appendToGroup(header, name: "borderfills", additions: border, count: definitions.count + 1)
        var rows = ""
        for row in 0..<request.rows {
            rows += "<\(prefix)tr>"
            for column in 0..<request.columns {
                nextID += 1
                let p = "<\(prefix)p id=\"\(nextID)\" paraPrIDRef=\"\(paraID)\" styleIDRef=\"\(styleID)\" pageBreak=\"0\" columnBreak=\"0\" merged=\"0\"><\(prefix)run charPrIDRef=\"\(charID)\"><\(prefix)t/></\(prefix)run></\(prefix)p>"
                rows += "<\(prefix)tc name=\"\" header=\"0\" hasMargin=\"1\" protect=\"0\" editable=\"1\" dirty=\"0\" borderFillIDRef=\"\(borderID)\"><\(prefix)subList id=\"\" textDirection=\"HORIZONTAL\" lineWrap=\"BREAK\" vertAlign=\"TOP\" linkListIDRef=\"0\" linkListNextIDRef=\"0\" textWidth=\"0\" textHeight=\"0\" hasTextRef=\"0\" hasNumRef=\"0\">\(p)</\(prefix)subList><\(prefix)cellAddr colAddr=\"\(column)\" rowAddr=\"\(row)\"/><\(prefix)cellSpan colSpan=\"1\" rowSpan=\"1\"/><\(prefix)cellSz width=\"\(unit(request.columnWidths[column]))\" height=\"\(unit(Request.rowHeight))\"/><\(prefix)cellMargin left=\"400\" right=\"400\" top=\"400\" bottom=\"400\"/></\(prefix)tc>"
            }
            rows += "</\(prefix)tr>"
        }
        let table = "<\(prefix)tbl id=\"\(tableID)\" zOrder=\"0\" numberingType=\"TABLE\" textWrap=\"TOP_AND_BOTTOM\" textFlow=\"BOTH_SIDES\" lock=\"0\" dropcapstyle=\"None\" pageBreak=\"CELL\" repeatHeader=\"0\" rowCnt=\"\(request.rows)\" colCnt=\"\(request.columns)\" cellSpacing=\"0\" borderFillIDRef=\"\(borderID)\" noAdjust=\"0\"><\(prefix)sz width=\"\(unit(request.selection.width))\" widthRelTo=\"ABSOLUTE\" height=\"\(unit(Double(request.rows) * Request.rowHeight))\" heightRelTo=\"ABSOLUTE\" protect=\"0\"/><\(prefix)pos treatAsChar=\"1\" affectLSpacing=\"0\" flowWithText=\"1\" allowOverlap=\"0\" holdAnchorAndSO=\"0\" vertRelTo=\"PARA\" horzRelTo=\"COLUMN\" vertAlign=\"TOP\" horzAlign=\"LEFT\" vertOffset=\"0\" horzOffset=\"0\"/><\(prefix)outMargin left=\"0\" right=\"0\" top=\"0\" bottom=\"0\"/><\(prefix)inMargin left=\"400\" right=\"400\" top=\"400\" bottom=\"400\"/>\(rows)</\(prefix)tbl>"
        let updatedRun = try HWPFormattingXML.append(table, to: run.xml)
        let updatedParagraph = (paragraph as NSString).replacingCharacters(in: run.range, with: updatedRun)
        let xml = (section.xml as NSString).replacingCharacters(in: ranges[index], with: updatedParagraph)
        guard xml.utf8.count <= HWPXTextExtractor.maximumEntryBytes else { throw HWPDocumentEditingError.limitExceeded }
        return try archive.repack(replacing: [section.path: Data(xml.utf8), "Contents/header.xml": Data(header.utf8)])
    }

    private static func hwp(_ request: Request, data: Data, owner: HWPDocumentBlock) throws -> Data {
        let container = try OLECompoundFile(data: data)
        let flags = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36)
        guard flags & 0x6796 == 0 else { throw HWPDocumentEditingError.protectedDocument }
        let compressed = flags & 1 != 0
        func expanded(_ data: Data) throws -> Data { try compressed ? HWP5TextExtractor.inflateRawDeflate(data, maximumBytes: HWP5TextExtractor.maximumSectionBytes) : data }
        func encoded(_ records: [Record]) throws -> Data {
            let bytes = records.reduce(into: Data()) { $0.append($1.serialized()) }
            guard bytes.count <= HWP5TextExtractor.maximumSectionBytes else { throw HWPDocumentEditingError.limitExceeded }
            return try compressed ? HWP5DocumentRewriter.rawDeflate(bytes) : bytes
        }
        let paths = container.streamNames.filter { $0.hasPrefix("bodytext/section") }
            .sorted { (HWPPageSetup.sectionIndex($0) ?? 0) < (HWPPageSetup.sectionIndex($1) ?? 0) }
        var sections: [String: [Record]] = [:], nextInstance: UInt32 = 0, ordinal = 0
        var ownerRecord: Int?
        for path in paths {
            let records = try HWP5DocumentRewriter.parseRecords(expanded(container.stream(named: path)))
            sections[path] = records
            for (index, record) in records.enumerated() {
                if record.tag == 0x42 {
                    if ordinal == owner.paragraphIndex && path == owner.sectionPath.lowercased() { ownerRecord = index }
                    ordinal += 1
                    if record.payload.count >= 22 { nextInstance = max(nextInstance, try record.payload.hwpWriterUInt32(at: 18)) }
                } else if record.tag == 0x47 && record.payload.count >= 40,
                          [0x7462_6C20, 0x6773_6F20, 0x6571_6564].contains(try record.payload.hwpWriterUInt32(at: 0)) {
                    nextInstance = max(nextInstance, try record.payload.hwpWriterUInt32(at: 36))
                }
            }
        }
        let path = owner.sectionPath.lowercased()
        guard var records = sections[path], let start = ownerRecord, records[start].level == 0,
              nextInstance < UInt32.max - UInt32(request.rows * request.columns + 1) else { throw HWPDocumentEditingError.unsupportedEdit }
        var end = records.indices.dropFirst(start + 1).first { records[$0].level == 0 } ?? records.endIndex
        let owned = start..<end
        let text = owned.first(where: { records[$0].tag == 0x43 })
        guard owned.allSatisfy({ [0x42, 0x43, 0x44, 0x45].contains(records[$0].tag) }),
              text.map({ records[$0].payload.isEmpty || records[$0].payload == Data([13, 0]) }) ?? true,
              let shape = owned.first(where: { records[$0].tag == 0x44 }), records[shape].payload.count >= 8,
              records[start].payload.count >= 22 else { throw HWPDocumentEditingError.unsupportedEdit }
        let templateHeader = records[start].payload, templateShape = Data(records[shape].payload.prefix(8))
        var info = try HWP5DocumentRewriter.parseRecords(expanded(container.stream(named: "DocInfo")))
        let definitions = info.filter { $0.tag == 0x14 }
        guard definitions.count < 65_534, let mapping = info.firstIndex(where: { $0.tag == 0x11 }), info[mapping].payload.count >= 36 else { throw HWPDocumentEditingError.limitExceeded }
        let borderID = definitions.count + 1
        var border = Data(repeating: 0, count: 41)
        for offset in [2, 8, 14, 20] { border[offset] = 1; border[offset + 1] = 5 } // solid, 0.3 mm, black
        info[mapping].payload.hwpWriterSetUInt32(UInt32(borderID), at: 32)
        info.insert(.init(tag: 0x14, level: 0, payload: border), at: info.firstIndex(where: { $0.tag > 0x14 }) ?? info.endIndex)
        var anchor = Data(); anchor.hwpWriterAppendUInt16(11); anchor.hwpWriterAppendUInt32(0x7462_6C20)
        anchor.append(Data(repeating: 0, count: 8)); anchor.hwpWriterAppendUInt16(11); anchor.hwpWriterAppendUInt16(13)
        if let text { records[text].payload = anchor } else {
            // Empty HWP paragraphs may omit PARA_TEXT altogether. Add the
            // anchor text before their character-shape and line records.
            records.insert(.init(tag: 0x43, level: 1, payload: anchor), at: start + 1)
            end += 1
        }
        let lastBit = try records[start].payload.hwpWriterUInt32(at: 0) & 0x8000_0000
        records[start].payload.hwpWriterSetUInt32(lastBit | 9, at: 0)
        records[start].payload.hwpWriterSetUInt32(1 << 11, at: 4)
        nextInstance += 1
        var control = Data(repeating: 0, count: 46)
        control.hwpWriterSetUInt32(0x7462_6C20, at: 0)
        control.hwpWriterSetUInt32(1 | (2 << 3) | (2 << 8) | (4 << 15) | (2 << 18) | (2 << 26), at: 4)
        control.hwpWriterSetUInt32(UInt32((request.selection.width * 100).rounded()), at: 16)
        control.hwpWriterSetUInt32(UInt32(Double(request.rows) * Request.rowHeight * 100), at: 20)
        control.hwpWriterSetUInt32(nextInstance, at: 36)
        var property = Data(repeating: 0, count: 18)
        property.hwpWriterSetUInt32(1, at: 0) // split at cell boundaries
        property.hwpWriterSetUInt16(UInt16(request.rows), at: 4); property.hwpWriterSetUInt16(UInt16(request.columns), at: 6)
        for offset in [10, 12, 14, 16] { property.hwpWriterSetUInt16(400, at: offset) }
        for _ in 0..<request.rows { property.hwpWriterAppendUInt16(UInt16(request.columns)) }
        property.hwpWriterAppendUInt16(UInt16(borderID)); property.hwpWriterAppendUInt16(0)
        var inserted = [Record(tag: 0x47, level: 1, payload: control), Record(tag: 0x4D, level: 2, payload: property)]
        for row in 0..<request.rows {
            for column in 0..<request.columns {
                var cell = Data(); cell.hwpWriterAppendUInt16(1); cell.hwpWriterAppendUInt32(1 << 16)
                for value in [column, row, 1, 1] { cell.hwpWriterAppendUInt16(UInt16(value)) }
                cell.hwpWriterAppendUInt32(UInt32((request.columnWidths[column] * 100).rounded()))
                cell.hwpWriterAppendUInt32(UInt32(Request.rowHeight * 100))
                for _ in 0..<4 { cell.hwpWriterAppendUInt16(400) }
                cell.hwpWriterAppendUInt16(UInt16(borderID))
                var header = templateHeader
                header.hwpWriterSetUInt32(0x8000_0001, at: 0); header.hwpWriterSetUInt32(0, at: 4); header[11] = 0
                header.hwpWriterSetUInt16(1, at: 12); header.hwpWriterSetUInt16(0, at: 14); header.hwpWriterSetUInt16(0, at: 16)
                nextInstance += 1; header.hwpWriterSetUInt32(nextInstance, at: 18)
                inserted += [.init(tag: 0x48, level: 2, payload: cell), .init(tag: 0x42, level: 3, payload: header),
                             .init(tag: 0x43, level: 4, payload: Data([13, 0])), .init(tag: 0x44, level: 4, payload: templateShape)]
            }
        }
        records.insert(contentsOf: inserted, at: end)
        return try container.serialized(replacing: [path: encoded(records), "DocInfo": encoded(info)])
    }
}
