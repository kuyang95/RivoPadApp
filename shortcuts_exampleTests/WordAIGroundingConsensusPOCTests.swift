import XCTest

@testable import shortcuts_example

final class WordAIGroundingConsensusPOCTests: XCTestCase {
    func testReconstructsFactFromSourceWhenModelParaphrases() {
        let source = "사용자는 근로자를 해고하려면 적어도 30일 전에 예고하여야 한다."
        let evidence = block("notice", source)
        let result = validate(
            question: "해고 예고 기간은?",
            blocks: [evidence],
            response: answer(
                claim: "해고는 한 달 전에 알려야 한다.",
                blockID: evidence.id,
                quote: source
            )
        )

        XCTAssertEqual(result.state, .verified)
        XCTAssertEqual(result.displayText, source)
    }

    func testIgnoresFabricatedClaimValueAndDisplaysVerifiedSource() {
        let source = "2026년 성장률은 2.0퍼센트다."
        let evidence = block("gdp", source, scope: "2026년 경제전망")
        let result = validate(
            question: "2026년 성장률은?",
            blocks: [evidence],
            response: answer(
                claim: "2026년 성장률은 9.9퍼센트다.",
                blockID: evidence.id,
                quote: source
            )
        )

        XCTAssertEqual(result.state, .verified)
        XCTAssertEqual(result.displayText, source)
        XCTAssertFalse(result.displayText?.contains("9.9") == true)
    }

    func testAcceptsVerifiedEvidenceFromSecondRetrievedCandidate() {
        let blocks = [
            block("pointer", "2026년 기준 시나리오 매출은 부록에서 다룬다."),
            block("answer", "2026년 기준 시나리오 매출은 100억원이다."),
        ]
        let result = validate(
            question: "2026년 기준 시나리오 매출은?",
            blocks: blocks,
            topCandidates: ["pointer"],
            response: answer(
                claim: "매출은 100억원입니다.",
                blockID: "answer",
                quote: blocks[1].text
            )
        )

        XCTAssertEqual(result.state, .verified)
        XCTAssertTrue(result.displayText?.contains("100억원") == true)
    }

    func testRejectsWrongScenarioEvenWhenItWasRetrieved() {
        let blocks = [
            block(
                "baseline",
                "2026년 실질 국내총생산 성장률의 기본 전망은 2.0퍼센트다."
            ),
            block("downside", "2026년 성장률 비관 전망은 1.7퍼센트다."),
        ]
        let result = validate(
            question: "2026년 실질 국내총생산 성장률의 기본 전망은?",
            blocks: blocks,
            topCandidates: ["baseline"],
            response: answer(
                claim: blocks[1].text,
                blockID: "downside",
                quote: blocks[1].text
            )
        )

        XCTAssertEqual(result.state, .rejected)
        XCTAssertEqual(result.reasons, ["evidenceNotRelevantToQuestion"])
    }

    func testRejectsEvidenceOutsideLocalRetrievedCandidates() {
        let blocks = [
            block("retrieved", "2026년 성장률은 2.0퍼센트다."),
            block("outside", "2026년 성장률은 9.9퍼센트다."),
        ]
        let context = WordAIGroundingContext(
            question: "2026년 성장률은?",
            blocks: blocks,
            requiresClarification: false,
            eligibleEvidenceBlockIDs: ["retrieved"]
        )
        let response = answer(
            claim: blocks[1].text,
            blockID: "outside",
            quote: blocks[1].text
        )

        let result = WordAIGroundingValidator.validate(
            response,
            context: context,
            policy: .retrievedEvidenceConsensus
        )

        XCTAssertEqual(result.state, .rejected)
        XCTAssertEqual(result.reasons, ["evidenceOutsideEligibleCandidates"])
    }

    func testInheritsRequestedYearFromTrustedHeadingScope() {
        let source = "여름철 강수량 대비 장마철 강수량은 78.8퍼센트로 1973년 이래 가장 큰 비율이었다."
        let evidence = block(
            "rain",
            source,
            scope: "2024 기상연감 > 2024년 우리나라 기후특성"
        )
        let result = validate(
            question: "2024년 여름철 강수량 중 장마철 강수량 비율은?",
            blocks: [evidence],
            response: answer(
                claim: "2024년 비율은 78.8퍼센트다.",
                blockID: evidence.id,
                quote: source
            )
        )

        XCTAssertEqual(result.state, .verified)
        XCTAssertTrue(result.displayText?.contains("78.8퍼센트") == true)
    }

