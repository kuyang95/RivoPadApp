import XCTest

@testable import shortcuts_example

final class PDFZoomStepsTests: XCTestCase {
    func testStepsMatchAndroidPdfPages() {
        XCTAssertEqual(
            PDFZoomSteps.steps,
            [1, 1.25, 1.5, 2, 3, 4, 5]
        )
    }

    func testZoomInWalksStepsAndStopsAtFiveTimes() {
        var zoom = PDFZoomSteps.minimum
        var percents: [Int] = []
        while PDFZoomSteps.canZoomIn(from: zoom) {
            zoom = PDFZoomSteps.zoomIn(from: zoom)
            percents.append(PDFZoomSteps.percent(zoom))
        }
        XCTAssertEqual(
            percents,
            [125, 150, 200, 300, 400, 500]
        )
        XCTAssertEqual(PDFZoomSteps.zoomIn(from: 5), 5)
        XCTAssertFalse(PDFZoomSteps.canZoomIn(from: 5))
    }

    func testZoomOutWalksStepsAndStopsAtFitWidth() {
        var zoom = PDFZoomSteps.maximum
        var percents: [Int] = []
        while PDFZoomSteps.canZoomOut(from: zoom) {
            zoom = PDFZoomSteps.zoomOut(from: zoom)
            percents.append(PDFZoomSteps.percent(zoom))
        }
        XCTAssertEqual(
            percents,
            [400, 300, 200, 150, 125, 100]
        )
        XCTAssertEqual(PDFZoomSteps.zoomOut(from: 1), 1)
        XCTAssertFalse(PDFZoomSteps.canZoomOut(from: 1))
    }

    func testPinchedZoomBetweenStepsMovesToNeighbouringSteps() {
        XCTAssertEqual(PDFZoomSteps.zoomIn(from: 1.7), 2)
        XCTAssertEqual(PDFZoomSteps.zoomOut(from: 1.7), 1.5)
        // Within 1% of a step counts as that step.
        XCTAssertEqual(PDFZoomSteps.zoomIn(from: 1.995), 3)
        XCTAssertEqual(PDFZoomSteps.zoomOut(from: 2.005), 1.5)
    }

    func testClampKeepsPinchInsideOneToFiveTimes() {
        XCTAssertEqual(PDFZoomSteps.clamped(0.4), 1)
        XCTAssertEqual(PDFZoomSteps.clamped(7), 5)
        XCTAssertEqual(PDFZoomSteps.clamped(2.6), 2.6)
        XCTAssertEqual(PDFZoomSteps.percent(2.6), 260)
    }

    func testPageLabelReadsAsAndroid() {
        XCTAssertEqual(
            String(
                format: AppLocalization.string(
                    "%lld/%lld페이지",
                    language: .korean
                ),
                2, 7
            ),
            "2/7페이지"
        )
        XCTAssertEqual(
            String(
                format: AppLocalization.string(
                    "%lld/%lld페이지",
                    language: .english
                ),
                2, 7
            ),
            "Page 2 of 7"
        )
        XCTAssertEqual(
            AppLocalization.string("확대", language: .japanese),
            "拡大"
        )
    }
}
