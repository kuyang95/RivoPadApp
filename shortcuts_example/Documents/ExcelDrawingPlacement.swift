import Foundation
import CoreGraphics

/// DrawingML coordinates are EMUs (9,525 per 96-dpi pixel), including sub-cell offsets.
nonisolated struct ExcelDrawingOffset: Hashable, Sendable {
    var x: Int64
    var y: Int64
    static let zero = ExcelDrawingOffset(x: 0, y: 0)
}

nonisolated enum ExcelDrawingPlacementXML {
    static func read(_ root: ExcelEditingXML.Node) -> ExcelDrawingAnchor {
        func number(_ text: String?) -> Int64 { max(0, min(Int64(text ?? "") ?? 0, 100_000_000_000)) }
        func marker(_ name: String, fallback: ExcelCellAddress) -> (ExcelCellAddress, ExcelDrawingOffset) {
            guard let node = root.child(name) else { return (fallback, .zero) }
            return (.init(row: min(Int(number(node.child("row")?.text)) + 1, 1_048_576), column: min(Int(number(node.child("col")?.text)) + 1, 16_384)),
                    .init(x: number(node.child("colOff")?.text), y: number(node.child("rowOff")?.text)))
        }
        let (start, from) = marker("from", fallback: .init(row: 1, column: 1))
        let (end, to) = marker("to", fallback: .init(row: start.row + 5, column: start.column + 2))
        let pos = root.child("pos"), ext = root.child("ext")
        return .init(start: start, end: end, fromOffset: from, toOffset: to,
                     absolutePosition: pos.map { .init(x: number($0.attributes["x"]), y: number($0.attributes["y"])) },
                     extent: ext.map { .init(x: number($0.attributes["cx"]), y: number($0.attributes["cy"])) })
    }

    /// Replace only placement and nonvisual metadata. Keep crop, rotation, effects,
    /// chart relationships, clientData and sibling drawing order intact.
    static func updating(_ xml: String, relationshipID: String, anchor: ExcelDrawingAnchor, name: String, alternativeText: String?, isImage: Bool) throws -> String {
        let root = try ExcelEditingXML.parse(Data(xml.utf8))
        guard let node = root.children.first(where: { node in
            node.descendants(isImage ? "blip" : "chart").contains { child in
                child.attributes.contains { key, value in key.split(separator: ":").last == (isImage ? "embed" : "id") && value == relationshipID }
            }
        }) else { throw ExcelWorkbookDocumentError.cannotSave }
        let old = read(node)
        if old != anchor {
            let prefix = node.name.contains(":") ? String(node.name.prefix(through: node.name.firstIndex(of: ":")!)) : ""
            node.name = prefix + "twoCellAnchor"
            node.attributes["editAs"] = "oneCell"
            for name in ["from", "to", "pos", "ext"] { node.remove(name) }
            func marker(_ name: String, address: ExcelCellAddress, offset: ExcelDrawingOffset) -> ExcelEditingXML.Node {
                let child = node.make(name)
                for (key, value) in [("col", Int64(address.column - 1)), ("colOff", offset.x), ("row", Int64(address.row - 1)), ("rowOff", offset.y)] {
                    child.ensure(key).text = String(value)
                }
                return child
            }
            node.children.insert(contentsOf: [marker("from", address: anchor.start, offset: anchor.fromOffset), marker("to", address: anchor.end, offset: anchor.toOffset)], at: 0)
        }
        if let metadata = node.descendants("cNvPr").first {
            metadata.attributes["name"] = name
            if isImage { metadata.attributes["descr"] = alternativeText }
        }
        return String(decoding: ExcelEditingXML.data(root), as: UTF8.self)
    }
}

nonisolated struct ExcelDrawingTrack {
    let index: Int
    let origin: CGFloat
    let size: CGFloat
    let emuSize: Double
}

