import XCTest
@testable import shortcuts_example

@MainActor
final class HWPTableSizingTests: XCTestCase {
    func testSelectionReportsCurrentSizeAndPageLimits() throws {
        let source = try fixture()
        let target = try firstCell(source)
        let selection = try XCTUnwrap(HWPTableSizing.selection(blocks: source.blocks, selectedID: target.id, layouts: source.layouts))
        XCTAssertEqual(selection.width, 120, accuracy: 0.03); XCTAssertEqual(selection.height, 90, accuracy: 0.03)
        XCTAssertEqual(selection.rowSpan, 1); XCTAssertEqual(selection.columnSpan, 1)
        let page = source.layouts[0]
        XCTAssertLessThanOrEqual(selection.maximumWidth + 120, page.widthPoints - page.leftMarginPoints - page.rightMarginPoints + 0.03)
        XCTAssertNil(HWPTableSizing.selection(blocks: source.blocks, selectedID: source.blocks.last!.id, layouts: source.layouts))
    }

    func testRawResizeUpdatesWholeRowAndColumnWithoutChangingOtherTracksContentOrStyles() throws {
        let source = try fixture(), selected = try firstCell(source)
        let result = try resizedRaw(source, selected.id, .init(widthPoints: 80, heightPoints: 60))
        XCTAssertEqual(result.blocks.map(\.text), source.blocks.map(\.text))
        for (old, new) in zip(source.blocks, result.blocks) {
            XCTAssertTrue(HWPDocumentFormatting.matches(old, new))
            if let cell = new.tableLocation {
                XCTAssertEqual(cell.cellWidthPoints ?? 0, cell.column == 0 ? 80 : 120, accuracy: 0.03)
                XCTAssertEqual(cell.cellHeightPoints ?? 0, cell.row == 0 ? 60 : 90, accuracy: 0.03)
                XCTAssertEqual(cell.rowSpan, old.tableLocation?.rowSpan); XCTAssertEqual(cell.columnSpan, old.tableLocation?.columnSpan)
                XCTAssertEqual(cell.tablePlacement?.widthPoints ?? 0, 200, accuracy: 0.03)
                XCTAssertEqual(cell.tablePlacement?.heightPoints ?? 0, 150, accuracy: 0.03)
            }
        }
        try assertAssets(source.data, result.data)
    }

    func testResizingOnlyOneDimensionLeavesTheOtherUnchanged() throws {
        for dimensions in [HWPTableDimensions(widthPoints: 160), .init(heightPoints: 120)] {
            let source = try fixture(), target = try firstCell(source)
            let result = try resizedRaw(source, target.id, dimensions)
            for (old, new) in zip(source.blocks, result.blocks) where old.tableLocation != nil {
                if dimensions.heightPoints == nil { XCTAssertEqual(new.tableLocation?.cellHeightPoints, old.tableLocation?.cellHeightPoints) }
                if dimensions.widthPoints == nil { XCTAssertEqual(new.tableLocation?.cellWidthPoints, old.tableLocation?.cellWidthPoints) }
            }
        }
    }

    func testMergedColumnRangeScalesProportionallyAndKeepsSpan() throws {
        var source = try fixture()
        source = try resizedRaw(source, firstCell(source).id, .init(widthPoints: 80))
        source = try structuralRaw(source, .mergeRight, firstCell(source).id)
        let target = try firstCell(source)
        let result = try resizedRaw(source, target.id, .init(widthPoints: 300))
        let merged = try firstCell(result)
        XCTAssertEqual(merged.tableLocation?.columnSpan, 2)
        XCTAssertEqual(merged.tableLocation?.cellWidthPoints ?? 0, 300, accuracy: 0.03)
        let bottom = result.blocks.filter { $0.tableLocation?.row == 1 }
        XCTAssertEqual(bottom[0].tableLocation?.cellWidthPoints ?? 0, 120, accuracy: 0.03)
        XCTAssertEqual(bottom[1].tableLocation?.cellWidthPoints ?? 0, 180, accuracy: 0.03)
        XCTAssertEqual(result.blocks.map(\.text), source.blocks.map(\.text))
    }

