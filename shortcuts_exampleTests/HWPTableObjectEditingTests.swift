import XCTest
import UIKit
@testable import shortcuts_example

@MainActor
final class HWPTableObjectEditingTests: XCTestCase {
    func testHWPXNestedTableCellFormattingAndListsRoundTrip() throws {
        try exerciseNestedCellFormattingAndLists(try nestedTableDocument())
    }

    func testHWPNestedTableCellFormattingAndListsRoundTrip() async throws {
        let source = try HWPTableStructureDocument.load(fixture("hangul_design_application", "hwp"))
        let outer = try await tableDocument(source, texts: ["바깥 HWP 셀"])
        let nested = try insertingNestedHWPTable(into: outer,
            owner: try XCTUnwrap(outer.blocks.first { $0.text == "바깥 HWP 셀" }))
        try exerciseNestedCellFormattingAndLists(nested)
    }

    func testHWPXNestedTableStructureAndSizingRoundTrip() async throws {
        try await exerciseNestedTableStructure(try nestedTableDocument())
    }

    func testHWPNestedTableStructureAndSizingRoundTrip() async throws {
        let source = try HWPTableStructureDocument.load(fixture("hangul_design_application", "hwp"))
        let outer = try await tableDocument(source, texts: ["바깥 HWP 셀"])
        let nested = try insertingNestedHWPTable(into: outer,
            owner: try XCTUnwrap(outer.blocks.first { $0.text == "바깥 HWP 셀" }))
        try await exerciseNestedTableStructure(nested)
    }

    func testHWPXNestedTableCellsInsertAndEditImageAndShapeRoundTrip() async throws {
        var document = try nestedTableDocument()
        let nested = document.blocks.filter { $0.tableLocation?.parent != nil }
            .sorted { ($0.tableLocation?.column ?? 0) < ($1.tableLocation?.column ?? 0) }
        XCTAssertEqual(nested.map(\.text), ["안쪽 그림 셀", "안쪽 도형 셀"])
        let parent = try XCTUnwrap(nested[0].tableLocation?.parent)
        let outerBefore = try XCTUnwrap(document.blocks.first {
            $0.tableLocation?.table == parent.table && $0.tableLocation?.row == parent.row
                && $0.tableLocation?.column == parent.column
        })
        let outerHeight = outerBefore.tableLocation?.cellHeightPoints ?? 0
        let bodyY = try XCTUnwrap(document.blocks.first { $0.text == "중첩 표 뒤 본문" })
            .lineLayouts.first?.verticalPositionPoints ?? 0

        let imageSelection = try XCTUnwrap(HWPImageEditing.selection(blocks: document.blocks,
            selectedID: nested[0].id, range: NSRange(location: 3, length: 0),
            layouts: document.layouts))
        let image = try HWPImageEditing.normalize(Self.png)
        document = try await HWPImageEditing.inserting(.init(selection: imageSelection,
            image: image, widthPoints: 104, heightPoints: 72),
            source: document, drafts: document.blocks).document

        let shapeCell = try XCTUnwrap(document.blocks.first { $0.id == nested[1].id })
        let shapeSelection = try XCTUnwrap(HWPShapeEditing.selection(blocks: document.blocks,
            selectedID: shapeCell.id, range: NSRange(location: 3, length: 0),
            layouts: document.layouts))
        document = try await HWPShapeEditing.inserting(.init(selection: shapeSelection,
            kind: .ellipse, widthPoints: 98, heightPoints: 68),
            source: document, drafts: document.blocks).document

        var imageOwner = try XCTUnwrap(document.blocks.first { $0.id == nested[0].id })
        var imageObject = try XCTUnwrap(imageOwner.canvasObjects.first {
            if case .image = $0.content { return true }; return false
        })
        var imageTarget = try XCTUnwrap(HWPImageEditing.target(owner: imageOwner, object: imageObject))
        let imageUpdate = try XCTUnwrap(HWPImageEditing.directUpdate(
            .resize(anchor: .bottomTrailing, deltaX: 24, deltaY: 36), target: imageTarget))
        document = try await HWPImageEditing.applying(
            .update(imageUpdate.crop, imageUpdate.dimensions, imageUpdate.presentation, imageUpdate.appearance),
            target: imageTarget, source: document, drafts: document.blocks).document

        var shapeOwner = try XCTUnwrap(document.blocks.first { $0.id == nested[1].id })
        var shapeObject = try XCTUnwrap(shapeOwner.canvasObjects.first {
            if case .shape = $0.content { return true }; return false
        })
        var shapeTarget = try XCTUnwrap(HWPShapeEditing.target(owner: shapeOwner, object: shapeObject))
        let shapeUpdate = try XCTUnwrap(HWPShapeEditing.directLayout(
            .rotate(deltaDegrees: 27), target: shapeTarget))
        document = try await HWPShapeEditing.applying(.update(shapeUpdate), target: shapeTarget,
            source: document, drafts: document.blocks).document

        let reopened = try HWPTableStructureDocument.load(document.data)
        imageOwner = try XCTUnwrap(reopened.blocks.first { $0.id == nested[0].id })
        imageObject = try XCTUnwrap(imageOwner.canvasObjects.first {
            if case .image = $0.content { return true }; return false
        })
        imageTarget = try XCTUnwrap(HWPImageEditing.target(owner: imageOwner, object: imageObject))
        shapeOwner = try XCTUnwrap(reopened.blocks.first { $0.id == nested[1].id })
        shapeObject = try XCTUnwrap(shapeOwner.canvasObjects.first {
            if case .shape = $0.content { return true }; return false
        })
        shapeTarget = try XCTUnwrap(HWPShapeEditing.target(owner: shapeOwner, object: shapeObject))
        XCTAssertEqual(imageOwner.text, "안쪽 그림 셀")
        XCTAssertEqual(shapeOwner.text, "안쪽 도형 셀")
        XCTAssertNotNil(imageOwner.tableLocation?.parent)
        XCTAssertNotNil(shapeOwner.tableLocation?.parent)
        XCTAssertEqual(imageTarget.widthPoints, imageUpdate.dimensions.widthPoints, accuracy: 0.03)
        XCTAssertEqual(imageTarget.heightPoints, imageUpdate.dimensions.heightPoints, accuracy: 0.03)
        XCTAssertEqual(shapeTarget.rotationDegrees, shapeUpdate.rotationDegrees, accuracy: 0.03)
        let outerAfter = try XCTUnwrap(reopened.blocks.first {
            $0.tableLocation?.table == parent.table && $0.tableLocation?.row == parent.row
                && $0.tableLocation?.column == parent.column
        })
        XCTAssertGreaterThan(outerAfter.tableLocation?.cellHeightPoints ?? 0, outerHeight)
        XCTAssertGreaterThan(try XCTUnwrap(reopened.blocks.first { $0.text == "중첩 표 뒤 본문" })
            .lineLayouts.first?.verticalPositionPoints ?? 0, bodyY)
        let deleted = try await HWPImageEditing.applying(.delete, target: imageTarget,
            source: reopened, drafts: reopened.blocks)
        let deletedOwner = try XCTUnwrap(deleted.document.blocks.first { $0.id == nested[0].id })
        XCTAssertFalse(deletedOwner.canvasObjects.contains {
            if case .image = $0.content { return true }; return false
        })
        XCTAssertNotNil(deletedOwner.tableLocation?.parent)
    }

