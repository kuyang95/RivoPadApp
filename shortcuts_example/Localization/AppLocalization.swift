import Foundation

nonisolated enum AppLocalization {
    static func string(
        _ key: String,
        bundle: Bundle = .main
    ) -> String {
        bundle.localizedString(
            forKey: key,
            value: key,
            table: nil
        )
    }

    static func format(
        _ key: String,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: string(key),
            locale: Locale.current,
            arguments: arguments
        )
    }
}
