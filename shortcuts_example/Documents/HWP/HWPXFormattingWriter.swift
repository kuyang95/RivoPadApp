import Foundation

/// Edits only affected XML fragments. Unknown metadata and controls stay intact.
nonisolated enum HWPXFormattingWriter {
    static func apply(to data: Data, originals: [HWPDocumentBlock], edited: [HWPDocumentBlock]) throws -> Data {
        let current = try HWPXDocumentPackage.load(from: data)
        let parsed = Dictionary(uniqueKeysWithValues: current.blocks.map { ($0.id, $0) })
        let changes = Dictionary(uniqueKeysWithValues: zip(originals, edited).filter { old, new in
            if HWPDocumentFormatting.requiresStyleWrite(from: old, to: new) { return true }
            // Typing Korean text with spaces can select a different language
            // font from the same HWPX character style. Reconcile the parsed
            // text against the actual typing runs even without a toolbar edit.
            return old.text != new.text && new.presentation.textRuns.map(\.text).joined() == new.text
                && parsed[new.id].map { !HWPDocumentFormatting.matches($0, new, includingCell: false) } == true
        }.map { ($0.0.id, $0.1) })
        guard !changes.isEmpty else { return data }
        guard changes.values.allSatisfy(\.isEditable) else { throw HWPDocumentEditingError.unsupportedEdit }
        let archive = try HWPXEditingArchive(data: data)
        if !archive.contains("Contents/header.xml") {
            let originalsByID = Dictionary(uniqueKeysWithValues: originals.map { ($0.id, $0) })
            // Minimal HWPX files can omit the optional style table. Plain typing
            // still saves correctly because the paragraph patch has already
            // written the text; only explicit style changes require a header.
            guard changes.allSatisfy({ id, block in
                originalsByID[id].map { !HWPDocumentFormatting.hasChanges(from: $0, to: block) } == true
            }) else { throw HWPDocumentEditingError.unsupportedEdit }
            return data
        }
        var header = String(decoding: try archive.data(at: "Contents/header.xml"), as: UTF8.self)
        let prefix = try HWPFormattingXML.prefix(header)
        let fallback = LegacyHWPXConverter.headerXML.replacingOccurrences(of: "hh:", with: prefix)
        var characters = try HWPFormattingXML.dictionary(header, name: "charpr")
        var paragraphs = try HWPFormattingXML.dictionary(header, name: "parapr")
        let defaultChar = try HWPFormattingXML.elements(fallback, name: "charpr").first!.xml
        let defaultPara = try HWPFormattingXML.elements(fallback, name: "parapr").first!.xml
        var nextChar = (characters.keys.compactMap(Int.init).max() ?? -1) + 1
        var nextPara = (paragraphs.keys.compactMap(Int.init).max() ?? -1) + 1
        var charAdditions = "", paraAdditions = ""
        var charCache: [String: String] = [:], paraCache: [String: String] = [:]
        var listCache: [String: String] = [:]
        func listID(_ list: HWPParagraphList) throws -> String {
            let key = "\(list.kind.rawValue):\(list.definitionID)"
            if let cached = listCache[key] { return cached }
            let name = list.kind == .number ? "numbering" : "bullet"
            let definitions = try HWPFormattingXML.dictionary(header, name: name)
            if definitions[list.definitionID] != nil { return list.definitionID }
            guard list.isSimple, list.level == 0 else { throw HWPDocumentEditingError.unsupportedEdit }
            let id = (definitions.keys.compactMap(Int.init).max() ?? 0) + 1
            guard id < 65_535 else { throw HWPDocumentEditingError.limitExceeded }
            let xml = HWPListXML.definition(list, id: id, prefix: prefix)
            header = try HWPListXML.appending(xml, kind: list.kind, to: header, prefix: prefix, count: definitions.count + 1)
            listCache[key] = String(id)
            return String(id)
        }
        let languages = ["hangul", "latin", "hanja", "japanese", "other", "symbol", "user"]

        func fontID(_ name: String, language: String) throws -> String {
            let groups = try HWPFormattingXML.elements(header, name: "fontface")
            guard let group = try groups.first(where: { try HWPFormattingXML.attribute($0.xml, "lang")?.lowercased() == language }) else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            let fonts = try HWPFormattingXML.elements(group.xml, name: "font")
            for font in fonts where try HWPFormattingXML.attribute(font.xml, "face") == name {
                return try HWPFormattingXML.attribute(font.xml, "id") ?? "0"
            }
            let id = (try fonts.compactMap { try HWPFormattingXML.attribute($0.xml, "id").flatMap(Int.init) }.max() ?? -1) + 1
            guard id < 65_535 else { throw HWPDocumentEditingError.limitExceeded }
            let addition = "<\(prefix)font id=\"\(id)\" face=\"\(HWPFormattingXML.escaped(name))\" type=\"TTF\" isEmbedded=\"0\"/>"
            var updated = try HWPFormattingXML.append(addition, to: group.xml)
            updated = try HWPFormattingXML.setAttribute(updated, "fontCnt", String(fonts.count + 1))
            header = (header as NSString).replacingCharacters(in: group.range, with: updated)
            return String(id)
        }

        func characterID(baseID: String, old: HWPDocumentTextRun, new: HWPDocumentTextRun) throws -> String {
            let original = characters[baseID] ?? defaultChar
            var xml = original
            if let name = new.fontName, name != old.fontName {
                var refs = try HWPFormattingXML.elements(xml, name: "fontref").first?.xml ?? "<\(prefix)fontRef/>"
                for language in languages { refs = try HWPFormattingXML.setAttribute(refs, language, fontID(name, language: language)) }
                xml = try HWPFormattingXML.replaceOrAppend(xml, name: "fontref", replacement: refs)
            }
            if let size = new.fontSizePoints, size != old.fontSizePoints {
                xml = try HWPFormattingXML.setAttribute(xml, "height", String(Int((size * 100).rounded())))
                var relative = try HWPFormattingXML.elements(xml, name: "relsz").first?.xml ?? "<\(prefix)relSz/>"
                for language in languages { relative = try HWPFormattingXML.setAttribute(relative, language, "100") }
                xml = try HWPFormattingXML.replaceOrAppend(xml, name: "relsz", replacement: relative)
            }
            if new.isBold != old.isBold { xml = try HWPFormattingXML.replaceOrAppend(xml, name: "bold", replacement: new.isBold ? "<\(prefix)bold/>" : "") }
            for (name, before, after) in [("ratio", old.fontWidthPercent, new.fontWidthPercent),
                ("spacing", old.letterSpacingPercent, new.letterSpacingPercent),
                ("offset", old.baselinePositionPercent, new.baselinePositionPercent)] where before != after {
                var entry = try HWPFormattingXML.elements(xml, name: name).first?.xml ?? "<\(prefix)\(name)/>"
                for language in languages { entry = try HWPFormattingXML.setAttribute(entry, language, String(Int(after.rounded()))) }
                xml = try HWPFormattingXML.replaceOrAppend(xml, name: name, replacement: entry)
            }
            if new.isItalic != old.isItalic { xml = try HWPFormattingXML.replaceOrAppend(xml, name: "italic", replacement: new.isItalic ? "<\(prefix)italic/>" : "") }
            if new.isUnderlined != old.isUnderlined {
                var underline = try HWPFormattingXML.elements(xml, name: "underline").first?.xml ?? "<\(prefix)underline shape=\"SOLID\" color=\"#000000\"/>"
                underline = try HWPFormattingXML.setAttribute(underline, "type", new.isUnderlined ? "BOTTOM" : "NONE")
                xml = try HWPFormattingXML.replaceOrAppend(xml, name: "underline", replacement: underline)
            }
            if new.textColorRGB != old.textColorRGB {
                xml = try HWPFormattingXML.setAttribute(xml, "textColor", String(format: "#%06X", new.textColorRGB ?? 0))
            }
            if new.backgroundColorRGB != old.backgroundColorRGB {
                xml = try HWPFormattingXML.setAttribute(xml, "shadeColor", new.backgroundColorRGB.map { String(format: "#%06X", $0) } ?? "none")
            }
            if new.isStruckThrough != old.isStruckThrough {
                let strike = "<\(prefix)strikeout shape=\"SOLID\" color=\"\(String(format: "#%06X", new.textColorRGB ?? 0))\"/>"
                xml = try HWPFormattingXML.replaceOrAppend(xml, name: "strikeout", replacement: new.isStruckThrough ? strike : "")
            }
            if new.isSuperscript != old.isSuperscript {
                xml = try HWPFormattingXML.replaceOrAppend(xml, name: "supscript", replacement: new.isSuperscript ? "<\(prefix)supscript/>" : "")
            }
            if new.isSubscript != old.isSubscript {
                xml = try HWPFormattingXML.replaceOrAppend(xml, name: "subscript", replacement: new.isSubscript ? "<\(prefix)subscript/>" : "")
            }
            guard xml != original else { return baseID }
            let key = try HWPFormattingXML.setAttribute(xml, "id", "")
            if let id = charCache[key] { return id }
            guard nextChar < 65_535 else { throw HWPDocumentEditingError.limitExceeded }
            let id = String(nextChar); nextChar += 1
            xml = try HWPFormattingXML.setAttribute(xml, "id", id)
            characters[id] = xml; charCache[key] = id; charAdditions += xml
            return id
        }

        func paragraphID(baseID: String, old: HWPDocumentBlockPresentation, new: HWPDocumentBlockPresentation) throws -> String {
            let original = paragraphs[baseID] ?? defaultPara
            var xml = original
            if old.pageBreakBefore && !new.pageBreakBefore {
                for setting in try HWPFormattingXML.elements(xml, name: "breaksetting").reversed() {
                    xml = (xml as NSString).replacingCharacters(in: setting.range,
                        with: try HWPFormattingXML.setAttribute(setting.xml, "pageBreakBefore", "0"))
                }
            }
            if new.list != old.list {
                let id = try new.list.map(listID) ?? "0"
                let type = new.list.map { $0.kind == .number ? "NUMBER" : "BULLET" } ?? "NONE"
                let heading = "<\(prefix)heading type=\"\(type)\" idRef=\"\(id)\" level=\"\(new.list?.level ?? 0)\"/>"
                xml = try HWPFormattingXML.replaceOrAppend(xml, name: "heading", replacement: heading)
            }
            if new.alignment != old.alignment {
                var alignment = try HWPFormattingXML.elements(xml, name: "align").first?.xml ?? "<\(prefix)align vertical=\"BASELINE\"/>"
                let value = switch new.alignment { case .leading: "LEFT"; case .trailing: "RIGHT"; case .centered: "CENTER"; case .justified: "JUSTIFY"; case .distributed: "DISTRIBUTE" }
                alignment = try HWPFormattingXML.setAttribute(alignment, "horizontal", value)
                xml = try HWPFormattingXML.replaceOrAppend(xml, name: "align", replacement: alignment)
            }
            let before = [old.leftMarginPoints, old.rightMarginPoints, old.firstLineIndentPoints, old.spacingBeforePoints, old.spacingAfterPoints]
            let after = [new.leftMarginPoints, new.rightMarginPoints, new.firstLineIndentPoints, new.spacingBeforePoints, new.spacingAfterPoints]
            if before != after {
                func updateMargin(_ source: String) throws -> String {
                    var margin = source
                    // HWPX can carry parallel unit-specific and fallback styles.
                    // Preserve both branches and the common-namespace children.
                    for (index, name) in [(2, "intent"), (0, "left"), (1, "right"), (3, "prev"), (4, "next")] {
                        let hasIndent = !(try HWPFormattingXML.elements(margin, name: "indent")).isEmpty
                        let currentName = name == "intent" && hasIndent ? "indent" : name
                        let existing = try HWPFormattingXML.elements(margin, name: currentName).first?.xml
                        guard before[index] != after[index] || existing == nil else { continue }
                        var entry = existing ?? "<hc:\(currentName) xmlns:hc=\"http://www.hancom.co.kr/hwpml/2011/core\"/>"
                        entry = try HWPFormattingXML.setAttribute(entry, "value", String(Int((after[index] * 100).rounded())))
                        entry = try HWPFormattingXML.setAttribute(entry, "unit", "HWPUNIT")
                        margin = try HWPFormattingXML.replaceOrAppend(margin, name: currentName, replacement: entry)
                    }
                    return margin
                }
                let margins = try HWPFormattingXML.elements(xml, name: "margin")
                if margins.isEmpty {
                    xml = try HWPFormattingXML.append(updateMargin("<\(prefix)margin/>"), to: xml)
                } else {
                    for margin in margins.reversed() {
                        xml = (xml as NSString).replacingCharacters(in: margin.range, with: try updateMargin(margin.xml))
                    }
                }
            }
            if let percent = new.lineSpacingPercent, percent != old.lineSpacingPercent {
                let spacing = "<\(prefix)lineSpacing type=\"PERCENT\" value=\"\(Int(percent.rounded()))\" unit=\"HWPUNIT\"/>"
                let variants = try HWPFormattingXML.elements(xml, name: "linespacing")
                if variants.isEmpty { xml = try HWPFormattingXML.append(spacing, to: xml) }
                else {
                    for variant in variants.reversed() {
                        xml = (xml as NSString).replacingCharacters(in: variant.range, with: spacing)
                    }
                }
            }
            guard xml != original else { return baseID }
            let key = try HWPFormattingXML.setAttribute(xml, "id", "")
            if let id = paraCache[key] { return id }
            guard nextPara < 65_535 else { throw HWPDocumentEditingError.limitExceeded }
            let id = String(nextPara); nextPara += 1
            xml = try HWPFormattingXML.setAttribute(xml, "id", id)
            paragraphs[id] = xml; paraCache[key] = id; paraAdditions += xml
            return id
        }

        var replacements: [String: Data] = [:]
        for section in current.sections {
            var xml = section.xml
            let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: xml)
            for index in ranges.indices.reversed() {
                let before = section.blocks[index]
                guard let block = changes[before.id] else { continue }
                let range = try HWPXParagraphXMLPatcher.paragraphRanges(in: xml)[index]
                let detached = try HWPXDetachedRegions((xml as NSString).substring(with: range))
                var paragraph = detached.xml
                let paragraphPrefix = try HWPFormattingXML.prefix(paragraph)
                var styleOffset = 0
                let styleBoundaries = HWPDocumentFormatting.runs(in: before).map { run in
                    defer { styleOffset += run.text.utf16.count }
                    return styleOffset
                }
                var offset = 0
                var patches: [(NSRange, String)] = []
                let existingRuns = try HWPFormattingXML.elements(paragraph, name: "run")
                for source in existingRuns {
                    let sourceText = try HWPXEditableTextReader.read(source.xml)
                    let start = offset; offset += sourceText.utf16.count
                    let originalID = try HWPFormattingXML.attribute(source.xml, "charPrIDRef") ?? "0"
                    var newRuns = "", runOffset = 0
                    for run in HWPDocumentFormatting.runs(in: block) {
                        let runRange = NSRange(location: runOffset, length: run.text.utf16.count)
                        runOffset += runRange.length
                        let intersection = NSIntersectionRange(runRange, NSRange(location: start, length: sourceText.utf16.count))
                        guard intersection.length > 0 || (block.text.isEmpty && newRuns.isEmpty) else { continue }
                        let cuts = [intersection.location] + styleBoundaries.filter {
                            $0 > intersection.location && $0 < NSMaxRange(intersection)
                        } + [NSMaxRange(intersection)]
                        for (lower, upper) in zip(cuts, cuts.dropFirst()) {
                            let value = (block.text as NSString).substring(with: NSRange(location: lower, length: upper - lower))
                            let oldRun = HWPDocumentFormatting.run(at: lower, in: before)
                            let id = try characterID(baseID: originalID, old: oldRun, new: run)
                            let encoded = HWPXParagraphXMLPatcher.encodedTextContent(value, prefix: paragraphPrefix)
                            // Preserve non-text children once, on the first split part.
                            let extras = newRuns.isEmpty ? try HWPFormattingXML.withoutTextChildren(source.xml) : ""
                            var opening = try HWPFormattingXML.opening(source.xml)
                            opening = try HWPFormattingXML.setAttribute(opening, "charPrIDRef", id)
                            if opening.hasSuffix("/>") { opening = String(opening.dropLast(2)) + ">" }
                            newRuns += opening + extras + "<\(paragraphPrefix)t xml:space=\"preserve\">\(encoded)</\(paragraphPrefix)t></\(paragraphPrefix)run>"
                        }
                    }
                    if !newRuns.isEmpty { patches.append((source.range, newRuns)) }
                }
                if existingRuns.isEmpty, block.text.isEmpty {
                    let run = HWPDocumentFormatting.runs(in: block)[0]
                    let id = try characterID(baseID: "0", old: HWPDocumentFormatting.run(at: 0, in: before), new: run)
                    paragraph = try HWPFormattingXML.append("<\(paragraphPrefix)run charPrIDRef=\"\(id)\"><\(paragraphPrefix)t/></\(paragraphPrefix)run>", to: paragraph)
                } else {
                    for (range, value) in patches.reversed() { paragraph = (paragraph as NSString).replacingCharacters(in: range, with: value) }
                }
                let paraID = try paragraphID(baseID: HWPFormattingXML.attribute(paragraph, "paraPrIDRef") ?? "0",
                    old: before.presentation, new: block.presentation)
                paragraph = try HWPFormattingXML.setAttribute(paragraph, "paraPrIDRef", paraID)
                if before.presentation.pageBreakBefore != block.presentation.pageBreakBefore {
                    paragraph = try HWPFormattingXML.setAttribute(paragraph, "pageBreak", block.presentation.pageBreakBefore ? "1" : "0")
                }
                if !block.lineLayouts.isEmpty {
                    let lines = block.lineLayouts.map { line in
                        "<\(paragraphPrefix)lineseg textpos=\"\(line.startCharacter)\" vertpos=\"\(Int((line.verticalPositionPoints * 100).rounded()))\" vertsize=\"\(Int((line.lineHeightPoints * 100).rounded()))\" textheight=\"\(Int((line.textHeightPoints * 100).rounded()))\" baseline=\"\(Int((line.baselinePoints * 100).rounded()))\" spacing=\"\(Int((line.lineSpacingPoints * 100).rounded()))\" horzpos=\"\(Int((line.columnStartPoints * 100).rounded()))\" horzsize=\"\(Int((line.widthPoints * 100).rounded()))\" flags=\"\(line.flags)\"/>"
                    }.joined()
                    paragraph = try HWPFormattingXML.replaceOrAppend(paragraph, name: "linesegarray",
                        replacement: "<\(paragraphPrefix)linesegarray>\(lines)</\(paragraphPrefix)linesegarray>")
                }
                xml = (xml as NSString).replacingCharacters(in: range, with: detached.restoring(paragraph))
            }
            if xml != section.xml { replacements[section.path] = Data(xml.utf8) }
        }
        if !charAdditions.isEmpty { header = try HWPFormattingXML.appendToGroup(header, name: "charproperties", additions: charAdditions, count: characters.count) }
        if !paraAdditions.isEmpty { header = try HWPFormattingXML.appendToGroup(header, name: "paraproperties", additions: paraAdditions, count: paragraphs.count) }
        replacements["Contents/header.xml"] = Data(header.utf8)
        let result = try archive.repack(replacing: replacements)
        let saved = try HWPXDocumentPackage.load(from: result)
        for block in saved.blocks {
            if let expected = changes[block.id], !HWPDocumentFormatting.matches(block, expected,
                includingCell: false, includingHyperlinks: false) { throw HWPDocumentEditingError.cannotSave }
        }
        return result
    }
}

