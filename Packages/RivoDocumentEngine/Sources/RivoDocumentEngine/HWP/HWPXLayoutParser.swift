import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Resolves HWPX references into the same page scene used by the binary HWP reader.
/// XML is inspected locally; referenced assets are restricted to the validated ZIP.
public nonisolated final class HWPXLayoutParser {
    private let header: HWPXLayoutNode
    private let assetPaths: [String: String]
    private let readAsset: (String) throws -> Data
    private var assets: [String: Data] = [:]
    private var fonts: [String: [String: HWPXLayoutNode]] = [:]
    private var characters: [String: HWPXLayoutNode] = [:]
    private var paragraphs: [String: HWPXLayoutNode] = [:]
    private var styles: [String: HWPXLayoutNode] = [:]
    private var borders: [String: HWPDocumentBoxStyle] = [:]

    public init(headerData: Data?, manifestData: Data?, readAsset: @escaping (String) throws -> Data) throws {
        header = try headerData.map(HWPXLayoutXML.parse) ?? HWPXLayoutNode(name: "head")
        self.readAsset = readAsset
        let manifest = try manifestData.map(HWPXLayoutXML.parse)
        var paths: [String: String] = [:]
        for item in manifest?.descendants("item") ?? [] {
            guard let id = item["id"], let href = item["href"],
                  let path = Self.assetPath(href) else { continue }
            paths[id] = path
        }
        assetPaths = paths
        for face in header.descendants("fontface") {
            let language = (face["lang"] ?? "HANGUL").lowercased()
            for font in face.children where font.name == "font" {
                if let id = font["id"] { fonts[language, default: [:]][id] = font }
            }
        }
        for node in header.descendants("charpr") { if let id = node["id"] { characters[id] = node } }
        for node in header.descendants("parapr") { if let id = node["id"] { paragraphs[id] = node } }
        for node in header.descendants("style") { if let id = node["id"] { styles[id] = node } }
        for node in header.descendants("borderfill") {
            if let id = node["id"] { borders[id] = Self.boxStyle(node) }
        }
    }

    public func resolve(data: Data, blocks: [HWPDocumentBlock], sectionIndex: Int) throws
        -> (blocks: [HWPDocumentBlock], layout: HWPDocumentPageLayout) {
        let root = try HWPXLayoutXML.parse(data)
        let nodes = root.descendants("p")
        guard nodes.count == blocks.count else { throw HWPDocumentEditingError.invalidDocument }
        let layout = pageLayout(root, sectionIndex: sectionIndex)
        let paragraphIndices = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { (ObjectIdentifier($0.element), $0.offset) })
        let tableNodes = root.descendants("tbl")
        let tableIndices = Dictionary(uniqueKeysWithValues: tableNodes.enumerated().map { (ObjectIdentifier($0.element), $0.offset) })
        var result: [HWPDocumentBlock] = []
        for (block, node) in zip(blocks, nodes) {
            let style = styles[node["styleidref"] ?? ""]
            let para = paragraphs[node["parapridref"] ?? style?["parapridref"] ?? ""]
            let content = paragraphContent(node, fallbackStyle: style?["charpridref"])
            var runs = content.runs.map(\.run)
            if runs.isEmpty, block.text.isEmpty {
                let ref = node.child("run")?["charpridref"] ?? style?["charpridref"]
                runs = textRuns(" ", styleID: ref).map { $0.withText("") }
            }
            let margin = para?.first("margin")
            let alignment: HWPParagraphAlignment
            switch para?.first("align")?["horizontal"] {
            case "CENTER": alignment = .centered
            case "RIGHT": alignment = .trailing
            case "JUSTIFY": alignment = .justified
            case "DISTRIBUTE", "DISTRIBUTE_SPACE": alignment = .distributed
            default: alignment = .leading
            }
            let heading = para?.first("heading")
            let presentation = HWPDocumentBlockPresentation(
                styleName: style?["name"], alignment: alignment,
                outlineLevel: heading?["type"] == "OUTLINE" ? heading?.integer("level") : nil,
                leftMarginPoints: margin?.child("left")?.points("value") ?? 0,
                rightMarginPoints: margin?.child("right")?.points("value") ?? 0,
                firstLineIndentPoints: (margin?.child("intent") ?? margin?.child("indent"))?.points("value") ?? 0,
                spacingBeforePoints: margin?.child("prev")?.points("value") ?? 0,
                spacingAfterPoints: margin?.child("next")?.points("value") ?? 0,
                pageBreakBefore: node.bool("pagebreak") || para?.first("breaksetting")?.bool("pagebreakbefore") == true,
                textRuns: runs.map(\.text).joined() == block.text ? runs : [HWPDocumentTextRun(text: block.text)],
                lineSpacingPercent: para?.first("linespacing")?["type"] == "PERCENT"
                    ? para?.first("linespacing")?.number("value") : nil,
                list: listStyle(heading)

            )
            let lines = cachedLines(node, block: block, content: content,
                verticalAlignment: para?.first("align")?["vertical"], leftMargin: presentation.leftMarginPoints)
            let objects = try node.ownedDescendants().filter { object in
                guard Self.objectNames.contains(object.name) else { return false }
                var ancestor = object.parent
                while let current = ancestor {
                    if current === node { return true }
                    if Self.objectNames.contains(current.name) { return false }
                    ancestor = current.parent
                }
                return false
            }
                .enumerated().map { index, object in
                    try canvasObject(object, id: "\(block.id)-object-\(index)")
                }
            let regionNode = node.ancestor(in: ["header", "footer", "footnote", "endnote"])
            let region = HWPDocumentRegion(
                kind: regionNode.flatMap { HWPDocumentRegionKind(rawValue: $0.name) } ?? .body,
                ordinal: regionNode?.integer("number"),
                scope: regionNode.map {
                    switch $0["applypagetype"] {
                    case "EVEN": return .evenPages
                    case "ODD": return .oddPages
                    default: return .bothPages
                    }
                }
            )
            result.append(HWPDocumentBlock(
                id: block.id, sectionPath: block.sectionPath, paragraphIndex: block.paragraphIndex,
                text: block.text, tableLocation: block.tableLocation, isEditable: block.isEditable,
                presentation: presentation, region: region,
                images: objects.compactMap { if case .image(let image) = $0.content { return image }; return nil },
                lineLayouts: lines, canvasObjects: objects,
                layoutContainerID: node.ancestor(in: Self.textContainerNames).map { "hwpx-container-\($0.serial)" },
                keepsParagraphBoundary: block.keepsParagraphBoundary
            ))
        }
        // The owning paragraph's line cache occurs after the entire table XML.
        // Resolve anchors after all paragraphs, including nested cells, are known.
        for index in result.indices {
            let node = nodes[index]
            guard let old = result[index].tableLocation,
                  let cell = node.ancestor(in: ["tc"]),
                  let table = cell.ancestor(in: ["tbl"]) else { continue }
            let owner = table.ancestor(in: ["p"])
                .flatMap { paragraphIndices[ObjectIdentifier($0)] }.map { result[$0] }
            let line = owner?.lineLayouts.first
            let outerCell = table.ancestor(in: ["tc"])
            let parent = outerCell.flatMap { parentCell -> HWPDocumentTableParentLocation? in
                guard let parentTable = parentCell.ancestor(in: ["tbl"]),
                      let parentIndex = tableIndices[ObjectIdentifier(parentTable)] else { return nil }
                let address = parentCell.child("celladdr")
                return HWPDocumentTableParentLocation(table: parentIndex,
                    row: address?.integer("rowaddr") ?? 0, column: address?.integer("coladdr") ?? 0)
            }
            let margin = cell.bool("hasmargin") ? cell.child("cellmargin") : table.child("inmargin") ?? cell.child("cellmargin")
            let location = HWPDocumentTableLocation(
                table: old.table, row: old.row, column: old.column, paragraph: old.paragraph,
                rowSpan: old.rowSpan, columnSpan: old.columnSpan,
                boxStyle: borders[cell["borderfillidref"] ?? table["borderfillidref"] ?? ""],
                cellWidthPoints: old.cellWidthPoints, cellHeightPoints: old.cellHeightPoints,
                cellMarginLeftPoints: margin?.points("left") ?? old.cellMarginLeftPoints,
                cellMarginRightPoints: margin?.points("right") ?? old.cellMarginRightPoints,
                cellMarginTopPoints: margin?.points("top") ?? old.cellMarginTopPoints,
                cellMarginBottomPoints: margin?.points("bottom") ?? old.cellMarginBottomPoints,
                cellVerticalAlignment: Self.relativeAlignment(cell.child("sublist")?["vertalign"]),
                tablePageBoundaryMode: table["pagebreak"] == "CELL" ? 2 : table["pagebreak"] == "TABLE" ? 1 : 0,
                repeatsHeaderRow: table.bool("repeatheader"),
                tablePlacement: Self.placement(table, owner: owner?.presentation, anchor: line),
                tableAnchor: line.map { HWPDocumentTableAnchor(columnStartPoints: $0.columnStartPoints,
                    verticalPositionPoints: $0.verticalPositionPoints, widthPoints: $0.widthPoints,
                    lineHeightPoints: $0.lineHeightPoints,
                    paragraphAlignment: owner?.presentation.alignment ?? .leading) }, parent: parent
            )
            result[index] = result[index].withLayout(tableLocation: location)
        }
        return (HWPListFormatting.renumbering(result), layout)
    }

    private func listStyle(_ heading: HWPXLayoutNode?) -> HWPParagraphList? {
        guard let heading, let id = heading["idref"],
              ["BULLET", "NUMBER"].contains(heading["type"] ?? "") else { return nil }
        let level = heading.integer("level") ?? 0
        if heading["type"] == "BULLET" {
            let definition = header.descendants("bullet").first { $0["id"] == id }
            let format = definition?["char"] ?? ""
            return HWPParagraphList(kind: .bullet, definitionID: id, level: level, format: format,
                isSimple: level == 0 && format.utf16.count == 1 && definition?.first("img") == nil)
        }
        let definition = header.descendants("numbering").first { $0["id"] == id }
        let head = definition?.children.first { $0.name == "parahead" && $0.integer("level") == level + 1 }
        return HWPParagraphList(kind: .number, definitionID: id, level: level,
            format: head?.allText ?? "", start: max(1, head?.integer("start") ?? definition?.integer("start") ?? 1),
            isSimple: level == 0 && head?["numformat"] == "DIGIT" && head?.allText == "^1.")
    }

    private func pageLayout(_ root: HWPXLayoutNode, sectionIndex: Int) -> HWPDocumentPageLayout {
        let standard = HWPDocumentPageLayout.standard(sectionIndex: sectionIndex)
        let page = root.first("pagepr")
        let margin = page?.child("margin")
        var width = min(max(page?.points("width") ?? standard.widthPoints, 72), 4_000)
        var height = min(max(page?.points("height") ?? standard.heightPoints, 72), 4_000)
        // HWPX's NARROWLY rotates the stored paper dimensions by 90 degrees.
        if page?["landscape"] == "NARROWLY", height > width { swap(&width, &height) }
        func inset(_ key: String, fallback: Double) -> Double {
            min(max(margin?.points(key) ?? fallback, 0), min(width, height) * 0.45)
        }
        let left = inset("left", fallback: standard.leftMarginPoints)
        let right = inset("right", fallback: standard.rightMarginPoints)
        let col = root.first("colpr")
        let count = min(max(col?.integer("colcount") ?? 1, 1), 32)
        let gap = col?.points("samegap") ?? 0
        let available = max(1, width - left - right - gap * Double(count - 1))
        var x = 0.0
        let declaredColumns = col?.descendants("colsz") ?? []
        let columns = (0..<count).map { index -> HWPDocumentColumn in
            let size = declaredColumns.indices.contains(index) ? declaredColumns[index].points("width") : nil
            let columnWidth = max(1, size ?? available / Double(count))
            defer { x += columnWidth + gap }
            return HWPDocumentColumn(xPoints: x, widthPoints: columnWidth)
        }
        var result = HWPDocumentPageLayout(sectionIndex: sectionIndex,
            widthPoints: width, heightPoints: height,
            leftMarginPoints: left, rightMarginPoints: right,
            topMarginPoints: inset("top", fallback: standard.topMarginPoints),
            bottomMarginPoints: inset("bottom", fallback: standard.bottomMarginPoints),
            headerMarginPoints: inset("header", fallback: standard.headerMarginPoints),
            footerMarginPoints: inset("footer", fallback: standard.footerMarginPoints),
            gutterPoints: inset("gutter", fallback: 0), isLandscape: width > height,
            hidesHeader: false, hidesFooter: false, hidesBackground: false,
            hidesPageBorder: false, hidesPageBackground: false,
            pageBorderFirstPageOnly: false, pageBackgroundFirstPageOnly: false,
            pageStyle: borders[root.first("pageborderfill")?["borderfillidref"] ?? ""],
            footnoteStyle: nil, endnoteStyle: nil,
            columnLayout: count > 1 ? HWPDocumentColumnLayout(columns: columns, gapPoints: gap,
                separator: col?.child("colline").map(Self.borderLine)) : .single)
        let start = root.first("startnum")?.integer("page") ?? 0
        result.pageNumberStart = start > 0 ? start : nil
        if let pageNumber = root.first("pagenum"), pageNumber["formattype"] == "DIGIT",
           let position = pageNumber["pos"], position != "NONE" {
            result.pageNumberStyle = HWPDocumentPageNumberStyle(position: position,
                sideCharacter: pageNumber["sidechar"] ?? "", startsAt: start > 0 ? start : nil)
        }
        return result
    }

    private struct StyledFragment {
        let rawStart: Int
        let rawEnd: Int
        let run: HWPDocumentTextRun
    }
    private struct ParagraphContent {
        var runs: [StyledFragment] = []
        var rawLength = 0
    }

    private func paragraphContent(_ paragraph: HWPXLayoutNode, fallbackStyle: String?) -> ParagraphContent {
        var result = ParagraphContent()
        var activeHyperlink: String?
        func append(_ text: String, styleID: String?, rawLength: Int? = nil) {
            let runs = textRuns(text, styleID: styleID)
            for source in runs {
                var run = source
                run.hyperlink = activeHyperlink
                let length = rawLength ?? run.text.utf16.count
                result.runs.append(StyledFragment(rawStart: result.rawLength,
                    rawEnd: result.rawLength + length, run: run))
                result.rawLength += length
            }
        }
        func visit(_ node: HWPXLayoutNode, styleID: String?, insideText: Bool = false) {
            switch node.name {
            case "__text": if insideText { append(node.text, styleID: styleID) }
            case "t": for child in node.children { visit(child, styleID: styleID, insideText: true) }
            case "tab": append("\t", styleID: styleID, rawLength: 8)
            case "linebreak": append("\n", styleID: styleID)
            case "hyphen", "hypen": append("-", styleID: styleID)
            case "nbspace": append("\u{00A0}", styleID: styleID)
            case "fwspace": append("\u{3000}", styleID: styleID)
            case "run": for child in node.children { visit(child, styleID: node["charpridref"] ?? styleID) }
            case "ctrl":
                for child in node.children where child.name != "__text" {
                    if child.name == "fieldbegin" || child.name == "fieldend" { visit(child, styleID: styleID) }
                    else { result.rawLength += 8 }
                }
            case "fieldbegin":
                activeHyperlink = Self.hyperlinkTarget(node)
                result.rawLength += 8
            case "fieldend":
                activeHyperlink = nil
                result.rawLength += 8
            case "secpr", "tbl", "pic", "rect", "ellipse", "line", "polygon", "connectline", "equation", "container", "ole":
                result.rawLength += 8
            default: break
            }
        }
        for child in paragraph.children { visit(child, styleID: fallbackStyle) }
        return result
    }

    private static func hyperlinkTarget(_ field: HWPXLayoutNode) -> String? {
        guard field["type"]?.uppercased() == "HYPERLINK" else { return nil }
        let items = field.descendants("parameteritem") + field.descendants("param")
            + field.descendants("stringparam")
        for name in ["path", "command"] {
            if let item = items.first(where: { $0["name"]?.lowercased() == name }),
               let value = item["value"] ?? (item.allText.isEmpty ? nil : item.allText),
               !value.isEmpty {
                if name == "command" {
                    var result = "", escaped = false
                    for character in value {
                        if escaped { result.append(character); escaped = false }
                        else if character == "\\" { escaped = true }
                        else if character == ";" { break }
                        else { result.append(character) }
                    }
                    return result.isEmpty ? nil : result
                }
                return value
            }
        }
        return nil
    }

    private func textRuns(_ text: String, styleID: String?) -> [HWPDocumentTextRun] {
        guard !text.isEmpty else { return [] }
        let shape = characters[styleID ?? ""]
        var pieces: [(String, String)] = []
        for character in text {
            let value = character.unicodeScalars.first?.value ?? 0
            let language: String
            switch value {
            case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF: language = "hangul"
            case 0x3040...0x30FF: language = "japanese"
            case 0x3400...0x9FFF, 0xF900...0xFAFF: language = "hanja"
            case 0...0x024F: language = "latin"
            default: language = "symbol"
            }
            let key = character == " " ? "space" : language
            if pieces.last?.0 == key { pieces[pieces.count - 1].1.append(character) }
            else { pieces.append((key, String(character))) }
        }
        return pieces.map { key, value in
            let language = key == "space" ? "latin" : key
            let ref = shape?.child("fontref")?[language] ?? shape?.child("fontref")?["hangul"] ?? "0"
            let font = fonts[language]?[ref] ?? fonts["hangul"]?[ref]
            let relativeSize = shape?.child("relsz")?.number(language) ?? 100
            return HWPDocumentTextRun(text: value, fontName: font?["face"],
                alternateFontName: font?.child("substfont")?["face"],
                fontSizePoints: min(max((shape?.points("height") ?? 10) * relativeSize / 100, 1), 512),
                fontWidthPercent: shape?.child("ratio")?.number(language) ?? 100,
                letterSpacingPercent: shape?.child("spacing")?.number(language) ?? 0,
                baselinePositionPercent: shape?.child("offset")?.number(language) ?? 0,
                textColorRGB: Self.color(shape?["textcolor"]),
                backgroundColorRGB: Self.color(shape?["shadecolor"]),
                isBold: shape?.child("bold") != nil, isItalic: shape?.child("italic") != nil,
                isUnderlined: shape?.child("underline").map { ($0["type"] ?? "NONE") != "NONE" } ?? false,
                // Some Hancom exports retain a 3D border value in strikeout
                // while showing no decoration. Do not turn it into a solid line.
                isStruckThrough: shape?.child("strikeout").map {
                    ["SOLID", "DASH", "DOT", "DASH_DOT", "DASH_DOT_DOT", "LONG_DASH", "DOUBLE_SLIM"].contains($0["shape"] ?? "NONE")
                } ?? false,
                isSuperscript: shape?.child("supscript") != nil,
                isSubscript: shape?.child("subscript") != nil,
                spaceWidthPoints: key == "space" && shape?.bool("usefontspace") == false
                    ? min(max((shape?.points("height") ?? 10) * relativeSize / 200, 0.5), 256) : nil)
        }
    }

    private func cachedLines(_ node: HWPXLayoutNode, block: HWPDocumentBlock, content: ParagraphContent,
                             verticalAlignment: String?, leftMargin: Double) -> [HWPDocumentLineLayout] {
        let lines = node.child("linesegarray")?.children.filter { $0.name == "lineseg" } ?? []
        return lines.enumerated().map { index, line in
            let start = max(line.integer("textpos") ?? 0, 0)
            let end = index + 1 < lines.count ? max(lines[index + 1].integer("textpos") ?? content.rawLength, start) : content.rawLength
            let runs = content.runs.compactMap { fragment -> HWPDocumentTextRun? in
                let lower = max(start, fragment.rawStart)
                let upper = min(end, fragment.rawEnd)
                guard lower < upper else { return nil }
                let source = fragment.run.text as NSString
                let text: String
                if source.length == fragment.rawEnd - fragment.rawStart {
                    let range = source.rangeOfComposedCharacterSequences(for:
                        NSRange(location: lower - fragment.rawStart, length: upper - lower))
                    text = source.substring(with: range)
                } else { text = fragment.run.text }
                return fragment.run.withText(text.replacingOccurrences(of: "\n", with: ""))
            }
            var flags = UInt32(clamping: line.integer("flags") ?? 0)
            if index == 0 && node.bool("columnbreak") { flags |= 2 }
            return HWPDocumentLineLayout(id: "\(block.id)-line-\(index)", startCharacter: start,
                verticalPositionPoints: line.points("vertpos") ?? 0,
                lineHeightPoints: line.points("vertsize") ?? 12,
                textHeightPoints: line.points("textheight") ?? 10,
                baselinePoints: (line.points("baseline") ?? 8.5)
                    + (verticalAlignment == "CENTER" ? (line.points("textheight") ?? 10) * 0.35 : 0),
                lineSpacingPoints: line.points("spacing") ?? 0,
                columnStartPoints: (line.points("horzpos") ?? 0) - leftMargin,
                widthPoints: line.points("horzsize") ?? 0, flags: flags,
                text: runs.map(\.text).joined(), textRuns: runs)
        }
    }

    private static let textContainerNames: Set<String> = ["rect", "ellipse", "polygon", "container"]
    private static let objectNames: Set<String> = ["pic", "equation", "rect", "ellipse", "line", "polygon", "connectline", "container", "ole", "chart"]
    private static let shapeNames: Set<String> = ["rect", "ellipse", "line", "polygon", "connectline"]

    private func canvasObject(_ node: HWPXLayoutNode, id: String) throws -> HWPDocumentCanvasObject {
        let placement = Self.placement(node)
        let content: HWPDocumentCanvasContent
        if node.name == "pic", let reference = node.first("img")?["binaryitemidref"],
           let path = assetPaths[reference], let data = try? assetData(at: path) {
            let imageNode = node.first("img")
            let clip = node.child("imgclip")
            let dim = node.child("imgdim")
            let line = node.child("lineshape")
            let crop: CGRect?
            if let width = dim?.number("dimwidth"), let height = dim?.number("dimheight"), width > 0, height > 0,
               let clip, let right = clip.number("right"), let bottom = clip.number("bottom") {
                let left = clip.number("left") ?? 0, top = clip.number("top") ?? 0
                crop = CGRect(x: left / width, y: top / height, width: (right - left) / width, height: (bottom - top) / height)
            } else { crop = nil }
            content = .image(HWPDocumentImage(id: id, binaryID: Int(reference.filter(\.isNumber)) ?? 0,
                data: data, widthPoints: placement.widthPoints, heightPoints: placement.heightPoints,
                description: node.child("shapecomment")?.allText, cropRect: crop,
                borderStroke: line.map { value in
                    let style = Self.strokeStyle(value["style"])
                    return style == 0 ? nil : HWPDocumentStroke(
                        colorRGB: Self.color(value["color"]) ?? 0,
                        widthPoints: value.points("width") ?? 0.75,
                        style: style, startArrow: 0, endArrow: 0)
                } ?? nil,
                brightness: min(max(imageNode?.integer("bright") ?? 0, -100), 100),
                contrast: min(max(imageNode?.integer("contrast") ?? 0, -100), 100),
                effect: HWPDocumentImageEffect(hwpXName: imageNode?["effect"]),
                transparencyPercent: Int((Double(min(max(imageNode?.integer("alpha") ?? 0, 0), 255))
                    * 100 / 255).rounded()),
                supportsTransparency: true))
        } else if node.name == "equation" {
            content = .equation(HWPDocumentEquation(script: node.child("script")?.allText ?? "",
                fontSizePoints: node.points("baseunit") ?? 10, colorRGB: Self.color(node["textcolor"]) ?? 0,
                baselinePercent: node.number("baseline") ?? 85, fontName: node["font"]))
        } else if node.name == "container" {
            let children = node.ownedDescendants().filter {
                Self.shapeNames.contains($0.name)
                    && $0.ancestor(in: Self.objectNames) === node
            }
            let shapes = try children.enumerated().compactMap { index, child -> HWPDocumentShape? in
                let parsed = try canvasObject(child, id: "\(id)-child-\(index)")
                guard case .shape(let shape) = parsed.content else { return nil }
                let childPlacement = Self.placement(child)
                return HWPDocumentShape(geometry: shape.geometry, stroke: shape.stroke,
                    fill: shape.fill,
                    localFrame: CGRect(x: childPlacement.xPoints, y: childPlacement.yPoints,
                        width: childPlacement.widthPoints, height: childPlacement.heightPoints),
                    rotationDegrees: childPlacement.rotationDegrees,
                    flipHorizontal: childPlacement.flipHorizontal,
                    flipVertical: childPlacement.flipVertical, shadow: shape.shadow)
            }
            content = shapes.isEmpty ? .unsupported("빈 그룹 도형") : .group(shapes)
        } else if Self.shapeNames.contains(node.name) {
            let geometry: HWPDocumentShapeGeometry
            let points = node.children.filter { $0.name.hasPrefix("pt") }.map {
                HWPDocumentPoint(x: $0.points("x") ?? 0, y: $0.points("y") ?? 0)
            }
            switch node.name {
            case "rect": geometry = .rectangle(cornerRadiusPercent: node.number("ratio") ?? 0, points: points)
            case "line": geometry = .line(start: HWPDocumentPoint(x: 0, y: 0), end: HWPDocumentPoint(x: placement.widthPoints, y: placement.heightPoints))
            case "polygon": geometry = .polygon(points: points)
            case "connectline":
                let start = node.child("startpt").map {
                    HWPDocumentPoint(x: $0.points("x") ?? 0, y: $0.points("y") ?? 0)
                } ?? HWPDocumentPoint(x: 0, y: 0)
                let controls = node.child("controlpoints")?.children.filter { $0.name == "point" }.map {
                    HWPDocumentPoint(x: $0.points("x") ?? 0, y: $0.points("y") ?? 0)
                } ?? []
                let end = node.child("endpt").map {
                    HWPDocumentPoint(x: $0.points("x") ?? placement.widthPoints,
                        y: $0.points("y") ?? placement.heightPoints)
                } ?? HWPDocumentPoint(x: placement.widthPoints, y: placement.heightPoints)
                let path = [start] + controls + [end]
                geometry = .curve(points: path, curvedSegments: Array(repeating: false,
                    count: max(path.count - 1, 0)))
            default: geometry = .ellipse(center: HWPDocumentPoint(x: placement.widthPoints / 2, y: placement.heightPoints / 2),
                axis1: HWPDocumentPoint(x: placement.widthPoints, y: placement.heightPoints / 2),
                axis2: HWPDocumentPoint(x: placement.widthPoints / 2, y: placement.heightPoints))
            }
            let line = node.child("lineshape")
            let shadow = node.child("shadow")
            content = .shape(HWPDocumentShape(geometry: geometry,
                stroke: HWPDocumentStroke(colorRGB: Self.color(line?["color"]) ?? 0,
                    widthPoints: line?.points("width") ?? 0.5, style: Self.strokeStyle(line?["style"]),
                    startArrow: Self.arrowStyle(line?["headstyle"]),
                    endArrow: Self.arrowStyle(line?["tailstyle"])),
                fill: HWPDocumentFill(colorRGB: Self.color(node.first("winbrush")?["facecolor"])),
                flipHorizontal: placement.flipHorizontal,
                flipVertical: placement.flipVertical,
                shadow: shadow.flatMap { node in
                    guard node["type"] != "NONE" else { return nil }
                    let alpha = min(max(node.number("alpha") ?? 0, 0), 255)
                    return HWPDocumentShapeShadow(kind: 4, colorRGB: Self.color(node["color"]) ?? 0,
                        offsetX: node.points("offsetx") ?? 3, offsetY: node.points("offsety") ?? 3,
                        opacity: 1 - alpha / 255)
                }))
        } else { content = .unsupported(node.name == "pic" ? "그림을 읽을 수 없습니다." : "지원하지 않는 개체") }
        return HWPDocumentCanvasObject(id: id, placement: placement, content: content,
            description: node.child("shapecomment")?.allText,
            textContainerID: Self.textContainerNames.contains(node.name) ? "hwpx-container-\(node.serial)" : nil,
            groupCoordinateFrame: node.name == "container" ? Self.groupCoordinateFrame(node) : nil)
    }

    private static func groupCoordinateFrame(_ node: HWPXLayoutNode) -> CGRect? {
        guard let encoded = node["groupbounds"] else { return nil }
        let values = encoded.split(separator: ",").compactMap { Double($0) }
        guard values.count == 4, values.allSatisfy(\.isFinite),
              values[2] > 0, values[3] > 0 else { return nil }
        return CGRect(x: values[0] / 100, y: values[1] / 100,
            width: values[2] / 100, height: values[3] / 100)
    }

    private func assetData(at path: String) throws -> Data {
        if let cached = assets[path] { return cached }
        let data = try readAsset(path)
        assets[path] = data
        return data
    }

    private static func placement(_ node: HWPXLayoutNode, owner: HWPDocumentBlockPresentation? = nil,
                                  anchor: HWPDocumentLineLayout? = nil) -> HWPDocumentObjectPlacement {
        let size = node.child("sz") ?? node.child("cursz")
        let pos = node.child("pos")
        let margin = node.child("outmargin")
        let flip = node.child("flip")
        let wrap: HWPDocumentObjectWrap
        switch node["textwrap"] {
        case "TOP_AND_BOTTOM": wrap = .topAndBottom
        case "BEHIND_TEXT": wrap = .behindText
        case "IN_FRONT_OF_TEXT": wrap = .inFrontOfText
        case "TIGHT": wrap = .tight
        case "THROUGH": wrap = .through
        default: wrap = .square
        }
        let inline = pos?.bool("treataschar") ?? true
        var x = pos?.points("horzoffset") ?? 0
        var y = pos?.points("vertoffset") ?? 0
        if inline {
            let left = margin?.points("left") ?? 0, right = margin?.points("right") ?? 0
            let available = (anchor?.widthPoints ?? 0) - (size?.points("width") ?? 0) - left - right
            if let owner, available > 0 {
                if owner.alignment == .centered { x += available / 2 }
                else if owner.alignment == .trailing { x += available }
            }
            x += left
            y += margin?.points("top") ?? 0
        }
        return HWPDocumentObjectPlacement(xPoints: x, yPoints: y,
            widthPoints: size?.points("width") ?? 120, heightPoints: size?.points("height") ?? 36,
            zOrder: node.integer("zorder") ?? 0, rotationDegrees: node.child("rotationinfo")?.number("angle") ?? 0,
            flipHorizontal: flip?.bool("horizontal") ?? false,
            flipVertical: flip?.bool("vertical") ?? false,
            isInline: inline,
            horizontalReference: layoutReference(pos?["horzrelto"]), verticalReference: layoutReference(pos?["vertrelto"]),
            horizontalAlignment: relativeAlignment(pos?["horzalign"]), verticalAlignment: relativeAlignment(pos?["vertalign"]),
            wrap: wrap, marginLeftPoints: margin?.points("left") ?? 0,
            marginRightPoints: margin?.points("right") ?? 0, marginTopPoints: margin?.points("top") ?? 0,
            marginBottomPoints: margin?.points("bottom") ?? 0,
            inlineOriginIsResolved: inline)
    }

    private static func layoutReference(_ value: String?) -> HWPDocumentLayoutReference {
        switch value { case "PAPER": .paper; case "PAGE": .page; case "COLUMN": .column; default: .paragraph }
    }
    private static func relativeAlignment(_ value: String?) -> HWPDocumentRelativeAlignment {
        switch value { case "CENTER": .center; case "RIGHT", "BOTTOM": .end; case "INSIDE": .inside; case "OUTSIDE": .outside; default: .start }
    }
    private static func color(_ value: String?) -> UInt32? {
        guard let value, value.lowercased() != "none" else { return nil }
        return UInt32(value.replacingOccurrences(of: "#", with: ""), radix: 16).map { $0 & 0xFFFFFF }
    }
    private static func strokeStyle(_ value: String?) -> Int {
        switch value?.uppercased() {
        case "NONE": 0
        case "DASH": 2
        case "DOT": 3
        case "DASH_DOT": 4
        case "DASH_DOT_DOT": 5
        case "LONG_DASH": 6
        default: 1
        }
    }
    private static func arrowStyle(_ value: String?) -> Int {
        switch value?.uppercased() {
        case "ARROW": 1
        case "SPEAR": 2
        case "CONCAVE_ARROW": 3
        case "EMPTY_DIAMOND": 4
        case "EMPTY_CIRCLE": 5
        case "EMPTY_BOX": 6
        default: 0
        }
    }
    private static func borderLine(_ node: HWPXLayoutNode) -> HWPDocumentBorderLine {
        let kind: UInt8 = switch node["type"] { case "NONE": 0; case "DASH": 2; case "DOT": 3; case "DASH_DOT": 4; case "DOUBLE_SLIM": 6; default: 1 }
        let widthString = node["width"] ?? "0.1 mm"
        let value = Double(widthString.split(separator: " ").first ?? "") ?? 0.1
        let width = widthString.contains("mm") ? value * 72 / 25.4 : value
        return HWPDocumentBorderLine(kind: kind, widthPoints: width, colorRGB: color(node["color"]) ?? 0)
    }
    private static func boxStyle(_ node: HWPXLayoutNode) -> HWPDocumentBoxStyle {
        HWPDocumentBoxStyle(left: node.child("leftborder").map(borderLine) ?? .init(),
            right: node.child("rightborder").map(borderLine) ?? .init(),
            top: node.child("topborder").map(borderLine) ?? .init(),
            bottom: node.child("bottomborder").map(borderLine) ?? .init(),
            backgroundColorRGB: color(node.first("winbrush")?["facecolor"]))
    }
    private static func assetPath(_ value: String) -> String? {
        let decoded = (value.removingPercentEncoding ?? value).replacingOccurrences(of: "\\", with: "/")
        guard !decoded.contains(":"), !decoded.hasPrefix("/") else { return nil }
        var parts: [Substring] = []
        let path = decoded.hasPrefix("../") ? "Contents/" + decoded : decoded
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { guard !parts.isEmpty else { return nil }; parts.removeLast() }
            else { parts.append(part) }
        }
        guard parts.first == "BinData", parts.count > 1 else { return nil }
        return parts.joined(separator: "/")
    }
}

