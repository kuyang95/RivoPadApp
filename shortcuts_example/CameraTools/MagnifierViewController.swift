import AVFoundation
import CoreImage
import MetalKit
import UIKit
import Vision

nonisolated enum MagnifierCameraMode: Sendable {
    case magnifier
    case liveTextReader
    case imageDescription
}

nonisolated struct LiveTextOCRQuality:
    Equatable,
    Sendable
{
    let elementCount: Int
    let medianGlyphHeight: Int
    let below16Percentage: Int

    init(
        elementCount: Int = 0,
        medianGlyphHeight: Int = 0,
        below16Percentage: Int = 0
    ) {
        self.elementCount = max(0, elementCount)
        self.medianGlyphHeight = max(
            0,
            medianGlyphHeight
        )
        self.below16Percentage = min(
            max(0, below16Percentage),
            100
        )
    }

    var isLowForSpeech: Bool {
        elementCount >= 8
            && (
                medianGlyphHeight < 18
                    || below16Percentage >= 25
            )
    }
}

nonisolated enum LiveTextAnnouncementDisposition:
    Equatable,
    Sendable
{
    case noText
    case lowQuality
    case checking
    case suppressed
    case announce
}

nonisolated struct LiveTextAnnouncementDecision:
    Equatable,
    Sendable
{
    let disposition:
        LiveTextAnnouncementDisposition
    let text: String
    let reason: String
    let similarity: Double?
}

