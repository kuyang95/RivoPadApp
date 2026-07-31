import Foundation
import ZIPFoundation

/// Bounded, text-only reader for Hancom's open HWPX/OWPML package format.
///
/// HWPX files are ZIP packages. This reader follows the section order in
/// `Contents/content.hpf`, reads only `Contents/section*.xml`, and collects
/// paragraph text from `hp:t`. It never evaluates scripts, macros, embedded
/// objects, links, or binary payloads.
nonisolated enum HWPXTextExtractor {
    static let maximumDocumentBytes =
        20 * 1_024 * 1_024
    static let maximumArchiveEntries = 4_096
    static let maximumExpandedBytes =
        64 * 1_024 * 1_024
    static let maximumEntryBytes =
        16 * 1_024 * 1_024
    static let maximumSections = 64
    static let maximumOutputBytes =
        1_024 * 1_024

    private static let expectedMIMEType =
        "application/hwp+zip"

    static func extract(
        from data: Data
    ) throws -> String {
        guard data.count
                <= maximumDocumentBytes else {
            throw ChatAttachmentError
                .fileTooLarge(
                    maximumMegabytes:
                        maximumDocumentBytes
                        / 1_024
                        / 1_024
                )
        }
        let reader = try HWPXArchiveReader(
            data: data,
            maximumEntries:
                maximumArchiveEntries,
            maximumExpandedBytes:
                maximumExpandedBytes,
            maximumEntryBytes:
                maximumEntryBytes
        )
        guard reader.contains("mimetype"),
              let mimeType = String(
                  data: try reader.data(
                      at: "mimetype"
                  ),
                  encoding: .utf8
              )?
              .trimmingCharacters(
                  in: .whitespacesAndNewlines
              ),
              mimeType == expectedMIMEType
        else {
            throw ChatAttachmentError
                .invalidHWPX
        }

        let sectionPaths = try orderedSectionPaths(
            in: reader
        )
        guard !sectionPaths.isEmpty else {
            throw ChatAttachmentError
                .invalidHWPX
        }
        guard sectionPaths.count
                <= maximumSections else {
            throw ChatAttachmentError
                .hwpxLimitExceeded
        }

        var paragraphs: [String] = []
        var remainingOutputBytes =
            maximumOutputBytes
        var didTruncate = false

        for path in sectionPaths {
            guard remainingOutputBytes > 0
            else {
                didTruncate = true
                break
            }
            let result = try HWPXSectionXML
                .parse(
                    try reader.data(
                        at: path
                    ),
                    maximumOutputBytes:
                        remainingOutputBytes
                )
            paragraphs.append(
                contentsOf:
                    result.paragraphs
            )
            remainingOutputBytes -=
                result.outputBytes
            didTruncate =
                didTruncate
                || result.didTruncate
        }

        var text = paragraphs
            .filter {
                !$0.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            }
            .joined(separator: "\n")
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard !text.isEmpty else {
            throw ChatAttachmentError
                .documentHasNoText
        }
        if didTruncate {
            text += AppLocalization.string(
                "\n\n[HWPX 내용 일부 생략]"
            )
        }
        return text
    }

    private static func orderedSectionPaths(
        in reader: HWPXArchiveReader
    ) throws -> [String] {
        let fallback = reader.paths
            .compactMap {
                path -> (
                    index: Int,
                    path: String
                )? in
                guard let index =
                        sectionIndex(
                            for: path
                        ) else {
                    return nil
                }
                return (index, path)
            }
            .sorted {
                if $0.index != $1.index {
                    return $0.index < $1.index
                }
                return $0.path < $1.path
            }
            .map(\.path)

        guard reader.contains(
            "Contents/content.hpf"
        ) else {
            return fallback
        }
        let package: HWPXPackage
        do {
            package = try HWPXPackageXML
                .parse(
                    try reader.data(
                        at:
                            "Contents/content.hpf"
                    )
                )
        } catch {
            return fallback
        }

        var ordered: [String] = []
        var seen: Set<String> = []
        for identifier in package.spineIDs {
            guard let href =
                    package.manifest[
                        identifier
                    ],
                  let path =
                    normalizedSectionPath(
                        href
                    ),
                  reader.contains(path),
                  seen.insert(path).inserted
            else {
                continue
            }
            ordered.append(path)
        }
        if ordered.isEmpty {
            for href in package
                .manifest
                .values {
                guard let path =
                        normalizedSectionPath(
                            href
                        ),
                      reader.contains(path),
                      seen.insert(path).inserted
                else {
                    continue
                }
                ordered.append(path)
            }
            ordered.sort {
                (
                    sectionIndex(for: $0)
                    ?? Int.max,
                    $0
                ) < (
                    sectionIndex(for: $1)
                    ?? Int.max,
                    $1
                )
            }
        }
        return ordered.isEmpty
            ? fallback
            : ordered
    }

    private static func normalizedSectionPath(
        _ rawHref: String
    ) -> String? {
        let decoded =
            rawHref.removingPercentEncoding
            ?? rawHref
        let slashNormalized = decoded
            .replacingOccurrences(
                of: "\\",
                with: "/"
            )
        let candidate: String
        if slashNormalized.hasPrefix("/") {
            candidate = String(
                slashNormalized.dropFirst()
            )
        } else if slashNormalized
                    .hasPrefix("Contents/") {
            candidate = slashNormalized
        } else {
            candidate =
                "Contents/"
                + slashNormalized
        }

        var components: [Substring] = []
        for component in candidate.split(
            separator: "/",
            omittingEmptySubsequences: true
        ) {
            switch component {
            case ".":
                continue
            case "..":
                guard !components.isEmpty
                else {
                    return nil
                }
                components.removeLast()
            default:
                components.append(component)
            }
        }
        let normalized = components
            .joined(separator: "/")
        guard normalized.hasPrefix(
            "Contents/"
        ),
        sectionIndex(for: normalized) != nil
        else {
            return nil
        }
        return normalized
    }

    private static func sectionIndex(
        for path: String
    ) -> Int? {
        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: true
        )
        guard components.count >= 2,
              components.first?
                .lowercased()
                == "contents",
              let filename =
                components.last?
                .lowercased(),
              filename.hasPrefix("section"),
              filename.hasSuffix(".xml")
        else {
            return nil
        }
        let number = filename
            .dropFirst("section".count)
            .dropLast(".xml".count)
        guard !number.isEmpty,
              number.allSatisfy(\.isNumber)
        else {
            return nil
        }
        return Int(number)
    }
}

