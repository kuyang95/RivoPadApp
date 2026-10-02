import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif
import RivoZIPFoundation

public nonisolated enum HWPDocumentEditingError:
    Error,
    LocalizedError,
    Equatable,
    Sendable
{
    case invalidDocument
    case protectedDocument
    case limitExceeded
    case unsupportedEdit
    case staleDocument
    case cannotSave

    public var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return DocumentEngineLocalization.string("한글 문서 구조를 읽을 수 없습니다.")
        case .protectedDocument:
            return DocumentEngineLocalization.string("보호된 한글 문서는 편집할 수 없습니다.")
        case .limitExceeded:
            return DocumentEngineLocalization.string(
                "한글 문서가 안전하게 편집할 수 있는 크기 또는 구조 제한을 초과했습니다."
            )
        case .unsupportedEdit:
            return DocumentEngineLocalization.string(
                "이 문단에는 현재 버전에서 보존할 수 없는 복합 개체가 있어 직접 편집할 수 없습니다."
            )
        case .staleDocument:
            return DocumentEngineLocalization.string(
                "편집하는 동안 문서 구조가 바뀌었습니다. 문서를 다시 열어 주세요."
            )
        case .cannotSave:
            return DocumentEngineLocalization.string("HWPX 문서를 저장할 수 없습니다.")
        }
    }
}

public nonisolated struct HWPDocumentBorderLine: Hashable, Sendable {
    public let kind: UInt8
    public let widthPoints: Double
    public let colorRGB: UInt32

    public init(kind: UInt8 = 0, widthPoints: Double = 0, colorRGB: UInt32 = 0) {
        self.kind = kind
        self.widthPoints = min(max(widthPoints, 0), 16)
        self.colorRGB = colorRGB & 0x00FF_FFFF
    }

    public var isVisible: Bool { kind != 0 && widthPoints > 0 }
}

public nonisolated struct HWPDocumentBoxStyle: Hashable, Sendable {
    public let left: HWPDocumentBorderLine
    public let right: HWPDocumentBorderLine
    public let top: HWPDocumentBorderLine
    public let bottom: HWPDocumentBorderLine
    public let backgroundColorRGB: UInt32?
    public let backgroundImage: HWPDocumentImage?
    public let backgroundImageFillMode: Int?

    public init(
        left: HWPDocumentBorderLine = HWPDocumentBorderLine(),
        right: HWPDocumentBorderLine = HWPDocumentBorderLine(),
        top: HWPDocumentBorderLine = HWPDocumentBorderLine(),
        bottom: HWPDocumentBorderLine = HWPDocumentBorderLine(),
        backgroundColorRGB: UInt32? = nil,
        backgroundImage: HWPDocumentImage? = nil,
        backgroundImageFillMode: Int? = nil
    ) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
        self.backgroundColorRGB = backgroundColorRGB
        self.backgroundImage = backgroundImage
        self.backgroundImageFillMode = backgroundImageFillMode
    }

    public var firstVisibleBorder: HWPDocumentBorderLine? {
        [left, right, top, bottom].first(where: \.isVisible)
    }
}

public nonisolated enum HWPDocumentHeaderFooterScope: String, Hashable, Sendable {
    case bothPages
    case evenPages
    case oddPages
}

public nonisolated enum HWPDocumentRegionKind: String, Hashable, Sendable {
    case body
    case background
    case header
    case footer
    case footnote
    case endnote
}

public nonisolated struct HWPDocumentRegion: Hashable, Sendable {
    public let kind: HWPDocumentRegionKind
    public let ordinal: Int?
    public let scope: HWPDocumentHeaderFooterScope?

    public static let body = HWPDocumentRegion(kind: .body)

    public init(
        kind: HWPDocumentRegionKind,
        ordinal: Int? = nil,
        scope: HWPDocumentHeaderFooterScope? = nil
    ) {
        self.kind = kind
        self.ordinal = ordinal
        self.scope = scope
    }

    public var accessibilityDescription: String? {
        switch kind {
        case .body:
            return nil
        case .background:
            return DocumentEngineLocalization.string("바탕쪽")
        case .header:
            return DocumentEngineLocalization.string("머리말")
        case .footer:
            return DocumentEngineLocalization.string("꼬리말")
        case .footnote:
            return DocumentEngineLocalization.format("각주 %lld", (ordinal ?? 0) + 1)
        case .endnote:
            return DocumentEngineLocalization.format("미주 %lld", (ordinal ?? 0) + 1)
        }
    }
}

public nonisolated enum HWPDocumentImageEffect: Int, Hashable, Sendable, CaseIterable {
    case original = 0
    case grayscale = 1
    case blackAndWhite = 2

    public init(hwpXName: String?) {
        switch hwpXName?.uppercased() {
        case "GRAY_SCALE": self = .grayscale
        case "BLACK_WHITE": self = .blackAndWhite
        default: self = .original
        }
    }

    public var hwpXName: String {
        switch self {
        case .original: return "REAL_PIC"
        case .grayscale: return "GRAY_SCALE"
        case .blackAndWhite: return "BLACK_WHITE"
        }
    }
}

public nonisolated struct HWPDocumentImage: Hashable, Sendable, Identifiable {
    public let id: String
    public let binaryID: Int
    public let data: Data
    public let widthPoints: Double
    public let heightPoints: Double
    public let description: String?
    public let cropRect: CGRect?
    public let borderStroke: HWPDocumentStroke?
    public let brightness: Int
    public let contrast: Int
    public let effect: HWPDocumentImageEffect
    public let transparencyPercent: Int
    public let supportsTransparency: Bool

    public init(
        id: String,
        binaryID: Int,
        data: Data,
        widthPoints: Double,
        heightPoints: Double,
        description: String? = nil,
        cropRect: CGRect? = nil,
        borderStroke: HWPDocumentStroke? = nil,
        brightness: Int = 0,
        contrast: Int = 0,
        effect: HWPDocumentImageEffect = .original,
        transparencyPercent: Int = 0,
        supportsTransparency: Bool = false
    ) {
        self.id = id
        self.binaryID = binaryID
        self.data = data
        self.widthPoints = min(max(widthPoints, 1), 2_000)
        self.heightPoints = min(max(heightPoints, 1), 2_000)
        self.description = description
        if let cropRect,
           cropRect.width > 0,
           cropRect.height > 0 {
            let x = min(max(cropRect.minX, 0), 0.999)
            let y = min(max(cropRect.minY, 0), 0.999)
            self.cropRect = CGRect(
                x: x,
                y: y,
                width: min(max(cropRect.width, 0.001), 1 - x),
                height: min(max(cropRect.height, 0.001), 1 - y)
            )
        } else {
            self.cropRect = nil
        }
        self.borderStroke = borderStroke
        self.brightness = min(max(brightness, -100), 100)
        self.contrast = min(max(contrast, -100), 100)
        self.effect = effect
        self.transparencyPercent = min(max(transparencyPercent, 0), 100)
        self.supportsTransparency = supportsTransparency
    }
}

public nonisolated struct HWPDocumentNoteStyle: Hashable, Sendable {
    public let startingNumber: Int
    public let separatorLengthPoints: Double
    public let separatorMarginTopPoints: Double
    public let separatorMarginBottomPoints: Double
    public let noteSpacingPoints: Double
    public let separator: HWPDocumentBorderLine

    public init(startingNumber: Int, separatorLengthPoints: Double, separatorMarginTopPoints: Double, separatorMarginBottomPoints: Double, noteSpacingPoints: Double, separator: HWPDocumentBorderLine) {
        self.startingNumber = startingNumber
        self.separatorLengthPoints = separatorLengthPoints
        self.separatorMarginTopPoints = separatorMarginTopPoints
        self.separatorMarginBottomPoints = separatorMarginBottomPoints
        self.noteSpacingPoints = noteSpacingPoints
        self.separator = separator
    }
}

