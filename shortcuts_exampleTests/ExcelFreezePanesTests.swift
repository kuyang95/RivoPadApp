import Foundation
import CoreGraphics
import XCTest
@testable import shortcuts_example

final class ExcelFreezePanesTests: XCTestCase {
    private func apply(_ edit: ExcelAdvancedEdit, to data: Data) throws -> Data {
        try ExcelAdvancedWorkbookEditing.applying(edit, to: data, workbook: ExcelWorkbookDocument.load(from: data), sheetIndex: 0)
    }
    private func root(_ data: Data) throws -> ExcelEditingXML.Node {
        let reader = try ExcelArchiveReader(data: data)
        let book = try ExcelWorkbookDocument.load(from: data)
        return try ExcelEditingXML.parse(reader.data(at: book.sheets[0].partPath))
    }

    func testFirstRowAndFirstColumnPersistWithoutChangingCells() throws {
        let blank = try ExcelWorkbookDocument.blankWorkbookData(), book = try ExcelWorkbookDocument.load(from: blank)
        let data = try ExcelWorkbookDocument.applying([.init(partPath: book.sheets[0].partPath, cells: [ExcelCellAddress("B2")!: ExcelCellEdit(input: .text("Keep me"), styleIndex: nil)])], to: blank, workbook: book)
        for panes in [ExcelFrozenPanes(rows: 1, columns: 0), .init(rows: 0, columns: 1)] {
            let result = try apply(.freezePanes(panes), to: data)
            let sheet = try ExcelWorkbookDocument.load(from: result).sheets[0]
            XCTAssertEqual(sheet.frozenPanes, panes)
            XCTAssertEqual(sheet.cells[ExcelCellAddress("B2")!]?.rawValue, "Keep me")
            XCTAssertEqual(try root(result).child("sheetViews")?.child("sheetView")?.child("pane")?.attributes["topLeftCell"], panes.firstScrollableCell.reference)
        }
    }

    func testSelectedCellFreezeAndUnfreezeKeepOtherViewSettings() throws {
        let blank = try ExcelWorkbookDocument.blankWorkbookData(), reader = try ExcelArchiveReader(data: blank)
        let xml = try root(blank), view = try XCTUnwrap(xml.child("sheetViews")?.child("sheetView"))
        view.attributes["zoomScale"] = "140"; view.attributes["showGridLines"] = "0"
        view.attributes["workbookViewId"] = nil
        view.remove("selection")
        view.children.append(view.make("selection", ["activeCell": "D3", "sqref": "A1 B2 D3", "activeCellId": "2"]))
        let initial = try reader.repack(replacing: ["xl/worksheets/sheet1.xml": ExcelEditingXML.data(xml)])
        let frozen = try apply(.freezePanes(.init(rows: 2, columns: 1)), to: initial)
        let savedView = try XCTUnwrap(root(frozen).child("sheetViews")?.child("sheetView"))
        XCTAssertEqual(savedView.child("pane")?.attributes["activePane"], "bottomRight")
        XCTAssertEqual(savedView.child("pane")?.attributes["topLeftCell"], "B3")
        XCTAssertEqual(try root(frozen).child("sheetViews")?.elements("sheetView").count, 1)
        XCTAssertNil(savedView.child("selection")?.attributes["activeCellId"])
        let cleared = try apply(.freezePanes(.none), to: frozen)
        let clearedView = try XCTUnwrap(root(cleared).child("sheetViews")?.child("sheetView"))
        XCTAssertNil(clearedView.child("pane"))
        XCTAssertNil(clearedView.child("selection")?.attributes["pane"])
        XCTAssertEqual(clearedView.attributes["zoomScale"], "140")
        XCTAssertEqual(clearedView.attributes["showGridLines"], "0")
        XCTAssertEqual(try ExcelWorkbookDocument.load(from: cleared).sheets[0].frozenPanes, .none)
    }

    func testImportedFrozenSplitAndSecondaryWindowAreReadCorrectly() throws {
        XCTAssertEqual(ExcelFrozenPanes.read(["state": "frozenSplit", "xSplit": "2.0", "ySplit": "3"]), .init(rows: 3, columns: 2))
        XCTAssertEqual(ExcelFrozenPanes.read(["state": "split", "xSplit": "1000", "ySplit": "500"]), .none)
        XCTAssertEqual(ExcelFrozenPanes.read(["state": "frozen", "xSplit": "nan", "ySplit": "1.5"]), .none)
        let blank = try ExcelWorkbookDocument.blankWorkbookData(), reader = try ExcelArchiveReader(data: blank)
        let xml = try root(blank)
        try ExcelFrozenPanes(rows: 1, columns: 1).write(to: xml)
        let views = try XCTUnwrap(xml.child("sheetViews"))
        let second = views.make("sheetView", ["workbookViewId": "1"])
        second.children = [second.make("pane", ["state": "frozen", "ySplit": "7"])]
        views.children.append(second)
        let data = try reader.repack(replacing: ["xl/worksheets/sheet1.xml": ExcelEditingXML.data(xml)])
        XCTAssertEqual(try ExcelWorkbookDocument.load(from: data).sheets[0].frozenPanes, .init(rows: 1, columns: 1))
    }

