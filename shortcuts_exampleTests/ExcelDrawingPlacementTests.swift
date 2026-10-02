import RivoDocumentEngine
import Foundation
import CoreGraphics
import XCTest
@testable import shortcuts_example

final class ExcelDrawingPlacementTests: XCTestCase {
    private let drawingPath = "xl/drawings/drawingTest.xml"
    private let chartPath = "xl/charts/chartTest.xml"
    private let imagePath = "xl/media/imageTest.png"
    private func fixture() throws -> Data {
        let blank = try ExcelWorkbookDocument.blankWorkbookData(), book = try ExcelWorkbookDocument.load(from: blank)
        let path = book.sheets[0].partPath
        var objects = ExcelWorksheetDrawingObjects.empty
        objects.drawingPartPath = drawingPath; objects.drawingRelationshipID = "rIdDrawingTest"
        let anchor = ExcelDrawingAnchor(start: .init(row: 2, column: 2), end: .init(row: 7, column: 6), fromOffset: .init(x: 5000, y: 9000), toOffset: .init(x: 1234, y: 5678))
        objects.images = [.init(id: drawingPath + "#rIdImage", name: "Image one", alternativeText: "Description", anchor: anchor, relationshipID: "rIdImage", mediaPartPath: imagePath, contentType: "image/png", data: Data([1,2,3,4]), originalAnchorXML: nil)]
        objects.charts = [.init(id: drawingPath + "#rIdChart", name: "Sales", title: "Sales", kind: .column, sourceRange: ExcelCellRange("A1:C3"), sheetName: book.sheets[0].name, anchor: .init(start: .init(row: 8, column: 2), end: .init(row: 18, column: 9)), relationshipID: "rIdChart", chartPartPath: chartPath, originalAnchorXML: nil, originalChartXML: nil)]
        objects.chartCount = 1
        let edits: [ExcelCellAddress: ExcelCellEdit] = [
            ExcelCellAddress("A1")!: .init(input: .text("Country"), styleIndex: nil),
            ExcelCellAddress("B1")!: .init(input: .text("Sales"), styleIndex: nil),
            ExcelCellAddress("C1")!: .init(input: .text("Profit"), styleIndex: nil),
            ExcelCellAddress("A2")!: .init(input: .text("Germany"), styleIndex: nil),
            ExcelCellAddress("A3")!: .init(input: .text("France"), styleIndex: nil),
            ExcelCellAddress("B2")!: .init(input: .number("12"), styleIndex: nil),
            ExcelCellAddress("B3")!: .init(input: .number("18"), styleIndex: nil),
            ExcelCellAddress("C2")!: .init(input: .number("3"), styleIndex: nil),
            ExcelCellAddress("C3")!: .init(input: .number("4"), styleIndex: nil)]
        return try ExcelWorkbookDocument.applying([.init(partPath: path, cells: edits)], to: blank, workbook: book, drawingEdits: [.init(partPath: path, original: .empty, current: objects)])
    }
    private func change(_ data: Data, _ action: (inout ExcelWorksheetDrawingObjects) -> Void) throws -> Data {
        let book = try ExcelWorkbookDocument.load(from: data), sheet = book.sheets[0]
        var objects = sheet.drawingObjects; action(&objects)
        return try ExcelWorkbookDocument.applying([], to: data, workbook: book, drawingEdits: [.init(partPath: sheet.partPath, original: sheet.drawingObjects, current: objects)])
    }
    private func drawing(_ data: Data) throws -> ExcelEditingXML.Node {
        try ExcelEditingXML.parse(ExcelArchiveReader(data: data).data(at: drawingPath))
    }
    func testSubcellOffsetsAndFrontToBackOrderSurviveExport() throws {
        let data = try fixture(), objects = try ExcelWorkbookDocument.load(from: data).sheets[0].drawingObjects
        XCTAssertEqual(objects.images[0].anchor.fromOffset, .init(x: 5000, y: 9000))
        XCTAssertEqual(objects.images[0].anchor.toOffset, .init(x: 1234, y: 5678))
        XCTAssertLessThan(objects.images[0].displayOrder, objects.charts[0].displayOrder)
        let moved = ExcelDrawingAnchor(start: .init(row: 4, column: 3), end: .init(row: 4, column: 3), fromOffset: .init(x: 1000, y: 1000), toOffset: .init(x: 100000, y: 100000))
        let result = try change(data) { $0.images[0].anchor = moved }
        XCTAssertEqual(try ExcelWorkbookDocument.load(from: result).sheets[0].drawingObjects.images[0].anchor, moved, "A small image can begin and end inside one cell")
    }
    func testMovingImagePreservesCropEffectsSiblingAndMediaBytes() throws {
        let initial = try fixture(), root = try drawing(initial)
        let image = try XCTUnwrap(root.children.first), fill = try XCTUnwrap(image.descendants("blipFill").first)
        fill.children.append(.init("a:srcRect", ["l":"1200", "t":"2500"]))
        let props = try XCTUnwrap(image.descendants("spPr").first)
        props.children.append(.init("a:effectLst", children: [.init("a:glow", ["rad":"90000"])]))
        let modified = try ExcelArchiveReader(data: initial).repack(replacing: [drawingPath: ExcelEditingXML.data(root)])
        let oldPayload = try XCTUnwrap(drawing(modified).descendants("pic").first).xml
        let oldChartAnchor = try XCTUnwrap(drawing(modified).children.last).xml
        let result = try change(modified) {
            let a = $0.images[0].anchor
            $0.images[0].anchor.start = .init(row: a.start.row + 3, column: a.start.column)
            $0.images[0].anchor.end = .init(row: a.end.row + 3, column: a.end.column)
        }
        XCTAssertEqual(try XCTUnwrap(drawing(result).descendants("pic").first).xml, oldPayload)
        XCTAssertEqual(try XCTUnwrap(drawing(result).children.last).xml, oldChartAnchor)
        XCTAssertEqual(try ExcelArchiveReader(data: result).data(at: imagePath), Data([1,2,3,4]))
    }
    func testMovingUnsupportedChartDoesNotRebuildItsContents() throws {
        let initial = try fixture()
        let chartXML = Data(#"<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart><c:plotArea><c:surface3DChart><c:customKeep/></c:surface3DChart></c:plotArea></c:chart></c:chartSpace>"#.utf8)
        let source = try ExcelArchiveReader(data: initial).repack(replacing: [chartPath: chartXML])
        let result = try change(source) {
            let a = $0.charts[0].anchor.end
            $0.charts[0].anchor.end = .init(row: a.row, column: a.column + 2)
        }
        XCTAssertEqual(try ExcelArchiveReader(data: result).data(at: chartPath), chartXML)
        XCTAssertEqual(try ExcelWorkbookDocument.load(from: result).sheets[0].drawingObjects.charts[0].anchor.end.column, 11)
    }
    func testOneCellAndAbsolutePlacementConvertWithoutLosingPictureSettings() throws {
        for absolute in [false, true] {
            let initial = try fixture(), root = try drawing(initial), node = try XCTUnwrap(root.children.first)
            node.name = absolute ? "xdr:absoluteAnchor" : "xdr:oneCellAnchor"
            node.attributes.removeValue(forKey: "editAs"); node.remove("to")
            if absolute { node.remove("from"); node.children.insert(node.make("pos", ["x":"981075", "y":"385445"]), at: 0) }
            node.children.insert(node.make("ext", ["cx":"1962150", "cy":"770890"]), at: 1)
            let source = try ExcelArchiveReader(data: initial).repack(replacing: [drawingPath: ExcelEditingXML.data(root)])
            let objects = try ExcelWorkbookDocument.load(from: source).sheets[0].drawingObjects
            XCTAssertNotNil(objects.images[0].anchor.extent)
            XCTAssertEqual(objects.images[0].anchor.absolutePosition != nil, absolute)
            let payload = try XCTUnwrap(drawing(source).descendants("pic").first).xml
            let target = ExcelDrawingAnchor(start: .init(row: 2, column: 2), end: .init(row: 5, column: 5), fromOffset: .init(x: 333, y: 444))
            let result = try change(source) { $0.images[0].anchor = target }
            XCTAssertEqual(try ExcelWorkbookDocument.load(from: result).sheets[0].drawingObjects.images[0].anchor, target)
            XCTAssertEqual(try XCTUnwrap(drawing(result).descendants("pic").first).xml, payload)
            XCTAssertEqual(try drawing(result).children.first?.localName, "twoCellAnchor")
        }
    }
    func testReplacingSharedPictureUsesSeparateMediaAndKeepsOtherPicture() throws {
        let initial = try fixture()
        let shared = try change(initial) { objects in
            let one = objects.images[0]
            objects.images.append(.init(id: drawingPath + "#rIdOther", name: "Other", alternativeText: nil, anchor: one.anchor, relationshipID: "rIdOther", mediaPartPath: one.mediaPartPath, contentType: one.contentType, data: one.data, originalAnchorXML: nil))
        }
        let result = try change(shared) { $0.images[0].mediaPartPath = "xl/media/replacement.png"; $0.images[0].data = Data([8,9]); $0.images[0].name = "Renamed & described"; $0.images[0].alternativeText = "<hello>" }
        let images = try ExcelWorkbookDocument.load(from: result).sheets[0].drawingObjects.images
        XCTAssertEqual(images[0].data, Data([8,9])); XCTAssertEqual(images[1].data, Data([1,2,3,4]))
        XCTAssertEqual(images[0].name, "Renamed & described"); XCTAssertEqual(images[0].alternativeText, "<hello>")
    }
    private func grid(columns: [Int] = Array(1...12), rows: [Int] = Array(1...30)) -> ExcelDrawingGrid {
        .init(columns: columns.enumerated().map { .init(index: $0.element, origin: CGFloat($0.offset * 100 + 54), size: 100, emuSize: 1_000_000) },
              rows: rows.enumerated().map { .init(index: $0.element, origin: CGFloat($0.offset * 40 + 42), size: 40, emuSize: 400_000) }, columnWidths: [:], rowHeights: [:])
    }
    func testGeometryConvertsFractionalPositionsAndSmallSizes() throws {
        let grid = grid(), rect = CGRect(x: 175, y: 123, width: 27, height: 18)
        let anchor = try XCTUnwrap(grid.anchor(for: rect))
        XCTAssertEqual(anchor.start, .init(row: 3, column: 2))
        XCTAssertEqual(anchor.fromOffset, .init(x: 210000, y: 10000))
        XCTAssertEqual(try XCTUnwrap(grid.rect(for: anchor)), rect)
        XCTAssertTrue(grid.canManipulate(anchor))
    }
    func testPartialPageAndHiddenRowsCannotChangeObjectSizeByAccident() {
        let grid = grid(columns: [1,2,41,42], rows: [1,2,5,6])
        XCTAssertFalse(grid.canManipulate(.init(start: .init(row: 1, column: 1), end: .init(row: 6, column: 42))))
        XCTAssertTrue(grid.canManipulate(.init(start: .init(row: 5, column: 41), end: .init(row: 6, column: 42))))
    }
    func testMoveAndFourCornerResizeStayInsideCanvasAndCannotInvert() {
        let rect = CGRect(x: 100, y: 100, width: 300, height: 200), bounds = CGRect(x: 54, y: 42, width: 800, height: 600)
        XCTAssertEqual(ExcelDrawingDragMode.move.applying(CGPoint(x: -1000, y: -1000), to: rect, within: bounds).origin, bounds.origin)
        for mode in ExcelDrawingDragMode.allCases where mode != .move {
            for delta in [CGPoint(x: -10000, y: -10000), CGPoint(x: 10000, y: 10000)] {
                let resized = mode.applying(delta, to: rect, within: bounds)
                XCTAssertTrue(bounds.contains(resized)); XCTAssertGreaterThanOrEqual(resized.width, 32); XCTAssertGreaterThanOrEqual(resized.height, 32)
            }
            XCTAssertEqual(ExcelDrawingDragMode.hit(mode.corner(in: rect)!, rect: rect, radius: 22), mode)
        }
    }
    func testPreviewUsesCurrentSeriesValuesAndRejectsUnsupportedCharts() throws {
        let data = try fixture(), book = try ExcelWorkbookDocument.load(from: data), chart = book.sheets[0].drawingObjects.charts[0]
        let preview = ExcelDrawingChartData(chart: chart, workbook: book)
        XCTAssertTrue(preview.supported); XCTAssertEqual(preview.series.count, 2)
        XCTAssertEqual(preview.series[0].points.map(\.value), [12,18])
        XCTAssertEqual(preview.series[1].points.map(\.value), [3,4])
        XCTAssertEqual(preview.series[0].points.map(\.category), ["Germany","France"])
        var unsupported = chart
        unsupported.originalChartXML = #"<chartSpace><chart><plotArea><barChart/><lineChart/></plotArea></chart></chartSpace>"#
        XCTAssertFalse(ExcelDrawingChartData(chart: unsupported, workbook: book).supported)
        let updated = try ExcelWorkbookDocument.applying([.init(partPath: book.sheets[0].partPath, cells: [ExcelCellAddress("B2")!: .init(input: .number("888"), styleIndex: nil)])], to: data, workbook: book)
        let editedBook = try ExcelWorkbookDocument.load(from: updated)
        XCTAssertEqual(ExcelDrawingChartData(chart: chart, workbook: editedBook).series[0].points[0].value, 888)
    }
    func testDeleteAfterMoveRetainsTheOtherObjectAndItsContent() throws {
        let source = try fixture()
        let moved = try change(source) {
            let a = $0.images[0].anchor
            $0.images[0].anchor.start = .init(row: a.start.row + 1, column: a.start.column)
            $0.images[0].anchor.end = .init(row: a.end.row + 1, column: a.end.column)
        }
        let deleted = try change(moved) { $0.images.removeAll() }
        let book = try ExcelWorkbookDocument.load(from: deleted)
        XCTAssertTrue(book.sheets[0].drawingObjects.images.isEmpty)
        XCTAssertEqual(book.sheets[0].drawingObjects.charts.count, 1)
        XCTAssertEqual(try ExcelArchiveReader(data: deleted).data(at: chartPath), try ExcelArchiveReader(data: source).data(at: chartPath))
    }
}
