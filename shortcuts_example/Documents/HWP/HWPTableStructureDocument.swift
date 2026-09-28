import Foundation

/// An in-memory editing baseline. Changing table structure never writes the
/// user's file; the file's optimistic-concurrency snapshot stays separate.
nonisolated enum HWPTableStructureDocument: Sendable {
    case hwpx(HWPXDocumentPackage)
    case hwp(HWP5StructuredDocument, Data)

    var blocks: [HWPDocumentBlock] {
        switch self { case .hwpx(let p): p.blocks; case .hwp(let d, _): d.blocks }
    }
    var layouts: [HWPDocumentPageLayout] {
        switch self { case .hwpx(let p): p.pageLayouts; case .hwp(let d, _): d.pageLayouts }
    }
    var data: Data {
        switch self { case .hwpx(let p): p.sourceData; case .hwp(_, let data): data }
    }
    static func load(_ data: Data) throws -> Self {
        data.starts(with: [0x50, 0x4B]) ? .hwpx(try HWPXDocumentPackage.load(from: data))
            : .hwp(try HWP5StructuredDocumentParser.parse(from: data), data)
    }
    func serialized(_ edited: [HWPDocumentBlock]) throws -> Data {
        switch self {
        case .hwpx(let p): try p.serializedData(applying: edited)
        case .hwp(let d, let data): try HWP5DocumentRewriter.rewrite(sourceData: data, originalBlocks: d.blocks, editedBlocks: edited)
        }
    }

    struct Result: Sendable { let document: HWPTableStructureDocument; let focusedID: String }

    @MainActor func editing(_ action: HWPTableStructureAction, blocks drafts: [HWPDocumentBlock], selectedID: String,
                           dimensions: HWPTableDimensions? = nil) async throws -> Result {
        if action == .deleteTable { return try await HWPTableDeletion.applying(to: self, drafts: drafts, selectedID: selectedID) }
        guard let selectedIndex = drafts.firstIndex(where: { $0.id == selectedID }) else { throw HWPDocumentEditingError.staleDocument }
        let (original, changed, plan) = try await Task.detached(priority: .userInitiated) {
            let original = try Self.load(self.serialized(drafts))
            guard original.blocks.indices.contains(selectedIndex) else { throw HWPDocumentEditingError.staleDocument }
            let plan = try HWPTableStructureEditing.plan(action, blocks: original.blocks,
                selectedID: original.blocks[selectedIndex].id, layouts: original.layouts, dimensions: dimensions)
            let output: Data
            switch original {
            case .hwpx(let package): output = try HWPTableStructureWriter.hwpx(package, plan: plan)
            case .hwp(let document, let data): output = try HWPTableStructureWriter.hwp(data, blocks: document.blocks, plan: plan)
            }
            return (original, try Self.load(output), plan)
        }.value
        let indices = HWPTableStructureWriter.sourceIndices(plan, count: original.blocks.count)
        var oldIDs: [Int: String] = [:]
        for (index, source) in indices.enumerated() { if let source { oldIDs[source] = changed.blocks[index].id } }
        // Remap retained paragraph IDs so the existing flow engine can preserve
        // authored gaps below the old table while moving the new table's tail.
        var before = original.blocks.enumerated().map { index, block in
            HWPDocumentBlock(id: oldIDs[index] ?? "hwp-before-\(block.id)", sectionPath: block.sectionPath,
                paragraphIndex: block.paragraphIndex, text: block.text, tableLocation: block.tableLocation,
                isEditable: block.isEditable, presentation: block.presentation, region: block.region,
                images: block.images, lineLayouts: block.lineLayouts, canvasObjects: block.canvasObjects,
                layoutContainerID: block.layoutContainerID, keepsParagraphBoundary: block.keepsParagraphBoundary)
        }
        func resolving(_ blocks: [HWPDocumentBlock], layouts: [HWPDocumentPageLayout]) -> [HWPDocumentBlock] {
            let indices = blocks.indices.filter { blocks[$0].sectionPath == plan.section }
            let sectionIndex = Int(plan.section.lowercased().components(separatedBy: "section").last?.replacingOccurrences(of: ".xml", with: "") ?? "0") ?? 0
            guard let layout = layouts.first(where: { $0.sectionIndex == sectionIndex }) else { return blocks }
            let resolved = HWPFlowLayout.resolvingMissingLines(indices.map { blocks[$0] }, layout: layout)
            var result = blocks
            for (offset, index) in indices.enumerated() { result[index] = resolved[offset] }
            return result
        }
        before = resolving(before, layouts: original.layouts)
        let measuredBase = resolving(changed.blocks, layouts: changed.layouts)
        var flowed = measuredBase
        var cursor = plan.originalRange.lowerBound
        for cell in plan.cells {
            flowed = HWPTableEditing.reflow(flowed, before: measuredBase, startingAt: changed.blocks[cursor].id,
                layouts: changed.layouts, reflowBody: false)
            cursor += cell.isNew ? 1 : cell.paragraphs.count
        }
        if let owner = flowed.indices.prefix(plan.originalRange.lowerBound).last(where: {
            flowed[$0].sectionPath == plan.section && flowed[$0].tableLocation == nil && flowed[$0].region.kind == .body && flowed[$0].layoutContainerID == nil
        }) {
            flowed = HWPFlowLayout.reflowingBody(flowed, before: before, startingAt: flowed[owner].id,
                layouts: changed.layouts, reflowingTables: true)
        }
        let finalBlocks = flowed
        let final = try await Task.detached(priority: .userInitiated) {
            try Self.load(changed.serialized(finalBlocks))
        }.value
        guard final.blocks.count == finalBlocks.count, let focused = final.blocks.first(where: {
            $0.sectionPath == plan.section && $0.tableLocation?.table == plan.table
                && $0.tableLocation?.row == plan.focus.row && $0.tableLocation?.column == plan.focus.column
        }), zip(final.blocks, finalBlocks).allSatisfy({ HWPDocumentFormatting.matches($0, $1) }) else {
            throw HWPDocumentEditingError.cannotSave
        }
        return Result(document: final, focusedID: focused.id)
    }
}
