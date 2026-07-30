import Foundation

nonisolated enum OLECompoundFileError:
    Error,
    Equatable,
    Sendable
{
    case invalidFile
    case limitExceeded
    case streamNotFound
}

/// A bounded, read-only parser for Microsoft Compound Binary File (CFB/OLE)
/// containers. It intentionally exposes only named stream bytes: embedded
/// objects, macros, and property sets are never executed.
nonisolated final class OLECompoundFile:
    @unchecked Sendable
{
    struct Limits: Sendable {
        var maximumFileBytes =
            20 * 1_024 * 1_024
        var maximumDirectoryEntries = 4_096
        var maximumStreamBytes =
            32 * 1_024 * 1_024
        var maximumChainSectors = 131_072
    }

    private static let signature: [UInt8] = [
        0xD0, 0xCF, 0x11, 0xE0,
        0xA1, 0xB1, 0x1A, 0xE1,
    ]
    private static let freeSector =
        UInt32.max
    private static let endOfChain =
        UInt32.max - 1
    private static let fatSector =
        UInt32.max - 2
    private static let difatSector =
        UInt32.max - 3
    private static let noStream =
        UInt32.max

    private struct DirectoryEntry {
        let name: String
        let type: UInt8
        let leftSibling: UInt32
        let rightSibling: UInt32
        let child: UInt32
        let startSector: UInt32
        let streamSize: UInt64
    }

    private let data: Data
    private let limits: Limits
    private let sectorSize: Int
    private let miniSectorSize: Int
    private let miniStreamCutoff: Int
    private let totalSectorCount: Int
    private let fat: [UInt32]
    private let miniFAT: [UInt32]
    private let streamEntries:
        [String: DirectoryEntry]
    private let rootMiniStream: Data

    init(
        data: Data,
        limits: Limits = Limits()
    ) throws {
        guard data.count <= limits.maximumFileBytes
        else {
            throw OLECompoundFileError
                .limitExceeded
        }
        guard data.count >= 512,
              Array(data.prefix(8))
                == Self.signature,
              try data.oleUInt16(at: 28)
                == 0xFFFE
        else {
            throw OLECompoundFileError
                .invalidFile
        }

        let majorVersion =
            try data.oleUInt16(at: 26)
        let sectorShift =
            try data.oleUInt16(at: 30)
        let parsedSectorSize: Int
        switch (
            majorVersion,
            sectorShift
        ) {
        case (3, 9):
            parsedSectorSize = 512
        case (4, 12):
            parsedSectorSize = 4_096
        default:
            throw OLECompoundFileError
                .invalidFile
        }
        let parsedMiniSectorSize =
            1 << Int(
                try data.oleUInt16(at: 32)
            )
        guard parsedMiniSectorSize == 64,
              data.count
                >= parsedSectorSize,
              data.count
                % parsedSectorSize == 0
        else {
            throw OLECompoundFileError
                .invalidFile
        }

        let parsedSectorCount =
            data.count / parsedSectorSize - 1
        guard parsedSectorCount > 0,
              parsedSectorCount
                <= limits.maximumChainSectors
        else {
            throw OLECompoundFileError
                .limitExceeded
        }

        self.data = data
        self.limits = limits
        sectorSize = parsedSectorSize
        miniSectorSize =
            parsedMiniSectorSize
        totalSectorCount =
            parsedSectorCount

        let cutoff = Int(
            try data.oleUInt32(at: 56)
        )
        guard cutoff == 4_096 else {
            throw OLECompoundFileError
                .invalidFile
        }
        miniStreamCutoff = cutoff

        let numberOfFATSectors = Int(
            try data.oleUInt32(at: 44)
        )
        let firstDirectorySector =
            try data.oleUInt32(at: 48)
        let firstMiniFATSector =
            try data.oleUInt32(at: 60)
        let numberOfMiniFATSectors = Int(
            try data.oleUInt32(at: 64)
        )
        let firstDIFATSector =
            try data.oleUInt32(at: 68)
        let numberOfDIFATSectors = Int(
            try data.oleUInt32(at: 72)
        )

        guard numberOfFATSectors > 0,
              numberOfFATSectors
                <= parsedSectorCount,
              numberOfMiniFATSectors
                <= parsedSectorCount,
              numberOfDIFATSectors
                <= parsedSectorCount
        else {
            throw OLECompoundFileError
                .invalidFile
        }
        if majorVersion == 3 {
            guard try data.oleUInt32(at: 40)
                    == 0 else {
                throw OLECompoundFileError
                    .invalidFile
            }
        }

        let fatSectorIDs = try Self
            .readDIFAT(
                data: data,
                sectorSize:
                    parsedSectorSize,
                totalSectorCount:
                    parsedSectorCount,
                numberOfFATSectors:
                    numberOfFATSectors,
                firstDIFATSector:
                    firstDIFATSector,
                numberOfDIFATSectors:
                    numberOfDIFATSectors
            )
        var parsedFAT: [UInt32] = []
        parsedFAT.reserveCapacity(
            numberOfFATSectors
                * parsedSectorSize / 4
        )
        for sectorID in fatSectorIDs {
            let sector = try Self.sector(
                data: data,
                id: sectorID,
                sectorSize:
                    parsedSectorSize,
                totalSectorCount:
                    parsedSectorCount
            )
            for offset in stride(
                from: 0,
                to: sector.count,
                by: 4
            ) {
                parsedFAT.append(
                    try sector.oleUInt32(
                        at: offset
                    )
                )
            }
        }
        guard parsedFAT.count
                >= parsedSectorCount else {
            throw OLECompoundFileError
                .invalidFile
        }
        for sectorID in fatSectorIDs {
            guard parsedFAT[Int(sectorID)]
                    == Self.fatSector else {
                throw OLECompoundFileError
                    .invalidFile
            }
        }
        fat = parsedFAT

        let directoryChain = try Self
            .chain(
                startingAt:
                    firstDirectorySector,
                table: parsedFAT,
                totalSectorCount:
                    parsedSectorCount,
                maximumSectors:
                    min(
                        limits
                            .maximumChainSectors,
                        (
                            limits
                                .maximumDirectoryEntries
                            * 128
                            + parsedSectorSize
                            - 1
                        ) / parsedSectorSize
                    )
            )
        var directoryData = Data()
        directoryData.reserveCapacity(
            directoryChain.count
                * parsedSectorSize
        )
        for sectorID in directoryChain {
            directoryData.append(
                try Self.sector(
                    data: data,
                    id: sectorID,
                    sectorSize:
                        parsedSectorSize,
                    totalSectorCount:
                        parsedSectorCount
                )
            )
        }
        guard directoryData.count >= 128
        else {
            throw OLECompoundFileError
                .invalidFile
        }

        let rawEntryCount =
            directoryData.count / 128
        guard rawEntryCount
                <= limits
                    .maximumDirectoryEntries
        else {
            throw OLECompoundFileError
                .limitExceeded
        }
        var parsedEntries:
            [DirectoryEntry] = []
        let entryCount = rawEntryCount
        parsedEntries.reserveCapacity(
            entryCount
        )
        for index in 0..<entryCount {
            parsedEntries.append(
                try Self.parseDirectoryEntry(
                    directoryData,
                    offset: index * 128,
                    majorVersion:
                        majorVersion
                )
            )
        }
        guard let root =
                parsedEntries.first,
              root.type == 5 else {
            throw OLECompoundFileError
                .invalidFile
        }
        if numberOfMiniFATSectors == 0 {
            guard firstMiniFATSector
                    == Self.endOfChain
                    || firstMiniFATSector
                        == Self.freeSector
            else {
                throw OLECompoundFileError
                    .invalidFile
            }
            miniFAT = []
        } else {
            let miniFATChain = try Self
                .chain(
                    startingAt:
                        firstMiniFATSector,
                    table: parsedFAT,
                    totalSectorCount:
                        parsedSectorCount,
                    maximumSectors:
                        numberOfMiniFATSectors
                )
            guard miniFATChain.count
                    == numberOfMiniFATSectors
            else {
                throw OLECompoundFileError
                    .invalidFile
            }
            var parsedMiniFAT: [UInt32] =
                []
            parsedMiniFAT.reserveCapacity(
                numberOfMiniFATSectors
                    * parsedSectorSize / 4
            )
            for sectorID in miniFATChain {
                let sector = try Self
                    .sector(
                        data: data,
                        id: sectorID,
                        sectorSize:
                            parsedSectorSize,
                        totalSectorCount:
                            parsedSectorCount
                    )
                for offset in stride(
                    from: 0,
                    to: sector.count,
                    by: 4
                ) {
                    parsedMiniFAT.append(
                        try sector
                            .oleUInt32(
                                at: offset
                            )
                    )
                }
            }
            miniFAT = parsedMiniFAT
        }

        if root.streamSize == 0 {
            rootMiniStream = Data()
        } else {
            guard root.streamSize
                    <= UInt64(
                        limits
                            .maximumStreamBytes
                    ) else {
                throw OLECompoundFileError
                    .limitExceeded
            }
            rootMiniStream = try Self
                .readRegularStream(
                    data: data,
                    startSector:
                        root.startSector,
                    size:
                        Int(root.streamSize),
                    fat: parsedFAT,
                    sectorSize:
                        parsedSectorSize,
                    totalSectorCount:
                        parsedSectorCount,
                    maximumSectors:
                        limits
                            .maximumChainSectors
                )
        }

        var mapped:
            [String: DirectoryEntry] = [:]
        var visited: Set<Int> = []
        try Self.walkDirectoryTree(
            root.child,
            parentPath: "",
            entries: parsedEntries,
            visited: &visited,
            depth: 0,
            output: &mapped
        )
        streamEntries = mapped
    }

    var streamNames: [String] {
        streamEntries.keys.sorted()
    }

    func containsStream(
        named rawName: String
    ) -> Bool {
        streamEntries[
            Self.normalizedPath(rawName)
        ] != nil
    }

    func stream(
        named rawName: String
    ) throws -> Data {
        guard let entry =
                streamEntries[
                    Self.normalizedPath(
                        rawName
                    )
                ] else {
            throw OLECompoundFileError
                .streamNotFound
        }
        guard entry.streamSize
                <= UInt64(
                    limits.maximumStreamBytes
                ),
              entry.streamSize
                <= UInt64(Int.max)
        else {
            throw OLECompoundFileError
                .limitExceeded
        }
        let size = Int(entry.streamSize)
        if size == 0 {
            return Data()
        }

        if size < miniStreamCutoff {
            guard !miniFAT.isEmpty,
                  !rootMiniStream.isEmpty
            else {
                throw OLECompoundFileError
                    .invalidFile
            }
            let miniSectorCount =
                rootMiniStream.count
                / miniSectorSize
            let chain = try Self.chain(
                startingAt:
                    entry.startSector,
                table: miniFAT,
                totalSectorCount:
                    miniSectorCount,
                maximumSectors:
                    min(
                        limits
                            .maximumChainSectors,
                        (
                            size
                            + miniSectorSize
                            - 1
                        ) / miniSectorSize
                    )
            )
            let needed = (
                size + miniSectorSize - 1
            ) / miniSectorSize
            guard chain.count == needed
            else {
                throw OLECompoundFileError
                    .invalidFile
            }
            var output = Data()
            output.reserveCapacity(size)
            for miniSectorID in chain {
                let start =
                    Int(miniSectorID)
                    * miniSectorSize
                let end = start
                    + miniSectorSize
                guard start >= 0,
                      end
                        <= rootMiniStream
                        .count else {
                    throw OLECompoundFileError
                        .invalidFile
                }
                output.append(
                    rootMiniStream[
                        start..<end
                    ]
                )
            }
            return output.prefixData(size)
        }

        return try Self.readRegularStream(
            data: data,
            startSector:
                entry.startSector,
            size: size,
            fat: fat,
            sectorSize:
                sectorSize,
            totalSectorCount:
                totalSectorCount,
            maximumSectors:
                limits.maximumChainSectors
        )
    }

    private static func readDIFAT(
        data: Data,
        sectorSize: Int,
        totalSectorCount: Int,
        numberOfFATSectors: Int,
        firstDIFATSector: UInt32,
        numberOfDIFATSectors: Int
    ) throws -> [UInt32] {
        var fatSectorIDs: [UInt32] = []
        fatSectorIDs.reserveCapacity(
            numberOfFATSectors
        )
        var seenFATSectors: Set<UInt32> =
            []

        func appendFATSector(
            _ id: UInt32
        ) throws {
            if id == freeSector {
                return
            }
            guard id
                    < UInt32(
                        totalSectorCount
                    ),
                  id != endOfChain,
                  id != fatSector,
                  id != difatSector,
                  seenFATSectors.insert(id)
                    .inserted
            else {
                throw OLECompoundFileError
                    .invalidFile
            }
            fatSectorIDs.append(id)
        }

        for index in 0..<109 {
            try appendFATSector(
                data.oleUInt32(
                    at: 76 + index * 4
                )
            )
        }

        if numberOfDIFATSectors == 0 {
            guard firstDIFATSector
                    == endOfChain
                    || firstDIFATSector
                        == freeSector
            else {
                throw OLECompoundFileError
                    .invalidFile
            }
        } else {
            var current =
                firstDIFATSector
            var seenDIFAT: Set<UInt32> =
                []
            let idsPerSector =
                sectorSize / 4 - 1
            for index in
                0..<numberOfDIFATSectors
            {
                guard current
                        < UInt32(
                            totalSectorCount
                        ),
                      seenDIFAT.insert(
                          current
                      ).inserted
                else {
                    throw OLECompoundFileError
                        .invalidFile
                }
                let sector = try self.sector(
                    data: data,
                    id: current,
                    sectorSize: sectorSize,
                    totalSectorCount:
                        totalSectorCount
                )
                for fatIndex in
                    0..<idsPerSector
                {
                    try appendFATSector(
                        sector.oleUInt32(
                            at:
                                fatIndex * 4
                        )
                    )
                }
                let next =
                    try sector.oleUInt32(
                        at: idsPerSector * 4
                    )
                if index
                    == numberOfDIFATSectors
                        - 1 {
                    guard next
                            == endOfChain
                    else {
                        throw OLECompoundFileError
                            .invalidFile
                    }
                }
                current = next
            }
        }

        guard fatSectorIDs.count
                == numberOfFATSectors else {
            throw OLECompoundFileError
                .invalidFile
        }
        return fatSectorIDs
    }

    private static func parseDirectoryEntry(
        _ data: Data,
        offset: Int,
        majorVersion: UInt16
    ) throws -> DirectoryEntry {
        let nameByteCount = Int(
            try data.oleUInt16(
                at: offset + 64
            )
        )
        let type = try data.oleUInt8(
            at: offset + 66
        )
        guard [0, 1, 2, 5]
                .contains(type) else {
            throw OLECompoundFileError
                .invalidFile
        }

        let name: String
        if type == 0 {
            name = ""
        } else {
            guard nameByteCount >= 2,
                  nameByteCount <= 64,
                  nameByteCount % 2 == 0,
                  try data.oleUInt16(
                      at:
                        offset
                        + nameByteCount
                        - 2
                  ) == 0
            else {
                throw OLECompoundFileError
                    .invalidFile
            }
            let nameData = data.subdata(
                in:
                    offset..<(
                        offset
                        + nameByteCount - 2
                    )
            )
            guard let decoded = String(
                data: nameData,
                encoding: .utf16LittleEndian
            ),
            !decoded.isEmpty,
            !decoded.contains("/"),
            !decoded.contains("\\"),
            !decoded.contains("\0")
            else {
                throw OLECompoundFileError
                    .invalidFile
            }
            name = decoded
        }

        var streamSize =
            try data.oleUInt64(
                at: offset + 120
            )
        if majorVersion == 3 {
            streamSize &= 0xFFFF_FFFF
        }
        if type != 2 && type != 5 {
            streamSize = 0
        }
        return DirectoryEntry(
            name: name,
            type: type,
            leftSibling:
                try data.oleUInt32(
                    at: offset + 68
                ),
            rightSibling:
                try data.oleUInt32(
                    at: offset + 72
                ),
            child:
                try data.oleUInt32(
                    at: offset + 76
                ),
            startSector:
                try data.oleUInt32(
                    at: offset + 116
                ),
            streamSize: streamSize
        )
    }

    private static func walkDirectoryTree(
        _ rawIndex: UInt32,
        parentPath: String,
        entries: [DirectoryEntry],
        visited: inout Set<Int>,
        depth: Int,
        output:
            inout [String: DirectoryEntry]
    ) throws {
        if rawIndex == noStream {
            return
        }
        guard depth <= 128,
              rawIndex
                < UInt32(entries.count)
        else {
            throw OLECompoundFileError
                .invalidFile
        }
        let index = Int(rawIndex)
        guard visited.insert(index)
                .inserted else {
            throw OLECompoundFileError
                .invalidFile
        }
        let entry = entries[index]
        guard entry.type == 1
                || entry.type == 2 else {
            throw OLECompoundFileError
                .invalidFile
        }

        try walkDirectoryTree(
            entry.leftSibling,
            parentPath: parentPath,
            entries: entries,
            visited: &visited,
            depth: depth + 1,
            output: &output
        )

        let path = parentPath.isEmpty
            ? entry.name
            : parentPath + "/" + entry.name
        if entry.type == 2 {
            let key = normalizedPath(path)
            guard output[key] == nil else {
                throw OLECompoundFileError
                    .invalidFile
            }
            output[key] = entry
        } else {
            try walkDirectoryTree(
                entry.child,
                parentPath: path,
                entries: entries,
                visited: &visited,
                depth: depth + 1,
                output: &output
            )
        }

        try walkDirectoryTree(
            entry.rightSibling,
            parentPath: parentPath,
            entries: entries,
            visited: &visited,
            depth: depth + 1,
            output: &output
        )
    }

    private static func readRegularStream(
        data: Data,
        startSector: UInt32,
        size: Int,
        fat: [UInt32],
        sectorSize: Int,
        totalSectorCount: Int,
        maximumSectors: Int
    ) throws -> Data {
        let needed = (
            size + sectorSize - 1
        ) / sectorSize
        let chain = try self.chain(
            startingAt: startSector,
            table: fat,
            totalSectorCount:
                totalSectorCount,
            maximumSectors:
                min(
                    maximumSectors,
                    needed
                )
        )
        guard chain.count == needed else {
            throw OLECompoundFileError
                .invalidFile
        }
        var output = Data()
        output.reserveCapacity(size)
        for sectorID in chain {
            output.append(
                try sector(
                    data: data,
                    id: sectorID,
                    sectorSize: sectorSize,
                    totalSectorCount:
                        totalSectorCount
                )
            )
        }
        return output.prefixData(size)
    }

    private static func chain(
        startingAt startSector: UInt32,
        table: [UInt32],
        totalSectorCount: Int,
        maximumSectors: Int
    ) throws -> [UInt32] {
        guard maximumSectors > 0 else {
            throw OLECompoundFileError
                .limitExceeded
        }
        var result: [UInt32] = []
        var visited: Set<UInt32> = []
        var current = startSector
        while current != endOfChain {
            guard result.count
                    < maximumSectors else {
                throw OLECompoundFileError
                    .limitExceeded
            }
            guard current
                    < UInt32(
                        totalSectorCount
                    ),
                  Int(current) < table.count,
                  current != freeSector,
                  current != fatSector,
                  current != difatSector,
                  visited.insert(current)
                    .inserted
            else {
                throw OLECompoundFileError
                    .invalidFile
            }
            result.append(current)
            current = table[Int(current)]
        }
        guard !result.isEmpty else {
            throw OLECompoundFileError
                .invalidFile
        }
        return result
    }

    private static func sector(
        data: Data,
        id: UInt32,
        sectorSize: Int,
        totalSectorCount: Int
    ) throws -> Data {
        guard id
                < UInt32(totalSectorCount)
        else {
            throw OLECompoundFileError
                .invalidFile
        }
        let start = (Int(id) + 1)
            * sectorSize
        let end = start + sectorSize
        guard start >= sectorSize,
              end <= data.count else {
            throw OLECompoundFileError
                .invalidFile
        }
        return data.subdata(
            in: start..<end
        )
    }

    private static func normalizedPath(
        _ rawPath: String
    ) -> String {
        rawPath
            .replacingOccurrences(
                of: "\\",
                with: "/"
            )
            .split(
                separator: "/",
                omittingEmptySubsequences:
                    true
            )
            .map(String.init)
            .joined(separator: "/")
            .folding(
                options: [
                    .caseInsensitive,
                    .widthInsensitive,
                ],
                locale: Locale(
                    identifier: "en_US_POSIX"
                )
            )
    }
}

