import RivoDocumentEngine
import XCTest
@testable import shortcuts_example

@MainActor
final class HWPPageBreakTests: XCTestCase {
    func testMiddleSplitKeepsUnicodeStylesAndRoundTripsHWPX() throws {
        let source = try plain("첫 문단\n앞 한글 👨‍👩‍👧‍👦 뒤\n끝 문단")
        var blocks = source.blocks
        let range = (blocks[1].text as NSString).range(of: "한글 👨‍👩‍👧‍👦")
        blocks[1] = HWPDocumentFormatting.apply(.bold(true), to: blocks[1], range: range)
        let edited = try perform(.insertPageBreak(.init(location: range.location, length: 0)), index: 1, blocks: blocks, layouts: source.layouts)
        XCTAssertEqual(edited.blocks.map(\.text), ["첫 문단", "앞 ", "한글 👨‍👩‍👧‍👦 뒤", "끝 문단"])
        XCTAssertEqual(edited.caret, 0)
        XCTAssertTrue(edited.blocks[2].presentation.pageBreakBefore)
        XCTAssertTrue(HWPDocumentFormatting.run(at: 0, in: edited.blocks[2]).isBold)
        let saved = try roundTrip(source, edited.blocks)
        XCTAssertEqual(pages(saved).count, 2)
        XCTAssertEqual(pages(saved)[1].bodyBlocks.first?.text, edited.blocks[2].text)
    }

    func testStartUsesCurrentParagraphEndCreatesEmptyNextPageAndFirstStartKeepsBlankPage() throws {
        let source = try plain("처음\n둘째")
        let start = try perform(.insertPageBreak(.init(location: 0, length: 0)), index: 1, blocks: source.blocks, layouts: source.layouts)
        XCTAssertEqual(start.blocks.count, 2)
        XCTAssertEqual(pages(try roundTrip(source, start.blocks)).count, 2)
        XCTAssertNil(HWPParagraphEditing.apply(.insertPageBreak(.init(location: 0, length: 0)), draft: start.blocks[1], to: start.blocks))
        let end = try perform(.insertPageBreak(.init(location: 2, length: 0)), index: 1, blocks: source.blocks, layouts: source.layouts)
        XCTAssertEqual(end.blocks.map(\.text), ["처음", "둘째", ""])
        XCTAssertEqual(pages(try roundTrip(source, end.blocks)).count, 2)
        let first = try perform(.insertPageBreak(.init(location: 0, length: 0)), index: 0, blocks: source.blocks, layouts: source.layouts)
        XCTAssertEqual(first.blocks.map(\.text), ["", "처음", "둘째"])
        XCTAssertEqual(pages(try roundTrip(source, first.blocks)).count, 2)
    }

    func testBackspaceRemovesBreakBeforeMergingAndMenuRemovalPreservesParagraphs() throws {
        let source = try plain("앞 문단\n뒤 문단")
        let inserted = try perform(.insertPageBreak(.init(location: 0, length: 0)), index: 1, blocks: source.blocks, layouts: source.layouts)
        let saved = try roundTrip(source, inserted.blocks)
        for operation in [HWPParagraphEdit.mergeBackward, .removePageBreak] {
            let removed = try perform(operation, index: 1, blocks: saved.blocks, layouts: saved.layouts)
            XCTAssertEqual(removed.blocks.map(\.text), source.blocks.map(\.text))
            let reopened = try roundTrip(saved, removed.blocks)
            XCTAssertEqual(pages(reopened).count, 1)
            XCTAssertFalse(reopened.blocks[1].presentation.pageBreakBefore)
            let merged = try XCTUnwrap(HWPParagraphEditing.apply(.mergeBackward, draft: reopened.blocks[1], to: reopened.blocks))
            XCTAssertEqual(merged.blocks.map(\.text), ["앞 문단뒤 문단"])
        }
    }

    func testSelectedTextReplacementAndInvalidUnicodeRanges() throws {
        let source = try plain("앞 한글 😀 뒤")
        let range = (source.blocks[0].text as NSString).range(of: "한글 😀")
        let split = try perform(.insertPageBreak(range), index: 0, blocks: source.blocks, layouts: source.layouts)
        XCTAssertEqual(split.blocks.map(\.text), ["앞 ", " 뒤"])
        _ = try roundTrip(source, split.blocks)
        let emoji = (source.blocks[0].text as NSString).range(of: "😀")
        for invalid in [NSRange(location: emoji.location + 1, length: 0), .init(location: NSNotFound, length: 0), .init(location: 0, length: 999)] {
            XCTAssertNil(HWPParagraphEditing.apply(.insertPageBreak(invalid), draft: source.blocks[0], to: source.blocks))
        }
        XCTAssertNil(HWPParagraphEditing.apply(.removePageBreak, draft: source.blocks[0], to: source.blocks))
    }

