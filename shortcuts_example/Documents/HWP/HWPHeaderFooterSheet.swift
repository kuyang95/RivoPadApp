import SwiftUI

struct HWPHeaderFooterSheet: View {
    let selection: HWPHeaderFooterEditing.Selection
    let onApply: (HWPHeaderFooterRequest) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Int?
    @State private var texts: [String]
    @State private var alignment = "keep"
    @State private var size = 0
    @State private var scope: HWPDocumentHeaderFooterScope
    @State private var allSections = false

    init(selection: HWPHeaderFooterEditing.Selection, onApply: @escaping (HWPHeaderFooterRequest) -> Void) {
        self.selection = selection; self.onApply = onApply
        _texts = State(initialValue: selection.current.isEmpty ? [""] : selection.current.map(\.text))
        _scope = State(initialValue: selection.current.first?.region.scope ?? .bothPages)
    }
    private var sections: Set<Int> { allSections ? Set(selection.layouts.map(\.sectionIndex)) : [selection.section] }
    private var supported: Bool {
        sections.isSubset(of: selection.supported) && sections.allSatisfy {
            let count = selection.paragraphs[$0]?.count ?? 0
            return count == 0 || count == texts.count
        }
    }
    private var request: HWPHeaderFooterRequest {
        let align: HWPParagraphAlignment? = alignment == "left" ? .leading : alignment == "center" ? .centered : alignment == "right" ? .trailing : nil
        return .init(kind: selection.kind, texts: texts, sections: sections, alignment: align,
                     size: size == 0 ? nil : Double(size), scope: scope)
    }
    var body: some View {
        NavigationStack {
            Form {
                if selection.layouts.count > 1 {
                    Section {
                        Picker("적용 범위", selection: $allSections) {
                            Text("현재 구역").tag(false); Text("전체 문서").tag(true)
                        }.pickerStyle(.segmented).accessibilityIdentifier("hwp-region-sections")
                    }
                }
                if !supported {
                    Section {
                        Text("이 영역은 아직 편집할 수 없습니다. 여러 머리말·꼬리말이나 표·그림이 포함된 경우에는 원본 내용을 유지합니다.")
                    }
                }
                Section {
                    ForEach(texts.indices, id: \.self) { index in
                        TextEditor(text: $texts[index]).frame(minHeight: 80, maxHeight: 150)
                            .focused($focused, equals: index).accessibilityLabel(AppLocalization.string("내용"))
                            .accessibilityIdentifier("hwp-region-text-\(index)")
                    }
                    Button("내용 지우기", role: .destructive) { texts = texts.map { _ in "" } }
                        .accessibilityIdentifier("hwp-region-clear")
                } header: { Text("내용") } footer: {
                    Text("기존 글자 서식을 유지합니다. 새 영역은 바탕 10pt로 만듭니다. 비워 두면 내용이 표시되지 않습니다.")
                }
                .disabled(!supported)
                Section {
                    Picker("정렬", selection: $alignment) {
                        Text("기존 유지").tag("keep"); Text("왼쪽").tag("left")
                        Text("가운데").tag("center"); Text("오른쪽").tag("right")
                    }.accessibilityIdentifier("hwp-region-alignment")
                    Picker("글자 크기", selection: $size) {
                        Text("기존 유지").tag(0)
                        ForEach([8, 9, 10, 11, 12, 14, 16, 18, 20, 24], id: \.self) { Text("\($0) pt").tag($0) }
                    }.accessibilityIdentifier("hwp-region-size")
                    Picker("표시할 쪽", selection: $scope) {
                        Text("모든 쪽").tag(HWPDocumentHeaderFooterScope.bothPages)
                        Text("홀수 쪽").tag(HWPDocumentHeaderFooterScope.oddPages)
                        Text("짝수 쪽").tag(HWPDocumentHeaderFooterScope.evenPages)
                    }.accessibilityIdentifier("hwp-region-pages")
                }.disabled(!supported)
            }
            .navigationTitle(AppLocalization.string(selection.kind.title)).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { focused = nil; dismiss() }.accessibilityIdentifier("hwp-region-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") { focused = nil; onApply(request) }
                        .disabled(!supported || texts.reduce(0, { $0 + $1.utf16.count }) > 2_000)
                        .accessibilityIdentifier("hwp-region-apply")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("완료") { focused = nil } }
            }
        }.presentationSizing(.page)
    }
}
