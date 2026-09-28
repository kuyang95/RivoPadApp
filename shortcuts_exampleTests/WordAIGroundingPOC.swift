import Foundation

/// POC-only response contract for answers that must carry exact document
/// evidence. This is intentionally kept in the test target until the policy is
/// proven; production Word chat does not use it yet.
nonisolated struct WordAIGroundingResponse: Codable, Sendable {
    enum Intent: String, Codable, Sendable {
        case answer
        case clarify
    }

    struct Evidence: Codable, Hashable, Sendable {
        let blockID: String
        let quote: String
    }

    struct Claim: Codable, Hashable, Sendable {
        enum Kind: String, Codable, Sendable {
            case extractiveFact
            case interpretation
        }

        let text: String
        let kind: Kind
        let evidence: [Evidence]
    }

    let intent: Intent
    let assistantMessage: String
    let claims: [Claim]
}

nonisolated struct WordAIGroundingBlock: Codable, Hashable, Sendable {
    let id: String
    let sectionID: String
    let text: String
    /// Trusted structural context produced by the local parser, never by the
    /// model. Only temporal question tokens may be inherited from this field.
    let scopeText: String

    init(
        id: String,
        sectionID: String,
        text: String,
        scopeText: String = ""
    ) {
        self.id = id
        self.sectionID = sectionID
        self.text = text
        self.scopeText = scopeText
    }
}

nonisolated struct WordAIGroundingContext: Sendable {
    let question: String
    let blocks: [WordAIGroundingBlock]
    let requiresClarification: Bool
    let topCandidateBlockIDs: [String]
    /// Locally retrieved blocks that may be cited after independent quote,
    /// value, scope, and relevance checks. Search rank alone is not truth.
    let eligibleEvidenceBlockIDs: [String]

    init(
        question: String,
        blocks: [WordAIGroundingBlock],
        requiresClarification: Bool,
        topCandidateBlockIDs: [String] = [],
        eligibleEvidenceBlockIDs: [String] = []
    ) {
        self.question = question
        self.blocks = blocks
        self.requiresClarification = requiresClarification
        self.topCandidateBlockIDs = topCandidateBlockIDs
        self.eligibleEvidenceBlockIDs = eligibleEvidenceBlockIDs
    }
}

nonisolated struct WordAIGroundingValidationPolicy: Equatable, Sendable {
    let contextSentenceRadius: Int
    let requiresTopCandidateEvidence: Bool
    let requiresEligibleEvidence: Bool
    let reconstructsFactsFromSource: Bool
    let allowsTemporalScopeInheritance: Bool
    let resolvesEquivalentAmbiguity: Bool
    let minimumQuestionCoverage: Double
    let minimumClaimCoverage: Double

    /// The second POC behavior: display only the sentence containing quote and
    /// accept any evidence that clears the relevance threshold.
    static let singleSentence = WordAIGroundingValidationPolicy(
        contextSentenceRadius: 0,
        requiresTopCandidateEvidence: false,
        requiresEligibleEvidence: false,
        reconstructsFactsFromSource: false,
        allowsTemporalScopeInheritance: false,
        resolvesEquivalentAmbiguity: false,
        minimumQuestionCoverage: 0.5,
        minimumClaimCoverage: 0
    )

    /// Third POC candidate: show one sentence on either side and fail closed
    /// unless every evidence block is among the local top-scored candidates.
    static let surroundingTopCandidates = WordAIGroundingValidationPolicy(
        contextSentenceRadius: 1,
        requiresTopCandidateEvidence: true,
        requiresEligibleEvidence: false,
        reconstructsFactsFromSource: false,
        allowsTemporalScopeInheritance: false,
        resolvesEquivalentAmbiguity: false,
        minimumQuestionCoverage: 0.5,
        minimumClaimCoverage: 0
    )

    /// Fourth POC candidate. The model selects exact source evidence, but its
    /// prose is non-authoritative. Any locally retrieved candidate may be used
    /// only after deterministic validation. Equivalent duplicate evidence may
    /// resolve a lexical tie; uncertain or conflicting candidates still ask.
    static let retrievedEvidenceConsensus = WordAIGroundingValidationPolicy(
        contextSentenceRadius: 1,
        requiresTopCandidateEvidence: false,
        requiresEligibleEvidence: true,
        reconstructsFactsFromSource: true,
        allowsTemporalScopeInheritance: true,
        resolvesEquivalentAmbiguity: true,
        minimumQuestionCoverage: 0.6,
        minimumClaimCoverage: 0.25
    )
}

nonisolated struct WordAIGroundingValidation: Equatable, Sendable {
    enum State: String, Sendable {
        case verified
        case clarify
        case reviewRequired
        case rejected
    }

    let state: State
    let displayText: String?
    let reasons: [String]
    let candidateBlockIDs: [String]

    init(
        state: State,
        displayText: String?,
        reasons: [String],
        candidateBlockIDs: [String] = []
    ) {
        self.state = state
        self.displayText = displayText
        self.reasons = reasons
        self.candidateBlockIDs = candidateBlockIDs
    }
}

/// Result of checks the app can prove without interpreting language.
///
/// This deliberately does not decide whether an answer is semantically
/// relevant or whether two passages describe the same fact. Those decisions
/// belong to the independent semantic reviewer. The guardrail only proves
/// that citations exist and that protected values were not invented.
nonisolated struct WordAIEvidenceGuardrailResult: Equatable, Sendable {
    enum State: String, Sendable {
        case passed
        case clarify
        case rejected
    }

    let state: State
    let reasons: [String]
    let citedQuotes: [String]
}

nonisolated struct WordAIGroundingSemanticReview: Codable, Equatable, Sendable {
    enum Verdict: String, Codable, Sendable {
        case supported
        case contradicted
        case insufficient
    }

    enum QuestionType: String, Codable, Sendable {
        case factual
        case evaluativeOrInferential
    }

    struct CandidateFinding: Codable, Equatable, Sendable {
        enum Support: String, Codable, Sendable {
            case completeAnswer
            case partialAnswer
            case noAnswer
        }

        let blockID: String
        let support: Support
        /// Only the values that fill the slots asked by the user. Years,
        /// baselines, comparisons, and ranks must not be included unless the
        /// question asks for them.
        let answerValues: [String]
        /// Exact continuous source text, or an empty string for noAnswer.
        let quote: String
    }

    let verdict: Verdict
    let questionType: QuestionType
    /// The IDs the reviewer reports having inspected. This list must cover
    /// every candidate; detailed findings are required only for blocks that
    /// contain a complete or partial answer.
    let reviewedBlockIDs: [String]
    let candidateFindings: [CandidateFinding]
    /// Required only when an evaluative/inferential question can actually be
    /// answered because the document states that conclusion explicitly.
    let explicitConclusionBlockID: String
    let explicitConclusionQuote: String
    /// User-facing explanation for contradicted or insufficient results.
    /// It is ignored when verdict is supported.
    let userMessage: String
    /// Internal diagnostic retained by the POC report.
    let explanation: String
}

