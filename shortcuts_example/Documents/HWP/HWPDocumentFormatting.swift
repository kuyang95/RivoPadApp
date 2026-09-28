import Foundation
import CoreText
import UIKit

nonisolated extension HWPDocumentTextRun {
    // Keep stored point size intact: superscript/subscript are independent flags.
    var scriptScale: Double { isSuperscript || isSubscript ? 0.65 : 1 }

    func displayFontSize(fallback: Double) -> Double {
        (fontSizePoints ?? fallback) * scriptScale
    }

    func displayBaselineOffset(fallback: Double) -> Double {
        let size = fontSizePoints ?? fallback
        return size * (baselinePositionPercent / 100 + (isSuperscript ? 0.32 : isSubscript ? -0.22 : 0))
    }
}

nonisolated enum HWPFormattingCommand {
    case font(String), size(Double), bold(Bool), italic(Bool), underline(Bool), color(UInt32)
    case highlight(UInt32?), strikethrough(Bool), superscript(Bool), `subscript`(Bool)
    case clearCharacterFormatting
    case cell(HWPCellFormat)
    case list(HWPParagraphList?)
    case alignment(HWPParagraphAlignment)
    case paragraph(left: Double, right: Double, indent: Double, before: Double, after: Double, linePercent: Double?)

    var isParagraph: Bool {
        switch self { case .alignment, .paragraph, .list, .cell: return true; default: return false }
    }

    func applying(to source: HWPDocumentTextRun) -> HWPDocumentTextRun {
        var run = source
        switch self {
        case .font(let name):
            run.fontName = name; run.alternateFontName = nil; run.baseFontName = nil; run.fontSignature = nil
        case .size(let size): run.fontSizePoints = min(144, max(6, size))
        case .bold(let flag): run.isBold = flag
        case .italic(let flag): run.isItalic = flag
        case .underline(let flag): run.isUnderlined = flag
        case .color(let rgb): run.textColorRGB = rgb & 0xFFFFFF
        case .highlight(let rgb): run.backgroundColorRGB = rgb.map { $0 & 0xFFFFFF }
        case .strikethrough(let flag): run.isStruckThrough = flag
        case .superscript(let flag):
            run.isSuperscript = flag
            if flag { run.isSubscript = false }
        case .subscript(let flag):
            run.isSubscript = flag
            if flag { run.isSuperscript = false }
        case .clearCharacterFormatting:
            run = HWPDocumentTextRun(text: source.text, fontName: "바탕", fontSizePoints: 10,
                textColorRGB: 0, hyperlink: source.hyperlink,
                spaceWidthPoints: source.spaceWidthPoints == nil ? nil : 5,
                tabWidthPoints: source.tabWidthPoints)
        default: break
        }
        return run
    }
}

