import RivoDocumentEngine
import Combine
import SwiftUI

struct HWPDocumentSearchResult: Identifiable, Equatable {
    let pageIndex: Int
    let blockID: String
    let text: String
    let snippet: String
    let match: HWPTextMatch
    var id: String { match.id }
}

/// Paper coordinates stay fixed across scrolling, zooming and input updates.
struct HWPDocumentViewportLayout {
    let pageRects: [CGRect]
    let contentSize: CGSize

    init(pages: [HWPOriginalCanvasPage]) {
        let width = max(1, pages.map { $0.layout.widthPoints }.max() ?? 595) + 40
        var y = 20.0
        pageRects = pages.map { page in
            let rect = CGRect(x: (width - page.layout.widthPoints) / 2, y: y,
                width: page.layout.widthPoints, height: page.layout.heightPoints)
            y = rect.maxY + 18
            return rect
        }
        contentSize = CGSize(width: width, height: max(1, y + 2))
    }

    func pageIndex(in viewport: CGRect) -> Int {
        // At a page boundary, report the page occupying most of the viewport.
        pageRects.indices.max {
            visibleArea(pageRects[$0], viewport) < visibleArea(pageRects[$1], viewport)
        } ?? 0
    }

    private func visibleArea(_ page: CGRect, _ viewport: CGRect) -> CGFloat {
        let visible = page.intersection(viewport)
        return visible.isNull ? 0 : visible.width * visible.height
    }
}

struct HWPDocumentScrollRequest: Equatable {
    let id = UUID()
    let rect: CGRect
    var alignsPageTop = false
}

struct HWPDocumentZoomRequest: Equatable {
    let id = UUID()
    /// nil means fit to the available width.
    let scale: CGFloat?
}

@MainActor
final class HWPDocumentNavigation: ObservableObject {
    @Published private(set) var pages: [HWPOriginalCanvasPage] = []
    @Published private(set) var viewport = HWPDocumentViewportLayout(pages: [])
    @Published private(set) var currentPageIndex = 0
    @Published private(set) var zoomScale: CGFloat = 1
    @Published private(set) var scrollRequest: HWPDocumentScrollRequest?
    @Published private(set) var zoomRequest: HWPDocumentZoomRequest?
    @Published var showsSearch = false
    @Published var query = "" { didSet { if query != oldValue { replacementMessage = nil; search() } } }
    @Published var matchCase = false { didSet { if matchCase != oldValue { replacementMessage = nil; search() } } }
    @Published var showsReplacement = false
    @Published var replacement = ""
    @Published var replacementMessage: String?
    @Published private(set) var exceedsSearchLimit = false
    private var sourceBlocks: [HWPDocumentBlock] = []
    @Published private(set) var results: [HWPDocumentSearchResult] = []
    @Published private(set) var selectedResultIndex = 0
    @Published private(set) var searchSelectionID = UUID()
    private var resolvedSelectionID: UUID?

    var selectedResult: HWPDocumentSearchResult? {
        results.indices.contains(selectedResultIndex) ? results[selectedResultIndex] : nil
    }

    func update(blocks: [HWPDocumentBlock], layouts: [HWPDocumentPageLayout]) {
        sourceBlocks = blocks
        pages = HWPOriginalCanvasPageBuilder.makePages(blocks: blocks, layouts: layouts)
        viewport = HWPDocumentViewportLayout(pages: pages)
        currentPageIndex = min(currentPageIndex, max(0, pages.count - 1))
        search(preservingSelection: true)
    }

    func didScroll(_ rect: CGRect) {
        let index = viewport.pageIndex(in: rect)
        if currentPageIndex != index { currentPageIndex = index }
    }

    func didZoom(_ scale: CGFloat) {
        if abs(zoomScale - scale) > 0.0001 { zoomScale = scale }
    }

    func setZoom(_ scale: CGFloat?) {
        zoomRequest = HWPDocumentZoomRequest(scale: scale)
    }

    func goToPage(_ index: Int) {
        guard viewport.pageRects.indices.contains(index) else { return }
        currentPageIndex = index
        scrollRequest = HWPDocumentScrollRequest(rect: viewport.pageRects[index], alignsPageTop: true)
    }

    func pageNumber(from input: String) -> Int? {
        guard let page = Int(input.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...max(1, pages.count)).contains(page) else { return nil }
        return page
    }

    func moveResult(by offset: Int) {
        guard !results.isEmpty else { return }
        selectedResultIndex = (selectedResultIndex + offset % results.count + results.count) % results.count
        revealResult()
    }

    func closeSearch() {
        showsSearch = false
        query = ""
    }

