import Foundation
import ZIPFoundation

nonisolated enum WordDocumentTextExtractorError:
    Error,
    LocalizedError,
    Equatable,
    Sendable
{
    case invalidDocument
    case encryptedDocument
    case unsupportedLegacyVersion
    case limitExceeded
    case noText

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return AppLocalization.string(
                "선택한 Word 문서를 읽을 수 없습니다."
            )
        case .encryptedDocument:
            return AppLocalization.string(
                "암호화되었거나 암호로 보호된 Word 문서는 열 수 없습니다."
            )
        case .unsupportedLegacyVersion:
            return AppLocalization.string(
                "이 DOC 문서 형식은 지원하지 않습니다. Word 97-2003 형식으로 다시 저장해 주세요."
            )
        case .limitExceeded:
            return AppLocalization.string(
                "Word 문서가 안전하게 열 수 있는 크기 또는 구조 제한을 초과했습니다."
            )
        case .noText:
            return AppLocalization.string(
                "Word 문서에서 읽을 텍스트를 찾지 못했습니다."
            )
        }
    }
}

/// Bounded, text-only reader for DOCX and Word 97-2003 DOC files.
///
/// DOCX handling reads only WordprocessingML XML. DOC handling reads the
/// `WordDocument` and selected table streams from the OLE container. Macros,
/// scripts, links, embedded objects, and package relationships are ignored.
nonisolated enum WordDocumentTextExtractor {
    static let supportedExtensions: Set<String> = [
        "doc",
        "docx",
        "docs",
    ]
    static let maximumDocumentBytes =
        20 * 1_024 * 1_024
    static let maximumArchiveEntries = 4_096
    static let maximumExpandedBytes =
        64 * 1_024 * 1_024
    static let maximumEntryBytes =
        16 * 1_024 * 1_024
    static let maximumOutputBytes =
        1_024 * 1_024

    private static let oleSignature: [UInt8] = [
        0xD0, 0xCF, 0x11, 0xE0,
        0xA1, 0xB1, 0x1A, 0xE1,
    ]

    static func extract(
        from data: Data
    ) throws -> String {
        guard data.count <= maximumDocumentBytes
        else {
            throw WordDocumentTextExtractorError
                .limitExceeded
        }

        let extracted: String
        if data.starts(with: oleSignature) {
            extracted = try extractLegacyDOC(
                from: data
            )
        } else if data.starts(
            with: [0x50, 0x4B]
        ) {
            extracted = try extractDOCX(
                from: data
            )
        } else {
            throw WordDocumentTextExtractorError
                .invalidDocument
        }

        let normalized = normalize(extracted)
        guard !normalized.isEmpty else {
            throw WordDocumentTextExtractorError
                .noText
        }
        return boundedText(normalized)
    }

    private static func extractDOCX(
        from data: Data
    ) throws -> String {
        let reader = try WordArchiveReader(
            data: data,
            maximumEntries:
                maximumArchiveEntries,
            maximumExpandedBytes:
                maximumExpandedBytes,
            maximumEntryBytes:
                maximumEntryBytes
        )
        guard reader.contains(
            "word/document.xml"
        ) else {
            throw WordDocumentTextExtractorError
                .invalidDocument
        }

        var sections: [String] = []
        let headerPaths = reader.paths.filter {
            wordPartNumber(
                path: $0,
                prefix: "word/header"
            ) != nil
        }
        .sorted {
            wordPartNumber(
                path: $0,
                prefix: "word/header"
            )! < wordPartNumber(
                path: $1,
                prefix: "word/header"
            )!
        }
        for path in headerPaths {
            let text = try WordprocessingMLTextParser
                .parse(try reader.data(at: path))
            if !text.isEmpty {
                sections.append(text)
            }
        }

        let mainText = try WordprocessingMLTextParser
            .parse(
                try reader.data(
                    at: "word/document.xml"
                )
            )
        if !mainText.isEmpty {
            sections.append(mainText)
        }

        for path in [
            "word/footnotes.xml",
            "word/endnotes.xml",
        ] where reader.contains(path) {
            let text = try WordprocessingMLTextParser
                .parse(try reader.data(at: path))
            if !text.isEmpty {
                sections.append(text)
            }
        }
        return sections.joined(separator: "\n\n")
    }

    private static func wordPartNumber(
        path: String,
        prefix: String
    ) -> Int? {
        guard path.hasPrefix(prefix),
              path.hasSuffix(".xml") else {
            return nil
        }
        let start = path.index(
            path.startIndex,
            offsetBy: prefix.count
        )
        let end = path.index(
            path.endIndex,
            offsetBy: -4
        )
        let value = path[start..<end]
        guard !value.isEmpty,
              value.allSatisfy(\.isNumber)
        else {
            return nil
        }
        return Int(value)
    }

    private static func extractLegacyDOC(
        from data: Data
    ) throws -> String {
        let container: OLECompoundFile
        do {
            container = try OLECompoundFile(
                data: data
            )
        } catch OLECompoundFileError
                    .limitExceeded {
            throw WordDocumentTextExtractorError
                .limitExceeded
        } catch {
            throw WordDocumentTextExtractorError
                .invalidDocument
        }

        if container.containsStream(
            named: "EncryptedPackage"
        ) {
            throw WordDocumentTextExtractorError
                .encryptedDocument
        }
        guard container.containsStream(
            named: "WordDocument"
        ) else {
            throw WordDocumentTextExtractorError
                .invalidDocument
        }

        let wordDocument: Data
        do {
            wordDocument = try container.stream(
                named: "WordDocument"
            )
        } catch {
            throw WordDocumentTextExtractorError
                .invalidDocument
        }
        guard try wordDocument.wordUInt16(at: 0)
                == 0xA5EC else {
            throw WordDocumentTextExtractorError
                .invalidDocument
        }

        let version = try wordDocument
            .wordUInt16(at: 2)
        guard version >= 0x00C1 else {
            throw WordDocumentTextExtractorError
                .unsupportedLegacyVersion
        }
        let flags = try wordDocument
            .wordUInt16(at: 10)
        let isEncrypted = flags
            & (1 << 8) != 0
        let isObfuscated = flags
            & (1 << 15) != 0
        guard !isEncrypted,
              !isObfuscated else {
            throw WordDocumentTextExtractorError
                .encryptedDocument
        }

        let tableName = flags
            & (1 << 9) == 0
            ? "0Table"
            : "1Table"
        guard container.containsStream(
            named: tableName
        ) else {
            throw WordDocumentTextExtractorError
                .invalidDocument
        }
        let table: Data
        do {
            table = try container.stream(
                named: tableName
            )
        } catch {
            throw WordDocumentTextExtractorError
                .invalidDocument
        }

        // fcClx/lcbClx are the 34th FibRgFcLcb97 pair. Later binary Word
        // versions retain this prefix for backward compatibility.
        let clxOffset = Int(
            try wordDocument.wordUInt32(
                at: 0x01A2
            )
        )
        let clxLength = Int(
            try wordDocument.wordUInt32(
                at: 0x01A6
            )
        )
        guard clxLength > 0,
              clxOffset >= 0,
              clxOffset <= table.count,
              clxLength <= table.count
                - clxOffset else {
            throw WordDocumentTextExtractorError
                .invalidDocument
        }
        let mainCharacterCount = Int(
            try wordDocument.wordUInt32(
                at: 0x004C
            )
        )
        return try extractPieceTableText(
            wordDocument: wordDocument,
            table: table,
            clxRange:
                clxOffset
                ..< clxOffset + clxLength,
            mainCharacterCount:
                mainCharacterCount
        )
    }

    private static func extractPieceTableText(
        wordDocument: Data,
        table: Data,
        clxRange: Range<Int>,
        mainCharacterCount: Int
    ) throws -> String {
        var cursor = clxRange.lowerBound
        while cursor < clxRange.upperBound,
              table[cursor] == 0x01 {
            let length = Int(
                try table.wordUInt16(
                    at: cursor + 1
                )
            )
            guard length <= clxRange.upperBound
                    - cursor - 3 else {
                throw WordDocumentTextExtractorError
                    .invalidDocument
            }
            cursor += 3 + length
        }
        guard cursor < clxRange.upperBound,
              table[cursor] == 0x02 else {
            throw WordDocumentTextExtractorError
                .invalidDocument
        }

        let pieceTableLength = Int(
            try table.wordUInt32(
                at: cursor + 1
            )
        )
        let pieceTableStart = cursor + 5
        guard pieceTableLength >= 16,
              pieceTableLength % 12 == 4,
              pieceTableStart
                <= clxRange.upperBound,
              pieceTableLength
                <= clxRange.upperBound
                    - pieceTableStart else {
            throw WordDocumentTextExtractorError
                .invalidDocument
        }

        let pieceCount =
            (pieceTableLength - 4) / 12
        guard pieceCount > 0,
              pieceCount <= 1_000_000 else {
            throw WordDocumentTextExtractorError
                .limitExceeded
        }
        let characterPositionsBytes =
            (pieceCount + 1) * 4
        let descriptorsStart =
            pieceTableStart
            + characterPositionsBytes
        guard descriptorsStart
                + pieceCount * 8
                == pieceTableStart
                    + pieceTableLength else {
            throw WordDocumentTextExtractorError
                .invalidDocument
        }

        var positions: [Int] = []
        positions.reserveCapacity(
            pieceCount + 1
        )
        for index in 0...pieceCount {
            let value = Int(
                try table.wordUInt32(
                    at: pieceTableStart
                        + index * 4
                )
            )
            guard value >= positions.last ?? 0
            else {
                throw WordDocumentTextExtractorError
                    .invalidDocument
            }
            positions.append(value)
        }

        let availableCharacters =
            positions.last ?? 0
        let characterLimit =
            mainCharacterCount > 0
            ? min(
                mainCharacterCount,
                availableCharacters
            )
            : availableCharacters
        guard characterLimit >= 0,
              characterLimit
                <= 64 * 1_024 * 1_024 else {
            throw WordDocumentTextExtractorError
                .limitExceeded
        }

        var result = ""
        result.reserveCapacity(
            min(
                characterLimit,
                maximumOutputBytes
            )
        )
        var resultByteCount = 0
        for index in 0..<pieceCount {
            let pieceStart = positions[index]
            let pieceEnd = positions[index + 1]
            guard pieceStart <= characterLimit
            else {
                break
            }
            let clippedEnd = min(
                pieceEnd,
                characterLimit
            )
            guard clippedEnd > pieceStart else {
                continue
            }

            let descriptorOffset =
                descriptorsStart + index * 8
            let rawFileOffset = try table
                .wordUInt32(
                    at: descriptorOffset + 2
                )
            guard rawFileOffset
                    & 0x8000_0000 == 0 else {
                throw WordDocumentTextExtractorError
                    .invalidDocument
            }
            let isCompressed = rawFileOffset
                & 0x4000_0000 != 0
            let maskedOffset = rawFileOffset
                & 0x3FFF_FFFF
            let baseOffset = isCompressed
                ? Int(maskedOffset / 2)
                : Int(maskedOffset)
            let characterCount =
                clippedEnd - pieceStart
            let byteCount = isCompressed
                ? characterCount
                : characterCount * 2
            guard baseOffset >= 0,
                  byteCount >= 0,
                  baseOffset
                    <= wordDocument.count,
                  byteCount
                    <= wordDocument.count
                        - baseOffset else {
                throw WordDocumentTextExtractorError
                    .invalidDocument
            }
            let range = baseOffset
                ..< baseOffset + byteCount
            let fragment: String
            if isCompressed {
                let bytes = wordDocument
                    .subdata(in: range)
                fragment = String(
                    data: bytes,
                    encoding: .windowsCP1252
                ) ?? String(
                    data: bytes,
                    encoding: .isoLatin1
                ) ?? ""
            } else {
                var units: [UInt16] = []
                units.reserveCapacity(
                    characterCount
                )
                for offset in stride(
                    from: range.lowerBound,
                    to: range.upperBound,
                    by: 2
                ) {
                    units.append(
                        try wordDocument
                            .wordUInt16(at: offset)
                    )
                }
                fragment = String(
                    decoding: units,
                    as: UTF16.self
                )
            }
            result += fragment
            resultByteCount +=
                fragment.utf8.count
            if resultByteCount
                > maximumOutputBytes * 2 {
                break
            }
        }
        return result
    }

    private static func normalize(
        _ source: String
    ) -> String {
        var mapped = ""
        mapped.reserveCapacity(source.count)
        for scalar in source.unicodeScalars {
            switch scalar.value {
            case 0x0007, 0x0009:
                mapped.append("\t")
            case 0x000A, 0x000B, 0x000D:
                mapped.append("\n")
            case 0x000C:
                mapped.append("\n\n")
            case 0x001E:
                mapped.append("\u{2011}")
            case 0x001F:
                mapped.append("\u{00AD}")
            case 0x0000...0x001F:
                continue
            default:
                mapped.unicodeScalars.append(
                    scalar
                )
            }
        }

        var lines: [String] = []
        var previousWasBlank = false
        for rawLine in mapped.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ) {
            let line = rawLine
                .trimmingCharacters(
                    in: .whitespaces
                )
            let isBlank = line.isEmpty
            if isBlank, previousWasBlank {
                continue
            }
            lines.append(line)
            previousWasBlank = isBlank
        }
        return lines.joined(separator: "\n")
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
    }

    private static func boundedText(
        _ text: String
    ) -> String {
        guard text.utf8.count
                > maximumOutputBytes else {
            return text
        }
        let marker = AppLocalization.string(
            "\n\n[Word 내용 일부 생략]"
        )
        let budget = max(
            0,
            maximumOutputBytes
                - marker.utf8.count
        )
        var output = ""
        output.reserveCapacity(budget)
        var byteCount = 0
        for character in text {
            let size = String(character)
                .utf8.count
            guard byteCount + size <= budget
            else {
                break
            }
            output.append(character)
            byteCount += size
        }
        return output + marker
    }
}

