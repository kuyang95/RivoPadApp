import Foundation
import CoreGraphics

nonisolated enum HWPShapeEditing {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case rectangle, ellipse, line, polygon, connector

        var id: String { rawValue }
        var title: String {
            switch self {
            case .rectangle: "사각형"
            case .ellipse: "타원"
            case .line: "선"
            case .polygon: "자유 다각형"
            case .connector: "연결선"
            }
        }
        var systemImage: String {
            switch self {
            case .rectangle: "rectangle"
            case .ellipse: "circle"
            case .line: "line.diagonal"
            case .polygon: "pentagon"
            case .connector: "point.topleft.down.to.point.bottomright.curvepath"
            }
        }

        var defaultPathPoints: [PathPoint] {
            switch self {
            case .polygon:
                [.init(x: 0.50, y: 0), .init(x: 0.96, y: 0.35), .init(x: 0.78, y: 1),
                 .init(x: 0.22, y: 1), .init(x: 0.04, y: 0.35)]
            case .connector:
                [.init(x: 0, y: 0.12), .init(x: 0.50, y: 0.12),
                 .init(x: 0.50, y: 0.88), .init(x: 1, y: 0.88)]
            default: []
            }
        }
    }

    struct PathPoint: Hashable, Sendable {
        let x: Double
        let y: Double

        init(x: Double, y: Double) {
            self.x = min(max(x, 0), 1)
            self.y = min(max(y, 0), 1)
        }
    }

    struct Selection: Identifiable, Sendable {
        let id = UUID()
        let blockID: String
        let text: String
        let caret: Int
        let width: Double
    }

    struct Request: Sendable {
        let selection: Selection
        let kind: Kind
        let widthPoints: Double
        let heightPoints: Double
        let textBoxText: String?

        init(selection: Selection, kind: Kind, widthPoints: Double,
             heightPoints: Double, textBoxText: String? = nil) {
            self.selection = selection
            self.kind = kind
            self.widthPoints = widthPoints
            self.heightPoints = heightPoints
            self.textBoxText = textBoxText
        }

        var isValid: Bool {
            widthPoints.isFinite && heightPoints.isFinite
                && (20...2_000).contains(widthPoints)
                && (8...2_000).contains(heightPoints)
                && textBoxText.map { !$0.isEmpty && $0.utf16.count <= 32_768 } != false
        }
    }

    struct GroupRequest: Sendable {
        let ownerID: String
        let objectIDs: [String]

        init(ownerID: String, objectIDs: [String]) {
            self.ownerID = ownerID
            self.objectIDs = objectIDs
        }

        var isValid: Bool {
            (2...32).contains(objectIDs.count) && Set(objectIDs).count == objectIDs.count
        }
    }

    enum Arrangement: String, CaseIterable, Identifiable, Sendable {
        case alignLeft, alignCenter, alignRight, alignInside, alignOutside
        case alignTop, alignMiddle, alignBottom
        case distributeHorizontally, distributeVertically

        var id: String { rawValue }
        var title: String {
            switch self {
            case .alignLeft: "왼쪽 맞춤"
            case .alignCenter: "가운데 맞춤"
            case .alignRight: "오른쪽 맞춤"
            case .alignInside: "맞쪽 안쪽 맞춤"
            case .alignOutside: "맞쪽 바깥쪽 맞춤"
            case .alignTop: "위쪽 맞춤"
            case .alignMiddle: "중간 맞춤"
            case .alignBottom: "아래쪽 맞춤"
            case .distributeHorizontally: "가로 간격 동일"
            case .distributeVertically: "세로 간격 동일"
            }
        }
        var systemImage: String {
            switch self {
            case .alignLeft: "align.horizontal.left"
            case .alignCenter: "align.horizontal.center"
            case .alignRight: "align.horizontal.right"
            case .alignInside: "book.closed"
            case .alignOutside: "book.closed.fill"
            case .alignTop: "align.vertical.top"
            case .alignMiddle: "align.vertical.center"
            case .alignBottom: "align.vertical.bottom"
            case .distributeHorizontally: "distribute.horizontal.center"
            case .distributeVertically: "distribute.vertical.center"
            }
        }
        var minimumSelectionCount: Int {
            switch self {
            case .alignInside, .alignOutside: 1
            case .distributeHorizontally, .distributeVertically: 3
            default: 2
            }
        }
    }

    struct ArrangementRequest: Sendable {
        let ownerID: String
        let objectIDs: [String]
        let arrangement: Arrangement

        var isValid: Bool {
            (arrangement.minimumSelectionCount...32).contains(objectIDs.count)
                && Set(objectIDs).count == objectIDs.count
        }
    }

    enum SizeMatch: String, CaseIterable, Identifiable, Sendable {
        case width, height, both

        var id: String { rawValue }
        var title: String {
            switch self {
            case .width: "너비 같게"
            case .height: "높이 같게"
            case .both: "크기 같게"
            }
        }
        var systemImage: String {
            switch self {
            case .width: "arrow.left.and.right"
            case .height: "arrow.up.and.down"
            case .both: "arrow.up.left.and.arrow.down.right"
            }
        }
    }

    struct SizeMatchRequest: Sendable {
        let ownerID: String
        let objectIDs: [String]
        let match: SizeMatch

        var isValid: Bool {
            (2...32).contains(objectIDs.count) && Set(objectIDs).count == objectIDs.count
        }
    }

    enum Flip: String, CaseIterable, Identifiable, Sendable {
        case horizontal, vertical

        var id: String { rawValue }
        var title: String { self == .horizontal ? "좌우 뒤집기" : "상하 뒤집기" }
        var systemImage: String { self == .horizontal ? "arrow.left.and.right" : "arrow.up.and.down" }
    }

    struct FlipRequest: Sendable {
        let ownerID: String
        let objectIDs: [String]
        let flip: Flip

        var isValid: Bool {
            (1...32).contains(objectIDs.count) && Set(objectIDs).count == objectIDs.count
        }
    }

    enum ResizeAnchor: String, CaseIterable, Sendable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        var movesLeadingEdge: Bool { self == .topLeading || self == .bottomLeading }
        var movesTopEdge: Bool { self == .topLeading || self == .topTrailing }
    }

    enum DirectManipulation: Sendable {
        case move(deltaX: Double, deltaY: Double)
        case resize(anchor: ResizeAnchor, deltaX: Double, deltaY: Double)
        case rotate(deltaDegrees: Double)
    }

    struct DirectResizeGeometry: Equatable, Sendable {
        let xPoints: Double
        let yPoints: Double
        let widthPoints: Double
        let heightPoints: Double
        let localOffsetX: Double
        let localOffsetY: Double
    }

    enum BatchAction: Equatable, Sendable {
        case duplicate, delete
    }

    struct BatchRequest: Sendable {
        let ownerID: String
        let objectIDs: [String]
        let action: BatchAction

        var isValid: Bool {
            (2...32).contains(objectIDs.count) && Set(objectIDs).count == objectIDs.count
        }
    }

    struct Target: Identifiable, Sendable {
        let ownerID: String
        let objectID: String
        let groupChildIndex: Int?
        let groupChildCount: Int
        let kind: Kind?
        let xPoints: Double
        let yPoints: Double
        let widthPoints: Double
        let heightPoints: Double
        let zOrder: Int
        let rotationDegrees: Double
        let flipHorizontal: Bool
        let flipVertical: Bool
        let strokeColorRGB: UInt32
        let strokeWidthPoints: Double
        let strokeStyle: Int
        let fillColorRGB: UInt32?
        let shadow: Shadow?
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
        let pathPoints: [PathPoint]
        let startArrow: Int
        let endArrow: Int
        var id: String { Self.selectionID(objectID: objectID, childIndex: groupChildIndex) }
        var title: String {
            if let groupChildIndex { return "그룹 안 \(kind?.title ?? "도형") \(groupChildIndex + 1)" }
            return kind?.title ?? "그룹 도형"
        }
        var isGroup: Bool { kind == nil && groupChildIndex == nil }
        var isGroupChild: Bool { groupChildIndex != nil }
        var canDeleteGroupChild: Bool { isGroupChild && groupChildCount > 1 }
        var canMoveGroupChildBackward: Bool { (groupChildIndex ?? 0) > 0 }
        var canMoveGroupChildForward: Bool {
            guard let groupChildIndex else { return false }
            return groupChildIndex + 1 < groupChildCount
        }

        static func selectionID(objectID: String, childIndex: Int?) -> String {
            childIndex.map { "\(objectID)#group-child-\($0)" } ?? objectID
        }
    }

    struct Shadow: Hashable, Sendable {
        let colorRGB: UInt32
        let offsetX: Double
        let offsetY: Double
        let opacity: Double
    }

    struct Layout: Sendable {
        let xPoints: Double
        let yPoints: Double
        let widthPoints: Double
        let heightPoints: Double
        let zOrder: Int
        let rotationDegrees: Double
        let flipHorizontal: Bool
        let flipVertical: Bool
        let strokeColorRGB: UInt32
        let strokeWidthPoints: Double
        let strokeStyle: Int
        let fillColorRGB: UInt32?
        let shadow: Shadow?
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
        let pathPoints: [PathPoint]
        let startArrow: Int
        let endArrow: Int

        init(xPoints: Double, yPoints: Double, widthPoints: Double, heightPoints: Double,
             zOrder: Int, rotationDegrees: Double,
             flipHorizontal: Bool = false, flipVertical: Bool = false,
             strokeColorRGB: UInt32,
             strokeWidthPoints: Double, strokeStyle: Int, fillColorRGB: UInt32?,
             shadow: Shadow?, isInline: Bool = true,
             horizontalReference: HWPDocumentLayoutReference = .paragraph,
             verticalReference: HWPDocumentLayoutReference = .paragraph,
             horizontalAlignment: HWPDocumentRelativeAlignment = .start,
             verticalAlignment: HWPDocumentRelativeAlignment = .start,
             wrap: HWPDocumentObjectWrap = .topAndBottom,
             marginLeftPoints: Double = 0, marginRightPoints: Double = 0,
             marginTopPoints: Double = 0, marginBottomPoints: Double = 0,
             pathPoints: [PathPoint] = [], startArrow: Int = 0, endArrow: Int = 0) {
            self.xPoints = xPoints; self.yPoints = yPoints
            self.widthPoints = widthPoints; self.heightPoints = heightPoints
            self.zOrder = zOrder; self.rotationDegrees = rotationDegrees
            self.flipHorizontal = flipHorizontal; self.flipVertical = flipVertical
            self.strokeColorRGB = strokeColorRGB; self.strokeWidthPoints = strokeWidthPoints
            self.strokeStyle = strokeStyle; self.fillColorRGB = fillColorRGB; self.shadow = shadow
            self.isInline = isInline; self.horizontalReference = horizontalReference
            self.verticalReference = verticalReference; self.horizontalAlignment = horizontalAlignment
            self.verticalAlignment = verticalAlignment; self.wrap = wrap
            self.marginLeftPoints = marginLeftPoints; self.marginRightPoints = marginRightPoints
            self.marginTopPoints = marginTopPoints; self.marginBottomPoints = marginBottomPoints
            self.pathPoints = pathPoints
            self.startArrow = min(max(startArrow, 0), 6)
            self.endArrow = min(max(endArrow, 0), 6)
        }

        var isValid: Bool {
            xPoints.isFinite && yPoints.isFinite && widthPoints.isFinite && heightPoints.isFinite
                && (-4_000...4_000).contains(xPoints) && (-4_000...4_000).contains(yPoints)
                && (20...2_000).contains(widthPoints) && (8...2_000).contains(heightPoints)
                && (-100_000...100_000).contains(zOrder)
                && rotationDegrees.isFinite && (0...359).contains(rotationDegrees)
                && strokeColorRGB <= 0xFF_FFFF && strokeWidthPoints.isFinite
                && (0.1...32).contains(strokeWidthPoints) && (0...7).contains(strokeStyle)
                && fillColorRGB.map { $0 <= 0xFF_FFFF } != false
                && shadow.map { value in
                    value.colorRGB <= 0xFF_FFFF && value.offsetX.isFinite && value.offsetY.isFinite
                        && (-100...100).contains(value.offsetX) && (-100...100).contains(value.offsetY)
                        && value.opacity.isFinite && (0...1).contains(value.opacity)
                } != false
                && [marginLeftPoints, marginRightPoints, marginTopPoints, marginBottomPoints].allSatisfy {
                    $0.isFinite && (0...655).contains($0)
                }
                && pathPoints.count <= 32
                && pathPoints.allSatisfy { $0.x.isFinite && $0.y.isFinite }
                && (0...6).contains(startArrow) && (0...6).contains(endArrow)
                && (!isInline || wrap == .topAndBottom)
        }
    }

    enum Action: Sendable {
        case update(Layout)
        case delete
        case moveGroupChild(offset: Int)
        case ungroup
    }

    static func directLayout(_ operation: DirectManipulation, target: Target) -> Layout? {
        guard target.groupChildIndex == nil else { return nil }
        var x = target.xPoints
        var y = target.yPoints
        var width = target.widthPoints
        var height = target.heightPoints
        var rotation = target.rotationDegrees
        switch operation {
        case .move(let deltaX, let deltaY):
            guard deltaX.isFinite, deltaY.isFinite else { return nil }
            x = min(max(x + deltaX, -4_000), 4_000)
            y = min(max(y + deltaY, -4_000), 4_000)
        case .resize(let anchor, let deltaX, let deltaY):
            guard let geometry = directResizeGeometry(anchor: anchor,
                deltaX: deltaX, deltaY: deltaY,
                xPoints: target.xPoints, yPoints: target.yPoints,
                widthPoints: target.widthPoints, heightPoints: target.heightPoints,
                rotationDegrees: target.rotationDegrees,
                flipHorizontal: target.flipHorizontal,
                flipVertical: target.flipVertical,
                minimumHeight: 8) else { return nil }
            x = geometry.xPoints; y = geometry.yPoints
            width = geometry.widthPoints; height = geometry.heightPoints
        case .rotate(let deltaDegrees):
            guard deltaDegrees.isFinite else { return nil }
            rotation = (target.rotationDegrees + deltaDegrees)
                .truncatingRemainder(dividingBy: 360)
            if rotation < 0 { rotation += 360 }
        }
        let result = Layout(xPoints: x, yPoints: y,
            widthPoints: width, heightPoints: height,
            zOrder: target.zOrder, rotationDegrees: rotation,
            flipHorizontal: target.flipHorizontal, flipVertical: target.flipVertical,
            strokeColorRGB: target.strokeColorRGB,
            strokeWidthPoints: target.strokeWidthPoints,
            strokeStyle: target.strokeStyle, fillColorRGB: target.fillColorRGB,
            shadow: target.shadow, isInline: target.isInline,
            horizontalReference: target.horizontalReference,
            verticalReference: target.verticalReference,
            horizontalAlignment: target.horizontalAlignment,
            verticalAlignment: target.verticalAlignment, wrap: target.wrap,
            marginLeftPoints: target.marginLeftPoints,
            marginRightPoints: target.marginRightPoints,
            marginTopPoints: target.marginTopPoints,
            marginBottomPoints: target.marginBottomPoints,
            pathPoints: target.pathPoints, startArrow: target.startArrow,
            endArrow: target.endArrow)
        return result.isValid ? result : nil
    }

    static func directResizeGeometry(anchor: ResizeAnchor,
                                     deltaX: Double, deltaY: Double,
                                     xPoints: Double, yPoints: Double,
                                     widthPoints: Double, heightPoints: Double,
                                     rotationDegrees: Double,
                                     flipHorizontal: Bool, flipVertical: Bool,
                                     minimumHeight: Double) -> DirectResizeGeometry? {
        guard [deltaX, deltaY, xPoints, yPoints, widthPoints, heightPoints,
               rotationDegrees, minimumHeight].allSatisfy(\.isFinite),
              widthPoints > 0, heightPoints > 0,
              (0...2_000).contains(minimumHeight) else { return nil }
        guard let localDelta = directLocalVector(deltaX: deltaX, deltaY: deltaY,
            rotationDegrees: rotationDegrees,
            flipHorizontal: flipHorizontal, flipVertical: flipVertical) else { return nil }
        let horizontalSign = anchor.movesLeadingEdge ? -1.0 : 1.0
        let verticalSign = anchor.movesTopEdge ? -1.0 : 1.0
        let width = min(max(widthPoints + horizontalSign * localDelta.x, 20), 2_000)
        let height = min(max(heightPoints + verticalSign * localDelta.y,
            minimumHeight), 2_000)

        // The dragged edge changes in the object's local coordinate system.
        // Shift the center through the same flip and rotation so the opposite
        // corner remains fixed in document coordinates.
        let localCenterX = horizontalSign * (width - widthPoints) / 2
        let localCenterY = verticalSign * (height - heightPoints) / 2
        let displayCenterX = (flipHorizontal ? -1 : 1) * localCenterX
        let displayCenterY = (flipVertical ? -1 : 1) * localCenterY
        let radians = rotationDegrees * .pi / 180
        let cosine = cos(radians), sine = sin(radians)
        let centerDeltaX = cosine * displayCenterX - sine * displayCenterY
        let centerDeltaY = sine * displayCenterX + cosine * displayCenterY
        let oldCenterX = xPoints + widthPoints / 2
        let oldCenterY = yPoints + heightPoints / 2
        let x = min(max(oldCenterX + centerDeltaX - width / 2, -4_000), 4_000)
        let y = min(max(oldCenterY + centerDeltaY - height / 2, -4_000), 4_000)

        // The canvas applies the existing flip and rotation outside the object
        // view. Convert the final center displacement back to that local space
        // so the drag preview exactly matches the values that will be saved.
        guard let localCenterDelta = directLocalVector(
            deltaX: x + width / 2 - oldCenterX,
            deltaY: y + height / 2 - oldCenterY,
            rotationDegrees: rotationDegrees,
            flipHorizontal: flipHorizontal, flipVertical: flipVertical
        ) else { return nil }
        return DirectResizeGeometry(xPoints: x, yPoints: y,
            widthPoints: width, heightPoints: height,
            localOffsetX: localCenterDelta.x + widthPoints / 2 - width / 2,
            localOffsetY: localCenterDelta.y + heightPoints / 2 - height / 2)
    }

    static func directLocalVector(deltaX: Double, deltaY: Double,
                                  rotationDegrees: Double,
                                  flipHorizontal: Bool, flipVertical: Bool)
        -> (x: Double, y: Double)? {
        guard deltaX.isFinite, deltaY.isFinite, rotationDegrees.isFinite else { return nil }
        let radians = rotationDegrees * .pi / 180
        let cosine = cos(radians), sine = sin(radians)
        let rotatedX = cosine * deltaX + sine * deltaY
        let rotatedY = -sine * deltaX + cosine * deltaY
        return ((flipHorizontal ? -1 : 1) * rotatedX,
            (flipVertical ? -1 : 1) * rotatedY)
    }

    static func selection(blocks: [HWPDocumentBlock], selectedID: String?, range: NSRange,
                          layouts: [HWPDocumentPageLayout]) -> Selection? {
        let block = selectedID.flatMap { id in blocks.first { $0.id == id } }
            ?? (blocks.count == 1 && blocks[0].text.isEmpty ? blocks[0] : nil)
        guard let block, HWPImageEditing.supportsInsertion(in: block), block.presentation.list == nil,
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

    static func target(owner: HWPDocumentBlock, object: HWPDocumentCanvasObject,
                       groupChildIndex: Int? = nil) -> Target? {
        guard owner.region.kind == .body else { return nil }
        let objectKind: Kind?, shape: HWPDocumentShape
        switch object.content {
        case .shape(let value):
            guard groupChildIndex == nil else { return nil }
            guard let valueKind = kind(value.geometry) else { return nil }
            objectKind = valueKind; shape = value
        case .group(let shapes):
            if let groupChildIndex {
                guard shapes.indices.contains(groupChildIndex),
                      let valueKind = kind(shapes[groupChildIndex].geometry),
                      shapes[groupChildIndex].localFrame != nil else { return nil }
                objectKind = valueKind
                shape = shapes[groupChildIndex]
            } else {
                guard let value = shapes.first(where: {
                    if case .container = $0.geometry { return false }
                    return true
                }) ?? shapes.first else { return nil }
                objectKind = nil; shape = value
            }
        default: return nil
        }
        let localFrame = groupChildIndex == nil ? nil : shape.localFrame
        let targetWidth = localFrame.map { Double($0.width) } ?? object.placement.widthPoints
        let targetHeight = localFrame.map { Double($0.height) } ?? object.placement.heightPoints
        let pathPoints: [PathPoint]
        switch shape.geometry {
        case .polygon(let points), .curve(let points, _):
            let width = max(targetWidth, 0.01)
            let height = max(targetHeight, 0.01)
            pathPoints = points.map { PathPoint(x: $0.x / width, y: $0.y / height) }
        default: pathPoints = []
        }
        let groupChildCount: Int = if case .group(let shapes) = object.content { shapes.count } else { 0 }
        return Target(ownerID: owner.id, objectID: object.id, groupChildIndex: groupChildIndex,
            groupChildCount: groupChildCount,
            kind: objectKind,
            xPoints: localFrame.map { Double($0.minX) } ?? object.placement.xPoints,
            yPoints: localFrame.map { Double($0.minY) } ?? object.placement.yPoints,
            widthPoints: targetWidth, heightPoints: targetHeight,
            zOrder: groupChildIndex ?? object.placement.zOrder,
            rotationDegrees: groupChildIndex == nil ? object.placement.rotationDegrees : shape.rotationDegrees,
            flipHorizontal: groupChildIndex == nil ? object.placement.flipHorizontal : shape.flipHorizontal,
            flipVertical: groupChildIndex == nil ? object.placement.flipVertical : shape.flipVertical,
            strokeColorRGB: shape.stroke.colorRGB, strokeWidthPoints: shape.stroke.widthPoints,
            strokeStyle: shape.stroke.style, fillColorRGB: shape.fill.colorRGB,
            shadow: shape.shadow.map { Shadow(colorRGB: $0.colorRGB, offsetX: $0.offsetX,
                offsetY: $0.offsetY, opacity: $0.opacity) },
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
            pathPoints: pathPoints, startArrow: shape.stroke.startArrow,
            endArrow: shape.stroke.endArrow)
    }

    private static func kind(_ geometry: HWPDocumentShapeGeometry) -> Kind? {
        switch geometry {
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .line: .line
        case .polygon: .polygon
        case .curve: .connector
        default: nil
        }
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
            let bytes = try HWPShapeEditingWriter.insert(request, into: prepared, ownerIndex: ownerIndex)
            return (prepared, try HWPTableStructureDocument.load(bytes), ownerIndex)
        }.value
        guard changed.blocks.indices.contains(ownerIndex),
              changed.blocks[ownerIndex].canvasObjects.contains(where: { if case .shape = $0.content { return true }; return false }),
              let layout = changed.layouts.first(where: {
                  $0.sectionIndex == HWPPageSetup.sectionIndex(changed.blocks[ownerIndex].sectionPath)
              }) else { throw HWPDocumentEditingError.cannotSave }
        let final = try await finalized(changed: changed, before: prepared.blocks, ownerIndex: ownerIndex,
            minimumHeight: request.heightPoints, layout: layout)
        return .init(document: final, focusedID: final.blocks[ownerIndex].id)
    }

    @MainActor static func applying(_ action: Action, target: Target, source: HWPTableStructureDocument,
                                    drafts: [HWPDocumentBlock]) async throws -> HWPTableStructureDocument.Result {
        guard let ownerIndex = drafts.firstIndex(where: { $0.id == target.ownerID }),
              let current = drafts[ownerIndex].canvasObjects.first(where: { $0.id == target.objectID }),
              let currentTarget = Self.target(owner: drafts[ownerIndex], object: current,
                groupChildIndex: target.groupChildIndex),
              abs(currentTarget.widthPoints - target.widthPoints) < 0.03,
              abs(currentTarget.heightPoints - target.heightPoints) < 0.03,
              abs(currentTarget.xPoints - target.xPoints) < 0.03,
              abs(currentTarget.yPoints - target.yPoints) < 0.03,
              (target.isGroupChild || (current.placement.isInline == target.isInline
                && current.placement.wrap == target.wrap)) else {
            throw HWPDocumentEditingError.staleDocument
        }
        switch action {
        case .delete where target.isGroupChild && !target.canDeleteGroupChild:
            throw HWPDocumentEditingError.unsupportedEdit
        case .moveGroupChild(let offset):
            guard target.isGroupChild, abs(offset) == 1,
                  let index = target.groupChildIndex,
                  (0..<target.groupChildCount).contains(index + offset) else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
        case .ungroup:
            guard target.isGroup, target.groupChildCount > 0 else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
        default: break
        }
        if case .update(let layout) = action {
            guard layout.isValid else { throw HWPDocumentEditingError.limitExceeded }
            if target.kind == .polygon, !(3...32).contains(layout.pathPoints.count) {
                throw HWPDocumentEditingError.limitExceeded
            }
            if target.kind == .connector, !(2...32).contains(layout.pathPoints.count) {
                throw HWPDocumentEditingError.limitExceeded
            }
        }
        let (base, changed) = try await Task.detached(priority: .userInitiated) {
            let base = source.blocks == drafts
                ? source
                : try HWPTableStructureDocument.load(source.serialized(drafts))
            guard base.blocks.indices.contains(ownerIndex),
                  base.blocks[ownerIndex].canvasObjects.contains(where: { $0.id == target.objectID }) else {
                throw HWPDocumentEditingError.staleDocument
            }
            let data = try HWPShapeEditingWriter.apply(action, target: target, to: base, ownerIndex: ownerIndex)
            return (base, try HWPTableStructureDocument.load(data))
        }.value
        if target.isGroupChild {
            guard changed.blocks.indices.contains(ownerIndex) else {
                throw HWPDocumentEditingError.cannotSave
            }
            let expectedCount = if case .delete = action {
                target.groupChildCount - 1
            } else { target.groupChildCount }
            let updated = changed.blocks[ownerIndex].canvasObjects.first(where: { $0.id == target.objectID })
            let shapes: [HWPDocumentShape]? = if let updated, case .group(let values) = updated.content {
                values
            } else { nil }
            if case .delete = action, expectedCount == 1, shapes == nil {
                guard changed.blocks[ownerIndex].canvasObjects.contains(where: {
                    if case .shape = $0.content { return true }
                    return false
                }) else { throw HWPDocumentEditingError.cannotSave }
                return .init(document: changed, focusedID: changed.blocks[ownerIndex].id)
            }
            guard let updated, let shapes, shapes.count == expectedCount else {
                throw HWPDocumentEditingError.cannotSave
            }
            if case .moveGroupChild(let offset) = action,
               Self.target(owner: changed.blocks[ownerIndex], object: updated,
                 groupChildIndex: (target.groupChildIndex ?? 0) + offset) == nil {
                throw HWPDocumentEditingError.cannotSave
            }
            return .init(document: changed, focusedID: changed.blocks[ownerIndex].id)
        }
        if case .ungroup = action {
            let beforeGroupCount = drafts[ownerIndex].canvasObjects.filter {
                if case .group = $0.content { return true }
                return false
            }.count
            let beforeShapeCount = drafts[ownerIndex].canvasObjects.filter {
                if case .shape = $0.content { return true }
                return false
            }.count
            guard changed.blocks.indices.contains(ownerIndex),
                  changed.blocks[ownerIndex].canvasObjects.filter({
                      if case .group = $0.content { return true }
                      return false
                  }).count == beforeGroupCount - 1,
                  changed.blocks[ownerIndex].canvasObjects.filter({
                      if case .shape = $0.content { return true }
                      return false
                  }).count >= beforeShapeCount + target.groupChildCount else {
                throw HWPDocumentEditingError.cannotSave
            }
            return .init(document: changed, focusedID: changed.blocks[ownerIndex].id)
        }
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
        if case .update(let layout) = action, !affectsFlow(layout, comparedWith: target) {
            return .init(document: changed, focusedID: changed.blocks[ownerIndex].id)
        }
        guard changed.blocks.indices.contains(ownerIndex),
              let page = changed.layouts.first(where: {
                  $0.sectionIndex == HWPPageSetup.sectionIndex(changed.blocks[ownerIndex].sectionPath)
              }) else { throw HWPDocumentEditingError.cannotSave }
        let minimum: Double = switch action {
        case .update(let value):
            value.wrap == .behindText || value.wrap == .inFrontOfText
                ? 0 : max(0, value.yPoints) + value.heightPoints
        case .delete, .moveGroupChild, .ungroup: 0
        }
        let final = try await finalized(changed: changed, before: base.blocks, ownerIndex: ownerIndex,
            minimumHeight: minimum, layout: page)
        if case .delete = action,
           final.blocks[ownerIndex].canvasObjects.contains(where: { $0.id == target.objectID }) {
            throw HWPDocumentEditingError.cannotSave
        }
        return .init(document: final, focusedID: final.blocks[ownerIndex].id)
    }

    @MainActor static func grouping(_ request: GroupRequest, source: HWPTableStructureDocument,
                                    drafts: [HWPDocumentBlock]) async throws -> HWPTableStructureDocument.Result {
        guard request.isValid,
              let ownerIndex = drafts.firstIndex(where: { $0.id == request.ownerID }) else {
            throw HWPDocumentEditingError.staleDocument
        }
        let owner = drafts[ownerIndex]
        let selected = request.objectIDs.compactMap { id in owner.canvasObjects.first(where: { $0.id == id }) }
        guard selected.count == request.objectIDs.count,
              selected.allSatisfy({ object in
                  guard case .shape = object.content else { return false }
                  return target(owner: owner, object: object) != nil
              }) else { throw HWPDocumentEditingError.unsupportedEdit }
        let (beforeGroupCount, beforeShapeCount) = owner.canvasObjects.reduce(into: (0, 0)) { value, object in
            if case .group = object.content { value.0 += 1 }
            if case .shape = object.content { value.1 += 1 }
        }
        let changed = try await Task.detached(priority: .userInitiated) {
            let base = try HWPTableStructureDocument.load(source.serialized(drafts))
            let data = try HWPShapeEditingWriter.group(request, in: base, ownerIndex: ownerIndex)
            return try HWPTableStructureDocument.load(data)
        }.value
        guard changed.blocks.indices.contains(ownerIndex) else {
            throw HWPDocumentEditingError.cannotSave
        }
        let changedOwner = changed.blocks[ownerIndex]
        let groupCount = changedOwner.canvasObjects.filter { if case .group = $0.content { return true }; return false }.count
        let shapeCount = changedOwner.canvasObjects.filter { if case .shape = $0.content { return true }; return false }.count
        guard groupCount == beforeGroupCount + 1,
              shapeCount == beforeShapeCount - request.objectIDs.count else {
            throw HWPDocumentEditingError.cannotSave
        }
        return .init(document: changed, focusedID: changedOwner.id)
    }

    @MainActor static func arranging(_ request: ArrangementRequest,
                                     source: HWPTableStructureDocument,
                                     drafts: [HWPDocumentBlock]) async throws
        -> HWPTableStructureDocument.Result {
        guard request.isValid,
              let ownerIndex = drafts.firstIndex(where: { $0.id == request.ownerID }) else {
            throw HWPDocumentEditingError.staleDocument
        }
        let owner = drafts[ownerIndex]
        let objects = request.objectIDs.compactMap { id in
            owner.canvasObjects.first(where: { $0.id == id })
        }
        guard objects.count == request.objectIDs.count,
              objects.allSatisfy({ if case .shape = $0.content { return true }; return false }) else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        let targets = try objects.map { object -> Target in
            guard let value = target(owner: owner, object: object) else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            return value
        }
        let positions = arrangedPositions(targets, arrangement: request.arrangement)
        guard positions.count == targets.count else { throw HWPDocumentEditingError.unsupportedEdit }
        let changed = try await Task.detached(priority: .userInitiated) {
            var document = try HWPTableStructureDocument.load(source.serialized(drafts))
            for index in targets.indices {
                let target = targets[index]
                let layout = arrangementLayout(target, position: positions[index],
                    arrangement: request.arrangement)
                let data = try HWPShapeEditingWriter.apply(.update(layout), target: target,
                    to: document, ownerIndex: ownerIndex)
                document = try HWPTableStructureDocument.load(data)
            }
            return document
        }.value
        guard changed.blocks.indices.contains(ownerIndex) else {
            throw HWPDocumentEditingError.cannotSave
        }
        let changedOwner = changed.blocks[ownerIndex]
        for index in targets.indices {
            guard let object = changedOwner.canvasObjects.first(where: { $0.id == targets[index].objectID }),
                  let changedTarget = target(owner: changedOwner, object: object) else {
                throw HWPDocumentEditingError.cannotSave
            }
            if request.arrangement == .alignInside || request.arrangement == .alignOutside {
                let alignment: HWPDocumentRelativeAlignment = request.arrangement == .alignInside
                    ? .inside : .outside
                guard !changedTarget.isInline, changedTarget.horizontalReference == .page,
                      changedTarget.horizontalAlignment == alignment,
                      abs(changedTarget.yPoints - positions[index].y) < 0.03 else {
                    throw HWPDocumentEditingError.cannotSave
                }
            } else if abs(changedTarget.xPoints - positions[index].x) >= 0.03
                        || abs(changedTarget.yPoints - positions[index].y) >= 0.03 {
                throw HWPDocumentEditingError.cannotSave
            }
        }
        return .init(document: changed, focusedID: changedOwner.id)
    }

    @MainActor static func flipping(_ request: FlipRequest,
                                    source: HWPTableStructureDocument,
                                    drafts: [HWPDocumentBlock]) async throws
        -> HWPTableStructureDocument.Result {
        guard request.isValid,
              let ownerIndex = drafts.firstIndex(where: { $0.id == request.ownerID }) else {
            throw HWPDocumentEditingError.staleDocument
        }
        let owner = drafts[ownerIndex]
        let selectedIDs = Set(request.objectIDs)
        let objects = owner.canvasObjects.filter { selectedIDs.contains($0.id) }
        guard objects.count == request.objectIDs.count,
              objects.allSatisfy({ if case .shape = $0.content { return true }; return false }) else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        let targets = try objects.map { object -> Target in
            guard let value = target(owner: owner, object: object) else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            return value
        }
        let changed = try await Task.detached(priority: .userInitiated) {
            var document = try HWPTableStructureDocument.load(source.serialized(drafts))
            for target in targets {
                let layout = arrangementLayout(target,
                    position: CGPoint(x: target.xPoints, y: target.yPoints),
                    flipHorizontal: request.flip == .horizontal ? !target.flipHorizontal : target.flipHorizontal,
                    flipVertical: request.flip == .vertical ? !target.flipVertical : target.flipVertical)
                let data = try HWPShapeEditingWriter.apply(.update(layout), target: target,
                    to: document, ownerIndex: ownerIndex)
                document = try HWPTableStructureDocument.load(data)
            }
            return document
        }.value
        guard changed.blocks.indices.contains(ownerIndex) else {
            throw HWPDocumentEditingError.cannotSave
        }
        let changedOwner = changed.blocks[ownerIndex]
        for target in targets {
            guard let object = changedOwner.canvasObjects.first(where: { $0.id == target.objectID }),
                  let changedTarget = self.target(owner: changedOwner, object: object),
                  changedTarget.flipHorizontal == (request.flip == .horizontal ? !target.flipHorizontal : target.flipHorizontal),
                  changedTarget.flipVertical == (request.flip == .vertical ? !target.flipVertical : target.flipVertical) else {
                throw HWPDocumentEditingError.cannotSave
            }
        }
        return .init(document: changed, focusedID: changedOwner.id)
    }

    @MainActor static func matchingSizes(_ request: SizeMatchRequest,
                                         source: HWPTableStructureDocument,
                                         drafts: [HWPDocumentBlock]) async throws
        -> HWPTableStructureDocument.Result {
        guard request.isValid,
              let ownerIndex = drafts.firstIndex(where: { $0.id == request.ownerID }) else {
            throw HWPDocumentEditingError.staleDocument
        }
        let owner = drafts[ownerIndex]
        let selectedIDs = Set(request.objectIDs)
        let objects = owner.canvasObjects.filter { selectedIDs.contains($0.id) }
        guard objects.count == request.objectIDs.count,
              objects.allSatisfy({ if case .shape = $0.content { return true }; return false }) else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        let targets = try objects.map { object -> Target in
            guard let value = target(owner: owner, object: object) else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            return value
        }
        guard let reference = targets.first else { throw HWPDocumentEditingError.unsupportedEdit }
        let sizes = targets.map { target -> CGSize in
            switch request.match {
            case .width: CGSize(width: reference.widthPoints, height: target.heightPoints)
            case .height: CGSize(width: target.widthPoints, height: reference.heightPoints)
            case .both: CGSize(width: reference.widthPoints, height: reference.heightPoints)
            }
        }
        let changed = try await Task.detached(priority: .userInitiated) {
            var document = try HWPTableStructureDocument.load(source.serialized(drafts))
            for index in targets.indices {
                let target = targets[index]
                let layout = arrangementLayout(target, position: CGPoint(x: target.xPoints,
                    y: target.yPoints), size: sizes[index])
                let data = try HWPShapeEditingWriter.apply(.update(layout), target: target,
                    to: document, ownerIndex: ownerIndex)
                document = try HWPTableStructureDocument.load(data)
            }
            return document
        }.value
        guard changed.blocks.indices.contains(ownerIndex) else {
            throw HWPDocumentEditingError.cannotSave
        }
        let changedOwner = changed.blocks[ownerIndex]
        for index in targets.indices {
            guard let object = changedOwner.canvasObjects.first(where: { $0.id == targets[index].objectID }),
                  let changedTarget = target(owner: changedOwner, object: object),
                  abs(changedTarget.widthPoints - Double(sizes[index].width)) < 0.03,
                  abs(changedTarget.heightPoints - Double(sizes[index].height)) < 0.03 else {
                throw HWPDocumentEditingError.cannotSave
            }
        }
        return .init(document: changed, focusedID: changedOwner.id)
    }

    @MainActor static func batchEditing(_ request: BatchRequest,
                                        source: HWPTableStructureDocument,
                                        drafts: [HWPDocumentBlock]) async throws
        -> HWPTableStructureDocument.Result {
        guard request.isValid,
              let ownerIndex = drafts.firstIndex(where: { $0.id == request.ownerID }) else {
            throw HWPDocumentEditingError.staleDocument
        }
        let owner = drafts[ownerIndex]
        let selected = request.objectIDs.compactMap { id in
            owner.canvasObjects.first(where: { $0.id == id })
        }
        guard selected.count == request.objectIDs.count,
              selected.allSatisfy({ object in
                  guard case .shape = object.content else { return false }
                  return target(owner: owner, object: object) != nil
              }), request.action != .duplicate || owner.canvasObjects.count + selected.count <= 128 else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        let (base, changed) = try await Task.detached(priority: .userInitiated) {
            let base = try HWPTableStructureDocument.load(source.serialized(drafts))
            let data = try HWPShapeEditingWriter.batch(request, in: base, ownerIndex: ownerIndex)
            return (base, try HWPTableStructureDocument.load(data))
        }.value
        guard changed.blocks.indices.contains(ownerIndex) else {
            throw HWPDocumentEditingError.cannotSave
        }
        let beforeCount = owner.canvasObjects.filter { if case .shape = $0.content { return true }; return false }.count
        let expectedCount = switch request.action {
        case .duplicate: beforeCount + selected.count
        case .delete: beforeCount - selected.count
        }
        let changedCount = changed.blocks[ownerIndex].canvasObjects.filter {
            if case .shape = $0.content { return true }; return false
        }.count
        guard changedCount == expectedCount,
              let page = changed.layouts.first(where: {
                  $0.sectionIndex == HWPPageSetup.sectionIndex(changed.blocks[ownerIndex].sectionPath)
              }) else { throw HWPDocumentEditingError.cannotSave }
        let minimumHeight = changed.blocks[ownerIndex].canvasObjects.reduce(0.0) { value, object in
            guard object.placement.wrap != .behindText,
                  object.placement.wrap != .inFrontOfText else { return value }
            return max(value, max(0, object.placement.yPoints) + object.placement.heightPoints)
        }
        let final = try await finalized(changed: changed, before: base.blocks, ownerIndex: ownerIndex,
            minimumHeight: minimumHeight, layout: page)
        return .init(document: final, focusedID: final.blocks[ownerIndex].id)
    }

    private static func arrangedPositions(_ targets: [Target], arrangement: Arrangement)
        -> [CGPoint] {
        guard let first = targets.first else { return [] }
        let bounds = targets.dropFirst().reduce(CGRect(x: first.xPoints, y: first.yPoints,
            width: first.widthPoints, height: first.heightPoints)) { value, target in
            value.union(CGRect(x: target.xPoints, y: target.yPoints,
                width: target.widthPoints, height: target.heightPoints))
        }
        var result = targets.map { CGPoint(x: $0.xPoints, y: $0.yPoints) }
        switch arrangement {
        case .alignLeft:
            for index in result.indices { result[index].x = bounds.minX }
        case .alignCenter:
            for index in result.indices { result[index].x = bounds.midX - targets[index].widthPoints / 2 }
        case .alignRight:
            for index in result.indices { result[index].x = bounds.maxX - targets[index].widthPoints }
        case .alignInside, .alignOutside:
            for index in result.indices { result[index].x = 0 }
        case .alignTop:
            for index in result.indices { result[index].y = bounds.minY }
        case .alignMiddle:
            for index in result.indices { result[index].y = bounds.midY - targets[index].heightPoints / 2 }
        case .alignBottom:
            for index in result.indices { result[index].y = bounds.maxY - targets[index].heightPoints }
        case .distributeHorizontally:
            let order = targets.indices.sorted { targets[$0].xPoints < targets[$1].xPoints }
            let occupied = order.reduce(0.0) { $0 + targets[$1].widthPoints }
            let gap = (bounds.width - occupied) / Double(max(order.count - 1, 1))
            var cursor = bounds.minX
            for index in order { result[index].x = cursor; cursor += targets[index].widthPoints + gap }
        case .distributeVertically:
            let order = targets.indices.sorted { targets[$0].yPoints < targets[$1].yPoints }
            let occupied = order.reduce(0.0) { $0 + targets[$1].heightPoints }
            let gap = (bounds.height - occupied) / Double(max(order.count - 1, 1))
            var cursor = bounds.minY
            for index in order { result[index].y = cursor; cursor += targets[index].heightPoints + gap }
        }
        return result
    }

    private static func arrangementLayout(_ target: Target, position: CGPoint,
                                          size: CGSize? = nil,
                                          arrangement: Arrangement? = nil,
                                          flipHorizontal: Bool? = nil,
                                          flipVertical: Bool? = nil) -> Layout {
        let facing = arrangement == .alignInside || arrangement == .alignOutside
        return Layout(xPoints: position.x, yPoints: position.y,
            widthPoints: size.map { Double($0.width) } ?? target.widthPoints,
            heightPoints: size.map { Double($0.height) } ?? target.heightPoints,
            zOrder: target.zOrder, rotationDegrees: target.rotationDegrees,
            flipHorizontal: flipHorizontal ?? target.flipHorizontal,
            flipVertical: flipVertical ?? target.flipVertical,
            strokeColorRGB: target.strokeColorRGB,
            strokeWidthPoints: target.strokeWidthPoints, strokeStyle: target.strokeStyle,
            fillColorRGB: target.fillColorRGB, shadow: target.shadow,
            isInline: facing ? false : target.isInline,
            horizontalReference: facing ? .page : target.horizontalReference,
            verticalReference: target.verticalReference,
            horizontalAlignment: arrangement == .alignInside ? .inside
                : (arrangement == .alignOutside ? .outside : target.horizontalAlignment),
            verticalAlignment: target.verticalAlignment, wrap: target.wrap,
            marginLeftPoints: target.marginLeftPoints,
            marginRightPoints: target.marginRightPoints,
            marginTopPoints: target.marginTopPoints,
            marginBottomPoints: target.marginBottomPoints,
            pathPoints: target.pathPoints, startArrow: target.startArrow,
            endArrow: target.endArrow)
    }

    private static func affectsFlow(_ layout: Layout, comparedWith target: Target) -> Bool {
        let values = [
            (layout.xPoints, target.xPoints), (layout.yPoints, target.yPoints),
            (layout.widthPoints, target.widthPoints), (layout.heightPoints, target.heightPoints),
            (layout.marginLeftPoints, target.marginLeftPoints),
            (layout.marginRightPoints, target.marginRightPoints),
            (layout.marginTopPoints, target.marginTopPoints),
            (layout.marginBottomPoints, target.marginBottomPoints)
        ]
        return values.contains { abs($0.0 - $0.1) >= 0.005 }
            || layout.isInline != target.isInline
            || layout.horizontalReference != target.horizontalReference
            || layout.verticalReference != target.verticalReference
            || layout.horizontalAlignment != target.horizontalAlignment
            || layout.verticalAlignment != target.verticalAlignment
            || layout.wrap != target.wrap
    }

    private static func cellMinimumHeight(_ action: Action) -> Double {
        guard case .update(let layout) = action,
              layout.wrap != .behindText,
              layout.wrap != .inFrontOfText else { return 0 }
        let radians = layout.rotationDegrees * .pi / 180
        let rotatedHeight = abs(sin(radians)) * layout.widthPoints
            + abs(cos(radians)) * layout.heightPoints
        let bottom = layout.yPoints + layout.heightPoints / 2
            + rotatedHeight / 2
        return max(layout.heightPoints, bottom)
            + layout.marginTopPoints + layout.marginBottomPoints
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
            width: max(bodyWidth, 1), startY: y,
            pageHeight: layout.heightPoints - layout.topMarginPoints - layout.bottomMarginPoints,
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
