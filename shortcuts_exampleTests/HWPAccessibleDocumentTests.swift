import RivoDocumentEngine
import Foundation
import XCTest
import ZIPFoundation
@testable import shortcuts_example

final class HWPAccessibleDocumentTests: XCTestCase {
    private func block(_ id: String, text: String = "", section: String = "Contents/section0.xml",
        table: Int? = nil, row: Int = 0, column: Int = 0, paragraph: Int = 0,
        rowSpan: Int = 1, columnSpan: Int = 1,
        parent: HWPDocumentTableParentLocation? = nil) -> HWPDocumentBlock {
        HWPDocumentBlock(id: id, sectionPath: section, paragraphIndex: paragraph, text: text,
            tableLocation: table.map { HWPDocumentTableLocation(table: $0, row: row, column: column,
                paragraph: paragraph, rowSpan: rowSpan, columnSpan: columnSpan, parent: parent) }, isEditable: true)
    }

    func testApplicationFormKeepsEmptyFieldsAndCellParagraphsInDocumentOrder() throws {
        let blocks = [block("heading", text: "신청서"), block("blank-body"),
            block("name", text: "성명", table: 0), block("empty-name", table: 0, column: 1),
            block("work", text: "작품 설명", table: 0, row: 1),
            block("description-1", text: "첫 문단", table: 0, row: 1, column: 1),
            block("description-2", text: "둘째 문단", table: 0, row: 1, column: 1, paragraph: 1),
            block("footer", text: "서명")]
        let document = HWPAccessibleDocument.make(blocks: blocks)
        let table = try XCTUnwrap(document.tables.first)
        XCTAssertEqual(document.tables.count, 1)
        XCTAssertEqual(table.rowCount, 2)
        XCTAssertEqual(table.columnCount, 2)
        XCTAssertEqual(table.rows[0].cells.count, 2)
        XCTAssertTrue(table.rows[0].cells[1].isEmpty)
        XCTAssertEqual(table.rows[1].cells[1].blocks.map(\.id), ["description-1", "description-2"])
        XCTAssertEqual(table.rows[1].cells[1].text, "첫 문단\n둘째 문단")
        XCTAssertEqual(document.entries.first?.id, "heading")
        XCTAssertEqual(document.entries.last?.id, "footer")
        XCTAssertNil(document.entryIDByBlockID["blank-body"])
        XCTAssertEqual(document.entryIDByBlockID["empty-name"], table.rows[0].id)
        XCTAssertEqual(document.entryIDByBlockID["description-2"], table.rows[1].id)
    }

    func testRepeatedTableNumbersAcrossSectionsDoNotCombineUnrelatedForms() {
        let document = HWPAccessibleDocument.make(blocks: [
            block("a", text: "첫 표", table: 0),
            block("b", text: "둘째 표", section: "Contents/section1.xml", table: 0)])
        XCTAssertEqual(document.tables.count, 2)
        XCTAssertNotEqual(document.tables[0].id, document.tables[1].id)
        XCTAssertEqual(document.tables[0].rows[0].blocks.map(\.id), ["a"])
        XCTAssertEqual(document.tables[1].rows[0].blocks.map(\.id), ["b"])
    }

    func testMergedCellsProvideContextWithoutDuplicatingEditableParagraphs() {
        let document = HWPAccessibleDocument.make(blocks: [
            block("merged", text: "신청인", table: 0, rowSpan: 2, columnSpan: 2),
            block("name", text: "성명", table: 0, column: 2),
            block("contact", text: "연락처", table: 0, row: 1, column: 2)])
        let table = document.tables[0]
        XCTAssertEqual(table.rowCount, 2)
        XCTAssertEqual(table.columnCount, 3)
        XCTAssertEqual(table.rows[1].spanningCells.map(\.id), ["merged"])
        XCTAssertEqual(table.rows[1].blocks.map(\.id), ["contact"])
        XCTAssertEqual(table.rows.flatMap(\.blocks).filter { $0.id == "merged" }.count, 1)
    }

