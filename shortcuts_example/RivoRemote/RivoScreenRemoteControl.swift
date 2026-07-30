import Combine
import Foundation

nonisolated enum RivoRemoteScreen:
    Equatable,
    Sendable
{
    case magnifier
    case liveTextReader
    case documentScanner
    case publicationReader
    case localDocumentReader
    case localAIChat
    case voiceAction
}

nonisolated enum RivoMagnifierRemoteAction:
    Equatable,
    Sendable
{
    case enterCameraMode(showGuide: Bool)
    case enterDisplayMode(showGuide: Bool)
    case close
    case switchCamera
    case toggleTorch
    case capture
    case focus
    case decreaseZoom
    case resetZoom
    case increaseZoom
    case previousColor
    case originalColor
    case nextColor
    case decreaseThreshold
    case resetThreshold
    case increaseThreshold
    case decreaseBrightness
    case resetBrightness
    case increaseBrightness
    case invertColor
}

nonisolated enum RivoMagnifierRemoteMode:
    Equatable,
    Sendable
{
    case camera
    case display
}

nonisolated enum RivoDocumentScannerRemoteAction:
    Equatable,
    Sendable
{
    case close
    case capture
}

nonisolated enum RivoPublicationReaderRemoteAction:
    Equatable,
    Sendable
{
    case previous
    case togglePlayback
    case next
    case previousNavigationUnit
    case nextNavigationUnit
}

nonisolated enum RivoLocalDocumentRemoteAction:
    Equatable,
    Sendable
{
    case enterTextMode(showGuide: Bool)
    case enterDisplayMode(showGuide: Bool)
    case beginning
    case previousLine
    case previousPage
    case decreaseFont
    case defaultFont
    case increaseFont
    case end
    case nextLine
    case nextPage
    case decreaseLineHeight
    case defaultLineHeight
    case increaseLineHeight
    case previousColor
    case originalColor
    case nextColor
    case invertColor
    case toggleReading

    func updatedAppearance(
        from appearance:
            LocalDocumentAppearance
    ) -> LocalDocumentAppearance? {
        var updated = appearance
        switch self {
        case .decreaseFont:
            updated.fontLevel -= 1
        case .defaultFont:
            updated.fontLevel =
                LocalDocumentAppearance
                .defaultValue.fontLevel
        case .increaseFont:
            updated.fontLevel += 1
        case .decreaseLineHeight:
            updated.lineHeightLevel -= 1
        case .defaultLineHeight:
            updated.lineHeightLevel =
                LocalDocumentAppearance
                .defaultValue
                .lineHeightLevel
        case .increaseLineHeight:
            updated.lineHeightLevel += 1
        case .previousColor:
            let count =
                LocalDocumentColorTheme.all.count
            guard count > 0 else {
                return updated
            }
            let current =
                updated.normalized(
                    colorCount: count
                ).colorIndex
            updated.colorIndex =
                (
                    current
                        - 1
                        + count
                ) % count
        case .originalColor:
            updated.colorIndex = 0
        case .nextColor:
            let count =
                LocalDocumentColorTheme.all.count
            guard count > 0 else {
                return updated
            }
            let current =
                updated.normalized(
                    colorCount: count
                ).colorIndex
            updated.colorIndex =
                (current + 1)
                % count
        case .invertColor:
            updated.colorIndex =
                Self.invertedColorIndex(
                    from: updated.colorIndex
                )
        default:
            return nil
        }
        return updated.normalized()
    }

    private static func invertedColorIndex(
        from colorIndex: Int
    ) -> Int {
        let themes = LocalDocumentColorTheme.all
        guard !themes.isEmpty else {
            return 0
        }
        let currentIndex = min(
            max(colorIndex, 0),
            themes.count - 1
        )
        let current = themes[currentIndex]
        if let invertedIndex = themes.firstIndex(
            where: {
                $0.backgroundHex
                    == current.foregroundHex
                    && $0.foregroundHex
                        == current.backgroundHex
            }
        ) {
            return invertedIndex
        }
        return currentIndex == 0
            ? min(1, themes.count - 1)
            : 0
    }
}

nonisolated enum RivoLocalDocumentRemoteMode:
    Equatable,
    Sendable
{
    case text
    case display
}

nonisolated enum RivoLocalAIChatRemoteAction:
    Equatable,
    Sendable
{
    case toggleVoiceInput
}

nonisolated enum RivoVoiceActionRemoteAction:
    Equatable,
    Sendable
{
    case cancel
}

