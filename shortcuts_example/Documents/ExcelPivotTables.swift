import Foundation

nonisolated enum ExcelPivotAggregation:
    String,
    CaseIterable,
    Identifiable,
    Sendable
{
    case sum
    case count

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sum:
            return AppLocalization.string("합계")
        case .count:
            return AppLocalization.string("개수")
        }
    }
}

nonisolated struct ExcelPivotTable: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var relationshipID: String
    var partPath: String
    var cacheID: Int
    var cacheDefinitionPath: String?
    var cacheRelationshipID: String?
    var workbookCacheRelationshipID: String?
    var sourceSheetName: String?
    var sourceRange: ExcelCellRange?
    var destinationRange: ExcelCellRange?
    var fieldNames: [String]
    var rowFieldIndex: Int?
    var dataFieldIndex: Int?
    var aggregation: ExcelPivotAggregation
    var refreshOnLoad: Bool
    var originalPivotXML: String?
    var originalCacheXML: String?

    var supportsFieldEditing: Bool {
        originalPivotXML == nil
            || (sourceRange != nil
                && destinationRange != nil
                && rowFieldIndex != nil
                && dataFieldIndex != nil
                && !fieldNames.isEmpty)
    }

    var supportsMetadataEditing: Bool {
        originalPivotXML == nil
            || originalPivotXML?.range(
                of: #"<(?:[A-Za-z_][\w.-]*:)?pivotTableDefinition\b"#,
                options: .regularExpression
            ) != nil
    }
}

nonisolated struct ExcelWorksheetPivotEdits: Sendable {
    let partPath: String
    let original: [ExcelPivotTable]
    let current: [ExcelPivotTable]
}

