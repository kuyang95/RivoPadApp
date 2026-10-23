import SwiftUI

struct RatioHomeItem: Identifiable, Codable {
    var id: String
    var name: String
    var textOnly = false
    var columns = 2
    var rows = 2
    var textSize = 36
    var iconOnly: Bool?
    var colorKey: String?
    var iconText: Bool?
    var isWeather: Bool { id == "widget:weather" }
    var isTimer: Bool { id == "widget:timer" }
    var isUtility: Bool { isWeather || isTimer }
    var isNews: Bool { id == "widget:news" }
    var isYouTube: Bool { id == "widget:youtube" }
    var isFullPage: Bool { isYouTube || isBrowser || isDaisy || isNews }
    var isDaisy: Bool { id == "widget:daisy" }
    var isBrowser: Bool { id == "widget:browser" }
    var normalized: RatioHomeItem {
        if isUtility { var item = self; item.columns = columns < 4 ? 2 : 4; item.rows = min(5, max(2, rows)); item.textOnly = false; item.iconOnly = false; return item }
        if isYouTube || isNews { var item = self; item.columns = 4; item.rows = 10; item.textOnly = false; item.iconOnly = false; return item }
        guard isBrowser || isDaisy else { return self }
        var item = self; item.columns = 4; item.rows = min(10, max(isDaisy ? 6 : 8, rows)); item.textOnly = false; item.iconOnly = false
        return item
    }
    var isSearch: Bool { id == "widget:search" }
}
struct RatioSwatch: Identifiable {
    var id: String
    var name: String
    var rgb: UInt32
    var color: Color { VisionCraftUI.fixedColor(rgb) }
}
let ratioPalette: [RatioSwatch] = [
    .init(id: "lemon", name: "레몬", rgb: 0xF3F565), .init(id: "butter", name: "버터", rgb: 0xF1D89A),
    .init(id: "apricot", name: "살구", rgb: 0xF3BC91), .init(id: "coral", name: "코랄", rgb: 0xEDA99A),
    .init(id: "rose", name: "로즈", rgb: 0xE5B2C4), .init(id: "lavender", name: "라벤더", rgb: 0xCBBCEB),
    .init(id: "periwinkle", name: "페리윙클", rgb: 0xAFBDE8), .init(id: "sky", name: "스카이", rgb: 0x9FCDE5),
    .init(id: "aqua", name: "아쿠아", rgb: 0x95D4D1), .init(id: "mint", name: "민트", rgb: 0xADE0C8),
    .init(id: "sage", name: "세이지", rgb: 0xC1CFAD), .init(id: "sand", name: "샌드", rgb: 0xDACDBA)
]
struct RatioSize: Identifiable {
    var columns: Int
    var rows: Int
    var id: String { "\(columns)x\(rows)" }
    init(_ columns: Int, _ rows: Int) { self.columns = columns; self.rows = rows }
}
struct RatioColumnSpan: LayoutValueKey { static let defaultValue = 2 }

