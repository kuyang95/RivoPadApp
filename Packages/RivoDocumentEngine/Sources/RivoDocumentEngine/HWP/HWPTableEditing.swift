import Foundation

/// Editing changes the logical cell sizes. Page slices remain a projection of
/// these blocks, so saves and undo never contain duplicated continuation cells.
@MainActor
public enum HWPTableEditing {
    public static func supports(_ block: HWPDocumentBlock) -> Bool {
        supportsCellLayout(block, allowingObjects: false)
    }

    public static func reflow(_ blocks: [HWPDocumentBlock], before: [HWPDocumentBlock],
                       startingAt id: String, layouts: [HWPDocumentPageLayout],
                       reflowBody: Bool = true, minimumHeight: Double = 0,
                       allowingObjects: Bool = false) -> [HWPDocumentBlock] {
        guard minimumHeight.isFinite, minimumHeight >= 0,
              let index = blocks.firstIndex(where: { $0.id == id }),
              supportsCellLayout(blocks[index], allowingObjects: allowingObjects),
              let cell = blocks[index].tableLocation else { return blocks }
        let section = blocks[index].sectionPath
        let sectionIndex = Int(section.lowercased().components(separatedBy: "section").last?
            .replacingOccurrences(of: ".xml", with: "") ?? "0") ?? 0
        guard let layout = layouts.first(where: { $0.sectionIndex == sectionIndex }),
              layout.columnLayout.columns.count <= 1 else { return blocks }
        let members = blocks.indices.filter {
            blocks[$0].sectionPath == section
                && blocks[$0].layoutContainerID == blocks[index].layoutContainerID
                && blocks[$0].tableLocation?.table == cell.table
        }
        let oldMembers = before.filter {
            $0.sectionPath == section
                && $0.layoutContainerID == blocks[index].layoutContainerID
                && $0.tableLocation?.table == cell.table
        }
        let tracks = HWPTableTrackLayoutSolver.make(blocks: oldMembers.isEmpty ? members.map { blocks[$0] } : oldMembers)
        let currentTracks = HWPTableTrackLayoutSolver.make(blocks: members.map { blocks[$0] })
        guard cell.column + cell.columnSpan <= tracks.columnWidths.count,
              cell.row + cell.rowSpan <= tracks.rowHeights.count else { return blocks }
        var result = blocks
        let cellIndices = members.filter {
            blocks[$0].tableLocation?.row == cell.row && blocks[$0].tableLocation?.column == cell.column
        }.sorted { blocks[$0].tableLocation!.paragraph < blocks[$1].tableLocation!.paragraph }
        guard cellIndices.allSatisfy({
            supportsCellLayout(blocks[$0], allowingObjects: allowingObjects)
        }) else { return blocks }
        let cellWidth = tracks.columnWidths[cell.column..<(cell.column + cell.columnSpan)].reduce(0, +)
        let width = max(1, cellWidth - cell.cellMarginLeftPoints - cell.cellMarginRightPoints)
        var y = 0.0
        for position in cellIndices {
            let block = blocks[position]
            y += block.presentation.spacingBeforePoints
            let lines = HWPFlowLayout.measure(block,
                width: max(1, width - block.presentation.leftMarginPoints - block.presentation.rightMarginPoints),
                startY: y, pageHeight: nil,
                minimumHeight: block.id == id ? minimumHeight : 0)
            result[position] = block.withLayout(lines: lines)
            if let last = lines.last {
                y = last.verticalPositionPoints + last.lineHeightPoints
                    + last.lineSpacingPoints + block.presentation.spacingAfterPoints
            }
        }
        let last = cellIndices.last.flatMap { result[$0].lineLayouts.last }
        // Last-line leading is between lines, not padding below a cell.
        let required = max(16, y - (last?.lineSpacingPoints ?? 0))
            + cell.cellMarginTopPoints + cell.cellMarginBottomPoints
        var heights = zip(tracks.rowHeights, currentTracks.rowHeights).map { max($0, $1) }
        let span = cell.row..<(cell.row + cell.rowSpan)
        let deficit = max(0, required - heights[span].reduce(0, +))
        // Grow the last track of a vertical merge, keeping preceding rows fixed.
        heights[span.upperBound - 1] += deficit
        let total = heights.reduce(0, +)
        for position in members {
            guard let location = result[position].tableLocation,
                  location.row + location.rowSpan <= heights.count else { continue }
            result[position] = result[position].withLayout(tableLocation: location.withEditingHeights(
                cell: heights[location.row..<(location.row + location.rowSpan)].reduce(0, +), table: total))
        }
        if let parent = cell.parent {
            let firstChild = members.min() ?? index
            let parentMembers = result.indices.filter {
                result[$0].sectionPath == section
                    && result[$0].layoutContainerID == result[index].layoutContainerID
                    && result[$0].tableLocation?.table == parent.table
                    && result[$0].tableLocation?.row == parent.row
                    && result[$0].tableLocation?.column == parent.column
            }
            // The paragraph containing the nested table precedes its child
            // cell records. Prefer that paragraph when an outer cell contains
            // more than one paragraph so text after the table keeps its place.
            let parentIndex = parentMembers.last(where: { $0 < firstChild })
                ?? parentMembers.first
            guard let parentIndex else { return result }
            let placementHeight = result[members.first ?? index].tableLocation?
                .tablePlacement?.heightPoints ?? 0
            let requiredBottom = max(total, placementHeight)
                + max(0, cell.tableAnchor?.verticalPositionPoints ?? 0)
                + max(0, cell.tablePlacement?.yPoints ?? 0)
            return reflow(result, before: before, startingAt: result[parentIndex].id,
                layouts: layouts, reflowBody: reflowBody,
                minimumHeight: max(16, requiredBottom), allowingObjects: true)
        }
        // The owning root paragraph precedes the table's cell paragraphs.
        if reflowBody, blocks[index].layoutContainerID == nil, let first = members.first,
           let owner = result.indices.prefix(first).last(where: {
               result[$0].sectionPath == section && result[$0].region.kind == .body
                   && result[$0].tableLocation == nil && result[$0].layoutContainerID == nil
           }) {
            // An uncached table control has no line to move. Resolve its
            // anchor before laying out the body, including the undo baseline.
            var baseline = before
            if result[owner].lineLayouts.isEmpty {
                func resolving(_ source: [HWPDocumentBlock]) -> [HWPDocumentBlock] {
                    let indices = source.indices.filter { source[$0].sectionPath == section }
                    let resolved = HWPFlowLayout.resolvingMissingLines(indices.map { source[$0] }, layout: layout)
                    var output = source
                    for (offset, index) in indices.enumerated() { output[index] = resolved[offset] }
                    return output
                }
                baseline = resolving(before)
                result = resolving(result)
            }
            result = HWPFlowLayout.reflowingBody(result, before: baseline,
                startingAt: result[owner].id, layouts: layouts, reflowingTables: true)
        }
        return result
    }

