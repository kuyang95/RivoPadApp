import Foundation
import XCTest
import zlib
@testable import shortcuts_example

final class LegacyDocumentAttachmentTests:
    XCTestCase
{
    func testOLEReadsMiniAndRegularNestedStreams()
        throws
    {
        let small = Data(
            "nested mini stream".utf8
        )
        let large = Data(
            (0..<5_000).map {
                UInt8($0 % 251)
            }
        )
        let fixture = try makeOLEFile(
            streams: [
                "BodyText/Section0":
                    small,
                "Workbook": large,
            ]
        )
        let container =
            try OLECompoundFile(
                data: fixture
            )

        XCTAssertEqual(
            try container.stream(
                named:
                    "bodytext/SECTION0"
            ),
            small
        )
        XCTAssertEqual(
            try container.stream(
                named: "workbook"
            ),
            large
        )
    }

    func testOLERejectsRegularFATCycle()
        throws
    {
        var fixture = try makeOLEFile(
            streams: [
                "Workbook": Data(
                    repeating: 0x41,
                    count: 5_000
                ),
            ]
        )
        let fatSectorID = Int(
            try fixture.testUInt32(
                at: 76
            )
        )
        let fatOffset =
            (fatSectorID + 1) * 512
        // Sector 1 is the first regular Workbook sector in this fixture.
        fixture.testSetUInt32(
            1,
            at: fatOffset + 4
        )

        XCTAssertThrowsError(
            try OLECompoundFile(
                data: fixture
            ).stream(named: "Workbook")
        )
    }

    func testLegacyXLSExtractsBIFF8ValuesAndStoresOriginal()
        async throws
    {
        let root = try makeTemporaryRoot()
        defer {
            try? FileManager.default
                .removeItem(at: root)
        }
        let source = root
            .appendingPathComponent(
                "legacy.xls"
            )
        let workbook =
            try makeLegacyXLSWorkbook()
        try makeOLEFile(
            streams: [
                "Workbook": workbook,
            ]
        ).write(to: source)

        let store = ChatAttachmentStore(
            attachmentDirectory:
                root.appendingPathComponent(
                    "Attachments",
                    isDirectory: true
                )
        )
        let attachment =
            try await store
            .importLegacySpreadsheet(
                from: source
            )

        XCTAssertEqual(
            attachment.mimeType,
            "application/vnd.ms-excel"
        )
        XCTAssertTrue(
            attachment.extractedText?
                .contains("[매출]") == true
        )
        XCTAssertTrue(
            attachment.extractedText?
                .contains(
                    "제품\t수량\t활성"
                ) == true
        )
        XCTAssertTrue(
            attachment.extractedText?
                .contains(
                    "사과\t12.0\ttrue"
                ) == true
        )
        XCTAssertTrue(
            attachment.extractedText?
                .contains(
                    "3.5\t계산됨"
                ) == true
        )
        XCTAssertTrue(
            attachment.extractedText?
                .contains("[메모]") == true
        )
        XCTAssertTrue(
            attachment.extractedText?
                .contains(
                    "긴 문자열 시작"
                ) == true
        )
        XCTAssertTrue(
            attachment.extractedText?
                .contains(
                    "긴 문자열 끝"
                ) == true
        )
        let storedURL = await store
            .existingURL(for: attachment)
        XCTAssertNotNil(
            storedURL
        )
    }

    func testLegacyXLSRejectsFilePass()
        throws
    {
        let workbook =
            try makeLegacyXLSWorkbook(
                includesFilePass: true
            )
        let fixture = try makeOLEFile(
            streams: [
                "Workbook": workbook,
            ]
        )
        XCTAssertThrowsError(
            try LegacyXLSExtractor.extract(
                from: fixture
            )
        ) {
            XCTAssertEqual(
                $0 as? ChatAttachmentError,
                .encryptedSpreadsheet
            )
        }
    }

    func testCompressedHWP5ExtractsParagraphControlsAndStoresOriginal()
        async throws
    {
        let root = try makeTemporaryRoot()
        defer {
            try? FileManager.default
                .removeItem(at: root)
        }
        let source = root
            .appendingPathComponent(
                "local.hwp"
            )
        try makeHWP5File(
            compressed: true
        ).write(to: source)
        let store = ChatAttachmentStore(
            attachmentDirectory:
                root.appendingPathComponent(
                    "Attachments",
                    isDirectory: true
                )
        )

        let attachment =
            try await store.importHWP(
                from: source
            )

        XCTAssertEqual(
            attachment.mimeType,
            "application/x-hwp"
        )
        XCTAssertTrue(
            attachment.extractedText?
                .contains(
                    "첫 문단\t탭 뒤"
                ) == true
        )
        XCTAssertTrue(
            attachment.extractedText?
                .contains(
                    "둘째 문단-끝"
                ) == true
        )
        XCTAssertFalse(
            attachment.extractedText?
                .contains("\0") == true
        )
        let storedURL = await store
            .existingURL(for: attachment)
        XCTAssertNotNil(
            storedURL
        )
    }

    func testHWP5RejectsProtectedAndMalformedDocuments()
        throws
    {
        let protected = try makeHWP5File(
            compressed: false,
            properties: 1 << 2
        )
        XCTAssertThrowsError(
            try HWP5TextExtractor.extract(
                from: protected
            )
        ) {
            XCTAssertEqual(
                $0 as? ChatAttachmentError,
                .encryptedHWP
            )
        }

        var malformedBody = Data()
        malformedBody.testAppendUInt32(
            UInt32(10 << 20) | 0x43
        )
        malformedBody.append(
            Data(repeating: 0, count: 2)
        )
        let malformed =
            try makeHWP5File(
                compressed: false,
                sectionOverride:
                    malformedBody
            )
        XCTAssertThrowsError(
            try HWP5TextExtractor.extract(
                from: malformed
            )
        ) {
            XCTAssertEqual(
                $0 as? ChatAttachmentError,
                .invalidHWP
            )
        }
    }

    @MainActor
    func testVisionLinkLocallyExtractsLegacyXLSAndHWP()
        async throws
    {
        let root = try makeTemporaryRoot()
        defer {
            try? FileManager.default
                .removeItem(at: root)
        }
        let xlsURL = root
            .appendingPathComponent(
                "remote.xls"
            )
        try makeOLEFile(
            streams: [
                "Workbook":
                    try makeLegacyXLSWorkbook(),
            ]
        ).write(to: xlsURL)
        let hwpURL = root
            .appendingPathComponent(
                "remote.hwp"
            )
        try makeHWP5File(
            compressed: true
        ).write(to: hwpURL)

        let service =
            VisionLinkLocalRemoteChatService
            .shared
        let spreadsheet =
            try await service.extractDocumentText(
                at: xlsURL,
                mimeType:
                    "application/vnd.ms-excel"
            )
        let hwp =
            try await service.extractDocumentText(
                at: hwpURL,
                mimeType:
                    "application/x-hwp"
            )

        XCTAssertTrue(
            spreadsheet.contains(
                "제품\t수량\t활성"
            )
        )
        XCTAssertTrue(
            spreadsheet.contains(
                "사과\t12.0\ttrue"
            )
        )
        XCTAssertTrue(
            hwp.contains(
                "첫 문단\t탭 뒤"
            )
        )
        XCTAssertTrue(
            hwp.contains(
                "둘째 문단-끝"
            )
        )
    }

    private func makeTemporaryRoot()
        throws -> URL
    {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "RivoLegacyAttachmentTests-"
                    + UUID().uuidString,
                isDirectory: true
            )
        try FileManager.default
            .createDirectory(
                at: root,
                withIntermediateDirectories:
                    true
            )
        return root
    }

    private func makeLegacyXLSWorkbook(
        includesFilePass: Bool = false
    ) throws -> Data {
        let longString =
            "긴 문자열 시작 "
            + String(
                repeating: "가나다라마바사 ",
                count: 1_100
            )
            + " 긴 문자열 끝"
        let sharedStrings = [
            "제품",
            "수량",
            "활성",
            "사과",
            "계산됨",
            longString,
        ]
        let sstRecords = try makeSSTRecords(
            sharedStrings
        )
        let sheet1 = makeBIFFSheet1()
        let sheet2 = makeBIFFSheet2()

        let globalBOF = biffRecord(
            0x0809,
            payload:
                makeBOFPayload(type: 0x0005)
        )
        let filePass = includesFilePass
            ? biffRecord(
                0x002F,
                payload: Data([0, 0])
            )
            : Data()
        let placeholder1 =
            makeBoundSheetRecord(
                offset: 0,
                name: "매출"
            )
        let placeholder2 =
            makeBoundSheetRecord(
                offset: 0,
                name: "메모"
            )
        let eof = biffRecord(
            0x000A,
            payload: Data()
        )
        let globalLength =
            globalBOF.count
            + filePass.count
            + placeholder1.count
            + placeholder2.count
            + sstRecords.count
            + eof.count
        let sheet1Offset = globalLength
        let sheet2Offset =
            sheet1Offset + sheet1.count

        var workbook = Data()
        workbook.append(globalBOF)
        workbook.append(filePass)
        workbook.append(
            makeBoundSheetRecord(
                offset: sheet1Offset,
                name: "매출"
            )
        )
        workbook.append(
            makeBoundSheetRecord(
                offset: sheet2Offset,
                name: "메모"
            )
        )
        workbook.append(sstRecords)
        workbook.append(eof)
        workbook.append(sheet1)
        workbook.append(sheet2)
        return workbook
    }

    private func makeSSTRecords(
        _ strings: [String]
    ) throws -> Data {
        var logical = Data()
        logical.testAppendUInt32(
            UInt32(strings.count)
        )
        logical.testAppendUInt32(
            UInt32(strings.count)
        )
        for string in strings {
            let units = Array(
                string.utf16
            )
            logical.testAppendUInt16(
                UInt16(units.count)
            )
            logical.append(1)
            for unit in units {
                logical.testAppendUInt16(
                    unit
                )
            }
        }

        // Split only within the final UTF-16 string and prepend the required
        // continuation encoding byte.
        let split = 8_222
        XCTAssertGreaterThan(
            logical.count,
            split
        )
        var result = biffRecord(
            0x00FC,
            payload: logical.subdata(
                in: 0..<split
            )
        )
        var cursor = split
        while cursor < logical.count {
            let end = min(
                logical.count,
                cursor + 8_222
            )
            var continuation = Data([1])
            continuation.append(
                logical.subdata(
                    in: cursor..<end
                )
            )
            result.append(
                biffRecord(
                    0x003C,
                    payload: continuation
                )
            )
            cursor = end
        }
        return result
    }

    private func makeBIFFSheet1() -> Data {
        var sheet = biffRecord(
            0x0809,
            payload:
                makeBOFPayload(type: 0x0010)
        )
        sheet.append(
            labelSST(
                row: 0,
                column: 0,
                index: 0
            )
        )
        sheet.append(
            labelSST(
                row: 0,
                column: 1,
                index: 1
            )
        )
        sheet.append(
            labelSST(
                row: 0,
                column: 2,
                index: 2
            )
        )
        sheet.append(
            labelSST(
                row: 1,
                column: 0,
                index: 3
            )
        )
        var number = cellHeader(
            row: 1,
            column: 1
        )
        number.testAppendDouble(12)
        sheet.append(
            biffRecord(
                0x0203,
                payload: number
            )
        )
        var boolean = cellHeader(
            row: 1,
            column: 2
        )
        boolean.append(contentsOf: [1, 0])
        sheet.append(
            biffRecord(
                0x0205,
                payload: boolean
            )
        )
        sheet.append(
            formulaRecord(
                row: 2,
                column: 0,
                numericValue: 3.5
            )
        )
        sheet.append(
            formulaStringRecord(
                row: 2,
                column: 1,
                string: "계산됨"
            )
        )
        sheet.append(
            biffRecord(
                0x000A,
                payload: Data()
            )
        )
        return sheet
    }

    private func makeBIFFSheet2() -> Data {
        var sheet = biffRecord(
            0x0809,
            payload:
                makeBOFPayload(type: 0x0010)
        )
        sheet.append(
            labelSST(
                row: 0,
                column: 0,
                index: 5
            )
        )
        sheet.append(
            biffRecord(
                0x000A,
                payload: Data()
            )
        )
        return sheet
    }

    private func makeBOFPayload(
        type: UInt16
    ) -> Data {
        var payload = Data()
        payload.testAppendUInt16(0x0600)
        payload.testAppendUInt16(type)
        payload.testAppendUInt16(0x0DBB)
        payload.testAppendUInt16(0x07CC)
        payload.testAppendUInt32(0x0000_0041)
        payload.testAppendUInt32(0x0000_0006)
        return payload
    }

    private func makeBoundSheetRecord(
        offset: Int,
        name: String
    ) -> Data {
        let units = Array(name.utf16)
        var payload = Data()
        payload.testAppendUInt32(
            UInt32(offset)
        )
        payload.append(contentsOf: [
            0, 0,
            UInt8(units.count),
            1,
        ])
        for unit in units {
            payload.testAppendUInt16(unit)
        }
        return biffRecord(
            0x0085,
            payload: payload
        )
    }

    private func labelSST(
        row: UInt16,
        column: UInt16,
        index: UInt32
    ) -> Data {
        var payload = cellHeader(
            row: row,
            column: column
        )
        payload.testAppendUInt32(index)
        return biffRecord(
            0x00FD,
            payload: payload
        )
    }

    private func cellHeader(
        row: UInt16,
        column: UInt16
    ) -> Data {
        var payload = Data()
        payload.testAppendUInt16(row)
        payload.testAppendUInt16(column)
        payload.testAppendUInt16(0)
        return payload
    }

    private func formulaRecord(
        row: UInt16,
        column: UInt16,
        numericValue: Double
    ) -> Data {
        var payload = cellHeader(
            row: row,
            column: column
        )
        payload.testAppendDouble(
            numericValue
        )
        payload.append(
            Data(repeating: 0, count: 8)
        )
        return biffRecord(
            0x0006,
            payload: payload
        )
    }

    private func formulaStringRecord(
        row: UInt16,
        column: UInt16,
        string: String
    ) -> Data {
        var payload = cellHeader(
            row: row,
            column: column
        )
        payload.append(
            contentsOf: [
                0, 0, 0, 0,
                0, 0, 0xFF, 0xFF,
            ]
        )
        payload.append(
            Data(repeating: 0, count: 8)
        )
        var result = biffRecord(
            0x0006,
            payload: payload
        )
        let units = Array(string.utf16)
        var stringPayload = Data()
        stringPayload.testAppendUInt16(
            UInt16(units.count)
        )
        stringPayload.append(1)
        for unit in units {
            stringPayload
                .testAppendUInt16(unit)
        }
        result.append(
            biffRecord(
                0x0207,
                payload: stringPayload
            )
        )
        return result
    }

    private func biffRecord(
        _ id: UInt16,
        payload: Data
    ) -> Data {
        var record = Data()
        record.testAppendUInt16(id)
        record.testAppendUInt16(
            UInt16(payload.count)
        )
        record.append(payload)
        return record
    }

    private func makeHWP5File(
        compressed: Bool,
        properties rawProperties:
            UInt32 = 0,
        sectionOverride: Data? = nil
    ) throws -> Data {
        var header = Data(
            repeating: 0,
            count: 256
        )
        header.replaceSubrange(
            0..<17,
            with: Data(
                "HWP Document File".utf8
            )
        )
        header.testSetUInt32(
            0x0500_0300,
            at: 32
        )
        let properties =
            rawProperties
            | (compressed ? 1 : 0)
        header.testSetUInt32(
            properties,
            at: 36
        )

        let plainSection =
            sectionOverride
            ?? makeHWPSection()
        let section = compressed
            ? try rawDeflate(plainSection)
            : plainSection
        return try makeOLEFile(
            streams: [
                "FileHeader": header,
                "BodyText/Section0":
                    section,
            ]
        )
    }

    private func makeHWPSection()
        -> Data
    {
        var section = Data()
        var first = Array(
            "첫 문단".utf16
        )
        first.append(contentsOf: [
            9, 0, 0, 0, 0, 0, 0, 9,
        ])
        first.append(
            contentsOf:
                Array("탭 뒤".utf16)
        )
        first.append(13)
        section.append(
            hwpParagraphRecord(first)
        )

        var second = Array(
            "둘째 문단".utf16
        )
        second.append(contentsOf: [
            11, 0, 0, 0, 0, 0, 0, 11,
        ])
        second.append(24)
        second.append(
            contentsOf:
                Array("끝".utf16)
        )
        second.append(13)
        section.append(
            hwpParagraphRecord(second)
        )
        return section
    }

    private func hwpParagraphRecord(
        _ units: [UInt16]
    ) -> Data {
        var payload = Data()
        for unit in units {
            payload.testAppendUInt16(unit)
        }
        var record = Data()
        record.testAppendUInt32(
            UInt32(payload.count << 20)
                | UInt32(1 << 10)
                | 0x43
        )
        record.append(payload)
        return record
    }

    private func rawDeflate(
        _ input: Data
    ) throws -> Data {
        var stream = z_stream()
        XCTAssertEqual(
            deflateInit2_(
                &stream,
                Z_DEFAULT_COMPRESSION,
                Z_DEFLATED,
                -MAX_WBITS,
                8,
                Z_DEFAULT_STRATEGY,
                ZLIB_VERSION,
                Int32(
                    MemoryLayout<z_stream>
                        .size
                )
            ),
            Z_OK
        )
        defer {
            deflateEnd(&stream)
        }

        return try input.withUnsafeBytes {
            rawInput in
            let bytes = rawInput.bindMemory(
                to: Bytef.self
            )
            stream.next_in =
                UnsafeMutablePointer(
                    mutating:
                        bytes.baseAddress
                )
            stream.avail_in =
                uInt(input.count)
            var output = Data()
            var chunk = [UInt8](
                repeating: 0,
                count: 1_024
            )
            while true {
                let status = chunk
                    .withUnsafeMutableBytes {
                        rawOutput in
                        let outputBytes =
                            rawOutput.bindMemory(
                                to: Bytef.self
                            )
                        stream.next_out =
                            outputBytes
                                .baseAddress
                        stream.avail_out =
                            uInt(
                                outputBytes
                                    .count
                            )
                        return deflate(
                            &stream,
                            Z_FINISH
                        )
                    }
                let produced =
                    chunk.count
                    - Int(stream.avail_out)
                output.append(
                    contentsOf:
                        chunk.prefix(produced)
                )
                if status == Z_STREAM_END {
                    return output
                }
                guard status == Z_OK
                        || status
                            == Z_BUF_ERROR
                else {
                    throw TestFixtureError
                        .compressionFailed
                }
            }
        }
    }
}

