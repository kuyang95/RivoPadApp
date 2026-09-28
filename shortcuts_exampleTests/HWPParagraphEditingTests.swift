import Foundation
import XCTest
import ZIPFoundation
import SwiftUI
@testable import shortcuts_example

@MainActor
final class HWPParagraphEditingTests: XCTestCase {
    func testSplitSelectionAndMergePreserveKoreanEmojiAndCharacterStyles() throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "앞 한글 👨‍👩‍👧‍👦 뒤"))
        let range = (package.blocks[0].text as NSString).range(of: "한글 👨‍👩‍👧‍👦")
        let styled = HWPDocumentFormatting.apply(.bold(true), to: package.blocks[0], range: range)
        let split = try XCTUnwrap(HWPParagraphEditing.apply(.split(NSRange(location: range.location, length: 0)), draft: styled, to: [styled]))
        XCTAssertEqual(split.blocks.map(\.text), ["앞 ", "한글 👨‍👩‍👧‍👦 뒤"])
        XCTAssertTrue(HWPDocumentFormatting.run(at: 0, in: split.blocks[1]).isBold)
        XCTAssertFalse(HWPDocumentFormatting.run(at: split.blocks[1].text.utf16.count - 1, in: split.blocks[1]).isBold)
        let merged = try XCTUnwrap(HWPParagraphEditing.apply(.mergeBackward, draft: split.blocks[1], to: split.blocks))
        XCTAssertTrue(HWPDocumentFormatting.matches(styled, merged.blocks[0]))
        XCTAssertEqual(merged.caret, range.location)
        let replaced = try XCTUnwrap(HWPParagraphEditing.apply(.split(range), draft: styled, to: [styled]))
        XCTAssertEqual(replaced.blocks.map(\.text), ["앞 ", " 뒤"])
        let invalid = (styled.text as NSString).range(of: "👨").location + 1
        XCTAssertNil(HWPParagraphEditing.apply(.split(NSRange(location: invalid, length: 0)), draft: styled, to: [styled]))
    }

    func testRepeatedEnterAndBackspaceRoundTripHWPXWithoutDuplicatingSectionProperties() throws {
        var package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "한글 본문\n뒤 문단"))
        let path = package.sections[0].path
        let section = package.sections[0].xml
        let run = try XCTUnwrap(HWPXParagraphXMLPatcher.tagTokens(in: section).first { $0.localName == "run" && !$0.isClosing })
        let withProperties = (section as NSString).replacingCharacters(in: NSRange(location: NSMaxRange(run.range), length: 0),
            with: "<hp:secPr><hp:pagePr width=\"59528\" height=\"84186\"/></hp:secPr>")
        package = try HWPXDocumentPackage.load(from: HWPXEditingArchive(data: package.sourceData).repack(replacing: [path: Data(withProperties.utf8)]))
        XCTAssertTrue(package.blocks[0].keepsParagraphBoundary)
        var result = try XCTUnwrap(HWPParagraphEditing.apply(.split(NSRange(location: 2, length: 0)), draft: package.blocks[0], to: package.blocks))
        XCTAssertTrue(result.blocks[0].keepsParagraphBoundary)
        XCTAssertFalse(result.blocks[1].keepsParagraphBoundary)
        result = try XCTUnwrap(HWPParagraphEditing.apply(.split(NSRange(location: 0, length: 0)), draft: result.blocks[1], to: result.blocks))
        XCTAssertEqual(result.blocks.map(\.text), ["한글", "", " 본문", "뒤 문단"])
        let saved = try package.serializedData(applying: result.blocks)
        package = try HWPXDocumentPackage.load(from: saved)
        XCTAssertEqual(package.blocks.map(\.text), result.blocks.map(\.text))
        XCTAssertEqual(try HWPFormattingXML.elements(package.sections[0].xml, name: "secpr").count, 1)
        let ids = try HWPFormattingXML.elements(package.sections[0].xml, name: "p").map { try HWPFormattingXML.attribute($0.xml, "id") }
        XCTAssertEqual(Set(ids).count, ids.count)
        result = try XCTUnwrap(HWPParagraphEditing.apply(.mergeBackward, draft: package.blocks[2], to: package.blocks))
        result = try XCTUnwrap(HWPParagraphEditing.apply(.mergeBackward, draft: result.blocks[1], to: result.blocks))
        XCTAssertEqual(try HWPXDocumentPackage.load(from: package.serializedData(applying: result.blocks)).blocks.map(\.text), ["한글 본문", "뒤 문단"])
    }

    func testHWPInsertionBeforeTablesKeepsEveryCellAndBinaryAsset() throws {
        let source = try fixture("hangul_design_application", ext: "hwp")
        let original = try HWP5StructuredDocumentParser.parse(from: source)
        let index = try XCTUnwrap(original.blocks.firstIndex { HWPParagraphEditing.supports($0) && $0.text.count > 4 })
        let draft = HWPDocumentFormatting.apply(.bold(true), to: original.blocks[index], range: NSRange(location: 0, length: 2))
        let result = try XCTUnwrap(HWPParagraphEditing.apply(.split(NSRange(location: 2, length: 0)), draft: draft, to: original.blocks))
        let saved = try HWP5DocumentRewriter.rewrite(sourceData: source, originalBlocks: original.blocks, editedBlocks: result.blocks)
        let reopened = try HWP5StructuredDocumentParser.parse(from: saved)
        XCTAssertEqual(reopened.blocks.map(\.text), result.blocks.map(\.text))
        XCTAssertEqual(reopened.tableCount, original.tableCount)
        XCTAssertEqual(reopened.tableCellCount, original.tableCellCount)
        XCTAssertTrue(HWPDocumentFormatting.matches(reopened.blocks[index], result.blocks[index]))
        XCTAssertTrue(HWPDocumentFormatting.matches(reopened.blocks[index + 1], result.blocks[index + 1]))
        for (before, after) in zip(original.blocks.filter { $0.tableLocation != nil }, reopened.blocks.filter { $0.tableLocation != nil }) {
            XCTAssertEqual(before.tableLocation, after.tableLocation)
            XCTAssertTrue(HWPDocumentFormatting.matches(before, after))
        }
        let beforeOLE = try OLECompoundFile(data: source), afterOLE = try OLECompoundFile(data: saved)
        for path in beforeOLE.streamNames where !path.hasPrefix("bodytext/") && path != "docinfo" && path != "prvtext" {
            XCTAssertEqual(try beforeOLE.stream(named: path), try afterOLE.stream(named: path), path)
        }
        let merge = try XCTUnwrap(HWPParagraphEditing.apply(.mergeBackward, draft: reopened.blocks[index + 1], to: reopened.blocks))
        let twice = try HWP5DocumentRewriter.rewrite(sourceData: saved, originalBlocks: reopened.blocks, editedBlocks: merge.blocks)
        XCTAssertEqual(try HWP5StructuredDocumentParser.parse(from: twice).blocks.map(\.text), original.blocks.map(\.text))
    }

    func testHWPXInsertionKeepsOfficialDocumentTablesAndAssets() throws {
        let data = try fixture("mss_voucher", ext: "hwpx")
        let package = try HWPXDocumentPackage.load(from: data)
        let index = try XCTUnwrap(package.blocks.firstIndex { HWPParagraphEditing.supports($0) && $0.text.count > 2 })
        let result = try XCTUnwrap(HWPParagraphEditing.apply(.split(NSRange(location: 1, length: 0)), draft: package.blocks[index], to: package.blocks))
        let saved = try package.serializedData(applying: result.blocks)
        let reopened = try HWPXDocumentPackage.load(from: saved)
        XCTAssertEqual(reopened.blocks.map(\.text), result.blocks.map(\.text))
        for (old, new) in zip(package.blocks.filter { $0.tableLocation != nil }, reopened.blocks.filter { $0.tableLocation != nil }) {
            XCTAssertEqual(old.tableLocation, new.tableLocation)
            XCTAssertTrue(HWPDocumentFormatting.matches(old, new))
        }
        let oldZIP = try Archive(data: data, accessMode: .read), newZIP = try Archive(data: saved, accessMode: .read)
        for entry in oldZIP where entry.path.hasPrefix("BinData/") {
            var old = Data(), new = Data()
            _ = try oldZIP.extract(entry) { old.append($0) }
            _ = try newZIP.extract(XCTUnwrap(newZIP[entry.path])) { new.append($0) }
            XCTAssertEqual(old, new, entry.path)
        }
    }

    func testEmptyHWPParagraphCanBeSplitMergedAndRefreshItsTextPreview() throws {
        let fixture = try fixture("hangul_design_application", ext: "hwp")
        let original = try HWP5StructuredDocumentParser.parse(from: fixture)
        let index = try XCTUnwrap(original.blocks.firstIndex { HWPParagraphEditing.supports($0) && !$0.text.isEmpty })
        var emptied = original.blocks
        emptied[index] = HWPTextRunEditing.replacingText(in: emptied[index], with: "")
        let data = try HWP5DocumentRewriter.rewrite(sourceData: fixture, originalBlocks: original.blocks, editedBlocks: emptied)
        let empty = try HWP5StructuredDocumentParser.parse(from: data)
        let split = try XCTUnwrap(HWPParagraphEditing.apply(.split(NSRange(location: 0, length: 0)), draft: empty.blocks[index], to: empty.blocks))
        let saved = try HWP5DocumentRewriter.rewrite(sourceData: data, originalBlocks: empty.blocks, editedBlocks: split.blocks)
        let reopened = try HWP5StructuredDocumentParser.parse(from: saved)
        XCTAssertEqual(reopened.blocks.count, empty.blocks.count + 1)
        XCTAssertEqual(reopened.blocks[index].text, "")
        XCTAssertEqual(reopened.blocks[index + 1].text, "")
        let preview = try OLECompoundFile(data: saved).stream(named: "PrvText")
        XCTAssertEqual(String(data: preview, encoding: .utf16LittleEndian), split.blocks.filter { $0.region.kind == .body }.map(\.text).joined(separator: "\n"))
        let merged = try XCTUnwrap(HWPParagraphEditing.apply(.mergeBackward, draft: reopened.blocks[index + 1], to: reopened.blocks))
        let restored = try HWP5DocumentRewriter.rewrite(sourceData: saved, originalBlocks: reopened.blocks, editedBlocks: merged.blocks)
        XCTAssertEqual(try HWP5StructuredDocumentParser.parse(from: restored).blocks.map(\.text), empty.blocks.map(\.text))
    }

    func testTableCellEnterAndBackspaceRoundTripInBothFormats() throws {
        let hwpx = try tableDocument()
        let hwp = try HWPTableStructureDocument.load(fixture("hangul_design_application", ext: "hwp"))
        for source in [hwpx, hwp] {
            let target = try XCTUnwrap(source.blocks.first {
                HWPParagraphEditing.supportsCellParagraph($0) && $0.tableLocation?.parent == nil
                    && $0.text.utf16.count > 2
            })
            let location = try XCTUnwrap(target.tableLocation)
            let beforeCell = source.blocks.filter { HWPCellFormatting.sameCell($0, target) }
                .sorted { $0.tableLocation!.paragraph < $1.tableLocation!.paragraph }
            let range = NSRange(location: 1, length: 0)
            let split = try XCTUnwrap(HWPParagraphEditing.apply(.split(range), draft: target, to: source.blocks))
            let flowed = HWPParagraphEditing.reflow(split, before: source.blocks, draft: target,
                operation: .split(range), layouts: source.layouts)
            let reopened = try HWPTableStructureDocument.load(source.serialized(flowed))
            let splitCell = reopened.blocks.filter {
                $0.tableLocation?.table == location.table && $0.tableLocation?.parent == location.parent
                    && $0.tableLocation?.row == location.row && $0.tableLocation?.column == location.column
            }.sorted { $0.tableLocation!.paragraph < $1.tableLocation!.paragraph }
            XCTAssertEqual(splitCell.count, beforeCell.count + 1)
            XCTAssertEqual(splitCell.map { $0.tableLocation!.paragraph }, Array(0..<splitCell.count))
            XCTAssertEqual(splitCell[location.paragraph].text + splitCell[location.paragraph + 1].text, target.text)
            let second = splitCell[location.paragraph + 1]
            let merged = try XCTUnwrap(HWPParagraphEditing.apply(.mergeBackward, draft: second, to: reopened.blocks))
            let mergedFlow = HWPParagraphEditing.reflow(merged, before: reopened.blocks, draft: second,
                operation: .mergeBackward, layouts: reopened.layouts)
            let restored = try HWPTableStructureDocument.load(reopened.serialized(mergedFlow))
            XCTAssertEqual(restored.blocks.map(\.text), source.blocks.map(\.text))
            let restoredCell = restored.blocks.filter {
                $0.tableLocation?.table == location.table && $0.tableLocation?.parent == location.parent
                    && $0.tableLocation?.row == location.row && $0.tableLocation?.column == location.column
            }.sorted { $0.tableLocation!.paragraph < $1.tableLocation!.paragraph }
            XCTAssertEqual(restoredCell.count, beforeCell.count)
            XCTAssertEqual(restoredCell.map { $0.tableLocation!.paragraph }, Array(0..<restoredCell.count))
        }
    }

    func testReflowPushesFollowingParagraphsAcrossPagesAndPersistsPositions() throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "첫 문단\n뒤 문단"))
        let initial = HWPFlowLayout.resolvingMissingLines(package.blocks, layout: package.pageLayouts[0])
        var edited = initial
        edited[0] = HWPTextRunEditing.replacingText(in: edited[0], with: String(repeating: "한글 문단의 길이가 늘어나면 다음 쪽으로 이어집니다. ", count: 140))
        edited = HWPFlowLayout.reflowingBody(edited, before: initial, startingAt: edited[0].id, layouts: package.pageLayouts)
        let pages = HWPOriginalCanvasPageBuilder.makePages(blocks: edited, layouts: package.pageLayouts)
        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertTrue(edited[0].lineLayouts.contains { $0.startsPage })
        XCTAssertGreaterThanOrEqual(edited[1].lineLayouts[0].verticalPositionPoints, edited[0].lineLayouts.last!.verticalPositionPoints)
        let reopened = try HWPXDocumentPackage.load(from: package.serializedData(applying: edited))
        XCTAssertEqual(reopened.blocks.map(\.text), edited.map(\.text))
        XCTAssertEqual(HWPOriginalCanvasPageBuilder.makePages(blocks: reopened.blocks, layouts: reopened.pageLayouts).count, pages.count)
        var shortened = edited
        shortened[0] = HWPTextRunEditing.replacingText(in: shortened[0], with: "짧게")
        shortened = HWPFlowLayout.reflowingBody(shortened, before: edited, startingAt: shortened[0].id, layouts: package.pageLayouts)
        XCTAssertEqual(HWPOriginalCanvasPageBuilder.makePages(blocks: shortened, layouts: package.pageLayouts).count, 1)
    }

    func testParagraphUndoRedoRestoresStructureSelectionAndSave() async throws {
        let data = try LegacyHWPXConverter.convert(text: "한글 본문\n끝")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.hwpx")
        try data.write(to: url)
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let before = model.blocks
        let result = try XCTUnwrap(model.editParagraph(before[0], operation: .split(NSRange(location: 2, length: 0))))
        XCTAssertEqual(model.blocks.map(\.text), ["한글", " 본문", "끝"])
        XCTAssertEqual(model.selectedBlockID, result.focusedID)
        model.undo()
        XCTAssertEqual(model.blocks, before)
        XCTAssertEqual(model.selectedBlockID, before[0].id)
        model.redo()
        XCTAssertEqual(model.blocks.map(\.text), ["한글", " 본문", "끝"])
        await model.save()
        XCTAssertNil(model.errorDescription)
        XCTAssertEqual(try HWPXDocumentPackage.load(from: Data(contentsOf: url)).blocks.map(\.text), model.blocks.map(\.text))
    }

    func testTableCellParagraphUndoRedoAndSaveInBothFormats() async throws {
        let sources: [(HWPTableStructureDocument, String)] = [
            (try tableDocument(), "hwpx"),
            (try HWPTableStructureDocument.load(fixture("hangul_design_application", ext: "hwp")), "hwp")
        ]
        for (source, ext) in sources {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("cell.\(ext)")
            try source.data.write(to: url)
            let model = HWPDocumentViewModel(fileURL: url)
            await model.load()
            let before = model.blocks
            let target = try XCTUnwrap(before.first {
                HWPParagraphEditing.supportsCellParagraph($0) && $0.tableLocation?.parent == nil
                    && $0.text.utf16.count > 2
            })
            let oldCount = before.filter { HWPCellFormatting.sameCell($0, target) }.count
            let result = try XCTUnwrap(model.editParagraph(target,
                operation: .split(NSRange(location: 1, length: 0))))
            XCTAssertEqual(model.blocks.filter { HWPCellFormatting.sameCell($0, target) }.count, oldCount + 1)
            XCTAssertEqual(model.selectedBlockID, result.focusedID)
            model.undo()
            XCTAssertEqual(model.blocks, before)
            model.redo()
            XCTAssertEqual(model.blocks.filter { HWPCellFormatting.sameCell($0, target) }.count, oldCount + 1)
            await model.save()
            XCTAssertNil(model.errorDescription)
            let reopened = try HWPTableStructureDocument.load(Data(contentsOf: url))
            XCTAssertEqual(reopened.blocks.map(\.text), model.blocks.map(\.text))
        }
    }

    func testReflowDoesNotPullThePageAfterALargeTableOverItsCells() throws {
        let data = try fixture("hangul_design_application", ext: "hwp")
        let source = try HWP5StructuredDocumentParser.parse(from: data)
        let originalPages = HWPOriginalCanvasPageBuilder.makePages(blocks: source.blocks, layouts: source.pageLayouts)
        let draft = try XCTUnwrap(source.blocks.first { $0.paragraphIndex == 2 })
        let split = try XCTUnwrap(HWPParagraphEditing.apply(.split(NSRange(location: 4, length: 0)), draft: draft, to: source.blocks))
        let blocks = HWPFlowLayout.reflowingBody(split.blocks, before: source.blocks, startingAt: draft.id, layouts: source.pageLayouts)
        let pages = HWPOriginalCanvasPageBuilder.makePages(blocks: blocks, layouts: source.pageLayouts)
        XCTAssertGreaterThanOrEqual(pages.count, originalPages.count)
        let laterBody = try XCTUnwrap(originalPages.dropFirst().flatMap(\.bodyBlocks).first {
            $0.tableLocation == nil && !$0.text.isEmpty && !$0.id.contains("-page-fragment-")
        })
        XCTAssertFalse(pages[0].bodyBlocks.contains { $0.id == laterBody.id })
        XCTAssertTrue(pages.dropFirst().contains { $0.bodyBlocks.contains { $0.id == laterBody.id } })
        let saved = try HWP5DocumentRewriter.rewrite(sourceData: data, originalBlocks: source.blocks, editedBlocks: blocks)
        let reopened = try HWP5StructuredDocumentParser.parse(from: saved)
        let savedPages = HWPOriginalCanvasPageBuilder.makePages(blocks: reopened.blocks, layouts: reopened.pageLayouts)
        XCTAssertEqual(reopened.blocks.map(\.text), blocks.map(\.text))
        XCTAssertEqual(savedPages.count, pages.count)
        XCTAssertFalse(savedPages[0].bodyBlocks.contains { $0.text == laterBody.text })
        XCTAssertTrue(savedPages.dropFirst().contains { $0.bodyBlocks.contains { $0.text == laterBody.text } })
    }

    func testColorUnderlineAndAlignmentKeepTheOriginalLineGeometry() throws {
        let source = try HWP5StructuredDocumentParser.parse(from: fixture("hangul_design_application", ext: "hwp"))
        let paragraph = try XCTUnwrap(source.blocks.first { HWPParagraphEditing.supports($0) && $0.text.count > 3 })
        let range = NSRange(location: 1, length: 2)
        var edited = HWPDocumentFormatting.apply(.color(0xCC2244), to: paragraph, range: range)
        edited = HWPDocumentFormatting.apply(.underline(true), to: edited, range: range)
        edited = HWPDocumentFormatting.apply(.alignment(.trailing), to: edited, range: range)
        XCTAssertFalse(HWPFlowLayout.needsReflow(from: paragraph, to: edited))
        XCTAssertEqual(HWP5FormattingWriter.lineData(paragraph.lineLayouts), HWP5FormattingWriter.lineData(edited.lineLayouts))
        let enlarged = HWPDocumentFormatting.apply(.size(28), to: edited, range: range)
        XCTAssertTrue(HWPFlowLayout.needsReflow(from: paragraph, to: enlarged))
    }

    func testSoftBreakRetainsTheEmptyTrailingLineAndDoesNotCreateAParagraph() throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "한글"))
        let draft = HWPTextRunEditing.replacingText(in: package.blocks[0], with: "한글\n")
        let blocks = HWPFlowLayout.reflowingBody([draft], before: package.blocks, startingAt: draft.id, layouts: package.pageLayouts)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].lineLayouts.count, 2)
        XCTAssertEqual(blocks[0].lineLayouts.last?.text, "")
        XCTAssertEqual(blocks[0].lineLayouts.last?.startCharacter, 3)
        XCTAssertEqual(try HWPXDocumentPackage.load(from: package.serializedData(applying: blocks)).blocks[0].text, "한글\n")
    }

    func testPageFragmentEditingResolvesTheWholeParagraphAndCorrectCaretPage() throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: String(repeating: "한글 문서의 다음 쪽입니다.\t", count: 260)))
        let blocks = HWPFlowLayout.resolvingMissingLines(package.blocks, layout: package.pageLayouts[0])
        let pages = HWPOriginalCanvasPageBuilder.makePages(blocks: blocks, layouts: package.pageLayouts)
        let fragment = try XCTUnwrap(pages.dropFirst().first?.bodyBlocks.first)
        let session = HWPInlineEditingSession()
        let context = HWPInlineEditingContext(session: session, sources: [blocks[0].id: blocks[0]])
        let whole = try XCTUnwrap(context.source(for: fragment))
        XCTAssertEqual(whole.text, blocks[0].text)
        XCTAssertGreaterThan(whole.text.utf16.count, fragment.text.utf16.count)
        let offset = HWPInlineParagraphGeometry.textOffset(in: whole.text, raw: fragment.lineLayouts[0].startCharacter)
        XCTAssertGreaterThan(offset, 0)
        XCTAssertEqual(HWPInlineParagraphGeometry.surfaceID(for: whole, caret: offset), fragment.id)
        session.begin(block: whole, at: .zero, onSelect: { _ in }, onChange: { _ in }, onCommit: {}, caretOffset: offset)
        XCTAssertEqual(session.activation?.surfaceID, fragment.id)
        XCTAssertTrue(context.hidesText(fragment))
        session.finish()
    }

    func testCannotMergeAcrossSectionOrTableBoundaryOrForgeAnInsertion() throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "첫째\n둘째"))
        let cell = HWPDocumentBlock(id: "cell", sectionPath: package.blocks[0].sectionPath, paragraphIndex: 4,
            text: "표", tableLocation: HWPDocumentTableLocation(table: 0, row: 0, column: 0, paragraph: 0), isEditable: true)
        XCTAssertNil(HWPParagraphEditing.apply(.mergeBackward, draft: package.blocks[1], to: [cell, package.blocks[1]]))
        let split = try XCTUnwrap(HWPParagraphEditing.apply(.split(NSRange(location: 0, length: 0)), draft: cell, to: [cell]))
        XCTAssertEqual(split.blocks.compactMap { $0.tableLocation?.paragraph }, [0, 1])
        XCTAssertNil(HWPParagraphEditing.apply(.mergeBackward, draft: cell, to: [package.blocks[0], cell]))
        let nextCell = HWPDocumentBlock(id: "next-cell", sectionPath: cell.sectionPath, paragraphIndex: 5,
            text: "옆 셀", tableLocation: HWPDocumentTableLocation(table: 0, row: 0, column: 1, paragraph: 0), isEditable: true)
        XCTAssertNil(HWPParagraphEditing.apply(.mergeBackward, draft: nextCell, to: [cell, nextCell]))
        let other = HWPDocumentBlock(id: "other", sectionPath: "Contents/section1.xml", paragraphIndex: 0,
            text: "다른 구역", tableLocation: nil, isEditable: true)
        XCTAssertNil(HWPParagraphEditing.apply(.mergeBackward, draft: other, to: [package.blocks[0], other]))
        XCTAssertThrowsError(try package.serializedData(applying: package.blocks + [other]))
        XCTAssertThrowsError(try package.serializedData(applying: package.blocks.reversed()))
    }

    func testLiveReflowKeepsNativeInputCaretUndoAndKoreanCompositionAcrossNewPages() async throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "시작\n뒤 문단"))
        let source = HWPFlowLayout.resolvingMissingLines(package.blocks, layout: package.pageLayouts[0])
        let session = HWPInlineEditingSession()
        let navigation = HWPDocumentNavigation()
        var committed: HWPDocumentBlock?
        session.begin(block: source[0], at: .zero, onSelect: { _ in }, onChange: { _ in }, onCommit: {},
            onCommitBlock: { committed = $0 }, caretOffset: source[0].text.utf16.count)
        let host = UIHostingController(rootView: LiveParagraphCanvas(session: session, navigation: navigation,
            blocks: source, layouts: package.pageLayouts))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 900))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { session.finish(); window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        let input = try XCTUnwrap(findInput(host.view))
        let appended = String(repeating: " 입력한 문장이 길어지면 뒤 문단은 다음 쪽으로 이동합니다.", count: 100)
        input.insertText(appended)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertTrue(findInput(host.view) === input, "Live pagination must retain the native editor and its undo manager")
        XCTAssertEqual(input.text, "시작" + appended)
        XCTAssertEqual(input.selectedRange.location, input.text.utf16.count)
        XCTAssertGreaterThan(navigation.pages.count, 1)
        XCTAssertTrue(input.undoManager?.canUndo == true)
        input.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0))
        input.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0))
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertNotNil(input.markedTextRange)
        XCTAssertTrue(findInput(host.view) === input)
        session.finish()
        XCTAssertEqual(committed?.text, "시작" + appended + "한")
    }

    private struct LiveParagraphCanvas: View {
        @ObservedObject var session: HWPInlineEditingSession
        let navigation: HWPDocumentNavigation
        let blocks: [HWPDocumentBlock]
        let layouts: [HWPDocumentPageLayout]

        var body: some View {
            let preview = session.previewing(blocks, layouts: layouts)
            HWPOriginalDocumentCanvas(blocks: preview, pageLayouts: layouts, navigation: navigation)
                .environment(\.hwpInlineEditing, HWPInlineEditingContext(session: session,
                    sources: Dictionary(uniqueKeysWithValues: preview.map { ($0.id, $0) }), activeID: session.activation?.block.id))
        }
    }

    private func findInput(_ view: UIView) -> HWPInlineTextView? {
        if let input = view as? HWPInlineTextView { return input }
        return view.subviews.lazy.compactMap { self.findInput($0) }.first
    }

    private func fixture(_ name: String, ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "HWPXViewerFixtures")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("HWPXViewerFixtures/\(name).\(ext)")
        return try Data(contentsOf: url)
    }

    private func tableDocument() throws -> HWPTableStructureDocument {
        let base = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "\n표 뒤"))
        let section = base.sections[0]
        let first = try XCTUnwrap(HWPFormattingXML.elements(section.xml, name: "p").first)
        let paragraph = first.xml.replacingOccurrences(of: "</hp:run>",
            with: HWPCellFormattingTests.tableXML + "</hp:run>")
        let xml = (section.xml as NSString).replacingCharacters(in: first.range, with: paragraph)
        let data = try HWPXEditingArchive(data: base.sourceData).repack(
            replacing: [section.path: Data(xml.utf8)])
        return try HWPTableStructureDocument.load(data)
    }
}
