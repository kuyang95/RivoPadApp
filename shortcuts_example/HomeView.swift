import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PhotosUI

struct HomeView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var rivoRemoteManager: RivoRemoteManager
    @ObservedObject private var settings = AppSettingsStore.shared
    @ObservedObject private var appFonts = AppFontCatalogStore.shared

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
    @State private var textViewClipboardText: String?
    @State private var showsFontSelection = false

    var body: some View {
        ZStack {
            VisionCraftHomeUI.background
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    androidParityHomeContent
                    updateContent
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .accessibilityHidden(isHomeDialogPresented)
            .allowsHitTesting(!isHomeDialogPresented)

            if let selectionDialog {
                VisionCraftSelectionDialog(
                    title: selectionDialog.title,
                    options: selectionDialog.options,
                    selectedID:
                        selectedID(
                            for: selectionDialog
                        ),
                    onSelect: { option in
                        select(
                            option,
                            for: selectionDialog
                        )
                    },
                    onDismiss: {
                        self.selectionDialog = nil
                    }
                )
            }

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
        .sheet(isPresented: $showsFontSelection) {
            AppFontSelectionView(
                catalog: appFonts,
                languageCode:
                    settings.appLanguage
                    .effectiveLanguageCode
            )
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
        selectionDialog != nil || isTextSourceDialogPresented || isLoadingTextViewPhoto
    }

    @ViewBuilder
    private var androidParityHomeContent: some View {
        homeTitleRow

        sectionSpacer(height: 16)
        VisionCraftHomeGuideEntry {
            appRouter.route = .help
        }

        sectionSpacer(height: 28)
        VisionCraftHomeSectionHeader(title: "AI 챗", tone: .ai)
        VisionCraftHomeActionList(items: chatActions)

        sectionSpacer(height: 28)
        VisionCraftHomeSectionHeader(title: "카메라와 연결", tone: .camera)
        VisionCraftHomeActionList(items: cameraActions)

        sectionSpacer(height: 28)
        VisionCraftHomeSectionHeader(title: "읽기와 문서", tone: .reading)
        VisionCraftHomeActionList(items: readingActions)

        // 연결 항목은 헤더 없이 바로 이어 붙인다.
        sectionSpacer(height: 16)
        VisionCraftHomeActionList(items: connectionActions)

        sectionSpacer(height: 28)
        VisionCraftHomeSectionHeader(title: "설정", tone: .settings)
        mainFeedbackSettings

        sectionSpacer(height: 20)
        voiceAndLanguageSettings

        sectionSpacer(height: 20)
        appearanceSettings

        sectionSpacer(height: 20)
        quickMenuSettings

        sectionSpacer(height: 20)
        documentViewerSettings

        sectionSpacer(height: 20)
        VisionCraftHomeActionList(
            items: advancedSettingsActions
        )
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
                    theme: quickMenuTheme,
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
                    value: "\(documentAppearance.fontLevel)단계",
                    action: {
                        selectionDialog = .documentFontLevel
                    }
                )
                VisionCraftSettingValueTile(
                    label: "텍스트뷰어 줄 간격",
                    value:
                        "\(documentAppearance.lineHeightLevel)단계",
                    action: {
                        selectionDialog = .documentLineHeight
                    }
                )
                VisionCraftColorSettingTile(
                    label: "텍스트뷰어 색 조합",
                    theme: documentTheme,
                    action: {
                        selectionDialog = .documentColor
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var updateContent: some View {
        if let latestReleaseNote {
            sectionSpacer(height: 32)
            VisionCraftHomeSectionHeader(title: "업데이트 기록", tone: .updates)

            VStack(alignment: .leading, spacing: 10) {
                Text(latestReleaseNote.version)
                    .font(.title3.bold())
                    .foregroundStyle(
                        VisionCraftHomeUI.text
                    )
                Text(latestReleaseNote.date)
                    .font(.subheadline)
                    .foregroundStyle(
                        VisionCraftHomeUI.secondaryText
                    )
                ForEach(
                    Array(
                        latestReleaseNote.texts
                            .prefix(3)
                            .enumerated()
                    ),
                    id: \.offset
                ) { _, text in
                    HStack(alignment: .firstTextBaseline) {
                        Text("•")
                            .accessibilityHidden(true)
                        Text(text)
                            .foregroundStyle(
                                VisionCraftHomeUI.text
                            )
                    }
                }
            }
            .padding(20)
            .background(
                VisionCraftHomeUI.surface,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )

            HStack(spacing: 8) {
                Button("이전 업데이트 기록보기") {
                    appRouter.route = .help
                }
                Button("매뉴얼 보기", systemImage: "line.3.horizontal") {
                    appRouter.route = .help
                }
            }
            .buttonStyle(VisionCraftAndroidButtonStyle(filled: false))
            .tint(VisionCraftUI.primary)
            .padding(.top, 12)
        }
    }

    private func sectionSpacer(height: CGFloat) -> some View {
        Color.clear
            .frame(height: height)
            .accessibilityHidden(true)
    }

    private var chatActions: [VisionCraftActionItem] {
        [
            VisionCraftActionItem(
                id: "new-chat",
                icon: "doc.text",
                title: "새 채팅",
                description:
                    "문서, 클립보드, 사진을 첨부해 새 대화를 시작합니다.",
                action: {
                    appRouter.route = .localChat(
                        conversationID: nil
                    )
                }
            ),
            VisionCraftActionItem(
                id: "chat-history",
                icon: "clock.arrow.circlepath",
                title: "대화기록",
                description:
                    "저장된 대화를 검색하고 다시 엽니다.",
                action: {
                    appRouter.route = .chatHistory
                }
            ),
        ]
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
                title: "이미지 설명",
                description:
                    "사진을 촬영하고 AI가 보이는 장면을 설명합니다.",
                action: {
                    appRouter.route = .imageDescriptionCamera
                }
            ),
        ]
    }

    private var readingActions: [VisionCraftActionItem] {
        [
            VisionCraftActionItem(
                id: "text-view",
                icon: "text.alignleft",
                title: "텍스트 편집뷰",
                description:
                    "큰 글자로 읽고, 바로 고치고, 복사합니다.",
                action: {
                    presentTextSourceDialog()
                }
            ),
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

    private var homeTitleRow: some View {
        HStack(spacing: 16) {
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
                subtitle: rivoBannerSubtitle,
                systemImage: rivoStatusSystemImage,
                accent: rivoStatusColor,
                isBusy: rivoIsBusy,
                action: {
                    appRouter.route = .rivoRemote
                }
            )
        }
    }

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

    private var documentTheme: LocalDocumentColorTheme {
        theme(at: documentAppearance.colorIndex)
    }

    private var quickMenuTheme: LocalDocumentColorTheme {
        theme(at: settings.rivoQuickMenuColorIndex)
    }

    private func theme(at index: Int) -> LocalDocumentColorTheme {
        let themes = LocalDocumentColorTheme.all
        guard !themes.isEmpty else {
            preconditionFailure("VisionCraft color themes must not be empty")
        }
        return themes[min(max(index, 0), themes.count - 1)]
    }

    private var latestReleaseNote: HelpReleaseNote? {
        try? HelpContentLibrary
            .releaseNotes(
                language: settings.appLanguage
            )
            .first
    }

    private var rivoBannerSubtitle: String {
        switch rivoRemoteManager.state {
        case .ready:
            if let type = rivoRemoteManager.connectedDeviceType {
                return type.title
            }
            return AppLocalization.string(
                "Rivo 버튼으로 앱을 조작할 수 있습니다."
            )
        case .preparing, .scanning, .connecting, .discovering:
            return AppLocalization.string(
                "잠시 기다려 주세요."
            )
        case .inactive, .disconnected:
            return AppLocalization.string(
                "탭하여 리모컨을 연결합니다."
            )
        case .permissionDenied, .unsupported, .bluetoothOff, .failed:
            return AppLocalization.string(
                "탭하여 문제를 확인합니다."
            )
        }
    }

    private var rivoIsBusy: Bool {
        switch rivoRemoteManager.state {
        case .preparing, .scanning, .connecting, .discovering:
            return true
        default:
            return false
        }
    }

    private var rivoStatusSystemImage: String {
        switch rivoRemoteManager.state {
        case .ready:
            return "dot.radiowaves.left.and.right"
        case .preparing, .scanning, .connecting, .discovering:
            return "antenna.radiowaves.left.and.right"
        case .inactive,
             .disconnected,
             .permissionDenied,
             .unsupported,
             .bluetoothOff,
             .failed:
            return "antenna.radiowaves.left.and.right.slash"
        }
    }

    private var rivoHomeStatusTitle: String {
        switch rivoRemoteManager.state {
        case .inactive:
            return AppLocalization.string("연결 안 됨")
        default:
            return rivoRemoteManager.state.title
        }
    }

    private var rivoStatusColor: Color {
        switch rivoRemoteManager.state {
        case .ready:
            return VisionCraftHomeUI.connected
        case .permissionDenied,
             .unsupported,
             .bluetoothOff,
             .failed:
            return .red
        case .preparing,
             .scanning,
             .connecting,
             .discovering:
            return VisionCraftHomeUI.connecting
        case .inactive,
             .disconnected:
            return VisionCraftHomeUI.secondaryText
        }
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
        }
        selectionDialog = nil
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

private struct VisionCraftTextSourceDialog: View {
    let showsClipboard: Bool
    let onImage: () -> Void
    let onDocument: () -> Void
    let onClipboard: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VisionCraftDialogCard(
            title: "열기",
            usesHomeStyle: true,
            onDismiss: onDismiss
        ) {
            if showsClipboard {
                VisionCraftDialogOptionRow(
                    title: "클립보드",
                    subtitle: "복사해 둔 텍스트를 붙여 넣습니다.",
                    systemImage: "doc.on.clipboard",
                    isPrimary: true,
                    action: onClipboard
                )
            }
            VisionCraftDialogOptionRow(
                title: "이미지에서 텍스트 읽어오기",
                subtitle: "사진 앨범에서 고른 이미지의 글자를 읽어옵니다.",
                systemImage: "photo",
                action: onImage
            )
            VisionCraftDialogOptionRow(
                title: "문서",
                subtitle: "파일 앱에서 텍스트·문서 파일을 엽니다.",
                systemImage: "doc.text",
                action: onDocument
            )
        }
    }
}

private enum HomeSelectionDialog: String, Identifiable {
    case speechRate
    case language
    case documentFontLevel
    case documentLineHeight
    case documentColor
    case quickMenuColor

    var id: String {
        rawValue
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
                    title: "\($0)단계"
                )
            }
        case .documentColor,
             .quickMenuColor:
            return LocalDocumentColorTheme.all
                .enumerated()
                .map { index, theme in
                    VisionCraftSelectionOption(
                        id: String(index),
                        title: theme.displayName
                    )
                }
        }
    }
}

private extension AppSpeechRate {
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
