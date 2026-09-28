import Foundation
import zlib

/// A deliberately narrow HWP 5 writer. It rewrites text records in editable
/// paragraphs while preserving every other OLE stream and every unknown HWP
/// record byte-for-byte. Paragraphs with controls or positioned metadata are
/// excluded by the parser before they can reach this writer.
nonisolated enum HWP5DocumentRewriter {
    private static let paraHeaderTag: UInt32 = 0x42
    private static let paraTextTag: UInt32 = 0x43
    private static let paraCharShapeTag: UInt32 = 0x44
    private static let paraLineSegmentTag: UInt32 = 0x45
    private static let maximumRecordLevel = 64
    private static let lineSegmentBytes = 36
    /// PARA_HEADER: nchars(4) + control mask(4) + para shape(2) + style(1)
    /// + column kind(1) + char shape count(2) + range tag count(2) + line
    /// segment count(2).
    private static let lineSegmentCountOffset = 16

    struct Record {
        let tag: UInt32
        let level: UInt32
        var payload: Data
        var originalPayload: Data? = nil
        var originalEncoding: Data? = nil

        func serialized() -> Data {
            if payload == originalPayload, let originalEncoding { return originalEncoding }
            var result = Data()
            if payload.count < 0x0FFF {
                result.hwpWriterAppendUInt32(
                    UInt32(payload.count) << 20 | level << 10 | tag
                )
            } else {
                result.hwpWriterAppendUInt32(
                    UInt32(0x0FFF) << 20 | level << 10 | tag
                )
                result.hwpWriterAppendUInt32(UInt32(payload.count))
            }
            result.append(payload)
            return result
        }
    }

    static func rewrite(sourceData: Data, originalBlocks: [HWPDocumentBlock],
                        editedBlocks: [HWPDocumentBlock]) throws -> Data {
        if originalBlocks.map(\.id) != editedBlocks.map(\.id) {
            return try HWP5ParagraphWriter.rewrite(sourceData, originals: originalBlocks, edited: editedBlocks)
        }
        let textData = try rewriteText(sourceData: sourceData, originalBlocks: originalBlocks, editedBlocks: editedBlocks)
        let formatted = try HWP5FormattingWriter.apply(to: textData, originals: originalBlocks, edited: editedBlocks)
        let lined = try HWP5LineLayoutWriter.apply(formatted, originals: originalBlocks, edited: editedBlocks)
        let linked = try HWPHyperlinkEditingWriter.applyHWP(to: lined, originals: originalBlocks, edited: editedBlocks)
        let sized = try HWPTableLayoutWriter.applyHWP(linked, originals: originalBlocks, edited: editedBlocks)
        return try HWPCellFormattingWriter.applyHWP(sized, originals: originalBlocks, edited: editedBlocks)
    }

    private static func rewriteText(
        sourceData: Data,
        originalBlocks: [HWPDocumentBlock],
        editedBlocks: [HWPDocumentBlock]
    ) throws -> Data {
        guard originalBlocks.count == editedBlocks.count,
              sourceData.count <= HWP5TextExtractor.maximumDocumentBytes else {
            throw HWPDocumentEditingError.cannotSave
        }
        guard Set(originalBlocks.map(\.id)).count == originalBlocks.count,
              Set(editedBlocks.map(\.id)).count == editedBlocks.count else {
            throw HWPDocumentEditingError.staleDocument
        }
        let originalsByID = Dictionary(uniqueKeysWithValues: originalBlocks.map { ($0.id, $0) })
        let editedByID = Dictionary(uniqueKeysWithValues: editedBlocks.map { ($0.id, $0) })
        guard originalsByID.keys == editedByID.keys else {
            throw HWPDocumentEditingError.staleDocument
        }

        var changes: [Int: Data] = [:]
        var editedLineStarts: [Int: [Int]] = [:]
        var changedIDs: Set<String> = []
        for original in originalBlocks {
            guard let edited = editedByID[original.id] else {
                throw HWPDocumentEditingError.staleDocument
            }
            guard original.text != edited.text else { continue }
            guard original.isEditable else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            changes[original.paragraphIndex] = try encodedParagraphText(edited.text)
            let preview = HWPTextRunEditing.replacingText(in: original, with: edited.text)
            if !preview.lineLayouts.isEmpty {
                editedLineStarts[original.paragraphIndex] = preview.lineLayouts.map(\.startCharacter)
            }
            changedIDs.insert(original.id)
        }
        guard !changes.isEmpty else { return sourceData }

        let container: OLECompoundFile
        do {
            container = try OLECompoundFile(
                data: sourceData,
                limits: .init(
                    maximumFileBytes: HWP5TextExtractor.maximumDocumentBytes,
                    maximumDirectoryEntries: 4_096,
                    maximumStreamBytes: HWP5TextExtractor.maximumSectionBytes,
                    maximumChainSectors: 131_072
                )
            )
        } catch OLECompoundFileError.limitExceeded {
            throw HWPDocumentEditingError.limitExceeded
        } catch {
            throw HWPDocumentEditingError.invalidDocument
        }

        let header: Data
        do {
            header = try container.stream(named: "FileHeader")
        } catch {
            throw HWPDocumentEditingError.invalidDocument
        }
        guard header.count >= 48,
              String(data: header.prefix(17), encoding: .ascii) == "HWP Document File",
              try header.hwpWriterUInt32(at: 32) >> 24 == 5 else {
            throw HWPDocumentEditingError.invalidDocument
        }
        let properties = try header.hwpWriterUInt32(at: 36)
        let unsupportedSecurityFlags: UInt32 =
            (1 << 1) | (1 << 2) | (1 << 4) | (1 << 7) | (1 << 8)
            | (1 << 9) | (1 << 10) | (1 << 13) | (1 << 14)
        guard properties & unsupportedSecurityFlags == 0 else {
            throw HWPDocumentEditingError.protectedDocument
        }
        // Validate against the bytes being saved, not just a caller's cached
        // editability flag or paragraph ordinal. This also protects controls
        // if an old editor snapshot predates the parser's capability checks.
        let sourceDocument = try HWP5StructuredDocumentParser.parse(from: sourceData)
        guard sourceDocument.blocks == originalBlocks else {
            throw HWPDocumentEditingError.staleDocument
        }
        let isCompressed = properties & 0x01 != 0
        let sectionPrefix = "bodytext/section"
        let sections = container.streamNames.compactMap { path -> (Int, String)? in
            guard path.hasPrefix(sectionPrefix),
                  let index = Int(path.dropFirst(sectionPrefix.count)) else { return nil }
            return (index, path)
        }.sorted { $0.0 < $1.0 }
        guard !sections.isEmpty else {
            throw HWPDocumentEditingError.invalidDocument
        }

        var replacements: [String: Data] = [:]
        var paragraphOrdinal = 0
        var appliedOrdinals: Set<Int> = []
        let originalTexts = Dictionary(uniqueKeysWithValues: originalBlocks.map { ($0.paragraphIndex, $0.text) })
        let editedTexts = Dictionary(uniqueKeysWithValues: editedBlocks.map { ($0.paragraphIndex, $0.text) })
        for (_, path) in sections {
            let stored = try container.stream(named: path)
            let expanded = isCompressed
                ? try HWP5TextExtractor.inflateRawDeflate(
                    stored,
                    maximumBytes: HWP5TextExtractor.maximumSectionBytes
                )
                : stored
            let rewritten = try rewriteSection(
                expanded,
                changes: changes,
                originalTexts: originalTexts,
                editedTexts: editedTexts,
                editedLineStarts: editedLineStarts,
                paragraphOrdinal: &paragraphOrdinal,
                appliedOrdinals: &appliedOrdinals
            )
            if rewritten != expanded {
                replacements[path] = isCompressed ? try rawDeflate(rewritten) : rewritten
            }
        }
        guard appliedOrdinals == Set(changes.keys) else {
            throw HWPDocumentEditingError.staleDocument
        }

        if container.containsStream(named: "PrvText") {
            let bodyText = editedBlocks
                .filter { $0.region.kind == .body }
                .map(\.text)
                .joined(separator: "\n")
            replacements["PrvText"] = Data(bodyText.utf16.flatMap {
                [UInt8($0 & 0xFF), UInt8($0 >> 8)]
            })
        }

        let output: Data
        do {
            output = try container.serialized(replacing: replacements)
        } catch OLECompoundFileError.limitExceeded {
            throw HWPDocumentEditingError.limitExceeded
        } catch {
            throw HWPDocumentEditingError.cannotSave
        }
        let reparsed: HWP5StructuredDocument
        do {
            reparsed = try HWP5StructuredDocumentParser.parse(from: output)
        } catch {
            throw HWPDocumentEditingError.cannotSave
        }
        guard reparsed.blocks.count == originalBlocks.count,
              reparsed.tableCount == sourceDocument.tableCount,
              reparsed.tableCellCount == sourceDocument.tableCellCount else {
            throw HWPDocumentEditingError.cannotSave
        }
        for (original, saved) in zip(originalBlocks, reparsed.blocks) {
            guard saved.id == original.id,
                  saved.text == editedByID[original.id]?.text,
                  saved.tableLocation == original.tableLocation,
                  saved.region == original.region,
                  saved.layoutContainerID == original.layoutContainerID,
                  changedIDs.contains(original.id) || saved == original else {
                throw HWPDocumentEditingError.cannotSave
            }
        }
        return output
    }

    private static func rewriteSection(
        _ data: Data,
        changes: [Int: Data],
        originalTexts: [Int: String],
        editedTexts: [Int: String],
        editedLineStarts: [Int: [Int]],
        paragraphOrdinal: inout Int,
        appliedOrdinals: inout Set<Int>
    ) throws -> Data {
        let records = try parseRecords(data)
        var output: [Record] = []
        output.reserveCapacity(records.count)
        var currentParagraph: Int?
        var currentHeaderIndex: Int?
        var currentHasHeader = false
        var currentHeaderLevel: UInt32?
        var sawTextForCurrent = false

        for (recordIndex, sourceRecord) in records.enumerated() {
            var record = sourceRecord
            if record.tag == paraHeaderTag {
                currentParagraph = paragraphOrdinal
                paragraphOrdinal += 1
                currentHasHeader = true
                sawTextForCurrent = false
                currentHeaderIndex = output.count
                currentHeaderLevel = record.level
                if let currentParagraph,
                   let replacement = changes[currentParagraph] {
                    guard record.payload.count >= 4 else {
                        throw HWPDocumentEditingError.invalidDocument
                    }
                    let oldCount = try record.payload.hwpWriterUInt32(at: 0)
                    let unitCount = UInt32(replacement.count / 2)
                    guard unitCount <= 0x7FFF_FFFF else {
                        throw HWPDocumentEditingError.limitExceeded
                    }
                    record.payload.hwpWriterSetUInt32(
                        oldCount & 0x8000_0000 | unitCount,
                        at: 0
                    )
                    // PARA_HEADER's control mask includes tabs and explicit
                    // line breaks (bits 9 and 10), but not the terminal CR.
                    let oldMask = try record.payload.hwpWriterUInt32(at: 4)
                    record.payload.hwpWriterSetUInt32(
                        oldMask & ~UInt32((1 << 9) | (1 << 10)) | textControlMask(replacement),
                        at: 4
                    )
                    // A genuine empty paragraph can omit PARA_TEXT. Insert
                    // it directly after its own header, before shape/line
                    // records, using the paragraph's existing nesting level.
                    let ownedRecords = records[(recordIndex + 1)...].prefix {
                        $0.tag != paraHeaderTag && $0.level > record.level
                    }
                    if !ownedRecords.contains(where: { $0.tag == paraTextTag }) {
                        guard oldCount & 0x7FFF_FFFF <= 1,
                              record.level < maximumRecordLevel,
                              ownedRecords.allSatisfy({
                                  $0.level == record.level + 1
                                      && ($0.tag == paraCharShapeTag || $0.tag == paraLineSegmentTag)
                              }) else {
                            throw HWPDocumentEditingError.unsupportedEdit
                        }
                        output.append(record)
                        output.append(Record(tag: paraTextTag, level: record.level + 1,
                            payload: replacement))
                        sawTextForCurrent = true
                        appliedOrdinals.insert(currentParagraph)
                        continue
                    }
                }
            } else if record.tag == paraTextTag {
                if currentParagraph == nil || (!currentHasHeader && sawTextForCurrent) {
                    currentParagraph = paragraphOrdinal
                    paragraphOrdinal += 1
                    currentHasHeader = false
                    currentHeaderIndex = nil
                    currentHeaderLevel = nil
                    sawTextForCurrent = false
                }
                sawTextForCurrent = true
                if let currentParagraph,
                   let replacement = changes[currentParagraph] {
                    guard currentHeaderLevel.map({ record.level == $0 + 1 }) ?? true else {
                        throw HWPDocumentEditingError.unsupportedEdit
                    }
                    record.payload = replacement
                    appliedOrdinals.insert(currentParagraph)
                }
            } else if let currentParagraph,
                      let replacement = changes[currentParagraph],
                      currentHeaderLevel.map({ record.level == $0 + 1 }) ?? true {
                if record.tag == paraCharShapeTag {
                    record.payload = try adjustedCharacterShapes(
                        record.payload,
                        originalText: originalTexts[currentParagraph] ?? "",
                        editedText: editedTexts[currentParagraph] ?? ""
                    )
                    if let headerIndex = currentHeaderIndex {
                        let count = record.payload.count / 8
                        guard count <= Int(UInt16.max), output[headerIndex].payload.count >= 14 else {
                            throw HWPDocumentEditingError.invalidDocument
                        }
                        output[headerIndex].payload[12] = UInt8(count & 0xFF)
                        output[headerIndex].payload[13] = UInt8(count >> 8)
                    }
                } else if record.tag == paraLineSegmentTag {
                    // Cached line geometry describes the old text. Rebuild
                    // it from the original metrics so the paragraph keeps its
                    // page position, and keep the header's segment count in
                    // sync. Hancom-compatible readers recalculate the rest.
                    record.payload = try regeneratedLineSegments(
                        record.payload,
                        replacement: replacement,
                        editedLineStarts: editedLineStarts[currentParagraph]
                    )
                    let segmentCount = record.payload.count / lineSegmentBytes
                    if let currentHeaderIndex,
                       output.indices.contains(currentHeaderIndex),
                       output[currentHeaderIndex].payload.count >= lineSegmentCountOffset + 2 {
                        output[currentHeaderIndex].payload.hwpWriterSetUInt16(
                            UInt16(min(segmentCount, Int(UInt16.max))),
                            at: lineSegmentCountOffset
                        )
                    }
                }
            }
            output.append(record)
        }
        var serialized = Data()
        serialized.reserveCapacity(data.count)
        for record in output { serialized.append(record.serialized()) }
        return serialized
    }

    /// Uses the edited paragraph's measured line starts, falling back to
    /// explicit line breaks when there is no preview geometry. Maps each
    /// line onto the original cached segments in order. Lines beyond the
    /// original count continue below the last segment; surplus segments are
    /// dropped. The "empty segment" flag follows whether text remains after
    /// the edit, including when a previously filled paragraph is cleared.
    private static func regeneratedLineSegments(
        _ original: Data,
        replacement: Data,
        editedLineStarts: [Int]?
    ) throws -> Data {
        guard original.count.isMultiple(of: lineSegmentBytes) else {
            throw HWPDocumentEditingError.invalidDocument
        }
        let originalCount = original.count / lineSegmentBytes
        guard originalCount > 0 else { return original }
        guard originalCount <= 4_096 else {
            throw HWPDocumentEditingError.limitExceeded
        }

        var lineStarts = [0]
        var unitIndex = 0
        var offset = 0
        while offset + 2 <= replacement.count {
            let unit = UInt16(replacement[offset]) | UInt16(replacement[offset + 1]) << 8
            unitIndex += 1
            if unit == 10 { lineStarts.append(unitIndex) }
            offset += 2
        }
        if let editedLineStarts { lineStarts = editedLineStarts }
        guard lineStarts.count <= 4_096 else {
            throw HWPDocumentEditingError.limitExceeded
        }

        func segment(_ index: Int) -> Data {
            original.subdata(
                in: (index * lineSegmentBytes)..<((index + 1) * lineSegmentBytes)
            )
        }

        var result = Data()
        result.reserveCapacity(lineStarts.count * lineSegmentBytes)
        var previous = segment(originalCount - 1)
        for (line, start) in lineStarts.enumerated() {
            var rebuilt: Data
            if line < originalCount {
                rebuilt = segment(line)
            } else {
                rebuilt = previous
                let previousY = Int32(bitPattern: try previous.hwpWriterUInt32(at: 4))
                let previousHeight = Int32(bitPattern: try previous.hwpWriterUInt32(at: 8))
                let previousTextHeight = Int32(bitPattern: try previous.hwpWriterUInt32(at: 12))
                let advance = max(abs(previousHeight), abs(previousTextHeight), 1)
                let nextY = previousY.addingReportingOverflow(advance)
                rebuilt.hwpWriterSetUInt32(
                    UInt32(bitPattern: nextY.overflow ? previousY : nextY.partialValue),
                    at: 4
                )
                // Continuation lines never start a page or column.
                let flags = try rebuilt.hwpWriterUInt32(at: 32) & ~UInt32(0x3)
                rebuilt.hwpWriterSetUInt32(flags, at: 32)
            }
            rebuilt.hwpWriterSetUInt32(UInt32(start), at: 0)
            var flags = try rebuilt.hwpWriterUInt32(at: 32) & ~UInt32(0x0001_0000)
            if replacement == Data([13, 0]) { flags |= 0x0001_0000 }
            rebuilt.hwpWriterSetUInt32(flags, at: 32)
            result.append(rebuilt)
            previous = rebuilt
        }
        return result
    }

    static func parseRecords(_ data: Data) throws -> [Record] {
        var offset = 0
        var result: [Record] = []
        result.reserveCapacity(min(2_048, data.count / 8))
        while offset < data.count {
            let recordStart = offset
            guard offset + 4 <= data.count else {
                throw HWPDocumentEditingError.invalidDocument
            }
            let header = try data.hwpWriterUInt32(at: offset)
            offset += 4
            let tag = header & 0x03FF
            let level = (header >> 10) & 0x03FF
            guard level <= maximumRecordLevel else {
                throw HWPDocumentEditingError.limitExceeded
            }
            var size = Int(header >> 20)
            if size == 0x0FFF {
                guard offset + 4 <= data.count else {
                    throw HWPDocumentEditingError.invalidDocument
                }
                size = Int(try data.hwpWriterUInt32(at: offset))
                offset += 4
            }
            guard size >= 0,
                  size <= HWP5TextExtractor.maximumSectionBytes,
                  offset + size <= data.count else {
                throw HWPDocumentEditingError.invalidDocument
            }
            result.append(
                Record(
                    tag: tag,
                    level: level,
                    payload: data.subdata(in: offset..<(offset + size)),
                    originalPayload: data.subdata(in: offset..<(offset + size)),
                    originalEncoding: data.subdata(in: recordStart..<(offset + size))
                )
            )
            offset += size
            guard result.count <= 200_000 else {
                throw HWPDocumentEditingError.limitExceeded
            }
        }
        return result
    }

    private static func textControlMask(_ replacement: Data) -> UInt32 {
        var mask: UInt32 = 0
        var offset = 0
        while offset + 1 < replacement.count {
            let unit = UInt16(replacement[offset]) | UInt16(replacement[offset + 1]) << 8
            if unit == 9 || unit == 10 { mask |= 1 << UInt32(unit) }
            offset += unit == 9 ? 16 : 2
        }
        return mask
    }

    private static func encodedParagraphText(_ text: String) throws -> Data {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var units: [UInt16] = []
        units.reserveCapacity(normalized.utf16.count + 1)
        var buffer = ""

        func flushBuffer() {
            if !buffer.isEmpty {
                units.append(contentsOf: buffer.utf16)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        for character in normalized {
            switch character {
            case "\t":
                flushBuffer()
                units.append(contentsOf: [9, 0, 0, 0, 0, 0, 0, 9])
            case "\n":
                flushBuffer()
                units.append(10)
            default:
                guard !character.unicodeScalars.contains(where: {
                    $0.value < 32 || $0.value == 0x7F
                }) else {
                    throw HWPDocumentEditingError.unsupportedEdit
                }
                buffer.append(character)
            }
        }
        flushBuffer()
        units.append(13)
        guard units.count * 2 <= HWP5TextExtractor.maximumSectionBytes else {
            throw HWPDocumentEditingError.limitExceeded
        }
        var result = Data()
        result.reserveCapacity(units.count * 2)
        for unit in units { result.hwpWriterAppendUInt16(unit) }
        return result
    }

    static func adjustedCharacterShapes(
        _ payload: Data,
        originalText: String,
        editedText: String
    ) throws -> Data {
        guard !payload.isEmpty, payload.count.isMultiple(of: 8) else {
            throw HWPDocumentEditingError.invalidDocument
        }
        // Shape offsets count raw HWP units (a tab takes eight), while the
        // editor uses Unicode text. Move the actual style boundaries with
        // insertions/deletions, using the same ownership rule as the preview.
        var offsets = [0]
        var rawPosition = 0
        for unit in originalText.utf16 {
            rawPosition += unit == 9 ? 8 : 1
            offsets.append(rawPosition)
        }
        let count = payload.count / 8
        var positions: [Int] = []
        var shapes: [UInt32] = []
        for index in 0..<count {
            let raw = Int(try payload.hwpWriterUInt32(at: index * 8))
            guard raw <= rawPosition + 1,
                  positions.last.map({ raw >= $0 }) ?? (raw == 0) else {
                throw HWPDocumentEditingError.invalidDocument
            }
            positions.append(raw)
            shapes.append(try payload.hwpWriterUInt32(at: index * 8 + 4))
        }
        let source = originalText as NSString
        var cursor = 0
        let starts = positions.map { position in
            while cursor < source.length, offsets[cursor] < position { cursor += 1 }
            return cursor
        }
        let segments = starts.indices.map { index in
            let end = index + 1 < starts.count ? starts[index + 1] : source.length
            return source.substring(with: NSRange(location: starts[index], length: end - starts[index]))
        }
        let replacements = HWPTextRunEditing.redistribute(editedText, originalSegments: segments)
        var result = Data()
        var position = 0
        for (index, segment) in replacements.enumerated() where !segment.isEmpty {
            result.hwpWriterAppendUInt32(UInt32(position))
            result.hwpWriterAppendUInt32(shapes[index])
            position += segment.utf16.reduce(0) { $0 + ($1 == 9 ? 8 : 1) }
        }
        if result.isEmpty {
            result.hwpWriterAppendUInt32(0)
            result.hwpWriterAppendUInt32(shapes[starts.lastIndex(of: 0) ?? 0])
        }
        return result
    }

    static func rawDeflate(_ input: Data) throws -> Data {
        guard !input.isEmpty else { return input }
        var stream = z_stream()
        guard deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            -MAX_WBITS,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        ) == Z_OK else {
            throw HWPDocumentEditingError.cannotSave
        }
        defer { deflateEnd(&stream) }

        return try input.withUnsafeBytes { rawInput in
            let bytes = rawInput.bindMemory(to: Bytef.self)
            stream.next_in = UnsafeMutablePointer(mutating: bytes.baseAddress)
            stream.avail_in = uInt(input.count)
            var output = Data()
            var chunk = [UInt8](repeating: 0, count: 64 * 1_024)
            while true {
                let status = chunk.withUnsafeMutableBytes { rawOutput -> Int32 in
                    let outputBytes = rawOutput.bindMemory(to: Bytef.self)
                    stream.next_out = outputBytes.baseAddress
                    stream.avail_out = uInt(outputBytes.count)
                    return deflate(&stream, Z_FINISH)
                }
                let produced = chunk.count - Int(stream.avail_out)
                if produced > 0 { output.append(contentsOf: chunk.prefix(produced)) }
                if status == Z_STREAM_END { return output }
                guard status == Z_OK || status == Z_BUF_ERROR,
                      output.count <= HWP5TextExtractor.maximumSectionBytes else {
                    throw HWPDocumentEditingError.cannotSave
                }
            }
        }
    }
}

nonisolated extension Data {
    func hwpWriterUInt16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset <= count, count - offset >= 2 else {
            throw HWPDocumentEditingError.invalidDocument
        }
        return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func hwpWriterUInt32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else {
            throw HWPDocumentEditingError.invalidDocument
        }
        return UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }

    mutating func hwpWriterAppendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func hwpWriterAppendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    mutating func hwpWriterSetUInt16(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8(value & 0xFF)
        self[offset + 1] = UInt8(value >> 8)
    }

    mutating func hwpWriterSetUInt32(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8(value & 0xFF)
        self[offset + 1] = UInt8((value >> 8) & 0xFF)
        self[offset + 2] = UInt8((value >> 16) & 0xFF)
        self[offset + 3] = UInt8((value >> 24) & 0xFF)
    }
}
