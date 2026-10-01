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
    /// Android `vc_error` / `VCColors.Error`. 오류·중지 상태에만 쓴다.
    static let error = adaptiveColor(light: 0xCF6679, dark: 0xCF6679)
    /// Android `vc_chat_text_disabled`: 입력칸 안내 글자(입력칸 위 4.6:1).
    static let inputPlaceholder = adaptiveColor(light: 0x616E7F, dark: 0x8A97A8)
    /// Android `vc_soft_overlay`: 안내 띠. 글자색 88%, 글자는 배경색.
    static let overlay = adaptiveColor(light: 0x283546, dark: 0xF0F4FA).opacity(0.88)
    /// Android `vc_link_success` / `vc_link_warning`: 비전링크 연결 상태 전용.
    static let linkSuccess = adaptiveColor(light: 0x28765A, dark: 0x99D8BA)
    static let linkWarning = adaptiveColor(light: 0x976026, dark: 0xE7BE80)

    /// 접근성 계약: 누를 수 있는 것은 48pt 이상.
    static let minTouchTarget: CGFloat = 48
    static let minTextSize: CGFloat = 12

    static let contentWidth: CGFloat = 760
    static let horizontalPadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 28
    static let actionRowSpacing: CGFloat = 16
    static let sectionHeaderBottomSpacing: CGFloat = 14
    /// Android VcHomeSectionHeader 아래 14 + VcHomeCategoryDialog 추가 6.
    static let cardDialogHeaderBottomSpacing = sectionHeaderBottomSpacing + 6

    /// 테마를 따르지 않는 고정색(카메라 미리보기 위 버튼).
    static func fixedColor(_ hex: UInt32) -> Color {
        Color(uiColor: UIColor(hex: hex))
    }

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

/// 카메라 미리보기 위 버튼 고정색. Android `camera/CameraControls.kt` 상단과 같다.
/// 미리보기를 가리지 않도록 띠를 깔지 않고 버튼 자체가 대비를 만든다.
enum VisionCraftCameraUI {
    static let surface = VisionCraftUI.fixedColor(0x171717)
    static let pressed = VisionCraftUI.fixedColor(0x3A3A3A)
    static let outline = Color.white
    static let text = Color.white
    static let secondaryText = VisionCraftUI.fixedColor(0xD6DCE6)
    static let on = VisionCraftUI.fixedColor(0xFFA05C)
    static let onText = VisionCraftUI.fixedColor(0x2B1200)
    static let mode = VisionCraftUI.fixedColor(0x283546)
    static let modeOutline = VisionCraftUI.fixedColor(0xF0F4FA)
    static let shutterRing = VisionCraftUI.fixedColor(0x171717)
    static let shutterPressed = VisionCraftUI.fixedColor(0xD0D0D0)
}

extension UIColor {
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

