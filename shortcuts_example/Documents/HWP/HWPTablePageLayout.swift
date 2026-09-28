import Foundation

extension HWPOriginalCanvasPageBuilder {
    /// Split a plain row taller than one sheet at cached line boundaries.
    /// This only produces canvas fragments; the logical row stays intact.
    static func expandingTallTableRows(_ blocks: [HWPDocumentBlock], maximumHeight: Double) -> [HWPDocumentBlock] {
        guard let table = blocks.first?.tableLocation?.table else { return blocks }
        let roots = blocks.filter { $0.tableLocation?.table == table && $0.tableLocation?.parent == nil }
        let tracks = HWPTableTrackLayoutSolver.make(blocks: roots)
        var slices: [Int: [Range<Double>]] = [:]
        for row in tracks.rowHeights.indices where tracks.rowHeights[row] > maximumHeight {
            let rowBlocks = roots.filter { $0.tableLocation?.row == row }
            guard !rowBlocks.isEmpty,
                  rowBlocks.allSatisfy({ $0.tableLocation?.rowSpan == 1 && $0.images.isEmpty && $0.canvasObjects.isEmpty }),
                  !roots.contains(where: { ($0.tableLocation!.row..<($0.tableLocation!.row + $0.tableLocation!.rowSpan)).contains(row) && $0.tableLocation!.rowSpan > 1 }),
                  !blocks.contains(where: { $0.tableLocation?.parent?.table == table && $0.tableLocation?.parent?.row == row }) else { continue }
            let padding = rowBlocks.map { $0.tableLocation!.cellMarginTopPoints + $0.tableLocation!.cellMarginBottomPoints }.max() ?? 0
            let capacity = max(16, maximumHeight - padding)
            let contentHeight = max(1, tracks.rowHeights[row] - padding)
            let lines = rowBlocks.flatMap(\.lineLayouts)
            var start = 0.0, ranges: [Range<Double>] = []
            while start < contentHeight {
                var end = min(contentHeight, start + capacity)
                // All cells share the cut, so no neighboring line is clipped.
                let crossing = lines.filter {
                    $0.verticalPositionPoints > start + 0.01 && $0.verticalPositionPoints < end
                        && $0.verticalPositionPoints + max($0.lineHeightPoints, $0.textHeightPoints) > end
                }.map(\.verticalPositionPoints)
                if let cut = crossing.min() { end = cut }
                guard end > start else { break }
                ranges.append(start..<end)
                start = end
            }
            if ranges.count > 1 { slices[row] = ranges }
        }
        guard !slices.isEmpty else { return blocks }
        func rowOffset(_ row: Int) -> Int { slices.filter { $0.key < row }.values.reduce(0) { $0 + $1.count - 1 } }
        var output: [HWPDocumentBlock] = []
        for block in blocks {
            guard let location = block.tableLocation, location.table == table, location.parent == nil else {
                // A nested table in another row follows its outer cell index.
                if let location = block.tableLocation, let parent = location.parent, parent.table == table {
                    var updated = location
                    updated.parent = HWPDocumentTableParentLocation(table: parent.table,
                        row: parent.row + rowOffset(parent.row), column: parent.column)
                    output.append(block.withLayout(tableLocation: updated))
                } else { output.append(block) }
                continue
            }
            guard let ranges = slices[location.row] else {
                output.append(block.withLayout(tableLocation: location.replacingRow(location.row + rowOffset(location.row),
                    rowSpan: location.rowSpan, cellHeightPoints: location.cellHeightPoints)))
                continue
            }
            for (part, range) in ranges.enumerated() {
                let lines = block.lineLayouts.filter { range.contains($0.verticalPositionPoints) }
                let start = lines.first.map { HWPInlineParagraphGeometry.textOffset(in: block.text, raw: $0.startCharacter) } ?? block.text.utf16.count
                let next = block.lineLayouts.first { $0.verticalPositionPoints >= range.upperBound }
                let end = next.map { HWPInlineParagraphGeometry.textOffset(in: block.text, raw: $0.startCharacter) } ?? block.text.utf16.count
                let textRange = NSRange(location: start, length: max(0, end - start))
                let fragment = HWPParagraphEditing.slice(block, range: textRange)
                let height = range.upperBound - range.lowerBound + location.cellMarginTopPoints + location.cellMarginBottomPoints
                let cell = location.replacingRow(location.row + rowOffset(location.row) + part,
                    rowSpan: 1, cellHeightPoints: height)
                output.append(HWPDocumentBlock(id: part == 0 ? block.id : block.id + "-page-fragment-cell-\(part)",
                    sectionPath: block.sectionPath, paragraphIndex: block.paragraphIndex,
                    text: fragment.text, tableLocation: cell, isEditable: block.isEditable,
                    presentation: fragment.presentation, region: block.region, images: block.images,
                    lineLayouts: lines.map { $0.positioned(y: $0.verticalPositionPoints - range.lowerBound) },
                    canvasObjects: block.canvasObjects, layoutContainerID: block.layoutContainerID))
            }
        }
        // Row fragments must be adjacent; paragraph order alone would group all
        // pages of the first column ahead of the neighboring cell.
        return output.enumerated().sorted { a, b in
            let rowA = a.element.tableLocation?.parent?.row ?? a.element.tableLocation?.row ?? 0
            let rowB = b.element.tableLocation?.parent?.row ?? b.element.tableLocation?.row ?? 0
            return rowA == rowB ? a.offset < b.offset : rowA < rowB
        }.map(\.element)
    }
}
