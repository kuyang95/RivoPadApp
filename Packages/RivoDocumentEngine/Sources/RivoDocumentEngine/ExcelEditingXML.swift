import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A small ordered XML tree. Untouched package parts are copied byte for byte.
public nonisolated final class ExcelEditingXML: NSObject, XMLParserDelegate {
    public final class Node {
        public var name: String
        public var attributes: [String: String]
        public var children: [Node]
        public var value: String
        public var localName: String { name.split(separator: ":").last.map(String.init) ?? name }
        public init(_ name: String, _ attributes: [String: String] = [:], children: [Node] = [], value: String = "") {
            self.name = name; self.attributes = attributes; self.children = children; self.value = value
        }
        public var text: String {
            get { name == "#text" ? value : children.map(\.text).joined() }
            set { children = [Node("#text", value: newValue)] }
        }
        public func child(_ name: String) -> Node? { children.first { $0.localName == name } }
        public func elements(_ name: String) -> [Node] { children.filter { $0.localName == name } }
        public func descendants(_ name: String) -> [Node] {
            children.flatMap { ($0.localName == name ? [$0] : []) + $0.descendants(name) }
        }
        public func copy() -> Node { Node(name, attributes, children: children.map { $0.copy() }, value: value) }
        public func make(_ localName: String, _ attributes: [String: String] = [:]) -> Node {
            let prefix = name.contains(":") ? String(name.prefix(through: name.firstIndex(of: ":")!)) : ""
            return Node(prefix + localName, attributes)
        }
        @discardableResult public func ensure(_ localName: String) -> Node {
            if let node = child(localName) { return node }
            let node = make(localName); children.append(node); return node
        }
        public func remove(_ name: String) { children.removeAll { $0.localName == name } }
        public var xml: String {
            if name == "#text" { return Self.escape(value) }
            if name == "#comment" { return "<!--" + value + "-->" }
            let attrs = attributes.keys.sorted().map { " " + $0 + "=\"" + Self.escape(attributes[$0]!).replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "\n", with: "&#10;").replacingOccurrences(of: "\r", with: "&#13;").replacingOccurrences(of: "\t", with: "&#9;") + "\"" }.joined()
            return children.isEmpty ? "<\(name)\(attrs)/>" : "<\(name)\(attrs)>" + children.map(\.xml).joined() + "</\(name)>"
        }
        private static func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
    }
    private var stack: [Node] = []
    private var root: Node?
    public static func parse(_ data: Data) throws -> Node {
        let delegate = ExcelEditingXML()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else { throw ExcelWorkbookDocumentError.invalidWorkbook }
        return root
    }
    public static func data(_ root: Node) -> Data { Data(("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" + root.xml).utf8) }
    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        let node = Node(qName ?? elementName, attributeDict)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }
    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { _ = stack.popLast() }
    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        if let last = stack.last?.children.last, last.name == "#text" { last.value += string }
        else { stack.last?.children.append(Node("#text", value: string)) }
    }
    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { self.parser(parser, foundCharacters: String(decoding: CDATABlock, as: UTF8.self)) }
    public func parser(_ parser: XMLParser, foundComment comment: String) { stack.last?.children.append(Node("#comment", value: comment)) }
}

public nonisolated enum ExcelEditAxis: String, CaseIterable, Identifiable, Sendable {
    case row, column
    public var id: String { rawValue }
    public var title: String { DocumentEngineLocalization.string(self == .row ? "행" : "열") }
}

public nonisolated struct ExcelStructureChange: Sendable {
    public let axis: ExcelEditAxis
    public let index: Int
    public let count: Int
    public let deleting: Bool
    public func position(_ value: Int) -> Int? {
        if value < index { return value }
        if deleting && value < index + count { return nil }
        return value + (deleting ? -count : count)
    }
    public func address(_ address: ExcelCellAddress) -> ExcelCellAddress? {
        guard let value = position(axis == .row ? address.row : address.column) else { return nil }
        return ExcelCellAddress(row: axis == .row ? value : address.row, column: axis == .column ? value : address.column)
    }
    public func interval(_ lower: Int, _ upper: Int) -> ClosedRange<Int>? {
        if !deleting { return position(lower)! ... position(upper)! }
        let first = lower >= index && lower < index + count ? index + count : lower
        let last = upper >= index && upper < index + count ? index - 1 : upper
        guard first <= last, let a = position(first), let b = position(last) else { return nil }
        return a ... b
    }
    public func range(_ range: ExcelCellRange) -> ExcelCellRange? {
        guard let interval = interval(axis == .row ? range.start.row : range.start.column, axis == .row ? range.end.row : range.end.column) else { return nil }
        return ExcelCellRange(start: ExcelCellAddress(row: axis == .row ? interval.lowerBound : range.start.row, column: axis == .column ? interval.lowerBound : range.start.column), end: ExcelCellAddress(row: axis == .row ? interval.upperBound : range.end.row, column: axis == .column ? interval.upperBound : range.end.column))
    }

    public init(axis: ExcelEditAxis, index: Int, count: Int, deleting: Bool) {
        self.axis = axis
        self.index = index
        self.count = count
        self.deleting = deleting
    }
}

