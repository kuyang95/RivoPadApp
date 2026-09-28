import XCTest
@testable import shortcuts_example

@MainActor
final class HWPPageSetupTests: XCTestCase {
    func testInvalidPaperMarginsAndUnknownSectionsAreRejected() throws {
        let source = try plain("쪽 설정"), original = HWPPageSettings(source.layouts[0])
        for value in [Double.nan, .infinity, -1, 0, 71, 2_001] {
            var s = original; s.width = value
            XCTAssertThrowsError(try HWPPageSetupWriter.apply(.init(settings: s, sections: [0]), to: source))
        }
        for value in [Double.nan, -1, original.width] {
            var s = original; s.left = value
            XCTAssertFalse(s.isValid)
        }
        var s = original; s.top = 250; s.bottom = 250; s.header = 200; s.footer = 200
        XCTAssertFalse(s.isValid)
        XCTAssertThrowsError(try HWPPageSetupWriter.apply(.init(settings: original, sections: []), to: source))
        XCTAssertThrowsError(try HWPPageSetupWriter.apply(.init(settings: original, sections: [9]), to: source))
    }

    func testNewHWPXInstallsPagePropertiesWithoutChangingTextAndCanEditAgain() async throws {
        let source = try plain("한글 😀 첫 문단\n두 번째"), settings = a5(source.layouts[0], landscape: true)
        let changed = try await HWPPageSetup.applying(.init(settings: settings, sections: [0]), source: source, drafts: source.blocks)
        XCTAssertTrue(settings.matches(changed.layouts[0])); XCTAssertTrue(changed.layouts[0].isLandscape)
        XCTAssertEqual(changed.blocks.map(\.text), source.blocks.map(\.text))
        XCTAssertTrue(changed.blocks.allSatisfy(\.isEditable))
        let archive = try HWPXEditingArchive(data: changed.data)
        let xml = String(decoding: try archive.data(at: "Contents/section0.xml"), as: UTF8.self)
        XCTAssertEqual(try HWPFormattingXML.elements(xml, name: "secpr").count, 1)
        XCTAssertEqual(try HWPFormattingXML.elements(xml, name: "pagepr").count, 1)
        var drafts = changed.blocks
        drafts[0] = HWPTextRunEditing.replacingText(in: drafts[0], with: "쪽 설정 후 입력")
        let saved = try HWPTableStructureDocument.load(changed.serialized(drafts))
        XCTAssertEqual(saved.blocks[0].text, "쪽 설정 후 입력"); XCTAssertTrue(settings.matches(saved.layouts[0]))
    }

    func testHWPPageDefinitionKeepsGutterBindingBitsOtherRecordsAndStreams() throws {
        let source = try HWPTableStructureDocument.load(file("hangul_design_application", "hwp"))
        var settings = HWPPageSettings(source.layouts[0]); settings.orient(landscape: !settings.isLandscape); settings.left = 40
        let changed = try HWPPageSetupWriter.apply(.init(settings: settings, sections: [source.layouts[0].sectionIndex]), to: source)
        let reopened = try HWPTableStructureDocument.load(changed)
        XCTAssertTrue(settings.matches(reopened.layouts[0]))
        XCTAssertEqual(reopened.blocks, source.blocks)
        let old = try OLECompoundFile(data: source.data), new = try OLECompoundFile(data: changed)
        let compressed = try old.stream(named: "FileHeader").hwpWriterUInt32(at: 36) & 1 != 0
        for path in old.streamNames {
            let a = try old.stream(named: path), b = try new.stream(named: path)
            if path == "bodytext/section0" {
                let ar = try HWP5DocumentRewriter.parseRecords(compressed ? HWP5TextExtractor.inflateRawDeflate(a, maximumBytes: HWP5TextExtractor.maximumSectionBytes) : a)
                let br = try HWP5DocumentRewriter.parseRecords(compressed ? HWP5TextExtractor.inflateRawDeflate(b, maximumBytes: HWP5TextExtractor.maximumSectionBytes) : b)
                XCTAssertEqual(ar.count, br.count)
                for (a, b) in zip(ar, br) {
                    if a.tag == 0x49 {
                        XCTAssertEqual(a.payload.subdata(in: 32..<36), b.payload.subdata(in: 32..<36))
                        XCTAssertEqual(try a.payload.hwpWriterUInt32(at: 36) & ~1, try b.payload.hwpWriterUInt32(at: 36) & ~1)
                    } else { XCTAssertEqual(a.serialized(), b.serialized()) }
                }
            } else { XCTAssertEqual(a, b, path) }
        }
    }

