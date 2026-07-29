import Foundation

nonisolated struct VisionLinkConversationContext:
    Equatable,
    Sendable
{
    let sharedText: String
    let attachment:
        VisionLinkConversationAttachment?
}

nonisolated struct VisionLinkConversationAttachment:
    Equatable,
    Sendable
{
    let name: String
    let kind: VisionLinkChatAttachmentKind
    let mimeType: String
    let fileURL: URL
    let extractedText: String?
}

actor VisionLinkConversationStore {
    static let shared =
        VisionLinkConversationStore()
    static let maximumSharedContextSize =
        256 * 1_024

    private let databaseURL: URL
    private let attachmentDirectory: URL
    private let fileManager: FileManager
    private let chatHistoryStore: ChatHistoryStore

    init(
        databaseURL: URL? = nil,
        attachmentDirectory: URL? = nil,
        fileManager: FileManager = .default,
        chatHistoryStore:
            ChatHistoryStore = .shared
    ) {
        self.fileManager = fileManager
        self.chatHistoryStore = chatHistoryStore

        if let databaseURL,
           let attachmentDirectory {
            self.databaseURL = databaseURL
            self.attachmentDirectory =
                attachmentDirectory
            return
        }

        let base = try! fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent(
            "VisionLink",
            isDirectory: true
        )
        self.databaseURL = databaseURL
            ?? base.appendingPathComponent(
                "conversations-v1.json",
                isDirectory: false
            )
        self.attachmentDirectory =
            attachmentDirectory
            ?? base.appendingPathComponent(
                "ChatAttachments",
                isDirectory: true
            )
    }

    func context(
        conversationID: String
    ) throws -> VisionLinkConversationContext {
        var database = try loadDatabase()
        let index = ensureConversation(
            conversationID,
            in: &database
        )
        try saveDatabase(database)
        let conversation =
            database.conversations[index]
        return context(for: conversation)
    }

    func appendContext(
        conversationID: String,
        name: String,
        text: String
    ) throws {
        let block = "[\(name)]\n\(text)"
        var database = try loadDatabase()
        let index = ensureConversation(
            conversationID,
            in: &database
        )
        let previous =
            database.conversations[index]
                .sharedText
        let combined = previous.isEmpty
            ? block
            : previous + "\n\n" + block
        guard combined.utf8.count
                <= Self.maximumSharedContextSize else {
            throw VisionLinkConversationStoreError
                .contextTooLarge
        }
        database.conversations[index]
            .sharedText = combined
        try saveDatabase(database)
    }

    func saveAttachment(
        conversationID: String,
        name: String,
        kind: VisionLinkChatAttachmentKind,
        mimeType: String,
        sourceURL: URL,
        extractedText: String?
    ) throws {
        try fileManager.createDirectory(
            at: attachmentDirectory,
            withIntermediateDirectories: true
        )

        var storedName = UUID().uuidString
        let pathExtension =
            sourceURL.pathExtension
                .lowercased()
        if !pathExtension.isEmpty {
            storedName += ".\(pathExtension)"
        }
        let destination =
            attachmentDirectory
            .appendingPathComponent(
                storedName,
                isDirectory: false
            )
        try fileManager.copyItem(
            at: sourceURL,
            to: destination
        )

        do {
            var database = try loadDatabase()
            let index = ensureConversation(
                conversationID,
                in: &database
            )
            let oldStoredName =
                database.conversations[index]
                    .attachment?.storedName
            database.conversations[index]
                .attachment =
                VisionLinkStoredConversationAttachment(
                    name: name,
                    kind: kind,
                    mimeType: mimeType,
                    storedName: storedName,
                    extractedText: extractedText
                )
            try saveDatabase(database)
            if let oldStoredName,
               oldStoredName != storedName {
                try? fileManager.removeItem(
                    at: attachmentDirectory
                        .appendingPathComponent(
                            oldStoredName,
                            isDirectory: false
                        )
                )
            }
        } catch {
            try? fileManager.removeItem(
                at: destination
            )
            throw error
        }
    }

    func saveExchange(
        request: VisionLinkChatRequest,
        answer: String
    ) async throws {
        var database = try loadDatabase()
        let index = ensureConversation(
            request.conversationID,
            in: &database
        )
        let localID =
            database.conversations[index].localID
        try saveDatabase(database)

        var conversation =
            try await chatHistoryStore
                .conversation(id: localID)
            ?? StoredChatConversation(
                id: localID,
                title: Self.title(
                    from: request.messages
                        .first(where: {
                            $0.role == .user
                        })?.content ?? ""
                ),
                createdAt: Date(),
                updatedAt: Date(),
                messages: []
            )

        let sourceMessages:
            [VisionLinkChatMessage]
        if conversation.messages.isEmpty {
            sourceMessages = request.messages
        } else if let latestQuestion =
                    request.messages.last(where: {
                        $0.role == .user
                    }) {
            sourceMessages = [latestQuestion]
        } else {
            sourceMessages = []
        }
        conversation.messages.append(
            contentsOf: sourceMessages.map {
                StoredChatMessage(
                    role: $0.role == .user
                        ? .user
                        : .assistant,
                    text: $0.content
                )
            }
        )
        conversation.messages.append(
            StoredChatMessage(
                role: .assistant,
                text: answer
            )
        )
        conversation.updatedAt = Date()
        try await chatHistoryStore.upsert(
            conversation
        )
    }

    private func context(
        for conversation:
            VisionLinkStoredConversation
    ) -> VisionLinkConversationContext {
        let attachment =
            conversation.attachment.map {
                VisionLinkConversationAttachment(
                    name: $0.name,
                    kind: $0.kind,
                    mimeType: $0.mimeType,
                    fileURL: attachmentDirectory
                        .appendingPathComponent(
                            $0.storedName,
                            isDirectory: false
                        ),
                    extractedText:
                        $0.extractedText
                )
            }
        return VisionLinkConversationContext(
            sharedText: conversation.sharedText,
            attachment: attachment
        )
    }

    private func ensureConversation(
        _ remoteID: String,
        in database:
            inout VisionLinkConversationDatabase
    ) -> Int {
        if let index =
                database.conversations
                .firstIndex(where: {
                    $0.remoteID == remoteID
                }) {
            return index
        }
        database.conversations.append(
            VisionLinkStoredConversation(
                remoteID: remoteID,
                localID: UUID(),
                sharedText: "",
                attachment: nil
            )
        )
        return database.conversations.count - 1
    }

    private func loadDatabase() throws
        -> VisionLinkConversationDatabase {
        guard fileManager.fileExists(
            atPath: databaseURL.path
        ) else {
            return .empty
        }
        let data = try Data(contentsOf: databaseURL)
        return try JSONDecoder().decode(
            VisionLinkConversationDatabase.self,
            from: data
        )
    }

    private func saveDatabase(
        _ database:
            VisionLinkConversationDatabase
    ) throws {
        try fileManager.createDirectory(
            at: databaseURL
                .deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
        ]
        let data = try encoder.encode(database)
        try data.write(
            to: databaseURL,
            options: .atomic
        )
    }

    private static func title(
        from text: String
    ) -> String {
        let normalized = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else {
            return "VisionLink 대화"
        }
        let limit = 30
        return normalized.count <= limit
            ? normalized
            : String(normalized.prefix(limit)) + "…"
    }
}

nonisolated private struct
    VisionLinkConversationDatabase:
    Codable
{
    var schemaVersion: Int
    var conversations:
        [VisionLinkStoredConversation]

    static let empty = Self(
        schemaVersion: 1,
        conversations: []
    )
}

nonisolated private struct
    VisionLinkStoredConversation:
    Codable
{
    let remoteID: String
    let localID: UUID
    var sharedText: String
    var attachment:
        VisionLinkStoredConversationAttachment?
}

nonisolated private struct
    VisionLinkStoredConversationAttachment:
    Codable
{
    let name: String
    let kind: VisionLinkChatAttachmentKind
    let mimeType: String
    let storedName: String
    let extractedText: String?
}

nonisolated enum VisionLinkConversationStoreError:
    Error,
    LocalizedError,
    Equatable
{
    case contextTooLarge

    var errorDescription: String? {
        switch self {
        case .contextTooLarge:
            return "대화에 첨부된 문맥이 256KB를 초과했습니다."
        }
    }
}
