import RivoDocumentEngine
import SwiftUI
import UIKit
import XCTest
@testable import shortcuts_example

@MainActor
final class HWPCellFormattingTests: XCTestCase {
    private func decorated(_ cell: HWPDocumentTableLocation) -> HWPCellFormat {
        var style = HWPCellFormat(cell)
        style.setFill(0xDDEBF7); style.vertical = .end
        for side in 0..<4 { style.setBorder(side, line: .init(kind: 1, widthPoints: 0.3 * 72 / 25.4, colorRGB: 0x0066CC)) }
        return style
    }
    private func apply(_ style: HWPCellFormat, to blocks: [HWPDocumentBlock], at index: Int) -> [HWPDocumentBlock] {
        var result = blocks
        result[index] = HWPCellFormatting.apply(style, to: blocks[index])
        return HWPCellFormatting.propagating(result[index], from: blocks[index], in: result)
    }

    func testCellStyleAppliesToEveryParagraphButKeepsOtherCellsAndGeometry() throws {
        let source = try smallPackage().blocks
        let index = try XCTUnwrap(source.firstIndex { $0.tableLocation != nil })
        let styled = apply(decorated(source[index].tableLocation!), to: source, at: index)
        let members = source.indices.filter { HWPCellFormatting.sameCell(source[$0], source[index]) }
        XCTAssertEqual(members.count, 2)
        for i in source.indices {
            XCTAssertEqual(styled[i].text, source[i].text)
            XCTAssertEqual(styled[i].lineLayouts, source[i].lineLayouts)
            XCTAssertEqual(styled[i].tableLocation?.cellHeightPoints, source[i].tableLocation?.cellHeightPoints)
            if members.contains(i) {
                XCTAssertFalse(HWPDocumentFormatting.matches(styled[i], source[i]))
                XCTAssertEqual(styled[i].tableLocation?.cellVerticalAlignment, .end)
                XCTAssertEqual(styled[i].tableLocation?.boxStyle?.backgroundColorRGB, 0xDDEBF7)
            } else { XCTAssertEqual(styled[i], source[i]) }
        }
        XCTAssertEqual(HWPCellFormatting.apply(decorated(source[index].tableLocation!), to: source[0]), source[0])
    }

    func testCellFillKeepsExplicitCharacterHighlightAndDefaultTextTransparent() throws {
        let source = try smallPackage()
        let index = try XCTUnwrap(source.blocks.firstIndex { $0.tableLocation != nil })
        XCTAssertTrue(HWPDocumentFormatting.runs(in: source.blocks[index]).allSatisfy { $0.backgroundColorRGB == nil })
        var blocks = source.blocks
        blocks[index] = HWPDocumentFormatting.apply(.highlight(0xFFFFFF), to: blocks[index], range: NSRange(location: 0, length: 1))
        blocks = apply(decorated(blocks[index].tableLocation!), to: blocks, at: index)
        let saved = try HWPXDocumentPackage.load(from: source.serializedData(applying: blocks))
        XCTAssertEqual(HWPDocumentFormatting.run(at: 0, in: saved.blocks[index]).backgroundColorRGB, 0xFFFFFF)
        XCTAssertNil(HWPDocumentFormatting.run(at: 1, in: saved.blocks[index]).backgroundColorRGB)
        XCTAssertEqual(saved.blocks[index].tableLocation?.boxStyle?.backgroundColorRGB, 0xDDEBF7)
    }

