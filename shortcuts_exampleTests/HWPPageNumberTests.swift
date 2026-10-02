import RivoDocumentEngine
import XCTest
@testable import shortcuts_example

@MainActor final class HWPPageNumberTests: XCTestCase {
    func testInvalidStartPositionDecorationAndScope() throws {
        let source = try plain("본문")
        for start in [0, -1, 65_536] {
            XCTAssertThrowsError(try HWPPageNumberWriter.apply(request(start: start), to: source))
        }
        for style in [HWPDocumentPageNumberStyle(position: "INSIDE", sideCharacter: "", startsAt: nil),
                      .init(position: "TOP_LEFT", sideCharacter: "😀", startsAt: nil)] {
            XCTAssertThrowsError(try HWPPageNumberWriter.apply(.init(style: style, sections: [0]), to: source))
        }
        for sections: Set<Int> in [[], [7]] {
            XCTAssertThrowsError(try HWPPageNumberWriter.apply(.init(style: nil, sections: sections), to: source))
        }
    }
    func testNewHWPXSixPositionsPendingTextFormattingAndRemoveRoundTrip() async throws {
        var source = try plain("입력 전\n둘째 본문")
        var drafts = source.blocks
        drafts[0] = HWPTextRunEditing.replacingText(in: drafts[0], with: "쪽 번호와 한글 😀")
        drafts[0] = HWPDocumentFormatting.apply(.bold(true), to: drafts[0], range: NSRange(location: 0, length: 4))
        for (index, position) in HWPPageNumberEditing.positions.enumerated() {
            let edit = request(position: position, start: index == 0 ? 65_535 : 7, dash: index.isMultiple(of: 2))
            source = try await HWPPageNumberEditing.applying(edit, source: source, drafts: drafts)
            XCTAssertEqual(source.layouts[0].pageNumberStyle, edit.style)
            XCTAssertTrue(source.blocks.allSatisfy(\.isEditable)); XCTAssertTrue(HWPDocumentFormatting.matches(source.blocks[0], drafts[0]))
            let reopened = try HWPTableStructureDocument.load(source.serialized(source.blocks))
            XCTAssertEqual(reopened.layouts, source.layouts)
            XCTAssertEqual(pages(reopened)[0].pageNumberText, edit.style?.text(pageNumber: 1, sectionPageIndex: 0))
            drafts = source.blocks
        }
        let removed = try await HWPPageNumberEditing.applying(.init(style: nil, sections: [0]), source: source, drafts: source.blocks)
        XCTAssertNil(removed.layouts[0].pageNumberStyle); XCTAssertNil(pages(removed)[0].pageNumberText)
        XCTAssertEqual(removed.layouts[0].pageNumberStart, 7)
        XCTAssertEqual(removed.blocks, source.blocks)
    }
    func testMultipleSectionsContinueRestartCurrentAndPreserveUntouchedSection() async throws {
        let base = try plain("첫 문단\n둘째 문단"), archive = try HWPXEditingArchive(data: base.data)
        let xml = try archive.data(at: "Contents/section0.xml")
        let manifest = "<opf:package xmlns:opf=\"http://www.idpf.org/2007/opf\"><opf:manifest><opf:item id=\"first\" href=\"section0.xml\"/><opf:item id=\"second\" href=\"section7.xml\"/></opf:manifest><opf:spine><opf:itemref idref=\"first\"/><opf:itemref idref=\"second\"/></opf:spine></opf:package>"
        let source = try HWPTableStructureDocument.load(archive.repack(replacing: ["Contents/section7.xml": xml, "Contents/content.hpf": Data(manifest.utf8)]))
        let all = try await HWPPageNumberEditing.applying(request(start: 8, sections: [0, 7]), source: source, drafts: source.blocks)
        XCTAssertEqual(all.layouts.map(\.pageNumberStart), [8, nil])
        XCTAssertEqual(pages(all).map(\.pageNumberText), ["8", "9"])
        XCTAssertEqual(pages(all).map(\.pageNumber), [1, 2]) // Navigation stays physical.
        let current = try await HWPPageNumberEditing.applying(request(position: "TOP_RIGHT", start: 3, sections: [7]), source: all, drafts: all.blocks)
        XCTAssertEqual(pages(current).map(\.pageNumberText), ["8", "3"])
        XCTAssertEqual(try HWPXEditingArchive(data: all.data).data(at: "Contents/section0.xml"), try HWPXEditingArchive(data: current.data).data(at: "Contents/section0.xml"))
        let continuous = try await HWPPageNumberEditing.applying(request(start: nil, sections: [7]), source: current, drafts: current.blocks)
        XCTAssertEqual(pages(continuous).map(\.pageNumberText), ["8", "9"])
        let hidden = try await HWPPageNumberEditing.applying(.init(style: nil, sections: [0]), source: continuous, drafts: continuous.blocks)
        XCTAssertEqual(pages(hidden).map(\.pageNumberText), [nil, "9"])
    }
    func testPageBreakAndPaperChangeKeepNumberSequence() async throws {
        let source = try plain("첫째\n둘째")
        let numbered = try await HWPPageNumberEditing.applying(request(start: 5, dash: true), source: source, drafts: source.blocks)
        let draft = numbered.blocks[1], op = HWPParagraphEdit.insertPageBreak(.init(location: 0, length: 0))
        let proposal = try XCTUnwrap(HWPParagraphEditing.apply(op, draft: draft, to: numbered.blocks))
        let flowed = HWPParagraphEditing.reflow(proposal, before: numbered.blocks, draft: draft, operation: op, layouts: numbered.layouts)
        let broken = try HWPTableStructureDocument.load(numbered.serialized(flowed))
        XCTAssertEqual(pages(broken).map(\.pageNumberText), ["- 5 -", "- 6 -"])
        var settings = HWPPageSettings(broken.layouts[0]); settings.orient(landscape: true)
        let resized = try await HWPPageSetup.applying(.init(settings: settings, sections: [0]), source: broken, drafts: broken.blocks)
        XCTAssertEqual(pages(resized).map(\.pageNumberText), ["- 5 -", "- 6 -"])
    }
    func testHWPXPreservesPagePropertiesOtherNumberCountersAndArchiveEntries() async throws {
        let source = try HWPTableStructureDocument.load(file("mss_voucher", "hwpx"))
        let changed = try await HWPPageNumberEditing.applying(request(position: "TOP_LEFT", start: 12, dash: true), source: source, drafts: source.blocks)
        let a = try HWPXEditingArchive(data: source.data), b = try HWPXEditingArchive(data: changed.data)
        // Raw section properties other than page start/visibility remain byte-exact.
        if case .hwpx(let old) = source, case .hwpx(let new) = changed {
            for tag in ["pagepr", "colpr", "header", "footer", "tbl", "pic"] {
                XCTAssertEqual(try HWPFormattingXML.elements(old.sections[0].xml, name: tag).map(\.xml),
                               try HWPFormattingXML.elements(new.sections[0].xml, name: tag).map(\.xml), tag)
            }
        }
        XCTAssertEqual(try a.data(at: "Contents/header.xml"), try b.data(at: "Contents/header.xml"))
        XCTAssertEqual(changed.blocks, source.blocks)
    }
    func testHWPInsertAnchorSetStartChangeRemoveAndPreserveStreams() async throws {
        let source = try HWPTableStructureDocument.load(file("hangul_design_application", "hwp"))
        let added = try await HWPPageNumberEditing.applying(request(start: 23, dash: true), source: source, drafts: source.blocks)
        XCTAssertEqual(added.layouts[0].pageNumberStyle, request(start: 23, dash: true).style)
        XCTAssertEqual(added.blocks.map(\.text), source.blocks.map(\.text))
        XCTAssertEqual(added.blocks.map(\.isEditable), source.blocks.map(\.isEditable))
        let a = try OLECompoundFile(data: source.data), b = try OLECompoundFile(data: added.data)
        for path in a.streamNames where path != "bodytext/section0" { XCTAssertEqual(try a.stream(named: path), try b.stream(named: path), path) }
        let records = try hwpRecords(added.data)
        let originalRecords = try hwpRecords(source.data)
        func preserved(_ record: HWP5DocumentRewriter.Record) -> Bool {
            if [0x42, 0x43].contains(record.tag) { return false }
            return record.tag != 0x47 || ![0x7365_6364, 0x7067_6E70].contains((try? record.payload.hwpWriterUInt32(at: 0)) ?? 0)
        }
        XCTAssertEqual(originalRecords.filter(preserved).map { $0.serialized() }, records.filter(preserved).map { $0.serialized() })
        let numbers = records.filter { $0.tag == 0x47 && (try? $0.payload.hwpWriterUInt32(at: 0)) == 0x7067_6E70 }
        XCTAssertEqual(numbers.count, 1); XCTAssertEqual(try numbers[0].payload.hwpWriterUInt32(at: 4) & 0xFFF, 0x500)
        XCTAssertTrue(records.contains { $0.tag == 0x43 && $0.payload.range(of: Data([21, 0, 112, 110, 103, 112, 0, 0, 0, 0, 0, 0, 0, 0, 21, 0])) != nil })
        var drafts = added.blocks
        let index = try XCTUnwrap(drafts.firstIndex(where: \.isEditable))
        drafts[index] = HWPTextRunEditing.replacingText(in: drafts[index], with: "번호 설정 후 입력")
        let changed = try await HWPPageNumberEditing.applying(request(position: "TOP_RIGHT", start: 2), source: added, drafts: drafts)
        XCTAssertEqual(changed.blocks[index].text, "번호 설정 후 입력")
        XCTAssertEqual(pages(changed)[0].pageNumberText, "2")
        let removed = try await HWPPageNumberEditing.applying(.init(style: nil, sections: [0]), source: changed, drafts: changed.blocks)
        XCTAssertNil(removed.layouts[0].pageNumberStyle)
        let again = try await HWPPageNumberEditing.applying(request(start: nil), source: removed, drafts: removed.blocks)
        let againRecords = try hwpRecords(again.data)
        XCTAssertEqual(againRecords.count, try hwpRecords(changed.data).count)
        XCTAssertEqual(againRecords.filter { $0.tag == 0x47 && (try? $0.payload.hwpWriterUInt32(at: 0)) == 0x7067_6E70 }.count, 1)
        XCTAssertEqual(try HWPTableStructureDocument.load(again.serialized(again.blocks)).layouts, again.layouts)
    }
    func testAmbiguousOrLocalNumberControlsRejectWithoutChangingSource() throws {
        let base = try plain("처음\n나중"), archive = try HWPXEditingArchive(data: base.data)
        let original = String(decoding: try archive.data(at: "Contents/section0.xml"), as: UTF8.self)
        let firstRun = try XCTUnwrap(HWPFormattingXML.elements(original, name: "run").first)
        let number = "<hp:ctrl><hp:pageNum pos=\"BOTTOM_CENTER\" formatType=\"DIGIT\" sideChar=\"\"/></hp:ctrl>"
        for (run, content) in [(firstRun, number + number), (try HWPFormattingXML.elements(original, name: "run")[1], number),
                               (firstRun, "<hp:ctrl><hp:newNum num=\"7\" numType=\"PAGE\"/></hp:ctrl>")] {
            let changedRun = run.xml.replacingOccurrences(of: "</hp:run>", with: content + "</hp:run>")
            let xml = (original as NSString).replacingCharacters(in: run.range, with: changedRun)
            let data = try archive.repack(replacing: ["Contents/section0.xml": Data(xml.utf8)])
            let source = try HWPTableStructureDocument.load(data)
            XCTAssertThrowsError(try HWPPageNumberWriter.apply(request(), to: source))
            XCTAssertEqual(source.data, data)
        }
    }
    func testViewModelPageNumberUndoRedoSaveAndConflict() async throws {
        for source in [try plain("본문\n둘째"), try HWPTableStructureDocument.load(file("hangul_design_application", "hwp"))] {
            let ext = source.data.starts(with: [0x50, 0x4b]) ? "hwpx" : "hwp"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
            try source.data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
            let model = HWPDocumentViewModel(fileURL: url); await model.load()
            let block = try XCTUnwrap(model.blocks.first(where: \.isEditable))
            model.selectBlock(block.id); model.editorText = "저장 전 입력 😀"
            try await model.applyPageNumber(request(start: 9))
            XCTAssertTrue(model.blocks.contains { $0.text == "저장 전 입력 😀" })
            let after = model.pageLayouts
            XCTAssertEqual(try Data(contentsOf: url), source.data)
            model.undo(); XCTAssertEqual(model.pageLayouts, source.layouts); XCTAssertTrue(model.hasUnsavedChanges)
            model.undo(); XCTAssertFalse(model.hasUnsavedChanges)
            model.redo(); model.redo(); XCTAssertEqual(model.pageLayouts, after)
            await model.save(); XCTAssertNil(model.errorDescription); XCTAssertFalse(model.hasUnsavedChanges)
            XCTAssertEqual(try HWPTableStructureDocument.load(Data(contentsOf: url)).layouts, after)
            try await model.applyPageNumber(.init(style: nil, sections: [0]))
            try source.data.write(to: url); await model.save()
            XCTAssertNotNil(model.errorDescription); XCTAssertEqual(try Data(contentsOf: url), source.data)
        }
    }
    private func request(position: String = "BOTTOM_CENTER", start: Int? = 1, dash: Bool = false, sections: Set<Int> = [0]) -> HWPPageNumberRequest {
        .init(style: .init(position: position, sideCharacter: dash ? "-" : "", startsAt: start), sections: sections)
    }
    private func plain(_ text: String) throws -> HWPTableStructureDocument { try .load(LegacyHWPXConverter.convert(text: text)) }
    private func pages(_ source: HWPTableStructureDocument) -> [HWPOriginalCanvasPage] { HWPOriginalCanvasPageBuilder.makePages(blocks: source.blocks, layouts: source.layouts) }
    private func hwpRecords(_ data: Data) throws -> [HWP5DocumentRewriter.Record] {
        let ole = try OLECompoundFile(data: data), raw = try ole.stream(named: "bodytext/section0")
        let compressed = try ole.stream(named: "FileHeader").hwpWriterUInt32(at: 36) & 1 != 0
        return try HWP5DocumentRewriter.parseRecords(compressed ? HWP5TextExtractor.inflateRawDeflate(raw, maximumBytes: HWP5TextExtractor.maximumSectionBytes) : raw)
    }
    private func file(_ name: String, _ ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: ext) ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "HWPXViewerFixtures")))
    }
}
