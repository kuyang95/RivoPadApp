import Foundation

nonisolated struct EPUBChapter:
    Identifiable,
    Equatable,
    Sendable
{
    let id: String
    let title: String
    let href: String
    let text: String
}

nonisolated struct EPUBBook: Equatable, Sendable {
    let identifier: String
    let title: String
    let creator: String?
    let language: String?
    let chapters: [EPUBChapter]
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
            return "EPUB container.xml을 찾을 수 없습니다."
        case .packagePathMissing:
            return "EPUB 패키지 경로를 찾을 수 없습니다."
        case .packageInvalid:
            return "EPUB OPF 패키지를 해석할 수 없습니다."
        case .readingOrderMissing:
            return "EPUB 읽기 순서가 없습니다."
        case .chapterTextMissing:
            return "EPUB에서 읽을 수 있는 본문을 찾지 못했습니다."
        }
    }
}

nonisolated enum EPUBBookParser {
    private struct ManifestItem {
        let id: String
        let href: String
        let mediaType: String
        let properties: Set<String>
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
                properties: rawItem.properties
            )
        }
        let spine = packageDelegate.spineIDs.compactMap {
            manifest[$0]
        }
        guard !spine.isEmpty else {
            throw EPUBParserError.readingOrderMissing
        }

        let navigationTitles = try navigationTitleMap(
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
            let title = navigationTitles[chapterPath]
                ?? extractor.firstHeading
                ?? "제 \(index + 1)장"
            chapters.append(
                EPUBChapter(
                    id: item.id,
                    title: title,
                    href: chapterPath,
                    text: text
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
        return EPUBBook(
            identifier: identifier?.isEmpty == false
                ? identifier!
                : title ?? "EPUB",
            title: title?.isEmpty == false ? title! : "제목 없는 EPUB",
            creator: packageDelegate.creator,
            language: packageDelegate.language,
            chapters: chapters
        )
    }

    private static func navigationTitleMap(
        archive: EPUBArchive,
        packagePath: String,
        manifest: [String: ManifestItem],
        navigationID: String?
    ) throws -> [String: String] {
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
            var titles: [String: String] = [:]
            for link in delegate.links where !link.label.isEmpty {
                let path = try resolve(
                    href: link.href,
                    relativeTo: navigationPath
                )
                if titles[path] == nil {
                    titles[path] = link.label
                }
            }
            return titles
        }

        let ncxItem = navigationID.flatMap { manifest[$0] }
            ?? manifest.values.first(where: {
                $0.mediaType
                    == "application/x-dtbncx+xml"
            })
        guard let ncxItem else {
            return [:]
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
        var titles: [String: String] = [:]
        for link in delegate.links where !link.label.isEmpty {
            let path = try resolve(
                href: link.href,
                relativeTo: ncxPath
            )
            if titles[path] == nil {
                titles[path] = link.label
            }
        }
        return titles
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

    private static func parseXHTML(
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
        guard var text = String(data: data, encoding: .utf8) else {
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
                    properties: properties
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

private nonisolated final class EPUBNavigationXMLDelegate:
    NSObject,
    XMLParserDelegate
{
    struct Link {
        let href: String
        let label: String
    }

    var links: [Link] = []
    private var navigationDepth: Int?
    private var depth = 0
    private var currentHref: String?
    private var currentLabel = ""

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
            if type.split(whereSeparator: \.isWhitespace)
                .contains("toc") {
                navigationDepth = depth
            }
        } else if name == "a",
                  navigationDepth != nil,
                  let href = attributeDict["href"] {
            currentHref = href
            currentLabel = ""
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        if currentHref != nil {
            currentLabel += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        if name == "a", let href = currentHref {
            let label = currentLabel
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            links.append(Link(href: href, label: label))
            currentHref = nil
            currentLabel = ""
        }
        if name == "nav", navigationDepth == depth {
            navigationDepth = nil
        }
        depth -= 1
    }
}

private nonisolated final class EPUBNCXXMLDelegate:
    NSObject,
    XMLParserDelegate
{
    struct Link {
        let href: String
        let label: String
    }

    var links: [Link] = []
    private var isInsideNavPoint = false
    private var isInsideLabelText = false
    private var currentLabel = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        switch name {
        case "navpoint":
            isInsideNavPoint = true
            currentLabel = ""
        case "text":
            isInsideLabelText = isInsideNavPoint
        case "content":
            if isInsideNavPoint,
               let href = attributeDict["src"] {
                links.append(
                    Link(
                        href: href,
                        label: currentLabel
                            .split(whereSeparator: \.isWhitespace)
                            .joined(separator: " ")
                    )
                )
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        if isInsideLabelText {
            currentLabel += string
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
        case "navpoint":
            isInsideNavPoint = false
            currentLabel = ""
        default:
            break
        }
    }
}

private nonisolated final class EPUBHTMLTextDelegate:
    NSObject,
    XMLParserDelegate
{
    private static let blockElements: Set<String> = [
        "address", "article", "aside", "blockquote", "br",
        "div", "figcaption", "figure", "footer", "h1",
        "h2", "h3", "h4", "h5", "h6", "header", "li",
        "main", "p", "pre", "section", "table", "td", "th",
        "tr"
    ]
    private static let skippedElements: Set<String> = [
        "head", "nav", "script", "style", "svg"
    ]

    private var buffer = ""
    private var skippedDepth = 0
    private var headingDepth = 0
    private var headingBuffer = ""
    private(set) var firstHeading: String?

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

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
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
        if ["h1", "h2", "h3"].contains(name),
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
    }

    private func appendLineBreak() {
        guard !buffer.hasSuffix("\n") else {
            return
        }
        buffer += "\n"
    }
}
