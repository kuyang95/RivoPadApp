import SwiftUI
import UIKit

struct ExcelEditRowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session: ExcelRowEditingSession
    @State private var isClosing = false

    init(
        row: Int,
        initialFields: [ExcelWorkbookViewModel.RowField],
        viewModel: ExcelWorkbookViewModel
    ) {
        _session = StateObject(wrappedValue: ExcelRowEditingSession(
            row: row,
            initialFields: initialFields,
            viewModel: viewModel
        ))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VisionCraftDialogScrim(onTap: requestClose)
                VStack(spacing: 0) {
                    header
                    Divider()
                    fields
                    if session.errorMessage != nil {
                        Divider()
                        saveError
                    }
                }
                .frame(
                    width: min(840, max(0, geometry.size.width - 48)),
                    height: min(820, max(0, geometry.size.height - 48))
                )
                .background(
                    VisionCraftUI.surface,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(VisionCraftUI.outline, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Draft input stays enabled while the workbook writes a snapshot.
        .environment(\.isEnabled, true)
        .tint(VisionCraftUI.primary)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, requestClose)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                Task { await session.flush() }
            }
        }
        .onChange(of: session.errorMessage) { _, error in
            if let error, UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: error)
            }
        }
        .onDisappear { session.cancelDebounce() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text(AppLocalization.format("%lld행 편집", session.row))
                .font(.title2.weight(.semibold))
                .foregroundStyle(VisionCraftUI.primaryText)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button("닫기", action: requestClose)
                .font(.body.weight(.semibold))
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(VisionCraftUI.surfaceVariant, in: Capsule())
                .disabled(isClosing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var fields: some View {
        Form {
            ForEach(session.fields) { field in
                LabeledContent {
                    if field.dropdownValues.isEmpty {
                        TextField("", text: valueBinding(for: field), axis: .vertical)
                            .font(.body.weight(.medium))
                            .foregroundStyle(VisionCraftUI.primaryText)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .scrollDisabled(true)
                            .multilineTextAlignment(.leading)
                            .accessibilityLabel(field.title)
                    } else {
                        Menu {
                            if field.dropdownAllowsBlank {
                                Button("비움") {
                                    session.updateValue("", column: field.column)
                                }
                            }
                            ForEach(field.dropdownValues, id: \.self) { value in
                                Button(value) {
                                    session.updateValue(value, column: field.column)
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(field.value.isEmpty
                                    ? AppLocalization.string("선택") : field.value)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(VisionCraftUI.primaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .accessibilityLabel(field.title)
                        .accessibilityValue(field.value)
                    }
                } label: {
                    Text(field.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(VisionCraftUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(VisionCraftUI.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(VisionCraftUI.background)
        .disabled(isClosing || !session.isEditable)
    }

    private var saveError: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(VisionCraftUI.warning)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("다시 시도") {
                        Task { await session.flush() }
                    }
                    if session.canKeepChangesInDocument {
                        Spacer()
                        Button("나중에 저장") {
                            session.cancelDebounce()
                            dismiss()
                        }
                        .accessibilityHint("편집 내용은 열린 문서에 유지됩니다.")
                    }
                }
                .disabled(session.isSaving)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func valueBinding(for field: ExcelWorkbookViewModel.RowField) -> Binding<String> {
        Binding(
            get: { session.fields.first(where: { $0.id == field.id })?.value ?? "" },
            set: { session.updateValue($0, column: field.column) }
        )
    }

    private func requestClose() {
        guard !isClosing else { return }
        // Commit the keyboard's current composition before taking the final snapshot.
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        isClosing = true
        Task {
            await Task.yield()
            if await session.flush() {
                dismiss()
            } else {
                isClosing = false
            }
        }
    }
}