public nonisolated struct HWPDocumentPageLayout: Hashable, Sendable {
    public let sectionIndex: Int
    public let widthPoints: Double
    public let heightPoints: Double
    public let leftMarginPoints: Double
    public let rightMarginPoints: Double
    public let topMarginPoints: Double
    public let bottomMarginPoints: Double
    public let headerMarginPoints: Double
    public let footerMarginPoints: Double
    public let gutterPoints: Double
    public let isLandscape: Bool
    public let hidesHeader: Bool
    public let hidesFooter: Bool
    public let hidesBackground: Bool
    public let hidesPageBorder: Bool
    public let hidesPageBackground: Bool
    public let pageBorderFirstPageOnly: Bool
    public let pageBackgroundFirstPageOnly: Bool
    public let pageStyle: HWPDocumentBoxStyle?
    public let footnoteStyle: HWPDocumentNoteStyle?
    public let endnoteStyle: HWPDocumentNoteStyle?
    public let columnLayout: HWPDocumentColumnLayout
    public var pageNumberStyle: HWPDocumentPageNumberStyle? = nil
    public var pageNumberStart: Int? = nil

    public static func standard(sectionIndex: Int = 0) -> HWPDocumentPageLayout {
        HWPDocumentPageLayout(
            sectionIndex: sectionIndex,
            widthPoints: 595.28,
            heightPoints: 841.86,
            leftMarginPoints: 85.04,
            rightMarginPoints: 85.04,
            topMarginPoints: 56.68,
            bottomMarginPoints: 42.52,
            headerMarginPoints: 42.52,
            footerMarginPoints: 42.52,
            gutterPoints: 0,
            isLandscape: false,
            hidesHeader: false,
            hidesFooter: false,
            hidesBackground: false,
            hidesPageBorder: false,
            hidesPageBackground: false,
            pageBorderFirstPageOnly: false,
            pageBackgroundFirstPageOnly: false,
            pageStyle: nil,
            footnoteStyle: nil,
            endnoteStyle: nil,
            columnLayout: .single
        )
    }

    public init(sectionIndex: Int, widthPoints: Double, heightPoints: Double, leftMarginPoints: Double, rightMarginPoints: Double, topMarginPoints: Double, bottomMarginPoints: Double, headerMarginPoints: Double, footerMarginPoints: Double, gutterPoints: Double, isLandscape: Bool, hidesHeader: Bool, hidesFooter: Bool, hidesBackground: Bool, hidesPageBorder: Bool, hidesPageBackground: Bool, pageBorderFirstPageOnly: Bool, pageBackgroundFirstPageOnly: Bool, pageStyle: HWPDocumentBoxStyle? = nil, footnoteStyle: HWPDocumentNoteStyle? = nil, endnoteStyle: HWPDocumentNoteStyle? = nil, columnLayout: HWPDocumentColumnLayout, pageNumberStyle: HWPDocumentPageNumberStyle? = nil, pageNumberStart: Int? = nil) {
        self.sectionIndex = sectionIndex
        self.widthPoints = widthPoints
        self.heightPoints = heightPoints
        self.leftMarginPoints = leftMarginPoints
        self.rightMarginPoints = rightMarginPoints
        self.topMarginPoints = topMarginPoints
        self.bottomMarginPoints = bottomMarginPoints
        self.headerMarginPoints = headerMarginPoints
        self.footerMarginPoints = footerMarginPoints
        self.gutterPoints = gutterPoints
        self.isLandscape = isLandscape
        self.hidesHeader = hidesHeader
        self.hidesFooter = hidesFooter
        self.hidesBackground = hidesBackground
        self.hidesPageBorder = hidesPageBorder
        self.hidesPageBackground = hidesPageBackground
        self.pageBorderFirstPageOnly = pageBorderFirstPageOnly
        self.pageBackgroundFirstPageOnly = pageBackgroundFirstPageOnly
        self.pageStyle = pageStyle
        self.footnoteStyle = footnoteStyle
        self.endnoteStyle = endnoteStyle
        self.columnLayout = columnLayout
        self.pageNumberStyle = pageNumberStyle
        self.pageNumberStart = pageNumberStart
    }
}

public nonisolated struct HWPDocumentTableBackgroundZone: Hashable, Sendable {
    public let startRow: Int
    public let startColumn: Int
    public let endRow: Int
    public let endColumn: Int
    public let style: HWPDocumentBoxStyle

    public init(startRow: Int, startColumn: Int, endRow: Int, endColumn: Int, style: HWPDocumentBoxStyle) {
        self.startRow = startRow
        self.startColumn = startColumn
        self.endRow = endRow
        self.endColumn = endColumn
        self.style = style
    }
}

public nonisolated struct HWPDocumentTableLocation: Hashable, Sendable {
    /// Canvas-only page boundary; never written into a logical cell record.
    public var startsPageSlice = false
    public let table: Int
    public let row: Int
    public let column: Int
    public let paragraph: Int
    public let rowSpan: Int
    public let columnSpan: Int
    public let boxStyle: HWPDocumentBoxStyle?
    public let cellWidthPoints: Double?
    public let cellHeightPoints: Double?
    public let cellMarginLeftPoints: Double
    public let cellMarginRightPoints: Double
    public let cellMarginTopPoints: Double
    public let cellMarginBottomPoints: Double
    public let cellVerticalAlignment: HWPDocumentRelativeAlignment
    public let tablePageBoundaryMode: Int
    public let repeatsHeaderRow: Bool
    public let tablePlacement: HWPDocumentObjectPlacement?
    public let tableAnchor: HWPDocumentTableAnchor?
    public var parent: HWPDocumentTableParentLocation?
    public let backgroundZones: [HWPDocumentTableBackgroundZone]

    public init(
        table: Int,
        row: Int,
        column: Int,
        paragraph: Int,
        rowSpan: Int = 1,
        columnSpan: Int = 1,
        boxStyle: HWPDocumentBoxStyle? = nil,
        cellWidthPoints: Double? = nil,
        cellHeightPoints: Double? = nil,
        cellMarginLeftPoints: Double = 0,
        cellMarginRightPoints: Double = 0,
        cellMarginTopPoints: Double = 0,
        cellMarginBottomPoints: Double = 0,
        cellVerticalAlignment: HWPDocumentRelativeAlignment = .start,
        tablePageBoundaryMode: Int = 0,
        repeatsHeaderRow: Bool = false,
        tablePlacement: HWPDocumentObjectPlacement? = nil,
        tableAnchor: HWPDocumentTableAnchor? = nil,
        parent: HWPDocumentTableParentLocation? = nil,
        backgroundZones: [HWPDocumentTableBackgroundZone] = []
    ) {
        self.table = table
        self.row = row
        self.column = column
        self.paragraph = paragraph
        self.rowSpan = max(1, rowSpan)
        self.columnSpan = max(1, columnSpan)
        self.boxStyle = boxStyle
        self.cellWidthPoints = cellWidthPoints
        self.cellHeightPoints = cellHeightPoints
        self.cellMarginLeftPoints = min(max(cellMarginLeftPoints, 0), 720)
        self.cellMarginRightPoints = min(max(cellMarginRightPoints, 0), 720)
        self.cellMarginTopPoints = min(max(cellMarginTopPoints, 0), 720)
        self.cellMarginBottomPoints = min(max(cellMarginBottomPoints, 0), 720)
        self.cellVerticalAlignment = cellVerticalAlignment
        self.tablePageBoundaryMode = min(max(tablePageBoundaryMode, 0), 3)
        self.repeatsHeaderRow = repeatsHeaderRow
        self.tablePlacement = tablePlacement
        self.tableAnchor = tableAnchor
        self.parent = parent
        self.backgroundZones = backgroundZones
    }

    public var accessibilityDescription: String {
        let address = DocumentEngineLocalization.format(
            "표 %lld · %lld행 · %lld열",
            table + 1,
            row + 1,
            column + 1
        )
        guard rowSpan > 1 || columnSpan > 1 else { return address }
        return address + DocumentEngineLocalization.format(
            " · %lld행×%lld열 병합",
            rowSpan,
            columnSpan
        )
    }
}

/// The outer cell that owns a nested HWP table control.
public nonisolated struct HWPDocumentTableParentLocation: Hashable, Sendable {
    public let table: Int
    public let row: Int
    public let column: Int

    public init(table: Int, row: Int, column: Int) {
        self.table = table
        self.row = row
        self.column = column
    }
}

/// The cached line that owns an inline/paragraph-relative HWP table control.
/// Cell line segments are relative to the cell and cannot be used as the
/// table's page anchor.
public nonisolated struct HWPDocumentTableAnchor: Hashable, Sendable {
    public let columnStartPoints: Double
    public let verticalPositionPoints: Double
    public let widthPoints: Double
    public let lineHeightPoints: Double
    public var paragraphAlignment: HWPParagraphAlignment = .leading

    public init(columnStartPoints: Double, verticalPositionPoints: Double, widthPoints: Double, lineHeightPoints: Double, paragraphAlignment: HWPParagraphAlignment = .leading) {
        self.columnStartPoints = columnStartPoints
        self.verticalPositionPoints = verticalPositionPoints
        self.widthPoints = widthPoints
        self.lineHeightPoints = lineHeightPoints
        self.paragraphAlignment = paragraphAlignment
    }
}

