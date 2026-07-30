import AVFoundation
import Foundation
import XCTest

@testable import shortcuts_example

@MainActor
final class AppSettingsStoreTests:
    XCTestCase
{
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName =
            "AppSettingsStoreTests."
            + UUID().uuidString
        defaults = UserDefaults(
            suiteName: suiteName
        )
    }

    override func tearDown() {
        defaults.removePersistentDomain(
            forName: suiteName
        )
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsMatchVisionCraftPort()
    {
        let store = AppSettingsStore(
            defaults: defaults
        )

        XCTAssertTrue(
            store.soundEffectsEnabled
        )
        XCTAssertTrue(
            store.voiceFeedbackEnabled
        )
        XCTAssertEqual(
            store.speechRate,
            .normal
        )
        XCTAssertTrue(
            store
                .documentScanColorEnhancementEnabled
        )
        XCTAssertTrue(
            store
                .documentScanAutomaticCaptureEnabled
        )
        XCTAssertTrue(
            store
                .documentScanCurvedPageCorrectionEnabled
        )
        XCTAssertTrue(
            store.ocrAutoCorrectionEnabled
        )
        XCTAssertEqual(
            store.appLanguage,
            .system
        )
        XCTAssertEqual(
            store.sharedTextEntryMode,
            .voice
        )
    }

    func testChangesPersistAcrossStoreInstances()
    {
        let store = AppSettingsStore(
            defaults: defaults
        )
        store.soundEffectsEnabled = false
        store.voiceFeedbackEnabled = false
        store.speechRate = .veryFast
        store
            .documentScanColorEnhancementEnabled =
            false
        store
            .documentScanAutomaticCaptureEnabled =
            false
        store
            .documentScanCurvedPageCorrectionEnabled =
            false
        store.ocrAutoCorrectionEnabled =
            false
        store.appLanguage = .japanese
        store.sharedTextEntryMode = .chat

        let restored = AppSettingsStore(
            defaults: defaults
        )
        XCTAssertFalse(
            restored.soundEffectsEnabled
        )
        XCTAssertFalse(
            restored.voiceFeedbackEnabled
        )
        XCTAssertEqual(
            restored.speechRate,
            .veryFast
        )
        XCTAssertFalse(
            restored
                .documentScanColorEnhancementEnabled
        )
        XCTAssertFalse(
            restored
                .documentScanAutomaticCaptureEnabled
        )
        XCTAssertFalse(
            restored
                .documentScanCurvedPageCorrectionEnabled
        )
        XCTAssertFalse(
            restored
                .ocrAutoCorrectionEnabled
        )
        XCTAssertEqual(
            restored.appLanguage,
            .japanese
        )
        XCTAssertEqual(
            restored.sharedTextEntryMode,
            .chat
        )
    }

    func testInvalidEnumValuesUseDefaults()
    {
        defaults.set(
            "impossible",
            forKey: "settings.speechRate.v1"
        )
        defaults.set(
            "impossible",
            forKey:
                "settings.sharedTextEntryMode.v1"
        )
        defaults.set(
            "impossible",
            forKey:
                "settings.appLanguage.v1"
        )

        let store = AppSettingsStore(
            defaults: defaults
        )
        XCTAssertEqual(
            store.speechRate,
            .normal
        )
        XCTAssertEqual(
            store.sharedTextEntryMode,
            .voice
        )
        XCTAssertEqual(
            store.appLanguage,
            .system
        )
    }

    func testResetAndSpeechRateOrdering()
    {
        let store = AppSettingsStore(
            defaults: defaults
        )
        store.soundEffectsEnabled = false
        store.voiceFeedbackEnabled = false
        store.speechRate = .veryFast
        store
            .documentScanColorEnhancementEnabled =
            false
        store
            .documentScanAutomaticCaptureEnabled =
            false
        store
            .documentScanCurvedPageCorrectionEnabled =
            false
        store.ocrAutoCorrectionEnabled =
            false
        store.appLanguage = .english
        store.sharedTextEntryMode = .chat

        store.resetToDefaults()

        XCTAssertTrue(
            store.soundEffectsEnabled
        )
        XCTAssertTrue(
            store.voiceFeedbackEnabled
        )
        XCTAssertEqual(
            store.speechRate,
            .normal
        )
        XCTAssertTrue(
            store
                .documentScanColorEnhancementEnabled
        )
        XCTAssertTrue(
            store
                .documentScanAutomaticCaptureEnabled
        )
        XCTAssertTrue(
            store
                .documentScanCurvedPageCorrectionEnabled
        )
        XCTAssertTrue(
            store.ocrAutoCorrectionEnabled
        )
        XCTAssertEqual(
            store.appLanguage,
            .system
        )
        XCTAssertEqual(
            store.sharedTextEntryMode,
            .voice
        )
        XCTAssertEqual(
            AppSpeechRate.normal.avSpeechRate,
            AVSpeechUtteranceDefaultSpeechRate
        )
        XCTAssertLessThan(
            AppSpeechRate.slow.avSpeechRate,
            AppSpeechRate.normal.avSpeechRate
        )
        XCTAssertLessThan(
            AppSpeechRate.normal.avSpeechRate,
            AppSpeechRate.fast.avSpeechRate
        )
        XCTAssertLessThan(
            AppSpeechRate.fast.avSpeechRate,
            AppSpeechRate.veryFast.avSpeechRate
        )
        XCTAssertTrue(
            SharedTextEntryMode
                .voice
                .automaticallyStartsVoiceInput
        )
        XCTAssertFalse(
            SharedTextEntryMode
                .chat
                .automaticallyStartsVoiceInput
        )
    }

    func testSharedTextEntryPlanTrimsBoundsAndChoosesMode()
    {
        XCTAssertNil(
            SharedTextEntryPlan.make(
                rawText: " \n ",
                mode: .voice
            )
        )

        let voice =
            SharedTextEntryPlan.make(
                rawText:
                    "  "
                    + String(
                        repeating: "가",
                        count:
                            SharedTextEntryPlan
                            .maximumCharacters
                            + 10
                    )
                    + "  ",
                mode: .voice
            )
        XCTAssertEqual(
            voice?.text.count,
            SharedTextEntryPlan
                .maximumCharacters
        )
        XCTAssertEqual(
            voice?
                .automaticallyStartsVoiceInput,
            true
        )

        let chat =
            SharedTextEntryPlan.make(
                rawText: " 공유 문장 ",
                mode: .chat
            )
        XCTAssertEqual(
            chat?.text,
            "공유 문장"
        )
        XCTAssertEqual(
            chat?
                .automaticallyStartsVoiceInput,
            false
        )
    }
}
