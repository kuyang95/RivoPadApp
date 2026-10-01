import Combine
import SwiftUI
import UIKit

nonisolated enum RivoQuickDestination:
    String,
    Sendable
{
    case aiChat
    case aiChatHistory
    case reader
    case translation
    case magnifier
    case liveTextReader
    case imageDescription
    case scanner
    case textSource
    case settings
    case remoteSettings
}

nonisolated enum RivoQuickMenuPage:
    String,
    Equatable,
    Sendable
{
    case home
    case tools
    case appDisplay
    case widgets
    case camera
    case cameraContrast
    case text
    case publication
}

nonisolated enum RivoQuickValueAction:
    Equatable,
    Sendable
{
    case decrease
    case reset
    case increase
}

nonisolated enum RivoQuickOrientationAction:
    Equatable,
    Sendable
{
    case previous
    case automatic
    case next
}

nonisolated enum RivoRemoteCommand: Equatable, Sendable {
    case navigate(RivoQuickDestination)
    case screen(
        RivoRemoteScreen,
        RivoScreenRemoteAction
    )
    case startVoiceAction
    case home
    case back
    case stopSpeech
    case toggleAppInterfaceInversion
    case appBrightness(RivoQuickValueAction)
    case appOrientation(RivoQuickOrientationAction)
}

nonisolated struct RivoRemoteDecision:
    Equatable,
    Sendable
{
    let command: RivoRemoteCommand?
    let consumed: Bool
}

nonisolated struct RivoQuickMenuItem:
    Identifiable,
    Equatable,
    Sendable
{
    let id: String
    let title: String
    let systemImage: String
    let command: RivoRemoteCommand?
    let destinationPage: RivoQuickMenuPage?
    let increaseCommand: RivoRemoteCommand?
    let decreaseCommand: RivoRemoteCommand?

    init(
        id: String,
        title: String,
        systemImage: String,
        command: RivoRemoteCommand,
        increaseCommand: RivoRemoteCommand? = nil,
        decreaseCommand: RivoRemoteCommand? = nil
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.command = command
        destinationPage = nil
        self.increaseCommand = increaseCommand
        self.decreaseCommand = decreaseCommand
    }

    init(
        id: String,
        title: String,
        systemImage: String,
        destinationPage: RivoQuickMenuPage
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        command = nil
        self.destinationPage = destinationPage
        increaseCommand = nil
        decreaseCommand = nil
    }

    var isSubmenu: Bool {
        destinationPage != nil
    }

    /// Android `MenuAdjustment.isAdjustable`: 2/8(−/+)로 값을 조절하는 항목.
    var isAdjustable: Bool {
        increaseCommand != nil
            || decreaseCommand != nil
    }
}

/// Android `labelResForRibbonItem`: 토글 항목은 현재 상태에 따라 "수행될 동작"을 라벨로 보여준다.
/// 카메라 화면이 알려 준 실제 상태(`noteMagnifierState`)를 사용한다.
nonisolated struct RivoRemoteToggleStates:
    Equatable,
    Sendable
{
    var isTorchOn = false
    var isFrontCamera = false
}

@MainActor
final class RivoRemoteControlCenter: ObservableObject {
    @Published private(set) var isMenuPresented = false
    @Published private(set) var
        isCommandModeActive = false
    @Published private(set) var selectedIndex = 0
    @Published private(set) var feedback = ""
    @Published private(set) var activeScreen:
        RivoRemoteScreen?
    @Published private(set) var currentPage:
        RivoQuickMenuPage = .home
    @Published private(set) var toggleStates =
        RivoRemoteToggleStates()
    /// Android `RemoteModeOverlay.showKeyGuide`: 빠른 메뉴 안에서 현재 페이지 모드의 키 안내 키패드.
    @Published private(set) var isKeyGuidePresented =
        false
    /// Android `RemoteModeOverlay.showModeName`: 모드가 바뀌면 1.15초 동안 모드 이름을 띄운다.
    @Published private(set) var modeNameFlash:
        RivoRemoteKeyMode?

    private struct PageState {
        let page: RivoQuickMenuPage
        let selectedIndex: Int
    }

    /// Android `RibbonSessionState`: 닫힌 뒤 60초 안에 다시 열면 페이지·선택을 되살린다.
    private struct MenuSession {
        let page: RivoQuickMenuPage
        let selectedIndex: Int
        let pageStack: [PageState]
        let screen: RivoRemoteScreen?
        let closedAt: TimeInterval
    }

    /// Android `AUTO_CLOSE_DELAY_MS` / `SESSION_RESTORE_WINDOW_MS` = 60초.
    static let autoCloseDelay: TimeInterval = 60
    static let sessionRestoreWindow: TimeInterval = 60

    private var pageStack: [PageState] = []
    private var savedSession: MenuSession?
    private var autoCloseTask: Task<Void, Never>?
    private var modeNameFlashTask: Task<Void, Never>?

    var items: [RivoQuickMenuItem] {
        switch currentPage {
        case .home:
            return homeItems
        case .tools:
            return toolItems
        case .appDisplay:
            return appDisplayItems
        case .widgets:
            return widgetItems
        case .camera:
            return cameraItems
        case .cameraContrast:
            return cameraContrastItems
        case .text:
            return textItems
        case .publication:
            return publicationReaderItems
        }
    }

    var pageTitle: String {
        switch currentPage {
        case .home:
            return AppLocalization.string("홈")
        case .tools:
            return AppLocalization.string("도구")
        case .appDisplay:
            return AppLocalization.string("앱 화면")
        case .widgets:
            return AppLocalization.string("위젯")
        case .camera:
            return AppLocalization.string("카메라")
        case .cameraContrast:
            return AppLocalization.string("고대비")
        case .text:
            return AppLocalization.string("텍스트")
        case .publication:
            return AppLocalization.string("DAISY/EPUB")
        }
    }

    var canGoBackInMenu: Bool {
        !pageStack.isEmpty
    }

