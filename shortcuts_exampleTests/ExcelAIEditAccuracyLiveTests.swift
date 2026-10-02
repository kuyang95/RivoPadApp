import RivoDocumentEngine
import Foundation
import XCTest

@testable import shortcuts_example

/// End-to-end editing accuracy audit against a public, multi-sheet XLSX.
/// Every scenario starts from a pristine copy and follows the production path:
/// chat -> live model -> validation -> atomic apply -> XLSX export -> reload.
@MainActor
final class ExcelAIEditAccuracyLiveTests: XCTestCase {
    private enum CellPolicy {
        case exact(Set<String>)
        case valuesUnchanged
        case unrestricted
    }

    private struct Scenario {
        let id: String
        let sheet: String
        let request: String
        let expectsMutation: Bool
        let cellPolicy: CellPolicy
        let verify: (ExcelWorkbook) throws -> Void
    }

    private struct Result: Codable {
        let id: String
        let sheet: String
        let request: String
        let assistant: String
        let notice: String
        let changedCells: [String]
        let passed: Bool
        let detail: String
    }

    private struct VerificationError: Error, CustomStringConvertible {
        let description: String
    }

    func testChatEditingAccuracyOnPublicWorkbook() async throws {
        #if !EXCEL_AI_EDIT_ACCURACY
            throw XCTSkip("EXCEL_AI_EDIT_ACCURACY=1에서만 실제 AI 수정 감사를 실행합니다.")
        #else
        FirebaseRuntime.configureIfAvailable()
        guard FirebaseRuntime.isConfigured else {
            XCTFail("Firebase가 구성되지 않았습니다.")
            return
        }

        let budget = await CloudAITokenBudgetStore.shared.refillForTesting()
        print("EXCEL_EDIT_ACCURACY_TOKEN_BUDGET \(budget.remainingTokens)")

        let source = try Self.fixtureData()
        let baseline = try ExcelWorkbookDocument.load(from: source)
        let baselineValues = Self.valueMap(baseline)
        var results = [Result]()

        for scenario in Self.scenarios {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ExcelEditAccuracy-\(scenario.id)-\(UUID().uuidString).xlsx")
            try source.write(to: url, options: .atomic)
            defer { try? FileManager.default.removeItem(at: url) }

            let model = ExcelWorkbookViewModel(fileURL: url)
            await model.load()
            guard model.errorDescription == nil, let workbook = model.workbook,
                  let index = workbook.sheets.firstIndex(where: { $0.name == scenario.sheet }) else {
                XCTFail("\(scenario.id): 원본 통합문서를 열지 못했습니다.")
                continue
            }
            model.selectSheet(index)

            let chat = ExcelAIChatViewModel()
            let priorRevision = model.makeAISnapshot()?.revision
            chat.input = scenario.request
            await chat.send(
                snapshotProvider: { request in
                    try await model.makeAISnapshot(for: request)
                },
                applying: { plan in
                    try model.applyAIPlan(plan)
                },
                applyingOperations: { plan in
                    try await model.applyAIWorkbookPlan(plan)
                }
            )

            let assistant = chat.messages
                .last(where: { $0.role == .assistant })?.text ?? ""
            let notice = chat.messages
                .filter { $0.role == .notice }.map(\.text).joined(separator: " | ")
            let mutated = model.makeAISnapshot()?.revision != priorRevision
            var failures = [String]()
            if assistant.isEmpty && notice.isEmpty {
                failures.append("응답 없음")
            }
            if mutated != scenario.expectsMutation {
                failures.append("변경 여부 \(mutated), 기대값 \(scenario.expectsMutation)")
            }

            do {
                let exported = try await model.exportData()
                let reloaded = try ExcelWorkbookDocument.load(from: exported)
                let finalValues = Self.valueMap(reloaded)
                let changedCells = Self.changedKeys(from: baselineValues, to: finalValues)
                switch scenario.cellPolicy {
                case let .exact(expected):
                    if Set(changedCells) != expected {
                        failures.append(
                            "변경 셀 \(changedCells) != \(expected.sorted())"
                        )
                    }
                case .valuesUnchanged:
                    if !changedCells.isEmpty {
                        failures.append("값이 바뀌면 안 되지만 \(changedCells) 변경")
                    }
                case .unrestricted:
                    break
                }
                do {
                    try scenario.verify(reloaded)
                } catch {
                    failures.append(error.localizedDescription)
                }

                let output = FileManager.default.temporaryDirectory
                    .appendingPathComponent("accuracy-\(scenario.id).xlsx")
                try exported.write(to: output, options: .atomic)
                let attachment = XCTAttachment(
                    data: exported,
                    uniformTypeIdentifier: "org.openxmlformats.spreadsheetml.sheet"
                )
                attachment.name = "accuracy-\(scenario.id).xlsx"
                attachment.lifetime = .keepAlways
                add(attachment)

                let passed = failures.isEmpty
                results.append(.init(
                    id: scenario.id,
                    sheet: scenario.sheet,
                    request: scenario.request,
                    assistant: assistant,
                    notice: notice,
                    changedCells: changedCells,
                    passed: passed,
                    detail: failures.joined(separator: "; ")
                ))
                print(
                    "EXCEL_EDIT_ACCURACY_RESULT id=\(scenario.id) pass=\(passed) "
                        + "mutated=\(mutated) cells=\(changedCells.joined(separator: ",")) "
                        + "assistant=\(assistant.replacingOccurrences(of: "\n", with: " ").prefix(240)) "
                        + "notice=\(notice.replacingOccurrences(of: "\n", with: " ").prefix(180)) "
                        + "detail=\(failures.joined(separator: " | "))"
                )
            } catch {
                failures.append("내보내기/재열기 실패: \(error.localizedDescription)")
                results.append(.init(
                    id: scenario.id,
                    sheet: scenario.sheet,
                    request: scenario.request,
                    assistant: assistant,
                    notice: notice,
                    changedCells: [],
                    passed: false,
                    detail: failures.joined(separator: "; ")
                ))
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let report = try encoder.encode(results)
        let attachment = XCTAttachment(data: report, uniformTypeIdentifier: "public.json")
        attachment.name = "excel-edit-accuracy-report.json"
        attachment.lifetime = .keepAlways
        add(attachment)

        let passed = results.filter(\.passed).count
        print("EXCEL_EDIT_ACCURACY_SUMMARY passed=\(passed) total=\(results.count)")
        XCTAssertEqual(passed, results.count, "수정 정확도 실패: \(results.filter { !$0.passed }.map(\.id))")
        #endif
    }

    private static func fixtureData() throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(
            forResource: "ToolXkit_Sample",
            withExtension: "xlsx",
            subdirectory: "InternetWorkbookFixtures"
        ) ?? bundle.url(forResource: "ToolXkit_Sample", withExtension: "xlsx")
        guard let url else { throw VerificationError(description: "ToolXkit 샘플이 테스트 번들에 없습니다.") }
        return try Data(contentsOf: url)
    }

    private static func valueMap(_ workbook: ExcelWorkbook) -> [String: String] {
        Dictionary(uniqueKeysWithValues: workbook.sheets.flatMap { sheet in
            sheet.cells.values.map { cell in
                ("\(sheet.name)!\(cell.address.reference)", cell.formula.map { "=\($0)" } ?? cell.rawValue)
            }
        })
    }

    private static func changedKeys(
        from before: [String: String],
        to after: [String: String]
    ) -> [String] {
        Set(before.keys).union(after.keys)
            .filter { before[$0] != after[$0] }
            .sorted()
    }

    private static func sheet(_ name: String, in workbook: ExcelWorkbook) throws -> ExcelWorksheet {
        guard let sheet = workbook.sheets.first(where: { $0.name == name }) else {
            throw VerificationError(description: "\(name) 시트 없음")
        }
        return sheet
    }

    private static func cell(_ reference: String, in sheet: ExcelWorksheet) throws -> ExcelCell {
        guard let address = ExcelCellAddress(reference), let cell = sheet.cell(at: address) else {
            throw VerificationError(description: "\(sheet.name)!\(reference) 셀 없음")
        }
        return cell
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw VerificationError(description: message) }
    }

