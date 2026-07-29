import Foundation
import zlib

nonisolated enum EPUBArchiveError: LocalizedError {
    case invalidArchive
    case zip64Unsupported
    case encryptedEntry
    case unsupportedCompression(method: UInt16)
    case unsafePath
    case entryTooLarge
    case decompressionFailed
    case checksumMismatch
    case missingEntry(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "올바른 EPUB ZIP 파일이 아닙니다."
        case .zip64Unsupported:
            return "ZIP64 형식의 EPUB은 아직 지원하지 않습니다."
        case .encryptedEntry:
            return "암호화된 EPUB은 열 수 없습니다."
        case .unsupportedCompression(let method):
            return "지원하지 않는 ZIP 압축 방식입니다: \(method)"
        case .unsafePath:
            return "EPUB 안에 안전하지 않은 파일 경로가 있습니다."
        case .entryTooLarge:
            return "EPUB 내부 파일이 너무 큽니다."
        case .decompressionFailed:
            return "EPUB 압축을 해제하지 못했습니다."
        case .checksumMismatch:
            return "EPUB 내부 파일이 손상되었습니다."
        case .missingEntry(let path):
            return "EPUB 내부 파일을 찾을 수 없습니다: \(path)"
        }
    }
}

nonisolated struct EPUBArchive: Sendable {
    private struct Entry: Sendable {
        let path: String
        let flags: UInt16
        let compressionMethod: UInt16
        let checksum: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private static let endSignature: UInt32 = 0x0605_4B50
    private static let centralSignature: UInt32 = 0x0201_4B50
    private static let localSignature: UInt32 = 0x0403_4B50
    private static let maximumEntrySize = 100 * 1_024 * 1_024

    private let data: Data
    private let entries: [String: Entry]

    init(data: Data) throws {
        self.data = data
        self.entries = try Self.readEntries(from: data)
    }

    var paths: [String] {
        entries.keys.sorted()
    }

    func contains(_ path: String) -> Bool {
        guard let normalized = try? Self.normalizedPath(path) else {
            return false
        }
        return entries[normalized] != nil
    }

    func data(at path: String) throws -> Data {
        let normalized = try Self.normalizedPath(path)
        guard let entry = entries[normalized] else {
            throw EPUBArchiveError.missingEntry(path)
        }
        guard entry.flags & 0x0001 == 0 else {
            throw EPUBArchiveError.encryptedEntry
        }
        guard entry.uncompressedSize <= Self.maximumEntrySize else {
            throw EPUBArchiveError.entryTooLarge
        }

        let localOffset = entry.localHeaderOffset
        guard try data.uint32LE(at: localOffset)
                == Self.localSignature else {
            throw EPUBArchiveError.invalidArchive
        }
        let nameLength = Int(
            try data.uint16LE(at: localOffset + 26)
        )
        let extraLength = Int(
            try data.uint16LE(at: localOffset + 28)
        )
        let contentOffset = localOffset + 30
            + nameLength + extraLength
        let contentEnd = contentOffset + entry.compressedSize
        guard contentOffset >= 0,
              contentEnd <= data.count else {
            throw EPUBArchiveError.invalidArchive
        }
        let compressed = data.subdata(
            in: contentOffset ..< contentEnd
        )

        let result: Data
        switch entry.compressionMethod {
        case 0:
            result = compressed
        case 8:
            result = try Self.inflateRaw(
                compressed,
                expectedSize: entry.uncompressedSize
            )
        default:
            throw EPUBArchiveError.unsupportedCompression(
                method: entry.compressionMethod
            )
        }
        guard result.count == entry.uncompressedSize else {
            throw EPUBArchiveError.decompressionFailed
        }
        guard Self.checksum(of: result) == entry.checksum else {
            throw EPUBArchiveError.checksumMismatch
        }
        return result
    }

    func text(at path: String) throws -> String {
        let entryData = try data(at: path)
        for encoding in [
            String.Encoding.utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian
        ] {
            if let text = String(
                data: entryData,
                encoding: encoding
            ) {
                return text
            }
        }
        throw LocalDocumentImportError.textDecodingFailed
    }

    static func normalizedPath(_ rawPath: String) throws -> String {
        let decoded = rawPath.removingPercentEncoding ?? rawPath
        let components = decoded
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
        var normalized: [Substring] = []
        for component in components {
            switch component {
            case ".":
                continue
            case "..":
                guard !normalized.isEmpty else {
                    throw EPUBArchiveError.unsafePath
                }
                normalized.removeLast()
            default:
                normalized.append(component)
            }
        }
        guard !normalized.isEmpty else {
            throw EPUBArchiveError.unsafePath
        }
        return normalized.joined(separator: "/")
    }

    private static func readEntries(
        from data: Data
    ) throws -> [String: Entry] {
        guard let endOffset = findEndRecord(in: data) else {
            throw EPUBArchiveError.invalidArchive
        }
        let diskNumber = try data.uint16LE(at: endOffset + 4)
        let centralDiskNumber = try data.uint16LE(
            at: endOffset + 6
        )
        let diskEntryCount = try data.uint16LE(
            at: endOffset + 8
        )
        let entryCount = Int(
            try data.uint16LE(at: endOffset + 10)
        )
        let centralSize = try data.uint32LE(
            at: endOffset + 12
        )
        let centralOffset = try data.uint32LE(
            at: endOffset + 16
        )
        guard centralSize != UInt32.max,
              centralOffset != UInt32.max,
              entryCount != Int(UInt16.max) else {
            throw EPUBArchiveError.zip64Unsupported
        }
        guard diskNumber == 0,
              centralDiskNumber == 0,
              Int(diskEntryCount) == entryCount else {
            throw EPUBArchiveError.invalidArchive
        }
        let centralEnd = Int(centralOffset)
            + Int(centralSize)
        guard centralEnd <= endOffset else {
            throw EPUBArchiveError.invalidArchive
        }

        var result: [String: Entry] = [:]
        var offset = Int(centralOffset)
        for _ in 0 ..< entryCount {
            guard try data.uint32LE(at: offset)
                    == centralSignature else {
                throw EPUBArchiveError.invalidArchive
            }
            let flags = try data.uint16LE(at: offset + 8)
            let method = try data.uint16LE(at: offset + 10)
            let checksum = try data.uint32LE(at: offset + 16)
            let compressedSize = try data.uint32LE(
                at: offset + 20
            )
            let uncompressedSize = try data.uint32LE(
                at: offset + 24
            )
            let nameLength = Int(
                try data.uint16LE(at: offset + 28)
            )
            let extraLength = Int(
                try data.uint16LE(at: offset + 30)
            )
            let commentLength = Int(
                try data.uint16LE(at: offset + 32)
            )
            let localHeaderOffset = try data.uint32LE(
                at: offset + 42
            )
            guard compressedSize != UInt32.max,
                  uncompressedSize != UInt32.max,
                  localHeaderOffset != UInt32.max else {
                throw EPUBArchiveError.zip64Unsupported
            }

            let nameStart = offset + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= data.count else {
                throw EPUBArchiveError.invalidArchive
            }
            let nameData = data.subdata(
                in: nameStart ..< nameEnd
            )
            guard let rawName = String(
                data: nameData,
                encoding: .utf8
            ) else {
                throw EPUBArchiveError.invalidArchive
            }

            if !rawName.hasSuffix("/") {
                let path = try normalizedPath(rawName)
                result[path] = Entry(
                    path: path,
                    flags: flags,
                    compressionMethod: method,
                    checksum: checksum,
                    compressedSize: Int(compressedSize),
                    uncompressedSize: Int(uncompressedSize),
                    localHeaderOffset: Int(localHeaderOffset)
                )
            }
            offset = nameEnd + extraLength + commentLength
        }
        guard offset <= centralEnd else {
            throw EPUBArchiveError.invalidArchive
        }
        guard !result.isEmpty else {
            throw EPUBArchiveError.invalidArchive
        }
        return result
    }

    private static func findEndRecord(in data: Data) -> Int? {
        guard data.count >= 22 else {
            return nil
        }
        let lowerBound = max(0, data.count - 65_557)
        for offset in stride(
            from: data.count - 22,
            through: lowerBound,
            by: -1
        ) {
            guard (try? data.uint32LE(at: offset))
                    == endSignature,
                  let commentLength = try? data.uint16LE(
                      at: offset + 20
                  ) else {
                continue
            }
            if offset + 22 + Int(commentLength) == data.count {
                return offset
            }
        }
        return nil
    }

    private static func inflateRaw(
        _ compressed: Data,
        expectedSize: Int
    ) throws -> Data {
        guard expectedSize > 0 else {
            return Data()
        }
        var stream = z_stream()
        let initialization = inflateInit2_(
            &stream,
            -MAX_WBITS,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initialization == Z_OK else {
            throw EPUBArchiveError.decompressionFailed
        }
        defer {
            inflateEnd(&stream)
        }

        var output = Data(count: expectedSize)
        let status = compressed.withUnsafeBytes { inputBytes in
            output.withUnsafeMutableBytes { outputBytes in
                stream.next_in = UnsafeMutablePointer<Bytef>(
                    mutating: inputBytes.bindMemory(
                        to: Bytef.self
                    ).baseAddress
                )
                stream.avail_in = uInt(compressed.count)
                stream.next_out = outputBytes.bindMemory(
                    to: Bytef.self
                ).baseAddress
                stream.avail_out = uInt(expectedSize)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END,
              Int(stream.total_out) == expectedSize else {
            throw EPUBArchiveError.decompressionFailed
        }
        return output
    }

    private static func checksum(of data: Data) -> UInt32 {
        data.withUnsafeBytes { bytes in
            UInt32(
                crc32(
                    0,
                    bytes.bindMemory(to: Bytef.self).baseAddress,
                    uInt(data.count)
                )
            )
        }
    }
}

private extension Data {
    nonisolated func uint16LE(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else {
            throw EPUBArchiveError.invalidArchive
        }
        return UInt16(self[offset])
            | UInt16(self[offset + 1]) << 8
    }

    nonisolated func uint32LE(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else {
            throw EPUBArchiveError.invalidArchive
        }
        return UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}
