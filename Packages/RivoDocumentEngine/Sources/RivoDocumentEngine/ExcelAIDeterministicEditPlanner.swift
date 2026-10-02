import Foundation

/// Handles explicit, mechanically verifiable spreadsheet commands without
/// asking the language model to reproduce the workbook-operation JSON schema.
/// Ambiguous requests deliberately fall through to the regular AI planner.
public nonisolated enum ExcelAIDeterministicEditPlanner {
    private struct ExplicitRange {
        let value: ExcelCellRange
        let prefix: String
        let suffix: String
    }

    public static func plan(
        userRequest: String,
        snapshot: ExcelAIWorkbookSnapshot
    ) -> ExcelAICommandPlan? {
        guard snapshot.supportsEdits,
              !snapshot.worksheetIsProtected else {
            return nil
        }

        if let plan = multipleExplicitCellValuesPlan(request: userRequest) {
            return plan
        }
        if let plan = implicitMultiplicationFormulaPlan(
            request: userRequest,
            snapshot: snapshot
        ) {
            return plan
        }
        if let plan = implicitColumnActionsPlan(
            request: userRequest,
            snapshot: snapshot
        ) {
            return plan
        }
        if let plan = explicitBlankTablePlan(
            request: userRequest,
            snapshot: snapshot
        ) {
            return plan
        }

        let parsedExplicitRange = explicitRange(in: userRequest)
        if let range = parsedExplicitRange?.value,
           let plan = sequentialSingleColumnFillPlan(
               request: userRequest,
               range: range
           ) {
            return plan
        }

        guard snapshot.localWorkbook != nil,
              snapshot.workbookContext?.supportedOperations.isEmpty == false,
              let explicitRange = parsedExplicitRange else {
            return nil
        }

        if let plan = literalTableFillPlan(
            request: userRequest,
            range: explicitRange.value,
            snapshot: snapshot
        ) {
            return plan
        }

        if let plan = directCellValuePlan(
            request: userRequest,
            suffix: explicitRange.suffix,
            range: explicitRange.value,
            snapshot: snapshot
        ) {
            return plan
        }
        if let plan = aggregateFormulaPlan(
            request: userRequest,
            prefix: explicitRange.prefix,
            sourceRange: explicitRange.value
        ) {
            return plan
        }
        if let plan = dropdownPlan(
            request: userRequest,
            suffix: explicitRange.suffix,
            range: explicitRange.value,
            snapshot: snapshot
        ) {
            return plan
        }
        if let plan = conditionalFormattingPlan(
            request: userRequest,
            range: explicitRange.value,
            snapshot: snapshot
        ) {
            return plan
        }
        if let plan = numberFormatPlan(
            request: userRequest,
            range: explicitRange.value,
            snapshot: snapshot
        ) {
            return plan
        }
        if let plan = replacePlan(
            request: userRequest,
            suffix: explicitRange.suffix,
            range: explicitRange.value,
            snapshot: snapshot
        ) {
            return plan
        }
        if let plan = sortPlan(
            request: userRequest,
            range: explicitRange.value,
            snapshot: snapshot
        ) {
            return plan
        }
        if let plan = filterPlan(
            request: userRequest,
            range: explicitRange.value,
            snapshot: snapshot
        ) {
            return plan
        }
        if let plan = formatAndFreezePlan(
            request: userRequest,
            range: explicitRange.value,
            snapshot: snapshot
        ) {
            return plan
        }
        if let plan = chartPlan(
            request: userRequest,
            range: explicitRange.value,
            snapshot: snapshot
        ) {
            return plan
        }
        return nil
    }

    private static func multipleExplicitCellValuesPlan(
        request: String
    ) -> ExcelAICommandPlan? {
        guard request.contains("다른 셀은 건드리지 마") else { return nil }
        let assignments = allCaptures(
            #"(?<![A-Za-z0-9_])([A-Za-z]{1,3}\d{1,7})\s*셀(?:에|은|에는)\s*['‘’\"]([^'‘’\"]*)['‘’\"]"#,
            in: request
        )
        guard assignments.count >= 2 else { return nil }
        var edits = [ExcelAICommandPlan.Edit]()
        var addresses = Set<ExcelCellAddress>()
        for assignment in assignments {
            guard assignment.count >= 2,
                  let address = ExcelCellAddress(assignment[0].uppercased()),
                  addresses.insert(address).inserted else {
                return nil
            }
            edits.append(.init(
                row: address.row,
                column: address.column,
                newValue: assignment[1]
            ))
        }
        return ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: edits.map {
                ExcelCellAddress(row: $0.row, column: $0.column).reference
            }.joined(separator: ", ") + " 셀에 요청한 값을 입력합니다.",
            edits: edits,
            appendedRows: []
        )
    }

    private static func implicitColumnActionsPlan(
        request: String,
        snapshot: ExcelAIWorkbookSnapshot
    ) -> ExcelAICommandPlan? {
        let foldedRequest = request.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        var actions = [ExcelAICommandPlan.Action]()

        for region in snapshot.regions {
            for column in region.columns where !column.title.isEmpty {
                guard foldedRequest.localizedCaseInsensitiveContains(column.title) else {
                    continue
                }
                let clause = requestClause(
                    containing: column.title,
                    in: request
                )
                let target = ExcelAICommandPlan.Action.Target(
                    scope: .column,
                    regionID: region.id,
                    row: nil,
                    column: column.number
                )

                if request.contains("드롭다운") {
                    let title = NSRegularExpression.escapedPattern(
                        for: column.title
                    )
                    if let valueText = captures(
                        "\(title)\\s*열(?:의)?(?:\\s*데이터\\s*셀)?(?:에는|에)\\s*(.+?)\\s*(?:중에서\\s*고르는\\s*)?드롭다운",
                        in: request
                    )?.first {
                        let values = valueText.split(separator: ",")
                            .map { cleaned(String($0)) }
                            .filter { !$0.isEmpty }
                        if values.count >= 2,
                           Set(values).count == values.count {
                            actions.append(.init(
                                type: .setDropdown,
                                target: target,
                                values: values,
                                allowsBlank: true
                            ))
                        }
                    }
                }

                if request.contains("텍스트 포함") {
                    let sentence = request.components(separatedBy: ".")
                        .first(where: {
                            $0.localizedCaseInsensitiveContains(column.title)
                        }) ?? request
                    for parts in allCaptures(
                        #"['‘’]([^'‘’]+)['‘’]\s*(?:을|를)?\s*포함하는\s*셀은\s*(빨간색|빨강|노란색|노랑|초록색|초록)"#,
                        in: sentence
                    ) where parts.count >= 2 {
                        guard let highlight = conditionalHighlight(
                            in: parts[1]
                        ) else {
                            continue
                        }
                        actions.append(.init(
                            type: .setConditionalFormatting,
                            target: target,
                            condition: ExcelConditionalRuleKind
                                .containsText.rawValue,
                            comparisonValue: parts[0],
                            highlight: highlight.rawValue
                        ))
                    }
                }

                if clause.contains("표시") || clause.contains("형식") {
                    let format: ExcelNumberFormat?
                    if clause.contains("소수점 둘째") || clause.contains("소수점 2") {
                        format = .decimalTwo
                    } else if clause.contains("소수점 첫째") || clause.contains("소수점 1") {
                        format = .decimalOne
                    } else if clause.contains("날짜") {
                        format = .date
                    } else if clause.contains("정수") || clause.contains("천 단위") {
                        format = .integer
                    } else if clause.contains("백분율") || clause.contains("퍼센트") {
                        format = .percent
                    } else if clause.contains("통화") || clause.contains("원화") {
                        format = .currencyWon
                    } else {
                        format = nil
                    }
                    if let format {
                        actions.append(.init(
                            type: .setNumberFormat,
                            target: target,
                            format: format.rawValue
                        ))
                    }
                }

                if request.contains("강조") || request.contains("색") {
                    let condition: ExcelConditionalRuleKind?
                    let comparisonValue: String?
                    if let parts = captures(
                        #"([+-]?\d[\d,]*(?:\.\d+)?)\s*(이상|이하|초과|미만|보다\s*큰|보다\s*작은)"#,
                        in: clause
                    ), parts.count >= 2 {
                        comparisonValue = parts[0]
                            .replacingOccurrences(of: ",", with: "")
                        switch parts[1].replacingOccurrences(of: " ", with: "") {
                        case "이상": condition = .greaterThanOrEqual
                        case "이하": condition = .lessThanOrEqual
                        case "초과", "보다큰": condition = .greaterThan
                        case "미만", "보다작은": condition = .lessThan
                        default: condition = nil
                        }
                    } else if let text = captures(
                        #"열에서\s*(.+?)\s*(?:과|와)\s*같은\s*값"#,
                        in: clause
                    )?.first {
                        condition = .equalTo
                        comparisonValue = cleaned(text)
                    } else {
                        condition = nil
                        comparisonValue = nil
                    }
                    if let condition, let comparisonValue,
                       let highlight = conditionalHighlight(in: clause) {
                        actions.append(.init(
                            type: .setConditionalFormatting,
                            target: target,
                            condition: condition.rawValue,
                            comparisonValue: comparisonValue,
                            highlight: highlight.rawValue
                        ))
                    }
                }
            }
        }

        guard !actions.isEmpty else { return nil }
        return editPlan(
            message: "요청한 열 표시와 강조 규칙을 적용합니다.",
            actions: actions
        )
    }

    private static func requestClause(
        containing column: String,
        in request: String
    ) -> String {
        let clauses = request.components(separatedBy: ",")
        return clauses.first(where: {
            $0.localizedCaseInsensitiveContains(column)
        }) ?? request
    }

    private static func conditionalHighlight(
        in request: String
    ) -> ExcelConditionalHighlight? {
        if request.contains("빨간") || request.contains("빨강") {
            return .red
        }
        if request.contains("노란") || request.contains("노랑") {
            return .yellow
        }
        if request.contains("초록") {
            return .green
        }
        return nil
    }

    private static func explicitBlankTablePlan(
        request: String,
        snapshot: ExcelAIWorkbookSnapshot
    ) -> ExcelAICommandPlan? {
        let compact = request.lowercased()
        guard compact.contains("표") || compact.contains("테이블"),
              compact.contains("만들") else {
            return nil
        }
        let start: ExcelCellAddress
        let headerCapture: String
        if let parts = captures(
            #"선택한\s*셀\s*([A-Za-z]{1,3}\d{1,7})부터\s*(.+?)\s*열(?:을\s*이\s*순서로\s*가진|\s*하나만\s*있는)"#,
            in: request
        ), parts.count >= 2,
           let address = ExcelCellAddress(parts[0].uppercased()) {
            start = address
            headerCapture = parts[1]
        } else if let headers = captures(
            #"빈\s*시트에\s*(.+?)\s*열(?:을\s*이\s*순서로\s*가진|\s*하나만\s*있는)"#,
            in: request
        )?.first {
            start = ExcelCellAddress(row: 1, column: 1)
            headerCapture = headers
        } else if let selectedCell = snapshot.selectedCell,
                  let selected = ExcelCellAddress(selectedCell),
                  let headers = captures(
                      #"선택한\s*셀(?:부터)?\s*(.+?)\s*열(?:을\s*이\s*순서로\s*가진|\s*하나만\s*있는)"#,
                      in: request
                  )?.first {
            start = selected
            headerCapture = headers
        } else {
            return nil
        }
        let headers = headerCapture
            .split(separator: ",")
            .map { cleaned(String($0)) }
            .filter { !$0.isEmpty }
        guard !headers.isEmpty, Set(headers).count == headers.count else {
            return nil
        }
        let rowCount = captures(
            #"빈\s*데이터\s*행은\s*(?:정확히\s*)?(\d+)\s*개"#,
            in: request
        )?.first.flatMap(Int.init) ?? 5
        guard (1...10_000).contains(rowCount) else { return nil }
        return ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "\(headers.joined(separator: ", ")) 열과 빈 데이터 행 \(rowCount)개가 있는 표를 만듭니다.",
            edits: [],
            appendedRows: [],
            createdTables: [.init(
                startRow: start.row,
                startColumn: start.column,
                headers: headers,
                blankRowCount: rowCount
            )]
        )
    }

    private static func sequentialSingleColumnFillPlan(
        request: String,
        range: ExcelCellRange
    ) -> ExcelAICommandPlan? {
        guard range.start.column == range.end.column,
              let parts = captures(
                  #"표의\s*(\d+)행부터\s*(\d+)행까지\s*(.+?)\s*값을\s*순서대로\s*채워줘[.。]?\s*([\s\S]+)$"#,
                  in: request
              ),
              parts.count >= 4,
              let firstRow = Int(parts[0]),
              let lastRow = Int(parts[1]),
              firstRow <= lastRow,
              firstRow > range.start.row,
              lastRow <= range.end.row else {
            return nil
        }

        let valueCount = lastRow - firstRow + 1
        guard let values = sequentialValues(
            from: parts[3],
            expectedCount: valueCount
        ) else {
            return nil
        }
        let edits = values.enumerated().map { offset, value in
            ExcelAICommandPlan.Edit(
                row: firstRow + offset,
                column: range.start.column,
                newValue: value
            )
        }
        return ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "\(range.reference)의 \(valueCount)개 값을 순서대로 입력합니다.",
            edits: edits,
            appendedRows: []
        )
    }

    private static func sequentialValues(
        from text: String,
        expectedCount: Int
    ) -> [String]? {
        guard expectedCount > 0 else { return nil }
        let quoted = allCaptures(#"['‘’\"]([^'‘’\"]+)['‘’\"]"#, in: text)
            .compactMap(\.first)
            .map(cleaned)
            .filter { !$0.isEmpty }
        if quoted.count == expectedCount {
            return quoted
        }

        if text.contains(",") || text.contains("|") || text.contains("\n") {
            let separated = text.components(separatedBy: CharacterSet(
                charactersIn: ",|\n"
            )).map(cleaned).filter { !$0.isEmpty }
            if separated.count == expectedCount {
                return separated
            }
        }

        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count == expectedCount {
            return words
        }

        // Unquoted English status lists are common in imported templates.
        // Keep connector-led labels such as "Not Started", "In Progress",
        // and "On Hold" together while still requiring the exact row count.
        let compoundLeads: Set<String> = [
            "not", "in", "on", "no", "to", "at", "very",
        ]
        var grouped = [String]()
        var index = 0
        while index < words.count {
            if compoundLeads.contains(words[index].lowercased()),
               index + 1 < words.count {
                grouped.append(words[index] + " " + words[index + 1])
                index += 2
            } else {
                grouped.append(words[index])
                index += 1
            }
        }
        return grouped.count == expectedCount ? grouped : nil
    }

    private static func literalTableFillPlan(
        request: String,
        range: ExcelCellRange,
        snapshot: ExcelAIWorkbookSnapshot
    ) -> ExcelAICommandPlan? {
        guard request.contains("|") && request.contains("채워"),
              let region = snapshot.regions.first(where: {
                  $0.range == range.reference
              }) else {
            return nil
        }
        let blankColumns = Set(region.columns.compactMap { column -> Int? in
            let title = NSRegularExpression.escapedPattern(for: column.title)
            guard captures(
                "(\(title))\\s*열은\\s*(?:아직\\s*)?비워",
                in: request
            ) != nil else {
                return nil
            }
            return column.number
        })
        let inputColumns = Array(range.start.column...range.end.column)
            .filter { !blankColumns.contains($0) }
        let lines = request.components(separatedBy: .newlines)
        let rows = lines.compactMap { line -> (row: Int?, values: [String])? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.contains("채워줘"),
                  !trimmed.contains("각 줄은") else {
                return nil
            }
            var valueText = trimmed
            var explicitRow: Int?
            if let parts = captures(#"^\s*(\d+)행:\s*(.*)$"#, in: trimmed),
               parts.count >= 2,
               let row = Int(parts[0]) {
                explicitRow = row
                valueText = parts[1]
            }
            let values: [String]
            if valueText.contains("|") {
                values = valueText.split(
                separator: "|",
                omittingEmptySubsequences: false
                ).map { String($0).trimmingCharacters(in: .whitespaces) }
            } else if inputColumns.count == 1 {
                values = [valueText]
            } else {
                return nil
            }
            return values.count == inputColumns.count
                ? (explicitRow, values)
                : nil
        }
        let availableRows = Array(range.start.row + 1...range.end.row)
        guard !rows.isEmpty, rows.count <= availableRows.count else {
            return nil
        }
        var edits = [ExcelAICommandPlan.Edit]()
        var usedRows = Set<Int>()
        for (rowOffset, item) in rows.enumerated() {
            let row = item.row ?? availableRows[rowOffset]
            guard availableRows.contains(row), usedRows.insert(row).inserted else {
                return nil
            }
            let values = item.values
            for (columnOffset, value) in values.enumerated() {
                edits.append(.init(
                    row: row,
                    column: inputColumns[columnOffset],
                    newValue: value
                ))
            }
        }

        var actions = [ExcelAICommandPlan.Action]()
        if request.contains("소수점 둘째 자리") || request.contains("소수점 2자리"),
           let column = requestedColumn(
               in: request,
               range: range,
               snapshot: snapshot
           ) {
            actions.append(.init(
                type: .setNumberFormat,
                target: .init(
                    scope: .column,
                    regionID: region.id,
                    row: nil,
                    column: column
                ),
                format: ExcelNumberFormat.decimalTwo.rawValue
            ))
        }
        return ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "\(range.reference)의 빈 데이터 행 \(rows.count)개를 입력합니다.",
            edits: edits,
            appendedRows: [],
            actions: actions
        )
    }

    private static func implicitMultiplicationFormulaPlan(
        request: String,
        snapshot: ExcelAIWorkbookSnapshot
    ) -> ExcelAICommandPlan? {
        let compact = request.lowercased().filter {
            !$0.isWhitespace && !$0.isPunctuation
        }
        let asksForCalculation = compact.contains("자동계산")
            || compact.contains("알아서계산")
            || compact.contains("곱하기")
            || compact.contains("곱한")
            || compact.contains("multiply")
        guard asksForCalculation else { return nil }

        let targetAliases = ["금액", "합계", "total", "amount"]
        let quantityAliases = ["수량", "개수", "quantity", "qty"]
        let unitPriceAliases = ["단가", "가격", "unitprice", "price"]

        for region in snapshot.regions {
            guard let target = region.columns.first(where: {
                Self.matchesHeader($0.title, aliases: targetAliases)
            }),
            compact.contains(Self.normalizedHeader(target.title)),
            let quantity = region.columns.first(where: {
                Self.matchesHeader($0.title, aliases: quantityAliases)
            }),
            let unitPrice = region.columns.first(where: {
                Self.matchesHeader($0.title, aliases: unitPriceAliases)
            }),
            !region.dataRows.isEmpty else {
                continue
            }

            let edits = region.dataRows.map { row in
                ExcelAICommandPlan.Edit(
                    row: row,
                    column: target.number,
                    newValue: "=\(quantity.letter)\(row)*\(unitPrice.letter)\(row)"
                )
            }
            return ExcelAICommandPlan(
                intent: .edit,
                assistantMessage: "\(target.title) 열을 \(quantity.title) × \(unitPrice.title) 수식으로 계산합니다.",
                edits: edits,
                appendedRows: []
            )
        }
        return nil
    }

    private static func matchesHeader(
        _ header: String,
        aliases: [String]
    ) -> Bool {
        let normalized = normalizedHeader(header)
        return aliases.contains { normalized == normalizedHeader($0) }
    }

    private static func normalizedHeader(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func directCellValuePlan(
        request: String,
        suffix: String,
        range: ExcelCellRange,
        snapshot: ExcelAIWorkbookSnapshot
    ) -> ExcelAICommandPlan? {
        guard range.start == range.end,
              request.contains("값"),
              request.contains("바꿔") || request.contains("변경")
                || request.contains("수정") || request.contains("입력"),
              snapshot.region(
                  containingRow: range.start.row,
                  column: range.start.column
              ) != nil,
              let parts = captures(
                  #"^\s*(?:셀\s*)?(?:의\s*)?값(?:을|를)?\s*[‘’'\"]?(.+?)[‘’'\"]?\s*(?:으로|로)\s*(?:바꿔|변경|수정|입력)"#,
                  in: suffix
              ),
              let captured = parts.first else {
            return nil
        }
        let value = cleaned(captured)
        guard !value.isEmpty else { return nil }
        return ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "\(range.start.reference) 셀 값을 \(value)(으)로 바꿉니다.",
            edits: [.init(
                row: range.start.row,
                column: range.start.column,
                newValue: value
            )],
            appendedRows: []
        )
    }

    private static func aggregateFormulaPlan(
        request: String,
        prefix: String,
        sourceRange: ExcelCellRange
    ) -> ExcelAICommandPlan? {
        guard request.contains("수식") || request.lowercased().contains("formula") else {
            return nil
        }
        let function: String?
        if request.contains("합계") || request.lowercased().contains("sum") {
            function = "SUM"
        } else if request.contains("평균") || request.lowercased().contains("average") {
            function = "AVERAGE"
        } else if request.contains("최댓값") || request.contains("최대값")
                    || request.lowercased().contains("maximum") {
            function = "MAX"
        } else if request.contains("최솟값") || request.contains("최소값")
                    || request.lowercased().contains("minimum") {
            function = "MIN"
        } else if request.contains("개수") || request.lowercased().contains("count") {
            function = "COUNT"
        } else {
            function = nil
        }
        guard let function,
              let targetText = captures(
                  #"(?<![A-Za-z0-9_])\$?([A-Za-z]{1,3})\$?(\d{1,7})(?![A-Za-z0-9_])"#,
                  in: prefix
              ),
              targetText.count >= 2,
              let target = ExcelCellAddress(
                  targetText[0].uppercased() + targetText[1]
              ) else {
            return nil
        }
        let formula = "=\(function)(\(sourceRange.reference))"
        return ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "\(target.reference)에 \(sourceRange.reference)의 \(function) 수식을 입력합니다.",
            edits: [.init(
                row: target.row,
                column: target.column,
                newValue: formula
            )],
            appendedRows: []
        )
    }

    private static func dropdownPlan(
        request: String,
        suffix: String,
        range: ExcelCellRange,
        snapshot: ExcelAIWorkbookSnapshot
    ) -> ExcelAICommandPlan? {
        guard request.contains("드롭다운"),
              let target = actionTarget(for: range, snapshot: snapshot) else {
            return nil
        }
        if request.contains("제거") || request.contains("삭제") {
            return editPlan(
                message: "\(range.reference)의 드롭다운을 제거합니다.",
                actions: [.init(type: .removeDropdown, target: target)]
            )
        }
        guard request.contains("넣") || request.contains("설정")
                || request.contains("추가"),
              let values = captures(
                  #"^\s*(?:에)?\s*(.+?)(?:와|과)\s+(.+?)(?:을|를)\s+(?:고르는|선택하는)"#,
                  in: suffix
              ),
              values.count >= 2 else {
            return nil
        }
        let choices = values.prefix(2).map(cleaned)
        guard choices.allSatisfy({ !$0.isEmpty }) else { return nil }
        return editPlan(
            message: "\(range.reference)에 \(choices.joined(separator: ", ")) 드롭다운을 설정합니다.",
            actions: [.init(
                type: .setDropdown,
                target: target,
                values: choices,
                allowsBlank: true
            )]
        )
    }

    private static func conditionalFormattingPlan(
        request: String,
        range: ExcelCellRange,
        snapshot: ExcelAIWorkbookSnapshot
    ) -> ExcelAICommandPlan? {
        guard request.contains("강조") || request.contains("조건부 서식"),
              let target = actionTarget(for: range, snapshot: snapshot),
              let parts = captures(
                  #"([+-]?\d[\d,]*(?:\.\d+)?)\s*(이상|이하|초과|미만)"#,
                  in: request
              ),
              parts.count >= 2 else {
            return nil
        }
        let value = parts[0].replacingOccurrences(of: ",", with: "")
        let condition: ExcelConditionalRuleKind
        switch parts[1] {
        case "이상": condition = .greaterThanOrEqual
        case "이하": condition = .lessThanOrEqual
        case "초과": condition = .greaterThan
        case "미만": condition = .lessThan
        default: return nil
        }
        let highlight: ExcelConditionalHighlight?
        if request.contains("초록") {
            highlight = .green
        } else if request.contains("노란") || request.contains("노랑") {
            highlight = .yellow
        } else if request.contains("빨간") || request.contains("빨강") {
            highlight = .red
        } else {
            highlight = nil
        }
        guard let highlight else { return nil }
        return editPlan(
            message: "\(range.reference)에 \(value) \(condition.title) 조건부 서식을 적용합니다.",
            actions: [.init(
                type: .setConditionalFormatting,
                target: target,
                condition: condition.rawValue,
                comparisonValue: value,
                highlight: highlight.rawValue
            )]
        )
    }

    private static func numberFormatPlan(
        request: String,
        range: ExcelCellRange,
        snapshot: ExcelAIWorkbookSnapshot
    ) -> ExcelAICommandPlan? {
        let folded = request.lowercased()
        guard folded.contains("형식") || folded.contains("표시") else {
            return nil
        }
        let format: ExcelNumberFormat?
        if folded.contains("소수 2") || folded.contains("소수점 2") {
            format = .decimalTwo
        } else if folded.contains("소수 1") || folded.contains("소수점 1") {
            format = .decimalOne
        } else if folded.contains("정수") || folded.contains("천 단위") {
            format = .integer
        } else if folded.contains("백분율") || folded.contains("퍼센트") {
            format = .percent
        } else if folded.contains("통화") || folded.contains("원화") {
            format = .currencyWon
        } else if folded.contains("날짜") {
            format = .date
        } else if folded.contains("시간") {
            format = .time
        } else if folded.contains("텍스트") {
            format = .text
        } else if folded.contains("일반") {
            format = .general
        } else {
            format = nil
        }
        guard let format,
              range.start.column == range.end.column,
              let region = snapshot.regions.first(where: { region in
                  guard region.columns.contains(where: {
                      $0.number == range.start.column
                  }) else {
                      return false
                  }
                  return Set(region.dataRows)
                      == Set(range.start.row...range.end.row)
              }) else {
            return nil
        }
        let action = ExcelAICommandPlan.Action(
            type: .setNumberFormat,
            target: .init(
                scope: .column,
                regionID: region.id,
                row: nil,
                column: range.start.column
            ),
            format: format.rawValue
        )
        return editPlan(
            message: "\(range.reference)에 \(format.title) 표시 형식을 적용합니다.",
            actions: [action]
        )
    }

    private static func replacePlan(
        request: String,
        suffix: String,
        range: ExcelCellRange,
        snapshot: ExcelAIWorkbookSnapshot
    ) -> ExcelAICommandPlan? {
        guard request.contains("바꿔") || request.contains("치환")
                || request.contains("찾아 바꾸") || request.contains("replace") else {
            return nil
        }
        let korean = captures(
            #"^\s*(?:범위)?(?:에서)?\s*(.+?)(?:을|를)\s+(.+?)(?:으로|로)\s+(?:모두\s+)?(?:바꿔|변경|치환)"#,
            in: suffix
        )
        let english = captures(
            #"\breplace\s+['\"]?(.+?)['\"]?\s+with\s+['\"]?(.+?)['\"]?(?:\s|$)"#,
            in: request
        )
        guard let values = korean ?? english, values.count >= 2 else {
            return nil
        }
        let oldValue = cleaned(values[0])
        let newValue = cleaned(values[1])
        guard !oldValue.isEmpty, !newValue.isEmpty else { return nil }
        let operation = ExcelAIWorkbookOperation(
            type: .replaceText,
            sheetID: snapshot.sheetPartPath,
            range: range.reference,
            value: oldValue,
            replacement: newValue
        )
        return editPlan(
            message: "\(range.reference)에서 ‘\(oldValue)’을 ‘\(newValue)’로 바꿉니다.",
            operations: [operation]
        )
    }

    private static func sortPlan(
        request: String,
        range: ExcelCellRange,
        snapshot: ExcelAIWorkbookSnapshot
    ) -> ExcelAICommandPlan? {
        guard request.contains("정렬") else { return nil }
        guard let column = requestedColumn(
            in: request,
            range: range,
            snapshot: snapshot
        ) else { return nil }
        let ascending: Bool
        if request.contains("내림") || request.lowercased().contains("descending") {
            ascending = false
        } else if request.contains("오름") || request.lowercased().contains("ascending") {
            ascending = true
        } else {
            return nil
        }
        let header: Bool
        if request.contains("머리글 없") || request.contains("헤더 없") {
            header = false
        } else if request.contains("머리글") || request.contains("헤더")
                    || request.contains("첫 행") || request.contains("첫행") {
            header = true
        } else {
            return nil
        }
        let operation = ExcelAIWorkbookOperation(
            type: .sortRange,
            sheetID: snapshot.sheetPartPath,
            range: range.reference,
            column: column,
            ascending: ascending,
            header: header
        )
        return editPlan(
            message: "\(range.reference)을 \(ExcelCellAddress.columnName(column))열 기준 \(ascending ? "오름차순" : "내림차순")으로 정렬합니다.",
            operations: [operation]
        )
    }

    private static func filterPlan(
        request: String,
        range: ExcelCellRange,
        snapshot: ExcelAIWorkbookSnapshot
    ) -> ExcelAICommandPlan? {
        guard request.contains("필터") else { return nil }
        guard let column = requestedColumn(
            in: request,
            range: range,
            snapshot: snapshot
        ) else { return nil }
        let comparison: ExcelFilterComparison
        if request.contains("포함") {
            comparison = .contains
        } else if request.contains("보다 큰") || request.contains("초과") {
            comparison = .greater
        } else if request.contains("보다 작은") || request.contains("미만") {
            comparison = .less
        } else {
            comparison = .equals
        }
        let value = filterValue(in: request)
        guard let value, !value.isEmpty else { return nil }
        let operation = ExcelAIWorkbookOperation(
            type: .filterRange,
            sheetID: snapshot.sheetPartPath,
            range: range.reference,
            column: column,
            comparison: comparison.rawValue,
            value: value
        )
        return editPlan(
            message: "\(range.reference)에 \(ExcelCellAddress.columnName(column))열 ‘\(value)’ 필터를 적용합니다.",
            operations: [operation]
        )
    }

    private static func formatAndFreezePlan(
        request: String,
        range: ExcelCellRange,
        snapshot: ExcelAIWorkbookSnapshot
    ) -> ExcelAICommandPlan? {
        let wantsFormatting = request.contains("굵게")
            || request.contains("배경") || request.contains("글자색")
            || request.contains("가운데") || request.contains("테두리")
        let wantsFreeze = request.contains("고정")
            && (request.contains("행") || request.contains("열"))
        guard wantsFormatting || wantsFreeze else { return nil }

        var operations = [ExcelAIWorkbookOperation]()
        if wantsFormatting {
            var format = ExcelAIWorkbookOperation.Format()
            if request.contains("굵게") { format.bold = true }
            if request.contains("기울임") { format.italic = true }
            if request.contains("밑줄") { format.underline = true }
            if request.contains("배경"), let color = colorARGB(in: request) {
                format.fillColor = color
            }
            if request.contains("글자색"), let color = colorARGB(in: request) {
                format.textColor = color
            }
            if request.contains("가운데") { format.horizontal = "center" }
            if request.contains("테두리") { format.borders = "all" }
            guard !format.isEmpty else { return nil }
            operations.append(.init(
                type: .formatCells,
                sheetID: snapshot.sheetPartPath,
                range: range.reference,
                format: format
            ))
        }

        if wantsFreeze {
            guard let context = snapshot.workbookContext else { return nil }
            var rows = context.frozenRows
            var columns = context.frozenColumns
            if request.contains("첫 행") || request.contains("첫행")
                || request.contains("1행") {
                rows = 1
            }
            if request.contains("첫 열") || request.contains("첫열")
                || request.contains("1열") {
                columns = 1
            }
            guard rows != context.frozenRows || columns != context.frozenColumns else {
                return nil
            }
            operations.append(.init(
                type: .freezePanes,
                sheetID: snapshot.sheetPartPath,
                rows: rows,
                columns: columns
            ))
        }
        return editPlan(
            message: "\(range.reference)의 요청한 서식과 화면 고정을 적용합니다.",
            operations: operations
        )
    }

    private static func chartPlan(
        request: String,
        range: ExcelCellRange,
        snapshot: ExcelAIWorkbookSnapshot
    ) -> ExcelAICommandPlan? {
        guard request.contains("차트"),
              request.contains("추가") || request.contains("만들") else {
            return nil
        }
        let kind: ExcelChartKind?
        if request.contains("세로 막대") || request.contains("세로막대") {
            kind = .column
        } else if request.contains("가로 막대") || request.contains("가로막대") {
            kind = .bar
        } else if request.contains("꺾은선") || request.contains("선형") {
            kind = .line
        } else if request.contains("원형") || request.contains("파이") {
            kind = .pie
        } else if request.contains("영역") {
            kind = .area
        } else if request.contains("분산") {
            kind = .scatter
        } else if request.contains("도넛") {
            kind = .doughnut
        } else if request.contains("방사") || request.contains("레이더") {
            kind = .radar
        } else {
            kind = nil
        }
        guard let kind,
              let captures = captures(
                  #"제목(?:은|는|을|를)?\s+(.+?)(?:으로|로)\s+(?:해|설정|지정)"#,
                  in: request
              ),
              let rawTitle = captures.first else {
            return nil
        }
        let title = cleaned(rawTitle)
        guard !title.isEmpty else { return nil }
        let operation = ExcelAIWorkbookOperation(
            type: .addChart,
            sheetID: snapshot.sheetPartPath,
            range: range.reference,
            name: title,
            chartKind: kind.rawValue
        )
        return editPlan(
            message: "\(range.reference) 데이터로 ‘\(title)’ 차트를 추가합니다.",
            operations: [operation]
        )
    }

    private static func requestedColumn(
        in request: String,
        range: ExcelCellRange,
        snapshot: ExcelAIWorkbookSnapshot
    ) -> Int? {
        if let match = captures(#"(?<![A-Za-z])([A-Za-z]{1,3})\s*열"#, in: request),
           let letters = match.first,
           let address = ExcelCellAddress(letters.uppercased() + "1"),
           (range.start.column...range.end.column).contains(address.column) {
            return address.column
        }
        let folded = request.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        let matches = snapshot.regions
            .flatMap(\.columns)
            .filter {
                (range.start.column...range.end.column).contains($0.number)
                    && !$0.title.isEmpty
                    && folded.localizedCaseInsensitiveContains($0.title)
            }
            .sorted { $0.title.count > $1.title.count }
        return matches.first?.number
    }

    private static func actionTarget(
        for range: ExcelCellRange,
        snapshot: ExcelAIWorkbookSnapshot
    ) -> ExcelAICommandPlan.Action.Target? {
        guard range.start.column == range.end.column,
              let region = snapshot.regions.first(where: { region in
                  region.columns.contains(where: {
                      $0.number == range.start.column
                  })
              }) else {
            return nil
        }
        if range.start.row == range.end.row,
           region.dataRows.contains(range.start.row) {
            return .init(
                scope: .cell,
                regionID: region.id,
                row: range.start.row,
                column: range.start.column
            )
        }
        guard Set(region.dataRows) == Set(range.start.row...range.end.row) else {
            return nil
        }
        return .init(
            scope: .column,
            regionID: region.id,
            row: nil,
            column: range.start.column
        )
    }

    private static func filterValue(in request: String) -> String? {
        let patterns = [
            #"값(?:이|은|는)?\s*[‘’'\"]?(.+?)[‘’'\"]?(?:인\s*행|인\s*셀|만\s*보)"#,
            #"(?:같은|동일한)\s*[‘’'\"]?(.+?)[‘’'\"]?(?:인\s*행|만\s*보)"#,
            #"(?:equals|=)\s*[‘’'\"]?([^,.'\"]+)"#,
        ]
        for pattern in patterns {
            if let value = captures(pattern, in: request)?.first {
                return cleaned(value)
            }
        }
        return nil
    }

    private static func colorARGB(in request: String) -> String? {
        if request.contains("노란") { return "FFFFEB9C" }
        if request.contains("초록") { return request.contains("연한") ? "FFC6EFCE" : "FF00B050" }
        if request.contains("빨간") || request.contains("빨강") { return request.contains("연한") ? "FFFFC7CE" : "FFFF0000" }
        if request.contains("파란") || request.contains("파랑") { return request.contains("연한") ? "FFDDEBF7" : "FF5B9BD5" }
        if request.contains("회색") { return "FFD9E1F2" }
        if request.contains("흰색") { return "FFFFFFFF" }
        return nil
    }

    private static func explicitRange(in text: String) -> ExplicitRange? {
        let pattern = #"(?<![A-Za-z0-9_])\$?([A-Za-z]{1,3})\$?(\d{1,7})(?:\s*:\s*\$?([A-Za-z]{1,3})\$?(\d{1,7}))?(?![A-Za-z0-9_])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex..., in: text)
              ),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }
        func part(_ index: Int) -> String? {
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
        guard let startColumn = part(1), let startRow = part(2),
              let value = ExcelCellRange(
                  startColumn.uppercased() + startRow + ":"
                      + (part(3) ?? startColumn).uppercased()
                      + (part(4) ?? startRow)
              ) else {
            return nil
        }
        return ExplicitRange(
            value: value,
            prefix: String(text[..<matchRange.lowerBound]),
            suffix: String(text[matchRange.upperBound...])
        )
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
        ), match.numberOfRanges > 1 else {
            return nil
        }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).map {
                String(text[$0])
            }
        }
    }

    private static func allCaptures(
        _ pattern: String,
        in text: String
    ) -> [[String]] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        return regex.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                Range(match.range(at: index), in: text).map {
                    String(text[$0])
                }
            }
        }
    }

    private static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(
                CharacterSet(charactersIn: "‘’'\".,")
            )
        )
    }

    private static func editPlan(
        message: String,
        actions: [ExcelAICommandPlan.Action] = [],
        operations: [ExcelAIWorkbookOperation] = []
    ) -> ExcelAICommandPlan {
        ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: message,
            edits: [],
            appendedRows: [],
            actions: actions,
            workbookOperations: operations
        )
    }
}