    func testDoesNotOverrideLeadingConflictingYearWithHeadingScope() {
        let source = "2023년 우리나라 연강수량은 1,414.6밀리미터였다."
        let evidence = block(
            "rain-2023",
            source,
            scope: "2024 기상연감 > 2024년 강수량"
        )
        let result = validate(
            question: "2024년 우리나라 연강수량은?",
            blocks: [evidence],
            response: answer(
                claim: source,
                blockID: evidence.id,
                quote: source
            )
        )

        XCTAssertEqual(result.state, .rejected)
        XCTAssertEqual(result.reasons, ["questionValueNotInEvidence"])
    }

    func testNeverInheritsRequestedAnswerNumberFromScope() {
        let source = "여름철 강수량은 평년과 비슷했다."
        let evidence = block(
            "rain",
            source,
            scope: "2024년 장마철 비율 78.8퍼센트"
        )
        let result = validate(
            question: "2024년 장마철 강수량 비율은 78.8퍼센트야?",
            blocks: [evidence],
            response: answer(
                claim: "78.8퍼센트다.",
                blockID: evidence.id,
                quote: source
            )
        )

        XCTAssertEqual(result.state, .rejected)
        XCTAssertEqual(result.reasons, ["questionValueNotInEvidence"])
    }

    func testMergesDuplicateEvidenceOnlyAfterStrongAgreement() {
        let blocks = [
            block(
                "summary",
                "전반적인 가족 관계 만족도는 63.5퍼센트로 2년 전보다 1.0퍼센트포인트 감소했다.",
                scope: "2024년 사회조사 > 요약"
            ),
            block(
                "detail",
                "가족 조사에서 전반적인 가족 관계 만족도는 63.5퍼센트로 2년 전보다 1.0퍼센트포인트 감소했다.",
                scope: "2024년 사회조사 > 가족"
            ),
        ]
        let question = "2024년 전반적인 가족 관계 만족도는?"
        let ambiguity = WordAIGroundingAmbiguityDetector.analyze(
            question: question,
            blocks: blocks
        )
        XCTAssertTrue(ambiguity.requiresClarification)

        let result = validate(
            question: question,
            blocks: blocks,
            requiresClarification: true,
            topCandidates: ambiguity.candidateBlockIDs,
            response: answer(
                claim: "가족 관계 만족도는 63.5퍼센트다.",
                blockID: "summary",
                quote: blocks[0].text
            )
        )

        XCTAssertEqual(result.state, .verified)
        XCTAssertTrue(result.displayText?.contains("63.5퍼센트") == true)
    }

    func testSameNumberForDifferentMetricsStillClarifies() {
        let blocks = [
            block("gdp", "2026년 국내총생산 성장률은 2.0퍼센트다."),
            block("cpi", "2026년 소비자물가 상승률은 2.0퍼센트다."),
        ]
        assertAmbiguousAnswerRemainsClarification(
            question: "2026년 2.0퍼센트 전망치는 무엇을 뜻해?",
            blocks: blocks,
            selectedBlockID: "gdp"
        )
    }

    func testDifferentValuesForSameMetricStillClarify() {
        let blocks = [
            block(
                "summary",
                "2024년 연간 폭염일수와 열대야일수는 각각 31.1일과 24.4일이다."
            ),
            block(
                "detail",
                "2024년 연간 폭염일수와 열대야일수는 각각 30.1일과 24.5일이다."
            ),
        ]
        assertAmbiguousAnswerRemainsClarification(
            question: "2024년 연간 폭염일수와 열대야일수는?",
            blocks: blocks,
            selectedBlockID: "summary"
        )
    }

    func testPageHeadersAndUnrelatedNumbersCannotHideConflictingHeatValues() {
        let blocks = [
            block(
                "summary-page",
                "제1부 주요정책 및 이슈 02 2024년 우리나라 기후특성. 봄철 일부 지역에서는 30도 내외로 기온이 올랐다. 9월 전국 평균기온은 24.7도였으며 연간 폭염일수와 열대야일수는 각각 31.1일, 24.4일이었다. 온열질환자는 3,704명으로 31.4퍼센트 증가했다."
            ),
            block(
                "issue-page",
                "제1부 주요정책 및 이슈 04 2024년 기상이슈 4.1 올여름 최고의 더위. 2024년 연간 폭염일수는 30.1일로 평년 11.0일보다 19.1일 많았다. 2024년 열대야일수는 24.5일이었다."
            ),
        ]
        let question = "2024년 연간 폭염일수와 열대야일수는?"
        let ambiguity = WordAIGroundingAmbiguityDetector.analyze(
            question: question,
            blocks: blocks
        )
        XCTAssertTrue(ambiguity.requiresClarification)
        let result = validate(
            question: question,
            blocks: blocks,
            requiresClarification: true,
            topCandidates: ambiguity.candidateBlockIDs,
            response: answer(
                claim: "폭염 30.1일, 열대야 24.5일",
                blockID: "issue-page",
                quote: "2024년 연간 폭염일수는 30.1일로 평년 11.0일보다 19.1일 많았다."
            )
        )
        XCTAssertEqual(result.state, .clarify)
        XCTAssertEqual(result.reasons, ["localAmbiguityDetected"])
    }

