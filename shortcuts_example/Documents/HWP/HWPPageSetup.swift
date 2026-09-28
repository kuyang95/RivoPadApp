import Foundation

nonisolated struct HWPPageSettings: Equatable, Sendable {
    var width: Double, height: Double
    var left: Double, right: Double, top: Double, bottom: Double
    var header: Double, footer: Double
    var isLandscape: Bool { width > height }
    static let pointsPerMM = 72.0 / 25.4

    init(_ layout: HWPDocumentPageLayout) {
        width = layout.widthPoints; height = layout.heightPoints
        left = layout.leftMarginPoints; right = layout.rightMarginPoints
        top = layout.topMarginPoints; bottom = layout.bottomMarginPoints
        header = layout.headerMarginPoints; footer = layout.footerMarginPoints
    }
    var isValid: Bool {
        let margins = [left, right, top, bottom, header, footer]
        return [width, height].allSatisfy { $0.isFinite && (72...2_000).contains($0) }
            && margins.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= min(width, height) * 0.45 }
            && width - left - right >= 36 && height - top - bottom - header - footer >= 36
    }
    func matches(_ layout: HWPDocumentPageLayout) -> Bool {
        let b = Self(layout)
        return zip(values, b.values).allSatisfy { abs($0 - $1) < 0.03 }
    }
    var values: [Double] { [width, height, left, right, top, bottom, header, footer] }
    mutating func orient(landscape: Bool) {
        if landscape != isLandscape { swap(&width, &height) }
    }
}

nonisolated struct HWPPageSetupRequest: Sendable {
    let settings: HWPPageSettings
    let sections: Set<Int>
}

nonisolated enum HWPPageSetup {
    struct Selection: Identifiable {
        let id = UUID()
        let layout: HWPDocumentPageLayout
        let layouts: [HWPDocumentPageLayout]
    }
    static func sectionIndex(_ path: String) -> Int? {
        Int(path.lowercased().components(separatedBy: "section").last?.replacingOccurrences(of: ".xml", with: "") ?? "")
    }
    static func validate(_ request: HWPPageSetupRequest, layouts: [HWPDocumentPageLayout]) throws {
        guard request.settings.isValid else { throw HWPDocumentEditingError.limitExceeded }
        guard !request.sections.isEmpty, request.sections.isSubset(of: Set(layouts.map(\.sectionIndex))) else {
            throw HWPDocumentEditingError.staleDocument
        }
        guard layouts.filter({ request.sections.contains($0.sectionIndex) }).allSatisfy({ $0.columnLayout.columns.count <= 1 }) else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
    }

    @MainActor static func applying(_ request: HWPPageSetupRequest, source: HWPTableStructureDocument,
                                    drafts: [HWPDocumentBlock]) async throws -> HWPTableStructureDocument {
        try validate(request, layouts: source.layouts)
        let (original, changed) = try await Task.detached(priority: .userInitiated) {
            let original = try HWPTableStructureDocument.load(source.serialized(drafts))
            try validate(request, layouts: original.layouts)
            let data = try HWPPageSetupWriter.apply(request, to: original)
            return (original, try HWPTableStructureDocument.load(data))
        }.value
        var flowed = changed.blocks
        for layout in changed.layouts where request.sections.contains(layout.sectionIndex) {
            let indices = flowed.indices.filter { sectionIndex(flowed[$0].sectionPath) == layout.sectionIndex }
            let oldLayout = original.layouts.first { $0.sectionIndex == layout.sectionIndex } ?? layout
            let before = HWPFlowLayout.resolvingMissingLines(indices.map { original.blocks[$0] }, layout: oldLayout)
            var section = HWPFlowLayout.resolvingMissingLines(indices.map { flowed[$0] }, layout: layout)
            guard let first = section.firstIndex(where: { $0.region.kind == .body && $0.tableLocation == nil && $0.layoutContainerID == nil }) else { continue }
            // The original leading inset is retained; cached automatic page
            // boundaries are recalculated while explicit paragraph breaks stay.
            let working = layout.pageSetupFlowLayout
            section = HWPFlowLayout.reflowingBody(section, before: before, startingAt: section[first].id,
                layouts: [working], reflowingTables: true)
            for (offset, index) in indices.enumerated() { flowed[index] = section[offset] }
        }
        let edited = flowed
        let final = try await Task.detached(priority: .userInitiated) {
            try HWPTableStructureDocument.load(changed.serialized(edited))
        }.value
        guard final.blocks.count == edited.count,
              zip(final.blocks, edited).allSatisfy({ HWPDocumentFormatting.matches($0, $1) }),
              final.layouts.filter({ request.sections.contains($0.sectionIndex) }).allSatisfy({ request.settings.matches($0) }) else {
            throw HWPDocumentEditingError.cannotSave
        }
        return final
    }
}

nonisolated extension HWPDocumentPageLayout {
    /// Flow coordinates begin below the header band, just like the canvas.
    var pageSetupFlowLayout: Self {
        Self(sectionIndex: sectionIndex, widthPoints: widthPoints, heightPoints: heightPoints,
            leftMarginPoints: leftMarginPoints, rightMarginPoints: rightMarginPoints,
            topMarginPoints: topMarginPoints + headerMarginPoints, bottomMarginPoints: bottomMarginPoints + footerMarginPoints,
            headerMarginPoints: 0, footerMarginPoints: 0, gutterPoints: gutterPoints, isLandscape: isLandscape,
            hidesHeader: hidesHeader, hidesFooter: hidesFooter, hidesBackground: hidesBackground,
            hidesPageBorder: hidesPageBorder, hidesPageBackground: hidesPageBackground,
            pageBorderFirstPageOnly: pageBorderFirstPageOnly, pageBackgroundFirstPageOnly: pageBackgroundFirstPageOnly,
            pageStyle: pageStyle, footnoteStyle: footnoteStyle, endnoteStyle: endnoteStyle,
            columnLayout: columnLayout, pageNumberStyle: pageNumberStyle, pageNumberStart: pageNumberStart)
    }
}
