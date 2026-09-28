import SwiftUI

enum ExcelWorkbookViewMode: String, CaseIterable, Identifiable {
    case cellGrid
    case accessibleRows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibleRows:
            return AppLocalization.string("간편")
        case .cellGrid:
            return AppLocalization.string("원본")
        }
    }
}

struct ExcelWorkbookBottomBar: View {
    let sheetNames: [String]
    let selectedSheetIndex: Int
    @Binding var viewMode: ExcelWorkbookViewMode
    let onSelectSheet: (Int) -> Void
    var onManageSheets: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var pickerWidth = 184.0

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedControls
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        sheetTabs
                        Divider()
                            .frame(height: 24)
                        viewModePicker
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.trailing, 12)
                    }
                    stackedControls
                }
            }
        }
        .padding(.vertical, 4)
        .background(VisionCraftUI.surface)
    }

    private var stackedControls: some View {
        VStack(alignment: .trailing, spacing: 4) {
            sheetTabs
            viewModePicker
                .padding(.horizontal, 12)
        }
    }

    private var sheetTabs: some View {
        HStack(spacing: 4) {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sheetNames.indices, id: \.self) { index in
                        Button {
                            onSelectSheet(index)
                        } label: {
                            Text(sheetNames[index])
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    index == selectedSheetIndex
                                        ? VisionCraftUI.primary
                                        : VisionCraftUI.surfaceVariant,
                                    in: Capsule()
                                )
                                .foregroundStyle(
                                    index == selectedSheetIndex
                                        ? Color.white
                                        : VisionCraftUI.primaryText
                                )
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            AppLocalization.format("%@ 시트", sheetNames[index])
                        )
                        .accessibilityAddTraits(
                            index == selectedSheetIndex ? .isSelected : []
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, 12)
            }
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                proxy.scrollTo(selectedSheetIndex, anchor: .center)
            }
            .onChange(of: selectedSheetIndex) { _, index in
                proxy.scrollTo(index, anchor: .center)
            }
        }
        .frame(minWidth: 80)
            if let onManageSheets {
                Button(action: onManageSheets) {
                    Text("시트 관리")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    VisionCraftUI.primary.opacity(0.5),
                                    lineWidth: 1
                                )
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .foregroundStyle(VisionCraftUI.primary)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.trailing, 8)
            }
        }
    }

    private var viewModePicker: some View {
        Picker("보기 방식", selection: $viewMode) {
            ForEach(ExcelWorkbookViewMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(idealWidth: pickerWidth, maxWidth: pickerWidth)
        .frame(minHeight: 44)
        .accessibilityHint(
            "간편 표는 한 행씩 읽고, 원본 셀은 엑셀 격자를 셀 단위로 표시합니다."
        )
    }
}

#Preview("Sheet and view controls") {
    ExcelWorkbookBottomBar(
        sheetNames: ["매출 현황", "월별 집계", "상품 목록"],
        selectedSheetIndex: 0,
        viewMode: .constant(.cellGrid),
        onSelectSheet: { _ in }
    )
    .frame(width: 700)
}
