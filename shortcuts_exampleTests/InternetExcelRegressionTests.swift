import XCTest
import ZIPFoundation
@testable import shortcuts_example

final class InternetExcelRegressionTests: XCTestCase {
    private let fixtureNames = [
        "01_Financial_Sample",
        "02_FormulaEvalTestData_Copy",
        "03_ConditionalFormattingSamples",
        "04_WithThreeCharts",
        "05_WithTextBox",
    ]

    func testMicrosoftFinancialSampleLoadsAndRoundTripsItsTable() throws {
        let source = try fixtureData(named: fixtureNames[0])
        let workbook = try ExcelWorkbookDocument.load(from: source)

        XCTAssertEqual(workbook.sheets.count, 1)
        let sheet = try XCTUnwrap(workbook.sheets.first)
        XCTAssertEqual(sheet.name, "Sheet1")
        XCTAssertEqual(sheet.maximumRow, 701)
        XCTAssertEqual(sheet.maximumColumn, 16)
        XCTAssertEqual(sheet.cells.count, 11_216)
        let table = try XCTUnwrap(sheet.tables.first)
        XCTAssertEqual(table.range.reference, "A1:P701")
        XCTAssertEqual(table.columnNames.count, 16)
        XCTAssertEqual(
            sheet.cell(at: address("A1"))?.displayValue,
            "Segment"
        )

        let reloaded = try roundTrip(
            source: source,
            workbook: workbook,
            sheetName: "Sheet1",
            cell: "A2",
            value: "RivoPad round-trip"
        )
        XCTAssertEqual(reloaded.sheets.first?.tables.count, 1)
        XCTAssertEqual(
            reloaded.sheets.first?.tables.first?.range.reference,
            "A1:P701"
        )
    }

    func testApacheFormulaCorpusLoadsRoundTripsAndMeasuresCoverage() throws {
        let source = try fixtureData(named: fixtureNames[1])
        let workbook = try ExcelWorkbookDocument.load(from: source)

        XCTAssertEqual(
            workbook.sheets.map(\.name),
            ["EverythingTests", "FinanceLibTests", "StatsLibTests", "misc"]
        )
        XCTAssertFalse(workbook.supportsDynamicArrays)
        XCTAssertEqual(formulaCount(in: workbook), 1_295)
        XCTAssertEqual(
            workbook.sheets.flatMap(\.annotations.notes).count,
            1
        )
        XCTAssertEqual(
            workbook.sheets.flatMap(\.annotations.hyperlinks).count,
            1
        )

        var supported = 0
        var unsupported = 0
        var cachedMatches = 0
        var cachedMismatches = [(String, ExcelCell, ExcelFormulaCalculatedValue)]()
        for sheet in workbook.sheets {
            let result = ExcelFormulaCalculator.recalculate(
                cells: sheet.cells,
                styles: workbook.styles,
                uses1904DateSystem: workbook.uses1904DateSystem,
                mergedRanges: sheet.mergedRanges,
                tableRanges: sheet.tables.map(\.range),
                workbook: workbook,
                currentSheetName: sheet.name,
                timeZone: TimeZone(secondsFromGMT: 0)!
            )
            let formulaCells = sheet.cells.values.filter {
                $0.formula?.isEmpty == false
            }.sorted { $0.address < $1.address }
            for cell in formulaCells {
                guard let calculated = result.values[cell.address] else {
                    continue
                }
                supported += 1
                if equivalent(cell.rawValue, calculated.rawValue) {
                    cachedMatches += 1
                } else if cachedMismatches.count < 100 {
                    cachedMismatches.append((sheet.name, cell, calculated))
                }
            }
            unsupported += result.unsupportedFormulaCount
        }
        XCTAssertEqual(supported + unsupported, 1_295)
        XCTAssertGreaterThan(supported, 0)
        XCTAssertGreaterThanOrEqual(cachedMatches, 1_148)

        let mismatchCount = supported - cachedMatches
        let examples = cachedMismatches.map { sheetName, cell, calculated in
            let formula = cell.formula ?? ""
            return "\(sheetName)!\(cell.address.reference) "
                + "=\(formula) cached=\(cell.rawValue) "
                + "calculated=\(calculated.rawValue)"
        }.joined(separator: "\n")
        let report = """
        Formula corpus: 1295
        Supported: \(supported)
        Unsupported: \(unsupported)
        Cached-value matches: \(cachedMatches)
        Cached-value mismatches: \(mismatchCount)
        Mismatch examples (up to 100):
        \(examples)
        """
        print("INTERNET_XLSX_FORMULA_REPORT\n\(report)")
        XCTContext.runActivity(named: "External formula coverage") { activity in
            activity.add(XCTAttachment(string: report))
        }

        let reloaded = try roundTrip(
            source: source,
            workbook: workbook,
            sheetName: "misc",
            cell: "A16",
            value: "abc-rivopad"
        )
        XCTAssertEqual(formulaCount(in: reloaded), 1_295)
        XCTAssertEqual(
            reloaded.sheets.flatMap(\.annotations.notes).count,
            1
        )
        XCTAssertEqual(
            reloaded.sheets.flatMap(\.annotations.hyperlinks).count,
            1
        )
    }

