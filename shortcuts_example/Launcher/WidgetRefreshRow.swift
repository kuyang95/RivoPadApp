import SwiftUI

struct WidgetRefreshRow: View {
    let updatedAt: Date?
    let ink: Color
    let busy: Bool
    let enabled: Bool
    let refreshLabel: LocalizedStringKey
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            sectionDivider
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    updatedTime.fixedSize()
                    Spacer(minLength: 12)
                    refreshButton.fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    updatedTime
                    refreshButton
                }
            }
            sectionDivider
        }
    }

    @ViewBuilder private var updatedTime: some View {
        if let updatedAt {
            Text("\(updatedAt.formatted(date: .omitted, time: .shortened)) 갱신")
                .visionCraftAndroidText(16).foregroundStyle(ink.opacity(0.8))
        }
    }
    private var refreshButton: some View {
        Button(action: onRefresh) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise").font(.system(size: 22)).accessibilityHidden(true)
                Text("새로고침").visionCraftAndroidText(18)
            }.padding(.horizontal, 8).padding(.vertical, 14).frame(minHeight: 56)
        }
        .buttonStyle(.plain).foregroundStyle(ink)
        .accessibilityLabel(refreshLabel)
        .accessibilityValue(busy ? Text("갱신 중") : Text(""))
        .disabled(!enabled || busy)
        .opacity(!enabled || busy ? 0.45 : 1)
    }
    private var sectionDivider: some View {
        Rectangle().fill(ink.opacity(0.48)).frame(height: 1).accessibilityHidden(true)
    }
}