    func testModelCannotOmitConflictingCandidateByCitingOnlyPreferredPage() {
        let blocks = [
            block(
                "summary-page",
                "9월 전국 평균기온은 24.7℃로 평년(20.5℃)보다 4.2℃ 높게 나타났으며, 연간 폭염일수와 열대야일수는 각각 31.1일, 24.4일로 각각 2위, 1위를 기록하였다."
            ),
            block(
                "issue-page",
                "여름철 고온이 이례적으로 9월 중순까지 이어지며 2024년 연간 폭염일수는 30.1일로 평년(11.0일)보다 19.1일이나 많았고, 2018년(31.0일)보다는 0.9일 적어 역대 2위를 기록하였다. 또한, 올해 두드러진 특징은 열대야도 9월까지 이어지며, 2024년 열대야일수가 평년(6.6일) 대비 약 3.7배 많은 24.5일로 역대 1위를 기록하였다."
            ),
        ]
        let question = "2024년 연간 폭염일수와 열대야일수는 정확히 며칠이야?"
        let response = WordAIGroundingResponse(
            intent: .answer,
            assistantMessage: "폭염일수는 30.1일, 열대야일수는 24.5일입니다.",
            claims: [
                .init(
                    text: "폭염일수는 30.1일입니다.",
                    kind: .extractiveFact,
                    evidence: [
                        .init(
                            blockID: "issue-page",
                            quote: "여름철 고온이 이례적으로 9월 중순까지 이어지며 2024년 연간 폭염일수는 30.1일로 평년(11.0일)보다 19.1일이나 많았고, 2018년(31.0일)보다는 0.9일 적어 역대 2위를 기록하였다."
                        ),
                    ]
                ),
                .init(
                    text: "열대야일수는 24.5일입니다.",
                    kind: .extractiveFact,
                    evidence: [
                        .init(
                            blockID: "issue-page",
                            quote: "또한, 올해 두드러진 특징은 열대야도 9월까지 이어지며, 2024년 열대야일수가 평년(6.6일) 대비 약 3.7배 많은 24.5일로 역대 1위를 기록하였다."
                        ),
                    ]
                ),
            ]
        )
        let result = validate(
            question: question,
            blocks: blocks,
            requiresClarification: true,
            topCandidates: blocks.map(\.id),
            response: response
        )

        XCTAssertEqual(result.state, .clarify)
        XCTAssertEqual(result.reasons, ["localAmbiguityDetected"])
    }

    func testModelCannotHideConflictByCitingBothCandidates() {
        let blocks = [
            block(
                "summary",
                "2024년 연간 폭염일수와 열대야일수는 각각 31.1일과 24.4일이다."
            ),
            block(
                "detail",
                "2024년 연간 폭염일수와 열대야일수는 각각 30.1일과 24.5일이다."
            ),
        ]
        let response = WordAIGroundingResponse(
            intent: .answer,
            assistantMessage: "두 페이지를 모두 인용했습니다.",
            claims: [
                .init(
                    text: blocks[0].text,
                    kind: .extractiveFact,
                    evidence: [
                        .init(blockID: blocks[0].id, quote: blocks[0].text),
                    ]
                ),
                .init(
                    text: blocks[1].text,
                    kind: .extractiveFact,
                    evidence: [
                        .init(blockID: blocks[1].id, quote: blocks[1].text),
                    ]
                ),
            ]
        )
        let result = validate(
            question: "2024년 연간 폭염일수와 열대야일수는?",
            blocks: blocks,
            requiresClarification: true,
            topCandidates: blocks.map(\.id),
            response: response
        )

        XCTAssertEqual(result.state, .clarify)
        XCTAssertEqual(result.reasons, ["localAmbiguityDetected"])
    }