/// Four equal columns, stable saved order, natural text height. Never stretches the last row.
struct RatioWidgetGrid: Layout {
    private func placements(_ width: CGFloat, _ subviews: Subviews) -> [(CGPoint, CGSize)] {
        let cell = max(0, (width - 36) / 4)
        var result: [(CGPoint, CGSize)] = []
        var column = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let span = min(4, max(1, view[RatioColumnSpan.self]))
            if column + span > 4 { y += rowHeight + 12; rowHeight = 0; column = 0 }
            let w = cell * CGFloat(span) + 12 * CGFloat(span - 1)
            let size = view.sizeThatFits(ProposedViewSize(width: w, height: nil))
            result.append((CGPoint(x: CGFloat(column) * (cell + 12), y: y), CGSize(width: w, height: size.height)))
            rowHeight = max(rowHeight, size.height); column += span
        }
        return result
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        let frames = placements(width, subviews)
        return CGSize(width: width, height: frames.map { $0.0.y + $0.1.height }.max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, frame) in zip(subviews, placements(bounds.width, subviews)) {
            view.place(at: CGPoint(x: bounds.minX + frame.0.x, y: bounds.minY + frame.0.y), anchor: .topLeading,
                       proposal: ProposedViewSize(frame.1))
        }
    }
}
struct RatioWidgetHeightKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
func ratioItemRows(_ items: [RatioHomeItem]) -> [[RatioHomeItem]] {
    var rows: [[RatioHomeItem]] = []
    var row: [RatioHomeItem] = []
    var used = 0
    for item in items {
        if item.isFullPage {
            if !row.isEmpty { rows.append(row) }
            rows.append([item]); row = []; used = 0
            continue
        }
        let columns = min(4, max(1, item.columns))
        if used + columns > 4 { rows.append(row); row = []; used = 0 }
        row.append(item); used += columns
    }
    if !row.isEmpty { rows.append(row) }
    return rows
}
func ratioPageRows(_ heights: [CGFloat], available: CGFloat, fullPageRows: Set<Int> = []) -> [[Int]] {
    var pages: [[Int]] = []
    var page: [Int] = []
    var used: CGFloat = 0
    for (index, height) in heights.enumerated() {
        if fullPageRows.contains(index) {
            if !page.isEmpty { pages.append(page) }
            pages.append([index]); page = []; used = 0
            continue
        }
        if !page.isEmpty && used + 12 + height > available {
            pages.append(page); page = []; used = 0
        }
        used += (page.isEmpty ? 0 : 12) + height
        page.append(index)
    }
    if !page.isEmpty { pages.append(page) }
    return pages.isEmpty ? [[]] : pages
}

/// Last measured home geometry, retained while the widget picker is open.
struct RatioWidgetPageMetrics: Equatable {
    var rowIDs: [[String]]
    var rowHeights: [CGFloat]
    var available: CGFloat
}

/// Fill the selected page first without changing existing widgets' relative order.
func ratioWidgetInsertionIndex(_ items: [RatioHomeItem], widget: RatioHomeItem, preferredPage: Int,
                               metrics: RatioWidgetPageMetrics?, height: CGFloat) -> Int {
    let fallback = items.firstIndex(where: \.isFullPage) ?? items.count
    if widget.isFullPage { return items.count }
    guard let metrics, metrics.available > 0 else { return fallback }
    let rows = ratioItemRows(items)
    let heights: [CGFloat] = rows.map { row in
        if let index = metrics.rowIDs.firstIndex(of: row.map(\.id)), metrics.rowHeights.indices.contains(index) {
            return metrics.rowHeights[index]
        }
        return row.map { item in
            let previous = metrics.rowIDs.firstIndex(where: { $0.contains(item.id) })
            return max(CGFloat(item.rows * 100 - 12), previous.flatMap { metrics.rowHeights.indices.contains($0) ? metrics.rowHeights[$0] : nil } ?? 0)
        }.max() ?? 0
    }
    let fullRows = Set(rows.indices.filter { rows[$0].count == 1 && rows[$0][0].isFullPage })
    let pages = ratioPageRows(heights, available: metrics.available, fullPageRows: fullRows)
    let candidates = ([preferredPage] + Array(pages.indices)).reduce(into: [Int]()) { result, index in
        if pages.indices.contains(index) && !result.contains(index) { result.append(index) }
    }
    let heightByID = rows.enumerated().reduce(into: [String: CGFloat]()) { result, entry in
        for item in entry.element { result[item.id] = heights[entry.offset] }
    }
    func after(_ row: Int) -> Int { (items.firstIndex(where: { $0.id == rows[row].last?.id }) ?? (fallback - 1)) + 1 }
    func fits(_ index: Int, page: Int) -> Bool {
        var proposed = items
        proposed.insert(widget, at: index)
        let proposedRows = ratioItemRows(proposed)
        let proposedHeights = proposedRows.map { row in row.map { $0.id == widget.id ? height : (heightByID[$0.id] ?? 0) }.max() ?? 0 }
        let fullRows = Set(proposedRows.indices.filter { proposedRows[$0].count == 1 && proposedRows[$0][0].isFullPage })
        let proposedPages = ratioPageRows(proposedHeights, available: metrics.available, fullPageRows: fullRows)
        guard proposedPages.indices.contains(page) else { return false }
        let ids = Set(proposedPages[page].flatMap { proposedRows[$0].map(\.id) })
        return ids.contains(widget.id) && pages[page].flatMap { rows[$0] }.allSatisfy { ids.contains($0.id) }
    }
    for page in candidates {
        let indices = pages[page]
        guard !indices.isEmpty, !indices.contains(where: { rows[$0].contains(where: \.isFullPage) }) else { continue }
        let gaps = indices.filter { rows[$0].reduce(0, { $0 + $1.columns }) + widget.columns <= 4 }.map { after($0) }
        // A new row may need to precede a full row to avoid joining a taller next-page item.
        let positions = gaps + [after(indices.last!)] + indices.reversed().map { after($0) - rows[$0].count }
        if let index = positions.first(where: { fits($0, page: page) }) { return index }
    }
    return fallback
}

