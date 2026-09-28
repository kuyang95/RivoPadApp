import SwiftUI

struct VisionCraftSettingsGroup<Content: View>: View {
    let title: String?
    let content: Content

    init(
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title,
               !title.isEmpty {
                Text(AppLocalization.string(title))
                    .visionCraftAndroidText(14, weight: .medium)
                    .foregroundStyle(
                        VisionCraftHomeUI.secondaryText
                    )
                    .accessibilityAddTraits(.isHeader)
            }

            content
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    VisionCraftHomeUI.surface,
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(VisionCraftHomeUI.secondaryText.opacity(0.7), lineWidth: 1)
                }
        }
    }
}

struct VisionCraftSettingsGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let content: Content

    init(
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
    }

    var body: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: 8
        ) {
            content
        }
    }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize || horizontalSizeClass == .compact {
            return [GridItem(.flexible())]
        }
        return [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]
    }
}

struct VisionCraftSettingSwitchTile: View {
    let label: String
    let hint: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalization.string(label))
                    .visionCraftAndroidText(18)
                    .foregroundStyle(VisionCraftHomeUI.text)
                Text(AppLocalization.string(hint))
                    .visionCraftAndroidText(14)
                    .foregroundStyle(VisionCraftHomeUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)
                Capsule()
                    .fill(isOn ? VisionCraftHomeUI.switchOn : VisionCraftHomeUI.switchOff)
                    .frame(width: 52, height: 32)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: isOn ? 24 : 16, height: isOn ? 24 : 16)
                            .padding(isOn ? 4 : 8)
                    }
                    .accessibilityHidden(true)
            }
            .multilineTextAlignment(.leading)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(VisionCraftHomePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.string(label))
        .accessibilityValue(AppLocalization.string(isOn ? "켬" : "끔"))
        .accessibilityHint(AppLocalization.string(hint))
    }
}

struct VisionCraftSettingValueTile: View {
    let label: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppLocalization.string(label))
                    .visionCraftAndroidText(18)
                    .foregroundStyle(
                        VisionCraftHomeUI.text
                    )
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Text(value)
                    .visionCraftAndroidText(16, weight: .semibold)
                    .foregroundStyle(VisionCraftHomeUI.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(alignment: .trailing) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(VisionCraftHomeUI.icon)
                            .padding(.trailing, 14)
                            .accessibilityHidden(true)
                    }
                    .visionCraftHomeSurface(cornerRadius: 14)
            }
            .padding(12)
            .frame(
                maxWidth: .infinity,
                minHeight: 112,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(VisionCraftHomePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AppLocalization.string(label)
        )
        .accessibilityValue(value)
        .accessibilityHint(
            AppLocalization.string(
                "두 번 탭하여 값을 변경합니다."
            )
        )
        .accessibilityAddTraits(.isButton)
    }
}

struct VisionCraftColorSettingTile: View {
    let label: String
    let theme: LocalDocumentColorTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppLocalization.string(label))
                    .visionCraftAndroidText(18)
                    .foregroundStyle(
                        VisionCraftHomeUI.text
                    )
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    Color(rgbHex: theme.backgroundHex)
                    Color(rgbHex: theme.foregroundHex)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                    .stroke(
                        VisionCraftUI.outline,
                        lineWidth: 1
                    )
                }
            }
            .padding(12)
            .frame(
                maxWidth: .infinity,
                minHeight: 112,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(VisionCraftHomePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AppLocalization.string(label)
        )
        .accessibilityValue(theme.displayName)
        .accessibilityHint(
            AppLocalization.string(
                "두 번 탭하여 값을 변경합니다."
            )
        )
        .accessibilityAddTraits(.isButton)
    }
}

struct VisionCraftSelectionOption: Identifiable {
    let id: String
    let title: String
}

struct VisionCraftSelectionDialog: View {
    let title: String
    let options: [VisionCraftSelectionOption]
    let selectedID: String
    let onSelect: (VisionCraftSelectionOption) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(AppLocalization.string(title))
                    .visionCraftAndroidText(22, weight: .semibold, relativeTo: .title2)
                    .foregroundStyle(
                        VisionCraftHomeUI.text
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 14)
                    .accessibilityAddTraits(.isHeader)

                ViewThatFits(in: .vertical) {
                    selectionOptions
                    ScrollView {
                        selectionOptions
                    }
                    .frame(maxHeight: 420)
                }

                HStack {
                    Spacer()
                    Button(AppLocalization.string("취소"), action: onDismiss)
                        .buttonStyle(VisionCraftAndroidButtonStyle())
                }
                .padding(24)
            }
            .frame(maxWidth: 440)
            .visionCraftHomeDialogSurface()
            .padding(24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDismiss)
        .zIndex(100)
    }

    private var selectionOptions: some View {
        VStack(spacing: 0) {
            ForEach(options) { option in
                Button {
                    onSelect(option)
                } label: {
                    HStack(spacing: 14) {
                        Text(option.title)
                            .visionCraftAndroidText(18, weight: option.id == selectedID ? .semibold : .regular)
                            .foregroundStyle(option.id == selectedID ? VisionCraftUI.accent : VisionCraftHomeUI.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if option.id == selectedID {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(VisionCraftUI.accent)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .background(
                        VisionCraftUI.accent.opacity(option.id == selectedID ? 0.15 : 0),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(VisionCraftHomePressStyle())
                .accessibilityValue(AppLocalization.string(
                    option.id == selectedID ? "선택됨" : "선택 안 됨"
                ))
            }
        }
        .padding(.horizontal, 24)
    }

}

private extension Color {
    init(rgbHex: Int) {
        self.init(
            red: Double((rgbHex >> 16) & 0xFF) / 255,
            green: Double((rgbHex >> 8) & 0xFF) / 255,
            blue: Double(rgbHex & 0xFF) / 255
        )
    }
}
