import Foundation
import Speech
import AVFoundation
import Accelerate
import Combine

@MainActor
final class STTManager: ObservableObject {

    static let shared = STTManager()
    private init() {}

    // MARK: - Speech
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private let locale = Locale(identifier: "ko-KR")

    // MARK: - Recording State
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var amplitude: Float = 0

    // MARK: - Auto Stop Tuning
    private let silenceDurationRMS: TimeInterval = 4.0
    private let rmsThreshold: Float = 0.005

    // “텍스트가 더 이상 업데이트 안 됨” 기준 (말 끝 감지에 매우 강력)
    private let noTextUpdateDuration: TimeInterval = 1.2

    // endAudio 후 final이 안 오면 강제 종료 (안전장치)
    private let finalTimeoutAfterEndAudio: TimeInterval = 2.0

    enum STTError: Error {
        case permissionDenied
        case recognizerUnavailable
        case alreadyRecording
    }

    // MARK: - Logging
    private func log(_ msg: String) {
        let t = String(format: "%.3f", Date().timeIntervalSince1970)
        print("🎙️[STT][\(t)] \(msg)")
    }

    // MARK: - Public API
    func startRecording() async throws -> AsyncStream<String> {
        log("▶️ startRecording() called. isRecording=\(isRecording) audioEngine.isRunning=\(audioEngine.isRunning)")

        guard !isRecording else { throw STTError.alreadyRecording }

        let permissionGranted = await requestPermission()
        log("🔐 Permission result: \(permissionGranted)")
        guard permissionGranted else { throw STTError.permissionDenied }

        stopEngineIfNeeded()

        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable else {
            throw STTError.recognizerUnavailable
        }
        self.speechRecognizer = recognizer

        let audioSession = AVAudioSession.sharedInstance()
//        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.recognitionRequest = request

        return AsyncStream { continuation in
            self.log("🧵 AsyncStream started (continuation created)")

            var lastVoiceTime = Date()
            var lastTextUpdateTime = Date()
            var lastPartialText: String = ""

            var didEndAudio = false
            var didFinishStream = false

            func finishOnce(_ text: String?) {
                guard !didFinishStream else { return }
                didFinishStream = true
                Task { @MainActor in
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
                            finishOnce(nil)
                        }
                    }
                }
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

                // RMS 기반 무음 감지
                if rms >= self.rmsThreshold {
                    lastVoiceTime = Date()
                } else {
                    let silent = Date().timeIntervalSince(lastVoiceTime)
                    if silent >= self.silenceDurationRMS {
                        endAudioAndStopEngineOnce(reason: "RMS silence \(silent)s >= \(self.silenceDurationRMS)s")
                        return
                    }
                }

                // 텍스트 업데이트 정지 기반 종료 (말 끝났는데 노이즈로 RMS가 계속 튀는 상황을 잡아줌)
                let noUpdate = Date().timeIntervalSince(lastTextUpdateTime)
                if noUpdate >= self.noTextUpdateDuration, !lastPartialText.isEmpty {
                    endAudioAndStopEngineOnce(reason: "no text update \(noUpdate)s >= \(self.noTextUpdateDuration)s")
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
                finishOnce(nil)
                return
            }

            self.log("🧠 Starting recognitionTask…")
            self.recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.log("📝 result isFinal=\(result.isFinal) text=\(text)")

                    // partial 텍스트가 실제로 바뀌는 순간만 “업데이트 시각” 갱신
                    if !text.isEmpty && text != lastPartialText {
                        lastPartialText = text
                        lastTextUpdateTime = Date()
                    }

                    if result.isFinal {
                        let finalText = text.isEmpty ? lastPartialText : text
                        finishOnce(finalText.isEmpty ? nil : finalText)
                        return
                    }
                }

                if let error {
                    // endAudio 이후에 나오는 취소/기타 에러는 상황에 따라 final이 늦게 올 수도 있으니,
                    // 여기선 즉시 cancel하기보단 마무리로 종료
                    self.log("❌ recognition error: \((error as NSError).domain) \((error as NSError).code) \(error.localizedDescription)")
                    finishOnce(lastPartialText.isEmpty ? nil : lastPartialText)
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

    // MARK: - Stop (내부용)

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
        self.amplitude = 0

//        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        return speech && mic
    }

    // MARK: - RMS
    private static func rmsValue(buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, vDSP_Length(buffer.frameLength))
        return rms
    }
}
