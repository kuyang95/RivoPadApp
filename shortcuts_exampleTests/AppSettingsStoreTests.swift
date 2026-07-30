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
        XCTAssertEqual(
            store.fontChoice,
            .nanumSquareRound
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
        store.fontChoice = .system

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
        XCTAssertEqual(
            restored.fontChoice,
            .system
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
            forKey: "settings.fontChoice.v1"
        )

        let store = AppSettingsStore(
            defaults: defaults
        )
        XCTAssertEqual(
            store.speechRate,
            .normal
        )
        XCTAssertEqual(
            store.fontChoice,
            .nanumSquareRound
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
        store.fontChoice = .system

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
        XCTAssertEqual(
            store.fontChoice,
            .nanumSquareRound
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
    }
}
