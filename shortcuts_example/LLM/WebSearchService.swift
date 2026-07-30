import Foundation

nonisolated struct WebSearchResult:
    Equatable,
    Hashable,
    Sendable,
    Identifiable
{
    let id: Int
    let title: String
    let url: URL
    let snippet: String
    let ageDescription: String?
}

nonisolated struct WebSearchResponse:
    Equatable,
    Hashable,
    Sendable
{
    let query: String
    let results: [WebSearchResult]
    let providerName: String
    let searchedAt: Date
}

nonisolated enum WebSearchError:
    Error,
    LocalizedError,
    Equatable,
    Sendable
{
    case disabled
    case missingAPIKey
    case emptyQuery
    case queryTooLong
    case invalidResponse
    case invalidAPIKey
    case paymentRequired
    case rateLimited
    case httpStatus(Int)
    case responseTooLarge(maximumBytes: Int)
    case decodingFailed
    case noResults

    var errorDescription: String? {
        switch self {
        case .disabled:
            return AppLocalization.string(
                "설정에서 온라인 웹 검색을 먼저 켜 주세요."
            )
        case .missingAPIKey:
            return AppLocalization.string(
                "설정에서 Brave Search API 키를 저장해 주세요."
            )
        case .emptyQuery:
            return AppLocalization.string(
                "검색할 내용을 입력해 주세요."
            )
        case .queryTooLong:
            return AppLocalization.string(
                "검색어는 400자와 50단어 이내로 입력해 주세요."
            )
        case .invalidResponse:
            return AppLocalization.string(
                "검색 서버의 응답을 확인할 수 없습니다."
            )
        case .invalidAPIKey:
            return AppLocalization.string(
                "Brave Search API 키가 유효하지 않습니다."
            )
        case .paymentRequired:
            return AppLocalization.string(
                "Brave Search 구독 또는 결제 상태를 확인해 주세요."
            )
        case .rateLimited:
            return AppLocalization.string(
                "웹 검색 요청 한도를 초과했습니다. 잠시 후 다시 시도해 주세요."
            )
        case .httpStatus(let status):
            return AppLocalization.format(
                "검색 서버가 오류 상태 %lld를 반환했습니다.",
                status
            )
        case .responseTooLarge(
            let maximumBytes
        ):
            return AppLocalization.format(
                "검색 결과가 %lld바이트 제한을 초과했습니다.",
                maximumBytes
            )
        case .decodingFailed:
            return AppLocalization.string(
                "검색 결과 형식이 올바르지 않습니다."
            )
        case .noResults:
            return AppLocalization.string(
                "관련 검색 결과를 찾지 못했습니다."
            )
        }
    }
}

@MainActor
protocol WebSearchProviding:
    AnyObject
{
    func search(
        query: String
    ) async throws -> WebSearchResponse
}

nonisolated enum WebSearchQueryValidator {
    static let maximumCharacters = 400
    static let maximumWords = 50

    static func validated(
        _ rawValue: String
    ) throws -> String {
        let value = rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !value.isEmpty else {
            throw WebSearchError.emptyQuery
        }
        let wordCount = value.split {
            $0.isWhitespace
        }.count
        guard value.count
                <= maximumCharacters,
              wordCount
                <= maximumWords else {
            throw WebSearchError
                .queryTooLong
        }
        return value
    }
}

