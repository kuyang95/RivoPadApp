import Combine
import SwiftUI
import Foundation
import UIKit
import WebKit

enum MailReaderAction: String, CaseIterable {
    case reply, read, delete, more, favorite, unfavorite

    var title: String {
        switch self {
        case .reply: AppLocalization.string("답장")
        case .read: AppLocalization.string("읽음 상태 변경")
        case .delete: AppLocalization.string("삭제")
        case .more: AppLocalization.string("더보기")
        case .favorite: AppLocalization.string("즐겨찾기 추가")
        case .unfavorite: AppLocalization.string("즐겨찾기 해제")
        }
    }
}

struct MailReaderActions {
    let address: URL
    let ticket: String
    let options: [MailReaderAction]
}

enum AccessibleWebAddress {
    static func isGoogleSearchPage(_ text: String) -> Bool {
        guard let url = URL(string: text), url.scheme == "https", let host = url.host?.lowercased(),
              ["google.com", "www.google.com", "google.co.kr", "www.google.co.kr"].contains(host) else { return false }
        return ["", "/", "/webhp", "/search"].contains(url.path)
    }
    static func isGoogleHome(_ text: String) -> Bool { isGoogleSearchPage(text) && URL(string: text)?.path != "/search" }

    static func isWebURL(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false
    }

    static func resolve(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), isWebURL(url) { return url }
        // Never execute a pasted javascript:, file:, data: or custom-app URL.
        let hostWithPort = text.range(of: #"^(?:localhost|[^/\s:]+\.[^/\s:]+):[0-9]+(?:[/?#]|$)"#, options: .regularExpression) != nil
        if !hostWithPort, text.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]*:"#, options: .regularExpression) != nil { return nil }
        if !text.contains(where: \.isWhitespace), text.contains(".") || hostWithPort,
           let url = URL(string: "https://" + text), isWebURL(url) { return url }
        var search = URLComponents(string: "https://www.google.com/search")!
        search.queryItems = [URLQueryItem(name: "q", value: text)]
        return search.url
    }
}

