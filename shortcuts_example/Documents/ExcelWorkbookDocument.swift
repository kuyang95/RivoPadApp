import Foundation
import ZIPFoundation

nonisolated struct ExcelCellAddress:
    Hashable,
    Comparable,
    Sendable
{
    let row: Int
    let column: Int

    init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    init?(_ reference: String) {
        let cleaned = reference
            .replacingOccurrences(of: "$", with: "")
            .uppercased()
        var column = 0
        var rowText = ""
        for scalar in cleaned.unicodeScalars {
            if scalar.value >= 65,
               scalar.value <= 90,
               rowText.isEmpty {
                column = column * 26
                    + Int(scalar.value - 64)
            } else if scalar.value >= 48,
                      scalar.value <= 57 {
                rowText.unicodeScalars.append(scalar)
            } else {
                return nil
            }
        }
        guard column > 0,
              let row = Int(rowText),
              row > 0 else {
            return nil
        }
        self.init(row: row, column: column)
    }

    var reference: String {
        Self.columnName(column) + String(row)
    }

    static func < (
        lhs: ExcelCellAddress,
        rhs: ExcelCellAddress
    ) -> Bool {
        if lhs.row != rhs.row {
            return lhs.row < rhs.row
        }
        return lhs.column < rhs.column
    }

    static func columnName(_ column: Int) -> String {
        guard column > 0 else {
            return ""
        }
        var value = column
        var result = ""
        while value > 0 {
            value -= 1
            let scalar = UnicodeScalar(65 + value % 26)!
            result.insert(Character(scalar), at: result.startIndex)
            value /= 26
        }
        return result
    }
}

nonisolated struct ExcelCellRange:
    Hashable,
    Sendable
{
    let start: ExcelCellAddress
    let end: ExcelCellAddress

    init(start: ExcelCellAddress, end: ExcelCellAddress) {
        self.start = ExcelCellAddress(
            row: min(start.row, end.row),
            column: min(start.column, end.column)
        )
        self.end = ExcelCellAddress(
            row: max(start.row, end.row),
            column: max(start.column, end.column)
        )
    }

    init?(_ reference: String) {
        let parts = reference.split(
            separator: ":",
            maxSplits: 1
        )
        guard let first = parts.first,
              let start = ExcelCellAddress(String(first)) else {
            return nil
        }
        let end: ExcelCellAddress
        if parts.count == 2 {
            guard let parsed = ExcelCellAddress(String(parts[1])) else {
                return nil
            }
            end = parsed
        } else {
            end = start
        }
        self.init(start: start, end: end)
    }

    var reference: String {
        start == end
            ? start.reference
            : start.reference + ":" + end.reference
    }

    func contains(_ address: ExcelCellAddress) -> Bool {
        address.row >= start.row
            && address.row <= end.row
            && address.column >= start.column
            && address.column <= end.column
    }
}

nonisolated struct ExcelCellStyle: Sendable {
    var numberFormatID: Int
    var numberFormatCode: String?
    let isBold: Bool
    let fillARGB: String?
    let horizontalAlignment: String?
    var fontName: String? = nil
    var fontSize: Double? = nil
    var fontARGB: String? = nil
    var isItalic = false
    var isUnderlined = false
    var wrapText = false
    var verticalAlignment: String? = nil
    var borderEdges: [String: String] = [:]

    static let plain = ExcelCellStyle(
        numberFormatID: 0,
        numberFormatCode: nil,
        isBold: false,
        fillARGB: nil,
        horizontalAlignment: nil
    )
}

nonisolated struct ExcelCell: Identifiable, Sendable {
    var id: ExcelCellAddress { address }

    let address: ExcelCellAddress
    var rawValue: String
    var displayValue: String
    var formula: String?
    var styleIndex: Int?
    var cellType: String?
    var spillAnchor: ExcelCellAddress? = nil
    var spillRange: ExcelCellRange? = nil

    var editText: String {
        if let formula,
           !formula.isEmpty {
            return "=" + formula
        }
        return rawValue
    }
}

nonisolated struct ExcelTable: Identifiable, Sendable {
    let id: String
    let name: String
    var range: ExcelCellRange
    let partPath: String
    var columnNames: [String] = []
    var headerRowCount: Int = 1
    var totalsRowCount: Int = 0
}

nonisolated struct ExcelDefinedName: Identifiable, Hashable, Sendable {
    var id: String {
        name.lowercased() + "#" + String(localSheetIndex ?? -1)
    }

    let name: String
    let formula: String
    let localSheetIndex: Int?
    let isHidden: Bool
}

nonisolated enum ExcelPageOrientation: String, CaseIterable, Sendable {
    case portrait
    case landscape
}

nonisolated struct ExcelPageMargins: Equatable, Sendable {
    var left: Double = 0.7
    var right: Double = 0.7
    var top: Double = 0.75
    var bottom: Double = 0.75
    var header: Double = 0.3
    var footer: Double = 0.3
}

nonisolated struct ExcelPrintSettings: Equatable, Sendable {
    var orientation: ExcelPageOrientation?
    var paperSize: Int?
    var scale: Int?
    var fitToWidth: Int?
    var fitToHeight: Int?
    var margins: ExcelPageMargins?
    var printAreaFormula: String?
    var printTitlesFormula: String?
}

nonisolated struct ExcelSheetProtection: Equatable, Sendable {
    var isEnabled = false
    var protectsObjects = false
    var protectsScenarios = false
    var passwordHash: String?
    var algorithmName: String?
    var hashValue: String?
    var saltValue: String?
    var spinCount: Int?
}

nonisolated struct ExcelWorkbookProtection: Equatable, Sendable {
    var lockStructure = false
    var lockWindows = false
    var lockRevision = false
    var workbookPasswordHash: String?
    var revisionsPasswordHash: String?
}

nonisolated struct ExcelExternalLink: Identifiable, Equatable, Sendable {
    let id: String
    let partPath: String
    let sourceTarget: String?
}

nonisolated struct ExcelWorksheet: Identifiable, Sendable {
    let id: String
    let name: String
    let partPath: String
    var cells: [ExcelCellAddress: ExcelCell]
    let mergedRanges: [ExcelCellRange]
    var tables: [ExcelTable]
    var dataValidations: [ExcelDataValidationRule] = []
    var conditionalFormatting: [ExcelConditionalFormattingBlock] = []
    var annotations: ExcelWorksheetAnnotations = .empty
    var drawingObjects: ExcelWorksheetDrawingObjects = .empty
    var pivotTables: [ExcelPivotTable] = []
    var printSettings: ExcelPrintSettings = .init()
    var protection: ExcelSheetProtection = .init()
    let columnWidths: [Int: Double]
    let rowHeights: [Int: Double]
    var maximumRow: Int
    var maximumColumn: Int
    let didTruncate: Bool
    var isWindowed: Bool = false
    var hiddenRows: Set<Int> = []
    var filterRange: ExcelCellRange? = nil
    var frozenPanes: ExcelFrozenPanes = .none

    func cell(at address: ExcelCellAddress) -> ExcelCell? {
        cells[address]
    }

    func mergedRange(
        containing address: ExcelCellAddress
    ) -> ExcelCellRange? {
        mergedRanges.first { $0.contains(address) }
    }

    func canonicalAddress(
        for address: ExcelCellAddress
    ) -> ExcelCellAddress {
        mergedRange(containing: address)?.start
            ?? address
    }

    func table(
        containing address: ExcelCellAddress
    ) -> ExcelTable? {
        tables.first { $0.range.contains(address) }
    }
}

nonisolated struct ExcelWorkbook: Sendable {
    var sheets: [ExcelWorksheet]
    var styles: [ExcelCellStyle]
    var differentialStyles: [ExcelDifferentialStyle] = []
    var definedNames: [ExcelDefinedName] = []
    var protection: ExcelWorkbookProtection = .init()
    var externalLinks: [ExcelExternalLink] = []
    var supportsDynamicArrays: Bool = true
    let uses1904DateSystem: Bool

    func style(at index: Int?) -> ExcelCellStyle {
        guard let index,
              styles.indices.contains(index) else {
            return .plain
        }
        return styles[index]
    }
}

nonisolated struct ExcelWorksheetPreflight: Identifiable, Sendable {
    var id: String { partPath }

    let name: String
    let partPath: String
    let maximumRow: Int
    let maximumColumn: Int
    let cellCount: Int
    let populatedRows: [Int]
    let tableHeaderRows: [Int]

    var requiresLargeMode: Bool {
        maximumRow > ExcelWorkbookDocument.maximumRowsPerSheet
            || maximumColumn > ExcelWorkbookDocument.maximumColumnsPerSheet
            || cellCount > ExcelWorkbookDocument.maximumCellsPerSheet
    }

    func windowRows(
        startingAt startIndex: Int,
        pageSize: Int = ExcelWorkbookDocument.largePageSize
    ) -> Set<Int> {
        let safeStart = min(max(startIndex, 0), populatedRows.count)
        let end = min(safeStart + pageSize, populatedRows.count)
        var rows = Set(populatedRows.prefix(
            ExcelWorkbookDocument.largeContextRowCount
        ))
        rows.formUnion(tableHeaderRows)
        if safeStart < end {
            rows.formUnion(populatedRows[safeStart..<end])
        }
        return rows
    }
}

nonisolated struct ExcelWorkbookPreflight: Sendable {
    let sheets: [ExcelWorksheetPreflight]

    var requiresLargeMode: Bool {
        sheets.contains(where: \.requiresLargeMode)
    }

    func sheet(partPath: String) -> ExcelWorksheetPreflight? {
        sheets.first(where: { $0.partPath == partPath })
    }
}

nonisolated struct ExcelLargeWorkbookCache: Sendable {
    let directoryURL: URL
    let sheets: [String: ExcelLargeSheetCache]

    func sheet(partPath: String) -> ExcelLargeSheetCache? {
        sheets[partPath]
    }
}

nonisolated struct ExcelLargeSheetCache: Sendable {
    let fileURL: URL
    let rowRanges: [Int: Range<UInt64>]

    func cells(in rows: Set<Int>) throws -> [ExcelCellAddress: ExcelCell] {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var cells = [ExcelCellAddress: ExcelCell]()
        let decoder = JSONDecoder()
        for row in rows.sorted() {
            guard let range = rowRanges[row] else {
                continue
            }
            try handle.seek(toOffset: range.lowerBound)
            var offset = range.lowerBound
            while offset < range.upperBound {
                guard let lengthData = try handle.read(upToCount: 4),
                      lengthData.count == 4 else {
                    throw ExcelWorkbookDocumentError.invalidWorkbook
                }
                let length = lengthData.reduce(UInt32(0)) {
                    ($0 << 8) | UInt32($1)
                }
                guard length > 0,
                      let payload = try handle.read(
                          upToCount: Int(length)
                      ),
                      payload.count == Int(length) else {
                    throw ExcelWorkbookDocumentError.invalidWorkbook
                }
                let record = try decoder.decode(
                    ExcelLargeCellRecord.self,
                    from: payload
                )
                let cell = record.cell
                cells[cell.address] = cell
                offset += 4 + UInt64(length)
            }
        }
        return cells
    }

    func searchRows(
        query: String,
        maximumResults: Int = 500
    ) throws -> [Int] {
        guard maximumResults > 0 else {
            return []
        }
        let normalizedQuery = ExcelSearchNormalizer.normalized(query)
        let compactQuery = ExcelSearchNormalizer.compact(query)
        guard !normalizedQuery.isEmpty else {
            return []
        }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let decoder = JSONDecoder()
        var matches = [Int]()
        for row in rowRanges.keys.sorted() {
            guard let range = rowRanges[row] else {
                continue
            }
            try handle.seek(toOffset: range.lowerBound)
            var offset = range.lowerBound
            var didMatch = false
            while offset < range.upperBound {
                guard let lengthData = try handle.read(upToCount: 4),
                      lengthData.count == 4 else {
                    throw ExcelWorkbookDocumentError.invalidWorkbook
                }
                let length = lengthData.reduce(UInt32(0)) {
                    ($0 << 8) | UInt32($1)
                }
                guard length > 0,
                      let payload = try handle.read(
                          upToCount: Int(length)
                      ),
                      payload.count == Int(length) else {
                    throw ExcelWorkbookDocumentError.invalidWorkbook
                }
                if !didMatch {
                    let record = try decoder.decode(
                        ExcelLargeCellRecord.self,
                        from: payload
                    )
                    didMatch = ExcelSearchNormalizer.matches(
                        record.displayValue,
                        normalizedQuery: normalizedQuery,
                        compactQuery: compactQuery
                    ) || ExcelSearchNormalizer.matches(
                        record.formula ?? "",
                        normalizedQuery: normalizedQuery,
                        compactQuery: compactQuery
                    )
                }
                offset += 4 + UInt64(length)
            }
            if didMatch {
                matches.append(row)
                if matches.count == maximumResults {
                    break
                }
            }
        }
        return matches
    }
}

private nonisolated struct ExcelLargeCellRecord: Codable {
    let row: Int
    let column: Int
    let rawValue: String
    let displayValue: String
    let formula: String?
    let styleIndex: Int?
    let cellType: String?

    init(_ cell: ExcelCell) {
        row = cell.address.row
        column = cell.address.column
        rawValue = cell.rawValue
        displayValue = cell.displayValue
        formula = cell.formula
        styleIndex = cell.styleIndex
        cellType = cell.cellType
    }

    var cell: ExcelCell {
        ExcelCell(
            address: ExcelCellAddress(row: row, column: column),
            rawValue: rawValue,
            displayValue: displayValue,
            formula: formula,
            styleIndex: styleIndex,
            cellType: cellType
        )
    }
}

private nonisolated enum ExcelSearchNormalizer {
    static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func compact(_ value: String) -> String {
        normalized(value).unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        .map(String.init)
        .joined()
    }

    static func matches(
        _ value: String,
        normalizedQuery: String,
        compactQuery: String
    ) -> Bool {
        let normalizedValue = normalized(value)
        if normalizedValue.contains(normalizedQuery) {
            return true
        }
        return !compactQuery.isEmpty
            && compact(value).contains(compactQuery)
    }
}

