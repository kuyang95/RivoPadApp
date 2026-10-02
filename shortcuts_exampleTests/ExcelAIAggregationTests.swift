import RivoDocumentEngine
import Foundation
import XCTest
@testable import shortcuts_example

final class ExcelAIAggregationTests: XCTestCase {
    private func workbook() throws -> ExcelWorkbook {
        let blank = try ExcelWorkbookDocument.blankWorkbookData(), book = try ExcelWorkbookDocument.load(from: blank)
        var cells: [ExcelCellAddress: ExcelCellEdit] = [:]
        let rows: [[ExcelCellInput]] = [
            ["Country", "Product", "Sales", "Profit", "Units", "ID"].map(ExcelCellInput.text),
            [.text("Germany"), .text("A"), .number("10.1"), .number("2"), .number("888"), .text("001")],
            [.text("Germany"), .text("B"), .number("20.2"), .number("4"), .number("0"), .text("001")],
            [.text("France"), .text("A"), .number("30.3"), .number("6"), .number("888"), .text("002")],
            [.text("Germany"), .text(" a "), .number("30.3"), .number("8"), .number("10"), .text("003")],
            [.text("Germany"), .text("C"), .blank, .text("9"), .blank, .blank],
            [.text("Germany"), .text("C"), .text("100"), .number("0"), .number("2"), .text("1")],
            [.text("France"), .text("B"), .number("-5.05"), .formula("C8*2"), .number("5"), .number("1")]
        ]
        for (r, row) in rows.enumerated() { for (c, input) in row.enumerated() { cells[.init(row: r + 1, column: c + 1)] = .init(input: input, styleIndex: nil) } }
        return try ExcelWorkbookDocument.load(from: ExcelWorkbookDocument.applying([.init(partPath: book.sheets[0].partPath, cells: cells)], to: blank, workbook: book))
    }
    private func snapshot(_ change: (inout ExcelWorkbook) -> Void = { _ in }) throws -> ExcelAIWorkbookSnapshot {
        var book = try workbook(); change(&book)
        return try XCTUnwrap(ExcelAISnapshotBuilder.make(workbookName: "Aggregate", workbook: book, selectedSheetIndex: 0, selectedAddress: ExcelCellAddress("A2")))
    }
    private func query(_ op: ExcelAIReadQuery.Operation, _ snapshot: ExcelAIWorkbookSnapshot, metric: Int? = 3,
                       groups: [Int] = [], filters: [ExcelAIReadQuery.Filter] = [], sort: ExcelAIReadQuery.Sort? = nil, limit: Int? = nil,
                       visible: Bool = false) -> ExcelAIReadQuery {
        .init(operation: op, regionID: snapshot.regions[0].id, match: .all, filters: filters, selectColumns: op == .rank ? [2] : [],
              metricColumn: metric, groupBy: groups, sort: sort, limit: limit, visibleOnly: visible)
    }
    private let germany = ExcelAIReadQuery.Filter(column: 1, comparison: .equals, valueType: .text, value: "Germany")
    private func result(_ q: ExcelAIReadQuery, _ s: ExcelAIWorkbookSnapshot) throws -> ExcelAIReadQueryResult {
        let result = try ExcelAIReadQueryExecutor.execute(q, snapshot: s)
        return try XCTUnwrap(result)
    }
    func testWholeRegionSumAndConditionalAverageUseRawNumbers() throws {
        let s = try snapshot { $0.sheets[0].cells[ExcelCellAddress("C2")!]?.displayValue = "10" }
        let sum = try result(query(.sum, s), s)
        XCTAssertTrue(sum.answer.contains("85.85")); XCTAssertEqual(sum.rows, [2, 3, 4, 5, 8])
        XCTAssertEqual(sum.references?.addresses.map(\.reference), ["C2", "C3", "C4", "C5", "C8"])
        let average = try result(query(.average, s, filters: [germany]), s)
        XCTAssertTrue(average.answer.contains("20.2")); XCTAssertEqual(average.rows, [2, 3, 5])
        XCTAssertEqual(average.references?.addresses.map(\.reference), ["A2", "C2", "A3", "C3", "A5", "C5"])
    }
    func testGroupedAverageRecalculatesFormulasAndKeepsZero() throws {
        let s = try snapshot { $0.sheets[0].cells[ExcelCellAddress("D8")!]?.rawValue = "999999" }
        let answer = try result(query(.average, s, metric: 4, groups: [2]), s)
        XCTAssertTrue(answer.answer.contains("5.333333333333")); XCTAssertTrue(answer.answer.contains("≈"))
        XCTAssertTrue(answer.answer.contains("-3.05")); XCTAssertFalse(answer.answer.contains("999999"))
        XCTAssertEqual(answer.rows, [2, 3, 4, 5, 7, 8])
        XCTAssertFalse(answer.references?.addresses.contains(ExcelCellAddress("D6")!) == true)
        XCTAssertTrue(answer.references?.addresses.contains(ExcelCellAddress("D7")!) == true)
        XCTAssertEqual(s.localQuerySheet?.cells[ExcelCellAddress("D8")!]?.rawValue, "999999", "Queries do not mutate cached workbook values")
    }
    func testDistinctValuesIgnoreBlankAndKeepNumericTextSeparate() throws {
        let s = try snapshot()
        let products = try result(query(.distinctCount, s, metric: 2), s)
        XCTAssertTrue(products.answer.contains(": 3")); XCTAssertEqual(products.rows, Array(2...8))
        let ids = try result(query(.distinctCount, s, metric: 6), s)
        XCTAssertTrue(ids.answer.contains(": 5")); XCTAssertEqual(ids.rows, [2, 3, 4, 5, 7, 8])
        XCTAssertFalse(ids.references?.addresses.contains(ExcelCellAddress("F6")!) == true)
    }
    func testTopRowsUseStableTiesAndOnlyResultEvidence() throws {
        let s = try snapshot()
        let top = try result(query(.rank, s, sort: .descending, limit: 1), s)
        XCTAssertEqual(top.rows, [4]); XCTAssertEqual(top.references?.addresses.map(\.reference), ["B4", "C4"])
        XCTAssertTrue(top.answer.contains("동점"))
        let two = try result(query(.rank, s, sort: .descending, limit: 2), s)
        XCTAssertEqual(two.rows, [4, 5]); XCTAssertTrue(two.answer.contains("1위 · 5행"))
        let bottom = try result(query(.rank, s, sort: .ascending, limit: 2), s)
        XCTAssertEqual(bottom.rows, [8, 2])
    }
    func testProductTotalsAreRankedAfterGrouping() throws {
        let s = try snapshot()
        let top = try result(query(.sum, s, groups: [2], sort: .descending, limit: 1), s)
        XCTAssertTrue(top.answer.contains("70.7")); XCTAssertEqual(top.rows, [2, 4, 5])
        XCTAssertEqual(top.references?.addresses.map(\.reference), ["B2", "C2", "B4", "C4", "B5", "C5"])
    }
    func testMinimumMaximumHighlightAllTiedResultCells() throws {
        let s = try snapshot()
        XCTAssertEqual(try result(query(.minimum, s), s).rows, [8])
        XCTAssertEqual(try result(query(.maximum, s), s).references?.addresses.map(\.reference), ["C4", "C5"])
    }
    func testHiddenRowsIncludedUnlessVisibleOnlyRequested() throws {
        let s = try snapshot { $0.sheets[0].hiddenRows = [4, 5] }
        XCTAssertTrue(try result(query(.sum, s), s).answer.contains("85.85"))
        let visible = try result(query(.sum, s, visible: true), s)
        XCTAssertTrue(visible.answer.contains("25.25")); XCTAssertEqual(visible.rows, [2, 3, 8])
    }
    func testNativeTableTotalsAreNotCountedTwice() throws {
        let s = try snapshot { book in
            book.sheets[0].tables = [.init(id: "1", name: "SalesTable", range: ExcelCellRange("A1:F8")!, partPath: "xl/tables/table1.xml", totalsRowCount: 1)]
        }
        let total = try result(query(.sum, s), s)
        XCTAssertTrue(total.answer.contains("90.9")); XCTAssertFalse(total.rows.contains(8))
        let count = try result(query(.count, s, metric: nil), s)
        XCTAssertEqual(count.rows.count, 6)
        XCTAssertFalse(s.valueGroups.flatMap(\.addresses).contains(ExcelCellAddress("A8")!))
    }
    func testGroupedRecordCountAndDistinctCount() throws {
        let s = try snapshot()
        let count = try result(query(.count, s, metric: nil, groups: [1]), s)
        XCTAssertTrue(count.answer.contains(": 5")); XCTAssertTrue(count.answer.contains(": 2"))
        let distinct = try result(query(.distinctCount, s, metric: 2, groups: [1]), s)
        XCTAssertTrue(distinct.answer.contains("Country: Germany")); XCTAssertTrue(distinct.answer.contains(": 3"))
    }
    func testEmptyMatchAndAllTextDoNotInventZeroAverage() throws {
        let s = try snapshot()
        let empty = try result(query(.sum, s, filters: [.init(column: 1, comparison: .equals, valueType: .text, value: "missing")]), s)
        XCTAssertTrue(empty.rows.isEmpty); XCTAssertNil(empty.references)
        let text = try result(query(.average, s, metric: 2), s)
        XCTAssertTrue(text.rows.isEmpty); XCTAssertNil(text.references); XCTAssertTrue(text.answer.contains("계산할 숫자"))
    }
    func testInvalidMetricsOptionsAndLimitsAreRejected() throws {
        let s = try snapshot()
        for q in [query(.sum, s, metric: nil), query(.sum, s, metric: 99), query(.sum, s, groups: [1, 1]), query(.rank, s, sort: nil), query(.rank, s, sort: .descending, limit: 101), query(.sum, s, limit: 1), query(.count, s)] {
            XCTAssertThrowsError(try ExcelAIReadQueryExecutor.execute(q, snapshot: s))
        }
    }
    func testErrorsAndUnsupportedFormulasFailOnlyWhenRequired() throws {
        let s = try snapshot {
            $0.sheets[0].cells[ExcelCellAddress("C8")!]?.cellType = "e"
            $0.sheets[0].cells[ExcelCellAddress("C8")!]?.rawValue = "#DIV/0!"
        }
        XCTAssertThrowsError(try ExcelAIReadQueryExecutor.execute(query(.sum, s), snapshot: s))
        XCTAssertTrue(try result(query(.sum, s, filters: [germany]), s).answer.contains("60.6"))
        let unsupported = try snapshot { $0.sheets[0].cells[ExcelCellAddress("C2")!]?.formula = "UNKNOWNFUNCTION(1)" }
        XCTAssertThrowsError(try ExcelAIReadQueryExecutor.execute(query(.sum, unsupported), snapshot: unsupported))
    }
    func testDecimalsDoNotSilentlyLoseLargeIntegerPrecision() throws {
        let values = [Decimal(string: "9007199254740993")!, Decimal(string: "0.1")!, Decimal(string: "0.2")!]
        XCTAssertEqual(try ExcelAIAggregation.aggregate(.sum, values: values)?.number, Decimal(string: "9007199254740993.3"))
        XCTAssertNil(ExcelAIReadQueryExecutor.decimal("123456789012345678901234567890123456789"))
        XCTAssertNil(ExcelAIReadQueryExecutor.decimal("1e-200"))
        XCTAssertThrowsError(try ExcelAIAggregation.aggregate(.sum, values: [Decimal(string: "1e38")!, Decimal(string: "0.01")!]))
    }
    func testFollowupUsesExactPriorRankedRowsAndRejectsStaleScope() throws {
        let s = try snapshot()
        var top = query(.rank, s, sort: .descending, limit: 2)
        top.resultScope = .init(revision: s.revision, rows: try result(top, s).rows)
        let context = ExcelAIReadQueryContext(request: "그중 평균 매출은?", snapshot: s, history: [.init(role: "assistant", text: "", query: top)])
        let average = try context.resolved(query(.average, s))
        XCTAssertEqual(try result(average, s).rows, [4, 5]); XCTAssertTrue(try result(average, s).answer.contains("30.3"))
        let changed = try snapshot { $0.sheets[0].cells[ExcelCellAddress("C4")!]?.rawValue = "100" }
        let stale = ExcelAIReadQueryContext(request: "그중 평균은?", snapshot: changed, history: [.init(role: "assistant", text: "", query: top)])
        XCTAssertThrowsError(try stale.resolved(query(.average, changed)))
    }
    func testOldQueriesDecodeAndLocalScopesNeverEnterModelJSON() throws {
        let old = #"{"operation":"count","regionID":"region","match":"all","filters":[],"selectColumns":[]}"#
        let decoded = try JSONDecoder().decode(ExcelAIReadQuery.self, from: Data(old.utf8))
        XCTAssertTrue(decoded.groupBy.isEmpty); XCTAssertNil(decoded.metricColumn); XCTAssertFalse(decoded.visibleOnly)
        let s = try snapshot(); var q = query(.sum, s); q.inputScope = .init(revision: "private", rows: [999]); q.resultScope = q.inputScope
        let json = String(data: try JSONEncoder().encode(q), encoding: .utf8)!
        XCTAssertFalse(json.contains("private")); XCTAssertFalse(json.contains("999")); XCTAssertFalse(json.contains("Scope"))
        let injected = old.dropLast() + #", "inputScope":{"revision":"x","rows":[1]}}"#
        XCTAssertNil(try JSONDecoder().decode(ExcelAIReadQuery.self, from: Data(injected.utf8)).inputScope)
    }
    func testFullSheetNumbersBeyondModelContextAreIncluded() throws {
        let s = try snapshot { book in
            for row in 9...1000 { for column in 1...6 {
                let address = ExcelCellAddress(row: row, column: column)
                book.sheets[0].cells[address] = .init(address: address, rawValue: column == 3 ? "1" : "Extra", displayValue: column == 3 ? "1" : "Extra", formula: nil, styleIndex: nil, cellType: column == 3 ? nil : "inlineStr")
            }}
            book.sheets[0].maximumRow = 1000
        }
        XCTAssertTrue(s.contextWasTruncated)
        let total = try result(query(.sum, s), s)
        XCTAssertTrue(total.answer.contains("1077.85")); XCTAssertEqual(total.rows.count, 997)
        XCTAssertTrue(total.references?.addresses.contains(ExcelCellAddress("C1000")!) == true)
    }
    func testPercentFormattingAndUnsupportedDateAverage() throws {
        let s = try snapshot { book in
            book.styles[0].numberFormatID = 9; book.styles[0].numberFormatCode = "0%"
            for (row, value) in [(2, "0.1"), (3, "0.2"), (4, "0.3"), (5, "0.3"), (8, "-0.05")] {
                book.sheets[0].cells[.init(row: row, column: 3)]?.rawValue = value
                book.sheets[0].cells[.init(row: row, column: 3)]?.styleIndex = 0
            }
        }
        XCTAssertTrue(try result(query(.average, s), s).answer.contains("17%"))
        let date = try snapshot { book in
            book.styles[0].numberFormatID = 14; book.styles[0].numberFormatCode = "yyyy-mm-dd"
            book.sheets[0].cells[ExcelCellAddress("C2")!]?.styleIndex = 0
        }
        XCTAssertThrowsError(try ExcelAIReadQueryExecutor.execute(query(.average, date), snapshot: date))
    }
    func testTruncatedAndVerticallyMergedDataAreRejected() throws {
        for truncated in [false, true] {
            let s = try snapshot { book in
                let old = book.sheets[0]
                book.sheets[0] = .init(id: old.id, name: old.name, partPath: old.partPath, cells: old.cells,
                    mergedRanges: truncated ? [] : [ExcelCellRange("C2:C3")!], tables: [], columnWidths: [:], rowHeights: [:],
                    maximumRow: old.maximumRow, maximumColumn: old.maximumColumn, didTruncate: truncated)
            }
            XCTAssertThrowsError(try ExcelAIReadQueryExecutor.execute(query(.sum, s), snapshot: s))
            if truncated { XCTAssertFalse(s.supportsLocalQueries); XCTAssertTrue(s.valueGroups.isEmpty) }
        }
    }
    func testComparisonCorrectionPreservesAggregationFields() throws {
        let s = try snapshot()
        let context = ExcelAIReadQueryContext(request: "Units가 888인 제품별 매출 합계 상위 2개", snapshot: s, history: [])
        let incorrect = query(.sum, s, groups: [2], filters: [.init(column: 5, comparison: .greaterThan, valueType: .number, value: "888")], sort: .descending, limit: 2)
        let corrected = try context.resolved(incorrect)
        XCTAssertEqual(corrected.filters.first?.comparison, .equals); XCTAssertEqual(corrected.metricColumn, 3)
        XCTAssertEqual(corrected.groupBy, [2]); XCTAssertEqual(corrected.limit, 2); XCTAssertEqual(corrected.sort, .descending)
        XCTAssertTrue(try result(corrected, s).answer.contains("40.4"))
    }

