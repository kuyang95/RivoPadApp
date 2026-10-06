import RivoDocumentEngine
import FirebaseAILogic
import Foundation

nonisolated enum ExcelAICommandServiceError: LocalizedError {
    case unavailable
    case invalidResponse
    case timedOut
    case networkUnavailable
    case authenticationFailed
    case invalidRequest
    case modelUnavailable
    case dailyQuotaExceeded
    case quotaExceeded
    case serviceUnavailable
    case promptBlocked
    case responseIncomplete
    case providerError(code: Int)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return AppLocalization.string(
                "AI 문서 도우미에 연결할 수 없습니다. 인터넷 연결을 확인해 주세요."
            )
        case .invalidResponse:
            return AppLocalization.string(
                "AI의 응답을 안전한 엑셀 수정안으로 바꾸지 못했습니다. 다시 지시해 주세요."
            )
        case .timedOut:
            return AppLocalization.string(
                "AI 응답 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요."
            )
        case .networkUnavailable:
            return AppLocalization.string(
                "인터넷 연결을 확인한 뒤 다시 시도해 주세요."
            )
        case .authenticationFailed:
            return AppLocalization.string(
                "Firebase AI 인증이 거부되었습니다. 개발용 앱에서는 App Check 디버그 토큰 등록 여부를 확인해 주세요."
            )
        case .invalidRequest:
            return AppLocalization.string(
                "Firebase AI가 요청 형식을 거부했습니다. 앱의 AI 설정을 확인해 주세요."
            )
        case .modelUnavailable:
            return AppLocalization.string(
                "현재 설정된 Gemini 모델을 사용할 수 없습니다. 모델 설정을 업데이트해 주세요."
            )
        case .dailyQuotaExceeded:
            return CloudAITokenBudgetError
                .dailyLimitExceeded(
                    remainingTokens: 0,
                    requiredTokens: 1
                )
                .errorDescription
        case .quotaExceeded:
            return AppLocalization.string(
                "Firebase AI 사용 한도에 도달했습니다. 잠시 후 다시 시도해 주세요."
            )
        case .serviceUnavailable:
            return AppLocalization.string(
                "Firebase AI 서버가 일시적으로 응답하지 않습니다. 잠시 후 다시 시도해 주세요."
            )
        case .promptBlocked:
            return AppLocalization.string(
                "안전 설정으로 인해 AI가 이 요청을 처리하지 않았습니다. 표현을 바꿔 다시 시도해 주세요."
            )
        case .responseIncomplete:
            return AppLocalization.string(
                "AI 응답이 완성되기 전에 중단되었습니다. 지시를 짧게 나눠 다시 시도해 주세요."
            )
        case let .providerError(code):
            return AppLocalization.format(
                "Firebase AI 요청 중 오류가 발생했습니다. 오류 코드: %d",
                code
            )
        }
    }
}

nonisolated struct ExcelAICommandRequestFailure: LocalizedError {
    let reason: ExcelAICommandServiceError
    let diagnosticDescription: String

    var errorDescription: String? {
        reason.errorDescription
    }
}

@MainActor
enum ExcelAICommandService {
    // The prompts, schemas and request rules live in the engine
    // (`ExcelAIAssistant`) so every host sends the same request.
    static var modelName: String { ExcelAIAssistant.modelName }
    static var systemInstruction: String { ExcelAIAssistant.systemInstruction }
    static var readQueryInstruction: String { ExcelAIAssistant.readQueryInstruction }
    static let responseSchema = ExcelAIAssistant.responseSchema.firebaseSchema
    static let readQuerySchema = ExcelAIAssistant.readQuerySchema.firebaseSchema

    static func plan(
        userRequest: String,
        snapshot: ExcelAIWorkbookSnapshot,
        history: [ExcelAIChatTurn]
    ) async throws -> ExcelAICommandPlan {
        let request: ExcelAIAssistant.CloudRequest
        switch try ExcelAIAssistant.prepare(userRequest: userRequest, snapshot: snapshot, history: history) {
        case .local(let plan):
            return plan
        case .cloud(let cloud):
            request = cloud
        }
        guard FirebaseRuntime.isConfigured else {
            throw ExcelAICommandServiceError.unavailable
        }
        let responseText = try await requestResponse(requestJSON: request.userJSON)
        do {
            return try ExcelAIAssistant.plan(fromResponse: responseText, for: request)
        } catch ExcelAIAssistantError.invalidResponse {
            throw ExcelAICommandServiceError.invalidResponse
        }
    }

