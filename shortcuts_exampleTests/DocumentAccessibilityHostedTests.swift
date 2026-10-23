import Combine
import PDFKit
import RivoDocumentEngine
import SwiftUI
import UIKit
import XCTest
import ZIPFoundation
@testable import shortcuts_example

/// The document screens hosted in a window, read through the UIKit accessibility tree as VoiceOver
/// reads them: labels, values, traits and custom actions, with the actions run through their handlers.
/// Everything works on temporary files and fresh UserDefaults suites; the app's own recent documents
/// and Documents folder are only read. The in-process accessibility flag is turned on for the suite, so it
/// runs the same with or without VoiceOver.
@MainActor
final class DocumentAccessibilityHostedTests: XCTestCase {
    private var previousLanguage: String?
    private var accessibilityWasEnabled = false
    private var windows: [UIWindow] = []
    private var cleanup: [URL] = []
    private var suites: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        previousLanguage = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        UserDefaults.standard.set(AppLanguage.korean.rawValue, forKey: AppLanguage.preferenceKey)
        accessibilityWasEnabled = InProcessAccessibility.isEnabled
        InProcessAccessibility.setEnabled(true)
    }

    override func tearDown() async throws {
        for window in windows {
            window.rootViewController = nil
            window.isHidden = true
        }
        windows = []
        for url in cleanup { try? FileManager.default.removeItem(at: url) }
        for suite in suites { UserDefaults().removePersistentDomain(forName: suite) }
        cleanup = []
        suites = []
        InProcessAccessibility.setEnabled(accessibilityWasEnabled)
        if let previousLanguage {
            UserDefaults.standard.set(previousLanguage, forKey: AppLanguage.preferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppLanguage.preferenceKey)
        }
        try await super.tearDown()
    }

    // MARK: 1. PDF 원본 보기 (LocalDocumentView `PDFOriginalPagesView`)

    func testPDFPagesReadPageAndTextAndZoomActionsStepTheCard() async throws {
        let document = try XCTUnwrap(PDFDocument(data: pdfData(pages: ["첫 쪽 본문입니다", "둘째 쪽 본문", "셋째 쪽 본문"])))
        let window = host(PDFOriginalPagesView(document: document), size: CGSize(width: 800, height: 1000))
        let pdfView = try await view(ZoomablePDFView.self, in: window)

        // Each page is one element: "n/m페이지. <text>".
        let pages = try XCTUnwrap(pdfView.accessibilityElements as? [NSObject])
        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(pages[0].accessibilityLabel, "1/3페이지. 첫 쪽 본문입니다")
        XCTAssertEqual(pages[2].accessibilityLabel, "3/3페이지. 셋째 쪽 본문")

        // At 100% only 확대; each 확대 steps the card 125 … 500 and then stops.
        XCTAssertEqual(names(pages[0]), ["확대"])
        _ = try await element(in: window) { $0.accessibilityLabel == "100%" }
        for percent in [125, 150, 200, 300, 400, 500] {
            try perform("확대", on: pages[0])
            _ = try await element(in: window) { $0.accessibilityLabel == "\(percent)%" }
        }
        XCTAssertEqual(PDFZoomSteps.percent(pdfView.zoom), 500)
        XCTAssertEqual(names(pages[1]), ["축소"], "확대 is gone at 500%")
        let zoomIn = try await element(in: window) { self.isButton($0, "확대") }
        XCTAssertTrue(zoomIn.accessibilityTraits.contains(.notEnabled), "the card's 확대 is dimmed at 500%")

        // 축소 walks back down to 100%, where only 확대 is left.
        for percent in [400, 300, 200, 150, 125, 100] {
            try perform("축소", on: pages[1])
            _ = try await element(in: window) { $0.accessibilityLabel == "\(percent)%" }
        }
        XCTAssertEqual(names(pages[1]), ["확대"])
        let zoomOut = try await element(in: window) { self.isButton($0, "축소") }
        XCTAssertTrue(zoomOut.accessibilityTraits.contains(.notEnabled), "the card's 축소 is dimmed at 100%")

        // The card's own 확대 button moves the same zoom.
        let cardZoomIn = try await element(in: window) { self.isButton($0, "확대") && !$0.accessibilityTraits.contains(.notEnabled) }
        XCTAssertTrue(cardZoomIn.accessibilityActivate())
        _ = try await element(in: window) { $0.accessibilityLabel == "125%" }
        try perform("확대", on: pages[0])
        try perform("확대", on: pages[0])
        _ = try await element(in: window) { $0.accessibilityLabel == "200%" }
        XCTAssertEqual(pdfView.zoom, 2, accuracy: 0.001)

        // A width change (rotation, split view) keeps 200% of the new fitted width.
        let fitBefore = pdfView.scaleFactorForSizeToFit
        window.frame.size.width = 560
        window.layoutIfNeeded()
        try await settle()
        let fitAfter = pdfView.scaleFactorForSizeToFit
        XCTAssertNotEqual(fitBefore, fitAfter, accuracy: 0.001, "the fitted width changed")
        XCTAssertEqual(pdfView.zoom, 2, accuracy: 0.001)
        XCTAssertEqual(pdfView.scaleFactor, fitAfter * 2, accuracy: 0.01)
        _ = try await element(in: window) { $0.accessibilityLabel == "200%" }
    }

    // MARK: 2. 문서 작업 편집 mode (DocumentLibraryView)

    func testLibraryEditButtonTogglesAndDeleteRemovesOnlyTheRecentEntry() async throws {
        let directory = try temporaryDirectory()
        let store = recentStore()
        for name in ["a.xlsx", "b.hwpx"] {
            let url = directory.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            _ = try await store.register(fileURL: url)
            try await Task.sleep(for: .milliseconds(20))
        }
        let model = DocumentLibraryViewModel(recentStore: store, appFolderURL: nil)
        let window = host(NavigationStack { DocumentLibraryView(viewModel: model) }
            .environmentObject(AppRouter()))

        let edit = try await element(in: window) { self.isButton($0, "최근 목록 편집") }
        // Not editing: a row offers the swipe's 최근 목록에서 제거 as an action.
        let row = try await element(in: window) { ($0.accessibilityLabel ?? "").hasPrefix("b.hwpx, ") }
        XCTAssertTrue(names(row).contains { matches($0, "최근 목록에서 제거") }, "\(names(row))")

        XCTAssertTrue(edit.accessibilityActivate())
        _ = try await element(in: window) { self.isButton($0, "완료") }
        let stillEdit = try? await element(in: window, timeout: 0.5) { self.isButton($0, "최근 목록 편집") }
        XCTAssertNil(stillEdit)

        // Editing: red delete controls come in before the rows. Their VoiceOver label comes from UIKit's
        // accessibility runtime, which a test process does not load, so that control is checked by hand.
        try await settle(800)
        let editingRow = try await element(in: window) { ($0.accessibilityLabel ?? "").hasPrefix("b.hwpx, ") }
        // VoiceOver keeps the swipe's 최근 목록에서 제거 on the row while editing; it removes the entry as
        // the red delete control's onDelete does (both call `removeRecentDocuments`).
        XCTAssertTrue(names(editingRow).contains { matches($0, "최근 목록에서 제거") }, "\(names(editingRow))")
        try perform("최근 목록에서 제거", on: editingRow)
        try await waitUntil { model.recentDocuments.map(\.displayName) == ["a.xlsx"] }
        let stored = await store.documents()
        XCTAssertEqual(stored.map(\.displayName), ["a.xlsx"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("b.hwpx").path),
            "only the recent entry goes; the file stays")

        // Deleting the last one ends 편집 by itself and the button goes.
        _ = try await element(in: window) { ($0.accessibilityLabel ?? "").hasPrefix("a.xlsx, ") }
        await model.removeRecentDocuments(model.recentDocuments)
        try await waitUntil {
            (try? self.allElements(in: window).contains { self.isButton($0, "완료") || self.isButton($0, "최근 목록 편집") }) == false
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("a.xlsx").path))
    }

    // MARK: 3. AI 문서 선택 rows (AIDocumentSelectionView)

    func testAIDocumentRowsHaveASeparateOpenButtonForSpreadsheetAndHangul() async throws {
        let items = [
            AuthorizedDocumentItem(name: "매출.xlsx", relativePath: "자료/매출.xlsx", pathExtension: "xlsx",
                fileSize: nil, modificationDate: nil),
            AuthorizedDocumentItem(name: "공문.hwp", relativePath: "자료/공문.hwp", pathExtension: "hwp",
                fileSize: nil, modificationDate: nil),
            AuthorizedDocumentItem(name: "보고.hwpx", relativePath: "보고.hwpx", pathExtension: "hwpx",
                fileSize: nil, modificationDate: nil),
            AuthorizedDocumentItem(name: "안내.pdf", relativePath: "안내.pdf", pathExtension: "pdf",
                fileSize: nil, modificationDate: nil),
        ]
        var opened: [String] = []
        var originals: [String] = []
        let window = host(VStack(spacing: 16) {
            ForEach(items) { item in
                AIDocumentSelectionRow(item: item, isImporting: false,
                    onOpen: { opened.append(item.name) }, onOpenOriginal: { originals.append(item.name) })
            }
        }
        .padding(24))

        let all = try await elements(in: window, atLeast: 7)
        func row(_ item: AuthorizedDocumentItem) -> NSObject? {
            all.first { $0.accessibilityLabel == "\(item.name). \(item.relativePath)" }
        }
        let buttons = all.filter { $0.accessibilityLabel == "엑셀에서 편집" || $0.accessibilityLabel == "읽기" }
        XCTAssertEqual(buttons.map { $0.accessibilityLabel ?? "" }, ["엑셀에서 편집", "읽기", "읽기"],
            all.map { $0.accessibilityLabel ?? "" }.description + "\n" + viewTree(window))
        for item in items {
            let element = try XCTUnwrap(row(item), item.name)
            XCTAssertTrue(element.accessibilityTraits.contains(.button))
            XCTAssertFalse(buttons.contains { $0 === element }, "row and button are separate elements")
        }
        // Reading order: each row, then its own button.
        let order = all.compactMap(\.accessibilityLabel).filter {
            $0.hasSuffix(".xlsx") || $0.hasSuffix(".hwp") || $0.hasSuffix(".hwpx") || $0.hasSuffix(".pdf")
                || $0 == "엑셀에서 편집" || $0 == "읽기"
        }
        XCTAssertEqual(order, ["매출.xlsx. 자료/매출.xlsx", "엑셀에서 편집", "공문.hwp. 자료/공문.hwp", "읽기",
                               "보고.hwpx. 보고.hwpx", "읽기", "안내.pdf. 안내.pdf"])
        for button in buttons { XCTAssertTrue(button.accessibilityTraits.contains(.button)) }

        XCTAssertTrue(buttons[0].accessibilityActivate())
        XCTAssertTrue(try XCTUnwrap(row(items[3])).accessibilityActivate())
        XCTAssertTrue(buttons[1].accessibilityActivate())
        try await waitUntil { originals.count == 2 && opened.count == 1 }
        XCTAssertEqual(originals, ["매출.xlsx", "공문.hwp"])
        XCTAssertEqual(opened, ["안내.pdf"])
    }

    // MARK: 4. HWP 간편 보기 find (HWPDocumentView)

    func testSimpleViewFindButtonIsSelectedWhileOpenAndCommandFOpensIt() async throws {
        let url = try hwpx(["첫 문단입니다", "둘째 문단에 사과가 있습니다", "셋째 문단"])
        let model = HWPDocumentViewModel(fileURL: url, autosaveDelay: .seconds(600), recentDocuments: recentStore())
        let window = host(NavigationStack { HWPDocumentView(viewModel: model) })
        try await waitUntil(timeout: .seconds(20)) { !model.isLoading && !model.blocks.isEmpty }

        // 원본 has no header magnifying glass (its find is the ribbon's 찾기 tab); 간편 has it.
        try await settle()
        if let simple = try? await element(in: window, timeout: 0.5, { self.matches($0.accessibilityLabel ?? "", "간편") }) {
            XCTAssertTrue(simple.accessibilityActivate())
        } else {
            let picker = try XCTUnwrap(first(UISegmentedControl.self, in: window), viewTree(window))
            let titles = (0..<picker.numberOfSegments).map { picker.titleForSegment(at: $0) ?? "" }
            let index = try XCTUnwrap(titles.firstIndex { self.matches($0, "간편") }, titles.description)
            picker.selectedSegmentIndex = index
            picker.sendActions(for: .valueChanged)
        }
        var toggle = try await element(in: window) { $0.identifier == "hwp-search-toggle" }
        XCTAssertTrue(matches(toggle.accessibilityLabel ?? "", "찾기·바꾸기"), toggle.accessibilityLabel ?? "")
        XCTAssertTrue(toggle.accessibilityTraits.contains(.button))
        XCTAssertFalse(toggle.accessibilityTraits.contains(.selected))

        XCTAssertTrue(toggle.accessibilityActivate())
        toggle = try await element(in: window) {
            $0.identifier == "hwp-search-toggle" && $0.accessibilityTraits.contains(.selected)
        }
        XCTAssertTrue(toggle.accessibilityActivate())
        _ = try await element(in: window) {
            $0.identifier == "hwp-search-toggle" && !$0.accessibilityTraits.contains(.selected)
        }

        // ⌘F is a key command of the screen; it opens find again.
        let command = try XCTUnwrap(keyCommands(in: window).first {
            $0.command.input?.lowercased() == "f" && $0.command.modifierFlags == .command
        }, "⌘F key command: \(keyCommands(in: window).map { ($0.command.input ?? "", $0.command.modifierFlags.rawValue) })")
        XCTAssertTrue(matches(command.command.discoverabilityTitle ?? command.command.title, "찾기·바꾸기"),
            command.command.discoverabilityTitle ?? command.command.title)
        let action = try XCTUnwrap(command.command.action)
        let target = try XCTUnwrap(command.responder.target(forAction: action, withSender: command.command) as? NSObject)
        _ = target.perform(action, with: command.command)
        _ = try await element(in: window) {
            $0.identifier == "hwp-search-toggle" && $0.accessibilityTraits.contains(.selected)
        }
    }

    // MARK: 5–6. HWP shape sheet: point editor and range notice (HWPShapeEditingSheet)

    func testPolygonPointsReadNumberAndPlaceAndDeleteThePickedPoint() async throws {
        let square: [HWPShapeEditing.PathPoint] = [.init(x: 0, y: 0), .init(x: 1, y: 0), .init(x: 1, y: 1),
                                                   .init(x: 0, y: 1)]
        var applied: [HWPShapeEditing.Layout] = []
        let window = host(HWPShapeEditingSheet(target: shapeTarget(kind: .polygon, points: square),
            onUpdate: { applied.append($0) }, onDelete: {}, onMoveGroupChild: { _ in }, onUngroup: {}))

        func points() throws -> [NSObject] {
            try allElements(in: window).filter { ($0.accessibilityLabel ?? "").hasPrefix("점 ") && ($0.accessibilityLabel ?? "").contains(" / ") }
        }
        _ = try await element(in: window) { $0.accessibilityLabel == "점 4 / 4" }
        var list = try points()
        XCTAssertEqual(list.map { $0.accessibilityLabel ?? "" }, ["점 1 / 4", "점 2 / 4", "점 3 / 4", "점 4 / 4"],
            "drawing order")
        XCTAssertEqual(list.map { $0.accessibilityValue ?? "" },
            ["가로 0%, 세로 0%", "가로 100%, 세로 0%", "가로 100%, 세로 100%", "가로 0%, 세로 100%"])
        XCTAssertTrue(list[0].accessibilityTraits.contains(.selected), "the first point starts picked")
        XCTAssertFalse(list[1].accessibilityTraits.contains(.selected))
        XCTAssertEqual(names(list[1]), ["위로 이동", "아래로 이동", "왼쪽으로 이동", "오른쪽으로 이동", "점 추가", "선택한 점 삭제"],
            "VoiceOver's order, as Android")

        // 왼쪽으로 이동 on 점 2 moves it 5% and picks it.
        try perform("왼쪽으로 이동", on: list[1])
        _ = try await element(in: window) { $0.accessibilityLabel == "점 2 / 4" && $0.accessibilityValue == "가로 95%, 세로 0%" }
        list = try points()
        XCTAssertTrue(list[1].accessibilityTraits.contains(.selected))

        // 선택한 점 삭제 on 점 3 removes that point (not the second-to-last as before).
        try perform("선택한 점 삭제", on: list[2])
        _ = try await element(in: window) { $0.accessibilityLabel == "점 3 / 3" }
        list = try points()
        XCTAssertEqual(list.map { $0.accessibilityValue ?? "" },
            ["가로 0%, 세로 0%", "가로 95%, 세로 0%", "가로 0%, 세로 100%"])
        XCTAssertFalse(names(list[0]).contains("선택한 점 삭제"), "a polygon keeps three points")
        let delete = try await element(in: window) { $0.identifier == "hwp-shape-path-delete" }
        XCTAssertTrue(delete.accessibilityTraits.contains(.notEnabled))

        let apply = try await element(in: window) { $0.identifier == "hwp-shape-apply" }
        XCTAssertFalse(apply.accessibilityTraits.contains(.notEnabled))
        XCTAssertTrue(apply.accessibilityActivate())
        try await waitUntil { applied.count == 1 }
        XCTAssertEqual(applied.first?.pathPoints.count, 3)
        XCTAssertEqual(applied.first?.pathPoints[2], .init(x: 0, y: 1))
        XCTAssertEqual(applied.first?.pathPoints[1].x ?? 0, 0.95, accuracy: 1e-9)
    }

    func testShapeOutOfRangeValueShowsItsReasonAndDimsApply() async throws {
        let target = shapeTarget(kind: .rectangle, points: [],
            shadow: .init(colorRGB: 0, offsetX: 150, offsetY: 3, opacity: 0.5))
        let window = host(HWPShapeEditingSheet(target: target, onUpdate: { _ in }, onDelete: {},
            onMoveGroupChild: { _ in }, onUngroup: {}))

        let notice = try await element(in: window) { $0.identifier == "hwp-range-notice" }
        XCTAssertEqual(notice.accessibilityLabel,
            "가로 이동: 문서의 값 150 pt이(가) 적용할 수 있는 범위(-100~100 pt)를 벗어났습니다.\n범위 안으로 바꾸면 적용할 수 있습니다.")
        let apply = try await element(in: window) { $0.identifier == "hwp-shape-apply" }
        XCTAssertTrue(apply.accessibilityTraits.contains(.notEnabled), "적용 is dimmed")

        // In range: no notice and 적용 is enabled.
        let fine = host(HWPShapeEditingSheet(target: shapeTarget(kind: .rectangle, points: [],
            shadow: .init(colorRGB: 0, offsetX: 3, offsetY: 3, opacity: 0.5)),
            onUpdate: { _ in }, onDelete: {}, onMoveGroupChild: { _ in }, onUngroup: {}))
        let fineApply = try await element(in: fine) { $0.identifier == "hwp-shape-apply" }
        XCTAssertFalse(fineApply.accessibilityTraits.contains(.notEnabled))
        XCTAssertFalse(try allElements(in: fine).contains { $0.identifier == "hwp-range-notice" })
    }

    // MARK: 7. HWP chart and picture labels on the 원본 pages

    func testStagedHangulFilesReadChartsAndPicturesAsAndroid() async throws {
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let names = ["테스트_차트.hwp", "테스트_다각형.hwp", "테스트_곡선연결선.hwp"]
        let staged = names.map { documents.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        try XCTSkipIf(staged.isEmpty, "the staged 테스트_*.hwp files are not in Documents/")
        var charts = 0
        var report: [String] = []
        for source in staged {
            // A copy: the staged file is only read.
            let url = try temporaryDirectory().appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: url)
            let model = HWPDocumentViewModel(fileURL: url, autosaveDelay: .seconds(600), recentDocuments: recentStore())
            await model.load()
            XCTAssertNil(model.errorDescription, source.lastPathComponent)
            var objects: [String: (HWPDocumentCanvasObject, Bool)] = [:]
            for block in model.blocks {
                for object in block.canvasObjects { objects[object.id] = (object, false) }
            }
            let navigation = HWPDocumentNavigation()
            navigation.update(blocks: model.blocks, layouts: model.pageLayouts)
            report.append("\(source.lastPathComponent): \(model.blocks.count) blocks, \(objects.count) objects "
                + "\(objects.values.map { String(describing: $0.0.content).prefix(40) }), \(navigation.pages.count) pages")
            for page in navigation.pages {
                let window = host(HWPOriginalCanvasPageView(page: page)
                    .environment(\.hwpInlineEditing, HWPInlineEditingContext(session: HWPInlineEditingSession()))
                    .environment(\.hwpCanvasObjectSelection, .editingTargets(in: model.blocks)))
                try await settle()
                let nodes = try allElements(in: window)
                report.append("  page \(page.pageNumber): \(nodes.count) elements, ids \(nodes.map(\.identifier).filter { !$0.isEmpty }.prefix(12))")
                for node in nodes where node.identifier.hasPrefix("hwp-canvas-object-") {
                    let id = String(node.identifier.dropFirst("hwp-canvas-object-".count))
                    guard let (object, _) = objects[id] else { continue }
                    let label = node.accessibilityLabel ?? ""
                    report.append("\(source.lastPathComponent) p\(page.pageNumber) \(id): \(label)")
                    let hasText = !(node.accessibilityValue ?? "").isEmpty
                    let expected = HWPCanvasObjectLabel.text(object, hasText: hasText)
                    XCTAssertEqual(label, expected, "\(source.lastPathComponent) \(id)")
                    switch object.content {
                    case .chart(let chart):
                        charts += 1
                        XCTAssertTrue(label.contains("차트"), label)
                        let series = chart.series.map(\.name).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        if !series.isEmpty { XCTAssertTrue(label.contains("계열: " + series.joined(separator: ", ")), label) }
                        if let title = chart.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                            XCTAssertTrue(label.contains(title), label)
                        }
                    case .image:
                        XCTAssertTrue(label == "그림" || label.hasPrefix("그림: "), label)
                    default:
                        break
                    }
                }
                window.isHidden = true
            }
        }
        print("HWP object labels:\n" + report.joined(separator: "\n"))
        let attachment = XCTAttachment(string: report.joined(separator: "\n"))
        attachment.lifetime = .keepAlways
        add(attachment)
        if staged.contains(where: { $0.lastPathComponent == "테스트_차트.hwp" }) {
            XCTAssertGreaterThan(charts, 0, "테스트_차트.hwp shows a chart:\n" + report.joined(separator: "\n"))
        }
    }

    func testDescribedPictureReadsPictureColonDescription() async throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "그림"))
        let selection = try XCTUnwrap(HWPImageEditing.selection(blocks: package.blocks,
            selectedID: package.blocks[0].id, range: NSRange(location: 1, length: 0), layouts: package.pageLayouts))
        let png = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
        let image = try HWPImageEditing.normalize(png)
        let size = image.displaySize(maxWidth: selection.width)
        let inserted = try await HWPImageEditing.inserting(.init(selection: selection, image: image,
            widthPoints: size.width, heightPoints: size.height),
            source: HWPTableStructureDocument.hwpx(package), drafts: package.blocks)
        let url = try temporaryDirectory().appendingPathComponent("그림.hwpx")
        try inserted.document.data.write(to: url)
        let model = HWPDocumentViewModel(fileURL: url, autosaveDelay: .seconds(600), recentDocuments: recentStore())
        await model.load()
        var owner = try XCTUnwrap(model.blocks.first { !$0.canvasObjects.isEmpty })
        let target = try XCTUnwrap(HWPImageEditing.target(owner: owner, object: try XCTUnwrap(owner.canvasObjects.first)))
        _ = try await model.describeImage("회사 로고", target: target)
        owner = try XCTUnwrap(model.blocks.first { !$0.canvasObjects.isEmpty })
        let object = try XCTUnwrap(owner.canvasObjects.first)
        let navigation = HWPDocumentNavigation()
        navigation.update(blocks: model.blocks, layouts: model.pageLayouts)
        let page = try XCTUnwrap(navigation.pages.first)
        let window = host(HWPOriginalCanvasPageView(page: page)
            .environment(\.hwpInlineEditing, HWPInlineEditingContext(session: HWPInlineEditingSession()))
            .environment(\.hwpCanvasObjectSelection, .editingTargets(in: model.blocks)))
        let node = try await element(in: window) { $0.identifier == "hwp-canvas-object-\(object.id)" }
        XCTAssertEqual(node.accessibilityLabel, "그림: 회사 로고")
    }

    // MARK: 8. Excel row form dropdown (ExcelEditRowView)

    func testRowFormDropdownReadsTheDisplayedTextOfARangeChoice() async throws {
        let url = try temporaryDirectory().appendingPathComponent("목록.xlsx")
        try formattedListWorkbookData().write(to: url)
        let model = ExcelWorkbookViewModel(fileURL: url, autosaveDelay: .seconds(600))
        await model.load()
        let columns = [ExcelAccessibleColumn(column: 1, title: "이름"), ExcelAccessibleColumn(column: 2, title: "값")]
        let window = host(ExcelEditRowView(row: 2, initialFields: model.rowFields(for: 2, columns: columns),
            viewModel: model))

        // The field reads its title and the choice's shown text, not the stored 1.2345.
        let field = try await element(in: window) { $0.accessibilityLabel == "값" && $0.accessibilityTraits.contains(.button) }
        XCTAssertEqual(field.accessibilityValue, "1.23")

        // The menu's items are `Button(field.dropdownLabels[index])` (verbatim text), after 비움: the menu
        // itself opens only through UIKit's accessibility runtime, so its items are read from the field.
        let shown = try XCTUnwrap(model.rowFields(for: 2, columns: columns).first { $0.column == 2 })
        XCTAssertTrue(shown.dropdownAllowsBlank)
        XCTAssertEqual(shown.dropdownLabels, ["1.23", "대기"])
        XCTAssertEqual(shown.dropdownValues, ["1.2345", "대기"])
    }

    // MARK: 9. Going to the background writes pending edits (DocumentBackgroundSave)

    func testHangulScreenSavesPendingEditWhenTheSceneGoesToTheBackground() async throws {
        let url = try hwpx(["원문"])
        let original = try Data(contentsOf: url)
        let model = HWPDocumentViewModel(fileURL: url, autosaveDelay: .seconds(600), recentDocuments: recentStore())
        let phase = PhaseBox()
        let window = host(PhaseHost(phase: phase) { NavigationStack { HWPDocumentView(viewModel: model) } })
        try await waitUntil(timeout: .seconds(20)) { !model.isLoading && !model.blocks.isEmpty }
        model.selectBlock(try XCTUnwrap(model.blocks.first { $0.text == "원문" }).id)
        model.editorText = "배경 저장"
        model.commitEditorChange()
        XCTAssertTrue(model.hasUnsavedChanges)

        // The app's own didEnterBackground notification is not what the screen listens to.
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: UIApplication.shared)
        try await settle()
        XCTAssertEqual(try Data(contentsOf: url), original, "the 10-minute autosave has not run")

        phase.value = .background
        try await waitUntil { !model.hasUnsavedChanges }
        XCTAssertEqual(try HWPXDocumentPackage.load(from: Data(contentsOf: url)).blocks.first?.text, "배경 저장")
        _ = window
    }

    func testSpreadsheetScreenSavesPendingEditWhenTheSceneGoesToTheBackground() async throws {
        let url = try temporaryDirectory().appendingPathComponent("배경.xlsx")
        try formattedListWorkbookData().write(to: url)
        let model = ExcelWorkbookViewModel(fileURL: url, autosaveDelay: .seconds(600))
        let phase = PhaseBox()
        let window = host(PhaseHost(phase: phase) { NavigationStack { ExcelWorkbookView(viewModel: model) } })
        try await waitUntil(timeout: .seconds(20)) { !model.isLoading && model.selectedSheet != nil }
        model.selectCell(.init(row: 2, column: 1))
        model.updateEditorText("배경 입력")
        XCTAssertTrue(model.hasUnsavedChanges)
        try await settle()
        XCTAssertEqual(try sheetCell(url, row: 2, column: 1)?.displayValue, "가")

        phase.value = .inactive
        try await waitUntil { !model.hasUnsavedChanges }
        XCTAssertEqual(try sheetCell(url, row: 2, column: 1)?.displayValue, "배경 입력")
        _ = window
    }

    // MARK: - Hosting

    private func host<Content: View>(_ view: Content, size: CGSize? = nil) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        let bounds = scene?.screen.bounds ?? CGRect(x: 0, y: 0, width: 834, height: 1194)
        window.frame = CGRect(origin: .zero, size: size ?? bounds.size)
        window.windowLevel = .normal + 10
        window.rootViewController = UIHostingController(rootView: AnyView(view))
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        windows.append(window)
        return window
    }

    private func settle(_ milliseconds: Int = 400) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }

    private func view<T: UIView>(_ type: T.Type, in window: UIWindow) async throws -> T {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if let found = first(type, in: window) { return found }
            try await settle(100)
        } while Date() < deadline
        XCTFail("no \(type) in the window\n\(viewTree(window))")
        throw CancellationError()
    }

    private func first<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews { if let match = first(type, in: subview) { return match } }
        return nil
    }

    // MARK: Accessibility tree

    private func element(in window: UIWindow, timeout: TimeInterval = 5,
                         _ predicate: (NSObject) -> Bool) async throws -> NSObject {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let match = try allElements(in: window).first(where: predicate) { return match }
            try await settle(100)
        } while Date() < deadline
        if timeout >= 1 { XCTFail("Accessibility element not found\n\(dump(window))") }
        throw CancellationError()
    }

    private func elements(in window: UIWindow, atLeast count: Int) async throws -> [NSObject] {
        let deadline = Date().addingTimeInterval(5)
        var found: [NSObject] = []
        repeat {
            found = try allElements(in: window)
            if found.count >= count { return found }
            try await settle(100)
        } while Date() < deadline
        return found
    }

    private func allElements(in window: UIWindow) throws -> [NSObject] {
        var found: [NSObject] = []
        var visited = Set<ObjectIdentifier>()
        collect(window, depth: 0, into: &found, visited: &visited)
        return found
    }

    /// What VoiceOver reaches: an accessibility element is a leaf (its implementation subviews are not read),
    /// and a container's own elements (accessibilityElements or the indexed container methods) replace its
    /// subviews.
    private func collect(_ object: NSObject, depth: Int, into found: inout [NSObject],
                         visited: inout Set<ObjectIdentifier>) {
        guard depth < 120, visited.insert(ObjectIdentifier(object)).inserted else { return }
        if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return }
        if object.accessibilityElementsHidden { return }
        if object.isAccessibilityElement {
            found.append(object)
            return
        }
        var children: [NSObject] = []
        if let list = object.accessibilityElements {
            children = list.compactMap { $0 as? NSObject }
        } else if case let count = object.accessibilityElementCount(), count != NSNotFound, count > 0 {
            for index in 0..<min(count, 50_000) {
                if let child = object.accessibilityElement(at: index) as? NSObject { children.append(child) }
            }
        } else if let view = object as? UIView {
            children = view.subviews
        }
        for child in children { collect(child, depth: depth + 1, into: &found, visited: &visited) }
    }

    private func dump(_ window: UIWindow) -> String {
        ((try? allElements(in: window)) ?? []).map { element in
            var line = "\(type(of: element)) '\(element.accessibilityLabel ?? "")'"
            if let value = element.accessibilityValue, !value.isEmpty { line += " value='\(value)'" }
            if !element.identifier.isEmpty { line += " id=\(element.identifier)" }
            line += " traits=\(element.accessibilityTraits.rawValue)"
            let actions = names(element)
            if !actions.isEmpty { line += " actions=\(actions)" }
            return line
        }.joined(separator: "\n")
    }

    private func viewTree(_ view: UIView, depth: Int = 0) -> String {
        guard depth < 40 else { return "" }
        var line = String(repeating: " ", count: depth) + "\(type(of: view)) \(view.frame.integral)"
        if view.isHidden { line += " hidden" }
        if view.alpha < 0.01 { line += " alpha0" }
        if view.isAccessibilityElement { line += " el '\(view.accessibilityLabel ?? "")'" }
        if let list = view.accessibilityElements { line += " axElements=\(list.count)" }
        if !view.interactions.isEmpty { line += " interactions=\(view.interactions.map { String(describing: type(of: $0)) })" }
        return ([line] + view.subviews.map { viewTree($0, depth: depth + 1) }).joined(separator: "\n")
    }

    /// The key text, its translation in the app language, or in the system language.
    private func matches(_ text: String, _ key: String) -> Bool {
        text == key || text == AppLocalization.string(key) || text == NSLocalizedString(key, comment: "")
    }

    private func isButton(_ element: NSObject, _ key: String) -> Bool {
        element.accessibilityTraits.contains(.button) && matches(element.accessibilityLabel ?? "", key)
    }

    private func names(_ element: NSObject) -> [String] {
        (element.accessibilityCustomActions ?? []).map(\.name)
    }

    private func perform(_ name: String, on element: NSObject) throws {
        let action = try XCTUnwrap(element.accessibilityCustomActions?.first { matches($0.name, name) },
            "\(name) in \(names(element))")
        if let handler = action.actionHandler {
            XCTAssertTrue(handler(action), name)
        } else if let target = action.target as? NSObject {
            _ = target.perform(action.selector, with: action)
        } else {
            XCTFail("\(name) has no handler")
        }
    }

    private func keyCommands(in window: UIWindow) -> [(command: UIKeyCommand, responder: UIResponder)] {
        var result: [(UIKeyCommand, UIResponder)] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ responder: UIResponder?) {
            var current = responder
            while let next = current, seen.insert(ObjectIdentifier(next)).inserted {
                for command in next.keyCommands ?? [] { result.append((command, next)) }
                current = next.next
            }
        }
        func walk(_ view: UIView) {
            visit(view)
            view.subviews.forEach(walk)
        }
        walk(window)
        return result
    }

    // MARK: Fixtures

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentAccessibilityHostedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        cleanup.append(url)
        return url
    }

    private func recentStore() -> RecentOriginalDocumentStore {
        let suite = "DocumentAccessibilityHostedTests-\(UUID().uuidString)"
        suites.append(suite)
        return RecentOriginalDocumentStore(defaults: UserDefaults(suiteName: suite)!, storageKey: "records")
    }

    private func hwpx(_ paragraphs: [String]) throws -> URL {
        let url = try temporaryDirectory().appendingPathComponent("문서.hwpx")
        try LegacyHWPXConverter.convert(text: paragraphs.joined(separator: "\n")).write(to: url)
        return url
    }

    private func pdfData(pages: [String]) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for text in pages {
                context.beginPage()
                (text as NSString).draw(at: CGPoint(x: 72, y: 72),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
            }
        }
    }

    private func shapeTarget(kind: HWPShapeEditing.Kind, points: [HWPShapeEditing.PathPoint],
                             shadow: HWPShapeEditing.Shadow? = nil) -> HWPShapeEditing.Target {
        HWPShapeEditing.Target(ownerID: "owner", objectID: "shape", groupChildCount: 0, kind: kind,
            xPoints: 0, yPoints: 0, widthPoints: 120, heightPoints: 80, zOrder: 0, rotationDegrees: 0,
            flipHorizontal: false, flipVertical: false, strokeColorRGB: 0, strokeWidthPoints: 1, strokeStyle: 1,
            fillColorRGB: 0xFFFFFF, shadow: shadow, isInline: true, horizontalReference: .paragraph,
            verticalReference: .paragraph, horizontalAlignment: .start, verticalAlignment: .start,
            wrap: .topAndBottom, marginLeftPoints: 0, marginRightPoints: 0, marginTopPoints: 0,
            marginBottomPoints: 0, pathPoints: points, startArrow: 0, endArrow: 0)
    }

    private func sheetCell(_ url: URL, row: Int, column: Int) throws -> ExcelCell? {
        try ExcelWorkbookDocument.load(from: Data(contentsOf: url)).sheets.first?.cell(at: .init(row: row, column: column))
    }

    /// 1.2345 formatted 0.00 in H1 and 대기 in H2, the list for B2:B10; A2 가, B2 1.2345.
    private func formattedListWorkbookData() throws -> Data {
        let entries = [
            "[Content_Types].xml": #"<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>"#,
            "xl/workbook.xml": #"<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="목록" sheetId="1" r:id="rId1"/></sheets></workbook>"#,
            "xl/_rels/workbook.xml.rels": #"<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>"#,
            "xl/styles.xml": #"<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font/></fonts><fills count="1"><fill><patternFill patternType="none"/></fill></fills><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0"/><xf numFmtId="2" fontId="0" fillId="0" applyNumberFormat="1"/></cellXfs></styleSheet>"#,
            "xl/worksheets/sheet1.xml": #"<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="A1:H2"/><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>이름</t></is></c><c r="B1" t="inlineStr"><is><t>값</t></is></c><c r="H1" s="1"><v>1.2345</v></c></row><row r="2"><c r="A2" t="inlineStr"><is><t>가</t></is></c><c r="B2" s="1"><v>1.2345</v></c><c r="H2" t="inlineStr"><is><t>대기</t></is></c></row></sheetData><dataValidations count="1"><dataValidation type="list" allowBlank="1" sqref="B2:B10"><formula1>$H$1:$H$2</formula1></dataValidation></dataValidations></worksheet>"#,
        ]
        let archive = try Archive(accessMode: .create)
        for (path, string) in entries.sorted(by: { $0.key < $1.key }) {
            let data = Data(string.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                compressionMethod: .deflate) { position, size in
                let lower = Int(position)
                let upper = min(data.count, lower + size)
                return lower < upper ? data.subdata(in: lower..<upper) : Data()
            }
        }
        return try XCTUnwrap(archive.data)
    }

    private func waitUntil(timeout: Duration = .seconds(10), _ condition: () throws -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if try condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(try condition(), "timed out")
    }
}

