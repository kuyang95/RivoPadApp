import RivoDocumentEngine
import Foundation
import XCTest
@testable import shortcuts_example

/// The HWP editor's autosave (Android `HwpViewModel`): after an edit pause, one save at a time,
/// history kept, another app's change never overwritten, a converted HWP never written over.
@MainActor
final class HWPAutosaveTests: XCTestCase {
    private var cleanup: [URL] = []
    private var suites: [String] = []

    override func tearDown() async throws {
        for url in cleanup { try? FileManager.default.removeItem(at: url) }
        for suite in suites { UserDefaults().removePersistentDomain(forName: suite) }
        cleanup = []
        suites = []
        try await super.tearDown()
    }

    func testAutosaveWritesOncePauseAfterLastEdit() async throws {
        let (url, original) = try hwpx("원문")
        let model = HWPDocumentViewModel(fileURL: url, autosaveDelay: .seconds(1))
        await model.load()
        edit(model, "첫 입력")
        try await Task.sleep(for: .milliseconds(400))
        edit(model, "둘째 입력")
        try await Task.sleep(for: .milliseconds(400))
        // 0.8 s after the first edit but only 0.4 s after the last: nothing written yet.
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertEqual(model.saveState, .idle)
        try await waitUntil { !model.hasUnsavedChanges }
        XCTAssertNil(model.errorDescription)
        XCTAssertEqual(model.saveState, .saved)
        XCTAssertEqual(try savedText(url), "둘째 입력")
        XCTAssertTrue(model.canUndo)
        // The next edit makes the document changed again, and is saved after its own pause.
        edit(model, "셋째 입력")
        XCTAssertEqual(model.saveState, .idle)
        try await waitUntil { !model.hasUnsavedChanges }
        XCTAssertEqual(try savedText(url), "셋째 입력")
    }

    func testOneSaveAtATimeAndEditsDuringSaveAreSavedNext() async throws {
        let (url, _) = try hwpx("원문")
        let gate = CountingWriteGate()
        defer { gate.release.signal(); gate.release.signal() }
        let model = HWPDocumentViewModel(fileURL: url, autosaveDelay: .milliseconds(50), writeContents: gate.write)
        await model.load()
        edit(model, "첫 수정")
        try await waitUntil { gate.started == 1 }
        XCTAssertTrue(model.isAutosaving)
        XCTAssertFalse(model.isSaving)
        XCTAssertEqual(model.saveState, .saving)
        // Editing goes on during an autosave.
        XCTAssertTrue(model.canEditSelectedBlock)
        edit(model, "저장 중 수정")
        XCTAssertEqual(model.blocks.first?.text, "저장 중 수정")
        let leaving = Task { await model.flushAutosave() }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(gate.started, 1, "A second save must wait for the running one")
        gate.release.signal()
        try await waitUntil { gate.started == 2 }
        gate.release.signal()
        let written = await leaving.value
        XCTAssertTrue(written)
        XCTAssertEqual(gate.maxActive, 1)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertFalse(model.isAutosaving)
        XCTAssertEqual(try savedText(url), "저장 중 수정")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(gate.started, 2, "Nothing is left to write")
    }

    func testUndoHistoryStaysAcrossSaves() async throws {
        let (url, _) = try hwpx("원문")
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        edit(model, "저장할 수정")
        await model.save()
        XCTAssertNil(model.errorDescription)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertTrue(model.canUndo)
        XCTAssertEqual(model.status, AppLocalization.string("HWPX 문서에 저장했습니다."))
        XCTAssertEqual(try savedText(url), "저장할 수정")

        model.undo()
        XCTAssertEqual(model.blocks.first?.text, "원문")
        XCTAssertTrue(model.hasUnsavedChanges, "The file holds the undone edit")
        XCTAssertTrue(model.canRedo)
        let undone = await model.flushAutosave()
        XCTAssertTrue(undone)
        XCTAssertEqual(try savedText(url), "원문")

        model.redo()
        XCTAssertTrue(model.hasUnsavedChanges)
        let redone = await model.flushAutosave()
        XCTAssertTrue(redone)
        XCTAssertEqual(try savedText(url), "저장할 수정")
        XCTAssertTrue(model.canUndo)
        XCTAssertFalse(model.canRedo)
    }

    func testAnotherAppsChangeIsNeverOverwrittenAndStopsAutosave() async throws {
        let (url, _) = try hwpx("원문")
        let model = HWPDocumentViewModel(fileURL: url, autosaveDelay: .milliseconds(100))
        await model.load()
        let external = try LegacyHWPXConverter.convert(text: "외부 변경")
        try external.write(to: url)
        edit(model, "내 수정")
        try await waitUntil { model.saveFailure != nil }
        let changed = DocumentFileAccessError.documentChanged.localizedDescription
        XCTAssertEqual(model.saveFailure?.message, changed)
        XCTAssertEqual(model.status, changed)
        XCTAssertEqual(model.saveState, .idle)
        XCTAssertEqual(try Data(contentsOf: url), external)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertTrue(model.canUndo)
        XCTAssertEqual(model.blocks.first?.text, "내 수정")

        // No more autosaves; leaving asks; 이 문서에 저장 refuses the same way.
        edit(model, "다음 수정")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(try Data(contentsOf: url), external)
        let canLeave = await model.prepareToLeave()
        XCTAssertFalse(canLeave)
        await model.save()
        XCTAssertNotNil(model.errorDescription)
        XCTAssertEqual(try Data(contentsOf: url), external)
        XCTAssertTrue(model.hasUnsavedChanges)
    }

