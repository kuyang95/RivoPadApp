import Foundation
import SwiftUI
import WebKit

nonisolated enum EPUBOriginalPublicationLink:
    Equatable,
    Sendable
{
    case publication(
        path: String,
        fragment: String?
    )
    case external(URL)
    case blocked
}

nonisolated enum EPUBOriginalResourcePolicy {
    static let scheme = "rivo-epub"
    static let host = "book"

    private static let resourceTypes:
        [String: (mimeType: String, encoding: String?)] =
    [
        "css": ("text/css", "utf-8"),
        "png": ("image/png", nil),
        "jpg": ("image/jpeg", nil),
        "jpeg": ("image/jpeg", nil),
        "gif": ("image/gif", nil),
        "webp": ("image/webp", nil),
        "svg": ("image/svg+xml", "utf-8"),
        "bmp": ("image/bmp", nil),
        "tif": ("image/tiff", nil),
        "tiff": ("image/tiff", nil),
        "ttf": ("font/ttf", nil),
        "otf": ("font/otf", nil),
        "woff": ("font/woff", nil),
        "woff2": ("font/woff2", nil),
    ]

    static func archivePath(
        forResourceURL url: URL
    ) -> String? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host else {
            return nil
        }
        guard let path = normalizedArchivePath(
            from: url
        ),
        resourceDescription(for: path) != nil else {
            return nil
        }
        return path
    }

    static func resourceDescription(
        for path: String
    ) -> (
        mimeType: String,
        encoding: String?
    )? {
        let pathExtension = URL(
            fileURLWithPath: path
        )
        .pathExtension
        .lowercased()
        return resourceTypes[pathExtension]
    }

    static func classifyLink(
        _ url: URL
    ) -> EPUBOriginalPublicationLink {
        let schemeValue =
            url.scheme?.lowercased()
        if schemeValue == scheme,
           url.host?.lowercased() == host,
           let path = normalizedArchivePath(
               from: url
           ) {
            return .publication(
                path: path,
                fragment:
                    url.fragment?
                    .removingPercentEncoding
                    ?? url.fragment
            )
        }
        if schemeValue == "https"
            || schemeValue == "http" {
            return .external(url)
        }
        return .blocked
    }

    static func publicationURL(
        for chapterPath: String
    ) -> URL? {
        guard let normalized =
                try? EPUBArchive.normalizedPath(
                    chapterPath
                ) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/" + normalized
        return components.url
    }

    private static func normalizedArchivePath(
        from url: URL
    ) -> String? {
        let rawPath = String(
            url.path.drop(
                while: { $0 == "/" }
            )
        )
        guard !rawPath.isEmpty,
              !rawPath.contains("\0") else {
            return nil
        }
        return try? EPUBArchive.normalizedPath(
            rawPath.removingPercentEncoding
                ?? rawPath
        )
    }
}

nonisolated struct EPUBOriginalMarkupStyle:
    Equatable,
    Sendable
{
    let backgroundColor: String
    let foregroundColor: String
    let linkColor: String
    let fontScale: Double
    let lineHeight: Double
}

