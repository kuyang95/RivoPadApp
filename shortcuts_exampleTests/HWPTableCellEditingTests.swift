import RivoDocumentEngine
import XCTest
@testable import shortcuts_example

@MainActor
final class HWPTableCellEditingTests: XCTestCase {
    func testHorizontalMergePreservesEveryParagraphAndCharacterStyleUsingFirstCellAppearance() throws {
        let source = try styledFixture()
        let target = try firstCell(source)
        let expected = source.blocks.filter { $0.tableLocation?.row == 0 }
        let result = try raw(.mergeRight, source, target.id)
        let merged = result.blocks.filter { $0.tableLocation?.row == 0 }
        XCTAssertEqual(merged.map(\.text), expected.map(\.text))
        XCTAssertEqual(merged.count, 3)
        for (a, b) in zip(merged, expected) {
            XCTAssertTrue(HWPDocumentFormatting.matches(a, b, includingCell: false))
            XCTAssertEqual(a.tableLocation?.columnSpan, 2)
            XCTAssertTrue(HWPCellFormatting.matches(a, target))
        }
        XCTAssertEqual(merged.first?.tableLocation?.cellWidthPoints ?? 0, 240, accuracy: 0.03)
        XCTAssertEqual(result.blocks.last?.text, "표 뒤")
        try assertArchiveUnchanged(source, result)
    }

    func testVerticalMergeUsesRowOrderAndLeavesNeighborCellsUntouched() throws {
        let source = try styledFixture(), target = try firstCell(source)
        let result = try raw(.mergeBelow, source, target.id)
        let merged = result.blocks.filter { $0.tableLocation?.column == 0 }
        XCTAssertEqual(merged.map(\.text), source.blocks.filter { $0.tableLocation?.column == 0 }.map(\.text))
        XCTAssertTrue(merged.allSatisfy { $0.tableLocation?.rowSpan == 2 })
        let oldOther = source.blocks.filter { $0.tableLocation?.column == 1 }
        let newOther = result.blocks.filter { $0.tableLocation?.column == 1 }
        XCTAssertTrue(zip(oldOther, newOther).allSatisfy { HWPDocumentFormatting.matches($0, $1) })
    }

    func testWideCellMergesWithMultipleCellsAlongTheWholeLowerEdge() throws {
        let source = try styledFixture()
        let horizontal = try raw(.mergeRight, source, firstCell(source).id)
        let result = try raw(.mergeBelow, horizontal, firstCell(horizontal).id)
        XCTAssertEqual(cells(result).count, 1)
        XCTAssertEqual(result.blocks.filter { $0.tableLocation != nil }.map(\.text), source.blocks.filter { $0.tableLocation != nil }.map(\.text))
        XCTAssertEqual(try firstCell(result).tableLocation?.rowSpan, 2)
        XCTAssertEqual(try firstCell(result).tableLocation?.columnSpan, 2)
    }

    func testPartialEdgeMergeAndOutOfBoundsCommandsAreUnavailable() throws {
        let source = try styledFixture()
        let bottom = try XCTUnwrap(source.blocks.first { $0.tableLocation?.row == 1 && $0.tableLocation?.column == 0 })
        let merged = try raw(.mergeRight, source, bottom.id)
        let right = try XCTUnwrap(merged.blocks.first { $0.tableLocation?.row == 0 && $0.tableLocation?.column == 1 })
        XCTAssertThrowsError(try HWPTableStructureEditing.plan(.mergeBelow, blocks: merged.blocks, selectedID: right.id, layouts: merged.layouts))
        let last = try XCTUnwrap(source.blocks.last { $0.tableLocation != nil })
        let available = HWPTableStructureEditing.availableCells(blocks: source.blocks, selectedID: last.id, layouts: source.layouts)
        XCTAssertFalse(available.contains(.mergeRight)); XCTAssertFalse(available.contains(.mergeBelow)); XCTAssertFalse(available.contains(.unmerge))
        XCTAssertTrue(HWPTableStructureEditing.availableCells(blocks: source.blocks, selectedID: source.blocks.last!.id, layouts: source.layouts).isEmpty)
    }