nonisolated enum RivoScreenRemoteAction:
    Equatable,
    Sendable
{
    case magnifier(RivoMagnifierRemoteAction)
    case documentScanner(
        RivoDocumentScannerRemoteAction
    )
    case publicationReader(
        RivoPublicationReaderRemoteAction
    )
    case localDocumentReader(
        RivoLocalDocumentRemoteAction
    )
    case localAIChat(
        RivoLocalAIChatRemoteAction
    )
    case voiceAction(
        RivoVoiceActionRemoteAction
    )
}

nonisolated struct RivoScreenRemoteEvent:
    Equatable,
    Sendable
{
    let id: UInt64
    let screen: RivoRemoteScreen
    let action: RivoScreenRemoteAction
}

nonisolated enum RivoScreenInputPriorityPolicy {
    static func shouldOfferToScreenFirst(
        _ input: RivoRemoteInput,
        isMenuPresented: Bool
    ) -> Bool {
        if case .sequence = input {
            return true
        }
        return !isMenuPresented
    }
}

nonisolated enum RivoScreenRemoteMapper {
    static func action(
        for input: RivoRemoteInput,
        on screen: RivoRemoteScreen,
        magnifierMode:
            RivoMagnifierRemoteMode = .camera,
        localDocumentMode:
            RivoLocalDocumentRemoteMode = .text
    ) -> RivoScreenRemoteAction? {
        if case .localAIChat = screen,
           case .sequence(let payload) = input,
           payload == "a/" {
            return .localAIChat(.toggleVoiceInput)
        }
        if case .voiceAction = screen,
           case .sequence(let payload) = input,
           payload == "a/" {
            return .voiceAction(.cancel)
        }

        guard case .button(
            let button,
            let buttonAction,
            _
        ) = input else {
            return nil
        }

        if screen == .magnifier
            || screen == .liveTextReader,
           let action = magnifierModeAction(
               for: button,
               buttonAction: buttonAction,
               mode: magnifierMode
           ) {
            return .magnifier(action)
        }

        if case .localDocumentReader = screen,
           let action = localDocumentModeAction(
               for: button,
               buttonAction: buttonAction,
               mode: localDocumentMode
           ) {
            return .localDocumentReader(action)
        }

        guard buttonAction == .pressed else {
            return nil
        }

        switch screen {
        case .magnifier, .liveTextReader:
            return nil
        case .documentScanner:
            switch button {
            case .four:
                return .documentScanner(.close)
            case .seven:
                return .documentScanner(.capture)
            default:
                return nil
            }
        case .publicationReader:
            switch button {
            case .four:
                return .publicationReader(.previous)
            case .five:
                return .publicationReader(
                    .togglePlayback
                )
            case .six:
                return .publicationReader(.next)
            case .two:
                return .publicationReader(
                    .previousNavigationUnit
                )
            case .eight:
                return .publicationReader(
                    .nextNavigationUnit
                )
            default:
                return nil
            }
        case .localDocumentReader:
            return nil
        case .localAIChat:
            return nil
        case .voiceAction:
            return nil
        }
    }

    private static func magnifierAction(
        for button: RivoButton
    ) -> RivoMagnifierRemoteAction? {
        switch button {
        case .four:
            return .close
        case .five:
            return .switchCamera
        case .six:
            return .toggleTorch
        case .seven:
            return .capture
        case .r2:
            return .focus
        case .star:
            return .decreaseZoom
        case .zero:
            return .resetZoom
        case .sharp:
            return .increaseZoom
        default:
            return nil
        }
    }

    private static func magnifierModeAction(
        for button: RivoButton,
        buttonAction: RivoButtonAction,
        mode: RivoMagnifierRemoteMode
    ) -> RivoMagnifierRemoteAction? {
        if button == .r1 {
            switch buttonAction {
            case .pressed:
                return .enterCameraMode(
                    showGuide: false
                )
            case .doubleTapped:
                return .enterCameraMode(
                    showGuide: true
                )
            default:
                return nil
            }
        }
        if button == .l2 {
            switch buttonAction {
            case .pressed:
                return .enterDisplayMode(
                    showGuide: false
                )
            case .doubleTapped:
                return .enterDisplayMode(
                    showGuide: true
                )
            default:
                return nil
            }
        }
        guard buttonAction == .pressed else {
            return nil
        }

        switch mode {
        case .camera:
            return magnifierAction(for: button)
        case .display:
            switch button {
            case .four:
                return .previousColor
            case .five:
                return .originalColor
            case .six:
                return .nextColor
            case .seven:
                return .decreaseThreshold
            case .eight:
                return .resetThreshold
            case .nine:
                return .increaseThreshold
            case .star:
                return .decreaseBrightness
            case .zero:
                return .resetBrightness
            case .sharp:
                return .increaseBrightness
            case .r2:
                return .invertColor
            default:
                return nil
            }
        }
    }

    private static func localDocumentAction(
        for button: RivoButton
    ) -> RivoLocalDocumentRemoteAction? {
        switch button {
        case .one:
            return .beginning
        case .two:
            return .previousLine
        case .three:
            return .previousPage
        case .four:
            return .decreaseFont
        case .five:
            return .defaultFont
        case .six:
            return .increaseFont
        case .seven:
            return .end
        case .eight:
            return .nextLine
        case .nine:
            return .nextPage
        case .star:
            return .decreaseLineHeight
        case .zero:
            return .defaultLineHeight
        case .sharp:
            return .increaseLineHeight
        default:
            return nil
        }
    }

    private static func localDocumentModeAction(
        for button: RivoButton,
        buttonAction: RivoButtonAction,
        mode: RivoLocalDocumentRemoteMode
    ) -> RivoLocalDocumentRemoteAction? {
        if button == .l2 {
            switch buttonAction {
            case .pressed:
                return .enterDisplayMode(
                    showGuide: false
                )
            case .doubleTapped:
                return .enterDisplayMode(
                    showGuide: true
                )
            default:
                return nil
            }
        }
        if button == .l3 {
            switch buttonAction {
            case .pressed:
                return .enterTextMode(
                    showGuide: false
                )
            case .doubleTapped:
                return .enterTextMode(
                    showGuide: true
                )
            default:
                return nil
            }
        }
        guard buttonAction == .pressed else {
            return nil
        }
        if button == .r3 {
            return .toggleReading
        }

        switch mode {
        case .text:
            return localDocumentAction(for: button)
        case .display:
            switch button {
            case .four:
                return .previousColor
            case .five:
                return .originalColor
            case .six:
                return .nextColor
            case .r2:
                return .invertColor
            default:
                return nil
            }
        }
    }
}

