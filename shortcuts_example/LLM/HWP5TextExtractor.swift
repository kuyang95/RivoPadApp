import Foundation
import zlib

/// Text-only HWP 5.x reader based on Hancom's published binary format.
/// It does not execute scripts or load embedded OLE objects and rejects
/// password-protected, distribution, DRM, and certificate-encrypted files.
nonisolated enum HWP5TextExtractor {
    static let maximumDocumentBytes =
        20 * 1_024 * 1_024
    static let maximumSections = 64
    static let maximumSectionBytes =
        16 * 1_024 * 1_024
    static let maximumExpandedBytes =
        32 * 1_024 * 1_024
    static let maximumOutputBytes =
        1_024 * 1_024
    private static let paragraphTextTag:
        UInt32 = 0x43

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

        let container: OLECompoundFile
        do {
            container =
                try OLECompoundFile(
                    data: data,
                    limits: .init(
                        maximumFileBytes:
                            maximumDocumentBytes,
                        maximumDirectoryEntries:
                            4_096,
                        maximumStreamBytes:
                            maximumSectionBytes,
                        maximumChainSectors:
                            65_536
                    )
                )
        } catch
            OLECompoundFileError
                .limitExceeded {
            throw ChatAttachmentError
                .hwpLimitExceeded
        } catch {
            throw ChatAttachmentError
                .invalidHWP
        }

        let header: Data
        do {
            header = try container.stream(
                named: "FileHeader"
            )
        } catch {
            throw ChatAttachmentError
                .invalidHWP
        }
        guard header.count >= 48,
              String(
                  data: header.prefix(17),
                  encoding: .ascii
              ) == "HWP Document File"
        else {
            throw ChatAttachmentError
                .invalidHWP
        }
        let version =
            try header.hwpUInt32(at: 32)
        guard version >> 24 == 5 else {
            throw ChatAttachmentError
                .unsupportedHWPVersion
        }
        let properties =
            try header.hwpUInt32(at: 36)
        let unsupportedSecurityFlags:
            UInt32 =
                (1 << 1)  // password
                | (1 << 2) // distribution
                | (1 << 4) // DRM
                | (1 << 8) // certificate encryption
                | (1 << 10) // certificate DRM
                | (1 << 13) // privacy protection
        let encryptionVersion =
            try header.hwpUInt32(at: 44)
        guard properties
                & unsupportedSecurityFlags
                == 0,
              encryptionVersion == 0
        else {
            throw ChatAttachmentError
                .encryptedHWP
        }
        let isCompressed =
            properties & 0x01 != 0

        let sections = container.streamNames
            .compactMap {
                name
                -> (
                    index: Int,
                    name: String
                )? in
                let prefix =
                    "bodytext/section"
                guard name.hasPrefix(prefix)
                else {
                    return nil
                }
                let suffix = name.dropFirst(
                    prefix.count
                )
                guard !suffix.isEmpty,
                      suffix.allSatisfy(
                          \.isNumber
                      ),
                      let index = Int(
                          suffix
                      )
                else {
                    return nil
                }
                return (index, name)
            }
            .sorted {
                $0.index < $1.index
            }
        guard !sections.isEmpty else {
            throw ChatAttachmentError
                .invalidHWP
        }
        guard sections.count
                <= maximumSections else {
            throw ChatAttachmentError
                .hwpLimitExceeded
        }

        var paragraphs: [String] = []
        var expandedByteCount = 0
        var outputByteCount = 0
        var didTruncate = false

        sectionLoop:
        for section in sections {
            let stored: Data
            do {
                stored = try container.stream(
                    named: section.name
                )
            } catch
                OLECompoundFileError
                    .limitExceeded {
                throw ChatAttachmentError
                    .hwpLimitExceeded
            } catch {
                throw ChatAttachmentError
                    .invalidHWP
            }
            let body: Data
            if isCompressed {
                body = try inflateRawDeflate(
                    stored,
                    maximumBytes:
                        maximumSectionBytes
                )
            } else {
                body = stored
            }
            expandedByteCount += body.count
            guard expandedByteCount
                    <= maximumExpandedBytes
            else {
                throw ChatAttachmentError
                    .hwpLimitExceeded
            }

            var offset = 0
            while offset < body.count {
                guard offset + 4
                        <= body.count else {
                    throw ChatAttachmentError
                        .invalidHWP
                }
                let recordHeader =
                    try body.hwpUInt32(
                        at: offset
                    )
                offset += 4
                let tag =
                    recordHeader & 0x03FF
                var payloadSize = Int(
                    recordHeader >> 20
                )
                if payloadSize == 0x0FFF {
                    guard offset + 4
                            <= body.count else {
                        throw ChatAttachmentError
                            .invalidHWP
                    }
                    payloadSize = Int(
                        try body.hwpUInt32(
                            at: offset
                        )
                    )
                    offset += 4
                }
                guard payloadSize >= 0,
                      payloadSize
                        <= maximumSectionBytes,
                      offset + payloadSize
                        <= body.count else {
                    throw ChatAttachmentError
                        .invalidHWP
                }

                if tag
                    == paragraphTextTag {
                    let paragraph =
                        try paragraphText(
                            body.subdata(
                                in:
                                    offset..<(
                                        offset
                                        + payloadSize
                                    )
                            )
                        )
                    if !paragraph.isEmpty {
                        let additionBytes =
                            paragraph.utf8.count
                            + (
                                paragraphs.isEmpty
                                    ? 0
                                    : 1
                            )
                        if outputByteCount
                            + additionBytes
                            > maximumOutputBytes {
                            didTruncate = true
                            break sectionLoop
                        }
                        paragraphs.append(
                            paragraph
                        )
                        outputByteCount +=
                            additionBytes
                    }
                }
                offset += payloadSize
            }
        }

        guard !paragraphs.isEmpty else {
            throw ChatAttachmentError
                .documentHasNoText
        }
        var result = paragraphs.joined(
            separator: "\n"
        )
        if didTruncate {
            result += AppLocalization.string(
                "\n\n[HWP 내용 일부 생략]"
            )
        }
        return result
    }

    private static func paragraphText(
        _ data: Data
    ) throws -> String {
        guard data.count % 2 == 0 else {
            throw ChatAttachmentError
                .invalidHWP
        }
        var units: [UInt16] = []
        units.reserveCapacity(
            data.count / 2
        )
        var offset = 0
        while offset < data.count {
            units.append(
                try data.hwpUInt16(
                    at: offset
                )
            )
            offset += 2
        }

        var output: [UInt16] = []
        output.reserveCapacity(units.count)
        var index = 0
        while index < units.count {
            let code = units[index]
            if code > 31 {
                output.append(code)
                index += 1
                continue
            }

            switch code {
            case 9:
                output.append(9)
                guard index + 8
                        <= units.count else {
                    throw ChatAttachmentError
                        .invalidHWP
                }
                index += 8
            case 10:
                output.append(10)
                index += 1
            case 13:
                index += 1
            case 24:
                output.append(45)
                index += 1
            case 30, 31:
                output.append(32)
                index += 1
            case 1...8,
                 11...23:
                guard index + 8
                        <= units.count else {
                    throw ChatAttachmentError
                        .invalidHWP
                }
                index += 8
            default:
                index += 1
            }
        }
        return String(
            decoding: output,
            as: UTF16.self
        )
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
    }

    private static func inflateRawDeflate(
        _ compressed: Data,
        maximumBytes: Int
    ) throws -> Data {
        guard !compressed.isEmpty,
              maximumBytes > 0 else {
            throw ChatAttachmentError
                .invalidHWP
        }
        var stream = z_stream()
        let initialization = inflateInit2_(
            &stream,
            -MAX_WBITS,
            ZLIB_VERSION,
            Int32(
                MemoryLayout<z_stream>
                    .size
            )
        )
        guard initialization == Z_OK else {
            throw ChatAttachmentError
                .invalidHWP
        }
        defer {
            inflateEnd(&stream)
        }

        return try compressed
            .withUnsafeBytes {
                rawInput in
                let input = rawInput
                    .bindMemory(to: Bytef.self)
                guard let base =
                        input.baseAddress else {
                    throw ChatAttachmentError
                        .invalidHWP
                }
                stream.next_in =
                    UnsafeMutablePointer(
                        mutating: base
                    )
                stream.avail_in =
                    uInt(compressed.count)

                var output = Data()
                var chunk = [UInt8](
                    repeating: 0,
                    count: 64 * 1_024
                )
                while true {
                    let status = chunk
                        .withUnsafeMutableBytes {
                            rawOutput -> Int32 in
                            let bytes = rawOutput
                                .bindMemory(
                                    to: Bytef.self
                                )
                            stream.next_out =
                                bytes.baseAddress
                            stream.avail_out =
                                uInt(
                                    bytes.count
                                )
                            return inflate(
                                &stream,
                                Z_NO_FLUSH
                            )
                        }
                    let produced =
                        chunk.count
                        - Int(stream.avail_out)
                    guard output.count
                            + produced
                            <= maximumBytes
                    else {
                        throw ChatAttachmentError
                            .hwpLimitExceeded
                    }
                    if produced > 0 {
                        output.append(
                            contentsOf:
                                chunk.prefix(
                                    produced
                                )
                        )
                    }
                    if status == Z_STREAM_END {
                        guard stream.avail_in
                                == 0 else {
                            throw ChatAttachmentError
                                .invalidHWP
                        }
                        return output
                    }
                    guard status == Z_OK,
                          produced > 0
                            || stream.avail_in
                                > 0
                    else {
                        throw ChatAttachmentError
                            .invalidHWP
                    }
                }
            }
    }
}

private extension Data {
    nonisolated func hwpUInt16(
        at offset: Int
    ) throws -> UInt16 {
        guard offset >= 0,
              offset + 2 <= count else {
            throw ChatAttachmentError
                .invalidHWP
        }
        return UInt16(self[offset])
            | UInt16(self[offset + 1])
                << 8
    }

    nonisolated func hwpUInt32(
        at offset: Int
    ) throws -> UInt32 {
        guard offset >= 0,
              offset + 4 <= count else {
            throw ChatAttachmentError
                .invalidHWP
        }
        return UInt32(self[offset])
            | UInt32(self[offset + 1])
                << 8
            | UInt32(self[offset + 2])
                << 16
            | UInt32(self[offset + 3])
                << 24
    }
}
