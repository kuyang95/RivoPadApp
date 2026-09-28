import CoreImage
import Foundation

nonisolated struct ScannerPixelPoint: Equatable, Sendable {
    let x: Float
    let y: Float
}

nonisolated struct ScannerPixelSize: Equatable, Sendable {
    let width: Int
    let height: Int
}

nonisolated enum ScannerPerspectiveError: Error, Equatable, Sendable {
    case invalidQuad
    case singularTransform
}

nonisolated enum AndroidPerspectiveMath {
    /// VisionCraft Android shrinks capture-time LCNet corners by 1.5% toward
    /// the centroid before the perspective warp. UVDoc is sensitive to the
    /// page boundary it receives, so keep this value shared by every iOS
    /// perspective-correction path instead of relying on a caller override.
    static let captureInsetFraction: Float = 0.015

    static func pixelCorners(
        from quad: DocumentQuad,
        imageWidth: Int,
        imageHeight: Int,
        insetFraction: Float = captureInsetFraction
    ) -> [ScannerPixelPoint] {
        let source = quad.points.map {
            ScannerPixelPoint(
                x: Float($0.x) * Float(imageWidth),
                y: Float($0.y) * Float(imageHeight)
            )
        }
        let ordered = orderCorners(source)
        return insetCorners(ordered, fraction: insetFraction)
    }

    static func orderCorners(
        _ corners: [ScannerPixelPoint]
    ) -> [ScannerPixelPoint] {
        precondition(corners.count == 4)

        let verticallySorted = corners.enumerated().sorted { left, right in
            if left.element.y == right.element.y {
                return left.offset < right.offset
            }
            return left.element.y < right.element.y
        }.map(\.element)

        let top = Array(verticallySorted[0 ..< 2])
            .enumerated()
            .sorted { left, right in
                if left.element.x == right.element.x {
                    return left.offset < right.offset
                }
                return left.element.x < right.element.x
            }
            .map(\.element)
        let bottom = Array(verticallySorted[2 ..< 4])
            .enumerated()
            .sorted { left, right in
                if left.element.x == right.element.x {
                    return left.offset < right.offset
                }
                return left.element.x < right.element.x
            }
            .map(\.element)

        return [top[0], top[1], bottom[1], bottom[0]]
    }

    static func insetCorners(
        _ corners: [ScannerPixelPoint],
        fraction: Float
    ) -> [ScannerPixelPoint] {
        precondition(corners.count == 4)
        let centerX = Float(
            corners.reduce(0.0) { $0 + Double($1.x) }
                / Double(corners.count)
        )
        let centerY = Float(
            corners.reduce(0.0) { $0 + Double($1.y) }
                / Double(corners.count)
        )

        return corners.map { point in
            ScannerPixelPoint(
                x: point.x + (centerX - point.x) * fraction,
                y: point.y + (centerY - point.y) * fraction
            )
        }
    }

    static func outputSize(
        for orderedCorners: [ScannerPixelPoint]
    ) -> ScannerPixelSize {
        precondition(orderedCorners.count == 4)
        let topLeft = orderedCorners[0]
        let topRight = orderedCorners[1]
        let bottomRight = orderedCorners[2]
        let bottomLeft = orderedCorners[3]

        let topWidth = distance(topLeft, topRight)
        let bottomWidth = distance(bottomLeft, bottomRight)
        let leftHeight = distance(topLeft, bottomLeft)
        let rightHeight = distance(topRight, bottomRight)
        let fallback = ScannerPixelSize(
            width: max(Int(max(topWidth, bottomWidth)), 1),
            height: max(Int(max(leftHeight, rightHeight)), 1)
        )

        guard topWidth > 0, bottomWidth > 0,
              leftHeight > 0, rightHeight > 0 else {
            return fallback
        }

        let widthRatio =
            min(topWidth, bottomWidth) / max(topWidth, bottomWidth)
        let heightRatio =
            min(leftHeight, rightHeight) / max(leftHeight, rightHeight)
        if widthRatio > 0.9, heightRatio > 0.9 {
            return fallback
        }

        guard let horizontalVanishingPoint = lineIntersection(
            topLeft,
            topRight,
            bottomLeft,
            bottomRight
        ),
        let verticalVanishingPoint = lineIntersection(
            topLeft,
            bottomLeft,
            topRight,
            bottomRight
        ) else {
            return fallback
        }

        let centerX =
            (topLeft.x + topRight.x + bottomRight.x + bottomLeft.x) / 4
        let centerY =
            (topLeft.y + topRight.y + bottomRight.y + bottomLeft.y) / 4
        let focalLengthSquared = -(
            (
                horizontalVanishingPoint.x - centerX
            ) * (
                verticalVanishingPoint.x - centerX
            )
            + (
                horizontalVanishingPoint.y - centerY
            ) * (
                verticalVanishingPoint.y - centerY
            )
        )
        guard focalLengthSquared > 0 else {
            return fallback
        }

        let focalLength = Float(sqrt(Double(focalLengthSquared)))
        let angularWidth = (
            angularSpan(
                topLeft,
                topRight,
                centerX: centerX,
                centerY: centerY,
                focalLength: focalLength
            )
            + angularSpan(
                bottomLeft,
                bottomRight,
                centerX: centerX,
                centerY: centerY,
                focalLength: focalLength
            )
        ) / 2
        let angularHeight = (
            angularSpan(
                topLeft,
                bottomLeft,
                centerX: centerX,
                centerY: centerY,
                focalLength: focalLength
            )
            + angularSpan(
                topRight,
                bottomRight,
                centerX: centerX,
                centerY: centerY,
                focalLength: focalLength
            )
        ) / 2
        guard angularWidth > 0, angularHeight > 0 else {
            return fallback
        }

        let aspectRatio = angularWidth / angularHeight
        let maximumEdge = max(
            topWidth,
            bottomWidth,
            leftHeight,
            rightHeight
        )
        if aspectRatio >= 1 {
            return ScannerPixelSize(
                width: max(Int(maximumEdge), 1),
                height: max(Int(maximumEdge / aspectRatio), 1)
            )
        }
        return ScannerPixelSize(
            width: max(Int(maximumEdge * aspectRatio), 1),
            height: max(Int(maximumEdge), 1)
        )
    }

    static func warp(
        _ source: ScannerRGBAImage,
        orderedCorners: [ScannerPixelPoint],
        outputSize: ScannerPixelSize
    ) throws -> ScannerRGBAImage {
        guard orderedCorners.count == 4,
              outputSize.width > 0,
              outputSize.height > 0 else {
            throw ScannerPerspectiveError.invalidQuad
        }

        let homography = try UnitSquareHomography(
            topLeft: orderedCorners[0],
            topRight: orderedCorners[1],
            bottomRight: orderedCorners[2],
            bottomLeft: orderedCorners[3]
        )
        var output = [UInt8](
            repeating: 0,
            count: outputSize.width * outputSize.height * 4
        )

        for y in 0 ..< outputSize.height {
            let unitY = (Float(y) + 0.5) / Float(outputSize.height)
            for x in 0 ..< outputSize.width {
                let unitX = (Float(x) + 0.5) / Float(outputSize.width)
                let geometricSource = try homography.map(
                    x: unitX,
                    y: unitY
                )
                // Bitmap coordinates describe pixel edges; bilinear texel
                // coordinates describe pixel centers.
                let sourceX = min(
                    max(geometricSource.x - 0.5, 0),
                    Float(source.width - 1)
                )
                let sourceY = min(
                    max(geometricSource.y - 0.5, 0),
                    Float(source.height - 1)
                )
                let sourceX0 = Int(sourceX)
                let sourceY0 = Int(sourceY)
                let sourceX1 = min(sourceX0 + 1, source.width - 1)
                let sourceY1 = min(sourceY0 + 1, source.height - 1)
                let fractionX = sourceX - Float(sourceX0)
                let fractionY = sourceY - Float(sourceY0)
                let weight00 = (1 - fractionX) * (1 - fractionY)
                let weight01 = fractionX * (1 - fractionY)
                let weight10 = (1 - fractionX) * fractionY
                let weight11 = fractionX * fractionY
                let source00 = source.byteOffset(x: sourceX0, y: sourceY0)
                let source01 = source.byteOffset(x: sourceX1, y: sourceY0)
                let source10 = source.byteOffset(x: sourceX0, y: sourceY1)
                let source11 = source.byteOffset(x: sourceX1, y: sourceY1)
                let destination = (y * outputSize.width + x) * 4

                for channel in 0 ..< 4 {
                    let value =
                        weight00 * Float(source.bytes[source00 + channel])
                        + weight01 * Float(source.bytes[source01 + channel])
                        + weight10 * Float(source.bytes[source10 + channel])
                        + weight11 * Float(source.bytes[source11 + channel])
                    output[destination + channel] = UInt8(
                        clamping: Int(value.rounded())
                    )
                }
            }
        }

        return try ScannerRGBAImage(
            width: outputSize.width,
            height: outputSize.height,
            bytes: output
        )
    }

    /// Maps points from the warped output back into source coordinates.
    ///
    /// `warpedPoints` use the output image's pixel-edge coordinates
    /// (0 … width, 0 … height), the same space ``PaperEdgeRefiner`` returns,
    /// so a refined quad can be re-warped from the source image instead of
    /// resampling the already-warped page a second time.
    static func sourcePoints(
        for warpedPoints: [ScannerPixelPoint],
        orderedCorners: [ScannerPixelPoint],
        outputSize: ScannerPixelSize
    ) throws -> [ScannerPixelPoint] {
        guard orderedCorners.count == 4,
              outputSize.width > 0,
              outputSize.height > 0 else {
            throw ScannerPerspectiveError.invalidQuad
        }
        let homography = try UnitSquareHomography(
            topLeft: orderedCorners[0],
            topRight: orderedCorners[1],
            bottomRight: orderedCorners[2],
            bottomLeft: orderedCorners[3]
        )
        return try warpedPoints.map { point in
            try homography.map(
                x: point.x / Float(outputSize.width),
                y: point.y / Float(outputSize.height)
            )
        }
    }

    private static func distance(
        _ first: ScannerPixelPoint,
        _ second: ScannerPixelPoint
    ) -> Float {
        let deltaX = first.x - second.x
        let deltaY = first.y - second.y
        return Float(sqrt(Double(deltaX * deltaX + deltaY * deltaY)))
    }

    private static func lineIntersection(
        _ firstStart: ScannerPixelPoint,
        _ firstEnd: ScannerPixelPoint,
        _ secondStart: ScannerPixelPoint,
        _ secondEnd: ScannerPixelPoint
    ) -> ScannerPixelPoint? {
        let denominator =
            (firstStart.x - firstEnd.x)
            * (secondStart.y - secondEnd.y)
            - (firstStart.y - firstEnd.y)
            * (secondStart.x - secondEnd.x)
        guard abs(denominator) >= 0.000_001 else {
            return nil
        }

        let amount = (
            (firstStart.x - secondStart.x)
            * (secondStart.y - secondEnd.y)
            - (firstStart.y - secondStart.y)
            * (secondStart.x - secondEnd.x)
        ) / denominator
        return ScannerPixelPoint(
            x: firstStart.x + amount * (firstEnd.x - firstStart.x),
            y: firstStart.y + amount * (firstEnd.y - firstStart.y)
        )
    }

    private static func angularSpan(
        _ first: ScannerPixelPoint,
        _ second: ScannerPixelPoint,
        centerX: Float,
        centerY: Float,
        focalLength: Float
    ) -> Float {
        let firstX = (first.x - centerX) / focalLength
        let firstY = (first.y - centerY) / focalLength
        let secondX = (second.x - centerX) / focalLength
        let secondY = (second.y - centerY) / focalLength
        let dot = firstX * secondX + firstY * secondY + 1
        let firstMagnitude = Float(
            sqrt(Double(firstX * firstX + firstY * firstY + 1))
        )
        let secondMagnitude = Float(
            sqrt(Double(secondX * secondX + secondY * secondY + 1))
        )
        let cosine = min(
            max(Double(dot / (firstMagnitude * secondMagnitude)), -1),
            1
        )
        return Float(acos(cosine))
    }

    private struct UnitSquareHomography {
        let a: Float
        let b: Float
        let c: Float
        let d: Float
        let e: Float
        let f: Float
        let g: Float
        let h: Float

        init(
            topLeft: ScannerPixelPoint,
            topRight: ScannerPixelPoint,
            bottomRight: ScannerPixelPoint,
            bottomLeft: ScannerPixelPoint
        ) throws {
            let deltaX1 = topRight.x - bottomRight.x
            let deltaX2 = bottomLeft.x - bottomRight.x
            let deltaX3 =
                topLeft.x - topRight.x + bottomRight.x - bottomLeft.x
            let deltaY1 = topRight.y - bottomRight.y
            let deltaY2 = bottomLeft.y - bottomRight.y
            let deltaY3 =
                topLeft.y - topRight.y + bottomRight.y - bottomLeft.y

            let g: Float
            let h: Float
            if abs(deltaX3) < 0.000_001,
               abs(deltaY3) < 0.000_001 {
                g = 0
                h = 0
            } else {
                let denominator = deltaX1 * deltaY2 - deltaX2 * deltaY1
                guard abs(denominator) >= 0.000_001 else {
                    throw ScannerPerspectiveError.singularTransform
                }
                g = (deltaX3 * deltaY2 - deltaX2 * deltaY3)
                    / denominator
                h = (deltaX1 * deltaY3 - deltaX3 * deltaY1)
                    / denominator
            }

            self.a = topRight.x - topLeft.x + g * topRight.x
            self.b = bottomLeft.x - topLeft.x + h * bottomLeft.x
            self.c = topLeft.x
            self.d = topRight.y - topLeft.y + g * topRight.y
            self.e = bottomLeft.y - topLeft.y + h * bottomLeft.y
            self.f = topLeft.y
            self.g = g
            self.h = h
        }

        func map(x: Float, y: Float) throws -> ScannerPixelPoint {
            let denominator = g * x + h * y + 1
            guard abs(denominator) >= 0.000_001 else {
                throw ScannerPerspectiveError.singularTransform
            }
            return ScannerPixelPoint(
                x: (a * x + b * y + c) / denominator,
                y: (d * x + e * y + f) / denominator
            )
        }
    }
}