/// The scene phase a hosted screen sees, changed by the test as iPadOS changes it.
@MainActor
private final class PhaseBox: ObservableObject {
    @Published var value: ScenePhase = .active
}

private struct PhaseHost<Content: View>: View {
    @ObservedObject var phase: PhaseBox
    @ViewBuilder let content: () -> Content

    var body: some View {
        content().environment(\.scenePhase, phase.value)
    }
}

/// The in-process accessibility flag XCUITest and VoiceOver turn on; SwiftUI builds the full accessibility
/// tree of nested hosting views only while it is on.
private enum InProcessAccessibility {
    private typealias Getter = @convention(c) () -> Bool
    private typealias Setter = @convention(c) (Bool) -> Void
    private static let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW)

    static var isEnabled: Bool {
        guard let handle, let symbol = dlsym(handle, "_AXSApplicationAccessibilityEnabled") else { return false }
        return unsafeBitCast(symbol, to: Getter.self)()
    }

    static func setEnabled(_ enabled: Bool) {
        guard let handle else { return }
        for name in ["_AXSApplicationAccessibilitySetEnabled", "_AXSSetAutomationEnabled"] {
            if let symbol = dlsym(handle, name) { unsafeBitCast(symbol, to: Setter.self)(enabled) }
        }
    }
}

private extension NSObject {
    var identifier: String {
        responds(to: NSSelectorFromString("accessibilityIdentifier"))
            ? (value(forKey: "accessibilityIdentifier") as? String ?? "") : ""
    }
}
