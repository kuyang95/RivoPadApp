import Foundation

public nonisolated struct HWPOriginalCanvasPage: Identifiable, Sendable {
    public let id: String
    public let pageNumber: Int
    public let sectionPageIndex: Int
    public let layout: HWPDocumentPageLayout
    public let bodyBlocks: [HWPDocumentBlock]
    public let sectionBlocks: [HWPDocumentBlock]
    public let noteBlocks: [HWPDocumentBlock]
    public var numberingOffset = 0
    public func regionBlocks(_ kind: HWPDocumentRegionKind) -> [HWPDocumentBlock] {
        sectionBlocks.filter { block in
            guard block.region.kind == kind else { return false }
            switch block.region.scope ?? .bothPages {
            case .bothPages: return true
            case .evenPages: return (pageNumber + numberingOffset).isMultiple(of: 2)
            case .oddPages: return !(pageNumber + numberingOffset).isMultiple(of: 2)
            }
        }
    }
    public var pageNumberText: String? {
        layout.pageNumberStyle?.text(pageNumber: pageNumber + numberingOffset, sectionPageIndex: sectionPageIndex)
    }

    public init(id: String, pageNumber: Int, sectionPageIndex: Int, layout: HWPDocumentPageLayout, bodyBlocks: [HWPDocumentBlock], sectionBlocks: [HWPDocumentBlock], noteBlocks: [HWPDocumentBlock], numberingOffset: Int = 0) {
        self.id = id
        self.pageNumber = pageNumber
        self.sectionPageIndex = sectionPageIndex
        self.layout = layout
        self.bodyBlocks = bodyBlocks
        self.sectionBlocks = sectionBlocks
        self.noteBlocks = noteBlocks
        self.numberingOffset = numberingOffset
    }
}