/// A bounded tree keeps mixed text/control order and lets cell metadata appear
/// after its paragraphs without leaking descendant styles into the owner.
private nonisolated final class HWPXLayoutNode {
    let name: String
    let serial: Int
    var attributes: [String: String]
    weak var parent: HWPXLayoutNode?
    var children: [HWPXLayoutNode] = []
    var text = ""
    init(name: String, serial: Int = 0, attributes: [String: String] = [:]) {
        self.name = name; self.serial = serial; self.attributes = attributes
    }
    subscript(_ name: String) -> String? { attributes[name.lowercased()] }
    func number(_ key: String) -> Double? { self[key].flatMap(Double.init).flatMap { $0.isFinite ? min(max($0, -10_000_000), 10_000_000) : nil } }
    func integer(_ key: String) -> Int? { number(key).map(Int.init) }
    func points(_ key: String) -> Double? { number(key).map { $0 / 100 } }
    func bool(_ key: String) -> Bool { self[key] == "1" || self[key]?.lowercased() == "true" }
    func child(_ name: String) -> HWPXLayoutNode? { children.first { $0.name == name } }
    func descendants(_ name: String) -> [HWPXLayoutNode] {
        children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) }
    }
    func first(_ name: String) -> HWPXLayoutNode? {
        for child in children { if child.name == name { return child }; if let found = child.first(name) { return found } }
        return nil
    }
    func ancestor(in names: Set<String>) -> HWPXLayoutNode? {
        guard let parent else { return nil }
        return names.contains(parent.name) ? parent : parent.ancestor(in: names)
    }
    func ownedDescendants() -> [HWPXLayoutNode] {
        children.filter { $0.name != "p" }.flatMap { [$0] + $0.ownedDescendants() }
    }
    var allText: String { text + children.map(\.allText).joined() }
}

