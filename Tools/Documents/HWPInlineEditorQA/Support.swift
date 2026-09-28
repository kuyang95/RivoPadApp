import Foundation
nonisolated enum AppLocalization {
 static func string(_ value: String) -> String { value }
 static func format(_ value: String, _ arguments: CVarArg...) -> String { String(format: value, arguments: arguments) }
}

nonisolated enum ChatAttachmentError: Error {

    case clipboardEmpty
    case unsupportedDocument
    case invalidImage
    case invalidPDF
    case invalidSpreadsheet
    case encryptedSpreadsheet
    case spreadsheetLimitExceeded
    case unsupportedLegacySpreadsheet
    case invalidHWP
    case encryptedHWP
    case hwpLimitExceeded
    case unsupportedHWPVersion
    case invalidHWPX
    case hwpxLimitExceeded
    case documentHasNoText
    case fileTooLarge(maximumMegabytes: Int)
    case contextTooLarge(maximumKilobytes: Int)
    case storedFileMissing

}