    func testMergedRowRangeScalesProportionallyAndHiddenTracksRemainResizable() throws {
        var source = try fixture()
        source = try resizedRaw(source, firstCell(source).id, .init(heightPoints: 60))
        source = try structuralRaw(source, .mergeBelow, firstCell(source).id)
        source = try resizedRaw(source, firstCell(source).id, .init(heightPoints: 200))
        let right = source.blocks.filter { $0.tableLocation?.column == 1 }
        XCTAssertEqual(right[0].tableLocation?.cellHeightPoints ?? 0, 80, accuracy: 0.03)
        XCTAssertEqual(right[1].tableLocation?.cellHeightPoints ?? 0, 120, accuracy: 0.03)
        source = try structuralRaw(source, .mergeRight, firstCell(source).id)
        let result = try resizedRaw(source, firstCell(source).id, .init(widthPoints: 280, heightPoints: 180))
        let selected = try XCTUnwrap(HWPTableSizing.selection(blocks: result.blocks, selectedID: firstCell(result).id, layouts: result.layouts))
        XCTAssertEqual(selected.rowSpan, 2); XCTAssertEqual(selected.columnSpan, 2)
        XCTAssertEqual(selected.width, 280, accuracy: 0.03); XCTAssertEqual(selected.height, 180, accuracy: 0.03)
    }

    func testInvalidAndOversizeValuesAreRejectedBeforeSourceChanges() throws {
        let source = try fixture(), target = try firstCell(source)
        let selection = try XCTUnwrap(HWPTableSizing.selection(blocks: source.blocks, selectedID: target.id, layouts: source.layouts))
        for value in [Double.nan, .infinity, -.infinity, 0, -10, 1, selection.maximumWidth + 1] {
            XCTAssertThrowsError(try resizedRaw(source, target.id, .init(widthPoints: value)), "width \(value)")
        }
        for value in [Double.nan, .infinity, 0, -10, 1, selection.maximumHeight + 1] {
            XCTAssertThrowsError(try resizedRaw(source, target.id, .init(heightPoints: value)), "height \(value)")
        }
        XCTAssertEqual(try source.serialized(source.blocks), source.data)
    }

    func testHeightCanShrinkButNeverCutsOffMultipleParagraphs() async throws {
        let source = try fixture(), target = try firstCell(source)
        let result = try await source.editing(.resize, blocks: source.blocks, selectedID: target.id, dimensions: .init(heightPoints: 10))
        let focused = try XCTUnwrap(result.document.blocks.first { $0.id == result.focusedID })
        let members = result.document.blocks.filter { HWPCellFormatting.sameCell($0, focused) }
        let height = try XCTUnwrap(focused.tableLocation?.cellHeightPoints)
        XCTAssertGreaterThan(height, 10); XCTAssertLessThan(height, 90)
        XCTAssertEqual(members.map(\.text), ["첫 문단", "둘째 문단"])
        let bottom = members.flatMap(\.lineLayouts).map { $0.verticalPositionPoints + $0.lineHeightPoints }.max() ?? 0
        XCTAssertGreaterThanOrEqual(height + 0.03, bottom + focused.tableLocation!.cellMarginTopPoints + focused.tableLocation!.cellMarginBottomPoints)
        for cell in result.document.blocks.compactMap(\.tableLocation) where cell.row == 1 {
            XCTAssertEqual(cell.cellHeightPoints ?? 0, 90, accuracy: 0.03)
        }
    }