    private static func supportsCellLayout(_ block: HWPDocumentBlock,
                                           allowingObjects: Bool) -> Bool {
        (block.isEditable || (allowingObjects
            && (!block.canvasObjects.isEmpty || block.keepsParagraphBoundary)))
            && block.region.kind == .body
            && block.tableLocation != nil
            && (allowingObjects || block.canvasObjects.isEmpty)
            && (allowingObjects || block.images.isEmpty)
            && (block.presentation.list?.isSimple
                ?? !block.lineLayouts.contains(where: { $0.listMarker != nil }))
    }

    public static func finalPageBottom(_ blocks: [HWPDocumentBlock], anchorY: Double,
                                layout: HWPDocumentPageLayout) -> Double {
        guard let location = blocks.first?.tableLocation else { return anchorY }
        var tracks = HWPTableTrackLayoutSolver.make(blocks: blocks)
        let body = layout.heightPoints - layout.topMarginPoints - layout.bottomMarginPoints
        let reserved = body - layout.headerMarginPoints - layout.footerMarginPoints
        let capacity = location.tablePageBoundaryMode == 1
            || (location.tablePageBoundaryMode == 2 && anchorY > reserved * 0.75) ? reserved : body
        let header = location.repeatsHeaderRow ? tracks.rowHeights.first ?? 0 : 0
        let expanded = HWPOriginalCanvasPageBuilder.expandingTallTableRows(blocks, maximumHeight: max(72, capacity - header))
        tracks = HWPTableTrackLayoutSolver.make(blocks: expanded)
        let slices = HWPOriginalCanvasPageBuilder.tableRowSlices(heights: tracks.rowHeights,
            firstCapacity: max(72, capacity - anchorY), continuationCapacity: max(72, capacity - header),
            locations: expanded.compactMap(\.tableLocation), cutsThroughMergedCells: location.tablePageBoundaryMode == 2)
        guard let last = slices.last else { return anchorY }
        return tracks.rowHeights[last].reduce(0, +) + (slices.count == 1 ? anchorY : header)
    }
}

nonisolated extension HWPDocumentTableLocation {
    public func withEditingHeights(cell: Double, table: Double) -> HWPDocumentTableLocation {
        var placement = tablePlacement
        if var value = placement { value.heightPoints = table; placement = value }
        return HWPDocumentTableLocation(table: self.table, row: row, column: column, paragraph: paragraph,
            rowSpan: rowSpan, columnSpan: columnSpan, boxStyle: boxStyle,
            cellWidthPoints: cellWidthPoints, cellHeightPoints: cell,
            cellMarginLeftPoints: cellMarginLeftPoints, cellMarginRightPoints: cellMarginRightPoints,
            cellMarginTopPoints: cellMarginTopPoints, cellMarginBottomPoints: cellMarginBottomPoints,
            cellVerticalAlignment: cellVerticalAlignment, tablePageBoundaryMode: tablePageBoundaryMode,
            repeatsHeaderRow: repeatsHeaderRow, tablePlacement: placement, tableAnchor: tableAnchor,
                parent: parent, backgroundZones: backgroundZones)
    }
}
