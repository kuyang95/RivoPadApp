import Foundation

/// Counts come from the loaded sheet, not the model's truncated cell context.
/// Full addresses stay local; only compact group metadata is sent to the model.
nonisolated struct ExcelAIValueGroup: Encodable, Sendable {
    let id: String
    let regionID: String
    let column: Int
    let header: String
    let value: String
    let count: Int
    let addresses: [ExcelCellAddress]

    private enum CodingKeys: String, CodingKey {
        case id, regionID, column, header, value, count
    }

    static func make(
        sheet: ExcelWorksheet,
        regions: [ExcelAccessibleRegion]
    ) -> [Self] {
        // A window cannot establish complete counts for an entire sheet.
        guard !sheet.isWindowed, !sheet.didTruncate else { return [] }
        var result: [Self] = []
        for region in regions {
            for column in region.columns {
                var matches: [String: [ExcelCellAddress]] = [:]
                for row in ExcelAIQueryData.dataRows(region.rowNumbers, regionID: region.id, sheet: sheet) {
                    let address = ExcelCellAddress(row: row, column: column.column)
                    guard sheet.canonicalAddress(for: address) == address,
                          let cell = sheet.cell(at: address),
                          cell.formula?.isEmpty != false,
                          ["s", "inlineStr", "str"].contains(cell.cellType ?? "")
                    else { continue }
                    let value = cell.displayValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty, value.count <= 120 else { continue }
                    matches[value, default: []].append(address)
                }
                // Keep categorical columns compact, without truncating a group's count.
                guard matches.count <= 40 else { continue }
                for value in matches.keys.sorted() {
                    guard result.count < 240 else { return result }
                    let addresses = matches[value, default: []].sorted()
                    result.append(Self(
                        id: "value-\(result.count + 1)", regionID: region.id,
                        column: column.column, header: column.title, value: value,
                        count: addresses.count, addresses: addresses
                    ))
                }
            }
        }
        return result
    }
}

nonisolated struct ExcelAIReferences: Equatable, Sendable {
    struct Sheet: Equatable, Sendable {
        let sheetPartPath: String
        let sheetName: String
        let addresses: [ExcelCellAddress]
    }

    let sheetPartPath: String
    let sheetName: String
    let addresses: [ExcelCellAddress]
    var additionalSheets: [Sheet] = []

    var sheets: [Sheet] {
        [.init(sheetPartPath: sheetPartPath, sheetName: sheetName, addresses: addresses)] + additionalSheets
    }

    var totalAddressCount: Int { sheets.reduce(0) { $0 + $1.addresses.count } }

    static func combining(_ references: [Self]) -> Self? {
        var order: [String] = []
        var names: [String: String] = [:]
        var addresses: [String: Set<ExcelCellAddress>] = [:]
        for reference in references {
            for sheet in reference.sheets {
                if names[sheet.sheetPartPath] == nil { order.append(sheet.sheetPartPath) }
                names[sheet.sheetPartPath] = sheet.sheetName
                addresses[sheet.sheetPartPath, default: []].formUnion(sheet.addresses)
            }
        }
        guard let first = order.first else { return nil }
        let groups = order.map { path in
            Sheet(sheetPartPath: path, sheetName: names[path] ?? "", addresses: addresses[path, default: []].sorted())
        }.filter { !$0.addresses.isEmpty }
        guard let primary = groups.first else { return nil }
        return .init(sheetPartPath: primary.sheetPartPath, sheetName: primary.sheetName,
                     addresses: primary.addresses, additionalSheets: Array(groups.dropFirst()))
    }

    static func resolve(
        command: ExcelAICommandPlan,
        snapshot: ExcelAIWorkbookSnapshot,
        userRequest: String = "",
        appliedPlan: ExcelAIValidatedPlan? = nil
    ) -> Self? {
        guard command.intent != .clarify else { return nil }
        if command.intent == .answer, let query = command.query, query.operation != .none {
            return (try? ExcelAIReadQueryExecutor.execute(query, snapshot: snapshot))?.references
        }
        if let group = countGroup(command: command, snapshot: snapshot, userRequest: userRequest) {
            // Count evidence is exactly the population that was counted, even if
            // the model also mentions headers or unrelated sample cells.
            return Self(sheetPartPath: snapshot.sheetPartPath, sheetName: snapshot.sheetName,
                        addresses: group.addresses)
        }
        let knownCells = Set(snapshot.cells.compactMap { ExcelCellAddress($0.address) })
        var addresses = Set(command.referencedCells.compactMap { reference -> ExcelCellAddress? in
            guard let address = ExcelCellAddress(reference), knownCells.contains(address) else { return nil }
            return snapshot.canonicalAddress(row: address.row, column: address.column)
        })
        let groupIDs = Set(command.referencedGroupIDs + [command.countGroupID].compactMap { $0 })
        for group in snapshot.valueGroups where groupIDs.contains(group.id) {
            addresses.formUnion(group.addresses)
        }
        if let plan = appliedPlan {
            addresses.formUnion(plan.edits.map {
                snapshot.canonicalAddress(row: $0.row, column: $0.column)
            })
            addresses.formUnion(plan.actions.flatMap(\.addresses))
            var nextRowByRegion: [String: Int] = [:]
            for appended in plan.appendedRows {
                guard let region = snapshot.region(id: appended.regionID),
                      let range = ExcelCellRange(region.range) else { continue }
                // The apply path appends after the region's current data extent.
                let row = nextRowByRegion[region.id] ?? (range.end.row + 1)
                nextRowByRegion[region.id] = row + 1
                addresses.formUnion(appended.values.map {
                    ExcelCellAddress(row: row, column: $0.column)
                })
            }
            for table in plan.createdTables {
                addresses.formUnion(table.headers.indices.map {
                    ExcelCellAddress(row: table.startRow, column: table.startColumn + $0)
                })
            }
        }
        guard !addresses.isEmpty else { return nil }
        return Self(sheetPartPath: snapshot.sheetPartPath, sheetName: snapshot.sheetName,
                    addresses: addresses.sorted())
    }

    static func answerText(command: ExcelAICommandPlan, snapshot: ExcelAIWorkbookSnapshot,
                           userRequest: String = "") throws -> String {
        if command.intent == .answer, let query = command.query,
           let result = try ExcelAIReadQueryExecutor.execute(query, snapshot: snapshot) {
            return result.answer
        }
        if command.intent == .answer, let id = command.countGroupID, !id.isEmpty,
           !snapshot.valueGroups.contains(where: { $0.id == id }) {
            throw ExcelAICommandValidationError.invalidResponse
        }
        guard let group = countGroup(command: command, snapshot: snapshot, userRequest: userRequest) else {
            return command.assistantMessage
        }
        return AppLocalization.format("%@ 항목은 총 %lld개입니다.", group.value, group.count)
    }

    static func countGroup(command: ExcelAICommandPlan, snapshot: ExcelAIWorkbookSnapshot,
                           userRequest: String) -> ExcelAIValueGroup? {
        guard command.intent == .answer else { return nil }
        if let id = command.countGroupID, !id.isEmpty {
            return snapshot.valueGroups.first { $0.id == id }
        }
        guard Set(command.referencedGroupIDs).count <= 1 else { return nil }
        return ExcelAILocalCountRequest.group(in: snapshot, request: userRequest)
    }
}

