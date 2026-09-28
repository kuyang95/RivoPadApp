import XCTest

final class InlineQAUITests: XCTestCase {
    @MainActor func testPDFPreviewSaveDialogPrintDialogAndPendingTextPreserved() throws {
        let app = XCUIApplication(); app.launchArguments = ["--page-fixture"]; app.launch()
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '쪽 설정 문단'")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10)); target.tap()
        let input = app.textViews["hwp-inline-editor"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.typeText("PDF 저장 전 24680")
        app.buttons["qa-export-pdf"].tap()
        XCTAssertTrue(app.otherElements["hwp-pdf-preview"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.staticTexts["hwp-pdf-page-count"].label, "1 / 1쪽")
        let preview = XCTAttachment(screenshot: app.screenshot()); preview.name = "pdf-output-preview"; preview.lifetime = .keepAlways; add(preview)
        app.buttons["hwp-pdf-save"].tap()
        XCTAssertTrue(app.buttons["저장"].waitForExistence(timeout: 10))
        let save = XCTAttachment(screenshot: app.screenshot()); save.name = "pdf-save-dialog"; save.lifetime = .keepAlways; add(save)
        app.buttons["저장"].tap()
        if app.buttons["대치"].waitForExistence(timeout: 2) { app.buttons["대치"].tap() }
        expectation(for: NSPredicate(format: "label == %@", "PDF를 저장했습니다."), evaluatedWith: app.staticTexts["hwp-pdf-status"])
        waitForExpectations(timeout: 15)
        func closePrint() {
            let nativeClose = app.buttons.matching(NSPredicate(format: "label IN {'취소', '닫기', 'Cancel', 'Close'}"))
            let found = NSPredicate { _, _ in nativeClose.allElementsBoundByIndex.contains { $0.isHittable && $0.isEnabled } }
            expectation(for: found, evaluatedWith: app); waitForExpectations(timeout: 15)
            nativeClose.allElementsBoundByIndex.first { $0.isHittable && $0.isEnabled }?.tap()
        }
        app.buttons["hwp-pdf-print"].tap()
        XCTAssertTrue(app.buttons["hwp-pdf-print"].waitForExistence(timeout: 10))
        let print = XCTAttachment(screenshot: app.screenshot()); print.name = "pdf-print-dialog"; print.lifetime = .keepAlways; add(print)
        closePrint()
        XCTAssertTrue(app.buttons["hwp-pdf-close"].isEnabled); app.buttons["hwp-pdf-close"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label CONTAINS '24680'")).firstMatch.exists)
        app.buttons["저장 확인"].tap(); XCTAssertEqual(app.staticTexts["qa-result"].label, "저장·재열기 성공")
        app.buttons["qa-print-pdf"].tap()
        closePrint()
        XCTAssertTrue(app.buttons["hwp-pdf-close"].waitForExistence(timeout: 5)); app.buttons["hwp-pdf-close"].tap()
    }

    @MainActor func testHeaderFooterCancelAlignmentUndoBodyInputClearAndSave() throws {
        let app = XCUIApplication(); app.launchArguments = ["--page-fixture"]; app.launch()
        let menu = app.buttons["hwp-page-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        func open(_ kind: String) {
            menu.tap(); app.buttons["hwp-page-" + kind].tap()
            XCTAssertTrue(app.textViews["hwp-region-text-0"].waitForExistence(timeout: 5))
        }
        func expectRegion(_ kind: String, _ text: String) {
            let node = app.descendants(matching: .any)["hwp-region-\(kind)-hwp-canvas-page-0-0-0"].firstMatch
            expectation(for: NSPredicate(format: "label == %@", text), evaluatedWith: node); waitForExpectations(timeout: 15)
        }
        open("header"); app.textViews["hwp-region-text-0"].tap(); app.textViews["hwp-region-text-0"].typeText("취소할 내용")
        app.buttons["hwp-region-cancel"].tap()
        open("header"); XCTAssertEqual(app.textViews["hwp-region-text-0"].value as? String, "")
        app.textViews["hwp-region-text-0"].tap(); app.textViews["hwp-region-text-0"].typeText("테스트 문서 제목")
        app.buttons["완료"].firstMatch.tap()
        app.buttons["hwp-region-alignment"].tap(); app.buttons["가운데"].tap()
        let sheet = XCTAttachment(screenshot: app.screenshot()); sheet.name = "header-footer-sheet"; sheet.lifetime = .keepAlways; add(sheet)
        app.buttons["hwp-region-apply"].tap(); expectRegion("header", "테스트 문서 제목")
        app.buttons["qa-undo"].tap(); app.buttons["qa-redo"].tap(); expectRegion("header", "테스트 문서 제목")
        open("footer"); app.textViews["hwp-region-text-0"].tap(); app.textViews["hwp-region-text-0"].typeText("VisionCraft")
        app.buttons["hwp-region-apply"].tap(); expectRegion("footer", "VisionCraft")
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '쪽 설정 문단'")).firstMatch
        XCTAssertTrue(target.exists); target.tap()
        let input = app.textViews["hwp-inline-editor"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.typeText("본문 계속 입력")
        open("header"); app.buttons["hwp-region-cancel"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5)); XCTAssertTrue((input.value as? String)?.contains("본문 계속 입력") == true)
        app.buttons["저장 확인"].tap(); XCTAssertEqual(app.staticTexts["qa-result"].label, "저장·재열기 성공")
        let page = XCTAttachment(screenshot: app.screenshot()); page.name = "header-footer-page"; page.lifetime = .keepAlways; add(page)
        open("header"); app.buttons["hwp-region-clear"].tap(); app.buttons["hwp-region-apply"].tap()
        app.buttons["저장 확인"].tap(); XCTAssertEqual(app.staticTexts["qa-result"].label, "저장·재열기 성공")
        open("header"); XCTAssertEqual(app.textViews["hwp-region-text-0"].value as? String, "")
        app.buttons["hwp-region-cancel"].tap(); expectRegion("footer", "VisionCraft")
    }

    @MainActor func testDeleteTableUndoRestoresContentsRedoAndBodyInputSave() throws {
        let app = XCUIApplication(); app.launchArguments = ["--insert-table-fixture"]; app.launch()
        func expect(_ id: String, _ value: String) {
            expectation(for: NSPredicate(format: "label == %@", value), evaluatedWith: app.staticTexts[id]); waitForExpectations(timeout: 15)
        }
        let insert = app.buttons["hwp-table-insert"]
        XCTAssertTrue(insert.waitForExistence(timeout: 10)); insert.tap()
        app.buttons["hwp-insert-table-apply"].tap(); expect("qa-cell-count", "셀 9개")
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.typeText("삭제 복원할 내용\n다음 줄")
        app.buttons["저장 확인"].tap(); expect("qa-result", "저장·재열기 성공")
        let cell = app.buttons["hwp-inline-target-Contents/section0.xml#p-2"]
        cell.tap(); app.buttons["hwp-format-table-structure"].tap()
        let menu = XCTAttachment(screenshot: app.screenshot()); menu.name = "table-delete-menu"; menu.lifetime = .keepAlways; add(menu)
        let delete = app.buttons["hwp-table-deleteTable"]
        XCTAssertTrue(delete.isEnabled); delete.tap(); expect("qa-cell-count", "셀 0개")
        XCTAssertTrue(input.waitForExistence(timeout: 5)); XCTAssertEqual(input.value as? String, "")
        app.buttons["qa-undo"].tap(); expect("qa-cell-count", "셀 9개")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label CONTAINS '삭제 복원할 내용'")).firstMatch.exists)
        app.buttons["qa-redo"].tap(); expect("qa-cell-count", "셀 0개")
        let body = app.buttons["hwp-inline-target-Contents/section0.xml#p-1"]
        XCTAssertTrue(body.exists); body.tap(); input.typeText("삭제 후 본문")
        app.buttons["저장 확인"].tap(); expect("qa-result", "저장·재열기 성공")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label CONTAINS '삭제 후 본문'")).firstMatch.exists)
        let saved = XCTAttachment(screenshot: app.screenshot()); saved.name = "table-deleted-body-save"; saved.lifetime = .keepAlways; add(saved)
    }

    @MainActor func testInsertTableIntoEmptyDocumentCancelUndoInputRowsColumnsAndSave() throws {
        let app = XCUIApplication(); app.launchArguments = ["--insert-table-fixture"]; app.launch()
        let button = app.buttons["hwp-table-insert"]
        XCTAssertTrue(button.waitForExistence(timeout: 10)); XCTAssertTrue(button.isEnabled)
        func open() { button.tap(); XCTAssertTrue(app.textFields["hwp-insert-table-rows"].waitForExistence(timeout: 5)) }
        func expect(_ id: String, _ text: String) {
            expectation(for: NSPredicate(format: "label == %@", text), evaluatedWith: app.staticTexts[id]); waitForExpectations(timeout: 15)
        }
        func enter(_ id: String, _ value: String) {
            app.buttons["hwp-insert-table-\(id)-clear"].tap(); app.textFields["hwp-insert-table-\(id)"].typeText(value)
            app.buttons["hwp-insert-table-keyboard-done"].tap()
        }
        open(); XCTAssertEqual(app.staticTexts["hwp-insert-table-preview"].label, "3행 × 3열")
        app.buttons["hwp-insert-table-cancel"].tap(); expect("qa-cell-count", "셀 0개")
        open(); enter("rows", "0"); XCTAssertFalse(app.buttons["hwp-insert-table-apply"].isEnabled)
        enter("rows", "3"); enter("columns", "2")
        let sheet = XCTAttachment(screenshot: app.screenshot()); sheet.name = "table-insertion-sheet"; sheet.lifetime = .keepAlways; add(sheet)
        app.buttons["hwp-insert-table-apply"].tap(); expect("qa-table-size", "표 3행 2열"); expect("qa-cell-count", "셀 6개")
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); XCTAssertEqual(input.value as? String, "")
        XCTAssertFalse(button.isEnabled)
        app.buttons["qa-undo"].tap(); expect("qa-cell-count", "셀 0개"); expect("qa-paragraph-count", "문단 1")
        app.buttons["qa-redo"].tap(); expect("qa-cell-count", "셀 6개")
        let cell = app.buttons["hwp-inline-target-Contents/section0.xml#p-2"]
        XCTAssertTrue(cell.exists); cell.tap(); XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.typeText("새 표 첫 셀\n다음 줄")
        app.buttons["hwp-format-table-structure"].tap(); app.buttons["hwp-table-rowBelow"].tap()
        expect("qa-table-size", "표 4행 2열")
        app.buttons["hwp-format-table-structure"].tap(); app.buttons["hwp-table-columnAfter"].tap()
        expect("qa-table-size", "표 4행 3열")
        app.buttons["저장 확인"].tap(); expect("qa-result", "저장·재열기 성공")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label CONTAINS '새 표 첫 셀'")).firstMatch.exists)
        let saved = XCTAttachment(screenshot: app.screenshot()); saved.name = "inserted-table-after-edit-save"; saved.lifetime = .keepAlways; add(saved)
    }

    @MainActor func testPageNumberWithoutCaretCancelApplyUndoRedoRemoveAndSave() throws {
        let app = XCUIApplication(); app.launchArguments = ["--page-fixture"]; app.launch()
        let menu = app.buttons["hwp-page-menu"], status = app.staticTexts["qa-number-style"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        func open() {
            menu.tap(); app.buttons["hwp-page-number"].tap()
            XCTAssertTrue(app.switches["hwp-number-show"].waitForExistence(timeout: 5))
        }
        func toggle(_ id: String) {
            let row = app.switches[id]
            let control = row.switches.firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 3)); control.tap()
        }
        func expect(_ value: String) {
            expectation(for: NSPredicate(format: "label == %@", value), evaluatedWith: status)
            waitForExpectations(timeout: 10)
        }
        open(); toggle("hwp-number-show")
        app.buttons["hwp-number-cancel"].tap(); expect("번호 없음")
        open(); toggle("hwp-number-show")
        app.segmentedControls["hwp-number-position"].buttons["위쪽"].tap()
        app.segmentedControls["hwp-number-alignment"].buttons["오른쪽"].tap()
        toggle("hwp-number-decoration"); toggle("hwp-number-restart")
        app.buttons["hwp-number-start-clear"].tap(); app.textFields["hwp-number-start"].typeText("0")
        XCTAssertFalse(app.buttons["hwp-number-apply"].isEnabled)
        app.buttons["hwp-number-start-clear"].tap(); app.textFields["hwp-number-start"].typeText("7")
        app.buttons["hwp-number-keyboard-done"].tap()
        let sheet = XCTAttachment(screenshot: app.screenshot()); sheet.name = "page-number-sheet"; sheet.lifetime = .keepAlways; add(sheet)
        app.buttons["hwp-number-apply"].tap(); expect("TOP_RIGHT - 7")
        let number = app.staticTexts["hwp-page-number-hwp-canvas-page-0-0"]
        XCTAssertEqual(number.label, "- 7 -")
        app.buttons["qa-undo"].tap(); expect("번호 없음")
        app.buttons["qa-redo"].tap(); expect("TOP_RIGHT - 7")
        app.buttons["저장 확인"].tap(); XCTAssertEqual(app.staticTexts["qa-result"].label, "저장·재열기 성공")
        let applied = XCTAttachment(screenshot: app.screenshot()); applied.name = "page-number-applied"; applied.lifetime = .keepAlways; add(applied)
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '쪽 설정 문단'")).firstMatch
        target.tap()
        let input = app.textViews["hwp-inline-editor"]; XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.typeText("번호 테스트")
        open(); app.buttons["hwp-number-cancel"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5)); XCTAssertTrue((input.value as? String)?.contains("번호 테스트") == true)
        open(); app.segmentedControls["hwp-number-alignment"].buttons["왼쪽"].tap()
        app.buttons["hwp-number-apply"].tap(); expect("TOP_LEFT - 7")
        XCTAssertTrue(input.waitForExistence(timeout: 5)); XCTAssertTrue((input.value as? String)?.contains("번호 테스트") == true)
        open(); XCTAssertEqual(app.textFields["hwp-number-start"].value as? String, "7")
        toggle("hwp-number-show"); app.buttons["hwp-number-apply"].tap(); expect("번호 없음")
        app.buttons["저장 확인"].tap(); XCTAssertEqual(app.staticTexts["qa-result"].label, "저장·재열기 성공")
        app.buttons["qa-undo"].tap(); expect("TOP_LEFT - 7")
    }

