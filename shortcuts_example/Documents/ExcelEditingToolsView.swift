import SwiftUI
import UIKit

enum ExcelEditingPanel: String, Identifiable {
    case range = "범위 선택·복사"
    case structure = "행·열 편집"
    case formatting = "글꼴·색·테두리"
    case sorting = "정렬·필터·찾기"
    case merging = "셀 병합·해제"
    case freezing = "틀 고정"
    var id: String { rawValue }
}

struct ExcelEditingToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ExcelWorkbookViewModel
    let panel: ExcelEditingPanel
    @State private var rangeText = ""
    @State private var axis: ExcelEditAxis = .row
    @State private var insertCount = "1"
    @State private var dimension = "24"
    @State private var format = ExcelBasicFormat()
    @State private var fontName = ""
    @State private var fontSize = "11"
    @State private var bold = false
    @State private var italic = false
    @State private var underline = false
    @State private var wrapping = false
    @State private var foreground = Color.black
    @State private var background = Color.white
    @State private var horizontal = "left"
    @State private var vertical = "center"
    @State private var border = "keep"
    @State private var column = 1
    @State private var header = true
    @State private var filterComparison: ExcelFilterComparison = .contains
    @State private var filterText = ""
    @State private var replacement = ""
    @State private var centerMergedCell = false
    @State private var pendingMerge: ExcelCellMergePlan?
    @State private var isConfirmingMerge = false
    @State private var mergeError: String?

    private var range: ExcelCellRange? { ExcelCellRange(rangeText) }
    private var canEdit: Bool { viewModel.canEditSelectedSheet && !viewModel.isLargeWorkbook }

    var body: some View {
        NavigationStack {
            Form {
                Section(LocalizedStringKey(panel == .freezing ? "기준 셀" : "적용 범위")) {
                    TextField(panel == .freezing ? "B3" : "A1:D10", text: $rangeText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityLabel(LocalizedStringKey(panel == .freezing ? "기준 셀" : "셀 범위"))
                    if let range, panel != .freezing { Text(AppLocalization.format("%lld개 셀", range.cellCount)).font(.caption).foregroundStyle(.secondary) }
                }
                switch panel {
                case .range: rangeTools
                case .structure: structureTools
                case .formatting: formattingTools
                case .sorting: sortingTools
                case .merging: mergingTools
                case .freezing: freezingTools
                }
                if !viewModel.status.isEmpty {
                    Section { Text(viewModel.status).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(LocalizedStringKey(panel.rawValue))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }.disabled(viewModel.isSaving)
                }
            }
            .disabled(viewModel.isSaving)
            .overlay { if viewModel.isSaving { ProgressView().padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        }
        .tint(VisionCraftUI.primary)
        .onAppear(perform: loadSelection)
        .onChange(of: rangeText) { _, _ in
            if let range, !(range.start.column ... range.end.column).contains(column) { column = range.start.column }
        }
        .onChange(of: axis) { _, _ in
            dimension = String(axis == .row ? viewModel.selectedSheet?.rowHeights[range?.start.row ?? 1] ?? 24 : viewModel.selectedSheet?.columnWidths[range?.start.column ?? 1] ?? 14)
        }
        .alert("셀을 병합할까요?", isPresented: $isConfirmingMerge) {
            Button("병합", role: .destructive) {
                if let plan = pendingMerge {
                    rangeText = plan.range.reference
                    run(.merge(plan.range, center: centerMergedCell, discardOtherValues: true))
                }
                pendingMerge = nil
            }
            Button("취소", role: .cancel) { pendingMerge = nil }
        } message: {
            if let plan = pendingMerge {
                Text(AppLocalization.format("%@ 범위를 병합합니다. %@ 셀의 값만 남고 다른 %lld개 셀의 값·수식은 지워집니다. 실행 취소로 복원할 수 있습니다.", plan.range.reference, plan.range.start.reference, plan.discardedAddresses.count))
            }
        }
    }

    private var rangeTools: some View {
        Group {
            Section {
                Button("범위 선택") {
                    if viewModel.selectRange(rangeText) {
                        viewModel.navigationRevealAddress = range?.start
                        dismiss()
                    }
                }
                Button("복사") { selectionAction { viewModel.copySelection() } }
                Button("잘라내기") { selectionAction { viewModel.copySelection(cutting: true) } }.disabled(!canEdit)
                Button("붙여넣기") { selectionAction { viewModel.pasteSelection() } }.disabled(!canEdit)
                Button("값 지우기", role: .destructive) { selectionAction { viewModel.clearSelection() } }.disabled(!canEdit)
            } footer: {
                Text("셀을 길게 누른 뒤 끌어서 범위를 선택할 수도 있습니다. 행 번호나 열 이름을 누르면 해당 데이터 행·열을 선택합니다.")
            }
            Section {
                Button("아래로 채우기") { selectionAction { viewModel.fillSelection(across: false) } }
                Button("오른쪽으로 채우기") { selectionAction { viewModel.fillSelection(across: true) } }
            } footer: {
                Text("첫 셀의 값이나 수식을 채웁니다. 첫 두 셀이 숫자이면 두 값의 간격으로 이어서 채웁니다.")
            }
            .disabled(!canEdit || (range?.cellCount ?? 0) < 2)
        }
    }

    private var structureTools: some View {
        Group {
            Section("행·열 선택") {
                Picker("대상", selection: $axis) {
                    ForEach(ExcelEditAxis.allCases) { axis in Text(axis.title).tag(axis) }
                }.pickerStyle(.segmented)
                TextField("추가할 개수", text: $insertCount).keyboardType(.numberPad)
                Button(axis == .row ? "선택 위에 행 삽입" : "선택 왼쪽에 열 삽입") { insert(after: false) }
                Button(axis == .row ? "선택 아래에 행 삽입" : "선택 오른쪽에 열 삽입") { insert(after: true) }
                Button(axis == .row ? "선택한 행 삭제" : "선택한 열 삭제", role: .destructive) {
                    guard let range else { return }
                    let indices = selectedIndices(range)
                    run(.structure(ExcelStructureChange(axis: axis, index: indices.lowerBound, count: indices.count, deleting: true)))
                }
            }.disabled(!canEdit || range == nil)
            Section(axis == .row ? "행 높이" : "열 너비") {
                TextField(axis == .row ? "높이(pt)" : "너비", text: $dimension).keyboardType(.decimalPad)
                Button("크기 적용") {
                    guard let range, let value = Double(dimension) else { return }
                    run(.resize(axis, selectedIndices(range), value))
                }
            }.disabled(!canEdit || range == nil || Double(dimension) == nil)
        }
    }

    private var formattingTools: some View {
        Group {
            Section("글꼴") {
                TextField("글꼴 이름", text: Binding(get: { fontName }, set: { fontName = $0; format.fontName = $0 }))
                TextField("글자 크기", text: Binding(get: { fontSize }, set: { fontSize = $0; format.fontSize = Double($0) })).keyboardType(.decimalPad)
                Toggle("굵게", isOn: Binding(get: { bold }, set: { bold = $0; format.bold = $0 }))
                Toggle("기울임", isOn: Binding(get: { italic }, set: { italic = $0; format.italic = $0 }))
                Toggle("밑줄", isOn: Binding(get: { underline }, set: { underline = $0; format.underline = $0 }))
            }
            Section("색상") {
                ColorPicker("글자색", selection: Binding(get: { foreground }, set: { foreground = $0; format.textColor = argb($0) }), supportsOpacity: false)
                ColorPicker("배경색", selection: Binding(get: { background }, set: { background = $0; format.fillColor = argb($0) }), supportsOpacity: false)
                Button("배경색 없음") { format.fillColor = ""; background = .white }
                Button("기본 글자색") { format.textColor = ""; foreground = .black }
            }
            Section("정렬·줄바꿈") {
                Picker("가로 정렬", selection: Binding(get: { horizontal }, set: { horizontal = $0; format.horizontal = $0 })) {
                    Text("왼쪽").tag("left"); Text("가운데").tag("center"); Text("오른쪽").tag("right")
                }
                Picker("세로 정렬", selection: Binding(get: { vertical }, set: { vertical = $0; format.vertical = $0 })) {
                    Text("위").tag("top"); Text("가운데").tag("center"); Text("아래").tag("bottom")
                }
                Toggle("자동 줄바꿈", isOn: Binding(get: { wrapping }, set: { wrapping = $0; format.wrap = $0 }))
                Picker("테두리", selection: Binding(get: { border }, set: { border = $0; format.borders = $0 == "keep" ? nil : $0 })) {
                    Text("유지").tag("keep"); Text("모든 테두리").tag("all"); Text("바깥 테두리").tag("outside"); Text("테두리 없음").tag("none")
                }
            }
            Section {
                Button("선택 범위에 서식 적용") { if let range { run(.format(range, format)) } }
                    .disabled(!canEdit || range == nil)
            }
        }
    }

    private var mergingTools: some View {
        Group {
            if let mergeError {
                Section { Text(mergeError).foregroundStyle(.red) }
            }
            Section {
                if let range, let sheet = viewModel.selectedSheet {
                    let expanded = range.includingMergedCells(in: sheet)
                    LabeledContent("병합 범위", value: expanded.reference)
                    LabeledContent("남는 셀", value: expanded.start.reference)
                    Text(String((sheet.cells[expanded.start]?.editText ?? AppLocalization.string("빈 셀")).prefix(160)))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Toggle("병합 후 가운데 정렬", isOn: $centerMergedCell)
                Button("셀 병합") { prepareMerge() }
                    .disabled(!canEdit || (range?.cellCount ?? 0) < 2)
            } header: { Text("병합") } footer: {
                Text("왼쪽 위 셀의 값만 남습니다. 다른 셀에 값이 있으면 지우기 전에 확인합니다. 이미 병합된 셀에 걸치면 해당 셀 전체를 포함합니다.")
            }
            Section {
                Button("병합 해제") { if let range { run(.unmerge(range)) } }
                    .disabled(!canEdit || !hasMergedCells)
            } footer: {
                Text("선택 범위와 겹치는 병합을 모두 해제합니다. 값은 왼쪽 위 셀에 남으며, 병합할 때 지운 값은 실행 취소로 복원할 수 있습니다.")
            }
        }
    }

    private var hasMergedCells: Bool {
        guard let range, let sheet = viewModel.selectedSheet else { return false }
        return sheet.mergedRanges.contains(where: range.intersects)
    }

    private var freezingTools: some View {
        Group {
            Section("현재 고정") {
                let panes = viewModel.selectedSheet?.frozenPanes ?? .none
                Text(panes.isEnabled ? AppLocalization.format("위쪽 %lld개 행 · 왼쪽 %lld개 열", panes.rows, panes.columns) : AppLocalization.string("고정 없음"))
                if viewModel.workbook?.protection.lockWindows == true { Text("창 구성이 보호된 문서는 틀 고정을 바꿀 수 없습니다.").foregroundStyle(.secondary) }
            }
            Section {
                Button("첫 행 고정") { run(.freezePanes(.init(rows: 1, columns: 0))) }
                Button("첫 열 고정") { run(.freezePanes(.init(rows: 0, columns: 1))) }
                Button("첫 행과 첫 열 고정") { run(.freezePanes(.init(rows: 1, columns: 1))) }
                Button("선택한 셀 기준 고정") {
                    if let address = range?.start { run(.freezePanes(.init(rows: address.row - 1, columns: address.column - 1))) }
                }.disabled(range?.start == nil || range?.start == ExcelCellAddress(row: 1, column: 1))
                if let address = range?.start {
                    Text(AppLocalization.format("%@ 기준: 위쪽 %lld개 행과 왼쪽 %lld개 열을 고정합니다.", address.reference, address.row - 1, address.column - 1))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("틀 고정 해제") { run(.freezePanes(.none)) }
                    .disabled(viewModel.selectedSheet?.frozenPanes.isEnabled != true)
            } footer: {
                Text("원본 보기에서 스크롤해도 고정 영역이 남습니다. 화면에 다 담기지 않는 고정 영역은 일부만 표시되며, 본문을 스크롤할 공간은 유지됩니다.")
            }
            .disabled(!canEdit || viewModel.workbook?.protection.lockWindows == true)
        }
    }

    private func prepareMerge() {
        guard let range, let sheet = viewModel.selectedSheet else { return }
        mergeError = nil
        do {
            let plan = try ExcelCellMergePlan(range: range, sheet: sheet)
            if plan.discardedAddresses.isEmpty {
                rangeText = plan.range.reference
                run(.merge(plan.range, center: centerMergedCell))
            } else {
                pendingMerge = plan
                isConfirmingMerge = true
            }
        } catch { mergeError = error.localizedDescription }
    }

    private var sortingTools: some View {
        Group {
            Section("정렬") {
                if let range, range.end.column - range.start.column < 200 {
                    Picker("기준 열", selection: $column) {
                        ForEach(range.start.column ... range.end.column, id: \.self) { column in
                            Text(ExcelCellAddress.columnName(column) + " · " + (viewModel.selectedSheet?.cells[ExcelCellAddress(row: range.start.row, column: column)]?.displayValue ?? ""))
                                .tag(column)
                        }
                    }
                }
                Toggle("첫 행은 머리글", isOn: $header)
                Button("오름차순 정렬") { if let range { run(.sort(range, column: column, ascending: true, header: header)) } }
                Button("내림차순 정렬") { if let range { run(.sort(range, column: column, ascending: false, header: header)) } }
            }.disabled(!canEdit || range == nil)
            Section {
                Picker("조건", selection: $filterComparison) { ForEach(ExcelFilterComparison.allCases) { Text($0.title).tag($0) } }
                TextField("필터 값", text: $filterText)
                Button("조건에 맞는 행만 보기") {
                    if let range { run(.filter(range, column: column, comparison: filterComparison, query: filterText)) }
                }.disabled(filterText.isEmpty)
                Button("필터 해제") { run(.clearFilter) }
            } header: { Text("필터") } footer: { Text("위에서 선택한 기준 열에 적용하며 첫 행은 머리글로 유지합니다.") }
                .disabled(!canEdit || range == nil)
            Section("찾기·바꾸기") {
                TextField("찾을 내용", text: $viewModel.findText)
                Text(AppLocalization.format("검색 결과 %lld개", viewModel.findResults.count)).foregroundStyle(.secondary)
                Button("다음 결과") { viewModel.findNext() }.disabled(viewModel.findText.isEmpty)
                TextField("바꿀 내용", text: $replacement)
                Button("현재 셀 바꾸기") { viewModel.replaceFound(all: false, replacement: replacement) }.disabled(!canEdit || viewModel.findText.isEmpty)
                Button("시트에서 모두 바꾸기") { viewModel.replaceFound(all: true, replacement: replacement) }.disabled(!canEdit || viewModel.findText.isEmpty)
            }
        }
    }

    private func loadSelection() {
        rangeText = (panel == .sorting ? viewModel.editingRange : viewModel.selectedRange)?.reference ?? "A1"
        column = viewModel.selectedAddress?.column ?? 1
        dimension = String(viewModel.selectedSheet?.rowHeights[viewModel.selectedAddress?.row ?? 1] ?? 24)
        let style = viewModel.workbook?.style(at: viewModel.selectedCell?.styleIndex) ?? .plain
        fontName = style.fontName ?? "Arial"; fontSize = String(style.fontSize ?? 11)
        bold = style.isBold; italic = style.isItalic; underline = style.isUnderlined; wrapping = style.wrapText
        horizontal = style.horizontalAlignment ?? "left"; vertical = style.verticalAlignment ?? "center"
        foreground = color(style.fontARGB) ?? .black; background = color(style.fillARGB) ?? .white
    }
    private func selectedIndices(_ range: ExcelCellRange) -> ClosedRange<Int> {
        axis == .row ? range.start.row ... range.end.row : range.start.column ... range.end.column
    }
    private func insert(after: Bool) {
        guard let range, let count = Int(insertCount), count > 0 else { return }
        let indices = selectedIndices(range)
        run(.structure(ExcelStructureChange(axis: axis, index: after ? indices.upperBound + 1 : indices.lowerBound, count: count, deleting: false)))
    }
    private func selectionAction(_ action: () -> Void) {
        guard viewModel.selectRange(rangeText) else { return }
        action()
    }
    private func run(_ edit: ExcelAdvancedEdit) {
        Task { await viewModel.performAdvancedEdit(edit) }
    }
    private func argb(_ color: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "FF%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
    private func color(_ argb: String?) -> Color? {
        guard let argb, let value = UInt32(argb.suffix(6), radix: 16) else { return nil }
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
