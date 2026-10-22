import RivoDocumentEngine
import XCTest
@testable import shortcuts_example

/// HWP object editing carried over from Android: polygon and connector point editing (`HwpPathPoints`)
/// and the notices saying why 적용 is dimmed (`HwpRangeNotice`).
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

    // MARK: Range notices (Android `HwpRangeNotice` / `rangeProblem`)

    func testRangeProblemNamesTheValueAndTheRange() {
        XCTAssertNil(HWPRangeProblems.problem("굵기", value: 0.25, range: HWPRangeProblems.imageBorder, unit: " pt"))
        XCTAssertEqual(HWPRangeProblems.problem("굵기", value: 0.1, range: HWPRangeProblems.imageBorder, unit: " pt"),
            "굵기: 문서의 값 0.1 pt이(가) 적용할 수 있는 범위(0.25~32 pt)를 벗어났습니다.")
        XCTAssertEqual(HWPRangeProblems.short(50.8), "50.8")
        XCTAssertEqual(HWPRangeProblems.short(-100), "-100")
        XCTAssertEqual(HWPRangeProblems.short(0), "0")
    }

    func testPictureProblemsCoverBorderAdjustmentsAndTransparency() {
        XCTAssertEqual(HWPRangeProblems.image(hasBorder: true, borderWidth: 0.75, brightness: 0, contrast: 0,
            transparency: 0, supportsTransparency: false), [])
        let problems = HWPRangeProblems.image(hasBorder: false, borderWidth: 0.1, brightness: 150, contrast: -120,
            transparency: 30, supportsTransparency: false)
        XCTAssertEqual(problems, [
            "밝기: 문서의 값 150이(가) 적용할 수 있는 범위(-100~100)를 벗어났습니다.",
            "대비: 문서의 값 -120이(가) 적용할 수 있는 범위(-100~100)를 벗어났습니다.",
            "투명도: 문서의 값 30%이(가) 적용할 수 있는 범위(0~0%)를 벗어났습니다.",
        ], "A border that is off is not checked; transparency needs a picture that supports it")
        XCTAssertEqual(HWPRangeProblems.image(hasBorder: false, borderWidth: 0, brightness: 0, contrast: 0,
            transparency: 30, supportsTransparency: true), [])
    }

    func testShapeProblemsCoverStrokeAndShadowButNotAGroup() {
        let problems = HWPRangeProblems.shape(isGroup: false, strokeWidth: 1, hasShadow: true,
            shadowX: 150, shadowY: 3, shadowOpacity: 1.5)
        XCTAssertEqual(problems, [
            "가로 이동: 문서의 값 150 pt이(가) 적용할 수 있는 범위(-100~100 pt)를 벗어났습니다.",
            "농도: 문서의 값 150%이(가) 적용할 수 있는 범위(0~100%)를 벗어났습니다.",
        ])
        XCTAssertEqual(HWPRangeProblems.shape(isGroup: false, strokeWidth: 1, hasShadow: false,
            shadowX: 150, shadowY: 150, shadowOpacity: 2), [])
        XCTAssertEqual(HWPRangeProblems.shape(isGroup: true, strokeWidth: 50, hasShadow: true,
            shadowX: 150, shadowY: 150, shadowOpacity: 2), [])
    }

    func testColumnProblemsExplainCountGapAndNarrowColumns() throws {
        let layouts = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "단")).pageLayouts
        XCTAssertFalse(layouts.isEmpty)
        let fine = HWPRangeProblems.columns(count: 2, gapPoints: 10 * HWPPageSettings.pointsPerMM, layouts: layouts)
        XCTAssertEqual(fine.problems, [])
        let five = HWPRangeProblems.columns(count: 5, gapPoints: 0, layouts: layouts)
        XCTAssertEqual(five.problems, ["이 구역은 5단입니다. 1~4단 중에서 고르면 적용할 수 있습니다."])
        XCTAssertFalse(five.showsHelp)
        let gap = HWPRangeProblems.columns(count: 2, gapPoints: 200, layouts: layouts)
        XCTAssertEqual(gap.problems.first, "단 사이: 문서의 값 70.56 mm이(가) 적용할 수 있는 범위(0~50.8 mm)를 벗어났습니다.")
        XCTAssertTrue(gap.showsHelp)
        let narrow = HWPRangeProblems.columns(count: 4, gapPoints: 144, layouts: layouts)
        XCTAssertEqual(narrow.problems, ["단 너비가 너무 좁습니다. 단 수나 단 사이를 줄여 주세요."])
        XCTAssertFalse(narrow.showsHelp)
    }
}
