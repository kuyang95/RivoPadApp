import Foundation

public nonisolated enum ExcelAICommandCapability:
    String,
    CaseIterable,
    Codable,
    Sendable
{
    case setCellValue
    case appendRow
    case createTable
    case setNumberFormat
    case setDropdown
    case removeDropdown
    case setConditionalFormatting
    case removeConditionalFormatting
    case workbookOperations
}

public nonisolated struct ExcelAIWorkbookSnapshot: Encodable, Sendable {
    public struct Region: Encodable, Sendable {
        public struct Column: Encodable, Sendable {
            public let number: Int
            public let letter: String
            public let title: String
        
    public init(number: Int, letter: String, title: String) {
        self.number = number
        self.letter = letter
        self.title = title
    }
}

        public let id: String
        public let name: String
        public let range: String
        public let headerRow: Int?
        public let columns: [Column]
        public let dataRows: [Int]
        public let isNativeTable: Bool
    
    public init(id: String, name: String, range: String, headerRow: Int? = nil, columns: [Column], dataRows: [Int], isNativeTable: Bool) {
        self.id = id
        self.name = name
        self.range = range
        self.headerRow = headerRow
        self.columns = columns
        self.dataRows = dataRows
        self.isNativeTable = isNativeTable
    }
}

    public struct Cell: Encodable, Sendable {
        public let address: String
        public let row: Int
        public let column: Int
        public let header: String?
        public let value: String
        public let formula: String?
        public let numberFormat: String?
    
    public init(address: String, row: Int, column: Int, header: String? = nil, value: String, formula: String? = nil, numberFormat: String? = nil) {
        self.address = address
        self.row = row
        self.column = column
        self.header = header
        self.value = value
        self.formula = formula
        self.numberFormat = numberFormat
    }
}

    public let workbookName: String
    public let sheetName: String
    public let sheetPartPath: String
    public let selectedCell: String?
    public let supportsEdits: Bool
    public let worksheetIsProtected: Bool
    public let capabilities: [ExcelAICommandCapability]
    public let searchedWholeSheet: Bool
    public let searchTerms: [String]
    public let searchResultRowCount: Int
    public let searchResultsWereTruncated: Bool
    public let retrievedRows: [Int]
    public let regions: [Region]
    public let mergedRanges: [String]
    public let cells: [Cell]
    public let contextWasTruncated: Bool
    public let revision: String
    public var valueGroups: [ExcelAIValueGroup] = []
    public var supportsLocalQueries = false
    // Keep the complete sheet on device; the model receives only the existing
    // bounded context and a capability flag for planning a read-only query.
    public var localQuerySheet: ExcelWorksheet? = nil
    public var workbookContext: ExcelAIWorkbookContext? = nil
    public var localWorkbook: ExcelWorkbook? = nil

    private enum CodingKeys: String, CodingKey {
        case workbookName, sheetName, sheetPartPath, selectedCell, supportsEdits
        case worksheetIsProtected, capabilities, searchedWholeSheet, searchTerms
        case searchResultRowCount, searchResultsWereTruncated, retrievedRows
        case regions, mergedRanges, cells, contextWasTruncated, revision, valueGroups
        case supportsLocalQueries
        case workbookContext
    }

    public func region(id: String) -> Region? {
        regions.first { $0.id == id }
    }

    public func region(
        containingRow row: Int,
        column: Int
    ) -> Region? {
        let address = ExcelCellAddress(row: row, column: column)
        return regions.first {
            let rowIsEditable: Bool
            if $0.isNativeTable,
               let headerRow = $0.headerRow {
                rowIsEditable = row > headerRow
                    && (ExcelCellRange($0.range)?.contains(address) == true)
            } else {
                rowIsEditable = $0.dataRows.contains(row)
            }
            return rowIsEditable && $0.columns.contains(where: {
                    $0.number == column
                })
        }
    }

    public func cell(row: Int, column: Int) -> Cell? {
        cells.first {
            $0.row == row && $0.column == column
        }
    }

    /// Maps a cell inside a merged range to the range's anchor
    /// (top-left) cell, mirroring `ExcelWorksheet.canonicalAddress`.
    public func canonicalAddress(row: Int, column: Int) -> ExcelCellAddress {
        let address = ExcelCellAddress(row: row, column: column)
        for reference in mergedRanges {
            if let range = ExcelCellRange(reference),
               range.contains(address) {
                return range.start
            }
        }
        return address
    }

    public init(workbookName: String, sheetName: String, sheetPartPath: String, selectedCell: String? = nil, supportsEdits: Bool, worksheetIsProtected: Bool, capabilities: [ExcelAICommandCapability], searchedWholeSheet: Bool, searchTerms: [String], searchResultRowCount: Int, searchResultsWereTruncated: Bool, retrievedRows: [Int], regions: [Region], mergedRanges: [String], cells: [Cell], contextWasTruncated: Bool, revision: String, valueGroups: [ExcelAIValueGroup] = [], supportsLocalQueries: Bool = false, localQuerySheet: ExcelWorksheet? = nil, workbookContext: ExcelAIWorkbookContext? = nil, localWorkbook: ExcelWorkbook? = nil) {
        self.workbookName = workbookName
        self.sheetName = sheetName
        self.sheetPartPath = sheetPartPath
        self.selectedCell = selectedCell
        self.supportsEdits = supportsEdits
        self.worksheetIsProtected = worksheetIsProtected
        self.capabilities = capabilities
        self.searchedWholeSheet = searchedWholeSheet
        self.searchTerms = searchTerms
        self.searchResultRowCount = searchResultRowCount
        self.searchResultsWereTruncated = searchResultsWereTruncated
        self.retrievedRows = retrievedRows
        self.regions = regions
        self.mergedRanges = mergedRanges
        self.cells = cells
        self.contextWasTruncated = contextWasTruncated
        self.revision = revision
        self.valueGroups = valueGroups
        self.supportsLocalQueries = supportsLocalQueries
        self.localQuerySheet = localQuerySheet
        self.workbookContext = workbookContext
        self.localWorkbook = localWorkbook
    }
}