public nonisolated enum HWPParagraphAlignment: String, Hashable, Sendable {
    case justified
    case leading
    case trailing
    case centered
    case distributed
}

/// PANOSE-style metadata stored by HWP for selecting a compatible face when
/// the declared font is unavailable. HWP stores the ten classification bytes
/// even when it cannot embed the actual font program.
public nonisolated struct HWPDocumentFontSignature: Hashable, Sendable {
    public let bytes: [UInt8]

    public init(bytes: [UInt8]) {
        self.bytes = Array(bytes.prefix(10))
    }

    public var isMonospaced: Bool {
        bytes.indices.contains(3) && bytes[3] == 9
    }

    public var prefersSerif: Bool? {
        guard bytes.indices.contains(1), bytes[1] > 1 else { return nil }
        // PANOSE serif styles 11-15 describe normal/obtuse/perpendicular
        // sans-serif designs. Values 2-10 are serif variants.
        return !(11...15).contains(bytes[1])
    }
}

public nonisolated struct HWPDocumentTextRun: Hashable, Sendable {
    public var text: String
    public var fontName: String?
    public var alternateFontName: String?
    public var baseFontName: String?
    public var fontSignature: HWPDocumentFontSignature?
    public var fontSizePoints: Double?
    public var fontWidthPercent: Double
    public var letterSpacingPercent: Double
    public var baselinePositionPercent: Double
    public var textColorRGB: UInt32?
    public var backgroundColorRGB: UInt32?
    public var isBold: Bool
    public var isItalic: Bool
    public var isUnderlined: Bool
    public var isStruckThrough: Bool
    public var isSuperscript: Bool
    public var isSubscript: Bool
    public var hyperlink: String?
    public var spaceWidthPoints: Double?
    public var tabWidthPoints: Double?

    public init(
        text: String,
        fontName: String? = nil,
        alternateFontName: String? = nil,
        baseFontName: String? = nil,
        fontSignature: HWPDocumentFontSignature? = nil,
        fontSizePoints: Double? = nil,
        fontWidthPercent: Double = 100,
        letterSpacingPercent: Double = 0,
        baselinePositionPercent: Double = 0,
        textColorRGB: UInt32? = nil,
        backgroundColorRGB: UInt32? = nil,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderlined: Bool = false,
        isStruckThrough: Bool = false,
        isSuperscript: Bool = false,
        isSubscript: Bool = false,
        hyperlink: String? = nil,
        spaceWidthPoints: Double? = nil,
        tabWidthPoints: Double? = nil
    ) {
        self.text = text
        self.fontName = fontName
        self.alternateFontName = alternateFontName
        self.baseFontName = baseFontName
        self.fontSignature = fontSignature
        self.fontSizePoints = fontSizePoints
        self.fontWidthPercent = min(max(fontWidthPercent, 10), 250)
        self.letterSpacingPercent = min(max(letterSpacingPercent, -50), 50)
        self.baselinePositionPercent = min(max(baselinePositionPercent, -100), 100)
        self.textColorRGB = textColorRGB
        self.backgroundColorRGB = backgroundColorRGB
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.isStruckThrough = isStruckThrough
        self.isSuperscript = isSuperscript
        self.isSubscript = isSubscript
        self.hyperlink = hyperlink
        self.spaceWidthPoints = spaceWidthPoints
        self.tabWidthPoints = tabWidthPoints
    }
}

public nonisolated struct HWPDocumentParagraphBorder: Hashable, Sendable {
    public let style: HWPDocumentBoxStyle
    public let left: Double
    public let right: Double
    public let top: Double
    public let bottom: Double

    public init(style: HWPDocumentBoxStyle, left: Double, right: Double, top: Double, bottom: Double) {
        self.style = style
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }
}

public nonisolated struct HWPDocumentBlockPresentation: Hashable, Sendable {
    public var styleName: String?
    public var alignment: HWPParagraphAlignment
    public var outlineLevel: Int?
    public var leftMarginPoints: Double
    public var rightMarginPoints: Double
    public var firstLineIndentPoints: Double
    public var spacingBeforePoints: Double
    public var spacingAfterPoints: Double
    public var pageBreakBefore: Bool
    public var textRuns: [HWPDocumentTextRun]
    public var paragraphBorder: HWPDocumentParagraphBorder?

    public var lineSpacingPercent: Double?
    public var list: HWPParagraphList?

    public static let plain = HWPDocumentBlockPresentation()

    public init(
        styleName: String? = nil,
        alignment: HWPParagraphAlignment = .leading,
        outlineLevel: Int? = nil,
        leftMarginPoints: Double = 0,
        rightMarginPoints: Double = 0,
        firstLineIndentPoints: Double = 0,
        spacingBeforePoints: Double = 0,
        spacingAfterPoints: Double = 0,
        pageBreakBefore: Bool = false,
        textRuns: [HWPDocumentTextRun] = [],
        paragraphBorder: HWPDocumentParagraphBorder? = nil,
        lineSpacingPercent: Double? = nil,
        list: HWPParagraphList? = nil
    ) {
        self.styleName = styleName
        self.alignment = alignment
        self.outlineLevel = outlineLevel
        self.leftMarginPoints = leftMarginPoints
        self.rightMarginPoints = rightMarginPoints
        self.firstLineIndentPoints = firstLineIndentPoints
        self.spacingBeforePoints = spacingBeforePoints
        self.spacingAfterPoints = spacingAfterPoints
        self.pageBreakBefore = pageBreakBefore
        self.textRuns = textRuns
        self.paragraphBorder = paragraphBorder
        self.lineSpacingPercent = lineSpacingPercent
        self.list = list
    }
}

public nonisolated struct HWPDocumentBlock: Identifiable, Hashable, Sendable {
    public let id: String
    public let sectionPath: String
    public let paragraphIndex: Int
    public var text: String
    public let tableLocation: HWPDocumentTableLocation?
    public let isEditable: Bool
    public let presentation: HWPDocumentBlockPresentation
    public let region: HWPDocumentRegion
    public let images: [HWPDocumentImage]
    public let lineLayouts: [HWPDocumentLineLayout]
    public let canvasObjects: [HWPDocumentCanvasObject]
    public let layoutContainerID: String?
    /// Original paragraph used to create an unsaved paragraph. Parsed IDs stay stable during editing.
    public let sourceParagraphID: String?
    public let keepsParagraphBoundary: Bool

    public init(
        id: String,
        sectionPath: String,
        paragraphIndex: Int,
        text: String,
        tableLocation: HWPDocumentTableLocation?,
        isEditable: Bool,
        presentation: HWPDocumentBlockPresentation = .plain,
        region: HWPDocumentRegion = .body,
        images: [HWPDocumentImage] = [],
        lineLayouts: [HWPDocumentLineLayout] = [],
        canvasObjects: [HWPDocumentCanvasObject] = [],
        layoutContainerID: String? = nil,
        sourceParagraphID: String? = nil,
        keepsParagraphBoundary: Bool = false
    ) {
        self.id = id
        self.sectionPath = sectionPath
        self.paragraphIndex = paragraphIndex
        self.text = text
        self.tableLocation = tableLocation
        self.isEditable = isEditable
        self.presentation = presentation
        self.region = region
        self.images = images
        self.lineLayouts = lineLayouts
        self.canvasObjects = canvasObjects
        self.layoutContainerID = layoutContainerID
        self.sourceParagraphID = sourceParagraphID
        self.keepsParagraphBoundary = keepsParagraphBoundary
    }

    public var accessibilityLabel: String {
        let role: String
        if let tableLocation {
            role = tableLocation.accessibilityDescription
        } else if let outlineLevel = presentation.outlineLevel {
            role = DocumentEngineLocalization.format("제목 수준 %lld", outlineLevel + 1)
        } else if let styleName = presentation.styleName,
                  !styleName.isEmpty {
            role = styleName
        } else {
            role = DocumentEngineLocalization.string("문단")
        }
        let regionPrefix = region.accessibilityDescription.map { "\($0). " } ?? ""
        let imageSuffix = images.isEmpty
            ? ""
            : DocumentEngineLocalization.format(". 그림 %lld개", images.count)
        return regionPrefix + (text.isEmpty ? role : "\(role). \(text)") + imageSuffix
    }
}

