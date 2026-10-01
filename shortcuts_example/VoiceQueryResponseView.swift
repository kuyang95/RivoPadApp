//
//  VoiceQueryResponseView.swift
//  shortcuts_example
//
//  Android `ai/voice/VoiceQueryScreen.kt` + `VoiceQueryViewModel.kt`:
//  the dedicated voice question screen opened from sharing in 음성 mode.
//

import SwiftUI
import AVFoundation
import Combine
import CoreImage

/// Android `ShareDataType` → receive notice ("PDF 수신", "이미지 수신" …).
enum VoiceQueryReceiptKind: Equatable {
    case web
    case pdf
    case excel
    case hwp
    case text
    case document
    case image

    var label: String {
        switch self {
        case .web:
            return AppLocalization.string("웹 수신")
        case .pdf:
            return AppLocalization.string("PDF 수신")
        case .excel:
            return AppLocalization.string("엑셀 수신")
        case .hwp:
            return AppLocalization.string("한글 수신")
        case .text:
            return AppLocalization.string("텍스트 수신")
        case .document:
            return AppLocalization.string("문서 수신")
        case .image:
            return AppLocalization.string("이미지 수신")
        }
    }

    static func forFileName(_ name: String) -> VoiceQueryReceiptKind {
        switch (name as NSString).pathExtension.lowercased() {
        case "pdf":
            return .pdf
        case "xls", "xlsx":
            return .excel
        case "hwp", "hwpx":
            return .hwp
        case "txt", "text":
            return .text
        default:
            return .document
        }
    }
}

enum QuerySource {
    case text(String, kind: VoiceQueryReceiptKind = .document)
    case image(UIImage)
    /// A file imported by the share inbox. The screen reads its extracted
    /// text (or image) and removes the stored copy when it closes.
    case attachment(StoredChatFileAttachment)
}

/// Android `VoicePhase`.
private enum VoicePhase {
    case intake, ready, listening, thinking, answering, done, error
}

// MARK: - Message Model

struct Message: Identifiable {
    let id = UUID()
    var text: String?
    let image: UIImage?
    let isMe: Bool
}

// MARK: - Colors (Android VoiceQueryColors.kt)

/// 다크는 검정 바탕 + 흰 글자, 라이트는 홈 soft UI 와 같은 흰 바탕 + 남색 글자.
struct VoiceQueryColors {
    let backgroundTop: Color
    let backgroundBottom: Color
    let text: Color
    let secondaryText: Color
    let bubbleFill: Color
    let bubbleBorder: Color

    static func resolve(isDark: Bool) -> VoiceQueryColors {
        if isDark {
            return VoiceQueryColors(
                backgroundTop: .black,
                backgroundBottom: VisionCraftUI.fixedColor(0x14141A),
                text: .white,
                secondaryText: .white.opacity(0.76),
                bubbleFill: .white.opacity(0.08),
                bubbleBorder: .white.opacity(0.2)
            )
        }
        return VoiceQueryColors(
            backgroundTop: .white,
            backgroundBottom: VisionCraftUI.fixedColor(0xF2F4F8),
            text: VisionCraftUI.fixedColor(0x283546),
            secondaryText: VisionCraftUI.fixedColor(0x536176),
            bubbleFill: VisionCraftUI.fixedColor(0x283546).opacity(0.06),
            bubbleBorder: VisionCraftUI.fixedColor(0x536176).opacity(0.35)
        )
    }
}

// MARK: - Chat Bubble (Android VoiceChatBubble)

struct ChatBubble: View {
    let text: String
    let colors: VoiceQueryColors

