import XCTest
@testable import shortcuts_example

@MainActor
final class ExcelAIAggregationChatTests: XCTestCase {
    private func snapshot() throws -> ExcelAIWorkbookSnapshot {
        let blank = try ExcelWorkbookDocument.blankWorkbookData(), book = try ExcelWorkbookDocument.load(from: blank)
        var cells: [ExcelCellAddress: ExcelCellEdit] = [:]
        let values = [["Country", "Product", "Sales"], ["Germany", "A", "10"], ["Germany", "B", "30"], ["Germany", "C", "20"], ["France", "D", "100"]]
        for (r, row) in values.enumerated() { for (c, value) in row.enumerated() {
            cells[.init(row: r + 1, column: c + 1)] = .init(input: r > 0 && c == 2 ? .number(value) : .text(value), styleIndex: nil)
        }}
        let loaded = try ExcelWorkbookDocument.load(from: ExcelWorkbookDocument.applying([.init(partPath: book.sheets[0].partPath, cells: cells)], to: blank, workbook: book))
        return try XCTUnwrap(ExcelAISnapshotBuilder.make(workbookName: "Chat", workbook: loaded, selectedSheetIndex: 0, selectedAddress: ExcelCellAddress("A2")))
    }
    func testChatUsesCalculatedAnswerAndExactPriorRankScope() throws {
        let s = try snapshot(), chat = ExcelAIChatViewModel()
        let top = ExcelAIReadQuery(operation: .rank, regionID: s.regions[0].id, match: .all,
            filters: [.init(column: 1, comparison: .equals, valueType: .text, value: "Germany")], selectColumns: [2], metricColumn: 3, sort: .descending, limit: 2)
        try chat.handle(.init(intent: .answer, assistantMessage: "MODEL WRONG 99999", edits: [], appendedRows: [], referencedCells: ["C5"], query: top), snapshot: s) { _ in XCTFail("Must not edit"); return "" }
        XCTAssertFalse(chat.messages.last!.text.contains("99999"))
        XCTAssertEqual(chat.activeReferences?.addresses.map(\.reference), ["A3", "B3", "C3", "A4", "B4", "C4"])
        let previous = try XCTUnwrap(chat.messages.last?.query)
        XCTAssertEqual(previous.resultScope?.rows, [3, 4])
        let context = ExcelAIReadQueryContext(request: "그중 합계는?", snapshot: s, history: [.init(role: "assistant", text: chat.messages.last!.text, query: previous)])
        let sum = try context.resolved(.init(operation: .sum, regionID: s.regions[0].id, match: .all, filters: [], selectColumns: [], metricColumn: 3))
        try chat.handle(.init(intent: .answer, assistantMessage: "WRONG", edits: [], appendedRows: [], query: sum), snapshot: s) { _ in XCTFail("Must not edit"); return "" }
        XCTAssertTrue(chat.messages.last!.text.contains(": 50")); XCTAssertFalse(chat.messages.last!.text.contains(": 160"))
        XCTAssertEqual(chat.activeReferences?.addresses.map(\.reference), ["C3", "C4"])
    }
    func testFailedCalculationDoesNotPublishModelSuccessOrReferences() throws {
        var s = try snapshot(); s.localQuerySheet?.cells[ExcelCellAddress("C2")!]?.cellType = "e"
        let chat = ExcelAIChatViewModel()
        let sum = ExcelAIReadQuery(operation: .sum, regionID: s.regions[0].id, match: .all, filters: [], selectColumns: [], metricColumn: 3)
        XCTAssertThrowsError(try chat.handle(.init(intent: .answer, assistantMessage: "합계는 160", edits: [], appendedRows: [], query: sum), snapshot: s) { _ in "" })
        XCTAssertTrue(chat.messages.isEmpty); XCTAssertNil(chat.activeReferences)
    }
    func testMicrosoftSampleUsesAllGermanyRowsAndCurrencyDisplay() throws {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "01_Financial_Sample", withExtension: "xlsx", subdirectory: "InternetWorkbookFixtures") ?? bundle.url(forResource: "01_Financial_Sample", withExtension: "xlsx"))
        let book = try ExcelWorkbookDocument.load(from: Data(contentsOf: url))
        let s = try XCTUnwrap(ExcelAISnapshotBuilder.make(workbookName: "Microsoft", workbook: book, selectedSheetIndex: 0, selectedAddress: ExcelCellAddress("A2")))
        let region = try XCTUnwrap(s.regions.first)
        let sum = ExcelAIReadQuery(operation: .sum, regionID: region.id, match: .all,
            filters: [.init(column: 2, comparison: .equals, valueType: .text, value: "Germany")], selectColumns: [], metricColumn: 10)
        let result = try XCTUnwrap(ExcelAIReadQueryExecutor.execute(sum, snapshot: s))
        // Independent ZIP/XML + decimal oracle: 23505340.8199999999915, shown
        // using the source column's dollar accounting format with two decimals.
        XCTAssertEqual(result.rows.count, 140); XCTAssertTrue(result.answer.contains("$23,505,340.82"))
        XCTAssertEqual(result.references?.addresses.count, 280)
        let distinct = ExcelAIReadQuery(operation: .distinctCount, regionID: region.id, match: .all, filters: [], selectColumns: [], metricColumn: 3)
        XCTAssertTrue(try XCTUnwrap(ExcelAIReadQueryExecutor.execute(distinct, snapshot: s)).answer.contains(": 6"))
        let rank = ExcelAIReadQuery(operation: .rank, regionID: region.id, match: .all, filters: [], selectColumns: [3], metricColumn: 10, sort: .descending, limit: 1)
        XCTAssertEqual(try ExcelAIReadQueryExecutor.execute(rank, snapshot: s)?.rows, [194])
    }

}
