import Foundation

nonisolated struct HelpManualDocument:
    Equatable,
    Sendable
{
    let title: String
    let version: String
    let date: String
    let chapters: [HelpManualChapter]
}

nonisolated struct HelpManualChapter:
    Equatable,
    Identifiable,
    Sendable
{
    let id: String
    let name: String
    let sections: [HelpManualSection]
}

nonisolated struct HelpManualSection:
    Equatable,
    Identifiable,
    Sendable
{
    let id: String
    let name: String
    let texts: [String]
    let subsections: [HelpManualSubsection]

    var searchableText: String {
        (
            [name]
                + texts
                + subsections.flatMap {
                    [$0.name] + $0.texts
                }
        )
        .joined(separator: "\n")
    }
}

nonisolated struct HelpManualSubsection:
    Equatable,
    Identifiable,
    Sendable
{
    let id: String
    let name: String
    let texts: [String]
}

nonisolated struct HelpReleaseNote:
    Equatable,
    Identifiable,
    Sendable
{
    var id: String {
        version + "-" + date
    }

    let version: String
    let date: String
    let texts: [String]
}

nonisolated enum HelpDocumentError:
    Error,
    Equatable,
    LocalizedError
{
    case missingResource(String)
    case missingValue(String)
    case misplacedDirective(String)
    case emptyDocument

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            return AppLocalization.format(
                "%@ 도움말 파일을 찾지 못했습니다.",
                name
            )
        case .missingValue(let directive):
            return AppLocalization.format(
                "%@ 항목의 내용이 비어 있습니다.",
                directive
            )
        case .misplacedDirective(let directive):
            return AppLocalization.format(
                "%@ 항목의 위치가 올바르지 않습니다.",
                directive
            )
        case .emptyDocument:
            return AppLocalization.string(
                "도움말 내용이 비어 있습니다."
            )
        }
    }
}

