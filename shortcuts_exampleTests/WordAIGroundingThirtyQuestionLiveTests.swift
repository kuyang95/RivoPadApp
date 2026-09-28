import FirebaseAILogic
import Foundation
import PDFKit
import XCTest

@testable import shortcuts_example

/// Exploratory live evaluation against three full-size public PDFs.
///
/// The complete PDFs are downloaded and parsed on the iPad. Each question is
/// answered from four locally retrieved pages, expanding once to eight when
/// needed. Gemini drafts a concise cited answer, each candidate is reviewed in
/// an independent call, mechanical checks validate citation/value integrity,
/// and a final Gemini pass reviews semantic support. Grounding misses are
/// emitted as evaluation data, while infrastructure/token errors fail the run
/// so a partial evaluation cannot be mistaken for a valid score.
@MainActor
final class WordAIGroundingThirtyQuestionLiveTests: XCTestCase {
    private enum Expectation {
        case mustVerify([String])
        case mustNotVerify

        var label: String {
            switch self {
            case .mustVerify(let values):
                return "mustVerify:" + values.joined(separator: "|")
            case .mustNotVerify:
                return "mustNotVerify"
            }
        }
    }

    private struct EvaluationCase {
        let id: String
        let question: String
        let expectation: Expectation
    }

    private struct SourceDefinition {
        let id: String
        let title: String
        let url: URL
        let minimumPageCount: Int
        let minimumCharacterCount: Int
        let cases: [EvaluationCase]
    }

    private struct LoadedDocument {
        let blocks: [WordAIGroundingBlock]
        let pageCount: Int
        let characterCount: Int
        let byteCount: Int
    }

    private struct Retrieval {
        let blocks: [WordAIGroundingBlock]
        let scores: [Int]
        let fullDocumentBlockCount: Int

        var characterCount: Int {
            blocks.reduce(0) { $0 + $1.text.count }
        }
    }

    private struct DocumentMetric: Encodable {
        let sourceID: String
        let title: String
        let pageCount: Int
        let blockCount: Int
        let characterCount: Int
        let byteCount: Int
    }

    private struct EvaluationResult: Encodable {
        let sourceID: String
        let sourceTitle: String
        let id: String
        let question: String
        let expectation: String
        let fullPageCount: Int
        let fullCharacterCount: Int
        let retrievedBlockIDs: [String]
        let retrievalScores: [Int]
        let retrievedCharacterCount: Int
        let localAmbiguity: Bool
        let ambiguityCandidates: [String]
        let modelIntent: String?
        let modelMessage: String?
        let claimKinds: [String]
        let claimTexts: [String]
        let evidenceBlockIDs: [String]
        let evidenceQuotes: [String]
        let baselineState: String?
        let baselineReasons: [String]
        let strictState: String?
        let strictReasons: [String]
        let reviewVerdict: String?
        let reviewQuestionType: String?
        let reviewedBlockIDs: [String]
        let reviewFindings: [WordAIGroundingSemanticReview.CandidateFinding]
        let reviewExplanation: String?
        let reviewUserMessage: String?
        let reviewAuditReasons: [String]
        let displayText: String?
        let attempts: Int
        let answerTokens: Int
        let reviewTokens: Int
        let tokens: Int
        let passed: Bool
        let error: String?
    }

    private struct PipelineRun {
        let retrieval: Retrieval
        let generated: WordAIGroundingPOCLiveService.Generated
        let guardrail: WordAIEvidenceGuardrailResult
        let review: WordAIGroundingSemanticReview?
        let reviewAuditReasons: [String]
        let validation: WordAIGroundingValidation
        let attempts: Int
        let answerTokens: Int
        let reviewTokens: Int
    }

    func testThirtyQuestionsAgainstThreePublicPDFs() async throws {
        #if !WORD_AI_LIVE_EVAL
        throw XCTSkip("WORD_AI_LIVE_EVAL에서만 실제 Gemini 평가를 실행합니다.")
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
            "WORD_AI_LIVE_TOKEN_BUDGET_REFILLED "
                + String(refilledBudget.remainingTokens)
        )

        var results: [EvaluationResult] = []
        var metrics: [DocumentMetric] = []

