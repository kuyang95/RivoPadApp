import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Measures paragraphs that have no saved line cache, such as newly edited or
/// generated HWPX paragraphs. Existing cached page geometry stays authoritative.
@MainActor
public enum HWPFlowLayout {
    /// Bulk operations measure each edited cell once, then move each section's
    /// body once. Reflowing the whole tail for every match becomes quadratic.
    public static func reflowingEdits(_ blocks: [HWPDocumentBlock], before: [HWPDocumentBlock],
                              changedIDs: [String], layouts: [HWPDocumentPageLayout]) -> [HWPDocumentBlock] {
        let ids = Set(changedIDs)
        let old = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
        var result = HWPListFormatting.renumbering(blocks)
        var starts: [String: Int] = [:], tableSections: Set<String> = [], cells: Set<String> = []
        for index in blocks.indices where ids.contains(blocks[index].id) {
            let block = blocks[index]
            guard let original = old[block.id], needsReflow(from: original, to: block),
                  block.region.kind == .body, block.layoutContainerID == nil else { continue }
            if let cell = block.tableLocation {
                let key = "\(block.sectionPath):\(cell.table):\(cell.row):\(cell.column)"
                guard cells.insert(key).inserted else { continue }
                let updated = HWPTableEditing.reflow(result, before: before, startingAt: block.id,
                    layouts: layouts, reflowBody: false)
                guard updated != result else { continue }
                result = updated
                if let first = blocks.firstIndex(where: { $0.sectionPath == block.sectionPath && $0.tableLocation?.table == cell.table }),
                   let owner = blocks.indices.prefix(first).last(where: {
                       blocks[$0].sectionPath == block.sectionPath && blocks[$0].tableLocation == nil
                           && blocks[$0].region.kind == .body && blocks[$0].layoutContainerID == nil
                   }) {
                    starts[block.sectionPath] = min(starts[block.sectionPath] ?? owner, owner)
                    tableSections.insert(block.sectionPath)
                }
            } else { starts[block.sectionPath] = min(starts[block.sectionPath] ?? index, index) }
        }
        for (section, index) in starts.sorted(by: { $0.value < $1.value }) {
            result = reflowingBody(result, before: before, startingAt: result[index].id,
                layouts: layouts, reflowingTables: tableSections.contains(section))
        }
        return result
    }

    public static func reflowingEdit(_ blocks: [HWPDocumentBlock], before: [HWPDocumentBlock],
                             startingAt id: String, layouts: [HWPDocumentPageLayout]) -> [HWPDocumentBlock] {
        let blocks = HWPListFormatting.renumbering(blocks)
        if blocks.first(where: { $0.id == id })?.tableLocation != nil {
            return HWPTableEditing.reflow(blocks, before: before, startingAt: id, layouts: layouts)
        }
        return reflowingBody(blocks, before: before, startingAt: id, layouts: layouts)
    }

    public static func needsReflow(from old: HWPDocumentBlock, to new: HWPDocumentBlock) -> Bool {
        if old.text != new.text || old.presentation.list != new.presentation.list { return true }
        let a = old.presentation, b = new.presentation
        if a.leftMarginPoints != b.leftMarginPoints || a.rightMarginPoints != b.rightMarginPoints
            || a.firstLineIndentPoints != b.firstLineIndentPoints || a.spacingBeforePoints != b.spacingBeforePoints
            || a.spacingAfterPoints != b.spacingAfterPoints || a.lineSpacingPercent != b.lineSpacingPercent
            || a.pageBreakBefore != b.pageBreakBefore { return true }
        func metrics(_ block: HWPDocumentBlock) -> [HWPDocumentTextRun] {
            var result: [HWPDocumentTextRun] = []
            for var run in HWPDocumentFormatting.runs(in: block) {
                run.textColorRGB = nil
                run.backgroundColorRGB = nil
                run.isUnderlined = false
                run.isStruckThrough = false
                if let last = result.last, last.withText("") == run.withText("") {
                    result[result.count - 1].text += run.text
                } else { result.append(run) }
            }
            return result
        }
        return metrics(old) != metrics(new)
    }

