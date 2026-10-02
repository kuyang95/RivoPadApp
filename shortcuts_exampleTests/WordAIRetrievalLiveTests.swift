import RivoDocumentEngine
import Foundation
import XCTest

@testable import shortcuts_example

/// Opt-in, device-only live evaluation for the two-stage Word AI pipeline.
///
/// These tests call Gemini and consume the shared daily token budget, so normal
/// test runs skip them. Run one of the following explicitly on a signed device:
///
///     xcodebuild ... \
///       'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) WORD_AI_LIVE_SMOKE' \
///       -only-testing:shortcuts_exampleTests/WordAIRetrievalLiveTests/testDateEditSmoke test
///
///     xcodebuild ... \
///       'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) WORD_AI_LIVE_EVAL' \
///       -only-testing:shortcuts_exampleTests/WordAIRetrievalLiveTests/testLongDocumentBenchmark test
///
/// Each result is emitted as one `WORD_AI_EVAL_JSON` line so it can be archived
/// and reviewed without changing the retrieval algorithm during an evaluation.
@MainActor
final class WordAIRetrievalLiveTests: XCTestCase {
    fileprivate struct EvaluationCase {
        enum ExpectedIntent: String {
            case answer
            case clarify
            case edit
        }

        let id: String
        let documentName: String
        let blocks: [WordDocumentBlock]
        let request: String
        let expectedIntent: ExpectedIntent
        let evidenceGroups: [[String]]
        let answerGroups: [[String]]
    }

    fileprivate struct EvaluationResult: Encodable {
        let id: String
        let request: String
        let expectedIntent: String
        let routeIntent: String?
        let routeSectionIDs: [String]
        let routeBlockIDs: [String]
        let commandIntent: String?
        let assistantMessage: String?
        let operationDescriptions: [String]
        let documentBlocks: Int
        let documentCharacters: Int
        let catalogSections: Int
        let catalogCandidates: Int
        let catalogWasTruncated: Bool
        let snapshotBlocks: Int
        let snapshotCharacters: Int
        let routeTokens: Int
        let commandTokens: Int
        let evidencePassed: Bool
        let outcomePassed: Bool
        let error: String?
    }

    func testDateEditSmoke() async throws {
        try requireFlag("RUN_WORD_AI_LIVE_SMOKE")
        try configureFirebase()
        await refillTokenBudget()

        let result = await evaluate(Self.dateEditCase())
        emit(result)

        XCTAssertNil(result.error)
        XCTAssertTrue(result.evidencePassed)
        XCTAssertTrue(result.outcomePassed)
    }

    func testLongDocumentBenchmark() async throws {
        try requireFlag("RUN_WORD_AI_LIVE_EVAL")
        try configureFirebase()
        await refillTokenBudget()

        var results: [EvaluationResult] = []
        for item in Self.benchmarkCases() {
            let result = await evaluate(item)
            results.append(result)
            emit(result)
        }

        let summary = [
            "cases": results.count,
            "evidencePassed": results.filter(\.evidencePassed).count,
            "outcomePassed": results.filter(\.outcomePassed).count,
            "errors": results.compactMap(\.error).count,
            "tokens": results.reduce(0) {
                $0 + $1.routeTokens + $1.commandTokens
            },
        ]
        let data = try JSONSerialization.data(
            withJSONObject: summary,
            options: [.sortedKeys]
        )
        print(
            "WORD_AI_EVAL_SUMMARY "
                + String(decoding: data, as: UTF8.self)
        )

        XCTAssertEqual(results.count, Self.benchmarkCases().count)
        XCTAssertFalse(results.allSatisfy { $0.error != nil })
    }

    private func refillTokenBudget() async {
        #if DEBUG || WORD_AI_LIVE_EVAL || WORD_AI_LIVE_SMOKE
        let snapshot = await CloudAITokenBudgetStore
            .shared
            .refillForTesting()
        print(
            "WORD_AI_LIVE_TOKEN_BUDGET_REFILLED "
                + String(snapshot.remainingTokens)
        )
        #endif
    }

    private func requireFlag(_ name: String) throws {
        #if WORD_AI_LIVE_SMOKE
        if name == "RUN_WORD_AI_LIVE_SMOKE" { return }
        #endif
        #if WORD_AI_LIVE_EVAL
        if name == "RUN_WORD_AI_LIVE_EVAL" { return }
        #endif
        throw XCTSkip("\(name) 컴파일 플래그가 있을 때만 실제 Gemini 평가를 실행합니다.")
    }