    private static let scenarios: [Scenario] = [
        Scenario(
            id: "01-targeted-text",
            sheet: "Employees",
            request: "Daniel Weber의 location 값만 Hamburg로 바꿔줘.",
            expectsMutation: true,
            cellPolicy: .exact(["Employees!E5"]),
            verify: { book in
                let employees = try sheet("Employees", in: book)
                let value = try cell("E5", in: employees).displayValue
                try require(value == "Hamburg", "E5가 Hamburg가 아님")
            }
        ),
        Scenario(
            id: "02-targeted-number",
            sheet: "Employees",
            request: "Aisha Bakr의 salary 값만 61000으로 바꿔줘.",
            expectsMutation: true,
            cellPolicy: .exact(["Employees!G6"]),
            verify: { book in
                let employees = try sheet("Employees", in: book)
                let value = try cell("G6", in: employees).rawValue
                try require(Double(value) == 61_000, "G6가 61000이 아님")
            }
        ),
        Scenario(
            id: "03-clear-one-cell",
            sheet: "Employees",
            request: "Sofia Marchetti 행의 location 셀 하나만 비워줘.",
            expectsMutation: true,
            cellPolicy: .exact(["Employees!E4"]),
            verify: { book in
                let sheet = try sheet("Employees", in: book)
                try require(sheet.cell(at: ExcelCellAddress("E4")!)?.rawValue.isEmpty != false, "E4가 비어 있지 않음")
            }
        ),
        Scenario(
            id: "04-replace-all",
            sheet: "Employees",
            request: "Employees 시트 D2:D9 범위에서 Engineering을 Technology로 모두 바꿔줘.",
            expectsMutation: true,
            cellPolicy: .exact(["Employees!D3", "Employees!D6", "Employees!D9"]),
            verify: { book in
                let sheet = try sheet("Employees", in: book)
                for address in ["D3", "D6", "D9"] {
                    let value = try cell(address, in: sheet).displayValue
                    try require(value == "Technology", "\(address)가 Technology가 아님")
                }
            }
        ),
        Scenario(
            id: "05-number-format",
            sheet: "Employees",
            request: "salary 열의 데이터 G2:G9를 천 단위 구분이 있는 정수 형식으로 표시해줘.",
            expectsMutation: true,
            cellPolicy: .valuesUnchanged,
            verify: { book in
                let sheet = try sheet("Employees", in: book)
                for row in 2...9 {
                    let cell = try cell("G\(row)", in: sheet)
                    try require(ExcelNumberFormat.matching(book.style(at: cell.styleIndex)) == .integer, "G\(row) 정수 형식 누락")
                }
            }
        ),
        Scenario(
            id: "06-dropdown",
            sheet: "Employees",
            request: "active 데이터 H2:H9에 TRUE와 FALSE를 고르는 드롭다운을 넣어줘.",
            expectsMutation: true,
            cellPolicy: .valuesUnchanged,
            verify: { book in
                let sheet = try sheet("Employees", in: book)
                for row in 2...9 {
                    let address = ExcelCellAddress("H\(row)")!
                    let values = sheet.dataValidations.first(where: { $0.contains(address) })?.inlineListValues?.map { $0.uppercased() }
                    try require(values == ["TRUE", "FALSE"], "H\(row) 드롭다운 누락")
                }
            }
        ),
        Scenario(
            id: "07-conditional-format",
            sheet: "Employees",
            request: "salary 데이터 G2:G9에서 80000 이상인 셀을 연한 초록색으로 강조해줘.",
            expectsMutation: true,
            cellPolicy: .valuesUnchanged,
            verify: { book in
                let sheet = try sheet("Employees", in: book)
                let found = sheet.conditionalFormatting.contains { block in
                    block.ranges.contains(ExcelCellRange("G2:G9")!)
                        && block.rules.contains { rule in
                            rule.kind == .greaterThanOrEqual
                                && Double(rule.comparisonValue) == 80_000
                                && book.differentialStyles.indices.contains(rule.differentialStyleIndex)
                                && ExcelConditionalHighlight.matching(book.differentialStyles[rule.differentialStyleIndex]) == .green
                        }
                }
                try require(found, "G2:G9의 80000 이상 초록 조건부 서식 누락")
            }
        ),
        Scenario(
            id: "08-append-row",
            sheet: "Employees",
            request: "Employees 데이터 끝에 새 직원 한 줄을 추가해줘. id 1009, name Hana Kim, role UX Researcher, department Product, location Seoul, started 2024-05-20, salary 73000, active TRUE.",
            expectsMutation: true,
            cellPolicy: .exact(Set((1...8).map { "Employees!\(ExcelCellAddress.columnName($0))10" })),
            verify: { book in
                let sheet = try sheet("Employees", in: book)
                let expected = ["1009", "Hana Kim", "UX Researcher", "Product", "Seoul", "2024-05-20", "73000", "TRUE"]
                for (offset, value) in expected.enumerated() {
                    let actual = try cell("\(ExcelCellAddress.columnName(offset + 1))10", in: sheet).displayValue
                    try require(actual.caseInsensitiveCompare(value) == .orderedSame || Double(actual) == Double(value), "10행 \(offset + 1)열 값 \(actual) != \(value)")
                }
            }
        ),
        Scenario(
            id: "09-formula",
            sheet: "Invoice",
            request: "Invoice 시트 D11 셀을 D6:D9의 합계 수식으로 바꿔줘.",
            expectsMutation: true,
            cellPolicy: .exact(["Invoice!D11"]),
            verify: { book in
                let formula = try cell("D11", in: sheet("Invoice", in: book)).formula?.uppercased()
                try require(formula == "SUM(D6:D9)", "D11 합계 수식이 아님: \(formula ?? "nil")")
            }
        ),
        Scenario(
            id: "10-sort",
            sheet: "Employees",
            request: "Employees의 A1:H9 전체를 salary 열인 G열 기준 내림차순으로 정렬해줘. 첫 행은 머리글이야.",
            expectsMutation: true,
            cellPolicy: .unrestricted,
            verify: { book in
                let sheet = try sheet("Employees", in: book)
                let names = try (2...9).map { try cell("B\($0)", in: sheet).displayValue }
                try require(names == ["Priya Raman", "Mei Lin Chen", "Carlos Mendes", "Tom Okafor", "Daniel Weber", "James Whitfield", "Sofia Marchetti", "Aisha Bakr"], "급여 내림차순 정렬 결과가 다름: \(names)")
            }
        ),
        Scenario(
            id: "11-filter",
            sheet: "Employees",
            request: "Employees의 A1:H9에서 department 열인 D열 값이 Product인 행만 보이게 필터해줘.",
            expectsMutation: true,
            cellPolicy: .valuesUnchanged,
            verify: { book in
                let sheet = try sheet("Employees", in: book)
                try require(sheet.filterRange == ExcelCellRange("A1:H9"), "필터 범위가 A1:H9가 아님")
                try require(sheet.hiddenRows == Set([3, 4, 6, 7, 9]), "숨김 행이 다름: \(sheet.hiddenRows.sorted())")
            }
        ),
        Scenario(
            id: "12-format-and-freeze",
            sheet: "Summary",
            request: "Summary 시트 A1:C1을 굵게 하고 연한 노란색 배경으로 바꾼 다음 첫 행을 고정해줘.",
            expectsMutation: true,
            cellPolicy: .valuesUnchanged,
            verify: { book in
                let sheet = try sheet("Summary", in: book)
                try require(sheet.frozenPanes.rows == 1, "첫 행이 고정되지 않음")
                for column in 1...3 {
                    let cell = try cell("\(ExcelCellAddress.columnName(column))1", in: sheet)
                    let style = book.style(at: cell.styleIndex)
                    try require(style.isBold && style.fillARGB != nil, "A1:C1 굵게/배경 서식 누락")
                }
            }
        ),
        Scenario(
            id: "13-chart",
            sheet: "Summary",
            request: "Summary 시트 A1:C5 데이터로 세로 막대형 차트를 추가해줘. 제목은 부서별 급여로 해줘.",
            expectsMutation: true,
            cellPolicy: .valuesUnchanged,
            verify: { book in
                let charts = try sheet("Summary", in: book).drawingObjects.charts
                try require(charts.contains { $0.title == "부서별 급여" && $0.kind == .column && $0.sourceRange == ExcelCellRange("A1:C5") }, "요청한 차트가 없음")
            }
        ),
        Scenario(
            id: "14-ambiguous-safe",
            sheet: "Employees",
            request: "salary를 바꿔줘.",
            expectsMutation: false,
            cellPolicy: .valuesUnchanged,
            verify: { _ in }
        ),
    ]
}
