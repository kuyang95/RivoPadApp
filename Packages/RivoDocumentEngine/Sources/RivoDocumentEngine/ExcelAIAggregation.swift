import Foundation

/// A query-local view of cells. Recalculation never edits the workbook or trusts
/// a stale cached value when the current formula cannot be evaluated.
public nonisolated struct ExcelAIQueryData {
    public let sheet: ExcelWorksheet
    public let workbook: ExcelWorkbook?
    public let unresolved: Set<ExcelCellAddress>

    public init(snapshot: ExcelAIWorkbookSnapshot, recalculating: Bool) throws {
        guard var sheet = snapshot.localQuerySheet else { throw ExcelAIReadQueryError.incompleteSheet }
        workbook = snapshot.localWorkbook
        var unresolved = Set<ExcelCellAddress>()
        if recalculating && sheet.cells.values.contains(where: { $0.formula?.isEmpty == false }) {
            let result = ExcelFormulaCalculator.recalculate(cells: sheet.cells, styles: workbook?.styles ?? [.plain],
                uses1904DateSystem: workbook?.uses1904DateSystem ?? false, mergedRanges: sheet.mergedRanges,
                tableRanges: sheet.tables.map(\.range), workbook: workbook, currentSheetName: sheet.name)
            unresolved = Set(sheet.cells.values.filter { $0.formula?.isEmpty == false && result.values[$0.address] == nil }.map(\.address))
            for (address, value) in result.values {
                if var cell = sheet.cells[address] {
                    cell.rawValue = value.rawValue; cell.displayValue = value.displayValue; cell.cellType = value.cellType
                    sheet.cells[address] = cell
                }
            }
        }
        self.sheet = sheet
        self.unresolved = unresolved
    }

    public static func dataRows(_ rows: [Int], regionID: String, sheet: ExcelWorksheet) -> [Int] {
        guard let table = sheet.tables.first(where: { "table:" + $0.id == regionID }) else { return rows }
        return rows.filter { $0 >= table.range.start.row + table.headerRowCount && $0 <= table.range.end.row - table.totalsRowCount }
    }

    public func cell(row: Int, column: Int) throws -> ExcelCell? {
        let address = sheet.canonicalAddress(for: .init(row: row, column: column))
        if unresolved.contains(address) { throw ExcelAIReadQueryError.unsupportedFormula }
        let cell = sheet.cell(at: address)
        if cell?.cellType == "e" { throw ExcelAIReadQueryError.cellError }
        return cell
    }
    public func format(_ cell: ExcelCell) -> ExcelNumberFormat? {
        workbook.map { ExcelNumberFormat.matching($0.style(at: cell.styleIndex)) } ?? nil
    }
    public func currency(_ cell: ExcelCell) -> (symbol: String, places: Int)? {
        guard let workbook else { return nil }
        let style = workbook.style(at: cell.styleIndex)
        let code = (style.numberFormatCode ?? "").replacingOccurrences(of: #"\[\$-[^\]]*\]"#, with: "", options: .regularExpression)
        let symbols = ["$", "€", "£", "₩", "¥"].filter { code.contains($0) }
        let builtin = [5, 6, 7, 8, 42, 44].contains(style.numberFormatID)
        guard let symbol = symbols.count == 1 ? symbols.first : (code.isEmpty && builtin ? "$" : nil) else { return nil }
        let pattern = #"0\.([0#?]+)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let match = regex?.firstMatch(in: code, range: NSRange(code.startIndex..., in: code))
        let places = match.map { min($0.range(at: 1).length, 12) } ?? ([7, 8, 44].contains(style.numberFormatID) ? 2 : 0)
        return (symbol, places)
    }

}

public nonisolated enum ExcelAIAggregation {
    public struct Value: Sendable { public let number: Decimal; public let approximate: Bool 
    public init(number: Decimal, approximate: Bool) {
        self.number = number
        self.approximate = approximate
    }
}
    private enum Key: Hashable { case blank, text(String), number(Decimal), boolean(String) }
    private struct Entry {
        let row: Int
        let metric: Decimal?
        let key: Key
        let metricCell: ExcelCell?
    }
    private struct Group {
        let title: String
        let firstRow: Int
        var entries: [Entry]
    }
    private struct Summary {
        let group: Group
        let value: Value?
        let contributing: [Entry]
    }

    public static func validate(_ query: ExcelAIReadQuery, region: ExcelAIWorkbookSnapshot.Region) throws {
        let columns = Set(region.columns.map(\.number))
        guard query.groupBy.count <= 3, Set(query.groupBy).count == query.groupBy.count,
              query.groupBy.allSatisfy(columns.contains), query.limit.map({ (1...100).contains($0) }) ?? true else { throw ExcelAIReadQueryError.invalidQuery }
        if [.sum, .average, .minimum, .maximum, .distinctCount, .rank].contains(query.operation) {
            guard let metric = query.metricColumn, columns.contains(metric) else { throw ExcelAIReadQueryError.invalidQuery }
        } else if query.metricColumn != nil { throw ExcelAIReadQueryError.invalidQuery }
        if query.operation == .rank {
            guard query.groupBy.isEmpty, query.sort != nil, !query.selectColumns.isEmpty else { throw ExcelAIReadQueryError.invalidQuery }
        } else if query.isAnalysis {
            guard query.selectColumns.isEmpty else { throw ExcelAIReadQueryError.invalidQuery }
            if query.groupBy.isEmpty && (query.sort != nil || query.limit != nil) { throw ExcelAIReadQueryError.invalidQuery }
        } else if !query.groupBy.isEmpty || query.sort != nil || query.limit != nil {
            throw ExcelAIReadQueryError.invalidQuery
        }
        if query.operation == .rows && !query.groupBy.isEmpty { throw ExcelAIReadQueryError.invalidQuery }
    }

    public static func execute(_ query: ExcelAIReadQuery, snapshot: ExcelAIWorkbookSnapshot,
                        region: ExcelAIWorkbookSnapshot.Region, data: ExcelAIQueryData, rows: [Int]) throws -> ExcelAIReadQueryResult {
        let titles = Dictionary(uniqueKeysWithValues: region.columns.map { ($0.number, $0.title) })
        let metricTitle = query.metricColumn.flatMap { titles[$0] } ?? DocumentEngineLocalization.string("행")
        let condition = conditionDescription(query, titles: titles)
        let scope = DocumentEngineLocalization.format("%@ · %@", region.name, condition)
        if rows.isEmpty { return .init(rows: [], answer: scope + "\n" + DocumentEngineLocalization.string("조건에 맞는 데이터가 없습니다."), references: nil) }
        // A vertically merged measure or label would duplicate an anchor across
        // records. Require a row-wise table instead of inventing an allocation.
        let relevantColumns = Set(query.groupBy + query.filters.map(\.column) + [query.metricColumn].compactMap { $0 })
        if data.sheet.mergedRanges.contains(where: { range in
            range.start.row != range.end.row && relevantColumns.contains(where: { (range.start.column...range.end.column).contains($0) }) && rows.contains(where: { (range.start.row...range.end.row).contains($0) })
        }) { throw ExcelAIReadQueryError.ambiguousMergedData }

        var groups: [Group] = [], groupIndices: [[Key]: Int] = [:]
        var ignoredCount = 0
        for row in rows {
            var keys: [Key] = [], labels: [String] = []
            for column in query.groupBy {
                let cell = try data.cell(row: row, column: column)
                keys.append(try key(cell))
                let label = cell?.displayValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                labels.append("\(titles[column] ?? ""): \(label.isEmpty ? DocumentEngineLocalization.string("빈 셀") : label)")
            }
            let metricCell = try query.metricColumn.map { try data.cell(row: row, column: $0) } ?? nil
            var number: Decimal?
            if query.operation != .distinctCount && query.operation != .count {
                if let cell = metricCell, cell.cellType == nil || cell.cellType == "n", !cell.rawValue.isEmpty {
                    guard let parsed = ExcelAIReadQueryExecutor.decimal(cell.rawValue) else { throw ExcelAIReadQueryError.arithmeticOverflow }
                    if [.sum, .average].contains(query.operation), let format = data.format(cell), [.date, .time].contains(format) { throw ExcelAIReadQueryError.unsupportedMetric }
                    number = parsed
                } else { ignoredCount += 1 }
            }
            let entry = Entry(row: row, metric: number, key: query.operation == .distinctCount ? try key(metricCell) : .blank, metricCell: metricCell)
            if let index = groupIndices[keys] { groups[index].entries.append(entry) }
            else {
                groupIndices[keys] = groups.count
                groups.append(.init(title: labels.joined(separator: " · "), firstRow: row, entries: [entry]))
            }
        }
        if query.operation != .distinctCount && query.operation != .count {
            for group in groups { try validateUnits(group.entries, data: data) }
            if query.sort != nil { try validateUnits(groups.flatMap(\.entries), data: data) }
        }
        if query.operation == .rank {
            return try ranked(query, snapshot: snapshot, data: data, titles: titles, scope: scope, entries: groups.flatMap(\.entries), ignoredCount: ignoredCount)
        }
        var summaries = try groups.map { group -> Summary in
            if query.operation == .count {
                return .init(group: group, value: .init(number: Decimal(group.entries.count), approximate: false), contributing: group.entries)
            }
            if query.operation == .distinctCount {
                let entries = group.entries.filter { $0.key != .blank }
                return .init(group: group, value: .init(number: Decimal(Set(entries.map(\.key)).count), approximate: false), contributing: entries)
            }
            let entries = group.entries.filter { $0.metric != nil }
            let value = try aggregate(query.operation, values: entries.compactMap(\.metric))
            let contributing = [.minimum, .maximum].contains(query.operation) ? entries.filter { $0.metric == value?.number } : entries
            return .init(group: group, value: value, contributing: contributing)
        }
        if let sort = query.sort {
            summaries.sort { a, b in
                guard let av = a.value?.number else { return b.value == nil && a.group.firstRow < b.group.firstRow }
                guard let bv = b.value?.number else { return true }
                if av == bv { return a.group.firstRow < b.group.firstRow }
                return sort == .ascending ? av < bv : av > bv
            }
        }
        let displayed = Array(summaries.prefix(query.limit ?? 20))
        let label = operationLabel(query.operation)
        var lines = [scope]
        for item in displayed {
            let title = item.group.title.isEmpty ? metricTitle : item.group.title + " · " + metricTitle
            guard let value = item.value else {
                lines.append(DocumentEngineLocalization.format("%@: 계산할 숫자가 없습니다.", title)); continue
            }
            let number = query.operation == .distinctCount || query.operation == .count
                ? NSDecimalNumber(decimal: value.number).stringValue
                : try formatted(value, entries: item.contributing, query: query, data: data)
            lines.append(DocumentEngineLocalization.format("%@ · %@: %@", title, label, number))
            if query.operation == .average {
                lines.append(DocumentEngineLocalization.format("숫자 %lld셀을 기준으로 계산했습니다.", item.contributing.count))
            }
        }
        if ignoredCount > 0 { lines.append(DocumentEngineLocalization.format("빈 셀·텍스트 등 숫자가 아닌 %lld셀은 계산에서 제외했습니다.", ignoredCount)) }
        if query.operation == .distinctCount {
            lines.append(DocumentEngineLocalization.string("빈 값은 제외하고 텍스트의 앞뒤 공백과 영문 대소문자는 구분하지 않았습니다."))
        }
        if summaries.count > displayed.count {
            lines.append(DocumentEngineLocalization.format("전체 %lld그룹을 계산한 뒤 %lld그룹을 표시했습니다. 표시한 그룹의 근거 셀을 강조했습니다.", summaries.count, displayed.count))
            if query.sort != nil, let last = displayed.last?.value?.number, summaries[displayed.count].value?.number == last {
                lines.append(DocumentEngineLocalization.string("마지막 순위와 같은 값이 더 있습니다. 동점은 원래 행 순서로 표시했습니다."))
            }
        }
        let shownRows = displayed.flatMap { $0.contributing.map(\.row) }.sorted()
        let evidenceColumns = Set(query.filters.map(\.column) + query.groupBy + [query.metricColumn].compactMap { $0 })
        let population = [.sum, .average, .count].contains(query.operation) ? displayed.flatMap { $0.group.entries.map(\.row) }.sorted() : shownRows
        return .init(rows: shownRows, answer: lines.joined(separator: "\n"), references: references(rows: shownRows, columns: evidenceColumns, sheet: data.sheet, snapshot: snapshot), scopeRows: population)
    }

    private static func ranked(_ query: ExcelAIReadQuery, snapshot: ExcelAIWorkbookSnapshot, data: ExcelAIQueryData,
                               titles: [Int: String], scope: String, entries: [Entry], ignoredCount: Int) throws -> ExcelAIReadQueryResult {
        let sorted = entries.filter { $0.metric != nil }.sorted { a, b in
            if a.metric! == b.metric! { return a.row < b.row }
            return query.sort == .ascending ? a.metric! < b.metric! : a.metric! > b.metric!
        }
        let winners = Array(sorted.prefix(query.limit ?? 5))
        var lines = [scope]
        let columns = Array(Set(query.selectColumns + [query.metricColumn!])).sorted()
        var rank = 0, previous: Decimal?
        for (offset, entry) in winners.enumerated() {
            if entry.metric != previous { rank = offset + 1 }
            previous = entry.metric
            let values = try columns.map { column -> String in
                let cell = try data.cell(row: entry.row, column: column)
                let text: String
                if column == query.metricColumn {
                    text = try formatted(.init(number: entry.metric!, approximate: false), entries: [entry], query: query, data: data)
                } else {
                    let displayed = cell?.displayValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    text = displayed.isEmpty ? DocumentEngineLocalization.string("빈 셀") : displayed
                }
                return "\(titles[column] ?? ""): \(text)"
            }.joined(separator: ", ")
            lines.append(DocumentEngineLocalization.format("%lld위 · %lld행 — %@", rank, entry.row, values))
        }
        if sorted.isEmpty { lines.append(DocumentEngineLocalization.string("계산할 숫자가 없습니다.")) }
        else { lines.append(DocumentEngineLocalization.format("숫자가 있는 %lld행 중 %lld행을 표시했습니다.", sorted.count, winners.count)) }
        if sorted.count > winners.count, sorted[winners.count].metric == winners.last?.metric {
            lines.append(DocumentEngineLocalization.string("마지막 순위와 같은 값이 더 있습니다. 동점은 원래 행 순서로 표시했습니다."))
        }
        if ignoredCount > 0 { lines.append(DocumentEngineLocalization.format("빈 셀·텍스트 등 숫자가 아닌 %lld셀은 계산에서 제외했습니다.", ignoredCount)) }
        return .init(rows: winners.map(\.row), answer: lines.joined(separator: "\n"), references: references(rows: winners.map(\.row), columns: Set(columns + query.filters.map(\.column)), sheet: data.sheet, snapshot: snapshot))
    }

    private static func validateUnits(_ entries: [Entry], data: ExcelAIQueryData) throws {
        let units = Set(entries.filter { $0.metric != nil }.compactMap { entry -> String? in
            guard let cell = entry.metricCell else { return nil }
            if let currency = data.currency(cell) { return currency.symbol }
            if let kind = data.format(cell), [.percent, .date, .time].contains(kind) { return kind.rawValue }
            return nil
        })
        if units.count > 1 { throw ExcelAIReadQueryError.mixedUnits }
    }

    private static func key(_ cell: ExcelCell?) throws -> Key {
        guard let cell else { return .blank }
        let text = cell.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .blank }
        if cell.cellType == nil || cell.cellType == "n" {
            guard let value = ExcelAIReadQueryExecutor.decimal(text) else { throw ExcelAIReadQueryError.arithmeticOverflow }
            return .number(value)
        }
        if cell.cellType == "b" { return .boolean(text) }
        return .text(text.precomposedStringWithCanonicalMapping.lowercased())
    }
    public static func aggregate(_ operation: ExcelAIReadQuery.Operation, values: [Decimal]) throws -> Value? {
        guard !values.isEmpty else { return nil }
        if operation == .minimum { return .init(number: values.min()!, approximate: false) }
        if operation == .maximum { return .init(number: values.max()!, approximate: false) }
        var total = Decimal.zero
        for var value in values {
            var output = Decimal.zero
            guard NSDecimalAdd(&output, &total, &value, .plain) == .noError else { throw ExcelAIReadQueryError.arithmeticOverflow }
            total = output
        }
        if operation == .average {
            var count = Decimal(values.count), output = Decimal.zero
            let error = NSDecimalDivide(&output, &total, &count, .plain)
            guard error == .noError || error == .lossOfPrecision else { throw ExcelAIReadQueryError.arithmeticOverflow }
            return .init(number: output, approximate: error == .lossOfPrecision)
        }
        return .init(number: total, approximate: false)
    }
    private static func formatted(_ value: Value, entries: [Entry], query: ExcelAIReadQuery, data: ExcelAIQueryData) throws -> String {
        let cells = entries.compactMap(\.metricCell)
        let allPercent = !cells.isEmpty && cells.allSatisfy { data.format($0) == .percent }
        if [.minimum, .maximum, .rank].contains(query.operation),
           let cell = entries.first(where: { $0.metric == value.number })?.metricCell,
           let format = data.format(cell), [.date, .time].contains(format) { return cell.displayValue }
        let currencies = cells.compactMap { data.currency($0) }
        let currencySymbols = Set(currencies.map(\.symbol))
        if currencySymbols.count > 1 || (!currencies.isEmpty && cells.contains { data.format($0) == .percent }) {
            throw ExcelAIReadQueryError.mixedUnits
        }
        let currency = currencies.count == cells.count && currencySymbols.count == 1 ? (symbol: currencies[0].symbol, places: currencies.map(\.places).max()!) : nil
        var raw = value.number
        if allPercent {
            var factor = Decimal(100), scaled = Decimal.zero
            guard NSDecimalMultiply(&scaled, &raw, &factor, .plain) == .noError else { throw ExcelAIReadQueryError.arithmeticOverflow }
            raw = scaled
        }
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &raw, currency?.places ?? 12, .plain)
        let text = NSDecimalNumber(decimal: rounded).stringValue
        // Never silently round a small nonzero number to zero.
        let display = rounded == 0 && raw != 0 ? NSDecimalNumber(decimal: raw).stringValue : text
        if let currency {
            let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
            let signed = String(pieces[0]), sign = signed.hasPrefix("-") ? "-" : ""
            let digits = Array(signed.trimmingCharacters(in: CharacterSet(charactersIn: "-")).reversed())
            let integer = stride(from: 0, to: digits.count, by: 3).map { String(digits[$0..<min($0 + 3, digits.count)].reversed()) }.reversed().joined(separator: ",")
            let fraction = pieces.count > 1 ? String(pieces[1]) : ""
            let tail = currency.places > 0 ? "." + fraction + String(repeating: "0", count: max(0, currency.places - fraction.count)) : ""
            return sign + currency.symbol + integer + tail
        }
        let approximate = value.approximate || (rounded != raw && rounded != 0)
        return (approximate ? "≈ " : "") + display + (allPercent ? "%" : "")
    }
    private static func operationLabel(_ operation: ExcelAIReadQuery.Operation) -> String {
        switch operation {
        case .sum: DocumentEngineLocalization.string("합계")
        case .average: DocumentEngineLocalization.string("평균")
        case .minimum: DocumentEngineLocalization.string("최솟값")
        case .maximum: DocumentEngineLocalization.string("최댓값")
        case .distinctCount: DocumentEngineLocalization.string("중복 제외 개수")
        default: DocumentEngineLocalization.string("행 개수")
        }
    }
    private static func conditionDescription(_ query: ExcelAIReadQuery, titles: [Int: String]) -> String {
        let separator = query.match == .all ? DocumentEngineLocalization.string(" 그리고 ") : DocumentEngineLocalization.string(" 또는 ")
        let conditions = query.filters.map { "\(titles[$0.column] ?? "") \($0.comparison.label) \($0.value)" }.joined(separator: separator)
        let base = conditions.isEmpty ? DocumentEngineLocalization.string("전체 데이터") : conditions
        let visibility = DocumentEngineLocalization.string(query.visibleOnly ? "보이는 행 기준" : "숨겨진 행 포함")
        return (query.inputScope == nil ? "" : DocumentEngineLocalization.string("이전 결과에서 ")) + base + " · " + visibility
    }
    private static func references(rows: [Int], columns: Set<Int>, sheet: ExcelWorksheet, snapshot: ExcelAIWorkbookSnapshot) -> ExcelAIReferences? {
        let addresses = Set(rows.flatMap { row in columns.compactMap { column -> ExcelCellAddress? in
            let address = sheet.canonicalAddress(for: .init(row: row, column: column))
            return sheet.cell(at: address) == nil ? nil : address
        }}).sorted()
        return addresses.isEmpty ? nil : .init(sheetPartPath: snapshot.sheetPartPath, sheetName: snapshot.sheetName, addresses: addresses)
    }
}
