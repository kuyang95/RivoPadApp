#if DEBUG
import Foundation
import MLX
import UIKit

/// Explicit launch-only diagnostic. Exercises the same offline loader and
/// conversation stream as the app, and writes only synthetic prompts/results.
@MainActor
enum LocalLLMBenchmark {
    private static var started = false
    private(set) static var activeSampleSeed: UInt64?

    static var usesGreedySampling: Bool {
        isRequested && ProcessInfo.processInfo.arguments.contains("--local-llm-benchmark-greedy")
    }

    static var usesRecommendedSampling: Bool {
        isRequested && ProcessInfo.processInfo.arguments.contains("--local-llm-benchmark-recommended")
    }

    static var isThinkingEnabled: Bool {
        isRequested && ProcessInfo.processInfo.arguments.contains("--local-llm-benchmark-thinking")
    }

    static var outputTokenLimitOverride: Int? {
        guard isRequested, let value = argumentValue("--local-llm-benchmark-max-tokens="),
              let limit = Int(value) else { return nil }
        return min(8192, max(1024, limit))
    }

    private static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--local-llm-benchmark")
    }

    private static func argumentValue(_ prefix: String) -> String? {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }

    private struct Sample: Codable {
        let name: String
        let prompt: String
        let expectedFragments: [String]
        let promptCharacters: Int
        let firstTokenSeconds: Double
        let firstResponseSeconds: Double
        let totalSeconds: Double
        let responseCharacters: Int
        let responseCharactersPerSecond: Double
        let mlxActiveBytes: Int
        let mlxPeakBytes: Int
        let availableAppMemoryBytes: UInt64
        let thinkingCharacters: Int
        let finalAnswerProduced: Bool
        // Fragment hint only, not a correctness grade. Normalization can join
        // unrelated numbers, and matching answers can still have false reasoning.
        let passed: Bool
        let response: String
    }

    private struct Report: Codable {
        let date: Date
        let suite: String
        let model: String
        let physicalMemoryBytes: UInt64
        let memoryTier: String
        let mlxMemoryLimitBytes: Int
        let offlineModelLoading: Bool
        let thinkingEnabled: Bool
        let maximumOutputTokens: Int
        let seed: UInt64?
        let samplingProfile: String
        var modelLoadSeconds: Double = 0
        var samples: [Sample] = []
        var completed = false
        var error: String?
    }

    static func runIfRequested() async -> Bool {
        guard isRequested else {
            return false
        }
        guard !started else { return true }
        started = true
        let wasIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = wasIdleTimerDisabled }

        let capabilities = DeviceCapabilityProfiler.snapshot()
        let policy = LocalInferencePolicy.make(from: capabilities)
        let model = LoadedModel.preferredTextModel
        let isHardSuite = ProcessInfo.processInfo.arguments.contains("--local-llm-benchmark-hard")
        let seed = argumentValue("--local-llm-benchmark-seed=").flatMap(UInt64.init)
        var report = Report(
            date: Date(), suite: isHardSuite ? "hard" : "smoke", model: model.displayName,
            physicalMemoryBytes: capabilities.physicalMemoryBytes,
            memoryTier: capabilities.memoryTier.rawValue,
            mlxMemoryLimitBytes: policy.mlxMemoryLimitBytes,
            offlineModelLoading: true,
            thinkingEnabled: isThinkingEnabled,
            maximumOutputTokens: outputTokenLimitOverride ?? policy.textMaxTokens,
            seed: seed,
            samplingProfile: usesGreedySampling ? "greedy" : (usesRecommendedSampling ? "qwen-recommended" : "app-default")
        )
        let progressAlert = presentProgress(thinkingEnabled: report.thinkingEnabled)
        defer { progressAlert?.dismiss(animated: false) }
        save(report)
        print("LOCAL_LLM_BENCHMARK_START model=\(model.displayName) physical=\(capabilities.physicalMemoryBytes) tier=\(policy.memoryTier.rawValue) limit=\(policy.mlxMemoryLimitBytes)")

        let service = LLMService.shared
        do {
            let loadStart = Date()
            try await service.activateModel(model)
            report.modelLoadSeconds = Date().timeIntervalSince(loadStart)
            save(report)
            print("LOCAL_LLM_MODEL_LOADED seconds=\(report.modelLoadSeconds) active=\(Memory.activeMemory)")

            let conversation = LLMConversationID()
            let system = "당신은 한국어로 간결하고 정확하게 답하는 도우미입니다. 제공된 문서에 없는 사실은 만들지 마세요."
            let filler = (1...90).map {
                "자료 \($0): 도서관은 자료 정리와 시설 점검을 진행했습니다. 이 항목에는 특별 강연의 날짜, 참가비, 신청 기한 정보가 없습니다."
            }.joined(separator: "\n")
            let cases: [(String, String, LLMConversationID, [String])] = isHardSuite ? hardCases : [
                ("korean_reading", "안내문: 별빛 도서관 특별 강연은 10월 17일 오후 2시입니다. 참가비는 무료이고 신청은 10월 10일까지입니다. 특별 강연의 날짜와 참가비를 한 문장으로 답하세요.", conversation, ["10월17일", "무료"]),
                ("conversation_followup", "그 강연의 신청 마감은 언제인가요? 날짜만 답하세요.", conversation, ["10월10일"]),
                ("korean_reasoning", "노트 한 권은 2500원입니다. 3권을 사고 10000원을 냈습니다. 거스름돈은 얼마인가요? 계산과 답을 두 문장 이내로 설명하세요.", .init(), ["2500원"]),
                ("long_document", filler + "\n[특별 강연 안내] 달빛 과학관은 11월 23일 오후 3시에 강연을 엽니다. 참가비는 7000원이며 11월 18일까지 신청해야 합니다.\n" + filler + "\n질문: 특별 강연 날짜, 참가비, 신청 마감을 문서에 근거해 한 문장으로 답하세요.", .init(), ["11월23일", "7000원", "11월18일"]),
            ]

            for (index, item) in cases.enumerated() {
                let (name, prompt, id, expected) = item
                if let selectedCase = argumentValue("--local-llm-benchmark-case="),
                   selectedCase != name { continue }
                progressAlert?.message = "\(index + 1)/\(cases.count)번째 문제를 풀고 있습니다.\n완료될 때까지 이 화면을 유지해 주세요."
                activeSampleSeed = seed.map { $0 + UInt64(index) }
                if let activeSampleSeed { MLXRandom.seed(activeSampleSeed) }
                print("LOCAL_LLM_SAMPLE_START \(name) thinking=\(isThinkingEnabled) maxTokens=\(report.maximumOutputTokens)")
                let start = Date()
                var first: Double?
                var firstToken: Double?
                var rawResponse = ""
                var lastProgressSeconds = 0
                let stream = try await service.streamText(
                    conversationID: id, system: system, prompt: prompt
                )
                for try await chunk in stream {
                    if firstToken == nil, !chunk.isEmpty { firstToken = Date().timeIntervalSince(start) }
                    rawResponse += chunk
                    let progressSeconds = Int(Date().timeIntervalSince(start))
                    if progressSeconds >= lastProgressSeconds + 10 {
                        lastProgressSeconds = progressSeconds
                        progressAlert?.message = "\(index + 1)/\(cases.count)번째 문제를 풀고 있습니다.\n경과 \(progressSeconds)초 · 이 화면을 유지해 주세요."
                        print("LOCAL_LLM_PROGRESS \(name) seconds=\(progressSeconds) generatedCharacters=\(rawResponse.count)")
                    }
                    if first == nil,
                       !finalAnswer(from: rawResponse).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        first = Date().timeIntervalSince(start)
                    }
                    if Date().timeIntervalSince(start) > 300 {
                        await service.cancelGeneration(for: id)
                        throw NSError(domain: "LocalLLMBenchmark", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Response exceeded 300 seconds"])
                    }
                }
                let elapsed = Date().timeIntervalSince(start)
                let response = finalAnswer(from: rawResponse).trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = response.filter { $0.isLetter || $0.isNumber }
                let passed = !response.isEmpty && !response.contains("<think>")
                    && expected.allSatisfy { normalized.contains($0) }
                report.samples.append(Sample(
                    name: name, prompt: prompt, expectedFragments: expected,
                    promptCharacters: prompt.count,
                    firstTokenSeconds: firstToken ?? elapsed,
                    firstResponseSeconds: first ?? elapsed, totalSeconds: elapsed,
                    responseCharacters: response.count,
                    responseCharactersPerSecond: Double(response.count) / max(elapsed, 0.001),
                    mlxActiveBytes: Memory.activeMemory, mlxPeakBytes: Memory.peakMemory,
                    availableAppMemoryBytes: DeviceCapabilityProfiler.snapshot().availableAppMemoryBytes,
                    thinkingCharacters: isThinkingEnabled ? rawResponse.count - response.count : 0,
                    finalAnswerProduced: !response.isEmpty,
                    passed: passed, response: response
                ))
                save(report)
                print("LOCAL_LLM_SAMPLE \(name) first=\(first ?? elapsed) total=\(elapsed) passed=\(passed) response=\(response)")
                if name != "korean_reading" { await service.resetConversation(id) }
            }
            report.completed = true
        } catch {
            report.error = String(describing: error)
            print("LOCAL_LLM_BENCHMARK_ERROR \(error)")
        }
        save(report)
        print("LOCAL_LLM_BENCHMARK_FINISHED completed=\(report.completed)")
        return true
    }

    private static func finalAnswer(from rawResponse: String) -> String {
        guard isThinkingEnabled else { return rawResponse }
        // Qwen's template already supplies the opening <think> tag in the prompt.
        guard let end = rawResponse.range(of: "</think>") else { return "" }
        return String(rawResponse[end.upperBound...])
    }

    private static func presentProgress(thinkingEnabled: Bool) -> UIAlertController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController,
              root.presentedViewController == nil else { return nil }
        let alert = UIAlertController(
            title: thinkingEnabled ? "성능 시험: 사고 모드 켜짐" : "성능 시험: 사고 모드 꺼짐",
            message: "모델을 준비하고 있습니다.\n완료될 때까지 이 화면을 유지해 주세요.",
            preferredStyle: .alert
        )
        root.present(alert, animated: false)
        return alert
    }

    /// Synthetic questions with independently enumerated/calculated answers.
    /// Fragment checks are only a first pass; explanations must be reviewed too.
    private static var hardCases: [(String, String, LLMConversationID, [String])] {
        let filler = (1...80).map {
            "[R\($0)] 남부센터 시설 점검 기록: 안내판과 서가를 정리하고 복도 조명을 확인했다. 이 기록은 정기 시설 점검에 관한 것이며 북부센터 특별강좌의 참가비, 신청 마감, 주차요금은 정하지 않는다."
        }
        let document = ([
            "[D01 / 9월 1일] 공통 안내: 특별강좌 참가비는 50,000원, 신청 마감은 10월 14일이다. 센터별 별도 공지가 있으면 그 공지를 우선한다."
        ] + Array(filler[0..<20]) + [
            "[D37 / 9월 3일] 북부센터 특별강좌: 참가비는 37,000원, 신청 마감은 10월 10일이다."
        ] + Array(filler[20..<40]) + [
            "[D68 / 9월 5일] 북부센터 특별강좌 정정: 참가비만 39,000원으로 바꾼다. 다른 조건은 D37을 유지한다."
        ] + Array(filler[40..<60]) + [
            "[D94 / 9월 7일] 남부센터 특별강좌: 참가비는 33,000원, 신청 마감은 10월 12일이다. 북부센터에는 적용하지 않는다."
        ] + Array(filler[60..<80])).joined(separator: "\n")

        return [
            ("constraint_order", """
            가, 나, 다, 라, 마, 바 여섯 사람이 한 줄에 한 번씩 선다. 아래 조건을 모두 만족하는 왼쪽부터의 순서를 구하라.
            1. 바는 가의 바로 왼쪽이다.
            2. 라는 바보다 왼쪽이고, 라와 바 사이에는 정확히 한 사람이 있다.
            3. 나는 라보다 오른쪽, 가보다 왼쪽이다.
            4. 가는 마보다 왼쪽이고, 마는 다보다 왼쪽이다.
            5. 다의 위치 번호에서 나의 위치 번호를 빼면 4이다. 맨 왼쪽은 1번이다.
            첫 줄에 여섯 이름을 쉼표로 구분해 쓰고, 다음 두 문장 이내로 조건을 확인하라.
            """, .init(), ["라나바가마다"]),
            ("constrained_optimization", """
            다음 프로젝트를 각각 최대 한 번 선택한다. 비용 합계는 12 이하, 시간 합계는 10 이하이어야 하며 점수 합계를 최대화한다. 프로젝트 일부만 선택할 수는 없다.
            프로젝트 | 비용 | 시간 | 점수
            A | 5 | 4 | 16
            B | 4 | 6 | 15
            C | 6 | 4 | 19
            D | 3 | 3 | 10
            E | 2 | 2 | 7
            F | 4 | 2 | 11
            추가 조건: A와 C를 동시에 고를 수 없다. D를 고르면 E도 반드시 골라야 한다.
            최적 조합과 합계를 '선택: 알파벳 목록 / 점수: 정수 / 비용: 정수 / 시간: 정수'로 쓰고, 두 문장 이내로 왜 더 높은 점수가 불가능한지 설명하라.
            """, .init(), ["CEF", "점수37", "비용12", "시간8"]),
            ("conditional_refund", """
            가상의 주문 규칙이다. 상품 정가는 개당 48,000원이며 처음에 3개를 샀다.
            (1) 상품 정가 합계에 먼저 15% 할인을 적용한다.
            (2) 할인 전 상품 정가 합계가 120,000원 이상일 때만 12,000원 쿠폰을 추가 차감한다.
            (3) 할인과 쿠폰을 적용한 상품 결제액이 100,000원 미만이면 배송비 3,000원을 더하고, 그 이상이면 무료다.
            (4) 1개를 반품하면 남은 2개로 위 규칙을 처음부터 다시 적용한다. 쿠폰 자격과 배송비도 다시 계산한다. 별도 반품 수수료는 없다.
            환불액은 최초 결제액에서 재계산한 최종 결제액을 뺀 금액이다. 최초 결제액, 재계산한 최종 결제액, 환불액을 각각 쓰고 계산을 설명하라. 네 문장 이내로 답하라.
            """, .init(), ["110400", "84600", "25800"]),
            ("conditional_probability", """
            상자 A에는 빨간 공 3개와 파란 공 1개, B에는 빨간 공 2개와 파란 공 2개, C에는 빨간 공 1개와 파란 공 3개가 있다.
            먼저 A, B, C 중 하나를 각각 1/6, 2/6, 3/6의 확률로 고른다. 고른 상자에서 공 두 개를 복원 없이 뽑았더니 빨간 공 하나와 파란 공 하나였다. 뽑힌 순서는 관측하지 않았다.
            이 관측 후 (가) 고른 상자가 B일 확률과 (나) 같은 상자에 남은 공에서 세 번째 공을 뽑을 때 빨간 공일 확률을 구하라.
            두 확률을 기약분수로 답하고, 관측 확률과 조건부 확률 계산을 네 문장 이내로 설명하라.
            """, .init(), ["25", "720"]),
            ("inclusion_exclusion", """
            1부터 200까지의 정수 중 3 또는 5로 나누어떨어지지만 7로는 나누어떨어지지 않는 수를 모두 더하면 얼마인가?
            중복으로 세지 않도록 포함·배제를 적용하라. 최종 합과 검산 가능한 계산식을 세 문장 이내로 답하라.
            """, .init(), ["8003"]),
            ("document_revision_and_unknown", """
            아래는 가상의 센터 문서다. 같은 대상에 대한 수정 공지를 우선하되 변경하지 않은 조건은 기존 공지를 따른다. 다른 센터의 공지를 섞지 말고, 적히지 않은 정보는 추정하지 마라.
            \(document)
            질문: 최종적으로 북부센터 특별강좌의 참가비, 신청 마감, 주차요금은 무엇인가?
            정확히 세 줄로 답하라. 참가비와 신청 마감에는 실제 근거 문서 ID를 대괄호로 붙여라. 주차요금이 없으면 '주차요금: 문서에 없음'이라고 써라.
            """, .init(), ["39000원D68", "10월10일D37", "주차요금문서에없음"]),
        ]
    }

    private static func save(_ report: Report) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let directory = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            var filename = report.suite == "hard" ? "LocalLLMHardBenchmark" : "LocalLLMBenchmark"
            if report.model == LoadedModel.ministral3_8b_instruct_4bit.displayName {
                filename += "-ministral3-8b"
            }
            if report.thinkingEnabled { filename += "-thinking" }
            else if report.seed != nil { filename += "-control" }
            if report.samplingProfile == "qwen-recommended" { filename += "-recommended" }
            if report.samplingProfile == "greedy" { filename += "-greedy" }
            try encoder.encode(report).write(
                to: directory.appendingPathComponent(filename + ".json"), options: .atomic
            )
        } catch { print("LOCAL_LLM_REPORT_ERROR \(error)") }
    }
}
#endif
