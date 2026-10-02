import RivoDocumentEngine
import XCTest
@testable import shortcuts_example

@MainActor final class HWPTableInsertionTests: XCTestCase {
    func testInvalidDimensionsCaretSelectionAndStaleTextAreRejected() async throws {
        let source = try plain("한글 😀 뒤"), selection = try XCTUnwrap(HWPTableInsertion.selection(blocks: source.blocks, selectedID: source.blocks[0].id,
            range: .init(location: 0, length: 0), layouts: source.layouts))
        for (rows, cols) in [(0, 1), (1, 0), (-1, 2), (21, 2), (2, 21), (Int.max, 1)] {
            let request = HWPTableInsertion.Request(selection: selection, rows: rows, columns: cols)
            XCTAssertFalse(request.isValid)
            do { _ = try await HWPTableInsertion.applying(request, source: source, drafts: source.blocks); XCTFail("Invalid dimensions") } catch {}
        }
        for range in [NSRange(location: 4, length: 0), .init(location: 0, length: 1), .init(location: -1, length: 0), .init(location: 99, length: 0)] {
            XCTAssertNil(HWPTableInsertion.selection(blocks: source.blocks, selectedID: source.blocks[0].id, range: range, layouts: source.layouts))
        }
        var drafts = source.blocks; drafts[0] = HWPTextRunEditing.replacingText(in: drafts[0], with: "바뀜")
        do { _ = try await HWPTableInsertion.applying(.init(selection: selection, rows: 2, columns: 2), source: source, drafts: drafts); XCTFail("Stale selection") } catch {}
        XCTAssertNil(HWPTableInsertion.selection(blocks: source.blocks, selectedID: nil, range: .init(location: 0, length: 0), layouts: source.layouts))
    }
    func testEmptyDocumentCreatesEditableGridWithBordersAndBodyAfterTable() async throws {
        for (rows, cols) in [(1, 1), (3, 2), (2, 20), (20, 20)] {
            let source = try plain("")
            let selection = try XCTUnwrap(HWPTableInsertion.selection(blocks: source.blocks, selectedID: nil, range: .init(location: 0, length: 0), layouts: source.layouts))
            let result = try await HWPTableInsertion.applying(.init(selection: selection, rows: rows, columns: cols), source: source, drafts: source.blocks)
            let cells = result.document.blocks.filter { $0.tableLocation != nil }
            XCTAssertEqual(cells.count, rows * cols); XCTAssertEqual(result.focusedID, cells[0].id)
            XCTAssertTrue(cells.allSatisfy { $0.isEditable && $0.text.isEmpty && HWPCellFormat($0.tableLocation!).borders.allSatisfy { $0.isVisible } })
            XCTAssertEqual(cells.last?.tableLocation?.row, rows - 1); XCTAssertEqual(cells.last?.tableLocation?.column, cols - 1)
            XCTAssertTrue(result.document.blocks.last!.isEditable); XCTAssertNil(result.document.blocks.last!.tableLocation)
            XCTAssertEqual(result.document.layouts, source.layouts)
            XCTAssertEqual(try HWPTableStructureDocument.load(result.document.serialized(result.document.blocks)).blocks, result.document.blocks)
        }
    }
    func testCaretStartMiddleAndEndPreserveUnicodeAndCharacterRuns() async throws {
        let text = "앞 한글 👨‍👩‍👧‍👦 뒤"
        for caret in [0, 2, text.utf16.count] {
            let source = try plain(text + "\n다음 본문")
            var drafts = source.blocks
            drafts[0] = HWPDocumentFormatting.apply(.bold(true), to: drafts[0], range: NSRange(location: 0, length: 2))
            let request = try request(source, drafts: drafts, index: 0, caret: caret)
            let result = try await HWPTableInsertion.applying(request, source: source, drafts: drafts)
            let body = result.document.blocks.filter { $0.tableLocation == nil }
            XCTAssertEqual(body.map(\.text), [(text as NSString).substring(to: caret), "", (text as NSString).substring(from: caret), "다음 본문"])
            let prefix = HWPParagraphEditing.slice(drafts[0], range: .init(location: 0, length: caret))
            let suffix = HWPParagraphEditing.slice(drafts[0], range: .init(location: caret, length: text.utf16.count - caret))
            XCTAssertTrue(HWPDocumentFormatting.matches(body[0], prefix)); XCTAssertTrue(HWPDocumentFormatting.matches(body[2], suffix))
        }
    }
    func testHWPAndHWPXNewCellsSupportInputFormattingRowsColumnsMergeSplitAndResize() async throws {
        for source in [try plain("표 앞\n표 뒤"), try HWPTableStructureDocument.load(file("hangul_design_application", "hwp"))] {
            let index = try XCTUnwrap(source.blocks.firstIndex { HWPParagraphEditing.supports($0) && $0.presentation.list == nil })
            let inserted = try await HWPTableInsertion.applying(request(source, index: index, caret: source.blocks[index].text.utf16.count), source: source, drafts: source.blocks)
            var document = inserted.document, id = inserted.focusedID
            var drafts = document.blocks
            let i = try XCTUnwrap(drafts.firstIndex { $0.id == id })
            drafts[i] = HWPTextRunEditing.replacingText(in: drafts[i], with: "새 표 셀 한글 😀\n두 번째 줄")
            var cell = HWPCellFormat(drafts[i].tableLocation!); cell.setFill(0xFFF2CC); cell.vertical = .center
            drafts[i] = HWPCellFormatting.apply(cell, to: drafts[i])
            drafts = HWPTableEditing.reflow(drafts, before: document.blocks, startingAt: id, layouts: document.layouts)
            document = try HWPTableStructureDocument.load(document.serialized(drafts))
            XCTAssertEqual(document.blocks[i].text, "새 표 셀 한글 😀\n두 번째 줄")
            for action in [HWPTableStructureAction.rowBelow, .columnAfter, .mergeRight, .splitColumns, .resize] {
                let result = try await document.editing(action, blocks: document.blocks, selectedID: id,
                    dimensions: action == .resize ? .init(widthPoints: 70, heightPoints: 45) : nil)
                document = result.document; id = result.focusedID
            }
            XCTAssertTrue(document.blocks.contains { $0.text == "새 표 셀 한글 😀\n두 번째 줄" })
            let reopened = try HWPTableStructureDocument.load(document.serialized(document.blocks))
            XCTAssertEqual(reopened.blocks, document.blocks)
            XCTAssertEqual(reopened.layouts, source.layouts)
            if case .hwp = source {
                let a = try OLECompoundFile(data: source.data), b = try OLECompoundFile(data: document.data)
                for path in a.streamNames where !path.hasPrefix("bodytext/") && !["docinfo", "prvtext"].contains(path) {
                    XCTAssertEqual(try a.stream(named: path), try b.stream(named: path), path)
                }
            }
        }
    }
    func testCurrentSectionAndExistingTableContentSurviveAnotherTableInsertion() async throws {
        let base = try plain("구역 본문"), archive = try HWPXEditingArchive(data: base.data)
        let xml = try archive.data(at: "Contents/section0.xml")
        let manifest = "<opf:package xmlns:opf=\"http://www.idpf.org/2007/opf\"><opf:manifest><opf:item id=\"first\" href=\"section0.xml\"/><opf:item id=\"second\" href=\"section7.xml\"/></opf:manifest><opf:spine><opf:itemref idref=\"first\"/><opf:itemref idref=\"second\"/></opf:spine></opf:package>"
        let source = try HWPTableStructureDocument.load(archive.repack(replacing: ["Contents/section7.xml": xml, "Contents/content.hpf": Data(manifest.utf8)]))
        let inserted = try await HWPTableInsertion.applying(request(source, index: 1), source: source, drafts: source.blocks)
        var drafts = inserted.document.blocks
        let cell = try XCTUnwrap(drafts.firstIndex { $0.id == inserted.focusedID })
        drafts[cell] = HWPTextRunEditing.replacingText(in: drafts[cell], with: "첫 표 보존")
        let first = try HWPTableStructureDocument.load(inserted.document.serialized(drafts))
        let second = try await HWPTableInsertion.applying(request(first, index: 1), source: first, drafts: first.blocks)
        XCTAssertEqual(Set(second.document.blocks.compactMap { $0.tableLocation?.table }).count, 2)
        XCTAssertTrue(second.document.blocks.contains { $0.text == "첫 표 보존" })
        XCTAssertEqual(try HWPXEditingArchive(data: second.document.data).data(at: "Contents/section0.xml"), xml)
        XCTAssertEqual(second.document.layouts, source.layouts)
    }
    func testTallTablePaginatesAndPageNumbersRemainContinuous() async throws {
        let source = try plain("앞\n뒤")
        var settings = HWPPageSettings(source.layouts[0]); settings.height = 420
        let paper = try await HWPPageSetup.applying(.init(settings: settings, sections: [0]), source: source, drafts: source.blocks)
        let numbered = try await HWPPageNumberEditing.applying(.init(style: .init(position: "BOTTOM_CENTER", sideCharacter: "", startsAt: 7), sections: [0]), source: paper, drafts: paper.blocks)
        let result = try await HWPTableInsertion.applying(request(numbered, index: 0, rows: 20, cols: 2), source: numbered, drafts: numbered.blocks)
        let pages = HWPOriginalCanvasPageBuilder.makePages(blocks: result.document.blocks, layouts: result.document.layouts)
        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertEqual(pages.map(\.pageNumberText), pages.indices.map { String(7 + $0) })
        XCTAssertEqual(result.document.blocks.filter { $0.tableLocation != nil }.count, 40)
        XCTAssertEqual(result.document.blocks.last?.text, "뒤")
    }
    func testViewModelTableInsertionUndoRedoPendingTextSaveAndConflict() async throws {
        for source in [try plain("앞뒤"), try HWPTableStructureDocument.load(file("hangul_design_application", "hwp"))] {
            let ext = source.data.starts(with: [0x50, 0x4b]) ? "hwpx" : "hwp"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
            try source.data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
            let model = HWPDocumentViewModel(fileURL: url); await model.load()
            let index = try XCTUnwrap(model.blocks.firstIndex { HWPParagraphEditing.supports($0) && $0.presentation.list == nil })
            model.selectBlock(model.blocks[index].id); model.editorText = "저장 전 입력 😀"
            var drafts = model.blocks; drafts[index] = HWPTextRunEditing.replacingText(in: drafts[index], with: model.editorText)
            let focused = try await model.insertTable(request(source, drafts: drafts, index: index, caret: 3))
            XCTAssertEqual(model.selectedBlockID, focused)
            XCTAssertEqual(try Data(contentsOf: url), source.data)
            let after = model.blocks
            model.undo(); XCTAssertEqual(model.blocks[index].text, "저장 전 입력 😀"); XCTAssertTrue(model.hasUnsavedChanges)
            model.undo(); XCTAssertFalse(model.hasUnsavedChanges)
            model.redo(); model.redo(); XCTAssertEqual(model.blocks, after)
            await model.save(); XCTAssertNil(model.errorDescription); XCTAssertFalse(model.hasUnsavedChanges)
            XCTAssertEqual(try HWPTableStructureDocument.load(Data(contentsOf: url)).blocks, after)
            let nextIndex = try XCTUnwrap(model.blocks.lastIndex { HWPParagraphEditing.supports($0) && $0.presentation.list == nil })
            _ = try await model.insertTable(request(try HWPTableStructureDocument.load(Data(contentsOf: url)), drafts: model.blocks, index: nextIndex))
            try source.data.write(to: url); await model.save()
            XCTAssertNotNil(model.errorDescription); XCTAssertEqual(try Data(contentsOf: url), source.data)
        }
    }
    private func request(_ source: HWPTableStructureDocument, drafts: [HWPDocumentBlock]? = nil, index: Int = 0, caret: Int = 0,
                         rows: Int = 2, cols: Int = 2) throws -> HWPTableInsertion.Request {
        let blocks = drafts ?? source.blocks
        let selection = try XCTUnwrap(HWPTableInsertion.selection(blocks: blocks, selectedID: blocks[index].id,
            range: .init(location: caret, length: 0), layouts: source.layouts))
        return .init(selection: selection, rows: rows, columns: cols)
    }
    private func plain(_ text: String) throws -> HWPTableStructureDocument { try .load(LegacyHWPXConverter.convert(text: text)) }
    private func file(_ name: String, _ ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: ext) ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "HWPXViewerFixtures")))
    }
}
