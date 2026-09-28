import Foundation

nonisolated struct ExcelBasicFormat: Sendable {
    var fontName: String?
    var fontSize: Double?
    var bold: Bool?
    var italic: Bool?
    var underline: Bool?
    var textColor: String?
    var fillColor: String?
    var horizontal: String?
    var vertical: String?
    var wrap: Bool?
    var borders: String?
}

nonisolated enum ExcelFilterComparison: String, CaseIterable, Identifiable, Sendable {
    case contains, equals, greater, less
    var id: String { rawValue }
    var title: String {
        switch self {
        case .contains: return AppLocalization.string("포함")
        case .equals: return AppLocalization.string("같음")
        case .greater: return AppLocalization.string("보다 큼")
        case .less: return AppLocalization.string("보다 작음")
        }
    }
    func matches(_ value: String, query: String) -> Bool {
        switch self {
        case .contains: return value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        case .equals: return value.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        case .greater, .less:
            guard let a = Double(value.replacingOccurrences(of: ",", with: "")), let b = Double(query.replacingOccurrences(of: ",", with: "")) else { return false }
            return self == .greater ? a > b : a < b
        }
    }
}

nonisolated enum ExcelAdvancedEdit: Sendable {
    case structure(ExcelStructureChange)
    case resize(ExcelEditAxis, ClosedRange<Int>, Double)
    case format(ExcelCellRange, ExcelBasicFormat)
    case sort(ExcelCellRange, column: Int, ascending: Bool, header: Bool)
    case filter(ExcelCellRange, column: Int, comparison: ExcelFilterComparison, query: String)
    case clearFilter
    case merge(ExcelCellRange, center: Bool, discardOtherValues: Bool = false)
    case unmerge(ExcelCellRange)
    case freezePanes(ExcelFrozenPanes)
}

nonisolated struct ExcelEditingError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { AppLocalization.string(message) }
}

