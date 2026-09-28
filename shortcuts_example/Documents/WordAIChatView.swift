import Combine
import SwiftUI
import UIKit

@MainActor
final class WordAIChatViewModel: ObservableObject {
    struct Message: Identifiable, Sendable {
        enum Role: Equatable, Sendable {
            case user
            case assistant
            case notice
        }

        let id = UUID()
        let role: Role
        let text: String
    }

    @Published var input = ""
    @Published private(set) var messages: [Message] = []
    @Published private(set) var pendingPlan: WordAIValidatedPlan?
    @Published private(set) var isSending = false
    private var pendingFormClarification: (request: String, context: WordAIFormContext)?

    func send(
        catalogProvider: (String) -> WordAIRetrievalCatalog?,
        snapshotProvider: (
            String,
            WordAIRetrievalCatalog,
            WordAIRetrievalPlan?
        ) -> WordAIDocumentSnapshot?,
        documentDisplayName: String = "Word",
        applying apply: ((WordAIValidatedPlan) throws -> String)? = nil
    ) async {
        let inputRequest = input.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !inputRequest.isEmpty, !isSending else { return }
        let request = pendingFormClarification.flatMap {
            $0.context.continuing($0.request, with: inputRequest)
        } ?? inputRequest
        pendingFormClarification = nil
        let history = messages.suffix(8).compactMap { message in
            switch message.role {
            case .user:
                return WordAIChatTurn(role: "user", text: message.text)
            case .assistant:
                return WordAIChatTurn(role: "assistant", text: message.text)
            case .notice:
                return nil
            }
        }
        input = ""
        pendingPlan = nil
        messages.append(Message(role: .user, text: inputRequest))
        isSending = true
        defer { isSending = false }

        do {
            guard let catalog = catalogProvider(request) else {
                appendNotice(
                    "현재 \(documentDisplayName) 문서 구조를 읽을 수 없습니다."
                )
                return
            }
            var retrievalPlan: WordAIRetrievalPlan?
            if catalog.requiresRouting {
                let route = try await WordAICommandService.route(
                    userRequest: request,
                    catalog: catalog,
                    history: history
                )
                if route.intent == .clarify {
                    messages.append(
                        Message(
                            role: .assistant,
                            text: route.assistantMessage
                        )
                    )
                    return
                }
                retrievalPlan = route
            }
            guard let snapshot = snapshotProvider(
                request,
                catalog,
                retrievalPlan
            ) else {
                appendNotice(
                    "검색하는 동안 \(documentDisplayName) 문서가 변경되었거나 관련 구역을 구성하지 못했습니다. 다시 요청해 주세요."
                )
                return
            }
            let command = try await WordAICommandService.plan(
                userRequest: request,
                snapshot: snapshot,
                history: history
            )
            try Task.checkCancellation()
            try handle(
                command,
                snapshot: snapshot,
                userRequest: request,
                applying: apply
            )
        } catch is CancellationError {
            return
        } catch {
            appendNotice(
                AppLocalization.format(
                    "AI 요청을 처리하지 못했습니다. %@",
                    error.localizedDescription
                )
            )
        }
    }

    func handle(
        _ command: WordAICommandPlan,
        snapshot: WordAIDocumentSnapshot,
        userRequest: String,
        applying apply: ((WordAIValidatedPlan) throws -> String)? = nil
    ) throws {
        let validated = try WordAICommandValidator.validate(
            command,
            snapshot: snapshot,
            userRequest: userRequest
        )
        if let validated, let apply {
            do {
                let result = try apply(validated)
                messages.append(
                    Message(role: .assistant, text: command.assistantMessage)
                )
                appendNotice(result)
            } catch {
                appendNotice(error.localizedDescription)
            }
            return
        }

        messages.append(
            Message(role: .assistant, text: command.assistantMessage)
        )
        if command.intent == .clarify, let context = snapshot.formContext,
           context.resolution == .ambiguous || context.resolution == .unsupported {
            pendingFormClarification = (userRequest, context)
        }
        if let validated {
            pendingPlan = validated
            appendNotice(
                AppLocalization.format(
                    "%lld개 변경의 미리보기를 확인한 뒤 적용해 주세요.",
                    validated.changeCount
                )
            )
        }
    }

