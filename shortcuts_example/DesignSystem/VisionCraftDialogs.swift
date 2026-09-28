import SwiftUI

/// 앱 공통 선택 다이얼로그.
/// 안드로이드 VisionCraft 의 `AlertDialog(shape = 24dp)` + `DialogActionButton`
/// 조합과 같은 구조다. 스크림 → 카드(제목, 선택 항목, 취소) 순서로 쌓인다.
///
/// - 항목은 `VisionCraftDialogOptionRow` 로 넣는다.
/// - 취소 버튼은 카드가 그린다. 항목 안에 취소를 또 넣지 않는다.
/// - 스크림을 탭해도 닫힌다.
struct VisionCraftDialogCard<Content: View>: View {
    let title: String
    var message: String? = nil
    var cancelTitle: String = "취소"
    var maxWidth: CGFloat = 560
    var usesHomeStyle = false
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        message: String? = nil,
        cancelTitle: String = "취소",
        maxWidth: CGFloat = 560,
        usesHomeStyle: Bool = false,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.message = message
        self.cancelTitle = cancelTitle
        self.maxWidth = maxWidth
        self.usesHomeStyle = usesHomeStyle
        self.onDismiss = onDismiss
        self.content = content
    }

    var body: some View {
        ZStack {
            VisionCraftDialogScrim(onTap: onDismiss)

            VStack(alignment: .leading, spacing: 0) {
                Text(AppLocalization.string(title))
                    .font(.title2.bold())
                    .foregroundStyle(VisionCraftUI.primaryText)
                    .accessibilityAddTraits(.isHeader)

                if let message {
                    Text(AppLocalization.string(message))
                        .font(.subheadline)
                        .foregroundStyle(VisionCraftUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }

                VStack(spacing: 10) {
                    content()
                }
                .padding(.top, 16)

                Button(AppLocalization.string(cancelTitle), action: onDismiss)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(VisionCraftAndroidButtonStyle())
                    .padding(.top, 16)
            }
            .padding(20)
            .frame(maxWidth: maxWidth)
            .modifier(VisionCraftDialogSurfaceModifier(usesHomeStyle: usesHomeStyle))
            .padding(24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDismiss)
        .zIndex(100)
    }
}

private struct VisionCraftDialogSurfaceModifier: ViewModifier {
    let usesHomeStyle: Bool

    func body(content: Content) -> some View {
        if usesHomeStyle {
            content.visionCraftHomeDialogSurface()
        } else {
            content
                .visionCraftSurfaceCard(cornerRadius: 28, outlineOpacity: 1)
                .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
        }
    }
}

/// 다이얼로그 뒤 반투명 스크림. 탭하면 닫힌다.
struct VisionCraftDialogScrim: View {
    let onTap: () -> Void

    var body: some View {
        Color.black.opacity(0.52)
            .ignoresSafeArea()
            .onTapGesture(perform: onTap)
            .accessibilityHidden(true)
    }
}

/// 다이얼로그 안의 선택 항목 한 줄.
/// 아이콘 타일 + 제목(+ 설명) + chevron. 항목마다 배경과 테두리를 가져
/// 서로 다른 선택지임이 한눈에 구분된다.
struct VisionCraftDialogOptionRow: View {
    let title: String
    var subtitle: String? = nil
    let systemImage: String
    var isPrimary = false
    var isEnabled = true
    var badge: String? = nil
    var showsIconTile = true
    let action: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        isPrimary: Bool = false,
        isEnabled: Bool = true,
        badge: String? = nil,
        showsIconTile: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isPrimary = isPrimary
        self.isEnabled = isEnabled
        self.badge = badge
        self.showsIconTile = showsIconTile
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if showsIconTile {
                    VisionCraftIconTile(
                        systemImage: systemImage,
                        foreground: iconForeground,
                        background: iconBackground,
                        size: 52,
                        iconSize: 28
                    )
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 28))
                        .foregroundStyle(VisionCraftHomeUI.icon)
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.string(title))
                        .visionCraftAndroidText(18, weight: .semibold, relativeTo: .headline)
                        .foregroundStyle(titleColor)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(AppLocalization.string(subtitle))
                            .visionCraftAndroidText(16)
                            .foregroundStyle(subtitleColor)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                if let badge {
                    Text(AppLocalization.string(badge))
                        .visionCraftAndroidText(16, weight: .bold)
                        .foregroundStyle(VisionCraftUI.background)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(VisionCraftUI.accent, in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            VisionCraftUI.secondaryText.opacity(
                                isEnabled ? 1 : 0.4
                            )
                        )
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(
                rowBackground,
                in: RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(rowStroke, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var iconForeground: Color {
        guard isEnabled else {
            return VisionCraftUI.secondaryText.opacity(0.5)
        }
        return VisionCraftUI.accent
    }

    private var iconBackground: Color {
        guard isEnabled else {
            return VisionCraftUI.surfaceVariant.opacity(0.6)
        }
        return VisionCraftUI.accent.opacity(0.14)
    }

    private var titleColor: Color {
        isEnabled
            ? VisionCraftUI.primaryText
            : VisionCraftUI.secondaryText.opacity(0.55)
    }

    private var subtitleColor: Color {
        VisionCraftUI.secondaryText.opacity(isEnabled ? 1 : 0.5)
    }

    private var rowBackground: Color {
        return VisionCraftUI.surface
    }

    private var rowStroke: Color {
        return isPrimary && isEnabled
            ? VisionCraftUI.accent
            : VisionCraftUI.outline
    }
}
