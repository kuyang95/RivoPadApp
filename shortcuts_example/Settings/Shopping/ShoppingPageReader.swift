#if DEBUG
import Foundation
import WebKit

/** A single temporary browser, behind the local UI and excluded from accessibility navigation. */
@MainActor
final class ShoppingPageReader: NSObject, WKNavigationDelegate {
    private let source: ShoppingSource
    private let container: UIView
    private let view: WKWebView
    private var failed = false
    private var upgraded = false
    init(source: ShoppingSource, container: UIView, store: WKWebsiteDataStore) {
        self.source = source; self.container = container
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.defaultWebpagePreferences.preferredContentMode = .recommended
        view = WKWebView(frame: container.bounds, configuration: config)
        super.init()
        view.navigationDelegate = self
        view.isUserInteractionEnabled = false; view.accessibilityElementsHidden = true
        container.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor), view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor), view.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
    }

    func read(_ query: String, partial: ([String: Any]) -> Void) async throws -> [String: Any] {
        defer { view.stopLoading(); view.navigationDelegate = nil; view.removeFromSuperview() }
        view.load(URLRequest(url: source.searchURL(query)))
        let deadline = Date().addingTimeInterval(24)
        let core = ShoppingWebAssets.files["shopping-core.js"] ?? ""
        let extractor = ShoppingWebAssets.files["shopping-extract.js"] ?? ""
        let script = "(function(){const module=undefined;const require=undefined;\n\(core)\n\(extractor)\nreturn JSON.stringify(window.RivoShoppingExtract.extract('\(source.rawValue)',document));})()"
        var last: [String: Any]?
        var previous = ""
        var stable = 0
        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(900))
            if failed { throw ShoppingPageError() }
            guard let url = view.url, source.allows(url), !view.isLoading else { continue }
            guard let raw = try? await view.evaluateJavaScript(script) as? String, raw.utf8.count <= 400_000,
                  let data = raw.data(using: .utf8), let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            guard result["state"] as? String == "ready", let products = result["products"] as? [[String: Any]] else { continue }
            let signature = products.compactMap { $0["key"] as? String }.joined(separator: "|")
            if signature == previous { stable += 1 } else { previous = signature; stable = 0 }
            last = result
            if !products.isEmpty && stable == 0 { partial(result) }
            if stable >= 1 { return result }
        }
        if let last { return last }
        throw ShoppingPageError()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame?.isMainFrame == true, !upgraded, let url = navigationAction.request.url, let target = source.upgradeSearch(url) {
            upgraded = true; decisionHandler(.cancel); webView.load(URLRequest(url: target)); return
        }
        if navigationAction.targetFrame?.isMainFrame == true, let url = navigationAction.request.url, !source.allows(url) { failed = true; decisionHandler(.cancel) }
        else { decisionHandler(.allow) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse, response.statusCode >= 400 { failed = true; decisionHandler(.cancel) }
        else { decisionHandler(.allow) }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed = true }
}
#endif
