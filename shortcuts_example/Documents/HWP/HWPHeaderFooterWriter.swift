import Foundation

nonisolated enum HWPHeaderFooterWriter {
    typealias Record = HWP5DocumentRewriter.Record
    private static func simple(_ block: HWPDocumentBlock) -> Bool {
        block.isEditable && block.tableLocation == nil && block.layoutContainerID == nil && block.images.isEmpty
            && block.canvasObjects.isEmpty && block.presentation.list == nil && !block.presentation.pageBreakBefore
            && !block.lineLayouts.contains { $0.listMarker != nil }
    }
    static func validate(_ kind: HWPHeaderFooterKind, section: Int, source: HWPTableStructureDocument) throws {
        let paragraphs = HWPHeaderFooterEditing.paragraphs(source.blocks, kind: kind, section: section)
        guard paragraphs.count <= 8, paragraphs.allSatisfy(simple) else { throw HWPDocumentEditingError.unsupportedEdit }
        switch source {
        case .hwpx(let package):
            guard let item = package.sections.first(where: { HWPPageSetup.sectionIndex($0.path) == section }) else { throw HWPDocumentEditingError.staleDocument }
            let definitions = try HWPFormattingXML.elements(item.xml, name: kind.rawValue)
            guard definitions.count <= 1, definitions.isEmpty == paragraphs.isEmpty,
                  let first = try HWPFormattingXML.elements(item.xml, name: "p").first else { throw HWPDocumentEditingError.unsupportedEdit }
            if let definition = definitions.first {
                guard NSLocationInRange(definition.range.location, first.range),
                      NSMaxRange(definition.range) <= NSMaxRange(first.range),
                      try HWPFormattingXML.elements(definition.xml, name: "p").count == paragraphs.count else { throw HWPDocumentEditingError.unsupportedEdit }
            }
        case .hwp(_, let data):
            let container = try OLECompoundFile(data: data)
            guard let path = container.streamNames.first(where: { $0.hasPrefix("bodytext/section") && HWPPageSetup.sectionIndex($0) == section }) else { throw HWPDocumentEditingError.staleDocument }
            let records = try expanded(container, path: path)
            let controls = records.indices.filter { records[$0].tag == 0x47 && (try? records[$0].payload.hwpWriterUInt32(at: 0)) == kind.controlID }
            guard controls.count <= 1, controls.isEmpty == paragraphs.isEmpty, let first = records.firstIndex(where: { $0.tag == 0x42 && $0.level == 0 }) else { throw HWPDocumentEditingError.unsupportedEdit }
            if let control = controls.first {
                let owner = records.indices.prefix(control).last { records[$0].tag == 0x42 && records[$0].level == 0 }
                let end = records.indices.dropFirst(control + 1).first { records[$0].level <= 1 } ?? records.endIndex
                guard owner == first, records[control].level == 1, records[control].payload.count >= 8,
                      records[(control + 1)..<end].allSatisfy({ [0x48, 0x42, 0x43, 0x44, 0x45].contains($0.tag) }),
                      records[(control + 1)..<end].filter({ $0.tag == 0x42 }).count == paragraphs.count else { throw HWPDocumentEditingError.unsupportedEdit }
            }
        }
    }
    static func prepare(_ request: HWPHeaderFooterRequest, source: HWPTableStructureDocument) throws -> Data {
        switch source {
        case .hwpx(let package): return try hwpx(request, package: package)
        case .hwp(_, let data): return try hwp(request, data: data, blocks: source.blocks, layouts: source.layouts)
        }
    }
    private static func scope(_ value: HWPDocumentHeaderFooterScope) -> String {
        switch value { case .bothPages: "BOTH"; case .evenPages: "EVEN"; case .oddPages: "ODD" }
    }
    private static func units(_ value: Double) -> String { String(Int((value * 100).rounded())) }
    private static func hwpx(_ request: HWPHeaderFooterRequest, package: HWPXDocumentPackage) throws -> Data {
        var replacements: [String: Data] = [:], nextID: UInt32 = 0
        for section in package.sections {
            for tag in try HWPXParagraphXMLPatcher.tagTokens(in: section.xml) where !tag.isClosing {
                nextID = max(nextID, UInt32(try HWPFormattingXML.attribute((section.xml as NSString).substring(with: tag.range), "id") ?? "0") ?? 0)
            }
        }
        guard let template = package.blocks.first(where: { $0.isEditable && $0.presentation.list == nil && !$0.presentation.pageBreakBefore }),
              let templateSection = package.sections.first(where: { $0.path == template.sectionPath }),
              let ordinal = templateSection.blocks.firstIndex(where: { $0.id == template.id }) else { throw HWPDocumentEditingError.unsupportedEdit }
        let templateRanges = try HWPXParagraphXMLPatcher.paragraphRanges(in: templateSection.xml)
        let templateXML = (templateSection.xml as NSString).substring(with: templateRanges[ordinal])
        let templateRun = try HWPFormattingXML.elements(templateXML, name: "run").first
        let para = HWPFormattingXML.escaped(try HWPFormattingXML.attribute(templateXML, "paraPrIDRef") ?? "0")
        let style = HWPFormattingXML.escaped(try HWPFormattingXML.attribute(templateXML, "styleIDRef") ?? "0")
        let char = HWPFormattingXML.escaped(try templateRun.flatMap { try HWPFormattingXML.attribute($0.xml, "charPrIDRef") } ?? "0")
        for section in package.sections {
            guard let index = HWPPageSetup.sectionIndex(section.path), request.sections.contains(index),
                  let layout = package.pageLayouts.first(where: { $0.sectionIndex == index }) else { continue }
            var xml = section.xml
            let existing = try HWPFormattingXML.elements(xml, name: request.kind.rawValue).first
            if let existing {
                var definition = try HWPFormattingXML.setAttribute(existing.xml, "applyPageType", scope(request.scope))
                if let sublist = try HWPFormattingXML.elements(definition, name: "sublist").first {
                    var sub = try HWPFormattingXML.setAttribute(sublist.xml, "textWidth", units(layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints))
                    sub = try HWPFormattingXML.setAttribute(sub, "textHeight", units(request.kind.band(layout)))
                    definition = (definition as NSString).replacingCharacters(in: sublist.range, with: sub)
                }
                xml = (xml as NSString).replacingCharacters(in: existing.range, with: definition)
            } else {
                guard let run = try HWPFormattingXML.elements(xml, name: "run").first,
                      let token = try HWPXParagraphXMLPatcher.tagTokens(in: run.xml).first, !token.isSelfClosing,
                      nextID < UInt32.max - UInt32(request.texts.count + 1) else { throw HWPDocumentEditingError.unsupportedEdit }
                let prefix = try HWPFormattingXML.prefix(run.xml)
                nextID += 1; let id = nextID
                var paragraphs = ""
                for _ in request.texts {
                    nextID += 1
                    paragraphs += "<\(prefix)p id=\"\(nextID)\" paraPrIDRef=\"\(para)\" styleIDRef=\"\(style)\" pageBreak=\"0\" columnBreak=\"0\" merged=\"0\"><\(prefix)run charPrIDRef=\"\(char)\"><\(prefix)t/></\(prefix)run></\(prefix)p>"
                }
                let content = "<\(prefix)ctrl><\(prefix)\(request.kind.rawValue) id=\"\(id)\" applyPageType=\"\(scope(request.scope))\"><\(prefix)subList id=\"\" textDirection=\"HORIZONTAL\" lineWrap=\"BREAK\" vertAlign=\"TOP\" linkListIDRef=\"0\" linkListNextIDRef=\"0\" textWidth=\"\(units(layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints))\" textHeight=\"\(units(request.kind.band(layout)))\" hasTextRef=\"0\" hasNumRef=\"0\">\(paragraphs)</\(prefix)subList></\(prefix)\(request.kind.rawValue)></\(prefix)ctrl>"
                xml = (xml as NSString).replacingCharacters(in: .init(location: run.range.location + NSMaxRange(token.range), length: 0), with: content)
            }
            if let visibility = try HWPFormattingXML.elements(xml, name: "visibility").first {
                let updated = try HWPFormattingXML.setAttribute(visibility.xml, request.kind == .header ? "hideFirstHeader" : "hideFirstFooter", "0")
                xml = (xml as NSString).replacingCharacters(in: visibility.range, with: updated)
            }
            guard xml.utf8.count <= HWPXTextExtractor.maximumEntryBytes else { throw HWPDocumentEditingError.limitExceeded }
            replacements[section.path] = Data(xml.utf8)
        }
        return try HWPXEditingArchive(data: package.sourceData).repack(replacing: replacements)
    }
    private static func expanded(_ container: OLECompoundFile, path: String) throws -> [Record] {
        let stored = try container.stream(named: path)
        let compressed = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36) & 1 != 0
        return try HWP5DocumentRewriter.parseRecords(compressed ? HWP5TextExtractor.inflateRawDeflate(stored, maximumBytes: HWP5TextExtractor.maximumSectionBytes) : stored)
    }
    private static func hwp(_ request: HWPHeaderFooterRequest, data: Data, blocks: [HWPDocumentBlock], layouts: [HWPDocumentPageLayout]) throws -> Data {
        let container = try OLECompoundFile(data: data)
        let flags = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36)
        guard flags & 0x6796 == 0 else { throw HWPDocumentEditingError.protectedDocument }
        let paths = container.streamNames.filter { $0.hasPrefix("bodytext/section") }
            .sorted { (HWPPageSetup.sectionIndex($0) ?? 0) < (HWPPageSetup.sectionIndex($1) ?? 0) }
        guard let template = blocks.first(where: { $0.isEditable && $0.presentation.list == nil && !$0.presentation.pageBreakBefore }) else { throw HWPDocumentEditingError.unsupportedEdit }
        var sectionRecords: [String: [Record]] = [:], ordinal = 0, nextID: UInt32 = 0
        var templateHeader: Data?, templateShape: Data?
        for path in paths {
            let records = try expanded(container, path: path); sectionRecords[path] = records
            for index in records.indices where records[index].tag == 0x42 {
                if ordinal == template.paragraphIndex {
                    templateHeader = records[index].payload
                    let level = records[index].level
                    let owned = records.indices.dropFirst(index + 1).prefix { records[$0].level > level }
                    templateShape = owned.first(where: { records[$0].tag == 0x44 && records[$0].level == level + 1 }).map { Data(records[$0].payload.prefix(8)) }
                }
                if records[index].payload.count >= 22 { nextID = max(nextID, try records[index].payload.hwpWriterUInt32(at: 18)) }
                ordinal += 1
            }
        }
        guard let templateHeader, templateHeader.count >= 22, let templateShape, templateShape.count == 8 else { throw HWPDocumentEditingError.unsupportedEdit }
        var replacements: [String: Data] = [:]
        let pageScope: UInt32 = request.scope == .bothPages ? 0 : request.scope == .evenPages ? 1 : 2
        for path in paths {
            guard let section = HWPPageSetup.sectionIndex(path), request.sections.contains(section),
                  var records = sectionRecords[path], let layout = layouts.first(where: { $0.sectionIndex == section }) else { continue }
            if let control = records.firstIndex(where: { $0.tag == 0x47 && (try? $0.payload.hwpWriterUInt32(at: 0)) == request.kind.controlID }) {
                let value = try records[control].payload.hwpWriterUInt32(at: 4)
                records[control].payload.hwpWriterSetUInt32((value & ~3) | pageScope, at: 4)
                if let list = records.indices.dropFirst(control + 1).prefix(while: { records[$0].level > 1 }).first(where: { records[$0].tag == 0x48 }), records[list].payload.count >= 16 {
                    records[list].payload.hwpWriterSetUInt32(UInt32((layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints) * 100), at: 8)
                    records[list].payload.hwpWriterSetUInt32(UInt32(request.kind.band(layout) * 100), at: 12)
                }
            } else {
                guard let owner = records.firstIndex(where: { $0.tag == 0x42 && $0.level == 0 }), records[owner].payload.count >= 22,
                      nextID < UInt32.max - UInt32(request.texts.count + 1) else { throw HWPDocumentEditingError.unsupportedEdit }
                var end = records.indices.dropFirst(owner + 1).first { records[$0].level == 0 } ?? records.endIndex
                var anchor = Data(); anchor.hwpWriterAppendUInt16(16); anchor.hwpWriterAppendUInt32(request.kind.controlID)
                anchor.append(Data(repeating: 0, count: 8)); anchor.hwpWriterAppendUInt16(16)
                if let text = (owner + 1..<end).first(where: { records[$0].tag == 0x43 && records[$0].level == 1 }) {
                    guard records[text].payload.suffix(2) == Data([13, 0]) else { throw HWPDocumentEditingError.unsupportedEdit }
                    records[text].payload.insert(contentsOf: anchor, at: records[text].payload.count - 2)
                } else {
                    anchor.hwpWriterAppendUInt16(13)
                    records.insert(.init(tag: 0x43, level: 1, payload: anchor), at: owner + 1); end += 1
                }
                let count = try records[owner].payload.hwpWriterUInt32(at: 0)
                guard count & 0x7FFF_FFFF <= 0x7FFF_FFF6 else { throw HWPDocumentEditingError.limitExceeded }
                records[owner].payload.hwpWriterSetUInt32((count & 0x8000_0000) | (max(1, count & 0x7FFF_FFFF) + 8), at: 0)
                let mask = try records[owner].payload.hwpWriterUInt32(at: 4)
                records[owner].payload.hwpWriterSetUInt32(mask | (1 << 16), at: 4)
                nextID += 1
                var control = Data(); control.hwpWriterAppendUInt32(request.kind.controlID); control.hwpWriterAppendUInt32(pageScope); control.hwpWriterAppendUInt32(nextID)
                var list = Data(repeating: 0, count: 34)
                list.hwpWriterSetUInt32(UInt32(request.texts.count), at: 0)
                list.hwpWriterSetUInt32(UInt32((layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints) * 100), at: 8)
                list.hwpWriterSetUInt32(UInt32(request.kind.band(layout) * 100), at: 12)
                var inserted = [Record(tag: 0x47, level: 1, payload: control), Record(tag: 0x48, level: 2, payload: list)]
                for index in request.texts.indices {
                    var header = templateHeader, shape = templateShape
                    header.hwpWriterSetUInt32(index == request.texts.count - 1 ? 0x8000_0001 : 1, at: 0)
                    header.hwpWriterSetUInt32(0, at: 4); header[11] = 0
                    header.hwpWriterSetUInt16(1, at: 12); header.hwpWriterSetUInt16(0, at: 14); header.hwpWriterSetUInt16(0, at: 16)
                    nextID += 1; header.hwpWriterSetUInt32(nextID, at: 18); shape.hwpWriterSetUInt32(0, at: 0)
                    inserted += [.init(tag: 0x42, level: 2, payload: header), .init(tag: 0x43, level: 3, payload: Data([13, 0])), .init(tag: 0x44, level: 3, payload: shape)]
                }
                records.insert(contentsOf: inserted, at: end)
            }
            if let section = records.firstIndex(where: { $0.tag == 0x47 && (try? $0.payload.hwpWriterUInt32(at: 0)) == 0x7365_6364 }), records[section].payload.count >= 8 {
                let value = try records[section].payload.hwpWriterUInt32(at: 4)
                records[section].payload.hwpWriterSetUInt32(value & ~(request.kind == .header ? 1 : 2), at: 4)
            }
            let bytes = records.reduce(into: Data()) { $0.append($1.serialized()) }
            guard bytes.count <= HWP5TextExtractor.maximumSectionBytes else { throw HWPDocumentEditingError.limitExceeded }
            replacements[path] = try flags & 1 != 0 ? HWP5DocumentRewriter.rawDeflate(bytes) : bytes
        }
        return try container.serialized(replacing: replacements)
    }
}
