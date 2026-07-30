//
//  TTSManager.swift
//  shortcuts_example
//
//  Created by meee on 2/24/26.
//

import AVFoundation
import Combine

final class TTSManager: ObservableObject {
    
    static let shared = TTSManager()
    
    private let synthesizer = AVSpeechSynthesizer()
    
    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }
    
    private init() {
        prewarm()
    }
    
    private func prewarm() {
        let utterance = AVSpeechUtterance(string: " ")
        // utterance.volume = 0
        synthesizer.speak(utterance)
        synthesizer.stopSpeaking(at: .immediate)
    }
    
    func speak(_ text: String, rate: Float? = nil) {
        synthesizer.stopSpeaking(at: .immediate)
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = min(
            max(
                rate
                    ?? AppSettingsStore.shared
                    .speechRate.avSpeechRate,
                AVSpeechUtteranceMinimumSpeechRate
            ),
            AVSpeechUtteranceMaximumSpeechRate
        )
        
        synthesizer.speak(utterance)
    }

    func speakFeedback(_ text: String) {
        guard AppSettingsStore.shared
            .voiceFeedbackEnabled else {
            return
        }
        speak(text)
    }
    
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
