import RivoDocumentEngine
import Foundation
import XCTest
@testable import shortcuts_example

final class ExcelSheetManagementTests: XCTestCase {
    private func a(_ ref: String) -> ExcelCellAddress { ExcelCellAddress(ref)! }
    private func r(_ ref: String) -> ExcelCellRange { ExcelCellRange(ref)! }
    private func apply(_ edit: ExcelSheetEdit, _ data: Data, active: String? = nil) throws -> ExcelSheetManagement.Result {
        let book = try ExcelWorkbookDocument.load(from: data)
        return try ExcelSheetManagement.applying(edit, to: data, workbook: book, selectedSheetPath: active ?? book.sheets[0].partPath)
    }
    private func fixture(objects: Bool = false) throws -> Data {
        var data = try ExcelWorkbookDocument.blankWorkbookData(sheetName: "Data")
        data = try apply(.add(name: "Summary"), data).data
        var book = try ExcelWorkbookDocument.load(from: data)
        let path = book.sheets[0].partPath
        book.sheets[0].tables = [ExcelTable(id: "1", name: "Sales", range: r("A1:B2"), partPath: "xl/tables/table1.xml", columnNames: ["Product", "Amount"])]
        let values = ["A1": "Product", "B1": "Amount", "A2": "Pen", "B2": "3", "C2": "=Data!B2", "D2": "=SUM(Sales[Amount])"]
        var drawingEdits: [ExcelWorksheetDrawingEdits] = []
        var annotationEdits: [ExcelWorksheetAnnotationEdits] = []
        if objects {
            let anchor = ExcelDrawingAnchor(start: a("F2"), end: a("H6"))
            var drawings = ExcelWorksheetDrawingObjects.empty
            drawings.drawingPartPath = "xl/drawings/drawing1.xml"; drawings.drawingRelationshipID = "rIdDrawing1"
            drawings.images = [ExcelSheetImage(id: "image", name: "Photo", anchor: anchor, relationshipID: "rIdImage1", mediaPartPath: "xl/media/image1.png", contentType: "image/png", data: Data([1, 2, 3]), originalAnchorXML: nil)]
            drawings.charts = [ExcelSheetChart(id: "chart", name: "Chart", title: "Sales", kind: .column, sourceRange: r("A1:B2"), sheetName: "Data", anchor: anchor, relationshipID: "rIdChart1", chartPartPath: "xl/charts/chart1.xml", originalAnchorXML: nil, originalChartXML: nil)]
            drawingEdits = [.init(partPath: path, original: .empty, current: drawings)]
            var annotations = ExcelWorksheetAnnotations.empty
            annotations.notes = [ExcelCellNote(address: a("A2"), author: "Tester", text: "Keep this note")]
            annotations.hyperlinks = [ExcelCellHyperlink(range: r("B2"), target: "'Data'!A2", isExternal: false)]
            annotationEdits = [.init(partPath: path, annotations: annotations, writesHyperlinks: true, writesNotes: true)]
        }
        return try ExcelWorkbookDocument.applying([
            .init(partPath: path, cells: Dictionary(uniqueKeysWithValues: values.map { (a($0.key), ExcelCellEdit(input: ExcelCellInput(userText: $0.value), styleIndex: nil)) })),
            .init(partPath: book.sheets[1].partPath, cells: [a("A1"): ExcelCellEdit(input: .formula("Data!B2"), styleIndex: nil), a("B1"): ExcelCellEdit(input: .formula("SUM(Sales[Amount])"), styleIndex: nil)])
        ], to: data, workbook: book, annotationEdits: annotationEdits, drawingEdits: drawingEdits)
    }
    private func withNames(_ data: Data) throws -> Data {
        let reader = try ExcelArchiveReader(data: data)
        let root = try ExcelEditingXML.parse(reader.data(at: "xl/workbook.xml"))
        let names = root.make("definedNames")
        for (name, index, formula) in [("PrintData", "0", "Data!$A$1:$B$2"), ("PrintSummary", "1", "Summary!$A$1"), ("Global", "", "Data!B2")] {
            let node = names.make("definedName", index.isEmpty ? ["name": name] : ["name": name, "localSheetId": index])
            node.text = formula; names.children.append(node)
        }
        root.children.insert(names, at: root.children.firstIndex { $0.localName == "calcPr" }!)
        return try reader.repack(replacing: ["xl/workbook.xml": ExcelEditingXML.data(root)])
    }

