import XCTest

final class Manual225Batch5UITests: XCTestCase {
    @MainActor
    func testRectangleEllipseAndLineInsertionUndoRedoAndSave() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--page-fixture"]
        app.launch()

        func selectEditableBody() {
            let target = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-'")
            ).firstMatch
            XCTAssertTrue(target.waitForExistence(timeout: 10))
            target.tap()
            XCTAssertTrue(app.textViews["hwp-inline-editor"].waitForExistence(timeout: 5))
        }

        func insert(_ title: String, expected: String) {
            selectEditableBody()
            let menu = app.buttons["hwp-shape-insert"]
            XCTAssertTrue(menu.isEnabled)
            menu.tap()
            let item = app.buttons[title]
            XCTAssertTrue(item.waitForExistence(timeout: 5))
            item.tap()
            let status = app.staticTexts["qa-shapes"]
            let expectation = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label CONTAINS %@", "도형 1개 \(expected)"),
                object: status
            )
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed,
                "도형 상태=\(status.label), 결과=\(app.staticTexts["qa-result"].label)")
        }

        insert("사각형", expected: "사각형")
        app.buttons["qa-undo"].tap()
        XCTAssertTrue(app.staticTexts["qa-shapes"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["qa-shapes"].label, "도형 0개 ")
        app.buttons["qa-redo"].tap()
        XCTAssertTrue(app.staticTexts["qa-shapes"].label.contains("도형 1개 사각형"))

        app.buttons["qa-undo"].tap()
        insert("타원", expected: "타원")
        app.buttons["qa-undo"].tap()
        insert("선", expected: "선")

        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testShapeDirectMoveResizeRotateAndSave() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--page-fixture"]
        app.launch()
        insertRectangle(in: app)

        let object = firstShapeObject(in: app)
        XCTAssertTrue(object.waitForExistence(timeout: 10))
        object.tap()
        let status = app.staticTexts["qa-shape-layout"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let initial = status.label

        let moveStart = object.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        moveStart.press(forDuration: 0.2,
            thenDragTo: moveStart.withOffset(CGVector(dx: 34, dy: 22)))
        waitForLabelChange(status, from: initial)
        let moved = status.label

        let resize = app.descendants(matching: .any)["hwp-shape-resize-bottomTrailing"]
        XCTAssertTrue(resize.waitForExistence(timeout: 5))
        let resizeStart = resize.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        resizeStart.press(forDuration: 0.2,
            thenDragTo: resizeStart.withOffset(CGVector(dx: 36, dy: 24)))
        waitForLabelChange(status, from: moved)
        let resized = status.label

        let rotate = app.descendants(matching: .any)["hwp-shape-rotate"]
        XCTAssertTrue(rotate.waitForExistence(timeout: 5))
        let rotateStart = rotate.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        rotateStart.press(forDuration: 0.2,
            thenDragTo: rotateStart.withOffset(CGVector(dx: 42, dy: 18)))
        waitForLabelChange(status, from: resized)
        XCTAssertFalse(status.label.contains("회전 0"))

        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 15))
    }

    @MainActor
    func testShapeNumericLayoutRotationAndStylesUndoRedoSave() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--page-fixture"]
        app.launch()
        insertRectangle(in: app)

        let object = firstShapeObject(in: app)
        XCTAssertTrue(object.waitForExistence(timeout: 10))
        object.tap()
        object.tap()
        XCTAssertTrue(app.navigationBars["사각형 편집"].waitForExistence(timeout: 5))

        replace(app.textFields["hwp-shape-x"], with: "40")
        replace(app.textFields["hwp-shape-y"], with: "50")
        replace(app.textFields["hwp-shape-width"], with: "160")
        replace(app.textFields["hwp-shape-height"], with: "80")
        dismissKeyboard(in: app)
        app.sliders["hwp-shape-rotation"].adjust(toNormalizedSliderPosition: 0.25)
        let strokeWidth = app.sliders["hwp-shape-stroke-width"]
        reveal(strokeWidth, in: app)
        strokeWidth.adjust(toNormalizedSliderPosition: 0.5)
        let dashed = app.buttons["파선"]
        reveal(dashed, in: app)
        dashed.tap()
        let fill = app.switches["hwp-shape-fill-enabled"]
        reveal(fill, in: app)
        fill.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let shadow = app.switches["hwp-shape-shadow-enabled"]
        reveal(shadow, in: app)
        shadow.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let bringForward = app.buttons["hwp-shape-bring-forward"]
        reveal(bringForward, in: app)
        bringForward.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "label == %@", "1"),
            evaluatedWith: app.staticTexts["hwp-shape-z-order-value"])
        waitForExpectations(timeout: 5)
        app.buttons["hwp-shape-apply"].tap()

        let status = app.staticTexts["qa-shape-layout"]
        let applied = NSPredicate(format:
            "label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@",
            "X 40.0 · Y 50.0", "너비 160.0 · 높이 80.0", "순서 1", "선 2/", "채우기 끔 · 그림자 켬")
        expectation(for: applied, evaluatedWith: status)
        waitForExpectations(timeout: 15)
        XCTAssertFalse(status.label.contains("회전 0"))

        let changed = status.label
        app.buttons["qa-undo"].tap()
        expectation(for: NSPredicate(format: "label != %@", changed), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        app.buttons["qa-redo"].tap()
        expectation(for: NSPredicate(format: "label == %@", changed), evaluatedWith: status)
        waitForExpectations(timeout: 10)

        app.buttons["저장 확인"].tap()
        XCTAssertTrue(app.staticTexts["저장·재열기 성공"].waitForExistence(timeout: 15))
    }

    @MainActor
    private func insertRectangle(in app: XCUIApplication, expectedCount: Int = 1) {
        let target = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'hwp-inline-target-'")
        ).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        target.tap()
        XCTAssertTrue(app.textViews["hwp-inline-editor"].waitForExistence(timeout: 5))
        app.buttons["hwp-shape-insert"].tap()
        XCTAssertTrue(app.buttons["사각형"].waitForExistence(timeout: 5))
        app.buttons["사각형"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "도형 \(expectedCount)개"),
            evaluatedWith: app.staticTexts["qa-shapes"])
        waitForExpectations(timeout: 15)
    }

    @MainActor
    private func firstShapeObject(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'hwp-canvas-object-'")
        ).firstMatch
    }

    @MainActor
    private func replace(_ field: XCUIElement, with value: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        field.typeText(value)
    }

    @MainActor
    private func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.96)).tap()
        expectation(for: NSPredicate(format: "exists == false"),
            evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    private func waitForLabelChange(_ element: XCUIElement, from value: String) {
        expectation(for: NSPredicate(format: "label != %@", value), evaluatedWith: element)
        waitForExpectations(timeout: 15)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.exists || !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
    }
}
