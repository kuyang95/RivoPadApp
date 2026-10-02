import Foundation

public nonisolated struct HWPTableDimensions: Sendable, Equatable {
    public var widthPoints: Double? = nil
    public var heightPoints: Double? = nil

    public init(widthPoints: Double? = nil, heightPoints: Double? = nil) {
        self.widthPoints = widthPoints
        self.heightPoints = heightPoints
    }
}

public nonisolated enum HWPTableSizing {
    public typealias Plan = HWPTableStructureEditing.Plan
    public typealias Cell = HWPTableStructureEditing.Cell
    public static let pointsPerMM = 72.0 / 25.4

    public struct Selection: Identifiable, Sendable {
        public let id: String
        public let row: Int, column: Int, rowSpan: Int, columnSpan: Int
        public let width: Double, height: Double
        public let maximumWidth: Double, maximumHeight: Double
    
    public init(id: String, row: Int, column: Int, rowSpan: Int, columnSpan: Int, width: Double, height: Double, maximumWidth: Double, maximumHeight: Double) {
        self.id = id
        self.row = row
        self.column = column
        self.rowSpan = rowSpan
        self.columnSpan = columnSpan
        self.width = width
        self.height = height
        self.maximumWidth = maximumWidth
        self.maximumHeight = maximumHeight
    }
}

    public static func selection(blocks: [HWPDocumentBlock], selectedID: String?, layouts: [HWPDocumentPageLayout]) -> Selection? {
        guard let selectedID, let selected = blocks.first(where: { $0.id == selectedID }), let location = selected.tableLocation,
              let plan = try? HWPTableStructureEditing.plan(.resize, blocks: blocks, selectedID: selectedID, layouts: layouts),
              let cell = plan.cells.first(where: { $0.row == location.row && $0.column == location.column }),
              let layout = layouts.first(where: { $0.sectionIndex == sectionIndex(plan.section) }) else { return nil }
        let width = plan.width(cell), height = plan.height(cell)
        let containerWidth = nestedContainerWidth(location, blocks: blocks)
        return Selection(id: selectedID, row: cell.row, column: cell.column, rowSpan: cell.rowSpan, columnSpan: cell.columnSpan,
            width: width, height: height,
            maximumWidth: maximumTableWidth(location, layout: layout, current: plan.width,
                containerWidth: containerWidth) - (plan.width - width),
            maximumHeight: 4_000 - (plan.height - height))
    }

    public static func plan(_ dimensions: HWPTableDimensions?, section: String, location: HWPDocumentTableLocation,
                     originalRange: Range<Int>, originals: [Cell], rows: [Double], columns: [Double],
                     layout: HWPDocumentPageLayout, containerWidth: Double? = nil) throws -> Plan {
        let oldRows = HWPTableCellEditing.resolvedHiddenTracks(rows, cells: originals, rows: true)
        let oldColumns = HWPTableCellEditing.resolvedHiddenTracks(columns, cells: originals, rows: false)
        let rowRange = location.row..<(location.row + location.rowSpan)
        let columnRange = location.column..<(location.column + location.columnSpan)
        guard oldRows.allSatisfy({ $0.isFinite && $0 > 0 }), oldColumns.allSatisfy({ $0.isFinite && $0 >= 0.1 }),
              oldRows.count >= rowRange.upperBound, oldColumns.count >= columnRange.upperBound else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        var rows = oldRows, columns = oldColumns
        let maximum = maximumTableWidth(location, layout: layout, current: columns.reduce(0, +),
            containerWidth: containerWidth)
        if let width = dimensions?.widthPoints {
            let available = maximum - (columns.reduce(0, +) - columns[columnRange].reduce(0, +))
            columns = try resized(columns, range: columnRange, target: width, maximum: available)
        }
        if let height = dimensions?.heightPoints {
            let available = 4_000 - (rows.reduce(0, +) - rows[rowRange].reduce(0, +))
            rows = try resized(rows, range: rowRange, target: height, maximum: available)
        }
        guard rows.reduce(0, +) <= 4_000.01, columns.reduce(0, +) <= 4_000.01 else { throw HWPDocumentEditingError.limitExceeded }
        return Plan(section: section, table: location.table, action: .resize, position: 0,
            originalRange: originalRange, originalCells: originals, cells: originals,
            oldRows: oldRows, oldColumns: oldColumns, rows: rows, columns: columns,
            focus: .init(row: location.row, column: location.column))
    }

    private static func resized(_ source: [Double], range: Range<Int>, target: Double, maximum: Double) throws -> [Double] {
        guard target.isFinite, target >= pointsPerMM, target <= maximum + 0.005 else { throw HWPDocumentEditingError.limitExceeded }
        let total = source[range].reduce(0, +), requested = (target * 100).rounded() / 100
        guard total > 0 else { throw HWPDocumentEditingError.unsupportedEdit }
        var result = source, used = 0.0
        for index in range {
            let size = index == range.upperBound - 1 ? requested - used : (source[index] / total * requested * 100).rounded() / 100
            guard size >= 0.1 else { throw HWPDocumentEditingError.limitExceeded }
            result[index] = size; used += size
        }
        return result
    }

    public static func nestedContainerWidth(_ location: HWPDocumentTableLocation,
                                     blocks: [HWPDocumentBlock]) -> Double? {
        guard let parent = location.parent,
              let owner = blocks.first(where: {
                  $0.tableLocation?.table == parent.table
                      && $0.tableLocation?.row == parent.row
                      && $0.tableLocation?.column == parent.column
              }), let cell = owner.tableLocation, let width = cell.cellWidthPoints else { return nil }
        return max(pointsPerMM, width - cell.cellMarginLeftPoints - cell.cellMarginRightPoints)
    }

    private static func maximumTableWidth(_ location: HWPDocumentTableLocation, layout: HWPDocumentPageLayout,
                                          current: Double, containerWidth: Double? = nil) -> Double {
        let placement = location.tablePlacement
        let body = layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints
        let offset = abs(placement?.xPoints ?? 0) * (placement?.horizontalAlignment == .center ? 2 : 1)
        let occupied = offset + max(0, location.tableAnchor?.columnStartPoints ?? 0)
            + max(0, placement?.marginLeftPoints ?? 0) + max(0, placement?.marginRightPoints ?? 0)
        // Oversized imported tables may be reduced without first forcing them
        // to fit the page, but resizing never expands them farther off-page.
        let pageMaximum = body - occupied
        let available = containerWidth.map { min(pageMaximum, $0) } ?? pageMaximum
        return min(4_000, max(current, available))
    }

    private static func sectionIndex(_ path: String) -> Int {
        Int(path.lowercased().components(separatedBy: "section").last?.replacingOccurrences(of: ".xml", with: "") ?? "0") ?? 0
    }
}