private nonisolated final class
    HWPXArchiveReader
{
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
            throw ChatAttachmentError
                .invalidHWPX
        }
        self.maximumEntryBytes =
            maximumEntryBytes

        var mapped: [String: Entry] = [:]
        var entryCount = 0
        var expandedBytes: UInt64 = 0
        for entry in archive {
            entryCount += 1
            guard entryCount <= maximumEntries,
                  entry.type != .symlink
            else {
                throw ChatAttachmentError
                    .hwpxLimitExceeded
            }
            expandedBytes +=
                entry.uncompressedSize
            guard expandedBytes
                    <= UInt64(
                        maximumExpandedBytes
                    ),
                  entry.uncompressedSize
                    <= UInt64(
                        maximumEntryBytes
                    )
            else {
                throw ChatAttachmentError
                    .hwpxLimitExceeded
            }
            guard entry.type == .file else {
                continue
            }
            let normalized = entry.path
                .replacingOccurrences(
                    of: "\\",
                    with: "/"
                )
            guard !normalized.hasPrefix("/"),
                  !normalized
                    .split(separator: "/")
                    .contains("..")
            else {
                throw ChatAttachmentError
                    .invalidHWPX
            }
            guard mapped[normalized] == nil
            else {
                throw ChatAttachmentError
                    .invalidHWPX
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
                <= UInt64(
                    maximumEntryBytes
                )
        else {
            throw ChatAttachmentError
                .invalidHWPX
        }
        var result = Data()
        result.reserveCapacity(
            Int(entry.uncompressedSize)
        )
        do {
            _ = try archive.extract(
                entry
            ) { chunk in
                guard result.count
                        + chunk.count
                        <= maximumEntryBytes
                else {
                    throw ChatAttachmentError
                        .hwpxLimitExceeded
                }
                result.append(chunk)
            }
        } catch let error
            as ChatAttachmentError {
            throw error
        } catch {
            throw ChatAttachmentError
                .invalidHWPX
        }
        return result
    }
}

private nonisolated struct HWPXPackage {
    let manifest: [String: String]
    let spineIDs: [String]
}

private nonisolated enum HWPXPackageXML {
    static func parse(
        _ data: Data
    ) throws -> HWPXPackage {
        let delegate =
            HWPXPackageParserDelegate()
        try parseHWPXXML(
            data,
            delegate: delegate
        )
        return HWPXPackage(
            manifest:
                delegate.manifest,
            spineIDs:
                delegate.spineIDs
        )
    }
}

private nonisolated final class
    HWPXPackageParserDelegate:
        NSObject,
        XMLParserDelegate
{
    var manifest: [String: String] = [:]
    var spineIDs: [String] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName:
            String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict:
            [String: String] = [:]
    ) {
        switch hwpxLocalXMLName(
            qName ?? elementName
        ) {
        case "item":
            guard let identifier =
                    attributeDict["id"],
                  let href =
                    attributeDict["href"],
                  !identifier.isEmpty,
                  !href.isEmpty
            else {
                return
            }
            manifest[identifier] = href
        case "itemref":
            guard let identifier =
                    attributeDict["idref"],
                  !identifier.isEmpty
            else {
                return
            }
            spineIDs.append(identifier)
        default:
            break
        }
    }
}

private nonisolated struct
    HWPXSectionParseResult
{
    let paragraphs: [String]
    let outputBytes: Int
    let didTruncate: Bool
}