    private func configureFirebase() throws {
        FirebaseRuntime.configureIfAvailable()
        XCTAssertTrue(
            FirebaseRuntime.isConfigured,
            "테스트 호스트에서 GoogleService-Info.plist를 찾지 못했습니다."
        )
        guard FirebaseRuntime.isConfigured else {
            throw WordAICommandServiceError.unavailable
        }
    }

    private func evaluate(_ item: EvaluationCase) async -> EvaluationResult {
        let catalog = WordAIRetrievalCatalogBuilder.make(
            documentName: item.documentName,
            blocks: item.blocks,
            userRequest: item.request
        )
        var routeIntent: String?
        var routeSectionIDs: [String] = []
        var routeBlockIDs: [String] = []
        var commandIntent: String?
        var assistantMessage: String?
        var operationDescriptions: [String] = []
        var snapshotBlocks = 0
        var snapshotCharacters = 0
        var routeTokens = 0
        var commandTokens = 0
        var evidencePassed = false
        var outcomePassed = false

        do {
            let beforeRoute = await CloudAITokenBudgetStore.shared.snapshot()
            let route = try await WordAICommandService.route(
                userRequest: item.request,
                catalog: catalog,
                history: []
            )
            let afterRoute = await CloudAITokenBudgetStore.shared.snapshot()
            routeTokens = max(0, afterRoute.usedTokens - beforeRoute.usedTokens)
            routeIntent = route.intent.rawValue
            routeSectionIDs = route.sectionIDs
            routeBlockIDs = route.blockIDs

            if route.intent == .clarify {
                assistantMessage = route.assistantMessage
                outcomePassed = item.expectedIntent == .clarify
                evidencePassed = outcomePassed
                return makeResult(
                    item: item,
                    catalog: catalog,
                    routeIntent: routeIntent,
                    routeSectionIDs: routeSectionIDs,
                    routeBlockIDs: routeBlockIDs,
                    commandIntent: commandIntent,
                    assistantMessage: assistantMessage,
                    operationDescriptions: operationDescriptions,
                    snapshotBlocks: snapshotBlocks,
                    snapshotCharacters: snapshotCharacters,
                    routeTokens: routeTokens,
                    commandTokens: commandTokens,
                    evidencePassed: evidencePassed,
                    outcomePassed: outcomePassed,
                    error: nil
                )
            }

            guard let snapshot = WordAISnapshotBuilder.makeRetrieved(
                documentName: item.documentName,
                blocks: item.blocks,
                selectedBlockID: nil,
                catalog: catalog,
                retrievalPlan: route
            ) else {
                throw WordAICommandServiceError.invalidResponse
            }
            snapshotBlocks = snapshot.blocks.count
            snapshotCharacters = snapshot.blocks.reduce(0) {
                $0 + $1.text.count
            }
            let retrievedText = snapshot.blocks.map(\.text).joined(separator: "\n")
            evidencePassed = matches(
                groups: item.evidenceGroups,
                in: retrievedText
            )

            let beforeCommand = await CloudAITokenBudgetStore.shared.snapshot()
            let command = try await WordAICommandService.plan(
                userRequest: item.request,
                snapshot: snapshot,
                history: []
            )
            let afterCommand = await CloudAITokenBudgetStore.shared.snapshot()
            commandTokens = max(
                0,
                afterCommand.usedTokens - beforeCommand.usedTokens
            )
            commandIntent = command.intent.rawValue
            assistantMessage = command.assistantMessage
            operationDescriptions = command.operations.map { operation in
                [
                    operation.kind.rawValue,
                    operation.blockID,
                    operation.newText ?? "",
                    operation.styleID ?? "",
                ].joined(separator: "|")
            }

            switch item.expectedIntent {
            case .answer:
                outcomePassed = command.intent == .answer
                    && command.operations.isEmpty
                    && matches(
                        groups: item.answerGroups,
                        in: command.assistantMessage
                    )
            case .clarify:
                outcomePassed = command.intent == .clarify
                    && command.operations.isEmpty
            case .edit:
                let operationText = command.operations.compactMap(\.newText)
                    .joined(separator: "\n")
                let validated = try WordAICommandValidator.validate(
                    command,
                    snapshot: snapshot,
                    userRequest: item.request
                )
                outcomePassed = command.intent == .edit
                    && validated != nil
                    && matches(groups: item.answerGroups, in: operationText)
            }

            return makeResult(
                item: item,
                catalog: catalog,
                routeIntent: routeIntent,
                routeSectionIDs: routeSectionIDs,
                routeBlockIDs: routeBlockIDs,
                commandIntent: commandIntent,
                assistantMessage: assistantMessage,
                operationDescriptions: operationDescriptions,
                snapshotBlocks: snapshotBlocks,
                snapshotCharacters: snapshotCharacters,
                routeTokens: routeTokens,
                commandTokens: commandTokens,
                evidencePassed: evidencePassed,
                outcomePassed: outcomePassed,
                error: nil
            )
        } catch {
            return makeResult(
                item: item,
                catalog: catalog,
                routeIntent: routeIntent,
                routeSectionIDs: routeSectionIDs,
                routeBlockIDs: routeBlockIDs,
                commandIntent: commandIntent,
                assistantMessage: assistantMessage,
                operationDescriptions: operationDescriptions,
                snapshotBlocks: snapshotBlocks,
                snapshotCharacters: snapshotCharacters,
                routeTokens: routeTokens,
                commandTokens: commandTokens,
                evidencePassed: evidencePassed,
                outcomePassed: false,
                error: String(describing: error)
            )
        }
    }