nonisolated struct WordAIGroundingSemanticAuditResult: Equatable, Sendable {
    let review: WordAIGroundingSemanticReview
    let reasons: [String]
}

/// Audits the *shape and source integrity* of the semantic review without
/// pretending to understand prose. The reviewer decides relevance; the app
/// only verifies that every candidate was examined, quotes are real, and
/// independently extracted numeric answers do not disagree.
nonisolated enum WordAIGroundingSemanticAudit {
    static func evaluate(
        _ review: WordAIGroundingSemanticReview,
        question: String,
        blocks: [WordAIGroundingBlock]
    ) -> WordAIGroundingSemanticAuditResult {
        let blocksByID = Dictionary(
            uniqueKeysWithValues: blocks.map { ($0.id, $0) }
        )
        let expectedIDs = Set(blocksByID.keys)
        let reviewedIDs = review.reviewedBlockIDs
        guard reviewedIDs.count == Set(reviewedIDs).count,
              Set(reviewedIDs) == expectedIDs else {
            return insufficient(
                review,
                reason: "semanticReviewCandidateCoverageMismatch",
                message: "검색된 원문 후보를 모두 비교하지 못해 답을 보류했습니다."
            )
        }
        let findingIDs = review.candidateFindings.map(\.blockID)
        guard findingIDs.count == Set(findingIDs).count,
              Set(findingIDs).isSubset(of: expectedIDs) else {
            return insufficient(
                review,
                reason: "semanticReviewFindingCoverageInvalid",
                message: "후보별 답의 위치를 일관되게 확인하지 못했습니다."
            )
        }

        for finding in review.candidateFindings {
            guard let block = blocksByID[finding.blockID] else {
                return insufficient(
                    review,
                    reason: "semanticReviewUnknownBlockID",
                    message: "검토한 원문 위치를 확인하지 못해 답을 보류했습니다."
                )
            }
            switch finding.support {
            case .noAnswer:
                guard finding.answerValues.isEmpty,
                      finding.quote.trimmingCharacters(
                        in: .whitespacesAndNewlines
                      ).isEmpty else {
                    return insufficient(
                        review,
                        reason: "semanticReviewInvalidNoAnswerFinding",
                        message: "원문 후보의 답변 가능 여부를 일관되게 확인하지 못했습니다."
                    )
                }
            case .completeAnswer, .partialAnswer:
                let quote = finding.quote.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard quote.count >= 4, !finding.answerValues.isEmpty else {
                    return insufficient(
                        review,
                        reason: "semanticReviewFindingNotGrounded",
                        message: "후보별 답과 인용문을 원문에서 확인하지 못했습니다."
                    )
                }
                let trustedSource = block.scopeText + " " + block.text
                let quoteMatchesSource =
                    WordAIGroundingText.sourceContainsEquivalentQuote(
                        quote,
                        in: trustedSource
                    )
                let valuesMatchQuote = finding.answerValues.allSatisfy { value in
                    WordAIGroundingText.answerValue(
                        value,
                        isGroundedIn: quote
                    )
                }
                let valuesMatchSource = finding.answerValues.allSatisfy { value in
                    WordAIGroundingText.answerValue(
                        value,
                        isGroundedIn: trustedSource
                    )
                }
                guard (quoteMatchesSource && valuesMatchQuote)
                        || (!quoteMatchesSource && valuesMatchSource) else {
                    return insufficient(
                        review,
                        reason: "semanticReviewAnswerValueNotInQuote",
                        message: "후보별로 추출한 답을 원문에서 확인하지 못해 답을 보류했습니다."
                    )
                }
            }
        }

        let numericAnswers = review.candidateFindings.compactMap {
            finding -> Set<String>? in
            guard finding.support != .noAnswer else { return nil }
            let values = finding.answerValues.reduce(into: Set<String>()) {
                result, value in
                result.formUnion(
                    WordAIGroundingText.protectedTokens(in: value)
                )
            }
            return values.isEmpty ? nil : values
        }
        let maximumAnswerSlotCount = numericAnswers.map(\.count).max() ?? 0
        let completeSlotNumericAnswers = numericAnswers.filter {
            $0.count == maximumAnswerSlotCount
        }
        if let first = completeSlotNumericAnswers.first,
           completeSlotNumericAnswers.dropFirst().contains(where: {
               !WordAIGroundingText.protectedTokenSetsAreEquivalent(
                    first,
                    $0
               )
           }) {
            let alternatives = review.candidateFindings.compactMap { finding in
                let tokens = finding.answerValues.reduce(into: Set<String>()) {
                    result, value in
                    result.formUnion(
                        WordAIGroundingText.protectedTokens(in: value)
                    )
                }
                guard finding.support != .noAnswer,
                      tokens.count == maximumAnswerSlotCount,
                      !finding.answerValues.isEmpty else { return nil }
                return finding.answerValues.joined(separator: ", ")
            }
            .uniqued()
            .joined(separator: " / ")
            return contradicted(
                review,
                reason: "semanticReviewNumericAnswerConflict",
                message: "문서 후보에 같은 질문의 답이 \(alternatives)로 다르게 적혀 있습니다. 사용할 기준이나 위치를 지정해 주세요."
            )
        }

        if WordAIGroundingQuestionRisk.requiresExplicitConclusion(question) {
            let blockID = review.explicitConclusionBlockID.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let quote = review.explicitConclusionQuote.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let conclusionFinding = review.candidateFindings.first { finding in
                guard finding.blockID == blockID,
                      finding.support == .completeAnswer else { return false }
                let findingQuote = finding.quote.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                return WordAIGroundingText.sourceContainsEquivalentQuote(
                    quote,
                    in: findingQuote
                ) || WordAIGroundingText.sourceContainsEquivalentQuote(
                    findingQuote,
                    in: quote
                )
            }
            guard review.questionType == .evaluativeOrInferential,
                  let block = blocksByID[blockID],
                  quote.count >= 4,
                  WordAIGroundingText.sourceContainsEquivalentQuote(
                    quote,
                    in: block.text
                  ),
                  conclusionFinding != nil else {
                return insufficient(
                    review,
                    reason: "explicitEvaluationConclusionMissing",
                    message: "문서에는 관련 사실은 있지만 질문의 평가 결론이나 판단 기준이 명시되어 있지 않습니다. 평가 기준을 알려주세요."
                )
            }
        }

        return WordAIGroundingSemanticAuditResult(
            review: review,
            reasons: []
        )
    }

    private static func insufficient(
        _ review: WordAIGroundingSemanticReview,
        reason: String,
        message: String
    ) -> WordAIGroundingSemanticAuditResult {
        overridden(
            review,
            verdict: .insufficient,
            reason: reason,
            message: message
        )
    }

    private static func contradicted(
        _ review: WordAIGroundingSemanticReview,
        reason: String,
        message: String
    ) -> WordAIGroundingSemanticAuditResult {
        overridden(
            review,
            verdict: .contradicted,
            reason: reason,
            message: message
        )
    }

    private static func overridden(
        _ review: WordAIGroundingSemanticReview,
        verdict: WordAIGroundingSemanticReview.Verdict,
        reason: String,
        message: String
    ) -> WordAIGroundingSemanticAuditResult {
        WordAIGroundingSemanticAuditResult(
            review: WordAIGroundingSemanticReview(
                verdict: verdict,
                questionType: review.questionType,
                reviewedBlockIDs: review.reviewedBlockIDs,
                candidateFindings: review.candidateFindings,
                explicitConclusionBlockID: review.explicitConclusionBlockID,
                explicitConclusionQuote: review.explicitConclusionQuote,
                userMessage: message,
                explanation: review.explanation + " [audit: \(reason)]"
            ),
            reasons: [reason]
        )
    }
}