    /// 현재 페이지가 대응하는 리모컨 모드. DAISY·텍스트 페이지는 그 모드의 키 안내를, 나머지는 메뉴 키 안내를 보여준다.
    var keyGuideMode: RivoRemoteKeyMode {
        switch currentPage {
        case .publication:
            return .daisy
        case .text:
            return .textView
        default:
            return .menu
        }
    }

    /// 카메라 화면이 실제 라이트·전후면 상태를 알려줄 때 호출한다.
    func noteMagnifierState(
        isTorchOn: Bool,
        isFrontCamera: Bool
    ) {
        let state = RivoRemoteToggleStates(
            isTorchOn: isTorchOn,
            isFrontCamera: isFrontCamera
        )
        if toggleStates != state {
            toggleStates = state
        }
    }

    func toggleKeyGuide() {
        guard isMenuPresented else {
            return
        }
        isKeyGuidePresented.toggle()
        restartAutoCloseTimer()
        if isKeyGuidePresented {
            feedback = keyGuideMode.accessibilitySummary
            announceFeedback()
        }
    }

    func dismissKeyGuide() {
        isKeyGuidePresented = false
        restartAutoCloseTimer()
    }

    private var homeItems: [RivoQuickMenuItem] {
        [
            RivoQuickMenuItem(
                id: "home.voiceAction",
                title: AppLocalization.string("음성 명령"),
                systemImage: "mic.circle",
                command: .startVoiceAction
            ),
            RivoQuickMenuItem(
                id: "home.tools",
                title: AppLocalization.string("도구"),
                systemImage: "wrench.and.screwdriver",
                destinationPage: .tools
            ),
            RivoQuickMenuItem(
                id: "home.camera",
                title: AppLocalization.string("카메라"),
                systemImage: "plus.magnifyingglass",
                command: .navigate(.magnifier)
            ),
            RivoQuickMenuItem(
                id: "home.appDisplay",
                title: AppLocalization.string("앱 화면"),
                systemImage: "display",
                destinationPage: .appDisplay
            ),
            RivoQuickMenuItem(
                id: "home.widgets",
                title: AppLocalization.string("위젯"),
                systemImage: "square.grid.2x2",
                destinationPage: .widgets
            ),
        ]
    }

    private var toolItems: [RivoQuickMenuItem] {
        [
            RivoQuickMenuItem(
                id: "tools.voiceAction",
                title: AppLocalization.string("음성 명령"),
                systemImage: "waveform",
                command: .startVoiceAction
            ),
            RivoQuickMenuItem(
                id: "tools.scanner",
                title: AppLocalization.string("문서 스캔"),
                systemImage: "doc.viewfinder",
                command: .navigate(.scanner)
            ),
            RivoQuickMenuItem(
                id: "tools.imageDescription",
                title: AppLocalization.string("이미지 설명"),
                systemImage: "sparkles",
                command: .navigate(.imageDescription)
            ),
            RivoQuickMenuItem(
                id: "tools.ocr",
                title: AppLocalization.string("글자 인식"),
                systemImage: "text.viewfinder",
                command: .navigate(.textSource)
            ),
            RivoQuickMenuItem(
                id: "tools.translation",
                title: AppLocalization.string("번역"),
                systemImage: "character.bubble",
                command: .navigate(.translation)
            ),
            RivoQuickMenuItem(
                id: "tools.text",
                title: AppLocalization.string("텍스트 보기"),
                systemImage: "doc.plaintext",
                command: .navigate(.textSource)
            ),
        ]
    }

    private var appDisplayItems: [RivoQuickMenuItem] {
        [
            RivoQuickMenuItem(
                id: "display.invert",
                title: AppLocalization.string("앱 색상 반전"),
                systemImage: "circle.lefthalf.filled.inverse",
                command: .toggleAppInterfaceInversion
            ),
            RivoQuickMenuItem(
                id: "display.brightness",
                title: AppLocalization.string("화면 밝기"),
                systemImage: "sun.max",
                command: .appBrightness(.reset),
                increaseCommand: .appBrightness(.increase),
                decreaseCommand: .appBrightness(.decrease)
            ),
            RivoQuickMenuItem(
                id: "display.orientation",
                title: AppLocalization.string("화면 방향"),
                systemImage: "rectangle.landscape.rotate",
                command: .appOrientation(.automatic),
                increaseCommand: .appOrientation(.next),
                decreaseCommand: .appOrientation(.previous)
            ),
            RivoQuickMenuItem(
                id: "display.settings",
                title: AppLocalization.string("설정"),
                systemImage: "gearshape",
                command: .navigate(.settings)
            ),
        ]
    }

    private var widgetItems: [RivoQuickMenuItem] {
        [
            RivoQuickMenuItem(
                id: "widgets.newChat",
                title: AppLocalization.string("새 대화"),
                systemImage: "square.and.pencil",
                command: .navigate(.aiChat)
            ),
            RivoQuickMenuItem(
                id: "widgets.chatHistory",
                title: AppLocalization.string("대화 목록"),
                systemImage: "bubble.left.and.text.bubble.right",
                command: .navigate(.aiChatHistory)
            ),
            RivoQuickMenuItem(
                id: "widgets.scanner",
                title: AppLocalization.string("문서 스캔"),
                systemImage: "doc.viewfinder",
                command: .navigate(.scanner)
            ),
            RivoQuickMenuItem(
                id: "widgets.liveText",
                title: AppLocalization.string("바로 읽기"),
                systemImage: "text.viewfinder",
                command: .navigate(.liveTextReader)
            ),
            RivoQuickMenuItem(
                id: "widgets.reader",
                title: AppLocalization.string("데이지/EPUB 플레이어"),
                systemImage: "book",
                command: .navigate(.reader)
            ),
        ]
    }

