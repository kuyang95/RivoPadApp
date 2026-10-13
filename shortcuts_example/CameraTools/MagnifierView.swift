import Combine
import SwiftUI
import PhotosUI

/// 카메라 화면(Android `RVCameraXActivity`)의 SwiftUI 껍데기. 카메라 자체는 `MagnifierViewController`(UIKit)가 그리고,
/// 왼쪽 위에는 뒤로 가기만 둔다.
struct MagnifierView: View {
    let mode: MagnifierCameraMode

    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var remoteControl:
        RivoScreenRemoteControlCenter
    @EnvironmentObject private var quickMenu: RivoRemoteControlCenter
    @Environment(\.dismiss) private var dismiss

    init(mode: MagnifierCameraMode = .magnifier) {
        self.mode = mode
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            MagnifierCameraHost(
                mode: mode,
                remoteControl: remoteControl,
                quickMenu: quickMenu,
                appRouter: appRouter,
                dismiss: { dismiss() }
            )
            .ignoresSafeArea()
            VisionCraftBackButton(style: .overlay) { dismiss() }
                .padding(.leading, 16)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(.hidden, for: .navigationBar)
        .visionCraftHandlesBackNavigation()
    }

}

private struct MagnifierCameraHost: UIViewControllerRepresentable {
    let mode: MagnifierCameraMode
    let remoteControl: RivoScreenRemoteControlCenter
    let quickMenu: RivoRemoteControlCenter
    let appRouter: AppRouter
    let dismiss: () -> Void

    func makeUIViewController(
        context: Context
    ) -> MagnifierViewController {
        let controller = MagnifierViewController(mode: mode)
        let appRouter = appRouter
        let dismiss = dismiss
        controller.onClose = {
            dismiss()
        }
        controller.onCameraStateChanged = { [weak quickMenu] isTorchOn, isFrontCamera in
            quickMenu?.noteMagnifierState(
                isTorchOn: isTorchOn,
                isFrontCamera: isFrontCamera
            )
        }
        // 기본 촬영 결과는 사진 검토 화면으로 이어진다.
        controller.onOpenPhotoReview = {
            appRouter.route = .photoReview
        }
        controller.onAskAI = { image in
            guard let data = image.jpegData(compressionQuality: 0.85) else { return }
            Task {
                guard let attachment = try? await ChatAttachmentStore.shared.saveImage(
                    data: data,
                    suggestedName: "camera-question.jpg",
                    mimeType: "image/jpeg"
                ) else { return }
                appRouter.route = .sharedAttachmentQuestion(
                    attachment: attachment,
                    automaticallyStartsVoiceInput: true
                )
            }
        }
        controller.synchronizeRemoteEventCursor(
            to: remoteControl.latestEvent?.id
        )
        return controller
    }

    func updateUIViewController(
        _ uiViewController: MagnifierViewController,
        context: Context
    ) {
        guard let event = remoteControl.latestEvent,
              case .magnifier(let action) =
                event.action else {
            return
        }
        uiViewController.performRemoteAction(
            action,
            eventID: event.id
        )
    }
}

/// Android `PhotoReviewActivity`: 사진 한 장을 크게 보여주고 '작업' 버튼으로 후속 작업을 고르는 화면.
///
/// - 홈 '카메라와 연결 > 사진 분석': 사진 없이 열려 먼저 사진을 고르게 한다.
/// - 카메라 기본 모드: 촬영해 저장한 사진(`PhotoReviewHandoff`)을 받아 "촬영한 사진"으로 연다.
/// - 홈 '이미지 분석 > 사진에서'(`startsWithImageDescription`): 사진을 고르면 바로 설명한다(Android `ImageAnalysisActivity`).
///
/// 글자가 필요한 작업(글자 인식·번역·텍스트뷰어·텍스트 읽기)은 처음 고를 때 한 번만 인식하고 결과를 재사용한다.
struct PhotoReviewView: View {
    var startsWithImageDescription = false

    @EnvironmentObject private var appRouter: AppRouter
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettingsStore.shared

