import RivoDocumentEngine
import Combine
import SwiftUI
import UIKit
import XCTest
@testable import shortcuts_example

/// Live conversations through send -> snapshot -> model -> validation/apply ->
/// references -> the actual grid. Expected cells are independent of AI plans.
@MainActor
final class ExcelAIChatHighlightAuditTests: XCTestCase {
    private struct Entry: Encodable {
        let request: String
        let answer: String
        let expectedRows: [Int]
        let expectedCells: [String]
        let actualCells: [String]
        let passed: Bool
    }
    private var entries: [Entry] = []
    private static var budgetWasRefilled = false

    private func enableLive() async throws {
        guard ProcessInfo.processInfo.environment["EXCEL_AI_CHAT_AUDIT"] == "1" else {
            throw XCTSkip("Opt-in live chat and visual audit")
        }
        FirebaseRuntime.configureIfAvailable()
        #if DEBUG
        if ProcessInfo.processInfo.environment["EXCEL_AI_CHAT_AUDIT_REFILL_AUTHORIZED"] == "1", !Self.budgetWasRefilled {
            await CloudAITokenBudgetStore.shared.refillForTesting()
            Self.budgetWasRefilled = true
        }
        #endif
        print("EXCEL_CHAT_AUDIT availableTokens=\(await CloudAITokenBudgetStore.shared.availableTokens())")
    }

    private func model(data: Data) async throws -> ExcelWorkbookViewModel {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ChatHighlightAudit-\(UUID()).xlsx")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let model = ExcelWorkbookViewModel(fileURL: url)
        await model.load()
        XCTAssertNotNil(model.workbook)
        model.selectCell(try XCTUnwrap(ExcelCellAddress("A2")))
        return model
    }

    private func evidence(rows: [Int], columns: [Int]) -> Set<ExcelCellAddress> {
        Set(rows.flatMap { row in columns.map { ExcelCellAddress(row: row, column: $0) } })
    }

    @discardableResult
    private func send(_ request: String, rows: [Int], columns: [Int],
                      chat: ExcelAIChatViewModel, model: ExcelWorkbookViewModel,
                      editing: Bool = false) async throws -> Bool {
        let expected = evidence(rows: rows, columns: columns)
        let before = try XCTUnwrap(model.makeAISnapshot())
        let selected = model.selectedAddress
        let previousCount = chat.messages.count
        chat.input = request
        await chat.send(snapshotProvider: { try await model.makeAISnapshot(for: $0) },
                        applying: { try model.applyAIPlan($0) })
        let newMessages = chat.messages.dropFirst(previousCount)
        if newMessages.contains(where: { $0.role == .notice && $0.text.contains("100만 토큰") }) {
            throw XCTSkip("Live chat audit stopped at the app's daily AI limit; remaining conversations were not verified.")
        }
        let answer = newMessages.last(where: { $0.role == .assistant })?.text
        let actual = Set(chat.activeReferences?.addresses ?? [])
        let passed = answer != nil && actual == expected && model.aiHighlightedAddresses == expected
        entries.append(Entry(request: request, answer: answer ?? newMessages.map(\.text).joined(separator: "\n"),
            expectedRows: rows, expectedCells: expected.sorted().map(\.reference),
            actualCells: actual.sorted().map(\.reference), passed: passed))
        print("EXCEL_CHAT_AUDIT passed=\(passed) request=\(request) expectedRows=\(rows.count) expectedCells=\(expected.count) actualCells=\(actual.count) answer=\(answer ?? "NO ANSWER")")
        XCTAssertNotNil(answer, request + " " + newMessages.map(\.text).joined(separator: " "))
        XCTAssertEqual(actual, expected, request)
        XCTAssertEqual(model.aiHighlightedAddresses, expected, request)
        XCTAssertFalse(chat.isSending)
        if !editing {
            XCTAssertEqual(model.makeAISnapshot()?.revision, before.revision, "Read-only chat changed cells: \(request)")
            XCTAssertEqual(model.selectedAddress, selected, "Reference must preserve the blue selection")
        }
        if !expected.isEmpty {
            XCTAssertEqual(chat.activeReferences?.sheetPartPath, model.selectedSheet?.partPath)
            XCTAssertEqual(model.aiReferenceAddress, expected.sorted().first)
        }
        return passed
    }