public nonisolated struct HWPXDocumentPackage: Sendable {
    public static let maximumBlocks = 20_000
    private static let expectedMIMEType = "application/hwp+zip"

    public let sourceData: Data
    public let sectionPaths: [String]
    public let sections: [HWPXSectionDocument]
    public let blocks: [HWPDocumentBlock]
    public let pageLayouts: [HWPDocumentPageLayout]

    public static func load(from data: Data) throws -> HWPXDocumentPackage {
        guard data.count <= HWPXTextExtractor.maximumDocumentBytes else {
            throw HWPDocumentEditingError.limitExceeded
        }
        let archive = try HWPXEditingArchive(data: data)
        guard archive.contains("mimetype"),
              let mime = String(
                  data: try archive.data(at: "mimetype"),
                  encoding: .utf8
              )?.trimmingCharacters(in: .whitespacesAndNewlines),
              mime == expectedMIMEType else {
            throw HWPDocumentEditingError.invalidDocument
        }

        let paths = try orderedSectionPaths(in: archive)
        guard !paths.isEmpty,
              paths.count <= HWPXTextExtractor.maximumSections else {
            throw HWPDocumentEditingError.invalidDocument
        }

        var documents: [HWPXSectionDocument] = []
        var allBlocks: [HWPDocumentBlock] = []
        var pageLayouts: [HWPDocumentPageLayout] = []
        let layoutParser = try HWPXLayoutParser(
            headerData: archive.contains("Contents/header.xml") ? archive.data(at: "Contents/header.xml") : nil,
            manifestData: archive.contains("Contents/content.hpf") ? archive.data(at: "Contents/content.hpf") : nil,
            readAsset: { try archive.data(at: $0) }
        )
        for path in paths {
            let data = try archive.data(at: path)
            guard let xml = String(data: data, encoding: .utf8),
                  !xml.localizedCaseInsensitiveContains("<!DOCTYPE"),
                  !xml.localizedCaseInsensitiveContains("<!ENTITY") else {
                throw HWPDocumentEditingError.invalidDocument
            }
            let structureBlocks = try HWPXSectionStructureParser(
                sectionPath: path,
                paragraphOffset: allBlocks.count
            ).parse(data)
            let resolved = try layoutParser.resolve(data: data, blocks: structureBlocks,
                sectionIndex: sectionIndex(for: path) ?? pageLayouts.count)
            let sectionBlocks = resolved.blocks
            pageLayouts.append(resolved.layout)
            let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: xml)
            guard ranges.count == sectionBlocks.count else {
                throw HWPDocumentEditingError.invalidDocument
            }
            allBlocks.append(contentsOf: sectionBlocks)
            documents.append(
                HWPXSectionDocument(
                    path: path,
                    xml: xml,
                    blocks: sectionBlocks
                )
            )
            guard allBlocks.count <= maximumBlocks else {
                throw HWPDocumentEditingError.limitExceeded
            }
        }
        return HWPXDocumentPackage(
            sourceData: data,
            sectionPaths: paths,
            sections: documents,
            blocks: allBlocks,
            pageLayouts: pageLayouts
        )
    }

    public func serializedData(applying editedBlocks: [HWPDocumentBlock]) throws -> Data {
        if blocks.map(\.id) != editedBlocks.map(\.id) {
            return try HWPXParagraphWriter.rewrite(self, edited: editedBlocks)
        }
        guard editedBlocks.count == blocks.count else {
            throw HWPDocumentEditingError.staleDocument
        }
        var replacements: [String: Data] = [:]
        var offset = 0
        for section in sections {
            let end = offset + section.blocks.count
            guard end <= editedBlocks.count else {
                throw HWPDocumentEditingError.staleDocument
            }
            let edited = Array(editedBlocks[offset..<end])
            if edited != section.blocks {
                let patched = try HWPXParagraphXMLPatcher.apply(
                    originalXML: section.xml,
                    originalBlocks: section.blocks,
                    editedBlocks: edited
                )
                guard let payload = patched.data(using: .utf8),
                      payload.count <= HWPXTextExtractor.maximumEntryBytes else {
                    throw HWPDocumentEditingError.limitExceeded
                }
                replacements[section.path] = payload
            }
            offset = end
        }
        guard offset == editedBlocks.count else {
            throw HWPDocumentEditingError.staleDocument
        }

        let archive = try HWPXEditingArchive(data: sourceData)
        let textData = try archive.repack(replacing: replacements)
        let formatted = try HWPXFormattingWriter.apply(to: textData, originals: blocks, edited: editedBlocks)
        let lined = try HWPXLineLayoutWriter.apply(formatted, originals: blocks, edited: editedBlocks)
        let linked = try HWPHyperlinkEditingWriter.applyHWPX(to: lined, originals: blocks, edited: editedBlocks)
        let sized = try HWPTableLayoutWriter.applyHWPX(linked, originals: blocks, edited: editedBlocks)
        let result = try HWPCellFormattingWriter.applyHWPX(sized, originals: blocks, edited: editedBlocks)
        guard result.count <= HWPXTextExtractor.maximumDocumentBytes else {
            throw HWPDocumentEditingError.limitExceeded
        }

        let verified = try HWPXDocumentPackage.load(from: result)
        guard verified.blocks.count == editedBlocks.count,
              zip(verified.blocks, editedBlocks).allSatisfy({
                  $0.id == $1.id && $0.text == $1.text
              }) else {
            throw HWPDocumentEditingError.cannotSave
        }
        return result
    }

    private static func orderedSectionPaths(
        in archive: HWPXEditingArchive
    ) throws -> [String] {
        let fallback = archive.paths.compactMap { path -> (Int, String)? in
            guard let index = sectionIndex(for: path) else { return nil }
            return (index, path)
        }.sorted {
            $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0
        }.map(\.1)

        guard archive.contains("Contents/content.hpf") else {
            return fallback
        }
        let packageData = try archive.data(at: "Contents/content.hpf")
        guard let packageXML = String(data: packageData, encoding: .utf8),
              !packageXML.localizedCaseInsensitiveContains("<!DOCTYPE"),
              !packageXML.localizedCaseInsensitiveContains("<!ENTITY") else {
            throw HWPDocumentEditingError.invalidDocument
        }
        let package = HWPXPackageManifestParser().parse(packageData)
        var result: [String] = []
        var seen = Set<String>()
        for identifier in package.spineIDs {
            guard let href = package.manifest[identifier],
                  let path = normalizedSectionPath(href),
                  archive.contains(path),
                  seen.insert(path).inserted else { continue }
            result.append(path)
        }
        if result.isEmpty {
            for href in package.manifest.values {
                guard let path = normalizedSectionPath(href),
                      archive.contains(path),
                      seen.insert(path).inserted else { continue }
                result.append(path)
            }
            result.sort {
                (sectionIndex(for: $0) ?? .max, $0)
                    < (sectionIndex(for: $1) ?? .max, $1)
            }
        }
        return result.isEmpty ? fallback : result
    }

    private static func normalizedSectionPath(_ rawHref: String) -> String? {
        let decoded = rawHref.removingPercentEncoding ?? rawHref
        let slashes = decoded.replacingOccurrences(of: "\\", with: "/")
        let candidate: String
        if slashes.hasPrefix("/") {
            candidate = String(slashes.dropFirst())
        } else if slashes.hasPrefix("Contents/") {
            candidate = slashes
        } else {
            candidate = "Contents/" + slashes
        }
        var components: [Substring] = []
        for component in candidate.split(separator: "/") {
            if component == "." { continue }
            if component == ".." {
                guard !components.isEmpty else { return nil }
                components.removeLast()
            } else {
                components.append(component)
            }
        }
        let path = components.joined(separator: "/")
        guard path.hasPrefix("Contents/"), sectionIndex(for: path) != nil else {
            return nil
        }
        return path
    }

    private static func sectionIndex(for path: String) -> Int? {
        guard path.hasPrefix("Contents/section"),
              path.lowercased().hasSuffix(".xml") else { return nil }
        let name = URL(fileURLWithPath: path).deletingPathExtension()
            .lastPathComponent
        let suffix = name.dropFirst("section".count)
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { return nil }
        return Int(suffix)
    }

    public init(sourceData: Data, sectionPaths: [String], sections: [HWPXSectionDocument], blocks: [HWPDocumentBlock], pageLayouts: [HWPDocumentPageLayout]) {
        self.sourceData = sourceData
        self.sectionPaths = sectionPaths
        self.sections = sections
        self.blocks = blocks
        self.pageLayouts = pageLayouts
    }
}

