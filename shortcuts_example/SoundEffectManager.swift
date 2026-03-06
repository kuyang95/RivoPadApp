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

    enum Effect: String, CaseIterable {
        case recording      // recording.mp3
        case startingLLM        // startingLLM.mp3

        var fileExtension: String {
            return "mp3"   // 필요하면 케이스별로 분기 가능
        }
    }

    // MARK: - Storage

    private var players: [Effect: AVAudioPlayer] = [:]

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
            forResource: effect.rawValue,
            withExtension: effect.fileExtension
        ) else {
            print("❌ Sound file not found:", effect.rawValue)
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
        guard let player = players[effect] else {
            print("⚠️ Not preloaded:", effect.rawValue)
            return
        }

        player.currentTime = 0
        player.volume = volume
        player.play()
    }

    // MARK: - Stop

    func stop(_ effect: Effect) {
        players[effect]?.stop()
    }

    func stopAll() {
        players.values.forEach { $0.stop() }
    }
}
