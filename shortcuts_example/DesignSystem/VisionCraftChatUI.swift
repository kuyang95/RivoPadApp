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
