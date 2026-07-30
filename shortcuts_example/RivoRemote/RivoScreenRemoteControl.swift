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
}

nonisolated enum RivoMagnifierRemoteAction:
    Equatable,
    Sendable
{
    case close
    case switchCamera
    case toggleTorch
    case capture
    case decreaseZoom
    case resetZoom
    case increaseZoom
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
        default:
            return nil
        }
        return updated.normalized()
    }
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
}

nonisolated struct RivoScreenRemoteEvent:
    Equatable,
    Sendable
{
    let id: UInt64
    let screen: RivoRemoteScreen
    let action: RivoScreenRemoteAction
}

nonisolated enum RivoScreenRemoteMapper {
    static func action(
        for input: RivoRemoteInput,
        on screen: RivoRemoteScreen
    ) -> RivoScreenRemoteAction? {
        guard case .button(
            let button,
            let buttonAction,
            _
        ) = input,
        buttonAction == .pressed else {
            return nil
        }

        switch screen {
        case .magnifier, .liveTextReader:
            return magnifierAction(for: button)
                .map(RivoScreenRemoteAction.magnifier)
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
            return localDocumentAction(
                for: button
            ).map(
                RivoScreenRemoteAction
                    .localDocumentReader
            )
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
}

@MainActor
final class RivoScreenRemoteControlCenter:
    ObservableObject
{
    @Published private(set) var activeScreen:
        RivoRemoteScreen?
    @Published private(set) var latestEvent:
        RivoScreenRemoteEvent?

    private var nextEventID: UInt64 = 0

    func activate(_ screen: RivoRemoteScreen) {
        activeScreen = screen
        latestEvent = nil
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
                    on: activeScreen
                ) else {
            return false
        }
        nextEventID &+= 1
        latestEvent = RivoScreenRemoteEvent(
            id: nextEventID,
            screen: activeScreen,
            action: action
        )
        return true
    }
}
