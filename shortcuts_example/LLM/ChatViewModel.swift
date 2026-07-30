import Foundation
import Combine
import CoreImage
import UIKit

@MainActor
final class ChatViewModel: ObservableObject {

    struct Msg: Identifiable {
        let id: UUID
        let role: String
        var text: String
        var image: UIImage?
        let createdAt: Date

        init(
            id: UUID = UUID(),
            role: String,
            text: String = "",
            image: UIImage? = nil,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.role = role
            self.text = text
            self.image = image
            self.createdAt = createdAt
        }
    }

    @Published var messages: [Msg] = []
    @Published var input: String = ""
    @Published var status: String = ""
    @Published var isLoadingModel: Bool = false
    @Published var isInitialQueryRunning: Bool = false
    @Published var isGenerating: Bool = false
    @Published var historyErrorDescription: String?

    let llm: LLMService
    private var genTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var generationRequestID: UUID?
    private let conversationID: LLMConversationID
    private let historyStore: ChatHistoryStore
    private let persistsHistory: Bool
    private let storedConversationID: UUID
    private var conversationCreatedAt: Date
    private var conversationUpdatedAt: Date
    private var needsContextReplay = false
    private var didPrepare = false

    // ✅ 이미지 분석 모드일 때 고정 이미지(후속 질문에도 계속 같이 보냄)
    private var pinnedCIImages: [CIImage] = []

    // ✅ 한번 로드하면 재로드/모델 변경 방지
    private var didLoadOnce = false
    private var loadedKind: LoadedKind?

    private enum LoadedKind { case text, vision }

    var canSend: Bool {
        isReadyForInput
            && !isGenerating
            && !input.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
    }

    var isReadyForInput: Bool {
        didLoadOnce && !isLoadingModel
    }

    init(
        llm: LLMService,
        historyStore: ChatHistoryStore = .shared,
        storedConversationID: UUID = UUID(),
        persistsHistory: Bool = false
    ) {
        self.llm = llm
        self.historyStore = historyStore
        self.storedConversationID = storedConversationID
        self.persistsHistory = persistsHistory
        self.conversationID = LLMConversationID(
            storedConversationID
        )
        let now = Date()
        self.conversationCreatedAt = now
        self.conversationUpdatedAt = now
    }

    // MARK: - System Prompts (모드별로 다르게)

    private var systemForDocumentQA: String {
        """
        너는 한국어로 간결하게 답하는 도우미야.
        유저가 "Document:" 뒤에 제공하는 내용은 참고 문서고,
        "Question:" 뒤의 질문에 문서 내용을 근거로 답해.
        문서에 없는 내용은 추측하지 말고 모른다고 말해.
        """
    }

    private var systemForImageAnalysis: String {
        """
        너는 한국어로 답하는 이미지 분석 도우미야.
        제공된 이미지를 관찰해서 질문에 답해.
        보이지 않는 내용은 추측하지 말고, 확인 불가하다고 말해.
        """
    }

    private var systemForGeneralChat: String {
        """
        너는 iPad에서 완전히 로컬로 실행되는 한국어 AI 도우미야.
        사용자의 질문에 정확하고 명확하게 답하고, 확실하지 않은 내용은
        추측해서 단정하지 마.
        """
    }

    // MARK: - Prepare and load

    func prepare(for intent: ChatIntentInput) async {
        guard !didPrepare else {
            return
        }
        didPrepare = true

        if case .textChat = intent, persistsHistory {
            await restoreConversation()
        }

        guard await loadModel(for: intent) else {
            return
        }

        switch intent {
        case .textChat:
            break
        case .voiceQuestion(let question):
            input = question
            sendUserMessage()
        case .imageAnalysis, .documentQA:
            runInitialIntent(intent)
        }
    }

    @discardableResult
    func loadModel(for intent: ChatIntentInput) async -> Bool {
        guard !didLoadOnce else {
            return true
        }

        do {
            isLoadingModel = true

            switch intent {
            case .imageAnalysis:
                try await llm.activateModel(.qwen3_vl_8b_4bit)
                loadedKind = .vision
            case .textChat, .voiceQuestion, .documentQA:
                try await llm.activateModel(.qwen3_8b_4bit)
                loadedKind = .text
            }

            didLoadOnce = true
            isLoadingModel = false
            status = "준비됨"
            return true
        } catch {
            isLoadingModel = false
            status = "모델 로드 실패"
            historyErrorDescription = error.localizedDescription
            return false
        }
    }

    // MARK: - Initial run (Intent 들어온 순간 1회 실행)

