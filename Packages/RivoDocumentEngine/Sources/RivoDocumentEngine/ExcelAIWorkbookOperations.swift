import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public nonisolated struct ExcelAIWorkbookContext: Encodable, Sendable {
    public struct Sheet: Encodable, Sendable {
        public let id: String
        public let name: String
        public let position: Int
        public let protected: Bool
        public let frozenRows: Int
        public let frozenColumns: Int
    
    public init(id: String, name: String, position: Int, protected: Bool, frozenRows: Int, frozenColumns: Int) {
        self.id = id
        self.name = name
        self.position = position
        self.protected = protected
        self.frozenRows = frozenRows
        self.frozenColumns = frozenColumns
    }
}
    public struct Drawing: Encodable, Sendable {
        public let id: String
        public let sheetID: String
        public let name: String
        public let type: String
        public let startCell: String
        public let boundaryCell: String
        public let width: Double
        public let height: Double
        public let chartKind: String?
        public let sourceRange: String?
    
    public init(id: String, sheetID: String, name: String, type: String, startCell: String, boundaryCell: String, width: Double, height: Double, chartKind: String? = nil, sourceRange: String? = nil) {
        self.id = id
        self.sheetID = sheetID
        self.name = name
        self.type = type
        self.startCell = startCell
        self.boundaryCell = boundaryCell
        self.width = width
        self.height = height
        self.chartKind = chartKind
        self.sourceRange = sourceRange
    }
}
    public let sheets: [Sheet]
    public let selectedRange: String?
    public let selectedDrawingID: String?
    public let drawings: [Drawing]
    public let frozenRows: Int
    public let frozenColumns: Int
    public let structureProtected: Bool
    public let windowsProtected: Bool
    public let supportedOperations: [String]

    public static func make(workbook: ExcelWorkbook, selectedSheetIndex: Int, selectedRange: ExcelCellRange?, selectedDrawingID: String?, supportsEdits: Bool) -> Self {
        let sheet = workbook.sheets[selectedSheetIndex]
        var drawings: [Drawing] = []
        let sources = [sheet] + workbook.sheets.filter { $0.partPath != sheet.partPath }
        for source in sources {
            guard !source.isWindowed, drawings.count < 200, !source.drawingObjects.images.isEmpty || !source.drawingObjects.charts.isEmpty else { continue }
            let grid = ExcelAIDrawingGeometry.grid(sheet: source)
            for image in source.drawingObjects.images.sorted { ($0.id == selectedDrawingID ? 0 : 1) < ($1.id == selectedDrawingID ? 0 : 1) }.prefix(200 - drawings.count - (source.drawingObjects.charts.contains { $0.id == selectedDrawingID } ? 1 : 0)) {
                let anchor = grid.normalized(image.anchor), rect = grid.rect(for: anchor) ?? .zero
                drawings.append(.init(id: image.id, sheetID: source.partPath, name: image.name, type: "image", startCell: anchor.start.reference, boundaryCell: anchor.end.reference, width: rect.width, height: rect.height, chartKind: nil, sourceRange: nil))
            }
            for chart in source.drawingObjects.charts.sorted { ($0.id == selectedDrawingID ? 0 : 1) < ($1.id == selectedDrawingID ? 0 : 1) }.prefix(200 - drawings.count) {
                let anchor = grid.normalized(chart.anchor), rect = grid.rect(for: anchor) ?? .zero
                drawings.append(.init(id: chart.id, sheetID: source.partPath, name: chart.title, type: "chart", startCell: anchor.start.reference, boundaryCell: anchor.end.reference, width: rect.width, height: rect.height, chartKind: chart.kind.rawValue, sourceRange: chart.sourceRange?.reference))
            }
        }
        return .init(sheets: workbook.sheets.enumerated().map { .init(id: $0.element.partPath, name: $0.element.name, position: $0.offset + 1, protected: $0.element.protection.isEnabled, frozenRows: $0.element.frozenPanes.rows, frozenColumns: $0.element.frozenPanes.columns) },
                     selectedRange: selectedRange?.reference, selectedDrawingID: drawings.contains(where: { $0.id == selectedDrawingID && $0.sheetID == sheet.partPath }) ? selectedDrawingID : nil,
                     drawings: drawings, frozenRows: sheet.frozenPanes.rows, frozenColumns: sheet.frozenPanes.columns,
                     structureProtected: workbook.protection.lockStructure, windowsProtected: workbook.protection.lockWindows,
                     supportedOperations: supportsEdits && !workbook.sheets.contains(where: { $0.didTruncate || $0.isWindowed }) ? ExcelAIWorkbookOperation.Kind.allCases.map(\.rawValue) : [])
    }

    /// Session-local revision covers all sheets and objects, including changes
    /// that do not alter cell text (selection, merge, dimensions, format, tabs).
    public static func revision(workbook: ExcelWorkbook, selectedSheetIndex: Int, selectedRange: ExcelCellRange?, selectedDrawingID: String?) -> String {
        var hash = Hasher()
        hash.combine(selectedSheetIndex); hash.combine(selectedRange); hash.combine(selectedDrawingID)
        hash.combine(String(reflecting: workbook.protection))
        hash.combine(String(reflecting: workbook.definedNames))
        for style in workbook.styles {
            hash.combine(style.numberFormatID); hash.combine(style.numberFormatCode); hash.combine(style.isBold)
            hash.combine(style.fillARGB); hash.combine(style.horizontalAlignment); hash.combine(style.fontName); hash.combine(style.fontSize)
            hash.combine(style.fontARGB); hash.combine(style.isItalic); hash.combine(style.isUnderlined); hash.combine(style.wrapText)
            hash.combine(style.verticalAlignment); hash.combine(style.borderEdges)
        }
        for sheet in workbook.sheets {
            hash.combine(sheet.partPath); hash.combine(sheet.name); hash.combine(sheet.maximumRow); hash.combine(sheet.maximumColumn)
            for cell in sheet.cells.values.sorted(by: { $0.address < $1.address }) {
                hash.combine(cell.address); hash.combine(cell.rawValue); hash.combine(cell.formula); hash.combine(cell.cellType)
                hash.combine(cell.styleIndex); hash.combine(cell.spillAnchor); hash.combine(cell.spillRange)
            }
            hash.combine(sheet.mergedRanges); hash.combine(sheet.columnWidths); hash.combine(sheet.rowHeights)
            hash.combine(sheet.hiddenRows); hash.combine(sheet.filterRange); hash.combine(sheet.frozenPanes.rows); hash.combine(sheet.frozenPanes.columns)
            hash.combine(sheet.drawingObjects); hash.combine(sheet.annotations)
            hash.combine(String(reflecting: sheet.tables)); hash.combine(String(reflecting: sheet.dataValidations))
            hash.combine(String(reflecting: sheet.conditionalFormatting)); hash.combine(String(reflecting: sheet.protection))
            hash.combine(String(reflecting: sheet.pivotTables)); hash.combine(sheet.didTruncate); hash.combine(sheet.isWindowed)
        }
        return "workbook-v2-" + String(hash.finalize())
    }

    public init(sheets: [Sheet], selectedRange: String? = nil, selectedDrawingID: String? = nil, drawings: [Drawing], frozenRows: Int, frozenColumns: Int, structureProtected: Bool, windowsProtected: Bool, supportedOperations: [String]) {
        self.sheets = sheets
        self.selectedRange = selectedRange
        self.selectedDrawingID = selectedDrawingID
        self.drawings = drawings
        self.frozenRows = frozenRows
        self.frozenColumns = frozenColumns
        self.structureProtected = structureProtected
        self.windowsProtected = windowsProtected
        self.supportedOperations = supportedOperations
    }
}