    func testNarrowColumnRewrapsLongTextAndKeepsFollowingBodyBelowTable() async throws {
        let source = try fixture(), target = try firstCell(source)
        var blocks = source.blocks
        let index = try XCTUnwrap(blocks.firstIndex { $0.id == target.id })
        blocks[index] = HWPTextRunEditing.replacingText(in: target, with: String(repeating: "길어진 한글 내용 ", count: 15))
        let result = try await source.editing(.resize, blocks: blocks, selectedID: target.id, dimensions: .init(widthPoints: 65, heightPoints: 20))
        let edited = result.document.blocks[index]
        XCTAssertEqual(edited.text, blocks[index].text)
        XCTAssertEqual(edited.tableLocation?.cellWidthPoints ?? 0, 65, accuracy: 0.03)
        XCTAssertGreaterThan(edited.tableLocation?.cellHeightPoints ?? 0, 90)
        try assertBodyBelowTable(result.document)
    }

    func testRealDocumentsKeepPendingTextStylesAssetsAndFurtherStructuralEditing() async throws {
        for (name, ext) in [("hangul_design_application", "hwp"), ("mss_voucher", "hwpx")] {
            var source = try HWPTableStructureDocument.load(file(name, ext))
            let selected = try XCTUnwrap(source.blocks.first { HWPTableSizing.selection(blocks: source.blocks, selectedID: $0.id, layouts: source.layouts) != nil })
            let selection = try XCTUnwrap(HWPTableSizing.selection(blocks: source.blocks, selectedID: selected.id, layouts: source.layouts))
            var blocks = source.blocks
            let index = try XCTUnwrap(blocks.firstIndex { $0.id == selected.id })
            blocks[index] = HWPTextRunEditing.replacingText(in: selected, with: "크기 편집 한글 👨‍👩‍👧‍👦")
            blocks[index] = HWPDocumentFormatting.apply(.bold(true), to: blocks[index], range: NSRange(location: 0, length: blocks[index].text.utf16.count))
            var style = HWPCellFormat(selected.tableLocation!); style.setFill(0xDDEBF7)
            blocks[index] = HWPCellFormatting.apply(style, to: blocks[index])
            blocks = HWPCellFormatting.propagating(blocks[index], from: selected, in: blocks)
            let requested = blocks[index]
            let result = try await source.editing(.resize, blocks: blocks, selectedID: selected.id,
                dimensions: .init(widthPoints: max(10, selection.width * 0.9), heightPoints: max(20, selection.height * 0.9)))
            source = result.document
            let retained = try XCTUnwrap(source.blocks.first { $0.id == result.focusedID })
            XCTAssertTrue(HWPDocumentFormatting.matches(retained, requested))
            let next = try await source.editing(.columnAfter, blocks: source.blocks, selectedID: retained.id)
            XCTAssertTrue(next.document.blocks.contains { $0.text == requested.text })
            let saved = try HWPTableStructureDocument.load(next.document.serialized(next.document.blocks))
            XCTAssertEqual(saved.blocks.map(\.text), next.document.blocks.map(\.text))
            try assertAssets(try file(name, ext), saved.data, stylesMayChange: true)
        }
    }

    func testRepeatedResizeShrinksAndGrowsWithoutDriftingOtherColumns() async throws {
        var source = try fixture(), selected = try firstCell(source).id
        for width in [80.0, 140, 70, 120] {
            let result = try await source.editing(.resize, blocks: source.blocks, selectedID: selected, dimensions: .init(widthPoints: width, heightPoints: 60))
            source = result.document; selected = result.focusedID
            for cell in source.blocks.compactMap(\.tableLocation) {
                XCTAssertEqual(cell.cellWidthPoints ?? 0, cell.column == 0 ? width : 120, accuracy: 0.03)
            }
            try assertBodyBelowTable(source)
        }
    }

