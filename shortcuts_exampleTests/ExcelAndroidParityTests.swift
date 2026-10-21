import RivoDocumentEngine
import XCTest
@testable import shortcuts_example

/// Spreadsheet features ported from Android VisionCraft: 표 배율 steps, sheet
/// moves without dragging, new-row dropdowns and the drawing manager notice.
@MainActor
final class ExcelAndroidParityTests: XCTestCase {
    func testGridZoomStepsMatchAndroidAndStopAtTheEnds() {
        XCTAssertEqual(ExcelGridZoom.steps, [0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3])
        XCTAssertEqual(ExcelGridZoom.range, 0.5 ... 3)
        XCTAssertEqual(ExcelGridZoom.zoomedIn(from: 1), 1.25)
        XCTAssertEqual(ExcelGridZoom.zoomedOut(from: 1), 0.75)
        // A pinch can leave the zoom between steps: the next step is the nearest one past it.
        XCTAssertEqual(ExcelGridZoom.zoomedIn(from: 1.1), 1.25)
        XCTAssertEqual(ExcelGridZoom.zoomedOut(from: 1.1), 1)
        XCTAssertEqual(ExcelGridZoom.zoomedIn(from: 3), 3)
        XCTAssertEqual(ExcelGridZoom.zoomedOut(from: 0.5), 0.5)
        XCTAssertFalse(ExcelGridZoom.canZoomIn(3))
        XCTAssertTrue(ExcelGridZoom.canZoomIn(2.5))
        XCTAssertFalse(ExcelGridZoom.canZoomOut(0.5))
        XCTAssertTrue(ExcelGridZoom.canZoomOut(0.75))
        XCTAssertEqual(ExcelGridZoom.percent(1.25), 125)
        XCTAssertTrue(ExcelGridZoom.status(1.25).contains("125%"))
    }

    func testGridZoomStepBecomesTheAnnouncedStatus() throws {
        let model = ExcelWorkbookViewModel(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("zoom.xlsx"))
        model.reportGridZoom(ExcelGridZoom.status(2))
        XCTAssertEqual(model.status, ExcelGridZoom.status(2))
    }

    func testSheetMoveActionsSwapNeighboursAndStopAtTheEnds() {
        let paths = ["a", "b", "c"]
        XCTAssertEqual(ExcelSheetManagerView.paths(paths, moving: 1, by: -1), ["b", "a", "c"])
        XCTAssertEqual(ExcelSheetManagerView.paths(paths, moving: 1, by: 1), ["a", "c", "b"])
        XCTAssertNil(ExcelSheetManagerView.paths(paths, moving: 0, by: -1))
        XCTAssertNil(ExcelSheetManagerView.paths(paths, moving: 2, by: 1))
        XCTAssertNil(ExcelSheetManagerView.paths(paths, moving: 5, by: -1))
    }

    func testSheetMoveActionReordersTheWorkbook() async throws {
        let (url, model) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let added = await model.performSheetEdit(.add(name: "둘째"))
        XCTAssertTrue(added)
        let before = try XCTUnwrap(model.workbook?.sheets.map(\.partPath))
        let moved = try XCTUnwrap(ExcelSheetManagerView.paths(before, moving: 1, by: -1))
        let reordered = await model.performSheetEdit(.reorder(paths: moved))
        XCTAssertTrue(reordered)
        XCTAssertEqual(model.workbook?.sheets.map(\.name).first, "둘째")
    }

    func testNewRowFormOffersTheDropdownOfTheRowItFills() async throws {
        let (url, model) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        model.selectCell(ExcelCellAddress(row: 3, column: 2))
        XCTAssertTrue(model.applyDropdown(values: ["보호자", "학생"], allowsBlank: false, toCurrentColumn: false))

        model.selectCell(ExcelCellAddress(row: 2, column: 1))
        let fields = model.rowFieldsForAppending()
        let role = try XCTUnwrap(fields.first { $0.column == 2 })
        XCTAssertEqual(role.dropdownValues, ["보호자", "학생"])
        XCTAssertFalse(role.dropdownAllowsBlank)
        XCTAssertEqual(fields.first { $0.column == 1 }?.dropdownValues, [])

        var filled = fields
        filled[filled.firstIndex { $0.column == 1 }!].value = "새 사람"
        filled[filled.firstIndex { $0.column == 2 }!].value = "학생"
        model.appendRow(fields: filled)
        XCTAssertEqual(model.selectedSheet?.cell(at: .init(row: 3, column: 2))?.displayValue, "학생")
        XCTAssertNil(model.validationWarning)
    }

    func testDrawingManagerNoticeCountsObjectsItDoesNotList() throws {
        XCTAssertNil(ExcelDrawingManagerNotice.otherObjects(0))
        let notice = try XCTUnwrap(ExcelDrawingManagerNotice.otherObjects(3))
        XCTAssertTrue(notice.contains("3"))
    }

    private func fixture() async throws -> (URL, ExcelWorkbookViewModel) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AndroidParity-\(UUID().uuidString).xlsx")
        let source = try ExcelWorkbookDocument.blankWorkbookData()
        let workbook = try ExcelWorkbookDocument.load(from: source)
        let sheet = try XCTUnwrap(workbook.sheets.first)
        let values: [ExcelCellAddress: ExcelCellInput] = [
            .init(row: 1, column: 1): .text("이름"),
            .init(row: 1, column: 2): .text("구분"),
            .init(row: 2, column: 1): .text("기존 사람"),
            .init(row: 2, column: 2): .text("보호자"),
        ]
        let data = try ExcelWorkbookDocument.applying(
            [.init(partPath: sheet.partPath, cells: values.mapValues {
                ExcelCellEdit(input: $0, styleIndex: nil)
            })], to: source, workbook: workbook
        )
        try data.write(to: url)
        let model = ExcelWorkbookViewModel(fileURL: url, autosaveDelay: .seconds(60))
        await model.load()
        return (url, model)
    }
}