public nonisolated enum ExcelAISnapshotBuilder {
    public static let maximumContextCells = 1_500

    public static func make(
        workbookName: String,
        workbook: ExcelWorkbook,
        selectedSheetIndex: Int,
        selectedAddress: ExcelCellAddress?,
        supportsEdits: Bool = true,
        searchedWholeSheet: Bool = false,
        searchTerms: [String] = [],
        searchResultRowCount: Int = 0,
        searchResultsWereTruncated: Bool = false,
        retrievedRows: [Int] = [],
        selectedRange: ExcelCellRange? = nil,
        selectedDrawingID: String? = nil
    ) -> ExcelAIWorkbookSnapshot? {
        guard workbook.sheets.indices.contains(selectedSheetIndex) else {
            return nil
        }
        let sheet = workbook.sheets[selectedSheetIndex]
        let accessibleRegions = ExcelAccessibilityAnalyzer.regions(in: sheet)
        let regions = accessibleRegions.map { region in
            ExcelAIWorkbookSnapshot.Region(
                id: region.id,
                name: region.name,
                range: region.range.reference,
                headerRow: region.headerRow,
                columns: region.columns.map { column in
                    .init(
                        number: column.column,
                        letter: ExcelCellAddress.columnName(column.column),
                        title: column.title
                    )
                },
                dataRows: ExcelAIQueryData.dataRows(region.rowNumbers, regionID: region.id, sheet: sheet),
                isNativeTable: region.isNativeTable
            )
        }
        let headerByAddress = Dictionary(
            uniqueKeysWithValues: accessibleRegions.flatMap { region in
                region.rowNumbers.flatMap { row in
                    region.columns.map { column in
                        (
                            ExcelCellAddress(
                                row: row,
                                column: column.column
                            ),
                            column.title
                        )
                    }
                }
            }
        )
        let allCells = sheet.cells.values
            .filter {
                !$0.displayValue.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty || $0.formula?.isEmpty == false
            }
            .sorted { $0.address < $1.address }
        let preferredRowRank = Dictionary(
            uniqueKeysWithValues: retrievedRows.enumerated().map {
                ($0.element, $0.offset)
            }
        )
        let prioritizedCells = allCells.sorted { lhs, rhs in
            let lhsRank = preferredRowRank[lhs.address.row]
            let rhsRank = preferredRowRank[rhs.address.row]
            switch (lhsRank, rhsRank) {
            case let (.some(left), .some(right)):
                if left != right {
                    return left < right
                }
                return lhs.address < rhs.address
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.address < rhs.address
            }
        }
        let selectedCells = Array(
            prioritizedCells.prefix(maximumContextCells)
        ).sorted { $0.address < $1.address }
        let cells = selectedCells.map { cell in
            ExcelAIWorkbookSnapshot.Cell(
                address: cell.address.reference,
                row: cell.address.row,
                column: cell.address.column,
                header: headerByAddress[cell.address],
                value: cell.displayValue,
                formula: cell.formula,
                numberFormat: ExcelNumberFormat.matching(
                    workbook.style(at: cell.styleIndex)
                )?.rawValue
            )
        }
        return ExcelAIWorkbookSnapshot(
            workbookName: workbookName,
            sheetName: sheet.name,
            sheetPartPath: sheet.partPath,
            selectedCell: selectedAddress?.reference,
            supportsEdits: supportsEdits,
            worksheetIsProtected: sheet.protection.isEnabled,
            capabilities: ExcelAICommandCapability.allCases,
            searchedWholeSheet: searchedWholeSheet,
            searchTerms: searchTerms,
            searchResultRowCount: searchResultRowCount,
            searchResultsWereTruncated: searchResultsWereTruncated,
            retrievedRows: retrievedRows,
            regions: regions,
            mergedRanges: sheet.mergedRanges.map(\.reference),
            cells: cells,
            contextWasTruncated: sheet.isWindowed
                || allCells.count > selectedCells.count,
            revision: ExcelAIWorkbookContext.revision(workbook: workbook, selectedSheetIndex: selectedSheetIndex, selectedRange: selectedRange ?? selectedAddress.map { .init(start: $0, end: $0) }, selectedDrawingID: selectedDrawingID),
            valueGroups: ExcelAIValueGroup.make(sheet: sheet, regions: accessibleRegions),
            supportsLocalQueries: !sheet.isWindowed && !sheet.didTruncate,
            localQuerySheet: sheet.isWindowed || sheet.didTruncate ? nil : sheet,
            workbookContext: ExcelAIWorkbookContext.make(workbook: workbook, selectedSheetIndex: selectedSheetIndex, selectedRange: selectedRange ?? selectedAddress.map { .init(start: $0, end: $0) }, selectedDrawingID: selectedDrawingID, supportsEdits: supportsEdits),
            localWorkbook: workbook.sheets.contains(where: { $0.isWindowed || $0.didTruncate }) ? nil : workbook
        )
    }

    private static func revision(
        sheet: ExcelWorksheet,
        regions: [ExcelAccessibleRegion]
    ) -> String {
        var value = "\(sheet.partPath)|\(sheet.maximumRow)|\(sheet.maximumColumn)"
        for cell in sheet.cells.values.sorted(by: { $0.address < $1.address }) {
            value += "|\(cell.address.reference):\(cell.editText):\(cell.styleIndex ?? -1)"
        }
        for region in regions {
            value += "|\(region.id):\(region.range.reference)"
        }
        value += "|protected:\(sheet.protection.isEnabled)"
        for rule in sheet.dataValidations {
            value += "|validation:\(rule.type ?? ""):"
                + rule.ranges.map(\.reference).joined(separator: ",")
                + ":\(rule.formula1 ?? "")"
        }
        for block in sheet.conditionalFormatting {
            value += "|conditional:"
                + block.ranges.map(\.reference).joined(separator: ",")
            for rule in block.rules {
                value += ":\(rule.kind.rawValue):"
                    + "\(rule.comparisonValue):"
                    + "\(rule.differentialStyleIndex)"
            }
        }

        // Stable FNV-1a is sufficient here: this token only detects whether
        // the in-memory sheet changed while an AI proposal was pending.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

public nonisolated enum ExcelLargeAIQueryTokenizer {
    private static let stopWords: Set<String> = [
        "ai", "excel", "xlsx", "값", "것", "관련", "검색", "검색해줘",
        "검색해주세요", "그", "내역", "데이터", "문서", "뭐야", "무엇",
        "보여줘", "보여주세요", "시트", "알려줘", "알려주세요", "어디",
        "어떤", "엑셀", "에서", "있는", "좀", "중", "찾아", "찾아줘",
        "찾아주세요", "표", "해줘", "해주세요", "행", "항목",
    ]
    private static let koreanParticles = [
        "으로", "에서", "에게", "부터", "까지", "처럼", "보다", "하고",
        "과", "와", "을", "를", "은", "는", "이", "가", "의", "에",
        "로", "도", "만",
    ]

    public static func terms(in request: String, maximumCount: Int = 8) -> [String] {
        guard maximumCount > 0 else {
            return []
        }
        let folded = request.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        var rawTokens = [String]()
        var current = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar)
                || scalar == "-"
                || scalar == "_"
                || scalar == "." {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                rawTokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            rawTokens.append(current)
        }

        var result = [String]()
        var seen = Set<String>()
        for rawToken in rawTokens {
            var token = rawToken.lowercased()
            for particle in koreanParticles where token.hasSuffix(particle) {
                guard token.count > particle.count + 1 else {
                    continue
                }
                token.removeLast(particle.count)
                break
            }
            guard token.count >= 2,
                  !stopWords.contains(token),
                  seen.insert(token).inserted else {
                continue
            }
            result.append(token)
            if result.count == maximumCount {
                break
            }
        }
        return result
    }
}

public nonisolated struct ExcelAIChatTurn: Encodable, Sendable {
    public let role: String
    public let text: String
    public var query: ExcelAIReadQuery? = nil

    public init(role: String, text: String, query: ExcelAIReadQuery? = nil) {
        self.role = role
        self.text = text
        self.query = query
    }
}

public nonisolated struct ExcelAICommandPlan: Decodable, Sendable {
    public enum Intent: String, Decodable, Sendable {
        case answer
        case clarify
        case edit
    }

    public struct Edit: Decodable, Hashable, Sendable {
        public let row: Int
        public let column: Int
        public let newValue: String
    
    public init(row: Int, column: Int, newValue: String) {
        self.row = row
        self.column = column
        self.newValue = newValue
    }
}

    public struct ColumnValue: Decodable, Hashable, Sendable {
        public let column: Int
        public let newValue: String
    
    public init(column: Int, newValue: String) {
        self.column = column
        self.newValue = newValue
    }
}

    public struct AppendedRow: Decodable, Hashable, Sendable {
        public let regionID: String
        public let values: [ColumnValue]
    
    public init(regionID: String, values: [ColumnValue]) {
        self.regionID = regionID
        self.values = values
    }
}

    public struct CreatedTable: Decodable, Hashable, Sendable {
        public let startRow: Int
        public let startColumn: Int
        public let headers: [String]
        public let blankRowCount: Int

        public init(
            startRow: Int,
            startColumn: Int,
            headers: [String],
            blankRowCount: Int = 5
        ) {
            self.startRow = startRow
            self.startColumn = startColumn
            self.headers = headers
            self.blankRowCount = blankRowCount
        }

        private enum CodingKeys: String, CodingKey {
            case startRow
            case startColumn
            case headers
            case blankRowCount
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            startRow = try container.decode(Int.self, forKey: .startRow)
            startColumn = try container.decode(Int.self, forKey: .startColumn)
            headers = try container.decode([String].self, forKey: .headers)
            blankRowCount = try container.decodeIfPresent(
                Int.self,
                forKey: .blankRowCount
            ) ?? 5
        }
    }

    public struct Action: Decodable, Hashable, Sendable {
        public enum Kind: String, Decodable, Sendable {
            case setNumberFormat
            case setDropdown
            case removeDropdown
            case setConditionalFormatting
            case removeConditionalFormatting
        }

        public struct Target: Decodable, Hashable, Sendable {
            public enum Scope: String, Decodable, Sendable {
                case cell
                case column
            }

            public let scope: Scope
            public let regionID: String
            public let row: Int?
            public let column: Int
        
    public init(scope: Scope, regionID: String, row: Int? = nil, column: Int) {
        self.scope = scope
        self.regionID = regionID
        self.row = row
        self.column = column
    }
}

        public let type: Kind
        public let target: Target
        public let format: String?
        public let values: [String]?
        public let allowsBlank: Bool?
        public let condition: String?
        public let comparisonValue: String?
        public let highlight: String?

        public init(
            type: Kind,
            target: Target,
            format: String? = nil,
            values: [String]? = nil,
            allowsBlank: Bool? = nil,
            condition: String? = nil,
            comparisonValue: String? = nil,
            highlight: String? = nil
        ) {
            self.type = type
            self.target = target
            self.format = format
            self.values = values
            self.allowsBlank = allowsBlank
            self.condition = condition
            self.comparisonValue = comparisonValue
            self.highlight = highlight
        }
    }

    public let intent: Intent
    public let assistantMessage: String
    public let edits: [Edit]
    public let appendedRows: [AppendedRow]
    public let createdTables: [CreatedTable]
    public let actions: [Action]
    public let referencedCells: [String]
    public let referencedGroupIDs: [String]
    public let countGroupID: String?
    public var query: ExcelAIReadQuery?
    public let workbookOperations: [ExcelAIWorkbookOperation]

    public init(
        intent: Intent,
        assistantMessage: String,
        edits: [Edit],
        appendedRows: [AppendedRow],
        createdTables: [CreatedTable] = [],
        actions: [Action] = [],
        referencedCells: [String] = [],
        referencedGroupIDs: [String] = [],
        countGroupID: String? = nil,
        query: ExcelAIReadQuery? = nil,
        workbookOperations: [ExcelAIWorkbookOperation] = []
    ) {
        self.intent = intent
        self.assistantMessage = assistantMessage
        self.edits = edits
        self.appendedRows = appendedRows
        self.createdTables = createdTables
        self.actions = actions
        self.referencedCells = referencedCells
        self.referencedGroupIDs = referencedGroupIDs
        self.countGroupID = countGroupID
        self.query = query
        self.workbookOperations = workbookOperations
    }

    private enum CodingKeys: String, CodingKey {
        case intent
        case assistantMessage
        case edits
        case appendedRows
        case createdTables
        case actions
        case referencedCells, referencedGroupIDs, countGroupID, query
        case workbookOperations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        intent = try container.decode(Intent.self, forKey: .intent)
        assistantMessage = try container.decode(
            String.self,
            forKey: .assistantMessage
        )
        edits = try container.decodeIfPresent(
            [Edit].self,
            forKey: .edits
        ) ?? []
        appendedRows = try container.decodeIfPresent(
            [AppendedRow].self,
            forKey: .appendedRows
        ) ?? []
        createdTables = try container.decodeIfPresent(
            [CreatedTable].self,
            forKey: .createdTables
        ) ?? []
        actions = try container.decodeIfPresent(
            [Action].self,
            forKey: .actions
        ) ?? []
        referencedCells = try container.decodeIfPresent([String].self, forKey: .referencedCells) ?? []
        referencedGroupIDs = try container.decodeIfPresent([String].self, forKey: .referencedGroupIDs) ?? []
        countGroupID = try container.decodeIfPresent(String.self, forKey: .countGroupID)
        query = try container.decodeIfPresent(ExcelAIReadQuery.self, forKey: .query)
        workbookOperations = try container.decodeIfPresent([ExcelAIWorkbookOperation].self, forKey: .workbookOperations) ?? []
    }
}

public nonisolated enum ExcelAIValidatedAction: Hashable, Sendable {
    case setNumberFormat(
        addresses: [ExcelCellAddress],
        format: ExcelNumberFormat
    )
    case setDropdown(
        addresses: [ExcelCellAddress],
        values: [String],
        allowsBlank: Bool
    )
    case removeDropdown(addresses: [ExcelCellAddress])
    case setConditionalFormatting(
        addresses: [ExcelCellAddress],
        kind: ExcelConditionalRuleKind,
        comparisonValue: String,
        highlight: ExcelConditionalHighlight
    )
    case removeConditionalFormatting(addresses: [ExcelCellAddress])

    public var addresses: [ExcelCellAddress] {
        switch self {
        case .setNumberFormat(let addresses, _),
             .setDropdown(let addresses, _, _),
             .removeDropdown(let addresses),
             .setConditionalFormatting(let addresses, _, _, _),
             .removeConditionalFormatting(let addresses):
            return addresses
        }
    }
}

public nonisolated struct ExcelAIValidatedPlan: Identifiable, Sendable {
    public let id = UUID()
    public let assistantMessage: String
    public let edits: [ExcelAICommandPlan.Edit]
    public let appendedRows: [ExcelAICommandPlan.AppendedRow]
    public let createdTables: [ExcelAICommandPlan.CreatedTable]
    public let actions: [ExcelAIValidatedAction]
    public let sheetPartPath: String
    public let sourceRevision: String
    public let previewLines: [String]
    /// Cells the user named explicitly in the request (e.g. "H6에 Tax"),
    /// which may be written even when they lie outside every region.
    public var explicitAddresses: Set<ExcelCellAddress> = []
    public var workbookOperations: [ExcelAIWorkbookOperation] = []

    public var changeCount: Int {
        edits.count
            + appendedRows.reduce(0) { $0 + $1.values.count }
            + createdTables.reduce(0) { $0 + $1.headers.count }
            + actions.reduce(0) { $0 + $1.addresses.count }
            + workbookOperations.count
    }

    public init(assistantMessage: String, edits: [ExcelAICommandPlan.Edit], appendedRows: [ExcelAICommandPlan.AppendedRow], createdTables: [ExcelAICommandPlan.CreatedTable], actions: [ExcelAIValidatedAction], sheetPartPath: String, sourceRevision: String, previewLines: [String], explicitAddresses: Set<ExcelCellAddress> = [], workbookOperations: [ExcelAIWorkbookOperation] = []) {
        self.assistantMessage = assistantMessage
        self.edits = edits
        self.appendedRows = appendedRows
        self.createdTables = createdTables
        self.actions = actions
        self.sheetPartPath = sheetPartPath
        self.sourceRevision = sourceRevision
        self.previewLines = previewLines
        self.explicitAddresses = explicitAddresses
        self.workbookOperations = workbookOperations
    }
}

public nonisolated enum ExcelAICommandValidationError: LocalizedError {
    case invalidResponse
    case invalidAction
    case tooManyChanges
    case invalidTarget
    case editingUnavailable
    case protectedWorksheet

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return DocumentEngineLocalization.string(
                "AI 수정안을 이해하지 못했습니다. 지시를 조금 더 구체적으로 입력해 주세요."
            )
        case .invalidAction:
            return DocumentEngineLocalization.string(
                "요청한 엑셀 작업의 옵션이 올바르지 않습니다. 대상과 설정값을 확인해 다시 요청해 주세요."
            )
        case .tooManyChanges:
            return DocumentEngineLocalization.string(
                "한 번에 수정할 수 있는 범위를 초과했습니다. 행이나 대상을 나누어 지시해 주세요."
            )
        case .invalidTarget:
            return DocumentEngineLocalization.string(
                "AI가 현재 표 밖의 셀을 지정했습니다. 파일은 변경되지 않았습니다."
            )
        case .editingUnavailable:
            return DocumentEngineLocalization.string(
                "대용량 문서에서는 AI 검색과 질문만 사용할 수 있습니다. 셀 수정은 직접 편집해 주세요."
            )
        case .protectedWorksheet:
            return DocumentEngineLocalization.string(
                "보호된 시트는 AI가 수정하지 않습니다. 시트 보호를 해제한 뒤 다시 요청해 주세요."
            )
        }
    }
}

