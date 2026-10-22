import XCTest

@testable import shortcuts_example

final class AIDocumentOriginalOpenerTests: XCTestCase {
    func testOnlySpreadsheetAndHangulRowsGetAnOpenButton() {
        XCTAssertEqual(
            AIDocumentOriginalOpener(pathExtension: "XLSX")?.labelKey,
            "aiDocument.openSpreadsheetEditor"
        )
        XCTAssertEqual(
            AIDocumentOriginalOpener(pathExtension: "hwp")?.labelKey,
            "aiDocument.readHangul"
        )
        XCTAssertEqual(
            AIDocumentOriginalOpener(pathExtension: "hwpx")?.labelKey,
            "aiDocument.readHangul"
        )
        for other in ["pdf", "txt", "xls", ""] {
            XCTAssertNil(AIDocumentOriginalOpener(pathExtension: other), other)
        }
    }

    func testButtonLabelsReadAsAndroid() {
        let expected: [(AppLanguage, String, String)] = [
            (.korean, "엑셀에서 편집", "읽기"),
            (.english, "Edit spreadsheet", "Read"),
            (.japanese, "表計算で編集", "読む"),
        ]
        for (language, edit, read) in expected {
            XCTAssertEqual(
                AppLocalization.string(
                    "aiDocument.openSpreadsheetEditor",
                    language: language
                ),
                edit
            )
            XCTAssertEqual(
                AppLocalization.string(
                    "aiDocument.readHangul",
                    language: language
                ),
                read
            )
        }
    }
}
