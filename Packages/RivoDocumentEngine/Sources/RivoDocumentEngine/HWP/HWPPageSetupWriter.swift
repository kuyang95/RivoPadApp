import Foundation

public nonisolated enum HWPPageSetupWriter {
    public static func apply(_ request: HWPPageSetupRequest, to source: HWPTableStructureDocument) throws -> Data {
        try HWPPageSetup.validate(request, layouts: source.layouts)
        switch source {
        case .hwpx(let package): return try hwpx(request, package: package)
        case .hwp(_, let data): return try hwp(request, data: data)
        }
    }
    private static func raw(_ points: Double) -> String { String(Int((points * 100).rounded())) }
    private static func hwpx(_ request: HWPPageSetupRequest, package: HWPXDocumentPackage) throws -> Data {
        let s = request.settings
        var replacements: [String: Data] = [:], found: Set<Int> = []
        for section in package.sections {
            guard let index = HWPPageSetup.sectionIndex(section.path), request.sections.contains(index) else { continue }
            let pages = try HWPFormattingXML.elements(section.xml, name: "pagepr")
            guard pages.count <= 1 else { throw HWPDocumentEditingError.unsupportedEdit }
            let runs = try HWPFormattingXML.elements(section.xml, name: "run")
            guard let firstRun = runs.first else { throw HWPDocumentEditingError.unsupportedEdit }
            let paragraphPrefix = try HWPFormattingXML.prefix(firstRun.xml)
            var page = pages.first?.xml ?? "<\(paragraphPrefix)pagePr/>"
            for (key, value) in ["width": raw(min(s.width, s.height)), "height": raw(max(s.width, s.height)),
                                 "landscape": s.isLandscape ? "NARROWLY" : "WIDELY"] {
                page = try HWPFormattingXML.setAttribute(page, key, value)
            }
            let marginElement = try HWPFormattingXML.elements(page, name: "margin").first
            var margin = marginElement?.xml ?? "<\(paragraphPrefix)margin/>"
            for (key, value) in ["left": s.left, "right": s.right, "top": s.top, "bottom": s.bottom, "header": s.header, "footer": s.footer] {
                margin = try HWPFormattingXML.setAttribute(margin, key, raw(value))
            }
            page = try HWPFormattingXML.replaceOrAppend(page, name: "margin", replacement: margin)
            var xml = section.xml
            if let original = pages.first {
                xml = (xml as NSString).replacingCharacters(in: original.range, with: page)
            } else if let sec = try HWPFormattingXML.elements(xml, name: "secpr").first {
                let settings = try HWPFormattingXML.append(page, to: sec.xml)
                xml = (xml as NSString).replacingCharacters(in: sec.range, with: settings)
            } else {
                // Newly created documents may omit section properties. Install
                // them at the start of the first run, before its text/table.
                guard let token = try HWPXParagraphXMLPatcher.tagTokens(in: firstRun.xml).first, !token.isSelfClosing else {
                    throw HWPDocumentEditingError.unsupportedEdit
                }
                xml = (xml as NSString).replacingCharacters(in: NSRange(location: firstRun.range.location + NSMaxRange(token.range), length: 0),
                    with: "<\(paragraphPrefix)secPr>\(page)</\(paragraphPrefix)secPr>")
            }
            replacements[section.path] = Data(xml.utf8); found.insert(index)
        }
        guard found == request.sections else { throw HWPDocumentEditingError.staleDocument }
        return try HWPXEditingArchive(data: package.sourceData).repack(replacing: replacements)
    }
    private static func hwp(_ request: HWPPageSetupRequest, data: Data) throws -> Data {
        let container = try OLECompoundFile(data: data)
        let flags = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36)
        guard flags & 0x6796 == 0 else { throw HWPDocumentEditingError.protectedDocument }
        let compressed = flags & 1 != 0, s = request.settings
        var replacements: [String: Data] = [:], found: Set<Int> = []
        for path in container.streamNames where path.hasPrefix("bodytext/section") {
            guard let index = HWPPageSetup.sectionIndex(path), request.sections.contains(index) else { continue }
            let stored = try container.stream(named: path)
            let expanded = try compressed ? HWP5TextExtractor.inflateRawDeflate(stored, maximumBytes: HWP5TextExtractor.maximumSectionBytes) : stored
            var records = try HWP5DocumentRewriter.parseRecords(expanded)
            let positions = records.indices.filter { records[$0].tag == 0x49 }
            guard positions.count == 1, let position = positions.first, records[position].payload.count >= 40 else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            let values = [min(s.width, s.height), max(s.width, s.height), s.left, s.right, s.top, s.bottom, s.header, s.footer]
            for (offset, value) in values.enumerated() {
                records[position].payload.hwpWriterSetUInt32(UInt32((value * 100).rounded()), at: offset * 4)
            }
            let oldFlags = try records[position].payload.hwpWriterUInt32(at: 36)
            records[position].payload.hwpWriterSetUInt32((oldFlags & ~1) | (s.isLandscape ? 1 : 0), at: 36)
            // Keep the gutter, binding flags and any extension bytes intact.
            let payload = records.reduce(into: Data()) { $0.append($1.serialized()) }
            replacements[path] = try compressed ? HWP5DocumentRewriter.rawDeflate(payload) : payload
            found.insert(index)
        }
        guard found == request.sections else { throw HWPDocumentEditingError.staleDocument }
        return try container.serialized(replacing: replacements)
    }
}
