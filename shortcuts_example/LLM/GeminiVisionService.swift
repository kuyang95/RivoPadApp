import CoreImage
import FirebaseAILogic
import UIKit

/// 이미지 분석 응답을 Gemini(Firebase AI Logic)로 생성한다.
///
/// 안드로이드 VisionCraft 의 `GeminiApiConnector.describeImage` 와 같은 경로다.
/// 이전에는 온디바이스 MLX 비전 모델(`qwen3_vl_8b_4bit`)이 담당했지만, 모델
/// 다운로드 없이 바로 쓰기 위해 서버 경로로 옮겼다. 텍스트 채팅과 문서 질의는
/// 그대로 로컬 모델을 쓴다.
nonisolated enum GeminiVisionService {

    /// 대화 맥락 한 턴. 로컬 모델은 `conversationID` 로 세션을 들고 있었지만
    /// Gemini 는 매 요청에 맥락을 실어 보내야 해서 호출부가 넘겨 준다.
    struct Turn: Sendable {
        enum Role: Sendable {
            case user
            case assistant
        }

        let role: Role
        let text: String

        init(role: Role, text: String) {
            self.role = role
            self.text = text
        }
    }

    enum ServiceError: LocalizedError {
        case imageEncodingFailed

        var errorDescription: String? {
            switch self {
            case .imageEncodingFailed:
                return AppLocalization.string(
                    "이미지를 전송할 수 있는 형식으로 변환하지 못했습니다."
                )
            }
        }
    }

    static func stream(
        system: String,
        prompt: String,
        images: [CIImage],
        history: [Turn] = []
    ) async throws -> AsyncThrowingStream<String, Error> {
        let imageParts = try imageParts(from: images)
        let contents = contents(
            history: history,
            prompt: prompt,
            imageParts: imageParts
        )
        let model = FirebaseAI
            .firebaseAI(
                backend: .googleAI()
            )
            .generativeModel(
                modelName: modelName,
                generationConfig:
                    GenerationConfig(
                        temperature: 0.2,
                        maxOutputTokens:
                            maximumOutputTokens
                    ),
                systemInstruction:
                    ModelContent(
                        role: "system",
                        parts: system
                    )
            )

        let inputTokens = try await model
            .countTokens(contents)
            .totalTokens
        let reservation = try await
            CloudAITokenBudgetStore.shared
            .reserve(
                inputTokens: inputTokens,
                maximumOutputTokens:
                    maximumOutputTokens
            )

        do {
            let responses = try model
                .generateContentStream(contents)
            return AsyncThrowingStream {
                continuation in
                let task = Task {
                    do {
                        var actualTokens: Int?
                        for try await response
                            in responses {
                            if let total = response
                                .usageMetadata?
                                .totalTokenCount {
                                actualTokens = total
                            }
                            guard let text =
                                    response.text,
                                  !text.isEmpty else {
                                continue
                            }
                            continuation.yield(
                                text
                            )
                        }
                        await CloudAITokenBudgetStore
                            .shared
                            .commit(
                                reservation,
                                actualTokens:
                                    actualTokens
                            )
                        continuation.finish()
                    } catch {
                        await CloudAITokenBudgetStore
                            .shared
                            .cancel(reservation)
                        continuation.finish(
                            throwing: error
                        )
                    }
                }
                continuation.onTermination = {
                    _ in
                    task.cancel()
                }
            }
        } catch {
            await CloudAITokenBudgetStore
                .shared
                .cancel(reservation)
            throw error
        }
    }

    /// 대화 맥락을 요청 본문으로 바꾼다. 이미지는 첫 사용자 턴에 붙여
    /// 후속 질문마다 다시 올리지 않는다.
    private static func contents(
        history: [Turn],
        prompt: String,
        imageParts: [InlineDataPart]
    ) -> [ModelContent] {
        var contents = history.map { turn in
            ModelContent(
                role: turn.role == .user
                    ? "user"
                    : "model",
                parts: [
                    TextPart(turn.text)
                ]
            )
        }
        contents.append(
            ModelContent(
                role: "user",
                parts: [
                    TextPart(prompt)
                ]
            )
        )

        guard !imageParts.isEmpty,
              let firstUserIndex = contents
                .firstIndex(where: {
                    $0.role == "user"
                }) else {
            return contents
        }
        contents[firstUserIndex] = ModelContent(
            role: "user",
            parts: imageParts.map { $0 as any Part }
                + contents[firstUserIndex].parts
        )
        return contents
    }

    private static func imageParts(
        from images: [CIImage]
    ) throws -> [InlineDataPart] {
        guard !images.isEmpty else {
            return []
        }

        let parts = images.compactMap {
            encodedImageData($0)
        }
        .map {
            InlineDataPart(
                data: $0,
                mimeType: "image/jpeg"
            )
        }
        guard !parts.isEmpty else {
            throw ServiceError.imageEncodingFailed
        }
        return parts
    }

    /// 안드로이드 `resizeForImageCaption` 과 같은 기준으로 긴 변을 1280px 로
    /// 맞춘다. 그 이상은 토큰만 늘고 설명 품질은 거의 달라지지 않는다.
    private static func encodedImageData(
        _ image: CIImage
    ) -> Data? {
        let extent = image.extent
        guard extent.width > 0,
              extent.height > 0,
              extent.isInfinite == false else {
            return nil
        }

        let longestEdge = max(
            extent.width,
            extent.height
        )
        let scale = min(
            1,
            maximumImageEdge / longestEdge
        )
        let scaled = scale < 1
            ? image.transformed(
                by: CGAffineTransform(
                    scaleX: scale,
                    y: scale
                )
            )
            : image
        guard let cgImage = renderContext
            .createCGImage(
                scaled,
                from: scaled.extent
            ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
            .jpegData(
                compressionQuality: 0.82
            )
    }

    private static let renderContext = CIContext(
        options: [
            .cacheIntermediates: false
        ]
    )
    private static let modelName =
        "gemini-2.5-flash-lite"
    private static let maximumImageEdge: CGFloat =
        1_280
    /// 안드로이드 캡션은 384 토큰이면 충분하지만, 여기는 후속 질문까지
    /// 이어지는 채팅이라 넉넉히 잡는다.
    private static let maximumOutputTokens = 2_048
}