@MainActor
public enum HWPOriginalCanvasPageBuilder {
    public static func makePages(
        blocks: [HWPDocumentBlock],
        layouts: [HWPDocumentPageLayout]
    ) -> [HWPOriginalCanvasPage] {
        let effectiveLayouts = layouts.isEmpty
            ? [HWPDocumentPageLayout.standard()]
            : layouts
        var result: [HWPOriginalCanvasPage] = []
        var pageNumber = 1, numberingOffset = 0
        for layout in effectiveLayouts {
            if let start = layout.pageNumberStart ?? layout.pageNumberStyle?.startsAt { numberingOffset = start - pageNumber }
            let section = HWPFlowLayout.resolvingMissingLines(blocks.filter {
                sectionIndex(for: $0) == layout.sectionIndex
            }, layout: layout)
            let rootBody = section.filter {
                $0.region.kind == .body && $0.layoutContainerID == nil
            }
            let positionedRootBody = normalizeColumnPositions(
                rootBody,
                layout: layout
            )
            let contentHeight = max(
                1,
                layout.heightPoints - layout.topMarginPoints - layout.bottomMarginPoints
            )
            let lineSplitBody = positionedRootBody.flatMap {
                splitAcrossPages($0, contentHeight: contentHeight)
            }
            let cachedPageSplitBody = markTableContentPageBreaks(
                lineSplitBody,
                contentHeight: contentHeight
            )
            let rowContinuationBody = normalizeSplitTableRows(
                cachedPageSplitBody
            )
            let body = splitOversizedTablesAcrossPages(
                rowContinuationBody,
                contentHeight: contentHeight,
                cellBoundaryContentHeight: max(
                    1,
                    contentHeight
                        - layout.headerMarginPoints
                        - layout.footerMarginPoints
                )
            )
            var pages: [[HWPDocumentBlock]] = [[]]
            var previousY = 0.0
            var previousTable: Int?
            var previousBlock: HWPDocumentBlock?
            for block in body {
                if block.tableLocation?.parent != nil {
                    pages[pages.count - 1].append(block)
                    continue
                }
                let table = block.tableLocation?.table
                let firstY = block.tableLocation?.tableAnchor?.verticalPositionPoints
                    ?? block.lineLayouts.first?.verticalPositionPoints
                    ?? previousY
                let generatedPageBreak = startsGeneratedPage(block)
                let isContinuationCell = table != nil
                    && table == previousTable
                    && !generatedPageBreak
                let previousAnchorsCurrentTable = table != nil
                    && previousBlock?.tableLocation == nil
                    && previousBlock?.text
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty == true
                    && (
                        previousBlock?.lineLayouts.contains { line in
                            abs(line.verticalPositionPoints - firstY) < 1
                                && (line.lineHeightPoints
                                >= (block.tableLocation?.tablePlacement?
                                    .heightPoints ?? .infinity) * 0.8
                                || line.widthPoints < 1)
                        } == true
                    )
                let resetToNewPage = !isContinuationCell
                    && !previousAnchorsCurrentTable
                    && !pages[pages.count - 1].isEmpty
                    && firstY < max(24, contentHeight * 0.08)
                    && previousY > contentHeight * 0.68
                // A line inside a table cell may carry the cached "first line
                // on page" bit. It describes the cell's layout context, not
                // a document-level page break. Only root paragraphs can use
                // that bit to start a new canvas page.
                let explicitBreak = generatedPageBreak
                    || (block.tableLocation == nil
                        && (block.presentation.pageBreakBefore
                            || block.lineLayouts.first?.startsPage == true))
                if (resetToNewPage || explicitBreak),
                   !pages[pages.count - 1].isEmpty {
                    pages.append([])
                    previousY = 0
                }
                pages[pages.count - 1].append(block)
                let tableBottom = block.tableLocation.flatMap { location in
                    location.tableAnchor.map { anchor in
                        anchor.verticalPositionPoints
                            + max(
                                location.tablePlacement?.heightPoints ?? 0,
                                anchor.lineHeightPoints
                            )
                    }
                }
                previousY = max(previousY, tableBottom ?? (
                    block.lineLayouts.last.map {
                        $0.verticalPositionPoints + max($0.lineHeightPoints, 12)
                    } ?? firstY
                ))
                previousTable = table
                previousBlock = block
            }
            if pages.isEmpty { pages = [[]] }
            var pageByParagraph: [String: Int] = [:]
            for (pageIndex, items) in pages.enumerated() {
                for item in items {
                    pageByParagraph[paragraphKey(item)] = pageIndex
                }
            }
            var notesByPage = [[HWPDocumentBlock]](
                repeating: [],
                count: pages.count
            )
            var activePageIndex = 0
            for block in section {
                if let pageIndex = pageByParagraph[paragraphKey(block)] {
                    activePageIndex = pageIndex
                } else if block.region.kind == .footnote
                            || block.region.kind == .endnote {
                    notesByPage[activePageIndex].append(block)
                }
            }
            for (index, pageBlocks) in pages.enumerated() {
                result.append(
                    HWPOriginalCanvasPage(
                        id: "hwp-canvas-page-\(layout.sectionIndex)-\(index)",
                        pageNumber: pageNumber,
                        sectionPageIndex: index,
                        layout: layout,
                        bodyBlocks: pageBlocks,
                        sectionBlocks: section,
                        noteBlocks: notesByPage[index], numberingOffset: numberingOffset
                    )
                )
                pageNumber += 1
            }
        }
        if result.isEmpty {
            result.append(
                HWPOriginalCanvasPage(
                    id: "hwp-canvas-page-fallback",
                    pageNumber: 1,
                    sectionPageIndex: 0,
                    layout: .standard(),
                    bodyBlocks: blocks,
                    sectionBlocks: blocks,
                    noteBlocks: blocks.filter {
                        $0.region.kind == .footnote || $0.region.kind == .endnote
                    }
                )
            )
        }
        return result
    }

