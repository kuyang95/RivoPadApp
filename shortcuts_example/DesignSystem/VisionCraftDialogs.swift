import SwiftUI
import UIKit

/// Android `VcCardDialog`(`VcHomeCategoryDialog`): 기능 고르기 다이얼로그.
/// 모서리 28, 배경색 면 + 1.5pt 테두리, 최대 너비 560, 안쪽 24.
/// 머리는 `VisionCraftHomeSectionHeader`(밑줄), 몸통은 `VisionCraftDialogOptionRow`
/// (VcActionRow) 목록, 맨 아래 VcButton 닫기. 내용 높이로 가운데에 놓고
/// 화면보다 길 때만 스크롤한다. 값 하나를 고르는 거라면
/// `VisionCraftSelectionDialog`(VcOptionDialog)를 쓴다.
struct VisionCraftDialogCard<Content: View>: View {
    let title: String
    var message: String? = nil
    var cancelTitle: String = "닫기"
    var maxWidth: CGFloat = 560
    var tone: VisionCraftHomeUI.SectionTone = .neutral
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        message: String? = nil,
        cancelTitle: String = "닫기",
        maxWidth: CGFloat = 560,
        tone: VisionCraftHomeUI.SectionTone = .neutral,
        usesHomeStyle: Bool = false,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.message = message
        self.cancelTitle = cancelTitle
        self.maxWidth = maxWidth
        self.tone = tone
        self.onDismiss = onDismiss
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VisionCraftDialogScrim(onTap: onDismiss)

                ViewThatFits(in: .vertical) {
                    dialogContents
                        .fixedSize(horizontal: false, vertical: true)
                    ScrollView {
                        dialogContents
                    }
                }
                .frame(width: min(maxWidth, max(0, geometry.size.width - 40)))
                .background(
                    VisionCraftHomeUI.background,
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(VisionCraftHomeUI.outline, lineWidth: 1.5)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDismiss)
        .onAppear {
            UIAccessibility.post(
                notification: .screenChanged,
                argument: AppLocalization.string(title)
            )
        }
        .zIndex(100)
    }

    private var dialogContents: some View {
        VStack(alignment: .leading, spacing: 0) {
            VisionCraftHomeSectionHeader(
                title: title,
                tone: tone,
                bottomSpacing: VisionCraftUI.cardDialogHeaderBottomSpacing
            )

            if let message {
                Text(AppLocalization.string(message))
                    .visionCraftAndroidText(16)
                    .foregroundStyle(VisionCraftUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
            }

            VStack(spacing: VisionCraftUI.actionRowSpacing) {
                content()
            }

            HStack {
                Spacer(minLength: 0)
                VisionCraftDialogCloseButton(title: cancelTitle, action: onDismiss)
            }
            .padding(.top, 24)
        }
        .padding(24)
    }
}

/// 기능·값 선택 다이얼로그가 공통으로 쓰는 오른쪽 아래 닫기 버튼.
struct VisionCraftDialogCloseButton: View {
    var title: String = "닫기"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(AppLocalization.string(title))
                .visionCraftAndroidText(16, weight: .semibold)
                .foregroundStyle(VisionCraftHomeUI.onPrimary)
                .padding(.horizontal, 20)
                .frame(minWidth: 104, minHeight: 52)
                .background(
                    VisionCraftHomeUI.text,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(VisionCraftHomePressStyle())
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

/// Android `VcActionRow`: 다이얼로그 안의 선택 항목 한 줄.
/// soft 면 + 모서리 22, 최소 88pt, 안쪽 20/18, 요소 간격 16.
/// 왼쪽 VcIconTile Large(52/16/30), 가운데 제목(18 SemiBold)과 설명(16 보조글자), 오른쪽 화살표.
/// `badge`가 있으면 테두리가 강조색이 되고 화살표 자리에 뱃지가 들어간다.
struct VisionCraftDialogOptionRow: View {
    let title: String
    var subtitle: String? = nil
    let systemImage: String
    var isPrimary = false
    var isEnabled = true
    var badge: String? = nil
    var showsIconTile = true
    var accent: Color? = nil
    let action: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        isPrimary: Bool = false,
        isEnabled: Bool = true,
        badge: String? = nil,
        showsIconTile: Bool = true,
        accent: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isPrimary = isPrimary
        self.isEnabled = isEnabled
        self.badge = badge
        self.showsIconTile = showsIconTile
        self.accent = accent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                if showsIconTile {
                    VisionCraftIconTile(
                        systemImage: systemImage,
                        tint: accent ?? VisionCraftUI.accent,
                        tileSize: .large,
                        isEnabled: isEnabled
                    )
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 28))
                        .foregroundStyle(
                            isEnabled
                                ? VisionCraftHomeUI.icon
                                : VisionCraftUI.primaryText.opacity(0.38)
                        )
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.string(title))
                        .visionCraftAndroidText(18, weight: .semibold, relativeTo: .headline)
                        .foregroundStyle(titleColor)
                    if let subtitle {
                        Text(AppLocalization.string(subtitle))
                            .visionCraftAndroidText(16)
                            .foregroundStyle(subtitleColor)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if let badge {
                    VisionCraftBadge(text: badge)
                } else {
                    VisionCraftChevron()
                        .opacity(isEnabled ? 1 : 0.4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .visionCraftHomeSurface(outlineColor: outlineColor)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(VisionCraftHomePressStyle())
        .disabled(!isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var outlineColor: Color? {
        (badge != nil || isPrimary) && isEnabled ? VisionCraftUI.accent : nil
    }

    private var titleColor: Color {
        isEnabled
            ? VisionCraftUI.primaryText
            : VisionCraftUI.secondaryText.opacity(0.55)
    }

    private var subtitleColor: Color {
        VisionCraftUI.secondaryText.opacity(isEnabled ? 1 : 0.5)
    }

    /// Android: "제목. 설명"(뱃지가 있으면 "제목, 뱃지. 설명") 한 덩어리.
    private var accessibilityLabel: String {
        var label = AppLocalization.string(title)
        if let badge {
            label += ", \(AppLocalization.string(badge))"
        }
        if let subtitle {
            label += ". \(AppLocalization.string(subtitle))"
        }
        return label
    }
}
