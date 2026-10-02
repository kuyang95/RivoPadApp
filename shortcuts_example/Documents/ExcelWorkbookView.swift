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

    private nonisolated struct CellMutation {
        let address: ExcelCellAddress
        let oldCell: ExcelCell?
        let newCell: ExcelCell?
        let oldEdit: ExcelCellEdit?
        let newEdit: ExcelCellEdit?
    }

    private nonisolated struct MutationGroup {
        let id = UUID()
        let sheetIndex: Int
        let cells: [CellMutation]
        let oldStyles: [ExcelCellStyle]?
        let newStyles: [ExcelCellStyle]?
        let oldStyleEdits: [Int: ExcelStyleEdit]?
        let newStyleEdits: [Int: ExcelStyleEdit]?
        let oldDifferentialStyles: [ExcelDifferentialStyle]?
        let newDifferentialStyles: [ExcelDifferentialStyle]?
        let oldDifferentialStyleEdits:
            [Int: ExcelDifferentialStyleEdit]?
        let newDifferentialStyleEdits:
            [Int: ExcelDifferentialStyleEdit]?
        let oldDataValidations: [ExcelDataValidationRule]?
        let newDataValidations: [ExcelDataValidationRule]?
        let oldConditionalFormatting:
            [ExcelConditionalFormattingBlock]?
        let newConditionalFormatting:
            [ExcelConditionalFormattingBlock]?
        let oldAnnotations: ExcelWorksheetAnnotations?
        let newAnnotations: ExcelWorksheetAnnotations?
        let oldDrawingObjects: ExcelWorksheetDrawingObjects?
        let newDrawingObjects: ExcelWorksheetDrawingObjects?
        let oldPivotTables: [ExcelPivotTable]?
        let newPivotTables: [ExcelPivotTable]?
        let oldDocumentState: EditingState?
        let newDocumentState: EditingState?
        let oldTables: [ExcelTable]?
        let newTables: [ExcelTable]?

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
            self.sheetIndex = sheetIndex
            self.cells = cells
            self.oldDocumentState = oldDocumentState
            self.newDocumentState = newDocumentState
            self.oldStyles = oldStyles
            self.newStyles = newStyles
            self.oldStyleEdits = oldStyleEdits
            self.newStyleEdits = newStyleEdits
            self.oldDifferentialStyles = oldDifferentialStyles
            self.newDifferentialStyles = newDifferentialStyles
            self.oldDifferentialStyleEdits = oldDifferentialStyleEdits
            self.newDifferentialStyleEdits = newDifferentialStyleEdits
            self.oldDataValidations = oldDataValidations
            self.newDataValidations = newDataValidations
            self.oldConditionalFormatting = oldConditionalFormatting
            self.newConditionalFormatting = newConditionalFormatting
            self.oldAnnotations = oldAnnotations
            self.newAnnotations = newAnnotations
            self.oldDrawingObjects = oldDrawingObjects
            self.newDrawingObjects = newDrawingObjects
            self.oldPivotTables = oldPivotTables
            self.newPivotTables = newPivotTables
            self.oldTables = oldTables
            self.newTables = newTables
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
    private var edits: [String: [ExcelCellAddress: ExcelCellEdit]] = [:]
    private var styleEdits: [Int: ExcelStyleEdit] = [:]
    private var originalDataValidations:
        [String: [ExcelDataValidationRule]] = [:]
    private var validationEdits:
        [String: [ExcelDataValidationRule]] = [:]
    private var originalConditionalFormatting:
        [String: [ExcelConditionalFormattingBlock]] = [:]
    private var conditionalFormattingEdits:
        [String: [ExcelConditionalFormattingBlock]] = [:]
    private var differentialStyleEdits:
        [Int: ExcelDifferentialStyleEdit] = [:]
    private var originalAnnotations:
        [String: ExcelWorksheetAnnotations] = [:]
    private var annotationEdits:
        [String: ExcelWorksheetAnnotations] = [:]
    private var originalDrawingObjects:
        [String: ExcelWorksheetDrawingObjects] = [:]
    private var drawingObjectEdits:
        [String: ExcelWorksheetDrawingObjects] = [:]
    private var originalPivotTables:
        [String: [ExcelPivotTable]] = [:]
    private var pivotTableEdits:
        [String: [ExcelPivotTable]] = [:]
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
        let regions = ExcelAccessibilityAnalyzer.regions(in: sheet)
        if let selectedAddress,
           let region = regions.first(where: {
               $0.contains(selectedAddress)
           }) {
            return region.range.reference
        }
        return regions.first?.range.reference
            ?? "A1:\(ExcelCellAddress.columnName(max(sheet.maximumColumn, 2)))"
                + String(max(sheet.maximumRow, 2))
    }

    var selectedSheetPivotTableCount: Int {
        selectedSheet?.pivotTables.count ?? 0
    }

    var selectedSheetPivotTables: [ExcelPivotTable] {
        selectedSheet?.pivotTables ?? []
    }

    var defaultPivotDestinationReference: String {
        guard let sheet = selectedSheet else { return "G1" }
        let source = ExcelCellRange(defaultChartSourceReference)
        let column = min(
            max((source?.end.column ?? sheet.maximumColumn) + 2, 1),
            ExcelWorkbookDocument.maximumExcelColumns
        )
        return ExcelCellAddress(row: 1, column: column).reference
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
            originalDataValidations = Dictionary(
                uniqueKeysWithValues: result.2.sheets.map {
                    ($0.partPath, $0.dataValidations)
                }
            )
            originalConditionalFormatting = Dictionary(
                uniqueKeysWithValues: result.2.sheets.map {
                    ($0.partPath, $0.conditionalFormatting)
                }
            )
            originalAnnotations = Dictionary(
                uniqueKeysWithValues: result.2.sheets.map {
                    ($0.partPath, $0.annotations)
                }
            )
            originalDrawingObjects = Dictionary(
                uniqueKeysWithValues: result.2.sheets.map {
                    ($0.partPath, $0.drawingObjects)
                }
            )
            originalPivotTables = Dictionary(
                uniqueKeysWithValues: result.2.sheets.map {
                    ($0.partPath, $0.pivotTables)
                }
            )
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
            if let first = rows.first {
                status = AppLocalization.format(
                    "%lld개 행에서 찾았습니다. 첫 결과는 %lld행입니다.",
                    rows.count,
                    first
                )
                await jumpToLargeRow(first)
            } else {
                status = AppLocalization.string("검색 결과가 없습니다.")
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
        let values = normalizedDropdownValues(rawValues)
        guard values.count >= 2 else {
            status = AppLocalization.string(
                "드롭다운 값은 서로 다른 항목을 2개 이상 입력하세요."
            )
            return false
        }
        guard values.allSatisfy({
            !$0.contains(",") && !$0.contains("\"")
        }) else {
            status = AppLocalization.string(
                "드롭다운 항목에는 쉼표와 큰따옴표를 사용할 수 없습니다."
            )
            return false
        }
        guard values.joined(separator: ",").utf16.count <= 253 else {
            status = AppLocalization.string(
                "드롭다운 항목 전체가 너무 깁니다. 항목 수나 글자 수를 줄여 주세요."
            )
            return false
        }

        let sheet = workbook.sheets[selectedSheetIndex]
        let canonical = sheet.canonicalAddress(for: selectedAddress)
        let addresses = validationTargetAddresses(
            selection: canonical,
            toCurrentColumn: toCurrentColumn,
            in: sheet
        )
        guard !addresses.isEmpty else {
            return false
        }
        let ranges = ExcelCellRange.verticalRanges(for: addresses)
        let oldRules = sheet.dataValidations
        var newRules = oldRules.compactMap { $0.removing(ranges) }
        newRules.append(
            .inlineList(
                ranges: ranges,
                values: values,
                allowsBlank: allowsBlank
            )
        )
        apply(
            MutationGroup(
                sheetIndex: selectedSheetIndex,
                cells: [],
                oldDataValidations: oldRules,
                newDataValidations: newRules
            ),
            forward: true,
            registeringUndo: true,
            workbook: &workbook
        )
        self.workbook = workbook
        updateValidationWarning(in: workbook.sheets[selectedSheetIndex])
        status = toCurrentColumn
            ? AppLocalization.format(
                "현재 열의 %lld개 데이터 셀에 드롭다운을 설정했습니다.",
                addresses.count
            )
            : AppLocalization.format(
                "%@ 셀에 드롭다운을 설정했습니다.",
                canonical.reference
            )
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
        let addresses = validationTargetAddresses(
            selection: canonical,
            toCurrentColumn: toCurrentColumn,
            in: sheet
        )
        let ranges = ExcelCellRange.verticalRanges(for: addresses)
        let oldRules = sheet.dataValidations
        let newRules = oldRules.compactMap { rule in
            rule.type == "list" ? rule.removing(ranges) : rule
        }
        guard newRules != oldRules else {
            status = AppLocalization.string(
                "선택한 범위에 제거할 드롭다운이 없습니다."
            )
            return
        }
        apply(
            MutationGroup(
                sheetIndex: selectedSheetIndex,
                cells: [],
                oldDataValidations: oldRules,
                newDataValidations: newRules
            ),
            forward: true,
            registeringUndo: true,
            workbook: &workbook
        )
        self.workbook = workbook
        updateValidationWarning(in: workbook.sheets[selectedSheetIndex])
        status = toCurrentColumn
            ? AppLocalization.string("현재 열의 드롭다운을 제거했습니다.")
            : AppLocalization.format(
                "%@ 셀의 드롭다운을 제거했습니다.",
                canonical.reference
            )
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
        let comparisonValue = rawComparisonValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !comparisonValue.isEmpty else {
            status = AppLocalization.string("비교할 값을 입력하세요.")
            return false
        }
        guard !kind.requiresNumber || Double(comparisonValue) != nil else {
            status = AppLocalization.string(
                "보다 큼·작음 규칙에는 숫자를 입력하세요."
            )
            return false
        }
        guard var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex),
              let selectedAddress else {
            return false
        }
        let sheet = workbook.sheets[selectedSheetIndex]
        let canonical = sheet.canonicalAddress(for: selectedAddress)
        let addresses = validationTargetAddresses(
            selection: canonical,
            toCurrentColumn: toCurrentColumn,
            in: sheet
        )
        guard !addresses.isEmpty else {
            return false
        }
        let ranges = ExcelCellRange.verticalRanges(for: addresses)
        let oldBlocks = sheet.conditionalFormatting
        let oldDifferentialStyles = workbook.differentialStyles
        let oldDifferentialStyleEdits = differentialStyleEdits
        // Rules accumulate like in Excel; only a rule with the same
        // condition and value is replaced (e.g. to change its color).
        var newBlocks = oldBlocks.compactMap { block in
            block.isSameRule(kind: kind, comparisonValue: comparisonValue)
                ? block.removing(ranges)
                : block
        }
        let styleIndex = differentialStyleIndex(
            for: highlight.style,
            workbook: &workbook
        )
        let priority = oldBlocks.flatMap(\.rules).map(\.priority).max()
            .map { $0 + 1 } ?? 1
        newBlocks.append(
            ExcelConditionalFormattingBlock(
                ranges: ranges,
                rules: [
                    ExcelConditionalFormattingRule(
                        kind: kind,
                        comparisonValue: comparisonValue,
                        differentialStyleIndex: styleIndex,
                        priority: priority
                    ),
                ]
            )
        )
        apply(
            MutationGroup(
                sheetIndex: selectedSheetIndex,
                cells: [],
                oldDifferentialStyles: oldDifferentialStyles,
                newDifferentialStyles: workbook.differentialStyles,
                oldDifferentialStyleEdits: oldDifferentialStyleEdits,
                newDifferentialStyleEdits: differentialStyleEdits,
                oldConditionalFormatting: oldBlocks,
                newConditionalFormatting: newBlocks
            ),
            forward: true,
            registeringUndo: true,
            workbook: &workbook
        )
        self.workbook = workbook
        status = toCurrentColumn
            ? AppLocalization.format(
                "현재 열의 %lld개 데이터 셀에 조건부 서식을 설정했습니다.",
                addresses.count
            )
            : AppLocalization.format(
                "%@ 셀에 조건부 서식을 설정했습니다.",
                canonical.reference
            )
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
        let addresses = validationTargetAddresses(
            selection: canonical,
            toCurrentColumn: toCurrentColumn,
            in: sheet
        )
        let ranges = ExcelCellRange.verticalRanges(for: addresses)
        let oldBlocks = sheet.conditionalFormatting
        let newBlocks = oldBlocks.compactMap { $0.removing(ranges) }
        guard newBlocks != oldBlocks else {
            status = AppLocalization.string(
                "선택한 범위에 제거할 기본 조건부 서식이 없습니다."
            )
            return
        }
        apply(
            MutationGroup(
                sheetIndex: selectedSheetIndex,
                cells: [],
                oldConditionalFormatting: oldBlocks,
                newConditionalFormatting: newBlocks
            ),
            forward: true,
            registeringUndo: true,
            workbook: &workbook
        )
        self.workbook = workbook
        status = toCurrentColumn
            ? AppLocalization.string("현재 열의 기본 조건부 서식을 제거했습니다.")
            : AppLocalization.format(
                "%@ 셀의 기본 조건부 서식을 제거했습니다.",
                canonical.reference
            )
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
        let target = rawTarget.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !target.isEmpty,
           !isSupportedHyperlinkTarget(target) {
            status = AppLocalization.string(
                "웹 주소는 http:// 또는 https://로 시작해야 합니다. 이메일·전화 링크와 #시트!셀 내부 링크도 사용할 수 있습니다."
            )
            return false
        }
        let tooltip = rawTooltip.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let noteText = rawNoteText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let author = rawAuthor.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty ? "VisionCraft" : rawAuthor.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let sheet = workbook.sheets[selectedSheetIndex]
        let address = sheet.canonicalAddress(for: selectedAddress)
        let targetRange = ExcelCellRange(start: address, end: address)
        let oldAnnotations = sheet.annotations
        var newAnnotations = oldAnnotations
        let existingHyperlink = oldAnnotations.hyperlink(at: address)
        newAnnotations.hyperlinks = oldAnnotations.hyperlinks.flatMap { link in
            guard link.contains(address) else {
                return [link]
            }
            return link.range.subtracting(targetRange).map { remaining in
                var copy = link
                copy.range = remaining
                return copy
            }
        }
        if !target.isEmpty {
            let isExternal = !target.hasPrefix("#")
            newAnnotations.hyperlinks.append(
                ExcelCellHyperlink(
                    range: targetRange,
                    target: target,
                    tooltip: tooltip.isEmpty ? nil : tooltip,
                    display: existingHyperlink?.display,
                    relationshipID: isExternal
                        ? existingHyperlink?.relationshipID
                            ?? "rIdVCHyperlink" + UUID().uuidString
                                .replacingOccurrences(of: "-", with: "")
                        : nil,
                    isExternal: isExternal
                )
            )
        }

        newAnnotations.notes.removeAll { $0.address == address }
        if !noteText.isEmpty {
            if newAnnotations.commentsPartPath == nil {
                let token = UUID().uuidString.replacingOccurrences(
                    of: "-",
                    with: ""
                )
                newAnnotations.commentsPartPath = "xl/commentsVC"
                    + token + ".xml"
                newAnnotations.vmlDrawingPartPath =
                    "xl/drawings/vmlDrawingVC" + token + ".vml"
                newAnnotations.commentsRelationshipID =
                    "rIdVCComments" + token
                newAnnotations.vmlDrawingRelationshipID =
                    "rIdVCVML" + token
            }
            if !newAnnotations.authors.contains(author) {
                newAnnotations.authors.append(author)
            }
            newAnnotations.notes.append(
                ExcelCellNote(
                    address: address,
                    author: author,
                    text: noteText
                )
            )
        }
        guard newAnnotations != oldAnnotations else {
            status = AppLocalization.string("바뀐 링크나 메모가 없습니다.")
            return false
        }
        apply(
            MutationGroup(
                sheetIndex: selectedSheetIndex,
                cells: [],
                oldAnnotations: oldAnnotations,
                newAnnotations: newAnnotations
            ),
            forward: true,
            registeringUndo: true,
            workbook: &workbook
        )
        self.workbook = workbook
        status = AppLocalization.format(
            "%@ 셀의 링크·메모를 수정했습니다.",
            address.reference
        )
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
            status = AppLocalization.string(
                "이미지를 추가하지 못했습니다. PNG 또는 JPEG 사진을 선택해 주세요."
            )
            return false
        }
        let sheet = workbook.sheets[selectedSheetIndex]
        let oldObjects = sheet.drawingObjects
        var newObjects = oldObjects
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        if newObjects.drawingPartPath == nil {
            newObjects.drawingPartPath = "xl/drawings/drawingVC"
                + token + ".xml"
            newObjects.drawingRelationshipID = "rIdVCDrawing" + token
        }
        guard let drawingPath = newObjects.drawingPartPath else {
            return false
        }
        let start = selectedAddress ?? ExcelCellAddress(row: 1, column: 1)
        let end = ExcelCellAddress(
            row: min(start.row + 5, 1_048_576),
            column: min(start.column + 2, 16_384)
        )
        let relationshipID = "rIdVCImage" + token
        let imageNumber = newObjects.images.count + 1
        newObjects.images.append(
            ExcelSheetImage(
                id: drawingPath + "#" + relationshipID,
                name: AppLocalization.format("이미지 %lld", imageNumber),
                alternativeText: AppLocalization.string(
                    "스프레드시트에 추가한 이미지"
                ),
                anchor: ExcelDrawingAnchor(start: start, end: end),
                relationshipID: relationshipID,
                mediaPartPath: "xl/media/imageVC" + token
                    + "." + prepared.extensionName,
                contentType: prepared.contentType,
                data: prepared.data,
                originalAnchorXML: nil,
                displayOrder: (oldObjects.images.map(\.displayOrder) + oldObjects.charts.map(\.displayOrder)).max().map { $0 + 1 } ?? 0
            )
        )
        apply(
            MutationGroup(
                sheetIndex: selectedSheetIndex,
                cells: [],
                oldDrawingObjects: oldObjects,
                newDrawingObjects: newObjects
            ),
            forward: true,
            registeringUndo: true,
            workbook: &workbook
        )
        self.workbook = workbook
        status = AppLocalization.format(
            "%@ 셀을 시작 위치로 이미지를 추가했습니다.",
            start.reference
        )
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
        let sheet = workbook.sheets[selectedSheetIndex]
        let oldObjects = sheet.drawingObjects
        guard let index = oldObjects.images.firstIndex(where: {
            $0.id == id
        }) else {
            return false
        }
        let existingContentType = oldObjects.images[index].contentType
        let preferredContentType = ["image/png", "image/jpeg"].contains(
            existingContentType
        ) ? existingContentType : nil
        guard let prepared = preparedImage(
            data,
            preferredContentType: preferredContentType
        ) else {
            status = AppLocalization.string(
                "이미지를 교체하지 못했습니다. PNG 또는 JPEG 사진을 선택해 주세요."
            )
            return false
        }
        var newObjects = oldObjects
        newObjects.images[index].data = prepared.data
        // A source image may be shared by other pictures or worksheets.
        if prepared.data != oldObjects.images[index].data {
            newObjects.images[index].mediaPartPath = "xl/media/imageVC" + UUID().uuidString.replacingOccurrences(of: "-", with: "") + "." + prepared.extensionName
        }
        newObjects.images[index].contentType = prepared.contentType
        guard newObjects != oldObjects else {
            status = AppLocalization.string("같은 이미지입니다.")
            return false
        }
        apply(
            MutationGroup(
                sheetIndex: selectedSheetIndex,
                cells: [],
                oldDrawingObjects: oldObjects,
                newDrawingObjects: newObjects
            ),
            forward: true,
            registeringUndo: true,
            workbook: &workbook
        )
        self.workbook = workbook
        status = AppLocalization.format(
            "%@을(를) 교체했습니다.",
            newObjects.images[index].name
        )
        return true
    }

    func removeSheetImage(id: String) {
        guard allowEditing() else { return }
        endEditorTextEditing()
        guard !isLargeWorkbook,
              var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return
        }
        let oldObjects = workbook.sheets[selectedSheetIndex].drawingObjects
        let partPath = workbook.sheets[selectedSheetIndex].partPath
        guard let image = oldObjects.images.first(where: { $0.id == id }) else {
            return
        }
        var newObjects = oldObjects
        newObjects.images.removeAll { $0.id == id }
        clearNewDrawingIdentityIfEmpty(
            &newObjects,
            original: originalDrawingObjects[partPath] ?? .empty
        )
        apply(
            MutationGroup(
                sheetIndex: selectedSheetIndex,
                cells: [],
                oldDrawingObjects: oldObjects,
                newDrawingObjects: newObjects
            ),
            forward: true,
            registeringUndo: true,
            workbook: &workbook
        )
        self.workbook = workbook
        status = AppLocalization.format("%@을(를) 삭제했습니다.", image.name)
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
              kind.isEditable,
              var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return false
        }
        let sheet = workbook.sheets[selectedSheetIndex]
        let oldObjects = sheet.drawingObjects
        var newObjects = oldObjects
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        if newObjects.drawingPartPath == nil {
            newObjects.drawingPartPath = "xl/drawings/drawingVC"
                + token + ".xml"
            newObjects.drawingRelationshipID = "rIdVCDrawing" + token
        }
        guard let drawingPath = newObjects.drawingPartPath else {
            return false
        }
        let shapeNumber = newObjects.shapes.count + 1
        let name = rawName.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
            ? AppLocalization.format("도형 %lld", shapeNumber)
            : rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = selectedAddress ?? ExcelCellAddress(row: 1, column: 1)
        let end = ExcelCellAddress(
            row: min(start.row + 4, 1_048_576),
            column: min(start.column + 3, 16_384)
        )
        newObjects.shapes.append(
            ExcelSheetShape(
                id: drawingPath + "#shapeVC" + token,
                nonVisualID: 0,
                name: name,
                text: rawText,
                kind: kind,
                fillARGB: kind == .line ? nil : "D9EAF7",
                lineARGB: "4472C4",
                anchor: ExcelDrawingAnchor(start: start, end: end),
                originalAnchorXML: nil
            )
        )
        applyDrawingObjectsChange(
            old: oldObjects,
            new: newObjects,
            workbook: &workbook
        )
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
              kind.isEditable,
              var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return false
        }
        let oldObjects = workbook.sheets[selectedSheetIndex].drawingObjects
        guard let index = oldObjects.shapes.firstIndex(where: {
            $0.id == id
        }) else { return false }
        var newObjects = oldObjects
        let name = rawName.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty ? oldObjects.shapes[index].name : rawName
        newObjects.shapes[index].name = name
        newObjects.shapes[index].text = text
        newObjects.shapes[index].kind = kind
        guard newObjects != oldObjects else {
            status = AppLocalization.string("바뀐 도형 설정이 없습니다.")
            return false
        }
        applyDrawingObjectsChange(
            old: oldObjects,
            new: newObjects,
            workbook: &workbook
        )
        self.workbook = workbook
        status = AppLocalization.format("%@을(를) 수정했습니다.", name)
        return true
    }

    func removeSheetShape(id: String) {
        guard allowEditing() else { return }
        endEditorTextEditing()
        guard !isLargeWorkbook,
              var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return
        }
        let oldObjects = workbook.sheets[selectedSheetIndex].drawingObjects
        let partPath = workbook.sheets[selectedSheetIndex].partPath
        guard let shape = oldObjects.shapes.first(where: {
            $0.id == id
        }) else { return }
        var newObjects = oldObjects
        newObjects.shapes.removeAll { $0.id == id }
        clearNewDrawingIdentityIfEmpty(
            &newObjects,
            original: originalDrawingObjects[partPath] ?? .empty
        )
        applyDrawingObjectsChange(
            old: oldObjects,
            new: newObjects,
            workbook: &workbook
        )
        self.workbook = workbook
        status = AppLocalization.format("%@을(를) 삭제했습니다.", shape.name)
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
              kind.isEditable,
              var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return false
        }
        let sheet = workbook.sheets[selectedSheetIndex]
        guard let sourceRange = validatedChartRange(
            sourceReference,
            in: sheet
        ) else {
            status = AppLocalization.string(
                "차트 범위는 머리글과 데이터가 포함된 두 행 이상의 셀 범위로 입력해 주세요."
            )
            return false
        }
        let oldObjects = sheet.drawingObjects
        var newObjects = oldObjects
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        if newObjects.drawingPartPath == nil {
            newObjects.drawingPartPath = "xl/drawings/drawingVC"
                + token + ".xml"
            newObjects.drawingRelationshipID = "rIdVCDrawing" + token
        }
        guard let drawingPath = newObjects.drawingPartPath else {
            return false
        }
        let relationshipID = "rIdVCChart" + token
        let chartNumber = newObjects.charts.count + 1
        let title = rawTitle.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
            ? AppLocalization.format("차트 %lld", chartNumber)
            : rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let startColumn = sourceRange.end.column <= 16_377
            ? sourceRange.end.column + 1
            : sourceRange.start.column
        let start = ExcelCellAddress(
            row: min(
                sourceRange.start.row + newObjects.charts.count * 13,
                1_048_563
            ),
            column: startColumn
        )
        let end = ExcelCellAddress(
            row: min(start.row + 12, 1_048_576),
            column: min(start.column + 6, 16_384)
        )
        newObjects.charts.append(
            ExcelSheetChart(
                id: drawingPath + "#" + relationshipID,
                name: title,
                title: title,
                kind: kind,
                sourceRange: sourceRange,
                sheetName: sheet.name,
                anchor: ExcelDrawingAnchor(start: start, end: end),
                relationshipID: relationshipID,
                chartPartPath: "xl/charts/chartVC" + token + ".xml",
                originalAnchorXML: nil,
                originalChartXML: nil,
                displayOrder: (oldObjects.images.map(\.displayOrder) + oldObjects.charts.map(\.displayOrder)).max().map { $0 + 1 } ?? 0
            )
        )
        newObjects.chartCount = newObjects.charts.count
        applyDrawingObjectsChange(
            old: oldObjects,
            new: newObjects,
            workbook: &workbook
        )
        self.workbook = workbook
        status = AppLocalization.format("%@을(를) 추가했습니다.", title)
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
              kind.isEditable,
              var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return false
        }
        let sheet = workbook.sheets[selectedSheetIndex]
        guard let sourceRange = validatedChartRange(
            sourceReference,
            in: sheet
        ) else {
            status = AppLocalization.string(
                "차트 범위는 머리글과 데이터가 포함된 두 행 이상의 셀 범위로 입력해 주세요."
            )
            return false
        }
        let oldObjects = sheet.drawingObjects
        guard let index = oldObjects.charts.firstIndex(where: {
            $0.id == id
        }) else {
            return false
        }
        var newObjects = oldObjects
        let title = rawTitle.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
            ? oldObjects.charts[index].name
            : rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        newObjects.charts[index].title = title
        newObjects.charts[index].name = title
        newObjects.charts[index].kind = kind
        newObjects.charts[index].sourceRange = sourceRange
        newObjects.charts[index].sheetName = sheet.name
        guard newObjects != oldObjects else {
            status = AppLocalization.string("바뀐 차트 설정이 없습니다.")
            return false
        }
        newObjects.charts[index].originalChartXML = nil
        applyDrawingObjectsChange(
            old: oldObjects,
            new: newObjects,
            workbook: &workbook
        )
        self.workbook = workbook
        status = AppLocalization.format("%@을(를) 수정했습니다.", title)
        return true
    }

    func removeSheetChart(id: String) {
        guard allowEditing() else { return }
        endEditorTextEditing()
        guard !isLargeWorkbook,
              var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return
        }
        let oldObjects = workbook.sheets[selectedSheetIndex].drawingObjects
        let partPath = workbook.sheets[selectedSheetIndex].partPath
        guard let chart = oldObjects.charts.first(where: {
            $0.id == id
        }) else {
            return
        }
        var newObjects = oldObjects
        newObjects.charts.removeAll { $0.id == id }
        newObjects.chartCount = newObjects.charts.count
        clearNewDrawingIdentityIfEmpty(
            &newObjects,
            original: originalDrawingObjects[partPath] ?? .empty
        )
        applyDrawingObjectsChange(
            old: oldObjects,
            new: newObjects,
            workbook: &workbook
        )
        self.workbook = workbook
        status = AppLocalization.format("%@을(를) 삭제했습니다.", chart.title)
    }

    func pivotFieldNames(sourceReference: String) -> [String] {
        guard let sheet = selectedSheet,
              let range = validatedPivotSourceRange(
                sourceReference,
                in: sheet
              ) else {
            return []
        }
        return pivotFieldNames(in: range, sheet: sheet)
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
        let sheet = workbook.sheets[selectedSheetIndex]
        guard let sourceRange = validatedPivotSourceRange(
            sourceReference,
            in: sheet
        ),
        let destination = validatedPivotDestination(
            destinationReference
        ) else {
            status = AppLocalization.string(
                "피벗 원본 범위와 결과 시작 셀을 확인해 주세요."
            )
            return false
        }
        let fieldNames = pivotFieldNames(in: sourceRange, sheet: sheet)
        guard fieldNames.indices.contains(rowFieldIndex),
              fieldNames.indices.contains(dataFieldIndex),
              rowFieldIndex != dataFieldIndex else {
            status = AppLocalization.string(
                "행 필드와 값 필드는 서로 다른 열로 선택해 주세요."
            )
            return false
        }
        let name = uniquePivotName(rawName, in: workbook)
        guard let summary = pivotSummary(
            title: name,
            sourceRange: sourceRange,
            destination: destination,
            rowFieldIndex: rowFieldIndex,
            dataFieldIndex: dataFieldIndex,
            aggregation: aggregation,
            fieldNames: fieldNames,
            sheet: sheet
        ) else {
            return false
        }
        guard !rangesOverlap(sourceRange, summary.range),
              pivotDestinationIsAvailable(
                summary.range,
                replacing: nil,
                in: sheet
              ) else {
            status = AppLocalization.string(
                "피벗 결과 범위가 원본 데이터나 기존 셀과 겹칩니다. 다른 시작 셀을 선택해 주세요."
            )
            return false
        }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let cacheID = (workbook.sheets
            .flatMap(\.pivotTables)
            .map(\.cacheID)
            .max() ?? -1) + 1
        let partPath = "xl/pivotTables/pivotTableVC" + token + ".xml"
        let pivot = ExcelPivotTable(
            id: partPath,
            name: name,
            relationshipID: "rIdVCPivot" + token,
            partPath: partPath,
            cacheID: cacheID,
            cacheDefinitionPath:
                "xl/pivotCache/pivotCacheDefinitionVC" + token + ".xml",
            cacheRelationshipID: "rIdVCCache" + token,
            workbookCacheRelationshipID: "rIdVCWorkbookCache" + token,
            sourceSheetName: sheet.name,
            sourceRange: sourceRange,
            destinationRange: summary.range,
            fieldNames: fieldNames,
            rowFieldIndex: rowFieldIndex,
            dataFieldIndex: dataFieldIndex,
            aggregation: aggregation,
            refreshOnLoad: refreshOnLoad,
            originalPivotXML: nil,
            originalCacheXML: nil
        )
        let oldPivots = sheet.pivotTables
        let newPivots = oldPivots + [pivot]
        let mutations = pivotSummaryMutations(
            summary.values,
            clearing: nil,
            in: sheet
        )
        apply(
            MutationGroup(
                sheetIndex: selectedSheetIndex,
                cells: mutations,
                oldPivotTables: oldPivots,
                newPivotTables: newPivots
            ),
            forward: true,
            registeringUndo: true,
            workbook: &workbook
        )
        expandSheetBounds(for: mutations, workbook: &workbook)
        self.workbook = workbook
        status = AppLocalization.format("%@을(를) 추가했습니다.", name)
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
        let sheet = workbook.sheets[selectedSheetIndex]
        guard let index = sheet.pivotTables.firstIndex(where: {
            $0.id == id
        }) else {
            return false
        }
        let oldPivot = sheet.pivotTables[index]
        var newPivot = oldPivot
        let trimmedName = rawName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedName.isEmpty,
              !workbook.sheets.flatMap(\.pivotTables).contains(where: {
                $0.id != id
                    && $0.name.caseInsensitiveCompare(trimmedName)
                        == .orderedSame
              }) else {
            status = AppLocalization.string(
                "피벗 이름은 비어 있지 않고 다른 피벗과 달라야 합니다."
            )
            return false
        }
        newPivot.name = String(trimmedName.prefix(255))
        newPivot.refreshOnLoad = refreshOnLoad

        var mutations = [CellMutation]()
        if oldPivot.supportsFieldEditing {
            guard let sourceRange = validatedPivotSourceRange(
                sourceReference,
                in: sheet
            ),
            let destination = validatedPivotDestination(
                destinationReference
            ) else {
                status = AppLocalization.string(
                    "피벗 원본 범위와 결과 시작 셀을 확인해 주세요."
                )
                return false
            }
            let fieldNames = pivotFieldNames(in: sourceRange, sheet: sheet)
            guard fieldNames.indices.contains(rowFieldIndex),
                  fieldNames.indices.contains(dataFieldIndex),
                  rowFieldIndex != dataFieldIndex,
                  let summary = pivotSummary(
                    title: newPivot.name,
                    sourceRange: sourceRange,
                    destination: destination,
                    rowFieldIndex: rowFieldIndex,
                    dataFieldIndex: dataFieldIndex,
                    aggregation: aggregation,
                    fieldNames: fieldNames,
                    sheet: sheet
                  ),
                  !rangesOverlap(sourceRange, summary.range),
                  pivotDestinationIsAvailable(
                    summary.range,
                    replacing: oldPivot.destinationRange,
                    in: sheet
                  ) else {
                status = AppLocalization.string(
                    "필드 설정 또는 결과 범위를 확인해 주세요."
                )
                return false
            }
            newPivot.sourceSheetName = sheet.name
            newPivot.sourceRange = sourceRange
            newPivot.destinationRange = summary.range
            newPivot.fieldNames = fieldNames
            newPivot.rowFieldIndex = rowFieldIndex
            newPivot.dataFieldIndex = dataFieldIndex
            newPivot.aggregation = aggregation
            mutations = pivotSummaryMutations(
                summary.values,
                clearing: oldPivot.destinationRange,
                in: sheet
            )
        }
        var newPivots = sheet.pivotTables
        newPivots[index] = newPivot
        guard newPivot != oldPivot || !mutations.isEmpty else {
            status = AppLocalization.string("바뀐 피벗 설정이 없습니다.")
            return false
        }
        apply(
            MutationGroup(
                sheetIndex: selectedSheetIndex,
                cells: mutations,
                oldPivotTables: sheet.pivotTables,
                newPivotTables: newPivots
            ),
            forward: true,
            registeringUndo: true,
            workbook: &workbook
        )
        expandSheetBounds(for: mutations, workbook: &workbook)
        self.workbook = workbook
        status = AppLocalization.format("%@을(를) 수정했습니다.", newPivot.name)
        return true
    }

    func removePivotTable(id: String) {
        guard allowEditing() else { return }
        endEditorTextEditing()
        guard !isLargeWorkbook,
              var workbook,
              workbook.sheets.indices.contains(selectedSheetIndex) else {
            return
        }
        let sheet = workbook.sheets[selectedSheetIndex]
        guard let pivot = sheet.pivotTables.first(where: {
            $0.id == id
        }) else {
            return
        }
        var newPivots = sheet.pivotTables
        newPivots.removeAll { $0.id == id }
        let mutations = pivotSummaryMutations(
            [:],
            clearing: pivot.destinationRange,
            in: sheet
        )
        apply(
            MutationGroup(
                sheetIndex: selectedSheetIndex,
                cells: mutations,
                oldPivotTables: sheet.pivotTables,
                newPivotTables: newPivots
            ),
            forward: true,
            registeringUndo: true,
            workbook: &workbook
        )
        self.workbook = workbook
        status = AppLocalization.format("%@을(를) 삭제했습니다.", pivot.name)
    }

    private func validatedPivotSourceRange(
        _ reference: String,
        in sheet: ExcelWorksheet
    ) -> ExcelCellRange? {
        guard let range = ExcelCellRange(
            reference.trimmingCharacters(in: .whitespacesAndNewlines)
        ),
        range.end.row > range.start.row,
        range.end.row <= max(sheet.maximumRow, 1),
        range.end.column <= max(sheet.maximumColumn, 1),
        range.end.column - range.start.column < 12,
        range.end.row - range.start.row <= 50_000 else {
            return nil
        }
        return range
    }

    private func validatedPivotDestination(
        _ reference: String
    ) -> ExcelCellAddress? {
        let first = reference.split(separator: ":", maxSplits: 1)
            .first.map(String.init) ?? reference
        return ExcelCellAddress(
            first.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func pivotFieldNames(
        in range: ExcelCellRange,
        sheet: ExcelWorksheet
    ) -> [String] {
        (range.start.column ... range.end.column).map { column in
            let value = sheet.cells[
                ExcelCellAddress(row: range.start.row, column: column)
            ]?.displayValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""
            return value.isEmpty
                ? ExcelCellAddress.columnName(column)
                : value
        }
    }

    private func pivotSummary(
        title: String,
        sourceRange: ExcelCellRange,
        destination: ExcelCellAddress,
        rowFieldIndex: Int,
        dataFieldIndex: Int,
        aggregation: ExcelPivotAggregation,
        fieldNames: [String],
        sheet: ExcelWorksheet
    ) -> (range: ExcelCellRange, values: [ExcelCellAddress: ExcelCellInput])? {
        let rowColumn = sourceRange.start.column + rowFieldIndex
        let dataColumn = sourceRange.start.column + dataFieldIndex
        var totals = [String: Double]()
        for row in (sourceRange.start.row + 1) ... sourceRange.end.row {
            let keyCell = sheet.cells[
                ExcelCellAddress(row: row, column: rowColumn)
            ]
            let rawKey = keyCell?.displayValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""
            let key = rawKey.isEmpty
                ? AppLocalization.string("(빈 셀)")
                : rawKey
            let valueCell = sheet.cells[
                ExcelCellAddress(row: row, column: dataColumn)
            ]
            switch aggregation {
            case .sum:
                let normalized = (valueCell?.rawValue ?? "")
                    .replacingOccurrences(of: ",", with: "")
                if let number = Double(normalized), number.isFinite {
                    totals[key, default: 0] += number
                }
            case .count:
                if !(valueCell?.displayValue.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty ?? true) {
                    totals[key, default: 0] += 1
                }
            }
        }
        let keys = totals.keys.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        let endRow = destination.row + keys.count + 2
        let endColumn = destination.column + 1
        guard endRow <= ExcelWorkbookDocument.maximumExcelRows,
              endColumn <= ExcelWorkbookDocument.maximumExcelColumns else {
            status = AppLocalization.string(
                "피벗 결과가 Excel의 최대 행·열 범위를 넘습니다."
            )
            return nil
        }
        let range = ExcelCellRange(
            start: destination,
            end: ExcelCellAddress(row: endRow, column: endColumn)
        )
        var values = [ExcelCellAddress: ExcelCellInput]()
        values[destination] = .text(title)
        values[ExcelCellAddress(
            row: destination.row + 1,
            column: destination.column
        )] = .text(fieldNames[rowFieldIndex])
        values[ExcelCellAddress(
            row: destination.row + 1,
            column: destination.column + 1
        )] = .text(aggregation.title + " - " + fieldNames[dataFieldIndex])
        var grandTotal = 0.0
        for (offset, key) in keys.enumerated() {
            let row = destination.row + offset + 2
            let value = totals[key] ?? 0
            grandTotal += value
            values[ExcelCellAddress(
                row: row,
                column: destination.column
            )] = .text(key)
            values[ExcelCellAddress(
                row: row,
                column: destination.column + 1
            )] = .number(pivotNumberText(value, aggregation: aggregation))
        }
        values[ExcelCellAddress(
            row: endRow,
            column: destination.column
        )] = .text(AppLocalization.string("총합계"))
        values[ExcelCellAddress(
            row: endRow,
            column: destination.column + 1
        )] = .number(pivotNumberText(grandTotal, aggregation: aggregation))
        return (range, values)
    }

    private func pivotNumberText(
        _ value: Double,
        aggregation: ExcelPivotAggregation
    ) -> String {
        if aggregation == .count || value.rounded() == value {
            return String(Int64(value))
        }
        return String(value)
    }

    private func pivotSummaryMutations(
        _ values: [ExcelCellAddress: ExcelCellInput],
        clearing range: ExcelCellRange?,
        in sheet: ExcelWorksheet
    ) -> [CellMutation] {
        var inputs = [ExcelCellAddress: ExcelCellInput]()
        if let range,
           (range.end.row - range.start.row + 1)
            * (range.end.column - range.start.column + 1) <= 10_000 {
            for row in range.start.row ... range.end.row {
                for column in range.start.column ... range.end.column {
                    inputs[ExcelCellAddress(row: row, column: column)] = .blank
                }
            }
        }
        inputs.merge(values) { _, new in new }
        return inputs.sorted { $0.key < $1.key }.map { address, input in
            makeMutation(
                address: address,
                input: input,
                styleIndex: sheet.cells[address]?.styleIndex
                    ?? styleForNewCell(
                        column: address.column,
                        row: address.row,
                        in: sheet
                    ),
                sheet: sheet
            )
        }
    }

    private func pivotDestinationIsAvailable(
        _ range: ExcelCellRange,
        replacing oldRange: ExcelCellRange?,
        in sheet: ExcelWorksheet
    ) -> Bool {
        !sheet.cells.contains { address, cell in
            range.contains(address)
                && !(oldRange?.contains(address) ?? false)
                && !cell.displayValue.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
        }
    }

    private func rangesOverlap(
        _ lhs: ExcelCellRange,
        _ rhs: ExcelCellRange
    ) -> Bool {
        lhs.start.row <= rhs.end.row
            && rhs.start.row <= lhs.end.row
            && lhs.start.column <= rhs.end.column
            && rhs.start.column <= lhs.end.column
    }

    private func uniquePivotName(
        _ rawName: String,
        in workbook: ExcelWorkbook
    ) -> String {
        let existing = Set(
            workbook.sheets.flatMap(\.pivotTables).map {
                $0.name.lowercased()
            }
        )
        let trimmed = rawName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let base = String((trimmed.isEmpty
            ? AppLocalization.string("피벗 테이블")
            : trimmed).prefix(240))
        guard existing.contains(base.lowercased()) else {
            return base
        }
        var index = 2
        while existing.contains("\(base) \(index)".lowercased()) {
            index += 1
        }
        return "\(base) \(index)"
    }

    private func expandSheetBounds(
        for mutations: [CellMutation],
        workbook: inout ExcelWorkbook
    ) {
        guard !mutations.isEmpty else { return }
        workbook.sheets[selectedSheetIndex].maximumRow = max(
            workbook.sheets[selectedSheetIndex].maximumRow,
            mutations.map(\.address.row).max() ?? 1
        )
        workbook.sheets[selectedSheetIndex].maximumColumn = max(
            workbook.sheets[selectedSheetIndex].maximumColumn,
            mutations.map(\.address.column).max() ?? 1
        )
    }

    @discardableResult
    func updateDrawingPlacement(_ selection: ExcelDrawingSelection, expected: ExcelDrawingAnchor, anchor: ExcelDrawingAnchor) -> Bool {
        guard !isSaving, allowEditing(), !isLargeWorkbook, var book = workbook,
              book.sheets.indices.contains(selectedSheetIndex), book.sheets[selectedSheetIndex].partPath == selection.sheetPath,
              anchor.start.row >= 1, anchor.start.row <= 2000, anchor.start.column >= 1, anchor.start.column <= 200,
              anchor.end.row >= anchor.start.row, anchor.end.row <= 2001, anchor.end.column >= anchor.start.column, anchor.end.column <= 201,
              (anchor.end.row > anchor.start.row || anchor.toOffset.y > anchor.fromOffset.y),
              (anchor.end.column > anchor.start.column || anchor.toOffset.x > anchor.fromOffset.x),
              [anchor.fromOffset.x, anchor.fromOffset.y, anchor.toOffset.x, anchor.toOffset.y].allSatisfy({ $0 >= 0 && $0 <= 100_000_000_000 }),
              anchor.extent == nil, anchor.absolutePosition == nil else { return false }
        endEditorTextEditing()
        let old = book.sheets[selectedSheetIndex].drawingObjects
        var next = old
        if let index = next.images.firstIndex(where: { $0.id == selection.id }), next.images[index].anchor == expected {
            next.images[index].anchor = anchor
        } else if let index = next.charts.firstIndex(where: { $0.id == selection.id }), next.charts[index].anchor == expected {
            next.charts[index].anchor = anchor
        } else { return false }
        guard old != next else { return true }
        applyDrawingObjectsChange(old: old, new: next, workbook: &book)
        workbook = book
        status = AppLocalization.string("개체의 위치와 크기를 바꿨습니다. 실행 취소로 되돌릴 수 있습니다.")
        return true
    }

    @discardableResult
    func updateSheetImageDescription(_ selection: ExcelDrawingSelection, name: String, alternativeText: String) -> Bool {
        guard !isSaving, allowEditing(), !isLargeWorkbook, var book = workbook,
              book.sheets.indices.contains(selectedSheetIndex), book.sheets[selectedSheetIndex].partPath == selection.sheetPath else { return false }
        endEditorTextEditing()
        let old = book.sheets[selectedSheetIndex].drawingObjects
        var next = old
        guard let index = next.images.firstIndex(where: { $0.id == selection.id }) else { return false }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        next.images[index].name = title.isEmpty ? old.images[index].name : title
        next.images[index].alternativeText = alternativeText.isEmpty ? nil : alternativeText
        guard next != old else { return true }
        applyDrawingObjectsChange(old: old, new: next, workbook: &book)
        workbook = book
        return true
    }

    private func applyDrawingObjectsChange(
        old: ExcelWorksheetDrawingObjects,
        new: ExcelWorksheetDrawingObjects,
        workbook: inout ExcelWorkbook
    ) {
        apply(
            MutationGroup(
                sheetIndex: selectedSheetIndex,
                cells: [],
                oldDrawingObjects: old,
                newDrawingObjects: new
            ),
            forward: true,
            registeringUndo: true,
            workbook: &workbook
        )
    }

    private func clearNewDrawingIdentityIfEmpty(
        _ objects: inout ExcelWorksheetDrawingObjects,
        original: ExcelWorksheetDrawingObjects
    ) {
        guard objects.images.isEmpty,
              objects.charts.isEmpty,
              objects.shapes.isEmpty,
              objects.otherDrawingObjectCount == 0,
              original.drawingPartPath == nil else {
            return
        }
        objects.drawingPartPath = nil
        objects.drawingRelationshipID = nil
    }

    private func validatedChartRange(
        _ reference: String,
        in sheet: ExcelWorksheet
    ) -> ExcelCellRange? {
        guard let range = ExcelCellRange(
            reference.trimmingCharacters(in: .whitespacesAndNewlines)
        ),
        range.end.row > range.start.row,
        range.end.row <= max(sheet.maximumRow, 1),
        range.end.column <= max(sheet.maximumColumn, 1),
        range.end.column - range.start.column < 12 else {
            return nil
        }
        return range
    }

    private func preparedImage(
        _ data: Data,
        preferredContentType: String? = nil
    ) -> (
        data: Data,
        contentType: String,
        extensionName: String
    )? {
        guard !data.isEmpty,
              data.count <= 20 * 1_024 * 1_024,
              let image = UIImage(data: data) else {
            return nil
        }
        if preferredContentType == "image/jpeg" {
            guard let encoded = image.jpegData(compressionQuality: 0.9) else {
                return nil
            }
            return (encoded, "image/jpeg", "jpg")
        }
        if preferredContentType == "image/png" {
            guard let encoded = image.pngData() else {
                return nil
            }
            return (encoded, "image/png", "png")
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return (data, "image/jpeg", "jpg")
        }
        if data.starts(with: [
            0x89, 0x50, 0x4E, 0x47,
            0x0D, 0x0A, 0x1A, 0x0A,
        ]) {
            return (data, "image/png", "png")
        }
        guard let encoded = image.pngData() else {
            return nil
        }
        return (encoded, "image/png", "png")
    }

    private func isSupportedHyperlinkTarget(_ target: String) -> Bool {
        if target.hasPrefix("#") {
            return target.count > 1
        }
        guard let components = URLComponents(string: target),
              let scheme = components.scheme?.lowercased() else {
            return false
        }
        return ["http", "https", "mailto", "tel"].contains(scheme)
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
        let oldStyles = workbook.styles
        let oldStyleEdits = styleEdits
        let canonicalSelection = sheet.canonicalAddress(
            for: selectedAddress
        )
        let requestedAddresses: [ExcelCellAddress]
        if toCurrentColumn {
            guard let region = ExcelAccessibilityAnalyzer
                .regions(in: sheet)
                .first(where: {
                    $0.contains(canonicalSelection)
                        && $0.columns.contains(where: {
                            $0.column == canonicalSelection.column
                        })
                }) else {
                return
            }
            requestedAddresses = region.rowNumbers.map {
                ExcelCellAddress(
                    row: $0,
                    column: canonicalSelection.column
                )
            }
        } else {
            guard (selectedRange?.cellCount ?? 1) <= 20000 else { return }
            requestedAddresses = selectedRange?.addresses ?? [canonicalSelection]
        }

        let addresses = Array(
            Set(requestedAddresses.map {
                sheet.canonicalAddress(for: $0)
            })
        ).sorted()
        var mutations = [CellMutation]()
        for address in addresses {
            guard let oldCell = sheet.cell(at: address) else {
                continue
            }
            let newStyleIndex = styleIndex(
                for: format,
                replacing: oldCell.styleIndex,
                workbook: &workbook
            )
            guard newStyleIndex != oldCell.styleIndex else {
                continue
            }
            var newCell = oldCell
            newCell.styleIndex = newStyleIndex
            newCell.displayValue = ExcelValueFormatter.displayValue(
                oldCell.rawValue,
                type: oldCell.cellType,
                style: workbook.style(at: newStyleIndex),
                uses1904DateSystem: workbook.uses1904DateSystem
            )
            let oldEdit = edits[sheet.partPath]?[address]
            mutations.append(
                CellMutation(
                    address: address,
                    oldCell: oldCell,
                    newCell: newCell,
                    oldEdit: oldEdit,
                    newEdit: ExcelCellEdit(
                        input: oldEdit?.input
                            ?? input(preserving: oldCell),
                        styleIndex: newStyleIndex,
                        preservesExistingContent:
                            oldEdit?.preservesExistingContent ?? true
                    )
                )
            )
        }
        guard !mutations.isEmpty else {
            status = AppLocalization.string(
                "선택한 셀에 이미 같은 표시 형식이 적용되어 있습니다."
            )
            return
        }
        apply(
            MutationGroup(
                sheetIndex: selectedSheetIndex,
                cells: mutations,
                oldStyles: oldStyles,
                newStyles: workbook.styles,
                oldStyleEdits: oldStyleEdits,
                newStyleEdits: styleEdits
            ),
            forward: true,
            registeringUndo: true,
            workbook: &workbook
        )
        self.workbook = workbook
        syncEditorText(using: workbook.sheets[selectedSheetIndex])
        status = toCurrentColumn
            ? AppLocalization.format(
                "현재 열의 %lld개 데이터 셀을 %@ 표시 형식으로 바꿨습니다.",
                mutations.count,
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
        return columns.map { column in
            let address = sheet.canonicalAddress(
                for: ExcelCellAddress(
                    row: row,
                    column: column.column
                )
            )
            let cell = sheet.cell(at: address)
            let validation = sheet.dataValidations.first {
                $0.contains(address) && $0.inlineListValues != nil
            }
            let presentedValue: String
            if cell?.formula?.isEmpty == false {
                presentedValue = cell?.editText ?? ""
            } else {
                presentedValue = cell?.displayValue ?? ""
            }
            return RowField(
                id: column.column,
                column: column.column,
                title: column.title,
                value: presentedValue,
                originalValue: presentedValue,
                dropdownValues: validation?.inlineListValues ?? [],
                dropdownAllowsBlank: validation?.allowsBlank ?? true
            )
        }
    }

    func rowFieldsForAppending() -> [RowField] {
        guard let sheet = selectedSheet else {
            return []
        }
        if let region = ExcelAccessibilityAnalyzer.region(
            containing: selectedAddress,
            in: sheet
        ) {
            return region.columns.map { column in
                RowField(
                    id: column.column,
                    column: column.column,
                    title: column.title,
                    value: ""
                )
            }
        }
        let columns: ClosedRange<Int>
        let headerRow: Int
        if let selectedAddress,
           let table = sheet.table(containing: selectedAddress) {
            columns = table.range.start.column ... table.range.end.column
            headerRow = table.range.start.row
        } else {
            columns = 1 ... max(min(sheet.maximumColumn, 30), 1)
            headerRow = firstPopulatedRow(in: sheet)
        }
        return columns.map { column in
            let address = ExcelCellAddress(
                row: headerRow,
                column: column
            )
            let header = sheet.cell(at: address)?.displayValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return RowField(
                id: column,
                column: column,
                title: header?.isEmpty == false
                    ? header!
                    : ExcelCellAddress.columnName(column),
                value: ""
            )
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
        let sheet = workbook.sheets[selectedSheetIndex]
        let oldStyles = workbook.styles
        let oldStyleEdits = styleEdits
        var mutations = [CellMutation]()
        for field in fields where field.value != field.originalValue {
            let address = sheet.canonicalAddress(
                for: ExcelCellAddress(
                    row: row,
                    column: field.column
                )
            )
            let styleIndex = sheet.cell(at: address)?.styleIndex
                ?? styleForNewCell(
                    column: address.column,
                    row: address.row,
                    in: sheet
                )
            let resolved = resolvedUserInput(
                field.value,
                styleIndex: styleIndex,
                workbook: &workbook
            )
            mutations.append(
                makeMutation(
                    address: address,
                    input: resolved.input,
                    styleIndex: resolved.styleIndex,
                    sheet: sheet,
                    workbook: workbook
                )
            )
        }
        guard !mutations.isEmpty else {
            return
        }
        let stylesChanged = workbook.styles.count != oldStyles.count
        apply(
            MutationGroup(
                sheetIndex: selectedSheetIndex,
                cells: mutations,
                oldStyles: stylesChanged ? oldStyles : nil,
                newStyles: stylesChanged ? workbook.styles : nil,
                oldStyleEdits: stylesChanged ? oldStyleEdits : nil,
                newStyleEdits: stylesChanged ? styleEdits : nil
            ),
            forward: true,
            registeringUndo: true,
            workbook: &workbook
        )
        self.workbook = workbook
        selectedAddress = mutations.first?.address
        syncEditorText(using: workbook.sheets[selectedSheetIndex])
        status = AppLocalization.format(
            "%lld행의 %lld개 값을 수정했습니다. 저장하면 XLSX 파일에 반영됩니다.",
            row,
            mutations.count
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
        let table = selectedAddress.flatMap {
            sheet.table(containing: $0)
        }
        let preferredRow = (table?.range.end.row ?? sheet.maximumRow) + 1
        let fieldColumns = Set(fields.map(\.column))
        let preferredRowIsOccupied = sheet.cells.keys.contains {
            $0.row == preferredRow
                && fieldColumns.contains($0.column)
        }
        let newRow = preferredRowIsOccupied
            ? max(sheet.maximumRow + 1, preferredRow)
            : preferredRow
        guard newRow <= ExcelWorkbookDocument.maximumExcelRows else {
            status = AppLocalization.string(
                "Excel의 최대 행 수를 초과해 행을 추가할 수 없습니다."
            )
            return
        }
        var mutations: [CellMutation] = []
        let oldStyles = workbook.styles
        let oldStyleEdits = styleEdits
        for field in fields {
            let address = ExcelCellAddress(
                row: newRow,
                column: field.column
            )
            let trimmedValue = field.value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            var styleIndex = styleForNewCell(
                column: field.column,
                row: newRow,
                in: sheet
            )
            let input: ExcelCellInput
            if !trimmedValue.isEmpty {
                let resolved = resolvedUserInput(
                    field.value,
                    styleIndex: styleIndex,
                    workbook: &workbook
                )
                input = resolved.input
                styleIndex = resolved.styleIndex
            } else if let previousCell = sheet.cells[
                ExcelCellAddress(
                    row: max(newRow - 1, 1),
                    column: field.column
                )
            ],
            let formula = previousCell.formula {
                input = .formula(
                    ExcelFormulaTranslator.shiftingRelativeRows(
                        in: formula,
                        by: 1
                    )
                )
            } else {
                continue
            }
            mutations.append(
                makeMutation(
                    address: address,
                    input: input,
                    styleIndex: styleIndex,
                    sheet: sheet,
                    workbook: workbook
                )
            )
        }
        guard !mutations.isEmpty else {
            return
        }
        let stylesChanged = workbook.styles.count != oldStyles.count
        apply(
            MutationGroup(
                sheetIndex: selectedSheetIndex,
                cells: mutations,
                oldStyles: stylesChanged ? oldStyles : nil,
                newStyles: stylesChanged ? workbook.styles : nil,
                oldStyleEdits: stylesChanged ? oldStyleEdits : nil,
                newStyleEdits: stylesChanged ? styleEdits : nil
            ),
            forward: true,
            registeringUndo: true,
            workbook: &workbook
        )
        workbook.sheets[selectedSheetIndex].maximumRow = max(
            workbook.sheets[selectedSheetIndex].maximumRow,
            newRow
        )
        workbook.sheets[selectedSheetIndex].maximumColumn = max(
            workbook.sheets[selectedSheetIndex].maximumColumn,
            mutations.map(\.address.column).max() ?? 1
        )
        if let table,
           let tableIndex = workbook.sheets[selectedSheetIndex]
            .tables.firstIndex(where: { $0.id == table.id }) {
            workbook.sheets[selectedSheetIndex]
                .tables[tableIndex].range = ExcelCellRange(
                    start: table.range.start,
                    end: ExcelCellAddress(
                        row: max(table.range.end.row, newRow),
                        column: table.range.end.column
                    )
                )
        }
        self.workbook = workbook
        if isLargeWorkbook {
            largeAddedRows[sheet.partPath, default: []].insert(newRow)
            largeWindowRows[sheet.partPath, default: []].append(newRow)
            largeWindowRows[sheet.partPath]?.sort()
        }
        selectedAddress = ExcelCellAddress(
            row: newRow,
            column: mutations.first?.address.column ?? 1
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
        guard let width = values.first?.count, width > 0, !values.isEmpty else { return }
        let repeated = width == 1 && values.count == 1 && clip?.isCut != true
        let rows = repeated ? (selectedRange?.end.row ?? target.row) - target.row + 1 : values.count
        let columns = repeated ? (selectedRange?.end.column ?? target.column) - target.column + 1 : width
        let destination = ExcelCellRange(start: target, end: ExcelCellAddress(row: target.row + rows - 1, column: target.column + columns - 1))
        guard destination.cellCount <= 20000, destination.end.row <= 1048576, destination.end.column <= 16384 else { status = AppLocalization.string("붙여넣을 범위가 너무 큽니다."); return }
        var updates: [Int: [ExcelCellAddress: ExcelClipboardValue]] = [:]
        if let clip, clip.isCut {
            guard original.sheets.indices.contains(clip.sheetIndex), !original.sheets[clip.sheetIndex].protection.isEnabled else { return }
            // A cut is deferred, so refuse to clear source cells edited since copying.
            for (r, row) in clip.values.enumerated() {
                for (c, value) in row.enumerated() {
                    let address = ExcelCellAddress(row: clip.range.start.row + r, column: clip.range.start.column + c)
                    guard (original.sheets[clip.sheetIndex].cells[address]?.editText ?? "") == value.text else { status = AppLocalization.string("잘라낼 원본이 변경되었습니다. 범위를 다시 선택해 주세요."); return }
                    updates[clip.sheetIndex, default: [:]][address] = ExcelClipboardValue(text: "", styleIndex: nil)
                }
            }
        }
        for r in 0 ..< rows {
            for c in 0 ..< columns {
                let value = values[repeated ? 0 : r][repeated ? 0 : c]
                let address = ExcelCellAddress(row: target.row + r, column: target.column + c)
                var pasted = value.text
                let isFormula: Bool
                if case .formula = value.input { isFormula = true } else { isFormula = value.input == nil && pasted.hasPrefix("=") }
                if isFormula, let clip, !clip.isCut {
                    let source = ExcelCellAddress(row: clip.range.start.row + (repeated ? 0 : r), column: clip.range.start.column + (repeated ? 0 : c))
                    pasted = "=" + ExcelFormulaReferenceEditing.copied(String(pasted.dropFirst()), from: source, to: address)
                }
                updates[selectedSheetIndex, default: [:]][address] = ExcelClipboardValue(text: pasted, styleIndex: clip == nil ? original.sheets[selectedSheetIndex].cells[address]?.styleIndex : value.styleIndex, input: isFormula ? .formula(String(pasted.dropFirst())) : value.input)
            }
        }
        if let clip, clip.isCut {
            let sourceName = original.sheets[clip.sheetIndex].name
            let destinationName = original.sheets[selectedSheetIndex].name
            if sourceName != destinationName && clip.values.flatMap({ $0 }).contains(where: { $0.text.hasPrefix("=") }) {
                status = AppLocalization.string("수식이 포함된 범위의 시트 간 잘라내기는 복사·붙여넣기를 사용해 주세요."); return
            }
            for (index, sheet) in original.sheets.enumerated() {
                let addresses = Set(sheet.cells.keys).union(updates[index]?.keys.map { $0 } ?? [])
                for address in addresses {
                    let cell = sheet.cells[address]
                    let effective = updates[index]?[address]?.text ?? cell?.editText ?? ""
                    let currentInput = updates[index]?[address].map { $0.input ?? ExcelCellInput(userText: $0.text) } ?? cell.map { input(preserving: $0) }
                    guard case .formula = currentInput else { continue }
                    let moved = "=" + ExcelFormulaReferenceEditing.moved(String(effective.dropFirst()), source: clip.range, sourceSheet: sourceName, destination: target, destinationSheet: destinationName, formulaSheet: sheet.name)
                    if moved != effective { updates[index, default: [:]][address] = ExcelClipboardValue(text: moved, styleIndex: updates[index]?[address]?.styleIndex ?? cell?.styleIndex, input: .formula(String(moved.dropFirst()))) }
                }
            }
        }
        if applyRangeUpdates(updates) {
            selectedAddress = target; selectionEnd = destination.end
            if clip?.isCut == true { rangeClipboard = nil }
            status = AppLocalization.string("선택한 위치에 붙여넣었습니다.")
        }
    }

    func clearSelection() {
        guard let range = selectedRange, range.cellCount <= 20000 else { return }
        if range.cellCount == 1 || selectedSheet?.mergedRange(containing: range.start) == range { clearSelectedCell(); return }
        let updates = Dictionary(uniqueKeysWithValues: range.addresses.map { ($0, ExcelClipboardValue(text: "", styleIndex: selectedSheet?.cells[$0]?.styleIndex)) })
        if applyRangeUpdates([selectedSheetIndex: updates]) { status = AppLocalization.string("선택 범위의 값을 지웠습니다.") }
    }

    func fillSelection(across: Bool) {
        guard let range = selectedRange, let sheet = selectedSheet, range.cellCount > 1, range.cellCount <= 20000 else { return }
        var updates: [ExcelCellAddress: ExcelClipboardValue] = [:]
        for address in range.addresses {
            let seed = ExcelCellAddress(row: across ? address.row : range.start.row, column: across ? range.start.column : address.column)
            let second = ExcelCellAddress(row: across ? seed.row : seed.row + 1, column: across ? seed.column + 1 : seed.column)
            let offset = across ? address.column - seed.column : address.row - seed.row
            guard offset > 0 else { continue }
            let original = sheet.cells[seed]
            var text = original?.editText ?? ""
            if let formula = original?.formula { text = "=" + ExcelFormulaReferenceEditing.copied(formula, from: seed, to: address) }
            else if let first = Double(text), let nextText = sheet.cells[second]?.rawValue, let next = Double(nextText), range.contains(second) {
                text = String(first + Double(offset) * (next - first))
            }
            let preserved = original.map { input(preserving: $0) }
            let newInput: ExcelCellInput? = original?.formula != nil ? .formula(String(text.dropFirst())) : text == original?.editText ? preserved : ExcelCellInput(userText: text)
            updates[address] = ExcelClipboardValue(text: text, styleIndex: original?.styleIndex, input: newInput)
        }
        if applyRangeUpdates([selectedSheetIndex: updates]) { status = AppLocalization.string("선택 범위를 채웠습니다.") }
    }

    @discardableResult private func applyRangeUpdates(_ updates: [Int: [ExcelCellAddress: ExcelClipboardValue]]) -> Bool {
        guard allowEditing(), !isLargeWorkbook, var next = workbook else { return false }
        guard updates.values.reduce(0, { $0 + $1.count }) <= 20000, updates.values.contains(where: { !$0.isEmpty }) else {
            status = AppLocalization.string("한 번에 편집할 범위는 20,000셀 이하로 선택해 주세요."); return false
        }
        endEditorTextEditing()
        let old = captureEditingState(next)
        for (index, values) in updates {
            guard next.sheets.indices.contains(index), !next.sheets[index].protection.isEnabled, !next.sheets[index].didTruncate else { status = AppLocalization.string("편집할 수 없는 시트가 포함되어 있습니다."); return false }
            let sheet = next.sheets[index]
            if values.keys.contains(where: { sheet.cells[$0]?.spillAnchor != nil || sheet.canonicalAddress(for: $0) != $0 }) || values.count > 1 && sheet.mergedRanges.contains(where: { merged in values.keys.contains(where: merged.contains) }) {
                status = AppLocalization.string("병합 셀이나 배열 수식이 포함된 범위는 이 작업을 사용할 수 없습니다."); return false
            }
        }
        for (index, values) in updates.sorted(by: { $0.key < $1.key }) {
            let sheet = next.sheets[index]
            let mutations = values.sorted { $0.key < $1.key }.map { address, value -> CellMutation in
                let validStyle = value.styleIndex.flatMap { next.styles.indices.contains($0) ? $0 : nil }
                let resolved = value.input.map { (input: $0, styleIndex: validStyle) } ?? resolvedUserInput(value.text, styleIndex: validStyle, workbook: &next)
                let mutation = makeMutation(address: address, input: resolved.input, styleIndex: resolved.styleIndex, sheet: sheet, workbook: next)
                if mutation.newCell == nil, let styleIndex = resolved.styleIndex {
                    return CellMutation(address: address, oldCell: mutation.oldCell, newCell: ExcelCell(address: address, rawValue: "", displayValue: "", formula: nil, styleIndex: styleIndex, cellType: nil), oldEdit: mutation.oldEdit, newEdit: mutation.newEdit)
                }
                return mutation
            }
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
        return sheet.cells.values.filter { $0.editText.range(of: findText, options: [.caseInsensitive, .diacriticInsensitive]) != nil }.map(\.address).sorted()
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
        var updates: [ExcelCellAddress: ExcelClipboardValue] = [:]
        for address in addresses {
            guard let cell = sheet.cells[address], cell.editText.range(of: findText, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { continue }
            let newText = cell.editText.replacingOccurrences(of: findText, with: replacement, options: [.caseInsensitive, .diacriticInsensitive])
            let literal = ["s", "inlineStr", "str"].contains(cell.cellType ?? "") && cell.formula == nil
            updates[address] = ExcelClipboardValue(text: newText, styleIndex: cell.styleIndex, input: literal ? .text(newText) : nil)
        }
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
            let input = try await exportData()
            let result = try await Task.detached(priority: .userInitiated) {
                let result = try ExcelSheetManagement.applying(edit, to: input, workbook: original, selectedSheetPath: active)
                var loaded = try ExcelWorkbookDocument.load(from: result.data)
                guard !loaded.sheets.contains(where: { $0.didTruncate }) else { throw ExcelEditingError("이 편집으로 일반 문서의 행·열 표시 한도를 넘습니다.") }
                _ = Self.refreshDerivedFormulaValues(in: &loaded, edits: [:])
                return (result, loaded)
            }.value
            guard result.0.data != input else { status = AppLocalization.string("변경할 내용이 없습니다."); return true }
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
        edits.removeAll()
        styleEdits.removeAll()
        validationEdits.removeAll()
        conditionalFormattingEdits.removeAll()
        differentialStyleEdits.removeAll()
        annotationEdits.removeAll()
        drawingObjectEdits.removeAll()
        pivotTableEdits.removeAll()

        originalDataValidations = Dictionary(uniqueKeysWithValues: workbook.sheets.map { ($0.partPath, $0.dataValidations) })
        originalConditionalFormatting = Dictionary(uniqueKeysWithValues: workbook.sheets.map { ($0.partPath, $0.conditionalFormatting) })
        originalAnnotations = Dictionary(uniqueKeysWithValues: workbook.sheets.map { ($0.partPath, $0.annotations) })
        originalDrawingObjects = Dictionary(uniqueKeysWithValues: workbook.sheets.map { ($0.partPath, $0.drawingObjects) })
        originalPivotTables = Dictionary(uniqueKeysWithValues: workbook.sheets.map { ($0.partPath, $0.pivotTables) })
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
            let input = try await exportData()
            let sheetIndex = selectedSheetIndex
            let result = try await Task.detached(priority: .userInitiated) {
                let data = try ExcelAdvancedWorkbookEditing.applying(edit, to: input, workbook: original, sheetIndex: sheetIndex)
                var loaded = try ExcelWorkbookDocument.load(from: data)
                guard !loaded.sheets.contains(where: { $0.didTruncate }) else { throw ExcelEditingError("이 편집으로 일반 문서의 행·열 표시 한도를 넘습니다.") }
                _ = Self.refreshDerivedFormulaValues(in: &loaded, edits: [:])
                return (data, loaded)
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
            let pendingEdits = serializedEdits()
            let pendingStyleEdits = serializedStyleEdits()
            let pendingValidationEdits = serializedValidationEdits()
            let pendingConditionalFormattingEdits =
                serializedConditionalFormattingEdits()
            let pendingDifferentialStyleEdits =
                serializedDifferentialStyleEdits()
            let pendingAnnotationEdits = serializedAnnotationEdits()
            let pendingDrawingEdits = serializedDrawingEdits()
            let pendingPivotEdits = serializedPivotEdits()
            let destination = fileURL
            let writeContents = writeContents
            let preflight = largeWorkbookPreflight
            let savedResult = try await Task.detached(
                priority: .userInitiated
            ) {
                let data = try ExcelWorkbookDocument.applying(
                    pendingEdits,
                    to: inputData,
                    workbook: workbook,
                    styleEdits: pendingStyleEdits,
                    validationEdits: pendingValidationEdits,
                    conditionalFormattingEdits:
                        pendingConditionalFormattingEdits,
                    differentialStyleEdits:
                        pendingDifferentialStyleEdits,
                    annotationEdits: pendingAnnotationEdits,
                    drawingEdits: pendingDrawingEdits,
                    pivotEdits: pendingPivotEdits
                )
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
                edits.removeAll()
                styleEdits.removeAll()
                validationEdits.removeAll()
                conditionalFormattingEdits.removeAll()
                differentialStyleEdits.removeAll()
                annotationEdits.removeAll()
                drawingObjectEdits.removeAll()
                pivotTableEdits.removeAll()
                originalDataValidations = Dictionary(
                    uniqueKeysWithValues: workbook.sheets.map {
                        ($0.partPath, $0.dataValidations)
                    }
                )
                originalConditionalFormatting = Dictionary(
                    uniqueKeysWithValues: workbook.sheets.map {
                        ($0.partPath, $0.conditionalFormatting)
                    }
                )
                originalAnnotations = Dictionary(
                    uniqueKeysWithValues: workbook.sheets.map {
                        ($0.partPath, $0.annotations)
                    }
                )
                originalDrawingObjects = Dictionary(
                    uniqueKeysWithValues: workbook.sheets.map {
                        ($0.partPath, $0.drawingObjects)
                    }
                )
                originalPivotTables = Dictionary(
                    uniqueKeysWithValues: workbook.sheets.map {
                        ($0.partPath, $0.pivotTables)
                    }
                )
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
        let edits = serializedEdits()
        let styleEdits = serializedStyleEdits()
        let validationEdits = serializedValidationEdits()
        let conditionalFormattingEdits =
            serializedConditionalFormattingEdits()
        let differentialStyleEdits = serializedDifferentialStyleEdits()
        let annotationEdits = serializedAnnotationEdits()
        let drawingEdits = serializedDrawingEdits()
        let pivotEdits = serializedPivotEdits()
        return try await Task.detached(priority: .userInitiated) {
            try ExcelWorkbookDocument.applying(
                edits,
                to: sourceData,
                workbook: workbook,
                styleEdits: styleEdits,
                validationEdits: validationEdits,
                conditionalFormattingEdits: conditionalFormattingEdits,
                differentialStyleEdits: differentialStyleEdits,
                annotationEdits: annotationEdits,
                drawingEdits: drawingEdits,
                pivotEdits: pivotEdits
            )
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
        let sourceSheet = workbook.sheets[sheetIndex]
        guard !sourceSheet.protection.isEnabled else {
            throw ExcelAICommandValidationError.protectedWorksheet
        }
        let regions = ExcelAccessibilityAnalyzer.regions(in: sourceSheet)
        let oldStyles = workbook.styles
        let oldStyleEdits = styleEdits
        let oldDifferentialStyles = workbook.differentialStyles
        let oldDifferentialStyleEdits = differentialStyleEdits
        var mutations = [CellMutation]()
        var newTables = sourceSheet.tables
        var createdTableFirstAddress: ExcelCellAddress?

        let existingTableNumbers = workbook.sheets
            .flatMap(\.tables)
            .compactMap { table -> Int? in
                let name = URL(fileURLWithPath: table.partPath)
                    .deletingPathExtension()
                    .lastPathComponent
                guard name.hasPrefix("table") else { return nil }
                return Int(name.dropFirst("table".count))
            }
        var nextTableNumber = (existingTableNumbers.max() ?? 0) + 1
        var usedTableNames = Set(
            workbook.sheets.flatMap(\.tables).map {
                $0.name.lowercased()
            }
        )
        let rangesOverlap: (ExcelCellRange, ExcelCellRange) -> Bool = {
            lhs,
            rhs in
            lhs.start.row <= rhs.end.row
                && lhs.end.row >= rhs.start.row
                && lhs.start.column <= rhs.end.column
                && lhs.end.column >= rhs.start.column
        }

        for createdTable in plan.createdTables {
            let start = ExcelCellAddress(
                row: createdTable.startRow,
                column: createdTable.startColumn
            )
            let range = ExcelCellRange(
                start: start,
                end: ExcelCellAddress(
                    row: createdTable.startRow
                        + createdTable.blankRowCount,
                    column: createdTable.startColumn
                        + createdTable.headers.count - 1
                )
            )
            guard !sourceSheet.cells.keys.contains(where: range.contains),
                  !sourceSheet.mergedRanges.contains(where: {
                      rangesOverlap(range, $0)
                  }),
                  !newTables.contains(where: {
                      rangesOverlap(range, $0.range)
                  }) else {
                throw ExcelAIApplyError.invalidTarget
            }

            while usedTableNames.contains(
                "table\(nextTableNumber)".lowercased()
            ) {
                nextTableNumber += 1
            }
            let tableName = "Table\(nextTableNumber)"
            let table = ExcelTable(
                id: String(nextTableNumber),
                name: tableName,
                range: range,
                partPath: "xl/tables/table\(nextTableNumber).xml",
                columnNames: createdTable.headers,
                headerRowCount: 1,
                totalsRowCount: 0
            )
            nextTableNumber += 1
            usedTableNames.insert(tableName.lowercased())
            newTables.append(table)
            createdTableFirstAddress = createdTableFirstAddress ?? start

            for (offset, header) in createdTable.headers.enumerated() {
                let address = ExcelCellAddress(
                    row: createdTable.startRow,
                    column: createdTable.startColumn + offset
                )
                mutations.append(
                    makeMutation(
                        address: address,
                        input: .text(header),
                        styleIndex: styleForNewCell(
                            column: address.column,
                            row: address.row,
                            in: sourceSheet
                        ),
                        sheet: sourceSheet
                    )
                )
            }
        }

        for edit in plan.edits {
            let requested = ExcelCellAddress(row: edit.row, column: edit.column)
            let address = sourceSheet.canonicalAddress(for: requested)
            let isExplicit = plan.explicitAddresses.contains(requested)
            if !isExplicit {
                guard let region = regions.first(where: {
                    let rowIsEditable = $0.isNativeTable
                        ? edit.row > ($0.headerRow ?? $0.range.start.row)
                            && $0.range.contains(requested)
                        : $0.rowNumbers.contains(edit.row)
                    return rowIsEditable
                        && $0.columns.contains(where: {
                            $0.column == edit.column
                        })
                }) else {
                    throw ExcelAIApplyError.invalidTarget
                }
                let rowIsEditable = region.isNativeTable
                    ? address.row > (region.headerRow ?? region.range.start.row)
                        && region.range.contains(address)
                    : region.rowNumbers.contains(address.row)
                guard rowIsEditable,
                      region.columns.contains(where: {
                          $0.column == address.column
                      }) else {
                    throw ExcelAIApplyError.invalidTarget
                }
            } else {
                guard requested.row <= ExcelWorkbookDocument.maximumExcelRows else {
                    throw ExcelAIApplyError.rowLimitExceeded
                }
            }
            let baseStyleIndex = sourceSheet.cell(at: address)?.styleIndex
                ?? styleForNewCell(
                    column: address.column,
                    row: address.row,
                    in: sourceSheet
                )
            let resolved = resolvedUserInput(
                edit.newValue,
                styleIndex: baseStyleIndex,
                workbook: &workbook
            )
            mutations.append(
                makeMutation(
                    address: address,
                    input: resolved.input,
                    styleIndex: resolved.styleIndex,
                    sheet: sourceSheet,
                    workbook: workbook
                )
            )
        }

        var nextRowByRegion = Dictionary(
            uniqueKeysWithValues: regions.map {
                ($0.id, $0.range.end.row + 1)
            }
        )
        var appendedEndRowByRegion = [String: Int]()
        var reservedRows = Set<Int>()

        for appendedRow in plan.appendedRows {
            guard let region = regions.first(where: {
                $0.id == appendedRow.regionID
            }) else {
                throw ExcelAIApplyError.invalidTarget
            }
            let columnNumbers = Set(region.columns.map(\.column))
            let newRow = nextRowByRegion[region.id]
                ?? region.range.end.row + 1
            let rowIsOccupied: (Int) -> Bool = { row in
                reservedRows.contains(row)
                    || sourceSheet.cells.keys.contains {
                        $0.row == row
                            && columnNumbers.contains($0.column)
                    }
            }
            if rowIsOccupied(newRow) {
                throw ExcelAIApplyError.appendTargetOccupied
            }
            guard newRow <= ExcelWorkbookDocument.maximumExcelRows else {
                throw ExcelAIApplyError.rowLimitExceeded
            }
            reservedRows.insert(newRow)
            nextRowByRegion[region.id] = newRow + 1
            appendedEndRowByRegion[region.id] = max(
                appendedEndRowByRegion[region.id] ?? 0,
                newRow
            )

            let valuesByColumn = Dictionary(
                uniqueKeysWithValues: appendedRow.values.map {
                    ($0.column, $0.newValue)
                }
            )
            for column in region.columns {
                var styleIndex = styleForNewCell(
                    column: column.column,
                    row: newRow,
                    in: sourceSheet
                )
                let input: ExcelCellInput
                if let value = valuesByColumn[column.column] {
                    let resolved = resolvedUserInput(
                        value,
                        styleIndex: styleIndex,
                        workbook: &workbook
                    )
                    input = resolved.input
                    styleIndex = resolved.styleIndex
                } else if let previousCell = sourceSheet.cells[
                    ExcelCellAddress(
                        row: region.range.end.row,
                        column: column.column
                    )
                ], let formula = previousCell.formula {
                    input = .formula(
                        ExcelFormulaTranslator.shiftingRelativeRows(
                            in: formula,
                            by: newRow - region.range.end.row
                        )
                    )
                } else {
                    continue
                }
                let address = ExcelCellAddress(
                    row: newRow,
                    column: column.column
                )
                mutations.append(
                    makeMutation(
                        address: address,
                        input: input,
                        styleIndex: styleIndex,
                        sheet: sourceSheet,
                        workbook: workbook
                    )
                )
            }
        }

        // Edits are canonicalized to merged-range anchors above, so two
        // plan entries can resolve to one address. Reject instead of
        // trapping in `Dictionary(uniqueKeysWithValues:)`.
        var mutationsByAddress = [ExcelCellAddress: CellMutation]()
        for mutation in mutations {
            guard mutationsByAddress
                .updateValue(mutation, forKey: mutation.address) == nil
            else {
                throw ExcelAIApplyError.conflictingEdits
            }
        }
        var newDataValidations = sourceSheet.dataValidations
        var newConditionalFormatting = sourceSheet.conditionalFormatting

        for action in plan.actions {
            guard action.addresses.allSatisfy({ address in
                regions.contains(where: { region in
                    let rowIsEditable = region.isNativeTable
                        ? address.row
                            > (region.headerRow ?? region.range.start.row)
                            && region.range.contains(address)
                        : region.rowNumbers.contains(address.row)
                    return rowIsEditable
                        && region.columns.contains(where: {
                            $0.column == address.column
                        })
                })
            }) else {
                throw ExcelAIApplyError.invalidTarget
            }
            let ranges = ExcelCellRange.verticalRanges(
                for: action.addresses
            )
            switch action {
            case .setNumberFormat(let addresses, let format):
                for address in addresses {
                    let existingMutation = mutationsByAddress[address]
                    guard let currentCell = existingMutation?.newCell
                            ?? sourceSheet.cell(at: address) else {
                        continue
                    }
                    let newStyleIndex = styleIndex(
                        for: format,
                        replacing: currentCell.styleIndex,
                        workbook: &workbook
                    )
                    guard newStyleIndex != currentCell.styleIndex else {
                        continue
                    }
                    var updatedCell = currentCell
                    updatedCell.styleIndex = newStyleIndex
                    updatedCell.displayValue = ExcelValueFormatter.displayValue(
                        currentCell.rawValue,
                        type: currentCell.cellType,
                        style: workbook.style(at: newStyleIndex),
                        uses1904DateSystem: workbook.uses1904DateSystem
                    )
                    // Carry over the unsaved edit for this cell (from an
                    // earlier turn) so its content and its
                    // `preservesExistingContent` flag survive; otherwise a
                    // cell that only exists in memory would be written as
                    // a style-only patch and fail to save.
                    let currentEdit = existingMutation?.newEdit
                        ?? edits[sourceSheet.partPath]?[address]
                    mutationsByAddress[address] = CellMutation(
                        address: address,
                        oldCell: existingMutation?.oldCell
                            ?? sourceSheet.cell(at: address),
                        newCell: updatedCell,
                        oldEdit: existingMutation?.oldEdit
                            ?? edits[sourceSheet.partPath]?[address],
                        newEdit: ExcelCellEdit(
                            input: currentEdit?.input
                                ?? input(preserving: currentCell),
                            styleIndex: newStyleIndex,
                            preservesExistingContent:
                                currentEdit?.preservesExistingContent ?? true,
                            cachedValue: currentEdit?.cachedValue,
                            cachedType: currentEdit?.cachedType,
                            formulaSpillRange:
                                currentEdit?.formulaSpillRange
                        )
                    )
                }

            case .setDropdown(_, let values, let allowsBlank):
                newDataValidations = newDataValidations.compactMap {
                    $0.removing(ranges)
                }
                newDataValidations.append(
                    .inlineList(
                        ranges: ranges,
                        values: values,
                        allowsBlank: allowsBlank
                    )
                )

            case .removeDropdown:
                newDataValidations = newDataValidations.compactMap { rule in
                    rule.type == "list" ? rule.removing(ranges) : rule
                }

            case .setConditionalFormatting(
                _,
                let kind,
                let comparisonValue,
                let highlight
            ):
                newConditionalFormatting = newConditionalFormatting
                    .compactMap { block in
                        block.isSameRule(
                            kind: kind,
                            comparisonValue: comparisonValue
                        ) ? block.removing(ranges) : block
                    }
                let styleIndex = differentialStyleIndex(
                    for: highlight.style,
                    workbook: &workbook
                )
                let priority = newConditionalFormatting
                    .flatMap(\.rules)
                    .map(\.priority)
                    .max()
                    .map { $0 + 1 } ?? 1
                newConditionalFormatting.append(
                    ExcelConditionalFormattingBlock(
                        ranges: ranges,
                        rules: [
                            ExcelConditionalFormattingRule(
                                kind: kind,
                                comparisonValue: comparisonValue,
                                differentialStyleIndex: styleIndex,
                                priority: priority
                            ),
                        ]
                    )
                )

            case .removeConditionalFormatting:
                newConditionalFormatting = newConditionalFormatting
                    .compactMap { $0.removing(ranges) }
            }
        }

        mutations = mutationsByAddress.values.sorted {
            $0.address < $1.address
        }
        let dataValidationsChanged =
            newDataValidations != sourceSheet.dataValidations
        let conditionalFormattingChanged =
            newConditionalFormatting != sourceSheet.conditionalFormatting
        guard !mutations.isEmpty
                || dataValidationsChanged
                || conditionalFormattingChanged else {
            throw ExcelAIApplyError.noChanges
        }
        apply(
            MutationGroup(
                sheetIndex: sheetIndex,
                cells: mutations,
                oldStyles: oldStyles,
                newStyles: workbook.styles,
                oldStyleEdits: oldStyleEdits,
                newStyleEdits: styleEdits,
                oldDifferentialStyles: oldDifferentialStyles,
                newDifferentialStyles: workbook.differentialStyles,
                oldDifferentialStyleEdits: oldDifferentialStyleEdits,
                newDifferentialStyleEdits: differentialStyleEdits,
                oldDataValidations: dataValidationsChanged
                    ? sourceSheet.dataValidations : nil,
                newDataValidations: dataValidationsChanged
                    ? newDataValidations : nil,
                oldConditionalFormatting: conditionalFormattingChanged
                    ? sourceSheet.conditionalFormatting : nil,
                newConditionalFormatting: conditionalFormattingChanged
                    ? newConditionalFormatting : nil,
                oldTables: plan.createdTables.isEmpty
                    ? nil : sourceSheet.tables,
                newTables: plan.createdTables.isEmpty
                    ? nil : newTables
            ),
            forward: true,
            registeringUndo: true,
            workbook: &workbook
        )
        workbook.sheets[sheetIndex].maximumRow = max(
            workbook.sheets[sheetIndex].maximumRow,
            mutations.map(\.address.row).max() ?? 1,
            plan.createdTables.map {
                $0.startRow + $0.blankRowCount
            }.max() ?? 1
        )
        workbook.sheets[sheetIndex].maximumColumn = max(
            workbook.sheets[sheetIndex].maximumColumn,
            mutations.map(\.address.column).max() ?? 1,
            plan.createdTables.map {
                $0.startColumn + $0.headers.count - 1
            }.max() ?? 1
        )
        for (regionID, endRow) in appendedEndRowByRegion {
            guard regionID.hasPrefix("table:"),
                  let tableIndex = workbook.sheets[sheetIndex]
                    .tables.firstIndex(where: {
                        "table:" + $0.id == regionID
                    }) else {
                continue
            }
            let table = workbook.sheets[sheetIndex].tables[tableIndex]
            workbook.sheets[sheetIndex].tables[tableIndex].range =
                ExcelCellRange(
                    start: table.range.start,
                    end: ExcelCellAddress(
                        row: max(table.range.end.row, endRow),
                        column: table.range.end.column
                    )
                )
        }

        self.workbook = workbook
        selectedAddress = createdTableFirstAddress
            ?? mutations.first?.address
            ?? plan.actions.first?.addresses.first
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
        let sheet = workbook.sheets[selectedSheetIndex]
        let address = sheet.canonicalAddress(for: requestedAddress)
        if let owner = sheet.cells[address]?.spillAnchor,
           owner != address {
            editorText = sheet.cells[address]?.displayValue ?? ""
            status = AppLocalization.format(
                "%@은(는) %@ 수식의 Spill 결과입니다. 원본 셀에서 수정해 주세요.",
                address.reference,
                owner.reference
            )
            return
        }
        guard (sheet.cell(at: address)?.editText ?? "") != userText else {
            return
        }
        let baseStyleIndex = sheet.cell(at: address)?.styleIndex
            ?? styleForNewCell(
                column: address.column,
                row: address.row,
                in: sheet
            )
        let oldStyles = workbook.styles
        let oldStyleEdits = styleEdits
        let resolved = resolvedUserInput(
            userText,
            styleIndex: baseStyleIndex,
            workbook: &workbook
        )
        let mutation = makeMutation(
            address: address,
            input: resolved.input,
            styleIndex: resolved.styleIndex,
            sheet: sheet,
            workbook: workbook
        )
        let stylesChanged = workbook.styles.count != oldStyles.count
        let group = MutationGroup(
            sheetIndex: selectedSheetIndex,
            cells: [mutation],
            oldStyles: stylesChanged ? oldStyles : nil,
            newStyles: stylesChanged ? workbook.styles : nil,
            oldStyleEdits: stylesChanged ? oldStyleEdits : nil,
            newStyleEdits: stylesChanged ? styleEdits : nil
        )
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
        workbook.sheets[selectedSheetIndex].maximumRow = max(
            workbook.sheets[selectedSheetIndex].maximumRow,
            address.row
        )
        workbook.sheets[selectedSheetIndex].maximumColumn = max(
            workbook.sheets[selectedSheetIndex].maximumColumn,
            address.column
        )
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
        let edit = ExcelCellEdit(
            input: input,
            styleIndex: styleIndex
        )
        return CellMutation(
            address: address,
            oldCell: sheet.cells[address],
            newCell: cell(
                address: address,
                input: input,
                styleIndex: styleIndex,
                workbook: styleSource
            ),
            oldEdit: edits[sheet.partPath]?[address],
            newEdit: edit
        )
    }

    /// Turns typed text into a cell input. Unambiguous dates such as
    /// `2024-03-05` become date serials with a date style so they display,
    /// sort, and calculate like dates entered in Excel. Cells formatted as
    /// text keep the literal.
    private func resolvedUserInput(
        _ userText: String,
        styleIndex: Int?,
        workbook: inout ExcelWorkbook
    ) -> (input: ExcelCellInput, styleIndex: Int?) {
        let input = ExcelCellInput(userText: userText)
        guard case .text(let text) = input,
              let serial = ExcelDateInput.serial(
                  fromUserText: text,
                  uses1904DateSystem: workbook.uses1904DateSystem
              ) else {
            return (input, styleIndex)
        }
        let currentFormat = ExcelNumberFormat.matching(
            workbook.style(at: styleIndex)
        )
        if currentFormat == .text {
            return (input, styleIndex)
        }
        let dateStyleIndex = currentFormat == .date
            ? styleIndex
            : self.styleIndex(
                for: .date,
                replacing: styleIndex,
                workbook: &workbook
            )
        return (.number(serial), dateStyleIndex)
    }

    private func cell(
        address: ExcelCellAddress,
        input: ExcelCellInput,
        styleIndex: Int?,
        workbook styleSource: ExcelWorkbook? = nil
    ) -> ExcelCell? {
        let workbook = styleSource ?? self.workbook
        switch input {
        case .blank:
            return nil
        case .text(let value):
            return ExcelCell(
                address: address,
                rawValue: value,
                displayValue: value,
                formula: nil,
                styleIndex: styleIndex,
                cellType: "inlineStr"
            )
        case .number(let value):
            let style = workbook?.style(at: styleIndex) ?? .plain
            return ExcelCell(
                address: address,
                rawValue: value,
                displayValue: ExcelValueFormatter.displayValue(
                    value,
                    type: nil,
                    style: style,
                    uses1904DateSystem:
                        workbook?.uses1904DateSystem ?? false
                ),
                formula: nil,
                styleIndex: styleIndex,
                cellType: nil
            )
        case .boolean(let value):
            return ExcelCell(
                address: address,
                rawValue: value ? "TRUE" : "FALSE",
                displayValue: value
                    ? AppLocalization.string("참")
                    : AppLocalization.string("거짓"),
                formula: nil,
                styleIndex: styleIndex,
                cellType: "b"
            )
        case .error(let value):
            return ExcelCell(
                address: address,
                rawValue: value,
                displayValue: value,
                formula: nil,
                styleIndex: styleIndex,
                cellType: "e"
            )
        case .formula(let formula):
            return ExcelCell(
                address: address,
                rawValue: "",
                displayValue: "=" + formula,
                formula: formula,
                styleIndex: styleIndex,
                cellType: nil
            )
        }
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
        let path = workbook.sheets[group.sheetIndex].partPath
        if let styles = forward ? group.newStyles : group.oldStyles {
            workbook.styles = styles
        }
        if let registry = forward
            ? group.newStyleEdits
            : group.oldStyleEdits {
            styleEdits = registry
        }
        if let styles = forward
            ? group.newDifferentialStyles
            : group.oldDifferentialStyles {
            workbook.differentialStyles = styles
        }
        if let registry = forward
            ? group.newDifferentialStyleEdits
            : group.oldDifferentialStyleEdits {
            differentialStyleEdits = registry
        }
        for mutation in group.cells {
            let cell = forward ? mutation.newCell : mutation.oldCell
            let edit = forward ? mutation.newEdit : mutation.oldEdit
            workbook.sheets[group.sheetIndex].cells[mutation.address] = cell
            if let edit {
                edits[path, default: [:]][mutation.address] = edit
            } else {
                edits[path]?[mutation.address] = nil
                if edits[path]?.isEmpty == true {
                    edits[path] = nil
                }
            }
        }
        if let rules = forward
            ? group.newDataValidations
            : group.oldDataValidations {
            workbook.sheets[group.sheetIndex].dataValidations = rules
            let original = originalDataValidations[path] ?? []
            if rules == original {
                validationEdits[path] = nil
            } else {
                validationEdits[path] = rules
            }
        }
        if let blocks = forward
            ? group.newConditionalFormatting
            : group.oldConditionalFormatting {
            workbook.sheets[group.sheetIndex].conditionalFormatting = blocks
            let original = originalConditionalFormatting[path] ?? []
            if blocks == original {
                conditionalFormattingEdits[path] = nil
            } else {
                conditionalFormattingEdits[path] = blocks
            }
        }
        if let annotations = forward
            ? group.newAnnotations
            : group.oldAnnotations {
            workbook.sheets[group.sheetIndex].annotations = annotations
            let original = originalAnnotations[path] ?? .empty
            if annotations == original {
                annotationEdits[path] = nil
            } else {
                annotationEdits[path] = annotations
            }
        }
        if let drawingObjects = forward
            ? group.newDrawingObjects
            : group.oldDrawingObjects {
            workbook.sheets[group.sheetIndex].drawingObjects = drawingObjects
            let original = originalDrawingObjects[path] ?? .empty
            if drawingObjects == original {
                drawingObjectEdits[path] = nil
            } else {
                drawingObjectEdits[path] = drawingObjects
            }
        }
        if let pivotTables = forward
            ? group.newPivotTables
            : group.oldPivotTables {
            workbook.sheets[group.sheetIndex].pivotTables = pivotTables
            workbook.sheets[group.sheetIndex]
                .drawingObjects.pivotTableCount = pivotTables.count
            let original = originalPivotTables[path] ?? []
            if pivotTables == original {
                pivotTableEdits[path] = nil
            } else {
                pivotTableEdits[path] = pivotTables
            }
        }
        if let tables = forward
            ? group.newTables
            : group.oldTables {
            workbook.sheets[group.sheetIndex].tables = tables
        }
        var effectiveGroup = group
        if forward, !group.cells.isEmpty, !isLargeWorkbook {
            let recalculated = Self.formulaRecalculationMutations(
                for: group,
                sheetIndex: group.sheetIndex,
                workbook: workbook,
                edits: edits
            )
            lastFormulaRecalculationCount = recalculated.mutations.count
            unsupportedFormulaCount = recalculated.unsupportedCount
            if !recalculated.mutations.isEmpty {
                for mutation in recalculated.mutations {
                    workbook.sheets[group.sheetIndex]
                        .cells[mutation.address] = mutation.newCell
                    if let edit = mutation.newEdit {
                        edits[path, default: [:]][mutation.address] = edit
                    }
                }
                effectiveGroup = replacingCells(
                    in: group,
                    with: mergedMutations(
                        primary: group.cells,
                        recalculated: recalculated.mutations
                    )
                )
            }
        } else if !forward {
            lastFormulaRecalculationCount = 0
        }
        if !group.cells.isEmpty, !isLargeWorkbook {
            lastFormulaRecalculationCount += refreshDerivedFormulaValues(
                excluding: group.sheetIndex,
                in: &workbook
            )
        }
        if forward {
            let populated = effectiveGroup.cells.compactMap {
                $0.newCell == nil ? nil : $0.address
            }
            if let maximumRow = populated.map(\.row).max() {
                workbook.sheets[group.sheetIndex].maximumRow = max(
                    workbook.sheets[group.sheetIndex].maximumRow,
                    maximumRow
                )
            }
            if let maximumColumn = populated.map(\.column).max() {
                workbook.sheets[group.sheetIndex].maximumColumn = max(
                    workbook.sheets[group.sheetIndex].maximumColumn,
                    maximumColumn
                )
            }
        }
        if registeringUndo {
            undoStack.append(effectiveGroup)
            redoStack.removeAll()
        }
        updateHistoryState()
        return effectiveGroup
    }

    private nonisolated static func formulaRecalculationMutations(
        for group: MutationGroup,
        sheetIndex: Int,
        workbook: ExcelWorkbook,
        edits: [String: [ExcelCellAddress: ExcelCellEdit]]
    ) -> (mutations: [CellMutation], unsupportedCount: Int) {
        let sheet = workbook.sheets[sheetIndex]
        let calculation = ExcelFormulaCalculator.recalculate(
            cells: sheet.cells,
            styles: workbook.styles,
            uses1904DateSystem: workbook.uses1904DateSystem,
            mergedRanges: sheet.mergedRanges,
            tableRanges: sheet.tables.map(\.range),
            workbook: workbook,
            currentSheetName: sheet.name
        )
        let directlyEdited = Set(group.cells.map(\.address))
        var mutations = calculation.values.sorted {
            $0.key < $1.key
        }.compactMap { address, result -> CellMutation? in
            let current = sheet.cells[address]
            let currentEdit = edits[sheet.partPath]?[address]
            if let formula = current?.formula, !formula.isEmpty {
                let spillRange = calculation.spillRanges[address]
                let valueChanged = current?.rawValue != result.rawValue
                    || current?.displayValue != result.displayValue
                    || current?.cellType != result.cellType
                    || current?.spillAnchor
                        != (spillRange == nil ? nil : address)
                    || current?.spillRange != spillRange
                let cachedValueChanged = directlyEdited.contains(address)
                    && (currentEdit?.cachedValue != result.cachedXMLValue
                        || currentEdit?.cachedType != result.cachedXMLType
                        || currentEdit?.formulaSpillRange != spillRange)
                guard valueChanged || cachedValueChanged else { return nil }
                var updated = current!
                updated.rawValue = result.rawValue
                updated.displayValue = result.displayValue
                updated.cellType = result.cellType
                updated.spillAnchor = spillRange == nil ? nil : address
                updated.spillRange = spillRange
                return CellMutation(
                    address: address,
                    oldCell: current,
                    newCell: updated,
                    oldEdit: currentEdit,
                    newEdit: ExcelCellEdit(
                        input: .formula(formula),
                        styleIndex: current?.styleIndex,
                        cachedValue: result.cachedXMLValue,
                        cachedType: result.cachedXMLType,
                        formulaSpillRange: spillRange
                    )
                )
            }
            guard let owner = calculation.spillOwners[address],
                  owner != address else { return nil }
            let styleIndex = current?.styleIndex
                ?? sheet.cells[owner]?.styleIndex
            let updated = ExcelCell(
                address: address,
                rawValue: result.rawValue,
                displayValue: result.displayValue,
                formula: nil,
                styleIndex: styleIndex,
                cellType: result.cellType,
                spillAnchor: owner,
                spillRange: nil
            )
            let valueChanged = current?.rawValue != updated.rawValue
                || current?.displayValue != updated.displayValue
                || current?.cellType != updated.cellType
                || current?.styleIndex != updated.styleIndex
                || current?.spillAnchor != owner
            guard valueChanged else { return nil }
            return CellMutation(
                address: address,
                oldCell: current,
                newCell: updated,
                oldEdit: currentEdit,
                newEdit: ExcelCellEdit(
                    input: spillInput(result),
                    styleIndex: styleIndex
                )
            )
        }
        for address in calculation.clearedSpillAddresses.sorted() {
            guard !calculation.values.keys.contains(address),
                  let current = sheet.cells[address] else { continue }
            mutations.append(CellMutation(
                address: address,
                oldCell: current,
                newCell: nil,
                oldEdit: edits[sheet.partPath]?[address],
                newEdit: ExcelCellEdit(
                    input: .blank,
                    styleIndex: current.styleIndex
                )
            ))
        }
        mutations.sort { $0.address < $1.address }
        return (mutations, calculation.unsupportedFormulaCount)
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
        var totalChanges = 0
        let maximumPasses = min(max(workbook.sheets.count, 1), 3)
        for _ in 0 ..< maximumPasses {
            var passChanges = 0
            for sheetIndex in workbook.sheets.indices
                where sheetIndex != excludedSheetIndex {
                let result = formulaRecalculationMutations(
                    for: MutationGroup(
                        sheetIndex: sheetIndex,
                        cells: []
                    ),
                    sheetIndex: sheetIndex,
                    workbook: workbook,
                    edits: edits
                )
                for mutation in result.mutations {
                    workbook.sheets[sheetIndex]
                        .cells[mutation.address] = mutation.newCell
                }
                passChanges += result.mutations.count
            }
            totalChanges += passChanges
            if passChanges == 0 { break }
        }
        return totalChanges
    }

    private nonisolated static func spillInput(
        _ value: ExcelFormulaCalculatedValue
    ) -> ExcelCellInput {
        switch value.cachedXMLType {
        case "b":
            return .boolean(value.cachedXMLValue == "1")
        case "e":
            return .error(value.cachedXMLValue)
        case "str":
            return .text(value.rawValue)
        default:
            return .number(value.cachedXMLValue)
        }
    }

    private func mergedMutations(
        primary: [CellMutation],
        recalculated: [CellMutation]
    ) -> [CellMutation] {
        var result = primary
        var indexes = Dictionary(
            uniqueKeysWithValues: primary.enumerated().map {
                ($0.element.address, $0.offset)
            }
        )
        for mutation in recalculated {
            if let index = indexes[mutation.address] {
                let original = result[index]
                result[index] = CellMutation(
                    address: mutation.address,
                    oldCell: original.oldCell,
                    newCell: mutation.newCell,
                    oldEdit: original.oldEdit,
                    newEdit: mutation.newEdit
                )
            } else {
                indexes[mutation.address] = result.count
                result.append(mutation)
            }
        }
        return result
    }

    private func replacingCells(
        in group: MutationGroup,
        with cells: [CellMutation]
    ) -> MutationGroup {
        MutationGroup(
            sheetIndex: group.sheetIndex,
            cells: cells,
            oldStyles: group.oldStyles,
            newStyles: group.newStyles,
            oldStyleEdits: group.oldStyleEdits,
            newStyleEdits: group.newStyleEdits,
            oldDifferentialStyles: group.oldDifferentialStyles,
            newDifferentialStyles: group.newDifferentialStyles,
            oldDifferentialStyleEdits:
                group.oldDifferentialStyleEdits,
            newDifferentialStyleEdits:
                group.newDifferentialStyleEdits,
            oldDataValidations: group.oldDataValidations,
            newDataValidations: group.newDataValidations,
            oldConditionalFormatting: group.oldConditionalFormatting,
            newConditionalFormatting: group.newConditionalFormatting,
            oldAnnotations: group.oldAnnotations,
            newAnnotations: group.newAnnotations,
            oldDrawingObjects: group.oldDrawingObjects,
            newDrawingObjects: group.newDrawingObjects,
            oldPivotTables: group.oldPivotTables,
            newPivotTables: group.newPivotTables
        )
    }

    private func coalescing(
        _ initial: MutationGroup,
        with latest: MutationGroup
    ) -> MutationGroup {
        let initialByAddress = Dictionary(
            uniqueKeysWithValues: initial.cells.map { ($0.address, $0) }
        )
        let latestByAddress = Dictionary(
            uniqueKeysWithValues: latest.cells.map { ($0.address, $0) }
        )
        let addresses = Set(initialByAddress.keys)
            .union(latestByAddress.keys)
            .sorted()
        let cells = addresses.compactMap { address -> CellMutation? in
            guard let first = initialByAddress[address]
                    ?? latestByAddress[address],
                  let last = latestByAddress[address]
                    ?? initialByAddress[address] else {
                return nil
            }
            return CellMutation(
                address: address,
                oldCell: first.oldCell,
                newCell: last.newCell,
                oldEdit: first.oldEdit,
                newEdit: last.newEdit
            )
        }
        return replacingCells(in: initial, with: cells)
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

    private func serializedEdits() -> [ExcelWorksheetEdits] {
        edits.map {
            ExcelWorksheetEdits(
                partPath: $0.key,
                cells: $0.value
            )
        }
    }

    private func serializedStyleEdits() -> [ExcelStyleEdit] {
        let referencedIndexes = Set(
            edits.values
                .flatMap(\.values)
                .compactMap(\.styleIndex)
        )
        guard let highestReferencedIndex = referencedIndexes
            .filter({ styleEdits[$0] != nil })
            .max() else {
            return []
        }
        return styleEdits.values
            .filter { $0.styleIndex <= highestReferencedIndex }
            .sorted { $0.styleIndex < $1.styleIndex }
    }

    private func serializedValidationEdits()
        -> [ExcelWorksheetValidationEdits] {
        validationEdits.map {
            ExcelWorksheetValidationEdits(
                partPath: $0.key,
                rules: $0.value
            )
        }
    }

    private func serializedConditionalFormattingEdits()
        -> [ExcelWorksheetConditionalFormattingEdits] {
        conditionalFormattingEdits.map {
            ExcelWorksheetConditionalFormattingEdits(
                partPath: $0.key,
                blocks: $0.value
            )
        }
    }

    private func serializedDifferentialStyleEdits()
        -> [ExcelDifferentialStyleEdit] {
        let referencedIndexes = Set(
            conditionalFormattingEdits.values
                .flatMap { $0 }
                .flatMap(\.rules)
                .map(\.differentialStyleIndex)
        )
        guard let highestReferencedIndex = referencedIndexes
            .filter({ differentialStyleEdits[$0] != nil })
            .max() else {
            return []
        }
        return differentialStyleEdits.values
            .filter { $0.styleIndex <= highestReferencedIndex }
            .sorted { $0.styleIndex < $1.styleIndex }
    }

    private func serializedAnnotationEdits()
        -> [ExcelWorksheetAnnotationEdits] {
        annotationEdits.map { partPath, annotations in
            let original = originalAnnotations[partPath] ?? .empty
            return ExcelWorksheetAnnotationEdits(
                partPath: partPath,
                annotations: annotations,
                writesHyperlinks: annotations.hyperlinks
                    != original.hyperlinks,
                writesNotes: annotations.notes != original.notes
                    || annotations.authors != original.authors
            )
        }
    }

    private func serializedDrawingEdits()
        -> [ExcelWorksheetDrawingEdits] {
        drawingObjectEdits.map { partPath, current in
            ExcelWorksheetDrawingEdits(
                partPath: partPath,
                original: originalDrawingObjects[partPath] ?? .empty,
                current: current
            )
        }
    }

    private func serializedPivotEdits()
        -> [ExcelWorksheetPivotEdits] {
        pivotTableEdits.map { partPath, current in
            ExcelWorksheetPivotEdits(
                partPath: partPath,
                original: originalPivotTables[partPath] ?? [],
                current: current
            )
        }
    }

    private func differentialStyleIndex(
        for style: ExcelDifferentialStyle,
        workbook: inout ExcelWorkbook
    ) -> Int {
        if let existing = workbook.differentialStyles.firstIndex(of: style) {
            return existing
        }
        let index = workbook.differentialStyles.count
        workbook.differentialStyles.append(style)
        differentialStyleEdits[index] = ExcelDifferentialStyleEdit(
            styleIndex: index,
            style: style
        )
        return index
    }

    private func normalizedDropdownValues(
        _ rawValues: [String]
    ) -> [String] {
        var seen = Set<String>()
        return rawValues.compactMap { rawValue in
            let value = rawValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !value.isEmpty,
                  seen.insert(value).inserted else {
                return nil
            }
            return value
        }
    }

    private func validationTargetAddresses(
        selection: ExcelCellAddress,
        toCurrentColumn: Bool,
        in sheet: ExcelWorksheet
    ) -> [ExcelCellAddress] {
        guard toCurrentColumn else {
            guard let range = selectedRange, range.cellCount <= 20000 else { return [selection] }
            return Array(Set(range.addresses.map { sheet.canonicalAddress(for: $0) })).sorted()
        }
        guard let region = ExcelAccessibilityAnalyzer
            .regions(in: sheet)
            .first(where: {
                $0.contains(selection)
                    && $0.columns.contains(where: {
                        $0.column == selection.column
                    })
            }) else {
            return []
        }
        return region.rowNumbers.map {
            ExcelCellAddress(row: $0, column: selection.column)
        }
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
        if ExcelNumberFormat.matching(
            workbook.style(at: currentStyleIndex)
        ) == format {
            return currentStyleIndex
        }
        let baseStyleIndex: Int?
        if let currentStyleIndex,
           let pendingStyle = styleEdits[currentStyleIndex] {
            baseStyleIndex = pendingStyle.baseStyleIndex
        } else {
            baseStyleIndex = currentStyleIndex
        }
        if let existing = styleEdits.values.first(where: {
            $0.baseStyleIndex == baseStyleIndex
                && $0.numberFormat == format
        }) {
            return existing.styleIndex
        }
        let baseStyle = workbook.style(at: baseStyleIndex)
        let newStyleIndex = workbook.styles.count
        var newStyle = baseStyle
        newStyle.numberFormatID = format.displayNumberFormatID
        newStyle.numberFormatCode = format.formatCode
        workbook.styles.append(newStyle)
        styleEdits[newStyleIndex] = ExcelStyleEdit(
            styleIndex: newStyleIndex,
            baseStyleIndex: baseStyleIndex,
            numberFormat: format
        )
        return newStyleIndex
    }

    private func input(preserving cell: ExcelCell) -> ExcelCellInput {
        if let formula = cell.formula,
           !formula.isEmpty {
            return .formula(formula)
        }
        if cell.cellType == "b" {
            return .boolean(
                cell.rawValue == "1"
                    || cell.rawValue.caseInsensitiveCompare("TRUE")
                        == .orderedSame
            )
        }
        if cell.cellType == nil || cell.cellType == "n",
           Double(cell.rawValue) != nil {
            return .number(cell.rawValue)
        }
        return .text(cell.rawValue)
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
        Array(
            Set(summary.populatedRows).union(
                largeAddedRows[summary.partPath] ?? []
            )
        ).sorted()
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
        status = AppLocalization.format(
            "%lld행부터 %lld행 구간을 불러오는 중…",
            visibleRows.first ?? 0,
            visibleRows.last ?? 0
        )
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
            status = AppLocalization.format(
                "%lld행부터 %lld행까지 표시합니다. 전체 데이터 행은 %lld개입니다.",
                visibleRows.first ?? 0,
                visibleRows.last ?? 0,
                allRows.count
            )
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
        guard let sheetEdits = edits[sheet.partPath] else {
            return
        }
        for (address, edit) in sheetEdits
            where includedRows.contains(address.row) {
            if edit.preservesExistingContent,
               var existing = sheet.cells[address] {
                existing.styleIndex = edit.styleIndex
                existing.displayValue = ExcelValueFormatter.displayValue(
                    existing.rawValue,
                    type: existing.cellType,
                    style: workbook?.style(at: edit.styleIndex) ?? .plain,
                    uses1904DateSystem:
                        workbook?.uses1904DateSystem ?? false
                )
                sheet.cells[address] = existing
            } else {
                sheet.cells[address] = cell(
                    address: address,
                    input: edit.input,
                    styleIndex: edit.styleIndex
                )
            }
            sheet.maximumRow = max(sheet.maximumRow, address.row)
            sheet.maximumColumn = max(sheet.maximumColumn, address.column)
        }
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
        switch input {
        case .blank:
            return ""
        case .text(let value), .number(let value), .error(let value):
            return value
        case .boolean(let value):
            return value ? "TRUE 참" : "FALSE 거짓"
        case .formula(let value):
            return value
        }
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
        guard row > 1 else {
            return sheet.cells[
                ExcelCellAddress(row: row, column: column)
            ]?.styleIndex
        }
        for candidateRow in stride(
            from: row - 1,
            through: max(1, row - 20),
            by: -1
        ) {
            if let style = sheet.cells[
                ExcelCellAddress(
                    row: candidateRow,
                    column: column
                )
            ]?.styleIndex {
                return style
            }
        }
        return nil
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
        var components = [
            AppLocalization.format(
                "%lld번째 데이터 행, 원본 %lld행",
                dataIndex + 1,
                row
            )
        ]
        let populated = region.columns.compactMap {
            column -> String? in
            let value = displayValue(
                row: row,
                column: column.column
            )
            guard !value.isEmpty else {
                return nil
            }
            let address = ExcelCellAddress(
                row: row,
                column: column.column
            )
            var metadata = ""
            if sheet.annotations.hyperlink(at: address) != nil {
                metadata += AppLocalization.string(", 하이퍼링크 있음")
            }
            if let note = sheet.annotations.note(at: address) {
                metadata += AppLocalization.format(
                    ", %@의 메모 %@",
                    note.author,
                    note.text
                )
            }
            if let formula = sheet.cell(at: address)?.formula,
               !formula.isEmpty {
                return AppLocalization.format(
                    "%@, %@, 수식 %@%@",
                    column.title,
                    value,
                    formula,
                    metadata
                )
            }
            return AppLocalization.format(
                "%@, %@%@",
                column.title,
                value,
                metadata
            )
        }
        components.append(contentsOf: populated)
        let emptyCount = region.columns.count - populated.count
        if emptyCount > 0 {
            components.append(
                AppLocalization.format(
                    "빈 항목 %lld개",
                    emptyCount
                )
            )
        }
        return components.joined(separator: ". ")
    }

    private func displayValue(
        row: Int,
        column: Int
    ) -> String {
        let address = sheet.canonicalAddress(
            for: ExcelCellAddress(
                row: row,
                column: column
            )
        )
        return sheet.cell(at: address)?.displayValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
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
        let rows = region.rowNumbers.filter { !sheet.hiddenRows.contains($0) }
        guard let visibleRows else { return rows }
        return rows.filter(visibleRows.contains)
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

// Chat batches use an isolated, memory-only editor. Nothing reaches the live
// workbook or file until every operation and the final XLSX export succeeds.
extension ExcelWorkbookViewModel {
    func applyAIWorkbookPlan(_ plan: ExcelAIValidatedPlan) async throws -> ExcelAIWorkbookApplyResult {
        guard !isSaving else { throw DocumentFileAccessError.savingInProgress }
        endEditorTextEditing()
        guard let original = workbook, let snapshot = makeAISnapshot(),
              snapshot.sheetPartPath == plan.sheetPartPath, snapshot.revision == plan.sourceRevision,
              !isLargeWorkbook, !plan.workbookOperations.isEmpty else { throw ExcelAIApplyError.staleProposal }
        let old = captureEditingState(original)
        let draft = ExcelWorkbookViewModel(fileURL: fileURL, writeContents: { _, _, _ in throw ExcelWorkbookDocumentError.cannotSave })
        draft.sourceData = sourceData
        var draftBook = original
        draft.restoreEditingState(old, workbook: &draftBook)
        draft.workbook = draftBook
        isSaving = true
        errorDescription = nil
        defer { isSaving = false }
        do {
            var messages: [String] = []
            var references: ExcelAIReferences?
            if !plan.edits.isEmpty || !plan.appendedRows.isEmpty || !plan.createdTables.isEmpty || !plan.actions.isEmpty {
                var legacy = plan
                legacy.workbookOperations = []
                try draft.applyAIPlan(legacy)
                messages.append(AppLocalization.format("%lld개 항목을 바꿨습니다.", legacy.changeCount))
                references = ExcelAIReferences.resolve(command: .init(intent: .edit, assistantMessage: "", edits: [], appendedRows: []), snapshot: snapshot, appliedPlan: legacy)
            }
            for operation in plan.workbookOperations {
                try Task.checkCancellation()
                let result = try await draft.executeAIWorkbookOperation(operation)
                messages.append(result.message)
                if let previous = references, operation.sheetID == previous.sheetPartPath || (operation.sheetID == "$current" && draft.selectedSheet?.partPath == previous.sheetPartPath),
                   operation.type == .insertTracks || operation.type == .deleteTracks {
                    let shift = ExcelStructureChange(axis: ExcelEditAxis(rawValue: operation.axis!)!, index: operation.index!, count: operation.count!, deleting: operation.type == .deleteTracks)
                    references = .init(sheetPartPath: previous.sheetPartPath, sheetName: previous.sheetName, addresses: previous.addresses.compactMap(shift.address))
                }
                if let actual = result.references {
                    let preceding = references?.sheetPartPath == actual.sheetPartPath ? references!.addresses : []
                    references = .init(sheetPartPath: actual.sheetPartPath, sheetName: actual.sheetName, addresses: Array(Set(preceding + actual.addresses)).sorted())
                }
                if let previous = references, let currentSheet = draft.selectedSheet, previous.sheetPartPath == currentSheet.partPath {
                    let addresses = Array(Set(previous.addresses.map { currentSheet.canonicalAddress(for: $0) })).sorted()
                    references = addresses.isEmpty ? nil : .init(sheetPartPath: currentSheet.partPath, sheetName: currentSheet.name, addresses: addresses)
                } else { references = nil }
            }
            try Task.checkCancellation()
            // Export validates drawing relationships and all other deferred XML.
            let data = try await draft.exportData()
            var finalBook = try await Task.detached(priority: .userInitiated) {
                var loaded = try ExcelWorkbookDocument.load(from: data)
                guard !loaded.sheets.contains(where: { $0.didTruncate || $0.isWindowed }) else { throw ExcelAIApplyError.rowLimitExceeded }
                _ = Self.refreshDerivedFormulaValues(in: &loaded, edits: [:])
                return loaded
            }.value
            try Task.checkCancellation()
            guard makeAISnapshot()?.revision == plan.sourceRevision else { throw ExcelAIApplyError.staleProposal }
            guard !draft.undoStack.isEmpty else { return .init(message: AppLocalization.string("변경할 내용이 없습니다."), references: nil) }
            draft.installEditingBase(data, workbook: finalBook)
            draft.workbook = finalBook
            let next = draft.captureEditingState(finalBook)
            restoreEditingState(next, workbook: &finalBook)
            workbook = finalBook
            navigationRevealAddress = selectedDrawingID == nil ? selectedAddress : nil
            findText = ""
            undoStack.append(MutationGroup(sheetIndex: selectedSheetIndex, cells: [], oldDocumentState: old, newDocumentState: next))
            redoStack.removeAll()
            if let sheet = selectedSheet {
                syncEditorText(using: sheet); updateValidationWarning(in: sheet); updateFormulaSupportSummary(in: sheet)
            }
            updateHistoryState()
            status = AppLocalization.string("채팅 요청을 적용했습니다. 실행 취소 한 번으로 되돌릴 수 있습니다.")
            return .init(message: messages.joined(separator: "\n"), references: references)
        } catch {
            status = error.localizedDescription
            throw error
        }
    }

    private func executeAIWorkbookOperation(_ op: ExcelAIWorkbookOperation) async throws -> ExcelAIWorkbookApplyResult {
        func require(_ success: Bool) throws {
            if !success { throw ExcelEditingError(status.isEmpty ? "요청한 작업을 적용하지 못했습니다." : status) }
        }
        guard let book = workbook else { throw ExcelAIApplyError.invalidTarget }
        let path = op.sheetID == "$current" ? selectedSheet?.partPath : op.sheetID
        guard let index = book.sheets.firstIndex(where: { $0.partPath == path }) else { throw ExcelAIApplyError.invalidTarget }
        if index != selectedSheetIndex { selectSheet(index) }
        guard let sheet = selectedSheet else { throw ExcelAIApplyError.invalidTarget }
        guard op.isSheetOperation || !sheet.protection.isEnabled else { throw ExcelAICommandValidationError.protectedWorksheet }
        status = ""
        let before = undoStack.count
        var highlighted: ExcelCellRange?
        var detail = op.range ?? ""
        var advanced: ExcelAdvancedEdit?
        let range = op.cellRange
        switch op.type {
        case .freezePanes:
            advanced = .freezePanes(.init(rows: op.rows!, columns: op.columns!))
            detail = AppLocalization.format("행 %lld개 · 열 %lld개", op.rows!, op.columns!)
        case .mergeCells: advanced = .merge(range!, center: op.center ?? false, discardOtherValues: false); highlighted = range
        case .unmergeCells: advanced = .unmerge(range!); highlighted = range?.includingMergedCells(in: sheet)
        case .insertTracks, .deleteTracks:
            advanced = .structure(.init(axis: ExcelEditAxis(rawValue: op.axis!)!, index: op.index!, count: op.count!, deleting: op.type == .deleteTracks))
            detail = "\(ExcelEditAxis(rawValue: op.axis!)!.title) \(op.index!)–\(op.index! + op.count! - 1)"
        case .resizeTracks:
            advanced = .resize(ExcelEditAxis(rawValue: op.axis!)!, op.index!...op.index! + op.count! - 1, op.size!)
            detail = "\(ExcelEditAxis(rawValue: op.axis!)!.title) \(op.index!)–\(op.index! + op.count! - 1) · \(op.size!)"
        case .formatCells: advanced = .format(range!, op.format!.basic); highlighted = range
        case .sortRange: advanced = .sort(range!, column: op.column!, ascending: op.ascending!, header: op.header!); highlighted = range
        case .filterRange: advanced = .filter(range!, column: op.column!, comparison: ExcelFilterComparison(rawValue: op.comparison!)!, query: op.value!); highlighted = range
        case .clearFilter: advanced = .clearFilter
        case .copyRange, .cutRange:
            let source = range!
            let values = (source.start.row...source.end.row).map { row in
                (source.start.column...source.end.column).map { column in
                    let cell = sheet.cells[.init(row: row, column: column)]
                    return ExcelClipboardValue(text: cell?.editText ?? "", styleIndex: cell?.styleIndex, input: cell.map { input(preserving: $0) } ?? .blank)
                }
            }
            let clipboard = ExcelRangeClipboard(range: source, sheetIndex: selectedSheetIndex, values: values, isCut: op.type == .cutRange, changeCount: 0)
            let destinationPath = op.destinationSheetID == "$current" ? sheet.partPath : (op.destinationSheetID ?? sheet.partPath)
            guard let targetSheet = book.sheets.firstIndex(where: { $0.partPath == destinationPath }), !book.sheets[targetSheet].protection.isEnabled else { throw ExcelAICommandValidationError.protectedWorksheet }
            if targetSheet != selectedSheetIndex { selectSheet(targetSheet) }
            let destination = ExcelCellAddress(op.destination!)!
            selectCell(destination)
            pasteSelection(using: clipboard)
            try require(undoStack.count > before)
            highlighted = .init(start: destination, end: .init(row: destination.row + values.count - 1, column: destination.column + values[0].count - 1))
            detail = "\(sheet.name)!\(source.reference) → \(selectedSheet!.name)!\(highlighted!.reference)"
        case .fillRange, .clearRange:
            selectRange(from: range!.start, to: range!.end)
            guard let effectiveRange = selectedRange, effectiveRange.cellCount <= 20_000 else { throw ExcelAICommandValidationError.tooManyChanges }
            if op.type == .fillRange { fillSelection(across: op.across!) } else { clearSelection() }
            // Already empty single cells and single-cell fills are valid no-ops.
            if undoStack.count == before && !status.isEmpty { throw ExcelEditingError(status) }
            highlighted = selectedRange
        case .setCellValue:
            let address = sheet.canonicalAddress(for: range!.start)
            try require(applyRangeUpdates([selectedSheetIndex: [address: .init(text: op.value!, styleIndex: sheet.cells[address]?.styleIndex)]]))
            highlighted = .init(start: address, end: address)
        case .replaceText:
            var updates: [ExcelCellAddress: ExcelClipboardValue] = [:]
            for address in range!.addresses {
                guard let cell = sheet.cells[address], cell.editText.range(of: op.value!, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { continue }
                let text = cell.editText.replacingOccurrences(of: op.value!, with: op.replacement!, options: [.caseInsensitive, .diacriticInsensitive])
                let literal = ["s", "str", "inlineStr"].contains(cell.cellType ?? "") && cell.formula == nil
                updates[address] = .init(text: text, styleIndex: cell.styleIndex, input: literal ? .text(text) : nil)
            }
            if !updates.isEmpty { try require(applyRangeUpdates([selectedSheetIndex: updates])) }
            let refs = ExcelAIReferences(sheetPartPath: sheet.partPath, sheetName: sheet.name, addresses: updates.keys.sorted())
            return .init(message: AppLocalization.format("%@ · %@: %lld셀을 바꿨습니다.", sheet.name, range!.reference, updates.count), references: updates.isEmpty ? nil : refs)
        case .addSheet, .duplicateSheet:
            let base = op.type == .addSheet ? AppLocalization.string("시트") : sheet.name
            let name = try ExcelSheetNames.validated(op.name ?? ExcelSheetNames.suggested(base: base, existing: book.sheets.map(\.name)), existing: book.sheets.map(\.name))
            try require(await performSheetEdit(op.type == .addSheet ? .add(name: name) : .duplicate(path: sheet.partPath, name: name)))
            selectedDrawingID = nil
            detail = op.type == .duplicateSheet ? "\(sheet.name) → \(name)" : name
        case .renameSheet:
            try require(await performSheetEdit(.rename(path: sheet.partPath, name: op.name!)))
            detail = "\(sheet.name) → \(selectedSheet!.name)"
        case .deleteSheet:
            try require(await performSheetEdit(.delete(path: sheet.partPath)))
            selectedDrawingID = nil; detail = sheet.name
        case .moveSheet:
            guard let position = op.position, (1...book.sheets.count).contains(position) else { throw ExcelAIApplyError.invalidTarget }
            var paths = book.sheets.map(\.partPath)
            paths.remove(at: index); paths.insert(sheet.partPath, at: position - 1)
            try require(await performSheetEdit(.reorder(paths: paths)))
            detail = "\(sheet.name) → \(position)"
        case .moveDrawing, .resizeDrawing, .deleteDrawing, .setImageDescription, .setChart:
            let image = sheet.drawingObjects.images.first { $0.id == op.drawingID }
            let chart = sheet.drawingObjects.charts.first { $0.id == op.drawingID }
            guard let anchor = image?.anchor ?? chart?.anchor, let id = op.drawingID else { throw ExcelAIApplyError.invalidTarget }
            let selection = ExcelDrawingSelection(id: id, sheetPath: sheet.partPath)
            detail = image?.name ?? chart!.title
            switch op.type {
            case .moveDrawing, .resizeDrawing:
                let next = try ExcelAIDrawingGeometry.applying(op, anchor: anchor, sheet: sheet)
                try require(updateDrawingPlacement(selection, expected: anchor, anchor: next))
                let rect = ExcelAIDrawingGeometry.grid(sheet: sheet).rect(for: next)!
                detail += " · \(next.start.reference) · \(Int(rect.width)) × \(Int(rect.height))"
                selectedDrawingID = id
            case .deleteDrawing:
                if image != nil { removeSheetImage(id: id) } else { removeSheetChart(id: id) }
                try require(undoStack.count > before); selectedDrawingID = nil
            case .setImageDescription:
                guard let image else { throw ExcelAIApplyError.invalidTarget }
                try require(updateSheetImageDescription(selection, name: op.name ?? image.name, alternativeText: op.value ?? image.alternativeText ?? ""))
                selectedDrawingID = id; detail = op.name ?? image.name
            case .setChart:
                try require(updateSheetChart(id: id, title: op.name!, kind: ExcelChartKind(rawValue: op.chartKind!)!, sourceReference: op.range!))
                selectedDrawingID = id; detail = "\(op.name!) · \(op.range!)"
            default: break
            }
        case .addChart:
            try require(addSheetChart(title: op.name!, kind: ExcelChartKind(rawValue: op.chartKind!)!, sourceReference: op.range!))
            selectedDrawingID = selectedSheetCharts.last?.id
            detail = "\(op.name!) · \(op.range!)"
        }
        if let advanced { try require(await performAdvancedEdit(advanced)) }
        let targetSheet = selectedSheet!
        let references = highlighted.map { ExcelAIReferences(sheetPartPath: targetSheet.partPath, sheetName: targetSheet.name, addresses: Array(Set($0.addresses.map { targetSheet.canonicalAddress(for: $0) })).sorted()) }
        let label = AppLocalization.string(op.type.label)
        let outcome = undoStack.count == before ? AppLocalization.string("변경할 내용이 없습니다.") : AppLocalization.string("적용했습니다.")
        return .init(message: "\(op.isSheetOperation ? "" : targetSheet.name + " · ")\(label)\(detail.isEmpty ? "" : " · " + detail): \(outcome)", references: references)
    }
}
