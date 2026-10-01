import SwiftUI

enum ExcelCellToolAction {
    case editingPanel(ExcelEditingPanel)
    case addRow
    case sheetObjects
    case numberFormat(ExcelNumberFormat, toCurrentColumn: Bool)
    case chooseDropdownValue(String)
    case editDropdown(toCurrentColumn: Bool)
    case removeDropdown(toCurrentColumn: Bool)
    case editConditionalFormatting(toCurrentColumn: Bool)
    case removeConditionalFormatting(toCurrentColumn: Bool)
    case openLink(URL)
    case editAnnotations
    case removeHyperlink
    case removeNote
}

struct ExcelCellToolsDialog: View {
    @ObservedObject var viewModel: ExcelWorkbookViewModel
    let onAction: (ExcelCellToolAction) -> Void
    let onDismiss: () -> Void

    @State private var page: Page = .tools
    @State private var toCurrentColumn = false

    private enum Page: String {
        case tools = "셀 도구"
        case numberFormat = "표시 형식"
        case dropdown = "드롭다운"
        case conditionalFormatting = "조건부 서식"
        case annotations = "링크 및 메모"
    }

    var body: some View {
        VisionCraftDialogCard(
            title: page.rawValue,
            message: AppLocalization.format(
                "선택한 셀 %@",
                viewModel.selectedRange?.reference ?? "—"
            ),
            cancelTitle: "닫기",
            onDismiss: onDismiss
        ) {
            if page != .tools {
                VisionCraftBackButton {
                    page = .tools
                    toCurrentColumn = false
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if page != .tools && page != .annotations {
                Picker("적용 범위", selection: $toCurrentColumn) {
                    Text((viewModel.selectedRange?.cellCount ?? 1) > 1 ? "선택 범위" : "선택한 셀").tag(false)
                    if viewModel.canApplyNumberFormatToCurrentColumn {
                        Text("현재 열 데이터 전체").tag(true)
                    }
                }
                .pickerStyle(.segmented)
            }

            ViewThatFits(in: .vertical) {
                actions.fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    actions
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .accessibilityAction(.escape, onDismiss)
    }

    @ViewBuilder
    private var actions: some View {
        switch page {
        case .tools: tools
        case .numberFormat: numberFormats
        case .dropdown: dropdown
        case .conditionalFormatting: conditionalFormatting
        case .annotations: annotations
        }
    }

    private var tools: some View {
        VStack(spacing: VisionCraftUI.actionRowSpacing) {
            VisionCraftDialogOptionRow(
                title: "범위 선택·복사",
                subtitle: "여러 셀을 선택하고 복사·붙여넣기·채우기를 합니다.",
                systemImage: "square.on.square"
            ) { onAction(.editingPanel(.range)) }

            VisionCraftDialogOptionRow(
                title: "행·열 편집",
                subtitle: "행·열을 삽입·삭제하고 높이와 너비를 조절합니다.",
                systemImage: "tablecells",
                isEnabled: viewModel.canEditSelectedSheet && !viewModel.isLargeWorkbook
            ) { onAction(.editingPanel(.structure)) }

            VisionCraftDialogOptionRow(
                title: "틀 고정",
                subtitle: "스크롤해도 제목 행이나 왼쪽 열을 계속 표시합니다.",
                systemImage: "pin",
                isEnabled: viewModel.selectedSheet != nil
            ) { onAction(.editingPanel(.freezing)) }

            VisionCraftDialogOptionRow(
                title: "셀 병합·해제",
                subtitle: "여러 셀을 하나로 합치거나 병합된 셀을 나눕니다.",
                systemImage: "rectangle.split.3x1",
                isEnabled: viewModel.canEditSelectedSheet && !viewModel.isLargeWorkbook
            ) { onAction(.editingPanel(.merging)) }

            VisionCraftDialogOptionRow(
                title: "글꼴·색·테두리",
                subtitle: "선택한 셀의 글꼴, 색, 정렬과 테두리를 바꿉니다.",
                systemImage: "textformat",
                isEnabled: viewModel.canEditSelectedSheet && !viewModel.isLargeWorkbook
            ) { onAction(.editingPanel(.formatting)) }

            VisionCraftDialogOptionRow(
                title: "정렬·필터·찾기",
                subtitle: "데이터를 정렬하고 원하는 행이나 값을 찾습니다.",
                systemImage: "line.3.horizontal.decrease"
            ) { onAction(.editingPanel(.sorting)) }

            VisionCraftDialogOptionRow(
                title: "표시 형식",
                subtitle: "숫자, 날짜, 백분율 등 값이 보이는 모양을 바꿉니다.",
                systemImage: "123.rectangle",
                isEnabled: viewModel.selectedCell != nil
            ) { page = .numberFormat }

            VisionCraftDialogOptionRow(
                title: "드롭다운",
                subtitle: "셀에 넣을 값을 목록에서 고르거나 목록을 만듭니다.",
                systemImage: "list.bullet.rectangle",
                isEnabled: viewModel.selectedAddress != nil
            ) { page = .dropdown }

            VisionCraftDialogOptionRow(
                title: "조건부 서식",
                subtitle: "조건에 맞는 셀을 자동으로 강조합니다.",
                systemImage: "paintpalette",
                isEnabled: viewModel.selectedAddress != nil
            ) { page = .conditionalFormatting }

            VisionCraftDialogOptionRow(
                title: "링크 및 메모",
                subtitle: "셀에 웹 링크나 메모를 넣고 편집합니다.",
                systemImage: "note.text",
                isEnabled: viewModel.selectedAddress != nil
            ) { page = .annotations }

            VisionCraftDialogOptionRow(
                title: "행 추가",
                subtitle: "현재 영역의 마지막에 새 행을 추가합니다.",
                systemImage: "plus.rectangle.on.rectangle",
                isEnabled: viewModel.canEditSelectedSheet && !viewModel.isLargeWorkbook
            ) { onAction(.addRow) }

            VisionCraftDialogOptionRow(
                title: "이미지·차트 등",
                subtitle: "이미지, 도형, 차트와 피벗 요약표를 추가하고 관리합니다.",
                systemImage: "photo.on.rectangle",
                isEnabled: viewModel.selectedSheet != nil && !viewModel.isLargeWorkbook
            ) { onAction(.sheetObjects) }
        }
    }

    private var numberFormats: some View {
        VStack(spacing: VisionCraftUI.actionRowSpacing) {
            ForEach(ExcelNumberFormat.allCases) { format in
                let isSelected = !toCurrentColumn
                    && viewModel.selectedNumberFormat == format
                VisionCraftDialogOptionRow(
                    title: format.title,
                    subtitle: format.example,
                    systemImage: isSelected ? "checkmark.circle.fill" : "123.rectangle",
                    isPrimary: isSelected
                ) {
                    onAction(.numberFormat(format, toCurrentColumn: toCurrentColumn))
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var dropdown: some View {
        VStack(spacing: VisionCraftUI.actionRowSpacing) {
            if !toCurrentColumn && !viewModel.selectedDropdownValues.isEmpty {
                Text("드롭다운 값")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                ForEach(viewModel.selectedDropdownValues, id: \.self) { value in
                    Button {
                        onAction(.chooseDropdownValue(value))
                    } label: {
                        Text(verbatim: value)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .padding(.horizontal, 14)
                            .background(
                                VisionCraftUI.surfaceVariant.opacity(0.55),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            VisionCraftDialogOptionRow(
                title: toCurrentColumn ? "현재 열 데이터 전체 설정…" : "선택한 셀 드롭다운 설정…",
                systemImage: "slider.horizontal.3"
            ) {
                onAction(.editDropdown(toCurrentColumn: toCurrentColumn))
            }
            if viewModel.selectedDataValidation?.type == "list" {
                removalButton(
                    toCurrentColumn ? "현재 열 드롭다운 제거" : "선택한 셀 드롭다운 제거"
                ) {
                    onAction(.removeDropdown(toCurrentColumn: toCurrentColumn))
                }
            }
        }
    }

    private var conditionalFormatting: some View {
        VStack(spacing: VisionCraftUI.actionRowSpacing) {
            VisionCraftDialogOptionRow(
                title: toCurrentColumn ? "현재 열 데이터 전체 설정…" : "선택한 셀 조건부 서식…",
                systemImage: "paintpalette"
            ) {
                onAction(.editConditionalFormatting(toCurrentColumn: toCurrentColumn))
            }
            if viewModel.selectedConditionalFormattingCount > 0 {
                removalButton(
                    toCurrentColumn ? "현재 열 기본 규칙 제거" : "선택한 셀 기본 규칙 제거"
                ) {
                    onAction(.removeConditionalFormatting(toCurrentColumn: toCurrentColumn))
                }
            }
        }
    }

    private var annotations: some View {
        VStack(spacing: VisionCraftUI.actionRowSpacing) {
            if let url = viewModel.selectedExternalHyperlinkURL {
                VisionCraftDialogOptionRow(title: "링크 열기", systemImage: "safari") {
                    onAction(.openLink(url))
                }
            }
            if let hyperlink = viewModel.selectedHyperlink, !hyperlink.isExternal {
                VStack(alignment: .leading, spacing: 4) {
                    Text("내부 링크").font(.headline)
                    Text(hyperlink.target).font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VisionCraftDialogOptionRow(title: "링크·메모 편집…", systemImage: "square.and.pencil") {
                onAction(.editAnnotations)
            }
            if viewModel.selectedHyperlink != nil {
                removalButton("하이퍼링크 제거", systemImage: "link.badge.minus") {
                    onAction(.removeHyperlink)
                }
            }
            if viewModel.selectedNote != nil {
                removalButton("메모 제거") {
                    onAction(.removeNote)
                }
            }
        }
    }

    private func removalButton(
        _ title: String,
        systemImage: String = "trash",
        action: @escaping () -> Void
    ) -> some View {
        Button(role: .destructive, action: action) {
            Label(AppLocalization.string(title), systemImage: systemImage)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, 14)
        }
        .buttonStyle(.borderless)
    }
}