nonisolated enum ExcelCellInput: Hashable, Sendable {
    case blank
    case text(String)
    case number(String)
    case boolean(Bool)
    case error(String)
    case formula(String)

    init(userText: String) {
        let trimmed = userText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if trimmed.isEmpty {
            self = .blank
        } else if trimmed.hasPrefix("=") {
            self = .formula(String(trimmed.dropFirst()))
        } else if trimmed.caseInsensitiveCompare("TRUE") == .orderedSame {
            self = .boolean(true)
        } else if trimmed.caseInsensitiveCompare("FALSE") == .orderedSame {
            self = .boolean(false)
        } else if Self.isUnambiguousNumber(trimmed) {
            self = .number(trimmed)
        } else {
            self = .text(userText)
        }
    }

    private static func isUnambiguousNumber(_ value: String) -> Bool {
        let unsigned = value.hasPrefix("-")
            || value.hasPrefix("+")
            ? String(value.dropFirst())
            : value
        if unsigned.count > 1,
           unsigned.hasPrefix("0"),
           !unsigned.hasPrefix("0.") {
            return false
        }
        return Double(value) != nil
    }
}

/// Recognizes unambiguous typed dates (`2024-03-05`, `2024.3.5`, `2024/03/05`)
/// so they are stored as Excel date serials instead of text.
nonisolated enum ExcelDateInput {
    static func serial(
        fromUserText text: String,
        uses1904DateSystem: Bool
    ) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(\d{4})[-./](\d{1,2})[-./](\d{1,2})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: trimmed,
                  range: NSRange(trimmed.startIndex..., in: trimmed)
              ),
              match.numberOfRanges == 4 else {
            return nil
        }
        func component(_ index: Int) -> Int? {
            Range(match.range(at: index), in: trimmed)
                .flatMap { Int(trimmed[$0]) }
        }
        guard let year = component(1),
              let month = component(2),
              let day = component(3),
              (1900...9999).contains(year),
              (1...12).contains(month),
              (1...31).contains(day) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day,
              calendar.component(.month, from: date) == month else {
            return nil
        }
        var baseComponents = DateComponents()
        baseComponents.year = uses1904DateSystem ? 1904 : 1899
        baseComponents.month = uses1904DateSystem ? 1 : 12
        baseComponents.day = uses1904DateSystem ? 1 : 30
        guard let base = calendar.date(from: baseComponents) else {
            return nil
        }
        let days = (date.timeIntervalSince(base) / 86_400).rounded()
        guard days >= (uses1904DateSystem ? 0 : 1) else {
            return nil
        }
        return String(Int(days))
    }
}

nonisolated struct ExcelCellEdit: Hashable, Sendable {
    let input: ExcelCellInput
    let styleIndex: Int?
    let preservesExistingContent: Bool
    let cachedValue: String?
    let cachedType: String?
    let formulaSpillRange: ExcelCellRange?

    init(
        input: ExcelCellInput,
        styleIndex: Int?,
        preservesExistingContent: Bool = false,
        cachedValue: String? = nil,
        cachedType: String? = nil,
        formulaSpillRange: ExcelCellRange? = nil
    ) {
        self.input = input
        self.styleIndex = styleIndex
        self.preservesExistingContent = preservesExistingContent
        self.cachedValue = cachedValue
        self.cachedType = cachedType
        self.formulaSpillRange = formulaSpillRange
    }
}

nonisolated struct ExcelWorksheetEdits: Sendable {
    let partPath: String
    let cells: [ExcelCellAddress: ExcelCellEdit]
}

nonisolated struct ExcelWorksheetValidationEdits: Sendable {
    let partPath: String
    let rules: [ExcelDataValidationRule]
}

nonisolated struct ExcelWorksheetConditionalFormattingEdits: Sendable {
    let partPath: String
    let blocks: [ExcelConditionalFormattingBlock]
}

nonisolated enum ExcelFormulaTranslator {
    static func shiftingRelativeRows(
        in formula: String,
        by offset: Int
    ) -> String {
        guard offset != 0,
              let regex = try? NSRegularExpression(
                  pattern: #"(?<![A-Za-z0-9_])([$]?[A-Za-z]{1,3})([$]?)([0-9]+)"#
              ) else {
            return formula
        }
        var result = formula
        let matches = regex.matches(
            in: formula,
            range: NSRange(formula.startIndex..., in: formula)
        )
        for match in matches.reversed() {
            guard match.numberOfRanges == 4,
                  let fullRange = Range(match.range(at: 0), in: formula),
                  let columnRange = Range(match.range(at: 1), in: formula),
                  let absoluteRowRange = Range(match.range(at: 2), in: formula),
                  let rowRange = Range(match.range(at: 3), in: formula),
                  let row = Int(formula[rowRange]) else {
                continue
            }
            let absoluteRowMarker = String(formula[absoluteRowRange])
            let shiftedRow = absoluteRowMarker == "$"
                ? row
                : max(row + offset, 1)
            let replacement = String(formula[columnRange])
                + absoluteRowMarker
                + String(shiftedRow)
            guard let resultRange = Range(
                NSRange(fullRange, in: formula),
                in: result
            ) else {
                continue
            }
            result.replaceSubrange(resultRange, with: replacement)
        }
        return result
    }
}

nonisolated enum ExcelWorkbookDocumentError: LocalizedError {
    case invalidWorkbook
    case unsupportedWorkbook
    case workbookLimitExceeded
    case cannotSave

    var errorDescription: String? {
        switch self {
        case .invalidWorkbook:
            return AppLocalization.string(
                "손상되었거나 올바르지 않은 XLSX 문서입니다."
            )
        case .unsupportedWorkbook:
            return AppLocalization.string(
                "암호화되었거나 지원하지 않는 XLSX 문서입니다."
            )
        case .workbookLimitExceeded:
            return AppLocalization.string(
                "XLSX 문서가 안전하게 열 수 있는 크기를 초과했습니다."
            )
        case .cannotSave:
            return AppLocalization.string(
                "XLSX 문서를 저장할 수 없습니다."
            )
        }
    }
}

