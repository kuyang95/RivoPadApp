import RivoDocumentEngine
import Foundation
import XCTest

@testable import shortcuts_example

/// Recreates three sheets of a public conditional-formatting sample workbook
/// from a blank workbook using only the AI chat: table creation, row fill,
/// formulas, number formats, dropdowns, and conditional formatting. Every turn
/// goes through the same chat view model, command service, validator, and
/// atomic apply path the app uses. Opt-in because it calls the live model.
@MainActor
final class ExcelAIChatFeatureRecreationTests: XCTestCase {
    private struct Turn {
        let request: String
        let verify: (ExcelWorkbookViewModel) throws -> Void
    }

    private struct Fixture {
        let outputName: String
        let turns: [Turn]
    }

    func testRecreateThreeFeatureSheetsThroughLiveAIChat() async throws {
        #if !EXCEL_AI_LIVE_RECREATE
        throw XCTSkip(
            "EXCEL_AI_LIVE_RECREATE에서만 실제 AI 채팅 재현을 실행합니다."
        )
        #else
        FirebaseRuntime.configureIfAvailable()
        guard FirebaseRuntime.isConfigured else {
            XCTFail("Firebase가 구성되지 않았습니다.")
            return
        }

        let budget = await CloudAITokenBudgetStore.shared.refillForTesting()
        print("EXCEL_AI_FEATURE_TOKEN_BUDGET \(budget.remainingTokens)")

        let outputDirectory = try Self.outputDirectory()
        for fixture in Self.fixtures {
            let data = try await recreate(fixture)
            let outputURL = outputDirectory
                .appendingPathComponent(fixture.outputName)
            try data.write(to: outputURL, options: .atomic)

            let attachment = XCTAttachment(
                data: data,
                uniformTypeIdentifier:
                    "org.openxmlformats.spreadsheetml.sheet"
            )
            attachment.name = fixture.outputName
            attachment.lifetime = .keepAlways
            add(attachment)
            print(
                "EXCEL_AI_FEATURE_OUTPUT "
                    + outputURL.path
                    + " bytes=\(data.count)"
            )
        }
        #endif
    }

    private func recreate(_ fixture: Fixture) async throws -> Data {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "AIChatFeature-\(UUID().uuidString).xlsx"
            )
        try ExcelWorkbookDocument.blankWorkbookData().write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let workbook = ExcelWorkbookViewModel(fileURL: sourceURL)
        await workbook.load()
        let chat = ExcelAIChatViewModel()

        for (index, turn) in fixture.turns.enumerated() {
            print(
                "EXCEL_AI_FEATURE_TURN \(fixture.outputName) "
                    + "#\(index + 1)"
            )
            let applied = await send(
                turn.request,
                chat: chat,
                workbook: workbook
            )
            XCTAssertTrue(
                applied,
                "\(fixture.outputName) turn \(index + 1) 적용 실패"
            )
            do {
                try turn.verify(workbook)
                print(
                    "EXCEL_AI_FEATURE_VERIFY \(fixture.outputName) "
                        + "#\(index + 1) ok"
                )
            } catch {
                XCTFail(
                    "\(fixture.outputName) turn \(index + 1) 검증 실패: "
                        + "\(error)"
                )
            }
        }

