import CoreImage
import Foundation
import ImageIO
import UIKit

nonisolated enum VisionLinkRemoteFeatureUpdate:
    Equatable,
    Sendable
{
    case progress(String)
    case result(String)
    case failed(String)
}

@MainActor
protocol VisionLinkRemoteFeatureServing: AnyObject {
    func recognizeImage(at url: URL) async throws
        -> String
    func describeImage(at url: URL) async throws
        -> String
    func translate(_ text: String) async throws
        -> String
}

@MainActor
struct VisionLinkRemoteFeatureProcessor {
    let service: any VisionLinkRemoteFeatureServing

    func process(
        _ request: VisionLinkRemoteFeatureRequest,
        onUpdate:
            @MainActor (VisionLinkRemoteFeatureUpdate)
                -> Void
    ) async throws {
        defer {
            if let url = request.temporaryFileURL {
                try? FileManager.default.removeItem(
                    at: url
                )
            }
        }

        do {
            let result: String
            switch request {
            case .image(let imageRequest):
                switch imageRequest.feature {
                case .ocr:
                    onUpdate(.progress("recognizing"))
                    result = try await service
                        .recognizeImage(
                            at: imageRequest.fileURL
                        )

                case .imageAnalysis:
                    onUpdate(.progress("analyzing"))
                    result = try await service
                        .describeImage(
                            at: imageRequest.fileURL
                        )

                case .aiChat:
                    throw VisionLinkRemoteFeatureError
                        .unsupportedRequest

                case .liveReading:
                    throw VisionLinkRemoteFeatureError
                        .unsupportedRequest

                case .translation:
                    onUpdate(.progress("recognizing"))
                    let recognized = try await service
                        .recognizeImage(
                            at: imageRequest.fileURL
                        )
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                    guard !recognized.isEmpty,
                          recognized != "(텍스트 없음)" else {
                        throw VisionLinkRemoteFeatureError
                            .noTextToTranslate
                    }
                    try Task.checkCancellation()
                    onUpdate(.progress("translating"))
                    result = try await service
                        .translate(recognized)
                }

            case .translationText(let textRequest):
                onUpdate(.progress("translating"))
                result = try await service.translate(
                    textRequest.text
                )
            }

            try Task.checkCancellation()
            guard result.utf8.count
                    <= VisionLinkFeatureControl
                        .maximumResultSize else {
                throw VisionLinkRemoteFeatureError
                    .resultTooLarge
            }
            onUpdate(.result(result))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            onUpdate(
                .failed(Self.userMessage(for: error))
            )
        }
    }

    private static func userMessage(
        for error: Error
    ) -> String {
        let message: String
        if let error = error as? LocalizedError,
           let description = error.errorDescription {
            message = description
        } else {
            message = error.localizedDescription
        }
        let trimmed = message.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty
            ? "로컬 기능 처리에 실패했습니다."
            : trimmed
    }
}

