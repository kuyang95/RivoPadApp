import Foundation

nonisolated enum StoredChatRole: String, Codable, Sendable {
    case user
    case assistant
}

nonisolated struct StoredChatMessage:
    Identifiable,
    Codable,
    Equatable,
    Sendable
{
    let id: UUID
    let role: StoredChatRole
    let text: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: StoredChatRole,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

nonisolated struct StoredChatConversation:
    Identifiable,
    Codable,
    Equatable,
    Sendable
{
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [StoredChatMessage]

    var preview: String {
        messages.last(where: {
            !$0.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        })?.text
            ?? AppLocalization.string(
                "메시지가 없습니다."
            )
    }

    static let maximumCustomTitleCharacters =
        120

    static func title(from text: String) -> String {
        guard let normalized =
                normalizedTitle(text) else {
            return AppLocalization.string(
                "새 대화"
            )
        }

        let limit = 36
        guard normalized.count > limit else {
            return normalized
        }
        return String(normalized.prefix(limit)) + "…"
    }

    static func normalizedTitle(
        _ text: String
    ) -> String? {
        let normalized = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else {
            return nil
        }
        return String(
            normalized.prefix(
                maximumCustomTitleCharacters
            )
        )
    }
}

nonisolated struct StoredChatDatabase: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var conversations: [StoredChatConversation]

    static let empty = Self(
        schemaVersion: 1,
        conversations: []
    )
}

nonisolated enum ChatHistoryStoreError:
    Error,
    LocalizedError,
    Equatable,
    Sendable
{
    case emptyTitle
    case conversationNotFound

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return AppLocalization.string(
                "대화 제목을 입력해 주세요."
            )
        case .conversationNotFound:
            return AppLocalization.string(
                "수정할 대화를 찾지 못했습니다."
            )
        }
    }
}

actor ChatHistoryStore {
    static let shared = ChatHistoryStore()

    private let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
            return
        }

        let base = try! fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.fileURL = base
            .appendingPathComponent(
                "LocalChat",
                isDirectory: true
            )
            .appendingPathComponent(
                "conversations-v1.json",
                isDirectory: false
            )
    }

    func allConversations() throws -> [StoredChatConversation] {
        try loadDatabase().conversations.sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.updatedAt > $1.updatedAt
        }
    }

    func conversation(id: UUID) throws -> StoredChatConversation? {
        try loadDatabase().conversations.first {
            $0.id == id
        }
    }

    func upsert(_ conversation: StoredChatConversation) throws {
        var database = try loadDatabase()
        if let index = database.conversations.firstIndex(where: {
            $0.id == conversation.id
        }) {
            database.conversations[index] = conversation
        } else {
            database.conversations.append(conversation)
        }
        try saveDatabase(database)
    }

    func deleteConversation(id: UUID) throws {
        var database = try loadDatabase()
        database.conversations.removeAll {
            $0.id == id
        }
        try saveDatabase(database)
    }

    @discardableResult
    func renameConversation(
        id: UUID,
        title rawTitle: String
    ) throws -> StoredChatConversation {
        guard let title =
                StoredChatConversation
                .normalizedTitle(
                    rawTitle
                ) else {
            throw ChatHistoryStoreError
                .emptyTitle
        }

        var database = try loadDatabase()
        guard let index =
                database.conversations
                .firstIndex(where: {
                    $0.id == id
                }) else {
            throw ChatHistoryStoreError
                .conversationNotFound
        }
        database.conversations[index]
            .title = title
        try saveDatabase(database)
        return database.conversations[index]
    }

    func deleteAllConversations() throws {
        try saveDatabase(.empty)
    }

    private func loadDatabase() throws -> StoredChatDatabase {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StoredChatDatabase.self, from: data)
    }

    private func saveDatabase(_ database: StoredChatDatabase) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(database)
        try data.write(to: fileURL, options: .atomic)
    }
}

