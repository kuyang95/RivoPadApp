//
//  OCRService.swift
//  shortcuts_example
//
//  Created by meee on 1/30/26.
//

import Vision
import UIKit

struct OCRRecognizedLine: Equatable, Sendable {
    let text: String
    let boundingBox: CGRect
}

actor OCRService {

    static let shared = OCRService()

    func recognize(from image: UIImage) async throws -> String {
        guard image.cgImage != nil else {
            return ""
        }
        let lines = try recognizeLines(
            from: image
        )
        return lines.isEmpty
            ? "(텍스트 없음)"
            : lines
                .map(\.text)
                .joined(separator: "\n")
    }

    func recognizeLines(
        from image: UIImage,
        minimumTextHeight: Float? = nil
    ) throws -> [OCRRecognizedLine] {
        guard let cgImage = image.cgImage else {
            return []
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ko-KR", "en-US"]
        if let minimumTextHeight {
            request.minimumTextHeight =
                minimumTextHeight
        }

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])

        return request.results?
            .compactMap { observation in
                guard let text = observation
                    .topCandidates(1)
                    .first?
                    .string
                else {
                    return nil
                }
                return OCRRecognizedLine(
                    text: text,
                    boundingBox:
                        observation.boundingBox
                )
            } ?? []
    }

    func recognizeAndCorrect(
        from image: UIImage,
        isCorrectionEnabled: Bool
    ) async throws -> String {
        let original = try await recognize(
            from: image
        )
        guard original != "(텍스트 없음)"
        else {
            return original
        }
        return await LocalOCRCorrectionService
            .shared
            .correct(
                image: image,
                originalText: original,
                isEnabled:
                    isCorrectionEnabled
            )
    }
}
