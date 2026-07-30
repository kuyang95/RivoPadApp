import Foundation

/// Local, read-only extraction for the BIFF8 workbook stream used by Excel
/// 97–2003 `.xls` files. Formatting, formulas, macros, and embedded objects are
/// never evaluated; only stored cell values are returned.
nonisolated enum LegacyXLSExtractor {
    static let maximumWorkbookBytes =
        20 * 1_024 * 1_024
    static let maximumSheets = 64
    static let maximumRowsPerSheet =
        20_000
    static let maximumCellsPerSheet =
        100_000
    static let maximumSharedStrings =
        200_000
    static let maximumOutputBytes =
        1_024 * 1_024

    static func extract(
        from data: Data
    ) throws -> String {
        guard data.count
                <= maximumWorkbookBytes else {
            throw ChatAttachmentError
                .fileTooLarge(
                    maximumMegabytes:
                        maximumWorkbookBytes
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
                            maximumWorkbookBytes,
                        maximumDirectoryEntries:
                            4_096,
                        maximumStreamBytes:
                            maximumWorkbookBytes,
                        maximumChainSectors:
                            65_536
                    )
                )
        } catch
            OLECompoundFileError
                .limitExceeded {
            throw ChatAttachmentError
                .spreadsheetLimitExceeded
        } catch {
            throw ChatAttachmentError
                .invalidSpreadsheet
        }

        let workbookData: Data
        do {
            if container.containsStream(
                named: "Workbook"
            ) {
                workbookData =
                    try container.stream(
                        named: "Workbook"
                    )
            } else {
                workbookData =
                    try container.stream(
                        named: "Book"
                    )
            }
        } catch {
            throw ChatAttachmentError
                .invalidSpreadsheet
        }

        let records = try parseRecords(
            workbookData
        )
        guard let firstBOF = records.first(
            where: {
                $0.id == 0x0809
            }
        ),
        firstBOF.payload.count >= 4
        else {
            throw ChatAttachmentError
                .invalidSpreadsheet
        }
        guard try firstBOF.payload
                .xlsUInt16(at: 0)
                == 0x0600 else {
            throw ChatAttachmentError
                .unsupportedLegacySpreadsheet
        }
        if records.contains(
            where: {
                $0.id == 0x002F
            }
        ) {
            throw ChatAttachmentError
                .encryptedSpreadsheet
        }

        let sheets = try parseSheets(
            records
        )
        guard !sheets.isEmpty else {
            throw ChatAttachmentError
                .invalidSpreadsheet
        }
        guard sheets.count
                <= maximumSheets else {
            throw ChatAttachmentError
                .spreadsheetLimitExceeded
        }
        let sharedStrings =
            try parseSharedStrings(
                records
            )

        var extracted:
            [LegacyXLSExtractedSheet] = []
        var didTruncate = false
        var remainingOutput =
            maximumOutputBytes

        for sheet in sheets {
            guard remainingOutput > 0 else {
                didTruncate = true
                break
            }
            let result = try parseCells(
                records,
                sheet: sheet,
                sharedStrings:
                    sharedStrings,
                maximumOutputBytes:
                    remainingOutput
            )
            remainingOutput -=
                result.text.utf8.count
            didTruncate =
                didTruncate
                || result.didTruncate
            extracted.append(
                LegacyXLSExtractedSheet(
                    name: sheet.name,
                    text: result.text
                )
            )
        }

        let nonempty = extracted.filter {
            !$0.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        }
        guard !nonempty.isEmpty else {
            throw ChatAttachmentError
                .documentHasNoText
        }
        let includesSheetNames =
            sheets.count > 1
        var result = nonempty.map {
            sheet in
            if includesSheetNames {
                return "[\(sheet.name)]\n"
                    + sheet.text
            }
            return sheet.text
        }
        .joined(separator: "\n")
        if didTruncate
            || nonempty.count < sheets.count {
            result += AppLocalization.string(
                "\n\n[스프레드시트 내용 일부 생략]"
            )
        }
        return result
    }

    private static func parseRecords(
        _ data: Data
    ) throws -> [LegacyXLSRecord] {
        var records: [LegacyXLSRecord] =
            []
        var offset = 0
        while offset + 4 <= data.count {
            let id =
                try data.xlsUInt16(
                    at: offset
                )
            let size = Int(
                try data.xlsUInt16(
                    at: offset + 2
                )
            )
            let payloadStart = offset + 4
            let payloadEnd =
                payloadStart + size
            guard payloadEnd <= data.count
            else {
                throw ChatAttachmentError
                    .invalidSpreadsheet
            }
            records.append(
                LegacyXLSRecord(
                    id: id,
                    offset: offset,
                    payload: data.subdata(
                        in:
                            payloadStart..<payloadEnd
                    )
                )
            )
            offset = payloadEnd
            if id == 0 && size == 0 {
                let remaining =
                    data[offset...]
                if remaining.allSatisfy({
                    $0 == 0
                }) {
                    break
                }
            }
            guard records.count
                    <= 1_000_000 else {
                throw ChatAttachmentError
                    .spreadsheetLimitExceeded
            }
        }
        guard !records.isEmpty else {
            throw ChatAttachmentError
                .invalidSpreadsheet
        }
        return records
    }

    private static func parseSheets(
        _ records: [LegacyXLSRecord]
    ) throws -> [LegacyXLSSheet] {
        var sheets: [LegacyXLSSheet] = []
        for record in records
        where record.id == 0x0085 {
            guard record.payload.count >= 8
            else {
                throw ChatAttachmentError
                    .invalidSpreadsheet
            }
            let streamOffset = Int(
                try record.payload
                    .xlsUInt32(at: 0)
            )
            let characterCount = Int(
                record.payload[6]
            )
            let isUTF16 =
                record.payload[7] & 0x01
                != 0
            let byteCount =
                characterCount
                * (isUTF16 ? 2 : 1)
            guard characterCount > 0,
                  8 + byteCount
                    <= record.payload.count
            else {
                throw ChatAttachmentError
                    .invalidSpreadsheet
            }
            let name = try decodeCharacters(
                record.payload.subdata(
                    in:
                        8..<(8 + byteCount)
                ),
                count: characterCount,
                isUTF16: isUTF16
            )
            sheets.append(
                LegacyXLSSheet(
                    name:
                        normalizedCellText(
                            name
                        ),
                    streamOffset:
                        streamOffset,
                    isWorksheet:
                        record.payload[5]
                        == 0
                )
            )
        }
        return sheets
    }

    private static func parseSharedStrings(
        _ records: [LegacyXLSRecord]
    ) throws -> [String] {
        guard let index = records
            .firstIndex(
                where: {
                    $0.id == 0x00FC
                }
            ) else {
            return []
        }
        var segments = [
            records[index].payload,
        ]
        var next = index + 1
        while next < records.count,
              records[next].id == 0x003C {
            segments.append(
                records[next].payload
            )
            next += 1
        }
        var reader =
            LegacyXLSContinuationReader(
                segments: segments
            )
        _ = try reader.readUInt32()
        let uniqueCount = Int(
            try reader.readUInt32()
        )
        guard uniqueCount >= 0,
              uniqueCount
                <= maximumSharedStrings
        else {
            throw ChatAttachmentError
                .spreadsheetLimitExceeded
        }

        var strings: [String] = []
        strings.reserveCapacity(uniqueCount)
        for _ in 0..<uniqueCount {
            strings.append(
                try reader
                    .readRichString()
            )
        }
        return strings
    }

    private static func parseCells(
        _ records: [LegacyXLSRecord],
        sheet: LegacyXLSSheet,
        sharedStrings: [String],
        maximumOutputBytes: Int
    ) throws -> (
        text: String,
        didTruncate: Bool
    ) {
        guard sheet.isWorksheet else {
            return ("", false)
        }
        guard let start = records.firstIndex(
            where: {
                $0.offset
                    == sheet.streamOffset
                    && $0.id == 0x0809
            }
        ),
        records[start].payload.count >= 4,
        try records[start].payload
            .xlsUInt16(at: 0) == 0x0600,
        try records[start].payload
            .xlsUInt16(at: 2) == 0x0010
        else {
            throw ChatAttachmentError
                .invalidSpreadsheet
        }

        var rows:
            [Int: [Int: String]] = [:]
        var cellCount = 0
        var pendingFormula:
            (row: Int, column: Int)?

        func add(
            row: Int,
            column: Int,
            value rawValue: String
        ) throws {
            guard row >= 0,
                  row <= 65_535,
                  column >= 0,
                  column <= 255 else {
                throw ChatAttachmentError
                    .invalidSpreadsheet
            }
            let value =
                normalizedCellText(
                    rawValue
                )
            guard !value.isEmpty else {
                return
            }
            if rows[row]?[column] == nil {
                cellCount += 1
            }
            guard cellCount
                    <= maximumCellsPerSheet
            else {
                throw ChatAttachmentError
                    .spreadsheetLimitExceeded
            }
            rows[row, default: [:]][
                column
            ] = value
            guard rows.count
                    <= maximumRowsPerSheet
            else {
                throw ChatAttachmentError
                    .spreadsheetLimitExceeded
            }
        }

        var index = start + 1
        while index < records.count {
            let record = records[index]
            if record.id == 0x000A {
                break
            }
            if record.id != 0x0207 {
                pendingFormula = nil
            }

            switch record.id {
            case 0x00FD: // LabelSst
                guard record.payload.count
                        >= 10 else {
                    throw ChatAttachmentError
                        .invalidSpreadsheet
                }
                let stringIndex = Int(
                    try record.payload
                        .xlsUInt32(at: 6)
                )
                guard stringIndex
                        < sharedStrings.count
                else {
                    throw ChatAttachmentError
                        .invalidSpreadsheet
                }
                try add(
                    row: Int(
                        try record.payload
                            .xlsUInt16(at: 0)
                    ),
                    column: Int(
                        try record.payload
                            .xlsUInt16(at: 2)
                    ),
                    value:
                        sharedStrings[
                            stringIndex
                        ]
                )
            case 0x0203: // Number
                guard record.payload.count
                        >= 14 else {
                    throw ChatAttachmentError
                        .invalidSpreadsheet
                }
                try add(
                    row: Int(
                        try record.payload
                            .xlsUInt16(at: 0)
                    ),
                    column: Int(
                        try record.payload
                            .xlsUInt16(at: 2)
                    ),
                    value: String(
                        try record.payload
                            .xlsDouble(at: 6)
                    )
                )
            case 0x027E: // RK
                guard record.payload.count
                        >= 10 else {
                    throw ChatAttachmentError
                        .invalidSpreadsheet
                }
                try add(
                    row: Int(
                        try record.payload
                            .xlsUInt16(at: 0)
                    ),
                    column: Int(
                        try record.payload
                            .xlsUInt16(at: 2)
                    ),
                    value: String(
                        decodeRK(
                            try record.payload
                                .xlsUInt32(
                                    at: 6
                                )
                        )
                    )
                )
            case 0x00BD: // MulRk
                guard record.payload.count
                        >= 12 else {
                    throw ChatAttachmentError
                        .invalidSpreadsheet
                }
                let row = Int(
                    try record.payload
                        .xlsUInt16(at: 0)
                )
                let firstColumn = Int(
                    try record.payload
                        .xlsUInt16(at: 2)
                )
                let lastColumn = Int(
                    try record.payload
                        .xlsUInt16(
                            at:
                                record.payload
                                    .count - 2
                        )
                )
                let count =
                    lastColumn
                    - firstColumn + 1
                guard count >= 0,
                      4 + count * 6 + 2
                        == record.payload
                            .count
                else {
                    throw ChatAttachmentError
                        .invalidSpreadsheet
                }
                for cellIndex in 0..<count {
                    try add(
                        row: row,
                        column:
                            firstColumn
                            + cellIndex,
                        value: String(
                            decodeRK(
                                try record
                                    .payload
                                    .xlsUInt32(
                                        at:
                                            6
                                            + cellIndex
                                            * 6
                                    )
                            )
                        )
                    )
                }
            case 0x0205: // BoolErr
                guard record.payload.count
                        >= 8 else {
                    throw ChatAttachmentError
                        .invalidSpreadsheet
                }
                if record.payload[7] == 0 {
                    try add(
                        row: Int(
                            try record.payload
                                .xlsUInt16(
                                    at: 0
                                )
                        ),
                        column: Int(
                            try record.payload
                                .xlsUInt16(
                                    at: 2
                                )
                        ),
                        value:
                            record.payload[6]
                                == 0
                            ? "false"
                            : "true"
                    )
                }
            case 0x0006: // Formula
                guard record.payload.count
                        >= 14 else {
                    throw ChatAttachmentError
                        .invalidSpreadsheet
                }
                let row = Int(
                    try record.payload
                        .xlsUInt16(at: 0)
                )
                let column = Int(
                    try record.payload
                        .xlsUInt16(at: 2)
                )
                if try record.payload
                    .xlsUInt16(at: 12)
                    == 0xFFFF {
                    switch record.payload[6] {
                    case 0:
                        pendingFormula = (
                            row,
                            column
                        )
                    case 1:
                        try add(
                            row: row,
                            column: column,
                            value:
                                record.payload[8]
                                    == 0
                                ? "false"
                                : "true"
                        )
                    default:
                        break
                    }
                } else {
                    try add(
                        row: row,
                        column: column,
                        value: String(
                            try record.payload
                                .xlsDouble(
                                    at: 6
                                )
                        )
                    )
                }
            case 0x0207: // String
                if let formula =
                    pendingFormula {
                    var segments = [
                        record.payload,
                    ]
                    while index + 1
                            < records.count,
                          records[index + 1]
                            .id == 0x003C {
                        index += 1
                        segments.append(
                            records[index]
                                .payload
                        )
                    }
                    var reader =
                        LegacyXLSContinuationReader(
                            segments: segments
                        )
                    try add(
                        row:
                            formula.row,
                        column:
                            formula
                                .column,
                        value:
                            try reader
                                .readRichString()
                    )
                    pendingFormula = nil
                }
            case 0x0204, 0x00D6:
                guard record.payload.count
                        >= 9 else {
                    throw ChatAttachmentError
                        .invalidSpreadsheet
                }
                try add(
                    row: Int(
                        try record.payload
                            .xlsUInt16(at: 0)
                    ),
                    column: Int(
                        try record.payload
                            .xlsUInt16(at: 2)
                    ),
                    value:
                        try parseUnicodeString(
                            record.payload
                                .subdata(
                                    in:
                                        6 ..< record
                                            .payload
                                            .count
                                )
                        )
                )
            default:
                break
            }
            index += 1
        }

        var output = ""
        var outputBytes = 0
        var didTruncate = false
        for row in rows.keys.sorted() {
            let line = rows[row]!
                .sorted {
                    $0.key < $1.key
                }
                .map(\.value)
                .joined(separator: "\t")
                + "\n"
            let lineBytes = line.utf8.count
            guard outputBytes + lineBytes
                    <= maximumOutputBytes
            else {
                didTruncate = true
                break
            }
            output += line
            outputBytes += lineBytes
        }
        return (
            output.trimmingCharacters(
                in: .newlines
            ),
            didTruncate
        )
    }

    private static func parseUnicodeString(
        _ data: Data
    ) throws -> String {
        guard data.count >= 3 else {
            throw ChatAttachmentError
                .invalidSpreadsheet
        }
        let count = Int(
            try data.xlsUInt16(at: 0)
        )
        let flags = data[2]
        let isUTF16 = flags & 0x01 != 0
        var offset = 3
        if flags & 0x08 != 0 {
            offset += 2
        }
        if flags & 0x04 != 0 {
            offset += 4
        }
        let byteCount =
            count * (isUTF16 ? 2 : 1)
        guard offset >= 3,
              offset + byteCount
                <= data.count else {
            throw ChatAttachmentError
                .invalidSpreadsheet
        }
        return try decodeCharacters(
            data.subdata(
                in:
                    offset..<(offset + byteCount)
            ),
            count: count,
            isUTF16: isUTF16
        )
    }

    private static func decodeCharacters(
        _ data: Data,
        count: Int,
        isUTF16: Bool
    ) throws -> String {
        if isUTF16 {
            guard data.count == count * 2
            else {
                throw ChatAttachmentError
                    .invalidSpreadsheet
            }
            var units: [UInt16] = []
            units.reserveCapacity(count)
            for offset in stride(
                from: 0,
                to: data.count,
                by: 2
            ) {
                units.append(
                    try data.xlsUInt16(
                        at: offset
                    )
                )
            }
            return String(
                decoding: units,
                as: UTF16.self
            )
        }
        guard data.count == count else {
            throw ChatAttachmentError
                .invalidSpreadsheet
        }
        return String(
            decoding:
                data.map(UInt16.init),
            as: UTF16.self
        )
    }

    private static func decodeRK(
        _ raw: UInt32
    ) -> Double {
        let value: Double
        if raw & 0x02 != 0 {
            value = Double(
                Int32(bitPattern: raw)
                    >> 2
            )
        } else {
            let bits =
                UInt64(
                    raw & 0xFFFF_FFFC
                ) << 32
            value = Double(
                bitPattern: bits
            )
        }
        return raw & 0x01 != 0
            ? value / 100
            : value
    }

    private static func normalizedCellText(
        _ raw: String
    ) -> String {
        raw.replacingOccurrences(
            of: "\r\n",
            with: " "
        )
        .replacingOccurrences(
            of: "\r",
            with: " "
        )
        .replacingOccurrences(
            of: "\n",
            with: " "
        )
        .replacingOccurrences(
            of: "\t",
            with: " "
        )
        .trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

}

