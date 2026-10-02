import Foundation

public nonisolated enum HWPTableDeletion {
    public struct Plan: Sendable {
        public let table: HWPTableStructureEditing.Plan
        public let owner: Int
        public var removed: Range<Int> { table.originalRange }
        public func retained(count: Int) -> [Int] { (0..<count).filter { !removed.contains($0) } }
    
    public init(table: HWPTableStructureEditing.Plan, owner: Int) {
        self.table = table
        self.owner = owner
    }
}

    public static func plan(blocks: [HWPDocumentBlock], selectedID: String, layouts: [HWPDocumentPageLayout]) throws -> Plan {
        let table = try HWPTableStructureEditing.plan(.resize, blocks: blocks, selectedID: selectedID, layouts: layouts)
        guard let owner = blocks.indices.prefix(table.originalRange.lowerBound).last(where: {
            blocks[$0].sectionPath == table.section && blocks[$0].region.kind == .body
                && blocks[$0].tableLocation == nil && blocks[$0].layoutContainerID == nil
        }), blocks[owner].images.isEmpty, blocks[owner].canvasObjects.isEmpty,
            blocks[(owner + 1)..<table.originalRange.lowerBound].allSatisfy({ $0.tableLocation == nil }) else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        // A paragraph owning several tables needs per-control placement and
        // selection; do not mistake the other table for the deleted one's tail.
        let after = blocks.dropFirst(table.originalRange.upperBound).prefix {
            $0.sectionPath == table.section && !($0.region.kind == .body && $0.tableLocation == nil && $0.layoutContainerID == nil)
        }
        guard after.allSatisfy({ $0.tableLocation == nil }) else { throw HWPDocumentEditingError.unsupportedEdit }
        return Plan(table: table, owner: owner)
    }

    @MainActor public static func applying(to source: HWPTableStructureDocument, drafts: [HWPDocumentBlock], selectedID: String) async throws -> HWPTableStructureDocument.Result {
        guard let selected = drafts.firstIndex(where: { $0.id == selectedID }) else { throw HWPDocumentEditingError.staleDocument }
        let (original, changed, plan) = try await Task.detached(priority: .userInitiated) {
            let original = try HWPTableStructureDocument.load(source.serialized(drafts))
            guard original.blocks.indices.contains(selected) else { throw HWPDocumentEditingError.staleDocument }
            let plan = try Self.plan(blocks: original.blocks, selectedID: original.blocks[selected].id, layouts: original.layouts)
            let changed = try HWPTableStructureDocument.load(HWPTableDeletionWriter.apply(plan, to: original))
            return (original, changed, plan)
        }.value
        let retained = plan.retained(count: original.blocks.count)
        guard changed.blocks.count == retained.count,
              HWPParagraphEditing.supports(changed.blocks[plan.owner]), changed.layouts == original.layouts else {
            throw HWPDocumentEditingError.cannotSave
        }
        for (index, old) in retained.enumerated() {
            guard HWPDocumentFormatting.matches(changed.blocks[index], original.blocks[old]) else { throw HWPDocumentEditingError.cannotSave }
        }
        let section = plan.table.section
        guard let layout = changed.layouts.first(where: { $0.sectionIndex == HWPPageSetup.sectionIndex(section) }) else {
            throw HWPDocumentEditingError.cannotSave
        }
        func resolved(_ blocks: [HWPDocumentBlock]) -> [HWPDocumentBlock] {
            let indices = blocks.indices.filter { blocks[$0].sectionPath == section }
            let values = HWPFlowLayout.resolvingMissingLines(indices.map { blocks[$0] }, layout: layout)
            var result = blocks
            for (index, value) in zip(indices, values) { result[index] = value }
            return result
        }
        let old = resolved(original.blocks), members = Array(old[plan.removed])
        let anchorY = members.first?.tableLocation?.tableAnchor?.verticalPositionPoints
            ?? old[plan.owner].lineLayouts.first?.verticalPositionPoints ?? 0
        let bottom = HWPTableEditing.finalPageBottom(members, anchorY: anchorY, layout: layout.pageSetupFlowLayout)
        // IDs and table ordinals shift after deletion. Retain current identity
        // while using the original geometry for all unaffected content.
        var before = retained.enumerated().map { index, oldIndex in changed.blocks[index].withLayout(lines: old[oldIndex].lineLayouts) }
        if let first = before[plan.owner].lineLayouts.first, anchorY < first.verticalPositionPoints {
            before[plan.owner] = before[plan.owner].withLayout(lines: before[plan.owner].lineLayouts.map {
                $0.positioned(y: max(0, $0.verticalPositionPoints - first.verticalPositionPoints + anchorY))
            })
        }
        let flowed = HWPFlowLayout.reflowingBody(resolved(changed.blocks), before: before, startingAt: changed.blocks[plan.owner].id,
            layouts: [layout.pageSetupFlowLayout], reflowingTables: true,
            removedTableBottoms: [changed.blocks[plan.owner].id: bottom])
        let final = try await Task.detached(priority: .userInitiated) {
            try HWPTableStructureDocument.load(changed.serialized(flowed))
        }.value
        guard final.blocks.count == flowed.count, final.layouts == source.layouts,
              zip(final.blocks, flowed).allSatisfy({ HWPDocumentFormatting.matches($0, $1) }),
              HWPParagraphEditing.supports(final.blocks[plan.owner]) else { throw HWPDocumentEditingError.cannotSave }
        return .init(document: final, focusedID: final.blocks[plan.owner].id)
    }
}
