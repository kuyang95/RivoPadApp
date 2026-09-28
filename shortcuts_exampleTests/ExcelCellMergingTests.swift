import Foundation
import CoreGraphics
import XCTest
@testable import shortcuts_example

final class ExcelCellMergingTests: XCTestCase {
    private func address(_ ref: String) -> ExcelCellAddress { ExcelCellAddress(ref)! }
    private func range(_ ref: String) -> ExcelCellRange { ExcelCellRange(ref)! }

    private func fixture() throws -> Data {
        let blank = try ExcelWorkbookDocument.blankWorkbookData(sheetName: "Data")
        let book = try ExcelWorkbookDocument.load(from: blank)
        let values = ["A1": "Title", "B1": "Other", "A2": "3", "B2": "=A2*2", "D1": "Untouched"]
        return try ExcelWorkbookDocument.applying([
            ExcelWorksheetEdits(partPath: book.sheets[0].partPath, cells: Dictionary(uniqueKeysWithValues: values.map {
                (address($0.key), ExcelCellEdit(input: ExcelCellInput(userText: $0.value), styleIndex: nil))
            }))
        ], to: blank, workbook: book)
    }

    private func apply(_ edit: ExcelAdvancedEdit, to data: Data) throws -> Data {
        try ExcelAdvancedWorkbookEditing.applying(edit, to: data, workbook: ExcelWorkbookDocument.load(from: data), sheetIndex: 0)
    }

    private func rewriteSheet(_ data: Data, _ mutate: (ExcelEditingXML.Node) throws -> Void) throws -> Data {
        let book = try ExcelWorkbookDocument.load(from: data)
        let reader = try ExcelArchiveReader(data: data)
        let path = book.sheets[0].partPath
        let root = try ExcelEditingXML.parse(reader.data(at: path))
        try mutate(root)
        return try reader.repack(replacing: [path: ExcelEditingXML.data(root)])
    }

    func testMergeRequiresExplicitValueDiscardAndKeepsOnlyAnchor() throws {
        let data = try fixture()
        let book = try ExcelWorkbookDocument.load(from: data)
        let plan = try ExcelCellMergePlan(range: range("A1:B2"), sheet: book.sheets[0])
        XCTAssertEqual(plan.discardedAddresses, [address("B1"), address("A2"), address("B2")])
        XCTAssertThrowsError(try apply(.merge(plan.range, center: false), to: data))

        let merged = try apply(.merge(plan.range, center: false, discardOtherValues: true), to: data)
        let sheet = try ExcelWorkbookDocument.load(from: merged).sheets[0]
        XCTAssertEqual(sheet.mergedRanges, [range("A1:B2")])
        XCTAssertEqual(sheet.cells[address("A1")]?.rawValue, "Title")
        XCTAssertEqual(sheet.cells[address("D1")]?.rawValue, "Untouched")
        for ref in ["B1", "A2", "B2"] {
            XCTAssertTrue(sheet.cells[address(ref)]?.rawValue.isEmpty ?? true)
            XCTAssertNil(sheet.cells[address(ref)]?.formula)
        }
        XCTAssertEqual(sheet.canonicalAddress(for: address("B2")), address("A1"))
    }

    func testCenterPreservesFontNumberFormatAndChildStyles() throws {
        var format = ExcelBasicFormat(); format.bold = true; format.fillColor = "FFFFFF00"
        let formatted = try apply(.format(range("A1:B2"), format), to: fixture())
        let before = try ExcelWorkbookDocument.load(from: formatted)
        let data = try apply(.merge(range("A1:B2"), center: true, discardOtherValues: true), to: formatted)
        let book = try ExcelWorkbookDocument.load(from: data)
        let style = book.style(at: book.sheets[0].cells[address("A1")]?.styleIndex)
        XCTAssertEqual(style.horizontalAlignment, "center")
        XCTAssertTrue(style.isBold)
        XCTAssertEqual(style.fillARGB, "FFFFFF00")
        XCTAssertEqual(style.numberFormatID, before.style(at: before.sheets[0].cells[address("A1")]?.styleIndex).numberFormatID)
        XCTAssertTrue(book.style(at: book.sheets[0].cells[address("B2")]?.styleIndex).isBold)
    }

    func testOverlappingMergeIncludesWholeExistingMerge() throws {
        let data = try apply(.merge(range("B2:C3"), center: false), to: ExcelWorkbookDocument.blankWorkbookData())
        let expanded = try apply(.merge(range("A1:B2"), center: false), to: data)
        XCTAssertEqual(try ExcelWorkbookDocument.load(from: expanded).sheets[0].mergedRanges, [range("A1:C3")])
    }

