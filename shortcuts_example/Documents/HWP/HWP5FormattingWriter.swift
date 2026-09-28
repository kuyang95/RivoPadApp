import Foundation

/// Appends cloned style records so shared original styles never change.
nonisolated enum HWP5FormattingWriter {
    typealias Record = HWP5DocumentRewriter.Record

    static func apply(to data: Data, originals: [HWPDocumentBlock], edited: [HWPDocumentBlock]) throws -> Data {
        let changes = Dictionary(uniqueKeysWithValues: zip(originals, edited).filter {
            HWPDocumentFormatting.hasChanges(from: $0, to: $1)
        }.map { ($0.0.paragraphIndex, $0.1) })
        guard !changes.isEmpty else { return data }
        guard changes.values.allSatisfy(\.isEditable) else { throw HWPDocumentEditingError.unsupportedEdit }
        let container = try OLECompoundFile(data: data)
        let fileHeader = try container.stream(named: "FileHeader")
        let compressed = try fileHeader.hwpWriterUInt32(at: 36) & 1 != 0
        func expanded(_ data: Data) throws -> Data {
            try compressed ? HWP5TextExtractor.inflateRawDeflate(data, maximumBytes: HWP5TextExtractor.maximumSectionBytes) : data
        }
        var info = try HWP5DocumentRewriter.parseRecords(expanded(container.stream(named: "DocInfo")))
        guard let mapping = info.firstIndex(where: { $0.tag == 0x11 }), info[mapping].payload.count >= 56 else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        var characters = info.filter { $0.tag == 0x15 }.map(\.payload)
        var paragraphs = info.filter { $0.tag == 0x19 }.map(\.payload)
        let originalCharCount = characters.count, originalParaCount = paragraphs.count
        var numbers = info.filter { $0.tag == 0x17 }.map(\.payload)
        var bullets = info.filter { $0.tag == 0x18 }.map(\.payload)
        let oldNumberCount = numbers.count, oldBulletCount = bullets.count
        var listIDs: [String: Int] = [:]
        func listID(_ list: HWPParagraphList) throws -> Int {
            let key = "\(list.kind.rawValue):\(list.definitionID)"
            if let cached = listIDs[key] { return cached }
            let count = list.kind == .number ? numbers.count : bullets.count
            if let id = Int(list.definitionID), id > 0, id <= count { return id }
            guard count < 65_534 else { throw HWPDocumentEditingError.limitExceeded }
            let data = try HWPListBinary.definition(list)
            if list.kind == .number { numbers.append(data) } else { bullets.append(data) }
            listIDs[key] = count + 1
            return count + 1
        }
        let faces = info.filter { $0.tag == 0x13 }.map(\.payload)
        var languageFonts: [[Data]] = [], start = 0
        for language in 0..<7 {
            let count = Int(try info[mapping].payload.hwpWriterUInt32(at: (language + 1) * 4))
            guard count <= faces.count - start else { throw HWPDocumentEditingError.invalidDocument }
            languageFonts.append(Array(faces[start..<(start + count)])); start += count
        }
        guard start == faces.count else { throw HWPDocumentEditingError.invalidDocument }
        let current = try HWP5StructuredDocumentParser.parse(from: data)
        let currentByIndex = Dictionary(uniqueKeysWithValues: current.blocks.map { ($0.paragraphIndex, $0) })
        func fontID(_ name: String, language: Int) throws -> UInt16 {
            if let index = languageFonts[language].firstIndex(where: { fontName($0) == name }) { return UInt16(index) }
            guard name.utf16.count <= 255, languageFonts[language].count < Int(UInt16.max) else {
                throw HWPDocumentEditingError.limitExceeded
            }
            var payload = Data([0])
            payload.hwpWriterAppendUInt16(UInt16(name.utf16.count))
            for unit in name.utf16 { payload.hwpWriterAppendUInt16(unit) }
            languageFonts[language].append(payload)
            return UInt16(languageFonts[language].count - 1)
        }
        var replacements: [String: Data] = [:], ordinal = 0
        let paths = container.streamNames.filter { $0.hasPrefix("bodytext/section") }
            .sorted { (Int($0.dropFirst(16)) ?? 0) < (Int($1.dropFirst(16)) ?? 0) }
        for path in paths {
            var records = try HWP5DocumentRewriter.parseRecords(expanded(container.stream(named: path)))
            var changed = false
            // Match the parser's global paragraph order, including nested cells.
            for index in records.indices where records[index].tag == 0x42 {
                let paragraphIndex = ordinal
                ordinal += 1
                guard let block = changes[paragraphIndex], let before = currentByIndex[paragraphIndex] else { continue }
                guard records[index].payload.count >= 22 else { throw HWPDocumentEditingError.invalidDocument }
                let level = records[index].level
                let owned = records.indices.dropFirst(index + 1).prefix {
                    records[$0].tag != 0x42 && records[$0].level > level
                }
                guard let shapeIndex = owned.first(where: { records[$0].tag == 0x44 && records[$0].level == level + 1 }) else {
                    throw HWPDocumentEditingError.unsupportedEdit
                }
                let paraID = Int(records[index].payload[8]) | Int(records[index].payload[9]) << 8
                guard paragraphs.indices.contains(paraID) else { throw HWPDocumentEditingError.invalidDocument }
                var newPara = try paragraphShape(paragraphs[paraID], from: before.presentation, to: block.presentation)
                if before.presentation.pageBreakBefore != block.presentation.pageBreakBefore {
                    // Store the break on this paragraph; shared paragraph shapes
                    // are cloned only when an inherited break must be cleared.
                    records[index].payload[11] = block.presentation.pageBreakBefore
                        ? records[index].payload[11] | 0x04 : records[index].payload[11] & ~0x04
                    if !block.presentation.pageBreakBefore {
                        newPara.hwpWriterSetUInt32(try newPara.hwpWriterUInt32(at: 0) & ~UInt32(1 << 19), at: 0)
                    }
                }
                if before.presentation.list != block.presentation.list {
                    var flags = try newPara.hwpWriterUInt32(at: 0) & ~UInt32(0x1F << 23)
                    var id = 0
                    if let list = block.presentation.list {
                        id = try listID(list)
                        flags |= UInt32(list.kind == .number ? 2 : 3) << 23 | UInt32(list.level) << 25
                    }
                    newPara.hwpWriterSetUInt32(flags, at: 0)
                    newPara.hwpWriterSetUInt16(UInt16(id), at: 30)
                }
                if newPara != paragraphs[paraID] {
                    let newID = try intern(newPara, in: &paragraphs)
                    guard newID <= Int(UInt16.max) else { throw HWPDocumentEditingError.limitExceeded }
                    records[index].payload.hwpWriterSetUInt16(UInt16(newID), at: 8)
                }

                let sourceShapes = records[shapeIndex].payload
                guard sourceShapes.count > 0, sourceShapes.count.isMultiple(of: 8) else { throw HWPDocumentEditingError.invalidDocument }
                var boundaries: [(Int, Int)] = []
                for offset in stride(from: 0, to: sourceShapes.count, by: 8) {
                    boundaries.append((Int(try sourceShapes.hwpWriterUInt32(at: offset)), Int(try sourceShapes.hwpWriterUInt32(at: offset + 4))))
                }
                var offsets = Set(boundaries.map(\.0)), location = 0
                for run in HWPDocumentFormatting.runs(in: block) {
                    offsets.insert(rawOffset(in: block.text, utf16: location)); location += run.text.utf16.count
                }
                location = 0
                for run in HWPDocumentFormatting.runs(in: before) {
                    offsets.insert(rawOffset(in: block.text, utf16: location)); location += run.text.utf16.count
                }
                let maxRaw = rawOffset(in: block.text, utf16: block.text.utf16.count)
                var output = Data(), lastStyle: Int?
                for raw in offsets.sorted() where raw < max(1, maxRaw) {
                    let styleID = boundaries.last(where: { $0.0 <= raw })?.1 ?? boundaries[0].1
                    guard characters.indices.contains(styleID) else { throw HWPDocumentEditingError.invalidDocument }
                    let position = textOffset(in: block.text, raw: raw)
                    let oldRun = HWPDocumentFormatting.run(at: position, in: before)
                    let newRun = HWPDocumentFormatting.run(at: position, in: block)
                    var shape = characters[styleID]
                    guard shape.count >= 56 else { throw HWPDocumentEditingError.unsupportedEdit }
                    if let name = newRun.fontName, name != oldRun.fontName {
                        for language in 0..<7 { shape.hwpWriterSetUInt16(try fontID(name, language: language), at: language * 2) }
                    }
                    if let size = newRun.fontSizePoints, size != oldRun.fontSizePoints {
                        shape.hwpWriterSetUInt32(UInt32((size * 100).rounded()), at: 42)
                        for byte in 28..<35 { shape[byte] = 100 }
                    }
                    if newRun.fontWidthPercent != oldRun.fontWidthPercent {
                        for byte in 14..<21 { shape[byte] = UInt8(newRun.fontWidthPercent.rounded()) }
                    }
                    if newRun.letterSpacingPercent != oldRun.letterSpacingPercent {
                        for byte in 21..<28 { shape[byte] = UInt8(bitPattern: Int8(newRun.letterSpacingPercent.rounded())) }
                    }
                    if newRun.baselinePositionPercent != oldRun.baselinePositionPercent {
                        for byte in 35..<42 { shape[byte] = UInt8(bitPattern: Int8(newRun.baselinePositionPercent.rounded())) }
                    }
                    var flags = try shape.hwpWriterUInt32(at: 46)
                    if newRun.isBold != oldRun.isBold { flags = newRun.isBold ? flags | 2 : flags & ~2 }
                    if newRun.isItalic != oldRun.isItalic { flags = newRun.isItalic ? flags | 1 : flags & ~1 }
                    if newRun.isUnderlined != oldRun.isUnderlined { flags = flags & ~UInt32(0xFC) | (newRun.isUnderlined ? 4 : 0) }
                    if newRun.isStruckThrough != oldRun.isStruckThrough {
                        flags = flags & ~UInt32((7 << 18) | (15 << 26)) | (newRun.isStruckThrough ? 1 << 18 : 0)
                        // Version 5.0.3.0+ stores a separate strike color after borderFillID.
                        if newRun.isStruckThrough, shape.count >= 74 {
                            let rgb = newRun.textColorRGB ?? 0
                            shape.hwpWriterSetUInt32((rgb & 255) << 16 | (rgb & 0xFF00) | (rgb >> 16 & 255), at: 70)
                        }
                    }
                    if newRun.isSuperscript != oldRun.isSuperscript {
                        flags = newRun.isSuperscript ? flags | (1 << 15) : flags & ~UInt32(1 << 15)
                    }
                    if newRun.isSubscript != oldRun.isSubscript {
                        flags = newRun.isSubscript ? flags | (1 << 16) : flags & ~UInt32(1 << 16)
                    }
                    shape.hwpWriterSetUInt32(flags, at: 46)
                    if newRun.textColorRGB != oldRun.textColorRGB {
                        let rgb = newRun.textColorRGB ?? 0
                        shape.hwpWriterSetUInt32((rgb & 255) << 16 | (rgb & 0xFF00) | (rgb >> 16 & 255), at: 52)
                    }
                    if newRun.backgroundColorRGB != oldRun.backgroundColorRGB {
                        guard shape.count >= 64 else { throw HWPDocumentEditingError.unsupportedEdit }
                        let color = newRun.backgroundColorRGB.map { rgb in
                            (rgb & 255) << 16 | (rgb & 0xFF00) | (rgb >> 16 & 255)
                        } ?? UInt32.max
                        shape.hwpWriterSetUInt32(color, at: 60)
                    }
                    let newID = try intern(shape, in: &characters)
                    if lastStyle != newID {
                        output.hwpWriterAppendUInt32(UInt32(raw)); output.hwpWriterAppendUInt32(UInt32(newID)); lastStyle = newID
                    }
                }
                guard output.count / 8 <= Int(UInt16.max) else { throw HWPDocumentEditingError.limitExceeded }
                records[shapeIndex].payload = output
                records[index].payload.hwpWriterSetUInt16(UInt16(output.count / 8), at: 12)
                if let lineIndex = owned.first(where: { records[$0].tag == 0x45 && records[$0].level == level + 1 }), !block.lineLayouts.isEmpty {
                    guard block.lineLayouts.count <= Int(UInt16.max) else { throw HWPDocumentEditingError.limitExceeded }
                    records[lineIndex].payload = lineData(block.lineLayouts)
                    records[index].payload.hwpWriterSetUInt16(UInt16(block.lineLayouts.count), at: 16)
                }
                changed = true
            }
            if changed {
                let payload = records.reduce(into: Data()) { $0.append($1.serialized()) }
                replacements[path] = try compressed ? HWP5DocumentRewriter.rawDeflate(payload) : payload
            }
        }
        guard changes.keys.allSatisfy({ $0 < ordinal }) else { throw HWPDocumentEditingError.staleDocument }
        for language in 0..<7 { info[mapping].payload.hwpWriterSetUInt32(UInt32(languageFonts[language].count), at: (language + 1) * 4) }
        info[mapping].payload.hwpWriterSetUInt32(UInt32(characters.count), at: 9 * 4)
        info[mapping].payload.hwpWriterSetUInt32(UInt32(paragraphs.count), at: 13 * 4)
        info[mapping].payload.hwpWriterSetUInt32(UInt32(numbers.count), at: 11 * 4)
        info[mapping].payload.hwpWriterSetUInt32(UInt32(bullets.count), at: 12 * 4)
        // Font IDs are local to each language group. Rebuild the groups in the
        // same order and retain every original font payload without changes.
        var rebuilt: [Record] = [], wroteFonts = false
        for (index, record) in info.enumerated() {
            if record.tag == 0x13 {
                if !wroteFonts {
                    rebuilt += languageFonts.flatMap { $0 }.map { Record(tag: 0x13, level: record.level, payload: $0) }
                    wroteFonts = true
                }
            } else { rebuilt.append(record) }
            if record.tag == 0x15, info.dropFirst(index + 1).first(where: { $0.tag == 0x15 }) == nil {
                rebuilt += characters.dropFirst(originalCharCount).map { Record(tag: 0x15, level: record.level, payload: $0) }
            }
            if record.tag == 0x19, info.dropFirst(index + 1).first(where: { $0.tag == 0x19 }) == nil {
                rebuilt += paragraphs.dropFirst(originalParaCount).map { Record(tag: 0x19, level: record.level, payload: $0) }
            }
        }
        for (tag, additions) in [(UInt32(0x17), Array(numbers.dropFirst(oldNumberCount))),
                                  (UInt32(0x18), Array(bullets.dropFirst(oldBulletCount)))] where !additions.isEmpty {
            let insertion = rebuilt.lastIndex(where: { $0.tag == tag }).map { $0 + 1 }
                ?? rebuilt.firstIndex(where: { $0.tag > tag }) ?? rebuilt.endIndex
            rebuilt.insert(contentsOf: additions.map { Record(tag: tag, level: 0, payload: $0) }, at: insertion)
        }
        let docInfo = rebuilt.reduce(into: Data()) { $0.append($1.serialized()) }
        replacements["DocInfo"] = try compressed ? HWP5DocumentRewriter.rawDeflate(docInfo) : docInfo
        let result = try container.serialized(replacing: replacements)
        let saved = try HWP5StructuredDocumentParser.parse(from: result)
        guard saved.blocks.count == edited.count else { throw HWPDocumentEditingError.cannotSave }
        for (actual, expected) in zip(saved.blocks, edited) where changes[expected.paragraphIndex] != nil {
            guard HWPDocumentFormatting.matches(actual, expected, includingCell: false,
                includingHyperlinks: false) else { throw HWPDocumentEditingError.cannotSave }
        }
        return result
    }

    private static func intern(_ data: Data, in values: inout [Data]) throws -> Int {
        if let index = values.firstIndex(of: data) { return index }
        guard values.count < 65_535 else { throw HWPDocumentEditingError.limitExceeded }
        values.append(data); return values.count - 1
    }

    private static func fontName(_ data: Data) -> String? {
        guard data.count >= 3 else { return nil }
        let count = Int(data[1]) | Int(data[2]) << 8
        guard 3 + count * 2 <= data.count else { return nil }
        return String(data: data.subdata(in: 3..<(3 + count * 2)), encoding: .utf16LittleEndian)
    }

    private static func paragraphShape(_ source: Data, from old: HWPDocumentBlockPresentation,
                                       to new: HWPDocumentBlockPresentation) throws -> Data {
        guard source.count >= 42 else { throw HWPDocumentEditingError.unsupportedEdit }
        var data = source
        if old.alignment != new.alignment {
            let align: UInt32 = switch new.alignment { case .justified: 0; case .leading: 1; case .trailing: 2; case .centered: 3; case .distributed: 4 }
            data.hwpWriterSetUInt32(try data.hwpWriterUInt32(at: 0) & ~UInt32(28) | align << 2, at: 0)
        }
        let before = [old.leftMarginPoints, old.rightMarginPoints, old.firstLineIndentPoints, old.spacingBeforePoints, old.spacingAfterPoints]
        let after = [new.leftMarginPoints, new.rightMarginPoints, new.firstLineIndentPoints, new.spacingBeforePoints, new.spacingAfterPoints]
        for index in after.indices where before[index] != after[index] {
            data.hwpWriterSetUInt32(UInt32(bitPattern: Int32((after[index] * 200).rounded())), at: 4 + index * 4)
        }
        if let percent = new.lineSpacingPercent, percent != old.lineSpacingPercent {
            data.hwpWriterSetUInt32(try data.hwpWriterUInt32(at: 0) & ~UInt32(3), at: 0)
            data.hwpWriterSetUInt32(UInt32(percent.rounded()), at: 24)
            if data.count >= 54 {
                data.hwpWriterSetUInt32(try data.hwpWriterUInt32(at: 46) & ~UInt32(31), at: 46)
                data.hwpWriterSetUInt32(UInt32(percent.rounded()), at: 50)
            }
        }
        return data
    }

    static func rawOffset(in text: String, utf16: Int) -> Int {
        let prefix = (text as NSString).substring(to: min(utf16, text.utf16.count))
        return utf16 + prefix.filter { $0 == "\t" }.count * 7
    }

    private static func textOffset(in text: String, raw: Int) -> Int {
        var source = 0, visible = 0
        for unit in text.utf16 {
            if source >= raw { break }
            source += unit == 9 ? 8 : 1; visible += 1
        }
        return visible
    }

    static func lineData(_ lines: [HWPDocumentLineLayout]) -> Data {
        var data = Data()
        for line in lines {
            data.hwpWriterAppendUInt32(UInt32(line.startCharacter))
            for value in [line.verticalPositionPoints, line.lineHeightPoints, line.textHeightPoints,
                          line.baselinePoints, line.lineSpacingPoints, line.columnStartPoints, line.widthPoints] {
                data.hwpWriterAppendUInt32(UInt32(bitPattern: Int32((value * 100).rounded())))
            }
            data.hwpWriterAppendUInt32(line.flags)
        }
        return data
    }
}
