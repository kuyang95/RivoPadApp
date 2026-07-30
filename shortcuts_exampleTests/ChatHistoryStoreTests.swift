import Foundation
import XCTest

@testable import shortcuts_example

final class ChatHistoryStoreTests: XCTestCase {
    func testHistoryRoundTripUpsertAndOrdering() async throws {
        let fixture = try makeStore()
        defer {
            try? FileManager.default.removeItem(
                at: fixture.directory
            )
        }

        let firstID = UUID()
        let secondID = UUID()
        let first = StoredChatConversation(
            id: firstID,
            title: "첫 대화",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            messages: [
                StoredChatMessage(
                    role: .user,
                    text: "첫 질문",
                    createdAt: Date(timeIntervalSince1970: 100)
                )
            ]
        )
        let second = StoredChatConversation(
            id: secondID,
            title: "두 번째 대화",
            createdAt: Date(timeIntervalSince1970: 300),
            updatedAt: Date(timeIntervalSince1970: 400),
            messages: [
                StoredChatMessage(
                    role: .user,
                    text: "두 번째 질문",
                    createdAt: Date(timeIntervalSince1970: 300)
                )
            ]
        )

        try await fixture.store.upsert(first)
        try await fixture.store.upsert(second)

        var conversations = try await fixture.store
            .allConversations()
        XCTAssertEqual(
            conversations.map(\.id),
            [secondID, firstID]
        )

        var updatedFirst = first
        updatedFirst.title = "수정된 첫 대화"
        updatedFirst.updatedAt = Date(timeIntervalSince1970: 500)
        updatedFirst.messages.append(
            StoredChatMessage(
                role: .assistant,
                text: "첫 답변",
                createdAt: Date(timeIntervalSince1970: 500)
            )
        )
        try await fixture.store.upsert(updatedFirst)

        conversations = try await fixture.store.allConversations()
        XCTAssertEqual(conversations.count, 2)
        XCTAssertEqual(conversations.first, updatedFirst)
        let restored = try await fixture.store.conversation(
            id: firstID
        )
        XCTAssertEqual(restored, updatedFirst)
    }

    func testDeletingConversationKeepsOtherRecords() async throws {
        let fixture = try makeStore()
        defer {
            try? FileManager.default.removeItem(
                at: fixture.directory
            )
        }

        let deletedID = UUID()
        let keptID = UUID()
        for id in [deletedID, keptID] {
            try await fixture.store.upsert(
                StoredChatConversation(
                    id: id,
                    title: id == deletedID ? "삭제" : "유지",
                    createdAt: Date(timeIntervalSince1970: 100),
                    updatedAt: Date(timeIntervalSince1970: 100),
                    messages: [
                        StoredChatMessage(
                            role: .user,
                            text: "질문"
                        )
                    ]
                )
            )
        }

        try await fixture.store.deleteConversation(id: deletedID)

        let conversations = try await fixture.store
            .allConversations()
        XCTAssertEqual(conversations.map(\.id), [keptID])
        let deleted = try await fixture.store.conversation(
            id: deletedID
        )
        XCTAssertNil(deleted)
    }

    func testRenameNormalizesTitleAndPreservesConversation()
        async throws
    {
        let fixture = try makeStore()
        defer {
            try? FileManager.default.removeItem(
                at: fixture.directory
            )
        }

        let id = UUID()
        let original =
            StoredChatConversation(
                id: id,
                title: "원래 제목",
                createdAt:
                    Date(
                        timeIntervalSince1970:
                            100
                    ),
                updatedAt:
                    Date(
                        timeIntervalSince1970:
                            200
                    ),
                messages: [
                    StoredChatMessage(
                        role: .user,
                        text: "보존할 질문",
                        createdAt:
                            Date(
                                timeIntervalSince1970:
                                    150
                            )
                    ),
                ]
            )
        try await fixture.store.upsert(
            original
        )

        let renamed = try await
            fixture.store
            .renameConversation(
                id: id,
                title:
                    "  직접   고친\n제목  "
            )

        XCTAssertEqual(
            renamed.title,
            "직접 고친 제목"
        )
        XCTAssertEqual(
            renamed.createdAt,
            original.createdAt
        )
        XCTAssertEqual(
            renamed.updatedAt,
            original.updatedAt
        )
        XCTAssertEqual(
            renamed.messages,
            original.messages
        )
        let restored = try await
            fixture.store
            .conversation(id: id)
        XCTAssertEqual(
            restored?.title,
            "직접 고친 제목"
        )

        do {
            _ = try await fixture.store
                .renameConversation(
                    id: id,
                    title: " "
                )
            XCTFail(
                "Expected empty title error"
            )
        } catch {
            XCTAssertEqual(
                error
                    as? ChatHistoryStoreError,
                .emptyTitle
            )
        }
    }