nonisolated struct LiveTextDeduplicator: Sendable {
    private var candidateText: String?
    private var candidateStableCount = 0
    private var lastSpokenText = ""
    private var lastSpokenAt: TimeInterval = 0
    private var sceneAnchorText = ""
    private var sceneAnchorAt: TimeInterval = 0
    private var consecutiveNoTextFrames = 0

    mutating func evaluate(
        _ rawText: String,
        quality: LiveTextOCRQuality,
        now: TimeInterval,
        isSpeaking: Bool
    ) -> LiveTextAnnouncementDecision {
        let normalized = Self.normalize(rawText)
        guard normalized.count >= Self.minimumTextLength else {
            noteNoTextFrame()
            return LiveTextAnnouncementDecision(
                disposition: .noText,
                text: "",
                reason: "text_too_short",
                similarity: nil
            )
        }
        consecutiveNoTextFrames = 0

        guard !quality.isLowForSpeech else {
            return LiveTextAnnouncementDecision(
                disposition: .lowQuality,
                text: normalized,
                reason: "low_ocr_quality",
                similarity: nil
            )
        }

        let previousCandidate = candidateText
        let candidateSimilarity = previousCandidate.map {
            Self.sceneSimilarity($0, normalized)
        }
        if let previousCandidate,
           let candidateSimilarity,
           candidateSimilarity.value
                >= Self.candidateMatchThreshold {
            candidateStableCount += 1
            if normalized.count
                > previousCandidate.count {
                candidateText = normalized
            }
        } else {
            candidateText = normalized
            candidateStableCount = 1
        }

        let stableText =
            candidateText ?? normalized
        guard candidateStableCount
            >= Self.requiredStableCount else {
            return LiveTextAnnouncementDecision(
                disposition: .checking,
                text: stableText,
                reason: "candidate_not_stable",
                similarity: candidateSimilarity?.value
            )
        }

        if lastSpokenText.isEmpty,
           candidateStableCount
            < Self.initialStableCount,
           !Self.isRichTextScene(
               stableText,
               quality: quality
           ) {
            return LiveTextAnnouncementDecision(
                disposition: .checking,
                text: stableText,
                reason: "initial_text_not_stable",
                similarity: candidateSimilarity?.value
            )
        }

        let decision = speechDecision(
            stableText,
            quality: quality,
            now: now,
            isSpeaking: isSpeaking
        )
        guard decision.disposition == .announce else {
            return decision
        }

        lastSpokenText = stableText
        lastSpokenAt = now
        let spokenText = String(
            stableText.prefix(Self.maximumSpokenCharacters)
        )
        updateSceneAnchor(
            spokenText,
            quality: quality,
            now: now
        )
        return LiveTextAnnouncementDecision(
            disposition: .announce,
            text: spokenText,
            reason: decision.reason,
            similarity: decision.similarity
        )
    }

    mutating func reset() {
        candidateText = nil
        candidateStableCount = 0
        lastSpokenText = ""
        lastSpokenAt = 0
        sceneAnchorText = ""
        sceneAnchorAt = 0
        consecutiveNoTextFrames = 0
    }

    static func shouldAnnounce(
        _ candidate: String,
        after previous: String
    ) -> Bool {
        let candidate = normalize(candidate)
        let previous = normalize(previous)
        guard candidate.count >= minimumTextLength else {
            return false
        }
        guard !previous.isEmpty else {
            return true
        }
        return sceneSimilarity(
            previous,
            candidate
        ).value < spokenDuplicateThreshold
    }

    static func quality(
        lineTexts: [String],
        linePixelHeights: [Double]
    ) -> LiveTextOCRQuality {
        var glyphHeights: [Int] = []
        for (index, text) in lineTexts.enumerated() {
            let tokenCount = max(
                1,
                comparisonTokens(text).count
            )
            let height = index < linePixelHeights.count
                ? max(
                    0,
                    Int(linePixelHeights[index].rounded())
                )
                : 0
            glyphHeights.append(
                contentsOf: repeatElement(
                    height,
                    count: tokenCount
                )
            )
        }
        guard !glyphHeights.isEmpty else {
            return LiveTextOCRQuality()
        }
        glyphHeights.sort()
        return LiveTextOCRQuality(
            elementCount: glyphHeights.count,
            medianGlyphHeight:
                glyphHeights[glyphHeights.count / 2],
            below16Percentage:
                glyphHeights.filter { $0 < 16 }.count
                * 100
                / glyphHeights.count
        )
    }

    private mutating func speechDecision(
        _ text: String,
        quality: LiveTextOCRQuality,
        now: TimeInterval,
        isSpeaking: Bool
    ) -> LiveTextAnnouncementDecision {
        if !sceneAnchorText.isEmpty {
            let elapsed = max(
                0,
                now - sceneAnchorAt
            )
            if elapsed < Self.sceneAnchorSuppression,
               isSameSceneAsAnchor(
                   text,
                   quality: quality
               ) {
                let similarity = Self.sceneSimilarity(
                    sceneAnchorText,
                    text
                ).value
                return suppressed(
                    text,
                    reason: "same_scene_anchor",
                    similarity: similarity
                )
            }
        }

        guard !lastSpokenText.isEmpty else {
            return LiveTextAnnouncementDecision(
                disposition: .announce,
                text: text,
                reason: "first_text",
                similarity: nil
            )
        }

        let elapsed = max(
            0,
            now - lastSpokenAt
        )
        let match = Self.sceneSimilarity(
            lastSpokenText,
            text
        )
        if match.value
            >= Self.spokenDuplicateThreshold {
            return suppressed(
                text,
                reason: "duplicate_threshold",
                similarity: match.value
            )
        }
        if isSpeaking,
           match.value
            >= Self.speakingSceneMatchThreshold {
            return suppressed(
                text,
                reason: "same_scene_while_speaking",
                similarity: match.value
            )
        }
        if elapsed < Self.sceneRepeatSuppression,
           match.value
            >= Self.sceneRepeatMatchThreshold {
            return suppressed(
                text,
                reason: "same_scene_cooldown",
                similarity: match.value
            )
        }
        if elapsed < Self.minimumSpeakInterval,
           match.value
            >= Self.recentTextMatchThreshold {
            return suppressed(
                text,
                reason: "recent_similar_text",
                similarity: match.value
            )
        }
        return LiveTextAnnouncementDecision(
            disposition: .announce,
            text: text,
            reason: "new_text",
            similarity: match.value
        )
    }

    private func suppressed(
        _ text: String,
        reason: String,
        similarity: Double
    ) -> LiveTextAnnouncementDecision {
        LiveTextAnnouncementDecision(
            disposition: .suppressed,
            text: text,
            reason: reason,
            similarity: similarity
        )
    }

    private func isSameSceneAsAnchor(
        _ text: String,
        quality: LiveTextOCRQuality
    ) -> Bool {
        let score = Self.sceneSimilarity(
            sceneAnchorText,
            text
        )
        if score.value
            >= Self.sceneAnchorMatchThreshold {
            return true
        }
        if score.containment
            >= Self.sceneAnchorContainmentThreshold {
            return true
        }

        let isShortPartial =
            text.count < Self.partialSceneMaximumCharacters
            || quality.elementCount
                < Self.partialSceneMaximumElements
        let isShorterThanAnchor =
            Double(text.count)
            < Double(sceneAnchorText.count)
                * Self.partialAnchorLengthRatio
        return isShortPartial
            && isShorterThanAnchor
            && score.containment
                >= Self.partialSceneContainmentThreshold
    }

    private mutating func updateSceneAnchor(
        _ text: String,
        quality: LiveTextOCRQuality,
        now: TimeInterval
    ) {
        guard Self.isRichTextScene(
            text,
            quality: quality
        ) else {
            return
        }
        if sceneAnchorText.isEmpty
            || Double(text.count)
                >= Double(sceneAnchorText.count)
                * Self.anchorReplaceMinimumLengthRatio {
            sceneAnchorText = text
            sceneAnchorAt = now
        }
    }

    private mutating func noteNoTextFrame() {
        consecutiveNoTextFrames += 1
        guard consecutiveNoTextFrames
            >= Self.noTextResetFrames else {
            return
        }
        candidateText = nil
        candidateStableCount = 0
        sceneAnchorText = ""
        sceneAnchorAt = 0
        consecutiveNoTextFrames = 0
    }

    private static func isRichTextScene(
        _ text: String,
        quality: LiveTextOCRQuality
    ) -> Bool {
        text.count >= richTextMinimumCharacters
            || quality.elementCount
                >= richTextMinimumElements
    }

    private static func normalize(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func sceneSimilarity(
        _ first: String,
        _ second: String
    ) -> SimilarityScore {
        let ordered = orderedSimilarity(
            first,
            second
        )
        let tokens = tokenSimilarity(
            first,
            second
        )
        return SimilarityScore(
            value: max(ordered, tokens.dice),
            ordered: ordered,
            tokens: tokens.dice,
            containment: tokens.containment
        )
    }

    private static func orderedSimilarity(
        _ first: String,
        _ second: String
    ) -> Double {
        let left = Array(
            first.prefix(similarityMaximumCharacters)
        )
        let right = Array(
            second.prefix(similarityMaximumCharacters)
        )
        guard !left.isEmpty, !right.isEmpty else {
            return 0
        }
        let distance = levenshteinDistance(
            left,
            right
        )
        return 1
            - Double(distance)
            / Double(max(left.count, right.count))
    }

    private static func tokenSimilarity(
        _ first: String,
        _ second: String
    ) -> TokenScore {
        let firstTokens = comparisonTokens(first)
        let secondTokens = comparisonTokens(second)
        guard !firstTokens.isEmpty,
              !secondTokens.isEmpty else {
            return TokenScore()
        }

        var remaining: [String: Int] = [:]
        for token in firstTokens {
            remaining[token, default: 0] += 1
        }
        var intersection = 0
        for token in secondTokens {
            guard let count = remaining[token],
                  count > 0 else {
                continue
            }
            intersection += 1
            if count == 1 {
                remaining.removeValue(forKey: token)
            } else {
                remaining[token] = count - 1
            }
        }
        return TokenScore(
            dice: Double(intersection * 2)
                / Double(
                    firstTokens.count
                        + secondTokens.count
                ),
            containment: Double(intersection)
                / Double(
                    min(
                        firstTokens.count,
                        secondTokens.count
                    )
                )
        )
    }

    private static func comparisonTokens(
        _ text: String
    ) -> [String] {
        var tokens: [String] = []
        var current = ""
        for character in text {
            if character.isLetter
                || character.isNumber
                || "@._-".contains(character) {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(
                    normalizeComparisonToken(current)
                )
                current = ""
            }
        }
        if !current.isEmpty {
            tokens.append(
                normalizeComparisonToken(current)
            )
        }
        return tokens.filter { !$0.isEmpty }
    }

    private static func normalizeComparisonToken(
        _ token: String
    ) -> String {
        var characters = Array(token.lowercased())
        let original = characters
        for index in characters.indices
        where characters[index] == "o" {
            let previousIsDigit =
                index > original.startIndex
                && original[
                    original.index(before: index)
                ].isNumber
            let nextIndex =
                original.index(after: index)
            let nextIsDigit =
                nextIndex < original.endIndex
                && original[nextIndex].isNumber
            if previousIsDigit || nextIsDigit {
                characters[index] = "0"
            }
        }
        return String(characters)
    }

    private static func levenshteinDistance(
        _ first: [Character],
        _ second: [Character]
    ) -> Int {
        if first == second {
            return 0
        }
        if first.isEmpty {
            return second.count
        }
        if second.isEmpty {
            return first.count
        }

        var previous = Array(0 ... second.count)
        var current = Array(
            repeating: 0,
            count: second.count + 1
        )
        for firstIndex in first.indices {
            current[0] = firstIndex + 1
            for secondIndex in second.indices {
                let substitutionCost =
                    first[firstIndex]
                        == second[secondIndex]
                    ? 0
                    : 1
                current[secondIndex + 1] = min(
                    current[secondIndex] + 1,
                    previous[secondIndex + 1] + 1,
                    previous[secondIndex]
                        + substitutionCost
                )
            }
            swap(&previous, &current)
        }
        return previous[second.count]
    }

    private struct SimilarityScore: Sendable {
        let value: Double
        let ordered: Double
        let tokens: Double
        let containment: Double
    }

    private struct TokenScore: Sendable {
        let dice: Double
        let containment: Double

        init(
            dice: Double = 0,
            containment: Double = 0
        ) {
            self.dice = dice
            self.containment = containment
        }
    }

    private static let minimumTextLength = 2
    private static let initialStableCount = 2
    private static let requiredStableCount = 1
    private static let candidateMatchThreshold = 0.78
    private static let spokenDuplicateThreshold = 0.82
    private static let recentTextMatchThreshold = 0.58
    private static let minimumSpeakInterval: TimeInterval = 3
    private static let sceneRepeatSuppression: TimeInterval = 12
    private static let sceneRepeatMatchThreshold = 0.70
    private static let speakingSceneMatchThreshold = 0.58
    private static let sceneAnchorSuppression: TimeInterval = 30
    private static let sceneAnchorMatchThreshold = 0.70
    private static let sceneAnchorContainmentThreshold = 0.46
    private static let partialSceneContainmentThreshold = 0.22
    private static let partialSceneMaximumCharacters = 90
    private static let partialSceneMaximumElements = 8
    private static let partialAnchorLengthRatio = 0.88
    private static let anchorReplaceMinimumLengthRatio = 0.92
    private static let richTextMinimumCharacters = 90
    private static let richTextMinimumElements = 16
    private static let noTextResetFrames = 3
    private static let maximumSpokenCharacters = 500
    private static let similarityMaximumCharacters = 240
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

nonisolated struct MagnifierDisplayAdjustment:
    Equatable,
    Sendable
{
    static let defaultThreshold: CGFloat = 0.5
    static let thresholdStep: CGFloat = 0.01
    static let brightnessStep: CGFloat = 0.1

    var colorIndex: Int?
    var threshold: CGFloat
    var isInverted: Bool
    var brightness: CGFloat

    static let defaultValue =
        MagnifierDisplayAdjustment(
            colorIndex: nil,
            threshold: defaultThreshold,
            isInverted: false,
            brightness: 0
        )

    func updated(
        for action: RivoMagnifierRemoteAction,
        colorCount: Int =
            LocalDocumentColorTheme.all.count
    ) -> Self {
        var updated = self
        switch action {
        case .previousColor:
            guard colorCount > 0 else {
                return updated
            }
            let current = min(
                max(colorIndex ?? 0, 0),
                colorCount - 1
            )
            updated.colorIndex =
                (current - 1 + colorCount)
                % colorCount
            updated.isInverted = false
        case .originalColor:
            updated.colorIndex = nil
            updated.isInverted = false
        case .nextColor:
            guard colorCount > 0 else {
                return updated
            }
            let current = min(
                max(colorIndex ?? 0, 0),
                colorCount - 1
            )
            updated.colorIndex =
                (current + 1) % colorCount
            updated.isInverted = false
        case .decreaseThreshold:
            updated.threshold = max(
                updated.threshold
                    - Self.thresholdStep,
                0
            )
        case .resetThreshold:
            updated.threshold =
                Self.defaultThreshold
        case .increaseThreshold:
            updated.threshold = min(
                updated.threshold
                    + Self.thresholdStep,
                1.05
            )
        case .decreaseBrightness:
            updated.brightness = max(
                updated.brightness
                    - Self.brightnessStep,
                -0.5
            )
        case .resetBrightness:
            updated.brightness = 0
        case .increaseBrightness:
            updated.brightness = min(
                updated.brightness
                    + Self.brightnessStep,
                0.5
            )
        case .invertColor:
            updated.isInverted.toggle()
        default:
            break
        }
        return updated
    }

    func applying(to image: CIImage) -> CIImage {
        var output = image
        if let colorIndex,
           !LocalDocumentColorTheme.all.isEmpty {
            let themes =
                LocalDocumentColorTheme.all
            let index = min(
                max(colorIndex, 0),
                themes.count - 1
            )
            let theme = themes[index]
            let scale: CGFloat = 20
            let bias =
                0.5 - scale * threshold
            let luminanceVector = CIVector(
                x: scale * 0.2126,
                y: scale * 0.7152,
                z: scale * 0.0722,
                w: 0
            )
            output = output.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": luminanceVector,
                    "inputGVector": luminanceVector,
                    "inputBVector": luminanceVector,
                    "inputAVector":
                        CIVector(
                            x: 0,
                            y: 0,
                            z: 0,
                            w: 1
                        ),
                    "inputBiasVector":
                        CIVector(
                            x: bias,
                            y: bias,
                            z: bias,
                            w: 0
                        )
                ]
            )
            .applyingFilter(
                "CIColorClamp",
                parameters: [
                    "inputMinComponents":
                        CIVector(
                            x: 0,
                            y: 0,
                            z: 0,
                            w: 0
                        ),
                    "inputMaxComponents":
                        CIVector(
                            x: 1,
                            y: 1,
                            z: 1,
                            w: 1
                        )
                ]
            )
            .applyingFilter(
                "CIFalseColor",
                parameters: [
                    "inputColor0":
                        Self.color(
                            from: theme.backgroundHex
                        ),
                    "inputColor1":
                        Self.color(
                            from: theme.foregroundHex
                        )
                ]
            )
        }
        if isInverted {
            output = output.applyingFilter(
                "CIColorInvert"
            )
        }
        if brightness != 0 {
            output = output.applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputBrightnessKey:
                        brightness
                ]
            )
        }
        return output
    }

    private static func color(
        from rgbHex: Int
    ) -> CIColor {
        CIColor(
            red:
                CGFloat((rgbHex >> 16) & 0xFF)
                / 255,
            green:
                CGFloat((rgbHex >> 8) & 0xFF)
                / 255,
            blue:
                CGFloat(rgbHex & 0xFF)
                / 255,
            alpha: 1
        )
    }
}

