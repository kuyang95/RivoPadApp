import RivoDocumentEngine
import Foundation
import FirebaseAILogic
import XCTest

@testable import shortcuts_example

/// Measures how conversational Excel requests fare at the two command gates:
/// Gemini intent recognition and the deterministic safety validator.
@MainActor
final class ExcelAINaturalLanguageAuditTests: XCTestCase {
    private enum Operation: String, CaseIterable, Encodable {
        case editCell
        case appendRow
        case createTable
        case setNumberFormat
        case setDropdown
        case removeDropdown
        case setConditionalFormatting
        case removeConditionalFormatting
        case clearCell
        case setFormula
    }

    private struct PhraseCase {
        let id: String
        let operation: Operation
        let request: String
    }

    private struct ValidatorResult: Encodable {
        let id: String
        let operation: Operation
        let request: String
        let accepted: Bool
        let error: String?
    }

    private struct LiveResult: Encodable {
        let id: String
        let operation: Operation
        let request: String
        let modelIntent: String?
        let modelPlan: String?
        let modelRecognized: Bool
        let validatorAccepted: Bool
        let outcome: String
        let error: String?
    }

    private struct LiveRequest: Encodable {
        let userRequest: String
        let recentConversation: [ExcelAIChatTurn]
        let worksheet: ExcelAIWorkbookSnapshot
    }

    func testValidatorNaturalLanguageCoverageAudit() throws {
        let rows = Self.cases.map { item in
            let snapshot = item.operation == .createTable
                ? Self.blankSnapshot
                : Self.salesSnapshot
            do {
                _ = try ExcelAICommandValidator.validate(
                    Self.idealPlan(for: item.operation),
                    snapshot: snapshot
                )
                return ValidatorResult(
                    id: item.id,
                    operation: item.operation,
                    request: item.request,
                    accepted: true,
                    error: nil
                )
            } catch {
                return ValidatorResult(
                    id: item.id,
                    operation: item.operation,
                    request: item.request,
                    accepted: false,
                    error: String(describing: error)
                )
            }
        }

        for row in rows {
            Self.emit(row, marker: "EXCEL_NL_VALIDATOR_CASE")
        }
        let accepted = rows.filter(\.accepted).count
        let summary: [String: Any] = [
            "cases": rows.count,
            "accepted": accepted,
            "rejected": rows.count - accepted,
            "acceptanceRate": Double(accepted) / Double(rows.count),
            "byOperation": Dictionary(
                uniqueKeysWithValues: Operation.allCases.map { operation in
                    let matching = rows.filter { $0.operation == operation }
                    return (
                        operation.rawValue,
                        [
                            "cases": matching.count,
                            "accepted": matching.filter(\.accepted).count,
                        ]
                    )
                }
            ),
        ]
        Self.emit(summary, marker: "EXCEL_NL_VALIDATOR_SUMMARY")

        XCTAssertEqual(rows.count, Self.cases.count)
        XCTAssertEqual(
            accepted,
            rows.count,
            "의미를 이미 구조화한 정상 계획을 자연어 키워드로 거부하면 안 됩니다."
        )
    }

    func testImplicitFormulaRequestsUseVerifiedTableColumns() throws {
        let requests = [
            "금액은 수량 곱하기 단가로 자동 계산되게 해줘",
            "금액 칸에 둘을 곱한 값 나오게 해줘",
            "금액이 알아서 계산되게 해줘",
        ]
        for request in requests {
            let plan = try XCTUnwrap(
                ExcelAIDeterministicEditPlanner.plan(
                    userRequest: request,
                    snapshot: Self.salesSnapshot
                ),
                request
            )
            XCTAssertEqual(plan.intent, .edit, request)
            XCTAssertEqual(
                plan.edits,
                [
                    .init(row: 2, column: 4, newValue: "=B2*C2"),
                    .init(row: 3, column: 4, newValue: "=B3*C3"),
                ],
                request
            )
            XCTAssertTrue(plan.appendedRows.isEmpty, request)
            XCTAssertTrue(plan.actions.isEmpty, request)
        }
    }

