import XCTest
@testable import shortcuts_example

final class LocalVoiceActionTests: XCTestCase {
    func testFileImportRequestsHaveUniqueSequenceNumbers() {
        let router = AppRouter()

        XCTAssertEqual(router.fileImportRequestID, 0)
        router.requestFileImport()
        XCTAssertEqual(router.fileImportRequestID, 1)
        router.requestFileImport()
        XCTAssertEqual(router.fileImportRequestID, 2)
    }

    func testClassifiesAndroidVoiceActionDestinations() {
        let cases: [
            (String, LocalVoiceActionIntent)
        ] = [
            ("문서 스캐너 열어 줘", .openDocumentScanner),
            ("AI 채팅 기록 보여 줘", .openChatHistory),
            ("이 문서에 질문할래", .openAIDocument),
            ("새 AI 채팅 시작", .openAIChat),
            ("데이지 책 읽기", .openReader),
            ("여기 글자 읽어 줘", .readVisibleText),
            ("앞에 뭐가 보여?", .describeScene),
            ("사진 찍어 줘", .capture),
            ("카메라 돋보기 켜", .openMagnifier),
            ("카메라 열어", .openCamera),
            ("텍스트 문서 열기", .openTextDocument),
            ("너는 누구니", .introduce),
        ]

        for (utterance, expected) in cases {
            XCTAssertEqual(
                LocalVoiceActionClassifier.classify(
                    utterance
                ),
                expected,
                utterance
            )
        }
    }

    func testTranslationSearchAndGeneralQuestionsKeepText() {
        XCTAssertEqual(
            LocalVoiceActionClassifier.classify(
                "안녕하세요를 영어로 번역해 줘"
            ),
            .translate(
                "안녕하세요를 영어로 번역해 줘"
            )
        )
        XCTAssertEqual(
            LocalVoiceActionClassifier.classify(
                "오늘 날씨 검색해 줘"
            ),
            .webSearch("오늘 날씨 검색해 줘")
        )
        XCTAssertEqual(
            LocalVoiceActionClassifier.classify(
                "무지개는 왜 생겨?"
            ),
            .question("무지개는 왜 생겨?")
        )
        XCTAssertNil(
            LocalVoiceActionClassifier.classify(
                " \n "
            )
        )
    }
}