final class MagnifierViewController:
    UIViewController,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    MTKViewDelegate,
    UIDocumentPickerDelegate
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
    private var displayAdjustment:
        MagnifierDisplayAdjustment = .defaultValue
    private var pinchStartZoom: CGFloat = 1
    private var isTorchEnabled = false
    private var isLiveReadingEnabled = true
    private var isLiveOCRBusy = false
    private var lastLiveOCRTime: CFTimeInterval = 0
    private var liveTextDeduplicator =
        LiveTextDeduplicator()
    private let liveOCRInterval: CFTimeInterval = 1
    private var lastRemoteEventID: UInt64 = 0

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
    private let photoSaveButton = UIButton(type: .system)
    private let captureButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let liveTextLabel = UILabel()
    private let tts = TTSManager.shared
    private let photoSaveService =
        MagnifierPhotoSaveService()
    private var pendingPhotoExportURL: URL?

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
            photoSaveButton,
            title: "사진 저장",
            systemImage: "camera.fill",
            action: #selector(photoSaveTapped)
        )
        photoSaveButton.accessibilityHint =
            "현재 필터와 확대가 적용된 프레임을 사진 보관함이나 Files에 저장합니다."
        configureActionButton(
            captureButton,
            title: captureButtonTitle,
            systemImage: captureButtonSystemImage,
            action: #selector(captureTapped)
        )
        captureButton.configuration?.baseBackgroundColor =
            .systemIndigo

        var actionButtons = [
            torchButton,
            switchCameraButton,
        ]
        if mode == .magnifier {
            actionButtons.append(
                photoSaveButton
            )
        }
        actionButtons.append(captureButton)
        let actionStack = UIStackView(
            arrangedSubviews: actionButtons
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

    func synchronizeRemoteEventCursor(
        to eventID: UInt64?
    ) {
        lastRemoteEventID = eventID ?? 0
    }

    func performRemoteAction(
        _ action: RivoMagnifierRemoteAction,
        eventID: UInt64
    ) {
        guard eventID != lastRemoteEventID else {
            return
        }
        lastRemoteEventID = eventID

        switch action {
        case .enterCameraMode(let showGuide):
            let seventhKeyAction: String
            switch mode {
            case .magnifier:
                seventhKeyAction =
                    "7 사진 저장"
            case .liveTextReader:
                seventhKeyAction =
                    "7 읽기 일시정지 또는 재개"
            case .imageDescription:
                seventhKeyAction =
                    "7 이미지 설명"
            }
            announceRemoteStatus(
                showGuide
                    ? "카메라 조작 모드. 4 닫기, 5 카메라 전환, 6 토치, \(seventhKeyAction), R2 초점, 별표 0 샵 확대"
                    : "카메라 조작 모드"
            )
        case .enterDisplayMode(let showGuide):
            announceRemoteStatus(
                showGuide
                    ? "화면 조작 모드. 4 이전 색상, 5 원본, 6 다음 색상, 7 8 9 임계값, 별표 0 샵 밝기, R2 반전, R1 카메라 조작"
                    : "화면 조작 모드"
            )
        case .close:
            closeTapped()
        case .switchCamera:
            switchCameraTapped()
        case .toggleTorch:
            torchTapped()
        case .capture:
            if mode == .magnifier {
                saveCurrentFrameToPhotos()
            } else {
                captureTapped()
            }
        case .focus:
            focusAtCenter()
        case .decreaseZoom:
            adjustZoom(by: -0.5)
        case .resetZoom:
            setZoom(1)
            announceCurrentZoom()
        case .increaseZoom:
            adjustZoom(by: 0.5)
        case .previousColor,
             .originalColor,
             .nextColor,
             .decreaseThreshold,
             .resetThreshold,
             .increaseThreshold,
             .decreaseBrightness,
             .resetBrightness,
             .increaseBrightness,
             .invertColor:
            applyRemoteDisplayAction(action)
        }
    }

    private func adjustZoom(by delta: CGFloat) {
        let currentZoom =
            cameraInput?.device.videoZoomFactor
                ?? CGFloat(zoomSlider.value)
        setZoom(currentZoom + delta)
        announceCurrentZoom()
    }

    private func announceCurrentZoom() {
        UIAccessibility.post(
            notification: .announcement,
            argument:
                "확대 배율 \(zoomLabel.text ?? "")"
        )
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
        displayAdjustment.colorIndex = nil
        displayAdjustment.isInverted = false
        UIAccessibility.post(
            notification: .announcement,
            argument: "\(currentFilter.title) 필터"
        )
    }

    private func applyRemoteDisplayAction(
        _ action: RivoMagnifierRemoteAction
    ) {
        displayAdjustment =
            displayAdjustment.updated(for: action)

        let message: String
        switch action {
        case .previousColor,
             .nextColor:
            filterControl.selectedSegmentIndex =
                UISegmentedControl.noSegment
            let index =
                displayAdjustment.colorIndex ?? 0
            let theme =
                LocalDocumentColorTheme.all[index]
            message = "색상 \(theme.name)"
        case .originalColor:
            currentFilter = .normal
            filterControl.selectedSegmentIndex =
                MagnifierFilter.normal.rawValue
            message = "원본 색상"
        case .decreaseThreshold,
             .resetThreshold,
             .increaseThreshold:
            message = String(
                format:
                    "색상 임계값 %.0f퍼센트",
                displayAdjustment.threshold
                    * 100
            )
        case .decreaseBrightness,
             .resetBrightness,
             .increaseBrightness:
            message = String(
                format:
                    "미리보기 밝기 %+.0f",
                displayAdjustment.brightness
                    * 100
            )
        case .invertColor:
            message =
                displayAdjustment.isInverted
                ? "미리보기 색상 반전"
                : "미리보기 색상 반전 해제"
        default:
            return
        }
        announceRemoteStatus(message)
    }

    private func focusAtCenter() {
        guard let device = cameraInput?.device else {
            announceRemoteStatus(
                "카메라가 준비되지 않았습니다."
            )
            return
        }

        do {
            try device.lockForConfiguration()
            let center = CGPoint(x: 0.5, y: 0.5)
            var didAdjust = false
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = center
                if device.isFocusModeSupported(
                    .autoFocus
                ) {
                    device.focusMode = .autoFocus
                } else if device.isFocusModeSupported(
                    .continuousAutoFocus
                ) {
                    device.focusMode =
                        .continuousAutoFocus
                }
                didAdjust = true
            }
            if device
                .isExposurePointOfInterestSupported {
                device.exposurePointOfInterest =
                    center
                if device.isExposureModeSupported(
                    .continuousAutoExposure
                ) {
                    device.exposureMode =
                        .continuousAutoExposure
                }
                didAdjust = true
            }
            device.unlockForConfiguration()
            announceRemoteStatus(
                didAdjust
                    ? "화면 중앙에 초점을 맞춥니다."
                    : "이 카메라는 수동 초점을 지원하지 않습니다."
            )
        } catch {
            announceRemoteStatus(
                "초점을 맞추지 못했습니다: "
                    + error.localizedDescription
            )
        }
    }

    private func announceRemoteStatus(
        _ message: String
    ) {
        statusLabel.text = message
        UIAccessibility.post(
            notification: .announcement,
            argument: message
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

    private var captureButtonTitle: String {
        switch mode {
        case .magnifier:
            return "텍스트 읽기"
        case .liveTextReader:
            return "읽기 일시정지"
        case .imageDescription:
            return "이미지 설명"
        }
    }

    private var captureButtonSystemImage: String {
        switch mode {
        case .magnifier:
            return "text.viewfinder"
        case .liveTextReader:
            return "pause.fill"
        case .imageDescription:
            return "sparkles"
        }
    }

    @objc private func photoSaveTapped() {
        guard let image = capturedImage() else {
            announceRemoteStatus(
                "카메라 프레임을 기다리는 중입니다."
            )
            return
        }
        presentPhotoSaveOptions(
            for: image
        )
    }

    private func presentPhotoSaveOptions(
        for image: UIImage
    ) {
        let alert = UIAlertController(
            title: "사진 저장",
            message:
                "저장할 위치를 선택합니다. 사진 보관함은 추가 전용 권한만 사용합니다.",
            preferredStyle: .actionSheet
        )
        alert.addAction(
            UIAlertAction(
                title: "사진 보관함",
                style: .default
            ) { [weak self] _ in
                self?.saveImageToPhotos(image)
            }
        )
        alert.addAction(
            UIAlertAction(
                title: "Files",
                style: .default
            ) { [weak self] _ in
                self?.exportImageToFiles(image)
            }
        )
        alert.addAction(
            UIAlertAction(
                title: "취소",
                style: .cancel
            )
        )
        if let popover =
                alert.popoverPresentationController {
            popover.sourceView = photoSaveButton
            popover.sourceRect =
                photoSaveButton.bounds
        }
        present(alert, animated: true)
    }

    private func saveCurrentFrameToPhotos() {
        guard let image = capturedImage() else {
            announceRemoteStatus(
                "카메라 프레임을 기다리는 중입니다."
            )
            return
        }
        saveImageToPhotos(image)
    }

    private func saveImageToPhotos(
        _ image: UIImage
    ) {
        photoSaveButton.isEnabled = false
        statusLabel.text =
            "사진 보관함에 저장하는 중"
        Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                self.photoSaveButton
                    .isEnabled = true
            }
            do {
                let capture =
                    try MagnifierPhotoCapture(
                        image: image
                    )
                try await self
                    .photoSaveService
                    .saveToPhotoLibrary(
                        capture
                    )
                UIImpactFeedbackGenerator(
                    style: .medium
                ).impactOccurred()
                self.announceRemoteStatus(
                    "사진 보관함에 저장했습니다."
                )
            } catch {
                self.announceRemoteStatus(
                    "사진을 저장하지 못했습니다: "
                        + error
                            .localizedDescription
                )
            }
        }
    }

    private func exportImageToFiles(
        _ image: UIImage
    ) {
        do {
            photoSaveService
                .removeTemporaryExport(
                    at:
                        pendingPhotoExportURL
                )
            let capture =
                try MagnifierPhotoCapture(
                    image: image
                )
            let url =
                try photoSaveService
                    .makeTemporaryExportURL(
                        for: capture
                    )
            pendingPhotoExportURL = url
            let picker =
                UIDocumentPickerViewController(
                    forExporting: [url],
                    asCopy: true
                )
            picker.delegate = self
            present(picker, animated: true)
        } catch {
            announceRemoteStatus(
                "Files로 내보내지 못했습니다: "
                    + error.localizedDescription
            )
        }
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        photoSaveService.removeTemporaryExport(
            at: pendingPhotoExportURL
        )
        pendingPhotoExportURL = nil
        announceRemoteStatus(
            "Files에 사진을 저장했습니다."
        )
    }

    func documentPickerWasCancelled(
        _ controller: UIDocumentPickerViewController
    ) {
        photoSaveService.removeTemporaryExport(
            at: pendingPhotoExportURL
        )
        pendingPhotoExportURL = nil
        statusLabel.text =
            "Files 저장을 취소했습니다."
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
        let image =
            CIImage(cvPixelBuffer: pixelBuffer)
        let baseImage =
            displayAdjustment.colorIndex == nil
                ? currentFilter.apply(to: image)
                : image
        return displayAdjustment.applying(
            to: baseImage
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
            let framePixelHeight = Double(
                CVPixelBufferGetHeight(pixelBuffer)
            )
            let recognizedLines = sorted.compactMap {
                observation
                    -> (text: String, height: Double)? in
                guard let candidate = observation
                    .topCandidates(1)
                    .first else {
                    return nil
                }
                let text = candidate.string
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                guard !text.isEmpty else {
                    return nil
                }
                return (
                    text,
                    Double(
                        observation.boundingBox.height
                    ) * framePixelHeight
                )
            }
            let text = recognizedLines
                .map(\.text)
                .joined(separator: "\n")
            let quality = LiveTextDeduplicator.quality(
                lineTexts: recognizedLines.map(\.text),
                linePixelHeights:
                    recognizedLines.map(\.height)
            )

            DispatchQueue.main.async { [weak self] in
                self?.publishLiveText(
                    text,
                    quality: quality
                )
            }
        } catch {
            publishStatus(
                "실시간 OCR 오류: \(error.localizedDescription)"
            )
        }
    }

    private func publishLiveText(
        _ text: String,
        quality: LiveTextOCRQuality
    ) {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let decision = liveTextDeduplicator.evaluate(
            trimmed,
            quality: quality,
            now: CACurrentMediaTime(),
            isSpeaking: tts.isSpeaking
        )

        guard decision.disposition != .noText else {
            liveTextLabel.text = "텍스트를 찾는 중…"
            liveTextLabel.accessibilityValue = nil
            statusLabel.text = "실시간 텍스트를 찾는 중"
            return
        }
        liveTextLabel.text = trimmed
        liveTextLabel.accessibilityValue = trimmed

        switch decision.disposition {
        case .lowQuality:
            statusLabel.text =
                "글자가 작아 더 가까이 비춰 주세요"
        case .checking:
            statusLabel.text =
                "인식 결과를 확인하는 중"
        case .suppressed:
            statusLabel.text =
                "실시간 텍스트를 찾는 중"
        case .announce:
            guard isLiveReadingEnabled else {
                return
            }
            statusLabel.text = "인식한 텍스트 읽는 중"
            tts.speak(decision.text)
        case .noText:
            return
        }
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
            liveTextDeduplicator.reset()
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
