import RivoDocumentEngine
import XCTest
@testable import shortcuts_example

/// The 간편 보기 editors: 문단 편집 (text, structure, 글자·문단, link, notes, table) and the
/// table row's 표 편집, each one undo step together with the typed text.
@MainActor
final class HWPAccessibleParagraphEditingTests: XCTestCase {
    func testColorCodes() {
        XCTAssertEqual(HWPColorCode.parse("#1f6fb2"), 0x1F6FB2)
        XCTAssertEqual(HWPColorCode.parse(" 1F6FB2 "), 0x1F6FB2)
        XCTAssertNil(HWPColorCode.parse("#12345"))
        XCTAssertNil(HWPColorCode.parse("#GG0000"))
        XCTAssertNil(HWPColorCode.parse("#1F6FB2FF"))
        XCTAssertEqual(HWPColorCode.string(0x1F6FB2), "#1F6FB2")
        XCTAssertEqual(HWPColorCode.string(0xFF000000), "#000000")
        XCTAssertEqual(HWPColorCode.rgb(HWPColorCode.color(0x1F6FB2)), 0x1F6FB2)
    }

    func testTextSelectionBecomesEngineUTF16Range() {
        let text = "😀가\r\n나다"
        let start = text.firstIndex(of: "나")!
        XCTAssertEqual(HWPAccessibleTextRange.utf16Range(start..<text.endIndex, in: text), NSRange(location: 4, length: 2))
        XCTAssertEqual(HWPAccessibleTextRange.utf16Range(nil, in: text), NSRange(location: 6, length: 0))
        let emoji = text.index(after: text.startIndex)
        XCTAssertEqual(HWPAccessibleTextRange.utf16Range(emoji..<emoji, in: text), NSRange(location: 2, length: 0))
        // A caret inside the emoji goes to its start.
        XCTAssertEqual(HWPAccessibleTextRange.index(utf16Offset: 1, in: "😀가"), "😀가".startIndex)
        XCTAssertEqual(HWPAccessibleTextRange.index(utf16Offset: 99, in: "가"), "가".endIndex)
    }

    func testTypedTextAndFormattingAreOneUndoStep() async throws {
        let model = try await load(text: "첫 문단\n둘째 문단")
        let original = model.blocks
        let id = try XCTUnwrap(original.first { $0.text == "첫 문단" }).id
        XCTAssertTrue(model.formatAccessibleParagraph(id, text: "바뀐 첫 문단", range: NSRange(location: 0, length: 2),
            commands: [.bold(true), .color(0x1F6FB2), .highlight(0xB2E3FF)]))
        let edited = try XCTUnwrap(model.blocks.first { $0.id == id })
        XCTAssertEqual(edited.text, "바뀐 첫 문단")
        let bold = HWPDocumentFormatting.run(at: 0, in: edited)
        XCTAssertTrue(bold.isBold)
        XCTAssertEqual(bold.textColorRGB, 0x1F6FB2)
        XCTAssertEqual(bold.backgroundColorRGB, 0xB2E3FF)
        XCTAssertFalse(HWPDocumentFormatting.run(at: 3, in: edited).isBold)
        XCTAssertEqual(model.selectedBlockID, id)
        XCTAssertEqual(model.status, AppLocalization.string("서식을 바꿨습니다. 저장하면 파일에 반영됩니다."))
        model.undo()
        XCTAssertEqual(model.blocks, original)
        XCTAssertFalse(model.canUndo)

        // No selection: the whole paragraph; paragraph commands as the 문단 sheet sends them.
        XCTAssertTrue(model.formatAccessibleParagraph(id, text: "첫 문단", range: NSRange(location: 4, length: 0),
            commands: [.italic(true), .alignment(.centered)]))
        let whole = try XCTUnwrap(model.blocks.first { $0.id == id })
        XCTAssertTrue(HWPDocumentFormatting.runs(in: whole).allSatisfy(\.isItalic))
        XCTAssertEqual(whole.presentation.alignment, .centered)
        model.undo()
        XCTAssertEqual(model.blocks, original)

        // Nothing changed: no undo step.
        XCTAssertTrue(model.formatAccessibleParagraph(id, text: "첫 문단", range: NSRange(location: 0, length: 0), commands: []))
        XCTAssertFalse(model.canUndo)
    }

