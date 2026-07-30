import Foundation
import WebKit

@MainActor
final class WebKitRenderedContentLoader:
    NSObject,
    WebRenderedContentLoading,
    WKNavigationDelegate
{
    private static let timeoutSeconds =
        15.0
    private static let settleSeconds =
        2.0

    private var activeID: UUID?
    private var continuation:
        CheckedContinuation<
            WebRenderedContent,
            Error
        >?
    private var webView: WKWebView?
    private var timeoutTask:
        Task<Void, Never>?
    private var settleTask:
        Task<Void, Never>?

    func loadRenderedContent(
        from url: URL
    ) async throws -> WebRenderedContent {
        if let activeID {
            finish(
                id: activeID,
                result:
                    .failure(
                        CancellationError()
                    )
            )
        }

        let id = UUID()
        return try await
            withTaskCancellationHandler {
                try await
                    withCheckedThrowingContinuation {
                        (
                            continuation:
                                CheckedContinuation<
                                    WebRenderedContent,
                                    Error
                                >
                        ) in
                        guard !Task
                            .isCancelled else {
                            continuation
                                .resume(
                                    throwing:
                                        CancellationError()
                                )
                            return
                        }

                        let configuration =
                            WKWebViewConfiguration()
                        configuration
                            .websiteDataStore =
                            .nonPersistent()
                        configuration
                            .defaultWebpagePreferences
                            .allowsContentJavaScript =
                            true

                        let webView = WKWebView(
                            frame: .zero,
                            configuration:
                                configuration
                        )
                        webView
                            .customUserAgent =
                            "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
                        webView
                            .navigationDelegate =
                            self

                        activeID = id
                        self.continuation =
                            continuation
                        self.webView = webView
                        scheduleTimeout(
                            id: id
                        )

                        var request =
                            URLRequest(
                                url: url,
                                cachePolicy:
                                    .reloadIgnoringLocalCacheData,
                                timeoutInterval:
                                    Self
                                    .timeoutSeconds
                            )
                        request.setValue(
                            webView
                                .customUserAgent,
                            forHTTPHeaderField:
                                "User-Agent"
                        )
                        webView.load(request)
                    }
            } onCancel: {
                Task { @MainActor [weak self] in
                    guard let self,
                          self.activeID
                            == id else {
                        return
                    }
                    self.finish(
                        id: id,
                        result:
                            .failure(
                                CancellationError()
                            )
                    )
                }
            }
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation:
            WKNavigation!
    ) {
        guard webView === self.webView,
              let id = activeID else {
            return
        }
        settleTask?.cancel()
        settleTask = Task {
            do {
                try await Task.sleep(
                    for:
                        .seconds(
                            Self
                            .settleSeconds
                        )
                )
                try Task
                    .checkCancellation()
                let script =
                    """
                    (() => JSON.stringify({
                      title: document.title || "",
                      text: document.body
                        ? document.body.innerText
                        : ""
                    }))()
                    """
                let raw = try await
                    webView
                    .evaluateJavaScript(
                        script
                    )
                guard let json = raw
                        as? String,
                      let data = json.data(
                          using: .utf8
                      ),
                      let payload = try?
                        JSONDecoder()
                        .decode(
                            RenderedPayload
                            .self,
                            from: data
                        ),
                      let finalURL =
                        webView.url,
                      let scheme =
                        finalURL.scheme?
                        .lowercased(),
                      scheme == "http"
                        || scheme == "https"
                else {
                    throw WebContentError
                        .emptyContent
                }
                finish(
                    id: id,
                    result:
                        .success(
                            WebRenderedContent(
                                sourceURL:
                                    finalURL,
                                title:
                                    payload
                                    .title,
                                text:
                                    payload
                                    .text
                            )
                        )
                )
            } catch is CancellationError {
                return
            } catch {
                finish(
                    id: id,
                    result:
                        .failure(error)
                )
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation:
            WKNavigation!,
        withError error: Error
    ) {
        failCurrentWebView(
            webView,
            error: error
        )
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation
            navigation: WKNavigation!,
        withError error: Error
    ) {
        failCurrentWebView(
            webView,
            error: error
        )
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction:
            WKNavigationAction,
        decisionHandler:
            @escaping (
                WKNavigationActionPolicy
            ) -> Void
    ) {
        guard navigationAction
                .targetFrame != nil,
              let url =
                navigationAction
                .request.url,
              let scheme =
                url.scheme?
                .lowercased(),
              scheme == "http"
                || scheme == "https" else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webViewWebContentProcessDidTerminate(
        _ webView: WKWebView
    ) {
        failCurrentWebView(
            webView,
            error:
                WebContentError
                .emptyContent
        )
    }

    private func scheduleTimeout(
        id: UUID
    ) {
        timeoutTask?.cancel()
        timeoutTask = Task {
            do {
                try await Task.sleep(
                    for:
                        .seconds(
                            Self
                            .timeoutSeconds
                        )
                )
                try Task
                    .checkCancellation()
                finish(
                    id: id,
                    result:
                        .failure(
                            WebContentError
                            .renderedPageTimedOut
                        )
                )
            } catch {
                return
            }
        }
    }

    private func failCurrentWebView(
        _ webView: WKWebView,
        error: Error
    ) {
        guard webView === self.webView,
              let id = activeID else {
            return
        }
        finish(
            id: id,
            result: .failure(error)
        )
    }

    private func finish(
        id: UUID,
        result:
            Result<
                WebRenderedContent,
                Error
            >
    ) {
        guard activeID == id,
              let continuation else {
            return
        }

        activeID = nil
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        settleTask?.cancel()
        settleTask = nil

        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil

        continuation.resume(
            with: result
        )
    }

    private struct RenderedPayload:
        Decodable
    {
        let title: String
        let text: String
    }
}
