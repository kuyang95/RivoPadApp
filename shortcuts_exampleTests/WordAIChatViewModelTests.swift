import Foundation
import XCTest
@testable import shortcuts_example

@MainActor
final class WordAIChatViewModelTests: XCTestCase {
    private let request = "문단을 사진 동아리로 바꿔줘"

    private func snapshot() -> WordAIDocumentSnapshot {
        WordAISnapshotBuilder.make(documentName: "예시.hwpx", blocks: [
            WordDocumentBlock(id: "p1", paragraphIndex: 0, text: "기존 이름",
                styleID: nil, isNumbered: false, tableLocation: nil, isEditable: true)
        ], selectedBlockID: "p1")
    }

    private func command(target: String = "p1") -> WordAICommandPlan {
        WordAICommandPlan(intent: .edit, assistantMessage: "사진 동아리로 변경했습니다.",
            operations: [.init(kind: .replaceText, blockID: target,
                newText: "사진 동아리", styleID: nil)])
    }

    func testAutomaticEditAppliesOnceWithoutLeavingAProposal() throws {
        let chat = WordAIChatViewModel()
        var applied: [WordAIValidatedPlan] = []
        try chat.handle(command(), snapshot: snapshot(), userRequest: request) { plan in
            applied.append(plan)
            return "적용 완료"
        }

        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied.first?.operations, command().operations)
        XCTAssertNil(chat.pendingPlan)
        XCTAssertEqual(chat.messages.map(\.role), [.assistant, .notice])
        XCTAssertEqual(chat.messages.last?.text, "적용 완료")
        chat.applyPending { _ in
            XCTFail("자동으로 적용한 수정안을 다시 적용하면 안 됩니다.")
            return "중복 적용"
        }
    }

    func testWordStillWaitsForManualApplicationByDefault() throws {
        let chat = WordAIChatViewModel()
        try chat.handle(command(), snapshot: snapshot(), userRequest: request)
        XCTAssertNotNil(chat.pendingPlan)

        var applyCount = 0
        chat.applyPending { _ in
            applyCount += 1
            return "적용 완료"
        }
        XCTAssertEqual(applyCount, 1)
        XCTAssertNil(chat.pendingPlan)
        XCTAssertEqual(chat.messages.last?.text, "적용 완료")
    }

    func testAnswersAndClarificationsDoNotEditTheDocument() throws {
        for intent in [WordAICommandPlan.Intent.answer, .clarify] {
            let chat = WordAIChatViewModel()
            let response = WordAICommandPlan(intent: intent,
                assistantMessage: "문서에 대한 답변입니다.", operations: [])
            try chat.handle(response, snapshot: snapshot(), userRequest: request) { _ in
                XCTFail("질문 답변이나 추가 질문으로 문서를 수정하면 안 됩니다.")
                return "적용 완료"
            }
            XCTAssertNil(chat.pendingPlan)
            XCTAssertEqual(chat.messages.map(\.text), [response.assistantMessage])
        }
    }

    func testInvalidTargetIsRejectedBeforeAutomaticApplication() {
        let chat = WordAIChatViewModel()
        XCTAssertThrowsError(try chat.handle(command(target: "missing"),
            snapshot: snapshot(), userRequest: request) { _ in
            XCTFail("검증을 통과하지 못한 수정안은 적용하면 안 됩니다.")
            return "적용 완료"
        })
        XCTAssertNil(chat.pendingPlan)
        XCTAssertTrue(chat.messages.isEmpty)
    }

    func testFailedApplicationDoesNotAnnounceSuccessOrLeaveAProposal() throws {
        for error in [WordAIApplyError.staleProposal, .invalidTarget, .noChanges] {
            let chat = WordAIChatViewModel()
            try chat.handle(command(), snapshot: snapshot(), userRequest: request) { _ in
                throw error
            }
            XCTAssertNil(chat.pendingPlan)
            XCTAssertEqual(chat.messages.map(\.role), [.notice])
            XCTAssertEqual(chat.messages.last?.text, error.localizedDescription)
        }
    }

    func testAutomaticHWPXEditSupportsUndoRedoAndSave() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        defer { try? FileManager.default.removeItem(at: url) }
        try LegacyHWPXConverter.convert(text: "기존 이름").write(to: url)
        let document = HWPDocumentViewModel(fileURL: url)
        await document.load()
        XCTAssertNil(document.errorDescription)
        let catalog = try XCTUnwrap(document.makeAIRetrievalCatalog(for: request))
        let snapshot = try XCTUnwrap(document.makeAISnapshot(for: request,
            catalog: catalog, retrievalPlan: nil))
        let target = try XCTUnwrap(snapshot.blocks.first?.id)
        let chat = WordAIChatViewModel()

        try chat.handle(command(target: target), snapshot: snapshot,
            userRequest: request, applying: document.applyAIPlan)
        XCTAssertNil(chat.pendingPlan)
        XCTAssertEqual(document.blocks.first?.text, "사진 동아리")
        XCTAssertTrue(document.hasUnsavedChanges)
        document.undo()
        XCTAssertEqual(document.blocks.first?.text, "기존 이름")
        document.redo()
        XCTAssertEqual(document.blocks.first?.text, "사진 동아리")
        await document.save()
        XCTAssertNil(document.errorDescription)
        XCTAssertFalse(document.hasUnsavedChanges)
        let reloaded = try HWPXDocumentPackage.load(from: Data(contentsOf: url))
        XCTAssertEqual(reloaded.blocks.first?.text, "사진 동아리")
    }

    func testAutomaticEditPreservesUserChangesMadeAfterTheSnapshot() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        defer { try? FileManager.default.removeItem(at: url) }
        try LegacyHWPXConverter.convert(text: "기존 이름").write(to: url)
        let document = HWPDocumentViewModel(fileURL: url)
        await document.load()
        let catalog = try XCTUnwrap(document.makeAIRetrievalCatalog(for: request))
        let snapshot = try XCTUnwrap(document.makeAISnapshot(for: request,
            catalog: catalog, retrievalPlan: nil))
        let target = try XCTUnwrap(snapshot.blocks.first?.id)
        document.selectBlock(target)
        document.editorText = "사용자가 직접 수정한 이름"
        let chat = WordAIChatViewModel()

        try chat.handle(command(target: target), snapshot: snapshot,
            userRequest: request, applying: document.applyAIPlan)
        XCTAssertEqual(document.blocks.first?.text, "사용자가 직접 수정한 이름")
        XCTAssertNil(chat.pendingPlan)
        XCTAssertEqual(chat.messages.map(\.role), [.notice])
        XCTAssertEqual(chat.messages.last?.text, WordAIApplyError.staleProposal.localizedDescription)
    }
}
