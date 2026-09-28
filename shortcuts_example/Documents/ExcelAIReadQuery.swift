import Foundation

/// Schema-sized context for interpreting a question. No row counts or partial
/// records are offered as possible answers at this stage.
nonisolated struct ExcelAIReadQueryContext: Encodable {
    struct Sheet: Encodable {
        let id: String
        let name: String
        let position: Int
    }
    struct Region: Encodable {
        struct Column: Encodable {
            let number: Int
            let title: String
            let storageTypes: [String]
            let exampleValues: [String]
        }
        let id: String
        let name: String
        let sheetID: String
        let sheetName: String
        let columns: [Column]
    }
    let userRequest: String
    let recentConversation: [ExcelAIChatTurn]
    let queryScope: String
    let previousQuery: ExcelAIReadQuery?
    let sheets: [Sheet]
    let regions: [Region]
    private let snapshotRevision: String
    private enum CodingKeys: String, CodingKey { case userRequest, recentConversation, queryScope, previousQuery, sheets, regions }

    init(request: String, snapshot: ExcelAIWorkbookSnapshot, history: [ExcelAIChatTurn]) {
        userRequest = request
        snapshotRevision = snapshot.revision
        let normalized = request.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
        let subsetPrefixes = ["그중", "이중", "그가운데", "이가운데", "amongthose", "ofthose", "amongthem", "その中", "それらのうち"]
        let contextPrefixes = ["그럼", "그러면", "그거", "그것", "이거", "이것", "방금", "앞에서", "위에서", "거기", "그품목", "그제품", "then", "whatabout", "those", "that", "それ", "では", "じゃあ"]
        let workbook = snapshot.localWorkbook
        let listedSheets = snapshot.workbookContext?.sheets ?? []
        sheets = listedSheets.map { .init(id: $0.id, name: $0.name, position: $0.position) }
        let requestsSheets = normalized.contains("시트") || normalized.contains("sheet") || normalized.contains("tab")
            || listedSheets.contains {
                let name = $0.name.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
                return $0.id != snapshot.sheetPartPath && !name.isEmpty && normalized.contains(name)
            }
        if subsetPrefixes.contains(where: normalized.hasPrefix) {
            queryScope = "previousResult"
        } else if contextPrefixes.contains(where: normalized.hasPrefix) {
            queryScope = "conversation"
        } else if requestsSheets, workbook != nil {
            queryScope = "workbook"
        } else {
            queryScope = "worksheet"
        }
        // A complete new question must not accidentally inherit old filters.
        // An explicit subset request uses the previous verified plan directly,
        // rather than reconstructing it from a possibly abbreviated answer.
        recentConversation = queryScope == "conversation" ? Array(history.suffix(8)) : []
        previousQuery = queryScope == "worksheet" || queryScope == "workbook" ? nil : history.last(where: { $0.role == "assistant" && $0.query != nil })?.query
        let sourceSheets = queryScope == "workbook" ? (workbook?.sheets ?? []) : [snapshot.localQuerySheet].compactMap { $0 }
        regions = sourceSheets.flatMap { sheet -> [Region] in
            let accessible = ExcelAccessibilityAnalyzer.regions(in: sheet)
            return accessible.map { region in
                Region(id: region.id, name: region.name, sheetID: sheet.partPath, sheetName: sheet.name,
                       columns: region.columns.map { column in
                    let cells = ExcelAIQueryData.dataRows(region.rowNumbers, regionID: region.id, sheet: sheet).prefix(20).compactMap { row in
                        sheet.cell(at: ExcelCellAddress(row: row, column: column.column))
                    }
                    let examples = sheet.partPath == snapshot.sheetPartPath
                        ? snapshot.valueGroups.filter { $0.regionID == region.id && $0.column == column.column }.map(\.value)
                        : []
                    return Region.Column(number: column.column, title: column.title,
                        storageTypes: Set(cells.map { $0.cellType == nil || $0.cellType == "n" ? "number" : "text" }).sorted(),
                        exampleValues: Array((examples.isEmpty ? Array(Set(cells.prefix(3).map(\.rawValue))).sorted() : examples).prefix(8)))
                })
            }
        }
    }

    func resolved(_ proposedQuery: ExcelAIReadQuery) throws -> ExcelAIReadQuery {
        var query = correctingExplicitComparisons(proposedQuery)
        guard queryScope == "previousResult", query.operation != .none else { return query }
        guard let previousQuery else { throw ExcelAIReadQueryError.invalidQuery }
        if !previousQuery.sheetTargets.isEmpty {
            guard !query.sheetTargets.isEmpty,
                  Set(previousQuery.sheetTargets.map(\.sheetID)) == Set(query.sheetTargets.map(\.sheetID)),
                  let scope = previousQuery.workbookResultScope,
                  scope.revision == snapshotRevision else { throw ExcelAIReadQueryError.invalidQuery }
            query.workbookInputScope = scope
            return query
        }
        guard previousQuery.regionID == query.regionID else { throw ExcelAIReadQueryError.invalidQuery }
        if let scope = previousQuery.resultScope {
            guard scope.revision == snapshotRevision else { throw ExcelAIReadQueryError.staleResult }
            query.inputScope = scope
            return query
        }
        // Older chat entries contain predicates, but cannot reconstruct a ranked
        // or grouped result from predicates alone.
        guard !previousQuery.isAnalysis,
              previousQuery.match == .all || previousQuery.filters.count == 1,
              query.match == .all || query.filters.count == 1 else {
            throw ExcelAIReadQueryError.invalidQuery
        }
        var filters = previousQuery.filters
        for filter in query.filters where !filters.contains(filter) { filters.append(filter) }
        query.match = .all
        query.filters = filters
        return query
    }

    /// Ground an unambiguous literal column/number comparison in the request.
    /// Header names and numeric thresholds come from the sheet and the request;
    /// this never relies on a particular workbook, column, product, or value.
    private func correctingExplicitComparisons(_ query: ExcelAIReadQuery) -> ExcelAIReadQuery {
        guard let region = regions.first(where: { $0.id == query.regionID }) else { return query }
        let number = #"([+-]?(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]+)?)"#
        let filters = query.filters.map { filter -> ExcelAIReadQuery.Filter in
            guard filter.valueType == .number,
                  let title = region.columns.first(where: { $0.number == filter.column })?.title,
                  !title.isEmpty else { return filter }
            let header = title.split(whereSeparator: \.isWhitespace)
                .map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"\s*"#)
            let lead = #"(?<![\p{L}\p{N}_])"# + header + #"\s*(?:열\s*)?(?:값\s*)?(?:가|이|은|는)?\s*"#
            let patterns = [
                (lead + #"(>=|<=|!=|==|=|>|<|≥|≤|≠)\s*"# + number, 2, 1),
                (lead + number + #"\s*(?:원|개|점|명|대)?\s*(이상|이하|초과|미만|이고|인|와\s*같은|과\s*같은)"#, 1, 2),
            ]
            var comparisons = Set<ExcelAIReadQuery.Filter.Comparison>()
            for (pattern, valueIndex, operatorIndex) in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
                for match in regex.matches(in: userRequest, range: NSRange(userRequest.startIndex..., in: userRequest)) {
                    guard let valueRange = Range(match.range(at: valueIndex), in: userRequest),
                          let operatorRange = Range(match.range(at: operatorIndex), in: userRequest),
                          let value = Decimal(string: userRequest[valueRange].replacingOccurrences(of: ",", with: "")),
                          value == Decimal(string: filter.value) else { continue }
                    let token = userRequest[operatorRange].filter { !$0.isWhitespace }
                    switch token {
                    case ">=", "≥", "이상": comparisons.insert(.greaterThanOrEqual)
                    case "<=", "≤", "이하": comparisons.insert(.lessThanOrEqual)
                    case ">", "초과": comparisons.insert(.greaterThan)
                    case "<", "미만": comparisons.insert(.lessThan)
                    case "!=", "≠": comparisons.insert(.notEqual)
                    default: comparisons.insert(.equals)
                    }
                }
            }
            guard comparisons.count == 1, let comparison = comparisons.first else { return filter }
            return .init(column: filter.column, comparison: comparison, valueType: filter.valueType, value: filter.value)
        }
        var corrected = query
        corrected.filters = filters
        return corrected
    }
}

/// The model selects columns and predicates. Only the local executor determines
/// matching rows, counts, displayed values, and reference addresses.
nonisolated struct ExcelAIReadQuery: Codable, Sendable {
    enum Operation: String, Codable, Sendable { case none, rows, count, sum, average, minimum, maximum, distinctCount, rank }
    enum Match: String, Codable, Sendable { case all, any }
    enum Presentation: String, Codable, Sendable { case single, bySheet, combined, both }
    struct Filter: Codable, Hashable, Sendable {
        enum Comparison: String, Codable, Sendable {
            case equals, notEqual, greaterThan, greaterThanOrEqual, lessThan, lessThanOrEqual, contains

            var label: String {
                switch self {
                case .equals: "="
                case .notEqual: "≠"
                case .greaterThan: ">"
                case .greaterThanOrEqual: "≥"
                case .lessThan: "<"
                case .lessThanOrEqual: "≤"
                case .contains: AppLocalization.string("포함")
                }
            }
        }
        enum ValueType: String, Codable, Sendable { case number, text }
        let column: Int
        let comparison: Comparison
        let valueType: ValueType
        let value: String
    }
    struct SheetTarget: Codable, Sendable {
        let sheetID: String
        let regionID: String
        let match: Match
        let filters: [Filter]
        let selectColumns: [Int]
        let metricColumn: Int?
        let groupBy: [Int]
        let visibleOnly: Bool
    }
    let operation: Operation
    let regionID: String
    var match: Match
    var filters: [Filter]
    let selectColumns: [Int]
    let metricColumn: Int?
    let groupBy: [Int]
    enum Sort: String, Codable, Sendable { case ascending, descending }
    let sort: Sort?
    let limit: Int?
    let visibleOnly: Bool
    let sheetTargets: [SheetTarget]
    let presentation: Presentation
    struct ResultScope: Sendable { let revision: String; let rows: [Int] }
    struct WorkbookResultScope: Sendable { let revision: String; let rowsBySheet: [String: [Int]] }
    var inputScope: ResultScope? = nil
    var resultScope: ResultScope? = nil
    var workbookInputScope: WorkbookResultScope? = nil
    var workbookResultScope: WorkbookResultScope? = nil
    var isAnalysis: Bool { ![.none, .rows, .count].contains(operation) || !groupBy.isEmpty }
    var isWorkbookQuery: Bool { !sheetTargets.isEmpty }

    init(operation: Operation, regionID: String, match: Match, filters: [Filter], selectColumns: [Int],
         metricColumn: Int? = nil, groupBy: [Int] = [], sort: Sort? = nil, limit: Int? = nil, visibleOnly: Bool = false,
         sheetTargets: [SheetTarget] = [], presentation: Presentation = .single) {
        self.operation = operation; self.regionID = regionID; self.match = match; self.filters = filters; self.selectColumns = selectColumns
        self.metricColumn = metricColumn; self.groupBy = groupBy; self.sort = sort; self.limit = limit; self.visibleOnly = visibleOnly
        self.sheetTargets = sheetTargets; self.presentation = presentation
    }
    private enum CodingKeys: String, CodingKey { case operation, regionID, match, filters, selectColumns, metricColumn, groupBy, sort, limit, visibleOnly, sheetTargets, presentation }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(operation: try c.decode(Operation.self, forKey: .operation), regionID: try c.decode(String.self, forKey: .regionID),
                  match: try c.decode(Match.self, forKey: .match), filters: try c.decode([Filter].self, forKey: .filters),
                  selectColumns: try c.decode([Int].self, forKey: .selectColumns), metricColumn: try c.decodeIfPresent(Int.self, forKey: .metricColumn),
                  groupBy: try c.decodeIfPresent([Int].self, forKey: .groupBy) ?? [], sort: try c.decodeIfPresent(Sort.self, forKey: .sort),
                  limit: try c.decodeIfPresent(Int.self, forKey: .limit), visibleOnly: try c.decodeIfPresent(Bool.self, forKey: .visibleOnly) ?? false,
                  sheetTargets: try c.decodeIfPresent([SheetTarget].self, forKey: .sheetTargets) ?? [],
                  presentation: try c.decodeIfPresent(Presentation.self, forKey: .presentation) ?? .single)
    }
}