        let selectedSources = Self.sources.compactMap { source -> SourceDefinition? in
            guard let filter = Self.liveCaseFilter else { return source }
            let cases = source.cases.filter { filter.contains($0.id) }
            guard !cases.isEmpty else { return nil }
            return SourceDefinition(
                id: source.id,
                title: source.title,
                url: source.url,
                minimumPageCount: source.minimumPageCount,
                minimumCharacterCount: source.minimumCharacterCount,
                cases: cases
            )
        }

        for source in selectedSources {
            let document = try await loadDocument(source)
            XCTAssertGreaterThanOrEqual(
                document.pageCount,
                source.minimumPageCount,
                "\(source.id) PDF page count"
            )
            XCTAssertGreaterThanOrEqual(
                document.characterCount,
                source.minimumCharacterCount,
                "\(source.id) extracted character count"
            )

            let metric = DocumentMetric(
                sourceID: source.id,
                title: source.title,
                pageCount: document.pageCount,
                blockCount: document.blocks.count,
                characterCount: document.characterCount,
                byteCount: document.byteCount
            )
            metrics.append(metric)
            emit(metric, marker: "WORD_GROUNDING_30_DOCUMENT")

            for item in source.cases {
                do {
                    let run = try await runPipeline(
                        question: item.question,
                        documentBlocks: document.blocks
                    )
                    let retrieval = run.retrieval
                    let ambiguity = WordAIGroundingAmbiguityDetector.analyze(
                        question: item.question,
                        blocks: retrieval.blocks
                    )
                    let passed = expectationPassed(
                        item.expectation,
                        validation: run.validation
                    )
                    let result = EvaluationResult(
                        sourceID: source.id,
                        sourceTitle: source.title,
                        id: item.id,
                        question: item.question,
                        expectation: item.expectation.label,
                        fullPageCount: document.pageCount,
                        fullCharacterCount: document.characterCount,
                        retrievedBlockIDs: retrieval.blocks.map(\.id),
                        retrievalScores: retrieval.scores,
                        retrievedCharacterCount: retrieval.characterCount,
                        localAmbiguity: ambiguity.requiresClarification,
                        ambiguityCandidates: ambiguity.candidateBlockIDs,
                        modelIntent: run.generated.response.intent.rawValue,
                        modelMessage: run.generated.response.assistantMessage,
                        claimKinds: run.generated.response.claims.map(\.kind.rawValue),
                        claimTexts: run.generated.response.claims.map(\.text),
                        evidenceBlockIDs: run.generated.response.claims.flatMap {
                            $0.evidence.map(\.blockID)
                        },
                        evidenceQuotes: run.generated.response.claims.flatMap {
                            $0.evidence.map(\.quote)
                        },
                        baselineState: run.guardrail.state.rawValue,
                        baselineReasons: run.guardrail.reasons,
                        strictState: run.validation.state.rawValue,
                        strictReasons: run.validation.reasons,
                        reviewVerdict: run.review?.verdict.rawValue,
                        reviewQuestionType: run.review?.questionType.rawValue,
                        reviewedBlockIDs: run.review?.reviewedBlockIDs ?? [],
                        reviewFindings: run.review?.candidateFindings ?? [],
                        reviewExplanation: run.review?.explanation,
                        reviewUserMessage: run.review?.userMessage,
                        reviewAuditReasons: run.reviewAuditReasons,
                        displayText: run.validation.displayText,
                        attempts: run.attempts,
                        answerTokens: run.answerTokens,
                        reviewTokens: run.reviewTokens,
                        tokens: run.answerTokens + run.reviewTokens,
                        passed: passed,
                        error: nil
                    )
                    results.append(result)
                    emit(result, marker: "WORD_GROUNDING_30_JSON")
                } catch {
                    let fallbackRetrieval = retrieve(
                        question: item.question,
                        from: document.blocks,
                        limit: 4
                    )
                    let fallbackAmbiguity = WordAIGroundingAmbiguityDetector.analyze(
                        question: item.question,
                        blocks: fallbackRetrieval.blocks
                    )
                    let result = EvaluationResult(
                        sourceID: source.id,
                        sourceTitle: source.title,
                        id: item.id,
                        question: item.question,
                        expectation: item.expectation.label,
                        fullPageCount: document.pageCount,
                        fullCharacterCount: document.characterCount,
                        retrievedBlockIDs: fallbackRetrieval.blocks.map(\.id),
                        retrievalScores: fallbackRetrieval.scores,
                        retrievedCharacterCount: fallbackRetrieval.characterCount,
                        localAmbiguity: fallbackAmbiguity.requiresClarification,
                        ambiguityCandidates: fallbackAmbiguity.candidateBlockIDs,
                        modelIntent: nil,
                        modelMessage: nil,
                        claimKinds: [],
                        claimTexts: [],
                        evidenceBlockIDs: [],
                        evidenceQuotes: [],
                        baselineState: nil,
                        baselineReasons: [],
                        strictState: nil,
                        strictReasons: [],
                        reviewVerdict: nil,
                        reviewQuestionType: nil,
                        reviewedBlockIDs: [],
                        reviewFindings: [],
                        reviewExplanation: nil,
                        reviewUserMessage: nil,
                        reviewAuditReasons: [],
                        displayText: nil,
                        attempts: 0,
                        answerTokens: 0,
                        reviewTokens: 0,
                        tokens: 0,
                        passed: false,
                        error: String(describing: error)
                    )
                    results.append(result)
                    emit(result, marker: "WORD_GROUNDING_30_JSON")
                }
            }
        }

