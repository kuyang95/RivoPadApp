import Foundation

/// A mechanical projection of worksheet contents. Interpretation belongs to
/// the model; accessibility labels and categorical summaries stay on device.
public nonisolated struct ExcelAISourceData: Encodable {
    public struct Cell: Encodable {
        public let sheetID: String
        public let address: String
        public let value: String
        public let rawValue: String?
        public let type: String
        public let formula: String?
    
    public init(sheetID: String, address: String, value: String, rawValue: String? = nil, type: String, formula: String? = nil) {
        self.sheetID = sheetID
        self.address = address
        self.value = value
        self.rawValue = rawValue
        self.type = type
        self.formula = formula
    }
}
    public struct Sheet: Encodable {
        public let id: String
        public let name: String
        public let mergedRanges: [String]
        public let contextWasTruncated: Bool
    
    public init(id: String, name: String, mergedRanges: [String], contextWasTruncated: Bool) {
        self.id = id
        self.name = name
        self.mergedRanges = mergedRanges
        self.contextWasTruncated = contextWasTruncated
    }
}
    public struct Region: Encodable {
        public struct Column: Encodable {
            public let number: Int
            public let letter: String
            public let title: String?
        
    public init(number: Int, letter: String, title: String? = nil) {
        self.number = number
        self.letter = letter
        self.title = title
    }
}
        public let id: String
        public let sheetID: String
        public let range: String
        public let headerRow: Int?
        public let columns: [Column]
        public let dataRows: [Int]
        public let dataRowsWereTruncated: Bool
        public let isNativeTable: Bool
    
    public init(id: String, sheetID: String, range: String, headerRow: Int? = nil, columns: [Column], dataRows: [Int], dataRowsWereTruncated: Bool, isNativeTable: Bool) {
        self.id = id
        self.sheetID = sheetID
        self.range = range
        self.headerRow = headerRow
        self.columns = columns
        self.dataRows = dataRows
        self.dataRowsWereTruncated = dataRowsWereTruncated
        self.isNativeTable = isNativeTable
    }
}
    public static let maximumCells = 1_500
    public static let maximumCharacters = 80_000
    public let sheets: [Sheet]
    public let cells: [Cell]
    public let regions: [Region]
    public var contextWasTruncated: Bool { sheets.contains { $0.contextWasTruncated } }

    public init(snapshot: ExcelAIWorkbookSnapshot, includeWorkbook: Bool = false) {
        let sourceSheets = includeWorkbook ? (snapshot.localWorkbook?.sheets ?? [])
            : [snapshot.localQuerySheet].compactMap { $0 }
        var sheets: [Sheet] = []
        var cells: [Cell] = []
        var regions: [Region] = []
        // Share the budget across requested sheets rather than starving the
        // later sheets. A row is included whole or omitted whole.
        let cellLimit = Self.maximumCells / max(1, sourceSheets.count)
        let characterLimit = Self.maximumCharacters / max(1, sourceSheets.count)
        for sheet in sourceSheets {
            let original = sheet.cells.values.filter { !$0.displayValue.isEmpty || $0.formula?.isEmpty == false }
            let rows = Dictionary(grouping: original, by: { $0.address.row })
            var count = 0
            var characters = 0
            var selected: [Cell] = []
            // Large-file retrieval has already chosen original rows; retain
            // those rows without summarizing or separating their cell values.
            let requestedRows = sheet.partPath == snapshot.sheetPartPath ? snapshot.retrievedRows : []
            var requested = Set<Int>()
            let priority = requestedRows.filter { requested.insert($0).inserted } + rows.keys.filter { !requested.contains($0) }.sorted()
            for row in priority {
                let rowCells = (rows[row] ?? []).sorted { $0.address < $1.address }
                let rowCharacters = rowCells.reduce(0) { $0 + $1.rawValue.count + $1.displayValue.count + ($1.formula?.count ?? 0) }
                guard count + rowCells.count <= cellLimit, characters + rowCharacters <= characterLimit else { break }
                count += rowCells.count
                characters += rowCharacters
                selected += rowCells.map { .init(sheetID: sheet.partPath, address: $0.address.reference,
                    value: $0.displayValue, rawValue: $0.rawValue == $0.displayValue ? nil : $0.rawValue,
                    type: $0.cellType ?? "n", formula: $0.formula) }
            }
            selected.sort { ExcelCellAddress($0.address)! < ExcelCellAddress($1.address)! }
            cells += selected
            sheets.append(.init(id: sheet.partPath, name: sheet.name, mergedRanges: sheet.mergedRanges.map(\.reference),
                contextWasTruncated: count < original.count || sheet.isWindowed || sheet.didTruncate))
            regions += ExcelAccessibilityAnalyzer.regions(in: sheet).map { region in
                .init(id: region.id, sheetID: sheet.partPath, range: region.range.reference,
                    headerRow: region.headerRow,
                    columns: region.columns.map { .init(number: $0.column, letter: ExcelCellAddress.columnName($0.column),
                        title: region.isNativeTable ? $0.title : nil) },
                    dataRows: Array(ExcelAIQueryData.dataRows(region.rowNumbers, regionID: region.id, sheet: sheet).prefix(Self.maximumCells)),
                    dataRowsWereTruncated: region.rowNumbers.count > Self.maximumCells,
                    isNativeTable: region.isNativeTable)
            }
        }
        // Manually constructed snapshots and read-only imports may not carry
        // the local worksheet. Preserve their literal cells as a fallback.
        if sourceSheets.isEmpty {
            cells = snapshot.cells.map { .init(sheetID: snapshot.sheetPartPath, address: $0.address,
                value: $0.value, rawValue: nil, type: "unknown", formula: $0.formula) }
            sheets = [.init(id: snapshot.sheetPartPath, name: snapshot.sheetName,
                mergedRanges: snapshot.mergedRanges, contextWasTruncated: snapshot.contextWasTruncated)]
            regions = snapshot.regions.map { region in
                .init(id: region.id, sheetID: snapshot.sheetPartPath, range: region.range, headerRow: region.headerRow,
                    columns: region.columns.map { .init(number: $0.number, letter: $0.letter,
                        title: region.isNativeTable ? $0.title : nil) },
                    dataRows: Array(region.dataRows.prefix(Self.maximumCells)),
                    dataRowsWereTruncated: region.dataRows.count > Self.maximumCells, isNativeTable: region.isNativeTable)
            }
        }
        self.cells = cells
        self.sheets = sheets
        self.regions = regions
    }
}