    /// HWP line-cache X values are relative to the active column. Preserve
    /// that local value for table cells, but translate root paragraph lines
    /// and table anchors into the page content coordinate system.
    private static func normalizeColumnPositions(
        _ blocks: [HWPDocumentBlock],
        layout: HWPDocumentPageLayout
    ) -> [HWPDocumentBlock] {
        let columns = layout.columnLayout.columns
        guard columns.count > 1 else { return blocks }

        let contentWidth = max(
            1,
            layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints
        )
        var columnIndex = 0
        var hasPositionedLine = false
        var previousY = 0.0
        var previousWasFullWidth = true

        func columnOffset(_ index: Int) -> Double {
            columns[min(max(index, 0), columns.count - 1)].xPoints
        }

        return blocks.map { block in
            if let table = block.tableLocation {
                guard table.parent == nil else { return block }
                let anchor = table.tableAnchor.map {
                    HWPDocumentTableAnchor(
                        columnStartPoints: $0.columnStartPoints
                            + columnOffset(columnIndex),
                        verticalPositionPoints: $0.verticalPositionPoints,
                        widthPoints: $0.widthPoints,
                        lineHeightPoints: $0.lineHeightPoints,
                        paragraphAlignment: $0.paragraphAlignment
                    )
                }
                let location = HWPDocumentTableLocation(
                    table: table.table,
                    row: table.row,
                    column: table.column,
                    paragraph: table.paragraph,
                    rowSpan: table.rowSpan,
                    columnSpan: table.columnSpan,
                    boxStyle: table.boxStyle,
                    cellWidthPoints: table.cellWidthPoints,
                    cellHeightPoints: table.cellHeightPoints,
                    cellMarginLeftPoints: table.cellMarginLeftPoints,
                    cellMarginRightPoints: table.cellMarginRightPoints,
                    cellMarginTopPoints: table.cellMarginTopPoints,
                    cellMarginBottomPoints: table.cellMarginBottomPoints,
                    cellVerticalAlignment: table.cellVerticalAlignment,
                    tablePageBoundaryMode: table.tablePageBoundaryMode,
                    repeatsHeaderRow: table.repeatsHeaderRow,
                    tablePlacement: table.tablePlacement,
                    tableAnchor: anchor,
                    parent: table.parent,
                    backgroundZones: table.backgroundZones
                )
                if let anchor {
                    previousY = anchor.verticalPositionPoints
                        + max(
                            table.tablePlacement?.heightPoints ?? 0,
                            anchor.lineHeightPoints
                        )
                    previousWasFullWidth = (
                        table.tablePlacement?.widthPoints
                            ?? anchor.widthPoints
                    ) >= contentWidth * 0.75
                    hasPositionedLine = true
                }
                return copy(block, tableLocation: location)
            }

            var normalizedLines: [HWPDocumentLineLayout] = []
            normalizedLines.reserveCapacity(block.lineLayouts.count)
            for line in block.lineLayouts {
                let currentIsFullWidth = line.widthPoints >= contentWidth * 0.75
                let verticalReset = hasPositionedLine
                    && line.verticalPositionPoints
                        < previousY - max(line.lineHeightPoints, 8)
                var flags = line.flags
                if line.startsPage {
                    columnIndex = 0
                } else if line.startsColumn || verticalReset {
                    if currentIsFullWidth || previousWasFullWidth {
                        columnIndex = 0
                        flags |= 0x0000_0003
                    } else if columnIndex + 1 < columns.count {
                        columnIndex += 1
                        flags |= 0x0000_0002
                    } else {
                        columnIndex = 0
                        flags |= 0x0000_0003
                    }
                }
                normalizedLines.append(
                    copy(
                        line,
                        columnStartPoints: line.columnStartPoints
                            + columnOffset(columnIndex),
                        flags: flags
                    )
                )
                previousY = line.verticalPositionPoints
                    + max(line.lineHeightPoints, 12)
                previousWasFullWidth = currentIsFullWidth
                hasPositionedLine = true
            }
            return copy(block, lineLayouts: normalizedLines)
        }
    }

    private static func copy(
        _ line: HWPDocumentLineLayout,
        columnStartPoints: Double,
        flags: UInt32
    ) -> HWPDocumentLineLayout {
        HWPDocumentLineLayout(
            id: line.id,
            startCharacter: line.startCharacter,
            verticalPositionPoints: line.verticalPositionPoints,
            lineHeightPoints: line.lineHeightPoints,
            textHeightPoints: line.textHeightPoints,
            baselinePoints: line.baselinePoints,
            lineSpacingPoints: line.lineSpacingPoints,
            columnStartPoints: columnStartPoints,
            widthPoints: line.widthPoints,
            flags: flags,
            text: line.text,
            textRuns: line.textRuns,
            baselineAlignment: line.baselineAlignment,
            textInsetPoints: line.textInsetPoints,
            listMarker: line.listMarker,
            showsListMarker: line.showsListMarker,
            endsParagraph: line.endsParagraph
        )
    }

    private static func copy(
        _ block: HWPDocumentBlock,
        tableLocation: HWPDocumentTableLocation? = nil,
        lineLayouts: [HWPDocumentLineLayout]? = nil
    ) -> HWPDocumentBlock {
        HWPDocumentBlock(
            id: block.id,
            sectionPath: block.sectionPath,
            paragraphIndex: block.paragraphIndex,
            text: block.text,
            tableLocation: tableLocation ?? block.tableLocation,
            isEditable: block.isEditable,
            presentation: block.presentation,
            region: block.region,
            images: block.images,
            lineLayouts: lineLayouts ?? block.lineLayouts,
            canvasObjects: block.canvasObjects,
            layoutContainerID: block.layoutContainerID
        )
    }

