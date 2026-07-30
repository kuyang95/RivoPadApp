import Foundation
import ZIPFoundation

nonisolated enum XLSXTextExtractor {
    static let maximumWorkbookBytes =
        20 * 1_024 * 1_024
    static let maximumArchiveEntries = 4_096
    static let maximumExpandedBytes =
        64 * 1_024 * 1_024
    static let maximumEntryBytes =
        32 * 1_024 * 1_024
    static let maximumSheets = 64
    static let maximumRowsPerSheet = 20_000
    static let maximumCellsPerSheet = 100_000
    static let maximumOutputBytes =
        1_024 * 1_024

    static func extract(
        from data: Data
    ) throws -> String {
        guard data.count <= maximumWorkbookBytes
        else {
            throw ChatAttachmentError
                .fileTooLarge(
                    maximumMegabytes:
                        maximumWorkbookBytes
                        / 1_024
                        / 1_024
                )
        }
        if data.starts(
            with: [
                0xD0, 0xCF, 0x11, 0xE0,
                0xA1, 0xB1, 0x1A, 0xE1,
            ]
        ) {
            throw ChatAttachmentError
                .encryptedSpreadsheet
        }

        let reader = try XLSXArchiveReader(
            data: data,
            maximumEntries:
                maximumArchiveEntries,
            maximumExpandedBytes:
                maximumExpandedBytes,
            maximumEntryBytes:
                maximumEntryBytes
        )
        let workbookData = try reader.data(
            at: "xl/workbook.xml"
        )
        let relationshipData = try reader.data(
            at:
                "xl/_rels/workbook.xml.rels"
        )
        let sheets = try XLSXWorkbookXML
            .parse(workbookData)
        guard !sheets.isEmpty else {
            throw ChatAttachmentError
                .invalidSpreadsheet
        }
        guard sheets.count <= maximumSheets
        else {
            throw ChatAttachmentError
                .spreadsheetLimitExceeded
        }

        let relationships =
            try XLSXRelationshipXML
            .parse(relationshipData)
        let sharedStrings: [String]
        if reader.contains(
            "xl/sharedStrings.xml"
        ) {
            sharedStrings =
                try XLSXSharedStringsXML
                .parse(
                    reader.data(
                        at:
                            "xl/sharedStrings.xml"
                    ),
                    maximumStrings:
                        maximumCellsPerSheet
                )
        } else {
            sharedStrings = []
        }

        var extractedSheets: [
            XLSXExtractedSheet
        ] = []
        var remainingOutputBytes =
            maximumOutputBytes
        var didTruncate = false

        for sheet in sheets {
            guard remainingOutputBytes > 0
            else {
                didTruncate = true
                break
            }
            guard let target =
                    relationships[
                        sheet.relationshipID
                    ],
                  let path =
                    normalizedWorksheetPath(
                        target
                    ),
                  reader.contains(path)
            else {
                continue
            }

            let result =
                try XLSXWorksheetXML.parse(
                    reader.data(at: path),
                    sharedStrings:
                        sharedStrings,
                    maximumRows:
                        maximumRowsPerSheet,
                    maximumCells:
                        maximumCellsPerSheet,
                    maximumOutputBytes:
                        remainingOutputBytes
                )
            remainingOutputBytes -=
                result.text.utf8.count
            didTruncate =
                didTruncate
                || result.didTruncate
            extractedSheets.append(
                XLSXExtractedSheet(
                    name: sheet.name,
                    text: result.text
                )
            )
        }

        let nonemptySheets =
            extractedSheets.filter {
                !$0.text.trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                ).isEmpty
            }
        guard !nonemptySheets.isEmpty else {
            throw ChatAttachmentError
                .documentHasNoText
        }

        let includesSheetNames =
            sheets.count > 1
        var text = nonemptySheets.map {
            sheet in
            if includesSheetNames {
                return "[\(sheet.name)]\n"
                    + sheet.text
            }
            return sheet.text
        }
        .joined(separator: "\n")

        if didTruncate
            || nonemptySheets.count
                < sheets.count {
            text += AppLocalization.string(
                "\n\n[스프레드시트 내용 일부 생략]"
            )
        }
        return text
    }

    private static func
        normalizedWorksheetPath(
            _ rawTarget: String
        ) -> String?
    {
        let decoded =
            rawTarget.removingPercentEncoding
            ?? rawTarget
        let candidate: String
        if decoded.hasPrefix("/") {
            candidate = String(
                decoded.dropFirst()
            )
        } else if decoded.hasPrefix("xl/") {
            candidate = decoded
        } else {
            candidate = "xl/" + decoded
        }

        var components: [Substring] = []
        for component in candidate.split(
            separator: "/",
            omittingEmptySubsequences: true
        ) {
            switch component {
            case ".":
                continue
            case "..":
                guard !components.isEmpty
                else {
                    return nil
                }
                components.removeLast()
            default:
                components.append(component)
            }
        }
        let normalized = components
            .joined(separator: "/")
        guard normalized.hasPrefix(
            "xl/worksheets/"
        ),
        normalized.hasSuffix(".xml")
        else {
            return nil
        }
        return normalized
    }
}