nonisolated enum ExcelAIReadQueryError: LocalizedError {
    case incompleteSheet, invalidQuery, invalidNumber, cellError, staleResult, arithmeticOverflow, unsupportedFormula, ambiguousMergedData, unsupportedMetric, mixedUnits

    var errorDescription: String? {
        switch self {
        case .staleResult:
            AppLocalization.string("이전 답변 이후 문서나 선택이 바뀌었습니다. 현재 데이터로 다시 질문해 주세요.")
        case .arithmeticOverflow:
            AppLocalization.string("숫자의 크기나 정밀도가 계산 범위를 넘어 결과를 확정할 수 없습니다.")
        case .unsupportedFormula:
            AppLocalization.string("계산에 필요한 수식을 앱에서 처리할 수 없어 결과를 확정하지 못했습니다.")
        case .ambiguousMergedData:
            AppLocalization.string("집계 대상에 여러 행에 걸친 병합 셀이 있습니다. 행별 값을 구분할 수 있는 범위로 질문해 주세요.")
        case .mixedUnits:
            AppLocalization.string("서로 다른 통화나 단위가 섞여 있어 하나의 값으로 집계할 수 없습니다.")
        case .unsupportedMetric:
            AppLocalization.string("날짜·시간 열의 합계나 평균은 아직 지원하지 않습니다. 숫자 열을 지정해 주세요.")
        case .incompleteSheet:
            AppLocalization.string("시트 전체를 읽지 못해 조건에 맞는 결과를 확정할 수 없습니다.")
        case .invalidQuery:
            AppLocalization.string("검색 조건을 확인하지 못했습니다. 열 이름과 조건을 다시 알려주세요.")
        case .invalidNumber:
            AppLocalization.string("비교할 숫자를 확인하지 못했습니다.")
        case .cellError:
            AppLocalization.string("검색 대상에 계산 오류가 있어 결과를 확정할 수 없습니다.")
        }
    }
}

