import Foundation

public nonisolated struct HWPAccessibleTableReference: Identifiable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public nonisolated struct HWPAccessibleCell: Identifiable {
    public let location: HWPDocumentTableLocation
    public let blocks: [HWPDocumentBlock]
    public var nestedTables: [HWPAccessibleTableReference] = []

    public var id: String { blocks[0].id }
    public var text: String { blocks.map(\.text).joined(separator: "\n") }
    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && blocks.allSatisfy { $0.images.isEmpty && $0.canvasObjects.isEmpty }
            && nestedTables.isEmpty
    }
    public var columnDescription: String {
        if location.columnSpan > 1 {
            return DocumentEngineLocalization.format("%lld–%lld열", location.column + 1,
                location.column + location.columnSpan)
        }
        return DocumentEngineLocalization.format("%lld열", location.column + 1)
    }
    public var mergeDescription: String? {
        guard location.rowSpan > 1 || location.columnSpan > 1 else { return nil }
        return DocumentEngineLocalization.format("%lld행×%lld열 병합", location.rowSpan, location.columnSpan)
    }
    public var displayText: String {
        if isEmpty { return DocumentEngineLocalization.string("빈 셀") }
        var parts: [String] = []
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(text) }
        if !nestedTables.isEmpty {
            parts.append(DocumentEngineLocalization.format("안쪽 표: %@", nestedTables.map(\.title).joined(separator: ", ")))
        }
        return parts.isEmpty ? DocumentEngineLocalization.string("문서 개체") : parts.joined(separator: "\n")
    }

    public init(location: HWPDocumentTableLocation, blocks: [HWPDocumentBlock], nestedTables: [HWPAccessibleTableReference] = []) {
        self.location = location
        self.blocks = blocks
        self.nestedTables = nestedTables
    }
}

public nonisolated struct HWPAccessibleRow: Identifiable {
    public let id: String
    public let tableTitle: String
    public let index: Int
    public let cells: [HWPAccessibleCell]
    /// Earlier cells spanning this row provide context without duplicating editable fields.
    public let spanningCells: [HWPAccessibleCell]

    public var title: String { DocumentEngineLocalization.format("%lld행", index + 1) }
    public var blocks: [HWPDocumentBlock] { cells.flatMap(\.blocks) }
    public var accessibilityLabel: String {
        accessibilityLabel(fieldNames: [:])
    }

    public func accessibilityLabel(fieldNames: [String: String]) -> String {
        var parts = [tableTitle, title]
        parts += spanningCells.map {
            DocumentEngineLocalization.format("위 행과 병합: %@", $0.displayText)
        }
        parts += cells.map { cell in
            [fieldNames[cell.id], cell.columnDescription, cell.displayText, cell.mergeDescription]
                .compactMap { $0 }.joined(separator: ". ")
        }
        return parts.joined(separator: ". ")
    }

    public init(id: String, tableTitle: String, index: Int, cells: [HWPAccessibleCell], spanningCells: [HWPAccessibleCell]) {
        self.id = id
        self.tableTitle = tableTitle
        self.index = index
        self.cells = cells
        self.spanningCells = spanningCells
    }
}

public nonisolated struct HWPAccessibleTable: Identifiable {
    public let id: String
    public let title: String
    public let context: String?
    public let rowCount: Int
    public let columnCount: Int
    public let rows: [HWPAccessibleRow]

    public init(id: String, title: String, context: String? = nil, rowCount: Int, columnCount: Int, rows: [HWPAccessibleRow]) {
        self.id = id
        self.title = title
        self.context = context
        self.rowCount = rowCount
        self.columnCount = columnCount
        self.rows = rows
    }
}

