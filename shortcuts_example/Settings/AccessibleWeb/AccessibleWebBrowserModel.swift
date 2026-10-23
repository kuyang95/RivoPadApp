import Combine
import SwiftUI
import Foundation
import UIKit
import WebKit

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
    @Published private(set) var progress = 0.0
    @Published private(set) var hasPopup = false
    @Published private(set) var adBlockEnabled = UserDefaults.standard.object(forKey: "browser.adBlock.enabled") as? Bool ?? true
    func setAdBlockEnabled(_ enabled: Bool) {
        guard !easyYouTube else { return }
        adBlockEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "browser.adBlock.enabled")
        windows.forEach { view in
            installScript(in: view)
            view.evaluateJavaScript("window.__rivoAdBlock?.set(\(enabled));", completionHandler: nil)
        }
        webView.reload()
    }
    private func applyAdBlockRules(to view: WKWebView) {
        guard !easyYouTube else { return }
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
    private static let world = WKContentWorld.world(name: "RivoAccessibleWeb")
    private var activeDialog: UIAlertController?
    private var cancelDialog: (() -> Void)?

    override convenience init() { self.init(easyYouTube: false) }

    init(easyYouTube: Bool, embedded: Bool = false) {
        self.easyYouTube = easyYouTube
        self.embedded = embedded
        let preferredScale = UIFontMetrics(forTextStyle: .body).scaledValue(for: 17) / 17
        let preferredPercent = min(300, max(75, Int((preferredScale * 100).rounded())))
        defaultZoomPercent = preferredPercent
        zoomPercent = preferredPercent
        let configuration = WKWebViewConfiguration()
        // Widgets and standalone screens share login; document viewers retain their own stores.
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: easyYouTube ? EasyYouTubePage.storeIdentifier : Self.browserStoreIdentifier)
        if easyYouTube || embedded { configuration.defaultWebpagePreferences.preferredContentMode = .mobile }
        configuration.allowsInlineMediaPlayback = true
        if easyYouTube { configuration.mediaTypesRequiringUserActionForPlayback = [] }
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        configure(webView)
        windows = [webView]
        observeActiveWindow()
        navigate(easyYouTube ? EasyYouTubePage.home : "https://www.google.com")
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
        installScript(in: view)
        applyZoom(to: view)
    }

    private func installScript(in view: WKWebView) {
        let controller = view.configuration.userContentController
        controller.removeAllUserScripts()
        if embedded {
            controller.addUserScript(WKUserScript(source: AccessibleWebTheme.script + "window.__rivoLauncherBrowser = \(!easyYouTube);window.__rivoLauncherNativeSwipe = true;\n" + LauncherWebAppearance.source + "\nwindow.__rivoLauncherReflow?.setZoom?.(\(Double(zoomPercent)/100));", injectionTime: .atDocumentStart,
                                                 forMainFrameOnly: false, in: .page))
        }
        if easyYouTube {
            controller.addUserScript(WKUserScript(source: AccessibleWebTheme.script + EasyYouTubePage.source, injectionTime: .atDocumentStart,
                                                 forMainFrameOnly: true, in: .page))
            return
        }
        controller.addUserScript(WKUserScript(source: BrowserAdBlocker.script(enabled: adBlockEnabled), injectionTime: .atDocumentStart,
                                             forMainFrameOnly: false, in: .page))
        applyAdBlockRules(to: view)
        controller.addUserScript(WKUserScript(
            source: AccessibleWebAppearance.bootstrap(enabled: appearanceEnabled, palette: palette) + "\n" + AccessibleGooglePage.bootstrap(enabled: simpleGoogleEnabled, appearanceEnabled: appearanceEnabled, palette: palette),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: Self.world
        ))
    }

    func applyAppearance() {
        guard !easyYouTube else { return }
        for window in windows {
            window.overrideUserInterfaceStyle = palette == .dark ? .dark : .light
            installScript(in: window)
            window.evaluateJavaScript(
                "window.__rivoAccessibleWeb?.set(\(AccessibleWebAppearance.configuration(enabled: appearanceEnabled, palette: palette)));" + AccessibleGooglePage.bootstrap(enabled: simpleGoogleEnabled, appearanceEnabled: appearanceEnabled, palette: palette),
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
        if view === webView { zoomPercent = percent }
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
        webView.load(URLRequest(url: url))
    }

    @discardableResult func goBack() -> Bool {
        if webView.canGoBack { webView.goBack(); return true }
        if hasPopup { closePopup(); return true }
        return false
    }

    func handleBack(onExhausted: @escaping () -> Void) {
        guard easyYouTube else { if !goBack() { onExhausted() }; return }
        let view = webView
        view.evaluateJavaScript("window.__rivoYouTubePrototype?.back?.() === true") { [weak self] result, _ in
            guard let self, self.webView === view else { return }
            if result as? Bool != true && !self.goBack() { onExhausted() }
        }
    }

    func reloadOrStop() {
        if webView.isLoading { webView.stopLoading() }
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
        observeActiveWindow()
        errorMessage = nil
    }

    func resetExitRequest() { exitRequested = false }

    private var youtubeContentActive = true
    func setContentActive(_ active: Bool) {
        youtubeContentActive = active
        if active && !easyYouTube { applyAppearance() }
        if easyYouTube { webView.evaluateJavaScript("window.__rivoYouTubeContentActive=\(active);window.__rivoYouTubePrototype?.setActive?.(\(active));", completionHandler: nil) }
    }
    func pauseMedia() {
        setContentActive(false)
        webView.evaluateJavaScript("window.__rivoOfficialPlayer?.pause?.();(function pause(root){root.querySelectorAll('video,audio').forEach(v=>v.pause());root.querySelectorAll('iframe').forEach(f=>f.contentWindow?.postMessage(JSON.stringify({event:'command',func:'pauseVideo',args:[]}),'*'));root.querySelectorAll('*').forEach(e=>{if(e.shadowRoot)pause(e.shadowRoot)});})(document);", completionHandler: nil)
    }

    func shutdown() {
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
            webView.observe(\.isLoading, options: [.new]) { view, _ in update(view) },
            webView.observe(\.estimatedProgress, options: [.new]) { view, _ in update(view) }
        ]
        syncState()
    }

    private func syncState() {
        currentAddress = webView.url?.absoluteString ?? (easyYouTube ? EasyYouTubePage.home : "https://www.google.com")
        hasPopup = windows.count > 1
        canGoBack = webView.canGoBack || hasPopup
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
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
        if webView === self.webView { errorMessage = nil }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        applyZoom(to: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === self.webView { setContentActive(youtubeContentActive) }
        applyZoom(to: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(error, from: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error, from: webView)
    }

    private func report(_ error: Error, from view: WKWebView) {
        guard view === webView, (error as NSError).code != NSURLErrorCancelled else { return }
        errorMessage = "페이지를 열지 못했습니다. \(error.localizedDescription)"
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
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
