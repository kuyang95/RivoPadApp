import AVFoundation
import CoreImage
import MetalKit
import UIKit

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

    private var cameraInput: AVCaptureDeviceInput?
    private var rotationCoordinator:
        AVCaptureDevice.RotationCoordinator?
    private var latestPixelBuffer: CVPixelBuffer?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var currentFilter: MagnifierFilter = .normal
    private var pinchStartZoom: CGFloat = 1
    private var isTorchEnabled = false

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
            title: "텍스트 읽기",
            systemImage: "text.viewfinder",
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
                position == .back
                ? "후면 카메라"
                : "전면 카메라"
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

    private func publishStatus(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = message
        }
    }
}
