import Combine
import Foundation

nonisolated enum SharedWebContext {
    static func make(
        content: WebPageContent
    ) -> String {
        """
        웹페이지 제목: \(content.title)
        원문 주소: \(content.sourceURL.absoluteString)

        웹페이지 본문:
        \(content.text)
        """
    }
}

@MainActor
final class WebQuestionViewModel:
    ObservableObject
{
    @Published var urlText: String
    @Published var question: String
    @Published private(set) var content:
        WebPageContent?
    @Published private(set) var isLoading =
        false
    @Published private(set) var status = ""
    @Published private(set) var errorDescription:
        String?

    private let loader:
        any WebContentLoading
    private var loadingTask:
        Task<Void, Never>?
    private var requestID: UUID?

    init(
        initialURL: String? = nil,
        loader: any WebContentLoading
    ) {
        urlText = initialURL ?? ""
        question = AppLocalization.string(
            "이 웹페이지의 핵심 내용을 한국어로 요약해 줘."
        )
        self.loader = loader
    }

    convenience init(
        initialURL: String? = nil
    ) {
        self.init(
            initialURL: initialURL,
            loader:
                URLSessionWebContentLoader
                .shared
        )
    }

    var canLoad: Bool {
        !isLoading
            && !urlText
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
            .isEmpty
    }

    var canAsk: Bool {
        guard !isLoading,
              content != nil,
              !question
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .isEmpty else {
            return false
        }
        return loadedContentMatchesInput
    }

    func startLoading() {
        guard loadingTask == nil,
              canLoad else {
            return
        }
        let id = UUID()
        requestID = id
        loadingTask = Task {
            await loadNow(
                requestID: id
            )
            if requestID == id {
                loadingTask = nil
            }
        }
    }

    func loadNow() async {
        guard !isLoading else {
            return
        }
        let id = UUID()
        requestID = id
        await loadNow(requestID: id)
        if requestID == id {
            requestID = nil
        }
    }

    func cancel() {
        guard isLoading
                || loadingTask != nil else {
            return
        }
        requestID = nil
        loadingTask?.cancel()
        loadingTask = nil
        isLoading = false
        status = AppLocalization.string(
            "웹페이지 읽기를 중지했습니다."
        )
    }

    func replaceURL(
        with text: String
    ) {
        guard !isLoading else {
            return
        }
        urlText =
            WebURLInputParser
            .firstWebURL(in: text)?
            .absoluteString
            ?? text
        urlDidChange()
    }

    func urlDidChange() {
        guard !isLoading,
              content != nil,
              !loadedContentMatchesInput else {
            return
        }
        content = nil
        status = ""
        errorDescription = nil
    }

    func questionRoute() -> AppRoute? {
        guard canAsk,
              let content else {
            return nil
        }
        let boundedQuestion = String(
            question
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .prefix(4_000)
        )
        return .webPageQuestion(
            content: content,
            question: boundedQuestion
        )
    }

    private var loadedContentMatchesInput:
        Bool
    {
        guard let content,
              let inputURL = try?
                WebURLInputParser
                .normalizedURL(
                    from: urlText
                ) else {
            return false
        }
        return inputURL
            == content.requestedURL
            || inputURL
            == content.sourceURL
    }

    private func loadNow(
        requestID id: UUID
    ) async {
        isLoading = true
        content = nil
        errorDescription = nil
        status = AppLocalization.string(
            "웹페이지 본문을 읽는 중"
        )

        do {
            let loaded = try await
                loader.load(urlText)
            guard requestID == id,
                  !Task.isCancelled else {
                return
            }
            content = loaded
            urlText =
                loaded.sourceURL
                .absoluteString
            status = loaded.wasTruncated
                ? AppLocalization.string(
                    "긴 본문의 앞부분을 읽었습니다."
                )
                : AppLocalization.string(
                    "웹페이지 읽기 완료"
                )
            isLoading = false
        } catch is CancellationError {
            guard requestID == id else {
                return
            }
            status = AppLocalization.string(
                "웹페이지 읽기를 중지했습니다."
            )
            isLoading = false
        } catch {
            guard requestID == id else {
                return
            }
            errorDescription =
                error.localizedDescription
            status = AppLocalization.string(
                "웹페이지 읽기 실패"
            )
            isLoading = false
        }
    }
}
