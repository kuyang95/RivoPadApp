import SwiftUI
import UIKit
import XCTest
@testable import shortcuts_example

@MainActor
final class ExcelRowAutosaveTests: XCTestCase {
    private typealias Writer = @Sendable (URL, Data, Data) throws -> Void

    private func fixture(
        delay: Duration = .seconds(60),
        workbookAutosaveDelay: Duration = .seconds(60),
        writer: @escaping Writer = {
            try CoordinatedDocumentFileAccess.replaceContents(at: $0, with: $1, expectedContents: $2)
        }
    ) async throws -> (URL, ExcelWorkbookViewModel, ExcelRowEditingSession) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RowAutosave-\(UUID().uuidString).xlsx")
        let source = try ExcelWorkbookDocument.blankWorkbookData()
        let workbook = try ExcelWorkbookDocument.load(from: source)
        let sheet = try XCTUnwrap(workbook.sheets.first)
        let values: [ExcelCellAddress: ExcelCellInput] = [
            .init(row: 1, column: 1): .text("상품"),
            .init(row: 1, column: 2): .text("수량"),
            .init(row: 1, column: 3): .text("계산 금액"),
            .init(row: 1, column: 4): .text("메모"),
            .init(row: 2, column: 1): .text("기존 상품"),
            .init(row: 2, column: 2): .number("2"),
            .init(row: 2, column: 3): .formula("B2*2"),
            .init(row: 2, column: 4): .text("유지할 메모"),
        ]
        let data = try ExcelWorkbookDocument.applying(
            [.init(partPath: sheet.partPath, cells: values.mapValues {
                ExcelCellEdit(input: $0, styleIndex: nil)
            })], to: source, workbook: workbook
        )
        try data.write(to: url)
        let model = ExcelWorkbookViewModel(
            fileURL: url,
            autosaveDelay: workbookAutosaveDelay,
            writeContents: writer
        )
        await model.load()
        let columns = ["상품", "수량", "계산 금액", "메모"].enumerated().map {
            ExcelAccessibleColumn(column: $0.offset + 1, title: $0.element)
        }
        let session = ExcelRowEditingSession(
            row: 2, initialFields: model.rowFields(for: 2, columns: columns),
            viewModel: model, debounceDelay: delay
        )
        return (url, model, session)
    }

    private func cell(_ column: Int, at url: URL) throws -> ExcelCell? {
        try ExcelWorkbookDocument.load(from: Data(contentsOf: url))
            .sheets.first?.cell(at: .init(row: 2, column: column))
    }

    func testTypingAutomaticallySavesAndPreservesUnchangedFormula() async throws {
        let wrote = expectation(description: "Saved without an Apply or Save button")
        let (url, model, session) = try await fixture(delay: .milliseconds(30)) { url, data, expected in
            try CoordinatedDocumentFileAccess.replaceContents(at: url, with: data, expectedContents: expected)
            wrote.fulfill()
        }
        defer { try? FileManager.default.removeItem(at: url) }
        session.updateValue("25", column: 2)
        await fulfillment(of: [wrote], timeout: 10)
        let succeeded = await session.flush()
        XCTAssertTrue(succeeded)
        XCTAssertEqual(try cell(2, at: url)?.rawValue, "25")
        XCTAssertEqual(try cell(3, at: url)?.formula, "B2*2")
        XCTAssertEqual(try cell(3, at: url)?.rawValue, "50")
        XCTAssertEqual(try cell(4, at: url)?.displayValue, "유지할 메모")
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertFalse(session.hasPendingChanges)
    }

    func testGridTypingCoalescesAndAutosavesWithoutBlockingTheWorkbook() async throws {
        let started = expectation(description: "Workbook autosave started")
        let gate = DispatchSemaphore(value: 0)
        let probe = WriterProbe()
        let (url, model, _) = try await fixture(
            workbookAutosaveDelay: .milliseconds(30)
        ) { url, data, expected in
            _ = probe.nextWrite()
            started.fulfill()
            guard gate.wait(timeout: .now() + 10) == .success else {
                throw ProbeError.timeout
            }
            try CoordinatedDocumentFileAccess.replaceContents(
                at: url, with: data, expectedContents: expected
            )
        }
        defer {
            gate.signal()
            try? FileManager.default.removeItem(at: url)
        }

        model.selectCell(.init(row: 2, column: 1))
        model.updateEditorText("첫 입력")
        model.updateEditorText("마지막 입력")
        await fulfillment(of: [started], timeout: 10)

        XCTAssertTrue(model.isAutosaving)
        XCTAssertFalse(model.isSaving)
        XCTAssertTrue(model.canEditSelectedSheet)
        gate.signal()
        let saved = await model.flushAutosave()

        XCTAssertTrue(saved)
        XCTAssertEqual(probe.count, 1)
        XCTAssertEqual(try cell(1, at: url)?.displayValue, "마지막 입력")
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testWorkbookFlushSavesImmediatelyBeforeTheDebounceExpires() async throws {
        let probe = WriterProbe()
        let (url, model, _) = try await fixture { url, data, expected in
            _ = probe.nextWrite()
            try CoordinatedDocumentFileAccess.replaceContents(
                at: url, with: data, expectedContents: expected
            )
        }
        defer { try? FileManager.default.removeItem(at: url) }

        model.selectCell(.init(row: 2, column: 2))
        model.updateEditorText("31")
        let saved = await model.flushAutosave()

        XCTAssertTrue(saved)
        XCTAssertEqual(probe.count, 1)
        XCTAssertEqual(try cell(2, at: url)?.rawValue, "31")
        XCTAssertEqual(try cell(3, at: url)?.rawValue, "62")
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testEditingDuringWorkbookAutosaveSchedulesTheLatestSnapshot() async throws {
        let firstStarted = expectation(description: "First autosave started")
        let secondFinished = expectation(description: "Latest snapshot saved")
        let gate = DispatchSemaphore(value: 0)
        let probe = WriterProbe()
        let (url, model, _) = try await fixture(
            workbookAutosaveDelay: .milliseconds(30)
        ) { url, data, expected in
            let count = probe.nextWrite()
            if count == 1 {
                firstStarted.fulfill()
                guard gate.wait(timeout: .now() + 10) == .success else {
                    throw ProbeError.timeout
                }
            }
            try CoordinatedDocumentFileAccess.replaceContents(
                at: url, with: data, expectedContents: expected
            )
            if count == 2 { secondFinished.fulfill() }
        }
        defer {
            gate.signal()
            try? FileManager.default.removeItem(at: url)
        }

        model.selectCell(.init(row: 2, column: 1))
        model.updateEditorText("첫 스냅샷")
        await fulfillment(of: [firstStarted], timeout: 10)
        model.updateEditorText("최종 스냅샷")
        model.selectCell(.init(row: 2, column: 2))
        model.updateEditorText("12")
        gate.signal()
        await fulfillment(of: [secondFinished], timeout: 10)
        let saved = await model.flushAutosave()

        XCTAssertTrue(saved)
        XCTAssertEqual(probe.count, 2)
        XCTAssertEqual(try cell(1, at: url)?.displayValue, "최종 스냅샷")
        XCTAssertEqual(try cell(2, at: url)?.rawValue, "12")
        XCTAssertEqual(try cell(3, at: url)?.rawValue, "24")
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testNewTypingDuringAWriteIsSavedAfterTheRunningSnapshot() async throws {
        let started = expectation(description: "First write started")
        let gate = DispatchSemaphore(value: 0)
        let probe = WriterProbe()
        let (url, model, session) = try await fixture { url, data, expected in
            if probe.nextWrite() == 1 {
                started.fulfill()
                guard gate.wait(timeout: .now() + 10) == .success else { throw ProbeError.timeout }
            }
            try CoordinatedDocumentFileAccess.replaceContents(at: url, with: data, expectedContents: expected)
        }
        defer { gate.signal(); try? FileManager.default.removeItem(at: url) }
        session.updateValue("첫 입력", column: 1)
        let firstSave = Task { await session.flush() }
        await fulfillment(of: [started], timeout: 10)
        session.updateValue("마지막 입력", column: 1)
        session.updateValue("7", column: 2)
        gate.signal()
        let succeeded = await firstSave.value
        XCTAssertTrue(succeeded)
        XCTAssertEqual(try cell(1, at: url)?.displayValue, "마지막 입력")
        XCTAssertEqual(try cell(2, at: url)?.rawValue, "7")
        XCTAssertEqual(try cell(3, at: url)?.rawValue, "14")
        XCTAssertEqual(probe.count, 2)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testClosingFlushesImmediatelyAndBlankValuesPersist() async throws {
        let (url, model, session) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        session.updateValue("", column: 4)
        // The same flush is awaited by Close, even though debounce is 60 seconds.
        let succeeded = await session.flush()
        XCTAssertTrue(succeeded)
        XCTAssertTrue(try cell(4, at: url)?.displayValue.isEmpty ?? true)
        XCTAssertFalse(model.hasUnsavedChanges)
        try await attachDialogPreview(model: model)
    }

    func testFailureRetainsDraftAndRetryCanRestoreTheOriginalValue() async throws {
        let probe = WriterProbe()
        let (url, model, session) = try await fixture { url, data, expected in
            if probe.nextWrite() == 1 { throw ProbeError.writeFailed }
            try CoordinatedDocumentFileAccess.replaceContents(at: url, with: data, expectedContents: expected)
        }
        defer { try? FileManager.default.removeItem(at: url) }
        session.updateValue("새 상품", column: 1)
        let failed = await session.flush()
        XCTAssertFalse(failed)
        XCTAssertNotNil(session.errorMessage)
        XCTAssertTrue(session.canKeepChangesInDocument)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertEqual(session.fields.first?.value, "새 상품")
        XCTAssertEqual(try cell(1, at: url)?.displayValue, "기존 상품")
        session.updateValue("기존 상품", column: 1)
        let retried = await session.flush()
        XCTAssertTrue(retried)
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(try cell(1, at: url)?.displayValue, "기존 상품")
        XCTAssertFalse(session.hasPendingChanges)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testUndoRedoAndManualSaveRemainCorrectAfterAutosave() async throws {
        let (url, model, session) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        session.updateValue("9", column: 2)
        let succeeded = await session.flush()
        XCTAssertTrue(succeeded)
        XCTAssertTrue(model.canUndo)
        XCTAssertFalse(model.hasUnsavedChanges)
        model.undo()
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertEqual(model.selectedSheet?.cell(at: .init(row: 2, column: 2))?.rawValue, "2")
        await model.save(preservingHistory: true)
        XCTAssertEqual(try cell(2, at: url)?.rawValue, "2")
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertTrue(model.canRedo)
        model.redo()
        XCTAssertTrue(model.hasUnsavedChanges)
        await model.save()
        XCTAssertEqual(try cell(2, at: url)?.rawValue, "9")
        XCTAssertEqual(try cell(3, at: url)?.rawValue, "18")
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertFalse(model.canUndo)
    }

    func testAutosaveDoesNotOverwriteAnExternalFileChange() async throws {
        let (url, model, session) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        session.updateValue("3", column: 2)
        let firstSave = await session.flush()
        XCTAssertTrue(firstSave)
        let external = try ExcelWorkbookDocument.blankWorkbookData()
        try external.write(to: url)
        session.updateValue("4", column: 2)
        let conflicted = await session.flush()
        XCTAssertFalse(conflicted)
        XCTAssertEqual(try Data(contentsOf: url), external)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertNotNil(session.errorMessage)
    }

    private func attachDialogPreview(model: ExcelWorkbookViewModel) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1_100, height: 850)
        let columns = ["상품", "수량", "계산 금액", "메모"].enumerated().map {
            ExcelAccessibleColumn(column: $0.offset + 1, title: $0.element)
        }
        let view = ExcelEditRowView(row: 2, initialFields: model.rowFields(for: 2, columns: columns), viewModel: model)
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(200))
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Large-centered-row-editor"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private enum ProbeError: Error { case timeout, writeFailed }

private final class WriterProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var writes = 0
    var count: Int { lock.withLock { writes } }
    func nextWrite() -> Int { lock.withLock { writes += 1; return writes } }
}