    func testAddCreatesIndependentBlankSheetAndSelectsIt() throws {
        let result = try apply(.add(name: "추가"), ExcelWorkbookDocument.blankWorkbookData())
        let book = try ExcelWorkbookDocument.load(from: result.data)
        XCTAssertEqual(book.sheets.map(\.name), ["시트1", "추가"])
        XCTAssertEqual(result.selectedSheetPath, book.sheets[1].partPath)
        XCTAssertTrue(book.sheets[1].cells.isEmpty)
        XCTAssertNotEqual(book.sheets[0].partPath, book.sheets[1].partPath)
    }

    func testRenameUpdatesOtherSheetsNamesChartsAndLinks() throws {
        let data = try withNames(fixture(objects: true))
        let before = try ExcelWorkbookDocument.load(from: data)
        let result = try apply(.rename(path: before.sheets[0].partPath, name: "O'Brien 매출"), data)
        let book = try ExcelWorkbookDocument.load(from: result.data)
        XCTAssertEqual(book.sheets[1].cells[a("A1")]?.formula, "'O''Brien 매출'!B2")
        XCTAssertEqual(book.definedNames.first { $0.name == "Global" }?.formula, "'O''Brien 매출'!B2")
        XCTAssertEqual(book.sheets[0].drawingObjects.charts.first?.sheetName, "O'Brien 매출")
        XCTAssertTrue(book.sheets[0].annotations.hyperlinks.first?.target.contains("O''Brien 매출") == true)
    }

    func testReorderRemapsLocalNamesAndKeepsActiveSheetIdentity() throws {
        let data = try withNames(fixture()), book = try ExcelWorkbookDocument.load(from: data)
        let result = try apply(.reorder(paths: book.sheets.reversed().map(\.partPath)), data)
        let reordered = try ExcelWorkbookDocument.load(from: result.data)
        XCTAssertEqual(reordered.sheets.map(\.name), ["Summary", "Data"])
        XCTAssertEqual(result.selectedSheetPath, book.sheets[0].partPath)
        XCTAssertEqual(reordered.definedNames.first { $0.name == "PrintData" }?.localSheetIndex, 1)
        XCTAssertEqual(reordered.definedNames.first { $0.name == "PrintSummary" }?.localSheetIndex, 0)
        XCTAssertEqual(reordered.sheets[0].cells[a("A1")]?.formula, "Data!B2")
    }

    func testDuplicateOwnsTablesImagesChartsNotesAndLocalNames() throws {
        let data = try withNames(fixture(objects: true)), original = try ExcelWorkbookDocument.load(from: data)
        let result = try apply(.duplicate(path: original.sheets[0].partPath, name: "Copy"), data)
        let book = try ExcelWorkbookDocument.load(from: result.data)
        XCTAssertEqual(book.sheets.map(\.name), ["Data", "Copy", "Summary"])
        let first = book.sheets[0], copy = book.sheets[1]
        XCTAssertEqual(copy.cells[a("A2")]?.rawValue, "Pen")
        XCTAssertEqual(copy.cells[a("C2")]?.formula, "'Copy'!B2")
        let table = try XCTUnwrap(copy.tables.first)
        XCTAssertNotEqual(table.name, "Sales"); XCTAssertNotEqual(table.partPath, first.tables.first?.partPath)
        XCTAssertEqual(copy.cells[a("D2")]?.formula, "SUM(\(table.name)[Amount])")
        XCTAssertEqual(first.cells[a("D2")]?.formula, "SUM(Sales[Amount])")
        XCTAssertNotEqual(copy.drawingObjects.images.first?.mediaPartPath, first.drawingObjects.images.first?.mediaPartPath)
        XCTAssertEqual(copy.drawingObjects.images.first?.data, first.drawingObjects.images.first?.data)
        XCTAssertNotEqual(copy.drawingObjects.charts.first?.chartPartPath, first.drawingObjects.charts.first?.chartPartPath)
        XCTAssertEqual(copy.drawingObjects.charts.first?.sheetName, "Copy")
        XCTAssertNotEqual(copy.annotations.commentsPartPath, first.annotations.commentsPartPath)
        XCTAssertEqual(copy.annotations.notes.first?.text, "Keep this note")
        XCTAssertEqual(book.definedNames.filter { $0.name == "PrintData" }.map(\.localSheetIndex), [0, 1])
        XCTAssertEqual(book.definedNames.first { $0.name == "PrintSummary" }?.localSheetIndex, 2)
    }

