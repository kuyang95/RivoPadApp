import UIKit
import AVFoundation
import Vision
import CoreImage

// MARK: - Delegate

protocol ManualDocumentScannerDelegate: AnyObject {
    func scannerDidCancel(_ vc: ManualDocumentScannerViewController)
    func scanner(_ vc: ManualDocumentScannerViewController, didCaptureDocument image: UIImage)
}

// MARK: - Quad helper (Vision normalized points: origin = lower-left)

private struct Quad {
    var tl: CGPoint
    var tr: CGPoint
    var br: CGPoint
    var bl: CGPoint

    init(_ r: VNRectangleObservation) {
        self.tl = r.topLeft
        self.tr = r.topRight
        self.br = r.bottomRight
        self.bl = r.bottomLeft
    }
}

private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = a.x - b.x, dy = a.y - b.y
    return sqrt(dx*dx + dy*dy)
}

private func quadArea(_ q: Quad) -> CGFloat {
    let p = [q.tl, q.tr, q.br, q.bl]
    var s: CGFloat = 0
    for i in 0..<4 {
        let a = p[i]
        let b = p[(i+1) % 4]
        s += (a.x * b.y - b.x * a.y)
    }
    return abs(s) * 0.5
}

private func minEdgeLength(_ q: Quad) -> CGFloat {
    min(dist(q.tl, q.tr), dist(q.tr, q.br), dist(q.br, q.bl), dist(q.bl, q.tl))
}

private func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
    let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
    let bc = CGPoint(x: c.x - b.x, y: c.y - b.y)
    return ab.x * bc.y - ab.y * bc.x
}

private func isConvex(_ q: Quad) -> Bool {
    let p = [q.tl, q.tr, q.br, q.bl]
    let z0 = cross(p[0], p[1], p[2])
    let z1 = cross(p[1], p[2], p[3])
    let z2 = cross(p[2], p[3], p[0])
    let z3 = cross(p[3], p[0], p[1])
    let allPos = (z0 > 0 && z1 > 0 && z2 > 0 && z3 > 0)
    let allNeg = (z0 < 0 && z1 < 0 && z2 < 0 && z3 < 0)
    return allPos || allNeg
}

private func withinMargins(_ q: Quad, margin: CGFloat) -> Bool {
    let pts = [q.tl, q.tr, q.br, q.bl]
    return pts.allSatisfy { p in
        p.x > margin && p.x < (1 - margin) && p.y > margin && p.y < (1 - margin)
    }
}

private func isGoodDocumentQuad(_ q: Quad) -> Bool {
    // 실전에서 꽤 안정적인 기본값들
    guard withinMargins(q, margin: 0.02) else { return false } // 프레임 밖 잘림 방지
    guard quadArea(q) > 0.12 else { return false }            // 너무 작으면 오검출/멀리있는 문서
    guard isConvex(q) else { return false }                   // 꼬인 사각형 방지
    guard minEdgeLength(q) > 0.15 else { return false }       // 너무 작은 변 방지
    return true
}

private func maxCornerDelta(_ a: Quad, _ b: Quad) -> CGFloat {
    let A = [a.tl, a.tr, a.br, a.bl]
    let B = [b.tl, b.tr, b.br, b.bl]
    return zip(A, B).map { dist($0, $1) }.max() ?? .greatestFiniteMagnitude
}

// MARK: - Main VC

final class ManualDocumentScannerViewController: UIViewController {

    weak var delegate: ManualDocumentScannerDelegate?

    // Camera
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let videoQueue = DispatchQueue(label: "camera.video.queue")
    private let visionQueue = DispatchQueue(label: "vision.queue")

    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()

    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let overlayLayer = CAShapeLayer()

    // Vision state
    private var isVisionBusy = false
    private var lastVisionTS: CFTimeInterval = 0
    private let visionInterval: CFTimeInterval = 1.0 / 10.0 // 10fps 정도로만 분석

    private var lastGoodQuad: Quad?
    private var stableCount: Int = 0
    private let stableNeedFrames = 8

    private var latestQuadForUI: Quad?

    // UI
    private let shutterButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    // MARK: lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupUI()
        setupPreviewLayerAndOverlay()

        sessionQueue.async { [weak self] in
            self?.configureSession()
            self?.session.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        updateVideoOrientation()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    // MARK: setup

    private func setupUI() {
        // Shutter
        shutterButton.setTitle(
            AppLocalization.string("촬영"),
            for: .normal
        )
        shutterButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        shutterButton.backgroundColor = UIColor.white.withAlphaComponent(0.9)
        shutterButton.setTitleColor(.black, for: .normal)
        shutterButton.layer.cornerRadius = 28
        shutterButton.addTarget(self, action: #selector(didTapShutter), for: .touchUpInside)

        // Cancel
        cancelButton.setTitle(
            AppLocalization.string("닫기"),
            for: .normal
        )
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)

        // Status
        statusLabel.text =
            AppLocalization.string(
                "문서를 프레임 안에 맞춰주세요"
            )
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 14, weight: .regular)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        statusLabel.layer.cornerRadius = 8
        statusLabel.layer.masksToBounds = true

        // Layout
        [shutterButton, cancelButton, statusLabel].forEach { v in
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }

        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.85),

            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            shutterButton.widthAnchor.constraint(equalToConstant: 120),
            shutterButton.heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    private func setupPreviewLayerAndOverlay() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(previewLayer, at: 0)