private extension Data {
    nonisolated func oleUInt8(
        at offset: Int
    ) throws -> UInt8 {
        guard offset >= 0,
              offset < count else {
            throw OLECompoundFileError
                .invalidFile
        }
        return self[offset]
    }

    nonisolated func oleUInt16(
        at offset: Int
    ) throws -> UInt16 {
        guard offset >= 0,
              offset + 2 <= count else {
            throw OLECompoundFileError
                .invalidFile
        }
        return UInt16(self[offset])
            | UInt16(self[offset + 1])
                << 8
    }

    nonisolated func oleUInt32(
        at offset: Int
    ) throws -> UInt32 {
        guard offset >= 0,
              offset + 4 <= count else {
            throw OLECompoundFileError
                .invalidFile
        }
        return UInt32(self[offset])
            | UInt32(self[offset + 1])
                << 8
            | UInt32(self[offset + 2])
                << 16
            | UInt32(self[offset + 3])
                << 24
    }

    nonisolated func oleUInt64(
        at offset: Int
    ) throws -> UInt64 {
        let low = UInt64(
            try oleUInt32(at: offset)
        )
        let high = UInt64(
            try oleUInt32(at: offset + 4)
        )
        return low | high << 32
    }

    nonisolated func prefixData(
        _ length: Int
    ) -> Data {
        if count == length {
            return self
        }
        return Data(prefix(length))
    }
}
