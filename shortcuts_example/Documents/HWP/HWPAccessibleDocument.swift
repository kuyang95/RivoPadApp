import Foundation

nonisolated struct HWPAccessibleTableReference: Identifiable {
    let id: String
    let title: String
}

nonisolated struct HWPAccessibleCell: Identifiable {
    let location: HWPDocumentTableLocation
    let blocks: [HWPDocumentBlock]
    var nestedTables: [HWPAccessibleTableReference] = []

    var id: String { blocks[0].id }
    var text: String { blocks.map(\.text).joined(separator: "\n") }
    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && blocks.allSatisfy { $0.images.isEmpty && $0.canvasObjects.isEmpty }
            && nestedTables.isEmpty
    }
    var columnDescription: String {
        if location.columnSpan > 1 {
            return AppLocalization.format("%lld–%lld열", location.column + 1,
                location.column + location.columnSpan)
        }
        return AppLocalization.format("%lld열", location.column + 1)
    }
    var mergeDescription: String? {
        guard location.rowSpan > 1 || location.columnSpan > 1 else { return nil }
        return AppLocalization.format("%lld행×%lld열 병합", location.rowSpan, location.columnSpan)
    }
    var displayText: String {
        if isEmpty { return AppLocalization.string("빈 셀") }
        var parts: [String] = []
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(text) }
        if !nestedTables.isEmpty {
            parts.append(AppLocalization.format("안쪽 표: %@", nestedTables.map(\.title).joined(separator: ", ")))
        }
        return parts.isEmpty ? AppLocalization.string("문서 개체") : parts.joined(separator: "\n")
    }
}

nonisolated struct HWPAccessibleRow: Identifiable {
    let id: String
    let tableTitle: String
    let index: Int
    let cells: [HWPAccessibleCell]
    /// Earlier cells spanning this row provide context without duplicating editable fields.
    let spanningCells: [HWPAccessibleCell]

    var title: String { AppLocalization.format("%lld행", index + 1) }
    var blocks: [HWPDocumentBlock] { cells.flatMap(\.blocks) }
    var accessibilityLabel: String {
        accessibilityLabel(fieldNames: [:])
    }

    func accessibilityLabel(fieldNames: [String: String]) -> String {
        var parts = [tableTitle, title]
        parts += spanningCells.map {
            AppLocalization.format("위 행과 병합: %@", $0.displayText)
        }
        parts += cells.map { cell in
            [fieldNames[cell.id], cell.columnDescription, cell.displayText, cell.mergeDescription]
                .compactMap { $0 }.joined(separator: ". ")
        }
        return parts.joined(separator: ". ")
    }
}

nonisolated struct HWPAccessibleTable: Identifiable {
    let id: String
    let title: String
    let context: String?
    let rowCount: Int
    let columnCount: Int
    let rows: [HWPAccessibleRow]
}

nonisolated struct HWPAccessibleDocument {
    enum Entry: Identifiable {
        case paragraph(HWPDocumentBlock)
        case table(HWPAccessibleTable)
        case row(HWPAccessibleRow)

        var id: String {
            switch self {
            case .paragraph(let block): return block.id
            case .table(let table): return table.id
            case .row(let row): return row.id
            }
        }
    }

    let entries: [Entry]
    let tables: [HWPAccessibleTable]
    let entryIDByBlockID: [String: String]

    private struct TableKey: Hashable {
        let section: String
        let region: HWPDocumentRegion
        let table: Int
    }

    private struct CellKey: Hashable {
        let row: Int
        let column: Int
    }

    static func make(blocks: [HWPDocumentBlock]) -> Self {
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
                title: AppLocalization.format("표 %lld", references.count + 1))
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
                context.append(parentTitle + AppLocalization.format("%lld행 · %lld열 안의 표",
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
}
