import Foundation

nonisolated struct PaperEdgeRefinerResult: Equatable, Sendable {
    /// Top-left, top-right, bottom-right, bottom-left in the input image's
    /// pixel-edge coordinates (0 … width, 0 … height).
    let corners: [ScannerPixelPoint]
    /// Which borders were refit, as `T`, `R`, `B`, `L`.
    let refinedEdges: String
    let maximumShiftFraction: Float
}

/// Refines the corners of a perspective-cropped document so they hug the
/// paper.
///
/// The document detector sometimes locks onto a quad that includes whatever
/// the page is lying on (laptop, table edge, clipboard), and it does so
/// consistently across preview frames, so neither the stability gate nor the
/// capture-time corner check can catch it. After the perspective warp that
/// shows up as a dark wedge or band along one or more borders. This estimates
/// the paper brightness (on a morphologically closed map so ink does not
/// count), scans inward from each border for where the paper really starts,
/// fits a line to that boundary, and returns the corners of the quad enclosed
/// by the four edge lines.
///
/// Assumptions and limits:
///  - Paper is brighter than the background it is lying on. A white desk
///    under white paper yields no boundary and the corners are left alone.
///  - Works in the warped image's coordinate space; the caller maps the
///    result back to the source image and re-warps from there so the output
///    is not resampled twice.
nonisolated enum PaperEdgeRefiner {
    static let mapLongSide = 320
    static let closeRadius = 4
    static let paperLevelPercentile: Float = 0.8
    static let paperThresholdRatio: Float = 0.55

    /// A boundary hit needs this many consecutive paper pixels to count.
    static let minimumRun = 3

    /// Boundary within this many map pixels of the border counts as
    /// "the paper reaches the border", which is not boundary evidence.
    static let borderMargin = 0

    /// An edge is refit only if at least this fraction of its scan lines
    /// found a boundary.
    static let minimumCandidateFraction: Float = 0.12
    static let minimumCandidates = 10

    /// Maximum |slope| for an edge line relative to its nominal orientation
    /// (1 = 45°).
    static let maximumEdgeSlope: Float = 0.7

    /// Median absolute residual of the fit, as a fraction of the map's long
    /// side.
    static let maximumResidualFraction: Float = 0.02

    /// The refined quad must keep at least this fraction of the original area.
    static let minimumAreaFraction: Float = 0.4

    /// Corners may move outward by at most this fraction of the dimension.
    static let maximumOutwardFraction: Float = 0.1

    /// Skip re-warping when no corner moves more than this fraction of the
    /// diagonal. Even a thin strip of desk along one border is visible in the
    /// saved scan, so this is kept small (~1 map pixel).
    static let minimumShiftFraction: Float = 0.0025

    /// Runs the refiner once on a small synthetic page with a background
    /// strip, so the first real capture does not pay for cold code paths.
    static func warmUp() {
        let width = 320
        let height = 240
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let background = y < 12 || x >= width - 14
                let value = background ? 45 : 215 - (20 * x) / width
                let offset = ((y * width) + x) * 4
                bytes[offset] = UInt8(clamping: value)
                bytes[offset + 1] = UInt8(clamping: value)
                bytes[offset + 2] = UInt8(clamping: value)
            }
        }
        guard let image = try? ScannerRGBAImage(
            width: width,
            height: height,
            bytes: bytes
        ) else {
            return
        }
        for _ in 0 ..< 2 {
            _ = refine(image)
        }
    }

    /// - Returns: refined corners, or `nil` when the paper already fills the
    ///   image or no reliable boundary could be found.
    static func refine(_ image: ScannerRGBAImage) -> PaperEdgeRefinerResult? {
        let width = image.width
        let height = image.height
        guard width >= 8, height >= 8 else {
            return nil
        }

        let scale = max(
            Int((Float(max(width, height)) / Float(mapLongSide)).rounded(.up)),
            1
        )
        let mapWidth = (width + scale - 1) / scale
        let mapHeight = (height + scale - 1) / scale
        let luminanceMap = downsampleLuminance(
            image,
            scale: scale,
            mapWidth: mapWidth,
            mapHeight: mapHeight
        )

        var closed = [Float](repeating: 0, count: mapWidth * mapHeight)
        var temporary = [Float](repeating: 0, count: mapWidth * mapHeight)
        var scratch = [Float](repeating: 0, count: mapWidth * mapHeight)
        AndroidDocumentColorMath.separableExtreme(
            luminanceMap,
            into: &temporary,
            scratch: &scratch,
            width: mapWidth,
            height: mapHeight,
            radius: closeRadius,
            useMaximum: true
        )
        AndroidDocumentColorMath.separableExtreme(
            temporary,
            into: &closed,
            scratch: &scratch,
            width: mapWidth,
            height: mapHeight,
            radius: closeRadius,
            useMaximum: false
        )

        let paperLevel = AndroidDocumentColorMath.percentile(
            of: closed,
            ratio: paperLevelPercentile
        )
        guard paperLevel >= 40 else {
            return nil
        }
        let threshold = paperLevel * paperThresholdRatio
        // The boundary scan uses the raw luminance, not the closed map:
        // closing would erase a thin background strip along a border just as
        // it erases ink. Ink cannot fool the scan because the page margin is
        // reached before any text, and the scan only records the first run of
        // paper from the border inward.
        let mask = luminanceMap.map { $0 >= threshold }

        // Edge lines live in map coordinates: pixel centers at integer
        // coordinates, borders at -0.5 and dimension - 0.5.
        let top = fitHorizontalEdge(
            mask,
            mapWidth: mapWidth,
            mapHeight: mapHeight,
            fromTop: true
        )
        let bottom = fitHorizontalEdge(
            mask,
            mapWidth: mapWidth,
            mapHeight: mapHeight,
            fromTop: false
        )
        let left = fitVerticalEdge(
            mask,
            mapWidth: mapWidth,
            mapHeight: mapHeight,
            fromLeft: true
        )
        let right = fitVerticalEdge(
            mask,
            mapWidth: mapWidth,
            mapHeight: mapHeight,
            fromLeft: false
        )
        guard top != nil || bottom != nil || left != nil || right != nil else {
            return nil
        }

        let topLine = top ?? Line(a: 0, b: 1, c: 0.5)
        let bottomLine = bottom ?? Line(a: 0, b: 1, c: -(Float(mapHeight) - 0.5))
        let leftLine = left ?? Line(a: 1, b: 0, c: 0.5)
        let rightLine = right ?? Line(a: 1, b: 0, c: -(Float(mapWidth) - 0.5))

        guard let topLeft = intersect(topLine, leftLine),
              let topRight = intersect(topLine, rightLine),
              let bottomRight = intersect(bottomLine, rightLine),
              let bottomLeft = intersect(bottomLine, leftLine) else {
            return nil
        }

        // Clamp outward growth, then validate the shape.
        let minimumX = -0.5 - Float(mapWidth) * maximumOutwardFraction
        let maximumX = Float(mapWidth) - 0.5
            + Float(mapWidth) * maximumOutwardFraction
        let minimumY = -0.5 - Float(mapHeight) * maximumOutwardFraction
        let maximumY = Float(mapHeight) - 0.5
            + Float(mapHeight) * maximumOutwardFraction
        let quad = [topLeft, topRight, bottomRight, bottomLeft].map { point in
            ScannerPixelPoint(
                x: min(max(point.x, minimumX), maximumX),
                y: min(max(point.y, minimumY), maximumY)
            )
        }
        guard isConvex(quad) else {
            return nil
        }
        guard polygonArea(quad)
            >= minimumAreaFraction * Float(mapWidth) * Float(mapHeight) else {
            return nil
        }

        let diagonal = hypotenuse(Float(mapWidth), Float(mapHeight))
        let border = [
            ScannerPixelPoint(x: -0.5, y: -0.5),
            ScannerPixelPoint(x: Float(mapWidth) - 0.5, y: -0.5),
            ScannerPixelPoint(
                x: Float(mapWidth) - 0.5,
                y: Float(mapHeight) - 0.5
            ),
            ScannerPixelPoint(x: -0.5, y: Float(mapHeight) - 0.5),
        ]
        var maximumShift: Float = 0
        for index in 0 ..< 4 {
            let shift = hypotenuse(
                quad[index].x - border[index].x,
                quad[index].y - border[index].y
            ) / diagonal
            maximumShift = max(maximumShift, shift)
        }
        guard maximumShift >= minimumShiftFraction else {
            return nil
        }

        // Map edge coordinates back to full resolution:
        // map edge e ↔ full (e + 0.5) × scale.
        let corners = quad.map { point in
            ScannerPixelPoint(
                x: (point.x + 0.5) * Float(scale),
                y: (point.y + 0.5) * Float(scale)
            )
        }
        var edges = ""
        if top != nil { edges += "T" }
        if right != nil { edges += "R" }
        if bottom != nil { edges += "B" }
        if left != nil { edges += "L" }
        return PaperEdgeRefinerResult(
            corners: corners,
            refinedEdges: edges,
            maximumShiftFraction: maximumShift
        )
    }

    // MARK: - Edge fitting

    /// Line `a·x + b·y + c = 0`.
    nonisolated struct Line: Equatable, Sendable {
        let a: Float
        let b: Float
        let c: Float
    }

    /// Scans each column from the top (or bottom) border inward for the first
    /// run of paper. Columns where the paper reaches the border are not
    /// boundary evidence; the rest are fit with `y = p + q·x`.
    private static func fitHorizontalEdge(
        _ mask: [Bool],
        mapWidth: Int,
        mapHeight: Int,
        fromTop: Bool
    ) -> Line? {
        var positions: [Float] = []
        var boundaries: [Float] = []
        for x in 0 ..< mapWidth {
            guard let hit = firstPaperAlongColumn(
                mask,
                mapWidth: mapWidth,
                mapHeight: mapHeight,
                column: x,
                fromTop: fromTop
            ) else {
                continue
            }
            let reachesBorder = fromTop
                ? hit <= borderMargin
                : hit >= mapHeight - 1 - borderMargin
            if reachesBorder {
                continue
            }
            positions.append(Float(x))
            // The edge sits between the first paper pixel and the one before.
            boundaries.append(
                fromTop ? Float(hit) - 0.5 : Float(hit) + 0.5
            )
        }
        guard positions.count >= minimumCandidates,
              Float(positions.count)
                  >= minimumCandidateFraction * Float(mapWidth) else {
            return nil
        }
        guard let fit = robustFit(
            positions,
            boundaries,
            longSide: max(mapWidth, mapHeight)
        ), abs(fit.slope) <= maximumEdgeSlope else {
            return nil
        }
        // y = p + q·x  →  q·x - y + p = 0
        return Line(a: fit.slope, b: -1, c: fit.intercept)
    }

    private static func fitVerticalEdge(
        _ mask: [Bool],
        mapWidth: Int,
        mapHeight: Int,
        fromLeft: Bool
    ) -> Line? {
        var positions: [Float] = []
        var boundaries: [Float] = []
        for y in 0 ..< mapHeight {
            guard let hit = firstPaperAlongRow(
                mask,
                mapWidth: mapWidth,
                row: y,
                fromLeft: fromLeft
            ) else {
                continue
            }
            let reachesBorder = fromLeft
                ? hit <= borderMargin
                : hit >= mapWidth - 1 - borderMargin
            if reachesBorder {
                continue
            }
            positions.append(Float(y))
            boundaries.append(
                fromLeft ? Float(hit) - 0.5 : Float(hit) + 0.5
            )
        }
        guard positions.count >= minimumCandidates,
              Float(positions.count)
                  >= minimumCandidateFraction * Float(mapHeight) else {
            return nil
        }
        guard let fit = robustFit(
            positions,
            boundaries,
            longSide: max(mapWidth, mapHeight)
        ), abs(fit.slope) <= maximumEdgeSlope else {
            return nil
        }
        // x = p + q·y  →  x - q·y - p = 0
        return Line(a: 1, b: -fit.slope, c: -fit.intercept)
    }

    private static func firstPaperAlongColumn(
        _ mask: [Bool],
        mapWidth: Int,
        mapHeight: Int,
        column: Int,
        fromTop: Bool
    ) -> Int? {
        var run = 0
        if fromTop {
            for y in 0 ..< mapHeight {
                if mask[y * mapWidth + column] {
                    run += 1
                    if run >= minimumRun {
                        return y - minimumRun + 1
                    }
                } else {
                    run = 0
                }
            }
        } else {
            for y in stride(from: mapHeight - 1, through: 0, by: -1) {
                if mask[y * mapWidth + column] {
                    run += 1
                    if run >= minimumRun {
                        return y + minimumRun - 1
                    }
                } else {
                    run = 0
                }
            }
        }
        return nil
    }

    private static func firstPaperAlongRow(
        _ mask: [Bool],
        mapWidth: Int,
        row: Int,
        fromLeft: Bool
    ) -> Int? {
        var run = 0
        let offset = row * mapWidth
        if fromLeft {
            for x in 0 ..< mapWidth {
                if mask[offset + x] {
                    run += 1
                    if run >= minimumRun {
                        return x - minimumRun + 1
                    }
                } else {
                    run = 0
                }
            }
        } else {
            for x in stride(from: mapWidth - 1, through: 0, by: -1) {
                if mask[offset + x] {
                    run += 1
                    if run >= minimumRun {
                        return x + minimumRun - 1
                    }
                } else {
                    run = 0
                }
            }
        }
        return nil
    }

    private struct LineFit {
        let intercept: Float
        let slope: Float
    }

    /// Least squares `v = p + q·u` with one pass of outlier rejection
    /// (residual > 2.5 × MAD). Returns `nil` when the fit is not tight.
    private static func robustFit(
        _ u: [Float],
        _ v: [Float],
        longSide: Int
    ) -> LineFit? {
        guard var fit = leastSquares(u, v, keep: nil) else {
            return nil
        }
        let residuals = (0 ..< u.count).map { index in
            abs(v[index] - (fit.intercept + fit.slope * u[index]))
        }
        let deviation = max(median(residuals), 0.5)
        let keep = residuals.map { $0 <= 2.5 * deviation }
        guard keep.filter({ $0 }).count >= minimumCandidates else {
            return nil
        }
        guard let refit = leastSquares(u, v, keep: keep) else {
            return nil
        }
        fit = refit
        var kept: [Float] = []
        for index in u.indices where keep[index] {
            kept.append(
                abs(v[index] - (fit.intercept + fit.slope * u[index]))
            )
        }
        guard median(kept) <= maximumResidualFraction * Float(longSide) else {
            return nil
        }
        return fit
    }

    private static func leastSquares(
        _ u: [Float],
        _ v: [Float],
        keep: [Bool]?
    ) -> LineFit? {
        var count = 0
        var sumU = 0.0
        var sumV = 0.0
        var sumUU = 0.0
        var sumUV = 0.0
        for index in u.indices {
            if let keep, !keep[index] {
                continue
            }
            count += 1
            sumU += Double(u[index])
            sumV += Double(v[index])
            sumUU += Double(u[index]) * Double(u[index])
            sumUV += Double(u[index]) * Double(v[index])
        }
        guard count >= 2 else {
            return nil
        }
        let denominator = Double(count) * sumUU - sumU * sumU
        guard abs(denominator) >= 1e-6 else {
            return nil
        }
        let slope = (Double(count) * sumUV - sumU * sumV) / denominator
        let intercept = (sumV - slope * sumU) / Double(count)
        return LineFit(intercept: Float(intercept), slope: Float(slope))
    }

    private static func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else {
            return 0
        }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    // MARK: - Geometry

    private static func intersect(
        _ first: Line,
        _ second: Line
    ) -> ScannerPixelPoint? {
        let determinant = first.a * second.b - second.a * first.b
        guard abs(determinant) >= 1e-6 else {
            return nil
        }
        return ScannerPixelPoint(
            x: (first.b * second.c - second.b * first.c) / determinant,
            y: (second.a * first.c - first.a * second.c) / determinant
        )
    }

    private static func isConvex(_ quad: [ScannerPixelPoint]) -> Bool {
        var sign = 0
        for index in 0 ..< 4 {
            let current = quad[index]
            let next = quad[(index + 1) % 4]
            let after = quad[(index + 2) % 4]
            let firstX = next.x - current.x
            let firstY = next.y - current.y
            let secondX = after.x - next.x
            let secondY = after.y - next.y
            let cross = firstX * secondY - firstY * secondX
            let orientation = cross > 0 ? 1 : (cross < 0 ? -1 : 0)
            if orientation == 0 {
                return false
            }
            if sign == 0 {
                sign = orientation
            } else if orientation != sign {
                return false
            }
        }
        return true
    }

    private static func polygonArea(_ quad: [ScannerPixelPoint]) -> Float {
        var sum: Float = 0
        for index in 0 ..< 4 {
            let current = quad[index]
            let next = quad[(index + 1) % 4]
            sum += current.x * next.y - next.x * current.y
        }
        return abs(sum) / 2
    }

    private static func hypotenuse(_ x: Float, _ y: Float) -> Float {
        Float(sqrt(Double(x) * Double(x) + Double(y) * Double(y)))
    }

    // MARK: - Map building

    private static func downsampleLuminance(
        _ image: ScannerRGBAImage,
        scale: Int,
        mapWidth: Int,
        mapHeight: Int
    ) -> [Float] {
        let width = image.width
        let height = image.height
        var output = [Float](repeating: 0, count: mapWidth * mapHeight)
        image.bytes.withUnsafeBufferPointer { pixels in
            output.withUnsafeMutableBufferPointer { destination in
                AndroidDocumentColorMath.parallelRows(mapHeight) { first, last in
                    for mapY in first ..< last {
                        let y0 = mapY * scale
                        let y1 = min(y0 + scale, height)
                        for mapX in 0 ..< mapWidth {
                            let x0 = mapX * scale
                            let x1 = min(x0 + scale, width)
                            var sum: Float = 0
                            var count = 0
                            for y in y0 ..< y1 {
                                let row = y * width
                                for x in x0 ..< x1 {
                                    let offset = (row + x) * 4
                                    sum += AndroidDocumentColorMath.luminance(
                                        red: Float(pixels[offset]),
                                        green: Float(pixels[offset + 1]),
                                        blue: Float(pixels[offset + 2])
                                    )
                                    count += 1
                                }
                            }
                            destination[mapY * mapWidth + mapX] =
                                sum / Float(max(count, 1))
                        }
                    }
                }
            }
        }
        return output
    }
}
