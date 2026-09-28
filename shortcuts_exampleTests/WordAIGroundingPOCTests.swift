import XCTest

@testable import shortcuts_example

final class WordAIGroundingPOCTests: XCTestCase {
    func testAcceptsExactRelevantFactAndIgnoresFreeformMessage() {
        let context = makeContext(
            question: "2026년 국내총생산 성장률은?",
            blocks: [
                block(
                    "gdp",
                    "2026년 실질 국내총생산 성장률은 2.0퍼센트로 전망한다."
                )
            ]
        )
        let response = answer(
            assistantMessage: "근거에는 없지만 3.5%라고 생각합니다.",
            claim: "2026년 실질 국내총생산 성장률은 2.0퍼센트로 전망한다.",
            blockID: "gdp",
            quote: "2026년 실질 국내총생산 성장률은 2.0퍼센트로 전망한다."
        )

        let result = WordAIGroundingValidator.validate(response, context: context)

        XCTAssertEqual(result.state, .verified)
        XCTAssertEqual(
            result.displayText,
            "2026년 실질 국내총생산 성장률은 2.0퍼센트로 전망한다."
        )
        XCTAssertFalse(result.displayText?.contains("3.5") == true)
    }

    func testRejectsFabricatedNumber() {
        let context = makeContext(
            question: "2026년 성장률은?",
            blocks: [block("gdp", "2026년 성장률은 2.0퍼센트다.")]
        )
        let response = answer(
            claim: "2026년 성장률은 3.0퍼센트다.",
            blockID: "gdp",
            quote: "2026년 성장률은 2.0퍼센트다."
        )

        let result = WordAIGroundingValidator.validate(response, context: context)

        XCTAssertEqual(result.state, .rejected)
        XCTAssertEqual(result.reasons, ["protectedValueNotInEvidence"])
    }

    func testRejectsFabricatedQuote() {
        let context = makeContext(
            question: "인터넷 이용률은?",
            blocks: [block("internet", "인터넷 이용률은 76.9퍼센트다.")]
        )
        let response = answer(
            claim: "인터넷 이용률은 92.6퍼센트다.",
            blockID: "internet",
            quote: "인터넷 이용률은 92.6퍼센트다."
        )

        let result = WordAIGroundingValidator.validate(response, context: context)

        XCTAssertEqual(result.state, .rejected)
        XCTAssertEqual(result.reasons, ["quoteNotFoundInBlock"])
    }

    func testRejectsUnknownBlockID() {
        let context = makeContext(
            question: "경상수지는?",
            blocks: [block("account", "경상수지는 1,700억 달러 흑자다.")]
        )
        let response = answer(
            claim: "경상수지는 1,700억 달러 흑자다.",
            blockID: "invented",
            quote: "경상수지는 1,700억 달러 흑자다."
        )

        let result = WordAIGroundingValidator.validate(response, context: context)

        XCTAssertEqual(result.state, .rejected)
        XCTAssertEqual(result.reasons, ["unknownBlockID"])
    }

    func testRejectsParaphraseEvenWhenMeaningIsCorrect() {
        let context = makeContext(
            question: "해고 예고 기간은?",
            blocks: [
                block("notice", "사용자는 근로자를 해고하려면 적어도 30일 전에 예고하여야 한다.")
            ]
        )
        let response = answer(
            claim: "해고는 한 달 전에 알려야 한다.",
            blockID: "notice",
            quote: "사용자는 근로자를 해고하려면 적어도 30일 전에 예고하여야 한다."
        )

        let result = WordAIGroundingValidator.validate(response, context: context)

        XCTAssertEqual(result.state, .rejected)
        XCTAssertTrue(result.reasons.contains("claimIsNotExactEvidence"))
    }

    func testRejectsOppositePolarity() {
        let context = makeContext(
            question: "매출은 어떻게 변했어?",
            blocks: [block("sales", "2026년 매출은 전년보다 3퍼센트 감소했다.")]
        )
        let response = answer(
            claim: "2026년 매출은 전년보다 3퍼센트 증가했다.",
            blockID: "sales",
            quote: "2026년 매출은 전년보다 3퍼센트 감소했다."
        )

        let result = WordAIGroundingValidator.validate(response, context: context)

        XCTAssertEqual(result.state, .rejected)
        XCTAssertEqual(result.reasons, ["polarityMismatch"])
    }

    func testRejectsTrueButIrrelevantQuote() {
        let context = makeContext(
            question: "성장률은?",
            blocks: [
                block("gdp", "2026년 성장률은 2.0퍼센트다."),
                block("weather", "오늘 서울의 기온은 20도다."),
            ]
        )
        let response = answer(
            claim: "오늘 서울의 기온은 20도다.",
            blockID: "weather",
            quote: "오늘 서울의 기온은 20도다."
        )

        let result = WordAIGroundingValidator.validate(response, context: context)

        XCTAssertEqual(result.state, .rejected)
        XCTAssertEqual(result.reasons, ["evidenceNotRelevantToQuestion"])
    }

