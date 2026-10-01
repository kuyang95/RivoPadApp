import SwiftUI

/// Chat-specific shapes and colors shared with Android's a_chat.xml drawables.
enum VisionCraftChatUI {
    static let accent = VisionCraftUI.accent

    static func bubbleShape(isUser: Bool) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: isUser ? 22 : 6,
            bottomLeadingRadius: 22,
            bottomTrailingRadius: isUser ? 6 : 22,
            topTrailingRadius: 22,
            style: .continuous
        )
    }

    static let composerShape = UnevenRoundedRectangle(
        topLeadingRadius: 24,
        bottomLeadingRadius: 0,
        bottomTrailingRadius: 0,
        topTrailingRadius: 24,
        style: .continuous
    )
}

extension View {
    func visionCraftChatBubble(isUser: Bool) -> some View {
        background {
            if isUser {
                VisionCraftChatUI.bubbleShape(isUser: true)
                    .fill(VisionCraftChatUI.accent)
            } else {
                VisionCraftChatUI.bubbleShape(isUser: false)
                    .fill(VisionCraftUI.surface)
                VisionCraftChatUI.bubbleShape(isUser: false)
                    .strokeBorder(VisionCraftUI.outline, lineWidth: 1.5)
            }
        }
    }

    func visionCraftChatInputSurface() -> some View {
        padding(.horizontal, 22)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(VisionCraftUI.surfaceVariant)
            }
    }

    func visionCraftChatComposerSurface() -> some View {
        background {
            VisionCraftChatUI.composerShape
                .fill(VisionCraftUI.surface)
        }
    }
}

struct VisionCraftChatTypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        Capsule()
            .fill(VisionCraftUI.surfaceVariant)
            .frame(width: 120, height: 4)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(VisionCraftUI.accent)
                    .frame(width: 30, height: 4)
                    .offset(x: isAnimating && !reduceMotion ? 90 : 0)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(),
                        value: isAnimating
                    )
            }
            .onAppear { isAnimating = true }
            .accessibilityLabel(AppLocalization.string("답변 생성 중…"))
    }
}

/// Android `item_sent_message.xml` / `item_received_message.xml`
/// `textViewSender`: 13sp bold, secondary text, letter spacing 0.03.
struct VisionCraftChatSenderLabel: View {
    let name: String

    var body: some View {
        Text(AppLocalization.string(name))
            .visionCraftAndroidText(13, weight: .bold, relativeTo: .footnote)
            .tracking(0.4)
            .foregroundStyle(VisionCraftUI.secondaryText)
            .accessibilityHidden(true)
    }
}

/// Android `buttonMic` (`bg_mic_button`): 52pt accent circle that never
/// changes colour; only the glyph switches between mic and stop.
struct VisionCraftChatMicButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(VisionCraftUI.onAccent)
                .frame(width: 52, height: 52)
                .background {
                    Circle().fill(VisionCraftChatUI.accent)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.string(label))
    }
}
