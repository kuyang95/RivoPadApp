import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension HWPDocumentObjectPlacement {
    public nonisolated func inlineBaselineOffset(in line: HWPDocumentLineLayout?) -> Double {
        guard isInline, !inlineOriginIsResolved,
              let line, line.baselineAlignment == .font else { return 0 }
        // HWP's font-aligned inline object has its baseline at 85% of its
        // height, just as the cached line metrics do for an object-only line.
        return max(0, line.baselinePoints - heightPoints * 0.85)
    }
}

public nonisolated enum HWPDocumentLineBaselineAlignment: Int, Hashable, Sendable {
    case font, top, center, bottom
}

public nonisolated struct HWPDocumentPageNumberStyle: Hashable, Sendable {
    public let position: String
    public let sideCharacter: String
    public let startsAt: Int?

    public func text(pageNumber: Int, sectionPageIndex: Int) -> String {
        let number = startsAt.map { $0 + sectionPageIndex } ?? pageNumber
        return sideCharacter.isEmpty ? "\(number)" : "\(sideCharacter) \(number) \(sideCharacter)"
    }

    public init(position: String, sideCharacter: String, startsAt: Int? = nil) {
        self.position = position
        self.sideCharacter = sideCharacter
        self.startsAt = startsAt
    }
}

/// Page-coordinate information cached by HWP writers for one laid-out line.
/// Values are converted from HWPUNIT (1/100 point) at the parser boundary.
public nonisolated struct HWPDocumentListMarker: Hashable, Sendable {
    public let run: HWPDocumentTextRun
    public let reservedWidthPoints: Double
    public var isLegacyCircle = false

    public init(run: HWPDocumentTextRun, reservedWidthPoints: Double, isLegacyCircle: Bool = false) {
        self.run = run
        self.reservedWidthPoints = reservedWidthPoints
        self.isLegacyCircle = isLegacyCircle
    }
}

public nonisolated struct HWPDocumentLineLayout: Hashable, Sendable, Identifiable {
    public let id: String
    public let startCharacter: Int
    public let verticalPositionPoints: Double
    public let lineHeightPoints: Double
    public let textHeightPoints: Double
    public let baselinePoints: Double
    public let lineSpacingPoints: Double
    public let columnStartPoints: Double
    public let widthPoints: Double
    public let flags: UInt32
    public let text: String
    public let textRuns: [HWPDocumentTextRun]
    public var baselineAlignment: HWPDocumentLineBaselineAlignment = .font
    public var textInsetPoints: Double = 0
    public var listMarker: HWPDocumentListMarker? = nil
    public var showsListMarker: Bool = true
    public var endsParagraph: Bool? = nil

    public var startsPage: Bool { flags & 0x0000_0001 != 0 }
    public var startsColumn: Bool { flags & 0x0000_0002 != 0 }
    public var isEmpty: Bool { flags & 0x0001_0000 != 0 }

    public init(id: String, startCharacter: Int, verticalPositionPoints: Double, lineHeightPoints: Double, textHeightPoints: Double, baselinePoints: Double, lineSpacingPoints: Double, columnStartPoints: Double, widthPoints: Double, flags: UInt32, text: String, textRuns: [HWPDocumentTextRun], baselineAlignment: HWPDocumentLineBaselineAlignment = .font, textInsetPoints: Double = 0, listMarker: HWPDocumentListMarker? = nil, showsListMarker: Bool = true, endsParagraph: Bool? = nil) {
        self.id = id
        self.startCharacter = startCharacter
        self.verticalPositionPoints = verticalPositionPoints
        self.lineHeightPoints = lineHeightPoints
        self.textHeightPoints = textHeightPoints
        self.baselinePoints = baselinePoints
        self.lineSpacingPoints = lineSpacingPoints
        self.columnStartPoints = columnStartPoints
        self.widthPoints = widthPoints
        self.flags = flags
        self.text = text
        self.textRuns = textRuns
        self.baselineAlignment = baselineAlignment
        self.textInsetPoints = textInsetPoints
        self.listMarker = listMarker
        self.showsListMarker = showsListMarker
        self.endsParagraph = endsParagraph
    }
}

public nonisolated enum HWPDocumentLayoutReference: Int, Hashable, Sendable {
    case paper
    case page
    case column
    case paragraph
    case absolute
}

public nonisolated enum HWPDocumentRelativeAlignment: Int, Hashable, Sendable {
    case start
    case center
    case end
    case inside
    case outside
}

public nonisolated enum HWPDocumentObjectWrap: Int, Hashable, Sendable {
    case square
    case tight
    case through
    case topAndBottom
    case behindText
    case inFrontOfText
}

