import XCTest
import SwiftUI
import UIKit
@testable import shortcuts_example

@MainActor
final class HWPFindReplaceTests: XCTestCase {
    private func block(_ text: String, id: String = "body", editable: Bool = true,
                       runs: [HWPDocumentTextRun] = [], table: HWPDocumentTableLocation? = nil) -> HWPDocumentBlock {
        HWPDocumentBlock(id: id, sectionPath: "Contents/section0.xml", paragraphIndex: 0,
            text: text, tableLocation: table, isEditable: editable, presentation: .init(textRuns: runs))
    }

    func testFindCountsEveryOccurrenceAndRespectsCaseAndLiteralSpaces() throws {
        let source = [block("한글 한글 Aa aa aA [x]   ")]
        XCTAssertEqual(HWPFindReplace.scan(source, query: "한글").matches.map(\.range.location), [0, 3])
        XCTAssertEqual(HWPFindReplace.scan(source, query: "aa").matches.count, 3)
        XCTAssertEqual(HWPFindReplace.scan(source, query: "aa", matchCase: true).matches.count, 1)
        XCTAssertEqual(HWPFindReplace.scan(source, query: "[x]").matches.count, 1)
        XCTAssertEqual(HWPFindReplace.scan(source, query: "  ").matches.count, 1)
        XCTAssertTrue(HWPFindReplace.scan(source, query: "").matches.isEmpty)
        let navigation = HWPDocumentNavigation()
        navigation.update(blocks: source, layouts: [])
        navigation.query = "한글"
        XCTAssertEqual(navigation.results.count, 2)
        XCTAssertNotEqual(navigation.results[0].id, navigation.results[1].id)
        navigation.moveResult(by: 1)
        XCTAssertEqual(navigation.selectedResult?.match.range.location, 3)
        navigation.moveResult(by: 1)
        XCTAssertEqual(navigation.selectedResult?.match.range.location, 0)
    }

