#!/usr/bin/xcrun swift

import Darwin
import Foundation

private struct Options {
    var objectsDirectory: URL?
    var sourcePrefix: String?
    var requiresCompleteExtraction = false
}

private enum AuditError: Error, CustomStringConvertible {
    case usage(String)
    case unreadable(String)

    var description: String {
        switch self {
        case .usage(let message),
             .unreadable(let message):
            return message
        }
    }
}

private struct StringCatalog: Decodable {
    struct Entry: Decodable {
        struct Localization: Decodable {
            struct StringUnit: Decodable {
                let state: String
                let value: String
            }

            let stringUnit: StringUnit?
        }

        let localizations:
            [String: Localization]?
    }

    let sourceLanguage: String
    let strings: [String: Entry]
}

private func parseOptions() throws -> Options {
    var options = Options()
    var index = 1
    let arguments = CommandLine.arguments
    while index < arguments.count {
        switch arguments[index] {
        case "--objects-dir":
            guard index + 1 < arguments.count else {
                throw AuditError.usage(
                    "--objects-dir requires a path"
                )
            }
            options.objectsDirectory =
                URL(
                    fileURLWithPath:
                        arguments[index + 1]
                )
            index += 2
        case "--source-prefix":
            guard index + 1 < arguments.count else {
                throw AuditError.usage(
                    "--source-prefix requires a path"
                )
            }
            options.sourcePrefix =
                arguments[index + 1]
                .trimmingCharacters(
                    in: CharacterSet(
                        charactersIn: "/"
                    )
                )
            index += 2
        case "--require-complete":
            options.requiresCompleteExtraction =
                true
            index += 1
        case "--help", "-h":
            printUsage()
            exit(EXIT_SUCCESS)
        default:
            throw AuditError.usage(
                "unknown argument: \(arguments[index])"
            )
        }
    }
    return options
}

private func printUsage() {
    print(
        """
        Usage:
          xcrun swift Tools/Localization/audit_localizations.swift \
            [--objects-dir PATH] [--source-prefix PATH] [--require-complete]

        Always checks that the English and Japanese Localizable.strings files
        have identical keys and compatible printf placeholders. It also checks
        the AppShortcuts string catalog and scans AppLocalization.string/format
        calls with literal keys in Swift source.

        When --objects-dir points to Xcode's Objects-normal directory, the
        script also reads every .stringsdata file and reports compiler-extracted
        Localizable keys missing from either bundle and AppShortcuts groups
        missing from the catalog. Use --source-prefix to limit that check, for
        example: shortcuts_example/Reader.
        """
    )
}

private func repositoryRoot() -> URL {
    URL(
        fileURLWithPath: #filePath
    )
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}

private func loadStrings(
    at url: URL
) throws -> [String: String] {
    let data = try Data(
        contentsOf: url
    )
    let propertyList =
        try PropertyListSerialization
        .propertyList(
            from: data,
            options: [],
            format: nil
        )
    guard let strings =
            propertyList
                as? [String: String] else {
        throw AuditError.unreadable(
            "\(url.path) is not a string dictionary"
        )
    }
    return strings
}

private func loadStringCatalog(
    at url: URL
) throws -> StringCatalog {
    let data = try Data(
        contentsOf: url
    )
    do {
        return try JSONDecoder()
            .decode(
                StringCatalog.self,
                from: data
            )
    } catch {
        throw AuditError.unreadable(
            "\(url.path) is not a valid string catalog: \(error)"
        )
    }
}

private func localizedCatalogValues(
    _ catalog: StringCatalog,
    language: String
) -> [String: String] {
    catalog.strings
        .reduce(
            into: [String: String]()
        ) { result, item in
            guard let unit =
                    item.value
                    .localizations?[language]?
                    .stringUnit,
                  unit.state == "translated",
                  !unit.value.isEmpty else {
                return
            }
            result[item.key] =
                unit.value
        }
}