nonisolated struct PaperEdgeRefinementOutcome: Equatable, Sendable {
    let applied: Bool
    let refinedEdges: String
    let maximumShiftFraction: Float
    let milliseconds: Double

    static func skipped(milliseconds: Double) -> Self {
        Self(
            applied: false,
            refinedEdges: "",
            maximumShiftFraction: 0,
            milliseconds: milliseconds
        )
    }

    var traceDetails: String {
        applied
            ? "paperEdges=\(refinedEdges) "
                + "shift=" + String(
                    format: "%.2f%%",
                    maximumShiftFraction * 100
                )
                + " refineMs=" + String(format: "%.1f", milliseconds)
            : "paperEdges=none refineMs="
                + String(format: "%.1f", milliseconds)
    }
}

actor AndroidPerspectiveCorrector: DocumentPerspectiveCorrecting {
    private let imageBridge = ScannerCIImageBridge()
    private let metalSampler: AndroidMetalImageSampler?
    private(set) var lastWarpBackend: UVDocWarpBackend?
    private(set) var lastPaperEdgeRefinement: PaperEdgeRefinementOutcome?

    init(preferMetalWarp: Bool = true) {
        metalSampler = preferMetalWarp
            ? try? AndroidMetalImageSampler()
            : nil
        lastWarpBackend = nil
    }

    init(metalSampler: AndroidMetalImageSampler?) {
        self.metalSampler = metalSampler
        lastWarpBackend = nil
    }

    func correct(
        _ image: CIImage,
        using quad: DocumentQuad
    ) async throws -> CIImage {
        let source = try imageBridge.rgbaImage(from: image)
        return imageBridge.ciImage(
            from: try correctPixels(source, using: quad)
        )
    }

    func correctPixels(
        _ source: ScannerRGBAImage,
        using quad: DocumentQuad,
        refinePaperEdges: Bool = true
    ) throws -> ScannerRGBAImage {
        let corners = AndroidPerspectiveMath.pixelCorners(
            from: quad,
            imageWidth: source.width,
            imageHeight: source.height
        )
        let outputSize = AndroidPerspectiveMath.outputSize(
            for: corners
        )
        let corrected = try warp(
            source,
            orderedCorners: corners,
            outputSize: outputSize
        )
        guard refinePaperEdges else {
            lastPaperEdgeRefinement = nil
            return corrected
        }

        let startedAt = ProcessInfo.processInfo.systemUptime
        guard let refinement = PaperEdgeRefiner.refine(corrected),
              let refinedCorners = sourceCorners(
                  for: refinement,
                  orderedCorners: corners,
                  outputSize: outputSize,
                  sourceWidth: source.width,
                  sourceHeight: source.height
              ) else {
            lastPaperEdgeRefinement = .skipped(
                milliseconds: ScannerDiagnostics.milliseconds(
                    since: startedAt
                )
            )
            return corrected
        }

        // Re-warp from the source so the page is resampled only once.
        let refinedSize = AndroidPerspectiveMath.outputSize(
            for: refinedCorners
        )
        let refined = try warp(
            source,
            orderedCorners: refinedCorners,
            outputSize: refinedSize
        )
        lastPaperEdgeRefinement = PaperEdgeRefinementOutcome(
            applied: true,
            refinedEdges: refinement.refinedEdges,
            maximumShiftFraction: refinement.maximumShiftFraction,
            milliseconds: ScannerDiagnostics.milliseconds(since: startedAt)
        )
        return refined
    }

    /// Maps the refiner's warped-space quad back into source coordinates and
    /// applies the same 1.5% inset the first warp used.
    private func sourceCorners(
        for refinement: PaperEdgeRefinerResult,
        orderedCorners: [ScannerPixelPoint],
        outputSize: ScannerPixelSize,
        sourceWidth: Int,
        sourceHeight: Int
    ) -> [ScannerPixelPoint]? {
        guard let mapped = try? AndroidPerspectiveMath.sourcePoints(
            for: refinement.corners,
            orderedCorners: orderedCorners,
            outputSize: outputSize
        ) else {
            return nil
        }
        let clamped = mapped.map { point in
            ScannerPixelPoint(
                x: min(max(point.x, 0), Float(sourceWidth - 1)),
                y: min(max(point.y, 0), Float(sourceHeight - 1))
            )
        }
        return AndroidPerspectiveMath.insetCorners(
            AndroidPerspectiveMath.orderCorners(clamped),
            fraction: AndroidPerspectiveMath.captureInsetFraction
        )
    }

    private func warp(
        _ source: ScannerRGBAImage,
        orderedCorners: [ScannerPixelPoint],
        outputSize: ScannerPixelSize
    ) throws -> ScannerRGBAImage {
        if let metalSampler {
            do {
                let warped = try metalSampler.perspectiveWarp(
                    source,
                    orderedCorners: orderedCorners,
                    outputSize: outputSize
                )
                lastWarpBackend = .metal
                return warped
            } catch {
                let warped = try AndroidPerspectiveMath.warp(
                    source,
                    orderedCorners: orderedCorners,
                    outputSize: outputSize
                )
                lastWarpBackend = .cpu
                return warped
            }
        }
        let warped = try AndroidPerspectiveMath.warp(
            source,
            orderedCorners: orderedCorners,
            outputSize: outputSize
        )
        lastWarpBackend = .cpu
        return warped
    }
}
