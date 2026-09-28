import Foundation
import XCTest
@testable import shortcuts_example

final class HWPEmptyParagraphEditingTests: XCTestCase {
    private struct Record: Equatable {
        var tag: UInt32
        var level: UInt32
        var payload: Data
        var usesExtendedSize = false

        var data: Data {
            var result = Data()
            let extended = usesExtendedSize || payload.count >= 0xFFF
            result.appendLE(UInt32(extended ? 0xFFF : payload.count) << 20 | level << 10 | tag)
            if extended { result.appendLE(UInt32(payload.count)) }
            result.append(payload)
            return result
        }
    }

    private func fixture() throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: "hangul_design_application", withExtension: "hwp")
            ?? bundle.url(forResource: "hangul_design_application", withExtension: "hwp",
                subdirectory: "HWPXViewerFixtures")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("HWPXViewerFixtures/hangul_design_application.hwp")
        return try Data(contentsOf: url)
    }

    private func records(_ data: Data) throws -> [Record] {
        var offset = 0
        var result: [Record] = []
        while offset < data.count {
            guard offset + 4 <= data.count else { throw HWPDocumentEditingError.invalidDocument }
            let header = data.readLE(offset)
            offset += 4
            let extended = header >> 20 == 0xFFF
            var size = Int(header >> 20)
            if extended {
                guard offset + 4 <= data.count else { throw HWPDocumentEditingError.invalidDocument }
                size = Int(data.readLE(offset))
                offset += 4
            }
            guard offset + size <= data.count else { throw HWPDocumentEditingError.invalidDocument }
            result.append(Record(tag: header & 0x3FF, level: (header >> 10) & 0x3FF,
                payload: data.subdata(in: offset..<(offset + size)), usesExtendedSize: extended))
            offset += size
        }
        return result
    }

    private func section(_ data: Data) throws -> [Record] {
        let container = try OLECompoundFile(data: data)
        let stored = try container.stream(named: "BodyText/Section0")
        let compressed = try container.stream(named: "FileHeader").readLE(36) & 1 != 0
        return try records(compressed
            ? HWP5TextExtractor.inflateRawDeflate(stored, maximumBytes: 32 * 1_024 * 1_024) : stored)
    }

    private func paragraphs(_ records: [Record]) -> [[Record]] {
        var result: [[Record]] = []
        for record in records {
            if record.tag == 0x42 { result.append([]) }
            if !result.isEmpty { result[result.count - 1].append(record) }
        }
        return result
    }

    /// Reuse real DocInfo/style data while constructing controlled body records.
    private func document(_ body: [Record]) throws -> Data {
        let container = try OLECompoundFile(data: fixture())
        var header = try container.stream(named: "FileHeader")
        let compressed = header.readLE(36) & 1 != 0
        header.setLE(header.readLE(36) & ~UInt32(1), at: 36)
        let storedDocInfo = try container.stream(named: "DocInfo")
        let docInfo = compressed ? try HWP5TextExtractor.inflateRawDeflate(storedDocInfo,
            maximumBytes: 32 * 1_024 * 1_024) : storedDocInfo
        return try container.serialized(replacing: ["FileHeader": header,
            "DocInfo": docInfo, "BodyText/Section0": body.reduce(into: Data()) { $0.append($1.data) }])
    }

    private func emptyParagraph(level: UInt32 = 0) -> [Record] {
        var header = Data(repeating: 0, count: 24)
        header.setLE(0x8000_0001, at: 0)
        header[12] = 1 // One character shape.
        header[16] = 1 // One cached line.
        var shape = Data(repeating: 0, count: 8)
        shape.setLE(1, at: 4) // Deliberately use a non-default typing shape.
        var line = Data(repeating: 0, count: 36)
        line.setLE(1_600, at: 8)
        line.setLE(1_200, at: 12)
        line.setLE(1_300, at: 16)
        line.setLE(40_000, at: 28)
        line.setLE(0x0001_0000, at: 32)
        return [Record(tag: 0x42, level: level, payload: header),
            Record(tag: 0x44, level: level + 1, payload: shape),
            Record(tag: 0x45, level: level + 1, payload: line)]
    }

    func testRealApplicationUnlocksAllMissingTextParagraphsButKeepsTableOwnersReadOnly() throws {
        let data = try fixture()
        let parsed = try HWP5StructuredDocumentParser.parse(from: data)
        let raw = paragraphs(try section(data))
        let missing = raw.indices.filter { !raw[$0].contains { $0.tag == 0x43 } }
        let tableMissing = missing.filter { parsed.blocks[$0].tableLocation != nil }
        XCTAssertEqual(tableMissing.count, 41)
        for index in tableMissing {
            XCTAssertTrue(parsed.blocks[index].isEditable, "paragraph \(index)")
            XCTAssertEqual(parsed.blocks[index].text, "")
            XCTAssertNotNil(parsed.blocks[index].presentation.textRuns.first?.fontSizePoints)
        }
        for index in [6, 12] {
            XCTAssertEqual(parsed.blocks[index].text, "")
            XCTAssertFalse(parsed.blocks[index].isEditable, "Nested table owner \(index)")
        }
        let product = parsed.blocks[18]
        XCTAssertEqual(product.tableLocation?.columnSpan, 3)
        let preview = HWPTextRunEditing.replacingText(in: product, with: "한글빛")
        XCTAssertEqual(preview.presentation.textRuns.first?.text, "한글빛")
        XCTAssertEqual(preview.presentation.textRuns.first?.fontName,
            product.presentation.textRuns.first?.fontName)
        XCTAssertEqual(preview.presentation.textRuns.first?.fontSizePoints,
            product.presentation.textRuns.first?.fontSizePoints)
    }

    func testAll41EmptyTableParagraphsSaveTogetherWithoutChangingOtherRecordsOrStreams() throws {
        let data = try fixture()
        let parsed = try HWP5StructuredDocumentParser.parse(from: data)
        let before = paragraphs(try section(data))
        var edited = parsed.blocks
        let targets = before.indices.filter {
            edited[$0].tableLocation != nil && !before[$0].contains { $0.tag == 0x43 }
        }
        XCTAssertEqual(targets.count, 41)
        for index in targets { edited[index] = HWPTextRunEditing.replacingText(in: edited[index], with: "가") }
        let output = try HWP5DocumentRewriter.rewrite(sourceData: data,
            originalBlocks: parsed.blocks, editedBlocks: edited)
        let reloaded = try HWP5StructuredDocumentParser.parse(from: output)
        XCTAssertEqual(reloaded.blocks.map(\.text), edited.map(\.text))
        XCTAssertEqual(reloaded.blocks.map(\.tableLocation), parsed.blocks.map(\.tableLocation))
        XCTAssertEqual(reloaded.tableCount, 4)
        let after = paragraphs(try section(output))
        XCTAssertEqual(after.count, before.count)
        for index in before.indices {
            if !targets.contains(index) {
                XCTAssertEqual(before[index], after[index], "Unedited paragraph \(index)")
                continue
            }
            XCTAssertEqual(after[index].filter { $0.tag == 0x43 }.count, 1)
            XCTAssertEqual(after[index][1].tag, 0x43)
            XCTAssertEqual(after[index][1].level, after[index][0].level + 1)
            XCTAssertEqual(after[index][0].payload.readLE(0),
                before[index][0].payload.readLE(0) & 0x8000_0000 | 2)
            XCTAssertEqual(after[index].filter { $0.tag == 0x44 }, before[index].filter { $0.tag == 0x44 })
            XCTAssertEqual(after[index].filter { ![0x42, 0x43, 0x44, 0x45].contains($0.tag) },
                before[index].filter { ![0x42, 0x43, 0x44, 0x45].contains($0.tag) })
            XCTAssertEqual(reloaded.blocks[index].presentation.textRuns.first,
                edited[index].presentation.textRuns.first)
        }
        let originalContainer = try OLECompoundFile(data: data)
        let savedContainer = try OLECompoundFile(data: output)
        XCTAssertEqual(Set(originalContainer.streamNames), Set(savedContainer.streamNames))
        for name in originalContainer.streamNames where name != "bodytext/section0" && name != "prvtext" {
            XCTAssertEqual(try originalContainer.stream(named: name), try savedContainer.stream(named: name), name)
        }
    }

    func testProductNameSupportsReopenSecondEditClearAndRefillWithoutDuplicateTextRecords() throws {
        var data = try fixture()
        var parsed = try HWP5StructuredDocumentParser.parse(from: data)
        for text in ["한글빛", "나랏말", "", "우리글"] {
            var edited = parsed.blocks
            edited[18] = HWPTextRunEditing.replacingText(in: edited[18], with: text)
            data = try HWP5DocumentRewriter.rewrite(sourceData: data,
                originalBlocks: parsed.blocks, editedBlocks: edited)
            parsed = try HWP5StructuredDocumentParser.parse(from: data)
            XCTAssertEqual(parsed.blocks[18].text, text)
            XCTAssertTrue(parsed.blocks[18].isEditable)
            XCTAssertEqual(paragraphs(try section(data))[18].filter { $0.tag == 0x43 }.count, 1)
        }
    }

    func testUncompressedEmptyBodyParagraphPreservesStyleHeaderFlagAndLineMetrics() throws {
        let raw = emptyParagraph()
        let data = try document(raw)
        let parsed = try HWP5StructuredDocumentParser.parse(from: data)
        XCTAssertTrue(parsed.blocks[0].isEditable)
        var edited = parsed.blocks
        edited[0] = HWPTextRunEditing.replacingText(in: edited[0], with: "가😀\t나\n다")
        let output = try HWP5DocumentRewriter.rewrite(sourceData: data,
            originalBlocks: parsed.blocks, editedBlocks: edited)
        let saved = try section(output)
        let text = try XCTUnwrap(saved.first { $0.tag == 0x43 })
        let header = try XCTUnwrap(saved.first { $0.tag == 0x42 }).payload
        XCTAssertEqual(header.readLE(0), 0x8000_0000 | UInt32(text.payload.count / 2))
        XCTAssertEqual(header.readLE(4), (1 << 9) | (1 << 10))
        XCTAssertEqual(text.payload.count / 2, 15) // Surrogate pair, 8-unit tab, LF, terminal CR.
        let lines = try XCTUnwrap(saved.first { $0.tag == 0x45 }).payload
        XCTAssertEqual(Int(header[16]) | Int(header[17]) << 8, lines.count / 36)
        XCTAssertEqual(lines.readLE(8), raw[2].payload.readLE(8))
        for offset in stride(from: 0, to: lines.count, by: 36) {
            XCTAssertEqual(lines.readLE(offset + 32) & 0x0001_0000, 0)
        }
        XCTAssertEqual(saved.first { $0.tag == 0x44 }, raw[1])
        let reopened = try HWP5StructuredDocumentParser.parse(from: output)
        XCTAssertEqual(reopened.blocks[0].text, edited[0].text)
        var cleared = reopened.blocks
        cleared[0].text = ""
        let clearedData = try HWP5DocumentRewriter.rewrite(sourceData: output,
            originalBlocks: reopened.blocks, editedBlocks: cleared)
        let clearedRecords = try section(clearedData)
        XCTAssertEqual(clearedRecords.first { $0.tag == 0x42 }?.payload.readLE(4), 0)
        XCTAssertEqual(try HWP5StructuredDocumentParser.parse(from: clearedData).blocks[0].lineLayouts.first?.isEmpty, true)
    }

    func testMissingTextWithInvalidCountsStylesOrPositionedMetadataRemainsReadOnly() throws {
        for variant in 0..<8 {
            var raw = emptyParagraph()
            switch variant {
            case 0: raw[0].payload.setLE(0x8000_0005, at: 0)
            case 1: raw[1].payload.setLE(999_999, at: 4)
            case 2: raw[0].payload[14] = 1
            case 3: raw[0].payload.setLE(1 << 11, at: 4)
            case 4:
                raw.append(Record(tag: 0x46, level: 1, payload: Data(repeating: 0, count: 12)))
            case 5: raw.append(Record(tag: 0x3F0, level: 1, payload: Data([1, 2, 3])))
            case 6: raw[1].level = 2
            default: raw[1].level = 0
            }
            let parsed = try HWP5StructuredDocumentParser.parse(from: document(raw))
            XCTAssertFalse(parsed.blocks[0].isEditable, "variant \(variant)")
        }
    }

    func testControlTokensCannotBeErasedEvenWithoutAControlHeader() throws {
        var raw = emptyParagraph()
        raw[0].payload.setLE(0x8000_0009, at: 0)
        var text = Data()
        for unit: UInt16 in [11, 0, 0, 0, 0, 0, 0, 11, 13] { text.appendLE(unit) }
        raw.insert(Record(tag: 0x43, level: 1, payload: text), at: 1)
        let data = try document(raw)
        let parsed = try HWP5StructuredDocumentParser.parse(from: data)
        XCTAssertFalse(parsed.blocks[0].isEditable)
        var edited = parsed.blocks
        edited[0].text = "손상시키면 안 됨"
        XCTAssertThrowsError(try HWP5DocumentRewriter.rewrite(sourceData: data,
            originalBlocks: parsed.blocks, editedBlocks: edited))
    }

    func testUnchangedUnknownRecordRetainsItsOriginalExtendedEncoding() throws {
        var raw = emptyParagraph() + emptyParagraph()
        let unknown = Record(tag: 0x3F0, level: 0, payload: Data([1, 2, 3]), usesExtendedSize: true)
        raw.append(unknown)
        let data = try document(raw)
        let parsed = try HWP5StructuredDocumentParser.parse(from: data)
        var edited = parsed.blocks
        edited[0].text = "가"
        let output = try HWP5DocumentRewriter.rewrite(sourceData: data,
            originalBlocks: parsed.blocks, editedBlocks: edited)
        XCTAssertEqual(try section(output).last, unknown)
    }

    func testNoOpIsByteIdenticalAndDuplicateOrStaleSnapshotsAreRejected() throws {
        let data = try fixture()
        let parsed = try HWP5StructuredDocumentParser.parse(from: data)
        XCTAssertEqual(try HWP5DocumentRewriter.rewrite(sourceData: data,
            originalBlocks: parsed.blocks, editedBlocks: parsed.blocks), data)
        var duplicate = parsed.blocks
        duplicate[1] = duplicate[0]
        XCTAssertThrowsError(try HWP5DocumentRewriter.rewrite(sourceData: data,
            originalBlocks: duplicate, editedBlocks: duplicate))
        var stale = parsed.blocks
        stale[18].text = "이전 파일의 값"
        var edited = stale
        edited[18].text = "새 값"
        XCTAssertThrowsError(try HWP5DocumentRewriter.rewrite(sourceData: data,
            originalBlocks: stale, editedBlocks: edited))
    }

    func testMiddleTypingMovesStoredStyleBoundariesAndRemainsEditableAfterReopening() throws {
        var raw = emptyParagraph()
        raw[0].payload.setLE(0x8000_0005, at: 0)
        raw[0].payload[12] = 2
        var shapes = Data()
        for value: UInt32 in [0, 1, 2, 2] { shapes.appendLE(value) }
        raw[1].payload = shapes
        var text = Data()
        for value in "가나다라\r".utf16 { text.appendLE(value) }
        raw.insert(Record(tag: 0x43, level: 1, payload: text), at: 1)
        let source = try document(raw)
        let original = try HWP5StructuredDocumentParser.parse(from: source)
        XCTAssertTrue(original.blocks[0].isEditable)
        let edited = [HWPTextRunEditing.replacingText(in: original.blocks[0], with: "가추가나다라")]
        let saved = try HWP5DocumentRewriter.rewrite(sourceData: source,
            originalBlocks: original.blocks, editedBlocks: edited)
        let storedShapes = try XCTUnwrap(section(saved).first { $0.tag == 0x44 })
        XCTAssertEqual(storedShapes.payload.readLE(8), 4)
        XCTAssertEqual(storedShapes.payload.readLE(12), 2)
        let reopened = try HWP5StructuredDocumentParser.parse(from: saved)
        XCTAssertEqual(reopened.blocks[0].text, "가추가나다라")
        XCTAssertTrue(reopened.blocks[0].isEditable)
        let removed = [HWPTextRunEditing.replacingText(in: reopened.blocks[0], with: "다라")]
        let savedAgain = try HWP5DocumentRewriter.rewrite(sourceData: saved,
            originalBlocks: reopened.blocks, editedBlocks: removed)
        let records = try section(savedAgain)
        XCTAssertEqual(records.first { $0.tag == 0x42 }?.payload[12], 1)
        XCTAssertEqual(records.first { $0.tag == 0x44 }?.payload.count, 8)
        XCTAssertEqual(records.first { $0.tag == 0x44 }?.payload.readLE(4), 2)
        XCTAssertTrue(try HWP5StructuredDocumentParser.parse(from: savedAgain).blocks[0].isEditable)
    }

    #if canImport(UIKit)
    @MainActor
    func testRealHWPRowEditingSupportsUndoRedoAndSameFormatSave() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwp")
        defer { try? FileManager.default.removeItem(at: url) }
        try fixture().write(to: url)
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let productID = "hwp-section-0-paragraph-18"
        let row = try XCTUnwrap(HWPAccessibleDocument.make(blocks: model.blocks).tables
            .flatMap(\.rows).first { $0.blocks.contains { $0.id == productID } })
        try model.applyTableRowEdits(originalBlocks: row.blocks, texts: [productID: "한글빛"])
        XCTAssertEqual(model.blocks.first { $0.id == productID }?.text, "한글빛")
        XCTAssertTrue(model.hasUnsavedChanges)
        model.undo()
        XCTAssertEqual(model.blocks.first { $0.id == productID }?.text, "")
        model.redo()
        XCTAssertEqual(model.blocks.first { $0.id == productID }?.text, "한글빛")
        await model.save()
        XCTAssertNil(model.errorDescription)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertTrue(model.isLegacyDocument)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(8)), [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
        XCTAssertEqual(try HWP5StructuredDocumentParser.parse(from: data).blocks[18].text, "한글빛")
    }
    #endif
}

private extension Data {
    func readLE(_ offset: Int) -> UInt32 {
        UInt32(self[offset]) | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24
    }

    mutating func setLE(_ value: UInt32, at offset: Int) {
        for index in 0..<4 { self[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8)) }
    }

    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        for index in 0..<MemoryLayout<T>.size { append(UInt8(truncatingIfNeeded: value >> (index * 8))) }
    }
}
