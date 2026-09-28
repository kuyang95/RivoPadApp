import Foundation

nonisolated struct ExcelCellHyperlink:
    Identifiable,
    Hashable,
    Sendable
{
    let id: UUID
    var range: ExcelCellRange
    var target: String
    var tooltip: String?
    var display: String?
    var relationshipID: String?
    var isExternal: Bool

    init(
        id: UUID = UUID(),
        range: ExcelCellRange,
        target: String,
        tooltip: String? = nil,
        display: String? = nil,
        relationshipID: String? = nil,
        isExternal: Bool = true
    ) {
        self.id = id
        self.range = range
        self.target = target
        self.tooltip = tooltip
        self.display = display
        self.relationshipID = relationshipID
        self.isExternal = isExternal
    }

    func contains(_ address: ExcelCellAddress) -> Bool {
        range.contains(address)
    }
}

nonisolated struct ExcelCellNote:
    Identifiable,
    Hashable,
    Sendable
{
    let id: UUID
    let address: ExcelCellAddress
    var author: String
    var text: String
    var originalXML: String?
    var originalAuthorID: Int?

    init(
        id: UUID = UUID(),
        address: ExcelCellAddress,
        author: String,
        text: String,
        originalXML: String? = nil,
        originalAuthorID: Int? = nil
    ) {
        self.id = id
        self.address = address
        self.author = author
        self.text = text
        self.originalXML = originalXML
        self.originalAuthorID = originalAuthorID
    }
}

nonisolated struct ExcelWorksheetAnnotations: Hashable, Sendable {
    var hyperlinks: [ExcelCellHyperlink]
    var notes: [ExcelCellNote]
    var authors: [String]
    var commentsPartPath: String?
    var vmlDrawingPartPath: String?
    var commentsRelationshipID: String?
    var vmlDrawingRelationshipID: String?

    static let empty = ExcelWorksheetAnnotations(
        hyperlinks: [],
        notes: [],
        authors: [],
        commentsPartPath: nil,
        vmlDrawingPartPath: nil,
        commentsRelationshipID: nil,
        vmlDrawingRelationshipID: nil
    )

    func hyperlink(at address: ExcelCellAddress) -> ExcelCellHyperlink? {
        hyperlinks.first { $0.contains(address) }
    }

    func note(at address: ExcelCellAddress) -> ExcelCellNote? {
        notes.first { $0.address == address }
    }
}

nonisolated struct ExcelWorksheetAnnotationEdits: Sendable {
    let partPath: String
    let annotations: ExcelWorksheetAnnotations
    let writesHyperlinks: Bool
    let writesNotes: Bool
}

