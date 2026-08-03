import FirebaseAILogic
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
    let answer: String
    let results: [WebSearchResult]
    let providerName: String
    let searchEntryPointHTML: String?
    let searchedAt: Date
}

nonisolated struct GeminiGroundedSearchPayload:
    Equatable,
    Sendable
{
    struct Source:
        Equatable,
        Sendable
    {
        let title: String
        let url: URL
        let supportedText: String
    }

    let answer: String
    let sources: [Source]
    let searchEntryPointHTML: String?
}

nonisolated enum WebSearchError:
    Error,
    LocalizedError,
    Equatable,
    Sendable
{
    case disabled
    case firebaseNotConfigured
    case emptyQuery
    case queryTooLong
    case invalidResponse
    case rateLimited
    case noResults
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .disabled:
            return AppLocalization.string(
                "설정에서 온라인 웹 검색을 먼저 켜 주세요."
            )
        case .firebaseNotConfigured:
            return AppLocalization.string(
                "VisionCraft의 Firebase 연결 설정이 필요합니다."
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
        case .rateLimited:
            return AppLocalization.string(
                "웹 검색 요청 한도를 초과했습니다. 잠시 후 다시 시도해 주세요."
            )
        case .noResults:
            return AppLocalization.string(
                "관련 검색 결과를 찾지 못했습니다."
            )
        case .requestFailed:
            return AppLocalization.string(
                "Gemini 웹 검색에 연결하지 못했습니다."
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
        guard value.count <= maximumCharacters,
              wordCount <= maximumWords else {
            throw WebSearchError.queryTooLong
        }
        return value
    }
}

@MainActor
final class GeminiGoogleSearchService:
    WebSearchProviding
{
    typealias Generator =
        @MainActor @Sendable (String) async throws
            -> GeminiGroundedSearchPayload

    static let shared =
        GeminiGoogleSearchService(
            configuration:
                WebSearchConfigurationStore
                .shared
        )

    private let configuration:
        any WebSearchConfigurationProviding
    private let now: @Sendable () -> Date
    private let isFirebaseConfigured:
        @MainActor @Sendable () -> Bool
    private let generator: Generator

    init(
        configuration:
            any WebSearchConfigurationProviding,
        now: @escaping @Sendable () -> Date = {
            Date()
        },
        isFirebaseConfigured:
            @escaping @MainActor @Sendable () -> Bool = {
                FirebaseRuntime.isConfigured
            },
        generator: Generator? = nil
    ) {
        self.configuration = configuration
        self.now = now
        self.isFirebaseConfigured =
            isFirebaseConfigured
        self.generator = generator ?? {
            try await Self.generate(
                query: $0
            )
        }
    }

    func search(
        query rawQuery: String
    ) async throws -> WebSearchResponse {
        guard configuration.isEnabled else {
            throw WebSearchError.disabled
        }
        guard isFirebaseConfigured() else {
            throw WebSearchError
                .firebaseNotConfigured
        }
        let query = try
            WebSearchQueryValidator
            .validated(rawQuery)

        let payload: GeminiGroundedSearchPayload
        do {
            payload = try await generator(query)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as WebSearchError {
            throw error
        } catch {
            let description = error
                .localizedDescription
                .lowercased()
            if description.contains("429")
                || description.contains(
                    "rate limit"
                ) {
                throw WebSearchError.rateLimited
            }
            throw WebSearchError.requestFailed
        }

        let answer = payload.answer
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard !answer.isEmpty else {
            throw WebSearchError
                .invalidResponse
        }
        guard !payload.sources.isEmpty else {
            throw WebSearchError.noResults
        }

        return WebSearchResponse(
            query: query,
            answer: answer,
            results: payload.sources
                .enumerated()
                .map { index, source in
                    WebSearchResult(
                        id: index + 1,
                        title: source.title,
                        url: source.url,
                        snippet:
                            source
                            .supportedText,
                        ageDescription: nil
                    )
                },
            providerName:
                "Gemini + Google Search",
            searchEntryPointHTML:
                payload
                .searchEntryPointHTML,
            searchedAt: now()
        )
    }

    private static func generate(
        query: String
    ) async throws
        -> GeminiGroundedSearchPayload
    {
        let model = FirebaseAI
            .firebaseAI(
                backend: .googleAI()
            )
            .generativeModel(
                modelName:
                    "gemini-2.5-flash-lite",
                generationConfig:
                    GenerationConfig(
                        temperature: 0.2,
                        maxOutputTokens: 512
                    ),
                tools: [
                    .googleSearch(),
                ],
                systemInstruction:
                    ModelContent(
                        role: "system",
                        parts:
                            systemInstruction
                    )
            )
        let response = try await model
            .generateContent(
                searchPrompt(query)
            )
        guard let answer = response.text?
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                ),
              !answer.isEmpty,
              let metadata = response
                .candidates
                .first?
                .groundingMetadata else {
            throw WebSearchError
                .invalidResponse
        }

        var supportedTextByIndex =
            [Int: [String]]()
        for support in metadata
            .groundingSupports {
            let text = support.segment.text
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
            guard !text.isEmpty else {
                continue
            }
            for index in support
                .groundingChunkIndices {
                supportedTextByIndex[
                    index,
                    default: []
                ].append(text)
            }
        }

        var seenURLs = Set<URL>()
        var sources = [
            GeminiGroundedSearchPayload
                .Source
        ]()
        for (index, chunk) in metadata
            .groundingChunks
            .enumerated() {
            guard let web = chunk.web,
                  let rawURL = web.uri,
                  let url = URL(
                      string: rawURL
                  ),
                  ["http", "https"]
                    .contains(
                        url.scheme?
                            .lowercased()
                            ?? ""
                    ),
                  seenURLs.insert(url)
                    .inserted else {
                continue
            }
            let title = web.title?
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
            let displayTitle =
                title.flatMap {
                    $0.isEmpty ? nil : $0
                }
                ?? url.host
                ?? rawURL
            let supportedText =
                Array(
                    Set(
                        supportedTextByIndex[
                            index
                        ] ?? []
                    )
                )
                .sorted()
                .joined(separator: " ")
            sources.append(
                .init(
                    title: displayTitle,
                    url: url,
                    supportedText:
                        supportedText
                )
            )
        }

        return GeminiGroundedSearchPayload(
            answer: answer,
            sources: sources,
            searchEntryPointHTML:
                metadata
                .searchEntryPoint?
                .renderedContent
        )
    }

    private static var systemInstruction:
        String
    {
        """
        너는 VisionCraft의 검색 도우미야. Google Search 결과에 근거해
        최신 정보를 정확하고 간결하게 답해. 날짜나 시점이 중요하면
        함께 말하고, 검색 결과가 불확실하거나 부족하면 그 한계를
        분명히 밝혀. 답변은 \(AppLanguage.current().localAIResponseLanguageName)로 작성해.
        """
    }

    private static func searchPrompt(
        _ query: String
    ) -> String {
        let currentDate =
            ISO8601DateFormatter()
            .string(from: Date())
        return """
        CURRENT_DATE: \(currentDate)
        Google Search를 사용해 다음 질문에 답해.

        QUESTION:
        \(query)
        """
    }
}
