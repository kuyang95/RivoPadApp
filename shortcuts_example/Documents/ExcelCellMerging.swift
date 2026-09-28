import Foundation
import CoreGraphics

nonisolated extension ExcelCellRange {
    func includingMergedCells(in sheet: ExcelWorksheet) -> ExcelCellRange {
        var result = self
        for _ in 0 ... sheet.mergedRanges.count {
            let previous = result
            for merged in sheet.mergedRanges where result.intersects(merged) {
                result = ExcelCellRange(
                    start: ExcelCellAddress(row: min(result.start.row, merged.start.row), column: min(result.start.column, merged.start.column)),
                    end: ExcelCellAddress(row: max(result.end.row, merged.end.row), column: max(result.end.column, merged.end.column))
                )
            }
            if result == previous { break }
        }
        return result
    }
}

/// The same plan drives the user-facing preview and the final package edit.
nonisolated struct ExcelCellMergePlan: Sendable {
    let range: ExcelCellRange
    let discardedAddresses: [ExcelCellAddress]

    init(range requested: ExcelCellRange, sheet: ExcelWorksheet) throws {
        let range = requested.includingMergedCells(in: sheet)
        guard !sheet.protection.isEnabled, !sheet.didTruncate, !sheet.isWindowed else {
            throw ExcelEditingError("보호된 시트나 대용량 시트에서는 이 편집을 사용할 수 없습니다.")
        }
        guard range.start.row > 0, range.start.column > 0, range.end.row <= 1_048_576,
              range.end.column <= 16_384, range.cellCount <= 20_000 else {
            throw ExcelEditingError("한 번에 편집할 범위는 20,000셀 이하로 선택해 주세요.")
        }
        guard range.cellCount > 1 else { throw ExcelEditingError("병합할 셀을 두 개 이상 선택해 주세요.") }
        guard range.end.row <= ExcelWorkbookDocument.maximumRowsPerSheet,
              range.end.column <= ExcelWorkbookDocument.maximumColumnsPerSheet else {
            throw ExcelEditingError("이 편집으로 일반 문서의 행·열 표시 한도를 넘습니다.")
        }
        guard !sheet.tables.contains(where: { range.intersects($0.range) }),
              !sheet.pivotTables.contains(where: { $0.destinationRange.map(range.intersects) == true }) else {
            throw ExcelEditingError("표나 피벗 요약표 안에서는 셀을 병합할 수 없습니다.")
        }
        guard !sheet.cells.values.contains(where: { cell in
            (cell.spillAnchor != nil && range.contains(cell.address))
                || cell.spillRange.map(range.intersects) == true
        }) else { throw ExcelEditingError("배열 수식이 포함된 범위는 병합할 수 없습니다.") }
        self.range = range
        discardedAddresses = sheet.cells.values.filter {
            range.contains($0.address) && $0.address != range.start
                && (!$0.rawValue.isEmpty || $0.formula?.isEmpty == false)
        }.map(\.address).sorted()
    }
}

/// A merged cell occupies one rectangle, including when its anchor is outside
/// the currently loaded grid window or when some rows are filtered out.
nonisolated enum ExcelMergedCellGeometry {
    static func rect(
        for range: ExcelCellRange,
        columns: ClosedRange<Int>,
        rows: [(number: Int, y: CGFloat, height: CGFloat)],
        rowHeaderWidth: CGFloat,
        columnWidth: (Int) -> CGFloat
    ) -> CGRect? {
        rect(for: range, columns: Array(columns), rows: rows, rowHeaderWidth: rowHeaderWidth, columnWidth: columnWidth)
    }

    static func rect(
        for range: ExcelCellRange,
        columns: [Int],
        rows: [(number: Int, y: CGFloat, height: CGFloat)],
        rowHeaderWidth: CGFloat,
        columnWidth: (Int) -> CGFloat
    ) -> CGRect? {
        let includedColumns = columns.filter { (range.start.column ... range.end.column).contains($0) }
        let includedRows = rows.filter { (range.start.row ... range.end.row).contains($0.number) }
        guard let firstColumn = includedColumns.first, let firstRow = includedRows.first, let lastRow = includedRows.last else { return nil }
        let x = rowHeaderWidth + columns.prefix { $0 < firstColumn }.reduce(CGFloat.zero) { $0 + columnWidth($1) }
        let width = includedColumns.reduce(CGFloat.zero) { $0 + columnWidth($1) }
        return CGRect(x: x, y: firstRow.y, width: width, height: lastRow.y + lastRow.height - firstRow.y)
    }
}
