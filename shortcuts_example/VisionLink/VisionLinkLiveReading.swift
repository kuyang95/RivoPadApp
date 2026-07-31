import CoreGraphics
import Foundation
import UIKit

nonisolated enum VisionLinkLiveReadingControl {
    static let maximumResultSize =
        16 * 1_024
    static let maximumErrorLength = 500

    static func status(
        sessionID: String,
        state: String
    ) -> Data {
        controlData(
            [
                "type": "live-reading-status",
                "sessionId": sessionID,
                "state": state,
            ]
        )
    }

    static func result(
        sessionID: String,
        sequence: Int,
        text: String
    ) -> Data {
        guard text.utf8.count
                <= maximumResultSize else {
            return error(
                sessionID: sessionID,
                message:
                    AppLocalization.string(
                        "인식한 글이 전송 가능한 크기를 초과했습니다."
                    )
            )
        }
        return controlData(
            [
                "type": "live-reading-result",
                "sessionId": sessionID,
                "sequence": sequence,
                "text": text,
            ]
        )
    }

    static func error(
        sessionID: String,
        message: String
    ) -> Data {
        controlData(
            [
                "type": "live-reading-error",
                "sessionId": sessionID,
                "message": String(
                    message.prefix(
                        maximumErrorLength
                    )
                ),
            ]
        )
    }

    private static func controlData(
        _ object: [String: Any]
    ) -> Data {
        (
            try? JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
            )
        ) ?? Data()
    }
}

nonisolated struct
    VisionLinkLiveReadingTextFilter
{
    private let similarityThreshold: Double
    private let historyLimit: Int
    private var recentTexts: [String] = []

    init(
        similarityThreshold: Double = 0.88,
        historyLimit: Int = 5
    ) {
        self.similarityThreshold =
            similarityThreshold
        self.historyLimit = historyLimit
    }

    mutating func accept(
        _ rawText: String
    ) -> String? {
        let normalized = rawText
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else {
            return nil
        }
        guard !recentTexts.contains(where: {
            isNearDuplicate($0, normalized)
        }) else {
            return nil
        }

        recentTexts.append(normalized)
        if recentTexts.count > historyLimit {
            recentTexts.removeFirst(
                recentTexts.count - historyLimit
            )
        }
        return normalized
    }

    mutating func reset() {
        recentTexts.removeAll(
            keepingCapacity: true
        )
    }

    private func isNearDuplicate(
        _ first: String,
        _ second: String
    ) -> Bool {
        if first == second {
            return true
        }
        let compactFirst = first.filter {
            !$0.isWhitespace
        }
        let compactSecond = second.filter {
            !$0.isWhitespace
        }
        if compactFirst == compactSecond {
            return true
        }
        guard compactFirst.count >= 6,
              compactSecond.count >= 6 else {
            return false
        }

        let firstBigrams = bigrams(
            in: compactFirst
        )
        let secondBigrams = bigrams(
            in: compactSecond
        )
        let overlap = firstBigrams.reduce(
            into: 0
        ) { partialResult, item in
            partialResult += min(
                item.value,
                secondBigrams[item.key] ?? 0
            )
        }
        let total =
            firstBigrams.values.reduce(0, +)
            + secondBigrams.values.reduce(0, +)
        return total > 0
            && (
                2 * Double(overlap)
                    / Double(total)
            ) >= similarityThreshold
    }

    private func bigrams(
        in text: String
    ) -> [String: Int] {
        let characters = Array(text)
        guard characters.count >= 2 else {
            return [:]
        }
        var result: [String: Int] = [:]
        for index in 0..<(characters.count - 1) {
            let bigram = String(
                characters[index...index + 1]
            )
            result[bigram, default: 0] += 1
        }
        return result
    }
}

@MainActor
protocol VisionLinkLiveReadingServing:
    AnyObject
{
    func recognize(
        _ image: CGImage
    ) async throws -> String
}

@MainActor
final class VisionLinkLocalLiveReadingService:
    VisionLinkLiveReadingServing
{
    static let shared =
        VisionLinkLocalLiveReadingService()

    private let ocrService: OCRService

    private init() {
        ocrService = .shared
    }

    func recognize(
        _ image: CGImage
    ) async throws -> String {
        let text = try await ocrService.recognize(
            from: UIImage(cgImage: image)
        )
        return text == "(텍스트 없음)"
            ? ""
            : text
    }
}