    func testApplyTypedText() async throws {
        let model = try await load(text: "첫 문단\n둘째 문단")
        let original = model.blocks
        let id = try XCTUnwrap(original.first { $0.text == "둘째 문단" }).id
        XCTAssertTrue(model.applyAccessibleParagraphText(id, text: "둘째\r\n줄"))
        XCTAssertEqual(model.blocks.first { $0.id == id }?.text, "둘째\n줄")
        XCTAssertEqual(model.editorText, "둘째\n줄")
        model.undo()
        XCTAssertEqual(model.blocks, original)
        XCTAssertFalse(model.applyAccessibleParagraphText("missing", text: "x"))
    }

    func testSplitMergeAndPageBreakWithTypedTextAreOneUndoStepEach() async throws {
        for (name, ext) in [("plain", "hwpx"), ("hangul_design_application", "hwp")] {
            let model = ext == "hwpx" ? try await load(text: "첫 문단\n둘째 문단") : try await load(fixture: name, ext)
            let original = model.blocks
            let index = try XCTUnwrap(original.indices.dropFirst().first {
                HWPParagraphEditing.supports(original[$0]) && original[$0].text.count > 2
                    && HWPParagraphEditing.supports(original[$0 - 1])
            }, name)
            let id = original[index].id

            let split = try XCTUnwrap(model.editAccessibleParagraph(id, text: "가나다라", operation: .split(NSRange(location: 2, length: 0))), name)
            XCTAssertEqual(model.blocks.count, original.count + 1, name)
            XCTAssertEqual(model.blocks[index].text, "가나", name)
            XCTAssertEqual(model.blocks[index + 1].text, "다라", name)
            XCTAssertEqual(split.focusedID, model.blocks[index + 1].id, name)
            XCTAssertEqual(model.selectedBlockID, split.focusedID, name)
            model.undo()
            XCTAssertEqual(model.blocks.map(\.text), original.map(\.text), name)
            XCTAssertFalse(model.canUndo, name)

            let merged = try XCTUnwrap(model.editAccessibleParagraph(id, text: "합칠 글", operation: .mergeBackward), name)
            XCTAssertEqual(model.blocks.count, original.count - 1, name)
            XCTAssertEqual(model.blocks[index - 1].text, original[index - 1].text + "합칠 글", name)
            XCTAssertEqual(merged.focusedID, original[index - 1].id, name)
            model.undo()
            XCTAssertEqual(model.blocks.map(\.text), original.map(\.text), name)
            XCTAssertFalse(model.canUndo, name)

            _ = try XCTUnwrap(model.editAccessibleParagraph(id, text: original[index].text,
                operation: .insertPageBreak(NSRange(location: 0, length: 0))), name)
            XCTAssertTrue(try XCTUnwrap(model.blocks.first { $0.id == id }).presentation.pageBreakBefore, name)
            _ = try XCTUnwrap(model.editAccessibleParagraph(id, text: original[index].text, operation: .removePageBreak), name)
            XCTAssertFalse(try XCTUnwrap(model.blocks.first { $0.id == id }).presentation.pageBreakBefore, name)
            model.undo(); model.undo()
            XCTAssertEqual(model.blocks.map(\.text), original.map(\.text), name)
            XCTAssertFalse(model.canUndo, name)
        }
    }

    func testFirstParagraphCannotMerge() async throws {
        let model = try await load(text: "첫 문단\n둘째 문단")
        let first = try XCTUnwrap(model.blocks.first { HWPParagraphEditing.supports($0) })
        XCTAssertNil(model.editAccessibleParagraph(first.id, text: "바뀐", operation: .mergeBackward))
        XCTAssertFalse(model.canUndo)
        XCTAssertEqual(model.blocks.first { $0.id == first.id }?.text, first.text)
    }