    func testSameValueForDifferentYearsStillClarifies() {
        let blocks = [
            block("year-2025", "2025년 성장률은 2.0퍼센트다."),
            block("year-2026", "2026년 성장률은 2.0퍼센트다."),
        ]
        assertAmbiguousAnswerRemainsClarification(
            question: "성장률은 얼마야?",
            blocks: blocks,
            selectedBlockID: "year-2025"
        )
    }

    func testSameNumericMagnitudeWithDifferentUnitsStillClarifies() {
        let blocks = [
            block("percent", "성장률은 2.0퍼센트다."),
            block("point", "성장률 변화 폭은 2.0퍼센트포인트다."),
        ]
        assertAmbiguousAnswerRemainsClarification(
            question: "성장률은?",
            blocks: blocks,
            selectedBlockID: "percent"
        )
    }

    private func assertAmbiguousAnswerRemainsClarification(
        question: String,
        blocks: [WordAIGroundingBlock],
        selectedBlockID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let ambiguity = WordAIGroundingAmbiguityDetector.analyze(
            question: question,
            blocks: blocks
        )
        XCTAssertTrue(
            ambiguity.requiresClarification,
            file: file,
            line: line
        )
        guard let selected = blocks.first(where: { $0.id == selectedBlockID }) else {
            XCTFail("missing selected block", file: file, line: line)
            return
        }
        let result = validate(
            question: question,
            blocks: blocks,
            requiresClarification: true,
            topCandidates: ambiguity.candidateBlockIDs,
            response: answer(
                claim: selected.text,
                blockID: selected.id,
                quote: selected.text
            )
        )
        XCTAssertEqual(result.state, .clarify, file: file, line: line)
        XCTAssertEqual(
            result.reasons,
            ["localAmbiguityDetected"],
            file: file,
            line: line
        )
    }

    private func validate(
        question: String,
        blocks: [WordAIGroundingBlock],
        requiresClarification: Bool = false,
        topCandidates: [String] = [],
        response: WordAIGroundingResponse
    ) -> WordAIGroundingValidation {
        let context = WordAIGroundingContext(
            question: question,
            blocks: blocks,
            requiresClarification: requiresClarification,
            topCandidateBlockIDs: topCandidates,
            eligibleEvidenceBlockIDs: blocks.map(\.id)
        )
        return WordAIGroundingValidator.validate(
            response,
            context: context,
            policy: .retrievedEvidenceConsensus
        )
    }

    private func block(
        _ id: String,
        _ text: String,
        scope: String = ""
    ) -> WordAIGroundingBlock {
        WordAIGroundingBlock(
            id: id,
            sectionID: id,
            text: text,
            scopeText: scope
        )
    }

    private func answer(
        claim: String,
        blockID: String,
        quote: String
    ) -> WordAIGroundingResponse {
        WordAIGroundingResponse(
            intent: .answer,
            assistantMessage: "문서에서 확인했습니다.",
            claims: [
                .init(
                    text: claim,
                    kind: .extractiveFact,
                    evidence: [.init(blockID: blockID, quote: quote)]
                )
            ]
        )
    }
}

final class WordAIGroundingV9POCTests: XCTestCase {
    func testGuardrailAcceptsParaphraseWithExactCitation() {
        let source = "서비스형 LLM 방식에 비해 기성 LLM 활용 시 더 높은 모델 통제권을 보유"
        let response = answer(
            message: "기성 LLM은 서비스형 LLM보다 모델 통제권이 높습니다.",
            claim: "기성 LLM의 모델 통제권이 더 높다.",
            source: source
        )
        let guardrail = validate(response, source: source)

        XCTAssertEqual(guardrail.state, .passed)
        let result = WordAIGroundingDecision.make(
            response: response,
            guardrail: guardrail,
            review: supportedReview
        )
        XCTAssertEqual(result.state, .verified)
        XCTAssertEqual(result.displayText, response.assistantMessage)
        XCTAssertFalse(result.displayText?.contains("구 분 내 용") == true)
    }

    func testGuardrailRejectsAnswerNumberMissingFromCitation() {
        let source = "2026년 성장률은 2.0퍼센트다."
        let response = answer(
            message: "2026년 성장률은 9.9퍼센트입니다.",
            claim: "2026년 성장률은 9.9퍼센트다.",
            source: source
        )

        let result = validate(response, source: source)

        XCTAssertEqual(result.state, .rejected)
        XCTAssertEqual(result.reasons, ["claimValueNotInEvidence"])
    }

