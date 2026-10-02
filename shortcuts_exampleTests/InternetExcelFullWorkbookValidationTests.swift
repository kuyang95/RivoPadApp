import RivoDocumentEngine
import XCTest
import ZIPFoundation
@testable import shortcuts_example

final class InternetExcelFullWorkbookValidationTests: XCTestCase {
    private let fixtureNames = [
        "Sparklines",
        "PivotTable_CachedDefinitionAndDataInSync",
        "image_hyperlink",
        "data_validation_test",
        "ProtecteSheet1234Pass",
    ]

    func testEverySheetLoadsAndSurvivesAnEditedRoundTrip() throws {
        var workbookReports = [String]()
        var totalSheets = 0
        var totalCells = 0

        for fixtureName in fixtureNames {
            let source = try fixtureData(named: fixtureName)
            let preflight = try ExcelWorkbookDocument.preflight(from: source)
            let workbook = try ExcelWorkbookDocument.load(from: source)
            XCTAssertFalse(workbook.sheets.isEmpty, fixtureName)
            XCTAssertEqual(
                workbook.sheets.map(\.name),
                preflight.sheets.map(\.name),
                "Preflight and full parsing must enumerate the same sheets: \(fixtureName)"
            )

            for sheet in workbook.sheets {
                let summary = try XCTUnwrap(
                    preflight.sheet(partPath: sheet.partPath),
                    "Missing preflight sheet \(sheet.name)"
                )
                XCTAssertEqual(sheet.maximumRow, summary.maximumRow, fixtureName)
                XCTAssertEqual(sheet.maximumColumn, summary.maximumColumn, fixtureName)
                XCTAssertEqual(sheet.cells.count, summary.cellCount, fixtureName)
                XCTAssertFalse(sheet.didTruncate, fixtureName)
                XCTAssertTrue(sheet.cells.keys.allSatisfy {
                    $0.row <= max(sheet.maximumRow, 1)
                        && $0.column <= max(sheet.maximumColumn, 1)
                }, "Parsed a cell outside the used range: \(fixtureName) \(sheet.name)")
            }

            try assertTargetFeature(fixtureName, source: source, workbook: workbook)
            let reloaded = try editedRoundTrip(
                fixtureName: fixtureName,
                source: source,
                workbook: workbook
            )
            XCTAssertEqual(
                workbookFeatureDigest(workbook),
                workbookFeatureDigest(reloaded),
                "Workbook features changed during round trip: \(fixtureName)"
            )

            let sheetReports = workbook.sheets.map { sheet in
                let formulas = sheet.cells.values.filter {
                    $0.formula?.isEmpty == false
                }.count
                return [
                    "sheet=\(sheet.name)",
                    "range=\(sheet.maximumRow)x\(sheet.maximumColumn)",
                    "cells=\(sheet.cells.count)",
                    "formulas=\(formulas)",
                    "merged=\(sheet.mergedRanges.count)",
                    "tables=\(sheet.tables.count)",
                    "validations=\(sheet.dataValidations.count)",
                    "conditional=\(sheet.conditionalFormatting.count)",
                    "hyperlinks=\(sheet.annotations.hyperlinks.count)",
                    "notes=\(sheet.annotations.notes.count)",
                    "images=\(sheet.drawingObjects.images.count)",
                    "charts=\(sheet.drawingObjects.charts.count)",
                    "shapes=\(sheet.drawingObjects.shapes.count)",
                    "pivots=\(sheet.pivotTables.count)",
                    "protected=\(sheet.protection.isEnabled)",
                ].joined(separator: " ")
            }
            workbookReports.append(
                "\(fixtureName).xlsx bytes=\(source.count) sheets=\(workbook.sheets.count)\n"
                    + sheetReports.joined(separator: "\n")
            )
            totalSheets += workbook.sheets.count
            totalCells += workbook.sheets.reduce(0) { $0 + $1.cells.count }
        }

        let report = """
        New internet XLSX full-workbook validation
        workbooks=\(fixtureNames.count)
        sheets=\(totalSheets)
        cells=\(totalCells)
        everySheetParsed=true
        editedRoundTrip=true
        opaqueFeaturesPreserved=true

        \(workbookReports.joined(separator: "\n\n"))
        """
        let attachment = XCTAttachment(
            data: Data(report.utf8),
            uniformTypeIdentifier: "public.plain-text"
        )
        attachment.name = "internet-xlsx-full-workbook-report.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertTargetFeature(
        _ fixtureName: String,
        source: Data,
        workbook: ExcelWorkbook
    ) throws {
        switch fixtureName {
        case "Sparklines":
            XCTAssertGreaterThan(try archiveTagCount("sparkline", in: source), 0)
            XCTAssertGreaterThan(try archiveTagCount("extLst", in: source), 0)
        case "PivotTable_CachedDefinitionAndDataInSync":
            XCTAssertGreaterThan(
                workbook.sheets.flatMap(\.pivotTables).count,
                0
            )
            XCTAssertGreaterThan(try archivePathCount(prefix: "xl/pivot", in: source), 0)
        case "image_hyperlink":
            XCTAssertGreaterThan(
                workbook.sheets.flatMap(\.drawingObjects.images).count,
                0
            )
            XCTAssertGreaterThan(try archiveTagCount("hlinkClick", in: source), 0)
        case "data_validation_test":
            XCTAssertGreaterThan(
                workbook.sheets.flatMap(\.dataValidations).count,
                0
            )
        case "ProtecteSheet1234Pass":
            XCTAssertTrue(workbook.sheets.contains { $0.protection.isEnabled })
            XCTAssertGreaterThan(try archiveTagCount("sheetProtection", in: source), 0)
        default:
            XCTFail("Unregistered full-workbook fixture: \(fixtureName)")
        }
    }