    func testApacheConditionalFormattingGalleryLoadsAndRoundTrips() throws {
        let source = try fixtureData(named: fixtureNames[2])
        let workbook = try ExcelWorkbookDocument.load(from: source)

        XCTAssertEqual(workbook.sheets.count, 18)
        XCTAssertEqual(
            workbook.sheets.flatMap(\.conditionalFormatting).count,
            38
        )
        XCTAssertEqual(
            workbook.sheets.flatMap(\.dataValidations).count,
            3
        )
        XCTAssertEqual(workbook.sheets.flatMap(\.tables).count, 9)
        XCTAssertEqual(
            workbook.sheets.flatMap(\.drawingObjects.images).count,
            20
        )
        XCTAssertEqual(
            workbook.sheets.flatMap(\.drawingObjects.shapes).count,
            51
        )

        let reloaded = try roundTrip(
            source: source,
            workbook: workbook,
            sheetName: "Home",
            cell: "D23",
            value: "RivoPad preservation check"
        )
        XCTAssertEqual(reloaded.sheets.count, 18)
        XCTAssertEqual(
            reloaded.sheets.flatMap(\.conditionalFormatting).count,
            38
        )
        XCTAssertEqual(
            reloaded.sheets.flatMap(\.dataValidations).count,
            3
        )
        XCTAssertEqual(
            reloaded.sheets.flatMap(\.drawingObjects.images).count,
            20
        )
        XCTAssertEqual(
            reloaded.sheets.flatMap(\.drawingObjects.shapes).count,
            51
        )
    }

    func testApacheThreeChartWorkbookLoadsAndRoundTripsAllCharts() throws {
        let source = try fixtureData(named: fixtureNames[3])
        let workbook = try ExcelWorkbookDocument.load(from: source)

        XCTAssertEqual(workbook.sheets.count, 3)
        XCTAssertEqual(workbook.definedNames.count, 1)
        XCTAssertEqual(workbook.definedNames.first?.name, "ChartRange2")
        let charts = workbook.sheets.flatMap(\.drawingObjects.charts)
        XCTAssertEqual(charts.count, 3)
        XCTAssertEqual(
            Set(charts.map(\.kind)),
            Set([.line, .pie, .area])
        )

        let reloaded = try roundTrip(
            source: source,
            workbook: workbook,
            sheetName: "Sheet1",
            cell: "A1",
            value: "7"
        )
        XCTAssertEqual(reloaded.definedNames.count, 1)
        XCTAssertEqual(
            reloaded.sheets.flatMap(\.drawingObjects.charts).count,
            3
        )
    }

    func testApacheTextBoxWorkbookLoadsAndRoundTripsItsTextBox() throws {
        let source = try fixtureData(named: fixtureNames[4])
        let workbook = try ExcelWorkbookDocument.load(from: source)

        XCTAssertEqual(workbook.sheets.count, 3)
        let shapes = workbook.sheets.flatMap(\.drawingObjects.shapes)
        let textBox = try XCTUnwrap(shapes.first)
        XCTAssertEqual(shapes.count, 1)
        XCTAssertEqual(textBox.kind, .textBox)
        XCTAssertEqual(textBox.name, "TextBox 1")
        XCTAssertEqual(textBox.text, "Line 1\nLine 2\nLine 3")

        let reloaded = try roundTrip(
            source: source,
            workbook: workbook,
            sheetName: "Sheet2",
            cell: "A1",
            value: "RivoPad round-trip"
        )
        let reloadedTextBox = try XCTUnwrap(
            reloaded.sheets.flatMap(\.drawingObjects.shapes).first
        )
        XCTAssertEqual(reloadedTextBox.kind, .textBox)
        XCTAssertEqual(reloadedTextBox.text, "Line 1\nLine 2\nLine 3")
    }