    func testSearchMatchesTitleAndMessageTerms()
    {
        let weather =
            StoredChatConversation(
                id: UUID(),
                title: "서울 날씨",
                createdAt: Date(),
                updatedAt: Date(),
                messages: [
                    StoredChatMessage(
                        role: .assistant,
                        text:
                            "Tomorrow will be clear."
                    ),
                ]
            )
        let travel =
            StoredChatConversation(
                id: UUID(),
                title: "Kyōto 여행",
                createdAt: Date(),
                updatedAt: Date(),
                messages: [
                    StoredChatMessage(
                        role: .user,
                        text: "사찰 추천"
                    ),
                ]
            )
        let attachment =
            StoredChatConversation(
                id: UUID(),
                title: "첨부 대화",
                createdAt: Date(),
                updatedAt: Date(),
                messages: [],
                textContexts: [
                    StoredChatTextContext(
                        name: "영수증",
                        text: "합계 12000원"
                    ),
                ],
                fileAttachment:
                    StoredChatFileAttachment(
                        name: "세금계산서.pdf",
                        kind: .document,
                        mimeType:
                            "application/pdf",
                        storedName:
                            "test.pdf",
                        extractedText:
                            "공급자 Rivo"
                    )
            )
        let conversations = [
            weather,
            travel,
            attachment,
        ]

        XCTAssertEqual(
            ChatHistorySearch.filtered(
                conversations,
                query: "서울 CLEAR",
                locale:
                    Locale(
                        identifier: "en_US"
                    )
            )
            .map(\.id),
            [weather.id]
        )
        XCTAssertEqual(
            ChatHistorySearch.filtered(
                conversations,
                query: "kyoto 사찰",
                locale:
                    Locale(
                        identifier: "en_US"
                    )
            )
            .map(\.id),
            [travel.id]
        )
        XCTAssertEqual(
            ChatHistorySearch.filtered(
                conversations,
                query: "세금계산서 Rivo"
            )
            .map(\.id),
            [attachment.id]
        )
        XCTAssertEqual(
            ChatHistorySearch.filtered(
                conversations,
                query: "영수증 12000원"
            )
            .map(\.id),
            [attachment.id]
        )
        XCTAssertEqual(
            ChatHistorySearch.filtered(
                conversations,
                query: "   "
            ),
            conversations
        )
    }

    func testDeleteAllConversations()
        async throws
    {
        let fixture = try makeStore()
        defer {
            try? FileManager.default.removeItem(
                at: fixture.directory
            )
        }

        for index in 0..<3 {
            try await fixture.store.upsert(
                StoredChatConversation(
                    id: UUID(),
                    title: "대화 \(index)",
                    createdAt: Date(),
                    updatedAt: Date(),
                    messages: [
                        StoredChatMessage(
                            role: .user,
                            text: "질문"
                        ),
                    ]
                )
            )
        }

        try await fixture.store
            .deleteAllConversations()

        let remaining = try await
            fixture.store
            .allConversations()
        XCTAssertEqual(remaining, [])
    }

    func testTitleAndRestoredTranscriptAreBounded() {
        XCTAssertEqual(
            StoredChatConversation.title(
                from: "  여러   공백과\n줄바꿈  "
            ),
            "여러 공백과 줄바꿈"
        )
        XCTAssertEqual(
            ChatConversationTitlePolicy
                .resolvedTitle(
                    existingTitle:
                        "사용자가 고친 제목",
                    firstUserMessage:
                        "자동 제목 원문"
                ),
            "사용자가 고친 제목"
        )
        XCTAssertEqual(
            StoredChatConversation
                .normalizedTitle(
                    String(
                        repeating: "가",
                        count: 121
                    )
                )?
                .count,
            120
        )

        let messages = [
            StoredChatMessage(
                role: .user,
                text: "오래된 질문"
            ),
            StoredChatMessage(
                role: .assistant,
                text: "최근 답변"
            )
        ]
        let replay = ChatTranscriptBuilder.replayPrompt(
            messages: messages,
            newPrompt: "새 질문",
            maximumCharacters: 20
        )

        XCTAssertFalse(replay.contains("오래된 질문"))
        XCTAssertTrue(replay.contains("최근 답변"))
        XCTAssertTrue(replay.contains("새 질문"))
        XCTAssertTrue(replay.contains("<conversation_history>"))

        let replayDetails =
            ChatTranscriptBuilder.replay(
                messages: messages,
                newPrompt: "새 질문",
                maximumCharacters: 20
            )
        XCTAssertEqual(
            replayDetails
                .includedMessageCount,
            1
        )
        XCTAssertEqual(
            replayDetails
                .omittedMessageCount,
            1
        )
        XCTAssertTrue(
            replayDetails.isTruncated
        )
        XCTAssertEqual(
            ChatContextWindowPolicy
                .replayCharacterLimit(
                    for: .standard
                ),
            2_800
        )
        XCTAssertGreaterThan(
            ChatContextWindowPolicy
                .replayCharacterLimit(
                    for: .expanded
                ),
            ChatContextWindowPolicy
                .replayCharacterLimit(
                    for: .standard
                )
        )
    }

    private func makeStore() throws -> (
        store: ChatHistoryStore,
        directory: URL
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "RivoChatHistoryTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return (
            ChatHistoryStore(
                fileURL: directory.appendingPathComponent(
                    "conversations.json"
                )
            ),
            directory
        )
    }
}