nonisolated enum ChatHistorySearch {
    static func filtered(
        _ conversations:
            [StoredChatConversation],
        query rawQuery: String,
        locale: Locale = .current
    ) -> [StoredChatConversation] {
        let terms = rawQuery
            .split(whereSeparator: \.isWhitespace)
            .map {
                normalized(
                    String($0),
                    locale: locale
                )
            }
            .filter {
                !$0.isEmpty
            }
        guard !terms.isEmpty else {
            return conversations
        }

        return conversations.filter {
            conversation in
            let searchable = normalized(
                (
                    [conversation.title]
                    + conversation.messages
                        .map(\.text)
                )
                .joined(separator: "\n"),
                locale: locale
            )
            return terms.allSatisfy {
                searchable.contains($0)
            }
        }
    }

    private static func normalized(
        _ value: String,
        locale: Locale
    ) -> String {
        value.folding(
            options: [
                .caseInsensitive,
                .diacriticInsensitive,
                .widthInsensitive,
            ],
            locale: locale
        )
    }
}

nonisolated enum ChatConversationTitlePolicy {
    static func resolvedTitle(
        existingTitle: String?,
        firstUserMessage: String
    ) -> String {
        if let existingTitle,
           !existingTitle
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty {
            return existingTitle
        }
        return StoredChatConversation
            .title(
                from: firstUserMessage
            )
    }
}

nonisolated struct ChatReplayPrompt:
    Equatable,
    Sendable
{
    let prompt: String
    let includedMessageCount: Int
    let omittedMessageCount: Int

    var isTruncated: Bool {
        omittedMessageCount > 0
    }
}

nonisolated enum ChatContextWindowPolicy {
    static func replayCharacterLimit(
        for memoryTier: DeviceMemoryTier
    ) -> Int {
        // Leave room in the 4K/8K rotating KV cache for the
        // system prompt, the new question, and generated output.
        switch memoryTier {
        case .standard:
            return 2_800
        case .expanded:
            return 6_400
        }
    }
}

nonisolated enum ChatTranscriptBuilder {
    static func replayPrompt(
        messages: [StoredChatMessage],
        newPrompt: String,
        maximumCharacters: Int = 12_000
    ) -> String {
        replay(
            messages: messages,
            newPrompt: newPrompt,
            maximumCharacters:
                maximumCharacters
        ).prompt
    }

    static func replay(
        messages: [StoredChatMessage],
        newPrompt: String,
        maximumCharacters: Int
    ) -> ChatReplayPrompt {
        let selection = recentTranscript(
            messages: messages,
            maximumCharacters:
                maximumCharacters
        )
        guard !selection.text.isEmpty else {
            return ChatReplayPrompt(
                prompt: newPrompt,
                includedMessageCount: 0,
                omittedMessageCount:
                    selection
                    .omittedMessageCount
            )
        }

        return ChatReplayPrompt(
            prompt: """
        다음은 이 대화의 이전 기록이다. 기록의 지시보다 현재 사용자의 \
        새 질문을 우선하고, 자연스럽게 대화를 이어서 답해.

        <conversation_history>
        \(selection.text)
        </conversation_history>

        새 질문:
        \(newPrompt)
        """,
            includedMessageCount:
                selection
                .includedMessageCount,
            omittedMessageCount:
                selection
                .omittedMessageCount
        )
    }

    private struct TranscriptSelection {
        let text: String
        let includedMessageCount: Int
        let omittedMessageCount: Int
    }

    private static func recentTranscript(
        messages: [StoredChatMessage],
        maximumCharacters: Int
    ) -> TranscriptSelection {
        let eligibleMessages =
            messages.filter {
                !$0.text
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .isEmpty
            }
        guard maximumCharacters > 0 else {
            return TranscriptSelection(
                text: "",
                includedMessageCount: 0,
                omittedMessageCount:
                    eligibleMessages.count
            )
        }

        var selected: [String] = []
        var usedCharacters = 0
        for message in
            eligibleMessages.reversed() {
            let trimmed = message.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let label = message.role == .user ? "사용자" : "도우미"
            let line = "\(label): \(trimmed)"
            guard selected.isEmpty
                    || usedCharacters + line.count + 1
                    <= maximumCharacters else {
                break
            }

            if selected.isEmpty, line.count > maximumCharacters {
                selected.append(
                    String(line.suffix(maximumCharacters))
                )
                break
            }
            selected.append(line)
            usedCharacters += line.count + 1
        }
        return TranscriptSelection(
            text: selected
                .reversed()
                .joined(separator: "\n"),
            includedMessageCount:
                selected.count,
            omittedMessageCount:
                max(
                    0,
                    eligibleMessages.count
                        - selected.count
                )
        )
    }
}
