import Foundation
import XCTest

@testable import shortcuts_example

@MainActor
final class SoundEffectParityTests: XCTestCase {
    func testAndroidSoundEffectResourceMapping() {
        let expected: [
            SoundEffectManager.Effect:
                (name: String, fileExtension: String)
        ] = [
            .record: ("pop_up_3", "mp3"),
            .recordComplete: ("good_sound", "mp3"),
            .complete: ("glow_4", "mp3"),
            .docScanGuideBeep: ("doc_scan_tick", "wav"),
            .cameraShot2: ("camera2", "wav"),
            .connected: ("correct_9", "mp3"),
            .disconnected: ("correct_9_reverse", "mp3"),
            .bbob: ("water_droplet_sound", "mp3"),
            .popUp2: ("pop_up_2", "mp3"),
            .waiting: ("pencil_write_eng", "mp3"),
            .fail: ("correct_11_low_slow_descending", "mp3"),
            .toggleButtonPressed: ("woosh_sound", "mp3"),
            .toggleButtonReleased:
                ("tiny_button_push_sound_reverse", "mp3"),
            .recording: ("recording", "mp3"),
            .startingLLM: ("startingLLM", "mp3"),
        ]

        XCTAssertEqual(
            Set(SoundEffectManager.Effect.allCases),
            Set(expected.keys)
        )
        for (effect, resource) in expected {
            XCTAssertEqual(effect.resourceName, resource.name)
            XCTAssertEqual(
                effect.fileExtension,
                resource.fileExtension
            )
        }
    }

    func testOnlyCameraShutterIgnoresSoundEffectSetting() {
        for effect in SoundEffectManager.Effect.allCases {
            XCTAssertEqual(
                effect.ignoresSoundEffectToggle,
                effect == .cameraShot2
            )
        }
    }

    func testEverySoundEffectResourceIsBundled() {
        for effect in SoundEffectManager.Effect.allCases {
            XCTAssertNotNil(
                Bundle.main.url(
                    forResource: effect.resourceName,
                    withExtension: effect.fileExtension
                ),
                "Missing sound effect: \(effect.resourceName).\(effect.fileExtension)"
            )
        }
    }
}