    private static func splitAcrossPages(
        _ block: HWPDocumentBlock,
        contentHeight: Double
    ) -> [HWPDocumentBlock] {
        guard block.lineLayouts.count > 1 else {
            return [block]
        }
        var chunks: [[HWPDocumentLineLayout]] = [[]]
        var previousY = block.lineLayouts[0].verticalPositionPoints
        for line in block.lineLayouts {
            // A paragraph inside a table cell can continue on the next
            // physical page. HWP restarts the cached cell-local Y coordinate
            // at that boundary without setting the page-start flag. Within a
            // single cell paragraph the coordinate is otherwise monotonic,
            // so a backwards jump is an unambiguous continuation marker.
            let tableCellPageReset = block.tableLocation != nil
                && line.verticalPositionPoints + 0.5 < previousY
            let resetsPage = !chunks[chunks.count - 1].isEmpty
                && (line.startsPage
                    || tableCellPageReset
                    || (line.verticalPositionPoints < 24
                        && previousY > contentHeight * 0.68))
            if resetsPage { chunks.append([]) }
            chunks[chunks.count - 1].append(line)
            previousY = line.verticalPositionPoints
        }
        guard chunks.count > 1 else { return [block] }
        return chunks.enumerated().map { index, lines in
            HWPDocumentBlock(
                id: index == 0 ? block.id : "\(block.id)-page-fragment-\(index)",
                sectionPath: block.sectionPath,
                paragraphIndex: block.paragraphIndex,
                text: lines.map(\.text).joined(separator: "\n"),
                tableLocation: block.tableLocation,
                isEditable: block.isEditable,
                presentation: block.presentation,
                region: block.region,
                images: index == 0 ? block.images : [],
                lineLayouts: lines,
                canvasObjects: index == 0 ? block.canvasObjects : [],
                layoutContainerID: block.layoutContainerID
            )
        }
    }

    /// Lines inside a table cell use the page's vertical coordinate cache.
    /// A cell that continues on the next physical page can therefore reset
    /// from the bottom of one page to the top between two paragraph records,
    /// even though neither paragraph contains an internal reset. Preserve
    /// that boundary so long single-cell forms do not collapse two printed
    /// pages into one canvas page.
    private static func markTableContentPageBreaks(
        _ blocks: [HWPDocumentBlock],
        contentHeight: Double
    ) -> [HWPDocumentBlock] {
        struct CellKey: Hashable {
            let table: Int
            let row: Int
            let column: Int
        }
        struct CellPosition {
            let firstY: Double
            let bottom: Double
            let fragment: Int
        }

        var state: [CellKey: CellPosition] = [:]
        return blocks.map { block in
            guard let location = block.tableLocation,
                  location.parent == nil,
                  let firstLine = block.lineLayouts.first,
                  let lastLine = block.lineLayouts.last else {
                return block
            }
            let key = CellKey(
                table: location.table,
                row: location.row,
                column: location.column
            )
            let firstY = firstLine.verticalPositionPoints
            let bottom = lastLine.verticalPositionPoints
                + max(lastLine.lineHeightPoints, lastLine.textHeightPoints, 10)
            let previous = state[key]
            let splitInsideParagraph = startsGeneratedPage(block)
            let crossesCachedPage = splitInsideParagraph || (previous.map {
                firstY + 0.5 < $0.firstY
                    || ($0.bottom > contentHeight * 0.60
                        && firstY < contentHeight * 0.24
                        && firstY + max(firstLine.lineHeightPoints, 10)
                            < $0.bottom - contentHeight * 0.30)
            } ?? false)
            let fragment = (previous?.fragment ?? 0)
                + (crossesCachedPage ? 1 : 0)
            state[key] = CellPosition(
                firstY: firstY,
                bottom: max(bottom, crossesCachedPage ? 0 : previous?.bottom ?? 0),
                fragment: fragment
            )

            guard crossesCachedPage else { return block }
            return HWPDocumentBlock(
                id: block.id
                    + "-table-content-page-fragment-\(fragment)-start",
                sectionPath: block.sectionPath,
                paragraphIndex: block.paragraphIndex,
                text: block.text,
                tableLocation: block.tableLocation,
                isEditable: block.isEditable,
                presentation: block.presentation,
                region: block.region,
                images: block.images,
                lineLayouts: block.lineLayouts,
                canvasObjects: block.canvasObjects,
                layoutContainerID: block.layoutContainerID
            )
        }
    }

