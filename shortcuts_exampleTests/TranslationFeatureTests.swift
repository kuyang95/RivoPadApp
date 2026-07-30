import XCTest

@testable import shortcuts_example

final class TranslationFeatureTests:
    XCTestCase
{
    func testAppLanguageSelectsTranslationTarget()
    {
        XCTAssertEqual(
            TranslationTargetLanguage
                .appDefault(
                    preferredLocalizations:
                        ["en-US"]
                ),
            .english
        )
        XCTAssertEqual(
            TranslationTargetLanguage
                .appDefault(
                    preferredLocalizations:
                        ["ja"]
                ),
            .japanese
        )
        XCTAssertEqual(
            TranslationTargetLanguage
                .appDefault(
                    preferredLocalizations:
                        ["ko-KR"]
                ),
            .korean
        )
    }

    func testTranslationInputValidation()
        throws
    {
        XCTAssertThrowsError(
            try LocalTranslationPromptBuilder
                .validatedSource(" \n ")
        ) { error in
            XCTAssertEqual(
                error as?
                    LocalTranslationError,
                .emptySource
            )
        }

        let maximum =
            LocalTranslationPromptBuilder
            .maximumSourceCharacters
        let valid = String(
            repeating: "가",
            count: maximum
        )
        XCTAssertEqual(
            try LocalTranslationPromptBuilder
                .validatedSource(valid)
                .count,
            maximum
        )
        XCTAssertThrowsError(
            try LocalTranslationPromptBuilder
                .validatedSource(
                    valid + "나"
                )
        ) { error in
            XCTAssertEqual(
                error as?
                    LocalTranslationError,
                .sourceTooLong(
                    maximum: maximum
                )
            )
        }
    }

    func testTranslationPromptKeepsSourceAndTarget()
    {
        let system =
            LocalTranslationPromptBuilder
            .systemPrompt(
                target: .japanese
            )
        let prompt =
            LocalTranslationPromptBuilder
            .userPrompt(
                source:
                    "Keep URL https://rivo.me"
            )

        XCTAssertTrue(
            system.contains("일본어")
        )
        XCTAssertTrue(
            system.contains(
                "번역문만 출력"
            )
        )
        XCTAssertTrue(
            prompt.contains(
                "Keep URL https://rivo.me"
            )
        )
        XCTAssertTrue(
            prompt.contains(
                "BEGIN_SOURCE"
            )
        )
    }

    func testViewModelPublishesStreamingResult()
        async
    {
        let service =
            TranslationServiceStub(
                chunks: [
                    "Good ",
                    "morning"
                ]
            )
        let model =
            TranslationViewModel(
                initialText: "좋은 아침",
                targetLanguage: .english,
                service: service
            )

        await model.translateNow()

        XCTAssertEqual(
            service.receivedSource,
            "좋은 아침"
        )
        XCTAssertEqual(
            service.receivedTarget,
            .english
        )
        XCTAssertEqual(
            model.result,
            "Good morning"
        )
        XCTAssertEqual(
            model.status,
            AppLocalization.string(
                "번역 완료"
            )
        )
        XCTAssertFalse(
            model.isTranslating
        )
    }

    func testViewModelReportsServiceFailure()
        async
    {
        let service =
            TranslationServiceStub(
                error:
                    LocalTranslationError
                    .emptyResult
            )
        let model =
            TranslationViewModel(
                initialText: "hello",
                service: service
            )

        await model.translateNow()

        XCTAssertEqual(
            model.errorDescription,
            LocalTranslationError
                .emptyResult
                .localizedDescription
        )
        XCTAssertEqual(
            model.status,
            AppLocalization.string(
                "번역 실패"
            )
        )
    }
}

@MainActor
private final class TranslationServiceStub:
    LocalTranslationServing
{
    let chunks: [String]
    let error: Error?
    private(set) var receivedSource:
        String?
    private(set) var receivedTarget:
        TranslationTargetLanguage?

    init(
        chunks: [String] = [],
        error: Error? = nil
    ) {
        self.chunks = chunks
        self.error = error
    }

    func translate(
        _ rawText: String,
        to target:
            TranslationTargetLanguage,
        onPartial:
            @escaping @MainActor
            (String) -> Void
    ) async throws -> String {
        receivedSource = rawText
        receivedTarget = target
        if let error {
            throw error
        }

        var result = ""
        for chunk in chunks {
            result += chunk
            onPartial(result)
        }
        return result
    }

    func cancel() async {}
}
