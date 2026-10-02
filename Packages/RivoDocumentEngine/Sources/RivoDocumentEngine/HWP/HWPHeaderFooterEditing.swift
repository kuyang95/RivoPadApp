import Foundation

public nonisolated enum HWPHeaderFooterKind: String, CaseIterable, Identifiable, Sendable {
    case header, footer
    public var id: String { rawValue }
    public var title: String { self == .header ? "머리말" : "꼬리말" }
    public var region: HWPDocumentRegionKind { self == .header ? .header : .footer }
    public var controlID: UInt32 { self == .header ? 0x6865_6164 : 0x666F_6F74 }
    public func band(_ layout: HWPDocumentPageLayout) -> Double { self == .header ? layout.headerMarginPoints : layout.footerMarginPoints }
}

public nonisolated struct HWPHeaderFooterRequest: Sendable {
    public let kind: HWPHeaderFooterKind
    public let texts: [String]
    public let sections: Set<Int>
    public var alignment: HWPParagraphAlignment? = nil
    public var size: Double? = nil
    public var scope: HWPDocumentHeaderFooterScope = .bothPages

    public init(kind: HWPHeaderFooterKind, texts: [String], sections: Set<Int>, alignment: HWPParagraphAlignment? = nil, size: Double? = nil, scope: HWPDocumentHeaderFooterScope = .bothPages) {
        self.kind = kind
        self.texts = texts
        self.sections = sections
        self.alignment = alignment
        self.size = size
        self.scope = scope
    }
}