    func testHWPXSharedDefinitionsSurviveFillBordersAlignmentAndClear() throws {
        var package = try smallPackage()
        let index = try XCTUnwrap(package.blocks.firstIndex { $0.tableLocation != nil })
        var blocks = apply(decorated(package.blocks[index].tableLocation!), to: package.blocks, at: index)
        let original = package.blocks
        let archive = try HWPXEditingArchive(data: package.sourceData)
        let oldHeader = String(decoding: try archive.data(at: "Contents/header.xml"), as: UTF8.self)
        let before = try HWPFormattingXML.dictionary(oldHeader, name: "borderfill")
        let output = try package.serializedData(applying: blocks)
        package = try HWPXDocumentPackage.load(from: output)
        let newHeader = String(decoding: try HWPXEditingArchive(data: output).data(at: "Contents/header.xml"), as: UTF8.self)
        let after = try HWPFormattingXML.dictionary(newHeader, name: "borderfill")
        for (id, xml) in before { XCTAssertEqual(after[id], xml) }
        XCTAssertEqual(after.count, before.count + 1, "Paragraphs in a cell share one new border definition")
        for i in blocks.indices {
            XCTAssertTrue(HWPDocumentFormatting.matches(package.blocks[i], blocks[i]))
            if !HWPCellFormatting.sameCell(blocks[i], blocks[index]) { XCTAssertEqual(package.blocks[i], original[i]) }
        }
        var clear = HWPCellFormat(package.blocks[index].tableLocation!)
        clear.setFill(nil); clear.vertical = .start
        for side in 0..<4 { clear.setBorder(side, line: .init()) }
        blocks = apply(clear, to: package.blocks, at: index)
        let saved = try HWPXDocumentPackage.load(from: package.serializedData(applying: blocks))
        XCTAssertTrue(HWPCellFormatting.matches(saved.blocks[index], blocks[index]))
        XCTAssertNil(saved.blocks[index].tableLocation?.boxStyle?.backgroundColorRGB)
        XCTAssertNil(saved.blocks[index].tableLocation?.boxStyle?.firstVisibleBorder)
    }

    func testAlignmentOnlyDoesNotCloneBorderDefinitions() throws {
        let source = try smallPackage()
        let index = try XCTUnwrap(source.blocks.firstIndex { $0.tableLocation != nil })
        var style = HWPCellFormat(source.blocks[index].tableLocation!); style.vertical = .center
        let blocks = apply(style, to: source.blocks, at: index)
        let data = try source.serializedData(applying: blocks)
        XCTAssertEqual(try HWPXEditingArchive(data: source.sourceData).data(at: "Contents/header.xml"),
            try HWPXEditingArchive(data: data).data(at: "Contents/header.xml"))
        XCTAssertEqual(try HWPXDocumentPackage.load(from: data).blocks[index].tableLocation?.cellVerticalAlignment, .center)
    }

    func testRealHWPCellStylesRoundTripAndKeepOtherRecordsAndStreams() throws {
        var data = try fixture("hangul_design_application", ext: "hwp")
        var source = try HWP5StructuredDocumentParser.parse(from: data)
        let index = try XCTUnwrap(source.blocks.firstIndex { HWPCellFormatting.supports($0) && !$0.text.isEmpty })
        for pass in 0..<3 {
            var style = decorated(source.blocks[index].tableLocation!)
            if pass == 1 { style.vertical = .center; style.setBorder(2, line: .init()) }
            if pass == 2 {
                style.setFill(nil); style.vertical = .start
                for side in 0..<4 { style.setBorder(side, line: .init()) }
            }
            let blocks = apply(style, to: source.blocks, at: index)
            let saved = try HWP5DocumentRewriter.rewrite(sourceData: data, originalBlocks: source.blocks, editedBlocks: blocks)
            let reopened = try HWP5StructuredDocumentParser.parse(from: saved)
            for i in blocks.indices {
                XCTAssertTrue(HWPDocumentFormatting.matches(reopened.blocks[i], blocks[i]), "Paragraph \(i)")
                if !HWPCellFormatting.sameCell(blocks[i], blocks[index]) { XCTAssertEqual(reopened.blocks[i], source.blocks[i]) }
            }
            let old = try OLECompoundFile(data: data), new = try OLECompoundFile(data: saved)
            for path in old.streamNames where path != "docinfo" && !path.hasPrefix("bodytext/") {
                XCTAssertEqual(try old.stream(named: path), try new.stream(named: path), path)
            }
            data = saved; source = reopened
        }
    }

