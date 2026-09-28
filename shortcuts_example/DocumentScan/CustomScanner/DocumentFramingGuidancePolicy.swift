import Foundation

/// Android's partial-page fallback for frames where LCNet cannot find all four
/// corners. Coordinates stay in the raw viewport until the camera adapter
/// rotates the resulting direction into the displayed preview.
nonisolated enum PartialDocumentFramingGuidance {
    static func evaluate(_ image: ScannerRGBAImage) -> DocumentFramingGuidance? {
        let width = 64
        let height = 96
        let sample = AndroidScannerImageMath.resizeBilinear(
            image, width: width, height: height
        )
        let pixelCount = width * height
        let mask = (0 ..< pixelCount).map { index in
            let offset = index * 4
            let red = Int(sample.bytes[offset])
            let green = Int(sample.bytes[offset + 1])
            let blue = Int(sample.bytes[offset + 2])
            let luminance = (red * 299 + green * 587 + blue * 114) / 1_000
            return luminance >= 155
                && max(red, green, blue) - min(red, green, blue) <= 85
        }
        var visited = [Bool](repeating: false, count: pixelCount)
        var queue = [Int](repeating: 0, count: pixelCount)
        var bestArea = 0
        var bestEdgeScores = [Int](repeating: 0, count: 4)

        for start in 0 ..< pixelCount where mask[start] && !visited[start] {
            var head = 0
            var tail = 1
            queue[0] = start
            visited[start] = true
            var minX = width
            var maxX = -1
            var minY = height
            var maxY = -1
            var edgeScores = [Int](repeating: 0, count: 4)

            while head < tail {
                let index = queue[head]
                head += 1
                let x = index % width
                let y = index / width
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
                if x < 3 { edgeScores[0] += 1 }
                if x >= width - 3 { edgeScores[1] += 1 }
                if y < 4 { edgeScores[2] += 1 }
                if y >= height - 4 { edgeScores[3] += 1 }

                let neighbors = [
                    x > 0 ? index - 1 : -1,
                    x < width - 1 ? index + 1 : -1,
                    y > 0 ? index - width : -1,
                    y < height - 1 ? index + width : -1,
                ]
                for next in neighbors where next >= 0 && mask[next] && !visited[next] {
                    visited[next] = true
                    queue[tail] = next
                    tail += 1
                }
            }

            let looksLikePage = tail >= Int(Double(pixelCount) * 0.025)
                && Double(maxX - minX + 1) >= Double(width) * 0.08
                && Double(maxY - minY + 1) >= Double(height) * 0.20
            if looksLikePage && tail > bestArea {
                bestArea = tail
                bestEdgeScores = edgeScores
            }
        }

        let directions: [DocumentFramingGuidance] = [
            .moveLeft, .moveRight, .moveUp, .moveDown,
        ]
        var strongestIndex = 0
        for index in 1 ..< directions.count {
            // Keep Android's first direction when edge scores are tied.
            if bestEdgeScores[index] > bestEdgeScores[strongestIndex] {
                strongestIndex = index
            }
        }
        return bestEdgeScores[strongestIndex] > 0
            ? directions[strongestIndex] : nil
    }
}

/// First instruction is immediate, changed directions must persist for one
/// second, and unchanged instructions repeat at most once every six seconds.
/// Camera frames drive the clock so an interrupted camera cannot speak a
/// delayed instruction from a stale frame.
nonisolated struct DocumentGuidanceSpeechPolicy {
    enum Effect: Equatable {
        case stop
        case speak(DocumentFramingGuidance)
    }

    private(set) var currentGuidance: DocumentFramingGuidance?
    private var lastSpokenAt: TimeInterval?
    private var pendingSince: TimeInterval?

    mutating func update(
        _ guidance: DocumentFramingGuidance?,
        at now: TimeInterval,
        isSpeaking: Bool
    ) -> [Effect] {
        guard let guidance else {
            let hadGuidance = currentGuidance != nil
            self = Self()
            return hadGuidance ? [.stop] : []
        }

        if guidance != currentGuidance {
            let hadGuidance = currentGuidance != nil
            currentGuidance = guidance
            if hadGuidance {
                pendingSince = now
                return [.stop]
            }
            lastSpokenAt = now
            return [.speak(guidance)]
        }

        if let pendingSince {
            guard now - pendingSince >= 1 else { return [] }
            self.pendingSince = nil
            lastSpokenAt = now
            return [.speak(guidance)]
        }

        guard !isSpeaking, now - (lastSpokenAt ?? now) >= 6 else { return [] }
        lastSpokenAt = now
        return [.speak(guidance)]
    }
}
