import XCTest

@testable import shortcuts_example

final class WordAIGroundingPolicyPOCTests: XCTestCase {
    func testAmbiguousRatioReturnsGroundedCandidateChoices() {
        let blocks = [
            block(
                "population-ratio",
                "2025년 65세 이상 고령자 인구 비율은 전체 인구의 20.3퍼센트이다."
            ),
            block(
                "employment-ratio",
                "2025년 고령자 고용 비율은 38.2퍼센트이다."
            ),
        ]
        let question = "고령자 비율은 얼마야?"
        let ambiguity = WordAIGroundingAmbiguityDetector.analyze(
            question: question,
            blocks: blocks
        )
        let context = WordAIGroundingContext(
            question: question,
            blocks: blocks,
            requiresClarification: ambiguity.requiresClarification,
            topCandidateBlockIDs: ambiguity.candidateBlockIDs
        )
        let response = WordAIGroundingResponse(
            intent: .answer,
            assistantMessage: "고령자 비율은 99퍼센트입니다.",
            claims: [
                .init(
                    text: blocks[0].text,
                    kind: .extractiveFact,
                    evidence: [
                        .init(blockID: blocks[0].id, quote: blocks[0].text)
                    ]
                )
            ]
        )

        let result = WordAIGroundingValidator.validate(
            response,
            context: context,
            policy: .surroundingTopCandidates
        )

        XCTAssertEqual(result.state, .clarify)
        XCTAssertEqual(result.reasons, ["localAmbiguityDetected"])
        XCTAssertEqual(
            result.candidateBlockIDs,
            ["population-ratio", "employment-ratio"]
        )
        XCTAssertTrue(result.displayText?.contains("20.3퍼센트") == true)
        XCTAssertTrue(result.displayText?.contains("38.2퍼센트") == true)
        XCTAssertFalse(result.displayText?.contains("99퍼센트") == true)
    }

    func testThreeSentencePolicyPreservesPreviousQualifier() {
        let source = "낙관 시나리오에서만 다음 수치를 적용한다. 2026년 성장률은 2.0퍼센트다."
        let context = context(
            question: "2026년 성장률은?",
            blocks: [block("scenario", source)],
            topCandidates: ["scenario"]
        )
        let response = answer(
            text: "2026년 성장률은 2.0퍼센트다.",
            blockID: "scenario"
        )

        let baseline = WordAIGroundingValidator.validate(
            response,
            context: context,
            policy: .singleSentence
        )
        let candidate = WordAIGroundingValidator.validate(
            response,
            context: context,
            policy: .surroundingTopCandidates
        )

        XCTAssertEqual(baseline.displayText, "2026년 성장률은 2.0퍼센트다.")
        XCTAssertEqual(candidate.state, .verified)
        XCTAssertEqual(candidate.displayText, source)
    }

    func testTopCandidateGateRejectsWrongScenario() {
        let blocks = scenarioBlocks
        let question = "2026년 실질 국내총생산 성장률의 기본 전망은?"
        let ambiguity = WordAIGroundingAmbiguityDetector.analyze(
            question: question,
            blocks: blocks
        )
        XCTAssertEqual(ambiguity.candidateBlockIDs, ["baseline"])
        let context = WordAIGroundingContext(
            question: question,
            blocks: blocks,
            requiresClarification: ambiguity.requiresClarification,
            topCandidateBlockIDs: ambiguity.candidateBlockIDs
        )
        let response = answer(
            text: "2026년 성장률 비관 전망은 1.7퍼센트다.",
            blockID: "downside"
        )

        let baseline = WordAIGroundingValidator.validate(
            response,
            context: context,
            policy: .singleSentence
        )
        let candidate = WordAIGroundingValidator.validate(
            response,
            context: context,
            policy: .surroundingTopCandidates
        )

        XCTAssertEqual(baseline.state, .verified)
        XCTAssertEqual(candidate.state, .rejected)
        XCTAssertEqual(candidate.reasons, ["evidenceOutsideTopCandidates"])
    }

    func testTopCandidateGateAcceptsCorrectScenario() {
        let blocks = scenarioBlocks
        let question = "2026년 실질 국내총생산 성장률의 기본 전망은?"
        let context = context(
            question: question,
            blocks: blocks,
            topCandidates: ["baseline"]
        )
        let response = answer(
            text: "2026년 실질 국내총생산 성장률의 기본 전망은 2.0퍼센트다.",
            blockID: "baseline"
        )

        let result = WordAIGroundingValidator.validate(
            response,
            context: context,
            policy: .surroundingTopCandidates
        )

        XCTAssertEqual(result.state, .verified)
        XCTAssertEqual(
            result.displayText,
            "2026년 실질 국내총생산 성장률의 기본 전망은 2.0퍼센트다."
        )
    }

