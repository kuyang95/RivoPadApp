import CoreImage
import CoreVideo
import Foundation
import ImageIO

// The camera adapter must retain this buffer and treat it as read-only for the
// lifetime of every asynchronous detector call.
nonisolated struct DocumentScannerFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let orientation: CGImagePropertyOrientation
    let timestamp: TimeInterval
}

nonisolated protocol DocumentCornerDetecting: AnyObject, Sendable {
    func detect(
        in frame: DocumentScannerFrame
    ) async throws -> DocumentDetection?
}

nonisolated protocol CurvedDocumentDewarping: AnyObject, Sendable {
    func dewarp(_ image: CIImage) async throws -> CIImage
}

nonisolated protocol DocumentPerspectiveCorrecting: AnyObject, Sendable {
    func correct(
        _ image: CIImage,
        using quad: DocumentQuad
    ) async throws -> CIImage
}

nonisolated protocol DocumentImageEnhancing: AnyObject, Sendable {
    func enhance(_ image: CIImage) async throws -> CIImage
}