@MainActor
final class AccessibleWebBrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let easyMail: Bool
    let easyYouTube: Bool
    private let embedded: Bool
    var onLauncherPageTurn: ((Int) -> Void)?
    var onLauncherPageDrag: ((CGFloat) -> Void)?
    var onLauncherPageDragEnd: ((Bool) -> Void)?
    @Published private(set) var exitRequested = false
    @Published private(set) var webView: WKWebView
    @Published private(set) var currentAddress = "https://www.google.com"
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    private var youtubeNavigation = 0
    @Published private(set) var youtubeReady = false
    @Published private(set) var youtubePlaybackLoading = false
    @Published private(set) var newsAwaitingDocument = false
    @Published private(set) var progress = 0.0
    @Published private(set) var hasPopup = false
    @Published private(set) var adBlockEnabled = UserDefaults.standard.object(forKey: "browser.adBlock.enabled") as? Bool ?? true
    func setAdBlockEnabled(_ enabled: Bool) {
        guard !easyYouTube && !easyMail else { return }
        adBlockEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "browser.adBlock.enabled")
        windows.forEach { view in
            installScript(in: view)
            view.evaluateJavaScript("window.__rivoAdBlock?.set(\(enabled));", completionHandler: nil)
        }
        webView.reload()
    }
    private func applyAdBlockRules(to view: WKWebView) {
        guard !easyYouTube && !easyMail else { return }
        BrowserAdBlocker.prepare { [weak self, weak view] rules in
            guard let self, let view, let rules else { return }
            let controller = view.configuration.userContentController
            controller.remove(rules)
            if self.adBlockEnabled { controller.add(rules) }
        }
    }
    @Published var simpleGoogleEnabled = true
    @Published var appearanceEnabled = true
    @Published var palette: AccessibleWebPalette = .dark
    func voiceSearchAllowed(_ address: String? = nil) -> Bool {
        let address = address ?? currentAddress
        if easyYouTube {
            guard let url = URL(string: address), url.scheme == "https", let host = url.host,
                  ["m.youtube.com", "www.youtube.com", "youtube.com"].contains(host) else { return false }
            return !url.path.hasPrefix("/embed/") && url.path != "/signin"
        }
        return simpleGoogleEnabled && AccessibleWebAddress.isGoogleSearchPage(address)
    }
    func performVoiceSearch(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, voiceSearchAllowed() else { return }
        if easyYouTube {
            var url = URLComponents(string: "https://m.youtube.com/results")!
            url.queryItems = [URLQueryItem(name: "search_query", value: query)]
            if let url = url.url { navigate(url.absoluteString) }
        } else { navigate(query) }
    }
    @Published var favoriteAddRequested = false
    func addFavorite(name: String, url: String) async -> Bool {
        let saved = await BrowserFavorites.add(name: name, address: url)
        if saved { applyAppearance() }
        return saved
    }
    @Published var voiceSearchRequested = false
    @Published var errorMessage: String?

    // Page zoom preferences remain local to each open screen.
    let defaultZoomPercent: Int
    @Published private(set) var zoomPercent: Int
    private var siteZoom: [String: Int] = [:]
    private var windows: [WKWebView] = []
    private var launcherSwipes: [ObjectIdentifier: LauncherWebPageSwipe] = [:]
    func launcherSwipe(for view: WKWebView) -> LauncherWebPageSwipe? { launcherSwipes[ObjectIdentifier(view)] }
    private var observations: [NSKeyValueObservation] = []
    private static let browserStoreIdentifier = UUID(uuidString: "382B897A-44FB-49CB-9A93-FCDA0D815DB1")!
    private static var youtubeStore: WKWebsiteDataStore { GoogleWebSession.store }
    private static let world = WKContentWorld.world(name: "RivoAccessibleWeb")
    private var activeDialog: UIAlertController?
    private var cancelDialog: (() -> Void)?

    override convenience init() { self.init(easyYouTube: false) }

    @Published private(set) var mailEnhanced = true
    @Published private(set) var mailReaderActions: MailReaderActions?
    private var mailActionsRequest = 0

    private func resetMailReaderActions() {
        mailActionsRequest += 1
        mailReaderActions = nil
    }

    private func requestMailReaderActions(in view: WKWebView) {
        guard easyMail, mailEnhanced, !mailStart, youtubeContentActive, view === webView,
              mailReaderActions == nil, let address = view.url,
              address.scheme == "https", address.port == nil, address.user == nil,
              let host = address.host, ["mail.naver.com", "m.mail.naver.com"].contains(host),
              address.path.hasPrefix("/v2/read/") else { return }
        mailActionsRequest += 1
        let request = mailActionsRequest
        view.evaluateJavaScript("window.__rivoMailActions?.snapshot()") { [weak self, weak view] result, _ in
            guard let self, let view, request == self.mailActionsRequest, view === self.webView,
                  view.url == address, self.youtubeContentActive, let result = result as? [String: Any],
                  let ticket = result["ticket"] as? String, UUID(uuidString: ticket) != nil,
                  let ids = result["ids"] as? [String] else { return }
            let options = MailReaderAction.allCases.filter { ids.contains($0.rawValue) }
            if !options.isEmpty { self.mailReaderActions = MailReaderActions(address: address, ticket: ticket, options: options) }
        }
    }

    func finishMailReaderActions(_ action: MailReaderAction? = nil) {
        guard let dialog = mailReaderActions else { return }
        resetMailReaderActions()
        guard youtubeContentActive, webView.url == dialog.address,
              action.map(dialog.options.contains) ?? true else { return }
        webView.evaluateJavaScript("window.__rivoMailActions?.finish('\(dialog.ticket)','\(action?.rawValue ?? "")')",
                                   completionHandler: nil)
    }

    func toggleMailAppearance() {
        resetMailReaderActions()
        mailEnhanced.toggle()
        windows.forEach { $0.evaluateJavaScript(mailBootstrap, completionHandler: nil) }
    }
    private var mailBootstrap: String {
        let signIn = GoogleSignInPage.source + "\n" + NaverMailLoginAppearance.source + "\n" + MailSecurityPage.source
            + "\n" + EasyMailPage.officialForm
            + "\nwindow.__rivoNaverMailLogin?.set(\(mailEnhanced));window.__rivoMailSecurity?.set(\(mailEnhanced));window.__rivoOfficialMailForm?.setEnhanced(\(mailEnhanced));"
        let theme = AccessibleWebTheme.colors
        let reader = EasyMailPage.source
            .replacingOccurrences(of: "__RIVO_MAIL_ACTION_FILL__", with: AccessibleWebTheme.hex(theme.searchFill(colorKey: "lemon")))
            .replacingOccurrences(of: "__RIVO_MAIL_ACTION_INK__", with: AccessibleWebTheme.hex(theme.ink))
        return AccessibleWebTheme.script + signIn + "\n" + reader
            + "\nif(window.__rivoMailHost){" + AccessibleWebAppearance.source
            + "\nwindow.__rivoMailAppearance?.set(\(mailEnhanced));}"
    }
    var mailSignIn: Bool {
        guard easyMail, !mailStart, let url = URL(string: currentAddress), url.scheme == "https", let host = url.host else { return false }
        return mailProvider?.authHosts.contains(host) == true
    }
    @Published private(set) var mailDirectConnection = false
    @Published private(set) var mailInbox = false
    @Published private(set) var mailAccounts: [MailAccount] = []
    @Published var mailInboxResults: [MailInboxKey: MailInboxResult] = [:]
    private var mailStoreIdentifier = EasyMailPage.storeIdentifier
    @Published var mailChoosingProvider = false
    @Published var mailEntryEditing = false
    @Published private(set) var mailStart = true
    @Published private(set) var mailProvider: EasyMailProvider?
    @Published private(set) var mailAddressHint = ""

    @Published private(set) var mailPasswordRequired = false
    @Published private(set) var mailAuthenticating = false
    @Published private(set) var mailLoginError: String?
    private var mailRestoring = false
    @Published private(set) var naverMailBlocksInput = false
    var mailLoginHidesWeb: Bool { mailAuthenticating && (mailRestoring || mailProvider?.id != "naver") }
    private let mailLogin = MailNativeLogin()

    func cancelMailLogin() {
        mailLogin.cancel()
        mailRestoring = false
        mailAuthenticating = false
        naverMailBlocksInput = false
        mailPasswordRequired = mailProvider?.nativeIdentifier(mailAddressHint) != nil
        mailStart = true
        mailLoginError = nil
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    func signInMail(password: String) {
        guard mailPasswordRequired, let provider = mailProvider, let identifier = provider.nativeIdentifier(mailAddressHint),
              !password.isEmpty, youtubeContentActive else { return }
        mailLoginError = nil
        mailPasswordRequired = false
        naverMailBlocksInput = provider.id == "naver"
        mailAuthenticating = true
        mailStart = false
        mailLogin.start(view: webView, provider: provider, identifier: identifier, password: password,
                        navigate: { navigate(provider.home) },
                        onForegroundBlocking: { [weak self] in self?.naverMailBlocksInput = $0 },
                        done: { [weak self] in self?.finishMailLogin($0) })
    }

    private func finishMailLogin(_ result: MailLoginResult) {
        let wasRestoring = mailRestoring
        mailRestoring = false
        mailAuthenticating = false
        naverMailBlocksInput = false
        if mailProvider?.id == "naver", !wasRestoring || mailAddressHint.isEmpty {
            if case .failed = result, errorMessage == nil {
                errorMessage = String(localized: "로그인을 완료하지 못했어요. 다시 시도해 주세요.")
            }
            return
        }
        switch result {
        case .content: break
        case .challenge: break
        case .needsAddress, .rejected, .failed:
            mailPasswordRequired = mailProvider?.nativeIdentifier(mailAddressHint) != nil
            mailStart = true
            switch result {
            case .rejected:
                mailLoginError = mailProvider?.id == "daum"
                    ? String(localized: "다음 메일 주소와 카카오계정 주소가 다르면 카카오계정 주소로 다시 시도해 주세요.")
                    : String(localized: "로그인하지 못했어요. 주소와 비밀번호를 확인해 주세요.")
            case .failed: mailLoginError = String(localized: "로그인을 완료하지 못했어요. 다시 시도해 주세요.")
            default: mailLoginError = nil
            }
            if wasRestoring { mailLoginError = nil }
            if !mailPasswordRequired { mailAddressHint = "" }
            webView.stopLoading()
            webView.loadHTMLString("", baseURL: nil)
        }
    }

    func showNaverConnection() {
        guard mailProvider?.id == "naver" else { return }
        mailPasswordRequired = false
        webView.stopLoading()
        mailDirectConnection = true
        mailStart = true
    }

    func showNaverWebMail() {
        guard let provider = mailProvider, provider.id == "naver" else { return }
        openMail(provider, address: mailAddressHint)
    }

    func rememberNaverMailLink() {
        UserDefaults.standard.set("naver", forKey: "easyMail.provider")
    }

    func openMail(_ provider: EasyMailProvider, address: String = "") {
        openMailAccount(MailAccounts.account(provider, address: address.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    func openMailAccount(_ account: MailAccount, target: String? = nil, compose: Bool = false) {
        guard MailWebLogout.shared.storeInProgress != account.storeIdentifier else { return }
        if account.storeIdentifier == EasyYouTubePage.storeIdentifier {
            googleLogoutVersion = MailWebLogout.shared.version(account.storeIdentifier)
        }
        resetMailReaderActions()
        let provider = account.provider
        let address = account.address
        mailInbox = false
        mailAccounts = MailAccounts.all()
        if target == nil, !compose {
            // Opening webmail can restore a session or make a failed account readable again.
            mailInboxResults = mailInboxResults.filter { key, result in
                if case .loaded = result { return true }
                return key.accountID != account.id
            }
        }
        mailLogin.cancel()
        mailRestoring = false
        mailAuthenticating = false
        naverMailBlocksInput = false
        mailPasswordRequired = false
        mailLoginError = nil
        while hasPopup { closePopup() }
        if mailStoreIdentifier != account.storeIdentifier {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            launcherSwipes.removeValue(forKey: ObjectIdentifier(webView))
            mailStoreIdentifier = account.storeIdentifier
            webView = WKWebView(frame: .zero, configuration: Self.mailConfiguration(account.storeIdentifier))
            configure(webView)
            windows = [webView]
            observeActiveWindow()
        }
        mailProvider = provider
        mailAddressHint = address.trimmingCharacters(in: .whitespacesAndNewlines)
        mailChoosingProvider = false
        mailDirectConnection = false
        mailStart = false
        errorMessage = nil
        if account.id != "google-session" {
            let defaults = UserDefaults.standard
            defaults.set(provider.id == "custom" ? nil : provider.id, forKey: "easyMail.provider")
            defaults.set(provider.nativeIdentifier(mailAddressHint) == nil ? nil : mailAddressHint, forKey: "easyMail.address")
            defaults.removeObject(forKey: "easyMail.naverAddress")
        }
        if compose && provider.id == "naver" {
            navigate("https://mail.naver.com/v2/new")
        } else if let target {
            navigate(target)
        } else if provider.id == "gmail", !address.isEmpty {
            var url = URLComponents(string: "https://mail.google.com/mail/")!
            url.queryItems = [URLQueryItem(name: "authuser", value: address)]
            if let url = url.url { navigate(url.absoluteString) }
        } else if !provider.nativeInboxHosts.isEmpty, provider.id != "naver" || !mailAddressHint.isEmpty {
            mailRestoring = true
            mailAuthenticating = true
            mailLogin.start(view: webView, provider: provider, identifier: nil, password: nil,
                            navigate: { navigate(provider.home) }, done: { [weak self] in self?.finishMailLogin($0) })
        } else {
            navigate(provider.home)
        }
    }

    func restoreMail() {
        mailAccounts = MailAccounts.all()
        let accountIDs = Set(mailAccounts.map(\.id))
        mailInboxResults = mailInboxResults.filter { accountIDs.contains($0.key.accountID) }
    }

    func showMailInbox() {
        showMailStart()
        restoreMail()
        mailInbox = !mailAccounts.isEmpty
    }

    private static func mailConfiguration(_ identifier: UUID) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = identifier == EasyYouTubePage.storeIdentifier
            ? GoogleWebSession.store : WKWebsiteDataStore(forIdentifier: identifier)
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.allowsInlineMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        return configuration
    }

    func showMailStart() {
        resetMailReaderActions()
        mailInbox = false
        mailLogin.cancel()
        mailRestoring = false
        mailAuthenticating = false
        naverMailBlocksInput = false
        mailPasswordRequired = false
        mailLoginError = nil
        mailDirectConnection = false
        mailStart = true; mailChoosingProvider = false; mailAddressHint = ""; errorMessage = nil
        while hasPopup { closePopup() }
        webView.stopLoading(); webView.load(URLRequest(url: URL(string: "about:blank")!))
    }
    let newsArticle: Bool
    @Published private(set) var aiPlatform: EasyAIPlatform?
    @Published private(set) var showsAIHome = false

    private func showAIHome() { showsAIHome = true }

    func openAIPlatform(_ platform: EasyAIPlatform) {
        UserDefaults.standard.set(platform.rawValue, forKey: "ai.lastPlatform")
        if aiPlatform != platform {
            if aiPlatform != nil {
                while hasPopup { closePopup() }
                let previous = webView
                let next = WKWebView(frame: .zero, configuration: previous.configuration)
                previous.navigationDelegate = nil
                previous.uiDelegate = nil
                previous.stopLoading()
                configure(next)
                windows = [next]
                webView = next
                observeActiveWindow()
            }
            aiPlatform = platform
            navigate(platform.address)
        }
        showsAIHome = false
    }

    let aiWeb: Bool
    private var usesBrowserPreparation: Bool { !easyYouTube && !easyMail && !newsArticle && !aiWeb }

    init(easyYouTube: Bool, embedded: Bool = false, newsArticle: Bool = false, easyMail: Bool = false,
         aiWeb: Bool = false, initialQuery: String? = nil) {
        self.newsArticle = newsArticle
        self.aiWeb = aiWeb
        self.easyYouTube = easyYouTube
        self.easyMail = easyMail
        self.embedded = embedded
        let preferredScale = UIFontMetrics(forTextStyle: .body).scaledValue(for: 17) / 17
        let preferredPercent = min(300, max(75, Int((preferredScale * 100).rounded())))
        defaultZoomPercent = preferredPercent
        zoomPercent = preferredPercent
        let configuration = easyMail ? Self.mailConfiguration(EasyMailPage.storeIdentifier) : WKWebViewConfiguration()
        // Widgets and standalone screens share login; document viewers retain their own stores.
        if easyYouTube {
            configuration.websiteDataStore = Self.youtubeStore
        } else if !easyMail {
            configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.browserStoreIdentifier)
        }
        if easyYouTube || easyMail || embedded || aiWeb { configuration.defaultWebpagePreferences.preferredContentMode = .mobile }
        configuration.allowsInlineMediaPlayback = true
        if easyYouTube { configuration.mediaTypesRequiringUserActionForPlayback = [] }
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        self.newsAwaitingDocument = newsArticle
        configure(webView)
        windows = [webView]
        observeActiveWindow()
        if easyMail {
            restoreMail()
            mailInbox = !mailAccounts.isEmpty
        } else if aiWeb {
            if let saved = UserDefaults.standard.string(forKey: "ai.lastPlatform"),
               let platform = EasyAIPlatform(rawValue: saved) {
                openAIPlatform(platform)
            } else {
                showAIHome()
            }
        }
        if let initialQuery {
            if usesBrowserPreparation, let url = AccessibleWebAddress.resolve(initialQuery) {
                currentAddress = url.absoluteString
            }
            navigate(initialQuery)
        } else if !easyMail && !aiWeb && !newsArticle {
            navigate(easyYouTube ? EasyYouTubePage.home : "https://www.google.com")
        }
    }

    private func configure(_ view: WKWebView) {
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = !embedded
        view.scrollView.keyboardDismissMode = .onDrag
        view.overrideUserInterfaceStyle = easyYouTube || palette == .dark ? .dark : .light
        if !embedded {
            view.backgroundColor = UIColor(AccessibleWebTheme.colors.background)
            view.scrollView.backgroundColor = view.backgroundColor
        }
        if embedded {
            launcherSwipes[ObjectIdentifier(view)] = LauncherWebPageSwipe(webView: view,
                drag: { [weak self, weak view] distance in
                    guard let self, view === self.webView else { return }
                    self.onLauncherPageDrag?(distance)
                }, end: { [weak self, weak view] cancelled in
                    guard let self, view === self.webView, let callback = self.onLauncherPageDragEnd else { return false }
                    callback(cancelled); return true
                }) { [weak self, weak view] direction in
                guard let self, view === self.webView else { return }
                self.onLauncherPageTurn?(direction)
            }
            view.isOpaque = false
            view.backgroundColor = .clear
            view.scrollView.backgroundColor = .clear
        }
        if aiWeb {
            view.isOpaque = false
            view.backgroundColor = .clear
            view.scrollView.backgroundColor = .clear
        }
        installScript(in: view)
        applyZoom(to: view)
    }

    private func installScript(in view: WKWebView) {
        let controller = view.configuration.userContentController
        controller.removeAllUserScripts()
        if embedded {
            controller.addUserScript(WKUserScript(source: AccessibleWebTheme.script + "window.__rivoLauncherBrowser = \(!easyYouTube && !easyMail);window.__rivoLauncherNativeSwipe = true;window.__rivoLauncherMail = \(easyMail);\n" + LauncherWebAppearance.source + "\nwindow.__rivoLauncherReflow?.setZoom?.(\(Double(zoomPercent)/100));", injectionTime: .atDocumentStart,
                                                 forMainFrameOnly: false, in: .page))
        }
        if easyMail {
            controller.addUserScript(WKUserScript(source: mailBootstrap,
                injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
            return
        }
        if easyYouTube {
            controller.addUserScript(WKUserScript(source: youTubeBootstrap, injectionTime: .atDocumentStart,
                                                 forMainFrameOnly: true, in: .page))
            return
        }
        controller.addUserScript(WKUserScript(source: BrowserAdBlocker.script(enabled: adBlockEnabled), injectionTime: .atDocumentStart,
                                             forMainFrameOnly: false, in: .page))
        applyAdBlockRules(to: view)
        controller.addUserScript(WKUserScript(
            source: AccessibleWebAppearance.bootstrap(enabled: appearanceEnabled, palette: palette, aiWeb: aiWeb) + "\n" + (newsArticle ? NewsArticlePage.source + "\nwindow.__rivoNewsArticle?.set(\(appearanceEnabled));\n" : "") + AccessibleGooglePage.bootstrap(enabled: simpleGoogleEnabled, appearanceEnabled: appearanceEnabled, palette: palette) + (aiWeb ? "\n" + GoogleSignInPage.source + "\n" + EasyAIPage.bootstrap(enabled: appearanceEnabled, palette: palette) : ""),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: Self.world
        ))
        if usesBrowserPreparation {
            controller.addUserScript(WKUserScript(
                source: BrowserPagePreparation.bootstrap(appearanceEnabled: appearanceEnabled, simpleGoogleEnabled: simpleGoogleEnabled,
                                                         palette: palette, embedded: embedded),
                injectionTime: .atDocumentStart, forMainFrameOnly: true, in: Self.world
            ))
        }
    }

    private var youTubeBootstrap: String {
        let preparing = embedded && !youtubeReady && !youtubePlaybackLoading
        return "window.__rivoYouTubeUIScale=\(Double(zoomPercent) / 100);window.__rivoYouTubeNativePreparing=\(preparing);\n"
            + AccessibleWebTheme.script + GoogleSignInPage.source + EasyYouTubePage.source
            + "\nwindow.__rivoYouTubePrototype?.setNativePreparing?.(\(preparing));"
    }

    func applyAppearance() {
        guard !easyYouTube && !easyMail else { return }
        for window in windows {
            window.overrideUserInterfaceStyle = palette == .dark ? .dark : .light
            installScript(in: window)
            window.evaluateJavaScript(
                "window.__rivoAccessibleWeb?.set(\(AccessibleWebAppearance.configuration(enabled: appearanceEnabled, palette: palette)));window.__rivoNewsArticle?.set(\(appearanceEnabled));" + AccessibleGooglePage.bootstrap(enabled: simpleGoogleEnabled, appearanceEnabled: appearanceEnabled, palette: palette) + (aiWeb ? "\n" + EasyAIPage.bootstrap(enabled: appearanceEnabled, palette: palette) : ""),
                in: nil, in: Self.world
            ) { _ in }
        }
    }

    private func host(_ url: URL?) -> String? {
        guard let url, AccessibleWebAddress.isWebURL(url) else { return nil }
        return url.host?.lowercased()
    }

    private func applyZoom(to view: WKWebView) {
        let percent = host(view.url).flatMap { siteZoom[$0] } ?? defaultZoomPercent
        let scale = CGFloat(percent) / 100
        if embedded && !easyYouTube {
            // Keep proportional CSS zoom without rewriting the authored layout.
            // WK pageZoom retains a wider minimum layout canvas on some sites.
            if abs(view.pageZoom - 1) > 0.001 { view.pageZoom = 1 }
            view.evaluateJavaScript("window.__rivoLauncherReflow?.setZoom?.(\(scale))", completionHandler: nil)
        } else if abs(view.pageZoom - scale) > 0.001 { view.pageZoom = scale }
        if easyYouTube {
            view.evaluateJavaScript("window.__rivoYouTubeUIScale=\(scale);window.__rivoYouTubePrototype?.setUIScale?.(\(scale));", completionHandler: nil)
        }
        if view === webView && zoomPercent != percent { zoomPercent = percent }
    }

    func changeZoom(increase: Bool) {
        let next = increase ? (zoomPercent / 25 + 1) * 25 : ((zoomPercent - 1) / 25) * 25
        setZoom(next)
    }

    func setZoom(_ percent: Int) {
        guard let key = host(webView.url) else { return }
        if siteZoom.count >= 256, siteZoom[key] == nil { siteZoom.removeValue(forKey: siteZoom.keys.sorted()[0]) }
        siteZoom[key] = min(300, max(75, percent))
        windows.forEach { applyZoom(to: $0) }
    }

    func resetZoom() {
        if let key = host(webView.url) { siteZoom.removeValue(forKey: key) }
        windows.forEach { applyZoom(to: $0) }
    }

    func navigate(_ input: String) {
        guard let url = AccessibleWebAddress.resolve(input) else {
            errorMessage = "웹 주소(http/https) 또는 검색어를 입력해 주세요."
            return
        }
        errorMessage = nil
        if newsArticle { newsAwaitingDocument = true }
        webView.load(URLRequest(url: url))
    }

    @discardableResult func goBack() -> Bool {
        if (easyMail || aiWeb) && webView.backForwardList.backItem?.url.absoluteString == "about:blank" { return false }
        if webView.canGoBack { webView.goBack(); return true }
        if hasPopup { closePopup(); return true }
        return false
    }

    func aiInitialPageReady(in view: WKWebView) async -> Bool {
        let script = """
        document.readyState !== 'loading' && location.href !== 'about:blank' &&
        (location.hostname !== 'chatgpt.com' || /^\\/(auth|api|backend-api)(\\/|$)/.test(location.pathname) ||
        window.__rivoEasyAI?.ready?.() === true)
        """
        let result = try? await view.evaluateJavaScript(script, in: nil, contentWorld: Self.world)
        return view === webView && (result as? Bool == true)
    }

    func handleBack(onExhausted: @escaping () -> Void) {
        if aiWeb {
            if showsAIHome {
                onExhausted()
                return
            }
            let view = webView
            view.evaluateJavaScript("window.__rivoEasyAI?.back?.() === true", in: nil, in: Self.world) { [weak self] result in
                guard let self, self.webView === view else { return }
                if case .success(let handled) = result, handled as? Bool == true { return }
                if !self.goBack() { self.showAIHome() }
            }
            return
        }
        if easyMail {
            if mailReaderActions != nil { finishMailReaderActions() }
            else if mailInbox { onExhausted() }
            else if mailAuthenticating { cancelMailLogin() }
            else if mailStart && mailChoosingProvider { mailChoosingProvider = false }
            else if mailStart && mailAccounts.isEmpty && !mailPasswordRequired && !mailDirectConnection { onExhausted() }
            else { showMailInbox() }
            return
        }
        guard easyYouTube else { if !goBack() { onExhausted() }; return }
        let view = webView
        view.evaluateJavaScript("window.__rivoYouTubePrototype?.back?.() === true") { [weak self] result, _ in
            guard let self, self.webView === view else { return }
            guard result as? Bool != true else { return }
            let url = view.url
            let atHome = url?.scheme == "https" &&
                ["m.youtube.com", "www.youtube.com", "youtube.com"].contains(url?.host ?? "") &&
                ["", "/"].contains(url?.path ?? "")
            // Tab switches and sign-in redirects remain in WebKit history even at home.
            if atHome {
                if self.hasPopup { self.closePopup() } else { onExhausted() }
            } else if !self.goBack() { onExhausted() }
        }
    }

    func reloadOrStop() {
        if webView.isLoading {
            webView.stopLoading()
            if usesBrowserPreparation {
                webView.evaluateJavaScript("window.__rivoBrowserPreparation?.finish()", in: nil, in: Self.world) { _ in }
            }
        }
        else { errorMessage = nil; webView.reload() }
    }

    func closePopup() {
        guard windows.count > 1 else { return }
        dismissDialog()
        let closed = windows.removeLast()
        launcherSwipes.removeValue(forKey: ObjectIdentifier(closed))
        closed.stopLoading()
        closed.navigationDelegate = nil
        closed.uiDelegate = nil
        webView = windows.last!
        youtubePlaybackLoading = false
        observeActiveWindow()
        errorMessage = nil
    }

    func resetExitRequest() { exitRequested = false }

    @Published private(set) var youtubeContentActive = true
    private var googleStatusRequest = 0
    private var googleSessionClosed = false

    private var googleLogoutVersion = MailWebLogout.shared.version(EasyYouTubePage.storeIdentifier)

    private func reloadYouTubeAfterLogout() -> Bool {
        let version = MailWebLogout.shared.version(EasyYouTubePage.storeIdentifier)
        guard easyYouTube, version != googleLogoutVersion else { return false }
        googleLogoutVersion = version
        googleStatusRequest += 1
        for view in windows {
            view.stopLoading()
            view.navigationDelegate = nil
            view.uiDelegate = nil
            launcherSwipes.removeValue(forKey: ObjectIdentifier(view))
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = Self.youtubeStore
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        configure(webView)
        windows = [webView]
        observeActiveWindow()
        youtubeReady = false
        youtubePlaybackLoading = false
        navigate(EasyYouTubePage.home)
        return true
    }

    private func refreshGoogleLoginStatus(reconnect: Bool = false) {
        googleStatusRequest += 1
        guard !googleSessionClosed, youtubeContentActive,
              easyYouTube || (easyMail && !mailStart && !mailInbox && mailProvider?.id == "gmail") else { return }
        pollGoogleLoginStatus(in: webView, request: googleStatusRequest,
                              logoutVersion: googleLogoutVersion, reconnect: reconnect)
    }

    private func pollGoogleLoginStatus(in view: WKWebView, request: Int, logoutVersion: Int, reconnect: Bool = false) {
        let serviceHosts = easyYouTube ? ["m.youtube.com", "www.youtube.com", "youtube.com"] : ["mail.google.com"]
        guard request == googleStatusRequest, !googleSessionClosed, youtubeContentActive, view === webView,
              MailWebLogout.shared.storeInProgress != EasyYouTubePage.storeIdentifier,
              logoutVersion == MailWebLogout.shared.version(EasyYouTubePage.storeIdentifier),
              let url = view.url, url.scheme == "https", url.port == nil, url.user == nil,
              let host = url.host, host == "accounts.google.com" || serviceHosts.contains(host) else { return }
        view.evaluateJavaScript(GoogleWebSession.statusScript) { [weak self, weak view] result, _ in
            guard let self, let view, request == self.googleStatusRequest, !self.googleSessionClosed,
                  self.youtubeContentActive, view === self.webView, view.url == url,
                  MailWebLogout.shared.storeInProgress != EasyYouTubePage.storeIdentifier,
                  logoutVersion == MailWebLogout.shared.version(EasyYouTubePage.storeIdentifier) else { return }
            let value: Bool? = (result as? String) == "in" ? true : (result as? String) == "out" ? false : nil
            if let value { GoogleWebSession.shared.update(youtube: self.easyYouTube, value: value) }
            if reconnect, self.easyYouTube, value == false, GoogleWebSession.shared.gmailSignedIn == true,
               ["m.youtube.com", "www.youtube.com", "youtube.com"].contains(host), ["", "/"].contains(url.path) {
                self.navigate(EasyYouTubePage.home + "signin")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self, weak view] in
                guard let self, let view else { return }
                self.pollGoogleLoginStatus(in: view, request: request, logoutVersion: logoutVersion)
            }
        }
    }

    func setContentActive(_ active: Bool) {
        let resuming = active && !youtubeContentActive
        if easyMail && !active { resetMailReaderActions() }
        if !active && mailAuthenticating && !mailRestoring {
            if mailProvider?.id == "naver" && !naverMailBlocksInput {
                mailLogin.cancel()
                finishMailLogin(.challenge)
            } else {
                cancelMailLogin()
            }
        }
        youtubeContentActive = active
        if active, reloadYouTubeAfterLogout() { return }
        refreshGoogleLoginStatus(reconnect: resuming)
        if active && !easyYouTube { applyAppearance() }
        if easyYouTube { webView.evaluateJavaScript("window.__rivoYouTubeContentActive=\(active);window.__rivoYouTubePrototype?.setActive?.(\(active));", completionHandler: nil) }
    }
    func pauseMedia() {
        setContentActive(false)
        webView.evaluateJavaScript("window.__rivoOfficialPlayer?.pause?.();(function pause(root){root.querySelectorAll('video,audio').forEach(v=>v.pause());root.querySelectorAll('iframe').forEach(f=>f.contentWindow?.postMessage(JSON.stringify({event:'command',func:'pauseVideo',args:[]}),'*'));root.querySelectorAll('*').forEach(e=>{if(e.shadowRoot)pause(e.shadowRoot)});})(document);", completionHandler: nil)
    }

    func shutdown() {
        googleSessionClosed = true
        googleStatusRequest += 1
        youtubeNavigation += 1
        mailLogin.cancel()
        dismissDialog()
        observations.removeAll()
        launcherSwipes.removeAll()
        windows.forEach {
            $0.stopLoading()
            $0.navigationDelegate = nil
            $0.uiDelegate = nil
        }
    }

    private func observeActiveWindow() {
        observations.removeAll()
        // WebKit callbacks can occur while SwiftUI is updating the hierarchy.
        let update: (WKWebView) -> Void = { [weak self] view in
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, view === self.webView else { return }
                self.syncState()
            }
        }
        observations = [
            webView.observe(\.url, options: [.new]) { view, _ in update(view) },
            webView.observe(\.canGoBack, options: [.new]) { view, _ in update(view) },
            webView.observe(\.canGoForward, options: [.new]) { view, _ in update(view) },
            webView.observe(\.isLoading, options: [.new]) { view, _ in update(view) }
        ]
        if easyYouTube {
            observations.append(webView.observe(\.estimatedProgress, options: [.new]) { view, _ in update(view) })
        }
        syncState()
    }

    private func syncState() {
        let address = webView.url?.absoluteString ?? (usesBrowserPreparation && windows.count == 1
            ? currentAddress : easyYouTube ? EasyYouTubePage.home : "https://www.google.com")
        if currentAddress != address { currentAddress = address }
        if let dialog = mailReaderActions, dialog.address != webView.url { resetMailReaderActions() }
        let popup = windows.count > 1
        if hasPopup != popup { hasPopup = popup }
        let canNavigateBack = webView.canGoBack || popup
        if canGoBack != canNavigateBack { canGoBack = canNavigateBack }
        if canGoForward != webView.canGoForward { canGoForward = webView.canGoForward }
        if isLoading != webView.isLoading { isLoading = webView.isLoading }
        if easyYouTube && progress != webView.estimatedProgress { progress = webView.estimatedProgress }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.absoluteString == "rivo-browser://mail-actions" {
            decisionHandler(.cancel)
            if navigationAction.sourceFrame.isMainFrame, navigationAction.targetFrame?.isMainFrame == true {
                requestMailReaderActions(in: webView)
            }
            return
        }
        if url.absoluteString == "rivo-browser://add-favorite" {
            if !easyYouTube, simpleGoogleEnabled, navigationAction.targetFrame?.isMainFrame == true,
               navigationAction.sourceFrame.isMainFrame, webView === self.webView, AccessibleWebAddress.isGoogleHome(webView.url?.absoluteString ?? "") { favoriteAddRequested = true }
            decisionHandler(.cancel)
            return
        }
        if url.absoluteString == "rivo-browser://voice", navigationAction.targetFrame?.isMainFrame == true {
            if navigationAction.sourceFrame.isMainFrame, webView === self.webView,
               voiceSearchAllowed(webView.url?.absoluteString ?? "") { voiceSearchRequested = true }
            decisionHandler(.cancel)
            return
        }
        if embedded, webView === self.webView, navigationAction.targetFrame?.isMainFrame == true,
           url.host == "page", url.scheme == "rivo-launcher" || (easyYouTube && url.scheme == "rivo-easy-youtube") {
            if url.path == "/next" { onLauncherPageTurn?(1) }
            else if url.path == "/previous" { onLauncherPageTurn?(-1) }
            decisionHandler(.cancel)
            return
        }
        if easyYouTube, navigationAction.targetFrame?.isMainFrame != false, url.absoluteString == EasyYouTubePage.closeURL {
            exitRequested = true
            decisionHandler(.cancel)
            return
        }
        let localChildFrame = navigationAction.targetFrame?.isMainFrame == false &&
            (["data", "blob"].contains(url.scheme ?? "") || url.absoluteString == "about:srcdoc")
        if AccessibleWebAddress.isWebURL(url) || url.absoluteString == "about:blank" || localChildFrame {
            if easyYouTube && webView === self.webView && navigationAction.targetFrame?.isMainFrame == true {
                youtubePlaybackLoading = isYouTubePlaybackURL(url)
            }
            decisionHandler(.allow)
        } else {
            if webView === self.webView, navigationAction.targetFrame?.isMainFrame != false {
                errorMessage = "외부 앱 전용 링크는 여기서 열 수 없습니다. 필요한 경우 Safari에서 이어서 이용해 주세요."
            }
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.canShowMIMEType { decisionHandler(.allow) }
        else {
            if webView === self.webView, navigationResponse.isForMainFrame {
                errorMessage = "이 파일 형식은 브라우저에서 표시할 수 없습니다. Safari에서 열어 주세요."
            }
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if easyYouTube && webView === self.webView {
            youtubeNavigation += 1
        }
        if easyMail && webView === self.webView { resetMailReaderActions() }
        if webView === self.webView {
            if errorMessage != nil { errorMessage = nil }
            if newsArticle { newsAwaitingDocument = true }
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if easyYouTube && webView === self.webView { youtubePlaybackLoading = isYouTubePlaybackURL(webView.url) }
        if newsArticle && webView === self.webView { newsAwaitingDocument = false }
        applyZoom(to: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if easyMail && !mailStart {
            webView.evaluateJavaScript(mailBootstrap, completionHandler: nil)
            if !mailAuthenticating, let script = mailProvider?.hintScript(address: mailAddressHint, url: webView.url), !script.isEmpty {
                webView.evaluateJavaScript(script, completionHandler: nil)
            }
        }
        if easyYouTube {
            let script = youTubeBootstrap
            if (embedded && !youtubeReady) || youtubePlaybackLoading, webView === self.webView,
               let url = webView.url, AccessibleWebAddress.isWebURL(url) {
                let navigation = youtubeNavigation
                webView.evaluateJavaScript(script) { [weak self, weak webView] _, _ in
                    guard let self, let webView else { return }
                    if self.embedded && !self.youtubeReady { self.awaitYouTubeReady(in: webView, url: url, navigation: navigation) }
                    if self.youtubePlaybackLoading { self.awaitYouTubePlayback(in: webView, url: url, navigation: navigation) }
                }
            } else {
                webView.evaluateJavaScript(script, completionHandler: nil)
            }
        }
        if webView === self.webView && !usesBrowserPreparation {
            setContentActive(youtubeContentActive)
        }
        applyZoom(to: webView)
    }

    private func awaitYouTubeReady(in view: WKWebView, url: URL, navigation: Int, attempt: Int = 0) {
        guard isWaitingForYouTubeReady(in: view, url: url, navigation: navigation) else { return }

        // Official sign-in and consent pages do not have the simplified account gate.
        if !["m.youtube.com", "www.youtube.com", "youtube.com"].contains(url.host ?? "") ||
            url.path == "/signin" || url.path.hasPrefix("/embed/") {
            youtubeReady = true
            return
        }
        view.evaluateJavaScript("window.__rivoYouTubePrototype?.startupReady?.() === true") { [weak self, weak view] result, _ in
            guard let self, let view, self.isWaitingForYouTubeReady(in: view, url: url, navigation: navigation) else { return }
            if result as? Bool == true {
                self.youtubeReady = true
                view.evaluateJavaScript("window.__rivoYouTubePrototype?.setNativePreparing?.(false);", completionHandler: nil)
            } else if attempt < 96 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak view] in
                    guard let self, let view else { return }
                    self.awaitYouTubeReady(in: view, url: url, navigation: navigation, attempt: attempt + 1)
                }
            } else {
                self.errorMessage = AppLocalization.string("유튜브를 준비하지 못했어요. 다시 시도해 주세요.")
            }
        }
    }

    private func awaitYouTubePlayback(in view: WKWebView, url: URL, navigation: Int, attempt: Int = 0) {
        guard isWaitingForYouTubePlayback(in: view, url: url, navigation: navigation) else { return }
        view.evaluateJavaScript("window.__rivoYouTubePrototype?.playbackReady?.() === true") { [weak self, weak view] result, _ in
            guard let self, let view, self.isWaitingForYouTubePlayback(in: view, url: url, navigation: navigation) else { return }
            if result as? Bool == true || attempt >= 96 { self.youtubePlaybackLoading = false }
            else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak view] in
                    guard let self, let view else { return }
                    self.awaitYouTubePlayback(in: view, url: url, navigation: navigation, attempt: attempt + 1)
                }
            }
        }
    }

    private func isYouTubePlaybackURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && ["m.youtube.com", "www.youtube.com", "youtube.com"].contains(url.host ?? "") && url.path == "/watch"
    }

    private func isWaitingForYouTubePlayback(in view: WKWebView, url: URL, navigation: Int) -> Bool {
        youtubePlaybackLoading && errorMessage == nil && view === webView && view.url == url &&
            youtubeNavigation == navigation && windows.contains { $0 === view }
    }

    private func isWaitingForYouTubeReady(in view: WKWebView, url: URL, navigation: Int) -> Bool {
        !youtubeReady && errorMessage == nil && view === webView && view.url == url && youtubeNavigation == navigation
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(error, from: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error, from: webView)
    }

    private func report(_ error: Error, from view: WKWebView) {
        guard view === webView, (error as NSError).code != NSURLErrorCancelled else { return }
        youtubePlaybackLoading = false
        newsAwaitingDocument = false
        if mailAuthenticating { mailLogin.fail(); return }
        errorMessage = "페이지를 열지 못했습니다. \(error.localizedDescription)"
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === self.webView { youtubePlaybackLoading = false }
        if webView === self.webView && mailAuthenticating { mailLogin.fail(); return }
        if webView === self.webView { errorMessage = "웹페이지 실행이 중단되었습니다. 새로고침해 주세요." }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil, windows.count < 5 else { return nil }
        // Use WebKit's configuration so opener/postMessage and login popups work.
        let popup = WKWebView(frame: .zero, configuration: configuration)
        configure(popup)
        windows.append(popup)
        self.webView = popup
        observeActiveWindow()
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView === self.webView { closePopup() }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        if webView === self.webView && mailLoginHidesWeb && mailProvider?.id != "naver" {
            completionHandler()
            mailLogin.reject()
            return
        }
        let alert = dialog(message, frame: frame)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { [weak self] _ in
            self?.cancelDialog = nil
            completionHandler()
        })
        present(alert, from: webView, cancel: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = dialog(message, frame: frame)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel) { [weak self] _ in
            self?.cancelDialog = nil
            completionHandler(false)
        })
        alert.addAction(UIAlertAction(title: "확인", style: .default) { [weak self] _ in
            self?.cancelDialog = nil
            completionHandler(true)
        })
        present(alert, from: webView) { completionHandler(false) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = dialog(prompt, frame: frame)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "취소", style: .cancel) { [weak self] _ in
            self?.cancelDialog = nil
            completionHandler(nil)
        })
        alert.addAction(UIAlertAction(title: "확인", style: .default) { [weak self, weak alert] _ in
            self?.cancelDialog = nil
            completionHandler(alert?.textFields?.first?.text)
        })
        present(alert, from: webView) { completionHandler(nil) }
    }

    private func dialog(_ message: String, frame: WKFrameInfo) -> UIAlertController {
        UIAlertController(title: frame.securityOrigin.host, message: message, preferredStyle: .alert)
    }

    private func present(_ alert: UIAlertController, from view: WKWebView, cancel: @escaping () -> Void) {
        guard view === webView, activeDialog?.presentingViewController == nil,
              var presenter = view.window?.rootViewController else { cancel(); return }
        while let next = presenter.presentedViewController { presenter = next }
        activeDialog = alert
        cancelDialog = cancel
        presenter.present(alert, animated: true)
    }

    private func dismissDialog() {
        let cancel = cancelDialog
        cancelDialog = nil
        activeDialog?.dismiss(animated: false)
        activeDialog = nil
        cancel?()
    }
}