private nonisolated struct XLSXExtractedSheet {
    let name: String
    let text: String
}

private nonisolated final class
    XLSXArchiveReader
{
    private let archive: Archive
    private let entries: [String: Entry]
    private let maximumEntryBytes: Int

    init(
        data: Data,
        maximumEntries: Int,
        maximumExpandedBytes: Int,
        maximumEntryBytes: Int
    ) throws {
        do {
            archive = try Archive(
                data: data,
                accessMode: .read
            )
        } catch {
            throw ChatAttachmentError
                .invalidSpreadsheet
        }
        self.maximumEntryBytes =
            maximumEntryBytes

        var mapped: [String: Entry] = [:]
        var entryCount = 0
        var expandedBytes: UInt64 = 0
        for entry in archive {
            entryCount += 1
            guard entryCount <= maximumEntries,
                  entry.type != .symlink
            else {
                throw ChatAttachmentError
                    .spreadsheetLimitExceeded
            }
            expandedBytes +=
                entry.uncompressedSize
            guard expandedBytes
                    <= UInt64(
                        maximumExpandedBytes
                    ),
                  entry.uncompressedSize
                    <= UInt64(
                        maximumEntryBytes
                    )
            else {
                throw ChatAttachmentError
                    .spreadsheetLimitExceeded
            }
            guard entry.type == .file else {
                continue
            }
            let normalized = entry.path
                .replacingOccurrences(
                    of: "\\",
                    with: "/"
                )
            guard !normalized.hasPrefix("/"),
                  !normalized
                    .split(separator: "/")
                    .contains("..")
            else {
                throw ChatAttachmentError
                    .invalidSpreadsheet
            }
            if mapped[normalized] == nil {
                mapped[normalized] = entry
            }
        }
        entries = mapped
    }

    func contains(
        _ path: String
    ) -> Bool {
        entries[path] != nil
    }

    func data(
        at path: String
    ) throws -> Data {
        guard let entry = entries[path],
              entry.type == .file,
              entry.uncompressedSize
                <= UInt64(maximumEntryBytes)
        else {
            throw ChatAttachmentError
                .invalidSpreadsheet
        }
        var result = Data()
        result.reserveCapacity(
            Int(entry.uncompressedSize)
        )
        do {
            _ = try archive.extract(
                entry
            ) { chunk in
                guard result.count
                        + chunk.count
                        <= maximumEntryBytes
                else {
                    throw ChatAttachmentError
                        .spreadsheetLimitExceeded
                }
                result.append(chunk)
            }
        } catch let error
            as ChatAttachmentError {
            throw error
        } catch {
            throw ChatAttachmentError
                .invalidSpreadsheet
        }
        return result
    }
}

private nonisolated struct XLSXSheetInfo {
    let name: String
    let relationshipID: String
}

private nonisolated enum XLSXWorkbookXML {
    static func parse(
        _ data: Data
    ) throws -> [XLSXSheetInfo] {
        let delegate =
            XLSXWorkbookParserDelegate()
        try parseXML(
            data,
            delegate: delegate
        )
        return delegate.sheets
    }
}

private nonisolated final class
    XLSXWorkbookParserDelegate:
        NSObject,
        XMLParserDelegate
{
    var sheets: [XLSXSheetInfo] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName:
            String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict:
            [String: String] = [:]
    ) {
        guard localXMLName(
            qName ?? elementName
        ) == "sheet",
        let rawName =
            attributeDict["name"],
        let relationshipID =
            attributeDict["r:id"]
            ?? attributeDict["id"]
        else {
            return
        }
        let name =
            rawName.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
        guard !name.isEmpty,
              !relationshipID.isEmpty else {
            return
        }
        sheets.append(
            XLSXSheetInfo(
                name: String(
                    name.prefix(120)
                ),
                relationshipID:
                    relationshipID
            )
        )
    }
}