public nonisolated struct ExcelAIWorkbookOperation: Decodable, Sendable {
    public enum Kind: String, CaseIterable, Decodable, Sendable {
        case freezePanes, mergeCells, unmergeCells
        case insertTracks, deleteTracks, resizeTracks, formatCells, sortRange, filterRange, clearFilter
        case copyRange, cutRange, fillRange, clearRange, replaceText, setCellValue
        case addSheet, renameSheet, duplicateSheet, deleteSheet, moveSheet
        case moveDrawing, resizeDrawing, deleteDrawing, setImageDescription, addChart, setChart
        public var label: String {
            switch self {
            case .freezePanes: return "틀 고정"
            case .mergeCells: return "셀 병합"
            case .unmergeCells: return "병합 해제"
            case .insertTracks: return "행·열 추가"
            case .deleteTracks: return "행·열 삭제"
            case .resizeTracks: return "행·열 크기"
            case .formatCells: return "셀 서식"
            case .sortRange: return "정렬"
            case .filterRange: return "필터"
            case .clearFilter: return "필터 해제"
            case .copyRange: return "복사"
            case .cutRange: return "잘라내기"
            case .fillRange: return "범위 채우기"
            case .clearRange: return "값 지우기"
            case .replaceText: return "찾아 바꾸기"
            case .setCellValue: return "셀 값 변경"
            case .addSheet: return "시트 추가"
            case .renameSheet: return "시트 이름 변경"
            case .duplicateSheet: return "시트 복제"
            case .deleteSheet: return "시트 삭제"
            case .moveSheet: return "시트 순서 변경"
            case .moveDrawing: return "개체 이동"
            case .resizeDrawing: return "개체 크기 변경"
            case .deleteDrawing: return "개체 삭제"
            case .setImageDescription: return "이미지 설명 변경"
            case .addChart: return "차트 추가"
            case .setChart: return "차트 수정"
            }
        }
    }
    public struct Format: Decodable, Sendable {
        public var fontName: String? = nil
        public var fontSize: Double? = nil
        public var bold: Bool? = nil
        public var italic: Bool? = nil
        public var underline: Bool? = nil
        public var textColor: String? = nil
        public var fillColor: String? = nil
        public var horizontal: String? = nil
        public var vertical: String? = nil
        public var wrap: Bool? = nil
        public var borders: String? = nil
        public var basic: ExcelBasicFormat { .init(fontName: fontName, fontSize: fontSize, bold: bold, italic: italic, underline: underline, textColor: textColor, fillColor: fillColor, horizontal: horizontal, vertical: vertical, wrap: wrap, borders: borders) }
        public var isEmpty: Bool { fontName == nil && fontSize == nil && bold == nil && italic == nil && underline == nil && textColor == nil && fillColor == nil && horizontal == nil && vertical == nil && wrap == nil && borders == nil }
    
    public init(fontName: String? = nil, fontSize: Double? = nil, bold: Bool? = nil, italic: Bool? = nil, underline: Bool? = nil, textColor: String? = nil, fillColor: String? = nil, horizontal: String? = nil, vertical: String? = nil, wrap: Bool? = nil, borders: String? = nil) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.textColor = textColor
        self.fillColor = fillColor
        self.horizontal = horizontal
        self.vertical = vertical
        self.wrap = wrap
        self.borders = borders
    }
}
    public let type: Kind
    public var sheetID: String? = nil
    public var range: String? = nil
    public var destination: String? = nil
    public var destinationSheetID: String? = nil
    public var name: String? = nil
    public var drawingID: String? = nil
    public var axis: String? = nil
    public var index: Int? = nil
    public var count: Int? = nil
    public var size: Double? = nil
    public var rows: Int? = nil
    public var columns: Int? = nil
    public var center: Bool? = nil
    public var discardOtherValues: Bool? = nil
    public var format: Format? = nil
    public var column: Int? = nil
    public var ascending: Bool? = nil
    public var header: Bool? = nil
    public var comparison: String? = nil
    public var value: String? = nil
    public var replacement: String? = nil
    public var across: Bool? = nil
    public var position: Int? = nil
    public var rowOffset: Int? = nil
    public var columnOffset: Int? = nil
    public var widthFactor: Double? = nil
    public var heightFactor: Double? = nil
    public var chartKind: String? = nil

    public var isSheetOperation: Bool { [.addSheet, .renameSheet, .duplicateSheet, .deleteSheet, .moveSheet].contains(type) }
    public var isDrawingOperation: Bool { [.moveDrawing, .resizeDrawing, .deleteDrawing, .setImageDescription, .setChart].contains(type) }
    public var cellRange: ExcelCellRange? { range.flatMap(ExcelCellRange.init) }

    public static func validate(_ operations: [Self], snapshot: ExcelAIWorkbookSnapshot, userRequest: String) throws -> [Self] {
        guard let context = snapshot.workbookContext, !context.supportedOperations.isEmpty, snapshot.localWorkbook != nil else { throw ExcelAICommandValidationError.editingUnavailable }
        guard operations.count <= 20 else { throw ExcelAICommandValidationError.tooManyChanges }
        var totalCells = 0
        return try operations.map { input in
            var op = input
            func require(_ condition: Bool) throws { if !condition { throw ExcelAICommandValidationError.invalidAction } }
            if op.range == "$selection" { op.range = context.selectedRange }
            op.sheetID = op.sheetID ?? snapshot.sheetPartPath
            try require(op.sheetID == "$current" || context.sheets.contains(where: { $0.id == op.sheetID }))
            if let destinationSheetID = op.destinationSheetID { try require(destinationSheetID == "$current" || context.sheets.contains(where: { $0.id == destinationSheetID })) }
            if let reference = op.range {
                guard let range = ExcelCellRange(reference), range.end.row <= 2000, range.end.column <= 200, range.cellCount <= 20_000 else { throw ExcelAICommandValidationError.tooManyChanges }
                totalCells += range.cellCount
                try require(totalCells <= 20_000)
                op.range = range.reference
            }
            if let destination = op.destination {
                guard let address = ExcelCellAddress(destination), address.row <= 2000, address.column <= 200 else { throw ExcelAICommandValidationError.invalidTarget }
                op.destination = address.reference
            }
            if op.isDrawingOperation {
                if op.drawingID == nil || op.drawingID == "$selected" { op.drawingID = context.selectedDrawingID }
                guard let drawing = context.drawings.first(where: { $0.id == op.drawingID && ($0.sheetID == op.sheetID || op.sheetID == "$current") }) else {
                    throw ExcelEditingError("편집할 이미지나 차트를 먼저 선택하거나 이름을 지정해 주세요.")
                }
                if op.type == .setChart { try require(drawing.type == "chart") }
                if op.type == .setImageDescription { try require(drawing.type == "image") }
            }
            switch op.type {
            case .freezePanes:
                try require(op.rows != nil && op.columns != nil)
                try require((0..<2000).contains(op.rows!) && (0..<200).contains(op.columns!))
            case .mergeCells, .unmergeCells, .clearRange: try require(op.cellRange != nil)
            case .insertTracks, .deleteTracks, .resizeTracks:
                try require(["row", "column"].contains(op.axis ?? ""))
                let maxIndex = op.axis == "row" ? 2000 : 200
                try require((1...maxIndex).contains(op.index ?? 0) && (1...maxIndex).contains(op.count ?? 0))
                try require(op.index! + op.count! - 1 <= maxIndex)
                if op.type == .resizeTracks { try require(op.size?.isFinite == true && op.size! > 0 && op.size! <= (op.axis == "row" ? 409 : 255)) }
            case .formatCells:
                try require(op.cellRange != nil && op.format != nil && !op.format!.isEmpty)
                let f = op.format!
                if let size = f.fontSize { try require(size.isFinite && (6...96).contains(size)) }
                if let name = f.fontName { try require(!name.isEmpty && name.count <= 100) }
                for color in [f.textColor, f.fillColor].compactMap({ $0 }) { try require(color.isEmpty || color.range(of: "^[A-Fa-f0-9]{8}$", options: .regularExpression) != nil) }
                if let h = f.horizontal { try require(["left", "center", "right"].contains(h)) }
                if let v = f.vertical { try require(["top", "center", "bottom"].contains(v)) }
                if let borders = f.borders { try require(["all", "outside", "none"].contains(borders)) }
            case .sortRange, .filterRange:
                guard let range = op.cellRange else { throw ExcelAICommandValidationError.invalidTarget }
                try require((range.start.column...range.end.column).contains(op.column ?? 0))
                if op.type == .sortRange { try require(op.ascending != nil && op.header != nil) }
                else { try require(ExcelFilterComparison(rawValue: op.comparison ?? "") != nil && op.value != nil) }
            case .clearFilter: break
            case .copyRange, .cutRange:
                try require(op.cellRange != nil && op.destination != nil)
                let range = op.cellRange!, target = ExcelCellAddress(op.destination!)!
                try require(target.row + range.end.row - range.start.row <= 2000 && target.column + range.end.column - range.start.column <= 200)
            case .fillRange: try require(op.cellRange != nil && op.across != nil)
            case .setCellValue: try require(op.cellRange?.cellCount == 1 && op.value != nil)
            case .replaceText: try require(op.cellRange != nil && op.value?.isEmpty == false && op.replacement != nil)
            case .addSheet, .duplicateSheet:
                if let name = op.name { _ = try ExcelSheetNames.validated(name, existing: []) }
            case .renameSheet: try require(op.name?.isEmpty == false)
            case .deleteSheet: break
            case .moveSheet: try require((1...64).contains(op.position ?? 0))
            case .moveDrawing:
                try require(op.destination != nil || op.rowOffset != nil || op.columnOffset != nil)
                try require((-2000...2000).contains(op.rowOffset ?? 0) && (-200...200).contains(op.columnOffset ?? 0))
            case .resizeDrawing:
                try require(op.widthFactor != nil || op.heightFactor != nil)
                for scale in [op.widthFactor, op.heightFactor].compactMap({ $0 }) { try require(scale.isFinite && (0.1...5).contains(scale)) }
            case .deleteDrawing: break
            case .setImageDescription: try require(op.name != nil || op.value != nil)
            case .addChart, .setChart:
                try require(op.cellRange != nil && ExcelChartKind(rawValue: op.chartKind ?? "")?.isEditable == true && op.name != nil)
            }
            for text in [op.name, op.value, op.replacement].compactMap({ $0 }) { try require(text.count <= 10_000) }
            if op.discardOtherValues == true {
                throw ExcelEditingError("값이 있는 여러 셀을 병합하려면 셀 도구의 병합 안내를 확인해 주세요. 아직 문서는 바꾸지 않았습니다.")
            }
            return op
        }
    }


    public init(type: Kind, sheetID: String? = nil, range: String? = nil, destination: String? = nil, destinationSheetID: String? = nil, name: String? = nil, drawingID: String? = nil, axis: String? = nil, index: Int? = nil, count: Int? = nil, size: Double? = nil, rows: Int? = nil, columns: Int? = nil, center: Bool? = nil, discardOtherValues: Bool? = nil, format: Format? = nil, column: Int? = nil, ascending: Bool? = nil, header: Bool? = nil, comparison: String? = nil, value: String? = nil, replacement: String? = nil, across: Bool? = nil, position: Int? = nil, rowOffset: Int? = nil, columnOffset: Int? = nil, widthFactor: Double? = nil, heightFactor: Double? = nil, chartKind: String? = nil) {
        self.type = type
        self.sheetID = sheetID
        self.range = range
        self.destination = destination
        self.destinationSheetID = destinationSheetID
        self.name = name
        self.drawingID = drawingID
        self.axis = axis
        self.index = index
        self.count = count
        self.size = size
        self.rows = rows
        self.columns = columns
        self.center = center
        self.discardOtherValues = discardOtherValues
        self.format = format
        self.column = column
        self.ascending = ascending
        self.header = header
        self.comparison = comparison
        self.value = value
        self.replacement = replacement
        self.across = across
        self.position = position
        self.rowOffset = rowOffset
        self.columnOffset = columnOffset
        self.widthFactor = widthFactor
        self.heightFactor = heightFactor
        self.chartKind = chartKind
    }
}

