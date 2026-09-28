import Foundation
import CoreGraphics

nonisolated struct ExcelFrozenPanes: Equatable, Sendable {
    var rows: Int
    var columns: Int
    static let none = ExcelFrozenPanes(rows: 0, columns: 0)
    var isEnabled: Bool { rows > 0 || columns > 0 }
    var firstScrollableCell: ExcelCellAddress { .init(row: rows + 1, column: columns + 1) }

    static func read(_ attributes: [String: String]) -> ExcelFrozenPanes {
        guard ["frozen", "frozenSplit"].contains(attributes["state"] ?? "") else { return .none }
        func count(_ key: String, maximum: Int) -> Int {
            guard let value = Double(attributes[key] ?? "0"), value.isFinite, value >= 0,
                  value < Double(maximum), value.rounded(.towardZero) == value else { return 0 }
            return Int(value)
        }
        return .init(rows: count("ySplit", maximum: 1_048_576), columns: count("xSplit", maximum: 16_384))
    }

    func shifted(by change: ExcelStructureChange) -> ExcelFrozenPanes {
        var result = self
        let count = change.axis == .row ? rows : columns
        let next = count == 0 ? 0 : change.interval(1, count)?.upperBound ?? 0
        if change.axis == .row { result.rows = next } else { result.columns = next }
        return result
    }

    func write(to root: ExcelEditingXML.Node) throws {
        guard rows >= 0, columns >= 0, rows < ExcelWorkbookDocument.maximumRowsPerSheet,
              columns < ExcelWorkbookDocument.maximumColumnsPerSheet else {
            throw ExcelEditingError("고정 기준은 일반 문서의 2,000행·200열 안에서 선택해 주세요.")
        }
        let views = root.child("sheetViews") ?? root.make("sheetViews")
        if root.child("sheetViews") == nil {
            root.children.insert(views, at: root.children.firstIndex { !["sheetPr", "dimension"].contains($0.localName) } ?? root.children.count)
        }
        let view = views.elements("sheetView").first { ($0.attributes["workbookViewId"] ?? "0") == "0" } ?? views.make("sheetView", ["workbookViewId": "0"])
        view.attributes["workbookViewId"] = "0"
        if !views.children.contains(where: { $0 === view }) { views.children.insert(view, at: 0) }
        let priorSelection = view.elements("selection").first { $0.attributes["pane"] == view.child("pane")?.attributes["activePane"] }
            ?? view.elements("selection").first
        let selection = priorSelection?.copy() ?? view.make("selection", ["activeCell": "A1", "sqref": "A1"])
        selection.attributes["pane"] = nil
        view.remove("pane"); view.remove("selection")
        if isEnabled {
            let active = rows > 0 && columns > 0 ? "bottomRight" : rows > 0 ? "bottomLeft" : "topRight"
            var attrs = ["state": "frozen", "topLeftCell": firstScrollableCell.reference, "activePane": active]
            if rows > 0 { attrs["ySplit"] = String(rows) }
            if columns > 0 { attrs["xSplit"] = String(columns) }
            view.children.insert(view.make("pane", attrs), at: 0)
            selection.attributes["pane"] = active
            selection.attributes["activeCell"] = firstScrollableCell.reference
            selection.attributes["sqref"] = firstScrollableCell.reference
            selection.attributes["activeCellId"] = nil
        }
        view.children.insert(selection, at: isEnabled ? 1 : 0)
    }
}

/// One document coordinate system drives painting, taps, range drags and reveal.
/// Oversized frozen regions are clipped while leaving room to scroll the body.
nonisolated struct ExcelFrozenViewport {
    enum Part: CaseIterable, Hashable { case rows, columns, corner }
    let documentSize: CGSize
    let viewportSize: CGSize
    let frozenSize: CGSize
    let scale: CGFloat
    let offset: CGPoint

    var insets: CGSize {
        CGSize(width: min(frozenSize.width * scale, max(0, viewportSize.width - min(96, viewportSize.width / 2))),
               height: min(frozenSize.height * scale, max(0, viewportSize.height - min(96, viewportSize.height / 2))))
    }
    var minimumOffset: CGPoint {
        CGPoint(x: max(0, frozenSize.width * scale - insets.width), y: max(0, frozenSize.height * scale - insets.height))
    }
    func clamped(_ value: CGPoint) -> CGPoint {
        CGPoint(x: min(max(value.x, minimumOffset.x), max(minimumOffset.x, documentSize.width * scale - viewportSize.width)),
                y: min(max(value.y, minimumOffset.y), max(minimumOffset.y, documentSize.height * scale - viewportSize.height)))
    }
    func documentPoint(at point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x < insets.width ? point.x : point.x + offset.x) / scale,
                y: (point.y < insets.height ? point.y : point.y + offset.y) / scale)
    }
    var bodyRect: CGRect {
        CGRect(x: (offset.x + insets.width) / scale, y: (offset.y + insets.height) / scale,
               width: max(0, viewportSize.width - insets.width) / scale, height: max(0, viewportSize.height - insets.height) / scale)
    }
    func frame(for part: Part) -> CGRect {
        switch part {
        case .rows: return CGRect(x: insets.width, y: 0, width: viewportSize.width - insets.width, height: insets.height)
        case .columns: return CGRect(x: 0, y: insets.height, width: insets.width, height: viewportSize.height - insets.height)
        case .corner: return CGRect(origin: .zero, size: insets)
        }
    }
    func visibleRect(for part: Part) -> CGRect {
        let frame = frame(for: part)
        let origin: CGPoint
        switch part {
        case .rows: origin = CGPoint(x: (offset.x + insets.width) / scale, y: 0)
        case .columns: origin = CGPoint(x: 0, y: (offset.y + insets.height) / scale)
        case .corner: origin = .zero
        }
        return CGRect(origin: origin, size: CGSize(width: frame.width / scale, height: frame.height / scale))
    }
    func domain(for part: Part?) -> CGRect {
        switch part {
        case .rows: return CGRect(x: frozenSize.width, y: 0, width: max(0, documentSize.width - frozenSize.width), height: frozenSize.height)
        case .columns: return CGRect(x: 0, y: frozenSize.height, width: frozenSize.width, height: max(0, documentSize.height - frozenSize.height))
        case .corner: return CGRect(origin: .zero, size: frozenSize)
        case nil: return CGRect(x: frozenSize.width, y: frozenSize.height, width: max(0, documentSize.width - frozenSize.width), height: max(0, documentSize.height - frozenSize.height))
        }
    }
    func buffered(_ rect: CGRect, part: Part? = nil) -> CGRect {
        rect.insetBy(dx: -max(rect.width / 2, 120), dy: -max(rect.height / 2, 120)).intersection(domain(for: part))
    }
    func revealing(_ rect: CGRect) -> CGPoint {
        func axis(_ start: CGFloat, _ end: CGFloat, _ offset: CGFloat, _ frozen: CGFloat, _ inset: CGFloat, _ viewport: CGFloat) -> CGFloat {
            guard start >= frozen else { return offset }
            let lower = start * scale, upper = end * scale
            if upper - lower > viewport - inset || lower < offset + inset { return lower - inset }
            if upper > offset + viewport { return upper - viewport }
            return offset
        }
        return clamped(CGPoint(x: axis(rect.minX, rect.maxX, offset.x, frozenSize.width, insets.width, viewportSize.width),
                               y: axis(rect.minY, rect.maxY, offset.y, frozenSize.height, insets.height, viewportSize.height)))
    }
}
