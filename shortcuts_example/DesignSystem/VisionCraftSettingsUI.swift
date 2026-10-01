import SwiftUI
import UIKit

/// Android `VcPanel` + `VcHomeSettingsGroup`: 면 색, 모서리 16, 1pt 보조글자색 70% 테두리,
/// 그림자 없음, 안쪽 20/12. 제목은 14pt Medium 보조글자색 + heading. 그룹 안에는 카드를 넣지 않는다.
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
                .visionCraftSurfaceCard(cornerRadius: 16)
        }
    }
}

/// Android `ResponsiveSettingsGrid`: 넓은 화면·보통 글자 크기에서는 두 열, 아니면 한 열.
/// 홀수 개일 때 마지막 한 칸은 전폭을 쓴다.
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
        VisionCraftSettingsGridLayout(columns: columns, spacing: 8) {
            content
        }
    }

    private var columns: Int {
        if dynamicTypeSize.isAccessibilitySize || horizontalSizeClass == .compact {
            return 1
        }
        return 2
    }
}

/// 두 열 격자. 마지막 줄에 항목이 하나만 남으면 전폭으로 늘린다(Android `ResponsiveSettingsGrid`).
struct VisionCraftSettingsGridLayout: Layout {
    var columns: Int
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 0
        let rows = rowLayouts(width: width, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for row in rowLayouts(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for (index, cellWidth) in zip(row.indices, row.widths) {
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: cellWidth, height: row.height)
                )
                x += cellWidth + spacing
            }
            y += row.height + spacing
        }
    }

    private struct RowLayout {
        let indices: [Int]
        let widths: [CGFloat]
        let height: CGFloat
    }

    private func rowLayouts(width: CGFloat, subviews: Subviews) -> [RowLayout] {
        let columns = max(1, columns)
        let count = subviews.count
        var rows: [RowLayout] = []
        var start = 0
        while start < count {
            let end = min(count, start + columns)
            let indices = Array(start..<end)
            let cellWidth: CGFloat
            if indices.count == 1 {
                cellWidth = width
            } else {
                cellWidth = (width - spacing * CGFloat(indices.count - 1)) / CGFloat(indices.count)
            }
            let widths = Array(repeating: cellWidth, count: indices.count)
            let height = indices.map { index in
                subviews[index]
                    .sizeThatFits(ProposedViewSize(width: cellWidth, height: nil))
                    .height
            }.max() ?? 0
            rows.append(RowLayout(indices: indices, widths: widths, height: height))
            start = end
        }
        return rows
    }
}

/// Android `VcSwitchRow`(`SettingSwitchRow`): 최소 112pt, 안쪽 12, 배경 없음.
/// 스크린리더는 스위치 역할 + 켬/끔 상태로 읽는다. 스위치 색은 `VcSwitch`.
struct VisionCraftSettingSwitchTile: View {
    let label: String
    let hint: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.string(label))
                        .visionCraftAndroidText(18)
                        .foregroundStyle(VisionCraftHomeUI.text)
                    Text(AppLocalization.string(hint))
                        .visionCraftAndroidText(14)
                        .foregroundStyle(VisionCraftHomeUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

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
        .accessibilityRemoveTraits(.isButton)
        .accessibilityAddTraits(.isToggle)
    }
}

/// Android `VcValueRow` + `VcValueButton`: 항목 이름 아래에 값 버튼(VcButton, 전폭,
/// 오른쪽 끝 아래 화살표, 글자 좌우 36). 스크린리더는 "항목, 값" + "값 바꾸기".
struct VisionCraftSettingValueTile: View {
    let label: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text(AppLocalization.string(label))
                    .visionCraftAndroidText(18)
                    .foregroundStyle(
                        VisionCraftHomeUI.text
                    )
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 10)

                Text(value)
                    .visionCraftAndroidText(16, weight: .semibold)
                    .foregroundStyle(VisionCraftHomeUI.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(alignment: .trailing) {
                        VisionCraftChevron(down: true)
                            .padding(.trailing, 14)
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
                "값 바꾸기"
            )
        )
        .accessibilityAddTraits(.isButton)
    }
}

/// Android `VcHomeColorSwatch`: 높이 48, 모서리 12, 1pt 테두리(#DADADA/#303030),
/// 왼쪽 반은 바탕색, 오른쪽 반은 글자색.
struct VisionCraftColorSettingTile: View {
    let label: String
    let theme: LocalDocumentColorTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text(AppLocalization.string(label))
                    .visionCraftAndroidText(18)
                    .foregroundStyle(
                        VisionCraftHomeUI.text
                    )
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 10)

                VisionCraftColorSwatch(theme: theme)
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
                "값 바꾸기"
            )
        )
        .accessibilityAddTraits(.isButton)
    }
}

struct VisionCraftColorSwatch: View {
    let theme: LocalDocumentColorTheme

    var body: some View {
        HStack(spacing: 0) {
            Color(visionCraftHex: theme.backgroundHex)
            Color(visionCraftHex: theme.foregroundHex)
        }
        .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
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
                VisionCraftHomeUI.swatchOutline,
                lineWidth: 1
            )
        }
        .accessibilityHidden(true)
    }
}

