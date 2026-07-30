import Foundation
import XCTest

@testable import shortcuts_example

final class AppLocalizationTests:
    XCTestCase
{
    func testEnglishAndJapaneseShellStringsLoad()
        throws
    {
        let english = try localizedBundle(
            language: "en"
        )
        let japanese = try localizedBundle(
            language: "ja"
        )

        XCTAssertEqual(
            AppLocalization.string(
                "설정",
                bundle: english
            ),
            "Settings"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "도움말",
                bundle: japanese
            ),
            "ヘルプ"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "Rivo 리모컨",
                bundle: english
            ),
            "Rivo Remote"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "로컬 번역",
                bundle: english
            ),
            "On-Device Translation"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "번역 결과",
                bundle: japanese
            ),
            "翻訳結果"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "웹페이지 질문",
                bundle: english
            ),
            "Ask About a Webpage"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "본문 읽기",
                bundle: japanese
            ),
            "本文を読む"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "웹 검색",
                bundle: english
            ),
            "Web Search"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "선택적 웹 검색",
                bundle: japanese
            ),
            "任意のWeb検索"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "AI 대화",
                bundle: english
            ),
            "AI Conversations"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "모든 대화를 삭제할까요?",
                bundle: japanese
            ),
            "すべての会話を削除しますか？"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "답변 음성",
                bundle: english
            ),
            "Spoken Answer"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "대화에 첨부",
                bundle: english
            ),
            "Attach to Conversation"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "다음 행동",
                bundle: japanese
            ),
            "次の行動"
        )
    }

    func testDynamicFormatTranslationsPreserveArguments()
        throws
    {
        let english = try localizedBundle(
            language: "en"
        )
        let japanese = try localizedBundle(
            language: "ja"
        )

        let englishRate = String(
            format: AppLocalization.string(
                "재생 속도 배수 형식",
                bundle: english
            ),
            "1.25"
        )
        let japaneseDevice = String(
            format: AppLocalization.string(
                "%@ 연결됨",
                bundle: japanese
            ),
            "Rivo Three"
        )
        let englishWebStatus = String(
            format: AppLocalization.string(
                "웹 서버가 오류 상태 %lld를 반환했습니다.",
                bundle: english
            ),
            404
        )
        let japaneseBodyCount = String(
            format: AppLocalization.string(
                "본문 %lld자",
                bundle: japanese
            ),
            1200
        )
        let englishSearchCount =
            String(
                format:
                    AppLocalization.string(
                        "검색 출처 %lld개",
                        bundle: english
                    ),
                5
            )
        let japaneseMessageCount =
            String(
                format:
                    AppLocalization.string(
                        "메시지 %lld개",
                        bundle: japanese
                    ),
                12
            )
        let englishAnswerPosition =
            String(
                format:
                    AppLocalization.string(
                        "답변 문장 %lld/%lld",
                        bundle: english
                    ),
                2,
                5
            )
        let japaneseAttachmentCount =
            String(
                format:
                    AppLocalization.string(
                        "텍스트 문맥 %lld개",
                        bundle: japanese
                    ),
                3
            )

        XCTAssertEqual(englishRate, "1.25×")
        XCTAssertEqual(
            japaneseDevice,
            "Rivo Threeに接続済み"
        )
        XCTAssertEqual(
            englishWebStatus,
            "The web server returned error status 404."
        )
        XCTAssertEqual(
            japaneseBodyCount,
            "本文1200文字"
        )
        XCTAssertEqual(
            englishSearchCount,
            "5 search sources"
        )
        XCTAssertEqual(
            japaneseMessageCount,
            "メッセージ12件"
        )
        XCTAssertEqual(
            englishAnswerPosition,
            "Answer sentence 2 of 5"
        )
        XCTAssertEqual(
            japaneseAttachmentCount,
            "テキストコンテキスト3件"
        )
    }

    func testPermissionDescriptionsAreLocalized()
        throws
    {
        let english = try localizedBundle(
            language: "en"
        )
        let japanese = try localizedBundle(
            language: "ja"
        )

        XCTAssertTrue(
            infoPlistString(
                "NSCameraUsageDescription",
                bundle: english
            )
            .contains("Camera")
        )
        XCTAssertTrue(
            infoPlistString(
                "NSBluetoothAlwaysUsageDescription",
                bundle: japanese
            )
            .contains("Bluetooth")
        )
    }

    private func localizedBundle(
        language: String
    ) throws -> Bundle {
        let url = try XCTUnwrap(
            Bundle.main.url(
                forResource: language,
                withExtension: "lproj"
            )
        )
        return try XCTUnwrap(
            Bundle(url: url)
        )
    }

    private func infoPlistString(
        _ key: String,
        bundle: Bundle
    ) -> String {
        bundle.localizedString(
            forKey: key,
            value: "",
            table: "InfoPlist"
        )
    }
}