    func testDeleteRemovesOwnedPartsAndInvalidatesSheetAndTableReferences() throws {
        let data = try withNames(fixture(objects: true)), original = try ExcelWorkbookDocument.load(from: data)
        let target = original.sheets[0]
        let result = try apply(.delete(path: target.partPath), data)
        let book = try ExcelWorkbookDocument.load(from: result.data)
        XCTAssertEqual(book.sheets.map(\.name), ["Summary"])
        XCTAssertEqual(book.sheets[0].cells[a("A1")]?.formula, "#REF!B2")
        XCTAssertEqual(book.sheets[0].cells[a("B1")]?.formula, "SUM(#REF!)")
        XCTAssertFalse(book.definedNames.contains { $0.name == "PrintData" })
        XCTAssertEqual(book.definedNames.first { $0.name == "PrintSummary" }?.localSheetIndex, 0)
        let reader = try ExcelArchiveReader(data: result.data)
        for path in [target.partPath, target.tables.first?.partPath, target.drawingObjects.drawingPartPath, target.drawingObjects.images.first?.mediaPartPath, target.drawingObjects.charts.first?.chartPartPath, target.annotations.commentsPartPath].compactMap({ $0 }) {
            XCTAssertFalse(reader.contains(path), "Deleted part remains: \(path)")
        }
    }

    func testDeletingOriginalDoesNotRemoveCopyAssets() throws {
        let data = try fixture(objects: true), original = try ExcelWorkbookDocument.load(from: data)
        let copied = try apply(.duplicate(path: original.sheets[0].partPath, name: "Copy"), data)
        let deleted = try apply(.delete(path: original.sheets[0].partPath), copied.data)
        let book = try ExcelWorkbookDocument.load(from: deleted.data)
        XCTAssertEqual(book.sheets[0].name, "Copy")
        XCTAssertEqual(book.sheets[0].drawingObjects.images.first?.data, Data([1, 2, 3]))
        XCTAssertEqual(book.sheets[0].drawingObjects.charts.first?.sheetName, "Copy")
        XCTAssertEqual(book.sheets[0].annotations.notes.first?.text, "Keep this note")
        XCTAssertEqual(book.sheets[0].cells[a("C2")]?.formula, "'Copy'!B2")
    }

    func testNameValidationAndReservedNames() throws {
        for invalid in ["", "Bad/Name", "Bad:Name", "'Name", "Name'", String(repeating: "a", count: 32), "History", "DATA"] {
            XCTAssertThrowsError(try ExcelSheetNames.validated(invalid, existing: ["Data"]))
        }
        XCTAssertEqual(try ExcelSheetNames.validated(" O'Brien 매출 ", existing: []), "O'Brien 매출")
        XCTAssertEqual(ExcelSheetNames.suggested(base: "Data", existing: ["Data", "Data (1)"]), "Data (2)")
    }

