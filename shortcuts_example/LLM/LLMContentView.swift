import SwiftUI
import CoreImage
import UIKit

enum ChatIntentInput: Equatable {
    case textChat(conversationID: UUID?)
    case voiceQuestion(question: String)
    case imageAnalysis(imageURL: URL, question: String)
    case documentQA(document: String, question: String)
    case webPageQA(
        content: WebPageContent,
        question: String
    )
    case webSearchQA(
        response: WebSearchResponse,
        question: String,
        speaksResponse: Bool
    )
}

struct LLMContentView: View {
    let intent: ChatIntentInput
    @StateObject private var vm: ChatViewModel
    @ObservedObject private var stt = STTManager.shared
    @EnvironmentObject private var remoteControl:
        RivoScreenRemoteControlCenter

    @State private var didStart = false
    @State private var speechTask: Task<Void, Never>?
    @State private var voiceErrorDescription: String?
    @State private var shouldSpeakNextResponse = false

    private let tts = TTSManager.shared

    init(intent: ChatIntentInput) {
        self.intent = intent
        let service = LLMService.shared
        let storedConversationID: UUID
        let persistsHistory: Bool
        switch intent {
        case .textChat(let conversationID):
            storedConversationID = conversationID ?? UUID()
            persistsHistory = true
        case .voiceQuestion:
            storedConversationID = UUID()
            persistsHistory = true
        case .imageAnalysis,
             .documentQA,
             .webPageQA,
             .webSearchQA:
            storedConversationID = UUID()
            persistsHistory = false
        }
        _vm = StateObject(
            wrappedValue: ChatViewModel(
                llm: service,
                storedConversationID: storedConversationID,
                persistsHistory: persistsHistory
            )
        )
        _shouldSpeakNextResponse = State(
            initialValue: {
                if case .voiceQuestion = intent {
                    return true
                }
                if case .webSearchQA(
                    _,
                    _,
                    let speaksResponse
                ) = intent {
                    return speaksResponse
                }
                return false
            }()
        )

        switch intent {
        case .imageAnalysis(let imageURL, let question):
            RVLogger.d("🔥 View에서 전달받은 imageURL: \(imageURL)")
            RVLogger.d("🔥 imageURL path: \(imageURL.path)")
            RVLogger.d("🔥 question: \(question)")
        case .textChat,
             .voiceQuestion,
             .documentQA,
             .webPageQA,
             .webSearchQA:
            break
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                if let source = webSource {
                    webSourceBanner(source)
                }
                if let response =
                        webSearchResponse {
                    webSearchSourceBanner(
                        response
                    )
                }

                if vm.messages.isEmpty, !vm.isLoadingModel {
                    ContentUnavailableView(
                        "새로운 대화",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text(
                            "M4에서 로컬로 실행되는 AI에게 질문해 보세요."
                        )
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List(vm.messages) { message in
                        MessageRow(message)
                            .listRowSeparator(.hidden)
                            .listRowInsets(
                                .init(
                                    top: 6,
                                    leading: 12,
                                    bottom: 6,
                                    trailing: 12
                                )
                            )
                    }
                    .listStyle(.plain)
                    .defaultScrollAnchor(.bottom)
                }

                if let error = voiceErrorDescription
                    ?? vm.historyErrorDescription {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .accessibilityLabel("오류: \(error)")
                } else if stt.isRecording {
                    Text("듣는 중… 마이크 버튼을 다시 누르면 종료됩니다.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .accessibilityLabel("음성을 듣는 중입니다.")
                } else if !vm.status.isEmpty {
                    Text(vm.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .accessibilityLabel("AI 상태: \(vm.status)")
                }

                HStack(alignment: .bottom) {
                    Button {
                        if stt.isRecording {
                            stt.finishRecording()
                        } else {
                            startVoiceInput()
                        }
                    } label: {
                        Image(
                            systemName: stt.isRecording
                                ? "stop.fill"
                                : "mic.fill"
                        )
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(stt.isRecording ? .red : .indigo)
                    .disabled(
                        !vm.isReadyForInput
                            || vm.isGenerating
                            || (
                                speechTask != nil
                                    && !stt.isRecording
                            )
                    )
                    .accessibilityLabel(
                        stt.isRecording
                            ? "음성 입력 종료"
                            : "음성으로 질문"
                    )
                    .accessibilityHint(
                        stt.isRecording
                            ? "인식을 마치고 질문을 전송합니다."
                            : "온디바이스 한국어 음성 인식을 시작합니다."
                    )

                    TextField(
                        "메시지를 입력하세요",
                        text: $vm.input,
                        axis: .vertical
                    )
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1 ... 6)
                        .disabled(
                            vm.isLoadingModel
                                || vm.isInitialQueryRunning
                                || vm.isGenerating
                                || stt.isRecording
                        )
                        .submitLabel(.send)
                        .onSubmit {
                            vm.sendUserMessage()
                        }

                    if vm.isGenerating {
                        Button("중지") {
                            vm.stop()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .accessibilityHint(
                            "현재 생성 중인 답변을 중지합니다."
                        )
                    } else {
                        Button("전송") {
                            vm.sendUserMessage()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!vm.canSend)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            if vm.isLoadingModel || vm.isInitialQueryRunning {
                Color.black.opacity(0.4).ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView().progressViewStyle(.circular)
                    Text(
                        vm.isLoadingModel
                            ? "로컬 모델을 불러오는 중"
                            : "분석 중…"
                    )
                        .font(.headline)
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .shadow(radius: 10)
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !didStart else { return }
            didStart = true
            await vm.prepare(for: intent)
        }
        .onDisappear {
            speechTask?.cancel()
            speechTask = nil
            stt.cancelRecording()
            tts.stop()
            vm.closeConversation()
        }
        .onChange(of: vm.isGenerating) { wasGenerating, isGenerating in
            guard wasGenerating,
                  !isGenerating,
                  shouldSpeakNextResponse else {
                return
            }
            shouldSpeakNextResponse = false
            guard vm.status == "완료",
                  let response = vm.messages.last(where: {
                      $0.role == "assistant"
                          && !$0.text.trimmingCharacters(
                              in: .whitespacesAndNewlines
                          ).isEmpty
                  }) else {
                return
            }
            speak(response.text)
        }
        .onChange(
            of: remoteControl.latestEvent
        ) { _, event in
            handleRemoteEvent(event)
        }
    }

    private var navigationTitle: String {
        switch intent {
        case .textChat, .voiceQuestion:
            return "로컬 AI"
        case .imageAnalysis:
            return "이미지 질문"
        case .documentQA:
            return "문서 질문"
        case .webPageQA:
            return "웹페이지 질문"
        case .webSearchQA:
            return "웹 검색 답변"
        }
    }

    private var webSource:
        WebPageContent?
    {
        guard case .webPageQA(
            let content,
            _
        ) = intent else {
            return nil
        }
        return content
    }

    private var webSearchResponse:
        WebSearchResponse?
    {
        guard case .webSearchQA(
            let response,
            _,
            _
        ) = intent else {
            return nil
        }
        return response
    }

    private func webSearchSourceBanner(
        _ response: WebSearchResponse
    ) -> some View {
        DisclosureGroup {
            VStack(
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(response.results) {
                    result in
                    Link(
                        destination: result.url
                    ) {
                        HStack {
                            Text(
                                "[\(result.id)] \(result.title)"
                            )
                            .lineLimit(2)
                            .multilineTextAlignment(
                                .leading
                            )
                            Spacer()
                            Image(
                                systemName:
                                    "arrow.up.right"
                            )
                        }
                    }
                }
                Text(
                    "검색 결과와 답변은 대화 기록에 저장하지 않습니다."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        } label: {
            Label(
                "Brave 검색 출처 \(response.results.count)개",
                systemImage:
                    "checkmark.shield"
            )
            .font(.subheadline.bold())
        }
        .padding(12)
        .background(
            Color.indigo.opacity(0.09)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
        .padding(.horizontal, 12)
    }

    private func webSourceBanner(
        _ content: WebPageContent
    ) -> some View {
        HStack(spacing: 12) {
            Image(
                systemName:
                    "link.circle.fill"
            )
            .foregroundStyle(.indigo)

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(content.title)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(
                    content.sourceURL
                        .absoluteString
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            Link(
                destination:
                    content.sourceURL
            ) {
                Image(
                    systemName: "safari"
                )
            }
            .accessibilityLabel(
                "Safari에서 원문 열기"
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color.secondary.opacity(0.08)
        )
        .accessibilityElement(
            children: .combine
        )
        .accessibilityLabel(
            "출처: \(content.title), \(content.sourceURL.absoluteString)"
        )
    }

    @discardableResult
    private func startVoiceInput() -> Bool {
        guard speechTask == nil,
              vm.isReadyForInput,
              !vm.isGenerating else {
            return false
        }

        tts.stop()
        voiceErrorDescription = nil
        speechTask = Task {
            defer {
                speechTask = nil
            }

            do {
                let stream = try await stt.startRecording(
                    requiresOnDeviceRecognition: true
                )
                for await recognizedText in stream {
                    try Task.checkCancellation()
                    let question = recognizedText.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    guard !question.isEmpty else {
                        voiceErrorDescription =
                            "음성을 인식하지 못했습니다. 다시 시도해 주세요."
                        continue
                    }

                    vm.input = question
                    shouldSpeakNextResponse = true
                    vm.sendUserMessage()
                }
            } catch is CancellationError {
                return
            } catch {
                voiceErrorDescription = error.localizedDescription
            }
        }
        return true
    }

    private func handleRemoteEvent(
        _ event: RivoScreenRemoteEvent?
    ) {
        guard event?.screen == .localAIChat,
              case .localAIChat(.toggleVoiceInput) =
                event?.action else {
            return
        }

        if speechTask != nil || stt.isRecording {
            speechTask?.cancel()
            speechTask = nil
            stt.cancelRecording()
            voiceErrorDescription = nil
            UIAccessibility.post(
                notification: .announcement,
                argument: "음성 입력 취소"
            )
        } else {
            let didStart = startVoiceInput()
            UIAccessibility.post(
                notification: .announcement,
                argument:
                    didStart
                        ? "음성 입력 시작"
                        : "AI가 준비되거나 답변을 마친 뒤 다시 시도해 주세요."
            )
        }
    }

    private func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            return
        }
        tts.stop()
        tts.speak(trimmed)
    }
}


private struct MessageRow: View {
    let m: ChatViewModel.Msg

    init(_ m: ChatViewModel.Msg) {
        self.m = m
    }

    var body: some View {
        HStack(alignment: .bottom) {
            if m.role == "user" {
                Spacer()
                bubble
            } else {
                bubble
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        VStack(alignment: m.role == "user" ? .trailing : .leading) {
            if let img = m.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)
                    .accessibilityLabel("첨부 이미지")
            }

            if !m.text.isEmpty {
                Text(m.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(
            m.role == "user"
                ? Color.accentColor.opacity(0.18)
                : Color.secondary.opacity(0.12)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(m.role == "user" ? "사용자" : "AI"): \(m.text)"
        )
    }
}