    func testRowAndColumnStructureMovesTheFrozenBoundary() throws {
        let frozen = try apply(.freezePanes(.init(rows: 3, columns: 2)), to: ExcelWorkbookDocument.blankWorkbookData())
        let inserted = try apply(.structure(.init(axis: .row, index: 2, count: 2, deleting: false)), to: frozen)
        XCTAssertEqual(try ExcelWorkbookDocument.load(from: inserted).sheets[0].frozenPanes, .init(rows: 5, columns: 2))
        let deleted = try apply(.structure(.init(axis: .column, index: 1, count: 2, deleting: true)), to: inserted)
        XCTAssertEqual(try ExcelWorkbookDocument.load(from: deleted).sheets[0].frozenPanes, .init(rows: 5, columns: 0))
        let below = try apply(.structure(.init(axis: .row, index: 6, count: 1, deleting: false)), to: deleted)
        XCTAssertEqual(try ExcelWorkbookDocument.load(from: below).sheets[0].frozenPanes, .init(rows: 5, columns: 0))
    }

    func testInvalidBoundsAndProtectedWindowsAreRejected() throws {
        let blank = try ExcelWorkbookDocument.blankWorkbookData()
        for panes in [ExcelFrozenPanes(rows: -1, columns: 1), .init(rows: 2000, columns: 1), .init(rows: 1, columns: 200)] {
            XCTAssertThrowsError(try apply(.freezePanes(panes), to: blank))
        }
        var book = try ExcelWorkbookDocument.load(from: blank); book.protection.lockWindows = true
        XCTAssertThrowsError(try ExcelAdvancedWorkbookEditing.applying(.freezePanes(.init(rows: 1, columns: 0)), to: blank, workbook: book, sheetIndex: 0))
    }

    func testEveryPaneMapsTapsToTheSameDocumentAtEveryZoom() {
        for scale: CGFloat in [0.5, 1, 2, 3] {
            let layout = ExcelFrozenViewport(documentSize: CGSize(width: 4000, height: 9000), viewportSize: CGSize(width: 800, height: 600), frozenSize: CGSize(width: 100, height: 60), scale: scale, offset: CGPoint(x: 500, y: 900))
            let corner = CGPoint(x: 25 * scale, y: 20 * scale)
            XCTAssertEqual(layout.documentPoint(at: corner), CGPoint(x: 25, y: 20))
            let row = CGPoint(x: layout.insets.width + 40, y: 20 * scale)
            XCTAssertEqual(layout.documentPoint(at: row), CGPoint(x: (row.x + 500) / scale, y: 20))
            let column = CGPoint(x: 25 * scale, y: layout.insets.height + 40)
            XCTAssertEqual(layout.documentPoint(at: column), CGPoint(x: 25, y: (column.y + 900) / scale))
            let body = CGPoint(x: layout.insets.width + 40, y: layout.insets.height + 40)
            XCTAssertEqual(layout.documentPoint(at: body), CGPoint(x: (body.x + 500) / scale, y: (body.y + 900) / scale))
            for part in ExcelFrozenViewport.Part.allCases {
                let frame = layout.frame(for: part), visible = layout.visibleRect(for: part)
                XCTAssertEqual(frame.width, visible.width * scale, accuracy: 0.001)
                XCTAssertEqual(frame.height, visible.height * scale, accuracy: 0.001)
                XCTAssertTrue(layout.domain(for: part).contains(visible))
            }
        }
    }

    func testOversizedFrozenRegionLeavesAScrollableBodyAfterResize() {
        for size in [CGSize(width: 800, height: 600), CGSize(width: 400, height: 300), CGSize(width: 80, height: 60)] {
            let initial = ExcelFrozenViewport(documentSize: CGSize(width: 4000, height: 9000), viewportSize: size, frozenSize: CGSize(width: 1000, height: 1500), scale: 2, offset: .zero)
            let layout = ExcelFrozenViewport(documentSize: initial.documentSize, viewportSize: size, frozenSize: initial.frozenSize, scale: 2, offset: initial.minimumOffset)
            XCTAssertGreaterThan(layout.bodyRect.width, 0); XCTAssertGreaterThan(layout.bodyRect.height, 0)
            XCTAssertEqual(layout.bodyRect.minX, 1000, accuracy: 0.001)
            XCTAssertEqual(layout.bodyRect.minY, 1500, accuracy: 0.001)
            XCTAssertEqual(layout.documentPoint(at: CGPoint(x: layout.insets.width, y: layout.insets.height)), CGPoint(x: 1000, y: 1500))
        }
    }

    func testRevealDoesNotHideTargetsBehindFrozenRowsAndColumns() {
        let layout = ExcelFrozenViewport(documentSize: CGSize(width: 4000, height: 9000), viewportSize: CGSize(width: 800, height: 600), frozenSize: CGSize(width: 100, height: 60), scale: 2, offset: CGPoint(x: 500, y: 900))
        XCTAssertEqual(layout.revealing(CGRect(x: 100, y: 60, width: 30, height: 20)), .zero)
        XCTAssertEqual(layout.revealing(CGRect(x: 0, y: 0, width: 30, height: 20)), layout.offset)
        let distant = layout.revealing(CGRect(x: 1000, y: 3000, width: 30, height: 20))
        XCTAssertEqual(distant, CGPoint(x: 1260, y: 5440))
        let fixedColumn = layout.revealing(CGRect(x: 20, y: 3000, width: 30, height: 20))
        XCTAssertEqual(fixedColumn.x, 500); XCTAssertEqual(fixedColumn.y, 5440)
    }

    func testMergedGeometryIncludesFrozenPrefixAndLaterColumnWindow() {
        let rect = ExcelMergedCellGeometry.rect(for: ExcelCellRange("A1:AP2")!, columns: [1, 2, 41, 42], rows: [(1, 42, 30), (2, 72, 30)], rowHeaderWidth: 54, columnWidth: { _ in 80 })
        XCTAssertEqual(rect, CGRect(x: 54, y: 42, width: 320, height: 60))
    }
}
