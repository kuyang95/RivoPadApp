import Foundation

nonisolated enum VisionLinkChatRole:
    String,
    Codable,
    Equatable,
    Sendable
{
    case user
    case assistant
}

nonisolated struct VisionLinkChatMessage:
    Codable,
    Equatable,
    Sendable
{
    let role: VisionLinkChatRole
    let content: String
}

nonisolated struct VisionLinkChatRequest:
    Equatable,
    Sendable
{
    let requestID: String
    let conversationID: String
    let messages: [VisionLinkChatMessage]
}

nonisolated enum VisionLinkChatAttachmentKind:
    String,
    Codable,
    Equatable,
    Sendable
{
    case image
    case document
}

nonisolated struct VisionLinkChatContextAttachment:
    Equatable,
    Sendable
{
    let attachmentID: String
    let conversationID: String
    let name: String
    let text: String
}

nonisolated struct VisionLinkChatFileAttachment:
    Equatable,
    Sendable
{
    let attachmentID: String
    let conversationID: String
    let name: String
    let kind: VisionLinkChatAttachmentKind
    let mimeType: String
    let fileURL: URL
}

nonisolated enum VisionLinkChatControl {
    static func attachmentReady(
        attachmentID: String,
        conversationID: String,
        name: String
    ) -> Data {
        controlData(
            [
                "type": "chat-attachment-ready",
                "attachmentId": attachmentID,
                "conversationId": conversationID,
                "name": name,
            ]
        )
    }

    static func attachmentError(
        attachmentID: String,
        conversationID: String,
        message: String
    ) -> Data {
        controlData(
            [
                "type": "chat-attachment-error",
                "attachmentId": attachmentID,
                "conversationId": conversationID,
                "message": String(message.prefix(500)),
            ]
        )
    }

    private static func controlData(
        _ object: [String: Any]
    ) -> Data {
        (
            try? JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
            )
        ) ?? Data()
    }
}
