import Foundation
import CoreText

/// Retains the style of unchanged characters. Insertions inherit the nearby
/// style; replacements inherit the first replaced character's style.
nonisolated enum HWPTextRunEditing {
    static func replacingText(in block: HWPDocumentBlock, with text: String) -> HWPDocumentBlock {
        guard text != block.text else { return block }
        let style = block.presentation
        let originalRuns = style.textRuns.isEmpty
            ? [HWPDocumentTextRun(text: block.text)] : style.textRuns
        let segments = redistribute(text, originalSegments: originalRuns.map(\.text))
        let runs = zip(originalRuns, segments).map { $0.replacingText($1) }
        let presentation = HWPDocumentBlockPresentation(
            styleName: style.styleName, alignment: style.alignment,
            outlineLevel: style.outlineLevel, leftMarginPoints: style.leftMarginPoints,
            rightMarginPoints: style.rightMarginPoints, firstLineIndentPoints: style.firstLineIndentPoints,
            spacingBeforePoints: style.spacingBeforePoints, spacingAfterPoints: style.spacingAfterPoints,
            pageBreakBefore: style.pageBreakBefore, textRuns: runs,
            paragraphBorder: style.paragraphBorder, lineSpacingPercent: style.lineSpacingPercent,
            list: style.list
        )
        return HWPDocumentBlock(
            id: block.id, sectionPath: block.sectionPath, paragraphIndex: block.paragraphIndex,
            text: text, tableLocation: block.tableLocation, isEditable: block.isEditable,
            presentation: presentation, region: block.region, images: block.images,
            lineLayouts: reflow(text: text, runs: runs, templates: block.lineLayouts),
            canvasObjects: block.canvasObjects, layoutContainerID: block.layoutContainerID, sourceParagraphID: block.sourceParagraphID, keepsParagraphBoundary: block.keepsParagraphBoundary
        )
    }

    private static func reflow(
        text: String, runs: [HWPDocumentTextRun], templates: [HWPDocumentLineLayout]
    ) -> [HWPDocumentLineLayout] {
        guard let first = templates.first else { return [] }
        let attributed = NSMutableAttributedString(string: "")
        for run in runs {
            let size = max(6, run.fontSizePoints ?? first.textHeightPoints)
            var font = run.fontName.map { CTFontCreateWithName($0 as CFString, size, nil) }
                ?? CTFontCreateUIFontForLanguage(.system, size, nil)!
            var traits: CTFontSymbolicTraits = []
            if run.isBold { traits.insert(.boldTrait) }
            if run.isItalic { traits.insert(.italicTrait) }
            if !traits.isEmpty {
                font = CTFontCreateCopyWithSymbolicTraits(font, size, nil, traits, traits) ?? font
            }
            var transform = CGAffineTransform(scaleX: run.fontWidthPercent / 100, y: 1)
            font = CTFontCreateCopyWithAttributes(font, size, &transform, nil)
            attributed.append(NSAttributedString(string: run.text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTKernAttributeName as String): size * run.letterSpacingPercent / 100,
            ]))
        }
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let source = text as NSString
        var result: [HWPDocumentLineLayout] = []
        var offset = 0
        var rawPosition = 0
        while offset < source.length {
            let index = result.count
            let template = templates[min(index, templates.count - 1)]
            var length = CTTypesetterSuggestLineBreak(typesetter, offset,
                max(template.widthPoints - template.textInsetPoints
                    - (template.listMarker?.reservedWidthPoints ?? 0), 1))
            if length <= 0 { length = source.rangeOfComposedCharacterSequence(at: offset).length }
            length = min(length, source.length - offset)
            let fragment = source.substring(with: NSRange(location: offset, length: length))
            let displayed = fragment.hasSuffix("\n") ? String(fragment.dropLast()) : fragment
            var runOffset = 0
            let lineRange = NSRange(location: offset, length: (displayed as NSString).length)
            let lineRuns = runs.compactMap { run -> HWPDocumentTextRun? in
                let runRange = NSRange(location: runOffset, length: (run.text as NSString).length)
                runOffset = NSMaxRange(runRange)
                let intersection = NSIntersectionRange(lineRange, runRange)
                guard intersection.length > 0 else { return nil }
                return run.replacingText(source.substring(with: intersection))
            }
            let previous = result.last
            let y = index < templates.count ? template.verticalPositionPoints
                : (previous?.verticalPositionPoints ?? template.verticalPositionPoints)
                    + max(template.lineHeightPoints, template.textHeightPoints, 1)
            let flags = (index < templates.count ? template.flags : template.flags & ~UInt32(3))
                & ~UInt32(0x0001_0000)
            result.append(HWPDocumentLineLayout(
                id: "\(first.id)-edit-\(index)", startCharacter: rawPosition,
                verticalPositionPoints: y, lineHeightPoints: template.lineHeightPoints,
                textHeightPoints: template.textHeightPoints, baselinePoints: template.baselinePoints,
                lineSpacingPoints: template.lineSpacingPoints, columnStartPoints: template.columnStartPoints,
                widthPoints: template.widthPoints, flags: flags, text: displayed, textRuns: lineRuns,
                baselineAlignment: template.baselineAlignment,
                textInsetPoints: template.textInsetPoints,
                listMarker: first.listMarker,
                showsListMarker: index == 0,
                endsParagraph: offset + length == source.length
            ))
            offset += length
            rawPosition += fragment.utf16.count + fragment.filter { $0 == "\t" }.count * 7
        }
        return result
    }

    static func redistribute(_ text: String, originalSegments: [String]) -> [String] {
        guard !originalSegments.isEmpty else { return [] }
        let original = originalSegments.flatMap { Array($0) }
        let owners = originalSegments.enumerated().flatMap { index, segment in
            Array(repeating: index, count: segment.count)
        }
        let replacement = Array(text)
        var output = Array(repeating: "", count: originalSegments.count)
        guard !original.isEmpty else {
            output[0] = text
            return output
        }

        var prefix = 0
        while prefix < min(original.count, replacement.count),
              original[prefix] == replacement[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(original.count, replacement.count) - prefix,
              original[original.count - suffix - 1]
                == replacement[replacement.count - suffix - 1] { suffix += 1 }

        var origins = Array<Int?>(repeating: nil, count: replacement.count)
        for index in 0..<prefix { origins[index] = index }
        for offset in 0..<suffix {
            origins[replacement.count - offset - 1] = original.count - offset - 1
        }
        let oldEnd = original.count - suffix
        let newEnd = replacement.count - suffix
        // Bound diff work for pasted/replaced paragraphs. The unchanged ends
        // still keep their styles when a very large replacement is coalesced.
        if (oldEnd - prefix) <= 1_000_000 / max(newEnd - prefix, 1) {
            let oldMiddle = Array(original[prefix..<oldEnd])
            let newMiddle = Array(replacement[prefix..<newEnd])
            let difference = newMiddle.difference(from: oldMiddle)
            var removed = Set<Int>()
            var inserted = Set<Int>()
            for change in difference {
                switch change {
                case .remove(let offset, _, _): removed.insert(offset)
                case .insert(let offset, _, _): inserted.insert(offset)
                }
            }
            let oldIndices = oldMiddle.indices.filter { !removed.contains($0) }
            let newIndices = newMiddle.indices.filter { !inserted.contains($0) }
            for (old, new) in zip(oldIndices, newIndices) {
                origins[prefix + new] = prefix + old
            }
        }

        var index = 0
        var previousOrigin: Int?
        while index < replacement.count {
            if let origin = origins[index] {
                output[owners[origin]].append(replacement[index])
                previousOrigin = origin
                index += 1
                continue
            }
            let start = index
            while index < replacement.count, origins[index] == nil { index += 1 }
            let nextOrigin = index < replacement.count ? origins[index]! : original.count
            let gapStart = previousOrigin.map { $0 + 1 } ?? 0
            let styleOrigin = gapStart < nextOrigin
                ? gapStart
                : previousOrigin ?? min(nextOrigin, original.count - 1)
            output[owners[styleOrigin]] += String(replacement[start..<index])
        }
        return output
    }
}

private extension HWPDocumentTextRun {
    nonisolated func replacingText(_ text: String) -> HWPDocumentTextRun {
        HWPDocumentTextRun(text: text, fontName: fontName, alternateFontName: alternateFontName,
            baseFontName: baseFontName, fontSignature: fontSignature, fontSizePoints: fontSizePoints,
            fontWidthPercent: fontWidthPercent, letterSpacingPercent: letterSpacingPercent,
            baselinePositionPercent: baselinePositionPercent, textColorRGB: textColorRGB,
            backgroundColorRGB: backgroundColorRGB,
            isBold: isBold, isItalic: isItalic, isUnderlined: isUnderlined,
            isStruckThrough: isStruckThrough, isSuperscript: isSuperscript, isSubscript: isSubscript,
            hyperlink: hyperlink, spaceWidthPoints: spaceWidthPoints, tabWidthPoints: tabWidthPoints)
    }
}