    func testPendingShortCellInputKeepsUncachedTableOwnerAndFollowingBodyApart() throws {
        let source = try fixture(), target = try firstCell(source)
        XCTAssertTrue(source.blocks[0].lineLayouts.isEmpty)
        var changed = source.blocks
        let index = try XCTUnwrap(changed.firstIndex { $0.id == target.id })
        changed[index] = HWPTextRunEditing.replacingText(in: target, with: "첫 문단크기 ")
        changed = HWPFlowLayout.reflowingEdit(changed, before: source.blocks, startingAt: target.id, layouts: source.layouts)
        XCTAssertEqual(changed[index].tableLocation?.cellHeightPoints ?? 0, 90, accuracy: 0.03)
        let anchor = try XCTUnwrap(changed[index].tableLocation?.tableAnchor)
        let body = try XCTUnwrap(changed.last?.lineLayouts.first)
        XCTAssertGreaterThanOrEqual(body.verticalPositionPoints, anchor.verticalPositionPoints + 180)
        try assertBodyBelowTable(HWPTableStructureDocument.load(source.serialized(changed)))
    }

    func testViewModelTableSizingUndoRedoKeepsUnsavedInputAndOriginalFile() async throws {
        let source = try fixture(), url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        try source.data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url); await model.load()
        let before = model.blocks, target = try firstCell(source)
        model.commitInlineBlock(HWPTextRunEditing.replacingText(in: target, with: "크기 입력"))
        let typed = model.blocks
        let tableBottom = (typed[1].tableLocation?.tableAnchor?.verticalPositionPoints ?? 0) + 180
        XCTAssertGreaterThanOrEqual(typed.last!.lineLayouts.first?.verticalPositionPoints ?? -1, tableBottom)
        let id = try await model.editTable(.resize, selectedID: target.id, dimensions: .init(widthPoints: 80, heightPoints: 60))
        let after = model.blocks
        XCTAssertEqual(try Data(contentsOf: url), source.data)
        model.undo(); XCTAssertEqual(model.blocks, typed)
        XCTAssertGreaterThanOrEqual(model.blocks.last!.lineLayouts.first?.verticalPositionPoints ?? -1, tableBottom)
        model.undo(); XCTAssertEqual(model.blocks, before); XCTAssertFalse(model.hasUnsavedChanges)
        model.redo(); model.redo(); XCTAssertEqual(model.blocks, after)
        let newCell = try XCTUnwrap(model.blocks.first { $0.id == id })
        XCTAssertEqual(newCell.text, "크기 입력")
        await model.save(); XCTAssertNil(model.errorDescription); XCTAssertFalse(model.hasUnsavedChanges)
        let saved = try HWPXDocumentPackage.load(from: Data(contentsOf: url))
        XCTAssertEqual(saved.blocks.first { $0.text == "크기 입력" }?.tableLocation?.cellWidthPoints ?? 0, 80, accuracy: 0.03)
    }

    func testViewModelHWPResizeRepeatedSaveAndExternalFileConflict() async throws {
        let data = try file("hangul_design_application", "hwp")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwp")
        try data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url); await model.load()
        let first = try XCTUnwrap(model.blocks.first { HWPTableSizing.selection(blocks: model.blocks, selectedID: $0.id, layouts: model.pageLayouts) != nil })
        let selection = try XCTUnwrap(HWPTableSizing.selection(blocks: model.blocks, selectedID: first.id, layouts: model.pageLayouts))
        var id = try await model.editTable(.resize, selectedID: first.id, dimensions: .init(widthPoints: max(10, selection.width * 0.9)))
        await model.save(); XCTAssertNil(model.errorDescription)
        id = try await model.editTable(.resize, selectedID: id, dimensions: .init(widthPoints: max(10, selection.width * 0.8)))
        let after = model.blocks; model.undo(); model.redo(); XCTAssertEqual(model.blocks, after)
        await model.save(); XCTAssertNil(model.errorDescription)
        XCTAssertEqual(try HWP5StructuredDocumentParser.parse(from: Data(contentsOf: url)).blocks.map(\.text), model.blocks.map(\.text))
        try await model.editTable(.resize, selectedID: id, dimensions: .init(widthPoints: max(10, selection.width * 0.7)))
        try data.write(to: url); await model.save()
        XCTAssertNotNil(model.errorDescription); XCTAssertEqual(try Data(contentsOf: url), data)
    }

    private func resizedRaw(_ source: HWPTableStructureDocument, _ selected: String, _ dimensions: HWPTableDimensions) throws -> HWPTableStructureDocument {
        try raw(source, HWPTableStructureEditing.plan(.resize, blocks: source.blocks, selectedID: selected, layouts: source.layouts, dimensions: dimensions))
    }
    private func structuralRaw(_ source: HWPTableStructureDocument, _ action: HWPTableStructureAction, _ selected: String) throws -> HWPTableStructureDocument {
        try raw(source, HWPTableStructureEditing.plan(action, blocks: source.blocks, selectedID: selected, layouts: source.layouts))
    }
    private func raw(_ source: HWPTableStructureDocument, _ plan: HWPTableStructureEditing.Plan) throws -> HWPTableStructureDocument {
        switch source {
        case .hwpx(let p): return try HWPTableStructureDocument.load(HWPTableStructureWriter.hwpx(p, plan: plan))
        case .hwp(_, let d): return try HWPTableStructureDocument.load(HWPTableStructureWriter.hwp(d, blocks: source.blocks, plan: plan))
        }
    }
    private func firstCell(_ source: HWPTableStructureDocument) throws -> HWPDocumentBlock { try XCTUnwrap(source.blocks.first { $0.tableLocation != nil }) }
    private func fixture() throws -> HWPTableStructureDocument {
        let base = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "\n표 뒤"))
        let section = base.sections[0], first = try XCTUnwrap(HWPFormattingXML.elements(base.sections[0].xml, name: "p").first)
        let xml = (section.xml as NSString).replacingCharacters(in: first.range, with: first.xml.replacingOccurrences(of: "</hp:run>", with: HWPCellFormattingTests.tableXML + "</hp:run>"))
        return try HWPTableStructureDocument.load(HWPXEditingArchive(data: base.sourceData).repack(replacing: [section.path: Data(xml.utf8)]))
    }
    private func file(_ name: String, _ ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: ext) ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "HWPXViewerFixtures")))
    }
    private func assertAssets(_ original: Data, _ result: Data, stylesMayChange: Bool = false) throws {
        if original.starts(with: [0x50, 0x4B]) {
            let a = try HWPXEditingArchive(data: original), b = try HWPXEditingArchive(data: result)
            for path in a.paths where path.hasPrefix("BinData/") || (!stylesMayChange && path == "Contents/header.xml") {
                XCTAssertEqual(try a.data(at: path), try b.data(at: path), path)
            }
        } else {
            let a = try OLECompoundFile(data: original), b = try OLECompoundFile(data: result)
            for path in a.streamNames where !path.hasPrefix("bodytext/") && path != "prvtext" && (!stylesMayChange || path != "docinfo") {
                XCTAssertEqual(try a.stream(named: path), try b.stream(named: path), path)
            }
        }
    }
    private func assertBodyBelowTable(_ source: HWPTableStructureDocument) throws {
        let table = source.blocks.filter { $0.tableLocation != nil }, body = try XCTUnwrap(source.blocks.last)
        let pages = HWPOriginalCanvasPageBuilder.makePages(blocks: source.blocks, layouts: source.layouts)
        let bodyPage = try XCTUnwrap(pages.firstIndex { $0.bodyBlocks.contains { $0.id == body.id } })
        let tablePage = try XCTUnwrap(pages.lastIndex { $0.bodyBlocks.contains { $0.tableLocation != nil } })
        XCTAssertGreaterThanOrEqual(bodyPage, tablePage)
        if bodyPage == tablePage {
            let bottom = HWPTableEditing.finalPageBottom(table, anchorY: table.first!.tableLocation!.tableAnchor?.verticalPositionPoints ?? 0, layout: source.layouts[0])
            XCTAssertGreaterThanOrEqual(body.lineLayouts[0].verticalPositionPoints + 0.03, bottom)
        }
    }
}