    func testRejectsAnswerForDifferentRequestedYear() {
        let context = makeContext(
            question: "2027년 국내총생산 성장률은?",
            blocks: [block("gdp", "2026년 국내총생산 성장률은 2.0퍼센트다.")]
        )
        let response = answer(
            claim: "2026년 국내총생산 성장률은 2.0퍼센트다.",
            blockID: "gdp",
            quote: "2026년 국내총생산 성장률은 2.0퍼센트다."
        )

        let result = WordAIGroundingValidator.validate(response, context: context)

        XCTAssertEqual(result.state, .rejected)
        XCTAssertEqual(result.reasons, ["questionValueNotInEvidence"])
    }

    func testInterpretationCanNeverBecomeVerified() {
        let context = makeContext(
            question: "경제 전망이 긍정적이야?",
            blocks: [
                block(
                    "risk",
                    "경제 전망에서 성장률은 2.0퍼센트지만 하방 위험이 확대되었다."
                )
            ]
        )
        let response = WordAIGroundingResponse(
            intent: .answer,
            assistantMessage: "긍정적입니다.",
            claims: [
                .init(
                    text: "경제 전망은 긍정적이다.",
                    kind: .interpretation,
                    evidence: [
                        .init(
                            blockID: "risk",
                            quote: "경제 전망에서 성장률은 2.0퍼센트지만 하방 위험이 확대되었다."
                        )
                    ]
                )
            ]
        )

        let result = WordAIGroundingValidator.validate(response, context: context)

        XCTAssertEqual(result.state, .reviewRequired)
        XCTAssertTrue(result.displayText?.contains("AI 해석") == true)
    }

    func testLocalAmbiguityOverridesModelAnswer() {
        let blocks = [
            WordAIGroundingBlock(
                id: "gdp",
                sectionID: "growth",
                text: "2026년 국내총생산 성장률은 2.0퍼센트다."
            ),
            WordAIGroundingBlock(
                id: "cpi",
                sectionID: "prices",
                text: "2026년 소비자물가 상승률은 2.0퍼센트다."
            ),
        ]
        let ambiguity = WordAIGroundingAmbiguityDetector.analyze(
            question: "2026년 2.0퍼센트 전망치는 무엇을 뜻해?",
            blocks: blocks
        )
        XCTAssertTrue(ambiguity.requiresClarification)
        let context = WordAIGroundingContext(
            question: "2026년 2.0퍼센트 전망치는 무엇을 뜻해?",
            blocks: blocks,
            requiresClarification: ambiguity.requiresClarification,
            topCandidateBlockIDs: ambiguity.candidateBlockIDs
        )
        let response = answer(
            claim: "2026년 국내총생산 성장률은 2.0퍼센트다.",
            blockID: "gdp",
            quote: "2026년 국내총생산 성장률은 2.0퍼센트다."
        )

        let result = WordAIGroundingValidator.validate(response, context: context)

        XCTAssertEqual(result.state, .clarify)
        XCTAssertEqual(result.reasons, ["localAmbiguityDetected"])
        XCTAssertEqual(result.candidateBlockIDs, ["gdp", "cpi"])
        XCTAssertTrue(result.displayText?.contains("국내총생산 성장률") == true)
        XCTAssertTrue(result.displayText?.contains("소비자물가 상승률") == true)
    }

    func testValidClarificationPasses() {
        let context = WordAIGroundingContext(
            question: "고령자 비율은?",
            blocks: [],
            requiresClarification: true
        )
        let response = WordAIGroundingResponse(
            intent: .clarify,
            assistantMessage: "인구 비중과 고용률 중 어느 비율을 말씀하시나요?",
            claims: []
        )

        let result = WordAIGroundingValidator.validate(response, context: context)

        XCTAssertEqual(result.state, .clarify)
    }

    func testClarificationWithHiddenClaimIsRejected() {
        let context = WordAIGroundingContext(
            question: "고령자 비율은?",
            blocks: [block("population", "고령인구 비중은 20.3퍼센트다.")],
            requiresClarification: true
        )
        let response = WordAIGroundingResponse(
            intent: .clarify,
            assistantMessage: "어느 비율인가요?",
            claims: [
                .init(
                    text: "고령인구 비중은 20.3퍼센트다.",
                    kind: .extractiveFact,
                    evidence: [
                        .init(
                            blockID: "population",
                            quote: "고령인구 비중은 20.3퍼센트다."
                        )
                    ]
                )
            ]
        )

        let result = WordAIGroundingValidator.validate(response, context: context)

        XCTAssertEqual(result.state, .rejected)
        XCTAssertEqual(result.reasons, ["clarifyContainsClaims"])
    }

    func testDisplaysCompleteSourceSentenceWhenClaimDropsTrailingNegation() {
        let context = makeContext(
            question: "2026년 국내총생산 성장률은 2.0퍼센트야?",
            blocks: [
                block(
                    "gdp-correction",
                    "2026년 국내총생산 성장률은 2.0퍼센트가 아니다."
                )
            ]
        )
        let response = answer(
            claim: "2026년 국내총생산 성장률은 2.0퍼센트",
            blockID: "gdp-correction",
            quote: "2026년 국내총생산 성장률은 2.0퍼센트가 아니다."
        )

        let result = WordAIGroundingValidator.validate(response, context: context)

        XCTAssertEqual(result.state, .verified)
        XCTAssertEqual(
            result.displayText,
            "2026년 국내총생산 성장률은 2.0퍼센트가 아니다."
        )
    }