    func testSequentialSingleColumnListsDoNotRequireModelOrFullWorkbook() throws {
        let cases: [(String, [ExcelAICommandPlan.Edit])] = [
            (
                """
                O4:O10 표의 5행부터 9행까지 STATUS KEY 값을 순서대로 채워줘.
                Not Started
                In Progress
                Complete
                On Hold
                Overdue
                """,
                [
                    .init(row: 5, column: 15, newValue: "Not Started"),
                    .init(row: 6, column: 15, newValue: "In Progress"),
                    .init(row: 7, column: 15, newValue: "Complete"),
                    .init(row: 8, column: 15, newValue: "On Hold"),
                    .init(row: 9, column: 15, newValue: "Overdue"),
                ]
            ),
            (
                """
                Q4:Q8 표의 5행부터 7행까지 PRIORITY KEY 값을 순서대로 채워줘.
                High
                Medium
                Low
                """,
                [
                    .init(row: 5, column: 17, newValue: "High"),
                    .init(row: 6, column: 17, newValue: "Medium"),
                    .init(row: 7, column: 17, newValue: "Low"),
                ]
            ),
        ]
        for (request, expectedEdits) in cases {
            let plan = try XCTUnwrap(
                ExcelAIDeterministicEditPlanner.plan(
                    userRequest: request,
                    snapshot: Self.blankSnapshot
                ),
                request
            )
            XCTAssertEqual(plan.edits, expectedEdits, request)
        }
    }

    func testMultipleExplicitCellWritesDoNotRequireModel() throws {
        let request = "표 밖의 셀에 값을 직접 써줘. B2 셀에 'PROJECT TRACKING TEMPLATE', F3 셀에 'PROJECTS', I3 셀에 'DELIVERABLE(S)' 를 그대로 넣어줘. 다른 셀은 건드리지 마."
        let plan = try XCTUnwrap(
            ExcelAIDeterministicEditPlanner.plan(
                userRequest: request,
                snapshot: Self.blankSnapshot
            )
        )
        XCTAssertEqual(
            plan.edits,
            [
                .init(row: 2, column: 2, newValue: "PROJECT TRACKING TEMPLATE"),
                .init(row: 3, column: 6, newValue: "PROJECTS"),
                .init(row: 3, column: 9, newValue: "DELIVERABLE(S)"),
            ]
        )
    }

