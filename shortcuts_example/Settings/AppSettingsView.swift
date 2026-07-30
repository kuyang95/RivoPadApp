import SwiftUI
import UIKit

struct AppSettingsView: View {
    @ObservedObject private var settings =
        AppSettingsStore.shared
    @Environment(\.openURL)
    private var openURL

    @State private var documentAppearance =
        LocalDocumentAppearanceStore().load()
    @State private var showsResetConfirmation =
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
            connectionSection
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
                    "VisionCraft 음성 속도 예시입니다."
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
                    Text(theme.name)
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
                    readerSpeechRate
                    .formatted(
                        .number.precision(
                            .fractionLength(2)
                        )
                    )
                    + "배"
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
                "Rivo 리모컨",
                value: AppRoute.rivoRemote
            )
            NavigationLink(
                "VisionLink",
                value: AppRoute.visionLink
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
                value: "iPad 시스템 설정 사용"
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
}