private func placeholderSignature(
    in value: String
) -> [String] {
    let pattern =
        #"%(?:\d+\$)?[-+ #0']*\d*(?:\.\d+)?(hh|h|ll|l|q|L|z|t|j)?([@diuoxXfFeEgGaAcCsSp])"#
    guard let expression =
            try? NSRegularExpression(
                pattern: pattern
            ) else {
        return []
    }
    let range = NSRange(
        location: 0,
        length:
            (value as NSString)
            .length
    )
    return expression.matches(
        in: value,
        range: range
    ).compactMap { match in
        guard let conversionRange =
                Range(
                    match.range(at: 2),
                    in: value
                ) else {
            return nil
        }
        let length: String
        if let lengthRange =
                Range(
                    match.range(at: 1),
                    in: value
                ) {
            length =
                String(value[lengthRange])
        } else {
            length = ""
        }
        return length
            + String(
                value[conversionRange]
            )
    }
    .sorted()
}

private func catalogTokenSignature(
    in value: String
) -> [String] {
    let pattern = #"\$\{[^}]+\}"#
    guard let expression =
            try? NSRegularExpression(
                pattern: pattern
            ) else {
        return []
    }
    let range = NSRange(
        location: 0,
        length:
            (value as NSString)
            .length
    )
    return expression.matches(
        in: value,
        range: range
    ).compactMap { match in
        guard let tokenRange =
                Range(
                    match.range,
                    in: value
                ) else {
            return nil
        }
        return String(
            value[tokenRange]
        )
    }
    .sorted()
}

private func extractedKeys(
    in directory: URL,
    sourcePrefix: String?,
    table: String
) throws -> Set<String> {
    guard let enumerator =
            FileManager.default
                .enumerator(
                    at: directory,
                    includingPropertiesForKeys:
                        [.isRegularFileKey],
                    options:
                        [.skipsHiddenFiles]
                ) else {
        throw AuditError.unreadable(
            "cannot enumerate \(directory.path)"
        )
    }
    var result: Set<String> = []
    for case let url as URL in enumerator {
        guard url.pathExtension
                == "stringsdata" else {
            continue
        }
        let data = try Data(
            contentsOf: url
        )
        guard let root =
                try JSONSerialization
                .jsonObject(with: data)
                as? [String: Any] else {
            continue
        }
        if let sourcePrefix,
           let source =
                root["source"] as? String {
            let normalized =
                source.replacingOccurrences(
                    of: "\\",
                    with: "/"
                )
            guard normalized.contains(
                "/\(sourcePrefix)/"
            )
                || normalized.hasSuffix(
                    "/\(sourcePrefix)"
                ) else {
                continue
            }
        }
        guard let tables =
                root["tables"]
                    as? [String: Any],
              let entries =
                tables[table]
                    as? [[String: Any]] else {
            continue
        }
        for entry in entries {
            if let key =
                    entry["key"]
                        as? String,
               !key.isEmpty {
                result.insert(key)
            }
        }
    }
    return result
}

private func appLocalizationLiteralKeys(
    in root: URL,
    sourcePrefix: String?
) throws -> Set<String> {
    let sourceRoot: URL
    if let sourcePrefix {
        sourceRoot =
            root.appendingPathComponent(
                sourcePrefix,
                isDirectory: true
            )
    } else {
        sourceRoot =
            root.appendingPathComponent(
                "shortcuts_example",
                isDirectory: true
            )
    }
    guard let enumerator =
            FileManager.default
                .enumerator(
                    at: sourceRoot,
                    includingPropertiesForKeys:
                        [.isRegularFileKey],
                    options:
                        [.skipsHiddenFiles]
                ) else {
        throw AuditError.unreadable(
            "cannot enumerate \(sourceRoot.path)"
        )
    }
    let expression =
        try NSRegularExpression(
            pattern:
                #"AppLocalization\s*\.\s*(?:string|format)\s*\(\s*"((?:\\.|[^"\\])*)""#
        )
    var result: Set<String> = []
    for case let url as URL in enumerator {
        guard url.pathExtension == "swift"
        else {
            continue
        }
        let source = try String(
            contentsOf: url,
            encoding: .utf8
        )
        let range = NSRange(
            location: 0,
            length:
                (source as NSString)
                .length
        )
        for match in expression.matches(
            in: source,
            range: range
        ) {
            guard let literalRange =
                    Range(
                        match.range(at: 1),
                        in: source
                    ) else {
                continue
            }
            let escaped =
                String(
                    source[literalRange]
                )
            let json =
                "\"\(escaped)\""
            guard let data =
                    json.data(
                        using: .utf8
                    ),
                  let key =
                    try JSONSerialization
                    .jsonObject(
                        with: data,
                        options:
                            .fragmentsAllowed
                    )
                        as? String else {
                throw AuditError.unreadable(
                    "cannot decode localization key in \(url.path)"
                )
            }
            result.insert(key)
        }
    }
    return result
}

