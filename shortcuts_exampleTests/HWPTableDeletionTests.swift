import RivoDocumentEngine
import XCTest
@testable import shortcuts_example

@MainActor final class HWPTableDeletionTests: XCTestCase {
    func testDeleteOnlyCellRetainsEditableBodyAndUncommittedCellTextIsRemoved() async throws {
        for base in [try plain(""), try fixture("hangul_design_application", "hwp")] {
            let inserted = try await insert(base, rows: 1, columns: 1)
            var drafts = inserted.document.blocks
            let cell = try XCTUnwrap(drafts.firstIndex { $0.id == inserted.focusedID })
            drafts[cell] = HWPTextRunEditing.replacingText(in: drafts[cell], with: "지울 내용 😀\n두 번째 줄")
            XCTAssertTrue(HWPTableStructureEditing.available(blocks: drafts, selectedID: inserted.focusedID, layouts: inserted.document.layouts).contains(.deleteTable))
            let result = try await inserted.document.editing(.deleteTable, blocks: drafts, selectedID: inserted.focusedID)
            XCTAssertEqual(result.document.blocks.count, base.blocks.count + 2)
            XCTAssertFalse(result.document.blocks.contains { $0.text.contains("지울 내용") })
            XCTAssertTrue(HWPParagraphEditing.supports(try XCTUnwrap(result.document.blocks.first { $0.id == result.focusedID })))
            XCTAssertEqual(result.document.layouts, base.layouts)
            XCTAssertEqual(try HWPTableStructureDocument.load(result.document.serialized(result.document.blocks)).blocks, result.document.blocks)
        }
    }
    func testImportedHWPAndHWPXDeleteKeepOtherTextTablesStylesAndAssets() async throws {
        for source in [try fixture("hangul_design_application", "hwp"), try fixture("mss_voucher", "hwpx")] {
            let target = try XCTUnwrap(source.blocks.first { (try? HWPTableDeletion.plan(blocks: source.blocks, selectedID: $0.id, layouts: source.layouts)) != nil })
            let plan = try HWPTableDeletion.plan(blocks: source.blocks, selectedID: target.id, layouts: source.layouts)
            let result = try await source.editing(.deleteTable, blocks: source.blocks, selectedID: target.id)
            let retained = plan.retained(count: source.blocks.count)
            XCTAssertEqual(result.document.blocks.count, retained.count)
            for (index, previous) in retained.enumerated() { XCTAssertTrue(HWPDocumentFormatting.matches(result.document.blocks[index], source.blocks[previous])) }
            XCTAssertEqual(Set(result.document.blocks.compactMap { $0.tableLocation?.table }).count, Set(source.blocks.compactMap { $0.tableLocation?.table }).count - 1)
            switch source {
            case .hwp:
                let a = try OLECompoundFile(data: source.data), b = try OLECompoundFile(data: result.document.data)
                for path in a.streamNames where !path.hasPrefix("bodytext/") && path != "prvtext" { XCTAssertEqual(try a.stream(named: path), try b.stream(named: path), path) }
                let preview = String(decoding: try b.stream(named: "PrvText").withUnsafeBytes { Array($0.bindMemory(to: UInt16.self)) }, as: UTF16.self)
                XCTAssertEqual(preview, result.document.blocks.map(\.text).joined(separator: "\n"))
            case .hwpx:
                let a = try HWPXEditingArchive(data: source.data), b = try HWPXEditingArchive(data: result.document.data)
                XCTAssertEqual(try a.data(at: "Contents/header.xml"), try b.data(at: "Contents/header.xml"))
                for path in a.paths where path != plan.table.section && path != "Preview/PrvText.txt" { XCTAssertEqual(try a.data(at: path), try b.data(at: path), path) }
                if a.paths.contains("Preview/PrvText.txt") { XCTAssertEqual(String(decoding: try b.data(at: "Preview/PrvText.txt"), as: UTF8.self), result.document.blocks.map(\.text).joined(separator: "\n")) }
            }
        }
    }
    func testMergedMultilineTableAndRemainingTableCanBeDeletedRepeatedly() async throws {
        for base in [try plain("본문\n끝"), try fixture("hangul_design_application", "hwp")] {
            let first = try await insert(base)
            var drafts = first.document.blocks
            let i = try XCTUnwrap(drafts.firstIndex { $0.id == first.focusedID })
            drafts[i] = HWPTextRunEditing.replacingText(in: drafts[i], with: "첫 셀\n여러 줄")
            drafts[i + 1] = HWPTextRunEditing.replacingText(in: drafts[i + 1], with: "두 번째 셀")
            let merged = try await first.document.editing(.mergeRight, blocks: drafts, selectedID: first.focusedID)
            let second = try await insert(merged.document)
            let deleted = try await second.document.editing(.deleteTable, blocks: second.document.blocks, selectedID: second.focusedID)
            let surviving = try XCTUnwrap(deleted.document.blocks.first { $0.text == "첫 셀\n여러 줄" })
            XCTAssertEqual(surviving.tableLocation?.columnSpan, 2)
            let final = try await deleted.document.editing(.deleteTable, blocks: deleted.document.blocks, selectedID: surviving.id)
            XCTAssertFalse(final.document.blocks.contains { $0.text == "두 번째 셀" })
            XCTAssertEqual(Set(final.document.blocks.compactMap { $0.tableLocation?.table }).count, Set(base.blocks.compactMap { $0.tableLocation?.table }).count)
        }
    }
    func testTallTableDeletionReclaimsPagesAndKeepsPageNumbersAndFollowingBody() async throws {
        let base = try plain("앞\n표 뒤 본문")
        var settings = HWPPageSettings(base.layouts[0]); settings.height = 420
        let paper = try await HWPPageSetup.applying(.init(settings: settings, sections: [0]), source: base, drafts: base.blocks)
        let numbered = try await HWPPageNumberEditing.applying(.init(style: .init(position: "BOTTOM_CENTER", sideCharacter: "", startsAt: 7), sections: [0]), source: paper, drafts: paper.blocks)
        let inserted = try await insert(numbered, rows: 20, columns: 2)
        let pages = HWPOriginalCanvasPageBuilder.makePages(blocks: inserted.document.blocks, layouts: inserted.document.layouts)
        XCTAssertGreaterThan(pages.count, 1)
        let result = try await inserted.document.editing(.deleteTable, blocks: inserted.document.blocks, selectedID: inserted.focusedID)
        let after = HWPOriginalCanvasPageBuilder.makePages(blocks: result.document.blocks, layouts: result.document.layouts)
        XCTAssertEqual(after.count, 1); XCTAssertEqual(after[0].pageNumberText, "7")
        XCTAssertEqual(result.document.blocks.last?.text, "표 뒤 본문")
        XCTAssertLessThan(try XCTUnwrap(result.document.blocks.last?.lineLayouts.first?.verticalPositionPoints), 100)
    }
    func testInvalidSelectionAndMultipleTablesInOneOwnerAreUnavailable() async throws {
        let base = try plain("본문")
        XCTAssertThrowsError(try HWPTableDeletion.plan(blocks: base.blocks, selectedID: base.blocks[0].id, layouts: base.layouts))
        let inserted = try await insert(base)
        let package = try HWPXDocumentPackage.load(from: inserted.document.data)
        let table = try XCTUnwrap(HWPFormattingXML.elements(package.sections[0].xml, name: "tbl").first)
        let xml = (package.sections[0].xml as NSString).replacingCharacters(in: table.range, with: table.xml + table.xml)
        let duplicated = try HWPTableStructureDocument.load(HWPXEditingArchive(data: package.sourceData).repack(replacing: [package.sections[0].path: Data(xml.utf8)]))
        for cell in duplicated.blocks where cell.tableLocation != nil {
            XCTAssertThrowsError(try HWPTableDeletion.plan(blocks: duplicated.blocks, selectedID: cell.id, layouts: duplicated.layouts))
        }
        do { _ = try await inserted.document.editing(.deleteTable, blocks: inserted.document.blocks, selectedID: "missing"); XCTFail("Stale selection") } catch {}
    }
    func testHWPAnchorRemovalPreservesUnicodeAndRawCharacterStyleOffsets() async throws {
        let inserted = try await insert(fixture("hangul_design_application", "hwp"))
        let source = inserted.document
        let plan = try HWPTableDeletion.plan(blocks: source.blocks, selectedID: inserted.focusedID, layouts: source.layouts)
        let container = try OLECompoundFile(data: source.data)
        let compressed = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36) & 1 != 0
        let path = plan.table.section
        let stored = try container.stream(named: path)
        var records = try HWP5DocumentRewriter.parseRecords(compressed ? HWP5TextExtractor.inflateRawDeflate(stored, maximumBytes: HWP5TextExtractor.maximumSectionBytes) : stored)
        let headers = records.indices.filter { records[$0].tag == 0x42 }
        let root = headers[source.blocks[plan.owner].paragraphIndex]
        let text = try XCTUnwrap(records.indices.dropFirst(root + 1).first { records[$0].tag == 0x43 })
        let shape = try XCTUnwrap(records.indices.dropFirst(root + 1).first { records[$0].tag == 0x44 })
        let prefix = "앞😀", suffix = "뒤 한글"
        var bytes = Data(prefix.utf16.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] })
        bytes.append(records[text].payload.prefix(16)); bytes.append(Data((suffix + "\r").utf16.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] }))
        records[text].payload = bytes
        records[root].payload.hwpWriterSetUInt32(UInt32(bytes.count / 2), at: 0)
        records[root].payload.hwpWriterSetUInt16(3, at: 12)
        var shapes = Data()
        for (offset, style) in [(0, 0), (prefix.utf16.count, 1), (prefix.utf16.count + 8, 0)] {
            shapes.hwpWriterAppendUInt32(UInt32(offset)); shapes.hwpWriterAppendUInt32(UInt32(style))
        }
        records[shape].payload = shapes
        let expanded = records.reduce(into: Data()) { $0.append($1.serialized()) }
        let edited = try HWPTableStructureDocument.load(container.serialized(replacing: [path: compressed ? HWP5DocumentRewriter.rawDeflate(expanded) : expanded]))
        let result = try await edited.editing(.deleteTable, blocks: edited.blocks, selectedID: inserted.focusedID)
        XCTAssertEqual(result.document.blocks[plan.owner].text, prefix + suffix)
        XCTAssertTrue(HWPDocumentFormatting.matches(result.document.blocks[plan.owner], edited.blocks[plan.owner]))
    }
    func testViewModelTableDeletionUndoRedoPendingInputSaveAndConflict() async throws {
        for base in [try plain("앞\n뒤"), try fixture("hangul_design_application", "hwp")] {
            let initial = try await insert(base)
            let inserted = try await initial.document.editing(.mergeRight, blocks: initial.document.blocks, selectedID: initial.focusedID)
            var styled = inserted.document.blocks
            let i = try XCTUnwrap(styled.firstIndex { $0.id == inserted.focusedID })
            styled[i] = HWPTextRunEditing.replacingText(in: styled[i], with: "원래 글자")
            styled[i] = HWPDocumentFormatting.apply(.bold(true), to: styled[i], range: .init(location: 0, length: styled[i].text.utf16.count))
            var fill = HWPCellFormat(styled[i].tableLocation!); fill.setFill(0xFFF2CC); fill.vertical = .center
            let previous = styled[i]; styled[i] = HWPCellFormatting.apply(fill, to: styled[i])
            styled = HWPCellFormatting.propagating(styled[i], from: previous, in: styled)
            let source = try HWPTableStructureDocument.load(inserted.document.serialized(styled))
            let ext = source.data.starts(with: [0x50, 0x4b]) ? "hwpx" : "hwp"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
            try source.data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
            let model = HWPDocumentViewModel(fileURL: url); await model.load()
            model.selectBlock(inserted.focusedID); model.editorText = "삭제 직전 😀"
            _ = try await model.editTable(.deleteTable, selectedID: inserted.focusedID)
            let deleted = model.blocks
            XCTAssertTrue(model.hasUnsavedChanges); XCTAssertEqual(try Data(contentsOf: url), source.data)
            model.undo(); XCTAssertEqual(model.selectedBlock?.text, "삭제 직전 😀")
            XCTAssertEqual(model.selectedBlock?.tableLocation?.columnSpan, 2)
            XCTAssertTrue(HWPCellFormatting.matches(try XCTUnwrap(model.selectedBlock), source.blocks[i]))
            XCTAssertTrue(HWPDocumentFormatting.run(at: 0, in: try XCTUnwrap(model.selectedBlock)).isBold)
            model.undo(); XCTAssertFalse(model.hasUnsavedChanges)
            model.redo(); model.redo(); XCTAssertEqual(model.blocks, deleted)
            await model.save(); XCTAssertNil(model.errorDescription); XCTAssertFalse(model.hasUnsavedChanges)
            XCTAssertEqual(try HWPTableStructureDocument.load(Data(contentsOf: url)).blocks, deleted)
            // Saving starts a fresh history in the current editor. Reload the
            // original table to check a separate deletion/save conflict.
            try source.data.write(to: url)
            let conflict = HWPDocumentViewModel(fileURL: url); await conflict.load()
            _ = try await conflict.editTable(.deleteTable, selectedID: inserted.focusedID)
            try base.data.write(to: url); await conflict.save()
            XCTAssertNotNil(conflict.errorDescription); XCTAssertEqual(try Data(contentsOf: url), base.data)
        }
    }
    private func insert(_ source: HWPTableStructureDocument, rows: Int = 2, columns: Int = 2) async throws -> HWPTableStructureDocument.Result {
        let block = try XCTUnwrap(source.blocks.first { HWPParagraphEditing.supports($0) && $0.presentation.list == nil })
        let selection = try XCTUnwrap(HWPTableInsertion.selection(blocks: source.blocks, selectedID: block.id, range: .init(location: block.text.utf16.count, length: 0), layouts: source.layouts))
        return try await HWPTableInsertion.applying(.init(selection: selection, rows: rows, columns: columns), source: source, drafts: source.blocks)
    }
    private func plain(_ text: String) throws -> HWPTableStructureDocument { try .load(LegacyHWPXConverter.convert(text: text)) }
    private func fixture(_ name: String, _ ext: String) throws -> HWPTableStructureDocument {
        let bundle = Bundle(for: Self.self)
        return try .load(Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: ext) ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "HWPXViewerFixtures"))))
    }
}
