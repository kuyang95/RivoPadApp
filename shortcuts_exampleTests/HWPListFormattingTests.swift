import RivoDocumentEngine
import XCTest
import UIKit
@testable import shortcuts_example

@MainActor
final class HWPListFormattingTests: XCTestCase {
    private func package(_ text: String = "첫째\n둘째\n셋째") throws -> HWPXDocumentPackage {
        try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: text))
    }

    private func list(_ kind: HWPListKind, _ blocks: [HWPDocumentBlock], index: Int) -> [HWPDocumentBlock] {
        var result = blocks
        let style = HWPListFormatting.style(kind, for: blocks[index], in: blocks)
        result[index] = HWPDocumentFormatting.apply(.list(style), to: blocks[index], range: NSRange(location: 0, length: 0))
        return HWPListFormatting.renumbering(result)
    }

    func testApplyConvertAndRemoveDoNotChangeTextOrCharacterStyles() throws {
        let original = try package().blocks
        var source = original
        source[0] = HWPDocumentFormatting.apply(.bold(true), to: source[0], range: NSRange(location: 0, length: 1))
        var edited = list(.bullet, source, index: 0)
        XCTAssertEqual(edited[0].presentation.list?.kind, .bullet)
        XCTAssertEqual(edited[0].presentation.textRuns, source[0].presentation.textRuns)
        XCTAssertEqual(edited.map(\.text), source.map(\.text))
        XCTAssertTrue(HWPDocumentFormatting.hasChanges(from: source[0], to: edited[0]))
        edited = list(.number, edited, index: 0)
        XCTAssertEqual(edited[0].presentation.list?.marker(in: edited[0])?.run.text, "1.")
        edited[0] = HWPDocumentFormatting.apply(.list(nil), to: edited[0], range: NSRange(location: 0, length: 0))
        XCTAssertNil(edited[0].presentation.list)
        XCTAssertTrue(edited[0].lineLayouts.allSatisfy { $0.listMarker == nil })
        XCTAssertTrue(HWPDocumentFormatting.matches(source[0], edited[0]))
    }

    func testConsecutiveNumbersShareDefinitionAndRemovingItemRenumbers() throws {
        var blocks = try package().blocks
        for index in blocks.indices { blocks = list(.number, blocks, index: index) }
        XCTAssertEqual(Set(blocks.compactMap { $0.presentation.list?.definitionID }).count, 1)
        XCTAssertEqual(blocks.compactMap { $0.presentation.list?.ordinal }, [1, 2, 3])
        blocks[1] = HWPDocumentFormatting.apply(.list(nil), to: blocks[1], range: NSRange(location: 0, length: 0))
        blocks = HWPListFormatting.renumbering(blocks)
        XCTAssertEqual(blocks.compactMap { $0.presentation.list?.ordinal }, [1, 2])
        XCTAssertNil(blocks[1].presentation.list)
    }

    func testSeparateDefinitionsAndCellContextsDoNotShareCounters() throws {
        let source = try package().blocks
        let a = list(.number, source, index: 0)
        let b = list(.number, a, index: 2)
        XCTAssertNotEqual(b[0].presentation.list?.definitionID, b[2].presentation.list?.definitionID)
        XCTAssertEqual(b[2].presentation.list?.ordinal, 1)
        let style = try XCTUnwrap(b[0].presentation.list)
        func cell(_ row: Int, paragraph: Int) -> HWPDocumentBlock {
            HWPDocumentBlock(id: "cell-\(row)-\(paragraph)", sectionPath: "Contents/section0.xml", paragraphIndex: paragraph,
                text: "셀", tableLocation: .init(table: 0, row: row, column: 0, paragraph: paragraph),
                isEditable: true, presentation: .init(list: style))
        }
        let cells = HWPListFormatting.renumbering([cell(0, paragraph: 0), cell(0, paragraph: 1), cell(1, paragraph: 0)])
        XCTAssertEqual(cells.compactMap { $0.presentation.list?.ordinal }, [1, 2, 1])
    }

    func testEnterContinuesAndEmptyItemEndsWithoutAddingParagraph() throws {
        var blocks = list(.number, try package("한글 😀").blocks, index: 0)
        let split = try XCTUnwrap(HWPParagraphEditing.apply(.split(NSRange(location: blocks[0].text.utf16.count, length: 0)), draft: blocks[0], to: blocks))
        blocks = split.blocks
        XCTAssertEqual(blocks.map(\.text), ["한글 😀", ""])
        XCTAssertEqual(blocks.compactMap { $0.presentation.list?.ordinal }, [1, 2])
        XCTAssertEqual(split.caret, 0)
        let exit = try XCTUnwrap(HWPParagraphEditing.apply(.split(NSRange(location: 0, length: 0)), draft: blocks[1], to: blocks))
        XCTAssertEqual(exit.blocks.count, 2)
        XCTAssertNil(exit.blocks[1].presentation.list)
        XCTAssertEqual(exit.focusedID, blocks[1].id)
    }

    func testBackspaceAtListStartRemovesHeadingBeforeMergingText() throws {
        let blocks = list(.bullet, try package().blocks, index: 1)
        let unlisted = try XCTUnwrap(HWPParagraphEditing.apply(.mergeBackward, draft: blocks[1], to: blocks))
        XCTAssertEqual(unlisted.blocks.map(\.text), blocks.map(\.text))
        XCTAssertNil(unlisted.blocks[1].presentation.list)
        let merged = try XCTUnwrap(HWPParagraphEditing.apply(.mergeBackward, draft: unlisted.blocks[1], to: unlisted.blocks))
        XCTAssertEqual(merged.blocks.map(\.text), ["첫째둘째", "셋째"])
    }

    func testReflowReservesMarkerForEveryLineAndDrawsOnlyFirst() throws {
        let package = try package(String(repeating: "긴 한글 목록 본문 ", count: 60))
        let block = list(.number, package.blocks, index: 0)[0]
        let lines = HWPFlowLayout.measure(block, width: 100, startY: 0, pageHeight: 100, minimumHeight: 0)
        XCTAssertGreaterThan(lines.count, 4)
        XCTAssertTrue(lines.allSatisfy { $0.listMarker != nil })
        XCTAssertEqual(lines.filter(\.showsListMarker).count, 1)
        XCTAssertTrue(lines.dropFirst().contains(where: \.startsPage))
        let attributes = HWPInlineTextAttributes.make(block: block)
        let paragraph = try XCTUnwrap(attributes.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertGreaterThan(paragraph.headIndent, 0)
        XCTAssertEqual(paragraph.headIndent, paragraph.firstLineHeadIndent)
    }

    func testBinaryNumberingDefinitionHasSevenHeadsAndValidCounters() throws {
        let style = HWPParagraphList(kind: .number, definitionID: "new-test", format: "^1.", start: 3)
        let data = try HWPListBinary.definition(style)
        let levels = HWPListBinary.levels(data)
        XCTAssertEqual(levels.count, 7)
        XCTAssertEqual(levels.map(\.start), Array(repeating: 3, count: 7))
        XCTAssertEqual(levels.map(\.format), (1...7).map { "^\($0)." })
        XCTAssertTrue(HWPListBinary.levels(Data(data.prefix(15))).isEmpty)
    }

    func testHWPXNativeListsRoundTripContinueAfterReopenAndRemove() throws {
        var package = try package()
        var blocks = package.blocks
        for index in blocks.indices { blocks = list(.number, blocks, index: index) }
        let saved = try package.serializedData(applying: blocks)
        let archive = try HWPXEditingArchive(data: saved)
        let header = String(decoding: try archive.data(at: "Contents/header.xml"), as: UTF8.self)
        XCTAssertEqual(try HWPFormattingXML.elements(header, name: "numbering").count, 1)
        XCTAssertTrue(header.contains("type=\"NUMBER\""))
        package = try HWPXDocumentPackage.load(from: saved)
        XCTAssertEqual(package.blocks.map(\.text), blocks.map(\.text))
        XCTAssertEqual(package.blocks.compactMap { $0.presentation.list?.ordinal }, [1, 2, 3])
        let last = package.blocks[2]
        let split = try XCTUnwrap(HWPParagraphEditing.apply(.split(NSRange(location: last.text.utf16.count, length: 0)), draft: last, to: package.blocks))
        let continued = try HWPXDocumentPackage.load(from: package.serializedData(applying: split.blocks))
        XCTAssertEqual(continued.blocks.compactMap { $0.presentation.list?.ordinal }, [1, 2, 3, 4])
        blocks = continued.blocks
        blocks[1] = HWPDocumentFormatting.apply(.list(nil), to: blocks[1], range: NSRange(location: 0, length: 0))
        let unlisted = try HWPXDocumentPackage.load(from: continued.serializedData(applying: HWPListFormatting.renumbering(blocks)))
        XCTAssertEqual(unlisted.blocks.compactMap { $0.presentation.list?.ordinal }, [1, 2, 3])
    }

    func testHWPXBulletKeepsAssetsAndCanBeConvertedToNumbers() throws {
        let source = try fixture("mss_voucher", ext: "hwpx")
        let package = try HWPXDocumentPackage.load(from: source)
        let index = try XCTUnwrap(package.blocks.firstIndex { HWPListFormatting.supports($0) && !$0.text.isEmpty })
        var blocks = list(.bullet, package.blocks, index: index)
        let saved = try package.serializedData(applying: blocks)
        let reopened = try HWPXDocumentPackage.load(from: saved)
        XCTAssertEqual(reopened.blocks[index].presentation.list?.kind, .bullet)
        XCTAssertEqual(reopened.blocks[index].lineLayouts.first?.listMarker?.run.text, "•")
        let old = try HWPXEditingArchive(data: source), new = try HWPXEditingArchive(data: saved)
        for path in old.paths where path.hasPrefix("BinData/") { XCTAssertEqual(try old.data(at: path), try new.data(at: path)) }
        blocks = list(.number, reopened.blocks, index: index)
        let converted = try HWPXDocumentPackage.load(from: reopened.serializedData(applying: blocks))
        XCTAssertEqual(converted.blocks[index].presentation.list?.kind, .number)
    }

    func testRealHWPListsAndEnterRoundTripPreserveOtherStreams() throws {
        let source = try fixture("hangul_design_application", ext: "hwp")
        let original = try HWP5StructuredDocumentParser.parse(from: source)
        let index = try XCTUnwrap(original.blocks.firstIndex { HWPParagraphEditing.supports($0) && !$0.keepsParagraphBoundary && !$0.text.isEmpty })
        var blocks = list(.number, original.blocks, index: index)
        let draft = blocks[index]
        let split = try XCTUnwrap(HWPParagraphEditing.apply(.split(NSRange(location: draft.text.utf16.count, length: 0)), draft: draft, to: blocks))
        blocks = HWPFlowLayout.reflowingBody(split.blocks, before: original.blocks, startingAt: draft.id, layouts: original.pageLayouts)
        let saved = try HWP5DocumentRewriter.rewrite(sourceData: source, originalBlocks: original.blocks, editedBlocks: blocks)
        let reopened = try HWP5StructuredDocumentParser.parse(from: saved)
        XCTAssertEqual(reopened.blocks.map(\.text), blocks.map(\.text))
        XCTAssertEqual(reopened.blocks[index].presentation.list?.ordinal, 1)
        XCTAssertEqual(reopened.blocks[index + 1].presentation.list?.ordinal, 2)
        let old = try OLECompoundFile(data: source), new = try OLECompoundFile(data: saved)
        for path in old.streamNames where !path.hasPrefix("bodytext/") && path != "docinfo" && path != "prvtext" {
            XCTAssertEqual(try old.stream(named: path), try new.stream(named: path), path)
        }
        var bullets = list(.bullet, reopened.blocks, index: index)
        bullets[index + 1] = HWPDocumentFormatting.apply(.list(nil), to: bullets[index + 1], range: NSRange(location: 0, length: 0))
        let resaved = try HWP5DocumentRewriter.rewrite(sourceData: saved, originalBlocks: reopened.blocks, editedBlocks: bullets)
        let final = try HWP5StructuredDocumentParser.parse(from: resaved)
        XCTAssertEqual(final.blocks[index].presentation.list?.kind, .bullet)
        XCTAssertNil(final.blocks[index + 1].presentation.list)
    }

    func testMovingToNextParagraphUsesTheJustCommittedListDraft() throws {
        let blocks = try package().blocks
        let editor = HWPInlineEditingSession()
        editor.begin(block: blocks[0], at: .zero, onSelect: { _ in }, onChange: { _ in }, onCommit: {}, listContext: blocks)
        let first = HWPInlineTextView()
        first.attributedText = HWPInlineTextAttributes.make(block: blocks[0])
        editor.attach(first, token: try XCTUnwrap(editor.activation?.token))
        editor.applyList(.number)
        let definition = editor.paragraphStyle.list?.definitionID
        // SwiftUI captured blocks before begin() commits the previous draft.
        editor.begin(block: blocks[1], at: .zero, onSelect: { _ in }, onChange: { _ in }, onCommit: {}, listContext: blocks)
        let second = HWPInlineTextView()
        second.attributedText = HWPInlineTextAttributes.make(block: blocks[1])
        editor.attach(second, token: try XCTUnwrap(editor.activation?.token))
        editor.applyList(.number)
        XCTAssertEqual(editor.paragraphStyle.list?.definitionID, definition)
        XCTAssertEqual(editor.paragraphStyle.list?.ordinal, 2)
        editor.finish(commitChanges: false)
    }

    func testNativeListFormattingUndoRedoPreservesCaretAndText() throws {
        let blocks = try package("한글 😀").blocks
        let editor = HWPInlineEditingSession()
        editor.begin(block: blocks[0], at: .zero, onSelect: { _ in }, onChange: { _ in }, onCommit: {}, listContext: blocks)
        let view = HWPInlineTextView()
        view.attributedText = HWPInlineTextAttributes.make(block: blocks[0])
        view.selectedRange = NSRange(location: blocks[0].text.utf16.count, length: 0)
        editor.attach(view, token: try XCTUnwrap(editor.activation?.token))
        editor.applyList(.number)
        XCTAssertEqual(editor.paragraphStyle.list?.kind, .number)
        XCTAssertEqual(view.text, blocks[0].text)
        XCTAssertEqual(view.selectedRange.location, blocks[0].text.utf16.count)
        XCTAssertTrue(editor.undo())
        XCTAssertNil(editor.paragraphStyle.list)
        XCTAssertTrue(editor.redo())
        XCTAssertEqual(editor.paragraphStyle.list?.kind, .number)
        editor.finish(commitChanges: false)
    }

    func testViewModelListsUndoRedoEnterAndSaveHWPX() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        try package("첫 항목").sourceData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let before = model.blocks
        let numbered = list(.number, before, index: 0)[0]
        model.commitInlineBlock(numbered)
        XCTAssertEqual(model.blocks[0].presentation.list?.kind, .number)
        model.undo(); XCTAssertEqual(model.blocks, before)
        model.redo()
        let draft = model.blocks[0]
        let split = try XCTUnwrap(model.editParagraph(draft, operation: .split(NSRange(location: draft.text.utf16.count, length: 0))))
        XCTAssertEqual(split.blocks.compactMap { $0.presentation.list?.ordinal }, [1, 2])
        model.undo(); XCTAssertEqual(model.blocks.count, 1)
        model.redo(); XCTAssertEqual(model.blocks.count, 2)
        await model.save()
        XCTAssertNil(model.errorDescription)
        let reopened = try HWPXDocumentPackage.load(from: Data(contentsOf: url))
        XCTAssertEqual(reopened.blocks.compactMap { $0.presentation.list?.ordinal }, [1, 2])
        XCTAssertEqual(reopened.blocks.map(\.text), ["첫 항목", ""])
    }

    private func fixture(_ name: String, ext: String) throws -> Data {
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("HWPXViewerFixtures/\(name).\(ext)")
        return try Data(contentsOf: url)
    }
}
