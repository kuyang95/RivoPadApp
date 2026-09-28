import XCTest
@testable import shortcuts_example

@MainActor final class HWPHeaderFooterTests: XCTestCase {
    func testCreateEditClearBothFormatsPreservesBodyAndEditability() async throws {
        for original in [try plain("본문 😀\n둘째 문단"), try hwp()] {
            var source = original
            for kind in HWPHeaderFooterKind.allCases {
                source = try await apply(kind, ["문서 제목 😀"], source, alignment: .centered)
                let current = region(source, kind)
                XCTAssertEqual(current.map(\.text), ["문서 제목 😀"])
                XCTAssertEqual(current.first?.presentation.alignment, .centered)
                XCTAssertEqual(current.first?.presentation.textRuns.first?.fontSizePoints ?? 0, 10, accuracy: 0.01)
                XCTAssertTrue(current.allSatisfy(\.isEditable))
                source = try await apply(kind, ["수정한 내용"], source)
                XCTAssertEqual(region(source, kind).count, 1)
                XCTAssertEqual(region(source, kind).map(\.text), ["수정한 내용"])
            }
            let a = original.blocks.filter { $0.region.kind == .body }, b = source.blocks.filter { $0.region.kind == .body }
            XCTAssertEqual(a.map(\.text), b.map(\.text)); XCTAssertEqual(a.map(\.isEditable), b.map(\.isEditable))
            XCTAssertEqual(a.map { HWP5FormattingWriter.lineData($0.lineLayouts) }, b.map { HWP5FormattingWriter.lineData($0.lineLayouts) })
            var drafts = source.blocks; let i = try XCTUnwrap(drafts.firstIndex { $0.isEditable && $0.region.kind == .body })
            drafts[i] = HWPTextRunEditing.replacingText(in: drafts[i], with: "머리말 입력 후 본문")
            source = try await HWPHeaderFooterEditing.applying(.init(kind: .header, texts: [""], sections: [0]), source: source, drafts: drafts)
            XCTAssertEqual(region(source, .header).map(\.text), [""])
            XCTAssertEqual(region(source, .footer).map(\.text), ["수정한 내용"])
            XCTAssertTrue(source.blocks.contains { $0.text == "머리말 입력 후 본문" })
            let reopened = try HWPTableStructureDocument.load(source.serialized(source.blocks))
            XCTAssertEqual(reopened.blocks, source.blocks)
        }
    }
    func testMultiParagraphStylesAndLineBreaksRoundTrip() async throws {
        for base in [try plain("본문"), try hwp()] {
            var source = try await apply(.header, ["첫 문단", "둘째"], base)
            var drafts = source.blocks
            let i = try XCTUnwrap(drafts.firstIndex { $0.region.kind == .header })
            drafts[i] = HWPDocumentFormatting.apply(.bold(true), to: drafts[i], range: .init(location: 0, length: drafts[i].text.utf16.count))
            source = try await HWPHeaderFooterEditing.applying(.init(kind: .header, texts: ["한글 😀", "다음"], sections: [0]), source: source, drafts: drafts)
            XCTAssertTrue(region(source, .header)[0].presentation.textRuns.allSatisfy { $0.isBold })
            XCTAssertGreaterThan(try XCTUnwrap(region(source, .header)[1].lineLayouts.first).verticalPositionPoints, try XCTUnwrap(region(source, .header)[0].lineLayouts.first).verticalPositionPoints)
            let footer = try await apply(.footer, ["첫 줄\n둘째 줄"], source, alignment: .trailing)
            XCTAssertEqual(region(footer, .footer)[0].text, "첫 줄\n둘째 줄")
            XCTAssertEqual(region(footer, .footer)[0].lineLayouts.count, 2)
        }
    }
    func testSectionsParityNumberRestartAndUntouchedArchive() async throws {
        let base = try plain("본문"), archive = try HWPXEditingArchive(data: base.data)
        let manifest = "<opf:package xmlns:opf=\"http://www.idpf.org/2007/opf\"><opf:manifest><opf:item id=\"first\" href=\"section0.xml\"/><opf:item id=\"second\" href=\"section7.xml\"/></opf:manifest><opf:spine><opf:itemref idref=\"first\"/><opf:itemref idref=\"second\"/></opf:spine></opf:package>"
        var source = try HWPTableStructureDocument.load(archive.repack(replacing: ["Contents/section7.xml": archive.data(at: "Contents/section0.xml"), "Contents/content.hpf": Data(manifest.utf8)]))
        source = try await HWPHeaderFooterEditing.applying(.init(kind: .header, texts: ["공통"], sections: [0, 7], scope: .evenPages), source: source, drafts: source.blocks)
        source = try await HWPPageNumberEditing.applying(.init(style: .init(position: "BOTTOM_CENTER", sideCharacter: "", startsAt: 2), sections: [0, 7]), source: source, drafts: source.blocks)
        let pages = HWPOriginalCanvasPageBuilder.makePages(blocks: source.blocks, layouts: source.layouts)
        XCTAssertEqual(pages.map { $0.regionBlocks(.header).count }, [1, 0])
        let changed = try await HWPHeaderFooterEditing.applying(.init(kind: .header, texts: ["둘째 구역"], sections: [7], scope: .oddPages), source: source, drafts: source.blocks)
        XCTAssertEqual(try HWPXEditingArchive(data: source.data).data(at: "Contents/section0.xml"), try HWPXEditingArchive(data: changed.data).data(at: "Contents/section0.xml"))
        XCTAssertEqual(changed.layouts, source.layouts)
        XCTAssertEqual(HWPHeaderFooterEditing.paragraphs(changed.blocks, kind: .header, section: 7).map(\.text), ["둘째 구역"])
    }
    func testHeaderOwnerBodyAndNestedTextFormattingTogetherAndParagraphSplitMerge() async throws {
        let source = try await apply(.header, ["머리말"], plain("본문 시작\n둘째"))
        var blocks = source.blocks
        for i in blocks.indices where blocks[i].region.kind == .header || i == 0 {
            blocks[i] = HWPTextRunEditing.replacingText(in: blocks[i], with: i == 0 ? "앞뒤" : "머리말 변경 😀")
            blocks[i] = HWPDocumentFormatting.apply(.bold(true), to: blocks[i], range: .init(location: 0, length: blocks[i].text.utf16.count))
            blocks[i] = blocks[i].withLayout(lines: HWPFlowLayout.measure(blocks[i], width: 400, startY: 0, pageHeight: nil, minimumHeight: 0))
        }
        let formatted = try HWPTableStructureDocument.load(source.serialized(blocks))
        XCTAssertEqual(formatted.blocks.map(\.text), blocks.map(\.text))
        XCTAssertTrue(zip(formatted.blocks, blocks).allSatisfy { HWPDocumentFormatting.matches($0, $1) })
        let draft = formatted.blocks[0], op = HWPParagraphEdit.split(.init(location: 1, length: 0))
        let proposal = try XCTUnwrap(HWPParagraphEditing.apply(op, draft: draft, to: formatted.blocks))
        let flowed = HWPParagraphEditing.reflow(proposal, before: formatted.blocks, draft: draft, operation: op, layouts: formatted.layouts)
        let split = try HWPTableStructureDocument.load(formatted.serialized(flowed))
        XCTAssertEqual(split.blocks.filter { $0.region.kind == .body }.map(\.text), ["앞", "뒤", "둘째"])
        XCTAssertEqual(region(split, .header).map(\.text), ["머리말 변경 😀"])
        let next = try XCTUnwrap(split.blocks.first { $0.text == "뒤" })
        let merged = try XCTUnwrap(HWPParagraphEditing.apply(.mergeBackward, draft: next, to: split.blocks))
        let reopened = try HWPTableStructureDocument.load(split.serialized(merged.blocks))
        XCTAssertEqual(reopened.blocks.filter { $0.region.kind == .body }.map(\.text), ["앞뒤", "둘째"])
        XCTAssertEqual(region(reopened, .header).map(\.text), ["머리말 변경 😀"])
    }
    func testInvalidRequestsAndOverflowLeaveSourceIntact() async throws {
        let source = try plain("본문")
        for request in [HWPHeaderFooterRequest(kind: .header, texts: [], sections: [0]),
                        .init(kind: .header, texts: ["a"], sections: []), .init(kind: .header, texts: ["a"], sections: [7]),
                        .init(kind: .header, texts: ["a"], sections: [0], size: .nan),
                        .init(kind: .header, texts: ["a\u{1}"], sections: [0])] {
            XCTAssertThrowsError(try HWPHeaderFooterEditing.validate(request, source: source))
        }
        do { _ = try await apply(.header, [String(repeating: "줄\n", count: 30)], source); XCTFail("Must reject overflow") }
        catch { XCTAssertTrue(error is HWPHeaderFooterError) }
        XCTAssertEqual(source.blocks.map(\.text), ["본문"])
    }
    func testBlankDocumentHeaderThenBodyTypingFormattingAndSave() async throws {
        let source = try await apply(.header, ["제목"], plain(""))
        var blocks = source.blocks
        XCTAssertTrue(blocks[0].isEditable)
        blocks[0] = HWPTextRunEditing.replacingText(in: blocks[0], with: "첫 본문 😀")
        blocks[0] = HWPDocumentFormatting.apply(.size(14), to: blocks[0], range: .init(location: 0, length: blocks[0].text.utf16.count))
        let saved = try HWPTableStructureDocument.load(source.serialized(blocks))
        XCTAssertEqual(saved.blocks[0].text, "첫 본문 😀"); XCTAssertEqual(region(saved, .header).map(\.text), ["제목"])
        XCTAssertTrue(saved.blocks[0].isEditable)
    }
    func testHeaderOwnerTableInsertionAndDeletionKeepRegionAndBody() async throws {
        let source = try await apply(.header, ["제목"], plain("앞뒤"))
        let selection = try XCTUnwrap(HWPTableInsertion.selection(blocks: source.blocks, selectedID: source.blocks[0].id,
            range: .init(location: 1, length: 0), layouts: source.layouts))
        let inserted = try await HWPTableInsertion.applying(.init(selection: selection, rows: 2, columns: 2), source: source, drafts: source.blocks)
        XCTAssertEqual(region(inserted.document, .header).map(\.text), ["제목"])
        XCTAssertEqual(inserted.document.blocks.filter { $0.region.kind == .body && $0.tableLocation == nil }.map(\.text), ["앞", "", "뒤"])
        let deleted = try await inserted.document.editing(.deleteTable, blocks: inserted.document.blocks, selectedID: inserted.focusedID)
        XCTAssertEqual(region(deleted.document, .header).map(\.text), ["제목"])
        XCTAssertFalse(deleted.document.blocks.contains { $0.tableLocation != nil })
        XCTAssertTrue(deleted.document.blocks.contains { $0.text == "뒤" })
    }
    func testTypingSpacesAfterHeaderKeepsPerRunFonts() async throws {
        let source = try await apply(.header, ["문서 제목"], plain("쪽 설정 문단\n둘째"))
        var blocks = source.blocks
        blocks[0] = HWPTextRunEditing.replacingText(in: blocks[0], with: "쪽 설정 문단본문 계속 입력")
        let saved = try HWPTableStructureDocument.load(source.serialized(blocks))
        XCTAssertTrue(HWPDocumentFormatting.matches(saved.blocks[0], blocks[0]))
        XCTAssertEqual(region(saved, .header).map(\.text), ["문서 제목"])
    }
    func testDuplicateLaterAndComplexDefinitionsRejectedAndAssetsPreserved() async throws {
        let source = try await apply(.header, ["제목"], plain("본문\n다음"))
        let archive = try HWPXEditingArchive(data: source.data)
        let xml = String(decoding: try archive.data(at: "Contents/section0.xml"), as: UTF8.self)
        let node = try XCTUnwrap(HWPFormattingXML.elements(xml, name: "header").first)
        let duplicate = (xml as NSString).replacingCharacters(in: node.range, with: node.xml + node.xml)
        let complex = (xml as NSString).replacingCharacters(in: node.range, with: node.xml.replacingOccurrences(of: "</hp:run>", with: "<hp:fieldBegin id=\"9\"/></hp:run>"))
        let without = (xml as NSString).replacingCharacters(in: node.range, with: "")
        let second = try HWPXParagraphXMLPatcher.paragraphRanges(in: without)[1]
        let p = (without as NSString).substring(with: second)
        let later = (without as NSString).replacingCharacters(in: second, with: p.replacingOccurrences(of: "</hp:run>", with: "<hp:ctrl>" + node.xml + "</hp:ctrl></hp:run>"))
        for modified in [duplicate, complex, later] {
            let data = try archive.repack(replacing: ["Contents/section0.xml": Data(modified.utf8)])
            let loaded = try HWPTableStructureDocument.load(data)
            XCTAssertThrowsError(try HWPHeaderFooterEditing.validate(.init(kind: .header, texts: ["변경"], sections: [0]), source: loaded))
            XCTAssertEqual(loaded.data, data)
        }
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "mss_voucher", withExtension: "hwpx") ?? bundle.url(forResource: "mss_voucher", withExtension: "hwpx", subdirectory: "HWPXViewerFixtures"))
        let original = try HWPTableStructureDocument.load(Data(contentsOf: url))
        let changed = try await apply(.footer, ["서류 안내"], original)
        let oldArchive = try HWPXEditingArchive(data: original.data), newArchive = try HWPXEditingArchive(data: changed.data)
        for path in oldArchive.paths where path != "Contents/section0.xml" && path != "Contents/header.xml" {
            XCTAssertEqual(try oldArchive.data(at: path), try newArchive.data(at: path), path)
        }
        XCTAssertEqual(original.blocks.compactMap(\.tableLocation), changed.blocks.compactMap(\.tableLocation))
    }
    func testViewModelHeaderFooterUndoRedoPendingTextSaveAndConflict() async throws {
        for source in [try plain("본문\n둘째"), try hwp()] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + (source.data.starts(with: [0x50, 0x4b]) ? ".hwpx" : ".hwp"))
            try source.data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
            let model = HWPDocumentViewModel(fileURL: url); await model.load()
            let block = try XCTUnwrap(model.blocks.first(where: \.isEditable)); model.selectBlock(block.id); model.editorText = "저장 전 입력 😀"
            try await model.applyHeaderFooter(.init(kind: .header, texts: ["머리말"], sections: [0]))
            XCTAssertEqual(model.selectedBlock?.text, "저장 전 입력 😀")
            XCTAssertEqual(try Data(contentsOf: url), source.data)
            let after = model.blocks
            model.undo(); XCTAssertFalse(model.blocks.contains { $0.region.kind == .header }); XCTAssertTrue(model.hasUnsavedChanges)
            model.undo(); XCTAssertFalse(model.hasUnsavedChanges)
            model.redo(); model.redo(); XCTAssertEqual(model.blocks, after)
            await model.save(); XCTAssertNil(model.errorDescription); XCTAssertFalse(model.hasUnsavedChanges)
            let reopened = HWPDocumentViewModel(fileURL: url); await reopened.load(); XCTAssertEqual(reopened.blocks, after)
            try await model.applyHeaderFooter(.init(kind: .header, texts: ["새 내용"], sections: [0]))
            try source.data.write(to: url); await model.save(); XCTAssertNotNil(model.errorDescription)
            XCTAssertEqual(try Data(contentsOf: url), source.data)
        }
    }
    private func plain(_ text: String) throws -> HWPTableStructureDocument { try .load(LegacyHWPXConverter.convert(text: text)) }
    private func hwp() throws -> HWPTableStructureDocument {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "hangul_design_application", withExtension: "hwp") ?? bundle.url(forResource: "hangul_design_application", withExtension: "hwp", subdirectory: "HWPXViewerFixtures"))
        return try .load(Data(contentsOf: url))
    }
    private func region(_ source: HWPTableStructureDocument, _ kind: HWPHeaderFooterKind) -> [HWPDocumentBlock] { HWPHeaderFooterEditing.paragraphs(source.blocks, kind: kind, section: 0) }
    private func apply(_ kind: HWPHeaderFooterKind, _ texts: [String], _ source: HWPTableStructureDocument, alignment: HWPParagraphAlignment? = nil) async throws -> HWPTableStructureDocument {
        try await HWPHeaderFooterEditing.applying(.init(kind: kind, texts: texts, sections: [0], alignment: alignment), source: source, drafts: source.blocks)
    }
}
