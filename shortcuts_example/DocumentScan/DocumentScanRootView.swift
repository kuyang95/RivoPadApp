import SwiftUI
import UniformTypeIdentifiers
import UIKit

private enum ScanReviewDialog {
    case save
    case actions
}

enum DocumentReviewImageLayout {
    static func fittedSize(
        imageSize: CGSize,
        availableSize: CGSize
    ) -> CGSize {
        guard imageSize.width.isFinite,
              imageSize.height.isFinite,
              availableSize.width.isFinite,
              availableSize.height.isFinite,
              imageSize.width > 0,
              imageSize.height > 0,
              availableSize.width > 0,
              availableSize.height > 0 else {
            return .zero
        }

        let scale = min(
            availableSize.width / imageSize.width,
            availableSize.height / imageSize.height
        )
        return CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
    }
}

struct DocumentScanRootView: View {
    private enum Phase {
        case camera
        case capturedPageReview
        case pageReview
    }

    @EnvironmentObject private var appRouter:
        AppRouter
    @EnvironmentObject private var remoteControl:
        RivoScreenRemoteControlCenter
    @Environment(\.dismiss)
    private var dismiss
    @ObservedObject private var settings =
        AppSettingsStore.shared

    @StateObject private var session:
        DocumentScanSessionModel
    @State private var phase:
        Phase
    @State private var pendingImage:
        UIImage?
    @State private var scannerCommand:
        DocumentScannerCommand?
    @State private var cameraRemoteEvent:
        RivoScreenRemoteEvent?
    @State private var selectedPageID:
        UUID?
    @State private var exportDocument:
        ScannedPDFFileDocument?
    @State private var isExporting = false
    @State private var isPreparingDocument =
        false
    @State private var errorMessage:
        String?
    @State private var showsDiscardConfirmation =
        false
    @State private var recognizedText = ""
    @State private var recognizedLines: [OCRRecognizedLine] = []
    @State private var isRecognizingText = false
    @State private var isCorrectingText = false
    @State private var recognitionTask:
        Task<Void, Never>?
    @State private var isShowingRecognizedText = false
    @State private var scanDialog: ScanReviewDialog?
    @State private var reviewStatusMessage: String?
    @State private var showsCameraModes = false
    @State private var isLeavingForCameraMode = false

    init() {
        let session =
            DocumentScanSessionModel()
        _session = StateObject(
            wrappedValue: session
        )
        _phase = State(
            initialValue:
                session.pages.isEmpty
                    ? .camera
                    : .pageReview
        )
        _selectedPageID = State(
            initialValue:
                session.pages.first?.id
        )
    }