    func testLexicalAmbiguityCannotOverrideSupportedSemanticReview() {
        let source = "전반적인 가족 관계 만족도는 63.5퍼센트다."
        let duplicate = "요약: 전반적인 가족 관계 만족도는 63.5퍼센트다."
        let response = answer(
            message: "전반적인 가족 관계 만족도는 63.5%입니다.",
            claim: "가족 관계 만족도는 63.5퍼센트다.",
            source: source
        )
        let blocks = [
            block("source", source),
            block("duplicate", duplicate),
        ]
        let context = WordAIGroundingContext(
            question: "가족 관계 만족도는?",
            blocks: blocks,
            requiresClarification: true,
            topCandidateBlockIDs: blocks.map(\.id),
            eligibleEvidenceBlockIDs: blocks.map(\.id)
        )
        let guardrail = WordAIEvidenceGuardrail.validate(
            response,
            context: context
        )

        XCTAssertEqual(guardrail.state, .passed)
        let decision = WordAIGroundingDecision.make(
            response: response,
            guardrail: guardrail,
            review: supportedReview
        )
        XCTAssertEqual(decision.state, .verified)
        XCTAssertEqual(decision.displayText, response.assistantMessage)
    }

    func testContradictionUsesSpecificReviewerMessage() {
        let source = "연간 폭염일수는 30.1일이다."
        let response = answer(
            message: "연간 폭염일수는 30.1일입니다.",
            claim: "연간 폭염일수는 30.1일이다.",
            source: source
        )
        let guardrail = validate(response, source: source)
        let review = WordAIGroundingSemanticReview(
            verdict: .contradicted,
            questionType: .factual,
            reviewedBlockIDs: ["source"],
            candidateFindings: [
                .init(
                    blockID: "source",
                    support: .completeAnswer,
                    answerValues: ["30.1일"],
                    quote: source
                )
            ],
            explicitConclusionBlockID: "",
            explicitConclusionQuote: "",
            userMessage: "문서에는 폭염일수가 30.1일과 31.1일로 다르게 적혀 있습니다. 어느 통계 기준을 원하시나요?",
            explanation: "동일 기간과 지표에 상충 수치가 있음"
        )

        let decision = WordAIGroundingDecision.make(
            response: response,
            guardrail: guardrail,
            review: review
        )

        XCTAssertEqual(decision.state, .clarify)
        XCTAssertEqual(decision.reasons, ["semanticContradiction"])
        XCTAssertTrue(decision.displayText?.contains("30.1일과 31.1일") == true)
    }

    func testModelClarificationIsShownInsteadOfCandidateDump() {
        let response = WordAIGroundingResponse(
            intent: .clarify,
            assistantMessage: "문서에 2027년 개정일이 없습니다. 다른 연도를 확인할까요?",
            claims: []
        )
        let context = WordAIGroundingContext(
            question: "2027년 개정일은?",
            blocks: [block("source", "2025년 8월 발간")],
            requiresClarification: true,
            eligibleEvidenceBlockIDs: ["source"]
        )
        let guardrail = WordAIEvidenceGuardrail.validate(
            response,
            context: context
        )
        let decision = WordAIGroundingDecision.make(
            response: response,
            guardrail: guardrail,
            review: nil
        )

        XCTAssertEqual(decision.state, .clarify)
        XCTAssertEqual(decision.displayText, response.assistantMessage)
    }

    func testSemanticAuditRequiresEveryCandidateFinding() {
        let blocks = [
            block("a", "연간 폭염일수는 30.1일이다."),
            block("b", "연간 폭염일수는 31.1일이다."),
        ]
        let raw = semanticReview(
            findings: [
                .init(
                    blockID: "a",
                    support: .completeAnswer,
                    answerValues: ["30.1일"],
                    quote: blocks[0].text
                )
            ]
        )

        let audited = WordAIGroundingSemanticAudit.evaluate(
            raw,
            question: "연간 폭염일수는?",
            blocks: blocks
        )

        XCTAssertEqual(audited.review.verdict, .insufficient)
        XCTAssertEqual(
            audited.reasons,
            ["semanticReviewCandidateCoverageMismatch"]
        )
    }

