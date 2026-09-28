import SwiftUI

struct HWPPageNumberSheet: View {
    let selection: HWPPageSetup.Selection
    let onApply: (HWPPageNumberRequest) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editingStart: Bool
    @State private var shown: Bool
    @State private var atTop: Bool
    @State private var alignment: String
    @State private var decorated: Bool
    @State private var restart: Bool
    @State private var start: String
    @State private var allSections = true

    init(selection: HWPPageSetup.Selection, onApply: @escaping (HWPPageNumberRequest) -> Void) {
        self.selection = selection; self.onApply = onApply
        let style = selection.layout.pageNumberStyle
        _shown = State(initialValue: style != nil)
        _atTop = State(initialValue: style?.position.hasPrefix("TOP") ?? false)
        _alignment = State(initialValue: style?.position.components(separatedBy: "_").last ?? "CENTER")
        _decorated = State(initialValue: style?.sideCharacter == "-")
        _restart = State(initialValue: style?.startsAt != nil)
        _start = State(initialValue: String(style?.startsAt ?? 1))
    }
    private var request: HWPPageNumberRequest? {
        let sections = allSections ? Set(selection.layouts.map(\.sectionIndex)) : [selection.layout.sectionIndex]
        if !shown { return .init(style: nil, sections: sections) }
        let number = Int(start.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !restart || number.map({ (1...65_535).contains($0) }) == true else { return nil }
        return .init(style: .init(position: "\(atTop ? "TOP" : "BOTTOM")_\(alignment)",
                                  sideCharacter: decorated ? "-" : "", startsAt: restart ? number : nil), sections: sections)
    }
    var body: some View {
        NavigationStack {
            Form {
                if selection.layouts.count > 1 {
                    Section {
                        Picker("적용 범위", selection: $allSections) {
                            Text("전체 문서").tag(true); Text("현재 구역").tag(false)
                        }.pickerStyle(.segmented).accessibilityIdentifier("hwp-number-scope")
                    }
                }
                Section {
                    Toggle("쪽 번호 표시", isOn: $shown).accessibilityIdentifier("hwp-number-show")
                }
                if shown {
                    Section("위치") {
                        Picker("위치", selection: $atTop) {
                            Text("위쪽").tag(true); Text("아래쪽").tag(false)
                        }.pickerStyle(.segmented).accessibilityIdentifier("hwp-number-position")
                        Picker("정렬", selection: $alignment) {
                            Text("왼쪽").tag("LEFT"); Text("가운데").tag("CENTER"); Text("오른쪽").tag("RIGHT")
                        }.pickerStyle(.segmented).accessibilityIdentifier("hwp-number-alignment")
                        Toggle("번호 양옆에 줄표", isOn: $decorated).accessibilityIdentifier("hwp-number-decoration")
                        Text(decorated ? "- \(restart ? start : "1") -" : (restart ? start : "1"))
                            .font(.title2.monospacedDigit()).frame(maxWidth: .infinity)
                            .accessibilityIdentifier("hwp-number-preview")
                    }
                    Section {
                        Toggle("새 번호로 시작", isOn: $restart).accessibilityIdentifier("hwp-number-restart")
                        if restart {
                            HStack {
                                Text("시작 번호")
                                TextField("1", text: $start).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                                    .focused($editingStart).accessibilityIdentifier("hwp-number-start")
                                Button { start = ""; editingStart = true } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 44, height: 44)
                                }.buttonStyle(.borderless).accessibilityLabel("입력 지우기").accessibilityIdentifier("hwp-number-start-clear")
                            }
                        }
                    } footer: {
                        Text(restart ? "1~65535 사이의 번호를 입력하세요. 전체 문서에 적용하면 첫 구역부터 이어집니다." : "앞 구역의 쪽 번호를 이어서 사용합니다.")
                    }
                }
            }.navigationTitle("쪽 번호").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") { editingStart = false; dismiss() }.accessibilityIdentifier("hwp-number-cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("적용") { if let request { editingStart = false; onApply(request) } }
                            .disabled(request == nil).accessibilityIdentifier("hwp-number-apply")
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer(); Button("완료") { editingStart = false }.accessibilityIdentifier("hwp-number-keyboard-done")
                    }
                }
        }.presentationSizing(.page)
    }
}
