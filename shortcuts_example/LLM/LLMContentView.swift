import SwiftUI
import CoreImage
import UIKit

enum ChatIntentInput: Equatable {
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
        _vm = StateObject(wrappedValue: ChatViewModel(llm: service))
        
        switch intent {
           case .imageAnalysis(let imageURL, let question):
               RVLogger.d("🔥 View에서 전달받은 imageURL: \(imageURL)")
               RVLogger.d("🔥 imageURL path: \(imageURL.path)")
               RVLogger.d("🔥 question: \(question)")
           case .documentQA:
               break
           }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 8) {

                // 메시지 리스트
                List(vm.messages) { m in
                    MessageRow(m)
                        .listRowSeparator(.hidden)
                        .listRowInsets(.init(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
                .listStyle(.plain)

                // 입력창 + 전송
                HStack {
                    TextField("Message…", text: $vm.input, axis: .vertical)
                        .textFieldStyle(.roundedBorder)

                    Button("Send") {
                        vm.sendUserMessage()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .disabled(vm.isLoadingModel || vm.isInitialQueryRunning)

            // 로딩/초기 분석 오버레이
            if vm.isLoadingModel || vm.isInitialQueryRunning {
                Color.black.opacity(0.4).ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView().progressViewStyle(.circular)
                    Text(vm.isLoadingModel ? "모델 불러오는중" : "분석중...")
                        .font(.headline)
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .shadow(radius: 10)
            }
        }
        .task {
            guard !didStart else { return }
            didStart = true

            // ✅ Intent에 따라 모델을 한 번만 로드
            await vm.loadModel(for: intent)

            // ✅ 초기 메시지 세팅(문서는 표시 X)
            vm.runInitialIntent(intent)
        }
        .onDisappear {
            vm.stop()
            Task {
                await vm.resetConversation()
            }
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
        Group {
            if let img = m.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260) // 필요하면 조절
            }

            if !m.text.isEmpty {
                Text(m.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
