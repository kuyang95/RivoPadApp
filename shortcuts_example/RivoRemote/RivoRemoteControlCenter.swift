import Combine
import SwiftUI
import UIKit

nonisolated enum RivoQuickDestination:
    String,
    Sendable
{
    case aiChat
    case reader
    case magnifier
    case liveTextReader
    case scanner
    case remoteSettings
}

nonisolated enum RivoRemoteCommand: Equatable, Sendable {
    case navigate(RivoQuickDestination)
    case startVoiceAction
    case home
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
    let destination: RivoQuickDestination
    let title: String
    let systemImage: String

    var id: RivoQuickDestination {
        destination
    }
}

@MainActor
final class RivoRemoteControlCenter: ObservableObject {
    @Published private(set) var isMenuPresented = false
    @Published private(set) var selectedIndex = 0
    @Published private(set) var feedback = ""

    let items: [RivoQuickMenuItem] = [
        RivoQuickMenuItem(
            destination: .aiChat,
            title: "AI 채팅",
            systemImage: "bubble.left.and.bubble.right"
        ),
        RivoQuickMenuItem(
            destination: .reader,
            title: "독서",
            systemImage: "book"
        ),
        RivoQuickMenuItem(
            destination: .magnifier,
            title: "카메라 돋보기",
            systemImage: "plus.magnifyingglass"
        ),
        RivoQuickMenuItem(
            destination: .liveTextReader,
            title: "실시간 텍스트 읽기",
            systemImage: "text.viewfinder"
        ),
        RivoQuickMenuItem(
            destination: .scanner,
            title: "문서 스캔",
            systemImage: "doc.viewfinder"
        ),
        RivoQuickMenuItem(
            destination: .remoteSettings,
            title: "리모컨 연결",
            systemImage: "dot.radiowaves.left.and.right"
        )
    ]

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
                feedback = "지원하지 않는 시퀀스 \(payload)"
                return RivoRemoteDecision(
                    command: nil,
                    consumed: true
                )
            }
            feedback = "음성 명령 듣기"
            isMenuPresented = false
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
                isMenuPresented = true
                feedback = selectedItemAnnouncement
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
                    "Android의 다른 앱 화면 확대 이동은 iPadOS에서 지원되지 않습니다. 앱의 카메라 돋보기를 사용해 주세요."
                announceFeedback()
                return RivoRemoteDecision(
                    command: nil,
                    consumed: true
                )
            }
            if button == .r3 {
                feedback = "음성 읽기 정지"
                return RivoRemoteDecision(
                    command: .stopSpeech,
                    consumed: true
                )
            }
            if button == .l1 {
                isMenuPresented.toggle()
                feedback = isMenuPresented
                    ? selectedItemAnnouncement
                    : "빠른 메뉴 닫힘"
                return RivoRemoteDecision(
                    command: nil,
                    consumed: true
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
                feedback = "홈으로 이동"
                command = .home
            case .star:
                isMenuPresented = false
                feedback = "빠른 메뉴 닫힘"
                command = nil
            default:
                feedback = "\(button.title) 버튼"
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

    func dismissMenu() {
        isMenuPresented = false
        feedback = "빠른 메뉴 닫힘"
    }

    private var selectedItemAnnouncement: String {
        guard items.indices.contains(selectedIndex) else {
            return "빠른 메뉴"
        }
        return "\(items[selectedIndex].title), "
            + "\(selectedIndex + 1)/\(items.count)"
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
            return "카메라 조작 안내. 빠른 메뉴에서 카메라 돋보기를 열면 R1 카메라 모드를 사용할 수 있습니다."
        case .l2:
            return "화면 색상 안내. 카메라 돋보기나 로컬 문서에서 L2 화면 색상 모드를 사용할 수 있습니다."
        case .l3:
            return "문서 조작 안내. TXT 또는 PDF 로컬 문서에서 L3 문서 탐색 모드를 사용할 수 있습니다."
        case .l4:
            return "화면 위치 점프 안내. Android의 다른 앱 화면 확대 이동은 iPadOS 공개 API로 지원되지 않습니다. 카메라 돋보기를 사용해 주세요."
        case .r4:
            return "화면 연속 이동 안내. Android의 다른 앱 화면 확대 스크롤은 iPadOS 공개 API로 지원되지 않습니다. 카메라 돋보기를 사용해 주세요."
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
        feedback = "\(item.title) 열기"
        return .navigate(item.destination)
    }
}

struct RivoQuickMenuOverlay: View {
    @ObservedObject var controlCenter: RivoRemoteControlCenter
    let onCommand: (RivoRemoteCommand) -> Void

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

                ForEach(
                    Array(controlCenter.items.enumerated()),
                    id: \.element.id
                ) { index, item in
                    Button {
                        if let command =
                            controlCenter.activateItem(
                                at: index
                            ) {
                            onCommand(command)
                        }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: item.systemImage)
                                .frame(width: 34)
                            Text(item.title)
                                .font(.title3.bold())
                            Spacer()
                            if index
                                == controlCenter.selectedIndex {
                                Image(systemName: "circle.fill")
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 62)
                        .frame(maxWidth: .infinity)
                        .background(
                            index == controlCenter.selectedIndex
                                ? Color.orange
                                : Color.white.opacity(0.12)
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
                        index == controlCenter.selectedIndex
                            ? "선택됨"
                            : ""
                    )
                }

                Text(
                    "L1 메뉴 · 2/4 이전 · 6/8 다음 · "
                        + "5 선택 · 0 홈 · 별표 닫기"
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
