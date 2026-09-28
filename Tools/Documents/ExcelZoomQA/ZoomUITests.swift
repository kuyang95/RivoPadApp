import XCTest

final class ZoomUITests: XCTestCase {
    @MainActor func testRepeatedPinchesAndCellSelection() throws {
        let app = XCUIApplication()
        app.launch()
        let result = app.staticTexts["zoom-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let grid = app.scrollViews.firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 10))
        for _ in 0 ..< 3 {
            let before = try XCTUnwrap(Double(result.label))
            // XCTest starts outward pinches with the fingers almost touching.
            // A larger synthesized spread must cross UIKit's recognition threshold.
            grid.pinch(withScale: 4, velocity: 2)
            let after = try XCTUnwrap(Double(result.label))
            XCTAssertGreaterThan(after, before * 1.3, "Pinching over cells must enlarge the grid")
            grid.pinch(withScale: 0.5, velocity: -1)
            XCTAssertLessThan(try XCTUnwrap(Double(result.label)), after * 0.8)
        }
        XCTAssertEqual(app.staticTexts["selection-result"].label, "none", "Pinching must not select a cell")
        grid.swipeUp(velocity: .slow)
        XCTAssertEqual(app.staticTexts["selection-result"].label, "none", "Panning must not select a cell")
        grid.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4)).tap()
        XCTAssertNotEqual(app.staticTexts["selection-result"].label, "none")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "repeated-native-pinches"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