private nonisolated final class HWPXLayoutXML: NSObject, XMLParserDelegate {
    private var root = HWPXLayoutNode(name: "root")
    private var stack: [HWPXLayoutNode] = []
    private var count = 0
    private var exceeded = false
    static func parse(_ data: Data) throws -> HWPXLayoutNode {
        guard let xml = String(data: data, encoding: .utf8),
              !xml.localizedCaseInsensitiveContains("<!DOCTYPE"), !xml.localizedCaseInsensitiveContains("<!ENTITY") else {
            throw HWPDocumentEditingError.invalidDocument
        }
        let reader = HWPXLayoutXML()
        reader.stack = [reader.root]
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), !reader.exceeded else {
            throw reader.exceeded ? HWPDocumentEditingError.limitExceeded : .invalidDocument
        }
        return reader.root
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        count += 1
        guard count <= 300_000, stack.count < 128 else { exceeded = true; parser.abortParsing(); return }
        func local(_ name: String) -> String { String(name.split(separator: ":").last ?? "").lowercased() }
        var mapped: [String: String] = [:]
        for (key, value) in attributes { mapped[local(key)] = value }
        let node = HWPXLayoutNode(name: local(elementName), serial: count, attributes: mapped)
        node.parent = stack.last
        stack.last?.children.append(node)
        stack.append(node)
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { if stack.count > 1 { stack.removeLast() } }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard let parent = stack.last else { return }
        if parent.children.last?.name == "__text" { parent.children[parent.children.count - 1].text += string }
        else { let node = HWPXLayoutNode(name: "__text"); node.text = string; parent.children.append(node) }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { self.parser(parser, foundCharacters: String(decoding: CDATABlock, as: UTF8.self)) }
}

