@preconcurrency import AVFoundation
import CoreImage
import CoreMedia
import UIKit

nonisolated private struct ScannerAnalysisPayload: Sendable {
    let modelInput: ScannerPreparedTensor
    let transform: ScannerViewportTransform
    let sharpness: Double
    let preprocessingMilliseconds: Double
    let preprocessingBackend: UVDocWarpBackend
    let generation: Int
}

nonisolated private struct ScannerPreparedStill: Sendable {
    let image: ScannerRGBAImage
    let modelInput: ScannerPreparedTensor?
    let transform: ScannerViewportTransform
    let sharpness: Double
    let sourceBackend: String
}

nonisolated private struct ScannerCapturedPhoto: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer?
    let encodedData: Data?
}

nonisolated private enum LocalDocumentScannerError: Error {
    case cameraConfigurationFailed
    case missingViewport
    case photoDataUnavailable
    case photoDecodeFailed
    case captureTooBlurry
    case renderFailed
}

extension LocalDocumentScannerError: LocalizedError {
    nonisolated var errorDescription: String? {
        switch self {
        case .cameraConfigurationFailed:
            return "카메라를 준비하지 못했습니다."
        case .missingViewport:
            return "카메라 화면 좌표를 확인하지 못했습니다."
        case .photoDataUnavailable:
            return "촬영한 사진 데이터를 가져오지 못했습니다."
        case .photoDecodeFailed:
            return "촬영한 사진을 열지 못했습니다."
        case .captureTooBlurry:
            return "촬영 중 흔들림이 감지되었습니다. 다시 촬영해 주세요."
        case .renderFailed:
            return "스캔 결과 이미지를 만들지 못했습니다."
        }
    }
}

/// AVFoundation scanner that keeps VisionCraft's raw-sensor/top-left coordinate
/// contract and uses only the bundled LCNet + UVDoc models.
final class LocalDocumentScannerViewController: UIViewController {
    var onScanCompleted: ((UIImage) -> Void)?
    var onCancel: (() -> Void)?

    private struct LiveDetection {
        let detection: DocumentDetection
        let transform: ScannerViewportTransform
        let sharpness: Double
        let generation: Int
    }

    private struct PendingCapture {
        let ticket: UUID
        let viewport: ScannerViewportConfiguration
        let previewDetection: DocumentDetection?
        let previewTransform: ScannerViewportTransform?
        let previewSharpness: Double
        let captureRotationDegrees: Int
        let photoSettingsID: Int64
        let requestedAt: TimeInterval
        var photoPixelBuffer: CVPixelBuffer?
        var photoData: Data?
    }

    nonisolated private let configuration = CustomDocumentScannerConfiguration
        .androidParitySeed
    private var stateMachine = DocumentScannerStateMachine()
    private var gateEvaluator = DocumentCaptureGateEvaluator()
    private let processor = AndroidParityDocumentProcessor()
    private var detector: LCNetDocumentDetector?
    private var detectorLoadTask: Task<Void, Never>?
    private var dewarperPrewarmTask: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var detectorLoadErrorDescription: String?

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(
        label: "net.rivo.scanner.camera.session",
        qos: .userInitiated
    )
    private let videoQueue = DispatchQueue(
        label: "net.rivo.scanner.camera.video",
        qos: .userInteractive
    )
    nonisolated private let frameAdmission =
        ScannerFrameAdmissionController(framesPerSecond: 10)
    nonisolated private let liveMetalSampler =
        try? AndroidMetalImageSampler()
    nonisolated private let forceCPULivePreprocessing =
        ProcessInfo.processInfo.arguments.contains(
            "-ScannerForceCPULivePreprocessing"
        )
    private let motionMonitor = ScannerMotionMonitor()
    private let diagnostics = ScannerDiagnostics()
    private var captureDevice: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?
    private var cameraConfigured = false
    private var latestLiveDetection: LiveDetection?
    private var pendingCapture: PendingCapture?
    private var manualFocusTickets = Set<UUID>()
    private var sessionInterrupted = false
    private var interruptionStartedAt: TimeInterval?
    private var recoveryStartedAt: TimeInterval?

    private let renderContext = CIContext(options: [
        .cacheIntermediates: false
    ])
    private let imageBridge = ScannerCIImageBridge()

    private lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

