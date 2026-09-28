import Foundation
import CoreGraphics

extension HWPDocumentObjectPlacement {
    nonisolated func inlineBaselineOffset(in line: HWPDocumentLineLayout?) -> Double {
        guard isInline, !inlineOriginIsResolved,
              let line, line.baselineAlignment == .font else { return 0 }
        // HWP's font-aligned inline object has its baseline at 85% of its
        // height, just as the cached line metrics do for an object-only line.
        return max(0, line.baselinePoints - heightPoints * 0.85)
    }
}

nonisolated enum HWPDocumentLineBaselineAlignment: Int, Hashable, Sendable {
    case font, top, center, bottom
}

nonisolated struct HWPDocumentPageNumberStyle: Hashable, Sendable {
    let position: String
    let sideCharacter: String
    let startsAt: Int?

    func text(pageNumber: Int, sectionPageIndex: Int) -> String {
        let number = startsAt.map { $0 + sectionPageIndex } ?? pageNumber
        return sideCharacter.isEmpty ? "\(number)" : "\(sideCharacter) \(number) \(sideCharacter)"
    }
}

/// Page-coordinate information cached by HWP writers for one laid-out line.
/// Values are converted from HWPUNIT (1/100 point) at the parser boundary.
nonisolated struct HWPDocumentListMarker: Hashable, Sendable {
    let run: HWPDocumentTextRun
    let reservedWidthPoints: Double
    var isLegacyCircle = false
}

nonisolated struct HWPDocumentLineLayout: Hashable, Sendable, Identifiable {
    let id: String
    let startCharacter: Int
    let verticalPositionPoints: Double
    let lineHeightPoints: Double
    let textHeightPoints: Double
    let baselinePoints: Double
    let lineSpacingPoints: Double
    let columnStartPoints: Double
    let widthPoints: Double
    let flags: UInt32
    let text: String
    let textRuns: [HWPDocumentTextRun]
    var baselineAlignment: HWPDocumentLineBaselineAlignment = .font
    var textInsetPoints: Double = 0
    var listMarker: HWPDocumentListMarker? = nil
    var showsListMarker: Bool = true
    var endsParagraph: Bool? = nil

    var startsPage: Bool { flags & 0x0000_0001 != 0 }
    var startsColumn: Bool { flags & 0x0000_0002 != 0 }
    var isEmpty: Bool { flags & 0x0001_0000 != 0 }
}

nonisolated enum HWPDocumentLayoutReference: Int, Hashable, Sendable {
    case paper
    case page
    case column
    case paragraph
    case absolute
}

nonisolated enum HWPDocumentRelativeAlignment: Int, Hashable, Sendable {
    case start
    case center
    case end
    case inside
    case outside
}

nonisolated enum HWPDocumentObjectWrap: Int, Hashable, Sendable {
    case square
    case tight
    case through
    case topAndBottom
    case behindText
    case inFrontOfText
}