    func testSemanticAuditRejectsConflictingCompleteNumericAnswers() {
        let blocks = [
            block("a", "연간 폭염일수는 30.1일, 열대야일수는 24.5일이다."),
            block("b", "연간 폭염일수는 31.1일, 열대야일수는 24.4일이다."),
        ]
        let raw = semanticReview(
            findings: [
                .init(
                    blockID: "a",
                    support: .completeAnswer,
                    answerValues: ["30.1일", "24.5일"],
                    quote: blocks[0].text
                ),
                .init(
                    blockID: "b",
                    support: .completeAnswer,
                    answerValues: ["31.1일", "24.4일"],
                    quote: blocks[1].text
                ),
            ]
        )

        let audited = WordAIGroundingSemanticAudit.evaluate(
            raw,
            question: "연간 폭염일수와 열대야일수는 정확히 며칠이야?",
            blocks: blocks
        )

        XCTAssertEqual(audited.review.verdict, .contradicted)
        XCTAssertEqual(
            audited.reasons,
            ["semanticReviewNumericAnswerConflict"]
        )
        XCTAssertTrue(audited.review.userMessage.contains("30.1일, 24.5일"))
        XCTAssertTrue(audited.review.userMessage.contains("31.1일, 24.4일"))
    }

    func testSemanticAuditTreatsMissingUnitAsSameNumericAnswer() {
        let blocks = [
            block("sentence", "한 가정의 이상적인 자녀 수는 평균 1.89명이다."),
            block("table", "이상적인 자녀 수 평균 1.89"),
        ]
        let raw = semanticReview(
            findings: [
                .init(
                    blockID: "sentence",
                    support: .completeAnswer,
                    answerValues: ["1.89"],
                    quote: blocks[0].text
                ),
                .init(
                    blockID: "table",
                    support: .completeAnswer,
                    answerValues: ["1.89명"],
                    quote: blocks[1].text
                ),
            ]
        )

        let audited = WordAIGroundingSemanticAudit.evaluate(
            raw,
            question: "한 가정의 이상적인 자녀 수 평균은?",
            blocks: blocks
        )

        XCTAssertEqual(audited.review.verdict, .supported)
        XCTAssertTrue(audited.reasons.isEmpty)
    }

    func testSemanticAuditDoesNotMergeDifferentExplicitUnits() {
        let blocks = [
            block("percent", "고령자 비율은 20.3%다."),
            block("people", "고령자 표본은 20.3명이다."),
        ]
        let raw = semanticReview(
            findings: [
                .init(
                    blockID: "percent",
                    support: .completeAnswer,
                    answerValues: ["20.3%"],
                    quote: blocks[0].text
                ),
                .init(
                    blockID: "people",
                    support: .completeAnswer,
                    answerValues: ["20.3명"],
                    quote: blocks[1].text
                ),
            ]
        )

        let audited = WordAIGroundingSemanticAudit.evaluate(
            raw,
            question: "고령자 수치는?",
            blocks: blocks
        )

        XCTAssertEqual(audited.review.verdict, .contradicted)
        XCTAssertEqual(
            audited.reasons,
            ["semanticReviewNumericAnswerConflict"]
        )
    }

    func testSemanticAuditAcceptsPresentationOnlyCitationDifferences() {
        let source = block(
            "source",
            "영향예보는 4단계(관심, 주의, 경고, 위험)로 구성되어 있다."
        )
        let raw = semanticReview(
            findings: [
                .init(
                    blockID: source.id,
                    support: .completeAnswer,
                    answerValues: ["4단계"],
                    quote: "영향예보는 4단계(관심●, 주의●, 경고●, 위험●)로 구성되어 있다."
                )
            ]
        )

        let audited = WordAIGroundingSemanticAudit.evaluate(
            raw,
            question: "영향예보는 몇 단계로 구성돼?",
            blocks: [source]
        )

        XCTAssertEqual(audited.review.verdict, .supported)
        XCTAssertTrue(audited.reasons.isEmpty)
    }

    func testSemanticAuditUsesGroundedValueWhenCandidateQuoteHasTypo() {
        let source = block(
            "source",
            "기상특보와 달리 영향예보는 4단계(관심, 주의, 경고, 위험)로 구성되어 있다."
        )
        let raw = semanticReview(
            findings: [
                .init(
                    blockID: source.id,
                    support: .completeAnswer,
                    answerValues: ["4단계"],
                    quote: "기상특보와 달리 영향예보는 4단계(관심, 주의, 경보, 위험)로 구성되어 있다."
                )
            ]
        )

        let audited = WordAIGroundingSemanticAudit.evaluate(
            raw,
            question: "영향예보는 몇 단계로 구성돼?",
            blocks: [source]
        )

        XCTAssertEqual(audited.review.verdict, .supported)
        XCTAssertTrue(audited.reasons.isEmpty)
    }

