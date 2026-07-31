import Foundation
import ImageIO
@testable import shortcuts_example
import UIKit
import UniformTypeIdentifiers
import XCTest

@MainActor
final class VisionLinkRemoteFeatureTests:
    XCTestCase
{
    func testReceivedImageLoaderAppliesExifOrientationAndBoundsSize()
        async throws
    {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "VisionLinkRotated-"
                    + UUID().uuidString
                    + ".jpg"
            )
        defer {
            try? FileManager.default.removeItem(
                at: url
            )
        }
        let sourceImage =
            UIGraphicsImageRenderer(
                size: CGSize(
                    width: 20,
                    height: 40
                )
            )
            .image { context in
                UIColor.systemRed.setFill()
                context.fill(
                    CGRect(
                        x: 0,
                        y: 0,
                        width: 20,
                        height: 20
                    )
                )
                UIColor.systemBlue.setFill()
                context.fill(
                    CGRect(
                        x: 0,
                        y: 20,
                        width: 20,
                        height: 20
                    )
                )
            }
        let cgImage = try XCTUnwrap(
            sourceImage.cgImage
        )
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(
            destination,
            cgImage,
            [
                kCGImagePropertyOrientation: 6,
                kCGImageDestinationLossyCompressionQuality:
                    1,
            ] as CFDictionary
        )
        XCTAssertTrue(
            CGImageDestinationFinalize(
                destination
            )
        )

        let loaded =
            try await VisionLinkReceivedImageLoader
            .load(
                at: url,
                maximumEdge: 24
            )

        XCTAssertGreaterThan(
            loaded.width,
            loaded.height
        )
        XCTAssertLessThanOrEqual(
            max(loaded.width, loaded.height),
            24
        )
    }

    func testReceivedImageLoaderRejectsInvalidImage()
        async
    {
        let url = makeTemporaryFile()
        defer {
            try? FileManager.default.removeItem(
                at: url
            )
        }

        do {
            _ = try await
                VisionLinkReceivedImageLoader.load(
                    at: url,
                    maximumEdge: 2_048
                )
            XCTFail(
                "Invalid image data must be rejected"
            )
        } catch {
            XCTAssertEqual(
                error
                    as? VisionLinkRemoteFeatureError,
                .invalidImage
            )
        }
    }

    func testOCRProgressResultAndTemporaryCleanup()
        async throws
    {
        let fixture = makeTemporaryFile()
        let service = RemoteFeatureServiceStub()
        service.recognizedText = "인식 결과"
        var updates: [VisionLinkRemoteFeatureUpdate] =
            []

        try await VisionLinkRemoteFeatureProcessor(
            service: service
        )
        .process(
            .image(
                VisionLinkFeatureImageRequest(
                    requestID: "ocr-1",
                    feature: .ocr,
                    fileURL: fixture
                )
            )
        ) {
            updates.append($0)
        }

        XCTAssertEqual(
            updates,
            [
                .progress("recognizing"),
                .result("인식 결과"),
            ]
        )
        XCTAssertEqual(service.calls, ["recognize"])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.path
            )
        )
    }

    func testImageTranslationRunsRecognitionThenTranslation()
        async throws
    {
        let fixture = makeTemporaryFile()
        let service = RemoteFeatureServiceStub()
        service.recognizedText = "Hello"
        service.translatedText = "안녕하세요"
        var updates: [VisionLinkRemoteFeatureUpdate] =
            []

        try await VisionLinkRemoteFeatureProcessor(
            service: service
        )
        .process(
            .image(
                VisionLinkFeatureImageRequest(
                    requestID: "translation-1",
                    feature: .translation,
                    fileURL: fixture
                )
            )
        ) {
            updates.append($0)
        }

        XCTAssertEqual(
            updates,
            [
                .progress("recognizing"),
                .progress("translating"),
                .result("안녕하세요"),
            ]
        )
        XCTAssertEqual(
            service.calls,
            ["recognize", "translate:Hello"]
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.path
            )
        )
    }

    func testImageAnalysisFailureIsReturnedAndCleaned()
        async throws
    {
        let fixture = makeTemporaryFile()
        let service = RemoteFeatureServiceStub()
        service.describeError =
            RemoteFeatureStubError.failed
        var updates: [VisionLinkRemoteFeatureUpdate] =
            []

        try await VisionLinkRemoteFeatureProcessor(
            service: service
        )
        .process(
            .image(
                VisionLinkFeatureImageRequest(
                    requestID: "analysis-1",
                    feature: .imageAnalysis,
                    fileURL: fixture
                )
            )
        ) {
            updates.append($0)
        }

        XCTAssertEqual(
            updates,
            [
                .progress("analyzing"),
                .failed("모의 기능 실패"),
            ]
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.path
            )
        )
    }

    func testTextTranslationDoesNotUseTemporaryFile()
        async throws
    {
        let service = RemoteFeatureServiceStub()
        service.translatedText = "안녕하세요"
        var updates: [VisionLinkRemoteFeatureUpdate] =
            []

        try await VisionLinkRemoteFeatureProcessor(
            service: service
        )
        .process(
            .translationText(
                VisionLinkTextTranslationRequest(
                    requestID: "translation-2",
                    text: "Hello"
                )
            )
        ) {
            updates.append($0)
        }

        XCTAssertEqual(
            updates,
            [
                .progress("translating"),
                .result("안녕하세요"),
            ]
        )
        XCTAssertEqual(
            service.calls,
            ["translate:Hello"]
        )
    }

    func testOversizedResultBecomesFeatureFailure()
        async throws
    {
        let service = RemoteFeatureServiceStub()
        service.translatedText = String(
            repeating: "a",
            count:
                VisionLinkFeatureControl
                .maximumResultSize + 1
        )
        var updates: [VisionLinkRemoteFeatureUpdate] =
            []

        try await VisionLinkRemoteFeatureProcessor(
            service: service
        )
        .process(
            .translationText(
                VisionLinkTextTranslationRequest(
                    requestID: "translation-3",
                    text: "Hello"
                )
            )
        ) {
            updates.append($0)
        }

        XCTAssertEqual(
            updates.first,
            .progress("translating")
        )
        XCTAssertEqual(
            updates.last,
            .failed(
                "기능 결과가 전송 가능한 크기를 초과했습니다."
            )
        )
    }

    private func makeTemporaryFile() -> URL {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "VisionLinkFeature-"
                    + UUID().uuidString
            )
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: url.path,
                contents: Data("fixture".utf8)
            )
        )
        return url
    }
}

@MainActor
private final class RemoteFeatureServiceStub:
    VisionLinkRemoteFeatureServing
{
    var recognizedText = ""
    var describedText = ""
    var translatedText = ""
    var recognizeError: Error?
    var describeError: Error?
    var translateError: Error?
    var calls: [String] = []

    func recognizeImage(
        at url: URL
    ) async throws -> String {
        calls.append("recognize")
        if let recognizeError {
            throw recognizeError
        }
        return recognizedText
    }

    func describeImage(
        at url: URL
    ) async throws -> String {
        calls.append("describe")
        if let describeError {
            throw describeError
        }
        return describedText
    }

    func translate(
        _ text: String
    ) async throws -> String {
        calls.append("translate:\(text)")
        if let translateError {
            throw translateError
        }
        return translatedText
    }
}

nonisolated private enum RemoteFeatureStubError:
    Error,
    LocalizedError
{
    case failed

    var errorDescription: String? {
        "모의 기능 실패"
    }
}