    private var cameraItems: [RivoQuickMenuItem] {
        [
            // Android `HIDDEN_BACK_MENU_IDS`: "뒤로" 항목은 별표/상단 버튼이 대신하므로 숨긴다.
            RivoQuickMenuItem(
                id: "camera.tools",
                title: AppLocalization.string("도구"),
                systemImage: "wrench.and.screwdriver",
                destinationPage: .tools
            ),
            adjustableMagnifierItem(
                id: "camera.zoom",
                title: "배율",
                systemImage: "plus.magnifyingglass",
                defaultAction: .resetZoom,
                increaseAction: .increaseZoom,
                decreaseAction: .decreaseZoom
            ),
            RivoQuickMenuItem(
                id: "camera.contrast",
                title: AppLocalization.string("고대비"),
                systemImage: "camera.filters",
                destinationPage: .cameraContrast
            ),
            RivoQuickMenuItem(
                id: "camera.appDisplay",
                title: AppLocalization.string("앱 화면"),
                systemImage: "display",
                destinationPage: .appDisplay
            ),
            magnifierItem(
                id: "camera.switch",
                title: toggleStates.isFrontCamera
                    ? "후면 카메라"
                    : "전면 카메라",
                systemImage:
                    "arrow.triangle.2.circlepath.camera",
                action: .switchCamera
            ),
            magnifierItem(
                id: "camera.torch",
                title: toggleStates.isTorchOn
                    ? "라이트 끄기"
                    : "라이트 켜기",
                systemImage: toggleStates.isTorchOn
                    ? "flashlight.off.fill"
                    : "flashlight.on.fill",
                action: .toggleTorch
            ),
        ]
    }

    private var cameraContrastItems: [RivoQuickMenuItem] {
        [
            magnifierItem(
                id: "camera.originalColor",
                title: "원래 색상",
                systemImage: "arrow.counterclockwise",
                action: .originalColor
            ),
            adjustableMagnifierItem(
                id: "camera.color",
                title: "대비 색상",
                systemImage: "camera.filters",
                defaultAction: .originalColor,
                increaseAction: .nextColor,
                decreaseAction: .previousColor
            ),
            adjustableMagnifierItem(
                id: "camera.textWeight",
                title: "글자 두께",
                systemImage:
                    "circle.lefthalf.filled",
                defaultAction: .resetThreshold,
                increaseAction: .increaseThreshold,
                decreaseAction: .decreaseThreshold
            ),
        ]
    }

    private var textItems: [RivoQuickMenuItem] {
        [
            localDocumentReaderItem(
                id: "document.originalColor",
                title: "원래 색상",
                systemImage: "arrow.counterclockwise",
                action: .originalColor
            ),
            adjustableLocalDocumentReaderItem(
                id: "document.color",
                title: "대비 색상",
                systemImage: "circle.lefthalf.filled",
                defaultAction: .invertColor,
                increaseAction: .nextColor,
                decreaseAction: .previousColor
            ),
            adjustableLocalDocumentReaderItem(
                id: "document.font",
                title: "글자 크기",
                systemImage: "textformat.size",
                defaultAction: .defaultFont,
                increaseAction: .increaseFont,
                decreaseAction: .decreaseFont
            ),
            adjustableLocalDocumentReaderItem(
                id: "document.lineHeight",
                title: "줄 간격",
                systemImage:
                    "text.line.first.and.arrowtriangle.forward",
                defaultAction:
                    .defaultLineHeight,
                increaseAction:
                    .increaseLineHeight,
                decreaseAction:
                    .decreaseLineHeight
            ),
        ]
    }

    private var publicationReaderItems: [RivoQuickMenuItem] {
        [
            publicationReaderItem(
                id: "reader.playPause",
                title: "재생/일시정지",
                systemImage: "playpause",
                action: .togglePlayback
            ),
            publicationReaderItem(
                id: "reader.previous",
                title: "이전",
                systemImage: "backward.end",
                action: .previous
            ),
            publicationReaderItem(
                id: "reader.next",
                title: "다음",
                systemImage: "forward.end",
                action: .next
            ),
            publicationReaderItem(
                id: "reader.previousUnit",
                title: "이동 단위 이전",
                systemImage: "minus.circle",
                action: .previousNavigationUnit
            ),
            publicationReaderItem(
                id: "reader.nextUnit",
                title: "이동 단위 다음",
                systemImage: "plus.circle",
                action: .nextNavigationUnit
            ),
            publicationReaderItem(
                id: "reader.contents",
                title: "목차",
                systemImage: "list.bullet",
                action: .showContents
            ),
            publicationReaderItem(
                id: "reader.search",
                title: "본문 검색",
                systemImage: "magnifyingglass",
                action: .showSearch
            ),
            publicationReaderItem(
                id: "reader.settings",
                title: "설정",
                systemImage: "textformat.size",
                action: .showSettings
            ),
        ]
    }

    private func publicationReaderItem(
        id: String,
        title: String,
        systemImage: String,
        action: RivoPublicationReaderRemoteAction
    ) -> RivoQuickMenuItem {
        RivoQuickMenuItem(
            id: id,
            title: AppLocalization.string(title),
            systemImage: systemImage,
            command: .screen(
                .publicationReader,
                .publicationReader(action)
            )
        )
    }

    private func magnifierItem(
        id: String,
        title: String,
        systemImage: String,
        action: RivoMagnifierRemoteAction
    ) -> RivoQuickMenuItem {
        RivoQuickMenuItem(
            id: id,
            title: AppLocalization.string(title),
            systemImage: systemImage,
            command: magnifierCommand(action)
        )
    }

    private func adjustableMagnifierItem(
        id: String,
        title: String,
        systemImage: String,
        defaultAction: RivoMagnifierRemoteAction,
        increaseAction: RivoMagnifierRemoteAction,
        decreaseAction: RivoMagnifierRemoteAction
    ) -> RivoQuickMenuItem {
        RivoQuickMenuItem(
            id: id,
            title: AppLocalization.string(title),
            systemImage: systemImage,
            command:
                magnifierCommand(defaultAction),
            increaseCommand:
                magnifierCommand(increaseAction),
            decreaseCommand:
                magnifierCommand(decreaseAction)
        )
    }

    private func magnifierCommand(
        _ action: RivoMagnifierRemoteAction
    ) -> RivoRemoteCommand {
        .screen(
            activeScreen == .liveTextReader
                ? .liveTextReader
                : .magnifier,
            .magnifier(action)
        )
    }