    func testSemanticAuditGroundsLabelAcrossParentheticalExpansion() {
        let source = block(
            "source",
            "자체개발 (Self-developed LLM)은 모델을 처음부터 직접 사전학습하는 방식이다."
        )
        let raw = semanticReview(
            findings: [
                .init(
                    blockID: source.id,
                    support: .completeAnswer,
                    answerValues: ["자체개발 LLM"],
                    quote: source.text
                )
            ]
        )

        let audited = WordAIGroundingSemanticAudit.evaluate(
            raw,
            question: "자체 개발 방식의 이름은?",
            blocks: [source]
        )

        XCTAssertEqual(audited.review.verdict, .supported)
        XCTAssertTrue(audited.reasons.isEmpty)
    }

    func testSemanticAuditComparesFullSlotPartialAnswersForConflict() {
        let blocks = [
            block("summary", "폭염일수 30.1일, 열대야일수 24.5일"),
            block("intro", "폭염일수 31.1일, 열대야일수 24.4일"),
        ]
        let raw = semanticReview(
            findings: [
                .init(
                    blockID: "summary",
                    support: .completeAnswer,
                    answerValues: ["30.1일", "24.5일"],
                    quote: blocks[0].text
                ),
                .init(
                    blockID: "intro",
                    support: .partialAnswer,
                    answerValues: ["31.1일", "24.4일"],
                    quote: blocks[1].text
                ),
            ]
        )

        let audited = WordAIGroundingSemanticAudit.evaluate(
            raw,
            question: "폭염일수와 열대야일수는 정확히 며칠이야?",
            blocks: blocks
        )

        XCTAssertEqual(audited.review.verdict, .contradicted)
        XCTAssertTrue(audited.review.userMessage.contains("30.1일, 24.5일"))
        XCTAssertTrue(audited.review.userMessage.contains("31.1일, 24.4일"))
    }

    func testIndependentReviewCanRecoverCitationFormattingOnlyFailure() {
        let source = block(
            "source",
            "서비스형 LLM, 기성 LLM 활용, 자체개발 방식으로 구분한다."
        )
        let response = WordAIGroundingResponse(
            intent: .answer,
            assistantMessage: "대표 방식은 서비스형 LLM, 기성 LLM 활용, 자체개발입니다.",
            claims: [
                .init(
                    text: "세 방식을 구분한다.",
                    kind: .extractiveFact,
                    evidence: [
                        .init(
                            blockID: source.id,
                            quote: "서비스형과 기성형 그리고 자체개발"
                        )
                    ]
                )
            ]
        )
        let context = WordAIGroundingContext(
            question: "대표적인 방식은?",
            blocks: [source],
            requiresClarification: false,
            eligibleEvidenceBlockIDs: [source.id]
        )
        let guardrail = WordAIEvidenceGuardrail.validate(
            response,
            context: context
        )
        let review = semanticReview(
            findings: [
                .init(
                    blockID: source.id,
                    support: .completeAnswer,
                    answerValues: [
                        "서비스형 LLM", "기성 LLM 활용", "자체개발",
                    ],
                    quote: source.text
                )
            ]
        )

        let decision = WordAIGroundingDecision.make(
            response: response,
            guardrail: guardrail,
            review: review
        )

        XCTAssertTrue(
            WordAIEvidenceGuardrail.isCitationFormattingFailure(guardrail)
        )
        XCTAssertEqual(decision.state, .verified)
        XCTAssertEqual(
            decision.reasons,
            ["citationFormattingRecoveredBySemanticReview"]
        )
    }

    func testEvaluativeQuestionRequiresExplicitDocumentConclusion() {
        let source = block(
            "source",
            "부안 지진 발생 시 11초 만에 학교에 지진정보가 전파되었다."
        )
        let raw = WordAIGroundingSemanticReview(
            verdict: .supported,
            questionType: .evaluativeOrInferential,
            reviewedBlockIDs: [source.id],
            candidateFindings: [
                .init(
                    blockID: source.id,
                    support: .partialAnswer,
                    answerValues: ["11초"],
                    quote: source.text
                )
            ],
            explicitConclusionBlockID: "",
            explicitConclusionQuote: "",
            userMessage: "",
            explanation: "신속 전파 사례가 있음"
        )

        let audited = WordAIGroundingSemanticAudit.evaluate(
            raw,
            question: "재난 대응은 성공적이었다고 평가할 수 있어?",
            blocks: [source]
        )

        XCTAssertEqual(audited.review.verdict, .insufficient)
        XCTAssertEqual(
            audited.reasons,
            ["explicitEvaluationConclusionMissing"]
        )
    }