    func testNestedTableDoesNotSplitOrMergeOuterCellParagraphs() {
        let document = HWPAccessibleDocument.make(blocks: [
            block("outer-1", text: "바깥 첫 문단", table: 0),
            block("inner", text: "안쪽 표", table: 1,
                parent: HWPDocumentTableParentLocation(table: 0, row: 0, column: 0)),
            block("outer-2", text: "바깥 둘째 문단", table: 0, paragraph: 1),
            block("outer-next-row", text: "다음 행", table: 0, row: 1)])
        XCTAssertEqual(document.tables.count, 2)
        XCTAssertEqual(document.tables[0].rows[0].cells[0].blocks.map(\.id), ["outer-1", "outer-2"])
        XCTAssertEqual(document.tables[1].rows[0].blocks.map(\.id), ["inner"])
        XCTAssertEqual(document.tables[0].rows[0].cells[0].nestedTables.first?.id, document.tables[1].id)
        XCTAssertEqual(document.entries.map(\.id), [document.tables[0].id,
            document.tables[0].rows[0].id, document.tables[1].id,
            document.tables[1].rows[0].id, document.tables[0].rows[1].id])
    }

    @MainActor
    func testEditingBlankFieldsSupportsSingleUndoAndPreservesCellsOnSave() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        defer { try? FileManager.default.removeItem(at: url) }
        try formData().write(to: url)
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let row = try XCTUnwrap(HWPAccessibleDocument.make(blocks: model.blocks).tables.first?.rows.first)
        XCTAssertEqual(model.accessibleBlocks.filter { $0.tableLocation != nil }.count, 4)
        let name = row.cells[1].blocks[0]
        let contact = row.cells[3].blocks[0]
        try model.applyTableRowEdits(originalBlocks: row.blocks,
            texts: [name.id: "홍길동", contact.id: "010-1234-5678"])
        XCTAssertEqual(model.blocks.first { $0.id == name.id }?.text, "홍길동")
        XCTAssertEqual(model.blocks.first { $0.id == contact.id }?.text, "010-1234-5678")
        model.undo()
        XCTAssertEqual(model.blocks.first { $0.id == name.id }?.text, "")
        XCTAssertEqual(model.blocks.first { $0.id == contact.id }?.text, "")
        model.redo()
        await model.save()
        XCTAssertNil(model.errorDescription)
        let saved = try HWPXDocumentPackage.load(from: Data(contentsOf: url))
        let savedCells = HWPAccessibleDocument.make(blocks: saved.blocks).tables[0].rows[0].cells
        XCTAssertEqual(savedCells.map(\.text), ["성명", "홍길동", "연락처", "010-1234-5678"])
    }

    @MainActor
    func testStaleRowEditRejectsAllChangesBeforeApplyingAnyCell() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        defer { try? FileManager.default.removeItem(at: url) }
        try formData().write(to: url)
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let row = try XCTUnwrap(HWPAccessibleDocument.make(blocks: model.blocks).tables.first?.rows.first)
        let name = row.cells[1].blocks[0]
        let contact = row.cells[3].blocks[0]
        model.selectBlock(contact.id)
        model.editorText = "이미 바뀐 값"
        model.commitEditorChange()
        XCTAssertThrowsError(try model.applyTableRowEdits(originalBlocks: row.blocks,
            texts: [name.id: "홍길동", contact.id: "오래된 수정안"]))
        XCTAssertEqual(model.blocks.first { $0.id == name.id }?.text, "")
        XCTAssertEqual(model.blocks.first { $0.id == contact.id }?.text, "이미 바뀐 값")
    }

    private func formData() throws -> Data {
        let cells = ["성명", "", "연락처", ""].enumerated().map { column, text in
            "<hp:tc><hp:cellAddr colAddr=\"\(column)\" rowAddr=\"0\"/><hp:subList><hp:p><hp:run><hp:t>\(text)</hp:t></hp:run></hp:p></hp:subList></hp:tc>"
        }.joined()
        let archive = try Archive(accessMode: .create)
        for (path, text) in [
            ("mimetype", "application/hwp+zip"),
            ("Contents/section0.xml", "<hs:sec xmlns:hs=\"http://www.hancom.co.kr/hwpml/2011/section\" xmlns:hp=\"http://www.hancom.co.kr/hwpml/2011/paragraph\"><hp:tbl><hp:tr>\(cells)</hp:tr></hp:tbl></hs:sec>")
        ] {
            let data = Data(text.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .none) { position, size in
                data.subdata(in: Int(position)..<min(data.count, Int(position) + size))
            }
        }
        return try XCTUnwrap(archive.data)
    }
}
