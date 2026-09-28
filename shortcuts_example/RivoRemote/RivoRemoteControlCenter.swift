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

    private struct PageState {
        let page: RivoQuickMenuPage
        let selectedIndex: Int
    }

    private var pageStack: [PageState] = []

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
            RivoQuickMenuItem(
                id: "camera.back",
                title: AppLocalization.string("뒤로"),
                systemImage: "chevron.backward",
                command: magnifierCommand(.close)
            ),
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
                title: "전면/후면",
                systemImage:
                    "arrow.triangle.2.circlepath.camera",
                action: .switchCamera
            ),
            magnifierItem(
                id: "camera.torch",
                title: "라이트",
                systemImage: "flashlight.on.fill",
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
            RivoQuickMenuItem(
                id: "document.back",
                title: AppLocalization.string("뒤로"),
                systemImage: "chevron.backward",
                command: .back
            ),
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
            RivoQuickMenuItem(
                id: "reader.back",
                title: AppLocalization.string("뒤로"),
                systemImage: "chevron.backward",
                command: .back
            ),
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
            isMenuPresented = false
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
                isCommandModeActive = false
                isMenuPresented = true
                SoundEffectManager.shared.play(
                    .toggleButtonPressed
                )
                feedback = selectedItemAnnouncement
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
                isCommandModeActive = false
                isMenuPresented.toggle()
                if isMenuPresented {
                    SoundEffectManager.shared.play(
                        .toggleButtonPressed
                    )
                }
                feedback = isMenuPresented
                    ? selectedItemAnnouncement
                    : AppLocalization.string(
                        "빠른 메뉴 닫힘"
                    )
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
                isMenuPresented = false
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
        return activateSelection()
    }

    func focusItem(at index: Int) {
        guard items.indices.contains(index)
        else {
            return
        }
        selectedIndex = index
        announceSelection()
    }

    func dismissMenu() {
        isMenuPresented = false
        feedback = AppLocalization.string(
            "빠른 메뉴 닫힘"
        )
    }

    func goBackInMenu() {
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
            return nil
        }
        guard let command = item.command else {
            SoundEffectManager.shared.play(.fail)
            return nil
        }
        SoundEffectManager.shared.play(.bbob)
        isMenuPresented = false
        isCommandModeActive = false
        feedback = AppLocalization.format(
            "%@ 실행",
            item.title
        )
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
        isMenuPresented = false
        isCommandModeActive = true
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

    private var accentColor: Color {
        color(
            hex: backgroundIsLight
                ? 0x0066CC
                : 0x64D2FF
        )
    }

    private var accentForegroundColor: Color {
        backgroundIsLight ? .white : .black
    }

    private var backgroundIsLight: Bool {
        let hex = theme.backgroundHex
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        return (red * 0.2126)
            + (green * 0.7152)
            + (blue * 0.0722) > 0.6
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
                        Button("뒤로", systemImage: "chevron.left") {
                            controlCenter.goBackInMenu()
                        }
                        .labelStyle(.iconOnly)
                        .font(.system(size: 26, weight: .bold))
                        .frame(width: 58, height: 58)
                        .background(
                            foregroundColor.opacity(0.14)
                        )
                        .clipShape(Circle())
                    }

                    Text(controlCenter.pageTitle)
                        .font(.system(size: 30, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer()

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
            .shadow(color: .black.opacity(0.34), radius: 30)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            }
        }
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
                if item.isSubmenu {
                    Image(systemName: "chevron.right")
                        .font(.title2.bold())
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

struct RivoCommandModeOverlay: View {
    @ObservedObject var controlCenter:
        RivoRemoteControlCenter

    private var commands: [
        (
            key: String,
            title: String
        )
    ] {
        [
            ("1", "—"),
            (
                "2",
                AppLocalization.string("번역")
            ),
            ("3", "OCR"),
            (
                "4",
                AppLocalization.string("카메라")
            ),
            (
                "5",
                AppLocalization.string("전·후면")
            ),
            (
                "6",
                AppLocalization.string("토치")
            ),
            (
                "7",
                AppLocalization.string("촬영")
            ),
            ("8", "—"),
            (
                "9",
                AppLocalization.string(
                    "이미지 설명"
                )
            ),
            (
                AppLocalization.string("별표"),
                AppLocalization.string("줌 축소")
            ),
            (
                "0",
                AppLocalization.string("줌 초기화")
            ),
            (
                AppLocalization.string("샵"),
                AppLocalization.string("줌 확대")
            ),
        ]
    }

    private let columns = Array(
        repeating:
            GridItem(
                .flexible(),
                spacing: 10
            ),
        count: 3
    )

    var body: some View {
        HStack {
            Spacer(minLength: 48)

            VStack(
                alignment: .leading,
                spacing: 16
            ) {
                HStack {
                    Text("Rivo 명령 모드")
                        .font(.title.bold())
                    Spacer()
                    Button(
                        "닫기",
                        systemImage: "xmark"
                    ) {
                        controlCenter
                            .dismissCommandMode()
                    }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                }

                LazyVGrid(
                    columns: columns,
                    spacing: 10
                ) {
                    ForEach(
                        Array(
                            commands.enumerated()
                        ),
                        id: \.offset
                    ) { _, command in
                        VStack(spacing: 5) {
                            Text(command.key)
                                .font(
                                    .title2
                                    .monospaced()
                                    .bold()
                                )
                            Text(command.title)
                                .font(.subheadline)
                                .lineLimit(1)
                                .minimumScaleFactor(
                                    0.75
                                )
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 68
                        )
                        .background(
                            Color.white
                                .opacity(0.12)
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 14,
                                style:
                                    .continuous
                            )
                        )
                        .accessibilityElement(
                            children: .combine
                        )
                        .accessibilityLabel(
                            AppLocalization.format(
                                "%@, %@",
                                command.key,
                                command.title
                            )
                        )
                    }
                }

                Text(
                    AppLocalization.string(
                        "2·3·4·9는 바로 실행합니다. 카메라 키는 돋보기에서 R1 뒤 사용합니다."
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
            .padding(24)
            .frame(width: 420)
            .background(.black.opacity(0.94))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 28,
                    style: .continuous
                )
            )
            .shadow(radius: 24)
            .padding(24)
        }
        .transition(
            .move(edge: .trailing)
                .combined(with: .opacity)
        )
    }
}
