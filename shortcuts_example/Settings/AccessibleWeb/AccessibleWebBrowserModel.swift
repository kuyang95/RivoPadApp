#if DEBUG
import Combine
import Foundation
import UIKit
import WebKit

enum AccessibleWebAddress {
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
        var search = URLComponents(string: "https://search.naver.com/search.naver")!
        search.queryItems = [URLQueryItem(name: "query", value: text)]
        return search.url
    }
}

@MainActor
final class AccessibleWebBrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var webView: WKWebView
    @Published private(set) var currentAddress = "https://www.naver.com"
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var progress = 0.0
    @Published private(set) var hasPopup = false
    @Published var appearanceEnabled = true
    @Published var palette: AccessibleWebPalette = .dark
    @Published var errorMessage: String?

    private var windows: [WKWebView] = []
    private var observations: [NSKeyValueObservation] = []
    private static let world = WKContentWorld.world(name: "RivoAccessibleWeb")
    private var activeDialog: UIAlertController?
    private var cancelDialog: (() -> Void)?

    override init() {
        let configuration = WKWebViewConfiguration()
        // Keep this experimental browser separate from document viewers and
        // their trusted local content. Logins work for the lifetime of the screen.
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        configure(webView)
        windows = [webView]
        observeActiveWindow()
        navigate("https://www.naver.com")
    }

    private func configure(_ view: WKWebView) {
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.scrollView.keyboardDismissMode = .onDrag
        installScript(in: view)
    }

    private func installScript(in view: WKWebView) {
        let controller = view.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(
            source: AccessibleWebAppearance.bootstrap(enabled: appearanceEnabled, palette: palette),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: Self.world
        ))
    }

    func applyAppearance() {
        for window in windows {
            installScript(in: window)
            window.evaluateJavaScript(
                "window.__rivoAccessibleWeb?.set(\(AccessibleWebAppearance.configuration(enabled: appearanceEnabled, palette: palette)));",
                in: nil, in: Self.world
            ) { _ in }
        }
    }

    func navigate(_ input: String) {
        guard let url = AccessibleWebAddress.resolve(input) else {
            errorMessage = "웹 주소(http/https) 또는 검색어를 입력해 주세요."
            return
        }
        errorMessage = nil
        webView.load(URLRequest(url: url))
    }

    func goBack() {
        if webView.canGoBack { webView.goBack() }
        else if hasPopup { closePopup() }
    }

    func reloadOrStop() {
        if webView.isLoading { webView.stopLoading() }
        else { errorMessage = nil; webView.reload() }
    }

    func closePopup() {
        guard windows.count > 1 else { return }
        dismissDialog()
        let closed = windows.removeLast()
        closed.stopLoading()
        closed.navigationDelegate = nil
        closed.uiDelegate = nil
        webView = windows.last!
        observeActiveWindow()
        errorMessage = nil
    }

    func shutdown() {
        dismissDialog()
        observations.removeAll()
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
        currentAddress = webView.url?.absoluteString ?? ""
        hasPopup = windows.count > 1
        canGoBack = webView.canGoBack || hasPopup
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
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
#endif
