import Combine
import Foundation

@MainActor
final class TranslationViewModel:
    ObservableObject
{
    @Published var sourceText: String
    @Published var targetLanguage:
        TranslationTargetLanguage
    @Published private(set) var result = ""
    @Published private(set) var status = ""
    @Published private(set) var isTranslating =
        false
    @Published private(set) var isCancelling =
        false
    @Published private(set) var errorDescription:
        String?

    private let service:
        any LocalTranslationServing
    private var translationTask:
        Task<Void, Never>?
    private var cancellationTask:
        Task<Void, Never>?

    init(
        initialText: String? = nil,
        targetLanguage:
            TranslationTargetLanguage =
                .appDefault(),
        service:
            any LocalTranslationServing
    ) {
        sourceText = initialText ?? ""
        self.targetLanguage =
            targetLanguage
        self.service = service
    }

    convenience init(
        initialText: String? = nil,
        targetLanguage:
            TranslationTargetLanguage =
                .appDefault()
    ) {
        self.init(
            initialText: initialText,
            targetLanguage:
                targetLanguage,
            service:
                MLXLocalTranslationService
                .shared
        )
    }

    var canTranslate: Bool {
        !isTranslating
            && !isCancelling
            && translationTask == nil
            && !sourceText
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
            .isEmpty
    }

    var isBusy: Bool {
        isTranslating || isCancelling
    }

    var canUseResult: Bool {
        !result
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
            .isEmpty
    }

    func startTranslation() {
        guard translationTask == nil,
              !isCancelling else {
            return
        }
        translationTask = Task {
            await translateNow()
            translationTask = nil
        }
    }

    func translateNow() async {
        guard !isTranslating,
              !isCancelling else {
            return
        }
        do {
            _ = try
                LocalTranslationPromptBuilder
                .validatedSource(
                    sourceText
                )
        } catch {
            errorDescription =
                error.localizedDescription
            return
        }

        result = ""
        errorDescription = nil
        status = AppLocalization.string(
            "M4 로컬 AI로 번역하는 중"
        )
        isTranslating = true
        defer {
            isTranslating = false
        }

        do {
            result = try await
                service.translate(
                    sourceText,
                    to: targetLanguage
                ) { [weak self] partial in
                    self?.result = partial
                }
            status = AppLocalization.string(
                "번역 완료"
            )
        } catch is CancellationError {
            status = AppLocalization.string(
                "번역을 중지했습니다."
            )
        } catch {
            errorDescription =
                error.localizedDescription
            status = AppLocalization.string(
                "번역 실패"
            )
        }
    }

    func cancel() {
        guard !isCancelling,
              translationTask != nil
                || isTranslating else {
            return
        }
        translationTask?.cancel()
        isCancelling = true
        let service = service
        cancellationTask = Task {
            await service.cancel()
            isCancelling = false
            cancellationTask = nil
        }
        isTranslating = false
        status = AppLocalization.string(
            "번역을 중지했습니다."
        )
    }

    func replaceSource(
        with text: String
    ) {
        guard !isTranslating,
              !isCancelling else {
            return
        }
        sourceText = text
        errorDescription = nil
    }

    func clear() {
        guard !isTranslating,
              !isCancelling else {
            return
        }
        sourceText = ""
        result = ""
        status = ""
        errorDescription = nil
    }
}