public nonisolated struct ExcelAIWorkbookApplyResult: Sendable {
    public let message: String
    public let references: ExcelAIReferences?

    public init(message: String, references: ExcelAIReferences? = nil) {
        self.message = message
        self.references = references
    }
}

public nonisolated enum ExcelAIDrawingGeometry {
    public static func grid(sheet: ExcelWorksheet) -> ExcelDrawingGrid {
        var x: CGFloat = 54, y: CGFloat = 42
        let columns = (1...200).map { column -> ExcelDrawingTrack in
            let width = min(max(CGFloat(sheet.columnWidths[column] ?? 14) * 7.2 + 12, 24), 1848)
            defer { x += width }
            return .init(index: column, origin: x, size: width, emuSize: ExcelDrawingGrid.columnEMUs(sheet.columnWidths[column] ?? 14))
        }
        let rows = (1...2000).map { row -> ExcelDrawingTrack in
            let height = min(max(CGFloat(sheet.rowHeights[row] ?? 30.35) * 1.45, 16), 600)
            defer { y += height }
            return .init(index: row, origin: y, size: height, emuSize: ExcelDrawingGrid.rowEMUs(sheet.rowHeights[row] ?? 30.35))
        }
        return .init(columns: columns, rows: rows, columnWidths: sheet.columnWidths, rowHeights: sheet.rowHeights)
    }
    public static func applying(_ op: ExcelAIWorkbookOperation, anchor: ExcelDrawingAnchor, sheet: ExcelWorksheet) throws -> ExcelDrawingAnchor {
        let grid = grid(sheet: sheet), normalized = grid.normalized(anchor)
        guard let original = grid.rect(for: normalized), grid.canManipulate(anchor) else { throw ExcelAICommandValidationError.invalidTarget }
        var rect = original
        if op.type == .moveDrawing {
            let start = op.destination.flatMap(ExcelCellAddress.init) ?? .init(row: normalized.start.row + (op.rowOffset ?? 0), column: normalized.start.column + (op.columnOffset ?? 0))
            guard let col = grid.columns.first(where: { $0.index == start.column }), let row = grid.rows.first(where: { $0.index == start.row }) else { throw ExcelAICommandValidationError.invalidTarget }
            rect.origin = CGPoint(x: col.origin + CGFloat(Double(normalized.fromOffset.x) / col.emuSize) * col.size,
                                  y: row.origin + CGFloat(Double(normalized.fromOffset.y) / row.emuSize) * row.size)
        } else {
            rect.size = CGSize(width: rect.width * (op.widthFactor ?? 1), height: rect.height * (op.heightFactor ?? 1))
        }
        guard rect.width >= 1, rect.height >= 1, grid.bounds.contains(rect), let result = grid.anchor(for: rect) else { throw ExcelAICommandValidationError.invalidTarget }
        return result
    }
}
