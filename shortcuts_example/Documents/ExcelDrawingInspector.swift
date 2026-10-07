import RivoDocumentEngine
import SwiftUI
import PhotosUI

struct ExcelDrawingInspector: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ExcelWorkbookViewModel
    let selection: ExcelDrawingSelection
    @State private var name = ""
    @State private var alternativeText = ""
    @State private var chartKind: ExcelChartKind = .column
    @State private var source = ""
    @State private var start = ""
    @State private var end = ""
    @State private var replacement: PhotosPickerItem?
    @State private var message: String?
    @State private var isLoadingImage = false

    private var sheet: ExcelWorksheet? { viewModel.selectedSheet?.partPath == selection.sheetPath ? viewModel.selectedSheet : nil }
    private var image: ExcelSheetImage? { sheet?.drawingObjects.images.first { $0.id == selection.id } }
    private var chart: ExcelSheetChart? { sheet?.drawingObjects.charts.first { $0.id == selection.id } }
    private var anchor: ExcelDrawingAnchor? { image?.anchor ?? chart?.anchor }
    private var canEdit: Bool { sheet != nil && viewModel.canEditSelectedSheet && !viewModel.isLargeWorkbook && !viewModel.isSaving && !isLoadingImage }
    private var canEditChart: Bool { chart?.kind.isEditable == true && chart?.sourceRange != nil && chart?.sheetName == sheet?.name }
    private var normalizedAnchor: ExcelDrawingAnchor? {
        guard let anchor, let sheet else { return nil }
        return ExcelDrawingGrid(columns: [], rows: [], columnWidths: sheet.columnWidths, rowHeights: sheet.rowHeights).normalized(anchor)
    }

    var body: some View {
        NavigationStack {
            Form {
                if anchor != nil {
                    if image != nil {
                        Section("이미지 설정") {
                            TextField("개체 이름", text: $name)
                            TextField("이미지 설명", text: $alternativeText, axis: .vertical)
                            Button("설정 적용") { report(viewModel.updateSheetImageDescription(selection, name: name, alternativeText: alternativeText)) }
                            PhotosPicker("이미지 교체", selection: $replacement, matching: .images)
                        }.disabled(!canEdit)
                    } else if let chart {
                        Section("차트 설정") {
                            TextField("차트 제목", text: $name)
                            Picker("차트 종류", selection: $chartKind) {
                                ForEach(ExcelChartKind.allCases.filter { $0.isEditable || $0 == chart.kind }) { kind in Text(kind.title).tag(kind) }
                            }
                            TextField("원본 셀 범위", text: $source).textInputAutocapitalization(.characters).autocorrectionDisabled()
                            Button("설정 적용") {
                                if name == chart.title, chartKind == chart.kind, source == chart.sourceRange?.reference { message = AppLocalization.string("변경할 내용이 없습니다.") }
                                else { report(viewModel.updateSheetChart(id: chart.id, title: name, kind: chartKind, sourceReference: source)) }
                            }
                        }.disabled(!canEdit || !canEditChart)
                        if !canEditChart {
                            Section { Text("이 차트는 위치와 크기만 편집할 수 있습니다. 원본 차트 설정은 유지됩니다.").font(.footnote) }
                        }
                    }
                    Section {
                        TextField("왼쪽 위 기준 셀", text: $start)
                        TextField("오른쪽 아래 경계 셀", text: $end)
                        Button("위치 적용") { applyPlacement() }
                    } header: { Text("위치와 크기") } footer: {
                        Text("예: A1부터 D6 경계까지. 기준 셀을 바꾸면 셀 경계에 맞춰 배치합니다. 미세 조절은 원본 화면에서 끌어서 할 수 있습니다.")
                    }
                    .textInputAutocapitalization(.characters).autocorrectionDisabled().disabled(!canEdit)
                    if let message { Section { Text(message).font(.footnote) } }
                } else { Text("선택한 개체가 없습니다.") }
            }
            .navigationTitle("개체 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
            .onAppear {
                name = image?.name ?? chart?.title ?? ""
                alternativeText = image?.alternativeText ?? ""
                chartKind = chart?.kind ?? .column
                source = chart?.sourceRange?.reference ?? ""
                start = normalizedAnchor?.start.reference ?? ""
                end = normalizedAnchor?.end.reference ?? ""
            }
            .onChange(of: replacement) { _, item in
                guard let item else { return }
                isLoadingImage = true
                Task { @MainActor in
                    defer { isLoadingImage = false; replacement = nil }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self), image != nil, sheet != nil else { return }
                        report(viewModel.replaceSheetImage(id: selection.id, data: data))
                    } catch { message = error.localizedDescription }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    private func report(_ succeeded: Bool) {
        message = succeeded ? AppLocalization.string("개체 설정을 적용했습니다.") : viewModel.status
    }
    private func applyPlacement() {
        guard let current = anchor, let a = ExcelCellAddress(start), let b = ExcelCellAddress(end) else {
            message = ExcelDrawingMessage.invalidPlacement; return
        }
        if a == normalizedAnchor?.start, b == normalizedAnchor?.end { message = AppLocalization.string("변경할 내용이 없습니다."); return }
        guard a.row < b.row, a.column < b.column else {
            message = ExcelDrawingMessage.invalidPlacement; return
        }
        report(viewModel.updateDrawingPlacement(selection, expected: current, anchor: .init(start: a, end: b)))
    }
}