    /// Convert a row whose cached cell content restarts at Y=0 into two
    /// logical rows. The table paginator can then place the first slice in the
    /// remaining space and the continuation slice on the following page.
    /// This preserves the HWP writer's own line coordinates instead of
    /// squeezing both physical-page fragments into one oversized cell.
    private static func normalizeSplitTableRows(
        _ blocks: [HWPDocumentBlock]
    ) -> [HWPDocumentBlock] {
        var result: [HWPDocumentBlock] = []
        var index = 0
        while index < blocks.count {
            guard let first = blocks[index].tableLocation,
                  first.parent == nil else {
                result.append(blocks[index])
                index += 1
                continue
            }
            let tableID = first.table
            var end = index
            while end < blocks.count {
                guard let location = blocks[end].tableLocation else { break }
                if location.table == tableID || location.parent?.table == tableID {
                    end += 1
                } else {
                    break
                }
            }
            let group = Array(blocks[index..<end])
            guard let markerIndex = group.firstIndex(where: {
                $0.id.contains("-table-content-page-fragment-")
            }),
            let splitLocation = group[markerIndex].tableLocation,
            splitLocation.parent == nil,
            let totalHeight = splitLocation.cellHeightPoints,
            totalHeight > 1 else {
                result.append(contentsOf: group)
                index = end
                continue
            }

            let topLevel = group.filter {
                $0.tableLocation?.table == tableID
                    && $0.tableLocation?.parent == nil
            }
            let tracks = HWPTableTrackLayoutSolver.make(blocks: topLevel)
            let precedingRowsHeight = tracks.rowHeights
                .prefix(splitLocation.row)
                .reduce(0, +)
            let declaredSliceHeight = max(
                0,
                (splitLocation.tablePlacement?.heightPoints ?? 0)
                    - precedingRowsHeight
            )
            let cachedContentBottom = group[..<markerIndex]
                .filter {
                    $0.tableLocation?.table == tableID
                        && $0.tableLocation?.row == splitLocation.row
                        && $0.tableLocation?.column == splitLocation.column
                }
                .flatMap(\.lineLayouts)
                .map {
                    $0.verticalPositionPoints
                        + max($0.lineHeightPoints, $0.textHeightPoints, 10)
                }
                .max() ?? 0
            let consumedHeight = min(
                totalHeight - 1,
                max(
                    1,
                    declaredSliceHeight,
                    cachedContentBottom
                        + splitLocation.cellMarginTopPoints
                        + splitLocation.cellMarginBottomPoints
                )
            )
            let remainingHeight = max(1, totalHeight - consumedHeight)

            for (groupIndex, block) in group.enumerated() {
                guard let location = block.tableLocation else {
                    result.append(block)
                    continue
                }
                var row = location.row
                var rowSpan = location.rowSpan
                var cellHeight = location.cellHeightPoints
                var parent = location.parent
                if location.table == tableID, location.parent == nil {
                    if row == splitLocation.row, rowSpan == 1 {
                        let isContinuation = groupIndex >= markerIndex
                        row += isContinuation ? 1 : 0
                        cellHeight = isContinuation
                            ? remainingHeight
                            : consumedHeight
                    } else if row > splitLocation.row {
                        row += 1
                    } else if row + rowSpan > splitLocation.row + 1 {
                        // A merged cell that spans across the split row now
                        // covers one more grid row.
                        rowSpan += 1
                    }
                } else if let oldParent = parent,
                          oldParent.table == tableID,
                          oldParent.row >= splitLocation.row {
                    parent = HWPDocumentTableParentLocation(
                        table: oldParent.table,
                        row: oldParent.row + 1,
                        column: oldParent.column
                    )
                }
                let adjustedLocation = HWPDocumentTableLocation(
                    table: location.table,
                    row: row,
                    column: location.column,
                    paragraph: location.paragraph,
                    rowSpan: rowSpan,
                    columnSpan: location.columnSpan,
                    boxStyle: location.boxStyle,
                    cellWidthPoints: location.cellWidthPoints,
                    cellHeightPoints: cellHeight,
                    cellMarginLeftPoints: location.cellMarginLeftPoints,
                    cellMarginRightPoints: location.cellMarginRightPoints,
                    cellMarginTopPoints: location.cellMarginTopPoints,
                    cellMarginBottomPoints: location.cellMarginBottomPoints,
                    cellVerticalAlignment: location.cellVerticalAlignment,
                    tablePageBoundaryMode: location.tablePageBoundaryMode,
                    // A one-row table split only because its single cell
                    // crosses a page has no semantic header row. Repeating
                    // row zero would duplicate the entire first-page legal
                    // notice above the real continuation.
                    repeatsHeaderRow: location.repeatsHeaderRow
                        && tracks.rowHeights.count > 1,
                    tablePlacement: location.tablePlacement,
                    tableAnchor: location.tableAnchor,
                    parent: parent,
                    backgroundZones: location.backgroundZones
                )
                result.append(
                    HWPDocumentBlock(
                        id: block.id + "-table-row-continuation-normalized",
                        sectionPath: block.sectionPath,
                        paragraphIndex: block.paragraphIndex,
                        text: block.text,
                        tableLocation: adjustedLocation,
                        isEditable: block.isEditable,
                        presentation: block.presentation,
                        region: block.region,
                        images: block.images,
                        lineLayouts: block.lineLayouts,
                        canvasObjects: block.canvasObjects,
                        layoutContainerID: block.layoutContainerID
                    )
                )
            }
            index = end
        }
        return result
    }

