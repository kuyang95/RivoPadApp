import Foundation

extension HWPDocumentTableLocation {
    /// Copy with a different grid row and span. Used when a merged cell is
    /// carried onto a continuation slice.
    public nonisolated func replacingRow(
        _ row: Int,
        rowSpan: Int,
        cellHeightPoints: Double?
    ) -> HWPDocumentTableLocation {
        HWPDocumentTableLocation(
            table: table,
            row: row,
            column: column,
            paragraph: paragraph,
            rowSpan: rowSpan,
            columnSpan: columnSpan,
            boxStyle: boxStyle,
            cellWidthPoints: cellWidthPoints,
            cellHeightPoints: cellHeightPoints,
            cellMarginLeftPoints: cellMarginLeftPoints,
            cellMarginRightPoints: cellMarginRightPoints,
            cellMarginTopPoints: cellMarginTopPoints,
            cellMarginBottomPoints: cellMarginBottomPoints,
            cellVerticalAlignment: cellVerticalAlignment,
            tablePageBoundaryMode: tablePageBoundaryMode,
            repeatsHeaderRow: repeatsHeaderRow,
            tablePlacement: tablePlacement,
            tableAnchor: tableAnchor,
            parent: parent,
            backgroundZones: backgroundZones
        )
    }
}
