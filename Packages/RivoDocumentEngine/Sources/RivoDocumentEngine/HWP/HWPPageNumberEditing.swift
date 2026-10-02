import Foundation

public nonisolated struct HWPPageNumberRequest: Sendable {
    public let style: HWPDocumentPageNumberStyle?
    public let sections: Set<Int>

    public func style(for section: Int, layouts: [HWPDocumentPageLayout]) -> HWPDocumentPageNumberStyle? {
        guard let style else { return nil }
        let first = layouts.first { sections.contains($0.sectionIndex) }?.sectionIndex
        return .init(position: style.position, sideCharacter: style.sideCharacter,
                     startsAt: section == first ? style.startsAt : nil)
    }

    public init(style: HWPDocumentPageNumberStyle? = nil, sections: Set<Int>) {
        self.style = style
        self.sections = sections
    }
}

public nonisolated enum HWPPageNumberEditing {
    public static let positions = ["TOP_LEFT", "TOP_CENTER", "TOP_RIGHT", "BOTTOM_LEFT", "BOTTOM_CENTER", "BOTTOM_RIGHT"]
    public static func validate(_ request: HWPPageNumberRequest, layouts: [HWPDocumentPageLayout]) throws {
        guard !request.sections.isEmpty, request.sections.isSubset(of: Set(layouts.map(\.sectionIndex))) else {
            throw HWPDocumentEditingError.staleDocument
        }
        if let style = request.style {
            guard positions.contains(style.position), ["", "-"].contains(style.sideCharacter),
                  style.startsAt.map({ (1...65_535).contains($0) }) ?? true else {
                throw HWPDocumentEditingError.limitExceeded
            }
        }
    }
    public static func applying(_ request: HWPPageNumberRequest, source: HWPTableStructureDocument,
                         drafts: [HWPDocumentBlock]) async throws -> HWPTableStructureDocument {
        try validate(request, layouts: source.layouts)
        return try await Task.detached(priority: .userInitiated) {
            let original = try HWPTableStructureDocument.load(source.serialized(drafts))
            let changed = try HWPTableStructureDocument.load(HWPPageNumberWriter.apply(request, to: original))
            guard original.blocks.count == changed.blocks.count,
                  zip(original.blocks, changed.blocks).allSatisfy({ HWPDocumentFormatting.matches($0, $1) }),
                  original.layouts.count == changed.layouts.count else { throw HWPDocumentEditingError.cannotSave }
            for (before, after) in zip(original.layouts, changed.layouts) {
                guard HWPPageSettings(before).matches(after),
                      request.sections.contains(after.sectionIndex)
                        ? after.pageNumberStyle == request.style(for: after.sectionIndex, layouts: original.layouts)
                        : before == after else { throw HWPDocumentEditingError.cannotSave }
            }
            return changed
        }.value
    }
}
