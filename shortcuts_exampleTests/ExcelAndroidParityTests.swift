import RivoDocumentEngine
import SwiftUI
import UIKit
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

    /// The row right below the table already has a value in a form column, so
    /// the engine appends after the sheet's last row: the form must offer the
    /// dropdown of that row, not of the occupied one.
    func testNewRowDropdownFollowsTheEngineWhenTheRowBelowTheTableIsOccupied() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AndroidParityTable-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try ExcelWorkbookDocument.blankWorkbookData()
        var book = try ExcelWorkbookDocument.load(from: source)
        let path = book.sheets[0].partPath
        book.sheets[0].tables = [ExcelTable(
            id: "1", name: "People", range: ExcelCellRange(start: .init(row: 1, column: 1), end: .init(row: 2, column: 2)),
            partPath: "xl/tables/table1.xml", columnNames: ["이름", "구분"])]
        let values: [String: String] = ["A1": "이름", "B1": "구분", "A2": "기존 사람", "B2": "보호자", "A3": "표 밖 메모"]
        let data = try ExcelWorkbookDocument.applying([
            .init(partPath: path, cells: Dictionary(uniqueKeysWithValues: values.map {
                (ExcelCellAddress($0.key)!, ExcelCellEdit(input: .text($0.value), styleIndex: nil))
            }))
        ], to: source, workbook: book)
        try data.write(to: url)
        let model = ExcelWorkbookViewModel(fileURL: url, autosaveDelay: .seconds(60))
        await model.load()
        let loaded = try XCTUnwrap(model.selectedSheet)
        XCTAssertEqual(loaded.tables.first?.range.end.row, 2)
        XCTAssertEqual(loaded.maximumRow, 3)

        model.selectCell(ExcelCellAddress(row: 3, column: 2))
        XCTAssertTrue(model.applyDropdown(values: ["틀린 줄", "다른 값"], allowsBlank: true, toCurrentColumn: false))
        model.selectCell(ExcelCellAddress(row: 4, column: 2))
        XCTAssertTrue(model.applyDropdown(values: ["보호자", "학생"], allowsBlank: false, toCurrentColumn: false))

        model.selectCell(ExcelCellAddress(row: 2, column: 1))
        let sheet = try XCTUnwrap(model.selectedSheet)
        let fields = model.rowFieldsForAppending()
        let columns = Set(fields.map(\.column))
        XCTAssertEqual(columns, [1, 2])
        let row = ExcelWorkbookViewModel.appendedRow(near: .init(row: 2, column: 1), columns: columns, in: sheet)
        XCTAssertEqual(row, 4)
        // Same answer as the engine's own rule.
        let workbook = try XCTUnwrap(model.workbook)
        let appended = try XCTUnwrap(ExcelRowEditing.appending(
            values: fields.map { ($0.column, $0.column == 1 ? "새 사람" : "") }, near: .init(row: 2, column: 1),
            sheetIndex: 0, workbook: workbook, registry: ExcelEditRegistry()))
        XCTAssertEqual(appended.row, row)

        let role = try XCTUnwrap(fields.first { $0.column == 2 })
        XCTAssertEqual(role.dropdownValues, ["보호자", "학생"])
        XCTAssertFalse(role.dropdownAllowsBlank)

        var filled = fields
        filled[filled.firstIndex { $0.column == 1 }!].value = "새 사람"
        filled[filled.firstIndex { $0.column == 2 }!].value = "학생"
        model.appendRow(fields: filled)
        XCTAssertEqual(model.selectedSheet?.cell(at: .init(row: 4, column: 2))?.displayValue, "학생")
        XCTAssertEqual(model.selectedSheet?.cell(at: .init(row: 3, column: 1))?.displayValue, "표 밖 메모")
    }

    func testAppendedRowIsBelowTheTableWhenThatRowIsFree() throws {
        var book = try ExcelWorkbookDocument.load(from: ExcelWorkbookDocument.blankWorkbookData())
        book.sheets[0].tables = [ExcelTable(
            id: "1", name: "T", range: ExcelCellRange(start: .init(row: 1, column: 1), end: .init(row: 2, column: 2)),
            partPath: "xl/tables/table1.xml")]
        book.sheets[0].maximumRow = 9
        // Row 3 is free in the form's columns, so the new row joins the table.
        XCTAssertEqual(ExcelWorkbookViewModel.appendedRow(near: .init(row: 2, column: 1), columns: [1, 2], in: book.sheets[0]), 3)
        // Away from the table it goes below the sheet's last row.
        XCTAssertEqual(ExcelWorkbookViewModel.appendedRow(near: .init(row: 20, column: 5), columns: [5], in: book.sheets[0]), 10)
    }

    func testDrawingManagerNoticeCountsObjectsItDoesNotList() throws {
        XCTAssertNil(ExcelDrawingManagerNotice.otherObjects(0))
        let notice = try XCTUnwrap(ExcelDrawingManagerNotice.otherObjects(3))
        XCTAssertTrue(notice.contains("3"))
    }

    /// A picked image or chart reads Android's object actions in this order:
    /// move ↑↓←→, 크게/작게, 설정, then 선택 해제 (only while picked).
    func testCanvasObjectActionsReadInOrderAndRun() async throws {
        let workbook = try ExcelWorkbookDocument.load(from: ExcelWorkbookDocument.blankWorkbookData())
        let png = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).pngData { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
        let anchor = ExcelDrawingAnchor(start: .init(row: 2, column: 2), end: .init(row: 6, column: 4))
        let image = ExcelSheetImage(id: "image", name: "사진 개체", anchor: anchor, relationshipID: "rIdImage1",
            mediaPartPath: "xl/media/image1.png", contentType: "image/png", data: png, originalAnchorXML: nil)
        let item = ExcelDrawingCanvasItem(id: "image", name: "사진 개체", anchor: anchor, order: 0, image: image, chart: nil)
        var nudges: [(CGPoint, Bool)] = []
        var settings = 0, deselections = 0

        func object(selected: Bool, editable: Bool) -> some View {
            ExcelDrawingCanvasObject(item: item, workbook: workbook, size: CGSize(width: 200, height: 120),
                renderScale: 1, zoomScale: 1, selected: selected, editable: editable,
                onSelect: {}, onSettings: { settings += 1 },
                onNudge: { nudges.append(($0, $1)) }, onDeselect: { deselections += 1 })
        }

        let window = host(object(selected: true, editable: true))
        defer { window.isHidden = true }
        var node = try await element(in: window) { $0.accessibilityLabel == "사진 개체" }
        let expected = ["위로 이동", "아래로 이동", "왼쪽으로 이동", "오른쪽으로 이동",
                        "개체 크게", "개체 작게", "개체 설정", "선택 해제"]
        XCTAssertEqual(names(node).count, expected.count, "\(names(node))")
        for (name, key) in zip(names(node), expected) { XCTAssertTrue(matches(name, key), "\(name) ≠ \(key)") }

        try perform("위로 이동", on: node)
        try perform("오른쪽으로 이동", on: node)
        try perform("개체 크게", on: node)
        try perform("개체 작게", on: node)
        try perform("개체 설정", on: node)
        try perform("선택 해제", on: node)
        XCTAssertEqual(nudges.map(\.0), [CGPoint(x: 0, y: -20), CGPoint(x: 20, y: 0), CGPoint(x: 20, y: 20), CGPoint(x: -20, y: -20)])
        XCTAssertEqual(nudges.map(\.1), [false, false, true, true])
        XCTAssertEqual(settings, 1)
        XCTAssertEqual(deselections, 1)

        // Not picked and outside the editable part: only 개체 설정.
        (window.rootViewController as? UIHostingController<AnyView>)?.rootView = AnyView(object(selected: false, editable: false))
        node = try await element(in: window) {
            $0.accessibilityLabel == "사진 개체" && !$0.accessibilityTraits.contains(.selected)
        }
        XCTAssertEqual(names(node).count, 1, "\(names(node))")
        XCTAssertTrue(names(node).first.map { matches($0, "개체 설정") } == true)
    }

    private func host<Content: View>(_ view: Content) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        window.rootViewController = UIHostingController(rootView: AnyView(view))
        window.makeKeyAndVisible()
        window.rootViewController?.view.layoutIfNeeded()
        return window
    }

    private func matches(_ text: String, _ key: String) -> Bool {
        text == key || text == AppLocalization.string(key) || text == NSLocalizedString(key, comment: "")
    }

    private func names(_ element: NSObject) -> [String] {
        (element.accessibilityCustomActions ?? []).map(\.name)
    }

    private func perform(_ name: String, on element: NSObject) throws {
        let action = try XCTUnwrap(element.accessibilityCustomActions?.first { matches($0.name, name) }, name)
        if let handler = action.actionHandler {
            XCTAssertTrue(handler(action))
        } else if let target = action.target as? NSObject {
            target.perform(action.selector, with: action)
        } else {
            XCTFail("\(name) has no handler")
        }
    }

    private func element(in window: UIWindow, timeout: TimeInterval = 5,
                         _ predicate: (NSObject) -> Bool) async throws -> NSObject {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            var found: [NSObject] = []
            var visited = Set<ObjectIdentifier>()
            collect(window, depth: 0, into: &found, visited: &visited)
            if let match = found.first(where: predicate) { return match }
            try await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline
        XCTFail("Accessibility element not found")
        throw CancellationError()
    }

    private func collect(_ object: NSObject, depth: Int, into found: inout [NSObject],
                         visited: inout Set<ObjectIdentifier>) {
        guard depth < 120, visited.insert(ObjectIdentifier(object)).inserted else { return }
        if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return }
        if object.isAccessibilityElement { found.append(object) }
        if object.accessibilityElementsHidden { return }
        var children: [NSObject] = []
        if let list = object.accessibilityElements {
            children = list.compactMap { $0 as? NSObject }
        } else {
            let count = object.accessibilityElementCount()
            if count != NSNotFound, count > 0, count < 50_000 {
                for index in 0..<count {
                    if let child = object.accessibilityElement(at: index) as? NSObject { children.append(child) }
                }
            }
        }
        if let view = object as? UIView { children.append(contentsOf: view.subviews) }
        for child in children { collect(child, depth: depth + 1, into: &found, visited: &visited) }
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
