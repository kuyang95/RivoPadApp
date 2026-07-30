import Foundation

nonisolated enum AppDeepLinkDestination:
    String,
    CaseIterable,
    Equatable,
    Sendable
{
    case ai
    case reader
    case camera
    case scanner
    case rivo
    case visionLink = "vision-link"
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