    static func readQuery(context: ExcelAIReadQueryContext) async throws -> ExcelAIReadQuery {
        let data = try JSONEncoder().encode(context)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ExcelAICommandServiceError.invalidResponse
        }
        let response = try await requestResponse(requestJSON: json, readQueryOnly: true)
        guard let responseData = ExcelAIAssistant.normalizedJSON(response).data(using: .utf8),
              let query = try? JSONDecoder().decode(ExcelAIReadQuery.self, from: responseData) else {
            throw ExcelAICommandServiceError.invalidResponse
        }
        return query
    }

    private static func requestResponse(requestJSON: String, readQueryOnly: Bool = false) async throws -> String {
        do {
            return try await withThrowingTaskGroup(
                of: String.self
            ) { group in
                group.addTask {
                    try await generate(requestJSON: requestJSON, readQueryOnly: readQueryOnly)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(ExcelAIAssistant.timeoutSeconds))
                    throw ExcelAICommandServiceError.timedOut
                }
                guard let result = try await group.next() else {
                    throw ExcelAICommandServiceError.invalidResponse
                }
                group.cancelAll()
                return result
            }
        } catch {
            let diagnostic = diagnosticDescription(for: error)
            RVLogger.e(
                "Excel AI 요청 실패: \(diagnostic)"
            )
            throw ExcelAICommandRequestFailure(
                reason: userFacingError(for: error),
                diagnosticDescription: diagnostic
            )
        }

    }

    private static func generate(
        requestJSON: String,
        readQueryOnly: Bool
    ) async throws -> String {
        let maximumOutputTokens = readQueryOnly
            ? ExcelAIAssistant.readQueryMaximumOutputTokens : ExcelAIAssistant.maximumOutputTokens
        let model = FirebaseAI
            .firebaseAI(backend: .googleAI())
            .generativeModel(
                modelName: modelName,
                generationConfig: GenerationConfig(
                    temperature: Float(ExcelAIAssistant.temperature),
                    maxOutputTokens: maximumOutputTokens,
                    responseMIMEType: "application/json",
                    responseSchema: readQueryOnly ? readQuerySchema : responseSchema
                ),
                systemInstruction: ModelContent(
                    role: "system",
                    parts: readQueryOnly ? readQueryInstruction : systemInstruction
                )
            )
        let contents = [ModelContent(
            role: "user",
            parts: [TextPart(requestJSON)]
        )]
        let inputTokens = try await model
            .countTokens(contents)
            .totalTokens
        let reservation = try await
            CloudAITokenBudgetStore.shared
            .reserve(
                inputTokens: inputTokens,
                maximumOutputTokens: maximumOutputTokens
            )

        do {
            let response = try await model
                .generateContent(contents)
            await CloudAITokenBudgetStore
                .shared
                .commit(
                    reservation,
                    actualTokens:
                        response
                        .usageMetadata?
                        .totalTokenCount
                )
            guard let text = response.text,
                  !text.trimmingCharacters(
                      in: .whitespacesAndNewlines
                  ).isEmpty else {
                throw ExcelAICommandServiceError
                    .invalidResponse
            }
            return text
        } catch {
            await CloudAITokenBudgetStore
                .shared
                .cancel(reservation)
            throw error
        }
    }

    nonisolated static func userFacingError(
        for error: Error
    ) -> ExcelAICommandServiceError {
        if let serviceError = error as? ExcelAICommandServiceError {
            return serviceError
        }

        if error is CloudAITokenBudgetError {
            return .dailyQuotaExceeded
        }

        if let generateError = error as? GenerateContentError {
            switch generateError {
            case let .internalError(underlying):
                return userFacingError(for: underlying)
            case let .promptImageContentError(underlying):
                return userFacingError(for: underlying)
            case .promptBlocked:
                return .promptBlocked
            case .responseStoppedEarly:
                return .responseIncomplete
            }
        }

        if error is URLError {
            return .networkUnavailable
        }

        let nsError = error as NSError
        let description = nsError.localizedDescription.lowercased()
        if nsError.domain == NSURLErrorDomain {
            return .networkUnavailable
        }
        if description.contains("app check") ||
            description.contains("appcheck") {
            return .authenticationFailed
        }

        switch nsError.code {
        case 400:
            return .invalidRequest
        case 401, 403:
            return .authenticationFailed
        case 404:
            return .modelUnavailable
        case 408:
            return .timedOut
        case 429:
            return .quotaExceeded
        case 500, 502, 503, 504:
            return .serviceUnavailable
        default:
            return .providerError(code: nsError.code)
        }
    }

    nonisolated static func diagnosticDescription(
        for error: Error
    ) -> String {
        if let generateError = error as? GenerateContentError {
            switch generateError {
            case let .internalError(underlying):
                return "GenerateContent internal: \(diagnosticDescription(for: underlying))"
            case let .promptImageContentError(underlying):
                return "Prompt content: \(diagnosticDescription(for: underlying))"
            case .promptBlocked:
                return "Prompt blocked"
            case let .responseStoppedEarly(reason, _):
                return "Response stopped early: \(String(describing: reason))"
            }
        }

        let nsError = error as NSError
        return "domain=\(nsError.domain), code=\(nsError.code), description=\(nsError.localizedDescription)"
    }
}