        let summary: [String: Int] = [
            "sources": metrics.count,
            "cases": results.count,
            "passed": results.filter(\.passed).count,
            "failed": results.filter { !$0.passed }.count,
            "verified": results.filter { $0.strictState == "verified" }.count,
            "clarified": results.filter { $0.strictState == "clarify" }.count,
            "reviewRequired": results.filter {
                $0.strictState == "reviewRequired"
            }.count,
            "rejected": results.filter { $0.strictState == "rejected" }.count,
            "errors": results.compactMap(\.error).count,
            "retried": results.filter { $0.attempts > 1 }.count,
            "answerTokens": results.reduce(0) { $0 + $1.answerTokens },
            "reviewTokens": results.reduce(0) { $0 + $1.reviewTokens },
            "tokens": results.reduce(0) { $0 + $1.tokens },
            "fullCharacters": metrics.reduce(0) { $0 + $1.characterCount },
            "retrievedCharacters": results.reduce(0) {
                $0 + $1.retrievedCharacterCount
            },
        ]
        emit(summary, marker: "WORD_GROUNDING_30_SUMMARY")

        XCTAssertEqual(metrics.count, selectedSources.count)
        XCTAssertEqual(
            results.count,
            selectedSources.reduce(0) { $0 + $1.cases.count }
        )
        XCTAssertTrue(
            results.allSatisfy { $0.error == nil },
            "AI 호출 오류가 있어 30문항 평가는 유효하지 않습니다."
        )
        #endif
    }

    /// Runs a high-recall first pass and expands from four to eight pages once
    /// when the model asks for clarification, the mechanical guardrail fails,
    /// or the independent reviewer finds insufficient evidence. A semantic
    /// contradiction is returned immediately so the user sees the real clash.
    private func runPipeline(
        question: String,
        documentBlocks: [WordAIGroundingBlock]
    ) async throws -> PipelineRun {
        var feedback: String?
        var answerTokens = 0
        var reviewTokens = 0

        for attemptIndex in 0..<2 {
            let retrieval = retrieve(
                question: question,
                from: documentBlocks,
                limit: attemptIndex == 0 ? 4 : 8
            )
            let context = WordAIGroundingContext(
                question: question,
                blocks: retrieval.blocks,
                requiresClarification: false,
                eligibleEvidenceBlockIDs: retrieval.blocks.map(\.id)
            )
            let generated = try await WordAIGroundingPOCLiveService.answer(
                question: question,
                blocks: retrieval.blocks,
                repairFeedback: feedback
            )
            answerTokens += generated.tokens
            let guardrail = WordAIEvidenceGuardrail.validate(
                generated.response,
                context: context
            )

            var semanticReview: WordAIGroundingSemanticReview?
            var reviewAuditReasons: [String] = []
            if guardrail.state == .passed
                || WordAIEvidenceGuardrail.isCitationFormattingFailure(
                    guardrail
                ) {
                let candidateReview = try await WordAIGroundingPOCLiveService
                    .reviewCandidates(
                        question: question,
                        blocks: retrieval.blocks
                    )
                reviewTokens += candidateReview.tokens
                let reviewed = try await WordAIGroundingPOCLiveService.review(
                    question: question,
                    response: generated.response,
                    blocks: retrieval.blocks,
                    findings: candidateReview.findings
                )
                reviewTokens += reviewed.tokens
                let audited = WordAIGroundingSemanticAudit.evaluate(
                    reviewed.review,
                    question: question,
                    blocks: retrieval.blocks
                )
                semanticReview = audited.review
                reviewAuditReasons = audited.reasons
            }
            let validation = WordAIGroundingDecision.make(
                response: generated.response,
                guardrail: guardrail,
                review: semanticReview
            )

            let shouldRetry: Bool
            if attemptIndex == 0 {
                if guardrail.state == .rejected,
                   validation.state != .verified {
                    feedback = "기계적 근거 검사에 실패했습니다: \(guardrail.reasons.joined(separator: ", ")). evidence.quote를 원문에서 정확히 복사하고 답의 숫자와 날짜를 인용에 맞춰 다시 작성하세요."
                    shouldRetry = true
                } else if guardrail.state == .clarify {
                    feedback = "첫 검색 범위에서는 답을 확정하지 못했습니다. 확장된 후보 전체를 다시 확인하고, 답이 있으면 정확한 인용으로 답하세요. 그래도 문서에 없거나 모호하면 실제 이유를 구체적으로 설명하세요."
                    shouldRetry = true
                } else if semanticReview?.verdict == .insufficient {
                    feedback = "독립 검토가 근거 부족으로 판정했습니다: \(semanticReview?.explanation ?? ""). 확장된 후보에서 더 직접적인 근거를 찾아 다시 답하세요."
                    shouldRetry = true
                } else {
                    shouldRetry = false
                }
            } else {
                shouldRetry = false
            }

            if !shouldRetry {
                return PipelineRun(
                    retrieval: retrieval,
                    generated: generated,
                    guardrail: guardrail,
                    review: semanticReview,
                    reviewAuditReasons: reviewAuditReasons,
                    validation: validation,
                    attempts: attemptIndex + 1,
                    answerTokens: answerTokens,
                    reviewTokens: reviewTokens
                )
            }
        }
        throw WordAICommandServiceError.invalidResponse
    }

    private func loadDocument(
        _ source: SourceDefinition
    ) async throws -> LoadedDocument {
        let (data, response) = try await downloadWithRetry(from: source.url)
        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
        }
        guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var blocks: [WordAIGroundingBlock] = []
        blocks.reserveCapacity(pdf.pageCount)
        var characterCount = 0
        for pageIndex in 0..<pdf.pageCount {
            guard let raw = pdf.page(at: pageIndex)?.string else { continue }
            let text = compactWhitespace(raw)
            let scopeText = trustedScope(
                documentTitle: source.title,
                pageText: raw
            )
            characterCount += text.count
            guard text.count >= 30 else { continue }
            let pageNumber = String(format: "%03d", pageIndex + 1)
            blocks.append(
                WordAIGroundingBlock(
                    id: "\(source.id)-p\(pageNumber)",
                    sectionID: "\(source.id)-p\(pageNumber)",
                    text: text,
                    scopeText: scopeText
                )
            )
        }
        return LoadedDocument(
            blocks: blocks,
            pageCount: pdf.pageCount,
            characterCount: characterCount,
            byteCount: data.count
        )
    }

    private func downloadWithRetry(
        from url: URL
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await URLSession.shared.data(for: request)
            } catch {
                lastError = error
                guard attempt < 2 else { break }
                try await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    private func compactWhitespace(_ value: String) -> String {
        value.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Keeps only the document title and the short leading lines that act as
    /// a page heading. Body paragraphs and table rows are deliberately not
    /// inherited as scope.
    private func trustedScope(
        documentTitle: String,
        pageText: String
    ) -> String {
        let leadingLines = pageText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(8)
        var headings: [String] = []
        var length = 0
        for line in leadingLines {
            guard line.count <= 100, length + line.count <= 260 else { break }
            headings.append(line)
            length += line.count
        }
        return ([documentTitle] + headings).joined(separator: " > ")
    }

    private func retrieve(
        question: String,
        from blocks: [WordAIGroundingBlock],
        limit: Int
    ) -> Retrieval {
        let terms = WordAIGroundingText.terms(in: question)
        let protected = WordAIGroundingText.protectedTokens(in: question)
        let scored = blocks.enumerated().map { index, block in
            let normalized = WordAIGroundingText.normalize(block.text)
            let lexicalMatches = terms.filter(normalized.contains).count
            let valueMatches = protected.filter(normalized.contains).count
            let occurrenceBonus = terms.reduce(0) { partial, term in
                partial + min(3, normalized.components(separatedBy: term).count - 1)
            }
            let score = lexicalMatches * 100
                + valueMatches * 40
                + occurrenceBonus * 5
            return (index: index, block: block, score: score)
        }
        .filter { $0.score > 0 }
        .sorted {
            if $0.score == $1.score { return $0.index < $1.index }
            return $0.score > $1.score
        }

        let selected = Array(scored.prefix(limit))
        return Retrieval(
            blocks: selected.map(\.block),
            scores: selected.map(\.score),
            fullDocumentBlockCount: blocks.count
        )
    }

    private func expectationPassed(
        _ expectation: Expectation,
        validation: WordAIGroundingValidation
    ) -> Bool {
        switch expectation {
        case .mustNotVerify:
            return validation.state != .verified
        case .mustVerify(let expectedValues):
            guard validation.state == .verified,
                  let displayText = validation.displayText else { return false }
            let normalized = WordAIGroundingText.normalize(displayText)
            return expectedValues.allSatisfy {
                normalized.contains(WordAIGroundingText.normalize($0))
            }
        }
    }

    private func emit<T: Encodable>(_ value: T, marker: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else {
            XCTFail("\(marker) JSON encoding failed")
            return
        }
        print(marker + " " + String(decoding: data, as: UTF8.self))
    }
}

private extension WordAIGroundingThirtyQuestionLiveTests {
    /// The full test remains the release gate. This compile-time filter exists
    /// only so a same-day POC can retest known failures without spending the
    /// remaining daily token budget on 20 already-correct controls.
    private static var liveCaseFilter: Set<String>? {
        #if WORD_AI_LIVE_CRITICAL_REGRESSION
        return ["P02", "W09"]
        #elseif WORD_AI_LIVE_FAILURE_REGRESSION
        return [
            "S01", "S03", "S06", "P02", "P07",
            "W03", "W07", "W08", "W09", "W10",
        ]
        #else
        return nil
        #endif
    }

    private static let sources: [SourceDefinition] = [
        SourceDefinition(
            id: "social",
            title: "2024년 사회조사 결과",
            url: URL(string: "https://sri.kostat.go.kr/boardDownload.es?bid=219&list_no=433638&seq=8")!,
            minimumPageCount: 140,
            minimumCharacterCount: 180_000,
            cases: [
                .init(id: "S01", question: "2024년 전반적인 가족 관계 만족도는 몇 퍼센트야?", expectation: .mustVerify(["63.5"])),
                .init(id: "S02", question: "2024년 가사를 공평하게 분담해야 한다고 생각한 비중은?", expectation: .mustVerify(["68.9"])),
                .init(id: "S03", question: "실제로 가사를 공평하게 분담한다고 응답한 아내 비중은?", expectation: .mustVerify(["23.3"])),
                .init(id: "S04", question: "2024년 결혼을 해야 한다고 생각한 비중은?", expectation: .mustVerify(["52.5"])),
                .init(id: "S05", question: "가장 효과적인 저출생 대책과 응답 비중은?", expectation: .mustVerify(["주거 지원", "33.4"])),
                .init(id: "S06", question: "한 가정의 이상적인 자녀 수 평균은?", expectation: .mustVerify(["1.89"])),
                .init(id: "S07", question: "학교생활에 만족한 중·고등학생 비중은?", expectation: .mustVerify(["57.3"])),
                .init(id: "S08", question: "중·고등학생이 공부하는 가장 큰 이유와 비중은?", expectation: .mustVerify(["좋은 직업", "74.9"])),
                .init(id: "S09", question: "2026년 가족 관계 만족도는?", expectation: .mustNotVerify),
                .init(id: "S10", question: "2024년 한국 사회는 전반적으로 행복했다고 볼 수 있어?", expectation: .mustNotVerify),
            ]
        ),
        SourceDefinition(
            id: "privacy",
            title: "생성형 인공지능(AI) 개발·활용을 위한 개인정보 처리 안내서",
            url: URL(string: "https://www.pipc.go.kr/np/cmm/fms/FileDown.do?atchFileId=FILE_000000000559959&fileSn=3&fileExtsn=pdf")!,
            minimumPageCount: 40,
            minimumCharacterCount: 50_000,
            cases: [
                .init(id: "P01", question: "안내서는 생성형 AI 개발·활용 생애주기를 몇 단계로 분류해?", expectation: .mustNotVerify),
                .init(id: "P02", question: "안내서가 구분한 대표적인 LLM 개발·활용 방식 세 가지는?", expectation: .mustVerify(["서비스형", "기성", "자체 개발"])),
                .init(id: "P03", question: "서비스형 LLM 이용사업자는 전송 데이터와 관련해 무엇을 확인해야 해?", expectation: .mustVerify(["처리 목적", "보관", "파기"])),
                .init(id: "P04", question: "기성 LLM 활용 방식이 서비스형 LLM보다 갖는 통제상 장점은?", expectation: .mustVerify(["모델 통제권", "더 높"])),
                .init(id: "P05", question: "자체개발 LLM 방식에 필요한 자원상 부담은?", expectation: .mustVerify(["고비용", "전문인력"])),
                .init(id: "P06", question: "공개된 개인정보 처리 시 검토해야 하는 세 가지 기준은?", expectation: .mustVerify(["정당성", "필요성", "이익형량"])),
                .init(id: "P07", question: "AI 프라이버시 거버넌스는 누구를 중심으로 구성해?", expectation: .mustVerify(["CPO"])),
                .init(id: "P08", question: "민감정보 또는 고유식별정보가 포함된 개인정보 영향평가 기준 인원은?", expectation: .mustVerify(["5만명"])),
                .init(id: "P09", question: "이 안내서의 2027년 개정일은?", expectation: .mustNotVerify),
                .init(id: "P10", question: "서비스형 LLM과 자체개발 중 어느 방식이 무조건 더 안전해?", expectation: .mustNotVerify),
            ]
        ),
        SourceDefinition(
            id: "weather",
            title: "2024 기상연감",
            url: URL(string: "https://www.weather.go.kr/kma/resources/introduce/yearbook_2024.pdf")!,
            minimumPageCount: 400,
            minimumCharacterCount: 350_000,
            cases: [
                .init(id: "W01", question: "2024년 우리나라 연평균기온은?", expectation: .mustVerify(["14.5"])),
                .init(id: "W02", question: "2024년 우리나라 연강수량은?", expectation: .mustVerify(["1414.6"])),
                .init(id: "W03", question: "2024년 9월 전국 평균기온은?", expectation: .mustVerify(["24.7"])),
                .init(id: "W04", question: "2024년 여름철 강수량 중 장마철 강수량 비율은?", expectation: .mustVerify(["78.8"])),
                .init(id: "W05", question: "2024년 온열질환자 수와 전년 대비 증가율은?", expectation: .mustVerify(["3704", "31.4"])),
                .init(id: "W06", question: "2024년 전 지구 평균기온은 산업화 이전보다 얼마나 높았어?", expectation: .mustVerify(["1.55"])),
                .init(id: "W07", question: "2024년 북서태평양 태풍 발생 수와 우리나라 영향 태풍 수는?", expectation: .mustVerify(["26", "2"])),
                .init(id: "W08", question: "기상 영향예보는 몇 단계로 구성돼?", expectation: .mustVerify(["4단계"])),
                .init(id: "W09", question: "2024년 연간 폭염일수와 열대야일수는 정확히 며칠이야?", expectation: .mustNotVerify),
                .init(id: "W10", question: "2024년 기상청의 재난 대응은 성공적이었다고 평가할 수 있어?", expectation: .mustNotVerify),
            ]
        ),
    ]
}