    func testOfficialHWPXCellFormattingKeepsImagesAndOtherCells() throws {
        let data = try fixture("mss_voucher", ext: "hwpx")
        let source = try HWPXDocumentPackage.load(from: data)
        let index = try XCTUnwrap(source.blocks.firstIndex { HWPCellFormatting.supports($0) && !$0.text.isEmpty })
        let blocks = apply(decorated(source.blocks[index].tableLocation!), to: source.blocks, at: index)
        let saved = try source.serializedData(applying: blocks)
        let reopened = try HWPXDocumentPackage.load(from: saved)
        for i in blocks.indices {
            XCTAssertTrue(HWPCellFormatting.matches(reopened.blocks[i], blocks[i]))
            if !HWPCellFormatting.sameCell(blocks[i], blocks[index]) { XCTAssertEqual(reopened.blocks[i], source.blocks[i]) }
        }
        let old = try HWPXEditingArchive(data: data), new = try HWPXEditingArchive(data: saved)
        for path in old.paths where path.hasPrefix("BinData/") { XCTAssertEqual(try old.data(at: path), try new.data(at: path)) }
    }

    func testCellAndCharacterFormattingAndTextCanSaveTogetherInBothFormats() throws {
        let hwpx = try smallPackage()
        let hwpData = try fixture("hangul_design_application", ext: "hwp")
        let hwp = try HWP5StructuredDocumentParser.parse(from: hwpData)
        for source in [hwpx.blocks, hwp.blocks] {
            let index = try XCTUnwrap(source.firstIndex { HWPTableEditing.supports($0) })
            var blocks = apply(decorated(source[index].tableLocation!), to: source, at: index)
            blocks[index] = HWPTextRunEditing.replacingText(in: blocks[index], with: "셀 서식과 글자")
            blocks[index] = HWPDocumentFormatting.apply(.bold(true), to: blocks[index], range: NSRange(location: 0, length: 2))
            let saved: [HWPDocumentBlock]
            if source == hwpx.blocks { saved = try HWPXDocumentPackage.load(from: hwpx.serializedData(applying: blocks)).blocks }
            else { saved = try HWP5StructuredDocumentParser.parse(from: HWP5DocumentRewriter.rewrite(sourceData: hwpData, originalBlocks: source, editedBlocks: blocks)).blocks }
            XCTAssertTrue(HWPDocumentFormatting.matches(saved[index], blocks[index]))
        }
    }

    func testRejectsConflictingStylesWithinOneCell() throws {
        let source = try smallPackage()
        let index = try XCTUnwrap(source.blocks.firstIndex { $0.tableLocation != nil })
        var blocks = source.blocks
        blocks[index] = HWPCellFormatting.apply(decorated(blocks[index].tableLocation!), to: blocks[index])
        XCTAssertThrowsError(try source.serializedData(applying: blocks)) { XCTAssertEqual($0 as? HWPDocumentEditingError, .staleDocument) }
    }

