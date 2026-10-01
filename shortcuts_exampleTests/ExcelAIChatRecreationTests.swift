import Foundation
import XCTest

@testable import shortcuts_example

/// Recreates public Excel samples from a blank workbook through the same
/// AI chat view model, command service, validator, and atomic apply path used
/// by the app. This is intentionally opt-in because it calls the live model.
@MainActor
final class ExcelAIChatRecreationTests: XCTestCase {
    private struct Fixture {
        let outputName: String
        let headers: [String]
        let rows: [[String]]
        let createRequest: String
        let fillRequest: String
    }

    func testRecreateThreePublicWorkbooksThroughLiveAIChat() async throws {
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
        print("EXCEL_AI_RECREATE_TOKEN_BUDGET \(budget.remainingTokens)")

        let outputDirectory = try Self.outputDirectory()
        #if EXCEL_AI_RECREATE_RETRY_LAST_TWO
        let selectedFixtures = Array(Self.fixtures.dropFirst())
        #else
        let selectedFixtures = Self.fixtures
        #endif
        for fixture in selectedFixtures {
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
                "EXCEL_AI_RECREATE_OUTPUT "
                    + outputURL.path
                    + " bytes=\(data.count)"
            )
        }
        #endif
    }

    private func recreate(_ fixture: Fixture) async throws -> Data {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "AIChatRecreate-\(UUID().uuidString).xlsx"
            )
        try ExcelWorkbookDocument.blankWorkbookData().write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let workbook = ExcelWorkbookViewModel(fileURL: sourceURL)
        await workbook.load()
        let chat = ExcelAIChatViewModel()

        try await send(
            fixture.createRequest,
            chat: chat,
            workbook: workbook
        )
        let expectedRange = ExcelCellRange(
            start: ExcelCellAddress(row: 1, column: 1),
            end: ExcelCellAddress(
                row: fixture.rows.count + 1,
                column: fixture.headers.count
            )
        )
        let createdTable = try XCTUnwrap(workbook.selectedSheet?.tables.first)
        XCTAssertEqual(createdTable.range, expectedRange)
        XCTAssertEqual(createdTable.columnNames, fixture.headers)

        try await send(
            fixture.fillRequest,
            chat: chat,
            workbook: workbook
        )
        try Self.assertValues(fixture, in: workbook)

        return try await workbook.exportData()
    }

    private func send(
        _ request: String,
        chat: ExcelAIChatViewModel,
        workbook: ExcelWorkbookViewModel
    ) async throws {
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
                "EXCEL_AI_RECREATE_CHAT role=\(message.role) "
                    + message.text.replacingOccurrences(of: "\n", with: " ")
            )
        }
        guard newMessages.contains(where: { $0.role == .assistant }),
              !newMessages.contains(where: {
                  $0.role == .notice
                      && $0.text.contains("처리하지 못했습니다")
              }) else {
            throw NSError(
                domain: "ExcelAIChatRecreationTests",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "AI 채팅 명령이 적용되지 않았습니다: \(request)",
                ]
            )
        }
    }

    private static func assertValues(
        _ fixture: Fixture,
        in workbook: ExcelWorkbookViewModel
    ) throws {
        let sheet = try XCTUnwrap(workbook.selectedSheet)
        for (columnOffset, header) in fixture.headers.enumerated() {
            XCTAssertEqual(
                sheet.cell(
                    at: ExcelCellAddress(
                        row: 1,
                        column: columnOffset + 1
                    )
                )?.displayValue,
                header
            )
        }
        for (rowOffset, row) in fixture.rows.enumerated() {
            for (columnOffset, value) in row.enumerated() {
                XCTAssertEqual(
                    sheet.cell(
                        at: ExcelCellAddress(
                            row: rowOffset + 2,
                            column: columnOffset + 1
                        )
                    )?.displayValue,
                    value,
                    "\(fixture.outputName) "
                        + "R\(rowOffset + 2)C\(columnOffset + 1)"
                )
            }
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

    private static let fixtures: [Fixture] = [
        Fixture(
            outputName: "AIChat_03_Product_Cost.xlsx",
            headers: ["SKU", "Product", "ProductCost"],
            rows: [
                ["1010-GL120-3C", "Trainer - Tailspin GL-120", "59.05"],
                ["1010-GL155-4C", "Trainer - Tailspin GL-155", "162.68"],
                ["2030-PCUB-3C", "Piper Cub 3 Channel", "60.83"],
                ["2030-PCUB-4C", "Piper Cub 4 Channel", "139.09"],
                ["2050-P47-4C", "P47 4 Channel", "86.91"],
                ["2050-P47-5C", "P47 5 Channel", "225.17"],
                ["2055-P51-5C", "P51", "217.35"],
                ["2060-SKYT-5C", "SkyTrainer", "146.91"],
                ["3010-TAVM2-11-3C", "Tailspin Aviator Mk2-11", "126.32"],
                ["3010-TAVM2-12-4C", "Tailspin Aviator Mk2-12", "129.13"],
                ["3010-TAVM2-15-4C", "Tailspin Aviator Mk2-15", "140.79"],
                ["3010-TWAR-BM32-5C", "Tailspin Warbird BM32", "240.79"],
                ["3050-THeli-Co-Ax Pro-4C", "Tailspin Heli - Co-Ax Pro Mk I - 4ch", "247.16"],
                ["3050-THeli-MaxPro-6C", "Tailspin Heli - Max Pro Flight - 6ch", "367.16"],
                ["3050-THeli-Pro-5C", "Tailspin Heli - Pro Mk III - 5ch", "255.16"],
                ["4010-3CAX-B-3C", "3CAX-B Helicopter", "39.96"],
                ["4010-3CFP-I-3C", "3CFP-I Helicopter", "95.16"],
                ["4030-4CAX-B-4C", "4CAX-B Helicopter", "95.96"],
                ["4030-4CFP-I-4C", "4CFP-I Helicopter", "111.96"],
                ["4040-6CCP-A-6C", "6CCP-A Helicopter", "151.96"],
            ],
            createRequest:
                "빈 시트에 SKU, Product, ProductCost 열을 이 순서로 가진 정식 Excel 표를 만들어줘. 빈 데이터 행은 정확히 20개로 해줘.",
            fillRequest: """
            방금 만든 A1:C21 표의 빈 데이터 행 2행부터 21행까지 아래 순서 그대로 채워줘. 각 줄은 SKU | Product | ProductCost야. ProductCost 값은 바꾸지 말고 열 전체를 소수점 둘째 자리까지 표시해줘.
            1010-GL120-3C | Trainer - Tailspin GL-120 | 59.05
            1010-GL155-4C | Trainer - Tailspin GL-155 | 162.68
            2030-PCUB-3C | Piper Cub 3 Channel | 60.83
            2030-PCUB-4C | Piper Cub 4 Channel | 139.09
            2050-P47-4C | P47 4 Channel | 86.91
            2050-P47-5C | P47 5 Channel | 225.17
            2055-P51-5C | P51 | 217.35
            2060-SKYT-5C | SkyTrainer | 146.91
            3010-TAVM2-11-3C | Tailspin Aviator Mk2-11 | 126.32
            3010-TAVM2-12-4C | Tailspin Aviator Mk2-12 | 129.13
            3010-TAVM2-15-4C | Tailspin Aviator Mk2-15 | 140.79
            3010-TWAR-BM32-5C | Tailspin Warbird BM32 | 240.79
            3050-THeli-Co-Ax Pro-4C | Tailspin Heli - Co-Ax Pro Mk I - 4ch | 247.16
            3050-THeli-MaxPro-6C | Tailspin Heli - Max Pro Flight - 6ch | 367.16
            3050-THeli-Pro-5C | Tailspin Heli - Pro Mk III - 5ch | 255.16
            4010-3CAX-B-3C | 3CAX-B Helicopter | 39.96
            4010-3CFP-I-3C | 3CFP-I Helicopter | 95.16
            4030-4CAX-B-4C | 4CAX-B Helicopter | 95.96
            4030-4CFP-I-4C | 4CFP-I Helicopter | 111.96
            4040-6CCP-A-6C | 6CCP-A Helicopter | 151.96
            """
        ),
        Fixture(
            outputName: "AIChat_04_Manager_Category.xlsx",
            headers: ["Manager", "Email", "Category"],
            rows: [
                ["Ananya Kumar", "ananya-kumar@tailspintoys.com", "Collective Pitch"],
                ["Carmen Carrington", "carmen-carrington@tailspintoys.com", "Co-Axial;Fixed Pitch"],
                ["Haruto Suzuki", "haruto-suzuki@tailspintoys.com", "Fixed Pitch;Glider"],
                ["Jane Campbell", "jane-campbell@tailspintoys.com", "Collective Pitch;Fixed Pitch"],
                ["John Bishop", "john-bishop@tailspintoys.com", "Glider;Warbird"],
                ["Ted Baker", "ted-baker@tailspintoys.com", "Warbird"],
                ["Ty Johnston", "ty-johnston@tailspintoys.com", "Collective Pitch;Trainer;Warbird"],
            ],
            createRequest:
                "빈 시트에 Manager, Email, Category 열을 이 순서로 가진 정식 Excel 표를 만들어줘. 빈 데이터 행은 정확히 7개로 해줘.",
            fillRequest: """
            방금 만든 A1:C8 표의 빈 데이터 행 2행부터 8행까지 아래 순서 그대로 채워줘. 각 줄은 Manager | Email | Category야.
            Ananya Kumar | ananya-kumar@tailspintoys.com | Collective Pitch
            Carmen Carrington | carmen-carrington@tailspintoys.com | Co-Axial;Fixed Pitch
            Haruto Suzuki | haruto-suzuki@tailspintoys.com | Fixed Pitch;Glider
            Jane Campbell | jane-campbell@tailspintoys.com | Collective Pitch;Fixed Pitch
            John Bishop | john-bishop@tailspintoys.com | Glider;Warbird
            Ted Baker | ted-baker@tailspintoys.com | Warbird
            Ty Johnston | ty-johnston@tailspintoys.com | Collective Pitch;Trainer;Warbird
            """
        ),
        Fixture(
            outputName: "AIChat_05_Price_Band.xlsx",
            headers: ["PriceBandID", "Price Band", "From", "To"],
            rows: [
                ["10", "< 100", "0", "100"],
                ["20", ">=100 to < 500", "100", "500"],
                ["30", ">=500 to < 1500", "500", "1500"],
                ["40", ">= 1500", "1500", "9999999999"],
            ],
            createRequest:
                "빈 시트에 PriceBandID, Price Band, From, To 열을 이 순서로 가진 정식 Excel 표를 만들어줘. 빈 데이터 행은 정확히 4개로 해줘.",
            fillRequest: """
            방금 만든 A1:D5 표의 빈 데이터 행 2행부터 5행까지 아래 순서 그대로 채워줘. 각 줄은 PriceBandID | Price Band | From | To야. 비교 기호로 시작하는 Price Band도 조건이 아니라 셀에 넣을 문자 데이터이므로 적힌 그대로 넣어줘.
            10 | < 100 | 0 | 100
            20 | >=100 to < 500 | 100 | 500
            30 | >=500 to < 1500 | 500 | 1500
            40 | >= 1500 | 1500 | 9999999999
            """
        ),
    ]
}
