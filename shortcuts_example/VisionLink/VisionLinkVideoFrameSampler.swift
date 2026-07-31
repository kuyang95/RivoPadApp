import CoreImage
import Foundation
import ImageIO
@preconcurrency import StreamWebRTC

nonisolated final class
    VisionLinkVideoFrameSampler:
    NSObject,
    RTCVideoRenderer,
    @unchecked Sendable
{
    typealias ResultHandler =
        @MainActor @Sendable
            (Result<CGImage, Error>) -> Void

    private let lock = NSLock()
    private let conversionQueue =
        DispatchQueue(
            label:
                "net.rivo.visionlink.live-reading-frame",
            qos: .userInitiated
        )
    private let handler: ResultHandler
    private var frameRequested = false
    private var generation = 0

    init(
        handler: @escaping ResultHandler
    ) {
        self.handler = handler
        super.init()
    }

    func requestFrame() {
        lock.lock()
        frameRequested = true
        lock.unlock()
    }

    func cancelRequest() {
        lock.lock()
        frameRequested = false
        generation &+= 1
        lock.unlock()
    }

    func setSize(_ size: CGSize) {}

    func renderFrame(
        _ frame: RTCVideoFrame?
    ) {
        guard let frame else {
            return
        }

        lock.lock()
        guard frameRequested else {
            lock.unlock()
            return
        }
        frameRequested = false
        let requestedGeneration = generation
        lock.unlock()

        conversionQueue.async { [weak self] in
            guard let self else {
                return
            }
            let result = Result {
                try Self.makeCGImage(
                    from: frame
                )
            }
            guard self.isCurrent(
                requestedGeneration
            ) else {
                return
            }
            Task { @MainActor in
                self.handler(result)
            }
        }
    }

    private func isCurrent(
        _ requestedGeneration: Int
    ) -> Bool {
        lock.lock()
        let current =
            requestedGeneration == generation
        lock.unlock()
        return current
    }

    private static func makeCGImage(
        from frame: RTCVideoFrame
    ) throws -> CGImage {
        let converter = RTCVideoFrameConverter()
        guard let pixelBuffer =
                converter.copyPixelBuffer(
                    from: frame,
                    targetSize: .zero
                )
        else {
            throw VisionLinkVideoFrameSamplerError
                .conversionFailed
        }

        let source = CIImage(
            cvPixelBuffer: pixelBuffer
        )
        let oriented = source.oriented(
            orientation(for: frame.rotation)
        )
        let context = CIContext(
            options: [
                .cacheIntermediates: false,
            ]
        )
        guard let image = context.createCGImage(
            oriented,
            from: oriented.extent
        ) else {
            throw VisionLinkVideoFrameSamplerError
                .conversionFailed
        }
        return image
    }

    private static func orientation(
        for rotation: RTCVideoRotation
    ) -> CGImagePropertyOrientation {
        switch rotation {
        case ._0:
            return .up
        case ._90:
            return .right
        case ._180:
            return .down
        case ._270:
            return .left
        @unknown default:
            return .up
        }
    }
}

nonisolated enum
    VisionLinkVideoFrameSamplerError:
    Error,
    LocalizedError,
    Equatable
{
    case conversionFailed

    var errorDescription: String? {
        AppLocalization.string(
            "카메라 화면을 읽을 이미지로 변환하지 못했습니다."
        )
    }
}
