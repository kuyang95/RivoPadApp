import Foundation

nonisolated enum AccessiblePublicationFormat:
    String,
    Equatable,
    Sendable
{
    case epub
    case daisy202
    case daisy3

    var displayName: String {
        switch self {
        case .epub:
            return "EPUB"
        case .daisy202:
            return "DAISY 2.02"
        case .daisy3:
            return "DAISY 3"
        }
    }
}

nonisolated struct PublicationNavigationItem:
    Identifiable,
    Equatable,
    Sendable
{
    let id: String
    let label: String
    let href: String?
    let depth: Int
    let playOrder: Int?
}

nonisolated struct EPUBChapter:
    Identifiable,
    Equatable,
    Sendable
{
    let id: String
    let title: String
    let href: String
    let text: String
    let sourceMarkup: String?
    let fragmentSegmentIndexes: [String: Int]

    init(
        id: String,
        title: String,
        href: String,
        text: String,
        sourceMarkup: String? = nil,
        fragmentSegmentIndexes:
            [String: Int] = [:]
    ) {
        self.id = id
        self.title = title
        self.href = href
        self.text = text
        self.sourceMarkup = sourceMarkup
        self.fragmentSegmentIndexes =
            fragmentSegmentIndexes
    }
}

nonisolated struct EPUBBook: Equatable, Sendable {
    let format: AccessiblePublicationFormat
    let identifier: String
    let title: String
    let creator: String?
    let language: String?
    let chapters: [EPUBChapter]
    let mediaOverlayItems:
        [EPUBMediaOverlayItem]
    let navigationItems:
        [PublicationNavigationItem]
    let pageListItems:
        [PublicationNavigationItem]

    init(
        format:
            AccessiblePublicationFormat = .epub,
        identifier: String,
        title: String,
        creator: String?,
        language: String?,
        chapters: [EPUBChapter],
        mediaOverlayItems:
            [EPUBMediaOverlayItem] = [],
        navigationItems:
            [PublicationNavigationItem] = [],
        pageListItems:
            [PublicationNavigationItem] = []
    ) {
        self.format = format
        self.identifier = identifier
        self.title = title
        self.creator = creator
        self.language = language
        self.chapters = chapters
        self.mediaOverlayItems =
            mediaOverlayItems
        self.navigationItems =
            navigationItems
        self.pageListItems =
            pageListItems
    }
}

nonisolated enum EPUBParserError: LocalizedError {
    case containerMissing
    case packagePathMissing
    case packageInvalid
    case readingOrderMissing
    case chapterTextMissing

    var errorDescription: String? {
        switch self {
        case .containerMissing:
            return AppLocalization.string(
                "EPUB container.xml을 찾을 수 없습니다."
            )
        case .packagePathMissing:
            return AppLocalization.string(
                "EPUB 패키지 경로를 찾을 수 없습니다."
            )
        case .packageInvalid:
            return AppLocalization.string(
                "EPUB OPF 패키지를 해석할 수 없습니다."
            )
        case .readingOrderMissing:
            return AppLocalization.string(
                "EPUB 읽기 순서가 없습니다."
            )
        case .chapterTextMissing:
            return AppLocalization.string(
                "EPUB에서 읽을 수 있는 본문을 찾지 못했습니다."
            )
        }
    }
}

