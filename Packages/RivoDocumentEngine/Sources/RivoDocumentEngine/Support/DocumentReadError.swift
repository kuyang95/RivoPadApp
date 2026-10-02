import Foundation

public nonisolated enum ChatAttachmentError:
    Error,
    LocalizedError,
    Equatable,
    Sendable
{
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

    public var errorDescription: String? {
        switch self {
        case .clipboardEmpty:
            return DocumentEngineLocalization.string(
                "클립보드에 첨부할 텍스트가 없습니다."
            )
        case .unsupportedDocument:
            return DocumentEngineLocalization.string(
                "PDF, TXT, XLSX, XLS, HWP와 HWPX 문서만 첨부할 수 있습니다."
            )
        case .invalidImage:
            return DocumentEngineLocalization.string(
                "선택한 사진을 읽을 수 없습니다."
            )
        case .invalidPDF:
            return DocumentEngineLocalization.string(
                "선택한 PDF를 열 수 없습니다."
            )
        case .invalidSpreadsheet:
            return DocumentEngineLocalization.string(
                "선택한 XLSX 문서를 읽을 수 없습니다."
            )
        case .encryptedSpreadsheet:
            return DocumentEngineLocalization.string(
                "암호화된 XLSX 문서는 로컬에서 열 수 없습니다. 암호를 해제한 복사본을 첨부해 주세요."
            )
        case .spreadsheetLimitExceeded:
            return DocumentEngineLocalization.string(
                "XLSX 문서가 시트·행·셀 또는 압축 해제 제한을 초과했습니다."
            )
        case .unsupportedLegacySpreadsheet:
            return DocumentEngineLocalization.string(
                "이 XLS 문서의 구형 BIFF 버전은 지원하지 않습니다. Excel 97-2003 XLS 또는 XLSX로 다시 저장해 주세요."
            )
        case .invalidHWP:
            return DocumentEngineLocalization.string(
                "선택한 HWP 5.x 문서를 읽을 수 없습니다."
            )
        case .encryptedHWP:
            return DocumentEngineLocalization.string(
                "암호·배포용·DRM 보안 HWP 문서는 로컬에서 열 수 없습니다. 보호를 해제한 복사본을 첨부해 주세요."
            )
        case .hwpLimitExceeded:
            return DocumentEngineLocalization.string(
                "HWP 문서가 구역 수 또는 압축 해제 제한을 초과했습니다."
            )
        case .unsupportedHWPVersion:
            return DocumentEngineLocalization.string(
                "이 구형 HWP 문서는 지원하지 않습니다. HWP 5.x 또는 HWPX로 다시 저장해 주세요."
            )
        case .invalidHWPX:
            return DocumentEngineLocalization.string(
                "선택한 HWPX 문서를 읽을 수 없습니다."
            )
        case .hwpxLimitExceeded:
            return DocumentEngineLocalization.string(
                "HWPX 문서가 구역 수 또는 압축 해제 제한을 초과했습니다."
            )
        case .documentHasNoText:
            return DocumentEngineLocalization.string(
                "문서에서 질문에 사용할 텍스트를 찾지 못했습니다."
            )
        case .fileTooLarge(
            let maximumMegabytes
        ):
            return DocumentEngineLocalization.format(
                "첨부 파일은 %lldMB 이하만 지원합니다.",
                maximumMegabytes
            )
        case .contextTooLarge(
            let maximumKilobytes
        ):
            return DocumentEngineLocalization.format(
                "대화에 첨부할 텍스트는 모두 합쳐 %lldKB 이하여야 합니다.",
                maximumKilobytes
            )
        case .storedFileMissing:
            return DocumentEngineLocalization.string(
                "저장된 첨부 원본을 찾을 수 없어 첨부 없이 대화를 엽니다."
            )
        }
    }
}
