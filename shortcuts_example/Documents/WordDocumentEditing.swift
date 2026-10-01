import Foundation
import ZIPFoundation

nonisolated enum WordDocumentEditingError:
    Error,
    LocalizedError,
    Equatable,
    Sendable
{
    case invalidDocument
    case encryptedDocument
    case limitExceeded
    case unsupportedEdit
    case staleDocument
    case cannotSave

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return AppLocalization.string(
                "Word 문서 구조를 읽을 수 없습니다."
            )
        case .encryptedDocument:
            return AppLocalization.string(
                "암호로 보호된 Word 문서는 편집할 수 없습니다."
            )
        case .limitExceeded:
            return AppLocalization.string(
                "Word 문서가 안전하게 편집할 수 있는 크기 또는 구조 제한을 초과했습니다."
            )
        case .unsupportedEdit:
            return AppLocalization.string(
                "이 문단에는 필드나 자동 생성 콘텐츠가 있어 현재 버전에서 직접 편집할 수 없습니다."
            )
        case .staleDocument:
            return AppLocalization.string(
                "편집하는 동안 문서 구조가 바뀌었습니다. 문서를 다시 열어 주세요."
            )
        case .cannotSave:
            return AppLocalization.string(
                "DOCX 문서를 저장할 수 없습니다."
            )
        }
    }
}

nonisolated struct WordDocumentTableLocation:
    Encodable,
    Hashable,
    Sendable
{
    let table: Int
    let row: Int
    let column: Int
    let paragraph: Int
    var rowSpan: Int = 1
    var columnSpan: Int = 1
    var sectionPath: String? = nil
    var parent: Parent? = nil

    struct Parent: Encodable, Hashable, Sendable {
        let table: Int
        let row: Int
        let column: Int
    }

    var accessibilityDescription: String {
        AppLocalization.format(
            "표 %lld · %lld행 · %lld열",
            table + 1,
            row + 1,
            column + 1
        )
    }
}

