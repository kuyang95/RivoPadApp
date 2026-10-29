import SwiftUI
import UIKit

/// 홈. Android `compose/MainScreen.kt`와 같은 구성: 제목 줄(앱 이름·리모컨 상태·전체 설정),
/// 사용법 안내(5번째 방문부터 설정 오른쪽 아이콘), 그 아래 목록형 또는 카테고리형(2x2 타일).
/// 항목 목록은 여기에서 한 번만 정의하고 두 구성이 같이 쓴다.
struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var rivoRemoteManager: RivoRemoteManager
    @ObservedObject private var settings = AppSettingsStore.shared
    @ObservedObject private var appFonts = AppFontCatalogStore.shared
    @AppStorage(HomeLayoutMode.storageKey) private var homeLayoutModeRaw = HomeLayoutMode.list.rawValue
    @AppStorage(AppLauncherMode.mediaKey) private var showsMedia = true
    @AppStorage(HomeGuideVisitStore.storageKey) private var homeGuideVisitCount = 0
    @State private var isHomeVisible = false
    @State private var hasRecordedCurrentHomeVisit = false

    @State private var documentAppearance =
        LocalDocumentAppearanceStore().load()
    @State private var selectionDialog: HomeSelectionDialog?
    @State private var isImageAnalysisDialogPresented = false
    @State private var showsFontSelection = false
    @State private var openCategory: VisionCraftHomeCategory?
    @State private var hasConversations = false
    @ScaledMetric(relativeTo: .title2) private var homeTitleLineHeight: CGFloat = 32

    var body: some View {
        ZStack {
            VisionCraftHomeUI.background
                .ignoresSafeArea()

            GeometryReader { geometry in
                // Android 홈의 44/32는 화면 가장자리 기준이다. 안전 영역을 다시 더하지 않는다.
                let topPadding = max(0, 44 - geometry.safeAreaInsets.top)
                let bottomPadding = max(0, 32 - geometry.safeAreaInsets.bottom)
                Group {
                    if homeLayoutMode == .grid {
                        categoryHomeContent(
                            availableSize: geometry.size,
                            topPadding: topPadding,
                            bottomPadding: bottomPadding
                        )
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                listHomeContent
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, topPadding)
                            .padding(.bottom, bottomPadding)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .id(homeLayoutMode)
                .accessibilityHidden(isHomeDialogPresented)
                .allowsHitTesting(!isHomeDialogPresented)
            }

            HomeSettingsDialogs(
                selectionDialog: $selectionDialog,
                showsFontSelection: $showsFontSelection,
                documentAppearance: $documentAppearance,
                homeLayoutModeRaw: $homeLayoutModeRaw
            )

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
        }
        .tint(VisionCraftUI.primary)
        .background(VisionCraftHomeUI.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            isHomeVisible = true
            recordHomeVisitIfNeeded()
            refreshChatHistoryAvailability()
            // 설치 후 이전 화면 상태가 남아 있어도 사용자가 고른 홈 구성을 다시 적용한다.
            if let stored = UserDefaults.standard.string(forKey: HomeLayoutMode.storageKey),
               HomeLayoutMode(rawValue: stored) != nil,
               homeLayoutModeRaw != stored {
                homeLayoutModeRaw = stored
            }
        }
        .onDisappear {
            isHomeVisible = false
            hasRecordedCurrentHomeVisit = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                hasRecordedCurrentHomeVisit = false
            } else if phase == .active {
                recordHomeVisitIfNeeded()
            }
        }
        .onChange(of: showsMedia) { _, value in if !value && openCategory?.id == "media" { openCategory = nil } }
        .onChange(of: homeLayoutModeRaw) { _, _ in
            openCategory = nil
        }
        .onChange(of: openCategory?.id) { _, _ in
            UIAccessibility.post(
                notification: .screenChanged,
                argument: openCategory.map { AppLocalization.string($0.title) } ?? "VisionCraft"
            )
        }
        .accessibilityAction(.escape) {
            navigateBackFromCategory()
        }
        // 뷰어·설정 화면이 그 사이 저장한 값을 홈의 옛 스냅샷으로 덮어쓰지 않도록,
        // 돌아올 때 다시 읽고 바뀐 필드만 얹어 저장한다.
        .onAppear {
            documentAppearance = LocalDocumentAppearanceStore().load()
        }
        .onChange(of: documentAppearance) { old, value in
            let merged = LocalDocumentAppearanceStore()
                .save(changesFrom: old, to: value)
            if merged != value {
                documentAppearance = merged
            }
        }
    }

    private var isHomeDialogPresented: Bool {
        selectionDialog != nil
            || showsFontSelection
            || isImageAnalysisDialogPresented
    }

    private var homeLayoutMode: HomeLayoutMode {
        HomeLayoutMode(rawValue: homeLayoutModeRaw) ?? .list
    }

    private var showsCompactHomeGuide: Bool {
        homeGuideVisitCount >= HomeGuideVisitStore.iconVisitThreshold
    }

    private func recordHomeVisitIfNeeded() {
        guard isHomeVisible, scenePhase != .background, !hasRecordedCurrentHomeVisit else { return }
        hasRecordedCurrentHomeVisit = true
        homeGuideVisitCount = HomeGuideVisitStore.recordVisit()
    }

    // MARK: - 카테고리형

    private var homeCategories: [VisionCraftHomeCategory] {
        [
            VisionCraftHomeCategory(id: "ai", title: "AI 대화", tone: .ai, artName: "HomeTileAIChat", description: "궁금한 내용을 AI에게 물어보세요.", items: chatActions),
            // 카메라 기능은 홈에서 각각 선택해 들어간다.
            VisionCraftHomeCategory(id: "camera", title: "카메라/이미지", tone: .camera, artName: "HomeTileCamera", description: "확대해서 보고, 글자와 이미지를 인식하세요.", items: categoryCameraActions),
            VisionCraftHomeCategory(id: "reading", title: "텍스트/문서", tone: .reading, artName: "HomeTileReading", description: "글과 문서를 읽고 편집하세요.", items: readingActions.map(categoryMenuItem)),
            VisionCraftHomeCategory(id: "link", title: "비전링크", tone: .link, artName: "HomeTilePhoneLink", description: "스마트폰과 VisionCraft를 함께 사용하세요.", items: connectionActions),
        ] + (showsMedia ? [VisionCraftHomeCategory(id: "media", title: "미디어 탐색", tone: .link, artName: nil,
            systemImage: "globe", description: "웹과 영상을 편하게 찾아보세요.", items: mediaActions)] : [])
    }

    /// 카테고리의 기능 타일에만 쓰는 그림. 목록·카메라 내부 버튼은 기존 심벌을 쓴다.
    private func categoryActionArtName(for actionID: String) -> String? {
        switch actionID {
        case "new-chat": "HomeActionNewChat"
        case "chat-history": "HomeActionChatHistory"
        case "image-analysis-camera": "HomeActionDescribeImage"
        case "image-analysis-photo": "HomeActionDescribePhoto"
        case "magnifier": "HomeActionCamera"
        case "scanner": "HomeActionScanDoc"
        case "live-text": "HomeActionLiveReading"
        case "describe-image": "HomeActionDescribeImage"
        case "ask-ai": "HomeActionAskAI"
        case "photo-review": "HomeActionSavedPhotos"
        case "text-view": "HomeActionText"
        case "files": "HomeActionDocument"
        case "reader": "HomeActionBookReader"
        default: nil
        }
    }

    /// 홈의 첫 네 칸을 기준으로 크기와 위치를 고정하고, 기능의 추가 행만 아래로 이어진다.
    private func categoryHomeContent(
        availableSize: CGSize,
        topPadding: CGFloat,
        bottomPadding: CGFloat
    ) -> some View {
        let columns = availableSize.width > availableSize.height ? 4 : 2
        let rootCategories = homeCategories
        let categories = openCategory.map { category in
            category.items.map { item in
                VisionCraftHomeCategory(
                    id: item.id, title: item.title, tone: category.tone,
                    artName: categoryActionArtName(for: item.id), systemImage: item.icon, items: [item]
                )
            }
        } ?? rootCategories
        return ScrollView {
            VisionCraftHomeTilePageLayout(
                columns: columns,
                referenceItemCount: rootCategories.count,
                itemCount: categories.count,
                firstPageHeight: max(0, availableSize.height - topPadding - bottomPadding - 12)
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    if let openCategory {
                        // 원래 제목 행의 높이를 그대로 예약해 타일 시작 위치를 유지한다.
                        homeTitleRow.hidden().overlay(alignment: .leading) {
                            HStack(spacing: 0) {
                                VisionCraftBackButton { navigateBackFromCategory() }
                                    .padding(.trailing, 4)
                                homeHeaderTitle(openCategory.title)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else {
                        homeTitleRow
                    }
                    if !showsCompactHomeGuide {
                        sectionSpacer(height: 16)
                        VisionCraftHomeGuideEntry {
                            appRouter.route = .help
                        }
                    }
                    sectionSpacer(height: 20)
                }
                VisionCraftHomeCategoryGrid(
                    categories: categories,
                    columns: columns,
                    minimumTitleSize: openCategory == nil ? 0 : 16,
                    identifierPrefix: openCategory == nil ? "home.category" : "home.action"
                ) { category in
                    if openCategory != nil {
                        category.items.first?.action()
                    } else if category.items.count == 1 {
                        category.items[0].action()
                    } else {
                        openCategory = category
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding + 12)
        }
        .id(openCategory?.id ?? "home")
    }

    // MARK: - 목록형

    @ViewBuilder
    private var listHomeContent: some View {
        homeTitleRow

        if !showsCompactHomeGuide {
            sectionSpacer(height: 16)
            VisionCraftHomeGuideEntry {
                appRouter.route = .help
            }
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

        if showsMedia {
            sectionSpacer(height: 28)
            VisionCraftHomeSectionHeader(title: "미디어 탐색", tone: .link)
            VisionCraftHomeActionList(items: mediaActions)
        }

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

    private var mediaActions: [VisionCraftActionItem] {
        [VisionCraftActionItem(id: "easy-browser", icon: "globe", title: "쉬운 브라우저",
            description: "검색과 즐겨찾기로 웹을 둘러봅니다.", action: { appRouter.route = .easyBrowser }),
         VisionCraftActionItem(id: "easy-youtube", icon: "play.rectangle", title: "쉬운 유튜브",
            description: "큰 글자와 간단한 조작으로 영상을 봅니다.", action: { appRouter.route = .easyYouTube })]
    }

    private var chatActions: [VisionCraftActionItem] {
        var actions = [
            VisionCraftActionItem(
                id: "new-chat",
                icon: "doc.text",
                title: "새 대화",
                description:
                    "문서, 클립보드 내용, 사진을 첨부할 수 있습니다.",
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
                title: "대화 기록",
                description:
                    "이전 대화를 다시 엽니다.",
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
                title: "확대 보기",
                description:
                    "확대, 조명, 색상 필터를 사용합니다.",
                action: {
                    appRouter.route = .magnifier
                }
            ),
            VisionCraftActionItem(
                id: "scanner",
                icon: "doc.viewfinder",
                title: "문서 스캔",
                description:
                    "문서 한 장을 텍스트로 변환합니다.",
                action: {
                    appRouter.route = .documentScanning
                }
            ),
            VisionCraftActionItem(
                id: "live-text",
                icon: "text.viewfinder",
                title: "실시간 읽기",
                description:
                    "비춘 글자를 자동으로 읽어줍니다.",
                action: {
                    appRouter.route = .liveTextReader
                }
            ),
            VisionCraftActionItem(
                id: "describe-image",
                icon: "sparkles",
                title: "장면 설명",
                description:
                    "촬영한 장면을 AI가 설명합니다.",
                action: {
                    isImageAnalysisDialogPresented = true
                }
            ),
            VisionCraftActionItem(
                id: "ask-ai",
                icon: "bubble.left.and.bubble.right",
                title: "AI 질문",
                description: "촬영 후 AI에게 음성으로 묻습니다.",
                action: {
                    appRouter.route = .cameraAskAI
                }
            ),
            VisionCraftActionItem(
                id: "photo-review",
                icon: "photo.on.rectangle",
                title: "저장된 사진",
                description: "글자 인식, 번역, AI 설명과 대화를 이용합니다.",
                action: {
                    appRouter.route = .photoReview
                }
            ),
        ]
    }

    private var categoryCameraActions: [VisionCraftActionItem] {
        let actions = cameraActions
        return (Array(actions.prefix(3)) + actions.filter { $0.id == "ask-ai" } + [
                VisionCraftActionItem(
                    id: "image-analysis-camera", icon: "camera", title: "촬영 후 설명",
                    description: "촬영한 장면을 AI가 설명합니다.",
                    action: { appRouter.route = .imageDescriptionCamera }
                ),
                VisionCraftActionItem(
                    id: "image-analysis-photo", icon: "photo.on.rectangle", title: "사진 설명",
                    description: "AI 설명을 먼저 받고 다른 기능을 이용합니다.",
                    action: { appRouter.route = .imageAnalysisPhoto }
                ),
            ] + actions.filter { $0.id == "photo-review" }).map(categoryMenuItem)
    }

    /// 목록형의 이름·동작을 유지하면서 카테고리형 문구만 제공 목록에 맞춘다.
    private func categoryMenuItem(_ item: VisionCraftActionItem) -> VisionCraftActionItem {
        let title: String
        switch item.id {
        case "files": title = "home.category.documents"
        case "scanner": title = "home.category.scan"
        default: title = item.title
        }
        let description: String
        switch item.id {
        case "magnifier": description = "확대, 조명, 색상 필터로 봅니다."
        case "ask-ai": description = "촬영 후 음성으로 질문합니다."
        case "photo-review": description = "글자 인식, 번역, 설명 또는 AI 대화를 이용합니다."
        case "text-view": description = "텍스트를 크게 보고 편집합니다."
        case "files": description = "읽고 편집합니다."
        case "reader": description = "EPUB/DAISY 도서를 읽습니다."
        default: description = item.description
        }
        return VisionCraftActionItem(
            id: item.id, icon: item.icon, title: title,
            description: description, accent: item.accent, badge: item.badge, action: item.action
        )
    }

    private func navigateBackFromCategory() {
        openCategory = nil
    }

    private var readingActions: [VisionCraftActionItem] {
        [
            VisionCraftActionItem(
                id: "text-view",
                icon: "text.alignleft",
                title: "텍스트",
                description:
                    "글을 크게 보고 편집합니다.",
                action: {
                    openTextView()
                }
            ),
            // 문서 작업(엑셀·한글은 공통, 워드 편집은 iPadOS 전용).
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
                title: "도서 읽기",
                description:
                    "EPUB·DAISY 도서를 읽습니다.",
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
                title: "스마트폰 연결",
                description:
                    "스마트폰의 카메라, 사진, 문서를 VisionCraft에서 활용하세요.",
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
            homeHeaderTitle("VisionCraft")

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
            if showsCompactHomeGuide {
                VisionCraftIconButton(
                    systemImage: "questionmark.circle",
                    label: "사용 설명서 열기",
                    tint: VisionCraftHomeUI.guideIcon
                ) {
                    appRouter.route = .help
                }
                .accessibilityIdentifier("home.user-guide")
            }
        }
    }

    private func homeHeaderTitle(_ title: String) -> some View {
        Text(AppLocalization.string(title))
            .visionCraftAndroidText(24, weight: .bold, relativeTo: .title2)
            .frame(minHeight: homeTitleLineHeight)
            .foregroundStyle(VisionCraftHomeUI.text)
            .accessibilityAddTraits(.isHeader)
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
        .onAppear {
            documentAppearance = LocalDocumentAppearanceStore().load()
        }
        .onChange(of: documentAppearance) { old, value in
            let merged = LocalDocumentAppearanceStore()
                .save(changesFrom: old, to: value)
            if merged != value {
                documentAppearance = merged
            }
        }
    }
}

// MARK: - 설정 패널

/// Android `HomeSettingsContent`: 목록형 홈과 전체 설정 화면이 같이 쓰는 설정 그룹.
/// 그룹은 VcPanel, 값은 VcValueButton → VcOptionDialog, 켜고 끄는 항목은 VcSwitchRow.
struct HomeSettingsPanel: View {
    @AppStorage(AppLauncherMode.storageKey) private var launcherModeRaw = AppLauncherMode.standard.rawValue
    @AppStorage(AppLauncherMode.mediaKey) private var showsMedia = true
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
            #if DEBUG
            VisionCraftSettingsGroup(title: "개발") {
                NavigationLink {
                    DebugDevelopmentView()
                } label: {
                    Label("개발 화면", systemImage: "hammer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VisionCraftAndroidButtonStyle())
                .accessibilityHint("Debug 전용 개발 도구를 엽니다.")
            }
            #endif
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
                VisionCraftSettingValueTile(label: "런처 변경",
                    value: AppLocalization.string((AppLauncherMode(rawValue: launcherModeRaw) ?? .standard).title),
                    action: { selectionDialog = .launcher })
                VisionCraftSettingSwitchTile(label: "미디어 탐색 표시",
                    hint: "목록형과 카테고리형 홈에 미디어 탐색을 표시합니다.", isOn: $showsMedia)
                VisionCraftSettingValueTile(
                    label: "앱 테마",
                    value: AppLocalization.string(settings.appTheme.title),
                    action: { selectionDialog = .appTheme }
                )
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
    @EnvironmentObject private var appRouter: AppRouter
    @AppStorage(AppLauncherMode.storageKey) private var launcherModeRaw = AppLauncherMode.standard.rawValue
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
        case .appTheme:
            return settings.appTheme.rawValue
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
        case .launcher:
            return launcherModeRaw
        case .homeLayout:
            return homeLayoutModeRaw
        }
    }

    private func select(
        _ option: VisionCraftSelectionOption,
        for dialog: HomeSelectionDialog
    ) {
        switch dialog {
        case .appTheme:
            if let value = AppThemeMode(rawValue: option.id) {
                settings.appTheme = value
            }
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
        case .launcher:
            if let value = AppLauncherMode(rawValue: option.id) {
                launcherModeRaw = value.rawValue
                appRouter.requestSelectedHome()
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
            title: "장면 설명",
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

// MARK: - 값 고르기 목록

enum HomeSelectionDialog: String, Identifiable {
    case appTheme
    case speechRate
    case language
    case documentFontLevel
    case documentLineHeight
    case documentColor
    case quickMenuColor
    case homeLayout
    case launcher

    var id: String {
        rawValue
    }

    var isColorDialog: Bool {
        self == .documentColor || self == .quickMenuColor
    }

    var title: String {
        switch self {
        case .appTheme:
            return "앱 테마"
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
        case .launcher:
            return "런처 변경"
        case .homeLayout:
            return "홈 화면 구성"
        }
    }

    var options: [VisionCraftSelectionOption] {
        switch self {
        case .appTheme:
            return AppThemeMode.allCases.map {
                VisionCraftSelectionOption(id: $0.rawValue, title: AppLocalization.string($0.title))
            }
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
            let maximumLevel = self == .documentFontLevel ? 20 : 10
            return (1 ... maximumLevel).map {
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
        case .launcher:
            return AppLauncherMode.allCases.map { VisionCraftSelectionOption(id: $0.rawValue, title: AppLocalization.string($0.title)) }
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