nonisolated enum EPUBBookParser {
    private static let maximumSourceMarkupBytes =
        5 * 1_024 * 1_024

    private struct ManifestItem {
        let id: String
        let href: String
        let mediaType: String
        let properties: Set<String>
        let mediaOverlayID: String?
    }

    private struct ParsedNavigation {
        let titlesByPath: [String: String]
        let tableOfContents:
            [PublicationNavigationItem]
        let pageList:
            [PublicationNavigationItem]

        static let empty = ParsedNavigation(
            titlesByPath: [:],
            tableOfContents: [],
            pageList: []
        )
    }

    static func parse(data: Data) throws -> EPUBBook {
        let archive = try EPUBArchive(data: data)
        guard archive.contains("META-INF/container.xml") else {
            throw EPUBParserError.containerMissing
        }
        let containerData = try archive.data(
            at: "META-INF/container.xml"
        )
        let containerDelegate = EPUBContainerXMLDelegate()
        try parseXML(
            containerData,
            delegate: containerDelegate
        )
        guard let rawPackagePath = containerDelegate.packagePath else {
            throw EPUBParserError.packagePathMissing
        }
        let packagePath = try EPUBArchive.normalizedPath(
            rawPackagePath
        )
        let packageData = try archive.data(at: packagePath)
        let packageDelegate = EPUBPackageXMLDelegate()
        try parseXML(
            packageData,
            delegate: packageDelegate
        )

        var manifest: [String: ManifestItem] = [:]
        for rawItem in packageDelegate.manifestItems
        where manifest[rawItem.id] == nil {
            manifest[rawItem.id] = ManifestItem(
                id: rawItem.id,
                href: rawItem.href,
                mediaType: rawItem.mediaType,
                properties: rawItem.properties,
                mediaOverlayID:
                    rawItem.mediaOverlayID
            )
        }
        let spine = packageDelegate.spineIDs.compactMap {
            manifest[$0]
        }
        guard !spine.isEmpty else {
            throw EPUBParserError.readingOrderMissing
        }

        let navigation = try parsedNavigation(
            archive: archive,
            packagePath: packagePath,
            manifest: manifest,
            navigationID: packageDelegate.navigationID
        )
        var chapters: [EPUBChapter] = []
        for (index, item) in spine.enumerated() {
            let chapterPath = try resolve(
                href: item.href,
                relativeTo: packagePath
            )
            guard archive.contains(chapterPath) else {
                continue
            }
            let chapterData = try archive.data(at: chapterPath)
            let extractor = EPUBHTMLTextDelegate()
            try parseXHTML(chapterData, delegate: extractor)
            let text = extractor.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !text.isEmpty else {
                continue
            }
            let title =
                navigation.titlesByPath[chapterPath]
                ?? extractor.firstHeading
                ?? "제 \(index + 1)장"
            let capturedFragmentIndexes =
                extractor.fragmentSegmentIndexes
            let textMatchedFragmentIndexes =
                fragmentSegmentIndexes(
                    text: text,
                    fragmentTexts:
                        extractor.fragmentTexts
                )
            chapters.append(
                EPUBChapter(
                    id: item.id,
                    title: title,
                    href: chapterPath,
                    text: text,
                    sourceMarkup:
                        sourceMarkup(
                            chapterData
                        ),
                    fragmentSegmentIndexes:
                        textMatchedFragmentIndexes
                        .merging(
                            capturedFragmentIndexes,
                            uniquingKeysWith: {
                                _, captured in
                                captured
                            }
                        )
                )
            )
        }
        guard !chapters.isEmpty else {
            throw EPUBParserError.chapterTextMissing
        }

        let identifier = packageDelegate.identifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = packageDelegate.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let overlayPaths =
            try mediaOverlayPaths(
                spine: spine,
                manifest: manifest,
                manifestOrder:
                    packageDelegate
                    .manifestItems
                    .compactMap {
                        manifest[$0.id]
                    },
                packagePath: packagePath
            )
        let mediaOverlayItems =
            EPUBMediaOverlayParser.parse(
                archive: archive,
                paths: overlayPaths
            )
        return EPUBBook(
            identifier: identifier?.isEmpty == false
                ? identifier!
                : title ?? "EPUB",
            title: title?.isEmpty == false ? title! : "제목 없는 EPUB",
            creator: packageDelegate.creator,
            language: packageDelegate.language,
            chapters: chapters,
            mediaOverlayItems:
                mediaOverlayItems,
            navigationItems:
                navigation.tableOfContents,
            pageListItems:
                navigation.pageList
        )
    }

    static func sourceMarkup(
        _ data: Data
    ) -> String? {
        guard data.count
                <= maximumSourceMarkupBytes else {
            return nil
        }
        return EPUBArchive.decodeText(data)
    }

    private static func mediaOverlayPaths(
        spine: [ManifestItem],
        manifest: [String: ManifestItem],
        manifestOrder: [ManifestItem],
        packagePath: String
    ) throws -> [String] {
        var paths: [String] = []
        var seen: Set<String> = []
        for item in spine {
            guard let overlayID =
                    item.mediaOverlayID,
                  let overlay = manifest[
                      overlayID
                  ],
                  isSMIL(overlay) else {
                continue
            }
            let path = try resolve(
                href: overlay.href,
                relativeTo: packagePath
            )
            if seen.insert(path).inserted {
                paths.append(path)
            }
        }
        if !paths.isEmpty {
            return paths
        }
        for overlay in manifestOrder
        where isSMIL(overlay) {
            let path = try resolve(
                href: overlay.href,
                relativeTo: packagePath
            )
            if seen.insert(path).inserted {
                paths.append(path)
            }
        }
        return paths
    }

    private static func isSMIL(
        _ item: ManifestItem
    ) -> Bool {
        item.mediaType.lowercased()
            == "application/smil+xml"
        || item.mediaType.lowercased()
            == "application/smil"
        || item.href.lowercased()
            .hasSuffix(".smil")
    }

    static func fragmentSegmentIndexes(
        text: String,
        fragmentTexts: [String: String]
    ) -> [String: Int] {
        let segments = text
            .components(separatedBy: "\n\n")
            .map {
                $0.split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
        var result: [String: Int] = [:]
        for (fragmentID, rawFragmentText)
            in fragmentTexts
        where result[fragmentID] == nil {
            let fragmentText = rawFragmentText
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            guard !fragmentText.isEmpty,
                  let index = segments.firstIndex(
                      where: {
                          $0 == fragmentText
                          || $0.contains(
                              fragmentText
                          )
                          || fragmentText.contains(
                              $0
                          )
                      }
                  ) else {
                continue
            }
            result[fragmentID] = index
        }
        return result
    }

    private static func parsedNavigation(
        archive: EPUBArchive,
        packagePath: String,
        manifest: [String: ManifestItem],
        navigationID: String?
    ) throws -> ParsedNavigation {
        if let navigationItem = manifest.values.first(where: {
            $0.properties.contains("nav")
        }) {
            let navigationPath = try resolve(
                href: navigationItem.href,
                relativeTo: packagePath
            )
            let delegate = EPUBNavigationXMLDelegate()
            try parseXHTML(
                archive.data(at: navigationPath),
                delegate: delegate
            )
            return navigation(
                tableOfContents:
                    delegate.tableOfContents,
                pageList: delegate.pageList,
                relativeTo: navigationPath
            )
        }

        let ncxItem = navigationID.flatMap { manifest[$0] }
            ?? manifest.values.first(where: {
                $0.mediaType
                    == "application/x-dtbncx+xml"
            })
        guard let ncxItem else {
            return .empty
        }
        let ncxPath = try resolve(
            href: ncxItem.href,
            relativeTo: packagePath
        )
        let delegate = EPUBNCXXMLDelegate()
        try parseXML(
            archive.data(at: ncxPath),
            delegate: delegate
        )
        return navigation(
            tableOfContents:
                delegate.tableOfContents,
            pageList: delegate.pageList,
            relativeTo: ncxPath
        )
    }

    private static func navigation(
        tableOfContents:
            [EPUBRawNavigationItem],
        pageList: [EPUBRawNavigationItem],
        relativeTo navigationPath: String
    ) -> ParsedNavigation {
        func resolveItems(
            _ items: [EPUBRawNavigationItem]
        ) -> [PublicationNavigationItem] {
            items.map { item in
                PublicationNavigationItem(
                    id: item.id,
                    label: item.label,
                    href: item.href.flatMap {
                        try? resolveNavigationHref(
                            $0,
                            relativeTo:
                                navigationPath
                        )
                    },
                    depth: item.depth,
                    playOrder: item.playOrder
                )
            }
        }

        let toc = resolveItems(tableOfContents)
        let pages = resolveItems(pageList)
        var titles: [String: String] = [:]
        for item in toc
        where !item.label.isEmpty {
            guard let href = item.href else {
                continue
            }
            let path = href
                .split(
                    separator: "#",
                    maxSplits: 1
                )
                .first
                .map(String.init)
                ?? href
            if titles[path] == nil {
                titles[path] = item.label
            }
        }
        return ParsedNavigation(
            titlesByPath: titles,
            tableOfContents: toc,
            pageList: pages
        )
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
                ?? EPUBParserError.packageInvalid
        }
    }

    static func parseXHTML(
        _ data: Data,
        delegate: XMLParserDelegate
    ) throws {
        try parseXML(
            replacingHTMLEntities(in: data),
            delegate: delegate
        )
    }

    private static func replacingHTMLEntities(
        in data: Data
    ) -> Data {
        guard var text =
                EPUBArchive.decodeText(data) else {
            return data
        }
        let replacements = [
            "&nbsp;": "&#160;",
            "&copy;": "&#169;",
            "&reg;": "&#174;",
            "&trade;": "&#8482;",
            "&hellip;": "&#8230;",
            "&mdash;": "&#8212;",
            "&ndash;": "&#8211;",
            "&lsquo;": "&#8216;",
            "&rsquo;": "&#8217;",
            "&ldquo;": "&#8220;",
            "&rdquo;": "&#8221;",
            "&bull;": "&#8226;",
            "&middot;": "&#183;",
            "&laquo;": "&#171;",
            "&raquo;": "&#187;",
            "&times;": "&#215;",
            "&divide;": "&#247;"
        ]
        for (entity, numericEntity) in replacements {
            text = text.replacingOccurrences(
                of: entity,
                with: numericEntity
            )
        }
        text = text.replacingOccurrences(
            of:
                #"(?i)(<\?xml\b[^>]*\bencoding\s*=\s*["'])[^"']+(["'])"#,
            with: "$1UTF-8$2",
            options: .regularExpression
        )
        return Data(text.utf8)
    }

    private static func resolve(
        href: String,
        relativeTo baseFilePath: String
    ) throws -> String {
        let hrefPath = href
            .split(separator: "#", maxSplits: 1)
            .first
            .map(String.init)
            ?? href
        let baseDirectory = baseFilePath
            .split(separator: "/")
            .dropLast()
            .joined(separator: "/")
        let combined = baseDirectory.isEmpty
            ? hrefPath
            : "\(baseDirectory)/\(hrefPath)"
        return try EPUBArchive.normalizedPath(combined)
    }

    private static func resolveNavigationHref(
        _ href: String,
        relativeTo baseFilePath: String
    ) throws -> String {
        let trimmed = href.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("//"),
              trimmed.range(
                  of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#,
                  options: .regularExpression
              ) == nil else {
            throw EPUBParserError.packageInvalid
        }
        let parts = trimmed.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let pathPart = parts.first
            .map(String.init)
            ?? ""
        let resolvedPath: String
        if pathPart.isEmpty {
            resolvedPath = try EPUBArchive
                .normalizedPath(baseFilePath)
        } else {
            resolvedPath = try resolve(
                href: pathPart,
                relativeTo: baseFilePath
            )
        }
        guard parts.count > 1 else {
            return resolvedPath
        }
        return resolvedPath + "#" + String(parts[1])
    }
}

