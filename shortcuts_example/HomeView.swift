import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PhotosUI

/// 홈. Android `compose/MainScreen.kt`와 같은 구성: 제목 줄(앱 이름·리모컨 상태·전체 설정),
/// 사용법 안내 카드, 그 아래 목록형(섹션 + 카드 + 설정 + 업데이트 기록) 또는 카테고리형(2x2 타일).
/// 항목 목록은 여기에서 한 번만 정의하고 두 구성이 같이 쓴다.
struct HomeView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var rivoRemoteManager: RivoRemoteManager
    @ObservedObject private var settings = AppSettingsStore.shared
    @ObservedObject private var appFonts = AppFontCatalogStore.shared
    @AppStorage(HomeLayoutMode.storageKey) private var homeLayoutModeRaw = HomeLayoutMode.list.rawValue

    @State private var documentAppearance =
        LocalDocumentAppearanceStore().load()
    @State private var isFileImporterPresented = false
    @State private var fileImportPurpose:
        HomeFileImportPurpose = .general
    @State private var isTextViewPhotoPickerPresented = false
    @State private var selectedTextViewPhotoItem:
        PhotosPickerItem?
    @State private var isLoadingTextViewPhoto = false
    @State private var fileImportError: String?
    @State private var selectionDialog: HomeSelectionDialog?
    @State private var isTextSourceDialogPresented = false
    @State private var isImageAnalysisDialogPresented = false
    @State private var textViewClipboardText: String?
    @State private var showsFontSelection = false
    @State private var openCategory: VisionCraftHomeCategory?
    @State private var hasConversations = false

    var body: some View {
        ZStack {
            VisionCraftHomeUI.background
                .ignoresSafeArea()

            GeometryReader { geometry in
                Group {
                    if homeLayoutMode == .grid {
                        categoryHomeContent(availableSize: geometry.size)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                listHomeContent
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 44)
                            .padding(.bottom, 32)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .id(homeLayoutMode)
                .accessibilityHidden(isHomeDialogPresented)
                .allowsHitTesting(!isHomeDialogPresented)
            }

            if let openCategory {
                VisionCraftHomeCategoryDialog(category: openCategory) {
                    self.openCategory = nil
                }
            }

            HomeSettingsDialogs(
                selectionDialog: $selectionDialog,
                showsFontSelection: $showsFontSelection,
                documentAppearance: $documentAppearance,
                homeLayoutModeRaw: $homeLayoutModeRaw
            )

            if isTextSourceDialogPresented {
                VisionCraftTextSourceDialog(
                    showsClipboard:
                        textViewClipboardText != nil,
                    onImage: {
                        presentTextViewPhotoPicker()
                    },
                    onDocument: {
                        presentTextViewDocumentImporter()
                    },
                    onClipboard: {
                        openClipboardInTextView()
                    },
                    onDismiss: {
                        isTextSourceDialogPresented = false
                        textViewClipboardText = nil
                    }
                )
            }

            if isImageAnalysisDialogPresented {
                HomeImageAnalysisDialog(
                    onCamera: {
                        isImageAnalysisDialogPresented = false
                        appRouter.route = .imageDescriptionCamera
                    },
                    onPhoto: {
                        isImageAnalysisDialogPresented = false
                        appRouter.route = .imageAnalysisPhoto
                    },
                    onDismiss: {
                        isImageAnalysisDialogPresented = false
                    }
                )
            }

            if isLoadingTextViewPhoto {
                Color.black.opacity(0.52)
                    .ignoresSafeArea()
                ProgressView(
                    AppLocalization.string(
                        "사진을 불러오는 중…"
                    )
                )
                .font(.headline)
                .padding(24)
                .visionCraftHomeSurface(cornerRadius: 24)
                .tint(VisionCraftUI.primary)
            }
        }
        .tint(VisionCraftUI.primary)
        .background(VisionCraftHomeUI.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes:
                fileImportPurpose.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .photosPicker(
            isPresented:
                $isTextViewPhotoPickerPresented,
            selection:
                $selectedTextViewPhotoItem,
            matching: .images
        )
        .alert(
            "파일을 열 수 없습니다",
            isPresented: Binding(
                get: { fileImportError != nil },
                set: { isPresented in
                    if !isPresented {
                        fileImportError = nil
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {
                fileImportError = nil
            }
        } message: {
            Text(fileImportError ?? "")
        }
        .onAppear {
            refreshChatHistoryAvailability()
            // 설치 후 이전 화면 상태가 남아 있어도 사용자가 고른 홈 구성을 다시 적용한다.
            if let stored = UserDefaults.standard.string(forKey: HomeLayoutMode.storageKey),
               HomeLayoutMode(rawValue: stored) != nil,
               homeLayoutModeRaw != stored {
                homeLayoutModeRaw = stored
            }
        }
        .onChange(of: documentAppearance) { _, value in
            LocalDocumentAppearanceStore().save(value)
        }
        .onChange(
            of: selectedTextViewPhotoItem
        ) { _, item in
            guard let item else {
                return
            }
            Task {
                await openTextViewPhoto(item)
            }
        }
        .onChange(of: appRouter.fileImportRequestID) {
            oldValue,
            newValue in
            guard newValue != oldValue else {
                return
            }
            fileImportPurpose = .general
            isFileImporterPresented = true
        }
        .onChange(of: appRouter.textSourceRequestID) {
            oldValue,
            newValue in
            guard newValue != oldValue else {
                return
            }
            presentTextSourceDialog()
        }
    }

    private var isHomeDialogPresented: Bool {
        selectionDialog != nil
            || showsFontSelection
            || openCategory != nil
            || isTextSourceDialogPresented
            || isImageAnalysisDialogPresented
            || isLoadingTextViewPhoto
    }

    private var homeLayoutMode: HomeLayoutMode {
        HomeLayoutMode(rawValue: homeLayoutModeRaw) ?? .list
    }

    // MARK: - 카테고리형

    private var homeCategories: [VisionCraftHomeCategory] {
        [
            VisionCraftHomeCategory(id: "ai", title: "AI 대화", tone: .ai, artName: "HomeTileAIChat", items: chatActions),
            // Android MainScreen: 카메라 타일은 카메라를 바로 연다. 문서 스캔·실시간 문자 읽기·
            // 이미지 분석·사진 분석은 카메라의 모드 버튼에서 들어간다.
            VisionCraftHomeCategory(id: "camera", title: "카메라", tone: .camera, artName: "HomeTileCamera", items: Array(cameraActions.prefix(1))),
            VisionCraftHomeCategory(id: "reading", title: "텍스트 · 문서", tone: .reading, artName: "HomeTileReading", items: readingActions),
            VisionCraftHomeCategory(id: "link", title: "비전링크", tone: .link, artName: "HomeTilePhoneLink", items: connectionActions),
        ]
    }

    /// 카테고리형은 스크롤 없이 한 화면에 맞춘다. 타일 비율 4:5를 유지하면서
    /// 화면 높이가 부족하면 타일 묶음의 너비를 줄이고 가로 가운데에 놓는다.
    private func categoryHomeContent(availableSize: CGSize) -> some View {
        let columns = availableSize.width > availableSize.height ? 4 : 2
        let categories = homeCategories
        return VStack(alignment: .leading, spacing: 0) {
            homeTitleRow
            sectionSpacer(height: 16)
            VisionCraftHomeGuideEntry {
                appRouter.route = .help
            }
            sectionSpacer(height: 20)
            GeometryReader { gridArea in
                let gap: CGFloat = 16
                let rows = max(1, (categories.count + columns - 1) / columns)
                let widthLimit = max(0, (gridArea.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns))
                let heightLimit = max(0, (gridArea.size.height - 12 - gap * CGFloat(rows - 1)) / CGFloat(rows) * 4 / 5)
                let tileWidth = min(widthLimit, heightLimit)
                let gridWidth = tileWidth * CGFloat(columns) + gap * CGFloat(columns - 1)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VisionCraftHomeCategoryGrid(
                        categories: categories,
                        columns: columns
                    ) { category in
                        if category.items.count == 1 {
                            category.items[0].action()
                        } else {
                            openCategory = category
                        }
                    }
                    .frame(width: gridWidth)
                    Spacer(minLength: 12)
                }
                .frame(width: gridArea.size.width, height: gridArea.size.height)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 44)
        .padding(.bottom, 32)
        .frame(width: availableSize.width, height: availableSize.height, alignment: .topLeading)
    }

    // MARK: - 목록형

    @ViewBuilder
    private var listHomeContent: some View {
        homeTitleRow

        sectionSpacer(height: 16)
        VisionCraftHomeGuideEntry {
            appRouter.route = .help
        }

        sectionSpacer(height: 28)
        VisionCraftHomeSectionHeader(title: "AI 대화", tone: .ai)
        VisionCraftHomeActionList(items: chatActions)

        sectionSpacer(height: 28)
        VisionCraftHomeSectionHeader(title: "카메라와 연결", tone: .camera)
        VisionCraftHomeActionList(items: cameraActions)

        sectionSpacer(height: 28)
        VisionCraftHomeSectionHeader(title: "읽기와 문서", tone: .reading)
        VisionCraftHomeActionList(items: readingActions)

        // 비전링크 카드는 섹션 제목 없이 28 띄워 이어 붙인다.
        sectionSpacer(height: 28)
        VisionCraftHomeActionList(items: connectionActions)

        sectionSpacer(height: 28)
        VisionCraftHomeSectionHeader(title: "설정", tone: .settings)
        HomeSettingsPanel(
            selectionDialog: $selectionDialog,
            showsFontSelection: $showsFontSelection,
            documentAppearance: $documentAppearance,
            homeLayoutModeRaw: $homeLayoutModeRaw
        )
        sectionSpacer(height: 20)
        VisionCraftHomeActionList(items: advancedSettingsActions)

        HomeUpdateNotesSection()
    }

    private func sectionSpacer(height: CGFloat) -> some View {
        Color.clear
            .frame(height: height)
            .accessibilityHidden(true)
    }

    // MARK: - 항목 목록 (두 구성이 같이 쓴다)

    private var chatActions: [VisionCraftActionItem] {
        var actions = [
            VisionCraftActionItem(
                id: "new-chat",
                icon: "doc.text",
                title: "새 대화",
                description:
                    "문서, 클립보드, 사진을 첨부해 새 대화를 시작합니다.",
                action: {
                    appRouter.route = .localChat(
                        conversationID: nil
                    )
                }
            ),
        ]
        if hasConversations {
            actions.append(VisionCraftActionItem(
                id: "chat-history",
                icon: "clock.arrow.circlepath",
                title: "대화기록",
                description:
                    "이전 AI 대화를 다시 엽니다.",
                action: {
                    appRouter.route = .chatHistory
                }
            ))
        }
        return actions
    }

    private func refreshChatHistoryAvailability() {
        Task {
            let conversations = try? await ChatHistoryStore.shared.allConversations()
            hasConversations = !(conversations?.isEmpty ?? true)
        }
    }

    private var cameraActions: [VisionCraftActionItem] {
        [
            VisionCraftActionItem(
                id: "magnifier",
                icon: "camera",
                title: "카메라",
                description:
                    "확대, 토치, 색상 필터로 가까운 대상을 봅니다.",
                action: {
                    appRouter.route = .magnifier
                }
            ),
            VisionCraftActionItem(
                id: "scanner",
                icon: "doc.viewfinder",
                title: "문서 스캔",
                description:
                    "문서 한 장을 촬영해 텍스트로 이어갑니다.",
                action: {
                    appRouter.route = .documentScanning
                }
            ),
            VisionCraftActionItem(
                id: "live-text",
                icon: "text.viewfinder",
                title: "실시간 문자 읽기",
                description:
                    "카메라 앞 글자를 자동으로 읽습니다.",
                action: {
                    appRouter.route = .liveTextReader
                }
            ),
            VisionCraftActionItem(
                id: "describe-image",
                icon: "sparkles",
                title: "이미지 분석",
                description:
                    "사진 속 내용을 AI가 설명해줍니다.",
                action: {
                    isImageAnalysisDialogPresented = true
                }
            ),
            VisionCraftActionItem(
                id: "photo-review",
                icon: "photo.on.rectangle",
                title: "사진 분석",
                description: "저장된 사진을 골라 글자 인식, 번역, 설명, AI 대화를 합니다.",
                action: {
                    appRouter.route = .photoReview
                }
            ),
        ]
    }

    private var readingActions: [VisionCraftActionItem] {
        [
            VisionCraftActionItem(
                id: "text-view",
                icon: "text.alignleft",
                title: "텍스트",
                description:
                    "클립보드의 글자를 큰 글자로 표시합니다.",
                action: {
                    openTextView()
                }
            ),
            // iPadOS 전용: 문서 작업(엑셀·워드·한글 편집).
            VisionCraftActionItem(
                id: "files",
                icon: "folder",
                title: "문서 작업",
                description:
                    "문서를 불러오거나 최근에 연 문서를 다시 엽니다.",
                action: {
                    appRouter.route = .documentLibrary
                }
            ),
            VisionCraftActionItem(
                id: "reader",
                icon: "book.closed",
                title: "데이지/EPUB 플레이어",
                description:
                    "EPUB/DAISY 도서를 이어 읽습니다.",
                action: {
                    appRouter.route = .readerLibrary
                }
            ),
        ]
    }

    private var connectionActions: [VisionCraftActionItem] {
        [
            VisionCraftActionItem(
                id: "vision-link",
                icon: "desktopcomputer",
                title: "스마트폰과 연동",
                description:
                    "원격 카메라를 사용하거나 스마트폰 파일을 받아옵니다.",
                action: {
                    appRouter.route = .visionLink
                }
            ),
        ]
    }

    /// iPadOS 전용 설정(스캐너·공유·독서·연결)으로 가는 카드.
    private var advancedSettingsActions:
        [VisionCraftActionItem] {
        [
            VisionCraftActionItem(
                id: "advanced-settings",
                icon: "gearshape",
                title: "모든 설정",
                description:
                    "스캐너, 공유, 독서와 연결 설정을 엽니다.",
                action: {
                    appRouter.route = .settings
                }
            ),
        ]
    }

    // MARK: - 제목 줄

    /// Android `VcScreenTitleRow`: 왼쪽 `VisionCraft`, 오른쪽에 리모컨 연결 상태 아이콘과 설정 아이콘(간격 0).
    private var homeTitleRow: some View {
        HStack(spacing: 0) {
            Text("VisionCraft")
                .visionCraftAndroidText(
                    24,
                    weight: .bold,
                    relativeTo: .title2
                )
                .foregroundStyle(VisionCraftHomeUI.text)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            VisionCraftHomeRemoteStatusIcon(
                eyebrow: "리모컨 연결",
                title: rivoHomeStatusTitle,
                subtitle: rivoHomeStatusDetail,
                systemImage: rivoStatusSystemImage,
                accent: rivoStatusColor,
                action: {
                    appRouter.route = .rivoRemote
                }
            )
            VisionCraftIconButton(
                systemImage: "gearshape",
                label: "전체 설정"
            ) {
                appRouter.route = .allSettings
            }
            .accessibilityIdentifier("home.all-settings")
        }
    }

    /// Android `VcHomeRemoteStatusIcon`: 연결됨 초록 / 연결 중 노랑 / 끊김 보조글자색.
    private var rivoStatusTone: HomeRemoteStatusTone {
        switch rivoRemoteManager.state {
        case .ready:
            return .connected
        case .preparing, .scanning, .connecting, .discovering:
            return .connecting
        case .inactive, .disconnected, .permissionDenied, .unsupported, .bluetoothOff, .failed:
            return .disconnected
        }
    }

    private var rivoHomeStatusTitle: String {
        switch rivoStatusTone {
        case .connected:
            return AppLocalization.string("연결됨")
        case .connecting:
            return AppLocalization.string("연결 중")
        case .disconnected:
            return AppLocalization.string("연결 안 됨")
        }
    }

    private var rivoHomeStatusDetail: String {
        switch rivoStatusTone {
        case .connected:
            return AppLocalization.string("조작 가능")
        case .connecting:
            return AppLocalization.string("상태 확인 중")
        case .disconnected:
            return AppLocalization.string("리모컨을 켜주세요")
        }
    }

    private var rivoStatusSystemImage: String {
        switch rivoStatusTone {
        case .connected, .connecting:
            return "dot.radiowaves.left.and.right"
        case .disconnected:
            return "antenna.radiowaves.left.and.right.slash"
        }
    }

    private var rivoStatusColor: Color {
        switch rivoStatusTone {
        case .connected:
            return VisionCraftHomeUI.connected
        case .connecting:
            return VisionCraftHomeUI.connecting
        case .disconnected:
            return VisionCraftHomeUI.secondaryText
        }
    }

    // MARK: - 텍스트 열기

    /// Android `readingItems`: 클립보드에 글이 있으면 바로 열고, 없을 때만 원본 고르는 화면을 연다.
    private func openTextView() {
        if let text = HomeTextSourcePolicy.availableClipboardText(
            UIPasteboard.general.string
        ) {
            appRouter.route = .textEditorText(
                title: AppLocalization.string("클립보드 텍스트"),
                text: text
            )
        } else {
            appRouter.route = .textEditorText(
                title: AppLocalization.string("텍스트"),
                text: ""
            )
        }
    }

    private func handleFileImport(
        _ result: Result<[URL], Error>
    ) {
        let purpose = fileImportPurpose
        fileImportPurpose = .general
        Task {
            do {
                guard let sourceURL = try result.get().first else {
                    return
                }
                let route = try await LocalFileOpening.route(
                    for: sourceURL
                )
                if purpose == .textDocument,
                   case .localDocument(let fileURL) = route {
                    appRouter.route = .textEditorDocument(
                        fileURL: fileURL
                    )
                } else {
                    appRouter.route = route
                }
            } catch {
                fileImportError = error.localizedDescription
            }
        }
    }

    private func presentTextSourceDialog() {
        textViewClipboardText =
            HomeTextSourcePolicy.availableClipboardText(
                UIPasteboard.general.string
            )
        isTextSourceDialogPresented = true
    }

    private func openClipboardInTextView() {
        guard let textViewClipboardText else {
            isTextSourceDialogPresented = false
            return
        }
        isTextSourceDialogPresented = false
        self.textViewClipboardText = nil
        appRouter.route = .textEditorText(
            title: AppLocalization.string(
                "클립보드 텍스트"
            ),
            text: textViewClipboardText
        )
    }

    private func presentTextViewPhotoPicker() {
        isTextSourceDialogPresented = false
        textViewClipboardText = nil
        Task { @MainActor in
            await Task.yield()
            isTextViewPhotoPickerPresented = true
        }
    }

    private func presentTextViewDocumentImporter() {
        isTextSourceDialogPresented = false
        textViewClipboardText = nil
        Task { @MainActor in
            await Task.yield()
            fileImportPurpose = .textDocument
            isFileImporterPresented = true
        }
    }

    @MainActor
    private func openTextViewPhoto(
        _ item: PhotosPickerItem
    ) async {
        isLoadingTextViewPhoto = true
        defer {
            isLoadingTextViewPhoto = false
            selectedTextViewPhotoItem = nil
        }
        do {
            guard let data = try await item
                .loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw HomeTextSourceImportError
                    .invalidImage
            }
            appRouter.route = .textEditorImage(
                image: image
            )
        } catch {
            fileImportError = error.localizedDescription
        }
    }
}

private enum HomeRemoteStatusTone {
    case connected, connecting, disconnected
}

// MARK: - 전체 설정 화면

/// Android `AllSettingsScreen`(`HomeSettings.kt`): 뒤로 가기 + 제목 + 설정 그룹(목록형 홈과 같은 패널).
/// 카테고리형일 때만 맨 아래에 업데이트 기록.
struct HomeAllSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(HomeLayoutMode.storageKey) private var homeLayoutModeRaw = HomeLayoutMode.list.rawValue
    @State private var documentAppearance =
        LocalDocumentAppearanceStore().load()
    @State private var selectionDialog: HomeSelectionDialog?
    @State private var showsFontSelection = false

    var body: some View {
        ZStack {
            VisionCraftHomeUI.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VisionCraftScreenTitleRow(
                        title: "전체 설정",
                        onBack: { dismiss() }
                    )
                    Color.clear.frame(height: 20).accessibilityHidden(true)
                    HomeSettingsPanel(
                        selectionDialog: $selectionDialog,
                        showsFontSelection: $showsFontSelection,
                        documentAppearance: $documentAppearance,
                        homeLayoutModeRaw: $homeLayoutModeRaw
                    )
                    if HomeLayoutMode(rawValue: homeLayoutModeRaw) == .grid {
                        HomeUpdateNotesSection()
                    }
                }
                .visionCraftScreenPadding(bottom: 32)
            }
            .accessibilityHidden(selectionDialog != nil || showsFontSelection)
            .allowsHitTesting(selectionDialog == nil && !showsFontSelection)

            HomeSettingsDialogs(
                selectionDialog: $selectionDialog,
                showsFontSelection: $showsFontSelection,
                documentAppearance: $documentAppearance,
                homeLayoutModeRaw: $homeLayoutModeRaw
            )
        }
        .tint(VisionCraftUI.primary)
        .toolbar(.hidden, for: .navigationBar)
        .visionCraftHandlesBackNavigation()
        .onChange(of: documentAppearance) { _, value in
            LocalDocumentAppearanceStore().save(value)
        }
    }
}

