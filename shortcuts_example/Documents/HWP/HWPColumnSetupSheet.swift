import RivoDocumentEngine
import SwiftUI

struct HWPColumnSetupSheet: View {
    let selection: HWPColumnSetup.Selection
    let onApply: (HWPColumnSetupRequest) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var count: Int
    @State private var gapMM: Double
    @State private var showsSeparator: Bool
    @State private var allSections = false

    init(selection: HWPColumnSetup.Selection,
         onApply: @escaping (HWPColumnSetupRequest) -> Void) {
        self.selection = selection
        self.onApply = onApply
        let settings = HWPColumnSettings(selection.layout.columnLayout)
        _count = State(initialValue: settings.count)
        _gapMM = State(initialValue: settings.gapPoints / HWPPageSettings.pointsPerMM)
        _showsSeparator = State(initialValue: settings.showsSeparator)
    }

    private var sections: Set<Int> {
        allSections ? Set(selection.layouts.map(\.sectionIndex)) : [selection.layout.sectionIndex]
    }

    private var settings: HWPColumnSettings {
        .init(count: count,
            gapPoints: count > 1 ? gapMM * HWPPageSettings.pointsPerMM : 0,
            showsSeparator: count > 1 && showsSeparator)
    }

    private var request: HWPColumnSetupRequest? {
        guard selection.layouts.filter({ sections.contains($0.sectionIndex) })
                .allSatisfy({ settings.isValid(for: $0) }),
              selection.layouts.contains(where: {
                  sections.contains($0.sectionIndex) && !settings.matches($0)
              }) else { return nil }
        return .init(settings: settings, sections: sections)
    }

    private var columnWidthMM: Double {
        let layout = selection.layout
        let content = layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints
        return max(0, (content - settings.gapPoints * Double(count - 1))
            / Double(count) / HWPPageSettings.pointsPerMM)
    }

    var body: some View {
        NavigationStack {
            Form {
                if selection.layouts.count > 1 {
                    Section {
                        Picker("적용 범위", selection: $allSections) {
                            Text("현재 구역").tag(false)
                            Text("전체 문서").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section("단 수") {
                    Picker("단 수", selection: $count) {
                        ForEach(1...4, id: \.self) { Text("\($0)단").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("hwp-column-count")
                    LabeledContent("단 너비", value: String(format: "%.1f mm", columnWidthMM))
                }
                Section {
                    Stepper(value: $gapMM, in: 0...30, step: 1) {
                        LabeledContent("단 사이", value: String(format: "%.0f mm", gapMM))
                    }
                    .disabled(count == 1)
                    .accessibilityIdentifier("hwp-column-gap")
                    Toggle("구분선", isOn: $showsSeparator)
                        .disabled(count == 1)
                        .accessibilityIdentifier("hwp-column-separator")
                } header: {
                    Text("간격과 구분선")
                } footer: {
                    Text("단 설정을 바꾸면 같은 너비로 정렬하고 본문을 왼쪽 단부터 다시 배치합니다.")
                }
            }
            .navigationTitle("다단 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") {
                        guard let request else { return }
                        dismiss()
                        onApply(request)
                    }
                    .disabled(request == nil)
                    .accessibilityIdentifier("hwp-column-apply")
                }
            }
        }
        .presentationSizing(.page)
    }
}
