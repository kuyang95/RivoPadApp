import Foundation

public nonisolated enum HWP5ParagraphWriter {
    public typealias Record = HWP5DocumentRewriter.Record

    public static func rewrite(_ data: Data, originals: [HWPDocumentBlock], edited: [HWPDocumentBlock]) throws -> Data {
        try HWPParagraphEditing.validate(originals: originals, edited: edited)
        guard try HWP5StructuredDocumentParser.parse(from: data).blocks == originals else {
            throw HWPDocumentEditingError.staleDocument
        }
        let container = try OLECompoundFile(data: data)
        let properties = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36)
        guard properties & 0x6796 == 0 else { throw HWPDocumentEditingError.protectedDocument }
        let compressed = properties & 1 != 0
        let paths = container.streamNames.filter { $0.hasPrefix("bodytext/section") }
            .sorted { (Int($0.dropFirst(16)) ?? 0) < (Int($1.dropFirst(16)) ?? 0) }
        let oldByID = Dictionary(uniqueKeysWithValues: originals.map { ($0.id, $0) })
        let retained = Set(edited.map(\.id))
        let promotedCellEnds = Set(Dictionary(grouping: originals.filter { $0.tableLocation != nil }, by: { block in
            let cell = block.tableLocation!
            return "\(block.sectionPath.lowercased()):\(cell.table):\(String(describing: cell.parent)):\(cell.row):\(cell.column)"
        }).values.compactMap { members -> String? in
            let kept = members.filter { retained.contains($0.id) }
            guard let lastKept = kept.last, members.last?.id != lastKept.id else { return nil }
            let final = edited.last { candidate in
                members.contains(where: { HWPCellFormatting.sameCell($0, candidate) })
            }
            return final?.id == lastKept.id ? lastKept.id : nil
        })
        var insertions: [String: [HWPDocumentBlock]] = [:], anchor = ""
        for block in edited {
            if oldByID[block.id] != nil { anchor = block.id }
            else { insertions[anchor, default: []].append(block) }
        }
        var ordinal = 0, replacements: [String: Data] = [:]
        var sectionRecords: [String: [Record]] = [:]
        var nextInstance: UInt32 = 0
        for path in paths {
            let stored = try container.stream(named: path)
            let expanded = try compressed ? HWP5TextExtractor.inflateRawDeflate(stored,
                maximumBytes: HWP5TextExtractor.maximumSectionBytes) : stored
            let records = try HWP5DocumentRewriter.parseRecords(expanded)
            sectionRecords[path] = records
            for record in records where record.tag == 0x42 && record.payload.count >= 22 {
                nextInstance = max(nextInstance, try record.payload.hwpWriterUInt32(at: 18))
            }
        }
        for path in paths {
            guard let records = sectionRecords[path] else { throw HWPDocumentEditingError.invalidDocument }
            var ranges: [Int: Range<Int>] = [:]
            for index in records.indices where records[index].tag == 0x42 {
                let end = records.indices.dropFirst(index + 1).first { records[$0].level <= records[index].level } ?? records.endIndex
                ranges[ordinal] = index..<end
                ordinal += 1
            }
            var patches: [(Range<Int>, [Record])] = []
            for original in originals where original.sectionPath.lowercased() == path.lowercased() {
                guard let range = ranges[original.paragraphIndex] else { throw HWPDocumentEditingError.staleDocument }
                let additions = insertions[original.id] ?? []
                let promotesCellEnd = promotedCellEnds.contains(original.id)
                guard !retained.contains(original.id) || !additions.isEmpty || promotesCellEnd else { continue }
                // Plain paragraph records stay contiguous inside their body or cell list. Never remove a nested control or an unknown record.
                var owned = Array(records[range])
                guard let paragraphLevel = owned.first?.level,
                      (original.tableLocation == nil ? paragraphLevel == 0 : paragraphLevel > 0),
                      owned.allSatisfy({ [0x42, 0x43, 0x44, 0x45].contains($0.tag) }),
                      owned.filter({ $0.tag == 0x42 }).count == 1 else {
                    throw HWPDocumentEditingError.unsupportedEdit
                }
                if promotesCellEnd {
                    var count = try owned[0].payload.hwpWriterUInt32(at: 0)
                    count |= 0x8000_0000
                    owned[0].payload.hwpWriterSetUInt32(count, at: 0)
                }
                var replacement = retained.contains(original.id) ? owned : []
                let lastBit = try owned[0].payload.hwpWriterUInt32(at: 0) & 0x8000_0000
                if !additions.isEmpty {
                    var count = try replacement[0].payload.hwpWriterUInt32(at: 0)
                    count &= 0x7FFF_FFFF
                    replacement[0].payload.hwpWriterSetUInt32(count, at: 0)
                }
                for (position, added) in additions.enumerated() {
                    guard let source = added.sourceParagraphID.flatMap({ oldByID[$0] }),
                          let templateRange = ranges[source.paragraphIndex] else { throw HWPDocumentEditingError.staleDocument }
                    var clone = Array(records[templateRange])
                    guard clone[0].level == paragraphLevel, clone[0].payload.count >= 22,
                          clone.allSatisfy({ [0x42, 0x43, 0x44, 0x45].contains($0.tag) }),
                          clone.filter({ $0.tag == 0x42 }).count == 1,
                          nextInstance < UInt32.max else { throw HWPDocumentEditingError.unsupportedEdit }
                    nextInstance += 1
                    clone[0].payload.hwpWriterSetUInt32(nextInstance, at: 18)
                    var count = try clone[0].payload.hwpWriterUInt32(at: 0) & 0x7FFF_FFFF
                    if position == additions.count - 1 { count |= lastBit }
                    clone[0].payload.hwpWriterSetUInt32(count, at: 0)
                    clone[0].payload[11] = 0 // A new paragraph does not inherit a section/page/column break.
                    replacement += clone
                }
                patches.append((range, replacement))
            }
            var output = records
            for (range, replacement) in patches.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
                output.replaceSubrange(range, with: replacement)
            }
            if !patches.isEmpty {
                // PARA_HEADER's high character-count bit marks the last paragraph in the body list.
                let roots = output.indices.filter { output[$0].tag == 0x42 && output[$0].level == 0 }
                for index in roots {
                    var count = try output[index].payload.hwpWriterUInt32(at: 0) & 0x7FFF_FFFF
                    if index == roots.last { count |= 0x8000_0000 }
                    output[index].payload.hwpWriterSetUInt32(count, at: 0)
                }
                let payload = output.reduce(into: Data()) { $0.append($1.serialized()) }
                guard payload.count <= HWP5TextExtractor.maximumSectionBytes else { throw HWPDocumentEditingError.limitExceeded }
                replacements[path] = try compressed ? HWP5DocumentRewriter.rawDeflate(payload) : payload
            }
        }
        if container.containsStream(named: "PrvText") {
            let preview = edited.filter { $0.region.kind == .body }.map(\.text).joined(separator: "\n")
            replacements["PrvText"] = Data(preview.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
        }
        let expanded = try container.serialized(replacing: replacements)
        let base = try HWP5StructuredDocumentParser.parse(from: expanded)
        let targets = try HWPParagraphEditing.rebased(edited, onto: base.blocks)
        return try HWP5DocumentRewriter.rewrite(sourceData: expanded, originalBlocks: base.blocks, editedBlocks: targets)
    }
}