nonisolated struct ExcelDrawingGrid {
    let columns: [ExcelDrawingTrack]
    let rows: [ExcelDrawingTrack]
    let columnWidths: [Int: Double]
    let rowHeights: [Int: Double]

    var bounds: CGRect {
        guard let x = columns.first, let y = rows.first, let endX = columns.last, let endY = rows.last else { return .zero }
        return CGRect(x: x.origin, y: y.origin, width: endX.origin + endX.size - x.origin, height: endY.origin + endY.size - y.origin)
    }
    static func columnEMUs(_ width: Double) -> Double { max(1, width * 7 + 5) * 9_525 }
    static func rowEMUs(_ height: Double) -> Double { max(1, height) * 12_700 }

    private func rawPosition(index: Int, offset: Int64, column: Bool) -> Double {
        let limit = column ? 201 : 2001
        let sizes = column ? columnWidths : rowHeights
        return (1 ..< max(1, min(index, limit))).reduce(Double(offset)) { result, i in
            result + (column ? Self.columnEMUs(sizes[i] ?? 14) : Self.rowEMUs(sizes[i] ?? 30.35))
        }
    }
    private func rawMarker(_ position: Double, column: Bool) -> (Int, Int64) {
        let sizes = column ? columnWidths : rowHeights
        var rest = max(0, position)
        let maximum = column ? 200 : 2000
        for index in 1 ... maximum {
            let size = column ? Self.columnEMUs(sizes[index] ?? 14) : Self.rowEMUs(sizes[index] ?? 30.35)
            if rest < size { return (index, Int64(rest.rounded())) }
            rest -= size
        }
        return (maximum + 1, 0)
    }
    func normalized(_ anchor: ExcelDrawingAnchor) -> ExcelDrawingAnchor {
        guard let extent = anchor.extent else { return anchor }
        let x = anchor.absolutePosition.map { Double($0.x) } ?? rawPosition(index: anchor.start.column, offset: anchor.fromOffset.x, column: true)
        let y = anchor.absolutePosition.map { Double($0.y) } ?? rawPosition(index: anchor.start.row, offset: anchor.fromOffset.y, column: false)
        let left = rawMarker(x, column: true), top = rawMarker(y, column: false)
        let right = rawMarker(x + Double(extent.x), column: true), bottom = rawMarker(y + Double(extent.y), column: false)
        return .init(start: .init(row: top.0, column: left.0), end: .init(row: bottom.0, column: right.0), fromOffset: .init(x: left.1, y: top.1), toOffset: .init(x: right.1, y: bottom.1))
    }
    private func position(_ index: Int, offset: Int64, tracks: [ExcelDrawingTrack]) -> CGFloat {
        if let track = tracks.first(where: { $0.index == index }) {
            return track.origin + CGFloat(Double(offset) / track.emuSize) * track.size
        }
        if let track = tracks.first(where: { $0.index > index }) { return track.origin }
        return tracks.last.map { $0.origin + $0.size } ?? 0
    }
    func rect(for anchor: ExcelDrawingAnchor) -> CGRect? {
        let a = normalized(anchor)
        let x = position(a.start.column, offset: a.fromOffset.x, tracks: columns), y = position(a.start.row, offset: a.fromOffset.y, tracks: rows)
        let right = position(a.end.column, offset: a.toOffset.x, tracks: columns), bottom = position(a.end.row, offset: a.toOffset.y, tracks: rows)
        guard right > x, bottom > y else { return nil }
        return CGRect(x: x, y: y, width: right - x, height: bottom - y)
    }
    func anchor(for rect: CGRect) -> ExcelDrawingAnchor? {
        guard rect.width > 0, rect.height > 0, rect.minX.isFinite, rect.minY.isFinite, rect.maxX.isFinite, rect.maxY.isFinite else { return nil }
        func marker(_ point: CGFloat, tracks: [ExcelDrawingTrack]) -> (Int, Int64)? {
            guard let last = tracks.last else { return nil }
            if point >= last.origin + last.size - 0.001 { return (last.index + 1, 0) }
            guard let track = tracks.first(where: { point < $0.origin + $0.size }) else { return nil }
            return (track.index, Int64((Double(max(0, point - track.origin) / track.size) * track.emuSize).rounded()))
        }
        guard let x = marker(rect.minX, tracks: columns), let y = marker(rect.minY, tracks: rows), let right = marker(rect.maxX, tracks: columns), let bottom = marker(rect.maxY, tracks: rows) else { return nil }
        return .init(start: .init(row: y.0, column: x.0), end: .init(row: bottom.0, column: right.0), fromOffset: .init(x: x.1, y: y.1), toOffset: .init(x: right.1, y: bottom.1))
    }
    /// Partial objects spanning a paged-out region can be selected, but must be
    /// brought fully into one page before a drag can represent their whole size.
    func canManipulate(_ anchor: ExcelDrawingAnchor) -> Bool {
        guard let rect = rect(for: anchor), bounds.contains(rect) else { return false }
        let a = normalized(anchor)
        func complete(_ start: Int, _ end: Int, _ tracks: [ExcelDrawingTrack]) -> Bool {
            let required = start ... max(start, end - 1)
            return required.count <= tracks.count && required.allSatisfy { i in tracks.contains { $0.index == i } }
                && (tracks.contains { $0.index == end } || tracks.last?.index == end - 1)
        }
        return complete(a.start.column, a.end.column, columns) && complete(a.start.row, a.end.row, rows)
    }
}

nonisolated enum ExcelDrawingDragMode: CaseIterable {
    case move, topLeft, topRight, bottomLeft, bottomRight
    func corner(in rect: CGRect) -> CGPoint? {
        switch self {
        case .move: return nil
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
    static func hit(_ point: CGPoint, rect: CGRect, radius: CGFloat) -> ExcelDrawingDragMode? {
        for mode in allCases {
            if let corner = mode.corner(in: rect), hypot(point.x - corner.x, point.y - corner.y) <= radius { return mode }
        }
        return rect.contains(point) ? .move : nil
    }
    func applying(_ delta: CGPoint, to rect: CGRect, within bounds: CGRect) -> CGRect {
        if self == .move {
            return CGRect(x: min(max(rect.minX + delta.x, bounds.minX), max(bounds.minX, bounds.maxX - rect.width)),
                          y: min(max(rect.minY + delta.y, bounds.minY), max(bounds.minY, bounds.maxY - rect.height)), width: rect.width, height: rect.height)
        }
        let minWidth = min(32, rect.width), minHeight = min(32, rect.height)
        var left = rect.minX, right = rect.maxX, top = rect.minY, bottom = rect.maxY
        if self == .topLeft || self == .bottomLeft { left = min(max(left + delta.x, bounds.minX), right - minWidth) }
        else { right = max(min(right + delta.x, bounds.maxX), left + minWidth) }
        if self == .topLeft || self == .topRight { top = min(max(top + delta.y, bounds.minY), bottom - minHeight) }
        else { bottom = max(min(bottom + delta.y, bounds.maxY), top + minHeight) }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

nonisolated struct ExcelDrawingSelection: Identifiable, Equatable {
    let id: String
    let sheetPath: String
}
nonisolated struct ExcelDrawingHitRegion: Equatable {
    let id: String
    let rect: CGRect
    let bounds: CGRect
}
