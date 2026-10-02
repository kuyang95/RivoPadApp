import Foundation

public nonisolated enum ExcelNumberFormat:
    String,
    CaseIterable,
    Identifiable,
    Hashable,
    Sendable
{
    case general
    case text
    case integer
    case decimalOne
    case decimalTwo
    case date
    case time
    case percent
    case currencyWon

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return DocumentEngineLocalization.string("일반")
        case .text: return DocumentEngineLocalization.string("텍스트")
        case .integer: return DocumentEngineLocalization.string("정수")
        case .decimalOne: return DocumentEngineLocalization.string("소수 1자리")
        case .decimalTwo: return DocumentEngineLocalization.string("소수 2자리")
        case .date: return DocumentEngineLocalization.string("날짜")
        case .time: return DocumentEngineLocalization.string("시간")
        case .percent: return DocumentEngineLocalization.string("백분율")
        case .currencyWon: return DocumentEngineLocalization.string("통화(원)")
        }
    }

    public var example: String {
        switch self {
        case .general: return "1234.5"
        case .text: return "00123"
        case .integer: return "1,235"
        case .decimalOne: return "1,234.5"
        case .decimalTwo: return "1,234.50"
        case .date: return "2026-08-31"
        case .time: return "14:30"
        case .percent: return "25%"
        case .currencyWon: return "₩1,235"
        }
    }

    public var builtInNumberFormatID: Int? {
        switch self {
        case .general: return 0
        case .text: return 49
        case .integer: return 3
        case .decimalTwo: return 4
        case .time: return 20
        case .percent: return 9
        case .decimalOne, .date, .currencyWon: return nil
        }
    }

    public var formatCode: String? {
        switch self {
        case .general: return nil
        case .text: return "@"
        case .integer: return "#,##0"
        case .decimalOne: return "#,##0.0"
        case .decimalTwo: return "#,##0.00"
        case .date: return "yyyy-mm-dd"
        case .time: return "h:mm"
        case .percent: return "0%"
        case .currencyWon: return "[$₩-412]#,##0"
        }
    }

    public var displayNumberFormatID: Int {
        builtInNumberFormatID ?? (200 + Self.allCases.firstIndex(of: self)!)
    }

    public static func matching(_ style: ExcelCellStyle) -> ExcelNumberFormat? {
        if style.numberFormatID == 0,
           style.numberFormatCode == nil {
            return .general
        }
        if let match = allCases.first(where: {
            $0.builtInNumberFormatID == style.numberFormatID
                && $0.builtInNumberFormatID != nil
        }) {
            return match
        }
        let normalized = style.numberFormatCode?
            .lowercased()
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "\"", with: "")
        if normalized == "@" { return .text }
        if normalized?.contains("₩") == true { return .currencyWon }
        if normalized?.contains("%") == true { return .percent }
        if normalized?.contains("yy") == true
            || normalized?.contains("dd") == true {
            return .date
        }
        if normalized?.contains(":") == true { return .time }
        if normalized?.contains(".00") == true { return .decimalTwo }
        if normalized?.contains(".0") == true { return .decimalOne }
        if normalized?.contains("0") == true { return .integer }
        return nil
    }
}

public nonisolated struct ExcelStyleEdit: Hashable, Sendable {
    public let styleIndex: Int
    public let baseStyleIndex: Int?
    public let numberFormat: ExcelNumberFormat

    public init(styleIndex: Int, baseStyleIndex: Int? = nil, numberFormat: ExcelNumberFormat) {
        self.styleIndex = styleIndex
        self.baseStyleIndex = baseStyleIndex
        self.numberFormat = numberFormat
    }
}