private nonisolated enum
    XLSXRelationshipXML
{
    static func parse(
        _ data: Data
    ) throws -> [String: String] {
        let delegate =
            XLSXRelationshipParserDelegate()
        try parseXML(
            data,
            delegate: delegate
        )
        return delegate.relationships
    }
}

private nonisolated final class
    XLSXRelationshipParserDelegate:
        NSObject,
        XMLParserDelegate
{
    var relationships:
        [String: String] = [:]

    func parser(
        _ parser: XMLParser,
        didStartElement elementName:
            String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict:
            [String: String] = [:]
    ) {
        guard localXMLName(
            qName ?? elementName
        ) == "Relationship",
        let identifier =
            attributeDict["Id"],
        let target =
            attributeDict["Target"]
        else {
            return
        }
        let type =
            attributeDict["Type"] ?? ""
        guard type.isEmpty
                || type.hasSuffix(
                    "/worksheet"
                )
        else {
            return
        }
        relationships[identifier] =
            target
    }
}

private nonisolated enum
    XLSXSharedStringsXML
{
    static func parse(
        _ data: Data,
        maximumStrings: Int
    ) throws -> [String] {
        let delegate =
            XLSXSharedStringsParserDelegate(
                maximumStrings:
                    maximumStrings
            )
        try parseXML(
            data,
            delegate: delegate
        )
        guard !delegate.didExceedLimit
        else {
            throw ChatAttachmentError
                .spreadsheetLimitExceeded
        }
        return delegate.strings
    }
}

