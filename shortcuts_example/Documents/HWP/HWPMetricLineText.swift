import RivoDocumentEngine
import CoreText
import SwiftUI
import UIKit

/// Draws one cached HWP line with Core Text. Unlike SwiftUI's Text fitting,
/// this preserves the per-language width ratio, letter spacing and baseline
/// position that the HWP writer stored in the character shape record.
struct HWPMetricLineText: UIViewRepresentable {
    let text: String
    let runs: [HWPDocumentTextRun]
    let fallbackSize: Double
    let alignment: HWPParagraphAlignment
    let baselinePoints: Double
    var baselineAlignment: HWPDocumentLineBaselineAlignment = .font
    var isLastLine = true
    var listMarker: HWPDocumentListMarker? = nil
    var showsListMarker = true
    var searchBlock: HWPDocumentBlock? = nil
    var searchLine: HWPDocumentLineLayout? = nil
    @Environment(\.hwpDocumentSearch) private var search

    func makeUIView(context: Context) -> HWPMetricLineUIView {
        HWPMetricLineUIView()
    }

    func updateUIView(_ view: HWPMetricLineUIView, context: Context) {
        view.update(
            text: text,
            runs: runs,
            fallbackSize: fallbackSize,
            alignment: alignment,
            baselinePoints: baselinePoints,
            baselineAlignment: baselineAlignment,
            isLastLine: isLastLine,
            listMarker: listMarker,
            showsListMarker: showsListMarker,
            highlightRange: searchBlock.flatMap { block in searchLine.flatMap { search.range(in: block, line: $0) } }
        )
    }
}

final class HWPMetricLineUIView: UIView {
    private struct DrawableRun {
        let line: CTLine
        let advance: CGFloat
        let widthScale: CGFloat
        let ascender: CGFloat
        let inkBounds: CGRect
        let spaceCount: Int
        let backgroundColorRGB: UInt32?
        let fontSize: CGFloat
        let baselineOffset: CGFloat
        let strikeColor: UIColor?
    }

