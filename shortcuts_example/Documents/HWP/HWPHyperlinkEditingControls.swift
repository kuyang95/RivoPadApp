import RivoDocumentEngine
import SwiftUI

struct HWPHyperlinkButton: View {
    let enabled: Bool
    let selection: () -> HWPHyperlinkEditing.Selection?
    let restoreFocus: () -> Void
    let onApply: (HWPHyperlinkEditing.Action, HWPHyperlinkEditing.Selection) -> Void

    @State private var pending: HWPHyperlinkEditing.Selection?

    var body: some View {
        Button {
            pending = selection()
        } label: {
            Label("링크", systemImage: "link")
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 48, minHeight: 48)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("하이퍼링크")
        .accessibilityIdentifier("hwp-hyperlink")
        .sheet(item: $pending, onDismiss: restoreFocus) { value in
            HWPHyperlinkSheet(selection: value) { action in
                onApply(action, value)
                pending = nil
            }
        }
    }
}

private struct HWPHyperlinkSheet: View {
    let selection: HWPHyperlinkEditing.Selection
    let onApply: (HWPHyperlinkEditing.Action) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var target = ""
    private var normalized: String? { HWPHyperlinkEditing.normalizedTarget(target) }

    var body: some View {
        NavigationStack {
            Form {
                Section("연결 주소") {
                    TextField("https://example.com", text: $target)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("hwp-link-target")
                    Text((selection.text as NSString).substring(with: selection.range))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let current = selection.target, let url = URL(string: current) {
                    Section {
                        Button("현재 링크 열기") { openURL(url) }
                            .accessibilityIdentifier("hwp-link-open")
                        Button("링크 해제", role: .destructive) {
                            onApply(.remove)
                        }
                        .accessibilityIdentifier("hwp-link-remove")
                    }
                }
            }
            .navigationTitle(selection.target == nil ? "링크 삽입" : "링크 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") {
                        guard let normalized else { return }
                        onApply(.set(normalized))
                    }
                    .disabled(normalized == nil)
                    .accessibilityIdentifier("hwp-link-apply")
                }
            }
            .onAppear { target = selection.target ?? "" }
        }
    }
}