func installFullPageWidgets(_ items: [RatioHomeItem]) -> [RatioHomeItem] {
    let ordinary = items.filter { !$0.isFullPage }
    let youtube = items.first(where: \.isYouTube) ?? RatioHomeItem(id: "widget:youtube", name: "쉬운 유튜브", columns: 4, rows: 10)
    var browser = items.first(where: \.isBrowser) ?? RatioHomeItem(id: "widget:browser", name: "쉬운 브라우저", columns: 4, rows: 8)
    browser.name = "쉬운 브라우저"
    let daisy = items.first(where: \.isDaisy) ?? RatioHomeItem(id: "widget:daisy", name: "데이지 플레이어", columns: 4, rows: 6)
    return ordinary + [youtube, browser, daisy] + items.filter(\.isNews)
}

/// Match Android's 4-bit RGB histogram; cache by image data rather than recomputing during layout.
enum RatioIconColor {
    private static let cache: NSCache<NSData, UIColor> = {
        let cache = NSCache<NSData, UIColor>(); cache.countLimit = 64; return cache
    }()
    static func color(_ data: Data) -> Color? {
        let key = data as NSData
        if let cached = cache.object(forKey: key) { return Color(uiColor: cached) }
        guard let image = UIImage(data: data)?.cgImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: 64 * 64 * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 64, height: 64,
                bitsPerComponent: 8, bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64)); return true
        }
        guard drawn else { return nil }
        var bins: [Int: [Int]] = [:]
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Int(bytes[i + 3]); guard alpha >= 128 else { continue }
            let r = min(255, Int(bytes[i]) * 255 / alpha)
            let g = min(255, Int(bytes[i + 1]) * 255 / alpha)
            let b = min(255, Int(bytes[i + 2]) * 255 / alpha)
            if r >= 240 && g >= 240 && b >= 240 { continue }
            let key = (r / 16) << 8 | (g / 16) << 4 | b / 16
            var bin = bins[key] ?? [0, 0, 0, 0]
            bin[0] += 1; bin[1] += r; bin[2] += g; bin[3] += b; bins[key] = bin
        }
        var winner: [Int]?
        for key in bins.keys.sorted() {
            if let bin = bins[key], bin[0] > (winner?[0] ?? 0) { winner = bin }
        }
        guard let bin = winner else { return nil }
        let result = UIColor(red: CGFloat(bin[1] / bin[0]) / 255,
            green: CGFloat(bin[2] / bin[0]) / 255, blue: CGFloat(bin[3] / bin[0]) / 255, alpha: 1)
        cache.setObject(result, forKey: key); return Color(uiColor: result)
    }
}