    func testAggregateFollowupRetainsRowsWithBlankOrTextMeasure() throws {
        let s = try snapshot()
        var sum = query(.sum, s, filters: [germany])
        let total = try result(sum, s)
        XCTAssertEqual(total.rows, [2, 3, 5])
        XCTAssertEqual(total.scopeRows, [2, 3, 5, 6, 7])
        sum.resultScope = .init(revision: s.revision, rows: total.scopeRows!)
        let context = ExcelAIReadQueryContext(request: "그중 제품 몇 종류야?", snapshot: s, history: [.init(role: "assistant", text: total.answer, query: sum)])
        let unique = try result(context.resolved(query(.distinctCount, s, metric: 2)), s)
        XCTAssertTrue(unique.answer.contains(": 3"))
    }

    func testCurrencyUsesSourcePrecisionAndGroupingSeparators() throws {
        let s = try snapshot { book in
            book.styles[0].numberFormatID = 44; book.styles[0].numberFormatCode = "\"$\"#,##0.00"
            for row in [2, 3, 4, 5, 8] { book.sheets[0].cells[.init(row: row, column: 3)]?.styleIndex = 0 }
            book.sheets[0].cells[ExcelCellAddress("C2")!]?.rawValue = "10000.1"
        }
        XCTAssertTrue(try result(query(.sum, s), s).answer.contains("$10,075.85"))
    }
    func testMixedCurrenciesCannotBeSummedOrRankedTogether() throws {
        let s = try snapshot { book in
            var dollars = ExcelCellStyle.plain; dollars.numberFormatCode = "\"$\"#,##0.00"
            var euros = ExcelCellStyle.plain; euros.numberFormatCode = "\"€\"#,##0.00"
            book.styles = [dollars, euros]
            book.sheets[0].cells[ExcelCellAddress("C2")!]?.styleIndex = 0
            book.sheets[0].cells[ExcelCellAddress("C3")!]?.styleIndex = 1
        }
        XCTAssertThrowsError(try ExcelAIReadQueryExecutor.execute(query(.sum, s), snapshot: s))
        XCTAssertThrowsError(try ExcelAIReadQueryExecutor.execute(query(.rank, s, sort: .descending, limit: 1), snapshot: s))
    }

}