public nonisolated struct HWPXSectionDocument: Sendable {
    public let path: String
    public let xml: String
    public let blocks: [HWPDocumentBlock]

    public init(path: String, xml: String, blocks: [HWPDocumentBlock]) {
        self.path = path
        self.xml = xml
        self.blocks = blocks
    }
}

private nonisolated final class HWPXPackageManifestParser:
    NSObject,
    XMLParserDelegate
{
    struct Result {
        var manifest: [String: String] = [:]
        var spineIDs: [String] = []
    }

    private var result = Result()

    func parse(_ data: Data) -> Result {
        result = Result()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { return Result() }
        return result
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch Self.localName(qName ?? elementName) {
        case "item":
            if let id = attribute(attributeDict, named: "id"),
               let href = attribute(attributeDict, named: "href") {
                result.manifest[id] = href
            }
        case "itemref":
            if let idref = attribute(attributeDict, named: "idref") {
                result.spineIDs.append(idref)
            }
        default:
            break
        }
    }

    private func attribute(
        _ attributes: [String: String],
        named name: String
    ) -> String? {
        attributes.first {
            Self.localName($0.key).lowercased() == name.lowercased()
        }?.value
    }

    private static func localName(_ name: String) -> String {
        String(name.split(separator: ":").last ?? Substring(name))
    }
}

private nonisolated final class HWPXSectionStructureParser:
    NSObject,
    XMLParserDelegate
{
    private struct ParagraphContext {
        let ordinal: Int
        var text = ""
        var isEditable = true
        var keepsParagraphBoundary = false
        let cellID: Int?
        let cellParagraph: Int
    }

    private struct TableContext {
        let index: Int
        var row = -1
        var column = -1
        var paragraph = -1
        var cellID: Int?
    }

    private struct CellContext {
        let table: Int
        var row: Int
        var column: Int
        var rowSpan = 1
        var columnSpan = 1
        var width: Double?
        var height: Double?
        var left = 0.0
        var right = 0.0
        var top = 0.0
        var bottom = 0.0
        var parent: HWPDocumentTableParentLocation?

        func location(paragraph: Int) -> HWPDocumentTableLocation {
            HWPDocumentTableLocation(table: table, row: row, column: column,
                paragraph: paragraph, rowSpan: rowSpan, columnSpan: columnSpan,
                cellWidthPoints: width, cellHeightPoints: height,
                cellMarginLeftPoints: left, cellMarginRightPoints: right,
                cellMarginTopPoints: top, cellMarginBottomPoints: bottom,
                parent: parent)
        }
    }

    private let sectionPath: String
    private let paragraphOffset: Int
    private var completedParagraphs: [ParagraphContext] = []
    private var paragraphStack: [ParagraphContext] = []
    private var nextParagraphOrdinal = 0
    private var textDepth = 0
    private var nextTableIndex = 0
    private var tableStack: [TableContext] = []
    private var cells: [Int: CellContext] = [:]
    private var nextCellID = 0
    private var elementStack: [String] = []

    init(sectionPath: String, paragraphOffset: Int) {
        self.sectionPath = sectionPath
        self.paragraphOffset = paragraphOffset
    }

    func parse(_ data: Data) throws -> [HWPDocumentBlock] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), paragraphStack.isEmpty else {
            throw HWPDocumentEditingError.invalidDocument
        }
        return completedParagraphs.sorted { $0.ordinal < $1.ordinal }.map { paragraph in
            HWPDocumentBlock(
                id: "\(sectionPath)#p-\(paragraph.ordinal)",
                sectionPath: sectionPath,
                paragraphIndex: paragraphOffset + paragraph.ordinal,
                text: paragraph.text,
                tableLocation: paragraph.cellID.flatMap { id in cells[id]?.location(paragraph: paragraph.cellParagraph) },
                isEditable: paragraph.isEditable, keepsParagraphBoundary: paragraph.keepsParagraphBoundary
            )
        }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = Self.localName(qName ?? elementName).lowercased()
        let parentElements = elementStack
        elementStack.append(name)
        let removable: Set<String> = ["p", "run", "t", "tab", "linebreak", "hyphen", "hypen", "nbspace", "fwspace", "linesegarray", "lineseg"]
        if !paragraphStack.isEmpty, !removable.contains(name) {
            paragraphStack[paragraphStack.count - 1].keepsParagraphBoundary = true
        }
        switch name {
        case "tbl":
            markCurrentParagraphReadOnly()
            tableStack.append(TableContext(index: nextTableIndex))
            nextTableIndex += 1
        case "tr":
            guard !tableStack.isEmpty else { break }
            tableStack[tableStack.count - 1].row += 1
            tableStack[tableStack.count - 1].column = -1
        case "tc":
            guard !tableStack.isEmpty else { break }
            tableStack[tableStack.count - 1].column += 1
            tableStack[tableStack.count - 1].paragraph = -1
            tableStack[tableStack.count - 1].cellID = nextCellID
            let table = tableStack[tableStack.count - 1]
            let outerCell = tableStack.dropLast().last?.cellID.flatMap { cells[$0] }
            cells[nextCellID] = CellContext(table: table.index,
                row: max(0, table.row), column: max(0, table.column),
                parent: outerCell.map {
                    HWPDocumentTableParentLocation(table: $0.table, row: $0.row, column: $0.column)
                })
            nextCellID += 1
        case "celladdr", "cellspan", "cellsz", "cellmargin":
            guard let id = tableStack.last?.cellID, var cell = cells[id] else { break }
            func number(_ key: String) -> Double? {
                attributeDict.first { Self.localName($0.key).lowercased() == key.lowercased() }
                    .flatMap { Double($0.value) }.flatMap { $0.isFinite ? $0 : nil }
            }
            func coordinate(_ key: String, fallback: Int) -> Int {
                guard let value = number(key), value >= 0, value <= 65_535 else { return fallback }
                return Int(value)
            }
            switch name {
            case "celladdr":
                cell.row = coordinate("rowAddr", fallback: cell.row)
                cell.column = coordinate("colAddr", fallback: cell.column)
            case "cellspan":
                cell.rowSpan = max(1, coordinate("rowSpan", fallback: 1))
                cell.columnSpan = max(1, coordinate("colSpan", fallback: 1))
            case "cellsz":
                cell.width = number("width").map { min(max($0 / 100, 0), 100_000) }
                cell.height = number("height").map { min(max($0 / 100, 0), 100_000) }
            default:
                cell.left = (number("left") ?? 0) / 100
                cell.right = (number("right") ?? 0) / 100
                cell.top = (number("top") ?? 0) / 100
                cell.bottom = (number("bottom") ?? 0) / 100
            }
            cells[id] = cell
        case "p":
            // Header/footer text lives in an independent sub-list. Its owner
            // remains editable because the text/style writers detach it first.
            let regionParagraph = paragraphStack.count == 1 && parentElements.last == "sublist"
                && ["header", "footer"].contains(parentElements.dropLast().last ?? "")
            if !regionParagraph { markCurrentParagraphReadOnly() }
            if !tableStack.isEmpty, tableStack.last?.cellID != nil {
                tableStack[tableStack.count - 1].paragraph += 1
            }
            paragraphStack.append(
                ParagraphContext(
                    ordinal: nextParagraphOrdinal,
                    cellID: tableStack.last?.cellID,
                    cellParagraph: max(0, tableStack.last?.paragraph ?? 0)
                )
            )
            nextParagraphOrdinal += 1
        case "t":
            if !paragraphStack.isEmpty { textDepth += 1 }
        case "tab":
            appendToCurrentParagraph("\t")
        case "linebreak":
            appendToCurrentParagraph("\n")
        case "hyphen", "hypen":
            appendToCurrentParagraph("-")
        case "nbspace":
            appendToCurrentParagraph("\u{00A0}")
        case "fwspace":
            appendToCurrentParagraph("\u{3000}")
        case "fieldbegin":
            let type = attributeDict.first { Self.localName($0.key).lowercased() == "type" }?.value
            if type?.uppercased() != "HYPERLINK" { markCurrentParagraphReadOnly() }
        case "fieldend":
            break
        default:
            if Self.unsafeParagraphElements.contains(name) {
                markCurrentParagraphReadOnly()
            }
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        guard !paragraphStack.isEmpty, textDepth > 0 else { return }
        paragraphStack[paragraphStack.count - 1].text.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = Self.localName(qName ?? elementName).lowercased()
        if !elementStack.isEmpty { elementStack.removeLast() }
        switch name {
        case "t":
            if textDepth > 0 { textDepth -= 1 }
        case "p":
            guard let paragraph = paragraphStack.popLast() else { return }
            completedParagraphs.append(paragraph)
        case "tc":
            if !tableStack.isEmpty { tableStack[tableStack.count - 1].cellID = nil }
        case "tbl":
            if !tableStack.isEmpty { tableStack.removeLast() }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard textDepth > 0 else { return }
        appendToCurrentParagraph(String(decoding: CDATABlock, as: UTF8.self))
    }

    private static func localName(_ name: String) -> String {
        String(name.split(separator: ":").last ?? Substring(name))
    }

    private func appendToCurrentParagraph(_ value: String) {
        guard !paragraphStack.isEmpty else { return }
        paragraphStack[paragraphStack.count - 1].text.append(value)
    }

    private func markCurrentParagraphReadOnly() {
        guard !paragraphStack.isEmpty else { return }
        paragraphStack[paragraphStack.count - 1].isEditable = false
    }

    private static let unsafeParagraphElements: Set<String> = [
        "arc", "chart", "compose", "connectline", "container", "curve",
        "dutmal", "ellipse", "equation",
        "formobject", "ole", "pic", "polygon", "rect", "shape", "video",
    ]
}

