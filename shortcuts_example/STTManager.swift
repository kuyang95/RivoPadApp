import Foundation
import Speech
import AVFoundation
import Accelerate
import Combine

/// Android `STTHelper.showSpeechRecognitionErrorToast`: one distinct message
/// per failure kind. Callers show `message` on screen; the failure sound is
/// played here, once, when the failure is decided.
nonisolated enum STTFailure: Equatable, Sendable {
    case microphoneUnavailable
    case network
    case permissionDenied
    case notRecognized
    case noSpeech
    case recognizerUnavailable
    case unknown

    var message: String {
        switch self {
        case .microphoneUnavailable:
            return AppLocalization.string("마이크를 사용할 수 없습니다.")
        case .network:
            return AppLocalization.string("인터넷 연결을 확인해주세요.")
        case .permissionDenied:
            return AppLocalization.string("마이크 권한을 확인해주세요.")
        case .notRecognized:
            return AppLocalization.string("음성을 인식하지 못했습니다.")
        case .noSpeech:
            return AppLocalization.string("음성이 들리지 않았습니다.")
        case .recognizerUnavailable:
            return AppLocalization.string("음성 인식을 사용할 수 없습니다.")
        case .unknown:
            return AppLocalization.string("음성 인식에 실패했습니다.")
        }
    }
}

@MainActor
final class STTManager: ObservableObject {

    static let shared = STTManager()
    private init() {}

    // MARK: - Speech
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var requestFinishHandler: (() -> Void)?

    /// Android `STTHelper` uses the device language; here the app language
    /// setting wins so the recognizer follows the UI the user reads.
    private var locale: Locale {
        Locale(
            identifier:
                AppSettingsStore.shared
                .appLanguage
                .speechLanguageCode
        )
    }

    // MARK: - Recording State
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var amplitude: Float = 0

    /// Why the last listening session ended without text. Cleared when a new
    /// session starts; callers read it after the stream ends empty.
    @Published private(set) var lastFailure: STTFailure?

    // MARK: - Auto Stop Tuning
    /// End after 3.5 s of acoustic silence or 2.5 s without a transcript
    /// update once speech has been recognized.
    private let silenceDurationRMS: TimeInterval = 3.5
    private let rmsThreshold: Float = 0.005
    private let noTextUpdateDuration: TimeInterval = 2.5

    /// Safety net: a session never runs longer than this even when the room
    /// is noisy enough to keep the RMS above the threshold.
    private let maximumListeningDuration: TimeInterval = 90

    // endAudio 후 final이 안 오면 강제 종료 (안전장치)
    private let finalTimeoutAfterEndAudio: TimeInterval = 2.0

    enum STTError: LocalizedError {
        case permissionDenied
        case recognizerUnavailable
        case alreadyRecording
        case onDeviceRecognitionUnavailable

        var failure: STTFailure {
            switch self {
            case .permissionDenied:
                return .permissionDenied
            case .recognizerUnavailable,
                 .onDeviceRecognitionUnavailable:
                return .recognizerUnavailable
            case .alreadyRecording:
                return .unknown
            }
        }

        var errorDescription: String? {
            switch self {
            case .permissionDenied,
                 .recognizerUnavailable:
                return failure.message
            case .alreadyRecording:
                return AppLocalization.string(
                    "이미 음성을 듣고 있습니다."
                )
            case .onDeviceRecognitionUnavailable:
                return AppLocalization.string(
                    "이 기기에서 온디바이스 음성 인식을 사용할 수 없습니다."
                )
            }
        }
    }

    /// Android `showSpeechRecognitionErrorToast` for a thrown start error.
    nonisolated static func failure(for error: Error) -> STTFailure {
        if let sttError = error as? STTError {
            return sttError.failure
        }
        return Self.classify(error as NSError, heardText: false)
    }

    /// Maps a Speech framework error to the Android failure kinds.
    nonisolated private static func classify(
        _ error: NSError,
        heardText: Bool
    ) -> STTFailure {
        if error.domain == NSURLErrorDomain {
            return .network
        }
        if error.domain == "kAFAssistantErrorDomain" {
            switch error.code {
            case 1110:
                return .noSpeech
            case 203:
                return .notRecognized
            case 1101, 1107:
                return .recognizerUnavailable
            default:
                break
            }
        }
        if error.domain == NSOSStatusErrorDomain {
            return .microphoneUnavailable
        }
        return heardText ? .notRecognized : .unknown
    }