nonisolated enum EPUBOriginalMarkupRenderer {
    static func document(
        sourceMarkup: String,
        style: EPUBOriginalMarkupStyle
    ) -> String {
        var markup = removingPublisherBaseAndCSP(
            from: sourceMarkup
        )
        let injection = """
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src \(EPUBOriginalResourcePolicy.scheme): data:; style-src 'unsafe-inline' \(EPUBOriginalResourcePolicy.scheme):; font-src \(EPUBOriginalResourcePolicy.scheme): data:; media-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; script-src 'none'; base-uri 'none'; form-action 'none'">
        <style id="rivo-reader-style">
        :root {
          color-scheme: light dark;
          background: \(style.backgroundColor);
          color: \(style.foregroundColor);
        }
        html, body {
          min-height: 100%;
          background: \(style.backgroundColor) !important;
          color: \(style.foregroundColor) !important;
          -webkit-text-size-adjust: 100%;
        }
        body {
          box-sizing: border-box;
          max-width: 860px;
          margin: 0 auto !important;
          padding: 28px 32px 64px !important;
          font-family: -apple-system, BlinkMacSystemFont, sans-serif !important;
          font-size: \(22 * style.fontScale)px !important;
          line-height: \(style.lineHeight) !important;
          overflow-wrap: anywhere;
        }
        img, svg {
          max-width: 100% !important;
          height: auto !important;
        }
        table {
          display: block;
          max-width: 100%;
          overflow-x: auto;
          border-collapse: collapse;
        }
        th, td {
          padding: 0.35em 0.5em;
          border: 1px solid currentColor;
          vertical-align: top;
        }
        ul, ol {
          padding-inline-start: 1.6em;
        }
        dtbook, frontmatter, bodymatter, rearmatter,
        level, level1, level2, level3, level4, level5, level6,
        prodnote, note, annotation, sidebar, imggroup {
          display: block;
        }
        hd {
          display: block;
          margin: 0.8em 0 0.4em;
          font-weight: 700;
        }
        pre, code {
          white-space: pre-wrap;
          overflow-wrap: anywhere;
        }
        a {
          color: \(style.linkColor) !important;
          text-decoration: underline;
        }
        script, iframe, frame, object, embed, form, audio, video {
          display: none !important;
        }
        .rivo-reader-position {
          outline: 3px solid #FF9500 !important;
          outline-offset: 4px;
          border-radius: 4px;
        }
        </style>
        """
        if let headEnd = markup.range(
            of: "</head>",
            options: .caseInsensitive
        ) {
            markup.insert(
                contentsOf: injection,
                at: headEnd.lowerBound
            )
            return markup
        }
        if let bodyStart = firstTagRange(
            named: "body",
            in: markup
        ) {
            markup.insert(
                contentsOf:
                    "<head>\(injection)</head>",
                at: bodyStart.lowerBound
            )
            return markup
        }
        return """
        <!doctype html>
        <html>
        <head>\(injection)</head>
        <body>\(markup)</body>
        </html>
        """
    }

    private static func removingPublisherBaseAndCSP(
        from source: String
    ) -> String {
        var result = replacing(
            pattern: #"<base\b[^>]*>"#,
            in: source,
            with: ""
        )
        result = replacing(
            pattern:
                #"<meta\b[^>]*http-equiv\s*=\s*['"]?content-security-policy['"]?[^>]*>"#,
            in: result,
            with: ""
        )
        return result
    }

    private static func firstTagRange(
        named name: String,
        in text: String
    ) -> Range<String.Index>? {
        guard let expression =
                try? NSRegularExpression(
                    pattern: "<\(name)\\b[^>]*>",
                    options: [
                        .caseInsensitive,
                        .dotMatchesLineSeparators,
                    ]
                ),
              let match = expression.firstMatch(
                  in: text,
                  range: NSRange(
                      text.startIndex...,
                      in: text
                  )
              ) else {
            return nil
        }
        return Range(match.range, in: text)
    }

    private static func replacing(
        pattern: String,
        in text: String,
        with replacement: String
    ) -> String {
        guard let expression =
                try? NSRegularExpression(
                    pattern: pattern,
                    options: [
                        .caseInsensitive,
                        .dotMatchesLineSeparators,
                    ]
                ) else {
            return text
        }
        return expression.stringByReplacingMatches(
            in: text,
            range: NSRange(
                text.startIndex...,
                in: text
            ),
            withTemplate: replacement
        )
    }
}

private struct EPUBOriginalResource:
    Sendable
{
    let data: Data
    let mimeType: String
    let encoding: String?
}

