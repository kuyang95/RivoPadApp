import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public nonisolated enum ExcelConditionalRuleKind:
    String,
    CaseIterable,
    Identifiable,
    Hashable,
    Sendable
{
    case greaterThan
    case greaterThanOrEqual
    case lessThan
    case lessThanOrEqual
    case equalTo
    case containsText

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .greaterThan: return DocumentEngineLocalization.string("보다 큼")
        case .greaterThanOrEqual: return DocumentEngineLocalization.string("이상")
        case .lessThan: return DocumentEngineLocalization.string("보다 작음")
        case .lessThanOrEqual: return DocumentEngineLocalization.string("이하")
        case .equalTo: return DocumentEngineLocalization.string("값과 같음")
        case .containsText: return DocumentEngineLocalization.string("텍스트 포함")
        }
    }

    public var requiresNumber: Bool {
        switch self {
        case .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual:
            return true
        case .equalTo, .containsText:
            return false
        }
    }
}

public nonisolated enum ExcelConditionalHighlight:
    String,
    CaseIterable,
    Identifiable,
    Hashable,
    Sendable
{
    case red
    case yellow
    case green

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .red: return DocumentEngineLocalization.string("연한 빨강")
        case .yellow: return DocumentEngineLocalization.string("연한 노랑")
        case .green: return DocumentEngineLocalization.string("연한 초록")
        }
    }

    public var style: ExcelDifferentialStyle {
        switch self {
        case .red:
            return ExcelDifferentialStyle(
                fillARGB: "FFFFC7CE",
                fontARGB: "FF9C0006",
                isBold: false
            )
        case .yellow:
            return ExcelDifferentialStyle(
                fillARGB: "FFFFEB9C",
                fontARGB: "FF9C6500",
                isBold: false
            )
        case .green:
            return ExcelDifferentialStyle(
                fillARGB: "FFC6EFCE",
                fontARGB: "FF006100",
                isBold: false
            )
        }
    }

    public static func matching(
        _ style: ExcelDifferentialStyle
    ) -> ExcelConditionalHighlight? {
        allCases.first { $0.style == style }
    }
}

public nonisolated struct ExcelDifferentialStyle: Hashable, Sendable {
    public let fillARGB: String?
    public let fontARGB: String?
    public let isBold: Bool

    public init(fillARGB: String? = nil, fontARGB: String? = nil, isBold: Bool) {
        self.fillARGB = fillARGB
        self.fontARGB = fontARGB
        self.isBold = isBold
    }
}

public nonisolated struct ExcelDifferentialStyleEdit: Hashable, Sendable {
    public let styleIndex: Int
    public let style: ExcelDifferentialStyle

    public init(styleIndex: Int, style: ExcelDifferentialStyle) {
        self.styleIndex = styleIndex
        self.style = style
    }
}