    func resolveSearchRect(_ rect: CGRect, selectionID: UUID) {
        guard selectionID == searchSelectionID, resolvedSelectionID != selectionID,
              !rect.isEmpty, !rect.isNull, selectedResult != nil else { return }
        resolvedSelectionID = selectionID
        scrollRequest = HWPDocumentScrollRequest(rect: rect.insetBy(dx: -16, dy: -24))
    }

    func selectAfterReplacement(of match: HWPTextMatch, insertedLength: Int) {
        let order = Dictionary(uniqueKeysWithValues: sourceBlocks.enumerated().map { ($0.element.id, $0.offset) })
        let oldIndex = order[match.blockID] ?? 0
        selectedResultIndex = results.firstIndex {
            let index = order[$0.match.blockID] ?? 0
            return index > oldIndex || (index == oldIndex && $0.match.range.location >= match.range.location + insertedLength)
        } ?? 0
        revealResult()
    }

    private func search(preservingSelection: Bool = false) {
        let previousID = selectedResult?.id
        let scan = HWPFindReplace.scan(sourceBlocks, query: query, matchCase: matchCase)
        exceedsSearchLimit = scan.exceedsLimit
        struct Surface {
            let page: Int
            let block: HWPDocumentBlock
            let start: Int
        }
        let sources = Dictionary(uniqueKeysWithValues: sourceBlocks.map { ($0.id, $0) })
        var surfaces: [String: [Surface]] = [:]
        for (pageIndex, page) in pages.enumerated() {
            for block in page.bodyBlocks {
                let id = HWPInlineParagraphGeometry.sourceID(block.id)
                guard let source = sources[id] else { continue }
                let start = block.id == source.id ? 0 : HWPInlineParagraphGeometry.textOffset(in: source.text,
                    raw: block.lineLayouts.first?.startCharacter ?? 0)
                surfaces[id, default: []].append(Surface(page: pageIndex, block: block, start: start))
            }
        }
        results = scan.matches.compactMap { match in
            let candidates = (surfaces[match.blockID] ?? []).sorted {
                $0.start == $1.start ? $0.page < $1.page : $0.start < $1.start
            }
            // Repeated headers and carried merge labels are projections of one
            // logical occurrence. Count and replace the source only once.
            let chosen = candidates.last(where: { surface in
                surface.start <= match.range.location
                    && candidates.first(where: { $0.start == surface.start })?.page == surface.page
            }) ?? candidates.first
            guard let chosen, let range = Range(match.range, in: match.sourceText) else { return nil }
            let text = match.sourceText
            let start = text.index(range.lowerBound, offsetBy: -25, limitedBy: text.startIndex) ?? text.startIndex
            let end = text.index(range.upperBound, offsetBy: 55, limitedBy: text.endIndex) ?? text.endIndex
            let snippet = (start == text.startIndex ? "" : "…")
                + text[start..<end].replacingOccurrences(of: "\n", with: " ") + (end == text.endIndex ? "" : "…")
            return HWPDocumentSearchResult(pageIndex: chosen.page, blockID: chosen.block.id,
                text: chosen.block.text, snippet: snippet, match: match)
        }
        selectedResultIndex = preservingSelection ? results.firstIndex(where: { $0.id == previousID }) ?? 0 : 0
        if !preservingSelection { revealResult() }
    }

    private func revealResult() {
        searchSelectionID = UUID()
        guard let result = selectedResult else { return }
        goToPage(result.pageIndex)
    }
}

struct HWPDocumentSearchContext {
    var result: HWPDocumentSearchResult?
    var pageIndex: Int = -1
    func range(in block: HWPDocumentBlock, line: HWPDocumentLineLayout) -> NSRange? {
        guard matches(block), let result else { return nil }
        let start = HWPInlineParagraphGeometry.textOffset(in: result.match.sourceText, raw: line.startCharacter)
        let selected = NSIntersectionRange(result.match.range, NSRange(location: start, length: line.text.utf16.count))
        guard selected.length > 0 else { return nil }
        return NSRange(location: selected.location - start, length: selected.length)
    }

    func matches(_ block: HWPDocumentBlock) -> Bool {
        result?.pageIndex == pageIndex && result?.blockID == block.id && result?.text == block.text
    }
}

private struct HWPDocumentSearchKey: EnvironmentKey {
    static let defaultValue = HWPDocumentSearchContext()
}

extension EnvironmentValues {
    var hwpDocumentSearch: HWPDocumentSearchContext {
        get { self[HWPDocumentSearchKey.self] }
        set { self[HWPDocumentSearchKey.self] = newValue }
    }
}

struct HWPDocumentSearchRectKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}
