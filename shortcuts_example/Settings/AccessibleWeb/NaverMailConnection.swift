import Foundation
import Security
import SwiftMail

struct NaverMailCredential: Codable {
    let address: String
    let appPassword: String
}

enum NaverMailCredentialStore {
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "rivo.naver-mail-link.v1",
            kSecAttrAccount as String: "connection",
        ]
    }

    static var exists: Bool {
        SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func read() throws -> NaverMailCredential? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw StoreError.unavailable }
        return try JSONDecoder().decode(NaverMailCredential.self, from: data)
    }

    static func save(_ credential: NaverMailCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw StoreError.unavailable }
        var entry = query
        entry[kSecValueData as String] = data
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw StoreError.unavailable }
    }

    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.unavailable }
    }

    private enum StoreError: Error { case unavailable }
}

struct NaverMailItem: Identifiable {
    let uid: SwiftMail.UID
    let validity: UIDValidity
    let subject: String?
    let sender: String?
    let date: Date?
    var id: UInt32 { uid.value }
}

enum NaverMailbox {
    private static let bodyLimit = 512 * 1024

    static func inbox(_ credential: NaverMailCredential) async throws -> [NaverMailItem] {
        try await withInbox(credential) { server, mailbox in
            let count = mailbox.messageCount
            guard count > 0, let last = UInt32(exactly: count) else { return [] }
            let first = UInt32(max(1, count - 29))
            let items = try await server.fetchMessageInfos(
                sequenceRange: SequenceNumber(first)...SequenceNumber(last),
                options: [.envelope, .internalDate]
            )
            return items.sorted { $0.sequenceNumber.value > $1.sequenceNumber.value }.compactMap { item in
                guard let uid = item.uid else { return nil }
                return NaverMailItem(uid: uid, validity: mailbox.uidValidity,
                    subject: item.subject.map { String($0.prefix(500)) },
                    sender: item.from.map { String($0.prefix(500)) },
                    date: item.internalDate ?? item.date)
            }
        }
    }

    static func body(_ credential: NaverMailCredential, item: NaverMailItem) async throws -> String? {
        try await withInbox(credential) { server, mailbox in
            guard mailbox.uidValidity == item.validity,
                  let info = try await server.fetchMessageInfo(for: item.uid, options: [.bodyStructure])
            else { throw MailboxError.messageUnavailable }
            guard var part = info.parts.first(where: {
                $0.contentType.lowercased().hasPrefix("text/plain") &&
                    $0.filename == nil && $0.disposition?.lowercased() != "attachment" &&
                    ($0.size ?? Int.max) <= bodyLimit
            }) else { return nil }
            part.data = try await server.fetchPart(section: part.section, of: item.uid)
            return part.textContent
        }
    }

    private static func withInbox<T>(
        _ credential: NaverMailCredential, _ operation: (IMAPServer, Mailbox.Selection) async throws -> T
    ) async throws -> T {
        let server = IMAPServer(host: "imap.naver.com", port: 993, transportSecurity: .implicitTLS)
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                try await server.connect()
                try Task.checkCancellation()
                try await server.login(username: credential.address, password: credential.appPassword)
                try Task.checkCancellation()
                let mailbox = try await server.selectMailbox("INBOX")
                let result = try await operation(server, mailbox)
                try? await server.disconnect()
                return result
            } catch {
                try? await server.disconnect()
                throw error
            }
        } onCancel: {
            Task { try? await server.disconnect() }
        }
    }

    private enum MailboxError: Error { case messageUnavailable }
}