@MainActor
final class VisionLinkLocalRemoteFeatureService:
    VisionLinkRemoteFeatureServing
{
    static let shared =
        VisionLinkLocalRemoteFeatureService()

    private let ocrService: OCRService
    private let llmService: LLMService

    private init() {
        ocrService = .shared
        llmService = .shared
    }

    func recognizeImage(
        at url: URL
    ) async throws -> String {
        let cgImage = try await Self.loadImage(
            at: url,
            maximumEdge: 2_048
        )
        try Task.checkCancellation()
        return try await ocrService.recognize(
            from: UIImage(cgImage: cgImage)
        )
    }

    func describeImage(
        at url: URL
    ) async throws -> String {
        try ensureLocalAIAvailable()
        let cgImage = try await Self.loadImage(
            at: url,
            maximumEdge: 2_048
        )
        let conversationID = LLMConversationID()
        return try await collectVisionResponse(
            conversationID: conversationID,
            system: """
            너는 시각장애 사용자를 위한 이미지 설명 도우미야.
            이미지에 실제로 보이는 핵심 대상, 글자, 위치 관계를
            한국어로 명확하고 간결하게 설명해.
            확실하지 않은 내용은 추측하지 마.
            """,
            prompt:
                "이 이미지에서 보이는 내용을 한국어로 설명해.",
            image: CIImage(cgImage: cgImage)
        )
    }

    func translate(
        _ rawText: String
    ) async throws -> String {
        let text = rawText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !text.isEmpty else {
            throw VisionLinkRemoteFeatureError
                .noTextToTranslate
        }
        try ensureLocalAIAvailable()
        let conversationID = LLMConversationID()
        return try await collectTextResponse(
            conversationID: conversationID,
            system: """
            너는 로컬 번역 엔진이야.
            원문의 언어를 감지해 한국어로 번역해.
            원문이 이미 한국어이면 원문을 그대로 반환해.
            설명, 머리말, 따옴표를 덧붙이지 말고 번역문만 출력해.
            문단, 줄바꿈, 숫자와 고유명사는 최대한 보존해.
            """,
            prompt: text
        )
    }

    private func ensureLocalAIAvailable() throws {
        guard !llmService.isGenerating,
              !llmService.isLoading else {
            throw VisionLinkRemoteFeatureError.localAIBusy
        }
    }

    private func collectTextResponse(
        conversationID: LLMConversationID,
        system: String,
        prompt: String
    ) async throws -> String {
        do {
            let stream = try await llmService.streamText(
                conversationID: conversationID,
                system: system,
                prompt: prompt
            )
            let result = try await Self.collect(stream)
            await llmService.resetConversation(
                conversationID
            )
            return try Self.validatedResult(result)
        } catch {
            await llmService.resetConversation(
                conversationID
            )
            throw error
        }
    }

    private func collectVisionResponse(
        conversationID: LLMConversationID,
        system: String,
        prompt: String,
        image: CIImage
    ) async throws -> String {
        do {
            let stream = try await llmService.streamVision(
                conversationID: conversationID,
                system: system,
                prompt: prompt,
                images: [image]
            )
            let result = try await Self.collect(stream)
            await llmService.resetConversation(
                conversationID
            )
            return try Self.validatedResult(result)
        } catch {
            await llmService.resetConversation(
                conversationID
            )
            throw error
        }
    }

    private static func collect(
        _ stream: AsyncThrowingStream<String, Error>
    ) async throws -> String {
        var result = ""
        var thinkFilter = StreamingThinkFilter()
        for try await chunk in stream {
            try Task.checkCancellation()
            result += thinkFilter.consume(chunk)
        }
        result += thinkFilter.finish()
        return result
    }

    private static func validatedResult(
        _ result: String
    ) throws -> String {
        let trimmed = result.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            throw VisionLinkRemoteFeatureError.emptyResult
        }
        return trimmed
    }

    nonisolated private static func downsampledImage(
        at url: URL,
        maximumEdge: Int
    ) throws -> CGImage {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            sourceOptions as CFDictionary
        ) else {
            throw VisionLinkRemoteFeatureError.invalidImage
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways:
                true,
            kCGImageSourceCreateThumbnailWithTransform:
                true,
            kCGImageSourceThumbnailMaxPixelSize:
                maximumEdge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image =
                CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    thumbnailOptions as CFDictionary
                ) else {
            throw VisionLinkRemoteFeatureError.invalidImage
        }
        return image
    }

    nonisolated private static func loadImage(
        at url: URL,
        maximumEdge: Int
    ) async throws -> CGImage {
        try await Task.detached(
            priority: .userInitiated
        ) {
            try downsampledImage(
                at: url,
                maximumEdge: maximumEdge
            )
        }
        .value
    }
}

nonisolated enum VisionLinkRemoteFeatureError:
    Error,
    LocalizedError,
    Equatable
{
    case invalidImage
    case noTextToTranslate
    case localAIBusy
    case emptyResult
    case resultTooLarge
    case unsupportedRequest

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "이미지를 읽을 수 없습니다."
        case .noTextToTranslate:
            return "번역할 텍스트가 없습니다."
        case .localAIBusy:
            return "로컬 AI가 다른 작업을 처리 중입니다. 잠시 후 다시 시도해 주세요."
        case .emptyResult:
            return "로컬 AI가 결과를 만들지 못했습니다."
        case .resultTooLarge:
            return "기능 결과가 전송 가능한 크기를 초과했습니다."
        case .unsupportedRequest:
            return "지원하지 않는 원격 기능 요청입니다."
        }
    }
}