private nonisolated final class EPUBContainerXMLDelegate:
    NSObject,
    XMLParserDelegate
{
    var packagePath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.lowercased() == "rootfile" else {
            return
        }
        packagePath = attributeDict["full-path"]
    }
}

private nonisolated final class EPUBPackageXMLDelegate:
    NSObject,
    XMLParserDelegate
{
    struct RawManifestItem {
        let id: String
        let href: String
        let mediaType: String
        let properties: Set<String>
        let mediaOverlayID: String?
    }

    var manifestItems: [RawManifestItem] = []
    var spineIDs: [String] = []
    var navigationID: String?
    var identifier: String?
    var title: String?
    var creator: String?
    var language: String?

    private var isInsideMetadata = false
    private var currentMetadataName: String?
    private var currentMetadataText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        switch name {
        case "metadata":
            isInsideMetadata = true
        case "item":
            guard let id = attributeDict["id"],
                  let href = attributeDict["href"],
                  let mediaType = attributeDict["media-type"] else {
                return
            }
            let properties = Set(
                (attributeDict["properties"] ?? "")
                    .split(whereSeparator: \.isWhitespace)
                    .map(String.init)
            )
            manifestItems.append(
                RawManifestItem(
                    id: id,
                    href: href,
                    mediaType: mediaType,
                    properties: properties,
                    mediaOverlayID:
                        attributeDict[
                            "media-overlay"
                        ]
                )
            )
        case "spine":
            navigationID = attributeDict["toc"]
        case "itemref":
            if let idRef = attributeDict["idref"],
               attributeDict["linear"] != "no" {
                spineIDs.append(idRef)
            }
        case "identifier", "title", "creator", "language":
            guard isInsideMetadata else {
                return
            }
            currentMetadataName = name
            currentMetadataText = ""
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        guard currentMetadataName != nil else {
            return
        }
        currentMetadataText += string
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
        guard currentMetadataName == name else {
            return
        }
        let value = currentMetadataText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
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
        currentMetadataName = nil
        currentMetadataText = ""
    }
}

