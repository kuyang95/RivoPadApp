import Foundation

public nonisolated struct ExcelClipboardValue: Sendable {
    public let text: String
    public let styleIndex: Int?
    public var input: ExcelCellInput? = nil

    public init(text: String, styleIndex: Int? = nil, input: ExcelCellInput? = nil) {
        self.text = text
        self.styleIndex = styleIndex
        self.input = input
    }
}

public nonisolated struct ExcelRangeClipboard: Sendable {
    public let range: ExcelCellRange
    public let sheetIndex: Int
    public let values: [[ExcelClipboardValue]]
    public let isCut: Bool
    public let changeCount: Int

    public init(range: ExcelCellRange, sheetIndex: Int, values: [[ExcelClipboardValue]], isCut: Bool, changeCount: Int) {
        self.range = range
        self.sheetIndex = sheetIndex
        self.values = values
        self.isCut = isCut
        self.changeCount = changeCount
    }
}

public nonisolated enum ExcelTabularClipboard {
    public static func encode(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { text in
                text.contains(where: { "\t\n\r\"".contains($0) }) ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : text
            }.joined(separator: "\t")
        }.joined(separator: "\n")
    }
    public static func decode(_ text: String) -> [[String]] {
        let characters = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, index = 0
        while index < characters.count {
            let c = characters[index]
            if c == "\"" && (quoted || field.isEmpty) {
                if quoted && index + 1 < characters.count && characters[index + 1] == "\"" { field.append("\""); index += 1 }
                else { quoted.toggle() }
            } else if !quoted && (c == "\t" || c == "\n") {
                row.append(field); field = ""
                if c == "\n" { rows.append(row); row = [] }
            } else { field.append(c) }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty || rows.isEmpty { row.append(field); rows.append(row) }
        let width = rows.map(\.count).max() ?? 1
        return rows.map { $0 + Array(repeating: "", count: width - $0.count) }
    }
}

extension ExcelCellRange {
    public nonisolated var cellCount: Int { (end.row - start.row + 1) * (end.column - start.column + 1) }
    public nonisolated var addresses: [ExcelCellAddress] {
        (start.row ... end.row).flatMap { row in (start.column ... end.column).map { ExcelCellAddress(row: row, column: $0) } }
    }
}