    func testUnmergeFromOneChildPreservesOtherMergesAndAnchorValue() throws {
        let first = try apply(.merge(range("A1:B2"), center: false, discardOtherValues: true), to: fixture())
        let second = try apply(.merge(range("D4:E4"), center: false), to: first)
        let unmerged = try apply(.unmerge(range("B2")), to: second)
        let sheet = try ExcelWorkbookDocument.load(from: unmerged).sheets[0]
        XCTAssertEqual(sheet.mergedRanges, [range("D4:E4")])
        XCTAssertEqual(sheet.cells[address("A1")]?.rawValue, "Title")
        XCTAssertEqual(sheet.canonicalAddress(for: address("B2")), address("B2"))
        XCTAssertTrue(sheet.cells[address("B1")]?.rawValue.isEmpty ?? true)
        let final = try apply(.unmerge(range("D4:E4")), to: unmerged)
        let reader = try ExcelArchiveReader(data: final)
        XCTAssertNil(try ExcelEditingXML.parse(reader.data(at: sheet.partPath)).child("mergeCells"))
        XCTAssertThrowsError(try apply(.unmerge(range("A1")), to: final))
    }

    func testMergingSharedFormulaAnchorPreservesFollowersOutsideRange() throws {
        let data = try rewriteSheet(fixture()) { root in
            let master = ExcelAdvancedWorkbookEditing.ensureCell(address("B2"), in: root).ensure("f")
            master.attributes = ["t": "shared", "si": "0", "ref": "B2:B3"]; master.text = "A2*2"
            let follower = ExcelAdvancedWorkbookEditing.ensureCell(address("B3"), in: root).ensure("f")
            follower.attributes = ["t": "shared", "si": "0"]; follower.children = []
        }
        let merged = try apply(.merge(range("A2:B2"), center: false, discardOtherValues: true), to: data)
        XCTAssertEqual(try ExcelWorkbookDocument.load(from: merged).sheets[0].cells[address("B3")]?.formula, "A3*2")
    }

    func testTableArrayAndOversizedRangesAreRejected() throws {
        let book = try ExcelWorkbookDocument.load(from: fixture())
        var tableSheet = book.sheets[0]
        tableSheet.tables = [ExcelTable(id: "1", name: "Table1", range: range("A1:B2"), partPath: "xl/tables/table1.xml")]
        XCTAssertThrowsError(try ExcelCellMergePlan(range: range("A1:B1"), sheet: tableSheet))
        var arraySheet = book.sheets[0]
        arraySheet.cells[address("B2")]?.spillAnchor = address("B2")
        arraySheet.cells[address("B2")]?.spillRange = range("B2:B4")
        XCTAssertThrowsError(try ExcelCellMergePlan(range: range("A4:B4"), sheet: arraySheet))
        XCTAssertThrowsError(try ExcelCellMergePlan(range: range("A1"), sheet: book.sheets[0]))
        XCTAssertThrowsError(try ExcelCellMergePlan(range: range("A1:GR2000"), sheet: book.sheets[0]))
        XCTAssertThrowsError(try ExcelCellMergePlan(range: range("A3000:B3000"), sheet: book.sheets[0]))
    }

    func testBlankMergedRangeExtendsWorksheetDimension() throws {
        let data = try apply(.merge(range("F7:J9"), center: false), to: ExcelWorkbookDocument.blankWorkbookData())
        let sheet = try ExcelWorkbookDocument.load(from: data).sheets[0]
        XCTAssertEqual(sheet.maximumColumn, 10); XCTAssertEqual(sheet.maximumRow, 9)
        let reader = try ExcelArchiveReader(data: data)
        XCTAssertEqual(try ExcelEditingXML.parse(reader.data(at: sheet.partPath)).child("dimension")?.attributes["ref"], "A1:J9")
    }

    func testMergedRectangleSpansRowsColumnsAndWindowEdges() {
        let rect = ExcelMergedCellGeometry.rect(for: range("B2:C4"), columns: 1 ... 4,
            rows: [(1, 42, 30), (2, 72, 50), (4, 122, 40)], rowHeaderWidth: 54, columnWidth: { CGFloat($0 * 40) })
        XCTAssertEqual(rect, CGRect(x: 94, y: 72, width: 200, height: 90))
        // Anchor B2 is outside this window. Its visible tail still represents B2:C4.
        let tail = ExcelMergedCellGeometry.rect(for: range("B2:C4"), columns: 3 ... 5,
            rows: [(4, 42, 40), (5, 82, 40)], rowHeaderWidth: 54, columnWidth: { _ in 80 })
        XCTAssertEqual(tail, CGRect(x: 54, y: 42, width: 80, height: 40))
    }
}
