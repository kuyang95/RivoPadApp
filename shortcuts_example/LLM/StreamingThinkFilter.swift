import Foundation

nonisolated struct StreamingThinkFilter: Sendable {
    private static let openingTag = "<think>"
    private static let closingTag = "</think>"

    private var buffer = ""
    private var isInsideThink = false

    mutating func consume(_ chunk: String) -> String {
        buffer += chunk
        var visibleText = ""

        while true {
            if isInsideThink {
                if let closingRange = buffer.range(of: Self.closingTag) {
                    buffer = String(buffer[closingRange.upperBound...])
                    isInsideThink = false
                    continue
                }

                retainPossibleTagPrefix(Self.closingTag)
                return visibleText
            }

            if let openingRange = buffer.range(of: Self.openingTag) {
                visibleText += String(buffer[..<openingRange.lowerBound])
                buffer = String(buffer[openingRange.upperBound...])
                isInsideThink = true
                continue
            }

            let retainedCount = possibleTagPrefixLength(Self.openingTag)
            let visibleEnd = buffer.index(
                buffer.endIndex,
                offsetBy: -retainedCount
            )
            visibleText += String(buffer[..<visibleEnd])
            buffer = String(buffer[visibleEnd...])
            return visibleText
        }
    }

    mutating func finish() -> String {
        defer {
            buffer = ""
            isInsideThink = false
        }
        return isInsideThink ? "" : buffer
    }

    private mutating func retainPossibleTagPrefix(_ tag: String) {
        let retainedCount = possibleTagPrefixLength(tag)
        guard retainedCount > 0 else {
            buffer = ""
            return
        }
        buffer = String(buffer.suffix(retainedCount))
    }

    private func possibleTagPrefixLength(_ tag: String) -> Int {
        let maximumLength = min(buffer.count, tag.count - 1)
        guard maximumLength > 0 else {
            return 0
        }

        for length in stride(from: maximumLength, through: 1, by: -1) {
            if buffer.hasSuffix(tag.prefix(length)) {
                return length
            }
        }
        return 0
    }
}
