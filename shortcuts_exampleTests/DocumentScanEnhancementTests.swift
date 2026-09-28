import XCTest

@testable import shortcuts_example

/// Mirrors Android's `DocumentColorEnhancerTest` and `PaperEdgeRefinerTest`
/// so the two scanners keep producing the same page.
final class DocumentScanEnhancementTests: XCTestCase {

    // MARK: - Local background flattening

    /// Synthetic page: paper brightness ramps 150 → 235 left to right (a hard
    /// shadow gradient), with text-like dark strokes and one large dark
    /// "photo" block. After enhancement the paper must be near white on both
    /// sides, ink must stay dark, and the photo must not be washed out.
    func testFlattensShadowGradientAndKeepsInkAndPhoto() throws {
        let width = 600
        let height = 800
        var levels = [Int](repeating: 0, count: width * height)
        for y in 0 ..< height {
            for x in 0 ..< width {
                levels[y * width + x] = 150 + (85 * x) / (width - 1)
            }
        }
        // Text block: 3 px strokes every 24 px, rows 100..<600, cols 40..<560.
        for y in 100 ..< 600 where (y - 100) % 24 < 3 {
            for x in 40 ..< 560 {
                levels[y * width + x] = 40 + (10 * x) / width
            }
        }
        // Dark photo block, 150×150 at (400, 620).
        for y in 620 ..< 770 {
            for x in 400 ..< 550 {
                levels[y * width + x] = 70
            }
        }

        let enhanced = AndroidDocumentColorMath.enhance(
            try grayImage(levels, width: width, height: height)
        )

        let paperLeft = meanLuminance(
            enhanced, x: 5, y: 300, width: 30, height: 60
        )
        let paperRight = meanLuminance(
            enhanced, x: 565, y: 300, width: 30, height: 60
        )
        // Stroke rows are 100…102, 124…126, …; 297…312 is a gap.
        let leftGap = meanLuminance(
            enhanced, x: 60, y: 297, width: 100, height: 16
        )
        let rightGap = meanLuminance(
            enhanced, x: 450, y: 297, width: 100, height: 16
        )
        let ink = meanLuminance(
            enhanced, x: 100, y: 100, width: 300, height: 3
        )
        let photo = meanLuminance(
            enhanced, x: 430, y: 650, width: 90, height: 90
        )
        let topMargin = meanLuminance(
            enhanced, x: 20, y: 20, width: 560, height: 40
        )

        XCTAssertGreaterThanOrEqual(
            paperLeft, 240, "left margin paper should be white"
        )
        XCTAssertGreaterThanOrEqual(
            paperRight, 240, "right margin paper should be white"
        )
        XCTAssertGreaterThanOrEqual(
            leftGap, 235, "left text gap should be white"
        )
        XCTAssertGreaterThanOrEqual(
            rightGap, 235, "right text gap should be white"
        )
        XCTAssertGreaterThanOrEqual(
            topMargin, 240, "top margin paper should be white"
        )
        XCTAssertLessThanOrEqual(ink, 90, "ink should stay dark")
        XCTAssertLessThanOrEqual(
            photo, 175, "photo should not be washed out"
        )
        XCTAssertGreaterThanOrEqual(
            photo, 60, "photo should not be crushed"
        )
    }

    func testWarmUpRuns() {
        AndroidDocumentColorMath.warmUp()
        PaperEdgeRefiner.warmUp()
    }

    // MARK: - Paper edge refinement

    func testFullPaperIsLeftAlone() throws {
        let image = try page(width: 600, height: 800) { _, _ in false }
        XCTAssertNil(PaperEdgeRefiner.refine(image))
    }

    func testBottomWedgeIsTrimmed() throws {
        // The true bottom edge runs from (0, 799) to (599, 600); everything
        // below it is the laptop the page is lying on.
        let image = try page(width: 600, height: 800) { x, y in
            Double(y) > 799.0 - 199.0 * Double(x) / 599.0
        }
        let result = try XCTUnwrap(PaperEdgeRefiner.refine(image))
        XCTAssertEqual(result.refinedEdges, "B")
        let corners = result.corners
        XCTAssertEqual(corners[0].x, 0, accuracy: 6)
        XCTAssertEqual(corners[0].y, 0, accuracy: 6)
        XCTAssertEqual(corners[1].x, 600, accuracy: 6)
        XCTAssertEqual(corners[1].y, 0, accuracy: 6)
        XCTAssertEqual(corners[2].x, 600, accuracy: 6)
        XCTAssertEqual(corners[2].y, 601, accuracy: 12)
        XCTAssertEqual(corners[3].x, 0, accuracy: 6)
        XCTAssertEqual(corners[3].y, 800, accuracy: 12)
    }

    func testRightBandAndBottomBandAreBothTrimmed() throws {
        let image = try page(width: 600, height: 800) { x, y in
            x >= 520 || y >= 700
        }
        let result = try XCTUnwrap(PaperEdgeRefiner.refine(image))
        XCTAssertEqual(result.refinedEdges, "RB")
        let corners = result.corners
        XCTAssertEqual(corners[1].x, 520, accuracy: 6)
        XCTAssertEqual(corners[2].x, 520, accuracy: 6)
        XCTAssertEqual(corners[2].y, 700, accuracy: 6)
        XCTAssertEqual(corners[3].y, 700, accuracy: 6)
    }

