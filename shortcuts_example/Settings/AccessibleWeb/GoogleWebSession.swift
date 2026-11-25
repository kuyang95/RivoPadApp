import Combine
import WebKit

/// Gmail uses the existing YouTube store, preserving its signed-in sessions.
@MainActor
final class GoogleWebSession: ObservableObject {
    static let shared = GoogleWebSession()
    static let store = WKWebsiteDataStore(forIdentifier: EasyYouTubePage.storeIdentifier)
    @Published private(set) var youtubeSignedIn: Bool?
    @Published private(set) var gmailSignedIn: Bool?
    // Status comes from an already opened service or a successful inbox read.
    func update(youtube: Bool, value: Bool) {
        if youtube {
            if youtubeSignedIn != value { youtubeSignedIn = value }
        } else {
            if gmailSignedIn != value { gmailSignedIn = value }
        }
    }

    // Reads login flags and structural mailbox landmarks, never personal content.
    static let statusScript = #"""
    (() => {
      if (location.protocol !== 'https:' || location.port) return 'unknown';
      if (location.hostname === 'accounts.google.com' &&
          document.querySelector('input[type="email"],input[type="password"]')) return 'out';
      if (['m.youtube.com','www.youtube.com','youtube.com'].includes(location.hostname)) {
        const value = window.ytcfg?.get?.('LOGGED_IN');
        return value === true ? 'in' : value === false ? 'out' : 'unknown';
      }
      if (location.hostname === 'mail.google.com') {
        const desktop = /^\/mail\/u\/\d+\/$/.test(location.pathname) &&
          document.querySelector('[role="navigation"]') && document.querySelector('[role="main"]');
        const mobile = /^\/mail\/mu\/mp\/\d+\/$/.test(location.pathname) &&
          document.querySelector('#nav') && document.querySelector('#views #tl_ [role="list"]') &&
          document.querySelector('#tltbt [role="button"]');
        if (desktop || mobile) return 'in';
      }
      return 'unknown';
    })()
    """#
}