extension HWPDocumentTextRun {
    public nonisolated func withText(_ value: String) -> HWPDocumentTextRun {
        HWPDocumentTextRun(text: value, fontName: fontName, alternateFontName: alternateFontName, baseFontName: baseFontName,
            fontSignature: fontSignature, fontSizePoints: fontSizePoints, fontWidthPercent: fontWidthPercent,
            letterSpacingPercent: letterSpacingPercent, baselinePositionPercent: baselinePositionPercent,
            textColorRGB: textColorRGB, backgroundColorRGB: backgroundColorRGB,
            isBold: isBold, isItalic: isItalic, isUnderlined: isUnderlined,
            isStruckThrough: isStruckThrough, isSuperscript: isSuperscript, isSubscript: isSubscript,
            hyperlink: hyperlink, spaceWidthPoints: spaceWidthPoints, tabWidthPoints: tabWidthPoints)
    }
}
extension HWPDocumentBlock {
    public nonisolated func withLayout(tableLocation: HWPDocumentTableLocation? = nil, lines: [HWPDocumentLineLayout]? = nil) -> HWPDocumentBlock {
        HWPDocumentBlock(id: id, sectionPath: sectionPath, paragraphIndex: paragraphIndex, text: text,
            tableLocation: tableLocation ?? self.tableLocation, isEditable: isEditable, presentation: presentation,
            region: region, images: images, lineLayouts: lines ?? lineLayouts, canvasObjects: canvasObjects, layoutContainerID: layoutContainerID, sourceParagraphID: sourceParagraphID, keepsParagraphBoundary: keepsParagraphBoundary)
    }
}