    func testUnicodeRangesNeverSplitEmojiAndCanonicalKoreanMatches() throws {
        let text = "😀 e\u{301} 👨‍👩‍👧‍👦 한글 한글"
        let source = [block(text)]
        XCTAssertEqual(HWPFindReplace.scan(source, query: "한글").matches.count, 2)
        XCTAssertTrue(HWPFindReplace.scan(source, query: "👨").matches.isEmpty)
        let matches = HWPFindReplace.scan(source, query: "é").matches
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].range.length, 2)
        let replaced = try HWPFindReplace.propose(blocks: source, query: "한글", replacement: "문서")
        XCTAssertEqual(replaced.blocks[0].text, "😀 e\u{301} 👨‍👩‍👧‍👦 문서 문서")
    }

    func testSingleReplacementUsesExactOccurrenceAndRejectsStaleSnapshot() throws {
        let source = [block("abc abc abc")]
        let match = HWPFindReplace.scan(source, query: "abc").matches[1]
        XCTAssertEqual(try HWPFindReplace.propose(blocks: source, query: "abc", replacement: "XYZ", selected: match).blocks[0].text, "abc XYZ abc")
        XCTAssertThrowsError(try HWPFindReplace.propose(blocks: [block("changed abc abc")], query: "abc", replacement: "X", selected: match))
    }

    func testAllReplacementDoesNotRepeatInsertedQueryOrOverlapMatches() throws {
        let proposal = try HWPFindReplace.propose(blocks: [block("aaaa")], query: "aa", replacement: "aaa")
        XCTAssertEqual(proposal.blocks[0].text, "aaaaaa")
        XCTAssertEqual(proposal.replacementCount, 2)
        let erased = try HWPFindReplace.propose(blocks: [block("삭제 삭제")], query: "삭제", replacement: "")
        XCTAssertEqual(erased.blocks[0].text, " ")
        let same = try HWPFindReplace.propose(blocks: [block("그대로")], query: "그대로", replacement: "그대로")
        XCTAssertEqual(same.replacementCount, 0)
        XCTAssertTrue(same.changedIDs.isEmpty)
    }

    func testReplacementKeepsUntouchedMixedStylesAndInheritsMatchedStyle() throws {
        let source = block("앞 abc 중 abc 뒤", runs: [
            HWPDocumentTextRun(text: "앞 ", fontSizePoints: 10),
            HWPDocumentTextRun(text: "ab", fontSizePoints: 14, isBold: true),
            HWPDocumentTextRun(text: "c 중 ", fontSizePoints: 16, isItalic: true),
            HWPDocumentTextRun(text: "abc", fontSizePoints: 12, isUnderlined: true),
            HWPDocumentTextRun(text: " 뒤", fontSizePoints: 20)
        ])
        let proposal = try HWPFindReplace.propose(blocks: [source], query: "abc", replacement: "교체")
        let value = proposal.blocks[0]
        XCTAssertEqual(value.text, "앞 교체 중 교체 뒤")
        XCTAssertTrue(HWPDocumentFormatting.run(at: 2, in: value).isBold)
        XCTAssertEqual(HWPDocumentFormatting.run(at: 2, in: value).fontSizePoints, 14)
        XCTAssertTrue(HWPDocumentFormatting.run(at: 5, in: value).isItalic)
        XCTAssertTrue(HWPDocumentFormatting.run(at: 7, in: value).isUnderlined)
        XCTAssertEqual(HWPDocumentFormatting.run(at: value.text.utf16.count - 1, in: value).fontSizePoints, 20)
    }

    func testReadOnlyResultsAreFoundAndSkippedWithoutChangingMetadata() throws {
        let source = [block("찾기", id: "locked", editable: false), block("찾기", id: "cell", table: .init(table: 0, row: 0, column: 0, paragraph: 0))]
        let proposal = try HWPFindReplace.propose(blocks: source, query: "찾기", replacement: "완료")
        XCTAssertEqual(proposal.replacementCount, 1)
        XCTAssertEqual(proposal.skippedCount, 1)
        XCTAssertEqual(proposal.blocks[0], source[0])
        XCTAssertEqual(proposal.blocks[1].tableLocation, source[1].tableLocation)
    }

    func testLimitsAreTransactionalAndNormalizeLineBreaks() throws {
        let source = [block("aa")]
        XCTAssertThrowsError(try HWPFindReplace.propose(blocks: source, query: "a", replacement: String(repeating: "x", count: 60_000)))
        XCTAssertEqual(source[0].text, "aa")
        XCTAssertThrowsError(try HWPFindReplace.propose(blocks: source, query: "a", replacement: "\u{0001}"))
        let limited = HWPFindReplace.scan([block(String(repeating: "a", count: HWPFindReplace.maximumMatches + 1))], query: "a")
        XCTAssertTrue(limited.exceedsLimit)
        XCTAssertThrowsError(try HWPFindReplace.propose(blocks: [block(String(repeating: "a", count: HWPFindReplace.maximumMatches + 1))], query: "a", replacement: "b"))
        XCTAssertEqual(try HWPFindReplace.propose(blocks: source, query: "aa", replacement: "앞\r\n뒤").blocks[0].text, "앞\n뒤")
    }

    func testPageFragmentsAndRepeatedTableHeadersUseOneLogicalMatch() throws {
        let source = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: String(repeating: "한글 찾기 ", count: 1_000)))
        let navigation = HWPDocumentNavigation()
        navigation.update(blocks: source.blocks, layouts: source.pageLayouts)
        navigation.query = "찾기"
        XCTAssertEqual(navigation.results.count, 1_000)
        XCTAssertGreaterThan(navigation.results.last!.pageIndex, 0)
        let selected = navigation.results.last!
        XCTAssertEqual(selected.match.blockID, source.blocks[0].id)
        let proposal = try HWPFindReplace.propose(blocks: source.blocks, query: "찾기", replacement: "발견", selected: selected.match)
        XCTAssertEqual(proposal.replacementCount, 1)
        XCTAssertEqual(proposal.blocks[0].text.components(separatedBy: "발견").count, 2)
        let fixture = try HWP5StructuredDocumentParser.parse(from: fixture("hangul_design_application", ext: "hwp"))
        navigation.update(blocks: fixture.blocks, layouts: fixture.pageLayouts)
        navigation.query = "참가형태"
        XCTAssertEqual(navigation.results.count, HWPFindReplace.scan(fixture.blocks, query: "참가형태").matches.count)
    }

    func testSearchHighlightUsesTheSelectedOccurrenceWithinEachLine() throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "한글 한글 한글"))
        let navigation = HWPDocumentNavigation()
        navigation.update(blocks: package.blocks, layouts: package.pageLayouts)
        navigation.query = "한글"
        navigation.moveResult(by: 1)
        let result = try XCTUnwrap(navigation.selectedResult)
        let block = try XCTUnwrap(navigation.pages[0].bodyBlocks.first)
        let line = try XCTUnwrap(block.lineLayouts.first)
        let context = HWPDocumentSearchContext(result: result, pageIndex: 0)
        XCTAssertEqual(context.range(in: block, line: line), NSRange(location: 3, length: 2))
        let view = HWPMetricLineUIView(frame: CGRect(x: 0, y: 0, width: 200, height: 20))
        view.update(text: line.text, runs: line.textRuns, fallbackSize: 10, alignment: .centered, baselinePoints: 12,
            highlightRange: context.range(in: block, line: line))
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { view.layer.render(in: $0.cgContext) }
        let attachment = XCTAttachment(image: image); attachment.name = "selected-second-search-occurrence"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testRealHWPRoundTripKeepsTextStylesTablesAndOtherStreams() throws {
        let data = try fixture("hangul_design_application", ext: "hwp")
        let original = try HWP5StructuredDocumentParser.parse(from: data)
        let proposal = try HWPFindReplace.propose(blocks: original.blocks, query: "공모전", replacement: "공모대회")
        XCTAssertGreaterThan(proposal.replacementCount, 0)
        let changed = reflow(proposal, before: original.blocks, layouts: original.pageLayouts)
        let saved = try HWP5DocumentRewriter.rewrite(sourceData: data, originalBlocks: original.blocks, editedBlocks: changed)
        let reopened = try HWP5StructuredDocumentParser.parse(from: saved)
        XCTAssertEqual(reopened.blocks.map(\.text), changed.map(\.text))
        XCTAssertEqual(reopened.tableCount, original.tableCount)
        XCTAssertEqual(reopened.tableCellCount, original.tableCellCount)
        for (a, b) in zip(reopened.blocks, changed) { XCTAssertTrue(HWPDocumentFormatting.matches(a, b), a.id) }
        let old = try OLECompoundFile(data: data), new = try OLECompoundFile(data: saved)
        for path in old.streamNames where !path.hasPrefix("bodytext/") && path != "docinfo" && path != "prvtext" {
            XCTAssertEqual(try old.stream(named: path), try new.stream(named: path), path)
        }
    }

    func testRealHWPXRoundTripKeepsAttachmentsAndSupportsDeletingMatches() throws {
        let data = try fixture("mss_voucher", ext: "hwpx")
        let original = try HWPXDocumentPackage.load(from: data)
        let proposal = try HWPFindReplace.propose(blocks: original.blocks, query: "지원", replacement: "")
        XCTAssertGreaterThan(proposal.replacementCount, 0)
        let changed = reflow(proposal, before: original.blocks, layouts: original.pageLayouts)
        let saved = try original.serializedData(applying: changed)
        let reopened = try HWPXDocumentPackage.load(from: saved)
        XCTAssertEqual(reopened.blocks.map(\.text), changed.map(\.text))
        let old = try HWPXEditingArchive(data: data), new = try HWPXEditingArchive(data: saved)
        for path in old.paths where path.hasPrefix("BinData/") { XCTAssertEqual(try old.data(at: path), try new.data(at: path)) }
    }

    func testViewModelReplaceAllIsOneUndoRestoresLayoutAndSaves() async throws {
        let data = try fixture("hangul_design_application", ext: "hwp")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwp")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let before = model.blocks
        let proposal = try model.replaceText(query: "공모전", matchCase: false, replacement: "공모대회")
        XCTAssertGreaterThan(proposal.replacementCount, 0)
        let changed = model.blocks
        model.undo(); XCTAssertEqual(model.blocks, before)
        model.redo(); XCTAssertEqual(model.blocks, changed)
        await model.save()
        XCTAssertNil(model.errorDescription)
        XCTAssertEqual(try HWP5StructuredDocumentParser.parse(from: Data(contentsOf: url)).blocks.map(\.text), changed.map(\.text))
    }

    func testViewModelRejectsStaleMatchWithoutApplyingAnotherUndoEntry() async throws {
        let data = try LegacyHWPXConverter.convert(text: "찾기 찾기")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let match = HWPFindReplace.scan(model.blocks, query: "찾기").matches[1]
        model.editorText = "입력 찾기 찾기"
        XCTAssertThrowsError(try model.replaceText(query: "찾기", matchCase: false, replacement: "변경", selected: match))
        XCTAssertEqual(model.blocks[0].text, "입력 찾기 찾기")
        model.undo(); XCTAssertEqual(model.blocks[0].text, "찾기 찾기")
        XCTAssertFalse(model.canUndo)
    }

    private func reflow(_ proposal: HWPFindReplace.Proposal, before: [HWPDocumentBlock], layouts: [HWPDocumentPageLayout]) -> [HWPDocumentBlock] {
        HWPFlowLayout.reflowingEdits(proposal.blocks, before: before, changedIDs: proposal.changedIDs, layouts: layouts)
    }

    private func fixture(_ name: String, ext: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("HWPXViewerFixtures")
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: ext) ?? root.appendingPathComponent(name + "." + ext)
        return try Data(contentsOf: url)
    }
}