private nonisolated struct EPUBRawNavigationItem:
    Sendable
{
    let id: String
    let label: String
    let href: String?
    let depth: Int
    let playOrder: Int?
}

private nonisolated final class EPUBNavigationXMLDelegate:
    NSObject,
    XMLParserDelegate
{
    private struct Section {
        let types: Set<String>
        var items: [EPUBRawNavigationItem]
    }

    private struct LinkCapture {
        let elementDepth: Int
        let itemDepth: Int
        let id: String?
        let href: String?
        var label: String
    }

    var tableOfContents:
        [EPUBRawNavigationItem] {
        sections.first {
            $0.types.contains("toc")
        }?.items
        ?? sections.first?.items
        ?? []
    }

    var pageList:
        [EPUBRawNavigationItem] {
        sections.first {
            $0.types.contains("page-list")
        }?.items
        ?? []
    }

    private var sections: [Section] = []
    private var activeSectionIndex: Int?
    private var navigationDepth: Int?
    private var depth = 0
    private var listDepth = 0
    private var listItemDepths: [Int] = []
    private var linkCapture: LinkCapture?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        depth += 1
        let name = elementName.lowercased()
        if name == "nav" {
            let type = attributeDict["type"]
                ?? attributeDict["epub:type"]
                ?? ""
            let types = Set(
                type.lowercased()
                    .split(whereSeparator: \.isWhitespace)
                    .map(String.init)
            )
            sections.append(
                Section(types: types, items: [])
            )
            activeSectionIndex =
                sections.indices.last
            navigationDepth = depth
            listDepth = 0
            listItemDepths = []
            linkCapture = nil
            return
        }
        guard activeSectionIndex != nil else {
            return
        }
        if name == "ol" {
            listDepth += 1
        } else if name == "li" {
            listItemDepths.append(depth)
        } else if (name == "a" || name == "span"),
                  linkCapture == nil,
                  let itemElementDepth =
                    listItemDepths.last,
                  depth == itemElementDepth + 1 {
            linkCapture = LinkCapture(
                elementDepth: depth,
                itemDepth: max(0, listDepth - 1),
                id: attributeDict["id"],
                href:
                    name == "a"
                    ? attributeDict["href"]
                    : nil,
                label: ""
            )
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        if linkCapture != nil {
            linkCapture?.label += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        if let capture = linkCapture,
           capture.elementDepth == depth {
            let label = capture.label
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            if !label.isEmpty
                || capture.href?.isEmpty == false {
                let sectionIndex =
                    activeSectionIndex!
                let itemIndex =
                    sections[sectionIndex]
                    .items.count
                let trimmedID = capture.id?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                sections[sectionIndex]
                    .items.append(
                        EPUBRawNavigationItem(
                            id:
                                trimmedID?.isEmpty == false
                                ? trimmedID!
                                : "nav-\(sectionIndex)-\(itemIndex)",
                            label: label,
                            href: capture.href,
                            depth: capture.itemDepth,
                            playOrder: nil
                        )
                    )
            }
            linkCapture = nil
        }
        if name == "li",
           listItemDepths.last == depth {
            listItemDepths.removeLast()
        } else if name == "ol" {
            listDepth = max(0, listDepth - 1)
        }
        if name == "nav", navigationDepth == depth {
            activeSectionIndex = nil
            navigationDepth = nil
            listDepth = 0
            listItemDepths = []
            linkCapture = nil
        }
        depth -= 1
    }
}

private nonisolated final class EPUBNCXXMLDelegate:
    NSObject,
    XMLParserDelegate
{
    private enum ItemKind: Equatable {
        case tableOfContents
        case pageList
    }

    private struct Capture {
        let kind: ItemKind
        let sequence: Int
        let id: String
        let depth: Int
        let playOrder: Int?
        var href: String?
        var label: String
    }

    var tableOfContents:
        [EPUBRawNavigationItem] {
        completed
            .filter {
                $0.capture.kind
                    == .tableOfContents
            }
            .sorted {
                $0.capture.sequence
                    < $1.capture.sequence
            }
            .map(\.item)
    }

    var pageList:
        [EPUBRawNavigationItem] {
        completed
            .filter {
                $0.capture.kind == .pageList
            }
            .sorted {
                $0.capture.sequence
                    < $1.capture.sequence
            }
            .map(\.item)
    }

    private var depth = 0
    private var navMapDepth: Int?
    private var pageListDepth: Int?
    private var captures: [Capture] = []
    private var completed:
        [(capture: Capture, item: EPUBRawNavigationItem)] = []
    private var labelTextDepth: Int?
    private var nextSequence = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        depth += 1
        let name = elementName.lowercased()
        switch name {
        case "navmap":
            navMapDepth = depth
        case "pagelist":
            pageListDepth = depth
        case "navpoint":
            guard navMapDepth != nil else {
                return
            }
            captures.append(
                Capture(
                    kind: .tableOfContents,
                    sequence: nextSequence,
                    id:
                        attributeDict["id"]
                        ?? "nav-\(nextSequence)",
                    depth:
                        captures.filter {
                            $0.kind
                                == .tableOfContents
                        }.count,
                    playOrder:
                        (
                            attributeDict["playOrder"]
                            ?? attributeDict["playorder"]
                        ).flatMap(Int.init),
                    href: nil,
                    label: ""
                )
            )
            nextSequence += 1
        case "pagetarget":
            guard pageListDepth != nil else {
                return
            }
            captures.append(
                Capture(
                    kind: .pageList,
                    sequence: nextSequence,
                    id:
                        attributeDict["id"]
                        ?? "page-\(nextSequence)",
                    depth: 0,
                    playOrder:
                        (
                            attributeDict["playOrder"]
                            ?? attributeDict["playorder"]
                        ).flatMap(Int.init),
                    href: nil,
                    label: ""
                )
            )
            nextSequence += 1
        case "text":
            if !captures.isEmpty {
                labelTextDepth = depth
            }
        case "content":
            if !captures.isEmpty,
               captures[captures.count - 1]
                   .href == nil {
                captures[captures.count - 1]
                    .href = attributeDict["src"]
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        if labelTextDepth != nil,
           !captures.isEmpty {
            captures[captures.count - 1]
                .label += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        switch name {
        case "text":
            if labelTextDepth == depth {
                labelTextDepth = nil
            }
        case "navpoint", "pagetarget":
            guard let capture = captures.last,
                  (
                      name == "navpoint"
                          && capture.kind
                              == .tableOfContents
                      || name == "pagetarget"
                          && capture.kind
                              == .pageList
                  ) else {
                break
            }
            captures.removeLast()
            let label = capture.label
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            if !label.isEmpty
                || capture.href?.isEmpty == false {
                completed.append(
                    (
                        capture,
                        EPUBRawNavigationItem(
                            id: capture.id,
                            label: label,
                            href: capture.href,
                            depth: capture.depth,
                            playOrder:
                                capture.playOrder
                        )
                    )
                )
            }
        case "navmap":
            if navMapDepth == depth {
                navMapDepth = nil
            }
        case "pagelist":
            if pageListDepth == depth {
                pageListDepth = nil
            }
        default:
            break
        }
        depth -= 1
    }
}

nonisolated final class EPUBHTMLTextDelegate:
    NSObject,
    XMLParserDelegate
{
    private static let blockElements: Set<String> = [
        "address", "article", "aside", "blockquote", "br",
        "div", "figcaption", "figure", "footer", "h1",
        "h2", "h3", "h4", "h5", "h6", "header", "li",
        "main", "p", "pre", "section", "table", "td", "th",
        "tr", "hd", "sent", "pagenum", "doctitle",
        "docauthor", "byline", "dateline", "note",
        "prodnote", "sidebar", "annotation", "dt", "dd"
    ]
    private static let skippedElements: Set<String> = [
        "head", "nav", "script", "style", "svg"
    ]

    private var buffer = ""
    private var skippedDepth = 0
    private var headingDepth = 0
    private var headingBuffer = ""
    private(set) var firstHeading: String?
    private(set) var fragmentTexts:
        [String: String] = [:]
    private var fragmentUTF16Offsets:
        [String: Int] = [:]
    private var elementDepth = 0
    private var fragmentCaptures:
        [FragmentCapture] = []

    private struct FragmentCapture {
        let id: String
        let depth: Int
        var text: String
    }

    var text: String {
        buffer
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .components(separatedBy: .newlines)
            .map {
                $0.split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    var fragmentSegmentIndexes:
        [String: Int] {
        let segments = normalizedLines(in: buffer)
        guard !segments.isEmpty else {
            return [:]
        }
        let source = buffer as NSString
        var indexes: [String: Int] = [:]
        for (fragmentID, rawOffset)
            in fragmentUTF16Offsets {
            let offset = min(
                max(0, rawOffset),
                source.length
            )
            let prefix = source.substring(to: offset)
            let rawLines = prefix.components(
                separatedBy: .newlines
            )
            let normalizedPrefixLines =
                rawLines.map(Self.normalizeLine)
            let completedOrCurrentCount =
                normalizedPrefixLines
                    .filter { !$0.isEmpty }
                    .count
            let isInsideCurrentSegment =
                normalizedPrefixLines.last?
                .isEmpty == false
            let proposedIndex =
                isInsideCurrentSegment
                ? completedOrCurrentCount - 1
                : completedOrCurrentCount
            indexes[fragmentID] = min(
                max(0, proposedIndex),
                segments.count - 1
            )
        }
        return indexes
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        elementDepth += 1
        let name = elementName.lowercased()
        if skippedDepth > 0 {
            skippedDepth += 1
            return
        }
        if Self.skippedElements.contains(name) {
            skippedDepth = 1
            return
        }
        if Self.blockElements.contains(name) {
            appendLineBreak()
        }
        if let fragmentID =
                attributeDict["id"]?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
           !fragmentID.isEmpty {
            if fragmentUTF16Offsets[fragmentID]
                == nil {
                fragmentUTF16Offsets[fragmentID] =
                    buffer.utf16.count
            }
            fragmentCaptures.append(
                FragmentCapture(
                    id: fragmentID,
                    depth: elementDepth,
                    text: ""
                )
            )
        }
        if [
            "h1", "h2", "h3", "hd", "doctitle",
        ].contains(name),
           firstHeading == nil {
            headingDepth = 1
            headingBuffer = ""
        } else if headingDepth > 0 {
            headingDepth += 1
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        guard skippedDepth == 0 else {
            return
        }
        buffer += string
        for index in fragmentCaptures.indices {
            fragmentCaptures[index].text += string
        }
        if headingDepth > 0 {
            headingBuffer += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        if skippedDepth > 0 {
            skippedDepth -= 1
            elementDepth -= 1
            return
        }
        if headingDepth > 0 {
            headingDepth -= 1
            if headingDepth == 0 {
                let heading = headingBuffer
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                if !heading.isEmpty {
                    firstHeading = heading
                }
            }
        }
        if Self.blockElements.contains(name) {
            appendLineBreak()
        }
        let completed = fragmentCaptures
            .filter {
                $0.depth == elementDepth
            }
        fragmentCaptures.removeAll {
            $0.depth == elementDepth
        }
        for capture in completed
        where fragmentTexts[capture.id] == nil {
            let text = capture.text
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            if !text.isEmpty {
                fragmentTexts[capture.id] = text
            }
        }
        elementDepth -= 1
    }

    private func appendLineBreak() {
        guard !buffer.hasSuffix("\n") else {
            return
        }
        buffer += "\n"
    }

    private func normalizedLines(
        in value: String
    ) -> [String] {
        value
            .replacingOccurrences(
                of: "\u{00A0}",
                with: " "
            )
            .components(separatedBy: .newlines)
            .map(Self.normalizeLine)
            .filter { !$0.isEmpty }
    }

    private static func normalizeLine(
        _ value: String
    ) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
