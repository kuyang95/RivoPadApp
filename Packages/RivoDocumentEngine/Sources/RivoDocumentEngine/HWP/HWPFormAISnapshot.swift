import Foundation

public nonisolated enum HWPFormAISnapshot {
    /// Keep a matched field's label and value together even when the general
    /// document snapshot was truncated or a selected paragraph is far away.
    public static func addingFormContext(
        to base: WordAIDocumentSnapshot,
        allBlocks: [WordDocumentBlock],
        context: WordAIFormContext
    ) -> WordAIDocumentSnapshot {
        let byID = Dictionary(uniqueKeysWithValues: allBlocks.map { ($0.id, $0) })
        let fieldIDs = Set(context.targetFieldIDs)
        let labelIDs = Set(context.fields.flatMap(\.labelBlockIDs))
        let targetValueIDs = Set(context.targetFields.filter(\.isEditable).flatMap(\.valueBlockIDs))
        let prioritizedFields = context.fields.filter { fieldIDs.contains($0.id) }
            + context.fields.filter { !fieldIDs.contains($0.id) }
        var included = Set<String>()
        var blocks: [WordAIDocumentSnapshot.Block] = []
        var characters = 0

        func add(_ block: WordDocumentBlock) {
            guard !included.contains(block.id), blocks.count < WordAISnapshotBuilder.maximumContextBlocks,
                  characters + block.text.count <= WordAISnapshotBuilder.maximumContextCharacters else { return }
            included.insert(block.id)
            characters += block.text.count
            blocks.append(WordAIDocumentSnapshot.Block(id: block.id, role: block.kind.rawValue,
                styleID: block.styleID ?? "Normal", text: block.text,
                tableLocation: block.tableLocation?.accessibilityDescription,
                isEditable: block.isEditable && !labelIDs.contains(block.id)
                    && (context.resolution == .unmatched
                        || (context.resolution == .resolved && targetValueIDs.contains(block.id)))))
        }

        for field in prioritizedFields.filter({ fieldIDs.contains($0.id) }).prefix(200) {
            for id in field.labelBlockIDs + field.valueBlockIDs {
                if let block = byID[id] { add(block) }
            }
        }
        for block in base.blocks {
            if let original = byID[block.id] { add(original) }
        }
        for field in prioritizedFields.prefix(200) {
            for id in field.labelBlockIDs + field.valueBlockIDs {
                if let block = byID[id] { add(block) }
            }
        }
        let visibleFields = prioritizedFields.prefix(200).filter {
            ($0.labelBlockIDs + $0.valueBlockIDs).allSatisfy(included.contains)
        }
        let targetMissing = context.resolution == .resolved
            && !context.targetFieldIDs.allSatisfy { id in visibleFields.contains { $0.id == id } }
        let formContext = WordAIFormContext(supportedOperations: context.supportedOperations,
            fields: visibleFields, targetFieldIDs: context.targetFieldIDs,
            resolution: targetMissing ? .unsupported : context.resolution,
            clarificationMessage: targetMissing
                ? DocumentEngineLocalization.string("입력 칸 전체를 읽을 수 없어 수정안을 만들지 않았습니다. 간편 문서에서 해당 칸을 선택해 주세요.")
                : context.clarificationMessage)
        return WordAIDocumentSnapshot(documentName: base.documentName,
            selectedBlockID: base.selectedBlockID.flatMap { included.contains($0) ? $0 : nil }, blocks: blocks,
            contextWasTruncated: included.count < allBlocks.count, retrieval: base.retrieval,
            revision: base.revision, formContext: formContext)
    }
}
