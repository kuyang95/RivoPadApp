import SwiftUI
import UIKit

struct AppSettingsView: View {
    @ObservedObject private var settings =
        AppSettingsStore.shared
    @ObservedObject private var webSearch =
        WebSearchConfigurationStore.shared
    @Environment(\.openURL)
    private var openURL

    @State private var documentAppearance =
        LocalDocumentAppearanceStore().load()
    @State private var showsResetConfirmation =
        false
    @State private var webSearchAPIKey = ""
    @State private var webSearchStatus: String?
    @State private var webSearchError: String?
    @State private var showsWebSearchConsent =
        false

    @AppStorage("reader.epub.theme")
    private var readerTheme = "light"
    @AppStorage("reader.epub.fontScale")
    private var readerFontScale = 1.0
    @AppStorage("reader.epub.lineHeight")
    private var readerLineHeight = 1.7
    @AppStorage("reader.epub.speechRate")
    private var readerSpeechRate = 1.0

    var body: some View {
        Form {
            feedbackSection
            scannerSection
            appearanceSection
            documentSection
            readerSection
            webSearchSection
            connectionSection
            supportSection
            systemSection
            resetSection
        }
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
        .confirmationDialog(
            "온라인 웹 검색을 켤까요?",
            isPresented:
                $showsWebSearchConsent,
            titleVisibility: .visible
        ) {
            Button(
                "동의하고 켜기"
            ) {
                webSearch.setEnabled(true)
                webSearchStatus =
                    "온라인 웹 검색을 켰습니다."
                webSearchError = nil
            }
            Button(
                "취소",
                role: .cancel
            ) {}
        } message: {
            Text(
                "검색어가 개인 Brave API 키로 Brave Search에 전송됩니다. Brave는 과금·장애 대응·남용 방지를 위해 검색어 로그를 최대 90일 보관할 수 있습니다. 검색 결과와 로컬 AI 답변은 VisionCraft 대화 기록에 저장하지 않습니다."
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
                "녹음 시작과 AI 처리 시작 효과음을 켜거나 끕니다."
            )

            Toggle(
                "자동 음성 안내",
                isOn:
                    $settings
                    .voiceFeedbackEnabled
            )
            .accessibilityHint(
                "화면 이동과 처리 상태 안내 음성을 켜거나 끕니다. 읽기 버튼으로 시작한 음성은 유지됩니다."
            )

            Picker(
                "기본 말하기 속도",
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
        } header: {
            Text("소리와 음성")
        } footer: {
            Text(
                "독서 화면의 오디오·TTS 속도는 책별 독서 설정을 따릅니다."
            )
        }
    }

    private var scannerSection: some View {
        Section {
            Toggle(
                "문서 색상 자동 보정",
                isOn:
                    $settings
                    .documentScanColorEnhancementEnabled
            )
            .accessibilityHint(
                "촬영한 문서의 배경과 글자 대비를 Android VisionCraft 방식으로 강화합니다."
            )
        } header: {
            Text("문서 스캐너")
        } footer: {
            Text(
                "모서리 검출과 원근·곡면 보정은 항상 적용하고, 이 항목은 마지막 색상 강화 단계만 제어합니다."
            )
        }
    }

    private var appearanceSection: some View {
        Section("앱 모양") {
            Picker(
                "앱 글꼴",
                selection:
                    $settings.fontChoice
            ) {
                ForEach(
                    AppFontChoice.allCases
                ) { choice in
                    Text(choice.title)
                        .tag(choice)
                }
            }
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

    private var webSearchSection:
        some View
    {
        Section {
            LabeledContent(
                "공급자",
                value:
                    "Brave LLM Context"
            )

            SecureField(
                "Brave Search API 키",
                text: $webSearchAPIKey
            )
            .textInputAutocapitalization(
                .never
            )
            .autocorrectionDisabled()
            .privacySensitive()

            HStack {
                Button(
                    "API 키 저장",
                    systemImage:
                        "key.fill"
                ) {
                    saveWebSearchAPIKey()
                }
                .disabled(
                    webSearchAPIKey
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                        .isEmpty
                )

                if webSearch.hasAPIKey {
                    Button(
                        "저장된 키 삭제",
                        role: .destructive
                    ) {
                        removeWebSearchAPIKey()
                    }
                }
            }

            LabeledContent(
                "키 상태",
                value:
                    webSearch.hasAPIKey
                    ? "Keychain에 저장됨"
                    : "저장되지 않음"
            )

            Toggle(
                "온라인 웹 검색 사용",
                isOn:
                    Binding(
                        get: {
                            webSearch
                                .isEnabled
                        },
                        set: {
                            requested in
                            if !requested {
                                webSearch
                                    .setEnabled(
                                        false
                                    )
                                webSearchStatus =
                                    "온라인 웹 검색을 껐습니다."
                            } else if webSearch
                                .hasAPIKey {
                                showsWebSearchConsent =
                                    true
                            } else {
                                webSearchError =
                                    "먼저 개인 Brave Search API 키를 저장해 주세요."
                            }
                        }
                    )
            )

            if let webSearchStatus {
                Text(webSearchStatus)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
            if let webSearchError {
                Text(webSearchError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityLabel(
                        "오류: \(webSearchError)"
                    )
            }

            Link(
                "Brave API 키와 요금 확인",
                destination: URL(
                    string:
                        "https://api-dashboard.search.brave.com/app/keys"
                )!
            )
            Link(
                "개인정보 안내",
                destination: URL(
                    string:
                        "https://api-dashboard.search.brave.com/privacy-policy"
                )!
            )
            Link(
                "이용약관",
                destination: URL(
                    string:
                        "https://api-dashboard.search.brave.com/documentation/resources/terms-of-service"
                )!
            )
        } header: {
            Text("선택적 웹 검색")
        } footer: {
            Text(
                "검색어와 API 키는 Brave로 전송됩니다. AI 답변은 M4에서 만들며 검색 결과를 캐시하거나 대화 기록에 저장하지 않습니다. 현재 Search 요금은 요청 1,000회당 미화 5달러이며 월 5달러 크레딧이 포함되지만, 최신 조건은 Brave에서 확인하세요."
            )
        }
    }

    private var connectionSection: some View {
        Section("연결") {
            NavigationLink(
                "Rivo 리모컨",
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
            Button(
                "VisionCraft 권한 설정 열기",
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

            LabeledContent(
                "앱 언어",
                value:
                    AppLocalization.string(
                        "iPad 시스템 설정 사용"
                    )
            )
        } header: {
            Text("iPadOS")
        } footer: {
            Text(
                "일반 iPad 앱은 시스템 전체 밝기·화면 필터·VoiceOver·다른 앱의 터치를 직접 바꿀 수 없습니다."
            )
        }
    }

    private var resetSection: some View {
        Section {
            Button(
                "보기·음성 설정 초기화",
                role: .destructive
            ) {
                showsResetConfirmation = true
            }
        }
    }

    private func resetSettings() {
        settings.resetToDefaults()
        documentAppearance = .defaultValue
        readerTheme = "light"
        readerFontScale = 1.0
        readerLineHeight = 1.7
        readerSpeechRate = 1.0
    }

    private func saveWebSearchAPIKey() {
        do {
            try webSearch.saveAPIKey(
                webSearchAPIKey
            )
            webSearchAPIKey = ""
            webSearchStatus =
                "API 키를 Keychain에 저장했습니다."
            webSearchError = nil
        } catch {
            webSearchStatus = nil
            webSearchError =
                error.localizedDescription
        }
    }

    private func removeWebSearchAPIKey() {
        do {
            try webSearch.removeAPIKey()
            webSearchAPIKey = ""
            webSearchStatus =
                "저장된 API 키를 삭제하고 웹 검색을 껐습니다."
            webSearchError = nil
        } catch {
            webSearchStatus = nil
            webSearchError =
                error.localizedDescription
        }
    }
}
