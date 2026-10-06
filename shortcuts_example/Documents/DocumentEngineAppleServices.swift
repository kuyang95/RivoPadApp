import CoreText
import Foundation
import ImageIO
import RivoDocumentEngine
import UIKit

/// Installs the old iOS metrics/codecs without exposing Apple types to the engine.
nonisolated enum DocumentEngineAppleServices {
    static func install() {
        DocumentEnginePlatform.configure(
            textMeasurement: AppleHWPTextMeasurementProvider(),
            imageProcessing: AppleDocumentImageProvider(),
            // The app catalog first; the engine's own table covers keys it lacks.
            localize: { key in
                let language = AppLanguage.current()
                let localized = AppLocalization.string(key, language: language)
                guard localized == key, let code = language.localizationCode else { return localized }
                return DocumentEngineStrings.localized(key, language: code)
            },
            locale: { AppLanguage.current().locale })
    }
}

private nonisolated struct AppleHWPTextMeasurementProvider: HWPTextMeasurementProvider {
    func makeSession(_ request: HWPTextMeasurementRequest) -> any HWPTextMeasurementSession {
        AppleHWPTextMeasurementSession(request)
    }
}

private nonisolated final class AppleHWPTextMeasurementSession: HWPTextMeasurementSession {
    let request: HWPTextMeasurementRequest
    let attributed: NSAttributedString
    let typesetter: CTTypesetter
    var string: String { attributed.string }

    init(_ request: HWPTextMeasurementRequest) {
        self.request = request
        let runs = request.runs
        switch request.policy {
        case .replacement:
            let attributed = NSMutableAttributedString(string: "")
            for run in runs {
                let size = max(6, run.fontSizePoints ?? request.fallbackFontSize)
                var font =
                    run.fontName.map { CTFontCreateWithName($0 as CFString, size, nil) }
                    ?? CTFontCreateUIFontForLanguage(.system, size, nil)!
                var traits: CTFontSymbolicTraits = []
                if run.isBold { traits.insert(.boldTrait) }
                if run.isItalic { traits.insert(.italicTrait) }
                if !traits.isEmpty {
                    font = CTFontCreateCopyWithSymbolicTraits(font, size, nil, traits, traits) ?? font
                }
                var transform = CGAffineTransform(scaleX: run.fontWidthPercent / 100, y: 1)
                font = CTFontCreateCopyWithAttributes(font, size, &transform, nil)
                attributed.append(
                    NSAttributedString(
                        string: run.text,
                        attributes: [
                            NSAttributedString.Key(kCTFontAttributeName as String): font,
                            NSAttributedString.Key(kCTKernAttributeName as String): size * run.letterSpacingPercent
                                / 100,
                        ]))
            }
            self.attributed = attributed
        case .formatting:
            func measuredText(_ runs: [HWPDocumentTextRun]) -> NSAttributedString {

                let result = NSMutableAttributedString(string: "")
                for run in runs {
                    let size = run.displayFontSize(fallback: request.fallbackFontSize)
                    var font = CTFontCreateWithName((run.fontName ?? "Helvetica") as CFString, size, nil)
                    var traits: CTFontSymbolicTraits = []
                    if run.isBold { traits.insert(.boldTrait) }
                    if run.isItalic { traits.insert(.italicTrait) }
                    if !traits.isEmpty {
                        font = CTFontCreateCopyWithSymbolicTraits(font, size, nil, traits, traits) ?? font
                    }
                    var transform = CGAffineTransform(scaleX: run.fontWidthPercent / 100, y: 1)
                    font = CTFontCreateCopyWithAttributes(font, size, &transform, nil)
                    result.append(
                        NSAttributedString(
                            string: run.text,
                            attributes: [
                                NSAttributedString.Key(kCTFontAttributeName as String): font,
                                NSAttributedString.Key(kCTBaselineOffsetAttributeName as String):
                                    run.displayBaselineOffset(fallback: request.fallbackFontSize),
                                NSAttributedString.Key(kCTKernAttributeName as String): size * run.letterSpacingPercent
                                    / 100,
                            ]))
                }
                return result
            }
            self.attributed = measuredText(runs)
        case .flow:
            self.attributed = MainActor.assumeIsolated {
                let attributed = NSMutableAttributedString(string: "")
                for run in runs {
                    let size = run.displayFontSize(fallback: 10)
                    let resolved = HWPDocumentFontResolver.resolution(for: run).resolvedName
                    let base = resolved.flatMap { UIFont(name: $0, size: size) } ?? .systemFont(ofSize: size)
                    var traits = base.fontDescriptor.symbolicTraits
                    if run.isBold { traits.insert(.traitBold) }
                    if run.isItalic { traits.insert(.traitItalic) }
                    let descriptor = base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor
                    let font = UIFont(descriptor: descriptor, size: size)
                    var transform = CGAffineTransform(scaleX: run.fontWidthPercent / 100, y: 1)
                    let ctFont = CTFontCreateCopyWithAttributes(font as CTFont, size, &transform, nil)
                    var kern = size * run.letterSpacingPercent / 100
                    if let space = run.spaceWidthPoints, run.text.allSatisfy({ $0 == " " }) {
                        kern =
                            space * run.scriptScale * (1 + run.letterSpacingPercent / 100)
                            - (" " as NSString).size(withAttributes: [.font: font]).width
                    }
                    attributed.append(
                        NSAttributedString(
                            string: run.text,
                            attributes: [
                                NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
                                .baselineOffset: run.displayBaselineOffset(fallback: 10),
                                .kern: kern,
                            ]))
                }
                return attributed
            }
        case .listMarker:
            let run = runs[0]
            let size = run.fontSizePoints ?? request.fallbackFontSize
            let font = CTFontCreateWithName((run.fontName ?? "Helvetica") as CFString, size, nil)
            self.attributed = NSAttributedString(
                string: run.text,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        }
        self.typesetter = CTTypesetterCreateWithAttributedString(self.attributed)
    }

    func suggestLineBreak(atUTF16 offset: Int, widthPoints: Double) -> Int {
        CTTypesetterSuggestLineBreak(typesetter, offset, widthPoints)
    }
    func scriptLineHeight(inUTF16 range: NSRange, runs: [HWPDocumentTextRun], minimumPoints: Double) -> Double {
        let line = CTTypesetterCreateLine(typesetter, CFRange(location: range.location, length: range.length))
        return Self.scriptLineHeight(line, runs: runs, minimum: minimumPoints)
    }
    func isMetricEquivalent(to other: any HWPTextMeasurementSession) -> Bool {
        guard let other = other as? AppleHWPTextMeasurementSession else { return false }
        return attributed.isEqual(to: other.attributed)
    }
    var typographicWidthPoints: Double {
        CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil)
    }
    static func scriptLineHeight(_ line: CTLine, runs: [HWPDocumentTextRun], minimum: Double) -> Double {

        guard runs.contains(where: { $0.isSuperscript || $0.isSubscript }) else { return minimum }
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        // Core Text's line bounds omit the baseline offsets used by UITextView.
        // Include each shifted run's ascent/descent in the editable line area.
        for glyphRun in CTLineGetGlyphRuns(line) as! [CTRun] {
            let attributes = CTRunGetAttributes(glyphRun) as NSDictionary
            let offset =
                (attributes[kCTBaselineOffsetAttributeName] as? NSNumber
                ?? attributes[NSAttributedString.Key.baselineOffset.rawValue] as? NSNumber)?.doubleValue ?? 0
            var runAscent: CGFloat = 0
            var runDescent: CGFloat = 0
            var runLeading: CGFloat = 0
            CTRunGetTypographicBounds(glyphRun, CFRange(location: 0, length: 0), &runAscent, &runDescent, &runLeading)
            if let font = attributes[kCTFontAttributeName] as? UIFont {
                // UIKit includes the font's line gap in its editable fragment.
                runAscent = max(runAscent, font.ascender)
                runDescent = max(runDescent, -font.descender)
                runLeading = max(runLeading, font.lineHeight - font.ascender + font.descender)
            }
            ascent = max(ascent, runAscent + offset)
            descent = max(descent, runDescent - offset)
            leading = max(leading, runLeading)
        }
        return max(minimum, ceil(Double(ascent + descent + leading)))
    }
}