nonisolated enum HWPFormattingXML {
    struct Element { let range: NSRange; let xml: String }

    static func elements(_ xml: String, name: String) throws -> [Element] {
        var stack: [HWPXParagraphXMLPatcher.TagToken] = [], result: [Element] = []
        for token in try HWPXParagraphXMLPatcher.tagTokens(in: xml) where token.localName == name {
            if token.isClosing {
                guard let start = stack.popLast() else { throw HWPDocumentEditingError.invalidDocument }
                let range = NSRange(location: start.range.location, length: NSMaxRange(token.range) - start.range.location)
                result.append(Element(range: range, xml: (xml as NSString).substring(with: range)))
            } else if token.isSelfClosing { result.append(Element(range: token.range, xml: (xml as NSString).substring(with: token.range))) }
            else { stack.append(token) }
        }
        guard stack.isEmpty else { throw HWPDocumentEditingError.invalidDocument }
        return result.sorted { $0.range.location < $1.range.location }
    }

    static func dictionary(_ xml: String, name: String) throws -> [String: String] {
        var result: [String: String] = [:]
        for element in try elements(xml, name: name) {
            if let id = try attribute(element.xml, "id") { result[id] = element.xml }
        }
        return result
    }

    static func opening(_ xml: String) throws -> String {
        guard let token = try HWPXParagraphXMLPatcher.tagTokens(in: xml).first else { throw HWPDocumentEditingError.invalidDocument }
        return (xml as NSString).substring(with: token.range)
    }

    static func prefix(_ xml: String) throws -> String {
        guard let name = try HWPXParagraphXMLPatcher.tagTokens(in: xml).first?.qualifiedName else { throw HWPDocumentEditingError.invalidDocument }
        return name.contains(":") ? String(name.prefix { $0 != ":" }) + ":" : ""
    }

    static func attribute(_ xml: String, _ name: String) throws -> String? {
        let tag = try opening(xml)
        let regex = try NSRegularExpression(pattern: "\\s" + NSRegularExpression.escapedPattern(for: name) + "\\s*=\\s*([\"'])(.*?)\\1", options: [.caseInsensitive, .dotMatchesLineSeparators])
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: tag.utf16.count)) else { return nil }
        return (tag as NSString).substring(with: match.range(at: 2))
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
    }

    static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func setAttribute(_ xml: String, _ name: String, _ value: String) throws -> String {
        guard let token = try HWPXParagraphXMLPatcher.tagTokens(in: xml).first else { throw HWPDocumentEditingError.invalidDocument }
        let tag = (xml as NSString).substring(with: token.range)
        let regex = try NSRegularExpression(pattern: "\\s" + NSRegularExpression.escapedPattern(for: name) + "\\s*=\\s*([\"'])(.*?)\\1", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let pair = " \(name)=\"\(escaped(value))\""
        let updated: String
        if let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: tag.utf16.count)) {
            updated = (tag as NSString).replacingCharacters(in: match.range, with: pair)
        } else {
            let ending = tag.hasSuffix("/>") ? "/>" : ">"
            updated = String(tag.dropLast(ending.count)) + pair + ending
        }
        return (xml as NSString).replacingCharacters(in: token.range, with: updated)
    }

    static func append(_ child: String, to xml: String) throws -> String {
        let tokens = try HWPXParagraphXMLPatcher.tagTokens(in: xml)
        guard let first = tokens.first, let last = tokens.last else { throw HWPDocumentEditingError.invalidDocument }
        if first.isSelfClosing {
            let tag = (xml as NSString).substring(with: first.range)
            return (xml as NSString).replacingCharacters(in: first.range,
                with: String(tag.dropLast(2)) + ">" + child + "</\(first.qualifiedName)>")
        }
        return (xml as NSString).replacingCharacters(in: NSRange(location: last.range.location, length: 0), with: child)
    }

    static func replaceOrAppend(_ xml: String, name: String, replacement: String) throws -> String {
        if let element = try elements(xml, name: name).first {
            return (xml as NSString).replacingCharacters(in: element.range, with: replacement)
        }
        return replacement.isEmpty ? xml : try append(replacement, to: xml)
    }

    static func appendToGroup(_ xml: String, name: String, additions: String, count: Int) throws -> String {
        guard let group = try elements(xml, name: name).first else { throw HWPDocumentEditingError.unsupportedEdit }
        let updated = try setAttribute(append(additions, to: group.xml), "itemCnt", String(count))
        return (xml as NSString).replacingCharacters(in: group.range, with: updated)
    }

    static func withoutTextChildren(_ run: String) throws -> String {
        let tokens = try HWPXParagraphXMLPatcher.tagTokens(in: run)
        guard let first = tokens.first, let last = tokens.last, !first.isSelfClosing else { return "" }
        let start = NSMaxRange(first.range)
        var body = (run as NSString).substring(with: NSRange(location: start, length: last.range.location - start))
        // Remove outer text nodes first; their nested controls disappear with them.
        for name in ["t", "tab", "linebreak", "hyphen", "hypen", "nbspace", "fwspace"] {
            for node in try elements(body, name: name).reversed() { body = (body as NSString).replacingCharacters(in: node.range, with: "") }
        }
        return body
    }
}
