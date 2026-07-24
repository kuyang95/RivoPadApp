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
    let inputShape: [Int]
    let outputShape: [Int?]

    static let documentAligner = ScannerModelDescriptor(
        fileName: "lcnet100_doc_aligner.onnx",
        inputShape: [1, 3, 256, 256],
        outputShape: [1, 4, nil, nil]
    )

    static let curvedPageDewarper = ScannerModelDescriptor(
        fileName: "uvdoc.onnx",
        inputShape: [1, 3, 720, 496],
        outputShape: [1, 2, 45, 31]
    )
}