    private func attachReport(_ name: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFinancialConversationsAndOffscreenReferences() async throws {
        try await enableLive()
        defer { attachReport("financial-chat-audit.json") }
        let bundle = Bundle(for: Self.self)
        let source = try XCTUnwrap(bundle.url(forResource: "01_Financial_Sample", withExtension: "xlsx", subdirectory: "InternetWorkbookFixtures")
            ?? bundle.url(forResource: "01_Financial_Sample", withExtension: "xlsx"))
        let model = try await model(data: Data(contentsOf: source))
        let chat = ExcelAIChatViewModel()
        let connection = chat.$activeReferences.sink { model.showAIReferences($0) }
        defer { connection.cancel() }
        let sheet = try XCTUnwrap(model.selectedSheet)
        func value(_ row: Int, _ column: Int) -> String {
            sheet.cell(at: ExcelCellAddress(row: row, column: column))?.rawValue ?? ""
        }
        let dataRows = Array(2...701)
        let france = dataRows.filter { value($0, 2) == "France" }
        try await send("프랑스 항목은 모두 몇 건이야?", rows: france, columns: [2], chat: chat, model: model)
        let paseo = dataRows.filter { value($0, 3) == "Paseo" }
        try await send("Paseo 총 몇개야?", rows: paseo, columns: [3], chat: chat, model: model)
        let highUnits = dataRows.filter { (Double(value($0, 5)) ?? -.infinity) >= 3000 }
        try await send("Units Sold가 3000 이상인 제품 알려줘", rows: highUnits, columns: [3, 5], chat: chat, model: model)
        let canadaHighUnits = highUnits.filter { value($0, 2) == "Canada" }
        try await send("그중 Country가 Canada인 것만 보여줘", rows: canadaHighUnits, columns: [2, 3, 5], chat: chat, model: model)
        let eitherCountry = dataRows.filter { ["France", "Mexico"].contains(value($0, 2)) }
        try await send("이번에는 Country가 France 또는 Mexico인 행은 몇 건이야?", rows: eitherCountry, columns: [2], chat: chat, model: model)
        let discounted = dataRows.filter { value($0, 2) == "Canada" && value($0, 4) == "High" }
        let passed = try await send("Country가 Canada이고 Discount Band가 High인 제품 알려줘", rows: discounted, columns: [2, 3, 4], chat: chat, model: model)
        if passed {
            model.moveAIReference(by: model.aiHighlightedAddresses.count - 1)
            XCTAssertGreaterThan(try XCTUnwrap(model.aiReferenceAddress).row, 400)
            try await render(model: model, chat: chat, name: "financial-last-reference", reveal: true)
        }
    }

    private func inventoryData() throws -> Data {
        let rows = [
            ["품목", "창고", "재고", "단가", "상태"],
            ["노트A", "서울", "12", "1500", "판매중"],
            ["펜B", "부산", "5", "800", "판매중"],
            ["파일C", "서울", "0", "2200", "품절"],
            ["클립D", "대전", "5", "500", "판매중"],
            ["테이프E", "부산", "12", "1500", "판매중"],
            ["가위F", "서울", "2", "4000", "단종"],
            ["자G", "대전", "5", "900", "판매중"],
            ["봉투H", "부산", "0", "300", "품절"],
        ]
        let data = try ExcelWorkbookDocument.blankWorkbookData(sheetName: "재고 검증")
        let workbook = try ExcelWorkbookDocument.load(from: data)
        var cells: [ExcelCellAddress: ExcelCellEdit] = [:]
        for (row, values) in rows.enumerated() {
            for (column, value) in values.enumerated() {
                cells[ExcelCellAddress(row: row + 1, column: column + 1)] = .init(input: .init(userText: value), styleIndex: nil)
            }
        }
        return try ExcelWorkbookDocument.applying([.init(partPath: workbook.sheets[0].partPath, cells: cells)], to: data, workbook: workbook)
    }

    func testInventoryFollowupsNoResultsConversationAndActualEdit() async throws {
        try await enableLive()
        defer { attachReport("inventory-chat-audit.json") }
        let model = try await model(data: inventoryData())
        let chat = ExcelAIChatViewModel()
        let connection = chat.$activeReferences.sink { model.showAIReferences($0) }
        defer { connection.cancel() }
        let first = try await send("재고가 5인 품목 알려줘", rows: [3, 5, 8], columns: [1, 3], chat: chat, model: model)
        if first {
            try await render(model: model, chat: chat, name: "inventory-stock-five-light")
            try await render(model: model, chat: chat, name: "inventory-stock-five-dark", dark: true)
        }
        try await send("그중 부산 창고에 있는 것만 보여줘", rows: [3], columns: [1, 2, 3], chat: chat, model: model)
        try await send("단가가 1000원 미만인 품목 보여줘", rows: [3, 5, 8, 9], columns: [1, 4], chat: chat, model: model)
        try await send("재고가 0인 품목은 몇 행이야?", rows: [4, 9], columns: [3], chat: chat, model: model)
        let empty = try await send("재고가 -1인 품목 있어?", rows: [], columns: [], chat: chat, model: model)
        if empty { try await render(model: model, chat: chat, name: "inventory-no-match-clears-purple") }
        try await send("판매중 항목은 몇개야?", rows: [2, 3, 5, 6, 8], columns: [5], chat: chat, model: model)
        try await send("고마워", rows: [], columns: [], chat: chat, model: model)
        try await send("그중 부산 창고에 있는 건 몇 행이야?", rows: [3, 6], columns: [2, 5], chat: chat, model: model)
        let edited = try await send("C3 셀 값을 9로 바꿔줘", rows: [3], columns: [3], chat: chat, model: model, editing: true)
        XCTAssertEqual(model.selectedSheet?.cell(at: try XCTUnwrap(ExcelCellAddress("C3")))?.rawValue, "9")
        if edited {
            model.selectCell(try XCTUnwrap(ExcelCellAddress("C3")))
            try await render(model: model, chat: chat, name: "inventory-edited-cell-purple-and-blue-selection")
        }
        try await send("재고가 9인 품목 알려줘", rows: [3], columns: [1, 3], chat: chat, model: model)
    }

    private func render(model: ExcelWorkbookViewModel, chat: ExcelAIChatViewModel,
                        name: String, dark: Bool = false, reveal: Bool = false) async throws {
        let sheet = try XCTUnwrap(model.selectedSheet)
        let workbook = try XCTUnwrap(model.workbook)
        let grid = ExcelGridView(sheet: sheet, workbook: workbook,
            regions: ExcelAccessibilityAnalyzer.regions(in: sheet), visibleRows: nil,
            selectedAddress: model.selectedAddress, onSelect: { _ in }, onEdit: { _ in },
            highlightedAddresses: model.aiHighlightedAddresses,
            revealAddress: reveal ? model.aiReferenceAddress : nil)
        let view = VStack(alignment: .leading, spacing: 12) {
            Text(chat.messages.last(where: { $0.role == .user })?.text ?? name).font(.headline)
            grid.frame(height: 450)
            Text(chat.messages.last(where: { $0.role == .assistant })?.text ?? "").font(.body).lineLimit(7)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 1_000, height: 740, alignment: .topLeading)
        .background(VisionCraftUI.surface)
        .preferredColorScheme(dark ? .dark : .light)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1_000, height: 740)
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(450))
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 5_000)
    }
}