        do {
            return try await workbook.exportData()
        } catch {
            print(
                "EXCEL_AI_FEATURE_EXPORT_ERROR \(fixture.outputName) "
                    + "\(type(of: error)): \(error)"
            )
            await Task.yield()
            return try await workbook.exportData()
        }
    }

    /// Returns true when the assistant answered and a change notice was
    /// recorded without a failure notice.
    private func send(
        _ request: String,
        chat: ExcelAIChatViewModel,
        workbook: ExcelWorkbookViewModel
    ) async -> Bool {
        let messageCount = chat.messages.count
        chat.input = request
        await chat.send(
            snapshotProvider: { request in
                try await workbook.makeAISnapshot(for: request)
            },
            applying: { plan in
                try workbook.applyAIPlan(plan)
            }
        )
        let newMessages = chat.messages.dropFirst(messageCount)
        for message in newMessages {
            print(
                "EXCEL_AI_FEATURE_CHAT role=\(message.role) "
                    + message.text.replacingOccurrences(of: "\n", with: " ")
            )
        }
        return newMessages.contains(where: { $0.role == .assistant })
            && !newMessages.contains(where: {
                $0.role == .notice
                    && ($0.text.contains("처리하지 못했습니다")
                        || $0.text.contains("파일은 변경되지 않았습니다"))
            })
    }

    // MARK: - Verification helpers

    private struct VerificationError: Error, CustomStringConvertible {
        let description: String
    }

    private static func fail(_ message: String) -> VerificationError {
        VerificationError(description: message)
    }

    private static func sheet(
        _ workbook: ExcelWorkbookViewModel
    ) throws -> ExcelWorksheet {
        guard let sheet = workbook.selectedSheet else {
            throw fail("선택된 시트가 없습니다.")
        }
        return sheet
    }

    private static func expectTable(
        _ workbook: ExcelWorkbookViewModel,
        headers: [String],
        dataRowCount: Int
    ) throws {
        let sheet = try sheet(workbook)
        guard let table = sheet.tables.first else {
            throw fail("정식 표가 만들어지지 않았습니다.")
        }
        let expected = ExcelCellRange(
            start: ExcelCellAddress(row: 1, column: 1),
            end: ExcelCellAddress(
                row: dataRowCount + 1,
                column: headers.count
            )
        )
        guard table.range == expected else {
            throw fail(
                "표 범위 \(table.range.reference) != "
                    + expected.reference
            )
        }
        guard table.columnNames == headers else {
            throw fail("표 머리글 \(table.columnNames) != \(headers)")
        }
    }

    private static func expectValues(
        _ workbook: ExcelWorkbookViewModel,
        rows: [[String]],
        startingAtRow firstRow: Int = 2
    ) throws {
        let sheet = try sheet(workbook)
        var mismatches = [String]()
        for (rowOffset, row) in rows.enumerated() {
            for (columnOffset, expected) in row.enumerated() {
                let address = ExcelCellAddress(
                    row: firstRow + rowOffset,
                    column: columnOffset + 1
                )
                let cell = sheet.cell(at: address)
                let actual: String
                if expected.hasPrefix("=") {
                    actual = cell?.formula.map { "=" + $0 } ?? ""
                } else if Double(expected) != nil {
                    // Number formats change the display text; compare the
                    // stored value so formatting turns don't look like
                    // data changes.
                    actual = cell?.rawValue ?? ""
                } else {
                    actual = cell?.displayValue ?? ""
                }
                if actual != expected,
                   !(Double(expected).map { $0 == Double(actual) } ?? false) {
                    mismatches.append(
                        "\(address.reference): '\(actual)' != '\(expected)'"
                    )
                }
            }
        }
        guard mismatches.isEmpty else {
            throw fail("값 불일치 \(mismatches.count)건: "
                + mismatches.prefix(8).joined(separator: ", "))
        }
    }

    private static func expectNumberFormat(
        _ workbook: ExcelWorkbookViewModel,
        _ format: ExcelNumberFormat,
        column: Int,
        rows: ClosedRange<Int>
    ) throws {
        let sheet = try sheet(workbook)
        guard let document = workbook.workbook else {
            throw fail("워크북이 없습니다.")
        }
        var wrong = [String]()
        for row in rows {
            let address = ExcelCellAddress(row: row, column: column)
            // Number-format actions only touch populated cells.
            guard let cell = sheet.cell(at: address) else { continue }
            let style = document.style(at: cell.styleIndex)
            if ExcelNumberFormat.matching(style) != format {
                wrong.append(address.reference)
            }
        }
        guard wrong.isEmpty else {
            throw fail(
                "\(format.rawValue) 표시 형식 누락: "
                    + wrong.prefix(8).joined(separator: ", ")
            )
        }
    }

    private static func expectFormulas(
        _ workbook: ExcelWorkbookViewModel,
        column: Int,
        rows: ClosedRange<Int>,
        formula: (Int) -> String
    ) throws {
        let sheet = try sheet(workbook)
        var wrong = [String]()
        for row in rows {
            let address = ExcelCellAddress(row: row, column: column)
            let actual = sheet.cell(at: address)?.formula.map { "=" + $0 } ?? ""
            if actual != formula(row) {
                wrong.append("\(address.reference)='\(actual)'")
            }
        }
        guard wrong.isEmpty else {
            throw fail("수식 훼손: " + wrong.prefix(8).joined(separator: ", "))
        }
    }

    private static func expectDropdown(
        _ workbook: ExcelWorkbookViewModel,
        values: [String],
        column: Int,
        rows: ClosedRange<Int>
    ) throws {
        let sheet = try sheet(workbook)
        var missing = [String]()
        for row in rows {
            let address = ExcelCellAddress(row: row, column: column)
            let rule = sheet.dataValidations.first { $0.contains(address) }
            if rule?.inlineListValues != values {
                missing.append(address.reference)
            }
        }
        guard missing.isEmpty else {
            throw fail(
                "드롭다운 \(values) 누락: "
                    + missing.prefix(8).joined(separator: ", ")
            )
        }
    }

    private static func expectConditionalRule(
        _ workbook: ExcelWorkbookViewModel,
        kind: ExcelConditionalRuleKind,
        comparisonValue: String,
        highlight: ExcelConditionalHighlight,
        column: Int,
        rows: ClosedRange<Int>
    ) throws {
        let sheet = try sheet(workbook)
        guard let document = workbook.workbook else {
            throw fail("워크북이 없습니다.")
        }
        var missing = [String]()
        for row in rows {
            let address = ExcelCellAddress(row: row, column: column)
            let matches = sheet.conditionalFormatting.contains { block in
                block.ranges.contains(where: { $0.contains(address) })
                    && block.rules.contains { rule in
                        guard rule.kind == kind else { return false }
                        let expectedValue = kind.requiresNumber
                            ? Double(comparisonValue)
                            : nil
                        let valueMatches = expectedValue.map {
                            Double(rule.comparisonValue) == $0
                        } ?? (rule.comparisonValue == comparisonValue)
                        guard valueMatches,
                              document.differentialStyles.indices.contains(
                                  rule.differentialStyleIndex
                              ) else { return false }
                        let style = document.differentialStyles[
                            rule.differentialStyleIndex
                        ]
                        return ExcelConditionalHighlight.matching(style)
                            == highlight
                    }
            }
            if !matches {
                missing.append(address.reference)
            }
        }
        guard missing.isEmpty else {
            throw fail(
                "조건부 서식 \(kind.rawValue) \(comparisonValue) "
                    + "\(highlight.rawValue) 누락: "
                    + missing.prefix(8).joined(separator: ", ")
            )
        }
    }

    private static func outputDirectory() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = documents
            .appendingPathComponent("AIChatRecreation", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    // MARK: - Fixtures

    private static let gradesRows: [[String]] = [
        ["Nancy", "96", "97", "90", "82"],
        ["Andrew", "59", "55", "71", "94"],
        ["Janet", "69", "71", "98", "98"],
        ["Margaret", "99", "90", "59", "79"],
        ["Steven", "56", "86", "65", "74"],
        ["Michael", "57", "61", "84", "67"],
        ["Robert", "55", "86", "59", "86"],
        ["Laura", "89", "91", "91", "81"],
        ["Anne", "55", "77", "91", "86"],
    ]

    private static let productsRows: [[String]] = [
        ["2007-04-09", "Dairy", "Denmark", "1148"],
        ["2007-05-26", "Produce", "Denmark", "1530"],
        ["2007-12-07", "Produce", "Denmark", "1423.5"],
        ["", "", "Denmark Total", "=SUBTOTAL(9,D2:D4)"],
        ["2007-11-05", "Dairy", "Finland", "192.1"],
        ["2007-07-12", "Dairy", "Finland", "351"],
        ["2007-06-02", "Grain", "Finland", "560.4"],
        ["", "", "Finland Total", "=SUBTOTAL(9,D6:D8)"],
        ["2007-08-30", "Dairy", "Germany", "470"],
        ["2007-07-26", "Dairy", "Germany", "17.4"],
        ["2007-09-24", "Grain", "Germany", "1405"],
        ["2007-10-30", "Grain", "Germany", "470"],
        ["2007-08-26", "Grain", "Germany", "17.4"],
        ["2007-07-07", "Grain", "Germany", "747"],
        ["2007-06-26", "Produce", "Germany", "17.4"],
        ["2007-07-07", "Produce", "Germany", "747"],
        ["", "", "Germany Total", "=SUBTOTAL(9,D10:D17)"],
        ["2007-01-18", "Dairy", "Italy", "3194.2"],
        ["2007-02-13", "Dairy", "Italy", "438.43"],
        ["2007-12-18", "Produce", "Italy", "3194.2"],
        ["2007-03-13", "Produce", "Italy", "438.43"],
        ["", "", "Italy Total", "=SUBTOTAL(9,D20:D23)"],
    ]

    private static let regionalRows: [[String]] = [
        ["NorthWest", "1781345"],
        ["West", "534389"],
        ["SouthWest", "1009268"],
        ["South", "899999"],
        ["Central", "2345184"],
        ["NorthEast", "900000"],
        ["East", "1567090"],
        ["Territories", "34678"],
        ["Total", "=SUBTOTAL(109,B2:B9)"],
    ]

    private static func pipeLines(_ rows: [[String]]) -> String {
        rows.map { $0.joined(separator: " | ") }.joined(separator: "\n")
    }

    private static let fixtures: [Fixture] = [
        // 03_ConditionalFormattingSamples.xlsx / "Grades"
        Fixture(
            outputName: "AIChat_Feature_Grades.xlsx",
            turns: [
                Turn(
                    request:
                        "빈 시트에 Student, Quiz1, Exam1, Quiz2, Exam2, Grade 열을 이 순서로 가진 정식 Excel 표를 만들어줘. 빈 데이터 행은 정확히 9개로 해줘.",
                    verify: { workbook in
                        try expectTable(
                            workbook,
                            headers: [
                                "Student", "Quiz1", "Exam1",
                                "Quiz2", "Exam2", "Grade",
                            ],
                            dataRowCount: 9
                        )
                    }
                ),
                Turn(
                    request: """
                    방금 만든 A1:F10 표의 빈 데이터 행 2행부터 10행까지 아래 순서 그대로 채워줘. 각 줄은 Student | Quiz1 | Exam1 | Quiz2 | Exam2 야. Grade 열은 아직 비워둬.
                    \(pipeLines(gradesRows))
                    """,
                    verify: { workbook in
                        try expectValues(workbook, rows: gradesRows)
                    }
                ),
                Turn(
                    request:
                        "Grade 열 2행부터 10행까지 각 행에 가중 평균 수식을 넣어줘. 2행은 =(B2+(C2*3)+D2+(E2*3))/8 이고, 3행은 =(B3+(C3*3)+D3+(E3*3))/8 처럼 행 번호만 바꿔서 10행까지 똑같이 넣어줘.",
                    verify: { workbook in
                        let rows = (2...10).map { row in
                            [
                                "", "", "", "", "",
                                "=(B\(row)+(C\(row)*3)+D\(row)+(E\(row)*3))/8",
                            ]
                        }
                        let sheet = try sheet(workbook)
                        for (offset, row) in rows.enumerated() {
                            let address = ExcelCellAddress(
                                row: offset + 2,
                                column: 6
                            )
                            let formula = sheet.cell(at: address)?.formula
                                .map { "=" + $0 } ?? ""
                            guard formula == row[5] else {
                                throw fail(
                                    "\(address.reference) 수식 '\(formula)' != '\(row[5])'"
                                )
                            }
                        }
                        let nancy = sheet.cell(
                            at: ExcelCellAddress(row: 2, column: 6)
                        )?.rawValue ?? ""
                        guard Double(nancy) == 90.375 else {
                            throw fail("F2 계산값 '\(nancy)' != 90.375")
                        }
                    }
                ),
                Turn(
                    request: "Grade 열 전체를 소수점 없이 정수로 표시해줘.",
                    verify: { workbook in
                        try expectNumberFormat(
                            workbook,
                            .integer,
                            column: 6,
                            rows: 2...10
                        )
                        let sheet = try sheet(workbook)
                        let display = sheet.cell(
                            at: ExcelCellAddress(row: 2, column: 6)
                        )?.displayValue ?? ""
                        guard display == "90" else {
                            throw fail("F2 표시값 '\(display)' != '90'")
                        }
                        try expectFormulas(workbook, column: 6, rows: 2...10) {
                            "=(B\($0)+(C\($0)*3)+D\($0)+(E\($0)*3))/8"
                        }
                        let raw = sheet.cell(
                            at: ExcelCellAddress(row: 2, column: 6)
                        )?.rawValue ?? ""
                        guard Double(raw) == 90.375 else {
                            throw fail("F2 원본값 '\(raw)' != 90.375 (반올림 덮어쓰기)")
                        }
                        try expectValues(workbook, rows: gradesRows)
                    }
                ),
                Turn(
                    request:
                        "Grade 열에서 85보다 큰 값은 초록색으로 강조해줘.",
                    verify: { workbook in
                        try expectConditionalRule(
                            workbook,
                            kind: .greaterThan,
                            comparisonValue: "85",
                            highlight: .green,
                            column: 6,
                            rows: 2...10
                        )
                    }
                ),
            ]
        ),
        // 03_ConditionalFormattingSamples.xlsx / "Products2"
        Fixture(
            outputName: "AIChat_Feature_Products2.xlsx",
            turns: [
                Turn(
                    request:
                        "빈 시트에 Date, Product, Region, Amount 열을 이 순서로 가진 정식 Excel 표를 만들어줘. 빈 데이터 행은 정확히 22개로 해줘.",
                    verify: { workbook in
                        try expectTable(
                            workbook,
                            headers: ["Date", "Product", "Region", "Amount"],
                            dataRowCount: 22
                        )
                    }
                ),
                Turn(
                    request: """
                    방금 만든 A1:D23 표의 빈 데이터 행 2행부터 23행까지 아래 순서 그대로 채워줘. 각 줄은 Date | Product | Region | Amount 야. 값이 비어 있는 칸은 비워두고, =로 시작하는 값은 수식으로 그대로 넣어줘. 날짜는 적힌 문자 그대로 넣어줘.
                    \(pipeLines(productsRows))
                    """,
                    verify: { workbook in
                        try expectValues(workbook, rows: productsRows)
                    }
                ),
                Turn(
                    request:
                        "Amount 열은 소수점 둘째 자리까지 표시하고, Date 열은 날짜 형식으로 표시해줘.",
                    verify: { workbook in
                        try expectNumberFormat(
                            workbook,
                            .decimalTwo,
                            column: 4,
                            rows: 2...23
                        )
                        try expectNumberFormat(
                            workbook,
                            .date,
                            column: 1,
                            rows: 2...23
                        )
                        try expectValues(workbook, rows: productsRows)
                    }
                ),
                Turn(
                    request:
                        "Product 열의 데이터 셀에 Dairy, Produce, Grain 중에서 고르는 드롭다운을 넣어줘.",
                    verify: { workbook in
                        try expectDropdown(
                            workbook,
                            values: ["Dairy", "Produce", "Grain"],
                            column: 2,
                            rows: 2...23
                        )
                    }
                ),
                Turn(
                    request:
                        "Amount 열에서 200보다 작은 값은 빨간색으로, Product 열에서 Grain 과 같은 값은 노란색으로 강조해줘.",
                    verify: { workbook in
                        try expectConditionalRule(
                            workbook,
                            kind: .lessThan,
                            comparisonValue: "200",
                            highlight: .red,
                            column: 4,
                            rows: 2...23
                        )
                        try expectConditionalRule(
                            workbook,
                            kind: .equalTo,
                            comparisonValue: "Grain",
                            highlight: .yellow,
                            column: 2,
                            rows: 2...23
                        )
                    }
                ),
            ]
        ),
        // 03_ConditionalFormattingSamples.xlsx / "Regional sales"
        Fixture(
            outputName: "AIChat_Feature_RegionalSales.xlsx",
            turns: [
                Turn(
                    request:
                        "빈 시트에 Region, Sales 열을 이 순서로 가진 정식 Excel 표를 만들어줘. 빈 데이터 행은 정확히 9개로 해줘.",
                    verify: { workbook in
                        try expectTable(
                            workbook,
                            headers: ["Region", "Sales"],
                            dataRowCount: 9
                        )
                    }
                ),
                Turn(
                    request: """
                    방금 만든 A1:B10 표의 빈 데이터 행 2행부터 10행까지 아래 순서 그대로 채워줘. 각 줄은 Region | Sales 야. 마지막 줄의 =로 시작하는 값은 수식으로 그대로 넣어줘.
                    \(pipeLines(regionalRows))
                    """,
                    verify: { workbook in
                        try expectValues(workbook, rows: regionalRows)
                    }
                ),
                Turn(
                    request:
                        "Sales 열 전체를 천 단위 구분 기호가 있는 정수로 표시해줘.",
                    verify: { workbook in
                        // "천 단위 구분 정수" is legitimately read as either a
                        // grouped integer or the won currency format.
                        do {
                            try expectNumberFormat(
                                workbook,
                                .integer,
                                column: 2,
                                rows: 2...10
                            )
                        } catch {
                            try expectNumberFormat(
                                workbook,
                                .currencyWon,
                                column: 2,
                                rows: 2...10
                            )
                        }
                        let sheet = try sheet(workbook)
                        let display = sheet.cell(
                            at: ExcelCellAddress(row: 2, column: 2)
                        )?.displayValue ?? ""
                        guard display.hasSuffix("1,781,345") else {
                            throw fail("B2 표시값 '\(display)' != '1,781,345'")
                        }
                        try expectValues(workbook, rows: regionalRows)
                    }
                ),
                Turn(
                    request:
                        "Sales 열에서 900000 이상인 값은 초록색으로 강조해줘.",
                    verify: { workbook in
                        try expectConditionalRule(
                            workbook,
                            kind: .greaterThanOrEqual,
                            comparisonValue: "900000",
                            highlight: .green,
                            column: 2,
                            rows: 2...10
                        )
                    }
                ),
            ]
        ),
    ]
}