public nonisolated struct HWPDocumentObjectPlacement: Hashable, Sendable {
    public let xPoints: Double
    public let yPoints: Double
    public let widthPoints: Double
    public var heightPoints: Double
    public let zOrder: Int
    public let rotationDegrees: Double
    public let flipHorizontal: Bool
    public let flipVertical: Bool
    public let isInline: Bool
    public let horizontalReference: HWPDocumentLayoutReference
    public let verticalReference: HWPDocumentLayoutReference
    public let horizontalAlignment: HWPDocumentRelativeAlignment
    public let verticalAlignment: HWPDocumentRelativeAlignment
    public let wrap: HWPDocumentObjectWrap
    public let marginLeftPoints: Double
    public let marginRightPoints: Double
    public let marginTopPoints: Double
    public let marginBottomPoints: Double
    public let inlineOriginIsResolved: Bool
    public var sourceCharacterPosition: Int? = nil
    public var inlineLeadingPoints: Double = 0

    public init(
        xPoints: Double = 0,
        yPoints: Double = 0,
        widthPoints: Double = 120,
        heightPoints: Double = 60,
        zOrder: Int = 0,
        rotationDegrees: Double = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        isInline: Bool = false,
        horizontalReference: HWPDocumentLayoutReference = .paragraph,
        verticalReference: HWPDocumentLayoutReference = .paragraph,
        horizontalAlignment: HWPDocumentRelativeAlignment = .start,
        verticalAlignment: HWPDocumentRelativeAlignment = .start,
        wrap: HWPDocumentObjectWrap = .square,
        marginLeftPoints: Double = 0,
        marginRightPoints: Double = 0,
        marginTopPoints: Double = 0,
        marginBottomPoints: Double = 0,
        inlineOriginIsResolved: Bool = false
    ) {
        self.xPoints = min(max(xPoints, -4_000), 4_000)
        self.yPoints = min(max(yPoints, -4_000), 4_000)
        self.widthPoints = min(max(abs(widthPoints), 1), 4_000)
        self.heightPoints = min(max(abs(heightPoints), 1), 4_000)
        self.zOrder = min(max(zOrder, -100_000), 100_000)
        self.rotationDegrees = rotationDegrees.truncatingRemainder(dividingBy: 360)
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.isInline = isInline
        self.horizontalReference = horizontalReference
        self.verticalReference = verticalReference
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.wrap = wrap
        self.marginLeftPoints = min(max(marginLeftPoints, 0), 720)
        self.marginRightPoints = min(max(marginRightPoints, 0), 720)
        self.marginTopPoints = min(max(marginTopPoints, 0), 720)
        self.marginBottomPoints = min(max(marginBottomPoints, 0), 720)
        self.inlineOriginIsResolved = inlineOriginIsResolved
    }

    public func inlineOffset(lineWidth: Double, paragraphAlignment: HWPParagraphAlignment) -> CGPoint {
        // HWPX already resolves character-like object offsets at import.
        // HWP5 keeps the raw offsets and resolves them against its cached line.
        if inlineOriginIsResolved { return CGPoint(x: xPoints, y: yPoints) }
        let remaining = max(lineWidth - widthPoints - marginLeftPoints - marginRightPoints, 0)
        let alignmentOffset = paragraphAlignment == .centered ? remaining / 2
            : paragraphAlignment == .trailing ? remaining : 0
        return CGPoint(x: xPoints + marginLeftPoints + alignmentOffset,
            y: yPoints + marginTopPoints)
    }
}

public nonisolated struct HWPDocumentPoint: Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = min(max(x, -8_000), 8_000)
        self.y = min(max(y, -8_000), 8_000)
    }
}

public nonisolated struct HWPDocumentStroke: Hashable, Sendable {
    public let colorRGB: UInt32
    public let widthPoints: Double
    public let style: Int
    public let startArrow: Int
    public let endArrow: Int

    public init(
        colorRGB: UInt32 = 0,
        widthPoints: Double = 0.75,
        style: Int = 1,
        startArrow: Int = 0,
        endArrow: Int = 0
    ) {
        self.colorRGB = colorRGB & 0x00FF_FFFF
        self.widthPoints = min(max(widthPoints, 0.25), 32)
        self.style = min(max(style, 0), 63)
        self.startArrow = min(max(startArrow, 0), 63)
        self.endArrow = min(max(endArrow, 0), 63)
    }
}

