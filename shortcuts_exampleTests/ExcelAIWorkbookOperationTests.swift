import RivoDocumentEngine
import Foundation
import XCTest
@testable import shortcuts_example

final class ExcelAIWorkbookOperationTests: XCTestCase {
    private func snapshot(_ transform: (inout ExcelWorkbook) -> Void = { _ in }) throws -> ExcelAIWorkbookSnapshot {
        var book = try ExcelWorkbookDocument.load(from: ExcelWorkbookDocument.blankWorkbookData())
        transform(&book)
        return try XCTUnwrap(ExcelAISnapshotBuilder.make(workbookName: "Test", workbook: book, selectedSheetIndex: 0, selectedAddress: .init(row: 1, column: 1), selectedRange: ExcelCellRange("A1:D1")))
    }
    private func validate(_ operations: [ExcelAIWorkbookOperation], _ snapshot: ExcelAIWorkbookSnapshot) throws -> ExcelAIValidatedPlan {
        let validated = try ExcelAICommandValidator.validate(.init(intent: .edit, assistantMessage: "요청", edits: [], appendedRows: [], workbookOperations: operations), snapshot: snapshot)
        return try XCTUnwrap(validated)
    }
    func testLegacyResponseStillDecodesWithoutOperations() throws {
        let json = #"{"intent":"answer","assistantMessage":"안녕","edits":[],"appendedRows":[],"actions":[],"createdTables":[]}"#
        XCTAssertTrue(try JSONDecoder().decode(ExcelAICommandPlan.self, from: Data(json.utf8)).workbookOperations.isEmpty)
    }
    func testSelectionAndCurrentSheetResolveForBatch() throws {
        let state = try snapshot()
        let plan = try validate([.init(type: .duplicateSheet, name: "9월"), .init(type: .mergeCells, sheetID: "$current", range: "$selection", center: true), .init(type: .freezePanes, sheetID: "$current", rows: 1, columns: 0)], state)
        XCTAssertEqual(plan.workbookOperations[0].sheetID, state.sheetPartPath)
        XCTAssertEqual(plan.workbookOperations[1].sheetID, "$current")
        XCTAssertEqual(plan.workbookOperations[1].range, "A1:D1")
    }
    func testInvalidIDsAndIncompleteOperationsAreRejected() throws {
        let state = try snapshot()
        for op in [ExcelAIWorkbookOperation(type: .deleteSheet, sheetID: "invented"), .init(type: .freezePanes, rows: 1), .init(type: .resizeTracks, axis: "row", index: 1, count: 1, size: -1), .init(type: .formatCells, range: "A1", format: .init()), .init(type: .sortRange, range: "A1:B4", column: 3, ascending: true, header: true)] {
            XCTAssertThrowsError(try validate([op], state))
        }
    }
    func testOperationAndDestinationLimits() throws {
        let state = try snapshot()
        XCTAssertThrowsError(try validate(Array(repeating: .init(type: .freezePanes, rows: 1, columns: 0), count: 21), state))
        XCTAssertThrowsError(try validate([.init(type: .copyRange, range: "A1:C3", destination: "GR2000")], state))
        XCTAssertThrowsError(try validate([.init(type: .clearRange, range: "A1:GR2000")], state))
    }
    func testModelCannotAuthorizeDestructiveMerge() throws {
        XCTAssertThrowsError(try validate([.init(type: .mergeCells, range: "A1:D1", discardOtherValues: true)], snapshot()))
    }
    func testReadOnlyResponsesCannotHideOperations() throws {
        XCTAssertThrowsError(try ExcelAICommandValidator.validate(.init(intent: .answer, assistantMessage: "완료", edits: [], appendedRows: [], workbookOperations: [.init(type: .deleteSheet)]), snapshot: snapshot()))
    }
    func testContextDoesNotEncodeFullLocalWorkbook() throws {
        let data = try JSONEncoder().encode(snapshot())
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(root["localWorkbook"]); XCTAssertNil(root["localQuerySheet"])
        XCTAssertNotNil((root["workbookContext"] as? [String: Any])?["sheets"])
    }
    func testRevisionChangesForNonCellEditsAndIsStableForSameState() throws {
        let state = try snapshot(), original = try XCTUnwrap(state.localWorkbook)
        func revision(_ book: ExcelWorkbook, _ range: String = "A1:D1", _ id: String? = nil) -> String {
            ExcelAIWorkbookContext.revision(workbook: book, selectedSheetIndex: 0, selectedRange: ExcelCellRange(range), selectedDrawingID: id)
        }
        XCTAssertEqual(revision(original), revision(original))
        var changed = original; changed.styles[0].fontSize = 30
        XCTAssertNotEqual(revision(original), revision(changed))
        changed = original; changed.sheets[0].frozenPanes = .init(rows: 1, columns: 0)
        XCTAssertNotEqual(revision(original), revision(changed))
        changed = original; changed.sheets[0].hiddenRows.insert(2)
        XCTAssertNotEqual(revision(original), revision(changed))
        XCTAssertNotEqual(revision(original), revision(original, "B2"))
        XCTAssertNotEqual(revision(original), revision(original, "A1:D1", "chart"))
    }
    func testGeometryMovesAndScalesWithoutChangingUnrequestedAxis() throws {
        let sheet = try XCTUnwrap(snapshot().localWorkbook?.sheets[0])
        let anchor = ExcelDrawingAnchor(start: .init(row: 2, column: 2), end: .init(row: 6, column: 5))
        let grid = ExcelAIDrawingGeometry.grid(sheet: sheet), old = try XCTUnwrap(grid.rect(for: anchor))
        let moved = try ExcelAIDrawingGeometry.applying(.init(type: .moveDrawing, columnOffset: 1), anchor: anchor, sheet: sheet)
        let movedRect = try XCTUnwrap(grid.rect(for: moved))
        XCTAssertEqual(moved.start.column, 3); XCTAssertEqual(movedRect.width, old.width, accuracy: 0.01)
        let bigger = try ExcelAIDrawingGeometry.applying(.init(type: .resizeDrawing, widthFactor: 1.2), anchor: moved, sheet: sheet)
        let rect = try XCTUnwrap(grid.rect(for: bigger))
        XCTAssertEqual(rect.width, old.width * 1.2, accuracy: 0.01)
        XCTAssertEqual(rect.height, old.height, accuracy: 0.01)
        XCTAssertEqual(rect.minX, movedRect.minX, accuracy: 0.01)
        XCTAssertThrowsError(try ExcelAIDrawingGeometry.applying(.init(type: .moveDrawing, columnOffset: -5), anchor: anchor, sheet: sheet))
    }
    func testWindowedOrTruncatedWorkbookDisablesOperations() throws {
        let state = try snapshot { $0.sheets[0].isWindowed = true }
        XCTAssertNil(state.localWorkbook)
        XCTAssertThrowsError(try validate([.init(type: .freezePanes, rows: 1, columns: 0)], state))
    }
}