    public static func resolvingMissingLines(_ source: [HWPDocumentBlock], layout: HWPDocumentPageLayout) -> [HWPDocumentBlock] {
        guard source.contains(where: { $0.lineLayouts.isEmpty }) else { return source }
        let bodyWidth = max(1, layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints)
        let bodyHeight = max(1, layout.heightPoints - layout.topMarginPoints - layout.bottomMarginPoints
            - layout.headerMarginPoints - layout.footerMarginPoints)
        var cursors: [String: Double] = [:]
        var result = source
        var lastOwner: HWPDocumentBlock?
        var generatedAnchors: [Int: HWPDocumentTableAnchor] = [:]
        for index in result.indices {
            let block = result[index]
            // Shape text uses its owner's local frame, not the page width.
            // Its existing renderer provides the container-specific fallback.
            if block.layoutContainerID != nil { continue }
            let cell = block.tableLocation
            let context = block.layoutContainerID ?? cell.map { "cell-\($0.table)-\($0.row)-\($0.column)" }
                ?? block.region.kind.rawValue
            let isBody = cell == nil && block.layoutContainerID == nil && block.region.kind == .body
            if let cell, cell.tableAnchor == nil, generatedAnchors[cell.table] == nil,
               let line = lastOwner?.lineLayouts.first {
                generatedAnchors[cell.table] = HWPDocumentTableAnchor(columnStartPoints: line.columnStartPoints,
                    verticalPositionPoints: line.verticalPositionPoints, widthPoints: line.widthPoints,
                    lineHeightPoints: line.lineHeightPoints,
                    paragraphAlignment: lastOwner?.presentation.alignment ?? .leading)
            }
            if !block.lineLayouts.isEmpty {
                if let last = block.lineLayouts.last {
                    cursors[context] = last.verticalPositionPoints + last.lineHeightPoints + last.lineSpacingPoints
                }
                if isBody { lastOwner = block }
                continue
            }
            var y = cursors[context] ?? 0
            if block.presentation.pageBreakBefore && isBody { y = 0 }
            y += block.presentation.spacingBeforePoints
            let width = max(1, (cell?.cellWidthPoints ?? layout.columnLayout.columns.first?.widthPoints ?? bodyWidth)
                - (cell?.cellMarginLeftPoints ?? 0) - (cell?.cellMarginRightPoints ?? 0)
                - block.presentation.leftMarginPoints - block.presentation.rightMarginPoints)
            let followingTable = index + 1 < result.count ? result[index + 1].tableLocation : nil
            let tableHeight = block.text.isEmpty && followingTable?.tableAnchor == nil
                ? followingTable?.tablePlacement?.heightPoints ?? 0 : 0
            let objectHeight = block.canvasObjects.filter { $0.placement.isInline }.map { $0.placement.heightPoints }.max() ?? 0
            let lines = measure(block, width: width, startY: y,
                pageHeight: isBody ? bodyHeight : nil, minimumHeight: max(tableHeight, objectHeight))
            result[index] = block.withLayout(lines: lines)
            if let last = lines.last {
                cursors[context] = last.verticalPositionPoints + last.lineHeightPoints
                    + last.lineSpacingPoints + block.presentation.spacingAfterPoints
            }
            if isBody { lastOwner = result[index] }
        }
        for index in result.indices {
            guard let location = result[index].tableLocation, location.tableAnchor == nil,
                  let anchor = generatedAnchors[location.table] else { continue }
            result[index] = result[index].withLayout(tableLocation: location.withAnchor(anchor))
        }
        return result
    }

