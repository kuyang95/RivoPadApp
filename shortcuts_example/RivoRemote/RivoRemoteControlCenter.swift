import Combine
import SwiftUI
import UIKit

nonisolated enum RivoQuickDestination:
    String,
    Sendable
{
    case aiChat
    case reader
    case translation
    case magnifier
    case liveTextReader
    case imageDescription
    case scanner
    case remoteSettings
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
    let command: RivoRemoteCommand
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

    var items: [RivoQuickMenuItem] {
        if activeScreen == .publicationReader {
            return publicationReaderItems
        }
        return globalItems
    }

    private var globalItems: [RivoQuickMenuItem] {
        [
            RivoQuickMenuItem(
                id: RivoQuickDestination.aiChat.rawValue,
                title:
                    AppLocalization.string(
                        "AI 채팅"
                    ),
                systemImage:
                    "bubble.left.and.bubble.right",
                command: .navigate(.aiChat)
            ),
            RivoQuickMenuItem(
                id: RivoQuickDestination.reader.rawValue,
                title:
                    AppLocalization.string(
                        "독서"
                    ),
                systemImage: "book",
                command: .navigate(.reader)
            ),
            RivoQuickMenuItem(
                id:
                    RivoQuickDestination
                    .magnifier.rawValue,
                title:
                    AppLocalization.string(
                        "카메라 돋보기"
                    ),
                systemImage:
                    "plus.magnifyingglass",
                command: .navigate(.magnifier)
            ),
            RivoQuickMenuItem(
                id:
                    RivoQuickDestination
                    .liveTextReader.rawValue,
                title:
                    AppLocalization.string(
                        "실시간 텍스트 읽기"
                    ),
                systemImage: "text.viewfinder",
                command:
                    .navigate(.liveTextReader)
            ),
            RivoQuickMenuItem(
                id: RivoQuickDestination.scanner.rawValue,
                title:
                    AppLocalization.string(
                        "문서 스캔"
                    ),
                systemImage: "doc.viewfinder",
                command: .navigate(.scanner)
            ),
            RivoQuickMenuItem(
                id:
                    RivoQuickDestination
                    .remoteSettings.rawValue,
                title:
                    AppLocalization.string(
                        "리모컨 연결"
                    ),
                systemImage:
                    "dot.radiowaves.left.and.right",
                command:
                    .navigate(.remoteSettings)
            )
        ]
    }

    private var publicationReaderItems:
        [RivoQuickMenuItem]
    {
        [
            RivoQuickMenuItem(
                id: "reader.back",
                title:
                    AppLocalization.string(
                        "독서 닫기"
                    ),
                systemImage: "chevron.backward",
                command: .back
            ),
            publicationReaderItem(
                id: "reader.playPause",
                title: "재생 또는 일시정지",
                systemImage: "playpause",
                action: .togglePlayback
            ),
            publicationReaderItem(
                id: "reader.previous",
                title: "이전 위치",
                systemImage: "backward.end",
                action: .previous
            ),
            publicationReaderItem(
                id: "reader.next",
                title: "다음 위치",
                systemImage: "forward.end",
                action: .next
            ),
            publicationReaderItem(
                id: "reader.previousUnit",
                title: "이전 탐색 단위",
                systemImage: "minus.circle",
                action: .previousNavigationUnit
            ),
            publicationReaderItem(
                id: "reader.nextUnit",
                title: "다음 탐색 단위",
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
                title: "보기 설정",
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
            title:
                AppLocalization.string(
                    title
                ),
            systemImage: systemImage,
            command: .screen(
                .publicationReader,
                .publicationReader(action)
            )
        )
    }

    func updateActiveScreen(
        _ screen: RivoRemoteScreen?
    ) {
        guard activeScreen != screen else {
            return
        }
        activeScreen = screen
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
            case .two, .four:
                moveSelection(by: -1)
                command = nil
            case .six, .eight:
                moveSelection(by: 1)
                command = nil
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
                isMenuPresented = false
                feedback = AppLocalization.string(
                    "빠른 메뉴 닫힘"
                )
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
        return AppLocalization.format(
            "%@, %lld/%lld",
            items[selectedIndex].title,
            selectedIndex + 1,
            items.count
        )
    }

    private func moveSelection(by delta: Int) {
        guard !items.isEmpty else {
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
            return nil
        }
        let item = items[selectedIndex]
        isMenuPresented = false
        isCommandModeActive = false
        feedback = AppLocalization.format(
            "%@ 실행",
            item.title
        )
        return item.command
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
        HStack {
            Spacer(minLength: 48)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Rivo 빠른 메뉴")
                        .font(.title.bold())
                    Spacer()
                    Button("닫기", systemImage: "xmark") {
                        controlCenter.dismissMenu()
                    }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                }

                if settings
                    .rivoQuickMenuExpanded {
                    ScrollView {
                        LazyVStack(spacing: 14) {
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
                    .frame(maxHeight: 560)
                } else {
                    HStack(spacing: 8) {
                        ForEach(
                            compactItems,
                            id: \.offset
                        ) { index, item in
                            compactMenuItem(
                                item,
                                at: index
                            )
                        }
                    }
                    .frame(height: 96)
                }

                Text(
                    AppLocalization.string(
                        "L1 메뉴 · 2/4 이전 · 6/8 다음 · 5 선택 · 0 홈 · 별표 닫기"
                    )
                )
                .font(.footnote)
                .foregroundStyle(
                    foregroundColor.opacity(0.75)
                )
            }
            .foregroundStyle(foregroundColor)
            .padding(24)
            .frame(width: 420)
            .background(
                backgroundColor.opacity(0.97)
            )
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
                .frame(width: 34)
                Text(item.title)
                    .font(.title3.bold())
                Spacer()
                if isSelected {
                    Image(
                        systemName:
                            "circle.fill"
                    )
                    .font(.caption)
                }
            }
            .foregroundStyle(
                isSelected
                    ? backgroundColor
                    : foregroundColor
            )
            .padding(.horizontal, 18)
            .frame(minHeight: 62)
            .frame(maxWidth: .infinity)
            .background(
                isSelected
                    ? foregroundColor
                    : foregroundColor
                        .opacity(0.12)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
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
            VStack(spacing: 8) {
                Image(
                    systemName:
                        item.systemImage
                )
                .font(
                    isSelected
                        ? .title2
                        : .headline
                )
                Text(item.title)
                    .font(
                        isSelected
                            ? .headline.bold()
                            : .subheadline
                    )
                    .multilineTextAlignment(
                        .center
                    )
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(
                foregroundColor
            )
            .opacity(
                isSelected ? 1 : 0.42
            )
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .background(
                isSelected
                    ? foregroundColor
                        .opacity(0.12)
                    : Color.clear
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )
            .scaleEffect(
                isSelected ? 1 : 0.9
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
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