nonisolated struct WordDocumentBlock:
    Identifiable,
    Hashable,
    Sendable
{
    enum Kind: String, Hashable, Sendable {
        case title
        case heading1
        case heading2
        case heading3
        case listItem
        case paragraph
        case tableCell
    }

    let id: String
    let paragraphIndex: Int
    var text: String
    var styleID: String?
    let isNumbered: Bool
    let tableLocation: WordDocumentTableLocation?
    let isEditable: Bool

    var kind: Kind {
        if tableLocation != nil {
            return .tableCell
        }
        switch normalizedStyleID {
        case "title":
            return .title
        case "heading1", "heading 1":
            return .heading1
        case "heading2", "heading 2":
            return .heading2
        case "heading3", "heading 3":
            return .heading3
        default:
            return isNumbered ? .listItem : .paragraph
        }
    }

    var normalizedStyleID: String {
        (styleID ?? "Normal")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var accessibilityLabel: String {
        let role: String
        switch kind {
        case .title:
            role = AppLocalization.string("문서 제목")
        case .heading1:
            role = AppLocalization.string("제목 1")
        case .heading2:
            role = AppLocalization.string("제목 2")
        case .heading3:
            role = AppLocalization.string("제목 3")
        case .listItem:
            role = AppLocalization.string("목록 항목")
        case .paragraph:
            role = AppLocalization.string("문단")
        case .tableCell:
            role = tableLocation?.accessibilityDescription
                ?? AppLocalization.string("표 셀")
        }
        return text.isEmpty ? role : "\(role). \(text)"
    }
}

nonisolated struct WordDocumentPackage: Sendable {
    static let maximumBlocks = 20_000

    let sourceData: Data
    let documentXML: String
    let blocks: [WordDocumentBlock]

    static func load(from data: Data) throws -> WordDocumentPackage {
        guard data.count <= WordDocumentTextExtractor.maximumDocumentBytes else {
            throw WordDocumentEditingError.limitExceeded
        }
        let archive = try WordEditingArchive(data: data)
        guard archive.contains("word/document.xml") else {
            if archive.contains("EncryptedPackage") {
                throw WordDocumentEditingError.encryptedDocument
            }
            throw WordDocumentEditingError.invalidDocument
        }
        let documentData = try archive.data(at: "word/document.xml")
        guard let xml = String(data: documentData, encoding: .utf8),
              !xml.localizedCaseInsensitiveContains("<!DOCTYPE"),
              !xml.localizedCaseInsensitiveContains("<!ENTITY") else {
            throw WordDocumentEditingError.invalidDocument
        }
        let parser = WordDocumentStructureParser()
        let blocks = try parser.parse(documentData)
        guard blocks.count <= maximumBlocks else {
            throw WordDocumentEditingError.limitExceeded
        }
        let ranges = try WordParagraphXMLPatcher.paragraphRanges(in: xml)
        guard ranges.count == blocks.count else {
            throw WordDocumentEditingError.invalidDocument
        }
        return WordDocumentPackage(
            sourceData: data,
            documentXML: xml,
            blocks: blocks
        )
    }

    func serializedData(
        applying editedBlocks: [WordDocumentBlock]
    ) throws -> Data {
        guard editedBlocks.count == blocks.count else {
            throw WordDocumentEditingError.staleDocument
        }
        let patched = try WordParagraphXMLPatcher.apply(
            originalXML: documentXML,
            originalBlocks: blocks,
            editedBlocks: editedBlocks
        )
        guard let documentData = patched.data(using: .utf8),
              documentData.count
                <= WordDocumentTextExtractor.maximumEntryBytes else {
            throw WordDocumentEditingError.limitExceeded
        }
        let archive = try WordEditingArchive(data: sourceData)
        let result = try archive.repack(
            replacing: ["word/document.xml": documentData]
        )
        guard result.count <= WordDocumentTextExtractor.maximumDocumentBytes else {
            throw WordDocumentEditingError.limitExceeded
        }
        return result
    }
}

private nonisolated final class WordDocumentStructureParser:
    NSObject,
    XMLParserDelegate
{
    private struct TableContext {
        let index: Int
        var row = -1
        var column = -1
        var paragraph = -1
    }

    private var blocks: [WordDocumentBlock] = []
    private var paragraphDepth = 0
    private var textDepth = 0
    private var currentText = ""
    private var currentStyleID: String?
    private var currentIsNumbered = false
    private var currentContainsField = false
    private var currentTableLocation: WordDocumentTableLocation?
    private var nextTableIndex = 0
    private var tableStack: [TableContext] = []
    private var parseError: Error?

    func parse(_ data: Data) throws -> [WordDocumentBlock] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), parseError == nil else {
            throw WordDocumentEditingError.invalidDocument
        }
        return blocks
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(qName ?? elementName)
        switch name {
        case "tbl":
            tableStack.append(
                TableContext(index: nextTableIndex)
            )
            nextTableIndex += 1
        case "tr":
            guard !tableStack.isEmpty else { return }
            tableStack[tableStack.count - 1].row += 1
            tableStack[tableStack.count - 1].column = -1
        case "tc":
            guard !tableStack.isEmpty else { return }
            tableStack[tableStack.count - 1].column += 1
            tableStack[tableStack.count - 1].paragraph = -1
        case "p":
            if paragraphDepth == 0 {
                currentText = ""
                currentStyleID = nil
                currentIsNumbered = false
                currentContainsField = false
                if !tableStack.isEmpty {
                    tableStack[tableStack.count - 1].paragraph += 1
                    let table = tableStack[tableStack.count - 1]
                    if table.row >= 0, table.column >= 0 {
                        currentTableLocation = WordDocumentTableLocation(
                            table: table.index,
                            row: table.row,
                            column: table.column,
                            paragraph: max(table.paragraph, 0)
                        )
                    } else {
                        currentTableLocation = nil
                    }
                } else {
                    currentTableLocation = nil
                }
            }
            paragraphDepth += 1
        case "pStyle":
            guard paragraphDepth > 0 else { return }
            currentStyleID = attribute(
                named: "val",
                in: attributeDict
            )
        case "numPr", "numId":
            if paragraphDepth > 0 {
                currentIsNumbered = true
            }
        case "t":
            if paragraphDepth > 0 {
                textDepth += 1
            }
        case "tab":
            if paragraphDepth > 0 {
                currentText.append("\t")
            }
        case "br", "cr":
            if paragraphDepth > 0 {
                currentText.append("\n")
            }
        case "fldChar", "instrText":
            if paragraphDepth > 0 {
                currentContainsField = true
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        guard paragraphDepth > 0, textDepth > 0 else { return }
        currentText.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(qName ?? elementName)
        switch name {
        case "t":
            textDepth = max(0, textDepth - 1)
        case "p":
            paragraphDepth = max(0, paragraphDepth - 1)
            if paragraphDepth == 0 {
                let index = blocks.count
                blocks.append(
                    WordDocumentBlock(
                        id: "word-paragraph-\(index)",
                        paragraphIndex: index,
                        text: currentText,
                        styleID: currentStyleID,
                        isNumbered: currentIsNumbered,
                        tableLocation: currentTableLocation,
                        isEditable: !currentContainsField
                    )
                )
            }
        case "tbl":
            if !tableStack.isEmpty {
                tableStack.removeLast()
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        parseErrorOccurred parseError: Error
    ) {
        self.parseError = parseError
    }

    private func localName(_ value: String) -> String {
        value.split(separator: ":").last.map(String.init) ?? value
    }

    private func attribute(
        named name: String,
        in attributes: [String: String]
    ) -> String? {
        attributes.first {
            localName($0.key) == name
        }?.value
    }
}

private nonisolated enum WordParagraphXMLPatcher {
    private static let paragraphExpression = try! NSRegularExpression(
        pattern: #"<w:p(?:\s[^>]*)?\s*/>|<w:p(?:\s[^>]*)?>[\s\S]*?</w:p>"#
    )
    private static let textExpression = try! NSRegularExpression(
        pattern: #"<w:t(?:\s[^>]*)?>([\s\S]*?)</w:t>"#
    )
    private static let styleExpression = try! NSRegularExpression(
        pattern: #"<w:pStyle(?:\s[^>]*)?\s*/>|<w:pStyle(?:\s[^>]*)?>[\s\S]*?</w:pStyle>"#
    )
    private static let paragraphPropertiesExpression = try! NSRegularExpression(
        pattern: #"<w:pPr(?:\s[^>]*)?>"#
    )
    private static let paragraphStartExpression = try! NSRegularExpression(
        pattern: #"<w:p(?:\s[^>]*)?>"#
    )

    static func paragraphRanges(in xml: String) throws -> [NSRange] {
        let range = NSRange(location: 0, length: (xml as NSString).length)
        return paragraphExpression.matches(in: xml, range: range).map(\.range)
    }

    static func apply(
        originalXML: String,
        originalBlocks: [WordDocumentBlock],
        editedBlocks: [WordDocumentBlock]
    ) throws -> String {
        let ranges = try paragraphRanges(in: originalXML)
        guard ranges.count == originalBlocks.count,
              editedBlocks.count == originalBlocks.count else {
            throw WordDocumentEditingError.staleDocument
        }

        var mutable = originalXML as NSString
        for index in ranges.indices.reversed() {
            let original = originalBlocks[index]
            let edited = editedBlocks[index]
            guard original.id == edited.id,
                  original.paragraphIndex == edited.paragraphIndex else {
                throw WordDocumentEditingError.staleDocument
            }
            guard original.text != edited.text
                    || normalizedStyle(original.styleID)
                    != normalizedStyle(edited.styleID) else {
                continue
            }
            guard original.isEditable else {
                throw WordDocumentEditingError.unsupportedEdit
            }
            var paragraph = mutable.substring(with: ranges[index])
            if original.text != edited.text {
                paragraph = replaceText(
                    in: paragraph,
                    originalText: original.text,
                    with: edited.text
                )
            }
            if normalizedStyle(original.styleID)
                != normalizedStyle(edited.styleID) {
                paragraph = replaceStyle(
                    in: paragraph,
                    with: edited.styleID
                )
            }
            mutable = mutable.replacingCharacters(
                in: ranges[index],
                with: paragraph
            ) as NSString
        }
        return mutable as String
    }

    private static func replaceText(
        in paragraph: String,
        originalText: String,
        with text: String
    ) -> String {
        let fullRange = NSRange(
            location: 0,
            length: (paragraph as NSString).length
        )
        let matches = textExpression.matches(
            in: paragraph,
            range: fullRange
        )
        if matches.isEmpty {
            let insertion = "<w:r>\(encodedTextElements(text))</w:r>"
            if let closing = paragraph.range(of: "</w:p>", options: .backwards) {
                var result = paragraph
                result.insert(contentsOf: insertion, at: closing.lowerBound)
                return result
            }
            if paragraph.hasSuffix("/>") {
                let start = String(paragraph.dropLast(2)) + ">"
                return start + insertion + "</w:p>"
            }
            return paragraph
        }

        if !originalText.contains("\n"),
           !originalText.contains("\t"),
           !text.contains("\n"),
           !text.contains("\t"),
           let segments = richTextSegments(
               matches: matches,
               paragraph: paragraph,
               originalText: originalText,
               replacementText: text
           ) {
            var result = paragraph as NSString
            for (index, match) in matches.enumerated().reversed() {
                let contentRange = match.range(at: 1)
                result = result.replacingCharacters(
                    in: contentRange,
                    with: xmlText(segments[index])
                ) as NSString
            }
            return result as String
        }

        var result = paragraph as NSString
        for (offset, match) in matches.enumerated().reversed() {
            let replacement = offset == 0
                ? encodedTextElements(text)
                : "<w:t></w:t>"
            result = result.replacingCharacters(
                in: match.range,
                with: replacement
            ) as NSString
        }
        return result as String
    }

    private static func richTextSegments(
        matches: [NSTextCheckingResult],
        paragraph: String,
        originalText: String,
        replacementText: String
    ) -> [String]? {
        let source = paragraph as NSString
        let originalSegments = matches.map {
            xmlUnescape(source.substring(with: $0.range(at: 1)))
        }
        guard originalSegments.joined() == originalText else { return nil }

        var remaining = replacementText[...]
        var result: [String] = []
        for index in originalSegments.indices {
            if index == originalSegments.indices.last {
                result.append(String(remaining))
                remaining = remaining[remaining.endIndex...]
                continue
            }
            let length = min(originalSegments[index].count, remaining.count)
            let end = remaining.index(
                remaining.startIndex,
                offsetBy: length
            )
            result.append(String(remaining[..<end]))
            remaining = remaining[end...]
        }
        return result
    }

    private static func replaceStyle(
        in paragraph: String,
        with styleID: String?
    ) -> String {
        let style = normalizedStyle(styleID)
        let fullRange = NSRange(
            location: 0,
            length: (paragraph as NSString).length
        )
        if let match = styleExpression.firstMatch(
            in: paragraph,
            range: fullRange
        ) {
            let replacement = style == "Normal"
                ? ""
                : "<w:pStyle w:val=\"\(xmlAttribute(style))\"/>"
            return (paragraph as NSString).replacingCharacters(
                in: match.range,
                with: replacement
            )
        }
        guard style != "Normal" else { return paragraph }
        let styleXML = "<w:pStyle w:val=\"\(xmlAttribute(style))\"/>"
        if paragraph.hasPrefix("<w:p"), paragraph.hasSuffix("/>") {
            let start = String(paragraph.dropLast(2)) + ">"
            return start + "<w:pPr>\(styleXML)</w:pPr></w:p>"
        }
        if let pPr = paragraphPropertiesExpression.firstMatch(
            in: paragraph,
            range: fullRange
        ) {
            let insertion = pPr.range.location + pPr.range.length
            return (paragraph as NSString).replacingCharacters(
                in: NSRange(location: insertion, length: 0),
                with: styleXML
            )
        }
        if let start = paragraphStartExpression.firstMatch(
            in: paragraph,
            range: fullRange
        ) {
            let insertion = start.range.location + start.range.length
            return (paragraph as NSString).replacingCharacters(
                in: NSRange(location: insertion, length: 0),
                with: "<w:pPr>\(styleXML)</w:pPr>"
            )
        }
        return paragraph
    }

    private static func normalizedStyle(_ styleID: String?) -> String {
        let value = (styleID ?? "Normal")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Normal" : value
    }

    private static func encodedTextElements(_ text: String) -> String {
        var result = "<w:t xml:space=\"preserve\">"
        var buffer = ""

        func flush() {
            result += xmlText(buffer)
            buffer = ""
        }

        for character in text {
            switch character {
            case "\n":
                flush()
                result += "</w:t><w:br/><w:t xml:space=\"preserve\">"
            case "\t":
                flush()
                result += "</w:t><w:tab/><w:t xml:space=\"preserve\">"
            default:
                buffer.append(character)
            }
        }
        flush()
        result += "</w:t>"
        return result
    }

    private static func xmlText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func xmlUnescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func xmlAttribute(_ value: String) -> String {
        xmlText(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private nonisolated final class WordEditingArchive {
    private let archive: Archive
    private let entries: [String: Entry]
    private let orderedEntries: [Entry]

    init(data: Data) throws {
        do {
            archive = try Archive(data: data, accessMode: .read)
        } catch {
            throw WordDocumentEditingError.invalidDocument
        }
        var mapped: [String: Entry] = [:]
        var ordered: [Entry] = []
        var entryCount = 0
        var expandedBytes: UInt64 = 0
        for entry in archive {
            entryCount += 1
            let addition = expandedBytes.addingReportingOverflow(
                entry.uncompressedSize
            )
            guard entryCount <= WordDocumentTextExtractor.maximumArchiveEntries,
                  !addition.overflow,
                  addition.partialValue <= UInt64(
                    WordDocumentTextExtractor.maximumExpandedBytes
                  ),
                  entry.uncompressedSize <= UInt64(
                    WordDocumentTextExtractor.maximumEntryBytes
                  ),
                  entry.type != .symlink,
                  Self.isSafePath(entry.path) else {
                throw WordDocumentEditingError.limitExceeded
            }
            expandedBytes = addition.partialValue
            ordered.append(entry)
            if entry.type == .file {
                guard mapped[entry.path] == nil else {
                    throw WordDocumentEditingError.invalidDocument
                }
                mapped[entry.path] = entry
            }
        }
        entries = mapped
        orderedEntries = ordered
    }

    func contains(_ path: String) -> Bool {
        entries[path] != nil
    }

    func data(at path: String) throws -> Data {
        guard let entry = entries[path], entry.type == .file else {
            throw WordDocumentEditingError.invalidDocument
        }
        var result = Data()
        result.reserveCapacity(Int(entry.uncompressedSize))
        do {
            _ = try archive.extract(entry) { chunk in
                guard result.count + chunk.count
                    <= WordDocumentTextExtractor.maximumEntryBytes else {
                    throw WordDocumentEditingError.limitExceeded
                }
                result.append(chunk)
            }
        } catch let error as WordDocumentEditingError {
            throw error
        } catch {
            throw WordDocumentEditingError.invalidDocument
        }
        return result
    }

    func repack(replacing replacements: [String: Data]) throws -> Data {
        let output = try Archive(accessMode: .create)
        for entry in orderedEntries {
            let payload: Data
            if let replacement = replacements[entry.path] {
                payload = replacement
            } else if entry.type == .file {
                payload = try data(at: entry.path)
            } else {
                payload = Data()
            }
            try output.addEntry(
                with: entry.path,
                type: entry.type,
                uncompressedSize: Int64(payload.count),
                compressionMethod: entry.type == .file ? .deflate : .none
            ) { position, size in
                let lower = Int(position)
                let upper = min(payload.count, lower + size)
                guard lower < upper else { return Data() }
                return payload.subdata(in: lower..<upper)
            }
        }
        guard let result = output.data else {
            throw WordDocumentEditingError.cannotSave
        }
        return result
    }

    private static func isSafePath(_ path: String) -> Bool {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        return !normalized.hasPrefix("/")
            && !normalized.split(separator: "/").contains("..")
    }
}

nonisolated enum LegacyDOCXConverter {
    static func convert(text: String) throws -> Data {
        let paragraphs = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var body = ""
        for paragraph in paragraphs.prefix(WordDocumentPackage.maximumBlocks) {
            if paragraph.isEmpty {
                body += "<w:p/>"
            } else {
                body += "<w:p><w:r><w:t xml:space=\"preserve\">"
                    + xmlText(paragraph)
                    + "</w:t></w:r></w:p>"
            }
        }
        body += "<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"708\" w:footer=\"708\" w:gutter=\"0\"/></w:sectPr>"

        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(body)</w:body></w:document>
        """
        let entries: [String: Data] = [
            "[Content_Types].xml": Data(contentTypesXML.utf8),
            "_rels/.rels": Data(rootRelationshipsXML.utf8),
            "word/document.xml": Data(documentXML.utf8),
            "word/styles.xml": Data(stylesXML.utf8),
            "word/_rels/document.xml.rels": Data(documentRelationshipsXML.utf8),
        ]
        let archive = try Archive(accessMode: .create)
        for (path, payload) in entries.sorted(by: { $0.key < $1.key }) {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(payload.count),
                compressionMethod: .deflate
            ) { position, size in
                let lower = Int(position)
                let upper = min(payload.count, lower + size)
                guard lower < upper else { return Data() }
                return payload.subdata(in: lower..<upper)
            }
        }
        guard let result = archive.data else {
            throw WordDocumentEditingError.cannotSave
        }
        return result
    }

    private static func xmlText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>
    """

    private static let rootRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
    """

    private static let documentRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
    """

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="Apple SD Gothic Neo"/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style><w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="44"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="32"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="28"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="24"/></w:rPr></w:style></w:styles>
    """
}
