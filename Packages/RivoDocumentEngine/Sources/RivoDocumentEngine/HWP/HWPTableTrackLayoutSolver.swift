import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public nonisolated struct HWPTableTrackLayout: Hashable, Sendable {
    public let columnWidths: [Double]
    public let rowHeights: [Double]

    public var size: CGSize {
        CGSize(
            width: columnWidths.reduce(0, +),
            height: rowHeights.reduce(0, +)
        )
    }

    public init(columnWidths: [Double], rowHeights: [Double]) {
        self.columnWidths = columnWidths
        self.rowHeights = rowHeights
    }
}

public nonisolated enum HWPTableTrackLayoutSolver {
    private struct Constraint {
        let start: Int
        let span: Int
        let length: Double
    }

    public static func make(
        blocks: [HWPDocumentBlock],
        maximumWidth: Double? = nil
    ) -> HWPTableTrackLayout {
        var cells: [String: [HWPDocumentBlock]] = [:]
        for block in blocks {
            guard let location = block.tableLocation else { continue }
            let key = "\(location.row)-\(location.column)"
            cells[key, default: []].append(block)
        }
        let locations = cells.values.compactMap { $0.first?.tableLocation }
        let columnCount = locations.map { $0.column + $0.columnSpan }.max() ?? 1
        let rowCount = locations.map { $0.row + $0.rowSpan }.max() ?? 1
        let widthConstraints = locations.compactMap { location in
            location.cellWidthPoints.map {
                Constraint(start: location.column, span: location.columnSpan, length: $0)
            }
        }
        let heightConstraints = cells.values.compactMap { cellBlocks -> Constraint? in
            guard let location = cellBlocks.first?.tableLocation else { return nil }
            let contentBottom = cellBlocks.flatMap(\.lineLayouts).map { line in
                line.verticalPositionPoints
                    + max(
                        line.lineHeightPoints,
                        line.textHeightPoints,
                        line.text.isEmpty ? 0 : line.textRuns.compactMap(\.fontSizePoints).max() ?? 0
                    )
            }.max() ?? (cellBlocks.contains { !$0.text.isEmpty } ? 16 : 0)
            // HWP stores the declared cell height as a minimum. Long form
            // cells frequently keep a tiny minimum (for example 2.82pt) and
            // rely on cached line positions to grow the row at layout time.
            return Constraint(
                start: location.row,
                span: location.rowSpan,
                length: max(
                    location.cellHeightPoints ?? 0,
                    contentBottom
                        + location.cellMarginTopPoints
                        + location.cellMarginBottomPoints
                )
            )
        }
        var columnWidths = solveDeclared(count: columnCount, constraints: widthConstraints) ?? solve(
                count: columnCount,
                constraints: widthConstraints,
                defaultLength: 80
            )
        var rowHeights = solveMinimum(
            count: rowCount,
            constraints: heightConstraints,
            defaultLength: 36
        )
        let isPageFragment = blocks.contains {
            $0.id.contains("-page-fragment-")
                || $0.id.contains("-table-page-fragment-")
        }
        // Hancom writes the laid-out cell sizes back into the cell records,
        // so when the declared row heights add up to the table's own height
        // they are authoritative. Trailing empty paragraphs can carry cached
        // line positions past the declared height (envelope forms do this);
        // Hancom clips them instead of growing the row, so do the same.
        if !isPageFragment,
           let placement = blocks.first?.tableLocation?.tablePlacement {
            let declaredConstraints = locations.compactMap { location in
                location.cellHeightPoints.map {
                    Constraint(start: location.row, span: location.rowSpan, length: $0)
                }
            }
            if declaredConstraints.count == locations.count {
                let declaredHeights = solveDeclared(count: rowCount, constraints: declaredConstraints) ?? solveMinimum(
                    count: rowCount,
                    constraints: declaredConstraints,
                    defaultLength: 36
                )
                if abs(declaredHeights.reduce(0, +) - placement.heightPoints) <= 2 {
                    rowHeights = declaredHeights
                }
            }
        }
        if !isPageFragment,
           let placement = blocks.first?.tableLocation?.tablePlacement {
            columnWidths = expandedTracks(
                columnWidths,
                minimumTotal: placement.widthPoints
            )
            rowHeights = expandedTracks(
                rowHeights,
                minimumTotal: placement.heightPoints
            )
        }
        if let maximumWidth,
           maximumWidth > 0,
           columnWidths.reduce(0, +) > maximumWidth {
            let scale = maximumWidth / columnWidths.reduce(0, +)
            columnWidths = columnWidths.map { $0 * scale }
        }
        return HWPTableTrackLayout(
            columnWidths: columnWidths,
            rowHeights: rowHeights
        )
    }

    private static func expandedTracks(
        _ tracks: [Double],
        minimumTotal: Double
    ) -> [Double] {
        let current = tracks.reduce(0, +)
        guard current > 0,
              minimumTotal > current,
              minimumTotal <= current * 1.5 else {
            return tracks
        }
        let scale = minimumTotal / current
        return tracks.map { $0 * scale }
    }

    // A merged cell constrains the difference between two grid boundaries.
    // Solve those differences before assigning defaults to hidden tracks;
    // inventing an 80pt track inside a merge changes every visible column.
    private static func solveDeclared(count: Int, constraints: [Constraint]) -> [Double]? {
        guard count > 0 else { return nil }
        var edges = [[(Int, Double)]](repeating: [], count: count + 1)
        for c in constraints where c.start >= 0 && c.span > 0 && c.start + c.span <= count {
            edges[c.start].append((c.start + c.span, c.length))
            edges[c.start + c.span].append((c.start, -c.length))
        }
        var positions = [Double?](repeating: nil, count: count + 1)
        positions[0] = 0
        var queue = [0], cursor = 0
        while cursor < queue.count {
            let index = queue[cursor]
            cursor += 1
            for (next, distance) in edges[index] where positions[next] == nil {
                positions[next] = positions[index]! + distance
                queue.append(next)
            }
        }
        guard positions.allSatisfy({ $0 != nil }) else { return nil }
        let values = positions.map { $0! }
        guard constraints.allSatisfy({ c in
            c.start >= 0 && c.start + c.span <= count
                && abs(values[c.start + c.span] - values[c.start] - c.length) < 1
        }) else { return nil }
        let tracks = (0..<count).map { values[$0 + 1] - values[$0] }
        return tracks.allSatisfy { $0 > 0 } ? tracks : nil
    }

    private static func solveMinimum(count: Int, constraints: [Constraint], defaultLength: Double) -> [Double] {
        guard count > 0 else { return [defaultLength] }
        var boundaries = [Double](repeating: 0, count: count + 1)
        let ending = Dictionary(grouping: constraints.filter {
            $0.start >= 0 && $0.span > 0 && $0.start + $0.span <= count
        }, by: { $0.start + $0.span })
        for end in 1...count {
            boundaries[end] = boundaries[end - 1]
            for constraint in ending[end] ?? [] {
                boundaries[end] = max(boundaries[end], boundaries[constraint.start] + constraint.length)
            }
        }
        return (0..<count).map { max(0, boundaries[$0 + 1] - boundaries[$0]) }
    }

    private static func solve(
        count: Int,
        constraints: [Constraint],
        defaultLength: Double
    ) -> [Double] {
        guard count > 0 else { return [defaultLength] }
        var tracks = [Double](repeating: 0, count: count)
        let ordered = constraints.sorted {
            if $0.span == $1.span { return $0.start < $1.start }
            return $0.span < $1.span
        }
        for constraint in ordered where constraint.span == 1 {
            guard tracks.indices.contains(constraint.start) else { continue }
            tracks[constraint.start] = max(
                tracks[constraint.start],
                constraint.length
            )
        }
        tracks = tracks.map { $0 > 0 ? $0 : defaultLength }
        for constraint in ordered where constraint.span > 1 {
            let end = min(count, constraint.start + constraint.span)
            guard constraint.start >= 0, constraint.start < end else { continue }
            let current = tracks[constraint.start..<end].reduce(0, +)
            let deficit = constraint.length - current
            guard deficit > 0 else { continue }
            let addition = deficit / Double(end - constraint.start)
            for index in constraint.start..<end {
                tracks[index] += addition
            }
        }
        return tracks
    }
}
