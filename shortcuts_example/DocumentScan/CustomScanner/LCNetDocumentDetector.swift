import CoreImage
import CoreVideo
import Foundation

nonisolated enum LCNetHeatmapDecoder {
    static let threshold: Float = 0.15
    static let refinementRadius = 3

    private struct HeatmapCorner {
        let x: Float
        let y: Float
        let confidence: Float
    }

    static func decode(
        _ heatmap: ScannerFloatTensor,
        letterbox: ScannerLetterboxTransform
    ) throws -> DocumentDetection? {
        guard heatmap.shape.count == 4 else {
            throw ScannerModelError.outputShapeMismatch(
                expected: ScannerModelDescriptor.documentAligner.outputShape,
                actual: heatmap.shape
            )
        }

        let channels = heatmap.shape[1]
        let height = heatmap.shape[2]
        let width = heatmap.shape[3]
        guard channels >= 4, height > 0, width > 0 else {
            throw ScannerModelError.outputShapeMismatch(
                expected: ScannerModelDescriptor.documentAligner.outputShape,
                actual: heatmap.shape
            )
        }

        var normalizedCorners = [NormalizedPoint]()
        normalizedCorners.reserveCapacity(4)
        var totalConfidence: Float = 0

        for channel in 0 ..< 4 {
            guard let corner = extractCorner(
                values: heatmap.values,
                channel: channel,
                height: height,
                width: width
            ) else {
                return nil
            }

            let letterboxX =
                corner.x / Float(width) * Float(letterbox.canvasSize)
            let letterboxY =
                corner.y / Float(height) * Float(letterbox.canvasSize)
            let originalX =
                (letterboxX - Float(letterbox.padX))
                / Float(letterbox.scaledWidth)
                * Float(letterbox.originalWidth)
            let originalY =
                (letterboxY - Float(letterbox.padY))
                / Float(letterbox.scaledHeight)
                * Float(letterbox.originalHeight)

            // Deliberately do not clamp. Android lets the framing gate reject
            // a peak that falls in the letterbox padding.
            normalizedCorners.append(
                NormalizedPoint(
                    x: Double(originalX / Float(letterbox.originalWidth)),
                    y: Double(originalY / Float(letterbox.originalHeight))
                )
            )
            totalConfidence += corner.confidence
        }

        let averageConfidence = totalConfidence / 4
        guard averageConfidence >= threshold else {
            return nil
        }

        return DocumentDetection(
            quad: DocumentQuad(
                topLeft: normalizedCorners[0],
                topRight: normalizedCorners[1],
                bottomRight: normalizedCorners[2],
                bottomLeft: normalizedCorners[3]
            ),
            confidence: Double(averageConfidence)
        )
    }

    private static func extractCorner(
        values: [Float],
        channel: Int,
        height: Int,
        width: Int
    ) -> HeatmapCorner? {
        let offset = channel * height * width
        var maximumValue: Float = 0
        var maximumX = 0
        var maximumY = 0

        for y in 0 ..< height {
            for x in 0 ..< width {
                let value = values[offset + y * width + x]
                if value > maximumValue {
                    maximumValue = value
                    maximumX = x
                    maximumY = y
                }
            }
        }

        guard maximumValue >= threshold else {
            return nil
        }

        // Kotlin uses Double accumulators here, so keep the same precision
        // instead of accumulating the weighted centroid as Float.
        var weightedX = 0.0
        var weightedY = 0.0
        var totalWeight = 0.0
        for deltaY in -refinementRadius ... refinementRadius {
            for deltaX in -refinementRadius ... refinementRadius {
                let x = maximumX + deltaX
                let y = maximumY + deltaY
                guard x >= 0, x < width, y >= 0, y < height else {
                    continue
                }

                let value = values[offset + y * width + x]
                guard value > threshold else {
                    continue
                }
                weightedX += Double(x) * Double(value)
                weightedY += Double(y) * Double(value)
                totalWeight += Double(value)
            }
        }

        return HeatmapCorner(
            x: totalWeight > 0 ? Float(weightedX / totalWeight) : Float(maximumX),
            y: totalWeight > 0 ? Float(weightedY / totalWeight) : Float(maximumY),
            confidence: maximumValue
        )
    }
}

/// LCNet100 corner detector with the VisionCraft Android preprocessing and
/// heatmap decoder contract.
actor LCNetDocumentDetector: DocumentCornerDetecting {
    nonisolated let backend: ScannerInferenceBackend

    private let session: ScannerONNXSession
    private let imageBridge = ScannerCIImageBridge()

    init(
        bundle: Bundle = .main,
        backend: ScannerInferenceBackend = .coreML
    ) throws {
        let session = try ScannerONNXSession(
            descriptor: .documentAligner,
            bundle: bundle,
            backend: backend
        )
        self.backend = session.activeBackend
        self.session = session
    }

    init(
        modelURL: URL,
        backend: ScannerInferenceBackend = .coreML
    ) throws {
        let session = try ScannerONNXSession(
            descriptor: .documentAligner,
            modelURL: modelURL,
            backend: backend
        )
        self.backend = session.activeBackend
        self.session = session
    }

    func detect(
        in frame: DocumentScannerFrame
    ) async throws -> DocumentDetection? {
        let fullSource: ScannerRGBAImage
        do {
            return try await detect(
                in: ScannerRGBAImage.readingBGRA(
                    frame.pixelBuffer,
                    cropRect: frame.cropRect
                )
            )
        } catch ScannerImageError.unsupportedPixelFormat(_) {
            fullSource = try imageBridge.rgbaImage(
                from: CIImage(cvPixelBuffer: frame.pixelBuffer)
            )
        }

        let source: ScannerRGBAImage
        if let cropRect = frame.cropRect {
            source = try fullSource.cropped(to: cropRect)
        } else {
            source = fullSource
        }

        // Android runs LCNet in the sensor/crop coordinate space and applies
        // frame.orientation only when drawing its overlay. Do the same here.
        return try await detect(in: source)
    }

    func detect(
        in image: CIImage
    ) async throws -> DocumentDetection? {
        try await detect(in: imageBridge.rgbaImage(from: image))
    }

    func detect(
        in source: ScannerRGBAImage
    ) async throws -> DocumentDetection? {
        let prepared = AndroidScannerImageMath.letterboxedRGBTensor(
            from: source,
            size: 256
        )
        return try await detect(prepared: prepared)
    }

    func detect(
        prepared: ScannerPreparedTensor
    ) async throws -> DocumentDetection? {
        guard let letterbox = prepared.letterbox else {
            return nil
        }
        let output = try await session.run(
            ScannerFloatTensor(
                values: prepared.values,
                shape: prepared.shape
            )
        )
        return try LCNetHeatmapDecoder.decode(
            output,
            letterbox: letterbox
        )
    }
}
