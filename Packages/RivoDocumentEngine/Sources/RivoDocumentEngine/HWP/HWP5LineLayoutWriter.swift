import Foundation

public nonisolated enum HWP5LineLayoutWriter {
    public static func apply(_ data: Data, originals: [HWPDocumentBlock], edited: [HWPDocumentBlock]) throws -> Data {
        let changes = Dictionary(uniqueKeysWithValues: zip(originals, edited).filter {
            !$1.lineLayouts.isEmpty && HWP5FormattingWriter.lineData($0.lineLayouts) != HWP5FormattingWriter.lineData($1.lineLayouts)
        }.map { ($0.0.paragraphIndex, $0.1.lineLayouts) })
        guard !changes.isEmpty else { return data }
        let container = try OLECompoundFile(data: data)
        let compressed = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36) & 1 != 0
        var ordinal = 0, replacements: [String: Data] = [:]
        let paths = container.streamNames.filter { $0.hasPrefix("bodytext/section") }
            .sorted { (Int($0.dropFirst(16)) ?? 0) < (Int($1.dropFirst(16)) ?? 0) }
        for path in paths {
            let stored = try container.stream(named: path)
            let expanded = try compressed ? HWP5TextExtractor.inflateRawDeflate(stored,
                maximumBytes: HWP5TextExtractor.maximumSectionBytes) : stored
            var records = try HWP5DocumentRewriter.parseRecords(expanded)
            var changed = false
            var inserts: [(Int, HWP5DocumentRewriter.Record)] = []
            for index in records.indices where records[index].tag == 0x42 {
                let number = ordinal
                ordinal += 1
                guard let lines = changes[number] else { continue }
                guard lines.count <= Int(UInt16.max), records[index].payload.count >= 18 else {
                    throw HWPDocumentEditingError.limitExceeded
                }
                let level = records[index].level
                let owned = records.indices.dropFirst(index + 1).prefix { records[$0].level > level }
                if let cache = owned.first(where: { records[$0].tag == 0x45 && records[$0].level == level + 1 }) {
                    records[cache].payload = HWP5FormattingWriter.lineData(lines)
                } else {
                    let location = owned.last.map { $0 + 1 } ?? index + 1
                    inserts.append((location, .init(tag: 0x45, level: level + 1, payload: HWP5FormattingWriter.lineData(lines))))
                }
                records[index].payload.hwpWriterSetUInt16(UInt16(lines.count), at: 16)
                changed = true
            }
            for (index, record) in inserts.reversed() { records.insert(record, at: index) }
            if changed {
                let payload = records.reduce(into: Data()) { $0.append($1.serialized()) }
                replacements[path] = try compressed ? HWP5DocumentRewriter.rawDeflate(payload) : payload
            }
        }
        return try container.serialized(replacing: replacements)
    }
}
