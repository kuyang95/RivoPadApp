import CoreFoundation
import Foundation

nonisolated struct WebPageContent:
    Equatable,
    Hashable,
    Sendable
{
    let requestedURL: URL
    let sourceURL: URL
    let title: String
    let text: String
    let wasTruncated: Bool
    let usedRenderedFallback: Bool

    init(
        requestedURL: URL,
        sourceURL: URL,
        title: String,
        text: String,
        wasTruncated: Bool,
        usedRenderedFallback: Bool =
            false
    ) {
        self.requestedURL = requestedURL
        self.sourceURL = sourceURL
        self.title = title
        self.text = text
        self.wasTruncated = wasTruncated
        self.usedRenderedFallback =
            usedRenderedFallback
    }
}

nonisolated enum WebContentError:
    LocalizedError,
    Equatable,
    Sendable
{
    case emptyURL
    case invalidURL
    case unsupportedScheme
    case insecureHTTPBlocked
    case invalidResponse
    case httpStatus(Int)
    case unsupportedContentType(String)
    case contentTooLarge(maximumBytes: Int)
    case embeddedRedirectLimit
    case renderedPageTimedOut
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .emptyURL:
            return AppLocalization.string(
                "웹 주소를 입력해 주세요."
            )
        case .invalidURL:
            return AppLocalization.string(
                "올바른 웹 주소를 입력해 주세요."
            )
        case .unsupportedScheme:
            return AppLocalization.string(
                "HTTP 또는 HTTPS 주소만 열 수 있습니다."
            )
        case .insecureHTTPBlocked:
            return AppLocalization.string(
                "iPadOS 보안 정책으로 이 HTTP 주소를 열 수 없습니다. HTTPS 주소를 사용해 주세요."
            )
        case .invalidResponse:
            return AppLocalization.string(
                "웹 서버의 응답을 확인할 수 없습니다."
            )
        case .httpStatus(let status):
            return AppLocalization.format(
                "웹 서버가 오류 상태 %lld를 반환했습니다.",
                status
            )
        case .unsupportedContentType:
            return AppLocalization.string(
                "HTML 또는 텍스트 웹페이지만 읽을 수 있습니다."
            )
        case .contentTooLarge(let maximumBytes):
            return AppLocalization.format(
                "웹페이지가 %lld바이트 제한을 초과했습니다.",
                maximumBytes
            )
        case .embeddedRedirectLimit:
            return AppLocalization.string(
                "웹페이지의 이동이 너무 많이 반복되었습니다."
            )
        case .renderedPageTimedOut:
            return AppLocalization.string(
                "동적 웹페이지를 읽는 시간이 초과되었습니다."
            )
        case .emptyContent:
            return AppLocalization.string(
                "웹페이지에서 읽을 본문을 찾지 못했습니다."
            )
        }
    }
}

nonisolated enum WebURLInputParser {
    static func normalizedURL(
        from rawValue: String
    ) throws -> URL {
        let trimmed = rawValue
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard !trimmed.isEmpty else {
            throw WebContentError.emptyURL
        }

        let hasExplicitScheme =
            trimmed.range(
            of: "^[A-Za-z][A-Za-z0-9+.-]*://",
            options: .regularExpression
        ) != nil
        let candidate: String
        if !hasExplicitScheme {
            let lowercased =
                trimmed.lowercased()
            guard trimmed.range(
                of: "\\s",
                options:
                    .regularExpression
            ) == nil,
            trimmed.contains(".")
                || lowercased == "localhost"
                || lowercased.hasPrefix(
                    "localhost:"
                ) else {
                throw WebContentError
                    .invalidURL
            }
            candidate = "https://" + trimmed
        } else {
            candidate = trimmed
        }

        guard let components =
                URLComponents(
                    string: candidate
                ),
              let scheme = components
                .scheme?.lowercased() else {
            throw WebContentError.invalidURL
        }
        guard scheme == "http"
                || scheme == "https" else {
            throw WebContentError
                .unsupportedScheme
        }
        guard let host = components.host,
              !host.isEmpty,
              let url = components.url else {
            throw WebContentError.invalidURL
        }
        return url
    }

    static func firstWebURL(
        in text: String
    ) -> URL? {
        let trimmed = text
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard !trimmed.isEmpty else {
            return nil
        }

        if let exact = try? normalizedURL(
            from: trimmed
        ),
        trimmed.range(
            of: "\\s",
            options: .regularExpression
        ) == nil {
            return exact
        }

        guard let detector = try?
                NSDataDetector(
                    types:
                        NSTextCheckingResult
                        .CheckingType.link
                        .rawValue
                ) else {
            return nil
        }
        let range = NSRange(
            trimmed.startIndex...,
            in: trimmed
        )
        return detector
            .matches(
                in: trimmed,
                options: [],
                range: range
            )
            .compactMap(\.url)
            .first {
                let scheme =
                    $0.scheme?.lowercased()
                return scheme == "http"
                    || scheme == "https"
            }
    }
}

