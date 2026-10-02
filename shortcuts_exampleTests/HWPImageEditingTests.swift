import RivoDocumentEngine
import XCTest
import UIKit
@testable import shortcuts_example

@MainActor
final class HWPImageEditingTests: XCTestCase {
    func testHWPXImageInsertResizeDeleteRoundTrip() async throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "앞뒤"))
        let source = HWPTableStructureDocument.hwpx(package)
        let selection = try XCTUnwrap(HWPImageEditing.selection(blocks: package.blocks,
            selectedID: package.blocks[0].id, range: NSRange(location: 1, length: 0), layouts: package.pageLayouts))
        let image = try HWPImageEditing.normalize(Self.png)
        let size = image.displaySize(maxWidth: selection.width)
        let inserted = try await HWPImageEditing.inserting(.init(selection: selection, image: image,
            widthPoints: size.width, heightPoints: size.height), source: source, drafts: package.blocks)

        XCTAssertEqual(inserted.document.blocks.map(\.text), ["앞", "", "뒤"])
        let owner = inserted.document.blocks[1]
        let object = try XCTUnwrap(owner.canvasObjects.first)
        guard case .image(let parsed) = object.content else { return XCTFail("Inserted object is not an image") }
        XCTAssertEqual(parsed.data, image.data)
        XCTAssertEqual(object.placement.widthPoints, size.width, accuracy: 0.02)

        let target = try XCTUnwrap(HWPImageEditing.target(owner: owner, object: object))
        XCTAssertTrue(target.isInline)
        XCTAssertTrue(target.supportsTransparency)
        let inlineMove = try XCTUnwrap(HWPImageEditing.directUpdate(
            .move(deltaX: 6, deltaY: 4), target: target))
        let inlineMoved = try await HWPImageEditing.applying(.update(inlineMove.crop,
            inlineMove.dimensions, inlineMove.presentation, inlineMove.appearance),
            target: target, source: inserted.document, drafts: inserted.document.blocks)
        let inlineOwner = inlineMoved.document.blocks[1]
        let inlineObject = try XCTUnwrap(inlineOwner.canvasObjects.first)
        let inlineTarget = try XCTUnwrap(HWPImageEditing.target(owner: inlineOwner, object: inlineObject))
        XCTAssertEqual(inlineTarget.xPoints, target.xPoints + 6, accuracy: 0.03)
        XCTAssertEqual(inlineTarget.yPoints, target.yPoints + 4, accuracy: 0.03)
        let half = try XCTUnwrap(HWPImageEditing.Crop(rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)))
        let cropped = try await HWPImageEditing.applying(
            .crop(half, inlineTarget.fittedDimensions(for: half, width: 120)),
            target: inlineTarget, source: inlineMoved.document, drafts: inlineMoved.document.blocks)
        let croppedOwner = cropped.document.blocks[1]
        let croppedObject = try XCTUnwrap(croppedOwner.canvasObjects.first)
        guard case .image(let croppedImage) = croppedObject.content else { return XCTFail("Cropped object is not an image") }
        XCTAssertEqual(try XCTUnwrap(croppedImage.cropRect).minX, 0.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(croppedImage.cropRect).width, 0.5, accuracy: 0.001)
        XCTAssertEqual(croppedObject.placement.widthPoints, 120, accuracy: 0.02)
        XCTAssertEqual(croppedObject.placement.heightPoints, 120, accuracy: 0.02)

        let croppedTarget = try XCTUnwrap(HWPImageEditing.target(owner: croppedOwner, object: croppedObject))
        let restored = try await HWPImageEditing.applying(
            .crop(.full, croppedTarget.fittedDimensions(for: .full, width: 120)),
            target: croppedTarget, source: cropped.document, drafts: cropped.document.blocks)
        let restoredOwner = restored.document.blocks[1]
        let restoredObject = try XCTUnwrap(restoredOwner.canvasObjects.first)
        guard case .image(let restoredImage) = restoredObject.content else { return XCTFail("Restored object is not an image") }
        XCTAssertEqual(try XCTUnwrap(restoredImage.cropRect).width, 1, accuracy: 0.001)
        XCTAssertEqual(restoredObject.placement.heightPoints, 60, accuracy: 0.02)

        let restoredTarget = try XCTUnwrap(HWPImageEditing.target(owner: restoredOwner, object: restoredObject))
        let presented = try await HWPImageEditing.applying(.update(.full,
            .init(widthPoints: 120, heightPoints: 60), presentation(restoredTarget,
                rotation: 90, flipHorizontal: true, wrap: .inFrontOfText),
            appearance(color: 0x1F5EA8, width: 2.5, style: 2, brightness: 18, contrast: -24,
                effect: .grayscale, transparency: 37)),
            target: restoredTarget, source: restored.document, drafts: restored.document.blocks)
        let presentedOwner = presented.document.blocks[1]
        let presentedObject = try XCTUnwrap(presentedOwner.canvasObjects.first)
        let presentedTarget = try XCTUnwrap(HWPImageEditing.target(owner: presentedOwner, object: presentedObject))
        XCTAssertEqual(presentedTarget.rotationDegrees, 90, accuracy: 0.02)
        XCTAssertTrue(presentedTarget.flipHorizontal)
        XCTAssertFalse(presentedTarget.isInline)
        XCTAssertEqual(presentedTarget.wrap, .inFrontOfText)
        XCTAssertEqual(presentedTarget.horizontalReference, .page)
        XCTAssertEqual(presentedTarget.horizontalAlignment, .center)
        XCTAssertEqual(presentedTarget.marginLeftPoints, 6, accuracy: 0.02)
        XCTAssertEqual(presentedTarget.borderStroke?.colorRGB, 0x1F5EA8)
        XCTAssertEqual(try XCTUnwrap(presentedTarget.borderStroke).widthPoints, 2.5, accuracy: 0.02)
        XCTAssertEqual(presentedTarget.borderStroke?.style, 2)
        XCTAssertEqual(presentedTarget.brightness, 18)
        XCTAssertEqual(presentedTarget.contrast, -24)
        XCTAssertEqual(presentedTarget.effect, .grayscale)
        XCTAssertEqual(presentedTarget.transparencyPercent, 37)

        let cleared = try await HWPImageEditing.applying(.update(.full,
            .init(widthPoints: 120, heightPoints: 60), presentedTarget.presentation,
            .init(borderStroke: nil, brightness: 0, contrast: 0)),
            target: presentedTarget, source: presented.document, drafts: presented.document.blocks)
        let clearedOwner = cleared.document.blocks[1]
        let clearedObject = try XCTUnwrap(clearedOwner.canvasObjects.first)
        let clearedTarget = try XCTUnwrap(HWPImageEditing.target(owner: clearedOwner, object: clearedObject))
        XCTAssertNil(clearedTarget.borderStroke)
        XCTAssertEqual(clearedTarget.brightness, 0)
        XCTAssertEqual(clearedTarget.contrast, 0)
        XCTAssertEqual(clearedTarget.effect, .original)
        XCTAssertEqual(clearedTarget.transparencyPercent, 0)

        let movedUpdate = try XCTUnwrap(HWPImageEditing.directUpdate(
            .move(deltaX: 14, deltaY: 9), target: clearedTarget))
        let moved = try await HWPImageEditing.applying(.update(movedUpdate.crop,
            movedUpdate.dimensions, movedUpdate.presentation, movedUpdate.appearance),
            target: clearedTarget, source: cleared.document, drafts: cleared.document.blocks)
        let movedOwner = moved.document.blocks[1]
        let movedObject = try XCTUnwrap(movedOwner.canvasObjects.first)
        let movedTarget = try XCTUnwrap(HWPImageEditing.target(owner: movedOwner, object: movedObject))
        XCTAssertEqual(movedTarget.xPoints, clearedTarget.xPoints + 14, accuracy: 0.03)
        XCTAssertEqual(movedTarget.yPoints, clearedTarget.yPoints + 9, accuracy: 0.03)
        let topLeading = try XCTUnwrap(HWPImageEditing.directUpdate(
            .resize(anchor: .topLeading, deltaX: 5, deltaY: 4), target: movedTarget))
        let topLeadingGeometry = try XCTUnwrap(HWPShapeEditing.directResizeGeometry(
            anchor: .topLeading, deltaX: 5, deltaY: 4,
            xPoints: movedTarget.xPoints, yPoints: movedTarget.yPoints,
            widthPoints: movedTarget.widthPoints, heightPoints: movedTarget.heightPoints,
            rotationDegrees: movedTarget.rotationDegrees,
            flipHorizontal: movedTarget.flipHorizontal,
            flipVertical: movedTarget.flipVertical, minimumHeight: 20))
        XCTAssertEqual(topLeading.presentation.xPoints, topLeadingGeometry.xPoints, accuracy: 0.001)
        XCTAssertEqual(topLeading.presentation.yPoints, topLeadingGeometry.yPoints, accuracy: 0.001)
        XCTAssertEqual(topLeading.dimensions.widthPoints, topLeadingGeometry.widthPoints, accuracy: 0.001)
        XCTAssertEqual(topLeading.dimensions.heightPoints, topLeadingGeometry.heightPoints, accuracy: 0.001)
        XCTAssertNil(HWPImageEditing.directUpdate(.move(deltaX: .nan, deltaY: 0),
            target: movedTarget))

        let handleResize = try XCTUnwrap(HWPImageEditing.directUpdate(
            .resize(anchor: .bottomTrailing, deltaX: 24, deltaY: 16), target: movedTarget))
        let handleResized = try await HWPImageEditing.applying(.update(handleResize.crop,
            handleResize.dimensions, handleResize.presentation, handleResize.appearance),
            target: movedTarget, source: moved.document, drafts: moved.document.blocks)
        let handleOwner = handleResized.document.blocks[1]
        let handleObject = try XCTUnwrap(handleOwner.canvasObjects.first)
        let handleTarget = try XCTUnwrap(HWPImageEditing.target(owner: handleOwner, object: handleObject))
        XCTAssertEqual(handleTarget.xPoints, handleResize.presentation.xPoints, accuracy: 0.03)
        XCTAssertEqual(handleTarget.yPoints, handleResize.presentation.yPoints, accuracy: 0.03)
        XCTAssertEqual(handleTarget.widthPoints, handleResize.dimensions.widthPoints, accuracy: 0.03)
        XCTAssertEqual(handleTarget.heightPoints, handleResize.dimensions.heightPoints, accuracy: 0.03)

        let handleRotation = try XCTUnwrap(HWPImageEditing.directUpdate(
            .rotate(deltaDegrees: 47), target: handleTarget))
        let handleRotated = try await HWPImageEditing.applying(.update(handleRotation.crop,
            handleRotation.dimensions, handleRotation.presentation, handleRotation.appearance),
            target: handleTarget, source: handleResized.document, drafts: handleResized.document.blocks)
        let rotatedOwner = handleRotated.document.blocks[1]
        let rotatedObject = try XCTUnwrap(rotatedOwner.canvasObjects.first)
        let rotatedTarget = try XCTUnwrap(HWPImageEditing.target(owner: rotatedOwner, object: rotatedObject))
        XCTAssertEqual(rotatedTarget.rotationDegrees,
            (handleTarget.rotationDegrees + 47).truncatingRemainder(dividingBy: 360), accuracy: 0.03)

        let axisUpdate = try XCTUnwrap(HWPImageEditing.directUpdate(
            .resize(anchor: .topTrailing, deltaX: 15, deltaY: -9), target: rotatedTarget))
        let axisResized = try await HWPImageEditing.applying(.update(axisUpdate.crop,
            axisUpdate.dimensions, axisUpdate.presentation, axisUpdate.appearance),
            target: rotatedTarget, source: handleRotated.document,
            drafts: handleRotated.document.blocks)
        let axisDocument = try HWPTableStructureDocument.load(axisResized.document.data)
        let axisOwner = try XCTUnwrap(axisDocument.blocks.first { $0.id == rotatedOwner.id })
        let axisObject = try XCTUnwrap(axisOwner.canvasObjects.first { $0.id == rotatedObject.id })
        let axisTarget = try XCTUnwrap(HWPImageEditing.target(owner: axisOwner, object: axisObject))
        XCTAssertEqual(axisTarget.xPoints, axisUpdate.presentation.xPoints, accuracy: 0.03)
        XCTAssertEqual(axisTarget.yPoints, axisUpdate.presentation.yPoints, accuracy: 0.03)
        XCTAssertEqual(axisTarget.widthPoints, axisUpdate.dimensions.widthPoints, accuracy: 0.03)
        XCTAssertEqual(axisTarget.heightPoints, axisUpdate.dimensions.heightPoints, accuracy: 0.03)
        XCTAssertEqual(axisTarget.rotationDegrees, rotatedTarget.rotationDegrees, accuracy: 0.03)
        XCTAssertTrue(axisTarget.flipHorizontal)

        let resized = try await HWPImageEditing.applying(.resize(.init(widthPoints: 144, heightPoints: 96)),
            target: axisTarget, source: axisDocument, drafts: axisDocument.blocks)
        let resizedOwner = try XCTUnwrap(resized.document.blocks.first { $0.id == axisOwner.id })
        let resizedObject = try XCTUnwrap(resizedOwner.canvasObjects.first)
        XCTAssertEqual(resizedObject.placement.widthPoints, 144, accuracy: 0.02)
        XCTAssertEqual(resizedObject.placement.heightPoints, 96, accuracy: 0.02)

        let resizedTarget = try XCTUnwrap(HWPImageEditing.target(owner: resizedOwner, object: resizedObject))
        let deleted = try await HWPImageEditing.applying(.delete, target: resizedTarget,
            source: resized.document, drafts: resized.document.blocks)
        XCTAssertTrue(deleted.document.blocks[1].canvasObjects.isEmpty)
        XCTAssertEqual(deleted.document.blocks.map(\.text), ["앞", "", "뒤"])
        _ = try HWPXDocumentPackage.load(from: deleted.document.data)
    }

    func testRejectsNonImageAndOversizedDimensions() throws {
        XCTAssertThrowsError(try HWPImageEditing.normalize(Data("text".utf8)))
        XCTAssertFalse(HWPImageEditing.Dimensions(widthPoints: 10, heightPoints: 100).isValid)
        XCTAssertFalse(HWPImageEditing.Dimensions(widthPoints: 100, heightPoints: .infinity).isValid)
        XCTAssertFalse(HWPImageEditing.Appearance(borderStroke: nil,
            brightness: 101, contrast: 0).isValid)
        XCTAssertFalse(HWPImageEditing.Appearance(borderStroke: nil,
            brightness: 0, contrast: 0, effect: .original, transparencyPercent: 101).isValid)
    }

    func testViewModelImageCropUndoRedoAndSave() async throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "그림"))
        let source = HWPTableStructureDocument.hwpx(package)
        let selection = try XCTUnwrap(HWPImageEditing.selection(blocks: package.blocks,
            selectedID: package.blocks[0].id, range: NSRange(location: 1, length: 0), layouts: package.pageLayouts))
        let image = try HWPImageEditing.normalize(Self.png)
        let size = image.displaySize(maxWidth: selection.width)
        let inserted = try await HWPImageEditing.inserting(.init(selection: selection, image: image,
            widthPoints: size.width, heightPoints: size.height), source: source, drafts: package.blocks)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        try inserted.document.data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let owner = try XCTUnwrap(model.blocks.first { !$0.canvasObjects.isEmpty })
        let object = try XCTUnwrap(owner.canvasObjects.first)
        let target = try XCTUnwrap(HWPImageEditing.target(owner: owner, object: object))
        let before = model.blocks
        let crop = try XCTUnwrap(HWPImageEditing.Crop(rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)))
        let layout = presentation(target, rotation: 90, flipHorizontal: true,
            flipVertical: true, wrap: .behindText)
        _ = try await model.editImage(.update(crop,
            target.fittedDimensions(for: crop, width: 120), layout,
            appearance(color: 0xB42318, width: 3, style: 3, brightness: -15, contrast: 32,
                effect: .blackAndWhite, transparency: 42)),
            target: target)
        let changed = model.blocks
        XCTAssertNotEqual(changed, before)
        XCTAssertTrue(model.hasUnsavedChanges)
        model.undo(); XCTAssertEqual(model.blocks, before)
        model.redo(); XCTAssertEqual(model.blocks, changed)
        await model.save()
        XCTAssertNil(model.errorDescription)
        XCTAssertFalse(model.hasUnsavedChanges)

        let reopened = try HWPTableStructureDocument.load(Data(contentsOf: url))
        let reopenedOwner = try XCTUnwrap(reopened.blocks.first { !$0.canvasObjects.isEmpty })
        let reopenedObject = try XCTUnwrap(reopenedOwner.canvasObjects.first)
        guard case .image(let reopenedImage) = reopenedObject.content else { return XCTFail("Saved object is not an image") }
        XCTAssertEqual(try XCTUnwrap(reopenedImage.cropRect).minX, 0.5, accuracy: 0.001)
        XCTAssertEqual(reopenedObject.placement.widthPoints, 120, accuracy: 0.02)
        XCTAssertEqual(reopenedObject.placement.heightPoints, 120, accuracy: 0.02)
        XCTAssertEqual(reopenedObject.placement.rotationDegrees, 90, accuracy: 0.02)
        XCTAssertTrue(reopenedObject.placement.flipHorizontal)
        XCTAssertTrue(reopenedObject.placement.flipVertical)
        XCTAssertFalse(reopenedObject.placement.isInline)
        XCTAssertEqual(reopenedObject.placement.wrap, .behindText)
        XCTAssertEqual(reopenedImage.borderStroke?.colorRGB, 0xB42318)
        XCTAssertEqual(try XCTUnwrap(reopenedImage.borderStroke).widthPoints, 3, accuracy: 0.02)
        XCTAssertEqual(reopenedImage.borderStroke?.style, 3)
        XCTAssertEqual(reopenedImage.brightness, -15)
        XCTAssertEqual(reopenedImage.contrast, 32)
        XCTAssertEqual(reopenedImage.effect, .blackAndWhite)
        XCTAssertEqual(reopenedImage.transparencyPercent, 42)
        XCTAssertTrue(reopenedImage.supportsTransparency)
    }

    func testHWPImageInsertResizeDeleteRoundTrip() async throws {
        let source = try HWPTableStructureDocument.load(fixture("hangul_design_application", "hwp"))
        let candidate = try XCTUnwrap(source.blocks.compactMap { block -> HWPImageEditing.Selection? in
            HWPImageEditing.selection(blocks: source.blocks, selectedID: block.id,
                range: NSRange(location: block.text.utf16.count, length: 0), layouts: source.layouts)
        }.first)
        let image = try HWPImageEditing.normalize(Self.png)
        let size = image.displaySize(maxWidth: candidate.width)
        let inserted = try await HWPImageEditing.inserting(.init(selection: candidate, image: image,
            widthPoints: size.width, heightPoints: size.height), source: source, drafts: source.blocks)

        let owner = try XCTUnwrap(inserted.document.blocks.first { $0.id == inserted.focusedID })
        let object = try XCTUnwrap(owner.canvasObjects.first { if case .image = $0.content { return true }; return false })
        let ole = try OLECompoundFile(data: inserted.document.data)
        XCTAssertTrue(ole.streamNames.contains { $0.hasPrefix("bindata/bin") })

        let target = try XCTUnwrap(HWPImageEditing.target(owner: owner, object: object))
        XCTAssertTrue(target.isInline)
        XCTAssertFalse(target.supportsTransparency)
        let inlineMove = try XCTUnwrap(HWPImageEditing.directUpdate(
            .move(deltaX: 7, deltaY: 5), target: target))
        let inlineMoved = try await HWPImageEditing.applying(.update(inlineMove.crop,
            inlineMove.dimensions, inlineMove.presentation, inlineMove.appearance),
            target: target, source: inserted.document, drafts: inserted.document.blocks)
        let inlineOwner = try XCTUnwrap(inlineMoved.document.blocks.first { $0.id == inlineMoved.focusedID })
        let inlineObject = try XCTUnwrap(inlineOwner.canvasObjects.first {
            if case .image = $0.content { return true }; return false
        })
        let inlineTarget = try XCTUnwrap(HWPImageEditing.target(owner: inlineOwner, object: inlineObject))
        XCTAssertEqual(inlineTarget.xPoints, target.xPoints + 7, accuracy: 0.03)
        XCTAssertEqual(inlineTarget.yPoints, target.yPoints + 5, accuracy: 0.03)
        let half = try XCTUnwrap(HWPImageEditing.Crop(rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)))
        let cropped = try await HWPImageEditing.applying(
            .crop(half, inlineTarget.fittedDimensions(for: half, width: 120)),
            target: inlineTarget, source: inlineMoved.document, drafts: inlineMoved.document.blocks)
        let croppedOwner = try XCTUnwrap(cropped.document.blocks.first { $0.id == cropped.focusedID })
        let croppedObject = try XCTUnwrap(croppedOwner.canvasObjects.first { if case .image = $0.content { return true }; return false })
        guard case .image(let croppedImage) = croppedObject.content else { return XCTFail("Cropped object is not an image") }
        XCTAssertEqual(try XCTUnwrap(croppedImage.cropRect).minX, 0.5, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(croppedImage.cropRect).width, 0.5, accuracy: 0.01)
        XCTAssertEqual(croppedObject.placement.heightPoints, 120, accuracy: 0.02)

        let croppedTarget = try XCTUnwrap(HWPImageEditing.target(owner: croppedOwner, object: croppedObject))
        let restored = try await HWPImageEditing.applying(
            .crop(.full, croppedTarget.fittedDimensions(for: .full, width: 120)),
            target: croppedTarget, source: cropped.document, drafts: cropped.document.blocks)
        let restoredOwner = try XCTUnwrap(restored.document.blocks.first { $0.id == restored.focusedID })
        let restoredObject = try XCTUnwrap(restoredOwner.canvasObjects.first { if case .image = $0.content { return true }; return false })
        guard case .image(let restoredImage) = restoredObject.content else { return XCTFail("Restored object is not an image") }
        XCTAssertEqual(try XCTUnwrap(restoredImage.cropRect).width, 1, accuracy: 0.01)
        XCTAssertEqual(restoredObject.placement.heightPoints, 60, accuracy: 0.02)

        let restoredTarget = try XCTUnwrap(HWPImageEditing.target(owner: restoredOwner, object: restoredObject))
        let presented = try await HWPImageEditing.applying(.update(.full,
            .init(widthPoints: 120, heightPoints: 60), presentation(restoredTarget,
                rotation: 270, flipVertical: true, wrap: .square),
            appearance(color: 0x248A3D, width: 1.75, style: 4, brightness: 21, contrast: -17,
                effect: .grayscale)),
            target: restoredTarget, source: restored.document, drafts: restored.document.blocks)
        let presentedOwner = try XCTUnwrap(presented.document.blocks.first { $0.id == presented.focusedID })
        let presentedObject = try XCTUnwrap(presentedOwner.canvasObjects.first { if case .image = $0.content { return true }; return false })
        let presentedTarget = try XCTUnwrap(HWPImageEditing.target(owner: presentedOwner, object: presentedObject))
        XCTAssertEqual(presentedTarget.rotationDegrees, 270, accuracy: 0.02)
        XCTAssertTrue(presentedTarget.flipVertical)
        XCTAssertFalse(presentedTarget.isInline)
        XCTAssertEqual(presentedTarget.wrap, .square)
        XCTAssertEqual(presentedTarget.horizontalReference, .page)
        XCTAssertEqual(presentedTarget.horizontalAlignment, .center)
        XCTAssertEqual(presentedTarget.marginBottomPoints, 9, accuracy: 0.02)
        XCTAssertEqual(presentedTarget.borderStroke?.colorRGB, 0x248A3D)
        XCTAssertEqual(try XCTUnwrap(presentedTarget.borderStroke).widthPoints, 1.75, accuracy: 0.02)
        XCTAssertEqual(presentedTarget.borderStroke?.style, 4)
        XCTAssertEqual(presentedTarget.brightness, 21)
        XCTAssertEqual(presentedTarget.contrast, -17)
        XCTAssertEqual(presentedTarget.effect, .grayscale)
        XCTAssertEqual(presentedTarget.transparencyPercent, 0)

        let movedUpdate = try XCTUnwrap(HWPImageEditing.directUpdate(
            .move(deltaX: 18, deltaY: 11), target: presentedTarget))
        let moved = try await HWPImageEditing.applying(.update(movedUpdate.crop,
            movedUpdate.dimensions, movedUpdate.presentation, movedUpdate.appearance),
            target: presentedTarget, source: presented.document, drafts: presented.document.blocks)
        let movedOwner = try XCTUnwrap(moved.document.blocks.first { $0.id == moved.focusedID })
        let movedObject = try XCTUnwrap(movedOwner.canvasObjects.first {
            if case .image = $0.content { return true }; return false
        })
        let movedTarget = try XCTUnwrap(HWPImageEditing.target(owner: movedOwner, object: movedObject))
        XCTAssertEqual(movedTarget.xPoints, presentedTarget.xPoints + 18, accuracy: 0.03)
        XCTAssertEqual(movedTarget.yPoints, presentedTarget.yPoints + 11, accuracy: 0.03)

        let axisUpdate = try XCTUnwrap(HWPImageEditing.directUpdate(
            .resize(anchor: .bottomLeading, deltaX: 12, deltaY: 18), target: movedTarget))
        let axisResized = try await HWPImageEditing.applying(.update(axisUpdate.crop,
            axisUpdate.dimensions, axisUpdate.presentation, axisUpdate.appearance),
            target: movedTarget, source: moved.document, drafts: moved.document.blocks)
        let axisDocument = try HWPTableStructureDocument.load(axisResized.document.data)
        let axisOwner = try XCTUnwrap(axisDocument.blocks.first { $0.id == movedOwner.id })
        let axisObject = try XCTUnwrap(axisOwner.canvasObjects.first { $0.id == movedObject.id })
        let axisTarget = try XCTUnwrap(HWPImageEditing.target(owner: axisOwner, object: axisObject))
        XCTAssertEqual(axisTarget.xPoints, axisUpdate.presentation.xPoints, accuracy: 0.03)
        XCTAssertEqual(axisTarget.yPoints, axisUpdate.presentation.yPoints, accuracy: 0.03)
        XCTAssertEqual(axisTarget.widthPoints, axisUpdate.dimensions.widthPoints, accuracy: 0.03)
        XCTAssertEqual(axisTarget.heightPoints, axisUpdate.dimensions.heightPoints, accuracy: 0.03)
        XCTAssertEqual(axisTarget.rotationDegrees, movedTarget.rotationDegrees, accuracy: 0.03)
        XCTAssertTrue(axisTarget.flipVertical)

        let resized = try await HWPImageEditing.applying(.resize(.init(widthPoints: 180, heightPoints: 120)),
            target: axisTarget, source: axisDocument, drafts: axisDocument.blocks)
        let resizedOwner = try XCTUnwrap(resized.document.blocks.first { $0.id == resized.focusedID })
        let resizedObject = try XCTUnwrap(resizedOwner.canvasObjects.first { if case .image = $0.content { return true }; return false })
        XCTAssertEqual(resizedObject.placement.widthPoints, 180, accuracy: 0.02)
        XCTAssertEqual(resizedObject.placement.heightPoints, 120, accuracy: 0.02)

        let resizedTarget = try XCTUnwrap(HWPImageEditing.target(owner: resizedOwner, object: resizedObject))
        let deleted = try await HWPImageEditing.applying(.delete, target: resizedTarget,
            source: resized.document, drafts: resized.document.blocks)
        let reopened = try HWPTableStructureDocument.load(deleted.document.data)
        XCTAssertFalse(reopened.blocks.flatMap(\.canvasObjects).contains { if case .image = $0.content { return true }; return false })
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

    private func presentation(_ target: HWPImageEditing.Target,
                              rotation: Double,
                              flipHorizontal: Bool = false,
                              flipVertical: Bool = false,
                              wrap: HWPDocumentObjectWrap) -> HWPImageEditing.Presentation {
        HWPImageEditing.Presentation(xPoints: target.xPoints, yPoints: target.yPoints,
            zOrder: target.zOrder + 2,
            rotationDegrees: rotation,
            flipHorizontal: flipHorizontal, flipVertical: flipVertical,
            isInline: false, horizontalReference: .page,
            verticalReference: .page, horizontalAlignment: .center,
            verticalAlignment: .end, wrap: wrap,
            marginLeftPoints: 6, marginRightPoints: 7,
            marginTopPoints: 8, marginBottomPoints: 9)
    }

    private func appearance(color: UInt32, width: Double, style: Int,
                            brightness: Int, contrast: Int,
                            effect: HWPDocumentImageEffect = .original,
                            transparency: Int = 0) -> HWPImageEditing.Appearance {
        HWPImageEditing.Appearance(borderStroke: HWPDocumentStroke(colorRGB: color,
            widthPoints: width, style: style), brightness: brightness, contrast: contrast,
            effect: effect, transparencyPercent: transparency)
    }

    private func fixture(_ name: String, _ ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "HWPXViewerFixtures")))
    }
}