    private func makeResult(
        item: EvaluationCase,
        catalog: WordAIRetrievalCatalog,
        routeIntent: String?,
        routeSectionIDs: [String],
        routeBlockIDs: [String],
        commandIntent: String?,
        assistantMessage: String?,
        operationDescriptions: [String],
        snapshotBlocks: Int,
        snapshotCharacters: Int,
        routeTokens: Int,
        commandTokens: Int,
        evidencePassed: Bool,
        outcomePassed: Bool,
        error: String?
    ) -> EvaluationResult {
        EvaluationResult(
            id: item.id,
            request: item.request,
            expectedIntent: item.expectedIntent.rawValue,
            routeIntent: routeIntent,
            routeSectionIDs: routeSectionIDs,
            routeBlockIDs: routeBlockIDs,
            commandIntent: commandIntent,
            assistantMessage: assistantMessage,
            operationDescriptions: operationDescriptions,
            documentBlocks: item.blocks.count,
            documentCharacters: catalog.documentCharacterCount,
            catalogSections: catalog.sections.count,
            catalogCandidates: catalog.candidates.count,
            catalogWasTruncated: catalog.catalogWasTruncated,
            snapshotBlocks: snapshotBlocks,
            snapshotCharacters: snapshotCharacters,
            routeTokens: routeTokens,
            commandTokens: commandTokens,
            evidencePassed: evidencePassed,
            outcomePassed: outcomePassed,
            error: error
        )
    }

    private func matches(groups: [[String]], in text: String) -> Bool {
        groups.allSatisfy { alternatives in
            alternatives.contains { text.localizedCaseInsensitiveContains($0) }
        }
    }

    private func emit(_ result: EvaluationResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else {
            XCTFail("평가 결과 JSON 인코딩 실패")
            return
        }
        print("WORD_AI_EVAL_JSON " + String(decoding: data, as: UTF8.self))
    }
}

private extension WordAIRetrievalLiveTests {
    struct FactSection {
        let heading: String
        let primary: String
        let secondary: String
    }