private enum TestFixtureError: Error {
    case invalidPath
    case tooLarge
    case compressionFailed
}

private struct OLETestEntry {
    let name: String
    let type: UInt8
    let parentPath: String
    var rightSibling = UInt32.max
    var child = UInt32.max
    var startSector =
        UInt32.max - 1
    var size: UInt64 = 0
}

private func makeOLEFile(
    streams: [String: Data]
) throws -> Data {
    let sectorSize = 512
    let miniSectorSize = 64
    let normalizedStreams = Dictionary(
        uniqueKeysWithValues:
            try streams.map {
                rawPath,
                data in
                let components =
                    rawPath.split(
                        separator: "/"
                    )
                    .map(String.init)
                guard !components.isEmpty,
                      components.allSatisfy({
                          !$0.isEmpty
                            && $0.utf16.count
                                <= 31
                      })
                else {
                    throw TestFixtureError
                        .invalidPath
                }
                return (
                    components.joined(
                        separator: "/"
                    ),
                    data
                )
            }
    )

    var storagePaths: Set<String> = []
    for path in normalizedStreams.keys {
        let parts = path.split(
            separator: "/"
        )
        if parts.count > 1 {
            for end in 1..<parts.count {
                storagePaths.insert(
                    parts[0..<end]
                        .joined(
                            separator: "/"
                        )
                )
            }
        }
    }

    var entries = [
        OLETestEntry(
            name: "Root Entry",
            type: 5,
            parentPath: ""
        ),
    ]
    var indexForPath = [
        "": 0,
    ]
    for path in storagePaths.sorted() {
        let parts = path.split(
            separator: "/"
        )
        let parent = parts.dropLast()
            .joined(separator: "/")
        indexForPath[path] =
            entries.count
        entries.append(
            OLETestEntry(
                name: String(parts.last!),
                type: 1,
                parentPath: parent
            )
        )
    }
    for path in normalizedStreams.keys
        .sorted()
    {
        let parts = path.split(
            separator: "/"
        )
        let parent = parts.dropLast()
            .joined(separator: "/")
        indexForPath[path] =
            entries.count
        entries.append(
            OLETestEntry(
                name: String(parts.last!),
                type: 2,
                parentPath: parent
            )
        )
    }
    guard entries.count <= 4 else {
        throw TestFixtureError.tooLarge
    }

    var children: [String: [Int]] = [:]
    for index in entries.indices
    where index > 0 {
        children[
            entries[index].parentPath,
            default: []
        ].append(index)
    }
    for (
        parent,
        rawChildren
    ) in children {
        let sorted = rawChildren.sorted {
            entries[$0].name
                < entries[$1].name
        }
        let parentIndex =
            indexForPath[parent]!
        entries[parentIndex].child =
            UInt32(sorted[0])
        for offset in sorted.indices
        where offset + 1 < sorted.count {
            entries[sorted[offset]]
                .rightSibling =
                    UInt32(
                        sorted[offset + 1]
                    )
        }
    }

    var miniStream = Data()
    var miniFAT: [UInt32] = []
    var regularStreams:
        [(entry: Int, data: Data)] = []
    for (
        path,
        streamData
    ) in normalizedStreams.sorted(
        by: {
            $0.key < $1.key
        }
    ) {
        let entryIndex =
            indexForPath[path]!
        entries[entryIndex].size =
            UInt64(streamData.count)
        if streamData.count < 4_096 {
            let firstMiniSector =
                miniFAT.count
            entries[entryIndex]
                .startSector =
                    streamData.isEmpty
                    ? UInt32.max - 1
                    : UInt32(
                        firstMiniSector
                    )
            let count = max(
                1,
                (
                    streamData.count
                    + miniSectorSize - 1
                ) / miniSectorSize
            )
            for miniIndex in 0..<count {
                miniFAT.append(
                    miniIndex == count - 1
                    ? UInt32.max - 1
                    : UInt32(
                        firstMiniSector
                        + miniIndex + 1
                    )
                )
                let start =
                    miniIndex
                    * miniSectorSize
                let end = min(
                    streamData.count,
                    start + miniSectorSize
                )
                if start < end {
                    miniStream.append(
                        streamData[start..<end]
                    )
                }
                if end - start
                    < miniSectorSize {
                    miniStream.append(
                        Data(
                            repeating: 0,
                            count:
                                miniSectorSize
                                - (end - start)
                        )
                    )
                }
            }
        } else {
            regularStreams.append(
                (entryIndex, streamData)
            )
        }
    }

    var sectors: [Data] = []
    var fat: [UInt32] = []
    func appendSectorChain(
        _ bytes: Data
    ) -> UInt32 {
        let first = sectors.count
        let count = max(
            1,
            (
                bytes.count
                + sectorSize - 1
            ) / sectorSize
        )
        for index in 0..<count {
            let start = index * sectorSize
            let end = min(
                bytes.count,
                start + sectorSize
            )
            var sector = Data()
            if start < end {
                sector.append(
                    bytes[start..<end]
                )
            }
            if sector.count < sectorSize {
                sector.append(
                    Data(
                        repeating: 0,
                        count:
                            sectorSize
                            - sector.count
                    )
                )
            }
            sectors.append(sector)
            fat.append(
                index == count - 1
                ? UInt32.max - 1
                : UInt32(first + index + 1)
            )
        }
        return UInt32(first)
    }

    // Reserve the directory sector first.
    sectors.append(
        Data(
            repeating: 0,
            count: sectorSize
        )
    )
    fat.append(UInt32.max - 1)

    let firstMiniFATSector:
        UInt32
    let miniFATSectorCount: Int
    if miniFAT.isEmpty {
        firstMiniFATSector =
            UInt32.max - 1
        miniFATSectorCount = 0
    } else {
        var miniFATData = Data()
        for value in miniFAT {
            miniFATData.testAppendUInt32(
                value
            )
        }
        while miniFATData.count
            % sectorSize != 0 {
            miniFATData.testAppendUInt32(
                UInt32.max
            )
        }
        firstMiniFATSector =
            appendSectorChain(
                miniFATData
            )
        miniFATSectorCount =
            miniFATData.count
            / sectorSize
    }

    if miniStream.isEmpty {
        entries[0].startSector =
            UInt32.max - 1
    } else {
        entries[0].startSector =
            appendSectorChain(
                miniStream
            )
        entries[0].size =
            UInt64(miniStream.count)
    }
    for (
        entryIndex,
        streamData
    ) in regularStreams {
        entries[entryIndex]
            .startSector =
                appendSectorChain(
                    streamData
                )
    }

    var directory = Data()
    for entry in entries {
        directory.append(
            makeOLEDirectoryEntry(entry)
        )
    }
    while directory.count < sectorSize {
        directory.append(
            Data(
                repeating: 0,
                count: min(
                    128,
                    sectorSize
                        - directory.count
                )
            )
        )
    }
    sectors[0] = directory

    guard sectors.count + 1 <= 128
    else {
        throw TestFixtureError.tooLarge
    }
    let fatSectorID = sectors.count
    fat.append(UInt32.max - 2)
    var fatSector = Data()
    for value in fat {
        fatSector.testAppendUInt32(value)
    }
    while fatSector.count < sectorSize {
        fatSector.testAppendUInt32(
            UInt32.max
        )
    }
    sectors.append(fatSector)

    var header = Data(
        repeating: 0,
        count: sectorSize
    )
    header.replaceSubrange(
        0..<8,
        with: Data([
            0xD0, 0xCF, 0x11, 0xE0,
            0xA1, 0xB1, 0x1A, 0xE1,
        ])
    )
    header.testSetUInt16(0x003E, at: 24)
    header.testSetUInt16(3, at: 26)
    header.testSetUInt16(0xFFFE, at: 28)
    header.testSetUInt16(9, at: 30)
    header.testSetUInt16(6, at: 32)
    header.testSetUInt32(0, at: 40)
    header.testSetUInt32(1, at: 44)
    header.testSetUInt32(0, at: 48)
    header.testSetUInt32(4_096, at: 56)
    header.testSetUInt32(
        firstMiniFATSector,
        at: 60
    )
    header.testSetUInt32(
        UInt32(miniFATSectorCount),
        at: 64
    )
    header.testSetUInt32(
        UInt32.max - 1,
        at: 68
    )
    header.testSetUInt32(0, at: 72)
    for index in 0..<109 {
        header.testSetUInt32(
            index == 0
                ? UInt32(fatSectorID)
                : UInt32.max,
            at: 76 + index * 4
        )
    }

    var file = header
    for sector in sectors {
        file.append(sector)
    }
    return file
}

