import XCTest

final class Manual225Batch4UITests: XCTestCase {
    @MainActor
    private func waitForLabel(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 15) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    func testHyperlinkInsertEditRemoveUndoAndSave() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--character-fixture"]
        app.launch()

        let target = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-'")
        ).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        target.tap()
        let input = app.textViews["hwp-inline-editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.typeText("링크 문구")
        input.typeKey("a", modifierFlags: .command)
        XCTAssertTrue(app.buttons["hwp-hyperlink"].isEnabled)
        app.buttons["hwp-hyperlink"].tap()
        let address = app.textFields["hwp-link-target"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        address.typeText("example.com")
        XCTAssertEqual(address.value as? String, "example.com")
        XCTAssertTrue(app.buttons["hwp-link-apply"].isEnabled)
        app.buttons["hwp-link-apply"].tap()
        guard waitForLabel(app.staticTexts["qa-links"], containing: "링크 1개 https://example.com") else {
            XCTFail("링크 삽입 상태=\(app.staticTexts["qa-links"].label), 결과=\(app.staticTexts["qa-result"].label)")
            return
        }
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 10))

        func selectLinkedText() {
            let activeEditor = app.textViews["hwp-inline-editor"]
            if activeEditor.exists {
                activeEditor.tap()
                activeEditor.typeKey("a", modifierFlags: .command)
                app.buttons["hwp-hyperlink"].tap()
                return
            }
            let linked = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-' AND label CONTAINS %@", "링크 문구")
            ).firstMatch
            XCTAssertTrue(linked.waitForExistence(timeout: 10))
            linked.tap()
            let editor = app.textViews["hwp-inline-editor"]
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            editor.typeKey("a", modifierFlags: .command)
            app.buttons["hwp-hyperlink"].tap()
        }

        selectLinkedText()
        XCTAssertTrue(app.buttons["hwp-link-open"].waitForExistence(timeout: 5))
        let editAddress = app.textFields["hwp-link-target"]
        editAddress.tap()
        editAddress.typeKey("a", modifierFlags: .command)
        editAddress.typeText("https://openai.com")
        app.buttons["hwp-link-apply"].tap()
        guard waitForLabel(app.staticTexts["qa-links"], containing: "링크 1개 https://openai.com") else {
            XCTFail("링크 수정 상태=\(app.staticTexts["qa-links"].label), 결과=\(app.staticTexts["qa-result"].label)")
            return
        }
        selectLinkedText()
        app.buttons["hwp-link-remove"].tap()
        expectation(
            for: NSPredicate(format: "label BEGINSWITH %@", "링크 0개"),
            evaluatedWith: app.staticTexts["qa-links"]
        )
        waitForExpectations(timeout: 15)
        app.buttons["qa-undo"].tap()
        expectation(
            for: NSPredicate(format: "label CONTAINS %@", "링크 1개 https://openai.com"),
            evaluatedWith: app.staticTexts["qa-links"]
        )
        waitForExpectations(timeout: 15)
        app.buttons["qa-redo"].tap()
        expectation(
            for: NSPredicate(format: "label BEGINSWITH %@", "링크 0개"),
            evaluatedWith: app.staticTexts["qa-links"]
        )
        waitForExpectations(timeout: 15)
        app.buttons["qa-undo"].tap()
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testFootnoteEndnoteInsertUpdateDeleteUndoAndSave() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--page-fixture"]
        app.launch()

        func selectBody() {
            let activeEditor = app.textViews["hwp-inline-editor"]
            if activeEditor.exists {
                activeEditor.tap()
                return
            }
            let body = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-'")
            ).firstMatch
            XCTAssertTrue(body.waitForExistence(timeout: 10))
            body.tap()
        }
        selectBody()
        XCTAssertTrue(app.textViews["hwp-inline-editor"].waitForExistence(timeout: 5))

        func insert(_ kind: String, text: String) {
            app.buttons["hwp-notes"].tap()
            let insert = app.buttons["hwp-note-insert-\(kind)"]
            XCTAssertTrue(insert.waitForExistence(timeout: 5))
            insert.tap()
            let editor = app.textViews["hwp-note-text"]
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            editor.tap()
            editor.typeText(text)
            XCTAssertTrue(app.buttons["hwp-note-apply"].isEnabled)
            app.buttons["hwp-note-apply"].tap()
        }

        insert("footNote", text: "각주 첫 내용")
        guard waitForLabel(app.staticTexts["qa-notes"], containing: "각주 1개 · 미주 0개 · 각주 첫 내용") else {
            XCTFail("각주 삽입 상태=\(app.staticTexts["qa-notes"].label), 결과=\(app.staticTexts["qa-result"].label)")
            return
        }
        selectBody()
        XCTAssertTrue(app.textViews["hwp-inline-editor"].waitForExistence(timeout: 5))
        insert("endNote", text: "미주 첫 내용")
        expectation(
            for: NSPredicate(format: "label CONTAINS %@", "각주 1개 · 미주 1개"),
            evaluatedWith: app.staticTexts["qa-notes"]
        )
        waitForExpectations(timeout: 15)

        app.buttons["hwp-notes"].tap()
        app.buttons["hwp-note-edit-footNote-1"].tap()
        let noteText = app.textViews["hwp-note-text"]
        noteText.tap()
        noteText.typeKey("a", modifierFlags: .command)
        noteText.typeText("각주 수정 내용")
        app.buttons["hwp-note-apply"].tap()
        expectation(
            for: NSPredicate(format: "label CONTAINS %@", "각주 수정 내용"),
            evaluatedWith: app.staticTexts["qa-notes"]
        )
        waitForExpectations(timeout: 15)

        app.buttons["hwp-notes"].tap()
        app.buttons["hwp-note-edit-endNote-1"].tap()
        app.buttons["hwp-note-delete"].tap()
        expectation(
            for: NSPredicate(format: "label CONTAINS %@", "각주 1개 · 미주 0개"),
            evaluatedWith: app.staticTexts["qa-notes"]
        )
        waitForExpectations(timeout: 15)
        app.buttons["qa-undo"].tap()
        expectation(
            for: NSPredicate(format: "label CONTAINS %@", "각주 1개 · 미주 1개"),
            evaluatedWith: app.staticTexts["qa-notes"]
        )
        waitForExpectations(timeout: 15)
        app.buttons["qa-redo"].tap()
        expectation(
            for: NSPredicate(format: "label CONTAINS %@", "각주 1개 · 미주 0개"),
            evaluatedWith: app.staticTexts["qa-notes"]
        )
        waitForExpectations(timeout: 15)
        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 10))
    }
}