nonisolated struct HWPDocumentObjectPlacement: Hashable, Sendable {
    let xPoints: Double
    let yPoints: Double
    let widthPoints: Double
    var heightPoints: Double
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
    let inlineOriginIsResolved: Bool
    var sourceCharacterPosition: Int? = nil
    var inlineLeadingPoints: Double = 0

    init(
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

    func inlineOffset(lineWidth: Double, paragraphAlignment: HWPParagraphAlignment) -> CGPoint {
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

nonisolated struct HWPDocumentPoint: Hashable, Sendable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = min(max(x, -8_000), 8_000)
        self.y = min(max(y, -8_000), 8_000)
    }
}

nonisolated struct HWPDocumentStroke: Hashable, Sendable {
    let colorRGB: UInt32
    let widthPoints: Double
    let style: Int
    let startArrow: Int
    let endArrow: Int

    init(
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

nonisolated struct HWPDocumentFill: Hashable, Sendable {
    let colorRGB: UInt32?
    let patternColorRGB: UInt32?
    let pattern: Int?

    static let none = HWPDocumentFill()

    init(
        colorRGB: UInt32? = nil,
        patternColorRGB: UInt32? = nil,
        pattern: Int? = nil
    ) {
        self.colorRGB = colorRGB.map { $0 & 0x00FF_FFFF }
        self.patternColorRGB = patternColorRGB.map { $0 & 0x00FF_FFFF }
        self.pattern = pattern
    }
}

nonisolated enum HWPDocumentShapeGeometry: Hashable, Sendable {
    case line(start: HWPDocumentPoint, end: HWPDocumentPoint)
    case rectangle(cornerRadiusPercent: Double, points: [HWPDocumentPoint])
    case ellipse(center: HWPDocumentPoint, axis1: HWPDocumentPoint, axis2: HWPDocumentPoint)
    case arc(center: HWPDocumentPoint, axis1: HWPDocumentPoint, axis2: HWPDocumentPoint, kind: Int)
    case polygon(points: [HWPDocumentPoint])
    case curve(points: [HWPDocumentPoint], curvedSegments: [Bool])
    case container
    case unknown
}

nonisolated struct HWPDocumentShape: Hashable, Sendable {
    let geometry: HWPDocumentShapeGeometry
    let stroke: HWPDocumentStroke
    let fill: HWPDocumentFill
    let localFrame: CGRect?
    let rotationDegrees: Double
    let flipHorizontal: Bool
    let flipVertical: Bool
    let shadow: HWPDocumentShapeShadow?

    init(
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

nonisolated struct HWPDocumentShapeShadow: Hashable, Sendable {
    let kind: Int
    let colorRGB: UInt32
    let offsetX: Double
    let offsetY: Double
    let opacity: Double

    var offset: CGSize {
        CGSize(width: [1, 3, 5, 7].contains(kind) ? -abs(offsetX) : abs(offsetX),
            height: [1, 2, 5, 6].contains(kind) ? -abs(offsetY) : abs(offsetY))
    }
}

nonisolated struct HWPDocumentEquation: Hashable, Sendable {
    let script: String
    let fontSizePoints: Double
    let colorRGB: UInt32
    let baselinePercent: Double
    let fontName: String?

    init(
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

nonisolated enum HWPDocumentChartKind: String, Hashable, Sendable {
    case bar
    case line
    case pie
    case area
    case scatter
    case radar
    case unknown
}

nonisolated struct HWPDocumentChartSeries: Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let values: [Double]
    let colorRGB: UInt32?
}

/// A legacy Windows Metafile embedded in an OLE presentation stream. The
/// renderer supports the compact drawing subset used by HWP 5 chart previews.
nonisolated struct HWPDocumentMetafile: Hashable, Sendable {
    let data: Data
    let widthLogical: Int
    let heightLogical: Int
}

nonisolated struct HWPDocumentChart: Hashable, Sendable {
    let kind: HWPDocumentChartKind
    let title: String?
    let categories: [String]
    let series: [HWPDocumentChartSeries]
    let previewImage: HWPDocumentImage?
    let previewMetafile: HWPDocumentMetafile?

    var hasRenderableData: Bool {
        series.contains { !$0.values.isEmpty }
    }
}

nonisolated enum HWPDocumentCanvasContent: Hashable, Sendable {
    case shape(HWPDocumentShape)
    case group([HWPDocumentShape])
    case image(HWPDocumentImage)
    case equation(HWPDocumentEquation)
    case chart(HWPDocumentChart)
    case unsupported(String)
}

nonisolated struct HWPDocumentTextContainerLayout: Hashable, Sendable {
    let left: Double, right: Double, top: Double, bottom: Double
    let verticalAlignment: HWPDocumentRelativeAlignment
    var localFrame: CGRect? = nil
}

nonisolated struct HWPDocumentCanvasObject: Hashable, Sendable, Identifiable {
    let id: String
    let placement: HWPDocumentObjectPlacement
    let content: HWPDocumentCanvasContent
    let description: String?
    let textContainerID: String?
    let repeatsOnEveryPage: Bool
    let textContainerLayout: HWPDocumentTextContainerLayout?

    var groupedTextFrame: CGRect? {
        guard case .group(let shapes) = content,
              let frame = textContainerLayout?.localFrame else { return nil }
        let frames = shapes.compactMap { shape -> CGRect? in
            if case .container = shape.geometry { return nil }
            return shape.localFrame
        }
        guard let first = frames.first else { return nil }
        let bounds = frames.dropFirst().reduce(first) { $0.union($1) }
        let scaleX = placement.widthPoints / max(bounds.width, 1)
        let scaleY = placement.heightPoints / max(bounds.height, 1)
        return CGRect(x: (frame.minX - bounds.minX) * scaleX,
            y: (frame.minY - bounds.minY) * scaleY,
            width: frame.width * scaleX, height: frame.height * scaleY)
    }

    init(
        id: String,
        placement: HWPDocumentObjectPlacement,
        content: HWPDocumentCanvasContent,
        description: String? = nil,
        textContainerID: String? = nil,
        repeatsOnEveryPage: Bool = false,
        textContainerLayout: HWPDocumentTextContainerLayout? = nil
    ) {
        self.id = id
        self.placement = placement
        self.content = content
        self.description = description
        self.textContainerID = textContainerID
        self.repeatsOnEveryPage = repeatsOnEveryPage
        self.textContainerLayout = textContainerLayout
    }
}

nonisolated struct HWPDocumentColumn: Hashable, Sendable {
    let xPoints: Double
    let widthPoints: Double
}

nonisolated struct HWPDocumentColumnLayout: Hashable, Sendable {
    let columns: [HWPDocumentColumn]
    let gapPoints: Double
    let separator: HWPDocumentBorderLine?

    static let single = HWPDocumentColumnLayout(
        columns: [],
        gapPoints: 0,
        separator: nil
    )

    var count: Int { max(columns.count, 1) }
}