    func testInheritedHWPXBreakIsClearedOnlyForSelectedParagraph() throws {
        let base = try plain("첫째\n둘째\n셋째"), archive = try HWPXEditingArchive(data: base.data)
        var header = String(decoding: try archive.data(at: "Contents/header.xml"), as: UTF8.self)
        let para = try XCTUnwrap(HWPFormattingXML.elements(header, name: "parapr").first)
        let prefix = try HWPFormattingXML.prefix(para.xml)
        let changed = try HWPFormattingXML.replaceOrAppend(para.xml, name: "breaksetting",
            replacement: "<\(prefix)breakSetting pageBreakBefore=\"1\" keepWithNext=\"1\"/>")
        header = (header as NSString).replacingCharacters(in: para.range, with: changed)
        let source = try HWPTableStructureDocument.load(archive.repack(replacing: ["Contents/header.xml": Data(header.utf8)]))
        XCTAssertTrue(source.blocks.allSatisfy { $0.presentation.pageBreakBefore })
        let removed = try perform(.removePageBreak, index: 1, blocks: source.blocks, layouts: source.layouts)
        let saved = try roundTrip(source, removed.blocks)
        XCTAssertEqual(saved.blocks.map { $0.presentation.pageBreakBefore }, [true, false, true])
        let newHeader = String(decoding: try HWPXEditingArchive(data: saved.data).data(at: "Contents/header.xml"), as: UTF8.self)
        XCTAssertTrue(newHeader.contains(changed))
        XCTAssertTrue(newHeader.contains("keepWithNext=\"1\""))
    }