nonisolated enum ExcelWorksheetPivotTablesLoader {
    static func load(
        sheetPartPath: String,
        relationships: [String: ExcelRelationship],
        workbookPivotCacheRelationshipIDs: [Int: String],
        workbookRelationships: [String: ExcelRelationship],
        reader: ExcelArchiveReader
    ) throws -> [ExcelPivotTable] {
        var result = [ExcelPivotTable]()
        let pivotRelationships = relationships.filter {
            $0.value.type.hasSuffix("/pivotTable")
        }.sorted { $0.key < $1.key }

        for (relationshipID, relationship) in pivotRelationships {
            guard let partPath = normalizedPartPath(
                relationship.target,
                relativeTo: sheetPartPath
            ) else {
                continue
            }
            let pivotXML = reader.contains(partPath)
                ? String(
                    data: try reader.data(at: partPath),
                    encoding: .utf8
                )
                : nil
            let pivotInfo = pivotXML.flatMap(parsePivotXML)
            let cacheID = pivotInfo?.cacheID ?? 0
            let pivotRelationshipsPath = relationshipsPath(for: partPath)
            let pivotRelationships = reader.contains(pivotRelationshipsPath)
                ? try ExcelRelationshipsParser.parse(
                    reader.data(at: pivotRelationshipsPath)
                )
                : [:]
            let pivotCacheRelationship = pivotRelationships.first {
                $0.value.type.hasSuffix("/pivotCacheDefinition")
            }
            let workbookCacheRelationshipID =
                workbookPivotCacheRelationshipIDs[cacheID]
            let workbookCacheRelationship = workbookCacheRelationshipID
                .flatMap { workbookRelationships[$0] }
            let cachePath: String?
            if let target = pivotCacheRelationship?.value.target {
                cachePath = normalizedPartPath(
                    target,
                    relativeTo: partPath
                )
            } else if let target = workbookCacheRelationship?.target {
                cachePath = normalizedPartPath(
                    target,
                    relativeTo: "xl/workbook.xml"
                )
            } else {
                cachePath = nil
            }
            let cacheXML: String?
            if let cachePath,
               reader.contains(cachePath) {
                cacheXML = String(
                    data: try reader.data(at: cachePath),
                    encoding: .utf8
                )
            } else {
                cacheXML = nil
            }
            let cacheInfo = cacheXML.flatMap(parseCacheXML)
            let displayNumber = result.count + 1
            result.append(
                ExcelPivotTable(
                    id: partPath,
                    name: pivotInfo?.name
                        ?? AppLocalization.format(
                            "피벗 테이블 %lld",
                            displayNumber
                        ),
                    relationshipID: relationshipID,
                    partPath: partPath,
                    cacheID: cacheID,
                    cacheDefinitionPath: cachePath,
                    cacheRelationshipID: pivotCacheRelationship?.key,
                    workbookCacheRelationshipID:
                        workbookCacheRelationshipID,
                    sourceSheetName: cacheInfo?.sheetName,
                    sourceRange: cacheInfo?.sourceRange,
                    destinationRange: pivotInfo?.destinationRange,
                    fieldNames: cacheInfo?.fieldNames ?? [],
                    rowFieldIndex: pivotInfo?.rowFieldIndex,
                    dataFieldIndex: pivotInfo?.dataFieldIndex,
                    aggregation: pivotInfo?.aggregation ?? .sum,
                    refreshOnLoad: cacheInfo?.refreshOnLoad ?? false,
                    originalPivotXML: pivotXML,
                    originalCacheXML: cacheXML
                )
            )
        }
        return result
    }

    private struct PivotInfo {
        let name: String
        let cacheID: Int
        let destinationRange: ExcelCellRange?
        let rowFieldIndex: Int?
        let dataFieldIndex: Int?
        let aggregation: ExcelPivotAggregation
    }

    private struct CacheInfo {
        let sheetName: String?
        let sourceRange: ExcelCellRange?
        let fieldNames: [String]
        let refreshOnLoad: Bool
    }

    private static func parsePivotXML(_ source: String) -> PivotInfo? {
        let delegate = PivotDefinitionParserDelegate()
        guard let data = source.data(using: .utf8) else {
            return nil
        }
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(),
              let name = delegate.name else {
            return nil
        }
        return PivotInfo(
            name: name,
            cacheID: delegate.cacheID ?? 0,
            destinationRange: delegate.destinationReference.flatMap(
                ExcelCellRange.init
            ),
            rowFieldIndex: delegate.rowFieldIndex,
            dataFieldIndex: delegate.dataFieldIndex,
            aggregation: delegate.aggregation
        )
    }

    private static func parseCacheXML(_ source: String) -> CacheInfo? {
        let delegate = PivotCacheParserDelegate()
        guard let data = source.data(using: .utf8) else {
            return nil
        }
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            return nil
        }
        return CacheInfo(
            sheetName: delegate.sheetName,
            sourceRange: delegate.sourceReference.flatMap(
                ExcelCellRange.init
            ),
            fieldNames: delegate.fieldNames,
            refreshOnLoad: delegate.refreshOnLoad
        )
    }

    private static func relationshipsPath(for partPath: String) -> String {
        let components = partPath.split(separator: "/")
        let filename = components.last.map(String.init) ?? partPath
        let directory = components.dropLast().joined(separator: "/")
        return directory + "/_rels/" + filename + ".rels"
    }
}

private nonisolated final class PivotDefinitionParserDelegate:
    NSObject,
    XMLParserDelegate
{
    var name: String?
    var cacheID: Int?
    var destinationReference: String?
    var rowFieldIndex: Int?
    var dataFieldIndex: Int?
    var aggregation: ExcelPivotAggregation = .sum

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch localName(qName ?? elementName) {
        case "pivotTableDefinition":
            name = attributeDict["name"]
            cacheID = Int(attributeDict["cacheId"] ?? "")
        case "location":
            destinationReference = attributeDict["ref"]
        case "field":
            if rowFieldIndex == nil {
                rowFieldIndex = Int(attributeDict["x"] ?? "")
            }
        case "dataField":
            if dataFieldIndex == nil {
                dataFieldIndex = Int(attributeDict["fld"] ?? "")
                aggregation = ExcelPivotAggregation(
                    rawValue: attributeDict["subtotal"] ?? "sum"
                ) ?? .sum
            }
        default:
            break
        }
    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }
}