    /// Reflows the body after an edit. Cell coordinates stay local to their table;
    /// their body anchor follows the paragraph that owns the table control.
    public static func reflowingBody(_ blocks: [HWPDocumentBlock], before: [HWPDocumentBlock],
                             startingAt id: String, layouts: [HWPDocumentPageLayout],
                             reflowingTables: Bool = false, removedTableBottoms: [String: Double] = [:]) -> [HWPDocumentBlock] {
        guard let changed = blocks.first(where: { $0.id == id }), changed.tableLocation == nil,
              changed.region.kind == .body,
              let sectionIndex = HWPPageSetup.sectionIndex(changed.sectionPath),
              let layout = layouts.first(where: { $0.sectionIndex == sectionIndex }) else { return blocks }
        if layout.columnLayout.columns.count > 1 {
            return reflowingSection(blocks, sectionIndex: sectionIndex, layout: layout)
        }
        let old = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
        let height = max(1, layout.heightPoints - layout.topMarginPoints - layout.bottomMarginPoints)
        let width = max(1, layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints)
        var result = blocks, active = false
        var y = 0.0, previousOld: HWPDocumentBlock?, owner: HWPDocumentBlock?
        var followsTable = false
        var oldTableBottom: Double?
        var reservedTables: Set<Int> = []
        let tables = Dictionary(grouping: blocks.filter {
            $0.sectionPath == changed.sectionPath && $0.tableLocation?.parent == nil && $0.tableLocation != nil
        }, by: { $0.tableLocation!.table })
        for index in result.indices {
            let block = result[index]
            guard block.sectionPath == changed.sectionPath, block.region.kind == .body,
                  block.layoutContainerID == nil else { continue }
            if let cell = block.tableLocation {
                if active, cell.parent == nil, let line = owner?.lineLayouts.first {
                    let anchor = HWPDocumentTableAnchor(columnStartPoints: line.columnStartPoints,
                        verticalPositionPoints: line.verticalPositionPoints, widthPoints: line.widthPoints,
                        lineHeightPoints: line.lineHeightPoints, paragraphAlignment: owner?.presentation.alignment ?? .leading)
                    result[index] = block.withLayout(tableLocation: cell.withAnchor(anchor))
                    if reservedTables.insert(cell.table).inserted {
                        let members = tables[cell.table] ?? []
                        let placementHeight = cell.tablePlacement?.heightPoints ?? 0
                        var rows: [Int: Double] = [:]
                        for member in members {
                            guard let location = member.tableLocation else { continue }
                            let rowHeight = (location.cellHeightPoints ?? 0) / Double(location.rowSpan)
                            for row in location.row..<(location.row + location.rowSpan) {
                                rows[row] = max(rows[row] ?? 0, rowHeight)
                            }
                        }
                        let tableHeight = max(placementHeight, rows.values.reduce(0, +))
                        if reflowingTables {
                            y = HWPTableEditing.finalPageBottom(members, anchorY: line.verticalPositionPoints, layout: layout)
                            let oldMembers = before.filter { $0.sectionPath == block.sectionPath && $0.tableLocation?.table == cell.table }
                            oldTableBottom = oldMembers.isEmpty ? nil : HWPTableEditing.finalPageBottom(oldMembers,
                                anchorY: oldMembers.first?.tableLocation?.tableAnchor?.verticalPositionPoints ?? 0, layout: layout)
                        } else {
                            y = max(y, line.verticalPositionPoints + tableHeight)
                        }
                    }
                    followsTable = true
                }
                continue
            }
            let original = old[block.id] ?? block.sourceParagraphID.flatMap { old[$0] }
            if block.id == id {
                active = true
                y = original?.lineLayouts.first?.verticalPositionPoints ?? block.presentation.spacingBeforePoints
            }
            guard active else { previousOld = original; owner = block; continue }
            if block.id != id {
                var gap = block.presentation.spacingBeforePoints
                if let previousOld, let bottom = removedTableBottoms[previousOld.id], let first = original?.lineLayouts.first {
                    // Removing a table releases its height; only keep the
                    // authored gap after its last page, not the entire table.
                    gap = max(gap, first.verticalPositionPoints - bottom)
                } else if reflowingTables, followsTable, let oldTableBottom,
                   let first = original?.lineLayouts.first {
                    gap = max(gap, first.verticalPositionPoints - oldTableBottom)
                } else if let original, let previousOld, original.id != previousOld.id,
                   let first = original.lineLayouts.first, let last = previousOld.lineLayouts.last {
                    // Keep authored blank space, but allow old automatic page boundaries to move.
                    gap = max(gap, first.verticalPositionPoints - last.verticalPositionPoints
                        - last.lineHeightPoints - last.lineSpacingPoints)
                }
                y += gap
            }
            if block.presentation.pageBreakBefore
                || (!reflowingTables && followsTable && (original?.lineLayouts.first?.startsPage == true
                    || (original?.lineLayouts.first?.verticalPositionPoints ?? 0) < (previousOld?.lineLayouts.first?.verticalPositionPoints ?? 0))) {
                y = height
            }
            followsTable = false
            let lines: [HWPDocumentLineLayout]
            if HWPParagraphEditing.supports(block) {
                let available = width - block.presentation.leftMarginPoints - block.presentation.rightMarginPoints
                lines = measure(block, width: max(1, available), startY: y, pageHeight: height, minimumHeight: 0)
            } else {
                // Positioned controls retain their own geometry; translate only the paragraph anchor.
                let firstY = block.lineLayouts.first?.verticalPositionPoints ?? 0
                let offset = y >= height ? -firstY : y - firstY
                lines = block.lineLayouts.enumerated().map { offsetIndex, line in
                    line.positioned(y: max(0, line.verticalPositionPoints + offset),
                        flags: offsetIndex == 0 && y >= height ? line.flags | 1 : line.flags)
                }
            }
            result[index] = block.withLayout(lines: lines)
            if let last = lines.last {
                y = last.verticalPositionPoints + last.lineHeightPoints + last.lineSpacingPoints
                    + block.presentation.spacingAfterPoints
            }
            owner = result[index]
            previousOld = original
        }
        return result
    }

