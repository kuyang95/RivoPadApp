import Foundation

/// Cell operations share the checked grid and lossless paragraph mapping used by
/// row/column edits. A split introduces a grid boundary, not an extra table width.
nonisolated enum HWPTableCellEditing {
    typealias Cell = HWPTableStructureEditing.Cell
    typealias Plan = HWPTableStructureEditing.Plan
    typealias Address = HWPTableStructureEditing.Address

    static func plan(_ action: HWPTableStructureAction, section: String, location: HWPDocumentTableLocation,
                     originalRange: Range<Int>, originals: [Cell], rows oldRows: [Double],
                     columns oldColumns: [Double], blockCount: Int) throws -> Plan {
        let oldRows = resolvedHiddenTracks(oldRows, cells: originals, rows: true)
        let oldColumns = resolvedHiddenTracks(oldColumns, cells: originals, rows: false)
        guard let selected = originals.first(where: { $0.row == location.row && $0.column == location.column }),
              oldRows.allSatisfy({ $0.isFinite && $0 > 0 }), oldColumns.allSatisfy({ $0.isFinite && $0 >= 0.1 }) else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        var cells = originals, rows = oldRows, columns = oldColumns
        var insertedBoundary: Int?
        switch action {
        case .mergeRight, .mergeBelow:
            let alongRows = action == .mergeBelow
            let edge = alongRows ? selected.row + selected.rowSpan : selected.column + selected.columnSpan
            let start = alongRows ? selected.column : selected.row
            let end = start + (alongRows ? selected.columnSpan : selected.rowSpan)
            let neighbors = originals.filter { cell in
                let a = alongRows ? cell.column : cell.row
                let b = a + (alongRows ? cell.columnSpan : cell.rowSpan)
                return (alongRows ? cell.row : cell.column) == edge && a < end && b > start
            }
            guard !neighbors.isEmpty else { throw HWPDocumentEditingError.unsupportedEdit }
            let farEdges = Set(neighbors.map { alongRows ? $0.row + $0.rowSpan : $0.column + $0.columnSpan })
            guard farEdges.count == 1, let far = farEdges.first,
                  neighbors.allSatisfy({ cell in
                      let a = alongRows ? cell.column : cell.row
                      let b = a + (alongRows ? cell.columnSpan : cell.rowSpan)
                      return a >= start && b <= end
                  }), neighbors.reduce(0, { $0 + (alongRows ? $1.columnSpan : $1.rowSpan) }) == end - start else {
                // A partial overlap would create an L-shaped cell or consume
                // content outside the selected edge. Keep that command disabled.
                throw HWPDocumentEditingError.unsupportedEdit
            }
            let members = ([selected] + neighbors).sorted { ($0.row, $0.column) < ($1.row, $1.column) }
            let addresses = Set(members.map(\.source))
            var merged = selected
            merged.paragraphs = members.flatMap(\.paragraphs)
            if alongRows { merged.rowSpan = far - merged.row } else { merged.columnSpan = far - merged.column }
            cells.removeAll { addresses.contains($0.source) }; cells.append(merged)
        case .splitColumns, .splitRows:
            let alongRows = action == .splitRows
            let tracks = alongRows ? rows : columns
            let start = alongRows ? selected.row : selected.column
            let end = start + (alongRows ? selected.rowSpan : selected.columnSpan)
            var edges: [Double] = [0]
            for size in tracks { edges.append(edges.last! + size) }
            let middle = ((edges[start] + edges[end]) * 50).rounded() / 100
            guard middle - edges[start] >= 0.1, edges[end] - middle >= 0.1 else { throw HWPDocumentEditingError.limitExceeded }
            let boundary: Int
            if let existing = (start + 1..<end).first(where: { abs(edges[$0] - middle) < 0.005 }) {
                boundary = existing
            } else {
                guard let track = (start..<end).first(where: { edges[$0] < middle && edges[$0 + 1] > middle }) else {
                    throw HWPDocumentEditingError.unsupportedEdit
                }
                boundary = track + 1; insertedBoundary = boundary
                var revised = tracks
                revised.replaceSubrange(track...track, with: [middle - edges[track], edges[track + 1] - middle])
                if alongRows { rows = revised } else { columns = revised }
                cells = cells.map { cell in
                    var result = cell
                    let a = alongRows ? cell.row : cell.column
                    let b = a + (alongRows ? cell.rowSpan : cell.columnSpan)
                    let first = a >= boundary ? a + 1 : a
                    let last = b >= boundary ? b + 1 : b
                    if alongRows { result.row = first; result.rowSpan = last - first }
                    else { result.column = first; result.columnSpan = last - first }
                    return result
                }
            }
            guard let index = cells.firstIndex(where: { $0.source == selected.source }) else { throw HWPDocumentEditingError.staleDocument }
            var first = cells.remove(at: index), second = first
            second.paragraphs = [selected.paragraphs[0]]; second.isNew = true
            if alongRows {
                first.rowSpan = boundary - first.row
                second.row = boundary; second.rowSpan -= first.rowSpan
            } else {
                first.columnSpan = boundary - first.column
                second.column = boundary; second.columnSpan -= first.columnSpan
            }
            cells += [first, second]
        case .unmerge:
            guard selected.rowSpan > 1 || selected.columnSpan > 1 else { throw HWPDocumentEditingError.unsupportedEdit }
            cells.removeAll { $0.source == selected.source }
            for row in selected.row..<(selected.row + selected.rowSpan) {
                for column in selected.column..<(selected.column + selected.columnSpan) {
                    let isNew = row != selected.row || column != selected.column
                    cells.append(Cell(source: selected.source, paragraphs: isNew ? [selected.paragraphs[0]] : selected.paragraphs,
                        row: row, column: column, rowSpan: 1, columnSpan: 1, isNew: isNew))
                }
            }
        default: throw HWPDocumentEditingError.unsupportedEdit
        }
        cells.sort { ($0.row, $0.column) < ($1.row, $1.column) }
        guard rows.count <= 512, columns.count <= 512, rows.count * columns.count <= 20_000,
              rows.reduce(0, +) <= 4_000, columns.allSatisfy({ $0 >= 0.1 }),
              blockCount - originalRange.count + cells.reduce(0, { $0 + ($1.isNew ? 1 : $1.paragraphs.count) }) <= 20_000 else {
            throw HWPDocumentEditingError.limitExceeded
        }
        return Plan(section: section, table: location.table, action: action, position: 0,
            originalRange: originalRange, originalCells: originals, cells: cells,
            oldRows: oldRows, oldColumns: oldColumns, rows: rows, columns: columns,
            focus: selected.source, insertedBoundary: insertedBoundary)
    }

    /// Once every cell across a grid boundary is merged, the file contains no
    /// size for that hidden track. Divide its enclosing extent evenly while
    /// keeping every boundary that still has a visible cell edge fixed.
    static func resolvedHiddenTracks(_ tracks: [Double], cells: [Cell], rows: Bool) -> [Double] {
        let edges = Set(cells.flatMap { cell in
            rows ? [cell.row, cell.row + cell.rowSpan] : [cell.column, cell.column + cell.columnSpan]
        }).sorted()
        var result = tracks
        for (start, end) in zip(edges, edges.dropFirst()) where end - start > 1 {
            let total = tracks[start..<end].reduce(0, +)
            let unit = (total / Double(end - start) * 100).rounded() / 100
            for index in start..<end { result[index] = index == end - 1 ? total - unit * Double(end - start - 1) : unit }
        }
        return result
    }
}