@MainActor
final class RivoScreenRemoteControlCenter:
    ObservableObject
{
    @Published private(set) var activeScreen:
        RivoRemoteScreen?
    @Published private(set) var latestEvent:
        RivoScreenRemoteEvent?
    @Published private(set) var localDocumentMode:
        RivoLocalDocumentRemoteMode = .text
    @Published private(set) var magnifierMode:
        RivoMagnifierRemoteMode = .camera

    private var nextEventID: UInt64 = 0

    func activate(_ screen: RivoRemoteScreen) {
        activeScreen = screen
        latestEvent = nil
        if screen == .localDocumentReader {
            localDocumentMode = .text
        }
        if screen == .magnifier
            || screen == .liveTextReader {
            magnifierMode = .camera
        }
    }

    func deactivate(_ screen: RivoRemoteScreen) {
        guard activeScreen == screen else {
            return
        }
        activeScreen = nil
        latestEvent = nil
    }

    @discardableResult
    func receive(_ input: RivoRemoteInput) -> Bool {
        guard let activeScreen,
              let action =
                RivoScreenRemoteMapper.action(
                    for: input,
                    on: activeScreen,
                    magnifierMode:
                        magnifierMode,
                    localDocumentMode:
                        localDocumentMode
                ) else {
            return false
        }
        if case .localDocumentReader(
            let documentAction
        ) = action {
            switch documentAction {
            case .enterTextMode:
                localDocumentMode = .text
            case .enterDisplayMode:
                localDocumentMode = .display
            default:
                break
            }
        }
        if case .magnifier(
            let magnifierAction
        ) = action {
            switch magnifierAction {
            case .enterCameraMode:
                magnifierMode = .camera
            case .enterDisplayMode:
                magnifierMode = .display
            default:
                break
            }
        }
        nextEventID &+= 1
        latestEvent = RivoScreenRemoteEvent(
            id: nextEventID,
            screen: activeScreen,
            action: action
        )
        return true
    }

    @discardableResult
    func receivePriorityInput(
        _ input: RivoRemoteInput
    ) -> Bool {
        if case .sequence = input {
            return receive(input)
        }
        guard activeScreen == .localDocumentReader,
              case .button(
                button: .r3,
                action: .pressed,
                rawKey: _
              ) = input else {
            return false
        }
        return receive(input)
    }
}
