import Foundation

public nonisolated struct ExcelDrawingAnchor: Hashable, Sendable {
    public var start: ExcelCellAddress
    public var end: ExcelCellAddress
    public var fromOffset: ExcelDrawingOffset = .zero
    public var toOffset: ExcelDrawingOffset = .zero
    public var absolutePosition: ExcelDrawingOffset? = nil
    public var extent: ExcelDrawingOffset? = nil

    public init(start: ExcelCellAddress, end: ExcelCellAddress, fromOffset: ExcelDrawingOffset = .zero, toOffset: ExcelDrawingOffset = .zero, absolutePosition: ExcelDrawingOffset? = nil, extent: ExcelDrawingOffset? = nil) {
        self.start = start
        self.end = end
        self.fromOffset = fromOffset
        self.toOffset = toOffset
        self.absolutePosition = absolutePosition
        self.extent = extent
    }
}

public nonisolated struct ExcelSheetImage: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var alternativeText: String?
    public var anchor: ExcelDrawingAnchor
    public var relationshipID: String
    public var mediaPartPath: String
    public var contentType: String
    public var data: Data
    public var originalAnchorXML: String?
    public var displayOrder: Int = 0

    public init(id: String, name: String, alternativeText: String? = nil, anchor: ExcelDrawingAnchor, relationshipID: String, mediaPartPath: String, contentType: String, data: Data, originalAnchorXML: String? = nil, displayOrder: Int = 0) {
        self.id = id
        self.name = name
        self.alternativeText = alternativeText
        self.anchor = anchor
        self.relationshipID = relationshipID
        self.mediaPartPath = mediaPartPath
        self.contentType = contentType
        self.data = data
        self.originalAnchorXML = originalAnchorXML
        self.displayOrder = displayOrder
    }
}

public nonisolated enum ExcelShapeKind: String, CaseIterable, Identifiable, Sendable {
    case rectangle
    case roundedRectangle
    case ellipse
    case line
    case textBox
    case unsupported

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rectangle: return DocumentEngineLocalization.string("사각형")
        case .roundedRectangle: return DocumentEngineLocalization.string("둥근 사각형")
        case .ellipse: return DocumentEngineLocalization.string("타원")
        case .line: return DocumentEngineLocalization.string("선")
        case .textBox: return DocumentEngineLocalization.string("텍스트 상자")
        case .unsupported: return DocumentEngineLocalization.string("고급 도형")
        }
    }

    public var isEditable: Bool { self != .unsupported }
}

public nonisolated struct ExcelSheetShape: Identifiable, Hashable, Sendable {
    public let id: String
    public var nonVisualID: Int
    public var name: String
    public var text: String
    public var kind: ExcelShapeKind
    public var fillARGB: String?
    public var lineARGB: String?
    public var anchor: ExcelDrawingAnchor
    public var originalAnchorXML: String?

    public init(id: String, nonVisualID: Int, name: String, text: String, kind: ExcelShapeKind, fillARGB: String? = nil, lineARGB: String? = nil, anchor: ExcelDrawingAnchor, originalAnchorXML: String? = nil) {
        self.id = id
        self.nonVisualID = nonVisualID
        self.name = name
        self.text = text
        self.kind = kind
        self.fillARGB = fillARGB
        self.lineARGB = lineARGB
        self.anchor = anchor
        self.originalAnchorXML = originalAnchorXML
    }
}

public nonisolated enum ExcelChartKind: String, CaseIterable, Identifiable, Sendable {
    case column
    case bar
    case line
    case pie
    case area
    case scatter
    case doughnut
    case radar
    case unsupported

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .column: return DocumentEngineLocalization.string("세로 막대")
        case .bar: return DocumentEngineLocalization.string("가로 막대")
        case .line: return DocumentEngineLocalization.string("꺾은선")
        case .pie: return DocumentEngineLocalization.string("원형")
        case .area: return DocumentEngineLocalization.string("영역")
        case .scatter: return DocumentEngineLocalization.string("분산형")
        case .doughnut: return DocumentEngineLocalization.string("도넛")
        case .radar: return DocumentEngineLocalization.string("방사형")
        case .unsupported: return DocumentEngineLocalization.string("고급 차트")
        }
    }

    public var isEditable: Bool { self != .unsupported }
}

public nonisolated struct ExcelSheetChart: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var title: String
    public var kind: ExcelChartKind
    public var sourceRange: ExcelCellRange?
    public var sheetName: String
    public var anchor: ExcelDrawingAnchor
    public var relationshipID: String
    public var chartPartPath: String
    public var originalAnchorXML: String?
    public var originalChartXML: String?
    public var displayOrder: Int = 0

    public init(id: String, name: String, title: String, kind: ExcelChartKind, sourceRange: ExcelCellRange? = nil, sheetName: String, anchor: ExcelDrawingAnchor, relationshipID: String, chartPartPath: String, originalAnchorXML: String? = nil, originalChartXML: String? = nil, displayOrder: Int = 0) {
        self.id = id
        self.name = name
        self.title = title
        self.kind = kind
        self.sourceRange = sourceRange
        self.sheetName = sheetName
        self.anchor = anchor
        self.relationshipID = relationshipID
        self.chartPartPath = chartPartPath
        self.originalAnchorXML = originalAnchorXML
        self.originalChartXML = originalChartXML
        self.displayOrder = displayOrder
    }
}

public nonisolated struct ExcelWorksheetDrawingObjects: Hashable, Sendable {
    public var images: [ExcelSheetImage]
    public var charts: [ExcelSheetChart] = []
    public var shapes: [ExcelSheetShape] = []
    public var drawingPartPath: String?
    public var drawingRelationshipID: String?
    public var chartCount: Int
    public var otherDrawingObjectCount: Int
    public var pivotTableCount: Int

    public static let empty = ExcelWorksheetDrawingObjects(
        images: [],
        charts: [],
        shapes: [],
        drawingPartPath: nil,
        drawingRelationshipID: nil,
        chartCount: 0,
        otherDrawingObjectCount: 0,
        pivotTableCount: 0
    )

    public init(images: [ExcelSheetImage], charts: [ExcelSheetChart] = [], shapes: [ExcelSheetShape] = [], drawingPartPath: String? = nil, drawingRelationshipID: String? = nil, chartCount: Int, otherDrawingObjectCount: Int, pivotTableCount: Int) {
        self.images = images
        self.charts = charts
        self.shapes = shapes
        self.drawingPartPath = drawingPartPath
        self.drawingRelationshipID = drawingRelationshipID
        self.chartCount = chartCount
        self.otherDrawingObjectCount = otherDrawingObjectCount
        self.pivotTableCount = pivotTableCount
    }
}

public nonisolated struct ExcelWorksheetDrawingEdits: Sendable {
    public let partPath: String
    public let original: ExcelWorksheetDrawingObjects
    public let current: ExcelWorksheetDrawingObjects

    public init(partPath: String, original: ExcelWorksheetDrawingObjects, current: ExcelWorksheetDrawingObjects) {
        self.partPath = partPath
        self.original = original
        self.current = current
    }
}