public nonisolated enum ExcelFormulaReferenceEditing {
    // Match an optional sheet qualifier and a whole A1 range as one token.
    private static let pattern = #"(?<![\p{L}\p{N}_.\[\]])(?:(('[^']*(?:''[^']*)*'|[\p{L}_][\p{L}\p{N}_.]*)!))?(\$?[A-Za-z]{1,3}\$?[1-9][0-9]*)(?::(\$?[A-Za-z]{1,3}\$?[1-9][0-9]*))?(?![\p{L}\p{N}_(\]!])"#
    public static func structural(_ formula: String, change: ExcelStructureChange, targetSheet: String, localSheet: String?) -> String {
        transform(formula) { qualifier, first, last in
            let sheet = qualifier.map(unquote) ?? localSheet
            guard sheet?.caseInsensitiveCompare(targetSheet) == .orderedSame else { return nil }
            guard let start = ExcelCellAddress(first) else { return nil }
            if let last, let end = ExcelCellAddress(last) {
                guard let range = change.range(ExcelCellRange(start: start, end: end)) else { return "#REF!" }
                return (qualifier.map { $0 + "!" } ?? "") + preservingDollars(first, address: range.start) + ":" + preservingDollars(last, address: range.end)
            }
            guard let moved = change.address(start) else { return "#REF!" }
            return (qualifier.map { $0 + "!" } ?? "") + preservingDollars(first, address: moved)
        }
    }
    public static func copied(_ formula: String, from: ExcelCellAddress, to: ExcelCellAddress) -> String {
        transform(formula) { qualifier, first, last in
            func shifted(_ ref: String) -> String {
                guard let address = ExcelCellAddress(ref) else { return ref }
                let rowFixed = ref.range(of: #"\$[0-9]"#, options: .regularExpression) != nil
                let row = address.row + (rowFixed ? 0 : to.row - from.row)
                let column = address.column + (ref.hasPrefix("$") ? 0 : to.column - from.column)
                guard row > 0, column > 0, row <= ExcelWorkbookDocument.maximumExcelRows, column <= ExcelWorkbookDocument.maximumExcelColumns else { return "#REF!" }
                return preservingDollars(ref, address: ExcelCellAddress(row: row, column: column))
            }
            return (qualifier.map { $0 + "!" } ?? "") + shifted(first) + (last.map { ":" + shifted($0) } ?? "")
        }
    }
    public static func moved(_ formula: String, source: ExcelCellRange, sourceSheet: String, destination: ExcelCellAddress, destinationSheet: String, formulaSheet: String) -> String {
        transform(formula) { qualifier, first, last in
            guard (qualifier.map(unquote) ?? formulaSheet).caseInsensitiveCompare(sourceSheet) == .orderedSame,
                  let a = ExcelCellAddress(first), source.contains(a),
                  last == nil || ExcelCellAddress(last!).map(source.contains) == true else { return nil }
            func movedRef(_ ref: String) -> String {
                let address = ExcelCellAddress(ref)!
                return preservingDollars(ref, address: ExcelCellAddress(row: address.row + destination.row - source.start.row, column: address.column + destination.column - source.start.column))
            }
            let prefix = qualifier != nil || formulaSheet != destinationSheet ? "'" + destinationSheet.replacingOccurrences(of: "'", with: "''") + "'!" : ""
            return prefix + movedRef(first) + (last.map { ":" + movedRef($0) } ?? "")
        }
    }
    private static func transform(_ formula: String, replace: (String?, String, String?) -> String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return formula }
        let original = formula as NSString
        let result = NSMutableString(string: formula)
        for match in regex.matches(in: formula, range: NSRange(location: 0, length: original.length)).reversed() {
            let prefix = original.substring(to: match.range.location)
            // Excel escapes quotes by doubling them; an odd count is inside a string.
            guard prefix.filter({ $0 == "\"" }).count % 2 == 0 else { continue }
            // Do not rewrite external-workbook or 3-D references as local references.
            if prefix.last == "]" || prefix.last == ":" { continue }
            let qualifier = match.range(at: 2).location == NSNotFound ? nil : original.substring(with: match.range(at: 2))
            let first = original.substring(with: match.range(at: 3))
            let last = match.range(at: 4).location == NSNotFound ? nil : original.substring(with: match.range(at: 4))
            if let replacement = replace(qualifier, first, last) { result.replaceCharacters(in: match.range, with: replacement) }
        }
        return result as String
    }
    private static func unquote(_ name: String) -> String {
        name.hasPrefix("'") ? String(name.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") : name
    }
    private static func preservingDollars(_ source: String, address: ExcelCellAddress) -> String {
        (source.hasPrefix("$") ? "$" : "") + ExcelCellAddress.columnName(address.column)
            + (source.range(of: #"\$[0-9]"#, options: .regularExpression) != nil ? "$" : "") + String(address.row)
    }
}