nonisolated enum ExcelWorkbookDocument {
    static let maximumWorkbookBytes = 40 * 1_024 * 1_024
    static let maximumArchiveEntries = 4_096
    static let maximumExpandedBytes = 128 * 1_024 * 1_024
    static let maximumEntryBytes = 40 * 1_024 * 1_024
    static let maximumSheets = 64
    static let maximumRowsPerSheet = 2_000
    static let maximumColumnsPerSheet = 200
    static let maximumCellsPerSheet = 100_000
    static let maximumExcelRows = 1_048_576
    static let maximumExcelColumns = 16_384
    static let maximumLargeSharedStrings = 500_000
    static let largePageSize = 200
    static let largeContextRowCount = 40

    static func blankWorkbookData(
        sheetName rawSheetName: String = "시트1"
    ) throws -> Data {
        let trimmedName = rawSheetName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let sheetName = escapeXML(
            String((trimmedName.isEmpty ? "시트1" : trimmedName).prefix(31))
        )
        let entries: [String: Data] = [
            "[Content_Types].xml": Data(
                """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
                """.utf8
            ),
            "_rels/.rels": Data(
                """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
                """.utf8
            ),
            "xl/workbook.xml": Data(
                """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><bookViews><workbookView/></bookViews><sheets><sheet name="\(sheetName)" sheetId="1" r:id="rId1"/></sheets><calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>
                """.utf8
            ),
            "xl/_rels/workbook.xml.rels": Data(
                """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
                """.utf8
            ),
            "xl/worksheets/sheet1.xml": Data(
                """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="A1"/><sheetViews><sheetView workbookViewId="0"><selection activeCell="A1" sqref="A1"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="15"/><sheetData/></worksheet>
                """.utf8
            ),
            "xl/styles.xml": Data(
                """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><sz val="11"/><color theme="1"/><name val="Aptos Narrow"/><family val="2"/><scheme val="minor"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles><dxfs count="0"/><tableStyles count="0" defaultTableStyle="TableStyleMedium2" defaultPivotStyle="PivotStyleLight16"/></styleSheet>
                """.utf8
            ),
        ]
        let archive = try Archive(accessMode: .create)
        for (path, payload) in entries.sorted(by: { $0.key < $1.key }) {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(payload.count),
                compressionMethod: .deflate
            ) { position, size in
                let lower = Int(position)
                let upper = min(payload.count, lower + size)
                return lower < upper
                    ? payload.subdata(in: lower..<upper)
                    : Data()
            }
        }
        guard let data = archive.data else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        return data
    }

    static func preflight(
        from data: Data
    ) throws -> ExcelWorkbookPreflight {
        try validateContainer(data)
        let reader = try ExcelArchiveReader(data: data)
        let workbookInfo = try ExcelWorkbookParser.parse(
            reader.data(at: "xl/workbook.xml")
        )
        guard !workbookInfo.sheets.isEmpty,
              workbookInfo.sheets.count <= maximumSheets else {
            throw ExcelWorkbookDocumentError.invalidWorkbook
        }
        let relationships = try ExcelRelationshipsParser.parse(
            reader.data(at: "xl/_rels/workbook.xml.rels")
        )
        var sheets = [ExcelWorksheetPreflight]()
        for sheetInfo in workbookInfo.sheets {
            guard let relationship = relationships[
                sheetInfo.relationshipID
            ],
            relationship.type.hasSuffix("/worksheet"),
            let sheetPath = normalizedPartPath(
                relationship.target,
                relativeTo: "xl/workbook.xml"
            ),
            reader.contains(sheetPath) else {
                continue
            }
            let summary = try ExcelWorksheetPreflightParser.parse(
                reader.data(at: sheetPath)
            )
            let partRelationships = try relationshipsForPart(
                sheetPath,
                reader: reader
            )
            var tableHeaderRows = [Int]()
            for relationshipID in summary.tableRelationshipIDs {
                guard let tableRelationship = partRelationships[
                    relationshipID
                ],
                tableRelationship.type.hasSuffix("/table"),
                let tablePath = normalizedPartPath(
                    tableRelationship.target,
                    relativeTo: sheetPath
                ),
                reader.contains(tablePath),
                let table = try ExcelTableParser.parse(
                    reader.data(at: tablePath),
                    partPath: tablePath
                ) else {
                    continue
                }
                tableHeaderRows.append(table.range.start.row)
            }
            sheets.append(
                ExcelWorksheetPreflight(
                    name: sheetInfo.name,
                    partPath: sheetPath,
                    maximumRow: summary.maximumRow,
                    maximumColumn: summary.maximumColumn,
                    cellCount: summary.cellCount,
                    populatedRows: summary.populatedRows,
                    tableHeaderRows: Array(Set(tableHeaderRows)).sorted()
                )
            )
        }
        guard !sheets.isEmpty else {
            throw ExcelWorkbookDocumentError.invalidWorkbook
        }
        return ExcelWorkbookPreflight(sheets: sheets)
    }

    static func load(from data: Data) throws -> ExcelWorkbook {
        try validateContainer(data)

        let reader = try ExcelArchiveReader(data: data)
        let workbookData = try reader.data(at: "xl/workbook.xml")
        let workbookInfo = try ExcelWorkbookParser.parse(workbookData)
        guard !workbookInfo.sheets.isEmpty,
              workbookInfo.sheets.count <= maximumSheets else {
            throw ExcelWorkbookDocumentError.invalidWorkbook
        }
        let relationships = try ExcelRelationshipsParser.parse(
            reader.data(at: "xl/_rels/workbook.xml.rels")
        )
        let sharedStrings = reader.contains("xl/sharedStrings.xml")
            ? try ExcelSharedStringsParser.parse(
                reader.data(at: "xl/sharedStrings.xml"),
                maximumStrings: maximumCellsPerSheet
            )
            : []
        let stylesData = reader.contains("xl/styles.xml")
            ? try reader.data(at: "xl/styles.xml")
            : nil
        let styles = try stylesData.map(ExcelStylesParser.parse) ?? [.plain]
        let differentialStyles = try stylesData.map(
            ExcelDifferentialStylesParser.parse
        ) ?? []

        var worksheets: [ExcelWorksheet] = []
        for (sheetIndex, sheetInfo) in workbookInfo.sheets.enumerated() {
            guard let relationship = relationships[
                sheetInfo.relationshipID
            ],
            relationship.type.hasSuffix("/worksheet"),
            let sheetPath = normalizedPartPath(
                relationship.target,
                relativeTo: "xl/workbook.xml"
            ),
            reader.contains(sheetPath) else {
                continue
            }

            let sheetData = try reader.data(at: sheetPath)
            let parsed = try ExcelWorksheetParser.parse(
                sheetData,
                sharedStrings: sharedStrings,
                styles: styles,
                uses1904DateSystem: workbookInfo.uses1904DateSystem
            )
            let dataValidations = try ExcelDataValidationXMLParser.parse(
                sheetData
            )
            guard let sheetXML = String(data: sheetData, encoding: .utf8) else {
                throw ExcelWorkbookDocumentError.invalidWorkbook
            }
            let conditionalFormatting = try
                ExcelConditionalFormattingXMLParser.parse(sheetXML)
            let tableRelationships = try relationshipsForPart(
                sheetPath,
                reader: reader
            )
            var tables: [ExcelTable] = []
            for relationshipID in parsed.tableRelationshipIDs {
                guard let relationship = tableRelationships[relationshipID],
                      relationship.type.hasSuffix("/table"),
                      let path = normalizedPartPath(
                          relationship.target,
                          relativeTo: sheetPath
                      ),
                      reader.contains(path),
                      let table = try ExcelTableParser.parse(
                          reader.data(at: path),
                          partPath: path
                      ) else {
                    continue
                }
                tables.append(table)
            }
            let annotations = try ExcelWorksheetAnnotationsLoader.load(
                sheetData: sheetData,
                sheetPartPath: sheetPath,
                relationships: tableRelationships,
                reader: reader
            )
            let drawingObjects = try ExcelWorksheetDrawingObjectsLoader.load(
                sheetPartPath: sheetPath,
                relationships: tableRelationships,
                reader: reader
            )
            let pivotTables = try ExcelWorksheetPivotTablesLoader.load(
                sheetPartPath: sheetPath,
                relationships: tableRelationships,
                workbookPivotCacheRelationshipIDs:
                    workbookInfo.pivotCacheRelationshipIDs,
                workbookRelationships: relationships,
                reader: reader
            )
            let printSettings = printSettings(
                parsed.printSettings,
                sheetIndex: sheetIndex,
                definedNames: workbookInfo.definedNames
            )

            worksheets.append(
                ExcelWorksheet(
                    id: sheetPath,
                    name: sheetInfo.name,
                    partPath: sheetPath,
                    cells: parsed.cells,
                    mergedRanges: parsed.mergedRanges,
                    tables: tables,
                    dataValidations: dataValidations,
                    conditionalFormatting: conditionalFormatting,
                    annotations: annotations,
                    drawingObjects: drawingObjects,
                    pivotTables: pivotTables,
                    printSettings: printSettings,
                    protection: parsed.protection,
                    columnWidths: parsed.columnWidths,
                    rowHeights: parsed.rowHeights,
                    maximumRow: parsed.maximumRow,
                    maximumColumn: parsed.maximumColumn,
                    didTruncate: parsed.didTruncate,
                    frozenPanes: parsed.frozenPanes
                )
            )
        }
        guard !worksheets.isEmpty else {
            throw ExcelWorkbookDocumentError.invalidWorkbook
        }
        for index in worksheets.indices {
            let xml = try ExcelEditingXML.parse(reader.data(at: worksheets[index].partPath))
            worksheets[index].hiddenRows = Set((xml.child("sheetData")?.elements("row") ?? []).compactMap { $0.attributes["hidden"] == "1" ? Int($0.attributes["r"] ?? "") : nil })
            worksheets[index].filterRange = xml.child("autoFilter")?.attributes["ref"].flatMap(ExcelCellRange.init)
        }
        return ExcelWorkbook(
            sheets: worksheets,
            styles: styles.isEmpty ? [.plain] : styles,
            differentialStyles: differentialStyles,
            definedNames: workbookInfo.definedNames,
            protection: workbookInfo.protection,
            externalLinks: try externalLinks(
                workbookInfo: workbookInfo,
                workbookRelationships: relationships,
                reader: reader
            ),
            supportsDynamicArrays:
                reader.contains("xl/metadata.xml")
                    || (workbookInfo.calculationID ?? 0) >= 191_029,
            uses1904DateSystem: workbookInfo.uses1904DateSystem
        )
    }

    static func loadWindowed(
        from data: Data,
        preflight: ExcelWorkbookPreflight,
        startIndices: [String: Int] = [:]
    ) throws -> ExcelWorkbook {
        try validateContainer(data)
        let reader = try ExcelArchiveReader(data: data)
        let workbookInfo = try ExcelWorkbookParser.parse(
            reader.data(at: "xl/workbook.xml")
        )
        let workbookRelationships = try ExcelRelationshipsParser.parse(
            reader.data(at: "xl/_rels/workbook.xml.rels")
        )
        let sharedStrings = reader.contains("xl/sharedStrings.xml")
            ? try ExcelSharedStringsParser.parse(
                reader.data(at: "xl/sharedStrings.xml"),
                maximumStrings: maximumLargeSharedStrings
            )
            : []
        let stylesData = reader.contains("xl/styles.xml")
            ? try reader.data(at: "xl/styles.xml")
            : nil
        let styles = try stylesData.map(ExcelStylesParser.parse) ?? [.plain]
        let differentialStyles = try stylesData.map(
            ExcelDifferentialStylesParser.parse
        ) ?? []
        var worksheets = [ExcelWorksheet]()
        for (sheetIndex, summary) in preflight.sheets.enumerated() {
            let rows = summary.windowRows(
                startingAt: startIndices[summary.partPath] ?? 0
            )
            worksheets.append(
                try loadSheetWindow(
                    summary,
                    includedRows: rows,
                    reader: reader,
                    sharedStrings: sharedStrings,
                    styles: styles,
                    uses1904DateSystem: workbookInfo.uses1904DateSystem,
                    workbookPivotCacheRelationshipIDs:
                        workbookInfo.pivotCacheRelationshipIDs,
                    workbookRelationships: workbookRelationships,
                    printSettings: printSettings(
                        .init(),
                        sheetIndex: sheetIndex,
                        definedNames: workbookInfo.definedNames
                    )
                )
            )
        }
        return ExcelWorkbook(
            sheets: worksheets,
            styles: styles.isEmpty ? [.plain] : styles,
            differentialStyles: differentialStyles,
            definedNames: workbookInfo.definedNames,
            protection: workbookInfo.protection,
            externalLinks: try externalLinks(
                workbookInfo: workbookInfo,
                workbookRelationships: workbookRelationships,
                reader: reader
            ),
            supportsDynamicArrays:
                reader.contains("xl/metadata.xml")
                    || (workbookInfo.calculationID ?? 0) >= 191_029,
            uses1904DateSystem: workbookInfo.uses1904DateSystem
        )
    }

    static func buildLargeCache(
        from data: Data,
        preflight: ExcelWorkbookPreflight,
        directoryURL: URL
    ) throws -> ExcelLargeWorkbookCache {
        try validateContainer(data)
        let reader = try ExcelArchiveReader(data: data)
        let workbookInfo = try ExcelWorkbookParser.parse(
            reader.data(at: "xl/workbook.xml")
        )
        let sharedStrings = reader.contains("xl/sharedStrings.xml")
            ? try ExcelSharedStringsParser.parse(
                reader.data(at: "xl/sharedStrings.xml"),
                maximumStrings: maximumLargeSharedStrings
            )
            : []
        let styles = reader.contains("xl/styles.xml")
            ? try ExcelStylesParser.parse(
                reader.data(at: "xl/styles.xml")
            )
            : [.plain]
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        var sheetCaches = [String: ExcelLargeSheetCache]()
        let encoder = JSONEncoder()
        for (index, summary) in preflight.sheets.enumerated() {
            let fileURL = directoryURL.appendingPathComponent(
                "sheet-\(index).rows",
                isDirectory: false
            )
            guard FileManager.default.createFile(
                atPath: fileURL.path,
                contents: nil
            ) else {
                throw ExcelWorkbookDocumentError.cannotSave
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            var offset: UInt64 = 0
            var currentRow: Int?
            var currentRowStart: UInt64 = 0
            var rowRanges = [Int: Range<UInt64>]()
            do {
                try ExcelWorksheetParser.visitCells(
                    reader.data(at: summary.partPath),
                    sharedStrings: sharedStrings,
                    styles: styles,
                    uses1904DateSystem:
                        workbookInfo.uses1904DateSystem
                ) { cell in
                    if let currentRow,
                       currentRow != cell.address.row {
                        rowRanges[currentRow] = currentRowStart..<offset
                        currentRowStart = offset
                    } else if currentRow == nil {
                        currentRowStart = offset
                    }
                    currentRow = cell.address.row
                    let payload = try encoder.encode(
                        ExcelLargeCellRecord(cell)
                    )
                    guard payload.count <= Int(UInt32.max) else {
                        throw ExcelWorkbookDocumentError.workbookLimitExceeded
                    }
                    var length = UInt32(payload.count).bigEndian
                    let lengthData = withUnsafeBytes(of: &length) {
                        Data($0)
                    }
                    try handle.write(contentsOf: lengthData)
                    try handle.write(contentsOf: payload)
                    offset += 4 + UInt64(payload.count)
                }
                if let currentRow {
                    rowRanges[currentRow] = currentRowStart..<offset
                }
                try handle.close()
            } catch {
                try? handle.close()
                try? FileManager.default.removeItem(at: directoryURL)
                throw error
            }
            sheetCaches[summary.partPath] = ExcelLargeSheetCache(
                fileURL: fileURL,
                rowRanges: rowRanges
            )
        }
        return ExcelLargeWorkbookCache(
            directoryURL: directoryURL,
            sheets: sheetCaches
        )
    }

    static func loadSheetWindow(
        from data: Data,
        summary: ExcelWorksheetPreflight,
        includedRows: Set<Int>
    ) throws -> ExcelWorksheet {
        try validateContainer(data)
        let reader = try ExcelArchiveReader(data: data)
        let workbookInfo = try ExcelWorkbookParser.parse(
            reader.data(at: "xl/workbook.xml")
        )
        let workbookRelationships = try ExcelRelationshipsParser.parse(
            reader.data(at: "xl/_rels/workbook.xml.rels")
        )
        let sharedStrings = reader.contains("xl/sharedStrings.xml")
            ? try ExcelSharedStringsParser.parse(
                reader.data(at: "xl/sharedStrings.xml"),
                maximumStrings: maximumLargeSharedStrings
            )
            : []
        let styles = reader.contains("xl/styles.xml")
            ? try ExcelStylesParser.parse(
                reader.data(at: "xl/styles.xml")
            )
            : [.plain]
        return try loadSheetWindow(
            summary,
            includedRows: includedRows,
            reader: reader,
            sharedStrings: sharedStrings,
            styles: styles,
            uses1904DateSystem: workbookInfo.uses1904DateSystem,
            workbookPivotCacheRelationshipIDs:
                workbookInfo.pivotCacheRelationshipIDs,
            workbookRelationships: workbookRelationships,
            printSettings: printSettings(
                .init(),
                sheetIndex: workbookInfo.sheets.firstIndex(where: {
                    $0.name == summary.name
                }) ?? 0,
                definedNames: workbookInfo.definedNames
            )
        )
    }

    static func searchRows(
        in data: Data,
        sheetPartPath: String,
        query: String,
        maximumResults: Int = 500
    ) throws -> [Int] {
        try validateContainer(data)
        guard maximumResults > 0 else {
            return []
        }
        let reader = try ExcelArchiveReader(data: data)
        guard reader.contains(sheetPartPath) else {
            throw ExcelWorkbookDocumentError.invalidWorkbook
        }
        let sharedStrings = reader.contains("xl/sharedStrings.xml")
            ? try ExcelSharedStringsParser.parse(
                reader.data(at: "xl/sharedStrings.xml"),
                maximumStrings: maximumLargeSharedStrings
            )
            : []
        return try ExcelWorksheetSearchParser.search(
            reader.data(at: sheetPartPath),
            sharedStrings: sharedStrings,
            query: query,
            maximumResults: maximumResults
        )
    }

    private static func loadSheetWindow(
        _ summary: ExcelWorksheetPreflight,
        includedRows: Set<Int>,
        reader: ExcelArchiveReader,
        sharedStrings: [String],
        styles: [ExcelCellStyle],
        uses1904DateSystem: Bool,
        workbookPivotCacheRelationshipIDs: [Int: String],
        workbookRelationships: [String: ExcelRelationship],
        printSettings namedPrintSettings: ExcelPrintSettings
    ) throws -> ExcelWorksheet {
        let sheetData = try reader.data(at: summary.partPath)
        let parsed = try ExcelWorksheetParser.parse(
            sheetData,
            sharedStrings: sharedStrings,
            styles: styles,
            uses1904DateSystem: uses1904DateSystem,
            includedRows: includedRows
        )
        guard let sheetXML = String(data: sheetData, encoding: .utf8) else {
            throw ExcelWorkbookDocumentError.invalidWorkbook
        }
        let tableRelationships = try relationshipsForPart(
            summary.partPath,
            reader: reader
        )
        var tables = [ExcelTable]()
        for relationshipID in parsed.tableRelationshipIDs {
            guard let relationship = tableRelationships[relationshipID],
                  relationship.type.hasSuffix("/table"),
                  let path = normalizedPartPath(
                      relationship.target,
                      relativeTo: summary.partPath
                  ),
                  reader.contains(path),
                  let table = try ExcelTableParser.parse(
                      reader.data(at: path),
                      partPath: path
                  ) else {
                continue
            }
            tables.append(table)
        }
        let annotations = try ExcelWorksheetAnnotationsLoader.load(
            sheetData: sheetData,
            sheetPartPath: summary.partPath,
            relationships: tableRelationships,
            reader: reader
        )
        let drawingObjects = try ExcelWorksheetDrawingObjectsLoader.load(
            sheetPartPath: summary.partPath,
            relationships: tableRelationships,
            reader: reader
        )
        let pivotTables = try ExcelWorksheetPivotTablesLoader.load(
            sheetPartPath: summary.partPath,
            relationships: tableRelationships,
            workbookPivotCacheRelationshipIDs:
                workbookPivotCacheRelationshipIDs,
            workbookRelationships: workbookRelationships,
            reader: reader
        )
        var printSettings = parsed.printSettings
        printSettings.printAreaFormula = namedPrintSettings.printAreaFormula
        printSettings.printTitlesFormula = namedPrintSettings.printTitlesFormula
        return ExcelWorksheet(
            id: summary.partPath,
            name: summary.name,
            partPath: summary.partPath,
            cells: parsed.cells,
            mergedRanges: parsed.mergedRanges,
            tables: tables,
            dataValidations: try ExcelDataValidationXMLParser.parse(
                sheetData
            ),
            conditionalFormatting: try
                ExcelConditionalFormattingXMLParser.parse(sheetXML),
            annotations: annotations,
            drawingObjects: drawingObjects,
            pivotTables: pivotTables,
            printSettings: printSettings,
            protection: parsed.protection,
            columnWidths: parsed.columnWidths,
            rowHeights: parsed.rowHeights,
            maximumRow: summary.maximumRow,
            maximumColumn: summary.maximumColumn,
            didTruncate: true,
            isWindowed: true,
            frozenPanes: parsed.frozenPanes
        )
    }

    private static func validateContainer(_ data: Data) throws {
        guard data.count <= maximumWorkbookBytes else {
            throw ExcelWorkbookDocumentError.workbookLimitExceeded
        }
        if data.starts(with: [
            0xD0, 0xCF, 0x11, 0xE0,
            0xA1, 0xB1, 0x1A, 0xE1,
        ]) {
            throw ExcelWorkbookDocumentError.unsupportedWorkbook
        }
    }

    static func applying(
        _ edits: [ExcelWorksheetEdits],
        to sourceData: Data,
        workbook: ExcelWorkbook,
        styleEdits: [ExcelStyleEdit] = [],
        validationEdits: [ExcelWorksheetValidationEdits] = [],
        conditionalFormattingEdits:
            [ExcelWorksheetConditionalFormattingEdits] = [],
        differentialStyleEdits: [ExcelDifferentialStyleEdit] = [],
        annotationEdits: [ExcelWorksheetAnnotationEdits] = [],
        drawingEdits: [ExcelWorksheetDrawingEdits] = [],
        pivotEdits: [ExcelWorksheetPivotEdits] = []
    ) throws -> Data {
        guard !edits.isEmpty
                || !styleEdits.isEmpty
                || !validationEdits.isEmpty
                || !conditionalFormattingEdits.isEmpty
                || !differentialStyleEdits.isEmpty
                || !annotationEdits.isEmpty
                || !drawingEdits.isEmpty
                || !pivotEdits.isEmpty else {
            return sourceData
        }
        let reader = try ExcelArchiveReader(data: sourceData)
        var replacements: [String: Data] = [:]
        let cellEditsByPath = Dictionary(
            uniqueKeysWithValues: edits.map { ($0.partPath, $0.cells) }
        )
        let validationEditsByPath = Dictionary(
            uniqueKeysWithValues: validationEdits.map {
                ($0.partPath, $0.rules)
            }
        )
        let conditionalEditsByPath = Dictionary(
            uniqueKeysWithValues: conditionalFormattingEdits.map {
                ($0.partPath, $0.blocks)
            }
        )
        let annotationEditsByPath = Dictionary(
            uniqueKeysWithValues: annotationEdits.map {
                ($0.partPath, $0)
            }
        )
        let drawingEditsByPath = Dictionary(
            uniqueKeysWithValues: drawingEdits.map {
                ($0.partPath, $0)
            }
        )
        let pivotEditsByPath = Dictionary(
            uniqueKeysWithValues: pivotEdits.map {
                ($0.partPath, $0)
            }
        )
        let createdTableSheetPaths = Set(
            workbook.sheets.compactMap { sheet in
                sheet.tables.contains(where: {
                    !reader.contains($0.partPath)
                }) ? sheet.partPath : nil
            }
        )

        if !styleEdits.isEmpty || !differentialStyleEdits.isEmpty {
            let path = "xl/styles.xml"
            guard reader.contains(path),
                  var source = String(
                      data: try reader.data(at: path),
                      encoding: .utf8
                  ) else {
                throw ExcelWorkbookDocumentError.cannotSave
            }
            if !styleEdits.isEmpty {
                source = try ExcelStylesXMLWriter.applying(
                    styleEdits,
                    to: source
                )
            }
            if !differentialStyleEdits.isEmpty {
                source = try ExcelDifferentialStylesXMLWriter.applying(
                    differentialStyleEdits,
                    to: source
                )
            }
            replacements[path] = Data(source.utf8)
        }

        let editedSheetPaths = Set(cellEditsByPath.keys)
            .union(validationEditsByPath.keys)
            .union(conditionalEditsByPath.keys)
            .union(annotationEditsByPath.keys)
            .union(drawingEditsByPath.keys)
            .union(pivotEditsByPath.keys)
            .union(createdTableSheetPaths)
        for partPath in editedSheetPaths {
            guard let sheet = workbook.sheets.first(
                where: { $0.partPath == partPath }
            ) else {
                continue
            }
            let originalData = try reader.data(at: sheet.partPath)
            guard var xml = String(
                data: originalData,
                encoding: .utf8
            ) else {
                throw ExcelWorkbookDocumentError.invalidWorkbook
            }
            let cellEdits = cellEditsByPath[partPath] ?? [:]
            for (address, edit) in cellEdits.sorted(
                by: { $0.key < $1.key }
            ) {
                xml = try ExcelWorksheetXMLWriter.apply(
                    edit,
                    at: address,
                    to: xml
                )
            }
            xml = ExcelWorksheetXMLWriter.expandDimension(
                in: xml,
                toInclude: cellEdits.keys
            )

            let maximumEditedRow = cellEdits.keys
                .map(\.row)
                .max() ?? 0
            for table in sheet.tables
                where maximumEditedRow > table.range.end.row
            {
                let editsBelowTable = cellEdits
                    .filter { $0.key.row > table.range.end.row }
                let editedColumns = editsBelowTable
                    .map { $0.key.column }
                let editedRows = Set(
                    editsBelowTable.map { $0.key.row }
                )
                let expectedRows = Set(
                    (table.range.end.row + 1) ... maximumEditedRow
                )
                guard editedRows == expectedRows,
                      !editedColumns.isEmpty,
                      editedColumns.allSatisfy({
                          $0 >= table.range.start.column
                              && $0 <= table.range.end.column
                      }) else {
                    continue
                }
                let newRange = ExcelCellRange(
                    start: table.range.start,
                    end: ExcelCellAddress(
                        row: maximumEditedRow,
                        column: table.range.end.column
                    )
                )
                xml = ExcelWorksheetXMLWriter.replaceReference(
                    table.range.reference,
                    with: newRange.reference,
                    in: xml,
                    elementNames: ["autoFilter"]
                )
                let tableData: Data
                if let replacement = replacements[table.partPath] {
                    tableData = replacement
                } else {
                    tableData = try reader.data(at: table.partPath)
                }
                guard let tableXML = String(
                    data: tableData,
                    encoding: .utf8
                ) else {
                    continue
                }
                let updated = ExcelWorksheetXMLWriter.replaceReference(
                    table.range.reference,
                    with: newRange.reference,
                    in: tableXML,
                    elementNames: ["table", "autoFilter"]
                )
                replacements[table.partPath] = Data(updated.utf8)
            }
            if let validationRules = validationEditsByPath[partPath] {
                xml = try ExcelDataValidationXMLWriter.applying(
                    validationRules,
                    to: xml
                )
            }
            if let conditionalBlocks = conditionalEditsByPath[partPath] {
                xml = try ExcelConditionalFormattingXMLWriter.applying(
                    conditionalBlocks,
                    to: xml
                )
            }
            if let annotationEdit = annotationEditsByPath[partPath] {
                try ExcelWorksheetAnnotationsPackageWriter.apply(
                    annotationEdit,
                    sheetXML: &xml,
                    reader: reader,
                    replacements: &replacements
                )
            }
            if let drawingEdit = drawingEditsByPath[partPath] {
                try ExcelWorksheetDrawingPackageWriter.apply(
                    drawingEdit,
                    sheetXML: &xml,
                    reader: reader,
                    replacements: &replacements
                )
            }
            if let pivotEdit = pivotEditsByPath[partPath] {
                try ExcelWorksheetPivotPackageWriter.apply(
                    pivotEdit,
                    reader: reader,
                    replacements: &replacements
                )
            }
            let createdTables = sheet.tables.filter {
                !reader.contains($0.partPath)
            }
            if !createdTables.isEmpty {
                try ExcelWorksheetTablePackageWriter.apply(
                    createdTables,
                    sheetXML: &xml,
                    sheetPartPath: sheet.partPath,
                    reader: reader,
                    replacements: &replacements
                )
            }
            replacements[sheet.partPath] = Data(xml.utf8)
        }

        if !replacements.isEmpty {
            let workbookXML: Data
            if let replacement = replacements["xl/workbook.xml"] {
                workbookXML = replacement
            } else {
                workbookXML = try reader.data(at: "xl/workbook.xml")
            }
            if let text = String(data: workbookXML, encoding: .utf8) {
                replacements["xl/workbook.xml"] = Data(
                    ExcelWorksheetXMLWriter.markForRecalculation(text).utf8
                )
            }
        }
        return try reader.repack(replacing: replacements)
    }

    private static func printSettings(
        _ base: ExcelPrintSettings,
        sheetIndex: Int,
        definedNames: [ExcelDefinedName]
    ) -> ExcelPrintSettings {
        var result = base
        result.printAreaFormula = definedNames.first(where: {
            $0.name.caseInsensitiveCompare("_xlnm.Print_Area") == .orderedSame
                && $0.localSheetIndex == sheetIndex
        })?.formula
        result.printTitlesFormula = definedNames.first(where: {
            $0.name.caseInsensitiveCompare("_xlnm.Print_Titles")
                == .orderedSame
                && $0.localSheetIndex == sheetIndex
        })?.formula
        return result
    }

    private static func externalLinks(
        workbookInfo: ExcelWorkbookInfo,
        workbookRelationships: [String: ExcelRelationship],
        reader: ExcelArchiveReader
    ) throws -> [ExcelExternalLink] {
        try workbookInfo.externalLinkRelationshipIDs.compactMap {
            relationshipID in
            guard let relationship = workbookRelationships[relationshipID],
                  relationship.type.hasSuffix("/externalLink"),
                  let partPath = normalizedPartPath(
                      relationship.target,
                      relativeTo: "xl/workbook.xml"
                  ), reader.contains(partPath) else {
                return nil
            }
            let partRelationships = try relationshipsForPart(
                partPath,
                reader: reader
            )
            let externalTarget = partRelationships
                .sorted { $0.key < $1.key }
                .first(where: {
                    $0.value.targetMode?.caseInsensitiveCompare("External")
                        == .orderedSame
                })?.value.target
            return ExcelExternalLink(
                id: relationshipID,
                partPath: partPath,
                sourceTarget: externalTarget
            )
        }
    }

    private static func relationshipsForPart(
        _ path: String,
        reader: ExcelArchiveReader
    ) throws -> [String: ExcelRelationship] {
        let components = path.split(separator: "/")
        guard let filename = components.last else {
            return [:]
        }
        let directory = components.dropLast()
            .joined(separator: "/")
        let relationshipsPath = directory
            + "/_rels/"
            + filename
            + ".rels"
        guard reader.contains(relationshipsPath) else {
            return [:]
        }
        return try ExcelRelationshipsParser.parse(
            reader.data(at: relationshipsPath)
        )
    }
}

