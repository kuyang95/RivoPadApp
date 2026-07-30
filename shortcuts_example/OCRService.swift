//
//  OCRService.swift
//  shortcuts_example
//
//  Created by meee on 1/30/26.
//

import Vision
import UIKit

actor OCRService {

    static let shared = OCRService()

    func recognize(from image: UIImage) async throws -> String {

        guard let cgImage = image.cgImage else { return "" }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ko-KR", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])

        return request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n") ?? "(텍스트 없음)"
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
