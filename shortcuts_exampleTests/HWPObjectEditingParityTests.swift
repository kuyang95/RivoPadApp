import RivoDocumentEngine
import XCTest
@testable import shortcuts_example

/// HWP object editing carried over from Android: polygon and connector point editing (`HwpPathPoints`).
@MainActor
final class HWPObjectEditingParityTests: XCTestCase {
    private var previousLanguage: String?

    override func setUp() {
        super.setUp()
        previousLanguage = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        UserDefaults.standard.set(AppLanguage.korean.rawValue, forKey: AppLanguage.preferenceKey)
    }

    override func tearDown() {
        if let previousLanguage {
            UserDefaults.standard.set(previousLanguage, forKey: AppLanguage.preferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppLanguage.preferenceKey)
        }
        super.tearDown()
    }

    private typealias Point = HWPShapeEditing.PathPoint

    private let square: [Point] = [.init(x: 0, y: 0), .init(x: 1, y: 0), .init(x: 1, y: 1), .init(x: 0, y: 1)]

    func testPointIsAddedAfterThePickedOneHalfwayToTheNext() throws {
        let middle = try XCTUnwrap(HWPPathPoints.inserting(after: 1, in: square, closed: true))
        XCTAssertEqual(middle.selected, 2)
        XCTAssertEqual(middle.points, [square[0], square[1], .init(x: 1, y: 0.5), square[2], square[3]])

        // A polygon's last point: halfway back to the first, added at the end.
        let closing = try XCTUnwrap(HWPPathPoints.inserting(after: 3, in: square, closed: true))
        XCTAssertEqual(closing.selected, 4)
        XCTAssertEqual(closing.points.last, .init(x: 0, y: 0.5))

        // A connector's end stays its end: the point goes between the last two.
        let connector: [Point] = [.init(x: 0, y: 0), .init(x: 0.5, y: 0), .init(x: 1, y: 1)]
        let end = try XCTUnwrap(HWPPathPoints.inserting(after: 2, in: connector, closed: false))
        XCTAssertEqual(end.selected, 2)
        XCTAssertEqual(end.points, [connector[0], connector[1], .init(x: 0.75, y: 0.5), connector[2]])

        let full = Array(repeating: Point(x: 0.5, y: 0.5), count: HWPPathPoints.maximum)
        XCTAssertNil(HWPPathPoints.inserting(after: 0, in: full, closed: true), "32 points at most")
        XCTAssertNil(HWPPathPoints.inserting(after: 0, in: [], closed: false))
    }

    func testDeleteRemovesThePickedPointIncludingTheLast() throws {
        // The old 마지막 점 삭제 removed the second-to-last point; the picked point is the one removed now.
        let last = try XCTUnwrap(HWPPathPoints.removing(3, from: square, closed: true))
        XCTAssertEqual(last.points, Array(square.prefix(3)))
        XCTAssertEqual(last.selected, 2, "The new last point is picked")

        let first = try XCTUnwrap(HWPPathPoints.removing(0, from: square, closed: true))
        XCTAssertEqual(first.points, Array(square.dropFirst()))
        XCTAssertEqual(first.selected, 0)

        XCTAssertNil(HWPPathPoints.removing(0, from: Array(square.prefix(3)), closed: true), "A polygon keeps 3")
        XCTAssertNotNil(HWPPathPoints.removing(0, from: Array(square.prefix(3)), closed: false))
        XCTAssertNil(HWPPathPoints.removing(0, from: Array(square.prefix(2)), closed: false), "A connector keeps 2")
        XCTAssertNil(HWPPathPoints.removing(4, from: square, closed: true))
        XCTAssertEqual(HWPPathPoints.minimum(closed: true), 3)
        XCTAssertEqual(HWPPathPoints.minimum(closed: false), 2)
    }

    func testStepsMoveOnePointByFivePercentInsideTheShape() {
        let moved = HWPPathPoints.moving(1, in: square, dx: -HWPPathPoints.step, dy: HWPPathPoints.step)
        XCTAssertEqual(moved[0], square[0])
        XCTAssertEqual(moved[1].x, 0.95, accuracy: 1e-9)
        XCTAssertEqual(moved[1].y, 0.05, accuracy: 1e-9)
        XCTAssertEqual(moved[2], square[2])
        // Kept inside the shape.
        let clamped = HWPPathPoints.moving(2, in: square, dx: HWPPathPoints.step, dy: HWPPathPoints.step)
        XCTAssertEqual(clamped[2], .init(x: 1, y: 1))
    }

    func testPointsReadTheirNumberAndPlaceAsAndroid() {
        XCTAssertEqual(HWPPathPoints.label(1, count: 5), "점 2 / 5")
        XCTAssertEqual(HWPPathPoints.value(.init(x: 0.5, y: 0.349)), "가로 50%, 세로 35%")
        XCTAssertEqual(HWPPathPoints.value(.init(x: 0.96, y: 0)), "가로 96%, 세로 0%")
    }
}
