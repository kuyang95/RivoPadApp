import Combine
import Foundation
import Security

@MainActor
protocol WebSearchConfigurationProviding:
    AnyObject
{
    var isEnabled: Bool { get }
}

@MainActor
final class WebSearchConfigurationStore:
    ObservableObject,
    WebSearchConfigurationProviding
{
    private enum Key {
        static let isEnabled =
            "webSearch.enabled.v1"
        static let removedLegacyCredential =
            "webSearch.removedBraveCredential.v1"
    }

    static let shared =
        WebSearchConfigurationStore()

    @Published private(set)
    var isEnabled: Bool

    private let defaults: UserDefaults

    var isFirebaseConfigured: Bool {
        FirebaseRuntime.isConfigured
    }

    init(
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        isEnabled = defaults.bool(
            forKey: Key.isEnabled
        )
        removeLegacyBraveCredentialIfNeeded()
    }

    func setEnabled(
        _ enabled: Bool
    ) {
        isEnabled = enabled
        defaults.set(
            enabled,
            forKey: Key.isEnabled
        )
    }

    private func removeLegacyBraveCredentialIfNeeded() {
        guard !defaults.bool(
            forKey:
                Key.removedLegacyCredential
        ) else {
            return
        }
        let query: [String: Any] = [
            kSecClass as String:
                kSecClassGenericPassword,
            kSecAttrService as String:
                "com.rivo.shortcuts-example.web-search",
            kSecAttrAccount as String:
                "brave-search-api-key",
        ]
        SecItemDelete(query as CFDictionary)
        defaults.set(
            true,
            forKey:
                Key.removedLegacyCredential
        )
    }
}