public nonisolated enum HWPXParagraphXMLPatcher {
    public struct ParagraphRange {
        public let outer: NSRange
    
    public init(outer: NSRange) {
        self.outer = outer
    }
}

    public struct TagToken {
        public let range: NSRange
        public let qualifiedName: String
        public let localName: String
        public let isClosing: Bool
        public let isSelfClosing: Bool
    
    public init(range: NSRange, qualifiedName: String, localName: String, isClosing: Bool, isSelfClosing: Bool) {
        self.range = range
        self.qualifiedName = qualifiedName
        self.localName = localName
        self.isClosing = isClosing
        self.isSelfClosing = isSelfClosing
    }
}

    public static func paragraphRanges(in xml: String) throws -> [NSRange] {
        let tokens = try tagTokens(in: xml)
        var starts: [NSRange] = []
        var ranges: [NSRange] = []
        for token in tokens where token.localName == "p" {
            if token.isClosing {
                guard let start = starts.popLast() else {
                    throw HWPDocumentEditingError.invalidDocument
                }
                ranges.append(
                    NSRange(
                        location: start.location,
                        length: NSMaxRange(token.range) - start.location
                    )
                )
            } else if token.isSelfClosing {
                ranges.append(token.range)
            } else {
                starts.append(token.range)
            }
        }
        guard starts.isEmpty else {
            throw HWPDocumentEditingError.invalidDocument
        }
        return ranges.sorted { $0.location < $1.location }
    }

    public static func apply(
        originalXML: String,
        originalBlocks: [HWPDocumentBlock],
        editedBlocks: [HWPDocumentBlock]
    ) throws -> String {
        let ranges = try paragraphRanges(in: originalXML)
        guard ranges.count == originalBlocks.count,
              editedBlocks.count == originalBlocks.count else {
            throw HWPDocumentEditingError.staleDocument
        }
        var result = originalXML as NSString
        for index in ranges.indices.reversed() {
            let original = originalBlocks[index]
            let edited = editedBlocks[index]
            guard original.id == edited.id else {
                throw HWPDocumentEditingError.staleDocument
            }
            guard original.text != edited.text else { continue }
            guard original.isEditable, edited.isEditable else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            // A nested paragraph edited earlier can change the owner's length.
            let range = try paragraphRanges(in: result as String)[index]
            let paragraph = result.substring(with: range)
            let detached = try HWPXDetachedRegions(paragraph)
            let patched = detached.restoring(try replaceText(in: detached.xml, with: edited.text))
            result = result.replacingCharacters(
                in: range,
                with: patched
            ) as NSString
        }
        return result as String
    }

    private static func replaceText(in paragraph: String, with text: String) throws -> String {
        let tokens = try tagTokens(in: paragraph)
        let ranges = try elementRanges(named: "run", tokens: tokens)
        guard !ranges.isEmpty else {
            return try replaceRunText(in: paragraph, with: text)
        }
        let source = paragraph as NSString
        let runTexts = try ranges.map {
            try HWPXEditableTextReader.read(source.substring(with: $0))
        }
        let replacements = HWPTextRunEditing.redistribute(text, originalSegments: runTexts)
        var result = source
        for index in ranges.indices.reversed() {
            let patched = try replaceRunText(
                in: source.substring(with: ranges[index]),
                with: replacements[index]
            )
            result = result.replacingCharacters(in: ranges[index], with: patched) as NSString
        }
        // Line positions are a cache of the old paragraph, not document content.
        let staleLines = try elementRanges(named: "linesegarray", tokens: tagTokens(in: result as String))
        for range in staleLines.reversed() {
            result = result.replacingCharacters(in: range, with: "") as NSString
        }
        return result as String
    }

    private static func elementRanges(named name: String, tokens: [TagToken]) throws -> [NSRange] {
        var starts: [TagToken] = []
        var result: [NSRange] = []
        for token in tokens where token.localName == name {
            if token.isClosing {
                guard let start = starts.popLast() else {
                    throw HWPDocumentEditingError.invalidDocument
                }
                if starts.isEmpty {
                    result.append(NSRange(location: start.range.location,
                                          length: NSMaxRange(token.range) - start.range.location))
                }
            } else if token.isSelfClosing {
                if starts.isEmpty { result.append(token.range) }
            } else {
                starts.append(token)
            }
        }
        guard starts.isEmpty else { throw HWPDocumentEditingError.invalidDocument }
        return result.sorted { $0.location < $1.location }
    }

    private static func replaceRunText(in paragraph: String, with text: String) throws -> String {
        let tokens = try tagTokens(in: paragraph)
        guard let paragraphStart = tokens.first(where: {
            ($0.localName == "p" || $0.localName == "run") && !$0.isClosing
        }) else {
            throw HWPDocumentEditingError.invalidDocument
        }
        let prefix = paragraphStart.qualifiedName.split(separator: ":").dropLast()
            .joined(separator: ":")
        let elementPrefix = prefix.isEmpty ? "" : prefix + ":"
        let encoded = encodedTextContent(text, prefix: elementPrefix)

        var textStarts: [TagToken] = []
        var textRanges: [(outer: NSRange, content: NSRange?)] = []
        for token in tokens where token.localName == "t" {
            if token.isClosing {
                guard let start = textStarts.popLast() else { continue }
                textRanges.append((
                    NSRange(
                        location: start.range.location,
                        length: NSMaxRange(token.range) - start.range.location
                    ),
                    NSRange(
                        location: NSMaxRange(start.range),
                        length: token.range.location - NSMaxRange(start.range)
                    )
                ))
            } else if token.isSelfClosing {
                textRanges.append((token.range, nil))
            } else {
                textStarts.append(token)
            }
        }
        textRanges.sort { $0.outer.location < $1.outer.location }

        if textRanges.isEmpty {
            let controls = try HWPXEditableTextReader.controlText.keys.flatMap {
                try elementRanges(named: $0, tokens: tokens)
            }
            if !controls.isEmpty {
                var cleaned = paragraph as NSString
                for range in controls.sorted(by: { $0.location > $1.location }) {
                    cleaned = cleaned.replacingCharacters(in: range, with: "") as NSString
                }
                return try replaceRunText(in: cleaned as String, with: text)
            }
        }
        if textRanges.isEmpty {
            let textElement = "<\(elementPrefix)t xml:space=\"preserve\">\(encoded)</\(elementPrefix)t>"
            let insertion = paragraphStart.localName == "run" ? textElement
                : "<\(elementPrefix)run>\(textElement)</\(elementPrefix)run>"
            if paragraphStart.isSelfClosing {
                let source = paragraph as NSString
                let start = source.substring(with: paragraphStart.range)
                let expandedStart = String(start.dropLast(2)) + ">"
                return expandedStart + insertion + "</\(paragraphStart.qualifiedName)>"
            }
            guard let close = tokens.last(where: {
                $0.localName == paragraphStart.localName && $0.isClosing
            }) else {
                throw HWPDocumentEditingError.invalidDocument
            }
            return (paragraph as NSString).replacingCharacters(
                in: NSRange(location: close.range.location, length: 0),
                with: insertion
            )
        }

        var patches: [(NSRange, String)] = []
        for (index, item) in textRanges.enumerated() {
            if let content = item.content {
                patches.append((content, index == 0 ? encoded : ""))
            } else if index == 0 {
                patches.append((item.outer,
                    "<\(elementPrefix)t xml:space=\"preserve\">\(encoded)</\(elementPrefix)t>"))
            }
        }
        for name in HWPXEditableTextReader.controlText.keys {
            for range in try elementRanges(named: name, tokens: tokens)
                where !textRanges.contains(where: {
                    $0.outer.location <= range.location && NSMaxRange($0.outer) >= NSMaxRange(range)
                }) {
                patches.append((range, ""))
            }
        }
        var result = paragraph as NSString
        for (range, replacement) in patches.sorted(by: { $0.0.location > $1.0.location }) {
            result = result.replacingCharacters(in: range, with: replacement) as NSString
        }
        return result as String
    }

    public static func encodedTextContent(_ text: String, prefix: String) -> String {
        var result = ""
        var buffer = ""
        func flush() {
            result += xmlText(buffer)
            buffer = ""
        }
        for character in text {
            switch character {
            case "\n":
                flush()
                result += "</\(prefix)t><\(prefix)lineBreak/><\(prefix)t xml:space=\"preserve\">"
            case "\t":
                flush()
                result += "</\(prefix)t><\(prefix)tab/><\(prefix)t xml:space=\"preserve\">"
            default:
                buffer.append(character)
            }
        }
        flush()
        return result
    }

    private static func xmlText(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    public static func tagTokens(in xml: String) throws -> [TagToken] {
        let source = xml as NSString
        var result: [TagToken] = []
        var cursor = 0
        while cursor < source.length {
            let opening = source.range(
                of: "<",
                options: [],
                range: NSRange(location: cursor, length: source.length - cursor)
            )
            if opening.location == NSNotFound { break }

            if source.substring(from: opening.location).hasPrefix("<!--") {
                let close = source.range(
                    of: "-->",
                    options: [],
                    range: NSRange(
                        location: opening.location + 4,
                        length: source.length - opening.location - 4
                    )
                )
                guard close.location != NSNotFound else {
                    throw HWPDocumentEditingError.invalidDocument
                }
                cursor = NSMaxRange(close)
                continue
            }
            if source.substring(from: opening.location).hasPrefix("<![CDATA[") {
                let close = source.range(
                    of: "]]>",
                    options: [],
                    range: NSRange(
                        location: opening.location + 9,
                        length: source.length - opening.location - 9
                    )
                )
                guard close.location != NSNotFound else {
                    throw HWPDocumentEditingError.invalidDocument
                }
                cursor = NSMaxRange(close)
                continue
            }

            var index = opening.location + 1
            var quote: unichar = 0
            var closingLocation: Int?
            while index < source.length {
                let character = source.character(at: index)
                if quote != 0 {
                    if character == quote { quote = 0 }
                } else if character == 34 || character == 39 {
                    quote = character
                } else if character == 62 {
                    closingLocation = index
                    break
                }
                index += 1
            }
            guard let closingLocation else {
                throw HWPDocumentEditingError.invalidDocument
            }
            let range = NSRange(
                location: opening.location,
                length: closingLocation - opening.location + 1
            )
            let raw = source.substring(with: range)
            cursor = NSMaxRange(range)
            if raw.hasPrefix("<?") || raw.hasPrefix("<!") { continue }
            var body = raw.dropFirst().dropLast()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isClosing = body.hasPrefix("/")
            if isClosing { body.removeFirst() }
            let isSelfClosing = body.hasSuffix("/")
            if isSelfClosing { body.removeLast() }
            let qualifiedName = body.prefix {
                !$0.isWhitespace && $0 != "/"
            }
            guard !qualifiedName.isEmpty else { continue }
            let name = String(qualifiedName)
            result.append(
                TagToken(
                    range: range,
                    qualifiedName: name,
                    localName: String(name.split(separator: ":").last ?? Substring(name))
                        .lowercased(),
                    isClosing: isClosing,
                    isSelfClosing: isSelfClosing
                )
            )
        }
        return result
    }
}

public nonisolated final class HWPXEditableTextReader: NSObject, XMLParserDelegate {
    public static let controlText = ["tab": "\t", "linebreak": "\n", "hyphen": "-",
                              "hypen": "-", "nbspace": "\u{00A0}", "fwspace": "\u{3000}"]
    private var text = ""
    private var textDepth = 0

    public static func read(_ fragment: String) throws -> String {
        let reader = HWPXEditableTextReader()
        let parser = XMLParser(data: Data(fragment.utf8))
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse() else { throw HWPDocumentEditingError.invalidDocument }
        return reader.text
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let name = String(elementName.split(separator: ":").last ?? "").lowercased()
        if name == "t" { textDepth += 1 }
        if let value = Self.controlText[name] { text += value }
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName.split(separator: ":").last == "t" { textDepth -= 1 }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        if textDepth > 0 { text += string }
    }

    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if textDepth > 0 { text += String(decoding: CDATABlock, as: UTF8.self) }
    }
}

