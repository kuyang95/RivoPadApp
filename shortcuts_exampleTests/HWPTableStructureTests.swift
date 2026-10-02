import RivoDocumentEngine
import XCTest
@testable import shortcuts_example

@MainActor
final class HWPTableStructureTests: XCTestCase {
    func testAllSixHWPXOperationsKeepContentStylesAndHeaderDefinitions() throws {
        let package = try fixturePackage()
        let target = try XCTUnwrap(package.blocks.first { $0.tableLocation != nil })
        for action in HWPTableStructureAction.trackActions {
            let plan = try HWPTableStructureEditing.plan(action, blocks: package.blocks, selectedID: target.id, layouts: package.pageLayouts)
            let data = try HWPTableStructureWriter.hwpx(package, plan: plan)
            let saved = try HWPXDocumentPackage.load(from: data)
            try HWPTableStructureWriter.verify(saved.blocks, original: package.blocks, plan: plan)
            XCTAssertEqual(try HWPXEditingArchive(data: data).data(at: "Contents/header.xml"),
                try HWPXEditingArchive(data: package.sourceData).data(at: "Contents/header.xml"))
            XCTAssertEqual(plan.width, 240, accuracy: 0.03)
            if !action.isDeletion {
                let added = saved.blocks[plan.originalRange.lowerBound..<(plan.originalRange.lowerBound + plan.sourceIndices.count)]
                    .filter { $0.tableLocation?.row == plan.focus.row && $0.tableLocation?.column == plan.focus.column }
                XCTAssertEqual(added.count, 1); XCTAssertEqual(added.first?.text, "")
                XCTAssertTrue(added.first?.isEditable == true)
            }
        }
    }

    func testRowsCrossingMergedCellsExpandAndShrinkWithoutLosingTheirParagraphs() throws {
        let package = try fixturePackage(mergedRows: true)
        let selected = try XCTUnwrap(package.blocks.first { $0.tableLocation?.column == 1 })
        let plan = try HWPTableStructureEditing.plan(.rowBelow, blocks: package.blocks, selectedID: selected.id, layouts: package.pageLayouts)
        let added = try HWPXDocumentPackage.load(from: HWPTableStructureWriter.hwpx(package, plan: plan))
        let merged = try XCTUnwrap(added.blocks.first { $0.tableLocation?.column == 0 })
        XCTAssertEqual(merged.tableLocation?.rowSpan, 3)
        XCTAssertEqual(added.blocks.filter { HWPCellFormatting.sameCell($0, merged) }.map(\.text), ["첫 문단", "둘째 문단"])
        let blank = try XCTUnwrap(added.blocks.first { $0.tableLocation?.row == 1 && $0.tableLocation?.column == 1 })
        let removed = try HWPTableStructureEditing.plan(.deleteRow, blocks: added.blocks, selectedID: blank.id, layouts: added.pageLayouts)
        let restored = try HWPXDocumentPackage.load(from: HWPTableStructureWriter.hwpx(added, plan: removed))
        XCTAssertEqual(restored.blocks.map(\.text), package.blocks.map(\.text))
        XCTAssertEqual(restored.blocks.first { $0.tableLocation?.column == 0 }?.tableLocation?.rowSpan, 2)
    }

    func testDeletingFirstTrackOfAMergedCellRetainsTextAndMovesItsOrigin() throws {
        let package = try fixturePackage(mergedRows: true)
        let selected = try XCTUnwrap(package.blocks.first { $0.tableLocation?.rowSpan == 2 })
        let plan = try HWPTableStructureEditing.plan(.deleteRow, blocks: package.blocks, selectedID: selected.id, layouts: package.pageLayouts)
        let saved = try HWPXDocumentPackage.load(from: HWPTableStructureWriter.hwpx(package, plan: plan))
        XCTAssertEqual(saved.blocks.first { $0.text == "첫 문단" }?.tableLocation?.rowSpan, 1)
        XCTAssertEqual(saved.blocks.first { $0.text == "둘째 문단" }?.tableLocation?.row, 0)
        XCTAssertEqual(saved.blocks.filter { $0.tableLocation != nil }.count, 3)
    }

