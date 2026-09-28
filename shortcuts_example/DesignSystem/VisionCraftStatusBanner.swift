import SwiftUI

/// Home remote status, matching Android's compact soft banner.
struct VisionCraftStatusBanner: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    var iconAccent: Color = VisionCraftHomeUI.connected
    var isBusy = false
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(iconAccent)
                    .frame(width: 44, height: 44)
                    .background(
                        iconAccent.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .symbolEffect(.variableColor.iterative, isActive: isBusy && !reduceMotion)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.string(eyebrow))
                        .visionCraftAndroidText(18, weight: .semibold, relativeTo: .headline)
                        .foregroundStyle(VisionCraftHomeUI.text)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(accent)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text("\(title) · \(subtitle)")
                            .visionCraftAndroidText(16)
                            .foregroundStyle(VisionCraftHomeUI.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(VisionCraftHomeUI.icon)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .visionCraftHomeSurface()
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(VisionCraftHomePressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.remote")
    }
}

/// Compact remote status shown at the trailing edge of the home title row.
struct VisionCraftHomeRemoteStatusIcon: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    var isBusy = false
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(accent)
                    .frame(width: 52, height: 52)
                    .symbolEffect(
                        .variableColor.iterative,
                        isActive: isBusy && !reduceMotion
                    )

                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                    .padding(7)
                    .accessibilityHidden(true)
            }
            .contentShape(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(AppLocalization.string(eyebrow)). \(title). \(subtitle)"
        )
        .accessibilityHint(
            AppLocalization.string("리모컨 연결 화면을 엽니다.")
        )
        .accessibilityIdentifier("home.remote")
    }
}