@MainActor
final class BraveLLMContextSearchService:
    WebSearchProviding
{
    static let maximumResponseBytes =
        1_024 * 1_024
    static let shared =
        BraveLLMContextSearchService(
            configuration:
                WebSearchConfigurationStore
                .shared
        )

    private let configuration:
        any WebSearchConfigurationProviding
    private let session: URLSession
    private let localeIdentifier: String
    private let now: @Sendable () -> Date

    init(
        configuration:
            any WebSearchConfigurationProviding,
        session: URLSession? = nil,
        localeIdentifier: String =
            Locale.preferredLanguages.first
            ?? Locale.current.identifier,
        now: @escaping @Sendable () -> Date = {
            Date()
        }
    ) {
        self.configuration =
            configuration
        self.session =
            session
            ?? Self.makeSession()
        self.localeIdentifier =
            localeIdentifier
        self.now = now
    }

    func search(
        query rawQuery: String
    ) async throws -> WebSearchResponse {
        guard configuration.isEnabled else {
            throw WebSearchError.disabled
        }
        guard let apiKey = try
                configuration.apiKey()?
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                ),
              !apiKey.isEmpty else {
            throw WebSearchError
                .missingAPIKey
        }
        let query = try
            WebSearchQueryValidator
            .validated(rawQuery)
        let request = try makeRequest(
            query: query,
            apiKey: apiKey
        )
        let data = try await fetch(request)
        let response: BraveResponse
        do {
            response = try JSONDecoder()
                .decode(
                    BraveResponse.self,
                    from: data
                )
        } catch {
            throw WebSearchError
                .decodingFailed
        }
        let results = makeResults(
            from: response
        )
        guard !results.isEmpty else {
            throw WebSearchError.noResults
        }
        return WebSearchResponse(
            query: query,
            results: results,
            providerName: "Brave Search",
            searchedAt: now()
        )
    }

    private func makeRequest(
        query: String,
        apiKey: String
    ) throws -> URLRequest {
        guard let url = URL(
            string:
                "https://api.search.brave.com/res/v1/llm/context"
        ) else {
            throw WebSearchError
                .invalidResponse
        }
        let locale =
            SearchLocale(
                identifier:
                    localeIdentifier
            )
        let body: Data
        do {
            body = try JSONEncoder().encode(
                BraveRequest(
                    query: query,
                    country:
                        locale.country,
                    searchLanguage:
                        locale.language
                )
            )
        } catch {
            throw WebSearchError
                .invalidResponse
        }
        var request = URLRequest(
            url: url,
            cachePolicy:
                .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Content-Type"
        )
        request.setValue(
            apiKey,
            forHTTPHeaderField:
                "X-Subscription-Token"
        )
        return request
    }

    private func fetch(
        _ request: URLRequest
    ) async throws -> Data {
        let (bytes, response) =
            try await session.bytes(
                for: request
            )
        guard let http =
                response
                as? HTTPURLResponse else {
            throw WebSearchError
                .invalidResponse
        }
        switch http.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw WebSearchError
                .invalidAPIKey
        case 402:
            throw WebSearchError
                .paymentRequired
        case 429:
            throw WebSearchError
                .rateLimited
        default:
            throw WebSearchError
                .httpStatus(
                    http.statusCode
                )
        }
        if http.expectedContentLength
            > Int64(
                Self.maximumResponseBytes
            ) {
            throw WebSearchError
                .responseTooLarge(
                    maximumBytes:
                        Self
                        .maximumResponseBytes
                )
        }

        var data = Data()
        data.reserveCapacity(
            min(
                max(
                    0,
                    Int(
                        http
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
                throw WebSearchError
                    .responseTooLarge(
                        maximumBytes:
                            Self
                            .maximumResponseBytes
                    )
            }
            data.append(byte)
        }
        guard !data.isEmpty else {
            throw WebSearchError
                .invalidResponse
        }
        return data
    }

    private func makeResults(
        from response: BraveResponse
    ) -> [WebSearchResult] {
        var seenURLs = Set<URL>()
        var results = [WebSearchResult]()

        for item in response
            .grounding?
            .generic
            ?? [] {
            guard results.count < 5,
                  let url = URL(
                      string: item.url
                  ),
                  let scheme =
                      url.scheme?
                      .lowercased(),
                  scheme == "https"
                    || scheme == "http",
                  seenURLs.insert(url)
                    .inserted else {
                continue
            }
            let source =
                response.sources?[
                    item.url
                ]
            let fallbackTitle =
                source?.title
                ?? source?.hostname
                ?? url.host
                ?? item.url
            let title = Self.bounded(
                item.title ?? fallbackTitle,
                maximumCharacters: 300
            )
            let snippets = item.snippets
                .map {
                    Self.bounded(
                        $0,
                        maximumCharacters:
                            1_200
                    )
                }
                .filter {
                    !$0.isEmpty
                }
            guard !snippets.isEmpty else {
                continue
            }
            let age = source?.age?
                .filter {
                    !$0.trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    ).isEmpty
                }
                .first
            results.append(
                WebSearchResult(
                    id:
                        results.count + 1,
                    title:
                        title.isEmpty
                        ? fallbackTitle
                        : title,
                    url: url,
                    snippet:
                        snippets.joined(
                            separator: "\n"
                        ),
                    ageDescription: age
                )
            )
        }
        return results
    }

    private static func bounded(
        _ value: String,
        maximumCharacters: Int
    ) -> String {
        let normalized = value
            .replacingOccurrences(
                of: "\u{0000}",
                with: ""
            )
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard normalized.count
                > maximumCharacters else {
            return normalized
        }
        return String(
            normalized.prefix(
                maximumCharacters
            )
        )
    }

    private static func makeSession()
        -> URLSession
    {
        let configuration =
            URLSessionConfiguration
            .ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy =
            .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest =
            30
        configuration.timeoutIntervalForResource =
            30
        return URLSession(
            configuration: configuration
        )
    }
}