    private func localDocumentReaderItem(
        id: String,
        title: String,
        systemImage: String,
        action: RivoLocalDocumentRemoteAction
    ) -> RivoQuickMenuItem {
        RivoQuickMenuItem(
            id: id,
            title: AppLocalization.string(title),
            systemImage: systemImage,
            command: localDocumentCommand(action)
        )
    }

    private func adjustableLocalDocumentReaderItem(
        id: String,
        title: String,
        systemImage: String,
        defaultAction:
            RivoLocalDocumentRemoteAction,
        increaseAction:
            RivoLocalDocumentRemoteAction,
        decreaseAction:
            RivoLocalDocumentRemoteAction
    ) -> RivoQuickMenuItem {
        RivoQuickMenuItem(
            id: id,
            title: AppLocalization.string(title),
            systemImage: systemImage,
            command:
                localDocumentCommand(
                    defaultAction
                ),
            increaseCommand:
                localDocumentCommand(
                    increaseAction
                ),
            decreaseCommand:
                localDocumentCommand(
                    decreaseAction
                )
        )
    }

    private func localDocumentCommand(
        _ action: RivoLocalDocumentRemoteAction
    ) -> RivoRemoteCommand {
        .screen(
            .localDocumentReader,
            .localDocumentReader(action)
        )
    }

    private func rootPage(
        for screen: RivoRemoteScreen?
    ) -> RivoQuickMenuPage {
        switch screen {
        case .magnifier, .liveTextReader:
            return .camera
        case .localDocumentReader:
            return .text
        case .publicationReader:
            return .publication
        default:
            return .home
        }
    }

    func updateActiveScreen(
        _ screen: RivoRemoteScreen?
    ) {
        guard activeScreen != screen else {
            return
        }
        activeScreen = screen
        currentPage = rootPage(for: screen)
        pageStack.removeAll()
        selectedIndex = 0
        if isMenuPresented {
            feedback = selectedItemAnnouncement
            announceFeedback()
        }
    }

    func receive(
        _ input: RivoRemoteInput
    ) -> RivoRemoteCommand? {
        receiveDecision(input).command
    }

    func receiveDecision(
        _ input: RivoRemoteInput
    ) -> RivoRemoteDecision {
        switch input {
        case .sequence(let payload):
            guard payload == "a/" else {
                feedback = AppLocalization.format(
                    "지원하지 않는 시퀀스 %@",
                    payload
                )
                SoundEffectManager.shared.play(.fail)
                return RivoRemoteDecision(
                    command: nil,
                    consumed: true
                )
            }
            feedback = AppLocalization.string(
                "음성 명령 듣기"
            )
            hideMenu()
            isCommandModeActive = false
            return RivoRemoteDecision(
                command: .startVoiceAction,
                consumed: true
            )

        case .button(
            let button,
            let action,
            _
        ):
            if button == .l1,
               action == .doubleTapped {
                // Android L1 두 번: 메뉴 + 키 안내 키패드.
                presentMenu(showKeyGuide: true)
                return RivoRemoteDecision(
                    command: nil,
                    consumed: true
                )
            }
            if button == .r1,
               action == .doubleTapped {
                enterCommandMode(
                    showGuide: true
                )
                return RivoRemoteDecision(
                    command: nil,
                    consumed: true
                )
            }
            if action == .doubleTapped,
               let guide = modeGuide(for: button) {
                feedback = guide
                announceFeedback()
                return RivoRemoteDecision(
                    command: nil,
                    consumed: true
                )
            }
            guard action == .pressed else {
                return RivoRemoteDecision(
                    command: nil,
                    consumed: isMenuPresented
                )
            }

            if button == .l4 || button == .r4 {
                SoundEffectManager.shared.play(.fail)
                feedback =
                    AppLocalization.string(
                        "Android의 다른 앱 화면 확대 이동은 iPadOS에서 지원되지 않습니다. 앱의 카메라 돋보기를 사용해 주세요."
                    )
                announceFeedback()
                return RivoRemoteDecision(
                    command: nil,
                    consumed: true
                )
            }
            if button == .r3 {
                feedback = AppLocalization.string(
                    "음성 읽기 정지"
                )
                return RivoRemoteDecision(
                    command: .stopSpeech,
                    consumed: true
                )
            }
            if button == .r1 {
                enterCommandMode(
                    showGuide: false
                )
                return RivoRemoteDecision(
                    command: nil,
                    consumed: true
                )
            }
            if button == .l1 {
                if isMenuPresented {
                    dismissMenu()
                } else {
                    presentMenu(showKeyGuide: false)
                }
                return RivoRemoteDecision(
                    command: nil,
                    consumed: true
                )
            }
            if isCommandModeActive {
                return commandModeDecision(
                    for: button
                )
            }
            guard isMenuPresented else {
                return RivoRemoteDecision(
                    command: nil,
                    consumed: false
                )
            }
            restartAutoCloseTimer()
            if isKeyGuidePresented,
               button != .star {
                isKeyGuidePresented = false
            }

            let command: RivoRemoteCommand?
            switch button {
            case .one:
                selectedIndex = 0
                announceSelection()
                command = nil
            case .two:
                command =
                    activateAdjustment(
                        increase: true
                    )
            case .four:
                moveSelection(by: -1)
                command = nil
            case .six:
                moveSelection(by: 1)
                command = nil
            case .eight:
                command =
                    activateAdjustment(
                        increase: false
                    )
            case .seven:
                selectedIndex = max(items.count - 1, 0)
                announceSelection()
                command = nil
            case .five:
                command = activateSelection()
            case .zero:
                hideMenu()
                feedback = AppLocalization.string(
                    "홈으로 이동"
                )
                command = .home
            case .star:
                goBackInMenu()
                command = nil
            default:
                feedback = AppLocalization.format(
                    "%@ 버튼",
                    button.title
                )
                command = nil
            }
            return RivoRemoteDecision(
                command: command,
                consumed: true
            )
        }
    }