public nonisolated final class HWPXEditingArchive {
    private let archive: Archive
    private let entries: [String: Entry]
    private let orderedPaths: [String]

    public var paths: [String] { orderedPaths }

    public init(data: Data) throws {
        do {
            archive = try Archive(data: data, accessMode: .read)
        } catch {
            throw HWPDocumentEditingError.invalidDocument
        }
        var mapped: [String: Entry] = [:]
        var ordered: [String] = []
        var entryCount = 0
        var expandedBytes: UInt64 = 0
        for entry in archive {
            entryCount += 1
            let addition = expandedBytes.addingReportingOverflow(entry.uncompressedSize)
            guard entryCount <= HWPXTextExtractor.maximumArchiveEntries,
                  !addition.overflow,
                  addition.partialValue <= UInt64(HWPXTextExtractor.maximumExpandedBytes),
                  entry.uncompressedSize <= UInt64(HWPXTextExtractor.maximumEntryBytes),
                  entry.type != .symlink,
                  Self.isSafePath(entry.path) else {
                throw HWPDocumentEditingError.limitExceeded
            }
            expandedBytes = addition.partialValue
            guard entry.type == .file else { continue }
            guard mapped[entry.path] == nil else {
                throw HWPDocumentEditingError.invalidDocument
            }
            mapped[entry.path] = entry
            ordered.append(entry.path)
        }
        entries = mapped
        orderedPaths = ordered
    }

    public func contains(_ path: String) -> Bool { entries[path] != nil }

    public func data(at path: String) throws -> Data {
        guard let entry = entries[path] else {
            throw HWPDocumentEditingError.invalidDocument
        }
        var result = Data()
        result.reserveCapacity(Int(entry.uncompressedSize))
        do {
            _ = try archive.extract(entry) { chunk in
                guard result.count + chunk.count <= HWPXTextExtractor.maximumEntryBytes else {
                    throw HWPDocumentEditingError.limitExceeded
                }
                result.append(chunk)
            }
        } catch let error as HWPDocumentEditingError {
            throw error
        } catch {
            throw HWPDocumentEditingError.invalidDocument
        }
        return result
    }

    public func repack(replacing replacements: [String: Data]) throws -> Data {
        let output = try Archive(accessMode: .create)
        var ordered = orderedPaths
        if let mimeIndex = ordered.firstIndex(of: "mimetype") {
            ordered.remove(at: mimeIndex)
            ordered.insert("mimetype", at: 0)
        }
        ordered += replacements.keys.filter { !ordered.contains($0) }.sorted()
        for path in ordered {
            guard Self.isSafePath(path) else { throw HWPDocumentEditingError.invalidDocument }
            let payload = try replacements[path] ?? data(at: path)
            try output.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(payload.count),
                compressionMethod: path == "mimetype" ? .none : .deflate
            ) { position, size in
                let lower = Int(position)
                let upper = min(payload.count, lower + size)
                guard lower < upper else { return Data() }
                return payload.subdata(in: lower..<upper)
            }
        }
        guard let result = output.data else {
            throw HWPDocumentEditingError.cannotSave
        }
        return result
    }

    private static func isSafePath(_ path: String) -> Bool {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        return !normalized.hasPrefix("/")
            && !normalized.split(separator: "/").contains("..")
    }
}

