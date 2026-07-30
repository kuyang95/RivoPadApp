import XCTest

@testable import shortcuts_example

final class ChatAnswerSpeechTests:
    XCTestCase
{
    func testSentenceSegmenterSupportsKoreanPunctuationAndLines() {
        let sentences =
            ChatAnswerSentenceSegmenter
            .sentences(
                in: """
                첫 문장입니다. 둘째 문장입니다!
                - 목록 한 줄
                - 목록 두 줄
                """
            )

        XCTAssertEqual(
            sentences,
            [
                "첫 문장입니다.",
                "둘째 문장입니다!",
                "- 목록 한 줄",
                "- 목록 두 줄",
            ]
        )
    }

    func testSentenceSegmenterTrimsEmptyInputAndKeepsPlainText() {
        XCTAssertEqual(
            ChatAnswerSentenceSegmenter
                .sentences(
                    in: "  제목만 있는 답변  "
                ),
            ["제목만 있는 답변"]
        )
        XCTAssertTrue(
            ChatAnswerSentenceSegmenter
                .sentences(
                    in: " \n "
                )
                .isEmpty
        )
    }

    func testSpeechSelectionMovesWithinSentenceBounds() {
        var selection =
            ChatAnswerSpeechSelection(
                text:
                    "하나입니다. 둘입니다. 셋입니다."
            )

        XCTAssertEqual(
            selection.currentSentence,
            "하나입니다."
        )
        XCTAssertFalse(
            selection.movePrevious()
        )
        XCTAssertTrue(selection.moveNext())
        XCTAssertEqual(
            selection.currentSentence,
            "둘입니다."
        )
        XCTAssertTrue(selection.moveNext())
        XCTAssertEqual(
            selection.currentSentence,
            "셋입니다."
        )
        XCTAssertFalse(selection.moveNext())

        selection.moveToBeginning()
        XCTAssertEqual(
            selection.currentSentence,
            "하나입니다."
        )
    }

    func testControllerReadsEverySentenceOnceAndStopsAtEnd() {
        let synthesizer =
            TestChatSpeechSynthesizer()
        let controller =
            ChatAnswerSpeechController(
                tts: synthesizer
            )
        let messageID = UUID()

        XCTAssertTrue(
            controller.play(
                messageID: messageID,
                text:
                    "첫 문장입니다. 둘째입니다. 셋째입니다."
            )
        )
        XCTAssertEqual(
            synthesizer.spokenTexts,
            ["첫 문장입니다."]
        )
        XCTAssertTrue(controller.isSpeaking)

        synthesizer.finishCurrent()
        XCTAssertEqual(
            synthesizer.spokenTexts,
            [
                "첫 문장입니다.",
                "둘째입니다.",
            ]
        )
        XCTAssertEqual(
            controller.currentSentence,
            "둘째입니다."
        )

        synthesizer.finishCurrent()
        synthesizer.finishCurrent()
        XCTAssertEqual(
            synthesizer.spokenTexts,
            [
                "첫 문장입니다.",
                "둘째입니다.",
                "셋째입니다.",
            ]
        )
        XCTAssertFalse(controller.isSpeaking)
        XCTAssertEqual(
            controller.currentSentence,
            "셋째입니다."
        )

        XCTAssertTrue(
            controller.toggle(
                messageID: messageID,
                text:
                    "첫 문장입니다. 둘째입니다. 셋째입니다."
            )
        )
        XCTAssertEqual(
            synthesizer.spokenTexts.last,
            "첫 문장입니다."
        )
    }

    func testControllerStopInvalidatesOldCompletion() {
        let synthesizer =
            TestChatSpeechSynthesizer()
        let controller =
            ChatAnswerSpeechController(
                tts: synthesizer
            )

        _ = controller.play(
            messageID: UUID(),
            text:
                "첫 문장입니다. 둘째입니다."
        )
        let staleCompletion =
            synthesizer.completion
        controller.stop()
        staleCompletion?()

        XCTAssertFalse(controller.isSpeaking)
        XCTAssertEqual(
            synthesizer.spokenTexts,
            ["첫 문장입니다."]
        )
    }
}

@MainActor
private final class
    TestChatSpeechSynthesizer:
    ChatSpeechSynthesizing
{
    private(set) var spokenTexts:
        [String] = []
    private(set) var stopCount = 0
    var completion: (() -> Void)?

    func speak(
        _ text: String,
        rate: Float?,
        completion: (() -> Void)?
    ) {
        spokenTexts.append(text)
        self.completion = completion
    }

    func stop() {
        stopCount += 1
        completion = nil
    }

    func finishCurrent() {
        let current = completion
        completion = nil
        current?()
    }
}
