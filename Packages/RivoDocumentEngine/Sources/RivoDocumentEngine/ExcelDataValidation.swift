import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public nonisolated struct ExcelDataValidationAttribute: Hashable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public nonisolated struct ExcelDataValidationRule:
    Identifiable,
    Hashable,
    Sendable
{
    public let id: UUID
    public var ranges: [ExcelCellRange]
    public var unparsedRangeReferences: [String]
    public var attributes: [ExcelDataValidationAttribute]
    public var formula1: String?
    public var formula2: String?

    public init(
        id: UUID = UUID(),
        ranges: [ExcelCellRange],
        unparsedRangeReferences: [String] = [],
        attributes: [ExcelDataValidationAttribute],
        formula1: String? = nil,
        formula2: String? = nil
    ) {
        self.id = id
        self.ranges = ranges
        self.unparsedRangeReferences = unparsedRangeReferences
        self.attributes = attributes
        self.formula1 = formula1
        self.formula2 = formula2
    }

    public static func inlineList(
        ranges: [ExcelCellRange],
        values: [String],
        allowsBlank: Bool
    ) -> ExcelDataValidationRule {
        ExcelDataValidationRule(
            ranges: ranges,
            attributes: [
                ExcelDataValidationAttribute(name: "type", value: "list"),
                ExcelDataValidationAttribute(
                    name: "allowBlank",
                    value: allowsBlank ? "1" : "0"
                ),
                ExcelDataValidationAttribute(
                    name: "showErrorMessage",
                    value: "1"
                ),
                ExcelDataValidationAttribute(
                    name: "errorStyle",
                    value: "stop"
                ),
                ExcelDataValidationAttribute(
                    name: "errorTitle",
                    value: "목록에 없는 값"
                ),
                ExcelDataValidationAttribute(
                    name: "error",
                    value: "드롭다운 목록에서 값을 선택하세요."
                ),
                // In SpreadsheetML, true means the arrow is hidden.
                ExcelDataValidationAttribute(
                    name: "showDropDown",
                    value: "0"
                ),
            ],
            formula1: "\"" + values.joined(separator: ",") + "\""
        )
    }

    public var type: String? {
        attribute(named: "type")
    }

    public var allowsBlank: Bool {
        Self.booleanValue(attribute(named: "allowBlank"))
    }

    public var inlineListValues: [String]? {
        guard type == "list",
              let formula1,
              formula1.count >= 2,
              formula1.first == "\"",
              formula1.last == "\"" else {
            return nil
        }
        let body = String(formula1.dropFirst().dropLast())
            .replacingOccurrences(of: "\"\"", with: "\"")
        let separator: Character = body.contains(",") ? "," : ";"
        let values = body.split(
            separator: separator,
            omittingEmptySubsequences: false
        ).map(String.init)
        return values.isEmpty ? nil : values
    }

    public func contains(_ address: ExcelCellAddress) -> Bool {
        ranges.contains { $0.contains(address) }
    }

    public func removing(_ targets: [ExcelCellRange]) -> ExcelDataValidationRule? {
        var remaining = ranges
        for target in targets {
            remaining = remaining.flatMap { $0.subtracting(target) }
        }
        guard !remaining.isEmpty || !unparsedRangeReferences.isEmpty else {
            return nil
        }
        var copy = self
        copy.ranges = remaining
        return copy
    }

    private func attribute(named name: String) -> String? {
        attributes.first(where: {
            $0.name.split(separator: ":").last.map(String.init) == name
        })?.value
    }

    private static func booleanValue(_ value: String?) -> Bool {
        value == "1" || value?.caseInsensitiveCompare("true") == .orderedSame
    }
}