private nonisolated enum HWPXSectionXML {
    static func parse(
        _ data: Data,
        maximumOutputBytes: Int
    ) throws -> HWPXSectionParseResult {
        let delegate =
            HWPXSectionParserDelegate(
                maximumOutputBytes:
                    maximumOutputBytes
            )
        try parseHWPXXML(
            data,
            delegate: delegate
        )
        delegate.finish()
        return HWPXSectionParseResult(
            paragraphs:
                delegate.paragraphs,
            outputBytes:
                delegate.outputBytes,
            didTruncate:
                delegate.didTruncate
        )
    }
}

private nonisolated final class
    HWPXSectionParserDelegate:
        NSObject,
        XMLParserDelegate
{
    let maximumOutputBytes: Int

    var paragraphs: [String] = []
    var outputBytes = 0
    var didTruncate = false

    private var paragraphDepth = 0
    private var textDepth = 0
    private var currentParagraph = ""
    private var currentParagraphBytes = 0

    init(maximumOutputBytes: Int) {
        self.maximumOutputBytes =
            maximumOutputBytes
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName:
            String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict:
            [String: String] = [:]
    ) {
        switch hwpxLocalXMLName(
            qName ?? elementName
        ) {
        case "p":
            if paragraphDepth == 0 {
                currentParagraph = ""
                currentParagraphBytes = 0
            }
            paragraphDepth += 1
        case "t":
            textDepth += 1
        case "tab":
            if textDepth > 0 {
                append("\t")
            }
        case "lineBreak":
            if textDepth > 0 {
                append("\n")
            }
        case "hyphen", "hypen":
            if textDepth > 0 {
                append("-")
            }
        case "nbSpace":
            if textDepth > 0 {
                append("\u{00A0}")
            }
        case "fwSpace":
            if textDepth > 0 {
                append("\u{3000}")
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        guard textDepth > 0
        else {
            return
        }
        append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName:
            String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch hwpxLocalXMLName(
            qName ?? elementName
        ) {
        case "t":
            textDepth = max(
                textDepth - 1,
                0
            )
        case "p":
            paragraphDepth = max(
                paragraphDepth - 1,
                0
            )
            if paragraphDepth == 0 {
                commitCurrentParagraph()
            }
        default:
            break
        }
    }

    func finish() {
        if !currentParagraph.isEmpty {
            commitCurrentParagraph()
        }
    }

    private func append(
        _ string: String
    ) {
        guard !string.isEmpty
        else {
            return
        }
        let available =
            maximumOutputBytes
            - outputBytes
            - currentParagraphBytes
        guard available > 0
        else {
            didTruncate = true
            return
        }

        var appended = ""
        var appendedBytes = 0
        for scalar in string.unicodeScalars {
            let scalarString = String(scalar)
            let byteCount =
                scalarString.utf8.count
            guard appendedBytes
                    + byteCount
                    <= available
            else {
                didTruncate = true
                break
            }
            appended.unicodeScalars
                .append(scalar)
            appendedBytes += byteCount
        }
        currentParagraph += appended
        currentParagraphBytes +=
            appendedBytes
    }

    private func commitCurrentParagraph() {
        defer {
            currentParagraph = ""
            currentParagraphBytes = 0
        }
        let normalized = currentParagraph
            .replacingOccurrences(
                of: "\r\n",
                with: "\n"
            )
            .replacingOccurrences(
                of: "\r",
                with: "\n"
            )
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard !normalized.isEmpty
        else {
            return
        }
        let separatorBytes =
            paragraphs.isEmpty ? 0 : 1
        let required =
            normalized.utf8.count
            + separatorBytes
        guard outputBytes + required
                <= maximumOutputBytes
        else {
            didTruncate = true
            return
        }
        paragraphs.append(normalized)
        outputBytes += required
    }
}

private nonisolated func parseHWPXXML(
    _ data: Data,
    delegate: XMLParserDelegate
) throws {
    guard !hwpxContainsASCII(
        "<!DOCTYPE",
        in: data
    ),
    !hwpxContainsASCII(
        "<!ENTITY",
        in: data
    ) else {
        throw ChatAttachmentError
            .invalidHWPX
    }
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = true
    parser.shouldResolveExternalEntities =
        false
    parser.delegate = delegate
    guard parser.parse() else {
        throw ChatAttachmentError
            .invalidHWPX
    }
}

private nonisolated func hwpxContainsASCII(
    _ needle: String,
    in data: Data
) -> Bool {
    let pattern = Array(
        needle.uppercased().utf8
    )
    guard !pattern.isEmpty,
          data.count >= pattern.count
    else {
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
                let byte =
                    bytes[start + offset]
                let upper =
                    byte >= 0x61
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

private nonisolated func hwpxLocalXMLName(
    _ value: String
) -> String {
    value.split(separator: ":")
        .last
        .map(String.init)
        ?? value
}
