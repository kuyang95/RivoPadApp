import SwiftUI
import UIKit

enum VisionCraftUI {
    static let primary = adaptiveColor(
        light: 0x5A7FE6,
        dark: 0x7C9EFF
    )
    static let background = adaptiveColor(
        light: 0xF5F5F5,
        dark: 0x0F0F0F
    )
    static let surface = adaptiveColor(
        light: 0xFFFFFF,
        dark: 0x1A1A1A
    )
    static let surfaceVariant = adaptiveColor(
        light: 0xE8E8E8,
        dark: 0x252525
    )
    static let outline = adaptiveColor(
        light: 0xDADADA,
        dark: 0x303030
    )
    static let primaryText = adaptiveColor(
        light: 0x1A1A1A,
        dark: 0xE8E8E8
    )
    static let secondaryText = adaptiveColor(
        light: 0x616161,
        dark: 0x9E9E9E
    )
    static let success = Color(red: 0.01, green: 0.73, blue: 0.64)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.30)

    static let contentWidth: CGFloat = 760
    static let horizontalPadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 28

    private static func adaptiveColor(
        light: UInt32,
        dark: UInt32
    ) -> Color {
        Color(
            uiColor: UIColor { traits in
                UIColor(
                    hex: traits.userInterfaceStyle == .dark
                        ? dark
                        : light
                )
            }
        )
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct VisionCraftSectionHeader: View {
    let title: String

    var body: some View {
        Text(AppLocalization.string(title))
            .font(.title2.weight(.semibold))
            .foregroundStyle(VisionCraftUI.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .padding(.bottom, 12)
    }
}

struct VisionCraftPrimaryActionPanel: View {
    let icon: String
    let title: String
    let description: String
    let primaryTitle: String
    let secondaryTitle: String
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                VisionCraftIconTile(
                    systemImage: icon,
                    foreground: .white,
                    background: VisionCraftUI.primary,
                    size: 52,
                    iconSize: 27
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppLocalization.string(title))
                        .font(.title2.bold())
                        .foregroundStyle(VisionCraftUI.primaryText)
                    Text(AppLocalization.string(description))
                        .font(.body)
                        .foregroundStyle(VisionCraftUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    actionButtons
                }
                VStack(spacing: 10) {
                    actionButtons
                }
            }
        }
        .padding(18)
        .background(
            VisionCraftUI.primary.opacity(0.12),
            in: RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(VisionCraftUI.primary.opacity(0.28), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button(action: onPrimary) {
            Text(AppLocalization.string(primaryTitle))
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .tint(VisionCraftUI.primary)

        Button(action: onSecondary) {
            Text(AppLocalization.string(secondaryTitle))
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .tint(VisionCraftUI.primary)
    }
}

struct VisionCraftActionItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let description: String
    var accent: Color = VisionCraftUI.primary
    let action: () -> Void
}

struct VisionCraftActionList: View {
    let items: [VisionCraftActionItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button(action: item.action) {
                    HStack(spacing: 14) {
                        VisionCraftIconTile(
                            systemImage: item.icon,
                            foreground: item.accent,
                            background: item.accent.opacity(0.14),
                            size: 48,
                            iconSize: 24
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppLocalization.string(item.title))
                                .font(.headline)
                                .foregroundStyle(VisionCraftUI.primaryText)
                            Text(AppLocalization.string(item.description))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(VisionCraftUI.secondaryText)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(VisionCraftUI.secondaryText)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)

                if index < items.count - 1 {
                    Divider()
                        .overlay(VisionCraftUI.outline.opacity(0.7))
                        .padding(.leading, 78)
                }
            }
        }
        .background(
            VisionCraftUI.surface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(VisionCraftUI.outline.opacity(0.8), lineWidth: 1)
        }
    }
}

struct VisionCraftIconTile: View {
    let systemImage: String
    let foreground: Color
    let background: Color
    var size: CGFloat = 40
    var iconSize: CGFloat = 22

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(
                background,
                in: RoundedRectangle(
                    cornerRadius: size * 0.28,
                    style: .continuous
                )
            )
            .accessibilityHidden(true)
    }
}

private struct VisionCraftNavigationScreenModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(VisionCraftUI.primary)
            .background(VisionCraftUI.background.ignoresSafeArea())
            .toolbarBackground(VisionCraftUI.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

private struct VisionCraftListScreenModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(VisionCraftUI.background.ignoresSafeArea())
            .tint(VisionCraftUI.primary)
            .toolbarBackground(VisionCraftUI.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    func visionCraftNavigationScreen() -> some View {
        modifier(VisionCraftNavigationScreenModifier())
    }

    func visionCraftListScreen() -> some View {
        modifier(VisionCraftListScreenModifier())
    }
}