    func testHWPInheritedAndDirectBreakRemovalKeepsOtherHeaderBitsAndStreams() throws {
        let data = try file("hangul_design_application", "hwp")
        let original = try HWPTableStructureDocument.load(data)
        let index = try XCTUnwrap(original.blocks.firstIndex { HWPParagraphEditing.supports($0) && !$0.text.isEmpty })
        let container = try OLECompoundFile(data: data)
        let compressed = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36) & 1 != 0
        func expand(_ d: Data) throws -> Data { try compressed ? HWP5TextExtractor.inflateRawDeflate(d, maximumBytes: HWP5TextExtractor.maximumSectionBytes) : d }
        func pack(_ records: [HWP5DocumentRewriter.Record]) throws -> Data {
            let d = records.reduce(into: Data()) { $0.append($1.serialized()) }; return try compressed ? HWP5DocumentRewriter.rawDeflate(d) : d
        }
        let path = original.blocks[index].sectionPath
        var records = try HWP5DocumentRewriter.parseRecords(expand(container.stream(named: path)))
        let recordIndex = try XCTUnwrap(records.indices.filter { records[$0].tag == 0x42 }.dropFirst(original.blocks[index].paragraphIndex).first)
        let shapeID = Int(records[recordIndex].payload[8]) | Int(records[recordIndex].payload[9]) << 8
        records[recordIndex].payload[11] |= 0x0C
        var info = try HWP5DocumentRewriter.parseRecords(expand(container.stream(named: "DocInfo")))
        let shapeIndex = info.indices.filter { info[$0].tag == 0x19 }[shapeID]
        info[shapeIndex].payload.hwpWriterSetUInt32(try info[shapeIndex].payload.hwpWriterUInt32(at: 0) | (1 << 19), at: 0)
        let source = try HWPTableStructureDocument.load(container.serialized(replacing: [path: pack(records), "DocInfo": pack(info)]))
        XCTAssertTrue(source.blocks[index].presentation.pageBreakBefore)
        let removed = try perform(.removePageBreak, index: index, blocks: source.blocks, layouts: source.layouts)
        let saved = try roundTrip(source, removed.blocks)
        XCTAssertFalse(saved.blocks[index].presentation.pageBreakBefore)
        let final = try OLECompoundFile(data: saved.data)
        let after = try HWP5DocumentRewriter.parseRecords(expand(final.stream(named: path)))
        XCTAssertEqual(after[recordIndex].payload[11], records[recordIndex].payload[11] & ~0x04)
        let finalInfo = try HWP5DocumentRewriter.parseRecords(expand(final.stream(named: "DocInfo")))
        XCTAssertEqual(finalInfo.filter { $0.tag == 0x19 }[shapeID].payload, info[shapeIndex].payload)
        for name in container.streamNames where !name.hasPrefix("bodytext/") && name != "docinfo" && name != "prvtext" {
            XCTAssertEqual(try container.stream(named: name), try final.stream(named: name), name)
        }
    }

    func testRealHWPAndHWPXRepeatedInsertRemoveSaveKeepTablesAndAssets() throws {
        for (name, ext) in [("hangul_design_application", "hwp"), ("mss_voucher", "hwpx")] {
            var source = try HWPTableStructureDocument.load(file(name, ext))
            let baseline = source.data
            let tableText = source.blocks.filter { $0.tableLocation != nil }.map(\.text)
            let index = try XCTUnwrap(source.blocks.firstIndex { HWPParagraphEditing.supports($0) && $0.text.count > 2 })
            for _ in 0..<2 {
                let text = source.blocks.map(\.text).joined()
                let inserted = try perform(.insertPageBreak(.init(location: 1, length: 0)), index: index, blocks: source.blocks, layouts: source.layouts)
                source = try roundTrip(source, inserted.blocks)
                XCTAssertTrue(source.blocks[index + 1].presentation.pageBreakBefore)
                let removed = try perform(.removePageBreak, index: index + 1, blocks: source.blocks, layouts: source.layouts)
                source = try roundTrip(source, removed.blocks)
                XCTAssertEqual(source.blocks.map(\.text).joined(), text)
                XCTAssertEqual(source.blocks.filter { $0.tableLocation != nil }.map(\.text), tableText)
            }
            if ext == "hwp" {
                let old = try OLECompoundFile(data: baseline), new = try OLECompoundFile(data: source.data)
                for path in old.streamNames where !path.hasPrefix("bodytext/") && path != "docinfo" && path != "prvtext" {
                    XCTAssertEqual(try old.stream(named: path), try new.stream(named: path), path)
                }
            } else {
                let old = try HWPXEditingArchive(data: baseline), new = try HWPXEditingArchive(data: source.data)
                for path in old.paths where path.lowercased().hasPrefix("bindata/") {
                    XCTAssertEqual(try old.data(at: path), try new.data(at: path), path)
                }
            }
        }
    }

    func testEnterAfterPageBreakDoesNotCopyItAndListsContinue() throws {
        let source = try plain("첫 문단\n목록 내용")
        var blocks = source.blocks
        blocks[1] = HWPDocumentFormatting.apply(.list(HWPListFormatting.style(.number, for: blocks[1], in: blocks)), to: blocks[1], range: .init(location: 0, length: 0))
        let inserted = try perform(.insertPageBreak(.init(location: 0, length: 0)), index: 1, blocks: blocks, layouts: source.layouts)
        let saved = try roundTrip(source, inserted.blocks)
        let next = try perform(.split(.init(location: saved.blocks[1].text.utf16.count, length: 0)), index: 1, blocks: saved.blocks, layouts: saved.layouts)
        let reopened = try roundTrip(saved, next.blocks)
        XCTAssertTrue(reopened.blocks[1].presentation.pageBreakBefore)
        XCTAssertFalse(reopened.blocks[2].presentation.pageBreakBefore)
        XCTAssertEqual(reopened.blocks[2].presentation.list?.ordinal, 2)
        XCTAssertEqual(pages(reopened).count, 2)
    }

    func testBreakSurvivesPageSetupAndCellAndMulticolumnAreUnavailable() async throws {
        let source = try plain("첫째\n둘째")
        let inserted = try perform(.insertPageBreak(.init(location: 0, length: 0)), index: 1, blocks: source.blocks, layouts: source.layouts)
        var settings = HWPPageSettings(source.layouts[0]); settings.orient(landscape: true)
        let saved = try await HWPPageSetup.applying(.init(settings: settings, sections: [0]), source: source, drafts: inserted.blocks)
        XCTAssertTrue(saved.blocks[1].presentation.pageBreakBefore); XCTAssertEqual(pages(saved).count, 2)
        let actual = try HWPTableStructureDocument.load(file("mss_voucher", "hwpx"))
        let cell = try XCTUnwrap(actual.blocks.first { $0.tableLocation != nil && $0.isEditable })
        XCTAssertNil(HWPParagraphEditing.apply(.insertPageBreak(.init(location: 0, length: 0)), draft: cell, to: actual.blocks))
        let session = HWPInlineEditingSession()
        session.begin(block: source.blocks[0], at: .zero, onSelect: { _ in }, onChange: { _ in }, onCommit: {})
        XCTAssertTrue(session.supportsPageBreak(layouts: source.layouts))
        XCTAssertFalse(session.supportsPageBreak(layouts: []))
        let withPage = try HWPPageSetupWriter.apply(.init(settings: HWPPageSettings(source.layouts[0]), sections: [0]), to: source)
        let archive = try HWPXEditingArchive(data: withPage)
        var xml = String(decoding: try archive.data(at: "Contents/section0.xml"), as: UTF8.self)
        let section = try XCTUnwrap(HWPFormattingXML.elements(xml, name: "secpr").first)
        let changed = try HWPFormattingXML.append("<hp:colPr colCount=\"2\" sameGap=\"1000\"/>", to: section.xml)
        xml = (xml as NSString).replacingCharacters(in: section.range, with: changed)
        let columns = try HWPTableStructureDocument.load(archive.repack(replacing: ["Contents/section0.xml": Data(xml.utf8)]))
        XCTAssertEqual(columns.layouts[0].columnLayout.count, 2)
        XCTAssertFalse(session.supportsPageBreak(layouts: columns.layouts))
        session.finish(commitChanges: false)
    }

    func testViewModelPageBreakUndoRedoPendingInputSaveAndConflict() async throws {
        for (name, ext) in [("hangul_design_application", "hwp"), ("mss_voucher", "hwpx")] {
            let data = try file(name, ext), url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
            try data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
            let model = HWPDocumentViewModel(fileURL: url); await model.load()
            let index = try XCTUnwrap(model.blocks.firstIndex { HWPParagraphEditing.supports($0) && $0.text.count > 2 })
            let old = model.blocks
            let draft = HWPTextRunEditing.replacingText(in: old[index], with: "새 입력 한글 😀")
            let split = try XCTUnwrap(model.editParagraph(draft, operation: .insertPageBreak(.init(location: 3, length: 0))))
            XCTAssertTrue(split.blocks[index + 1].presentation.pageBreakBefore)
            model.undo(); XCTAssertEqual(model.blocks[index].text, draft.text); XCTAssertEqual(model.blocks.count, old.count)
            model.redo(); XCTAssertEqual(model.blocks.map(\.text), split.blocks.map(\.text))
            await model.save(); XCTAssertNil(model.errorDescription); XCTAssertFalse(model.hasUnsavedChanges)
            let saved = try HWPTableStructureDocument.load(Data(contentsOf: url))
            XCTAssertTrue(saved.blocks[index + 1].presentation.pageBreakBefore)
            _ = try XCTUnwrap(model.editParagraph(model.blocks[index + 1], operation: .removePageBreak))
            try data.write(to: url); await model.save()
            XCTAssertNotNil(model.errorDescription); XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }

    private func perform(_ operation: HWPParagraphEdit, index: Int, blocks: [HWPDocumentBlock], layouts: [HWPDocumentPageLayout]) throws -> HWPParagraphEditResult {
        let draft = blocks[index]
        let result = try XCTUnwrap(HWPParagraphEditing.apply(operation, draft: draft, to: blocks))
        return .init(blocks: HWPParagraphEditing.reflow(result, before: blocks, draft: draft, operation: operation, layouts: layouts), focusedID: result.focusedID, caret: result.caret)
    }
    private func roundTrip(_ source: HWPTableStructureDocument, _ blocks: [HWPDocumentBlock]) throws -> HWPTableStructureDocument {
        let saved = try HWPTableStructureDocument.load(source.serialized(blocks))
        XCTAssertEqual(saved.blocks.count, blocks.count)
        for (a, b) in zip(saved.blocks, blocks) { XCTAssertTrue(HWPDocumentFormatting.matches(a, b), "saved: \(a.presentation) requested: \(b.presentation)") }
        return saved
    }
    private func pages(_ source: HWPTableStructureDocument) -> [HWPOriginalCanvasPage] {
        HWPOriginalCanvasPageBuilder.makePages(blocks: source.blocks, layouts: source.layouts)
    }
    private func plain(_ text: String) throws -> HWPTableStructureDocument { try .load(LegacyHWPXConverter.convert(text: text)) }
    private func file(_ name: String, _ ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: ext) ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "HWPXViewerFixtures")))
    }
}
