import Foundation

nonisolated enum HWPTableLayoutWriter {
    struct Change {
        let original: HWPDocumentTableLocation
        let edited: HWPDocumentTableLocation
    }

    private static func changes(_ originals: [HWPDocumentBlock], _ edited: [HWPDocumentBlock]) throws -> [Int: Change] {
        guard originals.count == edited.count else { throw HWPDocumentEditingError.staleDocument }
        var result: [Int: Change] = [:]
        for (old, new) in zip(originals, edited) {
            guard old.id == new.id else { throw HWPDocumentEditingError.staleDocument }
            guard let a = old.tableLocation, let b = new.tableLocation,
                  a.cellHeightPoints != b.cellHeightPoints
                    || a.tablePlacement?.heightPoints != b.tablePlacement?.heightPoints else { continue }
            guard a.table == b.table, a.row == b.row, a.column == b.column,
                  a.rowSpan == b.rowSpan, a.columnSpan == b.columnSpan,
                  let height = b.cellHeightPoints, height.isFinite, height > 0, height <= 4_000,
                  b.tablePlacement?.heightPoints.isFinite != false,
                  (b.tablePlacement?.heightPoints ?? 1) > 0,
                  (b.tablePlacement?.heightPoints ?? 1) <= 4_000 else {
                throw HWPDocumentEditingError.limitExceeded
            }
            result[old.paragraphIndex] = Change(original: a, edited: b)
        }
        return result
    }

    static func applyHWPX(_ data: Data, originals: [HWPDocumentBlock], edited: [HWPDocumentBlock]) throws -> Data {
        let changes = try changes(originals, edited)
        guard !changes.isEmpty else { return data }
        let package = try HWPXDocumentPackage.load(from: data)
        var replacements: [String: Data] = [:]
        var applied: Set<Int> = []
        for section in package.sections {
            let xml = section.xml as NSString
            let tokens = try HWPXParagraphXMLPatcher.tagTokens(in: section.xml)
            var stack: [String] = [], tableStack: [Int] = [], nextTable = 0, ordinal = 0
            struct Cell { var size: NSRange?; var ordinals: [Int] = [] }
            var cells: [Cell] = []
            var tableSizes: [Int: NSRange] = [:]
            var tableSizeInsertions: [Int: (NSRange, String)] = [:]
            var tableChanges: [Int: Double] = [:]
            var patches: [Int: (NSRange, String)] = [:]
            for token in tokens {
                if token.isClosing {
                    if token.localName == "tc", let cell = cells.popLast() {
                        let targets = cell.ordinals.compactMap { changes[$0] }
                        if let target = targets.first {
                            guard targets.allSatisfy({ $0.edited.cellHeightPoints == target.edited.cellHeightPoints }) else {
                                throw HWPDocumentEditingError.cannotSave
                            }
                            let value = String(Int((target.edited.cellHeightPoints! * 100).rounded()))
                            if let range = cell.size {
                                patches[range.location] = (range,
                                    try HWPFormattingXML.setAttribute(xml.substring(with: range), "height", value))
                            } else {
                                let prefix = token.qualifiedName.contains(":")
                                    ? String(token.qualifiedName.prefix { $0 != ":" }) + ":" : ""
                                let insertion = NSRange(location: token.range.location, length: 0)
                                patches[insertion.location] = (insertion, "<\(prefix)cellSz height=\"\(value)\"/>")
                            }
                            applied.formUnion(cell.ordinals.filter { changes[$0] != nil })
                        }
                    }
                    if token.localName == "tbl", let table = tableStack.popLast() {
                        let prefix = token.qualifiedName.contains(":")
                            ? String(token.qualifiedName.prefix { $0 != ":" }) + ":" : ""
                        tableSizeInsertions[table] = (NSRange(location: token.range.location, length: 0), prefix)
                    }
                    _ = stack.popLast()
                    continue
                }
                if token.localName == "tbl" { tableStack.append(nextTable); nextTable += 1 }
                if token.localName == "tc" { cells.append(Cell()) }
                if token.localName == "cellsz", !cells.isEmpty { cells[cells.count - 1].size = token.range }
                if token.localName == "sz", stack.last == "tbl", let table = tableStack.last { tableSizes[table] = token.range }
                if token.localName == "p" {
                    guard ordinal < section.blocks.count else { throw HWPDocumentEditingError.cannotSave }
                    let number = section.blocks[ordinal].paragraphIndex
                    ordinal += 1
                    if !cells.isEmpty { cells[cells.count - 1].ordinals.append(number) }
                    if let change = changes[number], let height = change.edited.tablePlacement?.heightPoints {
                        tableChanges[change.edited.table] = height
                    }
                }
                if !token.isSelfClosing { stack.append(token.localName) }
            }
            for (table, height) in tableChanges {
                let value = String(Int((height * 100).rounded()))
                if let range = tableSizes[table] {
                    patches[range.location] = (range,
                        try HWPFormattingXML.setAttribute(xml.substring(with: range), "height", value))
                } else if let (insertion, prefix) = tableSizeInsertions[table] {
                    patches[insertion.location] = (insertion, "<\(prefix)sz height=\"\(value)\"/>")
                } else {
                    throw HWPDocumentEditingError.cannotSave
                }
            }
            var output = section.xml
            for (range, value) in patches.values.sorted(by: { $0.0.location > $1.0.location }) {
                output = (output as NSString).replacingCharacters(in: range, with: value)
            }
            if output != section.xml { replacements[section.path] = Data(output.utf8) }
        }
        guard applied == Set(changes.keys) else { throw HWPDocumentEditingError.cannotSave }
        let result = try HWPXEditingArchive(data: data).repack(replacing: replacements)
        try verify(try HWPXDocumentPackage.load(from: result).blocks, changes: changes)
        return result
    }

    static func applyHWP(_ data: Data, originals: [HWPDocumentBlock], edited: [HWPDocumentBlock]) throws -> Data {
        let changes = try changes(originals, edited)
        guard !changes.isEmpty else { return data }
        let container = try OLECompoundFile(data: data)
        let compressed = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36) & 1 != 0
        let paths = container.streamNames.filter { $0.hasPrefix("bodytext/section") }
            .sorted { (Int($0.dropFirst(16)) ?? 0) < (Int($1.dropFirst(16)) ?? 0) }
        var replacements: [String: Data] = [:], ordinal = 0
        var applied: Set<Int> = []
        for path in paths {
            let stored = try container.stream(named: path)
            let expanded = try compressed ? HWP5TextExtractor.inflateRawDeflate(stored,
                maximumBytes: HWP5TextExtractor.maximumSectionBytes) : stored
            var records = try HWP5DocumentRewriter.parseRecords(expanded)
            var changed = false
            for index in records.indices where records[index].tag == 0x42 {
                let number = ordinal
                ordinal += 1
                guard let change = changes[number] else { continue }
                // The cell LIST_HEADER immediately owns its paragraph list.
                // Validate the entire address and old dimensions before patching.
                let level = records[index].level
                guard level > 0 else { throw HWPDocumentEditingError.cannotSave }
                let candidates = records.indices.prefix(index).reversed().prefix { records[$0].level >= level - 1 }
                var match: (Int, Int)?
                for candidate in candidates where records[candidate].tag == 0x48 {
                    let payload = records[candidate].payload
                    for offset in payload.count >= 34 ? [8, 6] : [6] where payload.count >= offset + 26 {
                        let old = change.original
                        func word(_ at: Int) -> Int { Int(payload[at]) | (Int(payload[at + 1]) << 8) }
                        if word(offset) == old.column,
                           word(offset + 2) == old.row,
                           word(offset + 4) == old.columnSpan,
                           word(offset + 6) == old.rowSpan,
                           try abs(Double(payload.hwpWriterUInt32(at: offset + 8)) / 100 - (old.cellWidthPoints ?? -1)) < 0.02 {
                            match = (candidate, offset); break
                        }
                    }
                    if match != nil { break }
                }
                guard let (cellIndex, offset) = match else { throw HWPDocumentEditingError.cannotSave }
                records[cellIndex].payload.hwpWriterSetUInt32(UInt32((change.edited.cellHeightPoints! * 100).rounded()), at: offset + 12)
                if let height = change.edited.tablePlacement?.heightPoints {
                    guard let control = records.indices.prefix(cellIndex).reversed().first(where: {
                        records[$0].tag == 0x47 && records[$0].level < records[cellIndex].level
                            && (try? records[$0].payload.hwpWriterUInt32(at: 0)) == 0x7462_6C20
                    }), records[control].payload.count >= 24 else { throw HWPDocumentEditingError.cannotSave }
                    records[control].payload.hwpWriterSetUInt32(UInt32((height * 100).rounded()), at: 20)
                }
                changed = true
                applied.insert(number)
            }
            if changed {
                let payload = records.reduce(into: Data()) { $0.append($1.serialized()) }
                replacements[path] = try compressed ? HWP5DocumentRewriter.rawDeflate(payload) : payload
            }
        }
        guard applied == Set(changes.keys) else { throw HWPDocumentEditingError.cannotSave }
        let result = try container.serialized(replacing: replacements)
        try verify(try HWP5StructuredDocumentParser.parse(from: result).blocks, changes: changes)
        return result
    }

    private static func verify(_ blocks: [HWPDocumentBlock], changes: [Int: Change]) throws {
        for block in blocks {
            guard let expected = changes[block.paragraphIndex]?.edited else { continue }
            guard let actual = block.tableLocation,
                  abs((actual.cellHeightPoints ?? -1) - (expected.cellHeightPoints ?? -2)) < 0.02,
                  abs((actual.tablePlacement?.heightPoints ?? 0) - (expected.tablePlacement?.heightPoints ?? 0)) < 0.02 else {
                throw HWPDocumentEditingError.cannotSave
            }
        }
    }
}
