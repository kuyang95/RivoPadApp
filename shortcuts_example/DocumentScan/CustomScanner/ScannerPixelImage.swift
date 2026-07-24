import CoreImage
import CoreVideo
import Foundation

nonisolated enum ScannerImageError: Error, Equatable, Sendable {
    case invalidDimensions(width: Int, height: Int)
    case invalidByteCount(expected: Int, actual: Int)
    case unsupportedPixelFormat(OSType)
    case pixelBufferLockFailed(CVReturn)
    case missingPixelBufferBaseAddress
    case imageHasInfiniteExtent
}

/// An explicitly top-left-origin, row-major RGBA8 image.
///
/// Core Image uses a bottom-left coordinate system while camera buffers and
/// the Android scanner use a top-left origin. Keeping that distinction in one
/// value type prevents implicit flips in the model and perspective pipelines.
nonisolated struct ScannerRGBAImage: Equatable, Sendable {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    init(width: Int, height: Int, bytes: [UInt8]) throws {
        guard width > 0, height > 0 else {
            throw ScannerImageError.invalidDimensions(
                width: width,
                height: height
            )
        }

        let expectedByteCount = width * height * 4
        guard bytes.count == expectedByteCount else {
            throw ScannerImageError.invalidByteCount(
                expected: expectedByteCount,
                actual: bytes.count
            )
        }

        self.width = width
        self.height = height
        self.bytes = bytes
    }

    func byteOffset(x: Int, y: Int) -> Int {
        ((y * width) + x) * 4
    }

    /// CameraX feeds Android's detector a rotation-free RGBA crop. This reads
    /// iOS BGRA camera memory into the same logical top-left RGB pixel order.
    static func readingBGRA(_ pixelBuffer: CVPixelBuffer) throws -> Self {
        try readingBGRA(pixelBuffer, cropRect: nil)
    }

    /// Reads only the viewport ROI when supplied, avoiding a full-frame RGBA
    /// allocation followed by a second crop copy on every analysis frame.
    static func readingBGRA(
        _ pixelBuffer: CVPixelBuffer,
        cropRect: ScannerPixelRect?
    ) throws -> Self {
        let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
        let rect = cropRect ?? ScannerPixelRect(
            x: 0,
            y: 0,
            width: bufferWidth,
            height: bufferHeight
        )
        return try readingBGRA(
            pixelBuffer,
            cropRect: rect,
            outputWidth: rect.width,
            outputHeight: rect.height
        )
    }

    /// Samples a camera ROI directly into a bounded RGBA image instead of
    /// allocating and converting every source pixel first.
    static func readingBGRA(
        _ pixelBuffer: CVPixelBuffer,
        cropRect: ScannerPixelRect,
        maximumLongEdge: Int
    ) throws -> Self {
        guard maximumLongEdge > 0 else {
            throw ScannerImageError.invalidDimensions(
                width: maximumLongEdge,
                height: maximumLongEdge
            )
        }
        let sourceLongEdge = max(cropRect.width, cropRect.height)
        guard sourceLongEdge > 0 else {
            throw ScannerImageError.invalidDimensions(
                width: cropRect.width,
                height: cropRect.height
            )
        }
        let scale = min(
            Float(maximumLongEdge) / Float(sourceLongEdge),
            1
        )
        return try readingBGRA(
            pixelBuffer,
            cropRect: cropRect,
            outputWidth: max(Int(Float(cropRect.width) * scale), 1),
            outputHeight: max(Int(Float(cropRect.height) * scale), 1)
        )
    }

    /// Half-pixel-center bilinear BGRA-to-RGBA sampling with edge replication.
    /// This matches `AndroidScannerImageMath.resizeBilinear` without creating
    /// the full-resolution intermediate camera image.
    static func readingBGRA(
        _ pixelBuffer: CVPixelBuffer,
        cropRect: ScannerPixelRect,
        outputWidth: Int,
        outputHeight: Int
    ) throws -> Self {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard format == kCVPixelFormatType_32BGRA else {
            throw ScannerImageError.unsupportedPixelFormat(format)
        }
        guard outputWidth > 0, outputHeight > 0 else {
            throw ScannerImageError.invalidDimensions(
                width: outputWidth,
                height: outputHeight
            )
        }

        let lockResult = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        guard lockResult == kCVReturnSuccess else {
            throw ScannerImageError.pixelBufferLockFailed(lockResult)
        }
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw ScannerImageError.missingPixelBufferBaseAddress
        }

        let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard cropRect.x >= 0,
              cropRect.y >= 0,
              cropRect.width > 0,
              cropRect.height > 0,
              cropRect.maxX <= bufferWidth,
              cropRect.maxY <= bufferHeight else {
            throw ScannerImageError.invalidDimensions(
                width: cropRect.width,
                height: cropRect.height
            )
        }
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let source = baseAddress.assumingMemoryBound(to: UInt8.self)
        var rgba = [UInt8](
            repeating: 0,
            count: outputWidth * outputHeight * 4
        )
        let sourceMaximumX = Float(cropRect.width - 1)
        let sourceMaximumY = Float(cropRect.height - 1)
        let xScale = Float(cropRect.width) / Float(outputWidth)
        let yScale = Float(cropRect.height) / Float(outputHeight)
        let sourceChannels = [2, 1, 0, 3]

        for destinationY in 0 ..< outputHeight {
            let mappedY = min(
                max(
                    (Float(destinationY) + 0.5) * yScale - 0.5,
                    0
                ),
                sourceMaximumY
            )
            let sourceY0 = Int(mappedY)
            let sourceY1 = min(sourceY0 + 1, cropRect.height - 1)
            let yWeight = mappedY - Float(sourceY0)
            let topRow = source + (
                (cropRect.y + sourceY0) * sourceBytesPerRow
            )
            let bottomRow = source + (
                (cropRect.y + sourceY1) * sourceBytesPerRow
            )
            let destinationRow = destinationY * outputWidth * 4

            for destinationX in 0 ..< outputWidth {
                let mappedX = min(
                    max(
                        (Float(destinationX) + 0.5) * xScale - 0.5,
                        0
                    ),
                    sourceMaximumX
                )
                let sourceX0 = Int(mappedX)
                let sourceX1 = min(sourceX0 + 1, cropRect.width - 1)
                let xWeight = mappedX - Float(sourceX0)
                let leftOffset = (cropRect.x + sourceX0) * 4
                let rightOffset = (cropRect.x + sourceX1) * 4
                let destinationOffset =
                    destinationRow + destinationX * 4
                let weight00 = (1 - xWeight) * (1 - yWeight)
                let weight01 = xWeight * (1 - yWeight)
                let weight10 = (1 - xWeight) * yWeight
                let weight11 = xWeight * yWeight

                for destinationChannel in 0 ..< 4 {
                    let sourceChannel =
                        sourceChannels[destinationChannel]
                    let value =
                        weight00 * Float(
                            topRow[leftOffset + sourceChannel]
                        )
                        + weight01 * Float(
                            topRow[rightOffset + sourceChannel]
                        )
                        + weight10 * Float(
                            bottomRow[leftOffset + sourceChannel]
                        )
                        + weight11 * Float(
                            bottomRow[rightOffset + sourceChannel]
                        )
                    rgba[destinationOffset + destinationChannel] = UInt8(
                        clamping: Int(value.rounded())
                    )
                }
            }
        }

        return try Self(
            width: outputWidth,
            height: outputHeight,
            bytes: rgba
        )
    }
}