nonisolated struct ExcelAIReadQueryResult: Sendable {
    let rows: [Int]
    let answer: String
    let references: ExcelAIReferences?
    var scopeRows: [Int]? = nil
    var scopeRowsBySheet: [String: [Int]]? = nil
}

nonisolated enum ExcelAIReadQueryExecutor {
    static func execute(_ query: ExcelAIReadQuery, snapshot: ExcelAIWorkbookSnapshot) throws -> ExcelAIReadQueryResult? {
        guard query.operation != .none else { return nil }
        if query.isWorkbookQuery { return try ExcelAIWorkbookReadQueryExecutor.execute(query, snapshot: snapshot) }
        let prepared = try matchingRows(query, snapshot: snapshot)
        let region = prepared.region
        let data = prepared.data
        let rows = prepared.rows
        let sheet = data.sheet
        if query.isAnalysis {
            return try ExcelAIAggregation.execute(query, snapshot: snapshot, region: region, data: data, rows: rows)
        }
        let titles = Dictionary(uniqueKeysWithValues: region.columns.map { ($0.number, $0.title) })
        let separator = query.match == .all ? AppLocalization.string(" 그리고 ") : AppLocalization.string(" 또는 ")
        let condition = query.filters.isEmpty ? AppLocalization.string("전체 데이터") : query.filters.map {
            "\(titles[$0.column] ?? "") \($0.comparison.label) \($0.value)"
        }.joined(separator: separator)
        var lines = [rows.isEmpty
            ? AppLocalization.format("%@ 조건에 맞는 행이 없습니다.", condition)
            : AppLocalization.format("%@ 조건에 맞는 행은 %lld개입니다.", condition, rows.count)]
        let projections = query.selectColumns.reduce(into: [Int]()) { result, column in
            if !result.contains(column) { result.append(column) }
        }
        if query.operation == .rows {
            for row in rows.prefix(20) {
                let values = projections.map { column in
                    let address = sheet.canonicalAddress(for: ExcelCellAddress(row: row, column: column))
                    let value = sheet.cell(at: address)?.displayValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return "\(titles[column] ?? ""): \(value.isEmpty ? AppLocalization.string("빈 셀") : value)"
                }.joined(separator: ", ")
                lines.append(AppLocalization.format("%lld행 — %@", row, values))
            }
            if rows.count > 20 {
                lines.append(AppLocalization.format("전체 %lld행 중 처음 %lld행을 표시했습니다. 일치하는 셀은 모두 강조했습니다.", rows.count, 20))
            }
        }
        let evidenceColumns = Set(query.filters.map(\.column) + (query.operation == .rows ? projections : []))
        let addresses = Set(rows.flatMap { row in
            evidenceColumns.compactMap { column -> ExcelCellAddress? in
                let address = sheet.canonicalAddress(for: ExcelCellAddress(row: row, column: column))
                return sheet.cell(at: address) == nil ? nil : address
            }
        }).sorted()
        let references = addresses.isEmpty ? nil : ExcelAIReferences(
            sheetPartPath: snapshot.sheetPartPath, sheetName: snapshot.sheetName, addresses: addresses
        )
        return ExcelAIReadQueryResult(rows: rows, answer: lines.joined(separator: "\n"), references: references)
    }

    static func matchingRows(_ query: ExcelAIReadQuery, snapshot: ExcelAIWorkbookSnapshot) throws
        -> (region: ExcelAIWorkbookSnapshot.Region, data: ExcelAIQueryData, rows: [Int]) {
        guard snapshot.supportsLocalQueries, let sourceSheet = snapshot.localQuerySheet, !sourceSheet.isWindowed, !sourceSheet.didTruncate else {
            throw ExcelAIReadQueryError.incompleteSheet
        }
        guard let region = snapshot.region(id: query.regionID),
              query.filters.count <= 12,
              query.selectColumns.count <= 16 else {
            throw ExcelAIReadQueryError.invalidQuery
        }
        try ExcelAIAggregation.validate(query, region: region)
        let columns = Set(region.columns.map(\.number))
        guard query.filters.allSatisfy({ columns.contains($0.column) }),
              query.selectColumns.allSatisfy(columns.contains),
              query.operation != .rows || !query.selectColumns.isEmpty else {
            throw ExcelAIReadQueryError.invalidQuery
        }
        for filter in query.filters {
            if filter.valueType == .number {
                guard filter.comparison != .contains, decimal(filter.value) != nil else {
                    throw ExcelAIReadQueryError.invalidNumber
                }
            } else if ![.equals, .notEqual, .contains].contains(filter.comparison) {
                throw ExcelAIReadQueryError.invalidQuery
            }
        }
        let data = try ExcelAIQueryData(snapshot: snapshot, recalculating: query.isAnalysis)
        let sheet = data.sheet
        var candidates = Set(region.dataRows)
        if let table = sheet.tables.first(where: { "table:" + $0.id == region.id }) {
            candidates = candidates.filter { $0 >= table.range.start.row + table.headerRowCount && $0 <= table.range.end.row - table.totalsRowCount }
        }
        if query.visibleOnly { candidates.subtract(sheet.hiddenRows) }
        if let scope = query.inputScope {
            guard scope.revision == snapshot.revision else { throw ExcelAIReadQueryError.staleResult }
            candidates.formIntersection(scope.rows)
        }
        let rows = try candidates.sorted().filter { row in
            if query.filters.isEmpty { return true }
            let matches = try query.filters.map { filter in
                try matchesFilter(filter, cell: data.cell(row: row, column: filter.column))
            }
            return query.match == .all ? matches.allSatisfy { $0 } : matches.contains(true)
        }
        return (region, data, rows)
    }

    static func matchesFilter(_ filter: ExcelAIReadQuery.Filter, cell: ExcelCell?) throws -> Bool {
        guard let cell else {
            return filter.valueType == .text && filter.comparison == .equals && filter.value.isEmpty
        }
        guard cell.cellType != "e" else { throw ExcelAIReadQueryError.cellError }
        if filter.valueType == .number {
            // Compare stored numbers, never formatted/rounded display strings.
            guard cell.cellType == nil || cell.cellType == "n",
                  let lhs = decimal(cell.rawValue), let rhs = decimal(filter.value) else { return false }
            switch filter.comparison {
            case .equals: return lhs == rhs
            case .notEqual: return lhs != rhs
            case .greaterThan: return lhs > rhs
            case .greaterThanOrEqual: return lhs >= rhs
            case .lessThan: return lhs < rhs
            case .lessThanOrEqual: return lhs <= rhs
            case .contains: throw ExcelAIReadQueryError.invalidQuery
            }
        }
        let lhs = cell.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rhs = filter.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch filter.comparison {
        case .equals: return lhs == rhs
        case .notEqual: return !lhs.isEmpty && lhs != rhs
        case .contains: return !rhs.isEmpty && lhs.contains(rhs)
        default: throw ExcelAIReadQueryError.invalidQuery
        }
    }

    static func decimal(_ text: String) -> Decimal? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$"#, options: .regularExpression) != nil else { return nil }
        let mantissa = value.lowercased().split(separator: "e")[0].filter(\.isNumber)
        let significant = mantissa.drop(while: { $0 == "0" }).reversed().drop(while: { $0 == "0" })
        guard significant.count <= 38, let number = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), !number.isNaN,
              number != 0 || significant.isEmpty else { return nil }
        return number
    }
}