    static func benchmarkCases() -> [EvaluationCase] {
        let labor = laborDocument()
        let statistics = statisticsDocument()
        let economy = economyDocument()
        return [
            EvaluationCase(
                id: "L01",
                documentName: "근로기준법_장문.docx",
                blocks: labor,
                request: "근로자를 해고하려면 며칠 전에 예고해야 해?",
                expectedIntent: .answer,
                evidenceGroups: [["30일 전", "30일전에"]],
                answerGroups: [["30일"]]
            ),
            EvaluationCase(
                id: "L02",
                documentName: "근로기준법_장문.docx",
                blocks: labor,
                request: "상시 근로자 4명인 사업장에도 법이 전부 적용돼?",
                expectedIntent: .answer,
                evidenceGroups: [["5명 이상"], ["일부 규정"]],
                answerGroups: [["5명"], ["일부"]]
            ),
            EvaluationCase(
                id: "L03",
                documentName: "근로기준법_장문.docx",
                blocks: labor,
                request: "퇴직 후 임금이 늦게 지급되면 지연이율은 얼마야?",
                expectedIntent: .answer,
                evidenceGroups: [["연 20퍼센트", "연 20%"]],
                answerGroups: [["20"]]
            ),
            EvaluationCase(
                id: "L04",
                documentName: "근로기준법_장문.docx",
                blocks: labor,
                request: "사용자가 근로자를 폭행하면 처벌은 어떻게 돼?",
                expectedIntent: .answer,
                evidenceGroups: [["5년 이하"], ["5천만원 이하", "5000만원 이하"]],
                answerGroups: [["5년"], ["5천", "5000"]]
            ),
            EvaluationCase(
                id: "L05",
                documentName: "근로기준법_장문.docx",
                blocks: labor,
                request: "1년간 80퍼센트 이상 출근하면 연차가 며칠이야?",
                expectedIntent: .answer,
                evidenceGroups: [["80퍼센트 이상"], ["15일"]],
                answerGroups: [["15일"]]
            ),
            EvaluationCase(
                id: "S01",
                documentName: "2025_고령자통계_장문.docx",
                blocks: statistics,
                request: "2025년 65세 이상 인구 비중은 얼마야?",
                expectedIntent: .answer,
                evidenceGroups: [["20.3퍼센트", "20.3%"]],
                answerGroups: [["20.3"]]
            ),
            EvaluationCase(
                id: "S02",
                documentName: "2025_고령자통계_장문.docx",
                blocks: statistics,
                request: "고령인구 비율의 성별 격차를 알려줘.",
                expectedIntent: .answer,
                evidenceGroups: [["22.6"], ["18.0"], ["4.6"]],
                answerGroups: [["22.6"], ["18.0", "18%"], ["4.6"]]
            ),
            EvaluationCase(
                id: "S03",
                documentName: "2025_고령자통계_장문.docx",
                blocks: statistics,
                request: "65세 이상 고령자의 인터넷 이용률은?",
                expectedIntent: .answer,
                evidenceGroups: [["76.9퍼센트", "76.9%"]],
                answerGroups: [["76.9"]]
            ),
            EvaluationCase(
                id: "S04",
                documentName: "2025_고령자통계_장문.docx",
                blocks: statistics,
                request: "인터넷 이용 고령자 중 메신저 이용률은 얼마야?",
                expectedIntent: .answer,
                evidenceGroups: [["92.6퍼센트", "92.6%"]],
                answerGroups: [["92.6"]]
            ),
            EvaluationCase(
                id: "S05",
                documentName: "2025_고령자통계_장문.docx",
                blocks: statistics,
                request: "고령자 비율은 얼마야?",
                expectedIntent: .clarify,
                evidenceGroups: [],
                answerGroups: []
            ),
            EvaluationCase(
                id: "E01",
                documentName: "2026_경제전망_장문.docx",
                blocks: economy,
                request: "2026년 국내총생산 성장률 전망은?",
                expectedIntent: .answer,
                evidenceGroups: [["2.0퍼센트", "2.0%"]],
                answerGroups: [["2.0", "2%"]]
            ),
            EvaluationCase(
                id: "E02",
                documentName: "2026_경제전망_장문.docx",
                blocks: economy,
                request: "2026년 경상수지 흑자 규모는 얼마로 전망해?",
                expectedIntent: .answer,
                evidenceGroups: [["1,700억 달러", "1700억 달러"]],
                answerGroups: [["1,700억", "1700억"]]
            ),
            EvaluationCase(
                id: "E03",
                documentName: "2026_경제전망_장문.docx",
                blocks: economy,
                request: "수출이 증가하는 주된 이유는 뭐야?",
                expectedIntent: .answer,
                evidenceGroups: [["반도체 수요"]],
                answerGroups: [["반도체"]]
            ),
            EvaluationCase(
                id: "E04",
                documentName: "2026_경제전망_장문.docx",
                blocks: economy,
                request: "비관 시나리오에서 내년 성장률은 기본 전망보다 얼마나 낮아져?",
                expectedIntent: .answer,
                evidenceGroups: [["0.3퍼센트포인트", "0.3%포인트"]],
                answerGroups: [["0.3"]]
            ),
            EvaluationCase(
                id: "E05",
                documentName: "2026_경제전망_장문.docx",
                blocks: economy,
                request: "2026년 2.0퍼센트 전망치는 무엇을 뜻해?",
                expectedIntent: .clarify,
                evidenceGroups: [],
                answerGroups: []
            ),
            dateEditCase(),
        ]
    }

