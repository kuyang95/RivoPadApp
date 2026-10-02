import RivoDocumentEngine
import SwiftUI

nonisolated struct HWPEquationObjectEditingContext: Sendable {
    var selectedID: String?
    var onSelect: @MainActor @Sendable (String, HWPDocumentCanvasObject) -> Void = { _, _ in }
}

private struct HWPEquationObjectEditingKey: EnvironmentKey {
    static let defaultValue = HWPEquationObjectEditingContext()
}

nonisolated struct HWPTextBoxObjectEditingContext: Sendable {
    var selectedID: String?
    var onSelect: @MainActor @Sendable (String, HWPDocumentCanvasObject, [HWPDocumentBlock]) -> Void = { _, _, _ in }
}

private struct HWPTextBoxObjectEditingKey: EnvironmentKey {
    static let defaultValue = HWPTextBoxObjectEditingContext()
}

extension EnvironmentValues {
    var hwpEquationObjectEditing: HWPEquationObjectEditingContext {
        get { self[HWPEquationObjectEditingKey.self] }
        set { self[HWPEquationObjectEditingKey.self] = newValue }
    }

    var hwpTextBoxObjectEditing: HWPTextBoxObjectEditingContext {
        get { self[HWPTextBoxObjectEditingKey.self] }
        set { self[HWPTextBoxObjectEditingKey.self] = newValue }
    }
}

struct HWPEquationInsertionButton: View {
    let enabled: Bool
    let selection: () -> HWPEquationEditing.Selection?
    let restoreFocus: () -> Void
    let onSelect: (HWPEquationEditing.Selection) -> Void

    var body: some View {
        Button {
            guard let value = selection() else { restoreFocus(); return }
            onSelect(value)
        } label: {
            Label("수식", systemImage: "function")
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 48, minHeight: 48)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier("hwp-equation-insert")
    }
}

struct HWPTextBoxInsertionButton: View {
    let enabled: Bool
    let selection: () -> HWPTextBoxEditing.Selection?
    let restoreFocus: () -> Void
    let onSelect: (HWPTextBoxEditing.Selection) -> Void

    var body: some View {
        Button {
            guard let value = selection() else { restoreFocus(); return }
            onSelect(value)
        } label: {
            Label("글상자", systemImage: "character.textbox")
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 48, minHeight: 48)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier("hwp-textbox-insert")
    }
}

struct HWPTextBoxInsertionSheet: View {
    let selection: HWPTextBoxEditing.Selection
    let onApply: (HWPTextBoxEditing.Request) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = "글상자"
    @State private var width = 180.0
    @State private var height = 90.0

    var body: some View {
        NavigationStack {
            Form {
                Section("내용") { TextEditor(text: $text).frame(minHeight: 120) }
                Section("크기") {
                    Stepper("너비 \(Int(width))pt", value: $width, in: 60...600, step: 10)
                    Stepper("높이 \(Int(height))pt", value: $height, in: 30...600, step: 10)
                }
            }
            .navigationTitle("글상자 삽입").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("삽입") {
                        let request = HWPTextBoxEditing.Request(selection: selection, text: text,
                            widthPoints: width, heightPoints: height)
                        guard request.isValid else { return }
                        dismiss(); onApply(request)
                    }
                    .disabled(!HWPTextBoxEditing.Request(selection: selection, text: text,
                        widthPoints: width, heightPoints: height).isValid)
                }
            }
        }
    }
}

struct HWPEquationInsertionSheet: View {
    let selection: HWPEquationEditing.Selection
    let onApply: (HWPEquationEditing.Request) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var script = "x^{2}"
    @State private var fontSize = 12.0

    var body: some View {
        equationForm(title: "수식 삽입", confirms: "삽입") {
            let request = HWPEquationEditing.Request(selection: selection,
                script: script, fontSizePoints: fontSize)
            guard request.isValid else { return }
            dismiss(); onApply(request)
        }
    }

    @ViewBuilder private func equationForm(title: String, confirms: String,
                                           onConfirm: @escaping () -> Void) -> some View {
        NavigationStack {
            Form {
                Section("수식") {
                    TextEditor(text: $script).frame(minHeight: 110)
                    equationTemplates(script: $script)
                }
                Section("글자 크기") {
                    Stepper("\(fontSize, specifier: "%.0f")pt", value: $fontSize, in: 6...144, step: 1)
                }
                Section {
                    Text("한글 수식 문법 예: {a} over {b}, x^{2}, sqrt {x}")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirms, action: onConfirm)
                        .disabled(!HWPEquationEditing.Request(selection: selection,
                            script: script, fontSizePoints: fontSize).isValid)
                }
            }
        }
    }
}

struct HWPEquationEditingSheet: View {
    let target: HWPEquationEditing.Target
    let onUpdate: (HWPEquationEditing.Update) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var script = ""
    @State private var fontSize = 12.0

