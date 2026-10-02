import Foundation

public nonisolated enum HWPTableStructureWriter {
    public typealias Plan = HWPTableStructureEditing.Plan
    public typealias Address = HWPTableStructureEditing.Address
    public typealias Record = HWP5DocumentRewriter.Record

    public static func sourceIndices(_ plan: Plan, count: Int) -> [Int?] {
        (0..<plan.originalRange.lowerBound).map(Optional.some) + plan.sourceIndices
            + (plan.originalRange.upperBound..<count).map(Optional.some)
    }

    public static func verify(_ saved: [HWPDocumentBlock], original: [HWPDocumentBlock], plan: Plan) throws {
        let indices = sourceIndices(plan, count: original.count)
        guard indices.count == saved.count else { throw HWPDocumentEditingError.cannotSave }
        for (index, source) in indices.enumerated() {
            if let source {
                guard saved[index].text == original[source].text,
                      HWPDocumentFormatting.matches(saved[index], original[source], includingCell: !plan.originalRange.contains(source)) else { throw HWPDocumentEditingError.cannotSave }
            } else if !saved[index].text.isEmpty { throw HWPDocumentEditingError.cannotSave }
        }
        var offset = plan.originalRange.lowerBound
        for cell in plan.cells {
            guard let template = plan.originalCells.first(where: { $0.source == cell.source }) else { throw HWPDocumentEditingError.staleDocument }
            let count = cell.isNew ? 1 : cell.paragraphs.count
            for block in saved[offset..<(offset + count)] {
                guard let location = block.tableLocation, location.table == plan.table,
                      HWPCellFormatting.matches(block, original[template.paragraphs[0]]),
                      location.parent == original[template.paragraphs[0]].tableLocation?.parent,
                      location.row == cell.row, location.column == cell.column,
                      location.rowSpan == cell.rowSpan, location.columnSpan == cell.columnSpan,
                      abs((location.cellWidthPoints ?? 0) - plan.width(cell)) < 0.03,
                      abs((location.cellHeightPoints ?? 0) - plan.height(cell)) < 0.03 else { throw HWPDocumentEditingError.cannotSave }
            }
            offset += count
        }
    }

    public static func hwpx(_ package: HWPXDocumentPackage, plan: Plan) throws -> Data {
        guard let section = package.sections.first(where: { $0.path == plan.section }) else { throw HWPDocumentEditingError.staleDocument }
        let tables = try HWPFormattingXML.elements(section.xml, name: "tbl")
        guard tables.indices.contains(plan.table) else { throw HWPDocumentEditingError.staleDocument }
        let table = tables[plan.table]
        guard try HWPFormattingXML.elements(table.xml, name: "tbl").count == 1 else { throw HWPDocumentEditingError.unsupportedEdit }
        let rows = try HWPFormattingXML.elements(table.xml, name: "tr")
        guard rows.count == plan.oldRows.count else { throw HWPDocumentEditingError.unsupportedEdit }
        let cells = try HWPFormattingXML.elements(table.xml, name: "tc")
        var cellXML: [Address: String] = [:]
        for cell in cells {
            guard let addr = try HWPFormattingXML.elements(cell.xml, name: "celladdr").first,
                  let row = Int(try HWPFormattingXML.attribute(addr.xml, "rowAddr") ?? ""),
                  let column = Int(try HWPFormattingXML.attribute(addr.xml, "colAddr") ?? ""),
                  cellXML.updateValue(cell.xml, forKey: Address(row: row, column: column)) == nil else {
                throw HWPDocumentEditingError.invalidDocument
            }
        }
        guard cellXML.count == plan.originalCells.count else { throw HWPDocumentEditingError.unsupportedEdit }
        var paragraphXML: [Int: String] = [:]
        for cell in plan.originalCells {
            guard let xml = cellXML[cell.source] else { throw HWPDocumentEditingError.staleDocument }
            let paragraphs = try HWPFormattingXML.elements(xml, name: "p")
            guard paragraphs.count == cell.paragraphs.count else { throw HWPDocumentEditingError.unsupportedEdit }
            for (index, paragraph) in zip(cell.paragraphs, paragraphs) { paragraphXML[index] = paragraph.xml }
        }
        var nextID: UInt32 = 0
        for item in package.sections {
            for p in try HWPFormattingXML.elements(item.xml, name: "p") {
                nextID = max(nextID, UInt32(try HWPFormattingXML.attribute(p.xml, "id") ?? "0") ?? 0)
            }
        }
        var newRows = Array(repeating: "", count: plan.rows.count)
        for cell in plan.cells {
            guard var xml = cellXML[cell.source] else { throw HWPDocumentEditingError.staleDocument }
            if cell.isNew {
                guard let sublist = try HWPFormattingXML.elements(xml, name: "sublist").first,
                      let p = try HWPFormattingXML.elements(sublist.xml, name: "p").first,
                      let run = try HWPFormattingXML.elements(p.xml, name: "run").first,
                      nextID < UInt32.max else { throw HWPDocumentEditingError.unsupportedEdit }
                nextID += 1
                let prefix = try HWPFormattingXML.prefix(p.xml)
                let paraID = try HWPFormattingXML.attribute(p.xml, "paraPrIDRef") ?? "0"
                let styleID = try HWPFormattingXML.attribute(p.xml, "styleIDRef") ?? "0"
                let charID = try HWPFormattingXML.attribute(run.xml, "charPrIDRef") ?? "0"
                let paragraph = "<\(prefix)p id=\"\(nextID)\" paraPrIDRef=\"\(HWPFormattingXML.escaped(paraID))\" styleIDRef=\"\(HWPFormattingXML.escaped(styleID))\" pageBreak=\"0\" columnBreak=\"0\" merged=\"0\"><\(prefix)run charPrIDRef=\"\(HWPFormattingXML.escaped(charID))\"><\(prefix)t/></\(prefix)run></\(prefix)p>"
                let subPrefix = try HWPFormattingXML.prefix(sublist.xml)
                let replacement = try HWPFormattingXML.opening(sublist.xml) + paragraph + "</\(subPrefix)subList>"
                xml = (xml as NSString).replacingCharacters(in: sublist.range, with: replacement)
                xml = try HWPFormattingXML.setAttribute(xml, "name", "")
                xml = try HWPFormattingXML.setAttribute(xml, "header", "0")
            } else if cell.paragraphs != plan.originalCells.first(where: { $0.source == cell.source })?.paragraphs {
                guard let sublist = try HWPFormattingXML.elements(xml, name: "sublist").first else { throw HWPDocumentEditingError.unsupportedEdit }
                let paragraphs = try cell.paragraphs.map { index -> String in
                    guard let value = paragraphXML[index] else { throw HWPDocumentEditingError.staleDocument }
                    return value
                }.joined()
                let prefix = try HWPFormattingXML.prefix(sublist.xml)
                let replacement = try HWPFormattingXML.opening(sublist.xml) + paragraphs + "</\(prefix)subList>"
                xml = (xml as NSString).replacingCharacters(in: sublist.range, with: replacement)
            }
            xml = try setting(xml, element: "celladdr", attributes: ["rowAddr": String(cell.row), "colAddr": String(cell.column)])
            xml = try setting(xml, element: "cellspan", attributes: ["rowSpan": String(cell.rowSpan), "colSpan": String(cell.columnSpan)])
            xml = try setting(xml, element: "cellsz", attributes: ["width": unit(plan.width(cell)), "height": unit(plan.height(cell))])
            newRows[cell.row] += xml
        }
        let prefix = try HWPFormattingXML.prefix(table.xml)
        let replacement = newRows.map { "<\(prefix)tr>\($0)</\(prefix)tr>" }.joined()
        guard let first = rows.first, let last = rows.last else { throw HWPDocumentEditingError.invalidDocument }
        var xml = (table.xml as NSString).replacingCharacters(in: NSRange(location: first.range.location,
            length: NSMaxRange(last.range) - first.range.location), with: replacement)
        xml = try HWPFormattingXML.setAttribute(xml, "rowCnt", String(plan.rows.count))
        xml = try HWPFormattingXML.setAttribute(xml, "colCnt", String(plan.columns.count))
        xml = try setting(xml, element: "sz", attributes: ["width": unit(plan.width), "height": unit(plan.height)])
        xml = try updateXMLZones(xml, plan: plan)
        let sectionXML = (section.xml as NSString).replacingCharacters(in: table.range, with: xml)
        guard sectionXML.utf8.count <= HWPXTextExtractor.maximumEntryBytes else { throw HWPDocumentEditingError.limitExceeded }
        let result = try HWPXEditingArchive(data: package.sourceData).repack(replacing: [section.path: Data(sectionXML.utf8)])
        try verify(HWPXDocumentPackage.load(from: result).blocks, original: package.blocks, plan: plan)
        return result
    }

    private static func unit(_ points: Double) -> String { String(Int((points * 100).rounded())) }
    private static func setting(_ xml: String, element: String, attributes: [String: String]) throws -> String {
        guard let item = try HWPFormattingXML.elements(xml, name: element).first else { throw HWPDocumentEditingError.unsupportedEdit }
        var updated = item.xml
        for (key, value) in attributes { updated = try HWPFormattingXML.setAttribute(updated, key, value) }
        return (xml as NSString).replacingCharacters(in: item.range, with: updated)
    }

    private static func updateXMLZones(_ xml: String, plan: Plan) throws -> String {
        var result = xml
        for zone in try HWPFormattingXML.elements(xml, name: "cellzone").reversed() {
            let startKey = plan.action.isRow ? "startRowAddr" : "startColAddr"
            let endKey = plan.action.isRow ? "endRowAddr" : "endColAddr"
            guard let start = Int(try HWPFormattingXML.attribute(zone.xml, startKey) ?? ""),
                  let end = Int(try HWPFormattingXML.attribute(zone.xml, endKey) ?? ""), end >= start else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            var value = ""
            if let range = plan.interval(start, end - start + 1) {
                value = try HWPFormattingXML.setAttribute(zone.xml, startKey, String(range.start))
                value = try HWPFormattingXML.setAttribute(value, endKey, String(range.start + range.count - 1))
            }
            result = (result as NSString).replacingCharacters(in: zone.range, with: value)
        }
        if let list = try HWPFormattingXML.elements(result, name: "cellzonelist").first {
            let count = try HWPFormattingXML.elements(result, name: "cellzone").count
            result = (result as NSString).replacingCharacters(in: list.range,
                with: try HWPFormattingXML.setAttribute(list.xml, "itemCnt", String(count)))
        }
        return result
    }

    public static func hwp(_ data: Data, blocks: [HWPDocumentBlock], plan: Plan) throws -> Data {
        let container = try OLECompoundFile(data: data)
        let flags = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36)
        guard flags & 0x6796 == 0 else { throw HWPDocumentEditingError.protectedDocument }
        let compressed = flags & 1 != 0
        let paths = container.streamNames.filter { $0.hasPrefix("bodytext/section") }
            .sorted { (Int($0.dropFirst(16)) ?? 0) < (Int($1.dropFirst(16)) ?? 0) }
        var tableNumber = 0, nextInstance: UInt32 = 0
        var sections: [String: [Record]] = [:]
        for path in paths {
            let stored = try container.stream(named: path)
            let bytes = try compressed ? HWP5TextExtractor.inflateRawDeflate(stored, maximumBytes: HWP5TextExtractor.maximumSectionBytes) : stored
            let records = try HWP5DocumentRewriter.parseRecords(bytes)
            sections[path] = records
            for r in records where r.tag == 0x42 && r.payload.count >= 22 { nextInstance = max(nextInstance, try r.payload.hwpWriterUInt32(at: 18)) }
        }
        var replacement: [String: Data] = [:]
        for path in paths {
            guard var records = sections[path] else { continue }
            for control in records.indices where records[control].tag == 0x47 && (try? records[control].payload.hwpWriterUInt32(at: 0)) == 0x7462_6C20 {
                let currentTable = tableNumber; tableNumber += 1
                guard currentTable == plan.table, path.lowercased() == plan.section.lowercased() else { continue }
                let end = records.indices.dropFirst(control + 1).first { records[$0].level <= records[control].level } ?? records.endIndex
                guard let property = (control + 1..<end).first(where: { records[$0].tag == 0x4D }), records[control].payload.count >= 24 else {
                    throw HWPDocumentEditingError.unsupportedEdit
                }
                let oldProperty = records[property].payload
                guard oldProperty.count >= 20 + plan.oldRows.count * 2,
                      word(oldProperty, 4) == plan.oldRows.count, word(oldProperty, 6) == plan.oldColumns.count else {
                    throw HWPDocumentEditingError.unsupportedEdit
                }
                var headers: [(index: Int, offset: Int, address: Address)] = []
                let known = Dictionary(uniqueKeysWithValues: plan.originalCells.map { ($0.source, $0) })
                for index in property + 1..<end where records[index].tag == 0x48 {
                    let bytes = records[index].payload
                    for offset in bytes.count >= 34 ? [8, 6] : [6] where bytes.count >= offset + 26 {
                        let address = Address(row: word(bytes, offset + 2), column: word(bytes, offset))
                        if let cell = known[address], word(bytes, offset + 4) == cell.columnSpan, word(bytes, offset + 6) == cell.rowSpan,
                           abs(Double(try bytes.hwpWriterUInt32(at: offset + 8)) / 100 - (blocks[cell.paragraphs[0]].tableLocation?.cellWidthPoints ?? -1)) < 0.03 {
                            headers.append((index, offset, address)); break
                        }
                    }
                }
                guard headers.count == plan.originalCells.count, let firstHeader = headers.first else { throw HWPDocumentEditingError.unsupportedEdit }
                var owned: [Address: (header: Record, offset: Int, paragraphs: [Record])] = [:]
                for (position, header) in headers.enumerated() {
                    let upper = position + 1 < headers.count ? headers[position + 1].index : end
                    let paragraphs = Array(records[(header.index + 1)..<upper])
                    guard paragraphs.allSatisfy({ [0x42, 0x43, 0x44, 0x45].contains($0.tag) }),
                          paragraphs.filter({ $0.tag == 0x42 }).count == known[header.address]?.paragraphs.count,
                          owned[header.address] == nil else { throw HWPDocumentEditingError.unsupportedEdit }
                    owned[header.address] = (records[header.index], header.offset, paragraphs)
                }
                var inserted: [Record] = []
                var paragraphRecords: [Int: [Record]] = [:]
                for cell in plan.originalCells {
                    guard let source = owned[cell.source] else { throw HWPDocumentEditingError.staleDocument }
                    let roots = source.paragraphs.indices.filter { source.paragraphs[$0].tag == 0x42 }
                    for (offset, root) in roots.enumerated() {
                        let end = offset + 1 < roots.count ? roots[offset + 1] : source.paragraphs.count
                        paragraphRecords[cell.paragraphs[offset]] = Array(source.paragraphs[root..<end])
                    }
                }
                for cell in plan.cells {
                    guard let source = owned[cell.source] else { throw HWPDocumentEditingError.staleDocument }
                    var header = source.header, paragraphs = source.paragraphs
                    let offset = source.offset
                    header.payload.hwpWriterSetUInt16(UInt16(cell.column), at: offset)
                    header.payload.hwpWriterSetUInt16(UInt16(cell.row), at: offset + 2)
                    header.payload.hwpWriterSetUInt16(UInt16(cell.columnSpan), at: offset + 4)
                    header.payload.hwpWriterSetUInt16(UInt16(cell.rowSpan), at: offset + 6)
                    header.payload.hwpWriterSetUInt32(UInt32((plan.width(cell) * 100).rounded()), at: offset + 8)
                    header.payload.hwpWriterSetUInt32(UInt32((plan.height(cell) * 100).rounded()), at: offset + 12)
                    if cell.isNew {
                        guard let first = paragraphs.first, first.tag == 0x42, first.payload.count >= 22,
                              let shape = paragraphs.first(where: { $0.tag == 0x44 }), shape.payload.count >= 8,
                              nextInstance < UInt32.max else { throw HWPDocumentEditingError.unsupportedEdit }
                        nextInstance += 1
                        header.payload.hwpWriterSetUInt16(1, at: 0)
                        var p = first.payload
                        p.hwpWriterSetUInt32(0x8000_0001, at: 0); p.hwpWriterSetUInt32(0, at: 4)
                        p[11] = 0; p.hwpWriterSetUInt16(1, at: 12); p.hwpWriterSetUInt16(0, at: 14); p.hwpWriterSetUInt16(0, at: 16)
                        p.hwpWriterSetUInt32(nextInstance, at: 18)
                        var style = Data(shape.payload.prefix(8)); style.hwpWriterSetUInt32(0, at: 0)
                        paragraphs = [Record(tag: 0x42, level: first.level, payload: p),
                            Record(tag: 0x43, level: first.level + 1, payload: Data([13, 0])),
                            Record(tag: 0x44, level: first.level + 1, payload: style)]
                    } else if cell.paragraphs != known[cell.source]?.paragraphs {
                        paragraphs = try cell.paragraphs.flatMap { index -> [Record] in
                            guard let records = paragraphRecords[index] else { throw HWPDocumentEditingError.staleDocument }
                            return records
                        }
                        header.payload.hwpWriterSetUInt16(UInt16(cell.paragraphs.count), at: 0)
                        let roots = paragraphs.indices.filter { paragraphs[$0].tag == 0x42 }
                        for index in roots {
                            var count = try paragraphs[index].payload.hwpWriterUInt32(at: 0) & 0x7FFF_FFFF
                            if index == roots.last { count |= 0x8000_0000 }
                            paragraphs[index].payload.hwpWriterSetUInt32(count, at: 0)
                        }
                    }
                    inserted.append(header); inserted += paragraphs
                }
                records[property].payload = try tableProperty(oldProperty, plan: plan)
                records[control].payload.hwpWriterSetUInt32(UInt32((plan.width * 100).rounded()), at: 16)
                records[control].payload.hwpWriterSetUInt32(UInt32((plan.height * 100).rounded()), at: 20)
                records.replaceSubrange(firstHeader.index..<end, with: inserted)
                let bytes = records.reduce(into: Data()) { $0.append($1.serialized()) }
                guard bytes.count <= HWP5TextExtractor.maximumSectionBytes else { throw HWPDocumentEditingError.limitExceeded }
                replacement[path] = try compressed ? HWP5DocumentRewriter.rawDeflate(bytes) : bytes
                break
            }
            if !replacement.isEmpty { break }
        }
        guard !replacement.isEmpty else { throw HWPDocumentEditingError.staleDocument }
        if container.containsStream(named: "PrvText") {
            let text = sourceIndices(plan, count: blocks.count).map { $0.map { blocks[$0].text } ?? "" }.joined(separator: "\n")
            replacement["PrvText"] = Data(text.utf16.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] })
        }
        let result = try container.serialized(replacing: replacement)
        try verify(HWP5StructuredDocumentParser.parse(from: result).blocks, original: blocks, plan: plan)
        return result
    }

    private static func word(_ bytes: Data, _ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }
    private static func tableProperty(_ source: Data, plan: Plan) throws -> Data {
        var result = Data(source.prefix(18))
        result.hwpWriterSetUInt16(UInt16(plan.rows.count), at: 4)
        result.hwpWriterSetUInt16(UInt16(plan.columns.count), at: 6)
        // HWP Row Size is the number of cell records starting in each row.
        for row in plan.rows.indices { result.hwpWriterAppendUInt16(UInt16(plan.cells.filter { $0.row == row }.count)) }
        let border = 18 + plan.oldRows.count * 2
        result.append(source[border..<(border + 2)])
        if source.count >= border + 4 {
            let count = word(source, border + 2), start = border + 4
            guard source.count >= start + count * 10 else { throw HWPDocumentEditingError.invalidDocument }
            var zones: [Data] = []
            for index in 0..<count {
                var zone = Data(source[(start + index * 10)..<(start + (index + 1) * 10)])
                let a = plan.action.isRow ? 2 : 0, b = plan.action.isRow ? 6 : 4
                let first = word(zone, a), last = word(zone, b)
                guard last >= first else { throw HWPDocumentEditingError.unsupportedEdit }
                if let interval = plan.interval(first, last - first + 1) {
                    zone.hwpWriterSetUInt16(UInt16(interval.start), at: a)
                    zone.hwpWriterSetUInt16(UInt16(interval.start + interval.count - 1), at: b)
                    zones.append(zone)
                }
            }
            result.hwpWriterAppendUInt16(UInt16(zones.count)); zones.forEach { result.append($0) }
            result.append(source.dropFirst(start + count * 10))
        }
        return result
    }
}
