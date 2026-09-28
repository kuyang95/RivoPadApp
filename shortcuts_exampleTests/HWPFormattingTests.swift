import SwiftUI
import UIKit
import XCTest
import ZIPFoundation
@testable import shortcuts_example

@MainActor
final class HWPFormattingTests: XCTestCase {
    private func fixture(_ name: String, ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "HWPXViewerFixtures")
        return try Data(contentsOf: XCTUnwrap(url))
    }

    private func format(_ block: HWPDocumentBlock) -> HWPDocumentBlock {
        var result = block
        let selection = NSRange(location: 0, length: min(2, block.text.utf16.count))
        result = HWPDocumentFormatting.apply(.bold(true), to: result, range: selection)
        result = HWPDocumentFormatting.apply(.italic(true), to: result, range: selection)
        result = HWPDocumentFormatting.apply(.underline(true), to: result, range: selection)
        result = HWPDocumentFormatting.apply(.color(0xCC1234), to: result, range: selection)
        result = HWPDocumentFormatting.apply(.font("Arial"), to: result, range: selection)
        result = HWPDocumentFormatting.apply(.size(18), to: result, range: selection)
        result = HWPDocumentFormatting.apply(.alignment(.centered), to: result, range: selection)
        return HWPDocumentFormatting.apply(.paragraph(left: 10, right: 8, indent: 3, before: 4, after: 6, linePercent: 180),
            to: result, range: selection)
    }

    func testRangeFormattingPreservesUnselectedKoreanEmojiAndOtherStyles() throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "앞 한글 👨‍👩‍👧‍👦 뒤"))
        let source = package.blocks[0]
        let range = (source.text as NSString).range(of: "한글 👨‍👩‍👧‍👦")
        let result = HWPDocumentFormatting.apply(.bold(true), to: source, range: range)
        XCTAssertEqual(result.text, source.text)
        XCTAssertTrue(HWPDocumentFormatting.run(at: range.location, in: result).isBold)
        XCTAssertFalse(HWPDocumentFormatting.run(at: 0, in: result).isBold)
        XCTAssertFalse(HWPDocumentFormatting.run(at: source.text.utf16.count - 1, in: result).isBold)
        XCTAssertEqual(HWPDocumentFormatting.apply(.size(22), to: source,
            range: NSRange(location: source.text.utf16.count + 1, length: 1)), source)
    }

    func testHWPXCharacterAndParagraphFormattingSurvivesSaveAndSecondEdit() throws {
        var package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "한글 문단 ABC\n그대로 둘 문단"))
        let untouched = package.blocks[1]
        var blocks = package.blocks
        blocks[0] = format(blocks[0])
        var output = try package.serializedData(applying: blocks)
        package = try HWPXDocumentPackage.load(from: output)
        XCTAssertTrue(HWPDocumentFormatting.matches(package.blocks[0], blocks[0]))
        XCTAssertEqual(package.blocks[1], untouched)
        blocks = package.blocks
        blocks[0] = HWPTextRunEditing.replacingText(in: blocks[0], with: "한글 수정 ABC\t값\n새 줄")
        blocks[0] = HWPDocumentFormatting.apply(.color(0x008040), to: blocks[0], range: NSRange(location: 0, length: 2))
        output = try package.serializedData(applying: blocks)
        let reopened = try HWPXDocumentPackage.load(from: output)
        XCTAssertTrue(HWPDocumentFormatting.matches(reopened.blocks[0], blocks[0]))
        XCTAssertEqual(reopened.blocks[1], untouched)
    }

    func testOfficialHWPXTableCellFormattingPreservesOtherCellsAndAssets() throws {
        let source = try fixture("mss_voucher", ext: "hwpx")
        let package = try HWPXDocumentPackage.load(from: source)
        let index = try XCTUnwrap(package.blocks.firstIndex { $0.isEditable && $0.tableLocation != nil && $0.text.count > 4 })
        var blocks = package.blocks
        blocks[index] = format(blocks[index])
        let output = try package.serializedData(applying: blocks)
        let reopened = try HWPXDocumentPackage.load(from: output)
        XCTAssertTrue(HWPDocumentFormatting.matches(reopened.blocks[index], blocks[index]))
        for i in blocks.indices where i != index { XCTAssertEqual(reopened.blocks[i], package.blocks[i], "Unselected block \(i)") }
        let beforeArchive = try Archive(data: source, accessMode: .read)
        let afterArchive = try Archive(data: output, accessMode: .read)
        var headerData = Data()
        _ = try afterArchive.extract(XCTUnwrap(afterArchive["Contents/header.xml"])) { headerData.append($0) }
        let styles = try HWPFormattingXML.elements(String(decoding: headerData, as: UTF8.self), name: "parapr")
        let paragraph = try XCTUnwrap(styles.last).xml
        let margins = try HWPFormattingXML.elements(paragraph, name: "margin")
        XCTAssertEqual(margins.count, 2, "Both the unit-specific branch and fallback must be changed")
        for margin in margins {
            let left = try XCTUnwrap(HWPFormattingXML.elements(margin.xml, name: "left").first).xml
            XCTAssertEqual(try HWPFormattingXML.prefix(left), "hc:")
            XCTAssertEqual(try HWPFormattingXML.attribute(left, "value"), "1000")
        }
        for spacing in try HWPFormattingXML.elements(paragraph, name: "linespacing") {
            XCTAssertEqual(try HWPFormattingXML.attribute(spacing.xml, "value"), "180")
        }
        for entry in beforeArchive where entry.path.hasPrefix("BinData/") {
            var old = Data(), new = Data()
            _ = try beforeArchive.extract(entry) { old.append($0) }
            _ = try afterArchive.extract(XCTUnwrap(afterArchive[entry.path])) { new.append($0) }
            XCTAssertEqual(old, new, entry.path)
        }
    }

    func testHWPFormattingSurvivesSaveWithoutChangingOtherParagraphsOrStreams() throws {
        let source = try fixture("hangul_design_application", ext: "hwp")
        let original = try HWP5StructuredDocumentParser.parse(from: source)
        let index = try XCTUnwrap(original.blocks.firstIndex { $0.isEditable && $0.text.count > 4 })
        var blocks = original.blocks
        blocks[index] = format(blocks[index])
        let output = try HWP5DocumentRewriter.rewrite(sourceData: source, originalBlocks: original.blocks, editedBlocks: blocks)
        let saved = try HWP5StructuredDocumentParser.parse(from: output)
        XCTAssertTrue(HWPDocumentFormatting.matches(saved.blocks[index], blocks[index]))
        for i in blocks.indices where i != index { XCTAssertEqual(saved.blocks[i], original.blocks[i], "Unselected paragraph \(i)") }
        let before = try OLECompoundFile(data: source), after = try OLECompoundFile(data: output)
        for name in before.streamNames where name != "docinfo" && !name.hasPrefix("bodytext/") {
            XCTAssertEqual(try before.stream(named: name), try after.stream(named: name), name)
        }
        var second = saved.blocks
        second[index] = HWPTextRunEditing.replacingText(in: second[index], with: second[index].text + " 추가")
        let twice = try HWP5DocumentRewriter.rewrite(sourceData: output, originalBlocks: saved.blocks, editedBlocks: second)
        XCTAssertTrue(HWPDocumentFormatting.matches(try HWP5StructuredDocumentParser.parse(from: twice).blocks[index], second[index]))
    }

    func testEmptyHWPAndHWPXRetainTypingStyleAfterSaveAndNewInput() throws {
        let hwp = try fixture("hangul_design_application", ext: "hwp")
        let parsed = try HWP5StructuredDocumentParser.parse(from: hwp)
        let index = try XCTUnwrap(parsed.blocks.firstIndex { $0.isEditable && $0.text.isEmpty })
        var blocks = parsed.blocks
        blocks[index] = format(blocks[index])
        let savedHWP = try HWP5DocumentRewriter.rewrite(sourceData: hwp, originalBlocks: parsed.blocks, editedBlocks: blocks)
        let reloaded = try HWP5StructuredDocumentParser.parse(from: savedHWP)
        XCTAssertTrue(HWPDocumentFormatting.matches(reloaded.blocks[index], blocks[index]))
        blocks = reloaded.blocks
        blocks[index] = HWPTextRunEditing.replacingText(in: blocks[index], with: "새 입력")
        let filled = try HWP5DocumentRewriter.rewrite(sourceData: savedHWP, originalBlocks: reloaded.blocks, editedBlocks: blocks)
        XCTAssertTrue(HWPDocumentFormatting.matches(try HWP5StructuredDocumentParser.parse(from: filled).blocks[index], blocks[index]))

        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: ""))
        let edited = format(package.blocks[0])
        let saved = try HWPXDocumentPackage.load(from: package.serializedData(applying: [edited]))
        XCTAssertTrue(HWPDocumentFormatting.matches(saved.blocks[0], edited))
        let text = HWPTextRunEditing.replacingText(in: saved.blocks[0], with: "다음 입력")
        let result = try HWPXDocumentPackage.load(from: saved.serializedData(applying: [text]))
        XCTAssertTrue(HWPDocumentFormatting.matches(result.blocks[0], text))
    }

    func testNativeSelectionFormattingUndoAndFutureTypingStyle() async throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "가나다라"))
        let source = package.blocks[0]
        let session = HWPInlineEditingSession()
        var committed: HWPDocumentBlock?
        session.begin(block: source, at: .zero, onSelect: { _ in }, onChange: { _ in }, onCommit: {}, onCommitBlock: { committed = $0 })
        let host = UIHostingController(rootView: VStack(spacing: 0) {
            HWPFormattingToolbar(editor: session, documentFonts: ["Arial"])
            HWPInlineTextEditor(activation: session.activation!, session: session).frame(height: 200)
        }.frame(width: 800))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.layoutIfNeeded()
        defer { session.finish(); window.isHidden = true }
        try await Task.sleep(for: .milliseconds(150))
        let input = try XCTUnwrap(findInput(host.view))
        input.selectedRange = NSRange(location: 1, length: 2)
        session.selectionChanged(input)
        session.applyFormatting(.bold(true))
        XCTAssertEqual(input.selectedRange, NSRange(location: 1, length: 2))
        XCTAssertTrue(session.formattingRun.isBold)
        // Separate native undo events, as distinct toolbar taps do.
        try await Task.sleep(for: .milliseconds(20))
        session.applyFormatting(.paragraph(left: 12, right: 6, indent: 3, before: 4, after: 5, linePercent: 180))
        let nativeStyle = try XCTUnwrap(input.attributedText.attribute(.paragraphStyle, at: 1, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(nativeStyle.headIndent, 12)
        XCTAssertEqual(nativeStyle.firstLineHeadIndent, 15)
        XCTAssertEqual(nativeStyle.tailIndent, -6)
        XCTAssertGreaterThan(nativeStyle.lineSpacing, 0)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(session.undo())
        XCTAssertTrue(session.undo())
        XCTAssertFalse(session.formattingRun.isBold)
        XCTAssertTrue(session.redo())
        XCTAssertTrue(session.formattingRun.isBold)
        input.selectedRange = NSRange(location: 4, length: 0)
        session.selectionChanged(input)
        session.applyFormatting(.color(0x0066CC))
        input.insertText("추")
        // Real keyboard events omit custom metadata in the next typing attrs.
        input.typingAttributes.removeValue(forKey: .hwpCharacterStyle)
        input.insertText("가")
        session.finish()
        let block = try XCTUnwrap(committed)
        XCTAssertEqual(block.text, "가나다라추가")
        XCTAssertFalse(HWPDocumentFormatting.run(at: 0, in: block).isBold)
        XCTAssertTrue(HWPDocumentFormatting.run(at: 1, in: block).isBold)
        XCTAssertEqual(HWPDocumentFormatting.run(at: 4, in: block).textColorRGB, 0x0066CC)
        XCTAssertEqual(HWPDocumentFormatting.run(at: 5, in: block).textColorRGB, 0x0066CC)
        XCTAssertTrue(HWPDocumentFormatting.matches(try HWPXDocumentPackage.load(from: package.serializedData(applying: [block])).blocks[0], block))
    }

    func testViewModelFormattingOnlyUndoRedoAndFileSave() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        try LegacyHWPXConverter.convert(text: "서식 변경").write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let original = try XCTUnwrap(model.blocks.first)
        let formatted = format(original)
        model.commitInlineBlock(formatted)
        let laidOut = model.blocks[0]
        XCTAssertTrue(HWPDocumentFormatting.matches(laidOut, formatted))
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertTrue(model.canUndo)
        model.undo()
        XCTAssertEqual(model.blocks[0], original)
        model.redo()
        XCTAssertEqual(model.blocks[0], laidOut)
        await model.save()
        XCTAssertNil(model.errorDescription)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertTrue(HWPDocumentFormatting.matches(try HWPXDocumentPackage.load(from: Data(contentsOf: url)).blocks[0], formatted))
    }

    private func findInput(_ view: UIView) -> HWPInlineTextView? {
        if let input = view as? HWPInlineTextView { return input }
        for child in view.subviews { if let input = findInput(child) { return input } }
        return nil
    }
}