nonisolated enum WebHTMLExtractor {
    static let maximumExtractedCharacters =
        24_000

    static func extract(
        html: String,
        requestedURL: URL,
        sourceURL: URL,
        maximumCharacters: Int =
            maximumExtractedCharacters
    ) throws -> WebPageContent {
        let extractedTitle = title(
            from: html
        )
        let fullText = bodyText(
            from: html
        )
        guard !fullText.isEmpty else {
            throw WebContentError.emptyContent
        }

        let limit = max(
            1,
            maximumCharacters
        )
        let wasTruncated =
            fullText.count > limit
        let text = wasTruncated
            ? String(fullText.prefix(limit))
            : fullText
        let fallbackTitle =
            sourceURL.host
            ?? AppLocalization.string(
                "제목 없는 웹페이지"
            )

        return WebPageContent(
            requestedURL: requestedURL,
            sourceURL: sourceURL,
            title:
                extractedTitle.isEmpty
                ? fallbackTitle
                : extractedTitle,
            text: text,
            wasTruncated: wasTruncated
        )
    }

    static func extractRendered(
        title rawTitle: String?,
        text rawText: String,
        requestedURL: URL,
        sourceURL: URL,
        maximumCharacters: Int =
            maximumExtractedCharacters
    ) throws -> WebPageContent {
        let fullText = normalizedText(
            rawText
        )
        guard !fullText.isEmpty else {
            throw WebContentError.emptyContent
        }
        let title = normalizedText(
            rawTitle ?? ""
        )
        .replacingOccurrences(
            of: "\n",
            with: " "
        )
        let limit = max(
            1,
            maximumCharacters
        )
        let wasTruncated =
            fullText.count > limit

        return WebPageContent(
            requestedURL: requestedURL,
            sourceURL: sourceURL,
            title:
                title.isEmpty
                ? (
                    sourceURL.host
                    ?? AppLocalization
                    .string(
                        "제목 없는 웹페이지"
                    )
                )
                : title,
            text:
                wasTruncated
                ? String(
                    fullText.prefix(limit)
                )
                : fullText,
            wasTruncated: wasTruncated,
            usedRenderedFallback: true
        )
    }

    static func embeddedRedirect(
        in html: String,
        relativeTo baseURL: URL
    ) -> URL? {
        let patterns = [
            #"(?is)(?:top|window|document|self)\.location(?:\.replace\s*\(\s*|\.href\s*=\s*|\s*=\s*)['"]([^'"]+)['"]"#,
            #"(?is)<meta[^>]+http-equiv\s*=\s*['"]?refresh['"]?[^>]*?url\s*=\s*['"]?([^'">\s]+)"#,
        ]

        for pattern in patterns {
            guard let rawTarget =
                    firstCapture(
                        pattern: pattern,
                        in: html
                    ) else {
                continue
            }
            let target = decodeEntities(
                rawTarget.replacingOccurrences(
                    of: "\\/",
                    with: "/"
                )
            )
            guard let resolved = URL(
                string: target,
                relativeTo: baseURL
            )?.absoluteURL,
            let scheme =
                resolved.scheme?
                .lowercased(),
            scheme == "http"
                || scheme == "https" else {
                continue
            }
            return resolved
        }
        return nil
    }

    static func bodyText(
        from html: String
    ) -> String {
        var cleaned = html
        let removableElements = [
            "head",
            "script",
            "style",
            "noscript",
            "svg",
            "canvas",
            "template",
            "nav",
            "header",
            "footer",
            "aside",
            "form",
        ]
        for element in removableElements {
            cleaned =
                replacingMatches(
                    in: cleaned,
                    pattern:
                        "(?is)<\(element)\\b[^>]*>.*?</\(element)\\s*>",
                    with: "\n"
                )
        }
        cleaned = replacingMatches(
            in: cleaned,
            pattern: "(?is)<!--.*?-->",
            with: "\n"
        )
        cleaned = replacingMatches(
            in: cleaned,
            pattern:
                "(?i)</?(?:p|div|section|article|main|h[1-6]|li|tr|table|blockquote|pre|br|hr)\\b[^>]*>",
            with: "\n"
        )
        cleaned = replacingMatches(
            in: cleaned,
            pattern: "(?is)<[^>]+>",
            with: " "
        )
        return normalizedText(
            decodeEntities(cleaned)
        )
    }

    static func title(
        from html: String
    ) -> String {
        guard let rawTitle =
                firstCapture(
                    pattern:
                        "(?is)<title\\b[^>]*>(.*?)</title\\s*>",
                    in: html
                ) else {
            return ""
        }
        let withoutTags =
            replacingMatches(
                in: rawTitle,
                pattern: "(?is)<[^>]+>",
                with: " "
            )
        return normalizedText(
            decodeEntities(withoutTags)
        )
        .replacingOccurrences(
            of: "\n",
            with: " "
        )
    }

    static func charset(
        from htmlHeader: String
    ) -> String? {
        let patterns = [
            #"(?is)<meta[^>]+charset\s*=\s*['"]?\s*([A-Za-z0-9._-]+)"#,
            #"(?is)<meta[^>]+content\s*=\s*['"][^'"]*charset\s*=\s*([A-Za-z0-9._-]+)"#,
        ]
        for pattern in patterns {
            if let charset =
                    firstCapture(
                        pattern: pattern,
                        in: htmlHeader
                    ) {
                return charset
            }
        }
        return nil
    }

    static func decodeEntities(
        _ source: String
    ) -> String {
        let namedEntities = [
            "&nbsp;": " ",
            "&#160;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&#39;": "'",
            "&ndash;": "–",
            "&mdash;": "—",
            "&hellip;": "…",
        ]
        var result = source
        for (entity, replacement)
            in namedEntities {
            result = result
                .replacingOccurrences(
                    of: entity,
                    with: replacement,
                    options:
                        .caseInsensitive
                )
        }

        guard let expression = try?
                NSRegularExpression(
                    pattern:
                        "&#(?:x([0-9A-Fa-f]+)|([0-9]+));"
                ) else {
            return result
        }
        let matches = expression.matches(
            in: result,
            range: NSRange(
                result.startIndex...,
                in: result
            )
        )
        for match in matches.reversed() {
            guard let wholeRange = Range(
                match.range(at: 0),
                in: result
            ) else {
                continue
            }
            let hex = capture(
                match.range(at: 1),
                in: result
            )
            let decimal = capture(
                match.range(at: 2),
                in: result
            )
            let value: UInt32?
            if let hex {
                value = UInt32(hex, radix: 16)
            } else if let decimal {
                value = UInt32(
                    decimal,
                    radix: 10
                )
            } else {
                value = nil
            }
            guard let value,
                  let scalar =
                    UnicodeScalar(value) else {
                continue
            }
            result.replaceSubrange(
                wholeRange,
                with: String(scalar)
            )
        }
        return result
    }

    private static func normalizedText(
        _ source: String
    ) -> String {
        source
            .replacingOccurrences(
                of: "\r\n",
                with: "\n"
            )
            .replacingOccurrences(
                of: "\r",
                with: "\n"
            )
            .split(
                separator: "\n",
                omittingEmptySubsequences:
                    false
            )
            .map {
                $0.replacingOccurrences(
                    of: "[\\t ]+",
                    with: " ",
                    options:
                        .regularExpression
                )
                .trimmingCharacters(
                    in: .whitespaces
                )
            }
            .reduce(into: [String]()) {
                lines,
                line in
                if line.isEmpty {
                    if lines.last?.isEmpty
                        == false {
                        lines.append("")
                    }
                } else {
                    lines.append(line)
                }
            }
            .joined(separator: "\n")
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
    }

    private static func firstCapture(
        pattern: String,
        in source: String
    ) -> String? {
        guard let expression = try?
                NSRegularExpression(
                    pattern: pattern
                ),
              let match = expression
                .firstMatch(
                    in: source,
                    range: NSRange(
                        source.startIndex...,
                        in: source
                    )
                ),
              match.numberOfRanges > 1,
              let range = Range(
                match.range(at: 1),
                in: source
              ) else {
            return nil
        }
        return String(source[range])
    }

    private static func replacingMatches(
        in source: String,
        pattern: String,
        with replacement: String
    ) -> String {
        guard let expression = try?
                NSRegularExpression(
                    pattern: pattern
                ) else {
            return source
        }
        return expression
            .stringByReplacingMatches(
                in: source,
                range: NSRange(
                    source.startIndex...,
                    in: source
                ),
                withTemplate:
                    replacement
            )
    }

    private static func capture(
        _ range: NSRange,
        in source: String
    ) -> String? {
        guard range.location
                != NSNotFound,
              let swiftRange = Range(
                  range,
                  in: source
              ) else {
            return nil
        }
        return String(source[swiftRange])
    }
}