    /// Rebuilds a plain section from its first body paragraph and lets text
    /// continue through each column before starting a new page. Cached HWP
    /// horizontal positions remain column-local; the canvas translates them.
    public static func reflowingSection(_ blocks: [HWPDocumentBlock], sectionIndex: Int,
                                 layout: HWPDocumentPageLayout) -> [HWPDocumentBlock] {
        let indices = blocks.indices.filter {
            HWPPageSetup.sectionIndex(blocks[$0].sectionPath) == sectionIndex
                && blocks[$0].region.kind == .body && blocks[$0].layoutContainerID == nil
        }
        guard !indices.isEmpty,
              indices.allSatisfy({ blocks[$0].tableLocation == nil && blocks[$0].canvasObjects.isEmpty }) else {
            return blocks
        }
        let bodyWidth = max(1, layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints)
        let columns = layout.columnLayout.columns.isEmpty
            ? [HWPDocumentColumn(xPoints: 0, widthPoints: bodyWidth)] : layout.columnLayout.columns
        guard let narrowest = columns.map(\.widthPoints).min(),
              let widest = columns.map(\.widthPoints).max(),
              widest - narrowest < 0.03 else { return blocks }
        let pageHeight = max(1, layout.heightPoints - layout.topMarginPoints - layout.bottomMarginPoints)
        var result = blocks
        var columnIndex = 0
        var y = 0.0
        var wroteLine = false

        func advancedBoundary() -> UInt32 {
            if columnIndex + 1 < columns.count {
                columnIndex += 1
                y = 0
                return 2
            }
            columnIndex = 0
            y = 0
            return 1
        }

        for index in indices {
            let block = result[index]
            var pendingBoundary: UInt32 = 0
            if block.presentation.pageBreakBefore, wroteLine {
                columnIndex = 0
                y = 0
                pendingBoundary = 1
            }
            y += block.presentation.spacingBeforePoints
            let column = columns[columnIndex]
            let available = max(1, column.widthPoints
                - block.presentation.leftMarginPoints - block.presentation.rightMarginPoints)
            let measured = measure(block, width: available, startY: 0,
                pageHeight: nil, minimumHeight: 0)
            var lines: [HWPDocumentLineLayout] = []
            lines.reserveCapacity(measured.count)
            for measuredLine in measured {
                if y > 0, y + measuredLine.lineHeightPoints > pageHeight {
                    pendingBoundary = advancedBoundary()
                }
                let flags = (measuredLine.flags & ~UInt32(3)) | pendingBoundary
                lines.append(HWPDocumentLineLayout(
                    id: measuredLine.id,
                    startCharacter: measuredLine.startCharacter,
                    verticalPositionPoints: y,
                    lineHeightPoints: measuredLine.lineHeightPoints,
                    textHeightPoints: measuredLine.textHeightPoints,
                    baselinePoints: measuredLine.baselinePoints,
                    lineSpacingPoints: measuredLine.lineSpacingPoints,
                    columnStartPoints: measuredLine.columnStartPoints,
                    widthPoints: measuredLine.widthPoints,
                    flags: flags,
                    text: measuredLine.text,
                    textRuns: measuredLine.textRuns,
                    baselineAlignment: measuredLine.baselineAlignment,
                    textInsetPoints: measuredLine.textInsetPoints,
                    listMarker: measuredLine.listMarker,
                    showsListMarker: measuredLine.showsListMarker,
                    endsParagraph: measuredLine.endsParagraph
                ))
                pendingBoundary = 0
                y += measuredLine.lineHeightPoints + measuredLine.lineSpacingPoints
                wroteLine = true
            }
            y += block.presentation.spacingAfterPoints
            result[index] = block.withLayout(lines: lines)
        }
        return result
    }

