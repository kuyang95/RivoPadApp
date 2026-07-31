import SwiftUI

struct LocalVoiceActionView: View {
    @ObservedObject private var stt = STTManager.shared
    @EnvironmentObject private var remoteControl:
        RivoScreenRemoteControlCenter

    let onRoute: (AppRoute) -> Void
    let onFileImport: () -> Void
    let onClose: () -> Void

    @State private var status =
        AppLocalization.string(
            "말씀해 주세요."
        )
    @State private var errorDescription: String?
    @State private var listeningTask:
        Task<Void, Never>?
    @State private var didFinish = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .zIndex(0)

            if stt.isRecording {
                AuroraListeningOverlay(
                    amplitude: stt.amplitude
                )
                .allowsHitTesting(false)
                .ignoresSafeArea()
                .zIndex(1)
            }

            VStack(spacing: 28) {
                Image(
                    systemName:
                        stt.isRecording
                            ? "waveform.circle.fill"
                            : "mic.circle.fill"
                )
                .font(.system(size: 104))
                .foregroundStyle(
                    stt.isRecording
                        ? Color.red
                        : Color.indigo
                )
                .accessibilityHidden(true)

                Text("음성 명령")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                Text(errorDescription ?? status)
                    .font(.title2)
                    .foregroundStyle(
                        errorDescription == nil
                            ? Color.white
                            : Color.red
                    )
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)

                HStack(spacing: 20) {
                    if !stt.isRecording,
                       listeningTask == nil {
                        Button("다시 듣기") {
                            retryListening()
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.title3.bold())
                    }

                    Button("취소", role: .cancel) {
                        cancelAndClose()
                    }
                    .buttonStyle(.bordered)
                    .font(.title3.bold())
                    .tint(.white)
                }
            }
            .padding(40)
            .zIndex(2)
        }
        .navigationBarBackButtonHidden(true)
        .task {
            startListening()
        }
        .onChange(
            of: remoteControl.latestEvent
        ) { _, event in
            guard event?.screen == .voiceAction,
                  case .voiceAction(.cancel) =
                    event?.action else {
                return
            }
            cancelAndClose()
        }
        .onDisappear {
            listeningTask?.cancel()
            listeningTask = nil
            stt.cancelRecording()
        }
    }

    private func startListening() {
        guard listeningTask == nil,
              !stt.isRecording,
              !didFinish else {
            return
        }
        errorDescription = nil
        status = AppLocalization.string(
            "말씀해 주세요."
        )
        TTSManager.shared.stop()
        SoundEffectManager.shared.play(.recording)

        listeningTask = Task {
            defer {
                listeningTask = nil
            }
            do {
                let stream = try await stt.startRecording(
                    requiresOnDeviceRecognition: true
                )
                for await transcription in stream {
                    try Task.checkCancellation()
                    handle(transcription)
                    break
                }
                if !didFinish,
                   errorDescription == nil {
                    errorDescription =
                        AppLocalization.string(
                            "음성을 인식하지 못했습니다. 다시 시도해 주세요."
                        )
                }
            } catch is CancellationError {
                return
            } catch {
                errorDescription = error.localizedDescription
            }
        }
    }

    private func handle(_ transcription: String) {
        guard !didFinish,
              let intent =
                LocalVoiceActionClassifier.classify(
                    transcription
                ) else {
            errorDescription =
                AppLocalization.string(
                    "음성을 인식하지 못했습니다. 다시 시도해 주세요."
                )
            return
        }
        didFinish = true
        status = transcription

        switch intent {
        case .readVisibleText:
            route(
                .liveTextReader,
                announcement:
                    AppLocalization.string(
                        "실시간 텍스트 읽기를 엽니다."
                    )
            )
        case .describeScene:
            route(
                .magnifier,
                announcement:
                    AppLocalization.string(
                        "카메라를 엽니다. 대상을 촬영해 설명할 수 있습니다."
                    )
            )
        case .capture:
            route(
                .magnifier,
                announcement:
                    AppLocalization.string(
                        "카메라를 엽니다."
                    )
            )
        case .openAIChat:
            route(
                .localChat(conversationID: nil),
                announcement:
                    AppLocalization.string(
                        "새 로컬 AI 대화를 엽니다."
                    )
            )
        case .openChatHistory:
            route(
                .chatHistory,
                announcement:
                    AppLocalization.string(
                        "AI 대화 기록을 엽니다."
                    )
            )
        case .openAIDocument:
            announce(
                AppLocalization.string(
                    "질문할 PDF 또는 텍스트 문서를 선택해 주세요."
                )
            )
            onFileImport()
        case .openReader:
            route(
                .readerLibrary,
                announcement:
                    AppLocalization.string(
                        "독서 보관함을 엽니다."
                    )
            )
        case .openDocumentScanner:
            route(
                .documentScanning,
                announcement:
                    AppLocalization.string(
                        "문서 스캐너를 엽니다."
                    )
            )
        case .openMagnifier:
            route(
                .magnifier,
                announcement:
                    AppLocalization.string(
                        "카메라 돋보기를 엽니다."
                    )
            )
        case .openCamera:
            route(
                .magnifier,
                announcement:
                    AppLocalization.string(
                        "카메라를 엽니다."
                    )
            )
        case .openTextDocument:
            announce(
                AppLocalization.string(
                    "열 PDF 또는 텍스트 문서를 선택해 주세요."
                )
            )
            onFileImport()
        case .translate(let source):
            route(
                .translation(
                    initialText:
                        source.isEmpty
                            ? nil
                            : source
                ),
                announcement:
                    AppLocalization.string(
                        "로컬 번역 화면을 엽니다."
                    )
            )
        case .introduce:
            status =
                AppLocalization.string(
                    "저는 iPad에서 로컬로 동작하는 VisionCraft 도우미입니다."
                )
            announce(status)
        case .webSearch(let question):
            route(
                .webSearch(
                    initialQuery:
                        question,
                    autoSearch: true,
                    speaksAnswer: true
                ),
                announcement:
                    AppLocalization.string(
                        "온라인에서 출처를 찾고 M4 로컬 AI가 답변합니다."
                    )
            )
        case .question(let question):
            route(
                .voiceQuestion(question: question),
                announcement:
                    AppLocalization.string(
                        "로컬 AI가 답변합니다."
                    )
            )
        }
    }

    private func route(
        _ route: AppRoute,
        announcement: String
    ) {
        announce(announcement)
        onRoute(route)
    }

    private func announce(_ message: String) {
        TTSManager.shared.speakFeedback(
            message
        )
        UIAccessibility.post(
            notification: .announcement,
            argument: message
        )
    }

    private func retryListening() {
        didFinish = false
        startListening()
    }

    private func cancelAndClose() {
        listeningTask?.cancel()
        listeningTask = nil
        stt.cancelRecording()
        TTSManager.shared.stop()
        onClose()
    }
}