    /// A legacy HWP table can span physical pages while retaining one table
    /// control and one placement record. Cell line coordinates are local to
    /// each row, so the page boundary must be recovered from the accumulated
    /// row heights. Rebase continuation rows so each page can render the same
    /// table control without a leading block of phantom rows.
    private static func splitOversizedTablesAcrossPages(
        _ blocks: [HWPDocumentBlock],
        contentHeight: Double,
        cellBoundaryContentHeight: Double
    ) -> [HWPDocumentBlock] {
        var result: [HWPDocumentBlock] = []
        var index = 0
        while index < blocks.count {
            guard let firstLocation = blocks[index].tableLocation,
                  firstLocation.parent == nil else {
                result.append(blocks[index])
                index += 1
                continue
            }
            let tableID = firstLocation.table
            var end = index
            while end < blocks.count {
                guard let location = blocks[end].tableLocation else { break }
                if location.table == tableID && location.parent == nil {
                    end += 1
                    continue
                }
                if location.parent?.table == tableID {
                    end += 1
                    continue
                }
                break
            }
            var group = Array(blocks[index..<end])
            var topLevel = group.filter {
                $0.tableLocation?.table == tableID
                    && $0.tableLocation?.parent == nil
            }
            var tracks = HWPTableTrackLayoutSolver.make(blocks: topLevel)
            let anchorY = max(
                firstLocation.tableAnchor?.verticalPositionPoints ?? 0,
                0
            )
            let usesCellBoundaryPagination = firstLocation.tablePageBoundaryMode == 1
            let startsInReservedFooterArea = firstLocation.tablePageBoundaryMode == 2
                && anchorY > cellBoundaryContentHeight * 0.75
            let effectiveContentHeight = usesCellBoundaryPagination
                    || startsInReservedFooterArea
                ? cellBoundaryContentHeight
                : contentHeight
            let repeatedHeaderHeight = firstLocation.repeatsHeaderRow
                ? tracks.rowHeights.first ?? 0
                : 0
            group = expandingTallTableRows(group, maximumHeight: max(72, effectiveContentHeight - repeatedHeaderHeight))
            topLevel = group.filter { $0.tableLocation?.table == tableID && $0.tableLocation?.parent == nil }
            tracks = HWPTableTrackLayoutSolver.make(blocks: topLevel)
            let firstCapacity = max(
                72,
                effectiveContentHeight - anchorY
            )
            let rowSlices = tableRowSlices(
                heights: tracks.rowHeights,
                firstCapacity: firstCapacity,
                continuationCapacity: max(
                    72,
                    effectiveContentHeight - repeatedHeaderHeight
                ),
                locations: topLevel.compactMap(\.tableLocation),
                // TABLE property bits 0-1: 0 no split, 1 split by cell,
                // 2 split freely. Hancom cuts merged cells at the page
                // boundary in mode 2 and repeats the merged label.
                cutsThroughMergedCells: firstLocation.tablePageBoundaryMode == 2
            )
            guard rowSlices.count > 1 else {
                result.append(contentsOf: group)
                index = end
                continue
            }

            var emittedIDs: Set<String> = []
            for (sliceIndex, rows) in rowSlices.enumerated() {
                func owningRow(_ block: HWPDocumentBlock) -> Int? {
                    guard let location = block.tableLocation else { return nil }
                    if location.table == tableID && location.parent == nil {
                        return location.row
                    } else if location.parent?.table == tableID {
                        return location.parent?.row
                    }
                    return nil
                }
                let repeatsHeader = sliceIndex > 0
                    && firstLocation.repeatsHeaderRow
                    && !rows.contains(0)
                let headerBlocks = repeatsHeader
                    ? group.filter { owningRow($0) == 0 }
                    : []
                let contentBlocks = group.filter { block in
                    owningRow(block).map(rows.contains) ?? false
                }
                // A vertically merged cell cut by the page boundary keeps
                // its label on the continuation page. Carry the top-level
                // cell over, anchored to the slice's first row.
                let spanningBlocks = sliceIndex > 0
                    ? group.filter { block in
                        guard let location = block.tableLocation,
                              location.table == tableID,
                              location.parent == nil else { return false }
                        return location.row < rows.lowerBound
                            && location.row + location.rowSpan > rows.lowerBound
                    }
                    : []
                let sliceBlocks = headerBlocks + spanningBlocks + contentBlocks
                let rowBase = repeatsHeader ? 1 : 0
                let sliceHeight = tracks.rowHeights[rows].reduce(0, +)
                    + (repeatsHeader ? repeatedHeaderHeight : 0)
                for (blockIndex, block) in sliceBlocks.enumerated() {
                    guard let location = block.tableLocation else { continue }
                    let isRepeatedHeader = repeatsHeader
                        && owningRow(block) == 0
                    var rebased = rebase(
                        location,
                        topLevelTable: tableID,
                        rowOffset: isRepeatedHeader ? 0 : rows.lowerBound,
                        rowBase: isRepeatedHeader ? 0 : rowBase,
                        continuation: sliceIndex > 0,
                        sliceHeight: sliceHeight
                    )
                    // A merged cell cut by the slice boundary keeps only the
                    // rows that fall inside this slice, and its declared
                    // height no longer applies: spreading the full merged
                    // height over the surviving rows would inflate them.
                    if !isRepeatedHeader,
                       location.table == tableID,
                       location.parent == nil {
                        let cellEnd = location.row + location.rowSpan
                        let cutAtStart = location.row < rows.lowerBound
                        let cutAtEnd = cellEnd > rows.upperBound
                        if cutAtStart || cutAtEnd {
                            let visibleStart = max(location.row, rows.lowerBound)
                            let visibleEnd = min(cellEnd, rows.upperBound)
                            rebased = rebased.replacingRow(
                                visibleStart - rows.lowerBound + rowBase,
                                rowSpan: max(1, visibleEnd - visibleStart),
                                cellHeightPoints: nil
                            )
                        }
                    }
                    let marker = sliceIndex > 0 && blockIndex == 0
                        ? "-table-page-fragment-\(sliceIndex)-start"
                        : "-table-page-fragment-\(sliceIndex)"
                    rebased.startsPageSlice = sliceIndex > 0 && blockIndex == 0
                    result.append(
                        HWPDocumentBlock(
                            id: emittedIDs.insert(block.id).inserted ? block.id : block.id + marker,
                            sectionPath: block.sectionPath,
                            paragraphIndex: block.paragraphIndex,
                            text: block.text,
                            tableLocation: rebased,
                            isEditable: block.isEditable,
                            presentation: block.presentation,
                            region: block.region,
                            images: block.images,
                            lineLayouts: block.lineLayouts,
                            canvasObjects: block.canvasObjects,
                            layoutContainerID: block.layoutContainerID
                        )
                    )
                }
            }
            index = end
        }
        return result
    }