    func testSplittingOrdinaryCellPreservesTableSizeAndOtherCellsGeometry() throws {
        for action in [HWPTableStructureAction.splitColumns, .splitRows] {
            let source = try styledFixture(), target = try firstCell(source)
            let result = try raw(action, source, target.id)
            XCTAssertEqual(cells(result).count, 5)
            let retained = result.blocks.filter { $0.tableLocation?.row == 0 && $0.tableLocation?.column == 0 }
            XCTAssertEqual(retained.map(\.text), ["첫 문단", "둘째 문단"])
            let empty = try XCTUnwrap(result.blocks.first { $0.tableLocation != nil && $0.text.isEmpty })
            XCTAssertTrue(empty.isEditable); XCTAssertTrue(HWPCellFormatting.matches(empty, target))
            if action == .splitColumns {
                XCTAssertEqual(retained.first?.tableLocation?.cellWidthPoints ?? 0, 60, accuracy: 0.03)
                XCTAssertEqual(empty.tableLocation?.cellWidthPoints ?? 0, 60, accuracy: 0.03)
            } else {
                XCTAssertEqual(retained.first?.tableLocation?.cellHeightPoints ?? 0, 45, accuracy: 0.03)
                XCTAssertEqual(empty.tableLocation?.cellHeightPoints ?? 0, 45, accuracy: 0.03)
            }
            for old in source.blocks where old.tableLocation != nil && !HWPCellFormatting.sameCell(old, target) {
                let saved = try XCTUnwrap(result.blocks.first { $0.text == old.text })
                XCTAssertEqual(saved.tableLocation?.cellWidthPoints, old.tableLocation?.cellWidthPoints)
                XCTAssertEqual(saved.tableLocation?.cellHeightPoints, old.tableLocation?.cellHeightPoints)
            }
            let oldTracks = HWPTableTrackLayoutSolver.make(blocks: source.blocks.filter { $0.tableLocation != nil })
            let newTracks = HWPTableTrackLayoutSolver.make(blocks: result.blocks.filter { $0.tableLocation != nil })
            XCTAssertEqual(newTracks.columnWidths.reduce(0,+), oldTracks.columnWidths.reduce(0,+), accuracy: 0.03)
            XCTAssertEqual(newTracks.rowHeights.reduce(0,+), oldTracks.rowHeights.reduce(0,+), accuracy: 0.03)
        }
    }

    func testSplittingMergedCellReusesTheExistingMiddleBoundary() throws {
        let source = try styledFixture()
        for (merge, split) in [(HWPTableStructureAction.mergeRight, HWPTableStructureAction.splitColumns), (.mergeBelow, .splitRows)] {
            let merged = try raw(merge, source, firstCell(source).id)
            let result = try raw(split, merged, firstCell(merged).id)
            XCTAssertEqual(cells(result).count, 4)
            let tracks = HWPTableTrackLayoutSolver.make(blocks: result.blocks.filter { $0.tableLocation != nil })
            XCTAssertEqual(tracks.rowHeights.count, 2); XCTAssertEqual(tracks.columnWidths.count, 2)
            XCTAssertEqual(result.blocks.filter { !$0.text.isEmpty }.map(\.text).sorted(), source.blocks.filter { !$0.text.isEmpty }.map(\.text).sorted())
        }
    }

    func testUnmergeKeepsAllContentInFirstCellAndCreatesEditableEmptyPeers() throws {
        let source = try styledFixture()
        let horizontal = try raw(.mergeRight, source, firstCell(source).id)
        let merged = try raw(.mergeBelow, horizontal, firstCell(horizontal).id)
        let result = try raw(.unmerge, merged, firstCell(merged).id)
        XCTAssertEqual(cells(result).count, 4)
        let first = try firstCell(result)
        XCTAssertEqual(result.blocks.filter { HWPCellFormatting.sameCell($0, first) }.count, 5)
        XCTAssertEqual(result.blocks.filter { $0.tableLocation != nil && $0.text.isEmpty }.count, 3)
        XCTAssertTrue(result.blocks.filter { $0.tableLocation != nil }.allSatisfy { $0.isEditable && $0.tableLocation?.rowSpan == 1 && $0.tableLocation?.columnSpan == 1 })
    }

    func testRepeatedSplitStopsAtMinimumWidthWithoutChangingSource() throws {
        var source = try styledFixture()
        var rejected = false
        for _ in 0..<15 {
            let before = source.data
            do { source = try raw(.splitColumns, source, firstCell(source).id) }
            catch { XCTAssertEqual(source.data, before); rejected = true; break }
        }
        XCTAssertTrue(rejected)
    }

