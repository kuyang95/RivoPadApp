import Foundation

nonisolated enum AppLocalization {
    static func string(
        _ key: String,
        bundle: Bundle = .main,
        language: AppLanguage? = nil
    ) -> String {
        localizedBundle(
            from: bundle,
            language:
                language
                ?? AppLanguage.current()
        )
        .localizedString(
            forKey: key,
            value: key,
            table: nil
        )
    }

    static func format(
        _ key: String,
        _ arguments: CVarArg...
    ) -> String {
        let language =
            AppLanguage.current()
        return String(
            format: string(
                key,
                language: language
            ),
            locale: language.locale,
            arguments: arguments
        )
    }

    private static func localizedBundle(
        from bundle: Bundle,
        language: AppLanguage
    ) -> Bundle {
        guard let code =
                language.localizationCode,
              let path = bundle.path(
                  forResource: code,
                  ofType: "lproj"
              ),
              let localized =
                Bundle(path: path) else {
            return bundle
        }
        return localized
    }
}
