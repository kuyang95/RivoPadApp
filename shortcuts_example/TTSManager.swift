//
//  TTSManager.swift
//  shortcuts_example
//
//  Created by meee on 2/24/26.
//

import AVFoundation
import Combine

@MainActor
final class TTSManager:
    NSObject,
    ObservableObject,
    AVSpeechSynthesizerDelegate
{
    static let shared = TTSManager()

    private let synthesizer = AVSpeechSynthesizer()

    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    private var activeUtteranceID:
        ObjectIdentifier?
    private var activeCompletion:
        (() -> Void)?

    private override init() {
        super.init()
        synthesizer.delegate = self
        prewarm()
    }

    private func prewarm() {
        let utterance = AVSpeechUtterance(string: " ")
        // utterance.volume = 0
        synthesizer.speak(utterance)
        synthesizer.stopSpeaking(at: .immediate)
    }

    func speak(
        _ text: String,
        rate: Float? = nil,
        completion: (() -> Void)? = nil
    ) {
        stop()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice =
            AVSpeechSynthesisVoice(
                language:
                    AppLanguage.current()
                    .speechLanguageCode
            )
        utterance.rate = min(
            max(
                rate
                    ?? AppSettingsStore.shared
                    .speechRate.avSpeechRate,
                AVSpeechUtteranceMinimumSpeechRate
            ),
            AVSpeechUtteranceMaximumSpeechRate
        )

        activeUtteranceID =
            ObjectIdentifier(utterance)
        activeCompletion = completion
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
        activeUtteranceID = nil
        activeCompletion = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance:
            AVSpeechUtterance
    ) {
        let utteranceID =
            ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.finishSpeech(
                utteranceID: utteranceID
            )
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance:
            AVSpeechUtterance
    ) {
        let utteranceID =
            ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.cancelSpeech(
                utteranceID: utteranceID
            )
        }
    }

    private func finishSpeech(
        utteranceID: ObjectIdentifier
    ) {
        guard activeUtteranceID
                == utteranceID else {
            return
        }
        let completion = activeCompletion
        activeUtteranceID = nil
        activeCompletion = nil
        completion?()
    }

    private func cancelSpeech(
        utteranceID: ObjectIdentifier
    ) {
        guard activeUtteranceID
                == utteranceID else {
            return
        }
        activeUtteranceID = nil
        activeCompletion = nil
    }
}
