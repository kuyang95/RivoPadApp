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
    MTKViewDelegate
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
    /// 문서 스캔·실시간 문자 읽기: 자체 카메라 세션을 쓰므로 이 화면을 대신한다(Android `closeCameraActivity`).
    var onOpenDocumentScan: (() -> Void)?
    var onOpenLiveTextReader: (() -> Void)?
    /// 사진 분석: 카메라 위에 얹어 연다. 기본 모드 촬영 결과도 `PhotoReviewHandoff` 로 넘겨 같은 화면을 연다.
    var onOpenPhotoReview: (() -> Void)?
    /// AI 질문하기 촬영: 찍은 사진을 첨부해 음성 질문 화면으로 넘긴다.
    var onAskAI: ((UIImage) -> Void)?
    /// 기본·이미지 분석·AI 질문하기 사이를 제자리에서 바꿀 때 툴바의 모드 알약에 알린다.
    var onModeChanged: ((MagnifierCameraMode) -> Void)?
    /// 실시간 읽기는 촬영 컨트롤이 없으므로 촬영 모드는 별도 화면으로 연다.
    var onOpenCaptureMode: ((MagnifierCameraMode) -> Void)?
    var onCameraStateChanged: ((_ isTorchOn: Bool, _ isFrontCamera: Bool) -> Void)?

    private(set) var mode: MagnifierCameraMode
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
    private var torchObservation: NSKeyValueObservation?
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

    private let zoomLabel = UILabel()
    private let zoomSlider = UISlider()
    private let filterControl = UISegmentedControl(
        items: MagnifierFilter.allCases.map(\.title)
    )
    private let gridTile = VisionCraftCameraControlTile()
    private let torchTile = VisionCraftCameraControlTile()
    private let switchTile = VisionCraftCameraControlTile()
    private let settingsTile = VisionCraftCameraControlTile()
    private let captureButton = VisionCraftCameraShutterButton()
    private let expandableStack = UIStackView()
    private let controlsColumn = UIStackView()
    private let cameraStatusBand = VisionCraftPaddedLabel()
    private let statusLabel = UILabel()
    private let liveTextPanel = UIView()
    private let liveTitleLabel = UILabel()
    private let gridOverlay = UIView()
    private let verticalGridLine = UIView()
    private let horizontalGridLine = UIView()
    private var tileWidthConstraints: [NSLayoutConstraint] = []
    private var tileHeightConstraints: [NSLayoutConstraint] = []
    private var shutterSizeConstraints: [NSLayoutConstraint] = []
    private var controlsColumnWidthConstraint: NSLayoutConstraint?
    private var columnTrailingConstraint: NSLayoutConstraint?
    private var controlMetrics: VisionCraftCameraControlMetrics?
    private var isControlsExpanded = false
    private var isAnalyzingImage = false
    private var isSavingPhoto = false
    private var didAnnounceEntryHint = false
    private var zoomOverlayHideWorkItem:
        DispatchWorkItem?
    private var bandHideWorkItem: DispatchWorkItem?
    private let tts = TTSManager.shared
    private let photoSaveService =
        MagnifierPhotoSaveService()

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
        updateTorchUI()
        requestCameraAndStart()
        announceEntryHintIfNeeded()
    }

    /// Android `onCreate` 끝: 이미지 분석·AI 질문 모드로 들어오면 700ms 뒤 촬영 버튼의 쓰임을 음성으로 알린다.
    private func announceEntryHintIfNeeded() {
        guard !didAnnounceEntryHint,
              mode == .imageDescription || mode == .askAI else { return }
        didAnnounceEntryHint = true
        let hint = Self.modeHint(for: mode)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, self.isCameraScreenVisible else { return }
            self.tts.speakFeedback(hint)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateVideoRotation()
        updateLivePreviewSize()
        applyControlMetrics()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isCameraScreenVisible = false
        zoomOverlayHideWorkItem?.cancel()
        bandHideWorkItem?.cancel()
        setTorch(false)
        tts.stop()
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
    }

    /// Android `a_live_text_reader.xml`: 아래 반투명 패널(#80000000)에 제목 "바로 읽기"(22 Bold 흰색)와 상태(16).
    /// 닫기는 라우트의 뒤로가기 버튼이 담당한다. 모드 알약은 SwiftUI 툴바(왼쪽 위)에 있다.
    private func setupLiveTextReaderUI() {
        liveTextPanel.translatesAutoresizingMaskIntoConstraints = false
        liveTextPanel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        view.addSubview(liveTextPanel)

        liveTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        liveTitleLabel.text = AppLocalization.string("바로 읽기")
        liveTitleLabel.textColor = UIColor(VisionCraftCameraUI.text)
        liveTitleLabel.font = UIFontMetrics(forTextStyle: .title2)
            .scaledFont(for: .systemFont(ofSize: 22, weight: .bold))
        liveTitleLabel.adjustsFontForContentSizeCategory = true
        liveTitleLabel.numberOfLines = 1
        liveTitleLabel.accessibilityTraits = .header
        liveTextPanel.addSubview(liveTitleLabel)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = UIColor(VisionCraftCameraUI.secondaryText)
        statusLabel.font = UIFontMetrics(forTextStyle: .callout)
            .scaledFont(for: .systemFont(ofSize: 16, weight: .regular))
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textAlignment = .natural
        statusLabel.numberOfLines = 3
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.isAccessibilityElement = true
        statusLabel.accessibilityTraits = .updatesFrequently
        liveTextPanel.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            liveTextPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            liveTextPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            liveTextPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            liveTitleLabel.topAnchor.constraint(equalTo: liveTextPanel.topAnchor, constant: 16),
            liveTitleLabel.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 24
            ),
            liveTitleLabel.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -24
            ),
            statusLabel.topAnchor.constraint(equalTo: liveTitleLabel.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: liveTitleLabel.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: liveTitleLabel.trailingAnchor),
            statusLabel.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -16
            ),
        ])
        view.accessibilityElements = [liveTitleLabel, statusLabel, cameraView]
    }

    /// Android `CameraControls.kt`: 오른쪽 아래 세로 열에 [격자·라이트·전환(접힘)] → 설정 → 촬영.
    /// 미리보기를 가리지 않도록 띠 배경은 두지 않는다. 읽기 순서는 모드 → 촬영 → 설정 → 전환 → 라이트 → 격자.
    private func setupAndroidCameraUI() {
        view.addSubview(gridOverlay)
        configureGridOverlay()

        gridTile.title = AppLocalization.string("격자")
        gridTile.systemImage = "grid"
        gridTile.isOn = false
        gridTile.addTarget(self, action: #selector(gridTapped), for: .touchUpInside)

        torchTile.title = AppLocalization.string("라이트")
        torchTile.systemImage = "flashlight.off.fill"
        torchTile.isOn = false
        torchTile.addTarget(self, action: #selector(torchTapped), for: .touchUpInside)

        switchTile.title = AppLocalization.string("전환")
        switchTile.systemImage = "camera.rotate"
        switchTile.addTarget(self, action: #selector(switchCameraTapped), for: .touchUpInside)

        settingsTile.title = AppLocalization.string("설정")
        settingsTile.systemImage = "chevron.up"
        settingsTile.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)

        captureButton.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        applyModeToShutter()

        expandableStack.axis = .vertical
        expandableStack.alignment = .trailing
        expandableStack.translatesAutoresizingMaskIntoConstraints = false
        [gridTile, torchTile, switchTile].forEach(expandableStack.addArrangedSubview)

        controlsColumn.axis = .vertical
        controlsColumn.alignment = .trailing
        controlsColumn.translatesAutoresizingMaskIntoConstraints = false
        [settingsTile, captureButton].forEach(controlsColumn.addArrangedSubview)
        view.addSubview(controlsColumn)

        // 격자·라이트·전환 피드백과 배율을 보여 주는 화면 가운데 큰 글씨(Android overlayTextView).
        zoomLabel.translatesAutoresizingMaskIntoConstraints = false
        zoomLabel.text = "1.0"
        zoomLabel.textColor = .white
        zoomLabel.textAlignment = .center
        zoomLabel.numberOfLines = 0
        zoomLabel.layer.shadowColor = UIColor.black.cgColor
        zoomLabel.layer.shadowOpacity = 0.7
        zoomLabel.layer.shadowRadius = 10
        zoomLabel.isHidden = true
        zoomLabel.isAccessibilityElement = false
        view.addSubview(zoomLabel)

        // Android 토스트 자리: 이미지 분석 결과·저장 실패 안내 띠(VcCamStatusOverlay).
        cameraStatusBand.translatesAutoresizingMaskIntoConstraints = false
        cameraStatusBand.backgroundColor = UIColor(VisionCraftUI.overlay)
        cameraStatusBand.textColor = UIColor(VisionCraftUI.background)
        cameraStatusBand.font = UIFontMetrics(forTextStyle: .headline)
            .scaledFont(for: .systemFont(ofSize: 17, weight: .bold))
        cameraStatusBand.adjustsFontForContentSizeCategory = true
        cameraStatusBand.textAlignment = .center
        cameraStatusBand.numberOfLines = 0
        cameraStatusBand.layer.cornerRadius = 14
        cameraStatusBand.layer.cornerCurve = .continuous
        cameraStatusBand.layer.masksToBounds = true
        cameraStatusBand.isHidden = true
        cameraStatusBand.accessibilityTraits = .updatesFrequently
        view.addSubview(cameraStatusBand)

        tileWidthConstraints = [gridTile, torchTile, switchTile, settingsTile].map {
            $0.widthAnchor.constraint(equalToConstant: 76)
        }
        // Android heightIn(min=...)처럼 글자 크기에 따라 타일이 커져야 한다.
        // 고정 높이는 아이콘·제목·상태의 합이 80pt를 넘을 때 글자를 자른다.
        tileHeightConstraints = [gridTile, torchTile, switchTile, settingsTile].map {
            $0.heightAnchor.constraint(greaterThanOrEqualToConstant: 68)
        }
        shutterSizeConstraints = [
            captureButton.widthAnchor.constraint(equalToConstant: 100),
            captureButton.heightAnchor.constraint(equalToConstant: 100),
        ]
        columnTrailingConstraint = controlsColumn.trailingAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.trailingAnchor,
            constant: -10
        )
        controlsColumnWidthConstraint = controlsColumn.widthAnchor.constraint(equalToConstant: 100)

        NSLayoutConstraint.activate(
            tileWidthConstraints + tileHeightConstraints + shutterSizeConstraints + [
                columnTrailingConstraint!,
                controlsColumnWidthConstraint!,
                controlsColumn.bottomAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                    constant: -16
                ),
                controlsColumn.topAnchor.constraint(
                    greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor,
                    constant: 16
                ),
                zoomLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                zoomLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                zoomLabel.leadingAnchor.constraint(
                    greaterThanOrEqualTo: view.leadingAnchor,
                    constant: 8
                ),
                cameraStatusBand.leadingAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                    constant: 16
                ),
                cameraStatusBand.trailingAnchor.constraint(
                    equalTo: controlsColumn.leadingAnchor,
                    constant: -12
                ),
                cameraStatusBand.bottomAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                    constant: -24
                ),
                cameraStatusBand.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            ]
        )
        applyControlMetrics(force: true)
        updateControlTiles()
        updateGridColor()

        // VoiceOver 읽기 순서(Android traversalIndex): 촬영 → 설정 → 전환 → 라이트 → 격자.
        // 모드 알약은 툴바에 있어 그보다 먼저 읽힌다.
        view.accessibilityElements = [
            captureButton,
            settingsTile,
            switchTile,
            torchTile,
            gridTile,
            cameraStatusBand,
            cameraView,
        ]
    }

    /// Android `BoxWithConstraints`: 폭 600 이상이면 iPad 치수, 높이 560 미만이면 낮은 타일·작은 촬영 버튼.
    private func applyControlMetrics(force: Bool = false) {
        guard mode != .liveTextReader else { return }
        let metrics = VisionCraftCameraControlMetrics(bounds: view.bounds.size)
        guard force || metrics != controlMetrics else { return }
        controlMetrics = metrics
        tileWidthConstraints.forEach { $0.constant = metrics.tileWidth }
        tileHeightConstraints.forEach { $0.constant = metrics.tileMinHeight }
        [gridTile, torchTile, switchTile, settingsTile].forEach {
            $0.layoutWidth = metrics.tileWidth
            $0.minimumHeight = metrics.tileMinHeight
        }
        shutterSizeConstraints.forEach { $0.constant = metrics.shutterSize }
        controlsColumnWidthConstraint?.constant = metrics.shutterSize
        columnTrailingConstraint?.constant = -metrics.horizontalInset
        expandableStack.spacing = metrics.gap
        controlsColumn.spacing = metrics.gap
        [gridTile, torchTile, switchTile].forEach { $0.showsIcon = metrics.showsTileIcons }
        settingsTile.showsIcon = true
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
                if mode == .liveTextReader {
                    // Android LiveTextReaderActivity: 안내 문구를 보인 뒤 화면을 닫는다.
                    let message = AppLocalization.string("카메라 권한이 필요합니다.")
                    statusLabel.text = message
                    tts.speakFeedback(message)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        guard self.isCameraScreenVisible else { return }
                        self.onClose?()
                    }
                } else {
                    let message = AppLocalization.string("설정에서 카메라 권한을 허용해 주세요.")
                    statusLabel.text = message
                    showCameraBand(message, duration: 6)
                }
                return
            }
            sessionQueue.async {
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
                    mode == .liveTextReader
                    ? "카메라를 열 수 없습니다."
                    : "카메라를 사용할 수 없습니다."
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
            self.torchObservation = device.observe(\.isTorchActive, options: [.new]) { [weak self] device, _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.cameraInput?.device === device else { return }
                    self.updateTorchUI()
                }
            }
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
            captureTapped()
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
        isTorchEnabled = cameraInput?.device.isTorchActive == true
        let isAvailable = cameraInput?.device.hasTorch == true
            && currentPosition == .back
        torchTile.isEnabled = isAvailable
        updateControlTiles()
        if isCameraScreenVisible {
            onCameraStateChanged?(isTorchEnabled, currentPosition == .front)
        }
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
        updateGridColor()
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
        updateGridColor()
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
        updateGridColor()
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
        announceControlState(
            label: AppLocalization.string("라이트"),
            isOn: isTorchEnabled
        )
    }

    @objc private func gridTapped() {
        gridOverlay.isHidden.toggle()
        updateControlTiles()
        announceControlState(
            label: AppLocalization.string("격자"),
            isOn: !gridOverlay.isHidden
        )
    }

    /// Android `announceControlState`: 켜고 끈 결과를 화면 중앙 큰 글씨(700ms)와 음성으로 알린다.
    private func announceControlState(label: String, isOn: Bool) {
        let state = AppLocalization.string(isOn ? "켬" : "끔")
        showOverlay("\(label)\n\(state)", duration: 0.7)
        tts.speakFeedback("\(label) \(state)")
    }

    @objc private func switchCameraTapped() {
        setTorch(false)
        let nextPosition: AVCaptureDevice.Position =
            currentPosition == .back ? .front : .back
        sessionQueue.async { [weak self] in
            self?.configureSession(position: nextPosition)
        }
        showOverlay(
            AppLocalization.string(nextPosition == .back ? "후면" : "전면"),
            duration: 0.5
        )
    }

    @objc private func settingsTapped() {
        isControlsExpanded.toggle()
        updateControlTiles()
        UIAccessibility.post(
            notification: .layoutChanged,
            argument: settingsTile
        )
    }

    /// 격자·라이트·전환 타일과 접기 타일의 글자·상태·강조를 지금 상태로 맞춘다.
    private func updateControlTiles() {
        let onText = AppLocalization.string("켬")
        let offText = AppLocalization.string("끔")
        let isGridOn = !gridOverlay.isHidden
        gridTile.isOn = isGridOn
        gridTile.stateText = isGridOn ? onText : offText
        torchTile.isOn = isTorchEnabled
        torchTile.stateText = isTorchEnabled ? onText : offText
        torchTile.systemImage = isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill"
        let facingText = AppLocalization.string(currentPosition == .front ? "전면" : "후면")
        switchTile.stateText = facingText

        if isControlsExpanded, expandableStack.superview == nil {
            controlsColumn.insertArrangedSubview(expandableStack, at: 0)
        } else if !isControlsExpanded, expandableStack.superview != nil {
            controlsColumn.removeArrangedSubview(expandableStack)
            expandableStack.removeFromSuperview()
        }
        settingsTile.systemImage = isControlsExpanded ? "chevron.down" : "chevron.up"
        settingsTile.title = AppLocalization.string(isControlsExpanded ? "설정 접기" : "설정")
        settingsTile.isOutlineHighlighted = !isControlsExpanded && (isGridOn || isTorchEnabled)
        // "설정. 격자 끔, 라이트 끔, 전환 후면, 접힘"
        var label = AppLocalization.string("설정") + ". "
        label += AppLocalization.string("격자") + " " + (isGridOn ? onText : offText) + ", "
        label += AppLocalization.string("라이트") + " " + (isTorchEnabled ? onText : offText) + ", "
        label += AppLocalization.string("전환") + " " + facingText
        settingsTile.accessibilityOverrideLabel = label
        settingsTile.accessibilityStateText =
            AppLocalization.string(isControlsExpanded ? "펼쳐짐" : "접힘")
    }

    /// 격자선은 선택한 색 조합의 전경색을 따른다(Android `changeGridColor`). 원래 색상이면 검정.
    private func updateGridColor() {
        let color: UIColor
        if let index = displayAdjustment.colorIndex,
           !LocalDocumentColorTheme.all.isEmpty {
            let themes = LocalDocumentColorTheme.all
            let theme = themes[min(max(index, 0), themes.count - 1)]
            color = UIColor(hex: UInt32(theme.foregroundHex & 0xFFFFFF))
        } else {
            color = .black
        }
        verticalGridLine.backgroundColor = color
        horizontalGridLine.backgroundColor = color
    }

    // MARK: - 모드: 기본 / 문서 스캔 / 실시간 문자 읽기 / 이미지 분석 / AI 질문하기 / 사진 분석

    /// 왼쪽 위 모드 알약(SwiftUI 툴바)이 부른다.
    func presentModeDialog() {
        moreTapped()
    }

    @objc private func moreTapped() {
        guard !isOpeningCameraTool,
              presentedViewController == nil else { return }

        let dialog = CameraMoreOptionsDialog(
            currentMode: mode,
            onBasic: { [weak self] in
                self?.dismissMoreOptions { [weak self] in
                    self?.switchMode(to: .magnifier)
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
                    self?.switchMode(to: .imageDescription)
                }
            },
            onAskAI: { [weak self] in
                self?.dismissMoreOptions { [weak self] in
                    self?.switchMode(to: .askAI)
                }
            },
            onPhotoReview: { [weak self] in
                self?.dismissMoreOptions { [weak self] in
                    // 사진 분석은 카메라가 필요 없으니 이 화면 위에 연다. 뒤로 가면 카메라로 돌아온다.
                    guard let self, self.isCameraScreenVisible else { return }
                    self.onOpenPhotoReview?()
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

    /// 문서 스캔·실시간 문자 읽기는 자체 카메라 세션을 쓰므로 이 세션을 내리고 화면을 바꾼다.
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

    /// Android `selectCameraMode`: 모드를 고르는 순간에는 촬영하지 않는다. 세션·줌·토치·격자·색상은 그대로 두고
    /// 촬영 버튼의 동작만 바꾼 뒤, 바뀐 모드를 화면 중앙 큰 글씨와 음성으로 알린다. 이미 그 모드면 아무것도 하지 않는다.
    private func switchMode(to newMode: MagnifierCameraMode) {
        guard newMode != mode, newMode != .liveTextReader else { return }
        if mode == .liveTextReader {
            guard let onOpenCaptureMode else { return }
            openCameraTool { onOpenCaptureMode(newMode) }
            return
        }
        mode = newMode
        applyModeToShutter()
        onModeChanged?(newMode)
        showOverlay(
            Self.modeName(for: newMode).replacingOccurrences(of: " ", with: "\n"),
            duration: 0.9
        )
        tts.speakFeedback(Self.modeHint(for: newMode))
    }

    static func modeName(for mode: MagnifierCameraMode) -> String {
        switch mode {
        case .magnifier: return AppLocalization.string("기본")
        case .imageDescription: return AppLocalization.string("이미지 분석")
        case .askAI: return AppLocalization.string("AI 질문하기")
        case .liveTextReader: return AppLocalization.string("실시간 문자 읽기")
        }
    }

    /// Android `camera_mode_basic_hint` / `image_analysis_camera_hint` / `camera_ask_ai_mode_hint`.
    private static func modeHint(for mode: MagnifierCameraMode) -> String {
        switch mode {
        case .imageDescription:
            return AppLocalization.string("촬영 버튼을 누르면 이미지를 설명합니다.")
        case .askAI:
            return AppLocalization.string("촬영 버튼을 누르면 찍은 사진으로 AI에게 질문합니다.")
        case .magnifier, .liveTextReader:
            return AppLocalization.string("기본 모드입니다. 촬영 버튼을 누르면 사진을 저장합니다.")
        }
    }

    /// 촬영 버튼의 글자·색·접근성 이름을 지금 모드에 맞춘다(Android `VcCamShutter`).
    private func applyModeToShutter() {
        switch mode {
        case .imageDescription:
            captureButton.title = AppLocalization.string("분석\n촬영")
            captureButton.isSpecial = true
            captureButton.accessibilityLabel = AppLocalization.string("이미지 분석 촬영")
        case .askAI:
            captureButton.title = AppLocalization.string("질문\n촬영")
            captureButton.isSpecial = true
            captureButton.accessibilityLabel = AppLocalization.string("AI 질문 촬영")
        case .magnifier, .liveTextReader:
            captureButton.title = AppLocalization.string("촬영")
            captureButton.isSpecial = false
            captureButton.accessibilityLabel = AppLocalization.string("촬영")
        }
    }

    // MARK: - 촬영

    @objc private func captureTapped() {
        switch mode {
        case .liveTextReader:
            return
        case .magnifier:
            saveCurrentFrameToPhotos()
        case .imageDescription:
            captureAndAnalyzeImage()
        case .askAI:
            captureForAskAI()
        }
    }

    private func frameForAnalysis() -> UIImage? {
        guard let image = capturedImage(applyingDisplayAdjustments: false) else {
            SoundEffectManager.shared.play(.fail)
            let message = AppLocalization.string("카메라 프레임을 기다리는 중입니다.")
            announceRemoteStatus(message)
            showCameraBand(message, duration: 3)
            return nil
        }
        return image
    }

    /// Android `captureAndAnalyzeImage`: 카메라에 머문 채 한 장 찍어 이미지 설명을 받는다.
    /// 결과는 클립보드에 복사하고, 음성으로 읽고, 화면 아래 띠로 보여준다. 사진은 저장하지 않는다.
    private func captureAndAnalyzeImage() {
        guard !isOpeningCameraTool else { return }
        if isAnalyzingImage {
            tts.speakFeedback(AppLocalization.string("이미 이미지를 분석하고 있습니다."))
            return
        }
        guard let image = frameForAnalysis() else { return }
        isAnalyzingImage = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        SoundEffectManager.shared.play(.cameraShot2)
        SoundEffectManager.shared.play(.waiting)
        let started = AppLocalization.string("촬영한 이미지를 분석하고 있습니다.")
        tts.speakFeedback(started)
        showCameraBand(started, duration: 60)

        Task { [weak self] in
            guard let self else { return }
            defer { self.isAnalyzingImage = false }
            do {
                let caption = try await CameraImageDescriber.describe(image)
                guard self.isCameraScreenVisible else { return }
                guard !caption.isEmpty else {
                    self.handleAnalysisError(AppLocalization.string("사진을 해석하지 못했어요."))
                    return
                }
                UIPasteboard.general.string = caption
                SoundEffectManager.shared.play(.complete)
                self.tts.speakFeedback(caption)
                self.showCameraBand(caption, duration: 12)
            } catch {
                guard self.isCameraScreenVisible else { return }
                self.handleAnalysisError(CameraImageDescriber.userMessage(for: error))
            }
        }
    }

    private func handleAnalysisError(_ message: String) {
        SoundEffectManager.shared.play(.fail)
        tts.speakFeedback(message)
        showCameraBand(message, duration: 4)
    }

    /// Android `captureAndAskAi`: 한 장 찍어 음성 질문 화면으로 넘긴다. 사진은 갤러리에 저장하지 않는다.
    private func captureForAskAI() {
        guard !isOpeningCameraTool, let onAskAI else { return }
        if isAnalyzingImage {
            tts.speakFeedback(AppLocalization.string("이미 이미지를 분석하고 있습니다."))
            return
        }
        guard let image = frameForAnalysis() else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        SoundEffectManager.shared.play(.cameraShot2)
        openCameraTool { onAskAI(image) }
    }

    private func saveCurrentFrameToPhotos() {
        guard let image = capturedImage() else {
            let message = AppLocalization.string("카메라 프레임을 기다리는 중입니다.")
            announceRemoteStatus(message)
            showCameraBand(message, duration: 3)
            return
        }
        saveImageToPhotos(image)
    }

    /// Android `capturePhoto` → `saveCapturedPhoto`: 저장한 뒤 "촬영한 사진" 검토 화면을 위에 연다.
    /// 뒤로 가면 카메라로 돌아온다. 실패하면 토스트("사진 저장 실패: %@")만 띄운다.
    private func saveImageToPhotos(_ image: UIImage) {
        guard !isSavingPhoto else { return }
        isSavingPhoto = true
        SoundEffectManager.shared.play(.cameraShot2)
        Task { [weak self] in
            guard let self else { return }
            defer { self.isSavingPhoto = false }
            do {
                let capture = try MagnifierPhotoCapture(image: image)
                try await self.photoSaveService.saveToPhotoLibrary(capture)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                guard self.isCameraScreenVisible, !self.isOpeningCameraTool else { return }
                PhotoReviewHandoff.pendingCapturedImage = image
                self.onOpenPhotoReview?()
            } catch {
                SoundEffectManager.shared.play(.fail)
                let message = AppLocalization.format(
                    "사진 저장 실패: %@",
                    error.localizedDescription
                )
                self.tts.speakFeedback(message)
                self.showCameraBand(message, duration: 4)
            }
        }
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
        updateGridColor()
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
        showOverlay(
            String(
                format: "%.1f",
                cameraInput?.device.videoZoomFactor
                    ?? CGFloat(zoomSlider.value)
            ),
            duration: 0.6
        )
    }

    /// Android `showOverlay`: 화면 가운데 큰 글씨. 기본 크기는 "후면"·"2.0" 같은 두세 글자 기준이고,
    /// 더 긴 줄은 화면 폭의 90%에 들어가게만 줄인다.
    private func showOverlay(_ text: String, duration: TimeInterval) {
        zoomOverlayHideWorkItem?.cancel()
        let baseSize = overlayBaseFontSize
        let baseFont = UIFont.monospacedDigitSystemFont(ofSize: baseSize, weight: .regular)
        let widest = text.split(separator: "\n").map {
            (String($0) as NSString).size(withAttributes: [.font: baseFont]).width
        }.max() ?? 0
        let available = view.bounds.width * 0.9
        let scale = (widest > 0 && available > 0) ? min(1, available / widest) : 1
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: baseSize * scale, weight: .regular)
        zoomLabel.text = text
        zoomLabel.isHidden = false

        let workItem = DispatchWorkItem { [weak self] in
            self?.zoomLabel.isHidden = true
        }
        zoomOverlayHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + duration,
            execute: workItem
        )
    }

    private var overlayBaseFontSize: CGFloat {
        min(view.bounds.width, view.bounds.height) * 0.4
    }

    /// Android 카메라 화면의 토스트 자리: VcCamStatusOverlay 띠를 아래쪽에 띄운다.
    private func showCameraBand(_ text: String, duration: TimeInterval) {
        bandHideWorkItem?.cancel()
        cameraStatusBand.text = text
        cameraStatusBand.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: text)
        let workItem = DispatchWorkItem { [weak self] in
            self?.cameraStatusBand.isHidden = true
        }
        bandHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + duration,
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
            tts.speak(decision.text)
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
