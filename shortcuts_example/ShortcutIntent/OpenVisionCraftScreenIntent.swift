import AppIntents
import Foundation

struct OpenVisionCraftScreenIntent: AppIntent {
    static var title: LocalizedStringResource =
        "VisionCraft 화면 열기"
    static var description =
        IntentDescription(
            "VisionCraft의 주요 기능 화면을 바로 엽니다."
        )
    static var openAppWhenRun = true

    @Parameter(title: "열 화면")
    var screen: AppDeepLinkDestination

    static var parameterSummary:
        some ParameterSummary {
        Summary("\(\.$screen) 열기")
    }

    init() {}

    init(
        screen: AppDeepLinkDestination
    ) {
        self.screen = screen
    }

    func perform() async throws
        -> some IntentResult
    {
        let envelope =
            ShortcutEnvelope.openScreen(
                screen
            )
        await ShortcutBridge
            .replaceLastEnvelope(envelope)
        return .result()
    }
}

struct VisionCraftAppShortcuts:
    AppShortcutsProvider
{
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent:
                OpenVisionCraftScreenIntent(
                    screen: .settings
                ),
            phrases: [
                "\(.applicationName) 설정 열기",
                "\(.applicationName) 음성 설정"
            ],
            shortTitle: "설정",
            systemImageName: "gearshape"
        )
        AppShortcut(
            intent:
                OpenVisionCraftScreenIntent(
                    screen: .ai
                ),
            phrases: [
                "\(.applicationName) AI 채팅 열기",
                "\(.applicationName)에서 AI 열기"
            ],
            shortTitle: "AI 채팅",
            systemImageName:
                "bubble.left.and.bubble.right"
        )
        AppShortcut(
            intent:
                OpenVisionCraftScreenIntent(
                    screen: .reader
                ),
            phrases: [
                "\(.applicationName) 독서 열기",
                "\(.applicationName)에서 책 읽기"
            ],
            shortTitle: "독서",
            systemImageName: "book"
        )
        AppShortcut(
            intent:
                OpenVisionCraftScreenIntent(
                    screen: .camera
                ),
            phrases: [
                "\(.applicationName) 카메라 열기",
                "\(.applicationName) 카메라 도구"
            ],
            shortTitle: "카메라",
            systemImageName: "camera"
        )
        AppShortcut(
            intent:
                OpenVisionCraftScreenIntent(
                    screen: .scanner
                ),
            phrases: [
                "\(.applicationName) 문서 스캔",
                "\(.applicationName) 스캐너 열기"
            ],
            shortTitle: "문서 스캔",
            systemImageName: "doc.viewfinder"
        )
        AppShortcut(
            intent:
                OpenVisionCraftScreenIntent(
                    screen: .magnifier
                ),
            phrases: [
                "\(.applicationName) 돋보기 열기",
                "\(.applicationName) 확대경"
            ],
            shortTitle: "돋보기",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent:
                OpenVisionCraftScreenIntent(
                    screen: .liveText
                ),
            phrases: [
                "\(.applicationName) 실시간 글자 읽기",
                "\(.applicationName) 카메라로 읽기"
            ],
            shortTitle: "실시간 글자 읽기",
            systemImageName: "text.viewfinder"
        )
        AppShortcut(
            intent:
                OpenVisionCraftScreenIntent(
                    screen: .files
                ),
            phrases: [
                "\(.applicationName) 파일 열기",
                "\(.applicationName) 문서 가져오기"
            ],
            shortTitle: "파일 열기",
            systemImageName: "folder"
        )
        AppShortcut(
            intent:
                OpenVisionCraftScreenIntent(
                    screen: .rivo
                ),
            phrases: [
                "\(.applicationName) Rivo 연결",
                "\(.applicationName) 리모컨 열기"
            ],
            shortTitle: "Rivo 리모컨",
            systemImageName: "dot.radiowaves.left.and.right"
        )
        AppShortcut(
            intent:
                OpenVisionCraftScreenIntent(
                    screen: .visionLink
                ),
            phrases: [
                "\(.applicationName) VisionLink 열기",
                "\(.applicationName) 기기 연결"
            ],
            shortTitle: "VisionLink",
            systemImageName: "rectangle.connected.to.line.below"
        )
    }

    static var shortcutTileColor:
        ShortcutTileColor {
        .purple
    }
}