    func testHWPNestedTableCellsInsertAndEditImageAndShapeRoundTrip() async throws {
        let source = try HWPTableStructureDocument.load(fixture("hangul_design_application", "hwp"))
        let outer = try await tableDocument(source, texts: ["바깥 HWP 셀"])
        var document = try insertingNestedHWPTable(into: outer,
            owner: try XCTUnwrap(outer.blocks.first { $0.text == "바깥 HWP 셀" }))
        let nested = document.blocks.filter {
            $0.tableLocation?.parent != nil
                && ["HWP 안쪽 그림", "HWP 안쪽 도형"].contains($0.text)
        }
            .sorted { ($0.tableLocation?.column ?? 0) < ($1.tableLocation?.column ?? 0) }
        XCTAssertEqual(nested.map(\.text), ["HWP 안쪽 그림", "HWP 안쪽 도형"])

        let imageSelection = try XCTUnwrap(HWPImageEditing.selection(blocks: document.blocks,
            selectedID: nested[0].id, range: NSRange(location: 4, length: 0),
            layouts: document.layouts))
        let image = try HWPImageEditing.normalize(Self.png)
        document = try await HWPImageEditing.inserting(.init(selection: imageSelection,
            image: image, widthPoints: 96, heightPoints: 66),
            source: document, drafts: document.blocks).document

        let shapeCell = try XCTUnwrap(document.blocks.first { $0.id == nested[1].id })
        let shapeSelection = try XCTUnwrap(HWPShapeEditing.selection(blocks: document.blocks,
            selectedID: shapeCell.id, range: NSRange(location: 4, length: 0),
            layouts: document.layouts))
        document = try await HWPShapeEditing.inserting(.init(selection: shapeSelection,
            kind: .rectangle, widthPoints: 92, heightPoints: 62),
            source: document, drafts: document.blocks).document

        var imageOwner = try XCTUnwrap(document.blocks.first { $0.id == nested[0].id })
        var imageObject = try XCTUnwrap(imageOwner.canvasObjects.first {
            if case .image = $0.content { return true }; return false
        })
        let imageTarget = try XCTUnwrap(HWPImageEditing.target(owner: imageOwner, object: imageObject))
        let movedImage = try XCTUnwrap(HWPImageEditing.directUpdate(
            .move(deltaX: 6, deltaY: 9), target: imageTarget))
        document = try await HWPImageEditing.applying(
            .update(movedImage.crop, movedImage.dimensions, movedImage.presentation, movedImage.appearance),
            target: imageTarget, source: document, drafts: document.blocks).document

        var shapeOwner = try XCTUnwrap(document.blocks.first { $0.id == nested[1].id })
        var shapeObject = try XCTUnwrap(shapeOwner.canvasObjects.first {
            if case .shape = $0.content { return true }; return false
        })
        let shapeTarget = try XCTUnwrap(HWPShapeEditing.target(owner: shapeOwner, object: shapeObject))
        let movedShape = try XCTUnwrap(HWPShapeEditing.directLayout(
            .move(deltaX: 8, deltaY: 11), target: shapeTarget))
        document = try await HWPShapeEditing.applying(.update(movedShape), target: shapeTarget,
            source: document, drafts: document.blocks).document

        let reopened = try HWPTableStructureDocument.load(document.data)
        imageOwner = try XCTUnwrap(reopened.blocks.first { $0.id == nested[0].id })
        imageObject = try XCTUnwrap(imageOwner.canvasObjects.first {
            if case .image = $0.content { return true }; return false
        })
        shapeOwner = try XCTUnwrap(reopened.blocks.first { $0.id == nested[1].id })
        shapeObject = try XCTUnwrap(shapeOwner.canvasObjects.first {
            if case .shape = $0.content { return true }; return false
        })
        let savedImage = try XCTUnwrap(HWPImageEditing.target(owner: imageOwner, object: imageObject))
        let savedShape = try XCTUnwrap(HWPShapeEditing.target(owner: shapeOwner, object: shapeObject))
        XCTAssertEqual(savedImage.xPoints, movedImage.presentation.xPoints, accuracy: 0.03)
        XCTAssertEqual(savedImage.yPoints, movedImage.presentation.yPoints, accuracy: 0.03)
        XCTAssertEqual(savedShape.xPoints, movedShape.xPoints, accuracy: 0.03)
        XCTAssertEqual(savedShape.yPoints, movedShape.yPoints, accuracy: 0.03)
        XCTAssertNotNil(imageOwner.tableLocation?.parent)
        XCTAssertNotNil(shapeOwner.tableLocation?.parent)
    }