nonisolated extension ExcelCellRange {
    public func intersects(_ other: ExcelCellRange) -> Bool {
        start.row <= other.end.row
            && end.row >= other.start.row
            && start.column <= other.end.column
            && end.column >= other.start.column
    }

    public func subtracting(_ other: ExcelCellRange) -> [ExcelCellRange] {
        guard intersects(other) else {
            return [self]
        }
        let intersection = ExcelCellRange(
            start: ExcelCellAddress(
                row: max(start.row, other.start.row),
                column: max(start.column, other.start.column)
            ),
            end: ExcelCellAddress(
                row: min(end.row, other.end.row),
                column: min(end.column, other.end.column)
            )
        )
        var result = [ExcelCellRange]()
        if start.row < intersection.start.row {
            result.append(
                ExcelCellRange(
                    start: start,
                    end: ExcelCellAddress(
                        row: intersection.start.row - 1,
                        column: end.column
                    )
                )
            )
        }
        if intersection.end.row < end.row {
            result.append(
                ExcelCellRange(
                    start: ExcelCellAddress(
                        row: intersection.end.row + 1,
                        column: start.column
                    ),
                    end: end
                )
            )
        }
        if start.column < intersection.start.column {
            result.append(
                ExcelCellRange(
                    start: ExcelCellAddress(
                        row: intersection.start.row,
                        column: start.column
                    ),
                    end: ExcelCellAddress(
                        row: intersection.end.row,
                        column: intersection.start.column - 1
                    )
                )
            )
        }
        if intersection.end.column < end.column {
            result.append(
                ExcelCellRange(
                    start: ExcelCellAddress(
                        row: intersection.start.row,
                        column: intersection.end.column + 1
                    ),
                    end: ExcelCellAddress(
                        row: intersection.end.row,
                        column: end.column
                    )
                )
            )
        }
        return result
    }

    public static func verticalRanges(
        for addresses: [ExcelCellAddress]
    ) -> [ExcelCellRange] {
        let grouped = Dictionary(grouping: Set(addresses)) { $0.column }
        return grouped.keys.sorted().flatMap { column in
            let rows = grouped[column, default: []].map(\.row).sorted()
            guard var startRow = rows.first else {
                return [ExcelCellRange]()
            }
            var previousRow = startRow
            var ranges = [ExcelCellRange]()
            for row in rows.dropFirst() {
                if row == previousRow + 1 {
                    previousRow = row
                    continue
                }
                ranges.append(
                    ExcelCellRange(
                        start: ExcelCellAddress(row: startRow, column: column),
                        end: ExcelCellAddress(row: previousRow, column: column)
                    )
                )
                startRow = row
                previousRow = row
            }
            ranges.append(
                ExcelCellRange(
                    start: ExcelCellAddress(row: startRow, column: column),
                    end: ExcelCellAddress(row: previousRow, column: column)
                )
            )
            return ranges
        }
    }
}

public nonisolated enum ExcelDataValidationXMLParser {
    public static func parse(_ data: Data) throws -> [ExcelDataValidationRule] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse() else {
            throw ExcelWorkbookDocumentError.invalidWorkbook
        }
        return delegate.rules
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        private static let extendedValidationNamespace =
            "http://schemas.microsoft.com/office/spreadsheetml/2009/9/main"

        var rules = [ExcelDataValidationRule]()

        private var worksheetNamespace: String?
        private var currentRanges = [ExcelCellRange]()
        private var currentUnparsedRangeReferences = [String]()
        private var currentAttributes = [ExcelDataValidationAttribute]()
        private var currentFormula1: String?
        private var currentFormula2: String?
        private var currentFormulaName: String?
        private var currentFormulaText = ""
        private var currentRangeText = ""
        private var isReadingRangeText = false
        private var validationNamespace: String?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = localName(qName ?? elementName)
            if name == "worksheet" {
                worksheetNamespace = namespaceURI
                return
            }
            if name == "dataValidation",
               namespaceURI == worksheetNamespace
                    || namespaceURI == Self.extendedValidationNamespace {
                validationNamespace = namespaceURI
                let references = (attributeDict["sqref"] ?? "")
                    .split(whereSeparator: { $0.isWhitespace })
                    .map(String.init)
                currentRanges = references.compactMap(ExcelCellRange.init)
                currentUnparsedRangeReferences = references.filter {
                    ExcelCellRange($0) == nil
                }
                currentAttributes = attributeDict
                    .filter { localName($0.key) != "sqref" }
                    .map {
                        ExcelDataValidationAttribute(
                            name: $0.key,
                            value: $0.value
                        )
                    }
                    .sorted { $0.name < $1.name }
                currentFormula1 = nil
                currentFormula2 = nil
                currentRangeText = ""
                isReadingRangeText = false
                return
            }
            guard validationNamespace != nil else { return }
            if name == "sqref" {
                currentRangeText = ""
                isReadingRangeText = true
                return
            }
            guard name == "formula1" || name == "formula2" else { return }
            currentFormulaName = name
            currentFormulaText = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if currentFormulaName != nil {
                currentFormulaText += string
            }
            if isReadingRangeText {
                currentRangeText += string
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let name = localName(qName ?? elementName)
            if name == "sqref", isReadingRangeText {
                let references = currentRangeText
                    .split(whereSeparator: { $0.isWhitespace })
                    .map(String.init)
                currentRanges = references.compactMap(ExcelCellRange.init)
                currentUnparsedRangeReferences = references.filter {
                    ExcelCellRange($0) == nil
                }
                currentRangeText = ""
                isReadingRangeText = false
                return
            }
            if name == currentFormulaName {
                if name == "formula1" {
                    currentFormula1 = currentFormulaText
                } else {
                    currentFormula2 = currentFormulaText
                }
                currentFormulaName = nil
                currentFormulaText = ""
                return
            }
            guard name == "dataValidation",
                  namespaceURI == validationNamespace else {
                return
            }
            if !currentRanges.isEmpty
                || !currentUnparsedRangeReferences.isEmpty {
                rules.append(
                    ExcelDataValidationRule(
                        ranges: currentRanges,
                        unparsedRangeReferences:
                            currentUnparsedRangeReferences,
                        attributes: currentAttributes,
                        formula1: currentFormula1,
                        formula2: currentFormula2
                    )
                )
            }
            validationNamespace = nil
        }

        private func localName(_ name: String) -> String {
            name.split(separator: ":").last.map(String.init) ?? name
        }
    }
}