    func testLinkNoteAndTableWithTypedTextAreOneUndoStep() async throws {
        let model = try await load(text: "첫 문단\n둘째 문단")
        let original = model.blocks
        let id = try XCTUnwrap(original.first { $0.text == "첫 문단" }).id
        let typed = "새 링크 글"

        var drafts = try XCTUnwrap(model.accessibleParagraphDrafts(id, text: typed))
        let range = (typed as NSString).range(of: "링크")
        let link = try XCTUnwrap(HWPHyperlinkEditing.selection(blocks: drafts, selectedID: id, range: range))
        XCTAssertNil(HWPHyperlinkEditing.selection(blocks: drafts, selectedID: id, range: NSRange(location: 0, length: 0)))
        _ = try await model.editHyperlink(.set("example.com"), selection: link, drafts: drafts)
        let linked = try XCTUnwrap(model.blocks.first { $0.text == typed })
        XCTAssertEqual(HWPHyperlinkEditing.spans(in: linked), [.init(range: range, target: "https://example.com")])
        model.undo()
        XCTAssertEqual(model.blocks.map(\.text), original.map(\.text))
        XCTAssertFalse(model.canUndo)

        drafts = try XCTUnwrap(model.accessibleParagraphDrafts(id, text: typed))
        let insertion = try XCTUnwrap(HWPNoteEditing.insertion(blocks: drafts, selectedID: id,
            range: NSRange(location: typed.utf16.count, length: 0)))
        _ = try await model.editNote(.insert(.footNote, "주석 내용", insertion), drafts: drafts)
        XCTAssertTrue(model.blocks.contains { $0.text == typed })
        XCTAssertTrue(model.blocks.contains { $0.region.kind == .footnote && $0.text == "주석 내용" })
        model.undo()
        XCTAssertEqual(model.blocks.map(\.text), original.map(\.text))
        XCTAssertFalse(model.canUndo)

        drafts = try XCTUnwrap(model.accessibleParagraphDrafts(id, text: typed))
        let place = try XCTUnwrap(HWPTableInsertion.selection(blocks: drafts, selectedID: id,
            range: NSRange(location: 2, length: 0), layouts: model.pageLayouts))
        _ = try await model.insertTable(.init(selection: place, rows: 2, columns: 3), drafts: drafts)
        XCTAssertEqual(model.blocks.filter { $0.tableLocation != nil }.count, 6)
        XCTAssertTrue(model.blocks.contains { $0.text == "새 " })
        model.undo()
        XCTAssertEqual(model.blocks.map(\.text), original.map(\.text))
        XCTAssertFalse(model.canUndo)
    }

    func testTableEditPicksCellsFormatsAndChangesStructure() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        try tablePackage().sourceData.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let original = model.blocks
        let row = try XCTUnwrap(HWPAccessibleDocument.make(blocks: original).tables.first?.rows.first)
        let cells = HWPAccessibleTableEditSheet.cells(of: row)
        XCTAssertEqual(cells.count, 2)
        let anchor = cells[0].anchor

        let actions = model.accessibleTableActions(anchor.id)
        XCTAssertTrue(actions.contains(.rowBelow))
        XCTAssertTrue(actions.contains(.mergeRight))
        XCTAssertTrue(actions.contains(.deleteTable))
        XCTAssertFalse(actions.contains(.resize))
        XCTAssertEqual(actions, HWPTableStructureAction.allCases.filter(actions.contains))
        XCTAssertNotNil(model.accessibleTableSizing(anchor.id))

        var format = HWPCellFormat(try XCTUnwrap(anchor.tableLocation))
        format.vertical = .end
        format.setFill(0x123456)
        XCTAssertTrue(model.formatAccessibleCell(anchor.id, format: format))
        for block in model.blocks where HWPCellFormatting.sameCell(block, anchor) {
            XCTAssertEqual(block.tableLocation?.cellVerticalAlignment, .end)
            XCTAssertEqual(block.tableLocation?.boxStyle?.backgroundColorRGB, 0x123456)
        }
        model.undo()
        XCTAssertEqual(model.blocks, original)

