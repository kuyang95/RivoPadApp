import AVFoundation
import Combine
import Foundation

nonisolated enum AppSpeechRate:
    String,
    CaseIterable,
    Codable,
    Identifiable,
    Sendable
{
    case slow
    case normal
    case fast
    case veryFast

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .slow:
            return AppLocalization.string(
                "느리게"
            )
        case .normal:
            return AppLocalization.string(
                "보통"
            )
        case .fast:
            return AppLocalization.string(
                "빠르게"
            )
        case .veryFast:
            return AppLocalization.string(
                "매우 빠르게"
            )
        }
    }

    var avSpeechRate: Float {
        switch self {
        case .slow:
            return 0.40
        case .normal:
            return
                AVSpeechUtteranceDefaultSpeechRate
        case .fast:
            return 0.58
        case .veryFast:
            return 0.68
        }
    }
}

nonisolated enum AppLanguage:
    String,
    CaseIterable,
    Codable,
    Identifiable,
    Sendable
{
    static let preferenceKey =
        "settings.appLanguage.v1"

    case system
    case korean = "ko"
    case english = "en"
    case japanese = "ja"

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .system:
            return AppLocalization.string(
                "시스템 설정에 따름"
            )
        case .korean:
            return AppLocalization.string(
                "한국어"
            )
        case .english:
            return AppLocalization.string(
                "영어"
            )
        case .japanese:
            return AppLocalization.string(
                "일본어"
            )
        }
    }

    var localizationCode: String? {
        self == .system ? nil : rawValue
    }

    var effectiveLanguageCode: String {
        localizationCode
            ?? Bundle.main
            .preferredLocalizations
            .first?
            .split(separator: "-")
            .first
            .map(String.init)
            ?? "en"
    }

    var locale: Locale {
        Locale(
            identifier:
                effectiveLanguageCode
        )
    }

    static func current(
        defaults: UserDefaults = .standard
    ) -> Self {
        defaults
            .string(
                forKey:
                    preferenceKey
            )
            .flatMap(Self.init)
            ?? .system
    }
}

nonisolated enum SharedTextEntryMode:
    String,
    CaseIterable,
    Codable,
    Identifiable,
    Sendable
{
    case voice
    case chat

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .voice:
            return AppLocalization.string(
                "음성 질문"
            )
        case .chat:
            return AppLocalization.string(
                "AI 채팅"
            )
        }
    }

    var automaticallyStartsVoiceInput:
        Bool
    {
        self == .voice
    }
}

nonisolated struct SharedTextEntryPlan:
    Equatable,
    Sendable
{
    static let maximumCharacters =
        24_000

    let text: String
    let automaticallyStartsVoiceInput:
        Bool

    static func make(
        rawText: String,
        mode: SharedTextEntryMode
    ) -> Self? {
        let trimmed = rawText
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard !trimmed.isEmpty else {
            return nil
        }
        return Self(
            text: String(
                trimmed.prefix(
                    maximumCharacters
                )
            ),
            automaticallyStartsVoiceInput:
                mode
                .automaticallyStartsVoiceInput
        )
    }
}