    public static func tableRowSlices(
        heights: [Double],
        firstCapacity: Double,
        continuationCapacity: Double,
        locations: [HWPDocumentTableLocation],
        cutsThroughMergedCells: Bool = false
    ) -> [Range<Int>] {
        guard !heights.isEmpty else { return [0..<1] }
        var slices: [Range<Int>] = []
        if heights[0] > firstCapacity, heights[0] <= continuationCapacity {
            slices.append(0..<0)
        }
        var start = 0
        while start < heights.count {
            let capacity = slices.isEmpty ? firstCapacity : continuationCapacity
            var end = start
            var used = 0.0
            while end < heights.count {
                let next = max(heights[end], 1)
                if end > start && used + next > capacity { break }
                used += next
                end += 1
            }
            if end == start { end += 1 }

            // Never cut through a vertically merged cell that can fit on a
            // page. Prefer moving the boundary before the merged region.
            // Extending it past the page can absorb the following page and
            // was the source of missing pages in long qualification tables.
            // A merged cell taller than a whole page cannot be kept intact
            // anywhere; Hancom splits it at the page boundary and repeats
            // the merged label on the continuation, so let the cut through.
            while !cutsThroughMergedCells {
                let crossingStarts = locations.compactMap { location -> Int? in
                    let cellEnd = min(
                        heights.count,
                        location.row + location.rowSpan
                    )
                    guard location.row < end, cellEnd > end else { return nil }
                    let mergedHeight = heights[location.row..<cellEnd]
                        .reduce(0) { $0 + max($1, 1) }
                    guard mergedHeight <= continuationCapacity else { return nil }
                    return location.row
                }
                guard let earliest = crossingStarts.min() else { break }
                if earliest > start {
                    end = earliest
                } else {
                    end = locations
                        .filter { $0.row == start }
                        .map { min(heights.count, $0.row + $0.rowSpan) }
                        .max() ?? end
                    break
                }
            }
            slices.append(start..<min(end, heights.count))
            start = end
        }
        return slices
    }