@MainActor
private final class EPUBOriginalResourceSchemeHandler:
    NSObject,
    WKURLSchemeHandler
{
    private let archive: EPUBArchive
    private var tasks:
        [ObjectIdentifier: Task<Void, Never>] =
        [:]

    init(archive: EPUBArchive) {
        self.archive = archive
    }

    func webView(
        _ webView: WKWebView,
        start urlSchemeTask:
            any WKURLSchemeTask
    ) {
        let identifier = ObjectIdentifier(
            urlSchemeTask as AnyObject
        )
        guard let url =
                urlSchemeTask.request.url,
              let path =
                EPUBOriginalResourcePolicy
                .archivePath(
                    forResourceURL: url
                ),
              let description =
                EPUBOriginalResourcePolicy
                .resourceDescription(
                    for: path
                ) else {
            urlSchemeTask.didFailWithError(
                URLError(.unsupportedURL)
            )
            return
        }
        let archive = self.archive
        tasks[identifier] = Task {
            do {
                let resource =
                    try await Task.detached(
                        priority: .userInitiated
                    ) {
                        EPUBOriginalResource(
                            data:
                                try archive.data(
                                    at: path
                                ),
                            mimeType:
                                description
                                .mimeType,
                            encoding:
                                description
                                .encoding
                        )
                    }.value
                guard !Task.isCancelled,
                      self.tasks[
                          identifier
                      ] != nil else {
                    return
                }
                let response = URLResponse(
                    url: url,
                    mimeType:
                        resource.mimeType,
                    expectedContentLength:
                        resource.data.count,
                    textEncodingName:
                        resource.encoding
                )
                urlSchemeTask.didReceive(
                    response
                )
                urlSchemeTask.didReceive(
                    resource.data
                )
                urlSchemeTask.didFinish()
                self.tasks[
                    identifier
                ] = nil
            } catch {
                guard !Task.isCancelled,
                      self.tasks[
                          identifier
                      ] != nil else {
                    return
                }
                urlSchemeTask.didFailWithError(
                    error
                )
                self.tasks[
                    identifier
                ] = nil
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        stop urlSchemeTask:
            any WKURLSchemeTask
    ) {
        let identifier = ObjectIdentifier(
            urlSchemeTask as AnyObject
        )
        tasks.removeValue(
            forKey: identifier
        )?.cancel()
    }

    func cancelAll() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
    }
}

struct EPUBOriginalLayoutView:
    UIViewRepresentable
{
    let archive: EPUBArchive
    let chapter: EPUBChapter
    let segmentCount: Int
    let navigationRevision: Int
    let targetSegmentIndex: Int
    let style: EPUBOriginalMarkupStyle
    let onVisibleSegment: (Int) -> Void
    let onNavigationFinished:
        (Int, Int) -> Void
    let onLink: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            archive: archive,
            onVisibleSegment:
                onVisibleSegment,
            onNavigationFinished:
                onNavigationFinished,
            onLink: onLink
        )
    }

    func makeUIView(
        context: Context
    ) -> WKWebView {
        let controller =
            WKUserContentController()
        controller.addUserScript(
            WKUserScript(
                source:
                    Coordinator.bridgeScript,
                injectionTime:
                    .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        controller.add(
            context.coordinator,
            name: Coordinator.scrollHandler
        )
        controller.add(
            context.coordinator,
            name: Coordinator.linkHandler
        )

        let configuration =
            WKWebViewConfiguration()
        configuration
            .userContentController =
            controller
        configuration.websiteDataStore =
            .nonPersistent()
        configuration
            .defaultWebpagePreferences
            .allowsContentJavaScript =
            false
        configuration.setURLSchemeHandler(
            context.coordinator
                .resourceHandler,
            forURLScheme:
                EPUBOriginalResourcePolicy
                .scheme
        )

        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )
        webView.navigationDelegate =
            context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView
            .contentInsetAdjustmentBehavior =
            .automatic
        return webView
    }

    func updateUIView(
        _ webView: WKWebView,
        context: Context
    ) {
        context.coordinator.update(
            from: self,
            webView: webView
        )
    }

    static func dismantleUIView(
        _ webView: WKWebView,
        coordinator: Coordinator
    ) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration
            .userContentController
            .removeScriptMessageHandler(
                forName:
                    Coordinator
                    .scrollHandler
            )
        webView.configuration
            .userContentController
            .removeScriptMessageHandler(
                forName:
                    Coordinator
                    .linkHandler
            )
        coordinator.resourceHandler
            .cancelAll()
    }

    @MainActor
    final class Coordinator:
        NSObject,
        WKNavigationDelegate,
        WKScriptMessageHandler
    {
        static let scrollHandler =
            "rivoReaderScroll"
        static let linkHandler =
            "rivoReaderLink"

        fileprivate let resourceHandler:
            EPUBOriginalResourceSchemeHandler
        private var onVisibleSegment:
            (Int) -> Void
        private var onNavigationFinished:
            (Int, Int) -> Void
        private var onLink:
            (URL) -> Void
        private var documentKey: String?
        private var segmentCount = 0
        private var fragmentIndexes:
            [String: Int] = [:]
        private var pendingNavigation:
            (revision: Int, segment: Int)?
        private var lastNavigationRevision:
            Int?

        init(
            archive: EPUBArchive,
            onVisibleSegment:
                @escaping (Int) -> Void,
            onNavigationFinished:
                @escaping (Int, Int) -> Void,
            onLink:
                @escaping (URL) -> Void
        ) {
            resourceHandler =
                EPUBOriginalResourceSchemeHandler(
                    archive: archive
                )
            self.onVisibleSegment =
                onVisibleSegment
            self.onNavigationFinished =
                onNavigationFinished
            self.onLink = onLink
        }

        func update(
            from view:
                EPUBOriginalLayoutView,
            webView: WKWebView
        ) {
            onVisibleSegment =
                view.onVisibleSegment
            onNavigationFinished =
                view.onNavigationFinished
            onLink = view.onLink
            segmentCount = max(
                view.segmentCount,
                1
            )
            fragmentIndexes =
                view.chapter
                .fragmentSegmentIndexes
            let key = [
                view.chapter.href,
                String(
                    view.chapter.sourceMarkup?
                        .hashValue
                        ?? 0
                ),
                view.style.backgroundColor,
                view.style.foregroundColor,
                view.style.linkColor,
                String(view.style.fontScale),
                String(view.style.lineHeight),
            ].joined(separator: "|")
            if documentKey != key {
                documentKey = key
                pendingNavigation = (
                    view.navigationRevision,
                    view.targetSegmentIndex
                )
                lastNavigationRevision =
                    view.navigationRevision
                let document =
                    EPUBOriginalMarkupRenderer
                    .document(
                        sourceMarkup:
                            view.chapter
                            .sourceMarkup
                            ?? view.chapter.text,
                        style: view.style
                    )
                webView.loadHTMLString(
                    document,
                    baseURL:
                        EPUBOriginalResourcePolicy
                        .publicationURL(
                            for:
                                view.chapter.href
                        )
                )
                return
            }
            guard lastNavigationRevision
                    != view.navigationRevision else {
                return
            }
            lastNavigationRevision =
                view.navigationRevision
            configureAndNavigate(
                webView: webView,
                revision:
                    view.navigationRevision,
                segment:
                    view.targetSegmentIndex
            )
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation:
                WKNavigation?
        ) {
            let navigation =
                pendingNavigation
                ?? (
                    lastNavigationRevision ?? 0,
                    0
                )
            pendingNavigation = nil
            configureAndNavigate(
                webView: webView,
                revision:
                    navigation.revision,
                segment:
                    navigation.segment
            )
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction:
                WKNavigationAction,
            preferences:
                WKWebpagePreferences,
            decisionHandler:
                @escaping (
                    WKNavigationActionPolicy,
                    WKWebpagePreferences
                ) -> Void
        ) {
            preferences
                .allowsContentJavaScript =
                false
            if navigationAction
                .navigationType
                == .linkActivated,
               let url =
                    navigationAction.request.url {
                onLink(url)
                decisionHandler(
                    .cancel,
                    preferences
                )
                return
            }
            let scheme =
                navigationAction.request.url?
                .scheme?
                .lowercased()
            if scheme == nil
                || scheme == "about"
                || scheme
                    == EPUBOriginalResourcePolicy
                    .scheme {
                decisionHandler(
                    .allow,
                    preferences
                )
            } else {
                decisionHandler(
                    .cancel,
                    preferences
                )
            }
        }

        func userContentController(
            _ userContentController:
                WKUserContentController,
            didReceive message:
                WKScriptMessage
        ) {
            switch message.name {
            case Self.scrollHandler:
                if let number =
                        message.body
                        as? NSNumber {
                    onVisibleSegment(
                        min(
                            max(
                                number.intValue,
                                0
                            ),
                            max(
                                segmentCount - 1,
                                0
                            )
                        )
                    )
                }
            case Self.linkHandler:
                if let value =
                        message.body
                        as? String,
                   let url = URL(
                       string: value
                   ) {
                    onLink(url)
                }
            default:
                break
            }
        }

        private func configureAndNavigate(
            webView: WKWebView,
            revision: Int,
            segment: Int
        ) {
            let mapJSON =
                Self.json(
                    fragmentIndexes
                )
            let target = min(
                max(segment, 0),
                max(segmentCount - 1, 0)
            )
            let script = """
            window.__rivoReader.configure(\(segmentCount), \(mapJSON));
            window.__rivoReader.scrollToSegment(\(target));
            """
            webView.evaluateJavaScript(
                script
            ) { [weak self] _, _ in
                self?
                    .onNavigationFinished(
                        revision,
                        target
                    )
            }
        }

        private static func json(
            _ value: [String: Int]
        ) -> String {
            guard JSONSerialization
                    .isValidJSONObject(
                        value
                    ),
                  let data =
                    try? JSONSerialization
                    .data(
                        withJSONObject: value,
                        options: []
                    ),
                  let string = String(
                      data: data,
                      encoding: .utf8
                  ) else {
                return "{}"
            }
            return string
        }

        static let bridgeScript = """
        (function() {
          var state = {
            count: 1,
            fragments: {},
            scheduled: false,
            lastReported: -1,
            positionedElement: null
          };

          function clamp(value, lower, upper) {
            return Math.min(Math.max(value, lower), upper);
          }

          function visibleFragmentIndex() {
            var best = null;
            var bestDistance = Infinity;
            Object.keys(state.fragments).forEach(function(id) {
              var element = document.getElementById(id);
              if (!element) return;
              var rect = element.getBoundingClientRect();
              if (rect.bottom <= 0 || rect.top >= window.innerHeight) return;
              var distance = Math.abs(rect.top - window.innerHeight * 0.18);
              if (distance < bestDistance) {
                best = state.fragments[id];
                bestDistance = distance;
              }
            });
            return best;
          }

          function proportionalIndex() {
            var maximum = Math.max(
              document.documentElement.scrollHeight - window.innerHeight,
              1
            );
            var ratio = clamp(window.scrollY / maximum, 0, 1);
            return Math.round(ratio * Math.max(state.count - 1, 0));
          }

          function reportPosition() {
            state.scheduled = false;
            var index = visibleFragmentIndex();
            if (index === null) index = proportionalIndex();
            index = clamp(Math.round(index), 0, Math.max(state.count - 1, 0));
            if (index === state.lastReported) return;
            state.lastReported = index;
            window.webkit.messageHandlers.rivoReaderScroll.postMessage(index);
          }

          function scheduleReport() {
            if (state.scheduled) return;
            state.scheduled = true;
            window.requestAnimationFrame(reportPosition);
          }

          document.addEventListener('click', function(event) {
            var anchor = event.target.closest && event.target.closest('a[href]');
            if (!anchor) return;
            event.preventDefault();
            window.webkit.messageHandlers.rivoReaderLink.postMessage(anchor.href);
          }, true);
          window.addEventListener('scroll', scheduleReport, { passive: true });

          window.__rivoReader = {
            configure: function(count, fragments) {
              state.count = Math.max(Number(count) || 1, 1);
              state.fragments = fragments || {};
              state.lastReported = -1;
            },
            scrollToSegment: function(index) {
              index = clamp(
                Number(index) || 0,
                0,
                Math.max(state.count - 1, 0)
              );
              if (state.positionedElement) {
                state.positionedElement.classList.remove('rivo-reader-position');
                state.positionedElement = null;
              }
              var nearest = null;
              var nearestDistance = Infinity;
              Object.keys(state.fragments).forEach(function(id) {
                var element = document.getElementById(id);
                if (!element) return;
                var distance = Math.abs(state.fragments[id] - index);
                if (distance < nearestDistance) {
                  nearest = element;
                  nearestDistance = distance;
                }
              });
              if (nearest) {
                nearest.classList.add('rivo-reader-position');
                nearest.scrollIntoView({ block: 'start', behavior: 'auto' });
                state.positionedElement = nearest;
              } else {
                var maximum = Math.max(
                  document.documentElement.scrollHeight - window.innerHeight,
                  0
                );
                var ratio = state.count <= 1
                  ? 0
                  : index / (state.count - 1);
                window.scrollTo(0, maximum * ratio);
              }
              state.lastReported = Math.round(index);
            }
          };
        })();
        """
    }
}