nonisolated final class ExcelArchiveReader {
    private let archive: Archive
    private let entries: [String: Entry]

    init(data: Data) throws {
        do {
            archive = try Archive(data: data, accessMode: .read)
        } catch {
            throw ExcelWorkbookDocumentError.invalidWorkbook
        }
        var mapped: [String: Entry] = [:]
        var entryCount = 0
        var expandedBytes: UInt64 = 0
        for entry in archive {
            entryCount += 1
            expandedBytes += entry.uncompressedSize
            guard entryCount <= ExcelWorkbookDocument.maximumArchiveEntries,
                  expandedBytes <= UInt64(
                      ExcelWorkbookDocument.maximumExpandedBytes
                  ),
                  entry.uncompressedSize <= UInt64(
                      ExcelWorkbookDocument.maximumEntryBytes
                  ),
                  entry.type != .symlink,
                  isSafeArchivePath(entry.path) else {
                throw ExcelWorkbookDocumentError.workbookLimitExceeded
            }
            mapped[entry.path] = entry
        }
        entries = mapped
    }

    func contains(_ path: String) -> Bool {
        entries[path] != nil
    }

    var paths: Set<String> {
        Set(entries.keys)
    }

    func data(at path: String) throws -> Data {
        guard let entry = entries[path],
              entry.type == .file else {
            throw ExcelWorkbookDocumentError.invalidWorkbook
        }
        var result = Data()
        result.reserveCapacity(Int(entry.uncompressedSize))
        do {
            _ = try archive.extract(entry) { chunk in
                guard result.count + chunk.count
                        <= ExcelWorkbookDocument.maximumEntryBytes else {
                    throw ExcelWorkbookDocumentError.workbookLimitExceeded
                }
                result.append(chunk)
            }
        } catch let error as ExcelWorkbookDocumentError {
            throw error
        } catch {
            throw ExcelWorkbookDocumentError.invalidWorkbook
        }
        return result
    }

    func repack(replacing replacements: [String: Data], removing removedPaths: Set<String> = []) throws -> Data {
        let output = try Archive(accessMode: .create)
        for entry in archive {
            if removedPaths.contains(entry.path) { continue }
            let replacement = replacements[entry.path]
            let payload: Data
            if let replacement {
                payload = replacement
            } else if entry.type == .file {
                payload = try data(at: entry.path)
            } else {
                payload = Data()
            }
            try output.addEntry(
                with: entry.path,
                type: entry.type,
                uncompressedSize: Int64(payload.count),
                compressionMethod: entry.type == .file
                    ? .deflate
                    : .none
            ) { position, size in
                let lower = Int(position)
                let upper = min(payload.count, lower + size)
                guard lower < upper else {
                    return Data()
                }
                return payload.subdata(in: lower..<upper)
            }
        }
        for path in replacements.keys.sorted()
            where entries[path] == nil {
            guard isSafeArchivePath(path) else {
                throw ExcelWorkbookDocumentError.cannotSave
            }
            let payload = replacements[path] ?? Data()
            try output.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(payload.count),
                compressionMethod: .deflate
            ) { position, size in
                let lower = Int(position)
                let upper = min(payload.count, lower + size)
                return lower < upper
                    ? payload.subdata(in: lower..<upper)
                    : Data()
            }
        }
        guard let result = output.data else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        return result
    }
}

private nonisolated struct ExcelWorkbookSheetInfo {
    let name: String
    let relationshipID: String
}

private nonisolated struct ExcelWorkbookInfo {
    let sheets: [ExcelWorkbookSheetInfo]
    let uses1904DateSystem: Bool
    let calculationID: Int?
    let pivotCacheRelationshipIDs: [Int: String]
    let definedNames: [ExcelDefinedName]
    let protection: ExcelWorkbookProtection
    let externalLinkRelationshipIDs: [String]
}

private nonisolated enum ExcelWorkbookParser {
    static func parse(_ data: Data) throws -> ExcelWorkbookInfo {
        let delegate = ExcelWorkbookParserDelegate()
        try parseExcelXML(data, delegate: delegate)
        return ExcelWorkbookInfo(
            sheets: delegate.sheets,
            uses1904DateSystem: delegate.uses1904DateSystem,
            calculationID: delegate.calculationID,
            pivotCacheRelationshipIDs:
                delegate.pivotCacheRelationshipIDs,
            definedNames: delegate.definedNames,
            protection: delegate.protection,
            externalLinkRelationshipIDs:
                delegate.externalLinkRelationshipIDs
        )
    }
}