    @MainActor
    func testApacheTextBoxCanBeEditedThroughTheAppModel() async throws {
        let source = try fixtureData(named: fixtureNames[4])
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xlsx")
        try source.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()
        let shape = try XCTUnwrap(viewModel.selectedSheetShapes.first)
        XCTAssertTrue(
            viewModel.updateSheetShape(
                id: shape.id,
                name: shape.name,
                text: "RivoPad edited text",
                kind: .textBox
            )
        )

        let exported = try await viewModel.exportData()
        let reloaded = try ExcelWorkbookDocument.load(from: exported)
        let reloadedShape = try XCTUnwrap(
            reloaded.sheets.flatMap(\.drawingObjects.shapes).first
        )
        XCTAssertEqual(reloadedShape.kind, .textBox)
        XCTAssertEqual(reloadedShape.text, "RivoPad edited text")
        let sourcePaths = Set(try archivePaths(in: source))
        let exportedPaths = Set(try archivePaths(in: exported))
        XCTAssertEqual(exportedPaths, sourcePaths)
    }

    private func fixtureData(named name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(
            forResource: name,
            withExtension: "xlsx",
            subdirectory: "InternetWorkbookFixtures"
        ) ?? bundle.url(forResource: name, withExtension: "xlsx")
        return try Data(contentsOf: XCTUnwrap(url, "Missing \(name).xlsx"))
    }

    private func roundTrip(
        source: Data,
        workbook: ExcelWorkbook,
        sheetName: String,
        cell: String,
        value: String
    ) throws -> ExcelWorkbook {
        let sheet = try XCTUnwrap(
            workbook.sheets.first(where: { $0.name == sheetName })
        )
        let saved = try ExcelWorkbookDocument.applying(
            [
                ExcelWorksheetEdits(
                    partPath: sheet.partPath,
                    cells: [
                        address(cell): ExcelCellEdit(
                            input: .text(value),
                            styleIndex: sheet.cell(at: address(cell))?.styleIndex
                        ),
                    ]
                ),
            ],
            to: source,
            workbook: workbook
        )

        XCTAssertEqual(try archivePaths(in: saved), try archivePaths(in: source))
        for path in try archivePaths(in: source) where isOpaqueFeaturePart(path) {
            XCTAssertEqual(
                try archiveData(path, in: saved),
                try archiveData(path, in: source),
                "Changed opaque feature part: \(path)"
            )
        }
        for tag in [
            "f", "conditionalFormatting", "cfRule", "dataValidation",
            "hyperlink", "drawing", "tablePart",
        ] {
            XCTAssertEqual(
                try worksheetTagCount(tag, in: saved),
                try worksheetTagCount(tag, in: source),
                "Changed worksheet feature count: \(tag)"
            )
        }
        return try ExcelWorkbookDocument.load(from: saved)
    }

    private func formulaCount(in workbook: ExcelWorkbook) -> Int {
        workbook.sheets.reduce(0) { total, sheet in
            total + sheet.cells.values.filter {
                $0.formula?.isEmpty == false
            }.count
        }
    }

    private func equivalent(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        if left == right {
            return true
        }
        if let leftNumber = Double(left),
           let rightNumber = Double(right) {
            let scale = max(1, abs(leftNumber), abs(rightNumber))
            return abs(leftNumber - rightNumber) <= 1e-9 * scale
        }
        return false
    }

    private func worksheetTagCount(_ tag: String, in data: Data) throws -> Int {
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?"#
            + NSRegularExpression.escapedPattern(for: tag)
            + #"\b"#
        let regex = try NSRegularExpression(pattern: pattern)
        var total = 0
        for path in try archivePaths(in: data)
        where path.hasPrefix("xl/worksheets/") && path.hasSuffix(".xml") {
            let xml = try archiveData(path, in: data)
            guard let source = String(data: xml, encoding: .utf8) else {
                continue
            }
            total += regex.numberOfMatches(
                in: source,
                range: NSRange(source.startIndex..., in: source)
            )
        }
        return total
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

    private func address(_ reference: String) -> ExcelCellAddress {
        guard let address = ExcelCellAddress(reference) else {
            preconditionFailure("Invalid test address: \(reference)")
        }
        return address
    }
}
