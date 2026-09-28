import Foundation
import ImageIO
import UIKit

nonisolated enum HWPImageEditing {
    struct Selection: Identifiable, Sendable {
        let id = UUID()
        let blockID: String
        let text: String
        let caret: Int
        let width: Double
    }

    struct ImportedImage: Sendable {
        let data: Data
        let fileExtension: String
        let mediaType: String
        let pixelWidth: Int
        let pixelHeight: Int

        func displaySize(maxWidth: Double) -> CGSize {
            let width = min(max(maxWidth, 40), 360)
            let height = width * Double(pixelHeight) / Double(pixelWidth)
            if height <= 500 { return CGSize(width: width, height: max(height, 20)) }
            return CGSize(width: max(20, width * 500 / height), height: 500)
        }
    }

    struct Request: Sendable {
        let selection: Selection
        let image: ImportedImage
        let widthPoints: Double
        let heightPoints: Double

        var isValid: Bool {
            image.data.count <= 20 * 1_024 * 1_024
                && image.pixelWidth > 0 && image.pixelHeight > 0
                && widthPoints.isFinite && heightPoints.isFinite
                && (20...2_000).contains(widthPoints)
                && (20...2_000).contains(heightPoints)
        }
    }

    struct Target: Identifiable, Sendable {
        let ownerID: String
        let objectID: String
        let widthPoints: Double
        let heightPoints: Double
        let imageData: Data
        let cropRect: CGRect
        let sourcePixelWidth: Int
        let sourcePixelHeight: Int
        let sourceAspectRatio: Double
        let xPoints: Double
        let yPoints: Double
        let zOrder: Int
        let rotationDegrees: Double
        let flipHorizontal: Bool
        let flipVertical: Bool
        let isInline: Bool
        let horizontalReference: HWPDocumentLayoutReference
        let verticalReference: HWPDocumentLayoutReference
        let horizontalAlignment: HWPDocumentRelativeAlignment
        let verticalAlignment: HWPDocumentRelativeAlignment
        let wrap: HWPDocumentObjectWrap
        let marginLeftPoints: Double
        let marginRightPoints: Double
        let marginTopPoints: Double
        let marginBottomPoints: Double
        let borderStroke: HWPDocumentStroke?
        let brightness: Int
        let contrast: Int
        let effect: HWPDocumentImageEffect
        let transparencyPercent: Int
        let supportsTransparency: Bool
        var id: String { objectID }

        func fittedDimensions(for crop: Crop, width: Double? = nil) -> Dimensions {
            let fittedWidth = width ?? widthPoints
            let visibleAspect = sourceAspectRatio * crop.rect.width / crop.rect.height
            return Dimensions(widthPoints: fittedWidth,
                heightPoints: fittedWidth / max(visibleAspect, 0.001))
        }

        var presentation: Presentation {
            Presentation(xPoints: xPoints, yPoints: yPoints,
                zOrder: zOrder, rotationDegrees: rotationDegrees,
                flipHorizontal: flipHorizontal, flipVertical: flipVertical,
                isInline: isInline, horizontalReference: horizontalReference,
                verticalReference: verticalReference,
                horizontalAlignment: horizontalAlignment,
                verticalAlignment: verticalAlignment, wrap: wrap,
                marginLeftPoints: marginLeftPoints, marginRightPoints: marginRightPoints,
                marginTopPoints: marginTopPoints, marginBottomPoints: marginBottomPoints)
        }

        var appearance: Appearance {
            Appearance(borderStroke: borderStroke, brightness: brightness, contrast: contrast,
                effect: effect, transparencyPercent: transparencyPercent)
        }
    }

    struct Dimensions: Sendable {
        let widthPoints: Double
        let heightPoints: Double
        var isValid: Bool {
            widthPoints.isFinite && heightPoints.isFinite
                && (20...2_000).contains(widthPoints)
                && (20...2_000).contains(heightPoints)
        }
    }

    struct Crop: Sendable, Equatable {
        let rect: CGRect

        init?(rect: CGRect) {
            guard rect.minX.isFinite, rect.minY.isFinite,
                  rect.width.isFinite, rect.height.isFinite,
                  rect.minX >= 0, rect.minY >= 0,
                  rect.maxX <= 1.000_001, rect.maxY <= 1.000_001,
                  rect.width >= 0.02, rect.height >= 0.02 else { return nil }
            self.rect = CGRect(x: min(max(rect.minX, 0), 0.98),
                y: min(max(rect.minY, 0), 0.98),
                width: min(rect.width, 1 - min(max(rect.minX, 0), 0.98)),
                height: min(rect.height, 1 - min(max(rect.minY, 0), 0.98)))
        }

        static let full = Crop(rect: CGRect(x: 0, y: 0, width: 1, height: 1))!
    }

    struct Presentation: Sendable {
        let xPoints: Double
        let yPoints: Double
        let zOrder: Int
        let rotationDegrees: Double
        let flipHorizontal: Bool
        let flipVertical: Bool
        let isInline: Bool
        let horizontalReference: HWPDocumentLayoutReference
        let verticalReference: HWPDocumentLayoutReference
        let horizontalAlignment: HWPDocumentRelativeAlignment
        let verticalAlignment: HWPDocumentRelativeAlignment
        let wrap: HWPDocumentObjectWrap
        let marginLeftPoints: Double
        let marginRightPoints: Double
        let marginTopPoints: Double
        let marginBottomPoints: Double

        var isValid: Bool {
            xPoints.isFinite && yPoints.isFinite
                && (-4_000...4_000).contains(xPoints) && (-4_000...4_000).contains(yPoints)
                && (-100_000...100_000).contains(zOrder)
                && rotationDegrees.isFinite && (0...359).contains(rotationDegrees)
                && [marginLeftPoints, marginRightPoints, marginTopPoints, marginBottomPoints]
                    .allSatisfy { $0.isFinite && (0...655).contains($0) }
                && (!isInline || wrap == .topAndBottom)
        }
    }

    struct Appearance: Sendable {
        let borderStroke: HWPDocumentStroke?
        let brightness: Int
        let contrast: Int
        let effect: HWPDocumentImageEffect
        let transparencyPercent: Int

        init(borderStroke: HWPDocumentStroke?, brightness: Int, contrast: Int,
             effect: HWPDocumentImageEffect = .original, transparencyPercent: Int = 0) {
            self.borderStroke = borderStroke
            self.brightness = brightness
            self.contrast = contrast
            self.effect = effect
            self.transparencyPercent = transparencyPercent
        }

        var isValid: Bool {
            (-100...100).contains(brightness)
                && (-100...100).contains(contrast)
                && (0...100).contains(transparencyPercent)
                && borderStroke.map {
                    (0...63).contains($0.style) && $0.style != 0
                        && $0.widthPoints.isFinite && (0.25...32).contains($0.widthPoints)
                } ?? true
        }
    }

    enum DirectManipulation: Sendable {
        case move(deltaX: Double, deltaY: Double)
        case resize(anchor: HWPShapeEditing.ResizeAnchor, deltaX: Double, deltaY: Double)
        case rotate(deltaDegrees: Double)
    }

    struct Update: Sendable {
        let crop: Crop
        let dimensions: Dimensions
        let presentation: Presentation
        let appearance: Appearance
    }

    enum Action: Sendable {
        case resize(Dimensions)
        case crop(Crop, Dimensions)
        case update(Crop, Dimensions, Presentation, Appearance)
        case delete
    }

    static func selection(blocks: [HWPDocumentBlock], selectedID: String?, range: NSRange,
                          layouts: [HWPDocumentPageLayout]) -> Selection? {
        let block = selectedID.flatMap { id in blocks.first { $0.id == id } }
            ?? (blocks.count == 1 && blocks[0].text.isEmpty ? blocks[0] : nil)
        guard let block, supportsInsertion(in: block), block.presentation.list == nil,
              !block.lineLayouts.contains(where: { $0.listMarker != nil }), range.length == 0,
              range.location >= 0, range.location <= block.text.utf16.count,
              (block.text.indices.map { $0.utf16Offset(in: block.text) } + [block.text.utf16.count]).contains(range.location),
              let layout = layouts.first(where: { $0.sectionIndex == HWPPageSetup.sectionIndex(block.sectionPath) }),
              layout.columnLayout.columns.count <= 1 else { return nil }
        let availableWidth = block.tableLocation.map {
            ($0.cellWidthPoints ?? 0) - $0.cellMarginLeftPoints - $0.cellMarginRightPoints
        } ?? (layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints)
        return Selection(blockID: block.id, text: block.text, caret: range.location,
            width: max(availableWidth
                - block.presentation.leftMarginPoints - block.presentation.rightMarginPoints
                - max(block.presentation.firstLineIndentPoints, 0), 20))
    }

    static func supportsInsertion(in block: HWPDocumentBlock) -> Bool {
        if HWPParagraphEditing.supports(block) { return true }
        return block.isEditable && block.region.kind == .body
            && block.tableLocation != nil
            && block.layoutContainerID == nil
            && block.images.isEmpty && block.canvasObjects.isEmpty
            && block.presentation.list == nil
            && !block.lineLayouts.contains(where: { $0.listMarker != nil })
    }

    static func target(owner: HWPDocumentBlock, object: HWPDocumentCanvasObject) -> Target? {
        guard owner.region.kind == .body,
              case .image(let image) = object.content,
              let source = CGImageSourceCreateWithData(image.data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0 else { return nil }
        return Target(ownerID: owner.id, objectID: object.id,
            widthPoints: object.placement.widthPoints, heightPoints: object.placement.heightPoints,
            imageData: image.data,
            cropRect: image.cropRect ?? CGRect(x: 0, y: 0, width: 1, height: 1),
            sourcePixelWidth: width.intValue,
            sourcePixelHeight: height.intValue,
            sourceAspectRatio: width.doubleValue / height.doubleValue,
            xPoints: object.placement.xPoints,
            yPoints: object.placement.yPoints,
            zOrder: object.placement.zOrder,
            rotationDegrees: object.placement.rotationDegrees,
            flipHorizontal: object.placement.flipHorizontal,
            flipVertical: object.placement.flipVertical,
            isInline: object.placement.isInline,
            horizontalReference: object.placement.horizontalReference,
            verticalReference: object.placement.verticalReference,
            horizontalAlignment: object.placement.horizontalAlignment,
            verticalAlignment: object.placement.verticalAlignment,
            wrap: object.placement.wrap,
            marginLeftPoints: object.placement.marginLeftPoints,
            marginRightPoints: object.placement.marginRightPoints,
            marginTopPoints: object.placement.marginTopPoints,
            marginBottomPoints: object.placement.marginBottomPoints,
            borderStroke: image.borderStroke,
            brightness: image.brightness,
            contrast: image.contrast,
            effect: image.effect,
            transparencyPercent: image.transparencyPercent,
            supportsTransparency: image.supportsTransparency)
    }

    static func directUpdate(_ operation: DirectManipulation, target: Target) -> Update? {
        var x = target.xPoints, y = target.yPoints
        var width = target.widthPoints, height = target.heightPoints
        var rotation = target.rotationDegrees
        switch operation {
        case .move(let deltaX, let deltaY):
            guard deltaX.isFinite, deltaY.isFinite else { return nil }
            x = min(max(x + deltaX, -4_000), 4_000)
            y = min(max(y + deltaY, -4_000), 4_000)
        case .resize(let anchor, let deltaX, let deltaY):
            guard let geometry = HWPShapeEditing.directResizeGeometry(anchor: anchor,
                deltaX: deltaX, deltaY: deltaY,
                xPoints: target.xPoints, yPoints: target.yPoints,
                widthPoints: target.widthPoints, heightPoints: target.heightPoints,
                rotationDegrees: target.rotationDegrees,
                flipHorizontal: target.flipHorizontal,
                flipVertical: target.flipVertical,
                minimumHeight: 20) else { return nil }
            x = geometry.xPoints; y = geometry.yPoints
            width = geometry.widthPoints; height = geometry.heightPoints
        case .rotate(let deltaDegrees):
            guard deltaDegrees.isFinite else { return nil }
            rotation = (target.rotationDegrees + deltaDegrees)
                .truncatingRemainder(dividingBy: 360)
            if rotation < 0 { rotation += 360 }
        }
        let presentation = Presentation(xPoints: x, yPoints: y,
            zOrder: target.zOrder, rotationDegrees: rotation,
            flipHorizontal: target.flipHorizontal, flipVertical: target.flipVertical,
            isInline: target.isInline, horizontalReference: target.horizontalReference,
            verticalReference: target.verticalReference,
            horizontalAlignment: target.horizontalAlignment,
            verticalAlignment: target.verticalAlignment,
            wrap: target.isInline ? .topAndBottom : target.wrap,
            marginLeftPoints: target.marginLeftPoints,
            marginRightPoints: target.marginRightPoints,
            marginTopPoints: target.marginTopPoints,
            marginBottomPoints: target.marginBottomPoints)
        let dimensions = Dimensions(widthPoints: width, heightPoints: height)
        guard presentation.isValid, dimensions.isValid else { return nil }
        return Update(crop: Crop(rect: target.cropRect) ?? .full,
            dimensions: dimensions, presentation: presentation,
            appearance: target.appearance)
    }

    static func normalize(_ source: Data) throws -> ImportedImage {
        guard !source.isEmpty, source.count <= 20 * 1_024 * 1_024,
              let imageSource = CGImageSourceCreateWithData(source as CFData, nil),
              CGImageSourceGetCount(imageSource) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let rawWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let rawHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw HWPDocumentEditingError.invalidDocument
        }
        let width = rawWidth.intValue, height = rawHeight.intValue
        guard width > 0, height > 0, width <= 20_000, height <= 20_000,
              Int64(width) * Int64(height) <= 50_000_000 else {
            throw HWPDocumentEditingError.limitExceeded
        }
        let maximum = 4_096
        let scale = min(1, Double(maximum) / Double(max(width, height)))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(Double(max(width, height)) * scale))
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            throw HWPDocumentEditingError.invalidDocument
        }
        let uiImage = UIImage(cgImage: cgImage)
        let hasAlpha = cgImage.alphaInfo == .first || cgImage.alphaInfo == .last
            || cgImage.alphaInfo == .premultipliedFirst || cgImage.alphaInfo == .premultipliedLast
        let encoded = hasAlpha ? uiImage.pngData() : uiImage.jpegData(compressionQuality: 0.9)
        guard let encoded, encoded.count <= 20 * 1_024 * 1_024 else {
            throw HWPDocumentEditingError.limitExceeded
        }
        return ImportedImage(data: encoded, fileExtension: hasAlpha ? "png" : "jpg",
            mediaType: hasAlpha ? "image/png" : "image/jpeg",
            pixelWidth: cgImage.width, pixelHeight: cgImage.height)
    }

    @MainActor static func inserting(_ request: Request, source: HWPTableStructureDocument,
                                     drafts: [HWPDocumentBlock]) async throws -> HWPTableStructureDocument.Result {
        guard request.isValid, drafts.count <= HWPXDocumentPackage.maximumBlocks - 2,
              let index = drafts.firstIndex(where: { $0.id == request.selection.blockID }),
              drafts[index].text == request.selection.text,
              selection(blocks: drafts, selectedID: request.selection.blockID,
                  range: NSRange(location: request.selection.caret, length: 0), layouts: source.layouts) != nil else {
            throw HWPDocumentEditingError.staleDocument
        }
        let (prepared, changed, ownerIndex) = try await Task.detached(priority: .userInitiated) {
            let base = try HWPTableStructureDocument.load(source.serialized(drafts))
            guard base.blocks.indices.contains(index),
                  base.blocks[index].text == request.selection.text else {
                throw HWPDocumentEditingError.staleDocument
            }
            let prepared: HWPTableStructureDocument
            let ownerIndex: Int
            if base.blocks[index].tableLocation != nil {
                prepared = base
                ownerIndex = index
            } else {
                guard let split = HWPParagraphEditing.apply(
                    .split(.init(location: request.selection.caret, length: 0)),
                    draft: base.blocks[index], to: base.blocks),
                      let suffix = split.blocks.first(where: { $0.id == split.focusedID }),
                      let second = HWPParagraphEditing.apply(.split(.init(location: 0, length: 0)),
                        draft: suffix, to: split.blocks) else {
                    throw HWPDocumentEditingError.unsupportedEdit
                }
                var blocks = second.blocks
                guard let index = blocks.firstIndex(where: { $0.id == suffix.id }) else {
                    throw HWPDocumentEditingError.staleDocument
                }
                ownerIndex = index
                for command in [HWPFormattingCommand.clearCharacterFormatting, .alignment(.leading),
                                .paragraph(left: 0, right: 0, indent: 0, before: 0, after: 0, linePercent: 160)] {
                    blocks[ownerIndex] = HWPDocumentFormatting.apply(command, to: blocks[ownerIndex],
                        range: NSRange(location: 0, length: 0))
                }
                prepared = try HWPTableStructureDocument.load(base.serialized(blocks))
            }
            let bytes = try HWPImageEditingWriter.insert(request, into: prepared, ownerIndex: ownerIndex)
            return (prepared, try HWPTableStructureDocument.load(bytes), ownerIndex)
        }.value
        guard changed.blocks.indices.contains(ownerIndex),
              let object = changed.blocks[ownerIndex].canvasObjects.first(where: {
                  if case .image = $0.content { return true }; return false
              }), let layout = changed.layouts.first(where: {
                  $0.sectionIndex == HWPPageSetup.sectionIndex(changed.blocks[ownerIndex].sectionPath)
              }) else { throw HWPDocumentEditingError.cannotSave }
        let final = try await finalized(changed: changed, before: prepared.blocks,
            ownerIndex: ownerIndex, minimumHeight: object.placement.heightPoints, layout: layout)
        guard final.blocks.indices.contains(ownerIndex),
              final.blocks[ownerIndex].canvasObjects.contains(where: { if case .image = $0.content { return true }; return false }) else {
            throw HWPDocumentEditingError.cannotSave
        }
        return .init(document: final, focusedID: final.blocks[ownerIndex].id)
    }

    @MainActor static func applying(_ action: Action, target: Target, source: HWPTableStructureDocument,
                                    drafts: [HWPDocumentBlock]) async throws -> HWPTableStructureDocument.Result {
        guard let ownerIndex = drafts.firstIndex(where: { $0.id == target.ownerID }),
              let current = drafts[ownerIndex].canvasObjects.first(where: { $0.id == target.objectID }),
              case .image = current.content,
              abs(current.placement.widthPoints - target.widthPoints) < 0.03,
              abs(current.placement.heightPoints - target.heightPoints) < 0.03 else {
            throw HWPDocumentEditingError.staleDocument
        }
        switch action {
        case .resize(let dimensions), .crop(_, let dimensions):
            guard dimensions.isValid else { throw HWPDocumentEditingError.limitExceeded }
        case .update(_, let dimensions, let presentation, let appearance):
            guard dimensions.isValid, presentation.isValid, appearance.isValid,
                  target.supportsTransparency || appearance.transparencyPercent == 0 else {
                throw HWPDocumentEditingError.limitExceeded
            }
        case .delete: break
        }
        let (base, changed) = try await Task.detached(priority: .userInitiated) {
            let base = source.blocks == drafts
                ? source
                : try HWPTableStructureDocument.load(source.serialized(drafts))
            guard base.blocks.indices.contains(ownerIndex),
                  base.blocks[ownerIndex].canvasObjects.contains(where: { $0.id == target.objectID }) else {
                throw HWPDocumentEditingError.staleDocument
            }
            let data = try HWPImageEditingWriter.apply(action, target: target, to: base, ownerIndex: ownerIndex)
            return (base, try HWPTableStructureDocument.load(data))
        }.value
        if drafts[ownerIndex].tableLocation != nil {
            let minimum = cellMinimumHeight(action)
            let final = try await finalized(changed: changed, before: base.blocks,
                ownerIndex: ownerIndex, minimumHeight: minimum,
                layout: changed.layouts.first(where: {
                    $0.sectionIndex == HWPPageSetup.sectionIndex(changed.blocks[ownerIndex].sectionPath)
                }))
            if case .delete = action,
               final.blocks[ownerIndex].canvasObjects.contains(where: { $0.id == target.objectID }) {
                throw HWPDocumentEditingError.cannotSave
            }
            return .init(document: final, focusedID: final.blocks[ownerIndex].id)
        }
        if drafts[ownerIndex].layoutContainerID != nil {
            if case .delete = action,
               changed.blocks[ownerIndex].canvasObjects.contains(where: { $0.id == target.objectID }) {
                throw HWPDocumentEditingError.cannotSave
            }
            return .init(document: changed, focusedID: changed.blocks[ownerIndex].id)
        }
        guard changed.blocks.indices.contains(ownerIndex),
              let layout = changed.layouts.first(where: {
                  $0.sectionIndex == HWPPageSetup.sectionIndex(changed.blocks[ownerIndex].sectionPath)
              }) else { throw HWPDocumentEditingError.cannotSave }
        let minimum: Double
        switch action {
        case .resize(let dimensions): minimum = dimensions.heightPoints
        case .crop(_, let dimensions): minimum = dimensions.heightPoints
        case .update(_, let dimensions, let presentation, _):
            minimum = presentation.wrap == .behindText || presentation.wrap == .inFrontOfText
                ? 0 : dimensions.heightPoints
        case .delete: minimum = 0
        }
        let final = try await finalized(changed: changed, before: base.blocks,
            ownerIndex: ownerIndex, minimumHeight: minimum, layout: layout)
        if case .delete = action,
           final.blocks[ownerIndex].canvasObjects.contains(where: { $0.id == target.objectID }) {
            throw HWPDocumentEditingError.cannotSave
        }
        return .init(document: final, focusedID: final.blocks[ownerIndex].id)
    }

    private static func cellMinimumHeight(_ action: Action) -> Double {
        switch action {
        case .delete:
            return 0
        case .resize(let dimensions), .crop(_, let dimensions):
            return dimensions.heightPoints
        case .update(_, let dimensions, let presentation, _):
            guard presentation.wrap != .behindText,
                  presentation.wrap != .inFrontOfText else { return 0 }
            let radians = presentation.rotationDegrees * .pi / 180
            let rotatedHeight = abs(sin(radians)) * dimensions.widthPoints
                + abs(cos(radians)) * dimensions.heightPoints
            let bottom = presentation.yPoints + dimensions.heightPoints / 2
                + rotatedHeight / 2
            return max(dimensions.heightPoints, bottom)
                + presentation.marginTopPoints + presentation.marginBottomPoints
        }
    }

    @MainActor private static func finalized(changed: HWPTableStructureDocument, before: [HWPDocumentBlock],
                                             ownerIndex: Int, minimumHeight: Double,
                                             layout: HWPDocumentPageLayout?) async throws -> HWPTableStructureDocument {
        var flowed = changed.blocks
        let owner = flowed[ownerIndex]
        if owner.tableLocation != nil {
            flowed = HWPTableEditing.reflow(flowed, before: before,
                startingAt: owner.id, layouts: changed.layouts,
                reflowBody: owner.layoutContainerID == nil,
                minimumHeight: minimumHeight, allowingObjects: true)
            let output = try await Task.detached(priority: .userInitiated) {
                try HWPTableStructureDocument.load(changed.serialized(flowed))
            }.value
            guard output.blocks.count == flowed.count,
                  zip(output.blocks, flowed).allSatisfy({ HWPDocumentFormatting.matches($0, $1) }) else {
                throw HWPDocumentEditingError.cannotSave
            }
            return output
        }
        guard let layout else { throw HWPDocumentEditingError.cannotSave }
        let bodyWidth = layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints
            - owner.presentation.leftMarginPoints - owner.presentation.rightMarginPoints
        let y = before.indices.contains(ownerIndex) ? before[ownerIndex].lineLayouts.first?.verticalPositionPoints ?? 0 : 0
        flowed[ownerIndex] = owner.withLayout(lines: HWPFlowLayout.measure(owner,
            width: max(bodyWidth, 1), startY: y, pageHeight: layout.heightPoints - layout.topMarginPoints - layout.bottomMarginPoints,
            minimumHeight: minimumHeight))
        flowed = HWPFlowLayout.reflowingBody(flowed, before: before, startingAt: flowed[ownerIndex].id,
            layouts: changed.layouts)
        let output = try await Task.detached(priority: .userInitiated) {
            try HWPTableStructureDocument.load(changed.serialized(flowed))
        }.value
        guard output.blocks.count == flowed.count,
              zip(output.blocks, flowed).allSatisfy({ HWPDocumentFormatting.matches($0, $1) }) else {
            throw HWPDocumentEditingError.cannotSave
        }
        return output
    }
}