    func testRealHWPMergeSplitPreservesParagraphsStylesOtherStreamsAndLastParagraphFlags() throws {
        var source = try HWPTableStructureDocument.load(fixture("hangul_design_application", "hwp"))
        let selected = try XCTUnwrap(source.blocks.first {
            HWPTableStructureEditing.availableCells(blocks: source.blocks, selectedID: $0.id, layouts: source.layouts).contains(.splitColumns)
        })
        let table = selected.tableLocation!.table
        source = try raw(.splitColumns, source, selected.id)
        let first = try XCTUnwrap(source.blocks.first { $0.tableLocation?.table == table })
        let right = try XCTUnwrap(source.blocks.first { $0.tableLocation?.table == table && $0.tableLocation?.row == first.tableLocation?.row && $0.tableLocation?.column == first.tableLocation!.column + first.tableLocation!.columnSpan })
        var blocks = source.blocks
        let index = try XCTUnwrap(blocks.firstIndex { $0.id == right.id })
        blocks[index] = HWPTextRunEditing.replacingText(in: right, with: "합칠 한글 👨‍👩‍👧‍👦")
        blocks[index] = HWPDocumentFormatting.apply(.bold(true), to: blocks[index], range: NSRange(location: 0, length: blocks[index].text.utf16.count))
        source = try HWPTableStructureDocument.load(source.serialized(blocks))
        let original = source
        source = try raw(.mergeRight, source, first.id)
        let retained = try XCTUnwrap(source.blocks.first { $0.text == "합칠 한글 👨‍👩‍👧‍👦" })
        XCTAssertTrue(HWPDocumentFormatting.run(at: 0, in: retained).isBold)
        XCTAssertTrue(HWPCellFormatting.sameCell(retained, try XCTUnwrap(source.blocks.first { $0.tableLocation?.table == table })))
        try assertArchiveUnchanged(original, source)
        let ole = try OLECompoundFile(data: source.data)
        let flags = try ole.stream(named: "FileHeader").hwpWriterUInt32(at: 36)
        for path in ole.streamNames where path.hasPrefix("bodytext/section") {
            let stored = try ole.stream(named: path)
            let bytes = try flags & 1 != 0 ? HWP5TextExtractor.inflateRawDeflate(stored, maximumBytes: HWP5TextExtractor.maximumSectionBytes) : stored
            let records = try HWP5DocumentRewriter.parseRecords(bytes)
            for i in records.indices where records[i].tag == 0x48 {
                let end = records.indices.dropFirst(i+1).first { records[$0].level <= records[i].level } ?? records.count
                let paragraphs = (i+1..<end).filter { records[$0].tag == 0x42 }
                if paragraphs.count > 1 {
                    XCTAssertEqual(try paragraphs.map { try records[$0].payload.hwpWriterUInt32(at: 0) & 0x8000_0000 != 0 }, paragraphs.map { $0 == paragraphs.last })
                }
            }
        }
        for action in [HWPTableStructureAction.splitRows, .mergeBelow, .unmerge] {
            let target = try XCTUnwrap(source.blocks.first { $0.tableLocation?.table == table })
            source = try raw(action, source, target.id)
        }
        XCTAssertTrue(source.blocks.contains { $0.text == "합칠 한글 👨‍👩‍👧‍👦" })
    }

    func testSplitRemapsBackgroundZonesAndMergeLeavesThemUnchanged() throws {
        let source = try smallFixture(zones: true)
        let split = try raw(.splitColumns, source, firstCell(source).id)
        guard case .hwpx(let package) = split else { return XCTFail() }
        let zone = try XCTUnwrap(HWPFormattingXML.elements(package.sections[0].xml, name: "cellzone").first)
        XCTAssertEqual(try HWPFormattingXML.attribute(zone.xml, "startColAddr"), "0")
        XCTAssertEqual(try HWPFormattingXML.attribute(zone.xml, "endColAddr"), "1")
        let merged = try raw(.mergeRight, split, firstCell(split).id)
        guard case .hwpx(let after) = merged else { return XCTFail() }
        XCTAssertEqual(try HWPFormattingXML.elements(after.sections[0].xml, name: "cellzone").first?.xml, zone.xml)
    }