    func testCurrentSectionOnlyAndWholeDocumentRespectNonSequentialSectionIDs() async throws {
        let base = try plain("구역 내용")
        let archive = try HWPXEditingArchive(data: base.data)
        let xml = try archive.data(at: "Contents/section0.xml")
        let manifest = "<opf:package xmlns:opf=\"http://www.idpf.org/2007/opf\"><opf:manifest><opf:item id=\"first\" href=\"section0.xml\"/><opf:item id=\"second\" href=\"section7.xml\"/></opf:manifest><opf:spine><opf:itemref idref=\"first\"/><opf:itemref idref=\"second\"/></opf:spine></opf:package>"
        let data = try archive.repack(replacing: ["Contents/section7.xml": xml, "Contents/content.hpf": Data(manifest.utf8)])
        let source = try HWPTableStructureDocument.load(data)
        XCTAssertEqual(source.layouts.map(\.sectionIndex), [0, 7])
        let settings = a5(source.layouts[1], landscape: true)
        let first = try await HWPPageSetup.applying(.init(settings: settings, sections: [7]), source: source, drafts: source.blocks)
        XCTAssertEqual(first.layouts[0], source.layouts[0]); XCTAssertTrue(settings.matches(first.layouts[1]))
        XCTAssertEqual(try HWPXEditingArchive(data: first.data).data(at: "Contents/section0.xml"), xml)
        let all = try await HWPPageSetup.applying(.init(settings: settings, sections: [0, 7]), source: first, drafts: first.blocks)
        XCTAssertTrue(all.layouts.allSatisfy(settings.matches))
        XCTAssertEqual(all.blocks.map(\.text), source.blocks.map(\.text))
    }

    func testNarrowPaperRewrapsAndPaginatesInsideHeaderFooterBands() async throws {
        let text = String(repeating: "폭이 달라지는 한글 문장과 숫자 12345. ", count: 180)
        let source = try plain(text + "\n마지막 문단"), settings = a5(source.layouts[0])
        let changed = try await HWPPageSetup.applying(.init(settings: settings, sections: [0]), source: source, drafts: source.blocks)
        let pages = HWPOriginalCanvasPageBuilder.makePages(blocks: changed.blocks, layouts: changed.layouts)
        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertEqual(changed.blocks.map(\.text), source.blocks.map(\.text))
        let height = settings.height - settings.top - settings.bottom - settings.header - settings.footer
        let width = settings.width - settings.left - settings.right
        for page in pages {
            for block in page.bodyBlocks where block.tableLocation == nil {
                for line in block.lineLayouts {
                    XCTAssertLessThanOrEqual(line.widthPoints, width + 0.03)
                    XCTAssertLessThanOrEqual(line.verticalPositionPoints + line.lineHeightPoints, height + 0.03)
                }
            }
        }
        let rebuilt = pages.flatMap(\.bodyBlocks).filter { HWPInlineParagraphGeometry.sourceID($0.id) == changed.blocks[0].id }.flatMap(\.lineLayouts).map(\.text).joined()
        XCTAssertEqual(rebuilt, text)
    }

    func testExplicitPageBreakAndCharacterStylesSurviveChangingPaper() async throws {
        let base = try plain("첫 문단\n새 쪽 문단")
        let archive = try HWPXEditingArchive(data: base.data)
        let original = String(decoding: try archive.data(at: "Contents/section0.xml"), as: UTF8.self)
        let paragraph = try HWPFormattingXML.elements(original, name: "p")[1]
        let xml = (original as NSString).replacingCharacters(in: paragraph.range,
            with: try HWPFormattingXML.setAttribute(paragraph.xml, "pageBreak", "1"))
        let source = try HWPTableStructureDocument.load(archive.repack(replacing: ["Contents/section0.xml": Data(xml.utf8)]))
        XCTAssertTrue(source.blocks[1].presentation.pageBreakBefore)
        var drafts = source.blocks
        drafts[0] = HWPDocumentFormatting.apply(.bold(true), to: drafts[0], range: NSRange(location: 0, length: 2))
        let changed = try await HWPPageSetup.applying(.init(settings: a5(source.layouts[0]), sections: [0]), source: source, drafts: drafts)
        XCTAssertTrue(changed.blocks[1].presentation.pageBreakBefore)
        XCTAssertTrue(changed.blocks[0].presentation.textRuns.contains { $0.isBold })
        XCTAssertEqual(HWPOriginalCanvasPageBuilder.makePages(blocks: changed.blocks, layouts: changed.layouts).count, 2)
    }

