//
//  SentenceBox.swift
//  shortcuts_example
//
//  Created by meee on 2/4/26.
//

import UIKit
import Vision

struct SentenceBox {
    let id: UUID = UUID()
    let text: String
    /// Vision normalized boundingBox (origin: bottom-left, 0~1)
    let boundingBoxNormalized: CGRect
}

final class DocumentTextExtractor {

    enum ExtractError: LocalizedError {
        case cgImageMissing
        case noText

        var errorDescription: String? {
            switch self {
            case .cgImageMissing: return "이미지 변환(CGImage)에 실패했어요."
            case .noText: return "텍스트를 찾지 못했어요."
            }
        }
    }

    func extractSentenceBoxes(from image: UIImage,
                             completion: @escaping (Result<[SentenceBox], Error>) -> Void) {

        guard let cgImage = image.cgImage else {
            completion(.failure(ExtractError.cgImageMissing))
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            if observations.isEmpty {
                completion(.failure(ExtractError.noText))
                return
            }

            // 1) 라인 후보 만들기 (문자열 + 바운딩박스)
            var lines: [(text: String, bbox: CGRect)] = []
            lines.reserveCapacity(observations.count)

            for obs in observations {
                guard let top = obs.topCandidates(1).first else { continue }
                let t = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { continue }
                lines.append((t, obs.boundingBox))
            }

            if lines.isEmpty {
                completion(.failure(ExtractError.noText))
                return
            }

            // 2) 위->아래, 좌->우 정렬 (Vision bbox는 origin이 bottom-left)
            lines.sort { a, b in
                let aY = a.bbox.maxY
                let bY = b.bbox.maxY
                if abs(aY - bY) > 0.02 {   // 같은 줄(행) 허용 오차
                    return aY > bY         // 위쪽이 먼저
                } else {
                    return a.bbox.minX < b.bbox.minX
                }
            }

            // 3) 문장 휴리스틱 그룹핑: 구두점으로 문장 종료 판단
            let endPunctuations = CharacterSet(charactersIn: ".!?。！？…")
            var sentenceBoxes: [SentenceBox] = []

            var accTexts: [String] = []
            var accBBoxes: [CGRect] = []

            func flushIfNeeded() {
                guard !accTexts.isEmpty else { return }
                let sentenceText = accTexts.joined(separator: " ")
                let unionBox = accBBoxes.reduce(CGRect.null) { $0.union($1) }
                sentenceBoxes.append(SentenceBox(text: sentenceText, boundingBoxNormalized: unionBox))
                accTexts.removeAll(keepingCapacity: true)
                accBBoxes.removeAll(keepingCapacity: true)
            }

            for line in lines {
                accTexts.append(line.text)
                accBBoxes.append(line.bbox)

                // 문장 종료 추정: 마지막 글자가 구두점이면 끊기
                if let last = line.text.unicodeScalars.last,
                   endPunctuations.contains(last) {
                    flushIfNeeded()
                }
            }
            // 남은 것 마무리
            flushIfNeeded()

            completion(.success(sentenceBoxes))
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // 한국어/영어/일본어 등 필요에 맞게
        request.recognitionLanguages = ["ko-KR", "en-US", "ja-JP"]
        request.minimumTextHeight = 0.015 // 글자 너무 작으면 조정

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage,
                                                orientation: image.cgImageOrientation,
                                                options: [:])
            do {
                try handler.perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    func extractPlainText(from image: UIImage,
                          completion: @escaping (Result<String, Error>) -> Void) {

        guard let cgImage = image.cgImage else {
            RVLogger.d("extractPlainText error: cgImage missing")
            completion(.failure(ExtractError.cgImageMissing))
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                RVLogger.d("extractPlainText Vision error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            if observations.isEmpty {
                RVLogger.d("extractPlainText error: no observations")
                completion(.failure(ExtractError.noText))
                return
            }

            var lines: [(text: String, bbox: CGRect)] = []
            lines.reserveCapacity(observations.count)

            for obs in observations {
                guard let top = obs.topCandidates(1).first else { continue }
                let text = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                lines.append((text, obs.boundingBox))
            }

            if lines.isEmpty {
                RVLogger.d("extractPlainText error: lines empty after filtering")
                completion(.failure(ExtractError.noText))
                return
            }

            // Vision 좌표계 정렬 (위 → 아래, 좌 → 우)
            lines.sort { a, b in
                let aY = a.bbox.maxY
                let bY = b.bbox.maxY
                if abs(aY - bY) > 0.02 {
                    return aY > bY
                } else {
                    return a.bbox.minX < b.bbox.minX
                }
            }

            let text = lines.map { $0.text }.joined(separator: "\n")

            completion(.success(text))
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ko-KR", "en-US", "ja-JP"]
        request.minimumTextHeight = 0.015

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: image.cgImageOrientation,
                options: [:]
            )

            do {
                try handler.perform([request])
            } catch {
                RVLogger.d("extractPlainText handler.perform error: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
}

// UIImageOrientation -> CGImagePropertyOrientation 변환
private extension UIImage {
    var cgImageOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