public nonisolated struct HWPDocumentFill: Hashable, Sendable {
    public let colorRGB: UInt32?
    public let patternColorRGB: UInt32?
    public let pattern: Int?

    public static let none = HWPDocumentFill()

    public init(
        colorRGB: UInt32? = nil,
        patternColorRGB: UInt32? = nil,
        pattern: Int? = nil
    ) {
        self.colorRGB = colorRGB.map { $0 & 0x00FF_FFFF }
        self.patternColorRGB = patternColorRGB.map { $0 & 0x00FF_FFFF }
        self.pattern = pattern
    }
}

public nonisolated enum HWPDocumentShapeGeometry: Hashable, Sendable {
    case line(start: HWPDocumentPoint, end: HWPDocumentPoint)
    case rectangle(cornerRadiusPercent: Double, points: [HWPDocumentPoint])
    case ellipse(center: HWPDocumentPoint, axis1: HWPDocumentPoint, axis2: HWPDocumentPoint)
    case arc(center: HWPDocumentPoint, axis1: HWPDocumentPoint, axis2: HWPDocumentPoint, kind: Int)
    case polygon(points: [HWPDocumentPoint])
    case curve(points: [HWPDocumentPoint], curvedSegments: [Bool])
    case container
    case unknown
}

public nonisolated struct HWPDocumentShape: Hashable, Sendable {
    public let geometry: HWPDocumentShapeGeometry
    public let stroke: HWPDocumentStroke
    public let fill: HWPDocumentFill
    public let localFrame: CGRect?
    public let rotationDegrees: Double
    public let flipHorizontal: Bool
    public let flipVertical: Bool
    public let shadow: HWPDocumentShapeShadow?

    public init(
        geometry: HWPDocumentShapeGeometry,
        stroke: HWPDocumentStroke,
        fill: HWPDocumentFill,
        localFrame: CGRect? = nil,
        rotationDegrees: Double = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        shadow: HWPDocumentShapeShadow? = nil
    ) {
        self.geometry = geometry
        self.stroke = stroke
        self.fill = fill
        self.localFrame = localFrame
        self.rotationDegrees = rotationDegrees
            .truncatingRemainder(dividingBy: 360)
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.shadow = shadow
    }
}

public nonisolated struct HWPDocumentShapeShadow: Hashable, Sendable {
    public let kind: Int
    public let colorRGB: UInt32
    public let offsetX: Double
    public let offsetY: Double
    public let opacity: Double

    public var offset: CGSize {
        CGSize(width: [1, 3, 5, 7].contains(kind) ? -abs(offsetX) : abs(offsetX),
            height: [1, 2, 5, 6].contains(kind) ? -abs(offsetY) : abs(offsetY))
    }

    public init(kind: Int, colorRGB: UInt32, offsetX: Double, offsetY: Double, opacity: Double) {
        self.kind = kind
        self.colorRGB = colorRGB
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.opacity = opacity
    }
}

public nonisolated struct HWPDocumentEquation: Hashable, Sendable {
    public let script: String
    public let fontSizePoints: Double
    public let colorRGB: UInt32
    public let baselinePercent: Double
    public let fontName: String?

    public init(
        script: String,
        fontSizePoints: Double,
        colorRGB: UInt32,
        baselinePercent: Double,
        fontName: String?
    ) {
        self.script = script
        self.fontSizePoints = min(max(fontSizePoints, 6), 144)
        self.colorRGB = colorRGB & 0x00FF_FFFF
        self.baselinePercent = min(max(baselinePercent, 0), 100)
        self.fontName = fontName
    }
}

public nonisolated enum HWPDocumentChartKind: String, Hashable, Sendable {
    case bar
    case line
    case pie
    case area
    case scatter
    case radar
    case unknown
}

public nonisolated struct HWPDocumentChartSeries: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let values: [Double]
    public let colorRGB: UInt32?

    public init(id: String, name: String, values: [Double], colorRGB: UInt32? = nil) {
        self.id = id
        self.name = name
        self.values = values
        self.colorRGB = colorRGB
    }
}

/// A legacy Windows Metafile embedded in an OLE presentation stream. The
/// renderer supports the compact drawing subset used by HWP 5 chart previews.
public nonisolated struct HWPDocumentMetafile: Hashable, Sendable {
    public let data: Data
    public let widthLogical: Int
    public let heightLogical: Int

    public init(data: Data, widthLogical: Int, heightLogical: Int) {
        self.data = data
        self.widthLogical = widthLogical
        self.heightLogical = heightLogical
    }
}