    func testRealHWPAndHWPXKeepAssetsTableSizesPendingInputAndRepeatedSave() async throws {
        for (name, ext) in [("hangul_design_application", "hwp"), ("mss_voucher", "hwpx")] {
            var source = try HWPTableStructureDocument.load(file(name, ext))
            let initial = source
            var drafts = source.blocks
            let index = try XCTUnwrap(drafts.firstIndex { $0.isEditable && !$0.text.isEmpty })
            drafts[index] = HWPTextRunEditing.replacingText(in: drafts[index], with: "쪽 편집 보존")
            for landscape in [true, false] {
                var settings = HWPPageSettings(source.layouts[0]); settings.orient(landscape: landscape); settings.left = 40
                source = try await HWPPageSetup.applying(.init(settings: settings, sections: [source.layouts[0].sectionIndex]), source: source, drafts: drafts)
                XCTAssertTrue(settings.matches(source.layouts[0])); XCTAssertEqual(source.blocks[index].text, "쪽 편집 보존")
                XCTAssertEqual(source.blocks.compactMap { $0.tableLocation?.cellWidthPoints }, initial.blocks.compactMap { $0.tableLocation?.cellWidthPoints })
                drafts = source.blocks
                let saved = try HWPTableStructureDocument.load(source.serialized(drafts))
                XCTAssertEqual(saved.layouts, source.layouts)
            }
            if ext == "hwpx" {
                let a = try HWPXEditingArchive(data: initial.data), b = try HWPXEditingArchive(data: source.data)
                for path in a.paths where path.hasPrefix("BinData/") || path == "Contents/header.xml" { XCTAssertEqual(try a.data(at: path), try b.data(at: path), path) }
            } else {
                let a = try OLECompoundFile(data: initial.data), b = try OLECompoundFile(data: source.data)
                for path in a.streamNames where !path.hasPrefix("bodytext/") && path != "prvtext" { XCTAssertEqual(try a.stream(named: path), try b.stream(named: path), path) }
            }
        }
    }

    func testHWPXKeepsGutterAndUnknownPageMetadataAndRejectsMultipleColumns() throws {
        let base = try plain("쪽 설정"), archive = try HWPXEditingArchive(data: base.data)
        let xml = String(decoding: try archive.data(at: "Contents/section0.xml"), as: UTF8.self)
        let settingsXML = "<hp:secPr custom=\"keep\"><hp:pagePr width=\"59528\" height=\"84189\" landscape=\"WIDELY\" gutterType=\"LEFT_ONLY\" custom=\"page\"><hp:margin left=\"4000\" right=\"4000\" top=\"4000\" bottom=\"4000\" header=\"1000\" footer=\"1000\" gutter=\"300\" custom=\"margin\"/></hp:pagePr></hp:secPr>"
        let changedXML = xml.replacingOccurrences(of: "<hp:t ", with: settingsXML + "<hp:t ")
        let source = try HWPTableStructureDocument.load(archive.repack(replacing: ["Contents/section0.xml": Data(changedXML.utf8)]))
        let request = HWPPageSetupRequest(settings: a5(source.layouts[0]), sections: [0])
        let changed = try HWPPageSetupWriter.apply(request, to: source)
        let result = String(decoding: try HWPXEditingArchive(data: changed).data(at: "Contents/section0.xml"), as: UTF8.self)
        for value in ["custom=\"keep\"", "custom=\"page\"", "custom=\"margin\"", "gutter=\"300\"", "gutterType=\"LEFT_ONLY\""] { XCTAssertTrue(result.contains(value)) }
        let multi = changedXML.replacingOccurrences(of: "</hp:secPr>", with: "<hp:colPr colCount=\"2\" sameGap=\"1000\"/></hp:secPr>")
        let columns = try HWPTableStructureDocument.load(archive.repack(replacing: ["Contents/section0.xml": Data(multi.utf8)]))
        XCTAssertEqual(columns.layouts[0].columnLayout.columns.count, 2)
        XCTAssertThrowsError(try HWPPageSetupWriter.apply(request, to: columns))
    }

    func testTableAndFollowingBodyRemainSeparateAfterPaperChangeAndFurtherTableEditing() async throws {
        let base = try plain("\n표 뒤"), archive = try HWPXEditingArchive(data: base.data)
        let xml = String(decoding: try archive.data(at: "Contents/section0.xml"), as: UTF8.self)
        let paragraph = try HWPFormattingXML.elements(xml, name: "p")[0]
        let patched = (xml as NSString).replacingCharacters(in: paragraph.range,
            with: paragraph.xml.replacingOccurrences(of: "</hp:run>", with: HWPCellFormattingTests.tableXML + "</hp:run>"))
        let source = try HWPTableStructureDocument.load(archive.repack(replacing: ["Contents/section0.xml": Data(patched.utf8)]))
        var settings = a5(source.layouts[0], landscape: true); settings.header = 0; settings.footer = 0
        let changed = try await HWPPageSetup.applying(.init(settings: settings, sections: [0]), source: source, drafts: source.blocks)
        let first = try XCTUnwrap(changed.blocks.first { $0.tableLocation != nil })
        let bottom = (first.tableLocation?.tableAnchor?.verticalPositionPoints ?? 0) + 180
        XCTAssertGreaterThanOrEqual(changed.blocks.last!.lineLayouts[0].verticalPositionPoints, bottom)
        let resized = try await changed.editing(.resize, blocks: changed.blocks, selectedID: first.id, dimensions: .init(widthPoints: 90))
        XCTAssertTrue(settings.matches(resized.document.layouts[0]))
        XCTAssertEqual(resized.document.blocks.map(\.text), source.blocks.map(\.text))
    }

