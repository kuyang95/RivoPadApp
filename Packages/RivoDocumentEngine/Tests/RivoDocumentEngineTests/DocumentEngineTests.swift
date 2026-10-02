import Foundation
import XCTest
import RivoDocumentEngine
import RivoZIPFoundation

/// These run without the iOS app, Firebase, UIKit or CoreText. Real documents
/// exercise the newly independent parser/writer and archive/module boundary.
final class DocumentEngineTests: XCTestCase {
    func testBlankWorkbookEditFormulaSaveAndReload() throws {
        let data = try ExcelWorkbookDocument.blankWorkbookData()
        let workbook = try ExcelWorkbookDocument.load(from: data)
        let sheet = try XCTUnwrap(workbook.sheets.first)
        let edits: [ExcelCellAddress: ExcelCellEdit] = [
            address("A1"): .init(input: .text("한글 😀"), styleIndex: nil),
            address("B1"): .init(input: .number("12"), styleIndex: nil),
            address("B2"): .init(input: .number("30"), styleIndex: nil),
            address("C1"): .init(input: .formula("SUM(B1:B2)"), styleIndex: nil)
        ]
        let saved = try ExcelWorkbookDocument.applying(
            [.init(partPath: sheet.partPath, cells: edits)], to: data, workbook: workbook)
        let loaded = try ExcelWorkbookDocument.load(from: saved)
        let result = try XCTUnwrap(loaded.sheets.first)
        XCTAssertEqual(result.cell(at: address("A1"))?.displayValue, "한글 😀")
        XCTAssertEqual(result.cell(at: address("C1"))?.formula, "SUM(B1:B2)")
        // The low-level writer requests external recalculation when no cache
        // was supplied; the shared calculator owns the numeric result.
        let calculated = ExcelFormulaCalculator.recalculate(cells: result.cells, styles: loaded.styles,
            uses1904DateSystem: loaded.uses1904DateSystem)
        XCTAssertEqual(calculated.values[address("C1")]?.displayValue, "42")
        let cached = try ExcelWorkbookDocument.applying(
            [.init(partPath: result.partPath, cells: [address("C1"): .init(
                input: .formula("SUM(B1:B2)"), styleIndex: nil, cachedValue: "42")])],
            to: saved, workbook: loaded)
        XCTAssertEqual(try ExcelWorkbookDocument.load(from: cached).sheets[0].cell(at: address("C1"))?.displayValue, "42")
    }

    func testRealWorkbookEditPreservesEveryUnchangedArchivePart() throws {
        let original = try fixture("01_Financial_Sample.xlsx")
        let workbook = try ExcelWorkbookDocument.load(from: original)
        let sheet = try XCTUnwrap(workbook.sheets.first)
        let saved = try ExcelWorkbookDocument.applying(
            [.init(partPath: sheet.partPath, cells: [address("A2"): .init(input: .text("모듈 경계 확인"), styleIndex: nil)])],
            to: original, workbook: workbook)
        let before = try archivePayloads(original), after = try archivePayloads(saved)
        XCTAssertEqual(Set(before.keys), Set(after.keys))
        // The existing writer also invalidates workbook calculation settings.
        let permittedChanges: Set<String> = [sheet.partPath, "xl/calcChain.xml", "xl/workbook.xml"]
        for (path, bytes) in before where !permittedChanges.contains(path) {
            XCTAssertEqual(after[path], bytes, "Unexpected changed part: \(path)")
        }
        XCTAssertTrue(String(decoding: try XCTUnwrap(after["xl/workbook.xml"]), as: UTF8.self)
            .contains("fullCalcOnLoad=\"1\""))
        XCTAssertEqual(try ExcelWorkbookDocument.load(from: saved).sheets[0].cell(at: address("A2"))?.displayValue,
            "모듈 경계 확인")
    }

    func testRealChartWorkbookNoEditReturnsOriginalBytes() throws {
        let original = try fixture("04_WithThreeCharts.xlsx")
        let workbook = try ExcelWorkbookDocument.load(from: original)
        XCTAssertFalse(workbook.sheets.isEmpty)
        XCTAssertEqual(try ExcelWorkbookDocument.applying([], to: original, workbook: workbook), original)
    }

    func testFormulaFixtureLoadsAndCalculatesOutsideApp() throws {
        let workbook = try ExcelWorkbookDocument.load(from: fixture("02_FormulaEvalTestData_Copy.xlsx"))
        var formulas = 0
        for sheet in workbook.sheets {
            let result = ExcelFormulaCalculator.recalculate(cells: sheet.cells, styles: workbook.styles,
                uses1904DateSystem: workbook.uses1904DateSystem, workbook: workbook, currentSheetName: sheet.name,
                now: Date(timeIntervalSince1970: 0), timeZone: TimeZone(secondsFromGMT: 0)!)
            formulas += result.values.count
        }
        XCTAssertGreaterThan(formulas, 10)
    }

    func testHWPXNoEditPreservesAllArchivePayloads() throws {
        let original = try fixture("mss_voucher.hwpx")
        let package = try HWPXDocumentPackage.load(from: original)
        XCTAssertFalse(package.blocks.isEmpty)
        let saved = try package.serializedData(applying: package.blocks)
        XCTAssertEqual(try archivePayloads(original), try archivePayloads(saved))
    }

    func testBinaryHWPNoEditPreservesAllOLEStreams() throws {
        let original = try fixture("hangul_design_application.hwp")
        let parsed = try HWP5StructuredDocumentParser.parse(from: original)
        XCTAssertFalse(parsed.blocks.isEmpty)
        let saved = try HWP5DocumentRewriter.rewrite(sourceData: original,
            originalBlocks: parsed.blocks, editedBlocks: parsed.blocks)
        let before = try OLECompoundFile(data: original), after = try OLECompoundFile(data: saved)
        XCTAssertEqual(before.streamNames, after.streamNames)
        for path in before.streamNames {
            XCTAssertEqual(try before.stream(named: path), try after.stream(named: path), path)
        }
    }

    func testRawTabAndSurrogateOffsetsAreSharedDocumentRules() {
        let text = "한\t😀글"
        XCTAssertEqual(HWPInlineParagraphGeometry.rawLength(text), 12)
        XCTAssertEqual(HWPInlineParagraphGeometry.textOffset(in: text, raw: 9), 2)
        XCTAssertEqual(HWPInlineParagraphGeometry.textOffset(in: text, raw: 11), 4)
        XCTAssertEqual(HWPInlineTextInput.normalized("한\r\n글\u{2028}끝"), "한\n글\n끝")
        XCTAssertFalse(HWPInlineTextInput.accepts("\u{0000}", replacing: .init(location: 0, length: 0), in: ""))
    }

    private func address(_ value: String) -> ExcelCellAddress { ExcelCellAddress(value)! }
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")))
    }
    private func archivePayloads(_ data: Data) throws -> [String: Data] {
        let archive = try Archive(data: data, accessMode: .read)
        var parts: [String: Data] = [:]
        for entry in archive {
            var bytes = Data()
            _ = try archive.extract(entry, consumer: { bytes.append($0) })
            parts[entry.path] = bytes
        }
        return parts
    }
}
