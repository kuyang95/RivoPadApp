import RivoDocumentEngine
import Combine
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private nonisolated enum HWPLoadedDocument: Sendable {
    case editable(HWPXDocumentPackage)
    case legacy(HWP5StructuredDocument, Data)
}

@MainActor
final class HWPDocumentViewModel: ObservableObject {
    private struct Mutation {
        let index: Int
        let oldBlock: HWPDocumentBlock
        let newBlock: HWPDocumentBlock
    }

    private struct MutationGroup {
        var mutations: [Mutation] = []
        var before: [HWPDocumentBlock]? = nil
        var after: [HWPDocumentBlock]? = nil
        var oldSelection: String? = nil
        var newSelection: String? = nil
        var beforeSource: HWPTableStructureDocument? = nil
        var afterSource: HWPTableStructureDocument? = nil
        var beforeDirty: Bool? = nil
    }

    @Published private(set) var blocks: [HWPDocumentBlock] = []
    @Published private(set) var pageLayouts: [HWPDocumentPageLayout] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isSaving = false
    @Published private(set) var isLegacyReadOnly = false
    @Published private(set) var isLegacyDocument = false
    @Published private(set) var requiresSaveAs = false
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var status = ""
    @Published private(set) var errorDescription: String?
    @Published var selectedBlockID: String?
    @Published var editorText = ""

    let fileURL: URL
    let originalDocumentID: UUID?

    private var package: HWPXDocumentPackage?
    private var legacyDocument: HWP5StructuredDocument?
    private var legacySourceData: Data?
    private var legacyOriginalBlocks: [HWPDocumentBlock] = []
    private var undoStack: [MutationGroup] = []
    private var redoStack: [MutationGroup] = []
    private var didLoad = false
    private var exportedBlocks: [HWPDocumentBlock]?
    private var fileSnapshot: Data?
    private let writeContents: @Sendable (URL, Data, Data) throws -> Void

    init(
        fileURL: URL,
        originalDocumentID: UUID? = nil,
        writeContents: @escaping @Sendable (URL, Data, Data) throws -> Void = {
            try CoordinatedDocumentFileAccess.replaceContents(
                at: $0, with: $1, expectedContents: $2
            )
        }
    ) {
        self.fileURL = fileURL
        self.originalDocumentID = originalDocumentID
        self.writeContents = writeContents
    }

    var documentName: String {
        fileURL.deletingPathExtension().lastPathComponent
    }

    var selectedBlock: HWPDocumentBlock? {
        guard let selectedBlockID else { return nil }
        return blocks.first { $0.id == selectedBlockID }
    }

    var canEditSelectedBlock: Bool {
        !isSaving && selectedBlock?.isEditable == true && isEditableDocument
    }

    var hasPendingEditorChange: Bool {
        canEditSelectedBlock && selectedBlock?.text != editorText
    }

    var accessibleBlocks: [HWPDocumentBlock] {
        blocks.filter { block in
            block.tableLocation != nil
                || !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !block.images.isEmpty
                || !block.canvasObjects.isEmpty
        }
    }

    var isEditableDocument: Bool {
        package != nil || legacyDocument?.blocks.contains(where: \.isEditable) == true
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        isLoading = true
        errorDescription = nil
        status = AppLocalization.string("한글 문서를 여는 중…")
        do {
            let url = fileURL
            let loaded = try await Task.detached(priority: .userInitiated) {
                let data = try CoordinatedDocumentFileAccess.readData(from: url)
                if data.starts(with: [0x50, 0x4B]) {
                    return HWPLoadedDocument.editable(
                        try HWPXDocumentPackage.load(from: data)
                    )
                }
                return HWPLoadedDocument.legacy(
                    try HWP5StructuredDocumentParser.parse(from: data),
                    data
                )
            }.value
            switch loaded {
            case .editable(let package):
                install(package: package)
                isLegacyReadOnly = false
                isLegacyDocument = false
                requiresSaveAs = false
                status = documentStatus(package.blocks)
            case .legacy(let document, let sourceData):
                install(legacyDocument: document, sourceData: sourceData)
                isLegacyReadOnly = !document.blocks.contains(where: \.isEditable)
                isLegacyDocument = true
                requiresSaveAs = false
                status = legacyDocumentStatus(document)
            }
        } catch {
            errorDescription = error.localizedDescription
            status = AppLocalization.string("한글 문서를 열지 못했습니다.")
        }
        isLoading = false
    }

    func convertLegacyForEditing() async {
        commitEditorChange()
        guard legacyDocument != nil, package == nil, !isSaving else { return }
        let legacyText = blocks.map(\.text).joined(separator: "\n")
        isSaving = true
        errorDescription = nil
        status = AppLocalization.string("HWPX 편집본을 만드는 중…")
        do {
            let package = try await Task.detached(priority: .userInitiated) {
                try HWPXDocumentPackage.load(
                    from: LegacyHWPXConverter.convert(text: legacyText)
                )
            }.value
            install(package: package)
            undoStack.removeAll()
            redoStack.removeAll()
            updateHistoryState()
            isLegacyReadOnly = false
            isLegacyDocument = false
            requiresSaveAs = true
            hasUnsavedChanges = true
            status = AppLocalization.string(
                "HWP 본문을 HWPX 편집본으로 변환했습니다. 원본 HWP는 변경하지 않습니다."
            )
        } catch {
            errorDescription = error.localizedDescription
        }
        isSaving = false
    }

    func selectBlock(_ id: String) {
        guard !isSaving else { return }
        commitEditorChange()
        selectedBlockID = id
        syncEditor()
    }

    func applyTableRowEdits(originalBlocks: [HWPDocumentBlock], texts: [String: String]) throws {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        var mutations: [Mutation] = []
        for original in originalBlocks {
            guard let text = texts[original.id], text != original.text else { continue }
            guard let index = blocks.firstIndex(where: { $0.id == original.id }),
                  blocks[index] == original else { throw WordAIApplyError.staleProposal }
            guard original.tableLocation != nil, original.isEditable else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            let updated = HWPTextRunEditing.replacingText(in: original, with: text)
            mutations.append(Mutation(index: index, oldBlock: original, newBlock: updated))
        }
        guard !mutations.isEmpty else { return }
        apply(MutationGroup(mutations: mutations), forward: true, registeringUndo: true)
        selectedBlockID = mutations.first?.newBlock.id
        syncEditor()
        status = AppLocalization.string("표의 변경 사항을 적용했습니다. 저장하면 파일에 반영됩니다.")
    }

    func commitEditorChange() {
        guard !isSaving, let selectedBlockID,
              let index = blocks.firstIndex(where: { $0.id == selectedBlockID }),
              blocks[index].isEditable,
              isEditableDocument else { return }
        let oldBlock = blocks[index]
        let newBlock = HWPTextRunEditing.replacingText(in: oldBlock, with: editorText)
        guard newBlock != oldBlock else { return }
        commitInlineBlock(newBlock)
        status = isLegacyDocument
            ? AppLocalization.string("문단을 수정했습니다. 저장하면 원본 HWP 파일에 반영됩니다.")
            : AppLocalization.string("문단을 수정했습니다. 저장하면 HWPX 파일에 반영됩니다.")
    }

    @discardableResult
    func replaceText(query: String, matchCase: Bool, replacement: String,
                     selected: HWPTextMatch? = nil) throws -> HWPFindReplace.Proposal {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        guard isEditableDocument else { throw HWPDocumentEditingError.unsupportedEdit }
        commitEditorChange()
        let proposal = try HWPFindReplace.propose(blocks: blocks, query: query, matchCase: matchCase,
            replacement: replacement, selected: selected)
        let changed = Set(proposal.changedIDs)
        let mutations = blocks.indices.compactMap { index -> Mutation? in
            guard changed.contains(blocks[index].id) else { return nil }
            return Mutation(index: index, oldBlock: blocks[index], newBlock: proposal.blocks[index])
        }
        if !mutations.isEmpty {
            apply(MutationGroup(mutations: mutations), forward: true, registeringUndo: true)
            syncEditor()
        }
        return proposal
    }

    func commitInlineBlock(_ edited: HWPDocumentBlock) {
        guard !isSaving, isEditableDocument,
              let index = blocks.firstIndex(where: { $0.id == edited.id }),
              blocks[index].isEditable else { return }
        let original = blocks[index]
        if original != edited {
            let updated = HWPBlockEditing.committing(edited, in: blocks, layouts: pageLayouts)
            apply(MutationGroup(before: blocks, after: updated, oldSelection: selectedBlockID, newSelection: edited.id),
                forward: true, registeringUndo: true)
        }
        selectedBlockID = edited.id
        editorText = edited.text
    }

    func editParagraph(_ draft: HWPDocumentBlock, operation: HWPParagraphEdit) -> HWPParagraphEditResult? {
        let section = Int(draft.sectionPath.lowercased().components(separatedBy: "section").last?
            .replacingOccurrences(of: ".xml", with: "") ?? "0") ?? 0
        guard pageLayouts.contains(where: { $0.sectionIndex == section }),
              !isSaving, isEditableDocument,
              let proposal = HWPParagraphEditing.apply(operation, draft: draft, to: blocks) else { return nil }
        commitInlineBlock(draft)
        let updated = HWPParagraphEditing.reflow(proposal, before: blocks, draft: draft, operation: operation, layouts: pageLayouts)
        apply(MutationGroup(before: blocks, after: updated, oldSelection: draft.id, newSelection: proposal.focusedID),
            forward: true, registeringUndo: true)
        syncEditor()
        return HWPParagraphEditResult(blocks: blocks, focusedID: proposal.focusedID, caret: proposal.caret)
    }

    func undo() {
        guard !isSaving else { return }
        commitEditorChange()
        guard let group = undoStack.popLast() else { return }
        apply(group, forward: false, registeringUndo: false)
        redoStack.append(group)
        updateHistoryState()
        syncEditor()
    }

    private var editingSource: HWPTableStructureDocument? {
        if let package { return .hwpx(package) }
        if let legacyDocument, let legacySourceData { return .hwp(legacyDocument, legacySourceData) }
        return nil
    }

