//
//  OCRService.swift
//  shortcuts_example
//
//  Created by meee on 1/30/26.
//

import MLKit
import UIKit

struct OCRRecognizedLine: Equatable, Sendable {
    let text: String
    let boundingBox: CGRect
}

actor OCRService {

    static let shared = OCRService()

    // Android OcrEngine과 동일하게 한국어 ML Kit recognizer를 프로세스
    // 수명 동안 한 번만 만들고 모든 OCR 진입점에서 재사용한다.
    private let recognizer =
        TextRecognizer.textRecognizer(
            options: KoreanTextRecognizerOptions()
        )

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
        guard image.cgImage != nil else {
            return []
        }

        let visionImage = VisionImage(image: image)
        visionImage.orientation = image.imageOrientation
        let result = try recognizer.results(
            in: visionImage
        )
        let imageWidth = max(image.size.width, 1)
        let imageHeight = max(image.size.height, 1)

        return result.blocks
            .flatMap(\.lines)
            .compactMap { line in
                let frame = line.frame
                let normalizedHeight =
                    frame.height / imageHeight
                if let minimumTextHeight,
                   normalizedHeight
                    < CGFloat(minimumTextHeight) {
                    return nil
                }

                // ML Kit은 좌상단 원점, 기존 뷰어는 Vision과 같은 좌하단
                // 정규화 좌표를 사용하므로 여기서 한 번 변환한다.
                let box = CGRect(
                    x: frame.minX / imageWidth,
                    y: 1 - frame.maxY / imageHeight,
                    width:
                        frame.width / imageWidth,
                    height: normalizedHeight
                )
                return OCRRecognizedLine(
                    text: line.text,
                    boundingBox: box
                )
            }
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
        return await GeminiOCRCorrectionService
            .shared
            .correct(
                image: image,
                originalText: original,
                isEnabled:
                    isCorrectionEnabled
            )
    }
}