    private let overlayLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.systemBlue.withAlphaComponent(0.12).cgColor
        layer.strokeColor = UIColor.systemBlue.cgColor
        layer.lineWidth = 4
        layer.lineJoin = .round
        layer.lineCap = .round
        return layer
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "로컬 문서 인식 모델을 준비하는 중입니다."
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .headline)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.backgroundColor = UIColor.black.withAlphaComponent(0.58)
        label.layer.cornerRadius = 12
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isAccessibilityElement = true
        label.accessibilityTraits = .updatesFrequently
        return label
    }()

    private let backendLabel: UILabel = {
        let label = UILabel()
        label.text = "LCNet 준비 중 · UVDoc 준비 중"
        label.textColor = UIColor.white.withAlphaComponent(0.78)
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textAlignment = .center
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var shutterButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "촬영"
        configuration.baseBackgroundColor = .white
        configuration.baseForegroundColor = .black
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 16,
            leading: 34,
            bottom: 16,
            trailing: 34
        )
        let button = UIButton(configuration: configuration)
        button.titleLabel?.font = .preferredFont(
            forTextStyle: .headline
        )
        button.addTarget(
            self,
            action: #selector(didTapShutter),
            for: .touchUpInside
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "문서 수동 촬영"
        button.accessibilityHint =
            "자동 촬영을 기다리지 않고 현재 문서를 촬영합니다."
        return button
    }()

    private lazy var cancelButton: UIButton = {
        var configuration = UIButton.Configuration.gray()
        configuration.title = "닫기"
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration)
        button.addTarget(
            self,
            action: #selector(didTapCancel),
            for: .touchUpInside
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "문서 스캐너 닫기"
        return button
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let processingOverlay: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.48)
        view.isHidden = true
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var lastAnnouncedText: String?
    private var lastAnnouncementTime: TimeInterval = 0
    private var isViewActive = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupInterface()
        observeCaptureSession()
        diagnostics.logEnvironment()
        prepareModels()
        send(.start)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        overlayLayer.frame = previewLayer.bounds
        applyPreviewRotationAndViewport()
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.view.layoutIfNeeded()
        }, completion: { [weak self] _ in
            self?.applyPreviewRotationAndViewport()
            self?.gateEvaluator.reset()
            self?.latestLiveDetection = nil
            self?.clearOverlay()
        })
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isViewActive = false
        frameAdmission.invalidateViewport()
        gateEvaluator.reset()
        latestLiveDetection = nil
        clearOverlay()
        focusTask?.cancel()
        focusTask = nil
        processingTask?.cancel()
        processingTask = nil
        switch stateMachine.state {
        case .lockingFocus, .capturing, .processing:
            pendingCapture = nil
            manualFocusTickets.removeAll()
            manualCaptureTicketsPending = false
            send(.cancel)
        default:
            stopCamera()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isViewActive = true
        applyPreviewRotationAndViewport()
        updateControls()

        switch stateMachine.state {
        case .reviewing:
            send(.resumeScanning)
        case .idle:
            send(.start)
        case .searching, .guiding, .stabilizing, .awaitingPageRemoval:
            startCamera()
        default:
            break
        }
    }

    deinit {
        detectorLoadTask?.cancel()
        dewarperPrewarmTask?.cancel()
        focusTask?.cancel()
        processingTask?.cancel()
        previewRotationObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
        motionMonitor.stop()
    }

    private func setupInterface() {
        view.layer.addSublayer(previewLayer)
        previewLayer.addSublayer(overlayLayer)

        let controls = UIStackView(
            arrangedSubviews: [cancelButton, shutterButton]
        )
        controls.axis = .horizontal
        controls.alignment = .center
        controls.distribution = .equalSpacing
        controls.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(statusLabel)
        view.addSubview(backendLabel)
        view.addSubview(controls)
        view.addSubview(processingOverlay)
        processingOverlay.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 16
            ),
            statusLabel.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),
            statusLabel.widthAnchor.constraint(
                lessThanOrEqualTo: view.widthAnchor,
                multiplier: 0.9
            ),
            statusLabel.heightAnchor.constraint(
                greaterThanOrEqualToConstant: 52
            ),

            backendLabel.topAnchor.constraint(
                equalTo: statusLabel.bottomAnchor,
                constant: 8
            ),
            backendLabel.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),
            backendLabel.widthAnchor.constraint(
                lessThanOrEqualTo: view.widthAnchor,
                multiplier: 0.9
            ),

            controls.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 24
            ),
            controls.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -24
            ),
            controls.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -20
            ),

            processingOverlay.leadingAnchor.constraint(
                equalTo: view.leadingAnchor
            ),
            processingOverlay.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            ),
            processingOverlay.topAnchor.constraint(
                equalTo: view.topAnchor
            ),
            processingOverlay.bottomAnchor.constraint(
                equalTo: view.bottomAnchor
            ),

            activityIndicator.centerXAnchor.constraint(
                equalTo: processingOverlay.centerXAnchor
            ),
            activityIndicator.centerYAnchor.constraint(
                equalTo: processingOverlay.centerYAnchor
            )
        ])
    }

    private func prepareModels() {
        let scannerDiagnostics = diagnostics
        if ScannerDiagnostics.isUVDocBenchmarkRequested() {
            detectorLoadTask = Task {
                await Task.detached(priority: .userInitiated) {
                    await scannerDiagnostics.runUVDocBackendBenchmark()
                }.value
            }
            return
        }

        let detectorBackend: ScannerInferenceBackend = .cpuParity
        detectorLoadTask = Task {
            [weak self, scannerDiagnostics, detectorBackend] in
            let startedAt = ProcessInfo.processInfo.systemUptime
            do {
                let loadedDetector = try await Task.detached(
                    priority: .userInitiated
                ) {
                    try LCNetDocumentDetector(backend: detectorBackend)
                }.value
                scannerDiagnostics.logDuration(
                    "lcnetLoad",
                    milliseconds: ScannerDiagnostics.milliseconds(
                        since: startedAt
                    ),
                    details: "success=true"
                )
                scannerDiagnostics.logResource("lcnetLoaded")
                guard !Task.isCancelled, let self else {
                    return
                }
                detector = loadedDetector
                detectorLoadErrorDescription = nil
                updateBackendLabel()
                if case .searching = stateMachine.state {
                    setStatus("문서를 화면 안에 맞춰주세요.")
                }
            } catch {
                scannerDiagnostics.logDuration(
                    "lcnetLoad",
                    milliseconds: ScannerDiagnostics.milliseconds(
                        since: startedAt
                    ),
                    details: "success=false"
                )
                scannerDiagnostics.logResource("lcnetLoadFailed")
                guard !Task.isCancelled, let self else {
                    return
                }
                detectorLoadErrorDescription = error.localizedDescription
                updateBackendLabel()
                setStatus(
                    "자동 문서 인식을 준비하지 못했습니다. 수동 촬영은 가능합니다.",
                    announce: true
                )
            }
        }

        let documentProcessor = processor
        dewarperPrewarmTask = Task {
            [weak self, documentProcessor, scannerDiagnostics] in
            let startedAt = ProcessInfo.processInfo.systemUptime
            let succeeded = await documentProcessor.prepareDewarper()
            scannerDiagnostics.logDuration(
                "uvdocLoad",
                milliseconds: ScannerDiagnostics.milliseconds(
                    since: startedAt
                ),
                details: "success=\(succeeded)"
            )
            scannerDiagnostics.logResource("uvdocLoaded")
            guard !Task.isCancelled, let self else {
                return
            }
            updateBackendLabel()
        }
    }

    private func updateBackendLabel() {
        let detectorText: String
        if let detector {
            detectorText = detector.backend == .coreML
                ? "LCNet Core ML"
                : "LCNet CPU"
        } else if detectorLoadErrorDescription != nil {
            detectorText = "LCNet 수동 모드"
        } else {
            detectorText = "LCNet 준비 중"
        }

        Task { [weak self] in
            guard let self else {
                return
            }
            let backend = await processor.inferenceBackend
            let dewarperText: String
            if let backend {
                dewarperText = backend == .coreML
                    ? "UVDoc Core ML"
                    : "UVDoc CPU"
            } else if await processor.dewarperLoadErrorDescription != nil {
                dewarperText = "UVDoc 원근 보정 fallback"
            } else {
                dewarperText = "UVDoc 준비 중"
            }
            backendLabel.text = "\(detectorText) · \(dewarperText)"
        }
    }

    private func send(_ event: DocumentScanEvent) {
        let effects = stateMachine.handle(event)
        for effect in effects {
            apply(effect)
        }
        updateControls()
    }

    private func apply(_ effect: DocumentScanEffect) {
        switch effect {
        case .requestCameraAccess:
            requestCameraAccess()
        case .startCamera:
            startCamera()
        case .stopCamera:
            stopCamera()
        case .clearDetectionOverlay:
            clearOverlay()
            gateEvaluator.reset()
        case .updateGuidance(let guidance):
            setStatus(text(for: guidance), announce: true)
        case .stopGuidance:
            break
        case .lockFocus(let ticket):
            if manualCaptureTicketsPending {
                manualFocusTickets.insert(ticket)
                manualCaptureTicketsPending = false
            }
            lockFocus(ticket: ticket)
        case .capturePhoto(let ticket):
            capturePhoto(ticket: ticket)
        case .processPhoto(let ticket):
            processPhoto(ticket: ticket)
        case .promptForPageRemoval:
            setStatus("다음 문서를 위해 촬영한 문서를 치워주세요.", announce: true)
        }
    }

    private var manualCaptureTicketsPending = false

    private func updateControls() {
        let canCapture: Bool
        switch stateMachine.state {
        case .searching, .guiding, .stabilizing:
            canCapture = true
        default:
            canCapture = false
        }
        shutterButton.isEnabled =
            canCapture && isViewActive && !sessionInterrupted

        if case .processing = stateMachine.state {
            processingOverlay.isHidden = false
            activityIndicator.startAnimating()
        } else {
            processingOverlay.isHidden = true
            activityIndicator.stopAnimating()
        }
    }

    private func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureCameraAndSignalReady()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    guard isViewActive else {
                        send(.cancel)
                        return
                    }
                    if granted {
                        self.configureCameraAndSignalReady()
                    } else {
                        self.send(.cameraFailed(.cameraPermissionDenied))
                        self.showCameraFailure(
                            "카메라 권한이 필요합니다. 설정에서 카메라 접근을 허용해 주세요."
                        )
                    }
                }
            }
        default:
            send(.cameraFailed(.cameraPermissionDenied))
            showCameraFailure(
                "카메라 권한이 필요합니다. 설정에서 카메라 접근을 허용해 주세요."
            )
        }
    }

    private func observeCaptureSession() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(captureSessionWasInterrupted),
            name: AVCaptureSession.wasInterruptedNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(captureSessionInterruptionEnded),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(captureSessionRuntimeError),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
    }

    @objc nonisolated private func captureSessionWasInterrupted(
        _ notification: Notification
    ) {
        let reasonCode = (
            notification.userInfo?[
                AVCaptureSessionInterruptionReasonKey
            ] as? NSNumber
        )?.intValue
        Task { @MainActor [weak self] in
            self?.handleCaptureSessionInterruption(
                reasonCode: reasonCode
            )
        }
    }

    @objc nonisolated private func captureSessionInterruptionEnded(
        _ notification: Notification
    ) {
        Task { @MainActor [weak self] in
            self?.resumeAfterCaptureSessionInterruption()
        }
    }

    @objc nonisolated private func captureSessionRuntimeError(
        _ notification: Notification
    ) {
        let error = notification.userInfo?[
            AVCaptureSessionErrorKey
        ] as? NSError
        let code = error?.code ?? 0
        let description = error?.localizedDescription
            ?? LocalDocumentScannerError.cameraConfigurationFailed
                .localizedDescription
        Task { @MainActor [weak self] in
            self?.handleCaptureSessionRuntimeError(
                code: code,
                description: description
            )
        }
    }

    private func handleCaptureSessionInterruption(
        reasonCode: Int? = nil
    ) {
        if interruptionStartedAt == nil {
            interruptionStartedAt = ProcessInfo.processInfo.systemUptime
        }
        recoveryStartedAt = nil
        diagnostics.logEvent(
            "cameraInterrupted",
            details: "reason=\(reasonCode ?? -1) running=\(session.isRunning)"
        )
        sessionInterrupted = true
        frameAdmission.invalidateViewport()
        gateEvaluator.reset()
        latestLiveDetection = nil
        clearOverlay()
        focusTask?.cancel()
        focusTask = nil
        switch stateMachine.state {
        case .lockingFocus, .capturing:
            pendingCapture = nil
            manualFocusTickets.removeAll()
            manualCaptureTicketsPending = false
            send(.cancel)
        default:
            updateControls()
        }
        if isViewActive {
            setStatus(
                "카메라 사용이 잠시 중단되었습니다. 곧 자동으로 다시 시작합니다.",
                announce: true
            )
        }
    }

    private func resumeAfterCaptureSessionInterruption() {
        if let interruptionStartedAt {
            diagnostics.logDuration(
                "cameraInterruption",
                milliseconds: ScannerDiagnostics.milliseconds(
                    since: interruptionStartedAt
                )
            )
        }
        interruptionStartedAt = nil
        sessionInterrupted = false
        guard isViewActive else {
            recoveryStartedAt = nil
            updateControls()
            return
        }
        recoveryStartedAt = ProcessInfo.processInfo.systemUptime
        diagnostics.logEvent("cameraResumeRequested")
        applyPreviewRotationAndViewport()
        switch stateMachine.state {
        case .idle:
            send(.start)
        case .searching, .guiding, .stabilizing, .awaitingPageRemoval:
            startCamera()
            updateControls()
        default:
            updateControls()
        }
    }

    private func handleCaptureSessionRuntimeError(
        code: Int,
        description: String
    ) {
        diagnostics.logEvent(
            "cameraRuntimeError",
            details: "code=\(code) mediaReset="
                + "\(code == AVError.Code.mediaServicesWereReset.rawValue)"
        )
        if code == AVError.Code.mediaServicesWereReset.rawValue {
            handleCaptureSessionInterruption()
            resumeAfterCaptureSessionInterruption()
            return
        }

        sessionInterrupted = true
        focusTask?.cancel()
        focusTask = nil
        pendingCapture = nil
        manualFocusTickets.removeAll()
        manualCaptureTicketsPending = false
        frameAdmission.invalidateViewport()
        gateEvaluator.reset()
        latestLiveDetection = nil
        clearOverlay()
        send(.cameraFailed(.cameraUnavailable))
        if isViewActive {
            showCameraFailure(description)
        }
    }

    private func configureCameraAndSignalReady() {
        guard !cameraConfigured else {
            send(.cameraReady)
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ),
        let input = try? AVCaptureDeviceInput(device: device),
        session.canAddInput(input) else {
            session.commitConfiguration()
            send(.cameraFailed(.cameraUnavailable))
            showCameraFailure(
                LocalDocumentScannerError.cameraConfigurationFailed
                    .localizedDescription
            )
            return
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_32BGRA
        ]
        guard session.canAddOutput(videoOutput) else {
            session.removeInput(input)
            session.commitConfiguration()
            send(.cameraFailed(.cameraUnavailable))
            showCameraFailure(
                LocalDocumentScannerError.cameraConfigurationFailed
                    .localizedDescription
            )
            return
        }
        session.addOutput(videoOutput)
        guard session.canAddOutput(photoOutput) else {
            session.removeOutput(videoOutput)
            session.removeInput(input)
            session.commitConfiguration()
            send(.cameraFailed(.cameraUnavailable))
            showCameraFailure(
                LocalDocumentScannerError.cameraConfigurationFailed
                    .localizedDescription
            )
            return
        }
        session.addOutput(photoOutput)
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        if let videoConnection = videoOutput.connection(with: .video),
           videoConnection.isVideoRotationAngleSupported(0) {
            // Preserve raw native sensor pixels for Android coordinate parity.
            videoConnection.videoRotationAngle = 0
        }
        if let photoConnection = photoOutput.connection(with: .video),
           photoConnection.isVideoRotationAngleSupported(0) {
            // PhotoOutput records orientation in EXIF. Keep raster bytes raw and
            // rotate only after perspective correction.
            photoConnection.videoRotationAngle = 0
        }
        // Match Android's MINIMIZE_LATENCY capture path so the raster is
        // acquired promptly after the focus/motion gates pass.
        photoOutput.maxPhotoQualityPrioritization = .speed

        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            // Focus state is a fall-open gate on devices that reject tuning.
        }

        captureDevice = device
        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: device,
            previewLayer: previewLayer
        )
        rotationCoordinator = coordinator
        cameraConfigured = true
        session.commitConfiguration()
        let sourceDimensions = CMVideoFormatDescriptionGetDimensions(
            device.activeFormat.formatDescription
        )
        diagnostics.logCamera(
            formatWidth: sourceDimensions.width,
            formatHeight: sourceDimensions.height,
            fieldOfView: device.activeFormat.videoFieldOfView,
            zoomFactor: device.videoZoomFactor
        )
        previewRotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, isViewActive else {
                    return
                }
                applyPreviewRotationAndViewport()
                gateEvaluator.reset()
                latestLiveDetection = nil
                clearOverlay()
            }
        }
        send(.cameraReady)
    }

    private func startCamera() {
        motionMonitor.start()
        let cameraSession = session
        sessionQueue.async {
            if !cameraSession.isRunning {
                cameraSession.startRunning()
            }
        }
        setStatus(
            detector == nil
                ? "카메라가 준비되었습니다. 로컬 문서 모델을 불러오는 중입니다."
                : "문서를 화면 안에 맞춰주세요.",
            announce: true
        )
    }

    private func stopCamera() {
        interruptionStartedAt = nil
        recoveryStartedAt = nil
        motionMonitor.stop()
        restoreContinuousFocus()
        let cameraSession = session
        sessionQueue.async {
            if cameraSession.isRunning {
                cameraSession.stopRunning()
            }
        }
    }

    private func applyPreviewRotationAndViewport() {
        guard view.bounds.width > 0, view.bounds.height > 0 else {
            return
        }
        let angle = rotationCoordinator?
            .videoRotationAngleForHorizonLevelPreview ?? 0
        let cardinal = ScannerViewportTransform.cardinalDegrees(
            Int(angle.rounded())
        )
        if let connection = previewLayer.connection,
           connection.isVideoRotationAngleSupported(CGFloat(cardinal)) {
            connection.videoRotationAngle = CGFloat(cardinal)
        }
        frameAdmission.update(
            previewWidth: view.bounds.width,
            previewHeight: view.bounds.height,
            rotationDegrees: cardinal
        )
    }

    private func receive(_ payload: ScannerAnalysisPayload) async {
        defer {
            frameAdmission.finishFrame()
        }
        guard frameAdmission.isCurrent(generation: payload.generation),
              isViewActive,
              let detector,
              acceptsAnalysisFrames else {
            return
        }

        let inferenceStartedAt = ProcessInfo.processInfo.systemUptime
        do {
            let detection = try await detector.detect(
                prepared: payload.modelInput
            )
            diagnostics.recordLiveInference(
                milliseconds: ScannerDiagnostics.milliseconds(
                    since: inferenceStartedAt
                ),
                preprocessingMilliseconds:
                    payload.preprocessingMilliseconds,
                preprocessingBackend: payload.preprocessingBackend,
                inferenceBackend: detector.backend,
                detected: detection != nil
            )
            guard frameAdmission.isCurrent(generation: payload.generation),
                  isViewActive,
                  acceptsAnalysisFrames else {
                return
            }
            if let recoveryStartedAt {
                diagnostics.logDuration(
                    "cameraRecoveryToFirstInference",
                    milliseconds: ScannerDiagnostics.milliseconds(
                        since: recoveryStartedAt
                    )
                )
                self.recoveryStartedAt = nil
            }

            let deviceStill = motionMonitor.isStill()
            let focusReady = cameraFocusReady
            let sensorGates = gateEvaluator.evaluate(
                detection: detection,
                imageWidth: payload.transform.rawCropRect.width,
                imageHeight: payload.transform.rawCropRect.height,
                sharpness: detection == nil ? 0 : payload.sharpness,
                deviceStill: deviceStill,
                focusReady: focusReady
            )
            let gates = CaptureGateSnapshot(
                detection: sensorGates.detection,
                framingGuidance: sensorGates.framingGuidance.map {
                    ScannerViewportTransform.displayGuidance(
                        for: $0,
                        rotationDegrees: payload.transform.rotationDegrees
                    )
                },
                cornersStable: sensorGates.cornersStable,
                deviceStill: sensorGates.deviceStill,
                sharpEnough: sensorGates.sharpEnough,
                focusReady: sensorGates.focusReady
            )

            if let detection {
                latestLiveDetection = LiveDetection(
                    detection: detection,
                    transform: payload.transform,
                    sharpness: payload.sharpness,
                    generation: payload.generation
                )
                show(
                    detection: detection,
                    transform: payload.transform,
                    stable: gates.cornersStable
                        && gates.framingGuidance == nil
                )
            } else {
                latestLiveDetection = nil
                clearOverlay()
            }

            updateStatus(for: gates)
            send(.frameEvaluated(gates))
        } catch {
            diagnostics.logDuration(
                "liveLCNetFailure",
                milliseconds: ScannerDiagnostics.milliseconds(
                    since: inferenceStartedAt
                )
            )
            guard frameAdmission.isCurrent(generation: payload.generation),
                  isViewActive,
                  acceptsAnalysisFrames else {
                return
            }
            gateEvaluator.reset()
            latestLiveDetection = nil
            clearOverlay()
            setStatus(
                "문서를 다시 찾는 중입니다. 수동 촬영도 가능합니다."
            )
        }
    }

    private var acceptsAnalysisFrames: Bool {
        switch stateMachine.state {
        case .searching, .guiding, .stabilizing:
            return true
        default:
            return false
        }
    }

    private var cameraFocusReady: Bool {
        guard let captureDevice else {
            return true
        }
        let autofocusAvailable =
            captureDevice.isFocusModeSupported(.continuousAutoFocus)
            || captureDevice.isFocusModeSupported(.autoFocus)
        return !autofocusAvailable || !captureDevice.isAdjustingFocus
    }

    private func updateStatus(for gates: CaptureGateSnapshot) {
        if let guidance = gates.framingGuidance {
            setStatus(text(for: guidance))
        } else if gates.detection == nil {
            setStatus("문서를 화면 안에 맞춰주세요.")
        } else if !gates.cornersStable {
            setStatus("문서를 찾았습니다. 잠시 고정해 주세요.")
        } else if !gates.deviceStill {
            setStatus("기기를 조금만 더 고정해 주세요.")
        } else if !gates.sharpEnough {
            setStatus("초점이 선명해질 때까지 기다려 주세요.")
        } else if !gates.focusReady {
            setStatus("카메라 초점을 맞추는 중입니다.")
        } else {
            setStatus("촬영 준비가 완료되었습니다.")
        }
    }

    private func show(
        detection: DocumentDetection,
        transform: ScannerViewportTransform,
        stable: Bool
    ) {
        let points = detection.quad.points.map {
            transform.previewPoint(for: $0)
        }
        guard points.count == 4 else {
            clearOverlay()
            return
        }
        let path = UIBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.close()

        let color = stable ? UIColor.systemGreen : UIColor.systemBlue
        overlayLayer.strokeColor = color.cgColor
        overlayLayer.fillColor = color.withAlphaComponent(0.12).cgColor
        overlayLayer.path = path.cgPath
    }

    private func clearOverlay() {
        overlayLayer.path = nil
    }

    private func lockFocus(ticket: UUID) {
        setStatus("초점을 고정하는 중입니다.")
        focusTask?.cancel()
        let scannerDiagnostics = diagnostics
        let focusStartedAt = ProcessInfo.processInfo.systemUptime
        scannerDiagnostics.logEvent(
            "focusRequested",
            details: "ticket=\(ticket.uuidString.prefix(8))"
        )
        focusTask = Task { [weak self, scannerDiagnostics] in
            var outcome = "cancelled"
            defer {
                scannerDiagnostics.logDuration(
                    "focusLock",
                    milliseconds: ScannerDiagnostics.milliseconds(
                        since: focusStartedAt
                    ),
                    ticket: ticket,
                    details: "outcome=\(outcome)"
                )
            }
            guard let self else {
                return
            }
            guard !Task.isCancelled, isViewActive else {
                return
            }
            guard let device = captureDevice else {
                outcome = "unavailable"
                manualFocusTickets.remove(ticket)
                focusTask = nil
                send(.focusLockFailed(ticket: ticket))
                return
            }

            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }
                device.unlockForConfiguration()
            } catch {
                outcome = "configurationFailed"
                manualFocusTickets.remove(ticket)
                restoreContinuousFocus()
                focusTask = nil
                send(.focusLockFailed(ticket: ticket))
                return
            }

            for sampleIndex in 0 ..< 20 {
                guard !Task.isCancelled, isViewActive else {
                    return
                }
                // Some devices publish `isAdjustingFocus` one or two frames
                // after accepting `.autoFocus`; allow that transition before
                // treating a false value as settled.
                guard device.isAdjustingFocus || sampleIndex < 4 else {
                    break
                }
                try? await Task.sleep(for: .milliseconds(50))
            }

            guard !Task.isCancelled, isViewActive else {
                return
            }
            let manual = manualFocusTickets.contains(ticket)
            guard !device.isAdjustingFocus,
                  manual || motionMonitor.isStill() else {
                outcome = "unstable"
                manualFocusTickets.remove(ticket)
                restoreContinuousFocus()
                focusTask = nil
                send(.focusLockFailed(ticket: ticket))
                setStatus("기기를 고정한 뒤 다시 촬영해 주세요.", announce: true)
                return
            }

            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.locked) {
                    device.focusMode = .locked
                }
                device.unlockForConfiguration()
                outcome = "success"
                focusTask = nil
                send(.focusLocked(ticket: ticket))
            } catch {
                outcome = "configurationFailed"
                manualFocusTickets.remove(ticket)
                restoreContinuousFocus()
                focusTask = nil
                send(.focusLockFailed(ticket: ticket))
            }
        }
    }

    private func capturePhoto(ticket: UUID) {
        guard let viewport = frameAdmission.currentConfiguration() else {
            manualFocusTickets.remove(ticket)
            restoreContinuousFocus()
            send(.captureFailed(ticket: ticket))
            return
        }
        let live = latestLiveDetection.flatMap {
            $0.generation == viewport.generation ? $0 : nil
        }
        let captureRotation = ScannerViewportTransform.cardinalDegrees(
            Int(
                (
                    rotationCoordinator?
                        .videoRotationAngleForHorizonLevelCapture ?? 0
                ).rounded()
            )
        )
        let uncompressedFormats = photoOutput.availablePhotoPixelFormatTypes
        let preferredFormats: [OSType] = [
            kCVPixelFormatType_32BGRA,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        let requestedPixelFormat = preferredFormats.first {
            uncompressedFormats.contains($0)
        }
        let settings: AVCapturePhotoSettings
        if let requestedPixelFormat {
            settings = AVCapturePhotoSettings(
                format: [
                    kCVPixelBufferPixelFormatTypeKey as String:
                        requestedPixelFormat
                ]
            )
        } else {
            settings = AVCapturePhotoSettings()
        }
        settings.flashMode = .off
        settings.photoQualityPrioritization = .speed
        let requestedAt = ProcessInfo.processInfo.systemUptime
        pendingCapture = PendingCapture(
            ticket: ticket,
            viewport: viewport,
            previewDetection: live?.detection,
            previewTransform: live?.transform,
            previewSharpness: live?.sharpness ?? 0,
            captureRotationDegrees: captureRotation,
            photoSettingsID: settings.uniqueID,
            requestedAt: requestedAt,
            photoPixelBuffer: nil,
            photoData: nil
        )

        diagnostics.logEvent(
            "photoRequested",
            details: "ticket=\(ticket.uuidString.prefix(8)) "
                + "pixelFormat=\(requestedPixelFormat ?? 0)"
        )
        diagnostics.logResource("photoRequested", ticket: ticket)
        setStatus("문서를 촬영합니다.", announce: true)
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func processPhoto(ticket: UUID) {
        guard let capture = pendingCapture,
              capture.ticket == ticket,
              capture.photoPixelBuffer != nil
                || capture.photoData != nil else {
            failProcessing(
                ticket: ticket,
                error: LocalDocumentScannerError.photoDataUnavailable
            )
            return
        }

        setStatus("문서를 로컬 AI로 보정하는 중입니다.", announce: true)
        processingTask?.cancel()
        let stillDetector = detector
        let documentProcessor = processor
        let scannerConfiguration = configuration
        let stillMetalSampler = liveMetalSampler
        let scannerDiagnostics = diagnostics
        let resourceSampler = diagnostics.beginProcessing(ticket: ticket)
        let processingTrace = diagnostics.trace(ticket: ticket)
        let enhanceColors =
            AppSettingsStore.shared
            .documentScanColorEnhancementEnabled
        let capturedPhoto = ScannerCapturedPhoto(
            pixelBuffer: capture.photoPixelBuffer,
            encodedData: capture.photoData
        )
        processingTask = Task {
            [weak self,
             stillDetector,
             documentProcessor,
             scannerConfiguration,
             stillMetalSampler,
             scannerDiagnostics,
             resourceSampler,
             processingTrace,
             enhanceColors] in
            var outcome = "cancelled"
            defer {
                resourceSampler?.finish(outcome: outcome)
            }
            do {
                try Task.checkCancellation()
                var stageStartedAt = ProcessInfo.processInfo.systemUptime
                let prepared = try await Self.prepareStill(
                    capturedPhoto,
                    viewport: capture.viewport,
                    metalSampler: stillMetalSampler,
                    detectorInputSize:
                        scannerConfiguration.liveAnalysisLongEdgePixels,
                    sharpnessWidth:
                        scannerConfiguration.laplacianSampleWidth,
                    sharpnessHeight:
                        scannerConfiguration.laplacianSampleHeight
                )
                scannerDiagnostics.logDuration(
                    "stillPrepare",
                    milliseconds: ScannerDiagnostics.milliseconds(
                        since: stageStartedAt
                    ),
                    ticket: ticket,
                    details: "source=\(prepared.sourceBackend)"
                )
                scannerDiagnostics.logResource(
                    "stillPrepared",
                    ticket: ticket
                )
                try Task.checkCancellation()
                if capture.previewSharpness > 0,
                   prepared.sharpness
                    < capture.previewSharpness
                    * scannerConfiguration
                        .capturedToPreviewSharpnessRatio {
                    throw LocalDocumentScannerError.captureTooBlurry
                }

                stageStartedAt = ProcessInfo.processInfo.systemUptime
                let stillDetection: DocumentDetection?
                if let modelInput = prepared.modelInput {
                    stillDetection = try await stillDetector?.detect(
                        prepared: modelInput
                    )
                } else {
                    stillDetection = try await stillDetector?.detect(
                        in: prepared.image
                    )
                }
                scannerDiagnostics.logDuration(
                    "stillLCNet",
                    milliseconds: ScannerDiagnostics.milliseconds(
                        since: stageStartedAt
                    ),
                    ticket: ticket,
                    details: "available=\(stillDetector != nil) "
                        + "detected=\(stillDetection != nil) "
                        + "preprocess="
                        + (prepared.modelInput == nil ? "detector" : "prepared")
                )
                try Task.checkCancellation()
                if let previewDetection = capture.previewDetection,
                   let previewTransform = capture.previewTransform,
                   let stillDetection {
                    scannerDiagnostics.logFOV(
                        ScannerFOVComparison.compare(
                            liveQuad: previewDetection.quad,
                            liveTransform: previewTransform,
                            stillQuad: stillDetection.quad,
                            stillTransform: prepared.transform
                        ),
                        liveTransform: previewTransform,
                        stillTransform: prepared.transform,
                        ticket: ticket
                    )
                } else if capture.previewDetection != nil {
                    scannerDiagnostics.logEvent(
                        "fovUnavailable",
                        details: "ticket=\(ticket.uuidString.prefix(8)) "
                            + "stillDetected=\(stillDetection != nil)"
                    )
                }
                let detection =
                    stillDetection ?? capture.previewDetection
                let output: CIImage
                stageStartedAt = ProcessInfo.processInfo.systemUptime
                if let detection {
                    output = try await documentProcessor.process(
                        prepared.image,
                        detectedQuad: detection.quad,
                        captureRotationDegrees:
                            capture.captureRotationDegrees,
                        enhanceColors: enhanceColors,
                        trace: processingTrace
                    )
                } else {
                    output = try await documentProcessor
                        .processFallback(
                        prepared.image,
                        captureRotationDegrees:
                            capture.captureRotationDegrees,
                        enhanceColors: enhanceColors,
                        trace: processingTrace
                        )
                }
                scannerDiagnostics.logDuration(
                    "documentProcess",
                    milliseconds: ScannerDiagnostics.milliseconds(
                        since: stageStartedAt
                    ),
                    ticket: ticket,
                    details: "quadAvailable=\(detection != nil)"
                )

                try Task.checkCancellation()
                guard let self, isProcessing(ticket: ticket) else {
                    return
                }
                stageStartedAt = ProcessInfo.processInfo.systemUptime
                guard let cgImage = renderContext.createCGImage(
                    output,
                    from: output.extent.integral
                ) else {
                    throw LocalDocumentScannerError.renderFailed
                }
                scannerDiagnostics.logDuration(
                    "renderCGImage",
                    milliseconds: ScannerDiagnostics.milliseconds(
                        since: stageStartedAt
                    ),
                    ticket: ticket
                )
                let image = UIImage(
                    cgImage: cgImage,
                    scale: 1,
                    orientation: .up
                )
                outcome = "success"
                let pageID = UUID()
                pendingCapture = nil
                manualFocusTickets.remove(ticket)
                restoreContinuousFocus()
                processingTask = nil
                send(
                    .processingSucceeded(
                        ticket: ticket,
                        pageID: pageID
                    )
                )
                onScanCompleted?(image)
            } catch is CancellationError {
                return
            } catch {
                outcome = "failure"
                guard !Task.isCancelled,
                      let self,
                      isProcessing(ticket: ticket) else {
                    return
                }
                processingTask = nil
                failProcessing(ticket: ticket, error: error)
            }
        }
    }

    private func isProcessing(ticket: UUID) -> Bool {
        guard pendingCapture?.ticket == ticket,
              case .processing(let activeTicket) = stateMachine.state else {
            return false
        }
        return activeTicket == ticket
    }

    nonisolated private static func prepareStill(
        _ photo: ScannerCapturedPhoto,
        viewport: ScannerViewportConfiguration,
        metalSampler: AndroidMetalImageSampler?,
        detectorInputSize: Int,
        sharpnessWidth: Int,
        sharpnessHeight: Int
    ) async throws -> ScannerPreparedStill {
        try await Task.detached(priority: .userInitiated) {
            let bridge = ScannerCIImageBridge()
            let rawWidth: Int
            let rawHeight: Int
            let decodedDataImage: CIImage?
            if let pixelBuffer = photo.pixelBuffer {
                rawWidth = CVPixelBufferGetWidth(pixelBuffer)
                rawHeight = CVPixelBufferGetHeight(pixelBuffer)
                decodedDataImage = nil
            } else if let data = photo.encodedData,
                      let decoded = CIImage(
                          data: data,
                          options: [.applyOrientationProperty: false]
                      ) {
                let extent = decoded.extent.integral
                rawWidth = Int(extent.width)
                rawHeight = Int(extent.height)
                decodedDataImage = decoded
            } else {
                throw LocalDocumentScannerError.photoDecodeFailed
            }
            guard let transform = ScannerViewportTransform(
                rawWidth: rawWidth,
                rawHeight: rawHeight,
                configuration: viewport
            ) else {
                throw LocalDocumentScannerError.missingViewport
            }
            if let pixelBuffer = photo.pixelBuffer,
               CVPixelBufferGetPixelFormatType(pixelBuffer)
                == kCVPixelFormatType_32BGRA,
               let metalSampler {
                do {
                    let letterbox =
                        AndroidScannerImageMath.letterboxTransform(
                            sourceWidth: transform.rawCropRect.width,
                            sourceHeight: transform.rawCropRect.height,
                            size: detectorInputSize
                        )
                    let prepared = try metalSampler.prepareLiveFrame(
                        pixelBuffer,
                        cropRect: transform.rawCropRect,
                        letterbox: letterbox,
                        sharpnessWidth: sharpnessWidth,
                        sharpnessHeight: sharpnessHeight,
                        includeFullResolutionCrop: true
                    )
                    guard let cropped = prepared.fullResolutionCrop else {
                        throw LocalDocumentScannerError.photoDecodeFailed
                    }
                    return ScannerPreparedStill(
                        image: cropped,
                        modelInput: prepared.modelInput,
                        transform: transform,
                        sharpness:
                            AndroidScannerFrameQuality.laplacianVariance(
                                of: prepared.sharpnessSample,
                                sampleWidth: sharpnessWidth,
                                sampleHeight: sharpnessHeight
                            ),
                        sourceBackend: "pixelBufferMetalBGRA"
                    )
                } catch {
                    // Some capture buffers may not be Metal-compatible.
                    // Preserve the Core Image path on those devices.
                }
            }

            let rawCIImage: CIImage
            let sourceBackend: String
            if let pixelBuffer = photo.pixelBuffer {
                rawCIImage = CIImage(cvPixelBuffer: pixelBuffer)
                sourceBackend = "pixelBufferCoreImage"
            } else if let decoded = decodedDataImage {
                rawCIImage = decoded
                sourceBackend = "encodedData"
            } else {
                throw LocalDocumentScannerError.photoDecodeFailed
            }
            let cropped = try bridge.rgbaImage(
                from: rawCIImage,
                topLeftCropRect: transform.rawCropRect
            )
            return ScannerPreparedStill(
                image: cropped,
                modelInput: nil,
                transform: transform,
                sharpness: AndroidScannerFrameQuality.laplacianVariance(
                    of: cropped
                ),
                sourceBackend: sourceBackend
            )
        }.value
    }

    private func failProcessing(ticket: UUID, error: Error) {
        pendingCapture = nil
        manualFocusTickets.remove(ticket)
        restoreContinuousFocus()
        send(.processingFailed(ticket: ticket))

        let alert = UIAlertController(
            title: "다시 촬영해 주세요",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(title: "재시도", style: .default) { [weak self] _ in
                self?.send(.retry)
            }
        )
        present(alert, animated: true)
    }

    private func restoreContinuousFocus() {
        guard let captureDevice else {
            return
        }
        do {
            try captureDevice.lockForConfiguration()
            if captureDevice.isFocusModeSupported(.continuousAutoFocus) {
                captureDevice.focusMode = .continuousAutoFocus
            }
            captureDevice.unlockForConfiguration()
        } catch {
            // The next camera frame will continue with the device's current mode.
        }
    }

    private func setStatus(
        _ text: String,
        announce: Bool = false
    ) {
        let changed = statusLabel.text != text
        statusLabel.text = text
        guard announce, changed, UIAccessibility.isVoiceOverRunning else {
            return
        }

        let now = CACurrentMediaTime()
        guard lastAnnouncedText != text
                || now - lastAnnouncementTime >= 1 else {
            return
        }
        lastAnnouncedText = text
        lastAnnouncementTime = now
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    private func text(
        for guidance: DocumentFramingGuidance
    ) -> String {
        switch guidance {
        case .moveLeft:
            return "기기를 왼쪽으로 이동해 주세요."
        case .moveRight:
            return "기기를 오른쪽으로 이동해 주세요."
        case .moveUp:
            return "기기를 위로 이동해 주세요."
        case .moveDown:
            return "기기를 아래로 이동해 주세요."
        case .moveCloser:
            return "문서에 조금 더 가까이 이동해 주세요."
        case .moveFarther:
            return "문서에서 조금 더 멀리 이동해 주세요."
        }
    }

    private func showCameraFailure(_ message: String) {
        setStatus(message, announce: true)
        let alert = UIAlertController(
            title: "카메라를 사용할 수 없습니다",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(title: "닫기", style: .cancel) { [weak self] _ in
                self?.onCancel?()
            }
        )
        present(alert, animated: true)
    }

    func performRemoteAction(
        _ action: RivoDocumentScannerRemoteAction
    ) {
        switch action {
        case .close:
            didTapCancel()
        case .capture:
            didTapShutter()
        }
    }

    @objc private func didTapShutter() {
        switch stateMachine.state {
        case .searching, .guiding, .stabilizing:
            break
        default:
            return
        }
        manualCaptureTicketsPending = true
        send(.manualCaptureRequested)
    }

    @objc private func didTapCancel() {
        focusTask?.cancel()
        focusTask = nil
        processingTask?.cancel()
        processingTask = nil
        pendingCapture = nil
        manualFocusTickets.removeAll()
        manualCaptureTicketsPending = false
        restoreContinuousFocus()
        send(.cancel)
        onCancel?()
    }
}

extension LocalDocumentScannerViewController:
    AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(
            sampleBuffer
        )
        let timestamp = presentationTime.isValid
            ? presentationTime.seconds
            : ProcessInfo.processInfo.systemUptime
        guard let viewport = frameAdmission.beginFrame(
            timestamp: timestamp
        ) else {
            return
        }

        let preprocessingStartedAt = ProcessInfo.processInfo.systemUptime
        do {
            guard let transform = ScannerViewportTransform(
                rawWidth: CVPixelBufferGetWidth(pixelBuffer),
                rawHeight: CVPixelBufferGetHeight(pixelBuffer),
                configuration: viewport
            ) else {
                throw LocalDocumentScannerError.missingViewport
            }
            let letterbox = AndroidScannerImageMath.letterboxTransform(
                sourceWidth: transform.rawCropRect.width,
                sourceHeight: transform.rawCropRect.height,
                size: configuration.liveAnalysisLongEdgePixels
            )
            let modelInput: ScannerPreparedTensor
            let sharpnessSample: ScannerRGBAImage
            let preprocessingBackend: UVDocWarpBackend
            if !forceCPULivePreprocessing, let liveMetalSampler {
                do {
                    let prepared = try liveMetalSampler.prepareLiveFrame(
                        pixelBuffer,
                        cropRect: transform.rawCropRect,
                        letterbox: letterbox,
                        sharpnessWidth:
                            configuration.laplacianSampleWidth,
                        sharpnessHeight:
                            configuration.laplacianSampleHeight
                    )
                    modelInput = prepared.modelInput
                    sharpnessSample = prepared.sharpnessSample
                    preprocessingBackend = .metal
                } catch {
                    let prepared = try Self.prepareLiveFrameOnCPU(
                        pixelBuffer,
                        cropRect: transform.rawCropRect,
                        letterbox: letterbox,
                        sharpnessWidth:
                            configuration.laplacianSampleWidth,
                        sharpnessHeight:
                            configuration.laplacianSampleHeight
                    )
                    modelInput = prepared.modelInput
                    sharpnessSample = prepared.sharpnessSample
                    preprocessingBackend = .cpu
                }
            } else {
                let prepared = try Self.prepareLiveFrameOnCPU(
                    pixelBuffer,
                    cropRect: transform.rawCropRect,
                    letterbox: letterbox,
                    sharpnessWidth: configuration.laplacianSampleWidth,
                    sharpnessHeight: configuration.laplacianSampleHeight
                )
                modelInput = prepared.modelInput
                sharpnessSample = prepared.sharpnessSample
                preprocessingBackend = .cpu
            }
            let sharpness = AndroidScannerFrameQuality.laplacianVariance(
                of: sharpnessSample,
                sampleWidth: configuration.laplacianSampleWidth,
                sampleHeight: configuration.laplacianSampleHeight
            )
            let payload = ScannerAnalysisPayload(
                modelInput: modelInput,
                transform: transform,
                sharpness: sharpness,
                preprocessingMilliseconds:
                    ScannerDiagnostics.milliseconds(
                        since: preprocessingStartedAt
                    ),
                preprocessingBackend: preprocessingBackend,
                generation: viewport.generation
            )
            let admission = frameAdmission
            Task { @MainActor [weak self] in
                guard let self else {
                    admission.finishFrame()
                    return
                }
                await receive(payload)
            }
        } catch {
            frameAdmission.finishFrame()
        }
    }

    nonisolated private static func prepareLiveFrameOnCPU(
        _ pixelBuffer: CVPixelBuffer,
        cropRect: ScannerPixelRect,
        letterbox: ScannerLetterboxTransform,
        sharpnessWidth: Int,
        sharpnessHeight: Int
    ) throws -> AndroidMetalLiveFramePreparation {
        let detectorImage = try ScannerRGBAImage.readingBGRA(
            pixelBuffer,
            cropRect: cropRect,
            outputWidth: letterbox.scaledWidth,
            outputHeight: letterbox.scaledHeight
        )
        let modelInput = AndroidScannerImageMath.letterboxedRGBTensor(
            fromResized: detectorImage,
            letterbox: letterbox
        )
        let sharpnessSample = try ScannerRGBAImage.readingBGRA(
            pixelBuffer,
            cropRect: cropRect,
            outputWidth: sharpnessWidth,
            outputHeight: sharpnessHeight
        )
        return AndroidMetalLiveFramePreparation(
            modelInput: modelInput,
            sharpnessSample: sharpnessSample
        )
    }
}