    @discardableResult
    func editTable(_ action: HWPTableStructureAction, selectedID: String, dimensions: HWPTableDimensions? = nil) async throws -> String {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        if action == .resize, dimensions?.widthPoints == nil && dimensions?.heightPoints == nil {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, oldSelection = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true
        errorDescription = nil
        status = AppLocalization.string("표를 수정하는 중…")
        defer { isSaving = false }
        do {
            let result = try await source.editing(action, blocks: before, selectedID: selectedID, dimensions: dimensions)
            apply(MutationGroup(before: before, after: result.document.blocks,
                oldSelection: oldSelection, newSelection: result.focusedID,
                beforeSource: source, afterSource: result.document, beforeDirty: dirty),
                forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string("표의 변경 사항을 적용했습니다. 저장하면 파일에 반영됩니다.")
            return result.focusedID
        } catch {
            status = AppLocalization.string("표를 수정하지 못했습니다.")
            throw error
        }
    }

    @discardableResult
    func insertTable(_ request: HWPTableInsertion.Request) async throws -> String {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, selected = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true; errorDescription = nil; status = AppLocalization.string("표를 삽입하는 중…")
        defer { isSaving = false }
        do {
            let result = try await HWPTableInsertion.applying(request, source: source, drafts: before)
            apply(MutationGroup(before: before, after: result.document.blocks, oldSelection: selected, newSelection: result.focusedID,
                beforeSource: source, afterSource: result.document, beforeDirty: dirty), forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string("표를 삽입했습니다. 저장하면 파일에 반영됩니다.")
            return result.focusedID
        } catch { status = AppLocalization.string("표를 삽입하지 못했습니다."); throw error }
    }

    @discardableResult
    func insertImage(_ request: HWPImageEditing.Request) async throws -> String {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, selected = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true; errorDescription = nil; status = AppLocalization.string("그림을 삽입하는 중…")
        defer { isSaving = false }
        do {
            let result = try await HWPImageEditing.inserting(request, source: source, drafts: before)
            apply(MutationGroup(before: before, after: result.document.blocks,
                oldSelection: selected, newSelection: result.focusedID,
                beforeSource: source, afterSource: result.document, beforeDirty: dirty),
                forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string("그림을 삽입했습니다. 저장하면 파일에 반영됩니다.")
            return result.focusedID
        } catch {
            status = AppLocalization.string("그림을 삽입하지 못했습니다.")
            throw error
        }
    }

    @discardableResult
    func editImage(_ action: HWPImageEditing.Action, target: HWPImageEditing.Target) async throws -> String {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, selected = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true; errorDescription = nil; status = AppLocalization.string("그림을 수정하는 중…")
        defer { isSaving = false }
        do {
            let result = try await HWPImageEditing.applying(action, target: target, source: source, drafts: before)
            apply(MutationGroup(before: before, after: result.document.blocks,
                oldSelection: selected, newSelection: result.focusedID,
                beforeSource: source, afterSource: result.document, beforeDirty: dirty),
                forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string("그림의 변경 사항을 적용했습니다. 저장하면 파일에 반영됩니다.")
            return result.focusedID
        } catch {
            status = AppLocalization.string("그림을 수정하지 못했습니다.")
            throw error
        }
    }

    @discardableResult
    func insertShape(_ request: HWPShapeEditing.Request) async throws -> String {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, selected = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true; errorDescription = nil; status = AppLocalization.string("도형을 삽입하는 중…")
        defer { isSaving = false }
        do {
            let result = try await HWPShapeEditing.inserting(request, source: source, drafts: before)
            apply(MutationGroup(before: before, after: result.document.blocks,
                oldSelection: selected, newSelection: result.focusedID,
                beforeSource: source, afterSource: result.document, beforeDirty: dirty),
                forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string("도형을 삽입했습니다. 저장하면 파일에 반영됩니다.")
            return result.focusedID
        } catch {
            status = AppLocalization.string("도형을 삽입하지 못했습니다.")
            throw error
        }
    }

    @discardableResult
    func editShape(_ action: HWPShapeEditing.Action, target: HWPShapeEditing.Target) async throws -> String {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, selected = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true; errorDescription = nil; status = AppLocalization.string("도형을 수정하는 중…")
        defer { isSaving = false }
        do {
            let result = try await HWPShapeEditing.applying(action, target: target, source: source, drafts: before)
            apply(MutationGroup(before: before, after: result.document.blocks,
                oldSelection: selected, newSelection: result.focusedID,
                beforeSource: source, afterSource: result.document, beforeDirty: dirty),
                forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string("도형의 변경 사항을 적용했습니다. 저장하면 파일에 반영됩니다.")
            return result.focusedID
        } catch {
            status = AppLocalization.string("도형을 수정하지 못했습니다.")
            throw error
        }
    }

    @discardableResult
    func groupShapes(_ request: HWPShapeEditing.GroupRequest) async throws -> String {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, selected = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true; errorDescription = nil; status = AppLocalization.string("도형을 그룹으로 묶는 중…")
        defer { isSaving = false }
        do {
            let result = try await HWPShapeEditing.grouping(request, source: source, drafts: before)
            apply(MutationGroup(before: before, after: result.document.blocks,
                oldSelection: selected, newSelection: result.focusedID,
                beforeSource: source, afterSource: result.document, beforeDirty: dirty),
                forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string("선택한 도형을 그룹으로 묶었습니다. 저장하면 파일에 반영됩니다.")
            return result.focusedID
        } catch {
            status = AppLocalization.string("도형을 그룹으로 묶지 못했습니다.")
            throw error
        }
    }

    @discardableResult
    func arrangeShapes(_ request: HWPShapeEditing.ArrangementRequest) async throws -> String {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, selected = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true; errorDescription = nil; status = AppLocalization.string("도형을 정렬하는 중…")
        defer { isSaving = false }
        do {
            let result = try await HWPShapeEditing.arranging(request, source: source, drafts: before)
            apply(MutationGroup(before: before, after: result.document.blocks,
                oldSelection: selected, newSelection: result.focusedID,
                beforeSource: source, afterSource: result.document, beforeDirty: dirty),
                forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string("선택한 도형의 정렬을 적용했습니다. 저장하면 파일에 반영됩니다.")
            return result.focusedID
        } catch {
            status = AppLocalization.string("도형 정렬을 적용하지 못했습니다.")
            throw error
        }
    }

    @discardableResult
    func matchShapeSizes(_ request: HWPShapeEditing.SizeMatchRequest) async throws -> String {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, selected = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true; errorDescription = nil; status = AppLocalization.string("도형 크기를 맞추는 중…")
        defer { isSaving = false }
        do {
            let result = try await HWPShapeEditing.matchingSizes(request,
                source: source, drafts: before)
            apply(MutationGroup(before: before, after: result.document.blocks,
                oldSelection: selected, newSelection: result.focusedID,
                beforeSource: source, afterSource: result.document, beforeDirty: dirty),
                forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string("선택한 도형의 크기를 맞췄습니다. 저장하면 파일에 반영됩니다.")
            return result.focusedID
        } catch {
            status = AppLocalization.string("도형 크기를 맞추지 못했습니다.")
            throw error
        }
    }

    @discardableResult
    func flipShapes(_ request: HWPShapeEditing.FlipRequest) async throws -> String {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, selected = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true; errorDescription = nil; status = AppLocalization.string("도형을 뒤집는 중…")
        defer { isSaving = false }
        do {
            let result = try await HWPShapeEditing.flipping(request,
                source: source, drafts: before)
            apply(MutationGroup(before: before, after: result.document.blocks,
                oldSelection: selected, newSelection: result.focusedID,
                beforeSource: source, afterSource: result.document, beforeDirty: dirty),
                forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string("선택한 도형을 뒤집었습니다. 저장하면 파일에 반영됩니다.")
            return result.focusedID
        } catch {
            status = AppLocalization.string("도형을 뒤집지 못했습니다.")
            throw error
        }
    }

    @discardableResult
    func batchEditShapes(_ request: HWPShapeEditing.BatchRequest) async throws -> String {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, selected = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true; errorDescription = nil
        status = AppLocalization.string(request.action == .duplicate
            ? "선택한 도형을 복제하는 중…" : "선택한 도형을 삭제하는 중…")
        defer { isSaving = false }
        do {
            let result = try await HWPShapeEditing.batchEditing(request,
                source: source, drafts: before)
            apply(MutationGroup(before: before, after: result.document.blocks,
                oldSelection: selected, newSelection: result.focusedID,
                beforeSource: source, afterSource: result.document, beforeDirty: dirty),
                forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string(request.action == .duplicate
                ? "선택한 도형을 복제했습니다. 저장하면 파일에 반영됩니다."
                : "선택한 도형을 삭제했습니다. 저장하면 파일에 반영됩니다.")
            return result.focusedID
        } catch {
            status = AppLocalization.string(request.action == .duplicate
                ? "도형을 복제하지 못했습니다." : "도형을 삭제하지 못했습니다.")
            throw error
        }
    }

    @discardableResult
    func insertEquation(_ request: HWPEquationEditing.Request) async throws -> String {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, selected = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true; errorDescription = nil; status = AppLocalization.string("수식을 삽입하는 중…")
        defer { isSaving = false }
        do {
            let result = try await HWPEquationEditing.inserting(request, source: source, drafts: before)
            apply(MutationGroup(before: before, after: result.document.blocks,
                oldSelection: selected, newSelection: result.focusedID,
                beforeSource: source, afterSource: result.document, beforeDirty: dirty),
                forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string("수식을 삽입했습니다. 저장하면 파일에 반영됩니다.")
            return result.focusedID
        } catch {
            status = AppLocalization.string("수식을 삽입하지 못했습니다.")
            throw error
        }
    }

    @discardableResult
    func editEquation(_ action: HWPEquationEditing.Action,
                      target: HWPEquationEditing.Target) async throws -> String {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, selected = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true; errorDescription = nil; status = AppLocalization.string("수식을 수정하는 중…")
        defer { isSaving = false }
        do {
            let result = try await HWPEquationEditing.applying(action, target: target,
                source: source, drafts: before)
            apply(MutationGroup(before: before, after: result.document.blocks,
                oldSelection: selected, newSelection: result.focusedID,
                beforeSource: source, afterSource: result.document, beforeDirty: dirty),
                forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string("수식의 변경 사항을 적용했습니다. 저장하면 파일에 반영됩니다.")
            return result.focusedID
        } catch {
            status = AppLocalization.string("수식을 수정하지 못했습니다.")
            throw error
        }
    }

    @discardableResult
    func editTextBox(_ update: HWPTextBoxEditing.Update,
                     target: HWPTextBoxEditing.Target) async throws -> String {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, selected = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true; errorDescription = nil; status = AppLocalization.string("글상자 내용을 수정하는 중…")
        defer { isSaving = false }
        do {
            let result = try await HWPTextBoxEditing.applying(update, target: target,
                source: source, drafts: before)
            apply(MutationGroup(before: before, after: result.document.blocks,
                oldSelection: selected, newSelection: result.focusedID,
                beforeSource: source, afterSource: result.document, beforeDirty: dirty),
                forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string("글상자 내용을 적용했습니다. 저장하면 파일에 반영됩니다.")
            return result.focusedID
        } catch {
            status = AppLocalization.string("글상자 내용을 수정하지 못했습니다.")
            throw error
        }
    }

    @discardableResult
    func insertTextBox(_ request: HWPTextBoxEditing.Request) async throws -> String {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, selected = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true; errorDescription = nil; status = AppLocalization.string("글상자를 삽입하는 중…")
        defer { isSaving = false }
        do {
            let result = try await HWPTextBoxEditing.inserting(request, source: source, drafts: before)
            apply(MutationGroup(before: before, after: result.document.blocks,
                oldSelection: selected, newSelection: result.focusedID,
                beforeSource: source, afterSource: result.document, beforeDirty: dirty),
                forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string("글상자를 삽입했습니다. 저장하면 파일에 반영됩니다.")
            return result.focusedID
        } catch {
            status = AppLocalization.string("글상자를 삽입하지 못했습니다.")
            throw error
        }
    }

    @discardableResult
    func editHyperlink(_ action: HWPHyperlinkEditing.Action,
                       selection: HWPHyperlinkEditing.Selection) async throws -> String {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, selected = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true; errorDescription = nil; status = AppLocalization.string("링크를 수정하는 중…")
        defer { isSaving = false }
        do {
            let result = try await HWPHyperlinkEditing.applying(action, selection: selection,
                source: source, drafts: before)
            apply(MutationGroup(before: before, after: result.document.blocks,
                oldSelection: selected, newSelection: result.focusedID,
                beforeSource: source, afterSource: result.document, beforeDirty: dirty),
                forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string("링크 변경 사항을 적용했습니다. 저장하면 파일에 반영됩니다.")
            return result.focusedID
        } catch {
            status = AppLocalization.string("링크를 수정하지 못했습니다.")
            throw error
        }
    }

    @discardableResult
    func editNote(_ action: HWPNoteEditing.Action) async throws -> String {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, selected = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true; errorDescription = nil; status = AppLocalization.string("각주·미주를 수정하는 중…")
        defer { isSaving = false }
        do {
            let result = try await HWPNoteEditing.applying(action, source: source,
                drafts: before, selectedID: selected)
            apply(MutationGroup(before: before, after: result.document.blocks,
                oldSelection: selected, newSelection: result.focusedID,
                beforeSource: source, afterSource: result.document, beforeDirty: dirty),
                forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string("각주·미주 변경 사항을 적용했습니다. 저장하면 파일에 반영됩니다.")
            return result.focusedID
        } catch {
            status = AppLocalization.string("각주·미주를 수정하지 못했습니다.")
            throw error
        }
    }

    func applyPageSetup(_ request: HWPPageSetupRequest) async throws {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        try HWPPageSetup.validate(request, layouts: pageLayouts)
        guard pageLayouts.contains(where: { request.sections.contains($0.sectionIndex) && !request.settings.matches($0) }) else { return }
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, selected = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true; errorDescription = nil
        status = AppLocalization.string("쪽 설정을 적용하는 중…")
        defer { isSaving = false }
        do {
            let changed = try await HWPPageSetup.applying(request, source: source, drafts: before)
            let focused = before.firstIndex(where: { $0.id == selected }).flatMap { changed.blocks.indices.contains($0) ? changed.blocks[$0].id : nil }
            apply(MutationGroup(before: before, after: changed.blocks, oldSelection: selected, newSelection: focused,
                beforeSource: source, afterSource: changed, beforeDirty: dirty), forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string("쪽 설정을 적용했습니다. 저장하면 파일에 반영됩니다.")
        } catch {
            status = AppLocalization.string("쪽 설정을 적용하지 못했습니다.")
            throw error
        }
    }

    func applyColumnSetup(_ request: HWPColumnSetupRequest) async throws {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        try HWPColumnSetup.validate(request, layouts: pageLayouts)
        guard pageLayouts.contains(where: {
            request.sections.contains($0.sectionIndex) && !request.settings.matches($0)
        }) else { return }
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, selected = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true
        errorDescription = nil
        status = AppLocalization.string("다단 설정을 적용하는 중…")
        defer { isSaving = false }
        do {
            let changed = try await HWPColumnSetup.applying(request, source: source, drafts: before)
            let focused = before.firstIndex(where: { $0.id == selected }).flatMap {
                changed.blocks.indices.contains($0) ? changed.blocks[$0].id : nil
            }
            apply(MutationGroup(before: before, after: changed.blocks,
                oldSelection: selected, newSelection: focused,
                beforeSource: source, afterSource: changed, beforeDirty: dirty),
                forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string("다단 설정을 적용했습니다. 저장하면 파일에 반영됩니다.")
        } catch {
            status = AppLocalization.string("다단 설정을 적용하지 못했습니다.")
            throw error
        }
    }

    func applyPageNumber(_ request: HWPPageNumberRequest) async throws {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        try HWPPageNumberEditing.validate(request, layouts: pageLayouts)
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, selected = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true; errorDescription = nil
        status = AppLocalization.string("쪽 번호를 적용하는 중…")
        defer { isSaving = false }
        do {
            let changed = try await HWPPageNumberEditing.applying(request, source: source, drafts: before)
            let focused = before.firstIndex(where: { $0.id == selected }).flatMap { changed.blocks.indices.contains($0) ? changed.blocks[$0].id : nil }
            apply(MutationGroup(before: before, after: changed.blocks, oldSelection: selected, newSelection: focused,
                beforeSource: source, afterSource: changed, beforeDirty: dirty), forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string("쪽 번호를 적용했습니다. 저장하면 파일에 반영됩니다.")
        } catch {
            status = AppLocalization.string("쪽 번호를 적용하지 못했습니다.")
            throw error
        }
    }

    func headerFooterSelection(_ kind: HWPHeaderFooterKind, section: Int?) -> HWPHeaderFooterEditing.Selection? {
        guard let source = editingSource, let section = section ?? pageLayouts.first?.sectionIndex else { return nil }
        return HWPHeaderFooterEditing.selection(kind: kind, section: section, source: source, drafts: blocks)
    }

    func applyHeaderFooter(_ request: HWPHeaderFooterRequest) async throws {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        guard let source = editingSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let before = blocks, selected = selectedBlockID, dirty = hasUnsavedChanges
        isSaving = true; errorDescription = nil
        status = AppLocalization.string("머리말·꼬리말을 적용하는 중…")
        defer { isSaving = false }
        do {
            let changed = try await HWPHeaderFooterEditing.applying(request, source: source, drafts: before)
            let focused = HWPHeaderFooterEditing.remappedSelection(selected, before: before, after: changed.blocks, request: request)
            apply(MutationGroup(before: before, after: changed.blocks, oldSelection: selected, newSelection: focused,
                beforeSource: source, afterSource: changed, beforeDirty: dirty), forward: true, registeringUndo: true)
            syncEditor()
            status = AppLocalization.string("머리말·꼬리말을 적용했습니다. 저장하면 파일에 반영됩니다.")
        } catch { status = AppLocalization.string("머리말·꼬리말을 적용하지 못했습니다."); throw error }
    }

    func redo() {
        guard !isSaving else { return }
        commitEditorChange()
        guard let group = redoStack.popLast() else { return }
        apply(group, forward: true, registeringUndo: false)
        undoStack.append(group)
        updateHistoryState()
        syncEditor()
    }

    func save() async {
        commitEditorChange()
        guard !isSaving, !requiresSaveAs else { return }
        isSaving = true
        errorDescription = nil
        status = isLegacyDocument
            ? AppLocalization.string("HWP 저장 중…")
            : AppLocalization.string("HWPX 저장 중…")
        do {
            let editedBlocks = blocks
            let destination = fileURL
            let writeContents = writeContents
            guard let expectedContents = fileSnapshot else { throw HWPDocumentEditingError.cannotSave }
            let selectedIndex = selectedBlock.flatMap { selected in
                blocks.firstIndex { $0.id == selected.id }
            }
            if let package {
                let data = try await Task.detached(priority: .userInitiated) {
                    let data = try package.serializedData(applying: editedBlocks)
                    try writeContents(destination, data, expectedContents)
                    return data
                }.value
                let reloaded = try await Task.detached {
                    try HWPXDocumentPackage.load(from: data)
                }.value
                install(package: reloaded, selectedIndex: selectedIndex)
            } else if let sourceData = legacySourceData {
                let originalBlocks = legacyOriginalBlocks
                let result = try await Task.detached(priority: .userInitiated) {
                    let data = try HWP5DocumentRewriter.rewrite(
                        sourceData: sourceData,
                        originalBlocks: originalBlocks,
                        editedBlocks: editedBlocks
                    )
                    try writeContents(destination, data, expectedContents)
                    let document = try HWP5StructuredDocumentParser.parse(from: data)
                    return (data, document)
                }.value
                install(
                    legacyDocument: result.1,
                    sourceData: result.0,
                    selectedIndex: selectedIndex
                )
            } else {
                throw HWPDocumentEditingError.cannotSave
            }
            hasUnsavedChanges = false
            undoStack.removeAll()
            redoStack.removeAll()
            updateHistoryState()
            if let originalDocumentID {
                try? await RecentOriginalDocumentStore.shared.refreshBookmark(
                    id: originalDocumentID,
                    fileURL: fileURL
                )
            }
            status = isLegacyDocument
                ? AppLocalization.string("원본 HWP 형식으로 저장했습니다.")
                : AppLocalization.string("HWPX 문서에 저장했습니다.")
        } catch {
            errorDescription = error.localizedDescription
            status = AppLocalization.format(
                "저장하지 못했습니다: %@",
                error.localizedDescription
            )
        }
        isSaving = false
    }

    func outputSnapshot(opensPrintDialog: Bool = false) throws -> HWPOutputSnapshot {
        guard !isSaving, !isLoading else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        guard !blocks.isEmpty else { throw HWPPDFError.emptyDocument }
        return .init(title: documentName, blocks: blocks, layouts: pageLayouts, opensPrintDialog: opensPrintDialog)
    }

    func exportData() async throws -> Data {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        let editedBlocks = blocks
        let package = package
        let legacySourceData = legacySourceData
        let originalBlocks = legacyOriginalBlocks
        isSaving = true
        defer { isSaving = false }
        let data = try await Task.detached(priority: .userInitiated) {
            if let package {
                return try package.serializedData(applying: editedBlocks)
            }
            if let legacySourceData {
                return try HWP5DocumentRewriter.rewrite(
                    sourceData: legacySourceData, originalBlocks: originalBlocks,
                    editedBlocks: editedBlocks
                )
            }
            throw HWPDocumentEditingError.cannotSave
        }.value
        exportedBlocks = editedBlocks
        return data
    }

    func markExported() {
        commitEditorChange()
        // A copy does not save the open original. Only a converted document
        // without an original destination can become clean after export.
        if requiresSaveAs, exportedBlocks == blocks {
            hasUnsavedChanges = false
        }
        status = AppLocalization.string("문서 복사본을 내보냈습니다.")
    }

    func makeAIRetrievalCatalog(
        for userRequest: String
    ) -> WordAIRetrievalCatalog? {
        commitEditorChange()
        guard isEditableDocument else { return nil }
        let catalog = WordAIRetrievalCatalogBuilder.make(
            documentName: documentName,
            blocks: wordBlocks,
            userRequest: userRequest
        )
        return catalog
    }

    func makeAISnapshot(
        for userRequest: String,
        catalog: WordAIRetrievalCatalog,
        retrievalPlan: WordAIRetrievalPlan?
    ) -> WordAIDocumentSnapshot? {
        commitEditorChange()
        guard isEditableDocument else { return nil }
        return HWPAISource.snapshot(
            documentName: documentName, blocks: blocks, selectedBlockID: selectedBlockID,
            userRequest: userRequest, catalog: catalog, retrievalPlan: retrievalPlan)
    }

    @discardableResult
    func applyAIPlan(_ plan: WordAIValidatedPlan) throws -> String {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        commitEditorChange()
        let mutations = try HWPAISource.replacements(for: plan, in: blocks).map {
            Mutation(index: $0.index, oldBlock: blocks[$0.index], newBlock: $0.block)
        }
        apply(
            MutationGroup(mutations: mutations),
            forward: true,
            registeringUndo: true
        )
        selectedBlockID = mutations.first?.newBlock.id
        syncEditor()
        let message = isLegacyDocument
            ? AppLocalization.format(
                "AI 수정안으로 %lld개 문단을 변경했습니다. 저장하면 HWP 파일에 반영됩니다.",
                mutations.count
            )
            : AppLocalization.format(
                "AI 수정안으로 %lld개 문단을 변경했습니다. 저장하면 HWPX 파일에 반영됩니다.",
                mutations.count
            )
        status = message
        return message
    }

    var formFields: HWPFormFields {
        HWPFormFields.make(document: HWPAccessibleDocument.make(blocks: accessibleBlocks))
    }

    var formFieldNames: [String: String] {
        Dictionary(formFields.fields.flatMap { field in
            field.valueBlockIDs.map { ($0, field.displayName) }
        }, uniquingKeysWith: { first, _ in first })
    }

    private var wordBlocks: [WordDocumentBlock] {
        HWPAISource.blocks(blocks)
    }

    private func apply(
        _ group: MutationGroup,
        forward: Bool,
        registeringUndo: Bool
    ) {
        var group = group
        if registeringUndo, group.beforeDirty == nil { group.beforeDirty = hasUnsavedChanges }
        if let source = forward ? group.afterSource : group.beforeSource {
            switch source {
            case .hwpx(let package): install(package: package, updateFileSnapshot: false)
            case .hwp(let document, let data): install(legacyDocument: document, sourceData: data, updateFileSnapshot: false)
            }
        }
        if forward, registeringUndo, !group.mutations.isEmpty {
            let updated = HWPBlockEditing.replacing(
                group.mutations.map { ($0.index, $0.newBlock) }, in: blocks, layouts: pageLayouts)
            apply(MutationGroup(before: blocks, after: updated, oldSelection: selectedBlockID,
                newSelection: group.mutations.first?.newBlock.id), forward: true, registeringUndo: true)
            return
        }
        if let snapshot = forward ? group.after : group.before { blocks = snapshot }
        if let selection = forward ? group.newSelection : group.oldSelection { selectedBlockID = selection }
        let mutations = forward
            ? group.mutations
            : Array(group.mutations.reversed())
        for mutation in mutations {
            guard blocks.indices.contains(mutation.index) else { continue }
            blocks[mutation.index] = forward
                ? mutation.newBlock
                : mutation.oldBlock
        }
        if registeringUndo {
            undoStack.append(group)
            redoStack.removeAll()
        }
        hasUnsavedChanges = forward ? true : group.beforeDirty ?? true
        updateHistoryState()
    }

    private func updateHistoryState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func install(
        package: HWPXDocumentPackage,
        selectedIndex: Int? = nil,
        updateFileSnapshot: Bool = true
    ) {
        if updateFileSnapshot { fileSnapshot = package.sourceData }
        self.package = package
        isLegacyDocument = false
        isLegacyReadOnly = false
        legacyDocument = nil
        legacySourceData = nil
        legacyOriginalBlocks = []
        blocks = package.blocks
        pageLayouts = package.pageLayouts
        let preferred = selectedIndex.flatMap { index in
            blocks.indices.contains(index) ? blocks[index].id : nil
        }
        selectedBlockID = preferred
            ?? blocks.first(where: { !$0.text.isEmpty })?.id
            ?? blocks.first?.id
        syncEditor()
    }

    private func install(
        legacyDocument: HWP5StructuredDocument,
        sourceData: Data,
        selectedIndex: Int? = nil,
        updateFileSnapshot: Bool = true
    ) {
        if updateFileSnapshot { fileSnapshot = sourceData }
        package = nil
        self.legacyDocument = legacyDocument
        isLegacyDocument = true
        isLegacyReadOnly = !legacyDocument.blocks.contains(where: \.isEditable)
        legacySourceData = sourceData
        legacyOriginalBlocks = legacyDocument.blocks
        blocks = legacyDocument.blocks
        pageLayouts = legacyDocument.pageLayouts
        let preferred = selectedIndex.flatMap { index in
            blocks.indices.contains(index) ? blocks[index].id : nil
        }
        selectedBlockID = preferred
            ?? blocks.first(where: { !$0.text.isEmpty })?.id
            ?? blocks.first?.id
        syncEditor()
    }

    private func selectInitialBlock() {
        selectedBlockID = blocks.first(where: { !$0.text.isEmpty })?.id
            ?? blocks.first?.id
        syncEditor()
    }

    private func syncEditor() {
        editorText = selectedBlock?.text ?? ""
    }

    private func documentStatus(_ blocks: [HWPDocumentBlock]) -> String {
        AppLocalization.format(
            "%lld개 문단 · %lld개 표 셀 · 로컬 HWPX",
            blocks.count,
            blocks.filter { $0.tableLocation != nil }.count
        )
    }

    private func legacyDocumentStatus(_ document: HWP5StructuredDocument) -> String {
        AppLocalization.format(
            "로컬 HWP · %lld개 문단 중 %lld개 편집 가능 · 표 셀 %lld개 · 그림 %lld개 · 도형 %lld개 · 수식 %lld개 · 차트 %lld개 · 주석 %lld개 · 글꼴 %lld개",
            document.blocks.count,
            document.blocks.filter(\.isEditable).count,
            document.tableCellCount,
            document.imageCount,
            document.shapeCount,
            document.equationCount,
            document.chartCount,
            document.footnoteCount + document.endnoteCount,
            document.fontCount
        )
    }
}

struct HWPDocumentExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [VisionCraftFileTypes.hwp, VisionCraftFileTypes.hwpx] }

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private enum HWPDocumentViewMode: String, CaseIterable, Identifiable {
    case originalDocument
    case accessibleDocument

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibleDocument:
            return AppLocalization.string("간편")
        case .originalDocument:
            return AppLocalization.string("원본")
        }
    }
}

private enum HWPOriginalPreviewElement: Identifiable {
    case paragraph(HWPDocumentBlock)
    case table(id: String, index: Int, blocks: [HWPDocumentBlock])

    var id: String {
        switch self {
        case .paragraph(let block):
            return block.id
        case .table(let id, _, _):
            return "hwp-preview-table-\(id)"
        }
    }
}

private struct HWPOriginalTableCell: Identifiable {
    let location: HWPDocumentTableLocation
    let blocks: [HWPDocumentBlock]

    var id: String {
        "\(location.table)-\(location.row)-\(location.column)"
    }
}

private struct HWPOriginalTableRow: Identifiable {
    let row: Int
    let cells: [HWPOriginalTableCell]
    var id: Int { row }
}

private struct HWPOriginalPreviewPage: Identifiable {
    let id: String
    let pageNumber: Int
    let layout: HWPDocumentPageLayout
    let blocks: [HWPDocumentBlock]
}

private struct HWPBoxStyleOverlay: View {
    let style: HWPDocumentBoxStyle

    var body: some View {
        ZStack {
            border(style.top)
                .frame(maxHeight: .infinity, alignment: .top)
            border(style.bottom)
                .frame(maxHeight: .infinity, alignment: .bottom)
            verticalBorder(style.left)
                .frame(maxWidth: .infinity, alignment: .leading)
            verticalBorder(style.right)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func border(_ line: HWPDocumentBorderLine) -> some View {
        if line.isVisible {
            Rectangle()
                .fill(hwpColor(line.colorRGB))
                .frame(height: max(0.5, line.widthPoints))
        }
    }

    @ViewBuilder
    private func verticalBorder(_ line: HWPDocumentBorderLine) -> some View {
        if line.isVisible {
            Rectangle()
                .fill(hwpColor(line.colorRGB))
                .frame(width: max(0.5, line.widthPoints))
        }
    }
}

private func hwpColor(_ rgb: UInt32) -> Color {
    Color(
        red: Double((rgb >> 16) & 0xFF) / 255,
        green: Double((rgb >> 8) & 0xFF) / 255,
        blue: Double(rgb & 0xFF) / 255
    )
}

struct HWPDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: HWPDocumentViewModel
    @StateObject private var fontManager = HWPUserFontManager.shared
    @StateObject private var originalEditor = HWPInlineEditingSession()
    @StateObject private var documentNavigation = HWPDocumentNavigation()
    @State private var isEditingAccessibleDocument = false
    @State private var showsAI = true
    @State private var showsDiscardConfirmation = false
    @State private var isExporting = false
    @State private var exportFile: HWPDocumentExportFile?
    @State private var outputSnapshot: HWPOutputSnapshot?
    @State private var exportError: String?
    @State private var viewMode = HWPDocumentViewMode.originalDocument
    @State private var showsFontManager = false
    @State private var editingTableRow: HWPAccessibleRow?
    @State private var editingImage: HWPImageEditing.Target?
    @State private var selectedImage: HWPImageEditing.Target?
    @State private var editingShape: HWPShapeEditing.Target?
    @State private var selectedShape: HWPShapeEditing.Target?
    @State private var groupingShapeIDs: Set<String> = []
    @State private var groupingOwnerID: String?
    @State private var isSelectingShapeGroup = false
    @State private var insertingEquation: HWPEquationEditing.Selection?
    @State private var editingEquation: HWPEquationEditing.Target?
    @State private var editingTextBox: HWPTextBoxEditing.Target?
    @State private var insertingTextBox: HWPTextBoxEditing.Selection?
    @State private var ribbonTab: HWPRibbonTab = .character
    @State private var ribbonCollapsed = false
    @State private var showsMoreActions = false
    @State private var pendingMoreAction: HWPDocumentAction?
    @ScaledMetric(relativeTo: .subheadline) private var pickerWidth = 184.0

    init(fileURL: URL, originalDocumentID: UUID? = nil) {
        _viewModel = StateObject(
            wrappedValue: HWPDocumentViewModel(
                fileURL: fileURL,
                originalDocumentID: originalDocumentID
            )
        )
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ExcelDocumentLoadingView(
                    message: viewModel.status.isEmpty
                        ? AppLocalization.string("한글 문서를 여는 중…")
                        : viewModel.status
                )
            } else if let error = viewModel.errorDescription,
                      viewModel.blocks.isEmpty {
                ContentUnavailableView(
                    "한글 문서를 열 수 없습니다",
                    systemImage: "doc.badge.ellipsis",
                    description: Text(error)
                )
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top, spacing: 0) { documentHeader }
        .disabled(viewModel.isSaving)
        .visionCraftNavigationScreen()
        .navigationBarBackButtonHidden(true)
        .visionCraftHandlesBackNavigation()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.load()
        }
        .fullScreenCover(
            isPresented: $showsMoreActions,
            onDismiss: performPendingMoreAction
        ) {
            HWPDocumentActionsDialog(
                showsEditingAction: viewMode == .accessibleDocument,
                isEditing: isEditingAccessibleDocument,
                showsAI: showsAI,
                isEditableDocument: viewModel.isEditableDocument,
                isLegacyDocument: viewModel.isLegacyDocument,
                canSave: viewModel.hasUnsavedChanges || viewModel.requiresSaveAs,
                onAction: { action in
                    pendingMoreAction = action
                    setMoreActionsPresented(false)
                },
                onDismiss: { setMoreActionsPresented(false) }
            )
            .presentationBackground(.clear)
        }
        .sheet(item: $outputSnapshot) { snapshot in HWPPDFPreview(snapshot: snapshot) }
        .sheet(isPresented: $showsFontManager) {
            HWPFontManagerView(
                manager: fontManager,
                diagnosticsProvider: {
                    HWPFontDiagnostic.make(blocks: viewModel.blocks)
                }
            )
        }
        .sheet(item: $editingTableRow) { row in
            HWPAccessibleRowEditor(row: row, fieldNames: viewModel.formFieldNames,
                onFocus: viewModel.selectBlock) { texts in
                try viewModel.applyTableRowEdits(originalBlocks: row.blocks, texts: texts)
            }
        }
        .sheet(item: $editingImage) { target in
            HWPImageSizeSheet(target: target,
                onApply: { editImage($0, target: target) },
                onDelete: { editImage(.delete, target: target) })
        }
        .sheet(item: $editingShape) { target in
            HWPShapeEditingSheet(target: target,
                onUpdate: { editShape(.update($0), target: target) },
                onDelete: { editShape(.delete, target: target) },
                onMoveGroupChild: { editShape(.moveGroupChild(offset: $0), target: target) },
                onUngroup: { editShape(.ungroup, target: target) })
        }
        .sheet(item: $insertingEquation) { selection in
            HWPEquationInsertionSheet(selection: selection, onApply: insertEquation)
        }
        .sheet(item: $editingEquation) { target in
            HWPEquationEditingSheet(target: target,
                onUpdate: { editEquation(.update($0), target: target) },
                onDelete: { editEquation(.delete, target: target) })
        }
        .sheet(item: $editingTextBox) { target in
            HWPTextBoxEditingSheet(target: target,
                onApply: { editTextBox($0, target: target) })
        }
        .sheet(item: $insertingTextBox) { selection in
            HWPTextBoxInsertionSheet(selection: selection, onApply: insertTextBox)
        }
        .onChange(of: viewModel.isLegacyDocument) { _, isHWP in
            if isHWP { viewMode = .originalDocument }
        }
        .onChange(of: viewMode) { _, _ in
            originalEditor.finish()
            cancelShapeGrouping()
        }
        .onDisappear { originalEditor.finish() }
        .fileExporter(
            isPresented: $isExporting,
            document: exportFile,
            contentType: viewModel.isLegacyDocument ? VisionCraftFileTypes.hwp : VisionCraftFileTypes.hwpx,
            defaultFilename: "\(viewModel.documentName)-편집본.\(viewModel.isLegacyDocument ? "hwp" : "hwpx")"
        ) { result in
            exportFile = nil
            switch result {
            case .success:
                viewModel.markExported()
            case .failure(let error):
                exportError = error.localizedDescription
            }
        }
        .alert("저장하지 않은 변경 사항", isPresented: $showsDiscardConfirmation) {
            Button("계속 편집", role: .cancel) {}
            Button("변경 사항 버리기", role: .destructive) { dismiss() }
        } message: {
            Text("저장하지 않은 한글 문서 변경 사항이 있습니다.")
        }
        .alert(
            "저장할 수 없습니다",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("확인", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var availableRibbonTabs: [HWPRibbonTab] {
        var tabs: [HWPRibbonTab] = [.character, .paragraph, .insert, .page, .find]
        if let block = originalEditor.activation?.block, HWPCellFormatting.supports(block) {
            tabs.append(.table)
        }
        if selectedImage != nil || selectedShape != nil || isSelectingShapeGroup {
            tabs.append(.object)
        }
        return tabs
    }

    private var activeRibbonTab: HWPRibbonTab {
        availableRibbonTabs.contains(ribbonTab) ? ribbonTab : .character
    }

    private var formattingSection: HWPFormattingToolbar.ToolSection {
        switch activeRibbonTab {
        case .paragraph: .paragraph
        case .table: .table
        default: .character
        }
    }

    private func selectRibbonTab(_ tab: HWPRibbonTab) {
        ribbonTab = tab
        ribbonCollapsed = false
        if tab == .find {
            prepareSearch()
            documentNavigation.showsSearch = true
        } else {
            if documentNavigation.showsSearch { documentNavigation.closeSearch() }
            // A tab changes tools only; keep the editor's selection and composing text.
            originalEditor.restoreFocus()
        }
    }

    private var ribbon: some View {
        VStack(spacing: 0) {
            if !ribbonCollapsed {
                if [.character, .paragraph, .table].contains(activeRibbonTab) {
                    formattingRibbonTools
                } else if activeRibbonTab != .find {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            switch activeRibbonTab {
                            case .insert:
                                insertionRibbonTools
                                Divider().frame(height: 24)
                                shapeGroupingTools
                            case .page: pageRibbonTools
                            case .object: objectRibbonTools
                            default: EmptyView()
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)
                    }
                    .frame(height: 48)
                    .font(.subheadline)
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) { Divider() }
                } else if !documentNavigation.showsSearch {
                    Button("찾기·바꾸기", systemImage: "magnifyingglass") { selectRibbonTab(.find) }
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .padding(.horizontal, 12)
                }
            }
        }
        .background(VisionCraftUI.surface)
        .disabled(viewModel.isSaving)
        .onChange(of: availableRibbonTabs) { _, tabs in
            if !tabs.contains(ribbonTab) { ribbonTab = .character }
        }
        .onChange(of: originalEditor.activation?.block.id) { _, id in
            if id != nil {
                selectedImage = nil
                selectedShape = nil
                if isSelectingShapeGroup { cancelShapeGrouping() }
            }
        }
        .onChange(of: selectedImage?.id) { _, id in
            if id != nil { selectRibbonTab(.object) }
        }
        .onChange(of: selectedShape?.id) { _, id in
            if id != nil { selectRibbonTab(.object) }
        }
        .onChange(of: isSelectingShapeGroup) { _, selecting in
            if selecting { selectRibbonTab(.object) }
        }
        .onChange(of: documentNavigation.showsSearch) { _, showing in
            if showing { ribbonTab = .find; ribbonCollapsed = false }
        }
        .background {
            Button("찾기·바꾸기") { selectRibbonTab(.find) }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
                .accessibilityHidden(true)
        }
    }

    private var formattingRibbonTools: some View {
        HWPFormattingToolbar(section: formattingSection, editor: originalEditor,
            documentFonts: Array(Set(viewModel.blocks.flatMap { $0.presentation.textRuns.compactMap(\.fontName) })).sorted(),
            tableActions: HWPTableStructureEditing.available(blocks: viewModel.blocks,
                selectedID: originalEditor.activation?.block.id, layouts: viewModel.pageLayouts),
            cellActions: HWPTableStructureEditing.availableCells(blocks: viewModel.blocks,
                selectedID: originalEditor.activation?.block.id, layouts: viewModel.pageLayouts),
            onTableAction: { editTable($0) },
            tableSizing: {
                HWPTableSizing.selection(blocks: originalEditor.previewing(viewModel.blocks, layouts: viewModel.pageLayouts),
                    selectedID: originalEditor.activation?.block.id, layouts: viewModel.pageLayouts)
            }, onTableResize: { id, dimensions in editTable(.resize, selectedID: id, dimensions: dimensions) })
    }

    @ViewBuilder private var insertionRibbonTools: some View {
        HWPTableInsertionButton(enabled: originalEditor.tableInsertionSelection(blocks: viewModel.blocks, layouts: viewModel.pageLayouts) != nil,
            selection: { originalEditor.tableInsertionSelection(blocks: viewModel.blocks, layouts: viewModel.pageLayouts, prepare: true) },
            restoreFocus: originalEditor.restoreFocus, onApply: insertTable)
        HWPImageInsertionButton(
            enabled: originalEditor.imageInsertionSelection(blocks: viewModel.blocks, layouts: viewModel.pageLayouts) != nil,
            selection: { originalEditor.imageInsertionSelection(blocks: viewModel.blocks,
                layouts: viewModel.pageLayouts, prepare: true) },
            restoreFocus: originalEditor.restoreFocus,
            onApply: insertImage,
            onError: { exportError = $0 })
        HWPShapeInsertionButton(
            enabled: originalEditor.shapeInsertionSelection(blocks: viewModel.blocks,
                layouts: viewModel.pageLayouts) != nil,
            selection: { originalEditor.shapeInsertionSelection(blocks: viewModel.blocks,
                layouts: viewModel.pageLayouts, prepare: true) },
            restoreFocus: originalEditor.restoreFocus,
            onApply: insertShape)
        HWPTextBoxInsertionButton(
            enabled: originalEditor.shapeInsertionSelection(blocks: viewModel.blocks,
                layouts: viewModel.pageLayouts) != nil,
            selection: { originalEditor.shapeInsertionSelection(blocks: viewModel.blocks,
                layouts: viewModel.pageLayouts, prepare: true) },
            restoreFocus: originalEditor.restoreFocus,
            onSelect: { selection in
                originalEditor.finish()
                insertingTextBox = selection
            })
        HWPEquationInsertionButton(
            enabled: originalEditor.equationInsertionSelection(blocks: viewModel.blocks,
                layouts: viewModel.pageLayouts) != nil,
            selection: { originalEditor.equationInsertionSelection(blocks: viewModel.blocks,
                layouts: viewModel.pageLayouts, prepare: true) },
            restoreFocus: originalEditor.restoreFocus,
            onSelect: { selection in
                originalEditor.finish()
                insertingEquation = selection
            })
        HWPHyperlinkButton(
            enabled: originalEditor.hyperlinkSelection(blocks: viewModel.blocks,
                layouts: viewModel.pageLayouts) != nil,
            selection: { originalEditor.hyperlinkSelection(blocks: viewModel.blocks,
                layouts: viewModel.pageLayouts, prepare: true) },
            restoreFocus: originalEditor.restoreFocus,
            onApply: editHyperlink)
        HWPNoteButton(
            enabled: viewModel.isEditableDocument && !viewModel.blocks.isEmpty,
            selection: {
                let insertion = originalEditor.noteInsertion(blocks: viewModel.blocks,
                    layouts: viewModel.pageLayouts, prepare: true)
                let currentSection = documentNavigation.pages.indices.contains(documentNavigation.currentPageIndex)
                    ? documentNavigation.pages[documentNavigation.currentPageIndex].layout.sectionIndex : nil
                let path = insertion?.sectionPath ?? originalEditor.activation?.block.sectionPath
                    ?? currentSection.flatMap { section in
                        viewModel.blocks.first(where: {
                            HWPPageSetup.sectionIndex($0.sectionPath) == section
                        })?.sectionPath
                    } ?? viewModel.blocks[0].sectionPath
                return HWPNoteEditing.selection(blocks: viewModel.blocks,
                    sectionPath: path, insertion: insertion)
            },
            restoreFocus: originalEditor.restoreFocus,
            onApply: editNote)
    }

    private var pageRibbonTools: some View {
        HWPPageSetupButton(expanded: true, selection: {
            let section = originalEditor.activation.flatMap { HWPPageSetup.sectionIndex($0.block.sectionPath) }
                ?? (documentNavigation.pages.indices.contains(documentNavigation.currentPageIndex)
                    ? documentNavigation.pages[documentNavigation.currentPageIndex].layout.sectionIndex : nil)
            guard let layout = viewModel.pageLayouts.first(where: { $0.sectionIndex == section }) ?? viewModel.pageLayouts.first else { return nil }
            return .init(layout: layout, layouts: viewModel.pageLayouts)
        }, restoreFocus: originalEditor.restoreFocus, onApply: applyPageSetup,
            onApplyNumber: applyPageNumber,
            onApplyColumn: applyColumnSetup,
            headerFooterSelection: { kind in
                let section = originalEditor.activation.flatMap { HWPPageSetup.sectionIndex($0.block.sectionPath) }
                    ?? (documentNavigation.pages.indices.contains(documentNavigation.currentPageIndex)
                        ? documentNavigation.pages[documentNavigation.currentPageIndex].layout.sectionIndex : nil)
                return viewModel.headerFooterSelection(kind, section: section)
            }, onApplyHeaderFooter: applyHeaderFooter,
            canInsertBreak: originalEditor.supportsPageBreak(layouts: viewModel.pageLayouts),
            canRemoveBreak: originalEditor.supportsPageBreak(layouts: viewModel.pageLayouts) && originalEditor.paragraphStyle.pageBreakBefore,
            onInsertBreak: { originalEditor.insertPageBreak() },
            onRemoveBreak: { _ = originalEditor.editParagraph(.removePageBreak) })
            .disabled(!viewModel.isEditableDocument)
    }

    private var shapeGroupingTools: some View {
        HWPShapeGroupingControl(
            isSelecting: isSelectingShapeGroup,
            selectionCount: groupingShapeIDs.count,
            enabled: viewModel.isEditableDocument,
            onStart: beginShapeGrouping,
            onApply: applyShapeGrouping,
            onArrange: applyShapeArrangement,
            onMatchSize: applyShapeSizeMatch,
            onFlip: applyShapeFlip,
            onDuplicate: { applyShapeBatch(.duplicate) },
            onDelete: { applyShapeBatch(.delete) },
            onCancel: cancelShapeGrouping)
    }

    @ViewBuilder private var objectRibbonTools: some View {
        if let image = selectedImage {
            Button("그림 크기·배치", systemImage: "slider.horizontal.3") {
                editingImage = refreshedImageTarget(image)
            }
            .frame(minHeight: 48)
            .accessibilityIdentifier("hwp-ribbon-image-properties")
            Button("삭제", systemImage: "trash", role: .destructive) { editImage(.delete, target: image) }
                .frame(minHeight: 48)
        }
        if let shape = selectedShape {
            Button("위치·크기·스타일", systemImage: "slider.horizontal.3") {
                editingShape = refreshedShapeTarget(shape)
            }
            .frame(minHeight: 48)
            .accessibilityIdentifier("hwp-ribbon-shape-properties")
            if shape.isGroup {
                Button("그룹 해제", systemImage: "square.3.layers.3d") { editShape(.ungroup, target: shape) }
                    .frame(minHeight: 48)
            }
            Button("삭제", systemImage: "trash", role: .destructive) { editShape(.delete, target: shape) }
                .disabled(shape.isGroupChild && !shape.canDeleteGroupChild)
                .frame(minHeight: 48)
        }
        if selectedImage == nil { shapeGroupingTools }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if viewMode == .originalDocument {
                ribbon
                if documentNavigation.showsSearch, !ribbonCollapsed {
                    HWPDocumentSearchBar(navigation: documentNavigation,
                        allowsReplacement: viewModel.isEditableDocument,
                        finishEditing: prepareSearch, onReplace: replaceMatches)
                }
                originalDocumentView
                    .allowsHitTesting(!viewModel.isSaving)
            } else {
                documentList
                if isEditingAccessibleDocument, viewModel.isEditableDocument {
                    Divider()
                    editorPanel
                }
            }
            statusBar
            Divider()
            viewModePicker
            if showsAI, viewModel.isEditableDocument {
                WordAIChatPanel(
                    isAvailable: FirebaseRuntime.isConfigured,
                    catalogProvider: { request in
                        originalEditor.finish()
                        return viewModel.makeAIRetrievalCatalog(for: request)
                    },
                    snapshotProvider: { request, catalog, retrieval in
                        viewModel.makeAISnapshot(
                            for: request,
                            catalog: catalog,
                            retrievalPlan: retrieval
                        )
                    },
                    onApply: { plan in
                        originalEditor.finish()
                        return try viewModel.applyAIPlan(plan)
                    },
                    documentDisplayName: "한글",
                    showsHeader: false,
                    allowsVoiceInput: true,
                    appliesEditsAutomatically: true
                )
            }
        }
    }

    private var viewModePicker: some View {
        VStack(spacing: 6) {
            if viewMode == .originalDocument,
               !originalEditor.overflowingBlockIDs.isEmpty {
                Label(
                    "원래 문단 영역보다 긴 입력이 있습니다. 편집 중 문단 안에서 스크롤하여 확인하세요.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(VisionCraftUI.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    navigationControls
                    Spacer(minLength: 0)
                    compactModePicker
                }
                VStack(spacing: 0) {
                    navigationControls
                    compactModePicker.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(VisionCraftUI.surface)
    }

    @ViewBuilder
    private var navigationControls: some View {
        if viewMode == .originalDocument {
            HWPDocumentNavigationControls(navigation: documentNavigation, showsSearchButton: false) {
                originalEditor.finish()
                viewModel.commitEditorChange()
            }
        }
    }

    private func prepareSearch() {
        originalEditor.finish()
        viewModel.commitEditorChange()
        documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
    }

    private func replaceMatches(_ all: Bool) {
        let selected = documentNavigation.selectedResult?.match
        if !all && selected == nil { return }
        originalEditor.finish()
        do {
            let proposal = try viewModel.replaceText(query: documentNavigation.query,
                matchCase: documentNavigation.matchCase, replacement: documentNavigation.replacement,
                selected: all ? nil : selected)
            documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
            if !all, let selected, proposal.replacementCount > 0 {
                documentNavigation.selectAfterReplacement(of: selected,
                    insertedLength: HWPInlineTextInput.normalized(documentNavigation.replacement).utf16.count)
            }
            var message = AppLocalization.format("%lld개를 바꿨습니다.", proposal.replacementCount)
            if proposal.skippedCount > 0 {
                message += " " + AppLocalization.format("편집할 수 없는 %lld개는 그대로 두었습니다.", proposal.skippedCount)
            }
            documentNavigation.replacementMessage = message
            UIAccessibility.post(notification: .announcement, argument: message)
        } catch {
            documentNavigation.replacementMessage = error.localizedDescription
        }
    }

    private var compactModePicker: some View {
        Picker("보기 방식", selection: $viewMode) {
            ForEach(HWPDocumentViewMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: pickerWidth)
        .frame(minHeight: 48)
    }

    @ViewBuilder
    private var originalDocumentView: some View {
        HWPOriginalDocumentCanvas(
            blocks: originalEditor.previewing(viewModel.blocks, layouts: viewModel.pageLayouts),
            pageLayouts: viewModel.pageLayouts,
            navigation: documentNavigation
        )
        .environment(\.hwpInlineEditing, HWPInlineEditingContext(
            session: viewModel.isEditableDocument ? originalEditor : nil,
            sources: Dictionary(uniqueKeysWithValues: originalEditor.previewing(viewModel.blocks, layouts: viewModel.pageLayouts).map { ($0.id, $0) }),
            orderedBlocks: viewModel.blocks,
            activeID: originalEditor.activation?.block.id,
            onSelect: viewModel.selectBlock,
            onChange: { viewModel.editorText = $0 },
            onCommit: viewModel.commitEditorChange,
            onCommitBlock: viewModel.commitInlineBlock,
            onStructure: viewModel.editParagraph
        ))
        .environment(\.hwpImageObjectEditing, HWPImageObjectEditingContext(
            selectedID: selectedImage?.objectID,
            onSelect: { ownerID, object in
                guard let owner = viewModel.blocks.first(where: { $0.id == ownerID }),
                      let target = HWPImageEditing.target(owner: owner, object: object) else { return }
                originalEditor.finish()
                editingShape = nil
                selectedShape = nil
                if selectedImage?.objectID == target.objectID { editingImage = target }
                selectedImage = target
            },
            onDirectManipulation: applyDirectImageManipulation
        ))
        .environment(\.hwpShapeObjectEditing, HWPShapeObjectEditingContext(
            selectedID: selectedShape?.id,
            groupedSelectionIDs: groupingShapeIDs,
            isSelectingGroup: isSelectingShapeGroup,
            onSelect: { ownerID, object in
                if isSelectingShapeGroup {
                    guard case .shape = object.content else {
                        exportError = "독립 도형만 그룹으로 묶을 수 있습니다."
                        return
                    }
                    if let groupingOwnerID, groupingOwnerID != ownerID {
                        exportError = "같은 문단에 있는 도형을 선택해 주세요."
                        return
                    }
                    groupingOwnerID = ownerID
                    if groupingShapeIDs.contains(object.id) {
                        groupingShapeIDs.remove(object.id)
                        if groupingShapeIDs.isEmpty { groupingOwnerID = nil }
                    }
                    else if groupingShapeIDs.count < 32 { groupingShapeIDs.insert(object.id) }
                    return
                }
                guard let owner = viewModel.blocks.first(where: { $0.id == ownerID }),
                      let target = HWPShapeEditing.target(owner: owner, object: object) else { return }
                originalEditor.finish()
                selectedImage = nil
                if selectedShape?.id == target.id { editingShape = target }
                selectedShape = target
            },
            onSelectChild: { ownerID, object, childIndex in
                guard !isSelectingShapeGroup else {
                    exportError = "그룹 안 도형은 먼저 그룹 해제한 뒤 새 그룹에 넣을 수 있습니다."
                    return
                }
                guard let owner = viewModel.blocks.first(where: { $0.id == ownerID }),
                      let target = HWPShapeEditing.target(owner: owner, object: object,
                        groupChildIndex: childIndex) else { return }
                originalEditor.finish()
                selectedImage = nil
                if selectedShape?.id == target.id { editingShape = target }
                selectedShape = target
            },
            onDirectManipulation: applyDirectShapeManipulation
        ))
        .environment(\.hwpEquationObjectEditing, HWPEquationObjectEditingContext(
            selectedID: editingEquation?.objectID,
            onSelect: { ownerID, object in
                guard let owner = viewModel.blocks.first(where: { $0.id == ownerID }),
                      let target = HWPEquationEditing.target(owner: owner, object: object) else { return }
                originalEditor.finish()
                selectedImage = nil
                selectedShape = nil
                editingEquation = target
            }
        ))
        .environment(\.hwpTextBoxObjectEditing, HWPTextBoxObjectEditingContext(
            selectedID: editingTextBox?.objectID,
            onSelect: { ownerID, object, _ in
                guard let owner = viewModel.blocks.first(where: { $0.id == ownerID }),
                      let target = HWPTextBoxEditing.target(owner: owner, object: object,
                        blocks: viewModel.blocks) else { return }
                originalEditor.finish()
                selectedImage = nil
                selectedShape = nil
                editingTextBox = target
            }
        ))
        .overlay(alignment: .topLeading) {
            HWPShapeKeyboardNudgeReceiver(
                isActive: (selectedImage != nil
                    || (selectedShape != nil && selectedShape?.groupChildIndex == nil))
                    && editingImage == nil && editingShape == nil
                    && !isSelectingShapeGroup,
                onNudge: nudgeSelectedObject
            )
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
        }
        .id(fontManager.revision)
    }

    private func editTable(_ action: HWPTableStructureAction, selectedID: String? = nil, dimensions: HWPTableDimensions? = nil) {
        guard let id = selectedID ?? originalEditor.activation?.block.id else { return }
        originalEditor.finish()
        Task { @MainActor in
            do {
                let focused = try await viewModel.editTable(action, selectedID: id, dimensions: dimensions)
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                if let page = documentNavigation.pages.firstIndex(where: { $0.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == focused } }) {
                    documentNavigation.goToPage(page)
                }
                guard let block = viewModel.blocks.first(where: { $0.id == focused }) else { return }
                originalEditor.begin(block: block, at: .zero, onSelect: viewModel.selectBlock,
                    onChange: { viewModel.editorText = $0 }, onCommit: viewModel.commitEditorChange,
                    onCommitBlock: viewModel.commitInlineBlock, onStructure: viewModel.editParagraph,
                    listContext: viewModel.blocks, caretOffset: 0)
            } catch { exportError = error.localizedDescription }
        }
    }

    private func insertTable(_ request: HWPTableInsertion.Request) {
        originalEditor.finish()
        Task { @MainActor in
            do {
                let focused = try await viewModel.insertTable(request)
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                if let page = documentNavigation.pages.firstIndex(where: { $0.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == focused } }) {
                    documentNavigation.goToPage(page)
                }
                guard let block = viewModel.blocks.first(where: { $0.id == focused }) else { return }
                originalEditor.begin(block: block, at: .zero, onSelect: viewModel.selectBlock,
                    onChange: { viewModel.editorText = $0 }, onCommit: viewModel.commitEditorChange,
                    onCommitBlock: viewModel.commitInlineBlock, onStructure: viewModel.editParagraph,
                    listContext: viewModel.blocks, caretOffset: 0)
            } catch { exportError = error.localizedDescription }
        }
    }

    private func insertImage(_ request: HWPImageEditing.Request) {
        originalEditor.finish()
        Task { @MainActor in
            do {
                let focused = try await viewModel.insertImage(request)
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                if let page = documentNavigation.pages.firstIndex(where: {
                    $0.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == focused }
                }) { documentNavigation.goToPage(page) }
            } catch { exportError = error.localizedDescription }
        }
    }

    private func editImage(_ action: HWPImageEditing.Action, target: HWPImageEditing.Target) {
        originalEditor.finish()
        Task { @MainActor in
            do {
                let focused = try await viewModel.editImage(action, target: target)
                editingImage = nil
                selectedImage = refreshedImageTarget(target)
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                if let page = documentNavigation.pages.firstIndex(where: {
                    $0.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == focused }
                }) { documentNavigation.goToPage(page) }
            } catch { exportError = error.localizedDescription }
        }
    }

    private func insertShape(_ request: HWPShapeEditing.Request) {
        originalEditor.finish()
        Task { @MainActor in
            do {
                let focused = try await viewModel.insertShape(request)
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                if let page = documentNavigation.pages.firstIndex(where: {
                    $0.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == focused }
                }) { documentNavigation.goToPage(page) }
            } catch { exportError = error.localizedDescription }
        }
    }

    private func editShape(_ action: HWPShapeEditing.Action, target: HWPShapeEditing.Target) {
        originalEditor.finish()
        Task { @MainActor in
            do {
                let focused = try await viewModel.editShape(action, target: target)
                editingShape = nil
                if case .delete = action {
                    selectedShape = nil
                } else if case .moveGroupChild(let offset) = action,
                          let childIndex = target.groupChildIndex {
                    selectedShape = refreshedShapeTarget(target, childIndex: childIndex + offset)
                } else {
                    selectedShape = refreshedShapeTarget(target)
                }
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                if let page = documentNavigation.pages.firstIndex(where: {
                    $0.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == focused }
                }) { documentNavigation.goToPage(page) }
            } catch { exportError = error.localizedDescription }
        }
    }

    private func applyDirectShapeManipulation(_ ownerID: String,
                                              _ object: HWPDocumentCanvasObject,
                                              _ operation: HWPShapeEditing.DirectManipulation) {
        guard let owner = viewModel.blocks.first(where: { $0.id == ownerID }),
              let target = HWPShapeEditing.target(owner: owner, object: object),
              let layout = HWPShapeEditing.directLayout(operation, target: target) else { return }
        originalEditor.finish()
        Task { @MainActor in
            do {
                let focused = try await viewModel.editShape(.update(layout), target: target)
                selectedShape = refreshedShapeTarget(target)
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                if let page = documentNavigation.pages.firstIndex(where: {
                    $0.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == focused }
                }) { documentNavigation.goToPage(page) }
            } catch { exportError = error.localizedDescription }
        }
    }

    private func applyDirectImageManipulation(_ ownerID: String,
                                              _ object: HWPDocumentCanvasObject,
                                              _ operation: HWPImageEditing.DirectManipulation) {
        guard let owner = viewModel.blocks.first(where: { $0.id == ownerID }),
              let target = HWPImageEditing.target(owner: owner, object: object),
              let update = HWPImageEditing.directUpdate(operation, target: target) else { return }
        originalEditor.finish()
        Task { @MainActor in
            do {
                let focused = try await viewModel.editImage(.update(update.crop, update.dimensions,
                    update.presentation, update.appearance), target: target)
                selectedImage = refreshedImageTarget(target)
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                if let page = documentNavigation.pages.firstIndex(where: {
                    $0.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == focused }
                }) { documentNavigation.goToPage(page) }
            } catch { exportError = error.localizedDescription }
        }
    }

    private func nudgeSelectedObject(_ deltaX: Double, _ deltaY: Double) {
        if let selectedImage,
           let owner = viewModel.blocks.first(where: { $0.id == selectedImage.ownerID }),
           let object = owner.canvasObjects.first(where: { $0.id == selectedImage.objectID }) {
            applyDirectImageManipulation(owner.id, object,
                .move(deltaX: deltaX, deltaY: deltaY))
            return
        }
        guard let selectedShape, selectedShape.groupChildIndex == nil,
              let owner = viewModel.blocks.first(where: { $0.id == selectedShape.ownerID }),
              let object = owner.canvasObjects.first(where: { $0.id == selectedShape.objectID }) else {
            return
        }
        applyDirectShapeManipulation(owner.id, object,
            .move(deltaX: deltaX, deltaY: deltaY))
    }

    private func refreshedShapeTarget(_ previous: HWPShapeEditing.Target,
                                      childIndex: Int? = nil)
        -> HWPShapeEditing.Target? {
        guard let owner = viewModel.blocks.first(where: { $0.id == previous.ownerID }),
              let object = owner.canvasObjects.first(where: { $0.id == previous.objectID }) else {
            return nil
        }
        return HWPShapeEditing.target(owner: owner, object: object,
            groupChildIndex: childIndex ?? previous.groupChildIndex)
    }

    private func refreshedImageTarget(_ previous: HWPImageEditing.Target)
        -> HWPImageEditing.Target? {
        guard let owner = viewModel.blocks.first(where: { $0.id == previous.ownerID }),
              let object = owner.canvasObjects.first(where: { $0.id == previous.objectID }) else {
            return nil
        }
        return HWPImageEditing.target(owner: owner, object: object)
    }

    private func beginShapeGrouping() {
        originalEditor.finish()
        editingShape = nil
        selectedImage = nil
        selectedShape = nil
        groupingShapeIDs.removeAll()
        groupingOwnerID = nil
        isSelectingShapeGroup = true
    }

    private func cancelShapeGrouping() {
        groupingShapeIDs.removeAll()
        groupingOwnerID = nil
        isSelectingShapeGroup = false
    }

    private func applyShapeGrouping() {
        guard let ownerID = groupingOwnerID, groupingShapeIDs.count >= 2 else { return }
        let request = HWPShapeEditing.GroupRequest(ownerID: ownerID,
            objectIDs: Array(groupingShapeIDs))
        originalEditor.finish()
        Task { @MainActor in
            do {
                let focused = try await viewModel.groupShapes(request)
                cancelShapeGrouping()
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                if let page = documentNavigation.pages.firstIndex(where: {
                    $0.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == focused }
                }) { documentNavigation.goToPage(page) }
            } catch { exportError = error.localizedDescription }
        }
    }

    private func applyShapeArrangement(_ arrangement: HWPShapeEditing.Arrangement) {
        guard let ownerID = groupingOwnerID,
              groupingShapeIDs.count >= arrangement.minimumSelectionCount else { return }
        let request = HWPShapeEditing.ArrangementRequest(ownerID: ownerID,
            objectIDs: Array(groupingShapeIDs), arrangement: arrangement)
        originalEditor.finish()
        Task { @MainActor in
            do {
                let focused = try await viewModel.arrangeShapes(request)
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                if let page = documentNavigation.pages.firstIndex(where: {
                    $0.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == focused }
                }) { documentNavigation.goToPage(page) }
            } catch { exportError = error.localizedDescription }
        }
    }

    private func applyShapeSizeMatch(_ match: HWPShapeEditing.SizeMatch) {
        guard let ownerID = groupingOwnerID, groupingShapeIDs.count >= 2 else { return }
        let request = HWPShapeEditing.SizeMatchRequest(ownerID: ownerID,
            objectIDs: Array(groupingShapeIDs), match: match)
        originalEditor.finish()
        Task { @MainActor in
            do {
                let focused = try await viewModel.matchShapeSizes(request)
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                if let page = documentNavigation.pages.firstIndex(where: {
                    $0.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == focused }
                }) { documentNavigation.goToPage(page) }
            } catch { exportError = error.localizedDescription }
        }
    }

    private func applyShapeFlip(_ flip: HWPShapeEditing.Flip) {
        guard let ownerID = groupingOwnerID, !groupingShapeIDs.isEmpty else { return }
        let request = HWPShapeEditing.FlipRequest(ownerID: ownerID,
            objectIDs: Array(groupingShapeIDs), flip: flip)
        originalEditor.finish()
        Task { @MainActor in
            do {
                let focused = try await viewModel.flipShapes(request)
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                if let page = documentNavigation.pages.firstIndex(where: {
                    $0.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == focused }
                }) { documentNavigation.goToPage(page) }
            } catch { exportError = error.localizedDescription }
        }
    }

    private func applyShapeBatch(_ action: HWPShapeEditing.BatchAction) {
        guard let ownerID = groupingOwnerID, groupingShapeIDs.count >= 2 else { return }
        let request = HWPShapeEditing.BatchRequest(ownerID: ownerID,
            objectIDs: Array(groupingShapeIDs), action: action)
        originalEditor.finish()
        Task { @MainActor in
            do {
                let focused = try await viewModel.batchEditShapes(request)
                cancelShapeGrouping()
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                if let page = documentNavigation.pages.firstIndex(where: {
                    $0.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == focused }
                }) { documentNavigation.goToPage(page) }
            } catch { exportError = error.localizedDescription }
        }
    }

    private func insertEquation(_ request: HWPEquationEditing.Request) {
        originalEditor.finish()
        Task { @MainActor in
            do {
                let focused = try await viewModel.insertEquation(request)
                insertingEquation = nil
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                if let page = documentNavigation.pages.firstIndex(where: {
                    $0.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == focused }
                }) { documentNavigation.goToPage(page) }
            } catch { exportError = error.localizedDescription }
        }
    }

    private func editEquation(_ action: HWPEquationEditing.Action,
                              target: HWPEquationEditing.Target) {
        originalEditor.finish()
        Task { @MainActor in
            do {
                let focused = try await viewModel.editEquation(action, target: target)
                editingEquation = nil
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                if let page = documentNavigation.pages.firstIndex(where: {
                    $0.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == focused }
                }) { documentNavigation.goToPage(page) }
            } catch { exportError = error.localizedDescription }
        }
    }

    private func editTextBox(_ update: HWPTextBoxEditing.Update,
                             target: HWPTextBoxEditing.Target) {
        originalEditor.finish()
        Task { @MainActor in
            do {
                _ = try await viewModel.editTextBox(update, target: target)
                editingTextBox = nil
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
            } catch { exportError = error.localizedDescription }
        }
    }

    private func insertTextBox(_ request: HWPTextBoxEditing.Request) {
        originalEditor.finish()
        Task { @MainActor in
            do {
                let focused = try await viewModel.insertTextBox(request)
                insertingTextBox = nil
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                if let page = documentNavigation.pages.firstIndex(where: {
                    $0.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == focused }
                }) { documentNavigation.goToPage(page) }
            } catch { exportError = error.localizedDescription }
        }
    }

    private func editHyperlink(_ action: HWPHyperlinkEditing.Action,
                               selection: HWPHyperlinkEditing.Selection) {
        originalEditor.finish()
        Task { @MainActor in
            do {
                let focused = try await viewModel.editHyperlink(action, selection: selection)
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                if let page = documentNavigation.pages.firstIndex(where: {
                    $0.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == focused }
                }) { documentNavigation.goToPage(page) }
            } catch { exportError = error.localizedDescription }
        }
    }

    private func editNote(_ action: HWPNoteEditing.Action) {
        originalEditor.finish()
        Task { @MainActor in
            do {
                let focused = try await viewModel.editNote(action)
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                if let page = documentNavigation.pages.firstIndex(where: {
                    $0.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == focused }
                }) { documentNavigation.goToPage(page) }
            } catch { exportError = error.localizedDescription }
        }
    }

    private func applyPageSetup(_ request: HWPPageSetupRequest) {
        let wasEditing = originalEditor.activation != nil
        let caret = originalEditor.selectedRange.location
        originalEditor.finish()
        Task { @MainActor in
            do {
                try await viewModel.applyPageSetup(request)
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                documentNavigation.setZoom(nil)
                if wasEditing, let block = viewModel.selectedBlock, block.isEditable {
                    originalEditor.begin(block: block, at: .zero, onSelect: viewModel.selectBlock,
                        onChange: { viewModel.editorText = $0 }, onCommit: viewModel.commitEditorChange,
                        onCommitBlock: viewModel.commitInlineBlock, onStructure: viewModel.editParagraph,
                        listContext: viewModel.blocks, caretOffset: min(caret, block.text.utf16.count))
                }
            } catch { exportError = error.localizedDescription }
        }
    }

    private func applyPageNumber(_ request: HWPPageNumberRequest) {
        let wasEditing = originalEditor.activation != nil
        let caret = originalEditor.selectedRange.location
        originalEditor.finish()
        Task { @MainActor in
            do {
                try await viewModel.applyPageNumber(request)
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                if wasEditing, let block = viewModel.selectedBlock, block.isEditable {
                    originalEditor.begin(block: block, at: .zero, onSelect: viewModel.selectBlock,
                        onChange: { viewModel.editorText = $0 }, onCommit: viewModel.commitEditorChange,
                        onCommitBlock: viewModel.commitInlineBlock, onStructure: viewModel.editParagraph,
                        listContext: viewModel.blocks, caretOffset: min(caret, block.text.utf16.count))
                }
            } catch { exportError = error.localizedDescription }
        }
    }

    private func applyColumnSetup(_ request: HWPColumnSetupRequest) {
        let wasEditing = originalEditor.activation != nil
        let caret = originalEditor.selectedRange.location
        originalEditor.finish()
        Task { @MainActor in
            do {
                try await viewModel.applyColumnSetup(request)
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                documentNavigation.setZoom(nil)
                if wasEditing, let block = viewModel.selectedBlock, block.isEditable {
                    originalEditor.begin(block: block, at: .zero,
                        onSelect: viewModel.selectBlock,
                        onChange: { viewModel.editorText = $0 },
                        onCommit: viewModel.commitEditorChange,
                        onCommitBlock: viewModel.commitInlineBlock,
                        onStructure: viewModel.editParagraph,
                        listContext: viewModel.blocks,
                        caretOffset: min(caret, block.text.utf16.count))
                }
            } catch { exportError = error.localizedDescription }
        }
    }

    private func applyHeaderFooter(_ request: HWPHeaderFooterRequest) {
        let wasEditing = originalEditor.activation != nil
        let caret = originalEditor.selectedRange.location
        originalEditor.finish()
        Task { @MainActor in
            do {
                try await viewModel.applyHeaderFooter(request)
                documentNavigation.update(blocks: viewModel.blocks, layouts: viewModel.pageLayouts)
                if wasEditing, let block = viewModel.selectedBlock, block.isEditable {
                    originalEditor.begin(block: block, at: .zero, onSelect: viewModel.selectBlock,
                        onChange: { viewModel.editorText = $0 }, onCommit: viewModel.commitEditorChange,
                        onCommitBlock: viewModel.commitInlineBlock, onStructure: viewModel.editParagraph,
                        listContext: viewModel.blocks, caretOffset: min(caret, block.text.utf16.count))
                }
            } catch { exportError = error.localizedDescription }
        }
    }

    private var originalPages: [HWPOriginalPreviewPage] {
        let layouts = viewModel.pageLayouts.isEmpty
            ? [HWPDocumentPageLayout.standard()]
            : viewModel.pageLayouts
        var result: [HWPOriginalPreviewPage] = []
        var pageNumber = 1

        for layout in layouts {
            let sectionBlocks = viewModel.blocks.filter {
                sectionIndex(for: $0) == layout.sectionIndex
            }
            let chrome = sectionBlocks.filter { $0.region.kind != .body }
            let body = sectionBlocks.filter { $0.region.kind == .body }
            var bodyPages: [[HWPDocumentBlock]] = [[]]
            for block in body {
                if block.presentation.pageBreakBefore,
                   bodyPages.last?.isEmpty == false {
                    bodyPages.append([])
                }
                bodyPages[bodyPages.count - 1].append(block)
            }
            if bodyPages.isEmpty { bodyPages = [[]] }

            for (index, pageBody) in bodyPages.enumerated() {
                let includesNotes = index == bodyPages.count - 1
                let pageChrome = chrome.filter { block in
                    switch block.region.kind {
                    case .background:
                        return true
                    case .header, .footer:
                        return applies(block.region.scope, to: pageNumber)
                    case .footnote, .endnote:
                        return includesNotes
                    case .body:
                        return false
                    }
                }
                result.append(
                    HWPOriginalPreviewPage(
                        id: "hwp-page-\(layout.sectionIndex)-\(index)",
                        pageNumber: pageNumber,
                        layout: layout,
                        blocks: pageBody + pageChrome
                    )
                )
                pageNumber += 1
            }
        }
        if result.isEmpty {
            result.append(
                HWPOriginalPreviewPage(
                    id: "hwp-page-fallback",
                    pageNumber: 1,
                    layout: .standard(),
                    blocks: viewModel.blocks
                )
            )
        }
        return result
    }

    private func originalPageView(_ page: HWPOriginalPreviewPage) -> some View {
        let layout = page.layout
        let scale = min(1, 720 / max(layout.widthPoints, 1))
        let pageWidth = layout.widthPoints * scale
        let pageHeight = layout.heightPoints * scale
        let leadingPadding = max(20, layout.leftMarginPoints * scale)
        let trailingPadding = max(20, layout.rightMarginPoints * scale)
        // 표가 쪽 밖으로 넘치지 않도록 본문 폭을 표 열 너비 계산에 넘긴다.
        let contentWidth = max(160, pageWidth - leadingPadding - trailingPadding)
        return VStack(alignment: .leading, spacing: 0) {
            if !layout.hidesHeader {
                originalRegion(
                    .header,
                    blocks: page.blocks,
                    label: AppLocalization.string("머리말"),
                    contentWidth: contentWidth
                )
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(originalPreviewElements(for: .body, in: page.blocks)) { element in
                    originalPreviewView(element, contentWidth: contentWidth)
                }
            }
            .padding(.top, max(8, layout.topMarginPoints * scale * 0.35))

            Spacer(minLength: 28)

            originalNotes(
                kind: .footnote,
                blocks: page.blocks,
                style: layout.footnoteStyle,
                label: AppLocalization.string("각주"),
                contentWidth: contentWidth
            )
            originalNotes(
                kind: .endnote,
                blocks: page.blocks,
                style: layout.endnoteStyle,
                label: AppLocalization.string("미주"),
                contentWidth: contentWidth
            )
            if !layout.hidesFooter {
                originalRegion(
                    .footer,
                    blocks: page.blocks,
                    label: AppLocalization.string("꼬리말"),
                    contentWidth: contentWidth
                )
            }
        }
        .foregroundStyle(.black)
        .padding(.leading, leadingPadding)
        .padding(.trailing, trailingPadding)
        .padding(.top, max(20, layout.headerMarginPoints * scale))
        .padding(.bottom, max(20, layout.footerMarginPoints * scale))
        .frame(width: pageWidth, alignment: .topLeading)
        .frame(minHeight: pageHeight, alignment: .topLeading)
        .background(
            layout.pageStyle?.backgroundColorRGB.map(hwpColor) ?? .white
        )
        .overlay {
            if let pageStyle = layout.pageStyle {
                HWPBoxStyleOverlay(style: pageStyle)
            }
        }
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            AppLocalization.format("한글 원본 형태 미리보기 · %lld쪽", page.pageNumber)
        )
    }

    private func sectionIndex(for block: HWPDocumentBlock) -> Int {
        let digits = block.sectionPath.filter(\.isNumber)
        return Int(digits) ?? 0
    }

    private func applies(
        _ scope: HWPDocumentHeaderFooterScope?,
        to pageNumber: Int
    ) -> Bool {
        switch scope ?? .bothPages {
        case .bothPages:
            return true
        case .evenPages:
            return pageNumber.isMultiple(of: 2)
        case .oddPages:
            return !pageNumber.isMultiple(of: 2)
        }
    }

    private func originalPreviewElements(
        for kind: HWPDocumentRegionKind,
        in blocks: [HWPDocumentBlock]
    ) -> [HWPOriginalPreviewElement] {
        let regionBlocks = blocks.filter { $0.region.kind == kind }
        var elements: [HWPOriginalPreviewElement] = []
        var index = 0
        while index < regionBlocks.count {
            let block = regionBlocks[index]
            guard let table = block.tableLocation?.table else {
                elements.append(.paragraph(block))
                index += 1
                continue
            }
            let firstID = block.id
            var tableBlocks: [HWPDocumentBlock] = []
            while index < regionBlocks.count,
                  regionBlocks[index].tableLocation?.table == table {
                tableBlocks.append(regionBlocks[index])
                index += 1
            }
            elements.append(
                .table(id: firstID, index: table, blocks: tableBlocks)
            )
        }
        return elements
    }

    @ViewBuilder
    private func originalRegion(
        _ kind: HWPDocumentRegionKind,
        blocks: [HWPDocumentBlock],
        label: String,
        contentWidth: CGFloat
    ) -> some View {
        let elements = originalPreviewElements(for: kind, in: blocks)
        if !elements.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(elements) { element in
                    originalPreviewView(element, contentWidth: contentWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func originalNotes(
        kind: HWPDocumentRegionKind,
        blocks: [HWPDocumentBlock],
        style: HWPDocumentNoteStyle?,
        label: String,
        contentWidth: CGFloat
    ) -> some View {
        let elements = originalPreviewElements(for: kind, in: blocks)
        if !elements.isEmpty {
            VStack(alignment: .leading, spacing: style?.noteSpacingPoints ?? 5) {
                let separator = style?.separator
                    ?? HWPDocumentBorderLine(kind: 1, widthPoints: 0.7, colorRGB: 0)
                Rectangle()
                    .fill(hwpColor(separator.colorRGB))
                    .frame(
                        width: max(48, style?.separatorLengthPoints ?? 120),
                        height: max(0.5, separator.widthPoints)
                    )
                    .padding(.top, style?.separatorMarginTopPoints ?? 8)
                    .padding(.bottom, style?.separatorMarginBottomPoints ?? 5)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.gray)
                ForEach(elements) { element in
                    originalPreviewView(element, contentWidth: contentWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func originalPreviewView(
        _ element: HWPOriginalPreviewElement,
        contentWidth: CGFloat
    ) -> some View {
        switch element {
        case .paragraph(let block):
            originalBlockView(block)
        case .table(_, let index, let blocks):
            originalTableView(
                index: index,
                blocks: blocks,
                contentWidth: contentWidth
            )
        }
    }

    /// 표를 가로 스크롤 없이 본문 폭 안에 맞춰 그린다.
    /// 문서에 셀 너비가 있으면 그 비율을, 없으면 열별 글자 수 비율로 열 너비를 정한다.
    private func originalTableView(
        index: Int,
        blocks: [HWPDocumentBlock],
        contentWidth: CGFloat
    ) -> some View {
        let rows = originalTableRows(blocks)
        let columnWidths = originalTableColumnWidths(
            rows: rows,
            contentWidth: contentWidth
        )
        return VStack(alignment: .leading, spacing: 6) {
            Text(AppLocalization.format("표 %lld", index + 1))
                .font(.caption.weight(.semibold))
                .foregroundStyle(VisionCraftUI.secondaryText)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(row.cells) { cell in
                            originalTableCellView(
                                cell,
                                width: originalTableCellWidth(
                                    for: cell.location,
                                    columnWidths: columnWidths
                                )
                            )
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: contentWidth, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalization.format("표 %lld", index + 1))
    }

    private static let originalTableMinimumColumnWidth: CGFloat = 40
    private static let originalTableWeightCap = 36

    private func originalTableColumnWidths(
        rows: [HWPOriginalTableRow],
        contentWidth: CGFloat
    ) -> [CGFloat] {
        let columnCount = rows.reduce(0) { partial, row in
            max(
                partial,
                row.cells.reduce(0) {
                    max($0, $1.location.column + $1.location.columnSpan)
                }
            )
        }
        guard columnCount > 0 else { return [] }

        var pointWidths = [CGFloat?](repeating: nil, count: columnCount)
        var weights = [CGFloat](repeating: 4, count: columnCount)
        for row in rows {
            for cell in row.cells where cell.location.columnSpan == 1 {
                let column = min(max(cell.location.column, 0), columnCount - 1)
                if let width = cell.location.cellWidthPoints, width > 0 {
                    pointWidths[column] = max(pointWidths[column] ?? 0, CGFloat(width))
                }
                let longestLine = cell.blocks
                    .flatMap { $0.text.split(separator: "\n", omittingEmptySubsequences: false) }
                    .map(\.count)
                    .max() ?? 0
                weights[column] = max(
                    weights[column],
                    CGFloat(4 + min(longestLine, Self.originalTableWeightCap))
                )
            }
        }

        let ratios: [CGFloat]
        if pointWidths.allSatisfy({ $0 != nil }) {
            ratios = pointWidths.map { $0 ?? 1 }
        } else {
            ratios = weights
        }
        let total = max(ratios.reduce(0, +), 1)
        let minimum = min(
            Self.originalTableMinimumColumnWidth,
            contentWidth / CGFloat(columnCount)
        )
        var widths = ratios.map { max(minimum, contentWidth * $0 / total) }
        // 최소 너비 보정으로 넘친 만큼 넓은 열에서 덜어낸다.
        let overflow = widths.reduce(0, +) - contentWidth
        if overflow > 0 {
            let flexible = widths.enumerated().filter { $0.element > minimum }
            let flexibleTotal = flexible.reduce(0) { $0 + ($1.element - minimum) }
            if flexibleTotal > 0 {
                for (offset, width) in flexible {
                    widths[offset] = width - overflow * (width - minimum) / flexibleTotal
                }
            }
        }
        return widths.map { ($0 * 2).rounded(.down) / 2 }
    }

    private func originalTableCellWidth(
        for location: HWPDocumentTableLocation,
        columnWidths: [CGFloat]
    ) -> CGFloat {
        guard !columnWidths.isEmpty else {
            return Self.originalTableMinimumColumnWidth
        }
        let start = min(max(location.column, 0), columnWidths.count - 1)
        let end = min(start + location.columnSpan, columnWidths.count)
        return columnWidths[start..<end].reduce(0, +)
    }

    private func originalTableCellView(
        _ cell: HWPOriginalTableCell,
        width: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(cell.blocks) { block in
                styledText(for: block, baseFont: .footnote)
                    .multilineTextAlignment(
                        textAlignment(block.presentation.alignment)
                    )
                    .frame(
                        maxWidth: .infinity,
                        alignment: frameAlignment(block.presentation.alignment)
                    )
                ForEach(block.images) { image in
                    originalImageView(image)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(width: width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            cell.location.boxStyle?.backgroundColorRGB.map(hwpColor) ?? .white
        )
        .overlay {
            if let style = cell.location.boxStyle {
                HWPBoxStyleOverlay(style: style)
            } else {
                Rectangle().stroke(VisionCraftUI.outline, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            cell.blocks
                .map(\.accessibilityLabel)
                .joined(separator: ". ")
        )
    }

    private func originalTableRows(
        _ blocks: [HWPDocumentBlock]
    ) -> [HWPOriginalTableRow] {
        var cells: [String: HWPOriginalTableCell] = [:]
        for block in blocks {
            guard let location = block.tableLocation else { continue }
            let key = "\(location.table)-\(location.row)-\(location.column)"
            if let existing = cells[key] {
                cells[key] = HWPOriginalTableCell(
                    location: existing.location,
                    blocks: existing.blocks + [block]
                )
            } else {
                cells[key] = HWPOriginalTableCell(
                    location: location,
                    blocks: [block]
                )
            }
        }
        let byRow = Dictionary(grouping: cells.values) { $0.location.row }
        return byRow.keys.sorted().map { row in
            HWPOriginalTableRow(
                row: row,
                cells: (byRow[row] ?? []).sorted {
                    $0.location.column < $1.location.column
                }
            )
        }
    }

    private var documentList: some View {
        let document = HWPAccessibleDocument.make(blocks: viewModel.blocks)
        let fieldNames = viewModel.formFieldNames
        return ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if !document.tables.isEmpty {
                    HStack {
                        Text(AppLocalization.format("표 %lld개", document.tables.count))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Menu("표로 이동", systemImage: "tablecells") {
                            ForEach(document.tables) { table in
                                Button(table.title) {
                                    withAnimation { proxy.scrollTo(table.id, anchor: .top) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(VisionCraftUI.surfaceVariant)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(document.entries) { entry in
                            switch entry {
                            case .paragraph(let block):
                                blockView(block).id(entry.id)
                            case .table(let table):
                                HWPAccessibleTableHeader(table: table).id(entry.id)
                            case .row(let row):
                                HWPAccessibleRowButton(row: row,
                                    selectedBlockID: viewModel.selectedBlockID, fieldNames: fieldNames) {
                                    viewModel.commitEditorChange()
                                    // Capture current blocks after committing the paragraph editor.
                                    let current = HWPAccessibleDocument.make(blocks: viewModel.blocks)
                                    if let fresh = current.tables.flatMap(\.rows).first(where: { $0.id == row.id }) {
                                        if let block = fresh.blocks.first(where: { $0.isEditable && fieldNames[$0.id] != nil })
                                            ?? fresh.blocks.first(where: \.isEditable) ?? fresh.blocks.first {
                                            viewModel.selectBlock(block.id)
                                        }
                                        editingTableRow = fresh
                                    }
                                }
                                .id(entry.id)
                            }
                        }
                    }
                    .padding(16)
                }
                .accessibilityRotor("표") {
                    ForEach(document.tables) { table in
                        AccessibilityRotorEntry(table.title, id: table.id)
                    }
                }
            }
            .onChange(of: viewModel.selectedBlockID) { _, id in
                guard let id, let entryID = document.entryIDByBlockID[id] else { return }
                withAnimation { proxy.scrollTo(entryID, anchor: .center) }
            }
        }
    }

    private func blockView(_ block: HWPDocumentBlock) -> some View {
        Button { viewModel.selectBlock(block.id) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(
                    systemName: !block.images.isEmpty
                        ? "photo"
                        : (block.tableLocation == nil ? "text.alignleft" : "tablecells")
                )
                    .frame(width: 22)
                    .foregroundStyle(VisionCraftUI.primary)
                VStack(alignment: .leading, spacing: 4) {
                    if let label = HWPAccessibleDocument.label(for: block) {
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VisionCraftUI.secondaryText)
                    }
                    Text(HWPAccessibleDocument.displayText(for: block))
                        .foregroundStyle(
                            block.text.isEmpty
                                ? VisionCraftUI.secondaryText
                                : VisionCraftUI.primaryText
                        )
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !block.images.isEmpty {
                        Label(
                            AppLocalization.format("그림 %lld개", block.images.count),
                            systemImage: "photo"
                        )
                        .font(.caption)
                        .foregroundStyle(VisionCraftUI.secondaryText)
                        if let image = block.images.first,
                           let uiImage = UIImage(data: image.data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 260, maxHeight: 140, alignment: .leading)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                if !block.isEditable {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(VisionCraftUI.secondaryText)
                }
            }
            .padding(12)
            .background(
                viewModel.selectedBlockID == block.id
                    ? VisionCraftUI.primary.opacity(0.13)
                    : VisionCraftUI.surface,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14).stroke(
                    viewModel.selectedBlockID == block.id
                        ? VisionCraftUI.primary
                        : VisionCraftUI.outline,
                    lineWidth: viewModel.selectedBlockID == block.id ? 2 : 1
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(block.accessibilityLabel)
        .accessibilityHint(
            block.isEditable
                ? "두 번 탭하면 이 문단을 선택합니다."
                : "복합 개체가 포함된 읽기 전용 문단입니다."
        )
    }

    @ViewBuilder
    private func originalBlockView(_ block: HWPDocumentBlock) -> some View {
        let presentation = block.presentation
        VStack(alignment: .leading, spacing: 4) {
            if block.region.kind == .footnote || block.region.kind == .endnote,
               let region = block.region.accessibilityDescription {
                Text(region)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.gray)
            } else if let table = block.tableLocation {
                Text(table.accessibilityDescription)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VisionCraftUI.secondaryText)
            }
            styledText(for: block)
                .multilineTextAlignment(textAlignment(presentation.alignment))
                .frame(
                    maxWidth: .infinity,
                    alignment: frameAlignment(presentation.alignment)
                )
            ForEach(block.images) { image in
                originalImageView(image)
            }
        }
        .padding(.leading, max(0, presentation.leftMarginPoints))
        .padding(.trailing, max(0, presentation.rightMarginPoints))
        .padding(.top, max(0, presentation.spacingBeforePoints))
        .padding(.bottom, max(0, presentation.spacingAfterPoints))
        .padding(
            .leading,
            max(0, presentation.firstLineIndentPoints)
        )
        .padding(block.tableLocation == nil ? 0 : 8)
        .overlay {
            if block.tableLocation != nil {
                Rectangle().stroke(VisionCraftUI.outline)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(block.accessibilityLabel)
    }

    @ViewBuilder
    private func originalImageView(_ image: HWPDocumentImage) -> some View {
        if let uiImage = UIImage(data: image.data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(
                    width: min(image.widthPoints, 560),
                    height: min(image.heightPoints, 700),
                    alignment: .leading
                )
                .accessibilityLabel(
                    image.description?.isEmpty == false
                        ? image.description!
                        : AppLocalization.string("한글 문서 그림")
                )
        } else {
            Label("그림을 표시할 수 없습니다", systemImage: "photo.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.gray)
        }
    }

    private func styledText(
        for block: HWPDocumentBlock,
        baseFont: Font = .body
    ) -> Text {
        let runs = block.presentation.textRuns
        guard !runs.isEmpty else {
            return Text(block.text.isEmpty ? " " : block.text).font(baseFont)
        }
        return runs.reduce(Text("")) { partial, run in
            partial + styledTextRun(run)
        }
    }

    private func styledTextRun(_ run: HWPDocumentTextRun) -> Text {
        var text = Text(run.text)
        let size = run.fontSizePoints ?? 12
        if let size = run.fontSizePoints {
            if let name = HWPDocumentFontResolver.resolution(for: run).resolvedName {
                text = text.font(.custom(name, size: CGFloat(size)))
            } else {
                text = text.font(.system(size: CGFloat(size)))
            }
        }
        let kern = size * run.letterSpacingPercent / 100
        if kern != 0 { text = text.kerning(CGFloat(kern)) }
        if run.isBold { text = text.bold() }
        if run.isItalic { text = text.italic() }
        if run.isUnderlined { text = text.underline() }
        if run.isStruckThrough { text = text.strikethrough() }
        var baseline = size * run.baselinePositionPercent / 100
        if run.isSuperscript {
            baseline += size * 0.32
        } else if run.isSubscript {
            baseline -= size * 0.22
        }
        if baseline != 0 { text = text.baselineOffset(CGFloat(baseline)) }
        if let rgb = run.textColorRGB {
            text = text.foregroundColor(hwpColor(rgb))
        }
        return text
    }

    private func textAlignment(_ alignment: HWPParagraphAlignment) -> TextAlignment {
        switch alignment {
        case .trailing:
            return .trailing
        case .centered:
            return .center
        default:
            return .leading
        }
    }

    private func frameAlignment(_ alignment: HWPParagraphAlignment) -> Alignment {
        switch alignment {
        case .trailing:
            return .trailing
        case .centered:
            return .center
        default:
            return .leading
        }
    }

    private var editorPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("선택한 문단 편집")
                .font(.headline)
            TextEditor(text: $viewModel.editorText)
                .font(.body)
                .frame(minHeight: 90, maxHeight: 170)
                .padding(8)
                .background(
                    VisionCraftUI.surfaceVariant,
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .disabled(!viewModel.canEditSelectedBlock)
                .accessibilityLabel("선택한 한글 문단 편집")
            HStack {
                if viewModel.selectedBlock?.isEditable == false {
                    Label(
                        "복합 개체가 포함된 문단은 읽기 전용입니다.",
                        systemImage: "lock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(VisionCraftUI.secondaryText)
                }
                Spacer()
                Button("문단 적용") { viewModel.commitEditorChange() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canEditSelectedBlock)
            }
        }
        .padding(14)
        .background(VisionCraftUI.surface)
    }

    private var statusBar: some View {
        Text(viewModel.status)
            .font(.footnote)
            .foregroundStyle(VisionCraftUI.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(VisionCraftUI.surface)
            .accessibilityLabel(viewModel.status)
    }

    private var documentHeader: some View {
        HStack(spacing: 0) {
            documentBackButton
            if viewMode == .originalDocument, !viewModel.isLoading,
               !(viewModel.errorDescription != nil && viewModel.blocks.isEmpty) {
                HWPRibbonTabBar(tabs: availableRibbonTabs, selected: activeRibbonTab,
                    isCollapsed: $ribbonCollapsed, onSelect: selectRibbonTab)
            } else {
                Spacer(minLength: 0)
            }
            documentActions
        }
        .padding(.horizontal, 8)
        .frame(height: 48)
        .background(VisionCraftUI.surface)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var documentActions: some View {
        HStack(spacing: 0) {
            Button("실행 취소", systemImage: "arrow.uturn.backward") {
                if originalEditor.undo() { return }
                originalEditor.finish()
                viewModel.undo()
            }
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
            .disabled(viewModel.isSaving || (!viewModel.canUndo && !viewModel.hasPendingEditorChange
                && !originalEditor.hasChanges && !originalEditor.canUndo))

            Button("다시 실행", systemImage: "arrow.uturn.forward") {
                if originalEditor.redo() { return }
                originalEditor.finish()
                viewModel.redo()
            }
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
            .disabled(viewModel.isSaving || (!originalEditor.canRedo && (!viewModel.canRedo
                || viewModel.hasPendingEditorChange || originalEditor.hasChanges)))

            Button("더보기", systemImage: "ellipsis") {
                originalEditor.finish()
                viewModel.commitEditorChange()
                setMoreActionsPresented(true)
            }
            .labelStyle(.iconOnly)
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
            .disabled(viewModel.isSaving || viewModel.isLoading || viewModel.blocks.isEmpty)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func setMoreActionsPresented(_ isPresented: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showsMoreActions = isPresented
        }
    }

    private func performPendingMoreAction() {
        guard let action = pendingMoreAction else { return }
        pendingMoreAction = nil
        switch action {
        case .toggleAccessibleEditing:
            isEditingAccessibleDocument.toggle()
        case .toggleAI:
            showsAI.toggle()
        case .fonts:
            showsFontManager = true
        case .convertToHWPX:
            Task {
                await viewModel.convertLegacyForEditing()
                isEditingAccessibleDocument = viewModel.isEditableDocument
                if isEditingAccessibleDocument { viewMode = .accessibleDocument }
            }
        case .save:
            if viewModel.requiresSaveAs {
                beginExport()
            } else {
                Task { await viewModel.save() }
            }
        case .exportPDF, .printDocument:
            originalEditor.finish()
            do { outputSnapshot = try viewModel.outputSnapshot(opensPrintDialog: action == .printDocument) }
            catch { exportError = error.localizedDescription }
        case .exportCopy:
            beginExport()
        }
    }

    private var documentBackButton: some View {
        VisionCraftBackButton {
            guard !viewModel.isSaving else { return }
            originalEditor.finish()
            viewModel.commitEditorChange()
            if viewModel.hasUnsavedChanges {
                showsDiscardConfirmation = true
            } else {
                dismiss()
            }
        }
    }

    private func beginExport() {
        originalEditor.finish()
        Task {
            do {
                exportFile = HWPDocumentExportFile(
                    data: try await viewModel.exportData()
                )
                isExporting = true
            } catch {
                exportError = error.localizedDescription
            }
        }
    }
}
