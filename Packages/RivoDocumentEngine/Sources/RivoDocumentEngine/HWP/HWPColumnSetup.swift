import Foundation

public nonisolated struct HWPColumnSettings: Equatable, Sendable {
    public var count: Int
    public var gapPoints: Double
    public var showsSeparator: Bool

    public init(_ layout: HWPDocumentColumnLayout) {
        count = layout.count
        gapPoints = count > 1 ? layout.gapPoints : 0
        showsSeparator = count > 1 && layout.separator?.isVisible == true
    }

    public init(count: Int, gapPoints: Double, showsSeparator: Bool) {
        self.count = count
        self.gapPoints = count > 1 ? gapPoints : 0
        self.showsSeparator = count > 1 && showsSeparator
    }

    public func isValid(for layout: HWPDocumentPageLayout) -> Bool {
        guard (1...4).contains(count), gapPoints.isFinite, (0...144).contains(gapPoints) else { return false }
        let contentWidth = layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints
        return contentWidth - gapPoints * Double(count - 1) >= Double(count) * 36
    }

    public func matches(_ layout: HWPDocumentPageLayout) -> Bool {
        layout.columnLayout.count == count
            && abs((count > 1 ? layout.columnLayout.gapPoints : 0) - gapPoints) < 0.03
            && (count > 1 && layout.columnLayout.separator?.isVisible == true) == showsSeparator
    }
}

public nonisolated struct HWPColumnSetupRequest: Sendable {
    public let settings: HWPColumnSettings
    public let sections: Set<Int>

    public init(settings: HWPColumnSettings, sections: Set<Int>) {
        self.settings = settings
        self.sections = sections
    }
}

public nonisolated enum HWPColumnSetup {
    public struct Selection: Identifiable {
        public let id = UUID()
        public let layout: HWPDocumentPageLayout
        public let layouts: [HWPDocumentPageLayout]
    
    public init(layout: HWPDocumentPageLayout, layouts: [HWPDocumentPageLayout]) {
        self.layout = layout
        self.layouts = layouts
    }
}

    public static func validate(_ request: HWPColumnSetupRequest,
                         layouts: [HWPDocumentPageLayout]) throws {
        guard !request.sections.isEmpty,
              request.sections.isSubset(of: Set(layouts.map(\.sectionIndex))) else {
            throw HWPDocumentEditingError.staleDocument
        }
        guard layouts.filter({ request.sections.contains($0.sectionIndex) })
            .allSatisfy({ request.settings.isValid(for: $0) }) else {
            throw HWPDocumentEditingError.limitExceeded
        }
    }

    @MainActor public static func applying(_ request: HWPColumnSetupRequest,
                                    source: HWPTableStructureDocument,
                                    drafts: [HWPDocumentBlock]) async throws
        -> HWPTableStructureDocument {
        try validate(request, layouts: source.layouts)
        let serialized = try source.serialized(drafts)
        let base = try HWPTableStructureDocument.load(serialized)
        try validate(request, layouts: base.layouts)
        for layout in base.layouts where request.sections.contains(layout.sectionIndex) {
            let root = base.blocks.filter {
                HWPPageSetup.sectionIndex($0.sectionPath) == layout.sectionIndex
                    && $0.region.kind == .body && $0.layoutContainerID == nil
            }
            guard root.allSatisfy({ $0.tableLocation == nil && $0.canvasObjects.isEmpty }) else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
        }
        let changed = try await Task.detached(priority: .userInitiated) {
            let data = try HWPColumnSetupWriter.apply(request, to: base)
            return try HWPTableStructureDocument.load(data)
        }.value
        var flowed = changed.blocks
        for layout in changed.layouts where request.sections.contains(layout.sectionIndex) {
            flowed = HWPFlowLayout.reflowingSection(flowed,
                sectionIndex: layout.sectionIndex, layout: layout.pageSetupFlowLayout)
        }
        let final = try await Task.detached(priority: .userInitiated) {
            try HWPTableStructureDocument.load(changed.serialized(flowed))
        }.value
        guard final.layouts.filter({ request.sections.contains($0.sectionIndex) })
                .allSatisfy(request.settings.matches),
              final.blocks.map(\.text) == flowed.map(\.text),
              final.blocks.count == flowed.count else {
            throw HWPDocumentEditingError.cannotSave
        }
        return final
    }
}