    var body: some View {
        Text(text)
            .visionCraftAndroidText(16)
            .lineSpacing(6)
            .foregroundStyle(colors.text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(colors.bubbleFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(colors.bubbleBorder, lineWidth: 0.8)
            )
    }
}

// MARK: - Message Row (Android VoiceMessageRow)

private struct MessageRow: View {
    let message: Message
    let colors: VoiceQueryColors
    let availableWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.isMe {
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 8) {
                    attachedImage(cornerRadius: 14)
                    if let text = message.text {
                        ChatBubble(text: text, colors: colors)
                    }
                }
                .frame(
                    maxWidth: availableWidth * 0.7,
                    alignment: .trailing
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    attachedImage(cornerRadius: 12)
                    if let text = message.text {
                        Text(text)
                            .visionCraftAndroidText(16)
                            .lineSpacing(8)
                            .foregroundStyle(colors.text.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(
                    maxWidth: availableWidth * 0.85,
                    alignment: .leading
                )
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            AppLocalization.format(
                "%@: %@",
                AppLocalization.string(message.isMe ? "나" : "비크"),
                message.text ?? AppLocalization.string("첨부 이미지")
            )
        )
    }

    @ViewBuilder
    private func attachedImage(cornerRadius: CGFloat) -> some View {
        if let image = message.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 360)
                .clipShape(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Sentence-by-sentence answer speech

/// Android `TTSManager.speak` + `speakQueued`: the first sentence interrupts
/// the "답변 생성중" cue, later sentences wait their turn.
@MainActor
private final class VoiceAnswerSpeaker: ObservableObject {
    private var queue: [String] = []
    private var isSpeaking = false

    func speakInterrupting(_ text: String) {
        queue.removeAll()
        isSpeaking = true
        TTSManager.shared.speak(text) { [weak self] in
            self?.advance()
        }
    }

    func speakQueued(_ text: String) {
        guard isSpeaking else {
            speakInterrupting(text)
            return
        }
        queue.append(text)
    }

    func stop() {
        queue.removeAll()
        isSpeaking = false
        TTSManager.shared.stop()
    }

    private func advance() {
        guard !queue.isEmpty else {
            isSpeaking = false
            return
        }
        let next = queue.removeFirst()
        TTSManager.shared.speak(next) { [weak self] in
            self?.advance()
        }
    }
}

/// Android `VoiceQueryViewModel.findSentenceBoundary` / `stripMarkdownForTts`.
nonisolated enum VoiceAnswerSpeechText {
    static func sentenceBoundary(in text: String) -> String.Index? {
        let enders: Set<Character> = [".", "!", "?", "。", "！", "？", "\n"]
        guard let last = text.lastIndex(where: { enders.contains($0) }) else {
            return nil
        }
        return text.index(after: last)
    }

    static func strippingMarkdown(_ text: String) -> String {
        let rules: [(String, String)] = [
            ("```[\\s\\S]*?```", " "),
            ("`([^`]+)`", "$1"),
            ("\\*\\*|__", ""),
            ("(?<!\\*)\\*(?!\\*)|(?<!_)_(?!_)", ""),
            ("(?m)^#{1,6}\\s*", ""),
            ("(?m)^\\s*[-*+]\\s+", ""),
            ("\\[([^\\]]+)\\]\\([^\\)]+\\)", "$1"),
        ]
        var result = text
        for (pattern, template) in rules {
            result = result.replacingOccurrences(
                of: pattern,
                with: template,
                options: .regularExpression
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Screen

struct VoiceQueryResponseView: View {

    let source: QuerySource

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var stt = STTManager.shared
    @StateObject private var speaker = VoiceAnswerSpeaker()

    @State private var messages: [Message] = []
    @State private var phase: VoicePhase = .intake
    @State private var document: String?
    @State private var imageBitmap: UIImage?
    @State private var didStart = false
    @State private var sttTask: Task<Void, Never>?
    @State private var streamTask: Task<Void, Never>?
    @State private var modelTask: Task<Void, Error>?
    @State private var conversationID = LLMConversationID()

    private var colors: VoiceQueryColors {
        VoiceQueryColors.resolve(isDark: colorScheme == .dark)
    }

    private var systemPromptLLM: String {
        """
        너는 \(responseLanguageName)로 간결하게 답하는 도우미야.
        유저가 "Document:" 뒤에 제공하는 내용은 참고할 내용이고,
        "Question:" 뒤의 질문에 참고 내용을 근거로 답해.
        참고에 없는 내용은 추측하지 말고 모른다고 말해.
        """
    }

    private var systemPromptVLM: String {
        """
        너는 이미지와 질문을 함께 분석하는 \(responseLanguageName) 도우미야.
        이미지에 보이는 정보와 사용자의 질문을 기반으로 간결하게 답해.
        확실하지 않으면 추측하지 말고 모른다고 말해.
        """
    }

    private var responseLanguageName: String {
        AppLanguage.current()
            .localAIResponseLanguageName
    }

    /// Android: the mic reappears once nothing is being listened to or
    /// generated, so the user can ask again.
    private var showsMicButton: Bool {
        guard !stt.isRecording else { return false }
        switch phase {
        case .ready, .done, .error:
            return true
        case .intake, .listening, .thinking, .answering:
            return false
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [colors.backgroundTop, colors.backgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(messages) { message in
                                MessageRow(
                                    message: message,
                                    colors: colors,
                                    availableWidth: max(geometry.size.width - 40, 0)
                                )
                                .id(message.id)
                            }
                        }
                        .padding(.top, 80)
                        .padding(.bottom, 136)
                        .padding(.horizontal, 20)
                    }
                    .onChange(of: messages.count) { _, _ in
                        guard let last = messages.last else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            if stt.isRecording {
                AuroraListeningOverlay(amplitude: stt.amplitude)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(10)
            }

            // Android: close button top-right.
            VStack {
                HStack {
                    Spacer()
                    VisionCraftIconButton(
                        systemImage: "xmark",
                        label: "닫기",
                        tint: colors.text
                    ) {
                        dismiss()
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                Spacer()
            }
            .zIndex(20)

            // Android: 72dp mic "다시 말하기" restarts listening.
            if showsMicButton {
                VStack {
                    Spacer()
                    Button {
                        startListening()
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(VisionCraftUI.onAccent)
                            .frame(width: 72, height: 72)
                            .background(Circle().fill(VisionCraftUI.accent))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppLocalization.string("다시 말하기"))
                    .padding(.bottom, 40)
                }
                .zIndex(20)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .visionCraftHandlesBackNavigation()
        .task {
            guard !didStart else { return }
            didStart = true
            await handleSource()
        }
        .onDisappear {
            sttTask?.cancel()
            sttTask = nil
            streamTask?.cancel()
            streamTask = nil
            modelTask?.cancel()
            modelTask = nil
            stt.cancelRecording()
            speaker.stop()
            let id = conversationID
            let attachment: StoredChatFileAttachment?
            if case .attachment(let stored) = source {
                attachment = stored
            } else {
                attachment = nil
            }
            Task {
                await LLMService.shared.resetConversation(id)
                if let attachment {
                    // The share inbox handed the file to this screen only;
                    // nothing else keeps it, so the copy goes with the screen.
                    await ChatAttachmentStore.shared.delete(attachment)
                }
            }
        }
    }

    // MARK: - Intake (Android handleShareIntent)

    @MainActor
    private func handleSource() async {
        switch source {
        case .image(let image):
            receiveImage(image)

        case .text(let text, let kind):
            addMessage(AppLocalization.string("문서 읽는 중…"))
            receiveDocument(text, kind: kind)

        case .attachment(let attachment):
            addMessage(AppLocalization.string("문서 읽는 중…"))
            if attachment.kind == .image {
                do {
                    let image = try await ChatAttachmentStore.shared
                        .loadImage(for: attachment)
                    messages.removeLast()
                    receiveImage(image)
                } catch {
                    failIntake()
                }
                return
            }
            let text = attachment.extractedText?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else {
                failIntake()
                return
            }
            receiveDocument(
                text,
                kind: .forFileName(attachment.name)
            )
        }
    }

    private func receiveImage(_ image: UIImage) {
        imageBitmap = image
        document = nil
        messages.append(Message(text: nil, image: image, isMe: false))
        addMessage(VoiceQueryReceiptKind.image.label)
        phase = .ready
        startListening()
    }

    private func receiveDocument(_ text: String, kind: VoiceQueryReceiptKind) {
        document = text
        imageBitmap = nil
        RVLogger.d("VoiceShare: document length=\(text.count)")
        replaceLast(kind.label)
        prepareLocalModelIfNeeded()
        phase = .ready
        startListening()
    }

    private func failIntake() {
        replaceLast(AppLocalization.string("데이터를 처리하는데 실패했습니다."))
        SoundEffectManager.shared.play(.fail)
        phase = .error
    }

    /// Documents are answered by the on-device model; it warms up while the
    /// user is still speaking so the first answer does not wait for it.
    private func prepareLocalModelIfNeeded() {
        guard modelTask == nil else { return }
        modelTask = Task {
            try await LLMService.shared.activateModel(.preferredTextModel)
        }
    }

    // MARK: - Messages

    @discardableResult
    private func addMessage(
        _ text: String?,
        image: UIImage? = nil,
        isMe: Bool = false
    ) -> UUID {
        let message = Message(text: text, image: image, isMe: isMe)
        messages.append(message)
        return message.id
    }

    private func updateMessage(_ id: UUID, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return
        }
        messages[index].text = text
    }

    private func replaceLast(_ text: String) {
        guard !messages.isEmpty else {
            addMessage(text)
            return
        }
        messages[messages.count - 1].text = text
    }

    // MARK: - Listening (Android startListening)

    private func startListening() {
        switch phase {
        case .listening, .thinking, .answering:
            return
        case .intake, .ready, .done, .error:
            break
        }
        guard sttTask == nil else { return }
        speaker.stop()
        phase = .listening

        sttTask = Task {
            defer { sttTask = nil }
            do {
                let stream = try await stt.startRecording(
                    startEffect: .recording
                )
                var spoken: String?
                for await text in stream {
                    try Task.checkCancellation()
                    let trimmed = text.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    if !trimmed.isEmpty {
                        spoken = trimmed
                    }
                }
                guard let spoken else {
                    // Android showSpeechRecognitionErrorToast: failure sound
                    // already played, show the reason and let them retry.
                    if let failure = stt.consumeLastFailure() {
                        addMessage(failure.message)
                    }
                    phase = .ready
                    return
                }
                addMessage(spoken, isMe: true)
                runAnswer(question: spoken)
            } catch is CancellationError {
                return
            } catch {
                _ = stt.consumeLastFailure()
                addMessage(error.localizedDescription)
                phase = .ready
            }
        }
    }

    // MARK: - Answer streaming (Android runGemini)

    private func runAnswer(question: String) {
        streamTask?.cancel()
        phase = .thinking
        let answerID = addMessage(AppLocalization.string("답변 생성중…"))

        SoundEffectManager.shared.play(.startingLLM)
        TTSManager.shared.speakFeedback(AppLocalization.string("답변 생성중"))

        streamTask = Task {
            defer { streamTask = nil }
            let usesCloud = imageBitmap != nil
            do {
                let stream = try await makeAnswerStream(question: question)
                var thinkFilter = StreamingThinkFilter()
                var answer = ""
                var spokenCount = 0
                var received = false
                var isFirstSentence = true

                @MainActor
                func speakPending(final: Bool) {
                    let unspoken = String(answer.dropFirst(spokenCount))
                    let boundary: String.Index?
                    if final {
                        boundary = unspoken.endIndex
                    } else {
                        boundary = VoiceAnswerSpeechText.sentenceBoundary(in: unspoken)
                    }
                    guard let boundary, boundary > unspoken.startIndex else {
                        return
                    }
                    let sentence = VoiceAnswerSpeechText.strippingMarkdown(
                        String(unspoken[..<boundary])
                    )
                    if !sentence.isEmpty {
                        if isFirstSentence {
                            speaker.speakInterrupting(sentence)
                            isFirstSentence = false
                        } else {
                            speaker.speakQueued(sentence)
                        }
                    }
                    spokenCount += unspoken.distance(
                        from: unspoken.startIndex,
                        to: boundary
                    )
                }

                for try await chunk in stream {
                    try Task.checkCancellation()
                    let visible = usesCloud ? chunk : thinkFilter.consume(chunk)
                    guard !visible.isEmpty else { continue }
                    if !received {
                        received = true
                        phase = .answering
                    }
                    answer += visible
                    updateMessage(answerID, text: answer)
                    await speakPending(final: false)
                }
                if !usesCloud {
                    let tail = thinkFilter.finish()
                    if !tail.isEmpty {
                        answer += tail
                        updateMessage(answerID, text: answer)
                    }
                }
                guard received, !answer.isEmpty else {
                    updateMessage(
                        answerID,
                        text: AppLocalization.string("데이터를 처리하는데 실패했습니다.")
                    )
                    phase = .error
                    return
                }
                await speakPending(final: true)
                SoundEffectManager.shared.play(.complete)
                phase = .done
            } catch is CancellationError {
                return
            } catch {
                RVLogger.d("VoiceQuery answer failed: \(error)")
                updateMessage(
                    answerID,
                    text: Self.failureText(for: error, usesCloud: usesCloud)
                )
                SoundEffectManager.shared.play(.fail)
                phase = .error
            }
        }
    }

    private func makeAnswerStream(
        question: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        if let image = imageBitmap {
            guard let ciImage = CIImage(image: image)
                ?? image.cgImage.map({ CIImage(cgImage: $0) }) else {
                throw GeminiVisionService.ServiceError.imageEncodingFailed
            }
            return try await GeminiVisionService.stream(
                system: systemPromptVLM,
                prompt: question,
                images: [ciImage]
            )
        }
        guard let document else {
            throw CocoaError(.fileNoSuchFile)
        }
        prepareLocalModelIfNeeded()
        do {
            try await modelTask?.value
        } catch {
            // Failed tasks keep throwing their original error. Allow the
            // next spoken question to start a fresh model preparation.
            modelTask = nil
            throw error
        }
        try Task.checkCancellation()
        let prompt = """
        Document:
        \(document)

        Question:
        \(question)
        """
        return try await LLMService.shared.streamText(
            conversationID: conversationID,
            system: systemPromptLLM,
            prompt: prompt
        )
    }

    /// Android: quota → "일일 할당량이 소진되었습니다.", anything else from the
    /// cloud → "인터넷 연결이 좋지 않습니다". The on-device model has no
    /// network to blame, so its errors keep their own description.
    private static func failureText(
        for error: Error,
        usesCloud: Bool
    ) -> String {
        if error is CloudAITokenBudgetError {
            return AppLocalization.string("일일 할당량이 소진되었습니다.")
        }
        let description = error.localizedDescription.lowercased()
        if description.contains("quota")
            || description.contains("resource_exhausted")
            || description.contains("429") {
            return AppLocalization.string("일일 할당량이 소진되었습니다.")
        }
        if usesCloud {
            return AppLocalization.string("인터넷 연결이 좋지 않습니다")
        }
        return AppLocalization.format(
            "답변 생성 실패: %@",
            error.localizedDescription
        )
    }
}
