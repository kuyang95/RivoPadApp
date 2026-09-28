import XCTest

final class Manual225Batch2UITests: XCTestCase {
    @MainActor
    func testParagraphSpacingSheetAndSave() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--character-fixture"]
        app.launch()
        let target = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-'")
        ).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        target.tap()
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.typeText("문단 간격")
        app.buttons["hwp-format-paragraph"].tap()
        XCTAssertGreaterThanOrEqual(app.steppers.count, 5)
        for _ in 0..<2 {
            app.steppers.element(boundBy: 3).buttons.element(boundBy: 1).tap()
        }
        for _ in 0..<3 {
            app.steppers.element(boundBy: 4).buttons.element(boundBy: 1).tap()
        }
        let lineSpacing = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "줄 간격, 원본 설정")
        ).firstMatch
        XCTAssertTrue(lineSpacing.waitForExistence(timeout: 5))
        lineSpacing.tap()
        app.buttons["180%"].tap()
        app.buttons["적용"].tap()
        expectation(
            for: NSPredicate(format: "label == %@", "문단 앞 2 · 뒤 3 · 줄 180"),
            evaluatedWith: app.staticTexts["qa-paragraph-style"]
        )
        waitForExpectations(timeout: 10)
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testBodyPartialEditHardBreakAndCompleteCharacterToolbar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--character-fixture"]
        app.launch()

        let target = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-'")
        ).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        target.tap()
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.typeText("ABCDE")
        input.typeKey(.leftArrow, modifierFlags: .shift)
        input.typeKey(.leftArrow, modifierFlags: .shift)
        input.typeText("XY")
        XCTAssertEqual(input.value as? String, "ABCXY")

        let paragraphCount = app.staticTexts["qa-paragraph-count"].label
        input.typeKey(.return, modifierFlags: .shift)
        input.typeText("같은 문단")
        XCTAssertEqual(app.staticTexts["qa-paragraph-count"].label, paragraphCount)
        XCTAssertTrue(app.staticTexts["qa-draft"].label.contains("\\n"))

        app.buttons["hwp-format-font"].tap()
        XCTAssertTrue(app.buttons["굴림"].waitForExistence(timeout: 5))
        app.buttons["굴림"].tap()
        app.buttons["hwp-format-size"].tap()
        app.buttons["18 pt"].tap()
        for id in ["bold", "italic", "underline"] {
            app.buttons["hwp-format-\(id)"].tap()
            XCTAssertEqual(app.buttons["hwp-format-\(id)"].value as? String, "켜짐")
        }
        app.buttons["hwp-format-color"].tap()
        app.buttons["파랑"].tap()
        input.typeText(" 서식")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "manual225-body-character-toolbar"
        capture.lifetime = .keepAlways
        add(capture)
        app.buttons["완료"].tap()
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testListBackspaceRemovesListBeforeText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--list-fixture"]
        app.launch()
        let target = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-'")
        ).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        target.tap()
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        let original = try XCTUnwrap(input.value as? String)
        let bullet = app.buttons["hwp-format-bullet"]
        bullet.tap()
        XCTAssertEqual(bullet.value as? String, "켜짐")
        input.tap()
        for _ in 0..<30 {
            input.typeKey(.leftArrow, modifierFlags: [])
        }
        expectation(
            for: NSPredicate(format: "label == %@", "선택 0:0"),
            evaluatedWith: app.staticTexts["qa-selection"]
        )
        waitForExpectations(timeout: 10)
        input.typeText("\u{8}")
        expectation(
            for: NSPredicate(format: "value == %@", "꺼짐"),
            evaluatedWith: bullet
        )
        waitForExpectations(timeout: 10)
        XCTAssertEqual(input.value as? String, original)
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testCellParagraphEnterBackspaceHardBreakAndColumnDeletion() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--cell-fixture", "--table-structure-fixture"]
        app.launch()
        let target = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '첫 문단'")
        ).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        target.tap()
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        let initialParagraphs = app.staticTexts["qa-paragraph-count"].label
        input.typeText("\n")
        expectation(
            for: NSPredicate(format: "label != %@", initialParagraphs),
            evaluatedWith: app.staticTexts["qa-paragraph-count"]
        )
        waitForExpectations(timeout: 10)
        let splitInput = app.textViews["hwp-inline-editor"]
        splitInput.tap()
        splitInput.typeText("셀 둘째")
        for _ in 0..<30 {
            splitInput.typeKey(.leftArrow, modifierFlags: [])
        }
        expectation(
            for: NSPredicate(format: "label == %@", "선택 0:0"),
            evaluatedWith: app.staticTexts["qa-selection"]
        )
        waitForExpectations(timeout: 10)
        splitInput.typeText("\u{8}")
        expectation(
            for: NSPredicate(format: "label == %@", initialParagraphs),
            evaluatedWith: app.staticTexts["qa-paragraph-count"]
        )
        waitForExpectations(timeout: 10)
        let mergedInput = app.textViews["hwp-inline-editor"]
        mergedInput.tap()
        mergedInput.typeKey(.return, modifierFlags: .shift)
        mergedInput.typeText("셀 안 줄")
        XCTAssertEqual(app.staticTexts["qa-paragraph-count"].label, initialParagraphs)
        XCTAssertTrue(app.staticTexts["qa-draft"].label.contains("\\n"))
        XCTAssertTrue(app.staticTexts["qa-draft"].label.contains("셀 안 줄"))

        func tableAction(_ action: String, expected: String) {
            app.buttons["hwp-format-table-structure"].tap()
            let button = app.buttons["hwp-table-\(action)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
            expectation(
                for: NSPredicate(format: "label == %@", expected),
                evaluatedWith: app.staticTexts["qa-table-size"]
            )
            waitForExpectations(timeout: 15)
        }
        tableAction("columnBefore", expected: "표 2행 3열")
        tableAction("deleteColumn", expected: "표 2행 2열")
        tableAction("columnAfter", expected: "표 2행 3열")
        tableAction("deleteColumn", expected: "표 2행 2열")
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testInsertOneCellTableInBodyThenDeleteLastTable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--page-fixture"]
        app.launch()
        let body = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '쪽 설정 문단'")
        ).firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 10))
        body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let insert = app.buttons["hwp-table-insert"]
        XCTAssertTrue(insert.isEnabled)
        insert.tap()
        func enter(_ id: String, _ value: String) {
            app.buttons["hwp-insert-table-\(id)-clear"].tap()
            app.textFields["hwp-insert-table-\(id)"].typeText(value)
            app.buttons["hwp-insert-table-keyboard-done"].tap()
        }
        enter("rows", "1")
        enter("columns", "1")
        app.buttons["hwp-insert-table-apply"].tap()
        XCTAssertTrue(app.staticTexts["qa-cell-count"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["qa-cell-count"].label, "셀 1개")
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.typeText("한 칸")
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 10))
        let insertedCell = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '한 칸'")
        ).firstMatch
        XCTAssertTrue(insertedCell.waitForExistence(timeout: 10))
        insertedCell.tap()
        app.buttons["hwp-format-table-structure"].tap()
        app.buttons["hwp-table-deleteTable"].tap()
        expectation(
            for: NSPredicate(format: "label == '셀 0개'"),
            evaluatedWith: app.staticTexts["qa-cell-count"]
        )
        waitForExpectations(timeout: 15)
        XCTAssertTrue(app.textViews["hwp-inline-editor"].waitForExistence(timeout: 5))
        app.textViews["hwp-inline-editor"].typeText("표 삭제 뒤 본문")
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testSearchCaseSensitivityFromOptionsMenu() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--case-find-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["hwp-search-toggle"].waitForExistence(timeout: 10))
        app.buttons["hwp-search-toggle"].tap()
        let query = app.textFields["hwp-search-field"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.typeText("Case")
        XCTAssertTrue(app.staticTexts["hwp-search-count"].label.contains("/ 3"))
        app.buttons["hwp-search-options"].tap()
        let toggle = app.buttons["대소문자 구분"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        expectation(
            for: NSPredicate(format: "label CONTAINS '/ 1'"),
            evaluatedWith: app.staticTexts["hwp-search-count"]
        )
        waitForExpectations(timeout: 10)
    }

    @MainActor
    func testColumnsPageNavigationAndZoom() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--page-fixture"]
        app.launch()
        let target = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '둘째 본문'")
        ).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        target.tap()
        app.buttons["hwp-page-menu"].tap()
        app.buttons["hwp-page-break-insert"].tap()
        XCTAssertEqual(app.staticTexts["qa-page-count"].label, "쪽 2개")

        let jump = app.buttons["hwp-page-jump"]
        XCTAssertTrue(jump.waitForExistence(timeout: 5))
        app.buttons["다음 쪽"].tap()
        XCTAssertEqual(jump.value as? String, "2 / 2쪽")
        app.buttons["이전 쪽"].tap()
        XCTAssertEqual(jump.value as? String, "1 / 2쪽")
        let zoom = app.buttons["hwp-zoom-menu"]
        zoom.tap()
        app.buttons["150%"].tap()
        XCTAssertEqual(zoom.value as? String, "150%")

        func applyColumns(_ count: Int, configure: (() -> Void)? = nil) {
            app.buttons["hwp-page-menu"].tap()
            app.buttons["hwp-column-setup"].tap()
            let picker = app.segmentedControls["hwp-column-count"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            picker.buttons["\(count)단"].tap()
            configure?()
            app.buttons["hwp-column-apply"].tap()
            expectation(
                for: NSPredicate(format: "label BEGINSWITH %@", "단 \(count)개"),
                evaluatedWith: app.staticTexts["qa-column-style"]
            )
            waitForExpectations(timeout: 15)
        }
        applyColumns(2) {
            let gap = app.steppers["hwp-column-gap"]
            gap.buttons.element(boundBy: 1).tap()
            let separator = app.switches["hwp-column-separator"]
            XCTAssertTrue(separator.isEnabled)
            separator.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
            self.expectation(
                for: NSPredicate(format: "value == %@", "1"),
                evaluatedWith: separator
            )
            self.waitForExpectations(timeout: 10)
        }
        XCTAssertEqual(app.staticTexts["qa-column-style"].label, "단 2개 · 간격 1mm · 구분선 켜짐")
        applyColumns(3)
        applyColumns(4)
        applyColumns(1)
        applyColumns(2)
        let multicolumnTarget = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label CONTAINS %@", "쪽 설정 문단")
        ).firstMatch
        XCTAssertTrue(multicolumnTarget.waitForExistence(timeout: 10))
        multicolumnTarget.tap()
        let multicolumnInput = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(multicolumnInput.waitForExistence(timeout: 10))
        multicolumnInput.tap()
        multicolumnInput.typeText(" 다단 편집")
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label CONTAINS %@", "다단 편집")
        ).firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    func testHeaderSizeScopeMultilineAndRepeatAcrossPages() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--page-fixture"]
        app.launch()
        let second = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label == '둘째 본문'")
        ).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        second.tap()
        app.buttons["hwp-page-menu"].tap()
        app.buttons["hwp-page-break-insert"].tap()
        XCTAssertEqual(app.staticTexts["qa-page-count"].label, "쪽 2개")

        func openHeader() {
            app.buttons["hwp-page-menu"].tap()
            app.buttons["hwp-page-header"].tap()
            XCTAssertTrue(app.textViews["hwp-region-text-0"].waitForExistence(timeout: 5))
        }
        openHeader()
        let headerText = app.textViews["hwp-region-text-0"]
        headerText.tap()
        headerText.typeText("첫 줄\n둘째 줄")
        app.buttons["hwp-region-alignment"].tap()
        app.buttons["오른쪽"].tap()
        app.buttons["hwp-region-size"].tap()
        app.buttons["18 pt"].tap()
        app.buttons["hwp-region-pages"].tap()
        app.buttons["홀수 쪽"].tap()
        app.buttons["hwp-region-apply"].tap()
        XCTAssertTrue(app.staticTexts["머리말·꼬리말 공간이 부족합니다. 글자 크기나 줄 수를 줄이거나 쪽 설정에서 해당 여백을 늘려 주세요."].waitForExistence(timeout: 15))

        openHeader()
        let retryText = app.textViews["hwp-region-text-0"]
        retryText.tap()
        retryText.typeText("첫 줄\n둘째 줄")
        app.buttons["hwp-region-alignment"].tap()
        app.buttons["오른쪽"].tap()
        app.buttons["hwp-region-size"].tap()
        app.buttons["10 pt"].tap()
        app.buttons["hwp-region-pages"].tap()
        app.buttons["홀수 쪽"].tap()
        app.buttons["hwp-region-apply"].tap()
        expectation(
            for: NSPredicate(format: "label == %@", "머리말 첫 줄\n둘째 줄"),
            evaluatedWith: app.staticTexts["qa-header-text"]
        )
        waitForExpectations(timeout: 15)
        XCTAssertEqual(app.staticTexts["qa-header-pages"].label, "머리말 표시 1쪽")

        openHeader()
        app.buttons["hwp-region-pages"].tap()
        app.buttons["모든 쪽"].tap()
        app.buttons["hwp-region-apply"].tap()
        expectation(
            for: NSPredicate(format: "label == %@", "머리말 표시 2쪽"),
            evaluatedWith: app.staticTexts["qa-header-pages"]
        )
        waitForExpectations(timeout: 15)
        app.buttons["다음 쪽"].tap()
        XCTAssertEqual(app.buttons["hwp-page-jump"].value as? String, "2 / 2쪽")
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 10))
    }
}
