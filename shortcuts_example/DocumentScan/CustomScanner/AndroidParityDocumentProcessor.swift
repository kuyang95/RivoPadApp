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
                backend: requestedInferenceBackend
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
        let perspectiveStage = trace?.beginStage("perspectiveCorrect")
        let corrected: CIImage
        do {
            corrected = try await perspectiveCorrector.correct(
                image,
                using: detectedQuad
            )
            var details = "input=\(Self.dimensions(of: image)) "
                + "output=\(Self.dimensions(of: corrected))"
            if let androidCorrector =
                perspectiveCorrector as? AndroidPerspectiveCorrector {
                let backend = await androidCorrector.lastWarpBackend
                details += " backend=\(backend?.rawValue ?? "unknown")"
            }
            perspectiveStage?.finish(
                details: details
            )
        } catch {
            perspectiveStage?.finish(
                outcome: error is CancellationError
                    ? "cancelled"
                    : "failure"
            )
            throw error
        }

        let uprightStage = trace?.beginStage("uprightRasterize")
        let correctedPixels: ScannerRGBAImage
        do {
            correctedPixels = try imageBridge.rgbaImage(from: corrected)
        } catch {
            uprightStage?.finish(
                outcome: error is CancellationError
                    ? "cancelled"
                    : "failure"
            )
            throw error
        }
        let uprightPixels = AndroidScannerImageMath.rotatedClockwise(
            correctedPixels,
            degrees: captureRotationDegrees
        )
        let upright = imageBridge.ciImage(from: uprightPixels)
        uprightStage?.finish(
            details: "input=\(correctedPixels.width)x"
                + "\(correctedPixels.height) "
                + "output=\(uprightPixels.width)x"
                + "\(uprightPixels.height) "
                + "rotation=\(captureRotationDegrees)"
        )

        let dewarped: CIImage
        if prepareDewarper(), let dewarper {
            let dewarpStage = trace?.beginStage("uvdocTotal")
            do {
                if let traceableDewarper =
                    dewarper as? any TraceableCurvedDocumentDewarping {
                    dewarped = try await traceableDewarper.dewarp(
                        upright,
                        trace: trace
                    )
                } else {
                    dewarped = try await dewarper.dewarp(upright)
                }
                dewarpStage?.finish(
                    details: "backend="
                        + "\(inferenceBackend?.rawValue ?? "unavailable") "
                        + "output=\(Self.dimensions(of: dewarped))"
                )
            } catch {
                // Android deliberately keeps the perspective crop if UVDoc
                // inference fails, so scanning remains usable offline.
                dewarpStage?.finish(
                    outcome: "fallback",
                    details: "backend="
                        + "\(inferenceBackend?.rawValue ?? "unavailable")"
                )
                dewarped = upright
            }
        } else {
            trace?.beginStage("uvdocTotal").finish(
                outcome: "unavailable"
            )
            dewarped = upright
        }

        let outputRasterizeStage = trace?.beginStage("outputRasterize")
        let dewarpedPixels: ScannerRGBAImage
        do {
            dewarpedPixels = try imageBridge.rgbaImage(from: dewarped)
            outputRasterizeStage?.finish(
                details: "output=\(dewarpedPixels.width)x"
                    + "\(dewarpedPixels.height)"
            )
        } catch {
            outputRasterizeStage?.finish(
                outcome: error is CancellationError
                    ? "cancelled"
                    : "failure"
            )
            throw error
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