    func activateItem(
        at index: Int
    ) -> RivoRemoteCommand? {
        guard items.indices.contains(index) else {
            SoundEffectManager.shared.play(.fail)
            return nil
        }
        selectedIndex = index
        restartAutoCloseTimer()
        return activateSelection()
    }

    /// 펼친 줄의 −/+ 버튼(Android 펼침 줄 48dp 조절 버튼).
    func adjustItem(
        at index: Int,
        increase: Bool
    ) -> RivoRemoteCommand? {
        guard items.indices.contains(index) else {
            SoundEffectManager.shared.play(.fail)
            return nil
        }
        selectedIndex = index
        restartAutoCloseTimer()
        return activateAdjustment(increase: increase)
    }

    func focusItem(at index: Int) {
        guard items.indices.contains(index)
        else {
            return
        }
        selectedIndex = index
        restartAutoCloseTimer()
        announceSelection()
    }

    func dismissMenu() {
        hideMenu()
        feedback = AppLocalization.string(
            "빠른 메뉴 닫힘"
        )
    }

    func goBackInMenu() {
        restartAutoCloseTimer()
        if isKeyGuidePresented {
            isKeyGuidePresented = false
            feedback = selectedItemAnnouncement
            announceFeedback()
            return
        }
        guard let previous = pageStack.popLast()
        else {
            SoundEffectManager.shared.play(.popUp2)
            dismissMenu()
            return
        }
        SoundEffectManager.shared.play(
            .toggleButtonPressed
        )
        currentPage = previous.page
        selectedIndex = min(
            max(previous.selectedIndex, 0),
            max(items.count - 1, 0)
        )
        feedback = selectedItemAnnouncement
        announceFeedback()
    }

    func announceStopSpeaking() {
        SoundEffectManager.shared.play(.bbob)
        feedback = AppLocalization.string(
            "음성 읽기 정지"
        )
        announceFeedback()
    }

    func dismissCommandMode() {
        isCommandModeActive = false
        feedback = AppLocalization.string(
            "명령 모드 닫힘"
        )
    }

    // MARK: - 메뉴 표시·자동 닫힘·세션 복원 (Android `RemoteRibbonOverlay.show/hide`)

    private func presentMenu(showKeyGuide: Bool) {
        isCommandModeActive = false
        restoreSessionIfRecent()
        isMenuPresented = true
        isKeyGuidePresented = showKeyGuide
        SoundEffectManager.shared.play(
            .toggleButtonPressed
        )
        flashModeName(.menu)
        restartAutoCloseTimer()
        feedback = showKeyGuide
            ? keyGuideMode.accessibilitySummary
            : selectedItemAnnouncement
        if showKeyGuide {
            announceFeedback()
        }
    }

    private func hideMenu() {
        autoCloseTask?.cancel()
        autoCloseTask = nil
        if isMenuPresented {
            savedSession = MenuSession(
                page: currentPage,
                selectedIndex: selectedIndex,
                pageStack: pageStack,
                screen: activeScreen,
                closedAt: Self.uptime
            )
        }
        isMenuPresented = false
        isKeyGuidePresented = false
    }

    private func restoreSessionIfRecent() {
        guard let session = savedSession else {
            return
        }
        savedSession = nil
        guard Self.uptime - session.closedAt
                <= Self.sessionRestoreWindow,
              session.screen == activeScreen else {
            return
        }
        pageStack = session.pageStack
        currentPage = session.page
        selectedIndex = min(
            max(session.selectedIndex, 0),
            max(items.count - 1, 0)
        )
    }