public nonisolated enum ExcelAIApplyError: LocalizedError {
    case staleProposal
    case invalidTarget
    case appendTargetOccupied
    case rowLimitExceeded
    case conflictingEdits
    case noChanges

    public var errorDescription: String? {
        switch self {
        case .staleProposal:
            return DocumentEngineLocalization.string(
                "AI가 수정 내용을 준비하는 동안 문서나 시트가 바뀌었습니다. 최신 상태에서 다시 지시해 주세요."
            )
        case .invalidTarget:
            return DocumentEngineLocalization.string(
                "수정할 표 또는 셀을 현재 문서에서 찾지 못했습니다. 파일은 변경되지 않았습니다."
            )
        case .appendTargetOccupied:
            return DocumentEngineLocalization.string(
                "표 바로 아래에 다른 데이터가 있어 안전하게 새 행을 추가할 수 없습니다. 파일은 변경되지 않았습니다."
            )
        case .rowLimitExceeded:
            return DocumentEngineLocalization.string(
                "지원하는 최대 행 수를 초과해 새 행을 추가할 수 없습니다."
            )
        case .conflictingEdits:
            return DocumentEngineLocalization.string(
                "같은 셀(병합된 셀 포함)에 서로 다른 수정이 겹쳐 적용할 수 없습니다. 파일은 변경되지 않았습니다."
            )
        case .noChanges:
            return DocumentEngineLocalization.string(
                "적용할 변경 내용이 없습니다."
            )
        }
    }
}

