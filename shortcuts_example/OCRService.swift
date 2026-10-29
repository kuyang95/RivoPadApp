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

    /// Compare quarter turns on a bounded thumbnail; keep the camera direction on ties.
    func uprightDocument(_ image: UIImage) -> UIImage {
        let scale = min(1, 1200 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        var best = 0
        var bestScore = 0
        for turn in 0..<4 {
            if Task.isCancelled { return image }
            let candidate = rotatedDocument(thumbnail, turns: turn)
            let input = VisionImage(image: candidate)
            input.orientation = .up
            guard let result = try? recognizer.results(in: input) else { continue }
            let score = result.blocks.flatMap(\.lines).reduce(0) { total, line in
                let points = line.cornerPoints.map { $0.cgPointValue }
                guard points.count >= 2, points[1].x > points[0].x,
                      abs(points[1].y - points[0].y) < points[1].x - points[0].x else { return total }
                return total + line.text.filter { !$0.isWhitespace }.count
            }
            if score > bestScore { bestScore = score; best = turn }
        }
        return rotatedDocument(image, turns: best)
    }

    private func rotatedDocument(_ image: UIImage, turns: Int) -> UIImage {
        guard turns != 0 else { return image }
        let size = turns % 2 == 0 ? image.size : CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: CGFloat(turns) * .pi / 2)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
    }

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