    public static func measure(_ block: HWPDocumentBlock, width: Double, startY: Double,
                                pageHeight: Double?, minimumHeight: Double) -> [HWPDocumentLineLayout] {
        let runs = HWPDocumentFormatting.runs(in: block)
        let marker = block.presentation.list?.marker(in: block) ?? block.lineLayouts.first?.listMarker
        let typesetter = DocumentEnginePlatform.textSession(HWPTextMeasurementRequest(
            runs: runs, fallbackFontSize: 10, policy: .flow))
        let source = block.text as NSString
        var result: [HWPDocumentLineLayout] = []
        var offset = 0, rawPosition = 0
        var y = startY
        var pageIndex = 0
        let squareExclusions = block.canvasObjects.compactMap { object -> CGRect? in
            let placement = object.placement
            guard !placement.isInline, placement.wrap == .square,
                  placement.horizontalReference == .paragraph || placement.horizontalReference == .column,
                  placement.verticalReference == .paragraph,
                  placement.horizontalAlignment == .start,
                  placement.verticalAlignment == .start else { return nil }
            let angle = placement.rotationDegrees * .pi / 180
            let rotatedWidth = abs(cos(angle)) * placement.widthPoints
                + abs(sin(angle)) * placement.heightPoints
            let rotatedHeight = abs(sin(angle)) * placement.widthPoints
                + abs(cos(angle)) * placement.heightPoints
            return CGRect(
                x: placement.xPoints + (placement.widthPoints - rotatedWidth) / 2
                    - placement.marginLeftPoints - block.presentation.leftMarginPoints,
                y: startY + placement.yPoints + (placement.heightPoints - rotatedHeight) / 2
                    - placement.marginTopPoints,
                width: rotatedWidth + placement.marginLeftPoints + placement.marginRightPoints,
                height: rotatedHeight + placement.marginTopPoints + placement.marginBottomPoints)
        }
        let estimatedLineHeight = max(8, runs.compactMap(\.fontSizePoints).max() ?? 10)
        var needsTrailingLine = block.text.hasSuffix("\n")
        repeat {
            let isTrailingLine = offset == source.length
            let indent = result.isEmpty ? block.presentation.firstLineIndentPoints : 0
            var lineStart = 0.0
            var lineWidth = max(1, width - indent)
            if pageIndex == 0 {
                // A floating square object excludes its rotated bounds from each
                // intersecting text line. The widest free strip keeps line
                // geometry representable by the saved HWPX line cache.
                var strips: [(Double, Double)] = [(0, lineWidth)]
                var nextClearY: Double?
                for exclusion in squareExclusions where Double(exclusion.minY) < y + estimatedLineHeight
                    && Double(exclusion.maxY) > y {
                    let left = Double(exclusion.minX) - indent
                    let right = Double(exclusion.maxX) - indent
                    nextClearY = min(nextClearY ?? Double(exclusion.maxY), Double(exclusion.maxY))
                    strips = strips.flatMap { strip -> [(Double, Double)] in
                        if right <= strip.0 || left >= strip.1 { return [strip] }
                        var remaining: [(Double, Double)] = []
                        if left > strip.0 { remaining.append((strip.0, min(left, strip.1))) }
                        if right < strip.1 { remaining.append((max(right, strip.0), strip.1)) }
                        return remaining
                    }
                }
                if let widest = strips.max(by: { $0.1 - $0.0 < $1.1 - $1.0 }),
                   widest.1 - widest.0 >= estimatedLineHeight * 2 {
                    lineStart = widest.0
                    lineWidth = widest.1 - widest.0
                } else if let nextClearY, nextClearY > y {
                    y = nextClearY
                }
            }
            var length = offset < source.length ? typesetter.suggestLineBreak(atUTF16: offset, widthPoints: max(1, lineWidth - (marker?.reservedWidthPoints ?? 0))) : 0
            if length <= 0 && offset < source.length { length = source.rangeOfComposedCharacterSequence(at: offset).length }
            length = min(length, source.length - offset)
            let range = NSRange(location: offset, length: length)
            let fragment = source.substring(with: range)
            var runOffset = 0
            let lineRuns = runs.compactMap { run -> HWPDocumentTextRun? in
                let runRange = NSRange(location: runOffset, length: run.text.utf16.count)
                runOffset += runRange.length
                let intersection = NSIntersectionRange(range, runRange)
                return intersection.length > 0 ? run.withText(source.substring(with: intersection).replacingOccurrences(of: "\n", with: "")) : nil
            }
            let fontSize = lineRuns.compactMap(\.fontSizePoints).max() ?? runs.first?.fontSizePoints ?? 10
            // An inline or wrapped object reserves space once at its anchor line.
            // Repeating that height for every line expands a normal paragraph into pages.
            let reservedHeight = result.isEmpty ? minimumHeight : 0
            let height = typesetter.scriptLineHeight(inUTF16: range, runs: lineRuns,
                minimumPoints: max(fontSize, reservedHeight))
            let spacing = block.presentation.lineSpacingPercent.map { max(0, fontSize * ($0 / 100 - 1)) }
                ?? block.lineLayouts.first?.lineSpacingPoints ?? fontSize * 0.6
            var flags: UInt32 = 0
            if let pageHeight, y > 0, y + height > pageHeight {
                y = 0; flags = 1; pageIndex += 1
            }
            result.append(HWPDocumentLineLayout(id: "\(block.id)-flow-\(result.count)", startCharacter: rawPosition,
                verticalPositionPoints: y, lineHeightPoints: height, textHeightPoints: fontSize,
                baselinePoints: fontSize * 0.85, lineSpacingPoints: spacing,
                columnStartPoints: block.presentation.leftMarginPoints + indent + lineStart,
                widthPoints: lineWidth,
                flags: flags, text: fragment.replacingOccurrences(of: "\n", with: ""), textRuns: lineRuns,
                listMarker: marker, showsListMarker: result.isEmpty,
                endsParagraph: NSMaxRange(range) == source.length || fragment.hasSuffix("\n")))
            y += height + spacing
            offset += length
            rawPosition += fragment.utf16.count + fragment.filter { $0 == "\t" }.count * 7
            if isTrailingLine { needsTrailingLine = false }
        } while offset < source.length || needsTrailingLine
        return result
    }
}

