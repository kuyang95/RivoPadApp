import SwiftUI
import UIKit

struct AppSettingsView: View {
    @ObservedObject private var settings =
        AppSettingsStore.shared
    @ObservedObject private var appFonts =
        AppFontCatalogStore.shared
    @ObservedObject private var webSearch =
        WebSearchConfigurationStore.shared
    @Environment(\.openURL)
    private var openURL

    @State private var documentAppearance =
        LocalDocumentAppearanceStore().load()
    @State private var showsResetConfirmation =
        false
    @State private var showsFontSelection =
        false

    @AppStorage("reader.epub.theme")
    private var readerTheme = "light"
    @AppStorage("reader.epub.fontScale")
    private var readerFontScale = 1.0
    @AppStorage("reader.epub.lineHeight")
    private var readerLineHeight = 1.7
    @AppStorage("reader.epub.speechRate")
    private var readerSpeechRate = 1.0
    @AppStorage("reader.epub.originalLayout")
    private var readerUsesOriginalLayout = true

    var body: some View {
        Form {
            feedbackSection
            sharingSection
            webSearchSection
            scannerSection
            appearanceSection
            rivoQuickMenuSection
            documentSection
            readerSection
            connectionSection
            supportSection
            systemSection
            resetSection
        }
        .environment(\.defaultMinListRowHeight, VisionCraftUI.minTouchTarget)
        .visionCraftListScreen()
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: documentAppearance) {
            _, value in
            LocalDocumentAppearanceStore()
                .save(value)
        }
        .confirmationDialog(
            "앱 설정을 초기값으로 되돌릴까요?",
            isPresented:
                $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                "설정 초기화",
                role: .destructive
            ) {
                resetSettings()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(
                "대화·문서·책은 삭제하지 않고 보기와 음성 설정만 초기화합니다."
            )
        }
        .sheet(
            isPresented:
                $showsFontSelection
        ) {
            AppFontSelectionView(
                catalog: appFonts,
                languageCode:
                    settings
                    .appLanguage
                    .effectiveLanguageCode
            )
        }
    }

    private var sharingSection:
        some View
    {
        // Android `a_app_settings.xml` share_ui_mode: 켜면 음성 질의, 끄면 채팅 화면.
        Section {
            Toggle(
                "음성 질의 모드 사용 (끄면 채팅 화면)",
                isOn: Binding(
                    get: {
                        settings.sharedTextEntryMode == .voice
                    },
                    set: { usesVoice in
                        settings.sharedTextEntryMode =
                            usesVoice ? .voice : .chat
                    }
                )
            )
            .accessibilityHint(
                "음성 질문은 공유한 텍스트, 웹페이지, 사진과 지원 문서를 준비한 뒤 바로 듣기를 시작합니다. AI 채팅은 같은 자료를 첨부한 새 대화에서 질문을 기다립니다."
            )
        } header: {
            Text("공유 받았을 때 화면")
        } footer: {
            Text(
                "외부 앱에서 공유받았을 때 어떤 화면으로 열지 선택합니다."
            )
        }
    }

    private var webSearchSection: some View {
        Section {
            Toggle(
                "온라인 웹 검색",
                isOn: Binding(
                    get: { webSearch.isEnabled },
                    set: { webSearch.setEnabled($0) }
                )
            )
            .accessibilityHint(
                "웹 검색 화면에서 질문을 Gemini와 Google Search로 보냅니다."
            )

            Toggle(
                "AI 대화에서 자동으로 웹 검색",
                isOn: Binding(
                    get: {
                        webSearch
                            .isAutomaticChatSearchEnabled
                    },
                    set: {
                        webSearch
                            .setAutomaticChatSearchEnabled($0)
                    }
                )
            )
            .disabled(!webSearch.isEnabled)
            .accessibilityHint(
                "날씨·뉴스·환율처럼 최신 정보가 필요한 질문만 Gemini로 보내고 출처를 함께 보여줍니다."
            )
        } header: {
            Text("웹 검색")
        } footer: {
            Text(
                "자동 웹 검색을 켜면 날씨·뉴스·시세처럼 최신 정보가 있어야 답할 수 있는 질문만 Gemini와 Google Search로 전송하고, 나머지 대화와 첨부 문서는 그대로 이 iPad에서 처리합니다."
            )
        }
    }

    private var feedbackSection: some View {
        Section {
            Toggle(
                "효과음 피드백",
                isOn:
                    $settings
                    .soundEffectsEnabled
            )
            .accessibilityHint(
                "버튼 조작과 기능 실행 상태를 효과음으로 알려줍니다."
            )

            Toggle(
                "음성 피드백",
                isOn:
                    $settings
                    .voiceFeedbackEnabled
            )
            .accessibilityHint(
                "화면 이동과 처리 상태 안내 음성을 켜거나 끕니다. 읽기 버튼으로 시작한 음성은 유지됩니다."
            )

            Picker(
                "음성 속도",
                selection:
                    $settings.speechRate
            ) {
                ForEach(
                    AppSpeechRate.allCases
                ) { rate in
                    Text(rate.title)
                        .tag(rate)
                }
            }

            Button(
                "현재 속도로 음성 듣기",
                systemImage: "speaker.wave.2"
            ) {
                TTSManager.shared.speak(
                    AppLocalization.string(
                        "VisionCraft 음성 속도 예시입니다."
                    )
                )
            }

            Picker(
                "언어",
                selection:
                    $settings.appLanguage
            ) {
                ForEach(
                    AppLanguage.allCases
                ) { language in
                    Text(language.title)
                        .tag(language)
                }
            }
        } header: {
            Text("음성 및 언어")
        } footer: {
            Text(
                "앱 언어는 VisionCraft 화면과 번역·검색 기본 언어에 즉시 적용됩니다. 독서 화면의 오디오·TTS 속도는 책별 독서 설정을 따릅니다."
            )
        }
    }

    private var scannerSection: some View {
        Section {
            Toggle(
                "문서 자동 촬영",
                isOn:
                    $settings
                    .documentScanAutomaticCaptureEnabled
            )
            .accessibilityHint(
                "문서가 안정적으로 맞춰지면 자동 촬영합니다. 꺼도 모서리 안내와 수동 촬영은 계속 사용할 수 있습니다."
            )

            Toggle(
                "휘어진 페이지 보정",
                isOn:
                    $settings
                    .documentScanCurvedPageCorrectionEnabled
            )
            .accessibilityHint(
                "UVDoc 로컬 모델로 책처럼 휘어진 페이지를 펴 줍니다. 평평한 문서의 과보정을 막기 위해 기본으로 꺼져 있으며, 꺼도 모서리와 원근 보정은 유지됩니다."
            )

            Toggle(
                "문서 스캔 색상 자동 보정",
                isOn:
                    $settings
                    .documentScanColorEnhancementEnabled
            )
            .accessibilityHint(
                "촬영한 문서의 배경을 밝게 하고 글자 대비를 높입니다."
            )

            Toggle(
                "OCR 오타 자동 교정",
                isOn:
                    $settings
                    .ocrAutoCorrectionEnabled
            )
            .accessibilityHint(
                "정적인 사진과 스캔 문서의 이미지와 Vision OCR 원문을 Gemini로 보내 오타를 교정합니다."
            )
        } header: {
            Text("문서 스캐너")
        } footer: {
            Text(
                "모서리 검출과 원근 보정은 항상 적용됩니다. UVDoc은 이 iPad에서 처리하고, OCR 오타 교정은 Gemini를 사용하므로 네트워크가 필요합니다. Gemini 연결이 늦거나 실패하면 Vision OCR 원문을 바로 유지합니다."
            )
        }
    }

    private var appearanceSection: some View {
        Section {
            Button {
                showsFontSelection = true
            } label: {
                LabeledContent(
                    "앱 글꼴",
                    value:
                        appFonts
                        .selectedLabel(
                            languageCode:
                                settings
                                .appLanguage
                                .effectiveLanguageCode
                        )
                )
            }
            .foregroundStyle(.primary)
        } header: {
            Text("앱 모양")
        } footer: {
            Text(
                "언어에 맞는 추가 글꼴은 선택할 때만 내려받으며, 크기와 SHA-256 검증을 통과한 파일을 앱 안에 보관합니다."
            )
        }
    }

    private var documentSection: some View {
        Section("문서 보기 기본값") {
            Stepper(
                "글자 크기 \(documentAppearance.fontLevel)단계",
                value:
                    $documentAppearance
                    .fontLevel,
                in: 1 ... 10
            )
            Stepper(
                "줄 간격 \(documentAppearance.lineHeightLevel)단계",
                value:
                    $documentAppearance
                    .lineHeightLevel,
                in: 1 ... 10
            )
            Picker(
                "색상",
                selection:
                    $documentAppearance
                    .colorIndex
            ) {
                ForEach(
                    Array(
                        LocalDocumentColorTheme
                            .all.enumerated()
                    ),
                    id: \.offset
                ) { index, theme in
                    Text(
                        LocalizedStringKey(
                            theme.name
                        )
                    )
                        .tag(index)
                }
            }
            Toggle(
                "줄 구분선",
                isOn:
                    $documentAppearance
                    .showsLineSeparators
            )
            Toggle(
                "가로 화면 한 줄 읽기",
                isOn:
                    $documentAppearance
                    .usesSingleLineInLandscape
            )
        }
    }

    private var rivoQuickMenuSection:
        some View
    {
        Section {
            Toggle(
                "메뉴바 펼쳐보기",
                isOn:
                    $settings
                    .rivoQuickMenuExpanded
            )
            .accessibilityHint(
                "메뉴 항목을 위에서 아래로 한 번에 펼쳐 표시합니다."
            )

            Picker(
                "리모컨 조작 메뉴 색 조합",
                selection:
                    $settings
                    .rivoQuickMenuColorIndex
            ) {
                ForEach(
                    Array(
                        LocalDocumentColorTheme
                            .all.enumerated()
                    ),
                    id: \.offset
                ) { index, theme in
                    Text(
                        LocalizedStringKey(
                            theme.name
                        )
                    )
                    .tag(index)
                }
            }
        } header: {
            Text("앱 내부 빠른 메뉴")
        } footer: {
            Text(
                "Android의 Remote Ribbon 설정을 앱 안에서만 적용합니다. iPadOS에서는 다른 앱 위에 메뉴를 표시할 수 없습니다."
            )
        }
    }

    private var readerSection: some View {
        Section {
            Picker(
                "테마",
                selection: $readerTheme
            ) {
                Text("밝게").tag("light")
                Text("세피아").tag("sepia")
                Text("어둡게").tag("dark")
            }
            LabeledContent(
                "글자 배율",
                value:
                    readerFontScale
                    .formatted(
                        .number.precision(
                            .fractionLength(1)
                        )
                    )
            )
            Slider(
                value: $readerFontScale,
                in: 0.8 ... 2.0,
                step: 0.1
            )
            .accessibilityLabel(
                "독서 글자 배율"
            )

            LabeledContent(
                "줄 간격",
                value:
                    readerLineHeight
                    .formatted(
                        .number.precision(
                            .fractionLength(1)
                        )
                    )
            )
            Slider(
                value: $readerLineHeight,
                in: 1.2 ... 2.4,
                step: 0.1
            )
            .accessibilityLabel(
                "독서 줄 간격"
            )

            Toggle(
                "출판물 원본 표현",
                isOn:
                    $readerUsesOriginalLayout
            )

            LabeledContent(
                "재생 속도",
                value:
                    AppLocalization.format(
                        "재생 속도 배수 형식",
                        readerSpeechRate
                            .formatted(
                                .number.precision(
                                    .fractionLength(2)
                                )
                            )
                        )
            )
            Slider(
                value: $readerSpeechRate,
                in: 0.5 ... 2.0,
                step: 0.05
            )
            .accessibilityLabel(
                "독서 재생 속도"
            )
        } header: {
            Text("독서 기본값")
        } footer: {
            Text(
                "독서 화면에서 바꾼 값과 같은 설정을 사용합니다."
            )
        }
    }

    private var connectionSection: some View {
        Section("연결") {
            NavigationLink(
                "리모컨",
                value: AppRoute.rivoRemote
            )
            NavigationLink(
                "VisionLink",
                value: AppRoute.visionLink
            )
        }
    }

    private var supportSection: some View {
        Section("지원") {
            NavigationLink(
                "사용 설명서 및 변경 내역",
                value: AppRoute.help
            )
        }
    }

    private var systemSection: some View {
        Section {
            #if DEBUG
            NavigationLink {
                HWPReferenceComparisonView()
                    .visionCraftRouteBackButton()
            } label: {
                Label(
                    "HWP 비교 테스트",
                    systemImage: "rectangle.split.2x1"
                )
            }
            #endif

            Button(
                "앱 권한 설정 열기",
                systemImage: "gear"
            ) {
                guard let url = URL(
                    string:
                        UIApplication
                        .openSettingsURLString
                ) else {
                    return
                }
                openURL(url)
            }

        } header: {
            Text("iPadOS")
        } footer: {
            Text(
                "시스템 권한 문구는 iPadOS의 앱 언어 설정을 따릅니다. 일반 iPad 앱은 시스템 전체 밝기·화면 필터·VoiceOver·다른 앱의 터치를 직접 바꿀 수 없습니다."
            )
        }
    }

    private var resetSection: some View {
        Section {
            Button(
                "앱 설정 초기화",
                role: .destructive
            ) {
                showsResetConfirmation = true
            }
        }
    }

    private func resetSettings() {
        settings.resetToDefaults()
        appFonts.resetSelection()
        MagnifierDisplayPreferenceStore()
            .reset()
        documentAppearance = .defaultValue
        readerTheme = "light"
        readerFontScale = 1.0
        readerLineHeight = 1.7
        readerSpeechRate = 1.0
        readerUsesOriginalLayout = true
    }

}

