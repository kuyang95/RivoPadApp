import XCTest

@testable import shortcuts_example

final class LocalImageDescriptionPromptTests:
    XCTestCase
{
    func testUsesSelectedResponseLanguage() {
        XCTAssertTrue(
            LocalImageDescriptionPrompt
                .defaultQuestion(
                    language: .english
                )
                .contains("영어로")
        )
        XCTAssertTrue(
            LocalImageDescriptionPrompt
                .defaultQuestion(
                    language: .japanese
                )
                .contains("일본어로")
        )
    }

    func testRequestsVisibleDetailsWithoutGuessing() {
        let prompt =
            LocalImageDescriptionPrompt
            .defaultQuestion(
                language: .korean
            )

        XCTAssertTrue(
            prompt.contains(
                "장면과 물체, 글자, 사람의 행동"
            )
        )
        XCTAssertTrue(
            prompt.contains(
                "추측하지 마"
            )
        )
    }
}