private nonisolated final class ExcelWorkbookParserDelegate:
    NSObject,
    XMLParserDelegate
{
    var sheets: [ExcelWorkbookSheetInfo] = []
    var uses1904DateSystem = false
    var calculationID: Int?
    var pivotCacheRelationshipIDs: [Int: String] = [:]
    var definedNames: [ExcelDefinedName] = []
    var protection = ExcelWorkbookProtection()
    var externalLinkRelationshipIDs: [String] = []
    private var currentDefinedName: String?
    private var currentDefinedNameLocalSheetIndex: Int?
    private var currentDefinedNameIsHidden = false
    private var currentDefinedNameFormula = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch localExcelXMLName(qName ?? elementName) {
        case "workbookPr":
            uses1904DateSystem = attributeDict["date1904"] == "1"
                || attributeDict["date1904"]?.lowercased() == "true"
        case "calcPr":
            calculationID = Int(attributeDict["calcId"] ?? "")
        case "sheet":
            guard let name = attributeDict["name"],
                  let relationshipID = attributeDict["r:id"]
                    ?? attributeDict["id"] else {
                return
            }
            sheets.append(
                ExcelWorkbookSheetInfo(
                    name: String(name.prefix(120)),
                    relationshipID: relationshipID
                )
            )
        case "pivotCache":
            guard let cacheID = Int(attributeDict["cacheId"] ?? ""),
                  let relationshipID = attributeDict["r:id"]
                    ?? attributeDict["id"] else {
                return
            }
            pivotCacheRelationshipIDs[cacheID] = relationshipID
        case "workbookProtection":
            protection = ExcelWorkbookProtection(
                lockStructure: excelXMLBoolean(
                    attributeDict["lockStructure"]
                ),
                lockWindows: excelXMLBoolean(
                    attributeDict["lockWindows"]
                ),
                lockRevision: excelXMLBoolean(
                    attributeDict["lockRevision"]
                ),
                workbookPasswordHash: attributeDict["workbookPassword"],
                revisionsPasswordHash: attributeDict["revisionsPassword"]
            )
        case "externalReference":
            if let relationshipID = attributeDict["r:id"]
                ?? attributeDict["id"] {
                externalLinkRelationshipIDs.append(relationshipID)
            }
        case "definedName":
            guard let name = attributeDict["name"], !name.isEmpty else {
                return
            }
            currentDefinedName = name
            currentDefinedNameLocalSheetIndex = attributeDict[
                "localSheetId"
            ].flatMap(Int.init)
            currentDefinedNameIsHidden = attributeDict["hidden"] == "1"
                || attributeDict["hidden"]?.lowercased() == "true"
            currentDefinedNameFormula = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentDefinedName != nil {
            currentDefinedNameFormula += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard localExcelXMLName(qName ?? elementName) == "definedName",
              let name = currentDefinedName else { return }
        definedNames.append(ExcelDefinedName(
            name: name,
            formula: currentDefinedNameFormula,
            localSheetIndex: currentDefinedNameLocalSheetIndex,
            isHidden: currentDefinedNameIsHidden
        ))
        currentDefinedName = nil
        currentDefinedNameLocalSheetIndex = nil
        currentDefinedNameIsHidden = false
        currentDefinedNameFormula = ""
    }
}

nonisolated struct ExcelRelationship {
    let type: String
    let target: String
    let targetMode: String?
}

nonisolated enum ExcelRelationshipsParser {
    static func parse(_ data: Data) throws -> [String: ExcelRelationship] {
        let delegate = ExcelRelationshipsParserDelegate()
        try parseExcelXML(data, delegate: delegate)
        return delegate.relationships
    }
}

private nonisolated final class ExcelRelationshipsParserDelegate:
    NSObject,
    XMLParserDelegate
{
    var relationships: [String: ExcelRelationship] = [:]

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard localExcelXMLName(qName ?? elementName) == "Relationship",
              let identifier = attributeDict["Id"],
              let target = attributeDict["Target"] else {
            return
        }
        relationships[identifier] = ExcelRelationship(
            type: attributeDict["Type"] ?? "",
            target: target,
            targetMode: attributeDict["TargetMode"]
        )
    }
}

private nonisolated enum ExcelSharedStringsParser {
    static func parse(
        _ data: Data,
        maximumStrings: Int
    ) throws -> [String] {
        let delegate = ExcelSharedStringsParserDelegate(
            maximumStrings: maximumStrings
        )
        try parseExcelXML(data, delegate: delegate)
        guard !delegate.didExceedLimit else {
            throw ExcelWorkbookDocumentError.workbookLimitExceeded
        }
        return delegate.strings
    }
}

private nonisolated final class ExcelSharedStringsParserDelegate:
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
        self.maximumStrings = maximumStrings
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch localExcelXMLName(qName ?? elementName) {
        case "si":
            isInsideString = true
            current = ""
        case "t":
            isInsideText = isInsideString
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideText {
            current += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch localExcelXMLName(qName ?? elementName) {
        case "t":
            isInsideText = false
        case "si":
            isInsideString = false
            guard strings.count < maximumStrings else {
                didExceedLimit = true
                return
            }
            strings.append(current)
        default:
            break
        }
    }
}

private nonisolated struct ExcelWorksheetPreflightResult {
    let maximumRow: Int
    let maximumColumn: Int
    let cellCount: Int
    let populatedRows: [Int]
    let tableRelationshipIDs: [String]
}

private nonisolated enum ExcelWorksheetPreflightParser {
    static func parse(
        _ data: Data
    ) throws -> ExcelWorksheetPreflightResult {
        let delegate = ExcelWorksheetPreflightParserDelegate()
        try parseExcelXML(data, delegate: delegate)
        return ExcelWorksheetPreflightResult(
            maximumRow: delegate.maximumRow,
            maximumColumn: delegate.maximumColumn,
            cellCount: delegate.cellCount,
            populatedRows: delegate.populatedRows.sorted(),
            tableRelationshipIDs: delegate.tableRelationshipIDs
        )
    }
}

private nonisolated final class ExcelWorksheetPreflightParserDelegate:
    NSObject,
    XMLParserDelegate
{
    var maximumRow = 0
    var maximumColumn = 0
    var cellCount = 0
    var populatedRows = Set<Int>()
    var tableRelationshipIDs = [String]()
    var dimension: ExcelCellRange?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch localExcelXMLName(qName ?? elementName) {
        case "dimension":
            dimension = attributeDict["ref"].flatMap(ExcelCellRange.init)
        case "c":
            guard let address = attributeDict["r"].flatMap(
                ExcelCellAddress.init
            ) else {
                return
            }
            cellCount += 1
            populatedRows.insert(address.row)
            maximumRow = max(maximumRow, address.row)
            maximumColumn = max(maximumColumn, address.column)
        case "mergeCell":
            guard let range = attributeDict["ref"].flatMap(
                ExcelCellRange.init
            ) else {
                return
            }
            maximumRow = max(maximumRow, range.end.row)
            maximumColumn = max(maximumColumn, range.end.column)
        case "tablePart":
            if let relationshipID = attributeDict["r:id"]
                ?? attributeDict["id"] {
                tableRelationshipIDs.append(relationshipID)
            }
        default:
            break
        }
    }
}

private nonisolated enum ExcelWorksheetSearchParser {
    static func search(
        _ data: Data,
        sharedStrings: [String],
        query: String,
        maximumResults: Int
    ) throws -> [Int] {
        let delegate = ExcelWorksheetSearchParserDelegate(
            sharedStrings: sharedStrings,
            query: query,
            maximumResults: maximumResults
        )
        try parseExcelXML(data, delegate: delegate)
        return delegate.rows.sorted()
    }
}