    func testColumnsCrossingMergedCellsKeepContentsAndTableWidth() throws {
        let package = try fixturePackage(mergedColumns: true)
        let selected = try XCTUnwrap(package.blocks.first { $0.tableLocation?.row == 1 && $0.tableLocation?.column == 0 })
        let plan = try HWPTableStructureEditing.plan(.columnAfter, blocks: package.blocks, selectedID: selected.id, layouts: package.pageLayouts)
        let added = try HWPXDocumentPackage.load(from: HWPTableStructureWriter.hwpx(package, plan: plan))
        XCTAssertEqual(added.blocks.first { $0.text == "첫 문단" }?.tableLocation?.columnSpan, 3)
        let blank = try XCTUnwrap(added.blocks.first { $0.tableLocation?.row == 1 && $0.tableLocation?.column == 1 })
        let removed = try HWPTableStructureEditing.plan(.deleteColumn, blocks: added.blocks, selectedID: blank.id, layouts: added.pageLayouts)
        let restored = try HWPXDocumentPackage.load(from: HWPTableStructureWriter.hwpx(added, plan: removed))
        XCTAssertEqual(restored.blocks.map(\.text), package.blocks.map(\.text))
        XCTAssertEqual(restored.blocks.first { $0.text == "첫 문단" }?.tableLocation?.columnSpan, 2)
        XCTAssertEqual(removed.width, 240, accuracy: 0.03)
    }

    func testLastRowAndColumnDeletionAreUnavailableAndLeaveTheSourceUntouched() throws {
        var package = try fixturePackage()
        for action in [HWPTableStructureAction.deleteRow, .deleteColumn] {
            let target = try XCTUnwrap(package.blocks.first { $0.tableLocation != nil })
            let plan = try HWPTableStructureEditing.plan(action, blocks: package.blocks, selectedID: target.id, layouts: package.pageLayouts)
            package = try HWPXDocumentPackage.load(from: HWPTableStructureWriter.hwpx(package, plan: plan))
        }
        let selected = try XCTUnwrap(package.blocks.first { $0.tableLocation != nil })
        let actions = HWPTableStructureEditing.available(blocks: package.blocks, selectedID: selected.id, layouts: package.pageLayouts)
        XCTAssertEqual(actions.filter { HWPTableStructureAction.trackActions.contains($0) }.count, 4); XCTAssertTrue(actions.contains(.deleteTable)); XCTAssertFalse(actions.contains(.deleteRow)); XCTAssertFalse(actions.contains(.deleteColumn))
        XCTAssertThrowsError(try HWPTableStructureEditing.plan(.deleteRow, blocks: package.blocks, selectedID: selected.id, layouts: package.pageLayouts))
        XCTAssertEqual(try package.serializedData(applying: package.blocks), package.sourceData)
        XCTAssertTrue(HWPTableStructureEditing.available(blocks: package.blocks, selectedID: package.blocks.last!.id, layouts: package.pageLayouts).isEmpty)
    }

    func testRawHWPAllSixOperationsPreserveOtherStreamsAndRemainEditable() throws {
        let data = try expandedHWPFixture()
        let source = try HWP5StructuredDocumentParser.parse(from: data)
        let selected = try XCTUnwrap(source.blocks.first {
            HWPTableStructureEditing.available(blocks: source.blocks, selectedID: $0.id, layouts: source.pageLayouts).filter { HWPTableStructureAction.trackActions.contains($0) }.count == 6
        })
        for action in HWPTableStructureAction.trackActions {
            let plan = try HWPTableStructureEditing.plan(action, blocks: source.blocks, selectedID: selected.id, layouts: source.pageLayouts)
            let saved = try HWPTableStructureWriter.hwp(data, blocks: source.blocks, plan: plan)
            let reopened = try HWP5StructuredDocumentParser.parse(from: saved)
            try HWPTableStructureWriter.verify(reopened.blocks, original: source.blocks, plan: plan)
            let before = try OLECompoundFile(data: data), after = try OLECompoundFile(data: saved)
            for path in before.streamNames where !path.hasPrefix("bodytext/") && path != "prvtext" {
                XCTAssertEqual(try before.stream(named: path), try after.stream(named: path), path)
            }
        }
    }