extension LocalDocumentScannerViewController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let callbackAt = ProcessInfo.processInfo.systemUptime
        let pixelBuffer = error == nil ? photo.pixelBuffer : nil
        let data = error == nil && pixelBuffer == nil
            ? photo.fileDataRepresentation()
            : nil
        let errorDescription = error?.localizedDescription
        let photoSettingsID = photo.resolvedSettings.uniqueID
        Task { @MainActor [weak self] in
            guard let self,
                  let pending = pendingCapture,
                  pending.photoSettingsID == photoSettingsID else {
                return
            }
            diagnostics.logDuration(
                "shutterToPhotoData",
                milliseconds: max(
                    (callbackAt - pending.requestedAt) * 1_000,
                    0
                ),
                ticket: pending.ticket,
                details: "success=\(pixelBuffer != nil || data != nil) "
                    + "source="
                    + (pixelBuffer == nil ? "encodedData" : "pixelBuffer")
            )
            guard pixelBuffer != nil || data != nil else {
                pendingCapture = nil
                manualFocusTickets.remove(pending.ticket)
                restoreContinuousFocus()
                send(.captureFailed(ticket: pending.ticket))
                setStatus(
                    errorDescription
                        ?? LocalDocumentScannerError.photoDataUnavailable
                            .localizedDescription,
                    announce: true
                )
                return
            }
            pendingCapture?.photoPixelBuffer = pixelBuffer
            pendingCapture?.photoData = data
            send(.photoCaptured(ticket: pending.ticket))
        }
    }
}
