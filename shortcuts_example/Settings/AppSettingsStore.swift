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

nonisolated enum AppFontChoice:
    String,
    CaseIterable,
    Codable,
    Identifiable,
    Sendable
{
    case system
    case nanumSquareRound

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .system:
            return AppLocalization.string(
                "iPad 시스템 글꼴"
            )
        case .nanumSquareRound:
            return AppLocalization.string(
                "나눔스퀘어라운드"
            )
        }
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
        static let fontChoice =
            "settings.fontChoice.v1"
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

    @Published var fontChoice: AppFontChoice {
        didSet {
            defaults.set(
                fontChoice.rawValue,
                forKey: Key.fontChoice
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
        fontChoice = defaults
            .string(
                forKey: Key.fontChoice
            )
            .flatMap(AppFontChoice.init)
            ?? .nanumSquareRound
    }

    func resetToDefaults() {
        soundEffectsEnabled = true
        voiceFeedbackEnabled = true
        speechRate = .normal
        documentScanColorEnhancementEnabled =
            true
        fontChoice = .nanumSquareRound
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