public nonisolated enum HWPHeaderFooterEditing {
    public struct Selection: Identifiable {
        public let id = UUID()
        public let kind: HWPHeaderFooterKind
        public let section: Int
        public let layouts: [HWPDocumentPageLayout]
        public let paragraphs: [Int: [HWPDocumentBlock]]
        public let supported: Set<Int>
        public var current: [HWPDocumentBlock] { paragraphs[section] ?? [] }
    
    public init(kind: HWPHeaderFooterKind, section: Int, layouts: [HWPDocumentPageLayout], paragraphs: [Int: [HWPDocumentBlock]], supported: Set<Int>) {
        self.kind = kind
        self.section = section
        self.layouts = layouts
        self.paragraphs = paragraphs
        self.supported = supported
    }
}
    public static func paragraphs(_ blocks: [HWPDocumentBlock], kind: HWPHeaderFooterKind, section: Int) -> [HWPDocumentBlock] {
        blocks.filter { HWPPageSetup.sectionIndex($0.sectionPath) == section && $0.region.kind == kind.region }
    }
    public static func selection(kind: HWPHeaderFooterKind, section: Int, source: HWPTableStructureDocument, drafts: [HWPDocumentBlock]) -> Selection {
        var paragraphs: [Int: [HWPDocumentBlock]] = [:], supported: Set<Int> = []
        for layout in source.layouts {
            paragraphs[layout.sectionIndex] = Self.paragraphs(drafts, kind: kind, section: layout.sectionIndex)
            if (try? HWPHeaderFooterWriter.validate(kind, section: layout.sectionIndex, source: source)) != nil {
                supported.insert(layout.sectionIndex)
            }
        }
        return Selection(kind: kind, section: section, layouts: source.layouts, paragraphs: paragraphs, supported: supported)
    }
    public static func remappedSelection(_ id: String?, before: [HWPDocumentBlock], after: [HWPDocumentBlock], request: HWPHeaderFooterRequest) -> String? {
        func retained(_ block: HWPDocumentBlock) -> Bool {
            !(request.sections.contains(HWPPageSetup.sectionIndex(block.sectionPath) ?? -1) && block.region.kind == request.kind.region)
        }
        guard let index = before.filter(retained).firstIndex(where: { $0.id == id }) else { return nil }
        let remaining = after.filter(retained)
        return remaining.indices.contains(index) ? remaining[index].id : nil
    }
    public static func validate(_ request: HWPHeaderFooterRequest, source: HWPTableStructureDocument) throws {
        guard !request.sections.isEmpty, request.sections.isSubset(of: Set(source.layouts.map(\.sectionIndex))) else { throw HWPDocumentEditingError.staleDocument }
        guard (1...8).contains(request.texts.count), request.texts.reduce(0, { $0 + $1.utf16.count }) <= 2_000,
              request.texts.allSatisfy({ !$0.unicodeScalars.contains { $0.value < 32 && ![9, 10].contains($0.value) } }),
              request.size.map({ $0.isFinite && (6...36).contains($0) }) ?? true,
              request.alignment.map({ [.leading, .centered, .trailing].contains($0) }) ?? true else { throw HWPDocumentEditingError.limitExceeded }
        for section in request.sections {
            try HWPHeaderFooterWriter.validate(request.kind, section: section, source: source)
            let current = paragraphs(source.blocks, kind: request.kind, section: section)
            guard current.isEmpty || current.count == request.texts.count else { throw HWPDocumentEditingError.unsupportedEdit }
        }
    }

    @MainActor public static func applying(_ request: HWPHeaderFooterRequest, source: HWPTableStructureDocument, drafts: [HWPDocumentBlock]) async throws -> HWPTableStructureDocument {
        let original = try await Task.detached(priority: .userInitiated) { try HWPTableStructureDocument.load(source.serialized(drafts)) }.value
        try validate(request, source: original)
        let createdSections = Set(request.sections.filter { paragraphs(original.blocks, kind: request.kind, section: $0).isEmpty })
        let prepared = try await Task.detached(priority: .userInitiated) {
            try HWPTableStructureDocument.load(HWPHeaderFooterWriter.prepare(request, source: original))
        }.value
        var edited = prepared.blocks
        for section in request.sections {
            let indices = edited.indices.filter { HWPPageSetup.sectionIndex(edited[$0].sectionPath) == section && edited[$0].region.kind == request.kind.region }
            guard indices.count == request.texts.count,
                  let layout = prepared.layouts.first(where: { $0.sectionIndex == section }) else { throw HWPDocumentEditingError.cannotSave }
            var y = 0.0
            for (offset, index) in indices.enumerated() {
                var block = HWPTextRunEditing.replacingText(in: edited[index], with: request.texts[offset])
                let range = NSRange(location: 0, length: block.text.utf16.count)
                if createdSections.contains(section) {
                    block = HWPDocumentFormatting.apply(.clearCharacterFormatting, to: block, range: range)
                    block = HWPDocumentFormatting.apply(.paragraph(left: 0, right: 0, indent: 0, before: 0, after: 0, linePercent: 160), to: block, range: range)
                    block = HWPDocumentFormatting.apply(.alignment(.leading), to: block, range: range)
                }
                if let alignment = request.alignment { block = HWPDocumentFormatting.apply(.alignment(alignment), to: block, range: range) }
                if let size = request.size { block = HWPDocumentFormatting.apply(.size(size), to: block, range: range) }
                let width = max(1, layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints
                    - block.presentation.leftMarginPoints - block.presentation.rightMarginPoints)
                y += block.presentation.spacingBeforePoints
                let lines = HWPFlowLayout.measure(block, width: width, startY: y, pageHeight: nil, minimumHeight: 0)
                if let last = lines.last {
                    let bottom = last.verticalPositionPoints + last.lineHeightPoints
                    if !block.text.isEmpty, bottom > request.kind.band(layout) + 0.03 { throw HWPHeaderFooterError.insufficientSpace }
                    y = bottom + last.lineSpacingPoints + block.presentation.spacingAfterPoints
                }
                edited[index] = block.withLayout(lines: lines)
            }
        }
        let finalBlocks = edited
        let saved = try await Task.detached(priority: .userInitiated) {
            try HWPTableStructureDocument.load(prepared.serialized(finalBlocks))
        }.value
        guard saved.blocks.count == finalBlocks.count, zip(saved.blocks, finalBlocks).allSatisfy({ HWPDocumentFormatting.matches($0, $1) }),
              saved.layouts.count == original.layouts.count else { throw HWPDocumentEditingError.cannotSave }
        // Adding header/footer paragraphs shifts paragraph IDs; compare retained
        // content semantically in document order, including existing cell styles.
        func retained(_ blocks: [HWPDocumentBlock]) -> [HWPDocumentBlock] {
            blocks.filter { !(request.sections.contains(HWPPageSetup.sectionIndex($0.sectionPath) ?? -1) && $0.region.kind == request.kind.region) }
        }
        let before = retained(original.blocks), after = retained(saved.blocks)
        guard before.count == after.count, zip(before, after).allSatisfy({ HWPDocumentFormatting.matches($0, $1) && $0.isEditable == $1.isEditable }) else { throw HWPDocumentEditingError.cannotSave }
        for (old, new) in zip(original.layouts, saved.layouts) {
            guard HWPPageSettings(old).matches(new), old.pageNumberStyle == new.pageNumberStyle, old.pageNumberStart == new.pageNumberStart,
                  old.columnLayout == new.columnLayout,
                  request.kind == .header ? old.hidesFooter == new.hidesFooter : old.hidesHeader == new.hidesHeader else { throw HWPDocumentEditingError.cannotSave }
        }
        for section in request.sections {
            let current = paragraphs(saved.blocks, kind: request.kind, section: section)
            guard current.map(\.text) == request.texts, current.allSatisfy({ $0.region.scope == request.scope }) else { throw HWPDocumentEditingError.cannotSave }
        }
        return saved
    }
}

public nonisolated enum HWPHeaderFooterError: LocalizedError {
    case insufficientSpace
    public var errorDescription: String? { DocumentEngineLocalization.string("머리말·꼬리말 공간이 부족합니다. 글자 크기나 줄 수를 줄이거나 쪽 설정에서 해당 여백을 늘려 주세요.") }
}