    private func restartAutoCloseTimer() {
        autoCloseTask?.cancel()
        guard isMenuPresented else {
            return
        }
        autoCloseTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(
                    Self.autoCloseDelay * 1_000_000_000
                )
            )
            guard !Task.isCancelled,
                  let self,
                  self.isMenuPresented else {
                return
            }
            self.dismissMenu()
        }
    }

    private func flashModeName(
        _ mode: RivoRemoteKeyMode
    ) {
        modeNameFlashTask?.cancel()
        modeNameFlash = mode
        modeNameFlashTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds:
                    RivoRemoteKeyMode
                    .modeNameVisibleNanoseconds
            )
            guard !Task.isCancelled else {
                return
            }
            self?.modeNameFlash = nil
        }
    }

    /// Android `shouldCloseRibbonAfterSelection`: 도구·위젯 페이지만 닫고, DAISY·카메라·텍스트 페이지는 열어 둔다.
    /// 화면을 옮기는 명령(이동·음성 명령·홈·뒤로)은 어느 페이지에서든 닫는다.
    private func shouldCloseMenuAfterSelection(
        _ command: RivoRemoteCommand
    ) -> Bool {
        switch command {
        case .navigate, .startVoiceAction, .home, .back:
            return true
        default:
            break
        }
        return currentPage == .tools
            || currentPage == .widgets
    }

    private static var uptime: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    private var selectedItemAnnouncement: String {
        guard items.indices.contains(selectedIndex) else {
            return AppLocalization.string(
                "빠른 메뉴"
            )
        }
        let item = items[selectedIndex]
        let title = item.isSubmenu
            ? AppLocalization.format(
                "%@, 하위 메뉴",
                item.title
            )
            : item.title
        return AppLocalization.format(
            "%@, %lld/%lld",
            title,
            selectedIndex + 1,
            items.count
        )
    }

    private func moveSelection(by delta: Int) {
        guard !items.isEmpty else {
            SoundEffectManager.shared.play(.fail)
            return
        }
        selectedIndex = (
            selectedIndex + delta + items.count
        ) % items.count
        announceSelection()
    }

    private func announceSelection() {
        feedback = selectedItemAnnouncement
        announceFeedback()
    }

    private func announceFeedback() {
        UIAccessibility.post(
            notification: .announcement,
            argument: feedback
        )
    }

    private func modeGuide(
        for button: RivoButton
    ) -> String? {
        switch button {
        case .r1:
            return AppLocalization.string(
                "명령 모드 안내. R1 뒤 2 번역, 3 실시간 텍스트 읽기, 4 카메라 돋보기, 9 이미지 설명입니다."
            )
        case .l2:
            return AppLocalization.string(
                "화면 색상 안내. 카메라 돋보기나 로컬 문서에서 L2 화면 색상 모드를 사용할 수 있습니다."
            )
        case .l3:
            return AppLocalization.string(
                "문서 조작 안내. TXT 또는 PDF 로컬 문서에서 L3 문서 탐색 모드를 사용할 수 있습니다."
            )
        case .l4:
            return AppLocalization.string(
                "화면 위치 점프 안내. Android의 다른 앱 화면 확대 이동은 iPadOS 공개 API로 지원되지 않습니다. 카메라 돋보기를 사용해 주세요."
            )
        case .r4:
            return AppLocalization.string(
                "화면 연속 이동 안내. Android의 다른 앱 화면 확대 스크롤은 iPadOS 공개 API로 지원되지 않습니다. 카메라 돋보기를 사용해 주세요."
            )
        default:
            return nil
        }
    }

    private func activateSelection() -> RivoRemoteCommand? {
        guard items.indices.contains(selectedIndex) else {
            SoundEffectManager.shared.play(.fail)
            return nil
        }
        let item = items[selectedIndex]
        if let destinationPage = item.destinationPage {
            SoundEffectManager.shared.play(.bbob)
            pageStack.append(
                PageState(
                    page: currentPage,
                    selectedIndex: selectedIndex
                )
            )
            currentPage = destinationPage
            selectedIndex = 0
            feedback = selectedItemAnnouncement
            announceFeedback()
            restartAutoCloseTimer()
            return nil
        }
        guard let command = item.command else {
            SoundEffectManager.shared.play(.fail)
            return nil
        }
        SoundEffectManager.shared.play(.bbob)
        isCommandModeActive = false
        feedback = AppLocalization.format(
            "%@ 실행",
            item.title
        )
        if shouldCloseMenuAfterSelection(command) {
            hideMenu()
        } else {
            announceFeedback()
            restartAutoCloseTimer()
        }
        return command
    }

    private func activateAdjustment(
        increase: Bool
    ) -> RivoRemoteCommand? {
        guard items.indices.contains(
            selectedIndex
        ) else {
            SoundEffectManager.shared.play(.fail)
            return nil
        }
        let item = items[selectedIndex]
        let command = increase
            ? item.increaseCommand
            : item.decreaseCommand
        guard let command else {
            feedback = AppLocalization.format(
                "%@은 조절 항목이 아닙니다.",
                item.title
            )
            announceFeedback()
            return nil
        }
        SoundEffectManager.shared.play(.bbob)
        feedback = AppLocalization.format(
            increase
                ? "%@ 증가"
                : "%@ 감소",
            item.title
        )
        announceFeedback()
        return command
    }

    private func enterCommandMode(
        showGuide: Bool
    ) {
        hideMenu()
        isCommandModeActive = true
        flashModeName(.command)
        feedback = showGuide
            ? AppLocalization.string(
                "명령 모드. 2 클립보드 번역, 3 실시간 텍스트 읽기, 4 카메라 돋보기, 9 이미지 설명. 카메라를 연 뒤 5 전환, 6 토치, 7 촬영, 별표 0 샵 확대를 사용합니다."
            )
            : AppLocalization.string(
                "명령 모드. 2 번역, 3 텍스트 읽기, 4 카메라, 9 이미지 설명"
            )
        announceFeedback()
    }

    private func commandModeDecision(
        for button: RivoButton
    ) -> RivoRemoteDecision {
        let destination:
            RivoQuickDestination?
        let message: String

        switch button {
        case .two:
            destination = .translation
            message =
                AppLocalization.string(
                    "클립보드 번역 열기"
                )
        case .three:
            destination =
                .liveTextReader
            message =
                AppLocalization.string(
                    "실시간 텍스트 읽기 열기"
                )
        case .four:
            destination = .magnifier
            message =
                AppLocalization.string(
                    "카메라 돋보기 열기"
                )
        case .nine:
            destination =
                .imageDescription
            message =
                AppLocalization.string(
                    "이미지 설명 카메라 열기"
                )
        case .five,
             .six,
             .seven,
             .star,
             .zero,
             .sharp:
            destination = .magnifier
            message =
                AppLocalization.string(
                    "카메라 돋보기를 엽니다. R1을 누른 뒤 같은 키를 다시 사용해 주세요."
                )
        default:
            destination = nil
            message =
                AppLocalization.format(
                    "명령 모드에서 지원하지 않는 %@ 버튼",
                    button.title
                )
        }

        feedback = message
        announceFeedback()
        guard let destination else {
            return RivoRemoteDecision(
                command: nil,
                consumed: true
            )
        }
        isCommandModeActive = false
        return RivoRemoteDecision(
            command:
                .navigate(destination),
            consumed: true
        )
    }
}

struct RivoQuickMenuOverlay: View {
    @ObservedObject var controlCenter: RivoRemoteControlCenter
    @ObservedObject private var settings =
        AppSettingsStore.shared
    let onCommand: (RivoRemoteCommand) -> Void

    private var theme: LocalDocumentColorTheme {
        let themes = LocalDocumentColorTheme.all
        let index = min(
            max(
                settings.rivoQuickMenuColorIndex,
                0
            ),
            max(themes.count - 1, 0)
        )
        return themes[index]
    }

    private var backgroundColor: Color {
        color(hex: theme.backgroundHex)
    }

    private var foregroundColor: Color {
        color(hex: theme.foregroundHex)
    }

    /// Android 리모컨 조작 메뉴 색 조합: 선택 강조는 글자색 면 + 바탕색 글자(반전)로, 고정 파랑을 쓰지 않는다.
    private var accentColor: Color {
        foregroundColor
    }

    private var accentForegroundColor: Color {
        backgroundColor
    }

    private var indexedItems: [
        (
            offset: Int,
            element: RivoQuickMenuItem
        )
    ] {
        Array(
            controlCenter.items.enumerated()
        )
    }