        overlayLayer.strokeColor = UIColor.systemGreen.withAlphaComponent(0.95).cgColor
        overlayLayer.fillColor = UIColor.clear.cgColor
        overlayLayer.lineWidth = 3
        overlayLayer.lineJoin = .round
        overlayLayer.lineCap = .round
        previewLayer.addSublayer(overlayLayer)
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Input
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        // Video output
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        // Photo output
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }

        session.commitConfiguration()

        DispatchQueue.main.async { [weak self] in
            self?.updateVideoOrientation()
        }
    }

    private func updateVideoOrientation() {
        let portraitRotationAngle: CGFloat = 90
        if let c1 = previewLayer.connection,
           c1.isVideoRotationAngleSupported(
               portraitRotationAngle
           ) {
            c1.videoRotationAngle =
                portraitRotationAngle
        }
        if let c2 =
                videoOutput.connection(
                    with: .video
                ),
           c2.isVideoRotationAngleSupported(
               portraitRotationAngle
           ) {
            c2.videoRotationAngle =
                portraitRotationAngle
        }
        if let c3 =
                photoOutput.connection(
                    with: .video
                ),
           c3.isVideoRotationAngleSupported(
               portraitRotationAngle
           ) {
            c3.videoRotationAngle =
                portraitRotationAngle
        }
    }

    // MARK: actions

    @objc private func didTapCancel() {
        delegate?.scannerDidCancel(self)
    }

    @objc private func didTapShutter() {
        // 수동 촬영만
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: vision (live)

    private func processFrameForQuad(_ pixelBuffer: CVPixelBuffer) {
        let now = CACurrentMediaTime()
        guard now - lastVisionTS >= visionInterval else { return }
        guard !isVisionBusy else { return }
        isVisionBusy = true
        lastVisionTS = now

        let exif = exifOrientationForPortraitBackCamera()

        visionQueue.async { [weak self] in
            guard let self else { return }

            // 1) DocumentSegmentation 우선
            let docReq = VNDetectDocumentSegmentationRequest()
            docReq.preferBackgroundProcessing = true

            do {
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: exif, options: [:])
                try handler.perform([docReq])

                var rectObs: VNRectangleObservation? = docReq.results?.first

                // 2) 폴백: Rectangles
                if rectObs == nil {
                    rectObs = self.detectRectangleFallback(on: pixelBuffer, exif: exif)
                }

                guard let best = rectObs else {
                    self.publishQuad(nil, stable: false)
                    self.isVisionBusy = false
                    return
                }

                let q = Quad(best)
                let good = isGoodDocumentQuad(q)

                // 안정성(연속 프레임에서 덜 흔들릴 때만 good로)
                var stable = false
                if good, let last = self.lastGoodQuad {
                    let d = maxCornerDelta(last, q)
                    if d < 0.01 {
                        self.stableCount += 1
                    } else {
                        self.stableCount = 0
                    }
                    stable = self.stableCount >= self.stableNeedFrames
                } else if good {
                    self.stableCount = 0
                } else {
                    self.stableCount = 0
                }

                if good { self.lastGoodQuad = q }
                self.publishQuad(q, stable: stable)

            } catch {
                self.publishQuad(nil, stable: false)
            }

            self.isVisionBusy = false
        }
    }

    private func detectRectangleFallback(on pixelBuffer: CVPixelBuffer, exif: CGImagePropertyOrientation) -> VNRectangleObservation? {
        let req = VNDetectRectanglesRequest()
        req.maximumObservations = 5
        req.minimumConfidence = 0.6
        req.minimumSize = 0.2
        req.minimumAspectRatio = 0.4
        req.maximumAspectRatio = 1.0
        req.quadratureTolerance = 20.0

        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: exif, options: [:])
            try handler.perform([req])
            guard let results = req.results, !results.isEmpty else { return nil }

            // confidence * area 기준으로 가장 그럴듯한 문서 선택
            let best = results.max { a, b in
                let qa = Quad(a), qb = Quad(b)
                let sa = a.confidence * Float(quadArea(qa))
                let sb = b.confidence * Float(quadArea(qb))
                return sa < sb
            }
            return best
        } catch {
            return nil
        }
    }

    private func publishQuad(_ q: Quad?, stable: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.latestQuadForUI = q
            self.updateOverlayPath()

            if let q, isGoodDocumentQuad(q) {
                self.statusLabel.text =
                    stable
                    ? AppLocalization.string(
                        "문서 감지됨 ✅ (안정)"
                    )
                    : AppLocalization.string(
                        "문서 감지됨 ✅"
                    )
            } else {
                self.statusLabel.text =
                    AppLocalization.string(
                        "문서를 프레임 안에 맞춰주세요"
                    )
            }
        }
    }

    private func updateOverlayPath() {
        guard let q = latestQuadForUI else {
            overlayLayer.path = nil
            return
        }

        // Vision normalized (origin lower-left) -> AVCaptureDevice normalized (origin upper-left)
        func toLayerPoint(_ p: CGPoint) -> CGPoint {
            let capturePoint = CGPoint(x: p.x, y: 1.0 - p.y)
            return previewLayer.layerPointConverted(fromCaptureDevicePoint: capturePoint)
        }

        let tl = toLayerPoint(q.tl)
        let tr = toLayerPoint(q.tr)
        let br = toLayerPoint(q.br)
        let bl = toLayerPoint(q.bl)

        let path = UIBezierPath()
        path.move(to: tl)
        path.addLine(to: tr)
        path.addLine(to: br)
        path.addLine(to: bl)
        path.close()

        overlayLayer.path = path.cgPath
    }

    private func exifOrientationForPortraitBackCamera() -> CGImagePropertyOrientation {
        // iOS에서 portrait + back camera의 video buffer는 보통 right로 해석되는 경우가 많음.
        // (기기/파이프라인에 따라 달라질 수 있어 추후 필요하면 여기만 조정)
        return .right
    }

    // MARK: capture (manual) - on captured photo, re-detect then perspective-correct

    private func detectQuadOnStillImage(ciImage: CIImage, exif: CGImagePropertyOrientation) -> VNRectangleObservation? {
        // 1) doc segmentation
        let docReq = VNDetectDocumentSegmentationRequest()
        docReq.preferBackgroundProcessing = true

        do {
            let handler = VNImageRequestHandler(ciImage: ciImage, orientation: exif, options: [:])
            try handler.perform([docReq])
            if let best = docReq.results?.first { return best }
        } catch {}

        // 2) fallback rectangles
        let rectReq = VNDetectRectanglesRequest()
        rectReq.maximumObservations = 5
        rectReq.minimumConfidence = 0.6
        rectReq.minimumSize = 0.2
        rectReq.minimumAspectRatio = 0.4
        rectReq.maximumAspectRatio = 1.0
        rectReq.quadratureTolerance = 20.0

        do {
            let handler = VNImageRequestHandler(ciImage: ciImage, orientation: exif, options: [:])
            try handler.perform([rectReq])
            guard let results = rectReq.results, !results.isEmpty else { return nil }
            let best = results.max { a, b in
                let qa = Quad(a), qb = Quad(b)
                let sa = a.confidence * Float(quadArea(qa))
                let sb = b.confidence * Float(quadArea(qb))
                return sa < sb
            }
            return best
        } catch {
            return nil
        }
    }

    private func perspectiveCorrect(ciImage: CIImage, rect: VNRectangleObservation) -> CIImage? {
        let q = Quad(rect)
        guard isGoodDocumentQuad(q) else { return nil }

        let w = ciImage.extent.width
        let h = ciImage.extent.height

        func imgPoint(_ p: CGPoint) -> CGPoint {
            // Vision normalized (origin lower-left) -> CIImage pixel coords (origin lower-left)
            CGPoint(x: p.x * w, y: p.y * h)
        }

        let filter = CIFilter(name: "CIPerspectiveCorrection")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: imgPoint(q.tl)), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: imgPoint(q.tr)), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: imgPoint(q.br)), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: imgPoint(q.bl)), forKey: "inputBottomLeft")
        return filter.outputImage
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ManualDocumentScannerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        processFrameForQuad(pixelBuffer)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension ManualDocumentScannerViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            print("photo capture error: \(error)")
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let uiImage = UIImage(data: data)
        else { return }

        // 촬영된 사진에서 다시 검출 → 문서만 추출(퍼스펙티브 보정)
        let exif = CGImagePropertyOrientation(uiImage.imageOrientation)

        visionQueue.async { [weak self] in
            guard let self else { return }

            guard let ci = CIImage(data: data) else {
                DispatchQueue.main.async {
                    self.delegate?.scanner(self, didCaptureDocument: uiImage)
                }
                return
            }

            let rect = self.detectQuadOnStillImage(ciImage: ci, exif: exif)
            let corrected = rect.flatMap { self.perspectiveCorrect(ciImage: ci, rect: $0) }

            let ctx = CIContext()
            let outUIImage: UIImage

            if let corrected,
               let cg = ctx.createCGImage(corrected, from: corrected.extent) {
                outUIImage = UIImage(cgImage: cg, scale: uiImage.scale, orientation: .up)
            } else {
                // 검출 실패하면 원본 반환(앱에서 재시도/안내 가능)
                outUIImage = uiImage
            }

            DispatchQueue.main.async {
                self.delegate?.scanner(self, didCaptureDocument: outUIImage)
            }
        }
    }
}

// MARK: - UIImageOrientation -> CGImagePropertyOrientation

private extension CGImagePropertyOrientation {
    init(_ ui: UIImage.Orientation) {
        switch ui {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