nonisolated enum HWPDocumentFormatting {
    static func runs(in block: HWPDocumentBlock) -> [HWPDocumentTextRun] {
        let runs = block.presentation.textRuns
        return !runs.isEmpty && runs.map(\.text).joined() == block.text
            ? runs : [HWPDocumentTextRun(text: block.text, fontSizePoints: 10)]
    }

    static func apply(_ command: HWPFormattingCommand, to block: HWPDocumentBlock,
                      range: NSRange) -> HWPDocumentBlock {
        guard block.isEditable else { return block }
        if case .cell(let format) = command { return HWPCellFormatting.apply(format, to: block) }
        var style = block.presentation
        if command.isParagraph {
            switch command {
            case .list(let value):
                guard HWPListFormatting.supports(block) else { return block }
                style.list = value
                style.outlineLevel = nil
            case .alignment(let value): style.alignment = value
            case let .paragraph(left, right, indent, before, after, percent):
                style.leftMarginPoints = min(360, max(0, left))
                style.rightMarginPoints = min(360, max(0, right))
                style.firstLineIndentPoints = min(180, max(-180, indent))
                style.spacingBeforePoints = min(144, max(0, before))
                style.spacingAfterPoints = min(144, max(0, after))
                style.lineSpacingPercent = percent.map { min(300, max(100, $0)) }
            default: break
            }
        } else {
            guard range.location >= 0, range.length >= 0,
                  range.location <= block.text.utf16.count,
                  range.length <= block.text.utf16.count - range.location,
                  Range(range, in: block.text) != nil else { return block }
            let boundaries = Set(block.text.indices.map { $0.utf16Offset(in: block.text) } + [block.text.utf16.count])
            guard boundaries.contains(range.location), boundaries.contains(NSMaxRange(range)) else { return block }
            if block.text.isEmpty {
                style.textRuns = [command.applying(to: runs(in: block)[0])]
            } else {
                guard range.length > 0 else { return block }
                var offset = 0
                style.textRuns = runs(in: block).flatMap { run -> [HWPDocumentTextRun] in
                    let source = run.text as NSString
                    let runRange = NSRange(location: offset, length: source.length)
                    offset += source.length
                    let selected = NSIntersectionRange(runRange, range)
                    guard selected.length > 0 else { return [run] }
                    let start = selected.location - runRange.location
                    let end = start + selected.length
                    var pieces: [HWPDocumentTextRun] = []
                    if start > 0 { pieces.append(run.withText(source.substring(to: start))) }
                    pieces.append(command.applying(to: run.withText(source.substring(with: NSRange(location: start, length: selected.length)))))
                    if end < source.length { pieces.append(run.withText(source.substring(from: end))) }
                    return pieces
                }
            }
        }
        guard style != block.presentation else { return block }
        return replacingPresentation(of: block, with: style)
    }

    static func replacingPresentation(of block: HWPDocumentBlock,
                                      with style: HWPDocumentBlockPresentation,
                                      text: String? = nil) -> HWPDocumentBlock {
        let value = text ?? block.text
        let lines = reflow(text: value, style: style, original: block)
        return HWPDocumentBlock(id: block.id, sectionPath: block.sectionPath,
            paragraphIndex: block.paragraphIndex, text: value, tableLocation: block.tableLocation,
            isEditable: block.isEditable, presentation: style, region: block.region,
            images: block.images, lineLayouts: lines, canvasObjects: block.canvasObjects,
            layoutContainerID: block.layoutContainerID, sourceParagraphID: block.sourceParagraphID, keepsParagraphBoundary: block.keepsParagraphBoundary)
    }

    static func hasChanges(from original: HWPDocumentBlock, to edited: HWPDocumentBlock) -> Bool {
        if edited.text != original.text,
           edited.presentation.textRuns.map(\.text).joined() != edited.text { return false }
        let expected = HWPTextRunEditing.replacingText(in: original, with: edited.text).presentation
        var old = expected, new = edited.presentation
        old.list?.ordinal = 1; new.list?.ordinal = 1
        return old != new
    }

    static func requiresStyleWrite(from original: HWPDocumentBlock, to edited: HWPDocumentBlock) -> Bool {
        // Entering or leaving the empty state can change the parser's language
        // fallback. Reconcile the actual parsed font with the intended typing
        // style, including blank paragraphs created by a page break.
        hasChanges(from: original, to: edited)
            || (original.text.isEmpty != edited.text.isEmpty
                && edited.presentation.textRuns.map(\.text).joined() == edited.text)
    }

    static func scriptLineHeight(_ line: CTLine, runs: [HWPDocumentTextRun], minimum: Double) -> Double {
        guard runs.contains(where: { $0.isSuperscript || $0.isSubscript }) else { return minimum }
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        // Core Text's line bounds omit the baseline offsets used by UITextView.
        // Include each shifted run's ascent/descent in the editable line area.
        for glyphRun in CTLineGetGlyphRuns(line) as! [CTRun] {
            let attributes = CTRunGetAttributes(glyphRun) as NSDictionary
            let offset = (attributes[kCTBaselineOffsetAttributeName] as? NSNumber
                ?? attributes[NSAttributedString.Key.baselineOffset.rawValue] as? NSNumber)?.doubleValue ?? 0
            var runAscent: CGFloat = 0, runDescent: CGFloat = 0, runLeading: CGFloat = 0
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

    static func run(at location: Int, in block: HWPDocumentBlock) -> HWPDocumentTextRun {
        let all = runs(in: block)
        var offset = 0
        for run in all {
            offset += run.text.utf16.count
            if location < offset { return run }
        }
        return all.last ?? HWPDocumentTextRun(text: "")
    }

    /// Compare semantic style spans, not parser-dependent language/run splits.
    static func matches(_ saved: HWPDocumentBlock, _ requested: HWPDocumentBlock,
                        includingCell: Bool = true, includingHyperlinks: Bool = true) -> Bool {
        guard saved.text == requested.text else { return false }
        if includingCell, !HWPCellFormatting.matches(saved, requested) { return false }
        let a = saved.presentation, b = requested.presentation
        guard (a.list == nil) == (b.list == nil),
              b.list.map { a.list?.matches($0) == true } ?? true else { return false }
        guard a.pageBreakBefore == b.pageBreakBefore, a.alignment == b.alignment,
              abs(a.leftMarginPoints - b.leftMarginPoints) < 0.02,
              abs(a.rightMarginPoints - b.rightMarginPoints) < 0.02,
              abs(a.firstLineIndentPoints - b.firstLineIndentPoints) < 0.02,
              abs(a.spacingBeforePoints - b.spacingBeforePoints) < 0.02,
              abs(a.spacingAfterPoints - b.spacingAfterPoints) < 0.02,
              b.lineSpacingPercent == nil || abs((a.lineSpacingPercent ?? 0) - (b.lineSpacingPercent ?? 0)) < 0.02 else { return false }
        var positions = Set([0])
        for block in [saved, requested] {
            var offset = 0
            for run in runs(in: block) { positions.insert(offset); offset += run.text.utf16.count }
        }
        for position in positions where position < max(1, requested.text.utf16.count) {
            let x = run(at: position, in: saved), y = run(at: position, in: requested)
            guard y.fontName == nil || x.fontName == y.fontName,
                  y.fontSizePoints == nil || abs((x.fontSizePoints ?? 0) - (y.fontSizePoints ?? 0)) < 0.02,
                  x.isBold == y.isBold, x.isItalic == y.isItalic, x.isUnderlined == y.isUnderlined,
                  x.isStruckThrough == y.isStruckThrough,
                  x.isSuperscript == y.isSuperscript, x.isSubscript == y.isSubscript,
                  x.backgroundColorRGB == y.backgroundColorRGB,
                  !includingHyperlinks || x.hyperlink == y.hyperlink,
                  abs(x.fontWidthPercent - y.fontWidthPercent) < 0.02,
                  abs(x.letterSpacingPercent - y.letterSpacingPercent) < 0.02,
                  abs(x.baselinePositionPercent - y.baselinePositionPercent) < 0.02,
                  (x.textColorRGB ?? 0) == (y.textColorRGB ?? 0) else { return false }
        }
        return true
    }

    private static func reflow(text: String, style: HWPDocumentBlockPresentation,
                               original: HWPDocumentBlock) -> [HWPDocumentLineLayout] {
        guard let first = original.lineLayouts.first else { return [] }
        let old = original.presentation
        let marker = style.list?.marker(in: original)
            ?? (style.list == old.list ? first.listMarker : nil)
        let leftDelta = style.leftMarginPoints - old.leftMarginPoints
        let rightDelta = style.rightMarginPoints - old.rightMarginPoints
        let indentDelta = style.firstLineIndentPoints - old.firstLineIndentPoints
        let width = max(16, first.widthPoints - first.textInsetPoints - leftDelta - rightDelta)
        func measuredText(_ runs: [HWPDocumentTextRun]) -> NSAttributedString {
            let result = NSMutableAttributedString(string: "")
            for run in runs {
                let size = run.displayFontSize(fallback: first.textHeightPoints)
                var font = CTFontCreateWithName((run.fontName ?? "Helvetica") as CFString, size, nil)
                var traits: CTFontSymbolicTraits = []
                if run.isBold { traits.insert(.boldTrait) }
                if run.isItalic { traits.insert(.italicTrait) }
                if !traits.isEmpty { font = CTFontCreateCopyWithSymbolicTraits(font, size, nil, traits, traits) ?? font }
                var transform = CGAffineTransform(scaleX: run.fontWidthPercent / 100, y: 1)
                font = CTFontCreateCopyWithAttributes(font, size, &transform, nil)
                result.append(NSAttributedString(string: run.text, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTBaselineOffsetAttributeName as String): run.displayBaselineOffset(fallback: first.textHeightPoints),
                    NSAttributedString.Key(kCTKernAttributeName as String): size * run.letterSpacingPercent / 100]))
            }
            return result
        }
        let attributed = measuredText(style.textRuns)
        guard attributed.string == text else { return original.lineLayouts }
        // Color, underline and alignment do not invalidate stored line metrics.
        if style.list == old.list, text == original.text, leftDelta == 0, rightDelta == 0, indentDelta == 0,
           style.spacingBeforePoints == old.spacingBeforePoints,
           style.lineSpacingPercent == old.lineSpacingPercent,
           attributed.isEqual(to: measuredText(old.textRuns)) {
            return original.lineLayouts.map { line in
                var visible = 0, raw = 0
                for unit in text.utf16 {
                    if raw >= line.startCharacter { break }
                    raw += unit == 9 ? 8 : 1; visible += 1
                }
                var offset = 0
                let range = NSRange(location: visible, length: line.text.utf16.count)
                let runs = style.textRuns.compactMap { run -> HWPDocumentTextRun? in
                    let part = NSIntersectionRange(range, NSRange(location: offset, length: run.text.utf16.count))
                    defer { offset += run.text.utf16.count }
                    return part.length > 0 ? run.withText((text as NSString).substring(with: part)) : nil
                }
                return HWPDocumentLineLayout(id: line.id, startCharacter: line.startCharacter,
                    verticalPositionPoints: line.verticalPositionPoints, lineHeightPoints: line.lineHeightPoints,
                    textHeightPoints: line.textHeightPoints, baselinePoints: line.baselinePoints,
                    lineSpacingPoints: line.lineSpacingPoints, columnStartPoints: line.columnStartPoints,
                    widthPoints: line.widthPoints, flags: line.flags, text: line.text, textRuns: runs,
                    baselineAlignment: line.baselineAlignment, textInsetPoints: line.textInsetPoints,
                    listMarker: line.listMarker, showsListMarker: line.showsListMarker, endsParagraph: line.endsParagraph)
            }
        }
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let source = text as NSString
        var result: [HWPDocumentLineLayout] = [], offset = 0, raw = 0
        var y = first.verticalPositionPoints + style.spacingBeforePoints - old.spacingBeforePoints
        repeat {
            let index = result.count
            let inset = index == 0 ? indentDelta : -old.firstLineIndentPoints
            let available = max(16, width - inset - (marker?.reservedWidthPoints ?? 0))
            var count = offset < source.length ? CTTypesetterSuggestLineBreak(typesetter, offset, available) : 0
            if count == 0, offset < source.length { count = source.rangeOfComposedCharacterSequence(at: offset).length }
            let textRange = NSRange(location: offset, length: min(count, source.length - offset))
            let fragment = source.substring(with: textRange)
            let shown = fragment.hasSuffix("\n") ? String(fragment.dropLast()) : fragment
            var runOffset = 0
            let lineRuns = style.textRuns.compactMap { run -> HWPDocumentTextRun? in
                let range = NSRange(location: runOffset, length: run.text.utf16.count)
                runOffset += range.length
                let part = NSIntersectionRange(range, NSRange(location: offset, length: shown.utf16.count))
                return part.length > 0 ? run.withText(source.substring(with: part)) : nil
            }
            let size = lineRuns.compactMap(\.fontSizePoints).max() ?? style.textRuns.first?.fontSizePoints ?? first.textHeightPoints
            let gap = style.lineSpacingPercent.map { size * ($0 / 100 - 1) } ?? first.lineSpacingPoints
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: textRange.location, length: textRange.length))
            let height = scriptLineHeight(line, runs: lineRuns, minimum: max(1, size))
            result.append(HWPDocumentLineLayout(id: "\(original.id)-format-\(index)", startCharacter: raw,
                verticalPositionPoints: y, lineHeightPoints: height, textHeightPoints: max(1, size),
                baselinePoints: first.baselinePoints * size / max(1, first.textHeightPoints), lineSpacingPoints: gap,
                columnStartPoints: first.columnStartPoints + leftDelta + inset,
                widthPoints: max(16, first.widthPoints - leftDelta - rightDelta - inset),
                flags: index == 0 ? first.flags & ~UInt32(0x10000) : 0,
                text: shown, textRuns: lineRuns, baselineAlignment: first.baselineAlignment, textInsetPoints: first.textInsetPoints,
                listMarker: marker, showsListMarker: index == 0,
                endsParagraph: NSMaxRange(textRange) == source.length))
            y += height + gap
            offset += textRange.length
            raw += fragment.utf16.count + fragment.filter { $0 == "\t" }.count * 7
        } while offset < source.length
        return result
    }
}