    func testTransactionsKeepPendingEditsAndAllowFurtherFormattingAndSavingInBothFormats() async throws {
        for data in [try smallFixture().data, try fixture("hangul_design_application", "hwp")] {
            var source = try HWPTableStructureDocument.load(data)
            var selected = try XCTUnwrap(source.blocks.first {
                HWPCellFormatting.supports($0)
                    && HWPTableStructureEditing.availableCells(blocks: source.blocks, selectedID: $0.id, layouts: source.layouts).contains(.splitColumns)
            }).id
            var blocks = source.blocks
            let i = try XCTUnwrap(blocks.firstIndex { $0.id == selected })
            blocks[i] = HWPTextRunEditing.replacingText(in: blocks[i], with: "편집한 내용 👨‍👩‍👧‍👦")
            for action in [HWPTableStructureAction.splitColumns, .mergeRight, .splitRows, .mergeBelow, .unmerge] {
                let result = try await source.editing(action, blocks: blocks, selectedID: selected)
                source = result.document; selected = result.focusedID; blocks = source.blocks
                XCTAssertEqual(blocks.filter { $0.text == "편집한 내용 👨‍👩‍👧‍👦" }.count, 1)
            }
            let index = try XCTUnwrap(blocks.firstIndex { $0.id == selected })
            var style = HWPCellFormat(blocks[index].tableLocation!); style.setFill(0xFFF2CC)
            let old = blocks[index]; blocks[index] = HWPCellFormatting.apply(style, to: old)
            blocks = HWPCellFormatting.propagating(blocks[index], from: old, in: blocks)
            let saved = try HWPTableStructureDocument.load(source.serialized(blocks))
            let styled = try XCTUnwrap(saved.blocks.first { $0.id == blocks[index].id })
            XCTAssertEqual(styled.tableLocation?.boxStyle?.backgroundColorRGB, 0xFFF2CC,
                data.starts(with: [0x50, 0x4B]) ? "HWPX" : "HWP")
        }
    }

    func testMergedAndSplitLongContentReflowsWithoutOverlappingFollowingBody() async throws {
        var source = try smallFixture()
        var selected = try firstCell(source).id
        var blocks = source.blocks
        let i = try XCTUnwrap(blocks.firstIndex { $0.id == selected })
        blocks[i] = HWPTextRunEditing.replacingText(in: blocks[i], with: String(repeating: "길어진 한글 내용 ", count: 20))
        for action in [HWPTableStructureAction.mergeRight, .splitColumns, .splitRows, .mergeBelow, .unmerge] {
            let result = try await source.editing(action, blocks: blocks, selectedID: selected)
            source = result.document; blocks = source.blocks; selected = result.focusedID
            let pages = HWPOriginalCanvasPageBuilder.makePages(blocks: blocks, layouts: source.layouts)
            let body = try XCTUnwrap(blocks.last)
            let bodyPage = try XCTUnwrap(pages.firstIndex { $0.bodyBlocks.contains { $0.id == body.id } })
            let tablePage = try XCTUnwrap(pages.lastIndex { $0.bodyBlocks.contains { $0.tableLocation != nil } })
            XCTAssertGreaterThanOrEqual(bodyPage, tablePage)
            if bodyPage == tablePage {
                let table = blocks.filter { $0.tableLocation != nil }
                let bottom = HWPTableEditing.finalPageBottom(table, anchorY: table.first!.tableLocation!.tableAnchor?.verticalPositionPoints ?? 0, layout: source.layouts[0])
                XCTAssertGreaterThanOrEqual(body.lineLayouts[0].verticalPositionPoints + 0.03, bottom)
            }
        }
    }