    func testPageSetupCommitsPendingParagraphInsertionAndKeepsItEditable() async throws {
        let source = try plain("한글 문단")
        let split = try XCTUnwrap(HWPParagraphEditing.apply(.split(NSRange(location: 2, length: 0)), draft: source.blocks[0], to: source.blocks))
        let changed = try await HWPPageSetup.applying(.init(settings: a5(source.layouts[0]), sections: [0]), source: source, drafts: split.blocks)
        XCTAssertEqual(changed.blocks.map(\.text), ["한글", " 문단"])
        let joined = try XCTUnwrap(HWPParagraphEditing.apply(.mergeBackward, draft: changed.blocks[1], to: changed.blocks))
        let saved = try HWPTableStructureDocument.load(changed.serialized(joined.blocks))
        XCTAssertEqual(saved.blocks.map(\.text), ["한글 문단"]); XCTAssertEqual(saved.layouts, changed.layouts)
    }

    func testViewModelPageSetupUndoRedoRestoresLayoutAndUnsavedText() async throws {
        let source = try plain("첫 문단\n둘째 문단"), url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        try source.data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url); await model.load()
        model.commitInlineBlock(HWPTextRunEditing.replacingText(in: model.blocks[0], with: "입력 보존"))
        let typed = model.blocks, old = model.pageLayouts
        try await model.applyPageSetup(.init(settings: a5(old[0], landscape: true), sections: [0]))
        let changed = model.blocks, layout = model.pageLayouts
        XCTAssertEqual(try Data(contentsOf: url), source.data)
        model.undo(); XCTAssertEqual(model.blocks, typed); XCTAssertEqual(model.pageLayouts, old); XCTAssertTrue(model.hasUnsavedChanges)
        model.undo(); XCTAssertFalse(model.hasUnsavedChanges)
        model.redo(); model.redo(); XCTAssertEqual(model.blocks, changed); XCTAssertEqual(model.pageLayouts, layout)
        await model.save(); XCTAssertNil(model.errorDescription); XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertEqual(try HWPXDocumentPackage.load(from: Data(contentsOf: url)).pageLayouts, layout)
    }

    func testViewModelHWPPageSetupRepeatedSaveAndConflict() async throws {
        let data = try file("hangul_design_application", "hwp"), url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwp")
        try data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url); await model.load()
        let original = model.pageLayouts
        for landscape in [true, false] {
            var settings = HWPPageSettings(model.pageLayouts[0]); settings.orient(landscape: landscape); settings.left = 40
            try await model.applyPageSetup(.init(settings: settings, sections: [model.pageLayouts[0].sectionIndex]))
            let after = model.pageLayouts; model.undo(); model.redo(); XCTAssertEqual(model.pageLayouts, after)
            await model.save(); XCTAssertNil(model.errorDescription); XCTAssertFalse(model.hasUnsavedChanges)
        }
        try await model.applyPageSetup(.init(settings: HWPPageSettings(original[0]), sections: [original[0].sectionIndex]))
        try data.write(to: url); await model.save()
        XCTAssertNotNil(model.errorDescription); XCTAssertEqual(try Data(contentsOf: url), data)
    }

    private func plain(_ text: String) throws -> HWPTableStructureDocument { try .load(LegacyHWPXConverter.convert(text: text)) }
    private func a5(_ layout: HWPDocumentPageLayout, landscape: Bool = false) -> HWPPageSettings {
        var s = HWPPageSettings(layout), unit = HWPPageSettings.pointsPerMM
        s.width = 148 * unit; s.height = 210 * unit; s.left = 10 * unit; s.right = 10 * unit
        s.top = 10 * unit; s.bottom = 10 * unit; s.header = 5 * unit; s.footer = 5 * unit
        s.orient(landscape: landscape); return s
    }
    private func file(_ name: String, _ ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: ext) ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "HWPXViewerFixtures")))
    }
}
