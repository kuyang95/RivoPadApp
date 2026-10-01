import Foundation

/// HWP's binary records and HWPX XML share this lossless text/geometry
/// projection after parsing. Do not infer form labels or editable targets here.
nonisolated enum HWPAISource {
    static func blocks(_ blocks: [HWPDocumentBlock]) -> [WordDocumentBlock] {
        blocks.map { block in
            WordDocumentBlock(id: block.id, paragraphIndex: block.paragraphIndex,
                text: block.text, styleID: nil, isNumbered: false,
                tableLocation: block.tableLocation.map { location in
                    WordDocumentTableLocation(table: location.table, row: location.row,
                        column: location.column, paragraph: location.paragraph,
                        rowSpan: location.rowSpan, columnSpan: location.columnSpan,
                        sectionPath: block.sectionPath,
                        parent: location.parent.map { .init(table: $0.table, row: $0.row, column: $0.column) })
                }, isEditable: block.isEditable)
        }
    }
}
