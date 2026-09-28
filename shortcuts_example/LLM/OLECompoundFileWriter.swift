import Foundation

/// Rebuilds a CFB/OLE container from its streams. The reader remains the
/// authority for validating the source; this writer never executes embedded
/// content and normally replaces existing document streams. The explicit
/// `adding` overload is reserved for structured writers that also update the
/// owning format's manifest, such as an embedded HWP image.
nonisolated extension OLECompoundFile {
    func serialized(replacing rawReplacements: [String: Data]) throws -> Data {
        try serialized(replacing: rawReplacements, adding: [:])
    }

    func serialized(replacing rawReplacements: [String: Data],
                    adding rawAdditions: [String: Data]) throws -> Data {
        let replacements = Dictionary(
            uniqueKeysWithValues: rawReplacements.map {
                (Self.writerNormalizedPath($0.key), $0.value)
            }
        )
        let additions = Dictionary(
            uniqueKeysWithValues: rawAdditions.map {
                (Self.writerNormalizedPath($0.key), ($0.key, $0.value))
            }
        )
        let known = Set(streamNames.map(Self.writerNormalizedPath))
        guard Set(replacements.keys).isSubset(of: known),
              Set(additions.keys).isDisjoint(with: known),
              Set(additions.keys).isDisjoint(with: replacements.keys) else {
            throw OLECompoundFileError.streamNotFound
        }

        var streams: [String: Data] = [:]
        streams.reserveCapacity(streamPaths.count + additions.count)
        for path in streamPaths {
            let normalized = Self.writerNormalizedPath(path)
            streams[path] = try replacements[normalized] ?? stream(named: path)
        }
        for (_, addition) in additions { streams[addition.0] = addition.1 }
        return try OLECompoundFileWriter.make(streams: streams)
    }

    private static func writerNormalizedPath(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .joined(separator: "/")
            .folding(
                options: [.caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }
}

private nonisolated enum OLECompoundFileWriter {
    private static let sectorSize = 512
    private static let miniSectorSize = 64
    private static let miniStreamCutoff = 4_096
    private static let freeSector = UInt32.max
    private static let endOfChain = UInt32.max - 1
    private static let fatSector = UInt32.max - 2
    private static let difatSector = UInt32.max - 3
    private static let maximumOutputBytes = 64 * 1_024 * 1_024

    private struct Entry {
        let name: String
        let type: UInt8
        let parentPath: String
        var color: UInt8 = 1
        var left = freeSector
        var right = freeSector
        var child = freeSector
        var startSector = endOfChain
        var size: UInt64 = 0
    }

    static func make(streams rawStreams: [String: Data]) throws -> Data {
        let streams = try normalizedStreams(rawStreams)
        guard !streams.isEmpty,
              streams.values.reduce(0, { $0 + $1.count }) <= maximumOutputBytes else {
            throw OLECompoundFileError.limitExceeded
        }

        var storagePaths: Set<String> = []
        for path in streams.keys {
            let parts = path.split(separator: "/").map(String.init)
            if parts.count > 1 {
                for end in 1..<parts.count {
                    storagePaths.insert(parts[0..<end].joined(separator: "/"))
                }
            }
        }

        var entries = [Entry(name: "Root Entry", type: 5, parentPath: "")]
        var indexForPath = ["": 0]
        for path in storagePaths.sorted(by: pathLessThan) {
            let parts = path.split(separator: "/").map(String.init)
            let parent = parts.dropLast().joined(separator: "/")
            indexForPath[path] = entries.count
            entries.append(Entry(name: parts.last!, type: 1, parentPath: parent))
        }
        for path in streams.keys.sorted(by: pathLessThan) {
            let parts = path.split(separator: "/").map(String.init)
            let parent = parts.dropLast().joined(separator: "/")
            indexForPath[path] = entries.count
            entries.append(Entry(name: parts.last!, type: 2, parentPath: parent))
        }
        guard entries.count <= 4_096 else {
            throw OLECompoundFileError.limitExceeded
        }
        installDirectoryTrees(entries: &entries, indexForPath: indexForPath)

        var miniStream = Data()
        var miniFAT: [UInt32] = []
        var regularStreams: [(entry: Int, data: Data)] = []
        for (path, payload) in streams.sorted(by: { pathLessThan($0.key, $1.key) }) {
            guard let entryIndex = indexForPath[path] else {
                throw OLECompoundFileError.invalidFile
            }
            entries[entryIndex].size = UInt64(payload.count)
            guard !payload.isEmpty else { continue }
            if payload.count < miniStreamCutoff {
                let first = miniFAT.count
                entries[entryIndex].startSector = UInt32(first)
                let count = (payload.count + miniSectorSize - 1) / miniSectorSize
                for index in 0..<count {
                    miniFAT.append(
                        index == count - 1 ? endOfChain : UInt32(first + index + 1)
                    )
                    let lower = index * miniSectorSize
                    let upper = min(payload.count, lower + miniSectorSize)
                    miniStream.append(payload[lower..<upper])
                    if upper - lower < miniSectorSize {
                        miniStream.append(
                            Data(repeating: 0, count: miniSectorSize - (upper - lower))
                        )
                    }
                }
            } else {
                regularStreams.append((entryIndex, payload))
            }
        }

        let directorySectorCount = max(
            1,
            (entries.count * 128 + sectorSize - 1) / sectorSize
        )
        var sectors = Array(
            repeating: Data(repeating: 0, count: sectorSize),
            count: directorySectorCount
        )
        var fat = (0..<directorySectorCount).map {
            $0 == directorySectorCount - 1 ? endOfChain : UInt32($0 + 1)
        }

        func appendSectorChain(_ bytes: Data) throws -> UInt32 {
            guard !bytes.isEmpty else { return endOfChain }
            let first = sectors.count
            let count = (bytes.count + sectorSize - 1) / sectorSize
            guard first + count < Int(UInt32.max - 4) else {
                throw OLECompoundFileError.limitExceeded
            }
            for index in 0..<count {
                let lower = index * sectorSize
                let upper = min(bytes.count, lower + sectorSize)
                var sector = Data(bytes[lower..<upper])
                if sector.count < sectorSize {
                    sector.append(Data(repeating: 0, count: sectorSize - sector.count))
                }
                sectors.append(sector)
                fat.append(index == count - 1 ? endOfChain : UInt32(first + index + 1))
            }
            return UInt32(first)
        }

        let firstMiniFATSector: UInt32
        let miniFATSectorCount: Int
        if miniFAT.isEmpty {
            firstMiniFATSector = endOfChain
            miniFATSectorCount = 0
        } else {
            var bytes = Data()
            for value in miniFAT { bytes.cfbAppendUInt32(value) }
            while !bytes.count.isMultiple(of: sectorSize) {
                bytes.cfbAppendUInt32(freeSector)
            }
            firstMiniFATSector = try appendSectorChain(bytes)
            miniFATSectorCount = bytes.count / sectorSize
        }

        if !miniStream.isEmpty {
            entries[0].startSector = try appendSectorChain(miniStream)
            entries[0].size = UInt64(miniStream.count)
        }
        for stream in regularStreams {
            entries[stream.entry].startSector = try appendSectorChain(stream.data)
        }

        let baseSectorCount = sectors.count
        let allocation = fatAndDIFATCounts(baseSectorCount: baseSectorCount)
        let firstDIFATSector = allocation.difat == 0
            ? endOfChain
            : UInt32(sectors.count)
        let difatIDs = (0..<allocation.difat).map { UInt32(sectors.count + $0) }
        for _ in 0..<allocation.difat {
            sectors.append(Data(repeating: 0xFF, count: sectorSize))
            fat.append(difatSector)
        }
        let fatIDs = (0..<allocation.fat).map { UInt32(sectors.count + $0) }
        for _ in 0..<allocation.fat {
            sectors.append(Data(repeating: 0xFF, count: sectorSize))
            fat.append(fatSector)
        }
        guard fat.count == sectors.count,
              allocation.fat * (sectorSize / 4) >= fat.count else {
            throw OLECompoundFileError.invalidFile
        }

        var directory = Data()
        for entry in entries { directory.append(directoryEntry(entry)) }
        if directory.count < directorySectorCount * sectorSize {
            directory.append(
                Data(
                    repeating: 0,
                    count: directorySectorCount * sectorSize - directory.count
                )
            )
        }
        for index in 0..<directorySectorCount {
            let lower = index * sectorSize
            sectors[index] = directory.subdata(in: lower..<(lower + sectorSize))
        }

        if !difatIDs.isEmpty {
            let remainingFATIDs = Array(fatIDs.dropFirst(109))
            let perSector = sectorSize / 4 - 1
            for (index, sectorID) in difatIDs.enumerated() {
                var bytes = Data()
                let lower = index * perSector
                let upper = min(remainingFATIDs.count, lower + perSector)
                for id in remainingFATIDs[lower..<upper] { bytes.cfbAppendUInt32(id) }
                while bytes.count < perSector * 4 { bytes.cfbAppendUInt32(freeSector) }
                bytes.cfbAppendUInt32(
                    index == difatIDs.count - 1 ? endOfChain : difatIDs[index + 1]
                )
                sectors[Int(sectorID)] = bytes
            }
        }

        var paddedFAT = fat
        paddedFAT.append(
            contentsOf: repeatElement(
                freeSector,
                count: allocation.fat * (sectorSize / 4) - paddedFAT.count
            )
        )
        for (index, sectorID) in fatIDs.enumerated() {
            var bytes = Data()
            let lower = index * (sectorSize / 4)
            let upper = lower + sectorSize / 4
            for value in paddedFAT[lower..<upper] { bytes.cfbAppendUInt32(value) }
            sectors[Int(sectorID)] = bytes
        }

        var header = Data(repeating: 0, count: sectorSize)
        header.replaceSubrange(
            0..<8,
            with: Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
        )
        header.cfbSetUInt16(0x003E, at: 24)
        header.cfbSetUInt16(3, at: 26)
        header.cfbSetUInt16(0xFFFE, at: 28)
        header.cfbSetUInt16(9, at: 30)
        header.cfbSetUInt16(6, at: 32)
        header.cfbSetUInt32(0, at: 40)
        header.cfbSetUInt32(UInt32(allocation.fat), at: 44)
        header.cfbSetUInt32(0, at: 48)
        header.cfbSetUInt32(UInt32(miniStreamCutoff), at: 56)
        header.cfbSetUInt32(firstMiniFATSector, at: 60)
        header.cfbSetUInt32(UInt32(miniFATSectorCount), at: 64)
        header.cfbSetUInt32(firstDIFATSector, at: 68)
        header.cfbSetUInt32(UInt32(allocation.difat), at: 72)
        for index in 0..<109 {
            header.cfbSetUInt32(index < fatIDs.count ? fatIDs[index] : freeSector,
                                at: 76 + index * 4)
        }

        var output = header
        for sector in sectors { output.append(sector) }
        guard output.count <= maximumOutputBytes else {
            throw OLECompoundFileError.limitExceeded
        }
        return output
    }

    private static func normalizedStreams(_ streams: [String: Data]) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for (rawPath, data) in streams {
            let components = rawPath.replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            guard !components.isEmpty,
                  components.allSatisfy({ !$0.isEmpty && $0.utf16.count <= 31 }) else {
                throw OLECompoundFileError.invalidFile
            }
            let path = components.joined(separator: "/")
            let comparisonKey = path.folding(
                options: [.caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            guard !result.keys.contains(where: {
                $0.folding(
                    options: [.caseInsensitive, .widthInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                ) == comparisonKey
            }) else {
                throw OLECompoundFileError.invalidFile
            }
            result[path] = data
        }
        return result
    }

    private static func fatAndDIFATCounts(baseSectorCount: Int) -> (fat: Int, difat: Int) {
        let entriesPerFAT = sectorSize / 4
        let entriesPerDIFAT = entriesPerFAT - 1
        var fat = 0
        var difat = 0
        while true {
            let nextFAT = (baseSectorCount + fat + difat + entriesPerFAT - 1)
                / entriesPerFAT
            let nextDIFAT = nextFAT <= 109
                ? 0
                : (nextFAT - 109 + entriesPerDIFAT - 1) / entriesPerDIFAT
            if nextFAT == fat && nextDIFAT == difat { return (fat, difat) }
            fat = nextFAT
            difat = nextDIFAT
        }
    }

    private static func installDirectoryTrees(
        entries: inout [Entry],
        indexForPath: [String: Int]
    ) {
        let grouped = Dictionary(grouping: entries.indices.dropFirst()) {
            entries[$0].parentPath
        }
        for (parentPath, rawChildren) in grouped {
            guard let parentIndex = indexForPath[parentPath] else { continue }
            var root: Int?
            var parents: [Int: Int] = [:]

            func color(_ index: Int?) -> UInt8 {
                index.map { entries[$0].color } ?? 1
            }
            func left(_ index: Int) -> Int? {
                entries[index].left == freeSector ? nil : Int(entries[index].left)
            }
            func right(_ index: Int) -> Int? {
                entries[index].right == freeSector ? nil : Int(entries[index].right)
            }
            func setLeft(_ parent: Int, _ child: Int?) {
                entries[parent].left = child.map(UInt32.init) ?? freeSector
                if let child { parents[child] = parent }
            }
            func setRight(_ parent: Int, _ child: Int?) {
                entries[parent].right = child.map(UInt32.init) ?? freeSector
                if let child { parents[child] = parent }
            }
            func rotateLeft(_ value: Int) {
                guard let pivot = right(value) else { return }
                let pivotLeft = left(pivot)
                setRight(value, pivotLeft)
                let oldParent = parents[value]
                parents[pivot] = oldParent
                if let oldParent {
                    if left(oldParent) == value { setLeft(oldParent, pivot) }
                    else { setRight(oldParent, pivot) }
                } else {
                    root = pivot
                }
                setLeft(pivot, value)
            }
            func rotateRight(_ value: Int) {
                guard let pivot = left(value) else { return }
                let pivotRight = right(pivot)
                setLeft(value, pivotRight)
                let oldParent = parents[value]
                parents[pivot] = oldParent
                if let oldParent {
                    if left(oldParent) == value { setLeft(oldParent, pivot) }
                    else { setRight(oldParent, pivot) }
                } else {
                    root = pivot
                }
                setRight(pivot, value)
            }

            for inserted in rawChildren.sorted(by: {
                directoryNameLessThan(entries[$0].name, entries[$1].name)
            }) {
                entries[inserted].color = 0
                entries[inserted].left = freeSector
                entries[inserted].right = freeSector
                var parent: Int?
                var cursor = root
                while let current = cursor {
                    parent = current
                    cursor = directoryNameLessThan(
                        entries[inserted].name,
                        entries[current].name
                    ) ? left(current) : right(current)
                }
                if let parent {
                    parents[inserted] = parent
                    if directoryNameLessThan(entries[inserted].name, entries[parent].name) {
                        setLeft(parent, inserted)
                    } else {
                        setRight(parent, inserted)
                    }
                } else {
                    root = inserted
                }

                var node = inserted
                while color(parents[node]) == 0,
                      let parent = parents[node],
                      let grand = parents[parent] {
                    if left(grand) == parent {
                        let uncle = right(grand)
                        if color(uncle) == 0 {
                            entries[parent].color = 1
                            if let uncle { entries[uncle].color = 1 }
                            entries[grand].color = 0
                            node = grand
                        } else {
                            if right(parent) == node {
                                node = parent
                                rotateLeft(node)
                            }
                            guard let nextParent = parents[node],
                                  let nextGrand = parents[nextParent] else { break }
                            entries[nextParent].color = 1
                            entries[nextGrand].color = 0
                            rotateRight(nextGrand)
                        }
                    } else {
                        let uncle = left(grand)
                        if color(uncle) == 0 {
                            entries[parent].color = 1
                            if let uncle { entries[uncle].color = 1 }
                            entries[grand].color = 0
                            node = grand
                        } else {
                            if left(parent) == node {
                                node = parent
                                rotateRight(node)
                            }
                            guard let nextParent = parents[node],
                                  let nextGrand = parents[nextParent] else { break }
                            entries[nextParent].color = 1
                            entries[nextGrand].color = 0
                            rotateLeft(nextGrand)
                        }
                    }
                }
                if let root { entries[root].color = 1 }
            }
            entries[parentIndex].child = root.map(UInt32.init) ?? freeSector
        }
    }

    private static func pathLessThan(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.split(separator: "/").map(String.init)
        let right = rhs.split(separator: "/").map(String.init)
        for index in 0..<min(left.count, right.count) {
            if left[index] == right[index] { continue }
            return directoryNameLessThan(left[index], right[index])
        }
        return left.count < right.count
    }

    private static func directoryNameLessThan(_ lhs: String, _ rhs: String) -> Bool {
        if lhs.utf16.count != rhs.utf16.count { return lhs.utf16.count < rhs.utf16.count }
        return lhs.uppercased(with: Locale(identifier: "en_US_POSIX"))
            < rhs.uppercased(with: Locale(identifier: "en_US_POSIX"))
    }

    private static func directoryEntry(_ entry: Entry) -> Data {
        var data = Data(repeating: 0, count: 128)
        var units = Array(entry.name.utf16)
        units.append(0)
        for (index, unit) in units.enumerated() {
            data.cfbSetUInt16(unit, at: index * 2)
        }
        data.cfbSetUInt16(UInt16(units.count * 2), at: 64)
        data[66] = entry.type
        data[67] = entry.color
        data.cfbSetUInt32(entry.left, at: 68)
        data.cfbSetUInt32(entry.right, at: 72)
        data.cfbSetUInt32(entry.child, at: 76)
        data.cfbSetUInt32(entry.startSector, at: 116)
        data.cfbSetUInt64(entry.size, at: 120)
        return data
    }
}

private nonisolated extension Data {
    mutating func cfbAppendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    mutating func cfbSetUInt16(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8(value & 0xFF)
        self[offset + 1] = UInt8(value >> 8)
    }

    mutating func cfbSetUInt32(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8(value & 0xFF)
        self[offset + 1] = UInt8((value >> 8) & 0xFF)
        self[offset + 2] = UInt8((value >> 16) & 0xFF)
        self[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    mutating func cfbSetUInt64(_ value: UInt64, at offset: Int) {
        cfbSetUInt32(UInt32(value & 0xFFFF_FFFF), at: offset)
        cfbSetUInt32(UInt32(value >> 32), at: offset + 4)
    }
}
