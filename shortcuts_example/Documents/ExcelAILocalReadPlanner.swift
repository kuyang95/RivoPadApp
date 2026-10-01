import Foundation

/// Builds a read-only lookup for explicitly named
/// condition/result columns. Ambiguous questions continue to the model planner.
nonisolated enum ExcelAILocalReadPlanner {
    static func query(
        in snapshot: ExcelAIWorkbookSnapshot,
        request: String,
        history: [ExcelAIChatTurn] = []
    ) -> ExcelAIReadQuery? {
        guard snapshot.supportsLocalQueries,
              let sheet = snapshot.localQuerySheet else {
            return nil
        }
        let folded = request.lowercased()
        let lookupCues = [
            "알려줘", "알려주세요", "보여줘", "보여주세요", "찾아줘",
            "있어", "있나요", "있니", "몇", "which", "show", "find",
            "is there", "how many",
        ]
        let editCues = [
            "바꿔", "변경", "수정", "지워", "삭제", "추가", "넣어",
            "정렬", "필터", "서식", "강조", "replace", "change", "delete",
        ]
        guard lookupCues.contains(where: folded.contains),
              !editCues.contains(where: folded.contains) else {
            return nil
        }

        let compactRequest = compact(request)
        let isFollowup = [
            "그중", "이중", "그가운데", "이가운데", "amongthose",
            "ofthose", "amongthem",
        ].contains(where: compactRequest.hasPrefix)
        let previousQuery = isFollowup
            ? history.reversed().first(where: {
                $0.role == "assistant" && $0.query?.resultScope != nil
            })?.query
            : nil
        if isFollowup && previousQuery == nil {
            return nil
        }
        let countCue = ["몇건", "몇개", "몇행", "howmany"]
            .contains(where: compactRequest.contains)
            || folded.range(
                of: #"\bcount\b"#,
                options: .regularExpression
            ) != nil

        let candidates = snapshot.regions.compactMap { region -> ExcelAIReadQuery? in
            if let previousQuery, previousQuery.regionID != region.id {
                return nil
            }
            var filters = [ExcelAIReadQuery.Filter]()
            var mentionedColumns = [Int]()
            var hasDisjunction = false
            for column in region.columns {
                let aliases = aliases(for: column.title)
                guard aliases.contains(where: {
                    containsAlias($0, in: request)
                }) else {
                    continue
                }
                mentionedColumns.append(column.number)
                if let result = Self.filters(
                    for: column,
                    aliases: aliases,
                    request: request,
                    region: region,
                    sheet: sheet
                ) {
                    filters.append(contentsOf: result.filters)
                    hasDisjunction = hasDisjunction || result.isDisjunction
                }
            }
            guard !hasDisjunction || Set(filters.map(\.column)).count == 1 else {
                return nil
            }
            let filterColumns = Set(filters.map(\.column))
            var selectColumns = mentionedColumns.filter {
                !filterColumns.contains($0)
            }
            if let previousQuery {
                for column in previousQuery.filters.map(\.column)
                    + previousQuery.selectColumns
                where !filterColumns.contains(column)
                    && !selectColumns.contains(column) {
                    selectColumns.append(column)
                }
            }
            let operation: ExcelAIReadQuery.Operation = previousQuery == nil
                && countCue ? .count : .rows
            guard !filters.isEmpty,
                  operation != .rows || !selectColumns.isEmpty else {
                return nil
            }
            var query = ExcelAIReadQuery(
                operation: operation,
                regionID: region.id,
                match: hasDisjunction ? .any : .all,
                filters: filters,
                selectColumns: selectColumns
            )
            query.inputScope = previousQuery?.resultScope
            return query
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private struct FilterResult {
        let filters: [ExcelAIReadQuery.Filter]
        let isDisjunction: Bool
    }

    private static func filters(
        for column: ExcelAIWorkbookSnapshot.Region.Column,
        aliases: [String],
        request: String,
        region: ExcelAIWorkbookSnapshot.Region,
        sheet: ExcelWorksheet
    ) -> FilterResult? {
        let numericCells = region.dataRows.prefix(20).compactMap {
            sheet.cell(at: ExcelCellAddress(row: $0, column: column.number))
        }.filter { !$0.rawValue.isEmpty }
        let isNumeric = !numericCells.isEmpty && numericCells.allSatisfy {
            ($0.cellType == nil || $0.cellType == "n")
                && Decimal(string: $0.rawValue) != nil
        }
        for alias in aliases.sorted(by: { $0.count > $1.count }) {
            let lead = aliasPattern(alias)
                + #"\s*(?:열\s*)?(?:값\s*)?(?:가|이|은|는)?\s*"#
            if isNumeric {
                let number = #"([+-]?(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]+)?)"#
                let either = lead + number
                    + #"\s*(?:원|개|점|명|대)?\s*(?:또는|혹은|or)\s*"#
                    + number
                    + #"\s*(?:원|개|점|명|대)?\s*(?:이고|인|와\s*같은|과\s*같은)"#
                if let parts = captures(either, in: request),
                   parts.count >= 2 {
                    return FilterResult(filters: parts.prefix(2).map {
                        .init(
                            column: column.number,
                            comparison: .equals,
                            valueType: .number,
                            value: $0.replacingOccurrences(of: ",", with: "")
                        )
                    }, isDisjunction: true)
                }
                let pattern = lead + number
                    + #"\s*(?:원|개|점|명|대)?\s*(>=|<=|!=|==|=|>|<|≥|≤|≠|이상|이하|초과|미만|이고|인|와\s*같은|과\s*같은)"#
                if let parts = captures(pattern, in: request),
                   parts.count >= 2 {
                    return FilterResult(
                        filters: [.init(
                            column: column.number,
                            comparison: comparison(parts[1]),
                            valueType: .number,
                            value: parts[0].replacingOccurrences(of: ",", with: "")
                        )],
                        isDisjunction: false
                    )
                }
            } else {
                let value = #"[‘’'\"]?([\p{L}\p{N}_\-.]+)[‘’'\"]?"#
                let precedingValue = value
                    + #"\s*"# + aliasPattern(alias)
                    + #"\s*(?:에\s*)?(?:있는|인|이고)"#
                if let parts = captures(precedingValue, in: request),
                   let captured = parts.first {
                    return FilterResult(
                        filters: [.init(
                            column: column.number,
                            comparison: .equals,
                            valueType: .text,
                            value: captured
                        )],
                        isDisjunction: false
                    )
                }
                let either = lead + value
                    + #"\s*(?:또는|혹은|or)\s*"# + value
                    + #"\s*(?:이고|인|와\s*같은|과\s*같은)"#
                if let parts = captures(either, in: request),
                   parts.count >= 2 {
                    return FilterResult(filters: parts.prefix(2).map {
                        .init(
                            column: column.number,
                            comparison: .equals,
                            valueType: .text,
                            value: $0
                        )
                    }, isDisjunction: true)
                }
                let pattern = lead + value
                    + #"\s*(==|=|!=|≠|이고|인|와\s*같은|과\s*같은)"#
                if let parts = captures(pattern, in: request),
                   parts.count >= 2 {
                    return FilterResult(
                        filters: [.init(
                            column: column.number,
                            comparison: comparison(parts[1]),
                            valueType: .text,
                            value: parts[0]
                        )],
                        isDisjunction: false
                    )
                }
            }
        }
        return nil
    }

    private static func comparison(
        _ token: String
    ) -> ExcelAIReadQuery.Filter.Comparison {
        switch token.filter({ !$0.isWhitespace }) {
        case ">=", "≥", "이상": return .greaterThanOrEqual
        case "<=", "≤", "이하": return .lessThanOrEqual
        case ">", "초과": return .greaterThan
        case "<", "미만": return .lessThan
        case "!=", "≠": return .notEqual
        default: return .equals
        }
    }

    private static func aliases(for title: String) -> [String] {
        let compactTitle = compact(title)
        var values = [title]
        func add(_ aliases: [String]) {
            for alias in aliases where !values.contains(alias) {
                values.append(alias)
            }
        }
        if compactTitle.contains("product") || compactTitle.contains("제품")
            || compactTitle.contains("품목") || compactTitle.contains("상품") {
            add(["product", "제품", "품목", "상품"])
        }
        if compactTitle.contains("country") || compactTitle.contains("국가")
            || compactTitle.contains("나라") {
            add(["country", "국가", "나라"])
        }
        if compactTitle.contains("unitssold") || compactTitle.contains("판매수량")
            || compactTitle.contains("재고수량") {
            add(["units sold", "판매 수량", "판매수량", "재고 수량", "재고수량"])
        }
        if compactTitle.contains("employee") || compactTitle.contains("직원") {
            add(["employee", "직원"])
        }
        if compactTitle == "name" || compactTitle.contains("이름") {
            add(["name", "이름"])
        }
        return values
    }

    private static func containsAlias(
        _ alias: String,
        in request: String
    ) -> Bool {
        let value = compact(alias)
        return !value.isEmpty && compact(request).contains(value)
    }

    private static func compact(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).filter { $0.isLetter || $0.isNumber }
    }

    private static func aliasPattern(_ alias: String) -> String {
        let pieces = alias.split(whereSeparator: \.isWhitespace).map {
            NSRegularExpression.escapedPattern(for: String($0))
        }
        return #"(?<![\p{L}\p{N}_])"#
            + pieces.joined(separator: #"\s*"#)
    }

    private static func captures(
        _ pattern: String,
        in text: String
    ) -> [String]? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ), let match = regex.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ) else {
            return nil
        }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).map {
                String(text[$0])
            }
        }
    }
}
