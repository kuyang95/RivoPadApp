import Combine
import Foundation

@MainActor
final class ExcelRowEditingSession: ObservableObject {
    typealias Field = ExcelWorkbookViewModel.RowField

    @Published private(set) var fields: [Field]
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?

    let row: Int
    let isEditable: Bool
    private let viewModel: ExcelWorkbookViewModel
    private let sheetID: String?
    private let debounceDelay: Duration
    private var appliedFields: [Field]
    private var savedFields: [Field]
    private var hasAppliedUnsavedChanges = false
    private var debounceTask: Task<Void, Never>?
    private var saveTask: Task<Bool, Never>?

    init(
        row: Int,
        initialFields: [Field],
        viewModel: ExcelWorkbookViewModel,
        debounceDelay: Duration = .milliseconds(650)
    ) {
        self.row = row
        fields = initialFields
        appliedFields = initialFields
        savedFields = initialFields
        self.viewModel = viewModel
        sheetID = viewModel.selectedSheet?.id
        isEditable = viewModel.selectedSheet?.protection.isEnabled == false
        self.debounceDelay = debounceDelay
    }

    var hasPendingChanges: Bool {
        fields != savedFields || hasAppliedUnsavedChanges
    }

    var canKeepChangesInDocument: Bool {
        hasAppliedUnsavedChanges && fields == appliedFields
    }

    func updateValue(_ value: String, column: Int) {
        guard isEditable,
              let index = fields.firstIndex(where: { $0.column == column }),
              fields[index].value != value else { return }
        fields[index].value = value
        errorMessage = nil
        cancelDebounce()
        debounceTask = Task { [weak self, debounceDelay] in
            do {
                try await Task.sleep(for: debounceDelay)
            } catch {
                return
            }
            guard let self else { return }
            self.debounceTask = nil
            _ = await self.flush()
        }
    }

    func cancelDebounce() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    /// The running write owns its snapshot. New typing remains in `fields`
    /// and is drained afterward; cancelling a debounce never cancels a write.
    @discardableResult
    func flush() async -> Bool {
        cancelDebounce()
        if let saveTask {
            return await saveTask.value
        }
        guard hasPendingChanges else { return true }
        let task = Task { await self.savePendingChanges() }
        saveTask = task
        let succeeded = await task.value
        saveTask = nil
        return succeeded
    }

    private func savePendingChanges() async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        while hasPendingChanges {
            guard !viewModel.isSaving,
                  viewModel.selectedSheet?.id == sheetID,
                  viewModel.canEditSelectedSheet else {
                errorMessage = AppLocalization.string("현재 행을 저장할 수 없습니다. 다시 시도해 주세요.")
                return false
            }
            let snapshot = fields
            let previousValues = Dictionary(
                uniqueKeysWithValues: appliedFields.map { ($0.column, $0.value) }
            )
            let changes = snapshot.map { field in
                Field(
                    id: field.id,
                    column: field.column,
                    title: field.title,
                    value: field.value,
                    originalValue: previousValues[field.column],
                    dropdownValues: field.dropdownValues,
                    dropdownAllowsBlank: field.dropdownAllowsBlank
                )
            }
            viewModel.updateRow(row, fields: changes)
            appliedFields = snapshot
            hasAppliedUnsavedChanges = true
            if !(await viewModel.flushAutosave()) {
                errorMessage = viewModel.errorDescription
                    ?? AppLocalization.string("현재 행을 저장할 수 없습니다. 다시 시도해 주세요.")
                return false
            }
            savedFields = snapshot
            hasAppliedUnsavedChanges = false
        }
        return true
    }
}