public nonisolated struct HWPDocumentChart: Hashable, Sendable {
    public let kind: HWPDocumentChartKind
    public let title: String?
    public let categories: [String]
    public let series: [HWPDocumentChartSeries]
    public let previewImage: HWPDocumentImage?
    public let previewMetafile: HWPDocumentMetafile?

    public var hasRenderableData: Bool {
        series.contains { !$0.values.isEmpty }
    }

    public init(kind: HWPDocumentChartKind, title: String? = nil, categories: [String], series: [HWPDocumentChartSeries], previewImage: HWPDocumentImage? = nil, previewMetafile: HWPDocumentMetafile? = nil) {
        self.kind = kind
        self.title = title
        self.categories = categories
        self.series = series
        self.previewImage = previewImage
        self.previewMetafile = previewMetafile
    }
}

public nonisolated enum HWPDocumentCanvasContent: Hashable, Sendable {
    case shape(HWPDocumentShape)
    case group([HWPDocumentShape])
    case image(HWPDocumentImage)
    case equation(HWPDocumentEquation)
    case chart(HWPDocumentChart)
    case unsupported(String)
}

public nonisolated struct HWPDocumentTextContainerLayout: Hashable, Sendable {
    public let left: Double, right: Double, top: Double, bottom: Double
    public let verticalAlignment: HWPDocumentRelativeAlignment
    public var localFrame: CGRect? = nil

    public init(left: Double, right: Double, top: Double, bottom: Double, verticalAlignment: HWPDocumentRelativeAlignment, localFrame: CGRect? = nil) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
        self.verticalAlignment = verticalAlignment
        self.localFrame = localFrame
    }
}

public nonisolated struct HWPDocumentCanvasObject: Hashable, Sendable, Identifiable {
    public let id: String
    public let placement: HWPDocumentObjectPlacement
    public let content: HWPDocumentCanvasContent
    public let description: String?
    public let textContainerID: String?
    public let repeatsOnEveryPage: Bool
    public let textContainerLayout: HWPDocumentTextContainerLayout?
    /// The child coordinate system must survive edits that change the children's union.
    /// If absent, older documents use the original union as before.
    public let groupCoordinateFrame: CGRect?

    public var groupChildBounds: CGRect? {
        guard case .group(let shapes) = content else { return nil }
        if let groupCoordinateFrame, groupCoordinateFrame.width > 0,
           groupCoordinateFrame.height > 0 { return groupCoordinateFrame }
        if let container = shapes.first(where: {
            if case .container = $0.geometry { return true }; return false
        })?.localFrame, container.width > 0, container.height > 0 { return container }
        let frames = shapes.compactMap { shape -> CGRect? in
            if case .container = shape.geometry { return nil }
            return shape.localFrame
        }
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    public var groupedTextFrame: CGRect? {
        guard case .group(let shapes) = content,
              let frame = textContainerLayout?.localFrame else { return nil }
        guard let bounds = groupChildBounds else { return nil }
        let scaleX = placement.widthPoints / max(bounds.width, 1)
        let scaleY = placement.heightPoints / max(bounds.height, 1)
        return CGRect(x: (frame.minX - bounds.minX) * scaleX,
            y: (frame.minY - bounds.minY) * scaleY,
            width: frame.width * scaleX, height: frame.height * scaleY)
    }

    public init(
        id: String,
        placement: HWPDocumentObjectPlacement,
        content: HWPDocumentCanvasContent,
        description: String? = nil,
        textContainerID: String? = nil,
        repeatsOnEveryPage: Bool = false,
        textContainerLayout: HWPDocumentTextContainerLayout? = nil,
        groupCoordinateFrame: CGRect? = nil
    ) {
        self.id = id
        self.placement = placement
        self.content = content
        self.description = description
        self.textContainerID = textContainerID
        self.repeatsOnEveryPage = repeatsOnEveryPage
        self.textContainerLayout = textContainerLayout
        self.groupCoordinateFrame = groupCoordinateFrame
    }
}

public nonisolated struct HWPDocumentColumn: Hashable, Sendable {
    public let xPoints: Double
    public let widthPoints: Double

    public init(xPoints: Double, widthPoints: Double) {
        self.xPoints = xPoints
        self.widthPoints = widthPoints
    }
}

public nonisolated struct HWPDocumentColumnLayout: Hashable, Sendable {
    public let columns: [HWPDocumentColumn]
    public let gapPoints: Double
    public let separator: HWPDocumentBorderLine?

    public static let single = HWPDocumentColumnLayout(
        columns: [],
        gapPoints: 0,
        separator: nil
    )

    public var count: Int { max(columns.count, 1) }

    public init(columns: [HWPDocumentColumn], gapPoints: Double, separator: HWPDocumentBorderLine? = nil) {
        self.columns = columns
        self.gapPoints = gapPoints
        self.separator = separator
    }
}
