import XCTest

@testable import shortcuts_example

final class LiveTextDeduplicatorTests: XCTestCase {
    func testFirstMeaningfulTextIsAnnounced() {
        XCTAssertTrue(
            LiveTextDeduplicator.shouldAnnounce(
                "안녕하세요",
                after: ""
            )
        )
        XCTAssertFalse(
            LiveTextDeduplicator.shouldAnnounce(
                " ",
                after: ""
            )
        )
    }

    func testWhitespaceAndMinorPartialChangesAreSuppressed() {
        XCTAssertFalse(
            LiveTextDeduplicator.shouldAnnounce(
                "같은   문장입니다",
                after: "같은 문장입니다"
            )
        )
        XCTAssertFalse(
            LiveTextDeduplicator.shouldAnnounce(
                "문서를 읽고 있습니다.",
                after: "문서를 읽고 있습니다"
            )
        )
    }

    func testSubstantiallyDifferentTextIsAnnounced() {
        XCTAssertTrue(
            LiveTextDeduplicator.shouldAnnounce(
                "출입구는 오른쪽에 있습니다.",
                after: "오늘의 메뉴는 김치찌개입니다."
            )
        )
    }

    func testDigitAdjacentOCRLetterOIsComparedAsZero() {
        XCTAssertFalse(
            LiveTextDeduplicator.shouldAnnounce(
                "상품 번호 10o",
                after: "상품 번호 100"
            )
        )
    }

    func testShortInitialTextWaitsForStableSecondFrame() {
        var deduplicator = LiveTextDeduplicator()
        let quality = LiveTextOCRQuality(
            elementCount: 1,
            medianGlyphHeight: 32
        )

        let first = deduplicator.evaluate(
            "출입구",
            quality: quality,
            now: 1,
            isSpeaking: false
        )
        let second = deduplicator.evaluate(
            "출입구",
            quality: quality,
            now: 2,
            isSpeaking: false
        )

        XCTAssertEqual(first.disposition, .checking)
        XCTAssertEqual(
            first.reason,
            "initial_text_not_stable"
        )
        XCTAssertEqual(second.disposition, .announce)
        XCTAssertEqual(second.reason, "first_text")
    }

    func testRichSceneCanBeAnnouncedOnFirstFrame() {
        var deduplicator = LiveTextDeduplicator()
        let result = deduplicator.evaluate(
            "가 나 다 라 마 바 사 아 자 차 카 타 파 하 일 이 삼 사 오 육 칠 팔",
            quality: LiveTextOCRQuality(
                elementCount: 21,
                medianGlyphHeight: 30
            ),
            now: 1,
            isSpeaking: false
        )

        XCTAssertEqual(result.disposition, .announce)
        XCTAssertEqual(result.reason, "first_text")
    }

    func testSmallDenseTextIsRejectedBeforeSpeech() {
        var deduplicator = LiveTextDeduplicator()
        let result = deduplicator.evaluate(
            "하나 둘 셋 넷 다섯 여섯 일곱 여덟",
            quality: LiveTextOCRQuality(
                elementCount: 8,
                medianGlyphHeight: 15,
                below16Percentage: 100
            ),
            now: 1,
            isSpeaking: false
        )

        XCTAssertEqual(result.disposition, .lowQuality)
        XCTAssertEqual(result.reason, "low_ocr_quality")
    }

    func testRichSceneAnchorSuppressesPartialRecognition() {
        var deduplicator = LiveTextDeduplicator()
        let richText =
            "가 나 다 라 마 바 사 아 자 차 카 타 파 하 일 이 삼 사 오 육 칠 팔"
        _ = deduplicator.evaluate(
            richText,
            quality: LiveTextOCRQuality(
                elementCount: 21,
                medianGlyphHeight: 30
            ),
            now: 1,
            isSpeaking: false
        )

        let partial = deduplicator.evaluate(
            "가 나",
            quality: LiveTextOCRQuality(
                elementCount: 2,
                medianGlyphHeight: 30
            ),
            now: 4,
            isSpeaking: false
        )

        XCTAssertEqual(partial.disposition, .suppressed)
        XCTAssertEqual(partial.reason, "same_scene_anchor")
    }

    func testSimilarSceneDoesNotInterruptActiveSpeech() {
        var deduplicator = LiveTextDeduplicator()
        let quality = LiveTextOCRQuality(
            elementCount: 4,
            medianGlyphHeight: 30
        )
        _ = deduplicator.evaluate(
            "알파 베타 감마 델타",
            quality: quality,
            now: 1,
            isSpeaking: false
        )
        _ = deduplicator.evaluate(
            "알파 베타 감마 델타",
            quality: quality,
            now: 2,
            isSpeaking: false
        )

        let result = deduplicator.evaluate(
            "알파 베타 감마 엡실론",
            quality: quality,
            now: 4,
            isSpeaking: true
        )

        XCTAssertEqual(result.disposition, .suppressed)
        XCTAssertEqual(
            result.reason,
            "same_scene_while_speaking"
        )
    }

    func testThreeNoTextFramesClearSceneAnchor() {
        var deduplicator = LiveTextDeduplicator()
        let richText =
            "가 나 다 라 마 바 사 아 자 차 카 타 파 하 일 이 삼 사 오 육 칠 팔"
        _ = deduplicator.evaluate(
            richText,
            quality: LiveTextOCRQuality(
                elementCount: 21,
                medianGlyphHeight: 30
            ),
            now: 1,
            isSpeaking: false
        )
        for time in 2 ... 4 {
            _ = deduplicator.evaluate(
                "",
                quality: LiveTextOCRQuality(),
                now: TimeInterval(time),
                isSpeaking: false
            )
        }

        let newScene = deduplicator.evaluate(
            "가 나",
            quality: LiveTextOCRQuality(
                elementCount: 2,
                medianGlyphHeight: 30
            ),
            now: 40,
            isSpeaking: false
        )

        XCTAssertEqual(newScene.disposition, .announce)
        XCTAssertEqual(newScene.reason, "new_text")
    }

    func testVisionLineHeightsBecomeElementWeightedQuality() {
        let quality = LiveTextDeduplicator.quality(
            lineTexts: [
                "하나 둘 셋 넷",
                "다섯 여섯"
            ],
            linePixelHeights: [12, 30]
        )

        XCTAssertEqual(quality.elementCount, 6)
        XCTAssertEqual(quality.medianGlyphHeight, 12)
        XCTAssertEqual(quality.below16Percentage, 66)
        XCTAssertFalse(quality.isLowForSpeech)
    }

    func testSpokenTextUsesAndroidFiveHundredCharacterLimit() {
        var deduplicator = LiveTextDeduplicator()
        let result = deduplicator.evaluate(
            String(repeating: "가", count: 600),
            quality: LiveTextOCRQuality(
                elementCount: 1,
                medianGlyphHeight: 30
            ),
            now: 1,
            isSpeaking: false
        )

        XCTAssertEqual(result.disposition, .announce)
        XCTAssertEqual(result.text.count, 500)
    }
}
