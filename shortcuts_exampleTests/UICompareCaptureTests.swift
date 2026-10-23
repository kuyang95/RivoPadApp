import RivoDocumentEngine
import SwiftUI
import UIKit
import WebKit
import XCTest
@testable import shortcuts_example

/// Captures PNGs of the document screens for an iOS/Android visual comparison.
/// Not a regression test: it drives the real views through their accessibility
/// elements (the same entry points VoiceOver uses) and writes
/// `Documents/ui-compare/<state>.png` in the app container.
@MainActor
final class UICompareCaptureTests: XCTestCase {
    private var window: UIWindow?
    private var outputDirectory: URL!
    private var savedLanguage: Any?
    private var savedRecents: Any?
    private var logLines: [String] = []
    private var workDirectory: URL!

    override func setUp() async throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        outputDirectory = documents.appendingPathComponent("ui-compare", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory.appendingPathComponent("_ax"),
            withIntermediateDirectories: true)
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ui-compare-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        savedLanguage = UserDefaults.standard.object(forKey: AppLanguage.preferenceKey)
        UserDefaults.standard.set(AppLanguage.korean.rawValue, forKey: AppLanguage.preferenceKey)
        savedRecents = UserDefaults.standard.object(forKey: "RecentOriginalDocumentStore.records.v1")
        enableInProcessAccessibility()
        await ensurePortrait()
    }

    /// SwiftUI builds the accessibility tree of nested hosting views (scroll views,
    /// UIKit-wrapped grids) only while an assistive client is active. Turn on the
    /// same in-process flag XCUITest uses so those elements exist.
    private func enableInProcessAccessibility(_ enabled: Bool = true) {
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW) else { log("libAccessibility unavailable"); return }
        typealias Setter = @convention(c) (Bool) -> Void
        for name in ["_AXSApplicationAccessibilitySetEnabled", "_AXSSetAutomationEnabled"] {
            if let symbol = dlsym(handle, name) {
                unsafeBitCast(symbol, to: Setter.self)(enabled)
            }
        }
    }

    /// Nested SwiftUI hosting views keep a stale accessibility tree until their
    /// content changes; toggling the in-process flag makes them rebuild it.
    private func refreshAccessibility() async {
        enableInProcessAccessibility(false)
        await pump(0.3)
        enableInProcessAccessibility(true)
        UIAccessibility.post(notification: .screenChanged, argument: nil)
        await pump(0.7)
    }

    override func tearDown() async throws {
        closeWindow()
        if let savedLanguage { UserDefaults.standard.set(savedLanguage, forKey: AppLanguage.preferenceKey) }
        else { UserDefaults.standard.removeObject(forKey: AppLanguage.preferenceKey) }
        if let savedRecents { UserDefaults.standard.set(savedRecents, forKey: "RecentOriginalDocumentStore.records.v1") }
        else { UserDefaults.standard.removeObject(forKey: "RecentOriginalDocumentStore.records.v1") }
        try? FileManager.default.removeItem(at: workDirectory)
        flushLog()
    }

    // MARK: - Text source selection

    func testDaisyWidgetCanEnterAndReenterInsideAppNavigation() async throws {
        let holder = PathHolder()
        await showRoot(PushedRoot(holder: holder) {
            RatioDaisyWidgetView()
                .environmentObject(RivoScreenRemoteControlCenter())
        })
        for _ in 0..<2 {
            holder.path.append(1)
            let picker = await waitFor(timeout: 8) { $0.label.contains("도서 파일 선택") }
            XCTAssertNotNil(picker)
            XCTAssertFalse(elements().contains { $0.label == "위젯 설정" })
            capture("ratio-daisy-page")
            holder.path.removeLast()
            await pump(0.8)
        }
        XCTAssertTrue(holder.path.isEmpty)
    }

    func testLauncherUtilityWidgetControls() async throws {
        let saved = UserDefaults.standard.data(forKey: "ratio.home.widgets.v2")
        await show(VStack(alignment: .leading, spacing: 12) {
                RatioUtilityWidget(widget: RatioHomeItem(id: "widget:weather", name: "날씨", columns: 2, rows: 3), active: false, onEdit: {})
                    .frame(width: 360, height: 288)
                RatioUtilityWidget(widget: RatioHomeItem(id: "widget:timer", name: "타이머", columns: 4, rows: 3), active: false, onEdit: {})
                    .frame(height: 388)
                Spacer()
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background { GeometryReader { geometry in Image("RatioForestMist").resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped().overlay(Color.black.opacity(0.7)) } }
        )
        await pump(1)
        XCTAssertTrue(elements().contains { $0.label == "지역 선택" })
        XCTAssertTrue(elements().contains { $0.label == "시작" })
        XCTAssertTrue(elements().contains { $0.label == "알람" })
        capture("ratio-utility-widgets")
        XCTAssertEqual(saved, UserDefaults.standard.data(forKey: "ratio.home.widgets.v2"))
    }

    func testLauncherSingleStylePreservesSavedLayout() async throws {
        await show(RatioLauncherView().environmentObject(RivoScreenRemoteControlCenter()))
        let pageDot = await waitFor(timeout: 8) { $0.label.contains("페이지 중") }
        let dot = try XCTUnwrap(pageDot)
        let count = try XCTUnwrap(Int(dot.label.components(separatedBy: "페이지")[0]))
        let saved = UserDefaults.standard.data(forKey: "ratio.home.widgets.v2")
        let names = ["잉크 + 레몬", "종이 + 잉크", "사진 + 단정한 타일"]
        for index in 0..<min(count, 2) {
            try await activate(label: "\(count)페이지 중 \(index + 1)페이지")
            await pump(1)
            XCTAssertFalse(elements().contains { names.contains($0.label) })
            capture("ratio-single-style-\(index + 1)")
        }
        XCTAssertEqual(saved, UserDefaults.standard.data(forKey: "ratio.home.widgets.v2"))
        try await activate(label: "\(count)페이지 중 1페이지")
    }

    func testLauncherFeaturePagesShowWallpaperWithoutWidgetChrome() async throws {
        let savedLayout = UserDefaults.standard.data(forKey: "ratio.home.widgets.v2")
        await show(RatioLauncherView().environmentObject(RivoScreenRemoteControlCenter()))
        let pageDot = await waitFor(timeout: 8) { $0.label.contains("페이지 중") }
        let dot = try XCTUnwrap(pageDot)
        let count = try XCTUnwrap(Int(dot.label.components(separatedBy: "페이지")[0]))
        XCTAssertGreaterThanOrEqual(count, 4)
        for index in (count - 2)...count {
            try await activate(label: "\(count)페이지 중 \(index)페이지")
            await pump(2)
            XCTAssertFalse(elements().contains { $0.label == "이전 화면" })
            XCTAssertFalse(elements().contains { $0.label == "위젯 설정" })
            XCTAssertFalse(elements().contains { $0.label == "이지 유튜브" })
            capture("ratio-clear-page-\(index)")
        }
        try await activate(label: "\(count)페이지 중 1페이지")
        XCTAssertEqual(savedLayout, UserDefaults.standard.data(forKey: "ratio.home.widgets.v2"))
    }

    func testWebWidgetsTrackDragAndSettleWithoutRemovingSource() async throws {
        let savedLayout = UserDefaults.standard.data(forKey: "ratio.home.widgets.v2")
        await show(RatioLauncherView().environmentObject(RivoScreenRemoteControlCenter()))
        let pageDot = await waitFor(timeout: 8) { $0.label.contains("페이지 중") }
        let dot = try XCTUnwrap(pageDot)
        let count = try XCTUnwrap(Int(dot.label.components(separatedBy: "페이지")[0]))
        let window = try XCTUnwrap(window)
        var checked = 0
        for index in 1...count {
            try await activate(label: "\(count)페이지 중 \(index)페이지")
            await pump(0.6)
            guard let web = allViews(in: window).compactMap({ $0 as? WKWebView }).first(where: {
                $0.convert($0.bounds, to: window).intersection(window.bounds).width > $0.bounds.width * 0.95
            }), let swipe = web.gestureRecognizers?.compactMap({ $0.delegate as? LauncherWebPageSwipe }).first else { continue }
            for _ in 0..<40 {
                swipe.prepare(at: CGPoint(x: web.bounds.width * 0.5, y: web.bounds.height * 0.45))
                await pump(0.05)
                if swipe.eligible { break }
            }
            XCTAssertTrue(swipe.eligible)
            let origin = web.convert(.zero, to: window).x
            // A short/cancelled pan returns the same native view to its original position.
            swipe.update(translation: CGPoint(x: -80, y: 0))
            await pump(0.1)
            XCTAssertLessThan(web.convert(.zero, to: window).x, origin - 40)
            XCTAssertNotNil(web.superview)
            swipe.finish(translation: CGPoint(x: -80, y: 0), cancelled: true)
            await pump(0.6)
            XCTAssertEqual(web.convert(.zero, to: window).x, origin, accuracy: 2)
            swipe.prepare(at: CGPoint(x: web.bounds.width * 0.5, y: web.bounds.height * 0.45))
            await pump(0.1)
            let distance = -web.bounds.width * 0.3
            swipe.update(translation: CGPoint(x: distance, y: 0))
            await pump(0.1)
            XCTAssertEqual(web.convert(.zero, to: window).x, origin + distance, accuracy: 3)
            capture("ratio-web-drag-\(index)")
            swipe.finish(translation: CGPoint(x: distance, y: 0))
            await pump(0.6)
            XCTAssertTrue(elements().contains { $0.label == "\(count)페이지 중 \(min(count,index+1))페이지" && $0.traits.contains(.selected) })
            checked += 1
        }
        XCTAssertEqual(checked, 2)
        try await activate(label: "\(count)페이지 중 1페이지")
        XCTAssertEqual(savedLayout, UserDefaults.standard.data(forKey: "ratio.home.widgets.v2"))
    }

    func testTextSourceReplacesEditorUntilClipboardLoads() async throws {
        let savedClipboard = UIPasteboard.general.items
        defer { UIPasteboard.general.items = savedClipboard }
        UIPasteboard.general.string = ""
        await show(
            TextEditorViewerView(title: "텍스트", text: "")
                .environmentObject(RivoScreenRemoteControlCenter())
        )
        let source = await waitFor(timeout: 5) { $0.identifier == "text.source.clipboard" }
        XCTAssertNotNil(source)
        XCTAssertFalse(elements().contains { $0.label.contains("여기에 텍스트를 입력하세요.") })
        XCTAssertFalse(elements().contains { $0.label == "에디터 메뉴 열기" })
        capture("text-source-selection")

        try await activate { $0.identifier == "text.source.clipboard" }
        let emptyFeedback = await waitFor(timeout: 3) { $0.label == "클립보드가 비었습니다." }
        XCTAssertNotNil(emptyFeedback)
        XCTAssertTrue(elements().contains { $0.identifier == "text.source.clipboard" })
        capture("text-source-empty-clipboard")

        UIPasteboard.general.string = "가져온 본문만 표시합니다."
        try await activate { $0.identifier == "text.source.clipboard" }
        let loaded = await waitFor(timeout: 5) { $0.label == "가져온 본문만 표시합니다." }
        XCTAssertNotNil(loaded)
        XCTAssertFalse(elements().contains { $0.identifier.hasPrefix("text.source.") })
        XCTAssertTrue(elements().contains { $0.label == "에디터 메뉴 열기" })
        capture("text-source-loaded")
    }

    // MARK: - Library and legacy XLS

    func testLibraryAndLegacyXLS() async throws {
        for (name, ext) in [("ToolXkit_Sample", "xlsx"), ("mss_voucher", "hwpx"),
                            ("hangul_design_application", "hwp"), ("legacy_values", "xls")] {
            let url = try copyFixture(name, ext)
            _ = try? await RecentOriginalDocumentStore.shared.register(fileURL: url)
        }
        await show(DocumentLibraryView())
        _ = await waitFor(timeout: 5) { $0.label.contains("최근에 연 문서") || $0.label.contains("ToolXkit") }
        await pump(2.5)
        capture("library")

        let xls = try copyFixture("legacy_values", "xls")
        await show(LegacyXLSConversionView(fileURL: xls))
        await pump(2.5)
        capture("xls-readonly")
    }

    /// The library pushed with animation from an empty stack, as the app's router does.
    func testLibraryPushed() async throws {
        for (name, ext) in [("ToolXkit_Sample", "xlsx"), ("mss_voucher", "hwpx")] {
            let url = try copyFixture(name, ext)
            _ = try? await RecentOriginalDocumentStore.shared.register(fileURL: url)
        }
        let pusher = PathHolder()
        await showRoot(PushedRoot(holder: pusher) { DocumentLibraryView().visionCraftRouteBackButton() })
        await pump(1.0)
        withAnimation { pusher.path.append(1) }
        await pump(3.0)
        capture("library-pushed")
    }

    /// Writes the iOS-inserted rectangle file next to the captures, to compare with the Android one.
    func testShapeFile() async throws {
        let url = try await prepareHWPFixture()
        let out = outputDirectory.appendingPathComponent("shape-ios.hwpx")
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.copyItem(at: url, to: out)
        let reopened = HWPDocumentViewModel(fileURL: url)
        await reopened.load()
        let model = HWPDocumentViewModel(fileURL: try copyFixture("mss_voucher", "hwpx"))
        await model.load()
        log("pristine blocks=\(model.blocks.count) reopened blocks=\(reopened.blocks.count)")
        for b in reopened.blocks.prefix(12) { log("R \(b.id) \(b.text.prefix(24))") }
        for b in model.blocks.prefix(12) { log("P \(b.id) \(b.text.prefix(24))") }
        try await openHWP(url)
        await pump(1.5)
        capture("hwp-shape-reopened")
    }

    // MARK: - Excel

    func testExcel() async throws {
        let url = try copyFixture("ToolXkit_Sample", "xlsx")

        await attempt("excel-grid") {
            // excel-grid
            try await openExcel(url)
            try await selectExcelCell("B3")
            capture("excel-grid")
        }

        await attempt("excel-simple") {
            // excel-simple
            setSegment("간편")
            await pump(1.2)
            capture("excel-simple")
        }

        await attempt("excel-celltools") {
            // excel-celltools + excel-tool-format (표시 형식 page of the cell tools dialog)
            try await openExcel(url)
            try await selectExcelCell("B3")
            try await activate(label: "셀 도구")
            _ = await waitFor(timeout: 4) { $0.label.hasPrefix("표시 형식") }
            await pump(1.5)
            capture("excel-celltools")
            try await activate { $0.label.hasPrefix("표시 형식") }
            await pump(1.5)
            capture("excel-tool-format")
        }

        await attempt("excel-tool-font") {
            // excel-tool-font (+ color-picker)
            try await openExcel(url)
            try await selectExcelCell("B3")
            try await activate(label: "셀 도구")
            _ = await waitFor(timeout: 4) { $0.label.hasPrefix("글꼴·색·테두리") }
            try await activate { $0.label.hasPrefix("글꼴·색·테두리") }
            _ = await waitFor(timeout: 4) { $0.label == "닫기" }
            await pump(1.0)
            capture("excel-tool-font")
            await openColorPicker()
            capture("color-picker-excel")
        }

        await attempt("excel-tool-sortfilter") {
            // excel-tool-sortfilter
            try await openExcel(url)
            try await selectExcelCell("B3")
            try await activate(label: "셀 도구")
            _ = await waitFor(timeout: 4) { $0.label.hasPrefix("정렬·필터·찾기") }
            try await activate { $0.label.hasPrefix("정렬·필터·찾기") }
            _ = await waitFor(timeout: 4) { $0.label == "닫기" }
            await pump(1.0)
            capture("excel-tool-sortfilter")
        }

        await attempt("excel-sheetmanager") {
            // excel-sheetmanager
            try await openExcel(url)
            try await selectExcelCell("B3")
            try await activate(label: "시트 관리")
            _ = await waitFor(timeout: 4) { $0.label == "닫기" }
            await pump(1.0)
            capture("excel-sheetmanager")
        }

        await attempt("excel-ai:") {
            // excel-ai: type a question and send. Firebase is not configured in tests,
            // so the reply is the app's own offline notice (no network request).
            try await openExcel(url)
            try await selectExcelCell("B3")
            capture("excel-ai-empty")
            if let input = findTextInput(accessibilityLabelContaining: "AI에게") {
                input.becomeFirstResponder()
                (input as? UITextInput)?.insertText("급여 합계를 알려줘")
                await pump(0.5)
                input.resignFirstResponder()
                await pump(0.5)
                try? await activate { $0.isButton && ($0.label.contains("보내기") || $0.label.contains("전송")) }
                await pump(3)
            } else {
                log("excel-ai: composer text input not found")
            }
            capture("excel-ai")
        }
    }

    func testExcelDrawing() async throws {
        let url = try copyFixture("ToolXkit_Sample", "xlsx")
        // The fixture has no drawing; add one column chart with the app's own view model first.
        let model = ExcelWorkbookViewModel(fileURL: url)
        await model.load()
        model.selectSheet(2)
        let added = model.addSheetChart(title: "부서별 인원", kind: .column, sourceReference: "A1:B5")
        log("chart added: \(added) status=\(model.status)")
        _ = await model.flushAutosave()
        try await openExcel(url)
        await pump(1)
        try await activate(label: "Summary 시트")
        await pump(1)
        dumpAX("excel-drawing-before")
        try await activate { $0.label == "부서별 인원" && $0.isButton }
        await pump(1.2)
        capture("excel-drawing-selected")
    }

    // MARK: - HWP

    func testHWP() async throws {
        let url = try await prepareHWPFixture()
        let pristine = try copyFixture("mss_voucher", "hwpx")

        await attempt("original") {
            try await openHWP(pristine)
            capture("hwp-original")
            dumpTree("hwp-original")
        }

        await attempt("Inline") {
            // Inline editing + ribbon tabs
            try await beginInlineEditing()
            capture("hwp-inline-editing")
            for (tab, state) in [("글자", "hwp-ribbon-char"), ("문단", "hwp-ribbon-para"),
                                 ("삽입", "hwp-ribbon-insert"), ("쪽", "hwp-ribbon-page")] {
                try await activate { $0.label == tab && $0.isButton && $0.frame.minY < 80 }
                await pump(1.0)
                capture(state)
            }
            try await activate(label: "글자")
            try await activate { $0.identifier == "hwp-format-color" }
            await pump(1.2)
            capture("color-picker")
        }

        await attempt("찾기") {
            // 찾기
            try await openHWP(pristine)
            try await activate { $0.label == "찾기" && $0.isButton && $0.frame.minY < 80 }
            await pump(1.0)
            if let field = findTextInput(accessibilityLabelContaining: "찾") ?? findFirstTextField() {
                field.becomeFirstResponder()
                (field as? UITextInput)?.insertText("바우처")
                await pump(0.4)
                field.resignFirstResponder()
            }
            await pump(1.2)
            capture("hwp-find")
        }

        await attempt("간편") {
            // 간편
            try await openHWP(pristine)
            setSegment("간편")
            await pump(1.5)
            capture("hwp-simple")
        }

        await attempt("더보기") {
            // 더보기
            try await openHWP(pristine)
            try await activate(label: "더보기")
            _ = await waitFor(timeout: 3) { $0.label.hasPrefix("PDF로 저장") }
            await pump(0.8)
            capture("hwp-more")
        }

        await attempt("출력") {
            // 출력 미리보기 (PDF로 저장 opens the same preview without the system print dialog)
            try await activate { $0.label.hasPrefix("PDF로 저장") }
            _ = await waitFor(timeout: 40) { $0.identifier == "hwp-pdf-page-count" }
            await pump(1.5)
            capture("hwp-print-preview")
        }

        await attempt("Picture") {
            // Picture selection and image sheet
            try await openHWP(pristine)
            if try await selectCanvasObject(image: true) {
                capture("hwp-object-selected")
                try await activate { $0.identifier == "hwp-ribbon-image-properties" }
                await pump(1.2)
                capture("hwp-image-sheet")
            }
        }

        await attempt("Shape") {
            // Shape selection and shape sheet
            try await openHWP(url)
            if try await selectCanvasObject(image: false) {
                capture("hwp-shape-selected")
                try await activate { $0.identifier == "hwp-ribbon-shape-properties" }
                await pump(1.2)
                capture("hwp-shape-sheet")
            }
        }
    }

    private func attempt(_ name: String, _ body: () async throws -> Void) async {
        do { try await body() } catch { log("segment \(name) failed: \(error.localizedDescription)") }
    }

    // MARK: - Excel helpers

    private func openExcel(_ url: URL) async throws {
        await show(ExcelWorkbookView(fileURL: url))
        guard await waitFor(timeout: 20, { $0.label == "셀 도구" }) != nil else {
            dumpAX("excel-open-failed")
            throw failure("Excel did not finish loading")
        }
        await pump(0.8)
        // The grid is a nested hosting view with a stale accessibility tree until its
        // content changes; switching sheets away and back rebuilds it.
        if await waitFor(timeout: 2, { $0.label.hasSuffix(" A2 셀") }) == nil {
            try await activate(label: "Invoice 시트")
            try await activate(label: "Employees 시트")
            await pump(0.8)
        }
    }

    private func selectExcelCell(_ reference: String) async throws {
        try await activate { $0.label.hasSuffix(" \(reference) 셀") || $0.label.hasPrefix("\(reference) 셀") }
        await pump(0.8)
    }

    private func openColorPicker() async {
        guard let window else { return }
        if let well = allViews(in: window).compactMap({ $0 as? UIColorWell }).first {
            let center = well.convert(CGPoint(x: well.bounds.midX, y: well.bounds.midY), to: window)
            await synthesizeTap(at: center)
            await pump(1.5)
            if topViewController() is UIColorPickerViewController { log("color picker opened from UIColorWell"); return }
        }
        log("color picker: presenting UIColorPickerViewController directly (UIColorWell did not open)")
        let picker = UIColorPickerViewController()
        picker.title = "글자색"
        picker.supportsAlpha = false
        picker.selectedColor = .black
        topViewController()?.present(picker, animated: false)
        await pump(1.5)
    }

    // MARK: - HWP helpers

    private func prepareHWPFixture() async throws -> URL {
        var chosen: URL?
        for (name, ext) in [("hangul_design_application", "hwp"), ("mss_voucher", "hwpx"), ("V25-group", "hwp")] {
            let url = try copyFixture(name, ext)
            let model = HWPDocumentViewModel(fileURL: url)
            await model.load()
            let objects = model.blocks.flatMap(\.canvasObjects)
            let images = objects.filter { if case .image = $0.content { return true }; return false }.count
            let shapes = objects.filter {
                switch $0.content { case .shape, .group: return true; default: return false }
            }.count
            log("HWP probe \(name).\(ext): blocks=\(model.blocks.count) pages=\(model.pageLayouts.count) images=\(images) shapes=\(shapes) error=\(model.errorDescription ?? "-")")
            if chosen == nil, images > 0, shapes > 0 { chosen = url }
        }
        if let chosen { log("HWP fixture: \(chosen.lastPathComponent) (has picture and shape)"); return chosen }

        // No candidate has both: use mss_voucher.hwpx and insert one rectangle with the app's view model.
        let url = try copyFixture("mss_voucher", "hwpx")
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        // Same as the Android capture: end of the first editable body paragraph.
        let target = model.blocks.first { $0.region.kind == .body && $0.tableLocation == nil
            && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let target,
              let selection = HWPShapeEditing.selection(blocks: model.blocks, selectedID: target.id,
                range: NSRange(location: (target.text as NSString).length, length: 0), layouts: model.pageLayouts) else {
            log("HWP: shape insertion selection unavailable")
            return url
        }
        do {
            _ = try await model.insertShape(.init(selection: selection, kind: .rectangle,
                widthPoints: 140, heightPoints: 60))
            await model.save()
            log("HWP fixture: mss_voucher.hwpx + inserted rectangle after '\(target.text.prefix(20))' error=\(model.errorDescription ?? "-")")
        } catch {
            log("HWP shape insertion failed: \(error)")
        }
        return url
    }

    private func openHWP(_ source: URL) async throws {
        let folder = workDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: url)
        await show(HWPDocumentView(fileURL: url))
        guard await waitFor(timeout: 30, { $0.label.contains("개 문단") }) != nil else {
            dumpAX("hwp-open-failed"); capture("_hwp-open-failed-\(logLines.count)")
            throw failure("HWP did not finish loading")
        }
        await pump(1.0)
        // The canvas lives in a nested hosting view whose accessibility tree can be stale;
        // switching view mode rebuilds it (same document, same scroll position at the top).
        if await waitFor(timeout: 3, { $0.identifier.hasPrefix("hwp-inline-target-") }) == nil {
            setSegment("간편"); await pump(1.0)
            setSegment("원본"); await pump(1.5)
            if await waitFor(timeout: 8, { $0.identifier.hasPrefix("hwp-inline-target-") }) == nil {
                log("HWP inline targets still missing after view-mode toggle")
            }
        }
        await pump(0.5)
    }

    private func beginInlineEditing() async throws {
        let targets = elements().filter {
            $0.identifier.hasPrefix("hwp-inline-target-") && $0.label.hasPrefix("< 혁신바우처 유형 및 서비스")
        }
        log("inline targets: \(targets.prefix(5).map { "\($0.label.prefix(15))@\(Int($0.frame.minY))" })")
        guard let target = targets.first else { throw failure("No paragraph target") }
        _ = target.object.accessibilityActivate()
        await pump(1.5)
        hideKeyboardInputView()
        await pump(1.0)
    }

    /// Keeps the caret and selection but removes the software keyboard, which lives
    /// in another process and cannot be captured by `drawHierarchy`.
    private func hideKeyboardInputView() {
        guard let window, let responder = allViews(in: window).first(where: { $0.isFirstResponder }) else {
            log("no first responder after inline activation")
            return
        }
        log("first responder: \(type(of: responder))")
        if let textView = responder as? UITextView {
            textView.inputView = UIView(frame: .zero)
            textView.inputAssistantItem.leadingBarButtonGroups = []
            textView.inputAssistantItem.trailingBarButtonGroups = []
            textView.reloadInputViews()
        }
    }

    private func selectCanvasObject(image: Bool) async throws -> Bool {
        let objects = elements().filter { $0.identifier.hasPrefix("hwp-canvas-object-") }
        log("canvas objects: \(objects.map { "\($0.identifier) '\($0.label.prefix(12))' @\(Int($0.frame.minY))" })")
        let marker = image ? "hwp-ribbon-image-properties" : "hwp-ribbon-shape-properties"
        let ordered = objects.filter { image ? $0.label.hasPrefix("그림") : !$0.label.hasPrefix("그림") }
        for candidate in ordered {
            if !candidate.object.accessibilityActivate() {
                // The canvas uses a SpatialTapGesture, which has no accessibility default action.
                log("activate returned false for \(candidate.identifier); synthesizing a tap")
                await synthesizeTap(at: CGPoint(x: candidate.frame.midX, y: candidate.frame.midY))
            }
            await pump(1.0)
            if elements().contains(where: { $0.identifier == marker }) {
                await pump(0.5)
                return true
            }
        }
        dumpAX(image ? "hwp-image-select-failed" : "hwp-shape-select-failed")
        return false
    }

    // MARK: - Touch synthesis (test-only, private UIKit/IOKit API as used by KIF)

    private func synthesizeTap(at point: CGPoint) async {
        guard let window, let hitView = window.hitTest(point, with: nil),
              let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let createHandSymbol = dlsym(iokit, "IOHIDEventCreateDigitizerEvent"),
              let createFingerSymbol = dlsym(iokit, "IOHIDEventCreateDigitizerFingerEventWithQuality"),
              let setIntSymbol = dlsym(iokit, "IOHIDEventSetIntegerValueWithOptions"),
              let appendSymbol = dlsym(iokit, "IOHIDEventAppendEvent") else {
            log("touch synthesis unavailable"); return
        }
        typealias CreateHand = @convention(c) (CFAllocator?, UInt64, UInt32, UInt32, UInt32, UInt32, UInt32,
            Double, Double, Double, Double, Double, Bool, Bool, UInt32) -> UnsafeMutableRawPointer?
        typealias CreateFinger = @convention(c) (CFAllocator?, UInt64, UInt32, UInt32, UInt32,
            Double, Double, Double, Double, Double, Double, Double, Double, Double, Double, Bool, Bool, UInt32) -> UnsafeMutableRawPointer?
        typealias SetInt = @convention(c) (UnsafeMutableRawPointer?, UInt32, Int, UInt32) -> Void
        typealias Append = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UInt32) -> Void
        let createHand = unsafeBitCast(createHandSymbol, to: CreateHand.self)
        let createFinger = unsafeBitCast(createFingerSymbol, to: CreateFinger.self)
        let setInt = unsafeBitCast(setIntSymbol, to: SetInt.self)
        let append = unsafeBitCast(appendSymbol, to: Append.self)
        let displayIntegrated: UInt32 = 0xB0019
        func hidEvent(touching: Bool) -> UnsafeMutableRawPointer? {
            let time = mach_absolute_time()
            let hand = createHand(kCFAllocatorDefault, time, 3, 0, 0, 2, 0, 0, 0, 0, 0, 0, false, false, 0)
            setInt(hand, displayIntegrated, 1, 0xF000_0000)
            if let senderSymbol = dlsym(iokit, "IOHIDEventSetSenderID") {
                typealias SetSender = @convention(c) (UnsafeMutableRawPointer?, UInt64) -> Void
                unsafeBitCast(senderSymbol, to: SetSender.self)(hand, 0x0000_0001_2345_6789)
            }
            let mask: UInt32 = 0x1 | 0x2 // range | touch
            let finger = createFinger(kCFAllocatorDefault, time, 1, 2, mask, Double(point.x), Double(point.y),
                0, 0, 0, 5, 5, 1, 1, 1, touching, touching, 0)
            setInt(finger, displayIntegrated, 1, 0xF000_0000)
            append(hand, finger, 0)
            return hand
        }
        func send(_ object: NSObject, _ selector: String, _ value: AnyObject?) {
            let sel = NSSelectorFromString(selector)
            guard object.responds(to: sel) else { log("missing \(selector)"); return }
            typealias F = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
            unsafeBitCast(object.method(for: sel), to: F.self)(object, sel, value)
        }
        func sendInt(_ object: NSObject, _ selector: String, _ value: Int) {
            let sel = NSSelectorFromString(selector)
            guard object.responds(to: sel) else { log("missing \(selector)"); return }
            typealias F = @convention(c) (AnyObject, Selector, Int) -> Void
            unsafeBitCast(object.method(for: sel), to: F.self)(object, sel, value)
        }
        func sendBool(_ object: NSObject, _ selector: String, _ value: Bool) {
            let sel = NSSelectorFromString(selector)
            guard object.responds(to: sel) else { log("missing \(selector)"); return }
            typealias F = @convention(c) (AnyObject, Selector, Bool) -> Void
            unsafeBitCast(object.method(for: sel), to: F.self)(object, sel, value)
        }
        func sendPointer(_ object: NSObject, _ selector: String, _ value: UnsafeMutableRawPointer?) {
            let sel = NSSelectorFromString(selector)
            guard object.responds(to: sel) else { log("missing \(selector)"); return }
            typealias F = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> Void
            unsafeBitCast(object.method(for: sel), to: F.self)(object, sel, value)
        }
        let touch = UITouch()
        send(touch, "setWindow:", window)
        send(touch, "setView:", hitView)
        sendInt(touch, "setTapCount:", 1)
        do {
            let sel = NSSelectorFromString("_setLocationInWindow:resetPrevious:")
            typealias F = @convention(c) (AnyObject, Selector, CGPoint, Bool) -> Void
            unsafeBitCast(touch.method(for: sel), to: F.self)(touch, sel, point, true)
        }
        sendBool(touch, "_setIsFirstTouchForView:", true)
        sendInt(touch, "_setPathIndex:", 1)
        sendInt(touch, "_setPathIdentity:", 2)
        let app = UIApplication.shared
        func deliver(phase: UITouch.Phase) {
            sendInt(touch, "setPhase:", phase.rawValue)
            do {
                let sel = NSSelectorFromString("setTimestamp:")
                typealias F = @convention(c) (AnyObject, Selector, Double) -> Void
                unsafeBitCast(touch.method(for: sel), to: F.self)(touch, sel, ProcessInfo.processInfo.systemUptime)
            }
            let hid = hidEvent(touching: phase != .ended)
            sendPointer(touch, "_setHidEvent:", hid)
            guard let event = app.perform(NSSelectorFromString("_touchesEvent"))?.takeUnretainedValue() as? UIEvent else {
                log("no _touchesEvent"); return
            }
            _ = event.perform(NSSelectorFromString("_clearTouches"))
            sendPointer(event, "_setHIDEvent:", hid)
            do {
                let sel = NSSelectorFromString("_addTouch:forDelayedDelivery:")
                typealias F = @convention(c) (AnyObject, Selector, AnyObject, Bool) -> Void
                unsafeBitCast(event.method(for: sel), to: F.self)(event, sel, touch, false)
            }
            if phase == .began {
                // SwiftUI gestures live in gesture-recognizer containers found by UIKit's
                // own hit test, not on view.gestureRecognizers; attach them like UIKit does.
                var container: AnyObject? = hitView
                if let contextClass = NSClassFromString("_UIHitTestContext") as? NSObject.Type {
                    let makeSel = NSSelectorFromString("contextWithPoint:radius:event:")
                    typealias M = @convention(c) (AnyObject, Selector, CGPoint, CGFloat, AnyObject?) -> AnyObject?
                    let hitSel = NSSelectorFromString("_hitTestWithContext:")
                    typealias H = @convention(c) (AnyObject, Selector, AnyObject?) -> AnyObject?
                    var view: UIView? = hitView
                    while let current = view {
                        let local = window.convert(point, to: current)
                        let context = unsafeBitCast(contextClass.method(for: makeSel), to: M.self)(contextClass, makeSel, local, 0, event)
                        let found = unsafeBitCast(current.method(for: hitSel), to: H.self)(current, hitSel, context)
                        if let found, !(found is UIView) { container = found; break }
                        view = current.superview
                    }
                }
                let addSel = NSSelectorFromString("_addGestureRecognizersFromContainer:toTouch:")
                if event.responds(to: addSel), let container {
                    typealias A = @convention(c) (AnyObject, Selector, AnyObject, AnyObject) -> Void
                    unsafeBitCast(event.method(for: addSel), to: A.self)(event, addSel, container, touch)
                }
            }
            app.sendEvent(event)
        }
        deliver(phase: .began)
        await pump(0.08)
        deliver(phase: .ended)
        log("synthesized tap at \(point) on \(type(of: hitView))")
    }

    // MARK: - Hosting

    final class PathHolder: ObservableObject { @Published var path = NavigationPath() }
    struct PushedRoot<Content: View>: View {
        @ObservedObject var holder: PathHolder
        let content: () -> Content
        var body: some View {
            NavigationStack(path: $holder.path) {
                Color.white.navigationDestination(for: Int.self) { _ in content() }
            }
        }
    }

    private func showRoot<V: View>(_ root: V) async {
        closeWindow()
        guard let scene = windowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: portraitSize(scene))
        window.windowLevel = .normal + 5
        window.overrideUserInterfaceStyle = .light
        let host = UIHostingController(rootView: root
            .environmentObject(AppRouter())
            .environmentObject(AppSettingsStore.shared)
            .environment(\.locale, Locale(identifier: "ko_KR"))
            .environment(\.dynamicTypeSize, .large))
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        await pump(1.2)
    }

    private func show<V: View>(_ content: V) async {
        closeWindow()
        guard let scene = windowScene else { return }
        let size = portraitSize(scene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.windowLevel = .normal + 5
        window.overrideUserInterfaceStyle = .light
        window.traitOverrides.preferredContentSizeCategory = .large
        let fonts = AppFontCatalogStore.shared
        // Same as the app: every document screen is a pushed navigation destination
        // with the route back button (HomeView is the stack root).
        let root = NavigationStack(path: .constant(NavigationPath([1]))) {
            Color.clear.navigationDestination(for: Int.self) { _ in
                content.visionCraftRouteBackButton()
            }
        }
            .environmentObject(AppRouter())
            .environmentObject(AppSettingsStore.shared)
            .environment(\.font, fonts.font(languageCode: "ko"))
            .environment(\.visionCraftAppFontName, fonts.fontName(languageCode: "ko"))
            .environment(\.locale, Locale(identifier: "ko_KR"))
            .environment(\.dynamicTypeSize, .large)
        let host = UIHostingController(rootView: root)
        host.traitOverrides.preferredContentSizeCategory = .large
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        await pump(1.2)
    }

    private func closeWindow() {
        guard let window else { return }
        window.rootViewController?.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
        self.window = nil
    }

    private var windowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    private func portraitSize(_ scene: UIWindowScene) -> CGSize {
        let bounds = scene.coordinateSpace.bounds.size
        return CGSize(width: min(bounds.width, bounds.height), height: max(bounds.width, bounds.height))
    }

    private func ensurePortrait() async {
        guard let scene = windowScene else { return }
        log("device content size category=\(UIApplication.shared.preferredContentSizeCategory.rawValue)")
        log("scene orientation=\(scene.interfaceOrientation.rawValue) bounds=\(scene.coordinateSpace.bounds) scale=\(scene.screen.scale)")
        guard scene.interfaceOrientation.isLandscape else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
            Task { @MainActor in self.log("geometry update error: \(error)") }
        }
        await pump(2)
        log("after rotate orientation=\(scene.interfaceOrientation.rawValue) bounds=\(scene.coordinateSpace.bounds)")
    }

    private func pump(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func topViewController() -> UIViewController? {
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }

    // MARK: - Capture

    private func capture(_ state: String) {
        guard let window else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
            UIColor.white.setFill()
            context.fill(window.bounds)
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            for other in windowScene?.windows ?? [] where other !== window && !other.isHidden
                && other.windowLevel > window.windowLevel
                && !String(describing: type(of: other)).contains("Keyboard") {
                other.drawHierarchy(in: other.frame, afterScreenUpdates: false)
            }
        }
        let url = outputDirectory.appendingPathComponent("\(state).png")
        try? image.pngData()?.write(to: url)
        log("captured \(state) \(Int(image.size.width))x\(Int(image.size.height))@\(image.scale) top=\(topViewController().map { String(describing: type(of: $0)) } ?? "-")")
        dumpAX(state)
    }

    // MARK: - Accessibility

    private struct Element {
        let object: NSObject
        let label: String
        let identifier: String
        let frame: CGRect
        let traits: UIAccessibilityTraits
        var isButton: Bool { traits.contains(.button) }
    }

    private func elements() -> [Element] {
        guard let window else { return [] }
        var found: [NSObject] = []
        var visited = Set<ObjectIdentifier>()
        collect(window, depth: 0, into: &found, visited: &visited)
        return found.map { object in
            let identifier = object.responds(to: NSSelectorFromString("accessibilityIdentifier"))
                ? (object.value(forKey: "accessibilityIdentifier") as? String ?? "") : ""
            return Element(object: object, label: object.accessibilityLabel ?? "",
                identifier: identifier, frame: object.accessibilityFrame,
                traits: object.accessibilityTraits)
        }
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

    private func waitFor(timeout: Double, _ predicate: (Element) -> Bool) async -> Element? {
        let deadline = Date().addingTimeInterval(timeout)
        var attempts = 0
        repeat {
            if let match = elements().first(where: predicate) { return match }
            attempts += 1
            if attempts % 6 == 0 { await refreshAccessibility() } else { await pump(0.25) }
        } while Date() < deadline
        return nil
    }

    private func activate(label: String) async throws {
        try await activate { $0.label == label }
    }

    private func activate(_ predicate: (Element) -> Bool) async throws {
        guard let element = await waitFor(timeout: 5, predicate) else {
            dumpAX("activate-failed-\(logLines.count)")
            throw failure("Element not found")
        }
        if !element.object.accessibilityActivate() {
            log("activate returned false: '\(element.label.prefix(20))' \(element.identifier); tapping")
            await synthesizeTap(at: CGPoint(x: element.frame.midX, y: element.frame.midY))
        }
        await pump(1.0)
    }

    private func setSegment(_ title: String) {
        guard let window else { return }
        for control in allViews(in: window).compactMap({ $0 as? UISegmentedControl }) {
            for index in 0..<control.numberOfSegments where control.titleForSegment(at: index) == title {
                control.selectedSegmentIndex = index
                control.sendActions(for: .valueChanged)
                return
            }
        }
        log("segment '\(title)' not found")
    }

    private func allViews(in root: UIView) -> [UIView] {
        [root] + root.subviews.flatMap { allViews(in: $0) }
    }

    private func findTextInput(accessibilityLabelContaining text: String) -> UIView? {
        guard let window else { return nil }
        return allViews(in: window).first { view in
            (view is UITextView || view is UITextField) && !view.isHidden
                && ((view.accessibilityLabel ?? "").contains(text)
                    || ((view as? UITextField)?.placeholder ?? "").contains(text))
        }
    }

    private func findFirstTextField() -> UIView? {
        guard let window else { return nil }
        return allViews(in: window).first { $0 is UITextField && !$0.isHidden }
    }

    private func dumpTree(_ name: String) {
        guard let window else { return }
        var lines: [String] = []
        var visited = Set<ObjectIdentifier>()
        func walk(_ object: NSObject, _ depth: Int) {
            guard depth < 120, visited.insert(ObjectIdentifier(object)).inserted else { return }
            let pad = String(repeating: " ", count: depth)
            let hidden = (object as? UIView).map { $0.isHidden || $0.alpha < 0.01 } ?? false
            lines.append("\(pad)\(type(of: object)) el=\(object.isAccessibilityElement) hidden=\(hidden) axHidden=\(object.accessibilityElementsHidden) label='\((object.accessibilityLabel ?? "").prefix(30))' frame=\(object.accessibilityFrame.integral)")
            var children: [NSObject] = []
            if let list = object.accessibilityElements { children = list.compactMap { $0 as? NSObject }; lines.append("\(pad) [axElements \(children.count)]") }
            else {
                let count = object.accessibilityElementCount()
                if count != NSNotFound, count > 0, count < 50_000 {
                    lines.append("\(pad) [axCount \(count)]")
                    for index in 0..<count { if let child = object.accessibilityElement(at: index) as? NSObject { children.append(child) } }
                }
            }
            if let view = object as? UIView { children.append(contentsOf: view.subviews) }
            for child in children { walk(child, depth + 1) }
        }
        walk(window, 0)
        try? lines.joined(separator: "\n").write(to: outputDirectory.appendingPathComponent("_ax/tree-\(name).txt"),
            atomically: true, encoding: .utf8)
    }

    private func dumpAX(_ name: String) {
        let lines = elements().map { element in
            "\(element.isButton ? "[B]" : "   ") \(element.label.replacingOccurrences(of: "\n", with: " ").prefix(80)) | \(element.identifier) | \(Int(element.frame.minX)),\(Int(element.frame.minY)) \(Int(element.frame.width))x\(Int(element.frame.height))"
        }
        try? lines.joined(separator: "\n").write(to: outputDirectory.appendingPathComponent("_ax/\(name).txt"),
            atomically: true, encoding: .utf8)
    }

    // MARK: - Files and logging

    private func copyFixture(_ name: String, _ ext: String) throws -> URL {
        let bundle = Bundle(for: Self.self)
        let source = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: ext)
                ?? ["UICompareFixtures", "HWPXViewerFixtures", "InternetWorkbookFixtures"].lazy
                    .compactMap { bundle.url(forResource: name, withExtension: ext, subdirectory: $0) }.first,
            "Missing fixture \(name).\(ext)")
        let folder = workDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("테스트 문서", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent("\(name).\(ext)")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private func log(_ line: String) {
        logLines.append(line)
        print("[UICompare] \(line)")
    }

    private func flushLog() {
        guard let outputDirectory else { return }
        let url = outputDirectory.appendingPathComponent("_log-\(name.filter { $0.isLetter || $0.isNumber }).txt")
        try? logLines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func failure(_ message: String) -> Error {
        log("FAIL: \(message)")
        return NSError(domain: "UICompare", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
