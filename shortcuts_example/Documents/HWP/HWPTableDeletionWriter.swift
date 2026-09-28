import Foundation

nonisolated enum HWPTableDeletionWriter {
    typealias Plan = HWPTableDeletion.Plan
    typealias Record = HWP5DocumentRewriter.Record
    static func apply(_ plan: Plan, to source: HWPTableStructureDocument) throws -> Data {
        switch source {
        case .hwpx(let package): return try hwpx(plan, package: package)
        case .hwp(_, let data): return try hwp(plan, data: data, blocks: source.blocks)
        }
    }
    private static func hwpx(_ plan: Plan, package: HWPXDocumentPackage) throws -> Data {
        guard let section = package.sections.first(where: { $0.path == plan.table.section }) else { throw HWPDocumentEditingError.staleDocument }
        let tables = try HWPFormattingXML.elements(section.xml, name: "tbl")
        guard tables.indices.contains(plan.table.table) else { throw HWPDocumentEditingError.staleDocument }
        let table = tables[plan.table.table]
        let owner = package.blocks[plan.owner]
        guard let local = section.blocks.firstIndex(where: { $0.id == owner.id }) else { throw HWPDocumentEditingError.staleDocument }
        let paragraphs = try HWPXParagraphXMLPatcher.paragraphRanges(in: section.xml)
        guard paragraphs.indices.contains(local), NSLocationInRange(table.range.location, paragraphs[local]),
              NSMaxRange(table.range) <= NSMaxRange(paragraphs[local]),
              try HWPFormattingXML.elements(table.xml, name: "tbl").count == 1,
              try HWPFormattingXML.elements(table.xml, name: "p").count == plan.removed.count else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        // Keep the containing run/paragraph, including text, section properties,
        // page numbering and style references. Unused shared resources may still
        // belong to other objects, so the archive's assets remain untouched.
        let xml = (section.xml as NSString).replacingCharacters(in: table.range, with: "")
        let archive = try HWPXEditingArchive(data: package.sourceData)
        var replacements = [section.path: Data(xml.utf8)]
        if archive.paths.contains("Preview/PrvText.txt") {
            let preview = plan.retained(count: package.blocks.count).map { package.blocks[$0].text }.joined(separator: "\n")
            replacements["Preview/PrvText.txt"] = Data(preview.utf8)
        }
        return try archive.repack(replacing: replacements)
    }
    private static func hwp(_ plan: Plan, data: Data, blocks: [HWPDocumentBlock]) throws -> Data {
        let container = try OLECompoundFile(data: data)
        let flags = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36)
        guard flags & 0x6796 == 0 else { throw HWPDocumentEditingError.protectedDocument }
        let paths = container.streamNames.filter { $0.hasPrefix("bodytext/section") }
            .sorted { (HWPPageSetup.sectionIndex($0) ?? 0) < (HWPPageSetup.sectionIndex($1) ?? 0) }
        var tableNumber = 0, ordinal = 0
        for path in paths {
            let stored = try container.stream(named: path)
            let expanded = try flags & 1 != 0 ? HWP5TextExtractor.inflateRawDeflate(stored, maximumBytes: HWP5TextExtractor.maximumSectionBytes) : stored
            var records = try HWP5DocumentRewriter.parseRecords(expanded)
            var owner: Int?, ownerOrdinal: Int?
            for index in records.indices {
                let record = records[index]
                if record.tag == 0x42 {
                    if record.level == 0 { owner = index; ownerOrdinal = ordinal }
                    ordinal += 1
                }
                guard record.tag == 0x47, (try? record.payload.hwpWriterUInt32(at: 0)) == 0x7462_6C20 else { continue }
                let number = tableNumber; tableNumber += 1
                guard number == plan.table.table, path == plan.table.section.lowercased() else { continue }
                guard let owner, ownerOrdinal == blocks[plan.owner].paragraphIndex, record.level == 1,
                      records[owner].payload.count >= 22 else { throw HWPDocumentEditingError.unsupportedEdit }
                let end = records.indices.dropFirst(index + 1).first { records[$0].level <= record.level } ?? records.endIndex
                guard records[(index + 1)..<end].filter({ $0.tag == 0x42 }).count == plan.removed.count else { throw HWPDocumentEditingError.unsupportedEdit }
                let ownerEnd = records.indices.dropFirst(owner + 1).first { records[$0].level == 0 } ?? records.endIndex
                let direct = (owner + 1..<ownerEnd).filter { records[$0].level == 1 }
                let texts = direct.filter { records[$0].tag == 0x43 }
                guard texts.count == 1, let text = texts.first,
                      !direct.contains(where: { records[$0].tag == 0x46 }) else { throw HWPDocumentEditingError.unsupportedEdit }
                var bytes = records[text].payload
                guard bytes.count.isMultiple(of: 2) else { throw HWPDocumentEditingError.invalidDocument }
                var cursor = 0, anchors: [Int] = [], mask: UInt32 = 0
                while cursor < bytes.count / 2 {
                    let code = try bytes.hwpWriterUInt16(at: cursor * 2)
                    let size = code >= 1 && code <= 23 && code != 10 && code != 13 ? 8 : 1
                    guard cursor + size <= bytes.count / 2 else { throw HWPDocumentEditingError.invalidDocument }
                    let table = try code == 11 && bytes.hwpWriterUInt32(at: cursor * 2 + 2) == 0x7462_6C20
                    if table { anchors.append(cursor) }
                    else if code > 0 && code < 32 && code != 13 { mask |= 1 << UInt32(code) }
                    cursor += size
                }
                guard anchors.count == 1, let anchor = anchors.first else { throw HWPDocumentEditingError.unsupportedEdit }
                bytes.removeSubrange((anchor * 2)..<((anchor + 8) * 2))
                records[text].payload = bytes
                let last = try records[owner].payload.hwpWriterUInt32(at: 0) & 0x8000_0000
                records[owner].payload.hwpWriterSetUInt32(last | UInt32(bytes.count / 2), at: 0)
                records[owner].payload.hwpWriterSetUInt32(mask, at: 4)
                func mapped(_ position: UInt32) -> UInt32 { position <= UInt32(anchor) ? position : position < UInt32(anchor + 8) ? UInt32(anchor) : position - 8 }
                for item in direct where records[item].tag == 0x44 || records[item].tag == 0x45 {
                    let stride = records[item].tag == 0x44 ? 8 : 36
                    let payload = records[item].payload
                    guard payload.count.isMultiple(of: stride) else { throw HWPDocumentEditingError.invalidDocument }
                    var entries: [Data] = []
                    for offset in Swift.stride(from: 0, to: payload.count, by: stride) {
                        var entry = payload.subdata(in: offset..<(offset + stride))
                        let position = mapped(try entry.hwpWriterUInt32(at: 0))
                        entry.hwpWriterSetUInt32(position, at: 0)
                        if records[item].tag == 0x44, let last = entries.last, try last.hwpWriterUInt32(at: 0) == position { entries.removeLast() }
                        entries.append(entry)
                    }
                    guard entries.count <= Int(UInt16.max) else { throw HWPDocumentEditingError.limitExceeded }
                    records[item].payload = entries.reduce(into: Data()) { $0.append($1) }
                    records[owner].payload.hwpWriterSetUInt16(UInt16(entries.count), at: stride == 8 ? 12 : 16)
                }
                records.removeSubrange(index..<end)
                let payload = records.reduce(into: Data()) { $0.append($1.serialized()) }
                var replacements = [path: try flags & 1 != 0 ? HWP5DocumentRewriter.rawDeflate(payload) : payload]
                if container.containsStream(named: "PrvText") {
                    let text = plan.retained(count: blocks.count).map { blocks[$0].text }.joined(separator: "\n")
                    replacements["PrvText"] = Data(text.utf16.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] })
                }
                return try container.serialized(replacing: replacements)
            }
        }
        throw HWPDocumentEditingError.staleDocument
    }
}