    static func dateEditCase() -> EvaluationCase {
        EvaluationCase(
            id: "W01",
            documentName: "프로젝트_상태보고서_장문.docx",
            blocks: dateReportDocument(),
            request: "작성일을 하루 뒤로 바꿔줘.",
            expectedIntent: .edit,
            evidenceGroups: [["작성일: 2026-08-25"]],
            answerGroups: [["작성일: 2026-08-26"]]
        )
    }

    static func laborDocument() -> [WordDocumentBlock] {
        makeLongDocument(
            prefix: "labor",
            title: "근로기준법 해설 자료",
            subject: "근로조건과 사업장 운영",
            facts: [
                9: FactSection(
                    heading: "법의 적용 범위",
                    primary: "이 법은 상시 5명 이상의 근로자를 사용하는 모든 사업 또는 사업장에 적용한다.",
                    secondary: "상시 4명 이하의 근로자를 사용하는 사업 또는 사업장에는 대통령령으로 정하는 일부 규정만 적용할 수 있으므로 전부 적용되는 것은 아니다."
                ),
                27: FactSection(
                    heading: "해고의 예고",
                    primary: "사용자는 근로자를 해고하려면 적어도 30일 전에 예고하여야 한다.",
                    secondary: "30일 전에 예고하지 아니하였을 때에는 30일분 이상의 통상임금을 지급하여야 한다."
                ),
                44: FactSection(
                    heading: "임금 지급 지연에 대한 이자",
                    primary: "퇴직한 근로자에게 지급 사유 발생일부터 14일 이내에 임금을 지급하지 않으면 그 다음 날부터 지급일까지 연 20퍼센트의 지연이자를 지급한다.",
                    secondary: "당사자 합의로 지급 기일을 연장한 경우 등 법령이 정한 사유가 있으면 적용 범위를 따로 확인한다."
                ),
                63: FactSection(
                    heading: "폭행의 금지와 벌칙",
                    primary: "사용자는 사고 발생이나 그 밖의 어떠한 이유로도 근로자에게 폭행을 하지 못한다.",
                    secondary: "이를 위반한 사용자는 5년 이하의 징역 또는 5천만원 이하의 벌금에 처한다."
                ),
                78: FactSection(
                    heading: "연차 유급휴가",
                    primary: "사용자는 1년간 80퍼센트 이상 출근한 근로자에게 15일의 유급휴가를 주어야 한다.",
                    secondary: "계속하여 근로한 기간이 1년 미만인 근로자에 대해서는 별도의 발생 기준을 적용한다."
                ),
            ]
        )
    }

    static func statisticsDocument() -> [WordDocumentBlock] {
        makeLongDocument(
            prefix: "stats",
            title: "2025 고령자 통계",
            subject: "인구·가구·소득·건강·정보화 지표",
            facts: [
                12: FactSection(
                    heading: "고령인구 규모",
                    primary: "2025년 우리나라 65세 이상 고령인구는 전체 인구의 20.3퍼센트이다.",
                    secondary: "고령인구 비중은 지역별 인구구조와 이동에 따라 서로 다르게 나타난다."
                ),
                31: FactSection(
                    heading: "고령인구의 성별 구성",
                    primary: "2025년 65세 이상 인구 비율은 여자가 22.6퍼센트이고 남자가 18.0퍼센트이다.",
                    secondary: "여자와 남자의 고령인구 비율 차이는 4.6퍼센트포인트이다."
                ),
                49: FactSection(
                    heading: "인터넷 이용",
                    primary: "65세 이상 고령자의 인터넷 이용률은 76.9퍼센트로 조사되었다.",
                    secondary: "인터넷 이용 여부는 연령대와 교육 수준, 지역에 따라 차이가 있다."
                ),
                67: FactSection(
                    heading: "인터넷 서비스 이용",
                    primary: "인터넷을 이용하는 고령자 가운데 인스턴트 메신저 이용률은 92.6퍼센트이다.",
                    secondary: "동영상과 뉴스, 금융 서비스 이용률은 각각 다른 지표로 집계한다."
                ),
                80: FactSection(
                    heading: "고용과 생활 지표",
                    primary: "고령자의 고용률, 상대적 빈곤율, 독거 비율은 서로 다른 모집단과 산식으로 작성한다.",
                    secondary: "따라서 단순히 고령자 비율이라고 물으면 인구 비중인지 고용률인지 다른 지표인지 확인해야 한다."
                ),
            ]
        )
    }