/// Centralizes Core Image rasterization into the scanner's explicitly
/// top-left, row-major pixel representation. Core Image's geometry APIs use a
/// bottom-left origin, but its bitmap APIs expose the first memory row as the
/// visual top row, so no extra row reversal belongs at this boundary.
nonisolated final class ScannerCIImageBridge: @unchecked Sendable {
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    init(context: CIContext = CIContext(options: [
        .cacheIntermediates: false
    ])) {
        self.context = context
    }

    func rgbaImage(from image: CIImage) throws -> ScannerRGBAImage {
        let extent = image.extent.integral
        guard !extent.isInfinite else {
            throw ScannerImageError.imageHasInfiniteExtent
        }

        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, height > 0 else {
            throw ScannerImageError.invalidDimensions(
                width: width,
                height: height
            )
        }

        let translated = image.transformed(
            by: CGAffineTransform(
                translationX: -extent.minX,
                y: -extent.minY
            )
        )
        let bytesPerRow = width * 4
        var rgba = [UInt8](repeating: 0, count: bytesPerRow * height)

        rgba.withUnsafeMutableBytes { storage in
            guard let baseAddress = storage.baseAddress else {
                return
            }
            context.render(
                translated,
                toBitmap: baseAddress,
                rowBytes: bytesPerRow,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }

        return try ScannerRGBAImage(
            width: width,
            height: height,
            bytes: rgba
        )
    }

    func ciImage(from image: ScannerRGBAImage) -> CIImage {
        let bytesPerRow = image.width * 4
        return CIImage(
            bitmapData: Data(image.bytes),
            bytesPerRow: bytesPerRow,
            size: CGSize(width: image.width, height: image.height),
            format: .RGBA8,
            colorSpace: colorSpace
        )
    }
}
