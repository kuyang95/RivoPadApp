import Combine
import Foundation
import Security

nonisolated protocol WebSearchCredentialStoring:
    Sendable
{
    func readAPIKey() throws -> String?
    func saveAPIKey(_ apiKey: String) throws
    func clearAPIKey() throws
}

nonisolated final class WebSearchCredentialStore:
    WebSearchCredentialStoring,
    @unchecked Sendable
{
    private let service: String
    private let account = "brave-search-api-key"

    init(
        service: String =
            "com.rivo.shortcuts-example.web-search"
    ) {
        self.service = service
    }

    func readAPIKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] =
            kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query as CFDictionary,
            &result
        )
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(
                  data: data,
                  encoding: .utf8
              ) else {
            if status == errSecSuccess {
                throw WebSearchCredentialError
                    .corruptData
            }
            throw WebSearchCredentialError
                .keychain(status)
        }
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? nil : trimmed
    }

    func saveAPIKey(
        _ apiKey: String
    ) throws {
        let data = Data(apiKey.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var insert = baseQuery
            attributes.forEach {
                insert[$0.key] = $0.value
            }
            let insertStatus = SecItemAdd(
                insert as CFDictionary,
                nil
            )
            guard insertStatus == errSecSuccess else {
                throw WebSearchCredentialError
                    .keychain(insertStatus)
            }
        } else if updateStatus
                    != errSecSuccess {
            throw WebSearchCredentialError
                .keychain(updateStatus)
        }
    }

    func clearAPIKey() throws {
        let status = SecItemDelete(
            baseQuery as CFDictionary
        )
        guard status == errSecSuccess
                || status
                    == errSecItemNotFound else {
            throw WebSearchCredentialError
                .keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String:
                kSecClassGenericPassword,
            kSecAttrService as String:
                service,
            kSecAttrAccount as String:
                account,
        ]
    }
}

nonisolated enum WebSearchCredentialError:
    Error,
    LocalizedError,
    Equatable
{
    case emptyAPIKey
    case keychain(OSStatus)
    case corruptData

    var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            return AppLocalization.string(
                "Brave Search API 키를 입력해 주세요."
            )
        case .keychain(let status):
            let message =
                SecCopyErrorMessageString(
                    status,
                    nil
                ) as String?
                ?? AppLocalization.format(
                    "상태 %lld",
                    Int64(status)
                )
            return AppLocalization.format(
                "웹 검색 보안 저장소 오류: %@",
                message
            )
        case .corruptData:
            return AppLocalization.string(
                "저장된 웹 검색 API 키를 읽을 수 없습니다."
            )
        }
    }
}

@MainActor
protocol WebSearchConfigurationProviding:
    AnyObject
{
    var isEnabled: Bool { get }
    var hasAPIKey: Bool { get }
    func apiKey() throws -> String?
}

@MainActor
final class WebSearchConfigurationStore:
    ObservableObject,
    WebSearchConfigurationProviding
{
    private enum Key {
        static let isEnabled =
            "webSearch.enabled.v1"
    }

    static let shared =
        WebSearchConfigurationStore()

    @Published private(set)
    var isEnabled: Bool

    @Published private(set)
    var hasAPIKey: Bool

    private let defaults: UserDefaults
    private let credentials:
        any WebSearchCredentialStoring

    init(
        defaults: UserDefaults = .standard,
        credentials:
            any WebSearchCredentialStoring =
                WebSearchCredentialStore()
    ) {
        self.defaults = defaults
        self.credentials = credentials

        let hasStoredKey =
            ((try? credentials.readAPIKey())
                ?? nil) != nil
        hasAPIKey = hasStoredKey
        isEnabled =
            defaults.bool(
                forKey: Key.isEnabled
            )
            && hasStoredKey
        if !hasStoredKey {
            defaults.set(
                false,
                forKey: Key.isEnabled
            )
        }
    }

    func apiKey() throws -> String? {
        try credentials.readAPIKey()
    }

    func saveAPIKey(
        _ rawValue: String
    ) throws {
        let value = rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !value.isEmpty else {
            throw WebSearchCredentialError
                .emptyAPIKey
        }
        try credentials.saveAPIKey(value)
        hasAPIKey = true
    }

    func removeAPIKey() throws {
        try credentials.clearAPIKey()
        hasAPIKey = false
        setEnabled(false)
    }

    func setEnabled(
        _ enabled: Bool
    ) {
        isEnabled = enabled && hasAPIKey
        defaults.set(
            isEnabled,
            forKey: Key.isEnabled
        )
    }
}
