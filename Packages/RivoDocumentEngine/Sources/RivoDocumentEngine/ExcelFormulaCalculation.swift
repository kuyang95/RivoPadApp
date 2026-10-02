import Foundation

public nonisolated struct ExcelFormulaCalculatedValue: Hashable, Sendable {
    public let rawValue: String
    public let displayValue: String
    public let cellType: String?
    public let cachedXMLValue: String
    public let cachedXMLType: String?

    public init(rawValue: String, displayValue: String, cellType: String? = nil, cachedXMLValue: String, cachedXMLType: String? = nil) {
        self.rawValue = rawValue
        self.displayValue = displayValue
        self.cellType = cellType
        self.cachedXMLValue = cachedXMLValue
        self.cachedXMLType = cachedXMLType
    }
}

public nonisolated struct ExcelFormulaCalculationResult: Sendable {
    public let values: [ExcelCellAddress: ExcelFormulaCalculatedValue]
    public let unsupportedFormulaCount: Int
    public let spillRanges: [ExcelCellAddress: ExcelCellRange]
    public let spillOwners: [ExcelCellAddress: ExcelCellAddress]
    public let clearedSpillAddresses: Set<ExcelCellAddress>

    public init(values: [ExcelCellAddress: ExcelFormulaCalculatedValue], unsupportedFormulaCount: Int, spillRanges: [ExcelCellAddress: ExcelCellRange], spillOwners: [ExcelCellAddress: ExcelCellAddress], clearedSpillAddresses: Set<ExcelCellAddress>) {
        self.values = values
        self.unsupportedFormulaCount = unsupportedFormulaCount
        self.spillRanges = spillRanges
        self.spillOwners = spillOwners
        self.clearedSpillAddresses = clearedSpillAddresses
    }
}

