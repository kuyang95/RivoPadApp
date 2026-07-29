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
    case home
    case stopSpeech
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
        switch input {
        case .sequence(let payload):
            guard payload == "a/" else {
                feedback = "지원하지 않는 시퀀스 \(payload)"
                return nil
            }
            feedback = "음성 명령: AI 채팅 열기"
            isMenuPresented = false
            return .navigate(.aiChat)

        case .button(
            let button,
            let action,
            _
        ):
            guard action == .pressed else {
                return nil
            }

            if button == .r3 {
                feedback = "음성 읽기 정지"
                return .stopSpeech
            }
            if button == .l1 {
                isMenuPresented.toggle()
                feedback = isMenuPresented
                    ? selectedItemAnnouncement
                    : "빠른 메뉴 닫힘"
                return nil
            }
            guard isMenuPresented else {
                return nil
            }

            switch button {
            case .one:
                selectedIndex = 0
                announceSelection()
            case .two, .four:
                moveSelection(by: -1)
            case .six, .eight:
                moveSelection(by: 1)
            case .seven:
                selectedIndex = max(items.count - 1, 0)
                announceSelection()
            case .five:
                return activateSelection()
            case .zero:
                isMenuPresented = false
                feedback = "홈으로 이동"
                return .home
            case .star:
                isMenuPresented = false
                feedback = "빠른 메뉴 닫힘"
            default:
                feedback = "\(button.title) 버튼"
            }
            return nil
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
        UIAccessibility.post(
            notification: .announcement,
            argument: feedback
        )
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