    func testOfficialHWPXInsertionKeepsEmbeddedAssets() throws {
        let package = try HWPXDocumentPackage.load(from: fixture("mss_voucher", ext: "hwpx"))
        let selected = try XCTUnwrap(package.blocks.first {
            HWPTableStructureEditing.available(blocks: package.blocks, selectedID: $0.id, layouts: package.pageLayouts).contains(.rowBelow)
        })
        let plan = try HWPTableStructureEditing.plan(.rowBelow, blocks: package.blocks, selectedID: selected.id, layouts: package.pageLayouts)
        let data = try HWPTableStructureWriter.hwpx(package, plan: plan)
        let old = try HWPXEditingArchive(data: package.sourceData), saved = try HWPXEditingArchive(data: data)
        for path in old.paths where path.hasPrefix("BinData/") { XCTAssertEqual(try old.data(at: path), try saved.data(at: path)) }
    }

    func testTransactionKeepsPendingTextCellStyleAndBodyInsertionInBothFormats() async throws {
        for data in [try fixturePackage().sourceData, try fixture("hangul_design_application", ext: "hwp")] {
            let source = try HWPTableStructureDocument.load(data)
            let cell = try XCTUnwrap(source.blocks.first {
                HWPCellFormatting.supports($0)
                    && HWPTableStructureEditing.available(blocks: source.blocks, selectedID: $0.id, layouts: source.layouts).contains(.columnAfter)
            })
            var blocks = source.blocks
            let index = try XCTUnwrap(blocks.firstIndex { $0.id == cell.id })
            blocks[index] = HWPTextRunEditing.replacingText(in: cell, with: "한글 새 내용 👨‍👩‍👧‍👦")
            var format = HWPCellFormat(cell.tableLocation!); format.setFill(0xDDEBF7)
            blocks[index] = HWPCellFormatting.apply(format, to: blocks[index])
            blocks = HWPCellFormatting.propagating(blocks[index], from: cell, in: blocks)
            let body = try XCTUnwrap(blocks.first { HWPParagraphEditing.supports($0) && $0.text.count > 2 })
            blocks = try XCTUnwrap(HWPParagraphEditing.apply(.split(NSRange(location: 1, length: 0)), draft: body, to: blocks)).blocks
            let committed = try HWPTableStructureDocument.load(source.serialized(blocks))
            let committedCell = try XCTUnwrap(committed.blocks.first { $0.text == "한글 새 내용 👨‍👩‍👧‍👦" })
            XCTAssertEqual(committedCell.tableLocation?.boxStyle?.backgroundColorRGB, 0xDDEBF7,
                data.starts(with: [0x50, 0x4B]) ? "HWPX before structure" : "HWP before structure")
            let result = try await source.editing(.columnAfter, blocks: blocks, selectedID: cell.id)
            let retained = try XCTUnwrap(result.document.blocks.first { $0.text == "한글 새 내용 👨‍👩‍👧‍👦" })
            XCTAssertEqual(retained.tableLocation?.boxStyle?.backgroundColorRGB, 0xDDEBF7,
                data.starts(with: [0x50, 0x4B]) ? "HWPX" : "HWP")
            let newCell = try XCTUnwrap(result.document.blocks.first { $0.id == result.focusedID })
            XCTAssertEqual(newCell.text, ""); XCTAssertTrue(newCell.isEditable)
            var edited = result.document.blocks
            let newIndex = try XCTUnwrap(edited.firstIndex { $0.id == newCell.id })
            edited[newIndex] = HWPTextRunEditing.replacingText(in: newCell, with: "추가한 셀")
            let saved = try HWPTableStructureDocument.load(result.document.serialized(edited))
            XCTAssertEqual(saved.blocks[newIndex].text, "추가한 셀")
        }
    }