private func makeOLEDirectoryEntry(
    _ entry: OLETestEntry
) -> Data {
    var data = Data(
        repeating: 0,
        count: 128
    )
    var nameUnits = Array(
        entry.name.utf16
    )
    nameUnits.append(0)
    for (
        index,
        unit
    ) in nameUnits.enumerated() {
        data.testSetUInt16(
            unit,
            at: index * 2
        )
    }
    data.testSetUInt16(
        UInt16(nameUnits.count * 2),
        at: 64
    )
    data[66] = entry.type
    data[67] = 1
    data.testSetUInt32(
        UInt32.max,
        at: 68
    )
    data.testSetUInt32(
        entry.rightSibling,
        at: 72
    )
    data.testSetUInt32(
        entry.child,
        at: 76
    )
    data.testSetUInt32(
        entry.startSector,
        at: 116
    )
    data.testSetUInt64(
        entry.size,
        at: 120
    )
    return data
}

private extension Data {
    mutating func testAppendUInt16(
        _ value: UInt16
    ) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func testAppendUInt32(
        _ value: UInt32
    ) {
        append(UInt8(value & 0xFF))
        append(
            UInt8((value >> 8) & 0xFF)
        )
        append(
            UInt8((value >> 16) & 0xFF)
        )
        append(
            UInt8((value >> 24) & 0xFF)
        )
    }