    static func economyDocument() -> [WordDocumentBlock] {
        makeLongDocument(
            prefix: "economy",
            title: "2026년 경제전망",
            subject: "성장·물가·수출입·경상수지와 위험 시나리오",
            facts: [
                11: FactSection(
                    heading: "국내총생산 성장률",
                    primary: "2026년 실질 국내총생산 성장률은 2.0퍼센트로 전망한다.",
                    secondary: "민간소비 회복과 설비투자가 성장에 기여할 것으로 예상한다."
                ),
                29: FactSection(
                    heading: "소비자물가 전망",
                    primary: "2026년 소비자물가 상승률도 2.0퍼센트로 전망한다.",
                    secondary: "국제유가와 환율 변동은 물가 전망의 주요 불확실성이다."
                ),
                46: FactSection(
                    heading: "경상수지",
                    primary: "2026년 경상수지는 1,700억 달러 흑자를 기록할 것으로 전망한다.",
                    secondary: "상품수지 개선이 서비스수지 적자를 웃돌 것으로 예상한다."
                ),
                61: FactSection(
                    heading: "수출 전망",
                    primary: "수출 증가는 인공지능 서버와 데이터센터 투자 확대로 이어진 반도체 수요 증가가 주된 이유이다.",
                    secondary: "자동차와 화학제품의 흐름은 국가별 수요와 통상 여건에 따라 엇갈릴 수 있다."
                ),
                77: FactSection(
                    heading: "비관 시나리오",
                    primary: "비관 시나리오에서 내년 성장률은 기본 전망보다 0.3퍼센트포인트 낮아진다.",
                    secondary: "통상 갈등 심화와 금융시장 변동성 확대를 하방 위험으로 가정한 결과이다."
                ),
            ]
        )
    }

    static func dateReportDocument() -> [WordDocumentBlock] {
        makeLongDocument(
            prefix: "report",
            title: "접근성 프로젝트 상태 보고서",
            subject: "기능·품질·일정·리스크 점검",
            facts: [
                66: FactSection(
                    heading: "보고서 정보",
                    primary: "작성일: 2026-08-25",
                    secondary: "문서 상태: 내부 검토 중"
                )
            ],
            sectionCount: 72
        )
    }

    static func makeLongDocument(
        prefix: String,
        title: String,
        subject: String,
        facts: [Int: FactSection],
        sectionCount: Int = 84
    ) -> [WordDocumentBlock] {
        var blocks: [WordDocumentBlock] = []

        func append(_ text: String, style: String) {
            let index = blocks.count
            blocks.append(
                WordDocumentBlock(
                    id: "\(prefix)-block-\(index)",
                    paragraphIndex: index,
                    text: text,
                    styleID: style,
                    isNumbered: false,
                    tableLocation: nil,
                    isEditable: true
                )
            )
        }

        append(title, style: "Title")
        for section in 0..<sectionCount {
            if let fact = facts[section] {
                append(fact.heading, style: "Heading1")
                append(fact.primary, style: "Normal")
                append(fact.secondary, style: "Normal")
                continue
            }

            append("\(subject) 세부 항목 \(section + 1)", style: "Heading1")
            append(
                "이 절은 \(subject)의 일반 현황과 조사 기준, 적용 절차를 설명한다. 기준 시점과 대상 범위를 구분하고 관련 자료의 정의를 확인해야 하며, 세부 값은 해당 항목의 본문을 따른다.",
                style: "Normal"
            )
            append(
                "검토 번호 \(section + 1)의 참고 내용은 다른 절의 수치나 날짜를 대신하지 않는다. 유사한 표현이 있어도 제목과 문맥, 단위, 모집단을 함께 비교하여 판단한다.",
                style: "Normal"
            )
        }
        return blocks
    }
}
