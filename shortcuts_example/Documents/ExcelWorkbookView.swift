import RivoDocumentEngine
import Combine
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ExcelWorkbookViewModel: ObservableObject {
    struct RowField: Identifiable, Hashable {
        let id: Int
        let column: Int
        let title: String
        var value: String
        let originalValue: String?
        let dropdownValues: [String]
        let dropdownAllowsBlank: Bool

        init(
            id: Int,
            column: Int,
            title: String,
            value: String,
            originalValue: String? = nil,
            dropdownValues: [String] = [],
            dropdownAllowsBlank: Bool = true
        ) {
            self.id = id
            self.column = column
            self.title = title
            self.value = value
            self.originalValue = originalValue
            self.dropdownValues = dropdownValues
            self.dropdownAllowsBlank = dropdownAllowsBlank
        }
    }

    private nonisolated struct EditingState {
        let workbook: ExcelWorkbook
        let selectedSheetPath: String?
        let selectedAddress: ExcelCellAddress?
        let selectionEnd: ExcelCellAddress?
        let selectedDrawingID: String?
        let editingBaseData: Data?
        let edits: [String: [ExcelCellAddress: ExcelCellEdit]]
        let styleEdits: [Int: ExcelStyleEdit]
        let originalDataValidations: [String: [ExcelDataValidationRule]]
        let validationEdits: [String: [ExcelDataValidationRule]]
        let originalConditionalFormatting: [String: [ExcelConditionalFormattingBlock]]
        let conditionalFormattingEdits: [String: [ExcelConditionalFormattingBlock]]
        let differentialStyleEdits: [Int: ExcelDifferentialStyleEdit]
        let originalAnnotations: [String: ExcelWorksheetAnnotations]
        let annotationEdits: [String: ExcelWorksheetAnnotations]
        let originalDrawingObjects: [String: ExcelWorksheetDrawingObjects]
        let drawingObjectEdits: [String: ExcelWorksheetDrawingObjects]
        let originalPivotTables: [String: [ExcelPivotTable]]
        let pivotTableEdits: [String: [ExcelPivotTable]]
    }

    private typealias CellMutation = ExcelCellMutation

    /// Undo history entry: an engine document change, or a full snapshot.
    private nonisolated struct MutationGroup {
        let id = UUID()
        let change: ExcelDocumentChange
        let oldDocumentState: EditingState?
        let newDocumentState: EditingState?
        var sheetIndex: Int { change.sheetIndex }
        var cells: [CellMutation] { change.cells }

        init(
            sheetIndex: Int,
            cells: [CellMutation],
            oldDocumentState: EditingState? = nil,
            newDocumentState: EditingState? = nil,
            oldStyles: [ExcelCellStyle]? = nil,
            newStyles: [ExcelCellStyle]? = nil,
            oldStyleEdits: [Int: ExcelStyleEdit]? = nil,
            newStyleEdits: [Int: ExcelStyleEdit]? = nil,
            oldDifferentialStyles: [ExcelDifferentialStyle]? = nil,
            newDifferentialStyles: [ExcelDifferentialStyle]? = nil,
            oldDifferentialStyleEdits:
                [Int: ExcelDifferentialStyleEdit]? = nil,
            newDifferentialStyleEdits:
                [Int: ExcelDifferentialStyleEdit]? = nil,
            oldDataValidations: [ExcelDataValidationRule]? = nil,
            newDataValidations: [ExcelDataValidationRule]? = nil,
            oldConditionalFormatting:
                [ExcelConditionalFormattingBlock]? = nil,
            newConditionalFormatting:
                [ExcelConditionalFormattingBlock]? = nil,
            oldAnnotations: ExcelWorksheetAnnotations? = nil,
            newAnnotations: ExcelWorksheetAnnotations? = nil,
            oldDrawingObjects: ExcelWorksheetDrawingObjects? = nil,
            newDrawingObjects: ExcelWorksheetDrawingObjects? = nil,
            oldPivotTables: [ExcelPivotTable]? = nil,
            newPivotTables: [ExcelPivotTable]? = nil,
            oldTables: [ExcelTable]? = nil,
            newTables: [ExcelTable]? = nil
        ) {
            self.oldDocumentState = oldDocumentState
            self.newDocumentState = newDocumentState
            change = ExcelDocumentChange(
                sheetIndex: sheetIndex, cells: cells, oldStyles: oldStyles, newStyles: newStyles,
                oldStyleEdits: oldStyleEdits, newStyleEdits: newStyleEdits,
                oldDifferentialStyles: oldDifferentialStyles, newDifferentialStyles: newDifferentialStyles,
                oldDifferentialStyleEdits: oldDifferentialStyleEdits,
                newDifferentialStyleEdits: newDifferentialStyleEdits,
                oldDataValidations: oldDataValidations, newDataValidations: newDataValidations,
                oldConditionalFormatting: oldConditionalFormatting, newConditionalFormatting: newConditionalFormatting,
                oldAnnotations: oldAnnotations, newAnnotations: newAnnotations,
                oldDrawingObjects: oldDrawingObjects, newDrawingObjects: newDrawingObjects,
                oldPivotTables: oldPivotTables, newPivotTables: newPivotTables,
                oldTables: oldTables, newTables: newTables)
        }

        init(change: ExcelDocumentChange) {
            self.change = change
            oldDocumentState = nil
            newDocumentState = nil
        }
    }

    private struct EditorMutationSession {
        let sheetIndex: Int
        let address: ExcelCellAddress
        let undoStackIndex: Int
    }

    @Published private(set) var workbook: ExcelWorkbook?
    @Published var selectedSheetIndex = 0
    @Published var findText = ""
    @Published var navigationRevealAddress: ExcelCellAddress?
    @Published var selectionEnd: ExcelCellAddress?
    private var rangeClipboard: ExcelRangeClipboard?
    private var editingBaseData: Data?
    @Published var selectedDrawingID: String?
    @Published var selectedAddress: ExcelCellAddress?
    @Published var editorText = ""
    @Published private(set) var aiReferences: ExcelAIReferences?
    @Published private(set) var aiReferenceIndex = 0

    private var aiReferenceItems: [(sheet: ExcelAIReferences.Sheet, address: ExcelCellAddress)] {
        aiReferences?.sheets.flatMap { sheet in sheet.addresses.map { (sheet, $0) } } ?? []
    }

    var aiHighlightedAddresses: Set<ExcelCellAddress> {
        guard let path = selectedSheet?.partPath else { return [] }
        return Set(aiReferences?.sheets.first(where: { $0.sheetPartPath == path })?.addresses ?? [])
    }

    var aiReferenceAddress: ExcelCellAddress? {
        guard aiReferenceItems.indices.contains(aiReferenceIndex),
              aiReferenceItems[aiReferenceIndex].sheet.sheetPartPath == selectedSheet?.partPath else { return nil }
        return aiReferenceItems[aiReferenceIndex].address
    }

    var aiReferenceSheetName: String? {
        aiReferenceItems.indices.contains(aiReferenceIndex) ? aiReferenceItems[aiReferenceIndex].sheet.sheetName : nil
    }

    func showAIReferences(_ references: ExcelAIReferences?) {
        aiReferences = references
        aiReferenceIndex = 0
        revealAIReference(at: 0)
    }

    func moveAIReference(by offset: Int) {
        guard !aiReferenceItems.isEmpty else { return }
        aiReferenceIndex = min(max(0, aiReferenceIndex + offset), aiReferenceItems.count - 1)
        revealAIReference(at: aiReferenceIndex)
    }

    private func revealAIReference(at index: Int) {
        guard aiReferenceItems.indices.contains(index), let workbook else { return }
        let item = aiReferenceItems[index]
        if let sheetIndex = workbook.sheets.firstIndex(where: { $0.partPath == item.sheet.sheetPartPath }),
           sheetIndex != selectedSheetIndex {
            selectSheet(sheetIndex)
        }
    }
    // Keep the first render non-empty so SwiftUI mounts the `.task` that
    // actually reads the workbook. An initially empty conditional Group can
    // otherwise leave only the navigation toolbar visible.
    @Published private(set) var isLoading = true
    @Published private(set) var isSaving = false
    @Published private(set) var isAutosaving = false
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var status = ""
    @Published private(set) var validationWarning: String?
    @Published private(set) var errorDescription: String?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var accessibilityFocusRequestID = 0
    @Published private(set) var largeWorkbookPreflight:
        ExcelWorkbookPreflight?
    @Published private(set) var largeWindowStartIndices: [String: Int] = [:]
    @Published private(set) var largeWindowRows: [String: [Int]] = [:]
    @Published private(set) var largeAddedRows: [String: Set<Int>] = [:]
    @Published private(set) var largeSearchRows: [Int] = []
    @Published private(set) var largeSearchResultIndex: Int?
    @Published private(set) var isLoadingLargeWindow = false
    @Published private(set) var isSearchingLargeWorkbook = false
    @Published private(set) var lastFormulaRecalculationCount = 0
    @Published private(set) var unsupportedFormulaCount = 0

    let fileURL: URL
    let originalDocumentID: UUID?

    var isOriginalDocument: Bool {
        originalDocumentID != nil
    }

    var isLargeWorkbook: Bool {
        largeWorkbookPreflight?.requiresLargeMode == true
    }

    var selectedLargeSheetSummary: ExcelWorksheetPreflight? {
        guard let partPath = selectedSheet?.partPath else {
            return nil
        }
        return largeWorkbookPreflight?.sheet(partPath: partPath)
    }

    var selectedLargeWindowRows: [Int] {
        guard let partPath = selectedSheet?.partPath else {
            return []
        }
        return largeWindowRows[partPath] ?? []
    }

    var canMoveToPreviousLargeWindow: Bool {
        guard let partPath = selectedSheet?.partPath else {
            return false
        }
        return (largeWindowStartIndices[partPath] ?? 0) > 0
    }

    var canMoveToNextLargeWindow: Bool {
        guard let summary = selectedLargeSheetSummary else {
            return false
        }
        let start = largeWindowStartIndices[summary.partPath] ?? 0
        return start + ExcelWorkbookDocument.largePageSize
            < allLargeRows(for: summary).count
    }

    private var sourceData = Data()
    // Autosave writes a new disk version while keeping the editing baseline
    // and history intact, so undo can still restore values from before it.
    private var lastAutosavedData: Data?
    private var autosavedHistoryIDs: [UUID]?
    /// Pending edits; the shared engine owns the rules that change them.
    private var registry = ExcelEditRegistry()
    private var edits: [String: [ExcelCellAddress: ExcelCellEdit]] {
        get { registry.cells }
        _modify { yield &registry.cells }
        set { registry.cells = newValue }
    }
    private var styleEdits: [Int: ExcelStyleEdit] {
        get { registry.styles }
        _modify { yield &registry.styles }
        set { registry.styles = newValue }
    }
    private var originalDataValidations: [String: [ExcelDataValidationRule]] {
        get { registry.originalDataValidations }
        _modify { yield &registry.originalDataValidations }
        set { registry.originalDataValidations = newValue }
    }
    private var validationEdits: [String: [ExcelDataValidationRule]] {
        get { registry.dataValidations }
        _modify { yield &registry.dataValidations }
        set { registry.dataValidations = newValue }
    }
    private var originalConditionalFormatting: [String: [ExcelConditionalFormattingBlock]] {
        get { registry.originalConditionalFormatting }
        _modify { yield &registry.originalConditionalFormatting }
        set { registry.originalConditionalFormatting = newValue }
    }
    private var conditionalFormattingEdits: [String: [ExcelConditionalFormattingBlock]] {
        get { registry.conditionalFormatting }
        _modify { yield &registry.conditionalFormatting }
        set { registry.conditionalFormatting = newValue }
    }
    private var differentialStyleEdits: [Int: ExcelDifferentialStyleEdit] {
        get { registry.differentialStyles }
        _modify { yield &registry.differentialStyles }
        set { registry.differentialStyles = newValue }
    }
    private var originalAnnotations: [String: ExcelWorksheetAnnotations] {
        get { registry.originalAnnotations }
        _modify { yield &registry.originalAnnotations }
        set { registry.originalAnnotations = newValue }
    }
    private var annotationEdits: [String: ExcelWorksheetAnnotations] {
        get { registry.annotations }
        _modify { yield &registry.annotations }
        set { registry.annotations = newValue }
    }
    private var originalDrawingObjects: [String: ExcelWorksheetDrawingObjects] {
        get { registry.originalDrawingObjects }
        _modify { yield &registry.originalDrawingObjects }
        set { registry.originalDrawingObjects = newValue }
    }
    private var drawingObjectEdits: [String: ExcelWorksheetDrawingObjects] {
        get { registry.drawingObjects }
        _modify { yield &registry.drawingObjects }
        set { registry.drawingObjects = newValue }
    }
    private var originalPivotTables: [String: [ExcelPivotTable]] {
        get { registry.originalPivotTables }
        _modify { yield &registry.originalPivotTables }
        set { registry.originalPivotTables = newValue }
    }
    private var pivotTableEdits: [String: [ExcelPivotTable]] {
        get { registry.pivotTables }
        _modify { yield &registry.pivotTables }
        set { registry.pivotTables = newValue }
    }
    private var undoStack: [MutationGroup] = []
    private var redoStack: [MutationGroup] = []
    private var editorMutationSession: EditorMutationSession?
    private var didLoad = false
    private var autosaveDebounceTask: Task<Void, Never>?
    private var autosaveWriteTask: Task<Bool, Never>?
    private var largeWorkbookCache: ExcelLargeWorkbookCache?
    private let writeContents: @Sendable (URL, Data, Data) throws -> Void
    private let autosaveDelayOverride: Duration?

    init(
        fileURL: URL,
        originalDocumentID: UUID? = nil,
        autosaveDelay: Duration? = nil,
        writeContents: @escaping @Sendable (URL, Data, Data) throws -> Void = {
            try CoordinatedDocumentFileAccess.replaceContents(
                at: $0, with: $1, expectedContents: $2
            )
        }
    ) {
        self.fileURL = fileURL
        self.originalDocumentID =
            originalDocumentID
        self.autosaveDelayOverride = autosaveDelay
        self.writeContents = writeContents
    }

    var canEditSelectedSheet: Bool {
        !isSaving && selectedSheet?.protection.isEnabled == false
    }

    var canManageSheets: Bool {
        !isSaving && !isLargeWorkbook && workbook?.protection.lockStructure == false
            && workbook?.sheets.contains(where: { $0.didTruncate || $0.isWindowed }) == false
    }

    var sheetManagementRestriction: String? {
        if workbook?.protection.lockStructure == true { return AppLocalization.string("시트 구성이 보호된 문서는 시트를 변경할 수 없습니다.") }
        if isLargeWorkbook || workbook?.sheets.contains(where: { $0.didTruncate || $0.isWindowed }) == true { return AppLocalization.string("대용량 문서에서는 시트 관리를 사용할 수 없습니다.") }
        return nil
    }

    private func allowEditing() -> Bool {
        guard !isSaving else { return false }
        guard selectedSheet?.protection.isEnabled == false else {
            status = AppLocalization.string("보호된 시트는 편집할 수 없습니다.")
            return false
        }
        return true
    }

    deinit {
        if let directoryURL = largeWorkbookCache?.directoryURL {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    var selectedSheet: ExcelWorksheet? {
        guard let workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return nil
        }
        return workbook.sheets[selectedSheetIndex]
    }

    var selectedCell: ExcelCell? {
        guard let sheet = selectedSheet,
              let selectedAddress else {
            return nil
        }
        return sheet.cell(
            at: sheet.canonicalAddress(for: selectedAddress)
        )
    }

    var selectedCellIsSpillResult: Bool {
        guard let selectedAddress,
              let owner = selectedCell?.spillAnchor else { return false }
        return owner != selectedAddress
    }

    var selectedSpillAnchor: ExcelCellAddress? {
        selectedCell?.spillAnchor
    }

    var selectedNumberFormat: ExcelNumberFormat? {
        guard let workbook,
              let selectedCell else {
            return nil
        }
        return ExcelNumberFormat.matching(
            workbook.style(at: selectedCell.styleIndex)
        )
    }

    var selectedDataValidation: ExcelDataValidationRule? {
        guard let sheet = selectedSheet,
              let selectedAddress else {
            return nil
        }
        let canonical = sheet.canonicalAddress(for: selectedAddress)
        return sheet.dataValidations.first { $0.contains(canonical) }
    }

    var selectedDropdownValues: [String] {
        selectedDataValidation?.inlineListValues ?? []
    }

    var selectedDropdownAllowsBlank: Bool {
        selectedDataValidation?.allowsBlank ?? true
    }

    var selectedConditionalFormattingCount: Int {
        guard let sheet = selectedSheet,
              let selectedAddress else {
            return 0
        }
        let canonical = sheet.canonicalAddress(for: selectedAddress)
        return sheet.conditionalFormatting.filter {
            $0.contains(canonical) && $0.isEditable
        }.count
    }

    var selectedConditionalRule: ExcelConditionalFormattingRule? {
        guard let sheet = selectedSheet,
              let selectedAddress else {
            return nil
        }
        let canonical = sheet.canonicalAddress(for: selectedAddress)
        return sheet.conditionalFormatting.first(where: {
            $0.contains(canonical) && $0.isEditable
        })?.rules.first
    }

    var selectedConditionalHighlight: ExcelConditionalHighlight? {
        guard let workbook,
              let rule = selectedConditionalRule,
              workbook.differentialStyles.indices.contains(
                  rule.differentialStyleIndex
              ) else {
            return nil
        }
        return .matching(
            workbook.differentialStyles[rule.differentialStyleIndex]
        )
    }

    var selectedHyperlink: ExcelCellHyperlink? {
        guard let sheet = selectedSheet,
              let selectedAddress else {
            return nil
        }
        return sheet.annotations.hyperlink(
            at: sheet.canonicalAddress(for: selectedAddress)
        )
    }

    var selectedNote: ExcelCellNote? {
        guard let sheet = selectedSheet,
              let selectedAddress else {
            return nil
        }
        return sheet.annotations.note(
            at: sheet.canonicalAddress(for: selectedAddress)
        )
    }

    var selectedExternalHyperlinkURL: URL? {
        guard let hyperlink = selectedHyperlink,
              hyperlink.isExternal else {
            return nil
        }
        return URL(string: hyperlink.target)
    }

    var selectedSheetImages: [ExcelSheetImage] {
        selectedSheet?.drawingObjects.images ?? []
    }

    var selectedSheetChartCount: Int {
        selectedSheet?.drawingObjects.chartCount ?? 0
    }

    var selectedSheetCharts: [ExcelSheetChart] {
        selectedSheet?.drawingObjects.charts ?? []
    }

    var selectedSheetShapes: [ExcelSheetShape] {
        selectedSheet?.drawingObjects.shapes ?? []
    }

    var defaultChartSourceReference: String {
        guard let sheet = selectedSheet else { return "A1:B2" }
        return ExcelPivotEditing.defaultSourceReference(in: sheet, selected: selectedAddress)
    }

    var selectedSheetPivotTableCount: Int {
        selectedSheet?.pivotTables.count ?? 0
    }

    var selectedSheetPivotTables: [ExcelPivotTable] {
        selectedSheet?.pivotTables ?? []
    }

    var defaultPivotDestinationReference: String {
        guard let sheet = selectedSheet else { return "G1" }
        return ExcelPivotEditing.defaultDestinationReference(in: sheet, source: defaultChartSourceReference)
    }

    var canApplyNumberFormatToCurrentColumn: Bool {
        guard let sheet = selectedSheet,
              let selectedAddress,
              ExcelAccessibilityAnalyzer.regions(in: sheet).contains(
                  where: {
                      $0.contains(selectedAddress)
                          && $0.columns.contains(where: {
                              $0.column == selectedAddress.column
                          })
                          && !$0.rowNumbers.isEmpty
                  }
              ) else {
            return false
        }
        return true
    }

    var selectedRangeDescription: String? {
        guard let sheet = selectedSheet,
              let selectedAddress else {
            return nil
        }
        if let range = sheet.mergedRange(containing: selectedAddress) {
            return AppLocalization.format(
                "병합 셀 %@",
                range.reference
            )
        }
        return nil
    }

    func load() async {
        guard !didLoad else {
            return
        }
        didLoad = true
        isLoading = true
        errorDescription = nil
        status = AppLocalization.string("엑셀 파일을 여는 중…")
        do {
            let url = fileURL
            let result = try await Task.detached(
                priority: .userInitiated
            ) {
                let values = try url.resourceValues(
                    forKeys: [
                        .fileSizeKey,
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                    ]
                )
                guard values.isRegularFile == true,
                      values.isSymbolicLink != true else {
                    throw ExcelWorkbookDocumentError.invalidWorkbook
                }
                if let fileSize = values.fileSize,
                   fileSize > ExcelWorkbookDocument.maximumWorkbookBytes {
                    throw ExcelWorkbookDocumentError.workbookLimitExceeded
                }
                let data = try
                    CoordinatedDocumentFileAccess
                    .readData(
                        from: url
                    )
                let preflight = try ExcelWorkbookDocument.preflight(
                    from: data
                )
                var workbook: ExcelWorkbook
                let cache: ExcelLargeWorkbookCache?
                if preflight.requiresLargeMode {
                    let directoryURL = FileManager.default
                        .temporaryDirectory
                        .appendingPathComponent(
                            "VisionCraft-Large-XLSX-\(UUID().uuidString)",
                            isDirectory: true
                        )
                    do {
                        cache = try ExcelWorkbookDocument.buildLargeCache(
                            from: data,
                            preflight: preflight,
                            directoryURL: directoryURL
                        )
                        workbook = try ExcelWorkbookDocument.loadWindowed(
                            from: data,
                            preflight: preflight
                        )
                    } catch {
                        try? FileManager.default.removeItem(
                            at: directoryURL
                        )
                        throw error
                    }
                } else {
                    cache = nil
                    workbook = try ExcelWorkbookDocument.load(from: data)
                    // Initial recalculation can be as expensive as parsing.
                    // Finish it here before publishing the workbook to the UI.
                    _ = Self.refreshDerivedFormulaValues(in: &workbook, edits: [:])
                }
                return (
                    data,
                    preflight,
                    workbook,
                    cache
                )
            }.value
            sourceData = result.0
            largeWorkbookPreflight = result.1.requiresLargeMode
                ? result.1
                : nil
            let loadedWorkbook = result.2
            workbook = loadedWorkbook
            registry.setOriginals(from: result.2)
            largeWorkbookCache = result.3
            configureInitialLargeWindows(using: result.1)
            selectedSheetIndex = 0
            if let first = loadedWorkbook.sheets.first {
                selectedAddress = initialAddress(in: first)
                syncEditorText(using: first)
                updateValidationWarning(in: first)
                updateFormulaSupportSummary(in: first)
            }
            status = workbookStatus(result.2)
        } catch {
            errorDescription = error.localizedDescription
        }
        isLoading = false
    }

    func selectSheet(_ index: Int) {
        guard !isSaving else { return }
        endEditorTextEditing()
        guard var workbook,
              workbook.sheets.indices.contains(index) else {
            return
        }
        _ = refreshDerivedFormulaValues(in: &workbook)
        self.workbook = workbook
        selectedSheetIndex = index
        selectedDrawingID = nil
        navigationRevealAddress = nil
        selectionEnd = nil
        largeSearchRows = []
        largeSearchResultIndex = nil
        let sheet = workbook.sheets[index]
        selectedAddress = initialAddress(in: sheet)
        syncEditorText(using: sheet)
        updateValidationWarning(in: sheet)
        updateFormulaSupportSummary(in: sheet)
        status = accessibilitySummary(for: sheet)
        requestAccessibilityFocus()
    }

    func moveLargeWindow(byPages offset: Int) async {
        guard offset != 0,
              let summary = selectedLargeSheetSummary else {
            return
        }
        let current = largeWindowStartIndices[summary.partPath] ?? 0
        let rows = allLargeRows(for: summary)
        guard !rows.isEmpty else {
            return
        }
        let requested = current
            + offset * ExcelWorkbookDocument.largePageSize
        let lastPageStart = max(
            0,
            ((rows.count - 1) / ExcelWorkbookDocument.largePageSize)
                * ExcelWorkbookDocument.largePageSize
        )
        await loadLargeWindow(
            summary: summary,
            startingAt: min(max(requested, 0), lastPageStart)
        )
    }

    func jumpToLargeRow(_ requestedRow: Int) async {
        guard requestedRow > 0,
              let summary = selectedLargeSheetSummary else {
            return
        }
        let rows = allLargeRows(for: summary)
        guard !rows.isEmpty else {
            return
        }
        let position = lowerBound(of: requestedRow, in: rows)
        let selectedIndex = min(position, rows.count - 1)
        let pageStart = selectedIndex
            / ExcelWorkbookDocument.largePageSize
            * ExcelWorkbookDocument.largePageSize
        await loadLargeWindow(
            summary: summary,
            startingAt: pageStart,
            preferredRow: rows[selectedIndex]
        )
    }

    func searchLargeWorkbook(_ query: String) async {
        let trimmed = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty,
              !isSearchingLargeWorkbook,
              let sheet = selectedSheet else {
            return
        }
        isSearchingLargeWorkbook = true
        status = AppLocalization.string("대용량 시트 전체를 검색하는 중…")
        let data = sourceData
        let partPath = sheet.partPath
        let cachedSheet = largeWorkbookCache?.sheet(partPath: partPath)
        do {
            let sourceRows = try await Task.detached(
                priority: .userInitiated
            ) {
                if let cachedSheet {
                    return try cachedSheet.searchRows(query: trimmed)
                }
                return try ExcelWorkbookDocument.searchRows(
                    in: data,
                    sheetPartPath: partPath,
                    query: trimmed
                )
            }.value
            var matchingRows = Set(sourceRows)
            for (address, edit) in edits[partPath] ?? [:]
                where searchableText(for: edit.input)
                    .localizedCaseInsensitiveContains(trimmed) {
                matchingRows.insert(address.row)
            }
            let rows = Array(matchingRows).sorted()
            largeSearchRows = rows
            largeSearchResultIndex = rows.isEmpty ? nil : 0
            status = ExcelLargeWindow.foundMessage(rows)
            if let first = rows.first {
                await jumpToLargeRow(first)
            }
        } catch {
            errorDescription = error.localizedDescription
            status = AppLocalization.format(
                "검색하지 못했습니다: %@",
                error.localizedDescription
            )
        }
        isSearchingLargeWorkbook = false
    }

    func moveToNextLargeSearchResult() async {
        guard !largeSearchRows.isEmpty else {
            return
        }
        let next = ((largeSearchResultIndex ?? -1) + 1)
            % largeSearchRows.count
        largeSearchResultIndex = next
        await jumpToLargeRow(largeSearchRows[next])
    }

    func selectRegion(_ region: ExcelAccessibleRegion) {
        guard !isSaving else { return }
        guard selectedSheet != nil else {
            return
        }
        let row = region.rowNumbers.first
            ?? region.headerRow.map { $0 + 1 }
            ?? region.range.start.row
        let column = region.columns.first?.column
            ?? region.range.start.column
        selectCell(
            ExcelCellAddress(
                row: row,
                column: column
            )
        )
        status = AppLocalization.format(
            "%@ 영역 · %lld개 읽을 행 · %lld개 열",
            region.name,
            region.rowNumbers.count,
            region.columns.count
        )
        requestAccessibilityFocus()
    }

    func selectCell(_ address: ExcelCellAddress) {
        guard !isSaving else { return }
        selectedDrawingID = nil
        navigationRevealAddress = nil
        selectionEnd = nil
        guard !isSaving else { return }
        endEditorTextEditing()
        guard let sheet = selectedSheet else {
            return
        }
        let canonical = sheet.canonicalAddress(for: address)
        selectedAddress = canonical
        editorText = sheet.cell(at: canonical)?.editText ?? ""
        updateValidationWarning(in: sheet)
    }

    func commitEditorText() {
        guard allowEditing() else { return }
        guard let selectedAddress else {
            endEditorTextEditing()
            return
        }
        setCell(
            at: selectedAddress,
            userText: editorText,
            coalescingEditorChanges: true
        )
        endEditorTextEditing()
    }

    func updateEditorText(_ text: String) {
        guard allowEditing() else { return }
        editorText = text
        guard let selectedAddress else {
            return
        }
        setCell(
            at: selectedAddress,
            userText: text,
            coalescingEditorChanges: true,
            synchronizingEditorText: false
        )
    }

    func clearSelectedCell() {
        guard allowEditing() else { return }
        updateEditorText("")
        endEditorTextEditing()
    }

    @discardableResult
    func applyDropdown(
        values rawValues: [String],
        allowsBlank: Bool,
        toCurrentColumn: Bool
    ) -> Bool {
        guard allowEditing() else { return false }
        endEditorTextEditing()
        guard var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex),
              let selectedAddress else {
            return false
        }
        let sheet = workbook.sheets[selectedSheetIndex]
        let canonical = sheet.canonicalAddress(for: selectedAddress)
        let addresses = ExcelSheetPartEditing.targetAddresses(
            selection: canonical, selectedRange: selectedRange, toCurrentColumn: toCurrentColumn, in: sheet)
        let change: ExcelDocumentChange
        do {
            change = try ExcelSheetPartEditing.settingDropdown(
                values: rawValues, allowsBlank: allowsBlank, at: addresses, sheetIndex: selectedSheetIndex, in: workbook)
        } catch {
            status = error.localizedDescription
            return false
        }
        apply(MutationGroup(change: change), forward: true, registeringUndo: true, workbook: &workbook)
        self.workbook = workbook
        updateValidationWarning(in: workbook.sheets[selectedSheetIndex])
        status = ExcelSheetPartMessage.dropdownSet(at: canonical, count: addresses.count, toCurrentColumn: toCurrentColumn)
        return true
    }

    func removeDropdown(toCurrentColumn: Bool) {
        guard allowEditing() else { return }
        endEditorTextEditing()
        guard var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex),
              let selectedAddress else {
            return
        }
        let sheet = workbook.sheets[selectedSheetIndex]
        let canonical = sheet.canonicalAddress(for: selectedAddress)
        let addresses = ExcelSheetPartEditing.targetAddresses(
            selection: canonical, selectedRange: selectedRange, toCurrentColumn: toCurrentColumn, in: sheet)
        guard let change = ExcelSheetPartEditing.removingDropdown(
            at: addresses, sheetIndex: selectedSheetIndex, in: workbook) else {
            status = ExcelSheetPartMessage.noDropdown
            return
        }
        apply(MutationGroup(change: change), forward: true, registeringUndo: true, workbook: &workbook)
        self.workbook = workbook
        updateValidationWarning(in: workbook.sheets[selectedSheetIndex])
        status = ExcelSheetPartMessage.dropdownRemoved(at: canonical, toCurrentColumn: toCurrentColumn)
    }

    func chooseDropdownValue(_ value: String) {
        guard allowEditing() else { return }
        guard let selectedAddress else {
            return
        }
        editorText = value
        setCell(at: selectedAddress, userText: value)
    }

    @discardableResult
    func applyConditionalFormatting(
        kind: ExcelConditionalRuleKind,
        comparisonValue rawComparisonValue: String,
        highlight: ExcelConditionalHighlight,
        toCurrentColumn: Bool
    ) -> Bool {
        guard allowEditing() else { return false }
        endEditorTextEditing()
        let comparisonValue: String
        do {
            comparisonValue = try ExcelSheetPartEditing.validatedComparisonValue(rawComparisonValue, for: kind)
        } catch {
            status = error.localizedDescription
            return false
        }
        guard var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex),
              let selectedAddress else {
            return false
        }
        let sheet = workbook.sheets[selectedSheetIndex]
        let canonical = sheet.canonicalAddress(for: selectedAddress)
        let addresses = ExcelSheetPartEditing.targetAddresses(
            selection: canonical, selectedRange: selectedRange, toCurrentColumn: toCurrentColumn, in: sheet)
        let change: ExcelDocumentChange
        do {
            change = try ExcelSheetPartEditing.settingConditionalFormatting(
                kind: kind, comparisonValue: comparisonValue, highlight: highlight, at: addresses,
                sheetIndex: selectedSheetIndex, workbook: workbook, registry: registry)
        } catch {
            status = error.localizedDescription
            return false
        }
        apply(MutationGroup(change: change), forward: true, registeringUndo: true, workbook: &workbook)
        self.workbook = workbook
        status = ExcelSheetPartMessage.conditionalFormattingSet(at: canonical, count: addresses.count, toCurrentColumn: toCurrentColumn)
        return true
    }

    func removeConditionalFormatting(toCurrentColumn: Bool) {
        guard allowEditing() else { return }
        endEditorTextEditing()
        guard var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex),
              let selectedAddress else {
            return
        }
        let sheet = workbook.sheets[selectedSheetIndex]
        let canonical = sheet.canonicalAddress(for: selectedAddress)
        let addresses = ExcelSheetPartEditing.targetAddresses(
            selection: canonical, selectedRange: selectedRange, toCurrentColumn: toCurrentColumn, in: sheet)
        guard let change = ExcelSheetPartEditing.removingConditionalFormatting(
            at: addresses, sheetIndex: selectedSheetIndex, in: workbook) else {
            status = ExcelSheetPartMessage.noConditionalFormatting
            return
        }
        apply(MutationGroup(change: change), forward: true, registeringUndo: true, workbook: &workbook)
        self.workbook = workbook
        status = ExcelSheetPartMessage.conditionalFormattingRemoved(at: canonical, toCurrentColumn: toCurrentColumn)
    }

    @discardableResult
    func applyCellAnnotations(
        hyperlinkTarget rawTarget: String,
        hyperlinkTooltip rawTooltip: String,
        noteText rawNoteText: String,
        noteAuthor rawAuthor: String
    ) -> Bool {
        guard allowEditing() else { return false }
        endEditorTextEditing()
        guard var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex),
              let selectedAddress else {
            return false
        }
        let change: ExcelDocumentChange
        do {
            guard let edited = try ExcelSheetPartEditing.settingAnnotations(
                hyperlinkTarget: rawTarget, hyperlinkTooltip: rawTooltip, noteText: rawNoteText,
                noteAuthor: rawAuthor, at: selectedAddress, sheetIndex: selectedSheetIndex, in: workbook
            ) else {
                status = ExcelSheetPartMessage.annotationsUnchanged
                return false
            }
            change = edited
        } catch {
            status = error.localizedDescription
            return false
        }
        let address = workbook.sheets[selectedSheetIndex].canonicalAddress(for: selectedAddress)
        apply(MutationGroup(change: change), forward: true, registeringUndo: true, workbook: &workbook)
        self.workbook = workbook
        status = ExcelSheetPartMessage.annotationsChanged(at: address)
        return true
    }

    @discardableResult
    func addSheetImage(data: Data) -> Bool {
        guard allowEditing() else { return false }
        endEditorTextEditing()
        guard !isLargeWorkbook,
              var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex),
              let prepared = preparedImage(data) else {
            status = ExcelDrawingMessage.imageNotAdded
            return false
        }
        let start = selectedAddress ?? ExcelCellAddress(row: 1, column: 1)
        guard let change = ExcelDrawingEditing.addingImage(
            prepared, at: start, sheetIndex: selectedSheetIndex, in: workbook) else {
            return false
        }
        apply(MutationGroup(change: change), forward: true, registeringUndo: true, workbook: &workbook)
        self.workbook = workbook
        status = ExcelDrawingMessage.imageAdded(at: start)
        return true
    }

    @discardableResult
    func replaceSheetImage(id: String, data: Data) -> Bool {
        guard allowEditing() else { return false }
        endEditorTextEditing()
        guard !isLargeWorkbook,
              var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return false
        }
        guard workbook.sheets[selectedSheetIndex].drawingObjects.images.contains(where: { $0.id == id }) else {
            return false
        }
        guard let prepared = preparedImage(
            data,
            preferredContentType: ExcelDrawingEditing.preferredReplacementContentType(
                id: id, sheetIndex: selectedSheetIndex, in: workbook)
        ) else {
            status = ExcelDrawingMessage.imageNotReplaced
            return false
        }
        let result = ExcelDrawingEditing.replacingImage(id: id, with: prepared, sheetIndex: selectedSheetIndex, in: workbook)
        if case .unchanged = result {
            status = ExcelDrawingMessage.sameImage
            return false
        }
        guard case .changed(let change, let name) = result else { return false }
        apply(MutationGroup(change: change), forward: true, registeringUndo: true, workbook: &workbook)
        self.workbook = workbook
        status = ExcelDrawingMessage.imageReplaced(name)
        return true
    }

    func removeSheetImage(id: String) {
        guard allowEditing() else { return  }
        endEditorTextEditing()
        guard !isLargeWorkbook,
              var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return 
        }
        let result = ExcelDrawingEditing.removingImage(
            id: id, sheetIndex: selectedSheetIndex, in: workbook, registry: registry)
        guard case .changed(let change, let name) = result else { return  }
        apply(MutationGroup(change: change), forward: true, registeringUndo: true, workbook: &workbook)
        self.workbook = workbook
        status = AppLocalization.format("%@을(를) 삭제했습니다.", name)
    }

    @discardableResult
    func addSheetShape(
        name rawName: String,
        text rawText: String,
        kind: ExcelShapeKind
    ) -> Bool {
        guard allowEditing() else { return false }
        endEditorTextEditing()
        guard !isLargeWorkbook,
              var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return false
        }
        let result = ExcelDrawingEditing.addingShape(
            name: rawName, text: rawText, kind: kind, at: selectedAddress ?? ExcelCellAddress(row: 1, column: 1),
            sheetIndex: selectedSheetIndex, in: workbook)
        guard case .changed(let change, let name) = result else { return false }
        apply(MutationGroup(change: change), forward: true, registeringUndo: true, workbook: &workbook)
        self.workbook = workbook
        status = AppLocalization.format("%@을(를) 추가했습니다.", name)
        return true
    }

    @discardableResult
    func updateSheetShape(
        id: String,
        name rawName: String,
        text: String,
        kind: ExcelShapeKind
    ) -> Bool {
        guard allowEditing() else { return false }
        endEditorTextEditing()
        guard !isLargeWorkbook,
              var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return false
        }
        let result = ExcelDrawingEditing.updatingShape(
            id: id, name: rawName, text: text, kind: kind, sheetIndex: selectedSheetIndex, in: workbook)
        if case .unchanged = result {
            status = AppLocalization.string("바뀐 도형 설정이 없습니다.")
            return false
        }
        guard case .changed(let change, let name) = result else { return false }
        apply(MutationGroup(change: change), forward: true, registeringUndo: true, workbook: &workbook)
        self.workbook = workbook
        status = AppLocalization.format("%@을(를) 수정했습니다.", name)
        return true
    }

    func removeSheetShape(id: String) {
        guard allowEditing() else { return  }
        endEditorTextEditing()
        guard !isLargeWorkbook,
              var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return 
        }
        let result = ExcelDrawingEditing.removingShape(
            id: id, sheetIndex: selectedSheetIndex, in: workbook, registry: registry)
        guard case .changed(let change, let name) = result else { return  }
        apply(MutationGroup(change: change), forward: true, registeringUndo: true, workbook: &workbook)
        self.workbook = workbook
        status = AppLocalization.format("%@을(를) 삭제했습니다.", name)
    }

    @discardableResult
    func addSheetChart(
        title rawTitle: String,
        kind: ExcelChartKind,
        sourceReference: String
    ) -> Bool {
        guard allowEditing() else { return false }
        endEditorTextEditing()
        guard !isLargeWorkbook,
              var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return false
        }
        let result: ExcelDrawingEditResult
        do {
            result = try ExcelDrawingEditing.addingChart(
                title: rawTitle, kind: kind, sourceReference: sourceReference, sheetIndex: selectedSheetIndex, in: workbook)
        } catch {
            status = AppLocalization.string(
                "차트 범위는 머리글과 데이터가 포함된 두 행 이상의 셀 범위로 입력해 주세요."
            )
            return false
        }
        guard case .changed(let change, let name) = result else { return false }
        apply(MutationGroup(change: change), forward: true, registeringUndo: true, workbook: &workbook)
        self.workbook = workbook
        status = AppLocalization.format("%@을(를) 추가했습니다.", name)
        return true
    }

    @discardableResult
    func updateSheetChart(
        id: String,
        title rawTitle: String,
        kind: ExcelChartKind,
        sourceReference: String
    ) -> Bool {
        guard allowEditing() else { return false }
        endEditorTextEditing()
        guard !isLargeWorkbook,
              var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return false
        }
        let result: ExcelDrawingEditResult
        do {
            result = try ExcelDrawingEditing.updatingChart(
                id: id, title: rawTitle, kind: kind, sourceReference: sourceReference, sheetIndex: selectedSheetIndex,
                in: workbook)
        } catch {
            status = AppLocalization.string(
                "차트 범위는 머리글과 데이터가 포함된 두 행 이상의 셀 범위로 입력해 주세요."
            )
            return false
        }
        if case .unchanged = result {
            status = AppLocalization.string("바뀐 차트 설정이 없습니다.")
            return false
        }
        guard case .changed(let change, let name) = result else { return false }
        apply(MutationGroup(change: change), forward: true, registeringUndo: true, workbook: &workbook)
        self.workbook = workbook
        status = AppLocalization.format("%@을(를) 수정했습니다.", name)
        return true
    }

    func removeSheetChart(id: String) {
        guard allowEditing() else { return  }
        endEditorTextEditing()
        guard !isLargeWorkbook,
              var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return 
        }
        let result = ExcelDrawingEditing.removingChart(
            id: id, sheetIndex: selectedSheetIndex, in: workbook, registry: registry)
        guard case .changed(let change, let name) = result else { return  }
        apply(MutationGroup(change: change), forward: true, registeringUndo: true, workbook: &workbook)
        self.workbook = workbook
        status = AppLocalization.format("%@을(를) 삭제했습니다.", name)
    }

    func pivotFieldNames(sourceReference: String) -> [String] {
        guard let sheet = selectedSheet else { return [] }
        return ExcelPivotEditing.fieldNames(sourceReference: sourceReference, in: sheet)
    }

    @discardableResult
    func addPivotTable(
        name rawName: String,
        sourceReference: String,
        destinationReference: String,
        rowFieldIndex: Int,
        dataFieldIndex: Int,
        aggregation: ExcelPivotAggregation,
        refreshOnLoad: Bool
    ) -> Bool {
        guard allowEditing() else { return false }
        endEditorTextEditing()
        guard !isLargeWorkbook,
              var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return false
        }
        let edit: ExcelPivotEdit
        do {
            edit = try ExcelPivotEditing.adding(
                name: rawName, sourceReference: sourceReference, destinationReference: destinationReference,
                rowFieldIndex: rowFieldIndex, dataFieldIndex: dataFieldIndex, aggregation: aggregation,
                refreshOnLoad: refreshOnLoad, sheetIndex: selectedSheetIndex, workbook: workbook, registry: registry)
        } catch {
            status = error.localizedDescription
            return false
        }
        apply(MutationGroup(change: edit.change), forward: true, registeringUndo: true, workbook: &workbook)
        edit.finish(workbook: &workbook)
        self.workbook = workbook
        status = edit.message
        return true
    }

    @discardableResult
    func updatePivotTable(
        id: String,
        name rawName: String,
        sourceReference: String,
        destinationReference: String,
        rowFieldIndex: Int,
        dataFieldIndex: Int,
        aggregation: ExcelPivotAggregation,
        refreshOnLoad: Bool
    ) -> Bool {
        guard allowEditing() else { return false }
        endEditorTextEditing()
        guard !isLargeWorkbook,
              var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return false
        }
        guard workbook.sheets[selectedSheetIndex].pivotTables.contains(where: { $0.id == id }) else {
            return false
        }
        let edit: ExcelPivotEdit
        do {
            guard let updated = try ExcelPivotEditing.updating(
                id: id, name: rawName, sourceReference: sourceReference, destinationReference: destinationReference,
                rowFieldIndex: rowFieldIndex, dataFieldIndex: dataFieldIndex, aggregation: aggregation,
                refreshOnLoad: refreshOnLoad, sheetIndex: selectedSheetIndex, workbook: workbook, registry: registry
            ) else {
                status = ExcelPivotEdit.unchangedMessage
                return false
            }
            edit = updated
        } catch {
            status = error.localizedDescription
            return false
        }
        apply(MutationGroup(change: edit.change), forward: true, registeringUndo: true, workbook: &workbook)
        edit.finish(workbook: &workbook)
        self.workbook = workbook
        status = edit.message
        return true
    }

    func removePivotTable(id: String) {
        guard allowEditing() else { return  }
        endEditorTextEditing()
        guard !isLargeWorkbook,
              var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return 
        }
        guard let edit = ExcelPivotEditing.removing(
            id: id, sheetIndex: selectedSheetIndex, workbook: workbook, registry: registry) else {
            return
        }
        apply(MutationGroup(change: edit.change), forward: true, registeringUndo: true, workbook: &workbook)
        self.workbook = workbook
        status = edit.message
    }











    func updateDrawingPlacement(_ selection: ExcelDrawingSelection, expected: ExcelDrawingAnchor, anchor: ExcelDrawingAnchor) -> Bool {
        guard !isSaving, allowEditing(), !isLargeWorkbook, var book = workbook,
              book.sheets.indices.contains(selectedSheetIndex), book.sheets[selectedSheetIndex].partPath == selection.sheetPath,
              ExcelDrawingEditing.isEditablePlacement(anchor) else { return false }
        endEditorTextEditing()
        switch ExcelDrawingEditing.placing(
            id: selection.id, expected: expected, anchor: anchor, sheetIndex: selectedSheetIndex, in: book) {
        case .notFound:
            return false
        case .unchanged:
            return true
        case .changed(let change, _):
            apply(MutationGroup(change: change), forward: true, registeringUndo: true, workbook: &book)
            workbook = book
            status = ExcelDrawingMessage.placed
            return true
        }
    }

    func updateSheetImageDescription(_ selection: ExcelDrawingSelection, name: String, alternativeText: String) -> Bool {
        guard !isSaving, allowEditing(), !isLargeWorkbook, var book = workbook,
              book.sheets.indices.contains(selectedSheetIndex), book.sheets[selectedSheetIndex].partPath == selection.sheetPath else { return false }
        endEditorTextEditing()
        switch ExcelDrawingEditing.describingImage(
            id: selection.id, name: name, alternativeText: alternativeText, sheetIndex: selectedSheetIndex, in: book) {
        case .notFound:
            return false
        case .unchanged:
            return true
        case .changed(let change, _):
            apply(MutationGroup(change: change), forward: true, registeringUndo: true, workbook: &book)
            workbook = book
            return true
        }
    }




    private func preparedImage(
        _ data: Data,
        preferredContentType: String? = nil
    ) -> ExcelPreparedImage? {
        guard !data.isEmpty,
              data.count <= ExcelPreparedImage.maximumBytes,
              let image = UIImage(data: data) else {
            return nil
        }
        if preferredContentType == "image/jpeg" {
            guard let encoded = image.jpegData(compressionQuality: 0.9) else {
                return nil
            }
            return ExcelPreparedImage(data: encoded, contentType: "image/jpeg", extensionName: "jpg")
        }
        if preferredContentType == "image/png" {
            guard let encoded = image.pngData() else {
                return nil
            }
            return ExcelPreparedImage(data: encoded, contentType: "image/png", extensionName: "png")
        }
        if let detected = ExcelPreparedImage.detecting(data) { return detected }
        guard let encoded = image.pngData() else {
            return nil
        }
        return ExcelPreparedImage(data: encoded, contentType: "image/png", extensionName: "png")
    }


    func applyNumberFormat(
        _ format: ExcelNumberFormat,
        toCurrentColumn: Bool
    ) {
        guard allowEditing() else { return }
        endEditorTextEditing()
        guard var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex),
              let selectedAddress else {
            return
        }
        let sheet = workbook.sheets[selectedSheetIndex]
        let canonicalSelection = sheet.canonicalAddress(
            for: selectedAddress
        )
        let requestedAddresses: [ExcelCellAddress]
        if toCurrentColumn {
            guard let addresses = ExcelSheetPartEditing.columnDataAddresses(selection: canonicalSelection, in: sheet) else {
                return
            }
            requestedAddresses = addresses
        } else {
            guard (selectedRange?.cellCount ?? 1) <= 20000 else { return }
            requestedAddresses = selectedRange?.addresses ?? [canonicalSelection]
        }
        guard let change = ExcelCellEditing.formattingNumbers(
            format, at: requestedAddresses, sheetIndex: selectedSheetIndex, workbook: workbook, registry: registry
        ) else {
            status = AppLocalization.string(
                "선택한 셀에 이미 같은 표시 형식이 적용되어 있습니다."
            )
            return
        }
        apply(MutationGroup(change: change), forward: true, registeringUndo: true, workbook: &workbook)
        self.workbook = workbook
        syncEditorText(using: workbook.sheets[selectedSheetIndex])
        status = toCurrentColumn
            ? AppLocalization.format(
                "현재 열의 %lld개 데이터 셀을 %@ 표시 형식으로 바꿨습니다.",
                change.cells.count,
                format.title
            )
            : AppLocalization.format(
                "%@ 셀을 %@ 표시 형식으로 바꿨습니다.",
                canonicalSelection.reference,
                format.title
            )
    }

    func rowFields(
        for row: Int,
        columns: [ExcelAccessibleColumn]
    ) -> [RowField] {
        guard let sheet = selectedSheet else {
            return []
        }
        return ExcelAccessibleRows.fields(row: row, columns: columns, sheet: sheet).map { field in
            RowField(
                id: field.column, column: field.column, title: field.title, value: field.value,
                originalValue: field.value, dropdownValues: field.dropdownValues,
                dropdownAllowsBlank: field.dropdownAllowsBlank)
        }
    }

    func rowFieldsForAppending() -> [RowField] {
        guard let sheet = selectedSheet else {
            return []
        }
        return ExcelAccessibleRows.appendingFields(near: selectedAddress, sheet: sheet).map {
            RowField(id: $0.column, column: $0.column, title: $0.title, value: "")
        }
    }

    func updateRow(
        _ row: Int,
        fields: [RowField]
    ) {
        guard allowEditing() else { return }
        endEditorTextEditing()
        guard var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return
        }
        guard let change = ExcelRowEditing.updating(
            row: row,
            values: fields.filter { $0.value != $0.originalValue }.map { ($0.column, $0.value) },
            sheetIndex: selectedSheetIndex, workbook: workbook, registry: registry
        ) else {
            return
        }
        apply(MutationGroup(change: change), forward: true, registeringUndo: true, workbook: &workbook)
        self.workbook = workbook
        selectedAddress = change.cells.first?.address
        syncEditorText(using: workbook.sheets[selectedSheetIndex])
        status = AppLocalization.format(
            "%lld행의 %lld개 값을 수정했습니다. 저장하면 XLSX 파일에 반영됩니다.",
            row,
            change.cells.count
        )
    }

    func appendRow(fields: [RowField]) {
        guard allowEditing() else { return }
        endEditorTextEditing()
        guard var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return
        }
        let sheet = workbook.sheets[selectedSheetIndex]
        let appended: ExcelRowEditing.Appended
        do {
            guard let result = try ExcelRowEditing.appending(
                values: fields.map { ($0.column, $0.value) }, near: selectedAddress,
                sheetIndex: selectedSheetIndex, workbook: workbook, registry: registry
            ) else { return }
            appended = result
        } catch {
            status = AppLocalization.string(
                "Excel의 최대 행 수를 초과해 행을 추가할 수 없습니다."
            )
            return
        }
        let newRow = appended.row
        apply(MutationGroup(change: appended.change), forward: true, registeringUndo: true, workbook: &workbook)
        appended.finish(workbook: &workbook)
        self.workbook = workbook
        if isLargeWorkbook {
            largeAddedRows[sheet.partPath, default: []].insert(newRow)
            largeWindowRows[sheet.partPath, default: []].append(newRow)
            largeWindowRows[sheet.partPath]?.sort()
        }
        selectedAddress = ExcelCellAddress(
            row: newRow,
            column: appended.change.cells.first?.address.column ?? 1
        )
        syncEditorText(using: workbook.sheets[selectedSheetIndex])
        status = AppLocalization.format(
            "%lld행을 추가했습니다. 저장하면 XLSX 파일에 반영됩니다.",
            newRow
        )
    }

    var selectedRange: ExcelCellRange? {
        guard let selectedAddress else { return nil }
        if selectionEnd == nil, let merged = selectedSheet?.mergedRange(containing: selectedAddress) { return merged }
        return ExcelCellRange(start: selectedAddress, end: selectionEnd ?? selectedAddress)
    }

    var editingRange: ExcelCellRange? {
        guard let range = selectedRange, let sheet = selectedSheet else { return nil }
        if range.cellCount > 1 { return range }
        if let table = sheet.table(containing: range.start) { return table.range }
        if let region = ExcelAccessibilityAnalyzer.regions(in: sheet).first(where: { $0.contains(range.start) }),
           let firstColumn = region.columns.map(\.column).min(), let lastColumn = region.columns.map(\.column).max() {
            let rows = region.rowNumbers + [region.headerRow].compactMap { $0 }
            return ExcelCellRange(start: ExcelCellAddress(row: rows.min() ?? range.start.row, column: firstColumn), end: ExcelCellAddress(row: rows.max() ?? range.end.row, column: lastColumn))
        }
        return range
    }

    @discardableResult func selectRange(_ reference: String) -> Bool {
        guard !isSaving, let range = ExcelCellRange(reference), range.end.row <= 1048576, range.end.column <= 16384 else {
            status = AppLocalization.string("A1:D10처럼 올바른 셀 범위를 입력해 주세요."); return false
        }
        selectRange(from: range.start, to: range.end)
        return true
    }

    func selectRange(from start: ExcelCellAddress, to end: ExcelCellAddress) {
        guard !isSaving, let sheet = selectedSheet else { return }
        endEditorTextEditing()
        let range = ExcelCellRange(start: start, end: end).includingMergedCells(in: sheet)
        selectedAddress = range.start; selectionEnd = range.end
        selectedDrawingID = nil
        syncEditorText(using: sheet)
    }

    func selectEntireRow(_ row: Int) {
        selectRange(from: ExcelCellAddress(row: row, column: 1), to: ExcelCellAddress(row: row, column: max(selectedSheet?.maximumColumn ?? 1, 1)))
    }

    func selectEntireColumn(_ column: Int) {
        selectRange(from: ExcelCellAddress(row: 1, column: column), to: ExcelCellAddress(row: max(selectedSheet?.maximumRow ?? 1, 1), column: column))
    }

    func copySelection(cutting: Bool = false) {
        guard !isSaving, let range = selectedRange, let sheet = selectedSheet else { return }
        guard range.cellCount <= 20000 else { status = AppLocalization.string("한 번에 복사할 범위는 20,000셀 이하로 선택해 주세요."); return }
        if isLargeWorkbook && !(range.start.row ... range.end.row).allSatisfy({ selectedLargeWindowRows.contains($0) }) {
            status = AppLocalization.string("대용량 문서는 현재 표시된 행 범위에서 복사해 주세요."); return
        }
        if cutting && (!canEditSelectedSheet || isLargeWorkbook) { status = AppLocalization.string("이 시트에서는 잘라내기를 사용할 수 없습니다."); return }
        var values: [[ExcelClipboardValue]] = [], strings: [[String]] = []
        for row in range.start.row ... range.end.row {
            values.append((range.start.column ... range.end.column).map { column in
                let cell = sheet.cells[ExcelCellAddress(row: row, column: column)]
                return ExcelClipboardValue(text: cell?.editText ?? "", styleIndex: cell?.styleIndex, input: cell.map { input(preserving: $0) } ?? .blank)
            })
            strings.append((range.start.column ... range.end.column).map { sheet.cells[ExcelCellAddress(row: row, column: $0)]?.displayValue ?? "" })
        }
        UIPasteboard.general.string = ExcelTabularClipboard.encode(strings)
        rangeClipboard = ExcelRangeClipboard(range: range, sheetIndex: selectedSheetIndex, values: values, isCut: cutting, changeCount: UIPasteboard.general.changeCount)
        status = AppLocalization.string(cutting ? "잘라낼 범위를 기억했습니다. 붙여넣으면 원래 위치가 비워집니다." : "선택 범위를 복사했습니다.")
    }

    func pasteSelection() { pasteSelection(using: nil) }

    private func pasteSelection(using supplied: ExcelRangeClipboard?) {
        guard allowEditing(), !isLargeWorkbook, let target = selectedAddress, let original = workbook else { return }
        guard let text = supplied == nil ? UIPasteboard.general.string : "" else { status = AppLocalization.string("붙여넣을 표나 텍스트가 없습니다."); return }
        let clip = supplied ?? (rangeClipboard?.changeCount == UIPasteboard.general.changeCount ? rangeClipboard : nil)
        let values = clip?.values ?? ExcelTabularClipboard.decode(text).map { $0.map { ExcelClipboardValue(text: $0, styleIndex: nil) } }
        let plan: (updates: [Int: [ExcelCellAddress: ExcelClipboardValue]], destination: ExcelCellRange)
        do {
            plan = try ExcelRangeOperations.pasting(
                values, clipboard: clip, at: target, selection: selectedRange, sheetIndex: selectedSheetIndex, in: original)
        } catch .destinationTooLarge {
            status = AppLocalization.string("붙여넣을 범위가 너무 큽니다."); return
        } catch .cutSourceChanged {
            status = AppLocalization.string("잘라낼 원본이 변경되었습니다. 범위를 다시 선택해 주세요."); return
        } catch .crossSheetFormulaCut {
            status = AppLocalization.string("수식이 포함된 범위의 시트 간 잘라내기는 복사·붙여넣기를 사용해 주세요."); return
        } catch {
            return
        }
        if applyRangeUpdates(plan.updates) {
            selectedAddress = target; selectionEnd = plan.destination.end
            if clip?.isCut == true { rangeClipboard = nil }
            status = AppLocalization.string("선택한 위치에 붙여넣었습니다.")
        }
    }

    func clearSelection() {
        guard let range = selectedRange, range.cellCount <= ExcelRangeOperations.maximumCells else { return }
        if range.cellCount == 1 || selectedSheet?.mergedRange(containing: range.start) == range { clearSelectedCell(); return }
        guard let sheet = selectedSheet, let updates = ExcelRangeOperations.clearing(range, in: sheet) else { return }
        if applyRangeUpdates([selectedSheetIndex: updates]) { status = AppLocalization.string("선택 범위의 값을 지웠습니다.") }
    }

    func fillSelection(across: Bool) {
        guard let range = selectedRange, let sheet = selectedSheet,
              let updates = ExcelRangeOperations.filling(range, in: sheet, across: across) else { return }
        if applyRangeUpdates([selectedSheetIndex: updates]) { status = AppLocalization.string("선택 범위를 채웠습니다.") }
    }

    @discardableResult private func applyRangeUpdates(_ updates: [Int: [ExcelCellAddress: ExcelClipboardValue]]) -> Bool {
        guard allowEditing(), !isLargeWorkbook, var next = workbook else { return false }
        do {
            try ExcelRangeOperations.validate(updates, in: next)
        } catch .tooManyCellsOrEmpty {
            status = AppLocalization.string("한 번에 편집할 범위는 20,000셀 이하로 선택해 주세요."); return false
        } catch {
            endEditorTextEditing()
            status = error == .uneditableSheet
                ? AppLocalization.string("편집할 수 없는 시트가 포함되어 있습니다.")
                : AppLocalization.string("병합 셀이나 배열 수식이 포함된 범위는 이 작업을 사용할 수 없습니다.")
            return false
        }
        endEditorTextEditing()
        let old = captureEditingState(next)
        for (index, values) in updates.sorted(by: { $0.key < $1.key }) {
            let mutations = ExcelRangeOperations.mutations(for: values, sheetIndex: index, workbook: &next, registry: &registry)
            _ = apply(MutationGroup(sheetIndex: index, cells: mutations), forward: true, registeringUndo: false, workbook: &next)
        }
        let new = captureEditingState(next)
        undoStack.append(MutationGroup(sheetIndex: selectedSheetIndex, cells: [], oldDocumentState: old, newDocumentState: new))
        redoStack.removeAll(); workbook = next; aiReferences = nil
        if let sheet = selectedSheet { syncEditorText(using: sheet); updateValidationWarning(in: sheet) }
        updateHistoryState(); return true
    }

    var findResults: [ExcelCellAddress] {
        guard let sheet = selectedSheet, !findText.isEmpty else { return [] }
        return ExcelRangeOperations.finding(findText, in: sheet)
    }

    func findNext() {
        let results = findResults
        guard !results.isEmpty else { status = AppLocalization.string("찾는 값이 없습니다."); return }
        let next = results.first { selectedAddress == nil || $0 > selectedAddress! } ?? results[0]
        selectCell(next); navigationRevealAddress = next
        status = AppLocalization.format("%@ 셀을 찾았습니다.", next.reference)
    }

    func replaceFound(all: Bool, replacement: String) {
        guard !findText.isEmpty, let sheet = selectedSheet else { return }
        let addresses = all ? findResults : selectedAddress.map { [$0] } ?? []
        let updates = ExcelRangeOperations.replacing(findText, with: replacement, at: addresses, in: sheet)
        if !updates.isEmpty, applyRangeUpdates([selectedSheetIndex: updates]) { status = AppLocalization.string("찾은 내용을 바꿨습니다.") }
    }

    private func captureEditingState(_ workbook: ExcelWorkbook) -> EditingState {
        EditingState(workbook: workbook,
            selectedSheetPath: selectedSheet?.partPath,
            selectedAddress: selectedAddress,
            selectionEnd: selectionEnd,
            selectedDrawingID: selectedDrawingID,
            editingBaseData: editingBaseData,
            edits: edits,
            styleEdits: styleEdits,
            originalDataValidations: originalDataValidations,
            validationEdits: validationEdits,
            originalConditionalFormatting: originalConditionalFormatting,
            conditionalFormattingEdits: conditionalFormattingEdits,
            differentialStyleEdits: differentialStyleEdits,
            originalAnnotations: originalAnnotations,
            annotationEdits: annotationEdits,
            originalDrawingObjects: originalDrawingObjects,
            drawingObjectEdits: drawingObjectEdits,
            originalPivotTables: originalPivotTables,
            pivotTableEdits: pivotTableEdits)
    }

    private func restoreEditingState(_ state: EditingState, workbook: inout ExcelWorkbook) {
        workbook = state.workbook
        selectedSheetIndex = workbook.sheets.firstIndex(where: { $0.partPath == state.selectedSheetPath }) ?? 0
        selectedAddress = state.selectedAddress
        selectedDrawingID = state.selectedDrawingID
        rangeClipboard = nil
        editingBaseData = state.editingBaseData
        edits = state.edits
        styleEdits = state.styleEdits
        originalDataValidations = state.originalDataValidations
        validationEdits = state.validationEdits
        originalConditionalFormatting = state.originalConditionalFormatting
        conditionalFormattingEdits = state.conditionalFormattingEdits
        differentialStyleEdits = state.differentialStyleEdits
        originalAnnotations = state.originalAnnotations
        annotationEdits = state.annotationEdits
        originalDrawingObjects = state.originalDrawingObjects
        drawingObjectEdits = state.drawingObjectEdits
        originalPivotTables = state.originalPivotTables
        pivotTableEdits = state.pivotTableEdits
        aiReferences = nil
        selectionEnd = state.selectionEnd
    }

    @discardableResult
    func performSheetEdit(_ edit: ExcelSheetEdit) async -> Bool {
        guard canManageSheets, let original = workbook, let active = selectedSheet?.partPath else {
            if let restriction = sheetManagementRestriction { status = restriction }
            return false
        }
        endEditorTextEditing()
        let old = captureEditingState(original)
        isSaving = true
        errorDescription = nil
        status = AppLocalization.string("시트를 변경하는 중…")
        defer { isSaving = false }
        do {
            let source = editingBaseData ?? sourceData
            let registry = registry
            let result = try await Task.detached(priority: .userInitiated) {
                try ExcelStructuralEditing.applying(
                    edit, source: source, workbook: original, registry: registry, selectedSheetPath: active)
            }.value
            guard result.changed else { status = AppLocalization.string("변경할 내용이 없습니다."); return true }
            installEditingBase(result.0.data, workbook: result.1)
            workbook = result.1
            selectedSheetIndex = result.1.sheets.firstIndex { $0.partPath == result.0.selectedSheetPath } ?? 0
            if result.0.selectedSheetPath != active { selectedAddress = selectedSheet.flatMap { initialAddress(in: $0) } }
            selectionEnd = nil; navigationRevealAddress = selectedAddress
            aiReferences = nil; findText = ""; rangeClipboard = nil
            let next = captureEditingState(result.1)
            undoStack.append(MutationGroup(sheetIndex: selectedSheetIndex, cells: [], oldDocumentState: old, newDocumentState: next))
            redoStack.removeAll()
            if let sheet = selectedSheet {
                syncEditorText(using: sheet); updateValidationWarning(in: sheet); updateFormulaSupportSummary(in: sheet)
            }
            updateHistoryState()
            status = AppLocalization.string("시트를 변경했습니다. 실행 취소로 되돌릴 수 있습니다.")
            return true
        } catch {
            status = error.localizedDescription; errorDescription = error.localizedDescription
            return false
        }
    }

    private func installEditingBase(_ data: Data, workbook: ExcelWorkbook) {
        editingBaseData = data
        registry.rebaseline(to: workbook)
    }

    @discardableResult
    func performAdvancedEdit(_ edit: ExcelAdvancedEdit) async -> Bool {
        guard allowEditing(), !isLargeWorkbook, let original = workbook else { return false }
        endEditorTextEditing()
        isSaving = true
        errorDescription = nil
        status = AppLocalization.string("편집을 적용하는 중…")
        defer { isSaving = false }
        do {
            let old = captureEditingState(original)
            let source = editingBaseData ?? sourceData
            let registry = registry
            let sheetIndex = selectedSheetIndex
            let result = try await Task.detached(priority: .userInitiated) {
                try ExcelStructuralEditing.applying(
                    edit, source: source, workbook: original, registry: registry, sheetIndex: sheetIndex)
            }.value
            installEditingBase(result.0, workbook: result.1)
            let next = captureEditingState(result.1)
            undoStack.append(MutationGroup(sheetIndex: sheetIndex, cells: [], oldDocumentState: old, newDocumentState: next))
            redoStack.removeAll()
            workbook = result.1
            if case .structure(let change) = edit, let address = selectedAddress {
                selectedAddress = change.address(address) ?? ExcelCellAddress(row: change.axis == .row ? change.index : address.row, column: change.axis == .column ? change.index : address.column)
                selectionEnd = nil
            }
            switch edit {
            case .merge(let requested, _, _):
                let range = requested.includingMergedCells(in: original.sheets[sheetIndex])
                selectedAddress = range.start; selectionEnd = range.end
                navigationRevealAddress = range.start
            case .unmerge(let range):
                let expanded = range.includingMergedCells(in: original.sheets[sheetIndex])
                selectedAddress = expanded.start; selectionEnd = expanded.end
                navigationRevealAddress = expanded.start
            default: break
            }
            aiReferences = nil
            if let sheet = selectedSheet { syncEditorText(using: sheet); updateValidationWarning(in: sheet) }
            updateHistoryState()
            status = AppLocalization.string("편집을 적용했습니다. 실행 취소로 되돌릴 수 있습니다.")
            return true
        } catch {
            status = error.localizedDescription
            errorDescription = error.localizedDescription
            return false
        }
    }

    func undo() {
        guard !isSaving else { return }
        endEditorTextEditing()
        guard var workbook,
              let group = undoStack.popLast() else {
            return
        }
        apply(
            group,
            forward: false,
            registeringUndo: false,
            workbook: &workbook
        )
        redoStack.append(group)
        self.workbook = workbook
        syncAfterHistoryChange()
    }

    func redo() {
        guard !isSaving else { return }
        endEditorTextEditing()
        guard var workbook,
              let group = redoStack.popLast() else {
            return
        }
        apply(
            group,
            forward: true,
            registeringUndo: false,
            workbook: &workbook
        )
        undoStack.append(group)
        self.workbook = workbook
        syncAfterHistoryChange()
    }

    private var autosaveDelay: Duration {
        autosaveDelayOverride
            ?? (isLargeWorkbook ? .seconds(2) : .milliseconds(900))
    }

    private func cancelAutosaveDebounce() {
        autosaveDebounceTask?.cancel()
        autosaveDebounceTask = nil
    }

    private func scheduleAutosave() {
        guard didLoad, !isLoading, hasUnsavedChanges else {
            cancelAutosaveDebounce()
            return
        }
        cancelAutosaveDebounce()
        let delay = autosaveDelay
        autosaveDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.autosaveDebounceTask = nil
            await self.startAutosave()
        }
    }

    private func startAutosave() async {
        guard autosaveWriteTask == nil,
              !isSaving,
              hasUnsavedChanges else {
            return
        }
        let task = Task { [weak self] in
            guard let self else { return false }
            return await self.save(
                preservingHistory: true,
                automatic: true
            )
        }
        autosaveWriteTask = task
        let succeeded = await task.value
        autosaveWriteTask = nil
        if succeeded, hasUnsavedChanges {
            scheduleAutosave()
        }
    }

    @discardableResult
    func flushAutosave() async -> Bool {
        commitEditorText()
        cancelAutosaveDebounce()
        if let autosaveWriteTask {
            _ = await autosaveWriteTask.value
        }
        guard hasUnsavedChanges else { return true }
        return await save(
            preservingHistory: true,
            automatic: true
        )
    }

    @discardableResult
    func save(
        preservingHistory: Bool = false,
        automatic: Bool = false
    ) async -> Bool {
        if !automatic {
            commitEditorText()
            cancelAutosaveDebounce()
            if let autosaveWriteTask {
                _ = await autosaveWriteTask.value
            }
        }
        guard !isSaving,
              !isAutosaving,
              let workbook else {
            return false
        }
        if automatic {
            guard hasUnsavedChanges else { return true }
            isAutosaving = true
        } else {
            isSaving = true
        }
        errorDescription = nil
        status = AppLocalization.string(
            automatic ? "자동 저장 중…" : "XLSX 저장 중…"
        )
        let savedHistoryIDs = undoStack.map(\.id)
        do {
            let inputData = editingBaseData ?? sourceData
            let expectedFileData = lastAutosavedData ?? sourceData
            let pendingEdits = registry
            let destination = fileURL
            let writeContents = writeContents
            let preflight = largeWorkbookPreflight
            let savedResult = try await Task.detached(
                priority: .userInitiated
            ) {
                let data = try pendingEdits.applying(to: inputData, workbook: workbook)
                try writeContents(destination, data, expectedFileData)
                let cache: ExcelLargeWorkbookCache?
                if let preflight {
                    let directoryURL = FileManager.default
                        .temporaryDirectory
                        .appendingPathComponent(
                            "VisionCraft-Large-XLSX-\(UUID().uuidString)",
                            isDirectory: true
                        )
                    cache = try? ExcelWorkbookDocument.buildLargeCache(
                        from: data,
                        preflight: preflight,
                        directoryURL: directoryURL
                    )
                    if cache == nil {
                        try? FileManager.default.removeItem(at: directoryURL)
                    }
                } else {
                    cache = nil
                }
                return (data, cache)
            }.value
            if preservingHistory {
                lastAutosavedData = savedResult.0
                autosavedHistoryIDs = savedHistoryIDs
            } else {
                sourceData = savedResult.0
                editingBaseData = nil
                lastAutosavedData = nil
                autosavedHistoryIDs = nil
            }
            if let oldDirectory = largeWorkbookCache?.directoryURL,
               oldDirectory != savedResult.1?.directoryURL {
                try? FileManager.default.removeItem(at: oldDirectory)
            }
            largeWorkbookCache = savedResult.1
            if let originalDocumentID {
                try? await RecentOriginalDocumentStore
                    .shared
                    .refreshBookmark(
                        id: originalDocumentID,
                        fileURL: fileURL
                    )
            }
            if !preservingHistory {
                registry.rebaseline(to: workbook)
                undoStack.removeAll()
                redoStack.removeAll()
            }
            updateHistoryState()
            status = AppLocalization.string(
                automatic
                    ? "자동 저장됨"
                    : (isOriginalDocument
                        ? "원본 XLSX 문서에 저장했습니다."
                        : "XLSX 문서를 저장했습니다.")
            )
            if automatic {
                isAutosaving = false
            } else {
                isSaving = false
            }
            return true
        } catch {
            errorDescription = error.localizedDescription
            status = AppLocalization.format(
                automatic
                    ? "자동 저장하지 못했습니다: %@"
                    : "저장하지 못했습니다: %@",
                error.localizedDescription
            )
            if automatic {
                isAutosaving = false
            } else {
                isSaving = false
            }
            return false
        }
    }

    func exportData() async throws -> Data {
        guard let workbook else {
            throw ExcelWorkbookDocumentError.cannotSave
        }
        let sourceData = editingBaseData ?? sourceData
        let registry = registry
        return try await Task.detached(priority: .userInitiated) {
            try registry.applying(to: sourceData, workbook: workbook)
        }.value
    }

    func requestAccessibilityFocus() {
        accessibilityFocusRequestID &+= 1
    }

    func accessibilityWorkbookSummary() -> String? {
        guard let workbook,
              let sheet = selectedSheet else {
            return nil
        }
        return AppLocalization.format(
            "%@ 문서를 열었습니다. %lld개 시트. %@",
            fileURL.deletingPathExtension().lastPathComponent,
            workbook.sheets.count,
            accessibilitySummary(for: sheet)
        )
    }

    func makeAISnapshot() -> ExcelAIWorkbookSnapshot? {
        guard let workbook else {
            return nil
        }
        return ExcelAISnapshotBuilder.make(
            workbookName: fileURL
                .deletingPathExtension()
                .lastPathComponent,
            workbook: workbook,
            selectedSheetIndex: selectedSheetIndex,
            selectedAddress: selectedAddress,
            supportsEdits: !isLargeWorkbook,
            selectedRange: selectedRange,
            selectedDrawingID: selectedDrawingID
        )
    }

    func makeAISnapshot(
        for request: String
    ) async throws -> ExcelAIWorkbookSnapshot? {
        guard isLargeWorkbook else {
            return makeAISnapshot()
        }
        guard var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex),
              let summary = selectedLargeSheetSummary else {
            return nil
        }

        let sheetIndex = selectedSheetIndex
        let baseSheet = workbook.sheets[sheetIndex]
        let partPath = summary.partPath
        let cachedSheet = largeWorkbookCache?.sheet(partPath: partPath)
        let data = sourceData
        let terms = ExcelLargeAIQueryTokenizer.terms(in: request)
        let perTermResultLimit = 501

        let searchResult = try await Task.detached(
            priority: .userInitiated
        ) { () -> ([Int: Int], Bool) in
            var scores = [Int: Int]()
            var reachedResultLimit = false
            for term in terms {
                let rows: [Int]
                if let cachedSheet {
                    rows = try cachedSheet.searchRows(
                        query: term,
                        maximumResults: perTermResultLimit
                    )
                } else {
                    rows = try ExcelWorkbookDocument.searchRows(
                        in: data,
                        sheetPartPath: partPath,
                        query: term,
                        maximumResults: perTermResultLimit
                    )
                }
                if rows.count == perTermResultLimit {
                    reachedResultLimit = true
                }
                for row in rows {
                    scores[row, default: 0] += 1
                }
            }
            return (scores, reachedResultLimit)
        }.value

        var rowScores = searchResult.0
        for (address, edit) in edits[partPath] ?? [:] {
            let text = searchableText(for: edit.input)
            let score = terms.reduce(into: 0) { result, term in
                if text.localizedCaseInsensitiveContains(term) {
                    result += 1
                }
            }
            if score > 0 {
                rowScores[address.row] = max(
                    rowScores[address.row] ?? 0,
                    score
                )
            }
        }

        let relevantColumnCount = max(
            1,
            min(summary.maximumColumn, 100)
        )
        let maximumRetrievedRows = max(
            5,
            min(
                100,
                1_000 / relevantColumnCount
            )
        )
        let rankedRows = rowScores.keys.sorted { lhs, rhs in
            let leftScore = rowScores[lhs] ?? 0
            let rightScore = rowScores[rhs] ?? 0
            return leftScore == rightScore
                ? lhs < rhs
                : leftScore > rightScore
        }
        let retrievedRows = Array(
            rankedRows.prefix(maximumRetrievedRows)
        )
        let fallbackRows = retrievedRows.isEmpty
            ? selectedLargeWindowRows
            : []
        var includedRows = Set(
            summary.populatedRows.prefix(
                ExcelWorkbookDocument.largeContextRowCount
            )
        )
        includedRows.formUnion(summary.tableHeaderRows)
        includedRows.formUnion(retrievedRows)
        includedRows.formUnion(fallbackRows)
        if let selectedAddress {
            includedRows.insert(selectedAddress.row)
        }

        var loaded = try await Task.detached(
            priority: .userInitiated
        ) {
            if let cachedSheet {
                var sheet = baseSheet
                sheet.cells = try cachedSheet.cells(in: includedRows)
                sheet.maximumRow = summary.maximumRow
                sheet.maximumColumn = summary.maximumColumn
                sheet.isWindowed = true
                return sheet
            }
            return try ExcelWorkbookDocument.loadSheetWindow(
                from: data,
                summary: summary,
                includedRows: includedRows
            )
        }.value
        reapplyCurrentEdits(
            to: &loaded,
            includedRows: includedRows
        )
        workbook.sheets[sheetIndex] = loaded

        return ExcelAISnapshotBuilder.make(
            workbookName: fileURL
                .deletingPathExtension()
                .lastPathComponent,
            workbook: workbook,
            selectedSheetIndex: sheetIndex,
            selectedAddress: selectedAddress,
            supportsEdits: false,
            searchedWholeSheet: true,
            searchTerms: terms,
            searchResultRowCount: rowScores.count,
            searchResultsWereTruncated: searchResult.1
                || rankedRows.count > retrievedRows.count,
            retrievedRows: retrievedRows
        )
    }

    @discardableResult
    func applyAIPlan(
        _ plan: ExcelAIValidatedPlan
    ) throws -> String {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        guard plan.workbookOperations.isEmpty else { throw ExcelAICommandValidationError.invalidAction }
        endEditorTextEditing()
        guard var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex),
              let currentSnapshot = makeAISnapshot(),
              currentSnapshot.sheetPartPath == plan.sheetPartPath,
              currentSnapshot.revision == plan.sourceRevision else {
            throw ExcelAIApplyError.staleProposal
        }

        let sheetIndex = selectedSheetIndex
        let edit = try ExcelAIPlanApplication.edit(
            plan, sheetIndex: sheetIndex, workbook: workbook, registry: registry)
        apply(
            MutationGroup(change: edit.change),
            forward: true,
            registeringUndo: true,
            workbook: &workbook
        )
        edit.finish(workbook: &workbook)

        self.workbook = workbook
        selectedAddress = edit.focusAddress
        syncEditorText(using: workbook.sheets[sheetIndex])
        updateValidationWarning(in: workbook.sheets[sheetIndex])
        requestAccessibilityFocus()
        let message = AppLocalization.format(
            "AI 요청으로 %lld개 변경을 적용했습니다. 저장하면 XLSX 파일에 반영됩니다.",
            plan.changeCount
        )
        status = message
        return message
    }

    private func setCell(
        at requestedAddress: ExcelCellAddress,
        userText: String,
        coalescingEditorChanges: Bool = false,
        synchronizingEditorText: Bool = true
    ) {
        guard allowEditing() else { return }
        guard var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return
        }
        let change: ExcelDocumentChange
        do {
            guard let typed = try ExcelCellEditing.typing(
                userText, at: requestedAddress, sheetIndex: selectedSheetIndex, workbook: workbook, registry: registry
            ) else { return }
            change = typed
        } catch {
            guard case .spilledResult(let owner) = error else { return }
            let address = workbook.sheets[selectedSheetIndex].canonicalAddress(for: requestedAddress)
            editorText = workbook.sheets[selectedSheetIndex].cells[address]?.displayValue ?? ""
            status = AppLocalization.format(
                "%@은(는) %@ 수식의 Spill 결과입니다. 원본 셀에서 수정해 주세요.",
                address.reference,
                owner.reference
            )
            return
        }
        let address = change.cells[0].address
        let group = MutationGroup(change: change)
        if coalescingEditorChanges,
           let session = editorMutationSession,
           session.sheetIndex == selectedSheetIndex,
           session.address == address,
           session.undoStackIndex == undoStack.count - 1,
           undoStack.indices.contains(session.undoStackIndex) {
            // Live keystrokes update the sheet immediately, but remain one
            // logical edit when the user invokes Undo.
            let initialGroup = undoStack[session.undoStackIndex]
            let appliedGroup = apply(
                group,
                forward: true,
                registeringUndo: false,
                workbook: &workbook
            )
            undoStack[session.undoStackIndex] = coalescing(
                initialGroup,
                with: appliedGroup
            )
            redoStack.removeAll()
            updateHistoryState()
        } else {
            endEditorTextEditing()
            apply(
                group,
                forward: true,
                registeringUndo: true,
                workbook: &workbook
            )
            if coalescingEditorChanges {
                editorMutationSession = EditorMutationSession(
                    sheetIndex: selectedSheetIndex,
                    address: address,
                    undoStackIndex: undoStack.count - 1
                )
            }
        }
        ExcelCellEditing.extendUsedRange(to: address, sheetIndex: selectedSheetIndex, workbook: &workbook)
        self.workbook = workbook
        if synchronizingEditorText {
            editorText = workbook.sheets[selectedSheetIndex]
                .cell(at: address)?.editText ?? ""
        }
        updateValidationWarning(in: workbook.sheets[selectedSheetIndex])
        status = AppLocalization.format(
            "%@ 셀을 수정했습니다. 저장하면 XLSX 파일에 반영됩니다.%@",
            address.reference,
            formulaRecalculationStatusSuffix
        )
    }

    private func makeMutation(
        address: ExcelCellAddress,
        input: ExcelCellInput,
        styleIndex: Int?,
        sheet: ExcelWorksheet,
        workbook styleSource: ExcelWorkbook? = nil
    ) -> CellMutation {
        ExcelCellEditing.mutation(
            address: address, input: input, styleIndex: styleIndex, sheet: sheet,
            workbook: styleSource ?? workbook, registry: registry)
    }

    private func resolvedUserInput(
        _ userText: String,
        styleIndex: Int?,
        workbook: inout ExcelWorkbook
    ) -> (input: ExcelCellInput, styleIndex: Int?) {
        ExcelCellEditing.resolvedInput(userText, styleIndex: styleIndex, workbook: &workbook, registry: &registry)
    }

    private func cell(
        address: ExcelCellAddress,
        input: ExcelCellInput,
        styleIndex: Int?,
        workbook styleSource: ExcelWorkbook? = nil
    ) -> ExcelCell? {
        ExcelCellEditing.cell(address: address, input: input, styleIndex: styleIndex, workbook: styleSource ?? workbook)
    }

    @discardableResult
    private func apply(
        _ group: MutationGroup,
        forward: Bool,
        registeringUndo: Bool,
        workbook: inout ExcelWorkbook
    ) -> MutationGroup {
        if let state = forward ? group.newDocumentState : group.oldDocumentState {
            restoreEditingState(state, workbook: &workbook)
            if registeringUndo { undoStack.append(group); redoStack.removeAll() }
            updateHistoryState()
            return group
        }
        guard workbook.sheets.indices.contains(group.sheetIndex) else {
            return group
        }
        let applied = group.change.apply(
            forward: forward, workbook: &workbook, registry: &registry, recalculate: !isLargeWorkbook)
        if let count = applied.recalculatedCount {
            lastFormulaRecalculationCount = count
            unsupportedFormulaCount = applied.unsupportedFormulaCount ?? 0
        } else if !forward {
            lastFormulaRecalculationCount = 0
        }
        if !group.cells.isEmpty, !isLargeWorkbook {
            lastFormulaRecalculationCount += applied.derivedRecalculatedCount
        }
        // Recalculated formula cells join the undo entry; otherwise keep it as is.
        let effectiveGroup = (applied.recalculatedCount ?? 0) > 0 ? MutationGroup(change: applied.change) : group
        if registeringUndo {
            undoStack.append(effectiveGroup)
            redoStack.removeAll()
        }
        updateHistoryState()
        return effectiveGroup
    }


    private func refreshDerivedFormulaValues(
        excluding excludedSheetIndex: Int? = nil,
        in workbook: inout ExcelWorkbook
    ) -> Int {
        guard !isLargeWorkbook else { return 0 }
        return Self.refreshDerivedFormulaValues(
            excluding: excludedSheetIndex, in: &workbook, edits: edits
        )
    }

    private nonisolated static func refreshDerivedFormulaValues(
        excluding excludedSheetIndex: Int? = nil,
        in workbook: inout ExcelWorkbook,
        edits: [String: [ExcelCellAddress: ExcelCellEdit]]
    ) -> Int {
        ExcelRecalculation.refreshDerivedValues(excluding: excludedSheetIndex, in: &workbook, edits: edits)
    }




    private func coalescing(
        _ initial: MutationGroup,
        with latest: MutationGroup
    ) -> MutationGroup {
        MutationGroup(change: initial.change.coalescing(with: latest.change))
    }

    private var formulaRecalculationStatusSuffix: String {
        guard lastFormulaRecalculationCount > 0 else { return "" }
        return AppLocalization.format(
            " 수식 %lld개를 다시 계산했습니다.",
            lastFormulaRecalculationCount
        )
    }

    private func updateFormulaSupportSummary(in sheet: ExcelWorksheet) {
        guard !isLargeWorkbook, let workbook else {
            unsupportedFormulaCount = 0
            return
        }
        unsupportedFormulaCount = ExcelFormulaCalculator.recalculate(
            cells: sheet.cells,
            styles: workbook.styles,
            uses1904DateSystem: workbook.uses1904DateSystem,
            mergedRanges: sheet.mergedRanges,
            tableRanges: sheet.tables.map(\.range),
            workbook: workbook,
            currentSheetName: sheet.name
        ).unsupportedFormulaCount
    }

    private func syncAfterHistoryChange() {
        selectionEnd = nil
        navigationRevealAddress = nil
        updateHistoryState()
        if let sheet = selectedSheet {
            syncEditorText(using: sheet)
            updateValidationWarning(in: sheet)
        }
        status = AppLocalization.string(
            hasUnsavedChanges
                ? "저장되지 않은 변경 사항이 있습니다."
                : "모든 변경 사항을 되돌렸습니다."
        )
    }

    private func endEditorTextEditing() {
        editorMutationSession = nil
    }

    private func updateHistoryState() {
        if let autosavedHistoryIDs {
            hasUnsavedChanges = undoStack.map(\.id) != autosavedHistoryIDs
        } else {
            hasUnsavedChanges = editingBaseData != nil || !edits.isEmpty || !validationEdits.isEmpty
                || !conditionalFormattingEdits.isEmpty
                || !annotationEdits.isEmpty
                || !drawingObjectEdits.isEmpty
                || !pivotTableEdits.isEmpty
        }
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        if hasUnsavedChanges {
            scheduleAutosave()
        } else {
            cancelAutosaveDebounce()
        }
    }









    private func differentialStyleIndex(
        for style: ExcelDifferentialStyle,
        workbook: inout ExcelWorkbook
    ) -> Int {
        ExcelCellEditing.differentialStyleIndex(for: style, workbook: &workbook, registry: &registry)
    }



    private func updateValidationWarning(in sheet: ExcelWorksheet) {
        guard let selectedAddress else {
            validationWarning = nil
            return
        }
        let canonical = sheet.canonicalAddress(for: selectedAddress)
        guard let rule = sheet.dataValidations.first(where: {
            $0.contains(canonical)
        }),
        let values = rule.inlineListValues else {
            validationWarning = nil
            return
        }
        let value = sheet.cell(at: canonical)?.editText ?? ""
        if value.isEmpty, rule.allowsBlank {
            validationWarning = nil
        } else if values.contains(value) {
            validationWarning = nil
        } else {
            validationWarning = AppLocalization.string(
                "드롭다운 목록에 없는 값입니다. 목록에서 선택해 주세요."
            )
        }
    }

    private func styleIndex(
        for format: ExcelNumberFormat,
        replacing currentStyleIndex: Int?,
        workbook: inout ExcelWorkbook
    ) -> Int? {
        ExcelCellEditing.styleIndex(for: format, replacing: currentStyleIndex, workbook: &workbook, registry: &registry)
    }

    private func input(preserving cell: ExcelCell) -> ExcelCellInput {
        ExcelCellEditing.input(preserving: cell)
    }

    private func configureInitialLargeWindows(
        using preflight: ExcelWorkbookPreflight
    ) {
        guard preflight.requiresLargeMode else {
            largeWindowStartIndices = [:]
            largeWindowRows = [:]
            largeAddedRows = [:]
            return
        }
        largeWindowStartIndices = Dictionary(
            uniqueKeysWithValues: preflight.sheets.map {
                ($0.partPath, 0)
            }
        )
        largeWindowRows = Dictionary(
            uniqueKeysWithValues: preflight.sheets.map { summary in
                (
                    summary.partPath,
                    Array(
                        summary.populatedRows.prefix(
                            ExcelWorkbookDocument.largePageSize
                        )
                    )
                )
            }
        )
        largeAddedRows = [:]
    }

    private func allLargeRows(
        for summary: ExcelWorksheetPreflight
    ) -> [Int] {
        ExcelLargeWindow.rows(summary, added: largeAddedRows[summary.partPath] ?? [])
    }


    private func loadLargeWindow(
        summary: ExcelWorksheetPreflight,
        startingAt requestedStart: Int,
        preferredRow: Int? = nil
    ) async {
        endEditorTextEditing()
        guard !isLoadingLargeWindow,
              var workbook,
              let sheetIndex = workbook.sheets.firstIndex(where: {
                  $0.partPath == summary.partPath
              }) else {
            return
        }
        let allRows = allLargeRows(for: summary)
        guard !allRows.isEmpty else {
            return
        }
        let start = min(max(requestedStart, 0), allRows.count - 1)
        let end = min(
            start + ExcelWorkbookDocument.largePageSize,
            allRows.count
        )
        let visibleRows = Array(allRows[start..<end])
        var includedRows = Set(
            summary.populatedRows.prefix(
                ExcelWorkbookDocument.largeContextRowCount
            )
        )
        includedRows.formUnion(summary.tableHeaderRows)
        includedRows.formUnion(visibleRows)
        includedRows.formUnion(
            largeAddedRows[summary.partPath] ?? []
        )

        isLoadingLargeWindow = true
        status = ExcelLargeWindow.loadingMessage(visibleRows)
        let data = sourceData
        let cachedSheet = largeWorkbookCache?.sheet(
            partPath: summary.partPath
        )
        let baseSheet = workbook.sheets[sheetIndex]
        do {
            var loaded = try await Task.detached(
                priority: .userInitiated
            ) {
                if let cachedSheet {
                    var sheet = baseSheet
                    sheet.cells = try cachedSheet.cells(in: includedRows)
                    sheet.maximumRow = summary.maximumRow
                    sheet.maximumColumn = summary.maximumColumn
                    sheet.isWindowed = true
                    return sheet
                }
                return try ExcelWorkbookDocument.loadSheetWindow(
                    from: data,
                    summary: summary,
                    includedRows: includedRows
                )
            }.value
            reapplyCurrentEdits(
                to: &loaded,
                includedRows: includedRows
            )
            workbook.sheets[sheetIndex] = loaded
            self.workbook = workbook
            largeWindowStartIndices[summary.partPath] = start
            largeWindowRows[summary.partPath] = visibleRows

            let targetRow = preferredRow.flatMap {
                visibleRows.contains($0) ? $0 : nil
            } ?? visibleRows.first
            if let targetRow {
                let column = loaded.cells.keys
                    .filter { $0.row == targetRow }
                    .map(\.column)
                    .min() ?? 1
                selectedAddress = ExcelCellAddress(
                    row: targetRow,
                    column: column
                )
                syncEditorText(using: loaded)
            }
            status = ExcelLargeWindow.shownMessage(visibleRows, total: allRows.count)
            requestAccessibilityFocus()
        } catch {
            errorDescription = error.localizedDescription
            status = AppLocalization.format(
                "구간을 불러오지 못했습니다: %@",
                error.localizedDescription
            )
        }
        isLoadingLargeWindow = false
    }

    private func reapplyCurrentEdits(
        to sheet: inout ExcelWorksheet,
        includedRows: Set<Int>
    ) {
        guard let sheetEdits = edits[sheet.partPath], let workbook else { return }
        ExcelLargeWindow.reapplying(sheetEdits, to: &sheet, includedRows: includedRows, workbook: workbook)
    }


    private func lowerBound(
        of value: Int,
        in values: [Int]
    ) -> Int {
        var lower = 0
        var upper = values.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if values[middle] < value {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func searchableText(
        for input: ExcelCellInput
    ) -> String {
        ExcelLargeWindow.searchableText(for: input)
    }


    private func syncEditorText(using sheet: ExcelWorksheet) {
        guard let selectedAddress else {
            editorText = ""
            return
        }
        let address = sheet.canonicalAddress(for: selectedAddress)
        self.selectedAddress = address
        editorText = sheet.cell(at: address)?.editText ?? ""
    }

    private func firstPopulatedRow(in sheet: ExcelWorksheet) -> Int {
        sheet.cells.keys.map(\.row).min() ?? 1
    }

    private func initialAddress(
        in sheet: ExcelWorksheet
    ) -> ExcelCellAddress {
        guard let region = ExcelAccessibilityAnalyzer
            .regions(in: sheet).first else {
            return ExcelCellAddress(row: 1, column: 1)
        }
        return ExcelCellAddress(
            row: region.rowNumbers.first
                ?? region.headerRow
                ?? region.range.start.row,
            column: region.columns.first?.column
                ?? region.range.start.column
        )
    }

    private func accessibilitySummary(
        for sheet: ExcelWorksheet
    ) -> String {
        let regions = ExcelAccessibilityAnalyzer.regions(in: sheet)
        let rowCount = regions.reduce(0) {
            $0 + $1.rowNumbers.count
        }
        let formulaCount = sheet.cells.values.filter {
            $0.formula?.isEmpty == false
        }.count
        var details: String
        if let summary = largeWorkbookPreflight?.sheet(
            partPath: sheet.partPath
        ) {
            details = AppLocalization.format(
                "%@ 대용량 시트. 전체 데이터 행 %lld개. 현재 구간에서 %lld개 읽기 영역, %lld개 읽을 행",
                sheet.name,
                allLargeRows(for: summary).count,
                regions.count,
                rowCount
            )
        } else {
            details = AppLocalization.format(
                "%@ 시트. %lld개 읽기 영역, %lld개 읽을 행",
                sheet.name,
                regions.count,
                rowCount
            )
        }
        if formulaCount > 0 {
            details += AppLocalization.format(
                ", 수식 %lld개",
                formulaCount
            )
        }
        if !sheet.mergedRanges.isEmpty {
            details += AppLocalization.format(
                ", 병합 셀 %lld개",
                sheet.mergedRanges.count
            )
        }
        if !sheet.drawingObjects.images.isEmpty {
            details += AppLocalization.format(
                ", 이미지 %lld개",
                sheet.drawingObjects.images.count
            )
        }
        if !sheet.drawingObjects.charts.isEmpty {
            details += AppLocalization.format(
                ", 차트 %lld개",
                sheet.drawingObjects.charts.count
            )
        }
        if !sheet.drawingObjects.shapes.isEmpty {
            details += AppLocalization.format(
                ", 도형·텍스트 상자 %lld개",
                sheet.drawingObjects.shapes.count
            )
        }
        if sheet.drawingObjects.pivotTableCount > 0 {
            details += AppLocalization.format(
                ", 피벗 테이블 %lld개",
                sheet.drawingObjects.pivotTableCount
            )
        }
        return details + "."
    }

    private func styleForNewCell(
        column: Int,
        row: Int,
        in sheet: ExcelWorksheet
    ) -> Int? {
        ExcelCellEditing.styleForNewCell(column: column, row: row, in: sheet)
    }

    private func workbookStatus(_ workbook: ExcelWorkbook) -> String {
        if let preflight = largeWorkbookPreflight {
            let rowCount = preflight.sheets.reduce(0) {
                $0 + $1.populatedRows.count
            }
            return AppLocalization.format(
                "대용량 문서 · %lld개 시트 · 전체 데이터 행 %lld개",
                workbook.sheets.count,
                rowCount
            )
        }
        let cellCount = workbook.sheets.reduce(0) {
            $0 + $1.cells.count
        }
        return AppLocalization.format(
            "%lld개 시트 · %lld개 셀",
            workbook.sheets.count,
            cellCount
        )
    }
}

private struct ExcelEditableRow: Identifiable {
    let regionID: String
    let row: Int

    var id: String {
        regionID + ":" + String(row)
    }
}

private struct ExcelDropdownEditorState: Identifiable {
    let id = UUID()
    let values: [String]
    let allowsBlank: Bool
    let appliesToCurrentColumn: Bool
}

private struct ExcelConditionalFormattingEditorState: Identifiable {
    let id = UUID()
    let kind: ExcelConditionalRuleKind
    let comparisonValue: String
    let highlight: ExcelConditionalHighlight
    let appliesToCurrentColumn: Bool
}

private struct ExcelCellAnnotationsEditorState: Identifiable {
    let id = UUID()
    let hyperlinkTarget: String
    let hyperlinkTooltip: String
    let noteText: String
    let noteAuthor: String
}

struct ExcelWorkbookView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: ExcelWorkbookViewModel

    @State private var headerWidth: CGFloat = 0
    @State private var isAddingRow = false
    @State private var isExporting = false
    @State private var exportDocument: ExcelWorkbookExportDocument?
    @State private var exportError: String?
    @State private var showsDiscardConfirmation = false
    @State private var showsMoreActions = false
    @State private var pendingMoreAction: ExcelWorkbookAction?
    @State private var editingPanel: ExcelEditingPanel?
    @State private var isManagingSheets = false
    @State private var showsCellTools = false
    @State private var pendingCellToolAction: ExcelCellToolAction?
    @State private var viewMode = ExcelWorkbookViewMode.cellGrid
    @State private var selectedRegionID: String?
    @State private var editingRow: ExcelEditableRow?
    @State private var dropdownEditor: ExcelDropdownEditorState?
    @State private var conditionalFormattingEditor:
        ExcelConditionalFormattingEditorState?
    @State private var annotationsEditor: ExcelCellAnnotationsEditorState?
    @State private var isManagingImages = false
    @State private var drawingEditor: ExcelDrawingSelection?
    @State private var largeSearchText = ""
    @State private var largeJumpRowText = ""
    @FocusState private var isEditorFocused: Bool

    init(
        fileURL: URL,
        originalDocumentID: UUID? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: ExcelWorkbookViewModel(
                fileURL: fileURL,
                originalDocumentID:
                    originalDocumentID
            )
        )
    }

    private var documentBackButton: some View {
        VisionCraftBackButton {
            guard !viewModel.isSaving else { return }
            isEditorFocused = false
            Task {
                let saved = await viewModel.flushAutosave()
                if saved || !viewModel.hasUnsavedChanges {
                    dismiss()
                } else {
                    showsDiscardConfirmation = true
                }
            }
        }
    }

    private var documentContent: some View {
        Group {
            if viewModel.isLoading {
                ExcelDocumentLoadingView(
                    message: viewModel.status.isEmpty
                        ? AppLocalization.string("엑셀 파일을 여는 중…")
                        : viewModel.status
                )
            } else if let error = viewModel.errorDescription,
                      viewModel.workbook == nil {
                ContentUnavailableView(
                    "XLSX 문서를 열 수 없습니다",
                    systemImage: "tablecells.badge.ellipsis",
                    description: Text(error)
                )
            } else if let workbook = viewModel.workbook {
                workbookContent(workbook)
            } else {
                ExcelDocumentLoadingView()
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            documentHeader
            Divider()
            documentContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(viewModel.isSaving)
        .visionCraftNavigationScreen()
        .navigationBarBackButtonHidden(true)
        .visionCraftHandlesBackNavigation()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.load()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            Task { _ = await viewModel.flushAutosave() }
        }
        .onChange(of: viewModel.isLoading) { _, isLoading in
            guard !isLoading,
                  let summary = viewModel.accessibilityWorkbookSummary() else {
                return
            }
            announce(summary)
        }
        .onChange(of: viewModel.status) { _, status in
            guard !viewModel.isLoading,
                  !viewModel.isAutosaving,
                  editingRow == nil,
                  !status.isEmpty else {
                return
            }
            announce(status)
        }
        .onChange(of: viewMode) { _, mode in
            announce(
                mode == .accessibleRows
                    ? AppLocalization.string("간편 표 보기. 한 번 쓸어 한 행씩 이동합니다.")
                    : AppLocalization.string("원본 셀 보기. 셀 단위로 이동합니다.")
            )
            if mode == .accessibleRows {
                viewModel.requestAccessibilityFocus()
            }
        }
        .fullScreenCover(
            isPresented: $showsMoreActions,
            onDismiss: performPendingMoreAction
        ) {
            ExcelWorkbookActionsDialog(
                canUndo: viewModel.canUndo,
                canRedo: viewModel.canRedo,
                onAction: { action in
                    pendingMoreAction = action
                    setMoreActionsPresented(false)
                },
                onDismiss: { setMoreActionsPresented(false) }
            )
            .presentationBackground(.clear)
        }
        .fullScreenCover(
            isPresented: $showsCellTools,
            onDismiss: performPendingCellToolAction
        ) {
            ExcelCellToolsDialog(
                viewModel: viewModel,
                onAction: { action in
                    pendingCellToolAction = action
                    setCellToolsPresented(false)
                },
                onDismiss: { setCellToolsPresented(false) }
            )
            .presentationBackground(.clear)
        }
        .sheet(item: $editingPanel, onDismiss: viewModel.requestAccessibilityFocus) { panel in
            ExcelEditingToolsView(viewModel: viewModel, panel: panel)
        }
        .sheet(isPresented: $isManagingSheets, onDismiss: viewModel.requestAccessibilityFocus) {
            ExcelSheetManagerView(viewModel: viewModel)
        }
        .sheet(item: $drawingEditor) { selection in
            ExcelDrawingInspector(viewModel: viewModel, selection: selection)
        }
        .sheet(
            isPresented: $isAddingRow,
            onDismiss: viewModel.requestAccessibilityFocus
        ) {
            ExcelAddRowView(
                initialFields: viewModel.rowFieldsForAppending()
            ) { fields in
                viewModel.appendRow(fields: fields)
            }
        }
        .fullScreenCover(
            item: $editingRow,
            onDismiss: viewModel.requestAccessibilityFocus
        ) { selection in
            if let region = accessibleRegions.first(where: {
                $0.id == selection.regionID
            }) {
                ExcelEditRowView(
                    row: selection.row,
                    initialFields: viewModel.rowFields(
                        for: selection.row,
                        columns: region.columns
                    ),
                    viewModel: viewModel
                )
                .presentationBackground(.clear)
            } else {
                ContentUnavailableView(
                    "행을 편집할 수 없습니다",
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
        .sheet(
            item: $dropdownEditor,
            onDismiss: viewModel.requestAccessibilityFocus
        ) { configuration in
            ExcelDropdownEditorView(
                initialValues: configuration.values,
                initialAllowsBlank: configuration.allowsBlank,
                appliesToCurrentColumn:
                    configuration.appliesToCurrentColumn
            ) { values, allowsBlank in
                viewModel.applyDropdown(
                    values: values,
                    allowsBlank: allowsBlank,
                    toCurrentColumn:
                        configuration.appliesToCurrentColumn
                )
            }
        }
        .sheet(
            item: $conditionalFormattingEditor,
            onDismiss: viewModel.requestAccessibilityFocus
        ) { configuration in
            ExcelConditionalFormattingEditorView(
                initialKind: configuration.kind,
                initialComparisonValue: configuration.comparisonValue,
                initialHighlight: configuration.highlight,
                appliesToCurrentColumn:
                    configuration.appliesToCurrentColumn
            ) { kind, value, highlight in
                viewModel.applyConditionalFormatting(
                    kind: kind,
                    comparisonValue: value,
                    highlight: highlight,
                    toCurrentColumn:
                        configuration.appliesToCurrentColumn
                )
            }
        }
        .sheet(
            item: $annotationsEditor,
            onDismiss: viewModel.requestAccessibilityFocus
        ) { configuration in
            ExcelCellAnnotationsEditorView(
                initialHyperlinkTarget: configuration.hyperlinkTarget,
                initialHyperlinkTooltip: configuration.hyperlinkTooltip,
                initialNoteText: configuration.noteText,
                initialNoteAuthor: configuration.noteAuthor
            ) { target, tooltip, note, author in
                viewModel.applyCellAnnotations(
                    hyperlinkTarget: target,
                    hyperlinkTooltip: tooltip,
                    noteText: note,
                    noteAuthor: author
                )
            }
        }
        .sheet(
            isPresented: $isManagingImages,
            onDismiss: viewModel.requestAccessibilityFocus
        ) {
            ExcelSheetImageManagerView(
                images: viewModel.selectedSheetImages,
                charts: viewModel.selectedSheetCharts,
                shapes: viewModel.selectedSheetShapes,
                pivotTables: viewModel.selectedSheetPivotTables,
                selectedCellReference:
                    viewModel.selectedAddress?.reference ?? "A1",
                defaultChartSourceReference:
                    viewModel.defaultChartSourceReference,
                defaultPivotDestinationReference:
                    viewModel.defaultPivotDestinationReference,
                pivotFieldNames: viewModel.pivotFieldNames,
                onAdd: viewModel.addSheetImage,
                onReplace: viewModel.replaceSheetImage,
                onRemove: viewModel.removeSheetImage,
                onAddChart: viewModel.addSheetChart,
                onUpdateChart: viewModel.updateSheetChart,
                onRemoveChart: viewModel.removeSheetChart,
                onAddShape: viewModel.addSheetShape,
                onUpdateShape: viewModel.updateSheetShape,
                onRemoveShape: viewModel.removeSheetShape,
                onAddPivot: viewModel.addPivotTable,
                onUpdatePivot: viewModel.updatePivotTable,
                onRemovePivot: viewModel.removePivotTable
            )
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: VisionCraftFileTypes.xlsx,
            defaultFilename: exportFileName
        ) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
            }
            exportDocument = nil
        }
        .alert(
            "저장하지 않은 변경 사항",
            isPresented: $showsDiscardConfirmation
        ) {
            Button("계속 편집", role: .cancel) {}
            Button("변경 내용 버리기", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("저장하지 않고 문서를 닫을까요?")
        }
        .alert(
            "내보낼 수 없습니다",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
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
        case .undo:
            viewModel.undo()
        case .redo:
            viewModel.redo()
        }
    }

    private func workbookContent(_ workbook: ExcelWorkbook) -> some View {
        VStack(spacing: 0) {
            if viewModel.isLargeWorkbook {
                largeWorkbookControls
                Divider()
            }
            if let sheet = viewModel.selectedSheet {
                switch viewMode {
                case .accessibleRows:
                    accessibleRows(
                        sheet: sheet
                    )
                case .cellGrid:
                    ExcelGridView(
                        sheet: sheet,
                        workbook: workbook,
                        regions: ExcelAccessibilityAnalyzer.regions(
                            in: sheet
                        ),
                        visibleRows: viewModel.isLargeWorkbook
                            ? viewModel.selectedLargeWindowRows
                            : nil,
                        selectedAddress: viewModel.selectedAddress,
                        onSelect: viewModel.selectCell,
                        onEdit: { address in
                            viewModel.selectCell(address)
                            isEditorFocused = true
                        },
                        selectedRange: viewModel.selectedRange,
                        onRangeSelect: viewModel.selectRange(from:to:),
                        onSelectRow: viewModel.selectEntireRow,
                        onSelectColumn: viewModel.selectEntireColumn,
                        highlightedAddresses: viewModel.aiHighlightedAddresses,
                        revealAddress: viewModel.navigationRevealAddress ?? viewModel.aiReferenceAddress,
                        canEditDrawings: viewModel.canEditSelectedSheet && !viewModel.isLargeWorkbook && !viewModel.isSaving,
                        onMoveDrawing: { selection, expected, anchor in
                            viewModel.updateDrawingPlacement(selection, expected: expected, anchor: anchor)
                        },
                        onEditDrawing: { selection in isEditorFocused = false; drawingEditor = selection },
                        onDeleteDrawing: { selection in
                            guard viewModel.selectedSheet?.partPath == selection.sheetPath else { return }
                            if viewModel.selectedSheetImages.contains(where: { $0.id == selection.id }) { viewModel.removeSheetImage(id: selection.id) }
                            else { viewModel.removeSheetChart(id: selection.id) }
                        },
                        activeDrawingID: viewModel.selectedDrawingID,
                        onDrawingSelectionChanged: { id in
                            guard !viewModel.isSaving else { return }
                            viewModel.selectedDrawingID = id
                        }
                    )
                }
            }
            if let reference = viewModel.aiReferenceAddress,
               let references = viewModel.aiReferences {
                HStack(spacing: 12) {
                    Label(AppLocalization.format("참조 %lld개", references.totalAddressCount), systemImage: "square.on.square")
                        .foregroundStyle(Color.purple)
                    if references.sheets.count > 1, let sheetName = viewModel.aiReferenceSheetName {
                        Text(sheetName).lineLimit(1)
                    }
                    Text(reference.reference).monospaced()
                    Spacer()
                    Button { viewModel.moveAIReference(by: -1) } label: {
                        Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(viewModel.aiReferenceIndex == 0)
                    .accessibilityLabel("이전 참조 셀")
                    Text("\(viewModel.aiReferenceIndex + 1)/\(references.totalAddressCount)").monospacedDigit()
                    Button { viewModel.moveAIReference(by: 1) } label: {
                        Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(viewModel.aiReferenceIndex == references.totalAddressCount - 1)
                    .accessibilityLabel("다음 참조 셀")
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .background(VisionCraftUI.surface)
            }
            statusBar
            if viewModel.isLargeWorkbook {
                Text(
                    "대용량 문서에서도 AI 검색과 질문을 사용할 수 있습니다. 관련 행만 AI에 전달되며, AI 문서 수정은 일반 문서에서 사용할 수 있습니다."
                )
                .font(.caption)
                .foregroundStyle(VisionCraftUI.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(VisionCraftUI.surface)
                .accessibilityLabel(
                    "대용량 문서 안내. 전체 시트에서 AI 검색과 질문을 사용할 수 있습니다. 관련 행만 AI에 전달되며, AI 문서 수정은 일반 문서에서 사용할 수 있습니다."
                )
            }
            Divider()
            ExcelWorkbookBottomBar(
                sheetNames: workbook.sheets.map(\.name),
                selectedSheetIndex: viewModel.selectedSheetIndex,
                viewMode: $viewMode,
                onSelectSheet: viewModel.selectSheet,
                onManageSheets: { isEditorFocused = false; isManagingSheets = true }
            )
            ExcelAIChatPanel(
                isAvailable: viewModel.selectedSheet != nil,
                isLargeWorkbook: viewModel.isLargeWorkbook,
                snapshotProvider: { request in
                    try await viewModel.makeAISnapshot(for: request)
                },
                onApply: viewModel.applyAIPlan,
                onApplyOperations: viewModel.applyAIWorkbookPlan,
                onReferencesChanged: viewModel.showAIReferences
            )
        }
        .background(VisionCraftUI.background)
    }

    private var largeWorkbookControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive.badge.timemachine")
                    .foregroundStyle(VisionCraftUI.primary)
                if let summary = viewModel.selectedLargeSheetSummary {
                    Text(
                        AppLocalization.format(
                            "대용량 시트 · 데이터 행 %lld개 · 최대 %lld열",
                            summary.populatedRows.count,
                            summary.maximumColumn
                        )
                    )
                    .font(.subheadline.weight(.semibold))
                } else {
                    Text("대용량 문서")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                if viewModel.isLoadingLargeWindow
                    || viewModel.isSearchingLargeWorkbook {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("대용량 시트 처리 중")
                }
            }

            HStack(spacing: 8) {
                TextField("전체 시트에서 검색", text: $largeSearchText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .disabled(
                        viewModel.isLoadingLargeWindow
                            || viewModel.isSearchingLargeWorkbook
                    )
                    .onSubmit {
                        Task {
                            await viewModel.searchLargeWorkbook(
                                largeSearchText
                            )
                        }
                    }
                    .accessibilityLabel("대용량 시트 전체 검색어")
                Button("검색", systemImage: "magnifyingglass") {
                    Task {
                        await viewModel.searchLargeWorkbook(
                            largeSearchText
                        )
                    }
                }
                .disabled(
                    largeSearchText.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                        || viewModel.isLoadingLargeWindow
                        || viewModel.isSearchingLargeWorkbook
                )
                if !viewModel.largeSearchRows.isEmpty {
                    Button(
                        "다음 결과",
                        systemImage: "arrow.down.to.line"
                    ) {
                        Task {
                            await viewModel.moveToNextLargeSearchResult()
                        }
                    }
                    .disabled(viewModel.isLoadingLargeWindow)
                    .accessibilityValue(
                        AppLocalization.format(
                            "%lld개 결과",
                            viewModel.largeSearchRows.count
                        )
                    )
                }
            }

            HStack(spacing: 8) {
                Button("이전 200행", systemImage: "chevron.left") {
                    Task {
                        await viewModel.moveLargeWindow(byPages: -1)
                    }
                }
                .disabled(
                    !viewModel.canMoveToPreviousLargeWindow
                        || viewModel.isLoadingLargeWindow
                )

                Text(largeWindowDescription)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(VisionCraftUI.secondaryText)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(
                        "현재 표시 구간. " + largeWindowDescription
                    )

                Button("다음 200행", systemImage: "chevron.right") {
                    Task {
                        await viewModel.moveLargeWindow(byPages: 1)
                    }
                }
                .disabled(
                    !viewModel.canMoveToNextLargeWindow
                        || viewModel.isLoadingLargeWindow
                )

                TextField("행 번호", text: $largeJumpRowText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .frame(width: 100)
                    .accessibilityLabel("이동할 원본 행 번호")
                Button("이동") {
                    guard let row = Int(largeJumpRowText) else {
                        return
                    }
                    Task {
                        await viewModel.jumpToLargeRow(row)
                    }
                }
                .disabled(
                    Int(largeJumpRowText) == nil
                        || viewModel.isLoadingLargeWindow
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(VisionCraftUI.surfaceVariant)
        .accessibilityElement(children: .contain)
    }

    private var largeWindowDescription: String {
        let rows = viewModel.selectedLargeWindowRows
        guard let first = rows.first,
              let last = rows.last else {
            return AppLocalization.string("표시할 행 없음")
        }
        return AppLocalization.format(
            "원본 %lld–%lld행 · %lld개",
            first,
            last,
            rows.count
        )
    }

    private func accessibleRows(
        sheet: ExcelWorksheet
    ) -> some View {
        let regions = ExcelAccessibilityAnalyzer.regions(in: sheet)
        let region = selectedAccessibleRegion(
            from: regions
        )
        return ExcelAccessibleRowsView(
            sheet: sheet,
            regions: regions,
            selectedRegion: region,
            visibleRows: viewModel.isLargeWorkbook
                ? Set(viewModel.selectedLargeWindowRows)
                : nil,
            selectedAddress: viewModel.selectedAddress,
            focusRequestID: viewModel.accessibilityFocusRequestID,
            onSelectRegion: { selectedRegion in
                selectedRegionID = selectedRegion.id
                viewModel.selectRegion(selectedRegion)
            },
            onEditRow: { row in
                guard let region else {
                    return
                }
                select(
                    row: row,
                    in: region
                )
                editingRow = ExcelEditableRow(
                    regionID: region.id,
                    row: row
                )
            },
            onShowRowInGrid: { row in
                guard let region else {
                    return
                }
                select(
                    row: row,
                    in: region
                )
                viewMode = .cellGrid
            },
            referencedRows: Set(viewModel.aiHighlightedAddresses.map(\.row))
        )
    }

    private var showsInlineHistory: Bool {
        !dynamicTypeSize.isAccessibilitySize
            && (viewMode == .accessibleRows || headerWidth >= 640)
    }

    private var documentHeader: some View {
        Group {
            if !viewModel.isLoading,
               viewModel.selectedSheet != nil,
               viewMode == .cellGrid {
                formulaBar
            } else {
                HStack(spacing: 8) {
                    documentBackButton
                    Spacer(minLength: 0)
                    if viewModel.selectedSheet != nil {
                        cellToolsButton
                    }
                    if showsInlineHistory {
                        historyButtons
                    }
                    shareWorkbookButton
                    if !showsInlineHistory {
                        moreActionsButton
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(VisionCraftUI.surface)
            }
        }
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            headerWidth = width
        }
    }

    private var historyButtons: some View {
        HStack(spacing: 0) {
            Button {
                viewModel.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .disabled(viewModel.isSaving || !viewModel.canUndo)
            .accessibilityLabel("실행 취소")

            Button {
                viewModel.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .disabled(viewModel.isSaving || !viewModel.canRedo)
            .accessibilityLabel("다시 실행")
        }
        .buttonStyle(.borderless)
        .tint(VisionCraftUI.primary)
    }

    private var moreActionsButton: some View {
        Button {
            isEditorFocused = false
            setMoreActionsPresented(true)
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .tint(VisionCraftUI.primary)
        .disabled(viewModel.isSaving || viewModel.workbook == nil)
        .accessibilityLabel("더보기")
    }

    private var shareWorkbookButton: some View {
        Button {
            isEditorFocused = false
            Task { await beginExport() }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .tint(VisionCraftUI.primary)
        .disabled(viewModel.isSaving || viewModel.workbook == nil)
        .accessibilityLabel("XLSX 복사본 공유")
    }

    private var cellToolsButton: some View {
        Button {
            isEditorFocused = false
            setCellToolsPresented(true)
        } label: {
            Text("셀 도구")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(VisionCraftUI.primary.opacity(0.5), lineWidth: 1)
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(VisionCraftUI.primary)
        .opacity(viewModel.selectedSheet == nil ? 0.4 : 1)
        .fixedSize()
        .disabled(viewModel.selectedSheet == nil)
        .accessibilityHint(
            "셀 서식, 행 추가, 이미지·차트 등을 선택합니다."
        )
    }

    private var formulaBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: headerWidth < 640 ? 4 : 8) {
                documentBackButton

                Button { editingPanel = .range } label: {
                    Text(viewModel.selectedRange?.reference ?? "—")
                }
                    .buttonStyle(.plain)
                    .font(.body.monospaced().weight(.semibold))
                    .foregroundStyle(VisionCraftUI.primary)
                    .frame(width: headerWidth < 640 ? 48 : 62, height: 48)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel(
                        AppLocalization.format(
                            "선택한 셀 %@",
                            viewModel.selectedAddress?.reference ?? "—"
                        )
                    )

                Divider()
                    .frame(height: 28)

                TextField(
                    "값 또는 =수식",
                    text: Binding(
                        get: { viewModel.editorText },
                        set: viewModel.updateEditorText
                    ),
                    axis: .vertical
                )
                .lineLimit(1 ... 3)
                .textFieldStyle(.plain)
                .focused($isEditorFocused)
                .onSubmit {
                    viewModel.commitEditorText()
                    isEditorFocused = false
                }
                .onChange(of: isEditorFocused) { wasFocused, isFocused in
                    if wasFocused, !isFocused {
                        viewModel.commitEditorText()
                    }
                }
                .accessibilityLabel("선택한 셀 값")
                .accessibilityHint(
                    "값 또는 등호로 시작하는 수식을 입력하면 즉시 셀에 반영됩니다."
                )
                .disabled(!viewModel.canEditSelectedSheet || viewModel.selectedCellIsSpillResult)

                Button {
                    viewModel.clearSelection()
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .tint(VisionCraftUI.primary)
                .accessibilityLabel("비우기")
                .disabled(
                    viewModel.selectedAddress == nil
                        || viewModel.selectedCellIsSpillResult
                )

                cellToolsButton

                if showsInlineHistory {
                    historyButtons
                }
                shareWorkbookButton
                if !showsInlineHistory {
                    moreActionsButton
                }
            }
            if let warning = viewModel.validationWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(VisionCraftUI.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, headerWidth < 640 ? 97 : 127)
                    .accessibilityLabel("입력 경고. " + warning)
            }
            if let description = viewModel.selectedRangeDescription {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(VisionCraftUI.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, headerWidth < 640 ? 97 : 127)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(VisionCraftUI.surface)
    }

    private func setCellToolsPresented(_ isPresented: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showsCellTools = isPresented
        }
    }

    private func performPendingCellToolAction() {
        guard let action = pendingCellToolAction else {
            viewModel.requestAccessibilityFocus()
            return
        }
        pendingCellToolAction = nil
        // Present editors only after the tools dialog has finished dismissing.
        switch action {
        case .editingPanel(let panel):
            editingPanel = panel
            return
        case .addRow:
            prepareCurrentAccessibleRegion()
            isAddingRow = true
            return
        case .sheetObjects:
            isManagingImages = true
            return
        case let .numberFormat(format, toCurrentColumn):
            viewModel.applyNumberFormat(format, toCurrentColumn: toCurrentColumn)
        case let .chooseDropdownValue(value):
            viewModel.chooseDropdownValue(value)
        case let .editDropdown(toCurrentColumn):
            presentDropdownEditor(toCurrentColumn: toCurrentColumn)
            return
        case let .removeDropdown(toCurrentColumn):
            viewModel.removeDropdown(toCurrentColumn: toCurrentColumn)
        case let .editConditionalFormatting(toCurrentColumn):
            presentConditionalFormattingEditor(toCurrentColumn: toCurrentColumn)
            return
        case let .removeConditionalFormatting(toCurrentColumn):
            viewModel.removeConditionalFormatting(toCurrentColumn: toCurrentColumn)
        case let .openLink(url):
            openURL(url)
        case .editAnnotations:
            presentAnnotationsEditor()
            return
        case .removeHyperlink:
            removeSelectedHyperlink()
        case .removeNote:
            removeSelectedNote()
        }
        viewModel.requestAccessibilityFocus()
    }

    private func presentDropdownEditor(toCurrentColumn: Bool) {
        dropdownEditor = ExcelDropdownEditorState(
            values: viewModel.selectedDropdownValues,
            allowsBlank: viewModel.selectedDropdownAllowsBlank,
            appliesToCurrentColumn: toCurrentColumn
        )
    }

    private func presentConditionalFormattingEditor(
        toCurrentColumn: Bool
    ) {
        conditionalFormattingEditor =
            ExcelConditionalFormattingEditorState(
                kind: viewModel.selectedConditionalRule?.kind
                    ?? .greaterThan,
                comparisonValue:
                    viewModel.selectedConditionalRule?.comparisonValue ?? "",
                highlight: viewModel.selectedConditionalHighlight ?? .red,
                appliesToCurrentColumn: toCurrentColumn
            )
    }

    private func presentAnnotationsEditor() {
        annotationsEditor = ExcelCellAnnotationsEditorState(
            hyperlinkTarget: viewModel.selectedHyperlink?.target ?? "",
            hyperlinkTooltip: viewModel.selectedHyperlink?.tooltip ?? "",
            noteText: viewModel.selectedNote?.text ?? "",
            noteAuthor: viewModel.selectedNote?.author ?? "VisionCraft"
        )
    }

    private func removeSelectedHyperlink() {
        _ = viewModel.applyCellAnnotations(
            hyperlinkTarget: "",
            hyperlinkTooltip: "",
            noteText: viewModel.selectedNote?.text ?? "",
            noteAuthor: viewModel.selectedNote?.author ?? "VisionCraft"
        )
    }

    private func removeSelectedNote() {
        _ = viewModel.applyCellAnnotations(
            hyperlinkTarget: viewModel.selectedHyperlink?.target ?? "",
            hyperlinkTooltip: viewModel.selectedHyperlink?.tooltip ?? "",
            noteText: "",
            noteAuthor: "VisionCraft"
        )
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if viewModel.isSaving || viewModel.isAutosaving {
                ProgressView()
                    .controlSize(.small)
            }
            Text(viewModel.status)
                .font(.footnote)
                .foregroundStyle(VisionCraftUI.secondaryText)
                .lineLimit(2)
            Spacer()
            if viewModel.hasUnsavedChanges {
                Label("수정됨", systemImage: "circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VisionCraftUI.warning)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(VisionCraftUI.surface)
        .accessibilityElement(children: .combine)
    }

    private var accessibleRegions: [ExcelAccessibleRegion] {
        guard let sheet = viewModel.selectedSheet else {
            return []
        }
        return ExcelAccessibilityAnalyzer.regions(in: sheet)
    }

    private func selectedAccessibleRegion(
        from regions: [ExcelAccessibleRegion]
    ) -> ExcelAccessibleRegion? {
        if let selectedRegionID,
           let selected = regions.first(where: {
               $0.id == selectedRegionID
           }) {
            return selected
        }
        if let selectedAddress = viewModel.selectedAddress,
           let selected = regions.first(where: {
               $0.contains(selectedAddress)
           }) {
            return selected
        }
        return regions.first
    }

    private func prepareCurrentAccessibleRegion() {
        guard let region = selectedAccessibleRegion(
            from: accessibleRegions
        ) else {
            return
        }
        selectedRegionID = region.id
        if let address = viewModel.selectedAddress,
           region.contains(address) {
            return
        }
        viewModel.selectRegion(region)
    }

    private func select(
        row: Int,
        in region: ExcelAccessibleRegion
    ) {
        selectedRegionID = region.id
        viewModel.selectCell(
            ExcelCellAddress(
                row: row,
                column: region.columns.first?.column
                    ?? region.range.start.column
            )
        )
    }

    private func announce(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning,
              !text.isEmpty else {
            return
        }
        UIAccessibility.post(
            notification: .announcement,
            argument: text
        )
    }

    private var exportFileName: String {
        let base = viewModel.fileURL
            .deletingPathExtension()
            .lastPathComponent
        return base + "-수정본.xlsx"
    }

    private func beginExport() async {
        do {
            exportDocument = ExcelWorkbookExportDocument(
                data: try await viewModel.exportData()
            )
            isExporting = true
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct ExcelAccessibleRowsView: View {
    let sheet: ExcelWorksheet
    let regions: [ExcelAccessibleRegion]
    let selectedRegion: ExcelAccessibleRegion?
    let visibleRows: Set<Int>?
    let selectedAddress: ExcelCellAddress?
    let focusRequestID: Int
    let onSelectRegion: (ExcelAccessibleRegion) -> Void
    let onEditRow: (Int) -> Void
    let onShowRowInGrid: (Int) -> Void
    var referencedRows: Set<Int> = []

    @AccessibilityFocusState private var focusedRow: Int?

    var body: some View {
        VStack(spacing: 0) {
            if regions.count > 1 {
                regionPicker
                Divider()
            }
            if let region = selectedRegion {
                regionSummary(region)
                if displayedRows(in: region).isEmpty {
                    ContentUnavailableView(
                        "읽을 데이터 행이 없습니다",
                        systemImage: "table.rows",
                        description: Text(
                            "행 추가를 사용하거나 원본 셀 보기에서 내용을 확인하세요."
                        )
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    rowList(region)
                }
            } else {
                ContentUnavailableView(
                    "표 구조를 찾지 못했습니다",
                    systemImage: "tablecells.badge.ellipsis",
                    description: Text(
                        "원본 셀 보기를 사용하면 모든 셀을 확인할 수 있습니다."
                    )
                )
                .frame(maxHeight: .infinity)
            }
        }
        .background(VisionCraftUI.background)
        .onAppear {
            moveFocusToSelectedRow()
        }
        .onChange(of: focusRequestID) { _, _ in
            moveFocusToSelectedRow()
        }
        .onChange(of: selectedRegion?.id) { _, _ in
            moveFocusToSelectedRow()
        }
    }

    private var regionPicker: some View {
        Picker(
            "영역 선택",
            selection: Binding(
                get: { selectedRegion?.id ?? regions[0].id },
                set: { id in
                    guard let region = regions.first(where: {
                        $0.id == id
                    }) else {
                        return
                    }
                    onSelectRegion(region)
                }
            )
        ) {
            ForEach(regions) { region in
                Text(region.name).tag(region.id)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func regionSummary(
        _ region: ExcelAccessibleRegion
    ) -> some View {
        let rowCount = displayedRows(in: region).count
        return HStack(spacing: 8) {
            Image(systemName: "rectangle.grid.1x2")
            Text(
                AppLocalization.format(
                    "%lld개 데이터 행 · %lld개 열",
                    rowCount,
                    region.columns.count
                )
            )
            Spacer()
            Text(region.range.reference)
                .font(.caption.monospaced())
                .foregroundStyle(VisionCraftUI.secondaryText)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(VisionCraftUI.primaryText)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(VisionCraftUI.surfaceVariant)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AppLocalization.format(
                "%@ 영역. %lld개 읽을 행, %lld개 열. 범위 %@",
                region.name,
                rowCount,
                region.columns.count,
                region.range.reference
            )
        )
        .accessibilityAddTraits(.isHeader)
    }

    private func rowList(
        _ region: ExcelAccessibleRegion
    ) -> some View {
        let rows = displayedRows(in: region)
        return List {
            ForEach(
                Array(rows.enumerated()),
                id: \.element
            ) { index, row in
                rowButton(
                    row: row,
                    dataIndex: index,
                    region: region
                )
                .id(row)
            }
        }
        .listStyle(.plain)
        .accessibilityLabel(
            AppLocalization.format(
                "%@ 시트의 %@ 영역",
                sheet.name,
                region.name
            )
        )
        .accessibilityRotor("행") {
            ForEach(
                Array(rows.enumerated()),
                id: \.element
            ) { index, row in
                AccessibilityRotorEntry(
                    AppLocalization.format(
                        "%lld번째 데이터 행",
                        index + 1
                    ),
                    id: row
                )
            }
        }
        .accessibilityRotor("수식이 있는 행") {
            ForEach(formulaRows(in: region), id: \.self) { row in
                AccessibilityRotorEntry(
                    AppLocalization.format("원본 %lld행", row),
                    id: row
                )
            }
        }
    }

    private func rowButton(
        row: Int,
        dataIndex: Int,
        region: ExcelAccessibleRegion
    ) -> some View {
        let populatedColumns = region.columns.filter {
            !displayValue(row: row, column: $0.column).isEmpty
        }
        let primaryColumn = populatedColumns.first
        let secondaryColumns = Array(populatedColumns.dropFirst())
        let isSelected = selectedAddress?.row == row
        return Button {
            onEditRow(row)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(verbatim: String(dataIndex + 1))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VisionCraftUI.secondaryText)
                    Spacer()
                    if referencedRows.contains(row) {
                        Label("참조", systemImage: "square.on.square")
                            .font(.caption)
                            .foregroundStyle(Color.purple)
                    }
                    Image(systemName: "chevron.right")
                        .foregroundStyle(VisionCraftUI.secondaryText)
                }
                if let primaryColumn {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(primaryColumn.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(VisionCraftUI.secondaryText)
                            .frame(minWidth: 72, alignment: .leading)
                        Text(
                            displayValue(
                                row: row,
                                column: primaryColumn.column
                            )
                        )
                        .font(.headline)
                        .foregroundStyle(VisionCraftUI.primaryText)
                    }
                }
                ForEach(secondaryColumns) { column in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(column.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(VisionCraftUI.secondaryText)
                            .frame(minWidth: 72, alignment: .leading)
                        Text(
                            displayValue(
                                row: row,
                                column: column.column
                            )
                        )
                        .font(.body.weight(.medium))
                        .foregroundStyle(VisionCraftUI.primaryText)
                    }
                }
            }
            .padding(.vertical, 6)
            .overlay {
                if referencedRows.contains(row) {
                    Rectangle()
                        .inset(by: 1)
                        .stroke(Color.purple, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            rowAccessibilityLabel(
                row: row,
                dataIndex: dataIndex,
                region: region
            ) + (referencedRows.contains(row) ? ". " + AppLocalization.string("대화 관련 셀") : "")
        )
        .accessibilityHint("두 번 탭하면 이 행의 모든 값을 편집합니다.")
        .accessibilityAddTraits(
            isSelected ? [.isButton, .isSelected] : .isButton
        )
        .accessibilityAction(named: "원본 셀에서 보기") {
            onShowRowInGrid(row)
        }
        .accessibilityFocused($focusedRow, equals: row)
    }

    private func rowAccessibilityLabel(
        row: Int,
        dataIndex: Int,
        region: ExcelAccessibleRegion
    ) -> String {
        ExcelAccessibleRows.label(row: row, dataIndex: dataIndex, region: region, sheet: sheet)
    }

    private func displayValue(
        row: Int,
        column: Int
    ) -> String {
        ExcelAccessibleRows.displayValue(row: row, column: column, sheet: sheet)
    }

    private func formulaRows(
        in region: ExcelAccessibleRegion
    ) -> [Int] {
        displayedRows(in: region).filter { row in
            region.columns.contains { column in
                sheet.cell(
                    at: ExcelCellAddress(
                        row: row,
                        column: column.column
                    )
                )?.formula?.isEmpty == false
            }
        }
    }

    private func moveFocusToSelectedRow() {
        guard let row = selectedAddress?.row,
              selectedRegion?.rowNumbers.contains(row) == true else {
            return
        }
        Task { @MainActor in
            await Task.yield()
            focusedRow = row
        }
    }

    private func displayedRows(
        in region: ExcelAccessibleRegion
    ) -> [Int] {
        ExcelAccessibleRows.displayedRows(in: region, sheet: sheet, visibleRows: visibleRows)
    }
}

struct ExcelGridView: View {
    let sheet: ExcelWorksheet
    let workbook: ExcelWorkbook
    let regions: [ExcelAccessibleRegion]
    let visibleRows: [Int]?
    let selectedAddress: ExcelCellAddress?
    let onSelect: (ExcelCellAddress) -> Void
    let onEdit: (ExcelCellAddress) -> Void
    var selectedRange: ExcelCellRange? = nil
    var onRangeSelect: ((ExcelCellAddress, ExcelCellAddress) -> Void)? = nil
    var onSelectRow: ((Int) -> Void)? = nil
    var onSelectColumn: ((Int) -> Void)? = nil
    var highlightedAddresses: Set<ExcelCellAddress> = []
    var revealAddress: ExcelCellAddress? = nil
    var canEditDrawings = false
    var onMoveDrawing: ((ExcelDrawingSelection, ExcelDrawingAnchor, ExcelDrawingAnchor) -> Bool)? = nil
    var onEditDrawing: ((ExcelDrawingSelection) -> Void)? = nil
    var onDeleteDrawing: ((ExcelDrawingSelection) -> Void)? = nil
    var activeDrawingID: String? = nil
    var onDrawingSelectionChanged: ((String?) -> Void)? = nil

    @State private var zoomScale: CGFloat = 1
    @State private var windowAddress: ExcelCellAddress?
    @State private var selectedDrawingID: String?
    @State private var drawingRevealAddress: ExcelCellAddress?
    @State private var drawingPreview: (id: String, original: ExcelDrawingAnchor, rect: CGRect)?
    @ScaledMetric(relativeTo: .caption) private var headerFontSize = 12.0
    @ScaledMetric(relativeTo: .footnote) private var footnoteFontSize = 13.0
    @ScaledMetric(relativeTo: .body) private var headerIconSize = 17.0

    private let zoomRange: ClosedRange<CGFloat> = 0.5 ... 3
    private let rowHeaderWidth: CGFloat = 54
    private let maximumVisibleRows = 400
    private let maximumVisibleColumns = 40

    private struct GridRow: Identifiable {
        let id: Int
        let y: CGFloat
        let height: CGFloat
    }
    private struct GridColumn: Identifiable {
        let id: Int
        let x: CGFloat
        let width: CGFloat
    }

    var body: some View {
        let rows = gridRows
        let width = rowHeaderWidth + (displayedGridColumns).reduce(CGFloat.zero) {
            $0 + columnWidth($1)
        }
        let rowsBottom = rows.last.map { $0.y + $0.height } ?? 42
        let size = CGSize(width: width, height: rowsBottom + noticeHeight(width: width))
        ExcelZoomScrollView(
            contentSize: size,
            zoomScale: $zoomScale,
            zoomRange: zoomRange,
            onTap: { point in
                if let item = drawingItems.reversed().first(where: { drawingRect($0)?.contains(point) == true }) {
                    selectedDrawingID = item.id
                    return
                }
                selectedDrawingID = nil
                if point.y < 42, point.x >= rowHeaderWidth {
                    var edge = rowHeaderWidth
                    for column in displayedGridColumns {
                        edge += columnWidth(column)
                        if point.x < edge { onSelectColumn?(column); break }
                    }
                } else if point.x < rowHeaderWidth, let row = gridRows.first(where: { point.y >= $0.y && point.y < $0.y + $0.height }) {
                    onSelectRow?(row.id)
                } else if let address = cellAddress(at: point) { onSelect(address) }
            },
            onRangeDrag: { start, end in
                selectedDrawingID = nil
                drawingPreview = nil
                if let first = cellAddress(at: start), let last = cellAddress(at: end) { onRangeSelect?(first, last) }
            },
            revealRect: drawingRevealRect ?? referenceRevealRect,
            frozenSize: frozenSize,
            selectedDrawing: drawingHitRegion,
            drawingContains: { point in drawingItems.contains { drawingRect($0)?.contains(point) == true } },
            onDrawingDrag: handleDrawingDrag
        ) { visible, renderScale in
            ZStack(alignment: .topLeading) {
                if visible.minY < 42 {
                    columnHeader(renderScale: renderScale, visible: visible)
                }
                ForEach(rows.filter { $0.y + $0.height > visible.minY && $0.y < visible.maxY }) { row in
                    gridRow(row.id, renderScale: renderScale, visible: visible)
                        .offset(y: row.y * renderScale)
                }
                ForEach(sheet.mergedRanges, id: \.self) { range in
                    if let rect = mergedCellRect(range), rect.intersects(visible) {
                        cell(row: range.start.row, column: range.start.column, renderScale: renderScale, mergedRange: range, size: rect.size)
                            .offset(x: rect.minX * renderScale, y: rect.minY * renderScale)
                            .accessibilityHidden(!ownsMergedAccessibility(rect, visible: visible))
                    }
                }
                if let gridNotice, visible.maxY >= rowsBottom, visible.minX >= frozenSize.width {
                    Text(gridNotice)
                        .font(.system(size: footnoteFontSize * renderScale))
                        .foregroundStyle(VisionCraftUI.secondaryText)
                        .padding(16 * renderScale)
                        .frame(width: width * renderScale, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(y: rowsBottom * renderScale)
                }
                ForEach(drawingItems) { item in
                    if let rect = drawingRect(item), rect.intersects(visible) {
                        ExcelDrawingCanvasObject(item: item, workbook: workbook, size: rect.size,
                            renderScale: renderScale, zoomScale: zoomScale,
                            selected: selectedDrawingID == item.id,
                            editable: canEditDrawings && drawingGrid.canManipulate(item.anchor),
                            onSelect: { selectedDrawingID = item.id },
                            onSettings: { onEditDrawing?(.init(id: item.id, sheetPath: sheet.partPath)) },
                            onNudge: { delta, resizing in nudgeDrawing(item, delta: delta, resizing: resizing) })
                            .offset(x: rect.minX * renderScale, y: rect.minY * renderScale)
                            .accessibilityHidden(!ownsMergedAccessibility(rect, visible: visible))
                    }
                }
            }
            .frame(width: size.width * renderScale, height: size.height * renderScale, alignment: .topLeading)
        }
        .background(VisionCraftUI.surface)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let selectedDrawing { drawingToolbar(selectedDrawing) }
        }
        .overlay(alignment: .bottomTrailing) {
            if selectedDrawing == nil, !drawingItems.isEmpty {
                drawingPicker.padding(.horizontal, 12).frame(minHeight: 48)
                    .background(.regularMaterial, in: Capsule()).padding(8)
            }
        }
        .onAppear { windowAddress = revealAddress; selectedDrawingID = activeDrawingID }
        .onChange(of: activeDrawingID) { _, id in selectedDrawingID = id }
        .onChange(of: selectedDrawingID) { _, id in onDrawingSelectionChanged?(id) }
        .onChange(of: revealAddress) { _, address in
            if let address { windowAddress = address; drawingRevealAddress = nil; selectedDrawingID = nil; drawingPreview = nil }
        }
        .onChange(of: sheet.id) { _, _ in windowAddress = revealAddress; selectedDrawingID = activeDrawingID; drawingRevealAddress = nil; drawingPreview = nil }
        .onChange(of: sheet.drawingObjects) { _, _ in
            drawingPreview = nil
            if selectedDrawing == nil { selectedDrawingID = activeDrawingID; drawingRevealAddress = nil }
            if let item = selectedDrawing { drawingRevealAddress = item.anchor.start }
        }
        .accessibilityLabel(
            AppLocalization.format("%@ 스프레드시트", sheet.name)
        )
    }

    private var drawingItems: [ExcelDrawingCanvasItem] {
        guard !sheet.isWindowed else { return [] }
        let objects = sheet.drawingObjects
        let images = objects.images.map { ExcelDrawingCanvasItem(id: $0.id, name: $0.name, anchor: $0.anchor, order: $0.displayOrder, image: $0, chart: nil) }
        let charts = objects.charts.map { ExcelDrawingCanvasItem(id: $0.id, name: $0.title, anchor: $0.anchor, order: $0.displayOrder, image: nil, chart: $0) }
        return (images + charts).sorted { $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order }
    }
    private var selectedDrawing: ExcelDrawingCanvasItem? { drawingItems.first { $0.id == selectedDrawingID } }
    private var drawingExtent: ExcelCellAddress {
        let grid = ExcelDrawingGrid(columns: [], rows: [], columnWidths: sheet.columnWidths, rowHeights: sheet.rowHeights)
        let anchors = drawingItems.map { grid.normalized($0.anchor) }
        return .init(row: min(2000, anchors.map(\.end.row).max() ?? 1), column: min(200, anchors.map(\.end.column).max() ?? 1))
    }
    private var drawingGrid: ExcelDrawingGrid {
        .init(columns: gridColumns.map { .init(index: $0.id, origin: $0.x, size: $0.width, emuSize: ExcelDrawingGrid.columnEMUs(sheet.columnWidths[$0.id] ?? 14)) },
              rows: gridRows.map { .init(index: $0.id, origin: $0.y, size: $0.height, emuSize: ExcelDrawingGrid.rowEMUs(sheet.rowHeights[$0.id] ?? 30.35)) },
              columnWidths: sheet.columnWidths, rowHeights: sheet.rowHeights)
    }
    private func drawingRect(_ item: ExcelDrawingCanvasItem) -> CGRect? {
        if drawingPreview?.id == item.id { return drawingPreview?.rect }
        return drawingGrid.rect(for: item.anchor)
    }
    private var drawingRevealRect: CGRect? {
        guard drawingRevealAddress != nil, let selectedDrawing else { return nil }
        return drawingGrid.rect(for: selectedDrawing.anchor)
    }
    private var drawingHitRegion: ExcelDrawingHitRegion? {
        guard canEditDrawings, let item = selectedDrawing, drawingGrid.canManipulate(item.anchor), let rect = drawingRect(item) else { return nil }
        return .init(id: item.id, rect: rect, bounds: drawingGrid.bounds)
    }
    private func handleDrawingDrag(_ id: String, _ rect: CGRect?, _ ended: Bool) {
        guard let item = drawingItems.first(where: { $0.id == id }), canEditDrawings else { drawingPreview = nil; return }
        guard let rect else { drawingPreview = nil; return }
        let original = drawingPreview?.original ?? item.anchor
        if ended {
            drawingPreview = nil
            guard drawingGrid.rect(for: original) != rect else { return }
            if let anchor = drawingGrid.anchor(for: rect) {
                _ = onMoveDrawing?(.init(id: id, sheetPath: sheet.partPath), original, anchor)
            }
        } else { drawingPreview = (id, original, rect) }
    }
    private func nudgeDrawing(_ item: ExcelDrawingCanvasItem, delta: CGPoint, resizing: Bool) {
        guard canEditDrawings, drawingGrid.canManipulate(item.anchor), let rect = drawingGrid.rect(for: item.anchor) else { return }
        let next = (resizing ? ExcelDrawingDragMode.bottomRight : .move).applying(delta, to: rect, within: drawingGrid.bounds)
        guard next != rect else { return }
        if let anchor = drawingGrid.anchor(for: next) { _ = onMoveDrawing?(.init(id: item.id, sheetPath: sheet.partPath), item.anchor, anchor) }
    }
    private var drawingPicker: some View {
        Menu {
            ForEach(drawingItems) { item in
                Button(item.name) {
                    selectedDrawingID = item.id
                    drawingRevealAddress = drawingGrid.normalized(item.anchor).start
                    windowAddress = drawingRevealAddress
                    drawingPreview = nil
                }
            }
        } label: { Text("개체 선택").font(.subheadline.weight(.semibold)).frame(minHeight: 48) }
    }
    private func drawingToolbar(_ item: ExcelDrawingCanvasItem) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                drawingPicker
                Text(item.name).font(.subheadline).lineLimit(1).frame(maxWidth: 180)
                Button("설정") { onEditDrawing?(.init(id: item.id, sheetPath: sheet.partPath)) }.frame(minHeight: 48)
                Button("삭제", role: .destructive) { onDeleteDrawing?(.init(id: item.id, sheetPath: sheet.partPath)); selectedDrawingID = nil }
                    .disabled(!canEditDrawings).frame(minHeight: 48)
                Button("선택 해제") { selectedDrawingID = nil; drawingPreview = nil }.frame(minHeight: 48)
                if canEditDrawings, !drawingGrid.canManipulate(item.anchor) {
                    Text("화면 구간을 벗어난 개체는 설정에서 위치를 바꿀 수 있습니다.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 12)
        }
        .background(.regularMaterial)
    }

    private var gridRows: [GridRow] {
        var y: CGFloat = 42
        return displayedGridRows.map { row in
            let height = rowHeight(row)
            defer { y += height }
            return GridRow(id: row, y: y, height: height)
        }
    }

    private var gridColumns: [GridColumn] {
        var x = rowHeaderWidth
        return displayedGridColumns.map { column in
            let width = columnWidth(column)
            defer { x += width }
            return GridColumn(id: column, x: x, width: width)
        }
    }

    private var displayedFrozenPanes: ExcelFrozenPanes {
        guard !sheet.isWindowed else { return .none }
        return ExcelFrozenPanes(rows: min(sheet.frozenPanes.rows, ExcelWorkbookDocument.maximumRowsPerSheet - 1),
                                columns: min(sheet.frozenPanes.columns, ExcelWorkbookDocument.maximumColumnsPerSheet - 1))
    }

    private var frozenSize: CGSize {
        let frozen = displayedFrozenPanes
        return CGSize(width: frozen.columns > 0 ? rowHeaderWidth + displayedGridColumns.filter { $0 <= frozen.columns }.reduce(CGFloat.zero) { $0 + columnWidth($1) } : 0,
                      height: frozen.rows > 0 ? 42 + displayedGridRows.filter { $0 <= frozen.rows }.reduce(CGFloat.zero) { $0 + rowHeight($1) } : 0)
    }

    private func ownsMergedAccessibility(_ rect: CGRect, visible: CGRect) -> Bool {
        let size = frozenSize
        let inFrozenRows = size.height > 0 && visible.maxY <= size.height
        let inFrozenColumns = size.width > 0 && visible.maxX <= size.width
        return (rect.minY < size.height) == inFrozenRows && (rect.minX < size.width) == inFrozenColumns
    }

    private var referenceRevealRect: CGRect? {
        guard let address = revealAddress,
              displayedGridColumns.contains(address.column),
              let row = gridRows.first(where: { $0.id == address.row }) else { return nil }
        let x = rowHeaderWidth + displayedGridColumns.prefix { $0 < address.column }.reduce(CGFloat.zero) { $0 + columnWidth($1) }
        return CGRect(x: x, y: row.y, width: columnWidth(address.column), height: row.height)
    }

    private func mergedCellRect(_ range: ExcelCellRange) -> CGRect? {
        ExcelMergedCellGeometry.rect(
            for: range,
            columns: displayedGridColumns,
            rows: gridRows.map { (number: $0.id, y: $0.y, height: $0.height) },
            rowHeaderWidth: rowHeaderWidth,
            columnWidth: columnWidth
        )
    }

    func cellAddress(at point: CGPoint) -> ExcelCellAddress? {
        guard point.x >= rowHeaderWidth,
              let row = gridRows.first(where: { point.y >= $0.y && point.y < $0.y + $0.height }) else {
            return nil
        }
        var x = rowHeaderWidth
        for column in displayedGridColumns {
            x += columnWidth(column)
            if point.x < x {
                return ExcelCellAddress(row: row.id, column: column)
            }
        }
        return nil
    }

    private func gridRow(_ row: Int, renderScale: CGFloat, visible: CGRect) -> some View {
        HStack(spacing: 0) {
            Text(String(row))
                .font(.system(size: headerFontSize * renderScale).monospacedDigit())
                .foregroundStyle(VisionCraftUI.secondaryText)
                .frame(width: rowHeaderWidth * renderScale, height: rowHeight(row) * renderScale)
                .background(VisionCraftUI.surfaceVariant)
                .overlay(alignment: .trailing) { Divider() }
                .accessibilityLabel(AppLocalization.format("%lld행 머리글", row))
                .accessibilityAddTraits(.isHeader)
                .accessibilityHidden(row > sheet.maximumRow || visible.minX >= rowHeaderWidth)
            ForEach(gridColumns) { column in
                if column.x + column.width <= visible.minX || column.x >= visible.maxX || sheet.mergedRange(containing: ExcelCellAddress(row: row, column: column.id)) != nil {
                    Color.clear
                        .frame(width: column.width * renderScale, height: rowHeight(row) * renderScale)
                        .accessibilityHidden(true)
                } else {
                    cell(row: row, column: column.id, renderScale: renderScale)
                }
            }
        }
    }

    private var gridNotice: String? {
        guard sheet.maximumRow > displayedGridRows.count
            || sheet.maximumColumn > visibleColumnCount
            || sheet.didTruncate else { return nil }
        return AppLocalization.string(
            sheet.isWindowed
                ? "대용량 시트는 선택한 행 구간과 최대 40열씩 표시합니다. 저장 시 나머지 데이터는 유지됩니다."
                : "큰 시트는 본문을 400행·40열씩 표시합니다. 고정한 행·열은 함께 표시되며, 셀 이동으로 다른 구간을 볼 수 있습니다. 저장 시 나머지 데이터는 유지됩니다."
        )
    }

    private func noticeHeight(width: CGFloat) -> CGFloat {
        guard let gridNotice else { return 0 }
        let textSize = (gridNotice as NSString).boundingRect(
            with: CGSize(width: max(1, width - 32), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.systemFont(ofSize: footnoteFontSize)],
            context: nil
        )
        return ceil(textSize.height) + 34
    }

    private func columnHeader(renderScale: CGFloat, visible: CGRect) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "tablecells")
                .font(.system(size: headerIconSize * renderScale))
                .foregroundStyle(VisionCraftUI.secondaryText)
                .frame(width: rowHeaderWidth * renderScale, height: 42 * renderScale)
                .background(VisionCraftUI.surfaceVariant)
            ForEach(gridColumns) { column in
                if column.x + column.width <= visible.minX || column.x >= visible.maxX {
                    Color.clear.frame(width: column.width * renderScale, height: 42 * renderScale).accessibilityHidden(true)
                } else {
                Text(ExcelCellAddress.columnName(column.id))
                    .font(.system(size: headerFontSize * renderScale, weight: .semibold))
                    .foregroundStyle(VisionCraftUI.secondaryText)
                    .frame(width: column.width * renderScale, height: 42 * renderScale)
                    .background(VisionCraftUI.surfaceVariant)
                    .overlay {
                        Rectangle()
                            .stroke(VisionCraftUI.outline, lineWidth: 0.5 * renderScale)
                    }
                    .accessibilityLabel(
                        AppLocalization.format(
                            "%@ 열 머리글",
                            ExcelCellAddress.columnName(column.id)
                        )
                    )
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHidden(column.id > sheet.maximumColumn)
                }
            }
        }
    }

    private func cell(row: Int, column: Int, renderScale: CGFloat, mergedRange: ExcelCellRange? = nil, size: CGSize? = nil) -> some View {
        let address = ExcelCellAddress(row: row, column: column)
        let canonical = sheet.canonicalAddress(for: address)
        let cell = sheet.cell(at: canonical)
        let style = workbook.style(at: cell?.styleIndex)
        let conditionalRule = sheet.matchingConditionalRule(at: canonical)
        let conditionalStyle = conditionalRule.flatMap { rule in
            workbook.differentialStyles.indices.contains(
                rule.differentialStyleIndex
            ) ? workbook.differentialStyles[rule.differentialStyleIndex] : nil
        }
        let hyperlink = sheet.annotations.hyperlink(at: canonical)
        let note = sheet.annotations.note(at: canonical)
        let isSelected = selectedDrawingID == nil && (mergedRange.map { selectedRange?.intersects($0) ?? (selectedAddress == canonical) }
            ?? (selectedRange?.contains(address) ?? (selectedAddress == canonical)))
        let isReferenced = mergedRange.map { range in highlightedAddresses.contains(where: range.contains) }
            ?? highlightedAddresses.contains(canonical)
        let isMergedChild = canonical != address
        let label = Text(isMergedChild ? "" : cell?.displayValue ?? "")
                .font(cellFont(style, bold: conditionalStyle?.isBold == true, scale: renderScale))
                .foregroundStyle(
                    textColor(
                        conditionalStyle?.fontARGB ?? style.fontARGB,
                        isHyperlink: hyperlink != nil
                    )
                )
                .underline(hyperlink != nil || style.isUnderlined)
                .lineLimit(style.wrapText ? nil : 1)
                .frame(
                    width: max(0, (size?.width ?? columnWidth(column)) - 12) * renderScale,
                    height: max(0, (size?.height ?? rowHeight(row)) - 8) * renderScale,
                    alignment: alignment(for: style)
                )
                .padding(.horizontal, 6 * renderScale)
                .padding(.vertical, 4 * renderScale)
                .clipped()
        let decorated = label.background {
                    fillColor(
                        conditionalStyle?.fillARGB ?? style.fillARGB
                    )
                    .overlay(
                        isSelected
                            ? VisionCraftUI.primary.opacity(0.16)
                            : Color.clear
                    )
                }
                .overlay {
                    GeometryReader { geometry in
                        Path { path in
                            for edge in style.borderEdges.keys {
                                switch edge {
                                case "top": path.move(to: .zero); path.addLine(to: CGPoint(x: geometry.size.width, y: 0))
                                case "bottom": path.move(to: CGPoint(x: 0, y: geometry.size.height)); path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                                case "left": path.move(to: .zero); path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                                case "right": path.move(to: CGPoint(x: geometry.size.width, y: 0)); path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                                default: break
                                }
                            }
                        }
                        .stroke(textColor(style.borderEdges.values.first, isHyperlink: false), lineWidth: 1.2 * renderScale)
                    }
                }
                .overlay {
                    if isReferenced {
                        Rectangle()
                            .inset(by: (isSelected ? 3 : 1) * renderScale)
                            .stroke(
                                Color.purple,
                                style: StrokeStyle(
                                    lineWidth: 1.5 * renderScale,
                                    dash: [4 * renderScale, 3 * renderScale]
                                )
                            )
                    }
                }
                .overlay {
                    Rectangle()
                        .stroke(
                            isSelected
                                ? VisionCraftUI.primary
                                : VisionCraftUI.outline,
                            lineWidth: (isSelected ? 2 : 0.5) * renderScale
                        )
                }
        return decorated.overlay(alignment: .topTrailing) {
                    HStack(spacing: 2 * renderScale) {
                        if hyperlink != nil {
                            Image(systemName: "link")
                        }
                        if note != nil {
                            Image(systemName: "note.text")
                        }
                    }
                    .font(.system(size: 9 * renderScale, weight: .semibold))
                    .foregroundStyle(VisionCraftUI.primary)
                    .padding(2 * renderScale)
                }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            accessibilityLabel(
                for: canonical,
                cell: cell
            )
        )
        .accessibilityValue(
            cell?.formula.map { AppLocalization.format("수식 %@", $0) } ?? ""
        )
        .accessibilityHint("두 번 탭하면 이 셀을 선택합니다. 동작에서 셀 값 편집을 선택할 수 있습니다.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onSelect(address) }
        .accessibilityAction(named: "셀 값 편집") {
            onEdit(canonical)
        }
        .accessibilityHidden(
            isMergedChild
                || (cell == nil
                    && (row > sheet.maximumRow
                        || column > sheet.maximumColumn))
        )
    }

    private func accessibilityLabel(
        for address: ExcelCellAddress,
        cell: ExcelCell?
    ) -> String {
        let value = cell?.displayValue.isEmpty == false
            ? cell!.displayValue
            : AppLocalization.string("빈 셀")
        if let region = regions.first(where: { $0.contains(address) }),
           let column = region.columns.first(where: {
               $0.column == address.column
           }),
           address.row != region.headerRow {
            let dataIndex = region.rowNumbers.firstIndex(of: address.row)
            let position = dataIndex.map {
                AppLocalization.format(
                    "%lld번째 데이터 행",
                    $0 + 1
                )
            } ?? AppLocalization.format("원본 %lld행", address.row)
            return addingConditionalFormattingDescription(
                to: AppLocalization.format(
                "%@, %@. %@. %@ 셀",
                column.title,
                value,
                position,
                address.reference
                ),
                at: address
            )
        }
        if let mergedRange = sheet.mergedRange(containing: address) {
            return addingConditionalFormattingDescription(
                to: AppLocalization.format(
                    "%@ 셀, %@. %@ 범위 병합 셀",
                    address.reference,
                    value,
                    mergedRange.reference
                ),
                at: address
            )
        }
        return addingConditionalFormattingDescription(
            to: AppLocalization.format(
                "%@ 셀, %@",
                address.reference,
                value
            ),
            at: address
        )
    }

    private func addingConditionalFormattingDescription(
        to label: String,
        at address: ExcelCellAddress
    ) -> String {
        var result = label
        if highlightedAddresses.contains(address) {
            result += ". " + AppLocalization.string("대화 관련 셀")
        }
        if let rule = sheet.matchingConditionalRule(at: address),
           workbook.differentialStyles.indices.contains(
               rule.differentialStyleIndex
           ) {
            let style = workbook.differentialStyles[
                rule.differentialStyleIndex
            ]
            let highlight = ExcelConditionalHighlight.matching(style)?.title
                ?? AppLocalization.string("색상")
            result += AppLocalization.format(
                ". 조건부 서식 %@ 강조",
                highlight
            )
        }
        if let hyperlink = sheet.annotations.hyperlink(at: address) {
            result += AppLocalization.format(
                ". 하이퍼링크 %@",
                hyperlink.tooltip ?? hyperlink.target
            )
        }
        if let note = sheet.annotations.note(at: address) {
            result += AppLocalization.format(
                ". %@의 메모, %@",
                note.author,
                note.text
            )
        }
        return result
    }

    private var visibleRowCount: Int {
        max(1, min(max(sheet.maximumRow + 5, 30), maximumVisibleRows))
    }

    private var displayedGridRows: [Int] {
        if let visibleRows,
           !visibleRows.isEmpty {
            return visibleRows.filter { !sheet.hiddenRows.contains($0) }
        }
        let frozen = displayedFrozenPanes.rows
        let start = max(frozen + 1, (drawingRevealAddress ?? revealAddress ?? windowAddress).map { (($0.row - 1) / maximumVisibleRows) * maximumVisibleRows + 1 } ?? 1)
        let end = max(start, min(start + maximumVisibleRows - 1, max(sheet.maximumRow + 5, selectedRange?.end.row ?? 1, drawingExtent.row + 2, 30)))
        let pinned = frozen > 0 ? Array(1 ... frozen) : []
        return (pinned + Array(start ... end)).filter { !sheet.hiddenRows.contains($0) }
    }

    private var displayedGridColumns: [Int] {
        let frozen = displayedFrozenPanes.columns
        let start = max(frozen + 1, (drawingRevealAddress ?? revealAddress ?? windowAddress).map { (($0.column - 1) / maximumVisibleColumns) * maximumVisibleColumns + 1 } ?? 1)
        let end = max(start, min(start + maximumVisibleColumns - 1, max(sheet.maximumColumn, selectedRange?.end.column ?? 1, drawingExtent.column + 1, start + 7)))
        let pinned = frozen > 0 ? Array(1 ... frozen) : []
        return pinned + Array(start ... end)
    }

    private func cellFont(_ style: ExcelCellStyle, bold: Bool, scale: CGFloat) -> Font {
        let size = CGFloat(style.fontSize ?? 11) * (16.0 / 11.0) * scale
        var font = style.fontName.flatMap { UIFont(name: $0, size: size) }.map(Font.init) ?? .system(size: size)
        if style.isBold || bold { font = font.bold() }
        if style.isItalic { font = font.italic() }
        return font
    }

    private var visibleColumnCount: Int {
        max(1, min(max(sheet.maximumColumn, 8), maximumVisibleColumns))
    }

    private func columnWidth(_ column: Int) -> CGFloat {
        let excelWidth = sheet.columnWidths[column] ?? 14
        return min(max(CGFloat(excelWidth) * 7.2 + 12, 24), 1848)
    }

    private func rowHeight(_ row: Int) -> CGFloat {
        min(max(CGFloat(sheet.rowHeights[row] ?? 30.35) * 1.45, 16), 600)
    }

    private func alignment(for style: ExcelCellStyle) -> Alignment {
        let horizontal: HorizontalAlignment = style.horizontalAlignment == "center" ? .center : style.horizontalAlignment == "right" ? .trailing : .leading
        let vertical: VerticalAlignment = style.verticalAlignment == "top" ? .top : style.verticalAlignment == "bottom" ? .bottom : .center
        return Alignment(horizontal: horizontal, vertical: vertical)
    }

    private func fillColor(_ argb: String?) -> Color {
        guard let argb else {
            return VisionCraftUI.surface
        }
        let cleaned = argb.count == 8
            ? String(argb.dropFirst(2))
            : argb
        guard cleaned.count == 6,
              let value = UInt32(cleaned, radix: 16) else {
            return VisionCraftUI.surface
        }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private func textColor(
        _ argb: String?,
        isHyperlink: Bool
    ) -> Color {
        guard let argb else {
            return isHyperlink ? VisionCraftUI.primary : VisionCraftUI.primaryText
        }
        let cleaned = argb.count == 8
            ? String(argb.dropFirst(2))
            : argb
        guard cleaned.count == 6,
              let value = UInt32(cleaned, radix: 16) else {
            return VisionCraftUI.primaryText
        }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

private struct ExcelCellAnnotationsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hyperlinkTarget: String
    @State private var hyperlinkTooltip: String
    @State private var noteText: String
    @State private var noteAuthor: String
    @State private var errorMessage: String?

    let onSave: (String, String, String, String) -> Bool

    init(
        initialHyperlinkTarget: String,
        initialHyperlinkTooltip: String,
        initialNoteText: String,
        initialNoteAuthor: String,
        onSave: @escaping (String, String, String, String) -> Bool
    ) {
        _hyperlinkTarget = State(initialValue: initialHyperlinkTarget)
        _hyperlinkTooltip = State(initialValue: initialHyperlinkTooltip)
        _noteText = State(initialValue: initialNoteText)
        _noteAuthor = State(initialValue: initialNoteAuthor)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "https://example.com",
                        text: $hyperlinkTarget
                    )
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .accessibilityLabel("하이퍼링크 주소")
                    TextField(
                        "링크 설명(선택 사항)",
                        text: $hyperlinkTooltip
                    )
                } header: {
                    Text("하이퍼링크")
                } footer: {
                    Text("웹 주소는 https://로 시작합니다. 비워 두면 기존 링크가 제거됩니다.")
                }

                Section {
                    TextEditor(text: $noteText)
                        .frame(minHeight: 120)
                        .accessibilityLabel("Excel 메모 내용")
                    TextField("작성자", text: $noteAuthor)
                        .accessibilityLabel("메모 작성자")
                } header: {
                    Text("메모")
                } footer: {
                    Text("Excel의 기존 메모 형식으로 저장됩니다. 내용을 비우면 메모가 제거됩니다.")
                }

                if let errorMessage {
                    Section {
                        Label(
                            errorMessage,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(VisionCraftUI.warning)
                    }
                }
            }
            .navigationTitle("링크·메모")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") {
                        if onSave(
                            hyperlinkTarget,
                            hyperlinkTooltip,
                            noteText,
                            noteAuthor
                        ) {
                            dismiss()
                        } else {
                            errorMessage = "링크 주소를 확인하거나 변경할 내용을 입력해 주세요."
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}

private struct ExcelConditionalFormattingEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ExcelConditionalRuleKind
    @State private var comparisonValue: String
    @State private var highlight: ExcelConditionalHighlight
    @State private var errorMessage: String?

    let appliesToCurrentColumn: Bool
    let onSave: (
        ExcelConditionalRuleKind,
        String,
        ExcelConditionalHighlight
    ) -> Bool

    init(
        initialKind: ExcelConditionalRuleKind,
        initialComparisonValue: String,
        initialHighlight: ExcelConditionalHighlight,
        appliesToCurrentColumn: Bool,
        onSave: @escaping (
            ExcelConditionalRuleKind,
            String,
            ExcelConditionalHighlight
        ) -> Bool
    ) {
        _kind = State(initialValue: initialKind)
        _comparisonValue = State(initialValue: initialComparisonValue)
        _highlight = State(initialValue: initialHighlight)
        self.appliesToCurrentColumn = appliesToCurrentColumn
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("조건") {
                    Picker("규칙", selection: $kind) {
                        ForEach(ExcelConditionalRuleKind.allCases) { rule in
                            Text(rule.title).tag(rule)
                        }
                    }
                    TextField(
                        kind.requiresNumber ? "비교할 숫자" : "비교할 값",
                        text: $comparisonValue
                    )
                    .keyboardType(kind.requiresNumber ? .decimalPad : .default)
                    .accessibilityLabel(
                        kind.requiresNumber ? "비교할 숫자" : "비교할 값"
                    )
                }

                Section("강조 색") {
                    Picker("색", selection: $highlight) {
                        ForEach(ExcelConditionalHighlight.allCases) { choice in
                            Label {
                                Text(choice.title)
                            } icon: {
                                Image(systemName: "square.fill")
                                    .foregroundStyle(previewColor(choice))
                            }
                            .tag(choice)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("적용 범위") {
                    Text(
                        appliesToCurrentColumn
                            ? "현재 열 데이터 전체"
                            : "선택한 셀"
                    )
                }

                if let errorMessage {
                    Section {
                        Label(
                            errorMessage,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(VisionCraftUI.warning)
                    }
                }
            }
            .navigationTitle("조건부 서식")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") {
                        if onSave(kind, comparisonValue, highlight) {
                            dismiss()
                        } else {
                            errorMessage = kind.requiresNumber
                                ? "비교할 숫자를 확인해 주세요."
                                : "비교할 값을 입력해 주세요."
                        }
                    }
                    .disabled(
                        comparisonValue.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func previewColor(
        _ highlight: ExcelConditionalHighlight
    ) -> Color {
        switch highlight {
        case .red: return Color.red.opacity(0.65)
        case .yellow: return Color.yellow.opacity(0.8)
        case .green: return Color.green.opacity(0.65)
        }
    }
}

private struct ExcelDropdownEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var valuesText: String
    @State private var allowsBlank: Bool
    @State private var errorMessage: String?

    let appliesToCurrentColumn: Bool
    let onSave: ([String], Bool) -> Bool

    init(
        initialValues: [String],
        initialAllowsBlank: Bool,
        appliesToCurrentColumn: Bool,
        onSave: @escaping ([String], Bool) -> Bool
    ) {
        _valuesText = State(
            initialValue: initialValues.joined(separator: "\n")
        )
        _allowsBlank = State(initialValue: initialAllowsBlank)
        self.appliesToCurrentColumn = appliesToCurrentColumn
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $valuesText)
                        .frame(minHeight: 150)
                        .font(.body.monospaced())
                        .accessibilityLabel("드롭다운 항목")
                        .accessibilityHint("한 줄에 항목을 하나씩 입력합니다.")
                } header: {
                    Text("목록 값")
                } footer: {
                    Text("한 줄에 하나씩 입력하세요. 빈 줄과 같은 항목은 자동으로 제외됩니다.")
                }

                Section("입력 규칙") {
                    Toggle("빈 셀 허용", isOn: $allowsBlank)
                    LabeledContent(
                        "적용 범위",
                        value: appliesToCurrentColumn
                            ? "현재 열 데이터 전체"
                            : "선택한 셀"
                    )
                }

                if let errorMessage {
                    Section {
                        Label(
                            errorMessage,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(VisionCraftUI.warning)
                    }
                }
            }
            .navigationTitle("드롭다운 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") {
                        let values = valuesText.components(
                            separatedBy: .newlines
                        )
                        if onSave(values, allowsBlank) {
                            dismiss()
                        } else {
                            errorMessage = AppLocalization.string(
                                "목록 값을 확인해 주세요. 서로 다른 항목이 2개 이상 필요합니다."
                            )
                        }
                    }
                    .disabled(candidateValues.count < 2)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var candidateValues: [String] {
        Array(
            Set(
                valuesText.components(separatedBy: .newlines).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
            )
        )
    }
}

private struct ExcelShapeEditorState: Identifiable {
    let id = UUID()
    let shapeID: String?
    let name: String
    let text: String
    let kind: ExcelShapeKind
}

private struct ExcelSheetShapeRow: View {
    let shape: ExcelSheetShape
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: shape.kind == .textBox
                ? "textbox"
                : "square.on.circle")
                .font(.title2)
                .foregroundStyle(VisionCraftUI.primary)
                .frame(width: 44, height: 44)
                .background(
                    VisionCraftUI.surfaceVariant,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(shape.name).font(.body.weight(.semibold))
                Text(
                    shape.kind.title + " · "
                        + shape.anchor.start.reference + "–"
                        + shape.anchor.end.reference
                )
                .font(.caption)
                .foregroundStyle(VisionCraftUI.secondaryText)
                if !shape.text.isEmpty {
                    Text(shape.text)
                        .font(.caption)
                        .foregroundStyle(VisionCraftUI.secondaryText)
                        .lineLimit(2)
                }
            }
            Spacer()
            Menu {
                if shape.kind.isEditable {
                    Button("도형 편집", systemImage: "slider.horizontal.3") {
                        onEdit()
                    }
                }
                Button("도형 삭제", systemImage: "trash", role: .destructive) {
                    onRemove()
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
            .accessibilityLabel("\(shape.name) 동작")
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ExcelShapeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var text: String
    @State private var kind: ExcelShapeKind
    @State private var showsSaveError = false

    let configuration: ExcelShapeEditorState
    let onSave: (String, String, ExcelShapeKind) -> Bool

    init(
        configuration: ExcelShapeEditorState,
        onSave: @escaping (String, String, ExcelShapeKind) -> Bool
    ) {
        self.configuration = configuration
        self.onSave = onSave
        _name = State(initialValue: configuration.name)
        _text = State(initialValue: configuration.text)
        _kind = State(initialValue: configuration.kind)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("도형 설정") {
                    TextField("개체 이름", text: $name)
                    Picker("종류", selection: $kind) {
                        ForEach(ExcelShapeKind.allCases.filter(\.isEditable)) {
                            Text($0.title).tag($0)
                        }
                    }
                }
                Section("표시할 텍스트") {
                    TextEditor(text: $text).frame(minHeight: 100)
                }
                if configuration.shapeID != nil {
                    Section {
                        Label(
                            "도형을 편집하면 지원되는 기본 도형 구조로 저장됩니다.",
                            systemImage: "info.circle"
                        )
                    }
                }
            }
            .navigationTitle(
                configuration.shapeID == nil ? "도형 추가" : "도형 편집"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(configuration.shapeID == nil ? "추가" : "적용") {
                        if onSave(name, text, kind) {
                            dismiss()
                        } else {
                            showsSaveError = true
                        }
                    }
                }
            }
            .alert("도형을 저장할 수 없습니다", isPresented: $showsSaveError) {
                Button("확인", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ExcelChartEditorState: Identifiable {
    let id = UUID()
    let chartID: String?
    let title: String
    let kind: ExcelChartKind
    let sourceReference: String
}

private struct ExcelSheetChartRow: View {
    let chart: ExcelSheetChart
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(VisionCraftUI.primary)
                .frame(width: 44, height: 44)
                .background(
                    VisionCraftUI.surfaceVariant,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(chart.title)
                    .font(.body.weight(.semibold))
                Text(
                    chart.kind.title + " · "
                        + (chart.sourceRange?.reference
                            ?? AppLocalization.string("범위 확인 불가"))
                )
                .font(.caption)
                .foregroundStyle(VisionCraftUI.secondaryText)
            }
            Spacer()
            Menu {
                if chart.kind.isEditable,
                   chart.sourceRange != nil {
                    Button("차트 설정 편집", systemImage: "slider.horizontal.3") {
                        onEdit()
                    }
                }
                Button("차트 삭제", systemImage: "trash", role: .destructive) {
                    onRemove()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .accessibilityLabel("\(chart.title) 동작")
        }
        .accessibilityElement(children: .contain)
    }

    private var iconName: String {
        switch chart.kind {
        case .column: return "chart.bar.xaxis"
        case .bar: return "chart.bar.xaxis"
        case .line: return "chart.xyaxis.line"
        case .pie: return "chart.pie"
        case .area: return "chart.bar.fill"
        case .scatter: return "chart.dots.scatter"
        case .doughnut: return "chart.pie.fill"
        case .radar: return "pentagon"
        case .unsupported: return "chart.dots.scatter"
        }
    }
}

private struct ExcelChartEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var kind: ExcelChartKind
    @State private var sourceReference: String
    @State private var showsSaveError = false

    let configuration: ExcelChartEditorState
    let onSave: (String, ExcelChartKind, String) -> Bool

    init(
        configuration: ExcelChartEditorState,
        onSave: @escaping (String, ExcelChartKind, String) -> Bool
    ) {
        self.configuration = configuration
        self.onSave = onSave
        _title = State(initialValue: configuration.title)
        _kind = State(initialValue: configuration.kind)
        _sourceReference = State(
            initialValue: configuration.sourceReference
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("차트 설정") {
                    TextField("차트 제목", text: $title)
                    Picker("차트 종류", selection: $kind) {
                        ForEach(
                            ExcelChartKind.allCases.filter(\.isEditable)
                        ) { chartKind in
                            Text(chartKind.title).tag(chartKind)
                        }
                    }
                }
                Section {
                    TextField("예: A1:C10", text: $sourceReference)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("원본 셀 범위")
                } footer: {
                    Text(
                        "첫 행은 계열 이름, 첫 열은 항목 이름으로 사용합니다. 원형 차트는 첫 번째 값 계열을 사용합니다."
                    )
                }
                if configuration.chartID != nil {
                    Section {
                        Label(
                            "기존 차트를 수정하면 지원되는 기본 차트 구조로 저장됩니다.",
                            systemImage: "info.circle"
                        )
                    }
                }
            }
            .navigationTitle(
                configuration.chartID == nil ? "차트 추가" : "차트 편집"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(configuration.chartID == nil ? "추가" : "적용") {
                        if onSave(title, kind, sourceReference) {
                            dismiss()
                        } else {
                            showsSaveError = true
                        }
                    }
                    .disabled(!hasValidRange)
                }
            }
            .alert("차트를 저장할 수 없습니다", isPresented: $showsSaveError) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("현재 시트 안의 머리글과 데이터가 포함된 범위를 확인해 주세요.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var hasValidRange: Bool {
        guard let range = ExcelCellRange(
            sourceReference.trimmingCharacters(in: .whitespacesAndNewlines)
        ) else {
            return false
        }
        return range.end.row > range.start.row
    }
}

private struct ExcelPivotEditorState: Identifiable {
    let id = UUID()
    let pivotID: String?
    let name: String
    let sourceReference: String
    let destinationReference: String
    let rowFieldIndex: Int
    let dataFieldIndex: Int
    let aggregation: ExcelPivotAggregation
    let refreshOnLoad: Bool
    let supportsFieldEditing: Bool
}

private struct ExcelSheetPivotRow: View {
    let pivot: ExcelPivotTable
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tablecells")
                .font(.title2)
                .foregroundStyle(VisionCraftUI.primary)
                .frame(width: 44, height: 44)
                .background(
                    VisionCraftUI.surfaceVariant,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(pivot.name)
                    .font(.body.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(VisionCraftUI.secondaryText)
            }
            Spacer()
            Menu {
                if pivot.supportsMetadataEditing {
                    Button(
                        "피벗 설정 편집",
                        systemImage: "slider.horizontal.3"
                    ) {
                        onEdit()
                    }
                }
                Button(
                    "피벗 삭제",
                    systemImage: "trash",
                    role: .destructive
                ) {
                    onRemove()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .accessibilityLabel("\(pivot.name) 동작")
        }
        .accessibilityElement(children: .contain)
    }

    private var description: String {
        let source = pivot.sourceRange?.reference
            ?? AppLocalization.string("원본 범위 확인 불가")
        let destination = pivot.destinationRange?.start.reference
            ?? AppLocalization.string("결과 위치 확인 불가")
        return source + " → " + destination
            + (pivot.refreshOnLoad
                ? " · " + AppLocalization.string("열 때 새로고침")
                : "")
    }
}

private struct ExcelPivotEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var sourceReference: String
    @State private var destinationReference: String
    @State private var rowFieldIndex: Int
    @State private var dataFieldIndex: Int
    @State private var aggregation: ExcelPivotAggregation
    @State private var refreshOnLoad: Bool
    @State private var showsSaveError = false

    let configuration: ExcelPivotEditorState
    let fieldNamesForReference: (String) -> [String]
    let onSave: (
        String,
        String,
        String,
        Int,
        Int,
        ExcelPivotAggregation,
        Bool
    ) -> Bool

    init(
        configuration: ExcelPivotEditorState,
        fieldNamesForReference: @escaping (String) -> [String],
        onSave: @escaping (
            String,
            String,
            String,
            Int,
            Int,
            ExcelPivotAggregation,
            Bool
        ) -> Bool
    ) {
        self.configuration = configuration
        self.fieldNamesForReference = fieldNamesForReference
        self.onSave = onSave
        _name = State(initialValue: configuration.name)
        _sourceReference = State(
            initialValue: configuration.sourceReference
        )
        _destinationReference = State(
            initialValue: configuration.destinationReference
        )
        _rowFieldIndex = State(initialValue: configuration.rowFieldIndex)
        _dataFieldIndex = State(initialValue: configuration.dataFieldIndex)
        _aggregation = State(initialValue: configuration.aggregation)
        _refreshOnLoad = State(initialValue: configuration.refreshOnLoad)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("피벗 설정") {
                    TextField("피벗 이름", text: $name)
                    Toggle("문서를 열 때 새로고침", isOn: $refreshOnLoad)
                }

                if configuration.supportsFieldEditing {
                    Section {
                        TextField("예: A1:C100", text: $sourceReference)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        TextField("예: G1", text: $destinationReference)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    } header: {
                        Text("범위")
                    } footer: {
                        Text(
                            "원본 첫 행은 필드 이름으로 사용합니다. 결과 영역은 원본 또는 다른 값과 겹칠 수 없습니다."
                        )
                    }

                    Section("행과 값") {
                        Picker("행 필드", selection: $rowFieldIndex) {
                            ForEach(Array(fieldNames.enumerated()), id: \.offset) {
                                index,
                                fieldName in
                                Text(fieldName).tag(index)
                            }
                        }
                        Picker("값 필드", selection: $dataFieldIndex) {
                            ForEach(Array(fieldNames.enumerated()), id: \.offset) {
                                index,
                                fieldName in
                                Text(fieldName).tag(index)
                            }
                        }
                        Picker("계산", selection: $aggregation) {
                            ForEach(ExcelPivotAggregation.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                    }
                } else {
                    Section {
                        Label(
                            "이 피벗은 고급 구조라 이름과 새로고침 설정만 바꿀 수 있습니다.",
                            systemImage: "info.circle"
                        )
                    }
                }
            }
            .navigationTitle(
                configuration.pivotID == nil ? "피벗 추가" : "피벗 편집"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(configuration.pivotID == nil ? "추가" : "적용") {
                        if onSave(
                            name,
                            sourceReference,
                            destinationReference,
                            rowFieldIndex,
                            dataFieldIndex,
                            aggregation,
                            refreshOnLoad
                        ) {
                            dismiss()
                        } else {
                            showsSaveError = true
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .alert(
                "피벗을 저장할 수 없습니다",
                isPresented: $showsSaveError
            ) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("이름, 원본 범위, 결과 위치와 필드 선택을 확인해 주세요.")
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: sourceReference) { _, _ in
            if !fieldNames.indices.contains(rowFieldIndex) {
                rowFieldIndex = 0
            }
            if !fieldNames.indices.contains(dataFieldIndex)
                || dataFieldIndex == rowFieldIndex {
                dataFieldIndex = fieldNames.count > 1 ? 1 : 0
            }
        }
    }

    private var fieldNames: [String] {
        fieldNamesForReference(sourceReference)
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return false
        }
        guard configuration.supportsFieldEditing else {
            return true
        }
        return fieldNames.count >= 2
            && fieldNames.indices.contains(rowFieldIndex)
            && fieldNames.indices.contains(dataFieldIndex)
            && rowFieldIndex != dataFieldIndex
            && ExcelCellRange(sourceReference) != nil
            && ExcelCellAddress(destinationReference) != nil
    }
}

private struct ExcelSheetImageManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var newImageItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var chartEditor: ExcelChartEditorState?
    @State private var shapeEditor: ExcelShapeEditorState?
    @State private var pivotEditor: ExcelPivotEditorState?

    let images: [ExcelSheetImage]
    let charts: [ExcelSheetChart]
    let shapes: [ExcelSheetShape]
    let pivotTables: [ExcelPivotTable]
    let selectedCellReference: String
    let defaultChartSourceReference: String
    let defaultPivotDestinationReference: String
    let pivotFieldNames: (String) -> [String]
    let onAdd: (Data) -> Bool
    let onReplace: (String, Data) -> Bool
    let onRemove: (String) -> Void
    let onAddChart: (String, ExcelChartKind, String) -> Bool
    let onUpdateChart: (String, String, ExcelChartKind, String) -> Bool
    let onRemoveChart: (String) -> Void
    let onAddShape: (String, String, ExcelShapeKind) -> Bool
    let onUpdateShape: (String, String, String, ExcelShapeKind) -> Bool
    let onRemoveShape: (String) -> Void
    let onAddPivot: (
        String,
        String,
        String,
        Int,
        Int,
        ExcelPivotAggregation,
        Bool
    ) -> Bool
    let onUpdatePivot: (
        String,
        String,
        String,
        String,
        Int,
        Int,
        ExcelPivotAggregation,
        Bool
    ) -> Bool
    let onRemovePivot: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PhotosPicker(
                        selection: $newImageItem,
                        matching: .images
                    ) {
                        Label(
                            "사진 보관함에서 이미지 추가",
                            systemImage: "photo.badge.plus"
                        )
                    }
                } footer: {
                    Text(
                        "새 이미지는 현재 선택한 \(selectedCellReference) 셀부터 배치됩니다. PNG와 JPEG, 최대 20MB를 지원합니다."
                    )
                }

                Section("이미지 \(images.count)개") {
                    if images.isEmpty {
                        Text("이 시트에 이미지가 없습니다.")
                            .foregroundStyle(VisionCraftUI.secondaryText)
                    } else {
                        ForEach(images) { image in
                            ExcelSheetImageRow(
                                image: image,
                                onReplace: onReplace,
                                onRemove: onRemove,
                                onError: { errorMessage = $0 }
                            )
                        }
                    }
                }

                Section {
                    Button("도형·텍스트 상자 추가", systemImage: "square.on.circle") {
                        shapeEditor = ExcelShapeEditorState(
                            shapeID: nil,
                            name: AppLocalization.format(
                                "도형 %lld",
                                shapes.count + 1
                            ),
                            text: "",
                            kind: .textBox
                        )
                    }
                    if shapes.isEmpty {
                        Text("이 시트에 도형이나 텍스트 상자가 없습니다.")
                            .foregroundStyle(VisionCraftUI.secondaryText)
                    } else {
                        ForEach(shapes) { shape in
                            ExcelSheetShapeRow(
                                shape: shape,
                                onEdit: {
                                    shapeEditor = ExcelShapeEditorState(
                                        shapeID: shape.id,
                                        name: shape.name,
                                        text: shape.text,
                                        kind: shape.kind
                                    )
                                },
                                onRemove: { onRemoveShape(shape.id) }
                            )
                        }
                    }
                } header: {
                    Text("도형·텍스트 상자 \(shapes.count)개")
                } footer: {
                    Text(
                        "새 개체는 현재 선택한 \(selectedCellReference) 셀부터 배치됩니다. 사각형·둥근 사각형·타원·선·텍스트 상자를 지원합니다."
                    )
                }

                Section {
                    Button("차트 추가", systemImage: "chart.bar.xaxis") {
                        chartEditor = ExcelChartEditorState(
                            chartID: nil,
                            title: AppLocalization.format(
                                "차트 %lld",
                                charts.count + 1
                            ),
                            kind: .column,
                            sourceReference: defaultChartSourceReference
                        )
                    }
                    if charts.isEmpty {
                        Text("이 시트에 차트가 없습니다.")
                            .foregroundStyle(VisionCraftUI.secondaryText)
                    } else {
                        ForEach(charts) { chart in
                            ExcelSheetChartRow(
                                chart: chart,
                                onEdit: {
                                    chartEditor = ExcelChartEditorState(
                                        chartID: chart.id,
                                        title: chart.title,
                                        kind: chart.kind,
                                        sourceReference:
                                            chart.sourceRange?.reference
                                                ?? defaultChartSourceReference
                                    )
                                },
                                onRemove: { onRemoveChart(chart.id) }
                            )
                        }
                    }
                } header: {
                    Text("차트 \(charts.count)개")
                } footer: {
                    Text(
                        "막대·꺾은선·원형·영역·분산형·도넛·방사형 차트를 지원합니다. 그 밖의 고급 차트는 수정하지 않는 동안 원본 형식을 유지합니다."
                    )
                }

                Section {
                    Button("피벗 추가", systemImage: "tablecells.badge.ellipsis") {
                        pivotEditor = ExcelPivotEditorState(
                            pivotID: nil,
                            name: AppLocalization.format(
                                "피벗 테이블 %lld",
                                pivotTables.count + 1
                            ),
                            sourceReference: defaultChartSourceReference,
                            destinationReference:
                                defaultPivotDestinationReference,
                            rowFieldIndex: 0,
                            dataFieldIndex: 1,
                            aggregation: .sum,
                            refreshOnLoad: true,
                            supportsFieldEditing: true
                        )
                    }
                    if pivotTables.isEmpty {
                        Text("이 시트에 피벗 테이블이 없습니다.")
                            .foregroundStyle(VisionCraftUI.secondaryText)
                    } else {
                        ForEach(pivotTables) { pivot in
                            ExcelSheetPivotRow(
                                pivot: pivot,
                                onEdit: {
                                    pivotEditor = ExcelPivotEditorState(
                                        pivotID: pivot.id,
                                        name: pivot.name,
                                        sourceReference:
                                            pivot.sourceRange?.reference
                                                ?? defaultChartSourceReference,
                                        destinationReference:
                                            pivot.destinationRange?.start.reference
                                                ?? defaultPivotDestinationReference,
                                        rowFieldIndex:
                                            pivot.rowFieldIndex ?? 0,
                                        dataFieldIndex:
                                            pivot.dataFieldIndex ?? 1,
                                        aggregation: pivot.aggregation,
                                        refreshOnLoad: pivot.refreshOnLoad,
                                        supportsFieldEditing:
                                            pivot.supportsFieldEditing
                                    )
                                },
                                onRemove: { onRemovePivot(pivot.id) }
                            )
                        }
                    }
                } header: {
                    Text("피벗 테이블 \(pivotTables.count)개")
                } footer: {
                    Text(
                        "행 필드 하나와 합계·개수 값 필드 하나로 기본 피벗을 만들 수 있습니다. 고급 피벗은 직접 수정하지 않는 동안 원본 구조를 유지합니다."
                    )
                }
            }
            .navigationTitle("이미지·차트 등")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .onChange(of: newImageItem) { _, item in
                guard let item else { return }
                Task { await addImage(from: item) }
            }
            .alert(
                "이미지를 처리할 수 없습니다",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(item: $chartEditor) { configuration in
                ExcelChartEditorView(configuration: configuration) {
                    title,
                    kind,
                    sourceReference in
                    if let chartID = configuration.chartID {
                        return onUpdateChart(
                            chartID,
                            title,
                            kind,
                            sourceReference
                        )
                    }
                    return onAddChart(title, kind, sourceReference)
                }
            }
            .sheet(item: $shapeEditor) { configuration in
                ExcelShapeEditorView(configuration: configuration) {
                    name, text, kind in
                    if let shapeID = configuration.shapeID {
                        return onUpdateShape(shapeID, name, text, kind)
                    }
                    return onAddShape(name, text, kind)
                }
            }
            .sheet(item: $pivotEditor) { configuration in
                ExcelPivotEditorView(
                    configuration: configuration,
                    fieldNamesForReference: pivotFieldNames
                ) {
                    name,
                    sourceReference,
                    destinationReference,
                    rowFieldIndex,
                    dataFieldIndex,
                    aggregation,
                    refreshOnLoad in
                    if let pivotID = configuration.pivotID {
                        return onUpdatePivot(
                            pivotID,
                            name,
                            sourceReference,
                            destinationReference,
                            rowFieldIndex,
                            dataFieldIndex,
                            aggregation,
                            refreshOnLoad
                        )
                    }
                    return onAddPivot(
                        name,
                        sourceReference,
                        destinationReference,
                        rowFieldIndex,
                        dataFieldIndex,
                        aggregation,
                        refreshOnLoad
                    )
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @MainActor
    private func addImage(from item: PhotosPickerItem) async {
        defer { newImageItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  onAdd(data) else {
                throw ExcelSheetImagePickerError()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ExcelSheetImageRow: View {
    @State private var replacementItem: PhotosPickerItem?

    let image: ExcelSheetImage
    let onReplace: (String, Data) -> Bool
    let onRemove: (String) -> Void
    let onError: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let uiImage = UIImage(data: image.data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(VisionCraftUI.secondaryText)
                }
            }
            .frame(width: 64, height: 52)
            .background(VisionCraftUI.surfaceVariant, in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(image.name)
                    .font(.body.weight(.semibold))
                Text(
                    image.anchor.start.reference + "–"
                        + image.anchor.end.reference
                )
                .font(.caption.monospaced())
                .foregroundStyle(VisionCraftUI.secondaryText)
                if let alternativeText = image.alternativeText,
                   !alternativeText.isEmpty {
                    Text(alternativeText)
                        .font(.caption)
                        .foregroundStyle(VisionCraftUI.secondaryText)
                        .lineLimit(2)
                }
            }
            Spacer()
            Menu {
                PhotosPicker(
                    selection: $replacementItem,
                    matching: .images
                ) {
                    Label("이미지 교체", systemImage: "arrow.triangle.2.circlepath")
                }
                Button("이미지 삭제", systemImage: "trash", role: .destructive) {
                    onRemove(image.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .accessibilityLabel("\(image.name) 동작")
        }
        .accessibilityElement(children: .contain)
        .onChange(of: replacementItem) { _, item in
            guard let item else { return }
            Task { await replaceImage(from: item) }
        }
    }

    @MainActor
    private func replaceImage(from item: PhotosPickerItem) async {
        defer { replacementItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  onReplace(image.id, data) else {
                throw ExcelSheetImagePickerError()
            }
        } catch {
            onError(error.localizedDescription)
        }
    }
}

private struct ExcelSheetImagePickerError: LocalizedError {
    var errorDescription: String? {
        AppLocalization.string(
            "PNG 또는 JPEG 이미지인지, 파일 크기가 20MB 이하인지 확인해 주세요."
        )
    }
}

private struct ExcelAddRowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var fields: [ExcelWorkbookViewModel.RowField]
    let onAdd: ([ExcelWorkbookViewModel.RowField]) -> Void

    init(
        initialFields: [ExcelWorkbookViewModel.RowField],
        onAdd: @escaping ([ExcelWorkbookViewModel.RowField]) -> Void
    ) {
        _fields = State(initialValue: initialFields)
        self.onAdd = onAdd
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($fields) { $field in
                        TextField(field.title, text: $field.value)
                            .accessibilityLabel(field.title)
                    }
                } header: {
                    Text("열 값")
                } footer: {
                    Text("비워 둔 열은 수정하지 않습니다. 전화번호처럼 0으로 시작하는 값은 텍스트로 보존됩니다.")
                }
            }
            .navigationTitle("새 행 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("추가") {
                        onAdd(fields)
                        dismiss()
                    }
                    .disabled(
                        fields.allSatisfy {
                            $0.value.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                        }
                    )
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ExcelWorkbookExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [VisionCraftFileTypes.xlsx]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw ExcelWorkbookDocumentError.invalidWorkbook
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// Chat batches run in the engine on a copy of the document. Nothing reaches
// the live workbook or file until every operation and the export succeed.
extension ExcelWorkbookViewModel {
    func applyAIWorkbookPlan(_ plan: ExcelAIValidatedPlan) async throws -> ExcelAIWorkbookApplyResult {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        endEditorTextEditing()
        guard let original = workbook, let snapshot = makeAISnapshot(),
              snapshot.sheetPartPath == plan.sheetPartPath, snapshot.revision == plan.sourceRevision,
              !isLargeWorkbook, !plan.workbookOperations.isEmpty else { throw ExcelAIApplyError.staleProposal }
        let old = captureEditingState(original)
        let document = ExcelEditingDocument(base: editingBaseData ?? sourceData, workbook: original, registry: registry)
        let sheetIndex = selectedSheetIndex
        let selection = selectedAddress.map { ExcelCellRange(start: $0, end: selectionEnd ?? $0) }
        isSaving = true
        errorDescription = nil
        defer { isSaving = false }
        do {
            let task = Task.detached(priority: .userInitiated) {
                try ExcelWorkbookOperationExecution.applying(
                    plan, to: document, sheetIndex: sheetIndex, snapshot: snapshot, selection: selection,
                    checkpoint: { try Task.checkCancellation() })
            }
            let transaction = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            guard makeAISnapshot()?.revision == plan.sourceRevision else { throw ExcelAIApplyError.staleProposal }
            guard transaction.changed else { return .init(message: AppLocalization.string("변경할 내용이 없습니다."), references: nil) }
            let finalBook = transaction.document.workbook
            editingBaseData = transaction.document.base
            registry = transaction.document.registry
            workbook = finalBook
            selectedSheetIndex = transaction.sheetIndex
            if let range = transaction.selection {
                selectedAddress = range.start
                selectionEnd = range.cellCount > 1 ? range.end : nil
            } else if transaction.sheetIndex != sheetIndex {
                selectedAddress = selectedSheet.flatMap { initialAddress(in: $0) }
                selectionEnd = nil
            }
            selectedDrawingID = transaction.drawingID
            rangeClipboard = nil
            aiReferences = nil
            navigationRevealAddress = selectedDrawingID == nil ? selectedAddress : nil
            findText = ""
            let next = captureEditingState(finalBook)
            undoStack.append(MutationGroup(sheetIndex: selectedSheetIndex, cells: [], oldDocumentState: old, newDocumentState: next))
            redoStack.removeAll()
            if let sheet = selectedSheet {
                syncEditorText(using: sheet); updateValidationWarning(in: sheet); updateFormulaSupportSummary(in: sheet)
            }
            updateHistoryState()
            status = AppLocalization.string("채팅 요청을 적용했습니다. 실행 취소 한 번으로 되돌릴 수 있습니다.")
            return .init(message: transaction.messages.joined(separator: "\n"), references: transaction.references)
        } catch {
            status = error.localizedDescription
            throw error
        }
    }
}