public nonisolated struct ExcelAIModelWorksheet: Encodable {
    public let snapshot: ExcelAIWorkbookSnapshot
    public let source: ExcelAISourceData

    private enum CodingKeys: String, CodingKey {
        case workbookName, sheetName, sheetPartPath, selectedCell, supportsEdits, worksheetIsProtected
        case capabilities, supportsLocalQueries, workbookContext, cells, sheets, regions, contextWasTruncated
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(snapshot.workbookName, forKey: .workbookName)
        try c.encode(snapshot.sheetName, forKey: .sheetName)
        try c.encode(snapshot.sheetPartPath, forKey: .sheetPartPath)
        try c.encodeIfPresent(snapshot.selectedCell, forKey: .selectedCell)
        try c.encode(snapshot.supportsEdits, forKey: .supportsEdits)
        try c.encode(snapshot.worksheetIsProtected, forKey: .worksheetIsProtected)
        try c.encode(snapshot.capabilities, forKey: .capabilities)
        try c.encode(snapshot.supportsLocalQueries, forKey: .supportsLocalQueries)
        try c.encodeIfPresent(snapshot.workbookContext, forKey: .workbookContext)
        try c.encode(source.cells, forKey: .cells)
        try c.encode(source.sheets, forKey: .sheets)
        try c.encode(source.regions, forKey: .regions)
        try c.encode(source.contextWasTruncated, forKey: .contextWasTruncated)
    }

    public init(snapshot: ExcelAIWorkbookSnapshot, source: ExcelAISourceData) {
        self.snapshot = snapshot
        self.source = source
    }
}