private nonisolated struct LegacyXLSRecord {
    let id: UInt16
    let offset: Int
    let payload: Data
}

private nonisolated struct LegacyXLSSheet {
    let name: String
    let streamOffset: Int
    let isWorksheet: Bool
}

private nonisolated struct
    LegacyXLSExtractedSheet
{
    let name: String
    let text: String
}

private nonisolated struct
    LegacyXLSContinuationReader
{
    let segments: [Data]
    var segmentIndex = 0
    var offset = 0

    mutating func readUInt32()
        throws -> UInt32
    {
        let bytes = try readRawBytes(4)
        return try bytes.xlsUInt32(at: 0)
    }

    mutating func readRichString()
        throws -> String
    {
        let header = try readRawBytes(3)
        let characterCount = Int(
            try header.xlsUInt16(at: 0)
        )
        let flags = header[2]
        var isUTF16 =
            flags & 0x01 != 0
        let richRunCount: Int
        if flags & 0x08 != 0 {
            richRunCount = Int(
                try readRawBytes(2)
                    .xlsUInt16(at: 0)
            )
        } else {
            richRunCount = 0
        }
        let extendedByteCount: Int
        if flags & 0x04 != 0 {
            extendedByteCount = Int(
                try readRawBytes(4)
                    .xlsUInt32(at: 0)
            )
        } else {
            extendedByteCount = 0
        }
        guard characterCount <= 32_767,
              richRunCount <= 4_096,
              extendedByteCount
                <= 16 * 1_024 * 1_024
        else {
            throw ChatAttachmentError
                .spreadsheetLimitExceeded
        }

        var units: [UInt16] = []
        units.reserveCapacity(
            characterCount
        )
        for _ in 0..<characterCount {
            let width = isUTF16 ? 2 : 1
            if bytesRemainingInSegment
                < width {
                try moveToNextSegment()
                guard bytesRemainingInSegment
                        >= 1 else {
                    throw ChatAttachmentError
                        .invalidSpreadsheet
                }
                isUTF16 =
                    try readByteInCurrentSegment()
                        & 0x01 != 0
            }
            if isUTF16 {
                let low =
                    try readByteInCurrentSegment()
                let high =
                    try readByteInCurrentSegment()
                units.append(
                    UInt16(low)
                    | UInt16(high) << 8
                )
            } else {
                units.append(
                    UInt16(
                        try readByteInCurrentSegment()
                    )
                )
            }
        }

        _ = try readRawBytes(
            richRunCount * 4
        )
        _ = try readRawBytes(
            extendedByteCount
        )
        return String(
            decoding: units,
            as: UTF16.self
        )
    }

    private var bytesRemainingInSegment:
        Int
    {
        guard segmentIndex
                < segments.count else {
            return 0
        }
        return segments[segmentIndex]
            .count - offset
    }

    private mutating func
        readRawBytes(
            _ count: Int
        ) throws -> Data {
        guard count >= 0 else {
            throw ChatAttachmentError
                .invalidSpreadsheet
        }
        var output = Data()
        output.reserveCapacity(count)
        while output.count < count {
            if bytesRemainingInSegment == 0 {
                try moveToNextSegment()
            }
            let amount = min(
                count - output.count,
                bytesRemainingInSegment
            )
            guard amount > 0 else {
                throw ChatAttachmentError
                    .invalidSpreadsheet
            }
            output.append(
                segments[segmentIndex][
                    offset..<(offset + amount)
                ]
            )
            offset += amount
        }
        return output
    }

    private mutating func
        readByteInCurrentSegment()
        throws -> UInt8
    {
        guard segmentIndex < segments.count,
              offset
                < segments[segmentIndex]
                    .count else {
            throw ChatAttachmentError
                .invalidSpreadsheet
        }
        defer {
            offset += 1
        }
        return segments[segmentIndex][
            offset
        ]
    }

    private mutating func
        moveToNextSegment() throws {
        segmentIndex += 1
        offset = 0
        guard segmentIndex
                < segments.count else {
            throw ChatAttachmentError
                .invalidSpreadsheet
        }
    }
}

private extension Data {
    nonisolated func xlsUInt16(
        at offset: Int
    ) throws -> UInt16 {
        guard offset >= 0,
              offset + 2 <= count else {
            throw ChatAttachmentError
                .invalidSpreadsheet
        }
        return UInt16(self[offset])
            | UInt16(self[offset + 1])
                << 8
    }

    nonisolated func xlsUInt32(
        at offset: Int
    ) throws -> UInt32 {
        guard offset >= 0,
              offset + 4 <= count else {
            throw ChatAttachmentError
                .invalidSpreadsheet
        }
        return UInt32(self[offset])
            | UInt32(self[offset + 1])
                << 8
            | UInt32(self[offset + 2])
                << 16
            | UInt32(self[offset + 3])
                << 24
    }

    nonisolated func xlsUInt64(
        at offset: Int
    ) throws -> UInt64 {
        UInt64(
            try xlsUInt32(at: offset)
        )
        | UInt64(
            try xlsUInt32(
                at: offset + 4
            )
        ) << 32
    }

    nonisolated func xlsDouble(
        at offset: Int
    ) throws -> Double {
        Double(
            bitPattern:
                try xlsUInt64(at: offset)
        )
    }
}