private nonisolated final class WordArchiveReader {
    private let archive: Archive
    private let entries: [String: Entry]
    private let maximumEntryBytes: Int

    var paths: [String] {
        Array(entries.keys)
    }

    init(
        data: Data,
        maximumEntries: Int,
        maximumExpandedBytes: Int,
        maximumEntryBytes: Int
    ) throws {
        do {
            archive = try Archive(
                data: data,
                accessMode: .read
            )
        } catch {
            throw WordDocumentTextExtractorError
                .invalidDocument
        }
        self.maximumEntryBytes =
            maximumEntryBytes

        var mapped: [String: Entry] = [:]
        var entryCount = 0
        var expandedBytes: UInt64 = 0
        for entry in archive {
            entryCount += 1
            guard entryCount <= maximumEntries,
                  entry.type != .symlink else {
                throw WordDocumentTextExtractorError
                    .limitExceeded
            }
            let addition = expandedBytes
                .addingReportingOverflow(
                    entry.uncompressedSize
                )
            guard !addition.overflow,
                  addition.partialValue
                    <= UInt64(
                        maximumExpandedBytes
                    ),
                  entry.uncompressedSize
                    <= UInt64(
                        maximumEntryBytes
                    ) else {
                throw WordDocumentTextExtractorError
                    .limitExceeded
            }
            expandedBytes = addition.partialValue
            guard entry.type == .file else {
                continue
            }
            let normalized = entry.path
                .replacingOccurrences(
                    of: "\\",
                    with: "/"
                )
            guard !normalized.hasPrefix("/"),
                  !normalized.split(
                    separator: "/"
                  ).contains(".."),
                  mapped[normalized] == nil
            else {
                throw WordDocumentTextExtractorError
                    .invalidDocument
            }
            mapped[normalized] = entry
        }
        entries = mapped
    }

    func contains(
        _ path: String
    ) -> Bool {
        entries[path] != nil
    }

    func data(
        at path: String
    ) throws -> Data {
        guard let entry = entries[path],
              entry.type == .file,
              entry.uncompressedSize
                <= UInt64(maximumEntryBytes)
        else {
            throw WordDocumentTextExtractorError
                .invalidDocument
        }
        var result = Data()
        result.reserveCapacity(
            Int(entry.uncompressedSize)
        )
        do {
            _ = try archive.extract(entry) {
                chunk in
                guard result.count
                        + chunk.count
                        <= maximumEntryBytes else {
                    throw WordDocumentTextExtractorError
                        .limitExceeded
                }
                result.append(chunk)
            }
        } catch let error
            as WordDocumentTextExtractorError {
            throw error
        } catch {
            throw WordDocumentTextExtractorError
                .invalidDocument
        }
        return result
    }
}