// MARK: - 설정 패널

/// Android `HomeSettingsContent`: 목록형 홈과 전체 설정 화면이 같이 쓰는 설정 그룹.
/// 그룹은 VcPanel, 값은 VcValueButton → VcOptionDialog, 켜고 끄는 항목은 VcSwitchRow.
struct HomeSettingsPanel: View {
    @ObservedObject private var settings = AppSettingsStore.shared
    @ObservedObject private var appFonts = AppFontCatalogStore.shared
    @Binding var selectionDialog: HomeSelectionDialog?
    @Binding var showsFontSelection: Bool
    @Binding var documentAppearance: LocalDocumentAppearance
    @Binding var homeLayoutModeRaw: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            mainFeedbackSettings
            voiceAndLanguageSettings
            appearanceSettings
            quickMenuSettings
            documentViewerSettings
        }
    }

    @ViewBuilder
    private var mainFeedbackSettings: some View {
        VisionCraftSettingsGroup {
            VisionCraftSettingsGrid {
                VisionCraftSettingSwitchTile(
                    label: "효과음 피드백",
                    hint:
                        "버튼 조작과 기능 실행 상태를 효과음으로 알려줍니다.",
                    isOn:
                        $settings.soundEffectsEnabled
                )
                VisionCraftSettingSwitchTile(
                    label: "음성 피드백",
                    hint:
                        "기능 실행 상태와 안내 메시지를 음성으로 알려줍니다.",
                    isOn:
                        $settings.voiceFeedbackEnabled
                )
                VisionCraftSettingSwitchTile(
                    label: "OCR 오타 자동 교정",
                    hint:
                        "OCR로 인식한 글자의 오타를 AI가 자동으로 교정합니다.",
                    isOn:
                        $settings.ocrAutoCorrectionEnabled
                )
                VisionCraftSettingSwitchTile(
                    label: "문서 스캔 색상 자동 보정",
                    hint:
                        "촬영한 문서의 배경을 밝게 하고 글자 대비를 높입니다.",
                    isOn:
                        $settings.documentScanColorEnhancementEnabled
                )
            }
        }
    }

    @ViewBuilder
    private var voiceAndLanguageSettings: some View {
        VisionCraftSettingsGroup(title: "음성 및 언어") {
            VisionCraftSettingsGrid {
                VisionCraftSettingValueTile(
                    label: "음성 속도",
                    value: settings.speechRate.androidTitle,
                    action: {
                        selectionDialog = .speechRate
                    }
                )
                VisionCraftSettingValueTile(
                    label: "언어",
                    value: settings.appLanguage.title,
                    action: {
                        selectionDialog = .language
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var appearanceSettings: some View {
        VisionCraftSettingsGroup(title: "화면 및 글꼴") {
            VisionCraftSettingsGrid {
                VisionCraftSettingValueTile(
                    label: "앱 글꼴",
                    value:
                        appFonts.selectedLabel(
                            languageCode:
                                settings.appLanguage
                                .effectiveLanguageCode
                        ),
                    action: {
                        showsFontSelection = true
                    }
                )
                VisionCraftSettingValueTile(
                    label: "홈 화면 구성",
                    value: AppLocalization.string(
                        (HomeLayoutMode(rawValue: homeLayoutModeRaw) ?? .list).title
                    ),
                    action: {
                        selectionDialog = .homeLayout
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var quickMenuSettings: some View {
        VisionCraftSettingsGroup(title: "메뉴바") {
            VisionCraftSettingsGrid {
                VisionCraftSettingSwitchTile(
                    label: "메뉴바 펼쳐보기",
                    hint:
                        "메뉴 항목을 위에서 아래로 한 번에 펼쳐 표시합니다.",
                    isOn:
                        $settings.rivoQuickMenuExpanded
                )
                VisionCraftColorSettingTile(
                    label: "리모컨 조작 메뉴 색 조합",
                    theme: LocalDocumentColorTheme.theme(at: settings.rivoQuickMenuColorIndex),
                    action: {
                        selectionDialog = .quickMenuColor
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var documentViewerSettings: some View {
        VisionCraftSettingsGroup(title: "텍스트 뷰어") {
            VisionCraftSettingsGrid {
                VisionCraftSettingValueTile(
                    label: "텍스트뷰어 글씨 크기",
                    value: "\(documentAppearance.fontLevel)",
                    action: {
                        selectionDialog = .documentFontLevel
                    }
                )
                VisionCraftSettingValueTile(
                    label: "텍스트뷰어 줄 간격",
                    value:
                        "\(documentAppearance.lineHeightLevel)",
                    action: {
                        selectionDialog = .documentLineHeight
                    }
                )
                VisionCraftColorSettingTile(
                    label: "텍스트뷰어 색 조합",
                    theme: LocalDocumentColorTheme.theme(at: documentAppearance.colorIndex),
                    action: {
                        selectionDialog = .documentColor
                    }
                )
            }
        }
    }
}

/// 설정 값 고르기 다이얼로그(Android `HomeSettingsDialogs`): `VcOptionDialog` 한 벌.
/// 색 조합은 각 줄을 그 색으로 칠하고 "가 나 다 라" 미리보기, 글꼴은 그 글꼴로 이름을 보여 준다.
struct HomeSettingsDialogs: View {
    @ObservedObject private var settings = AppSettingsStore.shared
    @ObservedObject private var appFonts = AppFontCatalogStore.shared
    @Binding var selectionDialog: HomeSelectionDialog?
    @Binding var showsFontSelection: Bool
    @Binding var documentAppearance: LocalDocumentAppearance
    @Binding var homeLayoutModeRaw: String

    var body: some View {
        if let selectionDialog {
            VisionCraftSelectionDialog(
                title: selectionDialog.title,
                options: selectionDialog.options,
                selectedID: selectedID(for: selectionDialog),
                onSelect: { select($0, for: selectionDialog) },
                onDismiss: { self.selectionDialog = nil },
                markSelected: selectionDialog.isColorDialog,
                rowSpacing: selectionDialog.isColorDialog ? 8 : 0
            )
        }

        if showsFontSelection {
            fontSelectionDialog
        }
    }

    /// Android `AppFontSelectorDialog`: 글꼴 이름을 그 글꼴로, 받는 중이면 "다운로드 중",
    /// 목록을 불러오는 중·오류는 목록 위 안내. 글꼴을 받는 동안에는 닫지 않는다.
    private var fontSelectionDialog: some View {
        let languageCode = settings.appLanguage.effectiveLanguageCode
        let options = appFonts.visibleOptions(languageCode: languageCode)
        var notices: [VisionCraftSelectionNotice] = []
        if appFonts.isManifestLoading, options.count <= 2 {
            notices.append(VisionCraftSelectionNotice(
                text: AppLocalization.string("폰트 목록을 불러오는 중입니다.")
            ))
        }
        if let errorMessage = appFonts.errorMessage {
            notices.append(VisionCraftSelectionNotice(
                text: AppLocalization.format("폰트를 불러오지 못했습니다. %@", errorMessage),
                isError: true
            ))
        }
        return VisionCraftSelectionDialog(
            title: "앱 글꼴 선택",
            options: options.map { option in
                VisionCraftSelectionOption(
                    id: option.key,
                    title: option.label(languageCode: languageCode),
                    supportingText: appFonts.downloadingKey == option.key
                        ? AppLocalization.string("다운로드 중")
                        : nil,
                    fontName: previewFontName(for: option)
                )
            },
            selectedID: appFonts.effectiveOption(languageCode: languageCode).key,
            onSelect: { selected in
                guard appFonts.downloadingKey == nil,
                      let option = options.first(where: { $0.key == selected.id })
                else { return }
                Task { @MainActor in
                    if await appFonts.select(option) {
                        showsFontSelection = false
                    }
                }
            },
            onDismiss: { showsFontSelection = false },
            notices: notices
        )
    }

    private func previewFontName(for option: AppFontOption) -> String? {
        if option.isSystem {
            return nil
        }
        if option.isBundled {
            return AppFontCatalogStore.bundledFontName
        }
        if appFonts.activeRemoteKey == option.key {
            return appFonts.activeRemoteFontName
        }
        return nil
    }

    private func selectedID(
        for dialog: HomeSelectionDialog
    ) -> String {
        switch dialog {
        case .speechRate:
            return settings.speechRate.rawValue
        case .language:
            return settings.appLanguage.rawValue
        case .documentFontLevel:
            return String(documentAppearance.fontLevel)
        case .documentLineHeight:
            return String(documentAppearance.lineHeightLevel)
        case .documentColor:
            return String(documentAppearance.colorIndex)
        case .quickMenuColor:
            return String(settings.rivoQuickMenuColorIndex)
        case .homeLayout:
            return homeLayoutModeRaw
        }
    }

    private func select(
        _ option: VisionCraftSelectionOption,
        for dialog: HomeSelectionDialog
    ) {
        switch dialog {
        case .speechRate:
            if let value = AppSpeechRate(rawValue: option.id) {
                settings.speechRate = value
            }
        case .language:
            if let value = AppLanguage(rawValue: option.id) {
                settings.appLanguage = value
            }
        case .documentFontLevel:
            if let value = Int(option.id) {
                documentAppearance.fontLevel = value
            }
        case .documentLineHeight:
            if let value = Int(option.id) {
                documentAppearance.lineHeightLevel = value
            }
        case .documentColor:
            if let value = Int(option.id) {
                documentAppearance.colorIndex = value
            }
        case .quickMenuColor:
            if let value = Int(option.id) {
                settings.rivoQuickMenuColorIndex = value
            }
        case .homeLayout:
            if let value = HomeLayoutMode(rawValue: option.id) {
                homeLayoutModeRaw = value.rawValue
            }
        }
        selectionDialog = nil
    }
}

// MARK: - 업데이트 기록

/// Android `HomeUpdateNotesSection` + `ChangeLogInfoUI`: 최신 버전 카드(버전 24 Bold + "(날짜)" 한 줄,
/// 구분선, 항목마다 "- ") + "이전 업데이트 기록보기" 글자 버튼.
struct HomeUpdateNotesSection: View {
    @EnvironmentObject private var appRouter: AppRouter
    @ObservedObject private var settings = AppSettingsStore.shared

    var body: some View {
        if let note = latestReleaseNote {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 32).accessibilityHidden(true)
                VisionCraftHomeSectionHeader(title: "업데이트 기록", tone: .updates)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(note.version)
                            .visionCraftAndroidText(24, weight: .bold, relativeTo: .title2)
                            .foregroundStyle(VisionCraftHomeUI.text)
                        Text("(\(note.date))")
                            .visionCraftAndroidText(14)
                            .foregroundStyle(VisionCraftHomeUI.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                    Divider()
                        .overlay(VisionCraftHomeUI.outline.opacity(0.4))
                        .padding(.vertical, 8)
                    ForEach(Array(note.texts.enumerated()), id: \.offset) { _, text in
                        Text("- \(text)")
                            .visionCraftAndroidText(16)
                            .foregroundStyle(VisionCraftHomeUI.text)
                            .padding(.leading, 16)
                            .padding(.bottom, 4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    VisionCraftHomeUI.surface,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )

                Button {
                    appRouter.route = .releaseNotes
                } label: {
                    Text(AppLocalization.string("이전 업데이트 기록보기"))
                        .visionCraftAndroidText(16, weight: .medium)
                        .foregroundStyle(VisionCraftHomeUI.text)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(VisionCraftHomePressStyle())
                .padding(.top, 12)
            }
        }
    }

    private var latestReleaseNote: HelpReleaseNote? {
        try? HelpContentLibrary
            .releaseNotes(
                language: settings.appLanguage
            )
            .first
    }
}

// MARK: - 이미지 분석 선택

/// Android `MainScreenContent`의 이미지 분석 다이얼로그: 설명 + "촬영하기" / "사진에서".
private struct HomeImageAnalysisDialog: View {
    let onCamera: () -> Void
    let onPhoto: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VisionCraftDialogCard(
            title: "이미지 분석",
            message: "촬영하거나 사진을 선택하면 내용을 설명하고 클립보드에 복사합니다.",
            tone: .camera,
            onDismiss: onDismiss
        ) {
            VisionCraftDialogOptionRow(
                title: "촬영하기",
                subtitle: "카메라로 찍은 장면을 설명합니다.",
                systemImage: "camera",
                accent: VisionCraftHomeUI.logoAccent(4),
                action: onCamera
            )
            VisionCraftDialogOptionRow(
                title: "사진에서",
                subtitle: "저장된 사진을 골라 설명합니다.",
                systemImage: "photo.on.rectangle",
                accent: VisionCraftHomeUI.logoAccent(5),
                action: onPhoto
            )
        }
    }
}

// MARK: - 파일·텍스트 원본

private enum HomeFileImportPurpose: Equatable {
    case general
    case textDocument

    var allowedContentTypes: [UTType] {
        switch self {
        case .general:
            return VisionCraftFileTypes.openable
        case .textDocument:
            return VisionCraftFileTypes.documents
        }
    }
}

private enum HomeTextSourceImportError:
    LocalizedError
{
    case invalidImage

    var errorDescription: String? {
        AppLocalization.string(
            "선택한 사진을 읽을 수 없습니다."
        )
    }
}

nonisolated enum HomeTextSourcePolicy {
    static func availableClipboardText(
        _ text: String?
    ) -> String? {
        guard let text,
              !text.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty else {
            return nil
        }
        return text
    }
}

/// 리모컨·단축어에서 텍스트 원본을 고르라고 요청했을 때 쓰는 다이얼로그.
private struct VisionCraftTextSourceDialog: View {
    let showsClipboard: Bool
    let onImage: () -> Void
    let onDocument: () -> Void
    let onClipboard: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VisionCraftDialogCard(
            title: "열기",
            tone: .reading,
            onDismiss: onDismiss
        ) {
            if showsClipboard {
                VisionCraftDialogOptionRow(
                    title: "클립보드",
                    subtitle: "복사해 둔 텍스트를 붙여 넣습니다.",
                    systemImage: "doc.on.clipboard",
                    isPrimary: true,
                    accent: VisionCraftHomeUI.logoAccent(0),
                    action: onClipboard
                )
            }
            VisionCraftDialogOptionRow(
                title: "이미지에서 텍스트 읽어오기",
                subtitle: "사진 앨범에서 고른 이미지의 글자를 읽어옵니다.",
                systemImage: "photo",
                accent: VisionCraftHomeUI.logoAccent(1),
                action: onImage
            )
            VisionCraftDialogOptionRow(
                title: "문서",
                subtitle: "파일 앱에서 텍스트·문서 파일을 엽니다.",
                systemImage: "doc.text",
                accent: VisionCraftHomeUI.logoAccent(2),
                action: onDocument
            )
        }
    }
}

// MARK: - 값 고르기 목록

enum HomeSelectionDialog: String, Identifiable {
    case speechRate
    case language
    case documentFontLevel
    case documentLineHeight
    case documentColor
    case quickMenuColor
    case homeLayout

    var id: String {
        rawValue
    }

    var isColorDialog: Bool {
        self == .documentColor || self == .quickMenuColor
    }

    var title: String {
        switch self {
        case .speechRate:
            return "음성 속도"
        case .language:
            return "언어"
        case .documentFontLevel:
            return "텍스트뷰어 글씨 크기"
        case .documentLineHeight:
            return "텍스트뷰어 줄 간격"
        case .documentColor:
            return "텍스트뷰어 색 조합"
        case .quickMenuColor:
            return "리모컨 조작 메뉴 색 조합"
        case .homeLayout:
            return "홈 화면 구성"
        }
    }

    var options: [VisionCraftSelectionOption] {
        switch self {
        case .speechRate:
            return AppSpeechRate.allCases.map {
                VisionCraftSelectionOption(
                    id: $0.rawValue,
                    title: $0.androidTitle
                )
            }
        case .language:
            return AppLanguage.allCases.map {
                VisionCraftSelectionOption(
                    id: $0.rawValue,
                    title: $0.title
                )
            }
        case .documentFontLevel,
             .documentLineHeight:
            return (1 ... 10).map {
                VisionCraftSelectionOption(
                    id: String($0),
                    title: "\($0)"
                )
            }
        case .documentColor,
             .quickMenuColor:
            // Android `ColorSetSelectorDialog`: 줄마다 그 색 조합으로 "가 나 다 라", 읽기는 색 이름.
            return LocalDocumentColorTheme.all
                .enumerated()
                .map { index, theme in
                    VisionCraftSelectionOption(
                        id: String(index),
                        title: "가 나 다 라",
                        swatch: VisionCraftSelectionSwatch(theme: theme),
                        accessibilityLabel: theme.displayName
                    )
                }
        case .homeLayout:
            return HomeLayoutMode.allCases.map {
                VisionCraftSelectionOption(id: $0.rawValue, title: AppLocalization.string($0.title))
            }
        }
    }
}

/// Android `HomeLayoutController`: 목록형(기본) / 카테고리형. 설정에서 고르면 바로 바뀐다.
enum HomeLayoutMode: String, CaseIterable {
    case list
    case grid

    static let storageKey = "visioncraft.home.layout"

    var title: String {
        switch self {
        case .list: "목록형"
        case .grid: "카테고리형"
        }
    }
}

extension LocalDocumentColorTheme {
    static func theme(at index: Int) -> LocalDocumentColorTheme {
        let themes = LocalDocumentColorTheme.all
        guard !themes.isEmpty else {
            preconditionFailure("VisionCraft color themes must not be empty")
        }
        return themes[min(max(index, 0), themes.count - 1)]
    }
}

extension AppSpeechRate {
    var androidTitle: String {
        switch self {
        case .slow:
            return AppLocalization.string("천천히")
        case .normal:
            return AppLocalization.string("자연스럽게")
        case .fast:
            return AppLocalization.string("빠르게")
        case .veryFast:
            return AppLocalization.string("아주 빠르게")
        }
    }
}