nonisolated enum ExcelWorksheetAnnotationsLoader {
    static func load(
        sheetData: Data,
        sheetPartPath: String,
        relationships: [String: ExcelRelationship],
        reader: ExcelArchiveReader
    ) throws -> ExcelWorksheetAnnotations {
        let hyperlinks = try parseHyperlinks(
            sheetData,
            relationships: relationships
        )
        let commentsRelationship = relationships.first {
            $0.value.type.hasSuffix("/comments")
        }
        let vmlRelationship = relationships.first {
            $0.value.type.hasSuffix("/vmlDrawing")
        }
        let commentsPath = commentsRelationship.flatMap {
            normalizedPartPath(
                $0.value.target,
                relativeTo: sheetPartPath
            )
        }
        let vmlPath = vmlRelationship.flatMap {
            normalizedPartPath(
                $0.value.target,
                relativeTo: sheetPartPath
            )
        }
        let parsedComments: ParsedComments
        if let commentsPath,
           reader.contains(commentsPath),
           let xml = String(
               data: try reader.data(at: commentsPath),
               encoding: .utf8
           ) {
            parsedComments = parseComments(xml)
        } else {
            parsedComments = ParsedComments(authors: [], notes: [])
        }
        return ExcelWorksheetAnnotations(
            hyperlinks: hyperlinks,
            notes: parsedComments.notes,
            authors: parsedComments.authors,
            commentsPartPath: commentsPath,
            vmlDrawingPartPath: vmlPath,
            commentsRelationshipID: commentsRelationship?.key,
            vmlDrawingRelationshipID: vmlRelationship?.key
        )
    }

    private struct ParsedComments {
        let authors: [String]
        let notes: [ExcelCellNote]
    }

    private static func parseHyperlinks(
        _ data: Data,
        relationships: [String: ExcelRelationship]
    ) throws -> [ExcelCellHyperlink] {
        let delegate = HyperlinkDelegate(relationships: relationships)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse() else {
            throw ExcelWorkbookDocumentError.invalidWorkbook
        }
        return delegate.hyperlinks
    }

    private final class HyperlinkDelegate: NSObject, XMLParserDelegate {
        let relationships: [String: ExcelRelationship]
        var hyperlinks = [ExcelCellHyperlink]()

        init(relationships: [String: ExcelRelationship]) {
            self.relationships = relationships
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = (qName ?? elementName)
                .split(separator: ":").last.map(String.init)
                ?? elementName
            guard name == "hyperlink",
                  let reference = attributeDict["ref"],
                  let range = ExcelCellRange(reference) else {
                return
            }
            let relationshipID = attributeDict["r:id"]
                ?? attributeDict["id"]
            let location = attributeDict["location"]
            let relationship = relationshipID.flatMap {
                relationships[$0]
            }
            guard let target = location ?? relationship?.target else {
                return
            }
            hyperlinks.append(
                ExcelCellHyperlink(
                    range: range,
                    target: location.map { "#" + $0 } ?? target,
                    tooltip: attributeDict["tooltip"],
                    display: attributeDict["display"],
                    relationshipID: relationshipID,
                    isExternal: location == nil
                )
            )
        }
    }

    private static func parseComments(_ source: String) -> ParsedComments {
        let authorsContainer = firstContent(
            element: "authors",
            in: source
        ) ?? ""
        let authorXMLs = elementMatches("author", in: authorsContainer)
        let authors = authorXMLs.map {
            unescapeXML(stripTags($0))
        }
        let commentsContainer = firstContent(
            element: "commentList",
            in: source
        ) ?? ""
        let commentXMLs = elementMatches("comment", in: commentsContainer)
        let notes = commentXMLs.compactMap { xml -> ExcelCellNote? in
            guard let openingEnd = xml.firstIndex(of: ">") else {
                return nil
            }
            let opening = String(xml[...openingEnd])
            guard let reference = attribute("ref", in: opening),
                  let address = ExcelCellAddress(reference) else {
                return nil
            }
            let authorID = Int(attribute("authorId", in: opening) ?? "")
            let author = authorID.flatMap {
                authors.indices.contains($0) ? authors[$0] : nil
            } ?? AppLocalization.string("알 수 없는 작성자")
            let textXML = firstContent(element: "text", in: xml) ?? ""
            let textRuns = elementMatches("t", in: textXML)
            let text = textRuns.isEmpty
                ? unescapeXML(stripTags(textXML))
                : textRuns.map { unescapeXML(stripTags($0)) }.joined()
            return ExcelCellNote(
                address: address,
                author: author,
                text: text,
                originalXML: xml,
                originalAuthorID: authorID
            )
        }
        return ParsedComments(authors: authors, notes: notes)
    }

    private static func firstContent(
        element: String,
        in source: String
    ) -> String? {
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?"# + element
            + #"\b[^>]*>([\s\S]*?)</(?:[A-Za-z_][\w.-]*:)?"#
            + element + #"\s*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: source,
                  range: NSRange(source.startIndex..., in: source)
              ),
              let range = Range(match.range(at: 1), in: source) else {
            return nil
        }
        return String(source[range])
    }

    private static func elementMatches(
        _ element: String,
        in source: String
    ) -> [String] {
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?"# + element
            + #"\b[^>]*>[\s\S]*?</(?:[A-Za-z_][\w.-]*:)?"#
            + element + #"\s*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        return regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).compactMap {
            Range($0.range, in: source).map { String(source[$0]) }
        }
    }

    private static func attribute(
        _ name: String,
        in opening: String
    ) -> String? {
        let pattern = "(?:^|\\s)"
            + NSRegularExpression.escapedPattern(for: name)
            + #"\s*=\s*([\"'])(.*?)\1"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: opening,
                  range: NSRange(opening.startIndex..., in: opening)
              ),
              let range = Range(match.range(at: 2), in: opening) else {
            return nil
        }
        return unescapeXML(String(opening[range]))
    }

    private static func stripTags(_ source: String) -> String {
        source.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func unescapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

nonisolated enum ExcelWorksheetAnnotationsPackageWriter {
    static func apply(
        _ edit: ExcelWorksheetAnnotationEdits,
        sheetXML: inout String,
        reader: ExcelArchiveReader,
        replacements: inout [String: Data]
    ) throws {
        let relationshipPath = relationshipsPath(for: edit.partPath)
        var relationshipXML = try existingXML(
            at: relationshipPath,
            reader: reader,
            replacements: replacements
        ) ?? emptyRelationshipsXML
        var annotations = edit.annotations
        var usedPaths = reader.paths.union(replacements.keys)

        if edit.writesHyperlinks {
            relationshipXML = removingRelationships(
                typeSuffix: "/hyperlink",
                from: relationshipXML
            )
            let occupiedIDs = relationshipIDs(in: relationshipXML)
            var allocatedIDs = occupiedIDs
            for index in annotations.hyperlinks.indices
                where annotations.hyperlinks[index].isExternal {
                var identifier = annotations.hyperlinks[index]
                    .relationshipID
                if identifier == nil || allocatedIDs.contains(identifier!) {
                    identifier = nextRelationshipID(used: allocatedIDs)
                }
                allocatedIDs.insert(identifier!)
                annotations.hyperlinks[index].relationshipID = identifier
                relationshipXML = insertingRelationship(
                    id: identifier!,
                    type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink",
                    target: annotations.hyperlinks[index].target,
                    targetMode: "External",
                    into: relationshipXML
                )
            }
            sheetXML = try applyingHyperlinks(
                annotations.hyperlinks,
                to: sheetXML
            )
        }

        if edit.writesNotes {
            let needsParts = !annotations.notes.isEmpty
                || annotations.commentsPartPath != nil
            if needsParts {
                let commentsPath = annotations.commentsPartPath
                    ?? uniquePath(
                        directory: "xl",
                        stem: "comments",
                        extension: "xml",
                        used: &usedPaths
                    )
                let vmlPath = annotations.vmlDrawingPartPath
                    ?? uniquePath(
                        directory: "xl/drawings",
                        stem: "vmlDrawing",
                        extension: "vml",
                        used: &usedPaths
                    )
                annotations.commentsPartPath = commentsPath
                annotations.vmlDrawingPartPath = vmlPath

                var allocatedIDs = relationshipIDs(in: relationshipXML)
                let commentsID = annotations.commentsRelationshipID
                    ?? nextRelationshipID(used: allocatedIDs)
                allocatedIDs.insert(commentsID)
                let vmlID = annotations.vmlDrawingRelationshipID
                    ?? nextRelationshipID(used: allocatedIDs)
                annotations.commentsRelationshipID = commentsID
                annotations.vmlDrawingRelationshipID = vmlID

                if !relationshipHasID(commentsID, in: relationshipXML) {
                    relationshipXML = insertingRelationship(
                        id: commentsID,
                        type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments",
                        target: relativeTarget(
                            from: edit.partPath,
                            to: commentsPath
                        ),
                        targetMode: nil,
                        into: relationshipXML
                    )
                }
                if !relationshipHasID(vmlID, in: relationshipXML) {
                    relationshipXML = insertingRelationship(
                        id: vmlID,
                        type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/vmlDrawing",
                        target: relativeTarget(
                            from: edit.partPath,
                            to: vmlPath
                        ),
                        targetMode: nil,
                        into: relationshipXML
                    )
                }
                sheetXML = try ensureLegacyDrawing(
                    relationshipID: vmlID,
                    in: sheetXML
                )
                replacements[commentsPath] = Data(
                    commentsXML(for: annotations).utf8
                )
                replacements[vmlPath] = Data(
                    vmlXML(for: annotations.notes).utf8
                )
                try ensureContentTypes(
                    commentsPartPath: commentsPath,
                    reader: reader,
                    replacements: &replacements
                )
            }
        }

        replacements[relationshipPath] = Data(relationshipXML.utf8)
    }

    private static let emptyRelationshipsXML =
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"></Relationships>
        """

    private static func applyingHyperlinks(
        _ hyperlinks: [ExcelCellHyperlink],
        to source: String
    ) throws -> String {
        let prefix = worksheetPrefix(in: source)
        let escapedPrefix = NSRegularExpression.escapedPattern(for: prefix)
        let paired = "<" + escapedPrefix
            + #"hyperlinks\b[^>]*>[\s\S]*?</"#
            + escapedPrefix + #"hyperlinks\s*>"#
        let selfClosing = "<" + escapedPrefix + #"hyperlinks\b[^>]*/\s*>"#
        var result = replacingMatches(of: paired, in: source)
        result = replacingMatches(of: selfClosing, in: result)
        guard !hyperlinks.isEmpty else {
            return result
        }
        result = ensureRelationshipNamespace(in: result)
        let items = hyperlinks.map { link in
            var attributes = " ref=\""
                + escapeAttribute(link.range.reference) + "\""
            if link.isExternal,
               let relationshipID = link.relationshipID {
                attributes += " r:id=\""
                    + escapeAttribute(relationshipID) + "\""
            } else {
                attributes += " location=\""
                    + escapeAttribute(String(link.target.drop(while: {
                        $0 == "#"
                    }))) + "\""
            }
            if let display = link.display,
               !display.isEmpty {
                attributes += " display=\""
                    + escapeAttribute(display) + "\""
            }
            if let tooltip = link.tooltip,
               !tooltip.isEmpty {
                attributes += " tooltip=\""
                    + escapeAttribute(tooltip) + "\""
            }
            return "<\(prefix)hyperlink" + attributes + "/>"
        }.joined()
        let container = "<\(prefix)hyperlinks>" + items
            + "</\(prefix)hyperlinks>"
        let insertionPattern = "<" + escapedPrefix
            + #"(?:printOptions|pageMargins|pageSetup|headerFooter|drawing|legacyDrawing|legacyDrawingHF|picture|oleObjects|controls|webPublishItems|tableParts|extLst)\b"#
        if let range = result.range(
            of: insertionPattern,
            options: .regularExpression
        ) {
            result.insert(contentsOf: container, at: range.lowerBound)
            return result
        }
        return try insertBeforeWorksheetClose(container, in: result)
    }

    private static func ensureLegacyDrawing(
        relationshipID: String,
        in source: String
    ) throws -> String {
        var result = ensureRelationshipNamespace(in: source)
        let prefix = worksheetPrefix(in: result)
        let escapedPrefix = NSRegularExpression.escapedPattern(for: prefix)
        let pattern = "<" + escapedPrefix + #"legacyDrawing\b[^>]*/\s*>"#
        if let range = result.range(
            of: pattern,
            options: .regularExpression
        ) {
            result.replaceSubrange(
                range,
                with: "<\(prefix)legacyDrawing r:id=\""
                    + escapeAttribute(relationshipID) + "\"/>"
            )
            return result
        }
        let element = "<\(prefix)legacyDrawing r:id=\""
            + escapeAttribute(relationshipID) + "\"/>"
        let laterPattern = "<" + escapedPrefix
            + #"(?:legacyDrawingHF|picture|oleObjects|controls|webPublishItems|tableParts|extLst)\b"#
        if let range = result.range(
            of: laterPattern,
            options: .regularExpression
        ) {
            result.insert(contentsOf: element, at: range.lowerBound)
            return result
        }
        return try insertBeforeWorksheetClose(element, in: result)
    }

    private static func commentsXML(
        for annotations: ExcelWorksheetAnnotations
    ) -> String {
        var authors = annotations.authors
        for note in annotations.notes where !authors.contains(note.author) {
            authors.append(note.author)
        }
        if authors.isEmpty {
            authors = ["VisionCraft"]
        }
        let authorXML = authors.map {
            "<author>" + escapeText($0) + "</author>"
        }.joined()
        let noteXML = annotations.notes.sorted {
            $0.address < $1.address
        }.map { note in
            let authorID = authors.firstIndex(of: note.author) ?? 0
            if let originalXML = note.originalXML,
               note.originalAuthorID == authorID,
               originalXML.trimmingCharacters(in: .whitespacesAndNewlines)
                .hasPrefix("<comment") {
                return originalXML
            }
            let preserve = note.text.first?.isWhitespace == true
                || note.text.last?.isWhitespace == true
                || note.text.contains("\n")
                ? " xml:space=\"preserve\""
                : ""
            return "<comment ref=\""
                + escapeAttribute(note.address.reference)
                + "\" authorId=\"\(authorID)\"><text><t\(preserve)>"
                + escapeText(note.text)
                + "</t></text></comment>"
        }.joined()
        return
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <comments xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><authors>\(authorXML)</authors><commentList>\(noteXML)</commentList></comments>
            """
    }

    private static func vmlXML(for notes: [ExcelCellNote]) -> String {
        let shapes = notes.sorted { $0.address < $1.address }
            .enumerated().map { index, note in
                let column = max(note.address.column - 1, 0)
                let row = max(note.address.row - 1, 0)
                return
                    """
                    <v:shape id="_x0000_s\(1025 + index)" type="#_x0000_t202" style="position:absolute;margin-left:80pt;margin-top:5pt;width:108pt;height:59pt;z-index:1;visibility:hidden" fillcolor="#ffffe1" o:insetmode="auto"><v:fill color2="#ffffe1"/><v:shadow on="t" color="black" obscured="t"/><v:path o:connecttype="none"/><v:textbox style="mso-direction-alt:auto"><div style="text-align:left"/></v:textbox><x:ClientData ObjectType="Note"><x:MoveWithCells/><x:SizeWithCells/><x:Anchor>\(column), 15, \(row), 2, \(column + 2), 31, \(row + 3), 1</x:Anchor><x:AutoFill>False</x:AutoFill><x:Row>\(row)</x:Row><x:Column>\(column)</x:Column></x:ClientData></v:shape>
                    """
            }.joined()
        return
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <xml xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel"><o:shapelayout v:ext="edit"><o:idmap v:ext="edit" data="1"/></o:shapelayout><v:shapetype id="_x0000_t202" coordsize="21600,21600" o:spt="202" path="m,l,21600r21600,l21600,xe"><v:stroke joinstyle="miter"/><v:path gradientshapeok="t" o:connecttype="rect"/></v:shapetype>\(shapes)</xml>
            """
    }

    private static func ensureContentTypes(
        commentsPartPath: String,
        reader: ExcelArchiveReader,
        replacements: inout [String: Data]
    ) throws {
        let path = "[Content_Types].xml"
        guard var source = try existingXML(
            at: path,
            reader: reader,
            replacements: replacements
        ) else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        let commentPartName = "/" + commentsPartPath
        if !source.contains("PartName=\"\(commentPartName)\"")
            && !source.contains("PartName='\(commentPartName)'") {
            source = try insertingContentTypeElement(
                "<Override PartName=\""
                    + escapeAttribute(commentPartName)
                    + "\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.comments+xml\"/>",
                into: source
            )
        }
        let hasVMLDefault = source.range(
            of: #"<Default\b[^>]*\bExtension\s*=\s*[\"']vml[\"']"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        if !hasVMLDefault {
            source = try insertingContentTypeElement(
                "<Default Extension=\"vml\" ContentType=\"application/vnd.openxmlformats-officedocument.vmlDrawing\"/>",
                into: source
            )
        }
        replacements[path] = Data(source.utf8)
    }

    private static func insertingContentTypeElement(
        _ element: String,
        into source: String
    ) throws -> String {
        if let closing = source.range(
            of: #"</(?:[A-Za-z_][\w.-]*:)?Types\s*>"#,
            options: .regularExpression
        ) {
            var result = source
            result.insert(contentsOf: element, at: closing.lowerBound)
            return result
        }
        let selfClosingPattern = #"<(?:[A-Za-z_][\w.-]*:)?Types\b([^>]*)/\s*>"#
        guard let regex = try? NSRegularExpression(pattern: selfClosingPattern),
              let match = regex.firstMatch(
                  in: source,
                  range: NSRange(source.startIndex..., in: source)
              ),
              let range = Range(match.range, in: source) else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        let opening = String(source[range])
            .replacingOccurrences(
                of: #"/\s*>$"#,
                with: ">",
                options: .regularExpression
            )
        var result = source
        result.replaceSubrange(range, with: opening + element + "</Types>")
        return result
    }

    private static func removingRelationships(
        typeSuffix: String,
        from source: String
    ) -> String {
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?Relationship\b[^>]*/\s*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return source
        }
        var result = source
        let matches = regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )
        for match in matches.reversed() {
            guard let range = Range(match.range, in: source) else {
                continue
            }
            let element = String(source[range])
            if attribute("Type", in: element)?.hasSuffix(typeSuffix) == true,
               let resultRange = Range(match.range, in: result) {
                result.removeSubrange(resultRange)
            }
        }
        return result
    }

    private static func insertingRelationship(
        id: String,
        type: String,
        target: String,
        targetMode: String?,
        into source: String
    ) -> String {
        var element = "<Relationship Id=\"" + escapeAttribute(id)
            + "\" Type=\"" + escapeAttribute(type)
            + "\" Target=\"" + escapeAttribute(target) + "\""
        if let targetMode {
            element += " TargetMode=\"" + escapeAttribute(targetMode) + "\""
        }
        element += "/>"
        if let closing = source.range(
            of: #"</(?:[A-Za-z_][\w.-]*:)?Relationships\s*>"#,
            options: .regularExpression
        ) {
            var result = source
            result.insert(contentsOf: element, at: closing.lowerBound)
            return result
        }
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?Relationships\b([^>]*)/\s*>"#
        guard let range = source.range(of: pattern, options: .regularExpression)
        else {
            return source
        }
        let opening = String(source[range]).replacingOccurrences(
            of: #"/\s*>$"#,
            with: ">",
            options: .regularExpression
        )
        var result = source
        result.replaceSubrange(
            range,
            with: opening + element + "</Relationships>"
        )
        return result
    }

    private static func relationshipIDs(in source: String) -> Set<String> {
        let pattern = #"\bId\s*=\s*([\"'])(.*?)\1"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        return Set(regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).compactMap {
            Range($0.range(at: 2), in: source).map { String(source[$0]) }
        })
    }

    private static func relationshipHasID(
        _ id: String,
        in source: String
    ) -> Bool {
        relationshipIDs(in: source).contains(id)
    }

    private static func nextRelationshipID(used: Set<String>) -> String {
        var index = 1
        while used.contains("rId\(index)") {
            index += 1
        }
        return "rId\(index)"
    }

    private static func relationshipsPath(for partPath: String) -> String {
        let components = partPath.split(separator: "/")
        let directory = components.dropLast().joined(separator: "/")
        let filename = components.last.map(String.init) ?? "sheet.xml"
        return directory + "/_rels/" + filename + ".rels"
    }

    private static func relativeTarget(
        from sourcePart: String,
        to targetPart: String
    ) -> String {
        var sourceComponents = sourcePart.split(separator: "/").map(String.init)
        sourceComponents.removeLast()
        let targetComponents = targetPart.split(separator: "/").map(String.init)
        var common = 0
        while common < sourceComponents.count,
              common < targetComponents.count,
              sourceComponents[common] == targetComponents[common] {
            common += 1
        }
        return (
            Array(repeating: "..", count: sourceComponents.count - common)
                + Array(targetComponents.dropFirst(common))
        ).joined(separator: "/")
    }

    private static func uniquePath(
        directory: String,
        stem: String,
        extension fileExtension: String,
        used: inout Set<String>
    ) -> String {
        var index = 1
        while true {
            let path = directory + "/" + stem + String(index)
                + "." + fileExtension
            if !used.contains(path) {
                used.insert(path)
                return path
            }
            index += 1
        }
    }

    private static func existingXML(
        at path: String,
        reader: ExcelArchiveReader,
        replacements: [String: Data]
    ) throws -> String? {
        let data: Data?
        if let replacement = replacements[path] {
            data = replacement
        } else if reader.contains(path) {
            data = try reader.data(at: path)
        } else {
            data = nil
        }
        return data.flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func worksheetPrefix(in source: String) -> String {
        let pattern = #"<([A-Za-z_][\w.-]*:)?worksheet\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: source,
                  range: NSRange(source.startIndex..., in: source)
              ),
              match.range(at: 1).location != NSNotFound,
              let range = Range(match.range(at: 1), in: source) else {
            return ""
        }
        return String(source[range])
    }

    private static func ensureRelationshipNamespace(in source: String) -> String {
        guard !source.contains("xmlns:r=") else {
            return source
        }
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?worksheet\b"#
        guard let range = source.range(of: pattern, options: .regularExpression),
              let close = source[range.lowerBound...].firstIndex(of: ">") else {
            return source
        }
        var result = source
        result.insert(
            contentsOf: " xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"",
            at: close
        )
        return result
    }

    private static func insertBeforeWorksheetClose(
        _ element: String,
        in source: String
    ) throws -> String {
        let pattern = #"</(?:[A-Za-z_][\w.-]*:)?worksheet\s*>"#
        guard let range = source.range(of: pattern, options: .regularExpression)
        else {
            throw ExcelWorkbookDocumentError.invalidWorkbook
        }
        var result = source
        result.insert(contentsOf: element, at: range.lowerBound)
        return result
    }

    private static func replacingMatches(
        of pattern: String,
        in source: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return source
        }
        return regex.stringByReplacingMatches(
            in: source,
            range: NSRange(source.startIndex..., in: source),
            withTemplate: ""
        )
    }

    private static func attribute(_ name: String, in element: String) -> String? {
        let pattern = "(?:^|\\s)"
            + NSRegularExpression.escapedPattern(for: name)
            + #"\s*=\s*([\"'])(.*?)\1"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: element,
                  range: NSRange(element.startIndex..., in: element)
              ),
              let range = Range(match.range(at: 2), in: element) else {
            return nil
        }
        return String(element[range])
    }

    private static func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ value: String) -> String {
        escapeText(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
