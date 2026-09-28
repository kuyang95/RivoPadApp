import SwiftUI

struct HWPPageSetupSheet: View {
    let selection: HWPPageSetup.Selection
    let onApply: (HWPPageSetupRequest) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var values: [Field: String]
    @State private var allSections = true

    private enum Field: String, CaseIterable {
        case width, height, left, right, top, bottom, header, footer
        var title: String {
            switch self {
            case .width: "용지 너비"; case .height: "용지 높이"
            case .left: "왼쪽 여백"; case .right: "오른쪽 여백"
            case .top: "위쪽 여백"; case .bottom: "아래쪽 여백"
            case .header: "머리말 여백"; case .footer: "꼬리말 여백"
            }
        }
        var key: WritableKeyPath<HWPPageSettings, Double> {
            switch self {
            case .width: \.width; case .height: \.height; case .left: \.left; case .right: \.right
            case .top: \.top; case .bottom: \.bottom; case .header: \.header; case .footer: \.footer
            }
        }
    }
    private struct Paper: Identifiable {
        let id: String, width: Double, height: Double
        static let all: [Paper] = [
            .init(id: "A4", width: 210, height: 297), .init(id: "A3", width: 297, height: 420),
            .init(id: "A5", width: 148, height: 210), .init(id: "B5 (JIS)", width: 182, height: 257),
            .init(id: "Letter", width: 215.9, height: 279.4), .init(id: "Legal", width: 215.9, height: 355.6)
        ]
    }
    init(selection: HWPPageSetup.Selection, onApply: @escaping (HWPPageSetupRequest) -> Void) {
        self.selection = selection; self.onApply = onApply
        let settings = HWPPageSettings(selection.layout)
        _values = State(initialValue: Dictionary(uniqueKeysWithValues: Field.allCases.map { ($0, Self.mm(settings[keyPath: $0.key])) }))
    }
    private static func mm(_ value: Double) -> String { String(format: "%.1f", value / HWPPageSettings.pointsPerMM) }
    private var settings: HWPPageSettings? {
        let original = HWPPageSettings(selection.layout)
        var result = original
        for field in Field.allCases {
            let text = values[field] ?? ""
            if text == Self.mm(original[keyPath: field.key]) { continue }
            guard let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")), number.isFinite else { return nil }
            result[keyPath: field.key] = number * HWPPageSettings.pointsPerMM
        }
        return result
    }
    private var sections: Set<Int> { allSections ? Set(selection.layouts.map(\.sectionIndex)) : [selection.layout.sectionIndex] }
    private var supportsScope: Bool { selection.layouts.filter { sections.contains($0.sectionIndex) }.allSatisfy { $0.columnLayout.columns.count <= 1 } }
    private var request: HWPPageSetupRequest? {
        guard let settings, settings.isValid, supportsScope,
              selection.layouts.contains(where: { sections.contains($0.sectionIndex) && !settings.matches($0) }) else { return nil }
        return .init(settings: settings, sections: sections)
    }
    private var paperName: String {
        guard let s = settings else { return AppLocalization.string("사용자 지정") }
        return Paper.all.first { abs(min(s.width, s.height) / HWPPageSettings.pointsPerMM - $0.width) < 0.15
            && abs(max(s.width, s.height) / HWPPageSettings.pointsPerMM - $0.height) < 0.15 }?.id ?? AppLocalization.string("사용자 지정")
    }
    var body: some View {
        NavigationStack {
            Form {
                if selection.layouts.count > 1 {
                    Section {
                        Picker("적용 범위", selection: $allSections) {
                            Text("전체 문서").tag(true); Text("현재 구역").tag(false)
                        }.pickerStyle(.segmented).accessibilityIdentifier("hwp-page-scope")
                        Text(AppLocalization.format("현재 %lld번째 구역", (selection.layouts.firstIndex { $0.sectionIndex == selection.layout.sectionIndex } ?? 0) + 1))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("용지") {
                    Menu {
                        ForEach(Paper.all) { paper in
                            Button(paper.id) {
                                let landscape = settings?.isLandscape ?? selection.layout.isLandscape
                                values[.width] = String(format: "%.1f", landscape ? paper.height : paper.width)
                                values[.height] = String(format: "%.1f", landscape ? paper.width : paper.height)
                                focusedField = nil
                            }.accessibilityIdentifier("hwp-page-paper-\(paper.id)")
                        }
                    } label: { LabeledContent("용지 크기", value: paperName) }
                        .accessibilityIdentifier("hwp-page-paper")
                    Picker("방향", selection: Binding(get: { settings?.isLandscape ?? selection.layout.isLandscape }, set: { landscape in
                        guard var s = settings else { return }; s.orient(landscape: landscape)
                        values[.width] = Self.mm(s.width); values[.height] = Self.mm(s.height); focusedField = nil
                    })) {
                        Text("세로").tag(false); Text("가로").tag(true)
                    }.pickerStyle(.segmented).accessibilityIdentifier("hwp-page-orientation")
                    field(.width); field(.height)
                }
                Section {
                    HStack {
                        ForEach([10.0, 20, 30], id: \.self) { value in
                            Button(AppLocalization.string(value == 10 ? "좁게" : value == 20 ? "보통" : "넓게")) {
                                for f in [Field.left, .right, .top, .bottom] { values[f] = String(format: "%.1f", value) }
                                focusedField = nil
                            }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                                .accessibilityIdentifier("hwp-page-margins-\(Int(value))")
                        }
                    }
                    field(.left); field(.right); field(.top); field(.bottom)
                    DisclosureGroup("머리말·꼬리말 여백") { field(.header); field(.footer) }
                } header: { Text("여백") } footer: {
                    Text("표와 그림의 크기는 유지됩니다.")
                    if !supportsScope { Text("다단이 포함된 구역의 쪽 설정은 아직 지원하지 않습니다.") }
                    else if settings?.isValid != true { Text("용지는 25.4~705.5mm, 여백은 용지 짧은 변의 45% 이내로 입력하고 본문 공간을 남겨 주세요.") }
                }
            }.accessibilityIdentifier("hwp-page-setup-form")
                .navigationTitle("쪽 설정").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") { focusedField = nil; dismiss() }.accessibilityIdentifier("hwp-page-cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("적용") { if let request { focusedField = nil; onApply(request) } }
                            .disabled(request == nil).accessibilityIdentifier("hwp-page-apply")
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer(); Button("완료") { focusedField = nil }.accessibilityIdentifier("hwp-page-keyboard-done")
                    }
                }
        }.presentationSizing(.page)
    }
    private func field(_ field: Field) -> some View {
        HStack {
            Text(AppLocalization.string(field.title))
            Spacer()
            TextField("mm", text: Binding(get: { values[field] ?? "" }, set: { values[field] = $0 }))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 110)
                .focused($focusedField, equals: field).submitLabel(.done).onSubmit { focusedField = nil }
                .accessibilityIdentifier("hwp-page-\(field.rawValue)")
            Button { values[field] = ""; focusedField = field } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 44, height: 44)
            }.buttonStyle(.borderless).accessibilityLabel("입력 지우기").accessibilityIdentifier("hwp-page-\(field.rawValue)-clear")
            Text("mm").foregroundStyle(.secondary)
        }
    }
}

