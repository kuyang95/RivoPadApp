import Foundation
import RivoZIPFoundation

/// Creates a new, editable OOXML workbook from the values that can be read
/// safely from an Excel 97–2003 BIFF8 workbook. This is intentionally a
/// values-only conversion: formulas, styles, merged cells, charts, images,
/// macros, and other workbook features are not copied.
public nonisolated enum LegacyXLSXConverter {
    public static func convert(
        from data: Data
    ) throws -> Data {
        try encode(
            LegacyXLSExtractor.workbook(
                from: data
            )
        )
    }

    public static func encode(
        _ workbook:
            LegacyXLSWorkbookSnapshot
    ) throws -> Data {
        guard !workbook.sheets.isEmpty,
              workbook.sheets.count
                <= ExcelWorkbookDocument
                    .maximumSheets else {
            throw ExcelWorkbookDocumentError
                .cannotSave
        }

        let sheetNames = uniqueSheetNames(
            workbook.sheets.map(\.name)
        )
        var entries: [String: Data] = [:]
        entries["[Content_Types].xml"] =
            Data(
                contentTypesXML(
                    sheetCount:
                        workbook.sheets.count
                ).utf8
            )
        entries["_rels/.rels"] = Data(
            rootRelationshipsXML.utf8
        )
        entries["xl/workbook.xml"] =
            Data(
                workbookXML(
                    sheetNames: sheetNames
                ).utf8
            )
        entries[
            "xl/_rels/workbook.xml.rels"
        ] = Data(
            workbookRelationshipsXML(
                sheetCount:
                    workbook.sheets.count
            ).utf8
        )
        entries["xl/styles.xml"] = Data(
            stylesXML.utf8
        )

        for (index, sheet) in workbook
            .sheets.enumerated() {
            entries[
                "xl/worksheets/sheet\(index + 1).xml"
            ] = try worksheetData(
                sheet
            )
        }

        let archive = try Archive(
            accessMode: .create
        )
        for (path, payload) in entries
            .sorted(by: {
                $0.key < $1.key
            }) {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize:
                    Int64(payload.count),
                compressionMethod: .deflate
            ) { position, size in
                let lower = Int(position)
                let upper = min(
                    payload.count,
                    lower + size
                )
                guard lower < upper else {
                    return Data()
                }
                return payload.subdata(
                    in: lower..<upper
                )
            }
        }
        guard let result = archive.data,
              result.count
                <= ExcelWorkbookDocument
                    .maximumWorkbookBytes else {
            throw ExcelWorkbookDocumentError
                .workbookLimitExceeded
        }
        return result
    }

    private static func worksheetData(
        _ sheet: LegacyXLSSheetSnapshot
    ) throws -> Data {
        let sortedCells = sheet.cells.sorted {
            if $0.row != $1.row {
                return $0.row < $1.row
            }
            return $0.column < $1.column
        }
        var maximumRow = 1
        var maximumColumn = 1
        var rows: [String] = []
        rows.reserveCapacity(
            min(sortedCells.count, 20_000)
        )
        var currentRow: Int?
        var currentCells = ""
        var sheetDataByteCount = 0

        func appendCurrentRow() throws {
            guard let currentRow else {
                return
            }
            let rowXML = "<row r=\"\(currentRow)\">"
                + currentCells
                + "</row>"
            sheetDataByteCount +=
                rowXML.utf8.count
            guard sheetDataByteCount
                    <= ExcelWorkbookDocument
                        .maximumEntryBytes
                        - 2_048 else {
                throw ExcelWorkbookDocumentError
                    .workbookLimitExceeded
            }
            rows.append(rowXML)
        }

        for cell in sortedCells {
            guard cell.row > 0,
                  cell.row
                    <= ExcelWorkbookDocument
                        .maximumExcelRows,
                  cell.column > 0,
                  cell.column
                    <= ExcelWorkbookDocument
                        .maximumExcelColumns
            else {
                throw ExcelWorkbookDocumentError
                    .cannotSave
            }
            if currentRow != cell.row {
                try appendCurrentRow()
                currentRow = cell.row
                currentCells = ""
            }
            maximumRow = max(
                maximumRow,
                cell.row
            )
            maximumColumn = max(
                maximumColumn,
                cell.column
            )
            currentCells += cellXML(cell)
        }
        try appendCurrentRow()

        let dimension = sortedCells.isEmpty
            ? "A1"
            : "A1:"
                + ExcelCellAddress(
                    row: maximumRow,
                    column: maximumColumn
                ).reference
        let xml = xmlDeclaration
            + "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
            + "<dimension ref=\"\(dimension)\"/>"
            + "<sheetViews><sheetView workbookViewId=\"0\"/></sheetViews>"
            + "<sheetFormatPr defaultRowHeight=\"15\"/>"
            + "<sheetData>"
            + rows.joined()
            + "</sheetData></worksheet>"
        let data = Data(xml.utf8)
        guard data.count
                <= ExcelWorkbookDocument
                    .maximumEntryBytes else {
            throw ExcelWorkbookDocumentError
                .workbookLimitExceeded
        }
        return data
    }

    private static func cellXML(
        _ cell: LegacyXLSCellSnapshot
    ) -> String {
        let reference = ExcelCellAddress(
            row: cell.row,
            column: cell.column
        ).reference
        switch cell.value {
        case .text(let rawValue):
            let value = validXMLText(
                rawValue
            )
            let preserve =
                value.first?.isWhitespace
                    == true
                || value.last?.isWhitespace
                    == true
                ? " xml:space=\"preserve\""
                : ""
            return "<c r=\"\(reference)\" t=\"inlineStr\"><is><t\(preserve)>"
                + escapeXML(value)
                + "</t></is></c>"
        case .number(let value):
            return "<c r=\"\(reference)\"><v>"
                + String(value)
                + "</v></c>"
        case .boolean(let value):
            return "<c r=\"\(reference)\" t=\"b\"><v>"
                + (value ? "1" : "0")
                + "</v></c>"
        }
    }

    private static func uniqueSheetNames(
        _ source: [String]
    ) -> [String] {
        var used = Set<String>()
        return source.enumerated().map {
            index,
            rawName in
            let cleaned = validXMLText(
                rawName
            )
            let base = cleaned.isEmpty
                ? "Sheet\(index + 1)"
                : String(cleaned.prefix(31))
            var candidate = base
            var suffix = 2
            while used.contains(
                candidate.lowercased()
            ) {
                let marker = " (\(suffix))"
                candidate = String(
                    base.prefix(
                        max(31 - marker.count, 1)
                    )
                ) + marker
                suffix += 1
            }
            used.insert(candidate.lowercased())
            return candidate
        }
    }

    private static func contentTypesXML(
        sheetCount: Int
    ) -> String {
        let worksheets = (1...sheetCount)
            .map {
                "<Override PartName=\"/xl/worksheets/sheet\($0).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
            }
            .joined()
        return xmlDeclaration
            + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
            + "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
            + "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
            + "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
            + "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
            + worksheets
            + "</Types>"
    }

    private static func workbookXML(
        sheetNames: [String]
    ) -> String {
        let sheets = sheetNames.enumerated()
            .map {
                index,
                name in
                "<sheet name=\""
                    + escapeXML(name)
                    + "\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>"
            }
            .joined()
        return xmlDeclaration
            + "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
            + "<bookViews><workbookView/></bookViews><sheets>"
            + sheets
            + "</sheets><calcPr calcId=\"0\"/></workbook>"
    }

    private static func workbookRelationshipsXML(
        sheetCount: Int
    ) -> String {
        let sheets = (1...sheetCount)
            .map {
                "<Relationship Id=\"rId\($0)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0).xml\"/>"
            }
            .joined()
        return xmlDeclaration
            + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + sheets
            + "<Relationship Id=\"rId\(sheetCount + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
            + "</Relationships>"
    }

    private static let xmlDeclaration =
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"

    private static let rootRelationshipsXML =
        xmlDeclaration
        + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        + "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/>"
        + "</Relationships>"

    private static let stylesXML =
        xmlDeclaration
        + "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        + "<fonts count=\"1\"><font><sz val=\"11\"/><name val=\"Aptos\"/><family val=\"2\"/></font></fonts>"
        + "<fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills>"
        + "<borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders>"
        + "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
        + "<cellXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/></cellXfs>"
        + "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles>"
        + "</styleSheet>"

    private static func validXMLText(
        _ source: String
    ) -> String {
        var result = ""
        result.unicodeScalars.reserveCapacity(
            source.unicodeScalars.count
        )
        for scalar in source.unicodeScalars {
            let value = scalar.value
            if value == 0x09
                || value == 0x0A
                || value == 0x0D
                || (0x20...0xD7FF)
                    .contains(value)
                || (0xE000...0xFFFD)
                    .contains(value)
                || (0x10000...0x10FFFF)
                    .contains(value) {
                result.unicodeScalars
                    .append(scalar)
            }
        }
        return result
    }

    private static func escapeXML(
        _ value: String
    ) -> String {
        value
            .replacingOccurrences(
                of: "&",
                with: "&amp;"
            )
            .replacingOccurrences(
                of: "<",
                with: "&lt;"
            )
            .replacingOccurrences(
                of: ">",
                with: "&gt;"
            )
            .replacingOccurrences(
                of: "\"",
                with: "&quot;"
            )
            .replacingOccurrences(
                of: "'",
                with: "&apos;"
            )
    }
}
