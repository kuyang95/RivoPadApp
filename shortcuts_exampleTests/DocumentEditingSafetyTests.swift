import RivoDocumentEngine
import Foundation
import XCTest
@testable import shortcuts_example

final class DocumentEditingSafetyTests: XCTestCase, @unchecked Sendable {
    func testCoordinatedSaveRejectsExternalChangesWithoutOverwriting() throws {
        let url = temporaryURL("txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("original".utf8)
        let local = Data("local".utf8)
        let external = Data("external".utf8)
        try original.write(to: url)
        try CoordinatedDocumentFileAccess.replaceContents(at: url, with: local, expectedContents: original)
        XCTAssertEqual(try Data(contentsOf: url), local)
        try external.write(to: url)
        XCTAssertThrowsError(try CoordinatedDocumentFileAccess.replaceContents(
            at: url, with: original, expectedContents: local
        )) { error in
            guard case DocumentFileAccessError.documentChanged = error else {
                return XCTFail("Expected a document conflict, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: url), external)
    }

    @MainActor
    func testExcelSaveConflictKeepsPendingEditsAndUndo() async throws {
        let url = temporaryURL("xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        try ExcelWorkbookDocument.blankWorkbookData().write(to: url)
        let model = ExcelWorkbookViewModel(fileURL: url)
        await model.load()
        model.selectCell(ExcelCellAddress(row: 1, column: 1))
        model.updateEditorText("내 수정")
        let external = try ExcelWorkbookDocument.blankWorkbookData(sheetName: "외부 변경")
        try external.write(to: url)
        await model.save()
        XCTAssertNotNil(model.errorDescription)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertTrue(model.canUndo)
        XCTAssertEqual(model.selectedCell?.displayValue, "내 수정")
        XCTAssertEqual(try Data(contentsOf: url), external)
    }

    @MainActor
    func testHWPXSaveConflictKeepsPendingEditsAndUndo() async throws {
        let url = temporaryURL("hwpx")
        defer { try? FileManager.default.removeItem(at: url) }
        try LegacyHWPXConverter.convert(text: "원문").write(to: url)
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        model.editorText = "내 수정"
        model.commitEditorChange()
        let external = try LegacyHWPXConverter.convert(text: "외부 변경")
        try external.write(to: url)
        await model.save()
        XCTAssertNotNil(model.errorDescription)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertTrue(model.canUndo)
        XCTAssertEqual(model.blocks.first?.text, "내 수정")
        XCTAssertEqual(try Data(contentsOf: url), external)
        let copy = try await model.exportData()
        model.markExported()
        XCTAssertEqual(try HWPXDocumentPackage.load(from: copy).blocks.first?.text, "내 수정")
        XCTAssertTrue(model.hasUnsavedChanges, "Exporting a copy must not mark the original as saved")
        XCTAssertEqual(try Data(contentsOf: url), external)
    }

    @MainActor
    func testExcelRejectsMutationsWhileSaveIsInProgress() async throws {
        let url = temporaryURL("xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        try ExcelWorkbookDocument.blankWorkbookData().write(to: url)
        let gate = SaveGate()
        defer { gate.release.signal() }
        let model = ExcelWorkbookViewModel(fileURL: url, writeContents: gate.write)
        await model.load()
        model.selectCell(ExcelCellAddress(row: 1, column: 1))
        model.updateEditorText("저장할 값")
        let saving = Task { await model.save() }
        await fulfillment(of: [gate.started], timeout: 5)
        XCTAssertTrue(model.isSaving)
        XCTAssertFalse(model.canEditSelectedSheet)
        model.updateEditorText("저장 중 입력")
        model.undo()
        model.clearSelectedCell()
        XCTAssertFalse(model.applyDropdown(values: ["가", "나"], allowsBlank: true, toCurrentColumn: false))
        XCTAssertEqual(model.selectedCell?.displayValue, "저장할 값")
        gate.release.signal()
        await saving.value
        XCTAssertNil(model.errorDescription)
        XCTAssertFalse(model.isSaving)
        XCTAssertFalse(model.hasUnsavedChanges)
        let saved = try ExcelWorkbookDocument.load(from: Data(contentsOf: url))
        XCTAssertEqual(saved.sheets.first?.cells[ExcelCellAddress(row: 1, column: 1)]?.displayValue, "저장할 값")
        model.updateEditorText("다음 수정")
        XCTAssertTrue(model.hasUnsavedChanges)
    }

    @MainActor
    func testHWPXRejectsMutationsWhileSaveIsInProgress() async throws {
        let url = temporaryURL("hwpx")
        defer { try? FileManager.default.removeItem(at: url) }
        try LegacyHWPXConverter.convert(text: "원문").write(to: url)
        let gate = SaveGate()
        defer { gate.release.signal() }
        let model = HWPDocumentViewModel(fileURL: url, writeContents: gate.write)
        await model.load()
        model.editorText = "저장할 문단"
        model.commitEditorChange()
        let saving = Task { await model.save() }
        await fulfillment(of: [gate.started], timeout: 5)
        XCTAssertTrue(model.isSaving)
        XCTAssertFalse(model.canEditSelectedBlock)
        model.undo()
        model.redo()
        XCTAssertEqual(model.blocks.first?.text, "저장할 문단")
        gate.release.signal()
        await saving.value
        XCTAssertNil(model.errorDescription)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertTrue(model.canEditSelectedBlock)
        XCTAssertEqual(try HWPXDocumentPackage.load(from: Data(contentsOf: url)).blocks.first?.text, "저장할 문단")
    }

    @MainActor
    func testProtectedExcelSheetRejectsDirectEdits() async throws {
        let source = try ExcelWorkbookDocument.blankWorkbookData()
        let reader = try ExcelArchiveReader(data: source)
        let sheetPath = "xl/worksheets/sheet1.xml"
        let xml = String(decoding: try reader.data(at: sheetPath), as: UTF8.self)
            .replacingOccurrences(of: "</worksheet>", with: "<sheetProtection sheet=\"1\"/></worksheet>")
        let protected = try reader.repack(replacing: [sheetPath: Data(xml.utf8)])
        let url = temporaryURL("xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        try protected.write(to: url)
        let model = ExcelWorkbookViewModel(fileURL: url)
        await model.load()
        model.selectCell(ExcelCellAddress(row: 1, column: 1))
        XCTAssertFalse(model.canEditSelectedSheet)
        model.updateEditorText("금지된 수정")
        model.applyNumberFormat(.integer, toCurrentColumn: false)
        XCTAssertFalse(model.applyDropdown(values: ["가", "나"], allowsBlank: true, toCurrentColumn: false))
        XCTAssertFalse(model.addSheetShape(name: "보호", text: "금지된 개체", kind: .textBox))
        XCTAssertTrue(model.selectedSheet?.cells.isEmpty == true)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertFalse(model.canUndo)
        let exported = try await model.exportData()
        XCTAssertEqual(exported, protected)
    }

    private func temporaryURL(_ extensionName: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(extensionName)
    }
}

private final class SaveGate: @unchecked Sendable {
    let started = XCTestExpectation(description: "writer reached the save boundary")
    let release = DispatchSemaphore(value: 0)

    func write(_ url: URL, _ data: Data, _ expected: Data) throws {
        started.fulfill()
        guard release.wait(timeout: .now() + 10) == .success else {
            throw CocoaError(.fileWriteUnknown)
        }
        try CoordinatedDocumentFileAccess.replaceContents(at: url, with: data, expectedContents: expected)
    }
}