    /// Known tradeoff: the lexical top candidate can be a pointer sentence,
    /// while the semantically correct answer uses a synonym in another block.
    /// The strict gate turns this safe answer into a false rejection.
    func testTopCandidateGateFalseRejectsCorrectSynonymAnswer() {
        let blocks = [
            block(
                "pointer",
                "2026년 기본 매출 전망은 별도 부록에서 다룬다."
            ),
            block(
                "actual",
                "2026년 기준 시나리오의 매출은 100억원이다."
            ),
        ]
        let question = "2026년 기본 매출 전망은?"
        let ambiguity = WordAIGroundingAmbiguityDetector.analyze(
            question: question,
            blocks: blocks
        )
        XCTAssertEqual(ambiguity.candidateBlockIDs, ["pointer"])
        let context = WordAIGroundingContext(
            question: question,
            blocks: blocks,
            requiresClarification: ambiguity.requiresClarification,
            topCandidateBlockIDs: ambiguity.candidateBlockIDs
        )
        let response = answer(
            text: "2026년 기준 시나리오의 매출은 100억원이다.",
            blockID: "actual"
        )

        let baseline = WordAIGroundingValidator.validate(
            response,
            context: context,
            policy: .singleSentence
        )
        let candidate = WordAIGroundingValidator.validate(
            response,
            context: context,
            policy: .surroundingTopCandidates
        )

        XCTAssertEqual(baseline.state, .verified)
        XCTAssertEqual(candidate.state, .rejected)
        XCTAssertEqual(candidate.reasons, ["evidenceOutsideTopCandidates"])
    }

    func testStrictPolicyFailsClosedWithoutTopCandidate() {
        let evidence = block("answer", "계약 기간은 2년이다.")
        let context = WordAIGroundingContext(
            question: "계약 기간은?",
            blocks: [evidence],
            requiresClarification: false,
            topCandidateBlockIDs: []
        )
        let response = answer(text: evidence.text, blockID: evidence.id)

        let result = WordAIGroundingValidator.validate(
            response,
            context: context,
            policy: .surroundingTopCandidates
        )

        XCTAssertEqual(result.state, .rejected)
        XCTAssertEqual(result.reasons, ["topCandidateNotFound"])
    }

    func testThreeSentencePolicyDoesNotExpandBeyondOneNeighbor() {
        let source = "첫 문장이다. 둘째 문장이다. 2026년 성장률은 2.0퍼센트다. 넷째 문장이다. 다섯째 문장이다."
        let context = context(
            question: "2026년 성장률은?",
            blocks: [block("middle", source)],
            topCandidates: ["middle"]
        )
        let response = answer(
            text: "2026년 성장률은 2.0퍼센트다.",
            blockID: "middle"
        )

        let result = WordAIGroundingValidator.validate(
            response,
            context: context,
            policy: .surroundingTopCandidates
        )

        XCTAssertEqual(result.state, .verified)
        XCTAssertEqual(
            result.displayText,
            "둘째 문장이다. 2026년 성장률은 2.0퍼센트다. 넷째 문장이다."
        )
        XCTAssertFalse(result.displayText?.contains("첫 문장") == true)
        XCTAssertFalse(result.displayText?.contains("다섯째 문장") == true)
    }

    private var scenarioBlocks: [WordAIGroundingBlock] {
        [
            block(
                "baseline",
                "2026년 실질 국내총생산 성장률의 기본 전망은 2.0퍼센트다."
            ),
            block(
                "downside",
                "2026년 성장률 비관 전망은 1.7퍼센트다."
            ),
        ]
    }

    private func context(
        question: String,
        blocks: [WordAIGroundingBlock],
        topCandidates: [String]
    ) -> WordAIGroundingContext {
        WordAIGroundingContext(
            question: question,
            blocks: blocks,
            requiresClarification: false,
            topCandidateBlockIDs: topCandidates
        )
    }

    private func block(_ id: String, _ text: String) -> WordAIGroundingBlock {
        WordAIGroundingBlock(id: id, sectionID: id, text: text)
    }

    private func answer(
        text: String,
        blockID: String
    ) -> WordAIGroundingResponse {
        WordAIGroundingResponse(
            intent: .answer,
            assistantMessage: "문서에서 확인했습니다.",
            claims: [
                .init(
                    text: text,
                    kind: .extractiveFact,
                    evidence: [.init(blockID: blockID, quote: text)]
                )
            ]
        )
    }
}