private nonisolated final class
    XLSXSharedStringsParserDelegate:
        NSObject,
        XMLParserDelegate
{
    let maximumStrings: Int
    var strings: [String] = []
    var didExceedLimit = false

    private var isInsideString = false
    private var isInsideText = false
    private var current = ""

    init(maximumStrings: Int) {
        self.maximumStrings =
            maximumStrings
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName:
            String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict:
            [String: String] = [:]
    ) {
        switch localXMLName(
            qName ?? elementName
        ) {
        case "si":
            isInsideString = true
            current = ""
        case "t":
            isInsideText = isInsideString
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        guard isInsideString,
              isInsideText else {
            return
        }
        current += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName:
            String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch localXMLName(
            qName ?? elementName
        ) {
        case "t":
            isInsideText = false
        case "si":
            isInsideString = false
            guard strings.count
                    < maximumStrings
            else {
                didExceedLimit = true
                return
            }
            strings.append(current)
        default:
            break
        }
    }
}

private nonisolated struct
    XLSXWorksheetParseResult
{
    let text: String
    let didTruncate: Bool
}

private nonisolated enum XLSXWorksheetXML {
    static func parse(
        _ data: Data,
        sharedStrings: [String],
        maximumRows: Int,
        maximumCells: Int,
        maximumOutputBytes: Int
    ) throws -> XLSXWorksheetParseResult {
        let delegate =
            XLSXWorksheetParserDelegate(
                sharedStrings:
                    sharedStrings,
                maximumRows:
                    maximumRows,
                maximumCells:
                    maximumCells,
                maximumOutputBytes:
                    maximumOutputBytes
            )
        try parseXML(
            data,
            delegate: delegate
        )
        return XLSXWorksheetParseResult(
            text: delegate.lines
                .joined(separator: "\n"),
            didTruncate:
                delegate.didTruncate
        )
    }
}

private nonisolated final class
    XLSXWorksheetParserDelegate:
        NSObject,
        XMLParserDelegate
{
    let sharedStrings: [String]
    let maximumRows: Int
    let maximumCells: Int
    let maximumOutputBytes: Int

    var lines: [String] = []
    var didTruncate = false

    private var currentRow:
        [String] = []
    private var cellType: String?
    private var cellReference: String?
    private var rawValue = ""
    private var inlineValue = ""
    private var isInsideValue = false
    private var isInsideInlineString =
        false
    private var isInsideInlineText = false
    private var rowCount = 0
    private var cellCount = 0
    private var outputBytes = 0

    init(
        sharedStrings: [String],
        maximumRows: Int,
        maximumCells: Int,
        maximumOutputBytes: Int
    ) {
        self.sharedStrings =
            sharedStrings
        self.maximumRows = maximumRows
        self.maximumCells = maximumCells
        self.maximumOutputBytes =
            maximumOutputBytes
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName:
            String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict:
            [String: String] = [:]
    ) {
        switch localXMLName(
            qName ?? elementName
        ) {
        case "row":
            currentRow = []
        case "c":
            cellType =
                attributeDict["t"]
            cellReference =
                attributeDict["r"]
            rawValue = ""
            inlineValue = ""
        case "v":
            isInsideValue = true
        case "is":
            isInsideInlineString = true
        case "t":
            isInsideInlineText =
                isInsideInlineString
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        if isInsideValue {
            rawValue += string
        }
        if isInsideInlineText {
            inlineValue += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName:
            String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch localXMLName(
            qName ?? elementName
        ) {
        case "v":
            isInsideValue = false
        case "t":
            isInsideInlineText = false
        case "is":
            isInsideInlineString =
                false
        case "c":
            appendCurrentCell()
        case "row":
            appendCurrentRow()
        default:
            break
        }
    }

    private func appendCurrentCell() {
        defer {
            cellType = nil
            cellReference = nil
            rawValue = ""
            inlineValue = ""
        }
        guard !didReachStructuralLimit
        else {
            didTruncate = true
            return
        }
        cellCount += 1
        let value = displayValue()
        currentRow.append(
            normalizeCell(value)
        )
    }

    private func appendCurrentRow() {
        defer {
            currentRow = []
        }
        guard !currentRow.isEmpty else {
            return
        }
        guard rowCount < maximumRows,
              cellCount <= maximumCells
        else {
            didTruncate = true
            return
        }
        let line = currentRow
            .joined(separator: "\t")
            .trimmingCharacters(
                in: .whitespaces
            )
        guard !line.isEmpty else {
            return
        }
        let additionalBytes =
            line.utf8.count
            + (lines.isEmpty ? 0 : 1)
        guard outputBytes
                + additionalBytes
                <= maximumOutputBytes
        else {
            didTruncate = true
            return
        }
        lines.append(line)
        outputBytes += additionalBytes
        rowCount += 1
    }

    private var didReachStructuralLimit:
        Bool
    {
        rowCount >= maximumRows
            || cellCount
                >= maximumCells
    }

    private func displayValue() -> String {
        let trimmed = rawValue
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
        switch cellType {
        case "s":
            guard let index = Int(trimmed),
                  sharedStrings.indices
                    .contains(index)
            else {
                return ""
            }
            return sharedStrings[index]
        case "inlineStr":
            return inlineValue
        case "b":
            return trimmed == "1"
                ? "true"
                : "false"
        case "e":
            return ""
        default:
            return trimmed
        }
    }

    private func normalizeCell(
        _ value: String
    ) -> String {
        value
            .replacingOccurrences(
                of: "\r\n",
                with: " "
            )
            .replacingOccurrences(
                of: "\r",
                with: " "
            )
            .replacingOccurrences(
                of: "\n",
                with: " "
            )
            .replacingOccurrences(
                of: "\t",
                with: " "
            )
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
    }
}

private nonisolated func parseXML(
    _ data: Data,
    delegate: XMLParserDelegate
) throws {
    guard !containsASCII(
        "<!DOCTYPE",
        in: data
    ),
    !containsASCII(
        "<!ENTITY",
        in: data
    ) else {
        throw ChatAttachmentError
            .invalidSpreadsheet
    }
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = false
    parser.shouldReportNamespacePrefixes =
        true
    parser.shouldResolveExternalEntities =
        false
    parser.delegate = delegate
    guard parser.parse() else {
        throw ChatAttachmentError
            .invalidSpreadsheet
    }
}

private nonisolated func containsASCII(
    _ needle: String,
    in data: Data
) -> Bool {
    let pattern = Array(
        needle.uppercased().utf8
    )
    guard !pattern.isEmpty,
          data.count >= pattern.count
    else {
        return false
    }
    return data.withUnsafeBytes {
        rawBuffer in
        let bytes = rawBuffer.bindMemory(
            to: UInt8.self
        )
        for start in 0...(
            bytes.count - pattern.count
        ) {
            var matches = true
            for offset in pattern.indices {
                let byte =
                    bytes[start + offset]
                let upper =
                    byte >= 0x61
                        && byte <= 0x7A
                    ? byte - 0x20
                    : byte
                if upper != pattern[offset] {
                    matches = false
                    break
                }
            }
            if matches {
                return true
            }
        }
        return false
    }
}

private nonisolated func localXMLName(
    _ name: String
) -> String {
    name.split(separator: ":").last
        .map(String.init)
        ?? name
}
