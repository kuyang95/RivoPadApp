import Foundation

public nonisolated enum HWPInlineTextInput {
    public static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
    }

    public static func accepts(_ value: String, replacing range: NSRange, in text: String) -> Bool {
        let count = text.utf16.count
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location <= count, range.length <= count - range.location,
              count - range.length + value.utf16.count <= 100_000 else { return false }
        return value.unicodeScalars.allSatisfy {
            $0.value >= 32 || $0.value == 9 || $0.value == 10
        }
    }
}
