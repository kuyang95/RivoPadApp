import SwiftUI

struct HWPTableSizingSheet: View {
    let selection: HWPTableSizing.Selection
    let onApply: (HWPTableDimensions) -> Void
    @State private var widthText: String
    @State private var heightText: String
    @FocusState private var focusedDimension: String?
    @Environment(\.dismiss) private var dismiss

    init(selection: HWPTableSizing.Selection, onApply: @escaping (HWPTableDimensions) -> Void) {
        self.selection = selection; self.onApply = onApply
        _widthText = State(initialValue: Self.mm(selection.width))
        _heightText = State(initialValue: Self.mm(selection.height))
    }

    private static func mm(_ points: Double) -> String { String(format: "%.1f", points / HWPTableSizing.pointsPerMM) }
    private func points(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")), value.isFinite else { return nil }
        return value * HWPTableSizing.pointsPerMM
    }
    private var request: HWPTableDimensions? {
        let widthChanged = widthText != Self.mm(selection.width), heightChanged = heightText != Self.mm(selection.height)
        guard widthChanged || heightChanged else { return nil }
        var result = HWPTableDimensions()
        if widthChanged {
            guard let width = points(widthText), width >= HWPTableSizing.pointsPerMM, width <= selection.maximumWidth + 0.005 else { return nil }
            if abs(width - selection.width) > 0.005 { result.widthPoints = width }
        }
        if heightChanged {
            guard let height = points(heightText), height >= HWPTableSizing.pointsPerMM, height <= selection.maximumHeight + 0.005 else { return nil }
            if abs(height - selection.height) > 0.005 { result.heightPoints = height }
        }
        return result.widthPoints != nil || result.heightPoints != nil ? result : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("선택한 행", value: range(selection.row, selection.rowSpan))
                    LabeledContent("선택한 열", value: range(selection.column, selection.columnSpan))
                } footer: {
                    if selection.rowSpan > 1 || selection.columnSpan > 1 {
                        Text("병합 셀은 포함된 열·행의 전체 크기를 비율에 맞춰 조절합니다.")
                    } else { Text("변경한 열·행의 모든 셀에 적용됩니다.") }
                }
                Section(selection.columnSpan > 1 ? "병합된 열 너비" : "열 너비") {
                    dimensionField(text: $widthText, current: selection.width, maximum: selection.maximumWidth, id: "width")
                }
                Section {
                    dimensionField(text: $heightText, current: selection.height, maximum: selection.maximumHeight, id: "height")
                } header: {
                    Text(selection.rowSpan > 1 ? "병합된 행 높이" : "행 높이")
                } footer: {
                    Text("글이 잘리지 않도록 내용에 필요한 최소 높이는 유지합니다.")
                }
            }
            .accessibilityIdentifier("hwp-table-size-form")
            .navigationTitle("행·열 크기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { focusedDimension = nil; dismiss() }.accessibilityIdentifier("hwp-table-size-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") { if let request { focusedDimension = nil; onApply(request) } }
                        .disabled(request == nil).accessibilityIdentifier("hwp-table-size-apply")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") { focusedDimension = nil }
                        .accessibilityIdentifier("hwp-table-size-keyboard-done")
                }
            }
        }.presentationSizing(.page)
    }

    private func dimensionField(text: Binding<String>, current: Double, maximum: Double, id: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("크기")
                Spacer()
                TextField("mm", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .focused($focusedDimension, equals: id).submitLabel(.done)
                    .onSubmit { focusedDimension = nil }
                    .frame(maxWidth: 150).accessibilityIdentifier("hwp-table-size-\(id)")
                Button {
                    text.wrappedValue = ""; focusedDimension = id
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        .frame(width: 48, height: 48)
                }.buttonStyle(.borderless).accessibilityLabel("입력 지우기")
                    .accessibilityIdentifier("hwp-table-size-\(id)-clear")
                Text("mm").foregroundStyle(.secondary)
                Stepper("크기 조절") {
                    adjust(text, by: 1, current: current, maximum: maximum)
                } onDecrement: {
                    adjust(text, by: -1, current: current, maximum: maximum)
                }.labelsHidden().fixedSize().accessibilityIdentifier("hwp-table-size-\(id)-stepper")
            }
            Text(String(format: AppLocalization.string("1.0~%@ mm"), Self.mm((maximum / HWPTableSizing.pointsPerMM * 10).rounded(.down) / 10 * HWPTableSizing.pointsPerMM)))
                .font(.footnote).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
    private func adjust(_ text: Binding<String>, by delta: Double, current: Double, maximum: Double) {
        let value = (points(text.wrappedValue) ?? current) / HWPTableSizing.pointsPerMM
        let limit = (maximum / HWPTableSizing.pointsPerMM * 10).rounded(.down) / 10
        text.wrappedValue = String(format: "%.1f", min(limit, max(1, value + delta)))
    }
    private func range(_ start: Int, _ span: Int) -> String {
        span == 1 ? String(start + 1) : "\(start + 1)–\(start + span)"
    }
}