// Existing inline editor/renderers still operate on their own CTLine objects.
nonisolated extension HWPDocumentFormatting {
    static func scriptLineHeight(_ line: CTLine, runs: [HWPDocumentTextRun], minimum: Double) -> Double {
        AppleHWPTextMeasurementSession.scriptLineHeight(line, runs: runs, minimum: minimum)
    }
}

private nonisolated struct AppleDocumentImageProvider: DocumentEngineImageProvider {
    func metadata(of data: Data) -> DocumentEngineImageMetadata? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else { return nil }
        return DocumentEngineImageMetadata(pixelWidth: width.intValue, pixelHeight: height.intValue)
    }
    func normalizeHWPImage(_ source: Data) throws -> HWPImageEditing.ImportedImage {

        guard !source.isEmpty, source.count <= 20 * 1_024 * 1_024,
            let imageSource = CGImageSourceCreateWithData(source as CFData, nil),
            CGImageSourceGetCount(imageSource) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
            let rawWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let rawHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            throw HWPDocumentEditingError.invalidDocument
        }
        let width = rawWidth.intValue
        let height = rawHeight.intValue
        guard width > 0, height > 0, width <= 20_000, height <= 20_000,
            Int64(width) * Int64(height) <= 50_000_000
        else {
            throw HWPDocumentEditingError.limitExceeded
        }
        let maximum = 4_096
        let scale = min(1, Double(maximum) / Double(max(width, height)))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(Double(max(width, height)) * scale)),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            throw HWPDocumentEditingError.invalidDocument
        }
        let uiImage = UIImage(cgImage: cgImage)
        let hasAlpha =
            cgImage.alphaInfo == .first || cgImage.alphaInfo == .last
            || cgImage.alphaInfo == .premultipliedFirst || cgImage.alphaInfo == .premultipliedLast
        let encoded = hasAlpha ? uiImage.pngData() : uiImage.jpegData(compressionQuality: 0.9)
        guard let encoded, encoded.count <= 20 * 1_024 * 1_024 else {
            throw HWPDocumentEditingError.limitExceeded
        }
        return HWPImageEditing.ImportedImage(
            data: encoded, fileExtension: hasAlpha ? "png" : "jpg",
            mediaType: hasAlpha ? "image/png" : "image/jpeg",
            pixelWidth: cgImage.width, pixelHeight: cgImage.height)
    }
}
