import SwiftUI

struct HWPTableInsertionSheet: View {
    let selection: HWPTableInsertion.Selection
    let onApply: (HWPTableInsertion.Request) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: String?
    @State private var rows = "3"
    @State private var columns = "3"
    private var request: HWPTableInsertion.Request? {
        guard let r = Int(rows), let c = Int(columns) else { return nil }
        let result = HWPTableInsertion.Request(selection: selection, rows: r, columns: c)
        return result.isValid ? result : nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("행 수", id: "rows", value: $rows)
                    field("열 수", id: "columns", value: $columns)
                } header: { Text("표 크기") } footer: {
                    Text("행과 열은 각각 1~20개입니다. 표는 본문 너비에 맞춰 만듭니다.")
                }
                if let request {
                    Section {
                        HStack(spacing: 0) {
                            ForEach(0..<min(request.columns, 10), id: \.self) { _ in
                                VStack(spacing: 0) {
                                    ForEach(0..<min(request.rows, 6), id: \.self) { _ in
                                        Rectangle().fill(.background).frame(height: 24).border(.secondary.opacity(0.5), width: 0.5)
                                    }
                                }
                            }
                        }.accessibilityHidden(true)
                        Text(AppLocalization.format("%lld행 × %lld열", request.rows, request.columns))
                            .frame(maxWidth: .infinity).accessibilityIdentifier("hwp-insert-table-preview")
                    } footer: { Text("커서 앞뒤의 글은 표 위아래에 남습니다. 삽입 후 첫 셀에서 바로 입력할 수 있습니다.") }
                }
            }.navigationTitle("표 삽입").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") { focused = nil; dismiss() }.accessibilityIdentifier("hwp-insert-table-cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("삽입") { if let request { focused = nil; onApply(request) } }
                            .disabled(request == nil).accessibilityIdentifier("hwp-insert-table-apply")
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer(); Button("완료") { focused = nil }.accessibilityIdentifier("hwp-insert-table-keyboard-done")
                    }
                }
        }.presentationSizing(.page)
    }
    private func field(_ title: String, id: String, value: Binding<String>) -> some View {
        HStack {
            Text(AppLocalization.string(title))
            Spacer()
            TextField("1~20", text: value).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .frame(maxWidth: 100).focused($focused, equals: id).accessibilityIdentifier("hwp-insert-table-\(id)")
            Button { value.wrappedValue = ""; focused = id } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 48, height: 48)
            }.buttonStyle(.borderless).accessibilityLabel("입력 지우기").accessibilityIdentifier("hwp-insert-table-\(id)-clear")
            Stepper(AppLocalization.string(title), value: Binding(get: { min(20, max(1, Int(value.wrappedValue) ?? 1)) }, set: { value.wrappedValue = String($0); focused = nil }), in: 1...20)
                .labelsHidden().fixedSize().accessibilityIdentifier("hwp-insert-table-\(id)-stepper")
        }
    }
}

struct HWPTableInsertionButton: View {
    let enabled: Bool
    let selection: () -> HWPTableInsertion.Selection?
    let restoreFocus: () -> Void
    let onApply: (HWPTableInsertion.Request) -> Void
    @State private var presented: HWPTableInsertion.Selection?
    @State private var pending: HWPTableInsertion.Request?
    var body: some View {
        Button { presented = selection() } label: {
            Label("표", systemImage: "tablecells").font(.subheadline).frame(minWidth: 60, minHeight: 48)
        }.disabled(!enabled).accessibilityLabel("표 삽입").accessibilityIdentifier("hwp-table-insert")
            .sheet(item: $presented, onDismiss: {
                if let pending { self.pending = nil; onApply(pending) } else { restoreFocus() }
            }) { selection in
                HWPTableInsertionSheet(selection: selection) { request in pending = request; presented = nil }
            }
    }
}