private nonisolated final class PivotCacheParserDelegate:
    NSObject,
    XMLParserDelegate
{
    var sheetName: String?
    var sourceReference: String?
    var fieldNames = [String]()
    var refreshOnLoad = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch localName(qName ?? elementName) {
        case "pivotCacheDefinition":
            refreshOnLoad = Self.boolean(attributeDict["refreshOnLoad"])
        case "worksheetSource":
            sheetName = attributeDict["sheet"]
            sourceReference = attributeDict["ref"]
        case "cacheField":
            fieldNames.append(attributeDict["name"] ?? "")
        default:
            break
        }
    }

    private static func boolean(_ value: String?) -> Bool {
        value == "1" || value?.lowercased() == "true"
    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }
}

nonisolated enum ExcelWorksheetPivotPackageWriter {
    static func apply(
        _ edit: ExcelWorksheetPivotEdits,
        reader: ExcelArchiveReader,
        replacements: inout [String: Data]
    ) throws {
        let sheetRelationshipsPath = relationshipsPath(for: edit.partPath)
        var sheetRelationshipsXML = try existingXML(
            at: sheetRelationshipsPath,
            reader: reader,
            replacements: replacements
        ) ?? emptyRelationshipsXML
        let originalByID = Dictionary(
            uniqueKeysWithValues: edit.original.map { ($0.id, $0) }
        )
        let currentIDs = Set(edit.current.map(\.id))

        for pivot in edit.original where !currentIDs.contains(pivot.id) {
            sheetRelationshipsXML = removingRelationship(
                id: pivot.relationshipID,
                from: sheetRelationshipsXML
            )
        }

        for pivot in edit.current {
            let original = originalByID[pivot.id]
            if original == nil {
                sheetRelationshipsXML = insertingRelationship(
                    id: pivot.relationshipID,
                    type: relationshipNamespace + "/pivotTable",
                    target: relativeTarget(
                        from: edit.partPath,
                        to: pivot.partPath
                    ),
                    into: sheetRelationshipsXML
                )
            }
            try writePivot(
                pivot,
                original: original,
                reader: reader,
                replacements: &replacements
            )
        }
        replacements[sheetRelationshipsPath] = Data(
            sheetRelationshipsXML.utf8
        )
    }

    private static func writePivot(
        _ pivot: ExcelPivotTable,
        original: ExcelPivotTable?,
        reader: ExcelArchiveReader,
        replacements: inout [String: Data]
    ) throws {
        guard pivot.supportsMetadataEditing else {
            return
        }
        let requiresFullWrite = original == nil
            || pivotConfigurationChanged(pivot, from: original)
        let pivotXML: String
        if requiresFullWrite {
            guard pivot.supportsFieldEditing else {
                throw ExcelWorkbookDocumentError.cannotSave
            }
            pivotXML = try generatedPivotXML(for: pivot)
        } else if let source = pivot.originalPivotXML {
            pivotXML = replacingRootAttribute(
                "name",
                with: pivot.name,
                root: "pivotTableDefinition",
                in: source
            )
        } else {
            pivotXML = try generatedPivotXML(for: pivot)
        }
        replacements[pivot.partPath] = Data(pivotXML.utf8)

        guard let cachePath = pivot.cacheDefinitionPath,
              let pivotCacheRelationshipID = pivot.cacheRelationshipID,
              let workbookCacheRelationshipID =
                pivot.workbookCacheRelationshipID else {
            if original == nil {
                throw ExcelWorkbookDocumentError.cannotSave
            }
            return
        }

        let cacheXML: String
        if requiresFullWrite {
            cacheXML = try generatedCacheXML(for: pivot)
        } else if let source = pivot.originalCacheXML {
            cacheXML = replacingRootAttribute(
                "refreshOnLoad",
                with: pivot.refreshOnLoad ? "1" : "0",
                root: "pivotCacheDefinition",
                in: source
            )
        } else {
            cacheXML = try generatedCacheXML(for: pivot)
        }
        replacements[cachePath] = Data(cacheXML.utf8)

        let pivotRelationshipsPath = relationshipsPath(for: pivot.partPath)
        var pivotRelationshipsXML = try existingXML(
            at: pivotRelationshipsPath,
            reader: reader,
            replacements: replacements
        ) ?? emptyRelationshipsXML
        pivotRelationshipsXML = insertingRelationship(
            id: pivotCacheRelationshipID,
            type: relationshipNamespace + "/pivotCacheDefinition",
            target: relativeTarget(from: pivot.partPath, to: cachePath),
            into: pivotRelationshipsXML
        )
        replacements[pivotRelationshipsPath] = Data(
            pivotRelationshipsXML.utf8
        )

        try ensureWorkbookCache(
            cacheID: pivot.cacheID,
            relationshipID: workbookCacheRelationshipID,
            cachePath: cachePath,
            reader: reader,
            replacements: &replacements
        )
        try ensureContentTypes(
            pivotPartPath: pivot.partPath,
            cachePartPath: cachePath,
            reader: reader,
            replacements: &replacements
        )
    }

    private static func pivotConfigurationChanged(
        _ pivot: ExcelPivotTable,
        from original: ExcelPivotTable?
    ) -> Bool {
        guard let original else { return true }
        return pivot.sourceSheetName != original.sourceSheetName
            || pivot.sourceRange != original.sourceRange
            || pivot.destinationRange != original.destinationRange
            || pivot.fieldNames != original.fieldNames
            || pivot.rowFieldIndex != original.rowFieldIndex
            || pivot.dataFieldIndex != original.dataFieldIndex
            || pivot.aggregation != original.aggregation
    }

    private static func generatedPivotXML(
        for pivot: ExcelPivotTable
    ) throws -> String {
        guard let destinationRange = pivot.destinationRange,
              let rowFieldIndex = pivot.rowFieldIndex,
              let dataFieldIndex = pivot.dataFieldIndex,
              pivot.fieldNames.indices.contains(rowFieldIndex),
              pivot.fieldNames.indices.contains(dataFieldIndex) else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        let pivotFields = pivot.fieldNames.indices.map { index in
            if index == rowFieldIndex {
                return #"<pivotField axis="axisRow" showAll="0"/>"#
            }
            if index == dataFieldIndex {
                return #"<pivotField dataField="1" showAll="0"/>"#
            }
            return #"<pivotField showAll="0"/>"#
        }.joined()
        let valueName = pivot.aggregation.title + " - "
            + pivot.fieldNames[dataFieldIndex]
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <pivotTableDefinition xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" name="\(escapeAttribute(pivot.name))" cacheId="\(pivot.cacheID)" dataCaption="\(escapeAttribute(valueName))" updatedVersion="8" minRefreshableVersion="3" useAutoFormatting="1" applyNumberFormats="0" applyBorderFormats="0" applyFontFormats="0" applyPatternFormats="0" applyAlignmentFormats="0" applyWidthHeightFormats="1" showCalcMbrs="1" indent="0" compact="1" compactData="1" gridDropZones="0" multipleFieldFilters="0">
        <location ref="\(escapeAttribute(destinationRange.reference))" firstHeaderRow="1" firstDataRow="2" firstDataCol="1"/>
        <pivotFields count="\(pivot.fieldNames.count)">\(pivotFields)</pivotFields>
        <rowFields count="1"><field x="\(rowFieldIndex)"/></rowFields>
        <rowItems count="1"><i/></rowItems>
        <colItems count="1"><i/></colItems>
        <dataFields count="1"><dataField name="\(escapeAttribute(valueName))" fld="\(dataFieldIndex)" subtotal="\(pivot.aggregation.rawValue)"/></dataFields>
        <pivotTableStyleInfo name="PivotStyleMedium9" showRowHeaders="1" showColHeaders="1" showRowStripes="0" showColStripes="0" showLastColumn="0"/>
        </pivotTableDefinition>
        """
    }

    private static func generatedCacheXML(
        for pivot: ExcelPivotTable
    ) throws -> String {
        guard let sourceSheetName = pivot.sourceSheetName,
              let sourceRange = pivot.sourceRange,
              !pivot.fieldNames.isEmpty else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        let cacheFields = pivot.fieldNames.map {
            "<cacheField name=\"" + escapeAttribute($0)
                + "\"><sharedItems/></cacheField>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <pivotCacheDefinition xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" saveData="0" refreshOnLoad="\(pivot.refreshOnLoad ? 1 : 0)" recordCount="0" createdVersion="8" refreshedVersion="8" minRefreshableVersion="3">
        <cacheSource type="worksheet"><worksheetSource ref="\(escapeAttribute(sourceRange.reference))" sheet="\(escapeAttribute(sourceSheetName))"/></cacheSource>
        <cacheFields count="\(pivot.fieldNames.count)">\(cacheFields)</cacheFields>
        </pivotCacheDefinition>
        """
    }

    private static func ensureWorkbookCache(
        cacheID: Int,
        relationshipID: String,
        cachePath: String,
        reader: ExcelArchiveReader,
        replacements: inout [String: Data]
    ) throws {
        let relationshipsPath = "xl/_rels/workbook.xml.rels"
        guard var relationshipsXML = try existingXML(
            at: relationshipsPath,
            reader: reader,
            replacements: replacements
        ) else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        relationshipsXML = insertingRelationship(
            id: relationshipID,
            type: relationshipNamespace + "/pivotCacheDefinition",
            target: relativeTarget(
                from: "xl/workbook.xml",
                to: cachePath
            ),
            into: relationshipsXML
        )
        replacements[relationshipsPath] = Data(relationshipsXML.utf8)

        guard var workbookXML = try existingXML(
            at: "xl/workbook.xml",
            reader: reader,
            replacements: replacements
        ) else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        guard !workbookCacheExists(
            cacheID: cacheID,
            relationshipID: relationshipID,
            in: workbookXML
        ) else {
            return
        }
        let element = "<pivotCache cacheId=\"\(cacheID)\" r:id=\""
            + escapeAttribute(relationshipID) + "\"/>"
        if let closing = workbookXML.range(
            of: #"</(?:[A-Za-z_][\w.-]*:)?pivotCaches\s*>"#,
            options: .regularExpression
        ) {
            workbookXML.insert(contentsOf: element, at: closing.lowerBound)
        } else {
            let block = "<pivotCaches>" + element + "</pivotCaches>"
            if let closingSheets = workbookXML.range(
                of: #"</(?:[A-Za-z_][\w.-]*:)?sheets\s*>"#,
                options: .regularExpression
            ) {
                workbookXML.insert(contentsOf: block, at: closingSheets.upperBound)
            } else {
                throw ExcelWorkbookDocumentError.cannotSave
            }
        }
        replacements["xl/workbook.xml"] = Data(workbookXML.utf8)
    }

    private static func workbookCacheExists(
        cacheID: Int,
        relationshipID: String,
        in source: String
    ) -> Bool {
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?pivotCache\b[^>]*/\s*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        return regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).contains { match in
            guard let range = Range(match.range, in: source) else {
                return false
            }
            let element = String(source[range])
            return attribute("cacheId", in: element) == String(cacheID)
                || attribute("id", in: element) == relationshipID
        }
    }

    private static func ensureContentTypes(
        pivotPartPath: String,
        cachePartPath: String,
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
        if let selfClosing = source.range(
            of: #"<(?:[A-Za-z_][\w.-]*:)?Types\b([^>]*)/\s*>"#,
            options: .regularExpression
        ) {
            let opening = String(source[selfClosing]).replacingOccurrences(
                of: #"/\s*>$"#,
                with: ">",
                options: .regularExpression
            )
            source.replaceSubrange(
                selfClosing,
                with: opening + "</Types>"
            )
        }
        let overrides = [
            (
                "/" + pivotPartPath,
                "application/vnd.openxmlformats-officedocument.spreadsheetml.pivotTable+xml"
            ),
            (
                "/" + cachePartPath,
                "application/vnd.openxmlformats-officedocument.spreadsheetml.pivotCacheDefinition+xml"
            ),
        ]
        for (partName, contentType) in overrides where !source.contains(
            "PartName=\"" + partName + "\""
        ) {
            let element = "<Override PartName=\""
                + escapeAttribute(partName) + "\" ContentType=\""
                + escapeAttribute(contentType) + "\"/>"
            guard let closing = source.range(
                of: #"</(?:[A-Za-z_][\w.-]*:)?Types\s*>"#,
                options: .regularExpression
            ) else {
                throw ExcelWorkbookDocumentError.cannotSave
            }
            source.insert(contentsOf: element, at: closing.lowerBound)
        }
        replacements[path] = Data(source.utf8)
    }

    private static let relationshipNamespace =
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    private static let emptyRelationshipsXML =
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"></Relationships>
        """

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

    private static func relationshipsPath(for partPath: String) -> String {
        let components = partPath.split(separator: "/")
        let filename = components.last.map(String.init) ?? partPath
        let directory = components.dropLast().joined(separator: "/")
        return directory + "/_rels/" + filename + ".rels"
    }

    private static func insertingRelationship(
        id: String,
        type: String,
        target: String,
        into source: String
    ) -> String {
        if relationshipHasID(id, in: source) {
            return source
        }
        var result = source
        if let selfClosing = result.range(
            of: #"<(?:[A-Za-z_][\w.-]*:)?Relationships\b([^>]*)/\s*>"#,
            options: .regularExpression
        ) {
            let opening = String(result[selfClosing]).replacingOccurrences(
                of: #"/\s*>$"#,
                with: ">",
                options: .regularExpression
            )
            result.replaceSubrange(
                selfClosing,
                with: opening + "</Relationships>"
            )
        }
        let element = "<Relationship Id=\"" + escapeAttribute(id)
            + "\" Type=\"" + escapeAttribute(type) + "\" Target=\""
            + escapeAttribute(target) + "\"/>"
        if let closing = result.range(
            of: #"</(?:[A-Za-z_][\w.-]*:)?Relationships\s*>"#,
            options: .regularExpression
        ) {
            result.insert(contentsOf: element, at: closing.lowerBound)
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
            guard let sourceRange = Range(match.range, in: source) else {
                continue
            }
            let element = String(source[sourceRange])
            guard relationshipHasID(id, in: element),
                  let resultRange = Range(match.range, in: result) else {
                continue
            }
            result.removeSubrange(resultRange)
        }
        return result
    }

    private static func relationshipHasID(
        _ identifier: String,
        in source: String
    ) -> Bool {
        attribute("Id", in: source) == identifier
            || attribute("id", in: source) == identifier
    }

    private static func replacingRootAttribute(
        _ name: String,
        with value: String,
        root: String,
        in source: String
    ) -> String {
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?"#
            + NSRegularExpression.escapedPattern(for: root)
            + #"\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: source,
                range: NSRange(source.startIndex..., in: source)
              ),
              let range = Range(match.range, in: source) else {
            return source
        }
        let opening = String(source[range])
        let attributePattern = #"\b"#
            + NSRegularExpression.escapedPattern(for: name)
            + #"\s*=\s*([\"']).*?\1"#
        let replacement = name + "=\"" + escapeAttribute(value) + "\""
        let updatedOpening: String
        if opening.range(of: attributePattern, options: .regularExpression)
            != nil {
            updatedOpening = opening.replacingOccurrences(
                of: attributePattern,
                with: replacement,
                options: .regularExpression
            )
        } else {
            updatedOpening = opening.replacingOccurrences(
                of: ">",
                with: " " + replacement + ">",
                options: .backwards
            )
        }
        var result = source
        result.replaceSubrange(range, with: updatedOpening)
        return result
    }

    private static func attribute(
        _ name: String,
        in source: String
    ) -> String? {
        let pattern = #"(?:^|\s)(?:[A-Za-z_][\w.-]*:)?"#
            + NSRegularExpression.escapedPattern(for: name)
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

    private static func relativeTarget(from source: String, to target: String)
        -> String {
        var sourceComponents = source.split(separator: "/").map(String.init)
        _ = sourceComponents.popLast()
        let targetComponents = target.split(separator: "/").map(String.init)
        var shared = 0
        while shared < sourceComponents.count,
              shared < targetComponents.count,
              sourceComponents[shared] == targetComponents[shared] {
            shared += 1
        }
        var components = Array(
            repeating: "..",
            count: sourceComponents.count - shared
        )
        components.append(contentsOf: targetComponents.dropFirst(shared))
        return components.joined(separator: "/")
    }

    private static func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
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
