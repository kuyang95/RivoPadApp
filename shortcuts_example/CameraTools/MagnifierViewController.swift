import AVFoundation
import CoreImage
import MetalKit
import UIKit
import Vision

nonisolated enum MagnifierCameraMode: Sendable {
    case magnifier
    case liveTextReader
}

nonisolated enum LiveTextDeduplicator {
    static func shouldAnnounce(
        _ candidate: String,
        after previous: String
    ) -> Bool {
        let candidate = normalize(candidate)
        let previous = normalize(previous)
        guard candidate.count >= 2 else {
            return false
        }
        guard !previous.isEmpty else {
            return true
        }
        guard candidate != previous else {
            return false
        }

        let lengthDifference = abs(
            candidate.count - previous.count
        )
        let smallChangeLimit = max(
            8,
            Int(Double(previous.count) * 0.25)
        )
        if lengthDifference <= smallChangeLimit,
           candidate.contains(previous)
            || previous.contains(candidate) {
            return false
        }

        return diceSimilarity(candidate, previous) < 0.86
    }

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func diceSimilarity(
        _ lhs: String,
        _ rhs: String
    ) -> Double {
        let leftPairs = characterPairs(in: lhs)
        let rightPairs = characterPairs(in: rhs)
        guard !leftPairs.isEmpty, !rightPairs.isEmpty else {
            return lhs == rhs ? 1 : 0
        }

        var remaining = rightPairs
        var matches = 0
        for pair in leftPairs {
            guard let index = remaining.firstIndex(of: pair) else {
                continue
            }
            matches += 1
            remaining.remove(at: index)
        }
        return Double(matches * 2)
            / Double(leftPairs.count + rightPairs.count)
    }

    private static func characterPairs(in text: String) -> [String] {
        let characters = Array(text)
        guard characters.count >= 2 else {
            return []
        }
        return (0 ..< characters.count - 1).map {
            String(characters[$0 ... $0 + 1])
        }
    }
}

nonisolated enum MagnifierFilter: Int, CaseIterable, Sendable {
    case normal
    case grayscale
    case inverted
    case highContrast

    var title: String {
        switch self {
        case .normal:
            return "원본"
        case .grayscale:
            return "흑백"
        case .inverted:
            return "반전"
        case .highContrast:
            return "고대비"
        }
    }

    func apply(to image: CIImage) -> CIImage {
        switch self {
        case .normal:
            return image
        case .grayscale:
            return image.applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputSaturationKey: 0
                ]
            )
        case .inverted:
            return image.applyingFilter("CIColorInvert")
        case .highContrast:
            return image.applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputContrastKey: 2.2,
                    kCIInputSaturationKey: 1.1
                ]
            )
        }
    }
}

nonisolated enum MagnifierZoomPolicy {
    static let productMaximum: CGFloat = 10

    static func clamped(
        _ requestedZoom: CGFloat,
        deviceMinimum: CGFloat,
        deviceMaximum: CGFloat
    ) -> CGFloat {
        let upperBound = max(
            deviceMinimum,
            min(deviceMaximum, productMaximum)
        )
        return min(
            max(requestedZoom, deviceMinimum),
            upperBound
        )
    }
}