public nonisolated enum ExcelWorksheetDrawingObjectsLoader {
    public static func load(
        sheetPartPath: String,
        relationships: [String: ExcelRelationship],
        reader: ExcelArchiveReader
    ) throws -> ExcelWorksheetDrawingObjects {
        let pivotTableCount = relationships.values.filter {
            $0.type.hasSuffix("/pivotTable")
        }.count
        guard let drawingRelationship = relationships.first(where: {
            $0.value.type.hasSuffix("/drawing")
        }),
        let drawingPath = normalizedPartPath(
            drawingRelationship.value.target,
            relativeTo: sheetPartPath
        ),
        reader.contains(drawingPath),
        let drawingXML = String(
            data: try reader.data(at: drawingPath),
            encoding: .utf8
        ) else {
            var empty = ExcelWorksheetDrawingObjects.empty
            empty.pivotTableCount = pivotTableCount
            return empty
        }

        let drawingRelationshipsPath = relationshipsPath(for: drawingPath)
        let drawingRelationships = reader.contains(drawingRelationshipsPath)
            ? try ExcelRelationshipsParser.parse(
                reader.data(at: drawingRelationshipsPath)
            )
            : [:]
        let anchorXMLs = anchorElements(in: drawingXML)
        var images = [ExcelSheetImage]()
        var charts = [ExcelSheetChart]()
        var shapes = [ExcelSheetShape]()
        var otherObjectCount = 0
        for (displayOrder, anchorXML) in anchorXMLs.enumerated() {
            if let relationshipID = embeddedRelationshipID(
                in: anchorXML
            ),
               let relationship = drawingRelationships[relationshipID],
               relationship.type.hasSuffix("/image"),
               let mediaPath = normalizedPartPath(
                   relationship.target,
                   relativeTo: drawingPath
               ),
               reader.contains(mediaPath) {
                let anchor = parsedAnchor(in: anchorXML)
                let metadata = pictureMetadata(in: anchorXML)
                images.append(
                    ExcelSheetImage(
                        id: drawingPath + "#" + relationshipID,
                        name: metadata.name
                            ?? DocumentEngineLocalization.string("이미지"),
                        alternativeText: metadata.alternativeText,
                        anchor: anchor,
                        relationshipID: relationshipID,
                        mediaPartPath: mediaPath,
                        contentType: contentType(for: mediaPath),
                        data: try reader.data(at: mediaPath),
                        originalAnchorXML: anchorXML,
                        displayOrder: displayOrder
                    )
                )
                continue
            }
            if let relationshipID = chartRelationshipID(in: anchorXML),
               let relationship = drawingRelationships[relationshipID],
               relationship.type.hasSuffix("/chart"),
               let chartPath = normalizedPartPath(
                   relationship.target,
                   relativeTo: drawingPath
               ),
               reader.contains(chartPath),
               let chartXML = String(
                   data: try reader.data(at: chartPath),
                   encoding: .utf8
               ) {
                let metadata = pictureMetadata(in: anchorXML)
                charts.append(
                    ExcelSheetChart(
                        id: drawingPath + "#" + relationshipID,
                        name: metadata.name
                            ?? DocumentEngineLocalization.string("차트"),
                        title: chartTitle(in: chartXML)
                            ?? metadata.name
                            ?? DocumentEngineLocalization.string("차트"),
                        kind: chartKind(in: chartXML),
                        sourceRange: chartSourceRange(in: chartXML),
                        sheetName: sheetName(in: chartXML) ?? "",
                        anchor: parsedAnchor(in: anchorXML),
                        relationshipID: relationshipID,
                        chartPartPath: chartPath,
                        originalAnchorXML: anchorXML,
                        originalChartXML: chartXML,
                        displayOrder: displayOrder
                    )
                )
                continue
            }
            if isShapeAnchor(anchorXML) {
                let metadata = pictureMetadata(in: anchorXML)
                let nonVisualID = shapeNonVisualID(in: anchorXML)
                shapes.append(
                    ExcelSheetShape(
                        id: drawingPath + "#shape-" + String(nonVisualID),
                        nonVisualID: nonVisualID,
                        name: metadata.name
                            ?? DocumentEngineLocalization.string("도형"),
                        text: shapeText(in: anchorXML),
                        kind: shapeKind(in: anchorXML),
                        fillARGB: shapeColor(
                            in: anchorXML,
                            line: false
                        ),
                        lineARGB: shapeColor(
                            in: anchorXML,
                            line: true
                        ),
                        anchor: parsedAnchor(in: anchorXML),
                        originalAnchorXML: anchorXML
                    )
                )
                continue
            }
            otherObjectCount += 1
        }
        return ExcelWorksheetDrawingObjects(
            images: images,
            charts: charts,
            shapes: shapes,
            drawingPartPath: drawingPath,
            drawingRelationshipID: drawingRelationship.key,
            chartCount: charts.count,
            otherDrawingObjectCount: otherObjectCount,
            pivotTableCount: pivotTableCount
        )
    }

    private static func relationshipsPath(for partPath: String) -> String {
        let components = partPath.split(separator: "/")
        let filename = components.last.map(String.init) ?? partPath
        let directory = components.dropLast().joined(separator: "/")
        return directory + "/_rels/" + filename + ".rels"
    }

    private static func anchorElements(in source: String) -> [String] {
        let names = ["twoCellAnchor", "oneCellAnchor", "absoluteAnchor"]
        return names.flatMap { name -> [(Int, String)] in
            let pattern = #"<(?:[A-Za-z_][\w.-]*:)?"# + name
                + #"\b[^>]*>[\s\S]*?</(?:[A-Za-z_][\w.-]*:)?"#
                + name + #"\s*>"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return []
            }
            return regex.matches(
                in: source,
                range: NSRange(source.startIndex..., in: source)
            ).compactMap { match in
                guard let range = Range(match.range, in: source) else {
                    return nil
                }
                return (match.range.location, String(source[range]))
            }
        }.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private static func embeddedRelationshipID(
        in source: String
    ) -> String? {
        attribute("embed", in: source)
    }

    private static func chartRelationshipID(in source: String) -> String? {
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?chart\b[^>]*\b(?:r:)?id\s*=\s*([\"'])(.*?)\1"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: source,
                  range: NSRange(source.startIndex..., in: source)
              ),
              let range = Range(match.range(at: 2), in: source) else {
            return nil
        }
        return String(source[range])
    }

    private static func parsedAnchor(in source: String) -> ExcelDrawingAnchor {
        if let root = try? ExcelEditingXML.parse(Data(source.utf8)) {
            return ExcelDrawingPlacementXML.read(root)
        }
        let from = content(of: "from", in: source)
        let to = content(of: "to", in: source)
        let startColumn = Int(from.flatMap { content(of: "col", in: $0) }
            ?? "") ?? 0
        let startRow = Int(from.flatMap { content(of: "row", in: $0) }
            ?? "") ?? 0
        let endColumn = Int(to.flatMap { content(of: "col", in: $0) }
            ?? "") ?? (startColumn + 2)
        let endRow = Int(to.flatMap { content(of: "row", in: $0) }
            ?? "") ?? (startRow + 5)
        return ExcelDrawingAnchor(
            start: ExcelCellAddress(
                row: max(startRow + 1, 1),
                column: max(startColumn + 1, 1)
            ),
            end: ExcelCellAddress(
                row: max(endRow + 1, startRow + 2),
                column: max(endColumn + 1, startColumn + 2)
            )
        )
    }

    private static func pictureMetadata(
        in source: String
    ) -> (name: String?, alternativeText: String?) {
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?cNvPr\b[^>]*/?>"#
        guard let range = source.range(
            of: pattern,
            options: .regularExpression
        ) else {
            return (nil, nil)
        }
        let opening = String(source[range])
        return (
            attribute("name", in: opening),
            attribute("descr", in: opening)
        )
    }

    private static func chartKind(in source: String) -> ExcelChartKind {
        if source.range(
            of: #"<(?:[A-Za-z_][\w.-]*:)?doughnutChart\b"#,
            options: .regularExpression
        ) != nil {
            return .doughnut
        }
        if source.range(
            of: #"<(?:[A-Za-z_][\w.-]*:)?pieChart\b"#,
            options: .regularExpression
        ) != nil {
            return .pie
        }
        if source.range(
            of: #"<(?:[A-Za-z_][\w.-]*:)?lineChart\b"#,
            options: .regularExpression
        ) != nil {
            return .line
        }
        if source.range(
            of: #"<(?:[A-Za-z_][\w.-]*:)?areaChart\b"#,
            options: .regularExpression
        ) != nil {
            return .area
        }
        if source.range(
            of: #"<(?:[A-Za-z_][\w.-]*:)?scatterChart\b"#,
            options: .regularExpression
        ) != nil {
            return .scatter
        }
        if source.range(
            of: #"<(?:[A-Za-z_][\w.-]*:)?radarChart\b"#,
            options: .regularExpression
        ) != nil {
            return .radar
        }
        if source.range(
            of: #"<(?:[A-Za-z_][\w.-]*:)?barChart\b"#,
            options: .regularExpression
        ) != nil {
            let barDirection = #"<(?:[A-Za-z_][\w.-]*:)?barDir\b[^>]*\bval\s*=\s*([\"'])bar\1"#
            return source.range(
                of: barDirection,
                options: .regularExpression
            ) == nil ? .column : .bar
        }
        return .unsupported
    }

    private static func isShapeAnchor(_ source: String) -> Bool {
        source.range(
            of: #"<(?:[A-Za-z_][\w.-]*:)?(?:sp|cxnSp)\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func shapeNonVisualID(in source: String) -> Int {
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?cNvPr\b[^>]*\bid\s*=\s*([\"'])([0-9]+)\1"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: source,
                  range: NSRange(source.startIndex..., in: source)
              ), let range = Range(match.range(at: 2), in: source) else {
            return 0
        }
        return Int(source[range]) ?? 0
    }

    private static func shapeText(in source: String) -> String {
        let textBody = content(of: "txBody", in: source) ?? source
        let paragraphs = contents(of: "p", in: textBody)
        let sources = paragraphs.isEmpty ? [textBody] : paragraphs
        return sources.map { paragraph in
            contents(of: "t", in: paragraph)
                .map { unescapeXML($0.replacingOccurrences(
                    of: #"<[^>]+>"#,
                    with: "",
                    options: .regularExpression
                )) }
                .joined()
        }.joined(separator: paragraphs.isEmpty ? "" : "\n")
    }

    private static func shapeKind(in source: String) -> ExcelShapeKind {
        if source.range(
            of: #"<(?:[A-Za-z_][\w.-]*:)?cNvSpPr\b[^>]*\btxBox\s*=\s*([\"'])(?:1|true)\1"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil { return .textBox }
        if source.range(
            of: #"<(?:[A-Za-z_][\w.-]*:)?cxnSp\b"#,
            options: .regularExpression
        ) != nil { return .line }
        guard let geometry = firstAttribute(
            "prst",
            element: "prstGeom",
            in: source
        )?.lowercased() else { return .unsupported }
        switch geometry {
        case "rect": return .rectangle
        case "roundrect": return .roundedRectangle
        case "ellipse": return .ellipse
        case "line": return .line
        default: return .unsupported
        }
    }

    private static func shapeColor(
        in source: String,
        line: Bool
    ) -> String? {
        let shapeProperties = content(of: "spPr", in: source) ?? source
        let colorSource = line
            ? content(of: "ln", in: shapeProperties) ?? ""
            : shapeProperties.components(separatedBy: "<a:ln").first
                ?? shapeProperties
        return firstAttribute("val", element: "srgbClr", in: colorSource)
    }

    private static func firstAttribute(
        _ attributeName: String,
        element: String,
        in source: String
    ) -> String? {
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?"#
            + NSRegularExpression.escapedPattern(for: element)
            + #"\b[^>]*>"#
        guard let range = source.range(of: pattern, options: .regularExpression)
        else { return nil }
        return attribute(attributeName, in: String(source[range]))
    }

    private static func chartTitle(in source: String) -> String? {
        guard let titleXML = content(of: "title", in: source),
              let text = content(of: "t", in: titleXML) else {
            return nil
        }
        let result = unescapeXML(
            text.replacingOccurrences(
                of: #"<[^>]+>"#,
                with: "",
                options: .regularExpression
            )
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func chartSourceRange(
        in source: String
    ) -> ExcelCellRange? {
        let ranges = contents(of: "f", in: source).compactMap {
            formulaRange($0)
        }
        guard let first = ranges.first else {
            return nil
        }
        return ranges.dropFirst().reduce(first) { result, range in
            ExcelCellRange(
                start: ExcelCellAddress(
                    row: min(result.start.row, range.start.row),
                    column: min(result.start.column, range.start.column)
                ),
                end: ExcelCellAddress(
                    row: max(result.end.row, range.end.row),
                    column: max(result.end.column, range.end.column)
                )
            )
        }
    }

    private static func sheetName(in source: String) -> String? {
        for formula in contents(of: "f", in: source) {
            guard let separator = formula.lastIndex(of: "!") else {
                continue
            }
            var name = String(formula[..<separator])
            if name.hasPrefix("'"), name.hasSuffix("'") {
                name.removeFirst()
                name.removeLast()
                name = name.replacingOccurrences(of: "''", with: "'")
            }
            if !name.isEmpty { return name }
        }
        return nil
    }

    private static func formulaRange(_ formula: String) -> ExcelCellRange? {
        let reference = formula.split(separator: "!").last.map(String.init)
            ?? formula
        return ExcelCellRange(
            reference.replacingOccurrences(of: "$", with: "")
        )
    }

    private static func contents(
        of element: String,
        in source: String
    ) -> [String] {
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?"# + element
            + #"\b[^>]*>([\s\S]*?)</(?:[A-Za-z_][\w.-]*:)?"#
            + element + #"\s*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        return regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).compactMap { match in
            Range(match.range(at: 1), in: source).map {
                String(source[$0])
            }
        }
    }

    private static func content(
        of element: String,
        in source: String
    ) -> String? {
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?"# + element
            + #"\b[^>]*>([\s\S]*?)</(?:[A-Za-z_][\w.-]*:)?"#
            + element + #"\s*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: source,
                  range: NSRange(source.startIndex..., in: source)
              ),
              let range = Range(match.range(at: 1), in: source) else {
            return nil
        }
        return String(source[range])
    }

    private static func attribute(
        _ name: String,
        in source: String
    ) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"(?:^|\s)(?:[A-Za-z_][\w.-]*:)?"# + escaped
            + #"\s*=\s*([\"'])(.*?)\1"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: source,
                  range: NSRange(source.startIndex..., in: source)
              ),
              let range = Range(match.range(at: 2), in: source) else {
            return nil
        }
        return unescapeXML(String(source[range]))
    }

    private static func contentType(for path: String) -> String {
        switch path.split(separator: ".").last?.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "tif", "tiff": return "image/tiff"
        default: return "image/png"
        }
    }

    private static func unescapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

public nonisolated enum ExcelWorksheetDrawingPackageWriter {
    public static func apply(
        _ edit: ExcelWorksheetDrawingEdits,
        sheetXML: inout String,
        reader: ExcelArchiveReader,
        replacements: inout [String: Data]
    ) throws {
        let sheetRelationshipsPath = relationshipsPath(for: edit.partPath)
        var sheetRelationshipsXML = try existingXML(
            at: sheetRelationshipsPath,
            reader: reader,
            replacements: replacements
        ) ?? emptyRelationshipsXML
        let current = edit.current
        let hasRemainingDrawingObjects = !current.images.isEmpty
            || !current.charts.isEmpty
            || !current.shapes.isEmpty
            || current.otherDrawingObjectCount > 0

        guard hasRemainingDrawingObjects else {
            if let relationshipID = edit.original.drawingRelationshipID {
                sheetRelationshipsXML = removingRelationship(
                    id: relationshipID,
                    from: sheetRelationshipsXML
                )
                sheetXML = removingDrawingElement(from: sheetXML)
                replacements[sheetRelationshipsPath] = Data(
                    sheetRelationshipsXML.utf8
                )
            }
            return
        }

        guard let drawingPath = current.drawingPartPath,
              let drawingRelationshipID = current.drawingRelationshipID else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        if !relationshipHasID(
            drawingRelationshipID,
            in: sheetRelationshipsXML
        ) {
            sheetRelationshipsXML = insertingRelationship(
                id: drawingRelationshipID,
                type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing",
                target: relativeTarget(from: edit.partPath, to: drawingPath),
                into: sheetRelationshipsXML
            )
        }
        sheetXML = try ensuringDrawingElement(
            relationshipID: drawingRelationshipID,
            in: sheetXML
        )

        let drawingRelationshipsPath = relationshipsPath(for: drawingPath)
        let hadDrawingRelationships = replacements[drawingRelationshipsPath]
            != nil || reader.contains(drawingRelationshipsPath)
        var drawingXML = try existingXML(
            at: drawingPath,
            reader: reader,
            replacements: replacements
        ) ?? emptyDrawingXML
        var drawingRelationshipsXML = try existingXML(
            at: drawingRelationshipsPath,
            reader: reader,
            replacements: replacements
        ) ?? emptyRelationshipsXML

        let currentIDs = Set(current.images.map(\.id))
        for originalImage in edit.original.images
            where !currentIDs.contains(originalImage.id) {
            drawingXML = removingAnchor(
                relationshipID: originalImage.relationshipID,
                from: drawingXML
            )
            drawingRelationshipsXML = removingRelationship(
                id: originalImage.relationshipID,
                from: drawingRelationshipsXML
            )
        }

        let originalByID = Dictionary(
            uniqueKeysWithValues: edit.original.images.map { ($0.id, $0) }
        )
        var usedPictureIDs = pictureIDs(in: drawingXML)
        for image in current.images {
            let originalImage = originalByID[image.id]
            let needsRelationship = originalImage == nil
                || originalImage?.mediaPartPath != image.mediaPartPath
            if needsRelationship {
                if originalImage != nil {
                    drawingRelationshipsXML = removingRelationship(
                        id: image.relationshipID,
                        from: drawingRelationshipsXML
                    )
                }
                if !relationshipHasID(
                    image.relationshipID,
                    in: drawingRelationshipsXML
                ) {
                    drawingRelationshipsXML = insertingRelationship(
                        id: image.relationshipID,
                        type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image",
                        target: relativeTarget(
                            from: drawingPath,
                            to: image.mediaPartPath
                        ),
                        into: drawingRelationshipsXML
                    )
                }
                if originalImage == nil {
                    let pictureID = nextPictureID(used: usedPictureIDs)
                    usedPictureIDs.insert(pictureID)
                    drawingXML = try insertingAnchor(
                        imageAnchorXML(image, pictureID: pictureID),
                        into: drawingXML
                    )
                }
            }
            if originalByID[image.id]?.data != image.data
                || !reader.contains(image.mediaPartPath) {
                replacements[image.mediaPartPath] = image.data
            }
            if originalImage == nil || originalImage?.anchor != image.anchor || originalImage?.name != image.name || originalImage?.alternativeText != image.alternativeText {
                drawingXML = try ExcelDrawingPlacementXML.updating(drawingXML, relationshipID: image.relationshipID, anchor: image.anchor, name: image.name, alternativeText: image.alternativeText, isImage: true)
            }
        }

        let currentChartIDs = Set(current.charts.map(\.id))
        for originalChart in edit.original.charts
            where !currentChartIDs.contains(originalChart.id) {
            drawingXML = removingChartAnchor(
                relationshipID: originalChart.relationshipID,
                from: drawingXML
            )
            drawingRelationshipsXML = removingRelationship(
                id: originalChart.relationshipID,
                from: drawingRelationshipsXML
            )
        }
        let originalChartsByID = Dictionary(
            uniqueKeysWithValues: edit.original.charts.map { ($0.id, $0) }
        )
        for chart in current.charts {
            let originalChart = originalChartsByID[chart.id]
            if originalChart == nil {
                drawingRelationshipsXML = insertingRelationship(
                    id: chart.relationshipID,
                    type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart",
                    target: relativeTarget(
                        from: drawingPath,
                        to: chart.chartPartPath
                    ),
                    into: drawingRelationshipsXML
                )
                let pictureID = nextPictureID(used: usedPictureIDs)
                usedPictureIDs.insert(pictureID)
                drawingXML = try insertingAnchor(
                    chartAnchorXML(chart, pictureID: pictureID),
                    into: drawingXML
                )
            }
            if originalChart == nil || originalChart?.anchor != chart.anchor || originalChart?.name != chart.name {
                drawingXML = try ExcelDrawingPlacementXML.updating(drawingXML, relationshipID: chart.relationshipID, anchor: chart.anchor, name: chart.name, alternativeText: nil, isImage: false)
            }
            if originalChart == nil || originalChart?.title != chart.title || originalChart?.kind != chart.kind || originalChart?.sourceRange != chart.sourceRange || originalChart?.sheetName != chart.sheetName {
                replacements[chart.chartPartPath] = Data(
                    try chartXML(for: chart).utf8
                )
            }
        }

        let currentShapeIDs = Set(current.shapes.map(\.id))
        for originalShape in edit.original.shapes
            where !currentShapeIDs.contains(originalShape.id) {
            drawingXML = removingShapeAnchor(
                nonVisualID: originalShape.nonVisualID,
                from: drawingXML
            )
        }
        let originalShapesByID = Dictionary(
            uniqueKeysWithValues: edit.original.shapes.map { ($0.id, $0) }
        )
        for shape in current.shapes where shape.kind.isEditable {
            let originalShape = originalShapesByID[shape.id]
            guard originalShape == nil || originalShape != shape else {
                continue
            }
            if let originalShape {
                drawingXML = removingShapeAnchor(
                    nonVisualID: originalShape.nonVisualID,
                    from: drawingXML
                )
            }
            let shapeID: Int
            if shape.nonVisualID > 0 {
                shapeID = shape.nonVisualID
            } else {
                shapeID = nextPictureID(used: usedPictureIDs)
            }
            usedPictureIDs.insert(shapeID)
            drawingXML = try insertingAnchor(
                shapeAnchorXML(shape, nonVisualID: shapeID),
                into: drawingXML
            )
        }
        replacements[drawingPath] = Data(drawingXML.utf8)
        if hadDrawingRelationships
            || drawingRelationshipsXML.range(
                of: #"<(?:[A-Za-z_][\w.-]*:)?Relationship\b"#,
                options: .regularExpression
            ) != nil {
            replacements[drawingRelationshipsPath] = Data(
                drawingRelationshipsXML.utf8
            )
        }
        replacements[sheetRelationshipsPath] = Data(
            sheetRelationshipsXML.utf8
        )
        try ensureContentTypes(
            drawingPartPath: drawingPath,
            images: current.images,
            charts: current.charts,
            reader: reader,
            replacements: &replacements
        )
    }

    private static let emptyRelationshipsXML =
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"></Relationships>
        """

    private static let emptyDrawingXML =
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"></xdr:wsDr>
        """

    private static func relationshipsPath(for partPath: String) -> String {
        let components = partPath.split(separator: "/")
        let filename = components.last.map(String.init) ?? partPath
        let directory = components.dropLast().joined(separator: "/")
        return directory + "/_rels/" + filename + ".rels"
    }

    private static func existingXML(
        at path: String,
        reader: ExcelArchiveReader,
        replacements: [String: Data]
    ) throws -> String? {
        let data: Data
        if let replacement = replacements[path] {
            data = replacement
        } else if reader.contains(path) {
            data = try reader.data(at: path)
        } else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func relationshipHasID(
        _ identifier: String,
        in source: String
    ) -> Bool {
        source.range(
            of: #"\bId\s*=\s*([\"'])"#
                + NSRegularExpression.escapedPattern(for: identifier)
                + #"\1"#,
            options: .regularExpression
        ) != nil
    }

    private static func insertingRelationship(
        id: String,
        type: String,
        target: String,
        into source: String
    ) -> String {
        var result = source
        if let selfClosing = result.range(
            of: #"<(?:[A-Za-z_][\w.-]*:)?Relationships\b([^>]*)/\s*>"#,
            options: .regularExpression
        ) {
            let opening = String(result[selfClosing])
                .replacingOccurrences(
                    of: #"/\s*>$"#,
                    with: ">",
                    options: .regularExpression
                )
            result.replaceSubrange(
                selfClosing,
                with: opening + "</Relationships>"
            )
        }
        let relationship = "<Relationship Id=\""
            + escapeAttribute(id) + "\" Type=\""
            + escapeAttribute(type) + "\" Target=\""
            + escapeAttribute(target) + "\"/>"
        if let closing = result.range(
            of: #"</(?:[A-Za-z_][\w.-]*:)?Relationships\s*>"#,
            options: .regularExpression
        ) {
            result.insert(contentsOf: relationship, at: closing.lowerBound)
        }
        return result
    }

    private static func removingRelationship(
        id: String,
        from source: String
    ) -> String {
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?Relationship\b[^>]*/\s*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return source
        }
        var result = source
        for match in regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).reversed() {
            guard let range = Range(match.range, in: source) else {
                continue
            }
            let element = String(source[range])
            guard relationshipHasID(id, in: element),
                  let resultRange = Range(match.range, in: result) else {
                continue
            }
            result.removeSubrange(resultRange)
        }
        return result
    }

    private static func removingAnchor(
        relationshipID: String,
        from source: String
    ) -> String {
        let names = ["twoCellAnchor", "oneCellAnchor", "absoluteAnchor"]
        var result = source
        for name in names {
            let pattern = #"<(?:[A-Za-z_][\w.-]*:)?"# + name
                + #"\b[^>]*>[\s\S]*?</(?:[A-Za-z_][\w.-]*:)?"#
                + name + #"\s*>"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let snapshot = result
            for match in regex.matches(
                in: snapshot,
                range: NSRange(snapshot.startIndex..., in: snapshot)
            ).reversed() {
                guard let range = Range(match.range, in: snapshot) else {
                    continue
                }
                let element = String(snapshot[range])
                let escapedID = NSRegularExpression.escapedPattern(
                    for: relationshipID
                )
                guard element.range(
                    of: #"(?:r:)?embed\s*=\s*([\"'])"# + escapedID
                        + #"\1"#,
                    options: .regularExpression
                ) != nil,
                let resultRange = Range(match.range, in: result) else {
                    continue
                }
                result.removeSubrange(resultRange)
            }
        }
        return result
    }

    private static func removingChartAnchor(
        relationshipID: String,
        from source: String
    ) -> String {
        let names = ["twoCellAnchor", "oneCellAnchor", "absoluteAnchor"]
        var result = source
        let escapedID = NSRegularExpression.escapedPattern(
            for: relationshipID
        )
        for name in names {
            let pattern = #"<(?:[A-Za-z_][\w.-]*:)?"# + name
                + #"\b[^>]*>[\s\S]*?</(?:[A-Za-z_][\w.-]*:)?"#
                + name + #"\s*>"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let snapshot = result
            for match in regex.matches(
                in: snapshot,
                range: NSRange(snapshot.startIndex..., in: snapshot)
            ).reversed() {
                guard let range = Range(match.range, in: snapshot) else {
                    continue
                }
                let element = String(snapshot[range])
                let chartPattern = #"<(?:[A-Za-z_][\w.-]*:)?chart\b[^>]*\b(?:r:)?id\s*=\s*([\"'])"#
                    + escapedID + #"\1"#
                guard element.range(
                    of: chartPattern,
                    options: .regularExpression
                ) != nil,
                let resultRange = Range(match.range, in: result) else {
                    continue
                }
                result.removeSubrange(resultRange)
            }
        }
        return result
    }

    private static func removingShapeAnchor(
        nonVisualID: Int,
        from source: String
    ) -> String {
        let names = ["twoCellAnchor", "oneCellAnchor", "absoluteAnchor"]
        var result = source
        for name in names {
            let pattern = #"<(?:[A-Za-z_][\w.-]*:)?"# + name
                + #"\b[^>]*>[\s\S]*?</(?:[A-Za-z_][\w.-]*:)?"#
                + name + #"\s*>"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let snapshot = result
            for match in regex.matches(
                in: snapshot,
                range: NSRange(snapshot.startIndex..., in: snapshot)
            ).reversed() {
                guard let range = Range(match.range, in: snapshot) else {
                    continue
                }
                let element = String(snapshot[range])
                let idPattern = #"<(?:[A-Za-z_][\w.-]*:)?cNvPr\b[^>]*\bid\s*=\s*([\"'])"#
                    + String(nonVisualID) + #"\1"#
                guard element.range(
                    of: #"<(?:[A-Za-z_][\w.-]*:)?(?:sp|cxnSp)\b"#,
                    options: .regularExpression
                ) != nil,
                element.range(of: idPattern, options: .regularExpression) != nil,
                let resultRange = Range(match.range, in: result) else {
                    continue
                }
                result.removeSubrange(resultRange)
            }
        }
        return result
    }

    private static func pictureIDs(in source: String) -> Set<Int> {
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?cNvPr\b[^>]*\bid\s*=\s*([\"'])([0-9]+)\1"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        return Set(regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).compactMap { match in
            guard let range = Range(match.range(at: 2), in: source) else {
                return nil
            }
            return Int(source[range])
        })
    }

    private static func nextPictureID(used: Set<Int>) -> Int {
        var candidate = 1
        while used.contains(candidate) {
            candidate += 1
        }
        return candidate
    }

    private static func imageAnchorXML(
        _ image: ExcelSheetImage,
        pictureID: Int
    ) -> String {
        let startColumn = max(image.anchor.start.column - 1, 0)
        let startRow = max(image.anchor.start.row - 1, 0)
        let endColumn = max(image.anchor.end.column - 1, startColumn + 1)
        let endRow = max(image.anchor.end.row - 1, startRow + 1)
        let alternativeText = image.alternativeText.map {
            " descr=\"" + escapeAttribute($0) + "\""
        } ?? ""
        return
            """
            <xdr:twoCellAnchor editAs="oneCell"><xdr:from><xdr:col>\(startColumn)</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>\(startRow)</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from><xdr:to><xdr:col>\(endColumn)</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>\(endRow)</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to><xdr:pic><xdr:nvPicPr><xdr:cNvPr id="\(pictureID)" name="\(escapeAttribute(image.name))"\(alternativeText)/><xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr><xdr:blipFill><a:blip r:embed="\(escapeAttribute(image.relationshipID))"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr><a:xfrm/><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:twoCellAnchor>
            """
    }

    private static func chartAnchorXML(
        _ chart: ExcelSheetChart,
        pictureID: Int
    ) -> String {
        let startColumn = max(chart.anchor.start.column - 1, 0)
        let startRow = max(chart.anchor.start.row - 1, 0)
        let endColumn = max(chart.anchor.end.column - 1, startColumn + 1)
        let endRow = max(chart.anchor.end.row - 1, startRow + 1)
        return
            """
            <xdr:twoCellAnchor editAs="oneCell"><xdr:from><xdr:col>\(startColumn)</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>\(startRow)</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from><xdr:to><xdr:col>\(endColumn)</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>\(endRow)</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to><xdr:graphicFrame macro=""><xdr:nvGraphicFramePr><xdr:cNvPr id="\(pictureID)" name="\(escapeAttribute(chart.name))"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr><xdr:xfrm/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="\(escapeAttribute(chart.relationshipID))"/></a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:twoCellAnchor>
            """
    }

    private static func shapeAnchorXML(
        _ shape: ExcelSheetShape,
        nonVisualID: Int
    ) -> String {
        let startColumn = max(shape.anchor.start.column - 1, 0)
        let startRow = max(shape.anchor.start.row - 1, 0)
        let endColumn = max(shape.anchor.end.column - 1, startColumn + 1)
        let endRow = max(shape.anchor.end.row - 1, startRow + 1)
        let geometry: String
        switch shape.kind {
        case .rectangle, .textBox: geometry = "rect"
        case .roundedRectangle: geometry = "roundRect"
        case .ellipse: geometry = "ellipse"
        case .line: geometry = "line"
        case .unsupported: geometry = "rect"
        }
        let textBoxAttribute = shape.kind == .textBox ? " txBox=\"1\"" : ""
        let fillXML = shape.kind == .line
            ? "<a:noFill/>"
            : shape.fillARGB.map {
                "<a:solidFill><a:srgbClr val=\""
                    + escapeAttribute(normalizedColor($0, fallback: "D9EAF7"))
                    + "\"/></a:solidFill>"
            } ?? "<a:solidFill><a:srgbClr val=\"D9EAF7\"/></a:solidFill>"
        let lineXML = "<a:ln><a:solidFill><a:srgbClr val=\""
            + escapeAttribute(normalizedColor(shape.lineARGB, fallback: "4472C4"))
            + "\"/></a:solidFill></a:ln>"
        let paragraphs = shape.text.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map {
            "<a:p><a:r><a:rPr lang=\"ko-KR\"/><a:t>"
                + escapeText(String($0))
                + "</a:t></a:r><a:endParaRPr lang=\"ko-KR\"/></a:p>"
        }.joined()
        let textXML = "<xdr:txBody><a:bodyPr wrap=\"square\"/><a:lstStyle/>"
            + (paragraphs.isEmpty ? "<a:p/>" : paragraphs)
            + "</xdr:txBody>"
        return
            """
            <xdr:twoCellAnchor editAs="oneCell"><xdr:from><xdr:col>\(startColumn)</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>\(startRow)</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from><xdr:to><xdr:col>\(endColumn)</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>\(endRow)</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to><xdr:sp macro="" textlink=""><xdr:nvSpPr><xdr:cNvPr id="\(nonVisualID)" name="\(escapeAttribute(shape.name))"/><xdr:cNvSpPr\(textBoxAttribute)/></xdr:nvSpPr><xdr:spPr><a:xfrm/><a:prstGeom prst="\(geometry)"><a:avLst/></a:prstGeom>\(fillXML)\(lineXML)</xdr:spPr>\(textXML)</xdr:sp><xdr:clientData/></xdr:twoCellAnchor>
            """
    }

    private static func normalizedColor(
        _ value: String?,
        fallback: String
    ) -> String {
        let cleaned = (value ?? fallback)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .uppercased()
        if cleaned.count == 8 { return String(cleaned.suffix(6)) }
        return cleaned.count == 6 ? cleaned : fallback
    }

    private static func chartXML(for chart: ExcelSheetChart) throws -> String {
        guard chart.kind.isEditable,
              let sourceRange = chart.sourceRange,
              sourceRange.end.row > sourceRange.start.row else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        let sheetPrefix = "'"
            + chart.sheetName.replacingOccurrences(of: "'", with: "''")
            + "'!"
        let dataStartRow = sourceRange.start.row + 1
        let hasCategoryColumn = sourceRange.end.column
            > sourceRange.start.column
        let categoryRange = hasCategoryColumn
            ? ExcelCellRange(
                start: ExcelCellAddress(
                    row: dataStartRow,
                    column: sourceRange.start.column
                ),
                end: ExcelCellAddress(
                    row: sourceRange.end.row,
                    column: sourceRange.start.column
                )
            )
            : nil
        let firstSeriesColumn = hasCategoryColumn
            ? sourceRange.start.column + 1
            : sourceRange.start.column
        var seriesColumns = Array(firstSeriesColumn ... sourceRange.end.column)
        if chart.kind == .pie || chart.kind == .doughnut {
            seriesColumns = Array(seriesColumns.prefix(1))
        }
        guard !seriesColumns.isEmpty else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        let series = seriesColumns.enumerated().map { index, column in
            let titleReference = absoluteReference(
                ExcelCellAddress(
                    row: sourceRange.start.row,
                    column: column
                )
            )
            let valuesReference = absoluteReference(
                ExcelCellRange(
                    start: ExcelCellAddress(
                        row: dataStartRow,
                        column: column
                    ),
                    end: ExcelCellAddress(
                        row: sourceRange.end.row,
                        column: column
                    )
                )
            )
            let categories = categoryRange.map {
                "<c:cat><c:strRef><c:f>"
                    + escapeText(sheetPrefix + absoluteReference($0))
                    + "</c:f></c:strRef></c:cat>"
            } ?? ""
            return "<c:ser><c:idx val=\"\(index)\"/><c:order val=\"\(index)\"/><c:tx><c:strRef><c:f>"
                + escapeText(sheetPrefix + titleReference)
                + "</c:f></c:strRef></c:tx>" + categories
                + "<c:val><c:numRef><c:f>"
                + escapeText(sheetPrefix + valuesReference)
                + "</c:f></c:numRef></c:val></c:ser>"
        }.joined()
        let scatterSeries = seriesColumns.enumerated().map { index, column in
            let titleReference = absoluteReference(
                ExcelCellAddress(
                    row: sourceRange.start.row,
                    column: column
                )
            )
            let valuesReference = absoluteReference(
                ExcelCellRange(
                    start: ExcelCellAddress(
                        row: dataStartRow,
                        column: column
                    ),
                    end: ExcelCellAddress(
                        row: sourceRange.end.row,
                        column: column
                    )
                )
            )
            let xReference = categoryRange.map(absoluteReference)
                ?? valuesReference
            return "<c:ser><c:idx val=\"\(index)\"/><c:order val=\"\(index)\"/><c:tx><c:strRef><c:f>"
                + escapeText(sheetPrefix + titleReference)
                + "</c:f></c:strRef></c:tx><c:spPr><a:ln><a:noFill/></a:ln></c:spPr><c:marker><c:symbol val=\"circle\"/><c:size val=\"5\"/></c:marker><c:xVal><c:numRef><c:f>"
                + escapeText(sheetPrefix + xReference)
                + "</c:f></c:numRef></c:xVal><c:yVal><c:numRef><c:f>"
                + escapeText(sheetPrefix + valuesReference)
                + "</c:f></c:numRef></c:yVal><c:smooth val=\"0\"/></c:ser>"
        }.joined()
        let categoryAxisID = 48_610_112
        let valueAxisID = 48_672_896
        let plotXML: String
        switch chart.kind {
        case .column, .bar:
            let direction = chart.kind == .bar ? "bar" : "col"
            plotXML = "<c:barChart><c:barDir val=\"\(direction)\"/><c:grouping val=\"clustered\"/><c:varyColors val=\"0\"/>"
                + series
                + "<c:axId val=\"\(categoryAxisID)\"/><c:axId val=\"\(valueAxisID)\"/></c:barChart>"
                + axesXML(
                    categoryAxisID: categoryAxisID,
                    valueAxisID: valueAxisID,
                    isHorizontal: chart.kind == .bar
                )
        case .line:
            plotXML = "<c:lineChart><c:grouping val=\"standard\"/><c:varyColors val=\"0\"/>"
                + series
                + "<c:marker val=\"1\"/><c:smooth val=\"0\"/><c:axId val=\"\(categoryAxisID)\"/><c:axId val=\"\(valueAxisID)\"/></c:lineChart>"
                + axesXML(
                    categoryAxisID: categoryAxisID,
                    valueAxisID: valueAxisID,
                    isHorizontal: false
                )
        case .pie:
            plotXML = "<c:pieChart><c:varyColors val=\"1\"/>"
                + series + "<c:firstSliceAng val=\"0\"/></c:pieChart>"
        case .area:
            plotXML = "<c:areaChart><c:grouping val=\"standard\"/><c:varyColors val=\"0\"/>"
                + series
                + "<c:axId val=\"\(categoryAxisID)\"/><c:axId val=\"\(valueAxisID)\"/></c:areaChart>"
                + axesXML(
                    categoryAxisID: categoryAxisID,
                    valueAxisID: valueAxisID,
                    isHorizontal: false
                )
        case .scatter:
            plotXML = "<c:scatterChart><c:scatterStyle val=\"marker\"/><c:varyColors val=\"0\"/>"
                + scatterSeries
                + "<c:axId val=\"\(categoryAxisID)\"/><c:axId val=\"\(valueAxisID)\"/></c:scatterChart>"
                + scatterAxesXML(
                    xAxisID: categoryAxisID,
                    yAxisID: valueAxisID
                )
        case .doughnut:
            plotXML = "<c:doughnutChart><c:varyColors val=\"1\"/>"
                + series
                + "<c:firstSliceAng val=\"0\"/><c:holeSize val=\"50\"/></c:doughnutChart>"
        case .radar:
            plotXML = "<c:radarChart><c:radarStyle val=\"standard\"/><c:varyColors val=\"0\"/>"
                + series
                + "<c:axId val=\"\(categoryAxisID)\"/><c:axId val=\"\(valueAxisID)\"/></c:radarChart>"
                + axesXML(
                    categoryAxisID: categoryAxisID,
                    valueAxisID: valueAxisID,
                    isHorizontal: false
                )
        case .unsupported:
            throw ExcelWorkbookDocumentError.cannotSave
        }
        let title = chart.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleXML = title.isEmpty ? "" :
            "<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang=\"ko-KR\"/><a:t>"
                + escapeText(title)
                + "</a:t></a:r></a:p></c:rich></c:tx><c:layout/><c:overlay val=\"0\"/></c:title>"
        return
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><c:date1904 val="0"/><c:lang val="ko-KR"/><c:roundedCorners val="0"/><c:chart>\(titleXML)<c:autoTitleDeleted val="0"/><c:plotArea><c:layout/>\(plotXML)</c:plotArea><c:legend><c:legendPos val="r"/><c:layout/><c:overlay val="0"/></c:legend><c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/><c:showDLblsOverMax val="0"/></c:chart><c:printSettings><c:headerFooter/><c:pageMargins b="0.75" l="0.7" r="0.7" t="0.75" header="0.3" footer="0.3"/><c:pageSetup/></c:printSettings></c:chartSpace>
            """
    }

    private static func axesXML(
        categoryAxisID: Int,
        valueAxisID: Int,
        isHorizontal: Bool
    ) -> String {
        let categoryPosition = isHorizontal ? "l" : "b"
        let valuePosition = isHorizontal ? "b" : "l"
        return "<c:catAx><c:axId val=\"\(categoryAxisID)\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"\(categoryPosition)\"/><c:numFmt formatCode=\"General\" sourceLinked=\"1\"/><c:majorTickMark val=\"none\"/><c:minorTickMark val=\"none\"/><c:tickLblPos val=\"nextTo\"/><c:crossAx val=\"\(valueAxisID)\"/><c:crosses val=\"autoZero\"/><c:auto val=\"1\"/><c:lblAlgn val=\"ctr\"/><c:lblOffset val=\"100\"/></c:catAx><c:valAx><c:axId val=\"\(valueAxisID)\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"\(valuePosition)\"/><c:majorGridlines/><c:numFmt formatCode=\"General\" sourceLinked=\"1\"/><c:majorTickMark val=\"none\"/><c:minorTickMark val=\"none\"/><c:tickLblPos val=\"nextTo\"/><c:crossAx val=\"\(categoryAxisID)\"/><c:crosses val=\"autoZero\"/><c:crossBetween val=\"between\"/></c:valAx>"
    }

    private static func scatterAxesXML(
        xAxisID: Int,
        yAxisID: Int
    ) -> String {
        "<c:valAx><c:axId val=\"\(xAxisID)\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"b\"/><c:majorGridlines/><c:numFmt formatCode=\"General\" sourceLinked=\"1\"/><c:tickLblPos val=\"nextTo\"/><c:crossAx val=\"\(yAxisID)\"/><c:crosses val=\"autoZero\"/><c:crossBetween val=\"midCat\"/></c:valAx><c:valAx><c:axId val=\"\(yAxisID)\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"l\"/><c:majorGridlines/><c:numFmt formatCode=\"General\" sourceLinked=\"1\"/><c:tickLblPos val=\"nextTo\"/><c:crossAx val=\"\(xAxisID)\"/><c:crosses val=\"autoZero\"/><c:crossBetween val=\"midCat\"/></c:valAx>"
    }

    private static func absoluteReference(
        _ address: ExcelCellAddress
    ) -> String {
        "$" + ExcelCellAddress.columnName(address.column)
            + "$" + String(address.row)
    }

    private static func absoluteReference(_ range: ExcelCellRange) -> String {
        let start = absoluteReference(range.start)
        let end = absoluteReference(range.end)
        return start == end ? start : start + ":" + end
    }

    private static func insertingAnchor(
        _ anchor: String,
        into source: String
    ) throws -> String {
        var result = source
        guard let closing = result.range(
            of: #"</(?:[A-Za-z_][\w.-]*:)?wsDr\s*>"#,
            options: .regularExpression
        ) else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        result.insert(contentsOf: anchor, at: closing.lowerBound)
        return result
    }

    private static func ensuringDrawingElement(
        relationshipID: String,
        in source: String
    ) throws -> String {
        var result = ensureRelationshipNamespace(in: source)
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?drawing\b[^>]*/\s*>"#
        if let range = result.range(of: pattern, options: .regularExpression) {
            let prefix = elementPrefix(in: String(result[range]))
            result.replaceSubrange(
                range,
                with: "<\(prefix)drawing r:id=\""
                    + escapeAttribute(relationshipID) + "\"/>"
            )
            return result
        }
        let prefix = worksheetPrefix(in: result)
        let element = "<\(prefix)drawing r:id=\""
            + escapeAttribute(relationshipID) + "\"/>"
        let laterPattern = "<"
            + NSRegularExpression.escapedPattern(for: prefix)
            + #"(?:legacyDrawing|legacyDrawingHF|picture|oleObjects|controls|webPublishItems|tableParts|extLst)\b"#
        if let range = result.range(
            of: laterPattern,
            options: .regularExpression
        ) {
            result.insert(contentsOf: element, at: range.lowerBound)
            return result
        }
        guard let closing = result.range(
            of: #"</(?:[A-Za-z_][\w.-]*:)?worksheet\s*>"#,
            options: .regularExpression
        ) else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        result.insert(contentsOf: element, at: closing.lowerBound)
        return result
    }

    private static func removingDrawingElement(from source: String) -> String {
        source.replacingOccurrences(
            of: #"<(?:[A-Za-z_][\w.-]*:)?drawing\b[^>]*/\s*>"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func ensureRelationshipNamespace(in source: String) -> String {
        guard !source.contains("xmlns:r=") else {
            return source
        }
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?worksheet\b"#
        guard let range = source.range(of: pattern, options: .regularExpression)
        else {
            return source
        }
        var result = source
        result.insert(
            contentsOf: " xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"",
            at: range.upperBound
        )
        return result
    }

    private static func worksheetPrefix(in source: String) -> String {
        let pattern = #"<([A-Za-z_][\w.-]*:)?worksheet\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: source,
                  range: NSRange(source.startIndex..., in: source)
              ),
              match.range(at: 1).location != NSNotFound,
              let range = Range(match.range(at: 1), in: source) else {
            return ""
        }
        return String(source[range])
    }

    private static func elementPrefix(in source: String) -> String {
        let pattern = #"<([A-Za-z_][\w.-]*:)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: source,
                  range: NSRange(source.startIndex..., in: source)
              ),
              match.range(at: 1).location != NSNotFound,
              let range = Range(match.range(at: 1), in: source) else {
            return ""
        }
        return String(source[range])
    }

    private static func relativeTarget(from source: String, to target: String)
        -> String {
        let sourceDirectory = source.split(separator: "/").dropLast()
            .map(String.init)
        let targetComponents = target.split(separator: "/").map(String.init)
        var shared = 0
        while shared < sourceDirectory.count,
              shared < targetComponents.count,
              sourceDirectory[shared] == targetComponents[shared] {
            shared += 1
        }
        let parents = Array(
            repeating: "..",
            count: sourceDirectory.count - shared
        )
        return (parents + Array(targetComponents.dropFirst(shared)))
            .joined(separator: "/")
    }

    private static func ensureContentTypes(
        drawingPartPath: String,
        images: [ExcelSheetImage],
        charts: [ExcelSheetChart],
        reader: ExcelArchiveReader,
        replacements: inout [String: Data]
    ) throws {
        let path = "[Content_Types].xml"
        guard var source = try existingXML(
            at: path,
            reader: reader,
            replacements: replacements
        ) else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        let drawingPartName = "/" + drawingPartPath
        if !source.contains("PartName=\"\(drawingPartName)\"") {
            source = try insertContentType(
                "<Override PartName=\"" + escapeAttribute(drawingPartName)
                    + "\" ContentType=\"application/vnd.openxmlformats-officedocument.drawing+xml\"/>",
                into: source
            )
        }
        let defaults = Dictionary(grouping: images) {
            $0.mediaPartPath.split(separator: ".").last
                .map(String.init)?.lowercased() ?? "png"
        }
        for (extensionName, groupedImages) in defaults {
            if source.range(
                of: #"\bExtension\s*=\s*([\"'])"#
                    + NSRegularExpression.escapedPattern(for: extensionName)
                    + #"\1"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil {
                continue
            }
            let contentType = groupedImages.first?.contentType ?? "image/png"
            source = try insertContentType(
                "<Default Extension=\"" + escapeAttribute(extensionName)
                    + "\" ContentType=\"" + escapeAttribute(contentType)
                    + "\"/>",
                into: source
            )
        }
        for chart in charts {
            let chartPartName = "/" + chart.chartPartPath
            guard !source.contains("PartName=\"\(chartPartName)\"") else {
                continue
            }
            source = try insertContentType(
                "<Override PartName=\"" + escapeAttribute(chartPartName)
                    + "\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/>",
                into: source
            )
        }
        replacements[path] = Data(source.utf8)
    }

    private static func insertContentType(
        _ element: String,
        into source: String
    ) throws -> String {
        var result = source
        if let selfClosing = result.range(
            of: #"<(?:[A-Za-z_][\w.-]*:)?Types\b([^>]*)/\s*>"#,
            options: .regularExpression
        ) {
            let opening = String(result[selfClosing])
                .replacingOccurrences(
                    of: #"/\s*>$"#,
                    with: ">",
                    options: .regularExpression
                )
            result.replaceSubrange(selfClosing, with: opening + "</Types>")
        }
        guard let closing = result.range(
            of: #"</(?:[A-Za-z_][\w.-]*:)?Types\s*>"#,
            options: .regularExpression
        ) else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        result.insert(contentsOf: element, at: closing.lowerBound)
        return result
    }

    private static func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