    func testMergedCellFormattingKeepsSpansAndSurvivesRowGrowth() throws {
        var table = Self.tableXML
        let cells = try HWPFormattingXML.elements(table, name: "tc")
        table = (table as NSString).replacingCharacters(in: cells[2].range, with: "")
        let merged = cells[0].xml.replacingOccurrences(of: "rowSpan=\"1\"", with: "rowSpan=\"2\"")
            .replacingOccurrences(of: "height=\"9000\"", with: "height=\"18000\"")
        table = (table as NSString).replacingCharacters(in: cells[0].range, with: merged)
        let source = try smallPackage(table: table)
        let index = try XCTUnwrap(source.blocks.firstIndex { $0.tableLocation?.rowSpan == 2 })
        var blocks = apply(decorated(source.blocks[index].tableLocation!), to: source.blocks, at: index)
        let beforeGrowth = blocks
        blocks[index] = HWPTextRunEditing.replacingText(in: blocks[index], with: String(repeating: "병합 셀 내용\n", count: 18))
        blocks = HWPFlowLayout.reflowingEdit(blocks, before: beforeGrowth, startingAt: blocks[index].id, layouts: source.pageLayouts)
        XCTAssertGreaterThan(try XCTUnwrap(blocks[index].tableLocation?.cellHeightPoints), 180)
        let saved = try HWPXDocumentPackage.load(from: source.serializedData(applying: blocks))
        XCTAssertEqual(saved.blocks[index].tableLocation?.rowSpan, 2)
        XCTAssertEqual(saved.blocks[index].tableLocation?.columnSpan, 1)
        XCTAssertEqual(saved.blocks[index].tableLocation?.cellHeightPoints, blocks[index].tableLocation?.cellHeightPoints)
        XCTAssertEqual(saved.blocks.map(\.text), blocks.map(\.text))
        XCTAssertTrue(zip(saved.blocks, blocks).allSatisfy { HWPCellFormatting.matches($0, $1) })
    }

    func testCellFormattingSurvivesBodyParagraphInsertionInBothFormats() throws {
        let hwpx = try smallPackage()
        let hwpData = try fixture("hangul_design_application", ext: "hwp")
        let hwp = try HWP5StructuredDocumentParser.parse(from: hwpData)
        for source in [hwpx.blocks, hwp.blocks] {
            let index = try XCTUnwrap(source.firstIndex { HWPCellFormatting.supports($0) })
            let blocks = apply(decorated(source[index].tableLocation!), to: source, at: index)
            let body = try XCTUnwrap(blocks.first { HWPParagraphEditing.supports($0) && $0.text.count > 2 })
            let split = try XCTUnwrap(HWPParagraphEditing.apply(.split(NSRange(location: 1, length: 0)), draft: body, to: blocks))
            let saved: [HWPDocumentBlock]
            if source == hwpx.blocks { saved = try HWPXDocumentPackage.load(from: hwpx.serializedData(applying: split.blocks)).blocks }
            else { saved = try HWP5StructuredDocumentParser.parse(from: HWP5DocumentRewriter.rewrite(sourceData: hwpData, originalBlocks: source, editedBlocks: split.blocks)).blocks }
            XCTAssertEqual(saved.map(\.text), split.blocks.map(\.text))
            XCTAssertTrue(zip(saved, split.blocks).allSatisfy { HWPCellFormatting.matches($0, $1) })
        }
    }

    func testNativeCellFormatUndoKeepsSelectionAndPreviewsAllCellParagraphs() async throws {
        let source = try smallPackage()
        let index = try XCTUnwrap(source.blocks.firstIndex { $0.tableLocation != nil })
        let block = source.blocks[index], editor = HWPInlineEditingSession()
        var committed: HWPDocumentBlock?
        editor.begin(block: block, at: .zero, onSelect: { _ in }, onChange: { _ in }, onCommit: {}, onCommitBlock: { committed = $0 })
        let input = HWPInlineTextView()
        input.attributedText = HWPInlineTextAttributes.make(block: block)
        input.selectedRange = NSRange(location: 0, length: 2)
        editor.attach(input, token: try XCTUnwrap(editor.activation?.token))
        editor.applyFormatting(.cell(decorated(block.tableLocation!)))
        XCTAssertTrue(editor.hasChanges); XCTAssertEqual(input.selectedRange, NSRange(location: 0, length: 2))
        try await Task.sleep(for: .milliseconds(220))
        let preview = editor.previewing(source.blocks, layouts: source.pageLayouts)
        for member in preview where HWPCellFormatting.sameCell(member, block) {
            XCTAssertEqual(member.tableLocation?.boxStyle?.backgroundColorRGB, 0xDDEBF7)
            XCTAssertEqual(member.tableLocation?.cellVerticalAlignment, .end)
        }
        XCTAssertTrue(editor.undo()); XCTAssertEqual(editor.cellLocation, block.tableLocation)
        XCTAssertFalse(editor.hasChanges)
        XCTAssertTrue(editor.redo()); XCTAssertEqual(editor.cellLocation?.cellVerticalAlignment, .end)
        editor.finish()
        XCTAssertEqual(try XCTUnwrap(committed).tableLocation?.boxStyle?.backgroundColorRGB, 0xDDEBF7)
    }