    func testConvertedHWPNeverWritesTheOriginalAndAutosavesToItsNewFile() async throws {
        let original = try fixture("hangul_design_application", "hwp")
        let url = temporaryURL("hwp")
        try original.write(to: url)
        let store = recentStore()
        let model = HWPDocumentViewModel(fileURL: url, autosaveDelay: .milliseconds(100), recentDocuments: store)
        await model.load()
        XCTAssertTrue(model.isLegacyDocument)
        await model.convertLegacyForEditing()
        XCTAssertTrue(model.requiresSaveAs)
        XCTAssertTrue(model.hasUnsavedChanges)
        edit(model, "변환 후 수정")

        // No file of its own yet: nothing is written, and leaving asks.
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(try Data(contentsOf: url), original)
        let flushed = await model.flushAutosave()
        XCTAssertFalse(flushed)
        let canLeave = await model.prepareToLeave()
        XCTAssertFalse(canLeave)
        await model.save()
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertTrue(model.hasUnsavedChanges)

        // 이 문서에 저장 exports the HWPX copy (the file exporter writes it), which becomes the document's file.
        let copyURL = temporaryURL("hwpx")
        try await model.exportData().write(to: copyURL)
        await model.adoptSavedCopy(at: copyURL)
        XCTAssertFalse(model.requiresSaveAs)
        XCTAssertEqual(model.fileURL, copyURL)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertNotNil(model.originalDocumentID)
        XCTAssertTrue(try HWPXDocumentPackage.load(from: Data(contentsOf: copyURL)).blocks.map(\.text).contains("변환 후 수정"))

        edit(model, "새 파일에 자동 저장")
        try await waitUntil { !model.hasUnsavedChanges }
        XCTAssertNil(model.errorDescription)
        XCTAssertTrue(try HWPXDocumentPackage.load(from: Data(contentsOf: copyURL)).blocks.map(\.text).contains("새 파일에 자동 저장"))
        XCTAssertEqual(try Data(contentsOf: url), original, "The original HWP is never written")
    }

    func testLeavingSavesPendingChangesAndAsksOnlyWhenTheyCannotBeWritten() async throws {
        let (url, _) = try hwpx("원문")
        let model = HWPDocumentViewModel(fileURL: url, autosaveDelay: .seconds(60))
        await model.load()
        let clean = await model.prepareToLeave()
        XCTAssertTrue(clean)

        // Typed in the editor panel and not yet applied: leaving applies and writes it.
        model.editorText = "나가기 전 입력"
        XCTAssertTrue(model.hasPendingEditorChange)
        let saved = await model.prepareToLeave()
        XCTAssertTrue(saved)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertEqual(try savedText(url), "나가기 전 입력")

        let external = try LegacyHWPXConverter.convert(text: "외부 변경")
        try external.write(to: url)
        edit(model, "쓸 수 없는 수정")
        let blocked = await model.prepareToLeave()
        XCTAssertFalse(blocked, "A save that failed keeps the screen and asks")
        XCTAssertNotNil(model.saveFailure)
        // 변경 내용 버리기: nothing more is written.
        model.discardChanges()
        let afterDiscard = await model.flushAutosave()
        XCTAssertFalse(afterDiscard)
        XCTAssertEqual(try Data(contentsOf: url), external)
    }

    // MARK: Helpers

    private func edit(_ model: HWPDocumentViewModel, _ text: String) {
        model.editorText = text
        model.commitEditorChange()
        XCTAssertEqual(model.selectedBlock?.text, text)
    }

    private func savedText(_ url: URL) throws -> String? {
        try HWPXDocumentPackage.load(from: Data(contentsOf: url)).blocks.first?.text
    }

    private func hwpx(_ text: String) throws -> (URL, Data) {
        let url = temporaryURL("hwpx")
        let data = try LegacyHWPXConverter.convert(text: text)
        try data.write(to: url)
        return (url, data)
    }

    private func temporaryURL(_ pathExtension: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(pathExtension)
        cleanup.append(url)
        return url
    }

    private func recentStore() -> RecentOriginalDocumentStore {
        let suite = "HWPAutosaveTests-\(UUID().uuidString)"
        suites.append(suite)
        return RecentOriginalDocumentStore(defaults: UserDefaults(suiteName: suite)!, storageKey: "records")
    }

    private func fixture(_ name: String, _ pathExtension: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: pathExtension)
            ?? bundle.url(forResource: name, withExtension: pathExtension, subdirectory: "HWPXViewerFixtures")))
    }

    private func waitUntil(timeout: Duration = .seconds(10), _ condition: () throws -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while try !condition() {
            guard clock.now < deadline else { return XCTFail("Timed out waiting") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

/// A writer that holds each save until released and counts how many run at once.
private final class CountingWriteGate: @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var startedCount = 0
    private var activeCount = 0
    private var maxActiveCount = 0

    var started: Int { lock.withLock { startedCount } }
    var maxActive: Int { lock.withLock { maxActiveCount } }

    func write(_ url: URL, _ data: Data, _ expected: Data) throws {
        lock.withLock {
            startedCount += 1
            activeCount += 1
            maxActiveCount = max(maxActiveCount, activeCount)
        }
        defer { lock.withLock { activeCount -= 1 } }
        guard release.wait(timeout: .now() + 10) == .success else {
            throw CocoaError(.fileWriteUnknown)
        }
        try CoordinatedDocumentFileAccess.replaceContents(at: url, with: data, expectedContents: expected)
    }
}
