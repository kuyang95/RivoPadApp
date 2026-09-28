import UIKit
import XCTest
@testable import shortcuts_example

@MainActor
final class ExcelAIWorkbookTransactionTests: XCTestCase {
    private func fixture() async throws -> (URL, ExcelWorkbookViewModel) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AI-batch-\(UUID().uuidString).xlsx")
        let blank = try ExcelWorkbookDocument.blankWorkbookData(), book = try ExcelWorkbookDocument.load(from: blank)
        let inputs: [ExcelCellAddress: ExcelCellInput] = [
            ExcelCellAddress("A1")!: .text("제품"), ExcelCellAddress("B1")!: .text("수량"),
            ExcelCellAddress("A2")!: .text("Paseo"), ExcelCellAddress("B2")!: .number("888"),
            ExcelCellAddress("A3")!: .text("VTT"), ExcelCellAddress("B3")!: .number("40"),
            ExcelCellAddress("C2")!: .formula("B2*2")]
        let data = try ExcelWorkbookDocument.applying([.init(partPath: book.sheets[0].partPath, cells: inputs.mapValues { .init(input: $0, styleIndex: nil) })], to: blank, workbook: book)
        try data.write(to: url)
        let model = ExcelWorkbookViewModel(fileURL: url)
        await model.load()
        _ = try XCTUnwrap(model.workbook)
        return (url, model)
    }
    private func plan(_ operations: [ExcelAIWorkbookOperation], _ model: ExcelWorkbookViewModel, edits: [ExcelAICommandPlan.Edit] = []) throws -> ExcelAIValidatedPlan {
        try XCTUnwrap(ExcelAICommandValidator.validate(.init(intent: .edit, assistantMessage: "MODEL CLAIM SHOULD NOT APPEAR", edits: edits, appendedRows: [], workbookOperations: operations), snapshot: XCTUnwrap(model.makeAISnapshot()), userRequest: "B2를 99로 바꿔줘"))
    }
    func testDuplicateRenameFreezeCommitsOnceAndExports() async throws {
        let (url, model) = try await fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let original = try Data(contentsOf: url)
        let result = try await model.applyAIWorkbookPlan(plan([.init(type: .duplicateSheet), .init(type: .renameSheet, sheetID: "$current", name: "9월"), .init(type: .freezePanes, sheetID: "$current", rows: 1, columns: 1)], model))
        XCTAssertEqual(model.workbook?.sheets.count, 2); XCTAssertEqual(model.selectedSheet?.name, "9월")
        XCTAssertEqual(model.selectedSheet?.frozenPanes.rows, 1)
        XCTAssertEqual(try Data(contentsOf: url), original, "Chat application must not overwrite disk before save")
        XCTAssertFalse(result.message.contains("MODEL CLAIM")); XCTAssertNil(result.references)
        let exported = try await model.exportData()
        XCTAssertEqual(try ExcelWorkbookDocument.load(from: exported).sheets.last?.frozenPanes.columns, 1)
        model.undo(); XCTAssertEqual(model.workbook?.sheets.count, 1); XCTAssertFalse(model.canUndo)
        model.redo(); XCTAssertEqual(model.selectedSheet?.name, "9월"); XCTAssertEqual(model.selectedSheet?.frozenPanes.rows, 1)
    }
    func testEditingDuplicateAfterCreationKeepsOriginalValues() async throws {
        let (url, model) = try await fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let result = try await model.applyAIWorkbookPlan(plan([.init(type: .duplicateSheet, name: "복제"), .init(type: .setCellValue, sheetID: "$current", range: "B2", value: "99")], model))
        XCTAssertEqual(model.workbook?.sheets[0].cells[ExcelCellAddress("B2")!]?.rawValue, "888")
        XCTAssertEqual(model.workbook?.sheets[1].cells[ExcelCellAddress("B2")!]?.rawValue, "99")
        XCTAssertEqual(result.references?.sheetPartPath, model.selectedSheet?.partPath)
        XCTAssertEqual(result.references?.addresses.map(\.reference), ["B2"])
        model.undo(); XCTAssertEqual(model.workbook?.sheets.count, 1); XCTAssertFalse(model.canUndo)
    }
    func testLaterFailureRollsBackEarlierOperationAndHistory() async throws {
        let (url, model) = try await fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let bytes = try await model.exportData()
        do {
            _ = try await model.applyAIWorkbookPlan(plan([.init(type: .freezePanes, rows: 1, columns: 0), .init(type: .mergeCells, range: "A1:B1", center: true)], model))
            XCTFail("Merging two occupied cells must fail without partial freezing")
        } catch {}
        XCTAssertEqual(model.selectedSheet?.frozenPanes.rows, 0); XCTAssertTrue(model.selectedSheet?.mergedRanges.isEmpty == true)
        XCTAssertFalse(model.canUndo)
        let after = try await model.exportData(); XCTAssertEqual(after, bytes)
    }
    func testMixedLegacyValueEditAndFreezeUndoTogether() async throws {
        let (url, model) = try await fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let result = try await model.applyAIWorkbookPlan(plan([.init(type: .freezePanes, rows: 1, columns: 0)], model, edits: [.init(row: 2, column: 2, newValue: "99")]))
        XCTAssertEqual(result.references?.addresses.map(\.reference), ["B2"])
        XCTAssertEqual(model.selectedSheet?.cells[ExcelCellAddress("B2")!]?.rawValue, "99")
        XCTAssertEqual(model.selectedSheet?.frozenPanes.rows, 1)
        model.undo()
        XCTAssertEqual(model.selectedSheet?.cells[ExcelCellAddress("B2")!]?.rawValue, "888")
        XCTAssertEqual(model.selectedSheet?.frozenPanes.rows, 0); XCTAssertFalse(model.canUndo)
    }
    func testSelectionChangeInvalidatesPendingPlan() async throws {
        let (url, model) = try await fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let pending = try plan([.init(type: .freezePanes, rows: 1, columns: 0)], model)
        model.selectCell(ExcelCellAddress("B2")!)
        do { _ = try await model.applyAIWorkbookPlan(pending); XCTFail("Stale selection must be refused") } catch {}
        XCTAssertFalse(model.canUndo); XCTAssertEqual(model.selectedSheet?.frozenPanes.rows, 0)
    }
    func testCopyAdjustsFormulaAndHighlightsActualDestinationWithoutClipboardWrite() async throws {
        let (url, model) = try await fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let changeCount = UIPasteboard.general.changeCount
        let result = try await model.applyAIWorkbookPlan(plan([.init(type: .copyRange, range: "B2:C2", destination: "B5")], model))
        XCTAssertEqual(model.selectedSheet?.cells[ExcelCellAddress("C5")!]?.formula, "B5*2")
        XCTAssertEqual(result.references?.addresses.map(\.reference), ["B5", "C5"])
        XCTAssertEqual(UIPasteboard.general.changeCount, changeCount)
        model.undo(); XCTAssertNil(model.selectedSheet?.cells[ExcelCellAddress("C5")!]); XCTAssertFalse(model.canUndo)
    }
    func testMergeAndFormatBlankRangeKeepsSingleUndo() async throws {
        let (url, model) = try await fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let result = try await model.applyAIWorkbookPlan(plan([.init(type: .mergeCells, range: "E1:H1", center: true), .init(type: .formatCells, range: "E1:H1", format: .init(bold: true))], model))
        XCTAssertTrue(model.selectedSheet?.mergedRanges.contains(ExcelCellRange("E1:H1")!) == true)
        XCTAssertEqual(result.references?.addresses.map(\.reference), ["E1"])
        model.undo(); XCTAssertTrue(model.selectedSheet?.mergedRanges.isEmpty == true); XCTAssertFalse(model.canUndo)
    }
    func testChartMoveAndResizeRetainDataAndRoundTrip() async throws {
        let (url, model) = try await fixture(); defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(model.addSheetChart(title: "매출", kind: .column, sourceReference: "A1:B3"))
        let chart = try XCTUnwrap(model.selectedSheetCharts.first)
        model.selectedDrawingID = chart.id
        let sheet = try XCTUnwrap(model.selectedSheet), grid = ExcelAIDrawingGeometry.grid(sheet: sheet)
        let original = try XCTUnwrap(grid.rect(for: chart.anchor))
        let result = try await model.applyAIWorkbookPlan(plan([.init(type: .moveDrawing, drawingID: "$selected", columnOffset: 1), .init(type: .resizeDrawing, drawingID: "$selected", widthFactor: 1.2, heightFactor: 1.2)], model))
        let moved = try XCTUnwrap(model.selectedSheetCharts.first)
        let actual = try XCTUnwrap(grid.rect(for: moved.anchor))
        XCTAssertEqual(actual.width, original.width * 1.2, accuracy: 0.02)
        XCTAssertEqual(moved.sourceRange, chart.sourceRange); XCTAssertEqual(moved.title, chart.title)
        XCTAssertNil(result.references)
        model.undo(); XCTAssertEqual(model.selectedSheetCharts.first?.anchor, chart.anchor)
        model.redo(); XCTAssertEqual(model.selectedSheetCharts.first?.anchor, moved.anchor)
    }
    func testFillCannotWriteHiddenInteriorOfMergedCell() async throws {
        let (url, model) = try await fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let merged = await model.performAdvancedEdit(.merge(ExcelCellRange("E1:F1")!, center: false))
        XCTAssertTrue(merged)
        let pending = try plan([.init(type: .freezePanes, rows: 1, columns: 0), .init(type: .fillRange, range: "E1:F1", across: true)], model)
        do { _ = try await model.applyAIWorkbookPlan(pending); XCTFail("Cannot fill a hidden merged interior") } catch {}
        XCTAssertEqual(model.selectedSheet?.frozenPanes.rows, 0)
        XCTAssertTrue(model.selectedSheet?.cells[ExcelCellAddress("F1")!]?.rawValue.isEmpty != false)
        model.undo(); XCTAssertTrue(model.selectedSheet?.mergedRanges.isEmpty == true); XCTAssertFalse(model.canUndo)
    }
    func testClearingAlreadyEmptyCellDoesNotAbortOtherValidOperation() async throws {
        let (url, model) = try await fixture(); defer { try? FileManager.default.removeItem(at: url) }
        _ = try await model.applyAIWorkbookPlan(plan([.init(type: .freezePanes, rows: 1, columns: 0), .init(type: .clearRange, range: "G9")], model))
        XCTAssertEqual(model.selectedSheet?.frozenPanes.rows, 1)
        model.undo(); XCTAssertEqual(model.selectedSheet?.frozenPanes.rows, 0); XCTAssertFalse(model.canUndo)
    }
    func testChatUsesAppliedResultAndDoesNotAppendSuccessOnFailure() async throws {
        let (url, model) = try await fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let chat = ExcelAIChatViewModel(), snapshot = try XCTUnwrap(model.makeAISnapshot())
        let command = ExcelAICommandPlan(intent: .edit, assistantMessage: "MODEL CLAIM", edits: [], appendedRows: [], workbookOperations: [.init(type: .freezePanes, rows: 1, columns: 0)])
        try await chat.handleOperations(command, snapshot: snapshot, userRequest: "첫 행 고정", applying: model.applyAIWorkbookPlan)
        XCTAssertEqual(chat.messages.count, 1); XCTAssertFalse(chat.messages[0].text.contains("MODEL CLAIM"))
        do { try await chat.handleOperations(command, snapshot: snapshot, userRequest: "첫 행 고정", applying: model.applyAIWorkbookPlan); XCTFail("Stale revision") } catch {}
        XCTAssertEqual(chat.messages.count, 1)
    }
}