    func testViewModelCellStyleUndoRedoAndSaveAllParagraphs() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        try smallPackage().sourceData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url); await model.load()
        let before = model.blocks
        let index = try XCTUnwrap(before.firstIndex { $0.tableLocation != nil })
        model.commitInlineBlock(HWPCellFormatting.apply(decorated(before[index].tableLocation!), to: before[index]))
        XCTAssertTrue(model.hasUnsavedChanges)
        for block in model.blocks where HWPCellFormatting.sameCell(block, before[index]) {
            XCTAssertEqual(block.tableLocation?.cellVerticalAlignment, .end)
        }
        model.undo(); XCTAssertEqual(model.blocks, before)
        model.redo(); await model.save(); XCTAssertNil(model.errorDescription); XCTAssertFalse(model.hasUnsavedChanges)
        let reopened = try HWPXDocumentPackage.load(from: Data(contentsOf: url))
        XCTAssertTrue(zip(reopened.blocks, model.blocks).allSatisfy { HWPDocumentFormatting.matches($0, $1) })
    }

    private func smallPackage(table: String? = nil) throws -> HWPXDocumentPackage {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "\n표 뒤"))
        let section = package.sections[0]
        let first = try XCTUnwrap(HWPFormattingXML.elements(section.xml, name: "p").first)
        let paragraph = first.xml.replacingOccurrences(of: "</hp:run>", with: (table ?? Self.tableXML) + "</hp:run>")
        let xml = (section.xml as NSString).replacingCharacters(in: first.range, with: paragraph)
        let data = try HWPXEditingArchive(data: package.sourceData).repack(replacing: [section.path: Data(xml.utf8)])
        return try HWPXDocumentPackage.load(from: data)
    }

    static var tableXML: String {
        let rows = (0..<2).map { row in
            let cells = (0..<2).map { column in
                let texts = row == 0 && column == 0 ? ["첫 문단", "둘째 문단"] : ["다른 셀"]
                let paragraphs = texts.enumerated().map { i, text in
                    "<hp:p id=\"\(10 + row * 10 + column * 2 + i)\" paraPrIDRef=\"0\" styleIDRef=\"0\"><hp:run charPrIDRef=\"0\"><hp:t>\(text)</hp:t></hp:run></hp:p>"
                }.joined()
                return "<hp:tc borderFillIDRef=\"0\" hasMargin=\"1\"><hp:subList vertAlign=\"TOP\">\(paragraphs)</hp:subList><hp:cellAddr colAddr=\"\(column)\" rowAddr=\"\(row)\"/><hp:cellSpan colSpan=\"1\" rowSpan=\"1\"/><hp:cellSz width=\"12000\" height=\"9000\"/><hp:cellMargin left=\"400\" right=\"400\" top=\"400\" bottom=\"400\"/></hp:tc>"
            }.joined()
            return "<hp:tr>\(cells)</hp:tr>"
        }.joined()
        return "<hp:tbl id=\"9\" rowCnt=\"2\" colCnt=\"2\" borderFillIDRef=\"0\" pageBreak=\"CELL\"><hp:sz width=\"24000\" height=\"18000\"/><hp:pos treatAsChar=\"1\"/>\(rows)</hp:tbl>"
    }

    private func fixture(_ name: String, ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: name, withExtension: ext) ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "HWPXViewerFixtures")
        return try Data(contentsOf: XCTUnwrap(url))
    }
}
