import RivoDocumentEngine
import FirebaseAILogic
import Foundation

nonisolated enum WordAICommandServiceError: LocalizedError {
    case unavailable
    case invalidResponse
    case timedOut
    case quotaExceeded
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return AppLocalization.string(
                "AI 문서 도우미에 연결할 수 없습니다. 인터넷 연결을 확인해 주세요."
            )
        case .invalidResponse:
            return AppLocalization.string(
                "AI 응답을 안전한 문서 수정안으로 바꾸지 못했습니다. 다시 지시해 주세요."
            )
        case .timedOut:
            return AppLocalization.string(
                "AI 응답 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요."
            )
        case .quotaExceeded:
            return CloudAITokenBudgetError
                .dailyLimitExceeded(
                    remainingTokens: 0,
                    requiredTokens: 1
                )
                .errorDescription
        case .requestFailed:
            return AppLocalization.string(
                "AI 요청을 처리하지 못했습니다. 연결 상태와 Firebase AI 설정을 확인해 주세요."
            )
        }
    }
}

/// Calls Gemini for the Word and HWP assistant. The engine's
/// `WordAIAssistant` owns the prompts, schemas, request JSON and reply checks.
@MainActor
enum WordAICommandService {
    static func route(
        userRequest: String,
        catalog: WordAIRetrievalCatalog,
        history: [WordAIChatTurn]
    ) async throws -> WordAIRetrievalPlan {
        guard FirebaseRuntime.isConfigured else {
            throw WordAICommandServiceError.unavailable
        }
        let requestJSON = try engineCall {
            try WordAIAssistant.routeRequestJSON(userRequest: userRequest, catalog: catalog, history: history)
        }
        let responseText = try await generate(
            requestJSON: requestJSON,
            schema: WordAIAssistant.routeResponseSchema,
            instruction: WordAIAssistant.routeSystemInstruction,
            maximumOutputTokens: WordAIAssistant.routeMaximumOutputTokens,
            failureLog: "Word AI 구역 검색 실패"
        )
        do {
            return try WordAIAssistant.retrievalPlan(fromResponse: responseText, catalog: catalog)
        } catch {
            RVLogger.e("Word AI 구역 검색 응답 거부; responseCharacters=\(responseText.count)")
            throw WordAICommandServiceError.invalidResponse
        }
    }

    static func plan(
        userRequest: String,
        snapshot: WordAIDocumentSnapshot,
        history: [WordAIChatTurn]
    ) async throws -> WordAICommandPlan {
        if let message = snapshot.formContext?.clarificationMessage {
            return WordAICommandPlan(intent: .clarify, assistantMessage: message, operations: [])
        }
        guard FirebaseRuntime.isConfigured else {
            throw WordAICommandServiceError.unavailable
        }
        let requestJSON = try engineCall {
            try WordAIAssistant.planRequestJSON(userRequest: userRequest, snapshot: snapshot, history: history)
        }
        let responseText = try await generate(
            requestJSON: requestJSON,
            schema: WordAIAssistant.planResponseSchema(
                supportedOperations: snapshot.formContext?.supportedOperations ?? snapshot.supportedOperations),
            instruction: WordAIAssistant.planSystemInstruction,
            maximumOutputTokens: WordAIAssistant.planMaximumOutputTokens,
            failureLog: "Word AI 요청 실패"
        )
        do {
            return try decodeResponse(responseText)
        } catch {
            RVLogger.e("Word AI JSON 디코딩 실패; responseCharacters=\(responseText.count)")
            throw WordAICommandServiceError.invalidResponse
        }
    }

    nonisolated static func decodeResponse(
        _ responseText: String
    ) throws -> WordAICommandPlan {
        try WordAIAssistant.commandPlan(fromResponse: responseText)
    }

    private static func engineCall<T>(_ body: () throws -> T) throws -> T {
        do { return try body() } catch { throw WordAICommandServiceError.invalidResponse }
    }

    /// One model call raced against the engine's timeout.
    private static func generate(
        requestJSON: String,
        schema: ExcelAISchema,
        instruction: String,
        maximumOutputTokens: Int,
        failureLog: String
    ) async throws -> String {
        do {
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await generateJSON(
                        requestJSON: requestJSON, schema: schema.firebaseSchema,
                        instruction: instruction, maximumOutputTokens: maximumOutputTokens)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(WordAIAssistant.timeoutSeconds))
                    throw WordAICommandServiceError.timedOut
                }
                guard let result = try await group.next() else {
                    throw WordAICommandServiceError.invalidResponse
                }
                group.cancelAll()
                return result
            }
        } catch let error as WordAICommandServiceError {
            throw error
        } catch is CloudAITokenBudgetError {
            throw WordAICommandServiceError.quotaExceeded
        } catch {
            RVLogger.e("\(failureLog): \(error.localizedDescription)")
            throw WordAICommandServiceError.requestFailed
        }
    }

    private static func generateJSON(
        requestJSON: String,
        schema: Schema,
        instruction: String,
        maximumOutputTokens: Int
    ) async throws -> String {
        let model = FirebaseAI
            .firebaseAI(backend: .googleAI())
            .generativeModel(
                modelName: WordAIAssistant.modelName,
                generationConfig: GenerationConfig(
                    temperature: Float(WordAIAssistant.temperature),
                    maxOutputTokens: maximumOutputTokens,
                    responseMIMEType: "application/json",
                    responseSchema: schema
                ),
                systemInstruction: ModelContent(
                    role: "system",
                    parts: instruction
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
                      in:
                          .whitespacesAndNewlines
                  ).isEmpty else {
                throw WordAICommandServiceError
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
}