private nonisolated enum WordprocessingMLTextParser {
    static func parse(
        _ data: Data
    ) throws -> String {
        guard !containsWordASCII(
            "<!DOCTYPE",
            in: data
        ),
        !containsWordASCII(
            "<!ENTITY",
            in: data
        ) else {
            throw WordDocumentTextExtractorError
                .invalidDocument
        }

        let delegate =
            WordprocessingMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes =
            false
        parser.shouldResolveExternalEntities =
            false
        parser.delegate = delegate
        guard parser.parse() else {
            throw WordDocumentTextExtractorError
                .invalidDocument
        }
        return delegate.text
    }
}

private nonisolated final class
    WordprocessingMLParserDelegate:
        NSObject,
        XMLParserDelegate
{
    private var paragraphs: [String] = []
    private var currentParagraph = ""
    private var paragraphDepth = 0
    private var textDepth = 0

    var text: String {
        paragraphs.joined(separator: "\n")
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict:
            [String: String] = [:]
    ) {
        let name = localName(
            qName ?? elementName
        )
        switch name {
        case "p":
            if paragraphDepth == 0 {
                currentParagraph = ""
            }
            paragraphDepth += 1
        case "t":
            textDepth += 1
        case "tab":
            if paragraphDepth > 0 {
                currentParagraph.append("\t")
            }
        case "br", "cr":
            if paragraphDepth > 0 {
                currentParagraph.append("\n")
            }
        case "noBreakHyphen":
            if paragraphDepth > 0 {
                currentParagraph.append("\u{2011}")
            }
        case "softHyphen":
            if paragraphDepth > 0 {
                currentParagraph.append("\u{00AD}")
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        guard paragraphDepth > 0,
              textDepth > 0 else {
            return
        }
        currentParagraph += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(
            qName ?? elementName
        )
        switch name {
        case "t":
            textDepth = max(0, textDepth - 1)
        case "p":
            paragraphDepth = max(
                0,
                paragraphDepth - 1
            )
            if paragraphDepth == 0 {
                let paragraph = currentParagraph
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                if !paragraph.isEmpty {
                    paragraphs.append(paragraph)
                }
                currentParagraph = ""
            }
        default:
            break
        }
    }

    private func localName(
        _ value: String
    ) -> String {
        value.split(separator: ":")
            .last.map(String.init)
            ?? value
    }
}

private nonisolated func containsWordASCII(
    _ needle: String,
    in data: Data
) -> Bool {
    let pattern = Array(
        needle.uppercased().utf8
    )
    guard !pattern.isEmpty,
          data.count >= pattern.count else {
        return false
    }
    return data.withUnsafeBytes {
        rawBuffer in
        let bytes = rawBuffer.bindMemory(
            to: UInt8.self
        )
        for start in 0...(
            bytes.count - pattern.count
        ) {
            var matches = true
            for offset in pattern.indices {
                let byte = bytes[
                    start + offset
                ]
                let upper = byte >= 0x61
                    && byte <= 0x7A
                    ? byte - 0x20
                    : byte
                if upper != pattern[offset] {
                    matches = false
                    break
                }
            }
            if matches {
                return true
            }
        }
        return false
    }
}

private extension Data {
    nonisolated func wordUInt16(
        at offset: Int
    ) throws -> UInt16 {
        guard offset >= 0,
              offset + 2 <= count else {
            throw WordDocumentTextExtractorError
                .invalidDocument
        }
        return UInt16(self[offset])
            | UInt16(self[offset + 1]) << 8
    }

    nonisolated func wordUInt32(
        at offset: Int
    ) throws -> UInt32 {
        guard offset >= 0,
              offset + 4 <= count else {
            throw WordDocumentTextExtractorError
                .invalidDocument
        }
        return UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}
