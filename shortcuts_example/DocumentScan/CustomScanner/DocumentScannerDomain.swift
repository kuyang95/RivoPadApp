import Foundation

nonisolated struct NormalizedPoint: Equatable, Sendable {
    let x: Double
    let y: Double

    var isInsideUnitSquare: Bool {
        (0 ... 1).contains(x) && (0 ... 1).contains(y)
    }
}

nonisolated struct DocumentQuad: Equatable, Sendable {
    let topLeft: NormalizedPoint
    let topRight: NormalizedPoint
    let bottomRight: NormalizedPoint
    let bottomLeft: NormalizedPoint

    var points: [NormalizedPoint] {
        [topLeft, topRight, bottomRight, bottomLeft]
    }

    var isInsideUnitSquare: Bool {
        points.allSatisfy(\.isInsideUnitSquare)
    }

    var normalizedArea: Double {
        let polygon = points
        guard polygon.count > 2 else {
            return 0
        }

        var twiceArea = 0.0
        for index in polygon.indices {
            let nextIndex = polygon.index(after: index) == polygon.endIndex
                ? polygon.startIndex
                : polygon.index(after: index)
            twiceArea += polygon[index].x * polygon[nextIndex].y
            twiceArea -= polygon[nextIndex].x * polygon[index].y
        }
        return abs(twiceArea) / 2
    }
}

nonisolated struct DocumentDetection: Equatable, Sendable {
    let quad: DocumentQuad
    let confidence: Double
}

nonisolated enum DocumentFramingGuidance: String, Equatable, Sendable {
    case moveLeft
    case moveRight
    case moveUp
    case moveDown
    case moveCloser
    case moveFarther
}

nonisolated struct CaptureGateSnapshot: Equatable, Sendable {
    let detection: DocumentDetection?
    let framingGuidance: DocumentFramingGuidance?
    let cornersStable: Bool
    let deviceStill: Bool
    let sharpEnough: Bool
    let focusReady: Bool

    var allGatesPass: Bool {
        detection != nil
            && framingGuidance == nil
            && cornersStable
            && deviceStill
            && sharpEnough
            && focusReady
    }
}

nonisolated enum DocumentScanFailure: Equatable, Sendable {
    case cameraPermissionDenied
    case cameraUnavailable
    case focusFailed
    case captureFailed
    case processingFailed
}

nonisolated enum DocumentScanState: Equatable, Sendable {
    case idle
    case preparingCamera
    case searching
    case guiding(DocumentFramingGuidance)
    case stabilizing(passedGateFrames: Int)
    case lockingFocus(ticket: UUID)
    case capturing(ticket: UUID)
    case processing(ticket: UUID)
    case reviewing(pageID: UUID)
    case awaitingPageRemoval(capturedPageCount: Int)
    case failed(DocumentScanFailure)
}

nonisolated enum DocumentScanEvent: Equatable, Sendable {
    case start
    case cameraReady
    case cameraFailed(DocumentScanFailure)
    case frameEvaluated(CaptureGateSnapshot)
    case manualCaptureRequested
    case focusLocked(ticket: UUID)
    case focusLockFailed(ticket: UUID)
    case photoCaptured(ticket: UUID)
    case captureFailed(ticket: UUID)
    case processingSucceeded(ticket: UUID, pageID: UUID)
    case processingFailed(ticket: UUID)
    case resumeScanning
    case pageAccepted(capturedPageCount: Int, continueScanning: Bool)
    case pageRemoved
    case retry
    case cancel
}

nonisolated enum DocumentScanEffect: Equatable, Sendable {
    case requestCameraAccess
    case startCamera
    case stopCamera
    case clearDetectionOverlay
    case updateGuidance(DocumentFramingGuidance)
    case stopGuidance
    case lockFocus(ticket: UUID)
    case capturePhoto(ticket: UUID)
    case processPhoto(ticket: UUID)
    case promptForPageRemoval
}

nonisolated struct CustomDocumentScannerConfiguration: Equatable, Sendable {
    var analysisFramesPerSecond = 10
    var stableFrameCount = 7
    var consecutiveGatePassCount = 3
    var cornerStandardDeviationPixels = 30.0
    var motionSampleWindowSeconds = 0.32
    var accelerationVarianceThreshold = 0.5
    var laplacianSampleWidth = 96
    var laplacianSampleHeight = 64
    var laplacianSharpnessThreshold = 100.0
    var capturedToPreviewSharpnessRatio = 0.4
    var outputLongEdgePixels = 2_400
    var jpegQuality = 0.95

    static let androidParitySeed = Self()
}

nonisolated struct ScannerModelDescriptor: Equatable, Sendable {
    let fileName: String
    let inputName: String
    let outputName: String
    let inputShape: [Int]
    let outputShape: [Int]
    let byteCount: Int
    let sha256: String

    static let documentAligner = ScannerModelDescriptor(
        fileName: "lcnet100_doc_aligner.onnx",
        inputName: "img",
        outputName: "heatmap",
        inputShape: [1, 3, 256, 256],
        outputShape: [1, 4, 128, 128],
        byteCount: 4_767_987,
        sha256: "f4117b786e3a18470f3865c93f3c2bd69d9b998edd60f385574a5c665e79594e"
    )

    static let curvedPageDewarper = ScannerModelDescriptor(
        fileName: "uvdoc.onnx",
        inputName: "image",
        outputName: "grid_2d",
        inputShape: [1, 3, 720, 496],
        outputShape: [1, 2, 45, 31],
        byteCount: 31_802_768,
        sha256: "3fe34e4cce6df28dccd798af8d6054f254c7628eac9e3e2978965809553bc62b"
    )
}

nonisolated enum ScannerInferenceBackend: String, Equatable, Sendable {
    /// Deterministic reference mode used for Android/iOS result comparison.
    case cpuParity

    /// Lets ONNX Runtime partition supported operators to Core ML and falls
    /// back to its CPU provider for the remainder of the graph.
    case coreML
}

nonisolated struct ScannerFloatTensor: Equatable, Sendable {
    let values: [Float]
    let shape: [Int]
}

nonisolated struct UVDocGrid: Equatable, Sendable {
    let values: [Float]
    let height: Int
    let width: Int

    init(values: [Float], height: Int = 45, width: Int = 31) {
        self.values = values
        self.height = height
        self.width = width
    }
}
