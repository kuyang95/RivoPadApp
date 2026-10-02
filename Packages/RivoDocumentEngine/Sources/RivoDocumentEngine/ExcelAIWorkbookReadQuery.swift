import Foundation

/// Executes one grounded plan across explicitly named sheets. Every target owns
/// its own region and column mapping, so equal column numbers on different
/// sheets are never assumed to mean the same thing.
public nonisolated enum ExcelAIWorkbookReadQueryExecutor {
    private struct SourceRow {
        let sheetID: String
        let sheetName: String
        let row: Int
        let target: ExcelAIReadQuery.SheetTarget
        let data: ExcelAIQueryData
    }

    public static func execute(_ query: ExcelAIReadQuery, snapshot: ExcelAIWorkbookSnapshot) throws -> ExcelAIReadQueryResult {
        guard let workbook = snapshot.localWorkbook,
              !query.sheetTargets.isEmpty, query.sheetTargets.count <= 64,
              query.presentation != .single,
              Set(query.sheetTargets.map(\.sheetID)).count == query.sheetTargets.count,
              query.regionID.isEmpty, query.filters.isEmpty, query.selectColumns.isEmpty,
              query.metricColumn == nil, query.groupBy.isEmpty, !query.visibleOnly else {
            throw ExcelAIReadQueryError.invalidQuery
        }
        if let scope = query.workbookInputScope, scope.revision != snapshot.revision {
            throw ExcelAIReadQueryError.staleResult
        }
        if query.operation == .rows && [.combined, .both].contains(query.presentation) {
            throw ExcelAIReadQueryError.invalidQuery
        }

        let groupCount = query.sheetTargets.first?.groupBy.count ?? 0
        let selectCount = query.sheetTargets.first?.selectColumns.count ?? 0
        guard query.sheetTargets.allSatisfy({ $0.groupBy.count == groupCount && $0.selectColumns.count == selectCount }) else {
            throw ExcelAIReadQueryError.invalidQuery
        }

        var childAnswers: [String] = []
        var childReferences: [ExcelAIReferences] = []
        var scopeRowsBySheet: [String: [Int]] = [:]
        var sourceRows: [SourceRow] = []

        for target in query.sheetTargets {
            guard let sheetIndex = workbook.sheets.firstIndex(where: { $0.partPath == target.sheetID }),
                  let childSnapshot = ExcelAISnapshotBuilder.make(
                    workbookName: snapshot.workbookName, workbook: workbook, selectedSheetIndex: sheetIndex,
                    selectedAddress: nil, supportsEdits: false
                  ) else { throw ExcelAIReadQueryError.invalidQuery }
            let child = childQuery(query, target: target, revision: childSnapshot.revision)
            let prepared = try ExcelAIReadQueryExecutor.matchingRows(child, snapshot: childSnapshot)
            guard let result = try ExcelAIReadQueryExecutor.execute(child, snapshot: childSnapshot) else {
                throw ExcelAIReadQueryError.invalidQuery
            }
            childAnswers.append("[\(childSnapshot.sheetName)]\n\(result.answer)")
            if let references = result.references { childReferences.append(references) }
            scopeRowsBySheet[target.sheetID] = result.scopeRows ?? result.rows
            sourceRows.append(contentsOf: prepared.rows.map {
                SourceRow(sheetID: target.sheetID, sheetName: childSnapshot.sheetName, row: $0, target: target, data: prepared.data)
            })
        }

        var combinedResult: ExcelAIReadQueryResult?
        var combinedReferences: ExcelAIReferences?
        if [.combined, .both].contains(query.presentation) {
            let combined = try makeCombined(query, sourceRows: sourceRows, workbook: workbook, workbookName: snapshot.workbookName)
            combinedResult = combined.result
            combinedReferences = combined.references
        }

        let answer: String
        switch query.presentation {
        case .bySheet:
            answer = childAnswers.joined(separator: "\n\n")
        case .combined:
            answer = DocumentEngineLocalization.format("%lld개 시트 통합 결과", query.sheetTargets.count) + "\n" + (combinedResult?.answer ?? "")
        case .both:
            answer = childAnswers.joined(separator: "\n\n") + "\n\n" + DocumentEngineLocalization.format("%lld개 시트 통합 결과", query.sheetTargets.count) + "\n" + (combinedResult?.answer ?? "")
        case .single:
            throw ExcelAIReadQueryError.invalidQuery
        }

        let references: ExcelAIReferences?
        switch query.presentation {
        case .bySheet: references = ExcelAIReferences.combining(childReferences)
        case .combined: references = combinedReferences
        case .both: references = ExcelAIReferences.combining(childReferences + [combinedReferences].compactMap { $0 })
        case .single: references = nil
        }
        let displayedRows = combinedResult?.rows ?? sourceRows.map(\.row)
        return .init(rows: displayedRows, answer: answer, references: references,
                     scopeRowsBySheet: scopeRowsBySheet)
    }

    private static func childQuery(_ query: ExcelAIReadQuery, target: ExcelAIReadQuery.SheetTarget, revision: String) -> ExcelAIReadQuery {
        var child = ExcelAIReadQuery(
            operation: query.operation, regionID: target.regionID, match: target.match, filters: target.filters,
            selectColumns: target.selectColumns, metricColumn: target.metricColumn, groupBy: target.groupBy,
            sort: query.sort, limit: query.limit, visibleOnly: target.visibleOnly
        )
        if let scope = query.workbookInputScope?.rowsBySheet[target.sheetID] {
            child.inputScope = .init(revision: revision, rows: scope)
        }
        return child
    }

    private static func makeCombined(
        _ query: ExcelAIReadQuery, sourceRows: [SourceRow], workbook: ExcelWorkbook, workbookName: String
    ) throws -> (result: ExcelAIReadQueryResult, references: ExcelAIReferences?) {
        guard query.operation != .rank else { throw ExcelAIReadQueryError.invalidQuery }
        let groupCount = query.sheetTargets.first?.groupBy.count ?? 0
        let needsMetric = [.sum, .average, .minimum, .maximum, .distinctCount].contains(query.operation)
        let metricColumn = needsMetric ? groupCount + 1 : nil
        let firstTarget = query.sheetTargets[0]
        guard let firstSheet = workbook.sheets.first(where: { $0.partPath == firstTarget.sheetID }) else {
            throw ExcelAIReadQueryError.invalidQuery
        }
        let firstRegion = try region(firstTarget.regionID, in: firstSheet)
        let firstTitles = Dictionary(uniqueKeysWithValues: firstRegion.columns.map { ($0.number, $0.title) })
        let groupTitles = firstTarget.groupBy.enumerated().map { firstTitles[$0.element] ?? DocumentEngineLocalization.format("그룹 %lld", $0.offset + 1) }
        let metricTitle = firstTarget.metricColumn.flatMap { firstTitles[$0] } ?? DocumentEngineLocalization.string("행")

        var cells: [ExcelCellAddress: ExcelCell] = [:]
        let titles = groupTitles + (needsMetric ? [metricTitle] : []) + (!needsMetric && groupCount == 0 ? [DocumentEngineLocalization.string("행")] : [])
        for (offset, title) in titles.enumerated() {
            let address = ExcelCellAddress(row: 1, column: offset + 1)
            cells[address] = .init(address: address, rawValue: title, displayValue: title, formula: nil, styleIndex: nil, cellType: "inlineStr")
        }
        var originals: [Int: SourceRow] = [:]
        for (offset, source) in sourceRows.enumerated() {
            let syntheticRow = offset + 2
            originals[syntheticRow] = source
            for (groupOffset, originalColumn) in source.target.groupBy.enumerated() {
                try copyCell(from: source, originalColumn: originalColumn, to: .init(row: syntheticRow, column: groupOffset + 1), cells: &cells)
            }
            if let originalMetric = source.target.metricColumn, let metricColumn {
                try copyCell(from: source, originalColumn: originalMetric, to: .init(row: syntheticRow, column: metricColumn), cells: &cells)
            }
            if !needsMetric && groupCount == 0 {
                let address = ExcelCellAddress(row: syntheticRow, column: 1)
                cells[address] = .init(address: address, rawValue: "1", displayValue: "1", formula: nil, styleIndex: nil, cellType: nil)
            }
        }
        let maximumRow = max(1, sourceRows.count + 1)
        let maximumColumn = max(1, titles.count)
        let tableRange = ExcelCellRange("A1:\(ExcelCellAddress.columnName(maximumColumn))\(maximumRow)")!
        let synthetic = ExcelWorksheet(
            id: "ai-workbook-query", name: DocumentEngineLocalization.string("통합 데이터"), partPath: "ai/workbook-query",
            cells: cells, mergedRanges: [], tables: [.init(id: "ai", name: "Combined", range: tableRange, partPath: "ai/table")],
            columnWidths: [:], rowHeights: [:], maximumRow: maximumRow, maximumColumn: maximumColumn, didTruncate: false
        )
        let syntheticBook = ExcelWorkbook(sheets: [synthetic], styles: workbook.styles, differentialStyles: workbook.differentialStyles,
                                          definedNames: [], protection: .init(), externalLinks: [],
                                          supportsDynamicArrays: workbook.supportsDynamicArrays, uses1904DateSystem: workbook.uses1904DateSystem)
        guard let syntheticSnapshot = ExcelAISnapshotBuilder.make(
            workbookName: workbookName, workbook: syntheticBook, selectedSheetIndex: 0, selectedAddress: nil, supportsEdits: false
        ), let syntheticRegion = syntheticSnapshot.regions.first else { throw ExcelAIReadQueryError.invalidQuery }
        let syntheticQuery = ExcelAIReadQuery(
            operation: query.operation, regionID: syntheticRegion.id, match: .all, filters: [], selectColumns: [],
            metricColumn: metricColumn, groupBy: groupCount == 0 ? [] : Array(1...groupCount), sort: query.sort, limit: query.limit
        )
        guard let result = try ExcelAIReadQueryExecutor.execute(syntheticQuery, snapshot: syntheticSnapshot) else {
            throw ExcelAIReadQueryError.invalidQuery
        }
        let selectedSources = result.rows.compactMap { originals[$0] }
        let references = references(for: selectedSources, operation: query.operation)
        return (result, references)
    }

    private static func copyCell(from source: SourceRow, originalColumn: Int, to address: ExcelCellAddress,
                                 cells: inout [ExcelCellAddress: ExcelCell]) throws {
        guard let original = try source.data.cell(row: source.row, column: originalColumn) else { return }
        cells[address] = .init(address: address, rawValue: original.rawValue, displayValue: original.displayValue,
                               formula: nil, styleIndex: original.styleIndex, cellType: original.cellType)
    }

    private static func region(_ id: String, in sheet: ExcelWorksheet) throws -> ExcelAIWorkbookSnapshot.Region {
        guard let found = ExcelAccessibilityAnalyzer.regions(in: sheet).first(where: { $0.id == id }) else {
            throw ExcelAIReadQueryError.invalidQuery
        }
        return .init(id: found.id, name: found.name, range: found.range.reference, headerRow: found.headerRow,
                     columns: found.columns.map { .init(number: $0.column, letter: ExcelCellAddress.columnName($0.column), title: $0.title) },
                     dataRows: ExcelAIQueryData.dataRows(found.rowNumbers, regionID: found.id, sheet: sheet), isNativeTable: found.isNativeTable)
    }

    private static func references(for rows: [SourceRow], operation: ExcelAIReadQuery.Operation) -> ExcelAIReferences? {
        var grouped: [String: (name: String, addresses: Set<ExcelCellAddress>)] = [:]
        var order: [String] = []
        for source in rows {
            if grouped[source.sheetID] == nil {
                order.append(source.sheetID)
                grouped[source.sheetID] = (source.sheetName, [])
            }
            var columns = source.target.filters.map(\.column) + source.target.groupBy
            if let metric = source.target.metricColumn { columns.append(metric) }
            if operation == .rows || operation == .rank { columns.append(contentsOf: source.target.selectColumns) }
            for column in Set(columns) {
                let address = source.data.sheet.canonicalAddress(for: .init(row: source.row, column: column))
                if source.data.sheet.cell(at: address) != nil { grouped[source.sheetID]!.addresses.insert(address) }
            }
        }
        let refs = order.compactMap { path -> ExcelAIReferences? in
            guard let group = grouped[path], !group.addresses.isEmpty else { return nil }
            return .init(sheetPartPath: path, sheetName: group.name, addresses: group.addresses.sorted())
        }
        return ExcelAIReferences.combining(refs)
    }
}
