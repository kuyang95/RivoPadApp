import Foundation

nonisolated enum AccessiblePublicationParserError:
    LocalizedError
{
    case unsupportedFormat
    case rootDocumentMissing
    case readableContentMissing

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "지원하는 EPUB 또는 DAISY 책이 아닙니다."
        case .rootDocumentMissing:
            return "DAISY 책의 NCC 또는 OPF 파일을 찾을 수 없습니다."
        case .readableContentMissing:
            return "DAISY 책에서 읽을 본문을 찾지 못했습니다."
        }
    }
}

nonisolated enum AccessiblePublicationParser {
    static func parse(data: Data) throws -> EPUBBook {
        let archive = try EPUBArchive(data: data)
        switch detect(in: archive) {
        case .epub:
            return try EPUBBookParser.parse(
                data: data
            )
        case .daisy202(let nccPath):
            return try parseDaisy202(
                archive: archive,
                nccPath: nccPath
            )
        case .daisy3(let opfPath):
            return try parseDaisy3(
                archive: archive,
                opfPath: opfPath
            )
        case .unknown:
            throw AccessiblePublicationParserError
                .unsupportedFormat
        }
    }

    private enum DetectedFormat {
        case epub
        case daisy202(nccPath: String)
        case daisy3(opfPath: String)
        case unknown
    }

    private static func detect(
        in archive: EPUBArchive
    ) -> DetectedFormat {
        if archive.contains(
            "META-INF/container.xml"
        ) {
            return .epub
        }
        let paths = archive.paths
        for name in [
            "ncc.html", "ncc.htm", "ncc.xhtml",
        ] {
            if let path = paths.first(
                where: {
                    $0.split(separator: "/")
                        .last?
                        .lowercased() == name
                }
            ) {
                return .daisy202(
                    nccPath: path
                )
            }
        }
        let opfPath = paths.first {
            $0.lowercased().hasSuffix(".opf")
        }
        let hasNavigationOrSMIL = paths.contains {
            let path = $0.lowercased()
            return path.hasSuffix(".ncx")
                || path.hasSuffix(".smil")
        }
        if let opfPath,
           hasNavigationOrSMIL {
            return .daisy3(
                opfPath: opfPath
            )
        }
        return .unknown
    }

    private static func parseDaisy202(
        archive: EPUBArchive,
        nccPath: String
    ) throws -> EPUBBook {
        let ncc = parseNCC(
            archive: archive,
            path: nccPath
        )
        let smilPaths = daisy202SMILPaths(
            archive: archive,
            nccPath: nccPath,
            navigation: ncc.navigation
        )
        let overlays =
            EPUBMediaOverlayParser.parseResult(
                archive: archive,
                paths: smilPaths,
                fallbackTextDocumentPath:
                    nccPath
            )
        var documentPaths =
            overlays.referencedTextPaths
        if documentPaths.isEmpty {
            documentPaths = [nccPath]
        }
        let titleByPath =
            documentTitles(
                navigation: ncc.navigation,
                smilPaths: smilPaths,
                overlays: overlays.items
            )
        let chapters = try chapters(
            archive: archive,
            paths: documentPaths,
            titleByPath: titleByPath
        )
        guard !chapters.isEmpty else {
            throw AccessiblePublicationParserError
                .readableContentMissing
        }
        let title = ncc.metadata.title?
            .nonEmptyTrimmed
            ?? chapters.first?.title
            ?? "제목 없는 DAISY 2.02"
        return EPUBBook(
            format: .daisy202,
            identifier:
                ncc.metadata.identifier?
                .nonEmptyTrimmed
                ?? "\(nccPath):\(title)",
            title: title,
            creator:
                ncc.metadata.creator?
                .nonEmptyTrimmed,
            language:
                ncc.metadata.language?
                .nonEmptyTrimmed,
            chapters: chapters,
            mediaOverlayItems:
                overlays.items,
            navigationItems:
                ncc.navigation
        )
    }

    private static func parseDaisy3(
        archive: EPUBArchive,
        opfPath: String
    ) throws -> EPUBBook {
        let packageData = try archive.data(
            at: opfPath
        )
        let packageDelegate =
            DaisyPackageXMLDelegate()
        try parseXML(
            packageData,
            delegate: packageDelegate
        )
        let manifest = packageDelegate
            .manifestItems.reduce(
                into:
                    [String: DaisyManifestItem]()
            ) { result, item in
                guard result[item.id] == nil,
                      let path = try? resolvePath(
                          item.href,
                          relativeTo: opfPath
                      ) else {
                    return
                }
                result[item.id] =
                    DaisyManifestItem(
                        id: item.id,
                        path: path,
                        mediaType:
                            item.mediaType
                    )
            }
        let manifestOrder =
            packageDelegate.manifestItems
            .compactMap { manifest[$0.id] }
        let spineAssets =
            packageDelegate.spineIDs
            .compactMap { manifest[$0] }
        var smilPaths = unique(
            spineAssets.compactMap {
                isSMIL($0) ? $0.path : nil
            }
        )
        if smilPaths.isEmpty {
            smilPaths = unique(
                manifestOrder.compactMap {
                    isSMIL($0)
                        ? $0.path
                        : nil
                }
            )
        }

        let ncxAsset =
            packageDelegate.navigationID
            .flatMap { manifest[$0] }
            ?? manifestOrder.first {
                $0.mediaType.lowercased()
                    == "application/x-dtbncx+xml"
                    || $0.path.lowercased()
                    .hasSuffix(".ncx")
            }
        let navigation: NCXParseResult
        if let ncxAsset,
           archive.contains(ncxAsset.path) {
            navigation = parseNCX(
                archive: archive,
                path: ncxAsset.path
            )
        } else {
            navigation = NCXParseResult(
                navigation: [],
                pageList: []
            )
        }
        let overlays =
            EPUBMediaOverlayParser.parseResult(
                archive: archive,
                paths: smilPaths
            )
        var documentPaths =
            overlays.referencedTextPaths
        if documentPaths.isEmpty {
            documentPaths = unique(
                navigation.navigation
                    .compactMap { item in
                        guard let href =
                                item.href,
                              let path =
                                localPath(
                                    from: href
                                ),
                              !path.lowercased()
                                .hasSuffix(
                                    ".smil"
                                ),
                              archive.contains(
                                  path
                              ) else {
                            return nil
                        }
                        return path
                    }
            )
        }
        let titleByPath =
            documentTitles(
                navigation:
                    navigation.navigation,
                smilPaths: smilPaths,
                overlays: overlays.items
            )
        let chapters = try chapters(
            archive: archive,
            paths: documentPaths,
            titleByPath: titleByPath
        )
        guard !chapters.isEmpty else {
            throw AccessiblePublicationParserError
                .readableContentMissing
        }
        let title = packageDelegate.title?
            .nonEmptyTrimmed
            ?? chapters.first?.title
            ?? "제목 없는 DAISY 3"
        return EPUBBook(
            format: .daisy3,
            identifier:
                packageDelegate.identifier?
                .nonEmptyTrimmed
                ?? "\(opfPath):\(title)",
            title: title,
            creator:
                packageDelegate.creator?
                .nonEmptyTrimmed,
            language:
                packageDelegate.language?
                .nonEmptyTrimmed,
            chapters: chapters,
            mediaOverlayItems:
                overlays.items,
            navigationItems:
                navigation.navigation,
            pageListItems:
                navigation.pageList
        )
    }

    private static func chapters(
        archive: EPUBArchive,
        paths: [String],
        titleByPath: [String: String]
    ) throws -> [EPUBChapter] {
        var result: [EPUBChapter] = []
        for (index, path) in unique(paths)
            .enumerated()
        where archive.contains(path) {
            let data = try archive.data(at: path)
            let extractor = EPUBHTMLTextDelegate()
            let didParse = (
                try? EPUBBookParser.parseXHTML(
                    data,
                    delegate: extractor
                )
            ) != nil
            let extractedText = extractor.text
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            let text = didParse
                ? extractedText
                : fallbackText(
                    try archive.text(at: path)
                )
            guard !text.isEmpty else {
                continue
            }
            let fragmentIndexes = didParse
                ? EPUBBookParser
                    .fragmentSegmentIndexes(
                        text: text,
                        fragmentTexts:
                            extractor.fragmentTexts
                    )
                : [:]
            result.append(
                EPUBChapter(
                    id: "publication-\(index)-\(path)",
                    title:
                        titleByPath[path]
                        ?? extractor.firstHeading
                        ?? "제 \(index + 1)장",
                    href: path,
                    text: text,
                    fragmentSegmentIndexes:
                        fragmentIndexes
                )
            )
        }
        return result
    }

    private static func daisy202SMILPaths(
        archive: EPUBArchive,
        nccPath: String,
        navigation:
            [PublicationNavigationItem]
    ) -> [String] {
        let fromNavigation = unique(
            navigation.compactMap { item in
                guard let href = item.href,
                      let path = localPath(
                          from: href
                      ),
                      path.lowercased()
                        .hasSuffix(".smil"),
                      archive.contains(path) else {
                    return nil
                }
                return path
            }
        )
        if !fromNavigation.isEmpty {
            return fromNavigation
        }

        if let master = archive.paths.first(
            where: {
                $0.split(separator: "/")
                    .last?
                    .lowercased()
                    == "master.smil"
            }
        ) {
            let delegate =
                AttributeReferenceXMLDelegate()
            if let data = try? archive.data(
                at: master
            ),
               (
                   try? parseXML(
                       data,
                       delegate: delegate
                   )
               ) != nil {
                let fromMaster = unique(
                    delegate.references
                        .compactMap {
                            guard let path =
                                    try? resolvePath(
                                        $0,
                                        relativeTo:
                                            master
                                    ),
                                  path.lowercased()
                                    .hasSuffix(
                                        ".smil"
                                    ),
                                  archive.contains(
                                      path
                                  ) else {
                                return nil
                            }
                            return path
                        }
                )
                if !fromMaster.isEmpty {
                    return fromMaster
                }
            }
        }
        return archive.paths.filter {
            $0.lowercased().hasSuffix(".smil")
                && $0.split(separator: "/")
                .last?.lowercased()
                != "master.smil"
        }
    }

    private static func parseNCC(
        archive: EPUBArchive,
        path: String
    ) -> NCCParseResult {
        let delegate = NCCXMLDelegate(
            sourcePath: path
        )
        if let data = try? archive.data(at: path),
           (
               try? EPUBBookParser.parseXHTML(
                   data,
                   delegate: delegate
               )
           ) != nil {
            return delegate.result()
        }
        let text = (
            try? archive.text(at: path)
        ) ?? ""
        return fallbackNCC(
            text: text,
            path: path
        )
    }

    private static func fallbackNCC(
        text: String,
        path: String
    ) -> NCCParseResult {
        var metadata: [String: String] = [:]
        let metaPattern =
            #"<meta\s+[^>]*>"#
        for tag in regexMatches(
            pattern: metaPattern,
            in: text
        ) {
            guard let name = attribute(
                "name",
                in: tag
            ),
            let content = attribute(
                "content",
                in: tag
            ) else {
                continue
            }
            metadata[name] = content
        }
        var navigation:
            [PublicationNavigationItem] = []
        let headingPattern =
            #"<h([1-6])\b[^>]*>(.*?)</h\1>"#
        for (index, match) in regexGroups(
            pattern: headingPattern,
            in: text
        ).enumerated() {
            guard match.count >= 3,
                  let level = Int(match[1]),
                  let href = firstAnchorHref(
                      in: match[2]
                  ) else {
                continue
            }
            let label = fallbackText(match[2])
            guard !label.isEmpty else {
                continue
            }
            navigation.append(
                PublicationNavigationItem(
                    id: "ncc-\(index)",
                    label: label,
                    href: resolveReference(
                        href,
                        relativeTo: path
                    ),
                    depth: max(level - 1, 0),
                    playOrder: nil
                )
            )
        }
        let title = regexGroups(
            pattern:
                #"<title\b[^>]*>(.*?)</title>"#,
            in: text
        ).first?
            .dropFirst()
            .first
            .map(fallbackText)
        return NCCParseResult(
            metadata: PublicationMetadata(
                identifier:
                    firstMetadata(
                        metadata,
                        keys: [
                            "dc:identifier",
                            "identifier",
                        ]
                    ),
                title:
                    firstMetadata(
                        metadata,
                        keys: [
                            "dc:title",
                            "title",
                        ]
                    ) ?? title,
                creator:
                    firstMetadata(
                        metadata,
                        keys: [
                            "dc:creator",
                            "creator",
                        ]
                    ),
                language:
                    firstMetadata(
                        metadata,
                        keys: [
                            "dc:language",
                            "language",
                        ]
                    )
            ),
            navigation: navigation
        )
    }

    private static func parseNCX(
        archive: EPUBArchive,
        path: String
    ) -> NCXParseResult {
        let delegate = NCXXMLDelegate(
            sourcePath: path
        )
        guard let data = try? archive.data(
            at: path
        ),
        (
            try? parseXML(
                data,
                delegate: delegate
            )
        ) != nil else {
            return NCXParseResult(
                navigation: [],
                pageList: []
            )
        }
        return delegate.result()
    }

    private static func documentTitles(
        navigation:
            [PublicationNavigationItem],
        smilPaths: [String],
        overlays: [EPUBMediaOverlayItem]
    ) -> [String: String] {
        var titleBySMIL: [String: String] = [:]
        var direct: [String: String] = [:]
        for item in navigation {
            guard let href = item.href,
                  let path = localPath(
                      from: href
                  ),
                  !item.label.isEmpty else {
                continue
            }
            if path.lowercased()
                .hasSuffix(".smil") {
                if titleBySMIL[path] == nil {
                    titleBySMIL[path] =
                        item.label
                }
            } else if direct[path] == nil {
                direct[path] = item.label
            }
        }
        for smilPath in smilPaths {
            guard let title =
                    titleBySMIL[smilPath] else {
                continue
            }
            for overlay in overlays
            where overlay.smilPath == smilPath
                && direct[
                    overlay.textPath
                ] == nil {
                direct[overlay.textPath] =
                    title
            }
        }
        return direct
    }

    private static func parseXML(
        _ data: Data,
        delegate: XMLParserDelegate
    ) throws {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError
                ?? AccessiblePublicationParserError
                .rootDocumentMissing
        }
    }

    private static func resolvePath(
        _ rawReference: String,
        relativeTo basePath: String
    ) throws -> String {
        let rawPath = rawReference
            .split(
                separator: "#",
                maxSplits: 1,
                omittingEmptySubsequences: false
            ).first.map(String.init) ?? ""
        let path = rawPath.split(
            separator: "?",
            maxSplits: 1
        ).first.map(String.init) ?? rawPath
        if path.isEmpty {
            return try EPUBArchive
                .normalizedPath(basePath)
        }
        let directory = basePath
            .split(separator: "/")
            .dropLast()
            .joined(separator: "/")
        return try EPUBArchive.normalizedPath(
            directory.isEmpty
                ? path
                : "\(directory)/\(path)"
        )
    }

    static func resolveReference(
        _ rawReference: String,
        relativeTo basePath: String
    ) -> String? {
        let trimmed = rawReference
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard !trimmed.isEmpty,
              !trimmed.lowercased()
                .hasPrefix("http:"),
              !trimmed.lowercased()
                .hasPrefix("https:"),
              !trimmed.lowercased()
                .hasPrefix("mailto:"),
              !trimmed.lowercased()
                .hasPrefix("data:") else {
            return nil
        }
        let pieces = trimmed.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard let path = try? resolvePath(
            trimmed,
            relativeTo: basePath
        ) else {
            return nil
        }
        guard pieces.count > 1,
              !pieces[1].isEmpty else {
            return path
        }
        return "\(path)#\(pieces[1])"
    }

    private static func localPath(
        from reference: String
    ) -> String? {
        let value = reference.lowercased()
        guard !value.hasPrefix("http:"),
              !value.hasPrefix("https:"),
              !value.hasPrefix("mailto:"),
              !value.hasPrefix("data:") else {
            return nil
        }
        return reference.split(
            separator: "#",
            maxSplits: 1
        ).first.map(String.init)
    }

    private static func isSMIL(
        _ item: DaisyManifestItem
    ) -> Bool {
        item.mediaType.lowercased()
            == "application/smil+xml"
            || item.mediaType.lowercased()
            == "application/smil"
            || item.path.lowercased()
            .hasSuffix(".smil")
    }

    private static func unique(
        _ values: [String]
    ) -> [String] {
        var seen: Set<String> = []
        return values.filter {
            seen.insert($0).inserted
        }
    }

    private static func fallbackText(
        _ markup: String
    ) -> String {
        markup
            .replacingOccurrences(
                of:
                    #"(?is)<script\b[^>]*>.*?</script>"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of:
                    #"(?is)<style\b[^>]*>.*?</style>"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of:
                    #"(?i)<(?:br|p|div|li|h[1-6]|sent|pagenum)\b[^>]*>"#,
                with: "\n\n",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"<[^>]+>"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "&nbsp;",
                with: " "
            )
            .replacingOccurrences(
                of: "&lt;",
                with: "<"
            )
            .replacingOccurrences(
                of: "&gt;",
                with: ">"
            )
            .replacingOccurrences(
                of: "&amp;",
                with: "&"
            )
            .components(separatedBy: "\n\n")
            .map {
                $0.split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func regexMatches(
        pattern: String,
        in text: String
    ) -> [String] {
        regexGroups(
            pattern: pattern,
            in: text
        ).compactMap(\.first)
    }

    private static func regexGroups(
        pattern: String,
        in text: String
    ) -> [[String]] {
        guard let expression =
                try? NSRegularExpression(
                    pattern: pattern,
                    options: [
                        .caseInsensitive,
                        .dotMatchesLineSeparators,
                    ]
                ) else {
            return []
        }
        let range = NSRange(
            text.startIndex ..< text.endIndex,
            in: text
        )
        return expression.matches(
            in: text,
            range: range
        ).map { match in
            (0 ..< match.numberOfRanges).map {
                guard let range = Range(
                    match.range(at: $0),
                    in: text
                ) else {
                    return ""
                }
                return String(text[range])
            }
        }
    }

    private static func attribute(
        _ name: String,
        in tag: String
    ) -> String? {
        regexGroups(
            pattern:
                #"\b"# + NSRegularExpression
                .escapedPattern(for: name)
                + #"\s*=\s*["']([^"']+)["']"#,
            in: tag
        ).first?
            .dropFirst()
            .first?
            .nonEmptyTrimmed
    }

    private static func firstAnchorHref(
        in markup: String
    ) -> String? {
        guard let tag = regexMatches(
            pattern: #"<a\s+[^>]*>"#,
            in: markup
        ).first else {
            return nil
        }
        return attribute("href", in: tag)
    }

    private static func firstMetadata(
        _ metadata: [String: String],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = metadata.first(
                where: {
                    $0.key.caseInsensitiveCompare(
                        key
                    ) == .orderedSame
                }
            )?.value.nonEmptyTrimmed {
                return value
            }
        }
        return nil
    }
}