    // MARK: - Logging
    private func log(_ msg: String) {
        let t = String(format: "%.3f", Date().timeIntervalSince1970)
        print("🎙️[STT][\(t)] \(msg)")
    }

    // MARK: - Public API
    func startRecording(
        requiresOnDeviceRecognition: Bool = false,
        startEffect: SoundEffectManager.Effect = .record
    ) async throws -> AsyncStream<String> {
        log("▶️ startRecording() called. isRecording=\(isRecording) audioEngine.isRunning=\(audioEngine.isRunning)")

        guard !isRecording else { throw STTError.alreadyRecording }
        lastFailure = nil
        SoundEffectManager.shared.play(startEffect)

        let permissionGranted = await requestPermission()
        try Task.checkCancellation()
        log("🔐 Permission result: \(permissionGranted)")
        guard permissionGranted else {
            throw fail(.permissionDenied, error: .permissionDenied)
        }
        guard !isRecording else {
            SoundEffectManager.shared.play(.fail)
            throw STTError.alreadyRecording
        }

        stopEngineIfNeeded()

        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable else {
            throw fail(.recognizerUnavailable, error: .recognizerUnavailable)
        }
        guard !requiresOnDeviceRecognition
                || recognizer.supportsOnDeviceRecognition else {
            throw fail(
                .recognizerUnavailable,
                error: .onDeviceRecognitionUnavailable
            )
        }
        self.speechRecognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.recognitionRequest = request

        return AsyncStream { continuation in
            self.log("🧵 AsyncStream started (continuation created)")

            let sessionStart = Date()
            var lastVoiceTime = Date()
            var lastTextUpdateTime = Date()
            var lastPartialText: String = ""

            var didEndAudio = false
            var didFinishStream = false

            func finishOnce(
                _ text: String?,
                failure: STTFailure? = nil
            ) {
                guard !didFinishStream else { return }
                didFinishStream = true
                Task { @MainActor in
                    self.requestFinishHandler = nil
                    if let failure {
                        self.lastFailure = failure
                        SoundEffectManager.shared.play(.fail)
                    } else {
                        SoundEffectManager.shared.play(.recordComplete)
                    }
                    if let text {
                        continuation.yield(text)
                    }
                    self.stopInternalCancel()
                    continuation.finish()
                }
            }

            func endAudioAndStopEngineOnce(reason: String) {
                guard !didEndAudio else { return }
                didEndAudio = true

                Task { @MainActor in
                    self.log("⏹ endAudioAndStopEngine() reason=\(reason)")

                    // 더 이상 append하지 않도록 탭/엔진을 멈춰서 입력 스트림을 "확실히" 끝낸다
                    if self.audioEngine.isRunning {
                        self.audioEngine.stop()
                    }
                    self.audioEngine.inputNode.removeTap(onBus: 0)

                    // Speech에게 "입력 끝" 선언
                    self.recognitionRequest?.endAudio()

                    // final이 안 오면 안전장치로 종료
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(self.finalTimeoutAfterEndAudio * 1_000_000_000))
                        if !didFinishStream {
                            self.log("⏳ final timeout hit → finishing without final")
                            let fallback = lastPartialText
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                            finishOnce(
                                fallback.isEmpty ? nil : fallback,
                                failure: fallback.isEmpty ? .noSpeech : nil
                            )
                        }
                    }
                }
            }

            self.requestFinishHandler = {
                endAudioAndStopEngineOnce(reason: "manual stop")
            }

            // Tap
            let inputNode = self.audioEngine.inputNode
            inputNode.removeTap(onBus: 0)
            let format = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                if didEndAudio { return } // endAudio 이후엔 append 금지

                request.append(buffer)

                // 🔹 음성 amplitude 계산
                let rms = Self.rmsValue(buffer: buffer)

                Task { @MainActor in
                    // smoothing (UI가 덜 튐)
                    self.amplitude = self.amplitude * 0.7 + rms * 0.3
                }

