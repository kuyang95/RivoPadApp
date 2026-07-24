import CoreGraphics
import Foundation

nonisolated struct ScannerPixelRect: Equatable, Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    var maxX: Int { x + width }
    var maxY: Int { y + height }
}

nonisolated struct ScannerViewportConfiguration: Equatable, Sendable {
    let previewWidth: Double
    let previewHeight: Double
    let previewRotationDegrees: Int
    let generation: Int
}

/// Maps the raw, unrotated sensor raster to a `.resizeAspectFill` preview and
/// derives the same center viewport ROI for LCNet and still-photo processing.
nonisolated struct ScannerViewportTransform: Equatable, Sendable {
    let rawWidth: Int
    let rawHeight: Int
    let previewWidth: Double
    let previewHeight: Double
    let rotationDegrees: Int
    let rawCropRect: ScannerPixelRect

    private let scale: Double
    private let offsetX: Double
    private let offsetY: Double

    init?(
        rawWidth: Int,
        rawHeight: Int,
        configuration: ScannerViewportConfiguration
    ) {
        guard rawWidth > 0,
              rawHeight > 0,
              configuration.previewWidth > 0,
              configuration.previewHeight > 0 else {
            return nil
        }

        let rotation = Self.cardinalDegrees(
            configuration.previewRotationDegrees
        )
        let swapsDimensions = rotation == 90 || rotation == 270
        let rotatedWidth = Double(
            swapsDimensions ? rawHeight : rawWidth
        )
        let rotatedHeight = Double(
            swapsDimensions ? rawWidth : rawHeight
        )
        let scale = max(
            configuration.previewWidth / rotatedWidth,
            configuration.previewHeight / rotatedHeight
        )
        let scaledWidth = rotatedWidth * scale
        let scaledHeight = rotatedHeight * scale
        let offsetX = (configuration.previewWidth - scaledWidth) / 2
        let offsetY = (configuration.previewHeight - scaledHeight) / 2

        let visibleRotatedMinimumX = max(-offsetX / scale, 0)
        let visibleRotatedMinimumY = max(-offsetY / scale, 0)
        let visibleRotatedMaximumX = min(
            (configuration.previewWidth - offsetX) / scale,
            rotatedWidth
        )
        let visibleRotatedMaximumY = min(
            (configuration.previewHeight - offsetY) / scale,
            rotatedHeight
        )
        let rotatedCorners = [
            CGPoint(
                x: visibleRotatedMinimumX,
                y: visibleRotatedMinimumY
            ),
            CGPoint(
                x: visibleRotatedMaximumX,
                y: visibleRotatedMinimumY
            ),
            CGPoint(
                x: visibleRotatedMaximumX,
                y: visibleRotatedMaximumY
            ),
            CGPoint(
                x: visibleRotatedMinimumX,
                y: visibleRotatedMaximumY
            )
        ]
        let rawCorners = rotatedCorners.map {
            Self.inverseRotate(
                $0,
                rawWidth: Double(rawWidth),
                rawHeight: Double(rawHeight),
                degrees: rotation
            )
        }
        let minimumX = max(
            Int(floor(Self.stabilizedPixelCoordinate(
                rawCorners.map(\.x).min() ?? 0
            ))),
            0
        )
        let minimumY = max(
            Int(floor(Self.stabilizedPixelCoordinate(
                rawCorners.map(\.y).min() ?? 0
            ))),
            0
        )
        let maximumX = min(
            Int(ceil(Self.stabilizedPixelCoordinate(
                rawCorners.map(\.x).max() ?? CGFloat(rawWidth)
            ))),
            rawWidth
        )
        let maximumY = min(
            Int(ceil(Self.stabilizedPixelCoordinate(
                rawCorners.map(\.y).max() ?? CGFloat(rawHeight)
            ))),
            rawHeight
        )
        guard maximumX > minimumX, maximumY > minimumY else {
            return nil
        }

        self.rawWidth = rawWidth
        self.rawHeight = rawHeight
        self.previewWidth = configuration.previewWidth
        self.previewHeight = configuration.previewHeight
        self.rotationDegrees = rotation
        self.rawCropRect = ScannerPixelRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
        self.scale = scale
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    func previewPoint(
        for normalizedCropPoint: NormalizedPoint
    ) -> CGPoint {
        let rawPoint = CGPoint(
            x: Double(rawCropRect.x)
                + normalizedCropPoint.x * Double(rawCropRect.width),
            y: Double(rawCropRect.y)
                + normalizedCropPoint.y * Double(rawCropRect.height)
        )
        let rotated = Self.rotate(
            rawPoint,
            rawWidth: Double(rawWidth),
            rawHeight: Double(rawHeight),
            degrees: rotationDegrees
        )
        return CGPoint(
            x: rotated.x * scale + offsetX,
            y: rotated.y * scale + offsetY
        )
    }

    static func cardinalDegrees(_ degrees: Int) -> Int {
        let normalized = ((degrees % 360) + 360) % 360
        return ((normalized + 45) / 90 * 90) % 360
    }

    static func displayGuidance(
        for sensorGuidance: DocumentFramingGuidance,
        rotationDegrees: Int
    ) -> DocumentFramingGuidance {
        switch (
            cardinalDegrees(rotationDegrees),
            sensorGuidance
        ) {
        case (_, .moveCloser), (_, .moveFarther):
            return sensorGuidance

        case (90, .moveLeft):
            return .moveUp
        case (90, .moveRight):
            return .moveDown
        case (90, .moveUp):
            return .moveRight
        case (90, .moveDown):
            return .moveLeft

        case (180, .moveLeft):
            return .moveRight
        case (180, .moveRight):
            return .moveLeft
        case (180, .moveUp):
            return .moveDown
        case (180, .moveDown):
            return .moveUp

        case (270, .moveLeft):
            return .moveDown
        case (270, .moveRight):
            return .moveUp
        case (270, .moveUp):
            return .moveLeft
        case (270, .moveDown):
            return .moveRight

        default:
            return sensorGuidance
        }
    }

    private static func stabilizedPixelCoordinate(
        _ value: CGFloat
    ) -> CGFloat {
        let nearestInteger = value.rounded()
        return abs(value - nearestInteger) < 0.000_001
            ? nearestInteger
            : value
    }

    private static func rotate(
        _ point: CGPoint,
        rawWidth: Double,
        rawHeight: Double,
        degrees: Int
    ) -> CGPoint {
        switch degrees {
        case 90:
            return CGPoint(x: rawHeight - point.y, y: point.x)
        case 180:
            return CGPoint(
                x: rawWidth - point.x,
                y: rawHeight - point.y
            )
        case 270:
            return CGPoint(x: point.y, y: rawWidth - point.x)
        default:
            return point
        }
    }

    private static func inverseRotate(
        _ point: CGPoint,
        rawWidth: Double,
        rawHeight: Double,
        degrees: Int
    ) -> CGPoint {
        switch degrees {
        case 90:
            return CGPoint(x: point.y, y: rawHeight - point.x)
        case 180:
            return CGPoint(
                x: rawWidth - point.x,
                y: rawHeight - point.y
            )
        case 270:
            return CGPoint(x: rawWidth - point.y, y: point.x)
        default:
            return point
        }
    }
}

extension ScannerRGBAImage {
    nonisolated func cropped(
        to rect: ScannerPixelRect
    ) throws -> ScannerRGBAImage {
        guard rect.x >= 0,
              rect.y >= 0,
              rect.width > 0,
              rect.height > 0,
              rect.maxX <= width,
              rect.maxY <= height else {
            throw ScannerImageError.invalidDimensions(
                width: rect.width,
                height: rect.height
            )
        }

        let destinationBytesPerRow = rect.width * 4
        var output = [UInt8](
            repeating: 0,
            count: destinationBytesPerRow * rect.height
        )
        for destinationY in 0 ..< rect.height {
            let sourceStart = byteOffset(
                x: rect.x,
                y: rect.y + destinationY
            )
            let destinationStart =
                destinationY * destinationBytesPerRow
            output.replaceSubrange(
                destinationStart
                    ..< destinationStart + destinationBytesPerRow,
                with: bytes[
                    sourceStart
                        ..< sourceStart + destinationBytesPerRow
                ]
            )
        }
        return try ScannerRGBAImage(
            width: rect.width,
            height: rect.height,
            bytes: output
        )
    }
}

/// Thread-safe KEEP_ONLY_LATEST gate used directly from the camera output
/// queue. It also snapshots viewport generation so stale rotation results can
/// be discarded when the async detector returns.
nonisolated final class ScannerFrameAdmissionController: @unchecked Sendable {
    private let lock = NSLock()
    private let minimumInterval: TimeInterval
    private var configuration: ScannerViewportConfiguration?
    private var lastAcceptedTimestamp: TimeInterval = 0
    private var busy = false
    private var generation = 0

    init(framesPerSecond: Int) {
        minimumInterval = 1 / Double(max(framesPerSecond, 1))
    }

    func update(
        previewWidth: Double,
        previewHeight: Double,
        rotationDegrees: Int
    ) {
        lock.lock()
        defer { lock.unlock() }
        let cardinal = ScannerViewportTransform.cardinalDegrees(
            rotationDegrees
        )
        let changed =
            configuration?.previewWidth != previewWidth
            || configuration?.previewHeight != previewHeight
            || configuration?.previewRotationDegrees != cardinal
        if changed {
            generation += 1
        }
        configuration = ScannerViewportConfiguration(
            previewWidth: previewWidth,
            previewHeight: previewHeight,
            previewRotationDegrees: cardinal,
            generation: generation
        )
    }

    func beginFrame(
        timestamp: TimeInterval
    ) -> ScannerViewportConfiguration? {
        lock.lock()
        defer { lock.unlock() }
        guard !busy,
              let configuration,
              timestamp - lastAcceptedTimestamp >= minimumInterval else {
            return nil
        }
        busy = true
        lastAcceptedTimestamp = timestamp
        return configuration
    }

    func finishFrame() {
        lock.lock()
        busy = false
        lock.unlock()
    }

    func invalidateViewport() {
        lock.lock()
        generation += 1
        configuration = nil
        lock.unlock()
    }

    func isCurrent(generation expected: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == expected
    }

    func currentConfiguration() -> ScannerViewportConfiguration? {
        lock.lock()
        defer { lock.unlock() }
        return configuration
    }
}