    @MainActor func testPageBreakMenuInsertRemoveBackspaceUndoRedoAndSave() throws {
        let app = XCUIApplication(); app.launchArguments = ["--page-fixture"]; app.launch()
        let menu = app.buttons["hwp-page-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10)); menu.tap()
        XCTAssertFalse(app.buttons["hwp-page-break-insert"].isEnabled)
        XCTAssertFalse(app.buttons["hwp-page-break-remove"].isEnabled)
        app.buttons["hwp-page-setup"].tap(); app.buttons["hwp-page-cancel"].tap()
        func assertCount(_ name: String, _ value: String) {
            expectation(for: NSPredicate(format: "label == %@", value), evaluatedWith: app.staticTexts[name])
            waitForExpectations(timeout: 5)
        }
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '쪽 설정 문단'")).firstMatch
        XCTAssertTrue(target.exists); target.tap()
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        menu.tap(); XCTAssertTrue(app.buttons["hwp-page-break-insert"].isEnabled)
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "page-break-menu"; capture.lifetime = .keepAlways; add(capture)
        app.buttons["hwp-page-break-insert"].tap()
        assertCount("qa-break-count", "나눔 1개"); assertCount("qa-page-count", "쪽 2개")
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        menu.tap(); XCTAssertTrue(app.buttons["hwp-page-break-remove"].isEnabled)
        app.buttons["hwp-page-break-remove"].tap()
        assertCount("qa-break-count", "나눔 0개"); assertCount("qa-page-count", "쪽 1개")
        app.buttons["qa-undo"].tap(); assertCount("qa-break-count", "나눔 1개")
        app.buttons["qa-redo"].tap(); assertCount("qa-break-count", "나눔 0개")
        // Select the unchanged second paragraph, then test native Backspace at
        // the caret restored to the start of the newly created page.
        let second = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '둘째 본문'")).firstMatch
        XCTAssertTrue(second.exists); second.tap()
        menu.tap(); app.buttons["hwp-page-break-insert"].tap()
        assertCount("qa-break-count", "나눔 1개")
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.typeText(XCUIKeyboardKey.delete.rawValue)
        assertCount("qa-break-count", "나눔 0개"); assertCount("qa-page-count", "쪽 1개")
        menu.tap(); app.buttons["hwp-page-break-insert"].tap()
        assertCount("qa-break-count", "나눔 1개")
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.typeText("입력 유지 ")
        expectation(for: NSPredicate(format: "value CONTAINS %@", "입력 유지"), evaluatedWith: input); waitForExpectations(timeout: 5)
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 10))
        assertCount("qa-page-count", "쪽 2개")
        let saved = XCTAttachment(screenshot: app.screenshot()); saved.name = "page-break-saved"; saved.lifetime = .keepAlways; add(saved)
    }

    @MainActor func testPageSetupWithoutCaretCancelApplyUndoRedoAndSave() throws {
        let app = XCUIApplication(); app.launchArguments = ["--page-fixture"]; app.launch()
        let button = app.buttons["hwp-page-menu"], size = app.staticTexts["qa-page-size"]
        XCTAssertTrue(button.waitForExistence(timeout: 10)); XCTAssertTrue(button.isEnabled)
        XCTAssertFalse(app.textViews["hwp-inline-editor"].exists)
        let originalSize = size.label
        func open() {
            button.tap(); app.buttons["hwp-page-setup"].tap(); XCTAssertTrue(app.textFields["hwp-page-width"].waitForExistence(timeout: 5))
        }
        func paper(_ name: String) {
            app.buttons["hwp-page-paper"].tap(); app.buttons["hwp-page-paper-\(name)"].tap()
        }
        func enter(_ id: String, _ value: String) {
            app.buttons["hwp-page-\(id)-clear"].tap()
            let field = app.textFields["hwp-page-\(id)"]; field.typeText(value)
            XCTAssertEqual(field.value as? String, value)
            app.buttons["hwp-page-keyboard-done"].tap()
        }
        open(); XCTAssertFalse(app.buttons["hwp-page-apply"].isEnabled)
        paper("A5"); app.segmentedControls["hwp-page-orientation"].buttons["가로"].tap()
        app.buttons["hwp-page-margins-10"].tap()
        app.buttons["hwp-page-cancel"].tap(); XCTAssertEqual(size.label, originalSize)
        open(); XCTAssertEqual(app.textFields["hwp-page-width"].value as? String, "210.0")
        enter("width", "0"); XCTAssertFalse(app.buttons["hwp-page-apply"].isEnabled)
        paper("A5"); app.segmentedControls["hwp-page-orientation"].buttons["가로"].tap()
        app.buttons["hwp-page-margins-10"].tap()
        let sheet = XCTAttachment(screenshot: app.screenshot()); sheet.name = "page-setup-sheet"; sheet.lifetime = .keepAlways; add(sheet)
        app.buttons["hwp-page-apply"].tap()
        expectation(for: NSPredicate(format: "label == '210.0 × 148.0 mm'"), evaluatedWith: size); waitForExpectations(timeout: 10)
        app.buttons["qa-undo"].tap(); XCTAssertEqual(size.label, originalSize)
        app.buttons["qa-redo"].tap(); XCTAssertEqual(size.label, "210.0 × 148.0 mm")
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '쪽 설정 문단'")).firstMatch
        XCTAssertTrue(target.exists); target.tap()
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.typeText("추가 ")
        let typed = try XCTUnwrap(input.value as? String)
        open(); enter("left", "12.5")
        app.buttons["hwp-page-apply"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 10)); XCTAssertEqual(input.value as? String, typed)
        input.typeText("!")
        XCTAssertEqual((input.value as? String)?.replacingOccurrences(of: "!", with: ""), typed)
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 5))
        XCTAssertEqual(size.label, "210.0 × 148.0 mm")
        let saved = XCTAttachment(screenshot: app.screenshot()); saved.name = "page-setup-saved-landscape"; saved.lifetime = .keepAlways; add(saved)
    }

    @MainActor func testTableSizeSheetCancelApplyUndoRedoAndSave() throws {
        let app = XCUIApplication(); app.launchArguments = ["--cell-fixture", "--table-structure-fixture"]; app.launch()
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '첫 문단'")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10)); target.tap()
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.typeText("크기 ")
        let typed = try XCTUnwrap(input.value as? String)
        XCTAssertEqual(typed.replacingOccurrences(of: "크기 ", with: ""), "첫 문단")
        func openSize() {
            let button = app.buttons["hwp-format-table-size"]
            XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
            XCTAssertTrue(app.textFields["hwp-table-size-width"].waitForExistence(timeout: 5))
        }
        func enter(_ id: String, _ value: String) {
            let field = app.textFields["hwp-table-size-\(id)"]
            app.buttons["hwp-table-size-\(id)-clear"].tap()
            field.typeText(value)
            XCTAssertEqual(field.value as? String, value)
            app.buttons["hwp-table-size-keyboard-done"].tap()
        }
        openSize()
        XCTAssertFalse(app.buttons["hwp-table-size-apply"].isEnabled)
        XCTAssertEqual(app.textFields["hwp-table-size-width"].value as? String, "42.3")
        let originalHeight = app.textFields["hwp-table-size-height"].value as? String
        enter("width", "28.0")
        app.buttons["hwp-table-size-cancel"].tap()
        openSize()
        XCTAssertEqual(app.textFields["hwp-table-size-width"].value as? String, "42.3")
        enter("width", "0")
        XCTAssertFalse(app.buttons["hwp-table-size-apply"].isEnabled)
        enter("width", "9999")
        XCTAssertFalse(app.buttons["hwp-table-size-apply"].isEnabled)
        enter("width", "28.0"); enter("height", "21.0")
        XCTAssertTrue(app.buttons["hwp-table-size-apply"].isEnabled)
        let sheet = XCTAttachment(screenshot: app.screenshot()); sheet.name = "table-size-sheet"; sheet.lifetime = .keepAlways; add(sheet)
        app.buttons["hwp-table-size-apply"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, typed)
        openSize()
        XCTAssertEqual(app.textFields["hwp-table-size-width"].value as? String, "28.0")
        XCTAssertEqual(app.textFields["hwp-table-size-height"].value as? String, "21.0")
        app.buttons["hwp-table-size-cancel"].tap()
        app.buttons["qa-undo"].tap()
        let retained = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == %@", typed)).firstMatch
        XCTAssertTrue(retained.exists); retained.tap()
        openSize()
        XCTAssertEqual(app.textFields["hwp-table-size-width"].value as? String, "42.3")
        XCTAssertEqual(app.textFields["hwp-table-size-height"].value as? String, originalHeight)
        app.buttons["hwp-table-size-cancel"].tap(); app.buttons["qa-redo"].tap()
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 5))
        XCTAssertTrue(retained.exists)
        let body = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '표 뒤'")).firstMatch
        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '다른 셀'"))
        for index in 0..<cells.count { XCTAssertGreaterThan(body.frame.minY, cells.element(boundBy: index).frame.maxY) }
        let saved = XCTAttachment(screenshot: app.screenshot()); saved.name = "table-size-after-save"; saved.lifetime = .keepAlways; add(saved)
    }

    @MainActor func testCellMergeSplitKeepsContentUndoRedoAndSave() throws {
        let app = XCUIApplication(); app.launchArguments = ["--cell-fixture", "--table-structure-fixture"]; app.launch()
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '첫 문단'")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10)); target.tap()
        func action(_ name: String, count: Int) {
            let menu = app.buttons["hwp-format-cell-structure"]
            XCTAssertTrue(menu.waitForExistence(timeout: 5)); menu.tap()
            let button = app.buttons["hwp-table-\(name)"]
            XCTAssertTrue(button.waitForExistence(timeout: 3)); XCTAssertTrue(button.isEnabled); button.tap()
            expectation(for: NSPredicate(format: "label == %@", "셀 \(count)개"), evaluatedWith: app.staticTexts["qa-cell-count"])
            waitForExpectations(timeout: 15)
        }
        app.buttons["hwp-format-cell-structure"].tap()
        let menu = XCTAttachment(screenshot: app.screenshot()); menu.name = "cell-merge-split-menu"; menu.lifetime = .keepAlways; add(menu)
        app.buttons["hwp-table-mergeRight"].tap()
        expectation(for: NSPredicate(format: "label == '셀 3개'"), evaluatedWith: app.staticTexts["qa-cell-count"])
        waitForExpectations(timeout: 15)
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); XCTAssertEqual(input.value as? String, "첫 문단")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '둘째 문단'")).firstMatch.exists)
        let merged = XCTAttachment(screenshot: app.screenshot()); merged.name = "cell-merged-with-content"; merged.lifetime = .keepAlways; add(merged)
        input.typeText("병합 ")
        action("splitColumns", count: 4)
        XCTAssertEqual(input.value as? String, "병합 첫 문단")
        app.buttons["qa-undo"].tap(); XCTAssertEqual(app.staticTexts["qa-cell-count"].label, "셀 3개")
        app.buttons["qa-redo"].tap(); XCTAssertEqual(app.staticTexts["qa-cell-count"].label, "셀 4개")
        let retained = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '병합 첫 문단'")).firstMatch
        XCTAssertTrue(retained.exists); retained.tap()
        action("mergeBelow", count: 3)
        action("unmerge", count: 4)
        action("splitRows", count: 5)
        app.buttons["완료"].tap(); app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["qa-cell-count"].label, "셀 5개")
        XCTAssertTrue(retained.exists)
        let body = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '표 뒤'")).firstMatch
        let paragraphs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '다른 셀'"))
        XCTAssertTrue(body.exists)
        for index in 0..<paragraphs.count { XCTAssertGreaterThan(body.frame.minY, paragraphs.element(boundBy: index).frame.maxY) }
        let saved = XCTAttachment(screenshot: app.screenshot()); saved.name = "cell-split-after-save"; saved.lifetime = .keepAlways; add(saved)
    }

    @MainActor func testTableRowColumnActionsUndoRedoAndSave() throws {
        let app = XCUIApplication(); app.launchArguments = ["--cell-fixture", "--table-structure-fixture"]; app.launch()
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '첫 문단'")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10)); target.tap()
        func action(_ name: String, size: String) {
            let menu = app.buttons["hwp-format-table-structure"]
            XCTAssertTrue(menu.waitForExistence(timeout: 5)); menu.tap()
            app.buttons["hwp-table-\(name)"].tap()
            let expected = NSPredicate(format: "label == %@", size)
            expectation(for: expected, evaluatedWith: app.staticTexts["qa-table-size"])
            waitForExpectations(timeout: 15)
        }
        action("rowBelow", size: "표 3행 2열")
        let added = XCTAttachment(screenshot: app.screenshot())
        added.name = "table-row-added-caret"; added.lifetime = .keepAlways; add(added)
        action("columnAfter", size: "표 3행 3열")
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); XCTAssertEqual(input.value as? String, "")
        input.typeText("새 셀")
        action("deleteRow", size: "표 2행 3열")
        app.buttons["qa-undo"].tap()
        XCTAssertEqual(app.staticTexts["qa-table-size"].label, "표 3행 3열")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '새 셀'")).firstMatch.exists)
        app.buttons["qa-redo"].tap()
        XCTAssertEqual(app.staticTexts["qa-table-size"].label, "표 2행 3열")
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 5))
        let body = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '표 뒤'")).firstMatch
        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '다른 셀'"))
        XCTAssertTrue(body.exists); XCTAssertGreaterThan(body.frame.minY, cells.element(boundBy: cells.count - 1).frame.maxY)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "table-row-column-after-save"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    @MainActor func testCellFormattingSheetPreviewUndoAndSave() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--cell-fixture"]
        app.launch()
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '첫 문단'")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10)); target.tap()
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        let top = input.frame.minY
        app.buttons["hwp-format-cell"].tap()
        XCTAssertTrue(app.buttons["hwp-cell-apply"].waitForExistence(timeout: 5))
        app.buttons["hwp-cell-fill-14543863"].tap()
        app.segmentedControls["hwp-cell-vertical"].buttons["아래"].tap()
        app.buttons["취소"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.frame.minY, top, accuracy: 2)
        app.buttons["hwp-format-cell"].tap()
        XCTAssertTrue(app.buttons["hwp-cell-apply"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["hwp-cell-vertical"].buttons["위"].isSelected)
        app.buttons["hwp-cell-fill-14543863"].tap()
        app.segmentedControls["hwp-cell-vertical"].buttons["아래"].tap()
        let form = app.collectionViews["hwp-cell-form"]
        let allBorders = app.buttons["hwp-cell-border-all"]
        for _ in 0..<3 where !allBorders.isHittable { form.swipeUp() }
        XCTAssertTrue(allBorders.isHittable); allBorders.tap()
        let sheet = XCTAttachment(screenshot: app.screenshot())
        sheet.name = "cell-format-sheet-preview"; sheet.lifetime = .keepAlways; add(sheet)
        app.buttons["hwp-cell-apply"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        let moved = NSPredicate { _, _ in input.exists && input.frame.minY > top + 20 }
        expectation(for: moved, evaluatedWith: nil); waitForExpectations(timeout: 5)
        XCTAssertEqual(input.value as? String, "첫 문단")
        app.buttons["qa-undo"].tap()
        let restored = NSPredicate { _, _ in input.exists && abs(input.frame.minY - top) < 2 }
        expectation(for: restored, evaluatedWith: nil); waitForExpectations(timeout: 5)
        app.buttons["qa-redo"].tap()
        expectation(for: moved, evaluatedWith: nil); waitForExpectations(timeout: 5)
        let live = XCTAttachment(screenshot: app.screenshot())
        live.name = "cell-format-bottom-aligned-caret"; live.lifetime = .keepAlways; add(live)
        app.buttons["완료"].tap(); app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 5))
        let saved = XCTAttachment(screenshot: app.screenshot())
        saved.name = "cell-format-after-save"; saved.lifetime = .keepAlways; add(saved)
    }

    @MainActor func testCharacterEffectsMenusKeepCaretAndSaveToCanvas() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--character-fixture"]
        app.launch()
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-'")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10)); target.tap()
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        func effect(_ name: String) {
            app.buttons["hwp-format-effects"].tap()
            let button = app.buttons["hwp-format-\(name)"]
            XCTAssertTrue(button.waitForExistence(timeout: 3)); button.tap()
        }
        app.buttons["hwp-format-size"].tap(); app.buttons["24 pt"].tap()
        input.typeText("x")
        effect("superscript"); input.typeText("2"); effect("superscript")
        input.typeText("  H")
        effect("subscript"); input.typeText("2"); effect("subscript")
        input.typeText("O  ")
        effect("strike"); input.typeText("취소선"); effect("strike")
        input.typeText("  ")
        app.buttons["hwp-format-highlight"].tap(); app.buttons["hwp-highlight-16776960"].tap()
        input.typeText("강조")
        app.buttons["hwp-format-highlight"].tap(); app.buttons["hwp-highlight-none"].tap()
        input.typeText("  ")
        app.buttons["hwp-format-bold"].tap()
        effect("clear"); input.typeText("기본")
        XCTAssertEqual(app.buttons["hwp-format-bold"].value as? String, "꺼짐")
        XCTAssertEqual(input.value as? String, "x2  H2O  취소선  강조  기본")
        let editing = XCTAttachment(screenshot: app.screenshot())
        editing.name = "character-effects-native-caret"; editing.lifetime = .keepAlways; add(editing)
        app.buttons["완료"].tap(); app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 5))
        let saved = XCTAttachment(screenshot: app.screenshot())
        saved.name = "character-effects-after-save"; saved.lifetime = .keepAlways; add(saved)
    }

    @MainActor func testListToolbarContinuesOnEnterAndEndsEmptyItemThenSaves() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--list-fixture"]
        app.launch()
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-'")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        target.tap()
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        let bullet = app.buttons["hwp-format-bullet"], number = app.buttons["hwp-format-number"]
        bullet.tap()
        XCTAssertEqual(bullet.value as? String, "켜짐")
        app.buttons["qa-undo"].tap()
        XCTAssertEqual(bullet.value as? String, "꺼짐")
        app.buttons["qa-redo"].tap()
        XCTAssertEqual(bullet.value as? String, "켜짐")
        number.tap()
        XCTAssertEqual(number.value as? String, "켜짐")
        input.typeText("\n")
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["qa-paragraph-count"].label, "문단 2")
        XCTAssertEqual(number.value as? String, "켜짐")
        input.typeText("두 번째 항목")
        let during = XCTAttachment(screenshot: app.screenshot())
        during.name = "numbered-list-native-caret"; during.lifetime = .keepAlways; add(during)
        input.typeText("\n")
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["qa-paragraph-count"].label, "문단 3")
        input.typeText("\n")
        XCTAssertEqual(app.staticTexts["qa-paragraph-count"].label, "문단 3")
        XCTAssertEqual(number.value as? String, "꺼짐")
        input.typeText("일반 문단")
        app.buttons["완료"].tap()
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 5))
        let saved = XCTAttachment(screenshot: app.screenshot())
        saved.name = "numbered-list-after-save"; saved.lifetime = .keepAlways; add(saved)
    }

    @MainActor func testFindReplaceOneAllUndoAndSaveFromTopBar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--find-fixture"]
        app.launch()
        let search = app.buttons["hwp-search-toggle"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        let query = app.textFields["hwp-search-field"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.typeText("찾기")
        XCTAssertTrue(app.staticTexts["hwp-search-count"].label.contains("/ 4"))
        app.buttons["hwp-search-next"].tap()
        XCTAssertTrue(app.staticTexts["hwp-search-count"].label.contains("2 / 4"))
        app.buttons["hwp-replace-toggle"].tap()
        let replacement = app.textFields["hwp-replace-field"]
        replacement.tap(); replacement.typeText("교체")
        app.buttons["hwp-replace-one"].tap()
        XCTAssertEqual(app.staticTexts["hwp-replace-message"].label, "1개를 바꿨습니다.")
        XCTAssertTrue(app.staticTexts["hwp-search-count"].label.contains("/ 3"))
        let match = XCTAttachment(screenshot: app.screenshot())
        match.name = "find-replace-selected-occurrence"; match.lifetime = .keepAlways; add(match)
        app.buttons["hwp-replace-all"].tap()
        XCTAssertEqual(app.staticTexts["hwp-replace-message"].label, "3개를 바꿨습니다.")
        XCTAssertEqual(app.staticTexts["hwp-search-count"].label, "검색 결과가 없습니다.")
        app.buttons["qa-undo"].tap()
        XCTAssertTrue(app.staticTexts["hwp-search-count"].label.contains("/ 3"))
        app.buttons["qa-redo"].tap()
        XCTAssertEqual(app.staticTexts["hwp-search-count"].label, "검색 결과가 없습니다.")
        app.buttons["hwp-search-close"].tap()
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 5))
        let saved = XCTAttachment(screenshot: app.screenshot())
        saved.name = "find-replace-after-save"; saved.lifetime = .keepAlways; add(saved)
    }

    @MainActor func testCellHeightGrowsWhileTypingAndCaretSurvivesPagination() throws {
        let app = XCUIApplication()
        app.launch()
        let target = app.buttons["hwp-inline-target-hwp-section-0-paragraph-18"]
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        let paragraphCount = app.staticTexts["qa-paragraph-count"]
        XCTAssertTrue(paragraphCount.waitForExistence(timeout: 5))
        let initialCount = Int(paragraphCount.label.split(separator: " ").last ?? "0") ?? 0
        target.tap()
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.typeText(String(repeating: "RivoPad line\n", count: 30))
        input.typeText("Caret stays")
        XCTAssertTrue((input.value as? String ?? "").contains("Caret stays"))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "table-row-growth-native-caret"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["완료"].tap()
        let grown = NSPredicate { _, _ in
            guard paragraphCount.exists,
                  let count = Int(paragraphCount.label.split(separator: " ").last ?? "0") else { return false }
            return count > initialCount
        }
        expectation(for: grown, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 5))
        let saved = XCTAttachment(screenshot: app.screenshot())
        saved.name = "table-row-growth-after-save"
        saved.lifetime = .keepAlways
        add(saved)
    }

    @MainActor func testReturnSplitsBodyAndBackspaceMergesAtTheCaret() throws {
        let app = XCUIApplication()
        app.launch()
        let target = app.buttons["hwp-inline-target-hwp-section-0-paragraph-2"]
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        let originalCount = app.staticTexts["qa-paragraph-count"].label
        let original = target.label
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.typeText("\n")
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.staticTexts["qa-paragraph-count"].label, originalCount)
        input.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, original)
        XCTAssertEqual(app.staticTexts["qa-paragraph-count"].label, originalCount)
        input.typeText("\n")
        input.typeText("RivoPad")
        XCTAssertTrue((input.value as? String ?? "").hasPrefix("RivoPad"))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "body-paragraph-split-caret"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["완료"].tap()
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 5))
    }

    @MainActor func testFormattingToolbarKeepsCaretAndSavesStyle() throws {
        let app = XCUIApplication()
        app.launch()
        let target = app.buttons["hwp-inline-target-hwp-section-0-paragraph-18"]
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        target.tap()
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        let bold = app.buttons["hwp-format-bold"]
        bold.tap()
        XCTAssertEqual(bold.value as? String, "켜짐")
        app.buttons["hwp-format-center"].tap()
        XCTAssertEqual(bold.value as? String, "켜짐")
        app.buttons["qa-undo"].tap()
        app.buttons["qa-undo"].tap()
        XCTAssertEqual(bold.value as? String, "꺼짐")
        app.buttons["qa-redo"].tap()
        app.buttons["qa-redo"].tap()
        XCTAssertEqual(bold.value as? String, "켜짐")
        input.typeText("RivoPad")
        XCTAssertEqual(input.value as? String, "RivoPad")
        XCTAssertEqual(bold.value as? String, "켜짐")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "formatting-toolbar-native-cell"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["hwp-format-paragraph"].tap()
        XCTAssertTrue(app.navigationBars["문단"].waitForExistence(timeout: 5))
        let paragraph = XCTAttachment(screenshot: app.screenshot())
        paragraph.name = "formatting-paragraph-settings"
        paragraph.lifetime = .keepAlways
        add(paragraph)
        app.buttons["적용"].tap()
        input.typeText(" 2")
        XCTAssertEqual(input.value as? String, "RivoPad 2")
        app.buttons["완료"].tap()
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 5))
    }

    @MainActor func testTapOriginalProductCellTypeAndSaveWithoutLeavingPage() throws {
        let app = XCUIApplication()
        app.launch()
        let target = app.buttons["hwp-inline-target-hwp-section-0-paragraph-18"]
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        target.tap()
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.typeText("RivoPad")
        XCTAssertEqual(input.value as? String, "RivoPad")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "original-cell-native-caret"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["완료"].tap()
        XCTAssertTrue(target.waitForExistence(timeout: 3))
        XCTAssertEqual(target.label, "RivoPad")
        let savedShot = XCTAttachment(screenshot: app.screenshot())
        savedShot.name = "original-cell-after-input"
        savedShot.lifetime = .keepAlways
        add(savedShot)
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 5))
    }

    @MainActor func testTapInsideBodyTextPlacesCaretInTheMiddle() throws {
        let app = XCUIApplication()
        app.launch()
        let target = app.buttons["hwp-inline-target-hwp-section-0-paragraph-2"]
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        let original = target.label
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.typeText("X")
        let text = try XCTUnwrap(input.value as? String)
        XCTAssertEqual(text.count, original.count + 1)
        XCTAssertNotEqual(text, original + "X")
        XCTAssertFalse(text.hasPrefix("X"))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "original-body-native-caret"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["완료"].tap()
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 5))
    }
}
