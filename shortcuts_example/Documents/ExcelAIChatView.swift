import Combine
import SwiftUI
import UIKit

@MainActor
final class ExcelAIChatViewModel: ObservableObject {
    struct Message: Identifiable, Sendable {
        enum Role: Equatable, Sendable {
            case user
            case assistant
            case notice
        }

        let id = UUID()
        let role: Role
        let text: String
        var references: ExcelAIReferences? = nil
        var query: ExcelAIReadQuery? = nil
    }

    @Published var input = ""
    @Published private(set) var messages: [Message] = []
    @Published private(set) var isSending = false
    @Published private(set) var activeReferences: ExcelAIReferences?

    func send(
        snapshotProvider: (String) async throws -> ExcelAIWorkbookSnapshot?,
        applying apply: (ExcelAIValidatedPlan) throws -> String,
        applyingOperations: ((ExcelAIValidatedPlan) async throws -> ExcelAIWorkbookApplyResult)? = nil
    ) async {
        let request = input.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !request.isEmpty,
              !isSending else {
            return
        }

        let history = messages.suffix(8).compactMap { message in
            switch message.role {
            case .user:
                return ExcelAIChatTurn(role: "user", text: message.text)
            case .assistant:
                return ExcelAIChatTurn(role: "assistant", text: message.text, query: message.query)
            case .notice:
                return nil
            }
        }
        input = ""
        messages.append(Message(role: .user, text: request))
        isSending = true
        activeReferences = nil
        defer { isSending = false }

        do {
            guard let snapshot = try await snapshotProvider(request) else {
                appendNotice("현재 시트 정보를 읽을 수 없습니다.")
                return
            }
            let command = try await ExcelAICommandService.plan(
                userRequest: request,
                snapshot: snapshot,
                history: history
            )
            if command.intent == .answer, let query = command.query, query.operation != .none {
                guard let current = try await snapshotProvider(request), current.revision == snapshot.revision else {
                    throw ExcelAIReadQueryError.staleResult
                }
            }
            if !command.workbookOperations.isEmpty {
                guard let applyingOperations else { throw ExcelAICommandValidationError.invalidAction }
                try await handleOperations(command, snapshot: snapshot, userRequest: request, applying: applyingOperations)
            } else {
                try handle(command, snapshot: snapshot, userRequest: request, applying: apply)
            }
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

    func handleOperations(
        _ command: ExcelAICommandPlan,
        snapshot: ExcelAIWorkbookSnapshot,
        userRequest: String,
        applying: (ExcelAIValidatedPlan) async throws -> ExcelAIWorkbookApplyResult
    ) async throws {
        activeReferences = nil
        guard let plan = try ExcelAICommandValidator.validate(command, snapshot: snapshot, userRequest: userRequest),
              !plan.workbookOperations.isEmpty else { throw ExcelAICommandValidationError.invalidResponse }
        let result = try await applying(plan)
        messages.append(Message(role: .assistant, text: result.message, references: result.references))
        activeReferences = result.references
    }

    func handle(
        _ command: ExcelAICommandPlan,
        snapshot: ExcelAIWorkbookSnapshot,
        userRequest: String = "",
        applying apply: (ExcelAIValidatedPlan) throws -> String
    ) throws {
        activeReferences = nil
        let validated = try ExcelAICommandValidator.validate(
            command,
            snapshot: snapshot,
            userRequest: userRequest
        )
        guard let validated else {
            if command.intent == .answer, var query = command.query, query.operation != .none,
               let result = try ExcelAIReadQueryExecutor.execute(query, snapshot: snapshot) {
                if let rowsBySheet = result.scopeRowsBySheet {
                    query.workbookResultScope = .init(revision: snapshot.revision, rowsBySheet: rowsBySheet)
                } else {
                    query.resultScope = .init(revision: snapshot.revision, rows: result.scopeRows ?? result.rows)
                }
                messages.append(Message(role: .assistant, text: result.answer, references: result.references, query: query))
                activeReferences = result.references
                return
            }
            let text = try ExcelAIReferences.answerText(command: command, snapshot: snapshot, userRequest: userRequest)
            let references = ExcelAIReferences.resolve(command: command, snapshot: snapshot, userRequest: userRequest)
            let query = command.query.flatMap { $0.operation == .none ? nil : $0 }
            let countQuery = ExcelAIReferences.countGroup(
                command: command,
                snapshot: snapshot,
                userRequest: userRequest
            ).map { group in
                var query = ExcelAIReadQuery(
                    operation: .count,
                    regionID: group.regionID,
                    match: .all,
                    filters: [.init(
                        column: group.column,
                        comparison: .equals,
                        valueType: .text,
                        value: group.value
                    )],
                    selectColumns: []
                )
                if let result = try? ExcelAIReadQueryExecutor.execute(
                    query,
                    snapshot: snapshot
                ) {
                    query.resultScope = .init(
                        revision: snapshot.revision,
                        rows: result.scopeRows ?? result.rows
                    )
                }
                return query
            }
            messages.append(
                Message(
                    role: .assistant,
                    text: text,
                    references: references,
                    query: query ?? countQuery
                )
            )
            activeReferences = references
            return
        }

        do {
            // The status bar carries the generic "applied N" result; the
            // chat keeps only the AI's description of what it did.
            _ = try apply(validated)
            let references = ExcelAIReferences.resolve(
                command: command, snapshot: snapshot, appliedPlan: validated
            )
            messages.append(
                Message(
                    role: .assistant,
                    text: command.assistantMessage,
                    references: references
                )
            )
            activeReferences = references
        } catch {
            appendNotice(error.localizedDescription)
        }
    }

    func appendVoiceError(_ error: Error) {
        appendNotice(
            AppLocalization.format(
                "음성 입력을 사용할 수 없습니다. %@",
                error.localizedDescription
            )
        )
    }

    /// The reply to read aloud for the latest request: the AI's own work
    /// description, not the generic "applied N changes" notice.
    var spokenResponse: Message? {
        guard let last = messages.last, last.role != .user else { return nil }
        if last.role == .notice, messages.count > 1,
           messages[messages.count - 2].role == .assistant {
            return messages[messages.count - 2]
        }
        return last
    }

    private func appendNotice(_ text: String) {
        messages.append(Message(role: .notice, text: text))
    }
}

@MainActor
struct ExcelAIChatPanel: View {
    let isAvailable: Bool
    let isLargeWorkbook: Bool
    let snapshotProvider:
        (String) async throws -> ExcelAIWorkbookSnapshot?
    let onApply: (ExcelAIValidatedPlan) throws -> String
    var onApplyOperations: ((ExcelAIValidatedPlan) async throws -> ExcelAIWorkbookApplyResult)? = nil
    var onReferencesChanged: (ExcelAIReferences?) -> Void = { _ in }

    @StateObject private var chat = ExcelAIChatViewModel()
    @StateObject private var answerSpeech = ChatAnswerSpeechController()
    @ObservedObject private var stt = STTManager.shared
    @State private var isExpanded = true
    @State private var speechTask: Task<Void, Never>?
    @State private var responsePlaybackTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(VisionCraftUI.outline)
            if hasConversation {
                header
                if isExpanded {
                    conversation
                }
            }
            composer
        }
        .background(VisionCraftUI.surface)
        .onChange(of: chat.activeReferences) { _, references in
            onReferencesChanged(references)
        }
        .onDisappear {
            speechTask?.cancel()
            speechTask = nil
            stopResponsePlayback()
            stt.cancelRecording()
        }
        .onChange(of: chat.messages.count) { _, _ in
            guard let latest = chat.spokenResponse,
                  UIAccessibility.isVoiceOverRunning else {
                return
            }
            UIAccessibility.post(
                notification: .announcement,
                argument: latest.text
            )
        }
    }