private extension
    BraveLLMContextSearchService
{
    struct BraveResponse: Decodable {
        let grounding: Grounding?
        let sources:
            [String: Source]?
    }

    struct BraveRequest: Encodable {
        let query: String
        let country: String
        let searchLanguage: String
        let count = 10
        let maximumNumberOfURLs = 5
        let maximumNumberOfTokens =
            4_096
        let maximumNumberOfSnippets = 20
        let maximumNumberOfTokensPerURL =
            1_024
        let maximumNumberOfSnippetsPerURL =
            4
        let contextThresholdMode =
            "balanced"

        enum CodingKeys:
            String,
            CodingKey
        {
            case query = "q"
            case country
            case searchLanguage =
                "search_lang"
            case count
            case maximumNumberOfURLs =
                "maximum_number_of_urls"
            case maximumNumberOfTokens =
                "maximum_number_of_tokens"
            case maximumNumberOfSnippets =
                "maximum_number_of_snippets"
            case maximumNumberOfTokensPerURL =
                "maximum_number_of_tokens_per_url"
            case maximumNumberOfSnippetsPerURL =
                "maximum_number_of_snippets_per_url"
            case contextThresholdMode =
                "context_threshold_mode"
        }
    }

    struct Grounding: Decodable {
        let generic: [GroundingItem]?
    }

    struct GroundingItem: Decodable {
        let url: String
        let title: String?
        let snippets: [String]
    }

    struct Source: Decodable {
        let title: String?
        let hostname: String?
        let age: [String]?
    }

    struct SearchLocale {
        let country: String
        let language: String

        init(identifier: String) {
            let lowercased =
                identifier.lowercased()
            if lowercased.hasPrefix("ko") {
                country = "kr"
                language = "ko"
            } else if lowercased
                .hasPrefix("ja") {
                country = "jp"
                language = "ja"
            } else {
                country = "us"
                language = "en"
            }
        }
    }
}

nonisolated enum WebSearchPromptBuilder {
    static let beginMarker =
        "WEB_SEARCH_RESULTS_BEGIN"
    static let endMarker =
        "WEB_SEARCH_RESULTS_END"

    static func prompt(
        response: WebSearchResponse,
        question: String,
        currentDate: Date = Date()
    ) -> String {
        let timestamp =
            ISO8601DateFormatter()
            .string(from: currentDate)
        let sources = response.results
            .map { result in
                """
                [\(result.id)]
                TITLE: \(neutralized(result.title))
                URL: \(result.url.absoluteString)
                EXCERPTS:
                \(neutralized(result.snippet))
                """
            }
            .joined(
                separator: "\n\n"
            )
        return """
        CURRENT_DATE: \(timestamp)
        SEARCH_PROVIDER: \(response.providerName)
        SEARCH_QUERY: \(response.query)

        \(beginMarker)
        \(sources)
        \(endMarker)

        QUESTION:
        \(question)
        """
    }

    private static func neutralized(
        _ text: String
    ) -> String {
        text
            .replacingOccurrences(
                of: beginMarker,
                with:
                    "WEB_SEARCH_BOUNDARY_OPEN_TEXT"
            )
            .replacingOccurrences(
                of: endMarker,
                with:
                    "WEB_SEARCH_BOUNDARY_CLOSE_TEXT"
            )
    }
}