public nonisolated enum ExcelFormulaCalculator {
    public static func recalculate(
        cells: [ExcelCellAddress: ExcelCell],
        styles: [ExcelCellStyle],
        uses1904DateSystem: Bool,
        mergedRanges: [ExcelCellRange] = [],
        tableRanges: [ExcelCellRange] = [],
        workbook: ExcelWorkbook? = nil,
        currentSheetName: String? = nil,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> ExcelFormulaCalculationResult {
        let evaluator = ExcelFormulaEvaluator(
            cells: cells,
            mergedRanges: mergedRanges,
            tableRanges: tableRanges,
            workbook: workbook,
            currentSheetName: currentSheetName,
            uses1904DateSystem: uses1904DateSystem,
            now: now,
            timeZone: timeZone
        )
        evaluator.prepareDynamicArrays()
        var values = [ExcelCellAddress: ExcelFormulaCalculatedValue]()
        var unsupportedCount = 0
        for cell in cells.values.sorted(by: { $0.address < $1.address }) {
            guard cell.formula?.isEmpty == false else { continue }
            guard let value = evaluator.value(at: cell.address),
                  let calculated = calculatedValue(
                    value,
                    style: style(at: cell.styleIndex, in: styles),
                    uses1904DateSystem: uses1904DateSystem
                  ) else {
                unsupportedCount += 1
                continue
            }
            values[cell.address] = calculated
        }
        for (address, value) in evaluator.spilledValues.sorted(by: {
            $0.key < $1.key
        }) where address != evaluator.spillOwners[address] {
            let anchor = evaluator.spillOwners[address]
            let styleIndex = cells[address]?.styleIndex
                ?? anchor.flatMap { cells[$0]?.styleIndex }
            guard let calculated = calculatedValue(
                value,
                style: style(at: styleIndex, in: styles),
                uses1904DateSystem: uses1904DateSystem
            ) else {
                unsupportedCount += 1
                continue
            }
            values[address] = calculated
        }
        return ExcelFormulaCalculationResult(
            values: values,
            unsupportedFormulaCount: unsupportedCount,
            spillRanges: evaluator.spillRanges,
            spillOwners: evaluator.spillOwners,
            clearedSpillAddresses: evaluator.clearedSpillAddresses
        )
    }

    private static func style(
        at index: Int?,
        in styles: [ExcelCellStyle]
    ) -> ExcelCellStyle {
        guard let index, styles.indices.contains(index) else {
            return .plain
        }
        return styles[index]
    }

    private static func calculatedValue(
        _ value: ExcelFormulaValue,
        style: ExcelCellStyle,
        uses1904DateSystem: Bool
    ) -> ExcelFormulaCalculatedValue? {
        switch value {
        case .number(let number):
            guard number.isFinite else { return nil }
            let raw = numberText(number)
            return ExcelFormulaCalculatedValue(
                rawValue: raw,
                displayValue: ExcelValueFormatter.displayValue(
                    raw,
                    type: nil,
                    style: style,
                    uses1904DateSystem: uses1904DateSystem
                ),
                cellType: nil,
                cachedXMLValue: raw,
                cachedXMLType: nil
            )
        case .text(let text):
            return ExcelFormulaCalculatedValue(
                rawValue: text,
                displayValue: text,
                cellType: "str",
                cachedXMLValue: text,
                cachedXMLType: "str"
            )
        case .boolean(let value):
            return ExcelFormulaCalculatedValue(
                rawValue: value ? "TRUE" : "FALSE",
                displayValue: value
                    ? DocumentEngineLocalization.string("참")
                    : DocumentEngineLocalization.string("거짓"),
                cellType: "b",
                cachedXMLValue: value ? "1" : "0",
                cachedXMLType: "b"
            )
        case .blank:
            return ExcelFormulaCalculatedValue(
                rawValue: "",
                displayValue: "",
                cellType: "str",
                cachedXMLValue: "",
                cachedXMLType: "str"
            )
        case .error(let error):
            return ExcelFormulaCalculatedValue(
                rawValue: error.rawValue,
                displayValue: error.rawValue,
                cellType: "e",
                cachedXMLValue: error.rawValue,
                cachedXMLType: "e"
            )
        }
    }

    private static func numberText(_ value: Double) -> String {
        if value.rounded() == value,
           value >= Double(Int64.min),
           value <= Double(Int64.max) {
            return String(Int64(value))
        }
        return String(
            format: "%.15g",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }
}

private nonisolated enum ExcelFormulaError: String, Equatable, Error {
    case divideByZero = "#DIV/0!"
    case value = "#VALUE!"
    case reference = "#REF!"
    case name = "#NAME?"
    case number = "#NUM!"
    case notAvailable = "#N/A"
    case spill = "#SPILL!"
    case calculation = "#CALC!"

    init?(excelText: String) {
        self.init(rawValue: excelText.uppercased())
    }
}

private nonisolated enum ExcelFormulaValue: Equatable {
    case number(Double)
    case text(String)
    case boolean(Bool)
    case blank
    case error(ExcelFormulaError)

    var number: Double? {
        switch self {
        case .number(let value):
            return value
        case .boolean(let value):
            return value ? 1 : 0
        case .blank:
            return 0
        case .text(let value):
            return Double(value.trimmingCharacters(
                in: .whitespacesAndNewlines
            ))
        case .error:
            return nil
        }
    }

    var boolean: Bool? {
        switch self {
        case .boolean(let value):
            return value
        case .number(let value):
            return value != 0
        case .text(let value):
            if value.caseInsensitiveCompare("TRUE") == .orderedSame {
                return true
            }
            if value.caseInsensitiveCompare("FALSE") == .orderedSame {
                return false
            }
            return nil
        case .blank:
            return false
        case .error:
            return nil
        }
    }

    var text: String {
        switch self {
        case .number(let value):
            return Self.generalNumberText(value)
        case .text(let value):
            return value
        case .boolean(let value):
            return value ? "TRUE" : "FALSE"
        case .blank:
            return ""
        case .error(let error):
            return error.rawValue
        }
    }

    private static func generalNumberText(_ value: Double) -> String {
        guard value.isFinite else { return "#NUM!" }
        if value == 0 { return "0" }
        if value.rounded() == value,
           value >= Double(Int64.min),
           value <= Double(Int64.max) {
            return String(Int64(value))
        }
        let magnitude = abs(value)
        if magnitude >= 1e-9, magnitude < 1e11 {
            var result = String(
                format: "%.15f",
                locale: Locale(identifier: "en_US_POSIX"),
                value
            )
            while result.last == "0" { result.removeLast() }
            if result.last == "." { result.removeLast() }
            return result
        }
        return String(
            format: "%.15g",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        ).replacingOccurrences(of: "e", with: "E")
    }

    var error: ExcelFormulaError? {
        guard case .error(let error) = self else { return nil }
        return error
    }
}

private nonisolated indirect enum ExcelFormulaExpression {
    case literal(ExcelFormulaValue)
    case cell(ExcelCellAddress)
    case range(ExcelCellRange)
    case spill(ExcelCellAddress)
    case qualifiedCell(String, ExcelCellAddress)
    case qualifiedRange(String, ExcelCellRange)
    case name(String)
    case structuredReference(String)
    case unary(String, ExcelFormulaExpression)
    case binary(
        String,
        ExcelFormulaExpression,
        ExcelFormulaExpression
    )
    case function(String, [ExcelFormulaExpression])
}

private nonisolated struct ExcelFormulaArgumentValue {
    let value: ExcelFormulaValue
    let comesFromReference: Bool
}

private nonisolated struct ExcelFormulaRangeMatrix {
    let rowCount: Int
    let columnCount: Int
    let values: [ExcelFormulaValue]

    func value(row: Int, column: Int) -> ExcelFormulaValue? {
        guard row >= 1, row <= rowCount,
              column >= 1, column <= columnCount else {
            return nil
        }
        return values[(row - 1) * columnCount + column - 1]
    }

    var vectorValues: [ExcelFormulaValue]? {
        guard rowCount == 1 || columnCount == 1 else { return nil }
        return values
    }
}

private nonisolated enum ExcelFormulaToken: Equatable {
    case number(Double)
    case string(String)
    case error(ExcelFormulaError)
    case identifier(String)
    case quotedIdentifier(String)
    case structuredReference(String)
    case cell(ExcelCellAddress)
    case plus
    case minus
    case multiply
    case divide
    case power
    case concatenate
    case percent
    case equal
    case notEqual
    case less
    case lessOrEqual
    case greater
    case greaterOrEqual
    case leftParenthesis
    case rightParenthesis
    case comma
    case colon
    case spill
    case exclamation
    case end
}

private nonisolated struct ExcelFormulaLexer {
    private let characters: [Character]
    private var index = 0

    init(_ source: String) {
        characters = Array(source)
    }

    mutating func tokens() -> [ExcelFormulaToken]? {
        var result = [ExcelFormulaToken]()
        while true {
            guard let token = nextToken() else { return nil }
            result.append(token)
            if token == .end { return result }
        }
    }

    private mutating func nextToken() -> ExcelFormulaToken? {
        skipWhitespace()
        guard index < characters.count else { return .end }
        let character = characters[index]
        switch character {
        case "+": index += 1; return .plus
        case "-": index += 1; return .minus
        case "*": index += 1; return .multiply
        case "/": index += 1; return .divide
        case "^": index += 1; return .power
        case "&": index += 1; return .concatenate
        case "%": index += 1; return .percent
        case "=": index += 1; return .equal
        case "(": index += 1; return .leftParenthesis
        case ")": index += 1; return .rightParenthesis
        case ",", ";": index += 1; return .comma
        case ":": index += 1; return .colon
        case "!": index += 1; return .exclamation
        case "'":
            return quotedIdentifierToken()
        case "[":
            return structuredReferenceToken(prefix: "")
        case "<":
            index += 1
            if consume("=") { return .lessOrEqual }
            if consume(">") { return .notEqual }
            return .less
        case ">":
            index += 1
            return consume("=") ? .greaterOrEqual : .greater
        case "\"":
            return stringToken()
        case "#":
            if index + 1 < characters.count,
               characters[index + 1].isLetter {
                return errorToken()
            }
            index += 1
            return .spill
        default:
            if character.isNumber || character == "." {
                return numberToken()
            }
            if character.isLetter || character == "_" || character == "$" {
                return wordToken()
            }
            return nil
        }
    }

    private mutating func errorToken() -> ExcelFormulaToken? {
        let start = index
        while index < characters.count {
            let character = characters[index]
            guard character.isLetter || character.isNumber
                    || character == "#" || character == "/"
                    || character == "!" || character == "?" else {
                break
            }
            index += 1
        }
        guard let error = ExcelFormulaError(
            excelText: String(characters[start..<index])
        ) else {
            return nil
        }
        return .error(error)
    }

    private mutating func stringToken() -> ExcelFormulaToken? {
        index += 1
        var value = ""
        while index < characters.count {
            let character = characters[index]
            index += 1
            if character == "\"" {
                if index < characters.count,
                   characters[index] == "\"" {
                    value.append("\"")
                    index += 1
                    continue
                }
                return .string(value)
            }
            value.append(character)
        }
        return nil
    }

    private mutating func quotedIdentifierToken() -> ExcelFormulaToken? {
        index += 1
        var value = ""
        while index < characters.count {
            let character = characters[index]
            index += 1
            if character == "'" {
                if index < characters.count, characters[index] == "'" {
                    value.append("'")
                    index += 1
                    continue
                }
                return .quotedIdentifier(value)
            }
            value.append(character)
        }
        return nil
    }

    private mutating func numberToken() -> ExcelFormulaToken? {
        let start = index
        var sawExponent = false
        while index < characters.count {
            let character = characters[index]
            if character.isNumber || character == "." {
                index += 1
            } else if (character == "e" || character == "E"),
                      !sawExponent {
                sawExponent = true
                index += 1
                if index < characters.count,
                   characters[index] == "+" || characters[index] == "-" {
                    index += 1
                }
            } else {
                break
            }
        }
        guard let value = Double(String(characters[start..<index])) else {
            return nil
        }
        return .number(value)
    }

    private mutating func wordToken() -> ExcelFormulaToken? {
        let start = index
        while index < characters.count {
            let character = characters[index]
            guard character.isLetter || character.isNumber
                    || character == "_" || character == "."
                    || character == "$" else {
                break
            }
            index += 1
        }
        let word = String(characters[start..<index])
        if index < characters.count, characters[index] == "[" {
            return structuredReferenceToken(prefix: word)
        }
        var lookahead = index
        while lookahead < characters.count,
              characters[lookahead].isWhitespace {
            lookahead += 1
        }
        if lookahead < characters.count,
           characters[lookahead] == "(" {
            return .identifier(word)
        }
        if let address = ExcelCellAddress(word),
           address.row <= ExcelWorkbookDocument.maximumExcelRows,
           address.column <= ExcelWorkbookDocument.maximumExcelColumns {
            return .cell(address)
        }
        return .identifier(word)
    }

    private mutating func structuredReferenceToken(
        prefix: String
    ) -> ExcelFormulaToken? {
        let start = index
        var depth = 0
        while index < characters.count {
            let character = characters[index]
            if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
            }
            index += 1
            if depth == 0 { break }
        }
        guard depth == 0, index > start else { return nil }
        return .structuredReference(
            prefix + String(characters[start..<index])
        )
    }

    private mutating func skipWhitespace() {
        while index < characters.count, characters[index].isWhitespace {
            index += 1
        }
    }

    private mutating func consume(_ character: Character) -> Bool {
        guard index < characters.count,
              characters[index] == character else {
            return false
        }
        index += 1
        return true
    }
}

private nonisolated struct ExcelFormulaParser {
    private let tokens: [ExcelFormulaToken]
    private var index = 0

    init?(_ source: String) {
        var lexer = ExcelFormulaLexer(source)
        guard let tokens = lexer.tokens() else { return nil }
        self.tokens = tokens
    }

    mutating func parse() -> ExcelFormulaExpression? {
        guard let expression = comparison(), current == .end else {
            return nil
        }
        return expression
    }

    private var current: ExcelFormulaToken {
        tokens.indices.contains(index) ? tokens[index] : .end
    }

    private mutating func comparison() -> ExcelFormulaExpression? {
        guard var expression = concatenation() else { return nil }
        while [.equal, .notEqual, .less, .lessOrEqual, .greater,
               .greaterOrEqual].contains(current) {
            let operation = current
            index += 1
            guard let right = concatenation() else { return nil }
            expression = .binary(symbol(for: operation), expression, right)
        }
        return expression
    }

    private mutating func concatenation() -> ExcelFormulaExpression? {
        guard var expression = addition() else { return nil }
        while current == .concatenate {
            index += 1
            guard let right = addition() else { return nil }
            expression = .binary("&", expression, right)
        }
        return expression
    }

    private mutating func addition() -> ExcelFormulaExpression? {
        guard var expression = multiplication() else { return nil }
        while current == .plus || current == .minus {
            let operation = current == .plus ? "+" : "-"
            index += 1
            guard let right = multiplication() else { return nil }
            expression = .binary(operation, expression, right)
        }
        return expression
    }

    private mutating func multiplication() -> ExcelFormulaExpression? {
        guard var expression = power() else { return nil }
        while current == .multiply || current == .divide {
            let operation = current == .multiply ? "*" : "/"
            index += 1
            guard let right = power() else { return nil }
            expression = .binary(operation, expression, right)
        }
        return expression
    }

    private mutating func power() -> ExcelFormulaExpression? {
        guard var expression = unary() else { return nil }
        if current == .power {
            index += 1
            guard let right = power() else { return nil }
            expression = .binary("^", expression, right)
        }
        return expression
    }

    private mutating func unary() -> ExcelFormulaExpression? {
        if current == .plus || current == .minus {
            let operation = current == .plus ? "+" : "-"
            index += 1
            guard let value = unary() else { return nil }
            return .unary(operation, value)
        }
        guard var expression = primary() else { return nil }
        while current == .percent {
            index += 1
            expression = .unary("%", expression)
        }
        return expression
    }

    private mutating func primary() -> ExcelFormulaExpression? {
        switch current {
        case .number(let value):
            index += 1
            return .literal(.number(value))
        case .string(let value):
            index += 1
            return .literal(.text(value))
        case .error(let error):
            index += 1
            return .literal(.error(error))
        case .cell(let start):
            index += 1
            if current == .colon {
                index += 1
                guard case .cell(let end) = current else { return nil }
                index += 1
                return .range(ExcelCellRange(start: start, end: end))
            }
            if current == .spill {
                index += 1
                return .spill(start)
            }
            return .cell(start)
        case .quotedIdentifier(let sheetName):
            index += 1
            guard current == .exclamation else { return nil }
            index += 1
            return qualifiedReference(sheetName: sheetName)
        case .structuredReference(let reference):
            index += 1
            return .structuredReference(reference)
        case .identifier(let name):
            index += 1
            if current == .exclamation {
                index += 1
                return qualifiedReference(sheetName: name)
            }
            if name.caseInsensitiveCompare("TRUE") == .orderedSame,
               current != .leftParenthesis {
                return .literal(.boolean(true))
            }
            if name.caseInsensitiveCompare("FALSE") == .orderedSame,
               current != .leftParenthesis {
                return .literal(.boolean(false))
            }
            guard current == .leftParenthesis else {
                return .name(name)
            }
            index += 1
            var arguments = [ExcelFormulaExpression]()
            if current != .rightParenthesis {
                while true {
                    if current == .comma {
                        arguments.append(.literal(.blank))
                    } else {
                        guard let argument = comparison() else { return nil }
                        arguments.append(argument)
                    }
                    if current != .comma { break }
                    index += 1
                    if current == .rightParenthesis {
                        arguments.append(.literal(.blank))
                        break
                    }
                }
            }
            guard current == .rightParenthesis else { return nil }
            index += 1
            return .function(normalizedFunctionName(name), arguments)
        case .leftParenthesis:
            index += 1
            guard let expression = comparison(),
                  current == .rightParenthesis else {
                return nil
            }
            index += 1
            return expression
        default:
            return nil
        }
    }

    private mutating func qualifiedReference(
        sheetName: String
    ) -> ExcelFormulaExpression? {
        guard case .cell(let start) = current else { return nil }
        index += 1
        if current == .colon {
            index += 1
            guard case .cell(let end) = current else { return nil }
            index += 1
            return .qualifiedRange(
                sheetName,
                ExcelCellRange(start: start, end: end)
            )
        }
        return .qualifiedCell(sheetName, start)
    }

    private func symbol(for token: ExcelFormulaToken) -> String {
        switch token {
        case .equal: return "="
        case .notEqual: return "<>"
        case .less: return "<"
        case .lessOrEqual: return "<="
        case .greater: return ">"
        case .greaterOrEqual: return ">="
        default: return ""
        }
    }

    private func normalizedFunctionName(_ rawName: String) -> String {
        var name = rawName.uppercased()
        if name.hasPrefix("_XLFN.") {
            name.removeFirst("_XLFN.".count)
        }
        if name.hasPrefix("_XLWS.") {
            name.removeFirst("_XLWS.".count)
        }
        return name
    }
}

private nonisolated final class ExcelFormulaEvaluator {
    private enum CriterionOperation {
        case equal
        case notEqual
        case less
        case lessOrEqual
        case greater
        case greaterOrEqual
    }

    private struct Criterion {
        let operation: CriterionOperation
        let operand: ExcelFormulaValue
    }

    private enum CachedValue {
        case success(ExcelFormulaValue)
        case failure
    }

    private enum ArrayValueKey: Hashable {
        case number(Double)
        case text(String)
        case boolean(Bool)
        case blank
        case error(String)
    }

    private let cells: [ExcelCellAddress: ExcelCell]
    private let mergedRanges: [ExcelCellRange]
    private let tableRanges: [ExcelCellRange]
    private let workbook: ExcelWorkbook?
    private let currentSheetName: String?
    private let uses1904DateSystem: Bool
    private let now: Date
    private let timeZone: TimeZone
    private let supportsDynamicArrays: Bool
    private var cache = [ExcelCellAddress: CachedValue]()
    private var visiting = Set<ExcelCellAddress>()
    private var evaluationStack = [ExcelCellAddress]()
    private var parsedFormulas = [ExcelCellAddress: ExcelFormulaExpression]()
    private var dynamicArrayAttempts = Set<ExcelCellAddress>()
    private var visitingDynamicArrays = Set<ExcelCellAddress>()
    private var resolvingNames = Set<String>()
    private var inspectingArrayNames = Set<String>()
    private(set) var spilledValues = [ExcelCellAddress: ExcelFormulaValue]()
    private(set) var spillRanges = [ExcelCellAddress: ExcelCellRange]()
    private(set) var spillOwners = [ExcelCellAddress: ExcelCellAddress]()

    var clearedSpillAddresses: Set<ExcelCellAddress> {
        let previous: Set<ExcelCellAddress> = Set(cells.values.compactMap {
            cell -> ExcelCellAddress? in
            guard let anchor = cell.spillAnchor,
                  anchor != cell.address else { return nil }
            return cell.address
        })
        return previous.subtracting(Set(spillOwners.keys))
    }

    init(
        cells: [ExcelCellAddress: ExcelCell],
        mergedRanges: [ExcelCellRange],
        tableRanges: [ExcelCellRange],
        workbook: ExcelWorkbook?,
        currentSheetName: String?,
        uses1904DateSystem: Bool,
        now: Date,
        timeZone: TimeZone
    ) {
        self.cells = cells
        self.mergedRanges = mergedRanges
        self.tableRanges = tableRanges
        self.workbook = workbook
        self.currentSheetName = currentSheetName
        self.uses1904DateSystem = uses1904DateSystem
        self.now = now
        self.timeZone = timeZone
        self.supportsDynamicArrays = workbook?.supportsDynamicArrays ?? true
    }

    func prepareDynamicArrays() {
        for cell in cells.values.sorted(by: { $0.address < $1.address }) {
            guard let expression = parsedExpression(at: cell.address),
                  isArrayExpression(expression),
                  shouldPrepareDynamicArray(
                    at: cell.address,
                    expression: expression
                  ) else { continue }
            prepareDynamicArray(at: cell.address, expression: expression)
        }
    }

    func value(at address: ExcelCellAddress) -> ExcelFormulaValue? {
        if let value = spilledValues[address] {
            return value
        }
        if let owner = cells[address]?.spillAnchor,
           owner != address,
           !dynamicArrayAttempts.contains(owner),
           let expression = parsedExpression(at: owner),
           isArrayExpression(expression),
           shouldPrepareDynamicArray(at: owner, expression: expression) {
            prepareDynamicArray(at: owner, expression: expression)
            if let value = spilledValues[address] {
                return value
            }
        }
        if let cached = cache[address] {
            switch cached {
            case .success(let value): return value
            case .failure: return nil
            }
        }
        guard !visiting.contains(address) else {
            cache[address] = .failure
            return nil
        }
        guard let cell = cells[address] else {
            cache[address] = .success(.blank)
            return .blank
        }
        if let formula = cell.formula, !formula.isEmpty {
            if !dynamicArrayAttempts.contains(address),
               let expression = parsedExpression(at: address),
               isArrayExpression(expression),
               shouldPrepareDynamicArray(
                at: address,
                expression: expression
               ) {
                prepareDynamicArray(at: address, expression: expression)
                if let value = spilledValues[address] {
                    return value
                }
                if let cached = cache[address] {
                    switch cached {
                    case .success(let value): return value
                    case .failure: return nil
                    }
                }
            }
            visiting.insert(address)
            evaluationStack.append(address)
            let evaluated = parsedExpression(at: address).flatMap(evaluate)
            let result = evaluated.map { value -> ExcelFormulaValue in
                if case .blank = value { return .number(0) }
                return value
            }
            evaluationStack.removeLast()
            visiting.remove(address)
            cache[address] = result.map(CachedValue.success) ?? .failure
            return result
        }
        let value = literalValue(of: cell)
        cache[address] = .success(value)
        return value
    }

    private func parsedExpression(
        at address: ExcelCellAddress
    ) -> ExcelFormulaExpression? {
        if let expression = parsedFormulas[address] {
            return expression
        }
        guard let formula = cells[address]?.formula, !formula.isEmpty,
              var parser = ExcelFormulaParser(formula),
              let expression = parser.parse() else {
            return nil
        }
        parsedFormulas[address] = expression
        return expression
    }

    private func prepareDynamicArray(
        at anchor: ExcelCellAddress,
        expression: ExcelFormulaExpression
    ) {
        guard !dynamicArrayAttempts.contains(anchor),
              !visitingDynamicArrays.contains(anchor) else { return }
        dynamicArrayAttempts.insert(anchor)
        visitingDynamicArrays.insert(anchor)
        defer { visitingDynamicArrays.remove(anchor) }
        guard let matrix = arrayMatrix(expression) else {
            cache[anchor] = .failure
            return
        }
        guard matrix.rowCount > 0, matrix.columnCount > 0,
              matrix.values.count == matrix.rowCount * matrix.columnCount,
              matrix.rowCount <= ExcelWorkbookDocument.maximumExcelRows,
              matrix.columnCount <= ExcelWorkbookDocument.maximumExcelColumns,
              anchor.row <= ExcelWorkbookDocument.maximumExcelRows
                - matrix.rowCount + 1,
              anchor.column <= ExcelWorkbookDocument.maximumExcelColumns
                - matrix.columnCount + 1 else {
            cache[anchor] = .success(.error(.calculation))
            return
        }
        let range = ExcelCellRange(
            start: anchor,
            end: ExcelCellAddress(
                row: anchor.row + matrix.rowCount - 1,
                column: anchor.column + matrix.columnCount - 1
            )
        )
        guard spillRangeIsAvailable(range, for: anchor) else {
            cache[anchor] = .success(.error(.spill))
            return
        }
        spillRanges[anchor] = range
        for rowOffset in 0 ..< matrix.rowCount {
            for columnOffset in 0 ..< matrix.columnCount {
                let address = ExcelCellAddress(
                    row: anchor.row + rowOffset,
                    column: anchor.column + columnOffset
                )
                let value = matrix.values[
                    rowOffset * matrix.columnCount + columnOffset
                ]
                spilledValues[address] = value
                spillOwners[address] = anchor
            }
        }
        cache[anchor] = .success(matrix.values[0])
    }

    private func spillRangeIsAvailable(
        _ range: ExcelCellRange,
        for anchor: ExcelCellAddress
    ) -> Bool {
        if tableRanges.contains(where: { $0.contains(anchor) }) {
            return false
        }
        for row in range.start.row ... range.end.row {
            for column in range.start.column ... range.end.column {
                let address = ExcelCellAddress(row: row, column: column)
                if mergedRanges.contains(where: { $0.contains(address) })
                    || tableRanges.contains(where: { $0.contains(address) }) {
                    return false
                }
                if let owner = spillOwners[address], owner != anchor {
                    return false
                }
                guard address != anchor, let cell = cells[address] else {
                    continue
                }
                if cell.spillAnchor != nil { continue }
                if cell.formula?.isEmpty == false
                    || !cell.rawValue.isEmpty {
                    return false
                }
            }
        }
        return true
    }

    private func isArrayExpression(
        _ expression: ExcelFormulaExpression
    ) -> Bool {
        switch expression {
        case .range, .spill, .qualifiedRange:
            return true
        case .structuredReference(let reference):
            guard let location = structuredReferenceLocation(reference) else {
                return false
            }
            return location.range.start != location.range.end
        case .name(let name):
            let key = name.uppercased()
            guard inspectingArrayNames.insert(key).inserted else {
                return false
            }
            defer { inspectingArrayNames.remove(key) }
            return definedNameExpression(name).map(isArrayExpression) ?? false
        case .unary(_, let value):
            return isArrayExpression(value)
        case .binary(_, let left, let right):
            return isArrayExpression(left) || isArrayExpression(right)
        case .function(let name, _):
            if ["SEQUENCE", "FILTER", "SORT", "UNIQUE"].contains(name) {
                return true
            }
            return false
        case .literal, .cell, .qualifiedCell:
            return false
        }
    }

    private func shouldPrepareDynamicArray(
        at address: ExcelCellAddress,
        expression: ExcelFormulaExpression
    ) -> Bool {
        supportsDynamicArrays
            || cells[address]?.spillRange != nil
            || containsExplicitDynamicArrayOperation(expression)
    }

    private func containsExplicitDynamicArrayOperation(
        _ expression: ExcelFormulaExpression
    ) -> Bool {
        switch expression {
        case .spill:
            return true
        case .unary(_, let value):
            return containsExplicitDynamicArrayOperation(value)
        case .binary(_, let left, let right):
            return containsExplicitDynamicArrayOperation(left)
                || containsExplicitDynamicArrayOperation(right)
        case .function(let name, let arguments):
            return ["SEQUENCE", "FILTER", "SORT", "UNIQUE"].contains(name)
                || arguments.contains(
                    where: containsExplicitDynamicArrayOperation
                )
        case .literal, .cell, .range, .qualifiedCell, .qualifiedRange,
             .name, .structuredReference:
            return false
        }
    }

    private func arrayMatrix(
        _ expression: ExcelFormulaExpression
    ) -> ExcelFormulaRangeMatrix? {
        switch expression {
        case .literal(let value):
            return scalarMatrix(value)
        case .cell(let address):
            return value(at: address).map(scalarMatrix)
        case .range(let range):
            return rangeMatrix(range)
        case .qualifiedCell(let sheetName, let address):
            return qualifiedValue(
                sheetName: sheetName,
                at: address
            ).map(scalarMatrix)
        case .qualifiedRange(let sheetName, let range):
            return qualifiedRangeMatrix(
                sheetName: sheetName,
                range: range
            )
        case .name(let name):
            let key = name.uppercased()
            guard resolvingNames.insert(key).inserted else {
                return scalarMatrix(.error(.reference))
            }
            defer { resolvingNames.remove(key) }
            guard let expression = definedNameExpression(name) else {
                return scalarMatrix(.error(.name))
            }
            return arrayMatrix(expression)
        case .structuredReference(let reference):
            guard let location = structuredReferenceLocation(reference) else {
                return scalarMatrix(.error(.reference))
            }
            return qualifiedRangeMatrix(
                sheetName: location.sheetName,
                range: location.range
            )
        case .spill(let anchor):
            if !dynamicArrayAttempts.contains(anchor),
               let expression = parsedExpression(at: anchor),
               isArrayExpression(expression) {
                prepareDynamicArray(at: anchor, expression: expression)
            }
            if let range = spillRanges[anchor] {
                return rangeMatrix(range)
            }
            return value(at: anchor).map(scalarMatrix)
        case .unary(let operation, let valueExpression):
            guard let matrix = arrayMatrix(valueExpression) else {
                return nil
            }
            var values = [ExcelFormulaValue]()
            values.reserveCapacity(matrix.values.count)
            for value in matrix.values {
                if let error = value.error {
                    values.append(.error(error))
                    continue
                }
                guard let number = value.number else {
                    values.append(.error(.value))
                    continue
                }
                switch operation {
                case "+": values.append(finiteNumber(number))
                case "-": values.append(finiteNumber(-number))
                case "%": values.append(finiteNumber(number / 100))
                default: return nil
                }
            }
            return ExcelFormulaRangeMatrix(
                rowCount: matrix.rowCount,
                columnCount: matrix.columnCount,
                values: values
            )
        case .binary(let operation, let left, let right):
            guard let lhs = arrayMatrix(left),
                  let rhs = arrayMatrix(right) else { return nil }
            return arrayBinary(operation, lhs, rhs)
        case .function(let name, let arguments):
            switch name {
            case "SEQUENCE":
                return sequenceArray(arguments)
            case "FILTER":
                return filterArray(arguments)
            case "SORT":
                return sortArray(arguments)
            case "UNIQUE":
                return uniqueArray(arguments)
            default:
                return evaluate(expression).map(scalarMatrix)
            }
        }
    }

    private func scalarMatrix(
        _ value: ExcelFormulaValue
    ) -> ExcelFormulaRangeMatrix {
        ExcelFormulaRangeMatrix(
            rowCount: 1,
            columnCount: 1,
            values: [value]
        )
    }

    private func arrayBinary(
        _ operation: String,
        _ left: ExcelFormulaRangeMatrix,
        _ right: ExcelFormulaRangeMatrix
    ) -> ExcelFormulaRangeMatrix {
        let rowCount: Int
        let columnCount: Int
        if left.rowCount == right.rowCount,
           left.columnCount == right.columnCount {
            rowCount = left.rowCount
            columnCount = left.columnCount
        } else if left.rowCount == 1, left.columnCount == 1 {
            rowCount = right.rowCount
            columnCount = right.columnCount
        } else if right.rowCount == 1, right.columnCount == 1 {
            rowCount = left.rowCount
            columnCount = left.columnCount
        } else {
            return scalarMatrix(.error(.value))
        }
        var values = [ExcelFormulaValue]()
        values.reserveCapacity(rowCount * columnCount)
        for row in 1 ... rowCount {
            for column in 1 ... columnCount {
                let lhs = left.rowCount == 1 && left.columnCount == 1
                    ? left.values[0]
                    : left.value(row: row, column: column)
                let rhs = right.rowCount == 1 && right.columnCount == 1
                    ? right.values[0]
                    : right.value(row: row, column: column)
                guard let lhs, let rhs,
                      let result = binary(operation, lhs, rhs) else {
                    values.append(.error(.value))
                    continue
                }
                values.append(result)
            }
        }
        return ExcelFormulaRangeMatrix(
            rowCount: rowCount,
            columnCount: columnCount,
            values: values
        )
    }

    private func sequenceArray(
        _ arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaRangeMatrix {
        guard (1 ... 4).contains(arguments.count) else {
            return scalarMatrix(.error(.value))
        }
        guard let rows = integerArrayArgument(
            arguments,
            at: 0,
            defaultValue: 1
        ), let columns = integerArrayArgument(
            arguments,
            at: 1,
            defaultValue: 1
        ), let start = numberArrayArgument(
            arguments,
            at: 2,
            defaultValue: 1
        ), let step = numberArrayArgument(
            arguments,
            at: 3,
            defaultValue: 1
        ) else {
            return scalarMatrix(.error(.value))
        }
        guard rows > 0, columns > 0,
              rows <= 100_000, columns <= 100_000,
              rows <= 100_000 / columns else {
            return scalarMatrix(.error(.calculation))
        }
        var values = [ExcelFormulaValue]()
        values.reserveCapacity(rows * columns)
        for index in 0 ..< rows * columns {
            let value = start + Double(index) * step
            guard value.isFinite else {
                return scalarMatrix(.error(.number))
            }
            values.append(.number(value))
        }
        return ExcelFormulaRangeMatrix(
            rowCount: rows,
            columnCount: columns,
            values: values
        )
    }

    private func filterArray(
        _ arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaRangeMatrix {
        guard (2 ... 3).contains(arguments.count),
              let source = arrayMatrix(arguments[0]),
              let include = arrayMatrix(arguments[1]) else {
            return scalarMatrix(.error(.value))
        }
        if include.rowCount == source.rowCount,
           include.columnCount == 1 {
            var values = [ExcelFormulaValue]()
            var includedRows = 0
            for row in 1 ... source.rowCount {
                let includeValue = include.value(row: row, column: 1)
                    ?? .error(.value)
                guard let shouldInclude = filterBoolean(includeValue) else {
                    return scalarMatrix(.error(
                        includeValue.error ?? .value
                    ))
                }
                guard shouldInclude else { continue }
                includedRows += 1
                for column in 1 ... source.columnCount {
                    values.append(
                        source.value(row: row, column: column) ?? .blank
                    )
                }
            }
            if includedRows > 0 {
                return ExcelFormulaRangeMatrix(
                    rowCount: includedRows,
                    columnCount: source.columnCount,
                    values: values
                )
            }
        } else if include.rowCount == 1,
                  include.columnCount == source.columnCount {
            var selectedColumns = [Int]()
            for column in 1 ... source.columnCount {
                let includeValue = include.value(row: 1, column: column)
                    ?? .error(.value)
                guard let shouldInclude = filterBoolean(includeValue) else {
                    return scalarMatrix(.error(
                        includeValue.error ?? .value
                    ))
                }
                if shouldInclude { selectedColumns.append(column) }
            }
            if !selectedColumns.isEmpty {
                var values = [ExcelFormulaValue]()
                values.reserveCapacity(source.rowCount * selectedColumns.count)
                for row in 1 ... source.rowCount {
                    for column in selectedColumns {
                        values.append(
                            source.value(row: row, column: column) ?? .blank
                        )
                    }
                }
                return ExcelFormulaRangeMatrix(
                    rowCount: source.rowCount,
                    columnCount: selectedColumns.count,
                    values: values
                )
            }
        } else {
            return scalarMatrix(.error(.value))
        }
        if arguments.count == 3,
           let fallback = arrayMatrix(arguments[2]) {
            return fallback
        }
        return scalarMatrix(.error(.calculation))
    }

    private func filterBoolean(_ value: ExcelFormulaValue) -> Bool? {
        if value.error != nil { return nil }
        return value.boolean
    }

    private func sortArray(
        _ arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaRangeMatrix {
        guard (1 ... 4).contains(arguments.count),
              let source = arrayMatrix(arguments[0]),
              let index = integerArrayArgument(
                arguments,
                at: 1,
                defaultValue: 1
              ), let order = integerArrayArgument(
                arguments,
                at: 2,
                defaultValue: 1
              ), let byColumn = booleanArrayArgument(
                arguments,
                at: 3,
                defaultValue: false
              ), (order == 1 || order == -1) else {
            return scalarMatrix(.error(.value))
        }
        if byColumn {
            guard (1 ... source.rowCount).contains(index) else {
                return scalarMatrix(.error(.value))
            }
            let indexes = (1 ... source.columnCount).sorted { lhs, rhs in
                let comparison = arraySortComparison(
                    source.value(row: index, column: lhs) ?? .blank,
                    source.value(row: index, column: rhs) ?? .blank
                )
                if comparison == .orderedSame { return lhs < rhs }
                return order == 1
                    ? comparison == .orderedAscending
                    : comparison == .orderedDescending
            }
            var values = [ExcelFormulaValue]()
            values.reserveCapacity(source.values.count)
            for row in 1 ... source.rowCount {
                for column in indexes {
                    values.append(
                        source.value(row: row, column: column) ?? .blank
                    )
                }
            }
            return ExcelFormulaRangeMatrix(
                rowCount: source.rowCount,
                columnCount: source.columnCount,
                values: values
            )
        }
        guard (1 ... source.columnCount).contains(index) else {
            return scalarMatrix(.error(.value))
        }
        let indexes = (1 ... source.rowCount).sorted { lhs, rhs in
            let comparison = arraySortComparison(
                source.value(row: lhs, column: index) ?? .blank,
                source.value(row: rhs, column: index) ?? .blank
            )
            if comparison == .orderedSame { return lhs < rhs }
            return order == 1
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }
        var values = [ExcelFormulaValue]()
        values.reserveCapacity(source.values.count)
        for row in indexes {
            for column in 1 ... source.columnCount {
                values.append(
                    source.value(row: row, column: column) ?? .blank
                )
            }
        }
        return ExcelFormulaRangeMatrix(
            rowCount: source.rowCount,
            columnCount: source.columnCount,
            values: values
        )
    }

    private func uniqueArray(
        _ arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaRangeMatrix {
        guard (1 ... 3).contains(arguments.count),
              let source = arrayMatrix(arguments[0]),
              let byColumn = booleanArrayArgument(
                arguments,
                at: 1,
                defaultValue: false
              ), let exactlyOnce = booleanArrayArgument(
                arguments,
                at: 2,
                defaultValue: false
              ) else {
            return scalarMatrix(.error(.value))
        }
        let itemCount = byColumn ? source.columnCount : source.rowCount
        var signatures = [[ArrayValueKey]]()
        signatures.reserveCapacity(itemCount)
        for item in 1 ... itemCount {
            let values: [ExcelFormulaValue]
            if byColumn {
                values = (1 ... source.rowCount).map {
                    source.value(row: $0, column: item) ?? .blank
                }
            } else {
                values = (1 ... source.columnCount).map {
                    source.value(row: item, column: $0) ?? .blank
                }
            }
            signatures.append(values.map(arrayValueKey))
        }
        var counts = [[ArrayValueKey]: Int]()
        for signature in signatures {
            counts[signature, default: 0] += 1
        }
        var seen = Set<[ArrayValueKey]>()
        var kept = [Int]()
        for (offset, signature) in signatures.enumerated() {
            if exactlyOnce {
                if counts[signature] == 1 { kept.append(offset + 1) }
            } else if seen.insert(signature).inserted {
                kept.append(offset + 1)
            }
        }
        guard !kept.isEmpty else {
            return scalarMatrix(.error(.calculation))
        }
        var values = [ExcelFormulaValue]()
        if byColumn {
            values.reserveCapacity(source.rowCount * kept.count)
            for row in 1 ... source.rowCount {
                for column in kept {
                    values.append(
                        source.value(row: row, column: column) ?? .blank
                    )
                }
            }
            return ExcelFormulaRangeMatrix(
                rowCount: source.rowCount,
                columnCount: kept.count,
                values: values
            )
        }
        values.reserveCapacity(kept.count * source.columnCount)
        for row in kept {
            for column in 1 ... source.columnCount {
                values.append(
                    source.value(row: row, column: column) ?? .blank
                )
            }
        }
        return ExcelFormulaRangeMatrix(
            rowCount: kept.count,
            columnCount: source.columnCount,
            values: values
        )
    }

    private func arrayArgumentValue(
        _ arguments: [ExcelFormulaExpression],
        at index: Int
    ) -> ExcelFormulaValue? {
        guard arguments.indices.contains(index),
              let matrix = arrayMatrix(arguments[index]),
              matrix.rowCount == 1, matrix.columnCount == 1 else {
            return nil
        }
        return matrix.values[0]
    }

    private func numberArrayArgument(
        _ arguments: [ExcelFormulaExpression],
        at index: Int,
        defaultValue: Double
    ) -> Double? {
        guard arguments.indices.contains(index) else { return defaultValue }
        guard let value = arrayArgumentValue(arguments, at: index) else {
            return nil
        }
        if case .blank = value { return defaultValue }
        guard let number = value.number, number.isFinite else { return nil }
        return number
    }

    private func integerArrayArgument(
        _ arguments: [ExcelFormulaExpression],
        at index: Int,
        defaultValue: Int
    ) -> Int? {
        guard let number = numberArrayArgument(
            arguments,
            at: index,
            defaultValue: Double(defaultValue)
        ), number >= Double(Int.min), number <= Double(Int.max) else {
            return nil
        }
        return Int(number.rounded(.towardZero))
    }

    private func booleanArrayArgument(
        _ arguments: [ExcelFormulaExpression],
        at index: Int,
        defaultValue: Bool
    ) -> Bool? {
        guard arguments.indices.contains(index) else { return defaultValue }
        guard let value = arrayArgumentValue(arguments, at: index) else {
            return nil
        }
        if case .blank = value { return defaultValue }
        return value.boolean
    }

    private func arrayValueKey(_ value: ExcelFormulaValue) -> ArrayValueKey {
        switch value {
        case .number(let number): return .number(number)
        case .text(let text):
            return .text(text.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            ))
        case .boolean(let value): return .boolean(value)
        case .blank: return .blank
        case .error(let error): return .error(error.rawValue)
        }
    }

    private func arraySortComparison(
        _ left: ExcelFormulaValue,
        _ right: ExcelFormulaValue
    ) -> ComparisonResult {
        if let lhs = left.number, let rhs = right.number {
            if lhs == rhs { return .orderedSame }
            return lhs < rhs ? .orderedAscending : .orderedDescending
        }
        let leftRank = arraySortRank(left)
        let rightRank = arraySortRank(right)
        if leftRank != rightRank {
            return leftRank < rightRank ? .orderedAscending : .orderedDescending
        }
        return left.text.compare(
            right.text,
            options: [.caseInsensitive, .numeric]
        )
    }

    private func arraySortRank(_ value: ExcelFormulaValue) -> Int {
        switch value {
        case .number: return 0
        case .text: return 1
        case .boolean: return 2
        case .error: return 3
        case .blank: return 4
        }
    }

    private func qualifiedValue(
        sheetName: String,
        at address: ExcelCellAddress
    ) -> ExcelFormulaValue? {
        if currentSheetName?.caseInsensitiveCompare(sheetName)
            == .orderedSame {
            return value(at: address)
        }
        guard let sheet = worksheet(named: sheetName),
              let cell = sheet.cells[address] else {
            return .blank
        }
        return literalValue(of: cell)
    }

    private func qualifiedRangeMatrix(
        sheetName: String,
        range: ExcelCellRange
    ) -> ExcelFormulaRangeMatrix? {
        let rowCount = range.end.row - range.start.row + 1
        let columnCount = range.end.column - range.start.column + 1
        guard rowCount > 0, columnCount > 0,
              rowCount <= 100_000 / columnCount else { return nil }
        var values = [ExcelFormulaValue]()
        values.reserveCapacity(rowCount * columnCount)
        for row in range.start.row ... range.end.row {
            for column in range.start.column ... range.end.column {
                guard let value = qualifiedValue(
                    sheetName: sheetName,
                    at: ExcelCellAddress(row: row, column: column)
                ) else { return nil }
                values.append(value)
            }
        }
        return ExcelFormulaRangeMatrix(
            rowCount: rowCount,
            columnCount: columnCount,
            values: values
        )
    }

    private func worksheet(named name: String) -> ExcelWorksheet? {
        workbook?.sheets.first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func definedNameExpression(
        _ rawName: String
    ) -> ExcelFormulaExpression? {
        guard let workbook else { return nil }
        let sheetIndex = currentSheetName.flatMap { currentName in
            workbook.sheets.firstIndex {
                $0.name.caseInsensitiveCompare(currentName) == .orderedSame
            }
        }
        let matching = workbook.definedNames.filter {
            $0.name.caseInsensitiveCompare(rawName) == .orderedSame
        }
        let definition = matching.first {
            $0.localSheetIndex == sheetIndex
        } ?? matching.first { $0.localSheetIndex == nil }
        guard let definition else { return nil }
        var formula = definition.formula.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if formula.hasPrefix("=") { formula.removeFirst() }
        guard var parser = ExcelFormulaParser(formula) else { return nil }
        return parser.parse()
    }

    private func structuredReferenceLocation(
        _ reference: String
    ) -> (sheetName: String, range: ExcelCellRange)? {
        guard let opening = reference.firstIndex(of: "["),
              reference.last == "]", let workbook else { return nil }
        let tableName = String(reference[..<opening]).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let tableContext: (sheet: ExcelWorksheet, table: ExcelTable)?
        if tableName.isEmpty {
            guard let currentSheetName,
                  let sheet = worksheet(named: currentSheetName),
                  let address = evaluationStack.last,
                  let table = sheet.tables.first(where: {
                      $0.range.contains(address)
                  }) else { return nil }
            tableContext = (sheet, table)
        } else {
            tableContext = workbook.sheets.lazy.compactMap { sheet in
                sheet.tables.first(where: {
                    $0.name.caseInsensitiveCompare(tableName) == .orderedSame
                }).map { (sheet, $0) }
            }.first
        }
        guard let tableContext else { return nil }
        let sheet = tableContext.sheet
        let table = tableContext.table
        let bracketText = String(reference[opening...])
        let pattern = #"\[([^\[\]]+)\]"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let matches = regex?.matches(
            in: bracketText,
            range: NSRange(bracketText.startIndex..., in: bracketText)
        ) ?? []
        var tokens = matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: bracketText) else {
                return nil
            }
            return String(bracketText[range]).trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }
        if tokens.isEmpty {
            let content = bracketText.dropFirst().dropLast()
            tokens = [String(content)]
        }
        let normalizedTokens = tokens.map {
            $0.uppercased().replacingOccurrences(of: " ", with: "")
        }
        let usesAll = normalizedTokens.contains("#ALL")
        let usesHeaders = normalizedTokens.contains("#HEADERS")
        let usesTotals = normalizedTokens.contains("#TOTALS")
            || normalizedTokens.contains("#TOTALROW")
        let usesThisRow = normalizedTokens.contains("#THISROW")
            || tokens.contains(where: { $0.hasPrefix("@") })

        let headerRows = max(table.headerRowCount, 0)
        let totalsRows = max(table.totalsRowCount, 0)
        let dataStart = table.range.start.row + headerRows
        let dataEnd = table.range.end.row - totalsRows
        let startRow: Int
        let endRow: Int
        if usesAll {
            startRow = table.range.start.row
            endRow = table.range.end.row
        } else if usesHeaders {
            guard headerRows > 0 else { return nil }
            startRow = table.range.start.row
            endRow = table.range.start.row + headerRows - 1
        } else if usesTotals {
            guard totalsRows > 0 else { return nil }
            startRow = table.range.end.row - totalsRows + 1
            endRow = table.range.end.row
        } else if usesThisRow {
            guard let row = evaluationStack.last?.row,
                  row >= dataStart, row <= dataEnd else { return nil }
            startRow = row
            endRow = row
        } else {
            guard dataStart <= dataEnd else { return nil }
            startRow = dataStart
            endRow = dataEnd
        }

        let headerNames: [String]
        if table.columnNames.isEmpty, headerRows > 0 {
            headerNames = (table.range.start.column ... table.range.end.column)
                .map {
                    sheet.cells[ExcelCellAddress(
                        row: table.range.start.row,
                        column: $0
                    )]?.rawValue ?? ""
                }
        } else {
            headerNames = table.columnNames
        }
        let columnTokens = tokens.compactMap { token -> String? in
            var value = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("#") { return nil }
            if value.hasPrefix("@") { value.removeFirst() }
            return value.isEmpty ? nil : value
        }
        let startColumn: Int
        let endColumn: Int
        if let firstName = columnTokens.first,
           let firstIndex = headerNames.firstIndex(where: {
               $0.caseInsensitiveCompare(firstName) == .orderedSame
           }) {
            let lastName = columnTokens.last ?? firstName
            guard let lastIndex = headerNames.firstIndex(where: {
                $0.caseInsensitiveCompare(lastName) == .orderedSame
            }) else { return nil }
            startColumn = table.range.start.column + min(firstIndex, lastIndex)
            endColumn = table.range.start.column + max(firstIndex, lastIndex)
        } else if columnTokens.isEmpty {
            startColumn = table.range.start.column
            endColumn = table.range.end.column
        } else {
            return nil
        }
        return (
            sheet.name,
            ExcelCellRange(
                start: ExcelCellAddress(row: startRow, column: startColumn),
                end: ExcelCellAddress(row: endRow, column: endColumn)
            )
        )
    }

    private func literalValue(of cell: ExcelCell) -> ExcelFormulaValue {
        if cell.cellType == "e" {
            return ExcelFormulaError(excelText: cell.rawValue)
                .map(ExcelFormulaValue.error) ?? .error(.value)
        }
        if cell.cellType == "b" {
            return .boolean(
                cell.rawValue == "1"
                    || cell.rawValue.caseInsensitiveCompare("TRUE")
                        == .orderedSame
            )
        }
        if cell.cellType == nil || cell.cellType == "n",
           let number = Double(cell.rawValue) {
            return .number(number)
        }
        if cell.rawValue.isEmpty { return .blank }
        return .text(cell.rawValue)
    }

    private func evaluate(
        _ expression: ExcelFormulaExpression
    ) -> ExcelFormulaValue? {
        switch expression {
        case .literal(let value):
            return value
        case .cell(let address):
            return value(at: address)
        case .qualifiedCell(let sheetName, let address):
            return qualifiedValue(sheetName: sheetName, at: address)
        case .qualifiedRange(let sheetName, let range):
            return implicitIntersectionAddress(in: range).flatMap {
                qualifiedValue(sheetName: sheetName, at: $0)
            } ?? .error(.value)
        case .name(let name):
            let key = name.uppercased()
            guard resolvingNames.insert(key).inserted else {
                return .error(.reference)
            }
            defer { resolvingNames.remove(key) }
            guard let resolved = definedNameExpression(name) else {
                return .error(.name)
            }
            return evaluate(resolved)
        case .structuredReference(let reference):
            guard let matrix = arrayMatrix(.structuredReference(reference))
            else { return .error(.reference) }
            return matrix.values.first
        case .spill(let anchor):
            return value(at: anchor)
        case .range(let range):
            return implicitIntersectionAddress(in: range).flatMap(value)
                ?? .error(.value)
        case .unary(let operation, let expression):
            guard let value = evaluate(expression) else {
                return nil
            }
            if value.error != nil { return value }
            if operation == "+", !supportsDynamicArrays { return value }
            guard let number = value.number else { return .error(.value) }
            switch operation {
            case "+": return finiteNumber(number)
            case "-": return finiteNumber(-number)
            case "%": return finiteNumber(number / 100)
            default: return nil
            }
        case .binary(let operation, let left, let right):
            guard let leftValue = evaluate(left),
                  let rightValue = evaluate(right) else {
                return nil
            }
            return binary(operation, leftValue, rightValue)
        case .function(let name, let arguments):
            return function(name, arguments)
        }
    }

    private func binary(
        _ operation: String,
        _ left: ExcelFormulaValue,
        _ right: ExcelFormulaValue
    ) -> ExcelFormulaValue? {
        if let error = left.error ?? right.error {
            return .error(error)
        }
        if operation == "&" {
            return .text(left.text + right.text)
        }
        if ["=", "<>", "<", "<=", ">", ">="].contains(operation) {
            return .boolean(compare(left, right, operation: operation))
        }
        guard let lhs = left.number, let rhs = right.number else {
            return .error(.value)
        }
        switch operation {
        case "+": return finiteNumber(lhs + rhs)
        case "-": return finiteNumber(lhs - rhs)
        case "*": return finiteNumber(lhs * rhs)
        case "/":
            return rhs == 0
                ? .error(.divideByZero)
                : finiteNumber(lhs / rhs)
        case "^": return finiteNumber(pow(lhs, rhs))
        default: return nil
        }
    }

    private func finiteNumber(_ value: Double) -> ExcelFormulaValue {
        value.isFinite ? .number(value) : .error(.number)
    }

    private func compare(
        _ left: ExcelFormulaValue,
        _ right: ExcelFormulaValue,
        operation: String
    ) -> Bool {
        let result: ComparisonResult
        switch (left, right) {
        case (.blank, .blank):
            result = .orderedSame
        case (.blank, .number(let rightNumber)):
            result = compareNumbers(0, rightNumber)
        case (.number(let leftNumber), .blank):
            result = compareNumbers(leftNumber, 0)
        case (.blank, .text(let rightText)):
            result = "".compare(rightText, options: [.caseInsensitive])
        case (.text(let leftText), .blank):
            result = leftText.compare("", options: [.caseInsensitive])
        case (.blank, .boolean(let rightBoolean)):
            result = compareBooleans(false, rightBoolean)
        case (.boolean(let leftBoolean), .blank):
            result = compareBooleans(leftBoolean, false)
        case (.number(let lhs), .number(let rhs)):
            result = compareNumbers(lhs, rhs)
        case (.text(let lhs), .text(let rhs)):
            result = lhs.compare(rhs, options: [.caseInsensitive, .numeric])
        case (.boolean(let lhs), .boolean(let rhs)):
            result = compareBooleans(lhs, rhs)
        default:
            let leftRank = comparisonTypeRank(left)
            let rightRank = comparisonTypeRank(right)
            result = leftRank < rightRank
                ? .orderedAscending : .orderedDescending
        }
        switch operation {
        case "=": return result == .orderedSame
        case "<>": return result != .orderedSame
        case "<": return result == .orderedAscending
        case "<=": return result != .orderedDescending
        case ">": return result == .orderedDescending
        case ">=": return result != .orderedAscending
        default: return false
        }
    }

    private func implicitIntersectionAddress(
        in range: ExcelCellRange
    ) -> ExcelCellAddress? {
        guard let formulaAddress = evaluationStack.last else { return nil }
        if range.start == range.end { return range.start }
        if range.contains(formulaAddress) { return formulaAddress }
        if range.start.row == range.end.row,
           formulaAddress.column >= range.start.column,
           formulaAddress.column <= range.end.column {
            return ExcelCellAddress(
                row: range.start.row,
                column: formulaAddress.column
            )
        }
        if range.start.column == range.end.column,
           formulaAddress.row >= range.start.row,
           formulaAddress.row <= range.end.row {
            return ExcelCellAddress(
                row: formulaAddress.row,
                column: range.start.column
            )
        }
        return nil
    }

    private func compareNumbers(
        _ left: Double,
        _ right: Double
    ) -> ComparisonResult {
        left == right
            ? .orderedSame
            : (left < right ? .orderedAscending : .orderedDescending)
    }

    private func compareBooleans(
        _ left: Bool,
        _ right: Bool
    ) -> ComparisonResult {
        left == right
            ? .orderedSame
            : (!left ? .orderedAscending : .orderedDescending)
    }

    private func comparisonTypeRank(_ value: ExcelFormulaValue) -> Int {
        switch value {
        case .number, .blank: return 0
        case .text: return 1
        case .boolean: return 2
        case .error: return 3
        }
    }

    private func function(
        _ name: String,
        _ arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        switch name {
        case "IF":
            guard (2 ... 3).contains(arguments.count),
                  let condition = evaluate(arguments[0]) else {
                return (2 ... 3).contains(arguments.count)
                    ? nil : .error(.value)
            }
            if condition.error != nil { return condition }
            guard let boolean = condition.boolean else {
                return .error(.value)
            }
            if boolean { return evaluate(arguments[1]) }
            return arguments.count == 3
                ? evaluate(arguments[2]) : .boolean(false)
        case "IFS":
            return ifsFunction(arguments: arguments)
        case "SWITCH":
            return switchFunction(arguments: arguments)
        case "CHOOSE":
            return chooseFunction(arguments: arguments)
        case "IFERROR":
            guard arguments.count == 2,
                  let value = evaluate(arguments[0]) else {
                return arguments.count == 2 ? nil : .error(.value)
            }
            return value.error == nil ? value : evaluate(arguments[1])
        case "IFNA":
            guard arguments.count == 2,
                  let value = evaluate(arguments[0]) else {
                return arguments.count == 2 ? nil : .error(.value)
            }
            return value.error == .notAvailable
                ? evaluate(arguments[1]) : value
        case "AND", "OR", "XOR":
            return logicalFunction(name, arguments: arguments)
        case "TRUE":
            return arguments.isEmpty ? .boolean(true) : .error(.value)
        case "FALSE":
            return arguments.isEmpty ? .boolean(false) : .error(.value)
        case "NOT":
            guard arguments.count == 1,
                  let value = evaluate(arguments[0]) else {
                return nil
            }
            if value.error != nil { return value }
            guard let boolean = value.boolean else {
                return .error(.value)
            }
            return .boolean(!boolean)
        case "SUM", "AVERAGE", "COUNT", "COUNTA", "MAX", "MEDIAN",
             "MIN", "PRODUCT":
            return aggregateFunction(name, arguments: arguments)
        case "ABS", "INT", "SIGN", "SQRT":
            return unaryMathFunction(name, arguments: arguments)
        case "ACOS", "ACOSH", "ACOT", "ACOTH", "ASIN", "ASINH",
             "ATAN", "ATAN2", "ATANH", "COS", "COSH", "COT", "COTH",
             "CSC", "CSCH", "DEGREES", "EXP", "LN", "LOG", "LOG10",
             "PI", "RADIANS", "SEC", "SECH", "SIN", "SINH", "SQRTPI",
             "TAN", "TANH":
            return transcendentalFunction(name, arguments: arguments)
        case "MOD", "POWER", "QUOTIENT":
            return binaryMathFunction(name, arguments: arguments)
        case "ROUND", "ROUNDDOWN", "ROUNDUP", "TRUNC":
            return roundingFunction(name, arguments: arguments)
        case "CEILING", "CEILING.MATH", "CEILING.PRECISE", "FLOOR",
             "FLOOR.MATH", "FLOOR.PRECISE", "MROUND":
            return multipleRoundingFunction(name, arguments: arguments)
        case "EVEN", "ODD":
            return parityRoundingFunction(name, arguments: arguments)
        case "COMBIN", "COMBINA", "FACT", "FACTDOUBLE", "PERMUT",
             "PERMUTATIONA":
            return combinatoricsFunction(name, arguments: arguments)
        case "GCD", "LCM":
            return integerDivisorFunction(name, arguments: arguments)
        case "SUMSQ":
            return sumSquaresFunction(arguments: arguments)
        case "LARGE", "SMALL":
            return rankedStatisticFunction(name, arguments: arguments)
        case "RANK.AVG", "RANK.EQ":
            return rankFunction(name, arguments: arguments)
        case "STDEV.P", "STDEV.S", "VAR.P", "VAR.S":
            return dispersionFunction(name, arguments: arguments)
        case "AVEDEV", "DEVSQ", "GEOMEAN", "HARMEAN":
            return descriptiveStatisticFunction(name, arguments: arguments)
        case "CORREL", "COVARIANCE.P", "COVARIANCE.S", "INTERCEPT",
             "PEARSON", "RSQ", "SLOPE", "STEYX":
            return pairedStatisticFunction(name, arguments: arguments)
        case "FISHER", "FISHERINV", "STANDARDIZE":
            return scalarStatisticFunction(name, arguments: arguments)
        case "BASE", "BIN2DEC", "BIN2HEX", "BIN2OCT", "DEC2BIN",
             "DEC2HEX", "DEC2OCT", "DECIMAL", "HEX2BIN", "HEX2DEC",
             "HEX2OCT", "OCT2BIN", "OCT2DEC", "OCT2HEX":
            return numeralSystemFunction(name, arguments: arguments)
        case "DELTA", "GESTEP":
            return comparisonEngineeringFunction(name, arguments: arguments)
        case "SUMPRODUCT":
            return sumProductFunction(arguments: arguments)
        case "SUMX2MY2", "SUMX2PY2", "SUMXMY2":
            return pairedSumFunction(name, arguments: arguments)
        case "SERIESSUM":
            return seriesSumFunction(arguments: arguments)
        case "COUNTBLANK":
            return countBlankFunction(arguments: arguments)
        case "ISBLANK", "ISERR", "ISERROR", "ISLOGICAL", "ISNA",
             "ISNUMBER", "ISTEXT", "N", "NA", "TYPE":
            return informationFunction(name, arguments: arguments)
        case "ISFORMULA":
            return isFormulaFunction(arguments: arguments)
        case "ADDRESS", "COLUMN", "COLUMNS", "FORMULATEXT", "ROW",
             "ROWS":
            return referenceInformationFunction(name, arguments: arguments)
        case "FV", "NPER", "PMT", "PV":
            return annuityFunction(name, arguments: arguments)
        case "NPV":
            return netPresentValueFunction(arguments: arguments)
        case "LEN", "LEFT", "REPT", "RIGHT":
            return textFunction(name, arguments: arguments)
        case "MID", "FIND", "SEARCH", "SUBSTITUTE":
            return advancedTextFunction(name, arguments: arguments)
        case "CHAR", "CODE", "DOLLAR", "EXACT", "FIXED",
             "NUMBERVALUE", "T", "TEXT", "TEXTAFTER", "TEXTBEFORE",
             "UNICHAR", "UNICODE", "VALUE":
            return textConversionFunction(name, arguments: arguments)
        case "CONCAT", "CONCATENATE", "TEXTJOIN":
            return textJoiningFunction(name, arguments: arguments)
        case "CLEAN", "LOWER", "PROPER", "REPLACE", "TRIM", "UPPER":
            return textCleanupFunction(name, arguments: arguments)
        case "DATE", "DATEDIF", "DAY", "DAYS", "EDATE", "EOMONTH",
             "HOUR", "ISOWEEKNUM", "MINUTE", "MONTH", "NETWORKDAYS",
             "NETWORKDAYS.INTL", "NOW", "SECOND", "TIME", "TODAY",
             "WEEKDAY", "WEEKNUM", "WORKDAY", "WORKDAY.INTL", "YEAR":
            return dateFunction(name, arguments: arguments)
        case "HLOOKUP", "INDEX", "MATCH", "VLOOKUP", "XLOOKUP",
             "XMATCH":
            return lookupFunction(name, arguments: arguments)
        case "AVERAGEIF", "AVERAGEIFS", "COUNTIF", "COUNTIFS",
             "MAXIFS", "MINIFS", "SUMIF", "SUMIFS":
            return conditionalAggregateFunction(
                name,
                arguments: arguments
            )
        default:
            return nil
        }
    }

    private func ifsFunction(
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard arguments.count >= 2,
              arguments.count <= 254,
              arguments.count.isMultiple(of: 2) else {
            return .error(.value)
        }
        var index = 0
        while index < arguments.count {
            guard let condition = evaluate(arguments[index]) else {
                return nil
            }
            if condition.error != nil { return condition }
            guard let boolean = condition.boolean else {
                return .error(.value)
            }
            if boolean { return evaluate(arguments[index + 1]) }
            index += 2
        }
        return .error(.notAvailable)
    }

    private func switchFunction(
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard arguments.count >= 3, arguments.count <= 254,
              let expression = evaluate(arguments[0]) else {
            return arguments.count >= 3 && arguments.count <= 254
                ? nil : .error(.value)
        }
        if expression.error != nil { return expression }

        let remainingCount = arguments.count - 1
        let hasDefault = !remainingCount.isMultiple(of: 2)
        let pairEnd = hasDefault
            ? arguments.count - 1 : arguments.count
        var index = 1
        while index < pairEnd {
            guard let candidate = evaluate(arguments[index]) else {
                return nil
            }
            if candidate.error != nil { return candidate }
            if compare(expression, candidate, operation: "=") {
                return evaluate(arguments[index + 1])
            }
            index += 2
        }
        return hasDefault
            ? evaluate(arguments.last!) : .error(.notAvailable)
    }

    private func chooseFunction(
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard (2 ... 255).contains(arguments.count),
              let indexValue = evaluate(arguments[0]) else {
            return (2 ... 255).contains(arguments.count)
                ? nil : .error(.value)
        }
        if indexValue.error != nil { return indexValue }
        guard let number = indexValue.number, number.isFinite else {
            return .error(.value)
        }
        let index = number.rounded(.towardZero)
        guard index >= 1, index < Double(arguments.count) else {
            return .error(.value)
        }
        return evaluate(arguments[Int(index)])
    }

    private func isFormulaFunction(
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard arguments.count == 1,
              let range = cellRange(arguments[0]) else {
            return .error(.value)
        }
        return .boolean(cells[range.start]?.formula?.isEmpty == false)
    }

    private func referenceInformationFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        switch name {
        case "ROW", "COLUMN":
            guard arguments.count <= 1 else { return .error(.value) }
            let address: ExcelCellAddress
            if let argument = arguments.first {
                guard let range = cellRange(argument) else {
                    return .error(.value)
                }
                address = range.start
            } else if let currentAddress = evaluationStack.last {
                address = currentAddress
            } else {
                return nil
            }
            return .number(Double(
                name == "ROW" ? address.row : address.column
            ))
        case "ROWS", "COLUMNS":
            guard arguments.count == 1 else { return .error(.value) }
            if let range = cellRange(arguments[0]) {
                let count = name == "ROWS"
                    ? range.end.row - range.start.row + 1
                    : range.end.column - range.start.column + 1
                return .number(Double(count))
            }
            return evaluate(arguments[0]).map { value in
                value.error.map(ExcelFormulaValue.error) ?? .number(1)
            }
        case "FORMULATEXT":
            guard arguments.count == 1,
                  let range = cellRange(arguments[0]),
                  let formula = cells[range.start]?.formula,
                  !formula.isEmpty else {
                return arguments.count == 1
                    ? .error(.notAvailable) : .error(.value)
            }
            return checkedText(formula.hasPrefix("=") ? formula : "=" + formula)
        case "ADDRESS":
            return addressFunction(arguments: arguments)
        default:
            return nil
        }
    }

    private func addressFunction(
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard (2 ... 5).contains(arguments.count) else {
            return .error(.value)
        }
        guard let rowValue = evaluate(arguments[0]),
              let columnValue = evaluate(arguments[1]) else {
            return nil
        }
        if rowValue.error != nil { return rowValue }
        if columnValue.error != nil { return columnValue }
        guard let rowNumber = rowValue.number,
              let columnNumber = columnValue.number,
              rowNumber.isFinite, columnNumber.isFinite else {
            return .error(.value)
        }
        let row = rowNumber.rounded(.towardZero)
        let column = columnNumber.rounded(.towardZero)
        guard row >= 1, row <= 1_048_576,
              column >= 1, column <= 16_384 else {
            return .error(.value)
        }

        var absoluteType = 1
        if arguments.count >= 3, !isOmitted(arguments[2]) {
            guard let value = evaluate(arguments[2]) else { return nil }
            if value.error != nil { return value }
            guard let number = value.number, number.isFinite else {
                return .error(.value)
            }
            absoluteType = Int(number.rounded(.towardZero))
        }
        guard (1 ... 4).contains(absoluteType) else {
            return .error(.value)
        }

        var usesA1 = true
        if arguments.count >= 4, !isOmitted(arguments[3]) {
            guard let value = evaluate(arguments[3]) else { return nil }
            if value.error != nil { return value }
            guard let boolean = value.boolean else {
                return .error(.value)
            }
            usesA1 = boolean
        }

        let rowIsAbsolute = absoluteType == 1 || absoluteType == 2
        let columnIsAbsolute = absoluteType == 1 || absoluteType == 3
        let address: String
        if usesA1 {
            address = (columnIsAbsolute ? "$" : "")
                + ExcelCellAddress.columnName(Int(column))
                + (rowIsAbsolute ? "$" : "")
                + String(Int(row))
        } else {
            let rowText = rowIsAbsolute
                ? "R\(Int(row))" : "R[\(Int(row))]"
            let columnText = columnIsAbsolute
                ? "C\(Int(column))" : "C[\(Int(column))]"
            address = rowText + columnText
        }

        guard arguments.count == 5, !isOmitted(arguments[4]) else {
            return .text(address)
        }
        guard let sheetValue = evaluate(arguments[4]) else { return nil }
        if sheetValue.error != nil { return sheetValue }
        let sheet = sheetValue.text
        guard !sheet.isEmpty else { return .text(address) }
        let simpleSheet = sheet.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
                || $0.value == 95
                || $0.value == 46
                || $0.value == 91
                || $0.value == 93
        }
        let sheetPrefix = simpleSheet
            ? sheet
            : "'" + sheet.replacingOccurrences(of: "'", with: "''") + "'"
        return checkedText(sheetPrefix + "!" + address)
    }

    private func annuityFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard (3 ... 5).contains(arguments.count) else {
            return .error(.value)
        }
        var values = [Double]()
        for index in 0 ..< 5 {
            if index >= arguments.count || isOmitted(arguments[index]) {
                values.append(0)
                continue
            }
            guard let value = evaluate(arguments[index]) else { return nil }
            if value.error != nil { return value }
            guard let number = value.number, number.isFinite else {
                return .error(.value)
            }
            values.append(number)
        }

        let rate = values[0]
        let typeNumber = values[4].rounded(.towardZero)
        guard typeNumber == 0 || typeNumber == 1 else {
            return .error(.value)
        }
        let paymentType = typeNumber

        switch name {
        case "FV":
            let periods = values[1]
            let payment = values[2]
            let presentValue = values[3]
            if rate == 0 {
                return finiteNumber(-(presentValue + payment * periods))
            }
            let growth = pow(1 + rate, periods)
            guard growth.isFinite else { return .error(.number) }
            let paymentTerm = payment * (1 + rate * paymentType)
                * (growth - 1) / rate
            return finiteNumber(-(presentValue * growth + paymentTerm))
        case "PV":
            let periods = values[1]
            let payment = values[2]
            let futureValue = values[3]
            if rate == 0 {
                return finiteNumber(-(futureValue + payment * periods))
            }
            let growth = pow(1 + rate, periods)
            guard growth.isFinite else { return .error(.number) }
            guard growth != 0 else { return .error(.divideByZero) }
            let paymentTerm = payment * (1 + rate * paymentType)
                * (growth - 1) / rate
            return finiteNumber(-(futureValue + paymentTerm) / growth)
        case "PMT":
            let periods = values[1]
            let presentValue = values[2]
            let futureValue = values[3]
            if rate == 0 {
                guard periods != 0 else {
                    return .error(.divideByZero)
                }
                return finiteNumber(-(presentValue + futureValue) / periods)
            }
            let growth = pow(1 + rate, periods)
            guard growth.isFinite else { return .error(.number) }
            let denominator = (1 + rate * paymentType)
                * (growth - 1) / rate
            guard denominator != 0 else {
                return .error(.divideByZero)
            }
            return finiteNumber(
                -(futureValue + presentValue * growth) / denominator
            )
        case "NPER":
            let payment = values[1]
            let presentValue = values[2]
            let futureValue = values[3]
            if rate == 0 {
                guard payment != 0 else {
                    return .error(.divideByZero)
                }
                return finiteNumber(-(presentValue + futureValue) / payment)
            }
            guard 1 + rate > 0 else { return .error(.number) }
            let adjustedPayment = payment * (1 + rate * paymentType)
            let numerator = adjustedPayment - futureValue * rate
            let denominator = presentValue * rate + adjustedPayment
            guard denominator != 0 else {
                return .error(.divideByZero)
            }
            let ratio = numerator / denominator
            guard ratio > 0 else { return .error(.number) }
            return finiteNumber(log(ratio) / log(1 + rate))
        default:
            return nil
        }
    }

    private func netPresentValueFunction(
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard (2 ... 255).contains(arguments.count),
              let rateValue = evaluate(arguments[0]) else {
            return (2 ... 255).contains(arguments.count)
                ? nil : .error(.value)
        }
        if rateValue.error != nil { return rateValue }
        guard let rate = rateValue.number, rate.isFinite else {
            return .error(.value)
        }
        guard rate != -1 else { return .error(.divideByZero) }

        var result = 0.0
        var period = 0
        for argument in arguments.dropFirst() {
            guard let items = expandedValues(argument) else { return nil }
            for item in items {
                if let error = item.value.error {
                    if item.comesFromReference { continue }
                    return .error(error)
                }
                let cashFlow: Double
                if item.comesFromReference {
                    guard case .number(let number) = item.value else {
                        continue
                    }
                    cashFlow = number
                } else if let number = item.value.number {
                    cashFlow = number
                } else {
                    continue
                }
                period += 1
                let divisor = pow(1 + rate, Double(period))
                guard divisor.isFinite else { return .error(.number) }
                guard divisor != 0 else {
                    return .error(.divideByZero)
                }
                result += cashFlow / divisor
                guard result.isFinite else { return .error(.number) }
            }
        }
        return .number(result)
    }

    private func informationFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        if name == "NA" {
            return arguments.isEmpty
                ? .error(.notAvailable) : .error(.value)
        }
        guard arguments.count == 1 else { return .error(.value) }

        if name == "TYPE", case .range = arguments[0] {
            return .number(64)
        }
        guard let value = evaluate(arguments[0]) else { return nil }
        switch name {
        case "ISBLANK":
            if case .blank = value { return .boolean(true) }
            return .boolean(false)
        case "ISERR":
            guard case .error(let error) = value else {
                return .boolean(false)
            }
            return .boolean(error != .notAvailable)
        case "ISERROR":
            return .boolean(value.error != nil)
        case "ISLOGICAL":
            if case .boolean = value { return .boolean(true) }
            return .boolean(false)
        case "ISNA":
            return .boolean(value.error == .notAvailable)
        case "ISNUMBER":
            if case .number = value { return .boolean(true) }
            return .boolean(false)
        case "ISTEXT":
            if case .text = value { return .boolean(true) }
            return .boolean(false)
        case "N":
            switch value {
            case .number:
                return value
            case .boolean(let boolean):
                return .number(boolean ? 1 : 0)
            case .error:
                return value
            case .text, .blank:
                return .number(0)
            }
        case "TYPE":
            switch value {
            case .number, .blank: return .number(1)
            case .text: return .number(2)
            case .boolean: return .number(4)
            case .error: return .number(16)
            }
        default:
            return nil
        }
    }

    private func conditionalAggregateFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        switch name {
        case "AVERAGEIF":
            guard (2 ... 3).contains(arguments.count),
                  let criteriaRange = rangeMatrix(arguments[0]),
                  let criterionValue = evaluate(arguments[1]) else {
                return (2 ... 3).contains(arguments.count)
                    ? nil : .error(.value)
            }
            if criterionValue.error != nil { return criterionValue }
            let averageRange: ExcelFormulaRangeMatrix
            if arguments.count == 3 {
                guard let matrix = rangeMatrix(
                    startingAt: arguments[2],
                    rowCount: criteriaRange.rowCount,
                    columnCount: criteriaRange.columnCount
                ) else {
                    return nil
                }
                averageRange = matrix
            } else {
                averageRange = criteriaRange
            }
            let criterion = criterion(
                from: criterionValue,
                emptyReferenceIsZero: isEmptyReference(
                    arguments[1],
                    value: criterionValue
                )
            )
            return conditionalStatistic(
                "AVERAGEIFS",
                valueRange: averageRange,
                pairs: [(criteriaRange, criterion)]
            )
        case "AVERAGEIFS", "MAXIFS", "MINIFS":
            let pairLimit = name == "AVERAGEIFS" ? 127 : 126
            guard arguments.count >= 3,
                  !arguments.count.isMultiple(of: 2),
                  (arguments.count - 1) / 2 <= pairLimit,
                  let valueRange = rangeMatrix(arguments[0]) else {
                return .error(.value)
            }
            guard let pairs = criteriaPairs(
                Array(arguments.dropFirst())
            ) else {
                return nil
            }
            if let error = pairs.compactMap(\.error).first {
                return .error(error)
            }
            guard pairs.allSatisfy({
                $0.range.rowCount == valueRange.rowCount
                    && $0.range.columnCount == valueRange.columnCount
            }) else {
                return .error(.value)
            }
            return conditionalStatistic(
                name,
                valueRange: valueRange,
                pairs: pairs.map { ($0.range, $0.criterion) }
            )
        case "COUNTIF":
            guard arguments.count == 2,
                  let range = rangeMatrix(arguments[0]),
                  let criterionValue = evaluate(arguments[1]) else {
                return arguments.count == 2 ? nil : .error(.value)
            }
            let criterion = criterion(
                from: criterionValue,
                emptyReferenceIsZero: isEmptyReference(
                    arguments[1],
                    value: criterionValue
                )
            )
            let count = range.values.reduce(into: 0) { result, value in
                if matches(value, criterion: criterion) { result += 1 }
            }
            return .number(Double(count))
        case "COUNTIFS":
            guard arguments.count >= 2,
                  arguments.count.isMultiple(of: 2),
                  arguments.count / 2 <= 127 else {
                return .error(.value)
            }
            guard let pairs = criteriaPairs(arguments) else { return nil }
            if let error = pairs.compactMap(\.error).first {
                return .error(error)
            }
            guard let first = pairs.first?.range,
                  pairs.allSatisfy({
                      $0.range.rowCount == first.rowCount
                          && $0.range.columnCount == first.columnCount
                  }) else {
                return .error(.value)
            }
            let count = first.values.indices.reduce(into: 0) {
                result, index in
                if pairs.allSatisfy({ pair in
                    matches(
                        pair.range.values[index],
                        criterion: pair.criterion
                    )
                }) {
                    result += 1
                }
            }
            return .number(Double(count))
        case "SUMIF":
            guard (2 ... 3).contains(arguments.count),
                  let criteriaRange = rangeMatrix(arguments[0]),
                  let criterionValue = evaluate(arguments[1]) else {
                return (2 ... 3).contains(arguments.count)
                    ? nil : .error(.value)
            }
            if criterionValue.error != nil { return criterionValue }
            let sumRange: ExcelFormulaRangeMatrix
            if arguments.count == 3 {
                guard let matrix = rangeMatrix(
                    startingAt: arguments[2],
                    rowCount: criteriaRange.rowCount,
                    columnCount: criteriaRange.columnCount
                ) else {
                    return nil
                }
                sumRange = matrix
            } else {
                sumRange = criteriaRange
            }
            let criterion = criterion(
                from: criterionValue,
                emptyReferenceIsZero: isEmptyReference(
                    arguments[1],
                    value: criterionValue
                )
            )
            return conditionalSum(
                sumRange: sumRange,
                pairs: [(criteriaRange, criterion)]
            )
        case "SUMIFS":
            guard arguments.count >= 3,
                  !arguments.count.isMultiple(of: 2),
                  (arguments.count - 1) / 2 <= 127,
                  let sumRange = rangeMatrix(arguments[0]) else {
                return arguments.count >= 3
                    && !arguments.count.isMultiple(of: 2)
                    ? nil : .error(.value)
            }
            guard let pairs = criteriaPairs(
                Array(arguments.dropFirst())
            ) else {
                return nil
            }
            if let error = pairs.compactMap(\.error).first {
                return .error(error)
            }
            guard pairs.allSatisfy({
                $0.range.rowCount == sumRange.rowCount
                    && $0.range.columnCount == sumRange.columnCount
            }) else {
                return .error(.value)
            }
            return conditionalSum(
                sumRange: sumRange,
                pairs: pairs.map { ($0.range, $0.criterion) }
            )
        default:
            return nil
        }
    }

    private func conditionalStatistic(
        _ name: String,
        valueRange: ExcelFormulaRangeMatrix,
        pairs: [(ExcelFormulaRangeMatrix, Criterion)]
    ) -> ExcelFormulaValue {
        var numbers = [Double]()
        for index in valueRange.values.indices where pairs.allSatisfy({
            matches($0.0.values[index], criterion: $0.1)
        }) {
            switch valueRange.values[index] {
            case .number(let number):
                numbers.append(number)
            case .error(let error):
                return .error(error)
            case .boolean, .text, .blank:
                continue
            }
        }
        switch name {
        case "AVERAGEIFS":
            guard !numbers.isEmpty else { return .error(.divideByZero) }
            return finiteNumber(
                numbers.reduce(0, +) / Double(numbers.count)
            )
        case "MAXIFS":
            return .number(numbers.max() ?? 0)
        case "MINIFS":
            return .number(numbers.min() ?? 0)
        default:
            return .error(.value)
        }
    }

    private func criteriaPairs(
        _ arguments: [ExcelFormulaExpression]
    ) -> [(range: ExcelFormulaRangeMatrix, criterion: Criterion,
           error: ExcelFormulaError?)]? {
        var pairs = [(ExcelFormulaRangeMatrix, Criterion,
                      ExcelFormulaError?)]()
        for index in stride(from: 0, to: arguments.count, by: 2) {
            guard let range = rangeMatrix(arguments[index]),
                  let value = evaluate(arguments[index + 1]) else {
                return nil
            }
            pairs.append((
                range,
                criterion(
                    from: value,
                    emptyReferenceIsZero: isEmptyReference(
                        arguments[index + 1],
                        value: value
                    )
                ),
                value.error
            ))
        }
        return pairs
    }

    private func criterion(
        from value: ExcelFormulaValue,
        emptyReferenceIsZero: Bool
    ) -> Criterion {
        if emptyReferenceIsZero {
            return Criterion(operation: .equal, operand: .number(0))
        }
        guard case .text(let text) = value else {
            return Criterion(operation: .equal, operand: value)
        }
        let operations: [(String, CriterionOperation)] = [
            (">=", .greaterOrEqual),
            ("<=", .lessOrEqual),
            ("<>", .notEqual),
            (">", .greater),
            ("<", .less),
            ("=", .equal),
        ]
        let match = operations.first { text.hasPrefix($0.0) }
        let operation = match?.1 ?? .equal
        let operandText = match.map {
            String(text.dropFirst($0.0.count))
        } ?? text
        let trimmed = operandText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let operand: ExcelFormulaValue
        if trimmed.isEmpty {
            operand = .blank
        } else if let number = Double(trimmed) {
            operand = .number(number)
        } else if trimmed.caseInsensitiveCompare("TRUE") == .orderedSame {
            operand = .boolean(true)
        } else if trimmed.caseInsensitiveCompare("FALSE") == .orderedSame {
            operand = .boolean(false)
        } else {
            operand = .text(operandText)
        }
        return Criterion(operation: operation, operand: operand)
    }

    private func isEmptyReference(
        _ expression: ExcelFormulaExpression,
        value: ExcelFormulaValue
    ) -> Bool {
        guard case .blank = value,
              case .cell = expression else {
            return false
        }
        return true
    }

    private func matches(
        _ candidate: ExcelFormulaValue,
        criterion: Criterion
    ) -> Bool {
        let candidateIsBlank: Bool
        switch candidate {
        case .blank, .text(""):
            candidateIsBlank = true
        default:
            candidateIsBlank = false
        }

        if case .blank = criterion.operand {
            switch criterion.operation {
            case .equal: return candidateIsBlank
            case .notEqual: return !candidateIsBlank
            default: return false
            }
        }
        guard !candidateIsBlank else { return false }

        let result: ComparisonResult?
        switch criterion.operand {
        case .number(let operand):
            guard let number = candidate.number else { return false }
            result = number == operand ? .orderedSame
                : (number < operand ? .orderedAscending : .orderedDescending)
        case .text(let pattern):
            if criterion.operation == .equal
                || criterion.operation == .notEqual {
                let matched: Bool
                switch candidate {
                case .text(let text):
                    matched = wildcardLookupMatch(
                        pattern: pattern,
                        text: text
                    )
                case .error(let error):
                    matched = wildcardLookupMatch(
                        pattern: pattern,
                        text: error.rawValue
                    )
                default:
                    matched = false
                }
                return criterion.operation == .equal ? matched : !matched
            }
            guard case .text(let text) = candidate else { return false }
            result = text.compare(pattern, options: [.caseInsensitive])
        case .boolean(let operand):
            guard case .boolean(let boolean) = candidate else {
                return criterion.operation == .notEqual
            }
            result = boolean == operand ? .orderedSame
                : (!boolean ? .orderedAscending : .orderedDescending)
        case .error(let operand):
            guard case .error(let error) = candidate else {
                return criterion.operation == .notEqual
            }
            result = error == operand ? .orderedSame : .orderedAscending
        case .blank:
            return false
        }
        guard let result else { return false }
        switch criterion.operation {
        case .equal: return result == .orderedSame
        case .notEqual: return result != .orderedSame
        case .less: return result == .orderedAscending
        case .lessOrEqual: return result != .orderedDescending
        case .greater: return result == .orderedDescending
        case .greaterOrEqual: return result != .orderedAscending
        }
    }

    private func conditionalSum(
        sumRange: ExcelFormulaRangeMatrix,
        pairs: [(ExcelFormulaRangeMatrix, Criterion)]
    ) -> ExcelFormulaValue {
        var result = 0.0
        for index in sumRange.values.indices where pairs.allSatisfy({
            matches($0.0.values[index], criterion: $0.1)
        }) {
            switch sumRange.values[index] {
            case .number(let number):
                result += number
            case .boolean(let value):
                result += value ? 1 : 0
            case .error(let error):
                return .error(error)
            case .text, .blank:
                continue
            }
            guard result.isFinite else { return .error(.number) }
        }
        return .number(result)
    }

    private func lookupFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        switch name {
        case "HLOOKUP":
            return horizontalLookupFunction(arguments: arguments)
        case "INDEX":
            return indexFunction(arguments: arguments)
        case "MATCH":
            return matchFunction(arguments: arguments)
        case "VLOOKUP":
            return verticalLookupFunction(arguments: arguments)
        case "XLOOKUP":
            return xLookupFunction(arguments: arguments)
        case "XMATCH":
            return xMatchFunction(arguments: arguments)
        default:
            return nil
        }
    }

    private func horizontalLookupFunction(
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard (3 ... 4).contains(arguments.count),
              let lookupValue = evaluate(arguments[0]),
              let table = rangeMatrix(arguments[1]),
              let rowValue = evaluate(arguments[2]) else {
            return nil
        }
        if let error = lookupValue.error ?? rowValue.error {
            return .error(error)
        }
        guard let row = lookupInteger(rowValue) else {
            return .error(.value)
        }
        guard row >= 1 else { return .error(.value) }
        guard row <= table.rowCount else {
            return .error(.reference)
        }
        var approximate = true
        if arguments.count == 4 {
            guard let rangeLookup = evaluate(arguments[3]) else { return nil }
            if rangeLookup.error != nil { return rangeLookup }
            guard let boolean = rangeLookup.boolean else {
                return .error(.value)
            }
            approximate = boolean
        }
        let firstRow = (1 ... table.columnCount).compactMap {
            table.value(row: 1, column: $0)
        }
        let index = approximate
            ? approximateLookupIndex(
                lookupValue,
                in: firstRow,
                nextSmaller: true,
                preferLastEqual: true
            )
            : exactLookupIndex(
                lookupValue,
                in: firstRow,
                wildcard: true,
                reversed: false
            )
        guard let index,
              let result = table.value(row: row, column: index + 1) else {
            return .error(.notAvailable)
        }
        return result
    }

    private func indexFunction(
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard (2 ... 3).contains(arguments.count),
              let matrix = rangeMatrix(arguments[0]),
              let rowValue = evaluate(arguments[1]) else {
            return nil
        }
        if rowValue.error != nil { return rowValue }
        guard let rowNumber = lookupInteger(rowValue) else {
            return .error(.value)
        }
        var columnNumber = 1
        if arguments.count == 3 {
            guard let columnValue = evaluate(arguments[2]) else {
                return nil
            }
            if columnValue.error != nil { return columnValue }
            guard let parsedColumn = lookupInteger(columnValue) else {
                return .error(.value)
            }
            columnNumber = parsedColumn
        }
        guard rowNumber != 0, columnNumber != 0 else {
            return nil
        }
        guard rowNumber > 0, columnNumber > 0,
              let result = matrix.value(
                  row: rowNumber,
                  column: columnNumber
              ) else {
            return .error(.reference)
        }
        return result
    }

    private func matchFunction(
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard (2 ... 3).contains(arguments.count),
              let lookupValue = evaluate(arguments[0]),
              let values = rangeMatrix(arguments[1])?.vectorValues else {
            return nil
        }
        if lookupValue.error != nil { return lookupValue }
        var matchType = 1
        if arguments.count == 3 {
            guard let matchValue = evaluate(arguments[2]) else { return nil }
            if matchValue.error != nil { return matchValue }
            guard let parsedType = lookupInteger(matchValue),
                  [-1, 0, 1].contains(parsedType) else {
                return .error(.notAvailable)
            }
            matchType = parsedType
        }
        let index: Int?
        if matchType == 0 {
            index = exactLookupIndex(
                lookupValue,
                in: values,
                wildcard: true,
                reversed: false
            )
        } else {
            index = approximateLookupIndex(
                lookupValue,
                in: values,
                nextSmaller: matchType == 1,
                preferLastEqual: true
            )
        }
        guard let index else { return .error(.notAvailable) }
        return .number(Double(index + 1))
    }

    private func verticalLookupFunction(
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard (3 ... 4).contains(arguments.count),
              let lookupValue = evaluate(arguments[0]),
              let table = rangeMatrix(arguments[1]),
              let columnValue = evaluate(arguments[2]) else {
            return nil
        }
        if let error = lookupValue.error ?? columnValue.error {
            return .error(error)
        }
        guard let column = lookupInteger(columnValue) else {
            return .error(.value)
        }
        guard column >= 1 else { return .error(.value) }
        guard column <= table.columnCount else {
            return .error(.reference)
        }
        var approximate = true
        if arguments.count == 4 {
            guard let rangeLookup = evaluate(arguments[3]) else { return nil }
            if rangeLookup.error != nil { return rangeLookup }
            guard let boolean = rangeLookup.boolean else {
                return .error(.value)
            }
            approximate = boolean
        }
        let firstColumn = (1 ... table.rowCount).compactMap {
            table.value(row: $0, column: 1)
        }
        let index = approximate
            ? approximateLookupIndex(
                lookupValue,
                in: firstColumn,
                nextSmaller: true,
                preferLastEqual: true
            )
            : exactLookupIndex(
                lookupValue,
                in: firstColumn,
                wildcard: true,
                reversed: false
            )
        guard let index,
              let result = table.value(row: index + 1, column: column) else {
            return .error(.notAvailable)
        }
        return result
    }

    private func xLookupFunction(
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard (3 ... 6).contains(arguments.count),
              let lookupValue = evaluate(arguments[0]),
              let lookupValues = rangeMatrix(arguments[1])?.vectorValues,
              let returnValues = rangeMatrix(arguments[2])?.vectorValues else {
            return nil
        }
        if lookupValue.error != nil { return lookupValue }
        guard lookupValues.count == returnValues.count else {
            return .error(.value)
        }
        var matchMode = 0
        if arguments.count >= 5 {
            guard let modeValue = evaluate(arguments[4]) else { return nil }
            if modeValue.error != nil { return modeValue }
            guard let parsedMode = lookupInteger(modeValue),
                  [-1, 0, 1, 2].contains(parsedMode) else {
                return .error(.value)
            }
            matchMode = parsedMode
        }
        var searchMode = 1
        if arguments.count >= 6 {
            guard let searchValue = evaluate(arguments[5]) else { return nil }
            if searchValue.error != nil { return searchValue }
            guard let parsedSearch = lookupInteger(searchValue),
                  [-2, -1, 1, 2].contains(parsedSearch) else {
                return .error(.value)
            }
            searchMode = parsedSearch
        }
        let index = modernLookupIndex(
            lookupValue,
            in: lookupValues,
            matchMode: matchMode,
            searchMode: searchMode
        )
        if let index { return returnValues[index] }
        if arguments.count >= 4 {
            return evaluate(arguments[3])
        }
        return .error(.notAvailable)
    }

    private func xMatchFunction(
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard (2 ... 4).contains(arguments.count),
              let lookupValue = evaluate(arguments[0]),
              let matrix = rangeMatrix(arguments[1]) else {
            return (2 ... 4).contains(arguments.count)
                ? nil : .error(.value)
        }
        if lookupValue.error != nil { return lookupValue }
        guard let lookupValues = matrix.vectorValues else {
            return .error(.value)
        }
        var matchMode = 0
        if arguments.count >= 3 {
            guard let modeValue = evaluate(arguments[2]) else { return nil }
            if modeValue.error != nil { return modeValue }
            guard let parsedMode = lookupInteger(modeValue),
                  [-1, 0, 1, 2].contains(parsedMode) else {
                return .error(.value)
            }
            matchMode = parsedMode
        }
        var searchMode = 1
        if arguments.count == 4 {
            guard let searchValue = evaluate(arguments[3]) else { return nil }
            if searchValue.error != nil { return searchValue }
            guard let parsedSearch = lookupInteger(searchValue),
                  [-2, -1, 1, 2].contains(parsedSearch) else {
                return .error(.value)
            }
            searchMode = parsedSearch
        }
        guard let index = modernLookupIndex(
            lookupValue,
            in: lookupValues,
            matchMode: matchMode,
            searchMode: searchMode
        ) else {
            return .error(.notAvailable)
        }
        return .number(Double(index + 1))
    }

    private func modernLookupIndex(
        _ lookupValue: ExcelFormulaValue,
        in values: [ExcelFormulaValue],
        matchMode: Int,
        searchMode: Int
    ) -> Int? {
        if abs(searchMode) == 2, matchMode != 2 {
            return binaryLookupIndex(
                lookupValue,
                in: values,
                matchMode: matchMode,
                ascending: searchMode == 2
            )
        }
        let reversed = searchMode == -1 || searchMode == -2
        if let exact = exactLookupIndex(
            lookupValue,
            in: values,
            wildcard: matchMode == 2,
            reversed: reversed
        ) {
            return exact
        }
        guard matchMode == -1 || matchMode == 1 else { return nil }
        return approximateLookupIndex(
            lookupValue,
            in: values,
            nextSmaller: matchMode == -1,
            preferLastEqual: reversed
        )
    }

    private func binaryLookupIndex(
        _ lookupValue: ExcelFormulaValue,
        in values: [ExcelFormulaValue],
        matchMode: Int,
        ascending: Bool
    ) -> Int? {
        var lower = 0
        var upper = values.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            guard let comparison = lookupComparison(
                values[middle],
                lookupValue
            ) else {
                return nil
            }
            let belongsBeforeLookup = ascending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
            if belongsBeforeLookup {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        if values.indices.contains(lower),
           exactLookupMatch(
               lookupValue,
               values[lower],
               wildcard: false
           ) {
            return lower
        }
        switch (ascending, matchMode) {
        case (_, 0):
            return nil
        case (true, -1):
            return lower > 0 ? lower - 1 : nil
        case (true, 1):
            return values.indices.contains(lower) ? lower : nil
        case (false, -1):
            return values.indices.contains(lower) ? lower : nil
        case (false, 1):
            return lower > 0 ? lower - 1 : nil
        default:
            return nil
        }
    }

    private func lookupInteger(_ value: ExcelFormulaValue) -> Int? {
        guard let number = value.number, number.isFinite,
              number >= Double(Int.min / 2),
              number <= Double(Int.max / 2) else {
            return nil
        }
        return Int(number.rounded(.towardZero))
    }

    private func exactLookupIndex(
        _ lookupValue: ExcelFormulaValue,
        in values: [ExcelFormulaValue],
        wildcard: Bool,
        reversed: Bool
    ) -> Int? {
        let indices: AnySequence<Int> = reversed
            ? AnySequence(values.indices.reversed())
            : AnySequence(values.indices)
        for index in indices where exactLookupMatch(
            lookupValue,
            values[index],
            wildcard: wildcard
        ) {
            return index
        }
        return nil
    }

    private func approximateLookupIndex(
        _ lookupValue: ExcelFormulaValue,
        in values: [ExcelFormulaValue],
        nextSmaller: Bool,
        preferLastEqual: Bool
    ) -> Int? {
        var bestIndex: Int?
        for index in values.indices {
            guard values[index].error == nil,
                  let comparison = lookupComparison(
                      values[index],
                      lookupValue
                  ) else {
                continue
            }
            let eligible = nextSmaller
                ? comparison != .orderedDescending
                : comparison != .orderedAscending
            guard eligible else { continue }
            guard let currentBest = bestIndex,
                  let bestComparison = lookupComparison(
                      values[index],
                      values[currentBest]
                  ) else {
                bestIndex = index
                continue
            }
            if nextSmaller {
                if bestComparison == .orderedDescending
                    || (bestComparison == .orderedSame && preferLastEqual) {
                    bestIndex = index
                }
            } else if bestComparison == .orderedAscending
                        || (bestComparison == .orderedSame
                            && preferLastEqual) {
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func exactLookupMatch(
        _ lookupValue: ExcelFormulaValue,
        _ candidate: ExcelFormulaValue,
        wildcard: Bool
    ) -> Bool {
        switch (lookupValue, candidate) {
        case (.number(let lhs), .number(let rhs)):
            return lhs == rhs
        case (.text(let lhs), .text(let rhs)):
            if wildcard {
                return wildcardLookupMatch(pattern: lhs, text: rhs)
            }
            return lhs.caseInsensitiveCompare(rhs) == .orderedSame
        case (.boolean(let lhs), .boolean(let rhs)):
            return lhs == rhs
        case (.blank, .blank):
            return true
        case (.error(let lhs), .error(let rhs)):
            return lhs == rhs
        default:
            return false
        }
    }

    private func lookupComparison(
        _ left: ExcelFormulaValue,
        _ right: ExcelFormulaValue
    ) -> ComparisonResult? {
        let leftRank = lookupSortRank(left)
        let rightRank = lookupSortRank(right)
        guard let leftRank, let rightRank else { return nil }
        if leftRank != rightRank {
            return leftRank < rightRank
                ? .orderedAscending
                : .orderedDescending
        }
        switch (left, right) {
        case (.number(let lhs), .number(let rhs)):
            return lhs == rhs ? .orderedSame
                : (lhs < rhs ? .orderedAscending : .orderedDescending)
        case (.blank, .blank):
            return .orderedSame
        case (.blank, .number(let rhs)):
            return rhs == 0 ? .orderedSame
                : (0 < rhs ? .orderedAscending : .orderedDescending)
        case (.number(let lhs), .blank):
            return lhs == 0 ? .orderedSame
                : (lhs < 0 ? .orderedAscending : .orderedDescending)
        case (.text(let lhs), .text(let rhs)):
            return lhs.compare(rhs, options: [.caseInsensitive])
        case (.boolean(let lhs), .boolean(let rhs)):
            return lhs == rhs ? .orderedSame
                : (!lhs ? .orderedAscending : .orderedDescending)
        default:
            return nil
        }
    }

    private func lookupSortRank(_ value: ExcelFormulaValue) -> Int? {
        switch value {
        case .number, .blank: return 0
        case .text: return 1
        case .boolean: return 2
        case .error: return nil
        }
    }

    private func wildcardLookupMatch(
        pattern: String,
        text: String
    ) -> Bool {
        guard let expression = wildcardRegularExpression(
            pattern: pattern,
            anchored: true
        ) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return expression.firstMatch(
            in: text,
            options: [],
            range: range
        ) != nil
    }

    private func wildcardRegularExpression(
        pattern: String,
        anchored: Bool
    ) -> NSRegularExpression? {
        let characters = Array(pattern)
        var index = 0
        var regex = anchored ? "^" : ""
        while index < characters.count {
            let character = characters[index]
            if character == "~", index + 1 < characters.count,
               ["*", "?", "~"].contains(characters[index + 1]) {
                index += 1
                regex += NSRegularExpression.escapedPattern(
                    for: String(characters[index])
                )
            } else if character == "*" {
                regex += ".*"
            } else if character == "?" {
                regex += "."
            } else {
                regex += NSRegularExpression.escapedPattern(
                    for: String(character)
                )
            }
            index += 1
        }
        if anchored { regex += "$" }
        return try? NSRegularExpression(
            pattern: regex,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
    }

    private func rangeMatrix(
        _ expression: ExcelFormulaExpression
    ) -> ExcelFormulaRangeMatrix? {
        if isArrayExpression(expression) {
            return arrayMatrix(expression)
        }
        guard let range = cellRange(expression) else { return nil }
        return rangeMatrix(range)
    }

    private func rangeMatrix(
        startingAt expression: ExcelFormulaExpression,
        rowCount: Int,
        columnCount: Int
    ) -> ExcelFormulaRangeMatrix? {
        guard let start = cellRange(expression)?.start,
              rowCount > 0, columnCount > 0,
              start.row <= Int.max - rowCount + 1,
              start.column <= Int.max - columnCount + 1 else {
            return nil
        }
        return rangeMatrix(ExcelCellRange(
            start: start,
            end: ExcelCellAddress(
                row: start.row + rowCount - 1,
                column: start.column + columnCount - 1
            )
        ))
    }

    private func cellRange(
        _ expression: ExcelFormulaExpression
    ) -> ExcelCellRange? {
        switch expression {
        case .range(let value):
            return value
        case .cell(let address):
            return ExcelCellRange(start: address, end: address)
        case .spill(let anchor):
            if !dynamicArrayAttempts.contains(anchor),
               let expression = parsedExpression(at: anchor),
               isArrayExpression(expression) {
                prepareDynamicArray(at: anchor, expression: expression)
            }
            return spillRanges[anchor]
        default:
            return nil
        }
    }

    private func rangeMatrix(
        _ range: ExcelCellRange
    ) -> ExcelFormulaRangeMatrix? {
        let rowCount = range.end.row - range.start.row + 1
        let columnCount = range.end.column - range.start.column + 1
        guard rowCount * columnCount <= 100_000 else { return nil }
        var values = [ExcelFormulaValue]()
        values.reserveCapacity(rowCount * columnCount)
        for row in range.start.row ... range.end.row {
            for column in range.start.column ... range.end.column {
                guard let value = value(at: ExcelCellAddress(
                    row: row,
                    column: column
                )) else {
                    return nil
                }
                values.append(value)
            }
        }
        return ExcelFormulaRangeMatrix(
            rowCount: rowCount,
            columnCount: columnCount,
            values: values
        )
    }

    private func dateFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        switch name {
        case "TODAY":
            guard arguments.isEmpty else { return .error(.value) }
            return excelSerial(for: now).map(ExcelFormulaValue.number)
                ?? .error(.number)
        case "NOW":
            guard arguments.isEmpty else { return .error(.value) }
            return excelDateTimeSerial(for: now)
                .map(ExcelFormulaValue.number) ?? .error(.number)
        case "TIME":
            guard arguments.count == 3 else { return .error(.value) }
            var components = [Int]()
            for argument in arguments {
                guard let value = evaluate(argument) else { return nil }
                if value.error != nil { return value }
                guard let number = value.number, number.isFinite else {
                    return .error(.value)
                }
                let truncated = number.rounded(.towardZero)
                guard (0 ... 32_767).contains(truncated) else {
                    return .error(.number)
                }
                components.append(Int(truncated))
            }
            let totalSeconds = (
                components[0] * 3_600
                    + components[1] * 60
                    + components[2]
            ) % 86_400
            return .number(Double(totalSeconds) / 86_400)
        case "DATE":
            guard arguments.count == 3 else { return .error(.value) }
            var numbers = [Double]()
            for argument in arguments {
                guard let value = evaluate(argument) else { return nil }
                if value.error != nil { return value }
                guard let number = value.number, number.isFinite else {
                    return .error(.value)
                }
                numbers.append(number.rounded(.towardZero))
            }
            guard numbers[0] >= 0, numbers[0] < 10_000,
                  (-120_000 ... 120_000).contains(numbers[1]),
                  (-4_000_000 ... 4_000_000).contains(numbers[2]) else {
                return .error(.number)
            }
            var year = Int(numbers[0])
            if year <= 1899 { year += 1900 }
            guard let serial = normalizedExcelSerial(
                year: year,
                month: Int(numbers[1]),
                day: Int(numbers[2])
            ) else {
                return .error(.number)
            }
            return .number(serial)
        case "YEAR", "MONTH", "DAY":
            guard arguments.count == 1,
                  let value = evaluate(arguments[0]) else {
                return arguments.count == 1 ? nil : .error(.value)
            }
            if value.error != nil { return value }
            guard let serial = value.number, serial.isFinite else {
                return .error(.value)
            }
            guard let parts = excelDateParts(for: serial) else {
                return .error(.number)
            }
            switch name {
            case "YEAR": return .number(Double(parts.year))
            case "MONTH": return .number(Double(parts.month))
            case "DAY": return .number(Double(parts.day))
            default: return nil
            }
        case "HOUR", "MINUTE", "SECOND":
            guard arguments.count == 1,
                  let value = evaluate(arguments[0]) else {
                return arguments.count == 1 ? nil : .error(.value)
            }
            if value.error != nil { return value }
            guard let serial = value.number, serial.isFinite else {
                return .error(.value)
            }
            guard let seconds = timeSecondOfDay(for: serial) else {
                return .error(.number)
            }
            switch name {
            case "HOUR": return .number(Double(seconds / 3_600))
            case "MINUTE":
                return .number(Double((seconds % 3_600) / 60))
            case "SECOND": return .number(Double(seconds % 60))
            default: return nil
            }
        case "EDATE", "EOMONTH":
            guard arguments.count == 2,
                  let startValue = evaluate(arguments[0]),
                  let monthsValue = evaluate(arguments[1]) else {
                return arguments.count == 2 ? nil : .error(.value)
            }
            if let error = startValue.error ?? monthsValue.error {
                return .error(error)
            }
            guard let startSerial = startValue.number,
                  let monthsNumber = monthsValue.number,
                  startSerial.isFinite, monthsNumber.isFinite else {
                return .error(.value)
            }
            guard let start = excelDateParts(for: startSerial) else {
                return name == "EDATE"
                    ? .error(.value) : .error(.number)
            }
            let months = monthsNumber.rounded(.towardZero)
            guard (-120_000 ... 120_000).contains(months),
                  let target = normalizedYearAndMonth(
                      year: start.year,
                      month: start.month + Int(months)
                  ),
                  let days = daysInExcelMonth(
                      year: target.year,
                      month: target.month
                  ) else {
                return .error(.number)
            }
            let day = name == "EOMONTH"
                ? days : min(start.day, days)
            guard let serial = normalizedExcelSerial(
                year: target.year,
                month: target.month,
                day: day
            ) else {
                return .error(.number)
            }
            return .number(serial)
        case "DAYS", "DATEDIF":
            return dateDifferenceFunction(name, arguments: arguments)
        case "WORKDAY", "WORKDAY.INTL", "NETWORKDAYS",
             "NETWORKDAYS.INTL":
            return businessDayFunction(name, arguments: arguments)
        case "WEEKDAY":
            guard (1 ... 2).contains(arguments.count),
                  let serialValue = evaluate(arguments[0]) else {
                return (1 ... 2).contains(arguments.count)
                    ? nil : .error(.value)
            }
            if serialValue.error != nil { return serialValue }
            guard let serial = serialValue.number, serial.isFinite else {
                return .error(.value)
            }
            guard excelDateParts(for: serial) != nil else {
                return .error(.number)
            }
            var returnType = 1
            if arguments.count == 2 {
                guard let typeValue = evaluate(arguments[1]) else {
                    return nil
                }
                if typeValue.error != nil { return typeValue }
                guard let number = typeValue.number, number.isFinite,
                      number.rounded(.towardZero) == number,
                      number >= Double(Int.min),
                      number <= Double(Int.max) else {
                    return .error(.number)
                }
                returnType = Int(number)
            }
            guard let result = weekday(
                serial: Int(floor(serial)),
                returnType: returnType
            ) else {
                return .error(.number)
            }
            return .number(Double(result))
        case "WEEKNUM", "ISOWEEKNUM":
            return weekNumberFunction(name, arguments: arguments)
        default:
            return nil
        }
    }

    private func dateDifferenceFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        let expectedCount = name == "DAYS" ? 2 : 3
        guard arguments.count == expectedCount,
              let firstValue = evaluate(arguments[0]),
              let secondValue = evaluate(arguments[1]) else {
            return arguments.count == expectedCount
                ? nil : .error(.value)
        }
        if let error = firstValue.error ?? secondValue.error {
            return .error(error)
        }
        guard let firstNumber = firstValue.number,
              let secondNumber = secondValue.number,
              firstNumber.isFinite, secondNumber.isFinite else {
            return .error(.value)
        }

        if name == "DAYS" {
            guard excelDateParts(for: firstNumber) != nil,
                  excelDateParts(for: secondNumber) != nil else {
                return .error(.number)
            }
            return .number(firstNumber - secondNumber)
        }

        guard let start = excelDateParts(for: firstNumber),
              let end = excelDateParts(for: secondNumber) else {
            return .error(.number)
        }
        let startSerial = Int(floor(firstNumber))
        let endSerial = Int(floor(secondNumber))
        guard startSerial <= endSerial else { return .error(.number) }
        guard let unitValue = evaluate(arguments[2]) else { return nil }
        if unitValue.error != nil { return unitValue }
        guard case .text(let unitText) = unitValue else {
            return .error(.number)
        }
        let unit = unitText.uppercased()
        let monthDifference = (end.year - start.year) * 12
            + end.month - start.month
        let completedMonths = max(
            0,
            monthDifference - (end.day < start.day ? 1 : 0)
        )

        switch unit {
        case "D":
            return .number(Double(endSerial - startSerial))
        case "M":
            return .number(Double(completedMonths))
        case "Y":
            return .number(Double(completedMonths / 12))
        case "YM":
            return .number(Double(completedMonths % 12))
        case "MD":
            guard let anchor = shiftedExcelSerial(
                from: start,
                months: completedMonths
            ) else {
                return .error(.number)
            }
            return .number(Double(endSerial - anchor))
        case "YD":
            guard var anniversary = clampedExcelSerial(
                year: end.year,
                month: start.month,
                day: start.day
            ) else {
                return .error(.number)
            }
            if anniversary > endSerial {
                guard let previous = clampedExcelSerial(
                    year: end.year - 1,
                    month: start.month,
                    day: start.day
                ) else {
                    return .error(.number)
                }
                anniversary = previous
            }
            return .number(Double(endSerial - anniversary))
        default:
            return .error(.number)
        }
    }

    private func businessDayFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        let isInternational = name.hasSuffix(".INTL")
        let isWorkday = name.hasPrefix("WORKDAY")
        let allowedCounts = isInternational ? 2 ... 4 : 2 ... 3
        guard allowedCounts.contains(arguments.count),
              let firstValue = evaluate(arguments[0]),
              let secondValue = evaluate(arguments[1]) else {
            return allowedCounts.contains(arguments.count)
                ? nil : .error(.value)
        }
        if let error = firstValue.error ?? secondValue.error {
            return .error(error)
        }

        let invalidDateError: ExcelFormulaError = isInternational
            ? .number : .value
        guard let firstNumber = firstValue.number,
              let secondNumber = secondValue.number,
              firstNumber.isFinite, secondNumber.isFinite else {
            return .error(.value)
        }
        guard excelDateParts(for: firstNumber) != nil else {
            return .error(invalidDateError)
        }
        let firstSerial = Int(floor(firstNumber))

        var weekend = Set([0, 6])
        if isInternational, arguments.count >= 3 {
            guard let weekendValue = evaluate(arguments[2]) else {
                return nil
            }
            if weekendValue.error != nil { return weekendValue }
            switch weekendDays(
                from: weekendValue,
                allowEveryDay: !isWorkday
            ) {
            case .success(let days): weekend = days
            case .failure(let error): return .error(error)
            }
        }

        let holidayIndex: Int? = isInternational
            ? (arguments.count == 4 ? 3 : nil)
            : (arguments.count == 3 ? 2 : nil)
        var holidays = Set<Int>()
        if let holidayIndex {
            guard let result = holidaySerials(
                from: arguments[holidayIndex],
                invalidDateError: invalidDateError
            ) else {
                return nil
            }
            switch result {
            case .success(let values): holidays = values
            case .failure(let error): return .error(error)
            }
        }

        if isWorkday {
            let truncatedDays = secondNumber.rounded(.towardZero)
            guard truncatedDays >= Double(Int.min),
                  truncatedDays <= Double(Int.max),
                  abs(truncatedDays)
                    <= Double(maximumExcelDaySerial + 1) else {
                return .error(.number)
            }
            let dayOffset = Int(truncatedDays)
            if dayOffset == 0 { return .number(Double(firstSerial)) }
            var serial = firstSerial
            var remaining = abs(dayOffset)
            let direction = dayOffset > 0 ? 1 : -1
            while remaining > 0 {
                guard serial != (direction > 0
                    ? maximumExcelDaySerial : 0) else {
                    return .error(.number)
                }
                serial += direction
                if isWorkingDay(
                    serial,
                    weekend: weekend,
                    holidays: holidays
                ) {
                    remaining -= 1
                }
            }
            return .number(Double(serial))
        }

        guard excelDateParts(for: secondNumber) != nil else {
            return .error(invalidDateError)
        }
        let secondSerial = Int(floor(secondNumber))
        let direction = firstSerial <= secondSerial ? 1 : -1
        var serial = firstSerial
        var count = 0
        while true {
            if isWorkingDay(
                serial,
                weekend: weekend,
                holidays: holidays
            ) {
                count += direction
            }
            if serial == secondSerial { break }
            serial += direction
        }
        return .number(Double(count))
    }

    private func weekNumberFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        let allowedCounts = name == "WEEKNUM" ? 1 ... 2 : 1 ... 1
        guard allowedCounts.contains(arguments.count),
              let serialValue = evaluate(arguments[0]) else {
            return allowedCounts.contains(arguments.count)
                ? nil : .error(.value)
        }
        if serialValue.error != nil { return serialValue }
        guard let number = serialValue.number, number.isFinite else {
            return .error(.value)
        }
        guard excelDateParts(for: number) != nil else {
            return .error(.number)
        }
        let serial = Int(floor(number))

        if name == "ISOWEEKNUM" {
            guard let result = isoWeekNumber(serial: serial) else {
                return .error(.number)
            }
            return .number(Double(result))
        }

        var returnType = 1
        if arguments.count == 2 {
            guard let typeValue = evaluate(arguments[1]) else { return nil }
            if typeValue.error != nil { return typeValue }
            guard let typeNumber = typeValue.number,
                  typeNumber.isFinite,
                  typeNumber.rounded(.towardZero) == typeNumber,
                  typeNumber >= Double(Int.min),
                  typeNumber <= Double(Int.max) else {
                return .error(.number)
            }
            returnType = Int(typeNumber)
        }
        if returnType == 21 {
            guard let result = isoWeekNumber(serial: serial) else {
                return .error(.number)
            }
            return .number(Double(result))
        }
        guard let firstWeekday = weekStartSundayIndex(
            returnType: returnType
        ),
        let year = excelDateParts(for: number)?.year,
        let januaryFirst = normalizedExcelSerial(
            year: year,
            month: 1,
            day: 1
        ).map({ Int($0) }),
        let januaryFirstWeekday = weekday(
            serial: januaryFirst,
            returnType: 17
        ).map({ $0 - 1 }) else {
            return .error(.number)
        }
        let leadingDays = (
            januaryFirstWeekday - firstWeekday + 7
        ) % 7
        let numerator = serial - januaryFirst + leadingDays
        let week = numerator >= 0
            ? numerator / 7 + 1
            : (numerator - 6) / 7 + 1
        return .number(Double(week))
    }

    private func shiftedExcelSerial(
        from parts: (year: Int, month: Int, day: Int),
        months: Int
    ) -> Int? {
        guard let target = normalizedYearAndMonth(
            year: parts.year,
            month: parts.month + months
        ) else {
            return nil
        }
        return clampedExcelSerial(
            year: target.year,
            month: target.month,
            day: parts.day
        )
    }

    private func clampedExcelSerial(
        year: Int,
        month: Int,
        day: Int
    ) -> Int? {
        guard let days = daysInExcelMonth(year: year, month: month),
              let serial = normalizedExcelSerial(
                  year: year,
                  month: month,
                  day: min(day, days)
              ) else {
            return nil
        }
        return Int(serial)
    }

    private func holidaySerials(
        from expression: ExcelFormulaExpression,
        invalidDateError: ExcelFormulaError
    ) -> Result<Set<Int>, ExcelFormulaError>? {
        let values: [ExcelFormulaValue]
        if let range = rangeMatrix(expression) {
            values = range.values
        } else {
            guard let value = evaluate(expression) else { return nil }
            values = [value]
        }
        var result = Set<Int>()
        for value in values {
            if let error = value.error { return .failure(error) }
            if case .blank = value { continue }
            if case .text(let text) = value,
               text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            guard let number = value.number, number.isFinite else {
                return .failure(.value)
            }
            guard excelDateParts(for: number) != nil else {
                return .failure(invalidDateError)
            }
            result.insert(Int(floor(number)))
        }
        return .success(result)
    }

    private func weekendDays(
        from value: ExcelFormulaValue,
        allowEveryDay: Bool
    ) -> Result<Set<Int>, ExcelFormulaError> {
        if case .text(let text) = value {
            let characters = Array(text)
            guard characters.count == 7,
                  characters.allSatisfy({ $0 == "0" || $0 == "1" }) else {
                return .failure(.value)
            }
            let days = Set(characters.indices.compactMap { index in
                characters[index] == "1" ? (index + 1) % 7 : nil
            })
            guard allowEveryDay || days.count < 7 else {
                return .failure(.value)
            }
            return .success(days)
        }
        guard let number = value.number, number.isFinite,
              number.rounded(.towardZero) == number,
              number >= Double(Int.min),
              number <= Double(Int.max) else {
            return .failure(.number)
        }
        let code = Int(number)
        switch code {
        case 1:
            return .success([0, 6])
        case 2 ... 7:
            let first = code - 2
            return .success([first, (first + 1) % 7])
        case 11 ... 17:
            return .success([code - 11])
        default:
            return .failure(.number)
        }
    }

    private func isWorkingDay(
        _ serial: Int,
        weekend: Set<Int>,
        holidays: Set<Int>
    ) -> Bool {
        guard let day = weekday(serial: serial, returnType: 17) else {
            return false
        }
        return !weekend.contains(day - 1) && !holidays.contains(serial)
    }

    private func weekStartSundayIndex(returnType: Int) -> Int? {
        switch returnType {
        case 1, 17: return 0
        case 2, 11: return 1
        case 12 ... 16: return returnType - 10
        default: return nil
        }
    }

    private func isoWeekNumber(serial: Int) -> Int? {
        guard let isoWeekday = weekday(serial: serial, returnType: 2) else {
            return nil
        }
        let thursday = serial + 4 - isoWeekday
        guard let isoYear = excelDateParts(
            for: Double(thursday)
        )?.year,
        let januaryFourth = normalizedExcelSerial(
            year: isoYear,
            month: 1,
            day: 4
        ).map({ Int($0) }),
        let januaryFourthWeekday = weekday(
            serial: januaryFourth,
            returnType: 2
        ) else {
            return nil
        }
        let firstMonday = januaryFourth - (januaryFourthWeekday - 1)
        return (serial - firstMonday) / 7 + 1
    }

    private var maximumExcelDaySerial: Int {
        uses1904DateSystem ? 2_957_003 : 2_958_465
    }

    private func normalizedExcelSerial(
        year: Int,
        month: Int,
        day: Int
    ) -> Double? {
        guard let normalized = normalizedYearAndMonth(
            year: year,
            month: month
        ),
        (1900 ... 9999).contains(normalized.year) else {
            return nil
        }
        let calendar = gregorianCalendar
        guard let monthStart = calendar.date(
            from: DateComponents(
                timeZone: timeZone,
                year: normalized.year,
                month: normalized.month,
                day: 1
            )
        ),
        let firstSerial = excelDaySerial(for: monthStart) else {
            return nil
        }
        let serial = firstSerial + day - 1
        let maximum = uses1904DateSystem ? 2_957_003 : 2_958_465
        guard serial >= 0, serial <= maximum else { return nil }
        return Double(serial)
    }

    private func normalizedYearAndMonth(
        year: Int,
        month: Int
    ) -> (year: Int, month: Int)? {
        guard year >= Int.min / 12, year <= Int.max / 12 else {
            return nil
        }
        let totalMonths = year * 12 + month - 1
        var normalizedYear = totalMonths / 12
        var zeroBasedMonth = totalMonths % 12
        if zeroBasedMonth < 0 {
            normalizedYear -= 1
            zeroBasedMonth += 12
        }
        return (normalizedYear, zeroBasedMonth + 1)
    }

    private func daysInExcelMonth(
        year: Int,
        month: Int
    ) -> Int? {
        guard (1900 ... 9999).contains(year), (1 ... 12).contains(month) else {
            return nil
        }
        if !uses1904DateSystem, year == 1900, month == 2 {
            return 29
        }
        let calendar = gregorianCalendar
        guard let date = calendar.date(
            from: DateComponents(
                timeZone: timeZone,
                year: year,
                month: month,
                day: 1
            )
        ) else {
            return nil
        }
        return calendar.range(of: .day, in: .month, for: date)?.count
    }

    private func excelSerial(for date: Date) -> Double? {
        guard let serial = excelDaySerial(for: date) else { return nil }
        let maximum = uses1904DateSystem ? 2_957_003 : 2_958_465
        guard serial >= 0, serial <= maximum else { return nil }
        return Double(serial)
    }

    private func excelDateTimeSerial(for date: Date) -> Double? {
        guard let daySerial = excelSerial(for: date) else { return nil }
        let components = gregorianCalendar.dateComponents(
            [.hour, .minute, .second],
            from: date
        )
        guard let hour = components.hour,
              let minute = components.minute,
              let second = components.second else {
            return nil
        }
        let seconds = hour * 3_600 + minute * 60 + second
        return daySerial + Double(seconds) / 86_400
    }

    private func excelDaySerial(for source: Date) -> Int? {
        let calendar = gregorianCalendar
        let date = calendar.startOfDay(for: source)
        let baseComponents: DateComponents
        if uses1904DateSystem {
            baseComponents = DateComponents(
                timeZone: timeZone,
                year: 1904,
                month: 1,
                day: 1
            )
        } else {
            baseComponents = DateComponents(
                timeZone: timeZone,
                year: 1899,
                month: 12,
                day: 31
            )
        }
        guard let base = calendar.date(from: baseComponents),
              let dayCount = calendar.dateComponents(
                  [.day],
                  from: base,
                  to: date
              ).day else {
            return nil
        }
        var serial = dayCount
        if !uses1904DateSystem,
           let march1900 = calendar.date(
               from: DateComponents(
                   timeZone: timeZone,
                   year: 1900,
                   month: 3,
                   day: 1
               )
           ),
           date >= march1900 {
            serial += 1
        }
        return serial
    }

    private func timeSecondOfDay(for serial: Double) -> Int? {
        guard excelDateParts(for: serial) != nil else { return nil }
        let fraction = serial - floor(serial)
        let rawSeconds = fraction * 86_400
        let nearestSecond = rawSeconds.rounded()
        let representationTolerance = max(
            serial.ulp * 86_400 * 2,
            Double.ulpOfOne * 86_400
        )
        let seconds: Int
        if abs(rawSeconds - nearestSecond) <= representationTolerance {
            seconds = Int(nearestSecond)
        } else {
            seconds = Int(floor(rawSeconds))
        }
        if seconds == 86_400 { return 0 }
        return min(86_399, max(0, seconds))
    }

    private func weekday(
        serial: Int,
        returnType: Int
    ) -> Int? {
        let sundayIndex = (serial + (uses1904DateSystem ? 5 : 6)) % 7
        switch returnType {
        case 1, 17:
            return sundayIndex + 1
        case 2, 11:
            return (sundayIndex + 6) % 7 + 1
        case 3:
            return (sundayIndex + 6) % 7
        case 12 ... 16:
            let firstDayIndex = returnType - 10
            return (sundayIndex - firstDayIndex + 7) % 7 + 1
        default:
            return nil
        }
    }

    private func excelDateParts(
        for serial: Double
    ) -> (year: Int, month: Int, day: Int)? {
        let serial = serial.rounded(.down)
        let maximum = uses1904DateSystem ? 2_957_003.0 : 2_958_465.0
        guard serial >= 0, serial <= maximum else { return nil }
        let day = Int(serial)
        if !uses1904DateSystem {
            if day == 0 { return (1900, 1, 0) }
            if day == 60 { return (1900, 2, 29) }
        }
        let calendar = gregorianCalendar
        let baseComponents: DateComponents
        let offset: Int
        if uses1904DateSystem {
            baseComponents = DateComponents(
                timeZone: timeZone,
                year: 1904,
                month: 1,
                day: 1
            )
            offset = day
        } else {
            baseComponents = DateComponents(
                timeZone: timeZone,
                year: 1899,
                month: 12,
                day: 31
            )
            offset = day > 60 ? day - 1 : day
        }
        guard let base = calendar.date(from: baseComponents),
              let date = calendar.date(
                  byAdding: .day,
                  value: offset,
                  to: base
              ) else {
            return nil
        }
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return nil
        }
        return (year, month, day)
    }

    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func transcendentalFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        if name == "PI" {
            return arguments.isEmpty ? .number(Double.pi) : .error(.value)
        }
        if name == "ATAN2" {
            guard arguments.count == 2,
                  let xValue = evaluate(arguments[0]),
                  let yValue = evaluate(arguments[1]) else {
                return arguments.count == 2 ? nil : .error(.value)
            }
            if let error = xValue.error ?? yValue.error {
                return .error(error)
            }
            guard let x = xValue.number, let y = yValue.number,
                  x.isFinite, y.isFinite else {
                return .error(.value)
            }
            guard x != 0 || y != 0 else {
                return .error(.divideByZero)
            }
            return finiteNumber(atan2(y, x))
        }
        if name == "LOG" {
            guard (1 ... 2).contains(arguments.count),
                  let numberValue = evaluate(arguments[0]) else {
                return (1 ... 2).contains(arguments.count)
                    ? nil : .error(.value)
            }
            if numberValue.error != nil { return numberValue }
            guard let number = numberValue.number, number.isFinite else {
                return .error(.value)
            }
            var base = 10.0
            if arguments.count == 2, !isOmitted(arguments[1]) {
                guard let baseValue = evaluate(arguments[1]) else {
                    return nil
                }
                if baseValue.error != nil { return baseValue }
                guard let parsedBase = baseValue.number,
                      parsedBase.isFinite else {
                    return .error(.value)
                }
                base = parsedBase
            }
            guard number > 0, base > 0, base != 1 else {
                return .error(.number)
            }
            return finiteNumber(log(number) / log(base))
        }

        guard arguments.count == 1,
              let value = evaluate(arguments[0]) else {
            return arguments.count == 1 ? nil : .error(.value)
        }
        if value.error != nil { return value }
        guard let number = value.number, number.isFinite else {
            return .error(.value)
        }
        switch name {
        case "EXP":
            return finiteNumber(exp(number))
        case "LN":
            return number > 0
                ? finiteNumber(log(number)) : .error(.number)
        case "LOG10":
            return number > 0
                ? finiteNumber(log10(number)) : .error(.number)
        case "SIN":
            return finiteNumber(sin(number))
        case "COS":
            return finiteNumber(cos(number))
        case "TAN":
            return finiteNumber(tan(number))
        case "SINH":
            return finiteNumber(sinh(number))
        case "COSH":
            return finiteNumber(cosh(number))
        case "TANH":
            return finiteNumber(tanh(number))
        case "ASIN":
            guard (-1 ... 1).contains(number) else {
                return .error(.number)
            }
            return finiteNumber(asin(number))
        case "ACOS":
            guard (-1 ... 1).contains(number) else {
                return .error(.number)
            }
            return finiteNumber(acos(number))
        case "ATAN":
            return finiteNumber(atan(number))
        case "ASINH":
            return finiteNumber(asinh(number))
        case "ACOSH":
            guard number >= 1 else { return .error(.number) }
            return finiteNumber(acosh(number))
        case "ATANH":
            guard number > -1, number < 1 else {
                return .error(.number)
            }
            return finiteNumber(atanh(number))
        case "ACOT":
            return finiteNumber(atan2(1, number))
        case "ACOTH":
            guard abs(number) > 1 else { return .error(.number) }
            return finiteNumber(0.5 * log((number + 1) / (number - 1)))
        case "COT", "CSC", "SEC":
            guard abs(number) < 134_217_728 else {
                return .error(.number)
            }
            let denominator: Double
            switch name {
            case "COT": denominator = tan(number)
            case "CSC": denominator = sin(number)
            default: denominator = cos(number)
            }
            guard denominator != 0 else {
                return .error(.divideByZero)
            }
            return finiteNumber(1 / denominator)
        case "COTH", "CSCH", "SECH":
            guard abs(number) < 134_217_728 else {
                return .error(.number)
            }
            if name != "SECH", number == 0 {
                return .error(.divideByZero)
            }
            let magnitude = abs(number)
            let decaying = exp(-magnitude)
            let squared = decaying * decaying
            let result: Double
            switch name {
            case "COTH":
                let positive = (1 + squared) / (1 - squared)
                result = number < 0 ? -positive : positive
            case "CSCH":
                let positive = 2 * decaying / (1 - squared)
                result = number < 0 ? -positive : positive
            default:
                result = 2 * decaying / (1 + squared)
            }
            return finiteNumber(result)
        case "SQRTPI":
            guard number >= 0 else { return .error(.number) }
            return finiteNumber(sqrt(number * .pi))
        case "DEGREES":
            return finiteNumber(number * 180 / .pi)
        case "RADIANS":
            return finiteNumber(number * .pi / 180)
        default:
            return nil
        }
    }

    private func unaryMathFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard arguments.count == 1 else { return .error(.value) }
        guard let value = evaluate(arguments[0]) else { return nil }
        if value.error != nil { return value }
        guard let number = value.number else { return .error(.value) }
        switch name {
        case "ABS":
            return finiteNumber(abs(number))
        case "INT":
            return finiteNumber(floor(number))
        case "SIGN":
            return .number(number == 0 ? 0 : (number > 0 ? 1 : -1))
        case "SQRT":
            guard number >= 0 else { return .error(.number) }
            return finiteNumber(sqrt(number))
        default:
            return nil
        }
    }

    private func binaryMathFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard arguments.count == 2,
              let firstValue = evaluate(arguments[0]),
              let secondValue = evaluate(arguments[1]) else {
            return arguments.count == 2 ? nil : .error(.value)
        }
        if let error = firstValue.error ?? secondValue.error {
            return .error(error)
        }
        guard let first = firstValue.number,
              let second = secondValue.number,
              first.isFinite, second.isFinite else {
            return .error(.value)
        }
        switch name {
        case "MOD":
            guard second != 0 else { return .error(.divideByZero) }
            return finiteNumber(first - second * floor(first / second))
        case "POWER":
            if first == 0, second < 0 {
                return .error(.divideByZero)
            }
            let result = pow(first, second)
            return result.isFinite ? .number(result) : .error(.number)
        case "QUOTIENT":
            guard second != 0 else { return .error(.divideByZero) }
            return finiteNumber((first / second).rounded(.towardZero))
        default:
            return nil
        }
    }

    private func roundingFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        let allowedCounts = name == "TRUNC" ? 1 ... 2 : 2 ... 2
        guard allowedCounts.contains(arguments.count) else {
            return .error(.value)
        }
        guard let value = evaluate(arguments[0]),
              let digitsValue = arguments.count == 2
                ? evaluate(arguments[1]) : .number(0) else { return nil }
        if let error = value.error ?? digitsValue.error {
            return .error(error)
        }
        guard let number = value.number,
              let digits = digitsValue.number else {
            return .error(.value)
        }
        let rule: FloatingPointRoundingRule
        switch name {
        case "ROUND": rule = .toNearestOrAwayFromZero
        case "ROUNDDOWN": rule = .towardZero
        case "ROUNDUP": rule = .awayFromZero
        case "TRUNC": rule = .towardZero
        default: return nil
        }
        return roundedNumber(number, digits: digits, rule: rule)
    }

    private func multipleRoundingFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        let allowedCounts: ClosedRange<Int>
        switch name {
        case "CEILING.MATH", "FLOOR.MATH":
            allowedCounts = 1 ... 3
        case "CEILING.PRECISE", "FLOOR.PRECISE":
            allowedCounts = 1 ... 2
        default:
            allowedCounts = 2 ... 2
        }
        guard allowedCounts.contains(arguments.count) else {
            return .error(.value)
        }

        guard let numberValue = evaluate(arguments[0]) else { return nil }
        if numberValue.error != nil { return numberValue }
        guard let number = numberValue.number, number.isFinite else {
            return .error(.value)
        }

        var significance = 1.0
        if arguments.count >= 2, !isOmitted(arguments[1]) {
            guard let significanceValue = evaluate(arguments[1]) else {
                return nil
            }
            if significanceValue.error != nil { return significanceValue }
            guard let parsed = significanceValue.number, parsed.isFinite else {
                return .error(.value)
            }
            significance = parsed
        }

        var mode = 0.0
        if arguments.count == 3, !isOmitted(arguments[2]) {
            guard let modeValue = evaluate(arguments[2]) else { return nil }
            if modeValue.error != nil { return modeValue }
            guard let parsed = modeValue.number, parsed.isFinite else {
                return .error(.value)
            }
            mode = parsed
        }

        guard significance != 0 else {
            return name == "FLOOR" && number != 0
                ? .error(.divideByZero) : .number(0)
        }
        guard number != 0 else { return .number(0) }

        let magnitude = abs(significance)
        let rule: FloatingPointRoundingRule
        switch name {
        case "CEILING":
            guard !(number > 0 && significance < 0) else {
                return .error(.number)
            }
            rule = significance < 0 ? .down : .up
        case "FLOOR":
            guard !(number > 0 && significance < 0) else {
                return .error(.number)
            }
            rule = significance < 0 ? .up : .down
        case "CEILING.MATH":
            rule = number < 0 && mode != 0 ? .down : .up
        case "FLOOR.MATH":
            rule = number < 0 && mode != 0 ? .up : .down
        case "CEILING.PRECISE":
            rule = .up
        case "FLOOR.PRECISE":
            rule = .down
        case "MROUND":
            guard number.sign == significance.sign else {
                return .error(.number)
            }
            rule = .toNearestOrAwayFromZero
        default:
            return nil
        }

        let quotient = stabilizedMultipleQuotient(number / magnitude)
        let result = quotient.rounded(rule) * magnitude
        guard result.isFinite else { return .error(.number) }
        return .number(result == 0 ? 0 : result)
    }

    private func stabilizedMultipleQuotient(_ quotient: Double) -> Double {
        let nearestInteger = quotient.rounded()
        let tolerance = max(
            8 * Double.ulpOfOne,
            8 * abs(quotient).ulp
        )
        return abs(quotient - nearestInteger) <= tolerance
            ? nearestInteger : quotient
    }

    private func parityRoundingFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard arguments.count == 1,
              let value = evaluate(arguments[0]) else {
            return arguments.count == 1 ? nil : .error(.value)
        }
        if value.error != nil { return value }
        guard let number = value.number, number.isFinite else {
            return .error(.value)
        }
        let magnitude = abs(number)
        let rounded: Double
        if name == "EVEN" {
            rounded = ceil(magnitude / 2) * 2
        } else {
            rounded = ceil((magnitude - 1) / 2) * 2 + 1
        }
        guard rounded.isFinite else { return .error(.number) }
        let result = number < 0 ? -rounded : rounded
        return .number(result == 0 ? 0 : result)
    }

    private func combinatoricsFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        let expectedCount = ["FACT", "FACTDOUBLE"].contains(name) ? 1 : 2
        guard arguments.count == expectedCount else {
            return .error(.value)
        }
        var integers = [Double]()
        for argument in arguments {
            guard let value = evaluate(argument) else { return nil }
            if value.error != nil { return value }
            guard let number = value.number, number.isFinite else {
                return .error(.value)
            }
            integers.append(number.rounded(.towardZero))
        }

        let number = integers[0]
        switch name {
        case "FACT":
            guard number >= 0 else { return .error(.number) }
            return factorial(number, step: 1)
        case "FACTDOUBLE":
            guard number >= 0 else { return .error(.number) }
            return factorial(number, step: 2)
        default:
            let chosen = integers[1]
            guard number >= 0, chosen >= 0 else {
                return .error(.number)
            }
            switch name {
            case "COMBIN":
                guard chosen <= number else { return .error(.number) }
                return combination(total: number, chosen: chosen)
            case "COMBINA":
                guard number > 0 || chosen == 0 else {
                    return .error(.number)
                }
                if chosen == 0 { return .number(1) }
                return combination(
                    total: number + chosen - 1,
                    chosen: chosen
                )
            case "PERMUT":
                guard number > 0, chosen <= number else {
                    return .error(.number)
                }
                var result = 1.0
                var offset = 0.0
                while offset < chosen {
                    result *= number - offset
                    guard result.isFinite else { return .error(.number) }
                    offset += 1
                }
                return .number(result)
            case "PERMUTATIONA":
                guard number > 0 || chosen == 0 else {
                    return .error(.number)
                }
                return finiteNumber(pow(number, chosen))
            default:
                return nil
            }
        }
    }

    private func factorial(
        _ number: Double,
        step: Double
    ) -> ExcelFormulaValue {
        if number <= 1 { return .number(1) }
        var result = 1.0
        var factor = number
        while factor > 1 {
            result *= factor
            guard result.isFinite else { return .error(.number) }
            factor -= step
        }
        return .number(result)
    }

    private func combination(
        total: Double,
        chosen: Double
    ) -> ExcelFormulaValue {
        let smaller = min(chosen, total - chosen)
        if smaller <= 0 { return .number(1) }
        var result = 1.0
        var index = 1.0
        while index <= smaller {
            result *= (total - smaller + index) / index
            guard result.isFinite else { return .error(.number) }
            index += 1
        }
        return .number(result.rounded())
    }

    private func integerDivisorFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard (1 ... 255).contains(arguments.count) else {
            return .error(.value)
        }
        var integers = [Int64]()
        for argument in arguments {
            guard let items = expandedValues(argument) else { return nil }
            for item in items {
                if let error = item.value.error { return .error(error) }
                let number: Double
                switch item.value {
                case .number(let value):
                    number = value
                case .boolean(let value) where !item.comesFromReference:
                    number = value ? 1 : 0
                case .text(let text) where !item.comesFromReference:
                    guard let value = Double(text.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )) else {
                        return .error(.value)
                    }
                    number = value
                case .blank where !item.comesFromReference:
                    number = 0
                case .boolean, .text, .blank, .error:
                    continue
                }
                let integer = number.rounded(.towardZero)
                guard integer >= 0, integer < 9_007_199_254_740_992 else {
                    return .error(.number)
                }
                integers.append(Int64(integer))
            }
        }
        guard !integers.isEmpty else { return .number(0) }

        if name == "GCD" {
            return .number(Double(integers.reduce(0, greatestCommonDivisor)))
        }

        var result: Int64 = 1
        for integer in integers {
            if result == 0 || integer == 0 { return .number(0) }
            let divisor = greatestCommonDivisor(result, integer)
            let quotient = result / divisor
            let maximum = Int64(9_007_199_254_740_991)
            guard quotient <= maximum / integer else {
                return .error(.number)
            }
            result = quotient * integer
            guard result < 9_007_199_254_740_992 else {
                return .error(.number)
            }
        }
        return .number(Double(result))
    }

    private func greatestCommonDivisor(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        var first = lhs
        var second = rhs
        while second != 0 {
            let remainder = first % second
            first = second
            second = remainder
        }
        return first
    }

    private func sumSquaresFunction(
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard (1 ... 255).contains(arguments.count) else {
            return .error(.value)
        }
        var result = 0.0
        for argument in arguments {
            guard let items = expandedValues(argument) else { return nil }
            for item in items {
                if let error = item.value.error { return .error(error) }
                let number: Double
                switch item.value {
                case .number(let value):
                    number = value
                case .boolean(let value) where !item.comesFromReference:
                    number = value ? 1 : 0
                case .text(let text) where !item.comesFromReference:
                    guard let value = Double(text.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )) else {
                        return .error(.value)
                    }
                    number = value
                case .blank, .boolean, .text, .error:
                    continue
                }
                result += number * number
                guard result.isFinite else { return .error(.number) }
            }
        }
        return .number(result)
    }

    private func roundedNumber(
        _ number: Double,
        digits: Double,
        rule: FloatingPointRoundingRule
    ) -> ExcelFormulaValue {
        guard number.isFinite, digits.isFinite else {
            return .error(.number)
        }
        let truncatedDigits = digits.rounded(.towardZero)
        if truncatedDigits > 308 { return .number(number) }
        if truncatedDigits < -308 { return .number(0) }
        let digitCount = Int(truncatedDigits)
        let scale = pow(10, Double(abs(digitCount)))
        guard scale.isFinite else {
            return digitCount >= 0 ? .number(number) : .number(0)
        }
        if digitCount >= 0 {
            let scaled = number * scale
            guard scaled.isFinite else { return .number(number) }
            return finiteNumber(scaled.rounded(rule) / scale)
        }
        return finiteNumber((number / scale).rounded(rule) * scale)
    }

    private func textConversionFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        switch name {
        case "T":
            guard arguments.count == 1,
                  let value = evaluate(arguments[0]) else {
                return arguments.count == 1 ? nil : .error(.value)
            }
            if value.error != nil { return value }
            if case .text = value { return value }
            return .text("")
        case "FIXED", "DOLLAR":
            return fixedTextFunction(name, arguments: arguments)
        case "NUMBERVALUE":
            return numberValueFunction(arguments: arguments)
        case "EXACT":
            guard arguments.count == 2,
                  let first = evaluate(arguments[0]),
                  let second = evaluate(arguments[1]) else {
                return arguments.count == 2 ? nil : .error(.value)
            }
            if let error = first.error ?? second.error {
                return .error(error)
            }
            return .boolean(first.text == second.text)
        case "CHAR":
            guard arguments.count == 1,
                  let value = evaluate(arguments[0]) else {
                return arguments.count == 1 ? nil : .error(.value)
            }
            if value.error != nil { return value }
            guard let number = value.number, number.isFinite else {
                return .error(.value)
            }
            let integer = number.rounded(.towardZero)
            guard integer >= 1, integer <= 255 else {
                return .error(.value)
            }
            let byte = UInt8(integer)
            let data = Data([byte])
            guard let text = String(
                data: data,
                encoding: .windowsCP1252
            ) ?? String(data: data, encoding: .isoLatin1) else {
                return .error(.value)
            }
            return .text(text)
        case "CODE":
            guard arguments.count == 1,
                  let value = evaluate(arguments[0]) else {
                return arguments.count == 1 ? nil : .error(.value)
            }
            if value.error != nil { return value }
            guard !value.text.isEmpty else { return .error(.value) }
            let first = String(value.text.prefix(1))
            if let byte = first.data(
                using: .windowsCP1252,
                allowLossyConversion: false
            )?.first {
                return .number(Double(byte))
            }
            if let scalar = first.unicodeScalars.first,
               scalar.value <= 255 {
                return .number(Double(scalar.value))
            }
            guard let byte = first.utf8.first else {
                return .error(.value)
            }
            return .number(Double(byte))
        case "UNICHAR":
            guard arguments.count == 1,
                  let value = evaluate(arguments[0]) else {
                return arguments.count == 1 ? nil : .error(.value)
            }
            if value.error != nil { return value }
            guard let number = value.number, number.isFinite else {
                return .error(.value)
            }
            let integer = number.rounded(.towardZero)
            guard integer >= 1, integer <= 0x10_FFFF else {
                return .error(.value)
            }
            let codePoint = UInt32(integer)
            if (0xD800 ... 0xDFFF).contains(codePoint) {
                return .error(.notAvailable)
            }
            guard let scalar = UnicodeScalar(codePoint) else {
                return .error(.notAvailable)
            }
            return .text(String(Character(scalar)))
        case "UNICODE":
            guard arguments.count == 1,
                  let value = evaluate(arguments[0]) else {
                return arguments.count == 1 ? nil : .error(.value)
            }
            if value.error != nil { return value }
            guard let scalar = value.text.unicodeScalars.first else {
                return .error(.value)
            }
            return .number(Double(scalar.value))
        case "VALUE":
            guard arguments.count == 1,
                  let value = evaluate(arguments[0]) else {
                return arguments.count == 1 ? nil : .error(.value)
            }
            if value.error != nil { return value }
            if case .number = value { return value }
            guard case .text(let text) = value,
                  let number = parsedExcelValue(text) else {
                return .error(.value)
            }
            return finiteNumber(number)
        case "TEXT":
            guard arguments.count == 2,
                  let value = evaluate(arguments[0]),
                  let formatValue = evaluate(arguments[1]) else {
                return arguments.count == 2 ? nil : .error(.value)
            }
            if let error = value.error ?? formatValue.error {
                return .error(error)
            }
            guard let number = value.number else {
                return .error(.value)
            }
            return formattedExcelText(number, format: formatValue.text)
        case "TEXTBEFORE", "TEXTAFTER":
            return textBoundaryFunction(name, arguments: arguments)
        default:
            return nil
        }
    }

    private func fixedTextFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        let allowedCount = name == "FIXED" ? 1 ... 3 : 1 ... 2
        guard allowedCount.contains(arguments.count),
              let numberValue = evaluate(arguments[0]) else {
            return allowedCount.contains(arguments.count)
                ? nil : .error(.value)
        }
        if numberValue.error != nil { return numberValue }
        let number: Double?
        switch numberValue {
        case .blank:
            number = 0
        case .text(let text):
            number = parsedExcelValue(text)
        case .number(let value):
            number = value
        case .boolean(let value):
            number = value ? 1 : 0
        case .error:
            number = nil
        }
        guard let number, number.isFinite else {
            return .error(.value)
        }

        var decimalCount = 2
        if arguments.count >= 2, !isOmitted(arguments[1]) {
            guard let value = evaluate(arguments[1]) else { return nil }
            if value.error != nil { return value }
            guard let decimals = value.number, decimals.isFinite else {
                return .error(.value)
            }
            let truncated = decimals.rounded(.towardZero)
            guard truncated >= -127, truncated <= 127 else {
                return .error(.value)
            }
            decimalCount = Int(truncated)
        }

        var usesGrouping = true
        if name == "FIXED", arguments.count == 3,
           !isOmitted(arguments[2]) {
            guard let value = evaluate(arguments[2]) else { return nil }
            if value.error != nil { return value }
            guard let noCommas = value.boolean else {
                return .error(.value)
            }
            usesGrouping = !noCommas
        }

        let rounded = roundedNumber(
            number,
            digits: Double(decimalCount),
            rule: .toNearestOrAwayFromZero
        )
        if rounded.error != nil { return rounded }
        guard case .number(let roundedNumber) = rounded else { return nil }

        let fractionDigits = max(0, decimalCount)
        var coreFormat = usesGrouping ? "#,##0" : "0"
        if fractionDigits > 0 {
            coreFormat += "." + String(
                repeating: "0",
                count: fractionDigits
            )
        }
        let format: String
        if name == "DOLLAR" {
            format = "$" + coreFormat + ";($" + coreFormat + ")"
        } else {
            format = coreFormat
        }
        return formattedExcelText(roundedNumber, format: format)
    }

    private func numberValueFunction(
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard (1 ... 3).contains(arguments.count),
              let textValue = evaluate(arguments[0]) else {
            return (1 ... 3).contains(arguments.count)
                ? nil : .error(.value)
        }
        if textValue.error != nil { return textValue }

        let locale = Locale.current
        var decimalSeparator = locale.decimalSeparator?.first ?? "."
        if arguments.count >= 2, !isOmitted(arguments[1]) {
            guard let value = evaluate(arguments[1]) else { return nil }
            if value.error != nil { return value }
            guard let separator = value.text.first else {
                return .error(.value)
            }
            decimalSeparator = separator
        }
        var groupSeparator = locale.groupingSeparator?.first ?? ","
        if arguments.count == 3, !isOmitted(arguments[2]) {
            guard let value = evaluate(arguments[2]) else { return nil }
            if value.error != nil { return value }
            guard let separator = value.text.first else {
                return .error(.value)
            }
            groupSeparator = separator
        }
        guard decimalSeparator != groupSeparator else {
            return .error(.value)
        }

        var text = textValue.text.filter {
            !$0.isWhitespace && $0 != "\u{00A0}"
        }
        if text.isEmpty { return .number(0) }

        var percentageCount = 0
        while text.last == "%" {
            percentageCount += 1
            text.removeLast()
        }
        guard !text.isEmpty, !text.contains("%") else {
            return .error(.value)
        }

        let decimalCount = text.filter { $0 == decimalSeparator }.count
        guard decimalCount <= 1 else { return .error(.value) }
        if let decimalIndex = text.firstIndex(of: decimalSeparator),
           text[text.index(after: decimalIndex)...]
               .contains(groupSeparator) {
            return .error(.value)
        }

        var normalized = ""
        for character in text {
            if character == groupSeparator { continue }
            if character == decimalSeparator {
                normalized.append(".")
            } else if character == "−" {
                normalized.append("-")
            } else {
                normalized.append(character)
            }
        }
        guard let number = Double(normalized), number.isFinite else {
            return .error(.value)
        }
        return finiteNumber(
            number / pow(100, Double(percentageCount))
        )
    }

    private func textBoundaryFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard (2 ... 6).contains(arguments.count),
              let textValue = evaluate(arguments[0]),
              let delimiterValue = evaluate(arguments[1]) else {
            return (2 ... 6).contains(arguments.count)
                ? nil : .error(.value)
        }
        if let error = textValue.error ?? delimiterValue.error {
            return .error(error)
        }

        var instance = 1
        if arguments.count >= 3, !isOmitted(arguments[2]) {
            guard let value = evaluate(arguments[2]) else { return nil }
            if value.error != nil { return value }
            guard let number = value.number, number.isFinite else {
                return .error(.value)
            }
            let integer = number.rounded(.towardZero)
            guard integer != 0,
                  abs(integer) <= Double(textValue.text.count),
                  abs(integer) <= Double(Int.max / 2) else {
                return .error(.value)
            }
            instance = Int(integer)
        }

        var matchMode = 0
        if arguments.count >= 4, !isOmitted(arguments[3]) {
            guard let value = evaluate(arguments[3]) else { return nil }
            if value.error != nil { return value }
            guard let number = value.number, number.isFinite else {
                return .error(.value)
            }
            matchMode = Int(number.rounded(.towardZero))
            guard matchMode == 0 || matchMode == 1 else {
                return .error(.value)
            }
        }

        var matchEnd = false
        if arguments.count >= 5, !isOmitted(arguments[4]) {
            guard let value = evaluate(arguments[4]) else { return nil }
            if value.error != nil { return value }
            guard let number = value.number, number.isFinite else {
                return .error(.value)
            }
            let integer = Int(number.rounded(.towardZero))
            guard integer == 0 || integer == 1 else {
                return .error(.value)
            }
            matchEnd = integer == 1
        }

        let text = textValue.text
        let delimiter = delimiterValue.text
        if text.isEmpty { return .text("") }
        if delimiter.isEmpty {
            return .text(
                name == "TEXTBEFORE"
                    ? (instance > 0 ? "" : text)
                    : (instance > 0 ? text : "")
            )
        }

        let options: String.CompareOptions = matchMode == 1
            ? [.caseInsensitive] : []
        var matches = [Range<String.Index>]()
        var start = text.startIndex
        while start < text.endIndex,
              let range = text.range(
                  of: delimiter,
                  options: options,
                  range: start ..< text.endIndex
              ) {
            matches.append(range)
            start = range.upperBound
        }
        if matchEnd, matches.last?.upperBound != text.endIndex {
            matches.append(text.endIndex ..< text.endIndex)
        }

        let matchIndex = instance > 0
            ? instance - 1 : matches.count + instance
        guard matches.indices.contains(matchIndex) else {
            if arguments.count == 6, !isOmitted(arguments[5]) {
                return evaluate(arguments[5])
            }
            return .error(.notAvailable)
        }
        let match = matches[matchIndex]
        if name == "TEXTBEFORE" {
            return checkedText(String(text[..<match.lowerBound]))
        }
        return checkedText(String(text[match.upperBound...]))
    }

    private func isOmitted(_ expression: ExcelFormulaExpression) -> Bool {
        if case .literal(.blank) = expression { return true }
        return false
    }

    private func parsedExcelValue(_ source: String) -> Double? {
        var text = source.trimmingCharacters(in: CharacterSet(
            charactersIn: " \t\r\n\u{00A0}"
        ))
        guard !text.isEmpty else { return nil }

        var negative = false
        if text.hasPrefix("("), text.hasSuffix(")") {
            negative = true
            text.removeFirst()
            text.removeLast()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var percentageCount = 0
        while text.hasSuffix("%") {
            percentageCount += 1
            text.removeLast()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let currencySymbols = CharacterSet(charactersIn: "$₩€£¥")
        text = text.trimmingCharacters(in: currencySymbols)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let time = parsedClockValue(text) {
            let signed = negative ? -time : time
            return signed / pow(100, Double(percentageCount))
        }
        if let date = parsedDateValue(text),
           let serial = excelDateTimeSerial(for: date) {
            let signed = negative ? -serial : serial
            return signed / pow(100, Double(percentageCount))
        }
        if let fraction = parsedFractionValue(text) {
            let signed = negative ? -fraction : fraction
            return signed / pow(100, Double(percentageCount))
        }

        let normalized = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "−", with: "-")
        guard let number = Double(normalized) else { return nil }
        let signed = negative ? -abs(number) : number
        return signed / pow(100, Double(percentageCount))
    }

    private func parsedClockValue(_ text: String) -> Double? {
        let pattern = #"^(\d{1,2}):(\d{2})(?::(\d{2}(?:\.\d+)?))?\s*(AM|PM)?$"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = expression.firstMatch(
            in: text,
            options: [],
            range: range
        ), match.range == range else {
            return nil
        }
        func capture(_ index: Int) -> String? {
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: text) else {
                return nil
            }
            return String(text[range])
        }
        guard var hour = capture(1).flatMap(Int.init),
              let minute = capture(2).flatMap(Int.init),
              let second = capture(3).flatMap(Double.init) ?? 0 as Double?,
              minute < 60, second < 60 else {
            return nil
        }
        if let marker = capture(4)?.uppercased() {
            guard (1 ... 12).contains(hour) else { return nil }
            if marker == "AM" {
                if hour == 12 { hour = 0 }
            } else if hour != 12 {
                hour += 12
            }
        } else if hour >= 24 {
            return nil
        }
        return (Double(hour * 3_600 + minute * 60) + second) / 86_400
    }

    private func parsedDateValue(_ text: String) -> Date? {
        let formats = [
            "yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss",
            "M/d/yyyy H:mm:ss", "M/d/yyyy h:mm:ss a",
            "yyyy-MM-dd", "yyyy/M/d", "M/d/yyyy", "M/d/yy",
            "d-MMM-yyyy", "d-MMM-yy",
        ]
        for locale in [Locale.current, Locale(identifier: "en_US_POSIX")] {
            for format in formats {
                let formatter = DateFormatter()
                formatter.calendar = gregorianCalendar
                formatter.locale = locale
                formatter.timeZone = timeZone
                formatter.dateFormat = format
                formatter.isLenient = false
                if let date = formatter.date(from: text) {
                    return date
                }
            }
        }
        return nil
    }

    private func parsedFractionValue(_ text: String) -> Double? {
        let parts = text.split(separator: " ", omittingEmptySubsequences: true)
        guard let fractionText = parts.last,
              fractionText.contains("/") else {
            return nil
        }
        let fraction = fractionText.split(separator: "/")
        guard fraction.count == 2,
              let numerator = Double(fraction[0]),
              let denominator = Double(fraction[1]),
              denominator != 0 else {
            return nil
        }
        if parts.count == 1 { return numerator / denominator }
        guard parts.count == 2, let whole = Double(parts[0]) else {
            return nil
        }
        return whole + (whole < 0 ? -1 : 1) * numerator / denominator
    }

    private func formattedExcelText(
        _ number: Double,
        format: String
    ) -> ExcelFormulaValue {
        guard number.isFinite else { return .error(.value) }
        guard !format.isEmpty else { return .text("") }
        let selection = selectedFormatSection(format, number: number)
        let section = selection.section
        guard !section.isEmpty else { return .text("") }
        if section.caseInsensitiveCompare("General") == .orderedSame {
            return .text(formulaNumberText(number))
        }
        if isExcelDateFormat(section) {
            guard let text = formattedExcelDate(number, format: section) else {
                return .error(.value)
            }
            return checkedText(text)
        }
        guard let text = formattedExcelNumber(
            selection.useAbsoluteValue ? abs(number) : number,
            format: section
        ) else {
            return .error(.value)
        }
        return checkedText(text)
    }

    private func selectedFormatSection(
        _ format: String,
        number: Double
    ) -> (section: String, useAbsoluteValue: Bool) {
        let sections = splitFormatSections(format)
        if number < 0, sections.count >= 2 {
            return (sections[1], true)
        }
        if number == 0, sections.count >= 3 {
            return (sections[2], false)
        }
        return (sections.first ?? format, false)
    }

    private func splitFormatSections(_ format: String) -> [String] {
        var result = [String]()
        var current = ""
        var quoted = false
        var escaped = false
        for character in format {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                current.append(character)
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
                current.append(character)
            } else if character == ";", !quoted {
                result.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        result.append(current)
        return result
    }

    private func formatTokens(
        _ format: String
    ) -> [(character: Character, literal: Bool)] {
        let characters = Array(format)
        var result = [(Character, Bool)]()
        var index = 0
        var quoted = false
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                quoted.toggle()
                index += 1
                continue
            }
            if !quoted, character == "\\", index + 1 < characters.count {
                result.append((characters[index + 1], true))
                index += 2
                continue
            }
            if !quoted, character == "_", index + 1 < characters.count {
                result.append((" ", true))
                index += 2
                continue
            }
            if !quoted, character == "*", index + 1 < characters.count {
                index += 2
                continue
            }
            if !quoted, character == "[",
               let close = characters[(index + 1)...].firstIndex(of: "]") {
                let content = String(characters[(index + 1)..<close])
                if ["h", "m", "s"].contains(content.lowercased()) {
                    result.append((Character(content.lowercased()), false))
                }
                index = close + 1
                continue
            }
            result.append((character, quoted))
            index += 1
        }
        return result
    }

    private func isExcelDateFormat(_ format: String) -> Bool {
        let tokens = formatTokens(format)
        var hasMonth = false
        var hasNumericPlaceholder = false
        for token in tokens where !token.literal {
            switch token.character.lowercased() {
            case "y", "d", "h", "s": return true
            case "m": hasMonth = true
            case "0", "#", "?": hasNumericPlaceholder = true
            default: break
            }
        }
        return hasMonth && !hasNumericPlaceholder
    }

    private func formattedExcelDate(
        _ serial: Double,
        format: String
    ) -> String? {
        guard let parts = excelDateParts(for: serial),
              let seconds = timeSecondOfDay(for: serial) else {
            return nil
        }
        let characters = Array(format)
        let lowerFormat = format.lowercased()
        let usesTwelveHour = lowerFormat.contains("am/pm")
            || lowerFormat.contains("a/p")
        let firstHour = characters.firstIndex {
            $0.lowercased() == "h"
        }
        let hasSecond = characters.contains { $0.lowercased() == "s" }
        let hour24 = seconds / 3_600
        let minute = seconds / 60 % 60
        let second = seconds % 60
        let formatter = DateFormatter()
        formatter.locale = .current
        let months = formatter.monthSymbols ?? []
        let shortMonths = formatter.shortMonthSymbols ?? []
        let weekdays = formatter.weekdaySymbols ?? []
        let shortWeekdays = formatter.shortWeekdaySymbols ?? []
        let weekdayIndex = weekday(
            serial: Int(floor(serial)),
            returnType: 1
        ).map { $0 - 1 }

        func padded(_ value: Int, count: Int) -> String {
            String(format: "%0\(count)d", value)
        }
        func runLength(from start: Int, character: Character) -> Int {
            var end = start
            while end < characters.count,
                  characters[end].lowercased()
                    == character.lowercased() {
                end += 1
            }
            return end - start
        }

        var result = ""
        var index = 0
        var quoted = false
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                quoted.toggle()
                index += 1
                continue
            }
            if !quoted, character == "\\", index + 1 < characters.count {
                result.append(characters[index + 1])
                index += 2
                continue
            }
            if !quoted, character == "_", index + 1 < characters.count {
                result.append(" ")
                index += 2
                continue
            }
            if !quoted, character == "*", index + 1 < characters.count {
                index += 2
                continue
            }
            if !quoted, character == "[",
               let close = characters[(index + 1)...].firstIndex(of: "]") {
                let content = String(characters[(index + 1)..<close])
                    .lowercased()
                switch content {
                case "h": result += String(Int(floor(serial * 24)))
                case "m": result += String(Int(floor(serial * 1_440)))
                case "s": result += String(Int(floor(serial * 86_400)))
                default: break
                }
                index = close + 1
                continue
            }
            if !quoted {
                let remainder = String(characters[index...]).lowercased()
                if remainder.hasPrefix("am/pm") {
                    result += hour24 < 12
                        ? (formatter.amSymbol ?? "AM")
                        : (formatter.pmSymbol ?? "PM")
                    index += 5
                    continue
                }
                if remainder.hasPrefix("a/p") {
                    let symbol = hour24 < 12
                        ? (formatter.amSymbol ?? "A")
                        : (formatter.pmSymbol ?? "P")
                    result += String(symbol.prefix(1))
                    index += 3
                    continue
                }
            }
            guard !quoted else {
                result.append(character)
                index += 1
                continue
            }
            let lower = character.lowercased()
            if ["y", "m", "d", "h", "s"].contains(lower) {
                let count = runLength(from: index, character: character)
                switch lower {
                case "y":
                    result += count == 2
                        ? padded(parts.year % 100, count: 2)
                        : padded(parts.year, count: max(4, count))
                case "d":
                    if count == 1 { result += String(parts.day) }
                    else if count == 2 { result += padded(parts.day, count: 2) }
                    else if count == 3,
                            let weekdayIndex,
                            shortWeekdays.indices.contains(weekdayIndex) {
                        result += shortWeekdays[weekdayIndex]
                    } else if let weekdayIndex,
                              weekdays.indices.contains(weekdayIndex) {
                        result += weekdays[weekdayIndex]
                    }
                case "m":
                    let minuteToken = firstHour.map { index > $0 } ?? hasSecond
                    if minuteToken {
                        result += count >= 2
                            ? padded(minute, count: 2) : String(minute)
                    } else if count == 1 {
                        result += String(parts.month)
                    } else if count == 2 {
                        result += padded(parts.month, count: 2)
                    } else if count == 3,
                              shortMonths.indices.contains(parts.month - 1) {
                        result += shortMonths[parts.month - 1]
                    } else if months.indices.contains(parts.month - 1) {
                        result += months[parts.month - 1]
                    }
                case "h":
                    let hour = usesTwelveHour
                        ? (hour24 % 12 == 0 ? 12 : hour24 % 12)
                        : hour24
                    result += count >= 2
                        ? padded(hour, count: 2) : String(hour)
                case "s":
                    result += count >= 2
                        ? padded(second, count: 2) : String(second)
                default: break
                }
                index += count
            } else {
                result.append(character)
                index += 1
            }
        }
        return result
    }

    private func formattedExcelNumber(
        _ number: Double,
        format: String
    ) -> String? {
        let tokens = formatTokens(format)
        let placeholders = tokens.indices.filter {
            !tokens[$0].literal
                && ["0", "#", "?"].contains(tokens[$0].character)
        }
        guard let first = placeholders.first,
              let last = placeholders.last else {
            return tokens.map(\.character).map(String.init).joined()
        }
        let core = String(tokens[first ... last].map(\.character))
        let prefix = String(tokens[..<first].map(\.character))
        var suffixTokens = Array(tokens[(last + 1)...])
        var scaleCount = 0
        while suffixTokens.first?.character == ",",
              suffixTokens.first?.literal == false {
            scaleCount += 1
            suffixTokens.removeFirst()
        }
        let suffix = String(suffixTokens.map(\.character))
        let percentageCount = tokens.filter {
            !$0.literal && $0.character == "%"
        }.count
        let scaled = number * pow(100, Double(percentageCount))
            / pow(1_000, Double(scaleCount))

        if core.uppercased().contains("E+")
            || core.uppercased().contains("E-") {
            guard let scientific = formattedScientificNumber(
                scaled,
                core: core
            ) else { return nil }
            return prefix + scientific + suffix
        }
        if core.contains("/") {
            guard let fraction = formattedFractionNumber(
                scaled,
                core: core
            ) else { return nil }
            return prefix + fraction + suffix
        }
        let maskCharacters = Set(core).subtracting(["0", "#", "?", ","])
        if !maskCharacters.isEmpty, !core.contains(".") {
            return prefix + formattedDigitMask(scaled, mask: core) + suffix
        }

        let decimalIndex = core.firstIndex(of: ".")
        let integerPart = decimalIndex.map { core[..<$0] }
            ?? core[core.startIndex...]
        let fractionalPart = decimalIndex.map {
            core[core.index(after: $0)...]
        } ?? Substring()
        let minimumIntegerDigits = integerPart.filter { $0 == "0" }.count
        let minimumFractionDigits = fractionalPart.filter { $0 == "0" }.count
        let maximumFractionDigits = fractionalPart.filter {
            $0 == "0" || $0 == "#" || $0 == "?"
        }.count
        if scaled == 0, minimumIntegerDigits == 0,
           maximumFractionDigits == 0 {
            return prefix + suffix
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = integerPart.contains(",")
        formatter.minimumIntegerDigits = minimumIntegerDigits
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.roundingMode = .halfUp
        guard let formatted = formatter.string(
            from: NSNumber(value: scaled)
        ) else {
            return nil
        }
        return prefix + formatted + suffix
    }

    private func formattedScientificNumber(
        _ number: Double,
        core: String
    ) -> String? {
        let upper = core.uppercased()
        guard let exponentIndex = upper.firstIndex(of: "E") else {
            return nil
        }
        let mantissaPattern = upper[..<exponentIndex]
        let exponentPattern = upper[upper.index(after: exponentIndex)...]
        let fractionDigits = mantissaPattern.firstIndex(of: ".").map {
            mantissaPattern[mantissaPattern.index(after: $0)...]
                .filter { $0 == "0" || $0 == "#" }.count
        } ?? 0
        let exponentDigits = max(
            1,
            exponentPattern.filter { $0 == "0" }.count
        )
        let exponent: Int
        let mantissa: Double
        if number == 0 {
            exponent = 0
            mantissa = 0
        } else {
            exponent = Int(floor(log10(abs(number))))
            mantissa = number / pow(10, Double(exponent))
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumIntegerDigits = 1
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.roundingMode = .halfUp
        guard let text = formatter.string(from: NSNumber(value: mantissa)) else {
            return nil
        }
        let showsPositiveSign = exponentPattern.first == "+"
        let sign = exponent < 0 ? "-" : (showsPositiveSign ? "+" : "")
        return text + "E" + sign
            + String(format: "%0\(exponentDigits)d", abs(exponent))
    }

    private func formattedFractionNumber(
        _ number: Double,
        core: String
    ) -> String? {
        guard let slash = core.firstIndex(of: "/") else { return nil }
        let denominatorDigits = core[core.index(after: slash)...]
            .filter { $0 == "0" || $0 == "#" || $0 == "?" }.count
        guard denominatorDigits > 0 else { return nil }
        let maximumDenominator = min(
            9_999,
            Int(pow(10, Double(denominatorDigits))) - 1
        )
        let sign = number < 0 ? "-" : ""
        let magnitude = abs(number)
        let hasWholePart = core[..<slash].contains(" ")
        let whole = Int(floor(magnitude))
        let fraction = magnitude - Double(whole)
        var bestNumerator = 0
        var bestDenominator = 1
        var bestError = Double.greatestFiniteMagnitude
        for denominator in 1 ... maximumDenominator {
            let numerator = Int(
                (fraction * Double(denominator)).rounded()
            )
            let error = abs(
                fraction - Double(numerator) / Double(denominator)
            )
            if error < bestError {
                bestError = error
                bestNumerator = numerator
                bestDenominator = denominator
            }
        }
        var adjustedWhole = whole
        if bestNumerator == bestDenominator {
            adjustedWhole += 1
            bestNumerator = 0
        }
        if bestNumerator == 0 { return sign + String(adjustedWhole) }
        if hasWholePart {
            let wholeText = adjustedWhole == 0 ? "" : "\(adjustedWhole) "
            return sign + wholeText
                + "\(bestNumerator)/\(bestDenominator)"
        }
        let improper = adjustedWhole * bestDenominator + bestNumerator
        return sign + "\(improper)/\(bestDenominator)"
    }

    private func formattedDigitMask(
        _ number: Double,
        mask: String
    ) -> String {
        var digits = Array(String(Int(abs(number).rounded())))
        var result = [Character]()
        for character in mask.reversed() {
            if character == "0" || character == "#" || character == "?" {
                if let digit = digits.popLast() {
                    result.append(digit)
                } else if character == "0" {
                    result.append("0")
                } else if character == "?" {
                    result.append(" ")
                }
            } else if character != "," {
                result.append(character)
            }
        }
        result.append(contentsOf: digits.reversed())
        if number < 0 { result.append("-") }
        return String(result.reversed())
    }

    private func formulaNumberText(_ value: Double) -> String {
        if value.rounded() == value,
           value >= Double(Int64.min), value <= Double(Int64.max) {
            return String(Int64(value))
        }
        return String(
            format: "%.15g",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }

    private func textFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        if name == "REPT" {
            guard arguments.count == 2,
                  let textValue = evaluate(arguments[0]),
                  let countValue = evaluate(arguments[1]) else {
                return arguments.count == 2 ? nil : .error(.value)
            }
            if let error = textValue.error ?? countValue.error {
                return .error(error)
            }
            guard let count = countValue.number, count.isFinite else {
                return .error(.value)
            }
            let repetitionCount = count.rounded(.towardZero)
            guard repetitionCount >= 0 else { return .error(.value) }
            if textValue.text.isEmpty || repetitionCount == 0 {
                return .text("")
            }
            guard repetitionCount
                    <= Double(32_767 / textValue.text.count) else {
                return .error(.value)
            }
            return .text(String(
                repeating: textValue.text,
                count: Int(repetitionCount)
            ))
        }
        let allowedCount = name == "LEN" ? 1 ... 1 : 1 ... 2
        guard allowedCount.contains(arguments.count) else {
            return .error(.value)
        }
        guard let value = evaluate(arguments[0]) else { return nil }
        if value.error != nil { return value }
        let text = value.text
        if name == "LEN" {
            return .number(Double(text.count))
        }
        var characterCount = 1
        if arguments.count == 2 {
            guard let countValue = evaluate(arguments[1]) else { return nil }
            if countValue.error != nil { return countValue }
            guard let number = countValue.number, number.isFinite else {
                return .error(.value)
            }
            let truncated = number.rounded(.towardZero)
            guard truncated >= 0 else { return .error(.value) }
            if truncated >= Double(text.count) {
                return .text(text)
            }
            characterCount = Int(truncated)
        }
        switch name {
        case "LEFT":
            return .text(String(text.prefix(characterCount)))
        case "RIGHT":
            return .text(String(text.suffix(characterCount)))
        default:
            return nil
        }
    }

    private func advancedTextFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        switch name {
        case "MID":
            guard arguments.count == 3,
                  let textValue = evaluate(arguments[0]),
                  let startValue = evaluate(arguments[1]),
                  let countValue = evaluate(arguments[2]) else {
                return arguments.count == 3 ? nil : .error(.value)
            }
            if let error = textValue.error
                ?? startValue.error
                ?? countValue.error {
                return .error(error)
            }
            guard let startNumber = startValue.number,
                  let countNumber = countValue.number,
                  startNumber.isFinite, countNumber.isFinite else {
                return .error(.value)
            }
            let start = startNumber.rounded(.towardZero)
            let count = countNumber.rounded(.towardZero)
            guard start >= 1, count >= 0 else { return .error(.value) }
            let characters = Array(textValue.text)
            guard start <= Double(characters.count) else {
                return .text("")
            }
            if count == 0 { return .text("") }
            let startIndex = Int(start) - 1
            let available = characters.count - startIndex
            let resultCount = count >= Double(available)
                ? available : Int(count)
            return .text(String(
                characters[startIndex ..< startIndex + resultCount]
            ))
        case "FIND", "SEARCH":
            guard (2 ... 3).contains(arguments.count),
                  let needleValue = evaluate(arguments[0]),
                  let textValue = evaluate(arguments[1]) else {
                return (2 ... 3).contains(arguments.count)
                    ? nil : .error(.value)
            }
            if let error = needleValue.error ?? textValue.error {
                return .error(error)
            }
            var start = 1
            if arguments.count == 3 {
                guard let startValue = evaluate(arguments[2]) else {
                    return nil
                }
                if startValue.error != nil { return startValue }
                guard let number = startValue.number, number.isFinite,
                      number >= 1,
                      number.rounded(.towardZero)
                          <= Double(textValue.text.count) else {
                    return .error(.value)
                }
                start = Int(number.rounded(.towardZero))
            } else if textValue.text.isEmpty {
                return needleValue.text.isEmpty
                    ? .number(1) : .error(.value)
            }
            let text = textValue.text
            let needle = needleValue.text
            let searchStart = text.index(
                text.startIndex,
                offsetBy: start - 1
            )
            if needle.isEmpty { return .number(Double(start)) }
            let matchStart: String.Index?
            if name == "FIND" {
                matchStart = text.range(
                    of: needle,
                    options: [],
                    range: searchStart ..< text.endIndex
                )?.lowerBound
            } else {
                guard let expression = wildcardRegularExpression(
                    pattern: needle,
                    anchored: false
                ) else {
                    return .error(.value)
                }
                let range = NSRange(searchStart ..< text.endIndex, in: text)
                matchStart = expression.firstMatch(
                    in: text,
                    options: [],
                    range: range
                ).flatMap { Range($0.range, in: text)?.lowerBound }
            }
            guard let matchStart else { return .error(.value) }
            return .number(Double(
                text.distance(from: text.startIndex, to: matchStart) + 1
            ))
        case "SUBSTITUTE":
            guard (3 ... 4).contains(arguments.count) else {
                return .error(.value)
            }
            var values = [ExcelFormulaValue]()
            for argument in arguments {
                guard let value = evaluate(argument) else { return nil }
                if value.error != nil { return value }
                values.append(value)
            }
            let text = values[0].text
            let oldText = values[1].text
            let newText = values[2].text
            guard !oldText.isEmpty else { return .text(text) }
            if arguments.count == 3 {
                return checkedText(text.replacingOccurrences(
                    of: oldText,
                    with: newText
                ))
            }
            guard let number = values[3].number, number.isFinite else {
                return .error(.value)
            }
            let instance = number.rounded(.towardZero)
            guard instance >= 1, instance <= Double(Int.max / 2) else {
                return .error(.value)
            }
            var occurrence = 0
            var searchStart = text.startIndex
            while searchStart <= text.endIndex,
                  let range = text.range(
                      of: oldText,
                      options: [],
                      range: searchStart ..< text.endIndex
                  ) {
                occurrence += 1
                if occurrence == Int(instance) {
                    var result = text
                    result.replaceSubrange(range, with: newText)
                    return checkedText(result)
                }
                searchStart = range.upperBound
            }
            return .text(text)
        default:
            return nil
        }
    }

    private func textJoiningFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        switch name {
        case "CONCATENATE":
            guard (1 ... 255).contains(arguments.count) else {
                return .error(.value)
            }
            var result = ""
            var characterCount = 0
            for argument in arguments {
                if supportsDynamicArrays, case .range = argument {
                    return .error(.value)
                }
                guard let value = evaluate(argument) else { return nil }
                if value.error != nil { return value }
                let text = value.text
                characterCount += text.count
                guard characterCount <= 8_192 else {
                    return .error(.value)
                }
                result += text
            }
            return .text(result)
        case "CONCAT":
            guard (1 ... 253).contains(arguments.count) else {
                return .error(.value)
            }
            var result = ""
            var characterCount = 0
            for argument in arguments {
                guard let values = expandedValues(argument) else {
                    return nil
                }
                for item in values {
                    if let error = item.value.error { return .error(error) }
                    let text = item.value.text
                    characterCount += text.count
                    guard characterCount <= 32_767 else {
                        return .error(.value)
                    }
                    result += text
                }
            }
            return .text(result)
        case "TEXTJOIN":
            guard (3 ... 254).contains(arguments.count) else {
                return .error(.value)
            }
            guard let delimiterItems = expandedValues(arguments[0]),
                  !delimiterItems.isEmpty,
                  let ignoreValue = evaluate(arguments[1]) else {
                return nil
            }
            if ignoreValue.error != nil { return ignoreValue }
            guard let ignoreEmpty = ignoreValue.boolean else {
                return .error(.value)
            }
            var delimiters = [String]()
            for item in delimiterItems {
                if let error = item.value.error { return .error(error) }
                delimiters.append(item.value.text)
            }
            var textItems = [String]()
            for argument in arguments.dropFirst(2) {
                guard let values = expandedValues(argument) else {
                    return nil
                }
                for item in values {
                    if let error = item.value.error { return .error(error) }
                    let text = item.value.text
                    if ignoreEmpty && text.isEmpty { continue }
                    textItems.append(text)
                }
            }
            var result = ""
            var characterCount = 0
            for index in textItems.indices {
                if index > 0 {
                    let delimiter = delimiters[(index - 1) % delimiters.count]
                    characterCount += delimiter.count
                    guard characterCount <= 32_767 else {
                        return .error(.value)
                    }
                    result += delimiter
                }
                characterCount += textItems[index].count
                guard characterCount <= 32_767 else {
                    return .error(.value)
                }
                result += textItems[index]
            }
            return .text(result)
        default:
            return nil
        }
    }

    private func checkedText(_ text: String) -> ExcelFormulaValue {
        text.count <= 32_767 ? .text(text) : .error(.value)
    }

    private func textCleanupFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        if name == "REPLACE" {
            guard arguments.count == 4 else { return .error(.value) }
            var values = [ExcelFormulaValue]()
            for argument in arguments {
                guard let value = evaluate(argument) else { return nil }
                if value.error != nil { return value }
                values.append(value)
            }
            guard let startNumber = values[1].number,
                  let countNumber = values[2].number,
                  startNumber.isFinite, countNumber.isFinite else {
                return .error(.value)
            }
            let start = startNumber.rounded(.towardZero)
            let count = countNumber.rounded(.towardZero)
            guard start >= 1, count >= 0 else { return .error(.value) }

            let characters = Array(values[0].text)
            let startIndex: Int
            if start > Double(characters.count) {
                startIndex = characters.count
            } else {
                startIndex = Int(start) - 1
            }
            let available = characters.count - startIndex
            let removedCount = count >= Double(available)
                ? available : Int(count)
            let suffixStart = startIndex + removedCount
            let result = String(characters[..<startIndex])
                + values[3].text
                + String(characters[suffixStart...])
            return checkedText(result)
        }

        guard arguments.count == 1,
              let value = evaluate(arguments[0]) else {
            return arguments.count == 1 ? nil : .error(.value)
        }
        if value.error != nil { return value }
        let text = value.text
        switch name {
        case "LOWER":
            return checkedText(text.lowercased())
        case "UPPER":
            return checkedText(text.uppercased())
        case "PROPER":
            var result = ""
            var capitalizesNextLetter = true
            for character in text {
                let piece = String(character)
                if character.isLetter {
                    result += capitalizesNextLetter
                        ? piece.uppercased() : piece.lowercased()
                    capitalizesNextLetter = false
                } else {
                    result += piece
                    capitalizesNextLetter = true
                }
            }
            return checkedText(result)
        case "TRIM":
            return checkedText(text.split(
                separator: " ",
                omittingEmptySubsequences: true
            ).joined(separator: " "))
        case "CLEAN":
            var result = ""
            for scalar in text.unicodeScalars where scalar.value > 31 {
                result.unicodeScalars.append(scalar)
            }
            return checkedText(result)
        default:
            return nil
        }
    }

    private func logicalFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard !arguments.isEmpty else { return nil }
        var booleans = [Bool]()
        for argument in arguments {
            guard let values = expandedValues(argument) else { return nil }
            for item in values {
                if let error = item.value.error {
                    return .error(error)
                }
                if item.comesFromReference {
                    switch item.value {
                    case .number(let number):
                        booleans.append(number != 0)
                    case .boolean(let boolean):
                        booleans.append(boolean)
                    case .blank, .text:
                        continue
                    case .error:
                        break
                    }
                } else if let boolean = item.value.boolean {
                    booleans.append(boolean)
                } else {
                    return .error(.value)
                }
            }
        }
        guard !booleans.isEmpty else { return .error(.value) }
        switch name {
        case "AND":
            return .boolean(booleans.allSatisfy { $0 })
        case "OR":
            return .boolean(booleans.contains(true))
        case "XOR":
            return .boolean(!booleans.filter { $0 }.count.isMultiple(of: 2))
        default:
            return nil
        }
    }

    private func aggregateFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard !arguments.isEmpty else { return nil }
        var values = [ExcelFormulaArgumentValue]()
        for argument in arguments {
            guard let expanded = expandedValues(argument) else {
                return nil
            }
            values.append(contentsOf: expanded)
        }
        if name == "COUNTA" {
            return .number(Double(values.filter {
                if case .blank = $0.value { return false }
                return true
            }.count))
        }
        if name == "COUNT" {
            let count = values.reduce(into: 0) { result, item in
                switch item.value {
                case .number:
                    result += 1
                case .boolean:
                    if !item.comesFromReference { result += 1 }
                case .text(let text):
                    if !item.comesFromReference,
                       Double(text.trimmingCharacters(
                           in: .whitespacesAndNewlines
                       )) != nil {
                        result += 1
                    }
                case .blank, .error:
                    break
                }
            }
            return .number(Double(count))
        }

        var numbers = [Double]()
        for item in values {
            if let error = item.value.error { return .error(error) }
            switch item.value {
            case .number(let number):
                numbers.append(number)
            case .boolean(let boolean):
                if !item.comesFromReference {
                    numbers.append(boolean ? 1 : 0)
                }
            case .text(let text):
                guard !item.comesFromReference else { continue }
                let trimmed = text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard let number = Double(trimmed) else {
                    return .error(.value)
                }
                numbers.append(number)
            case .blank:
                continue
            case .error:
                break
            }
        }
        switch name {
        case "SUM":
            return finiteNumber(numbers.reduce(0, +))
        case "PRODUCT":
            return finiteNumber(numbers.isEmpty ? 0 : numbers.reduce(1, *))
        case "AVERAGE":
            guard !numbers.isEmpty else { return .error(.divideByZero) }
            return finiteNumber(
                numbers.reduce(0, +) / Double(numbers.count)
            )
        case "MEDIAN":
            guard !numbers.isEmpty else { return .error(.number) }
            let sorted = numbers.sorted()
            let middle = sorted.count / 2
            if !sorted.count.isMultiple(of: 2) {
                return .number(sorted[middle])
            }
            return finiteNumber(
                sorted[middle - 1] / 2 + sorted[middle] / 2
            )
        case "MIN":
            return finiteNumber(numbers.min() ?? 0)
        case "MAX":
            return finiteNumber(numbers.max() ?? 0)
        default:
            return nil
        }
    }

    private func countBlankFunction(
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard arguments.count == 1 else { return .error(.value) }
        guard let range = rangeMatrix(arguments[0]) else {
            return .error(.value)
        }
        let count = range.values.reduce(into: 0) { result, value in
            switch value {
            case .blank, .text(""):
                result += 1
            case .number, .text, .boolean, .error:
                break
            }
        }
        return .number(Double(count))
    }

    private func dispersionFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard (1 ... 255).contains(arguments.count) else {
            return .error(.value)
        }
        var numbers = [Double]()
        for argument in arguments {
            guard let items = expandedValues(argument) else { return nil }
            for item in items {
                if item.comesFromReference {
                    if case .number(let number) = item.value {
                        numbers.append(number)
                    }
                    continue
                }
                switch item.value {
                case .number(let number):
                    numbers.append(number)
                case .boolean(let boolean):
                    numbers.append(boolean ? 1 : 0)
                case .text(let text):
                    guard let number = Double(text.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )) else {
                        return .error(.value)
                    }
                    numbers.append(number)
                case .error(let error):
                    return .error(error)
                case .blank:
                    continue
                }
            }
        }

        let isSample = name.hasSuffix(".S")
        guard numbers.count >= (isSample ? 2 : 1) else {
            return .error(.divideByZero)
        }
        let mean = numbers.reduce(0, +) / Double(numbers.count)
        guard mean.isFinite else { return .error(.number) }
        let squaredDifferences = numbers.reduce(0.0) { result, number in
            let difference = number - mean
            return result + difference * difference
        }
        let divisor = Double(numbers.count - (isSample ? 1 : 0))
        let variance = squaredDifferences / divisor
        guard variance.isFinite else { return .error(.number) }
        return name.hasPrefix("STDEV")
            ? finiteNumber(sqrt(variance)) : .number(variance)
    }

    private func descriptiveStatisticFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard (1 ... 255).contains(arguments.count) else {
            return .error(.value)
        }
        var numbers = [Double]()
        for argument in arguments {
            guard let items = expandedValues(argument) else { return nil }
            for item in items {
                if let error = item.value.error { return .error(error) }
                switch item.value {
                case .number(let number):
                    numbers.append(number)
                case .boolean(let boolean) where !item.comesFromReference:
                    numbers.append(boolean ? 1 : 0)
                case .text(let text) where !item.comesFromReference:
                    guard let number = Double(text.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )) else {
                        return .error(.value)
                    }
                    numbers.append(number)
                case .blank, .boolean, .text, .error:
                    continue
                }
            }
        }
        guard !numbers.isEmpty else {
            return .error(.number)
        }

        switch name {
        case "AVEDEV", "DEVSQ":
            let mean = numbers.reduce(0, +) / Double(numbers.count)
            guard mean.isFinite else { return .error(.number) }
            if name == "AVEDEV" {
                let deviation = numbers.reduce(0.0) {
                    $0 + abs($1 - mean)
                }
                return finiteNumber(deviation / Double(numbers.count))
            }
            let squares = numbers.reduce(0.0) {
                let difference = $1 - mean
                return $0 + difference * difference
            }
            return finiteNumber(squares)
        case "GEOMEAN":
            guard numbers.allSatisfy({ $0 > 0 }) else {
                return .error(.number)
            }
            let logarithms = numbers.reduce(0.0) { $0 + log($1) }
            return finiteNumber(exp(logarithms / Double(numbers.count)))
        case "HARMEAN":
            guard numbers.allSatisfy({ $0 > 0 }) else {
                return .error(.number)
            }
            let reciprocalSum = numbers.reduce(0.0) { $0 + 1 / $1 }
            return finiteNumber(Double(numbers.count) / reciprocalSum)
        default:
            return nil
        }
    }

    private func pairedStatisticFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard arguments.count == 2,
              let first = rangeMatrix(arguments[0]),
              let second = rangeMatrix(arguments[1]) else {
            return arguments.count == 2 ? .error(.value) : .error(.value)
        }
        guard first.rowCount == second.rowCount,
              first.columnCount == second.columnCount else {
            return .error(.notAvailable)
        }

        var pairs = [(first: Double, second: Double)]()
        for index in first.values.indices {
            let firstValue = first.values[index]
            let secondValue = second.values[index]
            if let error = firstValue.error ?? secondValue.error {
                return .error(error)
            }
            guard case .number(let firstNumber) = firstValue,
                  case .number(let secondNumber) = secondValue else {
                continue
            }
            pairs.append((firstNumber, secondNumber))
        }
        let minimumCount = name == "STEYX" ? 3 : 1
        guard pairs.count >= minimumCount else {
            return .error(.divideByZero)
        }

        let count = Double(pairs.count)
        let firstMean = pairs.reduce(0.0) { $0 + $1.first } / count
        let secondMean = pairs.reduce(0.0) { $0 + $1.second } / count
        var firstSquares = 0.0
        var secondSquares = 0.0
        var crossProducts = 0.0
        for pair in pairs {
            let firstDifference = pair.first - firstMean
            let secondDifference = pair.second - secondMean
            firstSquares += firstDifference * firstDifference
            secondSquares += secondDifference * secondDifference
            crossProducts += firstDifference * secondDifference
        }
        guard firstSquares.isFinite, secondSquares.isFinite,
              crossProducts.isFinite else {
            return .error(.number)
        }

        switch name {
        case "COVARIANCE.P":
            return finiteNumber(crossProducts / count)
        case "COVARIANCE.S":
            guard pairs.count >= 2 else { return .error(.divideByZero) }
            return finiteNumber(crossProducts / (count - 1))
        case "CORREL", "PEARSON", "RSQ":
            guard firstSquares > 0, secondSquares > 0 else {
                return .error(.divideByZero)
            }
            let correlation = crossProducts
                / sqrt(firstSquares * secondSquares)
            return name == "RSQ"
                ? finiteNumber(correlation * correlation)
                : finiteNumber(correlation)
        case "SLOPE", "INTERCEPT", "STEYX":
            // Regression functions receive known_y's first and known_x's second.
            guard secondSquares > 0 else {
                return .error(.divideByZero)
            }
            let slope = crossProducts / secondSquares
            if name == "SLOPE" { return finiteNumber(slope) }
            if name == "INTERCEPT" {
                return finiteNumber(firstMean - slope * secondMean)
            }
            let residual = firstSquares
                - crossProducts * crossProducts / secondSquares
            let stabilizedResidual = residual < 0
                && abs(residual) <= 16 * firstSquares.ulp
                ? 0 : residual
            guard stabilizedResidual >= 0 else {
                return .error(.number)
            }
            return finiteNumber(sqrt(stabilizedResidual / (count - 2)))
        default:
            return nil
        }
    }

    private func scalarStatisticFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        let expectedCount = name == "STANDARDIZE" ? 3 : 1
        guard arguments.count == expectedCount else {
            return .error(.value)
        }
        var numbers = [Double]()
        for argument in arguments {
            guard let value = evaluate(argument) else { return nil }
            if value.error != nil { return value }
            guard let number = value.number, number.isFinite else {
                return .error(.value)
            }
            numbers.append(number)
        }
        switch name {
        case "FISHER":
            guard numbers[0] > -1, numbers[0] < 1 else {
                return .error(.number)
            }
            return finiteNumber(
                0.5 * log((1 + numbers[0]) / (1 - numbers[0]))
            )
        case "FISHERINV":
            return finiteNumber(tanh(numbers[0]))
        case "STANDARDIZE":
            guard numbers[2] > 0 else { return .error(.number) }
            return finiteNumber((numbers[0] - numbers[1]) / numbers[2])
        default:
            return nil
        }
    }

    private func numeralSystemFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        if name == "BASE" {
            guard (2 ... 3).contains(arguments.count) else {
                return .error(.value)
            }
            var values = [Double]()
            for argument in arguments {
                guard let value = evaluate(argument) else { return nil }
                if value.error != nil { return value }
                guard let number = value.number, number.isFinite else {
                    return .error(.value)
                }
                values.append(number.rounded(.towardZero))
            }
            let number = values[0]
            let radix = values[1]
            let minimumLength = values.count == 3 ? values[2] : 0
            guard number >= 0, number < 9_007_199_254_740_992,
                  (2 ... 36).contains(radix),
                  (0 ... 255).contains(minimumLength) else {
                return .error(.number)
            }
            var result = String(
                UInt64(number),
                radix: Int(radix),
                uppercase: true
            )
            if result.count < Int(minimumLength) {
                result = String(
                    repeating: "0",
                    count: Int(minimumLength) - result.count
                ) + result
            }
            return .text(result)
        }

        if name == "DECIMAL" {
            guard arguments.count == 2,
                  let textValue = evaluate(arguments[0]),
                  let radixValue = evaluate(arguments[1]) else {
                return arguments.count == 2 ? nil : .error(.value)
            }
            if let error = textValue.error ?? radixValue.error {
                return .error(error)
            }
            guard let radixNumber = radixValue.number,
                  radixNumber.isFinite else {
                return .error(.value)
            }
            let radix = radixNumber.rounded(.towardZero)
            guard (2 ... 36).contains(radix) else {
                return .error(.number)
            }
            let text = textValue.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).uppercased()
            guard !text.isEmpty, text.count <= 255 else {
                return .error(.number)
            }
            var result: UInt64 = 0
            for scalar in text.unicodeScalars {
                let digit: UInt64
                switch scalar.value {
                case 48 ... 57: digit = UInt64(scalar.value - 48)
                case 65 ... 90: digit = UInt64(scalar.value - 55)
                default: return .error(.number)
                }
                guard digit < UInt64(radix),
                      result < 9_007_199_254_740_992,
                      result <= (9_007_199_254_740_991 - digit)
                        / UInt64(radix) else {
                    return .error(.number)
                }
                result = result * UInt64(radix) + digit
            }
            return .number(Double(result))
        }

        let convertsFromDecimal = name.hasPrefix("DEC2")
        let convertsToDecimal = name.hasSuffix("2DEC")
        let allowedCounts = convertsToDecimal ? 1 ... 1 : 1 ... 2
        guard allowedCounts.contains(arguments.count),
              let sourceValue = evaluate(arguments[0]) else {
            return allowedCounts.contains(arguments.count)
                ? nil : .error(.value)
        }
        if sourceValue.error != nil { return sourceValue }

        let decimalValue: Int64
        if convertsFromDecimal {
            guard let number = sourceValue.number, number.isFinite,
                  number >= Double(Int64.min),
                  number <= Double(Int64.max) else {
                return .error(.value)
            }
            decimalValue = Int64(number.rounded(.towardZero))
        } else {
            let sourceRadix: Int
            let sourceBits: Int
            switch String(name.prefix(3)) {
            case "BIN": (sourceRadix, sourceBits) = (2, 10)
            case "OCT": (sourceRadix, sourceBits) = (8, 30)
            case "HEX": (sourceRadix, sourceBits) = (16, 40)
            default: return nil
            }
            guard let parsed = signedEngineeringInteger(
                sourceValue.text,
                radix: sourceRadix,
                bitCount: sourceBits
            ) else {
                return .error(.number)
            }
            decimalValue = parsed
        }

        if convertsToDecimal { return .number(Double(decimalValue)) }

        var places: Int?
        if arguments.count == 2, !isOmitted(arguments[1]) {
            guard let placesValue = evaluate(arguments[1]) else { return nil }
            if placesValue.error != nil { return placesValue }
            guard let number = placesValue.number, number.isFinite,
                  number >= Double(Int.min), number <= Double(Int.max) else {
                return .error(.value)
            }
            places = Int(number.rounded(.towardZero))
        }

        let target: (radix: Int, bitCount: Int)
        switch String(name.suffix(3)) {
        case "BIN": target = (2, 10)
        case "OCT": target = (8, 30)
        case "HEX": target = (16, 40)
        default: return nil
        }
        return formattedEngineeringInteger(
            decimalValue,
            radix: target.radix,
            bitCount: target.bitCount,
            places: places
        )
    }

    private func signedEngineeringInteger(
        _ source: String,
        radix: Int,
        bitCount: Int
    ) -> Int64? {
        let text = source.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).uppercased()
        guard !text.isEmpty, text.count <= 10,
              let unsigned = UInt64(text, radix: radix) else {
            return nil
        }
        let modulus = UInt64(1) << bitCount
        guard unsigned < modulus else { return nil }
        let signThreshold = UInt64(1) << (bitCount - 1)
        if text.count == 10, unsigned >= signThreshold {
            return Int64(unsigned) - Int64(modulus)
        }
        return Int64(unsigned)
    }

    private func formattedEngineeringInteger(
        _ value: Int64,
        radix: Int,
        bitCount: Int,
        places: Int?
    ) -> ExcelFormulaValue {
        let limit = Int64(1) << (bitCount - 1)
        guard value >= -limit, value < limit else {
            return .error(.number)
        }
        if value < 0 {
            let modulus = Int64(1) << bitCount
            return .text(String(
                UInt64(modulus + value),
                radix: radix,
                uppercase: true
            ))
        }

        var result = String(
            UInt64(value),
            radix: radix,
            uppercase: true
        )
        if let places {
            guard (1 ... 10).contains(places), places >= result.count else {
                return .error(.number)
            }
            result = String(
                repeating: "0",
                count: places - result.count
            ) + result
        }
        return .text(result)
    }

    private func comparisonEngineeringFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard (1 ... 2).contains(arguments.count),
              let firstValue = evaluate(arguments[0]) else {
            return (1 ... 2).contains(arguments.count)
                ? nil : .error(.value)
        }
        if firstValue.error != nil { return firstValue }
        let secondValue: ExcelFormulaValue
        if arguments.count == 2, !isOmitted(arguments[1]) {
            guard let evaluated = evaluate(arguments[1]) else { return nil }
            secondValue = evaluated
        } else {
            secondValue = .number(0)
        }
        if secondValue.error != nil { return secondValue }
        guard let first = firstValue.number,
              let second = secondValue.number,
              first.isFinite, second.isFinite else {
            return .error(.value)
        }
        if name == "DELTA" {
            return .number(first == second ? 1 : 0)
        }
        return .number(first >= second ? 1 : 0)
    }

    private func pairedSumFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard arguments.count == 2 else {
            return .error(.value)
        }
        let first = rangeMatrix(arguments[0])
            ?? evaluate(arguments[0]).map(scalarMatrix)
        let second = rangeMatrix(arguments[1])
            ?? evaluate(arguments[1]).map(scalarMatrix)
        guard let first, let second else { return nil }
        guard first.values.count == second.values.count else {
            return .error(.notAvailable)
        }
        var sum = 0.0
        for index in first.values.indices {
            let firstValue = first.values[index]
            let secondValue = second.values[index]
            if let error = firstValue.error ?? secondValue.error {
                return .error(error)
            }
            guard case .number(let x) = firstValue,
                  case .number(let y) = secondValue else {
                continue
            }
            switch name {
            case "SUMX2MY2": sum += x * x - y * y
            case "SUMX2PY2": sum += x * x + y * y
            case "SUMXMY2":
                let difference = x - y
                sum += difference * difference
            default: return nil
            }
            guard sum.isFinite else { return .error(.number) }
        }
        return .number(sum)
    }

    private func seriesSumFunction(
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard arguments.count == 4 else { return .error(.value) }
        var parameters = [Double]()
        for argument in arguments.prefix(3) {
            guard let value = evaluate(argument) else { return nil }
            if value.error != nil { return value }
            guard let number = value.number, number.isFinite else {
                return .error(.value)
            }
            parameters.append(number)
        }

        let coefficientValues: [ExcelFormulaValue]
        if let matrix = rangeMatrix(arguments[3]) {
            coefficientValues = matrix.values
        } else if let value = evaluate(arguments[3]) {
            coefficientValues = [value]
        } else {
            return nil
        }

        let x = parameters[0]
        let initialPower = parameters[1]
        let powerStep = parameters[2]
        var sum = 0.0
        for (index, coefficientValue) in coefficientValues.enumerated() {
            if let error = coefficientValue.error { return .error(error) }
            guard case .number(let coefficient) = coefficientValue else {
                continue
            }
            let power = initialPower + Double(index) * powerStep
            if x == 0, power < 0 { return .error(.divideByZero) }
            sum += coefficient * pow(x, power)
            guard sum.isFinite else { return .error(.number) }
        }
        return .number(sum)
    }

    private func rankFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard (2 ... 3).contains(arguments.count),
              let numberValue = evaluate(arguments[0]),
              let reference = rangeMatrix(arguments[1]) else {
            return .error(.value)
        }
        if numberValue.error != nil { return numberValue }
        guard let number = numberValue.number, number.isFinite else {
            return .error(.value)
        }

        var ascending = false
        if arguments.count == 3 {
            guard let orderValue = evaluate(arguments[2]) else { return nil }
            if orderValue.error != nil { return orderValue }
            guard let order = orderValue.number, order.isFinite else {
                return .error(.value)
            }
            ascending = order != 0
        }
        let values = reference.values.compactMap { value -> Double? in
            guard case .number(let number) = value else { return nil }
            return number
        }
        guard !values.isEmpty else { return .error(.notAvailable) }

        let valuesBefore = values.filter {
            ascending ? $0 < number : $0 > number
        }.count
        var rank = Double(valuesBefore + 1)
        if name == "RANK.AVG" {
            let equalCount = values.filter { $0 == number }.count
            if equalCount > 1 {
                rank += Double(equalCount - 1) / 2
            }
        }
        return .number(rank)
    }

    private func rankedStatisticFunction(
        _ name: String,
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard arguments.count == 2,
              let items = expandedValues(arguments[0]),
              let rankValue = evaluate(arguments[1]) else {
            return arguments.count == 2 ? nil : .error(.value)
        }
        if rankValue.error != nil { return rankValue }
        var numbers = [Double]()
        for item in items {
            if let error = item.value.error { return .error(error) }
            switch item.value {
            case .number(let number):
                numbers.append(number)
            case .boolean(let value):
                if !item.comesFromReference {
                    numbers.append(value ? 1 : 0)
                }
            case .text(let text):
                guard !item.comesFromReference else { continue }
                guard let number = Double(text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )) else {
                    return .error(.value)
                }
                numbers.append(number)
            case .blank:
                continue
            case .error:
                break
            }
        }
        guard let rankNumber = rankValue.number, rankNumber.isFinite else {
            return .error(.value)
        }
        let truncatedRank = rankNumber.rounded(.towardZero)
        guard truncatedRank >= 1,
              truncatedRank <= Double(numbers.count) else {
            return .error(.number)
        }
        let index = Int(truncatedRank) - 1
        let sorted = numbers.sorted {
            name == "LARGE" ? $0 > $1 : $0 < $1
        }
        return .number(sorted[index])
    }

    private func sumProductFunction(
        arguments: [ExcelFormulaExpression]
    ) -> ExcelFormulaValue? {
        guard (1 ... 255).contains(arguments.count) else {
            return .error(.value)
        }
        var matrices = [ExcelFormulaRangeMatrix]()
        for argument in arguments {
            if let matrix = rangeMatrix(argument) {
                matrices.append(matrix)
                continue
            }
            guard let value = evaluate(argument) else { return nil }
            matrices.append(ExcelFormulaRangeMatrix(
                rowCount: 1,
                columnCount: 1,
                values: [value]
            ))
        }
        guard let first = matrices.first,
              matrices.allSatisfy({
                  $0.rowCount == first.rowCount
                      && $0.columnCount == first.columnCount
              }) else {
            return .error(.value)
        }
        var sum = 0.0
        for index in first.values.indices {
            var product = 1.0
            for matrix in matrices {
                let value = matrix.values[index]
                if let error = value.error { return .error(error) }
                if case .number(let number) = value {
                    product *= number
                } else {
                    product = 0
                }
                guard product.isFinite else { return .error(.number) }
            }
            sum += product
            guard sum.isFinite else { return .error(.number) }
        }
        return .number(sum)
    }

    private func expandedValues(
        _ expression: ExcelFormulaExpression
    ) -> [ExcelFormulaArgumentValue]? {
        switch expression {
        case .range(let range):
            var result = [ExcelFormulaArgumentValue]()
            let cellCount = (range.end.row - range.start.row + 1)
                * (range.end.column - range.start.column + 1)
            guard cellCount <= 100_000 else { return nil }
            for row in range.start.row ... range.end.row {
                for column in range.start.column ... range.end.column {
                    guard let value = value(at: ExcelCellAddress(
                        row: row,
                        column: column
                    )) else {
                        return nil
                    }
                    result.append(ExcelFormulaArgumentValue(
                        value: value,
                        comesFromReference: true
                    ))
                }
            }
            return result
        case .spill(let anchor):
            if !dynamicArrayAttempts.contains(anchor),
               let expression = parsedExpression(at: anchor),
               isArrayExpression(expression) {
                prepareDynamicArray(at: anchor, expression: expression)
            }
            guard let range = spillRanges[anchor] else {
                return value(at: anchor).map {
                    [ExcelFormulaArgumentValue(
                        value: $0,
                        comesFromReference: true
                    )]
                }
            }
            var result = [ExcelFormulaArgumentValue]()
            let count = (range.end.row - range.start.row + 1)
                * (range.end.column - range.start.column + 1)
            guard count <= 100_000 else { return nil }
            for row in range.start.row ... range.end.row {
                for column in range.start.column ... range.end.column {
                    guard let value = value(at: ExcelCellAddress(
                        row: row,
                        column: column
                    )) else { return nil }
                    result.append(ExcelFormulaArgumentValue(
                        value: value,
                        comesFromReference: true
                    ))
                }
            }
            return result
        case .cell(let address):
            return value(at: address).map {
                [ExcelFormulaArgumentValue(
                    value: $0,
                    comesFromReference: true
                )]
            }
        default:
            if isArrayExpression(expression),
               let matrix = arrayMatrix(expression) {
                return matrix.values.map {
                    ExcelFormulaArgumentValue(
                        value: $0,
                        comesFromReference: false
                    )
                }
            }
            return evaluate(expression).map {
                [ExcelFormulaArgumentValue(
                    value: $0,
                    comesFromReference: false
                )]
            }
        }
    }
}