    func testFormulaTokensPreserveLiteralsExternalRefsAndColumnNames() {
        let formula = #"SUM(Data!A:A,'Data'!LocalName,[1]Data!B2,'[book.xlsx]Data'!C3,"Data!A1")"#
        XCTAssertEqual(ExcelSheetFormulaEditing.renamed(formula, old: "Data", new: "New"), #"SUM('New'!A:A,'New'!LocalName,[1]Data!B2,'[book.xlsx]Data'!C3,"Data!A1")"#)
        XCTAssertTrue(ExcelSheetFormulaEditing.hasThreeDimensionalReference("SUM(Data:Summary!A1)"))
        XCTAssertTrue(ExcelSheetFormulaEditing.hasThreeDimensionalReference("SUM('Data:Summary'!A1)"))
        XCTAssertFalse(ExcelSheetFormulaEditing.hasThreeDimensionalReference(#""Data:Summary!A1""#))
        XCTAssertEqual(ExcelSheetFormulaEditing.renamedTable(#"SUM(Sales[[#All],[Sales]])+Sales+"Sales""#, old: "Sales", new: "Copied"), #"SUM(Copied[[#All],[Sales]])+Copied+"Sales""#)
        XCTAssertEqual(ExcelSheetFormulaEditing.removedTable("SUM(Sales[[#All],[Amount]])+Sales", name: "Sales"), "SUM(#REF!)+#REF!")
    }

    func testLastSheetAndProtectedStructureAreRejected() throws {
        let data = try ExcelWorkbookDocument.blankWorkbookData(), book = try ExcelWorkbookDocument.load(from: data)
        XCTAssertThrowsError(try apply(.delete(path: book.sheets[0].partPath), data))
        var protected = book; protected.protection.lockStructure = true
        XCTAssertThrowsError(try ExcelSheetManagement.applying(.add(name: "New"), to: data, workbook: protected, selectedSheetPath: book.sheets[0].partPath))
    }

    func testLastVisibleSheetCannotBeDeletedAndHiddenStateSurvivesReorder() throws {
        let data = try fixture(), book = try ExcelWorkbookDocument.load(from: data)
        let reader = try ExcelArchiveReader(data: data)
        let root = try ExcelEditingXML.parse(reader.data(at: "xl/workbook.xml"))
        root.child("sheets")?.elements("sheet")[1].attributes["state"] = "hidden"
        let hidden = try reader.repack(replacing: ["xl/workbook.xml": ExcelEditingXML.data(root)])
        XCTAssertThrowsError(try apply(.delete(path: book.sheets[0].partPath), hidden))
        let reordered = try apply(.reorder(paths: book.sheets.reversed().map(\.partPath)), hidden, active: book.sheets[1].partPath)
        let saved = try ExcelArchiveReader(data: reordered.data)
        let xml = try ExcelEditingXML.parse(saved.data(at: "xl/workbook.xml"))
        XCTAssertEqual(xml.child("sheets")?.elements("sheet")[0].attributes["state"], "hidden")
        XCTAssertEqual(xml.child("bookViews")?.child("workbookView")?.attributes["activeTab"], "1")
    }

    func testDeletingOneSheetPreservesAnImageSharedByAnotherSheet() throws {
        let initial = try fixture(objects: true), original = try ExcelWorkbookDocument.load(from: initial)
        let copied = try apply(.duplicate(path: original.sheets[0].partPath, name: "Copy"), initial)
        let book = try ExcelWorkbookDocument.load(from: copied.data)
        let media = try XCTUnwrap(book.sheets[0].drawingObjects.images.first?.mediaPartPath)
        let drawing = try XCTUnwrap(book.sheets[1].drawingObjects.drawingPartPath)
        let url = URL(fileURLWithPath: "/" + drawing)
        let relPath = String(url.deletingLastPathComponent().appendingPathComponent("_rels").appendingPathComponent(url.lastPathComponent + ".rels").path.dropFirst())
        let reader = try ExcelArchiveReader(data: copied.data)
        let rels = try ExcelEditingXML.parse(reader.data(at: relPath))
        rels.elements("Relationship").first { $0.attributes["Type"]?.hasSuffix("/image") == true }?.attributes["Target"] = "/" + media
        let shared = try reader.repack(replacing: [relPath: ExcelEditingXML.data(rels)])
        let deleted = try apply(.delete(path: original.sheets[0].partPath), shared)
        XCTAssertTrue(try ExcelArchiveReader(data: deleted.data).contains(media))
        XCTAssertEqual(try ExcelWorkbookDocument.load(from: deleted.data).sheets[0].drawingObjects.images.first?.data, Data([1, 2, 3]))
    }

    func testThreeDimensionalReferencesBlockExistingSheetChanges() throws {
        let data = try fixture(), book = try ExcelWorkbookDocument.load(from: data)
        let modified = try ExcelWorkbookDocument.applying([
            .init(partPath: book.sheets[1].partPath, cells: [a("C1"): ExcelCellEdit(input: .formula("SUM(Data:Summary!B2)"), styleIndex: nil)])
        ], to: data, workbook: book)
        XCTAssertThrowsError(try apply(.rename(path: book.sheets[0].partPath, name: "New"), modified))
        XCTAssertThrowsError(try apply(.reorder(paths: book.sheets.reversed().map(\.partPath)), modified))
        XCTAssertEqual(try ExcelWorkbookDocument.load(from: apply(.add(name: "Extra"), modified).data).sheets.count, 3)
    }
}