    func testLiveNaturalLanguageCoverageAudit() async throws {
        #if !EXCEL_AI_LIVE_EVAL
        throw XCTSkip(
            "EXCEL_AI_LIVE_EVAL에서만 실제 Gemini 자연어 평가를 실행합니다."
        )
        #else
        FirebaseRuntime.configureIfAvailable()
        guard FirebaseRuntime.isConfigured else {
            XCTFail("Firebase가 구성되지 않았습니다.")
            return
        }

        let refilledBudget = await CloudAITokenBudgetStore
            .shared
            .refillForTesting()
        print(
            "EXCEL_NL_LIVE_TOKEN_BUDGET_REFILLED "
                + String(refilledBudget.remainingTokens)
        )

        #if EXCEL_AI_LIVE_SMOKE
        let selectedCases = Array(Self.cases.prefix(1))
        #elseif EXCEL_AI_LIVE_NUMBER_ONLY
        let selectedCases = Self.cases.filter {
            $0.operation == .setNumberFormat
        }
        #elseif EXCEL_AI_LIVE_EDGE_ONLY
        let selectedCases = Self.cases.filter {
            [
                "append-4", "number-4", "dropdown-set-3", "clear-3",
                "formula-5",
            ].contains($0.id)
        }
        #else
        let requestedIDs = Set(
            ProcessInfo.processInfo.environment["EXCEL_AI_LIVE_CASES"]?
                .split(separator: ",")
                .map(String.init) ?? []
        )
        let selectedCases = requestedIDs.isEmpty
            ? Self.cases
            : Self.cases.filter { requestedIDs.contains($0.id) }
        #endif
        let model = Self.makeLiveModel()
        var rows = [LiveResult]()
        for item in selectedCases {
            let snapshot = item.operation == .createTable
                ? Self.blankSnapshot
                : Self.salesSnapshot
            do {
                let plan = try await Self.livePlan(
                    userRequest: item.request,
                    snapshot: snapshot,
                    model: model
                )
                let recognized = Self.matches(
                    plan,
                    operation: item.operation
                )
                let validatorAccepted: Bool
                let validationError: String?
                do {
                    let validated = try ExcelAICommandValidator.validate(
                        plan,
                        snapshot: snapshot
                    )
                    validatorAccepted = validated != nil
                    validationError = nil
                } catch {
                    validatorAccepted = false
                    validationError = String(describing: error)
                }
                let outcome: String
                if !recognized {
                    outcome = "modelMiss"
                } else if !validatorAccepted {
                    outcome = "validatorRejected"
                } else {
                    outcome = "success"
                }
                let row = LiveResult(
                    id: item.id,
                    operation: item.operation,
                    request: item.request,
                    modelIntent: plan.intent.rawValue,
                    modelPlan: Self.planSummary(plan),
                    modelRecognized: recognized,
                    validatorAccepted: validatorAccepted,
                    outcome: outcome,
                    error: validationError
                )
                rows.append(row)
                Self.emit(row, marker: "EXCEL_NL_LIVE_CASE")
            } catch {
                let row = LiveResult(
                    id: item.id,
                    operation: item.operation,
                    request: item.request,
                    modelIntent: nil,
                    modelPlan: nil,
                    modelRecognized: false,
                    validatorAccepted: false,
                    outcome: "modelError",
                    error: String(describing: error)
                )
                rows.append(row)
                Self.emit(row, marker: "EXCEL_NL_LIVE_CASE")
            }
        }

        let summary: [String: Any] = [
            "cases": rows.count,
            "modelRecognized": rows.filter(\.modelRecognized).count,
            "validatorAccepted": rows.filter(\.validatorAccepted).count,
            "success": rows.filter { $0.outcome == "success" }.count,
            "modelMiss": rows.filter { $0.outcome == "modelMiss" }.count,
            "validatorRejected": rows.filter {
                $0.outcome == "validatorRejected"
            }.count,
            "modelError": rows.filter { $0.outcome == "modelError" }.count,
            "byOperation": Dictionary(
                uniqueKeysWithValues: Operation.allCases.map { operation in
                    let matching = rows.filter { $0.operation == operation }
                    return (
                        operation.rawValue,
                        [
                            "cases": matching.count,
                            "success": matching.filter {
                                $0.outcome == "success"
                            }.count,
                            "modelMiss": matching.filter {
                                $0.outcome == "modelMiss"
                            }.count,
                            "validatorRejected": matching.filter {
                                $0.outcome == "validatorRejected"
                            }.count,
                            "modelError": matching.filter {
                                $0.outcome == "modelError"
                            }.count,
                        ]
                    )
                }
            ),
        ]
        Self.emit(summary, marker: "EXCEL_NL_LIVE_SUMMARY")

        XCTAssertEqual(rows.count, selectedCases.count)
        #endif
    }

    private static func idealPlan(
        for operation: Operation
    ) -> ExcelAICommandPlan {
        let message = "요청한 작업을 적용했습니다."
        switch operation {
        case .editCell:
            return .init(
                intent: .edit,
                assistantMessage: message,
                edits: [.init(row: 2, column: 2, newValue: "5")],
                appendedRows: []
            )
        case .appendRow:
            return .init(
                intent: .edit,
                assistantMessage: message,
                edits: [],
                appendedRows: [
                    .init(
                        regionID: "table:1",
                        values: [
                            .init(column: 1, newValue: "바나나"),
                            .init(column: 2, newValue: "4"),
                            .init(column: 3, newValue: "1200"),
                        ]
                    ),
                ]
            )
        case .createTable:
            return .init(
                intent: .edit,
                assistantMessage: message,
                edits: [],
                appendedRows: [],
                createdTables: [
                    .init(
                        startRow: 1,
                        startColumn: 1,
                        headers: ["상품", "수량", "단가", "금액"]
                    ),
                ]
            )
        case .setNumberFormat:
            return actionPlan(
                .init(
                    type: .setNumberFormat,
                    target: columnTarget(2),
                    format: "integer"
                )
            )
        case .setDropdown:
            return actionPlan(
                .init(
                    type: .setDropdown,
                    target: columnTarget(1),
                    values: ["사과", "배"],
                    allowsBlank: true
                )
            )
        case .removeDropdown:
            return actionPlan(
                .init(
                    type: .removeDropdown,
                    target: columnTarget(1)
                )
            )
        case .setConditionalFormatting:
            return actionPlan(
                .init(
                    type: .setConditionalFormatting,
                    target: columnTarget(4),
                    condition: "greaterThan",
                    comparisonValue: "3000",
                    highlight: "red"
                )
            )
        case .removeConditionalFormatting:
            return actionPlan(
                .init(
                    type: .removeConditionalFormatting,
                    target: columnTarget(4)
                )
            )
        case .clearCell:
            return .init(
                intent: .edit,
                assistantMessage: message,
                edits: [.init(row: 2, column: 2, newValue: "")],
                appendedRows: []
            )
        case .setFormula:
            return .init(
                intent: .edit,
                assistantMessage: message,
                edits: [.init(row: 2, column: 4, newValue: "=B2*C2")],
                appendedRows: []
            )
        }
    }