private extension HWPDocumentTableLocation {
    func withAnchor(_ anchor: HWPDocumentTableAnchor) -> HWPDocumentTableLocation {
        HWPDocumentTableLocation(table: table, row: row, column: column, paragraph: paragraph,
            rowSpan: rowSpan, columnSpan: columnSpan, boxStyle: boxStyle,
            cellWidthPoints: cellWidthPoints, cellHeightPoints: cellHeightPoints,
            cellMarginLeftPoints: cellMarginLeftPoints, cellMarginRightPoints: cellMarginRightPoints,
            cellMarginTopPoints: cellMarginTopPoints, cellMarginBottomPoints: cellMarginBottomPoints,
            cellVerticalAlignment: cellVerticalAlignment, tablePageBoundaryMode: tablePageBoundaryMode,
            repeatsHeaderRow: repeatsHeaderRow, tablePlacement: tablePlacement, tableAnchor: anchor, parent: parent,
            backgroundZones: backgroundZones)
    }
}

nonisolated extension HWPDocumentLineLayout {
    public func positioned(y: Double, flags: UInt32? = nil) -> HWPDocumentLineLayout {
        var copy = HWPDocumentLineLayout(id: id, startCharacter: startCharacter,
            verticalPositionPoints: y, lineHeightPoints: lineHeightPoints, textHeightPoints: textHeightPoints,
            baselinePoints: baselinePoints, lineSpacingPoints: lineSpacingPoints,
            columnStartPoints: columnStartPoints, widthPoints: widthPoints, flags: flags ?? self.flags,
            text: text, textRuns: textRuns)
        copy.baselineAlignment = baselineAlignment
        copy.textInsetPoints = textInsetPoints
        copy.listMarker = listMarker
        copy.showsListMarker = showsListMarker
        copy.endsParagraph = endsParagraph
        return copy
    }
}
