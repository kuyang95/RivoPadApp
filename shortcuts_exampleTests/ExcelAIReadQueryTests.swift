import RivoDocumentEngine
import XCTest
@testable import shortcuts_example

@MainActor
final class ExcelAIReadQueryTests: XCTestCase {
    private func workbook() throws -> ExcelWorkbook {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "01_Financial_Sample", withExtension: "xlsx", subdirectory: "InternetWorkbookFixtures")
            ?? bundle.url(forResource: "01_Financial_Sample", withExtension: "xlsx"))
        return try ExcelWorkbookDocument.load(from: Data(contentsOf: url))
    }

    private func snapshot(_ workbook: ExcelWorkbook) throws -> ExcelAIWorkbookSnapshot {
        try XCTUnwrap(ExcelAISnapshotBuilder.make(workbookName: "Query regression", workbook: workbook,
            selectedSheetIndex: 0, selectedAddress: ExcelCellAddress("A3")))
    }

    private func query(_ snapshot: ExcelAIWorkbookSnapshot, value: String = "888",
                       comparison: ExcelAIReadQuery.Filter.Comparison = .equals,
                       operation: ExcelAIReadQuery.Operation = .rows,
                       extra: [ExcelAIReadQuery.Filter] = []) throws -> ExcelAIReadQuery {
        ExcelAIReadQuery(operation: operation, regionID: try XCTUnwrap(snapshot.regions.first).id,
            match: .all, filters: [.init(column: 5, comparison: comparison, valueType: .number, value: value)] + extra,
            selectColumns: operation == .rows ? [3] : [])
    }

    func testFullSheetLookupReturnsThreeProductsAndOnlyTheirEvidence() throws {
        let snapshot = try snapshot(workbook())
        XCTAssertTrue(snapshot.contextWasTruncated)
        XCTAssertFalse(snapshot.cells.contains { $0.address == "C660" })
        let query = try query(snapshot)
        let result = try XCTUnwrap(ExcelAIReadQueryExecutor.execute(query, snapshot: snapshot))
        XCTAssertEqual(result.rows, [5, 43, 660])
        XCTAssertEqual(result.references?.addresses.map(\.reference), ["C5", "E5", "C43", "E43", "C660", "E660"])
        for product in ["Carretera", "VTT", "Amarilla"] { XCTAssertTrue(result.answer.contains(product)) }
        XCTAssertFalse(result.answer.contains("Paseo"))
        XCTAssertFalse(result.answer.contains("Low"))
        let chat = ExcelAIChatViewModel()
        let incorrect = ExcelAICommandPlan(intent: .answer, assistantMessage: "Paseo Low 10건",
            edits: [], appendedRows: [], referencedCells: ["A1"], countGroupID: "invented", query: query)
        try chat.handle(incorrect, snapshot: snapshot, userRequest: "Units Sold 가 888인 제품 있어?") { _ in
            XCTFail("A lookup must not mutate cells"); return ""
        }
        XCTAssertEqual(chat.messages.last?.text, result.answer)
        XCTAssertEqual(chat.activeReferences, result.references)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        XCTAssertNil(encoded["localQuerySheet"])
        XCTAssertEqual(encoded["supportsLocalQueries"] as? Bool, true)
        XCTAssertEqual((encoded["cells"] as? [Any])?.count, 1_500)
    }

    func testCompoundConditionsAndNoMatchHaveExactReferences() throws {
        let snapshot = try snapshot(workbook())
        let country = ExcelAIReadQuery.Filter(column: 2, comparison: .equals, valueType: .text, value: "Canada")
        let result = try XCTUnwrap(ExcelAIReadQueryExecutor.execute(query(snapshot, extra: [country]), snapshot: snapshot))
        XCTAssertEqual(result.rows, [660])
        XCTAssertEqual(result.references?.addresses.map(\.reference), ["B660", "C660", "E660"])
        let count = try XCTUnwrap(ExcelAIReadQueryExecutor.execute(query(snapshot, operation: .count, extra: [country]), snapshot: snapshot))
        XCTAssertEqual(count.rows, [660])
        XCTAssertEqual(count.references?.addresses.map(\.reference), ["B660", "E660"])
        XCTAssertFalse(count.answer.contains("Amarilla"))
        let empty = try XCTUnwrap(ExcelAIReadQueryExecutor.execute(query(snapshot, value: "-9000000"), snapshot: snapshot))
        XCTAssertTrue(empty.rows.isEmpty)
        XCTAssertNil(empty.references)
    }

    func testNumbersUseStoredPrecisionAndRespectComparisonBoundaries() throws {
        var workbook = try workbook()
        let address = try XCTUnwrap(ExcelCellAddress("E5"))
        workbook.sheets[0].cells[address]?.rawValue = "888.4"
        workbook.sheets[0].cells[address]?.displayValue = "888"
        let snapshot = try snapshot(workbook)
        let equal = try XCTUnwrap(ExcelAIReadQueryExecutor.execute(query(snapshot), snapshot: snapshot))
        XCTAssertEqual(equal.rows, [43, 660])
        let upper = ExcelAIReadQuery.Filter(column: 5, comparison: .lessThan, valueType: .number, value: "889")
        let greater = try XCTUnwrap(ExcelAIReadQueryExecutor.execute(query(snapshot, comparison: .greaterThan, extra: [upper]), snapshot: snapshot))
        XCTAssertEqual(greater.rows, [5])
        let inclusive = try XCTUnwrap(ExcelAIReadQueryExecutor.execute(query(snapshot, comparison: .greaterThanOrEqual, extra: [upper]), snapshot: snapshot))
        XCTAssertEqual(inclusive.rows, [5, 43, 660])
    }

    func testChangedHeadersNumbersAndProductNamesAreReadFromWorkbook() throws {
        var workbook = try workbook()
        for (reference, value) in [("E1", "재고수량Z"), ("C1", "품목명Z"), ("E660", "913.75"), ("C660", "검증상품Q7")] {
            let address = try XCTUnwrap(ExcelCellAddress(reference))
            workbook.sheets[0].cells[address]?.rawValue = value
            workbook.sheets[0].cells[address]?.displayValue = value
        }
        let snapshot = try snapshot(workbook)
        let result = try XCTUnwrap(ExcelAIReadQueryExecutor.execute(query(snapshot, value: "913.75"), snapshot: snapshot))
        XCTAssertEqual(result.rows, [660])
        XCTAssertTrue(result.answer.contains("재고수량Z"))
        XCTAssertTrue(result.answer.contains("품목명Z: 검증상품Q7"))
        XCTAssertFalse(result.answer.contains("Amarilla"))
    }

    func testInvalidQueriesAndIncompleteSheetsDoNotPublishUnverifiedAnswers() throws {
        var snapshot = try snapshot(workbook())
        let original = try query(snapshot)
        let invalid = ExcelAIReadQuery(operation: .rows, regionID: original.regionID, match: .all,
            filters: original.filters, selectColumns: [99])
        XCTAssertThrowsError(try ExcelAIReadQueryExecutor.execute(invalid, snapshot: snapshot))
        XCTAssertThrowsError(try ExcelAIReadQueryExecutor.execute(query(snapshot, value: "888 units"), snapshot: snapshot))
        snapshot.supportsLocalQueries = false
        let chat = ExcelAIChatViewModel()
        XCTAssertThrowsError(try chat.handle(ExcelAICommandPlan(intent: .answer, assistantMessage: "Paseo 10건",
            edits: [], appendedRows: [], query: original), snapshot: snapshot) { _ in "" })
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertNil(chat.activeReferences)
    }

    func testDisplayLimitDoesNotLimitCountOrHighlights() throws {
        let snapshot = try snapshot(workbook())
        let result = try XCTUnwrap(ExcelAIReadQueryExecutor.execute(query(snapshot, value: "0", comparison: .greaterThan), snapshot: snapshot))
        XCTAssertEqual(result.rows.count, 700)
        XCTAssertEqual(result.references?.addresses.count, 1_400)
        XCTAssertLessThan(result.answer.components(separatedBy: "\n").count, 24)
        XCTAssertTrue(result.answer.contains("700"))
    }

    func testLiveReadPlannerPreservesTheEditRoute() async throws {
        guard ProcessInfo.processInfo.environment["EXCEL_AI_REFERENCE_LIVE"] == "1" else {
            throw XCTSkip("Enable the explicit live model regression run")
        }
        FirebaseRuntime.configureIfAvailable()
        var workbook = try workbook()
        // A small copy keeps this intent regression independent of large-context
        // limits. The user's workbook and its cells are never modified.
        workbook.sheets[0].cells = workbook.sheets[0].cells.filter { $0.key.row <= 6 }
        let snapshot = try snapshot(workbook)
        let request = "E5 셀 값을 889로 바꿔줘"
        let command = try await ExcelAICommandService.plan(userRequest: request, snapshot: snapshot, history: [])
        XCTAssertEqual(command.intent, .edit)
        let plan = try XCTUnwrap(ExcelAICommandValidator.validate(command, snapshot: snapshot, userRequest: request))
        XCTAssertEqual(plan.edits, [.init(row: 5, column: 5, newValue: "889")])
        XCTAssertTrue(plan.appendedRows.isEmpty)
        XCTAssertTrue(plan.actions.isEmpty)
        print("EXCEL_QUERY_LIVE_EDIT verified=E5 newValue=889")
    }

    func testFollowupKeepsVerifiedConditionsAndNewQuestionDropsOldHistory() throws {
        let snapshot = try snapshot(workbook())
        let original = try query(snapshot, value: "3000", comparison: .greaterThanOrEqual)
        let history = [ExcelAIChatTurn(role: "assistant", text: "제품 목록은 생략했습니다.", query: original)]
        let followup = ExcelAIReadQueryContext(request: "그중 Country가 Canada인 것만 보여줘", snapshot: snapshot, history: history)
        XCTAssertEqual(followup.queryScope, "previousResult")
        XCTAssertTrue(followup.recentConversation.isEmpty)
        let additional = ExcelAIReadQuery(operation: .rows, regionID: original.regionID, match: .all,
            filters: [.init(column: 2, comparison: .equals, valueType: .text, value: "Canada")], selectColumns: [3])
        let result = try XCTUnwrap(ExcelAIReadQueryExecutor.execute(followup.resolved(additional), snapshot: snapshot))
        XCTAssertEqual(result.rows.count, 7)
        XCTAssertEqual(result.references?.addresses.count, 21)
        for row in result.rows {
            let sheet = try XCTUnwrap(snapshot.localQuerySheet)
            XCTAssertEqual(sheet.cell(at: ExcelCellAddress(row: row, column: 2))?.rawValue, "Canada")
            XCTAssertGreaterThanOrEqual(Double(sheet.cell(at: ExcelCellAddress(row: row, column: 5))?.rawValue ?? "") ?? 0, 3000)
        }
        let standalone = ExcelAIReadQueryContext(request: "Country가 Canada인 제품 알려줘", snapshot: snapshot, history: history)
        XCTAssertEqual(standalone.queryScope, "worksheet")
        XCTAssertNil(standalone.previousQuery)
        XCTAssertTrue(standalone.recentConversation.isEmpty)
        let allCanada = try XCTUnwrap(ExcelAIReadQueryExecutor.execute(standalone.resolved(additional), snapshot: snapshot))
        XCTAssertEqual(allCanada.rows.count, 140)
        let afterThanks = ExcelAIReadQueryContext(request: "그중 Country가 Canada인 것만 보여줘", snapshot: snapshot,
            history: history + [.init(role: "user", text: "고마워"), .init(role: "assistant", text: "네")])
        XCTAssertEqual(try ExcelAIReadQueryExecutor.execute(afterThanks.resolved(additional), snapshot: snapshot)?.rows, result.rows)
    }

    func testExplicitNumericComparisonsOverrideAnIncorrectModelOperator() throws {
        let snapshot = try snapshot(workbook())
        let cases: [(String, String, ExcelAIReadQuery.Filter.Comparison)] = [
            ("Units Sold가 888이고 Country가 Canada인 제품 알려줘", "888", .equals),
            ("Units Sold가 913.75인 제품 알려줘", "913.75", .equals),
            ("Units Sold가 3,000 이상인 제품 알려줘", "3000", .greaterThanOrEqual),
            ("Units Sold가 3000 초과인 제품 알려줘", "3000", .greaterThan),
            ("Units Sold가 3000 이하인 제품 알려줘", "3000", .lessThanOrEqual),
            ("Units Sold가 3000 미만인 제품 알려줘", "3000", .lessThan),
            ("Units Sold >= 12.5인 제품 알려줘", "12.5", .greaterThanOrEqual),
            ("Units Sold != 12.5인 제품 알려줘", "12.5", .notEqual),
        ]
        for (request, value, expected) in cases {
            let context = ExcelAIReadQueryContext(request: request, snapshot: snapshot, history: [])
            let proposed = try query(snapshot, value: value, comparison: expected == .equals ? .greaterThanOrEqual : .equals)
            XCTAssertEqual(try context.resolved(proposed).filters.first?.comparison, expected, request)
        }
    }

    func testLiveModelPlansLookupFromConditionsInsteadOfInventingResults() async throws {
        guard ProcessInfo.processInfo.environment["EXCEL_AI_REFERENCE_LIVE"] == "1" else {
            throw XCTSkip("Enable the explicit live model regression run")
        }
        FirebaseRuntime.configureIfAvailable()
        let original = try workbook()
        var changed = original
        for (reference, value) in [("E1", "재고수량Z"), ("C1", "품목명Z"), ("E660", "913.75"), ("C660", "검증상품Q7")] {
            let address = try XCTUnwrap(ExcelCellAddress(reference))
            changed.sheets[0].cells[address]?.rawValue = value
            changed.sheets[0].cells[address]?.displayValue = value
        }
        let cases: [(String, ExcelWorkbook, [Int])] = [
            ("Units Sold 가 888인 제품 있어?", original, [5, 43, 660]),
            ("Units Sold가 888이고 Country가 Canada인 제품 알려줘", original, [660]),
            ("Units Sold가 -9000000인 제품 있어?", original, []),
            ("재고수량Z가 913.75인 품목명Z 알려줘", changed, [660]),
        ]
        for (request, workbook, rows) in cases {
            let snapshot = try snapshot(workbook)
            let command = try await ExcelAICommandService.plan(userRequest: request, snapshot: snapshot,
                history: [.init(role: "user", text: "독일 총 몇개야"), .init(role: "assistant", text: "Germany 항목은 총 140개입니다.")])
            XCTAssertEqual(command.intent, .answer, request)
            let query = try XCTUnwrap(command.query, request)
            XCTAssertEqual(query.operation, .rows, request)
            XCTAssertEqual(query.selectColumns, [3], request)
            let result = try XCTUnwrap(ExcelAIReadQueryExecutor.execute(query, snapshot: snapshot), request)
            XCTAssertEqual(result.rows, rows, request)
            let chat = ExcelAIChatViewModel()
            try chat.handle(command, snapshot: snapshot, userRequest: request) { _ in
                XCTFail("Read only"); return ""
            }
            XCTAssertEqual(chat.messages.last?.text, result.answer, request)
            XCTAssertEqual(chat.activeReferences, result.references, request)
            print("EXCEL_QUERY_LIVE request=\(request) rows=\(result.rows) answer=\(result.answer)")
        }
    }
}
