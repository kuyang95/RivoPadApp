import XCTest
@testable import shortcuts_example

final class ExcelAIWorkbookReadQueryTests: XCTestCase {
    private func sheet(id: String, name: String, path: String, rows: [[(String, String?)]]) -> ExcelWorksheet {
        var cells: [ExcelCellAddress: ExcelCell] = [:]
        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, value) in row.enumerated() {
                let address = ExcelCellAddress(row: rowIndex + 1, column: columnIndex + 1)
                cells[address] = .init(address: address, rawValue: value.0, displayValue: value.0,
                                       formula: nil, styleIndex: nil, cellType: value.1)
            }
        }
        return .init(id: id, name: name, partPath: path, cells: cells, mergedRanges: [], tables: [],
                     columnWidths: [:], rowHeights: [:], maximumRow: rows.count,
                     maximumColumn: rows.map(\.count).max() ?? 1, didTruncate: false)
    }

    private func workbook() -> ExcelWorkbook {
        let january = sheet(id: "1", name: "1월", path: "xl/worksheets/sheet1.xml", rows: [
            [("Product", "inlineStr"), ("Sales", "inlineStr"), ("Country", "inlineStr")],
            [("A", "inlineStr"), ("10", nil), ("Germany", "inlineStr")],
            [("B", "inlineStr"), ("20", nil), ("France", "inlineStr")],
            [("A", "inlineStr"), ("30", nil), ("Germany", "inlineStr")],
        ])
        let february = sheet(id: "2", name: "2월", path: "xl/worksheets/sheet2.xml", rows: [
            [("Country", "inlineStr"), ("Revenue", "inlineStr"), ("Item", "inlineStr")],
            [("Germany", "inlineStr"), ("40", nil), ("A", "inlineStr")],
            [("France", "inlineStr"), ("50", nil), ("B", "inlineStr")],
        ])
        return .init(sheets: [january, february], styles: [.plain], uses1904DateSystem: false)
    }

    private func target(sheet: ExcelWorksheet, countryColumn: Int, metricColumn: Int, groupColumn: Int? = nil,
                        country: String? = nil) -> ExcelAIReadQuery.SheetTarget {
        let region = ExcelAccessibilityAnalyzer.regions(in: sheet)[0]
        return .init(sheetID: sheet.partPath, regionID: region.id, match: .all,
                     filters: country.map { [.init(column: countryColumn, comparison: .equals, valueType: .text, value: $0)] } ?? [],
                     selectColumns: [], metricColumn: metricColumn, groupBy: groupColumn.map { [$0] } ?? [], visibleOnly: false)
    }

    private func query(_ operation: ExcelAIReadQuery.Operation, targets: [ExcelAIReadQuery.SheetTarget],
                       presentation: ExcelAIReadQuery.Presentation) -> ExcelAIReadQuery {
        .init(operation: operation, regionID: "", match: .all, filters: [], selectColumns: [],
              sheetTargets: targets, presentation: presentation)
    }

    func testDifferentColumnLayoutsProducePerSheetAndCombinedTotals() throws {
        let book = workbook()
        let snapshot = try XCTUnwrap(ExcelAISnapshotBuilder.make(workbookName: "Months", workbook: book, selectedSheetIndex: 0, selectedAddress: nil))
        let targets = [
            target(sheet: book.sheets[0], countryColumn: 3, metricColumn: 2, country: "Germany"),
            target(sheet: book.sheets[1], countryColumn: 1, metricColumn: 2, country: "Germany"),
        ]
        let result = try XCTUnwrap(ExcelAIReadQueryExecutor.execute(query(.sum, targets: targets, presentation: .both), snapshot: snapshot))
        XCTAssertTrue(result.answer.contains("[1월]"))
        XCTAssertTrue(result.answer.contains("[2월]"))
        XCTAssertTrue(result.answer.contains("80"))
        XCTAssertEqual(result.references?.sheets.map(\.sheetName), ["1월", "2월"])
        XCTAssertEqual(result.scopeRowsBySheet?[book.sheets[0].partPath], [2, 4])
        XCTAssertEqual(result.scopeRowsBySheet?[book.sheets[1].partPath], [2])
    }

    func testCombinedGroupingMapsDifferentProductColumns() throws {
        let book = workbook()
        let snapshot = try XCTUnwrap(ExcelAISnapshotBuilder.make(workbookName: "Months", workbook: book, selectedSheetIndex: 0, selectedAddress: nil))
        let targets = [
            target(sheet: book.sheets[0], countryColumn: 3, metricColumn: 2, groupColumn: 1),
            target(sheet: book.sheets[1], countryColumn: 1, metricColumn: 2, groupColumn: 3),
        ]
        let result = try XCTUnwrap(ExcelAIReadQueryExecutor.execute(query(.sum, targets: targets, presentation: .combined), snapshot: snapshot))
        XCTAssertTrue(result.answer.contains("Product: A"), result.answer)
        XCTAssertTrue(result.answer.contains("80"), result.answer)
        XCTAssertTrue(result.answer.contains("Product: B"), result.answer)
        XCTAssertTrue(result.answer.contains("70"), result.answer)
        XCTAssertEqual(result.references?.totalAddressCount, 10)
    }

    func testWorkbookContextIncludesOriginalCellsFromBothSheets() throws {
        let book = workbook()
        let snapshot = try XCTUnwrap(ExcelAISnapshotBuilder.make(workbookName: "Months", workbook: book, selectedSheetIndex: 0, selectedAddress: nil))
        let context = ExcelAIReadQueryContext(request: "각 시트의 매출 합계", snapshot: snapshot, history: [])
        let json = String(data: try JSONEncoder().encode(context), encoding: .utf8)!
        XCTAssertTrue(json.contains(#""queryScope":"workbook""#), json)
        XCTAssertTrue(json.contains(#""name":"1월""#), json)
        XCTAssertTrue(json.contains(#""name":"2월""#), json)
        XCTAssertTrue(json.contains(#""value":"Revenue""#), json)
        XCTAssertFalse(json.contains(#""title":"Revenue""#), json)
        XCTAssertEqual(context.source.cells.first { $0.sheetID == book.sheets[1].partPath && $0.address == "B1" }?.value, "Revenue")
    }

    func testUnsafeWorkbookPlansAreRejected() throws {
        let book = workbook()
        let snapshot = try XCTUnwrap(ExcelAISnapshotBuilder.make(workbookName: "Months", workbook: book, selectedSheetIndex: 0, selectedAddress: nil))
        let one = target(sheet: book.sheets[0], countryColumn: 3, metricColumn: 2)
        XCTAssertThrowsError(try ExcelAIReadQueryExecutor.execute(query(.sum, targets: [one, one], presentation: .combined), snapshot: snapshot))
        XCTAssertThrowsError(try ExcelAIReadQueryExecutor.execute(query(.rows, targets: [one], presentation: .combined), snapshot: snapshot))
    }
}
