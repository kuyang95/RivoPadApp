import XCTest
@testable import shortcuts_example

@MainActor
final class HWPEquationAndTextBoxEditingTests: XCTestCase {
    func testHWPXTextBoxInsertionRoundTrip() async throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "앞뒤"))
        let source = HWPTableStructureDocument.hwpx(package)
        let selection = try XCTUnwrap(HWPShapeEditing.selection(blocks: source.blocks,
            selectedID: source.blocks[0].id, range: NSRange(location: 1, length: 0), layouts: source.layouts))
        let result = try await HWPTextBoxEditing.inserting(.init(selection: selection,
            text: "새 글상자", widthPoints: 180, heightPoints: 90), source: source, drafts: source.blocks)
        let owner = try XCTUnwrap(result.document.blocks.first { $0.id == result.focusedID })
        let object = try XCTUnwrap(owner.canvasObjects.first { $0.textContainerID != nil })
        let container = try XCTUnwrap(object.textContainerID)
        XCTAssertEqual(result.document.blocks.first { $0.layoutContainerID == container }?.text, "새 글상자")
        let reopened = try HWPTableStructureDocument.load(result.document.data)
        XCTAssertTrue(reopened.blocks.contains { $0.text == "새 글상자" && $0.layoutContainerID != nil })
    }

    func testHWPTextBoxInsertionRoundTrip() async throws {
        let source = try HWPTableStructureDocument.load(fixture("hangul_design_application", "hwp"))
        let selection = try XCTUnwrap(source.blocks.compactMap { block in
            HWPShapeEditing.selection(blocks: source.blocks, selectedID: block.id,
                range: NSRange(location: block.text.utf16.count, length: 0), layouts: source.layouts)
        }.first)
        let result = try await HWPTextBoxEditing.inserting(.init(selection: selection,
            text: "바이너리 글상자", widthPoints: 180, heightPoints: 90), source: source, drafts: source.blocks)
        let reopened = try HWPTableStructureDocument.load(result.document.data)
        XCTAssertTrue(reopened.blocks.contains { $0.text == "바이너리 글상자" && $0.layoutContainerID != nil })
        XCTAssertTrue(reopened.blocks.flatMap(\.canvasObjects).contains { $0.textContainerID != nil })
    }
    func testHWPXEquationInsertUpdateDeleteRoundTrip() async throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "앞뒤"))
        let source = HWPTableStructureDocument.hwpx(package)
        let selection = try XCTUnwrap(HWPEquationEditing.selection(blocks: package.blocks,
            selectedID: package.blocks[0].id, range: NSRange(location: 1, length: 0), layouts: package.pageLayouts))
        let inserted = try await HWPEquationEditing.inserting(.init(selection: selection,
            script: "{a} over {b}", fontSizePoints: 13), source: source, drafts: package.blocks)
        XCTAssertEqual(inserted.document.blocks.map(\.text), ["앞", "", "뒤"])
        let owner = inserted.document.blocks[1]
        let object = try XCTUnwrap(owner.canvasObjects.first)
        guard case .equation(let equation) = object.content else { return XCTFail("Inserted object is not an equation") }
        XCTAssertEqual(equation.script, "{a} over {b}")
        XCTAssertEqual(equation.fontSizePoints, 13, accuracy: 0.02)

        let target = try XCTUnwrap(HWPEquationEditing.target(owner: owner, object: object))
        let changed = try await HWPEquationEditing.applying(.update(.init(script: "sqrt {x}+y^{2}",
            fontSizePoints: 16)), target: target, source: inserted.document, drafts: inserted.document.blocks)
        let changedOwner = changed.document.blocks[1]
        let changedObject = try XCTUnwrap(changedOwner.canvasObjects.first)
        guard case .equation(let changedEquation) = changedObject.content else { return XCTFail("Updated object is not an equation") }
        XCTAssertEqual(changedEquation.script, "sqrt {x}+y^{2}")
        XCTAssertEqual(changedEquation.fontSizePoints, 16, accuracy: 0.02)

        let changedTarget = try XCTUnwrap(HWPEquationEditing.target(owner: changedOwner, object: changedObject))
        let deleted = try await HWPEquationEditing.applying(.delete, target: changedTarget,
            source: changed.document, drafts: changed.document.blocks)
        XCTAssertTrue(deleted.document.blocks[1].canvasObjects.isEmpty)
        _ = try HWPXDocumentPackage.load(from: deleted.document.data)
    }

    func testHWPEquationInsertUpdateDeleteRoundTrip() async throws {
        let source = try HWPTableStructureDocument.load(fixture("hangul_design_application", "hwp"))
        let selection = try XCTUnwrap(source.blocks.compactMap { block in
            HWPEquationEditing.selection(blocks: source.blocks, selectedID: block.id,
                range: NSRange(location: block.text.utf16.count, length: 0), layouts: source.layouts)
        }.first)
        let inserted = try await HWPEquationEditing.inserting(.init(selection: selection,
            script: "x^{2}+y^{2}", fontSizePoints: 12), source: source, drafts: source.blocks)
        let owner = try XCTUnwrap(inserted.document.blocks.first { $0.id == inserted.focusedID })
        let object = try XCTUnwrap(owner.canvasObjects.first { if case .equation = $0.content { return true }; return false })
        let target = try XCTUnwrap(HWPEquationEditing.target(owner: owner, object: object))
        let changed = try await HWPEquationEditing.applying(.update(.init(script: "{1} over {2}",
            fontSizePoints: 15)), target: target, source: inserted.document, drafts: inserted.document.blocks)
        let changedOwner = try XCTUnwrap(changed.document.blocks.first { $0.id == changed.focusedID })
        let changedObject = try XCTUnwrap(changedOwner.canvasObjects.first { if case .equation = $0.content { return true }; return false })
        guard case .equation(let equation) = changedObject.content else { return XCTFail("Updated object is not an equation") }
        XCTAssertEqual(equation.script, "{1} over {2}")
        XCTAssertEqual(equation.fontSizePoints, 15, accuracy: 0.02)

        let changedTarget = try XCTUnwrap(HWPEquationEditing.target(owner: changedOwner, object: changedObject))
        let deleted = try await HWPEquationEditing.applying(.delete, target: changedTarget,
            source: changed.document, drafts: changed.document.blocks)
        let reopened = try HWPTableStructureDocument.load(deleted.document.data)
        XCTAssertFalse(reopened.blocks.flatMap(\.canvasObjects).contains { if case .equation = $0.content { return true }; return false })
    }

    func testHWPXTextBoxContentEditPreservesContainerAndParagraphs() async throws {
        let source = try textBoxDocument()
        let owner = try XCTUnwrap(source.blocks.first { !$0.canvasObjects.isEmpty })
        let object = try XCTUnwrap(owner.canvasObjects.first { $0.textContainerID != nil })
        let target = try XCTUnwrap(HWPTextBoxEditing.target(owner: owner, object: object, blocks: source.blocks))
        XCTAssertEqual(target.entries.map(\.text), ["첫 문단", "둘째 문단"])

        let changed = try await HWPTextBoxEditing.applying(.init(texts: ["바뀐 첫 문단", "바뀐 둘째 문단"]),
            target: target, source: source, drafts: source.blocks)
        let reopened = try HWPTableStructureDocument.load(changed.document.data)
        let reopenedOwner = try XCTUnwrap(reopened.blocks.first { !$0.canvasObjects.isEmpty })
        let reopenedObject = try XCTUnwrap(reopenedOwner.canvasObjects.first { $0.textContainerID != nil })
        let reopenedTarget = try XCTUnwrap(HWPTextBoxEditing.target(owner: reopenedOwner,
            object: reopenedObject, blocks: reopened.blocks))
        XCTAssertEqual(reopenedTarget.entries.map(\.text), ["바뀐 첫 문단", "바뀐 둘째 문단"])
        XCTAssertEqual(reopenedTarget.containerID, target.containerID)
    }

    func testHWPXTextBoxCanAddRemoveAndReorderParagraphsWhilePreservingInnerEquation() async throws {
        let source = try textBoxDocument(includingEquation: true)
        let owner = try XCTUnwrap(source.blocks.first { !$0.canvasObjects.isEmpty && $0.layoutContainerID == nil })
        let object = try XCTUnwrap(owner.canvasObjects.first { $0.textContainerID != nil })
        let target = try XCTUnwrap(HWPTextBoxEditing.target(owner: owner, object: object, blocks: source.blocks))
        XCTAssertEqual(target.internalObjectCount, 2)
        let update = HWPTextBoxEditing.Update(paragraphs: [
            .init(sourceID: target.entries[1].id, text: "둘째 문단"),
            .init(sourceID: nil, text: "새 가운데 문단"),
            .init(sourceID: target.entries[0].id, text: "첫 문단 이동")
        ])
        let changed = try await HWPTextBoxEditing.applying(update, target: target,
            source: source, drafts: source.blocks)
        let changedOwner = try XCTUnwrap(changed.document.blocks.first { $0.id == target.ownerID })
        let changedObject = try XCTUnwrap(changedOwner.canvasObjects.first { $0.textContainerID != nil })
        let changedTarget = try XCTUnwrap(HWPTextBoxEditing.target(owner: changedOwner,
            object: changedObject, blocks: changed.document.blocks))
        XCTAssertEqual(changedTarget.entries.map(\.text), ["둘째 문단", "새 가운데 문단", "첫 문단 이동"])
        XCTAssertEqual(changedTarget.internalObjectCount, 2)

        let equationOwner = try XCTUnwrap(changed.document.blocks.first {
            $0.layoutContainerID == changedTarget.containerID
                && $0.canvasObjects.contains { if case .equation = $0.content { return true }; return false }
        })
        let equationObject = try XCTUnwrap(equationOwner.canvasObjects.first {
            if case .equation = $0.content { return true }; return false
        })
        let equationTarget = try XCTUnwrap(HWPEquationEditing.target(owner: equationOwner, object: equationObject))
        let equationChanged = try await HWPEquationEditing.applying(.update(.init(script: "x^{3}", fontSizePoints: 14)),
            target: equationTarget, source: changed.document, drafts: changed.document.blocks)
        let shapeOwner = try XCTUnwrap(equationChanged.document.blocks.first {
            $0.layoutContainerID == changedTarget.containerID
                && $0.canvasObjects.contains { if case .shape = $0.content { return true }; return false }
        })
        let shapeObject = try XCTUnwrap(shapeOwner.canvasObjects.first {
            if case .shape = $0.content { return true }; return false
        })
        let shapeTarget = try XCTUnwrap(HWPShapeEditing.target(owner: shapeOwner, object: shapeObject))
        let shapeLayout = HWPShapeEditing.Layout(xPoints: shapeTarget.xPoints, yPoints: shapeTarget.yPoints,
            widthPoints: shapeTarget.widthPoints, heightPoints: shapeTarget.heightPoints,
            zOrder: shapeTarget.zOrder, rotationDegrees: shapeTarget.rotationDegrees,
            strokeColorRGB: 0xCC_3300, strokeWidthPoints: max(shapeTarget.strokeWidthPoints, 0.5),
            strokeStyle: shapeTarget.strokeStyle, fillColorRGB: shapeTarget.fillColorRGB,
            shadow: shapeTarget.shadow, isInline: shapeTarget.isInline,
            horizontalReference: shapeTarget.horizontalReference,
            verticalReference: shapeTarget.verticalReference,
            horizontalAlignment: shapeTarget.horizontalAlignment,
            verticalAlignment: shapeTarget.verticalAlignment, wrap: shapeTarget.wrap,
            marginLeftPoints: shapeTarget.marginLeftPoints, marginRightPoints: shapeTarget.marginRightPoints,
            marginTopPoints: shapeTarget.marginTopPoints, marginBottomPoints: shapeTarget.marginBottomPoints,
            pathPoints: shapeTarget.pathPoints, startArrow: shapeTarget.startArrow, endArrow: shapeTarget.endArrow)
        let shapeChanged = try await HWPShapeEditing.applying(.update(shapeLayout), target: shapeTarget,
            source: equationChanged.document, drafts: equationChanged.document.blocks)
        let reopened = try HWPTableStructureDocument.load(shapeChanged.document.data)
        XCTAssertTrue(reopened.blocks.flatMap(\.canvasObjects).contains {
            if case .equation(let equation) = $0.content { return equation.script == "x^{3}" }
            return false
        })
        XCTAssertTrue(reopened.blocks.flatMap(\.canvasObjects).contains {
            if case .shape(let shape) = $0.content { return shape.stroke.colorRGB == 0xCC_3300 }
            return false
        })
    }

    func testHWPTextBoxCanAddAndRemoveParagraphsRoundTrip() async throws {
        let source = try HWPTableStructureDocument.load(fixture("hangul_design_application", "hwp"))
        let selection = try XCTUnwrap(source.blocks.compactMap { block in
            HWPShapeEditing.selection(blocks: source.blocks, selectedID: block.id,
                range: NSRange(location: block.text.utf16.count, length: 0), layouts: source.layouts)
        }.first)
        let inserted = try await HWPTextBoxEditing.inserting(.init(selection: selection,
            text: "기존 문단", widthPoints: 180, heightPoints: 100), source: source, drafts: source.blocks)
        let owner = try XCTUnwrap(inserted.document.blocks.first { $0.id == inserted.focusedID })
        let object = try XCTUnwrap(owner.canvasObjects.first { $0.textContainerID != nil })
        let target = try XCTUnwrap(HWPTextBoxEditing.target(owner: owner, object: object,
            blocks: inserted.document.blocks))
        let expanded = try await HWPTextBoxEditing.applying(.init(paragraphs: [
            .init(sourceID: target.entries[0].id, text: "고친 기존 문단"),
            .init(sourceID: nil, text: "새 둘째 문단"),
            .init(sourceID: nil, text: "새 셋째 문단")
        ]), target: target, source: inserted.document, drafts: inserted.document.blocks)
        let expandedOwner = try XCTUnwrap(expanded.document.blocks.first { $0.id == target.ownerID })
        let expandedObject = try XCTUnwrap(expandedOwner.canvasObjects.first { $0.textContainerID != nil })
        let expandedTarget = try XCTUnwrap(HWPTextBoxEditing.target(owner: expandedOwner,
            object: expandedObject, blocks: expanded.document.blocks))
        XCTAssertEqual(expandedTarget.entries.map(\.text), ["고친 기존 문단", "새 둘째 문단", "새 셋째 문단"])

        let reduced = try await HWPTextBoxEditing.applying(.init(paragraphs: [
            .init(sourceID: expandedTarget.entries[2].id, text: "셋째를 첫째로"),
            .init(sourceID: expandedTarget.entries[0].id, text: "기존을 둘째로")
        ]), target: expandedTarget, source: expanded.document, drafts: expanded.document.blocks)
        let reopened = try HWPTableStructureDocument.load(reduced.document.data)
        let reopenedOwner = try XCTUnwrap(reopened.blocks.first { $0.id == target.ownerID })
        let reopenedObject = try XCTUnwrap(reopenedOwner.canvasObjects.first { $0.textContainerID != nil })
        let reopenedTarget = try XCTUnwrap(HWPTextBoxEditing.target(owner: reopenedOwner,
            object: reopenedObject, blocks: reopened.blocks))
        XCTAssertEqual(reopenedTarget.entries.map(\.text), ["셋째를 첫째로", "기존을 둘째로"])
    }

    func testHWPXTextBoxTableCellDirectEditUndoRedoAndSave() async throws {
        let source = try textBoxDocument(includingTable: true)
        let cell = try XCTUnwrap(source.blocks.first {
            $0.layoutContainerID != nil && $0.tableLocation != nil && $0.text == "셀 원문"
        })
        XCTAssertTrue(HWPTableEditing.supports(cell))
        let session = HWPInlineEditingSession()
        let context = HWPInlineEditingContext(session: session,
            sources: [cell.id: cell], orderedBlocks: source.blocks)
        XCTAssertEqual(context.source(for: cell)?.id, cell.id)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".hwpx")
        try source.data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let loadedCell = try XCTUnwrap(model.blocks.first { $0.id == cell.id })
        model.commitInlineBlock(HWPTextRunEditing.replacingText(in: loadedCell,
            with: "글상자 표 수정"))
        XCTAssertEqual(model.blocks.first { $0.id == cell.id }?.text, "글상자 표 수정")
        model.undo()
        XCTAssertEqual(model.blocks.first { $0.id == cell.id }?.text, "셀 원문")
        model.redo()
        XCTAssertEqual(model.blocks.first { $0.id == cell.id }?.text, "글상자 표 수정")
        await model.save()
        XCTAssertNil(model.errorDescription)

        let reopened = try HWPTableStructureDocument.load(Data(contentsOf: url))
        let reopenedCell = try XCTUnwrap(reopened.blocks.first {
            $0.layoutContainerID == cell.layoutContainerID && $0.tableLocation != nil
        })
        XCTAssertEqual(reopenedCell.text, "글상자 표 수정")
        let owner = try XCTUnwrap(reopened.blocks.first { block in
            block.layoutContainerID == nil
                && block.canvasObjects.contains { $0.textContainerID == cell.layoutContainerID }
        })
        let object = try XCTUnwrap(owner.canvasObjects.first {
            $0.textContainerID == cell.layoutContainerID
        })
        let target = try XCTUnwrap(HWPTextBoxEditing.target(owner: owner,
            object: object, blocks: reopened.blocks))
        XCTAssertEqual(target.internalTableCount, 1)
    }

    func testRejectsInvalidEquationAndTextBoxUpdates() throws {
        let selection = HWPEquationEditing.Selection(blockID: "x", text: "", caret: 0, width: 100)
        XCTAssertFalse(HWPEquationEditing.Request(selection: selection, script: " ", fontSizePoints: 12).isValid)
        XCTAssertFalse(HWPEquationEditing.Update(script: "x", fontSizePoints: 200).isValid)
        XCTAssertFalse(HWPTextBoxEditing.Update(texts: []).isValid)
    }

    private func textBoxDocument(includingEquation: Bool = false,
                                 includingTable: Bool = false) throws -> HWPTableStructureDocument {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "본문"))
        let section = try XCTUnwrap(package.sections.first)
        let prefix = "hp:"
        let closing = "</\(prefix)run>"
        guard let range = section.xml.range(of: closing) else { throw HWPDocumentEditingError.invalidDocument }
        let equation = includingEquation ? "<\(prefix)equation id=\"9003\" zOrder=\"1\" numberingType=\"EQUATION\" textWrap=\"TOP_AND_BOTTOM\" textFlow=\"BOTH_SIDES\" lock=\"0\" dropcapstyle=\"None\" baseUnit=\"1200\" textColor=\"#000000\" baseLine=\"85\"><\(prefix)sz width=\"6000\" widthRelTo=\"ABSOLUTE\" height=\"3000\" heightRelTo=\"ABSOLUTE\" protect=\"0\"/><\(prefix)pos treatAsChar=\"1\" affectLSpacing=\"0\" flowWithText=\"1\" allowOverlap=\"0\" holdAnchorAndSO=\"0\" vertRelTo=\"PARA\" horzRelTo=\"PARA\" vertAlign=\"TOP\" horzAlign=\"LEFT\" vertOffset=\"0\" horzOffset=\"0\"/><\(prefix)script>x^{2}</\(prefix)script></\(prefix)equation>" : ""
        let line = includingEquation ? "<\(prefix)line id=\"9004\" zOrder=\"2\" numberingType=\"LINE\" textWrap=\"TOP_AND_BOTTOM\" textFlow=\"BOTH_SIDES\" lock=\"0\" dropcapstyle=\"None\"><\(prefix)sz width=\"5000\" widthRelTo=\"ABSOLUTE\" height=\"1000\" heightRelTo=\"ABSOLUTE\" protect=\"0\"/><\(prefix)pos treatAsChar=\"1\" affectLSpacing=\"0\" flowWithText=\"1\" allowOverlap=\"0\" holdAnchorAndSO=\"0\" vertRelTo=\"PARA\" horzRelTo=\"PARA\" vertAlign=\"TOP\" horzAlign=\"LEFT\" vertOffset=\"0\" horzOffset=\"0\"/><\(prefix)lineShape color=\"#000000\" width=\"75\" style=\"SOLID\"/></\(prefix)line>" : ""
        let table = includingTable ? "<\(prefix)tbl id=\"9010\" rowCnt=\"1\" colCnt=\"1\" borderFillIDRef=\"0\" pageBreak=\"CELL\"><\(prefix)sz width=\"16000\" height=\"4000\"/><\(prefix)pos treatAsChar=\"1\" vertRelTo=\"PARA\" horzRelTo=\"PARA\" vertAlign=\"TOP\" horzAlign=\"LEFT\" vertOffset=\"0\" horzOffset=\"0\"/><\(prefix)tr><\(prefix)tc borderFillIDRef=\"0\" hasMargin=\"1\"><\(prefix)subList vertAlign=\"TOP\"><\(prefix)p id=\"9011\" paraPrIDRef=\"0\" styleIDRef=\"0\"><\(prefix)run charPrIDRef=\"0\"><\(prefix)t>셀 원문</\(prefix)t></\(prefix)run><\(prefix)linesegarray><\(prefix)lineseg textpos=\"0\" vertpos=\"0\" vertsize=\"1000\" textheight=\"1000\" horzsize=\"15000\"/></\(prefix)linesegarray></\(prefix)p></\(prefix)subList><\(prefix)cellAddr rowAddr=\"0\" colAddr=\"0\"/><\(prefix)cellSpan rowSpan=\"1\" colSpan=\"1\"/><\(prefix)cellSz width=\"16000\" height=\"4000\"/><\(prefix)cellMargin left=\"400\" right=\"400\" top=\"400\" bottom=\"400\"/></\(prefix)tc></\(prefix)tr></\(prefix)tbl>" : ""
        let box = "<\(prefix)rect id=\"9000\" zOrder=\"0\" numberingType=\"RECTANGLE\" textWrap=\"TOP_AND_BOTTOM\" textFlow=\"BOTH_SIDES\" lock=\"0\" dropcapstyle=\"None\" ratio=\"0\"><\(prefix)sz width=\"18000\" widthRelTo=\"ABSOLUTE\" height=\"9000\" heightRelTo=\"ABSOLUTE\" protect=\"0\"/><\(prefix)pos treatAsChar=\"1\" affectLSpacing=\"0\" flowWithText=\"1\" allowOverlap=\"0\" holdAnchorAndSO=\"0\" vertRelTo=\"PARA\" horzRelTo=\"PARA\" vertAlign=\"TOP\" horzAlign=\"LEFT\" vertOffset=\"0\" horzOffset=\"0\"/><\(prefix)outMargin left=\"0\" right=\"0\" top=\"0\" bottom=\"0\"/><\(prefix)lineShape color=\"#1F5EA8\" width=\"75\" style=\"SOLID\"/><\(prefix)subList id=\"0\" textDirection=\"HORIZONTAL\" lineWrap=\"BREAK\" vertAlign=\"TOP\"><\(prefix)p id=\"9001\" paraPrIDRef=\"0\" styleIDRef=\"0\" pageBreak=\"0\" columnBreak=\"0\" merged=\"0\"><\(prefix)run charPrIDRef=\"0\"><\(prefix)t>첫 문단</\(prefix)t></\(prefix)run></\(prefix)p><\(prefix)p id=\"9002\" paraPrIDRef=\"0\" styleIDRef=\"0\" pageBreak=\"0\" columnBreak=\"0\" merged=\"0\"><\(prefix)run charPrIDRef=\"0\"><\(prefix)t>둘째 문단</\(prefix)t>\(equation)\(line)\(table)</\(prefix)run></\(prefix)p></\(prefix)subList></\(prefix)rect>"
        var xml = section.xml
        xml.insert(contentsOf: box, at: range.lowerBound)
        let data = try HWPXEditingArchive(data: package.sourceData).repack(replacing: [section.path: Data(xml.utf8)])
        return try HWPTableStructureDocument.load(data)
    }

    private func fixture(_ name: String, _ ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "HWPXViewerFixtures")))
    }
}