/// Android `VcDialogOption`: 값 고르기 다이얼로그의 한 줄.
/// `supportingText` 아래 작은 글, `fontName` 글꼴 미리보기, `swatch` 바탕·글자 색 견본.
struct VisionCraftSelectionOption: Identifiable {
    let id: String
    let title: String
    var supportingText: String? = nil
    var fontName: String? = nil
    var swatch: VisionCraftSelectionSwatch? = nil
    /// 보이는 글자 대신 읽어 줄 이름(색 조합의 "가 나 다 라" 미리보기 등).
    var accessibilityLabel: String? = nil

    init(
        id: String,
        title: String,
        supportingText: String? = nil,
        fontName: String? = nil,
        swatch: VisionCraftSelectionSwatch? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.id = id
        self.title = title
        self.supportingText = supportingText
        self.fontName = fontName
        self.swatch = swatch
        self.accessibilityLabel = accessibilityLabel
    }
}

struct VisionCraftSelectionSwatch {
    let background: Color
    let foreground: Color

    init(background: Color, foreground: Color) {
        self.background = background
        self.foreground = foreground
    }

    init(theme: LocalDocumentColorTheme) {
        background = Color(visionCraftHex: theme.backgroundHex)
        foreground = Color(visionCraftHex: theme.foregroundHex)
    }
}

/// Android `VcDialogNotice`: 목록 위 안내·오류 글.
struct VisionCraftSelectionNotice: Identifiable {
    let id = UUID()
    let text: String
    var isError = false

    init(text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }
}

/// Android `VcOptionDialog`(`VcOptionListDialog`): 값 고르기 다이얼로그.
/// 모서리 24, 제목 22 SemiBold(스크린리더는 화면 이름으로만 읽음). 줄은 꽉 찬 너비, 모서리 12,
/// 안쪽 16, 18pt. 현재 값인 줄만 강조색 15% 바탕 + 강조색 글자 + SemiBold, `markSelected`면 오른쪽 ●.
/// 줄을 누르면 바로 적용하고 닫힌다. 내용 높이로 가운데에 놓고 화면보다 길 때만 스크롤한다.
/// 닫기 버튼 하나(잉크).
struct VisionCraftSelectionDialog: View {
    let title: String
    let options: [VisionCraftSelectionOption]
    let selectedID: String
    let onSelect: (VisionCraftSelectionOption) -> Void
    let onDismiss: () -> Void
    var notices: [VisionCraftSelectionNotice] = []
    var markSelected = false
    var rowSpacing: CGFloat = 0
    var dismissTitle: String = "닫기"

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
                .frame(width: min(440, max(0, geometry.size.width - 48)))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .visionCraftHomeDialogSurface(cornerRadius: 24)
                .padding(24)
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
            Text(AppLocalization.string(title))
                .visionCraftAndroidText(22, weight: .semibold, relativeTo: .title2)
                .foregroundStyle(VisionCraftHomeUI.text)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
                .accessibilityHidden(true)

            selectionOptions

            HStack {
                Spacer()
                VisionCraftDialogCloseButton(title: dismissTitle, action: onDismiss)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
    }

    private var selectionOptions: some View {
        VStack(spacing: rowSpacing) {
            ForEach(notices) { notice in
                Text(notice.text)
                    .visionCraftAndroidText(16)
                    .foregroundStyle(
                        notice.isError ? VisionCraftUI.error : VisionCraftHomeUI.secondaryText
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            ForEach(options) { option in
                selectionRow(option)
            }
        }
        .padding(.horizontal, 24)
    }

    private func selectionRow(_ option: VisionCraftSelectionOption) -> some View {
        let selected = option.id == selectedID
        let textColor: Color = option.swatch?.foreground
            ?? (selected ? VisionCraftUI.accent : VisionCraftHomeUI.text)
        let background: Color = option.swatch?.background
            ?? VisionCraftUI.accent.opacity(selected ? 0.15 : 0)
        return Button {
            onSelect(option)
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(option.title)
                        .font(
                            VisionCraftHomeUI.font(
                                size: UIFontMetrics.default.scaledValue(for: 18),
                                weight: selected ? .semibold : .regular,
                                appFontName: option.fontName
                            )
                        )
                        .foregroundStyle(textColor)
                    if let supportingText = option.supportingText {
                        Text(supportingText)
                            .font(
                                VisionCraftHomeUI.font(
                                    size: UIFontMetrics.default.scaledValue(for: 16),
                                    weight: .regular,
                                    appFontName: option.fontName
                                )
                            )
                            .foregroundStyle(
                                option.swatch?.foreground ?? VisionCraftHomeUI.secondaryText
                            )
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if markSelected, selected {
                    Text("\u{25CF}")
                        .visionCraftAndroidText(18, weight: .medium)
                        .foregroundStyle(textColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(
                background,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(VisionCraftHomePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: option))
        .accessibilityValue(AppLocalization.string(selected ? "선택됨" : ""))
        .accessibilityAddTraits(.isButton)
    }

    private func accessibilityLabel(for option: VisionCraftSelectionOption) -> String {
        if let label = option.accessibilityLabel {
            return label
        }
        if let supportingText = option.supportingText {
            return "\(option.title), \(supportingText)"
        }
        return option.title
    }
}

extension Color {
    init(visionCraftHex rgbHex: Int) {
        self.init(
            red: Double((rgbHex >> 16) & 0xFF) / 255,
            green: Double((rgbHex >> 8) & 0xFF) / 255,
            blue: Double(rgbHex & 0xFF) / 255
        )
    }
}
