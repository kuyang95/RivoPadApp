import XCTest
@testable import shortcuts_example

@MainActor
final class HWPColumnEditingTests: XCTestCase {
    func testHWPXColumnSetupFlowsAcrossColumnsAndRoundTrips() async throws {
        let text = String(repeating: "다단 본문 흐름을 확인하는 한글 문장입니다. ", count: 90)
        let source = try HWPTableStructureDocument.load(LegacyHWPXConverter.convert(text: text))
        let settings = HWPColumnSettings(count: 2, gapPoints: 18, showsSeparator: true)
        let changed = try await HWPColumnSetup.applying(
            .init(settings: settings, sections: [0]), source: source, drafts: source.blocks)

        XCTAssertTrue(settings.matches(changed.layouts[0]))
        XCTAssertEqual(changed.blocks.map(\.text), source.blocks.map(\.text))
        XCTAssertTrue(changed.blocks.flatMap(\.lineLayouts).contains(where: \.startsColumn))
        let pages = HWPOriginalCanvasPageBuilder.makePages(
            blocks: changed.blocks, layouts: changed.layouts)
        let starts = Set(pages.flatMap(\.bodyBlocks).flatMap(\.lineLayouts)
            .map { Int(($0.columnStartPoints * 10).rounded()) })
        XCTAssertGreaterThanOrEqual(starts.count, 2)
        let reopened = try HWPTableStructureDocument.load(changed.data)
        XCTAssertTrue(settings.matches(reopened.layouts[0]))
        XCTAssertEqual(reopened.blocks.map(\.text), source.blocks.map(\.text))
    }

    func testMulticolumnParagraphTextSplitAndMergeRemainEditable() async throws {
        let source = try HWPTableStructureDocument.load(
            LegacyHWPXConverter.convert(text: "첫 문단을 편집합니다.\n둘째 문단입니다."))
        let settings = HWPColumnSettings(count: 3, gapPoints: 12, showsSeparator: false)
        let columns = try await HWPColumnSetup.applying(
            .init(settings: settings, sections: [0]), source: source, drafts: source.blocks)
        let index = try XCTUnwrap(columns.blocks.firstIndex(where: \.isEditable))
        var edited = columns.blocks
        edited[index] = HWPTextRunEditing.replacingText(in: edited[index],
            with: String(repeating: "다단에서 바로 입력한 내용 ", count: 12))
        edited = HWPFlowLayout.reflowingEdit(edited, before: columns.blocks,
            startingAt: edited[index].id, layouts: columns.layouts.map(\.pageSetupFlowLayout))
        let saved = try HWPTableStructureDocument.load(columns.serialized(edited))
        XCTAssertEqual(saved.blocks[index].text, edited[index].text)
        XCTAssertTrue(settings.matches(saved.layouts[0]))

        let split = try XCTUnwrap(HWPParagraphEditing.apply(
            .split(NSRange(location: 8, length: 0)), draft: saved.blocks[index], to: saved.blocks))
        let flowed = HWPParagraphEditing.reflow(split, before: saved.blocks,
            draft: saved.blocks[index], operation: .split(NSRange(location: 8, length: 0)),
            layouts: saved.layouts.map(\.pageSetupFlowLayout))
        let splitSaved = try HWPTableStructureDocument.load(saved.serialized(flowed))
        XCTAssertEqual(splitSaved.blocks.count, saved.blocks.count + 1)
        XCTAssertTrue(settings.matches(splitSaved.layouts[0]))
        let inserted = splitSaved.blocks[index + 1]
        let merged = try XCTUnwrap(HWPParagraphEditing.apply(.mergeBackward,
            draft: inserted, to: splitSaved.blocks))
        let mergedFlow = HWPParagraphEditing.reflow(merged, before: splitSaved.blocks,
            draft: inserted, operation: .mergeBackward,
            layouts: splitSaved.layouts.map(\.pageSetupFlowLayout))
        let mergedSaved = try HWPTableStructureDocument.load(splitSaved.serialized(mergedFlow))
        XCTAssertEqual(mergedSaved.blocks.count, saved.blocks.count)
        XCTAssertTrue(settings.matches(mergedSaved.layouts[0]))
    }

    func testHWPColumnRecordCanBeAddedChangedAndRemovedWithoutChangingText() throws {
        let source = try HWPTableStructureDocument.load(fixture("hangul_design_application", "hwp"))
        let section = try XCTUnwrap(source.layouts.first?.sectionIndex)
        let three = HWPColumnSettings(count: 3, gapPoints: 16, showsSeparator: true)
        let changedData = try HWPColumnSetupWriter.apply(
            .init(settings: three, sections: [section]), to: source)
        let changed = try HWPTableStructureDocument.load(changedData)
        XCTAssertTrue(three.matches(try XCTUnwrap(changed.layouts.first)))
        XCTAssertEqual(changed.blocks.map(\.text), source.blocks.map(\.text))

        let one = HWPColumnSettings(count: 1, gapPoints: 0, showsSeparator: false)
        let restoredData = try HWPColumnSetupWriter.apply(
            .init(settings: one, sections: [section]), to: changed)
        let restored = try HWPTableStructureDocument.load(restoredData)
        XCTAssertTrue(one.matches(try XCTUnwrap(restored.layouts.first)))
        XCTAssertEqual(restored.blocks.map(\.text), source.blocks.map(\.text))
    }

    func testInvalidColumnSettingsAndComplexSectionAreRejected() async throws {
        let source = try HWPTableStructureDocument.load(LegacyHWPXConverter.convert(text: "본문"))
        XCTAssertThrowsError(try HWPColumnSetup.validate(.init(
            settings: .init(count: 5, gapPoints: 0, showsSeparator: false), sections: [0]),
            layouts: source.layouts))
        XCTAssertThrowsError(try HWPColumnSetup.validate(.init(
            settings: .init(count: 2, gapPoints: 1_000, showsSeparator: false), sections: [0]),
            layouts: source.layouts))
        XCTAssertThrowsError(try HWPColumnSetup.validate(.init(
            settings: .init(count: 2, gapPoints: 10, showsSeparator: false), sections: [9]),
            layouts: source.layouts))
    }

    func testViewModelColumnSetupUndoRedoAndSave() async throws {
        let source = try HWPTableStructureDocument.load(
            LegacyHWPXConverter.convert(text: "다단 저장 확인 본문"))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".hwpx")
        try source.data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let settings = HWPColumnSettings(count: 2, gapPoints: 15, showsSeparator: true)
        try await model.applyColumnSetup(.init(settings: settings, sections: [0]))
        XCTAssertTrue(settings.matches(model.pageLayouts[0]))
        model.undo()
        XCTAssertEqual(model.pageLayouts[0].columnLayout.count, 1)
        model.redo()
        XCTAssertTrue(settings.matches(model.pageLayouts[0]))
        await model.save()
        XCTAssertNil(model.errorDescription)
        let reopened = try HWPTableStructureDocument.load(Data(contentsOf: url))
        XCTAssertTrue(settings.matches(reopened.layouts[0]))
        XCTAssertEqual(reopened.blocks.map(\.text), source.blocks.map(\.text))
    }

    private func fixture(_ name: String, _ ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext,
                subdirectory: "HWPXViewerFixtures")))
    }
}
