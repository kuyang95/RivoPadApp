import CoreImage
import Foundation

/// Static captured-page pipeline. Live camera gates remain independent so a
/// slow UVDoc pass can never block preview analysis.
actor AndroidParityDocumentProcessor {
    nonisolated let requestedInferenceBackend: ScannerInferenceBackend
    private(set) var inferenceBackend: ScannerInferenceBackend?
    private(set) var dewarperLoadErrorDescription: String?

    private let perspectiveCorrector: any DocumentPerspectiveCorrecting
    private var dewarper: (any CurvedDocumentDewarping)?
    private let enhancer: any DocumentImageEnhancing
    private let imageBridge = ScannerCIImageBridge()
    private let metalImageSampler: AndroidMetalImageSampler?
    private let outputLongEdgePixels: Int
    private let modelBundle: Bundle?
    private var dewarperInitializationAttempted: Bool

    init(
        bundle: Bundle = .main,
        backend: ScannerInferenceBackend = .coreML,
        outputLongEdgePixels: Int = 2_400
    ) {
        let metalImageSampler = try? AndroidMetalImageSampler()
        self.requestedInferenceBackend = backend
        self.inferenceBackend = nil
        self.dewarperLoadErrorDescription = nil
        self.perspectiveCorrector = AndroidPerspectiveCorrector(
            metalSampler: metalImageSampler
        )
        self.dewarper = nil
        self.enhancer = AndroidDocumentColorEnhancer(
            metalSampler: metalImageSampler
        )
        self.metalImageSampler = metalImageSampler
        self.outputLongEdgePixels = outputLongEdgePixels
        self.modelBundle = bundle
        self.dewarperInitializationAttempted = false
    }

    init(
        perspectiveCorrector: any DocumentPerspectiveCorrecting,
        dewarper: any CurvedDocumentDewarping,
        enhancer: any DocumentImageEnhancing,
        backend: ScannerInferenceBackend,
        outputLongEdgePixels: Int = 2_400
    ) {
        self.requestedInferenceBackend = backend
        self.inferenceBackend = backend
        self.dewarperLoadErrorDescription = nil
        self.perspectiveCorrector = perspectiveCorrector
        self.dewarper = dewarper
        self.enhancer = enhancer
        self.metalImageSampler = try? AndroidMetalImageSampler()
        self.outputLongEdgePixels = outputLongEdgePixels
        self.modelBundle = nil
        self.dewarperInitializationAttempted = true
    }

    /// Loads UVDoc once on the processor actor. Camera setup can call this as a
    /// prewarm, while `process` also invokes it lazily. Failure is recorded and
    /// leaves perspective-only scanning available, matching Android's fallback.
    @discardableResult
    func prepareDewarper() -> Bool {
        guard !dewarperInitializationAttempted else {
            return dewarper != nil
        }
        dewarperInitializationAttempted = true

        guard let modelBundle else {
            return false
        }

        do {
            let engine = try UVDocDewarpEngine(
                bundle: modelBundle,
                backend: requestedInferenceBackend,
                metalImageSampler: metalImageSampler
            )
            dewarper = engine
            inferenceBackend = engine.backend
            return true
        } catch {
            dewarperLoadErrorDescription = error.localizedDescription
            return false
        }
    }

    /// Mirrors capture processing after the capture-time LCNet result:
    /// inset/perspective, upright rotation, UVDoc with graceful fallback,
    /// long-edge normalization, then optional document color enhancement.
    func process(
        _ image: CIImage,
        detectedQuad: DocumentQuad,
        captureRotationDegrees: Int = 0,
        enhanceColors: Bool = true,
        trace: ScannerProcessingTrace? = nil
    ) async throws -> CIImage {
        try await process(
            imageBridge.rgbaImage(from: image),
            detectedQuad: detectedQuad,
            captureRotationDegrees: captureRotationDegrees,
            enhanceColors: enhanceColors,
            trace: trace
        )
    }

    /// Pixel-native entry point used by the camera pipeline. It avoids
    /// materializing three intermediate CIImage/RGBA copies between the Metal
    /// perspective, UVDoc, normalization, and enhancement stages.
    func process(
        _ source: ScannerRGBAImage,
        detectedQuad: DocumentQuad,
        captureRotationDegrees: Int = 0,
        enhanceColors: Bool = true,
        trace: ScannerProcessingTrace? = nil
    ) async throws -> CIImage {
        let perspectiveStage = trace?.beginStage("perspectiveCorrect")
        let correctedPixels: ScannerRGBAImage
        var perspectiveBackend = "custom"
        do {
            if let androidCorrector =
                perspectiveCorrector as? AndroidPerspectiveCorrector {
                correctedPixels = try await androidCorrector.correctPixels(
                    source,
                    using: detectedQuad
                )
                perspectiveBackend =
                    await androidCorrector.lastWarpBackend?.rawValue
                    ?? "unknown"
            } else {
                let corrected = try await perspectiveCorrector.correct(
                    imageBridge.ciImage(from: source),
                    using: detectedQuad
                )
                correctedPixels = try imageBridge.rgbaImage(from: corrected)
            }
            perspectiveStage?.finish(
                details: "input=\(source.width)x\(source.height) "
                    + "output=\(correctedPixels.width)x"
                    + "\(correctedPixels.height) "
                    + "backend=\(perspectiveBackend) pixelNative=true"
            )
        } catch {
            perspectiveStage?.finish(
                outcome: error is CancellationError
                    ? "cancelled"
                    : "failure"
            )
            throw error
        }

        let uprightStage = trace?.beginStage("uprightRotate")
        let normalizedRotation =
            ((captureRotationDegrees % 360) + 360) % 360
        let uprightPixels: ScannerRGBAImage
        let rotationBackend: String
        if normalizedRotation == 0 {
            uprightPixels = correctedPixels
            rotationBackend = "passthrough"
        } else if let metalImageSampler {
            do {
                uprightPixels = try metalImageSampler.rotatedClockwise(
                    correctedPixels,
                    degrees: normalizedRotation
                )
                rotationBackend = "metal"
            } catch {
                uprightPixels = AndroidScannerImageMath.rotatedClockwise(
                    correctedPixels,
                    degrees: normalizedRotation
                )
                rotationBackend = "cpuFallback"
            }
        } else {
            uprightPixels = AndroidScannerImageMath.rotatedClockwise(
                correctedPixels,
                degrees: normalizedRotation
            )
            rotationBackend = "cpu"
        }
        uprightStage?.finish(
            details: "input=\(correctedPixels.width)x"
                + "\(correctedPixels.height) "
                + "output=\(uprightPixels.width)x"
                + "\(uprightPixels.height) "
                + "rotation=\(normalizedRotation) "
                + "backend=\(rotationBackend) pixelNative=true"
        )

        let dewarpedPixels: ScannerRGBAImage
        if prepareDewarper(), let dewarper {
            let dewarpStage = trace?.beginStage("uvdocTotal")
            do {
                if let uvdocEngine = dewarper as? UVDocDewarpEngine {
                    dewarpedPixels = try await uvdocEngine.dewarpPixels(
                        uprightPixels,
                        trace: trace
                    )
                } else if let traceableDewarper =
                    dewarper as? any TraceableCurvedDocumentDewarping {
                    let dewarped = try await traceableDewarper.dewarp(
                        imageBridge.ciImage(from: uprightPixels),
                        trace: trace
                    )
                    dewarpedPixels = try imageBridge.rgbaImage(
                        from: dewarped
                    )
                } else {
                    let dewarped = try await dewarper.dewarp(
                        imageBridge.ciImage(from: uprightPixels)
                    )
                    dewarpedPixels = try imageBridge.rgbaImage(
                        from: dewarped
                    )
                }
                dewarpStage?.finish(
                    details: "backend="
                        + "\(inferenceBackend?.rawValue ?? "unavailable") "
                        + "output=\(dewarpedPixels.width)x"
                        + "\(dewarpedPixels.height) pixelNative=true"
                )
            } catch {
                // Android deliberately keeps the perspective crop if UVDoc
                // inference fails, so scanning remains usable offline.
                dewarpStage?.finish(
                    outcome: "fallback",
                    details: "backend="
                        + "\(inferenceBackend?.rawValue ?? "unavailable")"
                )
                dewarpedPixels = uprightPixels
            }
        } else {
            trace?.beginStage("uvdocTotal").finish(
                outcome: "unavailable"
            )
            dewarpedPixels = uprightPixels
        }

        let normalizeStage = trace?.beginStage("outputNormalize")
        let normalizedPixels: ScannerRGBAImage
        let normalizationBackend: String
        if max(dewarpedPixels.width, dewarpedPixels.height)
            > outputLongEdgePixels,
           let metalImageSampler {
            do {
                normalizedPixels = try metalImageSampler
                    .normalizedLongEdge(
                        dewarpedPixels,
                        maximum: outputLongEdgePixels
                    )
                normalizationBackend = "metal"
            } catch {
                normalizedPixels = AndroidScannerImageMath
                    .normalizedLongEdge(
                        dewarpedPixels,
                        maximum: outputLongEdgePixels
                    )
                normalizationBackend = "cpuFallback"
            }
        } else {
            normalizedPixels = AndroidScannerImageMath.normalizedLongEdge(
                dewarpedPixels,
                maximum: outputLongEdgePixels
            )
            normalizationBackend =
                max(dewarpedPixels.width, dewarpedPixels.height)
                    > outputLongEdgePixels
                ? "cpu"
                : "passthrough"
        }
        normalizeStage?.finish(
            details: "input=\(dewarpedPixels.width)x"
                + "\(dewarpedPixels.height) "
                + "output=\(normalizedPixels.width)x"
                + "\(normalizedPixels.height) "
                + "backend=\(normalizationBackend)"
        )

        guard enhanceColors else {
            return imageBridge.ciImage(from: normalizedPixels)
        }
        let enhanceStage = trace?.beginStage("colorEnhance")
        if let androidEnhancer =
            enhancer as? AndroidDocumentColorEnhancer {
            let enhancedPixels = await androidEnhancer.enhancePixels(
                normalizedPixels
            )
            let performance = await androidEnhancer.lastPerformance
            let enhanced = imageBridge.ciImage(from: enhancedPixels)
            let performanceDetails = performance.map {
                " backend=\($0.backend.rawValue) "
                    + "statisticsMs="
                    + String(format: "%.2f", $0.statisticsMilliseconds)
                    + " applyMs="
                    + String(format: "%.2f", $0.applyMilliseconds)
            } ?? ""
            enhanceStage?.finish(
                details: "input=\(normalizedPixels.width)x"
                    + "\(normalizedPixels.height) "
                    + "output=\(enhancedPixels.width)x"
                    + "\(enhancedPixels.height)"
                    + performanceDetails
            )
            return enhanced
        }

        let normalized = imageBridge.ciImage(from: normalizedPixels)
        do {
            let enhanced = try await enhancer.enhance(normalized)
            enhanceStage?.finish(
                details: "input=\(normalizedPixels.width)x"
                    + "\(normalizedPixels.height) "
                    + "output=\(Self.dimensions(of: enhanced))"
            )
            return enhanced
        } catch {
            enhanceStage?.finish(
                outcome: error is CancellationError
                    ? "cancelled"
                    : "failure"
            )
            throw error
        }
    }

    private nonisolated static func dimensions(of image: CIImage) -> String {
        let extent = image.extent.integral
        return "\(Int(extent.width))x\(Int(extent.height))"
    }
}