nonisolated enum WordAIGroundingQuestionRisk {
    /// These phrases explicitly ask the model to supply a judgment rather
    /// than retrieve a fact. Routing them to an explicit-conclusion gate is a
    /// risk policy, not a claim that the app understands arbitrary semantics.
    static func requiresExplicitConclusion(_ question: String) -> Bool {
        let normalized = WordAIGroundingText.normalize(question)
        let markers = [
            "라고평가할수", "다고평가할수", "라고볼수", "다고볼수",
            "무조건더", "성공적이", "실패했다고", "행복했다고",
        ]
        return markers.contains { normalized.contains($0) }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

/// Mechanical evidence checks only. Search score, word overlap, and local
/// ambiguity are intentionally absent: they are retrieval signals, not proof.
nonisolated enum WordAIEvidenceGuardrail {
    static func isCitationFormattingFailure(
        _ result: WordAIEvidenceGuardrailResult
    ) -> Bool {
        result.state == .rejected
            && !result.reasons.isEmpty
            && result.reasons.allSatisfy {
                $0 == "quoteNotFoundInBlock" || $0 == "quoteTooShort"
            }
    }

    static func validate(
        _ response: WordAIGroundingResponse,
        context: WordAIGroundingContext
    ) -> WordAIEvidenceGuardrailResult {
        let message = response.assistantMessage.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !message.isEmpty else {
            return rejected("emptyAssistantMessage")
        }

        if response.intent == .clarify, response.claims.isEmpty {
            return WordAIEvidenceGuardrailResult(
                state: .clarify,
                reasons: ["modelRequestedClarification"],
                citedQuotes: []
            )
        }

        guard !response.claims.isEmpty else {
            return rejected("answerHasNoClaims")
        }
        let blocksByID = Dictionary(
            uniqueKeysWithValues: context.blocks.map { ($0.id, $0) }
        )
        let eligible = Set(context.eligibleEvidenceBlockIDs)
        guard !eligible.isEmpty else {
            return rejected("eligibleCandidateNotFound")
        }

        var allQuotes: [String] = []
        var allScopes: [String] = []
        for claim in response.claims {
            let claimText = claim.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !claimText.isEmpty else {
                return rejected("emptyClaim")
            }
            guard !claim.evidence.isEmpty else {
                return rejected("claimHasNoEvidence")
            }

            var claimQuotes: [String] = []
            var claimScopes: [String] = []
            for evidence in claim.evidence {
                guard eligible.contains(evidence.blockID) else {
                    return rejected("evidenceOutsideEligibleCandidates")
                }
                guard let block = blocksByID[evidence.blockID] else {
                    return rejected("unknownBlockID")
                }
                let quote = evidence.quote.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard quote.count >= 4 else {
                    return rejected("quoteTooShort")
                }
                guard WordAIGroundingText.sourceContainsEquivalentQuote(
                    quote,
                    in: block.text
                ) else {
                    return rejected("quoteNotFoundInBlock")
                }
                claimQuotes.append(quote)
                allQuotes.append(quote)
                if !block.scopeText.isEmpty {
                    claimScopes.append(block.scopeText)
                    allScopes.append(block.scopeText)
                }
            }

            guard protectedValues(
                in: claimText,
                areSupportedBy: claimQuotes,
                scopes: claimScopes
            ) else {
                return rejected("claimValueNotInEvidence")
            }
        }

        guard protectedValues(
            in: message,
            areSupportedBy: allQuotes,
            scopes: allScopes
        ) else {
            return rejected("answerValueNotInEvidence")
        }
        return WordAIEvidenceGuardrailResult(
            state: .passed,
            reasons: [],
            citedQuotes: allQuotes
        )
    }

    private static func protectedValues(
        in text: String,
        areSupportedBy quotes: [String],
        scopes: [String]
    ) -> Bool {
        let requested = WordAIGroundingText.protectedTokens(in: text)
        guard !requested.isEmpty else { return true }
        let quoteValues = quotes.reduce(into: Set<String>()) { result, quote in
            result.formUnion(WordAIGroundingText.protectedTokens(in: quote))
        }
        let scopeValues = scopes.reduce(into: Set<String>()) { result, scope in
            result.formUnion(WordAIGroundingText.protectedTokens(in: scope))
        }
        return requested.allSatisfy { value in
            quoteValues.contains(value)
                || (WordAIGroundingText.isTemporalToken(value)
                    && scopeValues.contains(value))
        }
    }

    private static func rejected(
        _ reason: String
    ) -> WordAIEvidenceGuardrailResult {
        WordAIEvidenceGuardrailResult(
            state: .rejected,
            reasons: [reason],
            citedQuotes: []
        )
    }
}

/// Combines mechanical proof with an independent semantic review. A supported
/// answer displays the model's concise prose; source passages remain citations
/// and are never substituted for the answer itself.
nonisolated enum WordAIGroundingDecision {
    static func make(
        response: WordAIGroundingResponse,
        guardrail: WordAIEvidenceGuardrailResult,
        review: WordAIGroundingSemanticReview?
    ) -> WordAIGroundingValidation {
        let message = response.assistantMessage.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        switch guardrail.state {
        case .clarify:
            return WordAIGroundingValidation(
                state: .clarify,
                displayText: message,
                reasons: guardrail.reasons
            )
        case .rejected:
            if WordAIEvidenceGuardrail.isCitationFormattingFailure(guardrail),
               let review,
               review.verdict == .supported,
               review.candidateFindings.contains(where: {
                   $0.support == .completeAnswer
               }),
               answerValuesInReviewSupportMessage(
                    message,
                    review: review
               ) {
                return WordAIGroundingValidation(
                    state: response.intent == .answer ? .verified : .clarify,
                    displayText: message,
                    reasons: ["citationFormattingRecoveredBySemanticReview"]
                )
            }
            return WordAIGroundingValidation(
                state: .rejected,
                displayText: guardrailMessage(for: guardrail.reasons.first),
                reasons: guardrail.reasons
            )
        case .passed:
            guard let review else {
                return WordAIGroundingValidation(
                    state: .reviewRequired,
                    displayText: "답변과 원문 근거의 의미 검토를 완료하지 못했습니다.",
                    reasons: ["semanticReviewMissing"]
                )
            }
            switch review.verdict {
            case .supported:
                if response.intent == .clarify {
                    return WordAIGroundingValidation(
                        state: .clarify,
                        displayText: message,
                        reasons: ["modelRequestedClarification"]
                    )
                }
                return WordAIGroundingValidation(
                    state: .verified,
                    displayText: message,
                    reasons: []
                )
            case .contradicted:
                return WordAIGroundingValidation(
                    state: .clarify,
                    displayText: reviewMessage(
                        review.userMessage,
                        fallback: "문서 안에 서로 충돌하는 근거가 있습니다. 어떤 기준을 사용할지 알려주세요."
                    ),
                    reasons: ["semanticContradiction"]
                )
            case .insufficient:
                return WordAIGroundingValidation(
                    state: .clarify,
                    displayText: reviewMessage(
                        review.userMessage,
                        fallback: "현재 찾은 원문만으로 답을 확정하기 어렵습니다. 대상을 조금 더 구체적으로 알려주세요."
                    ),
                    reasons: ["semanticEvidenceInsufficient"]
                )
            }
        }
    }

    private static func reviewMessage(
        _ value: String,
        fallback: String
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func answerValuesInReviewSupportMessage(
        _ message: String,
        review: WordAIGroundingSemanticReview
    ) -> Bool {
        let requested = WordAIGroundingText.protectedTokens(in: message)
        guard !requested.isEmpty else { return true }
        let supported = review.candidateFindings.reduce(into: Set<String>()) {
            result, finding in
            guard finding.support != .noAnswer else { return }
            for value in finding.answerValues {
                result.formUnion(
                    WordAIGroundingText.protectedTokens(in: value)
                )
            }
        }
        return requested.allSatisfy { token in
            supported.contains { candidate in
                WordAIGroundingText.protectedTokenSetsAreEquivalent(
                    [token],
                    [candidate]
                )
            }
        }
    }

    private static func guardrailMessage(for reason: String?) -> String {
        switch reason {
        case "unknownBlockID", "evidenceOutsideEligibleCandidates":
            return "AI가 인용한 위치가 이번 문서 검색 범위에 없어 답을 보류했습니다."
        case "quoteNotFoundInBlock", "quoteTooShort":
            return "AI가 표시한 인용문이 원문과 정확히 일치하지 않아 답을 보류했습니다."
        case "claimValueNotInEvidence", "answerValueNotInEvidence":
            return "답변의 숫자나 날짜가 인용한 원문에서 확인되지 않아 답을 보류했습니다."
        case "clarifyContainsClaims":
            return "되묻기 응답에 근거가 확인되지 않은 사실이 포함되어 답을 보류했습니다."
        default:
            return "답변의 인용 근거를 기계적으로 확인하지 못해 답을 보류했습니다."
        }
    }
}

/// A deliberately conservative verifier. It never trusts model-provided
/// confidence. Verified facts are reconstructed as complete sentences from
/// the local source block, and clarification text is generated locally.
nonisolated enum WordAIGroundingValidator {
    static let safeClarificationMessage =
        "문서에서 답의 대상을 하나로 확정하지 못했습니다. 대상이나 기간을 더 구체적으로 알려주세요."

    static func validate(
        _ response: WordAIGroundingResponse,
        context: WordAIGroundingContext,
        policy: WordAIGroundingValidationPolicy = .singleSentence
    ) -> WordAIGroundingValidation {
        let message = response.assistantMessage.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !message.isEmpty else {
            return rejected("emptyAssistantMessage")
        }

        switch response.intent {
        case .clarify:
            guard response.claims.isEmpty else {
                return rejected("clarifyContainsClaims")
            }
            if context.requiresClarification {
                return ambiguityClarification(context: context)
            }
            return WordAIGroundingValidation(
                state: .clarify,
                displayText: safeClarificationMessage,
                reasons: []
            )
        case .answer:
            guard !response.claims.isEmpty else {
                return rejected("answerHasNoClaims")
            }
            if context.requiresClarification,
               !policy.resolvesEquivalentAmbiguity {
                return ambiguityClarification(context: context)
            }
            if policy.requiresTopCandidateEvidence,
               context.topCandidateBlockIDs.isEmpty {
                return rejected("topCandidateNotFound")
            }
            if policy.requiresEligibleEvidence,
               context.eligibleEvidenceBlockIDs.isEmpty {
                return rejected("eligibleCandidateNotFound")
            }
        }

        let blocksByID = Dictionary(
            uniqueKeysWithValues: context.blocks.map { ($0.id, $0) }
        )
        let questionTerms = WordAIGroundingText.terms(in: context.question)
        var verifiedTexts: [String] = []
        var hasInterpretation = false
        var allEvidenceTexts: [String] = []
        var allScopeTexts: [String] = []
        var evidenceQuotesByBlock: [String: [String]] = [:]
        var evidenceBlockOrder: [String] = []

        for claim in response.claims {
            let claimText = claim.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard policy.reconstructsFactsFromSource || !claimText.isEmpty else {
                return rejected("emptyClaim")
            }
            guard !claim.evidence.isEmpty else {
                return rejected("claimHasNoEvidence")
            }

            var exactQuotes: [String] = []
            var sourceSentences: [String] = []
            var claimScopeTexts: [String] = []
            for evidence in claim.evidence {
                guard let block = blocksByID[evidence.blockID] else {
                    return rejected("unknownBlockID")
                }
                if policy.requiresTopCandidateEvidence,
                   !context.topCandidateBlockIDs.contains(evidence.blockID) {
                    return rejected("evidenceOutsideTopCandidates")
                }
                if policy.requiresEligibleEvidence,
                   !context.eligibleEvidenceBlockIDs.contains(evidence.blockID) {
                    return rejected("evidenceOutsideEligibleCandidates")
                }
                let quote = evidence.quote.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard quote.count >= 4 else {
                    return rejected("quoteTooShort")
                }
                guard block.text.range(of: quote) != nil else {
                    return rejected("quoteNotFoundInBlock")
                }
                guard let sentence = WordAIGroundingText.sourceContext(
                    containing: quote,
                    in: block.text,
                    sentenceRadius: policy.contextSentenceRadius
                ) else {
                    return rejected("completeSourceSentenceNotFound")
                }
                exactQuotes.append(quote)
                if !sourceSentences.contains(sentence) {
                    sourceSentences.append(sentence)
                }
                if !block.scopeText.isEmpty,
                   !claimScopeTexts.contains(block.scopeText) {
                    claimScopeTexts.append(block.scopeText)
                }
                if evidenceQuotesByBlock[block.id] == nil {
                    evidenceBlockOrder.append(block.id)
                }
                evidenceQuotesByBlock[block.id, default: []].append(quote)
            }

            let evidenceText = sourceSentences.joined(separator: " ")
            let scopeText = claimScopeTexts.joined(separator: " ")
            if policy.reconstructsFactsFromSource {
                let claimCoverage = questionCoverage(
                    terms: questionTerms,
                    evidenceText: evidenceText,
                    scopeText: scopeText,
                    allowsTemporalScopeInheritance:
                        policy.allowsTemporalScopeInheritance
                )
                guard claimCoverage >= policy.minimumClaimCoverage else {
                    return rejected("evidenceNotRelevantToQuestion")
                }
            } else {
                guard WordAIGroundingText.protectedTokens(in: context.question)
                    .isSubset(
                        of: WordAIGroundingText.protectedTokens(in: evidenceText)
                    ) else {
                    return rejected("questionValueNotInEvidence")
                }
                guard WordAIGroundingText.protectedTokens(in: claimText)
                    .isSubset(
                        of: WordAIGroundingText.protectedTokens(in: evidenceText)
                    ) else {
                    return rejected("protectedValueNotInEvidence")
                }
                guard WordAIGroundingText.polarityIsCompatible(
                    claim: claimText,
                    evidence: evidenceText
                ) else {
                    return rejected("polarityMismatch")
                }
                let coverage = questionCoverage(
                    terms: questionTerms,
                    evidenceText: evidenceText,
                    scopeText: "",
                    allowsTemporalScopeInheritance: false
                )
                guard coverage >= policy.minimumQuestionCoverage else {
                    return rejected("evidenceNotRelevantToQuestion")
                }
            }

            switch claim.kind {
            case .extractiveFact:
                if !policy.reconstructsFactsFromSource {
                    let normalizedClaim = WordAIGroundingText.normalize(claimText)
                    let isExtracted = exactQuotes.contains { quote in
                        WordAIGroundingText.normalize(quote)
                            .contains(normalizedClaim)
                    }
                    guard isExtracted else {
                        return rejected("claimIsNotExactEvidence")
                    }
                }
                for sentence in sourceSentences
                where !verifiedTexts.contains(sentence) {
                    verifiedTexts.append(sentence)
                }
            case .interpretation:
                hasInterpretation = true
            }
            allEvidenceTexts.append(evidenceText)
            allScopeTexts.append(contentsOf: claimScopeTexts)
        }

        if policy.reconstructsFactsFromSource {
            let combinedEvidence = allEvidenceTexts.joined(separator: " ")
            let combinedScope = allScopeTexts.joined(separator: " ")
            guard questionProtectedTokensAreSupported(
                question: context.question,
                evidenceText: combinedEvidence,
                scopeText: combinedScope,
                allowsTemporalScopeInheritance:
                    policy.allowsTemporalScopeInheritance
            ) else {
                return rejected("questionValueNotInEvidence")
            }
            let coverage = questionCoverage(
                terms: questionTerms,
                evidenceText: combinedEvidence,
                scopeText: combinedScope,
                allowsTemporalScopeInheritance:
                    policy.allowsTemporalScopeInheritance
            )
            guard coverage >= policy.minimumQuestionCoverage else {
                return rejected("evidenceNotRelevantToQuestion")
            }
        }

        if context.requiresClarification {
            let anchorBlockID = evidenceBlockOrder.first
            let anchorEvidenceText = anchorBlockID.flatMap {
                evidenceQuotesByBlock[$0]?.joined(separator: " ")
            } ?? ""
            let canResolve = policy.resolvesEquivalentAmbiguity
                && !hasInterpretation
                && equivalentCandidatesAgree(
                    context: context,
                    anchorEvidenceText: anchorEvidenceText,
                    anchorBlockID: anchorBlockID
                )
            if !canResolve {
                return ambiguityClarification(context: context)
            }
        }

        if hasInterpretation {
            return WordAIGroundingValidation(
                state: .reviewRequired,
                displayText:
                    "이 질문은 원문 인용만으로 결론을 확인할 수 없어 AI 해석으로 구분했습니다.",
                reasons: ["semanticInterpretationCannotBeProvenLocally"]
            )
        }
        return WordAIGroundingValidation(
            state: .verified,
            displayText: verifiedTexts.joined(separator: "\n"),
            reasons: []
        )
    }

    private static func questionCoverage(
        terms: [String],
        evidenceText: String,
        scopeText: String,
        allowsTemporalScopeInheritance: Bool
    ) -> Double {
        guard !terms.isEmpty else { return 0 }
        let evidence = WordAIGroundingText.normalize(evidenceText)
        let scope = WordAIGroundingText.normalize(scopeText)
        let matched = terms.filter { term in
            if evidence.contains(term) { return true }
            return allowsTemporalScopeInheritance
                && WordAIGroundingText.isTemporalToken(term)
                && scope.contains(term)
        }
        return Double(matched.count) / Double(terms.count)
    }

    private static func questionProtectedTokensAreSupported(
        question: String,
        evidenceText: String,
        scopeText: String,
        allowsTemporalScopeInheritance: Bool
    ) -> Bool {
        let requested = WordAIGroundingText.protectedTokens(in: question)
        let evidence = WordAIGroundingText.protectedTokens(in: evidenceText)
        let scope = WordAIGroundingText.protectedTokens(in: scopeText)
        return requested.allSatisfy { token in
            if evidence.contains(token) { return true }
            guard allowsTemporalScopeInheritance,
                  WordAIGroundingText.isTemporalToken(token),
                  scope.contains(token) else { return false }
            return !WordAIGroundingText.hasLeadingConflictingTemporalToken(
                requestedToken: token,
                evidenceText: evidenceText,
                question: question
            )
        }
    }

    /// A lexical tie may be collapsed only after the model-selected quotes
    /// have cleared all deterministic checks. Agreement is intentionally
    /// asymmetric: any uncertainty keeps clarification enabled.
    private static func equivalentCandidatesAgree(
        context: WordAIGroundingContext,
        anchorEvidenceText: String,
        anchorBlockID: String?
    ) -> Bool {
        guard !anchorEvidenceText.isEmpty,
              let anchorBlockID,
              context.topCandidateBlockIDs.count >= 2 else { return false }
        let blocksByID = Dictionary(
            uniqueKeysWithValues: context.blocks.map { ($0.id, $0) }
        )
        return context.topCandidateBlockIDs.allSatisfy { candidateID in
            if candidateID == anchorBlockID { return true }
            guard let candidate = blocksByID[candidateID] else { return false }
            return WordAIGroundingText.conservativelySupportsSameFact(
                selectedEvidence: anchorEvidenceText,
                candidateText: candidate.text,
                question: context.question
            )
        }
    }

    private static func rejected(_ reason: String) -> WordAIGroundingValidation {
        WordAIGroundingValidation(
            state: .rejected,
            displayText: userMessage(for: reason),
            reasons: [reason]
        )
    }

    private static func ambiguityClarification(
        context: WordAIGroundingContext
    ) -> WordAIGroundingValidation {
        let blocksByID = Dictionary(
            uniqueKeysWithValues: context.blocks.map { ($0.id, $0) }
        )
        let candidateIDs = Array(context.topCandidateBlockIDs.prefix(3))
        let excerpts = candidateIDs.compactMap { blockID -> String? in
            guard let text = blocksByID[blockID]?.text else { return nil }
            let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !compact.isEmpty else { return nil }
            if compact.count <= 180 { return compact }
            return String(compact.prefix(177)) + "…"
        }

        let displayText: String
        if excerpts.count >= 2 {
            let choices = excerpts.enumerated().map { index, excerpt in
                "\(index + 1). \(excerpt)"
            }.joined(separator: "\n")
            displayText = "관련된 항목이 여러 개 있습니다.\n\(choices)\n어느 항목을 말씀하시는지 알려주세요."
        } else {
            displayText = safeClarificationMessage
        }
        return WordAIGroundingValidation(
            state: .clarify,
            displayText: displayText,
            reasons: ["localAmbiguityDetected"],
            candidateBlockIDs: candidateIDs
        )
    }

    private static func userMessage(for reason: String) -> String {
        switch reason {
        case "emptyAssistantMessage", "answerHasNoClaims":
            return "AI 답변에서 확인할 내용을 찾지 못했습니다."
        case "clarifyContainsClaims":
            return "되묻기 응답에 검증되지 않은 사실이 섞여 있어 표시하지 않았습니다."
        case "unknownBlockID", "quoteNotFoundInBlock",
             "completeSourceSentenceNotFound", "quoteTooShort":
            return "AI가 제시한 근거를 문서 원문에서 확인하지 못했습니다."
        case "questionValueNotInEvidence":
            return "질문의 날짜나 수치와 일치하는 원문 근거를 찾지 못했습니다."
        case "protectedValueNotInEvidence":
            return "답변의 날짜나 수치가 제시된 원문 근거와 일치하지 않습니다."
        case "polarityMismatch":
            return "답변의 증가·감소 방향이 원문과 일치하지 않습니다."
        case "evidenceNotRelevantToQuestion":
            return "제시된 원문이 질문과 충분히 관련되지 않아 답을 확정하지 않았습니다."
        case "claimIsNotExactEvidence":
            return "AI 답변을 원문 그대로 확인하지 못했습니다."
        case "topCandidateNotFound":
            return "질문과 가장 관련 있는 원문 후보를 확정하지 못했습니다."
        case "evidenceOutsideTopCandidates":
            return "AI가 선택한 근거가 질문의 최상위 원문 후보와 달라 답을 확정하지 않았습니다."
        case "eligibleCandidateNotFound":
            return "검증 가능한 검색 후보를 찾지 못했습니다."
        case "evidenceOutsideEligibleCandidates":
            return "AI가 선택한 근거가 로컬 검색 후보에 없어 답을 확정하지 않았습니다."
        default:
            return "답변을 문서 원문으로 안전하게 확인하지 못했습니다."
        }
    }
}

nonisolated enum WordAIGroundingAmbiguityDetector {
    struct Result: Equatable, Sendable {
        let requiresClarification: Bool
        let candidateBlockIDs: [String]
    }

    /// This lexical detector is intentionally simple. It can block obvious
    /// duplicate facts, but the POC report must treat semantic ambiguity as an
    /// unsolved class rather than as a calibrated confidence percentage.
    static func analyze(
        question: String,
        blocks: [WordAIGroundingBlock]
    ) -> Result {
        let terms = WordAIGroundingText.terms(in: question)
        guard !terms.isEmpty else {
            return Result(
                requiresClarification: true,
                candidateBlockIDs: []
            )
        }
        let protected = WordAIGroundingText.protectedTokens(in: question)
        let scored = blocks.compactMap { block -> (WordAIGroundingBlock, Int)? in
            let normalized = WordAIGroundingText.normalize(block.text)
            let lexicalMatches = terms.filter(normalized.contains).count
            let valueMatches = protected.filter(normalized.contains).count
            let score = lexicalMatches * 10 + valueMatches * 8
            return score > 0 ? (block, score) : nil
        }
        guard let topScore = scored.map(\.1).max() else {
            return Result(
                requiresClarification: true,
                candidateBlockIDs: []
            )
        }
        let top = scored.filter { $0.1 == topScore }.map(\.0)
        let sectionIDs = Set(top.map(\.sectionID))
        return Result(
            requiresClarification: sectionIDs.count > 1,
            candidateBlockIDs: top.map(\.id)
        )
    }
}

nonisolated enum WordAIGroundingText {
    private static let stopwords: Set<String> = [
        "얼마", "얼마야", "무엇", "뭐야", "알려줘", "설명해줘", "뜻해",
        "전망치", "문서", "내용", "대한", "관련", "그리고", "하면",
    ]
    private static let particles = [
        "으로", "에서", "에게", "부터", "까지", "보다", "하고", "과", "와",
        "을", "를", "은", "는", "이", "가", "의", "에", "로", "도", "만",
    ]
    private static let increaseWords = [
        "증가", "상승", "늘어", "높아", "확대", "흑자",
    ]
    private static let decreaseWords = [
        "감소", "하락", "줄어", "낮아", "축소", "적자",
    ]

    static func normalize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "퍼센트포인트", with: "%p")
            .replacingOccurrences(of: "%포인트", with: "%p")
            .replacingOccurrences(of: "퍼센트", with: "%")
            .replacingOccurrences(of: ",", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    /// PDF extraction and model JSON can preserve the same visible text with
    /// different compatibility glyphs, bullets, slashes, or spacing. Citation
    /// matching may ignore only those presentation characters; it never drops
    /// letters or digits and therefore cannot join separated source phrases.
    static func sourceContainsEquivalentQuote(
        _ quote: String,
        in source: String
    ) -> Bool {
        if source.range(of: quote) != nil { return true }
        let needle = citationCharacters(in: quote)
        guard needle.count >= 4 else { return false }
        return citationCharacters(in: source).contains(needle)
    }

    /// Checks the value selected by the candidate reviewer against its own
    /// quote. Numeric units may be omitted on one side (common in PDF tables),
    /// but two explicit and different units are never treated as equivalent.
    static func answerValue(
        _ value: String,
        isGroundedIn quote: String
    ) -> Bool {
        let normalizedValue = normalize(value)
        guard !normalizedValue.isEmpty else { return false }
        if normalize(quote).contains(normalizedValue) { return true }

        let requested = protectedTokens(in: value)
        if !requested.isEmpty {
            let available = protectedTokens(in: quote)
            return requested.allSatisfy { token in
                available.contains { protectedTokensAreCompatible(token, $0) }
            }
        }

        let needle = citationCharacters(in: value)
        let sourceCharacters = citationCharacters(in: quote)
        if needle.count >= 2, sourceCharacters.contains(needle) {
            return true
        }
        let lexicalTerms = terms(in: value)
        return !lexicalTerms.isEmpty
            && lexicalTerms.allSatisfy {
                normalize(quote).contains($0)
            }
    }

    static func protectedTokenSetsAreEquivalent(
        _ lhs: Set<String>,
        _ rhs: Set<String>
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return canMatchProtectedTokens(Array(lhs), Array(rhs))
    }

    static func terms(in value: String) -> [String] {
        var raw: [String] = []
        var current = ""
        for scalar in value.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar)
                || scalar == "." || scalar == "%" {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                raw.append(current)
                current = ""
            }
        }
        if !current.isEmpty { raw.append(current) }

        var seen = Set<String>()
        return raw.compactMap { rawTerm in
            var term = normalize(rawTerm)
            for particle in particles where term.hasSuffix(particle) {
                guard term.count > particle.count + 1 else { continue }
                term.removeLast(particle.count)
                break
            }
            guard term.count >= 2,
                  !stopwords.contains(term),
                  seen.insert(term).inserted else { return nil }
            return term
        }
    }

    static func protectedTokens(in value: String) -> Set<String> {
        let normalized = normalize(value)
        let pattern = #"\d{1,4}(?:\.\d+)?(?:%p|%|년|월|일|명|억|만|달러|원|세)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(normalized.startIndex..., in: normalized)
        return Set(expression.matches(in: normalized, range: range).compactMap {
            Range($0.range, in: normalized).map { String(normalized[$0]) }
        })
    }

    private static func citationCharacters(in value: String) -> String {
        let compatible = value.precomposedStringWithCompatibilityMapping
            .lowercased()
        return String(compatible.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }.map(Character.init))
    }

    private static func protectedTokensAreCompatible(
        _ lhs: String,
        _ rhs: String
    ) -> Bool {
        guard let left = protectedTokenParts(lhs),
              let right = protectedTokenParts(rhs),
              left.number == right.number else { return false }
        return left.unit == right.unit
            || left.unit.isEmpty
            || right.unit.isEmpty
    }

    private static func protectedTokenParts(
        _ token: String
    ) -> (number: String, unit: String)? {
        let normalized = normalize(token)
        let pattern = #"^(\d{1,4}(?:\.\d+)?)(%p|%|년|월|일|명|억|만|달러|원|세)?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: normalized,
                range: NSRange(normalized.startIndex..., in: normalized)
              ),
              let numberRange = Range(match.range(at: 1), in: normalized)
        else { return nil }
        let unit: String
        if match.range(at: 2).location != NSNotFound,
           let unitRange = Range(match.range(at: 2), in: normalized) {
            unit = String(normalized[unitRange])
        } else {
            unit = ""
        }
        return (String(normalized[numberRange]), unit)
    }

    private static func canMatchProtectedTokens(
        _ lhs: [String],
        _ rhs: [String]
    ) -> Bool {
        guard let first = lhs.first else { return rhs.isEmpty }
        for index in rhs.indices
        where protectedTokensAreCompatible(first, rhs[index]) {
            var remaining = rhs
            remaining.remove(at: index)
            if canMatchProtectedTokens(Array(lhs.dropFirst()), remaining) {
                return true
            }
        }
        return false
    }

    static func orderedProtectedTokens(in value: String) -> [String] {
        let normalized = normalize(value)
        let pattern = #"\d{1,4}(?:\.\d+)?(?:%p|%|년|월|일|명|억|만|달러|원|세)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(normalized.startIndex..., in: normalized)
        return expression.matches(in: normalized, range: range).compactMap {
            Range($0.range, in: normalized).map { String(normalized[$0]) }
        }
    }

    static func isTemporalToken(_ token: String) -> Bool {
        token.hasSuffix("년") || token.hasSuffix("월") || token.hasSuffix("일")
    }

    /// Scope inheritance must not turn an explicitly different leading period
    /// into the requested period. A later historical comparison is allowed
    /// only when a semantic question term already anchors the quoted fact.
    static func hasLeadingConflictingTemporalToken(
        requestedToken: String,
        evidenceText: String,
        question: String
    ) -> Bool {
        guard requestedToken.hasSuffix("년") else { return false }
        let evidence = normalize(evidenceText)
        let competingYears = orderedProtectedTokens(in: evidenceText).filter {
            $0.hasSuffix("년") && $0 != requestedToken
        }
        guard !competingYears.isEmpty else { return false }

        let requestedProtected = protectedTokens(in: question)
        let semanticTerms = terms(in: question).filter { term in
            !requestedProtected.contains(term)
                && !term.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
        }
        let firstSemanticLocation = semanticTerms.compactMap {
            evidence.range(of: $0)?.lowerBound
        }.min()
        guard let firstSemanticLocation else { return true }
        return competingYears.contains { year in
            guard let location = evidence.range(of: year)?.lowerBound else {
                return false
            }
            return location < firstSemanticLocation
        }
    }

    /// Returns true only for strong lexical/value agreement. This is not a
    /// semantic equivalence engine: failure to prove equivalence means ask.
    static func conservativelySupportsSameFact(
        selectedEvidence: String,
        candidateText: String,
        question: String
    ) -> Bool {
        candidateFactSegments(in: candidateText).contains { segment in
            candidateSegmentSupportsSameFact(
                selectedEvidence: selectedEvidence,
                candidateSegment: segment,
                question: question
            )
        }
    }

    private static func candidateSegmentSupportsSameFact(
        selectedEvidence: String,
        candidateSegment: String,
        question: String
    ) -> Bool {
        let candidate = normalize(candidateSegment)
        let questionTerms = terms(in: question)
        let requestedValues = protectedTokens(in: question)
        let semanticQuestionTerms = questionTerms.filter {
            !requestedValues.contains($0)
        }
        // A model may cite a sentence containing harmless context values
        // before the actual answer (for example "9월"). Checking only the
        // first value lets it omit a conflicting answer value from another
        // retrieved candidate. Require every selected source value to occur
        // in the candidate segment before collapsing an ambiguity. This is
        // intentionally one-way and conservative: extra candidate values are
        // allowed, but a missing selected value always keeps clarification.
        let selectedAnswerValues = Set(
            orderedProtectedTokens(in: selectedEvidence).filter {
                !requestedValues.contains($0)
            }
        )
        let candidateValues = protectedTokens(in: candidateSegment)
        if !selectedAnswerValues.isSubset(of: candidateValues) {
            return false
        }

        let candidateQuestionMatches = semanticQuestionTerms.filter {
            candidate.contains($0)
        }.count
        let questionCoverage = semanticQuestionTerms.isEmpty
            ? 0
            : Double(candidateQuestionMatches)
                / Double(semanticQuestionTerms.count)

        let selectedTerms = terms(in: selectedEvidence)
        let answerTerms = selectedTerms.filter { term in
            !questionTerms.contains(term)
                && !protectedTokens(in: term).contains(term)
        }
        let matchingAnswerTerms = answerTerms.filter(candidate.contains).count
        let answerCoverage = answerTerms.isEmpty
            ? 0
            : Double(matchingAnswerTerms) / Double(answerTerms.count)

        if !selectedAnswerValues.isEmpty {
            guard questionCoverage >= 0.6 else { return false }
            if semanticQuestionTerms.count < 2 {
                return answerCoverage >= 0.6
            }
            return answerTerms.isEmpty || answerCoverage >= 0.25
        }
        return answerTerms.count >= 2 && answerCoverage >= 0.6
    }

    private static func candidateFactSegments(in source: String) -> [String] {
        var segments: [String] = []
        source.enumerateSubstrings(
            in: source.startIndex..<source.endIndex,
            options: [.bySentences, .substringNotRequired]
        ) { _, range, _, _ in
            let segment = source[range].trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !segment.isEmpty { segments.append(String(segment)) }
        }
        if segments.isEmpty {
            let compact = source.trimmingCharacters(in: .whitespacesAndNewlines)
            return compact.isEmpty ? [] : [compact]
        }
        return segments
    }

    /// Returns source-owned context rather than trusting the model to choose
    /// where a quote begins or ends. If sentence segmentation cannot isolate a
    /// sentence (for example, a punctuation-free table cell), the whole local
    /// block is the conservative fallback.
    static func completeSentence(
        containing quote: String,
        in source: String
    ) -> String? {
        sourceContext(containing: quote, in: source, sentenceRadius: 0)
    }

    static func sourceContext(
        containing quote: String,
        in source: String,
        sentenceRadius: Int
    ) -> String? {
        guard let quoteRange = source.range(of: quote) else { return nil }

        var sentenceRanges: [Range<String.Index>] = []
        source.enumerateSubstrings(
            in: source.startIndex..<source.endIndex,
            options: [.bySentences, .substringNotRequired]
        ) { _, sentenceRange, _, _ in
            sentenceRanges.append(sentenceRange)
        }

        if let index = sentenceRanges.firstIndex(where: { sentenceRange in
            sentenceRange.lowerBound <= quoteRange.lowerBound
                && sentenceRange.upperBound >= quoteRange.upperBound
        }) {
            let radius = max(0, sentenceRadius)
            let lower = max(0, index - radius)
            let upper = min(sentenceRanges.count - 1, index + radius)
            let context = sentenceRanges[lower...upper].compactMap { range in
                let sentence = source[range].trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                return sentence.isEmpty ? nil : String(sentence)
            }.joined(separator: " ")
            if !context.isEmpty { return context }
        }

        let block = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return block.isEmpty ? nil : block
    }

    static func polarityIsCompatible(claim: String, evidence: String) -> Bool {
        let claim = normalize(claim)
        let evidence = normalize(evidence)
        let claimIncreases = increaseWords.contains(where: claim.contains)
        let claimDecreases = decreaseWords.contains(where: claim.contains)
        let evidenceIncreases = increaseWords.contains(where: evidence.contains)
        let evidenceDecreases = decreaseWords.contains(where: evidence.contains)
        if claimIncreases && !claimDecreases && evidenceDecreases
            && !evidenceIncreases { return false }
        if claimDecreases && !claimIncreases && evidenceIncreases
            && !evidenceDecreases { return false }
        return true
    }
}
