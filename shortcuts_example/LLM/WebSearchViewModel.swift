import Combine
import Foundation

@MainActor
final class WebSearchViewModel:
    ObservableObject
{
    @Published var query: String
    @Published private(set)
    var response: WebSearchResponse?
    @Published private(set)
    var isSearching = false
    @Published private(set)
    var status = ""
    @Published private(set)
    var errorDescription: String?

    private let provider:
        any WebSearchProviding
    private var searchTask:
        Task<Void, Never>?

    init(
        initialQuery: String? = nil,
        provider:
            (any WebSearchProviding)? =
                nil
    ) {
        query = initialQuery ?? ""
        self.provider =
            provider
            ?? BraveLLMContextSearchService
                .shared
    }

    var canSearch: Bool {
        !isSearching
            && !query.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
    }

    func queryDidChange() {
        response = nil
        errorDescription = nil
        status = ""
    }

    func startSearching() {
        guard searchTask == nil else {
            return
        }
        searchTask = Task {
            await searchNow()
            searchTask = nil
        }
    }

    func searchNow() async {
        guard !isSearching else {
            return
        }
        isSearching = true
        response = nil
        errorDescription = nil
        status = AppLocalization.string(
            "Brave에서 출처를 찾는 중"
        )
        do {
            let result = try await
                provider.search(
                    query: query
                )
            try Task.checkCancellation()
            response = result
            status = AppLocalization.format(
                "검색 출처 %lld개",
                result.results.count
            )
        } catch is CancellationError {
            status = AppLocalization.string(
                "웹 검색을 중지했습니다."
            )
        } catch {
            status = AppLocalization.string(
                "웹 검색 실패"
            )
            errorDescription =
                error.localizedDescription
        }
        isSearching = false
    }

    func cancel() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    func answerRoute(
        speaksResponse: Bool = false
    ) -> AppRoute? {
        guard let response else {
            return nil
        }
        return .webSearchQuestion(
            response: response,
            question: response.query,
            speaksResponse: speaksResponse
        )
    }
}
