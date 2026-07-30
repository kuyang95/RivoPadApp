import AppIntents
import Foundation

nonisolated enum AppDeepLinkDestination:
    String,
    CaseIterable,
    Hashable,
    Sendable,
    AppEnum
{
    case settings
    case ai
    case reader
    case camera
    case magnifier
    case liveText = "live-text"
    case scanner
    case files
    case rivo
    case visionLink = "vision-link"

    static var typeDisplayRepresentation:
        TypeDisplayRepresentation {
        "VisionCraft 화면"
    }

    static var caseDisplayRepresentations:
        [AppDeepLinkDestination:
            DisplayRepresentation] {
        [
            .settings: "설정",
            .ai: "AI 채팅",
            .reader: "독서",
            .camera: "카메라",
            .magnifier: "돋보기",
            .liveText: "실시간 글자 읽기",
            .scanner: "문서 스캔",
            .files: "파일 열기",
            .rivo: "Rivo 리모컨",
            .visionLink: "VisionLink"
        ]
    }
}

nonisolated enum AppDeepLinkRouter {
    static func destination(
        for url: URL
    ) -> AppDeepLinkDestination? {
        guard url.scheme?
                .lowercased() == "rivopad",
              url.host?
                .lowercased() == "open" else {
            return nil
        }
        let components = url.pathComponents
            .filter { $0 != "/" }
        guard components.count == 1 else {
            return nil
        }
        return AppDeepLinkDestination(
            rawValue: components[0].lowercased()
        )
    }
}
