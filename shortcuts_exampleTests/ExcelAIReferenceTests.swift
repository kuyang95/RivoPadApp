import SwiftUI
import UIKit
import XCTest
@testable import shortcuts_example

@MainActor
final class ExcelAIReferenceTests: XCTestCase {
    private func financialURL() throws -> URL {
        let bundle = Bundle(for: Self.self)
        return try XCTUnwrap(bundle.url(forResource: "01_Financial_Sample", withExtension: "xlsx", subdirectory: "InternetWorkbookFixtures")
            ?? bundle.url(forResource: "01_Financial_Sample", withExtension: "xlsx"))
    }

    private func financialWorkbook() throws -> ExcelWorkbook {
        try ExcelWorkbookDocument.load(from: Data(contentsOf: financialURL()))
    }

    private func snapshot(_ workbook: ExcelWorkbook) throws -> ExcelAIWorkbookSnapshot {
        try XCTUnwrap(ExcelAISnapshotBuilder.make(
            workbookName: "Microsoft 매출 이익 샘플", workbook: workbook,
            selectedSheetIndex: 0, selectedAddress: ExcelCellAddress("A3")
        ))
    }

    func testGermanyCountAndEveryReferenceSurviveTruncatedAIContext() throws {
        let workbook = try financialWorkbook()
        let snapshot = try snapshot(workbook)
        let germany = try XCTUnwrap(snapshot.valueGroups.first { $0.header == "Country" && $0.value == "Germany" })
        let expected = Set(workbook.sheets[0].cells.values.filter { $0.displayValue == "Germany" }.map(\.address))
        XCTAssertEqual(expected.count, 140)
        XCTAssertTrue(snapshot.contextWasTruncated)
        XCTAssertEqual(snapshot.cells.count, 1_500)
        XCTAssertEqual(germany.count, 140)
        XCTAssertEqual(Set(germany.addresses), expected)
        XCTAssertTrue(germany.addresses.contains(try XCTUnwrap(ExcelCellAddress("B695"))))
        XCTAssertFalse(snapshot.cells.contains { $0.address == "B695" })
        let command = ExcelAICommandPlan(
            intent: .answer, assistantMessage: "일부 행만 보고 센 잘못된 개수: 18개",
            edits: [], appendedRows: [], referencedCells: ["A1", "B1", "C1"],
            referencedGroupIDs: [germany.id], countGroupID: germany.id
        )
        let chat = ExcelAIChatViewModel()
        try chat.handle(command, snapshot: snapshot, userRequest: "독일 총 몇개야") { _ in
            XCTFail("A count question must not mutate the workbook")
            return ""
        }
        XCTAssertEqual(chat.messages.last?.text, AppLocalization.format("%@ 항목은 총 %lld개입니다.", "Germany", 140))
        XCTAssertEqual(Set(try XCTUnwrap(chat.activeReferences).addresses), expected)
        XCTAssertEqual(chat.messages.last?.references, chat.activeReferences)
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(germany), encoding: .utf8))
        XCTAssertFalse(encoded.contains("addresses"), "Full reference addresses should remain local")
    }

    func testReferenceNavigationKeepsBlueSelectionAndTargetsAllMatches() async throws {
        let workbook = try financialWorkbook()
        let snapshot = try snapshot(workbook)
        let germany = try XCTUnwrap(snapshot.valueGroups.first { $0.header == "Country" && $0.value == "Germany" })
        let refs = ExcelAIReferences(sheetPartPath: snapshot.sheetPartPath, sheetName: snapshot.sheetName, addresses: germany.addresses)
        let model = ExcelWorkbookViewModel(fileURL: try financialURL())
        await model.load()
        model.selectCell(try XCTUnwrap(ExcelCellAddress("A3")))
        model.showAIReferences(refs)
        XCTAssertEqual(model.aiHighlightedAddresses.count, 140)
        XCTAssertEqual(model.aiReferenceAddress?.reference, "B3")
        model.moveAIReference(by: 139)
        XCTAssertEqual(model.aiReferenceAddress?.reference, "B695")
        XCTAssertEqual(model.selectedAddress?.reference, "A3")
        XCTAssertFalse(model.hasUnsavedChanges)
        model.showAIReferences(nil)
        XCTAssertTrue(model.aiHighlightedAddresses.isEmpty)
    }

    func testUnknownReferencesAreIgnoredAndUnknownCountIsRejected() throws {
        let snapshot = try snapshot(financialWorkbook())
        let chat = ExcelAIChatViewModel()
        let invalid = ExcelAICommandPlan(intent: .answer, assistantMessage: "140개",
            edits: [], appendedRows: [], referencedCells: ["B3", "B900000", "Sheet2!B3"],
            referencedGroupIDs: ["invented"], countGroupID: "invented")
        XCTAssertThrowsError(try chat.handle(invalid, snapshot: snapshot) { _ in "" })
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertNil(chat.activeReferences)
        let plain = ExcelAICommandPlan(intent: .answer, assistantMessage: "확인했습니다.",
            edits: [], appendedRows: [], referencedCells: ["B3", "B900000", "Sheet2!B3"], referencedGroupIDs: ["invented"])
        try chat.handle(plain, snapshot: snapshot) { _ in "" }
        XCTAssertEqual(chat.activeReferences?.addresses.map(\.reference), ["B3"])
    }

    func testClarificationAndFailedEditDoNotPublishReferences() throws {
        let snapshot = try snapshot(financialWorkbook())
        let chat = ExcelAIChatViewModel()
        let clarification = ExcelAICommandPlan(intent: .clarify, assistantMessage: "어떤 값인가요?",
            edits: [], appendedRows: [], referencedCells: ["B3"])
        try chat.handle(clarification, snapshot: snapshot) { _ in "" }
        XCTAssertNil(chat.activeReferences)
        let edit = ExcelAICommandPlan(intent: .edit, assistantMessage: "수정했습니다.",
            edits: [.init(row: 3, column: 2, newValue: "France")], appendedRows: [])
        try chat.handle(edit, snapshot: snapshot) { _ in throw ExcelAIApplyError.staleProposal }
        XCTAssertNil(chat.activeReferences)
        try chat.handle(edit, snapshot: snapshot) { _ in "1개 셀 수정" }
        XCTAssertEqual(chat.activeReferences?.addresses.map(\.reference), ["B3"])
    }

    func testWindowedSheetDoesNotClaimCompleteValueCounts() throws {
        var workbook = try financialWorkbook()
        workbook.sheets[0].isWindowed = true
        XCTAssertTrue(try snapshot(workbook).valueGroups.isEmpty)
    }

    func testFinancialReferenceGridRendersWithOriginalSelection() async throws {
        let workbook = try financialWorkbook()
        let snapshot = try snapshot(workbook)
        let germany = try XCTUnwrap(snapshot.valueGroups.first { $0.header == "Country" && $0.value == "Germany" })
        let grid = ExcelGridView(sheet: workbook.sheets[0], workbook: workbook,
            regions: ExcelAccessibilityAnalyzer.regions(in: workbook.sheets[0]), visibleRows: nil,
            selectedAddress: ExcelCellAddress("A3"), onSelect: { _ in }, onEdit: { _ in },
            highlightedAddresses: Set(germany.addresses), revealAddress: ExcelCellAddress("B3"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1_000, height: 700)
        let host = UIHostingController(rootView: grid)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(350))
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Germany-references-and-blue-selection"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 5_000)
    }

    func testLegacyResponseStillDecodesWithoutReferences() throws {
        let data = Data(#"{"intent":"answer","assistantMessage":"안녕하세요","edits":[],"appendedRows":[]}"#.utf8)
        let command = try JSONDecoder().decode(ExcelAICommandPlan.self, from: data)
        XCTAssertTrue(command.referencedCells.isEmpty)
        XCTAssertTrue(command.referencedGroupIDs.isEmpty)
        XCTAssertNil(command.countGroupID)
    }

    func testOtherCategoriesAndChangedDataUseTheirActualCells() throws {
        var workbook = try financialWorkbook()
        let original = try snapshot(workbook)
        let cases: [(String, String, Int)] = [
            ("Country", "France", 140), ("Country", "Canada", 140),
            ("Product", "Paseo", 202), ("Product", "Carretera", 93),
            ("Product", "Velo", 109), ("Segment", "Government", 300),
        ]
        for (header, value, count) in cases {
            let group = try XCTUnwrap(original.valueGroups.first { $0.header == header && $0.value == value })
            let expected = Set(workbook.sheets[0].cells.values.filter {
                $0.address.column == group.column && $0.displayValue == value
            }.map(\.address))
            let command = ExcelAICommandPlan(intent: .answer, assistantMessage: "계산 결과",
                edits: [], appendedRows: [], countGroupID: group.id)
            let chat = ExcelAIChatViewModel()
            try chat.handle(command, snapshot: original) { _ in XCTFail("Read-only query"); return "" }
            XCTAssertEqual(group.count, count, value)
            XCTAssertEqual(Set(try XCTUnwrap(chat.activeReferences).addresses), expected, value)
            XCTAssertEqual(chat.messages.last?.text, AppLocalization.format("%@ 항목은 총 %lld개입니다.", value, count))
        }

        // Change a copy in memory, including a value absent from every prompt.
        let changed = try XCTUnwrap(ExcelCellAddress("B3"))
        workbook.sheets[0].cells[changed]?.rawValue = "검증항목X9"
        workbook.sheets[0].cells[changed]?.displayValue = "검증항목X9"
        let updated = try snapshot(workbook)
        let germany = try XCTUnwrap(updated.valueGroups.first { $0.header == "Country" && $0.value == "Germany" })
        XCTAssertEqual(germany.count, 139)
        XCTAssertFalse(germany.addresses.contains(changed))
        let custom = try XCTUnwrap(updated.valueGroups.first { $0.value == "검증항목X9" })
        XCTAssertEqual(custom.count, 1)
        XCTAssertEqual(custom.addresses, [changed])
        let chat = ExcelAIChatViewModel()
        try chat.handle(ExcelAICommandPlan(intent: .answer, assistantMessage: "집계",
            edits: [], appendedRows: [], countGroupID: custom.id), snapshot: updated) { _ in
            XCTFail("Read-only query"); return ""
        }
        XCTAssertEqual(chat.activeReferences?.addresses, [changed])
        XCTAssertEqual(chat.messages.last?.text, AppLocalization.format("%@ 항목은 총 %lld개입니다.", "검증항목X9", 1))
    }

    func testMissingCountFieldUsesOneVerifiedGroupForOccurrenceQuestionOnly() throws {
        let snapshot = try snapshot(financialWorkbook())
        let france = try XCTUnwrap(snapshot.valueGroups.first { $0.header == "Country" && $0.value == "France" })
        let government = try XCTUnwrap(snapshot.valueGroups.first { $0.header == "Segment" && $0.value == "Government" })
        let command = ExcelAICommandPlan(intent: .answer, assistantMessage: "프랑스 항목은 총 4건입니다.",
            edits: [], appendedRows: [], referencedCells: ["A1", "B1"], referencedGroupIDs: [france.id])
        let chat = ExcelAIChatViewModel()
        try chat.handle(command, snapshot: snapshot, userRequest: "프랑스 항목은 모두 몇 건이야?") { _ in
            XCTFail("Read-only query"); return ""
        }
        XCTAssertEqual(chat.messages.last?.text, AppLocalization.format("%@ 항목은 총 %lld개입니다.", "France", 140))
        XCTAssertEqual(chat.activeReferences?.addresses, france.addresses)
        for request in ["프랑스 매출 합계는?", "프랑스에는 제품 종류가 몇 개야?", "프랑스이면서 Government인 행은 몇 개야?", "2014년 프랑스 행은 몇 개야?", "프랑스에서 취소된 행은 몇 개야?"] {
            XCTAssertNil(ExcelAIReferences.countGroup(command: command, snapshot: snapshot, userRequest: request))
        }
        let compound = ExcelAICommandPlan(intent: .answer, assistantMessage: "복수 조건",
            edits: [], appendedRows: [], referencedGroupIDs: [france.id, government.id])
        XCTAssertNil(ExcelAIReferences.countGroup(command: compound, snapshot: snapshot, userRequest: "해당하는 행은 몇 개야?"))
    }

    func testLiveOtherCountryProductAndUnseenValue() async throws {
        guard ProcessInfo.processInfo.environment["EXCEL_AI_REFERENCE_LIVE"] == "1" else {
            throw XCTSkip("EXCEL_AI_REFERENCE_LIVE=1 enables live reference regression requests")
        }
        FirebaseRuntime.configureIfAvailable()
        let original = try financialWorkbook()
        var changed = original
        let address = try XCTUnwrap(ExcelCellAddress("B3"))
        changed.sheets[0].cells[address]?.rawValue = "검증항목X9"
        changed.sheets[0].cells[address]?.displayValue = "검증항목X9"
        let cases: [(String, String, String, Int, ExcelWorkbook)] = [
            ("프랑스 항목은 모두 몇 건이야?", "Country", "France", 140, original),
            ("Product 열에서 Paseo가 나오는 행은 몇 개야?", "Product", "Paseo", 202, original),
            ("Country 열에서 검증항목X9가 나오는 행은 몇 개야?", "Country", "검증항목X9", 1, changed),
            ("독일 총 몇개야", "Country", "Germany", 139, changed),
        ]
        for (request, header, value, count, workbook) in cases {
            let snapshot = try snapshot(workbook)
            let group = try XCTUnwrap(snapshot.valueGroups.first { $0.header == header && $0.value == value })
            let command = try await ExcelAICommandService.plan(userRequest: request, snapshot: snapshot, history: [])
            XCTAssertEqual(command.intent, .answer, request)
            XCTAssertEqual(ExcelAIReferences.countGroup(command: command, snapshot: snapshot, userRequest: request)?.id, group.id, request)
            let chat = ExcelAIChatViewModel()
            try chat.handle(command, snapshot: snapshot, userRequest: request) { _ in
                XCTFail("Read-only query"); return ""
            }
            XCTAssertEqual(chat.activeReferences?.addresses, group.addresses, request)
            XCTAssertEqual(chat.activeReferences?.addresses.count, count, request)
            XCTAssertEqual(chat.messages.last?.text, AppLocalization.format("%@ 항목은 총 %lld개입니다.", value, count), request)
            print("EXCEL_REFERENCE_GENERAL value=\(value) expected=\(count) references=\(chat.activeReferences?.addresses.count ?? 0)")
        }
    }

    func testLiveKoreanGermanyQuestionUsesVerifiedGroup() async throws {
        guard ProcessInfo.processInfo.environment["EXCEL_AI_REFERENCE_LIVE"] == "1" else {
            throw XCTSkip("EXCEL_AI_REFERENCE_LIVE=1 enables the single live regression request")
        }
        FirebaseRuntime.configureIfAvailable()
        let snapshot = try snapshot(financialWorkbook())
        let command = try await ExcelAICommandService.plan(userRequest: "독일 총 몇개야", snapshot: snapshot, history: [])
        let germany = try XCTUnwrap(snapshot.valueGroups.first { $0.header == "Country" && $0.value == "Germany" })
        XCTAssertEqual(command.intent, .answer)
        XCTAssertEqual(ExcelAIReferences.countGroup(command: command, snapshot: snapshot, userRequest: "독일 총 몇개야")?.id, germany.id)
        let chat = ExcelAIChatViewModel()
        try chat.handle(command, snapshot: snapshot, userRequest: "독일 총 몇개야") { _ in
            XCTFail("Counting must never edit cells")
            return ""
        }
        XCTAssertEqual(chat.activeReferences?.addresses.count, 140)
        XCTAssertEqual(chat.messages.last?.text, AppLocalization.format("%@ 항목은 총 %lld개입니다.", "Germany", 140))
        print("EXCEL_REFERENCE_LIVE count=\(germany.count) references=\(chat.activeReferences?.addresses.count ?? 0) last=\(chat.activeReferences?.addresses.last?.reference ?? "none")")
    }
}
