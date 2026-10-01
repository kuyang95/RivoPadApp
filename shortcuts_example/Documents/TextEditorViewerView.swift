import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Android VisionCraft의 TextEditorViewerScreen과 같은 역할을 하는 전용 화면이다.
/// 일반 PDF/문서 뷰어와 분리해, 가져온 텍스트를 큰 글자로 보고 바로 편집하는
/// 흐름과 화면 구성을 유지한다.
struct TextEditorViewerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var remoteControl:
        RivoScreenRemoteControlCenter

    @StateObject private var viewModel: LocalDocumentViewModel
    private let initialImage: UIImage?
    private let appearanceStore: LocalDocumentAppearanceStore

    @State private var appearance: LocalDocumentAppearance
    @State private var isEditing = false
    @State private var isReading = false
    @State private var isMenuPresented = false
    @State private var isSourceDialogPresented = false
    @State private var isSaveDialogPresented = false
    @State private var isColorDialogPresented = false
    @State private var isDocumentImporterPresented = false
    @State private var isPhotoPickerPresented = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isReplacingContent = false
    @State private var replacementStatus = ""
    @State private var sourceError: String?
    @State private var feedback: String?
    @State private var didLoadInitialContent = false
    @State private var isExporting = false
    @State private var exportFile: LocalDocumentExportFile?
    @State private var exportContentType: UTType = .plainText
    @State private var exportFileName = "VisionCraftText.txt"
    @State private var currentLineIndex = 0
    @State private var scrollTargetIndex = 0
    @State private var scrollRevision: UInt64 = 0
    /// Android `showClipboard`: the 클립보드 choice is only offered while the
    /// clipboard actually holds text.
    @State private var clipboardHasText = false

    init(fileURL: URL) {
        let store = LocalDocumentAppearanceStore()
        appearanceStore = store
        initialImage = nil
        _viewModel = StateObject(
            wrappedValue: LocalDocumentViewModel(fileURL: fileURL)
        )
        _appearance = State(initialValue: store.load())
    }

    init(title: String, text: String) {
        let store = LocalDocumentAppearanceStore()
        appearanceStore = store
        initialImage = nil
        _viewModel = StateObject(
            wrappedValue: LocalDocumentViewModel(
                title: title,
                text: text
            )
        )
        _appearance = State(initialValue: store.load())
    }

    init(image: UIImage) {
        let store = LocalDocumentAppearanceStore()
        appearanceStore = store
        initialImage = image
        _viewModel = StateObject(
            wrappedValue: LocalDocumentViewModel(
                title: AppLocalization.string("이미지 텍스트"),
                text: ""
            )
        )
        _appearance = State(initialValue: store.load())
    }

    var body: some View {
        ZStack {
            editorBackground
                .ignoresSafeArea()

            mainContent

            if showsOpenSourcePage {
                openSourcePage
                    .transition(.opacity)
            }

            if isMenuPresented {
                TextEditorMenuOverlay(
                    hasText: hasText,
                    isEditing: $isEditing,
                    appearance: $appearance,
                    editorBackground: editorBackground,
                    editorForeground: editorForeground,
                    onDismiss: {
                        isMenuPresented = false
                    },
                    onOpen: {
                        isMenuPresented = false
                        isSourceDialogPresented = true
                    },
                    onSave: {
                        isMenuPresented = false
                        isSaveDialogPresented = true
                    },
                    onSelectColor: {
                        isColorDialogPresented = true
                    },
                    onAskAI: openAIChat,
                    onRead: startReading
                )
                .transition(.opacity)
            }

            dialogOverlays

            if isReplacingContent {
                loadingOverlay
            }
        }
        .animation(.easeOut(duration: 0.16), value: isMenuPresented)
        // The route back button stays; the editor bar itself has no back.
        .visionCraftNavigationScreen()
        .task {
            await loadInitialContentIfNeeded()
        }
        .onAppear {
            refreshClipboardState()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )
        ) { _ in
            refreshClipboardState()
        }
        .onDisappear {
            stopReading()
        }
        .onChange(of: appearance) { _, newValue in
            appearanceStore.save(newValue)
        }
        .onChange(of: viewModel.text) { _, _ in
            currentLineIndex = 0
            stopReading()
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                await replaceContent(from: item)
            }
        }
        .onChange(of: remoteControl.latestEvent) { _, event in
            handleRemoteEvent(event)
        }
        .fileImporter(
            isPresented: $isDocumentImporterPresented,
            allowedContentTypes: VisionCraftFileTypes.documents,
            allowsMultipleSelection: false,
            onCompletion: handleDocumentImport
        )
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .fileExporter(
            isPresented: $isExporting,
            document: exportFile,
            contentType: exportContentType,
            defaultFilename: exportFileName
        ) { result in
            exportFile = nil
            switch result {
            case .success:
                showFeedback(
                    exportContentType == .pdf
                        ? AppLocalization.string("PDF 파일로 내보냈습니다.")
                        : AppLocalization.string("TXT 파일로 내보냈습니다.")
                )
            case .failure(let error):
                sourceError = error.localizedDescription
            }
        }
        .alert(
            "파일을 열 수 없습니다",
            isPresented: Binding(
                get: { sourceError != nil },
                set: { if !$0 { sourceError = nil } }
            )
        ) {
            Button("확인", role: .cancel) {
                sourceError = nil
            }
        } message: {
            Text(sourceError ?? "")
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.isLoading {
            ProgressView(
                viewModel.status.isEmpty
                    ? AppLocalization.string("문서를 여는 중")
                    : viewModel.status
            )
            .tint(editorForeground)
            .foregroundStyle(editorForeground)
        } else if let error = viewModel.errorDescription {
            ContentUnavailableView(
                "문서를 열 수 없습니다",
                systemImage: "doc.badge.ellipsis",
                description: Text(error)
            )
            .foregroundStyle(editorForeground)
        } else {
            editorScreen
        }
    }

    private var editorScreen: some View {
        VStack(spacing: 8) {
            editorTopBar
                .padding(.horizontal, 14)
                .padding(.top, 10)

            TextEditorCanvas(
                text: $viewModel.text,
                isEditing: isEditing,
                appearance: appearance,
                background: editorBackground,
                foreground: editorForeground,
                scrollTargetIndex: scrollTargetIndex,
                scrollRevision: scrollRevision
            )
        }
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            if let feedback {
                Text(feedback)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(VisionCraftUI.primaryText)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(
                        VisionCraftUI.surface,
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(VisionCraftUI.outline, lineWidth: 1)
                    }
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// Android `EditorMenuBar`: menu button on the left (48pt circle),
    /// pause while reading, nothing else. The route back button is above.
    private var editorTopBar: some View {
        HStack(spacing: 6) {
            editorTopButton(
                title: "에디터 메뉴 열기",
                systemImage: "line.3.horizontal"
            ) {
                isMenuPresented = true
            }

            if isReading {
                editorTopButton(
                    title: "읽기 일시정지",
                    systemImage: "pause.fill",
                    isCircular: false,
                    action: stopReading
                )
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Android `TopBarIconButton`: 48pt, surface fill + outline; the menu
    /// button is a circle with a 2pt border, the pause button a 12pt rect.
    private func editorTopButton(
        title: String,
        systemImage: String,
        isCircular: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .bold))
                .frame(
                    width: VisionCraftUI.minTouchTarget,
                    height: VisionCraftUI.minTouchTarget
                )
                .foregroundStyle(VisionCraftUI.primaryText)
                .background(VisionCraftUI.surface)
                .clipShape(
                    isCircular
                        ? AnyShape(Circle())
                        : AnyShape(
                            RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                        )
                )
                .overlay {
                    if isCircular {
                        Circle()
                            .stroke(VisionCraftUI.outline, lineWidth: 2)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(VisionCraftUI.outline, lineWidth: 1)
                    }
                }
                .contentShape(
                    isCircular
                        ? AnyShape(Circle())
                        : AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.string(title))
    }

    /// Android: the page stays while the text is empty, even after a
    /// cancelled picker, and the route back button closes the viewer.
    private var showsOpenSourcePage: Bool {
        !viewModel.isLoading
            && viewModel.errorDescription == nil
            && !hasText
            && !isEditing
    }

    /// Android `OpenSourcePage`: theme background, faint illustration behind,
    /// 28pt bold heading and three outlined `VcHomeSoftButton`s (max 320).
    private var openSourcePage: some View {
        ZStack {
            VisionCraftUI.background
                .ignoresSafeArea()

            Image("TextOpenSourceIllustration")
                .resizable()
                .scaledToFit()
                .padding(.horizontal, 40)
                .opacity(colorScheme == .dark ? 0.08 : 0.12)
                .accessibilityHidden(true)

            GeometryReader { geometry in
                ScrollView {
                VStack(spacing: 14) {
                    Text(AppLocalization.string("어떤 텍스트를 열까요?"))
                        .visionCraftAndroidText(28, weight: .bold, relativeTo: .title)
                        .foregroundStyle(VisionCraftUI.primaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 18)

                    if clipboardHasText {
                        openSourceButton(
                            title: "클립보드",
                            hint: "복사해 둔 텍스트를 붙여 넣습니다."
                        ) {
                            replaceContentFromClipboard()
                        }
                    }
                    openSourceButton(
                        title: "이미지에서 텍스트 읽어오기",
                        hint: "사진 앨범에서 고른 이미지의 글자를 읽어옵니다."
                    ) {
                        isPhotoPickerPresented = true
                    }
                    openSourceButton(
                        title: "문서",
                        hint: "파일 앱에서 텍스트·문서 파일을 엽니다."
                    ) {
                        isDocumentImporterPresented = true
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
                }
            }
        }
    }

    private func openSourceButton(
        title: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(AppLocalization.string(title))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(VisionCraftAndroidButtonStyle())
        .frame(maxWidth: 320)
        .accessibilityLabel(AppLocalization.string(title))
        .accessibilityHint(AppLocalization.string(hint))
    }

    private func refreshClipboardState() {
        clipboardHasText = UIPasteboard.general.hasStrings
    }

    @ViewBuilder
    private var dialogOverlays: some View {
        if isSourceDialogPresented {
            VisionCraftDialogCard(
                title: "열기",
                onDismiss: {
                    isSourceDialogPresented = false
                }
            ) {
                VisionCraftDialogOptionRow(
                    title: "클립보드",
                    systemImage: "doc.on.clipboard"
                ) {
                    isSourceDialogPresented = false
                    replaceContentFromClipboard()
                }
                VisionCraftDialogOptionRow(
                    title: "이미지에서 텍스트 읽어오기",
                    systemImage: "photo"
                ) {
                    isSourceDialogPresented = false
                    isPhotoPickerPresented = true
                }
                VisionCraftDialogOptionRow(
                    title: "문서",
                    systemImage: "doc.text"
                ) {
                    isSourceDialogPresented = false
                    isDocumentImporterPresented = true
                }
            }
        }

        if isSaveDialogPresented {
            VisionCraftDialogCard(
                title: "저장",
                onDismiss: {
                    isSaveDialogPresented = false
                }
            ) {
                VisionCraftDialogOptionRow(
                    title: "클립보드로 복사",
                    systemImage: "doc.on.doc",
                    isEnabled: hasText
                ) {
                    isSaveDialogPresented = false
                    copyToClipboard()
                }
                VisionCraftDialogOptionRow(
                    title: "TXT 파일로 내보내기",
                    systemImage: "doc.text",
                    isEnabled: hasText
                ) {
                    isSaveDialogPresented = false
                    beginExport(as: .plainText)
                }
                VisionCraftDialogOptionRow(
                    title: "PDF 로 내보내기",
                    systemImage: "doc.richtext",
                    isEnabled: hasText
                ) {
                    isSaveDialogPresented = false
                    beginExport(as: .pdf)
                }
            }
        }

        if isColorDialogPresented {
            TextEditorColorDialog(
                selectedIndex: appearance.colorIndex,
                onSelect: { index in
                    appearance.colorIndex = index
                    isColorDialogPresented = false
                },
                onDismiss: {
                    isColorDialogPresented = false
                }
            )
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
            ProgressView(
                replacementStatus.isEmpty
                    ? AppLocalization.string("문서를 여는 중")
                    : replacementStatus
            )
            .font(.headline)
            .padding(24)
            .background(
                VisionCraftUI.surface,
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
            .tint(VisionCraftUI.primary)
        }
    }

    private var hasText: Bool {
        !viewModel.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var editorTheme: LocalDocumentColorTheme {
        let themes = LocalDocumentColorTheme.all
        return themes[
            min(max(appearance.colorIndex, 0), themes.count - 1)
        ]
    }

    private var editorBackground: Color {
        Color(textEditorRGBHex: editorTheme.backgroundHex)
    }

    private var editorForeground: Color {
        Color(textEditorRGBHex: editorTheme.foregroundHex)
    }

    @MainActor
    private func loadInitialContentIfNeeded() async {
        guard !didLoadInitialContent else { return }
        didLoadInitialContent = true
        if let initialImage {
            await replaceContent(from: initialImage)
        } else {
            await viewModel.load()
        }
    }

    private func replaceContentFromClipboard() {
        guard let text = HomeTextSourcePolicy.availableClipboardText(
            UIPasteboard.general.string
        ) else {
            showFeedback(AppLocalization.string("클립보드가 비었습니다."))
            return
        }
        viewModel.text = text
        isEditing = false
        showFeedback(
            AppLocalization.string("클립보드 텍스트를 불러왔습니다.")
        )
    }

    private func handleDocumentImport(
        _ result: Result<[URL], Error>
    ) {
        Task {
            do {
                guard let sourceURL = try result.get().first else { return }
                await replaceContent(from: sourceURL)
            } catch {
                sourceError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func replaceContent(from sourceURL: URL) async {
        isReplacingContent = true
        replacementStatus = AppLocalization.string("문서를 여는 중")
        defer { isReplacingContent = false }
        do {
            let route = try await LocalFileOpening.route(for: sourceURL)
            guard case .localDocument(let importedURL) = route else {
                throw AuthorizedDocumentLibraryError.unsupportedDocument
            }
            let importedModel = LocalDocumentViewModel(fileURL: importedURL)
            await importedModel.load()
            if let error = importedModel.errorDescription {
                throw CocoaError(
                    .fileReadUnknown,
                    userInfo: [NSLocalizedDescriptionKey: error]
                )
            }
            guard !importedModel.text.isEmpty else {
                throw DocumentTextExtractor.ExtractError.noText
            }
            viewModel.text = importedModel.text
            isEditing = false
            showFeedback(
                AppLocalization.string("문서 텍스트를 불러왔습니다.")
            )
        } catch {
            sourceError = error.localizedDescription
        }
    }

    @MainActor
    private func replaceContent(from item: PhotosPickerItem) async {
        selectedPhotoItem = nil
        isReplacingContent = true
        replacementStatus = AppLocalization.string(
            "이미지에서 텍스트를 읽는 중…"
        )
        defer { isReplacingContent = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw TextEditorViewerError.invalidImage
            }
            try await recognizeImageAndReplace(image)
        } catch {
            sourceError = error.localizedDescription
        }
    }

    @MainActor
    private func replaceContent(from image: UIImage) async {
        isReplacingContent = true
        replacementStatus = AppLocalization.string(
            "이미지에서 텍스트를 읽는 중…"
        )
        defer { isReplacingContent = false }
        do {
            try await recognizeImageAndReplace(image)
        } catch {
            sourceError = error.localizedDescription
        }
    }

    @MainActor
    private func recognizeImageAndReplace(_ image: UIImage) async throws {
        let original = try await OCRService.shared.recognize(from: image)
        guard original != "(텍스트 없음)",
              !original.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty else {
            throw TextEditorViewerError.noImageText
        }
        let correctionEnabled = AppSettingsStore.shared
            .ocrAutoCorrectionEnabled
        if correctionEnabled {
            replacementStatus = AppLocalization.string("오타 교정 중")
        }
        let corrected = await GeminiOCRCorrectionService.shared.correct(
            image: image,
            originalText: original,
            isEnabled: correctionEnabled
        )
        guard !corrected.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw TextEditorViewerError.noImageText
        }
        viewModel.text = corrected
        isEditing = false
        showFeedback(
            AppLocalization.string("이미지 텍스트를 불러왔습니다.")
        )
    }

    private func copyToClipboard() {
        guard hasText else { return }
        UIPasteboard.general.string = viewModel.text
        showFeedback(
            AppLocalization.string("결과를 클립보드에 복사했습니다.")
        )
    }

    private func beginExport(as contentType: UTType) {
        guard hasText else { return }
        exportContentType = contentType
        if contentType == .pdf {
            exportFile = LocalDocumentExportBuilder.pdfFile(
                text: viewModel.text
            )
            exportFileName = "VisionCraftText.pdf"
        } else {
            exportFile = LocalDocumentExportBuilder.textFile(
                text: viewModel.text
            )
            exportFileName = "VisionCraftText.txt"
        }
        isExporting = true
    }

    private func openAIChat() {
        guard hasText else { return }
        isMenuPresented = false
        appRouter.route = .sharedTextQuestion(
            text: viewModel.text,
            automaticallyStartsVoiceInput: false
        )
    }

    private func startReading() {
        guard hasText else { return }
        isMenuPresented = false
        isReading = true
        TTSManager.shared.speak(viewModel.text) {
            isReading = false
        }
    }

    private func stopReading() {
        TTSManager.shared.stop()
        isReading = false
    }

    private func showFeedback(_ message: String) {
        feedback = message
        UIAccessibility.post(
            notification: .announcement,
            argument: message
        )
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if feedback == message {
                withAnimation {
                    feedback = nil
                }
            }
        }
    }

    private func handleRemoteEvent(_ event: RivoScreenRemoteEvent?) {
        guard let event,
              case .localDocumentReader(let action) = event.action else {
            return
        }
        isEditing = false
        if let updated = action.updatedAppearance(from: appearance) {
            appearance = updated
            return
        }

        switch action {
        case .beginning:
            moveRemote(to: 0)
        case .end:
            moveRemote(to: max(documentLines.count - 1, 0))
        case .previousLine:
            moveRemote(by: -1)
        case .nextLine:
            moveRemote(by: 1)
        case .previousPage:
            moveRemote(by: -5)
        case .nextPage:
            moveRemote(by: 5)
        case .toggleReading:
            isReading ? stopReading() : startReading()
        case .enterTextMode(let showGuide):
            if showGuide {
                showFeedback(
                    AppLocalization.string(
                        "문서 조작 모드. 1 처음, 2 이전 줄, 3 이전 페이지, 4 5 6 글자 크기, 7 끝, 8 다음 줄, 9 다음 페이지, 별표 0 샵 줄 간격"
                    )
                )
            }
        case .enterDisplayMode(let showGuide):
            if showGuide {
                showFeedback(
                    AppLocalization.string(
                        "색상 조작 모드. 4 이전 색상, 5 원본 색상, 6 다음 색상, R2 반전, L3 문서 조작"
                    )
                )
            }
        default:
            break
        }
    }

    private var documentLines: [LocalDocumentLine] {
        LocalDocumentTextSegmenter.lines(in: viewModel.text)
    }

    private func moveRemote(by offset: Int) {
        moveRemote(to: currentLineIndex + offset)
    }

    private func moveRemote(to index: Int) {
        guard !documentLines.isEmpty else { return }
        currentLineIndex = min(max(index, 0), documentLines.count - 1)
        scrollTargetIndex = currentLineIndex
        scrollRevision &+= 1
    }
}

private struct TextEditorCanvas: View {
    @Binding var text: String
    let isEditing: Bool
    let appearance: LocalDocumentAppearance
    let background: Color
    let foreground: Color
    let scrollTargetIndex: Int
    let scrollRevision: UInt64

    var body: some View {
        GeometryReader { geometry in
            let usesHorizontal = LocalDocumentLayoutPolicy.usesSingleLine(
                preferenceEnabled: appearance.usesSingleLineInLandscape,
                width: geometry.size.width,
                height: geometry.size.height
            )
            let rawFontSize = TextEditorLayoutPolicy.fontSize(
                level: appearance.fontLevel,
                availableWidth: geometry.size.width
            )
            let fontSize = usesHorizontal
                ? min(
                    rawFontSize,
                    max((geometry.size.height - 12) / 1.14, 58)
                )
                : rawFontSize
            let lineSpacing = usesHorizontal
                ? fontSize * 0.14
                : TextEditorLayoutPolicy.lineSpacing(
                    level: appearance.lineHeightLevel,
                    fontSize: fontSize
                )

            if usesHorizontal {
                horizontalContent(
                    fontSize: fontSize,
                    lineSpacing: lineSpacing,
                    viewportSize: geometry.size
                )
            } else {
                verticalContent(
                    fontSize: fontSize,
                    lineSpacing: lineSpacing
                )
            }
        }
        .background(background)
    }

    @ViewBuilder
    private func verticalContent(
        fontSize: CGFloat,
        lineSpacing: CGFloat
    ) -> some View {
        if isEditing {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(AppLocalization.string("여기에 텍스트를 입력하세요."))
                        .font(.system(size: fontSize))
                        .foregroundStyle(foreground.opacity(0.58))
                        .padding(.horizontal, 32)
                        .padding(.vertical, 30)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: fontSize))
                    .lineSpacing(lineSpacing)
                    .foregroundStyle(foreground)
                    .tint(foreground)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .accessibilityLabel("텍스트 편집")
            }
        } else {
            let lines = LocalDocumentTextSegmenter.lines(in: text)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if text.isEmpty {
                            Text(
                                AppLocalization.string(
                                    "여기에 텍스트를 입력하세요."
                                )
                            )
                            .foregroundStyle(foreground.opacity(0.58))
                        } else {
                            ForEach(lines) { line in
                                Text(line.text.isEmpty ? " " : line.text)
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                                    .id(line.index)
                                    .overlay(alignment: .bottom) {
                                        if appearance.showsLineSeparators {
                                            Rectangle()
                                                .fill(foreground.opacity(0.16))
                                                .frame(height: 1)
                                        }
                                    }
                            }
                        }
                    }
                    .font(.system(size: fontSize))
                    .lineSpacing(lineSpacing)
                    .foregroundStyle(foreground)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
                .onChange(of: scrollRevision) { _, _ in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(scrollTargetIndex, anchor: .top)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func horizontalContent(
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        viewportSize: CGSize
    ) -> some View {
        if isEditing {
            TextField(
                AppLocalization.string("여기에 텍스트를 입력하세요."),
                text: $text
            )
            .textFieldStyle(.plain)
            .font(.system(size: fontSize))
            .foregroundStyle(foreground)
            .tint(foreground)
            .padding(.horizontal, 28)
            .frame(
                width: viewportSize.width,
                height: viewportSize.height,
                alignment: .leading
            )
        } else {
            let chunks = text.isEmpty
                ? [AppLocalization.string("여기에 텍스트를 입력하세요.")]
                : TextEditorLayoutPolicy.singleLineChunks(text)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .center, spacing: 0) {
                    ForEach(chunks.indices, id: \.self) { index in
                        Text(chunks[index])
                            .font(.system(size: fontSize))
                            .lineSpacing(lineSpacing)
                            .foregroundStyle(
                                text.isEmpty
                                    ? foreground.opacity(0.58)
                                    : foreground
                            )
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.horizontal, 28)
                .frame(
                    minHeight: viewportSize.height,
                    alignment: .leading
                )
                .textSelection(.enabled)
            }
            .frame(
                width: viewportSize.width,
                height: viewportSize.height,
                alignment: .leading
            )
        }
    }
}

private struct TextEditorMenuOverlay: View {
    let hasText: Bool
    @Binding var isEditing: Bool
    @Binding var appearance: LocalDocumentAppearance
    let editorBackground: Color
    let editorForeground: Color
    let onDismiss: () -> Void
    let onOpen: () -> Void
    let onSave: () -> Void
    let onSelectColor: () -> Void
    let onAskAI: () -> Void
    let onRead: () -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 5
    )

    var body: some View {
        ZStack {
            VisionCraftUI.background
                .ignoresSafeArea()
            VStack(spacing: 16) {
                // Android `VcScreenTitleRow(title = 메뉴)` + 48pt close.
                VisionCraftScreenTitleRow(title: "메뉴") {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(VisionCraftUI.primaryText)
                            .frame(
                                width: VisionCraftUI.minTouchTarget,
                                height: VisionCraftUI.minTouchTarget
                            )
                            .background(VisionCraftUI.surface, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(VisionCraftUI.outline, lineWidth: 2)
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppLocalization.string("취소"))
                    .padding(.leading, 12)
                }

                ScrollView {
                    VStack(spacing: 12) {
                        menuSection(title: "파일") {
                            TextEditorMenuActionRow(
                                title: "열기",
                                systemImage: "doc.badge.plus",
                                action: onOpen
                            )
                            Divider().padding(.leading, 68)
                            TextEditorMenuActionRow(
                                title: "저장",
                                systemImage: "square.and.arrow.down",
                                isEnabled: hasText,
                                action: onSave
                            )
                            Divider().padding(.leading, 68)
                            TextEditorMenuToggleRow(
                                title: "텍스트 편집",
                                systemImage: "pencil",
                                isOn: $isEditing
                            )
                        }

                        menuSection(title: "보기") {
                            Text(
                                AppLocalization.format(
                                    "글자 크기 %lld",
                                    appearance.fontLevel
                                )
                            )
                            .font(.headline)
                            .foregroundStyle(VisionCraftUI.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(1 ... 10, id: \.self) { level in
                                    Button {
                                        appearance.fontLevel = level
                                    } label: {
                                        // 배경·프레임을 라벨 안에 둬야
                                        // 칸 전체가 터치 영역이 된다.
                                        // Android `FontLevelButton`: selected =
                                        // 2pt accent outline + accent text.
                                        Text(String(level))
                                            .visionCraftAndroidText(
                                                16,
                                                weight: appearance.fontLevel == level
                                                    ? .bold
                                                    : .medium
                                            )
                                            .foregroundStyle(
                                                appearance.fontLevel == level
                                                    ? VisionCraftUI.accent
                                                    : VisionCraftUI.primaryText
                                            )
                                            .frame(maxWidth: .infinity, minHeight: 48)
                                            .background(
                                                appearance.fontLevel == level
                                                    ? VisionCraftUI.accent.opacity(0.16)
                                                    : Color.clear,
                                                in: RoundedRectangle(
                                                    cornerRadius: 12,
                                                    style: .continuous
                                                )
                                            )
                                            .overlay {
                                                RoundedRectangle(
                                                    cornerRadius: 12,
                                                    style: .continuous
                                                )
                                                .stroke(
                                                    appearance.fontLevel == level
                                                        ? VisionCraftUI.accent
                                                        : VisionCraftUI.secondaryText.opacity(0.55),
                                                    lineWidth: appearance.fontLevel == level ? 2 : 1
                                                )
                                            }
                                            .contentShape(
                                                RoundedRectangle(
                                                    cornerRadius: 12,
                                                    style: .continuous
                                                )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(
                                        AppLocalization.format("글자 크기 %lld", level)
                                    )
                                    .accessibilityAddTraits(
                                        appearance.fontLevel == level
                                            ? .isSelected
                                            : []
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)

                            Divider().padding(.leading, 68)
                            TextEditorMenuActionRow(
                                title: "색상 선택",
                                systemImage: "paintpalette",
                                action: onSelectColor
                            ) {
                                HStack(spacing: 8) {
                                    Image(systemName: "paintpalette.fill")
                                    Text(editorThemeName)
                                        .lineLimit(1)
                                }
                                .font(.caption.bold())
                                .foregroundStyle(editorForeground)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(
                                    editorBackground,
                                    in: RoundedRectangle(
                                        cornerRadius: 10,
                                        style: .continuous
                                    )
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(VisionCraftUI.outline, lineWidth: 1)
                                }
                            }
                            Divider().padding(.leading, 68)
                            TextEditorMenuToggleRow(
                                title: "가로화면일 때 한줄로 보기",
                                systemImage: "arrow.left.and.right",
                                isOn: $appearance.usesSingleLineInLandscape
                            )
                            Divider().padding(.leading, 68)
                            TextEditorMenuToggleRow(
                                title: "행 구분선 표시",
                                systemImage: "doc.text",
                                isOn: $appearance.showsLineSeparators
                            )
                        }

                        menuSection(title: "도구") {
                            TextEditorMenuActionRow(
                                title: "AI 질문",
                                systemImage: "bubble.left.and.bubble.right",
                                isEnabled: hasText,
                                action: onAskAI
                            )
                            Divider().padding(.leading, 68)
                            TextEditorMenuActionRow(
                                title: "소리로 읽기시작",
                                systemImage: "speaker.wave.2",
                                isEnabled: hasText,
                                action: onRead
                            )
                        }
                    }
                    .padding(.bottom, 16)
                }
                .background(
                    VisionCraftUI.surface,
                    in: RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(VisionCraftUI.outline, lineWidth: 1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private var editorThemeName: String {
        let themes = LocalDocumentColorTheme.all
        return themes[
            min(max(appearance.colorIndex, 0), themes.count - 1)
        ].displayName
    }

    /// Android `MenuSection`: small secondary heading (titleSmall).
    private func menuSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Text(AppLocalization.string(title))
                .visionCraftAndroidText(14, weight: .semibold, relativeTo: .subheadline)
                .foregroundStyle(VisionCraftUI.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .background(VisionCraftUI.surface)
    }
}

private struct TextEditorMenuActionRow<Trailing: View>: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        systemImage: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
        self.trailing = trailing
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(
                        isEnabled
                            ? VisionCraftUI.primary
                            : VisionCraftUI.secondaryText.opacity(0.5)
                    )
                    .frame(width: 40, height: 40)
                    .background(
                        VisionCraftUI.surfaceVariant,
                        in: RoundedRectangle(
                            cornerRadius: 10,
                            style: .continuous
                        )
                    )
                Text(AppLocalization.string(title))
                    .font(.body.weight(.medium))
                    .foregroundStyle(
                        isEnabled
                            ? VisionCraftUI.primaryText
                            : VisionCraftUI.secondaryText.opacity(0.55)
                    )
                Spacer()
                trailing()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private extension TextEditorMenuActionRow where Trailing == EmptyView {
    init(
        title: String,
        systemImage: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            systemImage: systemImage,
            isEnabled: isEnabled,
            action: action,
            trailing: { EmptyView() }
        )
    }
}

private struct TextEditorMenuToggleRow: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(VisionCraftUI.primary)
                    .frame(width: 40, height: 40)
                    .background(
                        VisionCraftUI.surfaceVariant,
                        in: RoundedRectangle(
                            cornerRadius: 10,
                            style: .continuous
                        )
                    )
                Text(AppLocalization.string(title))
                    .font(.body.weight(.medium))
                    .foregroundStyle(VisionCraftUI.primaryText)
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.string(title))
        .accessibilityValue(
            AppLocalization.string(isOn ? "켜짐" : "꺼짐")
        )
    }
}

private struct TextEditorColorDialog: View {
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 14) {
                Text(AppLocalization.string("색상 선택"))
                    .font(.title2.bold())
                    .foregroundStyle(VisionCraftUI.primaryText)
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(
                            Array(LocalDocumentColorTheme.all.enumerated()),
                            id: \.offset
                        ) { index, theme in
                            Button {
                                onSelect(index)
                            } label: {
                                HStack {
                                    Text(theme.displayName)
                                        .font(.headline)
                                    Spacer()
                                    if index == selectedIndex {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                }
                                .foregroundStyle(
                                    Color(
                                        textEditorRGBHex: theme.foregroundHex
                                    )
                                )
                                .padding(.horizontal, 16)
                                .frame(minHeight: 54)
                                .background(
                                    Color(
                                        textEditorRGBHex: theme.backgroundHex
                                    ),
                                    in: RoundedRectangle(
                                        cornerRadius: 12,
                                        style: .continuous
                                    )
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(VisionCraftUI.outline, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button("취소", action: onDismiss)
                    .font(.headline)
                    .foregroundStyle(VisionCraftUI.primary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        VisionCraftUI.surfaceVariant,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
            }
            .padding(20)
            .frame(maxWidth: 520, maxHeight: 760)
            .background(
                VisionCraftUI.surface,
                in: RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
            )
            .padding(24)
        }
    }
}

nonisolated enum TextEditorLayoutPolicy {
    private static let targetCharactersPerLine: [CGFloat] = [
        14, 12, 10, 8, 6, 5, 4, 3, 2, 1,
    ]

    static func fontSize(
        level: Int,
        availableWidth: CGFloat
    ) -> CGFloat {
        let safeLevel = min(max(level, 1), 10)
        return max(
            58,
            availableWidth / targetCharactersPerLine[safeLevel - 1]
        )
    }

    static func lineSpacing(
        level: Int,
        fontSize: CGFloat
    ) -> CGFloat {
        fontSize * CGFloat(min(max(level, 1), 10) - 1) * 0.07
    }

    static func singleLineChunks(
        _ text: String,
        maximumCharacterCount: Int = 256
    ) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "   ")
            .replacingOccurrences(of: "\r", with: "   ")
            .replacingOccurrences(of: "\n", with: "   ")
        guard !normalized.isEmpty else { return [] }

        let chunkSize = max(maximumCharacterCount, 1)
        var chunks: [String] = []
        var start = normalized.startIndex
        while start < normalized.endIndex {
            let end = normalized.index(
                start,
                offsetBy: chunkSize,
                limitedBy: normalized.endIndex
            ) ?? normalized.endIndex
            chunks.append(String(normalized[start..<end]))
            start = end
        }
        return chunks
    }
}

private enum TextEditorViewerError: LocalizedError {
    case invalidImage
    case noImageText

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return AppLocalization.string("선택한 사진을 읽을 수 없습니다.")
        case .noImageText:
            return AppLocalization.string("이미지에서 텍스트를 찾지 못했습니다.")
        }
    }
}

private extension Color {
    init(textEditorRGBHex value: Int) {
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