@MainActor
final class AppSettingsStore:
    ObservableObject
{
    private enum Key {
        static let soundEffects =
            "settings.soundEffects.v1"
        static let voiceFeedback =
            "settings.voiceFeedback.v1"
        static let speechRate =
            "settings.speechRate.v1"
        static let scanColorEnhancement =
            "settings.scanColorEnhancement.v1"
        static let scanAutomaticCapture =
            "settings.scanAutomaticCapture.v1"
        static let scanCurvedPageCorrection =
            "settings.scanCurvedPageCorrection.v1"
        static let ocrAutoCorrection =
            "settings.ocrAutoCorrection.v1"
        static let appLanguage =
            AppLanguage.preferenceKey
        static let sharedTextEntryMode =
            "settings.sharedTextEntryMode.v1"
    }

    static let shared = AppSettingsStore()

    @Published var soundEffectsEnabled: Bool {
        didSet {
            save(
                soundEffectsEnabled,
                forKey: Key.soundEffects
            )
        }
    }

    @Published var voiceFeedbackEnabled: Bool {
        didSet {
            save(
                voiceFeedbackEnabled,
                forKey: Key.voiceFeedback
            )
        }
    }

    @Published var speechRate: AppSpeechRate {
        didSet {
            defaults.set(
                speechRate.rawValue,
                forKey: Key.speechRate
            )
        }
    }

    @Published var
        documentScanColorEnhancementEnabled:
        Bool
    {
        didSet {
            save(
                documentScanColorEnhancementEnabled,
                forKey:
                    Key.scanColorEnhancement
            )
        }
    }

    @Published var
        documentScanAutomaticCaptureEnabled:
        Bool
    {
        didSet {
            save(
                documentScanAutomaticCaptureEnabled,
                forKey:
                    Key.scanAutomaticCapture
            )
        }
    }

    @Published var
        documentScanCurvedPageCorrectionEnabled:
        Bool
    {
        didSet {
            save(
                documentScanCurvedPageCorrectionEnabled,
                forKey:
                    Key.scanCurvedPageCorrection
            )
        }
    }

    @Published var ocrAutoCorrectionEnabled:
        Bool
    {
        didSet {
            save(
                ocrAutoCorrectionEnabled,
                forKey:
                    Key.ocrAutoCorrection
            )
        }
    }

    @Published var appLanguage: AppLanguage {
        didSet {
            defaults.set(
                appLanguage.rawValue,
                forKey: Key.appLanguage
            )
        }
    }

    @Published var sharedTextEntryMode:
        SharedTextEntryMode
    {
        didSet {
            defaults.set(
                sharedTextEntryMode.rawValue,
                forKey:
                    Key.sharedTextEntryMode
            )
        }
    }

    private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        soundEffectsEnabled =
            Self.bool(
                forKey: Key.soundEffects,
                defaults: defaults,
                fallback: true
            )
        voiceFeedbackEnabled =
            Self.bool(
                forKey: Key.voiceFeedback,
                defaults: defaults,
                fallback: true
            )
        speechRate = defaults
            .string(
                forKey: Key.speechRate
            )
            .flatMap(AppSpeechRate.init)
            ?? .normal
        documentScanColorEnhancementEnabled =
            Self.bool(
                forKey:
                    Key.scanColorEnhancement,
                defaults: defaults,
                fallback: true
            )
        documentScanAutomaticCaptureEnabled =
            Self.bool(
                forKey:
                    Key.scanAutomaticCapture,
                defaults: defaults,
                fallback: true
            )
        documentScanCurvedPageCorrectionEnabled =
            Self.bool(
                forKey:
                    Key.scanCurvedPageCorrection,
                defaults: defaults,
                fallback: true
            )
        ocrAutoCorrectionEnabled =
            Self.bool(
                forKey:
                    Key.ocrAutoCorrection,
                defaults: defaults,
                fallback: true
            )
        appLanguage = defaults
            .string(
                forKey: Key.appLanguage
            )
            .flatMap(AppLanguage.init)
            ?? .system
        sharedTextEntryMode = defaults
            .string(
                forKey:
                    Key.sharedTextEntryMode
            )
            .flatMap(
                SharedTextEntryMode.init
            )
            ?? .voice
    }

    func resetToDefaults() {
        soundEffectsEnabled = true
        voiceFeedbackEnabled = true
        speechRate = .normal
        documentScanColorEnhancementEnabled =
            true
        documentScanAutomaticCaptureEnabled =
            true
        documentScanCurvedPageCorrectionEnabled =
            true
        ocrAutoCorrectionEnabled = true
        appLanguage = .system
        sharedTextEntryMode = .voice
    }

    private func save(
        _ value: Bool,
        forKey key: String
    ) {
        defaults.set(value, forKey: key)
    }

    private static func bool(
        forKey key: String,
        defaults: UserDefaults,
        fallback: Bool
    ) -> Bool {
        guard defaults.object(
            forKey: key
        ) != nil else {
            return fallback
        }
        return defaults.bool(forKey: key)
    }
}