    func applyPending(
        using apply: (WordAIValidatedPlan) throws -> String
    ) {
        guard let pendingPlan else { return }
        do {
            let result = try apply(pendingPlan)
            self.pendingPlan = nil
            appendNotice(result)
        } catch {
            self.pendingPlan = nil
            appendNotice(error.localizedDescription)
        }
    }

    func cancelPending() {
        guard pendingPlan != nil else { return }
        pendingPlan = nil
        appendNotice(AppLocalization.string("AI 수정안을 취소했습니다."))
    }

    func appendVoiceError(_ error: Error) {
        appendNotice(
            AppLocalization.format(
                "음성 입력을 사용할 수 없습니다. %@",
                error.localizedDescription
            )
        )
    }

    private func appendNotice(_ text: String) {
        messages.append(Message(role: .notice, text: text))
    }
}

@MainActor
struct WordAIChatPanel: View {
    let isAvailable: Bool
    let catalogProvider: (String) -> WordAIRetrievalCatalog?
    let snapshotProvider: (
        String,
        WordAIRetrievalCatalog,
        WordAIRetrievalPlan?
    ) -> WordAIDocumentSnapshot?
    let onApply: (WordAIValidatedPlan) throws -> String
    var documentDisplayName = "Word"
    var showsHeader = true
    var allowsVoiceInput = false
    var appliesEditsAutomatically = false

