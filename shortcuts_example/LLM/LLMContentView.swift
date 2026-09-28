import SwiftUI
import CoreImage
import PhotosUI
import UniformTypeIdentifiers
import UIKit

enum ChatIntentInput: Equatable {
    case textChat(conversationID: UUID?)
    case voiceQuestion(question: String)
    case sharedTextQuestion(
        text: String,
        automaticallyStartsVoiceInput:
            Bool
    )
    case sharedAttachmentQuestion(
        attachment:
            StoredChatFileAttachment,
        automaticallyStartsVoiceInput:
            Bool
    )
    case imageAnalysis(imageURL: URL, question: String)
    case capturedImageAnalysis(
        image: UIImage,
        question: String
    )
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

private extension ChatIntentInput {
    var initialFileAttachment:
        StoredChatFileAttachment?
    {
        guard case .sharedAttachmentQuestion(
            let attachment,
            _
        ) = self else {
            return nil
        }
        return attachment
    }

    var automaticallyStartsSharedVoiceInput:
        Bool
    {
        switch self {
        case .sharedTextQuestion(
            _,
            let automaticallyStarts
        ),
             .sharedAttachmentQuestion(
                _,
                let automaticallyStarts
             ):
            return automaticallyStarts
        case .textChat,
             .voiceQuestion,
             .imageAnalysis,
             .capturedImageAnalysis,
             .documentQA,
             .webPageQA,
             .webSearchQA:
            return false
        }
    }

    var requiresLocalModel: Bool {
        if case .webSearchQA = self {
            return false
        }
        return true
    }
}

struct LLMContentView: View {
    let intent: ChatIntentInput
    @StateObject private var vm: ChatViewModel
    @ObservedObject private var localAI:
        LLMService
    @StateObject private var answerSpeech =
        ChatAnswerSpeechController()
    @ObservedObject private var stt = STTManager.shared
    @EnvironmentObject private var remoteControl:
        RivoScreenRemoteControlCenter
    @Environment(\.dismiss) private var dismiss

    @State private var didStart = false
    @State private var welcomeMessageID = UUID()
    @State private var speechTask: Task<Void, Never>?
    @State private var voiceErrorDescription: String?
    @State private var shouldSpeakNextResponse = false
    @State private var isAttachmentMenuPresented =
        false
    @State private var isDocumentImporterPresented =
        false
    @State private var isPhotoPickerPresented =
        false
    @State private var selectedPhotoItem:
        PhotosPickerItem?

