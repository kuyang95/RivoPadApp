import SwiftUI
import WebKit

struct GoogleSearchEntryPointView:
    UIViewRepresentable
{
    let html: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(
        context: Context
    ) -> WKWebView {
        let configuration =
            WKWebViewConfiguration()
        configuration.websiteDataStore =
            .nonPersistent()
        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor =
            .clear
        webView.scrollView.isScrollEnabled =
            false
        webView.accessibilityLabel =
            AppLocalization.string(
                "Google 검색 제안"
            )
        return webView
    }

    func updateUIView(
        _ webView: WKWebView,
        context: Context
    ) {
        guard context.coordinator
            .loadedHTML != html else {
            return
        }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(
            htmlDocument,
            baseURL: URL(
                string: "https://www.google.com"
            )
        )
    }

    private var htmlDocument: String {
        """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body { margin: 0; padding: 0; background: transparent; overflow: hidden; }
          </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }

    final class Coordinator {
        var loadedHTML: String?
    }
}