                // RMS 기반 무음 감지 — Android 와 같은 3.5초 창
                if rms >= self.rmsThreshold {
                    lastVoiceTime = Date()
                } else {
                    let silent = Date().timeIntervalSince(lastVoiceTime)
                    if silent >= self.silenceDurationRMS {
                        endAudioAndStopEngineOnce(reason: "RMS silence \(silent)s >= \(self.silenceDurationRMS)s")
                        return
                    }
                }

                let noUpdate = Date().timeIntervalSince(lastTextUpdateTime)
                if noUpdate >= self.noTextUpdateDuration,
                   !lastPartialText.isEmpty {
                    endAudioAndStopEngineOnce(reason: "no text update \(noUpdate)s >= \(self.noTextUpdateDuration)s")
                    return
                }

                // 안전장치: 소음으로 RMS 가 계속 튀어도 세션이 무한히 이어지지 않는다
                let elapsed = Date().timeIntervalSince(sessionStart)
                if elapsed >= self.maximumListeningDuration {
                    endAudioAndStopEngineOnce(reason: "maximum duration \(elapsed)s")
                    return
                }
            }

            self.audioEngine.prepare()
            do {
                try self.audioEngine.start()
                self.isRecording = true
                self.log("✅ audioEngine.start() success. isRecording=true")
            } catch {
                self.log("⛔️ audioEngine.start() failed: \(error.localizedDescription)")
                finishOnce(nil, failure: .microphoneUnavailable)
                return
            }

            self.log("🧠 Starting recognitionTask…")
            self.recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.log("📝 result isFinal=\(result.isFinal) text=\(text)")

                    if !text.isEmpty && text != lastPartialText {
                        lastPartialText = text
                        lastTextUpdateTime = Date()
                    }

                    if result.isFinal {
                        let finalText = text.isEmpty ? lastPartialText : text
                        finishOnce(
                            finalText.isEmpty ? nil : finalText,
                            failure: finalText.isEmpty ? .noSpeech : nil
                        )
                        return
                    }
                }

                if let error {
                    // endAudio 이후에 나오는 취소/기타 에러는 상황에 따라 final이 늦게 올 수도 있으니,
                    // 여기선 즉시 cancel하기보단 마무리로 종료
                    let nsError = error as NSError
                    self.log("❌ recognition error: \(nsError.domain) \(nsError.code) \(error.localizedDescription)")
                    let heard = lastPartialText
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !heard.isEmpty {
                        // 말은 들었으니 실패가 아니라 그 문장으로 끝낸다.
                        finishOnce(heard)
                    } else {
                        finishOnce(
                            nil,
                            failure: Self.classify(
                                nsError,
                                heardText: false
                            )
                        )
                    }
                    return
                }
            }

            continuation.onTermination = { reason in
                Task { @MainActor in
                    self.log("🧵 AsyncStream onTermination reason=\(reason)")
                    self.stopInternalCancel()
                }
            }
        }
    }

    func finishRecording() {
        requestFinishHandler?()
    }

    func cancelRecording() {
        requestFinishHandler = nil
        stopInternalCancel()
    }

    /// Returns the reason the last session ended empty, then clears it so a
    /// later session cannot show a stale message.
    func consumeLastFailure() -> STTFailure? {
        defer { lastFailure = nil }
        return lastFailure
    }

    private func fail(
        _ failure: STTFailure,
        error: STTError
    ) -> STTError {
        lastFailure = failure
        SoundEffectManager.shared.play(.fail)
        return error
    }

    // MARK: - Stop

    /// final 받기 전에는 cancel을 최대한 피해야 함.
    /// 하지만 stream을 완전히 종료할 때는 cancel 포함해서 정리.
    private func stopInternalCancel() {
        guard isRecording || audioEngine.isRunning || recognitionTask != nil || recognitionRequest != nil else { return }

        isRecording = false

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionTask = nil
        recognitionRequest = nil
        requestFinishHandler = nil
        self.amplitude = 0

        log("🛑 STT fully stopped")
    }

    private func stopEngineIfNeeded() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        requestFinishHandler = nil
        isRecording = false
    }

    // MARK: - Permission
    private func requestPermission() async -> Bool {
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let mic = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        return speech && mic
    }

    // MARK: - RMS
    nonisolated private static func rmsValue(buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, vDSP_Length(buffer.frameLength))
        return rms
    }
}
