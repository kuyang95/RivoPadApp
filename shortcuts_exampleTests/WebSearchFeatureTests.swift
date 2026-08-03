import XCTest

@testable import shortcuts_example

@MainActor
final class WebSearchFeatureTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "WebSearchFeatureTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testConfigurationPersistsEnabledStateWithoutUserKey() {
        let store = WebSearchConfigurationStore(defaults: defaults)

        XCTAssertFalse(store.isEnabled)
        store.setEnabled(true)
        XCTAssertTrue(store.isEnabled)

        let restored = WebSearchConfigurationStore(defaults: defaults)
        XCTAssertTrue(restored.isEnabled)

        restored.setEnabled(false)
        XCTAssertFalse(restored.isEnabled)
    }

    func testQueryValidationEnforcesProviderLimits() throws {
        XCTAssertEqual(
            try WebSearchQueryValidator.validated("  최신 iPad 소식  "),
            "최신 iPad 소식"
        )
        XCTAssertThrowsError(
            try WebSearchQueryValidator.validated(" ")
        ) { error in
            XCTAssertEqual(error as? WebSearchError, .emptyQuery)
        }
        XCTAssertThrowsError(
            try WebSearchQueryValidator.validated(
                String(repeating: "가", count: 401)
            )
        ) { error in
            XCTAssertEqual(error as? WebSearchError, .queryTooLong)
        }
        XCTAssertThrowsError(
            try WebSearchQueryValidator.validated(
                Array(repeating: "word", count: 51)
                    .joined(separator: " ")
            )
        )
    }

    func testServiceMapsGeminiAnswerAndGoogleSources() async throws {
        let sourceURL = try XCTUnwrap(
            URL(string: "https://example.com/source")
        )
        let searchedAt = Date(timeIntervalSince1970: 1_785_369_600)
        let service = GeminiGoogleSearchService(
            configuration: WebSearchConfigurationStub(isEnabled: true),
            now: { searchedAt },
            isFirebaseConfigured: { true },
            generator: { query in
                XCTAssertEqual(query, "오늘 서울 주요 뉴스")
                return GeminiGroundedSearchPayload(
                    answer: "오늘의 주요 소식입니다.",
                    sources: [
                        .init(
                            title: "오늘의 뉴스",
                            url: sourceURL,
                            supportedText: "답변을 뒷받침하는 문장"
                        ),
                    ],
                    searchEntryPointHTML: "<div>Google Search</div>"
                )
            }
        )

        let response = try await service.search(
            query: "  오늘 서울 주요 뉴스  "
        )

        XCTAssertEqual(response.query, "오늘 서울 주요 뉴스")
        XCTAssertEqual(response.answer, "오늘의 주요 소식입니다.")
        XCTAssertEqual(response.providerName, "Gemini + Google Search")
        XCTAssertEqual(response.searchEntryPointHTML, "<div>Google Search</div>")
        XCTAssertEqual(response.searchedAt, searchedAt)
        XCTAssertEqual(response.results.count, 1)
        XCTAssertEqual(response.results[0].title, "오늘의 뉴스")
        XCTAssertEqual(response.results[0].url, sourceURL)
        XCTAssertEqual(response.results[0].snippet, "답변을 뒷받침하는 문장")
    }

    func testServiceDoesNotGenerateWhenDisabled() async {
        let service = GeminiGoogleSearchService(
            configuration: WebSearchConfigurationStub(isEnabled: false),
            isFirebaseConfigured: { true },
            generator: { _ in
                XCTFail("Disabled search must not call Gemini")
                throw WebSearchError.invalidResponse
            }
        )

        do {
            _ = try await service.search(query: "검색")
            XCTFail("Expected disabled error")
        } catch {
            XCTAssertEqual(error as? WebSearchError, .disabled)
        }
    }

    func testServiceRequiresFirebaseConfiguration() async {
        let service = GeminiGoogleSearchService(
            configuration: WebSearchConfigurationStub(isEnabled: true),
            isFirebaseConfigured: { false },
            generator: { _ in
                XCTFail("Unconfigured search must not call Gemini")
                throw WebSearchError.invalidResponse
            }
        )

        do {
            _ = try await service.search(query: "검색")
            XCTFail("Expected Firebase configuration error")
        } catch {
            XCTAssertEqual(error as? WebSearchError, .firebaseNotConfigured)
        }
    }

    func testViewModelBuildsTransientAnswerRoute() async throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com"))
        let response = WebSearchResponse(
            query: "질문",
            answer: "Gemini 답변",
            results: [
                WebSearchResult(
                    id: 1,
                    title: "출처",
                    url: sourceURL,
                    snippet: "발췌",
                    ageDescription: nil
                ),
            ],
            providerName: "Gemini + Google Search",
            searchEntryPointHTML: "<div>Google</div>",
            searchedAt: Date()
        )
        let model = WebSearchViewModel(
            initialQuery: "질문",
            provider: WebSearchProviderStub(result: .success(response))
        )

        await model.searchNow()

        XCTAssertEqual(model.response, response)
        guard case .webSearchQuestion(
            let routedResponse,
            let question,
            let speaksResponse
        ) = model.answerRoute(speaksResponse: true) else {
            return XCTFail("Expected web search answer route")
        }
        XCTAssertEqual(routedResponse, response)
        XCTAssertEqual(question, "질문")
        XCTAssertTrue(speaksResponse)
    }
}

@MainActor
private final class WebSearchConfigurationStub:
    WebSearchConfigurationProviding
{
    let isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }
}

@MainActor
private final class WebSearchProviderStub: WebSearchProviding {
    let result: Result<WebSearchResponse, Error>

    init(result: Result<WebSearchResponse, Error>) {
        self.result = result
    }

    func search(query: String) async throws -> WebSearchResponse {
        try result.get()
    }
}