                VStack(alignment: .leading, spacing: 0) {
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
    /// 현재 값 표시(예: 카메라 모드 "현재"). 있으면 테두리가 강조색이 되고 화살표 자리에 뱃지가 들어간다.
    var badge: String? = nil
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

/// Android `VcIconTileSize`: 목록 카드용 Large, 메뉴 줄용 Medium.
enum VisionCraftIconTileSize {
    case large, medium, custom(box: CGFloat, corner: CGFloat, icon: CGFloat)

    var box: CGFloat {
        switch self {
        case .large: 52
        case .medium: 44
        case .custom(let box, _, _): box
        }
    }

    var corner: CGFloat {
        switch self {
        case .large: 16
        case .medium: 14
        case .custom(_, let corner, _): corner
        }
    }

    var icon: CGFloat {
        switch self {
        case .large: 30
        case .medium: 22
        case .custom(_, _, let icon): icon
        }
    }
}

/// Android `VcIconTile`: 강조색 14% 바탕의 둥근 사각 안에 아이콘.
/// `isEnabled == false`면 바탕 글자색 6%, 아이콘 글자색 38%.
struct VisionCraftIconTile: View {
    let systemImage: String
    let foreground: Color
    let background: Color
    var size: CGFloat = 40
    var iconSize: CGFloat = 22
    var cornerRadius: CGFloat? = nil
    var isEnabled = true

    init(
        systemImage: String,
        foreground: Color,
        background: Color,
        size: CGFloat = 40,
        iconSize: CGFloat = 22,
        cornerRadius: CGFloat? = nil,
        isEnabled: Bool = true
    ) {
        self.systemImage = systemImage
        self.foreground = foreground
        self.background = background
        self.size = size
        self.iconSize = iconSize
        self.cornerRadius = cornerRadius
        self.isEnabled = isEnabled
    }

    /// 강조색 하나로 Android 규격 크기를 그린다.
    init(
        systemImage: String,
        tint: Color,
        tileSize: VisionCraftIconTileSize = .large,
        isEnabled: Bool = true
    ) {
        self.systemImage = systemImage
        self.foreground = tint
        self.background = tint.opacity(0.14)
        self.size = tileSize.box
        self.iconSize = tileSize.icon
        self.cornerRadius = tileSize.corner
        self.isEnabled = isEnabled
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(
                isEnabled ? foreground : VisionCraftUI.primaryText.opacity(0.38)
            )
            .frame(width: size, height: size)
            .background(
                isEnabled ? background : VisionCraftUI.primaryText.opacity(0.06),
                in: RoundedRectangle(
                    cornerRadius: cornerRadius ?? resolvedCorner,
                    style: .continuous
                )
            )
            .accessibilityHidden(true)
    }

    private var resolvedCorner: CGFloat {
        switch size {
        case 52: 16
        case 44: 14
        default: size * 0.28
        }
    }
}

/// Android `VcIconButton`(`VcHomeTitleIconButton`): 52pt 정사각 터치 영역, 모서리 16,
/// 면·테두리 없음, 아이콘 26pt. 제목 줄 오른쪽 아이콘 버튼에 쓴다.
struct VisionCraftIconButton: View {
    let systemImage: String
    let label: String
    var tint: Color = VisionCraftUI.icon
    var statusDot: Color? = nil
    let action: () -> Void

    init(
        systemImage: String,
        label: String,
        tint: Color = VisionCraftUI.icon,
        statusDot: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.label = label
        self.tint = tint
        self.statusDot = statusDot
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .overlay(alignment: .topTrailing) {
                    if let statusDot {
                        Circle()
                            .fill(statusDot)
                            .frame(width: 8, height: 8)
                            .padding(.top, 7)
                            .padding(.trailing, 7)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(VisionCraftHomePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.string(label))
        .accessibilityAddTraits(.isButton)
    }
}

/// Android `VcScreenTitleRow`: 24pt Bold 제목(heading). `onBack`이 있으면 왼쪽에
/// 48pt 뒤로 가기, `actions`에 오른쪽 아이콘 버튼(`VisionCraftIconButton`).
struct VisionCraftScreenTitleRow<Actions: View>: View {
    let title: String
    var onBack: (() -> Void)? = nil
    @ViewBuilder let actions: () -> Actions

    init(
        title: String,
        onBack: (() -> Void)? = nil,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.onBack = onBack
        self.actions = actions
    }

    var body: some View {
        HStack(spacing: 0) {
            if let onBack {
                VisionCraftBackButton(action: onBack)
                    .padding(.trailing, 4)
            }
            Text(AppLocalization.string(title))
                .visionCraftAndroidText(24, weight: .bold, relativeTo: .title)
                .foregroundStyle(VisionCraftUI.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            actions()
        }
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
    var tint: Color?
    let action: () -> Void

    init(
        style: Style = .standard,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.style = style
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left.circle")
            .resizable()
            .scaledToFit()
            .frame(width: 30, height: 30)
            .foregroundStyle(
                tint ?? (style == .overlay
                    ? Color.white
                    : VisionCraftUI.primary)
            )
            .shadow(
                color: .black.opacity(
                    style == .overlay ? 0.55 : 0
                ),
                radius: 4,
                y: 1
            )
            .frame(
                width: VisionCraftUI.minTouchTarget,
                height: VisionCraftUI.minTouchTarget
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: VisionCraftUI.minTouchTarget, height: VisionCraftUI.minTouchTarget)
        .fixedSize()
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

    /// Android `VcPanel`: 면 색, 모서리 16, 1pt 보조글자색 70% 테두리, 그림자 없음.
    func visionCraftSurfaceCard(
        cornerRadius: CGFloat = 16,
        outlineOpacity: Double = 0.7
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

    /// Android `VcScreen`: 좌우 24pt, 위 12pt, 아래 24pt 화면 여백.
    func visionCraftScreenPadding(bottom: CGFloat = 24) -> some View {
        padding(.horizontal, VisionCraftUI.horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, bottom)
    }

    /// Android `VcPanel(error = true)`: 1.5pt 강조색 테두리(오류 안내).
    func visionCraftErrorPanel(cornerRadius: CGFloat = 16) -> some View {
        background(
            VisionCraftUI.surface,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(VisionCraftUI.accent, lineWidth: 1.5)
        }
    }
}
