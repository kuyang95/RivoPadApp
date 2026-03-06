//
//  AppAudioManager.swift
//  shortcuts_example
//
//  Created by meee on 3/3/26.
//

import AVFoundation

@MainActor
final class AppAudioManager {

    static let shared = AppAudioManager()
    private init() {}

    func configure() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [
                    .defaultToSpeaker,
                    .mixWithOthers
                ]
            )

            try session.setActive(true)

            print("✅ Global AudioSession configured")

        } catch {
            print("❌ AudioSession config failed:", error)
        }
    }
}