public nonisolated enum HWPColumnSetupWriter {
    private static let controlHeaderTag: UInt32 = 0x47
    private static let sectionControlID: UInt32 = 0x7365_6364 // "secd"
    private static let columnControlID: UInt32 = 0x636F_6C64 // "cold"

    public static func apply(_ request: HWPColumnSetupRequest,
                      to source: HWPTableStructureDocument) throws -> Data {
        try HWPColumnSetup.validate(request, layouts: source.layouts)
        switch source {
        case .hwpx(let package): return try hwpx(request, package: package)
        case .hwp(_, let data): return try hwp(request, data: data)
        }
    }

    private static func raw(_ points: Double) -> String {
        String(Int((points * 100).rounded()))
    }

    private static func columnXML(prefix: String, settings: HWPColumnSettings) -> String {
        let separator = settings.showsSeparator
            ? "<\(prefix)colLine type=\"SOLID\" width=\"0.12 mm\" color=\"#000000\"/>" : ""
        return "<\(prefix)colPr type=\"NEWSPAPER\" layout=\"LEFT\" colCount=\"\(settings.count)\" sameSz=\"1\" sameGap=\"\(raw(settings.gapPoints))\">\(separator)</\(prefix)colPr>"
    }

    private static func hwpx(_ request: HWPColumnSetupRequest,
                             package: HWPXDocumentPackage) throws -> Data {
        var replacements: [String: Data] = [:]
        var found: Set<Int> = []
        for section in package.sections {
            guard let index = HWPPageSetup.sectionIndex(section.path),
                  request.sections.contains(index) else { continue }
            let runs = try HWPFormattingXML.elements(section.xml, name: "run")
            guard let firstRun = runs.first else { throw HWPDocumentEditingError.unsupportedEdit }
            let prefix = try HWPFormattingXML.prefix(firstRun.xml)
            let columns = try HWPFormattingXML.elements(section.xml, name: "colpr")
            guard columns.count <= 1 else { throw HWPDocumentEditingError.unsupportedEdit }
            var xml = section.xml
            let replacement = columnXML(prefix: prefix, settings: request.settings)
            if let old = columns.first {
                xml = (xml as NSString).replacingCharacters(in: old.range, with: replacement)
            } else if let sectionProperties = try HWPFormattingXML.elements(xml, name: "secpr").first {
                let settings = try HWPFormattingXML.append(replacement, to: sectionProperties.xml)
                xml = (xml as NSString).replacingCharacters(in: sectionProperties.range, with: settings)
            } else {
                guard let token = try HWPXParagraphXMLPatcher.tagTokens(in: firstRun.xml).first,
                      !token.isSelfClosing else { throw HWPDocumentEditingError.unsupportedEdit }
                let value = "<\(prefix)secPr>\(replacement)</\(prefix)secPr>"
                xml = (xml as NSString).replacingCharacters(in:
                    NSRange(location: firstRun.range.location + NSMaxRange(token.range), length: 0),
                    with: value)
            }
            replacements[section.path] = Data(xml.utf8)
            found.insert(index)
        }
        guard found == request.sections else { throw HWPDocumentEditingError.staleDocument }
        return try HWPXEditingArchive(data: package.sourceData).repack(replacing: replacements)
    }

    private static func hwp(_ request: HWPColumnSetupRequest, data: Data) throws -> Data {
        let container = try OLECompoundFile(data: data)
        let flags = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36)
        guard flags & 0x6796 == 0 else { throw HWPDocumentEditingError.protectedDocument }
        let compressed = flags & 1 != 0
        var replacements: [String: Data] = [:]
        var found: Set<Int> = []
        for path in container.streamNames where path.hasPrefix("bodytext/section") {
            guard let index = HWPPageSetup.sectionIndex(path),
                  request.sections.contains(index) else { continue }
            let stored = try container.stream(named: path)
            let expanded = try compressed
                ? HWP5TextExtractor.inflateRawDeflate(stored,
                    maximumBytes: HWP5TextExtractor.maximumSectionBytes) : stored
            var records = try HWP5DocumentRewriter.parseRecords(expanded)
            let columnPositions = records.indices.filter {
                records[$0].tag == controlHeaderTag && records[$0].payload.count >= 4
                    && (try? records[$0].payload.hwpWriterUInt32(at: 0)) == columnControlID
            }
            if columnPositions.isEmpty {
                guard let sectionPosition = records.indices.first(where: {
                    records[$0].tag == controlHeaderTag && records[$0].payload.count >= 4
                        && (try? records[$0].payload.hwpWriterUInt32(at: 0)) == sectionControlID
                }) else { throw HWPDocumentEditingError.unsupportedEdit }
                let level = records[sectionPosition].level
                var insertion = sectionPosition + 1
                while insertion < records.count, records[insertion].level > level { insertion += 1 }
                records.insert(.init(tag: controlHeaderTag, level: level,
                    payload: payload(settings: request.settings, old: nil)), at: insertion)
            } else {
                for position in columnPositions {
                    records[position].payload = payload(settings: request.settings,
                        old: records[position].payload)
                }
            }
            let body = records.reduce(into: Data()) { $0.append($1.serialized()) }
            replacements[path] = try compressed ? HWP5DocumentRewriter.rawDeflate(body) : body
            found.insert(index)
        }
        guard found == request.sections else { throw HWPDocumentEditingError.staleDocument }
        return try container.serialized(replacing: replacements)
    }

    private static func payload(settings: HWPColumnSettings, old: Data?) -> Data {
        var property = (try? old?.hwpWriterUInt16(at: 4)) ?? 0
        property &= ~UInt16(0x03FC)
        property |= UInt16(settings.count << 2) | UInt16(1 << 12)
        var result = Data()
        result.hwpWriterAppendUInt32(columnControlID)
        result.hwpWriterAppendUInt16(property)
        result.hwpWriterAppendUInt16(UInt16(clamping: Int((settings.gapPoints * 100).rounded())))
        result.hwpWriterAppendUInt16(0)
        result.append(settings.showsSeparator ? 1 : 0)
        result.append(0)
        result.hwpWriterAppendUInt32(0)
        return result
    }
}
