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

    func testTitleAndRestoredTranscriptAreBounded() {
        XCTAssertEqual(
            StoredChatConversation.title(
                from: "  여러   공백과\n줄바꿈  "
            ),
            "여러 공백과 줄바꿈"
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
