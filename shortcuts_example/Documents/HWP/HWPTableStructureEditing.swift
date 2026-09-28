import Foundation

nonisolated enum HWPTableStructureAction: String, CaseIterable, Sendable {
    case rowAbove, rowBelow, columnBefore, columnAfter, deleteRow, deleteColumn
    case mergeRight, mergeBelow, splitColumns, splitRows, unmerge
    case resize, deleteTable
    static var trackActions: [Self] { [.rowAbove, .rowBelow, .columnBefore, .columnAfter, .deleteRow, .deleteColumn] }
    static var cellActions: [Self] { allCases.filter(\.isCellAction) }
    var isCellAction: Bool { [.mergeRight, .mergeBelow, .splitColumns, .splitRows, .unmerge].contains(self) }
    var isRow: Bool { [.rowAbove, .rowBelow, .deleteRow, .mergeBelow, .splitRows].contains(self) }
    var isDeletion: Bool { self == .deleteRow || self == .deleteColumn || self == .deleteTable }
    var title: String {
        switch self {
        case .rowAbove: "위에 행 추가"
        case .rowBelow: "아래에 행 추가"
        case .columnBefore: "왼쪽에 열 추가"
        case .columnAfter: "오른쪽에 열 추가"
        case .deleteRow: "행 삭제"
        case .deleteColumn: "열 삭제"
        case .mergeRight: "오른쪽 셀과 병합"
        case .mergeBelow: "아래 셀과 병합"
        case .splitColumns: "좌우로 둘로 나누기"
        case .splitRows: "상하로 둘로 나누기"
        case .unmerge: "병합 풀기"
        case .resize: "행·열 크기"
        case .deleteTable: "표 삭제"
        }
    }
}