struct HWPPageSetupButton: View {
    var expanded = false
    let selection: () -> HWPPageSetup.Selection?
    let restoreFocus: () -> Void
    let onApply: (HWPPageSetupRequest) -> Void
    @State private var presented: HWPPageSetup.Selection?
    @State private var pending: HWPPageSetupRequest?
    @State private var numberPresented: HWPPageSetup.Selection?
    @State private var pendingNumber: HWPPageNumberRequest?
    var onApplyNumber: (HWPPageNumberRequest) -> Void = { _ in }
    @State private var columnPresented: HWPColumnSetup.Selection?
    @State private var pendingColumn: HWPColumnSetupRequest?
    var onApplyColumn: (HWPColumnSetupRequest) -> Void = { _ in }
    @State private var regionPresented: HWPHeaderFooterEditing.Selection?
    @State private var pendingRegion: HWPHeaderFooterRequest?
    var headerFooterSelection: (HWPHeaderFooterKind) -> HWPHeaderFooterEditing.Selection? = { _ in nil }
    var onApplyHeaderFooter: (HWPHeaderFooterRequest) -> Void = { _ in }
    var canInsertBreak = false
    var canRemoveBreak = false
    var onInsertBreak: () -> Void = {}
    var onRemoveBreak: () -> Void = {}
    var body: some View {
        Group {
            if expanded {
                HStack(spacing: 16) { actions }
                    .buttonStyle(HWPRibbonPageButtonStyle())
                    .font(.subheadline)
                    .frame(minHeight: 44)
            } else {
                Menu { actions } label: {
                    Label("쪽", systemImage: "doc.badge.gearshape").font(.subheadline)
                        .frame(minWidth: 60, minHeight: 44)
                }.accessibilityLabel("쪽").accessibilityIdentifier("hwp-page-menu")
            }
        }
            .sheet(item: $presented, onDismiss: {
                if let pending { self.pending = nil; onApply(pending) } else { restoreFocus() }
            }) { selection in
                HWPPageSetupSheet(selection: selection) { request in pending = request; presented = nil }
            }
            .sheet(item: $numberPresented, onDismiss: {
                if let pendingNumber { self.pendingNumber = nil; onApplyNumber(pendingNumber) } else { restoreFocus() }
            }) { selection in
                HWPPageNumberSheet(selection: selection) { request in pendingNumber = request; numberPresented = nil }
            }
            .sheet(item: $columnPresented, onDismiss: {
                if let pendingColumn { self.pendingColumn = nil; onApplyColumn(pendingColumn) }
                else { restoreFocus() }
            }) { selection in
                HWPColumnSetupSheet(selection: selection) { request in
                    pendingColumn = request
                    columnPresented = nil
                }
            }
            .sheet(item: $regionPresented, onDismiss: {
                if let pendingRegion { self.pendingRegion = nil; onApplyHeaderFooter(pendingRegion) } else { restoreFocus() }
            }) { selection in
                HWPHeaderFooterSheet(selection: selection) { request in pendingRegion = request; regionPresented = nil }
            }
    }
    @ViewBuilder private var actions: some View {
            Button("쪽 설정", systemImage: "doc.badge.gearshape") { presented = selection() }
                .accessibilityIdentifier("hwp-page-setup")
            Button("쪽 번호", systemImage: "number") { numberPresented = selection() }
                .accessibilityIdentifier("hwp-page-number")
            Button("다단", systemImage: "rectangle.split.3x1") {
                guard let value = selection() else { return }
                columnPresented = .init(layout: value.layout, layouts: value.layouts)
            }
            .accessibilityIdentifier("hwp-column-setup")
            ForEach(HWPHeaderFooterKind.allCases) { kind in
                Button(AppLocalization.string(kind.title), systemImage: kind == .header ? "rectangle.topthird.inset.filled" : "rectangle.bottomthird.inset.filled") { regionPresented = headerFooterSelection(kind) }
                    .accessibilityIdentifier("hwp-page-\(kind.rawValue)")
            }
            if expanded { Divider().frame(height: 24) } else { Divider() }
            Button("쪽 나누기", systemImage: "rectangle.split.1x2") { onInsertBreak() }
                .disabled(!canInsertBreak).accessibilityIdentifier("hwp-page-break-insert")
            Button("쪽 나누기 없애기", systemImage: "rectangle") { onRemoveBreak() }
                .disabled(!canRemoveBreak).accessibilityIdentifier("hwp-page-break-remove")

    }

}

private struct HWPRibbonPageButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minHeight: 44)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