public nonisolated struct ExcelConditionalFormattingRule:
    Identifiable,
    Hashable,
    Sendable
{
    public let id: UUID
    public let kind: ExcelConditionalRuleKind
    public let comparisonValue: String
    public let differentialStyleIndex: Int
    public let priority: Int

    public init(
        id: UUID = UUID(),
        kind: ExcelConditionalRuleKind,
        comparisonValue: String,
        differentialStyleIndex: Int,
        priority: Int
    ) {
        self.id = id
        self.kind = kind
        self.comparisonValue = comparisonValue
        self.differentialStyleIndex = differentialStyleIndex
        self.priority = priority
    }

    public func matches(_ cell: ExcelCell?) -> Bool {
        guard let cell else {
            return false
        }
        let raw = cell.rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !raw.isEmpty else {
            return false
        }
        switch kind {
        case .greaterThan:
            guard let value = Double(raw),
                  let threshold = Double(comparisonValue) else {
                return false
            }
            return value > threshold
        case .greaterThanOrEqual:
            guard let value = Double(raw),
                  let threshold = Double(comparisonValue) else {
                return false
            }
            return value >= threshold
        case .lessThan:
            guard let value = Double(raw),
                  let threshold = Double(comparisonValue) else {
                return false
            }
            return value < threshold
        case .lessThanOrEqual:
            guard let value = Double(raw),
                  let threshold = Double(comparisonValue) else {
                return false
            }
            return value <= threshold
        case .equalTo:
            if let value = Double(raw),
               let threshold = Double(comparisonValue) {
                return value == threshold
            }
            return raw.caseInsensitiveCompare(comparisonValue) == .orderedSame
                || cell.displayValue.caseInsensitiveCompare(comparisonValue)
                    == .orderedSame
        case .containsText:
            return cell.displayValue.range(
                of: comparisonValue,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
    }
}

public nonisolated struct ExcelConditionalFormattingBlock:
    Identifiable,
    Hashable,
    Sendable
{
    public let id: UUID
    public var ranges: [ExcelCellRange]
    public var unparsedRangeReferences: [String]
    public var rules: [ExcelConditionalFormattingRule]
    public var originalXML: String?
    public let isEditable: Bool

    /// True when every rule in this block is the given condition, so
    /// re-applying that condition should replace it instead of stacking.
    public func isSameRule(
        kind: ExcelConditionalRuleKind,
        comparisonValue: String
    ) -> Bool {
        !rules.isEmpty && rules.allSatisfy { rule in
            rule.kind == kind
                && (kind.requiresNumber
                    ? Double(rule.comparisonValue) == Double(comparisonValue)
                    : rule.comparisonValue.caseInsensitiveCompare(
                        comparisonValue
                    ) == .orderedSame)
        }
    }

    public init(
        id: UUID = UUID(),
        ranges: [ExcelCellRange],
        unparsedRangeReferences: [String] = [],
        rules: [ExcelConditionalFormattingRule],
        originalXML: String? = nil,
        isEditable: Bool = true
    ) {
        self.id = id
        self.ranges = ranges
        self.unparsedRangeReferences = unparsedRangeReferences
        self.rules = rules
        self.originalXML = originalXML
        self.isEditable = isEditable
    }

    public func contains(_ address: ExcelCellAddress) -> Bool {
        ranges.contains { $0.contains(address) }
    }

    public func removing(
        _ targets: [ExcelCellRange]
    ) -> ExcelConditionalFormattingBlock? {
        guard isEditable else {
            return self
        }
        var remaining = ranges
        for target in targets {
            remaining = remaining.flatMap { $0.subtracting(target) }
        }
        guard !remaining.isEmpty || !unparsedRangeReferences.isEmpty else {
            return nil
        }
        var copy = self
        copy.ranges = remaining
        copy.originalXML = nil
        return copy
    }
}

nonisolated extension ExcelWorksheet {
    public func matchingConditionalRule(
        at address: ExcelCellAddress
    ) -> ExcelConditionalFormattingRule? {
        let cell = cell(at: address)
        return conditionalFormatting
            .filter { $0.contains(address) }
            .flatMap(\.rules)
            .filter { $0.matches(cell) }
            .min { $0.priority < $1.priority }
    }
}

public nonisolated enum ExcelDifferentialStylesParser {
    public static func parse(_ data: Data) throws -> [ExcelDifferentialStyle] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse() else {
            throw ExcelWorkbookDocumentError.invalidWorkbook
        }
        return delegate.styles
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var styles = [ExcelDifferentialStyle]()

        private var isInsideDXFs = false
        private var isInsideDXF = false
        private var isInsideFont = false
        private var isInsideFill = false
        private var fillARGB: String?
        private var fontARGB: String?
        private var isBold = false

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = localName(qName ?? elementName)
            switch name {
            case "dxfs":
                isInsideDXFs = true
            case "dxf" where isInsideDXFs:
                isInsideDXF = true
                fillARGB = nil
                fontARGB = nil
                isBold = false
            case "font" where isInsideDXF:
                isInsideFont = true
            case "fill" where isInsideDXF:
                isInsideFill = true
            case "b" where isInsideFont:
                isBold = attributeDict["val"] != "0"
            case "color" where isInsideFont:
                fontARGB = attributeDict["rgb"]
            case "fgColor" where isInsideFill:
                fillARGB = attributeDict["rgb"]
            default:
                break
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let name = localName(qName ?? elementName)
            switch name {
            case "font":
                isInsideFont = false
            case "fill":
                isInsideFill = false
            case "dxf" where isInsideDXF:
                styles.append(
                    ExcelDifferentialStyle(
                        fillARGB: fillARGB,
                        fontARGB: fontARGB,
                        isBold: isBold
                    )
                )
                isInsideDXF = false
            case "dxfs":
                isInsideDXFs = false
            default:
                break
            }
        }

        private func localName(_ name: String) -> String {
            name.split(separator: ":").last.map(String.init) ?? name
        }
    }
}

public nonisolated enum ExcelDifferentialStylesXMLWriter {
    public static func applying(
        _ edits: [ExcelDifferentialStyleEdit],
        to source: String
    ) throws -> String {
        guard !edits.isEmpty else {
            return source
        }
        let prefix = namespacePrefix(in: source)
        let escapedPrefix = NSRegularExpression.escapedPattern(for: prefix)
        let containerPattern = "(<" + escapedPrefix
            + #"dxfs\b[^>]*>)([\s\S]*?)(</"#
            + escapedPrefix + #"dxfs\s*>)"#
        let containerRegex = try NSRegularExpression(
            pattern: containerPattern
        )
        let fullRange = NSRange(source.startIndex..., in: source)
        let serialized = edits.sorted { $0.styleIndex < $1.styleIndex }
            .map { serialize($0.style, prefix: prefix) }
            .joined()

        if let match = containerRegex.firstMatch(in: source, range: fullRange),
           let elementRange = Range(match.range(at: 0), in: source),
           let openingRange = Range(match.range(at: 1), in: source),
           let contentRange = Range(match.range(at: 2), in: source),
           let closingRange = Range(match.range(at: 3), in: source) {
            let content = String(source[contentRange])
            let dxfPattern = "<" + escapedPrefix
                + #"dxf\b[^>]*(?:/>|>[\s\S]*?</"#
                + escapedPrefix + #"dxf\s*>)"#
            let count = try NSRegularExpression(pattern: dxfPattern)
                .numberOfMatches(
                    in: content,
                    range: NSRange(content.startIndex..., in: content)
                )
            try validateIndices(edits, originalCount: count)
            let opening = replaceCount(
                String(source[openingRange]),
                count + edits.count
            )
            var result = source
            result.replaceSubrange(
                elementRange,
                with: opening
                    + content
                    + serialized
                    + String(source[closingRange])
            )
            return result
        }

        try validateIndices(edits, originalCount: 0)
        let container = "<\(prefix)dxfs count=\"\(edits.count)\">"
            + serialized
            + "</\(prefix)dxfs>"
        let selfClosingPattern = "<" + escapedPrefix
            + #"dxfs\b[^>]*/\s*>"#
        if let range = source.range(
            of: selfClosingPattern,
            options: .regularExpression
        ) {
            var result = source
            result.replaceSubrange(range, with: container)
            return result
        }
        let insertionPattern = "<" + escapedPrefix
            + #"(?:tableStyles|colors|extLst)\b"#
        if let range = source.range(
            of: insertionPattern,
            options: .regularExpression
        ) {
            var result = source
            result.insert(contentsOf: container, at: range.lowerBound)
            return result
        }
        let closingPattern = "</" + escapedPrefix + #"styleSheet\s*>"#
        guard let range = source.range(
            of: closingPattern,
            options: .regularExpression
        ) else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        var result = source
        result.insert(contentsOf: container, at: range.lowerBound)
        return result
    }

    private static func validateIndices(
        _ edits: [ExcelDifferentialStyleEdit],
        originalCount: Int
    ) throws {
        for (offset, edit) in edits.sorted(by: {
            $0.styleIndex < $1.styleIndex
        }).enumerated() where edit.styleIndex != originalCount + offset {
            throw ExcelWorkbookDocumentError.cannotSave
        }
    }

    private static func serialize(
        _ style: ExcelDifferentialStyle,
        prefix: String
    ) -> String {
        var content = ""
        if style.fontARGB != nil || style.isBold {
            content += "<\(prefix)font>"
            if style.isBold {
                content += "<\(prefix)b/>"
            }
            if let fontARGB = style.fontARGB {
                content += "<\(prefix)color rgb=\""
                    + escapeAttribute(fontARGB)
                    + "\"/>"
            }
            content += "</\(prefix)font>"
        }
        if let fillARGB = style.fillARGB {
            content += "<\(prefix)fill><\(prefix)patternFill patternType=\"solid\">"
                + "<\(prefix)fgColor rgb=\""
                + escapeAttribute(fillARGB)
                + "\"/><\(prefix)bgColor indexed=\"64\"/>"
                + "</\(prefix)patternFill></\(prefix)fill>"
        }
        return "<\(prefix)dxf>" + content + "</\(prefix)dxf>"
    }

    private static func replaceCount(_ opening: String, _ count: Int) -> String {
        if opening.range(
            of: #"\bcount\s*=\s*[\"'][^\"']*[\"']"#,
            options: .regularExpression
        ) != nil {
            return opening.replacingOccurrences(
                of: #"\bcount\s*=\s*[\"'][^\"']*[\"']"#,
                with: "count=\"\(count)\"",
                options: .regularExpression
            )
        }
        guard let end = opening.lastIndex(of: ">") else {
            return opening
        }
        var result = opening
        result.insert(contentsOf: " count=\"\(count)\"", at: end)
        return result
    }

    private static func namespacePrefix(in source: String) -> String {
        let pattern = #"<([A-Za-z_][\w.-]*:)?styleSheet\b"#
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

    private static func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

public nonisolated enum ExcelConditionalFormattingXMLParser {
    public static func parse(_ source: String) throws
        -> [ExcelConditionalFormattingBlock] {
        let prefix = worksheetPrefix(in: source)
        let escapedPrefix = NSRegularExpression.escapedPattern(for: prefix)
        let pattern = "<" + escapedPrefix
            + #"conditionalFormatting\b[^>]*>[\s\S]*?</"#
            + escapedPrefix + #"conditionalFormatting\s*>"#
        let regex = try NSRegularExpression(pattern: pattern)
        return regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).compactMap { match in
            guard let range = Range(match.range, in: source) else {
                return nil
            }
            return parseBlock(String(source[range]), prefix: prefix)
        }
    }

    private static func parseBlock(
        _ xml: String,
        prefix: String
    ) -> ExcelConditionalFormattingBlock? {
        guard let openingEnd = xml.firstIndex(of: ">") else {
            return nil
        }
        let opening = String(xml[...openingEnd])
        let references = (attribute("sqref", in: opening) ?? "")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        let ranges = references.compactMap(ExcelCellRange.init)
        let unparsed = references.filter { ExcelCellRange($0) == nil }

        let escapedPrefix = NSRegularExpression.escapedPattern(for: prefix)
        let rulePattern = "<" + escapedPrefix
            + #"cfRule\b[^>]*(?:/>|>[\s\S]*?</"#
            + escapedPrefix + #"cfRule\s*>)"#
        guard let ruleRegex = try? NSRegularExpression(pattern: rulePattern) else {
            return nil
        }
        let ruleXMLs = ruleRegex.matches(
            in: xml,
            range: NSRange(xml.startIndex..., in: xml)
        ).compactMap { match -> String? in
            Range(match.range, in: xml).map { String(xml[$0]) }
        }
        let parsedRules = ruleXMLs.compactMap(parseRule)
        return ExcelConditionalFormattingBlock(
            ranges: ranges,
            unparsedRangeReferences: unparsed,
            rules: parsedRules,
            originalXML: xml,
            isEditable: ruleXMLs.count == 1 && parsedRules.count == 1
        )
    }

    private static func parseRule(
        _ xml: String
    ) -> ExcelConditionalFormattingRule? {
        guard let openingEnd = xml.firstIndex(of: ">") else {
            return nil
        }
        let opening = String(xml[...openingEnd])
        let type = attribute("type", in: opening)
        let operatorValue = attribute("operator", in: opening)
        let kind: ExcelConditionalRuleKind
        if type == "containsText" {
            kind = .containsText
        } else if type == "cellIs" {
            switch operatorValue {
            case "greaterThan": kind = .greaterThan
            case "greaterThanOrEqual": kind = .greaterThanOrEqual
            case "lessThan": kind = .lessThan
            case "lessThanOrEqual": kind = .lessThanOrEqual
            case "equal": kind = .equalTo
            default: return nil
            }
        } else {
            return nil
        }
        guard let dxfID = Int(attribute("dxfId", in: opening) ?? ""),
              let priority = Int(attribute("priority", in: opening) ?? "")
        else {
            return nil
        }
        let comparison: String
        if kind == .containsText,
           let text = attribute("text", in: opening) {
            comparison = text
        } else {
            guard let formula = firstFormula(in: xml) else {
                return nil
            }
            comparison = normalizedFormulaValue(formula)
        }
        return ExcelConditionalFormattingRule(
            kind: kind,
            comparisonValue: comparison,
            differentialStyleIndex: dxfID,
            priority: priority
        )
    }

    private static func firstFormula(in xml: String) -> String? {
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?formula\b[^>]*>([\s\S]*?)</(?:[A-Za-z_][\w.-]*:)?formula\s*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: xml,
                  range: NSRange(xml.startIndex..., in: xml)
              ),
              let range = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        return unescape(String(xml[range]))
    }

    private static func normalizedFormulaValue(_ formula: String) -> String {
        var value = formula.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("=") {
            value.removeFirst()
        }
        if value.count >= 2,
           value.first == "\"",
           value.last == "\"" {
            value = String(value.dropFirst().dropLast())
                .replacingOccurrences(of: "\"\"", with: "\"")
        }
        return value
    }

    private static func attribute(
        _ name: String,
        in opening: String
    ) -> String? {
        let pattern = "(?:^|\\s)" + NSRegularExpression.escapedPattern(
            for: name
        ) + #"\s*=\s*([\"'])(.*?)\1"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: opening,
                  range: NSRange(opening.startIndex..., in: opening)
              ),
              let range = Range(match.range(at: 2), in: opening) else {
            return nil
        }
        return unescape(String(opening[range]))
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

    private static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

public nonisolated enum ExcelConditionalFormattingXMLWriter {
    public static func applying(
        _ blocks: [ExcelConditionalFormattingBlock],
        to source: String
    ) throws -> String {
        let prefix = worksheetPrefix(in: source)
        let escapedPrefix = NSRegularExpression.escapedPattern(for: prefix)
        let pattern = "<" + escapedPrefix
            + #"conditionalFormatting\b[^>]*>[\s\S]*?</"#
            + escapedPrefix + #"conditionalFormatting\s*>"#
        let regex = try NSRegularExpression(pattern: pattern)
        var result = regex.stringByReplacingMatches(
            in: source,
            range: NSRange(source.startIndex..., in: source),
            withTemplate: ""
        )
        guard !blocks.isEmpty else {
            return result
        }
        let xml = blocks.map {
            $0.originalXML ?? serialize($0, prefix: prefix)
        }.joined()
        let insertionPattern = "<" + escapedPrefix
            + #"(?:dataValidations|hyperlinks|printOptions|pageMargins|pageSetup|headerFooter|drawing|legacyDrawing|legacyDrawingHF|picture|oleObjects|controls|webPublishItems|tableParts|extLst)\b"#
        if let range = result.range(
            of: insertionPattern,
            options: .regularExpression
        ) {
            result.insert(contentsOf: xml, at: range.lowerBound)
            return result
        }
        let closingPattern = "</" + escapedPrefix + #"worksheet\s*>"#
        guard let range = result.range(
            of: closingPattern,
            options: .regularExpression
        ) else {
            throw ExcelWorkbookDocumentError.invalidWorkbook
        }
        result.insert(contentsOf: xml, at: range.lowerBound)
        return result
    }

    private static func serialize(
        _ block: ExcelConditionalFormattingBlock,
        prefix: String
    ) -> String {
        let sqref = (block.ranges.map(\.reference)
            + block.unparsedRangeReferences).joined(separator: " ")
        let rules = block.rules.map { rule in
            let type: String
            let operatorAttribute: String
            let textAttribute: String
            let formula: String
            switch rule.kind {
            case .greaterThan:
                type = "cellIs"
                operatorAttribute = " operator=\"greaterThan\""
                textAttribute = ""
                formula = rule.comparisonValue
            case .greaterThanOrEqual:
                type = "cellIs"
                operatorAttribute = " operator=\"greaterThanOrEqual\""
                textAttribute = ""
                formula = rule.comparisonValue
            case .lessThan:
                type = "cellIs"
                operatorAttribute = " operator=\"lessThan\""
                textAttribute = ""
                formula = rule.comparisonValue
            case .lessThanOrEqual:
                type = "cellIs"
                operatorAttribute = " operator=\"lessThanOrEqual\""
                textAttribute = ""
                formula = rule.comparisonValue
            case .equalTo:
                type = "cellIs"
                operatorAttribute = " operator=\"equal\""
                textAttribute = ""
                if Double(rule.comparisonValue) != nil {
                    formula = rule.comparisonValue
                } else {
                    formula = "\""
                        + rule.comparisonValue.replacingOccurrences(
                            of: "\"",
                            with: "\"\""
                        )
                        + "\""
                }
            case .containsText:
                type = "containsText"
                operatorAttribute = " operator=\"containsText\""
                textAttribute = " text=\""
                    + escapeAttribute(rule.comparisonValue)
                    + "\""
                let topLeft = block.ranges.first?.start.reference ?? "A1"
                let searchText = rule.comparisonValue.replacingOccurrences(
                    of: "\"",
                    with: "\"\""
                )
                formula = "NOT(ISERROR(SEARCH(\""
                    + searchText + "\"," + topLeft + ")))"
            }
            return "<\(prefix)cfRule type=\"\(type)\""
                + " dxfId=\"\(rule.differentialStyleIndex)\""
                + " priority=\"\(rule.priority)\""
                + operatorAttribute + textAttribute + ">"
                + "<\(prefix)formula>" + escapeText(formula)
                + "</\(prefix)formula></\(prefix)cfRule>"
        }.joined()
        return "<\(prefix)conditionalFormatting sqref=\""
            + escapeAttribute(sqref) + "\">" + rules
            + "</\(prefix)conditionalFormatting>"
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