    var body: some View {
        ZStack {
            DocumentScannerController(
                remoteEvent:
                    cameraRemoteEvent,
                command: scannerCommand,
                isActive:
                    phase == .camera && !isLeavingForCameraMode,
                automaticCaptureEnabled:
                    settings
                    .documentScanAutomaticCaptureEnabled,
                curvedPageCorrectionEnabled:
                    settings
                    .documentScanCurvedPageCorrectionEnabled,
                onScanCompleted:
                    reviewCapturedPage,
                onCancel: handleScannerCancel
            )
            .ignoresSafeArea()
            .opacity(
                phase == .camera ? 1 : 0
            )
            .allowsHitTesting(
                phase == .camera
            )
            .accessibilityHidden(
                phase != .camera
            )

            switch phase {
            case .camera:
                EmptyView()
            case .capturedPageReview:
                capturedPageReview
            case .pageReview:
                pageReview
            }

            if phase == .camera {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            showsCameraModes = true
                        } label: {
                            Label(
                                AppLocalization.format("모드: %@", AppLocalization.string("문서 스캔")),
                                systemImage: "slider.horizontal.3"
                            )
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 64)
                            .background(Color(red: 40 / 255, green: 53 / 255, blue: 70 / 255),
                                        in: RoundedRectangle(cornerRadius: 20))
                            .overlay {
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color(red: 240 / 255, green: 244 / 255, blue: 250 / 255), lineWidth: 2.5)
                            }
                        }
                        .accessibilityLabel(AppLocalization.format("모드, %@", AppLocalization.string("문서 스캔")))
                    }
                    Spacer()
                }
                .padding(.top, 12)
                .padding(.trailing, 16)
            }

            if isPreparingDocument {
                preparingOverlay
            }

            scanDialogOverlay

            if showsCameraModes {
                CameraMoreOptionsDialog(
                    currentMode: nil,
                    onBasic: { openCameraMode(.magnifier) },
                    onDocumentScan: { showsCameraModes = false },
                    onLiveTextReader: { openCameraMode(.liveTextReader) },
                    onImageAnalysis: { openCameraMode(.imageDescriptionCamera) },
                    onAskAI: { openCameraMode(.cameraAskAI) },
                    onPhotoReview: { openCameraMode(.photoReview) },
                    onDismiss: { showsCameraModes = false }
                )
            }
        }
        .tint(VisionCraftUI.primary)
        .background(Color.black)
        .visionCraftCameraScreen()
        .visionCraftHandlesBackNavigation()
        .toolbar {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarLeading) {
                    scanBackButton
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) {
                    scanBackButton
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .pdf,
            defaultFilename:
                defaultPDFFileName
        ) { result in
            if case .failure(let error) =
                result {
                errorMessage =
                    error.localizedDescription
            }
            exportDocument = nil
        }
        .alert(
            "스캔 작업을 완료할 수 없습니다",
            isPresented: Binding(
                get: {
                    errorMessage != nil
                },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                        session.clearError()
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "촬영한 페이지를 모두 삭제할까요?",
            isPresented:
                $showsDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                "페이지 삭제 후 닫기",
                role: .destructive
            ) {
                session.discard()
                dismiss()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(
                "아직 내보내지 않은 스캔 페이지는 복구할 수 없습니다."
            )
        }
        .onReceive(
            session.$errorDescription
        ) { description in
            if let description {
                errorMessage = description
            }
        }
        .onChange(
            of: remoteControl.latestEvent
        ) { _, event in
            handleRemoteEvent(event)
        }
        .onChange(of: session.pages) {
            _, _ in
            normalizeSelectedPage()
        }
        .onDisappear {
            recognitionTask?.cancel()
            TTSManager.shared.stop()
        }
        .onAppear {
            isLeavingForCameraMode = false
        }
    }

    private func openCameraMode(_ route: AppRoute) {
        showsCameraModes = false
        isLeavingForCameraMode = true
        appRouter.route = route
    }

    private var scanBackButton: some View {
        VisionCraftBackButton(
            style: phase == .camera ? .overlay : .standard
        ) {
            if phase == .capturedPageReview {
                returnToCamera()
            } else {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var capturedPageReview:
        some View
    {
        if let pendingImage {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("스캔된 문서")
                        .font(
                            .system(
                                size: 22,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            VisionCraftUI.primaryText
                        )
                    Spacer()

                    Button {
                        guard !recognizedText
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty else {
                            reviewStatusMessage =
                                AppLocalization.string(
                                    "인식된 텍스트가 없습니다"
                                )
                            return
                        }
                        isShowingRecognizedText.toggle()
                    } label: {
                        Label(
                            AppLocalization.string(
                                isShowingRecognizedText
                                ? "이미지 보기"
                                : "텍스트만 보기"
                            ),
                            systemImage:
                                isShowingRecognizedText
                                ? "photo"
                                : "doc.text"
                        )
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(VisionCraftUI.primary)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .background(
                            VisionCraftUI.primary
                                .opacity(0.12),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    VisionCraftUI.primary
                                        .opacity(0.32),
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        AppLocalization.string(
                            isShowingRecognizedText
                            ? "이미지 보기"
                            : "텍스트만 보기"
                        )
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 8)

                ZStack {
                    if isShowingRecognizedText {
                        ScrollView {
                            Text(recognizedText)
                                .font(.system(size: 24))
                                .lineSpacing(6)
                                .foregroundStyle(
                                    VisionCraftUI.primaryText
                                )
                                .textSelection(.enabled)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                                .padding(20)
                        }
                        .background(
                            VisionCraftUI.surface
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 16,
                                style: .continuous
                            )
                        )
                    } else {
                        GeometryReader { geometry in
                            let previewSize =
                                DocumentReviewImageLayout
                                .fittedSize(
                                    imageSize: pendingImage.size,
                                    availableSize: geometry.size
                                )

                            Image(uiImage: pendingImage)
                                .resizable()
                                .scaledToFit()
                                .accessibilityLabel(
                                    "보정된 문서 미리보기"
                                )
                                .frame(
                                    width: previewSize.width,
                                    height: previewSize.height
                                )
                                .background(Color.black)
                                .overlay {
                                    scanReviewTextBoxes
                                }
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 16,
                                        style: .continuous
                                    )
                                )

                                .frame(
                                    width: geometry.size.width,
                                    height: geometry.size.height,
                                    alignment: .center
                                )
                        }
                    }

                    if let recognitionProgressMessage {
                        VStack(spacing: 4) {
                            Text(
                                recognitionProgressMessage
                            )
                            .font(.headline)

                            if isCorrectingText {
                                Text(
                                    "인식된 원문은 지금 사용할 수 있습니다"
                                )
                                .font(.subheadline)
                            }
                        }
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(
                                Color.black.opacity(0.7),
                                in: Capsule()
                            )
                            .accessibilityAddTraits(
                                .updatesFrequently
                            )
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

                HStack(spacing: 10) {
                    scanReviewActionButton(
                        title: "저장",
                        isPrimary: false
                    ) {
                        scanDialog = .save
                    }

                    scanReviewActionButton(
                        title: "작업",
                        isPrimary: true
                    ) {
                        scanDialog = .actions
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(VisionCraftUI.background)
            .overlay(alignment: .top) {
                if let reviewStatusMessage {
                    Text(reviewStatusMessage)
                        .font(.subheadline.bold())
                        .foregroundStyle(VisionCraftHomeUI.onPrimary)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 48)
                        .background(
                            VisionCraftUI.primary.opacity(0.88),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .padding(.top, 84)
                        .task(
                            id: reviewStatusMessage
                        ) {
                            try? await Task.sleep(
                                for: .seconds(5)
                            )
                            guard self
                                .reviewStatusMessage
                                == reviewStatusMessage
                            else {
                                return
                            }
                            self.reviewStatusMessage = nil
                        }
                }
            }
        }
    }

    private var scanReviewTextBoxes: some View {
        Canvas { context, size in
            let color = Color(
                red: 50.0 / 255,
                green: 150.0 / 255,
                blue: 1
            )
            let imageBounds = CGRect(origin: .zero, size: size)

            for line in recognizedLines {
                let box = line.boundingBox
                // OCR 좌하단 정규화 좌표를 미리보기의 좌상단 좌표로 변환한다.
                let rect = CGRect(
                    x: box.minX * size.width,
                    y: (1 - box.maxY) * size.height,
                    width: box.width * size.width,
                    height: box.height * size.height
                ).intersection(imageBounds)
                guard !rect.isNull, !rect.isEmpty else {
                    continue
                }

                let path = Path(roundedRect: rect, cornerRadius: 2)
                context.fill(
                    path,
                    with: .color(color.opacity(60.0 / 255))
                )
                context.stroke(
                    path,
                    with: .color(color.opacity(180.0 / 255)),
                    lineWidth: 1
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var recognitionProgressMessage: String? {
        if isRecognizingText {
            return AppLocalization.string(
                "기본 글자 인식 중 · 보통 몇 초 걸립니다"
            )
        }
        if isCorrectingText {
            return AppLocalization.string(
                "글자 인식 완료 · 오타 교정 중"
            )
        }
        return nil
    }

    private func scanReviewActionButton(
        title: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(AppLocalization.string(title))
                .visionCraftAndroidText(16, weight: .semibold)
                .foregroundStyle(
                    isPrimary ? VisionCraftUI.onAccent : VisionCraftUI.primaryText
                )
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(
                    isPrimary ? VisionCraftUI.accent : VisionCraftUI.surface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isPrimary ? VisionCraftUI.accent : VisionCraftUI.outline,
                            lineWidth: 1.5
                        )
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var scanDialogOverlay: some View {
        if let scanDialog {
            ZStack {
                Color.black.opacity(0.52)
                    .ignoresSafeArea()
                    .onTapGesture {
                        self.scanDialog = nil
                    }

                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {
                    Text(
                        scanDialog == .save
                        ? "저장 방식 선택"
                        : "작업 선택"
                    )
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(
                        VisionCraftUI.primaryText
                    )
                    .padding(.bottom, 12)

                    if scanDialog == .save {
                        scanDialogButton(
                            "사진으로 저장",
                            isPrimary: true,
                            action: saveReviewPhoto
                        )
                        scanDialogButton(
                            "PDF로 저장",
                            action: saveReviewPDF
                        )
                        scanDialogButton(
                            "텍스트를 클립보드에 저장",
                            action: copyReviewText
                        )
                    } else {
                        scanDialogButton(
                            "이 문서로 AI와대화",
                            isPrimary: true,
                            isEnabled: recognizedReviewText != nil
                        ) {
                            openDocumentChat()
                        }
                        scanDialogButton(
                            "번역",
                            isEnabled: recognizedReviewText != nil
                        ) {
                            openReviewTranslation()
                        }
                        scanDialogButton(
                            "텍스트뷰어로 보기",
                            isEnabled: recognizedReviewText != nil
                        ) {
                            openReviewTextViewer()
                        }
                        scanDialogButton(
                            "이미지 설명"
                        ) {
                            openReviewImageDescription()
                        }
                        scanDialogButton(
                            "텍스트 읽기",
                            isEnabled: recognizedReviewText != nil
                        ) {
                            readReviewText()
                        }
                    }

                    scanDialogButton("닫기") {
                        self.scanDialog = nil
                    }
                    .padding(.top, 4)
                }
                .padding(24)
                .frame(maxWidth: 560)
                .background(
                    VisionCraftUI.surface,
                    in: RoundedRectangle(
                        cornerRadius: 28,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 28,
                        style: .continuous
                    )
                    .stroke(
                        VisionCraftUI.outline,
                        lineWidth: 1.5
                    )
                }
                .padding(.horizontal, 24)
            }
            .zIndex(200)
        }
    }

    private func scanDialogButton(
        _ title: String,
        isPrimary: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(AppLocalization.string(title))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(
                    isPrimary
                    ? VisionCraftUI.onAccent
                    : VisionCraftUI.primaryText
                )
                .frame(
                    maxWidth: .infinity,
                    minHeight: 56
                )
                .background(
                    isPrimary
                    ? VisionCraftUI.accent
                    : VisionCraftUI.surface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isPrimary ? VisionCraftUI.accent : VisionCraftUI.outline,
                            lineWidth: 1.5
                        )
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var recognizedReviewText: String? {
        let text = recognizedText
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        return text.isEmpty ? nil : text
    }

    private func openDocumentChat() {
        guard let text = requireRecognizedReviewText() else { return }
        scanDialog = nil
        TTSManager.shared.stop()
        appRouter.route = .sharedTextQuestion(
            text: text,
            automaticallyStartsVoiceInput: false
        )
    }

    private func openReviewTranslation() {
        guard let text = requireRecognizedReviewText() else { return }
        scanDialog = nil
        TTSManager.shared.stop()
        appRouter.route = .translation(
            initialText: text,
            automaticallyStarts: true
        )
    }

    private func openReviewTextViewer() {
        guard let text = requireRecognizedReviewText() else { return }
        scanDialog = nil
        TTSManager.shared.stop()
        appRouter.route = .textEditorText(
            title: AppLocalization.string("스캔된 문서"),
            text: text
        )
    }

    private func openReviewImageDescription() {
        guard let pendingImage else { return }
        scanDialog = nil
        TTSManager.shared.stop()
        appRouter.route = .capturedImageAnalysis(
            image: pendingImage,
            question: LocalImageDescriptionPrompt.defaultQuestion(
                language: AppLanguage.current()
            )
        )
    }

    private func readReviewText() {
        guard let text = requireRecognizedReviewText() else { return }
        scanDialog = nil
        TTSManager.shared.speak(text)
    }

    private func requireRecognizedReviewText() -> String? {
        guard let text = recognizedReviewText else {
            scanDialog = nil
            reviewStatusMessage = AppLocalization.string(
                "인식된 텍스트가 없습니다"
            )
            return nil
        }
        return text
    }

    private func saveReviewPhoto() {
        guard let pendingImage else {
            return
        }
        scanDialog = nil
        Task {
            do {
                let capture = try MagnifierPhotoCapture(
                    image: pendingImage
                )
                try await MagnifierPhotoSaveService()
                    .saveToPhotoLibrary(capture)
                reviewStatusMessage =
                    AppLocalization.string(
                        "사진이 저장되었습니다"
                    )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func saveReviewPDF() {
        guard let pendingImage else {
            return
        }
        scanDialog = nil
        let pageBounds = CGRect(
            origin: .zero,
            size: pendingImage.size
        )
        let renderer = UIGraphicsPDFRenderer(
            bounds: pageBounds
        )
        let data = renderer.pdfData { context in
            context.beginPage()
            pendingImage.draw(in: pageBounds)
        }
        exportDocument = ScannedPDFFileDocument(
            data: data
        )
        isExporting = true
    }

    private func copyReviewText() {
        let text = recognizedText
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard !text.isEmpty else {
            scanDialog = nil
            reviewStatusMessage =
                AppLocalization.string(
                    "인식된 텍스트가 없습니다"
                )
            return
        }
        UIPasteboard.general.string = text
        scanDialog = nil
        reviewStatusMessage =
            AppLocalization.string(
                "텍스트를 클립보드에 저장했습니다"
            )
    }

    private var pageReview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button(
                    "닫기",
                    systemImage: "xmark"
                ) {
                    requestClose()
                }
                .buttonStyle(.bordered)

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text("스캔 페이지 검토")
                        .font(.title2.bold())
                    Text(
                        "\(session.pages.count)페이지 · 끌어서 순서 변경"
                    )
                    .font(.subheadline)
                    .foregroundStyle(
                        .secondary
                    )
                }

                Spacer()
                EditButton()
            }
            .padding(20)

            Divider()

            if session.pages.isEmpty {
                ContentUnavailableView(
                    "저장된 페이지가 없습니다",
                    systemImage:
                        "doc.viewfinder",
                    description:
                        Text(
                            "페이지 추가를 눌러 문서를 촬영하세요."
                        )
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(
                            Array(
                                session.pages
                                    .enumerated()
                            ),
                            id: \.element.id
                        ) { index, page in
                            pageRow(
                                page,
                                number: index + 1
                            )
                            .id(page.id)
                            .listRowBackground(
                                selectedPageID
                                    == page.id
                                    ? VisionCraftUI
                                        .primary
                                        .opacity(0.14)
                                    : VisionCraftUI.surface
                            )
                            .accessibilityAddTraits(
                                selectedPageID
                                    == page.id
                                    ? .isSelected
                                    : []
                            )
                        }
                        .onMove(
                            perform:
                                session.move
                        )
                        .onDelete(
                            perform:
                                session.remove
                        )
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(VisionCraftUI.background)
                    .onChange(
                        of: selectedPageID
                    ) { _, pageID in
                        guard let pageID else {
                            return
                        }
                        withAnimation {
                            proxy.scrollTo(
                                pageID,
                                anchor: .center
                            )
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                Button(
                    "페이지 추가",
                    systemImage: "camera"
                ) {
                    startAnotherPage()
                }
                .buttonStyle(.bordered)
                .disabled(
                    !session.canAddPage
                )

                Spacer()

                Button(
                    "문서로 열기",
                    systemImage:
                        "doc.text.magnifyingglass"
                ) {
                    openScannedDocument()
                }
                .buttonStyle(.bordered)
                .disabled(
                    session.pages.isEmpty
                )

                Button(
                    "PDF로 저장",
                    systemImage:
                        "square.and.arrow.down"
                ) {
                    exportPDF()
                }
                .buttonStyle(
                    .borderedProminent
                )
                .disabled(
                    session.pages.isEmpty
                )
            }
            .controlSize(.large)
            .padding(20)
        }
        .background(VisionCraftUI.background)
    }

    private func pageRow(
        _ page: DocumentScanPageRecord,
        number: Int
    ) -> some View {
        HStack(spacing: 16) {
            Group {
                if let image =
                        session.image(
                            for: page
                        ) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(
                        systemName:
                            "exclamationmark.triangle"
                    )
                    .foregroundStyle(.red)
                }
            }
            .frame(
                width: 90,
                height: 110
            )
            .background(Color.black)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
            )
            .accessibilityHidden(true)

            VStack(
                alignment: .leading,
                spacing: 6
            ) {
                Text("페이지 \(number)")
                    .font(.headline)
                Text(
                    page.capturedAt,
                    style: .time
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Text(
                    "오른쪽으로 \(page.normalizedQuarterTurns * 90)도 회전"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(
                "회전",
                systemImage:
                    "rotate.right"
            ) {
                session.rotate(page)
            }
            .buttonStyle(.bordered)
            .accessibilityHint(
                "페이지를 오른쪽으로 90도 회전합니다."
            )

            Button(
                "삭제",
                systemImage: "trash",
                role: .destructive
            ) {
                session.remove(page)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
        .accessibilityElement(
            children: .contain
        )
    }

    private var preparingOverlay:
        some View
    {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text(
                    "여러 페이지 문서를 만드는 중입니다."
                )
                .font(.headline)
                .foregroundStyle(.white)
            }
            .padding(28)
            .background(
                Color.black.opacity(0.75)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
        }
        .accessibilityElement(
            children: .combine
        )
    }

    private var defaultPDFFileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "en_US_POSIX"
        )
        formatter.dateFormat =
            "yyyyMMdd_HHmm"
        return "VisionCraft Scan "
            + formatter.string(
                from: Date()
            )
    }

    private func handleRemoteEvent(
        _ event: RivoScreenRemoteEvent?
    ) {
        guard let event,
              case .documentScanner(
                let action
              ) = event.action else {
            return
        }

        switch phase {
        case .camera:
            cameraRemoteEvent = event
        case .capturedPageReview:
            handleCapturedPageRemoteAction(
                action
            )
        case .pageReview:
            handlePageReviewRemoteAction(
                action
            )
        }
    }

    private func handleCapturedPageRemoteAction(
        _ action:
            RivoDocumentScannerRemoteAction
    ) {
        guard !isPreparingDocument,
              !showsDiscardConfirmation else {
            return
        }
        switch action {
        case .close:
            returnToCamera()
            announceRemoteFeedback(
                AppLocalization.string(
                    "재촬영"
                )
            )
        case .capture:
            announceRemoteFeedback(
                AppLocalization.string(
                    "저장"
                )
            )
            scanDialog = .save
        case .addPage:
            announceRemoteFeedback(
                AppLocalization.string(
                    "작업"
                )
            )
            scanDialog = .actions
        case .openDocument:
            announceRemoteFeedback(
                AppLocalization.string(
                    isShowingRecognizedText
                    ? "이미지 보기"
                    : "텍스트만 보기"
                )
            )
            if !recognizedText.isEmpty {
                isShowingRecognizedText.toggle()
            }
        case .previousPage,
             .rotatePage,
             .nextPage:
            break
        }
    }

    private func handlePageReviewRemoteAction(
        _ action:
            RivoDocumentScannerRemoteAction
    ) {
        guard !isPreparingDocument,
              !isExporting,
              !showsDiscardConfirmation else {
            return
        }
        switch action {
        case .close:
            requestClose()
        case .capture:
            announceRemoteFeedback(
                AppLocalization.string(
                    "PDF로 저장"
                )
            )
            exportPDF()
        case .previousPage:
            moveRemotePageSelection(by: -1)
        case .rotatePage:
            rotateRemoteSelectedPage()
        case .nextPage:
            moveRemotePageSelection(by: 1)
        case .addPage:
            announceRemoteFeedback(
                AppLocalization.string(
                    "페이지 추가"
                )
            )
            startAnotherPage()
        case .openDocument:
            announceRemoteFeedback(
                AppLocalization.string(
                    "문서로 열기"
                )
            )
            openScannedDocument()
        }
    }

    private func moveRemotePageSelection(
        by offset: Int
    ) {
        guard !session.pages.isEmpty else {
            return
        }
        let currentIndex =
            selectedPageID.flatMap { pageID in
                session.pages.firstIndex(
                    where: {
                        $0.id == pageID
                    }
                )
            } ?? 0
        let targetIndex = min(
            max(
                currentIndex + offset,
                0
            ),
            session.pages.count - 1
        )
        selectedPageID =
            session.pages[targetIndex].id
        announceRemotePage(
            at: targetIndex
        )
    }

    private func rotateRemoteSelectedPage() {
        normalizeSelectedPage()
        guard let selectedPageID,
              let index =
                session.pages.firstIndex(
                    where: {
                        $0.id
                            == selectedPageID
                    }
                ) else {
            return
        }
        session.rotate(
            session.pages[index]
        )
        announceRemoteFeedback(
            AppLocalization.format(
                "페이지 %lld를 오른쪽으로 90도 회전했습니다.",
                index + 1
            )
        )
    }

    private func normalizeSelectedPage() {
        guard !session.pages.isEmpty else {
            selectedPageID = nil
            return
        }
        guard let selectedPageID,
              session.pages.contains(
                where: {
                    $0.id
                        == selectedPageID
                }
              ) else {
            self.selectedPageID =
                session.pages.first?.id
            return
        }
    }

    private func announceRemotePage(
        at index: Int
    ) {
        announceRemoteFeedback(
            AppLocalization.format(
                "%@, %lld/%lld",
                AppLocalization.string(
                    "페이지"
                ),
                index + 1,
                session.pages.count
            )
        )
    }

    private func announceRemoteFeedback(
        _ message: String
    ) {
        UIAccessibility.post(
            notification: .announcement,
            argument: message
        )
    }

    private func reviewCapturedPage(
        _ image: UIImage
    ) {
        recognitionTask?.cancel()
        pendingImage = image
        recognizedText = ""
        recognizedLines = []
        isRecognizingText = false
        isCorrectingText = false
        isShowingRecognizedText = false
        reviewStatusMessage = nil
        scanDialog = nil
        phase = .capturedPageReview
        UIAccessibility.post(
            notification:
                .screenChanged,
            argument: "스캔된 문서"
        )
        recognizeReviewText(in: image)
    }

    private func recognizeReviewText(
        in image: UIImage
    ) {
        recognitionTask?.cancel()
        isRecognizingText = true
        isCorrectingText = false
        SoundEffectManager.shared.play(
            .startingLLM
        )
        TTSManager.shared.speakFeedback(
            AppLocalization.string(
                "글자 인식중입니다"
            )
        )

        recognitionTask = Task {
            do {
                let lines = try await OCRService
                    .shared
                    .recognizeLines(
                        from: image
                    )
                guard pendingImage === image else {
                    return
                }
                isRecognizingText = false
                let originalText = lines
                    .map(\.text)
                    .joined(separator: "\n")

                guard !originalText
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty else {
                    let message =
                        AppLocalization.string(
                            "인식된 텍스트가 없습니다"
                        )
                    recognizedText = ""
                    reviewStatusMessage = message
                    TTSManager.shared.speakFeedback(
                        message
                    )
                    return
                }

                recognizedText = originalText
                recognizedLines = lines
                guard settings
                    .ocrAutoCorrectionEnabled else {
                    let message =
                        AppLocalization.string(
                            "글자 인식을 완료했습니다"
                        )
                    reviewStatusMessage = message
                    SoundEffectManager.shared.play(.complete)
                    TTSManager.shared.speakFeedback(
                        message
                    )
                    return
                }

                isCorrectingText = true
                TTSManager.shared.speakFeedback(
                    AppLocalization.string(
                        "글자 인식을 완료했습니다. 오타 교정 중입니다. 원문은 지금 사용할 수 있습니다."
                    )
                )
                let correctionResult = await
                    GeminiOCRCorrectionService
                    .shared
                    .correctResult(
                        image: image,
                        originalText:
                            originalText,
                        isEnabled: true
                    )
                guard pendingImage === image else {
                    return
                }
                isCorrectingText = false
                recognizedText =
                    correctionResult.text

                switch correctionResult.status {
                case .notRequested:
                    reviewStatusMessage =
                        AppLocalization.string(
                            "글자 인식을 완료했습니다"
                        )
                case .corrected:
                    reviewStatusMessage =
                        AppLocalization.string(
                            "오타 교정을 완료했습니다"
                        )
                case .unchanged:
                    reviewStatusMessage =
                        AppLocalization.string(
                            "오타 확인을 완료했습니다. 원문을 그대로 표시합니다."
                        )
                case .unavailable:
                    reviewStatusMessage =
                        AppLocalization.string(
                            "글자 인식을 완료했습니다. 오타 교정을 사용할 수 없어 원문을 표시합니다."
                        )
                case .quotaExceeded:
                    reviewStatusMessage =
                        AppLocalization.string(
                            "글자 인식을 완료했습니다. 오늘의 클라우드 AI 토큰을 모두 사용해 원문을 표시합니다."
                        )
                case .failed:
                    reviewStatusMessage =
                        AppLocalization.string(
                            "글자 인식을 완료했습니다. 오타 교정을 완료하지 못해 원문을 표시합니다."
                        )
                case .cancelled:
                    break
                }
                if correctionResult.status
                    != .cancelled,
                   let reviewStatusMessage {
                    SoundEffectManager.shared.play(.complete)
                    TTSManager.shared.speakFeedback(
                        reviewStatusMessage
                    )
                }
            } catch {
                guard pendingImage === image else {
                    return
                }
                let message =
                    AppLocalization.string(
                        "인식된 텍스트가 없습니다"
                    )
                recognizedText = ""
                recognizedLines = []
                isRecognizingText = false
                isCorrectingText = false
                reviewStatusMessage = message
                TTSManager.shared.speakFeedback(
                    message
                )
            }
        }
    }

    private func returnToCamera() {
        recognitionTask?.cancel()
        recognitionTask = nil
        TTSManager.shared.stop()
        pendingImage = nil
        recognizedText = ""
        recognizedLines = []
        isRecognizingText = false
        isCorrectingText = false
        isShowingRecognizedText = false
        scanDialog = nil
        reviewStatusMessage = nil
        scannerCommand = .resume(
            id: UUID()
        )
        phase = .camera
    }

    private func saveAndContinue() {
        guard let pendingImage,
              session.append(
                pendingImage
              ) else {
            return
        }
        selectedPageID =
            session.pages.last?.id
        self.pendingImage = nil
        scannerCommand =
            .acceptAndContinue(
                id: UUID(),
                capturedPageCount:
                    session.pages.count
            )
        phase = .camera
    }

    private func saveAndFinish() {
        guard let pendingImage,
              session.append(
                pendingImage
              ) else {
            return
        }
        selectedPageID =
            session.pages.last?.id
        self.pendingImage = nil
        scannerCommand = .finish(
            id: UUID(),
            capturedPageCount:
                session.pages.count
        )
        phase = .pageReview
        UIAccessibility.post(
            notification:
                .screenChanged,
            argument: "스캔 페이지 검토"
        )
    }

    private func openSinglePageOCR() {
        guard let pendingImage else {
            return
        }
        scannerCommand = .finish(
            id: UUID(),
            capturedPageCount: 1
        )
        session.discard()
        appRouter.route =
            .OCRResult(
                image: pendingImage
            )
    }

    private func startAnotherPage() {
        guard session.canAddPage else {
            return
        }
        scannerCommand = .start(
            id: UUID()
        )
        phase = .camera
    }

    private func openScannedDocument() {
        guard !session.pages.isEmpty else {
            return
        }
        isPreparingDocument = true
        Task {
            do {
                let url =
                    try await session
                    .writeWorkingPDF()
                session.discard()
                isPreparingDocument = false
                appRouter.route =
                    .localDocument(
                        fileURL: url
                    )
            } catch {
                isPreparingDocument = false
                errorMessage =
                    error.localizedDescription
            }
        }
    }

    private func exportPDF() {
        guard !session.pages.isEmpty else {
            return
        }
        isPreparingDocument = true
        Task {
            do {
                let data =
                    try await session
                    .makePDFData()
                exportDocument =
                    ScannedPDFFileDocument(
                        data: data
                    )
                isPreparingDocument = false
                isExporting = true
            } catch {
                isPreparingDocument = false
                errorMessage =
                    error.localizedDescription
            }
        }
    }

    private func handleScannerCancel() {
        pendingImage = nil
        if session.pages.isEmpty {
            session.discard()
            dismiss()
        } else {
            phase = .pageReview
        }
    }

    private func requestClose() {
        guard !session.pages.isEmpty else {
            session.discard()
            dismiss()
            return
        }
        showsDiscardConfirmation = true
    }
}

private enum DocumentScannerCommand:
    Equatable
{
    case resume(id: UUID)
    case acceptAndContinue(
        id: UUID,
        capturedPageCount: Int
    )
    case finish(
        id: UUID,
        capturedPageCount: Int
    )
    case start(id: UUID)

    var id: UUID {
        switch self {
        case .resume(let id),
             .start(let id):
            return id
        case .acceptAndContinue(
            let id,
            _
        ),
        .finish(let id, _):
            return id
        }
    }
}

private struct DocumentScannerController:
    UIViewControllerRepresentable
{
    let remoteEvent:
        RivoScreenRemoteEvent?
    let command:
        DocumentScannerCommand?
    let isActive: Bool
    let automaticCaptureEnabled: Bool
    let curvedPageCorrectionEnabled: Bool
    let onScanCompleted:
        (UIImage) -> Void
    let onCancel:
        () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(
        context: Context
    ) -> DocumentScannerViewController {
        let controller =
            DocumentScannerViewController()
        controller.allowsAutomaticStart =
            isActive
        controller.automaticCaptureEnabled =
            automaticCaptureEnabled
        controller.curvedPageCorrectionEnabled =
            curvedPageCorrectionEnabled
        controller.onScanCompleted =
            onScanCompleted
        controller.onCancel = onCancel
        controller.synchronizeRemoteEventCursor(
            to: remoteEvent?.id
        )
        return controller
    }

    func updateUIViewController(
        _ controller:
            DocumentScannerViewController,
        context: Context
    ) {
        controller.onScanCompleted =
            onScanCompleted
        controller.onCancel = onCancel
        controller.allowsAutomaticStart =
            isActive
        controller.automaticCaptureEnabled =
            automaticCaptureEnabled
        controller.curvedPageCorrectionEnabled =
            curvedPageCorrectionEnabled

        if let remoteEvent,
           remoteEvent.id
            != context.coordinator
                .lastRemoteEventID,
           case .documentScanner(
               let action
           ) = remoteEvent.action {
            context.coordinator
                .lastRemoteEventID =
                remoteEvent.id
            controller.performRemoteAction(
                action,
                eventID: remoteEvent.id
            )
        }

        guard let command,
              command.id
                != context.coordinator
                    .lastCommandID else {
            return
        }
        context.coordinator.lastCommandID =
            command.id
        switch command {
        case .resume:
            controller.resumeAfterReview()
        case .acceptAndContinue(
            _,
            let capturedPageCount
        ):
            controller
                .acceptPageAndContinue(
                    capturedPageCount:
                        capturedPageCount
                )
        case .finish(
            _,
            let capturedPageCount
        ):
            controller.finishReview(
                capturedPageCount:
                    capturedPageCount
            )
        case .start:
            controller
                .startNewPageSession()
        }
    }

    final class Coordinator {
        var lastRemoteEventID:
            UInt64?
        var lastCommandID:
            UUID?
    }
}

private struct ScannedPDFFileDocument:
    FileDocument
{
    static var readableContentTypes:
        [UTType]
    {
        [.pdf]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(
        configuration:
            ReadConfiguration
    ) throws {
        data =
            configuration.file
            .regularFileContents
            ?? Data()
    }

    func fileWrapper(
        configuration:
            WriteConfiguration
    ) throws -> FileWrapper {
        FileWrapper(
            regularFileWithContents:
                data
        )
    }
}
