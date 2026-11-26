import Combine
import Foundation
import WebKit

/// Ends sessions in Rivo's selected web data store and retains registered accounts.
@MainActor
final class MailWebLogout: ObservableObject {
    static let shared = MailWebLogout()
    @Published private(set) var storeInProgress: UUID?
    @Published private var versions: [UUID: Int] = [:]

    func version(_ store: UUID) -> Int { versions[store, default: 0] }

    func signOut(_ account: MailAccount) async {
        guard storeInProgress == nil else { return }
        let identifier = account.storeIdentifier
        storeInProgress = identifier
        defer { storeInProgress = nil }
        let store = identifier == EasyYouTubePage.storeIdentifier
            ? GoogleWebSession.store : WKWebsiteDataStore(forIdentifier: identifier)
        await store.removeData(ofTypes: [WKWebsiteDataTypeCookies], modifiedSince: .distantPast)
        versions[identifier] = version(identifier) + 1
        if identifier == EasyYouTubePage.storeIdentifier {
            GoogleWebSession.shared.update(youtube: false, value: false)
            GoogleWebSession.shared.update(youtube: true, value: false)
        }
    }
}
