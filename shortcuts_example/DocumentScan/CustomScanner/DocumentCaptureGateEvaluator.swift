import Foundation

/// Android-compatible capture gates kept independent from AVFoundation so the
/// camera adapter can be thin and the decision logic can be regression-tested.
nonisolated struct DocumentCaptureGateEvaluator {
    private static let fullyVisibleMargin = 0.01
    private static let minimumDocumentArea = 0.12
    private static let maximumDocumentArea = 0.92

    let configuration: CustomDocumentScannerConfiguration
    private var cornerHistory: [[ScannerPixelPoint]] = []

    init(
        configuration: CustomDocumentScannerConfiguration = .androidParitySeed
    ) {
        self.configuration = configuration
    }

    mutating func evaluate(
        detection: DocumentDetection?,
        imageWidth: Int,
        imageHeight: Int,
        sharpness: Double,
        deviceStill: Bool,
        focusReady: Bool
    ) -> CaptureGateSnapshot {
        guard let detection, imageWidth > 0, imageHeight > 0 else {
            reset()
            return CaptureGateSnapshot(
                detection: nil,
                framingGuidance: nil,
                cornersStable: false,
                deviceStill: deviceStill,
                sharpEnough: false,
                focusReady: focusReady
            )
        }

        let guidance = framingGuidance(for: detection.quad)
        let cornersStable: Bool
        if guidance == nil {
            cornersStable = updateCornerStability(
                detection.quad,
                imageWidth: imageWidth,
                imageHeight: imageHeight
            )
        } else {
            cornerHistory.removeAll(keepingCapacity: true)
            cornersStable = false
        }

        return CaptureGateSnapshot(
            detection: detection,
            framingGuidance: guidance,
            cornersStable: cornersStable,
            deviceStill: deviceStill,
            sharpEnough:
                sharpness >= configuration.laplacianSharpnessThreshold,
            focusReady: focusReady
        )
    }

    mutating func reset() {
        cornerHistory.removeAll(keepingCapacity: true)
    }

    private func framingGuidance(
        for quad: DocumentQuad
    ) -> DocumentFramingGuidance? {
        if quad.normalizedArea < Self.minimumDocumentArea {
            return .moveCloser
        }
        if quad.normalizedArea > Self.maximumDocumentArea {
            return .moveFarther
        }

        let points = quad.points
        let margin = Self.fullyVisibleMargin
        func isInside(_ point: NormalizedPoint) -> Bool {
            point.x >= margin
                && point.x <= 1 - margin
                && point.y >= margin
                && point.y <= 1 - margin
        }

        let topVisible = [quad.topLeft, quad.topRight]
            .filter(isInside).count
        let rightVisible = [quad.topRight, quad.bottomRight]
            .filter(isInside).count
        let bottomVisible = [quad.bottomLeft, quad.bottomRight]
            .filter(isInside).count
        let leftVisible = [quad.topLeft, quad.bottomLeft]
            .filter(isInside).count

        if rightVisible == 2, leftVisible < 2 {
            return .moveLeft
        }
        if leftVisible == 2, rightVisible < 2 {
            return .moveRight
        }
        if bottomVisible == 2, topVisible < 2 {
            return .moveUp
        }
        if topVisible == 2, bottomVisible < 2 {
            return .moveDown
        }

        let overflow: [(DocumentFramingGuidance, Double)] = [
            (.moveLeft, points.reduce(0) {
                $0 + max(margin - $1.x, 0)
            }),
            (.moveRight, points.reduce(0) {
                $0 + max($1.x - (1 - margin), 0)
            }),
            (.moveUp, points.reduce(0) {
                $0 + max(margin - $1.y, 0)
            }),
            (.moveDown, points.reduce(0) {
                $0 + max($1.y - (1 - margin), 0)
            })
        ]
        guard let strongest = overflow.max(by: { $0.1 < $1.1 }),
              strongest.1 > 0 else {
            return nil
        }
        return strongest.0
    }

    private mutating func updateCornerStability(
        _ quad: DocumentQuad,
        imageWidth: Int,
        imageHeight: Int
    ) -> Bool {
        let pixels = quad.points.map {
            ScannerPixelPoint(
                x: Float($0.x * Double(imageWidth)),
                y: Float($0.y * Double(imageHeight))
            )
        }
        cornerHistory.append(pixels)
        if cornerHistory.count > configuration.stableFrameCount {
            cornerHistory.removeFirst()
        }
        guard cornerHistory.count >= configuration.stableFrameCount else {
            return false
        }

        for cornerIndex in 0 ..< 4 {
            let meanX = cornerHistory.reduce(0.0) {
                $0 + Double($1[cornerIndex].x)
            } / Double(cornerHistory.count)
            let meanY = cornerHistory.reduce(0.0) {
                $0 + Double($1[cornerIndex].y)
            } / Double(cornerHistory.count)
            let variance = cornerHistory.reduce(0.0) { partial, frame in
                let deltaX = Double(frame[cornerIndex].x) - meanX
                let deltaY = Double(frame[cornerIndex].y) - meanY
                return partial + deltaX * deltaX + deltaY * deltaY
            } / Double(cornerHistory.count)
            if sqrt(variance)
                > configuration.cornerStandardDeviationPixels {
                return false
            }
        }
        return true
    }
}

/// Laplacian variance used by VisionCraft Android, including the same 96×64
/// bilinear downsample, integer RGB luminance, and four-neighbour kernel.
nonisolated enum AndroidScannerFrameQuality {
    static func laplacianVariance(
        of image: ScannerRGBAImage,
        sampleWidth: Int = 96,
        sampleHeight: Int = 64
    ) -> Double {
        guard sampleWidth >= 3, sampleHeight >= 3 else {
            return 0
        }
        let sample = AndroidScannerImageMath.resizeBilinear(
            image,
            width: sampleWidth,
            height: sampleHeight
        )
        var grayscale = [Int](
            repeating: 0,
            count: sampleWidth * sampleHeight
        )
        for pixelIndex in grayscale.indices {
            let offset = pixelIndex * 4
            let red = Int(sample.bytes[offset])
            let green = Int(sample.bytes[offset + 1])
            let blue = Int(sample.bytes[offset + 2])
            grayscale[pixelIndex] =
                (red * 299 + green * 587 + blue * 114) / 1_000
        }

        var count = 0.0
        var mean = 0.0
        var squaredDifferenceSum = 0.0
        for y in 1 ..< sampleHeight - 1 {
            let row = y * sampleWidth
            for x in 1 ..< sampleWidth - 1 {
                let center = grayscale[row + x]
                let laplacian =
                    grayscale[row - sampleWidth + x]
                    + grayscale[row + sampleWidth + x]
                    + grayscale[row + x - 1]
                    + grayscale[row + x + 1]
                    - 4 * center
                count += 1
                let value = Double(laplacian)
                let delta = value - mean
                mean += delta / count
                squaredDifferenceSum += delta * (value - mean)
            }
        }
        return count < 2 ? 0 : squaredDifferenceSum / count
    }
}