public nonisolated enum ExcelDataValidationXMLWriter {
    public static func applying(
        _ rules: [ExcelDataValidationRule],
        to source: String
    ) throws -> String {
        var result = removingExistingContainer(from: source)
        guard !rules.isEmpty else {
            return result
        }
        let prefix = worksheetPrefix(in: result)
        let qualified = { (name: String) in prefix + name }
        let items = rules.map { rule in
            let attributes = rule.attributes
                .filter { localName($0.name) != "sqref" }
                .map {
                    " \($0.name)=\"\(escapeAttribute($0.value))\""
                }
                .joined()
            let sqref = (
                rule.ranges.map(\.reference)
                    + rule.unparsedRangeReferences
            ).joined(separator: " ")
            var content = ""
            if let formula1 = rule.formula1 {
                content += "<\(qualified("formula1"))>"
                    + escapeText(formula1)
                    + "</\(qualified("formula1"))>"
            }
            if let formula2 = rule.formula2 {
                content += "<\(qualified("formula2"))>"
                    + escapeText(formula2)
                    + "</\(qualified("formula2"))>"
            }
            return "<\(qualified("dataValidation"))"
                + attributes
                + " sqref=\"\(escapeAttribute(sqref))\">"
                + content
                + "</\(qualified("dataValidation"))>"
        }.joined()
        let container = "<\(qualified("dataValidations")) count=\"\(rules.count)\">"
            + items
            + "</\(qualified("dataValidations"))>"

        let insertionPattern = #"<(?:[A-Za-z_][\w.-]*:)?(?:hyperlinks|printOptions|pageMargins|pageSetup|headerFooter|drawing|legacyDrawing|legacyDrawingHF|picture|oleObjects|controls|webPublishItems|tableParts|extLst)\b"#
        if let range = firstMatch(of: insertionPattern, in: result) {
            result.insert(contentsOf: container, at: range.lowerBound)
            return result
        }
        let closingPattern = #"</(?:[A-Za-z_][\w.-]*:)?worksheet\s*>"#
        guard let range = firstMatch(of: closingPattern, in: result) else {
            throw ExcelWorkbookDocumentError.invalidWorkbook
        }
        result.insert(contentsOf: container, at: range.lowerBound)
        return result
    }

    private static func removingExistingContainer(from source: String) -> String {
        let prefix = NSRegularExpression.escapedPattern(
            for: worksheetPrefix(in: source)
        )
        let paired = "<" + prefix
            + #"dataValidations\b[^>]*>[\s\S]*?</"#
            + prefix
            + #"dataValidations\s*>"#
        let selfClosing = "<" + prefix
            + #"dataValidations\b[^>]*/\s*>"#
        return replacingMatches(
            of: selfClosing,
            in: replacingMatches(of: paired, in: source)
        )
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

    private static func firstMatch(
        of pattern: String,
        in source: String
    ) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: source,
                  range: NSRange(source.startIndex..., in: source)
              ) else {
            return nil
        }
        return Range(match.range, in: source)
    }

    private static func replacingMatches(
        of pattern: String,
        in source: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return source
        }
        return regex.stringByReplacingMatches(
            in: source,
            range: NSRange(source.startIndex..., in: source),
            withTemplate: ""
        )
    }

    private static func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    private static func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ value: String) -> String {
        escapeText(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