    private static func livePlan(
        userRequest: String,
        snapshot: ExcelAIWorkbookSnapshot,
        model: GenerativeModel
    ) async throws -> ExcelAICommandPlan {
        let request = LiveRequest(
            userRequest: userRequest,
            recentConversation: [],
            worksheet: snapshot
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let requestData = try encoder.encode(request)
        let requestJSON = String(decoding: requestData, as: UTF8.self)
        let contents = [ModelContent(
            role: "user",
            parts: [TextPart(requestJSON)]
        )]
        let inputTokens = try await model.countTokens(contents).totalTokens
        let reservation = try await CloudAITokenBudgetStore.shared.reserve(
            inputTokens: inputTokens,
            maximumOutputTokens: 4_096
        )
        do {
            let response = try await model.generateContent(contents)
            await CloudAITokenBudgetStore.shared.commit(
                reservation,
                actualTokens: response.usageMetadata?.totalTokenCount
            )
            guard let rawText = response.text else {
                throw ExcelAICommandServiceError.invalidResponse
            }
            let normalized = normalizedJSON(rawText)
            guard let data = normalized.data(using: .utf8) else {
                throw ExcelAICommandServiceError.invalidResponse
            }
            return try JSONDecoder().decode(
                ExcelAICommandPlan.self,
                from: data
            )
        } catch {
            await CloudAITokenBudgetStore.shared.cancel(reservation)
            throw error
        }
    }

    private static func makeLiveModel() -> GenerativeModel {
        let modelName = ExcelAICommandService.modelName
        return FirebaseAI
            .firebaseAI(backend: .googleAI())
            .generativeModel(
                modelName: modelName,
                generationConfig: GenerationConfig(
                    temperature: 0,
                    maxOutputTokens: 4_096,
                    responseMIMEType: "application/json",
                    responseSchema: ExcelAICommandService.responseSchema
                ),
                systemInstruction: ModelContent(
                    role: "system",
                    parts: ExcelAICommandService.systemInstruction
                )
            )
    }

    private static func normalizedJSON(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```"),
           let firstNewline = value.firstIndex(of: "\n") {
            value = String(value[value.index(after: firstNewline)...])
        }
        if value.hasSuffix("```") {
            value = String(value.dropLast(3))
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func actionPlan(
        _ action: ExcelAICommandPlan.Action
    ) -> ExcelAICommandPlan {
        .init(
            intent: .edit,
            assistantMessage: "요청한 작업을 적용했습니다.",
            edits: [],
            appendedRows: [],
            actions: [action]
        )
    }

    private static func columnTarget(
        _ column: Int
    ) -> ExcelAICommandPlan.Action.Target {
        .init(
            scope: .column,
            regionID: "table:1",
            row: nil,
            column: column
        )
    }

    private static func matches(
        _ plan: ExcelAICommandPlan,
        operation: Operation
    ) -> Bool {
        guard plan.intent == .edit else { return false }
        switch operation {
        case .editCell:
            return plan.edits.count == 1
                && plan.appendedRows.isEmpty
                && plan.createdTables.isEmpty
                && plan.actions.isEmpty
                && plan.edits.contains {
                $0.row == 2 && $0.column == 2 && $0.newValue == "5"
            }
        case .appendRow:
            return plan.edits.isEmpty
                && plan.appendedRows.count == 1
                && plan.createdTables.isEmpty
                && plan.actions.isEmpty
                && plan.appendedRows.contains { row in
                row.values.count == 3
                    && row.values.contains {
                    $0.column == 1 && $0.newValue.contains("바나나")
                }
                    && row.values.contains {
                        $0.column == 2 && $0.newValue == "4"
                    }
                    && row.values.contains {
                        $0.column == 3 && $0.newValue == "1200"
                    }
            }
        case .createTable:
            return plan.edits.isEmpty
                && plan.appendedRows.isEmpty
                && plan.createdTables.count == 1
                && plan.actions.isEmpty
                && plan.createdTables.contains { table in
                ["상품", "수량", "단가", "금액"].allSatisfy {
                    table.headers.contains($0)
                }
            }
        case .setNumberFormat:
            return plan.edits.isEmpty
                && plan.appendedRows.isEmpty
                && plan.createdTables.isEmpty
                && plan.actions.count == 1
                && plan.actions.contains {
                $0.type == .setNumberFormat && $0.format == "integer"
            }
        case .setDropdown:
            return plan.edits.isEmpty
                && plan.appendedRows.isEmpty
                && plan.createdTables.isEmpty
                && plan.actions.count == 1
                && plan.actions.contains { $0.type == .setDropdown }
        case .removeDropdown:
            return plan.edits.isEmpty
                && plan.appendedRows.isEmpty
                && plan.createdTables.isEmpty
                && plan.actions.count == 1
                && plan.actions.contains { $0.type == .removeDropdown }
        case .setConditionalFormatting:
            return plan.edits.isEmpty
                && plan.appendedRows.isEmpty
                && plan.createdTables.isEmpty
                && plan.actions.count == 1
                && plan.actions.contains {
                $0.type == .setConditionalFormatting
            }
        case .removeConditionalFormatting:
            return plan.edits.isEmpty
                && plan.appendedRows.isEmpty
                && plan.createdTables.isEmpty
                && plan.actions.count == 1
                && plan.actions.contains {
                $0.type == .removeConditionalFormatting
            }
        case .clearCell:
            return plan.edits.count == 1
                && plan.appendedRows.isEmpty
                && plan.createdTables.isEmpty
                && plan.actions.isEmpty
                && plan.edits.contains {
                $0.row == 2 && $0.column == 2 && $0.newValue.isEmpty
            }
        case .setFormula:
            return !plan.edits.isEmpty
                && plan.appendedRows.isEmpty
                && plan.createdTables.isEmpty
                && plan.actions.isEmpty
                && plan.edits.contains {
                $0.row == 2 && $0.column == 4
                    && $0.newValue.hasPrefix("=")
            }
        }
    }

    private static func planSummary(_ plan: ExcelAICommandPlan) -> String {
        let edits = plan.edits.map {
            "R\($0.row)C\($0.column)=\($0.newValue)"
        }.joined(separator: ",")
        let appendedRows = plan.appendedRows.map { row in
            let values = row.values.map {
                "C\($0.column)=\($0.newValue)"
            }.joined(separator: ",")
            return "\(row.regionID){\(values)}"
        }.joined(separator: ",")
        let tables = plan.createdTables.map {
            "R\($0.startRow)C\($0.startColumn)["
                + $0.headers.joined(separator: ",") + "]"
        }.joined(separator: ",")
        let actions = plan.actions.map {
            "\($0.type.rawValue):\($0.target.regionID):"
                + "C\($0.target.column)"
        }.joined(separator: ",")
        return "edits=\(edits);appends=\(appendedRows);"
            + "tables=\(tables);actions=\(actions)"
    }

    private static func emit<T: Encodable>(
        _ value: T,
        marker: String
    ) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        print(marker + " " + String(decoding: data, as: UTF8.self))
    }

    private static func emit(
        _ value: [String: Any],
        marker: String
    ) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys]
        ) else { return }
        print(marker + " " + String(decoding: data, as: UTF8.self))
    }

    private static let blankSnapshot = ExcelAIWorkbookSnapshot(
        workbookName: "새 스프레드시트",
        sheetName: "시트1",
        sheetPartPath: "xl/worksheets/sheet1.xml",
        selectedCell: "A1",
        supportsEdits: true,
        worksheetIsProtected: false,
        capabilities: ExcelAICommandCapability.allCases,
        searchedWholeSheet: false,
        searchTerms: [],
        searchResultRowCount: 0,
        searchResultsWereTruncated: false,
        retrievedRows: [],
        regions: [],
        mergedRanges: [],
        cells: [],
        contextWasTruncated: false,
        revision: "blank"
    )

    private static let salesSnapshot = ExcelAIWorkbookSnapshot(
        workbookName: "판매표",
        sheetName: "시트1",
        sheetPartPath: "xl/worksheets/sheet1.xml",
        selectedCell: "B2",
        supportsEdits: true,
        worksheetIsProtected: false,
        capabilities: ExcelAICommandCapability.allCases,
        searchedWholeSheet: false,
        searchTerms: [],
        searchResultRowCount: 0,
        searchResultsWereTruncated: false,
        retrievedRows: [],
        regions: [
            .init(
                id: "table:1",
                name: "판매",
                range: "A1:D3",
                headerRow: 1,
                columns: [
                    .init(number: 1, letter: "A", title: "상품"),
                    .init(number: 2, letter: "B", title: "수량"),
                    .init(number: 3, letter: "C", title: "단가"),
                    .init(number: 4, letter: "D", title: "금액"),
                ],
                dataRows: [2, 3],
                isNativeTable: true
            ),
        ],
        mergedRanges: [],
        cells: [
            .init(
                address: "A1", row: 1, column: 1,
                header: nil, value: "상품", formula: nil,
                numberFormat: nil
            ),
            .init(
                address: "B1", row: 1, column: 2,
                header: nil, value: "수량", formula: nil,
                numberFormat: nil
            ),
            .init(
                address: "C1", row: 1, column: 3,
                header: nil, value: "단가", formula: nil,
                numberFormat: nil
            ),
            .init(
                address: "D1", row: 1, column: 4,
                header: nil, value: "금액", formula: nil,
                numberFormat: nil
            ),
            .init(
                address: "A2", row: 2, column: 1,
                header: "상품", value: "사과", formula: nil,
                numberFormat: nil
            ),
            .init(
                address: "B2", row: 2, column: 2,
                header: "수량", value: "2.0", formula: nil,
                numberFormat: "decimalOne"
            ),
            .init(
                address: "C2", row: 2, column: 3,
                header: "단가", value: "1000", formula: nil,
                numberFormat: "integer"
            ),
            .init(
                address: "D2", row: 2, column: 4,
                header: "금액", value: "2000", formula: nil,
                numberFormat: "integer"
            ),
            .init(
                address: "A3", row: 3, column: 1,
                header: "상품", value: "배", formula: nil,
                numberFormat: nil
            ),
            .init(
                address: "B3", row: 3, column: 2,
                header: "수량", value: "3.0", formula: nil,
                numberFormat: "decimalOne"
            ),
            .init(
                address: "C3", row: 3, column: 3,
                header: "단가", value: "1500", formula: nil,
                numberFormat: "integer"
            ),
            .init(
                address: "D3", row: 3, column: 4,
                header: "금액", value: "4500", formula: nil,
                numberFormat: "integer"
            ),
        ],
        contextWasTruncated: false,
        revision: "sales"
    )

    private static let cases: [PhraseCase] = [
        .init(id: "edit-1", operation: .editCell,
              request: "사과 수량 5개로 바꿔줘"),
        .init(id: "edit-2", operation: .editCell,
              request: "사과가 두 개로 돼 있는데 다섯 개로 고쳐줘"),
        .init(id: "edit-3", operation: .editCell,
              request: "사과 수량 말이야, 그거 5로 해둘래?"),
        .init(id: "edit-4", operation: .editCell,
              request: "사과 수량만 5로 맞춰 놔"),

        .init(id: "append-1", operation: .appendRow,
              request: "바나나 4개, 개당 1200원으로 한 줄 넣어줘"),
        .init(id: "append-2", operation: .appendRow,
              request: "여기에 바나나도 추가하자. 수량은 4, 단가는 1200"),
        .init(id: "append-3", operation: .appendRow,
              request: "맨 밑에 바나나, 4, 1200 이렇게 적어줘"),
        .init(id: "append-4", operation: .appendRow,
              request: "바나나 항목도 하나 끼워 넣어. 네 개, 개당 천이백 원"),

        .init(id: "table-1", operation: .createTable,
              request: "상품, 수량, 단가, 금액 표 하나 만들어줘"),
        .init(id: "table-2", operation: .createTable,
              request: "상품이랑 수량, 단가, 금액 적을 표 좀 만들어줘"),
        .init(id: "table-3", operation: .createTable,
              request: "상품이랑 수량, 단가, 금액 적을 틀 하나 짜줘"),
        .init(id: "table-4", operation: .createTable,
              request: "상품·수량·단가·금액 네 칸짜리 입력 양식 만들어줘"),
        .init(id: "table-5", operation: .createTable,
              request: "상품 수량 단가 금액 들어간 테이블 하나 만들어줘"),

        .init(id: "number-1", operation: .setNumberFormat,
              request: "수량을 2.0 말고 2로 표시해줘"),
        .init(id: "number-2", operation: .setNumberFormat,
              request: "수량 뒤에 붙는 .0 좀 떼줘"),
        .init(id: "number-3", operation: .setNumberFormat,
              request: "수량은 소수점 없이 보이게 해줘"),
        .init(id: "number-4", operation: .setNumberFormat,
              request: "수량을 정수처럼 보이게 바꿔줘"),
        .init(id: "number-5", operation: .setNumberFormat,
              request: "수량 숫자 좀 깔끔하게 떨어지게 해줘"),

        .init(id: "dropdown-set-1", operation: .setDropdown,
              request: "상품 열에 사과, 배 드롭다운 넣어줘"),
        .init(id: "dropdown-set-2", operation: .setDropdown,
              request: "상품은 목록에서 사과나 배를 고르게 해줘"),
        .init(id: "dropdown-set-3", operation: .setDropdown,
              request: "상품을 사과, 배 선택 목록으로 해줘"),
        .init(id: "dropdown-set-4", operation: .setDropdown,
              request: "상품은 사과나 배 중에 골라 넣게 해줘"),
        .init(id: "dropdown-set-5", operation: .setDropdown,
              request: "상품 칸 누르면 사과랑 배 중 하나 고르게 해줘"),

        .init(id: "dropdown-remove-1", operation: .removeDropdown,
              request: "상품 열 드롭다운 없애줘"),
        .init(id: "dropdown-remove-2", operation: .removeDropdown,
              request: "상품 선택 목록 삭제해줘"),
        .init(id: "dropdown-remove-3", operation: .removeDropdown,
              request: "상품 고르는 거 이제 풀어줘"),
        .init(id: "dropdown-remove-4", operation: .removeDropdown,
              request: "상품은 아무거나 직접 쓰게 바꿔줘"),

        .init(id: "conditional-set-1", operation: .setConditionalFormatting,
              request: "금액이 3000 넘으면 빨간색으로 강조해줘"),
        .init(id: "conditional-set-2", operation: .setConditionalFormatting,
              request: "금액 3000 넘는 건 빨갛게 칠해줘"),
        .init(id: "conditional-set-3", operation: .setConditionalFormatting,
              request: "비싼 건 눈에 띄게 해줘. 3000원 넘으면"),
        .init(id: "conditional-set-4", operation: .setConditionalFormatting,
              request: "금액이 3000보다 크면 초록색으로 보여줘"),
        .init(id: "conditional-set-5", operation: .setConditionalFormatting,
              request: "금액 3000 초과한 건 노랑으로 칠해줘"),

        .init(id: "conditional-remove-1",
              operation: .removeConditionalFormatting,
              request: "금액 열 조건부 서식 없애줘"),
        .init(id: "conditional-remove-2",
              operation: .removeConditionalFormatting,
              request: "금액 조건부 규칙 삭제해줘"),
        .init(id: "conditional-remove-3",
              operation: .removeConditionalFormatting,
              request: "금액에 걸린 색칠 규칙 풀어줘"),
        .init(id: "conditional-remove-4",
              operation: .removeConditionalFormatting,
              request: "3000 넘을 때 빨갛게 되는 거 지워줘"),

        .init(id: "clear-1", operation: .clearCell,
              request: "사과 수량 칸 비워줘"),
        .init(id: "clear-2", operation: .clearCell,
              request: "사과 수량 지워줘"),
        .init(id: "clear-3", operation: .clearCell,
              request: "사과 수량 값 빼줘"),
        .init(id: "clear-4", operation: .clearCell,
              request: "사과 수량은 빈칸으로 해줘"),
        .init(id: "clear-5", operation: .clearCell,
              request: "사과 수량 내용 없게 해줘"),

        .init(id: "formula-1", operation: .setFormula,
              request: "금액에 수량 곱하기 단가 수식 넣어줘"),
        .init(id: "formula-2", operation: .setFormula,
              request: "금액 칸을 =B2*C2로 바꿔줘"),
        .init(id: "formula-3", operation: .setFormula,
              request: "금액은 수량 곱하기 단가로 자동 계산되게 해줘"),
        .init(id: "formula-4", operation: .setFormula,
              request: "금액 칸에 둘을 곱한 값 나오게 해줘"),
        .init(id: "formula-5", operation: .setFormula,
              request: "금액이 알아서 계산되게 해줘"),
    ]
}
