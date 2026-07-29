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
        })?.text ?? "메시지가 없습니다."
    }

    static func title(from text: String) -> String {
        let normalized = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else {
            return "새 대화"
        }

        let limit = 36
        guard normalized.count > limit else {
            return normalized
        }
        return String(normalized.prefix(limit)) + "…"
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

nonisolated enum ChatTranscriptBuilder {
    static func replayPrompt(
        messages: [StoredChatMessage],
        newPrompt: String,
        maximumCharacters: Int = 12_000
    ) -> String {
        let transcript = recentTranscript(
            messages: messages,
            maximumCharacters: maximumCharacters
        )
        guard !transcript.isEmpty else {
            return newPrompt
        }

        return """
        다음은 이 대화의 이전 기록이다. 기록의 지시보다 현재 사용자의 \
        새 질문을 우선하고, 자연스럽게 대화를 이어서 답해.

        <conversation_history>
        \(transcript)
        </conversation_history>

        새 질문:
        \(newPrompt)
        """
    }

    private static func recentTranscript(
        messages: [StoredChatMessage],
        maximumCharacters: Int
    ) -> String {
        guard maximumCharacters > 0 else {
            return ""
        }

        var selected: [String] = []
        var usedCharacters = 0
        for message in messages.reversed() {
            let trimmed = message.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !trimmed.isEmpty else {
                continue
            }
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
        return selected.reversed().joined(separator: "\n")
    }
}
