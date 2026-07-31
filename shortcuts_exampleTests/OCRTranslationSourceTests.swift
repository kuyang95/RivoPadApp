import XCTest

@testable import shortcuts_example

final class OCRTranslationSourceTests:
    XCTestCase
{
    func testPreservesRecognizedTextExactly() {
        let text =
            "첫 줄\n\nSecond line "

        XCTAssertEqual(
            OCRTranslationSource.make(
                from: text
            ),
            text
        )
    }

    func testRejectsWhitespaceOnlyText() {
        XCTAssertNil(
            OCRTranslationSource.make(
                from: " \n\t "
            )
        )
    }
}