nonisolated enum ExcelAdvancedWorkbookEditing {
    typealias Node = ExcelEditingXML.Node
    static func applying(_ edit: ExcelAdvancedEdit, to data: Data, workbook: ExcelWorkbook, sheetIndex: Int) throws -> Data {
        guard workbook.sheets.indices.contains(sheetIndex) else { throw ExcelWorkbookDocumentError.cannotSave }
        let sheet = workbook.sheets[sheetIndex]
        guard !sheet.protection.isEnabled, !sheet.didTruncate, !sheet.isWindowed else {
            throw ExcelEditingError("보호된 시트나 대용량 시트에서는 이 편집을 사용할 수 없습니다.")
        }
        let reader = try ExcelArchiveReader(data: data)
        let root = try ExcelEditingXML.parse(reader.data(at: sheet.partPath))
        var replacements: [String: Data] = [:]
        switch edit {
        case .freezePanes(let panes):
            guard !workbook.protection.lockWindows else { throw ExcelEditingError("창 구성이 보호된 문서는 틀 고정을 바꿀 수 없습니다.") }
            try panes.write(to: root)
        case let .merge(requested, center, discardOtherValues):
            let plan = try ExcelCellMergePlan(range: requested, sheet: sheet)
            guard discardOtherValues || plan.discardedAddresses.isEmpty else {
                throw ExcelEditingError("병합하면 왼쪽 위 셀을 제외한 값이 지워집니다. 병합 안내를 확인해 주세요.")
            }
            // Materialize shared formulas before clearing a possible group anchor.
            // Followers outside the merged range must remain valid formulas.
            for cell in root.child("sheetData")?.descendants("c") ?? [] {
                if let formula = cell.child("f"), formula.attributes["t"] == "shared" {
                    guard let address = ExcelCellAddress(cell.attributes["r"] ?? ""), let expanded = sheet.cells[address]?.formula, !expanded.isEmpty else {
                        throw ExcelEditingError("공유 수식을 읽을 수 없어 병합하지 못했습니다.")
                    }
                    formula.attributes = [:]; formula.text = expanded
                }
            }
            for cell in root.child("sheetData")?.descendants("c") ?? [] {
                guard let address = ExcelCellAddress(cell.attributes["r"] ?? ""), plan.range.contains(address), address != plan.range.start else { continue }
                cell.remove("f"); cell.remove("v"); cell.remove("is")
                cell.attributes["t"] = nil
                cell.attributes["cm"] = nil; cell.attributes["vm"] = nil
            }
            let merges = root.child("mergeCells") ?? root.make("mergeCells")
            if root.child("mergeCells") == nil {
                insert(merges, in: root, before: ["phoneticPr", "conditionalFormatting", "dataValidations", "hyperlinks", "printOptions", "pageMargins", "pageSetup", "headerFooter", "rowBreaks", "colBreaks", "customProperties", "cellWatches", "ignoredErrors", "smartTags", "drawing", "legacyDrawing", "legacyDrawingHF", "picture", "oleObjects", "controls", "webPublishItems", "tableParts", "extLst"])
            }
            merges.children.removeAll { $0.attributes["ref"].flatMap(ExcelCellRange.init).map(plan.range.intersects) == true }
            merges.children.append(merges.make("mergeCell", ["ref": plan.range.reference]))
            merges.attributes["count"] = String(merges.elements("mergeCell").count)
            // Keep a physical anchor even for a completely blank merged range.
            _ = ensureCell(plan.range.start, in: root)
            if center {
                let styles = try ExcelEditingXML.parse(reader.data(at: "xl/styles.xml"))
                var format = ExcelBasicFormat(); format.horizontal = "center"
                try applyFormat(format, range: ExcelCellRange(start: plan.range.start, end: plan.range.start), root: root, styles: styles)
                replacements["xl/styles.xml"] = ExcelEditingXML.data(styles)
            }
        case let .unmerge(range):
            try validate(range)
            guard let merges = root.child("mergeCells"), sheet.mergedRanges.contains(where: range.intersects) else {
                throw ExcelEditingError("선택한 범위에 병합된 셀이 없습니다.")
            }
            merges.children.removeAll { $0.attributes["ref"].flatMap(ExcelCellRange.init).map(range.intersects) == true }
            if merges.elements("mergeCell").isEmpty { root.remove("mergeCells") }
            else { merges.attributes["count"] = String(merges.elements("mergeCell").count) }
        case .structure(let change):
            try changeStructure(change, root: root, sheet: sheet, workbook: workbook, reader: reader, replacements: &replacements)
            if sheet.frozenPanes.isEnabled { try sheet.frozenPanes.shifted(by: change).write(to: root) }
        case let .resize(axis, indices, value):
            guard value.isFinite, value > 0, value <= (axis == .row ? 409 : 255), indices.count <= 2000 else { throw ExcelEditingError("행 높이 또는 열 너비를 확인해 주세요.") }
            if axis == .row {
                for index in indices {
                    let row = ensureRow(index, in: root)
                    row.attributes["ht"] = String(value); row.attributes["customHeight"] = "1"
                }
            } else {
                let cols = root.child("cols") ?? root.make("cols")
                if root.child("cols") == nil { insert(cols, in: root, before: ["sheetData"]) }
                // Split existing spans before changing individual columns.
                var values: [Int: Node] = [:]
                for col in cols.elements("col") {
                    guard let lo = Int(col.attributes["min"] ?? ""), let hi = Int(col.attributes["max"] ?? ""), lo > 0, hi <= 16384, lo <= hi else { continue }
                    for index in lo ... hi { let item = col.copy(); item.attributes["min"] = String(index); item.attributes["max"] = String(index); values[index] = item }
                }
                for index in indices {
                    let col = values[index] ?? cols.make("col", ["min": String(index), "max": String(index)])
                    col.attributes["width"] = String(value); col.attributes["customWidth"] = "1"; values[index] = col
                }
                cols.children = values.keys.sorted().compactMap { values[$0] }
            }
        case let .format(range, format):
            try validate(range)
            let styles = try ExcelEditingXML.parse(reader.data(at: "xl/styles.xml"))
            try applyFormat(format, range: range, root: root, styles: styles)
            replacements["xl/styles.xml"] = ExcelEditingXML.data(styles)
        case let .sort(range, column, ascending, header):
            try validate(range)
            guard (range.start.column ... range.end.column).contains(column) else { throw ExcelEditingError("정렬할 열이 선택 범위 안에 있어야 합니다.") }
            guard !sheet.mergedRanges.contains(where: { overlaps($0, range) }), !sheet.cells.values.contains(where: { range.contains($0.address) && $0.spillAnchor != nil }) else {
                throw ExcelEditingError("병합 셀이나 배열 수식이 포함된 범위는 정렬할 수 없습니다.")
            }
            let first = range.start.row + (header ? 1 : 0)
            guard first < range.end.row else { throw ExcelEditingError("정렬할 데이터 행을 두 개 이상 선택해 주세요.") }
            let order = Array(first ... range.end.row).sorted { lhs, rhs in
                let a = sheet.cells[ExcelCellAddress(row: lhs, column: column)]?.rawValue ?? ""
                let b = sheet.cells[ExcelCellAddress(row: rhs, column: column)]?.rawValue ?? ""
                if a == b { return lhs < rhs }
                if a.isEmpty { return false }; if b.isEmpty { return true }
                let comparison: ComparisonResult
                if let x = Double(a), let y = Double(b) { comparison = x == y ? .orderedSame : x < y ? .orderedAscending : .orderedDescending }
                else { comparison = a.compare(b, options: [.caseInsensitive, .numeric, .diacriticInsensitive]) }
                if comparison == .orderedSame { return lhs < rhs }
                return comparison == (ascending ? .orderedAscending : .orderedDescending)
            }
            let destinations = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, first + $0.offset) })
            let filterHidden = Set((root.child("sheetData")?.elements("row") ?? []).compactMap { row -> Int? in
                guard row.attributes["vc:filterHidden"] == "1", let number = Int(row.attributes["r"] ?? ""), destinations[number] != nil else { return nil }
                row.attributes["hidden"] = nil; row.attributes["vc:filterHidden"] = nil
                return number
            })
            for sourceRow in filterHidden {
                let row = ensureRow(destinations[sourceRow]!, in: root)
                row.attributes["hidden"] = "1"; row.attributes["vc:filterHidden"] = "1"
            }
            var moved: [Node] = []
            for row in root.child("sheetData")?.elements("row") ?? [] {
                row.children.removeAll { cell in
                    guard cell.localName == "c", let address = ExcelCellAddress(cell.attributes["r"] ?? ""), range.contains(address), let destinationRow = destinations[address.row] else { return false }
                    let copy = cell.copy()
                    let target = ExcelCellAddress(row: destinationRow, column: address.column)
                    copy.attributes["r"] = target.reference
                    if let formula = sheet.cells[address]?.formula {
                        let f = copy.ensure("f"); f.attributes = [:]; f.text = ExcelFormulaReferenceEditing.copied(formula, from: address, to: target)
                        copy.remove("v")
                    }
                    moved.append(copy); return true
                }
            }
            for cell in moved { let address = ExcelCellAddress(cell.attributes["r"]!)!; ensureRow(address.row, in: root).children.append(cell) }
            for link in root.descendants("hyperlink") {
                if let address = ExcelCellAddress(link.attributes["ref"] ?? ""), range.contains(address), let row = destinations[address.row] { link.attributes["ref"] = ExcelCellAddress(row: row, column: address.column).reference }
            }
            // Notes are stored in a related part, not in sheetData.
            for path in try relatedPaths(of: sheet.partPath, reader: reader) where path.contains("comments") && path.hasSuffix(".xml") {
                let comments = try ExcelEditingXML.parse(reader.data(at: path))
                for comment in comments.descendants("comment") {
                    if let address = ExcelCellAddress(comment.attributes["ref"] ?? ""), range.contains(address), let row = destinations[address.row] { comment.attributes["ref"] = ExcelCellAddress(row: row, column: address.column).reference }
                }
                replacements[path] = ExcelEditingXML.data(comments)
            }
        case let .filter(range, column, comparison, query):
            try validate(range)
            guard range.end.row > range.start.row, (range.start.column ... range.end.column).contains(column) else { throw ExcelEditingError("머리글과 데이터 행을 포함한 필터 범위를 선택해 주세요.") }
            clearFilter(in: root)
            root.attributes["vc:managedFilter"] = "1"
            root.attributes["xmlns:vc"] = "https://rivo.net/spreadsheet/2026"
            root.attributes["xmlns:mc"] = "http://schemas.openxmlformats.org/markup-compatibility/2006"
            let ignored = root.attributes["mc:Ignorable"] ?? ""
            root.attributes["mc:Ignorable"] = ignored.split(separator: " ").contains("vc") ? ignored : (ignored + " vc").trimmingCharacters(in: .whitespaces)
            let filter = root.make("autoFilter", ["ref": range.reference])
            let columnNode = filter.make("filterColumn", ["colId": String(column - range.start.column)])
            let custom = columnNode.make("customFilters")
            let escaped = query.replacingOccurrences(of: "~", with: "~~").replacingOccurrences(of: "*", with: "~*").replacingOccurrences(of: "?", with: "~?")
            let op = comparison == .greater ? "greaterThan" : comparison == .less ? "lessThan" : "equal"
            custom.children = [custom.make("customFilter", ["operator": op, "val": comparison == .contains ? "*" + escaped + "*" : query])]
            columnNode.children = [custom]; filter.children = [columnNode]
            insert(filter, in: root, before: ["sortState", "dataConsolidate", "customSheetViews", "mergeCells", "phoneticPr", "conditionalFormatting", "dataValidations", "hyperlinks", "printOptions", "pageMargins", "pageSetup", "headerFooter", "drawing", "tableParts", "extLst"])
            for index in (range.start.row + 1) ... range.end.row {
                let value = sheet.cells[ExcelCellAddress(row: index, column: column)]?.rawValue ?? ""
                if !comparison.matches(value, query: query) {
                    let row = ensureRow(index, in: root)
                    if row.attributes["hidden"] != "1" { row.attributes["vc:filterHidden"] = "1"; row.attributes["hidden"] = "1" }
                }
            }
            root.ensure("sheetPr").attributes["filterMode"] = "1"
        case .clearFilter: clearFilter(in: root)
        }
        normalizeSheet(root)
        replacements[sheet.partPath] = ExcelEditingXML.data(root)
        let workbookRoot = try ExcelEditingXML.parse(replacements["xl/workbook.xml"] ?? reader.data(at: "xl/workbook.xml"))
        let calc = workbookRoot.ensure("calcPr")
        calc.attributes["fullCalcOnLoad"] = "1"; calc.attributes["forceFullCalc"] = "1"
        replacements["xl/workbook.xml"] = ExcelEditingXML.data(workbookRoot)
        // Let Excel rebuild its calculation chain after edits.
        var removedPaths: Set<String> = []
        if reader.contains("xl/calcChain.xml") {
            removedPaths.insert("xl/calcChain.xml")
            let relationships = try ExcelEditingXML.parse(reader.data(at: "xl/_rels/workbook.xml.rels"))
            relationships.children.removeAll { $0.attributes["Type"]?.hasSuffix("/calcChain") == true }
            replacements["xl/_rels/workbook.xml.rels"] = ExcelEditingXML.data(relationships)
            let types = try ExcelEditingXML.parse(reader.data(at: "[Content_Types].xml"))
            types.children.removeAll { $0.attributes["PartName"] == "/xl/calcChain.xml" }
            replacements["[Content_Types].xml"] = ExcelEditingXML.data(types)
        }
        return try reader.repack(replacing: replacements, removing: removedPaths)
    }

    private static func validate(_ range: ExcelCellRange) throws {
        guard range.start.row > 0, range.start.column > 0, range.end.row <= 1048576, range.end.column <= 16384,
              (range.end.row - range.start.row + 1) * (range.end.column - range.start.column + 1) <= 20000 else {
            throw ExcelEditingError("한 번에 편집할 범위는 20,000셀 이하로 선택해 주세요.")
        }
    }
    private static func overlaps(_ a: ExcelCellRange, _ b: ExcelCellRange) -> Bool {
        a.start.row <= b.end.row && b.start.row <= a.end.row && a.start.column <= b.end.column && b.start.column <= a.end.column
    }
    static func ensureRow(_ index: Int, in root: Node) -> Node {
        let data = root.ensure("sheetData")
        if let row = data.elements("row").first(where: { $0.attributes["r"] == String(index) }) { return row }
        let row = data.make("row", ["r": String(index)]); data.children.append(row); return row
    }
    static func ensureCell(_ address: ExcelCellAddress, in root: Node) -> Node {
        let row = ensureRow(address.row, in: root)
        if let cell = row.elements("c").first(where: { $0.attributes["r"] == address.reference }) { return cell }
        let cell = row.make("c", ["r": address.reference]); row.children.append(cell); return cell
    }
    private static func insert(_ node: Node, in root: Node, before names: Set<String>) {
        root.children.insert(node, at: root.children.firstIndex(where: { names.contains($0.localName) }) ?? root.children.count)
    }
    private static func normalizeSheet(_ root: Node) {
        guard let data = root.child("sheetData") else { return }
        for row in data.elements("row") {
            row.attributes["spans"] = nil
            row.children = row.elements("c").sorted { (ExcelCellAddress($0.attributes["r"] ?? "")?.column ?? 0) < (ExcelCellAddress($1.attributes["r"] ?? "")?.column ?? 0) } + row.children.filter { $0.localName != "c" && $0.name != "#text" }
        }
        data.children = data.elements("row").sorted { (Int($0.attributes["r"] ?? "") ?? 0) < (Int($1.attributes["r"] ?? "") ?? 0) }
        let addresses = data.descendants("c").compactMap { ExcelCellAddress($0.attributes["r"] ?? "") }
            + root.descendants("mergeCell").compactMap { $0.attributes["ref"].flatMap(ExcelCellRange.init)?.end }
        let last = ExcelCellAddress(row: addresses.map(\.row).max() ?? 1, column: addresses.map(\.column).max() ?? 1)
        root.child("dimension")?.attributes["ref"] = "A1:" + last.reference
        if let pr = root.child("sheetPr") { root.children.removeAll { $0 === pr }; root.children.insert(pr, at: 0) }
    }
    private static func clearFilter(in root: Node) {
        let hadFilter = root.child("autoFilter") != nil
        let previousRange = root.child("autoFilter")?.attributes["ref"].flatMap(ExcelCellRange.init)
        let rows = root.child("sheetData")?.elements("row") ?? []
        let managed = root.attributes["vc:managedFilter"] == "1" || rows.contains { $0.attributes["vc:filterHidden"] != nil }
        root.attributes["vc:managedFilter"] = nil
        for row in rows {
            if row.attributes["vc:filterHidden"] == "1" { row.attributes["hidden"] = nil; row.attributes["vc:filterHidden"] = nil }
            else if !managed, let range = previousRange, let index = Int(row.attributes["r"] ?? ""), index > range.start.row, index <= range.end.row { row.attributes["hidden"] = nil }
        }
        root.remove("autoFilter")
        if hadFilter { root.child("sheetPr")?.attributes["filterMode"] = nil }
    }

    private static func relatedPaths(of path: String, reader: ExcelArchiveReader) throws -> Set<String> {
        let url = URL(fileURLWithPath: "/" + path)
        let rel = url.deletingLastPathComponent().appendingPathComponent("_rels").appendingPathComponent(url.lastPathComponent + ".rels").path.dropFirst()
        guard reader.contains(String(rel)) else { return [] }
        let root = try ExcelEditingXML.parse(reader.data(at: String(rel)))
        return Set(root.elements("Relationship").compactMap {
            guard $0.attributes["TargetMode"] != "External", let target = $0.attributes["Target"] else { return nil }
            return String(URL(fileURLWithPath: target, relativeTo: url.deletingLastPathComponent()).standardized.path.dropFirst())
        })
    }

    private static func changeStructure(_ change: ExcelStructureChange, root: Node, sheet: ExcelWorksheet, workbook: ExcelWorkbook, reader: ExcelArchiveReader, replacements: inout [String: Data]) throws {
        let maximum = change.axis == .row ? 1048576 : 16384
        guard change.count > 0, change.count <= 1000, change.index > 0, change.index + change.count - 1 <= maximum else { throw ExcelEditingError("삽입·삭제할 위치와 개수를 확인해 주세요.") }
        let populatedMaximum = change.axis == .row ? sheet.maximumRow : sheet.maximumColumn
        guard change.deleting || populatedMaximum < change.index || populatedMaximum + change.count <= maximum else { throw ExcelEditingError("엑셀의 최대 행·열 범위를 넘습니다.") }
        if sheet.cells.values.contains(where: { $0.spillAnchor != nil }) {
            throw ExcelEditingError("배열 수식이 있는 시트의 행·열 삽입과 삭제는 아직 지원하지 않습니다.")
        }
        // Avoid partially rewriting 3-D references or whole-row/column references.
        let formulas = workbook.sheets.flatMap { $0.cells.values.compactMap(\.formula) } + workbook.definedNames.map(\.formula)
        if formulas.contains(where: { $0.range(of: #"(?:\$?[A-Za-z]{1,3}:\$?[A-Za-z]{1,3}|\$?[0-9]+:\$?[0-9]+|[^\s+*/()]+:[^\s+*/()]+!)"#, options: .regularExpression) != nil }) {
            throw ExcelEditingError("전체 행·열 참조나 여러 시트 참조가 있는 문서는 구조 변경을 아직 지원하지 않습니다.")
        }
        let tablePaths = Set(sheet.tables.map(\.partPath))
        let related = try relatedPaths(of: sheet.partPath, reader: reader)
        for table in sheet.tables {
            guard let updated = change.range(table.range), updated.end.column >= updated.start.column,
                  !(change.deleting && change.axis == .row && (change.index ..< change.index + change.count).contains(table.range.start.row)) else {
                throw ExcelEditingError("표의 머리글이나 표 전체를 삭제하는 작업은 지원하지 않습니다.")
            }
        }
        for path in reader.paths.sorted() where path.hasSuffix(".xml") && (path.hasPrefix("xl/worksheets/") || path == "xl/workbook.xml" || path.hasPrefix("xl/charts/") || tablePaths.contains(path) || related.contains(path) || path.hasPrefix("xl/pivotCache/")) {
            let node = path == sheet.partPath ? root : try ExcelEditingXML.parse(reader.data(at: path))
            let localSheet = workbook.sheets.first(where: { $0.partPath == path })?.name ?? (tablePaths.contains(path) ? sheet.name : nil)
            if path == sheet.partPath || tablePaths.contains(path), change.axis == .column {
                for filter in node.descendants("autoFilter") {
                    guard let ref = filter.attributes["ref"], let before = ExcelCellRange(ref), let after = change.range(before) else { continue }
                    filter.children.removeAll { item in
                        guard item.localName == "filterColumn", let offset = Int(item.attributes["colId"] ?? "") else { return false }
                        guard let position = change.position(before.start.column + offset) else { return true }
                        item.attributes["colId"] = String(position - after.start.column)
                        return false
                    }
                }
            }
            if let originalSheet = workbook.sheets.first(where: { $0.partPath == path }) {
                for cell in node.descendants("c") {
                    if let address = ExcelCellAddress(cell.attributes["r"] ?? ""), let formula = originalSheet.cells[address]?.formula, let f = cell.child("f") {
                        f.text = formula
                        if f.attributes["t"] == "shared" { f.attributes = [:] }
                    }
                }
            }
            if path == sheet.partPath {
                for row in node.child("sheetData")?.elements("row") ?? [] {
                    row.children.removeAll { cell in
                        guard cell.localName == "c", let address = ExcelCellAddress(cell.attributes["r"] ?? "") else { return false }
                        guard let next = change.address(address) else { return true }
                        cell.attributes["r"] = next.reference; return false
                    }
                }
                if change.axis == .row {
                    node.child("sheetData")?.children.removeAll { row in
                        guard row.localName == "row", let value = Int(row.attributes["r"] ?? "") else { return false }
                        guard let next = change.position(value) else { return true }
                        row.attributes["r"] = String(next); return false
                    }
                } else {
                    node.child("cols")?.children.removeAll { col in
                        guard col.localName == "col", let lo = Int(col.attributes["min"] ?? ""), let hi = Int(col.attributes["max"] ?? "") else { return false }
                        guard let range = change.interval(lo, hi) else { return true }
                        col.attributes["min"] = String(range.lowerBound); col.attributes["max"] = String(range.upperBound); return false
                    }
                }
            }
            if tablePaths.contains(path), change.axis == .column, let oldTable = sheet.tables.first(where: { $0.partPath == path }), let cols = node.child("tableColumns") {
                var columns = cols.elements("tableColumn")
                if change.deleting {
                    columns = columns.enumerated().filter { change.position(oldTable.range.start.column + $0.offset) != nil }.map(\.element)
                } else if change.index > oldTable.range.start.column && change.index <= oldTable.range.end.column {
                    var names = Set(columns.compactMap { $0.attributes["name"] })
                    let nextID = (columns.compactMap { Int($0.attributes["id"] ?? "") }.max() ?? 0) + 1
                    for offset in 0 ..< change.count {
                        var number = nextID + offset
                        while names.contains("Column\(number)") { number += 1 }
                        let name = "Column\(number)"; names.insert(name)
                        columns.insert(cols.make("tableColumn", ["id": String(nextID + offset), "name": name]), at: change.index - oldTable.range.start.column + offset)
                        let address = ExcelCellAddress(row: oldTable.range.start.row, column: change.index + offset)
                        let cell = ensureCell(address, in: root); cell.attributes["t"] = "inlineStr"
                        let text = cell.ensure("is").ensure("t"); text.text = name
                    }
                }
                cols.children = columns; cols.attributes["count"] = String(columns.count)
            }
            func visit(_ item: Node, appliesLocally: Bool) {
                let scoped = appliesLocally || (item.localName == "worksheetSource" && item.attributes["sheet"] == sheet.name)
                if ["f", "formula", "formula1", "formula2", "calculatedColumnFormula", "totalsRowFormula", "definedName"].contains(item.localName) {
                    let definedLocal = item.attributes["localSheetId"].flatMap(Int.init).flatMap { workbook.sheets.indices.contains($0) ? workbook.sheets[$0].name : nil }
                    item.text = ExcelFormulaReferenceEditing.structural(item.text, change: change, targetSheet: sheet.name, localSheet: definedLocal ?? localSheet)
                }
                if scoped {
                    for key in ["ref", "sqref", "activeCell", "topLeftCell"] {
                        if let refs = item.attributes[key] {
                            let mapped = refs.split(separator: " ").compactMap { part -> String? in
                                guard let range = ExcelCellRange(String(part)), let next = change.range(range) else { return nil }
                                return next.reference
                            }.joined(separator: " ")
                            item.attributes[key] = mapped.isEmpty ? nil : mapped
                        }
                    }
                    if let location = item.attributes["location"] { item.attributes["location"] = ExcelFormulaReferenceEditing.structural(location, change: change, targetSheet: sheet.name, localSheet: sheet.name) }
                }
                item.children.removeAll { child in
                    guard appliesLocally, ["mergeCell", "hyperlink", "comment", "dataValidation", "conditionalFormatting"].contains(child.localName), let ref = child.attributes["ref"] ?? child.attributes["sqref"] else { return false }
                    return ref.split(separator: " ").allSatisfy { ExcelCellRange(String($0)).flatMap(change.range) == nil }
                }
                for child in item.children { visit(child, appliesLocally: scoped) }
                if ["mergeCells", "dataValidations"].contains(item.localName) { item.attributes["count"] = String(item.children.filter { !$0.name.hasPrefix("#") }.count) }
            }
            visit(node, appliesLocally: path == sheet.partPath || tablePaths.contains(path) || related.contains(path) && ["comments", "pivotTableDefinition"].contains(node.localName))
            if node.localName == "pivotCacheDefinition" { node.attributes["refreshOnLoad"] = "1" }
            if related.contains(path) && node.localName == "wsDr" {
                for anchor in node.children {
                    for endpoint in anchor.children where ["from", "to"].contains(endpoint.localName) {
                        let name = change.axis == .row ? "row" : "col"
                        if let coordinate = endpoint.child(name), let zeroBased = Int(coordinate.text) {
                            coordinate.text = String(max(0, (change.position(zeroBased + 1) ?? change.index) - 1))
                        }
                    }
                }
            }
            if path == sheet.partPath { normalizeSheet(node) }
            replacements[path] = ExcelEditingXML.data(node)
        }
    }

    private static func applyFormat(_ format: ExcelBasicFormat, range: ExcelCellRange, root: Node, styles: Node) throws {
        let fonts = styles.ensure("fonts"), fills = styles.ensure("fills"), borders = styles.ensure("borders"), xfs = styles.ensure("cellXfs")
        let originals = xfs.elements("xf")
        guard !originals.isEmpty else { throw ExcelWorkbookDocumentError.cannotSave }
        var registry: [String: Int] = [:]
        for row in range.start.row ... range.end.row {
            for column in range.start.column ... range.end.column {
                let cell = ensureCell(ExcelCellAddress(row: row, column: column), in: root)
                let oldIndex = Int(cell.attributes["s"] ?? "") ?? 0
                let mask = format.borders == "outside" ? "\(row == range.start.row)-\(row == range.end.row)-\(column == range.start.column)-\(column == range.end.column)" : "all"
                let key = "\(oldIndex):\(mask)"
                if let index = registry[key] { cell.attributes["s"] = String(index); continue }
                guard originals.indices.contains(oldIndex) else { throw ExcelWorkbookDocumentError.cannotSave }
                let xf = originals[oldIndex].copy()
                if format.fontName != nil || format.fontSize != nil || format.bold != nil || format.italic != nil || format.underline != nil || format.textColor != nil {
                    let index = Int(xf.attributes["fontId"] ?? "") ?? 0
                    let font = fonts.elements("font").indices.contains(index) ? fonts.elements("font")[index].copy() : fonts.make("font")
                    func flag(_ name: String, _ enabled: Bool?) { if let enabled { font.remove(name); if enabled { font.children.append(font.make(name)) } } }
                    flag("b", format.bold); flag("i", format.italic); flag("u", format.underline)
                    if let name = format.fontName { font.ensure("name").attributes = ["val": name]; font.remove("scheme") }
                    if let size = format.fontSize { font.ensure("sz").attributes = ["val": String(min(96, max(6, size)))] }
                    if let color = format.textColor { font.remove("color"); font.children.append(font.make("color", color.isEmpty ? ["theme": "1"] : ["rgb": color])) }
                    xf.attributes["fontId"] = String(fonts.elements("font").count); xf.attributes["applyFont"] = "1"; fonts.children.append(font)
                }
                if let color = format.fillColor {
                    let fill = fills.make("fill"), pattern = fills.make("patternFill", ["patternType": color.isEmpty ? "none" : "solid"])
                    if !color.isEmpty { pattern.children = [pattern.make("fgColor", ["rgb": color]), pattern.make("bgColor", ["indexed": "64"])] }
                    fill.children = [pattern]; xf.attributes["fillId"] = String(fills.elements("fill").count); xf.attributes["applyFill"] = "1"; fills.children.append(fill)
                }
                if format.horizontal != nil || format.vertical != nil || format.wrap != nil {
                    let alignment = xf.ensure("alignment")
                    if let value = format.horizontal { alignment.attributes["horizontal"] = value }
                    if let value = format.vertical { alignment.attributes["vertical"] = value }
                    if let value = format.wrap { alignment.attributes["wrapText"] = value ? "1" : "0" }
                    xf.attributes["applyAlignment"] = "1"
                }
                if let mode = format.borders {
                    let border = borders.make("border")
                    for name in ["left", "right", "top", "bottom", "diagonal"] {
                        let enabled = name != "diagonal" && (mode == "all" || mode == "outside" && ((name == "left" && column == range.start.column) || (name == "right" && column == range.end.column) || (name == "top" && row == range.start.row) || (name == "bottom" && row == range.end.row)))
                        let edge = border.make(name, enabled ? ["style": "thin"] : [:])
                        if enabled { edge.children = [edge.make("color", ["rgb": "FF808080"])] }
                        border.children.append(edge)
                    }
                    xf.attributes["borderId"] = String(borders.elements("border").count); xf.attributes["applyBorder"] = "1"; borders.children.append(border)
                }
                let index = xfs.elements("xf").count; xfs.children.append(xf); registry[key] = index; cell.attributes["s"] = String(index)
            }
        }
        for (node, name) in [(fonts, "font"), (fills, "fill"), (borders, "border"), (xfs, "xf")] { node.attributes["count"] = String(node.elements(name).count) }
    }
}
