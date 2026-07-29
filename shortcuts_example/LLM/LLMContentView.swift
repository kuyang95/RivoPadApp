import SwiftUI
import CoreImage
import UIKit

enum ChatIntentInput: Equatable {
    case textChat(conversationID: UUID?)
    case imageAnalysis(imageURL: URL, question: String)
    case documentQA(document: String, question: String)
}

struct LLMContentView: View {
    let intent: ChatIntentInput
    @StateObject private var vm: ChatViewModel

    @State private var didStart = false

    init(intent: ChatIntentInput) {
        self.intent = intent
        let service = LLMService.shared
        let storedConversationID: UUID
        let persistsHistory: Bool
        switch intent {
        case .textChat(let conversationID):
            storedConversationID = conversationID ?? UUID()
            persistsHistory = true
        case .imageAnalysis, .documentQA:
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

        switch intent {
        case .imageAnalysis(let imageURL, let question):
            RVLogger.d("🔥 View에서 전달받은 imageURL: \(imageURL)")
            RVLogger.d("🔥 imageURL path: \(imageURL.path)")
            RVLogger.d("🔥 question: \(question)")
        case .textChat, .documentQA:
            break
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
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

                if let error = vm.historyErrorDescription {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .accessibilityLabel("오류: \(error)")
                } else if !vm.status.isEmpty {
                    Text(vm.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .accessibilityLabel("AI 상태: \(vm.status)")
                }

                HStack(alignment: .bottom) {
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
            vm.closeConversation()
        }
    }

    private var navigationTitle: String {
        switch intent {
        case .textChat:
            return "로컬 AI"
        case .imageAnalysis:
            return "이미지 질문"
        case .documentQA:
            return "문서 질문"
        }
    }
}


private struct MessageRow: View {
    let m: ChatViewModel.Msg
    init(_ m: ChatViewModel.Msg) { self.m = m }

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