final class MagnifierViewController:
    UIViewController,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    MTKViewDelegate
{
    var onClose: (() -> Void)?
    var onCapture: ((UIImage) -> Void)?

    private let mode: MagnifierCameraMode
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(
        label: "magnifier.camera.session",
        qos: .userInitiated
    )
    private let videoQueue = DispatchQueue(
        label: "magnifier.camera.video",
        qos: .userInitiated
    )
    private let frameLock = NSLock()
    private let liveOCRLock = NSLock()
    private let liveOCRQueue = DispatchQueue(
        label: "magnifier.live.ocr",
        qos: .userInitiated
    )

    private var cameraInput: AVCaptureDeviceInput?
    private var rotationCoordinator:
        AVCaptureDevice.RotationCoordinator?
    private var latestPixelBuffer: CVPixelBuffer?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var currentFilter: MagnifierFilter = .normal
    private var pinchStartZoom: CGFloat = 1
    private var isTorchEnabled = false
    private var isLiveReadingEnabled = true
    private var isLiveOCRBusy = false
    private var lastLiveOCRTime: CFTimeInterval = 0
    private var lastSpokenText = ""
    private let liveOCRInterval: CFTimeInterval = 1.5

    private let metalDevice = MTLCreateSystemDefaultDevice()
    private lazy var commandQueue = metalDevice?.makeCommandQueue()
    private lazy var renderContext = CIContext(
        mtlDevice: metalDevice!,
        options: [
            .cacheIntermediates: false
        ]
    )
    private lazy var cameraView: MTKView = {
        let view = MTKView(
            frame: .zero,
            device: metalDevice
        )
        view.translatesAutoresizingMaskIntoConstraints = false
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 30
        view.colorPixelFormat = .bgra8Unorm
        view.contentMode = .scaleAspectFill
        view.delegate = self
        view.backgroundColor = .black
        return view
    }()

    private let closeButton = UIButton(type: .system)
    private let zoomLabel = UILabel()
    private let zoomSlider = UISlider()
    private let filterControl = UISegmentedControl(
        items: MagnifierFilter.allCases.map(\.title)
    )
    private let torchButton = UIButton(type: .system)
    private let switchCameraButton = UIButton(type: .system)
    private let captureButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let liveTextLabel = UILabel()
    private let tts = TTSManager.shared

    init(mode: MagnifierCameraMode = .magnifier) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupUI()
        setupGestures()
        requestCameraAndStart()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateVideoRotation()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setTorch(false)
        if mode == .liveTextReader {
            tts.stop()
        }
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    private func setupUI() {
        view.addSubview(cameraView)
        NSLayoutConstraint.activate([
            cameraView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor
            ),
            cameraView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            ),
            cameraView.topAnchor.constraint(
                equalTo: view.topAnchor
            ),
            cameraView.bottomAnchor.constraint(
                equalTo: view.bottomAnchor
            )
        ])

        let controlsBackdrop = UIVisualEffectView(
            effect: UIBlurEffect(style: .systemChromeMaterialDark)
        )
        controlsBackdrop.translatesAutoresizingMaskIntoConstraints = false
        controlsBackdrop.layer.cornerRadius = 22
        controlsBackdrop.clipsToBounds = true
        view.addSubview(controlsBackdrop)

        closeButton.configuration = .filled()
        closeButton.configuration?.title = "닫기"
        closeButton.configuration?.image = UIImage(
            systemName: "xmark"
        )
        closeButton.configuration?.imagePadding = 8
        closeButton.addTarget(
            self,
            action: #selector(closeTapped),
            for: .touchUpInside
        )
        closeButton.accessibilityHint = "카메라 도구 화면으로 돌아갑니다."

        zoomLabel.text = "1.0×"
        zoomLabel.textColor = .white
        zoomLabel.font = .monospacedDigitSystemFont(
            ofSize: 18,
            weight: .bold
        )
        zoomLabel.textAlignment = .center
        zoomLabel.accessibilityLabel = "현재 확대 배율"

        statusLabel.text = "카메라 준비 중"
        statusLabel.textColor = .white
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2

        liveTextLabel.translatesAutoresizingMaskIntoConstraints = false
        liveTextLabel.text = "텍스트를 찾는 중…"
        liveTextLabel.textColor = .white
        liveTextLabel.font = .preferredFont(
            forTextStyle: .title2
        )
        liveTextLabel.adjustsFontForContentSizeCategory = true
        liveTextLabel.textAlignment = .center
        liveTextLabel.numberOfLines = 5
        liveTextLabel.backgroundColor =
            UIColor.black.withAlphaComponent(0.7)
        liveTextLabel.layer.cornerRadius = 16
        liveTextLabel.layer.masksToBounds = true
        liveTextLabel.isHidden = mode != .liveTextReader
        liveTextLabel.isAccessibilityElement = true
        liveTextLabel.accessibilityLabel = "인식된 텍스트"
        view.addSubview(liveTextLabel)

        zoomSlider.minimumValue = 1
        zoomSlider.maximumValue = 10
        zoomSlider.value = 1
        zoomSlider.minimumValueImage = UIImage(
            systemName: "minus.magnifyingglass"
        )
        zoomSlider.maximumValueImage = UIImage(
            systemName: "plus.magnifyingglass"
        )
        zoomSlider.addTarget(
            self,
            action: #selector(zoomSliderChanged),
            for: .valueChanged
        )
        zoomSlider.accessibilityLabel = "확대 배율"

        filterControl.selectedSegmentIndex =
            MagnifierFilter.normal.rawValue
        filterControl.addTarget(
            self,
            action: #selector(filterChanged),
            for: .valueChanged
        )
        filterControl.accessibilityLabel = "카메라 색상 필터"

        configureActionButton(
            torchButton,
            title: "토치",
            systemImage: "flashlight.off.fill",
            action: #selector(torchTapped)
        )
        configureActionButton(
            switchCameraButton,
            title: "전환",
            systemImage: "camera.rotate.fill",
            action: #selector(switchCameraTapped)
        )
        configureActionButton(
            captureButton,
            title: mode == .magnifier
                ? "텍스트 읽기"
                : "읽기 일시정지",
            systemImage: mode == .magnifier
                ? "text.viewfinder"
                : "pause.fill",
            action: #selector(captureTapped)
        )
        captureButton.configuration?.baseBackgroundColor =
            .systemIndigo

        let actionStack = UIStackView(
            arrangedSubviews: [
                torchButton,
                switchCameraButton,
                captureButton
            ]
        )
        actionStack.axis = .horizontal
        actionStack.alignment = .fill
        actionStack.distribution = .fillEqually
        actionStack.spacing = 12

        let contentStack = UIStackView(
            arrangedSubviews: [
                zoomSlider,
                filterControl,
                actionStack,
                statusLabel
            ]
        )
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 14
        controlsBackdrop.contentView.addSubview(contentStack)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        zoomLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)
        view.addSubview(zoomLabel)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 18
            ),
            closeButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 12
            ),
            zoomLabel.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),
            zoomLabel.centerYAnchor.constraint(
                equalTo: closeButton.centerYAnchor
            ),

            liveTextLabel.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 32
            ),
            liveTextLabel.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -32
            ),
            liveTextLabel.bottomAnchor.constraint(
                equalTo: controlsBackdrop.topAnchor,
                constant: -12
            ),
            liveTextLabel.heightAnchor.constraint(
                greaterThanOrEqualToConstant: 72
            ),

            controlsBackdrop.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 18
            ),
            controlsBackdrop.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -18
            ),
            controlsBackdrop.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -14
            ),

            contentStack.leadingAnchor.constraint(
                equalTo: controlsBackdrop.contentView.leadingAnchor,
                constant: 18
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: controlsBackdrop.contentView.trailingAnchor,
                constant: -18
            ),
            contentStack.topAnchor.constraint(
                equalTo: controlsBackdrop.contentView.topAnchor,
                constant: 18
            ),
            contentStack.bottomAnchor.constraint(
                equalTo: controlsBackdrop.contentView.bottomAnchor,
                constant: -18
            ),
            actionStack.heightAnchor.constraint(
                greaterThanOrEqualToConstant: 52
            )
        ])
    }

    private func configureActionButton(
        _ button: UIButton,
        title: String,
        systemImage: String,
        action: Selector
    ) {
        button.configuration = .filled()
        button.configuration?.title = title
        button.configuration?.image = UIImage(
            systemName: systemImage
        )
        button.configuration?.imagePlacement = .top
        button.configuration?.imagePadding = 6
        button.configuration?.baseBackgroundColor =
            UIColor.white.withAlphaComponent(0.18)
        button.addTarget(
            self,
            action: action,
            for: .touchUpInside
        )
    }

    private func setupGestures() {
        let pinch = UIPinchGestureRecognizer(
            target: self,
            action: #selector(handlePinch)
        )
        cameraView.addGestureRecognizer(pinch)

        let doubleTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleDoubleTap)
        )
        doubleTap.numberOfTapsRequired = 2
        cameraView.addGestureRecognizer(doubleTap)
        cameraView.accessibilityHint =
            "두 번 탭하면 확대 배율을 초기화합니다."
    }

    private func requestCameraAndStart() {
        Task {
            let authorized: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                authorized = true
            case .notDetermined:
                authorized = await AVCaptureDevice.requestAccess(
                    for: .video
                )
            default:
                authorized = false
            }

            guard authorized else {
                statusLabel.text =
                    "설정에서 카메라 권한을 허용해 주세요."
                return
            }
            sessionQueue.async { [weak self] in
                self?.configureSession(position: .back)
                self?.session.startRunning()
            }
        }
    }

    private func configureSession(
        position: AVCaptureDevice.Position
    ) {
        session.beginConfiguration()
        session.sessionPreset = .high

        if let cameraInput {
            session.removeInput(cameraInput)
        }

        guard let device = cameraDevice(position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            publishStatus("카메라를 사용할 수 없습니다.")
            return
        }
        session.addInput(input)
        cameraInput = input
        currentPosition = position
        rotationCoordinator = .init(
            device: device,
            previewLayer: nil
        )

        if session.outputs.isEmpty {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA
            ]
            guard session.canAddOutput(videoOutput) else {
                session.commitConfiguration()
                publishStatus("카메라 영상을 받을 수 없습니다.")
                return
            }
            session.addOutput(videoOutput)
            videoOutput.setSampleBufferDelegate(
                self,
                queue: videoQueue
            )
        }

        session.commitConfiguration()
        configureDeviceDefaults(device)

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.updateVideoRotation()
            self.updateZoomUI(for: device)
            self.updateTorchUI()
            self.statusLabel.text =
                self.mode == .liveTextReader
                ? "실시간 텍스트를 찾는 중"
                : (
                    position == .back
                    ? "후면 카메라"
                    : "전면 카메라"
                )
        }
    }

    private func cameraDevice(
        position: AVCaptureDevice.Position
    ) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInUltraWideCamera
            ],
            mediaType: .video,
            position: position
        )
        return discovery.devices.first(where: {
            $0.deviceType == .builtInWideAngleCamera
        }) ?? discovery.devices.first
    }

    private func configureDeviceDefaults(
        _ device: AVCaptureDevice
    ) {
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(
                .continuousAutoFocus
            ) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(
                .continuousAutoExposure
            ) {
                device.exposureMode = .continuousAutoExposure
            }
            let initialZoom = MagnifierZoomPolicy.clamped(
                1,
                deviceMinimum: device.minAvailableVideoZoomFactor,
                deviceMaximum: device.maxAvailableVideoZoomFactor
            )
            device.videoZoomFactor = initialZoom
            device.unlockForConfiguration()
        } catch {
            publishStatus(error.localizedDescription)
        }
    }

    private func updateVideoRotation() {
        guard let connection = videoOutput.connection(with: .video),
              let angle = rotationCoordinator?
                  .videoRotationAngleForHorizonLevelCapture,
              connection.isVideoRotationAngleSupported(angle) else {
            return
        }
        connection.videoRotationAngle = angle
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored =
                currentPosition == .front
        }
    }

    private func updateZoomUI(for device: AVCaptureDevice) {
        let maximum = MagnifierZoomPolicy.clamped(
            device.maxAvailableVideoZoomFactor,
            deviceMinimum: device.minAvailableVideoZoomFactor,
            deviceMaximum: device.maxAvailableVideoZoomFactor
        )
        zoomSlider.minimumValue = Float(
            device.minAvailableVideoZoomFactor
        )
        zoomSlider.maximumValue = Float(maximum)
        zoomSlider.value = Float(device.videoZoomFactor)
        updateZoomLabel(device.videoZoomFactor)
    }

    private func setZoom(_ requestedZoom: CGFloat) {
        guard let device = cameraInput?.device else {
            return
        }
        let zoom = MagnifierZoomPolicy.clamped(
            requestedZoom,
            deviceMinimum: device.minAvailableVideoZoomFactor,
            deviceMaximum: device.maxAvailableVideoZoomFactor
        )
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = zoom
            device.unlockForConfiguration()
            zoomSlider.value = Float(zoom)
            updateZoomLabel(zoom)
        } catch {
            statusLabel.text = error.localizedDescription
        }
    }

    private func updateZoomLabel(_ zoom: CGFloat) {
        zoomLabel.text = String(format: "%.1f×", zoom)
        zoomLabel.accessibilityValue = zoomLabel.text
    }

    private func setTorch(_ enabled: Bool) {
        guard let device = cameraInput?.device,
              device.hasTorch,
              device.isTorchAvailable else {
            isTorchEnabled = false
            updateTorchUI()
            return
        }

        do {
            try device.lockForConfiguration()
            if enabled {
                try device.setTorchModeOn(level: 1)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
            isTorchEnabled = enabled
        } catch {
            isTorchEnabled = false
            statusLabel.text = error.localizedDescription
        }
        updateTorchUI()
    }

    private func updateTorchUI() {
        let isAvailable = cameraInput?.device.hasTorch == true
            && currentPosition == .back
        torchButton.isEnabled = isAvailable
        torchButton.configuration?.title =
            isTorchEnabled ? "토치 끄기" : "토치"
        torchButton.configuration?.image = UIImage(
            systemName: isTorchEnabled
                ? "flashlight.on.fill"
                : "flashlight.off.fill"
        )
        torchButton.accessibilityValue =
            isTorchEnabled ? "켜짐" : "꺼짐"
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func zoomSliderChanged() {
        setZoom(CGFloat(zoomSlider.value))
    }

    @objc private func filterChanged() {
        currentFilter = MagnifierFilter(
            rawValue: filterControl.selectedSegmentIndex
        ) ?? .normal
        UIAccessibility.post(
            notification: .announcement,
            argument: "\(currentFilter.title) 필터"
        )
    }

    @objc private func torchTapped() {
        setTorch(!isTorchEnabled)
    }

    @objc private func switchCameraTapped() {
        setTorch(false)
        let nextPosition: AVCaptureDevice.Position =
            currentPosition == .back ? .front : .back
        sessionQueue.async { [weak self] in
            self?.configureSession(position: nextPosition)
        }
    }

    @objc private func captureTapped() {
        if mode == .liveTextReader {
            toggleLiveReading()
            return
        }
        guard let image = capturedImage() else {
            statusLabel.text = "카메라 프레임을 기다리는 중입니다."
            return
        }
        UIImpactFeedbackGenerator(style: .medium)
            .impactOccurred()
        onCapture?(image)
    }

    @objc private func handlePinch(
        _ gesture: UIPinchGestureRecognizer
    ) {
        switch gesture.state {
        case .began:
            pinchStartZoom =
                cameraInput?.device.videoZoomFactor ?? 1
        case .changed:
            setZoom(pinchStartZoom * gesture.scale)
        default:
            break
        }
    }

    @objc private func handleDoubleTap() {
        setZoom(1)
        UIAccessibility.post(
            notification: .announcement,
            argument: "확대 배율 1배"
        )
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(
            sampleBuffer
        ) else {
            return
        }
        frameLock.lock()
        latestPixelBuffer = pixelBuffer
        frameLock.unlock()

        if shouldRunLiveOCR() {
            liveOCRQueue.async { [weak self] in
                self?.recognizeLiveText(in: pixelBuffer)
            }
        }
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue?
                  .makeCommandBuffer(),
              let image = currentProcessedImage() else {
            return
        }

        let target = CGRect(
            origin: .zero,
            size: view.drawableSize
        )
        let fittedImage = aspectFill(image, target: target)
        renderContext.render(
            fittedImage,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: target,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(
        _ view: MTKView,
        drawableSizeWillChange size: CGSize
    ) {}

    private func currentProcessedImage() -> CIImage? {
        frameLock.lock()
        let pixelBuffer = latestPixelBuffer
        frameLock.unlock()
        guard let pixelBuffer else {
            return nil
        }
        return currentFilter.apply(
            to: CIImage(cvPixelBuffer: pixelBuffer)
        )
    }

    private func aspectFill(
        _ image: CIImage,
        target: CGRect
    ) -> CIImage {
        let extent = image.extent
        let scale = max(
            target.width / extent.width,
            target.height / extent.height
        )
        let scaled = image.transformed(
            by: CGAffineTransform(
                scaleX: scale,
                y: scale
            )
        )
        let translation = CGAffineTransform(
            translationX:
                target.midX - scaled.extent.midX,
            y:
                target.midY - scaled.extent.midY
        )
        return scaled.transformed(by: translation)
    }

    private func capturedImage() -> UIImage? {
        guard let image = currentProcessedImage(),
              let cgImage = renderContext.createCGImage(
                  image,
                  from: image.extent
              ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func shouldRunLiveOCR() -> Bool {
        guard mode == .liveTextReader else {
            return false
        }
        let now = CACurrentMediaTime()
        liveOCRLock.lock()
        defer {
            liveOCRLock.unlock()
        }
        guard isLiveReadingEnabled,
              !isLiveOCRBusy,
              now - lastLiveOCRTime >= liveOCRInterval else {
            return false
        }
        isLiveOCRBusy = true
        lastLiveOCRTime = now
        return true
    }

    private func recognizeLiveText(
        in pixelBuffer: CVPixelBuffer
    ) {
        defer {
            liveOCRLock.lock()
            isLiveOCRBusy = false
            liveOCRLock.unlock()
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [
            "ko-KR",
            "en-US",
            "ja-JP"
        ]
        request.minimumTextHeight = 0.02

        do {
            try VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .up,
                options: [:]
            ).perform([request])

            let observations = request.results ?? []
            let sorted = observations.sorted { lhs, rhs in
                if abs(
                    lhs.boundingBox.maxY
                        - rhs.boundingBox.maxY
                ) > 0.02 {
                    return lhs.boundingBox.maxY
                        > rhs.boundingBox.maxY
                }
                return lhs.boundingBox.minX
                    < rhs.boundingBox.minX
            }
            let text = sorted.compactMap {
                $0.topCandidates(1).first?.string
            }
            .map {
                $0.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

            DispatchQueue.main.async { [weak self] in
                self?.publishLiveText(text)
            }
        } catch {
            publishStatus(
                "실시간 OCR 오류: \(error.localizedDescription)"
            )
        }
    }

    private func publishLiveText(_ text: String) {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            liveTextLabel.text = "텍스트를 찾는 중…"
            return
        }
        liveTextLabel.text = trimmed
        liveTextLabel.accessibilityValue = trimmed

        guard isLiveReadingEnabled,
              !tts.isSpeaking,
              LiveTextDeduplicator.shouldAnnounce(
                  trimmed,
                  after: lastSpokenText
              ) else {
            return
        }
        lastSpokenText = trimmed
        tts.speak(trimmed)
    }

    private func toggleLiveReading() {
        liveOCRLock.lock()
        isLiveReadingEnabled.toggle()
        let isEnabled = isLiveReadingEnabled
        if isEnabled {
            lastLiveOCRTime = 0
        }
        liveOCRLock.unlock()

        if isEnabled {
            lastSpokenText = ""
            captureButton.configuration?.title = "읽기 일시정지"
            captureButton.configuration?.image = UIImage(
                systemName: "pause.fill"
            )
            statusLabel.text = "실시간 텍스트를 찾는 중"
        } else {
            tts.stop()
            captureButton.configuration?.title = "읽기 재개"
            captureButton.configuration?.image = UIImage(
                systemName: "play.fill"
            )
            statusLabel.text = "실시간 읽기 일시정지"
        }
        captureButton.accessibilityValue =
            isEnabled ? "실행 중" : "일시정지"
        UIAccessibility.post(
            notification: .announcement,
            argument: isEnabled
                ? "실시간 읽기를 재개했습니다."
                : "실시간 읽기를 일시정지했습니다."
        )
    }

    private func publishStatus(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = message
        }
    }
}
