import SwiftUI
import UIKit

enum VisionCraftUI {
    // Android VisionCraft soft UI tokens. Ink is used for navigation and
    // confirmation; the orange accent marks an action that performs work.
    static let primary = adaptiveColor(light: 0x283546, dark: 0xF0F4FA)
    static let accent = adaptiveColor(light: 0xC0521B, dark: 0xFFA05C)
    static let onAccent = adaptiveColor(light: 0xFFFFFF, dark: 0x000000)
    static let background = adaptiveColor(light: 0xFFFFFF, dark: 0x000000)
    static let surface = adaptiveColor(light: 0xFAFAFA, dark: 0x171717)
    static let surfaceVariant = adaptiveColor(light: 0xF0F2F5, dark: 0x2B2B2B)
    static let outline = adaptiveColor(light: 0x536176, dark: 0xBBC6D7)
    static let primaryText = primary
    static let secondaryText = outline
    static let icon = adaptiveColor(light: 0x526580, dark: 0xC9D5E7)
    static let linkBlue = adaptiveColor(light: 0x356AA8, dark: 0x9EC5FF)
    static let success = adaptiveColor(light: 0x247548, dark: 0x83D4A1)
    static let warning = adaptiveColor(light: 0x8B6517, dark: 0xE8C978)

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

private struct VisionCraftRouteBackButtonModifier:
    ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @State private var childHandlesBackNavigation = false
    @State private var childIsCameraScreen = false

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) {
                        if !childHandlesBackNavigation {
                            VisionCraftBackButton(
                                style: backButtonStyle
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        if !childHandlesBackNavigation {
                            VisionCraftBackButton(
                                style: backButtonStyle
                            ) {
                                dismiss()
                            }
                        }
                    }
                }
            }
            .onPreferenceChange(
                VisionCraftHandlesBackNavigationPreferenceKey.self
            ) { handlesBackNavigation in
                childHandlesBackNavigation = handlesBackNavigation
            }
            .onPreferenceChange(
                VisionCraftCameraScreenPreferenceKey.self
            ) { isCameraScreen in
                childIsCameraScreen = isCameraScreen
            }
            .toolbarBackground(
                VisionCraftUI.background,
                for: .navigationBar
            )
            .toolbarBackground(
                childIsCameraScreen ? .hidden : .visible,
                for: .navigationBar
            )
            .toolbarColorScheme(
                childIsCameraScreen ? .dark : nil,
                for: .navigationBar
            )
    }

    private var backButtonStyle: VisionCraftBackButton.Style {
        childIsCameraScreen ? .overlay : .standard
    }
}

private struct VisionCraftHandlesBackNavigationPreferenceKey:
    PreferenceKey {
    static var defaultValue = false

    static func reduce(
        value: inout Bool,
        nextValue: () -> Bool
    ) {
        value = value || nextValue()
    }
}

/// 카메라 화면(문서 스캔, 돋보기, 실시간 읽기, 이미지 설명)이 설정한다.
/// 라우트 툴바 배경을 투명하게 만들고 뒤로가기 버튼을 카메라 위에 띄운다.
private struct VisionCraftCameraScreenPreferenceKey:
    PreferenceKey {
    static var defaultValue = false

    static func reduce(
        value: inout Bool,
        nextValue: () -> Bool
    ) {
        value = value || nextValue()
    }
}

struct VisionCraftBackButton: View {
    enum Style {
        /// 밝은 화면 배경 위. Primary 색 chevron.
        case standard
        /// 카메라 프리뷰 위. 흰색 chevron + 그림자, 배경 없음.
        case overlay
    }

    var style: Style = .standard
    let action: () -> Void

    init(
        style: Style = .standard,
        action: @escaping () -> Void
    ) {
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left.circle")
            .font(.system(size: 30, weight: .regular))
            .foregroundStyle(
                style == .overlay
                    ? Color.white
                    : VisionCraftUI.primary
            )
            .shadow(
                color: .black.opacity(
                    style == .overlay ? 0.55 : 0
                ),
                radius: 4,
                y: 1
            )
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            AppLocalization.string("뒤로가기")
        )
    }
}

private struct VisionCraftSurfaceCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let outlineOpacity: Double

    func body(content: Content) -> some View {
        content
            .background(
                VisionCraftUI.surface,
                in: RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .stroke(
                    VisionCraftUI.outline.opacity(outlineOpacity),
                    lineWidth: 1
                )
            }
    }
}

private struct VisionCraftInputSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                VisionCraftUI.surfaceVariant.opacity(0.58),
                in: RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(VisionCraftUI.outline.opacity(0.85), lineWidth: 1)
            }
    }
}

extension View {
    func visionCraftNavigationScreen() -> some View {
        modifier(VisionCraftNavigationScreenModifier())
    }

    func visionCraftListScreen() -> some View {
        modifier(VisionCraftListScreenModifier())
    }

    func visionCraftRouteBackButton() -> some View {
        modifier(VisionCraftRouteBackButtonModifier())
    }

    func visionCraftHandlesBackNavigation() -> some View {
        preference(
            key: VisionCraftHandlesBackNavigationPreferenceKey.self,
            value: true
        )
    }

    /// 카메라 프리뷰가 화면 전체를 채우는 라우트에 적용한다.
    /// 라우트 툴바 배경이 사라지고 뒤로가기 버튼만 카메라 위에 남는다.
    func visionCraftCameraScreen() -> some View {
        preference(
            key: VisionCraftCameraScreenPreferenceKey.self,
            value: true
        )
    }

    func visionCraftSurfaceCard(
        cornerRadius: CGFloat = 16,
        outlineOpacity: Double = 0.8
    ) -> some View {
        modifier(
            VisionCraftSurfaceCardModifier(
                cornerRadius: cornerRadius,
                outlineOpacity: outlineOpacity
            )
        )
    }

    func visionCraftInputSurface() -> some View {
        modifier(VisionCraftInputSurfaceModifier())
    }
}