    private var compactItems: [
        (
            offset: Int,
            element: RivoQuickMenuItem
        )
    ] {
        let indexed = indexedItems
        guard indexed.count > 1,
              indexed.indices.contains(
                  controlCenter.selectedIndex
              ) else {
            return indexed
        }
        let selected =
            controlCenter.selectedIndex
        let previous =
            selected == 0
            ? indexed.count - 1
            : selected - 1
        let next =
            (selected + 1)
            % indexed.count
        return [
            indexed[previous],
            indexed[selected],
            indexed[next],
        ]
    }

    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding = min(
                max(geometry.size.width * 0.05, 20),
                64
            )
            let panelHeight = settings.rivoQuickMenuExpanded
                ? min(max(geometry.size.height * 0.8, 520), 760)
                : min(max(geometry.size.height * 0.48, 380), 520)

            ZStack(alignment: .bottom) {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    if controlCenter.canGoBackInMenu {
                        VisionCraftBackButton(tint: foregroundColor) {
                            controlCenter.goBackInMenu()
                        }
                    }

                    Text(controlCenter.pageTitle)
                        .font(.system(size: 30, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer()

                    Button(
                        "키 안내",
                        systemImage: "questionmark.circle"
                    ) {
                        controlCenter.toggleKeyGuide()
                    }
                    .labelStyle(.iconOnly)
                    .font(.system(size: 25, weight: .bold))
                    .frame(width: 58, height: 58)
                    .background(
                        controlCenter.isKeyGuidePresented
                            ? accentColor.opacity(0.28)
                            : foregroundColor.opacity(0.14)
                    )
                    .clipShape(Circle())
                    .accessibilityValue(
                        Text(
                            verbatim:
                                controlCenter.isKeyGuidePresented
                                ? AppLocalization.string("열림")
                                : ""
                        )
                    )

                    Button(
                        "음성 읽기 정지",
                        systemImage: "speaker.slash.fill"
                    ) {
                        controlCenter.announceStopSpeaking()
                        onCommand(.stopSpeech)
                    }
                    .labelStyle(.iconOnly)
                    .font(.system(size: 25, weight: .bold))
                    .frame(width: 58, height: 58)
                    .background(
                        foregroundColor.opacity(0.14)
                    )
                    .clipShape(Circle())

                    Button("닫기", systemImage: "xmark") {
                        SoundEffectManager.shared.play(
                            .bbob
                        )
                        controlCenter.dismissMenu()
                    }
                    .labelStyle(.iconOnly)
                    .font(.system(size: 28, weight: .bold))
                    .frame(width: 58, height: 58)
                    .background(
                        foregroundColor.opacity(0.14)
                    )
                    .clipShape(Circle())
                }

                if settings
                    .rivoQuickMenuExpanded {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(
                                indexedItems,
                                id: \.element.id
                            ) { index, item in
                                expandedMenuRow(
                                    item,
                                    at: index
                                )
                            }
                        }
                    }
                } else {
                    spotlightMenu
                }