    func runInitialIntent(_ intent: ChatIntentInput) {
        switch intent {
        case .textChat, .voiceQuestion:
            return

        case .imageAnalysis(let imageURL, let question):

            do {
                let data = try Data(contentsOf: imageURL)
                RVLogger.d("✅ data size: \(data.count)")

                if let uiImage = UIImage(data: data) {
                    RVLogger.d("✅ image size: \(uiImage.size)")

                    messages.append(.init(role: "user", text: "", image: uiImage))
                    messages.append(.init(role: "user", text: question, image: nil))

                    pinnedCIImages = toCIImages([uiImage])
                    startImageAnalysis(question: question)

                } else {
                    print("❌ UIImage 변환 실패")
                    status = "UIImage 변환 실패"
                }

            } catch {
                print("❌ Data load error:", error)
                status = "이미지 로드 실패: \(error.localizedDescription)"
            }

        case .documentQA(let document, let question):
            messages.append(.init(role: "user", text: question, image: nil))
            startDocumentQA(document: document, question: question)
        }
    }

    private func restoreConversation() async {
        do {
            guard let stored = try await historyStore.conversation(
                id: storedConversationID
            ) else {
                return
            }

            conversationCreatedAt = stored.createdAt
            conversationUpdatedAt = stored.updatedAt
            messages = stored.messages.map {
                Msg(
                    id: $0.id,
                    role: $0.role.rawValue,
                    text: $0.text,
                    createdAt: $0.createdAt
                )
            }
            needsContextReplay = !messages.isEmpty
        } catch {
            historyErrorDescription =
                "대화 기록을 불러오지 못했습니다: "
                + error.localizedDescription
        }
    }

    // MARK: - Start flows (초기 실행 전용 이름)

    private func startDocumentQA(document: String, question: String) {
        let fullPrompt = buildDocumentPrompt(document: document, question: question)
        startStreamingResponse(
            mode: .text,
            system: systemForDocumentQA,
            prompt: fullPrompt
        )
    }

    private func startImageAnalysis(question: String) {
        startStreamingResponse(
            mode: .vision,
            system: systemForImageAnalysis,
            prompt: question
        )
    }

    // MARK: - Manual Chat (후속 질문)

    func sendUserMessage() {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty,
              didLoadOnce,
              !isLoadingModel,
              !isGenerating else {
            return
        }
        input = ""

        let modelPrompt: String
        if persistsHistory, needsContextReplay {
            modelPrompt = ChatTranscriptBuilder.replayPrompt(
                messages: storedMessages(),
                newPrompt: prompt
            )
            needsContextReplay = false
        } else {
            modelPrompt = prompt
        }
        messages.append(.init(role: "user", text: prompt, image: nil))
        conversationUpdatedAt = Date()

        // ✅ 로드된 모델 종류에 따라 텍스트/비전 분기
        switch loadedKind {
        case .vision:
            startStreamingResponse(
                mode: .vision,
                system: systemForImageAnalysis,
                prompt: modelPrompt
            )
        case .text, .none:
            startStreamingResponse(
                mode: .text,
                system: persistsHistory
                    ? systemForGeneralChat
                    : systemForDocumentQA,
                prompt: modelPrompt
            )
        }
    }

    func stop() {
        cancelLocalGeneration(status: "중지됨")
        scheduleCleanup(resetSession: false)
    }

    func resetConversation() async {
        await llm.resetConversation(conversationID)
    }

    func closeConversation() {
        cancelLocalGeneration(status: nil)
        scheduleCleanup(resetSession: true)
    }

    private func cancelLocalGeneration(status: String?) {
        generationRequestID = nil
        genTask?.cancel()
        genTask = nil
        if let status {
            self.status = status
        }
        isInitialQueryRunning = false
        isGenerating = false
    }

    private func scheduleCleanup(resetSession: Bool) {
        cleanupTask?.cancel()
        cleanupTask = Task {
            await llm.cancelGeneration(for: conversationID)
            guard !Task.isCancelled else {
                return
            }
            await persistConversation()
            guard resetSession, !Task.isCancelled else {
                return
            }
            await resetConversation()
        }
    }

    // MARK: - Core streaming runner

    private enum RunMode { case text, vision }