private nonisolated struct PublicationMetadata {
    let identifier: String?
    let title: String?
    let creator: String?
    let language: String?
}

private nonisolated struct NCCParseResult {
    let metadata: PublicationMetadata
    let navigation: [PublicationNavigationItem]
}

private nonisolated struct NCXParseResult {
    let navigation: [PublicationNavigationItem]
    let pageList: [PublicationNavigationItem]
}

private nonisolated struct DaisyManifestItem {
    let id: String
    let path: String
    let mediaType: String
}

private nonisolated final class NCCXMLDelegate:
    NSObject,
    XMLParserDelegate
{
    private final class Heading {
        let id: String
        let level: Int
        var label = ""
        var href: String?

        init(id: String, level: Int) {
            self.id = id
            self.level = level
        }
    }

    private let sourcePath: String
    private var title = ""
    private var isInsideTitle = false
    private var heading: Heading?
    private var metadata: [String: String] = [:]
    private var navigation:
        [PublicationNavigationItem] = []
    private var counter = 0

    init(sourcePath: String) {
        self.sourcePath = sourcePath
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict:
            [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        if name == "title" {
            isInsideTitle = true
        }
        if name == "meta",
           let key = attributeDict["name"],
           let value = attributeDict["content"] {
            metadata[key] = value
        }
        if name.count == 2,
           name.first == "h",
           let level = name.last?
            .wholeNumberValue,
           (1 ... 6).contains(level) {
            heading = Heading(
                id:
                    attributeDict["id"]
                    ?? "ncc-\(counter)",
                level: level
            )
            counter += 1
        } else if name == "a",
                  heading != nil {
            heading?.href =
                attributeDict["href"]
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        if isInsideTitle {
            title += string
        }
        heading?.label += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        if name == "title" {
            isInsideTitle = false
        }
        guard name.count == 2,
              name.first == "h",
              let heading else {
            return
        }
        let label = heading.label
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        if !label.isEmpty,
           let href = heading.href,
           let resolved =
            AccessiblePublicationParser
            .resolveReference(
                href,
                relativeTo: sourcePath
            ) {
            navigation.append(
                PublicationNavigationItem(
                    id: heading.id,
                    label: label,
                    href: resolved,
                    depth: max(
                        heading.level - 1,
                        0
                    ),
                    playOrder: nil
                )
            )
        }
        self.heading = nil
    }

    func result() -> NCCParseResult {
        NCCParseResult(
            metadata: PublicationMetadata(
                identifier:
                    metadataValue([
                        "dc:identifier",
                        "identifier",
                    ]),
                title:
                    metadataValue([
                        "dc:title", "title",
                    ])
                    ?? title.nonEmptyTrimmed,
                creator:
                    metadataValue([
                        "dc:creator",
                        "creator",
                    ]),
                language:
                    metadataValue([
                        "dc:language",
                        "language",
                    ])
            ),
            navigation: navigation
        )
    }

    private func metadataValue(
        _ keys: [String]
    ) -> String? {
        for key in keys {
            if let value = metadata.first(
                where: {
                    $0.key.caseInsensitiveCompare(
                        key
                    ) == .orderedSame
                }
            )?.value.nonEmptyTrimmed {
                return value
            }
        }
        return nil
    }
}

private nonisolated struct DaisyRawManifestItem {
    let id: String
    let href: String
    let mediaType: String
}

private nonisolated final class
    DaisyPackageXMLDelegate:
    NSObject,
    XMLParserDelegate
{
    private var isInsideMetadata = false
    private var metadataElement: String?
    private var metadataBuffer = ""
    private(set) var identifier: String?
    private(set) var title: String?
    private(set) var creator: String?
    private(set) var language: String?
    private(set) var manifestItems:
        [DaisyRawManifestItem] = []
    private(set) var spineIDs: [String] = []
    private(set) var navigationID: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict:
            [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        switch name {
        case "metadata":
            isInsideMetadata = true
        case "identifier", "title",
             "creator", "language":
            if isInsideMetadata {
                metadataElement = name
                metadataBuffer = ""
            }
        case "item":
            guard let id = attributeDict["id"],
                  let href =
                    attributeDict["href"],
                  let mediaType =
                    attributeDict[
                        "media-type"
                    ] else {
                return
            }
            manifestItems.append(
                DaisyRawManifestItem(
                    id: id,
                    href: href,
                    mediaType: mediaType
                )
            )
        case "spine":
            navigationID =
                attributeDict["toc"]
        case "itemref":
            if let id =
                    attributeDict["idref"] {
                spineIDs.append(id)
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        if metadataElement != nil {
            metadataBuffer += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        if name == "metadata" {
            isInsideMetadata = false
        }
        guard name == metadataElement else {
            return
        }
        let value =
            metadataBuffer.nonEmptyTrimmed
        switch name {
        case "identifier":
            identifier = identifier ?? value
        case "title":
            title = title ?? value
        case "creator":
            creator = creator ?? value
        case "language":
            language = language ?? value
        default:
            break
        }
        metadataElement = nil
        metadataBuffer = ""
    }
}

private nonisolated final class NCXXMLDelegate:
    NSObject,
    XMLParserDelegate
{
    private final class Entry {
        let id: String
        let depth: Int
        let playOrder: Int?
        var label = ""
        var href: String?

        init(
            id: String,
            depth: Int,
            playOrder: Int?
        ) {
            self.id = id
            self.depth = depth
            self.playOrder = playOrder
        }
    }

    private let sourcePath: String
    private var stack: [Entry] = []
    private var entries: [Entry] = []
    private var pages: [Entry] = []
    private var currentPage: Entry?
    private var isInsideNavLabel = false
    private var isInsideLabelText = false
    private var counter = 0

    init(sourcePath: String) {
        self.sourcePath = sourcePath
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict:
            [String: String] = [:]
    ) {
        switch elementName.lowercased() {
        case "navpoint":
            let entry = Entry(
                id:
                    attributeDict["id"]
                    ?? "nav-\(counter)",
                depth: stack.count,
                playOrder: Int(
                    attributeDict["playOrder"]
                    ?? attributeDict[
                        "playorder"
                    ]
                    ?? ""
                )
            )
            counter += 1
            entries.append(entry)
            stack.append(entry)
        case "pagetarget":
            currentPage = Entry(
                id:
                    attributeDict["id"]
                    ?? "page-\(counter)",
                depth: 0,
                playOrder: Int(
                    attributeDict["playOrder"]
                    ?? attributeDict[
                        "playorder"
                    ]
                    ?? ""
                )
            )
            counter += 1
        case "navlabel":
            isInsideNavLabel = true
        case "text":
            if isInsideNavLabel {
                isInsideLabelText = true
            }
        case "content":
            let source = attributeDict["src"]
            if let currentPage {
                currentPage.href = source
            } else {
                stack.last?.href = source
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        guard isInsideLabelText else {
            return
        }
        if let currentPage {
            currentPage.label += string
        } else {
            stack.last?.label += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName.lowercased() {
        case "text":
            isInsideLabelText = false
        case "navlabel":
            isInsideNavLabel = false
        case "navpoint":
            _ = stack.popLast()
        case "pagetarget":
            if let currentPage {
                pages.append(currentPage)
            }
            currentPage = nil
        default:
            break
        }
    }

    func result() -> NCXParseResult {
        let navigation = entries.compactMap {
            item($0)
        }
        return NCXParseResult(
            navigation: navigation,
            pageList: pages.compactMap {
                item($0)
            }
        )
    }

    private func item(
        _ entry: Entry
    ) -> PublicationNavigationItem? {
        let label = entry.label
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let href = entry.href.flatMap {
            AccessiblePublicationParser
                .resolveReference(
                    $0,
                    relativeTo: sourcePath
                )
        }
        guard !label.isEmpty
                || href != nil else {
            return nil
        }
        return PublicationNavigationItem(
            id: entry.id,
            label: label,
            href: href,
            depth: entry.depth,
            playOrder: entry.playOrder
        )
    }
}

private nonisolated final class
    AttributeReferenceXMLDelegate:
    NSObject,
    XMLParserDelegate
{
    private(set) var references: [String] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict:
            [String: String] = [:]
    ) {
        if let source =
                attributeDict["src"]
                ?? attributeDict["href"] {
            references.append(source)
        }
    }
}

private nonisolated extension String {
    var nonEmptyTrimmed: String? {
        let value = trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return value.isEmpty ? nil : value
    }
}