    private static func rebase(
        _ location: HWPDocumentTableLocation,
        topLevelTable: Int,
        rowOffset: Int,
        rowBase: Int,
        continuation: Bool,
        sliceHeight: Double
    ) -> HWPDocumentTableLocation {
        let isTopLevel = location.table == topLevelTable
            && location.parent == nil
        let parent = location.parent.map { parent in
            HWPDocumentTableParentLocation(
                table: parent.table,
                row: parent.table == topLevelTable
                    ? max(0, parent.row - rowOffset + rowBase)
                    : parent.row,
                column: parent.column
            )
        }
        let anchor = location.tableAnchor.map { anchor in
            HWPDocumentTableAnchor(
                columnStartPoints: anchor.columnStartPoints,
                verticalPositionPoints: continuation && isTopLevel
                    ? 0
                    : anchor.verticalPositionPoints,
                widthPoints: anchor.widthPoints,
                lineHeightPoints: anchor.lineHeightPoints,
                paragraphAlignment: anchor.paragraphAlignment
            )
        }
        let placement = location.tablePlacement.map { placement in
            guard isTopLevel else { return placement }
            return HWPDocumentObjectPlacement(
                xPoints: placement.xPoints,
                yPoints: placement.yPoints,
                widthPoints: placement.widthPoints,
                heightPoints: max(sliceHeight, 1),
                zOrder: placement.zOrder,
                rotationDegrees: placement.rotationDegrees,
                flipHorizontal: placement.flipHorizontal,
                flipVertical: placement.flipVertical,
                isInline: placement.isInline,
                horizontalReference: placement.horizontalReference,
                verticalReference: placement.verticalReference,
                horizontalAlignment: placement.horizontalAlignment,
                verticalAlignment: placement.verticalAlignment,
                wrap: placement.wrap,
                marginLeftPoints: placement.marginLeftPoints,
                marginRightPoints: placement.marginRightPoints,
                marginTopPoints: placement.marginTopPoints,
                marginBottomPoints: placement.marginBottomPoints,
                inlineOriginIsResolved: placement.inlineOriginIsResolved
            )
        }
        return HWPDocumentTableLocation(
            table: location.table,
            row: isTopLevel
                ? max(0, location.row - rowOffset + rowBase)
                : location.row,
            column: location.column,
            paragraph: location.paragraph,
            rowSpan: location.rowSpan,
            columnSpan: location.columnSpan,
            boxStyle: location.boxStyle,
            cellWidthPoints: location.cellWidthPoints,
            cellHeightPoints: location.cellHeightPoints,
            cellMarginLeftPoints: location.cellMarginLeftPoints,
            cellMarginRightPoints: location.cellMarginRightPoints,
            cellMarginTopPoints: location.cellMarginTopPoints,
            cellMarginBottomPoints: location.cellMarginBottomPoints,
            cellVerticalAlignment: location.cellVerticalAlignment,
            tablePageBoundaryMode: location.tablePageBoundaryMode,
            repeatsHeaderRow: location.repeatsHeaderRow,
            tablePlacement: placement,
            tableAnchor: anchor,
            parent: parent,
            backgroundZones: location.backgroundZones
        )
    }

    private static func startsGeneratedPage(_ block: HWPDocumentBlock) -> Bool {
        if block.tableLocation?.startsPageSlice == true { return true }
        if block.id.contains("-table-page-fragment-") {
            return block.id.hasSuffix("-start")
        }
        if block.id.contains("-table-row-continuation-normalized") {
            return false
        }
        if block.id.contains("-table-content-page-fragment-") {
            return block.id.hasSuffix("-start")
        }
        guard let marker = block.id.range(of: "-page-fragment-") else {
            return false
        }
        guard let fragment = Int(block.id[marker.upperBound...]) else {
            // Tall table rows use `-page-fragment-cell-N` to identify cell
            // slices. Those slices share one table page and must not each
            // start a separate document page.
            return false
        }
        return fragment != 0
    }

    private static func paragraphKey(_ block: HWPDocumentBlock) -> String {
        "\(block.sectionPath)#\(block.paragraphIndex)"
    }

    private static func sectionIndex(for block: HWPDocumentBlock) -> Int {
        Int(block.sectionPath.filter(\.isNumber)) ?? 0
    }
}
