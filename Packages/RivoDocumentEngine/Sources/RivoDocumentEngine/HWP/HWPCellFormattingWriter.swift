import Foundation

/// Clone shared border/fill definitions and change only the owning cell reference.
public nonisolated enum HWPCellFormattingWriter {
    private struct Change {
        let original: HWPDocumentBlock
        let edited: HWPDocumentBlock
    }

    private static func changes(_ originals: [HWPDocumentBlock], _ edited: [HWPDocumentBlock]) throws -> [Int: Change] {
        guard originals.count == edited.count else { throw HWPDocumentEditingError.staleDocument }
        var result: [Int: Change] = [:]
        for (old, new) in zip(originals, edited) {
            guard old.id == new.id else { throw HWPDocumentEditingError.staleDocument }
            guard !HWPCellFormatting.matches(old, new) else { continue }
            guard HWPCellFormatting.sameCell(old, new), let a = old.tableLocation, let b = new.tableLocation,
                  a.rowSpan == b.rowSpan, a.columnSpan == b.columnSpan,
                  [.start, .center, .end].contains(b.cellVerticalAlignment) else { throw HWPDocumentEditingError.unsupportedEdit }
            result[old.paragraphIndex] = Change(original: old, edited: new)
        }
        for change in result.values {
            guard edited.filter({ HWPCellFormatting.sameCell($0, change.edited) }).allSatisfy({
                HWPCellFormatting.matches($0, change.edited)
            }) else { throw HWPDocumentEditingError.staleDocument }
        }
        return result
    }

    private static func verify(_ saved: [HWPDocumentBlock], changes: [Int: Change]) throws {
        guard Set(saved.map(\.paragraphIndex)).isSuperset(of: changes.keys) else { throw HWPDocumentEditingError.cannotSave }
        for block in saved {
            if let change = changes[block.paragraphIndex], !HWPCellFormatting.matches(block, change.edited) {
                throw HWPDocumentEditingError.cannotSave
            }
        }
    }

    public static func applyHWPX(_ data: Data, originals: [HWPDocumentBlock], edited: [HWPDocumentBlock]) throws -> Data {
        let changes = try changes(originals, edited)
        guard !changes.isEmpty else { return data }
        let archive = try HWPXEditingArchive(data: data)
        var header = String(decoding: try archive.data(at: "Contents/header.xml"), as: UTF8.self)
        let prefix = try HWPFormattingXML.prefix(header)
        var definitions = try HWPFormattingXML.dictionary(header, name: "borderfill")
        let fallback = try defaultBorder(prefix: prefix)
        var nextID = (definitions.keys.compactMap(Int.init).max() ?? 0) + 1
        var additions = "", cache: [String: String] = [:]
        func styleID(_ baseID: String, _ change: Change) throws -> String {
            let old = HWPCellFormat(change.original.tableLocation!), new = HWPCellFormat(change.edited.tableLocation!)
            if old.box == new.box { return baseID }
            let source = definitions[baseID] ?? fallback
            var xml = source
            for (index, name) in ["leftBorder", "rightBorder", "topBorder", "bottomBorder"].enumerated()
                where old.borders[index] != new.borders[index] {
                let line = new.borders[index]
                let type: String = !line.isVisible ? "NONE" : [1: "SOLID", 2: "DASH", 3: "DOT", 4: "DASH_DOT", 6: "DOUBLE_SLIM"][Int(line.kind)] ?? "SOLID"
                let element = "<\(prefix)\(name) type=\"\(type)\" width=\"\(String(format: "%.4f", line.widthPoints * 25.4 / 72)) mm\" color=\"\(String(format: "#%06X", line.colorRGB))\"/>"
                xml = try HWPFormattingXML.replaceOrAppend(xml, name: name.lowercased(), replacement: element)
            }
            if old.box.backgroundColorRGB != new.box.backgroundColorRGB || old.box.backgroundImage != new.box.backgroundImage {
                let fill = new.box.backgroundColorRGB.map {
                    "<hc:fillBrush xmlns:hc=\"http://www.hancom.co.kr/hwpml/2011/core\"><hc:winBrush faceColor=\"\(String(format: "#%06X", $0))\" hatchColor=\"#000000\" hatchStyle=\"NONE\" alpha=\"0\"/></hc:fillBrush>"
                } ?? ""
                xml = try HWPFormattingXML.replaceOrAppend(xml, name: "fillbrush", replacement: fill)
            }
            guard xml != source else { return baseID }
            let key = try HWPFormattingXML.setAttribute(xml, "id", "")
            if let id = cache[key] { return id }
            guard nextID < 65_535 else { throw HWPDocumentEditingError.limitExceeded }
            let id = String(nextID); nextID += 1
            xml = try HWPFormattingXML.setAttribute(xml, "id", id)
            additions += xml; definitions[id] = xml; cache[key] = id
            return id
        }

        let package = try HWPXDocumentPackage.load(from: data)
        var replacements: [String: Data] = [:], applied: Set<Int> = []
        for section in package.sections {
            let source = section.xml as NSString
            struct Cell { let opening: NSRange; let borderID: String; var sublist: NSRange?; var ordinals: [Int] = [] }
            var cells: [Cell] = [], stack: [String] = [], tableBorders: [String] = [], ordinal = 0
            var patches: [Int: (NSRange, String)] = [:]
            for token in try HWPXParagraphXMLPatcher.tagTokens(in: section.xml) {
                if token.isClosing {
                    if token.localName == "tc", let cell = cells.popLast(),
                       let number = cell.ordinals.first(where: { changes[$0] != nil }), let change = changes[number] {
                        let original = change.original.tableLocation!, target = change.edited.tableLocation!
                        var opening = source.substring(with: cell.opening)
                        let oldID = cell.borderID
                        let id = try styleID(oldID, change)
                        if id != oldID {
                            opening = try HWPFormattingXML.setAttribute(opening, "borderFillIDRef", id)
                            patches[cell.opening.location] = (cell.opening, opening)
                        }
                        if original.cellVerticalAlignment != target.cellVerticalAlignment {
                            guard let range = cell.sublist else { throw HWPDocumentEditingError.unsupportedEdit }
                            let value = target.cellVerticalAlignment == .center ? "CENTER" : target.cellVerticalAlignment == .end ? "BOTTOM" : "TOP"
                            patches[range.location] = (range, try HWPFormattingXML.setAttribute(source.substring(with: range), "vertAlign", value))
                        }
                        applied.formUnion(cell.ordinals.filter { changes[$0] != nil })
                    }
                    if token.localName == "tbl" { _ = tableBorders.popLast() }
                    _ = stack.popLast(); continue
                }
                if token.localName == "tbl" { tableBorders.append(try HWPFormattingXML.attribute(source.substring(with: token.range), "borderFillIDRef") ?? "0") }
                if token.localName == "tc" {
                    let id = try HWPFormattingXML.attribute(source.substring(with: token.range), "borderFillIDRef") ?? tableBorders.last ?? "0"
                    cells.append(Cell(opening: token.range, borderID: id))
                }
                if token.localName == "sublist", stack.last == "tc", !cells.isEmpty { cells[cells.count - 1].sublist = token.range }
                if token.localName == "p" {
                    guard ordinal < section.blocks.count else { throw HWPDocumentEditingError.cannotSave }
                    if !cells.isEmpty { cells[cells.count - 1].ordinals.append(section.blocks[ordinal].paragraphIndex) }
                    ordinal += 1
                }
                if !token.isSelfClosing { stack.append(token.localName) }
            }
            var output = section.xml
            for (range, value) in patches.values.sorted(by: { $0.0.location > $1.0.location }) {
                output = (output as NSString).replacingCharacters(in: range, with: value)
            }
            if output != section.xml { replacements[section.path] = Data(output.utf8) }
        }
        guard applied == Set(changes.keys) else { throw HWPDocumentEditingError.cannotSave }
        if !additions.isEmpty {
            header = try HWPFormattingXML.appendToGroup(header, name: "borderfills", additions: additions, count: definitions.count)
            replacements["Contents/header.xml"] = Data(header.utf8)
        }
        let result = try archive.repack(replacing: replacements)
        try verify(HWPXDocumentPackage.load(from: result).blocks, changes: changes)
        return result
    }

    private static func defaultBorder(prefix: String) throws -> String {
        let header = LegacyHWPXConverter.headerXML.replacingOccurrences(of: "hh:", with: prefix)
        guard let xml = try HWPFormattingXML.elements(header, name: "borderfill").first?.xml else {
            throw HWPDocumentEditingError.invalidDocument
        }
        return xml
    }

    public static func applyHWP(_ data: Data, originals: [HWPDocumentBlock], edited: [HWPDocumentBlock]) throws -> Data {
        let changes = try changes(originals, edited)
        guard !changes.isEmpty else { return data }
        let container = try OLECompoundFile(data: data)
        let compressed = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36) & 1 != 0
        func expanded(_ value: Data) throws -> Data {
            try compressed ? HWP5TextExtractor.inflateRawDeflate(value, maximumBytes: HWP5TextExtractor.maximumSectionBytes) : value
        }
        var info = try HWP5DocumentRewriter.parseRecords(expanded(container.stream(named: "DocInfo")))
        var definitions = info.filter { $0.tag == 0x14 }.map(\.payload)
        let originalCount = definitions.count
        func styleID(_ id: Int, _ change: Change) throws -> Int {
            let old = HWPCellFormat(change.original.tableLocation!), new = HWPCellFormat(change.edited.tableLocation!)
            if old.box == new.box { return id }
            guard id > 0, definitions.indices.contains(id - 1) else { throw HWPDocumentEditingError.unsupportedEdit }
            var bytes = definitions[id - 1]
            guard bytes.count >= 36 else { throw HWPDocumentEditingError.invalidDocument }
            let widths = [0.1, 0.12, 0.15, 0.2, 0.25, 0.3, 0.4, 0.5, 0.6, 0.7, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0]
            func colorRef(_ rgb: UInt32) -> UInt32 { (rgb & 255) << 16 | (rgb & 0xFF00) | (rgb >> 16 & 255) }
            for index in 0..<4 where old.borders[index] != new.borders[index] {
                let line = new.borders[index], offset = 2 + index * 6
                let mm = line.widthPoints * 25.4 / 72
                let width = widths.indices.min(by: { abs(widths[$0] - mm) < abs(widths[$1] - mm) })!
                guard !line.isVisible || abs(widths[width] - mm) < 0.01 else { throw HWPDocumentEditingError.unsupportedEdit }
                bytes[offset] = line.isVisible ? line.kind : 0
                bytes[offset + 1] = UInt8(width)
                bytes.hwpWriterSetUInt32(colorRef(line.colorRGB), at: offset + 2)
            }
            if old.box.backgroundColorRGB != new.box.backgroundColorRGB || old.box.backgroundImage != new.box.backgroundImage {
                bytes = Data(bytes.prefix(32))
                bytes.hwpWriterAppendUInt32(new.box.backgroundColorRGB == nil ? 0 : 1)
                if let color = new.box.backgroundColorRGB {
                    bytes.hwpWriterAppendUInt32(colorRef(color))
                    bytes.hwpWriterAppendUInt32(0)
                    bytes.hwpWriterAppendUInt32(UInt32.max) // no hatch
                }
                bytes.hwpWriterAppendUInt32(0) // extra fill properties length
                bytes.append(0) // fully opaque alpha
            }
            if let index = definitions.firstIndex(of: bytes) { return index + 1 }
            guard definitions.count < 65_534 else { throw HWPDocumentEditingError.limitExceeded }
            definitions.append(bytes); return definitions.count
        }
        let paths = container.streamNames.filter { $0.hasPrefix("bodytext/section") }
            .sorted { (Int($0.dropFirst(16)) ?? 0) < (Int($1.dropFirst(16)) ?? 0) }
        var replacements: [String: Data] = [:], ordinal = 0, applied: Set<Int> = []
        for path in paths {
            var records = try HWP5DocumentRewriter.parseRecords(expanded(container.stream(named: path)))
            var patchedCells: Set<Int> = []
            for index in records.indices where records[index].tag == 0x42 {
                let number = ordinal; ordinal += 1
                guard let change = changes[number] else { continue }
                let level = records[index].level
                guard level > 0 else { throw HWPDocumentEditingError.cannotSave }
                let old = change.original.tableLocation!, new = change.edited.tableLocation!
                var owner: (Int, Int)?
                for candidate in records.indices.prefix(index).reversed().prefix(while: { records[$0].level >= level - 1 }) where records[candidate].tag == 0x48 {
                    let bytes = records[candidate].payload
                    for offset in bytes.count >= 34 ? [8, 6] : [6] where bytes.count >= offset + 26 {
                        func word(_ p: Int) -> Int { Int(bytes[p]) | Int(bytes[p + 1]) << 8 }
                        if word(offset) == old.column, word(offset + 2) == old.row,
                           word(offset + 4) == old.columnSpan, word(offset + 6) == old.rowSpan,
                           try abs(Double(bytes.hwpWriterUInt32(at: offset + 8)) / 100 - (old.cellWidthPoints ?? -1)) < 0.02 {
                            owner = (candidate, offset); break
                        }
                    }
                    if owner != nil { break }
                }
                guard let (cell, offset) = owner else { throw HWPDocumentEditingError.cannotSave }
                if !patchedCells.contains(cell) {
                    var id = Int(records[cell].payload[offset + 24]) | Int(records[cell].payload[offset + 25]) << 8
                    if id == 0, old.boxStyle != new.boxStyle,
                       let table = records.indices.prefix(cell).reversed().first(where: { records[$0].tag == 0x4D && records[$0].level <= records[cell].level }) {
                        let payload = records[table].payload
                        if payload.count >= 6 {
                            let rows = Int(payload[4]) | Int(payload[5]) << 8
                            let at = 18 + rows * 2
                            if payload.count >= at + 2 { id = Int(payload[at]) | Int(payload[at + 1]) << 8 }
                        }
                    }
                    records[cell].payload.hwpWriterSetUInt16(UInt16(try styleID(id, change)), at: offset + 24)
                    if old.cellVerticalAlignment != new.cellVerticalAlignment {
                        let position = offset == 8 ? 4 : 2
                        let flags = try records[cell].payload.hwpWriterUInt32(at: position)
                        let alignment: UInt32 = new.cellVerticalAlignment == .center ? 1 : new.cellVerticalAlignment == .end ? 2 : 0
                        records[cell].payload.hwpWriterSetUInt32(flags & ~UInt32(3 << 5) | alignment << 5, at: position)
                    }
                    patchedCells.insert(cell)
                }
                applied.insert(number)
            }
            if !patchedCells.isEmpty {
                let bytes = records.reduce(into: Data()) { $0.append($1.serialized()) }
                replacements[path] = try compressed ? HWP5DocumentRewriter.rawDeflate(bytes) : bytes
            }
        }
        guard applied == Set(changes.keys) else { throw HWPDocumentEditingError.cannotSave }
        if definitions.count != originalCount {
            guard let mapping = info.firstIndex(where: { $0.tag == 0x11 }), info[mapping].payload.count >= 36 else { throw HWPDocumentEditingError.invalidDocument }
            info[mapping].payload.hwpWriterSetUInt32(UInt32(definitions.count), at: 8 * 4)
            let insertion = info.firstIndex(where: { $0.tag > 0x14 }) ?? info.endIndex
            info.insert(contentsOf: definitions.dropFirst(originalCount).map { HWP5DocumentRewriter.Record(tag: 0x14, level: 0, payload: $0) }, at: insertion)
            let bytes = info.reduce(into: Data()) { $0.append($1.serialized()) }
            replacements["DocInfo"] = try compressed ? HWP5DocumentRewriter.rawDeflate(bytes) : bytes
        }
        let result = try container.serialized(replacing: replacements)
        try verify(HWP5StructuredDocumentParser.parse(from: result).blocks, changes: changes)
        return result
    }
}
