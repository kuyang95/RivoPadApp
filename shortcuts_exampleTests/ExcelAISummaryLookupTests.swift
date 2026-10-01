import XCTest
@testable import shortcuts_example

@MainActor
final class ExcelAISummaryLookupTests: XCTestCase {
    private func workbook() throws -> ExcelWorkbook {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "AuthorMeetingBudget", withExtension: "xlsx",
                                          subdirectory: "InternetWorkbookFixtures")
            ?? bundle.url(forResource: "AuthorMeetingBudget", withExtension: "xlsx"))
        return try ExcelWorkbookDocument.load(from: Data(contentsOf: url))
    }
    private func snapshot(_ workbook: ExcelWorkbook? = nil) throws -> ExcelAIWorkbookSnapshot {
        try XCTUnwrap(ExcelAISnapshotBuilder.make(workbookName: "작가와의만남_예산",
            workbook: try workbook ?? self.workbook(), selectedSheetIndex: 0, selectedAddress: ExcelCellAddress("A5")))
    }

    func testSourceContainsExactValuesFormulaAndNoInferredSummaries() throws {
        let snapshot = try snapshot()
        let source = ExcelAISourceData(snapshot: snapshot)
        XCTAssertFalse(source.contextWasTruncated)
        XCTAssertEqual(source.cells.count, snapshot.localQuerySheet?.cells.values.filter { !$0.displayValue.isEmpty || $0.formula?.isEmpty == false }.count)
        XCTAssertEqual(source.cells.first { $0.address == "A5" }?.value, "사용 가능 예산")
        XCTAssertEqual(source.cells.first { $0.address == "B5" }?.value, "300,000")
        XCTAssertEqual(source.cells.first { $0.address == "B5" }?.rawValue, "300000")
        XCTAssertEqual(source.cells.first { $0.address == "B7" }?.formula, "B5-B6")
        let json = String(decoding: try JSONEncoder().encode(ExcelAIModelWorksheet(snapshot: snapshot, source: source)), as: UTF8.self)
        for invented in ["summaryEntries", "exampleValues", "valueGroups", "storageTypes"] {
            XCTAssertFalse(json.contains(invented), invented)
        }
        XCTAssertTrue(source.regions.filter { !$0.isNativeTable }.flatMap(\.columns).allSatisfy { $0.title == nil })
        XCTAssertNil(ExcelAILocalReadPlanner.query(in: snapshot, request: "사용가능예산 얼마야?"))
    }

    func testSourceKeepsMoreThan256CellsAndNeverSplitsRowsAtLimit() throws {
        var book = try workbook()
        book.sheets[0].cells = [:]
        for row in 1...501 {
            for column in 1...3 {
                let address = ExcelCellAddress(row: row, column: column)
                book.sheets[0].cells[address] = .init(address: address, rawValue: "  원문\n\(row),\(column)  ",
                    displayValue: "  원문\n\(row),\(column)  ", formula: nil, styleIndex: nil, cellType: "inlineStr")
            }
        }
        let source = ExcelAISourceData(snapshot: try snapshot(book))
        XCTAssertTrue(source.contextWasTruncated)
        XCTAssertEqual(source.cells.count, 1500)
        XCTAssertEqual(source.cells.first?.value, "  원문\n1,1  ")
        XCTAssertTrue(Dictionary(grouping: source.cells, by: { ExcelCellAddress($0.address)!.row }).values.allSatisfy { $0.count == 3 })
    }

    func testLiveSourceAnswersThroughActualChatWithoutLookupShortcut() async throws {
        guard ProcessInfo.processInfo.environment["EXCEL_AI_REFERENCE_LIVE"] == "1" else {
            throw XCTSkip("Enable the explicit live model regression run")
        }
        FirebaseRuntime.configureIfAvailable()
        let original = try snapshot()
        for (request, value, evidence) in [
            ("사용가능예산 얼마야?", "300,000", "B5"),
            ("이 행사에서 쓸 수 있도록 잡아 둔 예산이 얼마인지 알려줘", "300,000", "B5"),
            ("예산 잔액 얼마야?", "82,800", "B7")
        ] {
            let chat = ExcelAIChatViewModel()
            chat.input = request
            await chat.send(snapshotProvider: { _ in original }, applying: { _ in
                XCTFail("A question must not edit the document"); return ""
            })
            let answer = try XCTUnwrap(chat.messages.last)
            print("SOURCE_ANSWER \(request) → \(answer.text)")
            XCTAssertEqual(answer.role, .assistant, answer.text)
            XCTAssertTrue(answer.text.contains(value), answer.text)
            XCTAssertTrue(chat.activeReferences?.addresses.map(\.reference).contains(evidence) == true, answer.text)
        }
        var book = try workbook()
        book.sheets[0].cells[ExcelCellAddress("A5")!]?.displayValue = "행사 지원금"
        book.sheets[0].cells[ExcelCellAddress("A5")!]?.rawValue = "행사 지원금"
        book.sheets[0].cells[ExcelCellAddress("B5")!]?.displayValue = "456,789"
        book.sheets[0].cells[ExcelCellAddress("B5")!]?.rawValue = "456789"
        let changed = try snapshot(book)
        let plan = try await ExcelAICommandService.plan(userRequest: "행사지원금 얼마야?", snapshot: changed, history: [])
        let answer = try ExcelAIReferences.answerText(command: plan, snapshot: changed)
        XCTAssertTrue(answer.contains("456,789"), answer)
        XCTAssertFalse(answer.contains("300,000"), answer)
    }
}
