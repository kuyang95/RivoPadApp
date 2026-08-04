import Foundation
import Security

nonisolated protocol VisionLinkCredentialStoring:
    Sendable
{
    func read() throws -> VisionLinkStoredCredentials?
    func save(_ credentials: VisionLinkStoredCredentials) throws
    func clear() throws
}

nonisolated final class VisionLinkCredentialStore:
    VisionLinkCredentialStoring,
    @unchecked Sendable
{
    private let service: String
    private let account = "receiver"

    init(
        service: String =
            "net.rivo.visioncraft.visionlink"
    ) {
        self.service = service
    }

    func read() throws -> VisionLinkStoredCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query as CFDictionary,
            &result
        )
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data else {
            throw VisionLinkCredentialError.keychain(status)
        }
        do {
            return try JSONDecoder().decode(
                VisionLinkStoredCredentials.self,
                from: data
            )
        } catch {
            throw VisionLinkCredentialError.corruptData
        }
    }

    func save(
        _ credentials: VisionLinkStoredCredentials
    ) throws {
        let data = try JSONEncoder().encode(credentials)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            attributes as CFDictionary
        )
        if status == errSecItemNotFound {
            var insert = baseQuery
            attributes.forEach {
                insert[$0.key] = $0.value
            }
            let insertStatus = SecItemAdd(
                insert as CFDictionary,
                nil
            )
            guard insertStatus == errSecSuccess else {
                throw VisionLinkCredentialError.keychain(
                    insertStatus
                )
            }
        } else if status != errSecSuccess {
            throw VisionLinkCredentialError.keychain(status)
        }
    }

    func clear() throws {
        let status = SecItemDelete(
            baseQuery as CFDictionary
        )
        guard status == errSecSuccess
                || status == errSecItemNotFound else {
            throw VisionLinkCredentialError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

nonisolated enum VisionLinkCredentialError:
    Error,
    LocalizedError,
    Equatable
{
    case keychain(OSStatus)
    case corruptData

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let systemMessage = SecCopyErrorMessageString(
                status,
                nil
            ) as String? ?? AppLocalization.format(
                "상태 %lld",
                Int(status)
            )
            return AppLocalization.format(
                "VisionLink 보안 저장소 오류: %@",
                systemMessage
            )
        case .corruptData:
            return AppLocalization.string(
                "저장된 VisionLink 연결 정보가 손상되었습니다."
            )
        }
    }
}