    @State private var selectedItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var fromCamera = false
    @State private var showsPicker = false
    @State private var showsActions = false
    @State private var didOpenPicker = false
    @State private var isBusy = false
    @State private var statusText: String?
    @State private var resultTitle: String?
    @State private var resultText: String?
    /// 인식해 둔 글자. nil 은 아직 안 했음, 빈 문자열은 했는데 글자가 없었음.
    @State private var recognizedText: String?
    @State private var work: Task<Void, Never>?

    private var title: String {
        AppLocalization.string(fromCamera ? "촬영한 사진" : "저장된 사진")
    }

    var body: some View {
        ZStack {
            VisionCraftHomeUI.background.ignoresSafeArea()
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .visionCraftAndroidText(24, weight: .bold, relativeTo: .title)
                        .foregroundStyle(VisionCraftHomeUI.text)
                        .padding(.leading, 4)
                        .padding(.top, 8)
                        .accessibilityAddTraits(.isHeader)
                    Spacer().frame(height: 12)

                    let hasResult = resultText != nil
                    // Android: 사진 weight 1, 결과 weight 0.6 → 결과 칸은 남은 높이의 0.6/1.6.
                    let flexibleHeight = max(geometry.size.height - 160, 120)
                    let resultHeight = hasResult ? flexibleHeight * 0.6 / 1.6 : 0

                    photoArea
                        .frame(maxWidth: .infinity)
                        .frame(height: hasResult ? flexibleHeight - resultHeight - 12 : nil)
                        .frame(maxHeight: hasResult ? nil : .infinity)

                    if let resultText {
                        Spacer().frame(height: 12)
                        resultPanel(resultText)
                            .frame(height: resultHeight)
                    }

                    Spacer().frame(height: 16)
                    let buttonRowWidth = max(geometry.size.width - 52, 0)
                    HStack(spacing: 12) {
                        Button {
                            if fromCamera {
                                dismiss()
                            } else {
                                showsPicker = true
                            }
                        } label: {
                            Text(AppLocalization.string(fromCamera ? "다시 촬영" : "다른 사진"))
                                .frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(VisionCraftAndroidButtonStyle())
                        .frame(width: buttonRowWidth / 2.45)
                        Button {
                            if image != nil { showsActions = true }
                        } label: {
                            Text(AppLocalization.string("작업"))
                                .frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(VisionCraftAndroidButtonStyle(emphasized: true))
                        .frame(width: buttonRowWidth * 1.45 / 2.45)
                        .disabled(image == nil)
                    }
                    .frame(minHeight: 64)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            if showsActions, image != nil {
                VisionCraftDialogCard(
                    title: "작업 선택",
                    cancelTitle: "닫기",
                    onDismiss: { showsActions = false }
                ) {
                    VStack(spacing: VisionCraftUI.actionRowSpacing) {
                        actionRow(
                            index: 0,
                            "글자 인식(OCR)",
                            "사진 속 글자를 인식해 보여주고 클립보드에 복사합니다.",
                            "textformat"
                        ) { recognizeText() }
                        actionRow(
                            index: 1,
                            "번역",
                            "인식한 글자를 앱 언어로 번역해 텍스트뷰어로 엽니다.",
                            "translate"
                        ) { translate() }
                        actionRow(
                            index: 2,
                            "AI와 이 사진으로 대화",
                            "이 사진을 첨부해 새 대화를 시작합니다.",
                            "bubble.left.and.bubble.right"
                        ) { chatWithPhoto() }
                        actionRow(
                            index: 3,
                            "텍스트뷰어로 보기",
                            "인식한 글자를 큰 글씨로 보고 수정하거나 저장합니다.",
                            "doc.text"
                        ) { viewInTextViewer() }
                        actionRow(
                            index: 4,
                            "이미지 설명",
                            "사진 속 내용을 AI가 설명해줍니다.",
                            "sparkles"
                        ) { describeImage() }
                        actionRow(
                            index: 5,
                            "텍스트 읽기",
                            "인식한 글자를 소리로 읽어줍니다. 다시 누르면 멈춥니다.",
                            "speaker.wave.2"
                        ) { readTextAloud() }
                    }
                }
            }
        }
        .photosPicker(isPresented: $showsPicker, selection: $selectedItem, matching: .images)
        .onAppear {
            guard !didOpenPicker else { return }
            didOpenPicker = true
            if let captured = PhotoReviewHandoff.take() {
                image = captured
                fromCamera = true
            } else {
                showsPicker = true
            }
        }
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .onChange(of: showsPicker) { _, isPresented in
            guard !isPresented else { return }
            // 처음부터 고르지 않고 닫았으면 빈 화면을 남기지 않는다(Android `finish()`).
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard image == nil, selectedItem == nil, !isBusy else { return }
                dismiss()
            }
        }
        .onDisappear {
            work?.cancel()
            TTSManager.shared.stop()
        }
    }

    // MARK: - 화면 조각

    @ViewBuilder
    private var photoArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(VisionCraftHomeUI.surface)
            if let image {
                VisionCraftZoomablePhoto(
                    image: image,
                    maximumScale: 6,
                    accessibilityLabel: "선택한 사진. 두 손가락으로 확대하고, 두 번 탭하면 원래 크기로 돌아갑니다."
                )
            } else if !isBusy {
                Text(AppLocalization.string("분석할 사진을 선택하세요."))
                    .visionCraftAndroidText(16)
                    .foregroundStyle(VisionCraftHomeUI.secondaryText)
            }
            if let statusText {
                VisionCraftCameraStatusBand(text: statusText)
                    .padding(16)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func resultPanel(_ text: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppLocalization.string(resultTitle ?? "글자 인식(OCR)"))
                    .visionCraftAndroidText(14, weight: .semibold, relativeTo: .subheadline)
                    .foregroundStyle(VisionCraftHomeUI.secondaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .visionCraftAndroidText(16)
                    .foregroundStyle(VisionCraftHomeUI.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
        .visionCraftSurfaceCard()
    }

    private func actionRow(
        index: Int,
        _ title: String,
        _ subtitle: String,
        _ icon: String,
        action: @escaping () -> Void
    ) -> some View {
        VisionCraftDialogOptionRow(
            title: title,
            subtitle: subtitle,
            systemImage: icon,
            showsIconTile: true,
            accent: VisionCraftHomeUI.logoAccent(index),
            action: {
                showsActions = false
                action()
            }
        )
    }

    // MARK: - 사진 불러오기

    private func load(_ item: PhotosPickerItem) async {
        work?.cancel()
        TTSManager.shared.stop()
        recognizedText = nil
        resultTitle = nil
        resultText = nil
        isBusy = true
        statusText = AppLocalization.string("사진을 불러오는 중")
        let data = try? await item.loadTransferable(type: Data.self)
        isBusy = false
        guard let data, let loaded = UIImage(data: data) else {
            statusText = AppLocalization.string("사진을 해석하지 못했어요.")
            fail(AppLocalization.string("사진을 해석하지 못했어요."))
            return
        }
        image = loaded
        statusText = nil
        if startsWithImageDescription {
            describeImage()
        }
    }

    // MARK: - 작업

    private func runAction(_ block: @escaping @MainActor (UIImage) async -> Void) {
        guard let source = image else { return }
        if isBusy {
            TTSManager.shared.speakFeedback(
                AppLocalization.string("작업을 처리하고 있습니다. 잠시만 기다려주세요.")
            )
            return
        }
        TTSManager.shared.stop()
        work = Task { @MainActor in
            isBusy = true
            await block(source)
            isBusy = false
            statusText = nil
        }
    }

    /// 인식한 글자를 돌려준다. 글자가 없으면 안내하고 nil.
    private func ensureRecognizedText(_ source: UIImage) async -> String? {
        let text: String
        if let cached = recognizedText {
            text = cached
        } else {
            statusText = AppLocalization.string("글자 인식중입니다")
            SoundEffectManager.shared.play(.startingLLM)
            TTSManager.shared.speakFeedback(AppLocalization.string("글자 인식중입니다"))
            var recognized = (try? await OCRService.shared.recognize(from: source)) ?? ""
            if recognized == "(텍스트 없음)" { recognized = "" }
            if !recognized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                recognized = await GeminiOCRCorrectionService.shared.correct(
                    image: source,
                    originalText: recognized,
                    isEnabled: settings.ocrAutoCorrectionEnabled
                )
            }
            guard !Task.isCancelled else { return nil }
            recognizedText = recognized
            text = recognized
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fail(AppLocalization.string("인식된 텍스트가 없습니다"))
            return nil
        }
        return text
    }

    private func recognizeText() {
        runAction { source in
            guard let text = await ensureRecognizedText(source) else { return }
            UIPasteboard.general.string = text
            showResult(AppLocalization.string("글자 인식(OCR)"), text)
            SoundEffectManager.shared.play(.complete)
            TTSManager.shared.speakFeedback(AppLocalization.string("결과를 클립보드에 복사했습니다."))
        }
    }

    private func translate() {
        runAction { source in
            guard let text = await ensureRecognizedText(source) else { return }
            statusText = AppLocalization.string("번역하고 있습니다.")
            TTSManager.shared.speakFeedback(AppLocalization.string("번역하고 있습니다."))
            appRouter.route = .translation(initialText: text, automaticallyStarts: true)
        }
    }

    private func viewInTextViewer() {
        runAction { source in
            guard let text = await ensureRecognizedText(source) else { return }
            appRouter.route = .textEditorText(title: title, text: text)
        }
    }

    private func readTextAloud() {
        if TTSManager.shared.isSpeaking {
            TTSManager.shared.stop()
            return
        }
        runAction { source in
            guard let text = await ensureRecognizedText(source) else { return }
            showResult(AppLocalization.string("글자 인식(OCR)"), text)
            TTSManager.shared.speak(text)
        }
    }

    private func describeImage() {
        runAction { source in
            statusText = AppLocalization.string("이미지를 설명하고 있습니다.")
            SoundEffectManager.shared.play(.startingLLM)
            TTSManager.shared.speakFeedback(AppLocalization.string("이미지를 설명하고 있습니다."))
            do {
                let caption = try await CameraImageDescriber.describe(source)
                guard !Task.isCancelled else { return }
                guard !caption.isEmpty else {
                    fail(AppLocalization.string("이미지를 설명하지 못했습니다."))
                    return
                }
                UIPasteboard.general.string = caption
                showResult(AppLocalization.string("이미지 설명"), caption)
                SoundEffectManager.shared.play(.complete)
                TTSManager.shared.speak(caption)
            } catch {
                guard !Task.isCancelled else { return }
                fail(CameraImageDescriber.userMessage(for: error))
            }
        }
    }

    /// 사진 자체를 첨부로 넘긴다.
    private func chatWithPhoto() {
        guard let image, let data = image.jpegData(compressionQuality: 0.85) else { return }
        TTSManager.shared.stop()
        Task {
            do {
                let attachment = try await ChatAttachmentStore.shared.saveImage(
                    data: data,
                    suggestedName: "photo-review.jpg",
                    mimeType: "image/jpeg"
                )
                appRouter.route = .sharedAttachmentQuestion(
                    attachment: attachment,
                    automaticallyStartsVoiceInput: false
                )
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    private func showResult(_ title: String, _ text: String) {
        resultTitle = title
        resultText = text
    }

    private func fail(_ message: String) {
        SoundEffectManager.shared.play(.fail)
        TTSManager.shared.speakFeedback(message)
        showResult(AppLocalization.string("안내"), message)
    }
}

/// 안드로이드 VisionCraft `describeImage` 의 사용자 프롬프트와 같은 문구.
/// 분량 기준만 4문장 이하로 둔다.
nonisolated enum LocalImageDescriptionPrompt {
    static func defaultQuestion(
        language: AppLanguage
    ) -> String {
        """
        이미지에 보이는 내용을 \(language.localAIResponseLanguageName)로 4문장 이하로 짧게 설명해 줘.
        """
    }

    /// LLM 화면(`ChatViewModel.systemForImageDescription`)과 같은 지시문.
    static func system(
        language: AppLanguage
    ) -> String {
        """
        너는 시각장애인 사용자를 돕는 \(language.localAIResponseLanguageName) 이미지 설명 도우미야.
        4문장 이하로 주요 대상, 화면의 중요한 텍스트, 상황만 간결하게 설명해.
        확실하지 않은 내용은 단정하지 마.
        """
    }
}