    func testColumnInsertionReflowsLongTextAndKeepsBodyBelowTable() async throws {
        let package = try fixturePackage()
        let selected = try XCTUnwrap(package.blocks.first { $0.tableLocation != nil })
        var blocks = package.blocks
        let index = try XCTUnwrap(blocks.firstIndex { $0.id == selected.id })
        blocks[index] = HWPTextRunEditing.replacingText(in: selected, with: String(repeating: "길어진 한글 내용 ", count: 30))
        let result = try await HWPTableStructureDocument.hwpx(package).editing(.columnAfter, blocks: blocks, selectedID: selected.id)
        let edited = try XCTUnwrap(result.document.blocks.first { $0.text.hasPrefix("길어진") })
        XCTAssertGreaterThan(try XCTUnwrap(edited.tableLocation?.cellHeightPoints), 90)
        XCTAssertLessThan(try XCTUnwrap(edited.tableLocation?.cellWidthPoints), 120)
        let body = try XCTUnwrap(result.document.blocks.last)
        let table = result.document.blocks.filter { $0.tableLocation != nil }
        let bottom = HWPTableEditing.finalPageBottom(table, anchorY: table.first!.tableLocation!.tableAnchor?.verticalPositionPoints ?? 0, layout: result.document.layouts[0])
        let pages = HWPOriginalCanvasPageBuilder.makePages(blocks: result.document.blocks, layouts: result.document.layouts)
        let bodyPage = try XCTUnwrap(pages.firstIndex { $0.bodyBlocks.contains { $0.id == body.id } })
        let tablePage = try XCTUnwrap(pages.lastIndex { $0.bodyBlocks.contains { $0.tableLocation != nil } })
        XCTAssertGreaterThanOrEqual(bodyPage, tablePage)
        if bodyPage == tablePage { XCTAssertGreaterThanOrEqual(body.lineLayouts[0].verticalPositionPoints + 0.03, bottom) }
    }

