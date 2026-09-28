import XCTest
import SwiftUI
import ZIPFoundation
@testable import shortcuts_example

@MainActor
final class HWPTableEditingTests: XCTestCase {
    func testGrowingCellUpdatesPeerHeightFollowingRowsAndBody() throws {
        let package = try fixturePackage()
        let before = package.blocks
        let index = try XCTUnwrap(before.firstIndex { $0.text == "입력" })
        let changed = edit(before, index: index, text: String(repeating: "한글 내용 추가\n", count: 8), layouts: package.pageLayouts)
        let members = changed.filter { $0.tableLocation != nil }
        let tracks = HWPTableTrackLayoutSolver.make(blocks: members)
        XCTAssertGreaterThan(tracks.rowHeights[0], 40)
        XCTAssertEqual(tracks.rowHeights[1], 40, accuracy: 0.02)
        let peers = members.filter { $0.tableLocation?.row == 0 }
        XCTAssertEqual(peers[0].tableLocation?.cellHeightPoints, peers[1].tableLocation?.cellHeightPoints)
        XCTAssertGreaterThanOrEqual(changed.last!.lineLayouts[0].verticalPositionPoints, 60 + tracks.rowHeights.reduce(0, +))
        XCTAssertEqual(changed[index].lineLayouts.last?.text, "")
        XCTAssertEqual(changed[index].id, before[index].id)
        XCTAssertEqual(changed.filter { $0.id != before[index].id }.map(\.text), before.filter { $0.id != before[index].id }.map(\.text))
    }

    func testMultipleCellParagraphsReflowWithoutOverlap() throws {
        let package = try fixturePackage(secondParagraph: true)
        let index = try XCTUnwrap(package.blocks.firstIndex { $0.text == "입력" })
        let changed = edit(package.blocks, index: index, text: String(repeating: "첫째\n", count: 5), layouts: package.pageLayouts)
        let second = try XCTUnwrap(changed.first { $0.text == "둘째 문단" })
        let last = try XCTUnwrap(changed[index].lineLayouts.last)
        XCTAssertGreaterThanOrEqual(second.lineLayouts.first!.verticalPositionPoints, last.verticalPositionPoints + last.lineHeightPoints)
    }

    func testVerticalMergeGrowsLastTrackAndPreservesEarlierRows() throws {
        let package = try fixturePackage(merged: true)
        let index = try XCTUnwrap(package.blocks.firstIndex { $0.text == "입력" })
        let changed = edit(package.blocks, index: index, text: String(repeating: "병합 셀\n", count: 10), layouts: package.pageLayouts)
        let tracks = HWPTableTrackLayoutSolver.make(blocks: changed.filter { $0.tableLocation != nil })
        XCTAssertEqual(tracks.rowHeights[0], 40, accuracy: 0.02)
        XCTAssertGreaterThan(tracks.rowHeights[1], 40)
        XCTAssertEqual(changed[index].tableLocation?.rowSpan, 2)
        XCTAssertEqual(changed[index].tableLocation!.cellHeightPoints!, tracks.rowHeights[0] + tracks.rowHeights[1], accuracy: 0.02)
    }

    func testRowPaginationPreservesEditableIDsAndKeepsFollowingBodyBelowTable() throws {
        let package = try fixturePackage()
        let index = try XCTUnwrap(package.blocks.firstIndex { $0.text == "입력" })
        let changed = edit(package.blocks, index: index, text: String(repeating: "입력\n", count: 20), layouts: package.pageLayouts)
        let pages = HWPOriginalCanvasPageBuilder.makePages(blocks: changed, layouts: package.pageLayouts)
        XCTAssertGreaterThan(pages.count, 1)
        for cell in changed where cell.tableLocation != nil {
            XCTAssertTrue(pages.flatMap(\.bodyBlocks).contains { $0.id == cell.id })
        }
        let lastPage = try XCTUnwrap(pages.last)
        let body = try XCTUnwrap(lastPage.bodyBlocks.first { $0.text == "뒤 본문" })
        let tracks = HWPTableTrackLayoutSolver.make(blocks: lastPage.bodyBlocks.filter { $0.tableLocation != nil })
        XCTAssertGreaterThanOrEqual(body.lineLayouts[0].verticalPositionPoints, tracks.size.height)
    }

