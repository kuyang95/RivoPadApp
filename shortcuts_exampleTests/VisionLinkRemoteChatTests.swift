import Foundation
@testable import shortcuts_example
import XCTest

@MainActor
final class VisionLinkRemoteChatTests:
    XCTestCase
{
    func testConversationContextAttachmentAndHistoryPersistence()
        async throws
    {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        try await fixture.store.appendContext(
            conversationID: "remote-1",
            name: "클립보드",
            text: "첫 문맥"
        )
        try await fixture.store.appendContext(
            conversationID: "remote-1",
            name: "메모",
            text: "둘째 문맥"
        )
        let context = try await fixture.store
            .context(conversationID: "remote-1")
        XCTAssertEqual(
            context.sharedText,
            "[클립보드]\n첫 문맥\n\n[메모]\n둘째 문맥"
        )

        let firstRequest = VisionLinkChatRequest(
            requestID: "request-1",
            conversationID: "remote-1",
            messages: [
                VisionLinkChatMessage(
                    role: .user,
                    content: "첫 질문"
                ),
                VisionLinkChatMessage(
                    role: .assistant,
                    content: "이전 답변"
                ),
                VisionLinkChatMessage(
                    role: .user,
                    content: "새 질문"
                ),
            ]
        )
        try await fixture.store.saveExchange(
            request: firstRequest,
            answer: "새 답변"
        )
        try await fixture.store.saveExchange(
            request: VisionLinkChatRequest(
                requestID: "request-2",
                conversationID: "remote-1",
                messages:
                    firstRequest.messages + [
                        VisionLinkChatMessage(
                            role: .assistant,
                            content: "새 답변"
                        ),
                        VisionLinkChatMessage(
                            role: .user,
                            content: "마지막 질문"
                        ),
                    ]
            ),
            answer: "마지막 답변"
        )

        let conversations =
            try await fixture.history
                .allConversations()
        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(
            conversations[0].title,
            "첫 질문"
        )
        XCTAssertEqual(
            conversations[0].messages.map(\.text),
            [
                "첫 질문",
                "이전 답변",
                "새 질문",
                "새 답변",
                "마지막 질문",
                "마지막 답변",
            ]
        )
    }

    func testReplacingStoredAttachmentDeletesOldCopy()
        async throws
    {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let first = fixture.root
            .appendingPathComponent("first.png")
        let second = fixture.root
            .appendingPathComponent("second.png")
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: first.path,
                contents: Data("first".utf8)
            )
        )
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: second.path,
                contents: Data("second".utf8)
            )
        )

        try await fixture.store.saveAttachment(
            conversationID: "remote-2",
            name: "첫 이미지",
            kind: .image,
            mimeType: "image/png",
            sourceURL: first,
            extractedText: nil
        )
        let firstContext =
            try await fixture.store.context(
                conversationID: "remote-2"
            )
        let firstStoredURL = try XCTUnwrap(
            firstContext.attachment?.fileURL
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: firstStoredURL.path
            )
        )

        try await fixture.store.saveAttachment(
            conversationID: "remote-2",
            name: "둘째 이미지",
            kind: .image,
            mimeType: "image/png",
            sourceURL: second,
            extractedText: nil
        )
        let secondContext =
            try await fixture.store.context(
                conversationID: "remote-2"
            )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: firstStoredURL.path
            )
        )
        XCTAssertEqual(
            secondContext.attachment?.name,
            "둘째 이미지"
        )
    }

    func testRemoteChatProcessorReturnsAnswerAndSavesHistory()
        async throws
    {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let service = RemoteChatServiceStub()
        service.answerText = "로컬 답변"
        var updates: [VisionLinkRemoteChatUpdate] =
            []
        let request = VisionLinkChatRequest(
            requestID: "request-3",
            conversationID: "remote-3",
            messages: [
                VisionLinkChatMessage(
                    role: .user,
                    content: "질문"
                ),
            ]
        )

        try await VisionLinkRemoteChatProcessor(
            service: service,
            conversationStore: fixture.store
        )
        .process(.request(request)) {
            updates.append($0)
        }

        XCTAssertEqual(
            updates,
            [
                .progress(
                    request: request,
                    stage: "thinking"
                ),
                .result(
                    request: request,
                    text: "로컬 답변"
                ),
            ]
        )
        XCTAssertEqual(service.answerCalls, 1)
        let savedMessages =
            try await fixture.history
            .allConversations()
            .first?
            .messages
            .map(\.text)
        XCTAssertEqual(
            savedMessages,
            ["질문", "로컬 답변"]
        )
    }

    func testTextAttachmentAppendsContextAndCleansTemporaryFile()
        async throws
    {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let service = RemoteChatServiceStub()
        let temporary = fixture.root
            .appendingPathComponent("note.txt")
        try Data("참고 텍스트".utf8).write(
            to: temporary
        )
        let attachment =
            VisionLinkChatFileAttachment(
                attachmentID: "attachment-1",
                conversationID: "remote-4",
                name: "note.txt",
                kind: .document,
                mimeType: "text/plain",
                fileURL: temporary
            )
        var updates: [VisionLinkRemoteChatUpdate] =
            []

        try await VisionLinkRemoteChatProcessor(
            service: service,
            conversationStore: fixture.store
        )
        .process(.file(attachment)) {
            updates.append($0)
        }

        XCTAssertEqual(
            updates,
            [
                .attachmentReady(
                    attachmentID: "attachment-1",
                    conversationID: "remote-4",
                    name: "note.txt"
                ),
            ]
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: temporary.path
            )
        )
        let storedContext =
            try await fixture.store.context(
                conversationID: "remote-4"
            )
        XCTAssertEqual(
            storedContext.sharedText,
            "[note.txt]\n참고 텍스트"
        )
    }

    func testUnsupportedDocumentReportsAttachmentErrorAndCleansFile()
        async throws
    {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let service = RemoteChatServiceStub()
        let temporary = fixture.root
            .appendingPathComponent("legacy.hwp")
        try Data("fixture".utf8).write(
            to: temporary
        )
        let attachment =
            VisionLinkChatFileAttachment(
                attachmentID: "attachment-2",
                conversationID: "remote-5",
                name: "legacy.hwp",
                kind: .document,
                mimeType:
                    "application/x-hwp",
                fileURL: temporary
            )
        var updates: [VisionLinkRemoteChatUpdate] =
            []

        try await VisionLinkRemoteChatProcessor(
            service: service,
            conversationStore: fixture.store
        )
        .process(.file(attachment)) {
            updates.append($0)
        }

        guard case .attachmentFailed(
            let attachmentID,
            let conversationID,
            let message
        ) = updates.first else {
            return XCTFail(
                "첨부 실패 응답이어야 합니다."
            )
        }
        XCTAssertEqual(
            attachmentID,
            "attachment-2"
        )
        XCTAssertEqual(
            conversationID,
            "remote-5"
        )
        XCTAssertTrue(
            message.contains("아직 지원되지")
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: temporary.path
            )
        )
    }

    func testPromptContainsBoundedContextHistoryAndQuestion()
    {
        let prompt =
            VisionLinkChatPromptBuilder.prompt(
                request: VisionLinkChatRequest(
                    requestID: "request-4",
                    conversationID: "remote-6",
                    messages: [
                        VisionLinkChatMessage(
                            role: .user,
                            content:
                                "오래된 질문"
                        ),
                        VisionLinkChatMessage(
                            role: .assistant,
                            content:
                                "오래된 답변"
                        ),
                        VisionLinkChatMessage(
                            role: .user,
                            content:
                                "현재 질문"
                        ),
                    ]
                ),
                context:
                    VisionLinkConversationContext(
                        sharedText:
                            "공유 문맥",
                        attachment:
                            VisionLinkConversationAttachment(
                                name: "문서",
                                kind: .document,
                                mimeType:
                                    "application/pdf",
                                fileURL: URL(
                                    fileURLWithPath:
                                        "/tmp/document.pdf"
                                ),
                                extractedText:
                                    "문서 본문"
                            )
                    )
            )

        XCTAssertTrue(
            prompt.contains("<shared_context>")
        )
        XCTAssertTrue(
            prompt.contains("<attached_document>")
        )
        XCTAssertTrue(
            prompt.contains("도우미: 오래된 답변")
        )
        XCTAssertTrue(
            prompt.contains("현재 질문")
        )
    }

    private func makeFixture() throws
        -> RemoteChatFixture {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "VisionLinkChatTests-"
                    + UUID().uuidString,
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let history = ChatHistoryStore(
            fileURL: root
                .appendingPathComponent(
                    "chat-history.json"
                )
        )
        return RemoteChatFixture(
            root: root,
            history: history,
            store: VisionLinkConversationStore(
                databaseURL: root
                    .appendingPathComponent(
                        "visionlink-chat.json"
                    ),
                attachmentDirectory: root
                    .appendingPathComponent(
                        "Attachments",
                        isDirectory: true
                    ),
                chatHistoryStore: history
            )
        )
    }
}

@MainActor
private final class RemoteChatServiceStub:
    VisionLinkRemoteChatServing
{
    var answerText = ""
    var extractedText = ""
    var answerCalls = 0
    var extractionCalls = 0

    func answer(
        request: VisionLinkChatRequest,
        context: VisionLinkConversationContext
    ) async throws -> String {
        answerCalls += 1
        return answerText
    }

    func extractDocumentText(
        at url: URL,
        mimeType: String
    ) async throws -> String {
        extractionCalls += 1
        return extractedText
    }
}

private struct RemoteChatFixture {
    let root: URL
    let history: ChatHistoryStore
    let store: VisionLinkConversationStore

    func remove() {
        try? FileManager.default.removeItem(
            at: root
        )
    }
}