/// A conservative local route for a single categorical value's occurrence count.
/// Unrecognized words or a second condition leave the request to the AI route.
nonisolated enum ExcelAILocalCountRequest {
    private static func compact(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static let countCues = ["몇개", "몇건", "몇행", "몇줄", "개수", "갯수", "건수", "행수", "howmany", "numberofrows", "count", "何件", "何個", "件数", "個数"]
    private static let countPhrases = (countCues + [
        "알려주세요", "알려줘", "보여주세요", "보여줘", "해당하는", "나오는", "들어있는", "있는",
        "몇번나와", "몇번", "정확히", "총", "전체", "모두", "항목", "데이터", "시트", "나라", "국가", "제품", "행", "열",
        "에서", "에는", "으로", "은", "는", "이", "가", "을", "를", "의", "에", "인", "개", "건", "야", "인지", "인가요", "입니까", "있어", "있나요", "있니", "요",
        "please", "tellme", "entries", "entry", "records", "record", "rows", "row", "column", "occurrences", "occur", "arethere", "thereare", "the", "in", "of", "total", "all",
        "全部で", "合計", "ありますか", "ですか", "は", "の", "行", "列", "商品", "国", "件", "個",
    ]).sorted { $0.count > $1.count }

    // Foundation supplies localized names for every ISO region. No country names,
    // workbook names, cell addresses or expected counts are embedded here.
    private static let regionAliases: [String: Set<String>] = {
        let locales = [Locale(identifier: "en_US"), Locale(identifier: "ko_KR"), Locale(identifier: "ja_JP")]
        var result: [String: Set<String>] = [:]
        for region in Locale.Region.isoRegions {
            let names = Set(locales.compactMap { $0.localizedString(forRegionCode: region.identifier) }.map(compact))
            for name in names { result[name, default: []].formUnion(names) }
        }
        return result
    }()

    static func group(in snapshot: ExcelAIWorkbookSnapshot, request: String) -> ExcelAIValueGroup? {
        let text = compact(request)
        guard countCues.contains(where: text.contains) else { return nil }
        let candidates = snapshot.valueGroups.filter { group in
            let value = compact(group.value)
            let aliases = regionAliases[value] ?? [value]
            return aliases.contains { alias in
                guard !alias.isEmpty, text.contains(alias) else { return false }
                var remaining = text.replacingOccurrences(of: alias, with: "")
                let header = compact(group.header)
                if !header.isEmpty { remaining = remaining.replacingOccurrences(of: header, with: "") }
                for phrase in countPhrases { remaining = remaining.replacingOccurrences(of: phrase, with: "") }
                return remaining.isEmpty
            }
        }
        return candidates.count == 1 ? candidates.first : nil
    }
}
