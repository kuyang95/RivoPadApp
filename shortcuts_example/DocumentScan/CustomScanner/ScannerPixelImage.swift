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
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard format == kCVPixelFormatType_32BGRA else {
            throw ScannerImageError.unsupportedPixelFormat(format)
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
        let rect = cropRect ?? ScannerPixelRect(
            x: 0,
            y: 0,
            width: bufferWidth,
            height: bufferHeight
        )
        guard rect.x >= 0,
              rect.y >= 0,
              rect.width > 0,
              rect.height > 0,
              rect.maxX <= bufferWidth,
              rect.maxY <= bufferHeight else {
            throw ScannerImageError.invalidDimensions(
                width: rect.width,
                height: rect.height
            )
        }
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let source = baseAddress.assumingMemoryBound(to: UInt8.self)
        var rgba = [UInt8](
            repeating: 0,
            count: rect.width * rect.height * 4
        )

        for destinationY in 0 ..< rect.height {
            let sourceRow =
                source + ((rect.y + destinationY) * sourceBytesPerRow)
            let destinationRow = destinationY * rect.width * 4
            for destinationX in 0 ..< rect.width {
                let sourceOffset = (rect.x + destinationX) * 4
                let destinationOffset =
                    destinationRow + destinationX * 4
                rgba[destinationOffset] =
                    sourceRow[sourceOffset + 2]
                rgba[destinationOffset + 1] =
                    sourceRow[sourceOffset + 1]
                rgba[destinationOffset + 2] =
                    sourceRow[sourceOffset]
                rgba[destinationOffset + 3] = sourceRow[sourceOffset + 3]
            }
        }

        return try Self(
            width: rect.width,
            height: rect.height,
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
