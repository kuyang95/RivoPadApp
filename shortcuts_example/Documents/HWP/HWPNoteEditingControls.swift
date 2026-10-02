import RivoDocumentEngine
import SwiftUI

struct HWPNoteButton: View {
    let enabled: Bool
    let selection: () -> HWPNoteEditing.Selection
    let restoreFocus: () -> Void
    let onApply: (HWPNoteEditing.Action) -> Void

    @State private var pending: HWPNoteEditing.Selection?

    var body: some View {
        Button { pending = selection() } label: {
            Label("주석", systemImage: "text.badge.plus")
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 48, minHeight: 48)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("각주와 미주")
        .accessibilityIdentifier("hwp-notes")
        .sheet(item: $pending, onDismiss: restoreFocus) { value in
            HWPNoteManager(selection: value) { action in
                onApply(action)
                pending = nil
            }
        }
    }
}

private struct HWPNoteManager: View {
    let selection: HWPNoteEditing.Selection
    let onApply: (HWPNoteEditing.Action) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let insertion = selection.insertion {
                    Section("현재 커서 위치에 추가") {
                        ForEach(HWPNoteKind.allCases) { kind in
                            NavigationLink {
                                HWPNoteEditor(title: "\(kind.title) 삽입", initialText: "") { text in
                                    onApply(.insert(kind, text, insertion))
                                }
                                .visionCraftRouteBackButton()
                            } label: {
                                Label("\(kind.title) 추가", systemImage: kind == .footNote
                                      ? "text.append" : "doc.append")
                            }
                            .accessibilityIdentifier("hwp-note-insert-\(kind.rawValue)")
                        }
                    }
                } else {
                    Section {
                        Label("본문에 커서를 놓으면 새 각주나 미주를 추가할 수 있습니다.",
                              systemImage: "cursorarrow.click")
                            .foregroundStyle(.secondary)
                    }
                }

                Section(selection.notes.isEmpty ? "이 구역의 주석 없음" : "이 구역의 주석") {
                    ForEach(selection.notes) { note in
                        NavigationLink {
                            HWPNoteEditor(title: "\(note.kind.title) \(note.number)",
                                          initialText: note.text,
                                          onDelete: { onApply(.delete(note)) }) { text in
                                onApply(.update(note, text))
                            }
                            .visionCraftRouteBackButton()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(note.kind.title) \(note.number)")
                                    .font(.subheadline.weight(.semibold))
                                Text(note.text.isEmpty ? "내용 없음" : note.text)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .accessibilityIdentifier("hwp-note-edit-\(note.kind.rawValue)-\(note.number)")
                    }
                }
            }
            .navigationTitle("각주·미주")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .accessibilityIdentifier("hwp-note-close")
                }
            }
        }
    }
}

private struct HWPNoteEditor: View {
    let title: String
    let initialText: String
    var onDelete: (() -> Void)? = nil
    let onApply: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(title: String, initialText: String, onDelete: (() -> Void)? = nil,
         onApply: @escaping (String) -> Void) {
        self.title = title
        self.initialText = initialText
        self.onDelete = onDelete
        self.onApply = onApply
        _text = State(initialValue: initialText)
    }

    private var isValid: Bool { (try? HWPNoteEditing.validatedText(text)) != nil }

    var body: some View {
        Form {
            Section("주석 내용") {
                TextEditor(text: $text)
                    .frame(minHeight: 160)
                    .accessibilityIdentifier("hwp-note-text")
                Text("\(text.utf16.count) / 2,000")
                    .font(.caption)
                    .foregroundStyle(text.utf16.count > 2_000 ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if let onDelete {
                Section {
                    Button("주석 삭제", role: .destructive) {
                        onDelete()
                    }
                    .accessibilityIdentifier("hwp-note-delete")
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("적용") {
                    guard isValid else { return }
                    onApply(text)
                }
                .disabled(!isValid || text == initialText)
                .accessibilityIdentifier("hwp-note-apply")
            }
        }
    }
}
