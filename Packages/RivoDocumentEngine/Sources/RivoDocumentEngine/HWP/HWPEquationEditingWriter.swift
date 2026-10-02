import Foundation

public nonisolated enum HWPEquationEditingWriter {
    public typealias Record = HWP5DocumentRewriter.Record
    private static let controlID: UInt32 = 0x6571_6564 // "eqed"

    public static func insert(_ request: HWPEquationEditing.Request, into source: HWPTableStructureDocument,
                       ownerIndex: Int) throws -> Data {
        guard request.isValid, source.blocks.indices.contains(ownerIndex),
              source.blocks[ownerIndex].text.isEmpty,
              HWPParagraphEditing.supports(source.blocks[ownerIndex]) else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        switch source {
        case .hwpx(let package): return try insertHWPX(request, package: package, owner: source.blocks[ownerIndex])
        case .hwp(_, let data): return try insertHWP(request, data: data, owner: source.blocks[ownerIndex])
        }
    }

    public static func apply(_ action: HWPEquationEditing.Action, target: HWPEquationEditing.Target,
                      to source: HWPTableStructureDocument, ownerIndex: Int) throws -> Data {
        guard source.blocks.indices.contains(ownerIndex), source.blocks[ownerIndex].id == target.ownerID else {
            throw HWPDocumentEditingError.staleDocument
        }
        switch source {
        case .hwpx(let package): return try editHWPX(action, target: target, package: package, owner: source.blocks[ownerIndex])
        case .hwp(_, let data): return try editHWP(action, target: target, data: data, owner: source.blocks[ownerIndex])
        }
    }

    private static func unit(_ value: Double) -> String { String(Int((value * 100).rounded())) }
    private static func raw(_ value: Double) -> UInt32 { UInt32(bitPattern: Int32((value * 100).rounded())) }

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

    private static func insertHWPX(_ request: HWPEquationEditing.Request, package: HWPXDocumentPackage,
                                   owner: HWPDocumentBlock) throws -> Data {
        guard let section = package.sections.first(where: { $0.path == owner.sectionPath }),
              let paragraphIndex = section.blocks.firstIndex(where: { $0.id == owner.id }) else {
            throw HWPDocumentEditingError.staleDocument
        }
        let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: section.xml)
        guard ranges.indices.contains(paragraphIndex) else { throw HWPDocumentEditingError.staleDocument }
        let paragraph = (section.xml as NSString).substring(with: ranges[paragraphIndex])
        let prefix = try HWPFormattingXML.prefix(paragraph)
        guard let run = try HWPFormattingXML.elements(paragraph, name: "run").first else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        let width = min(max(request.selection.width * 0.42, 120), 260)
        let height = min(max(request.fontSizePoints * 2.4, 32), 120)
        let id = try nextObjectID(package)
        let equation = "<\(prefix)equation id=\"\(id)\" zOrder=\"0\" numberingType=\"EQUATION\" textWrap=\"TOP_AND_BOTTOM\" textFlow=\"BOTH_SIDES\" lock=\"0\" dropcapstyle=\"None\" baseUnit=\"\(unit(request.fontSizePoints))\" textColor=\"#000000\" baseLine=\"85\"><\(prefix)sz width=\"\(unit(width))\" widthRelTo=\"ABSOLUTE\" height=\"\(unit(height))\" heightRelTo=\"ABSOLUTE\" protect=\"0\"/><\(prefix)pos treatAsChar=\"1\" affectLSpacing=\"0\" flowWithText=\"1\" allowOverlap=\"0\" holdAnchorAndSO=\"0\" vertRelTo=\"PARA\" horzRelTo=\"PARA\" vertAlign=\"TOP\" horzAlign=\"LEFT\" vertOffset=\"0\" horzOffset=\"0\"/><\(prefix)outMargin left=\"0\" right=\"0\" top=\"0\" bottom=\"0\"/><\(prefix)script>\(HWPFormattingXML.escaped(request.script))</\(prefix)script><\(prefix)shapeComment>VisionCraft 수식</\(prefix)shapeComment></\(prefix)equation>"
        let updatedRun = try HWPFormattingXML.append(equation, to: run.xml)
        let updatedParagraph = (paragraph as NSString).replacingCharacters(in: run.range, with: updatedRun)
        let sectionXML = (section.xml as NSString).replacingCharacters(in: ranges[paragraphIndex], with: updatedParagraph)
        return try HWPXEditingArchive(data: package.sourceData).repack(replacing: [section.path: Data(sectionXML.utf8)])
    }

    private static func editHWPX(_ action: HWPEquationEditing.Action, target: HWPEquationEditing.Target,
                                 package: HWPXDocumentPackage, owner: HWPDocumentBlock) throws -> Data {
        guard let section = package.sections.first(where: { $0.path == owner.sectionPath }),
              let paragraphIndex = section.blocks.firstIndex(where: { $0.id == owner.id }),
              let objectIndex = owner.canvasObjects.firstIndex(where: { $0.id == target.objectID }) else {
            throw HWPDocumentEditingError.staleDocument
        }
        let equationBefore = owner.canvasObjects[..<objectIndex].reduce(0) { count, object in
            if case .equation = object.content { return count + 1 }
            return count
        }
        let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: section.xml)
        guard ranges.indices.contains(paragraphIndex) else { throw HWPDocumentEditingError.staleDocument }
        let paragraph = (section.xml as NSString).substring(with: ranges[paragraphIndex])
        let elements = try HWPFormattingXML.elements(paragraph, name: "equation")
        guard elements.indices.contains(equationBefore) else { throw HWPDocumentEditingError.staleDocument }
        let element = elements[equationBefore]
        let replacement: String
        switch action {
        case .delete: replacement = ""
        case .update(let update):
            guard update.isValid else { throw HWPDocumentEditingError.limitExceeded }
            let prefix = try HWPFormattingXML.prefix(element.xml)
            let script = "<\(prefix)script>\(HWPFormattingXML.escaped(update.script))</\(prefix)script>"
            var result = try HWPFormattingXML.replaceOrAppend(element.xml, name: "script", replacement: script)
            result = try HWPFormattingXML.setAttribute(result, "baseUnit", unit(update.fontSizePoints))
            replacement = result
        }
        let updatedParagraph = (paragraph as NSString).replacingCharacters(in: element.range, with: replacement)
        let sectionXML = (section.xml as NSString).replacingCharacters(in: ranges[paragraphIndex], with: updatedParagraph)
        return try HWPXEditingArchive(data: package.sourceData).repack(replacing: [section.path: Data(sectionXML.utf8)])
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

    private static func sectionRecords(_ container: OLECompoundFile, compressed: Bool,
                                       owner: HWPDocumentBlock) throws -> (String, [Record], Int) {
        let paths = container.streamNames.filter { $0.hasPrefix("bodytext/section") }
            .sorted { (HWPPageSetup.sectionIndex($0) ?? 0) < (HWPPageSetup.sectionIndex($1) ?? 0) }
        var ordinal = 0
        for path in paths {
            let records = try HWP5DocumentRewriter.parseRecords(expanded(container.stream(named: path), compressed: compressed))
            for (index, record) in records.enumerated() where record.tag == 0x42 {
                if ordinal == owner.paragraphIndex && path == owner.sectionPath.lowercased() { return (path, records, index) }
                ordinal += 1
            }
        }
        throw HWPDocumentEditingError.staleDocument
    }

    private static func equationPayload(script: String, fontSizePoints: Double,
                                        colorRGB: UInt32, baselinePercent: Double,
                                        fontName: String?) throws -> Data {
        let units = Array(script.utf16)
        guard !units.isEmpty, units.count <= 32_768 else { throw HWPDocumentEditingError.limitExceeded }
        var payload = Data()
        payload.hwpWriterAppendUInt32(0)
        payload.hwpWriterAppendUInt16(UInt16(units.count))
        for unit in units { payload.hwpWriterAppendUInt16(unit) }
        payload.hwpWriterAppendUInt32(raw(fontSizePoints))
        let color = (colorRGB & 0xFF) << 16 | (colorRGB & 0xFF00) | (colorRGB >> 16 & 0xFF)
        payload.hwpWriterAppendUInt32(color)
        payload.hwpWriterAppendUInt16(UInt16(bitPattern: Int16(clamping: Int(baselinePercent.rounded()))))
        appendString("Equation Version 60", to: &payload)
        appendString(fontName?.isEmpty == false ? fontName! : "HYhwpEQ", to: &payload)
        return payload
    }

    private static func appendString(_ value: String, to data: inout Data) {
        let units = Array(value.utf16.prefix(Int(UInt16.max)))
        data.hwpWriterAppendUInt16(UInt16(units.count))
        for unit in units { data.hwpWriterAppendUInt16(unit) }
    }

    private static func insertHWP(_ request: HWPEquationEditing.Request, data: Data,
                                  owner: HWPDocumentBlock) throws -> Data {
        let container = try OLECompoundFile(data: data)
        let flags = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36)
        guard flags & 0x6796 == 0 else { throw HWPDocumentEditingError.protectedDocument }
        let compressed = flags & 1 != 0
        let (path, initial, start) = try sectionRecords(container, compressed: compressed, owner: owner)
        var records = initial
        var end = records.indices.dropFirst(start + 1).first { records[$0].level == 0 } ?? records.endIndex
        let owned = start..<end
        let text = owned.first(where: { records[$0].tag == 0x43 })
        guard owned.allSatisfy({ [0x42, 0x43, 0x44, 0x45].contains(records[$0].tag) }),
              text.map({ records[$0].payload.isEmpty || records[$0].payload == Data([13, 0]) }) ?? true,
              records[start].payload.count >= 22 else { throw HWPDocumentEditingError.unsupportedEdit }
        var anchor = Data(); anchor.hwpWriterAppendUInt16(11); anchor.hwpWriterAppendUInt32(controlID)
        anchor.append(Data(repeating: 0, count: 8)); anchor.hwpWriterAppendUInt16(11); anchor.hwpWriterAppendUInt16(13)
        if let text { records[text].payload = anchor }
        else { records.insert(.init(tag: 0x43, level: 1, payload: anchor), at: start + 1); end += 1 }
        let last = try records[start].payload.hwpWriterUInt32(at: 0) & 0x8000_0000
        records[start].payload.hwpWriterSetUInt32(last | 9, at: 0)
        records[start].payload.hwpWriterSetUInt32(1 << 11, at: 4)

        let widthPoints = min(max(request.selection.width * 0.42, 120), 260)
        let heightPoints = min(max(request.fontSizePoints * 2.4, 32), 120)
        let width = raw(widthPoints), height = raw(heightPoints)
        var nextInstance: UInt32 = 1
        for record in records where record.payload.count >= 40 && record.tag == 0x47 {
            nextInstance = max(nextInstance, try record.payload.hwpWriterUInt32(at: 36) &+ 1)
        }
        var control = Data(repeating: 0, count: 46)
        control.hwpWriterSetUInt32(controlID, at: 0)
        control.hwpWriterSetUInt32(1 | (2 << 3) | (3 << 8), at: 4)
        control.hwpWriterSetUInt32(width, at: 16); control.hwpWriterSetUInt32(height, at: 20)
        control.hwpWriterSetUInt32(nextInstance, at: 36)
        let comment = Array("VisionCraft 수식".utf16)
        control.hwpWriterSetUInt16(UInt16(comment.count), at: 44)
        for value in comment { control.hwpWriterAppendUInt16(value) }
        let equation = try equationPayload(script: request.script, fontSizePoints: request.fontSizePoints,
            colorRGB: 0, baselinePercent: 85, fontName: nil)
        records.insert(contentsOf: [.init(tag: 0x47, level: 1, payload: control),
                                    .init(tag: 0x58, level: 2, payload: equation)], at: end)
        return try container.serialized(replacing: [path: encoded(records, compressed: compressed)])
    }

    private static let objectControlIDs: Set<UInt32> = [
        0x2470_6963, 0x6773_6F20, controlID, 0x246C_696E, 0x2472_6563,
        0x2465_6C6C, 0x2461_7263, 0x2470_6F6C, 0x2463_7572, 0x246F_6C65, 0x2463_6F6E
    ]

    private static func editHWP(_ action: HWPEquationEditing.Action, target: HWPEquationEditing.Target,
                                data: Data, owner: HWPDocumentBlock) throws -> Data {
        let container = try OLECompoundFile(data: data)
        let flags = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36)
        guard flags & 0x6796 == 0 else { throw HWPDocumentEditingError.protectedDocument }
        let compressed = flags & 1 != 0
        let (path, initial, ownerRecord) = try sectionRecords(container, compressed: compressed, owner: owner)
        var records = initial
        guard let objectIndex = owner.canvasObjects.firstIndex(where: { $0.id == target.objectID }) else {
            throw HWPDocumentEditingError.staleDocument
        }
        let ownerEnd = records.indices.dropFirst(ownerRecord + 1).first { records[$0].level == 0 } ?? records.endIndex
        let controls = (ownerRecord + 1..<ownerEnd).filter { index in
            guard records[index].tag == 0x47, records[index].level == 1, records[index].payload.count >= 4,
                  let identifier = try? records[index].payload.hwpWriterUInt32(at: 0) else { return false }
            return objectControlIDs.contains(identifier)
        }
        guard controls.indices.contains(objectIndex) else { throw HWPDocumentEditingError.staleDocument }
        let controlIndex = controls[objectIndex]
        guard try records[controlIndex].payload.hwpWriterUInt32(at: 0) == controlID else {
            throw HWPDocumentEditingError.staleDocument
        }
        let end = records.indices.dropFirst(controlIndex + 1).first {
            records[$0].level <= records[controlIndex].level
        } ?? records.endIndex
        guard let equationIndex = records.indices[controlIndex..<end].first(where: { records[$0].tag == 0x58 }) else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        switch action {
        case .update(let update):
            guard update.isValid else { throw HWPDocumentEditingError.limitExceeded }
            records[equationIndex].payload = try equationPayload(script: update.script,
                fontSizePoints: update.fontSizePoints, colorRGB: target.colorRGB,
                baselinePercent: target.baselinePercent, fontName: target.fontName)
        case .delete:
            try removeAnchorAndControl(records: &records, ownerRecord: ownerRecord, ownerEnd: ownerEnd,
                controls: controls, objectIndex: objectIndex, controlIndex: controlIndex, controlEnd: end)
        }
        return try container.serialized(replacing: [path: encoded(records, compressed: compressed)])
    }

    private static func removeAnchorAndControl(records: inout [Record], ownerRecord: Int, ownerEnd: Int,
                                               controls: [Int], objectIndex: Int,
                                               controlIndex: Int, controlEnd: Int) throws {
        let direct = (ownerRecord + 1..<ownerEnd).filter { records[$0].level == 1 }
        guard let textIndex = direct.first(where: { records[$0].tag == 0x43 }),
              records[ownerRecord].payload.count >= 22 else { throw HWPDocumentEditingError.unsupportedEdit }
        var bytes = records[textIndex].payload
        let identifier = try records[controlIndex].payload.hwpWriterUInt32(at: 0)
        let sameBefore = controls.prefix(objectIndex).filter {
            (try? records[$0].payload.hwpWriterUInt32(at: 0)) == identifier
        }.count
        var cursor = 0, matching = 0, anchor: Int?
        while cursor < bytes.count / 2 {
            let code = try bytes.hwpWriterUInt16(at: cursor * 2)
            let size = code >= 1 && code <= 23 && code != 10 && code != 13 ? 8 : 1
            guard cursor + size <= bytes.count / 2 else { throw HWPDocumentEditingError.invalidDocument }
            if code == 11, try bytes.hwpWriterUInt32(at: cursor * 2 + 2) == identifier {
                if matching == sameBefore { anchor = cursor; break }
                matching += 1
            }
            cursor += size
        }
        guard let anchor else { throw HWPDocumentEditingError.unsupportedEdit }
        bytes.removeSubrange(anchor * 2..<(anchor + 8) * 2)
        records[textIndex].payload = bytes
        let last = try records[ownerRecord].payload.hwpWriterUInt32(at: 0) & 0x8000_0000
        records[ownerRecord].payload.hwpWriterSetUInt32(last | UInt32(bytes.count / 2), at: 0)
        var mask: UInt32 = 0, position = 0
        while position < bytes.count / 2 {
            let code = try bytes.hwpWriterUInt16(at: position * 2)
            let size = code >= 1 && code <= 23 && code != 10 && code != 13 ? 8 : 1
            if code > 0 && code < 32 && code != 13 { mask |= 1 << UInt32(code) }
            position += size
        }
        records[ownerRecord].payload.hwpWriterSetUInt32(mask, at: 4)
        func mapped(_ value: UInt32) -> UInt32 {
            value <= UInt32(anchor) ? value : value < UInt32(anchor + 8) ? UInt32(anchor) : value - 8
        }
        for index in direct where records[index].tag == 0x44 || records[index].tag == 0x45 {
            let stride = records[index].tag == 0x44 ? 8 : 36
            guard records[index].payload.count.isMultiple(of: stride) else {
                throw HWPDocumentEditingError.invalidDocument
            }
            var entries: [Data] = []
            for offset in Swift.stride(from: 0, to: records[index].payload.count, by: stride) {
                var entry = records[index].payload.subdata(in: offset..<(offset + stride))
                entry.hwpWriterSetUInt32(mapped(try entry.hwpWriterUInt32(at: 0)), at: 0)
                if records[index].tag == 0x44, let old = entries.last,
                   try old.hwpWriterUInt32(at: 0) == entry.hwpWriterUInt32(at: 0) { entries.removeLast() }
                entries.append(entry)
            }
            records[index].payload = entries.reduce(into: Data()) { $0.append($1) }
            records[ownerRecord].payload.hwpWriterSetUInt16(UInt16(entries.count), at: stride == 8 ? 12 : 16)
        }
        records.removeSubrange(controlIndex..<controlEnd)
    }
}