    init(intent: ChatIntentInput) {
        self.intent = intent
        let service = LLMService.shared
        _localAI = ObservedObject(
            wrappedValue: service
        )
        let storedConversationID: UUID
        let persistsHistory: Bool
        switch intent {
        case .textChat(let conversationID):
            storedConversationID = conversationID ?? UUID()
            persistsHistory = true
        case .voiceQuestion:
            storedConversationID = UUID()
            persistsHistory = true
        case .sharedTextQuestion:
            storedConversationID = UUID()
            persistsHistory = true
        case .sharedAttachmentQuestion:
            storedConversationID = UUID()
            persistsHistory = true
        case .imageAnalysis,
             .capturedImageAnalysis,
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
                persistsHistory:
                    persistsHistory,
                initialFileAttachment:
                    intent
                    .initialFileAttachment
            )
        )
        _shouldSpeakNextResponse = State(
            initialValue: {
                if case .voiceQuestion = intent {
                    return true
                }
                if case .capturedImageAnalysis =
                    intent {
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
        case .capturedImageAnalysis(
            _,
            let question
        ):
            RVLogger.d(
                "🔥 카메라 이미지 설명 질문: \(question)"
            )
        case .textChat,
             .voiceQuestion,
             .sharedTextQuestion,
             .sharedAttachmentQuestion,
             .documentQA,
             .webPageQA,
             .webSearchQA:
            break
        }
    }

    var body: some View {
        ZStack {
            VisionCraftUI.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if let source = webSource {
                    webSourceBanner(source)
                }
                if let response =
                        webSearchResponse {
                    webSearchSourceBanner(
                        response
                    )
                }
                if let summary =
                        vm.attachmentSummary {
                    attachmentBanner(summary)
                }

                if vm.messages.isEmpty, !vm.isLoadingModel, !showsWelcomeMessage {
                    ContentUnavailableView(
                        "새로운 대화",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text(
                            "AI에게 질문해 보세요"
                        )
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        Group {
                            if showsWelcomeMessage {
                                MessageRow(welcomeMessage) {
                                    _ = answerSpeech.play(
                                        messageID: welcomeMessageID,
                                        text: welcomeMessage.text
                                    )
                                }
                                .accessibilityIdentifier("local-chat-welcome")
                            }

                            ForEach(vm.messages) { message in
                                MessageRow(
                                    message,
                                    isGenerating: vm.isGenerating
                                ) {
                                    _ = answerSpeech.play(
                                        messageID: message.id,
                                        text: message.text
                                    )
                                }
                            }
                        }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(
                                .init(
                                    top: 0,
                                    leading: 0,
                                    bottom: 0,
                                    trailing: 0
                                )
                            )
                    }
                    .listStyle(.plain)
                    .listRowSpacing(0)
                    .environment(\.defaultMinListRowHeight, 0)
                    .contentMargins(.top, 20, for: .scrollContent)
                    .contentMargins(.bottom, 12, for: .scrollContent)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .defaultScrollAnchor(.bottom)
                }

                if allowsFollowUpInput {
                    quickPromptBar
                }

                if let error = voiceErrorDescription
                    ?? vm.attachmentErrorDescription
                    ?? vm.historyErrorDescription {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .accessibilityLabel(
                            AppLocalization.format(
                                "오류: %@",
                                error
                            )
                        )
                } else if stt.isRecording {
                    Text("듣는 중… 마이크 버튼을 다시 누르면 종료됩니다.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .accessibilityLabel("음성을 듣는 중입니다.")
                } else if vm.isPreparingAttachment,
                          let attachmentStatus =
                            vm.attachmentStatusDescription {
                    Text(attachmentStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .accessibilityLabel(
                            attachmentStatus
                        )
                } else if let status = visibleStatusDescription {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .accessibilityLabel(
                            AppLocalization.format(
                                "AI 상태: %@",
                                status
                            )
                        )
                }

                if let contextNotice =
                        vm
                        .contextNoticeDescription {
                    Label(
                        contextNotice,
                        systemImage:
                            "text.badge.checkmark"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                    .padding(.horizontal, 12)
                }

                if allowsFollowUpInput {
                    HStack(
                        alignment: .bottom,
                        spacing: 12
                    ) {
                        TextField(
                            "메시지를 입력하세요",
                            text: $vm.input,
                            axis: .vertical
                        )
                            .textFieldStyle(.plain)
                            .font(.callout)
                            .foregroundStyle(VisionCraftUI.primaryText)
                            .visionCraftChatInputSurface()
                            .lineLimit(1 ... 6)
                            .disabled(
                                vm.isLoadingModel
                                    || vm.isInitialQueryRunning
                                    || vm.isGenerating
                                    || vm.isPreparingAttachment
                                    || stt.isRecording
                            )
                            .submitLabel(.send)
                            .onSubmit {
                                sendTypedMessage()
                            }
                            .accessibilityIdentifier("local-chat-input")

                        Button {
                            if answerSpeech.isSpeaking {
                                answerSpeech.stop()
                            } else if stt.isRecording {
                                stt.finishRecording()
                            } else {
                                startVoiceInput()
                            }
                        } label: {
                            Image(
                                systemName:
                                    answerSpeech.isSpeaking
                                    || stt.isRecording
                                    ? "stop.fill"
                                    : "mic.fill"
                            )
                            .font(.title3.weight(.bold))
                            .foregroundStyle(VisionCraftUI.onAccent)
                            .frame(width: 52, height: 52)
                            .background {
                                if answerSpeech.isSpeaking || stt.isRecording {
                                    Circle().fill(Color.red)
                                } else {
                                    Circle().fill(VisionCraftChatUI.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            !answerSpeech.isSpeaking
                            && (
                                !vm.isReadyForInput
                                || vm.isGenerating
                                || vm.isPreparingAttachment
                                || (
                                    speechTask != nil
                                    && !stt.isRecording
                                )
                            )
                        )
                        .accessibilityLabel(
                            AppLocalization.string(
                                answerSpeech.isSpeaking
                                ? "읽기 정지"
                                : stt.isRecording
                                ? "음성 입력 종료"
                                : "마이크"
                            )
                        )

                        Button {
                            sendTypedMessage()
                        } label: {
                            Text("전송")
                                .font(.headline)
                                .lineLimit(1)
                                .foregroundStyle(VisionCraftUI.onAccent)
                                .padding(.horizontal, 16)
                                .frame(minWidth: 64, minHeight: 52)
                                .background {
                                    if canSendTypedMessage {
                                        Capsule().fill(VisionCraftChatUI.accent)
                                    } else {
                                        Capsule().fill(Color.secondary)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSendTypedMessage)
                        .accessibilityIdentifier("local-chat-send")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 22)
                    .visionCraftChatComposerSurface()
                }
            }

            if vm.isInitialQueryRunning
                || vm.isPreparingAttachment {
                Color.black.opacity(0.4).ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView().progressViewStyle(.circular)
                    Text(
                        vm.isPreparingAttachment
                            ? (
                                vm.attachmentStatusDescription
                                ?? AppLocalization.string(
                                    "첨부 준비 중…"
                                )
                            )
                            : AppLocalization.string(
                                "분석 중…"
                            )
                    )
                        .font(.headline)
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .shadow(radius: 10)
                .accessibilityElement(children: .combine)
            }

            if showsModelPreparationPage {
                VisionCraftUI.background
                    .ignoresSafeArea()
                LocalModelPreparationView(
                    phase:
                        localAI
                        .modelPreparationPhase,
                    model:
                        localAI
                        .modelBeingPrepared,
                    failure:
                        vm
                        .modelPreparationFailure,
                    onRetry: {
                        Task {
                            await vm
                                .retryModelPreparation(
                                    for: intent
                                )
                        }
                    },
                    onDefer: {
                        dismiss()
                    }
                )
            }
        }
        .visionCraftNavigationScreen()
        .navigationTitle(
            showsModelPreparationPage
                ? AppLocalization.string(
                    "AI 모델 다운로드"
                )
                : navigationTitle
        )
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "대화에 첨부",
            isPresented:
                $isAttachmentMenuPresented,
            titleVisibility: .visible
        ) {
            Button("문서") {
                isDocumentImporterPresented =
                    true
            }
            Button("클립보드") {
                Task {
                    await vm.attachClipboardText(
                        UIPasteboard
                            .general.string
                    )
                }
            }
            Button("사진") {
                isPhotoPickerPresented = true
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(
                "PDF·TXT·XLSX·XLS·HWP·HWPX 문서, 클립보드 텍스트 또는 사진을 현재 대화의 문맥으로 사용합니다."
            )
        }
        .fileImporter(
            isPresented:
                $isDocumentImporterPresented,
            allowedContentTypes: [
                .pdf,
                UTType(
                    filenameExtension: "txt"
                ) ?? .plainText,
                UTType(
                    filenameExtension: "xlsx"
                ) ?? .data,
                UTType(
                    filenameExtension: "xls"
                ) ?? .data,
                UTType(
                    filenameExtension: "hwp"
                ) ?? .data,
                UTType(
                    filenameExtension: "hwpx"
                ) ?? .data,
            ],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first
                else {
                    return
                }
                Task {
                    await vm.attachDocument(
                        at: url
                    )
                }
            case .failure(let error):
                vm.attachmentErrorDescription =
                    error.localizedDescription
            }
        }
        .photosPicker(
            isPresented:
                $isPhotoPickerPresented,
            selection:
                $selectedPhotoItem,
            matching: .images
        )
        .onChange(
            of: selectedPhotoItem
        ) { _, item in
            guard let item else {
                return
            }
            Task {
                await attachPhoto(item)
            }
        }
        .task {
            guard !didStart else { return }
            didStart = true
            await vm.prepare(for: intent)
            if intent
                .automaticallyStartsSharedVoiceInput,
            vm.attachmentSummary != nil {
                await Task.yield()
                _ = startVoiceInput()
            }
        }
        .onDisappear {
            speechTask?.cancel()
            speechTask = nil
            stt.cancelRecording()
            answerSpeech.stop()
            if vm.isLoadingModel {
                Task {
                    await vm
                        .cancelModelPreparation()
                    vm.closeConversation()
                }
            } else {
                vm.closeConversation()
            }
        }
        .onChange(of: vm.isGenerating) { wasGenerating, isGenerating in
            if isGenerating {
                answerSpeech.stop()
                return
            }
            guard wasGenerating,
                  shouldSpeakNextResponse else {
                return
            }
            shouldSpeakNextResponse = false
            guard vm.status
                    == AppLocalization.string(
                        "완료"
                    ),
                  let response = vm.messages.last(where: {
                      $0.role == "assistant"
                          && !$0.text.trimmingCharacters(
                              in: .whitespacesAndNewlines
                          ).isEmpty
                  }) else {
                return
            }
            _ = answerSpeech.play(
                messageID: response.id,
                text: response.text
            )
        }
        .onChange(
            of: remoteControl.latestEvent
        ) { _, event in
            handleRemoteEvent(event)
        }
    }

    private var showsModelPreparationPage: Bool {
        intent.requiresLocalModel
            && (
                !didStart
                    || vm.isLoadingModel
                    || vm.modelPreparationFailure
                        != nil
            )
    }

    private var showsWelcomeMessage: Bool {
        if case .textChat(conversationID: nil) = intent {
            return true
        }
        return false
    }

    // The introductory UI message is not part of the model's conversation context.
    private var welcomeMessage: ChatViewModel.Msg {
        .init(
            id: welcomeMessageID,
            role: "assistant",
            text: AppLocalization.string("대화를 시작합니다. 무엇이든 말씀해주세요.")
        )
    }

    private var visibleStatusDescription: String? {
        if let attachmentStatus = vm.attachmentStatusDescription {
            return attachmentStatus
        }
        let routineStatuses = ["준비됨", "완료", "답변 생성 중…"]
            .map { AppLocalization.string($0) }
        guard !vm.status.isEmpty, !routineStatuses.contains(vm.status) else {
            return nil
        }
        return vm.status
    }

    private var quickPromptBar:
        some View
    {
        ScrollView(
            .horizontal,
            showsIndicators: false
        ) {
            HStack(spacing: 8) {
                quickPromptButton(
                    title: "첨부"
                ) {
                    isAttachmentMenuPresented =
                        true
                }
                quickPromptButton(
                    title: "요약",
                    minimumWidth: 96
                ) {
                    vm.sendQuickPrompt(
                        AppLocalization.string(
                            "대화와 첨부 내용을 요약해 주세요."
                        )
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
        .disabled(
            !vm.isReadyForInput
                || vm.isGenerating
                || vm.isPreparingAttachment
                || stt.isRecording
        )
        .accessibilityElement(
            children: .contain
        )
    }

    private func quickPromptButton(
        title: String,
        minimumWidth: CGFloat = 78,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(AppLocalization.string(title))
                .font(.subheadline.bold())
                .foregroundStyle(VisionCraftUI.primaryText)
                .padding(.horizontal, 18)
                .frame(minWidth: minimumWidth, minHeight: 48)
                .background(
                    VisionCraftUI.surfaceVariant,
                    in: RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private func attachmentBanner(
        _ summary: ChatAttachmentSummary
    ) -> some View {
        HStack(spacing: 10) {
            Image(
                systemName:
                    "paperclip.circle.fill"
            )
            .foregroundStyle(VisionCraftUI.primary)
            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text("대화 첨부")
                    .font(.subheadline.bold())
                Text(summary.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .visionCraftSurfaceCard(cornerRadius: 14)
        .accessibilityElement(
            children: .combine
        )
        .accessibilityLabel(
            AppLocalization.format(
                "대화 첨부: %@",
                summary.description
            )
        )
    }

    @MainActor
    private func attachPhoto(
        _ item: PhotosPickerItem
    ) async {
        defer {
            selectedPhotoItem = nil
        }
        do {
            guard let data =
                    try await item
                    .loadTransferable(
                        type: Data.self
                    ) else {
                throw ChatAttachmentError
                    .invalidImage
            }
            let contentType =
                item.supportedContentTypes
                .first(where: {
                    $0.conforms(to: .image)
                })
                ?? .jpeg
            let pathExtension =
                contentType
                .preferredFilenameExtension
                ?? "jpg"
            await vm.attachImage(
                data: data,
                suggestedName:
                    AppLocalization.string(
                        "첨부 사진"
                    )
                    + "."
                    + pathExtension,
                mimeType:
                    contentType
                    .preferredMIMEType
                    ?? "image/jpeg"
            )
        } catch {
            vm.attachmentErrorDescription =
                error.localizedDescription
        }
    }

    private var navigationTitle: String {
        switch intent {
        case .textChat,
             .voiceQuestion:
            return AppLocalization.string(
                "로컬 AI"
            )
        case .sharedTextQuestion:
            return AppLocalization.string(
                "공유 텍스트 질문"
            )
        case .sharedAttachmentQuestion:
            return AppLocalization.string(
                "공유 파일 질문"
            )
        case .imageAnalysis,
             .capturedImageAnalysis:
            return AppLocalization.string(
                "이미지 질문"
            )
        case .documentQA:
            return AppLocalization.string(
                "문서 질문"
            )
        case .webPageQA:
            return AppLocalization.string(
                "웹페이지 질문"
            )
        case .webSearchQA:
            return AppLocalization.string(
                "웹 검색 답변"
            )
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

    private var canSendTypedMessage: Bool {
        vm.canSend
            && !vm.isInitialQueryRunning
            && !stt.isRecording
            && speechTask == nil
    }

    private func sendTypedMessage() {
        guard canSendTypedMessage else { return }
        vm.sendUserMessage()
    }

    private var allowsFollowUpInput: Bool {
        if case .webSearchQA = intent {
            return false
        }
        return true
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

    private var latestAssistantMessage:
        ChatViewModel.Msg?
    {
        vm.messages.last(where: {
            $0.role == "assistant"
                && !$0.text
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .isEmpty
        })
    }

    private func answerSpeechControls(
        for response: ChatViewModel.Msg
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            HStack {
                Label(
                    "답변 음성",
                    systemImage:
                        "text.bubble.waveform"
                )
                .font(.subheadline.bold())
                Spacer()
                Text(
                    answerSpeech
                        .activeMessageID
                        == response.id
                        ? answerSpeech
                            .currentPositionDescription
                            ?? ""
                        : AppLocalization.string(
                            "재생할 답변 준비됨"
                        )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                speechControlButton(
                    title: "이전 문장",
                    systemImage:
                        "backward.end.fill"
                ) {
                    _ = answerSpeech.previous(
                        messageID: response.id,
                        text: response.text
                    )
                }

                speechControlButton(
                    title: "현재 문장 다시 읽기",
                    systemImage:
                        "arrow.counterclockwise"
                ) {
                    _ = answerSpeech.replay(
                        messageID: response.id,
                        text: response.text
                    )
                }

                speechControlButton(
                    title:
                        answerSpeech.isSpeaking
                            ? AppLocalization.string(
                                "답변 읽기 정지"
                            )
                            : AppLocalization.string(
                                "답변 읽기"
                            ),
                    systemImage:
                        answerSpeech.isSpeaking
                            ? "stop.fill"
                            : "play.fill"
                ) {
                    _ = answerSpeech.toggle(
                        messageID: response.id,
                        text: response.text
                    )
                }

                speechControlButton(
                    title: "다음 문장",
                    systemImage:
                        "forward.end.fill"
                ) {
                    _ = answerSpeech.next(
                        messageID: response.id,
                        text: response.text
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            VisionCraftUI.surface
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(VisionCraftUI.outline.opacity(0.7), lineWidth: 1)
        }
        .accessibilityElement(
            children: .contain
        )
    }

    private func speechControlButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(
                    maxWidth: .infinity,
                    minHeight: 30
                )
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .tint(VisionCraftUI.primary)
        .accessibilityLabel(
            AppLocalization.string(title)
        )
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
                                AppLocalization.format(
                                    "[%lld] %@",
                                    result.id,
                                    result.title
                                )
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
                if let html = response
                    .searchEntryPointHTML,
                   !html.isEmpty {
                    GoogleSearchEntryPointView(
                        html: html
                    )
                    .frame(height: 64)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 10,
                            style: .continuous
                        )
                    )
                    .accessibilityHint(
                        "Google에서 관련 검색을 이어갑니다."
                    )
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
                AppLocalization.format(
                    "Google 검색 출처 %lld개",
                    response.results.count
                ),
                systemImage:
                    "checkmark.shield"
            )
            .font(.subheadline.bold())
        }
        .padding(12)
        .background(VisionCraftUI.primary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(VisionCraftUI.primary.opacity(0.25), lineWidth: 1)
        }
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
            .foregroundStyle(VisionCraftUI.primary)

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
                AppLocalization.string(
                    "Safari에서 원문 열기"
                )
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(VisionCraftUI.surface)
        .overlay(alignment: .bottom) {
            Divider().overlay(VisionCraftUI.outline)
        }
        .accessibilityElement(
            children: .combine
        )
        .accessibilityLabel(
            AppLocalization.format(
                "출처: %@, %@",
                content.title,
                content.sourceURL.absoluteString
            )
        )
    }

    @discardableResult
    private func startVoiceInput() -> Bool {
        guard speechTask == nil,
              vm.isReadyForInput,
              !vm.isGenerating else {
            return false
        }

        answerSpeech.stop()
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
                            AppLocalization.string(
                                "음성을 인식하지 못했습니다. 다시 시도해 주세요."
                            )
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
              case .localAIChat(let action) =
                event?.action else {
            return
        }

        switch action {
        case .toggleVoiceInput:
            toggleVoiceInputFromRemote()
        case .previousSentence:
            controlAnswerSpeechFromRemote(
                action: .previous
            )
        case .replaySentence:
            controlAnswerSpeechFromRemote(
                action: .replay
            )
        case .nextSentence:
            controlAnswerSpeechFromRemote(
                action: .next
            )
        case .toggleAnswerReading:
            controlAnswerSpeechFromRemote(
                action: .toggle
            )
        }
    }

    private func toggleVoiceInputFromRemote() {
        if speechTask != nil || stt.isRecording {
            speechTask?.cancel()
            speechTask = nil
            stt.cancelRecording()
            voiceErrorDescription = nil
            UIAccessibility.post(
                notification: .announcement,
                argument:
                    AppLocalization.string(
                        "음성 입력 취소"
                    )
            )
        } else {
            let didStart = startVoiceInput()
            UIAccessibility.post(
                notification: .announcement,
                argument:
                    didStart
                        ? AppLocalization.string(
                            "음성 입력 시작"
                        )
                        : AppLocalization.string(
                            "AI가 준비되거나 답변을 마친 뒤 다시 시도해 주세요."
                        )
            )
        }
    }

    private enum RemoteAnswerSpeechAction:
        Equatable
    {
        case previous
        case replay
        case next
        case toggle
    }

    private func controlAnswerSpeechFromRemote(
        action: RemoteAnswerSpeechAction
    ) {
        guard !vm.isGenerating,
              let response =
                latestAssistantMessage else {
            UIAccessibility.post(
                notification: .announcement,
                argument:
                    AppLocalization.string(
                        "읽을 수 있는 AI 답변이 없습니다."
                    )
            )
            return
        }

        let wasSpeaking =
            answerSpeech.isSpeaking
        let didHandle: Bool
        switch action {
        case .previous:
            didHandle =
                answerSpeech.previous(
                    messageID: response.id,
                    text: response.text
                )
        case .replay:
            didHandle =
                answerSpeech.replay(
                    messageID: response.id,
                    text: response.text
                )
        case .next:
            didHandle =
                answerSpeech.next(
                    messageID: response.id,
                    text: response.text
                )
        case .toggle:
            didHandle =
                answerSpeech.toggle(
                    messageID: response.id,
                    text: response.text
                )
        }

        let announcement: String?
        if !didHandle {
            announcement =
                AppLocalization.string(
                    "읽을 수 있는 AI 답변이 없습니다."
                )
        } else if action == .toggle,
                  wasSpeaking {
            announcement =
                AppLocalization.string(
                    "답변 읽기 정지"
                )
        } else {
            // The selected sentence itself is the
            // feedback. An accessibility announcement
            // here would overlap the app TTS.
            announcement = nil
        }
        if let announcement {
            UIAccessibility.post(
                notification: .announcement,
                argument: announcement
            )
        }
    }
}


private struct MessageRow: View {
    let m: ChatViewModel.Msg
    let isGenerating: Bool
    let onSpeak: () -> Void
    @ScaledMetric(relativeTo: .body) private var messageFontSize = 32

    init(
        _ m: ChatViewModel.Msg,
        isGenerating: Bool = false,
        onSpeak: @escaping () -> Void
    ) {
        self.m = m
        self.isGenerating = isGenerating
        self.onSpeak = onSpeak
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if m.role == "user" {
                Spacer(minLength: 0)
                messageStack
            } else {
                messageStack
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, m.role == "user" ? 72 : 20)
        .padding(.trailing, m.role == "user" ? 20 : 32)
        .padding(.vertical, isTyping ? 8 : m.role == "user" ? 5 : 6)
    }

    private var isTyping: Bool {
        isGenerating && m.role != "user" && m.text.isEmpty && m.image == nil
    }

    @ViewBuilder
    private var messageStack: some View {
        if isTyping {
            VisionCraftChatTypingIndicator()
        } else {
            bubble
        }
    }

    private var bubble: some View {
        VStack(alignment: m.role == "user" ? .trailing : .leading, spacing: 8) {
            if let img = m.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel(
                        AppLocalization.string(
                            "첨부 이미지"
                        )
                    )
            }

            if !m.text.isEmpty {
                Text(m.text)
                    .font(.system(size: messageFontSize))
                    .lineSpacing(messageFontSize * (m.role == "user" ? 0.35 : 0.4))
                    .foregroundStyle(
                        m.role == "user"
                            ? VisionCraftUI.onAccent
                            : VisionCraftUI.primaryText
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, m.role == "user" ? 20 : 18)
        .padding(.vertical, 14)
        .visionCraftChatBubble(isUser: m.role == "user")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            AppLocalization.format(
                "%@: %@",
                m.role == "user"
                    ? AppLocalization.string(
                        "사용자"
                    )
                    : "AI",
                m.text
            )
        )
        .accessibilityHint(
            AppLocalization.string(
                "두 번 탭하면 메시지를 읽습니다."
            )
        )
        .onTapGesture(perform: onSpeak)
    }
}