private func printItems(
    _ title: String,
    _ items: [String]
) {
    guard !items.isEmpty else {
        return
    }
    print("\n\(title) (\(items.count))")
    for item in items {
        print("  \(item)")
    }
}

do {
    let options = try parseOptions()
    let root = repositoryRoot()
    let english = try loadStrings(
        at:
            root.appendingPathComponent(
                "shortcuts_example/en.lproj/Localizable.strings"
            )
    )
    let japanese = try loadStrings(
        at:
            root.appendingPathComponent(
                "shortcuts_example/ja.lproj/Localizable.strings"
            )
    )
    let shortcutCatalog =
        try loadStringCatalog(
            at:
                root.appendingPathComponent(
                    "shortcuts_example/AppShortcuts.xcstrings"
                )
        )
    guard shortcutCatalog.sourceLanguage
            == "ko" else {
        throw AuditError.unreadable(
            "AppShortcuts.xcstrings sourceLanguage must be ko"
        )
    }
    let shortcutEnglish =
        localizedCatalogValues(
            shortcutCatalog,
            language: "en"
        )
    let shortcutJapanese =
        localizedCatalogValues(
            shortcutCatalog,
            language: "ja"
        )
    let englishKeys = Set(
        english.keys
    )
    let japaneseKeys = Set(
        japanese.keys
    )
    let missingEnglish =
        japaneseKeys
        .subtracting(englishKeys)
        .sorted()
    let missingJapanese =
        englishKeys
        .subtracting(japaneseKeys)
        .sorted()
    var formatMismatches: [String] =
        []
    for key in englishKeys
        .intersection(japaneseKeys)
        .sorted() {
        let sourceSignature =
            placeholderSignature(in: key)
        let englishSignature =
            placeholderSignature(
                in: english[key] ?? ""
            )
        let japaneseSignature =
            placeholderSignature(
                in: japanese[key] ?? ""
            )
        if englishSignature
            != japaneseSignature
            || (
                !sourceSignature.isEmpty
                && sourceSignature
                    != englishSignature
            ) {
            formatMismatches.append(
                "\(key) | source \(sourceSignature) | en \(englishSignature) | ja \(japaneseSignature)"
            )
        }
    }

    print(
        "Bundle keys: en \(english.count), ja \(japanese.count)"
    )
    printItems(
        "Missing from English",
        missingEnglish
    )
    printItems(
        "Missing from Japanese",
        missingJapanese
    )
    printItems(
        "Placeholder mismatches",
        formatMismatches
    )

    let shortcutKeys = Set(
        shortcutCatalog.strings.keys
    )
    let shortcutEnglishKeys = Set(
        shortcutEnglish.keys
    )
    let shortcutJapaneseKeys = Set(
        shortcutJapanese.keys
    )
    let shortcutMissingEnglish =
        shortcutKeys
        .subtracting(
            shortcutEnglishKeys
        )
        .sorted()
    let shortcutMissingJapanese =
        shortcutKeys
        .subtracting(
            shortcutJapaneseKeys
        )
        .sorted()
    var shortcutTokenMismatches:
        [String] = []
    for key in shortcutKeys.sorted() {
        let sourceSignature =
            catalogTokenSignature(
                in: key
            )
        let englishSignature =
            catalogTokenSignature(
                in:
                    shortcutEnglish[key]
                    ?? ""
            )
        let japaneseSignature =
            catalogTokenSignature(
                in:
                    shortcutJapanese[key]
                    ?? ""
            )
        if sourceSignature
            != englishSignature
            || sourceSignature
                != japaneseSignature {
            shortcutTokenMismatches
                .append(
                    "\(key) | source \(sourceSignature) | en \(englishSignature) | ja \(japaneseSignature)"
                )
        }
    }
    print(
        "App Shortcut catalog keys: \(shortcutKeys.count)"
    )
    printItems(
        "App Shortcut keys missing from English",
        shortcutMissingEnglish
    )
    printItems(
        "App Shortcut keys missing from Japanese",
        shortcutMissingJapanese
    )
    printItems(
        "App Shortcut token mismatches",
        shortcutTokenMismatches
    )

    let literalKeys =
        try appLocalizationLiteralKeys(
            in: root,
            sourcePrefix:
                options.sourcePrefix
        )
    let literalMissingEnglish =
        literalKeys.subtracting(
            englishKeys
        ).sorted()
    let literalMissingJapanese =
        literalKeys.subtracting(
            japaneseKeys
        ).sorted()
    print(
        "AppLocalization literal keys: \(literalKeys.count)"
    )
    printItems(
        "Literal keys missing from English",
        literalMissingEnglish
    )
    printItems(
        "Literal keys missing from Japanese",
        literalMissingJapanese
    )

    var extractionFailures = false
    if let objectsDirectory =
            options.objectsDirectory {
        let keys = try extractedKeys(
            in: objectsDirectory,
            sourcePrefix:
                options.sourcePrefix,
            table: "Localizable"
        )
        let extractedMissingEnglish =
            keys.subtracting(
                englishKeys
            ).sorted()
        let extractedMissingJapanese =
            keys.subtracting(
                japaneseKeys
            ).sorted()
        print(
            "Compiler-extracted keys: \(keys.count)"
        )
        printItems(
            "Extracted keys missing from English",
            extractedMissingEnglish
        )
        printItems(
            "Extracted keys missing from Japanese",
            extractedMissingJapanese
        )
        extractionFailures =
            options
            .requiresCompleteExtraction
            && (
                !extractedMissingEnglish
                    .isEmpty
                || !extractedMissingJapanese
                    .isEmpty
            )
        let extractedShortcutKeys =
            try extractedKeys(
                in: objectsDirectory,
                sourcePrefix:
                    options.sourcePrefix,
                table: "AppShortcuts"
            )
        let missingShortcutCatalogKeys =
            extractedShortcutKeys
            .subtracting(
                shortcutKeys
            )
            .sorted()
        print(
            "Compiler-extracted App Shortcut groups: \(extractedShortcutKeys.count)"
        )
        printItems(
            "Extracted App Shortcut groups missing from catalog",
            missingShortcutCatalogKeys
        )
        extractionFailures =
            extractionFailures
            || (
                options
                .requiresCompleteExtraction
                && !missingShortcutCatalogKeys
                    .isEmpty
            )
    }

    let failed =
        !missingEnglish.isEmpty
        || !missingJapanese.isEmpty
        || !formatMismatches.isEmpty
        || !shortcutMissingEnglish.isEmpty
        || !shortcutMissingJapanese.isEmpty
        || !shortcutTokenMismatches.isEmpty
        || (
            options
                .requiresCompleteExtraction
            && (
                !literalMissingEnglish
                    .isEmpty
                || !literalMissingJapanese
                    .isEmpty
            )
        )
        || extractionFailures
    if failed {
        exit(EXIT_FAILURE)
    }
    print("Localization audit passed.")
} catch {
    fputs(
        "Localization audit failed: \(error)\n",
        stderr
    )
    printUsage()
    exit(EXIT_FAILURE)
}