nonisolated enum WebPagePromptBuilder {
    static let beginMarker =
        "WEB_CONTENT_BEGIN"
    static let endMarker =
        "WEB_CONTENT_END"

    static func prompt(
        content: WebPageContent,
        question: String
    ) -> String {
        let safeTitle = neutralized(
            content.title
        )
        let safeText = neutralized(
            content.text
        )
        let boundedQuestion = String(
            question
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .prefix(4_000)
        )
        return """
        SOURCE_TITLE: \(safeTitle)
        SOURCE_URL: \(content.sourceURL.absoluteString)

        \(beginMarker)
        \(safeText)
        \(endMarker)

        USER_QUESTION:
        \(boundedQuestion)
        """
    }

    private static func neutralized(
        _ source: String
    ) -> String {
        source
            .replacingOccurrences(
                of: beginMarker,
                with:
                    "WEB_BOUNDARY_OPEN_TEXT"
            )
            .replacingOccurrences(
                of: endMarker,
                with:
                    "WEB_BOUNDARY_CLOSE_TEXT"
            )
    }
}

@MainActor
protocol WebContentLoading:
    AnyObject
{
    func load(
        _ rawURL: String
    ) async throws -> WebPageContent
}

nonisolated struct WebRenderedContent:
    Equatable,
    Sendable
{
    let sourceURL: URL
    let title: String?
    let text: String
}