    func testTallSingleRowContinuesWithoutLosingTextAndRoundTrips() throws {
        let package = try fixturePackage()
        let index = try XCTUnwrap(package.blocks.firstIndex { $0.text == "입력" })
        let text = (0..<80).map { "줄 \($0) 한글" }.joined(separator: "\n")
        let changed = edit(package.blocks, index: index, text: text, layouts: package.pageLayouts)
        let pages = HWPOriginalCanvasPageBuilder.makePages(blocks: changed, layouts: package.pageLayouts)
        XCTAssertGreaterThan(pages.count, 2)
        let fragments = pages.flatMap(\.bodyBlocks).filter { HWPInlineParagraphGeometry.sourceID($0.id) == changed[index].id }
        XCTAssertEqual(fragments.map(\.text).joined(), text)
        for page in pages {
            for cell in page.bodyBlocks where HWPInlineParagraphGeometry.sourceID(cell.id) == changed[index].id {
                XCTAssertLessThanOrEqual(cell.tableLocation!.cellHeightPoints!, 440)
                let context = HWPInlineEditingContext(session: HWPInlineEditingSession(), sources: [changed[index].id: changed[index]])
                XCTAssertNotNil(context.source(for: cell))
            }
        }
        let reopened = try HWPXDocumentPackage.load(from: package.serializedData(applying: changed))
        XCTAssertEqual(HWPOriginalCanvasPageBuilder.makePages(blocks: reopened.blocks, layouts: reopened.pageLayouts).count, pages.count)
        assertRoundTrip(changed, reopened.blocks)
    }

    func testHWPXRoundTripKeepsCellSizesStylesAndRepeatSave() throws {
        let package = try fixturePackage(merged: true, secondParagraph: true)
        let index = try XCTUnwrap(package.blocks.firstIndex { $0.text == "입력" })
        var changed = edit(package.blocks, index: index, text: String(repeating: "한글 😀\n", count: 14), layouts: package.pageLayouts)
        changed[index] = HWPDocumentFormatting.apply(.bold(true), to: changed[index], range: NSRange(location: 0, length: 2))
        let saved = try package.serializedData(applying: changed)
        let reopened = try HWPXDocumentPackage.load(from: saved)
        assertRoundTrip(changed, reopened.blocks)
        XCTAssertEqual(try reopened.serializedData(applying: reopened.blocks), saved)
        let again = edit(reopened.blocks, index: index, text: reopened.blocks[index].text + "이어 입력", layouts: reopened.pageLayouts)
        assertRoundTrip(again, try HWPXDocumentPackage.load(from: reopened.serializedData(applying: again)).blocks)
    }

    func testRealHWPTableGrowthRoundTripsAndPreservesOtherStreams() throws {
        let source = try fixture("hangul_design_application", ext: "hwp")
        let parsed = try HWP5StructuredDocumentParser.parse(from: source)
        let index = try XCTUnwrap(parsed.blocks.firstIndex { $0.paragraphIndex == 18 })
        let changed = edit(parsed.blocks, index: index, text: String(repeating: "제품 설명 추가\n", count: 9), layouts: parsed.pageLayouts)
        XCTAssertGreaterThan(changed[index].tableLocation!.cellHeightPoints!, parsed.blocks[index].tableLocation!.cellHeightPoints!)
        let saved = try HWP5DocumentRewriter.rewrite(sourceData: source, originalBlocks: parsed.blocks, editedBlocks: changed)
        let reopened = try HWP5StructuredDocumentParser.parse(from: saved)
        assertRoundTrip(changed, reopened.blocks)
        let old = try OLECompoundFile(data: source), new = try OLECompoundFile(data: saved)
        for path in old.streamNames where !path.hasPrefix("bodytext/") && path != "docinfo" && path != "prvtext" {
            XCTAssertEqual(try old.stream(named: path), try new.stream(named: path), path)
        }
        XCTAssertEqual(HWPOriginalCanvasPageBuilder.makePages(blocks: changed, layouts: parsed.pageLayouts).count,
            HWPOriginalCanvasPageBuilder.makePages(blocks: reopened.blocks, layouts: reopened.pageLayouts).count)
    }

    func testRealHWPXTableGrowthRoundTripsAndPreservesAssets() throws {
        let source = try fixture("mss_voucher", ext: "hwpx")
        let package = try HWPXDocumentPackage.load(from: source)
        let index = try XCTUnwrap(package.blocks.firstIndex { block in
            HWPTableEditing.supports(block) && !package.blocks.contains { $0.tableLocation?.parent?.table == block.tableLocation?.table }
        })
        let changed = edit(package.blocks, index: index, text: String(repeating: "설명 추가\n", count: 12), layouts: package.pageLayouts)
        let saved = try package.serializedData(applying: changed)
        assertRoundTrip(changed, try HWPXDocumentPackage.load(from: saved).blocks)
        let old = try HWPXEditingArchive(data: source), new = try HWPXEditingArchive(data: saved)
        for path in old.paths where path.hasPrefix("BinData/") { XCTAssertEqual(try old.data(at: path), try new.data(at: path)) }
    }

