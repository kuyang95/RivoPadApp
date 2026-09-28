import Foundation
import XCTest
import ZIPFoundation
@testable import shortcuts_example

final class HWPDocumentRegressionTests: XCTestCase {
    private func package(_ paragraph: String) throws -> HWPXDocumentPackage {
        let archive = try Archive(accessMode: .create)
        let entries = [
            ("mimetype", "application/hwp+zip"),
            ("Contents/section0.xml", "<hs:sec xmlns:hs=\"http://www.hancom.co.kr/hwpml/2011/section\" xmlns:hp=\"http://www.hancom.co.kr/hwpml/2011/paragraph\">\(paragraph)</hs:sec>")
        ]
        for (path, text) in entries {
            let data = Data(text.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .none) { position, size in
                data.subdata(in: Int(position)..<min(data.count, Int(position) + size))
            }
        }
        return try HWPXDocumentPackage.load(from: XCTUnwrap(archive.data))
    }

    func testCanEditParagraphAgainAfterSavingTabAndNewline() throws {
        let initial = try package("<hp:p><hp:run charPrIDRef=\"0\"><hp:t>원문</hp:t></hp:run></hp:p>")
        var first = initial.blocks
        first[0].text = "첫째\t열\n둘째"
        let savedOnce = try initial.serializedData(applying: first)
        let reopened = try HWPXDocumentPackage.load(from: savedOnce)
        XCTAssertEqual(reopened.blocks[0].text, first[0].text)
        var second = reopened.blocks
        second[0].text = "최종 문장"
        let savedTwice = try reopened.serializedData(applying: second)
        XCTAssertEqual(try HWPXDocumentPackage.load(from: savedTwice).blocks[0].text, "최종 문장")
    }

    func testAppendingTextPreservesExistingMixedCharacterStyles() throws {
        let initial = try package("<hp:p><hp:run charPrIDRef=\"1\"><hp:t>중요</hp:t></hp:run><hp:run charPrIDRef=\"2\"><hp:t> 일반</hp:t></hp:run></hp:p>")
        var edited = initial.blocks
        edited[0].text += "!"
        let data = try initial.serializedData(applying: edited)
        let archive = try Archive(data: data, accessMode: .read)
        var payload = Data()
        _ = try archive.extract(XCTUnwrap(archive["Contents/section0.xml"])) { payload.append($0) }
        let xml = String(decoding: payload, as: UTF8.self)
        XCTAssertTrue(xml.contains("<hp:run charPrIDRef=\"1\"><hp:t>중요</hp:t></hp:run>"), xml)
        XCTAssertTrue(xml.contains("<hp:run charPrIDRef=\"2\"><hp:t> 일반!</hp:t></hp:run>"), xml)
    }

    func testHWPXParserPreservesMergedCellSpansForRendering() throws {
        let initial = try package("<hp:tbl><hp:tr><hp:tc><hp:cellAddr colAddr=\"0\" rowAddr=\"0\"/><hp:cellSpan colSpan=\"2\" rowSpan=\"3\"/><hp:subList><hp:p><hp:run><hp:t>병합</hp:t></hp:run></hp:p></hp:subList></hp:tc></hp:tr></hp:tbl>")
        let cell = try XCTUnwrap(initial.blocks.first?.tableLocation)
        XCTAssertEqual(cell.columnSpan, 2)
        XCTAssertEqual(cell.rowSpan, 3)
    }
    func testControlsOnlyRunsCDATAAndUnicodeCanBeSavedRepeatedly() throws {
        let source = try package("<hp:p><hp:run charPrIDRef=\"1\"><hp:tab/></hp:run><hp:run charPrIDRef=\"2\"><hp:t><![CDATA[가족 👨‍👩‍👧‍👦 & <한글>]]></hp:t></hp:run></hp:p>")
        var current = source
        for text in ["\t가족 👨‍👩‍👧‍👦 & <한글>!", "새\n줄\t값", "", "재입력 🇰🇷 e\u{0301}"] {
            var edited = current.blocks
            edited[0].text = text
            current = try HWPXDocumentPackage.load(from: current.serializedData(applying: edited))
            XCTAssertEqual(current.blocks[0].text, text)
        }
    }

    func testCellMetadataAfterParagraphsAndNestedCellsRemainsAssociated() throws {
        let source = try package("""
            <hp:tbl><hp:tr><hp:tc><hp:subList><hp:p><hp:run><hp:t>바깥</hp:t><hp:tbl><hp:tr><hp:tc><hp:subList><hp:p><hp:run><hp:t>안쪽</hp:t></hp:run></hp:p></hp:subList><hp:cellAddr colAddr="0" rowAddr="0"/></hp:tc></hp:tr></hp:tbl></hp:run></hp:p></hp:subList><hp:cellAddr colAddr="2" rowAddr="4"/><hp:cellSpan colSpan="3" rowSpan="2"/></hp:tc></hp:tr></hp:tbl>
            """)
        XCTAssertEqual(source.blocks[0].tableLocation?.column, 2)
        XCTAssertEqual(source.blocks[0].tableLocation?.row, 4)
        XCTAssertEqual(source.blocks[0].tableLocation?.columnSpan, 3)
        XCTAssertEqual(source.blocks[1].tableLocation?.table, 1)
        XCTAssertEqual(source.blocks[1].tableLocation?.column, 0)
    }

    func testSeparateEditsRetainUnchangedRunStyles() {
        XCTAssertEqual(
            HWPTextRunEditing.redistribute("A! 中間 Z?", originalSegments: ["A", " 中間 ", "Z"]),
            ["A!", " 中間 ", "Z?"]
        )
    }

    func testEditedHWPPreviewContainsNewTextAndWrapsToItsWidth() {
        let old = "이전 문장"
        let run = HWPDocumentTextRun(text: old, fontSizePoints: 12, isBold: true)
        let line = HWPDocumentLineLayout(id: "line", startCharacter: 0,
            verticalPositionPoints: 24, lineHeightPoints: 16, textHeightPoints: 12,
            baselinePoints: 12, lineSpacingPoints: 4, columnStartPoints: 10,
            widthPoints: 48, flags: 1, text: old, textRuns: [run])
        let block = HWPDocumentBlock(id: "p", sectionPath: "BodyText/Section0",
            paragraphIndex: 0, text: old, tableLocation: nil, isEditable: true,
            presentation: HWPDocumentBlockPresentation(textRuns: [run]), lineLayouts: [line])
        let text = "수정한 문장이 길어지면 새 줄로 표시합니다."
        let changed = HWPTextRunEditing.replacingText(in: block, with: text)
        XCTAssertEqual(changed.text, text)
        XCTAssertEqual(changed.presentation.textRuns.map(\.text).joined(), text)
        XCTAssertEqual(changed.lineLayouts.map(\.text).joined(), text)
        XCTAssertGreaterThan(changed.lineLayouts.count, 1)
        XCTAssertTrue(changed.presentation.textRuns.allSatisfy(\.isBold))
        XCTAssertEqual(changed.lineLayouts.first?.verticalPositionPoints, 24)
        XCTAssertTrue(changed.lineLayouts.dropFirst().allSatisfy { !$0.startsPage })
        XCTAssertEqual(block.lineLayouts.first?.text, old)
    }

}