    func testClarificationReplacesUngroundedModelFactWithLocalMessage() {
        let context = WordAIGroundingContext(
            question: "2027년 국내총생산 성장률은?",
            blocks: [block("gdp", "2026년 국내총생산 성장률은 2.0퍼센트다.")],
            requiresClarification: false
        )
        let response = WordAIGroundingResponse(
            intent: .clarify,
            assistantMessage: "2027년 자료는 없습니다. 대신 2026년 성장률은 9.9퍼센트입니다.",
            claims: []
        )

        let result = WordAIGroundingValidator.validate(response, context: context)

        XCTAssertEqual(result.state, .clarify)
        XCTAssertEqual(
            result.displayText,
            WordAIGroundingValidator.safeClarificationMessage
        )
        XCTAssertFalse(result.displayText?.contains("9.9") == true)
    }

    func testDisplaysConditionFromCompleteSourceSentence() {
        let source = "전제 조건을 확인한다. 정부 지원이 계속되는 경우에만 2026년 성장률은 2.0퍼센트다. 다음 항목이다."
        let context = makeContext(
            question: "2026년 성장률은 2.0퍼센트야?",
            blocks: [block("conditional-gdp", source)]
        )
        let response = answer(
            claim: "2026년 성장률은 2.0퍼센트",
            blockID: "conditional-gdp",
            quote: "2026년 성장률은 2.0퍼센트"
        )

        let result = WordAIGroundingValidator.validate(response, context: context)

        XCTAssertEqual(result.state, .verified)
        XCTAssertEqual(
            result.displayText,
            "정부 지원이 계속되는 경우에만 2026년 성장률은 2.0퍼센트다."
        )
    }

    /// Known residual: a complete sentence can still depend on a qualifier in
    /// the immediately preceding sentence. The current POC records this loss
    /// of context rather than silently expanding the display window.
    func testKnownResidualCanLoseQualifierInPreviousSentence() {
        let source = "낙관 시나리오에서만 다음 수치를 적용한다. 2026년 성장률은 2.0퍼센트다."
        let context = makeContext(
            question: "2026년 성장률은?",
            blocks: [block("scenario", source)]
        )
        let response = answer(
            claim: "2026년 성장률은 2.0퍼센트다.",
            blockID: "scenario",
            quote: "2026년 성장률은 2.0퍼센트다."
        )

        let result = WordAIGroundingValidator.validate(response, context: context)

        XCTAssertEqual(result.state, .verified)
        XCTAssertEqual(result.displayText, "2026년 성장률은 2.0퍼센트다.")
        XCTAssertFalse(result.displayText?.contains("낙관 시나리오") == true)
    }

    /// Known residual: lexical relevance is not semantic target validation.
    /// Even when local search has a unique best block, another block can clear
    /// the 50% threshold and answer the wrong scenario.
    func testKnownResidualCanVerifyWrongScenario() {
        let blocks = [
            WordAIGroundingBlock(
                id: "baseline",
                sectionID: "baseline",
                text: "2026년 실질 국내총생산 성장률의 기본 전망은 2.0퍼센트다."
            ),
            WordAIGroundingBlock(
                id: "downside",
                sectionID: "downside",
                text: "2026년 성장률 비관 전망은 1.7퍼센트다."
            ),
        ]
        let question = "2026년 실질 국내총생산 성장률의 기본 전망은?"
        let ambiguity = WordAIGroundingAmbiguityDetector.analyze(
            question: question,
            blocks: blocks
        )
        XCTAssertFalse(ambiguity.requiresClarification)
        XCTAssertEqual(ambiguity.candidateBlockIDs, ["baseline"])

        let context = WordAIGroundingContext(
            question: question,
            blocks: blocks,
            requiresClarification: ambiguity.requiresClarification
        )
        let response = answer(
            claim: "2026년 성장률 비관 전망은 1.7퍼센트다.",
            blockID: "downside",
            quote: "2026년 성장률 비관 전망은 1.7퍼센트다."
        )

        let result = WordAIGroundingValidator.validate(response, context: context)

        XCTAssertEqual(result.state, .verified)
        XCTAssertEqual(result.displayText, "2026년 성장률 비관 전망은 1.7퍼센트다.")
    }

    private func makeContext(
        question: String,
        blocks: [WordAIGroundingBlock]
    ) -> WordAIGroundingContext {
        WordAIGroundingContext(
            question: question,
            blocks: blocks,
            requiresClarification: false
        )
    }

    private func block(_ id: String, _ text: String) -> WordAIGroundingBlock {
        WordAIGroundingBlock(id: id, sectionID: id, text: text)
    }

    private func answer(
        assistantMessage: String = "문서에서 확인했습니다.",
        claim: String,
        blockID: String,
        quote: String
    ) -> WordAIGroundingResponse {
        WordAIGroundingResponse(
            intent: .answer,
            assistantMessage: assistantMessage,
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