    func testHWPXTableCellsInsertImageAndShapeRoundTrip() async throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "삽입 기준"))
        var document = try await tableDocument(.hwpx(package), texts: ["그림 셀", "도형 셀"])
        let cells = document.blocks.filter { $0.tableLocation != nil }
        XCTAssertEqual(cells.count, 2)
        let originalHeight = cells[0].tableLocation?.cellHeightPoints ?? 0

        let imageSelection = try XCTUnwrap(HWPImageEditing.selection(blocks: document.blocks,
            selectedID: cells[0].id, range: NSRange(location: 2, length: 0),
            layouts: document.layouts))
        let image = try HWPImageEditing.normalize(Self.png)
        let imageResult = try await HWPImageEditing.inserting(.init(selection: imageSelection,
            image: image, widthPoints: 96, heightPoints: 58),
            source: document, drafts: document.blocks)
        document = imageResult.document

        let shapeCell = try XCTUnwrap(document.blocks.first { $0.id == cells[1].id })
        let shapeSelection = try XCTUnwrap(HWPShapeEditing.selection(blocks: document.blocks,
            selectedID: shapeCell.id, range: NSRange(location: shapeCell.text.utf16.count, length: 0),
            layouts: document.layouts))
        let shapeResult = try await HWPShapeEditing.inserting(.init(selection: shapeSelection,
            kind: .ellipse, widthPoints: 88, heightPoints: 64),
            source: document, drafts: document.blocks)
        let reopened = try HWPTableStructureDocument.load(shapeResult.document.data)
        let imageOwner = try XCTUnwrap(reopened.blocks.first { $0.id == cells[0].id })
        let shapeOwner = try XCTUnwrap(reopened.blocks.first { $0.id == cells[1].id })
        XCTAssertEqual(imageOwner.text, "그림 셀")
        XCTAssertEqual(shapeOwner.text, "도형 셀")
        XCTAssertTrue(imageOwner.canvasObjects.contains { if case .image = $0.content { return true }; return false })
        XCTAssertTrue(shapeOwner.canvasObjects.contains { if case .shape = $0.content { return true }; return false })
        XCTAssertGreaterThan(imageOwner.tableLocation?.cellHeightPoints ?? 0, originalHeight)
        XCTAssertNotNil(imageOwner.canvasObjects.first.flatMap {
            HWPImageEditing.target(owner: imageOwner, object: $0)
        })
        XCTAssertNotNil(shapeOwner.canvasObjects.first.flatMap {
            HWPShapeEditing.target(owner: shapeOwner, object: $0)
        })
    }

    func testHWPTableCellsInsertImageAndShapeRoundTrip() async throws {
        let source = try HWPTableStructureDocument.load(fixture("hangul_design_application", "hwp"))
        var document = try await tableDocument(source, texts: ["HWP 그림 셀", "HWP 도형 셀"])
        let cells = document.blocks.filter { ["HWP 그림 셀", "HWP 도형 셀"].contains($0.text) }
            .sorted { ($0.tableLocation?.column ?? 0) < ($1.tableLocation?.column ?? 0) }
        XCTAssertEqual(cells.count, 2)

        let imageSelection = try XCTUnwrap(HWPImageEditing.selection(blocks: document.blocks,
            selectedID: cells[0].id, range: NSRange(location: 4, length: 0),
            layouts: document.layouts))
        let image = try HWPImageEditing.normalize(Self.png)
        document = try await HWPImageEditing.inserting(.init(selection: imageSelection,
            image: image, widthPoints: 92, heightPoints: 56),
            source: document, drafts: document.blocks).document

        let shapeCell = try XCTUnwrap(document.blocks.first { $0.id == cells[1].id })
        let shapeSelection = try XCTUnwrap(HWPShapeEditing.selection(blocks: document.blocks,
            selectedID: shapeCell.id, range: NSRange(location: 4, length: 0),
            layouts: document.layouts))
        let result = try await HWPShapeEditing.inserting(.init(selection: shapeSelection,
            kind: .rectangle, widthPoints: 90, heightPoints: 62),
            source: document, drafts: document.blocks)
        let reopened = try HWPTableStructureDocument.load(result.document.data)
        let imageOwner = try XCTUnwrap(reopened.blocks.first { $0.id == cells[0].id })
        let shapeOwner = try XCTUnwrap(reopened.blocks.first { $0.id == cells[1].id })
        XCTAssertEqual(imageOwner.text, "HWP 그림 셀")
        XCTAssertEqual(shapeOwner.text, "HWP 도형 셀")
        XCTAssertTrue(imageOwner.canvasObjects.contains { if case .image = $0.content { return true }; return false })
        XCTAssertTrue(shapeOwner.canvasObjects.contains { if case .shape = $0.content { return true }; return false })
        XCTAssertNotNil(imageOwner.canvasObjects.first.flatMap {
            HWPImageEditing.target(owner: imageOwner, object: $0)
        })
        XCTAssertNotNil(shapeOwner.canvasObjects.first.flatMap {
            HWPShapeEditing.target(owner: shapeOwner, object: $0)
        })
    }

    func testHWPXTableCellImageSelectResizeAndDeleteRoundTrip() async throws {
        let source = try await tableCellImageDocument()
        let pair: (HWPDocumentBlock, HWPDocumentCanvasObject) = try XCTUnwrap(
            imagePair(in: source))
        let target = try XCTUnwrap(HWPImageEditing.target(owner: pair.0, object: pair.1))
        let oldCellHeight = pair.0.tableLocation?.cellHeightPoints ?? 0
        let update = try XCTUnwrap(HWPImageEditing.directUpdate(
            .resize(anchor: .bottomTrailing, deltaX: 36, deltaY: 58),
            target: target))

        let changed = try await HWPImageEditing.applying(
            .update(update.crop, update.dimensions, update.presentation, update.appearance),
            target: target, source: source, drafts: source.blocks)
        let reopened = try HWPTableStructureDocument.load(changed.document.data)
        let owner = try XCTUnwrap(reopened.blocks.first { $0.id == pair.0.id })
        let object = try XCTUnwrap(owner.canvasObjects.first { $0.id == pair.1.id })
        let saved = try XCTUnwrap(HWPImageEditing.target(owner: owner, object: object))
        XCTAssertEqual(saved.widthPoints, update.dimensions.widthPoints, accuracy: 0.03)
        XCTAssertEqual(saved.heightPoints, update.dimensions.heightPoints, accuracy: 0.03)
        XCTAssertGreaterThan(owner.tableLocation?.cellHeightPoints ?? 0, oldCellHeight)

        let deleted = try await HWPImageEditing.applying(.delete, target: saved,
            source: reopened, drafts: reopened.blocks)
        let deletedOwner = try XCTUnwrap(deleted.document.blocks.first { $0.id == owner.id })
        XCTAssertFalse(deletedOwner.canvasObjects.contains { if case .image = $0.content { return true }; return false })
    }

    func testHWPXTableCellShapeSelectMoveRotateResizeRoundTrip() async throws {
        let source = try tableCellShapeDocument()
        let pair: (HWPDocumentBlock, HWPDocumentCanvasObject) = try XCTUnwrap(
            shapePair(in: source))
        let initial = try XCTUnwrap(HWPShapeEditing.target(owner: pair.0, object: pair.1))
        let moved = try XCTUnwrap(HWPShapeEditing.directLayout(
            .move(deltaX: 11, deltaY: 17), target: initial))
        let movedResult = try await HWPShapeEditing.applying(.update(moved), target: initial,
            source: source, drafts: source.blocks)
        let movedOwner = try XCTUnwrap(movedResult.document.blocks.first { $0.id == pair.0.id })
        let movedObject = try XCTUnwrap(movedOwner.canvasObjects.first { $0.id == pair.1.id })
        let movedTarget = try XCTUnwrap(HWPShapeEditing.target(owner: movedOwner, object: movedObject))
        let rotated = try XCTUnwrap(HWPShapeEditing.directLayout(
            .rotate(deltaDegrees: 32), target: movedTarget))
        let rotatedResult = try await HWPShapeEditing.applying(.update(rotated), target: movedTarget,
            source: movedResult.document, drafts: movedResult.document.blocks)
        let rotatedOwner = try XCTUnwrap(rotatedResult.document.blocks.first { $0.id == pair.0.id })
        let rotatedObject = try XCTUnwrap(rotatedOwner.canvasObjects.first { $0.id == pair.1.id })
        let rotatedTarget = try XCTUnwrap(HWPShapeEditing.target(owner: rotatedOwner, object: rotatedObject))
        let resized = try XCTUnwrap(HWPShapeEditing.directLayout(
            .resize(anchor: .bottomTrailing, deltaX: 44, deltaY: 61),
            target: rotatedTarget))
        let resizedResult = try await HWPShapeEditing.applying(.update(resized), target: rotatedTarget,
            source: rotatedResult.document, drafts: rotatedResult.document.blocks)

        let reopened = try HWPTableStructureDocument.load(resizedResult.document.data)
        let owner = try XCTUnwrap(reopened.blocks.first { $0.id == pair.0.id })
        let object = try XCTUnwrap(owner.canvasObjects.first { $0.id == pair.1.id })
        let saved = try XCTUnwrap(HWPShapeEditing.target(owner: owner, object: object))
        XCTAssertEqual(saved.xPoints, resized.xPoints, accuracy: 0.03)
        XCTAssertEqual(saved.yPoints, resized.yPoints, accuracy: 0.03)
        XCTAssertEqual(saved.widthPoints, resized.widthPoints, accuracy: 0.03)
        XCTAssertEqual(saved.heightPoints, resized.heightPoints, accuracy: 0.03)
        XCTAssertEqual(saved.rotationDegrees, rotated.rotationDegrees, accuracy: 0.03)
        XCTAssertGreaterThan(owner.tableLocation?.cellHeightPoints ?? 0, 40)
    }

    func testHWPTableCellShapeCanBeSelectedAndMovedRoundTrip() async throws {
        let source = try HWPTableStructureDocument.load(fixture("table_cell_shape_editing", "hwp"))
        let pair = try XCTUnwrap(shapePair(in: source))
        let target = try XCTUnwrap(HWPShapeEditing.target(owner: pair.0, object: pair.1))
        let layout = try XCTUnwrap(HWPShapeEditing.directLayout(
            .move(deltaX: 7, deltaY: 9), target: target))
        let changed = try await HWPShapeEditing.applying(.update(layout), target: target,
            source: source, drafts: source.blocks)
        let reopened = try HWPTableStructureDocument.load(changed.document.data)
        let owner = try XCTUnwrap(reopened.blocks.first { $0.id == pair.0.id })
        let object = try XCTUnwrap(owner.canvasObjects.first { $0.id == pair.1.id })
        let saved = try XCTUnwrap(HWPShapeEditing.target(owner: owner, object: object))
        XCTAssertEqual(saved.xPoints, layout.xPoints, accuracy: 0.03)
        XCTAssertEqual(saved.yPoints, layout.yPoints, accuracy: 0.03)
    }

    private func tableCellImageDocument() async throws -> HWPTableStructureDocument {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: ""))
        let source = HWPTableStructureDocument.hwpx(package)
        let image = try HWPImageEditing.normalize(Self.png)
        let selection = HWPImageEditing.Selection(blockID: package.blocks[0].id,
            text: "", caret: 0, width: 240)
        let data = try HWPImageEditingWriter.insert(.init(selection: selection, image: image,
            widthPoints: 96, heightPoints: 48), into: source, ownerIndex: 0)
        return try wrapFirstObjectInTable(data, elementName: "pic")
    }

    private func exerciseNestedTableStructure(_ source: HWPTableStructureDocument) async throws {
        let initial = try XCTUnwrap(source.blocks.first { $0.tableLocation?.parent != nil })
        let table = try XCTUnwrap(initial.tableLocation?.table)
        let outsideTexts = source.blocks.filter { $0.tableLocation?.table != table }.map(\.text)
        var document = source

        func cell(_ row: Int, _ column: Int) throws -> HWPDocumentBlock {
            try XCTUnwrap(document.blocks.first {
                $0.tableLocation?.table == table && $0.tableLocation?.row == row
                    && $0.tableLocation?.column == column
            })
        }
        for (action, row, column) in [
            (HWPTableStructureAction.rowBelow, 0, 0),
            (.columnAfter, 0, 0),
            (.deleteColumn, 0, 1),
            (.deleteRow, 1, 0)
        ] {
            let selected = try cell(row, column)
            XCTAssertTrue(HWPTableStructureEditing.available(blocks: document.blocks,
                selectedID: selected.id, layouts: document.layouts).contains(action), action.rawValue)
            document = try await document.editing(action, blocks: document.blocks,
                selectedID: selected.id).document
        }

        var selected = try cell(0, 0)
        XCTAssertTrue(HWPTableStructureEditing.availableCells(blocks: document.blocks,
            selectedID: selected.id, layouts: document.layouts).contains(.mergeRight))
        document = try await document.editing(.mergeRight, blocks: document.blocks,
            selectedID: selected.id).document
        selected = try cell(0, 0)
        XCTAssertEqual(selected.tableLocation?.columnSpan, 2)
        XCTAssertTrue(HWPTableStructureEditing.availableCells(blocks: document.blocks,
            selectedID: selected.id, layouts: document.layouts).contains(.splitColumns))
        document = try await document.editing(.splitColumns, blocks: document.blocks,
            selectedID: selected.id).document

        selected = try cell(0, 0)
        let sizing = try XCTUnwrap(HWPTableSizing.selection(blocks: document.blocks,
            selectedID: selected.id, layouts: document.layouts))
        let width = min(sizing.maximumWidth, sizing.width + 8)
        document = try await document.editing(.resize, blocks: document.blocks,
            selectedID: selected.id,
            dimensions: .init(widthPoints: width, heightPoints: sizing.height + 8)).document

        let reopened = try HWPTableStructureDocument.load(document.data)
        let nested = reopened.blocks.filter { $0.tableLocation?.table == table }
        XCTAssertEqual(Set(nested.compactMap { $0.tableLocation?.row }).count, 1)
        XCTAssertEqual(Set(nested.compactMap { $0.tableLocation?.column }).count, 2)
        XCTAssertTrue(nested.allSatisfy { $0.tableLocation?.parent != nil })
        XCTAssertEqual(reopened.blocks.filter { $0.tableLocation?.table != table }.map(\.text), outsideTexts)
        let resized = try XCTUnwrap(nested.first { $0.tableLocation?.row == 0 && $0.tableLocation?.column == 0 })
        XCTAssertEqual(resized.tableLocation?.cellWidthPoints ?? 0, width, accuracy: 0.03)
        XCTAssertEqual(resized.tableLocation?.cellHeightPoints ?? 0, sizing.height + 8, accuracy: 0.03)
    }

    private func exerciseNestedCellFormattingAndLists(_ source: HWPTableStructureDocument) throws {
        let nested = source.blocks.indices.filter {
            source.blocks[$0].tableLocation?.parent != nil
                && !source.blocks[$0].text.isEmpty
        }.sorted {
            (source.blocks[$0].tableLocation?.column ?? 0)
                < (source.blocks[$1].tableLocation?.column ?? 0)
        }
        XCTAssertGreaterThanOrEqual(nested.count, 2)
        let formattedIndex = nested[0], listIndex = nested[1]
        XCTAssertTrue(HWPCellFormatting.supports(source.blocks[formattedIndex]))
        XCTAssertTrue(HWPListFormatting.supports(source.blocks[listIndex]))

        var blocks = source.blocks
        var cell = HWPCellFormat(blocks[formattedIndex].tableLocation!)
        cell.setFill(0xDDEBF7)
        cell.vertical = .end
        for side in 0..<4 {
            cell.setBorder(side, line: .init(kind: 1,
                widthPoints: 0.3 * 72 / 25.4, colorRGB: 0x0066CC))
        }
        let previous = blocks[formattedIndex]
        blocks[formattedIndex] = HWPCellFormatting.apply(cell, to: previous)
        blocks = HWPCellFormatting.propagating(blocks[formattedIndex], from: previous, in: blocks)
        let list = HWPListFormatting.style(.number, for: blocks[listIndex], in: blocks)
        blocks[listIndex] = HWPDocumentFormatting.apply(.list(list),
            to: blocks[listIndex], range: NSRange(location: 0, length: 0))
        blocks = HWPListFormatting.renumbering(blocks)

        let reopened = try HWPTableStructureDocument.load(source.serialized(blocks))
        let formatted = try XCTUnwrap(reopened.blocks.first { $0.id == blocks[formattedIndex].id })
        let listed = try XCTUnwrap(reopened.blocks.first { $0.id == blocks[listIndex].id })
        XCTAssertNotNil(formatted.tableLocation?.parent)
        XCTAssertNotNil(listed.tableLocation?.parent)
        XCTAssertTrue(HWPCellFormatting.matches(formatted, blocks[formattedIndex]))
        XCTAssertEqual(formatted.tableLocation?.boxStyle?.backgroundColorRGB, 0xDDEBF7)
        XCTAssertEqual(formatted.tableLocation?.cellVerticalAlignment, .end)
        XCTAssertEqual(formatted.tableLocation?.boxStyle?.firstVisibleBorder?.colorRGB, 0x0066CC)
        XCTAssertEqual(listed.presentation.list?.kind, .number)
        XCTAssertEqual(listed.presentation.list?.ordinal, 1)
        XCTAssertEqual(listed.presentation.list?.marker(in: listed)?.run.text, "1.")
        XCTAssertEqual(reopened.blocks.map(\.text), blocks.map(\.text))
    }

    private func nestedTableDocument() throws -> HWPTableStructureDocument {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: ""))
        let section = try XCTUnwrap(package.sections.first)
        let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: section.xml)
        let range = try XCTUnwrap(ranges.first)
        let paragraph = (section.xml as NSString).substring(with: range)
        let prefix = try HWPFormattingXML.prefix(paragraph)
        let paraID = HWPFormattingXML.escaped(
            try HWPFormattingXML.attribute(paragraph, "paraPrIDRef") ?? "0")
        let run = try XCTUnwrap(HWPFormattingXML.elements(paragraph, name: "run").first)
        let charID = HWPFormattingXML.escaped(
            try HWPFormattingXML.attribute(run.xml, "charPrIDRef") ?? "0")
        func p(_ id: Int, _ text: String, object: String = "") -> String {
            "<\(prefix)p id=\"\(id)\" paraPrIDRef=\"\(paraID)\" styleIDRef=\"0\"><\(prefix)run charPrIDRef=\"\(charID)\">\(object)<\(prefix)t>\(text)</\(prefix)t></\(prefix)run><\(prefix)linesegarray><\(prefix)lineseg textpos=\"0\" vertpos=\"0\" vertsize=\"1000\" textheight=\"1000\" baseline=\"850\" spacing=\"600\" horzsize=\"10000\"/></\(prefix)linesegarray></\(prefix)p>"
        }
        func cell(_ row: Int, _ column: Int, _ contents: String,
                  width: Int, height: Int) -> String {
            "<\(prefix)tc><\(prefix)subList vertAlign=\"TOP\">\(contents)</\(prefix)subList><\(prefix)cellAddr rowAddr=\"\(row)\" colAddr=\"\(column)\"/><\(prefix)cellSpan rowSpan=\"1\" colSpan=\"1\"/><\(prefix)cellSz width=\"\(width)\" height=\"\(height)\"/><\(prefix)cellMargin left=\"200\" right=\"200\" top=\"200\" bottom=\"200\"/></\(prefix)tc>"
        }
        let innerCells = cell(0, 0, p(9302, "안쪽 그림 셀"), width: 11000, height: 3200)
            + cell(0, 1, p(9303, "안쪽 도형 셀"), width: 11000, height: 3200)
        let inner = "<\(prefix)tbl id=\"9300\" rowCnt=\"1\" colCnt=\"2\" pageBreak=\"CELL\"><\(prefix)sz width=\"22000\" height=\"3200\"/><\(prefix)pos treatAsChar=\"1\" vertOffset=\"0\" horzOffset=\"0\"/><\(prefix)tr>\(innerCells)</\(prefix)tr></\(prefix)tbl>"
        let outerParagraph = p(9201, "바깥 셀", object: inner)
        let outerCell = cell(0, 0, outerParagraph, width: 24000, height: 4200)
        let outer = "<\(prefix)p id=\"9200\" paraPrIDRef=\"\(paraID)\" styleIDRef=\"0\"><\(prefix)run charPrIDRef=\"\(charID)\"><\(prefix)tbl id=\"9202\" rowCnt=\"1\" colCnt=\"1\" pageBreak=\"CELL\"><\(prefix)sz width=\"24000\" height=\"4200\"/><\(prefix)pos treatAsChar=\"1\" vertOffset=\"0\" horzOffset=\"0\"/><\(prefix)tr>\(outerCell)</\(prefix)tr></\(prefix)tbl></\(prefix)run><\(prefix)linesegarray><\(prefix)lineseg textpos=\"0\" vertpos=\"3000\" vertsize=\"4200\" textheight=\"1000\" baseline=\"850\" horzsize=\"24000\"/></\(prefix)linesegarray></\(prefix)p>"
        let following = p(9400, "중첩 표 뒤 본문")
        let xml = (section.xml as NSString).replacingCharacters(in: range,
            with: paragraph + outer + following)
        let archive = try HWPXEditingArchive(data: package.sourceData)
        return try HWPTableStructureDocument.load(
            archive.repack(replacing: [section.path: Data(xml.utf8)]))
    }

    private func insertingNestedHWPTable(into source: HWPTableStructureDocument,
                                         owner: HWPDocumentBlock) throws
        -> HWPTableStructureDocument {
        let data = source.data
        let container = try OLECompoundFile(data: data)
        let flags = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36)
        let compressed = flags & 1 != 0
        let paths = container.streamNames.filter { $0.hasPrefix("bodytext/section") }
            .sorted { (HWPPageSetup.sectionIndex($0) ?? 0) < (HWPPageSetup.sectionIndex($1) ?? 0) }
        var replacements: [String: Data] = [:]
        var ordinal = 0
        for path in paths {
            let stored = try container.stream(named: path)
            let expanded = try compressed
                ? HWP5TextExtractor.inflateRawDeflate(stored,
                    maximumBytes: HWP5TextExtractor.maximumSectionBytes) : stored
            var records = try HWP5DocumentRewriter.parseRecords(expanded)
            var start: Int?
            for index in records.indices where records[index].tag == 0x42 {
                if ordinal == owner.paragraphIndex && path == owner.sectionPath.lowercased() {
                    start = index
                }
                ordinal += 1
            }
            guard let start else { continue }
            let ownerLevel = records[start].level
            var end = records.indices.dropFirst(start + 1).first {
                records[$0].level <= ownerLevel
            } ?? records.endIndex
            guard records[start].payload.count >= 22 else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            end = try HWPObjectInsertionSupport.insertAnchor(0x7462_6C20,
                caret: owner.text.utf16.count, records: &records, header: start, end: end)
            let owned = start..<end
            guard let shape = owned.first(where: {
                records[$0].tag == 0x44 && records[$0].payload.count >= 8
            }) else { throw HWPDocumentEditingError.unsupportedEdit }
            let templateHeader = records[start].payload
            let templateShape = Data(records[shape].payload.prefix(8))
            var nextInstance: UInt32 = 1
            for record in records {
                if record.tag == 0x42, record.payload.count >= 22 {
                    nextInstance = max(nextInstance,
                        (try record.payload.hwpWriterUInt32(at: 18)) &+ 1)
                } else if record.tag == 0x47, record.payload.count >= 40 {
                    nextInstance = max(nextInstance,
                        (try record.payload.hwpWriterUInt32(at: 36)) &+ 1)
                }
            }
            let childLevel = ownerLevel + 1
            let width: UInt32 = 22_000, height: UInt32 = 3_200
            var control = Data(repeating: 0, count: 46)
            control.hwpWriterSetUInt32(0x7462_6C20, at: 0)
            control.hwpWriterSetUInt32(1 | (2 << 3) | (2 << 8) | (4 << 15)
                | (2 << 18) | (2 << 26), at: 4)
            control.hwpWriterSetUInt32(width, at: 16)
            control.hwpWriterSetUInt32(height, at: 20)
            control.hwpWriterSetUInt32(nextInstance, at: 36)
            nextInstance += 1
            var property = Data(repeating: 0, count: 18)
            property.hwpWriterSetUInt32(1, at: 0)
            property.hwpWriterSetUInt16(1, at: 4)
            property.hwpWriterSetUInt16(2, at: 6)
            for offset in [10, 12, 14, 16] { property.hwpWriterSetUInt16(200, at: offset) }
            property.hwpWriterAppendUInt16(2)
            property.hwpWriterAppendUInt16(1)
            property.hwpWriterAppendUInt16(0)
            var inserted = [
                HWP5DocumentRewriter.Record(tag: 0x47, level: childLevel, payload: control),
                HWP5DocumentRewriter.Record(tag: 0x4D, level: childLevel + 1, payload: property)
            ]
            let texts = ["HWP 안쪽 그림", "HWP 안쪽 도형"]
            for (column, text) in texts.enumerated() {
                var cell = Data()
                cell.hwpWriterAppendUInt16(1)
                cell.hwpWriterAppendUInt32(1 << 16)
                for value in [column, 0, 1, 1] { cell.hwpWriterAppendUInt16(UInt16(value)) }
                cell.hwpWriterAppendUInt32(width / 2)
                cell.hwpWriterAppendUInt32(height)
                for _ in 0..<4 { cell.hwpWriterAppendUInt16(200) }
                cell.hwpWriterAppendUInt16(1)
                var header = templateHeader
                header.hwpWriterSetUInt32(0x8000_0000 | UInt32(text.utf16.count + 1), at: 0)
                header.hwpWriterSetUInt32(0, at: 4)
                header[11] = 0
                header.hwpWriterSetUInt16(1, at: 12)
                header.hwpWriterSetUInt16(0, at: 14)
                header.hwpWriterSetUInt16(0, at: 16)
                header.hwpWriterSetUInt32(nextInstance, at: 18)
                nextInstance += 1
                var textData = Data()
                for unit in text.utf16 { textData.hwpWriterAppendUInt16(unit) }
                textData.hwpWriterAppendUInt16(13)
                inserted += [
                    .init(tag: 0x48, level: childLevel + 1, payload: cell),
                    .init(tag: 0x42, level: childLevel + 2, payload: header),
                    .init(tag: 0x43, level: childLevel + 3, payload: textData),
                    .init(tag: 0x44, level: childLevel + 3, payload: templateShape)
                ]
            }
            records.insert(contentsOf: inserted, at: end)
            let payload = records.reduce(into: Data()) { $0.append($1.serialized()) }
            replacements[path] = try compressed
                ? HWP5DocumentRewriter.rawDeflate(payload) : payload
        }
        guard !replacements.isEmpty else { throw HWPDocumentEditingError.staleDocument }
        return try HWPTableStructureDocument.load(
            container.serialized(replacing: replacements))
    }

    private func tableDocument(_ source: HWPTableStructureDocument, texts: [String]) async throws
        -> HWPTableStructureDocument {
        let owner = try XCTUnwrap(source.blocks.first {
            HWPParagraphEditing.supports($0) && $0.presentation.list == nil
        })
        let selection = try XCTUnwrap(HWPTableInsertion.selection(blocks: source.blocks,
            selectedID: owner.id,
            range: NSRange(location: owner.text.utf16.count, length: 0),
            layouts: source.layouts))
        let inserted = try await HWPTableInsertion.applying(.init(selection: selection,
            rows: 1, columns: texts.count), source: source, drafts: source.blocks)
        var drafts = inserted.document.blocks
        let newTable = try XCTUnwrap(drafts.first { $0.id == inserted.focusedID }?.tableLocation?.table)
        let cells = drafts.indices.filter { drafts[$0].tableLocation?.table == newTable }
            .sorted { (drafts[$0].tableLocation?.column ?? 0) < (drafts[$1].tableLocation?.column ?? 0) }
        XCTAssertEqual(cells.count, texts.count)
        for (index, text) in zip(cells, texts) {
            drafts[index] = HWPTextRunEditing.replacingText(in: drafts[index], with: text)
        }
        return try HWPTableStructureDocument.load(inserted.document.serialized(drafts))
    }

    private func imagePair(in document: HWPTableStructureDocument)
        -> (HWPDocumentBlock, HWPDocumentCanvasObject)? {
        for owner in document.blocks where owner.tableLocation != nil {
            for object in owner.canvasObjects {
                if case .image = object.content { return (owner, object) }
            }
        }
        return nil
    }

    private func shapePair(in document: HWPTableStructureDocument)
        -> (HWPDocumentBlock, HWPDocumentCanvasObject)? {
        for owner in document.blocks where owner.tableLocation != nil {
            for object in owner.canvasObjects {
                if case .shape = object.content { return (owner, object) }
            }
        }
        return nil
    }

    private func tableCellShapeDocument() throws -> HWPTableStructureDocument {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: ""))
        let source = HWPTableStructureDocument.hwpx(package)
        let selection = HWPShapeEditing.Selection(blockID: package.blocks[0].id,
            text: "", caret: 0, width: 240)
        let data = try HWPShapeEditingWriter.insert(.init(selection: selection,
            kind: .rectangle, widthPoints: 90, heightPoints: 54), into: source, ownerIndex: 0)
        return try wrapFirstObjectInTable(data, elementName: "rect")
    }

    private func wrapFirstObjectInTable(_ data: Data, elementName: String) throws
        -> HWPTableStructureDocument {
        let package = try HWPXDocumentPackage.load(from: data)
        let section = try XCTUnwrap(package.sections.first)
        let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: section.xml)
        let range = try XCTUnwrap(ranges.first)
        let paragraph = (section.xml as NSString).substring(with: range)
        let object = try XCTUnwrap(HWPFormattingXML.elements(paragraph, name: elementName).first)
        let rootParagraph = (paragraph as NSString).replacingCharacters(in: object.range, with: "")
        let cellParagraph = "<hp:p id=\"8101\" paraPrIDRef=\"0\" styleIDRef=\"0\"><hp:run charPrIDRef=\"0\">\(object.xml)<hp:t>셀 개체</hp:t></hp:run><hp:linesegarray><hp:lineseg textpos=\"0\" vertpos=\"0\" vertsize=\"1000\" textheight=\"1000\" baseline=\"850\" spacing=\"600\" horzsize=\"22000\"/></hp:linesegarray></hp:p>"
        let table = "<hp:p id=\"8100\" paraPrIDRef=\"0\" styleIDRef=\"0\"><hp:run charPrIDRef=\"0\"><hp:tbl id=\"8200\" rowCnt=\"1\" colCnt=\"1\" pageBreak=\"CELL\"><hp:sz width=\"24000\" height=\"4000\"/><hp:pos treatAsChar=\"1\"/><hp:tr><hp:tc><hp:subList vertAlign=\"TOP\">\(cellParagraph)</hp:subList><hp:cellAddr rowAddr=\"0\" colAddr=\"0\"/><hp:cellSpan rowSpan=\"1\" colSpan=\"1\"/><hp:cellSz width=\"24000\" height=\"4000\"/><hp:cellMargin left=\"200\" right=\"200\" top=\"200\" bottom=\"200\"/></hp:tc></hp:tr></hp:tbl></hp:run><hp:linesegarray><hp:lineseg textpos=\"0\" vertpos=\"3000\" vertsize=\"4000\" textheight=\"1000\" baseline=\"850\" horzsize=\"24000\"/></hp:linesegarray></hp:p>"
        let following = "<hp:p id=\"8300\" paraPrIDRef=\"0\" styleIDRef=\"0\"><hp:run charPrIDRef=\"0\"><hp:t>표 뒤 본문</hp:t></hp:run><hp:linesegarray><hp:lineseg textpos=\"0\" vertpos=\"9000\" vertsize=\"1000\" textheight=\"1000\" baseline=\"850\" spacing=\"600\" horzsize=\"24000\"/></hp:linesegarray></hp:p>"
        let replacement = rootParagraph + table + following
        let xml = (section.xml as NSString).replacingCharacters(in: range, with: replacement)
        let archive = try HWPXEditingArchive(data: data)
        return try HWPTableStructureDocument.load(
            archive.repack(replacing: [section.path: Data(xml.utf8)]))
    }

    private static var png: Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 1))
        return renderer.pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
        }
    }

    private func fixture(_ name: String, _ ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext,
                subdirectory: "HWPXViewerFixtures")))
    }
}
