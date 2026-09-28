import SwiftUI
import UIKit
import XCTest
@testable import shortcuts_example

@MainActor
final class HWPCharacterFormattingTests: XCTestCase {
    private let effects: [HWPFormattingCommand] = [.highlight(0xFFC7DE), .strikethrough(true), .superscript(true)]

    private func apply(_ commands: [HWPFormattingCommand], to block: HWPDocumentBlock, range: NSRange? = nil) -> HWPDocumentBlock {
        commands.reduce(block) { HWPDocumentFormatting.apply($1, to: $0,
            range: range ?? NSRange(location: 0, length: block.text.utf16.count)) }
    }

    private func package(_ text: String) throws -> HWPXDocumentPackage {
        try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: text))
    }

    func testEffectsRespectKoreanEmojiSelectionAndLeaveOtherSpansIntact() throws {
        let block = try package("앞 한글 👨‍👩‍👧‍👦 뒤").blocks[0]
        let range = (block.text as NSString).range(of: "한글 👨‍👩‍👧‍👦")
        let edited = apply(effects, to: block, range: range)
        XCTAssertEqual(edited.text, block.text)
        XCTAssertEqual(HWPDocumentFormatting.run(at: 0, in: edited).withText(""), HWPDocumentFormatting.run(at: 0, in: block).withText(""))
        let style = HWPDocumentFormatting.run(at: range.location, in: edited)
        XCTAssertTrue(style.isStruckThrough); XCTAssertTrue(style.isSuperscript)
        XCTAssertEqual(style.backgroundColorRGB, 0xFFC7DE)
        XCTAssertEqual(HWPDocumentFormatting.run(at: block.text.utf16.count - 1, in: edited).backgroundColorRGB,
            HWPDocumentFormatting.run(at: block.text.utf16.count - 1, in: block).backgroundColorRGB)
        XCTAssertFalse(HWPDocumentFormatting.matches(block, edited))
        let emoji = (block.text as NSString).range(of: "👨‍👩‍👧‍👦")
        XCTAssertEqual(apply(effects, to: block, range: NSRange(location: emoji.location + 1, length: 1)), block)
    }

    func testSuperscriptAndSubscriptAreExclusiveAndCanBothBeRemoved() throws {
        let block = apply(effects, to: try package("H2O x2").blocks[0])
        let sub = apply([.subscript(true)], to: block)
        let style = HWPDocumentFormatting.run(at: 0, in: sub)
        XCTAssertTrue(style.isSubscript); XCTAssertFalse(style.isSuperscript)
        XCTAssertTrue(style.isStruckThrough); XCTAssertEqual(style.backgroundColorRGB, 0xFFC7DE)
        let normal = apply([.subscript(false), .highlight(nil), .strikethrough(false)], to: sub)
        XCTAssertFalse(HWPDocumentFormatting.run(at: 0, in: normal).isSubscript)
        XCTAssertFalse(HWPDocumentFormatting.run(at: 0, in: normal).isStruckThrough)
        XCTAssertNil(HWPDocumentFormatting.run(at: 0, in: normal).backgroundColorRGB)
    }

    func testClearResetsCharacterStyleAndKeepsParagraphAndList() throws {
        let source = try package("첫째\t글자").blocks[0]
        var style = source.presentation
        style.alignment = .centered; style.leftMarginPoints = 12
        style.list = HWPListFormatting.style(.number, for: source, in: [source])
        style.textRuns = [HWPDocumentTextRun(text: source.text, fontName: "Arial", fontSizePoints: 24,
            fontWidthPercent: 80, letterSpacingPercent: -10, baselinePositionPercent: 5,
            textColorRGB: 0xFF0000, backgroundColorRGB: 0xFFFF00, isBold: true, isItalic: true,
            isUnderlined: true, isStruckThrough: true, isSuperscript: true)]
        let sourceWithStyle = source.withPresentation(style)
        let clear = apply([.clearCharacterFormatting], to: sourceWithStyle)
        let run = HWPDocumentFormatting.run(at: 0, in: clear)
        XCTAssertEqual(run, HWPDocumentTextRun(text: source.text, fontName: "바탕", fontSizePoints: 10, textColorRGB: 0))
        var expected = style; expected.textRuns = clear.presentation.textRuns
        XCTAssertEqual(clear.presentation, expected)
    }

    func testHWPXEffectsToggleAndClearSurviveRepeatedSave() throws {
        var source = try package("한글 ABC\n보존할 문단")
        var blocks = source.blocks
        blocks[0] = apply(effects + [.font("Arial"), .size(24), .bold(true)], to: blocks[0], range: NSRange(location: 0, length: 2))
        let data = try source.serializedData(applying: blocks)
        let archive = try HWPXEditingArchive(data: data)
        let header = String(decoding: try archive.data(at: "Contents/header.xml"), as: UTF8.self)
        XCTAssertTrue(header.contains("shadeColor=\"#FFC7DE\""))
        XCTAssertTrue(header.contains("supscript")); XCTAssertTrue(header.contains("strikeout shape=\"SOLID\""))
        source = try HWPXDocumentPackage.load(from: data)
        XCTAssertTrue(HWPDocumentFormatting.matches(source.blocks[0], blocks[0]))
        XCTAssertEqual(source.blocks[1], blocks[1])
        blocks = source.blocks
        blocks[0] = apply([.subscript(true), .highlight(nil), .strikethrough(false)], to: blocks[0])
        source = try HWPXDocumentPackage.load(from: source.serializedData(applying: blocks))
        XCTAssertTrue(HWPDocumentFormatting.matches(source.blocks[0], blocks[0]))
        blocks = source.blocks; blocks[0] = apply([.clearCharacterFormatting], to: blocks[0])
        let clear = try HWPXDocumentPackage.load(from: source.serializedData(applying: blocks))
        XCTAssertTrue(HWPDocumentFormatting.matches(clear.blocks[0], blocks[0]))
        XCTAssertEqual(clear.blocks[1], blocks[1])
    }

    func testRealHWPEffectsAndClearPreserveOtherParagraphsAndStreams() throws {
        var data = try fixture("hangul_design_application", ext: "hwp")
        var source = try HWP5StructuredDocumentParser.parse(from: data)
        let index = try XCTUnwrap(source.blocks.firstIndex { $0.isEditable && $0.text.count > 4 })
        for commands in [effects + [.font("Arial"), .size(24)], [.subscript(true), .highlight(nil), .strikethrough(false)], [.clearCharacterFormatting]] {
            var blocks = source.blocks
            blocks[index] = apply(commands, to: blocks[index], range: NSRange(location: 0, length: 2))
            let saved = try HWP5DocumentRewriter.rewrite(sourceData: data, originalBlocks: source.blocks, editedBlocks: blocks)
            let reopened = try HWP5StructuredDocumentParser.parse(from: saved)
            XCTAssertTrue(HWPDocumentFormatting.matches(reopened.blocks[index], blocks[index]))
            for i in blocks.indices where i != index { XCTAssertEqual(reopened.blocks[i], source.blocks[i], "Paragraph \(i)") }
            let old = try OLECompoundFile(data: data), new = try OLECompoundFile(data: saved)
            for path in old.streamNames where !path.hasPrefix("bodytext/") && path != "docinfo" {
                XCTAssertEqual(try old.stream(named: path), try new.stream(named: path), path)
            }
            data = saved; source = reopened
        }
    }

    func testRealHWPXCellEffectsPreserveOtherCellsAndImages() throws {
        let data = try fixture("mss_voucher", ext: "hwpx")
        let source = try HWPXDocumentPackage.load(from: data)
        let index = try XCTUnwrap(source.blocks.firstIndex { $0.isEditable && $0.tableLocation != nil && $0.text.count > 4 })
        var blocks = source.blocks
        blocks[index] = apply(effects, to: blocks[index], range: NSRange(location: 0, length: 2))
        let output = try source.serializedData(applying: blocks)
        let reopened = try HWPXDocumentPackage.load(from: output)
        XCTAssertTrue(HWPDocumentFormatting.matches(reopened.blocks[index], blocks[index]))
        for i in blocks.indices where i != index { XCTAssertEqual(reopened.blocks[i], source.blocks[i], "Cell \(i)") }
        let old = try HWPXEditingArchive(data: data), new = try HWPXEditingArchive(data: output)
        for path in old.paths where path.hasPrefix("BinData/") { XCTAssertEqual(try old.data(at: path), try new.data(at: path)) }
    }

    func testClearResetsStoredWidthSpacingAndBaselineInBothFormats() throws {
        func custom(_ block: HWPDocumentBlock) -> HWPDocumentBlock {
            var style = block.presentation
            style.textRuns = HWPDocumentFormatting.runs(in: block).map {
                var run = $0; run.fontWidthPercent = 80; run.letterSpacingPercent = -10
                run.baselinePositionPercent = 8; return run
            }
            return block.withPresentation(style)
        }
        let hwpx = try package("간격 ABC")
        let altered = custom(hwpx.blocks[0])
        let loaded = try HWPXDocumentPackage.load(from: hwpx.serializedData(applying: [altered]))
        XCTAssertTrue(HWPDocumentFormatting.matches(loaded.blocks[0], altered))
        let clear = apply([.clearCharacterFormatting], to: loaded.blocks[0])
        XCTAssertTrue(HWPDocumentFormatting.matches(try HWPXDocumentPackage.load(from: loaded.serializedData(applying: [clear])).blocks[0], clear))

        let data = try fixture("hangul_design_application", ext: "hwp")
        let source = try HWP5StructuredDocumentParser.parse(from: data)
        let index = try XCTUnwrap(source.blocks.firstIndex { $0.isEditable && $0.text.count > 4 })
        var blocks = source.blocks; blocks[index] = custom(blocks[index])
        let saved = try HWP5DocumentRewriter.rewrite(sourceData: data, originalBlocks: source.blocks, editedBlocks: blocks)
        let reopened = try HWP5StructuredDocumentParser.parse(from: saved)
        XCTAssertTrue(HWPDocumentFormatting.matches(reopened.blocks[index], blocks[index]))
        blocks = reopened.blocks; blocks[index] = apply([.clearCharacterFormatting], to: blocks[index])
        let result = try HWP5DocumentRewriter.rewrite(sourceData: saved, originalBlocks: reopened.blocks, editedBlocks: blocks)
        XCTAssertTrue(HWPDocumentFormatting.matches(try HWP5StructuredDocumentParser.parse(from: result).blocks[index], blocks[index]))
    }

    func testEmptyParagraphEffectsPersistThroughSaveAndLaterTypingInBothFormats() throws {
        let hwp = try fixture("hangul_design_application", ext: "hwp")
        let original = try HWP5StructuredDocumentParser.parse(from: hwp)
        let index = try XCTUnwrap(original.blocks.firstIndex { $0.isEditable && $0.text.isEmpty })
        var blocks = original.blocks; blocks[index] = apply(effects, to: blocks[index])
        let saved = try HWP5DocumentRewriter.rewrite(sourceData: hwp, originalBlocks: original.blocks, editedBlocks: blocks)
        let reopened = try HWP5StructuredDocumentParser.parse(from: saved)
        XCTAssertTrue(HWPDocumentFormatting.matches(reopened.blocks[index], blocks[index]))
        blocks = reopened.blocks; blocks[index] = HWPTextRunEditing.replacingText(in: blocks[index], with: "첨자")
        let typed = try HWP5DocumentRewriter.rewrite(sourceData: saved, originalBlocks: reopened.blocks, editedBlocks: blocks)
        XCTAssertTrue(HWPDocumentFormatting.matches(try HWP5StructuredDocumentParser.parse(from: typed).blocks[index], blocks[index]))

        let hwpx = try package("")
        let empty = apply(effects, to: hwpx.blocks[0])
        let loaded = try HWPXDocumentPackage.load(from: hwpx.serializedData(applying: [empty]))
        XCTAssertTrue(HWPDocumentFormatting.matches(loaded.blocks[0], empty), "saved: \(loaded.blocks[0].presentation.textRuns) requested: \(empty.presentation.textRuns)")
        let input = HWPTextRunEditing.replacingText(in: loaded.blocks[0], with: "첨자")
        XCTAssertTrue(HWPDocumentFormatting.matches(try HWPXDocumentPackage.load(from: loaded.serializedData(applying: [input])).blocks[0], input))
    }

    func testNativeMixedSelectionEffectsUndoAndFutureTypingStaySemantic() async throws {
        let package = try package("가나다라")
        let source = package.blocks[0]
        let session = HWPInlineEditingSession()
        var committed: HWPDocumentBlock?
        session.begin(block: source, at: .zero, onSelect: { _ in }, onChange: { _ in }, onCommit: {}, onCommitBlock: { committed = $0 })
        let host = UIHostingController(rootView: HWPInlineTextEditor(activation: session.activation!, session: session).frame(height: 200))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.layoutIfNeeded()
        defer { session.finish(); window.isHidden = true }
        try await Task.sleep(for: .milliseconds(150))
        let input = try XCTUnwrap(findInput(host.view))
        input.selectedRange = NSRange(location: 1, length: 2); session.selectionChanged(input)
        for command in effects {
            session.applyFormatting(command)
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(input.selectedRange, NSRange(location: 1, length: 2))
        XCTAssertTrue(session.hasChanges); XCTAssertTrue(session.formattingRun.isSuperscript)
        XCTAssertTrue(session.undo()); XCTAssertFalse(session.formattingRun.isSuperscript)
        XCTAssertTrue(session.redo()); XCTAssertTrue(session.formattingRun.isSuperscript)
        try await Task.sleep(for: .milliseconds(20))
        session.applyFormatting(.clearCharacterFormatting)
        XCTAssertFalse(session.formattingRun.isStruckThrough); XCTAssertNil(session.formattingRun.backgroundColorRGB)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(session.undo())
        XCTAssertTrue(session.formattingRun.isSuperscript); XCTAssertTrue(session.formattingRun.isStruckThrough)
        XCTAssertEqual(session.formattingRun.backgroundColorRGB, 0xFFC7DE)
        XCTAssertEqual(input.selectedRange, NSRange(location: 1, length: 2))
        input.selectedRange = NSRange(location: 0, length: 4); session.selectionChanged(input)
        XCTAssertFalse(session.formattingRun.isSuperscript); XCTAssertFalse(session.formattingRun.isStruckThrough)
        XCTAssertNil(session.formattingRun.backgroundColorRGB)
        input.selectedRange = NSRange(location: 4, length: 0); session.selectionChanged(input)
        session.applyFormatting(.subscript(true)); session.applyFormatting(.highlight(0xFFFF00))
        input.insertText("추"); input.typingAttributes.removeValue(forKey: .hwpCharacterStyle); input.insertText("가")
        session.applyFormatting(.clearCharacterFormatting)
        input.insertText("끝")
        session.finish()
        let block = try XCTUnwrap(committed)
        XCTAssertEqual(block.text, "가나다라추가끝")
        for position in 4...5 {
            let run = HWPDocumentFormatting.run(at: position, in: block)
            XCTAssertTrue(run.isSubscript); XCTAssertFalse(run.isSuperscript); XCTAssertEqual(run.backgroundColorRGB, 0xFFFF00)
        }
        let last = HWPDocumentFormatting.run(at: 6, in: block)
        XCTAssertFalse(last.isSubscript); XCTAssertNil(last.backgroundColorRGB); XCTAssertEqual(last.fontName, "바탕")
        XCTAssertTrue(HWPDocumentFormatting.matches(try HWPXDocumentPackage.load(from: package.serializedData(applying: [block])).blocks[0], block))
    }

    func testScriptMetricsShrinkGlyphsWithoutChangingStoredPointSize() throws {
        let normal = apply([.size(20)], to: try package(String(repeating: "한글 ", count: 12)).blocks[0])
        let script = apply([.superscript(true)], to: normal)
        let style = HWPDocumentFormatting.run(at: 0, in: script)
        let native = HWPInlineTextAttributes.attributes(run: style, block: script)
        XCTAssertEqual((native[.font] as? UIFont)?.pointSize, 13)
        XCTAssertEqual(native[.baselineOffset] as? Double, 6.4)
        XCTAssertEqual(style.fontSizePoints, 20)
        let ordinaryLines = HWPFlowLayout.measure(normal, width: 100, startY: 0, pageHeight: nil, minimumHeight: 0)
        let scriptLines = HWPFlowLayout.measure(script, width: 100, startY: 0, pageHeight: nil, minimumHeight: 0)
        XCTAssertLessThan(scriptLines.count, ordinaryLines.count)
        XCTAssertEqual(scriptLines.first?.textHeightPoints, 20)

        let large = apply([.size(24)], to: try package("H2O").blocks[0])
        let mixed = apply([.subscript(true)], to: large, range: NSRange(location: 1, length: 1))
        let input = HWPInlineTextView()
        input.textContainerInset = .zero; input.textContainer.lineFragmentPadding = 0
        input.attributedText = HWPInlineTextAttributes.make(block: mixed)
        let needed = input.sizeThatFits(CGSize(width: 400, height: 1000)).height
        let measured = HWPFlowLayout.measure(mixed, width: 400, startY: 0, pageHeight: nil, minimumHeight: 0)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(measured.first).lineHeightPoints, needed, "Subscript must fit the native input viewport")
    }

    func testViewModelCharacterEffectsDirtyUndoRedoAndSave() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        try package("강조할 글자").sourceData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let before = model.blocks
        let highlighted = apply([.highlight(0xFFFF00)], to: before[0])
        model.commitInlineBlock(highlighted)
        XCTAssertTrue(model.hasUnsavedChanges)
        model.undo(); XCTAssertEqual(model.blocks, before)
        model.redo(); XCTAssertTrue(HWPDocumentFormatting.matches(model.blocks[0], highlighted))
        let styled = apply(effects, to: model.blocks[0]); model.commitInlineBlock(styled)
        await model.save(); XCTAssertNil(model.errorDescription); XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertTrue(HWPDocumentFormatting.matches(try HWPXDocumentPackage.load(from: Data(contentsOf: url)).blocks[0], styled))
        model.commitInlineBlock(apply([.clearCharacterFormatting], to: model.blocks[0]))
        model.undo(); XCTAssertTrue(HWPDocumentFormatting.matches(model.blocks[0], styled))
        model.redo(); await model.save(); XCTAssertNil(model.errorDescription)
        XCTAssertTrue(HWPDocumentFormatting.matches(try HWPXDocumentPackage.load(from: Data(contentsOf: url)).blocks[0], model.blocks[0]))
    }

    private func fixture(_ name: String, ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "HWPXViewerFixtures")
        return try Data(contentsOf: XCTUnwrap(url))
    }

    private func findInput(_ view: UIView) -> HWPInlineTextView? {
        if let input = view as? HWPInlineTextView { return input }
        for child in view.subviews { if let input = findInput(child) { return input } }
        return nil
    }
}