    private func startStreamingResponse(mode: RunMode, system: String, prompt: String) {
        messages.append(.init(role: "assistant", text: "", image: nil))
        let assistantIndex = messages.count - 1
        let requestID = UUID()

        generationRequestID = requestID
        genTask?.cancel()
        genTask = Task {
            do {
                guard generationRequestID == requestID else {
                    throw CancellationError()
                }

                // 문서/이미지의 첫 분석에만 전체 화면 진행 표시를 사용한다.
                if !persistsHistory, messages.count <= 3 {
                    isInitialQueryRunning = true
                }
                isGenerating = true
                status = "답변 생성 중…"
                await persistConversation()

                let stream: AsyncThrowingStream<String, Error>
                switch mode {
                case .text:
                    stream = try await llm.streamText(
                        conversationID: conversationID,
                        system: system,
                        prompt: prompt
                    )
                case .vision:
                    stream = try await llm.streamVision(
                        conversationID: conversationID,
                        system: system,
                        prompt: prompt,
                        images: pinnedCIImages
                    )
                }

                try await consumeStream50ms(
                    stream,
                    assistantIndex: assistantIndex
                )
                guard generationRequestID == requestID else {
                    throw CancellationError()
                }

                conversationUpdatedAt = Date()
                status = "완료"
                isInitialQueryRunning = false
                isGenerating = false
                generationRequestID = nil
                await persistConversation()
            } catch is CancellationError {
                guard generationRequestID == requestID else {
                    return
                }
                conversationUpdatedAt = Date()
                status = "중지됨"
                isInitialQueryRunning = false
                isGenerating = false
                generationRequestID = nil
                await persistConversation()
            } catch {
                guard generationRequestID == requestID else {
                    return
                }
                messages[assistantIndex].text += "\n\n(스트림 오류: \(error))"
                conversationUpdatedAt = Date()
                status = "답변 생성 실패"
                historyErrorDescription = error.localizedDescription
                isInitialQueryRunning = false
                isGenerating = false
                generationRequestID = nil
                await persistConversation()
            }
        }
    }

    // MARK: - Stream 소비 + <think> 제거

    private func consumeStream50ms(
        _ stream: AsyncThrowingStream<String, Error>,
        assistantIndex: Int
    ) async throws {
        var thinkFilter = StreamingThinkFilter()
        var pending = ""
        let flushIntervalNs: UInt64 = 50_000_000 // 50ms
        var lastFlush = DispatchTime.now().uptimeNanoseconds

        func flushIfNeeded(force: Bool = false) {
            let now = DispatchTime.now().uptimeNanoseconds
            let due = (now - lastFlush) >= flushIntervalNs

            guard force || due else { return }
            guard !pending.isEmpty else { return }

            messages[assistantIndex].text += pending
            pending.removeAll(keepingCapacity: true)
            lastFlush = now
        }

        do {
            for try await chunk in stream {
                try Task.checkCancellation()

                pending += thinkFilter.consume(chunk)
                flushIfNeeded()
            }

            pending += thinkFilter.finish()
            // 스트림 끝나면 남은 거 강제 반영
            flushIfNeeded(force: true)

        } catch {
            pending += thinkFilter.finish()
            flushIfNeeded(force: true)
            throw error
        }
    }

    // MARK: - Prompt builders

    private func buildDocumentPrompt(document: String, question: String) -> String {
        """
        Document:
        \(document)

        Question:
        \(question)
        """
    }

    // MARK: - Local history

    private func persistConversation() async {
        guard persistsHistory else {
            return
        }

        let storedMessages = storedMessages()
        guard !storedMessages.isEmpty else {
            return
        }

        let titleSource = storedMessages.first(where: {
            $0.role == .user
        })?.text ?? ""
        let conversation = StoredChatConversation(
            id: storedConversationID,
            title: StoredChatConversation.title(
                from: titleSource
            ),
            createdAt: conversationCreatedAt,
            updatedAt: conversationUpdatedAt,
            messages: storedMessages
        )

        do {
            try await historyStore.upsert(conversation)
        } catch {
            historyErrorDescription =
                "대화 기록을 저장하지 못했습니다: "
                + error.localizedDescription
        }
    }

    private func storedMessages() -> [StoredChatMessage] {
        messages.compactMap { message in
            let text = message.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !text.isEmpty,
                  let role = StoredChatRole(
                      rawValue: message.role
                  ) else {
                return nil
            }
            return StoredChatMessage(
                id: message.id,
                role: role,
                text: text,
                createdAt: message.createdAt
            )
        }
    }

    // MARK: - UIImage -> CIImage

    private func toCIImages(_ images: [UIImage]) -> [CIImage] {
        images.compactMap { ui in
            if let ci = CIImage(image: ui) { return ci }
            if let cg = ui.cgImage { return CIImage(cgImage: cg) }
            return nil
        }
    }
}
