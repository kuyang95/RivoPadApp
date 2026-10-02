import Foundation

public nonisolated struct ExcelAccessibleColumn:
    Identifiable,
    Hashable,
    Sendable
{
    public var id: Int { column }

    public let column: Int
    public let title: String

    public init(column: Int, title: String) {
        self.column = column
        self.title = title
    }
}

public nonisolated struct ExcelAccessibleRegion:
    Identifiable,
    Hashable,
    Sendable
{
    public let id: String
    public let name: String
    public let range: ExcelCellRange
    public let headerRow: Int?
    public let columns: [ExcelAccessibleColumn]
    public let rowNumbers: [Int]
    public let isNativeTable: Bool

    public func contains(_ address: ExcelCellAddress) -> Bool {
        range.contains(address)
    }

    public init(id: String, name: String, range: ExcelCellRange, headerRow: Int? = nil, columns: [ExcelAccessibleColumn], rowNumbers: [Int], isNativeTable: Bool) {
        self.id = id
        self.name = name
        self.range = range
        self.headerRow = headerRow
        self.columns = columns
        self.rowNumbers = rowNumbers
        self.isNativeTable = isNativeTable
    }
}

public nonisolated enum ExcelAccessibilityAnalyzer {
    public static func regions(
        in sheet: ExcelWorksheet
    ) -> [ExcelAccessibleRegion] {
        let nativeRegions = sheet.tables
            .sorted {
                if $0.range.start.row != $1.range.start.row {
                    return $0.range.start.row < $1.range.start.row
                }
                return $0.range.start.column < $1.range.start.column
            }
            .map { table in
                region(for: table, in: sheet)
            }
        if nativeRegions.isEmpty {
            return supplementalRegions(
                in: sheet,
                excluding: []
            )
        }
        return nativeRegions + supplementalRegions(
            in: sheet,
            excluding: sheet.tables.map(\.range)
        )
    }

    public static func region(
        containing address: ExcelCellAddress?,
        in sheet: ExcelWorksheet
    ) -> ExcelAccessibleRegion? {
        let regions = regions(in: sheet)
        guard let address else {
            return regions.first
        }
        return regions.first(where: { $0.contains(address) })
            ?? regions.first
    }

    private static func region(
        for table: ExcelTable,
        in sheet: ExcelWorksheet
    ) -> ExcelAccessibleRegion {
        let headerRow = table.range.start.row
        let columns = (table.range.start.column ... table.range.end.column)
            .map { column in
                accessibleColumn(
                    column,
                    headerRow: headerRow,
                    in: sheet
                )
            }
        let rows: [Int]
        if sheet.isWindowed {
            rows = Array(
                Set(
                    sheet.cells.keys.compactMap { address -> Int? in
                        guard address.row > headerRow,
                              table.range.contains(address) else {
                            return nil
                        }
                        return address.row
                    }
                )
            )
            .sorted()
            .filter {
                rowHasContent(
                    $0,
                    columns: columns.map(\.column),
                    in: sheet
                )
            }
        } else if headerRow < table.range.end.row {
            rows = ((headerRow + 1) ... table.range.end.row)
                .filter {
                    rowHasContent(
                        $0,
                        columns: columns.map(\.column),
                        in: sheet
                    )
                }
        } else {
            rows = []
        }
        return ExcelAccessibleRegion(
            id: "table:" + table.id,
            name: table.name,
            range: table.range,
            headerRow: headerRow,
            columns: columns,
            rowNumbers: rows,
            isNativeTable: true
        )
    }

    /// Excel 표 밖에 있는 제목, 안내문, 요약 블록도 간편 표에서
    /// 읽을 수 있도록 값이 있는 셀만 인접 영역으로 묶는다. 워크시트는
    /// 로드할 때 이미 파싱됐으므로 이 과정에서 파일을 다시 읽지 않는다.
    private static func supplementalRegions(
        in sheet: ExcelWorksheet,
        excluding excludedRanges: [ExcelCellRange]
    ) -> [ExcelAccessibleRegion] {
        let populatedCells = sheet.cells.values.filter { cell in
            hasContent(cell)
                && !excludedRanges.contains(where: {
                    $0.contains(cell.address)
                })
        }
        guard !populatedCells.isEmpty else {
            return []
        }

        let cellsByAddress = Dictionary(
            uniqueKeysWithValues: populatedCells.map {
                ($0.address, $0)
            }
        )
        var remaining = Set(cellsByAddress.keys)
        var components = [[ExcelCell]]()

        while let start = remaining.min() {
            var queue = [start]
            var nextIndex = 0
            var addresses = [ExcelCellAddress]()
            remaining.remove(start)

            while nextIndex < queue.count {
                let address = queue[nextIndex]
                nextIndex += 1
                addresses.append(address)
                for neighbor in adjacentAddresses(to: address) {
                    if remaining.remove(neighbor) != nil {
                        queue.append(neighbor)
                    }
                }
            }
            components.append(
                addresses.compactMap { cellsByAddress[$0] }
            )
        }

        return mergeNearbyComponents(
            components,
            in: sheet
        ).compactMap {
            supplementalRegion(for: $0, in: sheet)
        }
        .sorted {
            if $0.range.start.row != $1.range.start.row {
                return $0.range.start.row < $1.range.start.row
            }
            return $0.range.start.column < $1.range.start.column
        }
    }

    private static func supplementalRegion(
        for cells: [ExcelCell],
        in sheet: ExcelWorksheet
    ) -> ExcelAccessibleRegion? {
        guard !cells.isEmpty else {
            return nil
        }
        let rows = Dictionary(grouping: cells, by: { $0.address.row })
        let rowNumbers = rows.keys.sorted()
        guard let firstRow = rowNumbers.first else {
            return nil
        }
        let bounds = expandedBounds(for: cells, in: sheet)
        let allRowsContainOneLogicalCell = rowNumbers.allSatisfy {
            rows[$0]?.count == 1
        }

        if allRowsContainOneLogicalCell {
            let contentColumn = cells.min(by: {
                $0.address.column < $1.address.column
            })?.address.column ?? bounds.start.column
            return ExcelAccessibleRegion(
                id: supplementalID(
                    sheet: sheet,
                    range: bounds
                ),
                name: DocumentEngineLocalization.string("문서 정보"),
                range: bounds,
                headerRow: nil,
                columns: [
                    ExcelAccessibleColumn(
                        column: contentColumn,
                        title: DocumentEngineLocalization.string("내용")
                    ),
                ],
                rowNumbers: rowNumbers,
                isNativeTable: false
            )
        }

        let firstRowCells = rows[firstRow] ?? []
        let mergedTitleCell = firstRowCells.count == 1
            ? firstRowCells.first.flatMap { cell -> ExcelCell? in
                guard let mergedRange = sheet.mergedRange(
                    containing: cell.address
                ),
                mergedRange.start == cell.address,
                mergedRange.end.column > mergedRange.start.column else {
                    return nil
                }
                return cell
            }
            : nil
        let rowsAfterTitle = rowNumbers.filter { $0 != firstRow }
        let columnsAfterTitle = Array(
            Set(
                rowsAfterTitle.flatMap {
                    rows[$0]?.map(\.address.column) ?? []
                }
            )
        ).sorted()

        if let mergedTitleCell,
           columnsAfterTitle.count == 2,
           !rowsAfterTitle.isEmpty {
            return ExcelAccessibleRegion(
                id: supplementalID(
                    sheet: sheet,
                    range: bounds
                ),
                name: mergedTitleCell.displayValue,
                range: bounds,
                headerRow: firstRow,
                columns: [
                    ExcelAccessibleColumn(
                        column: columnsAfterTitle[0],
                        title: DocumentEngineLocalization.string("항목")
                    ),
                    ExcelAccessibleColumn(
                        column: columnsAfterTitle[1],
                        title: DocumentEngineLocalization.string("값")
                    ),
                ],
                rowNumbers: rowsAfterTitle.filter {
                    rowHasContent(
                        $0,
                        columns: columnsAfterTitle,
                        in: sheet
                    )
                },
                isNativeTable: false
            )
        }

        if let mergedTitleCell,
           !rowsAfterTitle.isEmpty {
            return inferredRegion(
                in: sheet,
                populatedCells: cells.filter {
                    $0.address.row != firstRow
                },
                id: supplementalID(
                    sheet: sheet,
                    range: bounds
                ),
                name: mergedTitleCell.displayValue,
                fixedRange: bounds
            )
        }

        let usedColumns = Array(
            Set(cells.map(\.address.column))
        ).sorted()
        // A title and subtitle can precede a label/value summary without being
        // merged. Its first numeric value is data, never a column heading.
        if usedColumns.count == 2,
           let firstPairRow = rowNumbers.first(where: { rows[$0]?.count == 2 }) {
            let valueRows = rowNumbers.filter { $0 >= firstPairRow }
            let isNumericSummary = valueRows.count >= 2 && valueRows.allSatisfy { row in
                guard let pair = rows[row]?.sorted(by: { $0.address.column < $1.address.column }),
                      pair.count == 2,
                      pair.map(\.address.column) == usedColumns else { return false }
                return ["s", "inlineStr", "str"].contains(pair[0].cellType ?? "")
                    && pair[0].formula?.isEmpty != false
                    && (pair[1].cellType == nil || pair[1].cellType == "n")
                    && Decimal(string: pair[1].rawValue) != nil
            }
            if isNumericSummary {
                return ExcelAccessibleRegion(
                    id: supplementalID(sheet: sheet, range: bounds),
                    name: firstRow < firstPairRow ? (rows[firstRow]?.first?.displayValue ?? sheet.name) : sheet.name,
                    range: bounds,
                    headerRow: nil,
                    columns: [
                        .init(column: usedColumns[0], title: DocumentEngineLocalization.string("항목")),
                        .init(column: usedColumns[1], title: DocumentEngineLocalization.string("값")),
                    ],
                    rowNumbers: valueRows,
                    isNativeTable: false
                )
            }
        }
        if usedColumns.count == 2,
           rowNumbers.count > 1,
           rowNumbers.allSatisfy({ row in
               Set(rows[row]?.map(\.address.column) ?? [])
                   == Set(usedColumns)
           }) {
            let firstLabel = (rows[firstRow] ?? [])
                .min(by: {
                    $0.address.column < $1.address.column
                })?
                .displayValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return ExcelAccessibleRegion(
                id: supplementalID(
                    sheet: sheet,
                    range: bounds
                ),
                name: firstLabel?.isEmpty == false
                    ? firstLabel!
                    : sheet.name,
                range: bounds,
                headerRow: nil,
                columns: [
                    ExcelAccessibleColumn(
                        column: usedColumns[0],
                        title: DocumentEngineLocalization.string("항목")
                    ),
                    ExcelAccessibleColumn(
                        column: usedColumns[1],
                        title: DocumentEngineLocalization.string("값")
                    ),
                ],
                rowNumbers: rowNumbers,
                isNativeTable: false
            )
        }

        return inferredRegion(
            in: sheet,
            populatedCells: cells,
            id: supplementalID(
                sheet: sheet,
                range: bounds
            ),
            name: sheet.name,
            fixedRange: bounds
        )
    }

    /// 표 데이터 사이의 빈 한 행은 같은 영역으로 유지한다. 서로 다른
    /// 요약 블록은 사용 열이 다르므로 합쳐지지 않고, 새 병합 제목으로
    /// 시작하는 영역도 독립 영역으로 남는다.
    private static func mergeNearbyComponents(
        _ components: [[ExcelCell]],
        in sheet: ExcelWorksheet
    ) -> [[ExcelCell]] {
        let sorted = components.sorted {
            componentSortKey($0) < componentSortKey($1)
        }
        var result = [[ExcelCell]]()

        for component in sorted {
            let nextBounds = expandedBounds(
                for: component,
                in: sheet
            )
            let nextColumns = Set(
                component.map(\.address.column)
            )
            let startsWithMergedTitle = componentStartsWithMergedTitle(
                component,
                in: sheet
            )
            let mergeIndex = result.lastIndex { existing in
                let existingBounds = expandedBounds(
                    for: existing,
                    in: sheet
                )
                return !startsWithMergedTitle
                    && nextColumns.count >= 2
                    && Set(existing.map(\.address.column)) == nextColumns
                    && nextBounds.start.row > existingBounds.end.row
                    && (sheet.isWindowed
                        || nextBounds.start.row - existingBounds.end.row <= 2)
            }
            if let mergeIndex {
                result[mergeIndex].append(contentsOf: component)
            } else {
                result.append(component)
            }
        }
        return result
    }

    private static func componentSortKey(
        _ cells: [ExcelCell]
    ) -> ExcelCellAddress {
        cells.map(\.address).min()
            ?? ExcelCellAddress(row: 1, column: 1)
    }

    private static func componentStartsWithMergedTitle(
        _ cells: [ExcelCell],
        in sheet: ExcelWorksheet
    ) -> Bool {
        guard let firstRow = cells.map(\.address.row).min() else {
            return false
        }
        let firstRowCells = cells.filter {
            $0.address.row == firstRow
        }
        guard firstRowCells.count == 1,
              let cell = firstRowCells.first,
              let range = sheet.mergedRange(
                  containing: cell.address
              ) else {
            return false
        }
        return range.start == cell.address
            && range.end.column > range.start.column
    }

    private static func adjacentAddresses(
        to address: ExcelCellAddress
    ) -> [ExcelCellAddress] {
        var result = [ExcelCellAddress]()
        if address.row > 1 {
            result.append(
                ExcelCellAddress(
                    row: address.row - 1,
                    column: address.column
                )
            )
        }
        if address.row < ExcelWorkbookDocument.maximumExcelRows {
            result.append(
                ExcelCellAddress(
                    row: address.row + 1,
                    column: address.column
                )
            )
        }
        if address.column > 1 {
            result.append(
                ExcelCellAddress(
                    row: address.row,
                    column: address.column - 1
                )
            )
        }
        if address.column < ExcelWorkbookDocument.maximumColumnsPerSheet {
            result.append(
                ExcelCellAddress(
                    row: address.row,
                    column: address.column + 1
                )
            )
        }
        return result
    }

    private static func expandedBounds(
        for cells: [ExcelCell],
        in sheet: ExcelWorksheet
    ) -> ExcelCellRange {
        var startRow = cells.map(\.address.row).min() ?? 1
        var endRow = cells.map(\.address.row).max() ?? startRow
        var startColumn = cells.map(\.address.column).min() ?? 1
        var endColumn = cells.map(\.address.column).max() ?? startColumn
        for cell in cells {
            guard let mergedRange = sheet.mergedRange(
                containing: cell.address
            ) else {
                continue
            }
            startRow = min(startRow, mergedRange.start.row)
            endRow = max(endRow, mergedRange.end.row)
            startColumn = min(startColumn, mergedRange.start.column)
            endColumn = max(endColumn, mergedRange.end.column)
        }
        return ExcelCellRange(
            start: ExcelCellAddress(
                row: startRow,
                column: startColumn
            ),
            end: ExcelCellAddress(
                row: endRow,
                column: endColumn
            )
        )
    }

    private static func supplementalID(
        sheet: ExcelWorksheet,
        range: ExcelCellRange
    ) -> String {
        "supplemental:\(sheet.partPath):\(range.reference)"
    }

    private static func inferredRegion(
        in sheet: ExcelWorksheet,
        populatedCells: [ExcelCell],
        id: String,
        name: String,
        fixedRange: ExcelCellRange?
    ) -> ExcelAccessibleRegion? {
        guard !populatedCells.isEmpty else {
            return nil
        }

        let cellsByRow = Dictionary(grouping: populatedCells) {
            $0.address.row
        }
        let populatedRows = cellsByRow.keys.sorted()
        let candidateHeader = populatedRows.first { row in
            guard let cells = cellsByRow[row],
                  cells.count >= 2 else {
                return false
            }
            let columns = Set(cells.map { $0.address.column })
            return populatedRows.contains { laterRow in
                guard laterRow > row,
                      let laterCells = cellsByRow[laterRow] else {
                    return false
                }
                let laterColumns = Set(
                    laterCells.map { $0.address.column }
                )
                return columns.intersection(laterColumns).count
                    >= min(2, columns.count)
            }
        }
        let headerRow = candidateHeader

        let firstContentRow = headerRow ?? populatedRows[0]
        let relevantCells = populatedCells.filter {
            $0.address.row >= firstContentRow
        }
        let usedColumns = Array(
            Set(relevantCells.map { $0.address.column })
        ).sorted()
        guard let firstColumn = usedColumns.first,
              let lastColumn = usedColumns.last else {
            return nil
        }
        let columns = usedColumns.map { column in
            if let headerRow {
                return accessibleColumn(
                    column,
                    headerRow: headerRow,
                    in: sheet
                )
            }
            return ExcelAccessibleColumn(
                column: column,
                title: DocumentEngineLocalization.format(
                    "%@ 열",
                    ExcelCellAddress.columnName(column)
                )
            )
        }
        let rows = populatedRows.filter { row in
            row != headerRow
                && row >= firstContentRow
                && rowHasContent(
                    row,
                    columns: usedColumns,
                    in: sheet
                )
        }
        let lastRow = max(
            rows.last ?? headerRow ?? firstContentRow,
            firstContentRow
        )
        return ExcelAccessibleRegion(
            id: id,
            name: name,
            range: fixedRange ?? ExcelCellRange(
                start: ExcelCellAddress(
                    row: firstContentRow,
                    column: firstColumn
                ),
                end: ExcelCellAddress(
                    row: lastRow,
                    column: lastColumn
                )
            ),
            headerRow: headerRow,
            columns: columns,
            rowNumbers: rows,
            isNativeTable: false
        )
    }

    private static func hasContent(_ cell: ExcelCell) -> Bool {
        !cell.displayValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty || cell.formula?.isEmpty == false
    }

    private static func accessibleColumn(
        _ column: Int,
        headerRow: Int,
        in sheet: ExcelWorksheet
    ) -> ExcelAccessibleColumn {
        let value = sheet.cell(
            at: ExcelCellAddress(
                row: headerRow,
                column: column
            )
        )?.displayValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return ExcelAccessibleColumn(
            column: column,
            title: value?.isEmpty == false
                ? value!
                : DocumentEngineLocalization.format(
                    "%@ 열",
                    ExcelCellAddress.columnName(column)
                )
        )
    }

    private static func rowHasContent(
        _ row: Int,
        columns: [Int],
        in sheet: ExcelWorksheet
    ) -> Bool {
        columns.contains { column in
            let cell = sheet.cell(
                at: sheet.canonicalAddress(
                    for: ExcelCellAddress(
                        row: row,
                        column: column
                    )
                )
            )
            return cell?.formula?.isEmpty == false
                || cell?.displayValue.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty == false
        }
    }
}