        _ = try await model.editTable(.rowBelow, selectedID: anchor.id)
        XCTAssertEqual(HWPAccessibleDocument.make(blocks: model.blocks).tables.first?.rows.count, 3)
        model.undo()
        XCTAssertEqual(model.blocks, original)
        XCTAssertFalse(model.canUndo)

        XCTAssertFalse(model.formatAccessibleCell(try XCTUnwrap(original.first { $0.tableLocation == nil }).id, format: format))
    }

    func testFailedFileToolKeepsDocumentAndReportsForTheOpenEditor() async throws {
        let model = try await load(text: "첫 문단\n둘째 문단")
        let original = model.blocks
        let id = try XCTUnwrap(original.first { $0.text == "첫 문단" }).id
        let typed = "새 링크 글"
        // The selection was made on different drafts than those sent: the engine refuses it.
        let drafts = try XCTUnwrap(model.accessibleParagraphDrafts(id, text: typed))
        let stale = try XCTUnwrap(model.accessibleParagraphDrafts(id, text: "다른 링크 글"))
        let selection = try XCTUnwrap(HWPHyperlinkEditing.selection(blocks: stale, selectedID: id,
            range: ("다른 링크 글" as NSString).range(of: "링크")))
        let runner = HWPAccessibleToolRunner()
        let failure = await runner.perform {
            _ = try await model.editHyperlink(.set("example.com"), selection: selection, drafts: drafts)
        }
        XCTAssertNotNil(failure?.failure)
        XCTAssertFalse(runner.isRunning)
        XCTAssertEqual(model.blocks, original)
        XCTAssertFalse(model.canUndo)
        XCTAssertFalse(model.isSaving)
        XCTAssertFalse(model.hasUnsavedChanges)
        // The editor still holds the typed text, so the same drafts can be rebuilt and applied.
        XCTAssertEqual(model.accessibleParagraphDrafts(id, text: typed), drafts)
        let succeeded = await runner.perform {
            let link = try XCTUnwrap(HWPHyperlinkEditing.selection(blocks: drafts, selectedID: id,
                range: (typed as NSString).range(of: "링크")))
            _ = try await model.editHyperlink(.set("example.com"), selection: link, drafts: drafts)
        }
        XCTAssertNotNil(succeeded)
        XCTAssertNil(succeeded?.failure)
        XCTAssertTrue(model.blocks.contains { $0.text == typed })
    }

    func testRunningToolLocksEditorUntilItFinishes() async throws {
        let model = try await load(text: "첫 문단\n둘째 문단")
        let id = try XCTUnwrap(model.blocks.first { $0.text == "첫 문단" }).id
        let typed = "새 링크 글"
        let drafts = try XCTUnwrap(model.accessibleParagraphDrafts(id, text: typed))
        let link = try XCTUnwrap(HWPHyperlinkEditing.selection(blocks: drafts, selectedID: id,
            range: (typed as NSString).range(of: "링크")))
        let runner = HWPAccessibleToolRunner()
        var lockedDuringWork = false, secondWhileRunning: HWPAccessibleToolRunner.Outcome?? = .none
        let outcome = await runner.perform {
            // The sheet's lock (text editor, tools, 취소·적용, swipe-to-dismiss) is on while the file is rewritten.
            lockedDuringWork = runner.isRunning
            secondWhileRunning = .some(await runner.perform {
                XCTFail("A second tool must not run while one is running")
            })
            _ = try await model.editHyperlink(.set("example.com"), selection: link, drafts: drafts)
            lockedDuringWork = lockedDuringWork && (runner.isRunning || model.isSaving)
        }
        XCTAssertTrue(lockedDuringWork)
        XCTAssertNil(secondWhileRunning ?? nil)
        XCTAssertNil(try XCTUnwrap(outcome).failure)
        XCTAssertFalse(runner.isRunning)
        XCTAssertFalse(model.isSaving)
        XCTAssertTrue(model.blocks.contains { $0.text == typed })
    }

    func testCharacterEffectsSendTouchedControlsForMixedSelection() async throws {
        let model = try await load(text: "가나다라")
        let block = try XCTUnwrap(model.blocks.first { $0.text == "가나다라" })
        let all = NSRange(location: 0, length: 4)
        XCTAssertTrue(model.formatAccessibleParagraph(block.id, text: block.text, range: NSRange(location: 2, length: 2),
            commands: [.bold(true), .superscript(true)]))
        let mixed = try XCTUnwrap(model.blocks.first { $0.id == block.id })
        let runs = HWPCharacterEffects.runs(in: mixed, range: all)
        XCTAssertGreaterThan(runs.count, 1)

        // Mixed: shown off; touching it on then off again still sends "off" for every character.
        var effects = HWPCharacterEffects(runs: runs)
        XCTAssertFalse(effects[.bold])
        XCTAssertTrue(effects.commands.isEmpty)
        effects.set(.bold, true)
        effects.set(.bold, false)
        XCTAssertEqual(effects.commands.count, 1)
        var result = effects.commands.reduce(mixed) { HWPDocumentFormatting.apply($1, to: $0, range: all) }
        XCTAssertTrue(HWPDocumentFormatting.runs(in: result).allSatisfy { !$0.isBold })

        // Left on: every character becomes bold, though the first run already was not.
        effects = HWPCharacterEffects(runs: runs)
        effects.set(.bold, true)
        result = effects.commands.reduce(mixed) { HWPDocumentFormatting.apply($1, to: $0, range: all) }
        XCTAssertTrue(HWPDocumentFormatting.runs(in: result).allSatisfy(\.isBold))

        // Subscript on clears superscript everywhere, superscript included in what is sent.
        effects = HWPCharacterEffects(runs: runs)
        effects.set(.subscript, true)
        result = effects.commands.reduce(mixed) { HWPDocumentFormatting.apply($1, to: $0, range: all) }
        XCTAssertTrue(HWPDocumentFormatting.runs(in: result).allSatisfy { $0.isSubscript && !$0.isSuperscript })

        // A selection inside one run starts from that run's values.
        let boldRuns = HWPCharacterEffects.runs(in: mixed, range: NSRange(location: 2, length: 1))
        XCTAssertTrue(HWPCharacterEffects(runs: boldRuns)[.bold])
        XCTAssertTrue(HWPCharacterEffects(runs: boldRuns)[.superscript])
    }

    // MARK: - Fixtures

    private func load(text: String) async throws -> HWPDocumentViewModel {
        try await load(data: LegacyHWPXConverter.convert(text: text), ext: "hwpx")
    }

    private func load(fixture name: String, _ ext: String) async throws -> HWPDocumentViewModel {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "HWPXViewerFixtures"))
        return try await load(data: Data(contentsOf: url), ext: ext)
    }

    private func load(data: Data, ext: String) async throws -> HWPDocumentViewModel {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        XCTAssertNil(model.errorDescription)
        XCTAssertTrue(model.isEditableDocument)
        return model
    }

    private func tablePackage() throws -> HWPXDocumentPackage {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "\n표 뒤"))
        let section = package.sections[0]
        let first = try XCTUnwrap(HWPFormattingXML.elements(section.xml, name: "p").first)
        let paragraph = first.xml.replacingOccurrences(of: "</hp:run>", with: HWPCellFormattingTests.tableXML + "</hp:run>")
        let xml = (section.xml as NSString).replacingCharacters(in: first.range, with: paragraph)
        let data = try HWPXEditingArchive(data: package.sourceData).repack(replacing: [section.path: Data(xml.utf8)])
        return try HWPXDocumentPackage.load(from: data)
    }
}