    func testPreviewKeepsNativeSelectionAndDefersDuringComposition() async throws {
        let package = try fixturePackage()
        let block = try XCTUnwrap(package.blocks.first { $0.text == "입력" })
        let session = HWPInlineEditingSession()
        session.begin(block: block, at: .zero, onSelect: { _ in }, onChange: { _ in }, onCommit: {})
        let token = try XCTUnwrap(session.activation?.token)
        let input = HWPInlineTextView(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        input.attributedText = HWPInlineTextAttributes.make(block: block)
        input.typingAttributes = HWPInlineTextAttributes.typingAttributes(block: block)
        session.attach(input, token: token)
        input.selectedRange = NSRange(location: input.text.utf16.count, length: 0)
        input.insertText(String(repeating: "내용\n", count: 8))
        let selection = input.selectedRange
        session.changed(input.text, token: token)
        try await Task.sleep(for: .milliseconds(250))
        let preview = session.previewing(package.blocks, layouts: package.pageLayouts)
        XCTAssertGreaterThan(preview.first { $0.id == block.id }!.tableLocation!.cellHeightPoints!, block.tableLocation!.cellHeightPoints!)
        XCTAssertEqual(input.selectedRange, selection)
        XCTAssertEqual(session.activation?.token, token)
        input.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0))
        session.changed(input.text, token: token)
        let stable = session.previewBlock
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(session.previewBlock, stable)
        input.unmarkText()
        session.finish(commitChanges: false)
    }

    func testTableGrowthSurvivesBodyStructuralSave() throws {
        let package = try fixturePackage()
        let index = try XCTUnwrap(package.blocks.firstIndex { $0.text == "입력" })
        let changed = edit(package.blocks, index: index, text: String(repeating: "길게\n", count: 10), layouts: package.pageLayouts)
        let body = try XCTUnwrap(changed.last)
        let split = try XCTUnwrap(HWPParagraphEditing.apply(.split(NSRange(location: 1, length: 0)), draft: body, to: changed))
        let saved = try HWPXDocumentPackage.load(from: package.serializedData(applying: split.blocks))
        assertRoundTrip(split.blocks, saved.blocks)
    }

    func testViewModelTableGrowthUndoRedoAndSave() async throws {
        let package = try fixturePackage()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        try package.sourceData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let original = model.blocks
        let cell = try XCTUnwrap(original.first { $0.text == "입력" })
        model.commitInlineBlock(HWPTextRunEditing.replacingText(in: cell, with: String(repeating: "입력\n", count: 12)))
        let changed = model.blocks
        XCTAssertGreaterThan(changed.first { $0.id == cell.id }!.tableLocation!.cellHeightPoints!, cell.tableLocation!.cellHeightPoints!)
        model.undo(); XCTAssertEqual(model.blocks, original)
        model.redo(); XCTAssertEqual(model.blocks, changed)
        await model.save()
        XCTAssertNil(model.errorDescription)
        assertRoundTrip(changed, try HWPXDocumentPackage.load(from: Data(contentsOf: url)).blocks)
    }

    func testFontSizeChangeGrowsCellAndSavesWithoutChangingText() throws {
        let package = try fixturePackage()
        let index = try XCTUnwrap(package.blocks.firstIndex { $0.text == "입력" })
        var changed = package.blocks
        changed[index] = HWPDocumentFormatting.apply(.size(48), to: changed[index], range: NSRange(location: 0, length: changed[index].text.utf16.count))
        changed = HWPFlowLayout.reflowingEdit(changed, before: package.blocks, startingAt: changed[index].id, layouts: package.pageLayouts)
        XCTAssertEqual(changed.map(\.text), package.blocks.map(\.text))
        XCTAssertGreaterThan(changed[index].tableLocation!.cellHeightPoints!, 40)
        assertRoundTrip(changed, try HWPXDocumentPackage.load(from: package.serializedData(applying: changed)).blocks)
    }

    func testViewModelBatchCellGrowthUsesOneUndoAndKeepsBothHeights() async throws {
        let package = try fixturePackage()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        try package.sourceData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let before = model.blocks
        let cells = before.filter { $0.tableLocation?.column == 0 && ($0.tableLocation?.row ?? 99) < 2 }
        try model.applyTableRowEdits(originalBlocks: cells, texts: Dictionary(uniqueKeysWithValues: cells.map { ($0.id, String(repeating: "내용\n", count: 8)) }))
        let changed = model.blocks
        for cell in cells { XCTAssertGreaterThan(changed.first { $0.id == cell.id }!.tableLocation!.cellHeightPoints!, 40) }
        model.undo(); XCTAssertEqual(model.blocks, before)
        model.redo(); XCTAssertEqual(model.blocks, changed)
        await model.save()
        XCTAssertNil(model.errorDescription)
        assertRoundTrip(changed, try HWPXDocumentPackage.load(from: Data(contentsOf: url)).blocks)
    }

    private func edit(_ source: [HWPDocumentBlock], index: Int, text: String, layouts: [HWPDocumentPageLayout]) -> [HWPDocumentBlock] {
        var result = source
        result[index] = HWPTextRunEditing.replacingText(in: source[index], with: text)
        return HWPFlowLayout.reflowingEdit(result, before: source, startingAt: source[index].id, layouts: layouts)
    }

    private func assertRoundTrip(_ expected: [HWPDocumentBlock], _ actual: [HWPDocumentBlock], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(expected.map(\.text), actual.map(\.text), file: file, line: line)
        for (a, b) in zip(expected, actual) {
            XCTAssertTrue(HWPDocumentFormatting.matches(a, b), "Style: \(a.id)", file: file, line: line)
            if let cell = a.tableLocation, let saved = b.tableLocation {
                XCTAssertEqual(cell.cellHeightPoints ?? 0, saved.cellHeightPoints ?? 0, accuracy: 0.02, file: file, line: line)
                XCTAssertEqual(cell.tablePlacement?.heightPoints ?? 0, saved.tablePlacement?.heightPoints ?? 0, accuracy: 0.02, file: file, line: line)
                XCTAssertEqual(cell.rowSpan, saved.rowSpan, file: file, line: line)
                XCTAssertEqual(cell.columnSpan, saved.columnSpan, file: file, line: line)
                XCTAssertEqual(cell.boxStyle, saved.boxStyle, file: file, line: line)
            }
        }
    }

    private func fixture(_ name: String, ext: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("HWPXViewerFixtures")
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: ext) ?? root.appendingPathComponent(name + "." + ext)
        return try Data(contentsOf: url)
    }

    private func fixturePackage(merged: Bool = false, secondParagraph: Bool = false) throws -> HWPXDocumentPackage {
        func paragraph(_ text: String, y: Int = 0, height: Int = 1000) -> String {
            "<hp:p paraPrIDRef=\"0\" styleIDRef=\"0\"><hp:run charPrIDRef=\"0\"><hp:t>\(text)</hp:t></hp:run><hp:linesegarray><hp:lineseg textpos=\"0\" vertpos=\"\(y)\" vertsize=\"\(height)\" textheight=\"1000\" baseline=\"850\" spacing=\"600\" horzsize=\"10000\"/></hp:linesegarray></hp:p>"
        }
        var rows = ""
        for row in 0..<3 {
            rows += "<hp:tr>"
            for column in 0..<2 where !(merged && row == 1 && column == 0) {
                let first = row == 0 && column == 0
                rows += "<hp:tc><hp:subList>" + paragraph(first ? "입력" : "셀 \(row) \(column)")
                    + (first && secondParagraph ? paragraph("둘째 문단", y: 1600) : "")
                    + "</hp:subList><hp:cellAddr rowAddr=\"\(row)\" colAddr=\"\(column)\"/><hp:cellSpan rowSpan=\"\(first && merged ? 2 : 1)\" colSpan=\"1\"/><hp:cellSz width=\"12000\" height=\"\(first && merged ? 8000 : 4000)\"/><hp:cellMargin left=\"200\" right=\"200\" top=\"200\" bottom=\"200\"/></hp:tc>"
            }
            rows += "</hp:tr>"
        }
        let body = "<hp:p paraPrIDRef=\"0\" styleIDRef=\"0\"><hp:run charPrIDRef=\"0\"><hp:secPr><hp:pagePr width=\"30000\" height=\"48000\"><hp:margin left=\"2000\" right=\"2000\" top=\"2000\" bottom=\"2000\" header=\"0\" footer=\"0\"/></hp:pagePr></hp:secPr><hp:tbl pageBreak=\"CELL\"><hp:sz width=\"24000\" height=\"12000\"/><hp:pos treatAsChar=\"1\"/>\(rows)</hp:tbl></hp:run><hp:linesegarray><hp:lineseg vertpos=\"6000\" vertsize=\"12000\" textheight=\"1000\" horzsize=\"24000\"/></hp:linesegarray></hp:p>" + paragraph("뒤 본문", y: 20000)
        let archive = try Archive(accessMode: .create)
        for (path, string) in ["mimetype": "application/hwp+zip", "Contents/header.xml": LegacyHWPXConverter.headerXML.replacingOccurrences(of: "Helvetica", with: "Apple SD Gothic Neo"), "Contents/section0.xml": "<hs:sec xmlns:hs='http://www.hancom.co.kr/hwpml/2011/section' xmlns:hp='http://www.hancom.co.kr/hwpml/2011/paragraph'>\(body)</hs:sec>"] {
            let data = Data(string.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { offset, count in
                data.subdata(in: Int(offset)..<min(Int(offset) + count, data.count))
            }
        }
        return try HWPXDocumentPackage.load(from: XCTUnwrap(archive.data))
    }
}