    @StateObject private var chat = WordAIChatViewModel()
    @ObservedObject private var stt = STTManager.shared
    @State private var isExpanded = true
    @State private var speechTask: Task<Void, Never>?
    @State private var ownsVoiceRecording = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(VisionCraftUI.outline)
            if hasConversation {
                if showsHeader { header }
                if isExpanded {
                    conversation
                    if let plan = chat.pendingPlan {
                        proposal(plan)
                    }
                }
            }
            composer
            if hasConversation && isExpanded && showsHeader {
                Text(
                    appliesEditsAutomatically
                        ? "AI 명령 처리 시 현재 \(documentDisplayName) 문서의 일부 문단과 입력 내용이 Gemini로 전송됩니다. 수정안은 앱의 검증을 거쳐 바로 문서에 반영됩니다."
                        : "AI 명령 처리 시 현재 \(documentDisplayName) 문서의 일부 문단과 입력 내용이 Gemini로 전송됩니다. 수정안은 앱의 검증과 미리보기를 거쳐 사용자가 적용할 때만 문서에 반영됩니다."
                )
                .font(.caption2)
                .foregroundStyle(VisionCraftUI.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(VisionCraftUI.surface)
        .onDisappear {
            speechTask?.cancel()
            if ownsVoiceRecording {
                stt.cancelRecording()
                ownsVoiceRecording = false
            }
        }
        .onChange(of: chat.messages.count) { _, _ in
            guard let latest = chat.messages.last,
                  latest.role != .user,
                  UIAccessibility.isVoiceOverRunning else { return }
            UIAccessibility.post(
                notification: .announcement,
                argument: latest.text
            )
        }
    }

    private var hasConversation: Bool {
        !chat.messages.isEmpty || chat.isSending || chat.pendingPlan != nil
    }

    private var header: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(VisionCraftUI.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI \(documentDisplayName) 도우미")
                        .font(.headline)
                        .foregroundStyle(VisionCraftUI.primaryText)
                    Text("Gemini Flash · 문서 질문 및 안전한 수정 제안")
                        .font(.caption)
                        .foregroundStyle(VisionCraftUI.secondaryText)
                }
                Spacer()
                if chat.isSending {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(
                            "AI가 \(documentDisplayName) 문서를 분석하는 중"
                        )
                }
                Image(
                    systemName: isExpanded
                        ? "chevron.down"
                        : "chevron.up"
                )
                .foregroundStyle(VisionCraftUI.secondaryText)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("AI \(documentDisplayName) 도우미")
        .accessibilityValue(isExpanded ? "펼쳐짐" : "접힘")
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(chat.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .frame(minHeight: 54, maxHeight: 150)
            .onChange(of: chat.messages.count) { _, _ in
                guard let id = chat.messages.last?.id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private func messageBubble(
        _ message: WordAIChatViewModel.Message
    ) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(VisionCraftUI.primaryText)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    message.role == .user
                        ? VisionCraftUI.primary.opacity(0.16)
                        : VisionCraftUI.surfaceVariant,
                    in: RoundedRectangle(cornerRadius: 12)
                )
            if message.role != .user { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            message.role == .user
                ? "내 지시. \(message.text)"
                : message.role == .assistant
                    ? "AI 답변. \(message.text)"
                    : "안내. \(message.text)"
        )
    }

    private func proposal(_ plan: WordAIValidatedPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI 수정안 미리보기", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
                .foregroundStyle(VisionCraftUI.primaryText)
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(plan.previewLines.enumerated()), id: \.offset) {
                        _, line in
                        Text(line)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 110)
            HStack {
                Button("취소", role: .cancel) {
                    chat.cancelPending()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("수정안 적용") {
                    chat.applyPending(using: onApply)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(
            VisionCraftUI.primary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !showsHeader && hasConversation {
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .foregroundStyle(VisionCraftUI.secondaryText)
                        .frame(width: 44, height: 46)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "대화 접기" : "대화 펼치기")
            }

            TextField(
                "\(documentDisplayName) 수정 또는 질문을 입력하세요",
                text: $chat.input,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .visionCraftInputSurface()
            .lineLimit(1 ... 4)
            .submitLabel(.send)
            .focused($isInputFocused)
            .disabled(chat.isSending || chat.pendingPlan != nil || speechTask != nil)
            .onSubmit { send() }
            .accessibilityLabel(
                "AI에게 \(documentDisplayName) 수정 지시 또는 질문 입력"
            )

            if allowsVoiceInput { voiceInputButton }

            Button {
                send()
            } label: {
                Group {
                    if chat.isSending {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 46, height: 46)
                .background(
                    VisionCraftUI.primary,
                    in: RoundedRectangle(cornerRadius: 13)
                )
            }
            .buttonStyle(.plain)
            .disabled(
                chat.input.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                    || chat.isSending
                    || chat.pendingPlan != nil
                    || speechTask != nil
                    || !isAvailable
            )
            .accessibilityLabel("AI에게 전송")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var voiceInputButton: some View {
        Button {
            toggleVoiceInput()
        } label: {
            Group {
                if speechTask != nil && !stt.isRecording {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: ownsVoiceRecording ? "stop.fill" : "mic.fill")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 46, height: 46)
            .background(
                ownsVoiceRecording ? Color.red : VisionCraftUI.primary,
                in: RoundedRectangle(cornerRadius: 13)
            )
        }
        .buttonStyle(.plain)
        .disabled(
            chat.isSending || chat.pendingPlan != nil || !isAvailable
                || (stt.isRecording && !ownsVoiceRecording)
                || (speechTask != nil && !stt.isRecording)
        )
        .accessibilityLabel(ownsVoiceRecording ? "음성 입력 종료" : "음성 입력")
        .accessibilityHint("음성 입력이 끝나면 바로 질문을 전송합니다.")
        .accessibilityValue(
            ownsVoiceRecording ? "음성을 듣는 중입니다." : ""
        )
    }

    private func send() {
        guard isAvailable, !chat.isSending,
              chat.pendingPlan == nil, speechTask == nil else { return }
        isInputFocused = false
        isExpanded = true
        Task {
            await chat.send(
                catalogProvider: catalogProvider,
                snapshotProvider: snapshotProvider,
                documentDisplayName: documentDisplayName,
                applying: appliesEditsAutomatically ? onApply : nil
            )
        }
    }

    private func toggleVoiceInput() {
        if ownsVoiceRecording {
            stt.finishRecording()
            return
        }
        guard allowsVoiceInput, isAvailable, !chat.isSending,
              chat.pendingPlan == nil, speechTask == nil,
              !stt.isRecording else { return }
        isInputFocused = false
        speechTask = Task {
            defer {
                speechTask = nil
                ownsVoiceRecording = false
            }
            do {
                let stream = try await stt.startRecording(
                    requiresOnDeviceRecognition: true
                )
                ownsVoiceRecording = true
                for await recognizedText in stream {
                    try Task.checkCancellation()
                    let request = recognizedText.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    guard !request.isEmpty else { continue }
                    chat.input = request
                    isExpanded = true
                    await chat.send(
                        catalogProvider: catalogProvider,
                        snapshotProvider: snapshotProvider,
                        documentDisplayName: documentDisplayName,
                        applying: appliesEditsAutomatically ? onApply : nil
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                isExpanded = true
                chat.appendVoiceError(error)
            }
        }
    }
}