public nonisolated enum ExcelStylesXMLWriter {
    private static let optionalPrefix =
        "(?:[A-Za-z_][A-Za-z0-9_.-]*:)?"

    public static func applying(
        _ edits: [ExcelStyleEdit],
        to source: String
    ) throws -> String {
        guard !edits.isEmpty else {
            return source
        }
        let prefix = namespacePrefix(in: source)
        let cellXfsPattern = "(<" + optionalPrefix
            + "cellXfs\\b[^>]*>)([\\s\\S]*?)(</"
            + optionalPrefix + "cellXfs\\s*>)"
        let cellXfsRegex = try NSRegularExpression(
            pattern: cellXfsPattern
        )
        let fullRange = NSRange(source.startIndex..., in: source)
        guard let cellXfsMatch = cellXfsRegex.firstMatch(
            in: source,
            range: fullRange
        ),
        cellXfsMatch.numberOfRanges > 3,
        let contentRange = Range(cellXfsMatch.range(at: 2), in: source)
        else {
            throw ExcelWorkbookDocumentError.cannotSave
        }

        let originalContent = String(source[contentRange])
        let xfPattern = "<" + optionalPrefix
            + "xf\\b[^>]*(?:/>|>[\\s\\S]*?</"
            + optionalPrefix + "xf\\s*>)"
        let xfRegex = try NSRegularExpression(pattern: xfPattern)
        let xfMatches = xfRegex.matches(
            in: originalContent,
            range: NSRange(originalContent.startIndex..., in: originalContent)
        )
        let originalXFs = xfMatches.compactMap {
            Range($0.range, in: originalContent).map {
                String(originalContent[$0])
            }
        }
        guard !originalXFs.isEmpty else {
            throw ExcelWorkbookDocumentError.cannotSave
        }

        var result = source
        let customFormats = edits
            .map(\.numberFormat)
            .filter { $0.builtInNumberFormatID == nil }
        let formatIDs = try ensureCustomNumberFormats(
            Set(customFormats),
            in: &result,
            namespacePrefix: prefix
        )

        var appended = ""
        let sortedEdits = edits.sorted { $0.styleIndex < $1.styleIndex }
        for (offset, edit) in sortedEdits.enumerated() {
            guard edit.styleIndex == originalXFs.count + offset else {
                throw ExcelWorkbookDocumentError.cannotSave
            }
            let baseIndex = edit.baseStyleIndex ?? 0
            guard originalXFs.indices.contains(baseIndex) else {
                throw ExcelWorkbookDocumentError.cannotSave
            }
            let numberFormatID = edit.numberFormat.builtInNumberFormatID
                ?? formatIDs[edit.numberFormat]
            guard let numberFormatID else {
                throw ExcelWorkbookDocumentError.cannotSave
            }
            appended += replacingNumberFormat(
                in: originalXFs[baseIndex],
                with: numberFormatID
            )
        }

        // Custom number formats may have changed the string indices, so find
        // cellXfs again before appending the cloned styles.
        let updatedFullRange = NSRange(result.startIndex..., in: result)
        guard let updatedMatch = cellXfsRegex.firstMatch(
            in: result,
            range: updatedFullRange
        ),
        updatedMatch.numberOfRanges > 3,
        let updatedElementRange = Range(updatedMatch.range(at: 0), in: result),
        let updatedOpeningRange = Range(updatedMatch.range(at: 1), in: result),
        let updatedContentRange = Range(updatedMatch.range(at: 2), in: result),
        let updatedClosingRange = Range(updatedMatch.range(at: 3), in: result)
        else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        let opening = replacingCount(
            in: String(result[updatedOpeningRange]),
            with: originalXFs.count + sortedEdits.count
        )
        let replacement = opening
            + String(result[updatedContentRange])
            + appended
            + String(result[updatedClosingRange])
        result.replaceSubrange(updatedElementRange, with: replacement)

        return result
    }

    private static func ensureCustomNumberFormats(
        _ formats: Set<ExcelNumberFormat>,
        in source: inout String,
        namespacePrefix: String
    ) throws -> [ExcelNumberFormat: Int] {
        guard !formats.isEmpty else {
            return [:]
        }
        let numFmtPattern = "<" + optionalPrefix
            + "numFmt\\b[^>]*\\bnumFmtId=\"([0-9]+)\"[^>]*"
            + "\\bformatCode=\"([^\"]*)\"[^>]*/>"
        let numFmtRegex = try NSRegularExpression(pattern: numFmtPattern)
        let matches = numFmtRegex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )
        var maximumID = 163
        var existingByCode = [String: Int]()
        for match in matches where match.numberOfRanges > 2 {
            guard let idRange = Range(match.range(at: 1), in: source),
                  let codeRange = Range(match.range(at: 2), in: source),
                  let identifier = Int(source[idRange]) else {
                continue
            }
            maximumID = max(maximumID, identifier)
            existingByCode[unescapeXMLAttribute(String(source[codeRange]))]
                = identifier
        }

        let existingCount = matches.count
        var addedCount = 0
        var identifiers = [ExcelNumberFormat: Int]()
        var newElements = ""
        for format in formats.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let code = format.formatCode else {
                continue
            }
            if let existing = existingByCode[code] {
                identifiers[format] = existing
                continue
            }
            maximumID += 1
            addedCount += 1
            identifiers[format] = maximumID
            existingByCode[code] = maximumID
            newElements += "<\(namespacePrefix)numFmt numFmtId=\""
                + String(maximumID)
                + "\" formatCode=\""
                + escapeXMLAttribute(code)
                + "\"/>"
        }
        guard !newElements.isEmpty else {
            return identifiers
        }

        let containerPattern = "(<" + optionalPrefix
            + "numFmts\\b[^>]*>)([\\s\\S]*?)(</"
            + optionalPrefix + "numFmts\\s*>)"
        let containerRegex = try NSRegularExpression(pattern: containerPattern)
        let fullRange = NSRange(source.startIndex..., in: source)
        if let match = containerRegex.firstMatch(in: source, range: fullRange),
           match.numberOfRanges > 3,
           let elementRange = Range(match.range(at: 0), in: source),
           let openingRange = Range(match.range(at: 1), in: source),
           let contentRange = Range(match.range(at: 2), in: source),
           let closingRange = Range(match.range(at: 3), in: source) {
            let opening = replacingCount(
                in: String(source[openingRange]),
                with: existingCount + addedCount
            )
            let replacement = opening
                + String(source[contentRange])
                + newElements
                + String(source[closingRange])
            source.replaceSubrange(elementRange, with: replacement)
            return identifiers
        }

        let fontsPattern = "<" + optionalPrefix + "fonts\\b"
        guard let fontsRange = source.range(
            of: fontsPattern,
            options: .regularExpression
        ) else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        let container = "<\(namespacePrefix)numFmts count=\""
            + String(addedCount)
            + "\">" + newElements
            + "</\(namespacePrefix)numFmts>"
        source.insert(contentsOf: container, at: fontsRange.lowerBound)
        return identifiers
    }

    private static func replacingNumberFormat(
        in xf: String,
        with identifier: Int
    ) -> String {
        var result = xf
        if result.range(
            of: #"\bnumFmtId\s*=\s*[\"'][^\"']*[\"']"#,
            options: .regularExpression
        ) != nil {
            result = result.replacingOccurrences(
                of: #"\bnumFmtId\s*=\s*[\"'][^\"']*[\"']"#,
                with: "numFmtId=\"\(identifier)\"",
                options: .regularExpression
            )
        } else if let insertion = result.firstIndex(of: " ") {
            result.insert(
                contentsOf: " numFmtId=\"\(identifier)\"",
                at: insertion
            )
        }
        if result.range(
            of: #"\bapplyNumberFormat\s*=\s*[\"'][^\"']*[\"']"#,
            options: .regularExpression
        ) != nil {
            result = result.replacingOccurrences(
                of: #"\bapplyNumberFormat\s*=\s*[\"'][^\"']*[\"']"#,
                with: "applyNumberFormat=\"1\"",
                options: .regularExpression
            )
        } else if let insertion = result.firstIndex(of: " ") {
            result.insert(
                contentsOf: " applyNumberFormat=\"1\"",
                at: insertion
            )
        }
        return result
    }

    private static func replacingCount(
        in openingElement: String,
        with count: Int
    ) -> String {
        if openingElement.range(
            of: #"\bcount\s*=\s*[\"'][^\"']*[\"']"#,
            options: .regularExpression
        ) != nil {
            return openingElement.replacingOccurrences(
                of: #"\bcount\s*=\s*[\"'][^\"']*[\"']"#,
                with: "count=\"\(count)\"",
                options: .regularExpression
            )
        }
        guard let close = openingElement.lastIndex(of: ">") else {
            return openingElement
        }
        var result = openingElement
        result.insert(contentsOf: " count=\"\(count)\"", at: close)
        return result
    }

    private static func namespacePrefix(in source: String) -> String {
        let pattern = "<([A-Za-z_][A-Za-z0-9_.-]*:)?styleSheet\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: source,
                  range: NSRange(source.startIndex..., in: source)
              ),
              match.numberOfRanges > 1,
              match.range(at: 1).location != NSNotFound,
              let range = Range(match.range(at: 1), in: source) else {
            return ""
        }
        return String(source[range])
    }

    private static func escapeXMLAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func unescapeXMLAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