struct AppFontSelectionView:
    View
{
    @ObservedObject var catalog:
        AppFontCatalogStore
    let languageCode: String

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage =
                    catalog.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(
                                VisionCraftUI.error
                            )
                            .accessibilityLabel(
                                "오류: \(errorMessage)"
                            )
                    }
                }

                Section {
                    ForEach(
                        catalog.visibleOptions(
                            languageCode:
                                languageCode
                        )
                    ) { option in
                        fontRow(option)
                    }
                } footer: {
                    Text(
                        "추가 글꼴은 VisionCraft 서버에서 HTTPS로 받고 파일 크기와 SHA-256을 확인한 뒤 이 앱에서만 사용합니다."
                    )
                }
            }
            .environment(\.defaultMinListRowHeight, VisionCraftUI.minTouchTarget)
            .visionCraftListScreen()
            .navigationTitle(
                "앱 글꼴 선택"
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .overlay {
                if catalog.isManifestLoading,
                   catalog.options.count <= 2 {
                    ProgressView(
                        "글꼴 목록을 불러오는 중"
                    )
                }
            }
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button("닫기") {
                        dismiss()
                    }
                }
                ToolbarItem(
                    placement:
                        .primaryAction
                ) {
                    Button(
                        "목록 새로 고침",
                        systemImage:
                            "arrow.clockwise"
                    ) {
                        Task {
                            await catalog
                                .refreshManifest()
                        }
                    }
                    .disabled(
                        catalog
                            .isManifestLoading
                            || catalog
                            .downloadingKey
                            != nil
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func fontRow(
        _ option: AppFontOption
    ) -> some View {
        let isSelected =
            catalog.effectiveOption(
                languageCode:
                    languageCode
            ).key == option.key
        let isDownloading =
            catalog.downloadingKey
                == option.key

        VStack(
            alignment: .leading,
            spacing: 6
        ) {
            Button {
                Task {
                    if await catalog
                        .select(option) {
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(
                            option.label(
                                languageCode:
                                    languageCode
                            )
                        )
                        if isDownloading {
                            Text(
                                "글꼴을 내려받아 확인하는 중"
                            )
                            .font(.footnote)
                            .foregroundStyle(
                                .secondary
                            )
                        }
                    }
                    Spacer()
                    if isDownloading {
                        ProgressView()
                    } else if isSelected {
                        Image(
                            systemName:
                                "checkmark.circle.fill"
                        )
                        .foregroundStyle(
                            .tint
                        )
                        .accessibilityHidden(
                            true
                        )
                    }
                }
                .contentShape(
                    Rectangle()
                )
            }
            .buttonStyle(.plain)
            .disabled(
                catalog.downloadingKey
                    != nil
            )
            .accessibilityValue(
                AppLocalization.string(
                    isSelected
                        ? "선택됨"
                        : ""
                )
            )

            if let license =
                option.license {
                HStack(spacing: 8) {
                    Text(license)
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    if let licenseURL =
                        option.licenseURL {
                        Link(
                            "라이선스 보기",
                            destination:
                                licenseURL
                        )
                        .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