/// A checked rectangular grid. Existing cells keep their content, including
/// merged cells crossing the inserted/deleted track; new cells inherit style only.
nonisolated enum HWPTableStructureEditing {
    struct Address: Hashable, Sendable { let row: Int; let column: Int }
    struct Cell: Sendable {
        let source: Address
        var paragraphs: [Int]
        var row: Int, column: Int, rowSpan: Int, columnSpan: Int
        var isNew = false
    }
    struct Plan: Sendable {
        let section: String, table: Int
        let action: HWPTableStructureAction, position: Int
        let originalRange: Range<Int>
        let originalCells: [Cell]
        let cells: [Cell]
        let oldRows: [Double], oldColumns: [Double]
        let rows: [Double], columns: [Double]
        let focus: Address
        var insertedBoundary: Int? = nil

        var width: Double { columns.reduce(0, +) }
        var height: Double { rows.reduce(0, +) }
        func width(_ cell: Cell) -> Double { columns[cell.column..<(cell.column + cell.columnSpan)].reduce(0, +) }
        func height(_ cell: Cell) -> Double { rows[cell.row..<(cell.row + cell.rowSpan)].reduce(0, +) }
        var sourceIndices: [Int?] {
            cells.flatMap { $0.isNew ? [nil] : $0.paragraphs.map(Optional.some) }
        }
        func interval(_ start: Int, _ count: Int) -> (start: Int, count: Int)? {
            if action == .resize { return (start, count) }
            if action.isCellAction {
                guard let boundary = insertedBoundary else { return (start, count) }
                let first = start >= boundary ? start + 1 : start
                let end = start + count >= boundary ? start + count + 1 : start + count
                return (first, end - first)
            }
            return HWPTableStructureEditing.interval(start, count, at: position, deleting: action.isDeletion)
        }
    }

    static func available(blocks: [HWPDocumentBlock], selectedID: String?, layouts: [HWPDocumentPageLayout]) -> [HWPTableStructureAction] {
        guard let selectedID else { return [] }
        var actions = HWPTableStructureAction.trackActions.filter { (try? plan($0, blocks: blocks, selectedID: selectedID, layouts: layouts)) != nil }
        if (try? HWPTableDeletion.plan(blocks: blocks, selectedID: selectedID, layouts: layouts)) != nil { actions.append(.deleteTable) }
        return actions
    }

    static func availableCells(blocks: [HWPDocumentBlock], selectedID: String?, layouts: [HWPDocumentPageLayout]) -> [HWPTableStructureAction] {
        guard let selectedID else { return [] }
        return HWPTableStructureAction.cellActions.filter { (try? plan($0, blocks: blocks, selectedID: selectedID, layouts: layouts)) != nil }
    }

    static func plan(_ action: HWPTableStructureAction, blocks: [HWPDocumentBlock], selectedID: String,
                     layouts: [HWPDocumentPageLayout], dimensions: HWPTableDimensions? = nil) throws -> Plan {
        guard let selected = blocks.first(where: { $0.id == selectedID }), let location = selected.tableLocation,
              selected.region.kind == .body,
              let sectionIndex = Int(selected.sectionPath.lowercased().components(separatedBy: "section").last?.replacingOccurrences(of: ".xml", with: "") ?? ""),
              let layout = layouts.first(where: { $0.sectionIndex == sectionIndex }), layout.columnLayout.columns.count <= 1 else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        let indices = blocks.indices.filter { blocks[$0].sectionPath == selected.sectionPath && blocks[$0].tableLocation?.table == location.table }
        guard let first = indices.first, let last = indices.last, indices == Array(first...last),
              !blocks.contains(where: { $0.sectionPath == selected.sectionPath && $0.tableLocation?.parent?.table == location.table }),
              indices.allSatisfy({ index in
                  let block = blocks[index]
                  return block.isEditable && block.region.kind == .body && block.layoutContainerID == nil
                      && block.images.isEmpty && block.canvasObjects.isEmpty
                      && block.tableLocation?.parent == location.parent
                      && (block.presentation.list?.isSimple ?? !block.lineLayouts.contains(where: { $0.listMarker != nil }))
              }) else { throw HWPDocumentEditingError.unsupportedEdit }
        let grouped = Dictionary(grouping: indices) { Address(row: blocks[$0].tableLocation!.row, column: blocks[$0].tableLocation!.column) }
        let originals = grouped.map { address, members in
            let cell = blocks[members[0]].tableLocation!
            return Cell(source: address, paragraphs: members, row: cell.row, column: cell.column,
                        rowSpan: cell.rowSpan, columnSpan: cell.columnSpan)
        }.sorted { ($0.row, $0.column) < ($1.row, $1.column) }
        guard originals.allSatisfy({ $0.row >= 0 && $0.column >= 0 && $0.rowSpan > 0 && $0.columnSpan > 0 && $0.rowSpan <= 512 && $0.columnSpan <= 512
            && $0.row <= 512 - $0.rowSpan && $0.column <= 512 - $0.columnSpan }) else {
            throw HWPDocumentEditingError.limitExceeded
        }
        let rowCount = originals.map { $0.row + $0.rowSpan }.max() ?? 0
        let columnCount = originals.map { $0.column + $0.columnSpan }.max() ?? 0
        guard rowCount > 0, columnCount > 0, rowCount <= 512, columnCount <= 512,
              rowCount * columnCount <= 20_000 else { throw HWPDocumentEditingError.limitExceeded }
        var grid: [Address: Cell] = [:]
        for cell in originals {
            for row in cell.row..<(cell.row + cell.rowSpan) {
                for col in cell.column..<(cell.column + cell.columnSpan) {
                    guard grid.updateValue(cell, forKey: Address(row: row, column: col)) == nil else { throw HWPDocumentEditingError.unsupportedEdit }
                }
            }
        }
        guard grid.count == rowCount * columnCount else { throw HWPDocumentEditingError.unsupportedEdit }
        let tracks = HWPTableTrackLayoutSolver.make(blocks: indices.map { blocks[$0] })
        if action == .resize {
            return try HWPTableSizing.plan(dimensions, section: selected.sectionPath, location: location,
                originalRange: first..<(last + 1), originals: originals, rows: tracks.rowHeights,
                columns: tracks.columnWidths, layout: layout,
                containerWidth: HWPTableSizing.nestedContainerWidth(location, blocks: blocks))
        }
        if action.isCellAction {
            return try HWPTableCellEditing.plan(action, section: selected.sectionPath, location: location,
                originalRange: first..<(last + 1), originals: originals,
                rows: tracks.rowHeights, columns: tracks.columnWidths, blockCount: blocks.count)
        }
        var rows = tracks.rowHeights, columns = tracks.columnWidths
        let position: Int
        switch action {
        case .rowAbove, .deleteRow: position = location.row
        case .rowBelow: position = location.row + location.rowSpan
        case .columnBefore, .deleteColumn: position = location.column
        case .columnAfter: position = location.column + location.columnSpan
        case .mergeRight, .mergeBelow, .splitColumns, .splitRows, .unmerge, .resize, .deleteTable:
            throw HWPDocumentEditingError.unsupportedEdit
        }
        if action.isDeletion {
            guard (action.isRow ? rows.count : columns.count) > 1 else { throw HWPDocumentEditingError.unsupportedEdit }
            if action.isRow { rows.remove(at: position) } else { columns.remove(at: position) }
        } else {
            if action.isRow { rows.insert(max(24, rows[location.row]), at: position) }
            else { columns.insert(columns[location.column], at: position) }
        }
        // Keep the table on the page when its column count changes.
        if !action.isRow {
            let factor = tracks.columnWidths.reduce(0, +) / columns.reduce(0, +)
            columns = columns.map { ($0 * factor * 100).rounded() / 100 }
        }
        guard rows.count <= 512, columns.count <= 512, rows.count * columns.count <= 20_000,
              rows.reduce(0, +) <= 4_000, columns.allSatisfy({ $0.isFinite && $0 >= 0.1 }) else { throw HWPDocumentEditingError.limitExceeded }
        var cells = originals.compactMap { cell -> Cell? in
            guard let value = interval(action.isRow ? cell.row : cell.column,
                action.isRow ? cell.rowSpan : cell.columnSpan, at: position, deleting: action.isDeletion) else { return nil }
            var result = cell
            if action.isRow { result.row = value.start; result.rowSpan = value.count }
            else { result.column = value.start; result.columnSpan = value.count }
            return result
        }
        if !action.isDeletion {
            let count = action.isRow ? columns.count : rows.count
            var covered: Set<Int> = []
            for cell in cells where (action.isRow ? cell.row..<(cell.row + cell.rowSpan) : cell.column..<(cell.column + cell.columnSpan)).contains(position) {
                covered.formUnion(action.isRow ? cell.column..<(cell.column + cell.columnSpan) : cell.row..<(cell.row + cell.rowSpan))
            }
            var cursor = 0
            while cursor < count {
                if covered.contains(cursor) { cursor += 1; continue }
                let address = Address(row: action.isRow ? location.row : cursor, column: action.isRow ? cursor : location.column)
                guard let template = grid[address] else { throw HWPDocumentEditingError.unsupportedEdit }
                var end = cursor + 1
                let bound = action.isRow ? template.column + template.columnSpan : template.row + template.rowSpan
                while end < bound && !covered.contains(end) { end += 1 }
                cells.append(Cell(source: template.source, paragraphs: [template.paragraphs[0]],
                    row: action.isRow ? position : cursor, column: action.isRow ? cursor : position,
                    rowSpan: action.isRow ? 1 : end - cursor, columnSpan: action.isRow ? end - cursor : 1, isNew: true))
                cursor = end
            }
        }
        cells.sort { ($0.row, $0.column) < ($1.row, $1.column) }
        guard blocks.count - indices.count + cells.reduce(0, { $0 + ($1.isNew ? 1 : $1.paragraphs.count) }) <= 20_000 else {
            throw HWPDocumentEditingError.limitExceeded
        }
        let desired = Address(row: min(action.isRow ? position : location.row, rows.count - 1),
                              column: min(action.isRow ? location.column : position, columns.count - 1))
        let focus = cells.first { ($0.row..<$0.row + $0.rowSpan).contains(desired.row) && ($0.column..<$0.column + $0.columnSpan).contains(desired.column) }!
        return Plan(section: selected.sectionPath, table: location.table, action: action, position: position,
            originalRange: first..<(last + 1), originalCells: originals, cells: cells,
            oldRows: tracks.rowHeights, oldColumns: tracks.columnWidths, rows: rows, columns: columns,
            focus: Address(row: focus.row, column: focus.column))
    }

    static func interval(_ start: Int, _ count: Int, at position: Int, deleting: Bool) -> (start: Int, count: Int)? {
        if deleting {
            if start > position { return (start - 1, count) }
            if start + count > position { return count > 1 ? (start, count - 1) : nil }
        } else {
            if start >= position { return (start + 1, count) }
            if start + count > position { return (start, count + 1) }
        }
        return (start, count)
    }
}