private nonisolated final class ExcelWorksheetSearchParserDelegate:
    NSObject,
    XMLParserDelegate
{
    let sharedStrings: [String]
    let query: String
    let compactQuery: String
    let maximumResults: Int
    var rows = Set<Int>()

    private var currentAddress: ExcelCellAddress?
    private var currentType: String?
    private var currentValue = ""
    private var currentFormula = ""
    private var currentInlineValue = ""
    private var isInsideValue = false
    private var isInsideFormula = false
    private var isInsideInlineString = false
    private var isInsideInlineText = false

    init(
        sharedStrings: [String],
        query: String,
        maximumResults: Int
    ) {
        self.sharedStrings = sharedStrings
        self.query = Self.normalized(query)
        compactQuery = Self.compact(query)
        self.maximumResults = maximumResults
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch localExcelXMLName(qName ?? elementName) {
        case "c":
            currentAddress = attributeDict["r"].flatMap(
                ExcelCellAddress.init
            )
            currentType = attributeDict["t"]
            currentValue = ""
            currentFormula = ""
            currentInlineValue = ""
        case "v":
            isInsideValue = currentAddress != nil
        case "f":
            isInsideFormula = currentAddress != nil
        case "is":
            isInsideInlineString = currentAddress != nil
        case "t":
            isInsideInlineText = isInsideInlineString
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideValue {
            currentValue += string
        }
        if isInsideFormula {
            currentFormula += string
        }
        if isInsideInlineText {
            currentInlineValue += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch localExcelXMLName(qName ?? elementName) {
        case "v":
            isInsideValue = false
        case "f":
            isInsideFormula = false
        case "t":
            isInsideInlineText = false
        case "is":
            isInsideInlineString = false
        case "c":
            finishCell()
        default:
            break
        }
    }

    private func finishCell() {
        defer {
            currentAddress = nil
            currentType = nil
            currentValue = ""
            currentFormula = ""
            currentInlineValue = ""
        }
        guard rows.count < maximumResults,
              let row = currentAddress?.row else {
            return
        }
        let resolvedValue: String
        if currentType == "s",
           let index = Int(currentValue),
           sharedStrings.indices.contains(index) {
            resolvedValue = sharedStrings[index]
        } else if currentType == "inlineStr" {
            resolvedValue = currentInlineValue
        } else {
            resolvedValue = currentValue
        }
        if matches(resolvedValue) || matches(currentFormula) {
            rows.insert(row)
        }
    }

    private func matches(_ value: String) -> Bool {
        guard !query.isEmpty else {
            return false
        }
        let normalized = Self.normalized(value)
        if normalized.contains(query) {
            return true
        }
        return !compactQuery.isEmpty
            && Self.compact(value).contains(compactQuery)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func compact(_ value: String) -> String {
        normalized(value).unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        .map(String.init)
        .joined()
    }
}

private nonisolated struct ExcelParsedWorksheet {
    let cells: [ExcelCellAddress: ExcelCell]
    let mergedRanges: [ExcelCellRange]
    let tableRelationshipIDs: [String]
    let columnWidths: [Int: Double]
    let rowHeights: [Int: Double]
    let maximumRow: Int
    let maximumColumn: Int
    let didTruncate: Bool
    let printSettings: ExcelPrintSettings
    let protection: ExcelSheetProtection
    let frozenPanes: ExcelFrozenPanes
}

private nonisolated struct ExcelSharedFormulaTemplate {
    let anchor: ExcelCellAddress
    let formula: String
}

private nonisolated enum ExcelSharedFormulaTranslator {
    static func translated(
        _ formula: String,
        from anchor: ExcelCellAddress,
        to target: ExcelCellAddress
    ) -> String {
        let pattern = #"(?<![A-Za-z0-9_.\[])(\$?)([A-Za-z]{1,3})(\$?)([1-9][0-9]*)(?![A-Za-z0-9_(\]!])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return formula
        }
        let original = formula as NSString
        let matches = regex.matches(
            in: formula,
            range: NSRange(location: 0, length: original.length)
        )
        let result = NSMutableString(string: formula)
        let rowDelta = target.row - anchor.row
        let columnDelta = target.column - anchor.column
        for match in matches.reversed() {
            guard match.numberOfRanges == 5,
                  !isInsideStringLiteral(
                    original.substring(to: match.range.location)
                  ) else {
                continue
            }
            let columnAbsolute = original.substring(
                with: match.range(at: 1)
            ) == "$"
            let columnName = original.substring(
                with: match.range(at: 2)
            )
            let rowAbsolute = original.substring(
                with: match.range(at: 3)
            ) == "$"
            guard let parsed = ExcelCellAddress(columnName + "1"),
                  let row = Int(original.substring(
                    with: match.range(at: 4)
                  )) else {
                continue
            }
            let translatedColumn = columnAbsolute
                ? parsed.column
                : parsed.column + columnDelta
            let translatedRow = rowAbsolute ? row : row + rowDelta
            let replacement: String
            if translatedColumn > 0, translatedRow > 0 {
                replacement = (columnAbsolute ? "$" : "")
                    + ExcelCellAddress.columnName(translatedColumn)
                    + (rowAbsolute ? "$" : "")
                    + String(translatedRow)
            } else {
                replacement = "#REF!"
            }
            result.replaceCharacters(
                in: match.range,
                with: replacement
            )
        }
        return result as String
    }

    private static func isInsideStringLiteral(_ prefix: String) -> Bool {
        var isInside = false
        var index = prefix.startIndex
        while index < prefix.endIndex {
            guard prefix[index] == "\"" else {
                index = prefix.index(after: index)
                continue
            }
            let next = prefix.index(after: index)
            if isInside,
               next < prefix.endIndex,
               prefix[next] == "\"" {
                index = prefix.index(after: next)
            } else {
                isInside.toggle()
                index = next
            }
        }
        return isInside
    }
}

private nonisolated enum ExcelWorksheetParser {
    static func parse(
        _ data: Data,
        sharedStrings: [String],
        styles: [ExcelCellStyle],
        uses1904DateSystem: Bool,
        includedRows: Set<Int>? = nil
    ) throws -> ExcelParsedWorksheet {
        let delegate = ExcelWorksheetParserDelegate(
            sharedStrings: sharedStrings,
            styles: styles,
            uses1904DateSystem: uses1904DateSystem,
            includedRows: includedRows
        )
        try parseExcelXML(data, delegate: delegate)
        return ExcelParsedWorksheet(
            cells: delegate.cells,
            mergedRanges: delegate.mergedRanges,
            tableRelationshipIDs: delegate.tableRelationshipIDs,
            columnWidths: delegate.columnWidths,
            rowHeights: delegate.rowHeights,
            maximumRow: delegate.maximumRow,
            maximumColumn: delegate.maximumColumn,
            didTruncate: delegate.didTruncate,
            printSettings: delegate.printSettings,
            protection: delegate.protection,
            frozenPanes: delegate.frozenPanes
        )
    }

    static func visitCells(
        _ data: Data,
        sharedStrings: [String],
        styles: [ExcelCellStyle],
        uses1904DateSystem: Bool,
        visitor: @escaping (ExcelCell) throws -> Void
    ) throws {
        let delegate = ExcelWorksheetParserDelegate(
            sharedStrings: sharedStrings,
            styles: styles,
            uses1904DateSystem: uses1904DateSystem,
            includedRows: [],
            cellVisitor: visitor
        )
        try parseExcelXML(data, delegate: delegate)
        if let visitorError = delegate.visitorError {
            throw visitorError
        }
    }
}

private nonisolated final class ExcelWorksheetParserDelegate:
    NSObject,
    XMLParserDelegate
{
    let sharedStrings: [String]
    let styles: [ExcelCellStyle]
    let uses1904DateSystem: Bool
    let includedRows: Set<Int>?
    let cellVisitor: ((ExcelCell) throws -> Void)?
    var visitorError: Error?

    var cells: [ExcelCellAddress: ExcelCell] = [:]
    var mergedRanges: [ExcelCellRange] = []
    var tableRelationshipIDs: [String] = []
    var columnWidths: [Int: Double] = [:]
    var rowHeights: [Int: Double] = [:]
    var maximumRow = 0
    var maximumColumn = 0
    var didTruncate = false
    var printSettings = ExcelPrintSettings()
    var protection = ExcelSheetProtection()
    var frozenPanes = ExcelFrozenPanes.none
    private var isPrimarySheetView = false

    private var currentAddress: ExcelCellAddress?
    private var currentType: String?
    private var currentStyleIndex: Int?
    private var currentValue = ""
    private var currentFormula = ""
    private var currentFormulaType: String?
    private var currentSharedFormulaIndex: String?
    private var currentFormulaSpillRange: ExcelCellRange?
    private var currentInlineValue = ""
    private var isInsideValue = false
    private var isInsideFormula = false
    private var isInsideInlineString = false
    private var isInsideInlineText = false
    private var arrayFormulaRanges = [ExcelCellAddress: ExcelCellRange]()
    private var sharedFormulaTemplates = [String: ExcelSharedFormulaTemplate]()
    private var pendingSharedFormulaIndexes = [ExcelCellAddress: String]()

    init(
        sharedStrings: [String],
        styles: [ExcelCellStyle],
        uses1904DateSystem: Bool,
        includedRows: Set<Int>?,
        cellVisitor: ((ExcelCell) throws -> Void)? = nil
    ) {
        self.sharedStrings = sharedStrings
        self.styles = styles
        self.uses1904DateSystem = uses1904DateSystem
        self.includedRows = includedRows
        self.cellVisitor = cellVisitor
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch localExcelXMLName(qName ?? elementName) {
        case "sheetView":
            isPrimarySheetView = (attributeDict["workbookViewId"] ?? "0") == "0"
        case "pane":
            if isPrimarySheetView { frozenPanes = ExcelFrozenPanes.read(attributeDict) }
        case "row":
            if let row = Int(attributeDict["r"] ?? ""),
               let height = Double(attributeDict["ht"] ?? "") {
                rowHeights[row] = height
            }
        case "col":
            if let lower = Int(attributeDict["min"] ?? ""),
               let upper = Int(attributeDict["max"] ?? ""),
               let width = Double(attributeDict["width"] ?? "") {
                let cappedUpper = min(
                    upper,
                    ExcelWorkbookDocument.maximumColumnsPerSheet
                )
                if lower > 0, lower <= cappedUpper {
                    for column in lower ... cappedUpper {
                        columnWidths[column] = width
                    }
                }
            }
        case "c":
            currentAddress = attributeDict["r"].flatMap(ExcelCellAddress.init)
            currentType = attributeDict["t"]
            currentStyleIndex = attributeDict["s"].flatMap(Int.init)
            currentValue = ""
            currentFormula = ""
            currentFormulaType = nil
            currentSharedFormulaIndex = nil
            currentFormulaSpillRange = nil
            currentInlineValue = ""
        case "v":
            isInsideValue = currentAddress != nil
        case "f":
            isInsideFormula = currentAddress != nil
            currentFormulaType = attributeDict["t"]
            currentSharedFormulaIndex = attributeDict["si"]
            if attributeDict["t"] == "array",
               let range = attributeDict["ref"].flatMap(ExcelCellRange.init) {
                currentFormulaSpillRange = range
            }
        case "is":
            isInsideInlineString = currentAddress != nil
        case "t":
            isInsideInlineText = isInsideInlineString
        case "mergeCell":
            if let reference = attributeDict["ref"],
               let range = ExcelCellRange(reference) {
                mergedRanges.append(range)
                maximumRow = max(maximumRow, range.end.row)
                maximumColumn = max(maximumColumn, range.end.column)
            }
        case "tablePart":
            if let relationshipID = attributeDict["r:id"]
                ?? attributeDict["id"] {
                tableRelationshipIDs.append(relationshipID)
            }
        case "pageMargins":
            printSettings.margins = ExcelPageMargins(
                left: Double(attributeDict["left"] ?? "") ?? 0.7,
                right: Double(attributeDict["right"] ?? "") ?? 0.7,
                top: Double(attributeDict["top"] ?? "") ?? 0.75,
                bottom: Double(attributeDict["bottom"] ?? "") ?? 0.75,
                header: Double(attributeDict["header"] ?? "") ?? 0.3,
                footer: Double(attributeDict["footer"] ?? "") ?? 0.3
            )
        case "pageSetup":
            printSettings.orientation = attributeDict["orientation"]
                .flatMap(ExcelPageOrientation.init(rawValue:))
            printSettings.paperSize = attributeDict["paperSize"]
                .flatMap(Int.init)
            printSettings.scale = attributeDict["scale"].flatMap(Int.init)
            printSettings.fitToWidth = attributeDict["fitToWidth"]
                .flatMap(Int.init)
            printSettings.fitToHeight = attributeDict["fitToHeight"]
                .flatMap(Int.init)
        case "sheetProtection":
            let passwordHash = attributeDict["password"]
            let hashValue = attributeDict["hashValue"]
            protection = ExcelSheetProtection(
                isEnabled: excelXMLBoolean(attributeDict["sheet"])
                    || passwordHash != nil || hashValue != nil,
                protectsObjects: excelXMLBoolean(
                    attributeDict["objects"]
                ),
                protectsScenarios: excelXMLBoolean(
                    attributeDict["scenarios"]
                ),
                passwordHash: passwordHash,
                algorithmName: attributeDict["algorithmName"],
                hashValue: hashValue,
                saltValue: attributeDict["saltValue"],
                spinCount: attributeDict["spinCount"].flatMap(Int.init)
            )
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideValue {
            currentValue += string
        }
        if isInsideFormula {
            currentFormula += string
        }
        if isInsideInlineText {
            currentInlineValue += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch localExcelXMLName(qName ?? elementName) {
        case "sheetView":
            isPrimarySheetView = false
        case "v":
            isInsideValue = false
        case "f":
            isInsideFormula = false
        case "t":
            isInsideInlineText = false
        case "is":
            isInsideInlineString = false
        case "c":
            finishCell()
        default:
            break
        }
    }

    private func finishCell() {
        defer {
            currentAddress = nil
            currentType = nil
            currentStyleIndex = nil
            currentValue = ""
            currentFormula = ""
            currentFormulaType = nil
            currentSharedFormulaIndex = nil
            currentFormulaSpillRange = nil
            currentInlineValue = ""
        }
        guard let address = currentAddress else {
            return
        }
        maximumRow = max(maximumRow, address.row)
        maximumColumn = max(maximumColumn, address.column)
        let resolvedFormula = resolveCurrentFormula(at: address)
        let rowIsIncluded = includedRows?.contains(address.row)
            ?? (address.row <= ExcelWorkbookDocument.maximumRowsPerSheet)
        let columnIsIncluded = address.column
            <= ExcelWorkbookDocument.maximumColumnsPerSheet
        guard (rowIsIncluded && columnIsIncluded)
            || (cellVisitor != nil && columnIsIncluded) else {
            didTruncate = true
            return
        }

        let rawValue: String
        switch currentType {
        case "s":
            if let index = Int(currentValue),
               sharedStrings.indices.contains(index) {
                rawValue = sharedStrings[index]
            } else {
                rawValue = ""
            }
        case "inlineStr":
            rawValue = currentInlineValue
        case "b":
            rawValue = currentValue == "1" ? "TRUE" : "FALSE"
        default:
            rawValue = currentValue
        }
        let style = currentStyleIndex.flatMap {
            styles.indices.contains($0) ? styles[$0] : nil
        } ?? .plain
        let displayValue = ExcelValueFormatter.displayValue(
            rawValue,
            type: currentType,
            style: style,
            uses1904DateSystem: uses1904DateSystem
        )
        let cell = ExcelCell(
            address: address,
            rawValue: rawValue,
            displayValue: displayValue,
            formula: resolvedFormula,
            styleIndex: currentStyleIndex,
            cellType: currentType,
            spillAnchor: currentFormulaSpillRange == nil ? nil : address,
            spillRange: currentFormulaSpillRange
        )
        if let currentFormulaSpillRange {
            arrayFormulaRanges[address] = currentFormulaSpillRange
        }
        if resolvedFormula == nil,
           currentFormulaType == "shared",
           let currentSharedFormulaIndex {
            pendingSharedFormulaIndexes[address] = currentSharedFormulaIndex
        }
        if visitorError == nil,
           let cellVisitor {
            do {
                try cellVisitor(cell)
            } catch {
                visitorError = error
            }
        }
        guard rowIsIncluded,
              columnIsIncluded,
              cells.count < ExcelWorkbookDocument.maximumCellsPerSheet else {
            didTruncate = true
            return
        }
        cells[address] = cell
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        for (address, index) in pendingSharedFormulaIndexes {
            guard let template = sharedFormulaTemplates[index],
                  var cell = cells[address] else {
                continue
            }
            cell.formula = ExcelSharedFormulaTranslator.translated(
                template.formula,
                from: template.anchor,
                to: address
            )
            cells[address] = cell
        }
        guard !arrayFormulaRanges.isEmpty else { return }
        for address in Array(cells.keys) {
            guard let (anchor, range) = arrayFormulaRanges.first(where: {
                $0.value.contains(address)
            }), var cell = cells[address] else { continue }
            cell.spillAnchor = anchor
            cell.spillRange = address == anchor ? range : nil
            cells[address] = cell
        }
    }

    private func resolveCurrentFormula(
        at address: ExcelCellAddress
    ) -> String? {
        guard currentFormulaType == "shared",
              let currentSharedFormulaIndex else {
            return currentFormula.isEmpty ? nil : currentFormula
        }
        if !currentFormula.isEmpty {
            sharedFormulaTemplates[currentSharedFormulaIndex] =
                ExcelSharedFormulaTemplate(
                    anchor: address,
                    formula: currentFormula
                )
            return currentFormula
        }
        guard let template = sharedFormulaTemplates[
            currentSharedFormulaIndex
        ] else {
            return nil
        }
        return ExcelSharedFormulaTranslator.translated(
            template.formula,
            from: template.anchor,
            to: address
        )
    }
}

private nonisolated enum ExcelStylesParser {
    static func parse(_ data: Data) throws -> [ExcelCellStyle] {
        let delegate = ExcelStylesParserDelegate()
        try parseExcelXML(data, delegate: delegate)
        return try ExcelExtendedStyleReader.applying(data, to: delegate.styles.isEmpty ? [.plain] : delegate.styles)
    }
}

private nonisolated final class ExcelStylesParserDelegate:
    NSObject,
    XMLParserDelegate
{
    private struct XF {
        let numberFormatID: Int
        let fontID: Int
        let fillID: Int
        var alignment: String?
    }

    var styles: [ExcelCellStyle] = []
    private var numberFormats: [Int: String] = [:]
    private var fontsBold: [Bool] = []
    private var fills: [String?] = []
    private var currentSection = ""
    private var currentFontBold = false
    private var currentFill: String?
    private var currentXF: XF?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localExcelXMLName(qName ?? elementName)
        switch name {
        case "numFmts", "fonts", "fills", "cellXfs":
            currentSection = name
        case "numFmt" where currentSection == "numFmts":
            if let identifier = Int(attributeDict["numFmtId"] ?? ""),
               let code = attributeDict["formatCode"] {
                numberFormats[identifier] = code
            }
        case "font" where currentSection == "fonts":
            currentFontBold = false
        case "b" where currentSection == "fonts":
            currentFontBold = attributeDict["val"] != "0"
        case "fill" where currentSection == "fills":
            currentFill = nil
        case "fgColor" where currentSection == "fills":
            currentFill = attributeDict["rgb"]
        case "xf" where currentSection == "cellXfs":
            currentXF = XF(
                numberFormatID: Int(attributeDict["numFmtId"] ?? "") ?? 0,
                fontID: Int(attributeDict["fontId"] ?? "") ?? 0,
                fillID: Int(attributeDict["fillId"] ?? "") ?? 0,
                alignment: nil
            )
        case "alignment" where currentSection == "cellXfs":
            currentXF?.alignment = attributeDict["horizontal"]
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
        let name = localExcelXMLName(qName ?? elementName)
        switch name {
        case "font" where currentSection == "fonts":
            fontsBold.append(currentFontBold)
        case "fill" where currentSection == "fills":
            fills.append(currentFill)
        case "xf" where currentSection == "cellXfs":
            if let currentXF {
                styles.append(
                    ExcelCellStyle(
                        numberFormatID: currentXF.numberFormatID,
                        numberFormatCode: numberFormats[
                            currentXF.numberFormatID
                        ] ?? ExcelValueFormatter.builtInFormat(
                            currentXF.numberFormatID
                        ),
                        isBold: fontsBold.indices.contains(currentXF.fontID)
                            ? fontsBold[currentXF.fontID]
                            : false,
                        fillARGB: fills.indices.contains(currentXF.fillID)
                            ? fills[currentXF.fillID]
                            : nil,
                        horizontalAlignment: currentXF.alignment
                    )
                )
            }
            currentXF = nil
        case "numFmts", "fonts", "fills", "cellXfs":
            currentSection = ""
        default:
            break
        }
    }
}

private nonisolated enum ExcelTableParser {
    static func parse(
        _ data: Data,
        partPath: String
    ) throws -> ExcelTable? {
        let delegate = ExcelTableParserDelegate(partPath: partPath)
        try parseExcelXML(data, delegate: delegate)
        return delegate.table
    }
}

private nonisolated final class ExcelTableParserDelegate:
    NSObject,
    XMLParserDelegate
{
    let partPath: String
    var table: ExcelTable?

    init(partPath: String) {
        self.partPath = partPath
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let element = localExcelXMLName(qName ?? elementName)
        if element == "tableColumn", let name = attributeDict["name"] {
            table?.columnNames.append(name)
            return
        }
        guard table == nil, element == "table",
              let reference = attributeDict["ref"],
              let range = ExcelCellRange(reference) else { return }
        let identifier = attributeDict["id"] ?? partPath
        table = ExcelTable(
            id: identifier,
            name: attributeDict["displayName"]
                ?? attributeDict["name"]
                ?? AppLocalization.string("표"),
            range: range,
            partPath: partPath,
            columnNames: [],
            headerRowCount: Int(attributeDict["headerRowCount"] ?? "1") ?? 1,
            totalsRowCount: Int(attributeDict["totalsRowCount"] ?? "0")
                ?? ((attributeDict["totalsRowShown"] == "1") ? 1 : 0)
        )
    }
}

nonisolated enum ExcelValueFormatter {
    static func builtInFormat(_ identifier: Int) -> String? {
        switch identifier {
        case 1: return "0"
        case 2: return "0.00"
        case 3: return "#,##0"
        case 4: return "#,##0.00"
        case 9: return "0%"
        case 10: return "0.00%"
        case 14: return "m/d/yy"
        case 15: return "d-mmm-yy"
        case 16: return "d-mmm"
        case 17: return "mmm-yy"
        case 18: return "h:mm AM/PM"
        case 19: return "h:mm:ss AM/PM"
        case 20: return "h:mm"
        case 21: return "h:mm:ss"
        case 22: return "m/d/yy h:mm"
        case 45: return "mm:ss"
        case 46: return "[h]:mm:ss"
        case 47: return "mmss.0"
        case 49: return "@"
        default: return nil
        }
    }

    static func displayValue(
        _ raw: String,
        type: String?,
        style: ExcelCellStyle,
        uses1904DateSystem: Bool
    ) -> String {
        if type == "b" {
            return raw == "TRUE"
                ? AppLocalization.string("참")
                : AppLocalization.string("거짓")
        }
        guard type == nil || type == "n",
              let number = Double(raw),
              let format = style.numberFormatCode else {
            return raw
        }
        if isDateFormat(format),
           let date = excelDate(
               number,
               uses1904DateSystem: uses1904DateSystem
           ) {
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            let normalized = format.lowercased()
            if normalized.contains("yyyy-mm-dd") {
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd"
            } else if normalized == "h:mm" {
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "H:mm"
            } else {
                formatter.dateStyle = containsDateFields(format)
                    ? .short
                    : .none
                formatter.timeStyle = containsTimeFields(format)
                    ? .short
                    : .none
            }
            return formatter.string(from: date)
        }
        if format.contains("%") {
            let formatter = NumberFormatter()
            formatter.numberStyle = .percent
            formatter.minimumFractionDigits = decimalPlaces(in: format)
            formatter.maximumFractionDigits = decimalPlaces(in: format)
            return formatter.string(from: NSNumber(value: number)) ?? raw
        }
        if format.contains("₩") {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.currencySymbol = "₩"
            formatter.minimumFractionDigits = decimalPlaces(in: format)
            formatter.maximumFractionDigits = decimalPlaces(in: format)
            return formatter.string(from: NSNumber(value: number)) ?? raw
        }
        if format.contains(",") || format.contains(".") {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = format.contains(",")
            formatter.minimumFractionDigits = decimalPlaces(in: format)
            formatter.maximumFractionDigits = decimalPlaces(in: format)
            return formatter.string(from: NSNumber(value: number)) ?? raw
        }
        return raw
    }

    private static func isDateFormat(_ format: String) -> Bool {
        let cleaned = format
            .replacingOccurrences(
                of: #""[^"]*"|\\.|\[[^\]]*\]"#,
                with: "",
                options: .regularExpression
            )
            .lowercased()
        return cleaned.range(of: "[ymdhis]", options: .regularExpression) != nil
    }

    private static func containsDateFields(_ format: String) -> Bool {
        let normalized = format.lowercased()
        if normalized.range(
            of: "[yd]",
            options: .regularExpression
        ) != nil {
            return true
        }
        return !containsTimeFields(normalized)
            && normalized.contains("m")
    }

    private static func containsTimeFields(_ format: String) -> Bool {
        format.lowercased().range(
            of: "[his]",
            options: .regularExpression
        ) != nil
    }

    private static func excelDate(
        _ serial: Double,
        uses1904DateSystem: Bool
    ) -> Date? {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = uses1904DateSystem ? 1904 : 1899
        components.month = uses1904DateSystem ? 1 : 12
        components.day = uses1904DateSystem ? 1 : 30
        guard let base = components.date else {
            return nil
        }
        return base.addingTimeInterval(serial * 86_400)
    }

    private static func decimalPlaces(in format: String) -> Int {
        guard let dot = format.firstIndex(of: ".") else {
            return 0
        }
        return format[format.index(after: dot)...]
            .prefix { $0 == "0" || $0 == "#" }
            .count
    }
}

private nonisolated enum ExcelWorksheetTablePackageWriter {
    private static let relationshipType =
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships/table"
    private static let contentType =
        "application/vnd.openxmlformats-officedocument.spreadsheetml.table+xml"
    private static let optionalPrefix =
        "(?:[A-Za-z_][A-Za-z0-9_.-]*:)?"

    static func apply(
        _ tables: [ExcelTable],
        sheetXML: inout String,
        sheetPartPath: String,
        reader: ExcelArchiveReader,
        replacements: inout [String: Data]
    ) throws {
        guard !tables.isEmpty else { return }
        let relationshipsPath = try relationshipsPath(
            for: sheetPartPath
        )
        var relationshipsXML: String
        if let replacement = replacements[relationshipsPath] {
            guard let text = String(data: replacement, encoding: .utf8) else {
                throw ExcelWorkbookDocumentError.cannotSave
            }
            relationshipsXML = text
        } else if reader.contains(relationshipsPath) {
            guard let text = String(
                data: try reader.data(at: relationshipsPath),
                encoding: .utf8
            ) else {
                throw ExcelWorkbookDocumentError.cannotSave
            }
            relationshipsXML = text
        } else {
            relationshipsXML = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"></Relationships>
            """
        }

        var usedRelationshipIDs = Set(
            try ExcelRelationshipsParser.parse(
                Data(relationshipsXML.utf8)
            ).keys
        )
        var tablePartElements = [String]()
        for table in tables.sorted(by: { $0.partPath < $1.partPath }) {
            try validate(table)
            let relationshipID = nextRelationshipID(
                used: &usedRelationshipIDs
            )
            let target = "../tables/"
                + URL(fileURLWithPath: table.partPath).lastPathComponent
            relationshipsXML = try inserting(
                "<Relationship Id=\"\(relationshipID)\" Type=\"\(relationshipType)\" Target=\"\(escapeXML(target))\"/>",
                beforeClosingElement: "Relationships",
                in: relationshipsXML
            )
            tablePartElements.append(
                "<tablePart r:id=\"\(relationshipID)\"/>"
            )
            replacements[table.partPath] = Data(tableXML(table).utf8)
            try addContentType(
                for: table.partPath,
                reader: reader,
                replacements: &replacements
            )
            sheetXML = ExcelWorksheetXMLWriter.expandDimension(
                in: sheetXML,
                toInclude: table.range
            )
        }

        sheetXML = try addingTableParts(
            tablePartElements,
            to: sheetXML
        )
        replacements[relationshipsPath] = Data(relationshipsXML.utf8)
    }

    private static func validate(_ table: ExcelTable) throws {
        let width = table.range.end.column - table.range.start.column + 1
        guard table.range.start.row > 0,
              table.range.start.column > 0,
              table.range.end.row > table.range.start.row,
              width == table.columnNames.count,
              !table.columnNames.isEmpty,
              table.columnNames.allSatisfy({
                  !$0.isEmpty && $0.count <= 255 && !$0.contains("\0")
              }),
              table.partPath.hasPrefix("xl/tables/"),
              table.partPath.hasSuffix(".xml") else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
    }

    private static func relationshipsPath(
        for partPath: String
    ) throws -> String {
        let components = partPath.split(separator: "/")
        guard let filename = components.last else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        let directory = components.dropLast().joined(separator: "/")
        return directory + "/_rels/" + filename + ".rels"
    }

    private static func nextRelationshipID(
        used: inout Set<String>
    ) -> String {
        var index = 1
        while used.contains("rId\(index)") {
            index += 1
        }
        let result = "rId\(index)"
        used.insert(result)
        return result
    }

    private static func tableXML(_ table: ExcelTable) -> String {
        let identifier = Int(table.id) ?? 1
        let columns = table.columnNames.enumerated().map {
            "<tableColumn id=\"\($0.offset + 1)\" name=\"\(escapeXML($0.element))\"/>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <table xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" id="\(identifier)" name="\(escapeXML(table.name))" displayName="\(escapeXML(table.name))" ref="\(table.range.reference)" headerRowCount="1" totalsRowShown="0"><autoFilter ref="\(table.range.reference)"/><tableColumns count="\(table.columnNames.count)">\(columns)</tableColumns><tableStyleInfo name="TableStyleMedium2" showFirstColumn="0" showLastColumn="0" showRowStripes="1" showColumnStripes="0"/></table>
        """
    }

    private static func addingTableParts(
        _ elements: [String],
        to source: String
    ) throws -> String {
        guard !elements.isEmpty else { return source }
        var result = ensureRelationshipNamespace(in: source)
        let prefix = worksheetPrefix(in: result)
        let existingClosingPattern = "</" + optionalPrefix
            + "tableParts\\s*>"
        if let closing = lastRange(
            matching: existingClosingPattern,
            in: result
        ) {
            let qualifiedElements = elements.map {
                $0.replacingOccurrences(
                    of: "<tablePart ",
                    with: "<\(prefix)tablePart "
                )
            }.joined()
            result = result.replacingCharacters(
                in: closing.lowerBound..<closing.lowerBound,
                with: qualifiedElements
            )
            return updatingTablePartCount(in: result)
        }

        let body = elements.map {
            $0.replacingOccurrences(
                of: "<tablePart ",
                with: "<\(prefix)tablePart "
            )
        }.joined()
        let tableParts = "<\(prefix)tableParts count=\"\(elements.count)\">"
            + body + "</\(prefix)tableParts>"
        let extensionPattern = "<" + optionalPrefix + "extLst\\b"
        if let extensionRange = firstRange(
            matching: extensionPattern,
            in: result
        ) {
            return result.replacingCharacters(
                in: extensionRange.lowerBound..<extensionRange.lowerBound,
                with: tableParts
            )
        }
        let worksheetClosing = "</" + optionalPrefix + "worksheet\\s*>"
        guard let closing = lastRange(
            matching: worksheetClosing,
            in: result
        ) else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        return result.replacingCharacters(
            in: closing.lowerBound..<closing.lowerBound,
            with: tableParts
        )
    }

    private static func updatingTablePartCount(
        in source: String
    ) -> String {
        let partPattern = "<" + optionalPrefix + "tablePart\\b"
        let count = matches(of: partPattern, in: source).count
        let openingPattern = "<" + optionalPrefix + "tableParts\\b[^>]*>"
        guard let opening = firstRange(
            matching: openingPattern,
            in: source
        ) else { return source }
        var element = String(source[opening])
        let countPattern = "\\bcount\\s*=\\s*[\"'][0-9]+[\"']"
        if element.range(of: countPattern, options: .regularExpression) != nil {
            element = element.replacingOccurrences(
                of: countPattern,
                with: "count=\"\(count)\"",
                options: .regularExpression
            )
        } else if let close = element.lastIndex(of: ">") {
            element.insert(contentsOf: " count=\"\(count)\"", at: close)
        }
        return source.replacingCharacters(in: opening, with: element)
    }

    private static func ensureRelationshipNamespace(
        in source: String
    ) -> String {
        guard source.range(
            of: #"xmlns:r\s*=\s*[\"']http://schemas.openxmlformats.org/officeDocument/2006/relationships[\"']"#,
            options: .regularExpression
        ) == nil else { return source }
        let openingPattern = "<" + optionalPrefix + "worksheet\\b[^>]*>"
        guard let opening = firstRange(
            matching: openingPattern,
            in: source
        ) else { return source }
        var element = String(source[opening])
        guard let close = element.lastIndex(of: ">") else { return source }
        element.insert(
            contentsOf: " xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"",
            at: close
        )
        return source.replacingCharacters(in: opening, with: element)
    }

    private static func worksheetPrefix(in source: String) -> String {
        let pattern = "<([A-Za-z_][A-Za-z0-9_.-]*:)?worksheet\\b"
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

    private static func addContentType(
        for partPath: String,
        reader: ExcelArchiveReader,
        replacements: inout [String: Data]
    ) throws {
        let path = "[Content_Types].xml"
        let data = try replacements[path] ?? reader.data(at: path)
        guard var source = String(data: data, encoding: .utf8) else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        let partName = "/" + partPath
        guard !source.contains("PartName=\"\(partName)\"")
                && !source.contains("PartName='\(partName)'") else {
            return
        }
        source = try inserting(
            "<Override PartName=\"\(escapeXML(partName))\" ContentType=\"\(contentType)\"/>",
            beforeClosingElement: "Types",
            in: source
        )
        replacements[path] = Data(source.utf8)
    }

    private static func inserting(
        _ element: String,
        beforeClosingElement name: String,
        in source: String
    ) throws -> String {
        let pattern = "</" + optionalPrefix
            + NSRegularExpression.escapedPattern(for: name)
            + "\\s*>"
        guard let closing = lastRange(matching: pattern, in: source) else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        return source.replacingCharacters(
            in: closing.lowerBound..<closing.lowerBound,
            with: element
        )
    }

    private static func matches(
        of pattern: String,
        in source: String
    ) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        return regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )
    }

    private static func firstRange(
        matching pattern: String,
        in source: String
    ) -> Range<String.Index>? {
        matches(of: pattern, in: source).first.flatMap {
            Range($0.range, in: source)
        }
    }

    private static func lastRange(
        matching pattern: String,
        in source: String
    ) -> Range<String.Index>? {
        matches(of: pattern, in: source).last.flatMap {
            Range($0.range, in: source)
        }
    }
}

private nonisolated enum ExcelWorksheetXMLWriter {
    static func apply(
        _ edit: ExcelCellEdit,
        at address: ExcelCellAddress,
        to source: String
    ) throws -> String {
        let namespacePrefix = namespacePrefix(
            forRootElement: "worksheet",
            in: source
        )
        let cellPattern = "<" + optionalNamespacePrefixPattern
            + "c\\b(?=[^>]*\\br\\s*=\\s*[\"']"
            + NSRegularExpression.escapedPattern(for: address.reference)
            + "[\"'])[^>]*(?:/>|>[\\s\\S]*?</"
            + optionalNamespacePrefixPattern
            + "c\\s*>)"
        let cellRegex = try NSRegularExpression(pattern: cellPattern)
        let fullRange = NSRange(source.startIndex..., in: source)
        let cellXML = serializedCell(
            address: address,
            edit: edit,
            namespacePrefix: namespacePrefix
        )
        if let match = cellRegex.firstMatch(
            in: source,
            range: fullRange
        ),
        let range = Range(match.range, in: source) {
            let replacement = edit.preservesExistingContent
                ? replacingStyle(
                    in: String(source[range]),
                    with: edit.styleIndex
                )
                : cellXML
            return source.replacingCharacters(in: range, with: replacement)
        }

        guard !edit.preservesExistingContent else {
            throw ExcelWorkbookDocumentError.cannotSave
        }

        let rowPattern = "<" + optionalNamespacePrefixPattern
            + "row\\b(?=[^>]*\\br\\s*=\\s*[\"']"
            + String(address.row)
            + "[\"'])[^>]*(?:/>|>[\\s\\S]*?</"
            + optionalNamespacePrefixPattern
            + "row\\s*>)"
        let rowRegex = try NSRegularExpression(pattern: rowPattern)
        if let match = rowRegex.firstMatch(
            in: source,
            range: fullRange
        ),
        let range = Range(match.range, in: source) {
            let originalRow = String(source[range])
            let updatedRow = try insert(
                cellXML,
                address: address,
                intoRowXML: originalRow,
                namespacePrefix: namespacePrefix
            )
            return source.replacingCharacters(in: range, with: updatedRow)
        }

        let newRow = "<\(namespacePrefix)row r=\"\(address.row)\">"
            + cellXML
            + "</\(namespacePrefix)row>"
        return try insert(
            newRow,
            rowNumber: address.row,
            intoWorksheetXML: source
        )
    }

    static func expandDimension(
        in source: String,
        toInclude addresses: Dictionary<ExcelCellAddress, ExcelCellEdit>.Keys
    ) -> String {
        guard let maximumRow = addresses.map(\.row).max(),
              let maximumColumn = addresses.map(\.column).max() else {
            return source
        }
        return expandDimension(
            in: source,
            toInclude: ExcelCellRange(
                start: ExcelCellAddress(row: 1, column: 1),
                end: ExcelCellAddress(
                    row: maximumRow,
                    column: maximumColumn
                )
            )
        )
    }

    static func expandDimension(
        in source: String,
        toInclude range: ExcelCellRange
    ) -> String {
        let pattern = "<" + optionalNamespacePrefixPattern
            + "dimension\\b[^>]*\\bref\\s*=\\s*[\"']([^\"']+)[\"'][^>]*/?>"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: source,
                  range: NSRange(source.startIndex..., in: source)
              ),
              match.numberOfRanges > 1,
              let elementRange = Range(match.range(at: 0), in: source),
              let referenceRange = Range(match.range(at: 1), in: source),
              let oldRange = ExcelCellRange(String(source[referenceRange])) else {
            return source
        }
        let newRange = ExcelCellRange(
            start: oldRange.start,
            end: ExcelCellAddress(
                row: max(oldRange.end.row, range.end.row),
                column: max(oldRange.end.column, range.end.column)
            )
        )
        let oldElement = String(source[elementRange])
        let newElement = oldElement.replacingOccurrences(
            of: String(source[referenceRange]),
            with: newRange.reference
        )
        return source.replacingCharacters(in: elementRange, with: newElement)
    }

    static func replaceReference(
        _ oldReference: String,
        with newReference: String,
        in source: String,
        elementNames: [String]
    ) -> String {
        var result = source
        for name in elementNames {
            let pattern = "(<" + optionalNamespacePrefixPattern
                + NSRegularExpression.escapedPattern(for: name)
                + "\\b[^>]*\\bref\\s*=\\s*[\"'])"
                + NSRegularExpression.escapedPattern(for: oldReference)
                + "([\"'])"
            result = result.replacingOccurrences(
                of: pattern,
                with: "$1" + newReference + "$2",
                options: .regularExpression
            )
        }
        return result
    }

    static func markForRecalculation(_ source: String) -> String {
        let namespacePrefix = namespacePrefix(
            forRootElement: "workbook",
            in: source
        )
        let pattern = "<" + optionalNamespacePrefixPattern
            + "calcPr\\b[^>]*/?>"
        let calculationProperties = "<\(namespacePrefix)calcPr "
            + "calcMode=\"auto\" fullCalcOnLoad=\"1\" "
            + "forceFullCalc=\"1\"/>"
        if source.range(of: pattern, options: .regularExpression) != nil {
            return source.replacingOccurrences(
                of: pattern,
                with: calculationProperties,
                options: .regularExpression
            )
        }
        let laterElementPattern = "<" + optionalNamespacePrefixPattern
            + #"(?:oleSize|customWorkbookViews|pivotCaches|smartTagPr|smartTagTypes|webPublishing|fileRecoveryPr|webPublishObjects|extLst)\b"#
        if let range = source.range(
            of: laterElementPattern,
            options: .regularExpression
        ) {
            return source.replacingCharacters(
                in: range.lowerBound..<range.lowerBound,
                with: calculationProperties
            )
        }
        let closingPattern = "</" + optionalNamespacePrefixPattern
            + "workbook\\s*>"
        guard let closingRange = lastMatchRange(
            of: closingPattern,
            in: source
        ) else {
            return source
        }
        return source.replacingCharacters(
            in: closingRange.lowerBound..<closingRange.lowerBound,
            with: calculationProperties
        )
    }

    private static func serializedCell(
        address: ExcelCellAddress,
        edit: ExcelCellEdit,
        namespacePrefix: String
    ) -> String {
        let style = edit.styleIndex.map { " s=\"\($0)\"" } ?? ""
        let cellStart = "<\(namespacePrefix)c r=\"\(address.reference)\"\(style)"
        switch edit.input {
        case .blank:
            return cellStart + "/>"
        case .text(let value):
            let escaped = escapeXML(value)
            let preserve = value.first?.isWhitespace == true
                || value.last?.isWhitespace == true
                ? " xml:space=\"preserve\""
                : ""
            return cellStart + " t=\"inlineStr\">"
                + "<\(namespacePrefix)is><\(namespacePrefix)t\(preserve)>"
                + escaped
                + "</\(namespacePrefix)t></\(namespacePrefix)is>"
                + "</\(namespacePrefix)c>"
        case .number(let value):
            return cellStart + "><\(namespacePrefix)v>"
                + escapeXML(value)
                + "</\(namespacePrefix)v></\(namespacePrefix)c>"
        case .boolean(let value):
            return cellStart + " t=\"b\"><\(namespacePrefix)v>"
                + String(value ? 1 : 0)
                + "</\(namespacePrefix)v></\(namespacePrefix)c>"
        case .error(let value):
            return cellStart + " t=\"e\"><\(namespacePrefix)v>"
                + escapeXML(value)
                + "</\(namespacePrefix)v></\(namespacePrefix)c>"
        case .formula(let formula):
            let type = edit.cachedType.map {
                " t=\"" + escapeXML($0) + "\""
            } ?? ""
            let formulaAttributes = edit.formulaSpillRange.map {
                " t=\"array\" ref=\"" + escapeXML($0.reference)
                    + "\" aca=\"1\""
            } ?? ""
            let cached = edit.cachedValue.map {
                "<\(namespacePrefix)v>" + escapeXML($0)
                    + "</\(namespacePrefix)v>"
            } ?? ""
            return cellStart + type + "><\(namespacePrefix)f"
                + formulaAttributes + ">"
                + escapeXML(formula)
                + "</\(namespacePrefix)f>" + cached
                + "</\(namespacePrefix)c>"
        }
    }

    private static func replacingStyle(
        in cellXML: String,
        with styleIndex: Int?
    ) -> String {
        var result = cellXML
        let pattern = #"\ss\s*=\s*[\"'][^\"']*[\"']"#
        if let styleIndex {
            if result.range(
                of: pattern,
                options: .regularExpression
            ) != nil {
                result = result.replacingOccurrences(
                    of: pattern,
                    with: " s=\"\(styleIndex)\"",
                    options: .regularExpression
                )
            } else if let openingClose = result.firstIndex(of: ">") {
                var insertion = openingClose
                if result[result.startIndex..<openingClose].hasSuffix("/") {
                    insertion = result.index(before: openingClose)
                }
                result.insert(
                    contentsOf: " s=\"\(styleIndex)\"",
                    at: insertion
                )
            }
        } else {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        return result
    }

    private static func insert(
        _ cellXML: String,
        address: ExcelCellAddress,
        intoRowXML rowXML: String,
        namespacePrefix: String
    ) throws -> String {
        if rowXML.hasSuffix("/>") {
            guard let close = rowXML.range(of: "/>", options: .backwards) else {
                return rowXML
            }
            return String(rowXML[..<close.lowerBound])
                + ">" + cellXML + "</\(namespacePrefix)row>"
        }
        let cellRegex = try NSRegularExpression(
            pattern: "<" + optionalNamespacePrefixPattern
                + "c\\b[^>]*\\br\\s*=\\s*[\"']([^\"']+)[\"'][^>]*"
                + "(?:/>|>[\\s\\S]*?</"
                + optionalNamespacePrefixPattern
                + "c\\s*>)"
        )
        let range = NSRange(rowXML.startIndex..., in: rowXML)
        for match in cellRegex.matches(in: rowXML, range: range) {
            guard match.numberOfRanges > 1,
                  let referenceRange = Range(match.range(at: 1), in: rowXML),
                  let existingAddress = ExcelCellAddress(
                      String(rowXML[referenceRange])
                  ),
                  existingAddress.column > address.column,
                  let insertion = Range(match.range(at: 0), in: rowXML) else {
                continue
            }
            return rowXML.replacingCharacters(
                in: insertion.lowerBound..<insertion.lowerBound,
                with: cellXML
            )
        }
        let closingPattern = "</" + optionalNamespacePrefixPattern
            + "row\\s*>"
        guard let close = lastMatchRange(
            of: closingPattern,
            in: rowXML
        ) else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        return rowXML.replacingCharacters(
            in: close.lowerBound..<close.lowerBound,
            with: cellXML
        )
    }

    private static func insert(
        _ rowXML: String,
        rowNumber: Int,
        intoWorksheetXML source: String
    ) throws -> String {
        let rowRegex = try NSRegularExpression(
            pattern: "<" + optionalNamespacePrefixPattern
                + "row\\b[^>]*\\br\\s*=\\s*[\"']([0-9]+)[\"'][^>]*"
                + "(?:/>|>[\\s\\S]*?</"
                + optionalNamespacePrefixPattern
                + "row\\s*>)"
        )
        let fullRange = NSRange(source.startIndex..., in: source)
        for match in rowRegex.matches(in: source, range: fullRange) {
            guard match.numberOfRanges > 1,
                  let numberRange = Range(match.range(at: 1), in: source),
                  let existingRow = Int(source[numberRange]),
                  existingRow > rowNumber,
                  let insertion = Range(match.range(at: 0), in: source) else {
                continue
            }
            return source.replacingCharacters(
                in: insertion.lowerBound..<insertion.lowerBound,
                with: rowXML
            )
        }
        let selfClosingPattern = "<" + optionalNamespacePrefixPattern
            + "sheetData\\b[^>]*/\\s*>"
        if let selfClosing = source.range(
            of: selfClosingPattern,
            options: .regularExpression
        ) {
            let prefix = namespacePrefix(
                forRootElement: "worksheet",
                in: source
            )
            return source.replacingCharacters(
                in: selfClosing,
                with: "<\(prefix)sheetData>" + rowXML
                    + "</\(prefix)sheetData>"
            )
        }
        let closingPattern = "</" + optionalNamespacePrefixPattern
            + "sheetData\\s*>"
        guard let close = lastMatchRange(
            of: closingPattern,
            in: source
        ) else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        return source.replacingCharacters(
            in: close.lowerBound..<close.lowerBound,
            with: rowXML
        )
    }

    private static let optionalNamespacePrefixPattern =
        "(?:[A-Za-z_][A-Za-z0-9_.-]*:)?"

    private static func namespacePrefix(
        forRootElement name: String,
        in source: String
    ) -> String {
        let pattern = "<([A-Za-z_][A-Za-z0-9_.-]*:)?"
            + NSRegularExpression.escapedPattern(for: name)
            + "\\b"
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

    private static func lastMatchRange(
        of pattern: String,
        in source: String
    ) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.matches(
                  in: source,
                  range: NSRange(source.startIndex..., in: source)
              ).last else {
            return nil
        }
        return Range(match.range, in: source)
    }
}

private nonisolated func parseExcelXML(
    _ data: Data,
    delegate: XMLParserDelegate
) throws {
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = true
    parser.delegate = delegate
    guard parser.parse() else {
        throw ExcelWorkbookDocumentError.invalidWorkbook
    }
}

private nonisolated func localExcelXMLName(_ name: String) -> String {
    name.split(separator: ":").last.map(String.init) ?? name
}

private nonisolated func excelXMLBoolean(_ value: String?) -> Bool {
    guard let value else { return false }
    return value == "1" || value.caseInsensitiveCompare("true") == .orderedSame
}

nonisolated func normalizedPartPath(
    _ rawTarget: String,
    relativeTo sourcePart: String
) -> String? {
    let decoded = rawTarget.removingPercentEncoding ?? rawTarget
    let candidate: String
    if decoded.hasPrefix("/") {
        candidate = String(decoded.dropFirst())
    } else {
        let directory = sourcePart.split(separator: "/")
            .dropLast()
            .joined(separator: "/")
        candidate = directory.isEmpty
            ? decoded
            : directory + "/" + decoded
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
            guard !components.isEmpty else {
                return nil
            }
            components.removeLast()
        default:
            components.append(component)
        }
    }
    let normalized = components.joined(separator: "/")
    return isSafeArchivePath(normalized) ? normalized : nil
}

private nonisolated func isSafeArchivePath(_ path: String) -> Bool {
    !path.hasPrefix("/")
        && !path.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .contains("..")
}

private nonisolated func escapeXML(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}
