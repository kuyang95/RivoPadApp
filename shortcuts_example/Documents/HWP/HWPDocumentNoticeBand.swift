import SwiftUI

/// A band across the document under the header (Android `NoticeBand`): a notice,
/// its detail, and a capsule action — the read-only HWP's `편집용 HWPX 사본 만들기`
/// and the empty document's `글 쓰기`.
struct HWPDocumentNoticeBand: View {
    let text: LocalizedStringKey
    let detail: LocalizedStringKey?
    let action: LocalizedStringKey
    let identifier: String
    let onAction: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                message
                Spacer(minLength: 0)
                button
            }
            VStack(alignment: .leading, spacing: 8) {
                message
                button
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VisionCraftUI.surfaceVariant)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VisionCraftUI.primaryText)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(VisionCraftUI.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var button: some View {
        Button(action: onAction) {
            Text(action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VisionCraftUI.background)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(minHeight: 34)
                .background(VisionCraftUI.primary, in: Capsule())
                .frame(minHeight: VisionCraftUI.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