public nonisolated enum LegacyHWPXConverter {
    public static func convert(text: String) throws -> Data {
        let paragraphs = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(HWPXDocumentPackage.maximumBlocks)

        let body = paragraphs.enumerated().map { index, paragraph in
            let value = xmlText(String(paragraph))
            return "<hp:p id=\"\(index + 1)\" paraPrIDRef=\"0\" styleIDRef=\"0\" pageBreak=\"0\" columnBreak=\"0\" merged=\"0\"><hp:run charPrIDRef=\"0\"><hp:t xml:space=\"preserve\">\(value)</hp:t></hp:run></hp:p>"
        }.joined()

        let section = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <hs:sec xmlns:hs="http://www.hancom.co.kr/hwpml/2011/section" xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph">\(body)</hs:sec>
        """
        let entries: [(String, Data)] = [
            ("mimetype", Data("application/hwp+zip".utf8)),
            ("META-INF/container.xml", Data(containerXML.utf8)),
            ("META-INF/manifest.xml", Data(manifestXML.utf8)),
            ("version.xml", Data(versionXML.utf8)),
            ("settings.xml", Data(settingsXML.utf8)),
            ("Contents/header.xml", Data(headerXML.utf8)),
            ("Contents/section0.xml", Data(section.utf8)),
            ("Contents/content.hpf", Data(contentHPF.utf8)),
            ("Preview/PrvText.txt", Data(text.utf8)),
        ]
        let archive = try Archive(accessMode: .create)
        for (path, payload) in entries {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(payload.count),
                compressionMethod: path == "mimetype" ? .none : .deflate
            ) { position, size in
                let lower = Int(position)
                let upper = min(payload.count, lower + size)
                guard lower < upper else { return Data() }
                return payload.subdata(in: lower..<upper)
            }
        }
        guard let data = archive.data else {
            throw HWPDocumentEditingError.cannotSave
        }
        return data
    }

    private static func xmlText(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static let containerXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="Contents/content.hpf" media-type="application/hwpml-package+xml"/></rootfiles></container>
    """

    private static let manifestXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <manifest xmlns="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"><file-entry full-path="/" media-type="application/hwp+zip"/><file-entry full-path="Contents/content.hpf" media-type="application/hwpml-package+xml"/><file-entry full-path="Contents/header.xml" media-type="application/xml"/><file-entry full-path="Contents/section0.xml" media-type="application/xml"/></manifest>
    """

    private static let versionXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <hv:HCFVersion xmlns:hv="http://www.hancom.co.kr/hwpml/2011/version" targetApplication="WORDPROCESSOR" major="5" minor="1" micro="0" buildNumber="0" os="IOS" xmlVersion="1.2" application="RivoPad"/>
    """

    private static let settingsXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <ha:HWPApplicationSetting xmlns:ha="http://www.hancom.co.kr/hwpml/2011/app"/>
    """

    public static let headerXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <hh:head xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head" version="1.2" secCnt="1">
      <hh:beginNum page="1" footnote="1" endnote="1" pic="1" tbl="1" equation="1"/>
      <hh:refList>
        <hh:fontfaces itemCnt="7">
          <hh:fontface lang="HANGUL" fontCnt="1"><hh:font id="0" face="Apple SD Gothic Neo" type="TTF" isEmbedded="0"/></hh:fontface>
          <hh:fontface lang="LATIN" fontCnt="1"><hh:font id="0" face="Helvetica" type="TTF" isEmbedded="0"/></hh:fontface>
          <hh:fontface lang="HANJA" fontCnt="1"><hh:font id="0" face="Apple SD Gothic Neo" type="TTF" isEmbedded="0"/></hh:fontface>
          <hh:fontface lang="JAPANESE" fontCnt="1"><hh:font id="0" face="Hiragino Sans" type="TTF" isEmbedded="0"/></hh:fontface>
          <hh:fontface lang="OTHER" fontCnt="1"><hh:font id="0" face="Helvetica" type="TTF" isEmbedded="0"/></hh:fontface>
          <hh:fontface lang="SYMBOL" fontCnt="1"><hh:font id="0" face="Apple Symbols" type="TTF" isEmbedded="0"/></hh:fontface>
          <hh:fontface lang="USER" fontCnt="1"><hh:font id="0" face="Helvetica" type="TTF" isEmbedded="0"/></hh:fontface>
        </hh:fontfaces>
        <hh:borderFills itemCnt="1">
          <hh:borderFill id="0" threeD="0" shadow="0" centerLine="NONE" breakCellSeparateLine="0">
            <hh:slash type="NONE" Crooked="0" isCounter="0"/>
            <hh:backSlash type="NONE" Crooked="0" isCounter="0"/>
            <hh:leftBorder type="NONE" width="0.1 mm" color="#000000"/>
            <hh:rightBorder type="NONE" width="0.1 mm" color="#000000"/>
            <hh:topBorder type="NONE" width="0.1 mm" color="#000000"/>
            <hh:bottomBorder type="NONE" width="0.1 mm" color="#000000"/>
            <hh:diagonal type="NONE" width="0.1 mm" color="#000000"/>
          </hh:borderFill>
        </hh:borderFills>
        <hh:charProperties itemCnt="1">
          <hh:charPr id="0" height="1000" textColor="#000000" shadeColor="none" useFontSpace="0" useKerning="0" symMark="NONE" borderFillIDRef="0">
            <hh:fontRef hangul="0" latin="0" hanja="0" japanese="0" other="0" symbol="0" user="0"/>
            <hh:ratio hangul="100" latin="100" hanja="100" japanese="100" other="100" symbol="100" user="100"/>
            <hh:spacing hangul="0" latin="0" hanja="0" japanese="0" other="0" symbol="0" user="0"/>
            <hh:relSz hangul="100" latin="100" hanja="100" japanese="100" other="100" symbol="100" user="100"/>
            <hh:offset hangul="0" latin="0" hanja="0" japanese="0" other="0" symbol="0" user="0"/>
          </hh:charPr>
        </hh:charProperties>
        <hh:tabProperties itemCnt="1"><hh:tabPr id="0" autoTabLeft="0" autoTabRight="0"/></hh:tabProperties>
        <hh:numberings itemCnt="0"/>
        <hh:bullets itemCnt="0"/>
        <hh:paraProperties itemCnt="1">
          <hh:paraPr id="0" tabPrIDRef="0" condense="0" fontLineHeight="0" snapToGrid="1" suppressLineNumbers="0" checked="0">
            <hh:align horizontal="LEFT" vertical="BASELINE"/>
          </hh:paraPr>
        </hh:paraProperties>
        <hh:styles itemCnt="1">
          <hh:style id="0" type="PARA" name="바탕글" engName="Normal" paraPrIDRef="0" charPrIDRef="0" nextStyleIDRef="0" langID="1042" lockForm="0"/>
        </hh:styles>
      </hh:refList>
    </hh:head>
    """

    private static let contentHPF = """
    <?xml version="1.0" encoding="UTF-8"?>
    <opf:package xmlns:opf="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="RivoPad"><opf:metadata/><opf:manifest><opf:item id="header" href="header.xml" media-type="application/xml"/><opf:item id="section0" href="section0.xml" media-type="application/xml"/></opf:manifest><opf:spine><opf:itemref idref="section0"/></opf:spine></opf:package>
    """
}

/// Temporarily removes independent header/footer sub-lists while editing the
/// owning paragraph. Restore their exact bytes before writing the archive.
public nonisolated struct HWPXDetachedRegions {
    public let xml: String
    private let fragments: [(String, String)]
    public init(_ source: String) throws {
        let nodes = try ["header", "footer"].flatMap { try HWPFormattingXML.elements(source, name: $0) }
        var result = source, fragments: [(String, String)] = []
        for node in nodes.sorted(by: { $0.range.location > $1.range.location }) {
            let marker = "<!--hwp-region-\(UUID().uuidString)-->"
            result = (result as NSString).replacingCharacters(in: node.range, with: marker)
            fragments.append((marker, node.xml))
        }
        xml = result; self.fragments = fragments
    }
    public func restoring(_ value: String) -> String {
        fragments.reduce(value) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}