                keyGuide
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity)
            .frame(height: panelHeight)
            .background(
                backgroundColor.opacity(0.97)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 32,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 32,
                    style: .continuous
                )
                .stroke(
                    foregroundColor.opacity(0.28),
                    lineWidth: 2
                )
            }
            .overlay {
                if controlCenter.isKeyGuidePresented {
                    ZStack {
                        Color.black.opacity(0.79)
                        ScrollView {
                            RivoRemoteKeyGuideView(
                                mode: controlCenter.keyGuideMode,
                                onDismiss: {
                                    controlCenter.dismissKeyGuide()
                                }
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 32,
                            style: .continuous
                        )
                    )
                    .transition(.opacity)
                }
            }
            .shadow(color: .black.opacity(0.34), radius: 30)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            if let mode = controlCenter.modeNameFlash {
                RivoRemoteModeNameFlash(mode: mode)
                    .transition(.opacity)
            }
            }
        }
        .animation(
            .easeInOut(duration: 0.16),
            value: controlCenter.isKeyGuidePresented
        )
        .animation(
            .easeInOut(duration: 0.16),
            value: controlCenter.modeNameFlash
        )
        .transition(
            .move(edge: .bottom)
                .combined(with: .opacity)
        )
        .animation(
            .snappy(duration: 0.24),
            value: controlCenter.selectedIndex
        )
    }

    private var spotlightMenu: some View {
        GeometryReader { geometry in
            let spacing = min(
                max(geometry.size.width * 0.025, 8),
                18
            )
            let sideWidth = min(
                max(geometry.size.width * 0.19, 60),
                200
            )
            let centerWidth = max(
                geometry.size.width
                    - (sideWidth * 2)
                    - (spacing * 2),
                150
            )

            HStack(spacing: spacing) {
                ForEach(
                    compactItems,
                    id: \.offset
                ) { index, item in
                    compactMenuItem(
                        item,
                        at: index
                    )
                    .frame(
                        width:
                            index
                            == controlCenter.selectedIndex
                            ? centerWidth
                            : sideWidth
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 190, maxHeight: 230)
    }

    private var keyGuide: some View {
        HStack(spacing: 12) {
            Text(
                AppLocalization.string(
                    "L1 메뉴 · 4/6 이동 · 2/8 조절"
                )
            )
            .foregroundStyle(
                foregroundColor.opacity(0.88)
            )

            Text(
                AppLocalization.string("5 선택")
            )
            .foregroundStyle(accentForegroundColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(accentColor)
            .clipShape(Capsule())

            Text(
                AppLocalization.string(
                    "0 홈 · 별표 뒤로/닫기"
                )
            )
            .foregroundStyle(
                foregroundColor.opacity(0.88)
            )
        }
        .font(.system(size: 22, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            foregroundColor.opacity(0.1)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
    }

    private func expandedMenuRow(
        _ item: RivoQuickMenuItem,
        at index: Int
    ) -> some View {
        let isSelected =
            index
            == controlCenter.selectedIndex
        return Button {
            if let command =
                controlCenter.activateItem(
                    at: index
                ) {
                onCommand(command)
            }
        } label: {
            HStack(spacing: 16) {
                Image(
                    systemName:
                        item.systemImage
                )
                .font(.system(size: 34, weight: .semibold))
                .frame(width: 48)
                Text(item.title)
                    .font(.system(size: 27, weight: .bold))
                Spacer()
                if item.isAdjustable {
                    // Android 펼침 줄: 조절 항목은 −/+ 48dp 버튼.
                    HStack(spacing: 8) {
                        adjustButton(
                            systemImage: "minus",
                            label: AppLocalization.format(
                                "%@ 감소",
                                item.title
                            ),
                            index: index,
                            increase: false
                        )
                        adjustButton(
                            systemImage: "plus",
                            label: AppLocalization.format(
                                "%@ 증가",
                                item.title
                            ),
                            index: index,
                            increase: true
                        )
                    }
                }
                if item.isSubmenu {
                    Text("›")
                        .font(.system(size: 34, weight: .bold))
                        .accessibilityHidden(true)
                }
                if isSelected {
                    Image(
                        systemName:
                            "circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(accentColor)
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 22)
            .frame(minHeight: 82)
            .frame(maxWidth: .infinity)
            .background(
                isSelected
                    ? accentColor.opacity(0.16)
                    : foregroundColor
                        .opacity(0.12)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
                .stroke(
                    isSelected
                        ? accentColor
                        : Color.clear,
                    lineWidth: 4
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            item.isSubmenu
                ? AppLocalization.format(
                    "%@, 하위 메뉴",
                    item.title
                )
                : item.title
        )
        .accessibilityValue(
            Text(
                verbatim:
                    isSelected
                    ? AppLocalization.string(
                        "선택됨"
                    )
                    : ""
            )
        )
    }

    private func adjustButton(
        systemImage: String,
        label: String,
        index: Int,
        increase: Bool
    ) -> some View {
        Button {
            if let command =
                controlCenter.adjustItem(
                    at: index,
                    increase: increase
                ) {
                onCommand(command)
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(foregroundColor)
                .frame(width: 48, height: 48)
                .background(
                    foregroundColor.opacity(0.14),
                    in: Circle()
                )
                .overlay {
                    Circle().strokeBorder(
                        foregroundColor.opacity(0.5),
                        lineWidth: 1
                    )
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func compactMenuItem(
        _ item: RivoQuickMenuItem,
        at index: Int
    ) -> some View {
        let isSelected =
            index
            == controlCenter.selectedIndex
        return Button {
            if isSelected {
                if let command =
                    controlCenter.activateItem(
                        at: index
                    ) {
                    onCommand(command)
                }
            } else {
                controlCenter.focusItem(
                    at: index
                )
            }
        } label: {
            VStack(spacing: isSelected ? 16 : 10) {
                Image(
                    systemName:
                        item.systemImage
                )
                .font(.system(
                    size: isSelected ? 62 : 34,
                    weight: .semibold
                    )
                )
                .foregroundStyle(
                    isSelected
                        ? accentForegroundColor
                        : foregroundColor
                )
                .frame(
                    width: isSelected ? 100 : 60,
                    height: isSelected ? 100 : 60
                )
                .background(
                    isSelected
                        ? accentColor
                        : Color.clear
                )
                .clipShape(Circle())
                Text(item.title)
                    .font(.system(
                        size: isSelected ? 34 : 21,
                        weight: .bold
                        )
                    )
                    .multilineTextAlignment(
                        .center
                    )
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                if item.isSubmenu {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(
                            .system(
                                size: isSelected ? 24 : 18,
                                weight: .bold
                            )
                        )
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(foregroundColor)
            .opacity(
                isSelected ? 1 : 0.62
            )
            .frame(maxWidth: .infinity)
            .frame(height: isSelected ? 214 : 164)
            .background(
                isSelected
                    ? accentColor.opacity(0.16)
                    : foregroundColor.opacity(0.1)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
                .stroke(
                    isSelected
                        ? accentColor
                        : foregroundColor.opacity(0.28),
                    lineWidth: isSelected ? 4 : 1
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            item.isSubmenu
                ? AppLocalization.format(
                    "%@, 하위 메뉴",
                    item.title
                )
                : item.title
        )
        .accessibilityValue(
            Text(
                verbatim:
                    isSelected
                    ? AppLocalization.string(
                        "선택됨"
                    )
                    : ""
            )
        )
    }

    private func color(hex: Int) -> Color {
        Color(
            red:
                Double(
                    (hex >> 16) & 0xFF
                ) / 255,
            green:
                Double(
                    (hex >> 8) & 0xFF
                ) / 255,
            blue:
                Double(hex & 0xFF)
                / 255
        )
    }
}

/// Android `RemoteModeOverlay`(COMMAND): 모드 이름 1.15초 + COMMAND 키 안내 키패드(3×4 + R3).
struct RivoCommandModeOverlay: View {
    @ObservedObject var controlCenter:
        RivoRemoteControlCenter

    var body: some View {
        ZStack {
            Color.black.opacity(0.79)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            ScrollView {
                VStack(spacing: 12) {
                    RivoRemoteKeyGuideView(
                        mode: .command,
                        onDismiss: {
                            controlCenter.dismissCommandMode()
                        }
                    )
                    Text(
                        AppLocalization.string(
                            "2·3·4·9는 바로 실행합니다. 카메라 키는 돋보기에서 R1 뒤 사용합니다."
                        )
                    )
                    .visionCraftAndroidText(
                        16,
                        relativeTo: .footnote
                    )
                    .foregroundStyle(
                        VisionCraftUI.fixedColor(0xDCDCDC)
                    )
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
            }

            if let mode = controlCenter.modeNameFlash {
                RivoRemoteModeNameFlash(mode: mode)
                    .transition(.opacity)
            }
        }
        .animation(
            .easeInOut(duration: 0.16),
            value: controlCenter.modeNameFlash
        )
        .transition(.opacity)
    }
}