    private func editedRoundTrip(
        fixtureName: String,
        source: Data,
        workbook: ExcelWorkbook
    ) throws -> ExcelWorkbook {
        let populatedSheet = workbook.sheets.first { !$0.cells.isEmpty }
        let sheet = try XCTUnwrap(populatedSheet ?? workbook.sheets.first)
        let existingTarget = sheet.cells.values
                .filter { $0.formula?.isEmpty != false }
                .sorted { $0.address < $1.address }
                .first
        let targetAddress = existingTarget?.address
            ?? ExcelCellAddress(row: 1, column: 1)
        let marker = "RivoPad full-workbook \(fixtureName)"
        let saved = try ExcelWorkbookDocument.applying(
            [
                ExcelWorksheetEdits(
                    partPath: sheet.partPath,
                    cells: [
                        targetAddress: ExcelCellEdit(
                            input: .text(marker),
                            styleIndex: existingTarget?.styleIndex
                        ),
                    ]
                ),
            ],
            to: source,
            workbook: workbook
        )
        XCTAssertEqual(try archivePaths(in: saved), try archivePaths(in: source))

        let sourcePaths = try archivePaths(in: source)
        for path in sourcePaths where isOpaqueFeaturePart(path) {
            XCTAssertEqual(
                try archiveData(path, in: saved),
                try archiveData(path, in: source),
                "Opaque part changed: \(fixtureName) \(path)"
            )
        }
        for tag in [
            "sparkline", "extLst", "dataValidation", "sheetProtection",
            "hyperlink", "hlinkClick", "drawing", "pivotTableDefinition",
        ] {
            XCTAssertEqual(
                try archiveTagCount(tag, in: saved),
                try archiveTagCount(tag, in: source),
                "Feature tag count changed: \(fixtureName) \(tag)"
            )
        }

        let reloaded = try ExcelWorkbookDocument.load(from: saved)
        XCTAssertEqual(
            reloaded.sheets.first(where: { $0.partPath == sheet.partPath })?
                .cell(at: targetAddress)?.displayValue,
            marker
        )
        for (beforeSheet, afterSheet) in zip(workbook.sheets, reloaded.sheets) {
            let excludedAddress = beforeSheet.partPath == sheet.partPath
                ? targetAddress
                : nil
            let before = cellDigest(
                beforeSheet,
                excluding: excludedAddress
            )
            let after = cellDigest(
                afterSheet,
                excluding: excludedAddress
            )
            XCTAssertEqual(before, after, "Cell content changed: \(fixtureName) \(beforeSheet.name)")
        }
        return reloaded
    }

