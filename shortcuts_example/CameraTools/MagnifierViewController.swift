import AVFoundation
import CoreImage
import ImageIO
import MLKit
import MetalKit
import OSLog
import SwiftUI
import UIKit

nonisolated enum MagnifierCameraMode: Sendable {
    case magnifier
    case liveTextReader
    case imageDescription
    case askAI
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

    /// 안드로이드는 저품질 프레임에서도 중립 문구만 보여 준다.
    /// 여기서는 정말 글자가 작아 안내가 필요한 구간만 따로 구분해,
    /// 임계선 근처(12~18px)에서 사용자를 탓하지 않도록 한다.
    var needsCloserGuidance: Bool {
        elementCount >= 8 && medianGlyphHeight < 12
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

        guard !quality.isLowForSpeech
                || Self.isUsableDenseRecognition(
                    normalized,
                    quality: quality
                ) else {
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
        elementPixelHeights: [Double]
    ) -> LiveTextOCRQuality {
        var glyphHeights = elementPixelHeights
            .map { max(0, Int($0)) }
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

    private static func isUsableDenseRecognition(
        _ text: String,
        quality: LiveTextOCRQuality
    ) -> Bool {
        text.count >= richTextMinimumCharacters
            && quality.elementCount
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
            return AppLocalization.string("원본")
        case .grayscale:
            return AppLocalization.string("흑백")
        case .inverted:
            return AppLocalization.string("반전")
        case .highContrast:
            return AppLocalization.string("고대비")
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
    private struct LiveOCRFrameContext {
        let width: Int
        let height: Int
        let pixelFormat: String
        let videoRotationAngle: Double
        let physicalRotationApplied: Bool
        let imageOrientation: UIImage.Orientation
        let previewSize: CGSize
    }

    var onClose: (() -> Void)?
    var onCapture: ((UIImage) -> Void)?
    var onOpenDocumentScan: (() -> Void)?
    var onOpenLiveTextReader: (() -> Void)?
    var onOpenImageAnalysisMode: (() -> Void)?
    var onOpenBasicMode: (() -> Void)?
    var onOpenPhotoReview: (() -> Void)?
    var onOpenAskAIMode: (() -> Void)?
    var onDescribeImage: ((UIImage) -> Void)?

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
    private let liveTextRecognizer =
        TextRecognizer.textRecognizer(
            options: KoreanTextRecognizerOptions()
        )
    private let liveTextLogger = Logger(
        subsystem:
            Bundle.main.bundleIdentifier
                ?? "RivoPad",
        category: "LiveTextReader"
    )
    /// 화면 표시용 렌더 컨텍스트와 분리해 30fps 미리보기 루프와
    /// OCR 크롭이 서로를 기다리지 않게 한다.
    private let liveOCRRenderContext = CIContext(
        options: [
            .cacheIntermediates: false
        ]
    )

    private var cameraInput: AVCaptureDeviceInput?
    private var rotationCoordinator:
        AVCaptureDevice.RotationCoordinator?
    private var latestPixelBuffer: CVPixelBuffer?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var currentFilter: MagnifierFilter = .normal
    private var displayAdjustment:
        MagnifierDisplayAdjustment = .defaultValue
    private let displayPreferenceStore:
        MagnifierDisplayPreferenceStore =
            MagnifierDisplayPreferenceStore()
    private var pinchStartZoom: CGFloat = 1
    private var isTorchEnabled = false
    private var isLiveReadingEnabled = true
    private var isLiveOCRBusy = false
    private var lastLiveOCRTime: CFTimeInterval = 0
    private var liveOCRRequestSequence: UInt64 = 0
    private var liveVideoRotationApplied = false
    private var liveInterfaceOrientationRawValue =
        UIInterfaceOrientation.portrait.rawValue
    private var liveFrameCameraPosition:
        AVCaptureDevice.Position = .back
    private var livePreviewSize: CGSize = .zero
    private var liveTextDeduplicator =
        LiveTextDeduplicator()
    private let liveOCRInterval: CFTimeInterval = 1
    /// 확인 중 상태에 미리 보여 줄 인식 텍스트 길이(안드로이드와 동일).
    private static let statusPreviewCharacters = 48
    /// 디버그 콘솔에 남길 인식 텍스트 최대 길이(안드로이드와 동일).
    private static let logTextMaximumCharacters = 2_000
    private var lastRemoteEventID: UInt64 = 0
    private var isCameraScreenVisible = false
    private var isOpeningCameraTool = false
    private weak var moreOptionsController: UIViewController?

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
    private let gridButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private let torchButton = UIButton(type: .system)
    private let switchCameraButton = UIButton(type: .system)
    private let photoSaveButton = UIButton(type: .system)
    private let captureButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let liveTextLabel = UILabel()
    private let gridOverlay = UIView()
    private let verticalGridLine = UIView()
    private let horizontalGridLine = UIView()
    private var zoomOverlayHideWorkItem:
        DispatchWorkItem?
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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isCameraScreenVisible = true
        isOpeningCameraTool = false
        view.isUserInteractionEnabled = true
        requestCameraAndStart()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateVideoRotation()
        updateLivePreviewSize()
        if mode != .liveTextReader {
            zoomLabel.font = .monospacedDigitSystemFont(
                ofSize: min(
                    view.bounds.width,
                    view.bounds.height
                ) * 0.4,
                weight: .regular
            )
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isCameraScreenVisible = false
        zoomOverlayHideWorkItem?.cancel()
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

        configureSharedCameraControls()
        if mode == .liveTextReader {
            setupLiveTextReaderUI()
        } else {
            setupAndroidCameraUI()
        }
    }

    private func configureSharedCameraControls() {
        zoomSlider.minimumValue = 1
        zoomSlider.maximumValue = 10
        zoomSlider.value = 1
        zoomSlider.addTarget(
            self,
            action: #selector(zoomSliderChanged),
            for: .valueChanged
        )

        filterControl.selectedSegmentIndex =
            MagnifierFilter.normal.rawValue
        filterControl.addTarget(
            self,
            action: #selector(filterChanged),
            for: .valueChanged
        )

        statusLabel.text = AppLocalization.string(
            mode == .liveTextReader
            ? "카메라를 준비 중입니다."
            : "카메라 준비 중"
        )
        statusLabel.numberOfLines = 2

        closeButton.addTarget(
            self,
            action: #selector(closeTapped),
            for: .touchUpInside
        )
        closeButton.accessibilityLabel =
            AppLocalization.string("닫기")
    }

    private func setupLiveTextReaderUI() {
        // 문서 스캔과 같은 구성: 상단 상태 캡슐 + 하단 닫기 버튼.
        // 라벨과 버튼을 감싸는 패널은 두지 않는다.
        configureModeButton()
        moreButton.accessibilityIdentifier = "camera.more"
        moreButton.accessibilityHint = AppLocalization.string(
            "문서 스캔, 실시간 문자 읽기, 이미지 분석, AI 질문하기, 사진 분석 모드를 엽니다."
        )
        view.addSubview(moreButton)
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(
            ofSize: 17,
            weight: .bold
        )
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.backgroundColor = UIColor(
            red: 37 / 255,
            green: 37 / 255,
            blue: 37 / 255,
            alpha: 0.15
        )
        statusLabel.layer.cornerRadius = 22
        statusLabel.layer.masksToBounds = true
        statusLabel.layer.borderWidth = 1
        statusLabel.layer.borderColor = UIColor(
            red: 124 / 255,
            green: 158 / 255,
            blue: 1,
            alpha: 0.2
        ).cgColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.isAccessibilityElement = true
        statusLabel.accessibilityTraits = .updatesFrequently
        view.addSubview(statusLabel)

        // 문서 스캔의 촬영 버튼과 같은 크기·칠. 화면 가운데 정렬.
        var configuration = UIButton.Configuration.filled()
        configuration.title = AppLocalization.string("닫기")
        configuration.baseBackgroundColor = UIColor(
            white: 1,
            alpha: 0.14
        )
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .large
        closeButton.configuration = configuration
        closeButton.titleLabel?.font = .preferredFont(
            forTextStyle: .headline
        )
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            moreButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 12
            ),
            moreButton.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -16
            ),
            moreButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
            statusLabel.topAnchor.constraint(
                equalTo: moreButton.bottomAnchor,
                constant: 12
            ),
            statusLabel.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 24
            ),
            statusLabel.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -24
            ),
            statusLabel.heightAnchor.constraint(
                greaterThanOrEqualToConstant: 48
            ),

            closeButton.centerXAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.centerXAnchor
            ),
            // 스캐너 버튼 폭: (safe area 폭 - 좌우 24*2 - 간격 12) / 2
            closeButton.widthAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.widthAnchor,
                multiplier: 0.5,
                constant: -30
            ),
            closeButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -34
            ),
            closeButton.heightAnchor.constraint(
                equalToConstant: 52
            ),
        ])
    }

    private func setupAndroidCameraUI() {
        view.addSubview(gridOverlay)
        configureGridOverlay()

        if mode != .liveTextReader {
            configureModeButton()
            moreButton.accessibilityIdentifier = "camera.more"
            moreButton.accessibilityHint = AppLocalization.string(
                "문서 스캔, 실시간 문자 읽기, 이미지 분석, AI 질문하기, 사진 분석 모드를 엽니다."
            )
            view.addSubview(moreButton)
        }
        configureCircularCameraButton(
            gridButton,
            systemImage: "grid",
            accessibilityLabel: "격자 토글",
            action: #selector(gridTapped),
            size: 56
        )
        configureCircularCameraButton(
            torchButton,
            systemImage: "flashlight.off.fill",
            accessibilityLabel: "플래시 토글",
            action: #selector(torchTapped),
            size: 56
        )
        configureCircularCameraButton(
            switchCameraButton,
            systemImage: "camera.rotate.fill",
            accessibilityLabel: "카메라 전환",
            action: #selector(switchCameraTapped),
            size: 56
        )
        configureShutterButton()

        let actionStack = UIStackView(
            arrangedSubviews: [
                gridButton,
                torchButton,
                switchCameraButton,
                captureButton,
            ]
        )
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.axis = .vertical
        actionStack.alignment = .center
        actionStack.spacing = 16
        view.addSubview(actionStack)

        // 닫기는 라우트의 뒤로가기 버튼이 담당한다. 별도 X 버튼은 두지 않는다.
        zoomLabel.translatesAutoresizingMaskIntoConstraints = false
        zoomLabel.text = "1.0"
        zoomLabel.textColor = .white
        zoomLabel.textAlignment = .center
        zoomLabel.layer.shadowColor = UIColor.black.cgColor
        zoomLabel.layer.shadowOpacity = 0.7
        zoomLabel.layer.shadowRadius = 10
        zoomLabel.isHidden = true
        zoomLabel.isAccessibilityElement = false
        view.addSubview(zoomLabel)

        let shutterVerticalPosition = NSLayoutConstraint(
            item: captureButton,
            attribute: .centerY,
            relatedBy: .equal,
            toItem: view,
            attribute: .bottom,
            multiplier: 0.6,
            constant: 0
        )
        // 모드 버튼은 뒤로가기와 겹치지 않도록 오른쪽 위에 따로 둔다.
        shutterVerticalPosition.priority = .defaultHigh
        NSLayoutConstraint.activate([
            actionStack.topAnchor.constraint(
                greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 12
            ),
            actionStack.bottomAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -12
            ),
            actionStack.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -16
            ),
            shutterVerticalPosition,
            zoomLabel.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),
            zoomLabel.centerYAnchor.constraint(
                equalTo: view.centerYAnchor
            ),
        ])
        if mode != .liveTextReader {
            NSLayoutConstraint.activate([
                moreButton.topAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.topAnchor,
                    constant: 12
                ),
                moreButton.trailingAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                    constant: -16
                ),
                moreButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
            ])
        }
    }

    private func configureModeButton() {
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        let modeName: String
        switch mode {
        case .magnifier: modeName = "기본"
        case .imageDescription: modeName = "이미지 분석"
        case .askAI: modeName = "AI 질문하기"
        case .liveTextReader: modeName = "실시간 문자 읽기"
        }
        configuration.title = AppLocalization.format("모드: %@", AppLocalization.string(modeName))
        configuration.image = UIImage(systemName: "slider.horizontal.3")
        configuration.imagePadding = 10
        configuration.baseBackgroundColor = UIColor(
            red: 40 / 255,
            green: 53 / 255,
            blue: 70 / 255,
            alpha: 1
        )
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 8,
            leading: 16,
            bottom: 8,
            trailing: 12
        )
        moreButton.configuration = configuration
        moreButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        moreButton.layer.cornerRadius = 20
        moreButton.layer.borderWidth = 2.5
        moreButton.layer.borderColor = UIColor(
            red: 240 / 255,
            green: 244 / 255,
            blue: 250 / 255,
            alpha: 1
        ).cgColor
        moreButton.clipsToBounds = true
        moreButton.accessibilityLabel = AppLocalization.format("모드, %@", AppLocalization.string(modeName))
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
    }

    private func configureGridOverlay() {
        gridOverlay.translatesAutoresizingMaskIntoConstraints = false
        gridOverlay.isUserInteractionEnabled = false
        gridOverlay.isHidden = true
        verticalGridLine.translatesAutoresizingMaskIntoConstraints = false
        horizontalGridLine.translatesAutoresizingMaskIntoConstraints = false
        verticalGridLine.backgroundColor = .black
        horizontalGridLine.backgroundColor = .black
        gridOverlay.addSubview(verticalGridLine)
        gridOverlay.addSubview(horizontalGridLine)
        NSLayoutConstraint.activate([
            gridOverlay.leadingAnchor.constraint(
                equalTo: view.leadingAnchor
            ),
            gridOverlay.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            ),
            gridOverlay.topAnchor.constraint(
                equalTo: view.topAnchor
            ),
            gridOverlay.bottomAnchor.constraint(
                equalTo: view.bottomAnchor
            ),
            verticalGridLine.centerXAnchor.constraint(
                equalTo: gridOverlay.centerXAnchor
            ),
            verticalGridLine.topAnchor.constraint(
                equalTo: gridOverlay.topAnchor
            ),
            verticalGridLine.bottomAnchor.constraint(
                equalTo: gridOverlay.bottomAnchor
            ),
            verticalGridLine.widthAnchor.constraint(
                equalToConstant: 1
            ),
            horizontalGridLine.centerYAnchor.constraint(
                equalTo: gridOverlay.centerYAnchor
            ),
            horizontalGridLine.leadingAnchor.constraint(
                equalTo: gridOverlay.leadingAnchor
            ),
            horizontalGridLine.trailingAnchor.constraint(
                equalTo: gridOverlay.trailingAnchor
            ),
            horizontalGridLine.heightAnchor.constraint(
                equalToConstant: 1
            ),
        ])
    }

    private func configureCircularCameraButton(
        _ button: UIButton,
        systemImage: String,
        accessibilityLabel: String,
        action: Selector,
        size: CGFloat
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.configuration = nil
        button.setImage(
            UIImage(
                systemName: systemImage,
                withConfiguration:
                    UIImage.SymbolConfiguration(
                        pointSize: 24,
                        weight: .semibold
                    )
            ),
            for: .normal
        )
        button.tintColor = .white
        button.backgroundColor = UIColor(
            red: 0.145,
            green: 0.145,
            blue: 0.145,
            alpha: 1
        )
        button.layer.cornerRadius = size / 2
        button.accessibilityLabel =
            AppLocalization.string(accessibilityLabel)
        button.addTarget(
            self,
            action: action,
            for: .touchUpInside
        )
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(
                equalToConstant: size
            ),
            button.heightAnchor.constraint(
                equalToConstant: size
            ),
        ])
    }

    private func configureShutterButton() {
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.configuration = nil
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 35
        captureButton.layer.shadowColor = UIColor.black.cgColor
        captureButton.layer.shadowOpacity = 0.45
        captureButton.layer.shadowRadius = 9
        captureButton.layer.shadowOffset = CGSize(width: 0, height: 3)
        if mode == .imageDescription || mode == .askAI {
            captureButton.setImage(
                UIImage(systemName: mode == .askAI ? "bubble.left.and.bubble.right" : "sparkles"),
                for: .normal
            )
            captureButton.tintColor = .black
            captureButton.accessibilityLabel =
                AppLocalization.string(mode == .askAI ? "AI 질문하기" : "이미지 설명")
        } else {
            captureButton.setImage(nil, for: .normal)
            captureButton.accessibilityLabel =
                AppLocalization.string("촬영")
        }
        captureButton.addTarget(
            self,
            action: #selector(captureTapped),
            for: .touchUpInside
        )
        NSLayoutConstraint.activate([
            captureButton.widthAnchor.constraint(
                equalToConstant: 70
            ),
            captureButton.heightAnchor.constraint(
                equalToConstant: 70
            ),
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
        guard mode != .liveTextReader else {
            return
        }

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

        let swipeLeft = UISwipeGestureRecognizer(
            target: self,
            action: #selector(handleHorizontalSwipe(_:))
        )
        swipeLeft.direction = .left
        cameraView.addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(
            target: self,
            action: #selector(handleHorizontalSwipe(_:))
        )
        swipeRight.direction = .right
        cameraView.addGestureRecognizer(swipeRight)

        let swipeUp = UISwipeGestureRecognizer(
            target: self,
            action: #selector(handleVerticalSwipe)
        )
        swipeUp.direction = .up
        cameraView.addGestureRecognizer(swipeUp)

        let swipeDown = UISwipeGestureRecognizer(
            target: self,
            action: #selector(handleVerticalSwipe)
        )
        swipeDown.direction = .down
        cameraView.addGestureRecognizer(swipeDown)

        cameraView.accessibilityHint =
            AppLocalization.string(
                "핀치로 확대하고, 좌우로 쓸어 색 조합을 바꾸며, 위아래로 쓸어 카메라를 전환합니다. 두 번 탭하면 원본 색상으로 돌아갑니다."
            )
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

            guard isCameraScreenVisible, !isOpeningCameraTool else {
                return
            }
            guard authorized else {
                statusLabel.text =
                    AppLocalization.string(
                        mode == .liveTextReader
                        ? "카메라 권한이 필요합니다."
                        : "설정에서 카메라 권한을 허용해 주세요."
                    )
                return
            }
            sessionQueue.async { [weak self] in
                guard let self else { return }
                if self.cameraInput == nil {
                    self.configureSession(position: .back)
                }
                if self.cameraInput != nil, !self.session.isRunning {
                    self.session.startRunning()
                }
            }
        }
    }

    private func configureSession(
        position: AVCaptureDevice.Position
    ) {
        session.beginConfiguration()
        if mode == .liveTextReader,
           session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else {
            session.sessionPreset = .high
        }

        if let cameraInput {
            session.removeInput(cameraInput)
        }

        guard let device = cameraDevice(position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            publishStatus(
                AppLocalization.string(
                    "카메라를 사용할 수 없습니다."
                )
            )
            return
        }
        session.addInput(input)
        cameraInput = input
        currentPosition = position
        liveOCRLock.lock()
        liveVideoRotationApplied = false
        liveFrameCameraPosition = position
        liveOCRLock.unlock()
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
                publishStatus(
                    AppLocalization.string(
                        "카메라 영상을 받을 수 없습니다."
                    )
                )
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
                ? AppLocalization.string(
                    "글자를 찾는 중입니다."
                )
                : (
                    position == .back
                    ? AppLocalization.string(
                        "후면 카메라"
                    )
                    : AppLocalization.string(
                        "전면 카메라"
                    )
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
        guard let connection = videoOutput.connection(
            with: .video
        ) else {
            return
        }

        let angle = rotationCoordinator?
            .videoRotationAngleForHorizonLevelCapture
        let physicalRotationApplied = angle.map {
            connection.isVideoRotationAngleSupported($0)
        } ?? false
        if let angle,
           physicalRotationApplied {
            connection.videoRotationAngle = angle
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored =
                currentPosition == .front
        }

        let interfaceOrientation =
            view.window?.windowScene?.interfaceOrientation
                ?? .portrait
        liveOCRLock.lock()
        liveVideoRotationApplied =
            physicalRotationApplied
        liveInterfaceOrientationRawValue =
            interfaceOrientation.rawValue
        liveFrameCameraPosition = currentPosition
        liveOCRLock.unlock()
    }

    private func updateLivePreviewSize() {
        let size = cameraView.bounds.size
        liveOCRLock.lock()
        livePreviewSize = size
        liveOCRLock.unlock()
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

        guard !isOpeningCameraTool else { return }
        if moreOptionsController != nil {
            if case .close = action {
                dismissMoreOptions()
            }
            return
        }

        if mode == .liveTextReader {
            switch action {
            case .close:
                closeTapped()
            case .enterCameraMode:
                announceRemoteStatus(
                    AppLocalization.string(
                        "바로 읽기. 4 닫기"
                    )
                )
            default:
                break
            }
            return
        }

        switch action {
        case .enterCameraMode(let showGuide):
            let seventhKeyAction: String
            switch mode {
            case .magnifier:
                seventhKeyAction =
                    AppLocalization.string(
                        "7 사진 저장"
                    )
            case .liveTextReader:
                seventhKeyAction =
                    AppLocalization.string(
                        "7 사용 안 함"
                    )
            case .imageDescription:
                seventhKeyAction =
                    AppLocalization.string(
                        "7 이미지 설명"
                    )
            case .askAI:
                seventhKeyAction = AppLocalization.string("7 AI 질문하기")
            }
            announceRemoteStatus(
                showGuide
                    ? AppLocalization.format(
                        "카메라 조작 모드. 4 닫기, 5 카메라 전환, 6 토치, %@, R2 초점, 별표 0 샵 확대",
                        seventhKeyAction
                    )
                    : AppLocalization.string(
                        "카메라 조작 모드"
                    )
            )
        case .enterDisplayMode(let showGuide):
            restoreSavedDisplayAdjustment()
            announceRemoteStatus(
                showGuide
                    ? AppLocalization.string(
                        "화면 조작 모드. 4 이전 색상, 5 원본, 6 다음 색상, 7 8 9 임계값, 별표 0 샵 밝기, R2 반전, R1 카메라 조작"
                    )
                    : AppLocalization.string(
                        "화면 조작 모드"
                    )
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
            showZoomOverlay()
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
        showZoomOverlay()
        announceCurrentZoom()
    }

    private func announceCurrentZoom() {
        UIAccessibility.post(
            notification: .announcement,
            argument:
                AppLocalization.format(
                    "확대 배율 %@",
                    zoomLabel.text ?? ""
                )
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
        torchButton.setImage(
            UIImage(
                systemName:
                    isTorchEnabled
                    ? "flashlight.on.fill"
                    : "flashlight.off.fill",
                withConfiguration:
                    UIImage.SymbolConfiguration(
                        pointSize: 24,
                        weight: .semibold
                    )
            ),
            for: .normal
        )
        torchButton.accessibilityValue =
            isTorchEnabled
            ? AppLocalization.string("켜짐")
            : AppLocalization.string("꺼짐")
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
            argument: AppLocalization.format(
                "%@ 필터",
                currentFilter.title
            )
        )
    }

    private func applyRemoteDisplayAction(
        _ action: RivoMagnifierRemoteAction
    ) {
        displayAdjustment =
            displayAdjustment.updated(for: action)
        persistDisplayAdjustment(
            after: action
        )

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
            message = AppLocalization.format(
                "색상 %@",
                AppLocalization.string(
                    theme.name
                )
            )
        case .originalColor:
            currentFilter = .normal
            filterControl.selectedSegmentIndex =
                MagnifierFilter.normal.rawValue
            message = AppLocalization.string(
                "원본 색상"
            )
        case .decreaseThreshold,
             .resetThreshold,
             .increaseThreshold:
            message = AppLocalization.format(
                "색상 임계값 %.0f퍼센트",
                displayAdjustment.threshold
                    * 100
            )
        case .decreaseBrightness,
             .resetBrightness,
             .increaseBrightness:
            message = AppLocalization.format(
                "미리보기 밝기 %+.0f",
                displayAdjustment.brightness
                    * 100
            )
        case .invertColor:
            message =
                displayAdjustment.isInverted
                ? AppLocalization.string(
                    "미리보기 색상 반전"
                )
                : AppLocalization.string(
                    "미리보기 색상 반전 해제"
                )
        default:
            return
        }
        announceRemoteStatus(message)
    }

    private func restoreSavedDisplayAdjustment() {
        displayAdjustment =
            displayPreferenceStore.load(
                applyingTo:
                    displayAdjustment
            )
        if displayAdjustment.colorIndex != nil {
            filterControl.selectedSegmentIndex =
                UISegmentedControl.noSegment
        }
    }

    private func persistDisplayAdjustment(
        after action:
            RivoMagnifierRemoteAction
    ) {
        switch action {
        case .previousColor,
             .nextColor:
            displayPreferenceStore.saveColor(
                from: displayAdjustment
            )
        case .decreaseThreshold,
             .resetThreshold,
             .increaseThreshold:
            displayPreferenceStore
                .saveThreshold(
                    from:
                        displayAdjustment
                )
        case .invertColor:
            displayPreferenceStore
                .saveInversion(
                    from:
                        displayAdjustment
                )
        default:
            break
        }
    }

    private func focusAtCenter() {
        guard let device = cameraInput?.device else {
            announceRemoteStatus(
                AppLocalization.string(
                    "카메라가 준비되지 않았습니다."
                )
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
                    ? AppLocalization.string(
                        "화면 중앙에 초점을 맞춥니다."
                    )
                    : AppLocalization.string(
                        "이 카메라는 수동 초점을 지원하지 않습니다."
                    )
            )
        } catch {
            announceRemoteStatus(
                AppLocalization.format(
                    "초점을 맞추지 못했습니다: %@",
                    error.localizedDescription
                )
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

    @objc private func gridTapped() {
        gridOverlay.isHidden.toggle()
        gridButton.accessibilityValue =
            AppLocalization.string(
                gridOverlay.isHidden
                ? "꺼짐"
                : "켜짐"
            )
    }

    @objc private func switchCameraTapped() {
        setTorch(false)
        let nextPosition: AVCaptureDevice.Position =
            currentPosition == .back ? .front : .back
        sessionQueue.async { [weak self] in
            self?.configureSession(position: nextPosition)
        }
    }

    @objc private func moreTapped() {
        guard !isOpeningCameraTool,
              presentedViewController == nil else { return }

        let dialog = CameraMoreOptionsDialog(
            currentMode: mode,
            onBasic: { [weak self] in
                self?.dismissMoreOptions { [weak self] in
                    guard let self else { return }
                    self.openCameraTool(self.onOpenBasicMode)
                }
            },
            onDocumentScan: { [weak self] in
                self?.dismissMoreOptions { [weak self] in
                    guard let self else { return }
                    self.openCameraTool(self.onOpenDocumentScan)
                }
            },
            onLiveTextReader: { [weak self] in
                self?.dismissMoreOptions { [weak self] in
                    guard let self else { return }
                    self.openCameraTool(self.onOpenLiveTextReader)
                }
            },
            onImageAnalysis: { [weak self] in
                self?.dismissMoreOptions { [weak self] in
                    guard let self else { return }
                    self.openCameraTool(self.onOpenImageAnalysisMode)
                }
            },
            onAskAI: { [weak self] in
                self?.dismissMoreOptions { [weak self] in
                    guard let self else { return }
                    self.openCameraTool(self.onOpenAskAIMode)
                }
            },
            onPhotoReview: { [weak self] in
                self?.dismissMoreOptions { [weak self] in
                    guard let self else { return }
                    self.openCameraTool(self.onOpenPhotoReview)
                }
            },
            onDismiss: { [weak self] in
                self?.dismissMoreOptions()
            }
        )
        let controller = UIHostingController(rootView: dialog)
        controller.view.backgroundColor = .clear
        controller.view.accessibilityViewIsModal = true
        controller.modalPresentationStyle = .overFullScreen
        controller.modalTransitionStyle = .crossDissolve
        moreOptionsController = controller
        present(controller, animated: true)
    }

    private func dismissMoreOptions(completion: (() -> Void)? = nil) {
        guard let controller = moreOptionsController,
              !controller.isBeingDismissed else { return }
        controller.dismiss(animated: true) { [weak self] in
            self?.moreOptionsController = nil
            completion?()
        }
    }

    private func openCameraTool(_ action: (() -> Void)?) {
        guard let action, isCameraScreenVisible,
              !isOpeningCameraTool else { return }
        isOpeningCameraTool = true
        view.isUserInteractionEnabled = false
        setTorch(false)
        // 다음 화면이 자체 카메라를 시작하기 전에 현재 세션을 해제한다.
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async { [weak self] in
                guard self?.isCameraScreenVisible == true else { return }
                action()
            }
        }
    }

    private func captureForImageDescription(
        _ onImage: ((UIImage) -> Void)?
    ) {
        guard let onImage, !isOpeningCameraTool else { return }
        guard let image = capturedImage(applyingDisplayAdjustments: false) else {
            SoundEffectManager.shared.play(.fail)
            let message = AppLocalization.string(
                "카메라 프레임을 기다리는 중입니다."
            )
            announceRemoteStatus(message)
            let alert = UIAlertController(
                title: AppLocalization.string("이미지 설명"),
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(
                title: AppLocalization.string("확인"),
                style: .default
            ))
            present(alert, animated: true)
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        SoundEffectManager.shared.play(.cameraShot2)
        openCameraTool { onImage(image) }
    }

    @objc private func captureTapped() {
        switch mode {
        case .liveTextReader:
            return
        case .magnifier:
            saveCurrentFrameToPhotos()
        case .imageDescription:
            captureForImageDescription(onCapture)
        case .askAI:
            captureForImageDescription(onCapture)
        }
    }

    private var captureButtonTitle: String {
        switch mode {
        case .magnifier:
            return AppLocalization.string(
                "텍스트 읽기"
            )
        case .liveTextReader:
            return AppLocalization.string(
                "읽기 일시정지"
            )
        case .imageDescription:
            return AppLocalization.string(
                "이미지 설명"
            )
        case .askAI:
            return AppLocalization.string("AI 질문하기")
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
        case .askAI:
            return "bubble.left.and.bubble.right"
        }
    }

    @objc private func photoSaveTapped() {
        guard let image = capturedImage() else {
            announceRemoteStatus(
                AppLocalization.string(
                    "카메라 프레임을 기다리는 중입니다."
                )
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
            title: AppLocalization.string(
                "사진 저장"
            ),
            message:
                AppLocalization.string(
                    "저장할 위치를 선택합니다. 사진 보관함은 추가 전용 권한만 사용합니다."
                ),
            preferredStyle: .actionSheet
        )
        alert.addAction(
            UIAlertAction(
                title: AppLocalization.string(
                    "사진 보관함"
                ),
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
                title: AppLocalization.string(
                    "취소"
                ),
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
                AppLocalization.string(
                    "카메라 프레임을 기다리는 중입니다."
                )
            )
            return
        }
        saveImageToPhotos(image)
    }

    private func saveImageToPhotos(
        _ image: UIImage
    ) {
        SoundEffectManager.shared.play(
            .cameraShot2
        )
        photoSaveButton.isEnabled = false
        statusLabel.text =
            AppLocalization.string(
                "사진 보관함에 저장하는 중"
            )
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
                    AppLocalization.string(
                        "사진 보관함에 저장했습니다."
                    )
                )
            } catch {
                self.announceRemoteStatus(
                    AppLocalization.format(
                        "사진을 저장하지 못했습니다: %@",
                        error.localizedDescription
                    )
                )
            }
        }
    }

    private func exportImageToFiles(
        _ image: UIImage
    ) {
        SoundEffectManager.shared.play(
            .cameraShot2
        )
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
                AppLocalization.format(
                    "Files로 내보내지 못했습니다: %@",
                    error.localizedDescription
                )
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
            AppLocalization.string(
                "Files에 사진을 저장했습니다."
            )
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
            AppLocalization.string(
                "Files 저장을 취소했습니다."
            )
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
            showZoomOverlay()
        default:
            break
        }
    }

    @objc private func handleDoubleTap() {
        currentFilter = .normal
        filterControl.selectedSegmentIndex =
            MagnifierFilter.normal.rawValue
        displayAdjustment.colorIndex = nil
        displayAdjustment.isInverted = false
    }

    @objc private func handleHorizontalSwipe(
        _ gesture: UISwipeGestureRecognizer
    ) {
        applyRemoteDisplayAction(
            gesture.direction == .left
            ? .previousColor
            : .nextColor
        )
    }

    @objc private func handleVerticalSwipe() {
        switchCameraTapped()
    }

    private func showZoomOverlay() {
        zoomOverlayHideWorkItem?.cancel()
        zoomLabel.text = String(
            format: "%.1f",
            cameraInput?.device.videoZoomFactor
                ?? CGFloat(zoomSlider.value)
        )
        zoomLabel.isHidden = false

        let workItem = DispatchWorkItem { [weak self] in
            self?.zoomLabel.isHidden = true
        }
        zoomOverlayHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.6,
            execute: workItem
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
            let context = makeLiveOCRFrameContext(
                pixelBuffer: pixelBuffer,
                connection: connection
            )
            liveOCRQueue.async { [weak self] in
                self?.recognizeLiveText(
                    in: pixelBuffer,
                    context: context
                )
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

    private func currentProcessedImage(
        applyingDisplayAdjustments: Bool = true
    ) -> CIImage? {
        frameLock.lock()
        let pixelBuffer = latestPixelBuffer
        frameLock.unlock()
        guard let pixelBuffer else {
            return nil
        }
        let image =
            CIImage(cvPixelBuffer: pixelBuffer)
        guard applyingDisplayAdjustments else { return image }
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

    private func capturedImage(
        applyingDisplayAdjustments: Bool = true
    ) -> UIImage? {
        guard let image = currentProcessedImage(
                  applyingDisplayAdjustments: applyingDisplayAdjustments
              ),
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

    private func makeLiveOCRFrameContext(
        pixelBuffer: CVPixelBuffer,
        connection: AVCaptureConnection
    ) -> LiveOCRFrameContext {
        liveOCRLock.lock()
        let physicalRotationApplied =
            liveVideoRotationApplied
        let interfaceOrientation =
            UIInterfaceOrientation(
                rawValue: liveInterfaceOrientationRawValue
            ) ?? .portrait
        let cameraPosition = liveFrameCameraPosition
        let previewSize = livePreviewSize
        liveOCRLock.unlock()

        let imageOrientation: UIImage.Orientation
        if physicalRotationApplied {
            // AVCaptureVideoDataOutput physically rotates its pixel
            // buffers when videoRotationAngle is applied.
            imageOrientation = .up
        } else {
            imageOrientation = Self.mlKitImageOrientation(
                interfaceOrientation: interfaceOrientation,
                cameraPosition: cameraPosition
            )
        }

        return LiveOCRFrameContext(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            pixelFormat: Self.fourCharacterCode(
                CVPixelBufferGetPixelFormatType(pixelBuffer)
            ),
            videoRotationAngle:
                Double(connection.videoRotationAngle),
            physicalRotationApplied:
                physicalRotationApplied,
            imageOrientation: imageOrientation,
            previewSize: previewSize
        )
    }

    private static func mlKitImageOrientation(
        interfaceOrientation: UIInterfaceOrientation,
        cameraPosition: AVCaptureDevice.Position
    ) -> UIImage.Orientation {
        switch interfaceOrientation {
        case .portrait:
            return cameraPosition == .front
                ? .leftMirrored
                : .right
        case .portraitUpsideDown:
            return cameraPosition == .front
                ? .rightMirrored
                : .left
        case .landscapeLeft:
            return cameraPosition == .front
                ? .downMirrored
                : .up
        case .landscapeRight:
            return cameraPosition == .front
                ? .upMirrored
                : .down
        case .unknown:
            return .up
        @unknown default:
            return .up
        }
    }

    private static func fourCharacterCode(
        _ code: OSType
    ) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii)
            ?? String(code)
    }

    private func recognizeLiveText(
        in pixelBuffer: CVPixelBuffer,
        context: LiveOCRFrameContext
    ) {
        defer {
            liveOCRLock.lock()
            isLiveOCRBusy = false
            liveOCRLock.unlock()
        }

        liveOCRRequestSequence &+= 1
        let requestID = liveOCRRequestSequence
        let startedAt = CACurrentMediaTime()
        traceLiveText(
            "request=\(requestID) start frame=\(context.width)x\(context.height) format=\(context.pixelFormat) rotation=\(context.videoRotationAngle) physicalRotation=\(context.physicalRotationApplied) mlkitOrientation=\(context.imageOrientation.rawValue)"
        )

        guard let visible = makeVisibleVisionImage(
            pixelBuffer: pixelBuffer,
            context: context
        ) else {
            traceLiveTextError(
                "request=\(requestID) crop_failed"
            )
            publishStatus(
                AppLocalization.string(
                    "글자를 찾는 중입니다."
                )
            )
            return
        }

        do {
            let result = try liveTextRecognizer
                .results(in: visible.image)
            let elementHeights = result.blocks
                .flatMap(\.lines)
                .flatMap(\.elements)
                .map { Double($0.frame.height) }
            let quality = LiveTextDeduplicator.quality(
                elementPixelHeights: elementHeights
            )
            let lineCount = result.blocks
                .reduce(0) { $0 + $1.lines.count }
            let elapsedMilliseconds = Int(
                (CACurrentMediaTime() - startedAt) * 1_000
            )
            traceLiveText(
                "request=\(requestID) recognized elapsedMs=\(elapsedMilliseconds) crop=\(Int(visible.cropSize.width))x\(Int(visible.cropSize.height)) textLength=\(result.text.count) blocks=\(result.blocks.count) lines=\(lineCount) elements=\(quality.elementCount) medianGlyphPx=\(quality.medianGlyphHeight) below16Pct=\(quality.below16Percentage)"
            )
            traceLiveTextContent(
                "request=\(requestID) raw",
                result.text
            )

            DispatchQueue.main.async { [weak self] in
                self?.publishLiveText(
                    result.text,
                    quality: quality,
                    requestID: requestID
                )
            }
        } catch {
            let elapsedMilliseconds = Int(
                (CACurrentMediaTime() - startedAt) * 1_000
            )
            traceLiveTextError(
                "request=\(requestID) failed elapsedMs=\(elapsedMilliseconds) error=\(String(describing: error))"
            )
            publishStatus(
                AppLocalization.string(
                    "글자를 찾는 중입니다."
                )
            )
        }
    }

    /// 미리보기는 프레임을 aspect fill 로 그리기 때문에 화면 밖으로 잘려
    /// 나가는 영역이 생긴다. 그 영역의 잔글씨까지 OCR 이 집계하면 사용자가
    /// 겨냥한 글자가 충분히 큰데도 품질 중앙값이 끌려 내려가므로,
    /// 화면에 실제로 보이는 만큼만 잘라서 인식한다.
    private func makeVisibleVisionImage(
        pixelBuffer: CVPixelBuffer,
        context: LiveOCRFrameContext
    ) -> (image: VisionImage, cropSize: CGSize)? {
        let oriented = CIImage(cvPixelBuffer: pixelBuffer)
            .oriented(
                Self.exifOrientation(
                    context.imageOrientation
                )
            )
        let cropRect = Self.visibleCropRect(
            in: oriented.extent,
            previewSize: context.previewSize
        )
        guard !cropRect.isNull,
              cropRect.width >= 1,
              cropRect.height >= 1,
              let cgImage = liveOCRRenderContext.createCGImage(
                  oriented,
                  from: cropRect
              ) else {
            return nil
        }

        let image = VisionImage(
            image: UIImage(cgImage: cgImage)
        )
        image.orientation = .up
        return (image, cropRect.size)
    }

    private static func visibleCropRect(
        in extent: CGRect,
        previewSize: CGSize
    ) -> CGRect {
        guard extent.width > 0,
              extent.height > 0,
              previewSize.width > 0,
              previewSize.height > 0 else {
            return extent
        }

        let previewAspect =
            previewSize.width / previewSize.height
        let frameAspect = extent.width / extent.height
        var visible = extent.size
        if frameAspect > previewAspect {
            visible.width = extent.height * previewAspect
        } else {
            visible.height = extent.width / previewAspect
        }

        return CGRect(
            x: extent.midX - visible.width / 2,
            y: extent.midY - visible.height / 2,
            width: visible.width,
            height: visible.height
        )
        .integral
        .intersection(extent)
    }

    private static func exifOrientation(
        _ orientation: UIImage.Orientation
    ) -> CGImagePropertyOrientation {
        switch orientation {
        case .up:
            return .up
        case .upMirrored:
            return .upMirrored
        case .down:
            return .down
        case .downMirrored:
            return .downMirrored
        case .left:
            return .left
        case .leftMirrored:
            return .leftMirrored
        case .right:
            return .right
        case .rightMirrored:
            return .rightMirrored
        @unknown default:
            return .up
        }
    }

    private func publishLiveText(
        _ text: String,
        quality: LiveTextOCRQuality,
        requestID: UInt64
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
        let disposition: String
        switch decision.disposition {
        case .noText:
            disposition = "no_text"
        case .lowQuality:
            disposition = "low_quality"
        case .checking:
            disposition = "checking"
        case .suppressed:
            disposition = "suppressed"
        case .announce:
            disposition = "announce"
        }
        traceLiveText(
            "request=\(requestID) decision=\(disposition) reason=\(decision.reason) textLength=\(decision.text.count)"
        )
        traceLiveTextContent(
            "request=\(requestID) decision=\(disposition)",
            decision.text
        )

        guard decision.disposition != .noText else {
            statusLabel.text =
                AppLocalization.string(
                    "글자를 찾는 중입니다."
                )
            return
        }

        switch decision.disposition {
        case .lowQuality:
            statusLabel.text =
                AppLocalization.string(
                    quality.needsCloserGuidance
                    ? "글자가 작아 더 가까이 비춰 주세요"
                    : "글자를 찾는 중입니다."
                )
        case .checking:
            statusLabel.text =
                AppLocalization.format(
                    "확인 중: %@",
                    String(
                        decision.text.prefix(
                            Self.statusPreviewCharacters
                        )
                    )
                )
        case .suppressed:
            statusLabel.text =
                AppLocalization.string(
                    "글자를 찾는 중입니다."
                )
        case .announce:
            guard isLiveReadingEnabled else {
                return
            }
            statusLabel.text =
                AppLocalization.string(
                    "읽는 중입니다."
                )
            tts.speak(
                decision.text,
                language: "ko-KR"
            )
        case .noText:
            return
        }
    }

    private func publishStatus(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = message
        }
    }

    private func traceLiveText(_ message: String) {
        liveTextLogger.debug(
            "\(message, privacy: .public)"
        )
#if DEBUG
        print("[LiveTextReader] \(message)")
#endif
    }

    /// 인식된 문장 자체는 카메라에 비친 사용자 콘텐츠라 통합 로그에는 남기지
    /// 않고, 안드로이드처럼 디버그 빌드의 콘솔 출력으로만 흘린다.
    private func traceLiveTextContent(
        _ label: String,
        _ text: String
    ) {
#if DEBUG
        print(
            "[LiveTextReader] \(label) text=\"\(Self.traceText(text))\""
        )
#endif
    }

    private static func traceText(_ text: String) -> String {
        let compact = text
            .replacingOccurrences(
                of: "\n",
                with: "\\n"
            )
            .replacingOccurrences(
                of: "\r",
                with: "\\r"
            )
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard compact.count
            > logTextMaximumCharacters else {
            return compact
        }
        return String(
            compact.prefix(logTextMaximumCharacters)
        )
            + "...(truncated \(compact.count - logTextMaximumCharacters))"
    }

    private func traceLiveTextError(_ message: String) {
        liveTextLogger.error(
            "\(message, privacy: .public)"
        )
#if DEBUG
        print("[LiveTextReader] ERROR \(message)")
#endif
    }
}