    private var hasConversation: Bool {
        !chat.messages.isEmpty
            || chat.isSending
    }

    private var header: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Spacer()
                if chat.isSending {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("AI가 문서를 분석하는 중")
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
            .frame(minHeight: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isExpanded ? "채팅 내용 접기" : "채팅 내용 펼치기"
        )
        .accessibilityValue(isExpanded ? "펼쳐짐" : "접힘")
        .accessibilityHint(
            isExpanded
                ? "두 번 탭하면 채팅창을 접습니다."
                : "두 번 탭하면 채팅창을 펼칩니다."
        )
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .frame(minHeight: 54, maxHeight: 140)
            .onChange(of: chat.messages.count) { _, _ in
                guard let messageID = chat.messages.last?.id else {
                    return
                }
                withAnimation {
                    proxy.scrollTo(messageID, anchor: .bottom)
                }
            }
        }
    }

    private func messageBubble(
        _ message: ExcelAIChatViewModel.Message
    ) -> some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 40)
            }
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(VisionCraftUI.primaryText)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    message.role == .user
                        ? VisionCraftUI.primary.opacity(0.16)
                        : VisionCraftUI.surfaceVariant,
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )
            if message.role != .user {
                Spacer(minLength: 40)
            }
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

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(
                isLargeWorkbook
                    ? "대용량 시트에서 검색하거나 질문하세요"
                    : "엑셀 수정 또는 질문을 입력하세요",
                text: $chat.input,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .visionCraftInputSurface()
            .lineLimit(1 ... 4)
            .submitLabel(.send)
            .focused($isInputFocused)
            .disabled(chat.isSending || stt.isRecording)
            .onSubmit {
                send()
            }
            .accessibilityLabel(
                isLargeWorkbook
                    ? "AI에게 대용량 시트 검색 또는 질문 입력"
                    : "AI에게 엑셀 수정 지시 또는 질문 입력"
            )
            .accessibilityHint(
                isLargeWorkbook
                    ? "전체 시트에서 관련 행을 찾아 AI가 답합니다. AI 수정은 사용할 수 없습니다."
                    : "열린 시트의 정식 표와 머리글이 있는 일반 셀 범위를 기준으로 말합니다. 명확한 수정은 안전 검증 후 바로 반영되고, 대상이 불명확하면 다시 묻습니다."
            )

            Button {
                toggleVoiceInput()
            } label: {
                Image(
                    systemName: stt.isRecording
                        ? "stop.fill"
                        : "mic.fill"
                )
                .font(.body.weight(.bold))
                .foregroundStyle(stt.isRecording ? Color.white : VisionCraftUI.onAccent)
                .frame(width: 52, height: 52)
                .background(
                    stt.isRecording ? Color.red : VisionCraftUI.accent,
                    in: RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(chat.isSending || !isAvailable)
            .accessibilityLabel(
                stt.isRecording ? "음성 입력 종료" : "음성으로 지시"
            )

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(VisionCraftUI.onAccent)
                    .frame(width: 52, height: 52)
                    .background(
                        VisionCraftUI.accent,
                        in: RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(
                chat.input.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                    || chat.isSending
                    || stt.isRecording
                    || !isAvailable
            )
            .accessibilityLabel("AI에게 전송")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func send() {
        guard !chat.isSending else {
            return
        }
        stopResponsePlayback()
        isInputFocused = false
        Task {
            await chat.send(
                snapshotProvider: snapshotProvider,
                applying: onApply,
                applyingOperations: onApplyOperations
            )
        }
    }

    private func toggleVoiceInput() {
        if stt.isRecording {
            stt.finishRecording()
            return
        }
        if let speechTask {
            speechTask.cancel()
            self.speechTask = nil
            stt.cancelRecording()
            return
        }
        stopResponsePlayback()
        speechTask = Task {
            defer { speechTask = nil }
            do {
                let stream = try await stt.startRecording(
                    requiresOnDeviceRecognition: true
                )
                for await recognizedText in stream {
                    try Task.checkCancellation()
                    let request = recognizedText.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    guard !request.isEmpty else {
                        continue
                    }
                    chat.input = request
                    let previousMessageCount = chat.messages.count
                    await chat.send(
                        snapshotProvider: snapshotProvider,
                        applying: onApply,
                        applyingOperations: onApplyOperations
                    )
                    guard !Task.isCancelled,
                          chat.messages.count > previousMessageCount,
                          let response = chat.spokenResponse else {
                        continue
                    }
                    playVoiceResponse(response)
                }
            } catch is CancellationError {
                return
            } catch {
                chat.appendVoiceError(error)
            }
        }
    }

    private func playVoiceResponse(_ response: ExcelAIChatViewModel.Message) {
        stopResponsePlayback()
        responsePlaybackTask = Task {
            // A brief cue marks the result before the spoken chat message.
            SoundEffectManager.shared.play(.popUp2, volume: 0.35)
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled,
                  !UIAccessibility.isVoiceOverRunning,
                  AppSettingsStore.shared.voiceFeedbackEnabled else {
                return
            }
            _ = answerSpeech.play(
                messageID: response.id,
                text: response.text
            )
        }
    }

    private func stopResponsePlayback() {
        responsePlaybackTask?.cancel()
        responsePlaybackTask = nil
        if answerSpeech.isSpeaking {
            answerSpeech.stop()
        }
    }
}