    private func cellDigest(
        _ sheet: ExcelWorksheet,
        excluding address: ExcelCellAddress?
    ) -> [String] {
        sheet.cells.values
            .filter { $0.address != address }
            .sorted { $0.address < $1.address }
            .map {
                [
                    $0.address.reference,
                    $0.rawValue,
                    $0.displayValue,
                    $0.formula ?? "",
                    String($0.styleIndex ?? -1),
                    $0.cellType ?? "",
                ].joined(separator: "\u{1f}")
            }
    }

    private func workbookFeatureDigest(_ workbook: ExcelWorkbook) -> [String] {
        workbook.sheets.map(sheetFeatureDigest)
    }

    private func sheetFeatureDigest(_ sheet: ExcelWorksheet) -> String {
        var fields = [sheet.name, sheet.partPath]
        fields.append(String(sheet.mergedRanges.count))
        fields.append(String(sheet.tables.count))
        fields.append(String(sheet.dataValidations.count))
        fields.append(String(sheet.conditionalFormatting.count))
        fields.append(String(sheet.annotations.hyperlinks.count))
        fields.append(String(sheet.annotations.notes.count))
        fields.append(String(sheet.drawingObjects.images.count))
        fields.append(String(sheet.drawingObjects.charts.count))
        fields.append(String(sheet.drawingObjects.shapes.count))
        fields.append(String(sheet.pivotTables.count))
        fields.append(String(sheet.protection.isEnabled))
        fields.append(sheet.printSettings.orientation?.rawValue ?? "")
        fields.append(String(sheet.printSettings.paperSize ?? -1))
        fields.append(sheet.printSettings.printAreaFormula ?? "")
        return fields.joined(separator: "|")
    }

    private func fixtureData(named name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(
            forResource: name,
            withExtension: "xlsx",
            subdirectory: "InternetWorkbookFullValidationFixtures"
        ) ?? bundle.url(forResource: name, withExtension: "xlsx")
        return try Data(contentsOf: XCTUnwrap(url, "Missing \(name).xlsx"))
    }

    private func archiveTagCount(_ tag: String, in data: Data) throws -> Int {
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?"#
            + NSRegularExpression.escapedPattern(for: tag)
            + #"\b"#
        let regex = try NSRegularExpression(pattern: pattern)
        var total = 0
        for path in try archivePaths(in: data) where path.hasSuffix(".xml") {
            guard let source = String(
                data: try archiveData(path, in: data),
                encoding: .utf8
            ) else { continue }
            total += regex.numberOfMatches(
                in: source,
                range: NSRange(source.startIndex..., in: source)
            )
        }
        return total
    }

    private func archivePathCount(prefix: String, in data: Data) throws -> Int {
        try archivePaths(in: data).filter { $0.hasPrefix(prefix) }.count
    }

    private func isOpaqueFeaturePart(_ path: String) -> Bool {
        path.hasPrefix("xl/drawings/")
            || path.hasPrefix("xl/charts/")
            || path.hasPrefix("xl/media/")
            || path.hasPrefix("xl/tables/")
            || path.hasPrefix("xl/comments")
            || path.hasPrefix("xl/pivot")
            || path.hasPrefix("xl/externalLinks/")
    }

    private func archiveData(_ path: String, in data: Data) throws -> Data {
        let archive = try Archive(data: data, accessMode: .read)
        let entry = try XCTUnwrap(archive[path])
        var extracted = Data()
        _ = try archive.extract(entry) { extracted.append($0) }
        return extracted
    }

    private func archivePaths(in data: Data) throws -> [String] {
        let archive = try Archive(data: data, accessMode: .read)
        return archive.map(\.path).sorted()
    }
}