public nonisolated struct HWPAccessibleDocument {
    public enum Entry: Identifiable {
        case paragraph(HWPDocumentBlock)
        case table(HWPAccessibleTable)
        case row(HWPAccessibleRow)

        public var id: String {
            switch self {
            case .paragraph(let block): return block.id
            case .table(let table): return table.id
            case .row(let row): return row.id
            }
        }
    }

    public let entries: [Entry]
    public let tables: [HWPAccessibleTable]
    public let entryIDByBlockID: [String: String]

    private struct TableKey: Hashable {
        let section: String
        let region: HWPDocumentRegion
        let table: Int
    }

    private struct CellKey: Hashable {
        let row: Int
        let column: Int
    }

    public static func make(blocks: [HWPDocumentBlock]) -> Self {
        func key(for block: HWPDocumentBlock) -> TableKey? {
            block.tableLocation.map {
                TableKey(section: block.sectionPath, region: block.region, table: $0.table)
            }
        }
        var grouped: [TableKey: [HWPDocumentBlock]] = [:]
        for block in blocks {
            if let key = key(for: block) { grouped[key, default: []].append(block) }
        }
        var references: [TableKey: HWPAccessibleTableReference] = [:]
        for block in blocks {
            guard let key = key(for: block), references[key] == nil else { continue }
            references[key] = HWPAccessibleTableReference(id: "hwp-accessible-table-\(block.id)",
                title: DocumentEngineLocalization.format("표 %lld", references.count + 1))
        }
        var nested: [TableKey: [CellKey: [HWPAccessibleTableReference]]] = [:]
        for block in blocks {
            guard let childKey = key(for: block), grouped[childKey]?.first?.id == block.id,
                  let parent = block.tableLocation?.parent,
                  let reference = references[childKey] else { continue }
            let parentKey = TableKey(section: block.sectionPath, region: block.region, table: parent.table)
            let cellKey = CellKey(row: parent.row, column: parent.column)
            nested[parentKey, default: [:]][cellKey, default: []].append(reference)
        }
        var entries: [Entry] = []
        var tables: [HWPAccessibleTable] = []
        var emitted = Set<TableKey>()
        var entryIDs: [String: String] = [:]
        for block in blocks {
            guard let key = key(for: block) else {
                continue
            }
            guard emitted.insert(key).inserted, let tableBlocks = grouped[key] else { continue }
            guard let reference = references[key] else { continue }
            let tableID = reference.id
            let title = reference.title
            var groupedCells: [CellKey: [HWPDocumentBlock]] = [:]
            for cellBlock in tableBlocks {
                guard let location = cellBlock.tableLocation else { continue }
                groupedCells[CellKey(row: location.row, column: location.column), default: []]
                    .append(cellBlock)
            }
            let cells = groupedCells.values.compactMap { cellBlocks -> HWPAccessibleCell? in
                let sorted = cellBlocks.sorted {
                    ($0.tableLocation?.paragraph ?? 0) < ($1.tableLocation?.paragraph ?? 0)
                }
                guard let location = sorted.first?.tableLocation else { return nil }
                return HWPAccessibleCell(location: location, blocks: sorted,
                    nestedTables: nested[key]?[CellKey(row: location.row, column: location.column)] ?? [])
            }.sorted {
                ($0.location.row, $0.location.column) < ($1.location.row, $1.location.column)
            }
            let groupedRows = Dictionary(grouping: cells, by: { $0.location.row })
            var rows: [HWPAccessibleRow] = []
            var spanningCells: [HWPAccessibleCell] = []
            for row in groupedRows.keys.sorted() {
                spanningCells.removeAll { $0.location.row + $0.location.rowSpan <= row }
                let rowCells = groupedRows[row] ?? []
                rows.append(HWPAccessibleRow(id: "\(tableID)-row-\(row)", tableTitle: title,
                    index: row, cells: rowCells, spanningCells: spanningCells))
                spanningCells.append(contentsOf: rowCells.filter { $0.location.rowSpan > 1 })
            }
            var context = [block.region.accessibilityDescription]
            if let parent = block.tableLocation?.parent {
                let parentKey = TableKey(section: block.sectionPath, region: block.region, table: parent.table)
                let parentTitle = references[parentKey].map { $0.title + " · " } ?? ""
                context.append(parentTitle + DocumentEngineLocalization.format("%lld행 · %lld열 안의 표",
                    parent.row + 1, parent.column + 1))
            }
            let table = HWPAccessibleTable(id: tableID, title: title,
                context: context.compactMap { $0 }.joined(separator: " · "),
                rowCount: cells.map { $0.location.row + $0.location.rowSpan }.max() ?? 0,
                columnCount: cells.map { $0.location.column + $0.location.columnSpan }.max() ?? 0,
                rows: rows)
            tables.append(table)
            for row in rows {
                for cellBlock in row.blocks { entryIDs[cellBlock.id] = row.id }
            }
        }
        let tablesByID = Dictionary(uniqueKeysWithValues: tables.map { ($0.id, $0) })
        var emittedTableIDs = Set<String>()
        func appendTable(_ table: HWPAccessibleTable) {
            guard emittedTableIDs.insert(table.id).inserted else { return }
            entries.append(.table(table))
            for row in table.rows {
                entries.append(.row(row))
                for cell in row.cells {
                    for reference in cell.nestedTables {
                        if let child = tablesByID[reference.id] { appendTable(child) }
                    }
                }
            }
        }
        for block in blocks {
            if let key = key(for: block), let reference = references[key],
               let table = tablesByID[reference.id] {
                appendTable(table)
            } else if !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !block.images.isEmpty || !block.canvasObjects.isEmpty {
                entries.append(.paragraph(block))
                entryIDs[block.id] = block.id
            }
        }
        return Self(entries: entries, tables: tables, entryIDByBlockID: entryIDs)
    }

    public init(entries: [Entry], tables: [HWPAccessibleTable], entryIDByBlockID: [String: String]) {
        self.entries = entries
        self.tables = tables
        self.entryIDByBlockID = entryIDByBlockID
    }
}
