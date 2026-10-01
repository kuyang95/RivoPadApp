import Combine
import Foundation
import Security

@MainActor
protocol WebSearchConfigurationProviding:
    AnyObject
{
    var isEnabled: Bool { get }

    /// Whether AI chat may answer a question that needs live information
    /// with a grounded web search instead of the local model.
    var isAutomaticChatSearchEnabled: Bool { get }
}

extension WebSearchConfigurationProviding {
    var isAutomaticChatSearchEnabled: Bool { false }
}

@MainActor
final class WebSearchConfigurationStore:
    ObservableObject,
    WebSearchConfigurationProviding
{
    private enum Key {
        static let isEnabled =
            "webSearch.enabled.v1"
        static let automaticChatSearch =
            "webSearch.automaticChat.v1"
        static let removedLegacyCredential =
            "webSearch.removedBraveCredential.v1"
    }

    static let shared =
        WebSearchConfigurationStore()

    @Published private(set)
    var isEnabled: Bool

    @Published private(set)
    var isAutomaticChatSearchEnabled: Bool

    private let defaults: UserDefaults

    var isFirebaseConfigured: Bool {
        FirebaseRuntime.isConfigured
    }

    init(
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        // Android runs the web-search check on every free-chat message, so
        // both switches default to on; a stored `false` still wins.
        isEnabled = defaults.object(
            forKey: Key.isEnabled
        ) as? Bool ?? true
        isAutomaticChatSearchEnabled =
            defaults.object(
                forKey: Key.automaticChatSearch
            ) as? Bool ?? true
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
        if !enabled {
            setAutomaticChatSearchEnabled(false)
        }
    }

    func setAutomaticChatSearchEnabled(
        _ enabled: Bool
    ) {
        isAutomaticChatSearchEnabled = enabled
        defaults.set(
            enabled,
            forKey: Key.automaticChatSearch
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