    func testViewModelMergeSplitUndoRedoAndSaveKeepsBothCellsContent() async throws {
        let source = try styledFixture(), url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        try source.data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url); await model.load()
        let original = model.blocks
        var selected = try await model.editTable(.mergeRight, selectedID: firstCell(source).id)
        let merged = model.blocks
        selected = try await model.editTable(.splitColumns, selectedID: selected)
        let split = model.blocks
        XCTAssertEqual(try Data(contentsOf: url), source.data)
        model.undo(); XCTAssertEqual(model.blocks, merged)
        model.undo(); XCTAssertEqual(model.blocks, original); XCTAssertFalse(model.hasUnsavedChanges)
        model.redo(); model.redo(); XCTAssertEqual(model.blocks, split)
        let cell = try XCTUnwrap(model.blocks.first { $0.id == selected })
        model.commitInlineBlock(HWPTextRunEditing.replacingText(in: cell, with: "병합 후 입력"))
        model.undo(); XCTAssertEqual(model.blocks, split); model.redo()
        await model.save(); XCTAssertNil(model.errorDescription); XCTAssertFalse(model.hasUnsavedChanges)
        let saved = try HWPXDocumentPackage.load(from: Data(contentsOf: url))
        XCTAssertTrue(saved.blocks.contains { $0.text == "병합 후 입력" })
        XCTAssertTrue(saved.blocks.contains { $0.text == "오른쪽 내용" })
    }

    func testViewModelHWPRepeatedCellChangesSaveAndUndoToCleanBaseline() async throws {
        let data = try fixture("hangul_design_application", "hwp")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwp")
        try data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url); await model.load()
        let before = model.blocks
        var selected = try XCTUnwrap(model.blocks.first { HWPTableStructureEditing.availableCells(blocks: model.blocks, selectedID: $0.id, layouts: model.pageLayouts).contains(.splitColumns) }).id
        for action in [HWPTableStructureAction.splitColumns, .mergeRight, .splitRows, .mergeBelow, .unmerge] {
            selected = try await model.editTable(action, selectedID: selected)
        }
        let after = model.blocks
        for _ in 0..<5 { model.undo() }; XCTAssertEqual(model.blocks, before); XCTAssertFalse(model.hasUnsavedChanges)
        for _ in 0..<5 { model.redo() }; XCTAssertEqual(model.blocks, after)
        await model.save(); XCTAssertNil(model.errorDescription)
        XCTAssertEqual(try HWP5StructuredDocumentParser.parse(from: Data(contentsOf: url)).blocks.map(\.text), after.map(\.text))
    }

    private func cells(_ source: HWPTableStructureDocument) -> Set<HWPTableStructureEditing.Address> {
        Set(source.blocks.compactMap { $0.tableLocation.map { .init(row: $0.row, column: $0.column) } })
    }
    private func firstCell(_ source: HWPTableStructureDocument) throws -> HWPDocumentBlock { try XCTUnwrap(source.blocks.first { $0.tableLocation != nil }) }
    private func raw(_ action: HWPTableStructureAction, _ source: HWPTableStructureDocument, _ id: String) throws -> HWPTableStructureDocument {
        let plan = try HWPTableStructureEditing.plan(action, blocks: source.blocks, selectedID: id, layouts: source.layouts)
        let data: Data
        switch source {
        case .hwpx(let p): data = try HWPTableStructureWriter.hwpx(p, plan: plan)
        case .hwp(_, let d): data = try HWPTableStructureWriter.hwp(d, blocks: source.blocks, plan: plan)
        }
        return try HWPTableStructureDocument.load(data)
    }
    private func styledFixture() throws -> HWPTableStructureDocument {
        let source = try smallFixture(); var blocks = source.blocks
        let texts = ["첫 문단", "둘째 문단", "오른쪽 내용", "아래 내용", "오른쪽 아래"]
        var ordinal = 0
        for index in blocks.indices where blocks[index].tableLocation != nil {
            blocks[index] = HWPTextRunEditing.replacingText(in: blocks[index], with: texts[ordinal])
            blocks[index] = HWPDocumentFormatting.apply(.bold(ordinal % 2 == 0), to: blocks[index], range: NSRange(location: 0, length: blocks[index].text.utf16.count))
            var style = HWPCellFormat(blocks[index].tableLocation!)
            style.setFill(blocks[index].tableLocation?.column == 0 ? 0xDDEBF7 : 0xFFF2CC)
            blocks[index] = HWPCellFormatting.apply(style, to: blocks[index]); ordinal += 1
        }
        return try HWPTableStructureDocument.load(source.serialized(blocks))
    }
    private func smallFixture(zones: Bool = false) throws -> HWPTableStructureDocument {
        let base = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "\n표 뒤"))
        var table = HWPCellFormattingTests.tableXML
        if zones { table = table.replacingOccurrences(of: "</hp:tbl>", with: "<hp:cellzoneList itemCnt=\"1\"><hp:cellzone startRowAddr=\"0\" startColAddr=\"0\" endRowAddr=\"1\" endColAddr=\"0\" borderFillIDRef=\"1\"/></hp:cellzoneList></hp:tbl>") }
        let section = base.sections[0], first = try XCTUnwrap(HWPFormattingXML.elements(base.sections[0].xml, name: "p").first)
        let xml = (section.xml as NSString).replacingCharacters(in: first.range, with: first.xml.replacingOccurrences(of: "</hp:run>", with: table + "</hp:run>"))
        return try HWPTableStructureDocument.load(HWPXEditingArchive(data: base.sourceData).repack(replacing: [section.path: Data(xml.utf8)]))
    }
    private func fixture(_ name: String, _ ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: ext) ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "HWPXViewerFixtures")))
    }
    private func assertArchiveUnchanged(_ source: HWPTableStructureDocument, _ saved: HWPTableStructureDocument) throws {
        switch source {
        case .hwpx:
            let a = try HWPXEditingArchive(data: source.data), b = try HWPXEditingArchive(data: saved.data)
            for path in a.paths where !path.lowercased().hasPrefix("contents/section") { XCTAssertEqual(try a.data(at: path), try b.data(at: path), path) }
        case .hwp:
            let a = try OLECompoundFile(data: source.data), b = try OLECompoundFile(data: saved.data)
            for path in a.streamNames where !path.hasPrefix("bodytext/") && path != "prvtext" { XCTAssertEqual(try a.stream(named: path), try b.stream(named: path), path) }
        }
    }
}
