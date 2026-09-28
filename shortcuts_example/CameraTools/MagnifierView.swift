import SwiftUI
import PhotosUI

struct MagnifierView: UIViewControllerRepresentable {
    let mode: MagnifierCameraMode

    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var remoteControl:
        RivoScreenRemoteControlCenter
    @Environment(\.dismiss) private var dismiss

    init(mode: MagnifierCameraMode = .magnifier) {
        self.mode = mode
    }

    func makeUIViewController(
        context: Context
    ) -> MagnifierViewController {
        let controller = MagnifierViewController(mode: mode)
        controller.onClose = {
            dismiss()
        }
        controller.onOpenDocumentScan = {
            appRouter.route = .documentScanning
        }
        controller.onOpenLiveTextReader = {
            appRouter.route = .liveTextReader
        }
        controller.onOpenImageAnalysisMode = {
            appRouter.route = .imageDescriptionCamera
        }
        controller.onOpenBasicMode = {
            appRouter.route = .magnifier
        }
        controller.onOpenPhotoReview = {
            appRouter.route = .photoReview
        }
        controller.onOpenAskAIMode = {
            appRouter.route = .cameraAskAI
        }
        controller.onDescribeImage = { image in
            appRouter.route = .capturedImageAnalysis(
                image: image,
                question: LocalImageDescriptionPrompt.defaultQuestion(
                    language: AppLanguage.current()
                )
            )
        }
        switch mode {
        case .magnifier:
            controller.onCapture = { image in
                appRouter.route = .OCRResult(image: image)
            }
        case .imageDescription:
            controller.onCapture = controller.onDescribeImage
        case .askAI:
            controller.onCapture = { image in
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
        case .liveTextReader:
            break
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

struct CameraMoreOptionsDialog: View {
    /// nil means the document scanner is the current camera mode.
    let currentMode: MagnifierCameraMode?
    let onBasic: () -> Void
    let onDocumentScan: () -> Void
    let onLiveTextReader: () -> Void
    let onImageAnalysis: () -> Void
    let onAskAI: () -> Void
    let onPhotoReview: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VisionCraftDialogCard(
            title: "모드",
            cancelTitle: "닫기",
            onDismiss: onDismiss
        ) {
            ScrollView {
                VStack(spacing: 10) {
                    VisionCraftDialogOptionRow(
                        title: "기본",
                        subtitle: "확대, 토치, 색상 필터로 가까운 대상을 봅니다.",
                        systemImage: "camera",
                        isPrimary: currentMode == .magnifier,
                        badge: currentMode == .magnifier ? "현재" : nil,
                        showsIconTile: false,
                        action: currentMode == .magnifier ? onDismiss : onBasic
                    )
                    VisionCraftDialogOptionRow(
                        title: "문서 스캔",
                        subtitle: "문서 한 장을 촬영해 텍스트로 이어갑니다.",
                        systemImage: "doc.viewfinder",
                        isPrimary: currentMode == nil,
                        badge: currentMode == nil ? "현재" : nil,
                        showsIconTile: false,
                        action: currentMode == nil ? onDismiss : onDocumentScan
                    )
                    VisionCraftDialogOptionRow(
                        title: "실시간 문자 읽기",
                        subtitle: "카메라 앞 글자를 자동으로 읽습니다.",
                        systemImage: "text.viewfinder",
                        isPrimary: currentMode == .liveTextReader,
                        badge: currentMode == .liveTextReader ? "현재" : nil,
                        showsIconTile: false,
                        action: currentMode == .liveTextReader ? onDismiss : onLiveTextReader
                    )
                    VisionCraftDialogOptionRow(
                        title: "이미지 분석",
                        subtitle: "사진 속 내용을 AI가 설명해줍니다.",
                        systemImage: "sparkles",
                        isPrimary: currentMode == .imageDescription,
                        badge: currentMode == .imageDescription ? "현재" : nil,
                        showsIconTile: false,
                        action: currentMode == .imageDescription ? onDismiss : onImageAnalysis
                    )
                    VisionCraftDialogOptionRow(
                        title: "AI 질문하기",
                        subtitle: "지금 보이는 장면을 찍어 AI에게 음성으로 질문합니다.",
                        systemImage: "bubble.left.and.bubble.right",
                        isPrimary: currentMode == .askAI,
                        badge: currentMode == .askAI ? "현재" : nil,
                        showsIconTile: false,
                        action: currentMode == .askAI ? onDismiss : onAskAI
                    )
                    VisionCraftDialogOptionRow(
                        title: "사진 분석",
                        subtitle: "저장된 사진을 골라 글자 인식, 번역, 설명, AI 대화를 합니다.",
                        systemImage: "photo.on.rectangle",
                        showsIconTile: false,
                        action: onPhotoReview
                    )
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 540)
        }
        .accessibilityAction(.escape, onDismiss)
    }
}

/// Android PhotoReviewActivity의 저장된 사진 선택 → 미리보기 → 작업 흐름.
struct PhotoReviewView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @State private var selectedItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var showsPicker = false
    @State private var showsActions = false
    @State private var didOpenPicker = false
    @State private var isBusy = false
    @State private var resultTitle: String?
    @State private var resultText: String?
    @State private var photoScale: CGFloat = 1
    @State private var photoScaleAtGestureStart: CGFloat = 1
    @State private var photoOffset: CGSize = .zero
    @State private var photoOffsetAtGestureStart: CGSize = .zero

    var body: some View {
        ZStack {
            VisionCraftHomeUI.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text(AppLocalization.string("사진 분석"))
                    .visionCraftAndroidText(24, weight: .bold, relativeTo: .title2)
                    .foregroundStyle(VisionCraftHomeUI.text)
                    .accessibilityAddTraits(.isHeader)

                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(VisionCraftHomeUI.surface)
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(photoScale)
                            .offset(photoOffset)
                            .gesture(
                                MagnifyGesture()
                                    .onChanged { value in
                                        photoScale = min(max(photoScaleAtGestureStart * value.magnification, 1), 6)
                                    }
                                    .onEnded { _ in
                                        photoScaleAtGestureStart = photoScale
                                        if photoScale == 1 { photoOffset = .zero }
                                    }
                            )
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        guard photoScale > 1 else { return }
                                        photoOffset = CGSize(
                                            width: photoOffsetAtGestureStart.width + value.translation.width,
                                            height: photoOffsetAtGestureStart.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        photoOffsetAtGestureStart = photoOffset
                                    }
                            )
                            .onTapGesture(count: 2) {
                                photoScale = 1
                                photoScaleAtGestureStart = 1
                                photoOffset = .zero
                                photoOffsetAtGestureStart = .zero
                            }
                            .accessibilityLabel(AppLocalization.string("선택한 사진"))
                    } else if isBusy {
                        ProgressView(AppLocalization.string("사진을 불러오는 중…"))
                    } else {
                        Text(AppLocalization.string("분석할 사진을 선택하세요."))
                            .foregroundStyle(VisionCraftHomeUI.secondaryText)
                    }
                }
                .clipped()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let resultText {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLocalization.string(resultTitle ?? "글자 인식"))
                            .font(.headline)
                        ScrollView {
                            Text(resultText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(18)
                    .frame(maxHeight: 180)
                    .visionCraftHomeSurface(cornerRadius: 22)
                }

                HStack(spacing: 12) {
                    Button {
                        showsPicker = true
                    } label: {
                        Text(AppLocalization.string("다른 사진 선택"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VisionCraftAndroidButtonStyle())
                    Button {
                        showsActions = true
                    } label: {
                        Text(AppLocalization.string("작업"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VisionCraftAndroidButtonStyle(emphasized: true))
                    .disabled(image == nil || isBusy)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if showsActions, image != nil {
                VisionCraftDialogCard(title: "작업 선택", cancelTitle: "닫기", onDismiss: { showsActions = false }) {
                    ScrollView {
                        VStack(spacing: 10) {
                            actionRow("글자 인식", "text.viewfinder") { runOCR(.recognize) }
                            actionRow("번역", "translate") { runOCR(.translate) }
                            actionRow("AI 대화", "bubble.left.and.bubble.right") { openChat() }
                            actionRow("텍스트로 보기", "doc.text") { runOCR(.textView) }
                            actionRow("이미지 설명", "sparkles") { describeImage() }
                            actionRow("소리 내어 읽기", "speaker.wave.2") { runOCR(.readAloud) }
                        }
                    }
                    .frame(maxHeight: 540)
                }
            }
        }
        .photosPicker(isPresented: $showsPicker, selection: $selectedItem, matching: .images)
        .onAppear {
            guard !didOpenPicker else { return }
            didOpenPicker = true
            showsPicker = true
        }
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
    }

    private func actionRow(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        VisionCraftDialogOptionRow(title: title, systemImage: icon, showsIconTile: false, action: {
            showsActions = false
            action()
        })
    }

    private func load(_ item: PhotosPickerItem) async {
        isBusy = true
        defer { isBusy = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let loaded = UIImage(data: data) else {
            resultTitle = "안내"
            resultText = AppLocalization.string("사진을 불러오지 못했습니다.")
            return
        }
        image = loaded
        photoScale = 1
        photoScaleAtGestureStart = 1
        photoOffset = .zero
        photoOffsetAtGestureStart = .zero
        resultTitle = nil
        resultText = nil
    }

    private enum OCRAction { case recognize, translate, textView, readAloud }

    private func runOCR(_ action: OCRAction) {
        guard let image else { return }
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                let text = try await OCRService.shared.recognize(from: image)
                guard text != "(텍스트 없음)", !text.isEmpty else {
                    resultTitle = "안내"
                    resultText = AppLocalization.string("사진에서 글자를 찾지 못했습니다.")
                    return
                }
                switch action {
                case .recognize:
                    UIPasteboard.general.string = text
                    resultTitle = "글자 인식"
                    resultText = text
                case .translate:
                    appRouter.route = .translation(initialText: text)
                case .textView:
                    appRouter.route = .textEditorText(title: AppLocalization.string("사진 분석"), text: text)
                case .readAloud:
                    resultTitle = "글자 인식"
                    resultText = text
                    TTSManager.shared.speak(text)
                }
            } catch {
                resultTitle = "안내"
                resultText = error.localizedDescription
            }
        }
    }

    private func openChat() {
        guard let image, let data = image.jpegData(compressionQuality: 0.85) else { return }
        Task {
            isBusy = true
            defer { isBusy = false }
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
                resultTitle = "안내"
                resultText = error.localizedDescription
            }
        }
    }

    private func describeImage() {
        guard let image else { return }
        appRouter.route = .capturedImageAnalysis(
            image: image,
            question: LocalImageDescriptionPrompt.defaultQuestion(language: AppLanguage.current())
        )
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
}