    var body: some View {
        NavigationStack {
            Form {
                Section("수식") {
                    TextEditor(text: $script).frame(minHeight: 110)
                    equationTemplates(script: $script)
                }
                Section("글자 크기") {
                    Stepper("\(fontSize, specifier: "%.0f")pt", value: $fontSize, in: 6...144, step: 1)
                }
                Section {
                    Button("수식 삭제", role: .destructive) { dismiss(); onDelete() }
                }
            }
            .navigationTitle("수식 편집").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") {
                        let update = HWPEquationEditing.Update(script: script, fontSizePoints: fontSize)
                        guard update.isValid else { return }
                        dismiss(); onUpdate(update)
                    }
                    .disabled(!HWPEquationEditing.Update(script: script, fontSizePoints: fontSize).isValid)
                }
            }
            .onAppear { script = target.script; fontSize = target.fontSizePoints }
        }
    }
}

@ViewBuilder private func equationTemplates(script: Binding<String>) -> some View {
    HStack {
        Button("분수") { script.wrappedValue = "{a} over {b}" }
        Spacer()
        Button("제곱") { script.wrappedValue = "x^{2}" }
        Spacer()
        Button("근호") { script.wrappedValue = "sqrt {x}" }
        Spacer()
        Button("행렬") { script.wrappedValue = "matrix { a & b # c & d }" }
    }
    .buttonStyle(.bordered)
}

struct HWPTextBoxEditingSheet: View {
    let target: HWPTextBoxEditing.Target
    let onApply: (HWPTextBoxEditing.Update) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var paragraphs: [HWPTextBoxEditing.Paragraph] = []

    var body: some View {
        NavigationStack {
            Form {
                ForEach(paragraphs.indices, id: \.self) { index in
                    Section {
                        TextEditor(text: $paragraphs[index].text)
                            .frame(minHeight: 90)
                            .disabled(!isTextEditable(paragraphs[index]))
                        if !isTextEditable(paragraphs[index]) {
                            Text("내부 개체가 있는 문단은 순서만 바꿀 수 있으며 글자와 개체는 그대로 보존됩니다.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Button { moveParagraph(index, by: -1) } label: {
                                Label("위로", systemImage: "arrow.up")
                            }
                            .disabled(index == 0)
                            Spacer()
                            Button { moveParagraph(index, by: 1) } label: {
                                Label("아래로", systemImage: "arrow.down")
                            }
                            .disabled(index == paragraphs.count - 1)
                            Spacer()
                            Button(role: .destructive) { removeParagraph(index) } label: {
                                Label("삭제", systemImage: "trash")
                            }
                            .disabled(paragraphs.count == 1 || !isTextEditable(paragraphs[index]))
                        }
                        .buttonStyle(.borderless)
                    } header: {
                        Text(paragraphs.count == 1 ? "내용" : "문단 \(index + 1)")
                    }
                }
                Section {
                    Button { addParagraph() } label: {
                        Label("문단 추가", systemImage: "plus.circle")
                    }
                    .disabled(paragraphs.count >= 64)
                }
                if target.internalObjectCount > 0 || target.internalTableCount > 0 {
                    Section("내부 내용") {
                        if target.internalObjectCount > 0 {
                            Label("편집 가능한 그림·도형·수식 \(target.internalObjectCount)개",
                                systemImage: "square.on.square")
                        }
                        if target.internalTableCount > 0 {
                            Label("표 \(target.internalTableCount)개 · 셀 글자 직접 편집",
                                systemImage: "tablecells")
                        }
                        Text("적용한 뒤 글상자 안의 개체나 표 셀을 직접 누르면 해당 편집 화면이 열립니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text("문단별 글자·문단 서식은 유지되며 새 문단은 앞 문단의 기본 서식을 따릅니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("글상자 편집").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") {
                        let update = HWPTextBoxEditing.Update(paragraphs: paragraphs)
                        guard update.isValid else { return }
                        dismiss(); onApply(update)
                    }
                    .disabled(!HWPTextBoxEditing.Update(paragraphs: paragraphs).isValid
                        || unchanged)
                }
            }
            .onAppear {
                paragraphs = target.entries.map {
                    HWPTextBoxEditing.Paragraph(sourceID: $0.id, text: $0.text)
                }
            }
        }
    }

    private var unchanged: Bool {
        paragraphs.map(\.sourceID) == target.entries.map { Optional($0.id) }
            && paragraphs.map(\.text) == target.entries.map(\.text)
    }

    private func addParagraph() {
        guard paragraphs.count < 64 else { return }
        paragraphs.append(.init(sourceID: nil, text: ""))
    }

    private func isTextEditable(_ paragraph: HWPTextBoxEditing.Paragraph) -> Bool {
        guard let sourceID = paragraph.sourceID,
              let entry = target.entries.first(where: { $0.id == sourceID }) else { return true }
        return entry.isTextEditable
    }

    private func removeParagraph(_ index: Int) {
        guard paragraphs.count > 1, paragraphs.indices.contains(index) else { return }
        paragraphs.remove(at: index)
    }

    private func moveParagraph(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard paragraphs.indices.contains(index), paragraphs.indices.contains(destination) else { return }
        paragraphs.swapAt(index, destination)
    }
}
