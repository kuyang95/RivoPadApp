import Foundation
import XCTest

@testable import shortcuts_example

final class HelpDocumentTests: XCTestCase {
    func testManualParserPreservesHierarchyAndContinuation()
        throws
    {
        let source = """
        \u{FEFF}@title 설명서
        이어지는 제목
        @version 1.2
        @date 오늘
        @chapter 시작
        @section 기본
        @text #과 /와 "따옴표"를 보존합니다.
        이어지는 설명
        @subsection 세부
        @text 세부 내용
        """

        let document = try HelpDocumentParser
            .parseManual(source)

        XCTAssertEqual(
            document.title,
            "설명서\n이어지는 제목"
        )
        XCTAssertEqual(
            document.chapters.count,
            1
        )
        let section = try XCTUnwrap(
            document.chapters.first?
                .sections.first
        )
        XCTAssertEqual(
            section.texts,
            [
                "#과 /와 \"따옴표\"를 보존합니다.\n이어지는 설명"
            ]
        )
        XCTAssertEqual(
            section.subsections.first?
                .texts,
            ["세부 내용"]
        )
    }

    func testManualParserFlushesMultipleChapters()
        throws
    {
        let source = """
        @title 설명서
        @version 1
        @date 오늘
        @chapter 하나
        @section 첫째
        @text 내용 1
        @section 둘째
        @text 내용 2
        @chapter 둘
        @section 셋째
        @text 내용 3
        """

        let document = try HelpDocumentParser
            .parseManual(source)

        XCTAssertEqual(
            document.chapters.map(\.name),
            ["하나", "둘"]
        )
        XCTAssertEqual(
            document.chapters[0]
                .sections.map(\.name),
            ["첫째", "둘째"]
        )
        XCTAssertEqual(
            document.chapters[1]
                .sections.first?.texts,
            ["내용 3"]
        )
    }

    func testManualParserRejectsMisplacedText()
    {
        XCTAssertThrowsError(
            try HelpDocumentParser.parseManual(
                """
                @title 설명서
                @text 섹션 없는 내용
                """
            )
        ) { error in
            XCTAssertEqual(
                error as? HelpDocumentError,
                .misplacedDirective("@text")
            )
        }
    }

    func testReleaseNotesParserKeepsNewestFirst()
        throws
    {
        let notes = try HelpDocumentParser
            .parseReleaseNotes(
                """
                @title 변경 내역
                @version 2.0
                @date 오늘
                @text 새 기능
                @version 1.0
                @date 어제
                @text 첫 버전
                """
            )

        XCTAssertEqual(
            notes.map(\.version),
            ["2.0", "1.0"]
        )
        XCTAssertEqual(
            notes.first?.texts,
            ["새 기능"]
        )
    }

    func testReleaseNotesRequireDate()
    {
        XCTAssertThrowsError(
            try HelpDocumentParser
                .parseReleaseNotes(
                    """
                    @version 2.0
                    @text 날짜 없는 변경
                    """
                )
        ) { error in
            XCTAssertEqual(
                error as? HelpDocumentError,
                .missingValue("@date")
            )
        }
    }

    func testBundledIPadManualAndReleaseNotesLoad()
        throws
    {
        let manual =
            try HelpContentLibrary.manual()
        let notes =
            try HelpContentLibrary
            .releaseNotes()

        XCTAssertEqual(manual.version, "1.0")
        XCTAssertGreaterThanOrEqual(
            manual.chapters.count,
            8
        )
        XCTAssertTrue(
            manual.chapters.contains {
                $0.name == "Android와 다른 점"
            }
        )
        XCTAssertEqual(
            notes.first?.version,
            "1.0"
        )
        XCTAssertTrue(
            notes.first?.texts.contains {
                $0.contains(
                    "App Shortcut 10개"
                )
            } == true
        )
    }
}
