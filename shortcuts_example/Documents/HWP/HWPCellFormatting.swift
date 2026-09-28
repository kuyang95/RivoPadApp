import Foundation

nonisolated struct HWPCellFormat: Hashable, Sendable {
    var box: HWPDocumentBoxStyle
    var vertical: HWPDocumentRelativeAlignment

    init(_ cell: HWPDocumentTableLocation) {
        box = cell.boxStyle ?? HWPDocumentBoxStyle()
        vertical = cell.cellVerticalAlignment
    }

    mutating func setFill(_ rgb: UInt32?) {
        box = HWPDocumentBoxStyle(left: box.left, right: box.right, top: box.top, bottom: box.bottom,
            backgroundColorRGB: rgb.map { $0 & 0xFFFFFF })
    }

    mutating func setBorder(_ side: Int, line: HWPDocumentBorderLine) {
        box = HWPDocumentBoxStyle(left: side == 0 ? line : box.left, right: side == 1 ? line : box.right,
            top: side == 2 ? line : box.top, bottom: side == 3 ? line : box.bottom,
            backgroundColorRGB: box.backgroundColorRGB, backgroundImage: box.backgroundImage,
            backgroundImageFillMode: box.backgroundImageFillMode)
    }

    var borders: [HWPDocumentBorderLine] { [box.left, box.right, box.top, box.bottom] }

    func matches(_ other: HWPCellFormat) -> Bool {
        vertical == other.vertical && box.backgroundColorRGB == other.box.backgroundColorRGB
            && box.backgroundImage == other.box.backgroundImage
            && zip(borders, other.borders).allSatisfy { a, b in
                a.isVisible == b.isVisible && (!a.isVisible || (a.kind == b.kind
                    && abs(a.widthPoints - b.widthPoints) < 0.02 && a.colorRGB == b.colorRGB))
            }
    }
}

nonisolated enum HWPCellFormatting {
    static let widthsMM: [Double] = [0.1, 0.3, 0.5, 1]

    static func supports(_ block: HWPDocumentBlock) -> Bool {
        block.isEditable && block.tableLocation != nil
            && block.region.kind == .body && block.layoutContainerID == nil
    }

    static func sameCell(_ a: HWPDocumentBlock, _ b: HWPDocumentBlock) -> Bool {
        guard let x = a.tableLocation, let y = b.tableLocation else { return false }
        return a.sectionPath == b.sectionPath && x.table == y.table && x.parent == y.parent
            && x.row == y.row && x.column == y.column
    }

    static func matches(_ a: HWPDocumentBlock, _ b: HWPDocumentBlock) -> Bool {
        guard let x = a.tableLocation, let y = b.tableLocation else {
            return (a.tableLocation == nil) == (b.tableLocation == nil)
        }
        return HWPCellFormat(x).matches(HWPCellFormat(y))
    }

    static func apply(_ format: HWPCellFormat, to block: HWPDocumentBlock) -> HWPDocumentBlock {
        guard supports(block), let cell = block.tableLocation,
              [.start, .center, .end].contains(format.vertical) else { return block }
        return block.withLayout(tableLocation: cell.withCellFormat(format))
    }

    /// A cell owns its paragraph list; its appearance cannot vary by paragraph.
    static func propagating(_ edited: HWPDocumentBlock, from original: HWPDocumentBlock,
                            in blocks: [HWPDocumentBlock]) -> [HWPDocumentBlock] {
        guard supports(edited), !matches(edited, original), let cell = edited.tableLocation else { return blocks }
        return blocks.map { sameCell($0, edited) ? $0.withLayout(tableLocation: $0.tableLocation!.withCellFormat(HWPCellFormat(cell))) : $0 }
    }
}

nonisolated extension HWPDocumentTableLocation {
    func withCellFormat(_ format: HWPCellFormat) -> HWPDocumentTableLocation {
        var result = HWPDocumentTableLocation(table: table, row: row, column: column, paragraph: paragraph,
            rowSpan: rowSpan, columnSpan: columnSpan, boxStyle: format.box,
            cellWidthPoints: cellWidthPoints, cellHeightPoints: cellHeightPoints,
            cellMarginLeftPoints: cellMarginLeftPoints, cellMarginRightPoints: cellMarginRightPoints,
            cellMarginTopPoints: cellMarginTopPoints, cellMarginBottomPoints: cellMarginBottomPoints,
            cellVerticalAlignment: format.vertical, tablePageBoundaryMode: tablePageBoundaryMode,
            repeatsHeaderRow: repeatsHeaderRow, tablePlacement: tablePlacement, tableAnchor: tableAnchor,
            parent: parent, backgroundZones: backgroundZones)
        result.startsPageSlice = startsPageSlice
        return result
    }
}