@MainActor
protocol WebRenderedContentLoading:
    AnyObject
{
    func loadRenderedContent(
        from url: URL
    ) async throws -> WebRenderedContent
}

@MainActor
final class URLSessionWebContentLoader:
    WebContentLoading
{
    static let maximumResponseBytes =
        2 * 1_024 * 1_024
    static let maximumEmbeddedRedirects =
        2
    static let renderedFallbackThreshold =
        200
    static let shared =
        URLSessionWebContentLoader(
            session: makeSession(),
            renderedLoader:
                WebKitRenderedContentLoader()
        )

    private let session: URLSession
    private let renderedLoader:
        (any WebRenderedContentLoading)?

    init(
        session: URLSession,
        renderedLoader:
            (any WebRenderedContentLoading)? =
                nil
    ) {
        self.session = session
        self.renderedLoader =
            renderedLoader
    }

    func load(
        _ rawURL: String
    ) async throws -> WebPageContent {
        let requestedURL = try
            WebURLInputParser.normalizedURL(
                from: rawURL
            )
        var currentURL = requestedURL
        var visited = Set<URL>()

        for redirectCount
            in 0...Self
            .maximumEmbeddedRedirects {
            try Task.checkCancellation()
            guard visited.insert(
                currentURL
            ).inserted else {
                throw WebContentError
                    .embeddedRedirectLimit
            }

            let response: (
                html: String,
                finalURL: URL
            )
            do {
                response = try await fetch(
                    currentURL
                )
            } catch let error as URLError
                where error.code
                    == .appTransportSecurityRequiresSecureConnection {
                throw WebContentError
                    .insecureHTTPBlocked
            }
            if let embeddedRedirect =
                    WebHTMLExtractor
                    .embeddedRedirect(
                        in: response.html,
                        relativeTo:
                            response.finalURL
                    ) {
                guard redirectCount
                        < Self
                        .maximumEmbeddedRedirects else {
                    throw WebContentError
                        .embeddedRedirectLimit
                }
                currentURL =
                    embeddedRedirect
                continue
            }

            let extracted = try?
                WebHTMLExtractor.extract(
                    html: response.html,
                    requestedURL:
                        requestedURL,
                    sourceURL:
                        response.finalURL
                )
            if let extracted,
               extracted.text.count
                >= Self
                .renderedFallbackThreshold {
                return extracted
            }

            if let renderedLoader {
                do {
                    let rendered =
                        try await
                        renderedLoader
                        .loadRenderedContent(
                            from:
                                response.finalURL
                        )
                    return try
                        WebHTMLExtractor
                        .extractRendered(
                            title:
                                rendered.title,
                            text:
                                rendered.text,
                            requestedURL:
                                requestedURL,
                            sourceURL:
                                rendered
                                .sourceURL
                        )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    if let extracted {
                        return extracted
                    }
                    throw error
                }
            }

            if let extracted {
                return extracted
            }
            throw WebContentError.emptyContent
        }
        throw WebContentError
            .embeddedRedirectLimit
    }

    private func fetch(
        _ url: URL
    ) async throws -> (
        html: String,
        finalURL: URL
    ) {
        var request = URLRequest(
            url: url,
            cachePolicy:
                .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = "GET"
        request.setValue(
            "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField:
                "User-Agent"
        )
        request.setValue(
            "text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.1",
            forHTTPHeaderField: "Accept"
        )

        let (bytes, response) =
            try await session.bytes(
                for: request
            )
        guard let httpResponse =
                response
                as? HTTPURLResponse else {
            throw WebContentError
                .invalidResponse
        }
        guard let finalURL =
                httpResponse.url,
              let finalScheme =
                finalURL.scheme?
                .lowercased(),
              finalScheme == "http"
                || finalScheme == "https" else {
            throw WebContentError
                .unsupportedScheme
        }
        guard (200...299).contains(
            httpResponse.statusCode
        ) else {
            throw WebContentError.httpStatus(
                httpResponse.statusCode
            )
        }
        if httpResponse
            .expectedContentLength
            > Int64(
                Self.maximumResponseBytes
            ) {
            throw WebContentError
                .contentTooLarge(
                    maximumBytes:
                        Self
                        .maximumResponseBytes
                )
        }
        if let mimeType =
                httpResponse.mimeType?
                .lowercased(),
           !mimeType.hasPrefix("text/"),
           mimeType
                != "application/xhtml+xml" {
            throw WebContentError
                .unsupportedContentType(
                    mimeType
                )
        }

        var data = Data()
        data.reserveCapacity(
            min(
                max(
                    0,
                    Int(
                        httpResponse
                        .expectedContentLength
                    )
                ),
                Self.maximumResponseBytes
            )
        )
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count
                    < Self
                    .maximumResponseBytes else {
                throw WebContentError
                    .contentTooLarge(
                        maximumBytes:
                            Self
                            .maximumResponseBytes
                    )
            }
            data.append(byte)
        }
        guard !data.isEmpty else {
            throw WebContentError
                .emptyContent
        }
        guard let html = decode(
            data,
            response: httpResponse
        ) else {
            throw WebContentError
                .emptyContent
        }
        return (
            html,
            finalURL
        )
    }

    private func decode(
        _ data: Data,
        response: HTTPURLResponse
    ) -> String? {
        var encodings =
            [String.Encoding]()
        if let name =
                response.textEncodingName,
           let encoding =
                ianaEncoding(name) {
            encodings.append(encoding)
        }

        let header = String(
            data: data.prefix(8_192),
            encoding: .isoLatin1
        ) ?? ""
        if let charset =
                WebHTMLExtractor
                .charset(from: header),
           let encoding =
                ianaEncoding(charset) {
            encodings.append(encoding)
        }
        encodings.append(contentsOf: [
            .utf8,
            .unicode,
            .shiftJIS,
            .japaneseEUC,
            .isoLatin1,
        ])

        var seen =
            Set<String.Encoding.RawValue>()
        for encoding in encodings
            where seen.insert(
                encoding.rawValue
            ).inserted {
            if let value = String(
                data: data,
                encoding: encoding
            ) {
                return value
            }
        }
        return nil
    }

    private func ianaEncoding(
        _ name: String
    ) -> String.Encoding? {
        let cfEncoding =
            CFStringConvertIANACharSetNameToEncoding(
                name as CFString
            )
        guard cfEncoding
                != kCFStringEncodingInvalidId else {
            return nil
        }
        return String.Encoding(
            rawValue:
                CFStringConvertEncodingToNSStringEncoding(
                    cfEncoding
                )
        )
    }

    private static func makeSession()
        -> URLSession
    {
        let configuration =
            URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest =
            10
        configuration.timeoutIntervalForResource =
            15
        configuration.requestCachePolicy =
            .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost =
            2
        return URLSession(
            configuration: configuration
        )
    }
}