    func testRepeatedStructureChangesNeverMoveFollowingBodyInsideTableWithoutLineCaches() async throws {
        var source = HWPTableStructureDocument.hwpx(try fixturePackage())
        var focused = try XCTUnwrap(source.blocks.first { $0.tableLocation != nil }).id
        for action in [HWPTableStructureAction.rowBelow, .columnAfter, .deleteRow, .deleteColumn] {
            let result = try await source.editing(action, blocks: source.blocks, selectedID: focused)
            source = result.document; focused = result.focusedID
            let body = try XCTUnwrap(source.blocks.last)
            let cells = source.blocks.filter { $0.tableLocation != nil }
            let height = HWPTableTrackLayoutSolver.make(blocks: cells).rowHeights.reduce(0, +)
            let anchor = cells.first?.tableLocation?.tableAnchor?.verticalPositionPoints ?? 0
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(body.lineLayouts.first).verticalPositionPoints + 0.03, anchor + height, action.rawValue)
            XCTAssertFalse(try XCTUnwrap(body.lineLayouts.first).startsPage)
        }
    }

    func testRepeatedHWPStructureTransactionsKeepAReusableEditingBaseline() async throws {
        var source = try HWPTableStructureDocument.load(expandedHWPFixture())
        var selected = try XCTUnwrap(source.blocks.first {
            HWPTableStructureEditing.available(blocks: source.blocks, selectedID: $0.id, layouts: source.layouts).filter { HWPTableStructureAction.trackActions.contains($0) }.count == 6
        }).id
        for action in [HWPTableStructureAction.rowBelow, .columnAfter, .deleteRow] {
            do {
                let result = try await source.editing(action, blocks: source.blocks, selectedID: selected)
                source = result.document; selected = result.focusedID
            } catch { XCTFail("\(action.rawValue): \(error)"); return }
        }
    }

    func testViewModelTableStructureUndoRedoKeepsDiskSnapshotAndPendingEdits() async throws {
        let data = try fixturePackage().sourceData
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        try data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url); await model.load()
        let original = model.blocks
        let selected = try XCTUnwrap(original.first { $0.tableLocation != nil })
        let focused = try await model.editTable(.rowBelow, selectedID: selected.id)
        XCTAssertEqual(try Data(contentsOf: url), data)
        let added = model.blocks
        model.undo(); XCTAssertEqual(model.blocks, original); XCTAssertFalse(model.hasUnsavedChanges)
        model.redo(); XCTAssertEqual(model.blocks, added)
        let cell = try XCTUnwrap(model.blocks.first { $0.id == focused })
        model.commitInlineBlock(HWPTextRunEditing.replacingText(in: cell, with: "새 행 입력"))
        model.undo(); XCTAssertEqual(model.blocks, added)
        model.undo(); XCTAssertEqual(model.blocks, original)
        model.redo(); model.redo(); await model.save()
        XCTAssertNil(model.errorDescription); XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertTrue(try HWPXDocumentPackage.load(from: Data(contentsOf: url)).blocks.contains { $0.text == "새 행 입력" })
    }

    func testViewModelTableStructureStillRejectsExternalFileChanges() async throws {
        let data = try fixturePackage().sourceData
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        try data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url); await model.load()
        let selected = try XCTUnwrap(model.blocks.first { $0.tableLocation != nil })
        try await model.editTable(.columnAfter, selectedID: selected.id)
        let external = try LegacyHWPXConverter.convert(text: "외부 수정")
        try external.write(to: url); await model.save()
        XCTAssertNotNil(model.errorDescription); XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertEqual(try Data(contentsOf: url), external)
    }

    func testViewModelRepeatedHWPStructureOperationsSaveToOriginalFormat() async throws {
        let data = try expandedHWPFixture()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwp")
        try data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url); await model.load()
        var selected = try XCTUnwrap(model.blocks.first {
            HWPTableStructureEditing.available(blocks: model.blocks, selectedID: $0.id, layouts: model.pageLayouts).filter { HWPTableStructureAction.trackActions.contains($0) }.count == 6
        }).id
        for action in [HWPTableStructureAction.rowBelow, .columnAfter, .deleteRow] {
            selected = try await model.editTable(action, selectedID: selected)
        }
        let expected = model.blocks
        model.undo(); model.redo(); XCTAssertEqual(model.blocks, expected)
        await model.save(); XCTAssertNil(model.errorDescription)
        let reopened = try HWP5StructuredDocumentParser.parse(from: Data(contentsOf: url))
        XCTAssertTrue(zip(reopened.blocks, expected).allSatisfy { HWPDocumentFormatting.matches($0, $1) })
    }

    private func expandedHWPFixture() throws -> Data {
        var data = try fixture("hangul_design_application", ext: "hwp")
        var source = try HWP5StructuredDocumentParser.parse(from: data)
        var selected = try XCTUnwrap(source.blocks.first {
            HWPTableStructureEditing.available(blocks: source.blocks, selectedID: $0.id, layouts: source.pageLayouts).contains(.columnAfter)
        })
        let table = selected.tableLocation!.table
        for action in [HWPTableStructureAction.rowBelow, .columnAfter] {
            let plan = try HWPTableStructureEditing.plan(action, blocks: source.blocks, selectedID: selected.id, layouts: source.pageLayouts)
            data = try HWPTableStructureWriter.hwp(data, blocks: source.blocks, plan: plan)
            source = try HWP5StructuredDocumentParser.parse(from: data)
            selected = try XCTUnwrap(source.blocks.first { $0.tableLocation?.table == table })
        }
        return data
    }

    private func fixturePackage(mergedRows: Bool = false, mergedColumns: Bool = false) throws -> HWPXDocumentPackage {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "\n표 뒤"))
        var table = HWPCellFormattingTests.tableXML
        if mergedRows {
            let cells = try HWPFormattingXML.elements(table, name: "tc")
            table = (table as NSString).replacingCharacters(in: cells[2].range, with: "")
            let merged = cells[0].xml.replacingOccurrences(of: "rowSpan=\"1\"", with: "rowSpan=\"2\"")
                .replacingOccurrences(of: "height=\"9000\"", with: "height=\"18000\"")
            table = (table as NSString).replacingCharacters(in: cells[0].range, with: merged)
        } else if mergedColumns {
            let cells = try HWPFormattingXML.elements(table, name: "tc")
            table = (table as NSString).replacingCharacters(in: cells[1].range, with: "")
            let merged = cells[0].xml.replacingOccurrences(of: "colSpan=\"1\"", with: "colSpan=\"2\"")
                .replacingOccurrences(of: "width=\"12000\"", with: "width=\"24000\"")
            table = (table as NSString).replacingCharacters(in: cells[0].range, with: merged)
        }
        let section = package.sections[0]
        let first = try XCTUnwrap(HWPFormattingXML.elements(section.xml, name: "p").first)
        let xml = (section.xml as NSString).replacingCharacters(in: first.range,
            with: first.xml.replacingOccurrences(of: "</hp:run>", with: table + "</hp:run>"))
        return try HWPXDocumentPackage.load(from: HWPXEditingArchive(data: package.sourceData).repack(replacing: [section.path: Data(xml.utf8)]))
    }

    private func fixture(_ name: String, ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "HWPXViewerFixtures")))
    }
}
