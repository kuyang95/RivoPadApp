import RivoDocumentEngine
import XCTest
@testable import shortcuts_example

@MainActor
final class HWPShapeEditingTests: XCTestCase {
    func testEditingIndependentRectangleAfterGroupDoesNotChangeGroupChild() async throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: ""))
        let initial = HWPTableStructureDocument.hwpx(package)
        let selection = HWPShapeEditing.Selection(blockID: package.blocks[0].id,
            text: "", caret: 0, width: 400)
        let firstData = try HWPShapeEditingWriter.insert(.init(selection: selection,
            kind: .rectangle, widthPoints: 100, heightPoints: 60), into: initial, ownerIndex: 0)
        let firstPackage = try HWPXDocumentPackage.load(from: firstData)
        let section = try XCTUnwrap(firstPackage.sections.first)
        let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: section.xml)
        let paragraph = (section.xml as NSString).substring(with: ranges[0])
        let run = try XCTUnwrap(HWPFormattingXML.elements(paragraph, name: "run").first)
        let rectangle = try XCTUnwrap(HWPFormattingXML.elements(paragraph, name: "rect").first)
        var clones = ""
        for (id, x) in [(902, 12_000), (903, 24_000)] {
            var clone = try HWPFormattingXML.setAttribute(rectangle.xml, "id", String(id))
            var position = try XCTUnwrap(HWPFormattingXML.elements(clone, name: "pos").first?.xml)
            position = try HWPFormattingXML.setAttribute(position, "horzOffset", String(x))
            clone = try HWPFormattingXML.replaceOrAppend(clone, name: "pos", replacement: position)
            clones += clone
        }
        let changedRun = try HWPFormattingXML.append(clones, to: run.xml)
        let changedParagraph = (paragraph as NSString).replacingCharacters(in: run.range, with: changedRun)
        let changedSection = (section.xml as NSString).replacingCharacters(in: ranges[0], with: changedParagraph)
        let sourceData = try HWPXEditingArchive(data: firstPackage.sourceData).repack(
            replacing: [section.path: Data(changedSection.utf8)])
        let source = try HWPTableStructureDocument.load(sourceData)
        let owner = source.blocks[0]
        XCTAssertEqual(owner.canvasObjects.count, 3)
        let grouped = try await HWPShapeEditing.grouping(.init(ownerID: owner.id,
            objectIDs: Array(owner.canvasObjects.prefix(2).map(\.id))),
            source: source, drafts: source.blocks)
        let groupOwner = grouped.document.blocks[0]
        let independent = try XCTUnwrap(groupOwner.canvasObjects.first {
            if case .shape = $0.content { return true }; return false
        })
        let target = try XCTUnwrap(HWPShapeEditing.target(owner: groupOwner, object: independent))
        let layout = HWPShapeEditing.Layout(xPoints: target.xPoints, yPoints: target.yPoints,
            widthPoints: target.widthPoints, heightPoints: target.heightPoints,
            zOrder: target.zOrder, rotationDegrees: target.rotationDegrees,
            strokeColorRGB: target.strokeColorRGB, strokeWidthPoints: target.strokeWidthPoints,
            strokeStyle: target.strokeStyle, fillColorRGB: target.fillColorRGB,
            shadow: target.shadow, isInline: false, wrap: .inFrontOfText)
        let floating = try await HWPShapeEditing.applying(.update(layout), target: target,
            source: grouped.document, drafts: grouped.document.blocks)
        let floatingOwner = floating.document.blocks[0]
        let floatingObject = try XCTUnwrap(floatingOwner.canvasObjects.first { $0.id == independent.id })
        let floatingTarget = try XCTUnwrap(HWPShapeEditing.target(owner: floatingOwner, object: floatingObject))
        let inlineLayout = HWPShapeEditing.Layout(xPoints: floatingTarget.xPoints,
            yPoints: floatingTarget.yPoints, widthPoints: floatingTarget.widthPoints,
            heightPoints: floatingTarget.heightPoints, zOrder: floatingTarget.zOrder,
            rotationDegrees: floatingTarget.rotationDegrees,
            strokeColorRGB: floatingTarget.strokeColorRGB,
            strokeWidthPoints: floatingTarget.strokeWidthPoints, strokeStyle: floatingTarget.strokeStyle,
            fillColorRGB: floatingTarget.fillColorRGB, shadow: floatingTarget.shadow,
            isInline: true, wrap: .topAndBottom)
        let edited = try await HWPShapeEditing.applying(.update(inlineLayout), target: floatingTarget,
            source: floating.document, drafts: floating.document.blocks)
        let reopened = try HWPTableStructureDocument.load(edited.document.data)
        let reopenedOwner = reopened.blocks[0]
        let reopenedIndependent = try XCTUnwrap(reopenedOwner.canvasObjects.first { $0.id == independent.id })
        XCTAssertTrue(reopenedIndependent.placement.isInline)
        let group = try XCTUnwrap(reopenedOwner.canvasObjects.first {
            if case .group = $0.content { return true }; return false
        })
        guard case .group(let children) = group.content else { return XCTFail("Missing group") }
        XCTAssertEqual(children.count, 2)
        XCTAssertTrue(children.allSatisfy { $0.localFrame != nil })
    }

    func testWrappedObjectHeightIsReservedOnlyAtParagraphAnchor() throws {
        let text = "M5 그룹 배치 검사  " + String(repeating: "본문과 도형의 배치를 확인합니다. ", count: 38)
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: text))
        let block = try XCTUnwrap(package.blocks.first)

        let lines = HWPFlowLayout.measure(block, width: 425.2, startY: 0,
            pageHeight: 648, minimumHeight: 202)

        XCTAssertGreaterThan(lines.count, 5)
        XCTAssertGreaterThanOrEqual(lines[0].lineHeightPoints, 202)
        XCTAssertTrue(lines.dropFirst().allSatisfy { $0.lineHeightPoints < 30 })
        XCTAssertFalse(lines.contains { $0.startsPage })
    }

    func testSquareWrappedObjectKeepsTextInFreeStrip() {
        let object = HWPDocumentCanvasObject(id: "square",
            placement: HWPDocumentObjectPlacement(xPoints: 110, yPoints: 0,
                widthPoints: 180, heightPoints: 90, wrap: .square),
            content: .unsupported("test"))
        let block = HWPDocumentBlock(id: "body", sectionPath: "section0", paragraphIndex: 0,
            text: String(repeating: "본문과 도형의 배치를 확인합니다. ", count: 32),
            tableLocation: nil, isEditable: true, canvasObjects: [object])

        let lines = HWPFlowLayout.measure(block, width: 320, startY: 0,
            pageHeight: nil, minimumHeight: 0)

        XCTAssertGreaterThan(lines.count, 8)
        XCTAssertTrue(lines.filter { $0.verticalPositionPoints < 90 }.allSatisfy {
            $0.columnStartPoints + $0.widthPoints <= 110.01
        })
        XCTAssertTrue(lines.contains { $0.verticalPositionPoints >= 90 && $0.widthPoints > 300 })
        XCTAssertTrue(lines.allSatisfy { $0.lineHeightPoints < 30 })
    }

    func testHWPXShapeInsertMoveResizeLayerAndDeleteRoundTrip() async throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "앞뒤"))
        let source = HWPTableStructureDocument.hwpx(package)
        let selection = try XCTUnwrap(HWPShapeEditing.selection(blocks: package.blocks,
            selectedID: package.blocks[0].id, range: NSRange(location: 1, length: 0), layouts: package.pageLayouts))
        let inserted = try await HWPShapeEditing.inserting(.init(selection: selection, kind: .rectangle,
            widthPoints: 120, heightPoints: 72), source: source, drafts: package.blocks)

        XCTAssertEqual(inserted.document.blocks.map(\.text), ["앞", "", "뒤"])
        let owner = inserted.document.blocks[1]
        let object = try XCTUnwrap(owner.canvasObjects.first)
        guard case .shape(let shape) = object.content,
              case .rectangle = shape.geometry else { return XCTFail("Inserted object is not a rectangle") }

        let target = try XCTUnwrap(HWPShapeEditing.target(owner: owner, object: object))
        let changed = try await HWPShapeEditing.applying(.update(.init(xPoints: 18, yPoints: 12,
            widthPoints: 156, heightPoints: 84, zOrder: 3, rotationDegrees: 27,
            strokeColorRGB: 0xD02030, strokeWidthPoints: 2.25, strokeStyle: 2,
            fillColorRGB: 0xFFE090,
            shadow: .init(colorRGB: 0x223344, offsetX: 4, offsetY: 5, opacity: 0.65),
            isInline: false, horizontalReference: .page, verticalReference: .page,
            horizontalAlignment: .center, verticalAlignment: .end, wrap: .inFrontOfText,
            marginLeftPoints: 3, marginRightPoints: 4, marginTopPoints: 5, marginBottomPoints: 6)), target: target,
            source: inserted.document, drafts: inserted.document.blocks)
        let changedOwner = changed.document.blocks[1]
        let changedObject = try XCTUnwrap(changedOwner.canvasObjects.first)
        XCTAssertEqual(changedObject.placement.xPoints, 18, accuracy: 0.02)
        XCTAssertEqual(changedObject.placement.yPoints, 12, accuracy: 0.02)
        XCTAssertEqual(changedObject.placement.widthPoints, 156, accuracy: 0.02)
        XCTAssertEqual(changedObject.placement.heightPoints, 84, accuracy: 0.02)
        XCTAssertEqual(changedObject.placement.zOrder, 3)
        XCTAssertFalse(changedObject.placement.isInline)
        XCTAssertEqual(changedObject.placement.horizontalReference, .page)
        XCTAssertEqual(changedObject.placement.verticalReference, .page)
        XCTAssertEqual(changedObject.placement.horizontalAlignment, .center)
        XCTAssertEqual(changedObject.placement.verticalAlignment, .end)
        XCTAssertEqual(changedObject.placement.wrap, .inFrontOfText)
        XCTAssertEqual(changedObject.placement.marginLeftPoints, 3, accuracy: 0.02)
        XCTAssertEqual(changedObject.placement.marginBottomPoints, 6, accuracy: 0.02)
        XCTAssertEqual(changedObject.placement.rotationDegrees, 27, accuracy: 0.02)
        guard case .shape(let changedShape) = changedObject.content else { return XCTFail("Not a shape") }
        XCTAssertEqual(changedShape.stroke.colorRGB, 0xD02030)
        XCTAssertEqual(changedShape.stroke.widthPoints, 2.25, accuracy: 0.02)
        XCTAssertEqual(changedShape.stroke.style, 2)
        XCTAssertEqual(changedShape.fill.colorRGB, 0xFFE090)
        XCTAssertEqual(changedShape.shadow?.colorRGB, 0x223344)
        XCTAssertEqual(changedShape.shadow?.offsetX ?? 0, 4, accuracy: 0.02)
        XCTAssertEqual(changedShape.shadow?.opacity ?? 0, 0.65, accuracy: 0.02)

        let changedTarget = try XCTUnwrap(HWPShapeEditing.target(owner: changedOwner, object: changedObject))
        let directLayout = try XCTUnwrap(HWPShapeEditing.directLayout(
            .resize(anchor: .topLeading, deltaX: 18, deltaY: -6), target: changedTarget))
        let directlyResized = try await HWPShapeEditing.applying(.update(directLayout),
            target: changedTarget, source: changed.document, drafts: changed.document.blocks)
        let directOwner = try XCTUnwrap(directlyResized.document.blocks.first {
            $0.id == changedOwner.id
        })
        let directObject = try XCTUnwrap(directOwner.canvasObjects.first { $0.id == changedObject.id })
        let directTarget = try XCTUnwrap(HWPShapeEditing.target(owner: directOwner,
            object: directObject))
        XCTAssertEqual(directTarget.xPoints, directLayout.xPoints, accuracy: 0.02)
        XCTAssertEqual(directTarget.yPoints, directLayout.yPoints, accuracy: 0.02)
        XCTAssertEqual(directTarget.widthPoints, directLayout.widthPoints, accuracy: 0.02)
        XCTAssertEqual(directTarget.heightPoints, directLayout.heightPoints, accuracy: 0.02)
        XCTAssertEqual(directTarget.rotationDegrees, changedTarget.rotationDegrees, accuracy: 0.02)

        let deleted = try await HWPShapeEditing.applying(.delete, target: directTarget,
            source: directlyResized.document, drafts: directlyResized.document.blocks)
        XCTAssertTrue(deleted.document.blocks[1].canvasObjects.isEmpty)
        _ = try HWPXDocumentPackage.load(from: deleted.document.data)
    }

    func testHWPShapeInsertMoveResizeLayerAndDeleteRoundTrip() async throws {
        let source = try HWPTableStructureDocument.load(fixture("hangul_design_application", "hwp"))
        let selection = try XCTUnwrap(source.blocks.compactMap { block in
            HWPShapeEditing.selection(blocks: source.blocks, selectedID: block.id,
                range: NSRange(location: block.text.utf16.count, length: 0), layouts: source.layouts)
        }.first)
        let inserted = try await HWPShapeEditing.inserting(.init(selection: selection, kind: .ellipse,
            widthPoints: 132, heightPoints: 78), source: source, drafts: source.blocks)
        let owner = try XCTUnwrap(inserted.document.blocks.first { $0.id == inserted.focusedID })
        let object = try XCTUnwrap(owner.canvasObjects.first { if case .shape = $0.content { return true }; return false })
        let target = try XCTUnwrap(HWPShapeEditing.target(owner: owner, object: object))
        let changed = try await HWPShapeEditing.applying(.update(.init(xPoints: 10, yPoints: 15,
            widthPoints: 160, heightPoints: 90, zOrder: 4, rotationDegrees: 42,
            strokeColorRGB: 0x123456, strokeWidthPoints: 1.5, strokeStyle: 3,
            fillColorRGB: 0xABCDEF,
            shadow: .init(colorRGB: 0x203040, offsetX: 3, offsetY: 6, opacity: 0.7),
            isInline: false, horizontalReference: .column, verticalReference: .page,
            horizontalAlignment: .end, verticalAlignment: .center, wrap: .topAndBottom,
            marginLeftPoints: 2, marginRightPoints: 3, marginTopPoints: 4, marginBottomPoints: 5)), target: target,
            source: inserted.document, drafts: inserted.document.blocks)
        let changedOwner = try XCTUnwrap(changed.document.blocks.first { $0.id == changed.focusedID })
        let changedObject = try XCTUnwrap(changedOwner.canvasObjects.first { if case .shape = $0.content { return true }; return false })
        XCTAssertEqual(changedObject.placement.xPoints, 10, accuracy: 0.02)
        XCTAssertEqual(changedObject.placement.yPoints, 15, accuracy: 0.02)
        XCTAssertEqual(changedObject.placement.widthPoints, 160, accuracy: 0.02)
        XCTAssertEqual(changedObject.placement.heightPoints, 90, accuracy: 0.02)
        XCTAssertEqual(changedObject.placement.zOrder, 4)
        XCTAssertFalse(changedObject.placement.isInline)
        XCTAssertEqual(changedObject.placement.horizontalReference, .column)
        XCTAssertEqual(changedObject.placement.verticalReference, .page)
        XCTAssertEqual(changedObject.placement.horizontalAlignment, .end)
        XCTAssertEqual(changedObject.placement.verticalAlignment, .center)
        XCTAssertEqual(changedObject.placement.wrap, .topAndBottom)
        XCTAssertEqual(changedObject.placement.marginTopPoints, 4, accuracy: 0.02)
        XCTAssertEqual(changedObject.placement.marginBottomPoints, 5, accuracy: 0.02)
        XCTAssertEqual(changedObject.placement.rotationDegrees, 42, accuracy: 0.02)
        guard case .shape(let changedShape) = changedObject.content else { return XCTFail("Not a shape") }
        XCTAssertEqual(changedShape.stroke.colorRGB, 0x123456)
        XCTAssertEqual(changedShape.stroke.widthPoints, 1.5, accuracy: 0.02)
        XCTAssertEqual(changedShape.stroke.style, 3)
        XCTAssertEqual(changedShape.fill.colorRGB, 0xABCDEF)
        XCTAssertEqual(changedShape.shadow?.colorRGB, 0x203040)
        XCTAssertEqual(changedShape.shadow?.offsetY ?? 0, 6, accuracy: 0.02)

        let changedTarget = try XCTUnwrap(HWPShapeEditing.target(owner: changedOwner, object: changedObject))
        let deleted = try await HWPShapeEditing.applying(.delete, target: changedTarget,
            source: changed.document, drafts: changed.document.blocks)
        let reopened = try HWPTableStructureDocument.load(deleted.document.data)
        XCTAssertFalse(reopened.blocks.flatMap(\.canvasObjects).contains { if case .shape = $0.content { return true }; return false })
    }

    func testHWPXLineInsertionRoundTrip() async throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "선"))
        let source = HWPTableStructureDocument.hwpx(package)
        let selection = try XCTUnwrap(HWPShapeEditing.selection(blocks: package.blocks,
            selectedID: package.blocks[0].id, range: NSRange(location: 1, length: 0), layouts: package.pageLayouts))
        let inserted = try await HWPShapeEditing.inserting(.init(selection: selection, kind: .line,
            widthPoints: 120, heightPoints: 48), source: source, drafts: package.blocks)
        let owner = try XCTUnwrap(inserted.document.blocks.first { $0.id == inserted.focusedID })
        let object = try XCTUnwrap(owner.canvasObjects.first)
        guard case .shape(let shape) = object.content,
              case .line = shape.geometry else { return XCTFail("Inserted object is not a line") }

        let reopened = try HWPXDocumentPackage.load(from: inserted.document.data)
        let reopenedObject = try XCTUnwrap(reopened.blocks.flatMap(\.canvasObjects).first)
        guard case .shape(let reopenedShape) = reopenedObject.content,
              case .line = reopenedShape.geometry else { return XCTFail("Reopened object is not a line") }
    }

    func testHWPXPolygonAndConnectorPointEditingRoundTrip() async throws {
        for kind in [HWPShapeEditing.Kind.polygon, .connector] {
            let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "점"))
            let source = HWPTableStructureDocument.hwpx(package)
            let selection = try XCTUnwrap(HWPShapeEditing.selection(blocks: package.blocks,
                selectedID: package.blocks[0].id, range: NSRange(location: 1, length: 0),
                layouts: package.pageLayouts))
            let inserted = try await HWPShapeEditing.inserting(.init(selection: selection, kind: kind,
                widthPoints: 150, heightPoints: 90), source: source, drafts: package.blocks)
            let owner = try XCTUnwrap(inserted.document.blocks.first { $0.id == inserted.focusedID })
            let object = try XCTUnwrap(owner.canvasObjects.first)
            let target = try XCTUnwrap(HWPShapeEditing.target(owner: owner, object: object))
            XCTAssertEqual(target.kind, kind)
            XCTAssertGreaterThanOrEqual(target.pathPoints.count, kind == .polygon ? 3 : 2)

            let points: [HWPShapeEditing.PathPoint] = kind == .polygon
                ? [.init(x: 0.08, y: 0.20), .init(x: 0.72, y: 0),
                   .init(x: 1, y: 0.70), .init(x: 0.36, y: 1)]
                : [.init(x: 0, y: 0.15), .init(x: 0.30, y: 0.15),
                   .init(x: 0.30, y: 0.75), .init(x: 1, y: 0.75)]
            let changed = try await HWPShapeEditing.applying(.update(layout(target,
                pathPoints: points, startArrow: kind == .connector ? 4 : 0,
                endArrow: kind == .connector ? 1 : 0)), target: target,
                source: inserted.document, drafts: inserted.document.blocks)
            let reopened = try HWPXDocumentPackage.load(from: changed.document.data)
            let reopenedOwner = try XCTUnwrap(reopened.blocks.first { !$0.canvasObjects.isEmpty })
            let reopenedObject = try XCTUnwrap(reopenedOwner.canvasObjects.first)
            let reopenedTarget = try XCTUnwrap(HWPShapeEditing.target(owner: reopenedOwner, object: reopenedObject))
            XCTAssertEqual(reopenedTarget.kind, kind)
            XCTAssertEqual(reopenedTarget.pathPoints.count, points.count)
            for (actual, expected) in zip(reopenedTarget.pathPoints, points) {
                XCTAssertEqual(actual.x, expected.x, accuracy: 0.011)
                XCTAssertEqual(actual.y, expected.y, accuracy: 0.011)
            }
            if kind == .connector {
                XCTAssertEqual(reopenedTarget.startArrow, 4)
                XCTAssertEqual(reopenedTarget.endArrow, 1)
            }
        }
    }

    func testPublicHWPPolygonAndCurvePointEditingRoundTrip() async throws {
        let cases: [(String, HWPShapeEditing.Kind, [HWPShapeEditing.PathPoint])] = [
            ("V32-polygon", .polygon, [.init(x: 0, y: 0.30), .init(x: 0.50, y: 0),
                .init(x: 1, y: 0.30), .init(x: 0.78, y: 1), .init(x: 0.22, y: 1)]),
            ("V34-curves", .connector, [.init(x: 0, y: 0), .init(x: 0.25, y: 0.70),
                .init(x: 0.75, y: 0.30), .init(x: 1, y: 1)])
        ]
        for (fixtureName, kind, points) in cases {
            let source = try HWPTableStructureDocument.load(fixture(fixtureName, "hwp"))
            let pair = try XCTUnwrap(source.blocks.compactMap { owner -> (HWPDocumentBlock, HWPDocumentCanvasObject)? in
                owner.canvasObjects.first(where: { object in
                    guard let target = HWPShapeEditing.target(owner: owner, object: object) else { return false }
                    return target.kind == kind
                }).map { (owner, $0) }
            }.first)
            let target = try XCTUnwrap(HWPShapeEditing.target(owner: pair.0, object: pair.1))
            let updatedLayout = layout(target,
                pathPoints: points, startArrow: kind == .connector ? 2 : 0,
                endArrow: kind == .connector ? 1 : 0)
            let changed = try await HWPShapeEditing.applying(.update(updatedLayout), target: target,
                source: source, drafts: source.blocks)
            let reopened = try HWPTableStructureDocument.load(changed.document.data)
            let reopenedTarget = try XCTUnwrap(reopened.blocks.compactMap { owner in
                owner.canvasObjects.compactMap { HWPShapeEditing.target(owner: owner, object: $0) }
                    .first { $0.kind == kind }
            }.first)
            XCTAssertEqual(reopenedTarget.pathPoints.count, points.count)
            for (actual, expected) in zip(reopenedTarget.pathPoints, points) {
                XCTAssertEqual(actual.x, expected.x, accuracy: 0.015)
                XCTAssertEqual(actual.y, expected.y, accuracy: 0.015)
            }
            if kind == .connector {
                XCTAssertEqual(reopenedTarget.startArrow, 2)
                XCTAssertEqual(reopenedTarget.endArrow, 1)
            }
        }
    }

    func testHWPGroupMoveResizeRotationAndPlacementPreservesChildren() async throws {
        let source = try HWPTableStructureDocument.load(fixture("V25-group", "hwp"))
        let owner = try XCTUnwrap(source.blocks.first { block in
            block.canvasObjects.contains { if case .group = $0.content { return true }; return false }
        })
        let object = try XCTUnwrap(owner.canvasObjects.first {
            if case .group = $0.content { return true }; return false
        })
        guard case .group(let originalShapes) = object.content else {
            return XCTFail("Fixture object is not a group")
        }
        let target = try XCTUnwrap(HWPShapeEditing.target(owner: owner, object: object))
        XCTAssertTrue(target.isGroup)
        let layout = HWPShapeEditing.Layout(xPoints: target.xPoints + 11, yPoints: target.yPoints + 7,
            widthPoints: target.widthPoints + 30, heightPoints: target.heightPoints + 20,
            zOrder: target.zOrder + 2, rotationDegrees: 33,
            strokeColorRGB: target.strokeColorRGB, strokeWidthPoints: max(target.strokeWidthPoints, 0.1),
            strokeStyle: target.strokeStyle, fillColorRGB: target.fillColorRGB, shadow: target.shadow,
            isInline: false, horizontalReference: .page, verticalReference: .paragraph,
            horizontalAlignment: .center, verticalAlignment: .end, wrap: .behindText,
            marginLeftPoints: 2, marginRightPoints: 3, marginTopPoints: 4, marginBottomPoints: 5)
        let changed = try await HWPShapeEditing.applying(.update(layout), target: target,
            source: source, drafts: source.blocks)
        let reopened = try HWPTableStructureDocument.load(changed.document.data)
        let changedObject = try XCTUnwrap(reopened.blocks.flatMap(\.canvasObjects).first {
            if case .group = $0.content { return true }; return false
        })
        guard case .group(let changedShapes) = changedObject.content else {
            return XCTFail("Changed object is not a group")
        }
        XCTAssertEqual(changedShapes.count, originalShapes.count)
        XCTAssertEqual(changedShapes.map(\.geometry), originalShapes.map(\.geometry))
        XCTAssertEqual(changedObject.placement.xPoints, layout.xPoints, accuracy: 0.02)
        XCTAssertEqual(changedObject.placement.yPoints, layout.yPoints, accuracy: 0.02)
        XCTAssertEqual(changedObject.placement.widthPoints, layout.widthPoints, accuracy: 0.02)
        XCTAssertEqual(changedObject.placement.heightPoints, layout.heightPoints, accuracy: 0.02)
        XCTAssertEqual(changedObject.placement.rotationDegrees, 33, accuracy: 0.02)
        XCTAssertFalse(changedObject.placement.isInline)
        XCTAssertEqual(changedObject.placement.horizontalReference, .page)
        XCTAssertEqual(changedObject.placement.horizontalAlignment, .center)
        XCTAssertEqual(changedObject.placement.verticalAlignment, .end)
        XCTAssertEqual(changedObject.placement.wrap, .behindText)
        XCTAssertEqual(changedObject.placement.marginBottomPoints, 5, accuracy: 0.02)
    }

    func testHWPGroupChildCanBeSelectedStyledMovedAndResizedWithoutChangingSiblings() async throws {
        let source = try HWPTableStructureDocument.load(fixture("V25-group", "hwp"))
        let owner = try XCTUnwrap(source.blocks.first { block in
            block.canvasObjects.contains { if case .group = $0.content { return true }; return false }
        })
        let object = try XCTUnwrap(owner.canvasObjects.first {
            if case .group = $0.content { return true }; return false
        })
        guard case .group(let originalShapes) = object.content else {
            return XCTFail("Fixture object is not a group")
        }
        let pair = try XCTUnwrap(originalShapes.indices.compactMap { index -> (Int, HWPShapeEditing.Target)? in
            HWPShapeEditing.target(owner: owner, object: object, groupChildIndex: index).map { (index, $0) }
        }.first)
        let index = pair.0, target = pair.1
        XCTAssertTrue(target.isGroupChild)
        XCTAssertEqual(target.id, "\(object.id)#group-child-\(index)")
        let updated = HWPShapeEditing.Layout(
            xPoints: target.xPoints + 5, yPoints: target.yPoints + 3,
            widthPoints: target.widthPoints + 12, heightPoints: target.heightPoints + 8,
            zOrder: target.zOrder, rotationDegrees: 21,
            strokeColorRGB: 0xB02040, strokeWidthPoints: 2, strokeStyle: 2,
            fillColorRGB: target.kind == .line || target.kind == .connector ? nil : 0xF4D060,
            shadow: .init(colorRGB: 0x303040, offsetX: 2, offsetY: 4, opacity: 0.6),
            isInline: target.isInline, horizontalReference: target.horizontalReference,
            verticalReference: target.verticalReference,
            horizontalAlignment: target.horizontalAlignment,
            verticalAlignment: target.verticalAlignment, wrap: target.wrap,
            marginLeftPoints: target.marginLeftPoints, marginRightPoints: target.marginRightPoints,
            marginTopPoints: target.marginTopPoints, marginBottomPoints: target.marginBottomPoints,
            pathPoints: target.pathPoints, startArrow: target.startArrow, endArrow: target.endArrow)
        let result = try await HWPShapeEditing.applying(.update(updated), target: target,
            source: source, drafts: source.blocks)
        let reopened = try HWPTableStructureDocument.load(result.document.data)
        let reopenedOwner = try XCTUnwrap(reopened.blocks.first { $0.id == owner.id })
        let reopenedObject = try XCTUnwrap(reopenedOwner.canvasObjects.first { $0.id == object.id })
        guard case .group(let changedShapes) = reopenedObject.content else {
            return XCTFail("Edited object is not a group")
        }
        XCTAssertEqual(changedShapes.count, originalShapes.count)
        XCTAssertEqual(reopenedObject.groupChildBounds, object.groupChildBounds)
        let changed = try XCTUnwrap(HWPShapeEditing.target(owner: reopenedOwner,
            object: reopenedObject, groupChildIndex: index))
        XCTAssertEqual(changed.xPoints, updated.xPoints, accuracy: 0.02)
        XCTAssertEqual(changed.yPoints, updated.yPoints, accuracy: 0.02)
        XCTAssertEqual(changed.widthPoints, updated.widthPoints, accuracy: 0.02)
        XCTAssertEqual(changed.heightPoints, updated.heightPoints, accuracy: 0.02)
        XCTAssertEqual(changed.rotationDegrees, updated.rotationDegrees, accuracy: 0.02)
        XCTAssertEqual(changed.strokeColorRGB, updated.strokeColorRGB)
        XCTAssertEqual(changed.strokeWidthPoints, updated.strokeWidthPoints, accuracy: 0.02)
        XCTAssertEqual(changed.strokeStyle, updated.strokeStyle)
        if updated.fillColorRGB != nil { XCTAssertEqual(changed.fillColorRGB, updated.fillColorRGB) }
        XCTAssertEqual(changed.shadow?.colorRGB, updated.shadow?.colorRGB)
        for sibling in originalShapes.indices where sibling != index {
            XCTAssertEqual(changedShapes[sibling], originalShapes[sibling])
        }
        let deleted = try await HWPShapeEditing.applying(.delete, target: changed,
            source: reopened, drafts: reopened.blocks)
        let deletedOwner = try XCTUnwrap(deleted.document.blocks.first { $0.id == owner.id })
        if originalShapes.count == 2 {
            XCTAssertFalse(deletedOwner.canvasObjects.contains {
                if case .group = $0.content { return true }
                return false
            })
            XCTAssertTrue(deletedOwner.canvasObjects.contains {
                if case .shape = $0.content { return true }
                return false
            })
        } else {
            let deletedObject = try XCTUnwrap(deletedOwner.canvasObjects.first { $0.id == object.id })
            guard case .group(let remaining) = deletedObject.content else {
                return XCTFail("Deleted child must leave the group")
            }
            XCTAssertEqual(remaining.count, originalShapes.count - 1)
        }

        let movable = try XCTUnwrap(originalShapes.indices.compactMap { childIndex in
            HWPShapeEditing.target(owner: owner, object: object, groupChildIndex: childIndex)
        }.first(where: \.canMoveGroupChildForward))
        let reordered = try await HWPShapeEditing.applying(.moveGroupChild(offset: 1), target: movable,
            source: source, drafts: source.blocks)
        let reorderedOwner = try XCTUnwrap(reordered.document.blocks.first { $0.id == owner.id })
        let reorderedObject = try XCTUnwrap(reorderedOwner.canvasObjects.first { $0.id == object.id })
        guard case .group(let reorderedShapes) = reorderedObject.content else {
            return XCTFail("Reordered object must remain a group")
        }
        let movedIndex = try XCTUnwrap(movable.groupChildIndex)
        XCTAssertEqual(reorderedShapes[movedIndex], originalShapes[movedIndex + 1])
        XCTAssertEqual(reorderedShapes[movedIndex + 1], originalShapes[movedIndex])

        let groupTarget = try XCTUnwrap(HWPShapeEditing.target(owner: owner, object: object))
        let ungrouped = try await HWPShapeEditing.applying(.ungroup, target: groupTarget,
            source: source, drafts: source.blocks)
        let ungroupedOwner = try XCTUnwrap(ungrouped.document.blocks.first { $0.id == owner.id })
        XCTAssertFalse(ungroupedOwner.canvasObjects.contains {
            if case .group = $0.content { return true }
            return false
        })
        XCTAssertGreaterThanOrEqual(ungroupedOwner.canvasObjects.filter {
            if case .shape = $0.content { return true }
            return false
        }.count, originalShapes.count)
    }

    func testHWPXGroupChildCanBeSelectedAndEditedWithoutChangingSibling() async throws {
        let base = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "그룹"))
        let section = try XCTUnwrap(base.sections.first)
        let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: section.xml)
        let paragraph = (section.xml as NSString).substring(with: try XCTUnwrap(ranges.first))
        let run = try XCTUnwrap(HWPFormattingXML.elements(paragraph, name: "run").first)
        let prefix = try HWPFormattingXML.prefix(run.xml)
        let group = """
        <\(prefix)container id="900" zOrder="0" textWrap="TOP_AND_BOTTOM">
          <\(prefix)sz width="24000" height="12000"/><\(prefix)pos treatAsChar="1" horzOffset="0" vertOffset="0" horzRelTo="PARA" vertRelTo="PARA"/>
          <\(prefix)rect id="901" ratio="0"><\(prefix)sz width="9000" height="6000"/><\(prefix)pos treatAsChar="0" horzOffset="1000" vertOffset="1500"/><\(prefix)lineShape color="#102030" width="100" style="SOLID"/><\(prefix)fillBrush><\(prefix)winBrush faceColor="#DDEEFF" hatchColor="#DDEEFF" alpha="0"/></\(prefix)fillBrush></\(prefix)rect>
          <\(prefix)ellipse id="902"><\(prefix)sz width="8000" height="5000"/><\(prefix)pos treatAsChar="0" horzOffset="13000" vertOffset="3500"/><\(prefix)lineShape color="#405060" width="100" style="SOLID"/><\(prefix)fillBrush><\(prefix)winBrush faceColor="#FFEEDD" hatchColor="#FFEEDD" alpha="0"/></\(prefix)fillBrush></\(prefix)ellipse>
        </\(prefix)container>
        """
        let changedRun = try HWPFormattingXML.append(group, to: run.xml)
        let changedParagraph = (paragraph as NSString).replacingCharacters(in: run.range, with: changedRun)
        let changedSection = (section.xml as NSString).replacingCharacters(in: ranges[0], with: changedParagraph)
        let data = try HWPXEditingArchive(data: base.sourceData).repack(
            replacing: [section.path: Data(changedSection.utf8)])
        let source = try HWPTableStructureDocument.load(data)
        let owner = try XCTUnwrap(source.blocks.first { block in
            block.canvasObjects.contains { if case .group = $0.content { return true }; return false }
        })
        let object = try XCTUnwrap(owner.canvasObjects.first {
            if case .group = $0.content { return true }; return false
        })
        guard case .group(let original) = object.content else { return XCTFail("Missing group") }
        XCTAssertEqual(original.count, 2)
        let target = try XCTUnwrap(HWPShapeEditing.target(owner: owner, object: object,
            groupChildIndex: 0))
        let layout = HWPShapeEditing.Layout(xPoints: 22, yPoints: 18,
            widthPoints: 112, heightPoints: 68, zOrder: target.zOrder,
            rotationDegrees: 17, strokeColorRGB: 0xC02030,
            strokeWidthPoints: 2.5, strokeStyle: 3, fillColorRGB: 0xAACC66,
            shadow: .init(colorRGB: 0x202020, offsetX: 3, offsetY: 4, opacity: 0.55),
            isInline: target.isInline, horizontalReference: target.horizontalReference,
            verticalReference: target.verticalReference,
            horizontalAlignment: target.horizontalAlignment,
            verticalAlignment: target.verticalAlignment, wrap: target.wrap,
            marginLeftPoints: target.marginLeftPoints, marginRightPoints: target.marginRightPoints,
            marginTopPoints: target.marginTopPoints, marginBottomPoints: target.marginBottomPoints)
        let result = try await HWPShapeEditing.applying(.update(layout), target: target,
            source: source, drafts: source.blocks)
        let reopened = try HWPTableStructureDocument.load(result.document.data)
        let reopenedOwner = try XCTUnwrap(reopened.blocks.first { $0.id == owner.id })
        let reopenedObject = try XCTUnwrap(reopenedOwner.canvasObjects.first { $0.id == object.id })
        guard case .group(let current) = reopenedObject.content else { return XCTFail("Missing group") }
        XCTAssertEqual(current.count, 2)
        // The edited first child changes the union of child frames. The group
        // coordinate frame must stay at its pre-edit value after serialization,
        // otherwise the untouched ellipse is redrawn at a different size.
        XCTAssertEqual(reopenedObject.groupChildBounds, object.groupChildBounds)
        XCTAssertNotNil(reopenedObject.groupCoordinateFrame)
        let beforeBounds = try XCTUnwrap(object.groupChildBounds)
        let afterBounds = try XCTUnwrap(reopenedObject.groupChildBounds)
        let siblingFrame = try XCTUnwrap(original[1].localFrame)
        XCTAssertEqual(siblingFrame.height * object.placement.heightPoints / beforeBounds.height,
            siblingFrame.height * reopenedObject.placement.heightPoints / afterBounds.height,
            accuracy: 0.02)
        let edited = try XCTUnwrap(HWPShapeEditing.target(owner: reopenedOwner,
            object: reopenedObject, groupChildIndex: 0))
        XCTAssertEqual(edited.xPoints, 22, accuracy: 0.02)
        XCTAssertEqual(edited.yPoints, 18, accuracy: 0.02)
        XCTAssertEqual(edited.widthPoints, 112, accuracy: 0.02)
        XCTAssertEqual(edited.heightPoints, 68, accuracy: 0.02)
        XCTAssertEqual(edited.rotationDegrees, 17, accuracy: 0.02)
        XCTAssertEqual(edited.strokeColorRGB, 0xC02030)
        XCTAssertEqual(edited.fillColorRGB, 0xAACC66)
        XCTAssertEqual(current[1], original[1])

        let reordered = try await HWPShapeEditing.applying(.moveGroupChild(offset: 1), target: target,
            source: source, drafts: source.blocks)
        let reorderedOwner = try XCTUnwrap(reordered.document.blocks.first { $0.id == owner.id })
        let reorderedObject = try XCTUnwrap(reorderedOwner.canvasObjects.first { $0.id == object.id })
        guard case .group(let reorderedShapes) = reorderedObject.content else {
            return XCTFail("Reordered object must remain a group")
        }
        XCTAssertEqual(reorderedShapes, [original[1], original[0]])

        let deletedTarget = try XCTUnwrap(HWPShapeEditing.target(owner: reorderedOwner,
            object: reorderedObject, groupChildIndex: 1))
        let deleted = try await HWPShapeEditing.applying(.delete, target: deletedTarget,
            source: reordered.document, drafts: reordered.document.blocks)
        let deletedOwner = try XCTUnwrap(deleted.document.blocks.first { $0.id == owner.id })
        XCTAssertFalse(deletedOwner.canvasObjects.contains {
            if case .group = $0.content { return true }
            return false
        })
        XCTAssertTrue(deletedOwner.canvasObjects.contains {
            if case .shape = $0.content { return true }
            return false
        })

        let groupTarget = try XCTUnwrap(HWPShapeEditing.target(owner: owner, object: object))
        let ungrouped = try await HWPShapeEditing.applying(.ungroup, target: groupTarget,
            source: source, drafts: source.blocks)
        let ungroupedOwner = try XCTUnwrap(ungrouped.document.blocks.first { $0.id == owner.id })
        XCTAssertFalse(ungroupedOwner.canvasObjects.contains {
            if case .group = $0.content { return true }
            return false
        })
        XCTAssertGreaterThanOrEqual(ungroupedOwner.canvasObjects.filter {
            if case .shape = $0.content { return true }
            return false
        }.count, original.count)
    }

    func testViewModelGroupChildEditUndoRedoAndSave() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwp")
        try fixture("V25-group", "hwp").write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let original = model.blocks
        let owner = try XCTUnwrap(model.blocks.first { block in
            block.canvasObjects.contains { if case .group = $0.content { return true }; return false }
        })
        let object = try XCTUnwrap(owner.canvasObjects.first {
            if case .group = $0.content { return true }; return false
        })
        let target = try XCTUnwrap((0..<64).compactMap {
            HWPShapeEditing.target(owner: owner, object: object, groupChildIndex: $0)
        }.first)
        let changedLayout = layout(target, pathPoints: target.pathPoints,
            startArrow: target.startArrow, endArrow: target.endArrow,
            x: target.xPoints + 4, y: target.yPoints + 6,
            stroke: 0x1460B8, fill: target.kind == .line || target.kind == .connector ? nil : 0xA8D8F0)
        _ = try await model.editShape(.update(changedLayout), target: target)
        let changed = model.blocks
        XCTAssertNotEqual(changed, original)
        XCTAssertTrue(model.hasUnsavedChanges)
        model.undo(); XCTAssertEqual(model.blocks, original)
        model.redo(); XCTAssertEqual(model.blocks, changed)
        await model.save()
        XCTAssertNil(model.errorDescription)
        XCTAssertFalse(model.hasUnsavedChanges)
        let reopened = try HWPTableStructureDocument.load(Data(contentsOf: url))
        let reopenedOwner = try XCTUnwrap(reopened.blocks.first { $0.id == owner.id })
        let reopenedObject = try XCTUnwrap(reopenedOwner.canvasObjects.first { $0.id == object.id })
        let reopenedTarget = try XCTUnwrap(HWPShapeEditing.target(owner: reopenedOwner,
            object: reopenedObject, groupChildIndex: target.groupChildIndex))
        XCTAssertEqual(reopenedTarget.xPoints, changedLayout.xPoints, accuracy: 0.02)
        XCTAssertEqual(reopenedTarget.yPoints, changedLayout.yPoints, accuracy: 0.02)
        XCTAssertEqual(reopenedTarget.strokeColorRGB, changedLayout.strokeColorRGB)
    }

    func testViewModelGroupReorderAndUngroupUndoRedoSave() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwp")
        try fixture("V25-group", "hwp").write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let original = model.blocks
        let owner = try XCTUnwrap(model.blocks.first { block in
            block.canvasObjects.contains { if case .group = $0.content { return true }; return false }
        })
        let object = try XCTUnwrap(owner.canvasObjects.first {
            if case .group = $0.content { return true }; return false
        })
        let child = try XCTUnwrap((0..<64).compactMap {
            HWPShapeEditing.target(owner: owner, object: object, groupChildIndex: $0)
        }.first(where: \.canMoveGroupChildForward))
        _ = try await model.editShape(.moveGroupChild(offset: 1), target: child)
        let reordered = model.blocks
        XCTAssertNotEqual(reordered, original)
        model.undo(); XCTAssertEqual(model.blocks, original)
        model.redo(); XCTAssertEqual(model.blocks, reordered)
        model.undo(); XCTAssertEqual(model.blocks, original)

        let restoredOwner = try XCTUnwrap(model.blocks.first { $0.id == owner.id })
        let restoredObject = try XCTUnwrap(restoredOwner.canvasObjects.first {
            if case .group = $0.content { return true }; return false
        })
        let group = try XCTUnwrap(HWPShapeEditing.target(owner: restoredOwner, object: restoredObject))
        _ = try await model.editShape(.ungroup, target: group)
        let ungrouped = model.blocks
        XCTAssertFalse(ungrouped.flatMap(\.canvasObjects).contains {
            if case .group = $0.content { return true }
            return false
        })
        model.undo(); XCTAssertEqual(model.blocks, original)
        model.redo(); XCTAssertEqual(model.blocks, ungrouped)
        await model.save()
        XCTAssertNil(model.errorDescription)
        XCTAssertFalse(model.hasUnsavedChanges)
        let reopened = try HWPTableStructureDocument.load(Data(contentsOf: url))
        XCTAssertFalse(reopened.blocks.flatMap(\.canvasObjects).contains {
            if case .group = $0.content { return true }
            return false
        })
        XCTAssertGreaterThanOrEqual(reopened.blocks.flatMap(\.canvasObjects).filter {
            if case .shape = $0.content { return true }
            return false
        }.count, group.groupChildCount)
    }

    func testHWPIndependentShapesCanBeGroupedAndUngroupedRoundTrip() async throws {
        let source = try HWPTableStructureDocument.load(fixture("V25-group", "hwp"))
        let owner = try XCTUnwrap(source.blocks.first { block in
            block.canvasObjects.contains { if case .group = $0.content { return true }; return false }
        })
        let object = try XCTUnwrap(owner.canvasObjects.first {
            if case .group = $0.content { return true }; return false
        })
        let target = try XCTUnwrap(HWPShapeEditing.target(owner: owner, object: object))
        let ungrouped = try await HWPShapeEditing.applying(.ungroup, target: target,
            source: source, drafts: source.blocks)
        let independentOwner = try XCTUnwrap(ungrouped.document.blocks.first { $0.id == owner.id })
        let independent = independentOwner.canvasObjects.filter {
            if case .shape = $0.content { return true }
            return false
        }
        XCTAssertEqual(independent.count, target.groupChildCount)

        let grouped = try await HWPShapeEditing.grouping(.init(ownerID: independentOwner.id,
            objectIDs: independent.map(\.id)), source: ungrouped.document,
            drafts: ungrouped.document.blocks)
        let reopened = try HWPTableStructureDocument.load(grouped.document.data)
        let reopenedOwner = try XCTUnwrap(reopened.blocks.first { $0.id == owner.id })
        let reopenedGroup = try XCTUnwrap(reopenedOwner.canvasObjects.first {
            if case .group = $0.content { return true }; return false
        })
        guard case .group(let children) = reopenedGroup.content else { return XCTFail("Missing group") }
        XCTAssertEqual(children.count, independent.count)
        XCTAssertTrue(children.allSatisfy { $0.localFrame != nil })
    }

    func testHWPXIndependentShapesCanBeGroupedRoundTrip() async throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: ""))
        let initial = HWPTableStructureDocument.hwpx(package)
        let selection = HWPShapeEditing.Selection(blockID: package.blocks[0].id,
            text: "", caret: 0, width: 400)
        let firstData = try HWPShapeEditingWriter.insert(.init(selection: selection,
            kind: .rectangle, widthPoints: 100, heightPoints: 60), into: initial, ownerIndex: 0)
        let firstPackage = try HWPXDocumentPackage.load(from: firstData)
        let section = try XCTUnwrap(firstPackage.sections.first)
        let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: section.xml)
        let paragraph = (section.xml as NSString).substring(with: ranges[0])
        let run = try XCTUnwrap(HWPFormattingXML.elements(paragraph, name: "run").first)
        let rectangle = try XCTUnwrap(HWPFormattingXML.elements(paragraph, name: "rect").first)
        var duplicate = try HWPFormattingXML.setAttribute(rectangle.xml, "id", "902")
        var position = try XCTUnwrap(HWPFormattingXML.elements(duplicate, name: "pos").first?.xml)
        position = try HWPFormattingXML.setAttribute(position, "horzOffset", "12000")
        duplicate = try HWPFormattingXML.replaceOrAppend(duplicate, name: "pos", replacement: position)
        let changedRun = try HWPFormattingXML.append(duplicate, to: run.xml)
        let changedParagraph = (paragraph as NSString).replacingCharacters(in: run.range, with: changedRun)
        let changedSection = (section.xml as NSString).replacingCharacters(in: ranges[0], with: changedParagraph)
        let secondData = try HWPXEditingArchive(data: firstPackage.sourceData).repack(
            replacing: [section.path: Data(changedSection.utf8)])
        let source = try HWPTableStructureDocument.load(secondData)
        let owner = source.blocks[0]
        let shapes = owner.canvasObjects.filter { if case .shape = $0.content { return true }; return false }
        XCTAssertEqual(shapes.count, 2)

        let grouped = try await HWPShapeEditing.grouping(.init(ownerID: owner.id,
            objectIDs: shapes.map(\.id)), source: source, drafts: source.blocks)
        let reopened = try HWPTableStructureDocument.load(grouped.document.data)
        let group = try XCTUnwrap(reopened.blocks[0].canvasObjects.first {
            if case .group = $0.content { return true }; return false
        })
        guard case .group(let children) = group.content else { return XCTFail("Missing group") }
        XCTAssertEqual(children.count, 2)
        XCTAssertTrue(children.allSatisfy { $0.localFrame != nil })

        XCTAssertEqual(HWPShapeEditing.groupChildIndex(at: CGPoint(x: 50, y: 30), in: group), 0)
        XCTAssertEqual(HWPShapeEditing.groupChildIndex(at: CGPoint(x: 170, y: 30), in: group), 1)
        XCTAssertNil(HWPShapeEditing.groupChildIndex(at: CGPoint(x: 110, y: 30), in: group))
        XCTAssertNil(HWPShapeEditing.groupChildIndex(at: CGPoint(x: -10, y: 30), in: group))

        // Regression: HWPX group targets have no single-shape kind. Outer edits
        // must update the container, including missing properties, not its first child.
        let target = try XCTUnwrap(HWPShapeEditing.target(owner: reopened.blocks[0], object: group))
        let layout = HWPShapeEditing.Layout(xPoints: 25, yPoints: 65,
            widthPoints: target.widthPoints + 30, heightPoints: target.heightPoints + 20,
            zOrder: 3, rotationDegrees: 27, flipHorizontal: true, flipVertical: true,
            strokeColorRGB: target.strokeColorRGB, strokeWidthPoints: max(0.1, target.strokeWidthPoints),
            strokeStyle: target.strokeStyle, fillColorRGB: target.fillColorRGB, shadow: target.shadow,
            isInline: false, horizontalReference: .page, verticalReference: .paragraph,
            horizontalAlignment: .start, verticalAlignment: .start, wrap: .inFrontOfText,
            marginLeftPoints: 2, marginRightPoints: 3, marginTopPoints: 4, marginBottomPoints: 5)
        let edited = try await HWPShapeEditing.applying(.update(layout), target: target,
            source: reopened, drafts: reopened.blocks)
        let saved = try HWPTableStructureDocument.load(edited.document.data)
        let editedOwner = try XCTUnwrap(saved.blocks.first { $0.id == target.ownerID })
        let editedGroup = try XCTUnwrap(editedOwner.canvasObjects.first { $0.id == group.id })
        guard case .group(let unchangedChildren) = editedGroup.content else { return XCTFail("Lost group") }
        XCTAssertEqual(unchangedChildren, children)
        XCTAssertEqual(editedGroup.placement.xPoints, 25, accuracy: 0.02)
        XCTAssertEqual(editedGroup.placement.yPoints, 65, accuracy: 0.02)
        XCTAssertEqual(editedGroup.placement.widthPoints, layout.widthPoints, accuracy: 0.02)
        XCTAssertEqual(editedGroup.placement.heightPoints, layout.heightPoints, accuracy: 0.02)
        XCTAssertEqual(editedGroup.placement.rotationDegrees, 27, accuracy: 0.02)
        XCTAssertTrue(editedGroup.placement.flipHorizontal)
        XCTAssertTrue(editedGroup.placement.flipVertical)
        // Group flips and scaling also affect which child is under the tap.
        XCTAssertEqual(HWPShapeEditing.groupChildIndex(at: CGPoint(
            x: layout.widthPoints * (1 - 50.0 / 220), y: layout.heightPoints / 2),
            in: editedGroup), 0)
        XCTAssertEqual(HWPShapeEditing.groupChildIndex(at: CGPoint(
            x: layout.widthPoints * (1 - 170.0 / 220), y: layout.heightPoints / 2),
            in: editedGroup), 1)
        XCTAssertEqual(editedGroup.placement.wrap, .inFrontOfText)
        XCTAssertEqual(editedGroup.placement.horizontalReference, .page)
        XCTAssertEqual(editedGroup.placement.marginBottomPoints, 5, accuracy: 0.02)
        let beforeXML = try XCTUnwrap(HWPXDocumentPackage.load(from: reopened.data).sections.first?.xml)
        let afterXML = try XCTUnwrap(HWPXDocumentPackage.load(from: saved.data).sections.first?.xml)
        XCTAssertEqual(try HWPFormattingXML.elements(beforeXML, name: "rect").map(\.xml),
            try HWPFormattingXML.elements(afterXML, name: "rect").map(\.xml))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        try reopened.data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let beforeEdit = model.blocks
        _ = try await model.editShape(.update(layout), target: target)
        let afterEdit = model.blocks
        XCTAssertNotEqual(afterEdit, beforeEdit)
        model.undo(); XCTAssertEqual(model.blocks, beforeEdit)
        model.redo(); XCTAssertEqual(model.blocks, afterEdit)
        await model.save()
        XCTAssertNil(model.errorDescription)
        XCTAssertFalse(model.hasUnsavedChanges)
        let modelSaved = try HWPTableStructureDocument.load(Data(contentsOf: url))
        XCTAssertEqual(modelSaved.blocks.flatMap(\.canvasObjects), saved.blocks.flatMap(\.canvasObjects))
        let updatedTarget = try XCTUnwrap(HWPShapeEditing.target(owner: editedOwner, object: editedGroup))
        let deleted = try await HWPShapeEditing.applying(.delete, target: updatedTarget,
            source: saved, drafts: saved.blocks)
        XCTAssertTrue(deleted.document.blocks.flatMap(\.canvasObjects).isEmpty)
    }

    func testHWPIndependentShapesAlignRightRoundTrip() async throws {
        let source = try HWPTableStructureDocument.load(fixture("V25-group", "hwp"))
        let owner = try XCTUnwrap(source.blocks.first { block in
            block.canvasObjects.contains { if case .group = $0.content { return true }; return false }
        })
        let object = try XCTUnwrap(owner.canvasObjects.first {
            if case .group = $0.content { return true }; return false
        })
        let group = try XCTUnwrap(HWPShapeEditing.target(owner: owner, object: object))
        let ungrouped = try await HWPShapeEditing.applying(.ungroup, target: group,
            source: source, drafts: source.blocks)
        let independentOwner = try XCTUnwrap(ungrouped.document.blocks.first { $0.id == owner.id })
        let shapes = independentOwner.canvasObjects.filter {
            if case .shape = $0.content { return true }
            return false
        }
        XCTAssertGreaterThanOrEqual(shapes.count, 2)
        let originalY = Dictionary(uniqueKeysWithValues: shapes.map { ($0.id, $0.placement.yPoints) })

        let aligned = try await HWPShapeEditing.arranging(.init(ownerID: independentOwner.id,
            objectIDs: shapes.map(\.id), arrangement: .alignRight), source: ungrouped.document,
            drafts: ungrouped.document.blocks)
        let reopened = try HWPTableStructureDocument.load(aligned.document.data)
        let alignedOwner = try XCTUnwrap(reopened.blocks.first { $0.id == owner.id })
        let targets = shapes.compactMap { original in
            alignedOwner.canvasObjects.first(where: { $0.id == original.id }).flatMap {
                HWPShapeEditing.target(owner: alignedOwner, object: $0)
            }
        }
        XCTAssertEqual(targets.count, shapes.count)
        let rightEdge = try XCTUnwrap(targets.first.map { $0.xPoints + $0.widthPoints })
        for target in targets {
            XCTAssertEqual(target.xPoints + target.widthPoints, rightEdge, accuracy: 0.03)
            XCTAssertEqual(target.yPoints, try XCTUnwrap(originalY[target.objectID]), accuracy: 0.03)
        }
    }

    func testHWPXIndependentShapesDistributeHorizontallyRoundTrip() async throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: ""))
        let initial = HWPTableStructureDocument.hwpx(package)
        let selection = HWPShapeEditing.Selection(blockID: package.blocks[0].id,
            text: "", caret: 0, width: 500)
        let firstData = try HWPShapeEditingWriter.insert(.init(selection: selection,
            kind: .rectangle, widthPoints: 100, heightPoints: 60), into: initial, ownerIndex: 0)
        let firstPackage = try HWPXDocumentPackage.load(from: firstData)
        let section = try XCTUnwrap(firstPackage.sections.first)
        let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: section.xml)
        let paragraph = (section.xml as NSString).substring(with: ranges[0])
        let run = try XCTUnwrap(HWPFormattingXML.elements(paragraph, name: "run").first)
        let rectangle = try XCTUnwrap(HWPFormattingXML.elements(paragraph, name: "rect").first)
        var changedRun = run.xml
        for (id, offset) in [("902", "12000"), ("903", "36000")] {
            var duplicate = try HWPFormattingXML.setAttribute(rectangle.xml, "id", id)
            var position = try XCTUnwrap(HWPFormattingXML.elements(duplicate, name: "pos").first?.xml)
            position = try HWPFormattingXML.setAttribute(position, "horzOffset", offset)
            duplicate = try HWPFormattingXML.replaceOrAppend(duplicate, name: "pos", replacement: position)
            changedRun = try HWPFormattingXML.append(duplicate, to: changedRun)
        }
        let changedParagraph = (paragraph as NSString).replacingCharacters(in: run.range, with: changedRun)
        let changedSection = (section.xml as NSString).replacingCharacters(in: ranges[0], with: changedParagraph)
        let data = try HWPXEditingArchive(data: firstPackage.sourceData).repack(
            replacing: [section.path: Data(changedSection.utf8)])
        let source = try HWPTableStructureDocument.load(data)
        let owner = source.blocks[0]
        let shapes = owner.canvasObjects.filter { if case .shape = $0.content { return true }; return false }
        XCTAssertEqual(shapes.count, 3)
        let original = shapes.sorted { $0.placement.xPoints < $1.placement.xPoints }

        let distributed = try await HWPShapeEditing.arranging(.init(ownerID: owner.id,
            objectIDs: shapes.map(\.id), arrangement: .distributeHorizontally), source: source,
            drafts: source.blocks)
        let reopened = try HWPTableStructureDocument.load(distributed.document.data)
        let arranged = reopened.blocks[0].canvasObjects.filter {
            if case .shape = $0.content { return true }; return false
        }.sorted { $0.placement.xPoints < $1.placement.xPoints }
        XCTAssertEqual(arranged.count, 3)
        XCTAssertEqual(arranged[0].placement.xPoints, original[0].placement.xPoints, accuracy: 0.03)
        XCTAssertEqual(arranged[2].placement.xPoints, original[2].placement.xPoints, accuracy: 0.03)
        let firstGap = arranged[1].placement.xPoints
            - arranged[0].placement.xPoints - arranged[0].placement.widthPoints
        let secondGap = arranged[2].placement.xPoints
            - arranged[1].placement.xPoints - arranged[1].placement.widthPoints
        XCTAssertEqual(firstGap, secondGap, accuracy: 0.03)
    }

    func testHWPIndependentShapesMatchSizeDuplicateAndDeleteRoundTrip() async throws {
        let source = try HWPTableStructureDocument.load(fixture("V25-group", "hwp"))
        let owner = try XCTUnwrap(source.blocks.first { block in
            block.canvasObjects.contains { if case .group = $0.content { return true }; return false }
        })
        let object = try XCTUnwrap(owner.canvasObjects.first {
            if case .group = $0.content { return true }; return false
        })
        let group = try XCTUnwrap(HWPShapeEditing.target(owner: owner, object: object))
        let ungrouped = try await HWPShapeEditing.applying(.ungroup, target: group,
            source: source, drafts: source.blocks)
        var independentOwner = try XCTUnwrap(ungrouped.document.blocks.first { $0.id == owner.id })
        var shapes = independentOwner.canvasObjects.filter {
            if case .shape = $0.content { return true }; return false
        }
        XCTAssertGreaterThanOrEqual(shapes.count, 2)
        let secondTarget = try XCTUnwrap(HWPShapeEditing.target(owner: independentOwner,
            object: shapes[1]))
        let resized = try await HWPShapeEditing.applying(.update(layout(secondTarget,
            pathPoints: secondTarget.pathPoints, startArrow: secondTarget.startArrow,
            endArrow: secondTarget.endArrow, width: secondTarget.widthPoints + 30,
            height: secondTarget.heightPoints + 20)), target: secondTarget,
            source: ungrouped.document, drafts: ungrouped.document.blocks)
        independentOwner = try XCTUnwrap(resized.document.blocks.first { $0.id == owner.id })
        shapes = independentOwner.canvasObjects.filter {
            if case .shape = $0.content { return true }; return false
        }
        let originalCount = shapes.count
        let originalPositions = shapes.map { ($0.placement.xPoints, $0.placement.yPoints) }
        let matched = try await HWPShapeEditing.matchingSizes(.init(ownerID: independentOwner.id,
            objectIDs: shapes.map(\.id), match: .both), source: resized.document,
            drafts: resized.document.blocks)
        let matchedOwner = try XCTUnwrap(matched.document.blocks.first { $0.id == owner.id })
        let matchedShapes = matchedOwner.canvasObjects.filter {
            if case .shape = $0.content { return true }; return false
        }
        let reference = try XCTUnwrap(HWPShapeEditing.target(owner: matchedOwner,
            object: matchedShapes[0]))
        for (index, shape) in matchedShapes.enumerated() {
            let target = try XCTUnwrap(HWPShapeEditing.target(owner: matchedOwner, object: shape))
            XCTAssertEqual(target.widthPoints, reference.widthPoints, accuracy: 0.03)
            XCTAssertEqual(target.heightPoints, reference.heightPoints, accuracy: 0.03)
            XCTAssertEqual(target.xPoints, originalPositions[index].0, accuracy: 0.03)
            XCTAssertEqual(target.yPoints, originalPositions[index].1, accuracy: 0.03)
        }

        let duplicated = try await HWPShapeEditing.batchEditing(.init(ownerID: matchedOwner.id,
            objectIDs: Array(matchedShapes.prefix(2).map(\.id)), action: .duplicate),
            source: matched.document, drafts: matched.document.blocks)
        let duplicatedOwner = try XCTUnwrap(duplicated.document.blocks.first { $0.id == owner.id })
        let duplicatedShapes = duplicatedOwner.canvasObjects.filter {
            if case .shape = $0.content { return true }; return false
        }
        XCTAssertEqual(duplicatedShapes.count, originalCount + 2)
        let clones = Array(duplicatedShapes.suffix(2))
        let deleted = try await HWPShapeEditing.batchEditing(.init(ownerID: duplicatedOwner.id,
            objectIDs: clones.map(\.id), action: .delete), source: duplicated.document,
            drafts: duplicated.document.blocks)
        let reopened = try HWPTableStructureDocument.load(deleted.document.data)
        let remaining = try XCTUnwrap(reopened.blocks.first { $0.id == owner.id }).canvasObjects.filter {
            if case .shape = $0.content { return true }; return false
        }
        XCTAssertEqual(remaining.count, originalCount)
    }

    func testHWPXIndependentShapesDuplicateAndDeleteRoundTrip() async throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: ""))
        let initial = HWPTableStructureDocument.hwpx(package)
        let selection = HWPShapeEditing.Selection(blockID: package.blocks[0].id,
            text: "", caret: 0, width: 500)
        let firstData = try HWPShapeEditingWriter.insert(.init(selection: selection,
            kind: .rectangle, widthPoints: 100, heightPoints: 60), into: initial, ownerIndex: 0)
        let firstPackage = try HWPXDocumentPackage.load(from: firstData)
        let section = try XCTUnwrap(firstPackage.sections.first)
        let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: section.xml)
        let paragraph = (section.xml as NSString).substring(with: ranges[0])
        let run = try XCTUnwrap(HWPFormattingXML.elements(paragraph, name: "run").first)
        let rectangle = try XCTUnwrap(HWPFormattingXML.elements(paragraph, name: "rect").first)
        var changedRun = run.xml
        for (id, offset) in [("902", "12000"), ("903", "36000")] {
            var duplicate = try HWPFormattingXML.setAttribute(rectangle.xml, "id", id)
            var position = try XCTUnwrap(HWPFormattingXML.elements(duplicate, name: "pos").first?.xml)
            position = try HWPFormattingXML.setAttribute(position, "horzOffset", offset)
            duplicate = try HWPFormattingXML.replaceOrAppend(duplicate, name: "pos", replacement: position)
            changedRun = try HWPFormattingXML.append(duplicate, to: changedRun)
        }
        let changedParagraph = (paragraph as NSString).replacingCharacters(in: run.range, with: changedRun)
        let changedSection = (section.xml as NSString).replacingCharacters(in: ranges[0], with: changedParagraph)
        let data = try HWPXEditingArchive(data: firstPackage.sourceData).repack(
            replacing: [section.path: Data(changedSection.utf8)])
        let source = try HWPTableStructureDocument.load(data)
        let owner = source.blocks[0]
        let shapes = owner.canvasObjects.filter { if case .shape = $0.content { return true }; return false }
        let highestZ = shapes.map(\.placement.zOrder).max() ?? 0

        let duplicated = try await HWPShapeEditing.batchEditing(.init(ownerID: owner.id,
            objectIDs: Array(shapes.prefix(2).map(\.id)), action: .duplicate), source: source,
            drafts: source.blocks)
        let duplicatedOwner = duplicated.document.blocks[0]
        let duplicatedShapes = duplicatedOwner.canvasObjects.filter {
            if case .shape = $0.content { return true }; return false
        }
        XCTAssertEqual(duplicatedShapes.count, 5)
        let clones = duplicatedShapes.filter { $0.placement.zOrder > highestZ }
        XCTAssertEqual(clones.count, 2)
        for clone in clones {
            XCTAssertTrue(shapes.prefix(2).contains { original in
                abs(clone.placement.xPoints - original.placement.xPoints - 12) < 0.03
                    && abs(clone.placement.yPoints - original.placement.yPoints - 12) < 0.03
                    && abs(clone.placement.widthPoints - original.placement.widthPoints) < 0.03
            })
        }

        let deleted = try await HWPShapeEditing.batchEditing(.init(ownerID: duplicatedOwner.id,
            objectIDs: clones.map(\.id), action: .delete), source: duplicated.document,
            drafts: duplicated.document.blocks)
        let reopened = try HWPTableStructureDocument.load(deleted.document.data)
        XCTAssertEqual(reopened.blocks[0].canvasObjects.filter {
            if case .shape = $0.content { return true }; return false
        }.count, 3)
    }

    func testHWPShapeFacingPageAlignmentAndFlipRoundTrip() async throws {
        let source = try HWPTableStructureDocument.load(fixture("V32-polygon", "hwp"))
        let pair = try XCTUnwrap(source.blocks.compactMap { owner in
            owner.canvasObjects.first(where: { if case .shape = $0.content { return true }; return false })
                .map { (owner, $0) }
        }.first)
        let aligned = try await HWPShapeEditing.arranging(.init(ownerID: pair.0.id,
            objectIDs: [pair.1.id], arrangement: .alignInside), source: source,
            drafts: source.blocks)
        let alignedOwner = try XCTUnwrap(aligned.document.blocks.first { $0.id == pair.0.id })
        let alignedObject = try XCTUnwrap(alignedOwner.canvasObjects.first { $0.id == pair.1.id })
        let alignedTarget = try XCTUnwrap(HWPShapeEditing.target(owner: alignedOwner,
            object: alignedObject))
        XCTAssertFalse(alignedTarget.isInline)
        XCTAssertEqual(alignedTarget.horizontalReference, .page)
        XCTAssertEqual(alignedTarget.horizontalAlignment, .inside)

        let flipped = try await HWPShapeEditing.flipping(.init(ownerID: alignedOwner.id,
            objectIDs: [alignedObject.id], flip: .horizontal), source: aligned.document,
            drafts: aligned.document.blocks)
        let reopened = try HWPTableStructureDocument.load(flipped.document.data)
        let reopenedOwner = try XCTUnwrap(reopened.blocks.first { $0.id == pair.0.id })
        let reopenedObject = try XCTUnwrap(reopenedOwner.canvasObjects.first { $0.id == pair.1.id })
        let reopenedTarget = try XCTUnwrap(HWPShapeEditing.target(owner: reopenedOwner,
            object: reopenedObject))
        XCTAssertEqual(reopenedTarget.horizontalAlignment, .inside)
        XCTAssertTrue(reopenedTarget.flipHorizontal)
        XCTAssertFalse(reopenedTarget.flipVertical)
    }

    func testHWPXShapeFacingPageAlignmentAndFlipRoundTrip() async throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: ""))
        let initial = HWPTableStructureDocument.hwpx(package)
        let selection = HWPShapeEditing.Selection(blockID: package.blocks[0].id,
            text: "", caret: 0, width: 500)
        let data = try HWPShapeEditingWriter.insert(.init(selection: selection,
            kind: .polygon, widthPoints: 120, heightPoints: 80), into: initial, ownerIndex: 0)
        let source = try HWPTableStructureDocument.load(data)
        let owner = try XCTUnwrap(source.blocks.first { !$0.canvasObjects.isEmpty })
        let object = try XCTUnwrap(owner.canvasObjects.first)
        let aligned = try await HWPShapeEditing.arranging(.init(ownerID: owner.id,
            objectIDs: [object.id], arrangement: .alignOutside), source: source,
            drafts: source.blocks)
        let alignedOwner = try XCTUnwrap(aligned.document.blocks.first { $0.id == owner.id })
        let alignedObject = try XCTUnwrap(alignedOwner.canvasObjects.first { $0.id == object.id })
        let vertical = try await HWPShapeEditing.flipping(.init(ownerID: alignedOwner.id,
            objectIDs: [alignedObject.id], flip: .vertical), source: aligned.document,
            drafts: aligned.document.blocks)
        let reopened = try HWPTableStructureDocument.load(vertical.document.data)
        let reopenedOwner = try XCTUnwrap(reopened.blocks.first { $0.id == owner.id })
        let reopenedObject = try XCTUnwrap(reopenedOwner.canvasObjects.first { $0.id == object.id })
        let target = try XCTUnwrap(HWPShapeEditing.target(owner: reopenedOwner,
            object: reopenedObject))
        XCTAssertFalse(target.isInline)
        XCTAssertEqual(target.horizontalReference, .page)
        XCTAssertEqual(target.horizontalAlignment, .outside)
        XCTAssertFalse(target.flipHorizontal)
        XCTAssertTrue(target.flipVertical)
    }

    func testDirectShapeMoveAndCornerResizeLayout() throws {
        let source = try HWPTableStructureDocument.load(fixture("V32-polygon", "hwp"))
        let owner = try XCTUnwrap(source.blocks.first { !$0.canvasObjects.isEmpty })
        let object = try XCTUnwrap(owner.canvasObjects.first)
        let target = try XCTUnwrap(HWPShapeEditing.target(owner: owner, object: object))

        let moved = try XCTUnwrap(HWPShapeEditing.directLayout(
            .move(deltaX: 17, deltaY: -9), target: target))
        XCTAssertEqual(moved.xPoints, target.xPoints + 17, accuracy: 0.001)
        XCTAssertEqual(moved.yPoints, target.yPoints - 9, accuracy: 0.001)
        XCTAssertEqual(moved.widthPoints, target.widthPoints, accuracy: 0.001)
        XCTAssertEqual(moved.heightPoints, target.heightPoints, accuracy: 0.001)

        let resized = try XCTUnwrap(HWPShapeEditing.directLayout(
            .resize(anchor: .topLeading, deltaX: 12, deltaY: 7), target: target))
        XCTAssertEqual(resized.xPoints, target.xPoints + 12, accuracy: 0.001)
        XCTAssertEqual(resized.yPoints, target.yPoints + 7, accuracy: 0.001)
        XCTAssertEqual(resized.widthPoints, target.widthPoints - 12, accuracy: 0.001)
        XCTAssertEqual(resized.heightPoints, target.heightPoints - 7, accuracy: 0.001)

        let minimum = try XCTUnwrap(HWPShapeEditing.directLayout(
            .resize(anchor: .bottomTrailing, deltaX: -10_000, deltaY: -10_000),
            target: target))
        XCTAssertEqual(minimum.widthPoints, 20, accuracy: 0.001)
        XCTAssertEqual(minimum.heightPoints, 8, accuracy: 0.001)

        let quarterTurn = try XCTUnwrap(HWPShapeEditing.directResizeGeometry(
            anchor: .bottomTrailing, deltaX: 0, deltaY: 10,
            xPoints: 100, yPoints: 200, widthPoints: 100, heightPoints: 50,
            rotationDegrees: 90, flipHorizontal: false, flipVertical: false,
            minimumHeight: 8))
        XCTAssertEqual(quarterTurn.xPoints, 95, accuracy: 0.001)
        XCTAssertEqual(quarterTurn.yPoints, 205, accuracy: 0.001)
        XCTAssertEqual(quarterTurn.widthPoints, 110, accuracy: 0.001)
        XCTAssertEqual(quarterTurn.heightPoints, 50, accuracy: 0.001)
        XCTAssertEqual(quarterTurn.localOffsetX, 0, accuracy: 0.001)
        XCTAssertEqual(quarterTurn.localOffsetY, 0, accuracy: 0.001)

        let flipped = try XCTUnwrap(HWPShapeEditing.directResizeGeometry(
            anchor: .bottomTrailing, deltaX: -10, deltaY: 0,
            xPoints: 100, yPoints: 200, widthPoints: 100, heightPoints: 50,
            rotationDegrees: 0, flipHorizontal: true, flipVertical: false,
            minimumHeight: 8))
        XCTAssertEqual(flipped.xPoints, 90, accuracy: 0.001)
        XCTAssertEqual(flipped.yPoints, 200, accuracy: 0.001)
        XCTAssertEqual(flipped.widthPoints, 110, accuracy: 0.001)
        XCTAssertEqual(flipped.heightPoints, 50, accuracy: 0.001)
    }

    func testDirectShapeRotationNormalizesAndPreservesGeometry() throws {
        let source = try HWPTableStructureDocument.load(fixture("V32-polygon", "hwp"))
        let owner = try XCTUnwrap(source.blocks.first { !$0.canvasObjects.isEmpty })
        let object = try XCTUnwrap(owner.canvasObjects.first)
        let target = try XCTUnwrap(HWPShapeEditing.target(owner: owner, object: object))

        let rotated = try XCTUnwrap(HWPShapeEditing.directLayout(
            .rotate(deltaDegrees: 405), target: target))
        let expected = (target.rotationDegrees + 405).truncatingRemainder(dividingBy: 360)
        XCTAssertEqual(rotated.rotationDegrees, expected, accuracy: 0.001)
        XCTAssertEqual(rotated.xPoints, target.xPoints, accuracy: 0.001)
        XCTAssertEqual(rotated.yPoints, target.yPoints, accuracy: 0.001)
        XCTAssertEqual(rotated.widthPoints, target.widthPoints, accuracy: 0.001)
        XCTAssertEqual(rotated.heightPoints, target.heightPoints, accuracy: 0.001)

        let backwards = try XCTUnwrap(HWPShapeEditing.directLayout(
            .rotate(deltaDegrees: -target.rotationDegrees - 25), target: target))
        XCTAssertEqual(backwards.rotationDegrees, 335, accuracy: 0.001)
    }

    func testHWPXDirectShapeMoveResizeRoundTrip() async throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: ""))
        let initial = HWPTableStructureDocument.hwpx(package)
        let selection = HWPShapeEditing.Selection(blockID: package.blocks[0].id,
            text: "", caret: 0, width: 500)
        let data = try HWPShapeEditingWriter.insert(.init(selection: selection,
            kind: .rectangle, widthPoints: 120, heightPoints: 80), into: initial, ownerIndex: 0)
        let source = try HWPTableStructureDocument.load(data)
        let owner = try XCTUnwrap(source.blocks.first { !$0.canvasObjects.isEmpty })
        let object = try XCTUnwrap(owner.canvasObjects.first)
        let target = try XCTUnwrap(HWPShapeEditing.target(owner: owner, object: object))
        let movedLayout = try XCTUnwrap(HWPShapeEditing.directLayout(
            .move(deltaX: 24, deltaY: 13), target: target))
        let moved = try await HWPShapeEditing.applying(.update(movedLayout), target: target,
            source: source, drafts: source.blocks)
        let movedOwner = try XCTUnwrap(moved.document.blocks.first { $0.id == owner.id })
        let movedObject = try XCTUnwrap(movedOwner.canvasObjects.first { $0.id == object.id })
        let movedTarget = try XCTUnwrap(HWPShapeEditing.target(owner: movedOwner,
            object: movedObject))
        let resizedLayout = try XCTUnwrap(HWPShapeEditing.directLayout(
            .resize(anchor: .bottomTrailing, deltaX: 31, deltaY: 19),
            target: movedTarget))
        let resized = try await HWPShapeEditing.applying(.update(resizedLayout),
            target: movedTarget, source: moved.document, drafts: moved.document.blocks)
        let resizedOwner = try XCTUnwrap(resized.document.blocks.first { $0.id == owner.id })
        let resizedObject = try XCTUnwrap(resizedOwner.canvasObjects.first { $0.id == object.id })
        let resizedTarget = try XCTUnwrap(HWPShapeEditing.target(owner: resizedOwner,
            object: resizedObject))
        let rotatedLayout = try XCTUnwrap(HWPShapeEditing.directLayout(
            .rotate(deltaDegrees: 47), target: resizedTarget))
        let rotated = try await HWPShapeEditing.applying(.update(rotatedLayout),
            target: resizedTarget, source: resized.document, drafts: resized.document.blocks)
        let reopened = try HWPTableStructureDocument.load(rotated.document.data)
        let reopenedOwner = try XCTUnwrap(reopened.blocks.first { $0.id == owner.id })
        let reopenedObject = try XCTUnwrap(reopenedOwner.canvasObjects.first { $0.id == object.id })
        let reopenedTarget = try XCTUnwrap(HWPShapeEditing.target(owner: reopenedOwner,
            object: reopenedObject))
        XCTAssertEqual(reopenedTarget.xPoints, target.xPoints + 24, accuracy: 0.03)
        XCTAssertEqual(reopenedTarget.yPoints, target.yPoints + 13, accuracy: 0.03)
        XCTAssertEqual(reopenedTarget.widthPoints, target.widthPoints + 31, accuracy: 0.03)
        XCTAssertEqual(reopenedTarget.heightPoints, target.heightPoints + 19, accuracy: 0.03)
        XCTAssertEqual(reopenedTarget.rotationDegrees,
            (target.rotationDegrees + 47).truncatingRemainder(dividingBy: 360), accuracy: 0.03)

        let rotatedResizeLayout = try XCTUnwrap(HWPShapeEditing.directLayout(
            .resize(anchor: .topTrailing, deltaX: 11, deltaY: 23),
            target: reopenedTarget))
        let rotatedResize = try await HWPShapeEditing.applying(.update(rotatedResizeLayout),
            target: reopenedTarget, source: reopened, drafts: reopened.blocks)
        let finalDocument = try HWPTableStructureDocument.load(rotatedResize.document.data)
        let finalOwner = try XCTUnwrap(finalDocument.blocks.first { $0.id == owner.id })
        let finalObject = try XCTUnwrap(finalOwner.canvasObjects.first { $0.id == object.id })
        let finalTarget = try XCTUnwrap(HWPShapeEditing.target(owner: finalOwner,
            object: finalObject))
        XCTAssertEqual(finalTarget.xPoints, rotatedResizeLayout.xPoints, accuracy: 0.03)
        XCTAssertEqual(finalTarget.yPoints, rotatedResizeLayout.yPoints, accuracy: 0.03)
        XCTAssertEqual(finalTarget.widthPoints, rotatedResizeLayout.widthPoints, accuracy: 0.03)
        XCTAssertEqual(finalTarget.heightPoints, rotatedResizeLayout.heightPoints, accuracy: 0.03)
        XCTAssertEqual(finalTarget.rotationDegrees, reopenedTarget.rotationDegrees, accuracy: 0.03)
    }

    func testViewModelGroupShapesUndoRedoAndSave() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwp")
        try fixture("V25-group", "hwp").write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let owner = try XCTUnwrap(model.blocks.first { block in
            block.canvasObjects.contains { if case .group = $0.content { return true }; return false }
        })
        let object = try XCTUnwrap(owner.canvasObjects.first {
            if case .group = $0.content { return true }; return false
        })
        let target = try XCTUnwrap(HWPShapeEditing.target(owner: owner, object: object))
        _ = try await model.editShape(.ungroup, target: target)
        let independent = model.blocks
        let independentOwner = try XCTUnwrap(independent.first { $0.id == owner.id })
        let shapes = independentOwner.canvasObjects.filter {
            if case .shape = $0.content { return true }
            return false
        }
        _ = try await model.groupShapes(.init(ownerID: owner.id, objectIDs: shapes.map(\.id)))
        let grouped = model.blocks
        XCTAssertTrue(grouped.flatMap(\.canvasObjects).contains {
            if case .group = $0.content { return true }
            return false
        })
        model.undo(); XCTAssertEqual(model.blocks, independent)
        model.redo(); XCTAssertEqual(model.blocks, grouped)
        await model.save()
        XCTAssertNil(model.errorDescription)
        XCTAssertFalse(model.hasUnsavedChanges)
        let reopened = try HWPTableStructureDocument.load(Data(contentsOf: url))
        XCTAssertTrue(reopened.blocks.flatMap(\.canvasObjects).contains {
            if case .group = $0.content { return true }
            return false
        })
    }

    func testViewModelArrangeShapesUndoRedoAndSave() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwp")
        try fixture("V25-group", "hwp").write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let owner = try XCTUnwrap(model.blocks.first { block in
            block.canvasObjects.contains { if case .group = $0.content { return true }; return false }
        })
        let object = try XCTUnwrap(owner.canvasObjects.first {
            if case .group = $0.content { return true }; return false
        })
        let group = try XCTUnwrap(HWPShapeEditing.target(owner: owner, object: object))
        _ = try await model.editShape(.ungroup, target: group)
        let before = model.blocks
        let independentOwner = try XCTUnwrap(before.first { $0.id == owner.id })
        let shapes = independentOwner.canvasObjects.filter {
            if case .shape = $0.content { return true }
            return false
        }

        _ = try await model.arrangeShapes(.init(ownerID: owner.id,
            objectIDs: shapes.map(\.id), arrangement: .alignLeft))
        let aligned = model.blocks
        XCTAssertNotEqual(aligned, before)
        model.undo(); XCTAssertEqual(model.blocks, before)
        model.redo(); XCTAssertEqual(model.blocks, aligned)
        await model.save()
        XCTAssertNil(model.errorDescription)
        XCTAssertFalse(model.hasUnsavedChanges)
        let reopened = try HWPTableStructureDocument.load(Data(contentsOf: url))
        let reopenedOwner = try XCTUnwrap(reopened.blocks.first { $0.id == owner.id })
        let targets = shapes.compactMap { original in
            reopenedOwner.canvasObjects.first(where: { $0.id == original.id }).flatMap {
                HWPShapeEditing.target(owner: reopenedOwner, object: $0)
            }
        }
        XCTAssertEqual(targets.count, shapes.count)
        let left = try XCTUnwrap(targets.first?.xPoints)
        XCTAssertTrue(targets.allSatisfy { abs($0.xPoints - left) < 0.03 })
    }

    func testViewModelBatchDuplicateUndoRedoAndSave() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwp")
        try fixture("V25-group", "hwp").write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let owner = try XCTUnwrap(model.blocks.first { block in
            block.canvasObjects.contains { if case .group = $0.content { return true }; return false }
        })
        let object = try XCTUnwrap(owner.canvasObjects.first {
            if case .group = $0.content { return true }; return false
        })
        let group = try XCTUnwrap(HWPShapeEditing.target(owner: owner, object: object))
        _ = try await model.editShape(.ungroup, target: group)
        let before = model.blocks
        let independentOwner = try XCTUnwrap(before.first { $0.id == owner.id })
        let shapes = independentOwner.canvasObjects.filter {
            if case .shape = $0.content { return true }; return false
        }
        _ = try await model.batchEditShapes(.init(ownerID: owner.id,
            objectIDs: Array(shapes.prefix(2).map(\.id)), action: .duplicate))
        let duplicated = model.blocks
        XCTAssertNotEqual(duplicated, before)
        model.undo(); XCTAssertEqual(model.blocks, before)
        model.redo(); XCTAssertEqual(model.blocks, duplicated)
        await model.save()
        XCTAssertNil(model.errorDescription)
        XCTAssertFalse(model.hasUnsavedChanges)
        let reopened = try HWPTableStructureDocument.load(Data(contentsOf: url))
        let reopenedOwner = try XCTUnwrap(reopened.blocks.first { $0.id == owner.id })
        XCTAssertEqual(reopenedOwner.canvasObjects.filter {
            if case .shape = $0.content { return true }; return false
        }.count, shapes.count + 2)
    }

    func testViewModelShapeFlipUndoRedoAndSave() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwp")
        try fixture("V32-polygon", "hwp").write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let owner = try XCTUnwrap(model.blocks.first { !$0.canvasObjects.isEmpty })
        let object = try XCTUnwrap(owner.canvasObjects.first)
        let before = model.blocks
        _ = try await model.flipShapes(.init(ownerID: owner.id,
            objectIDs: [object.id], flip: .horizontal))
        let flipped = model.blocks
        XCTAssertNotEqual(flipped, before)
        model.undo(); XCTAssertEqual(model.blocks, before)
        model.redo(); XCTAssertEqual(model.blocks, flipped)
        await model.save()
        XCTAssertNil(model.errorDescription)
        XCTAssertFalse(model.hasUnsavedChanges)
        let reopened = try HWPTableStructureDocument.load(Data(contentsOf: url))
        let reopenedOwner = try XCTUnwrap(reopened.blocks.first { $0.id == owner.id })
        let reopenedObject = try XCTUnwrap(reopenedOwner.canvasObjects.first { $0.id == object.id })
        XCTAssertTrue(try XCTUnwrap(HWPShapeEditing.target(owner: reopenedOwner,
            object: reopenedObject)).flipHorizontal)
    }

    func testRejectsInvalidShapeDimensionsAndUnsupportedObject() throws {
        XCTAssertFalse(HWPShapeEditing.Request(selection: .init(blockID: "x", text: "", caret: 0, width: 100),
            kind: .line, widthPoints: 10, heightPoints: 30).isValid)
        XCTAssertFalse(HWPShapeEditing.Layout(xPoints: .infinity, yPoints: 0,
            widthPoints: 100, heightPoints: 60, zOrder: 0, rotationDegrees: 0,
            strokeColorRGB: 0, strokeWidthPoints: 1, strokeStyle: 1,
            fillColorRGB: nil, shadow: nil).isValid)
    }

    private func fixture(_ name: String, _ ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "HWPXViewerFixtures")))
    }

    private func layout(_ target: HWPShapeEditing.Target,
                        pathPoints: [HWPShapeEditing.PathPoint], startArrow: Int, endArrow: Int,
                        x: Double? = nil, y: Double? = nil,
                        width: Double? = nil, height: Double? = nil,
                        stroke: UInt32? = nil, fill: UInt32?? = nil)
        -> HWPShapeEditing.Layout {
        HWPShapeEditing.Layout(xPoints: x ?? target.xPoints, yPoints: y ?? target.yPoints,
            widthPoints: width ?? target.widthPoints, heightPoints: height ?? target.heightPoints,
            zOrder: target.zOrder, rotationDegrees: target.rotationDegrees,
            flipHorizontal: target.flipHorizontal, flipVertical: target.flipVertical,
            strokeColorRGB: stroke ?? target.strokeColorRGB,
            strokeWidthPoints: max(target.strokeWidthPoints, 0.25),
            strokeStyle: target.strokeStyle, fillColorRGB: fill ?? target.fillColorRGB,
            shadow: target.shadow, isInline: target.isInline,
            horizontalReference: target.horizontalReference,
            verticalReference: target.verticalReference,
            horizontalAlignment: target.horizontalAlignment,
            verticalAlignment: target.verticalAlignment, wrap: target.wrap,
            marginLeftPoints: target.marginLeftPoints,
            marginRightPoints: target.marginRightPoints,
            marginTopPoints: target.marginTopPoints,
            marginBottomPoints: target.marginBottomPoints,
            pathPoints: pathPoints, startArrow: startArrow, endArrow: endArrow)
    }
}