    mutating func testAppendDouble(
        _ value: Double
    ) {
        testAppendUInt64(
            value.bitPattern
        )
    }

    mutating func testAppendUInt64(
        _ value: UInt64
    ) {
        testAppendUInt32(
            UInt32(
                value & 0xFFFF_FFFF
            )
        )
        testAppendUInt32(
            UInt32(value >> 32)
        )
    }

    mutating func testSetUInt16(
        _ value: UInt16,
        at offset: Int
    ) {
        self[offset] =
            UInt8(value & 0xFF)
        self[offset + 1] =
            UInt8(value >> 8)
    }

    mutating func testSetUInt32(
        _ value: UInt32,
        at offset: Int
    ) {
        self[offset] =
            UInt8(value & 0xFF)
        self[offset + 1] =
            UInt8(
                (value >> 8) & 0xFF
            )
        self[offset + 2] =
            UInt8(
                (value >> 16) & 0xFF
            )
        self[offset + 3] =
            UInt8(
                (value >> 24) & 0xFF
            )
    }

    mutating func testSetUInt64(
        _ value: UInt64,
        at offset: Int
    ) {
        testSetUInt32(
            UInt32(
                value & 0xFFFF_FFFF
            ),
            at: offset
        )
        testSetUInt32(
            UInt32(value >> 32),
            at: offset + 4
        )
    }

    func testUInt32(
        at offset: Int
    ) throws -> UInt32 {
        guard offset >= 0,
              offset + 4 <= count else {
            throw TestFixtureError
                .tooLarge
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
