//
//  SoundEffectManager.swift
//  shortcuts_example
//
//  Created by meee on 3/3/26.
//

import Foundation
import AVFoundation

@MainActor
final class SoundEffectManager {

    static let shared = SoundEffectManager()
    private init() {}

    // MARK: - Effect Enum

    enum Effect: CaseIterable, Hashable {
        case record
        case recordComplete
        case complete
        case docScanGuideBeep
        case cameraShot2
        case connected
        case disconnected
        case bbob
        case popUp2
        case waiting
        case fail
        case toggleButtonPressed
        case toggleButtonReleased
        case recording
        case startingLLM

        var resourceName: String {
            switch self {
            case .record:
                return "pop_up_3"
            case .recordComplete:
                return "good_sound"
            case .complete:
                return "glow_4"
            case .docScanGuideBeep:
                return "doc_scan_tick"
            case .cameraShot2:
                return "camera2"
            case .connected:
                return "correct_9"
            case .disconnected:
                return "correct_9_reverse"
            case .bbob:
                return "water_droplet_sound"
            case .popUp2:
                return "pop_up_2"
            case .waiting:
                return "pencil_write_eng"
            case .fail:
                return "correct_11_low_slow_descending"
            case .toggleButtonPressed:
                return "woosh_sound"
            case .toggleButtonReleased:
                return "tiny_button_push_sound_reverse"
            case .recording:
                return "recording"
            case .startingLLM:
                return "startingLLM"
            }
        }

        var fileExtension: String {
            switch self {
            case .docScanGuideBeep,
                 .cameraShot2:
                return "wav"
            default:
                return "mp3"
            }
        }

        var ignoresSoundEffectToggle: Bool {
            self == .cameraShot2
        }
    }

    // MARK: - Storage

    private var players: [Effect: AVAudioPlayer] = [:]
    private var currentEffect: Effect?

    // MARK: - Preload All

    func preloadAll() {
        for effect in Effect.allCases {
            preload(effect)
        }
        print("✅ All sound effects preloaded")
    }

    private func preload(_ effect: Effect) {
        guard players[effect] == nil else { return }

        guard let url = Bundle.main.url(
            forResource: effect.resourceName,
            withExtension: effect.fileExtension
        ) else {
            print("❌ Sound file not found:", effect.resourceName)
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            players[effect] = player
        } catch {
            print("❌ Preload error:", error)
        }
    }

    // MARK: - Play

    func play(_ effect: Effect, volume: Float = 1.0) {
        guard AppSettingsStore.shared
            .soundEffectsEnabled
                || effect.ignoresSoundEffectToggle else {
            return
        }
        guard let player = players[effect] else {
            print("⚠️ Not preloaded:", effect.resourceName)
            return
        }

        if let currentEffect,
           currentEffect != effect,
           let currentPlayer = players[currentEffect] {
            currentPlayer.stop()
            currentPlayer.currentTime = 0
        }
        player.currentTime = 0
        player.volume = volume
        if player.play() {
            currentEffect = effect
        }
    }

    // MARK: - Stop

    func stop(_ effect: Effect) {
        guard let player = players[effect] else {
            return
        }
        player.stop()
        player.currentTime = 0
        if currentEffect == effect {
            currentEffect = nil
        }
    }

    func stopAll() {
        players.values.forEach {
            $0.stop()
            $0.currentTime = 0
        }
        currentEffect = nil
    }
}
