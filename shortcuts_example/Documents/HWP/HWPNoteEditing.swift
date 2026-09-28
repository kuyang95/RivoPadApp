import Foundation

nonisolated enum HWPNoteKind: String, CaseIterable, Identifiable, Sendable {
    case footNote, endNote

    var id: String { rawValue }
    var title: String { self == .footNote ? "각주" : "미주" }
    var region: HWPDocumentRegionKind { self == .footNote ? .footnote : .endnote }
    var controlID: UInt32 { self == .footNote ? 0x666E_2020 : 0x656E_2020 }
    var automaticNumberType: UInt32 { self == .footNote ? 1 : 2 }
    var xmlNumberType: String { self == .footNote ? "FOOTNOTE" : "ENDNOTE" }
}

nonisolated enum HWPNoteEditing {
    struct Insertion: Hashable, Sendable {
        let blockID: String
        let sectionPath: String
        let text: String
        let caret: Int
    }

    struct Note: Hashable, Identifiable, Sendable {
        let blockID: String
        let sectionPath: String
        let kind: HWPNoteKind
        let index: Int
        let text: String
        var id: String { "\(kind.rawValue):\(blockID)" }
        var number: Int { index + 1 }
    }

    struct Selection: Identifiable, Sendable {
        let id = UUID()
        let sectionPath: String
        let insertion: Insertion?
        let notes: [Note]
    }

    enum Action: Sendable {
        case insert(HWPNoteKind, String, Insertion)
        case update(Note, String)
        case delete(Note)
    }

    static func insertion(blocks: [HWPDocumentBlock], selectedID: String?, range: NSRange) -> Insertion? {
        guard let selectedID, let block = blocks.first(where: { $0.id == selectedID }),
              HWPParagraphEditing.supports(block), block.region.kind == .body,
              block.tableLocation == nil, block.layoutContainerID == nil,
              block.canvasObjects.isEmpty, block.images.isEmpty,
              range.location >= 0, range.length >= 0,
              range.location <= block.text.utf16.count,
              range.length <= block.text.utf16.count - range.location else { return nil }
        let caret = NSMaxRange(range)
        let boundaries = Set(block.text.indices.map { $0.utf16Offset(in: block.text) } + [block.text.utf16.count])
        guard boundaries.contains(caret) else { return nil }
        return Insertion(blockID: block.id, sectionPath: block.sectionPath, text: block.text, caret: caret)
    }

    static func selection(blocks: [HWPDocumentBlock], sectionPath: String,
                          insertion: Insertion?) -> Selection {
        var ordinal: [HWPNoteKind: Int] = [:]
        let notes = blocks.compactMap { block -> Note? in
            guard block.sectionPath == sectionPath,
                  let kind = HWPNoteKind.allCases.first(where: { $0.region == block.region.kind }) else { return nil }
            let index = ordinal[kind, default: 0]
            ordinal[kind] = index + 1
            return Note(blockID: block.id, sectionPath: block.sectionPath,
                        kind: kind, index: index, text: block.text)
        }
        return Selection(sectionPath: sectionPath, insertion: insertion, notes: notes)
    }

    static func validatedText(_ text: String) throws -> String {
        guard text.utf16.count <= 2_000,
              !text.unicodeScalars.contains(where: {
                  $0.value < 32 && ![9, 10].contains($0.value)
              }) else { throw HWPDocumentEditingError.limitExceeded }
        return text
    }

    @MainActor
    static func applying(_ action: Action, source: HWPTableStructureDocument,
                         drafts: [HWPDocumentBlock], selectedID: String?) async throws -> HWPTableStructureDocument.Result {
        let base = try await Task.detached(priority: .userInitiated) {
            let data = drafts == source.blocks ? source.data : try source.serialized(drafts)
            return try HWPTableStructureDocument.load(data)
        }.value
        let output = try await Task.detached(priority: .userInitiated) {
            switch base {
            case .hwpx(let package): return try HWPNoteEditingWriter.applyHWPX(action, package: package)
            case .hwp(_, let data): return try HWPNoteEditingWriter.applyHWP(action, data: data, blocks: base.blocks)
            }
        }.value
        let changed = try HWPTableStructureDocument.load(output)
        let beforeBody = base.blocks.filter { $0.region.kind == .body }
        let afterBody = changed.blocks.filter { $0.region.kind == .body }
        guard beforeBody.map(\.text) == afterBody.map(\.text),
              base.layouts.count == changed.layouts.count else { throw HWPDocumentEditingError.cannotSave }

        let focusSource: String?
        switch action {
        case .insert(_, _, let insertion): focusSource = insertion.blockID
        case .update, .delete: focusSource = selectedID
        }
        let focused: HWPDocumentBlock?
        if let focusSource, let index = beforeBody.firstIndex(where: { $0.id == focusSource }),
           afterBody.indices.contains(index) { focused = afterBody[index] }
        else { focused = afterBody.first }
        guard let focused else { throw HWPDocumentEditingError.cannotSave }
        return .init(document: changed, focusedID: focused.id)
    }
}