    private var text = ""
    private var runs: [HWPDocumentTextRun] = []
    private var fallbackSize = 12.0
    private var paragraphAlignment = HWPParagraphAlignment.leading
    private var storedBaselinePoints = 0.0
    private var baselineAlignment = HWPDocumentLineBaselineAlignment.font
    private var isLastLine = true
    private var listMarker: HWPDocumentListMarker?
    private var showsListMarker = true
    private var highlightRange: NSRange?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isAccessibilityElement = true
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isOpaque = false
        backgroundColor = .clear
        isAccessibilityElement = true
        contentMode = .redraw
    }

    func update(
        text: String,
        runs: [HWPDocumentTextRun],
        fallbackSize: Double,
        alignment: HWPParagraphAlignment,
        baselinePoints: Double,
        baselineAlignment: HWPDocumentLineBaselineAlignment = .font,
        isLastLine: Bool = true,
        listMarker: HWPDocumentListMarker? = nil,
        showsListMarker: Bool = true,
        highlightRange: NSRange? = nil
    ) {
        guard self.text != text
                || self.runs != runs
                || self.fallbackSize != fallbackSize
                || paragraphAlignment != alignment
                || storedBaselinePoints != baselinePoints
                || self.baselineAlignment != baselineAlignment
                || self.isLastLine != isLastLine
                || self.listMarker != listMarker
                || self.showsListMarker != showsListMarker
                || self.highlightRange != highlightRange else { return }
        self.text = text
        self.runs = runs
        self.fallbackSize = fallbackSize
        paragraphAlignment = alignment
        storedBaselinePoints = baselinePoints
        self.baselineAlignment = baselineAlignment
        self.isLastLine = isLastLine
        self.listMarker = listMarker
        self.showsListMarker = showsListMarker
        self.highlightRange = highlightRange
        accessibilityLabel = (showsListMarker ? listMarker.map { $0.run.text + " " } ?? "" : "") + text
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), bounds.width > 0 else {
            return
        }
        let drawableRuns = makeDrawableRuns()
        guard !drawableRuns.isEmpty || (showsListMarker && listMarker != nil) else { return }

        let naturalWidth = drawableRuns.reduce(CGFloat.zero) {
            $0 + $1.advance * $1.widthScale
        }
        let markerWidth = CGFloat(listMarker?.reservedWidthPoints ?? 0)
        let availableWidth = max(bounds.width - markerWidth, 1)
        let fitScale = naturalWidth > availableWidth
            ? max(availableWidth / max(naturalWidth, 1), 0.5)
            : 1
        let renderedWidth = naturalWidth * fitScale
        let startX: CGFloat
        switch paragraphAlignment {
        case .trailing:
            startX = max(availableWidth - renderedWidth, 0)
        case .centered:
            startX = max((availableWidth - renderedWidth) / 2, 0)
        case .justified, .distributed, .leading:
            startX = 0
        }

        let fallbackBaseline = drawableRuns.map(\.ascender).max() ?? 0
        let storedBaseline = storedBaselinePoints > 0
            ? CGFloat(storedBaselinePoints)
            : fallbackBaseline
        let inkTop = drawableRuns.map(\.inkBounds.maxY).max() ?? fallbackBaseline
        let inkBottom = drawableRuns.map(\.inkBounds.minY).min() ?? 0
        // A CENTER paragraph stores the line's center as its reference, not
        // a Latin font baseline. Convert that reference for the selected font.
        let baselineFromTop: CGFloat
        switch baselineAlignment {
        case .font: baselineFromTop = storedBaseline
        case .top: baselineFromTop = storedBaseline + inkTop
        case .center: baselineFromTop = storedBaseline + (inkTop + inkBottom) / 2
        case .bottom: baselineFromTop = storedBaseline + inkBottom
        }
        let baselineY = bounds.height - min(max(baselineFromTop, 0), bounds.height)

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)

        if showsListMarker, let marker = listMarker {
            if marker.isLegacyCircle {
                // Retain the legacy circle's ink size and baseline even if
                // the installed font gives Unicode BLACK CIRCLE a large glyph.
                let size = CGFloat(marker.run.fontSizePoints ?? 10)
                context.setFillColor(color(marker.run.textColorRGB).cgColor)
                context.fillEllipse(in: CGRect(x: size * 0.08, y: baselineY + size * 0.2,
                    width: size * 0.56, height: size * 0.56))
            } else if let mark = makeDrawableRuns(sourceRuns: [marker.run]).first {
                context.saveGState()
                context.translateBy(x: 0, y: baselineY)
                context.scaleBy(x: mark.widthScale, y: 1)
                context.textPosition = .zero
                CTLineDraw(mark.line, context)
                context.restoreGState()
            }
        }

        var cursorX = startX + markerWidth
        let spaceCount = drawableRuns.reduce(0) { $0 + $1.spaceCount }
        let shouldJustify = paragraphAlignment == .distributed
            || (paragraphAlignment == .justified && !isLastLine)
        let extraPerSpace = shouldJustify && spaceCount > 0
            ? max(0, availableWidth - renderedWidth) / CGFloat(spaceCount) : 0
        var textOffset = 0
        for run in drawableRuns {
            let horizontalScale = run.widthScale * fitScale
            let extra = extraPerSpace * CGFloat(run.spaceCount)
            let justified = extra > 0 ? CTLineCreateJustifiedLine(
                run.line, 1, Double(run.advance + extra / horizontalScale)
            ) : nil
            if let background = run.backgroundColorRGB {
                context.setFillColor(color(background).cgColor)
                context.fill(CGRect(x: cursorX, y: baselineY + run.baselineOffset - run.fontSize * 0.15,
                    width: run.advance * horizontalScale + extra, height: run.fontSize))
            }
            let length = CTLineGetStringRange(run.line).length
            if let highlightRange {
                let selected = NSIntersectionRange(highlightRange, NSRange(location: textOffset, length: length))
                if selected.length > 0 {
                    let line = justified ?? run.line
                    let start = CTLineGetOffsetForStringIndex(line, selected.location - textOffset, nil)
                    let end = CTLineGetOffsetForStringIndex(line, NSMaxRange(selected) - textOffset, nil)
                    context.setFillColor(UIColor.systemYellow.withAlphaComponent(0.65).cgColor)
                    context.fill(CGRect(x: cursorX + min(start, end) * horizontalScale,
                        y: baselineY + run.baselineOffset - run.fontSize * 0.25,
                        width: max(2, abs(end - start) * horizontalScale), height: run.fontSize * 1.25))
                }
            }
            textOffset += length
            context.saveGState()
            context.translateBy(x: cursorX, y: baselineY)
            context.scaleBy(x: horizontalScale, y: 1)
            context.textPosition = .zero
            CTLineDraw(justified ?? run.line, context)
            context.restoreGState()
            if let strikeColor = run.strikeColor {
                // CTLineDraw does not provide UIKit's strikethrough decoration.
                context.setStrokeColor(strikeColor.cgColor)
                context.setLineWidth(max(0.5, run.fontSize / 16))
                let y = baselineY + run.baselineOffset + run.fontSize * 0.3
                context.move(to: CGPoint(x: cursorX, y: y))
                context.addLine(to: CGPoint(x: cursorX + run.advance * horizontalScale + extra, y: y))
                context.strokePath()
            }
            // Core Text can decline justification for a space-only run.
            // Its allocated gap still belongs between the adjacent words.
            cursorX += run.advance * horizontalScale + extra
        }
        context.restoreGState()
    }

    private func makeDrawableRuns(sourceRuns: [HWPDocumentTextRun]? = nil) -> [DrawableRun] {
        let effectiveRuns: [HWPDocumentTextRun]
        if let sourceRuns {
            effectiveRuns = sourceRuns
        } else if runs.isEmpty {
            effectiveRuns = [HWPDocumentTextRun(
                text: text,
                fontSizePoints: fallbackSize
            )]
        } else {
            effectiveRuns = runs
        }

        return effectiveRuns.compactMap { run in
            let value = run.text
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "")
            guard !value.isEmpty else { return nil }
            let size = CGFloat(run.displayFontSize(fallback: fallbackSize))
            let font = resolvedFont(for: run, size: size)
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color(run.textColorRGB),
            ]
            // Several bundled substitutes (MaruBuri, PureBatang, Gulim) ship
            // a single weight, so a bold trait request silently falls back
            // to regular. Emulate Hancom's fake bold with a fill+stroke pass.
            if run.isBold,
               !font.fontDescriptor.symbolicTraits.contains(.traitBold) {
                attributes[.strokeWidth] = -2.5
                attributes[.strokeColor] = color(run.textColorRGB)
            }
            if run.isItalic, !font.fontDescriptor.symbolicTraits.contains(.traitItalic) {
                attributes[.obliqueness] = 0.2
            }
            let kern = size * CGFloat(run.letterSpacingPercent) / 100
            if kern != 0 { attributes[.kern] = kern }
            if run.isUnderlined {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            let baseline = run.displayBaselineOffset(fallback: fallbackSize)
            if baseline != 0 { attributes[.baselineOffset] = baseline }

            let attributed = NSMutableAttributedString(string: value, attributes: attributes)
            applyCompatibleHangulMetrics(to: attributed, run: run, font: font)
            let line = CTLineCreateWithAttributedString(attributed)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            var advance = CGFloat(CTLineGetTypographicBounds(
                line,
                &ascent,
                &descent,
                &leading
            ))
            if let width = run.spaceWidthPoints, value.allSatisfy({ $0 == " " }) {
                advance = CGFloat(value.count) * max(CGFloat(width * run.scriptScale)
                    * (1 + CGFloat(run.letterSpacingPercent) / 100), 0)
            }
            if let width = run.tabWidthPoints, value == "\t" {
                advance = CGFloat(width)
            }
            return DrawableRun(
                line: line,
                advance: max(advance, 0),
                widthScale: run.tabWidthPoints != nil ? 1 : CGFloat(run.fontWidthPercent / 100),
                ascender: ascent,
                inkBounds: CTLineGetBoundsWithOptions(line, .useGlyphPathBounds),
                spaceCount: value.filter { $0 == " " }.count,
                backgroundColorRGB: run.backgroundColorRGB,
                fontSize: size,
                baselineOffset: baseline,
                strikeColor: run.isStruckThrough ? color(run.textColorRGB) : nil
            )
        }
    }

    private func applyCompatibleHangulMetrics(
        to attributed: NSMutableAttributedString, run: HWPDocumentTextRun, font: UIFont
    ) {
        let resolution = HWPDocumentFontResolver.resolution(for: run)
        guard resolution.kind == .compatible else { return }
        let source = attributed.string as NSString
        if let symbolFont = UIFont(name: "Dotum-Regular", size: font.pointSize) {
            for index in 0..<source.length where [0x203B, 0x25CB, 0x261E].contains(Int(source.character(at: index))) {
                attributed.addAttribute(.font, value: symbolFont, range: NSRange(location: index, length: 1))
            }
        }
        guard ["Pretendard", "SUIT", "NanumSquareNeo"].contains(where: font.fontName.hasPrefix) else { return }
        // These modern Gothic substitutes have proportional Korean advances
        // (about 0.86–0.95 em). The legacy faces they replace use a full em.
        // Adjust Korean glyphs only; Latin and punctuation keep their metrics.
        var character: UniChar = 0xAC00
        var glyph: CGGlyph = 0
        CTFontGetGlyphsForCharacters(font as CTFont, &character, &glyph, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font as CTFont, .horizontal, &glyph, &advance, 1)
        guard advance.width > 0 else { return }
        var matrix = CGAffineTransform(scaleX: font.pointSize / advance.width, y: 1)
        let fullWidthFont = CTFontCreateCopyWithAttributes(font as CTFont, font.pointSize, &matrix, nil)
        for index in 0..<source.length {
            let code = source.character(at: index)
            if (0xAC00...0xD7AF).contains(code) || (0x3130...0x318F).contains(code) {
                attributed.addAttribute(NSAttributedString.Key(kCTFontAttributeName as String),
                    value: fullWidthFont, range: NSRange(location: index, length: 1))
            }
        }
    }

    private func resolvedFont(
        for run: HWPDocumentTextRun,
        size: CGFloat
    ) -> UIFont {
        let resolution = HWPDocumentFontResolver.resolution(for: run)
        let base = resolution.resolvedName.flatMap { UIFont(name: $0, size: size) }
            ?? UIFont.systemFont(ofSize: size)
        var traits = base.fontDescriptor.symbolicTraits
        if run.isBold { traits.insert(.traitBold) }
        if run.isItalic { traits.insert(.traitItalic) }
        guard traits != base.fontDescriptor.symbolicTraits,
              let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    private func color(_ rgb: UInt32?) -> UIColor {
        guard let rgb else { return .black }
        return UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
