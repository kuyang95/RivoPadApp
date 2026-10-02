import Foundation
import RivoDocumentEngine

// The same real-file probe runs on macOS and Android. It deliberately tests
// document computation/serialization, without pretending to test native UI.
func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try condition() == false {
        throw NSError(
            domain: "RivoEngineProbe", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message])
    }
}
func address(_ value: String) -> ExcelCellAddress { ExcelCellAddress(value)! }
func payloads(_ data: Data) throws -> [String: Data] {
    let reader = try ExcelArchiveReader(data: data)
    var result: [String: Data] = [:]
    for path in reader.paths { result[path] = try reader.data(at: path) }
    return result
}
func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name))
}

var results: [[String: Any]] = []
do {
    try require(CommandLine.arguments.count == 2, "Usage: RivoEngineProbe <fixture-directory>")
    let blank = try ExcelWorkbookDocument.blankWorkbookData()
    let wb = try ExcelWorkbookDocument.load(from: blank)
    let saved = try ExcelWorkbookDocument.applying(
        [
            .init(
                partPath: wb.sheets[0].partPath,
                cells: [
                    address("A1"): .init(input: .text("한글 😀"), styleIndex: nil),
                    address("B1"): .init(input: .number("12"), styleIndex: nil),
                    address("B2"): .init(input: .number("30"), styleIndex: nil),
                    address("C1"): .init(input: .formula("SUM(B1:B2)"), styleIndex: nil),
                ])
        ], to: blank, workbook: wb)
    let reloaded = try ExcelWorkbookDocument.load(from: saved)
    let sheet = reloaded.sheets[0]
    let calc = ExcelFormulaCalculator.recalculate(
        cells: sheet.cells, styles: reloaded.styles,
        uses1904DateSystem: reloaded.uses1904DateSystem,
        now: Date(timeIntervalSince1970: 0), timeZone: TimeZone(secondsFromGMT: 0)!)
    try require(sheet.cell(at: address("A1"))?.displayValue == "한글 😀", "XLSX Unicode save")
    try require(calc.values[address("C1")]?.rawValue == "42", "XLSX formula calculation")
    results.append(["check": "xlsx-edit-calculation", "result": calc.values[address("C1")]!.rawValue])

    let financial = try fixture("01_Financial_Sample.xlsx")
    let financialWB = try ExcelWorkbookDocument.load(from: financial)
    let financialSheet = financialWB.sheets[0]
    let financialSaved = try ExcelWorkbookDocument.applying(
        [
            .init(
                partPath: financialSheet.partPath,
                cells: [address("A2"): .init(input: .text("공용 엔진"), styleIndex: nil)])
        ],
        to: financial, workbook: financialWB)
    let before = try payloads(financial)
    let after = try payloads(financialSaved)
    let allowed: Set<String> = [financialSheet.partPath, "xl/workbook.xml", "xl/calcChain.xml"]
    var preserved = 0
    for (path, bytes) in before where !allowed.contains(path) {
        try require(after[path] == bytes, "XLSX part changed: \(path)")
        preserved += 1
    }
    try require(
        try ExcelWorkbookDocument.load(from: financialSaved).sheets[0].cell(at: address("A2"))?.displayValue == "공용 엔진",
        "real XLSX edit")
    results.append(["check": "xlsx-real-file-preservation", "preservedParts": preserved])

    let formulasWB = try ExcelWorkbookDocument.load(from: fixture("02_FormulaEvalTestData_Copy.xlsx"))
    var formulaResults = 0
    var formulaValues: [String: String] = [:]
    var formulaTypes: [String: String] = [:]
    var formulaDisplayValues: [String: String] = [:]
    for s in formulasWB.sheets {
        let computed = ExcelFormulaCalculator.recalculate(
            cells: s.cells, styles: formulasWB.styles,
            uses1904DateSystem: formulasWB.uses1904DateSystem, workbook: formulasWB,
            currentSheetName: s.name, now: Date(timeIntervalSince1970: 0), timeZone: TimeZone(secondsFromGMT: 0)!)
        formulaResults += computed.values.count
        for (cell, value) in computed.values {
            let key = s.name + "!" + cell.reference
            formulaValues[key] = value.rawValue
            formulaTypes[key] = value.cellType ?? "n"
            formulaDisplayValues[key] = value.displayValue
        }
    }
    try require(formulaResults > 10, "formula fixture not evaluated")
    results.append(["check": "xlsx-formula-fixture", "calculatedValues": formulaResults,
                    "values": formulaValues, "types": formulaTypes,
                    "displayValues": formulaDisplayValues])

    let chartData = try fixture("04_WithThreeCharts.xlsx")
    let chartWorkbook = try ExcelWorkbookDocument.load(from: chartData)
    let chartSaved = try ExcelWorkbookDocument.applying([], to: chartData, workbook: chartWorkbook)
    let chartParts = try payloads(chartData)
    try require(chartParts == payloads(chartSaved), "XLSX chart payloads")
    let chartCount = chartParts.keys.filter { $0.hasPrefix("xl/charts/chart") && $0.hasSuffix(".xml") }.count
    try require(chartCount == 3, "chart fixture must contain three charts")
    results.append(["check": "xlsx-chart-preservation", "preservedCharts": chartCount])

    let hwpx = try fixture("mss_voucher.hwpx")
    let hwpxPackage = try HWPXDocumentPackage.load(from: hwpx)
    let hwpxSaved = try hwpxPackage.serializedData(applying: hwpxPackage.blocks)
    let hwpxBefore = try payloads(hwpx)
    let hwpxAfter = try payloads(hwpxSaved)
    try require(hwpxBefore == hwpxAfter, "HWPX unchanged payloads")
    results.append([
        "check": "hwpx-real-file-preservation", "blocks": hwpxPackage.blocks.count,
        "preservedParts": hwpxBefore.count,
    ])

    let hwp = try fixture("hangul_design_application.hwp")
    let hwpDocument = try HWP5StructuredDocumentParser.parse(from: hwp)
    let hwpSaved = try HWP5DocumentRewriter.rewrite(
        sourceData: hwp,
        originalBlocks: hwpDocument.blocks, editedBlocks: hwpDocument.blocks)
    let oldOLE = try OLECompoundFile(data: hwp)
    let newOLE = try OLECompoundFile(data: hwpSaved)
    try require(oldOLE.streamNames == newOLE.streamNames, "HWP stream names")
    for path in oldOLE.streamNames {
        let old = try oldOLE.stream(named: path)
        let new = try newOLE.stream(named: path)
        try require(old == new, "HWP unchanged stream: \(path)")
    }
    results.append([
        "check": "hwp-real-file-preservation", "blocks": hwpDocument.blocks.count,
        "preservedStreams": oldOLE.streamNames.count,
    ])

    let text = "한\t😀글"
    try require(HWPInlineParagraphGeometry.rawLength(text) == 12, "raw HWP tab length")
    try require(HWPInlineParagraphGeometry.textOffset(in: text, raw: 11) == 4, "UTF-16 surrogate mapping")
    results.append(["check": "hwp-utf16-tab-mapping", "rawLength": 12, "utf16Offset": 4])
    let output = try JSONSerialization.data(
        withJSONObject: ["checks": results, "passed": results.count], options: [.sortedKeys])
    print(String(decoding: output, as: UTF8.self))
} catch {
    FileHandle.standardError.write(Data("RivoEngineProbe failed: \(error)\n".utf8))
    exit(1)
}
