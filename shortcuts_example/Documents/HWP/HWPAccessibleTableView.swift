import SwiftUI
import UIKit

struct HWPAccessibleTableHeader: View {
    let table: HWPAccessibleTable

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Label(table.title, systemImage: "tablecells")
                    .font(.headline)
                Spacer()
                Text(AppLocalization.format("%lld행 · %lld열", table.rowCount, table.columnCount))
                    .font(.subheadline)
            }
            if let context = table.context, !context.isEmpty {
                Text(context).font(.caption)
                    .foregroundStyle(VisionCraftUI.secondaryText)
            }
        }
        .foregroundStyle(VisionCraftUI.primaryText)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VisionCraftUI.surfaceVariant, in: RoundedRectangle(cornerRadius: 12))
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct HWPAccessibleRowButton: View {
    let row: HWPAccessibleRow
    let selectedBlockID: String?
    var fieldNames: [String: String] = [:]
    let onOpen: () -> Void

    private var isSelected: Bool { row.blocks.contains { $0.id == selectedBlockID } }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(row.tableTitle + " · " + row.title).font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .foregroundStyle(VisionCraftUI.secondaryText)
                ForEach(row.spanningCells) { cell in
                    Text(AppLocalization.format("위 행과 병합: %@", cell.displayText))
                        .font(.caption)
                        .foregroundStyle(VisionCraftUI.secondaryText)
                }
                ForEach(row.cells) { cell in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(fieldNames[cell.id] ?? cell.columnDescription)
                                .font(.subheadline.weight(.semibold))
                            if fieldNames[cell.id] != nil {
                                Text(cell.columnDescription).font(.caption)
                            }
                            if let merge = cell.mergeDescription {
                                Text(merge).font(.caption)
                            }
                        }
                        .foregroundStyle(VisionCraftUI.secondaryText)
                        .frame(width: 90, alignment: .leading)
                        Text(cell.displayText)
                            .font(.body)
                            .foregroundStyle(cell.isEmpty
                                ? VisionCraftUI.secondaryText : VisionCraftUI.primaryText)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !cell.blocks.contains(where: \.isEditable) {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(VisionCraftUI.secondaryText)
                        }
                    }
                }
            }
            .multilineTextAlignment(.leading)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? VisionCraftUI.primary.opacity(0.13) : VisionCraftUI.surface,
                in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? VisionCraftUI.primary : VisionCraftUI.outline,
                        lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel(fieldNames: fieldNames))
        .accessibilityHint(row.blocks.contains(where: \.isEditable)
            ? "두 번 탭하면 이 행의 모든 값을 편집합니다."
            : "두 번 탭하면 이 행의 내용을 확인합니다.")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct HWPAccessibleRowEditor: View {
    @Environment(\.dismiss) private var dismiss
    let row: HWPAccessibleRow
    let fieldNames: [String: String]
    let onFocus: ((String) -> Void)?
    let onApply: ([String: String]) throws -> Void
    @State private var texts: [String: String]
    @State private var errorMessage: String?
    @FocusState private var focusedBlockID: String?

    init(row: HWPAccessibleRow, fieldNames: [String: String] = [:],
         onFocus: ((String) -> Void)? = nil, onApply: @escaping ([String: String]) throws -> Void) {
        self.row = row
        self.fieldNames = fieldNames
        self.onFocus = onFocus
        self.onApply = onApply
        _texts = State(initialValue: Dictionary(uniqueKeysWithValues: row.blocks.map { ($0.id, $0.text) }))
    }

    private var hasChanges: Bool {
        row.blocks.contains { texts[$0.id] != $0.text }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !row.spanningCells.isEmpty {
                    Section("위 행과 병합된 셀") {
                        ForEach(row.spanningCells) { cell in
                            LabeledContent(cell.columnDescription, value: cell.displayText)
                        }
                    }
                }
                ForEach(row.cells) { cell in
                    Section {
                        ForEach(cell.blocks) { block in
                            if block.isEditable {
                                TextField("빈 셀", text: Binding(
                                    get: { texts[block.id] ?? block.text },
                                    set: { texts[block.id] = $0 }
                                ), axis: .vertical)
                                .lineLimit(1...8)
                                .focused($focusedBlockID, equals: block.id)
                                .accessibilityLabel(fieldLabel(block, in: cell))
                            } else {
                                HStack(alignment: .top) {
                                    Text(block.text.isEmpty ? cell.displayText : block.text)
                                    Spacer()
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(VisionCraftUI.secondaryText)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(fieldLabel(block, in: cell) + ". " + block.accessibilityLabel)
                                .accessibilityValue("읽기 전용")
                            }
                            ForEach(block.images) { image in
                                if let uiImage = UIImage(data: image.data) {
                                    Image(uiImage: uiImage).resizable().scaledToFit()
                                        .frame(maxHeight: 180)
                                        .accessibilityLabel(image.description ?? AppLocalization.string("한글 문서 그림"))
                                }
                            }
                        }
                    } header: {
                        Text([fieldNames[cell.id], cell.columnDescription, cell.mergeDescription]
                            .compactMap { $0 }.joined(separator: " · "))
                    }
                }
            }
            .navigationTitle(row.tableTitle + " · " + row.title)
            .onChange(of: focusedBlockID) { _, id in
                if let id { onFocus?(id) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("변경 적용") {
                        do {
                            try onApply(texts)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(!hasChanges)
                }
            }
            .alert("변경할 수 없습니다", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("확인", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func fieldLabel(_ block: HWPDocumentBlock, in cell: HWPAccessibleCell) -> String {
        let label = [fieldNames[block.id], cell.columnDescription].compactMap { $0 }.joined(separator: " · ")
        guard cell.blocks.count > 1 else { return label }
        return label + " · " + AppLocalization.format("문단 %lld",
            (block.tableLocation?.paragraph ?? 0) + 1)
    }
}
