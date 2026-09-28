import Foundation

nonisolated enum HWPTableInsertion {
    struct Selection: Identifiable, Sendable {
        let id = UUID()
        let blockID: String
        let text: String
        let caret: Int
        let width: Double
    }
    struct Request: Sendable {
        let selection: Selection
        let rows: Int
        let columns: Int
        var isValid: Bool {
            (1...20).contains(rows) && (1...20).contains(columns)
                && selection.width.isFinite && selection.width >= Double(columns) * 20 && selection.width <= 4_000
        }
        var columnWidths: [Double] {
            let total = Int((selection.width * 100).rounded()), basic = total / columns
            return (0..<columns).map { Double(basic + ($0 < total % columns ? 1 : 0)) / 100 }
        }
        static let rowHeight = 28.0
    }
    static func selection(blocks: [HWPDocumentBlock], selectedID: String?, range: NSRange,
                          layouts: [HWPDocumentPageLayout]) -> Selection? {
        let block = selectedID.flatMap { id in blocks.first { $0.id == id } }
            ?? (blocks.count == 1 && blocks[0].text.isEmpty ? blocks[0] : nil)
        guard let block, HWPParagraphEditing.supports(block), block.presentation.list == nil,
              !block.lineLayouts.contains(where: { $0.listMarker != nil }), range.length == 0,
              range.location >= 0, range.location <= block.text.utf16.count,
              (block.text.indices.map { $0.utf16Offset(in: block.text) } + [block.text.utf16.count]).contains(range.location),
              let layout = layouts.first(where: { $0.sectionIndex == HWPPageSetup.sectionIndex(block.sectionPath) }),
              layout.columnLayout.columns.count <= 1 else { return nil }
        return Selection(blockID: block.id, text: block.text, caret: range.location,
                         width: layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints)
    }

    @MainActor static func applying(_ request: Request, source: HWPTableStructureDocument,
                                    drafts: [HWPDocumentBlock]) async throws -> HWPTableStructureDocument.Result {
        guard request.isValid, drafts.count <= 20_000 - request.rows * request.columns - 2 else { throw HWPDocumentEditingError.limitExceeded }
        guard let index = drafts.firstIndex(where: { $0.id == request.selection.blockID }),
              drafts[index].text == request.selection.text,
              let valid = selection(blocks: drafts, selectedID: request.selection.blockID,
                                    range: .init(location: request.selection.caret, length: 0), layouts: source.layouts),
              abs(valid.width - request.selection.width) < 0.03 else { throw HWPDocumentEditingError.staleDocument }
        let (prepared, changed, ownerIndex) = try await Task.detached(priority: .userInitiated) {
            let base = try HWPTableStructureDocument.load(source.serialized(drafts))
            guard base.blocks.indices.contains(index), base.blocks[index].text == request.selection.text,
                  let split = HWPParagraphEditing.apply(.split(.init(location: request.selection.caret, length: 0)),
                    draft: base.blocks[index], to: base.blocks),
                  let suffix = split.blocks.first(where: { $0.id == split.focusedID }),
                  let second = HWPParagraphEditing.apply(.split(.init(location: 0, length: 0)), draft: suffix, to: split.blocks) else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            // A separate empty paragraph owns the block table. Its neutral
            // styles also supply valid font/paragraph references for every cell.
            var blocks = second.blocks
            guard let ownerIndex = blocks.firstIndex(where: { $0.id == suffix.id }) else { throw HWPDocumentEditingError.staleDocument }
            for command in [HWPFormattingCommand.clearCharacterFormatting, .alignment(.leading),
                            .paragraph(left: 0, right: 0, indent: 0, before: 0, after: 0, linePercent: 160)] {
                blocks[ownerIndex] = HWPDocumentFormatting.apply(command, to: blocks[ownerIndex], range: .init(location: 0, length: 0))
            }
            let prepared = try HWPTableStructureDocument.load(base.serialized(blocks))
            let data = try HWPTableInsertionWriter.apply(request, to: prepared, ownerIndex: ownerIndex)
            return (prepared, try HWPTableStructureDocument.load(data), ownerIndex)
        }.value
        let cellCount = request.rows * request.columns
        guard changed.blocks.count == prepared.blocks.count + cellCount,
              let layout = changed.layouts.first(where: { $0.sectionIndex == HWPPageSetup.sectionIndex(changed.blocks[ownerIndex].sectionPath) }) else {
            throw HWPDocumentEditingError.cannotSave
        }
        let cells = (ownerIndex + 1)..<(ownerIndex + 1 + cellCount)
        var before: [HWPDocumentBlock] = []
        for position in changed.blocks.indices {
            if cells.contains(position) {
                let cell = changed.blocks[position]
                let address = position - cells.lowerBound
                guard cell.isEditable, cell.text.isEmpty, cell.tableLocation?.row == address / request.columns,
                      cell.tableLocation?.column == address % request.columns else { throw HWPDocumentEditingError.cannotSave }
            } else {
                let old = prepared.blocks[position > ownerIndex ? position - cellCount : position], current = changed.blocks[position]
                guard HWPDocumentFormatting.matches(current, old) else { throw HWPDocumentEditingError.cannotSave }
                // Retained table numbers and paragraph IDs can shift on insertion.
                before.append(current.withLayout(lines: old.lineLayouts))
            }
        }
        let section = changed.blocks[ownerIndex].sectionPath
        func resolved(_ blocks: [HWPDocumentBlock]) -> [HWPDocumentBlock] {
            let indices = blocks.indices.filter { blocks[$0].sectionPath == section }
            let values = HWPFlowLayout.resolvingMissingLines(indices.map { blocks[$0] }, layout: layout)
            var result = blocks
            for (offset, index) in indices.enumerated() { result[index] = values[offset] }
            return result
        }
        before = resolved(before)
        var flowed = resolved(changed.blocks)
        // Empty cells share the same typography, so measuring one cell in each
        // row establishes the row's minimum height without quadratic work.
        for row in 0..<request.rows {
            flowed = HWPTableEditing.reflow(flowed, before: flowed, startingAt: changed.blocks[cells.lowerBound + row * request.columns].id,
                layouts: [layout], reflowBody: false)
        }
        flowed = HWPFlowLayout.reflowingBody(flowed, before: before, startingAt: flowed[index].id,
            layouts: [layout.pageSetupFlowLayout], reflowingTables: true)
        let finalBlocks = flowed
        let final = try await Task.detached(priority: .userInitiated) {
            try HWPTableStructureDocument.load(changed.serialized(finalBlocks))
        }.value
        guard final.blocks.count == finalBlocks.count,
              zip(final.blocks, finalBlocks).allSatisfy({ HWPDocumentFormatting.matches($0, $1) }),
              final.layouts == source.layouts else { throw HWPDocumentEditingError.cannotSave }
        return .init(document: final, focusedID: final.blocks[cells.lowerBound].id)
    }
}