public nonisolated enum ExcelAICommandValidator {
    public static let maximumChanges = 100
    public static let maximumAppendedRows = 10
    public static let maximumValueCharacters = 10_000
    public static let maximumActions = 20
    public static let maximumActionCells = 2_000
    public static let maximumCreatedTables = 3
    public static let maximumCreatedTableColumns = 50
    public static let maximumCreatedTableBlankRows = 100

    /// Cell references the user typed verbatim ("H6", "b2", "$I$6",
    /// "B2:C2"). Only these may be edited outside a region, so a model
    /// cannot invent a target address on its own.
    public static func explicitCellAddresses(
        in text: String
    ) -> Set<ExcelCellAddress> {
        let pattern = #"(?<![A-Za-z0-9_])\$?([A-Za-z]{1,3})\$?(\d{1,7})(?::\$?([A-Za-z]{1,3})\$?(\d{1,7}))?(?![A-Za-z0-9_])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        var addresses = Set<ExcelCellAddress>()
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            func part(_ index: Int) -> String? {
                Range(match.range(at: index), in: text).map { String(text[$0]) }
            }
            guard let startColumn = part(1), let startRow = part(2),
                  let start = ExcelCellAddress(startColumn.uppercased() + startRow) else {
                continue
            }
            if let endColumn = part(3), let endRow = part(4),
               let end = ExcelCellAddress(endColumn.uppercased() + endRow) {
                let cellRange = ExcelCellRange(start: start, end: end)
                let rows = cellRange.end.row - cellRange.start.row + 1
                let columns = cellRange.end.column - cellRange.start.column + 1
                guard rows * columns <= 100 else { continue }
                for row in cellRange.start.row...cellRange.end.row {
                    for column in cellRange.start.column...cellRange.end.column {
                        addresses.insert(ExcelCellAddress(row: row, column: column))
                    }
                }
            } else {
                addresses.insert(start)
            }
        }
        return addresses
    }

    public static func validate(
        _ plan: ExcelAICommandPlan,
        snapshot: ExcelAIWorkbookSnapshot,
        userRequest: String = ""
    ) throws -> ExcelAIValidatedPlan? {
        let assistantMessage = plan.assistantMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !assistantMessage.isEmpty else {
            throw ExcelAICommandValidationError.invalidResponse
        }

        switch plan.intent {
        case .answer, .clarify:
            guard plan.edits.isEmpty,
                  plan.appendedRows.isEmpty,
                  plan.createdTables.isEmpty,
                  plan.actions.isEmpty,
                  plan.workbookOperations.isEmpty else {
                throw ExcelAICommandValidationError.invalidResponse
            }
            return nil
        case .edit:
            guard !plan.edits.isEmpty
                    || !plan.appendedRows.isEmpty
                    || !plan.createdTables.isEmpty
                    || !plan.actions.isEmpty
                    || !plan.workbookOperations.isEmpty else {
                throw ExcelAICommandValidationError.invalidResponse
            }
            guard snapshot.supportsEdits else {
                throw ExcelAICommandValidationError.editingUnavailable
            }
            guard !snapshot.worksheetIsProtected || (plan.edits.isEmpty && plan.appendedRows.isEmpty && plan.createdTables.isEmpty && plan.actions.isEmpty && !plan.workbookOperations.isEmpty) else {
                throw ExcelAICommandValidationError.protectedWorksheet
            }
        }

        let operations = plan.workbookOperations.isEmpty ? [] : try ExcelAIWorkbookOperation.validate(plan.workbookOperations, snapshot: snapshot, userRequest: userRequest)
        let changeCount = plan.edits.count
            + plan.appendedRows.reduce(0) { $0 + $1.values.count }
            + plan.createdTables.reduce(0) { $0 + $1.headers.count }
        guard changeCount <= maximumChanges,
              plan.appendedRows.count <= maximumAppendedRows,
              plan.createdTables.count <= maximumCreatedTables,
              plan.actions.count <= maximumActions else {
            throw ExcelAICommandValidationError.tooManyChanges
        }

        if !plan.createdTables.isEmpty {
            guard plan.edits.isEmpty,
                  plan.appendedRows.isEmpty,
                  plan.actions.isEmpty,
                  !snapshot.contextWasTruncated else {
                throw ExcelAICommandValidationError.invalidResponse
            }
        }
        var seenAddresses = Set<String>()
        var previewLines = [String]()
        var validatedCreatedTables = [ExcelAICommandPlan.CreatedTable]()
        var createdTableRanges = [ExcelCellRange]()

        for table in plan.createdTables {
            let headers = table.headers.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let normalizedHeaders = headers.map {
                $0.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                )
            }
            guard !headers.isEmpty,
                  headers.count <= maximumCreatedTableColumns,
                  headers.allSatisfy({
                      !$0.isEmpty
                          && $0.count <= 255
                          && !$0.contains("\0")
                  }),
                  Set(normalizedHeaders).count == headers.count,
                  (1...maximumCreatedTableBlankRows).contains(
                      table.blankRowCount
                  ),
                  table.startRow > 0,
                  table.startColumn > 0 else {
                throw ExcelAICommandValidationError.invalidResponse
            }
            let endRow = table.startRow + table.blankRowCount
            let endColumn = table.startColumn + headers.count - 1
            guard endRow <= ExcelWorkbookDocument.maximumExcelRows,
                  endColumn <= ExcelWorkbookDocument.maximumExcelColumns else {
                throw ExcelAICommandValidationError.tooManyChanges
            }
            let range = ExcelCellRange(
                start: ExcelCellAddress(
                    row: table.startRow,
                    column: table.startColumn
                ),
                end: ExcelCellAddress(
                    row: endRow,
                    column: endColumn
                )
            )
            let overlapsDocument = snapshot.cells.contains {
                range.contains(
                    ExcelCellAddress(row: $0.row, column: $0.column)
                )
            } || snapshot.regions.contains {
                guard let existing = ExcelCellRange($0.range) else {
                    return false
                }
                return rangesOverlap(range, existing)
            } || snapshot.mergedRanges.contains {
                guard let existing = ExcelCellRange($0) else {
                    return false
                }
                return rangesOverlap(range, existing)
            } || createdTableRanges.contains {
                rangesOverlap(range, $0)
            }
            guard !overlapsDocument else {
                throw ExcelAICommandValidationError.invalidTarget
            }
            let validated = ExcelAICommandPlan.CreatedTable(
                startRow: table.startRow,
                startColumn: table.startColumn,
                headers: headers,
                blankRowCount: table.blankRowCount
            )
            validatedCreatedTables.append(validated)
            createdTableRanges.append(range)
            previewLines.append(
                DocumentEngineLocalization.format(
                    "%@에 새 표 · %lld열 · 빈 입력 행 %lld개 · %@",
                    range.reference,
                    headers.count,
                    table.blankRowCount,
                    headers.joined(separator: ", ")
                )
            )
        }

        let explicitAddresses = explicitCellAddresses(in: userRequest)
        var usedExplicitAddresses = Set<ExcelCellAddress>()
        for edit in plan.edits {
            guard edit.newValue.count <= maximumValueCharacters,
                  !edit.newValue.contains("\0"),
                  edit.row >= 1, edit.column >= 1 else {
                throw ExcelAICommandValidationError.invalidTarget
            }
            let region = snapshot.region(
                containingRow: edit.row,
                column: edit.column
            )
            if region == nil {
                // Outside every region: allowed only for a cell the user
                // named in this very request.
                let requested = ExcelCellAddress(row: edit.row, column: edit.column)
                guard explicitAddresses.contains(requested) else {
                    throw ExcelAICommandValidationError.invalidTarget
                }
                usedExplicitAddresses.insert(requested)
            }
            // Deduplicate on the merged-range anchor so two edits that
            // land on the same physical cell are rejected here instead
            // of colliding during apply.
            let canonical = snapshot.canonicalAddress(
                row: edit.row,
                column: edit.column
            )
            let key = "\(canonical.row):\(canonical.column)"
            guard seenAddresses.insert(key).inserted else {
                throw ExcelAICommandValidationError.invalidResponse
            }
            let columnTitle = region?.columns.first {
                $0.number == edit.column
            }?.title ?? ExcelCellAddress.columnName(edit.column)
            let oldValue = snapshot.cell(
                row: edit.row,
                column: edit.column
            )?.formula.map { "=" + $0 }
                ?? snapshot.cell(
                    row: edit.row,
                    column: edit.column
                )?.value
                ?? DocumentEngineLocalization.string("빈 셀")
            let newValue = edit.newValue.isEmpty
                ? DocumentEngineLocalization.string("빈 셀")
                : edit.newValue
            previewLines.append(
                DocumentEngineLocalization.format(
                    "%lld행 · %@: %@ → %@",
                    edit.row,
                    columnTitle,
                    oldValue,
                    newValue
                )
            )
        }

        for (index, appendedRow) in plan.appendedRows.enumerated() {
            guard let region = snapshot.region(id: appendedRow.regionID),
                  !appendedRow.values.isEmpty else {
                throw ExcelAICommandValidationError.invalidTarget
            }
            var seenColumns = Set<Int>()
            var valueDescriptions = [String]()
            for value in appendedRow.values {
                guard region.columns.contains(where: {
                    $0.number == value.column
                }),
                seenColumns.insert(value.column).inserted,
                value.newValue.count <= maximumValueCharacters,
                !value.newValue.contains("\0") else {
                    throw ExcelAICommandValidationError.invalidTarget
                }
                if value.newValue.isEmpty {
                    throw ExcelAICommandValidationError.invalidResponse
                }
                let title = region.columns.first {
                    $0.number == value.column
                }?.title ?? ExcelCellAddress.columnName(value.column)
                valueDescriptions.append("\(title) \(value.newValue)")
            }
            previewLines.append(
                DocumentEngineLocalization.format(
                    "새 행 %lld · %@",
                    index + 1,
                    valueDescriptions.joined(separator: ", ")
                )
            )
        }

        var validatedActions = [ExcelAIValidatedAction]()
        var actionCellCount = 0
        var actionTargetKeys = Set<String>()
        for action in plan.actions {
            let validated = try validateAction(
                action,
                snapshot: snapshot
            )
            actionCellCount += validated.action.addresses.count
            guard actionCellCount <= maximumActionCells else {
                throw ExcelAICommandValidationError.tooManyChanges
            }
            for conflictKey in validated.conflictKeys {
                guard actionTargetKeys.insert(conflictKey).inserted else {
                    throw ExcelAICommandValidationError.invalidResponse
                }
            }
            validatedActions.append(validated.action)
            previewLines.append(validated.preview)
        }

        // A display-format request must never rewrite the cells it formats.
        // Models sometimes pair setNumberFormat with edits that replace a
        // formula (or the same number, rounded) with its displayed text;
        // drop those edits so the format is applied and the data survives.
        let numberFormatTargets = Set(
            validatedActions.flatMap { action -> [ExcelCellAddress] in
                if case .setNumberFormat(let addresses, _) = action {
                    return addresses
                }
                return []
            }
        )
        let numberFormatDecimals: [ExcelCellAddress: Int] = Dictionary(
            validatedActions.flatMap { action -> [(ExcelCellAddress, Int)] in
                guard case .setNumberFormat(let addresses, let format) = action
                else { return [] }
                let decimals: Int
                switch format {
                case .integer, .currencyWon: decimals = 0
                case .decimalOne: decimals = 1
                case .decimalTwo: decimals = 2
                default: return []
                }
                return addresses.map { ($0, decimals) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let retainedEdits = plan.edits.filter { edit in
            guard !numberFormatTargets.isEmpty else { return true }
            let canonical = snapshot.canonicalAddress(
                row: edit.row,
                column: edit.column
            )
            let current = snapshot.cell(
                row: canonical.row,
                column: canonical.column
            )
            if numberFormatTargets.contains(canonical), let current {
                if current.formula != nil {
                    return false
                }
                if let currentNumber = Double(current.value),
                   let newNumber = Double(edit.newValue),
                   currentNumber == newNumber {
                    return false
                }
                return true
            }
            // A numeric write that equals a formatted cell in the same row
            // rounded to the requested precision is the model copying a
            // display value into the wrong column; drop it.
            guard let newNumber = Double(edit.newValue) else { return true }
            let strayRounding = numberFormatDecimals.contains { target, decimals in
                guard target.row == canonical.row,
                      target != canonical,
                      let formatted = snapshot.cell(
                          row: target.row,
                          column: target.column
                      ),
                      let value = Double(formatted.value) else {
                    return false
                }
                let scale = pow(10.0, Double(decimals))
                return value != newNumber
                    && (value * scale).rounded() / scale == newNumber
            }
            return !strayRounding
        }

        return ExcelAIValidatedPlan(
            assistantMessage: assistantMessage,
            edits: retainedEdits,
            appendedRows: plan.appendedRows,
            createdTables: validatedCreatedTables,
            actions: validatedActions,
            sheetPartPath: snapshot.sheetPartPath,
            sourceRevision: snapshot.revision,
            previewLines: previewLines,
            explicitAddresses: usedExplicitAddresses,
            workbookOperations: operations
        )
    }

    private static func rangesOverlap(
        _ lhs: ExcelCellRange,
        _ rhs: ExcelCellRange
    ) -> Bool {
        lhs.start.row <= rhs.end.row
            && lhs.end.row >= rhs.start.row
            && lhs.start.column <= rhs.end.column
            && lhs.end.column >= rhs.start.column
    }

    private static func validateAction(
        _ action: ExcelAICommandPlan.Action,
        snapshot: ExcelAIWorkbookSnapshot
    ) throws -> (
        action: ExcelAIValidatedAction,
        conflictKeys: [String],
        preview: String
    ) {
        guard let region = snapshot.region(id: action.target.regionID),
              let column = region.columns.first(where: {
                  $0.number == action.target.column
              }) else {
            throw ExcelAICommandValidationError.invalidTarget
        }
        let addresses: [ExcelCellAddress]
        let targetDescription: String
        let regionRange = ExcelCellRange(region.range)
        let editableRows: [Int]
        if region.isNativeTable,
           let regionRange,
           let headerRow = region.headerRow,
           headerRow < regionRange.end.row {
            editableRows = Array((headerRow + 1) ... regionRange.end.row)
        } else {
            editableRows = region.dataRows
        }
        switch action.target.scope {
        case .cell:
            guard let row = action.target.row,
                  editableRows.contains(row) else {
                throw ExcelAICommandValidationError.invalidTarget
            }
            addresses = [ExcelCellAddress(row: row, column: column.number)]
            targetDescription = "\(row)행 · \(column.title)"
        case .column:
            guard action.target.row == nil,
                  !editableRows.isEmpty else {
                throw ExcelAICommandValidationError.invalidTarget
            }
            addresses = editableRows.map {
                ExcelCellAddress(row: $0, column: column.number)
            }
            targetDescription = "\(column.title) 열"
        }
        switch action.type {
        case .setNumberFormat:
            guard let rawFormat = action.format,
                  let format = ExcelNumberFormat(rawValue: rawFormat) else {
                throw ExcelAICommandValidationError.invalidAction
            }
            return (
                .setNumberFormat(addresses: addresses, format: format),
                addresses.map { "numberFormat:\($0.reference)" },
                "\(targetDescription): 표시 형식 → \(format.title)"
            )

        case .setDropdown:
            let values = normalizedDropdownValues(action.values ?? [])
            guard values.count >= 2,
                  values.allSatisfy({
                      !$0.contains(",") && !$0.contains("\"")
                  }),
                  values.joined(separator: ",").utf16.count <= 253 else {
                throw ExcelAICommandValidationError.invalidAction
            }
            return (
                .setDropdown(
                    addresses: addresses,
                    values: values,
                    allowsBlank: action.allowsBlank ?? true
                ),
                addresses.map { "dropdown:\($0.reference)" },
                "\(targetDescription): 드롭다운 → "
                    + values.joined(separator: ", ")
            )

        case .removeDropdown:
            return (
                .removeDropdown(addresses: addresses),
                addresses.map { "dropdown:\($0.reference)" },
                "\(targetDescription): 드롭다운 제거"
            )

        case .setConditionalFormatting:
            guard let rawKind = action.condition,
                  let kind = ExcelConditionalRuleKind(rawValue: rawKind),
                  let rawHighlight = action.highlight,
                  let highlight = ExcelConditionalHighlight(
                      rawValue: rawHighlight
                  ),
                  let comparisonValue = action.comparisonValue?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !comparisonValue.isEmpty,
                  !kind.requiresNumber || Double(comparisonValue) != nil else {
                throw ExcelAICommandValidationError.invalidAction
            }
            return (
                .setConditionalFormatting(
                    addresses: addresses,
                    kind: kind,
                    comparisonValue: comparisonValue,
                    highlight: highlight
                ),
                // Distinct rules may stack on the same cells; only the same
                // condition and value twice in one plan is a conflict.
                addresses.map {
                    "conditionalFormatting:\($0.reference):\(kind.rawValue):"
                        + comparisonValue.lowercased()
                },
                "\(targetDescription): 조건부 서식 → "
                    + "\(kind.title) \(comparisonValue), \(highlight.title)"
            )

        case .removeConditionalFormatting:
            return (
                .removeConditionalFormatting(addresses: addresses),
                addresses.map {
                    "conditionalFormatting:\($0.reference)"
                },
                "\(targetDescription): 조건부 서식 제거"
            )
        }
    }

    private static func normalizedDropdownValues(
        _ rawValues: [String]
    ) -> [String] {
        var seen = Set<String>()
        return rawValues.compactMap { rawValue in
            let value = rawValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !value.isEmpty, seen.insert(value).inserted else {
                return nil
            }
            return value
        }
    }
}
