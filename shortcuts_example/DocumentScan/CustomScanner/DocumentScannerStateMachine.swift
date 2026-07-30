import Foundation

nonisolated struct DocumentScannerStateMachine: Sendable {
    private(set) var state: DocumentScanState = .idle
    let configuration: CustomDocumentScannerConfiguration
    private(set) var automaticCaptureEnabled:
        Bool

    init(
        configuration: CustomDocumentScannerConfiguration = .androidParitySeed,
        automaticCaptureEnabled: Bool = true
    ) {
        self.configuration = configuration
        self.automaticCaptureEnabled =
            automaticCaptureEnabled
    }

    mutating func setAutomaticCaptureEnabled(
        _ enabled: Bool
    ) {
        automaticCaptureEnabled = enabled
        if !enabled,
           case .stabilizing = state {
            state = .searching
        }
    }

    mutating func handle(_ event: DocumentScanEvent) -> [DocumentScanEffect] {
        if event == .cancel {
            state = .idle
            return [.stopGuidance, .stopCamera, .clearDetectionOverlay]
        }

        if case .cameraFailed(let failure) = event {
            switch state {
            case .preparingCamera,
                 .searching,
                 .guiding,
                 .stabilizing,
                 .lockingFocus,
                 .capturing,
                 .awaitingPageRemoval:
                state = .failed(failure)
                return [.stopGuidance, .stopCamera, .clearDetectionOverlay]

            case .idle, .processing, .reviewing, .failed:
                return []
            }
        }

        switch (state, event) {
        case (.idle, .start):
            state = .preparingCamera
            return [.requestCameraAccess]

        case (.preparingCamera, .cameraReady):
            state = .searching
            return [.startCamera]

        case (.searching, .frameEvaluated(let gates)),
             (.guiding, .frameEvaluated(let gates)),
             (.stabilizing, .frameEvaluated(let gates)):
            return handleFrame(gates)

        case (.searching, .manualCaptureRequested),
             (.guiding, .manualCaptureRequested),
             (.stabilizing, .manualCaptureRequested):
            let ticket = UUID()
            state = .lockingFocus(ticket: ticket)
            return [.stopGuidance, .lockFocus(ticket: ticket)]

        case (.lockingFocus(let expectedTicket), .focusLocked(let ticket))
            where expectedTicket == ticket:
            state = .capturing(ticket: ticket)
            return [.capturePhoto(ticket: ticket)]

        case (
            .lockingFocus(let expectedTicket),
            .focusLockFailed(let ticket)
        ) where expectedTicket == ticket:
            state = .searching
            return [.clearDetectionOverlay]

        case (.capturing(let expectedTicket), .photoCaptured(let ticket))
            where expectedTicket == ticket:
            state = .processing(ticket: ticket)
            return [.processPhoto(ticket: ticket)]

        case (.capturing(let expectedTicket), .captureFailed(let ticket))
            where expectedTicket == ticket:
            state = .searching
            return [.clearDetectionOverlay]

        case (
            .processing(let expectedTicket),
            .processingSucceeded(let ticket, let pageID)
        ) where expectedTicket == ticket:
            state = .reviewing(pageID: pageID)
            return [.stopCamera]

        case (.processing(let expectedTicket), .processingFailed(let ticket))
            where expectedTicket == ticket:
            state = .failed(.processingFailed)
            return [.stopCamera]

        case (.reviewing, .resumeScanning):
            state = .searching
            return [.startCamera, .clearDetectionOverlay]

        case (
            .reviewing,
            .pageAccepted(let capturedPageCount, let continueScanning)
        ):
            if continueScanning {
                state = .awaitingPageRemoval(
                    capturedPageCount: capturedPageCount
                )
                return [
                    .startCamera,
                    .clearDetectionOverlay,
                    .promptForPageRemoval
                ]
            }
            state = .idle
            return []

        case (.awaitingPageRemoval, .pageRemoved):
            state = .searching
            return [.clearDetectionOverlay]

        case (.failed, .retry):
            state = .preparingCamera
            return [.requestCameraAccess]

        default:
            return []
        }
    }

    private mutating func handleFrame(
        _ gates: CaptureGateSnapshot
    ) -> [DocumentScanEffect] {
        guard gates.detection != nil else {
            state = .searching
            return [.stopGuidance, .clearDetectionOverlay]
        }

        if let guidance = gates.framingGuidance {
            state = .guiding(guidance)
            return [.updateGuidance(guidance)]
        }

        guard gates.allGatesPass else {
            state = .stabilizing(passedGateFrames: 0)
            return [.stopGuidance]
        }

        guard automaticCaptureEnabled else {
            state = .stabilizing(
                passedGateFrames: 0
            )
            return [.stopGuidance]
        }

        let previousPassCount: Int
        if case .stabilizing(let passedGateFrames) = state {
            previousPassCount = passedGateFrames
        } else {
            previousPassCount = 0
        }

        let nextPassCount = previousPassCount + 1
        if nextPassCount >= configuration.consecutiveGatePassCount {
            let ticket = UUID()
            state = .lockingFocus(ticket: ticket)
            return [.stopGuidance, .lockFocus(ticket: ticket)]
        }

        state = .stabilizing(passedGateFrames: nextPassCount)
        return [.stopGuidance]
    }
}