    func testThinStripsAlongTopAndRightAreTrimmed() throws {
        // 8 px of desk along the top and 10 px along the right — what is left
        // when the detector's quad overshoots the page slightly.
        let image = try page(width: 600, height: 800) { x, y in
            y < 8 || x >= 590
        }
        let result = try XCTUnwrap(PaperEdgeRefiner.refine(image))
        XCTAssertEqual(result.refinedEdges, "TR")
        let corners = result.corners
        XCTAssertEqual(corners[0].y, 8, accuracy: 4)
        XCTAssertEqual(corners[1].x, 590, accuracy: 4)
        XCTAssertEqual(corners[1].y, 8, accuracy: 4)
        XCTAssertEqual(corners[2].x, 590, accuracy: 4)
        XCTAssertEqual(corners[2].y, 800, accuracy: 4)
        XCTAssertEqual(corners[3].x, 0, accuracy: 4)
    }

    func testDarkPrintedBorderDoesNotTriggerTrim() throws {
        // A 6 px black frame printed 10 px inside the paper edge.
        var levels = pageLevels(width: 600, height: 800) { _, _ in false }
        for y in 10 ..< 790 {
            for x in 10 ..< 590 {
                let inFrame = (x < 16 || x >= 584 || y < 16 || y >= 784)
                if inFrame {
                    levels[y * 600 + x] = 20
                }
            }
        }
        let image = try grayImage(levels, width: 600, height: 800)
        XCTAssertNil(PaperEdgeRefiner.refine(image))
    }

    func testBrightBackgroundIsNotTrimmed() throws {
        // White desk under white paper: there is no boundary to find.
        var levels = pageLevels(width: 600, height: 800) { _, _ in false }
        for y in 700 ..< 800 {
            for x in 0 ..< 600 {
                levels[y * 600 + x] = 235
            }
        }
        let image = try grayImage(levels, width: 600, height: 800)
        XCTAssertNil(PaperEdgeRefiner.refine(image))
    }

    func testDoesNotCollapseWhenMostlyBackground() throws {
        let image = try page(width: 600, height: 800) { x, y in
            x >= 200 || y >= 200
        }
        // Paper is only ~8% of the image — it must not produce a tiny quad.
        guard let result = PaperEdgeRefiner.refine(image) else {
            return
        }
        let corners = result.corners
        let area = (corners[1].x - corners[0].x)
            * (corners[3].y - corners[0].y)
        XCTAssertGreaterThanOrEqual(area, 0.4 * 600 * 800)
    }

    // MARK: - Mapping refined corners back to the source

    func testRefinedCornersMapBackThroughTheWarp() throws {
        let corners = [
            ScannerPixelPoint(x: 120, y: 80),
            ScannerPixelPoint(x: 880, y: 140),
            ScannerPixelPoint(x: 840, y: 700),
            ScannerPixelPoint(x: 160, y: 640),
        ]
        let outputSize = ScannerPixelSize(width: 400, height: 300)
        let mapped = try AndroidPerspectiveMath.sourcePoints(
            for: [
                ScannerPixelPoint(x: 0, y: 0),
                ScannerPixelPoint(x: 400, y: 0),
                ScannerPixelPoint(x: 400, y: 300),
                ScannerPixelPoint(x: 0, y: 300),
            ],
            orderedCorners: corners,
            outputSize: outputSize
        )

        // The four output corners map back onto the source quad's corners.
        for index in 0 ..< 4 {
            XCTAssertEqual(
                mapped[index].x, corners[index].x, accuracy: 0.01
            )
            XCTAssertEqual(
                mapped[index].y, corners[index].y, accuracy: 0.01
            )
        }
    }

    // MARK: - Helpers

    /// Paper (with text strokes) everywhere except where `isBackground` says.
    private func pageLevels(
        width: Int,
        height: Int,
        isBackground: (Int, Int) -> Bool
    ) -> [Int] {
        var levels = [Int](repeating: 0, count: width * height)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let stroke = y >= 80
                    && y < height - 80
                    && (y - 80) % 24 < 3
                    && x >= 60
                    && x < width - 60
                if isBackground(x, y) {
                    levels[y * width + x] = 45
                } else if stroke {
                    levels[y * width + x] = 30
                } else {
                    levels[y * width + x] = 215 - (25 * x) / width
                }
            }
        }
        return levels
    }

    private func page(
        width: Int,
        height: Int,
        isBackground: (Int, Int) -> Bool
    ) throws -> ScannerRGBAImage {
        try grayImage(
            pageLevels(
                width: width,
                height: height,
                isBackground: isBackground
            ),
            width: width,
            height: height
        )
    }

    private func grayImage(
        _ levels: [Int],
        width: Int,
        height: Int
    ) throws -> ScannerRGBAImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0 ..< (width * height) {
            let value = UInt8(clamping: levels[index])
            bytes[index * 4] = value
            bytes[index * 4 + 1] = value
            bytes[index * 4 + 2] = value
        }
        return try ScannerRGBAImage(
            width: width,
            height: height,
            bytes: bytes
        )
    }

    private func meanLuminance(
        _ image: ScannerRGBAImage,
        x: Int,
        y: Int,
        width: Int,
        height: Int
    ) -> Double {
        var sum = 0.0
        for row in y ..< (y + height) {
            for column in x ..< (x + width) {
                let offset = image.byteOffset(x: column, y: row)
                sum += 0.299 * Double(image.bytes[offset])
                    + 0.587 * Double(image.bytes[offset + 1])
                    + 0.114 * Double(image.bytes[offset + 2])
            }
        }
        return sum / Double(width * height)
    }
}