    func testEvaluativeConclusionNeedsIndependentCandidateAgreement() {
        let source = block(
            "source",
            "부안 지진 발생 시 11초 만에 학교에 지진정보가 전파되었다."
        )
        let raw = WordAIGroundingSemanticReview(
            verdict: .supported,
            questionType: .evaluativeOrInferential,
            reviewedBlockIDs: [source.id],
            candidateFindings: [
                .init(
                    blockID: source.id,
                    support: .noAnswer,
                    answerValues: [],
                    quote: ""
                )
            ],
            explicitConclusionBlockID: source.id,
            explicitConclusionQuote: source.text,
            userMessage: "",
            explanation: "최종 검토만 사례를 성공 결론으로 해석함"
        )

        let audited = WordAIGroundingSemanticAudit.evaluate(
            raw,
            question: "재난 대응은 성공적이었다고 평가할 수 있어?",
            blocks: [source]
        )

        XCTAssertEqual(audited.review.verdict, .insufficient)
        XCTAssertEqual(
            audited.reasons,
            ["explicitEvaluationConclusionMissing"]
        )
    }

    func testEvaluativeQuestionAllowsExactDocumentConclusion() {
        let source = block(
            "source",
            "외부 평가 결과 2024년 재난 대응은 성공적이었다."
        )
        let raw = WordAIGroundingSemanticReview(
            verdict: .supported,
            questionType: .evaluativeOrInferential,
            reviewedBlockIDs: [source.id],
            candidateFindings: [
                .init(
                    blockID: source.id,
                    support: .completeAnswer,
                    answerValues: ["성공적이었다"],
                    quote: source.text
                )
            ],
            explicitConclusionBlockID: source.id,
            explicitConclusionQuote: source.text,
            userMessage: "",
            explanation: "문서가 평가 결론을 직접 명시함"
        )

        let audited = WordAIGroundingSemanticAudit.evaluate(
            raw,
            question: "재난 대응은 성공적이었다고 평가할 수 있어?",
            blocks: [source]
        )

        XCTAssertEqual(audited.review.verdict, .supported)
        XCTAssertTrue(audited.reasons.isEmpty)
    }

    private var supportedReview: WordAIGroundingSemanticReview {
        WordAIGroundingSemanticReview(
            verdict: .supported,
            questionType: .factual,
            reviewedBlockIDs: ["source"],
            candidateFindings: [
                .init(
                    blockID: "source",
                    support: .completeAnswer,
                    answerValues: ["63.5퍼센트"],
                    quote: "전반적인 가족 관계 만족도는 63.5퍼센트다."
                )
            ],
            explicitConclusionBlockID: "",
            explicitConclusionQuote: "",
            userMessage: "",
            explanation: "인용문이 답을 직접 뒷받침함"
        )
    }

    private func semanticReview(
        findings: [WordAIGroundingSemanticReview.CandidateFinding]
    ) -> WordAIGroundingSemanticReview {
        WordAIGroundingSemanticReview(
            verdict: .supported,
            questionType: .factual,
            reviewedBlockIDs: findings.map(\.blockID),
            candidateFindings: findings,
            explicitConclusionBlockID: "",
            explicitConclusionQuote: "",
            userMessage: "",
            explanation: "초기 검토는 통과"
        )
    }

    private func validate(
        _ response: WordAIGroundingResponse,
        source: String
    ) -> WordAIEvidenceGuardrailResult {
        let evidence = block("source", source)
        let context = WordAIGroundingContext(
            question: "질문",
            blocks: [evidence],
            requiresClarification: false,
            eligibleEvidenceBlockIDs: [evidence.id]
        )
        return WordAIEvidenceGuardrail.validate(response, context: context)
    }

    private func answer(
        message: String,
        claim: String,
        source: String
    ) -> WordAIGroundingResponse {
        WordAIGroundingResponse(
            intent: .answer,
            assistantMessage: message,
            claims: [
                .init(
                    text: claim,
                    kind: .extractiveFact,
                    evidence: [.init(blockID: "source", quote: source)]
                )
            ]
        )
    }

    private func block(
        _ id: String,
        _ text: String
    ) -> WordAIGroundingBlock {
        WordAIGroundingBlock(id: id, sectionID: id, text: text)
    }
}