nonisolated enum HelpDocumentParser {
    private enum LastField {
        case title
        case version
        case date
        case chapter
        case section
        case subsection
        case text
    }

    static func parseManual(
        _ source: String
    ) throws -> HelpManualDocument {
        var title = ""
        var version = ""
        var date = ""
        var chapters: [HelpManualChapter] = []

        var chapterName: String?
        var sections: [HelpManualSection] = []
        var sectionName: String?
        var sectionTexts: [String] = []
        var subsections:
            [HelpManualSubsection] = []
        var subsectionName: String?
        var subsectionTexts: [String] = []
        var lastField: LastField?

        func finishSubsection() {
            guard let name = subsectionName else {
                return
            }
            let id =
                "chapter-\(chapters.count)"
                + ".section-\(sections.count)"
                + ".subsection-\(subsections.count)"
            subsections.append(
                HelpManualSubsection(
                    id: id,
                    name: name,
                    texts: subsectionTexts
                )
            )
            subsectionName = nil
            subsectionTexts = []
        }

        func finishSection() {
            finishSubsection()
            guard let name = sectionName else {
                return
            }
            let id =
                "chapter-\(chapters.count)"
                + ".section-\(sections.count)"
            sections.append(
                HelpManualSection(
                    id: id,
                    name: name,
                    texts: sectionTexts,
                    subsections: subsections
                )
            )
            sectionName = nil
            sectionTexts = []
            subsections = []
        }

        func finishChapter() {
            finishSection()
            guard let name = chapterName else {
                return
            }
            chapters.append(
                HelpManualChapter(
                    id:
                        "chapter-"
                        + String(chapters.count),
                    name: name,
                    sections: sections
                )
            )
            chapterName = nil
            sections = []
        }

        for rawLine in normalizedLines(source) {
            let line = rawLine.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !line.isEmpty else {
                continue
            }
            guard line.hasPrefix("@") else {
                appendContinuation(
                    line,
                    lastField: lastField,
                    title: &title,
                    version: &version,
                    date: &date,
                    chapterName: &chapterName,
                    sectionName: &sectionName,
                    subsectionName: &subsectionName,
                    sectionTexts: &sectionTexts,
                    subsectionTexts:
                        &subsectionTexts
                )
                continue
            }

            let directive = directiveAndValue(
                from: line
            )
            guard !directive.value.isEmpty else {
                throw HelpDocumentError
                    .missingValue(
                        directive.name
                    )
            }
            switch directive.name {
            case "@title":
                title = directive.value
                lastField = .title
            case "@version":
                version = directive.value
                lastField = .version
            case "@date":
                date = directive.value
                lastField = .date
            case "@chapter":
                finishChapter()
                chapterName = directive.value
                lastField = .chapter
            case "@section":
                guard chapterName != nil else {
                    throw HelpDocumentError
                        .misplacedDirective(
                            directive.name
                        )
                }
                finishSection()
                sectionName = directive.value
                lastField = .section
            case "@subsection":
                guard sectionName != nil else {
                    throw HelpDocumentError
                        .misplacedDirective(
                            directive.name
                        )
                }
                finishSubsection()
                subsectionName = directive.value
                lastField = .subsection
            case "@text":
                guard sectionName != nil else {
                    throw HelpDocumentError
                        .misplacedDirective(
                            directive.name
                        )
                }
                if subsectionName != nil {
                    subsectionTexts.append(
                        directive.value
                    )
                } else {
                    sectionTexts.append(
                        directive.value
                    )
                }
                lastField = .text
            default:
                continue
            }
        }
        finishChapter()

        guard !title.isEmpty,
              !chapters.isEmpty else {
            throw HelpDocumentError.emptyDocument
        }
        return HelpManualDocument(
            title: title,
            version: version,
            date: date,
            chapters: chapters
        )
    }

    static func parseReleaseNotes(
        _ source: String
    ) throws -> [HelpReleaseNote] {
        var result: [HelpReleaseNote] = []
        var version: String?
        var date: String?
        var texts: [String] = []

        func finishNote() {
            guard let version,
                  let date else {
                return
            }
            result.append(
                HelpReleaseNote(
                    version: version,
                    date: date,
                    texts: texts
                )
            )
            texts = []
        }

        for rawLine in normalizedLines(source) {
            let line = rawLine.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard line.hasPrefix("@") else {
                continue
            }
            let directive = directiveAndValue(
                from: line
            )
            switch directive.name {
            case "@version":
                if version != nil,
                   date == nil {
                    throw HelpDocumentError
                        .missingValue("@date")
                }
                finishNote()
                guard !directive.value.isEmpty else {
                    throw HelpDocumentError
                        .missingValue(
                            directive.name
                        )
                }
                version = directive.value
                date = nil
            case "@date":
                guard !directive.value.isEmpty else {
                    throw HelpDocumentError
                        .missingValue(
                            directive.name
                        )
                }
                date = directive.value
            case "@text":
                guard version != nil else {
                    throw HelpDocumentError
                        .misplacedDirective(
                            directive.name
                        )
                }
                guard !directive.value.isEmpty else {
                    throw HelpDocumentError
                        .missingValue(
                            directive.name
                        )
                }
                texts.append(directive.value)
            default:
                continue
            }
        }
        if version != nil,
           date == nil {
            throw HelpDocumentError
                .missingValue("@date")
        }
        finishNote()
        guard !result.isEmpty else {
            throw HelpDocumentError.emptyDocument
        }
        return result
    }

    private static func normalizedLines(
        _ source: String
    ) -> [Substring] {
        source
            .replacingOccurrences(
                of: "\u{FEFF}",
                with: ""
            )
            .split(
                omittingEmptySubsequences: false,
                whereSeparator: \.isNewline
            )
    }

    private static func directiveAndValue(
        from line: String
    ) -> (name: String, value: String) {
        guard let separator =
                line.firstIndex(
                    where: \.isWhitespace
                ) else {
            return (line, "")
        }
        return (
            String(line[..<separator]),
            String(line[separator...])
                .trimmingCharacters(
                    in: .whitespaces
                )
        )
    }

    private static func appendContinuation(
        _ text: String,
        lastField: LastField?,
        title: inout String,
        version: inout String,
        date: inout String,
        chapterName: inout String?,
        sectionName: inout String?,
        subsectionName: inout String?,
        sectionTexts: inout [String],
        subsectionTexts: inout [String]
    ) {
        func joined(
            _ original: String,
            _ addition: String
        ) -> String {
            original.isEmpty
                ? addition
                : original + "\n" + addition
        }
        switch lastField {
        case .title:
            title = joined(title, text)
        case .version:
            version = joined(version, text)
        case .date:
            date = joined(date, text)
        case .chapter:
            chapterName = joined(
                chapterName ?? "",
                text
            )
        case .section:
            sectionName = joined(
                sectionName ?? "",
                text
            )
        case .subsection:
            subsectionName = joined(
                subsectionName ?? "",
                text
            )
        case .text:
            if subsectionName != nil,
               let last = subsectionTexts.indices.last {
                subsectionTexts[last] = joined(
                    subsectionTexts[last],
                    text
                )
            } else if let last =
                        sectionTexts.indices.last {
                sectionTexts[last] = joined(
                    sectionTexts[last],
                    text
                )
            }
        case nil:
            break
        }
    }
}

nonisolated enum HelpContentLibrary {
    static func manual(
        bundle: Bundle = .main,
        language: AppLanguage =
            .current()
    ) throws -> HelpManualDocument {
        try HelpDocumentParser.parseManual(
            resourceText(
                named: "RivoPadManual",
                bundle: bundle,
                language: language
            )
        )
    }

    static func releaseNotes(
        bundle: Bundle = .main,
        language: AppLanguage =
            .current()
    ) throws -> [HelpReleaseNote] {
        try HelpDocumentParser
            .parseReleaseNotes(
                resourceText(
                    named:
                        "RivoPadChangelog",
                    bundle: bundle,
                    language: language
                )
            )
    }

    private static func resourceText(
        named name: String,
        bundle: Bundle,
        language: AppLanguage
    ) throws -> String {
        let localization =
            language
                .effectiveLanguageCode
        let localizedURL =
            bundle.path(
                forResource: localization,
                ofType: "lproj"
            )
            .flatMap(Bundle.init(path:))?
            .url(
                forResource: name,
                withExtension: "txt"
            )
        let fallbackURL = bundle.url(
            forResource: name,
            withExtension: "txt"
        )
        guard let url =
                localizedURL ?? fallbackURL
        else {
            throw HelpDocumentError
                .missingResource(name)
        }
        return try String(
            contentsOf: url,
            encoding: .utf8
        )
    }
}
