import Foundation

public nonisolated enum HWPTextBoxEditing {
    public typealias Selection = HWPShapeEditing.Selection

    public struct Request: Sendable {
        public let selection: Selection
        public let text: String
        public let widthPoints: Double
        public let heightPoints: Double

        public var isValid: Bool {
            !text.isEmpty && text.utf16.count <= 32_768
                && widthPoints.isFinite && heightPoints.isFinite
                && (60...2_000).contains(widthPoints) && (30...2_000).contains(heightPoints)
        }
    
    public init(selection: Selection, text: String, widthPoints: Double, heightPoints: Double) {
        self.selection = selection
        self.text = text
        self.widthPoints = widthPoints
        self.heightPoints = heightPoints
    }
}
    public struct Entry: Identifiable, Hashable, Sendable {
        public let id: String
        public let text: String
        public let paragraphIndex: Int
        public let isTextEditable: Bool
    
    public init(id: String, text: String, paragraphIndex: Int, isTextEditable: Bool) {
        self.id = id
        self.text = text
        self.paragraphIndex = paragraphIndex
        self.isTextEditable = isTextEditable
    }
}

    public struct Paragraph: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let sourceID: String?
        public var text: String

        public init(id: UUID = UUID(), sourceID: String?, text: String) {
            self.id = id
            self.sourceID = sourceID
            self.text = text
        }
    }

    public struct Target: Identifiable, Sendable {
        public let ownerID: String
        public let objectID: String
        public let containerID: String
        public let entries: [Entry]
        public let contentWidthPoints: Double
        public let contentHeightPoints: Double
        public let internalObjectCount: Int
        public let internalTableCount: Int
        public var id: String { objectID }
    
    public init(ownerID: String, objectID: String, containerID: String, entries: [Entry], contentWidthPoints: Double, contentHeightPoints: Double, internalObjectCount: Int, internalTableCount: Int) {
        self.ownerID = ownerID
        self.objectID = objectID
        self.containerID = containerID
        self.entries = entries
        self.contentWidthPoints = contentWidthPoints
        self.contentHeightPoints = contentHeightPoints
        self.internalObjectCount = internalObjectCount
        self.internalTableCount = internalTableCount
    }
}

    public struct Update: Sendable {
        public let paragraphs: [Paragraph]

        public init(paragraphs: [Paragraph]) { self.paragraphs = paragraphs }
        public init(texts: [String]) {
            paragraphs = texts.map { Paragraph(sourceID: nil, text: $0) }
        }

        public var texts: [String] { paragraphs.map(\.text) }

        public var isValid: Bool {
            !paragraphs.isEmpty && paragraphs.count <= 64
                && paragraphs.allSatisfy { $0.text.utf16.count <= 32_768 }
                && paragraphs.reduce(0) { $0 + $1.text.utf16.count } <= 131_072
                && Set(paragraphs.compactMap(\.sourceID)).count == paragraphs.compactMap(\.sourceID).count
        }
    }

    @MainActor public static func inserting(_ request: Request, source: HWPTableStructureDocument,
                                     drafts: [HWPDocumentBlock]) async throws -> HWPTableStructureDocument.Result {
        guard request.isValid else { throw HWPDocumentEditingError.limitExceeded }
        return try await HWPShapeEditing.inserting(.init(selection: request.selection, kind: .rectangle,
            widthPoints: request.widthPoints, heightPoints: request.heightPoints,
            textBoxText: request.text), source: source, drafts: drafts)
    }

    public static func target(owner: HWPDocumentBlock, object: HWPDocumentCanvasObject,
                       blocks: [HWPDocumentBlock]) -> Target? {
        guard owner.region.kind == .body, let containerID = object.textContainerID else { return nil }
        let contents = blocks.filter { $0.layoutContainerID == containerID }
        let paragraphs = contents.filter { $0.tableLocation == nil }
        guard !paragraphs.isEmpty, paragraphs.count <= 64 else { return nil }
        let margin = object.textContainerLayout
        return Target(ownerID: owner.id, objectID: object.id, containerID: containerID,
            entries: paragraphs.map { Entry(id: $0.id, text: $0.text,
                paragraphIndex: $0.paragraphIndex, isTextEditable: $0.isEditable) },
            contentWidthPoints: max(1, object.placement.widthPoints - (margin?.left ?? 6) - (margin?.right ?? 6)),
            contentHeightPoints: max(1, object.placement.heightPoints - (margin?.top ?? 6) - (margin?.bottom ?? 6)),
            internalObjectCount: contents.reduce(0) { $0 + $1.canvasObjects.count },
            internalTableCount: Set(contents.compactMap { $0.tableLocation?.table }).count)
    }

    @MainActor public static func applying(_ update: Update, target: Target,
                                    source: HWPTableStructureDocument,
                                    drafts: [HWPDocumentBlock]) async throws -> HWPTableStructureDocument.Result {
        guard update.isValid,
              let ownerIndex = drafts.firstIndex(where: { $0.id == target.ownerID }),
              let object = drafts[ownerIndex].canvasObjects.first(where: { $0.id == target.objectID }),
              object.textContainerID == target.containerID else {
            throw HWPDocumentEditingError.staleDocument
        }
        let indices = try target.entries.map { entry -> Int in
            guard let index = drafts.firstIndex(where: { $0.id == entry.id }),
                  drafts[index].text == entry.text,
                  drafts[index].layoutContainerID == target.containerID else {
                throw HWPDocumentEditingError.staleDocument
            }
            return index
        }
        let resolved: [Paragraph]
        if update.paragraphs.allSatisfy({ $0.sourceID == nil }) {
            resolved = update.paragraphs.enumerated().map { offset, paragraph in
                Paragraph(id: paragraph.id,
                    sourceID: target.entries.indices.contains(offset) ? target.entries[offset].id : nil,
                    text: paragraph.text)
            }
        } else {
            let sourceIDs = Set(target.entries.map(\.id))
            guard update.paragraphs.allSatisfy({ $0.sourceID.map(sourceIDs.contains) ?? true }) else {
                throw HWPDocumentEditingError.staleDocument
            }
            resolved = update.paragraphs
        }
        var edited = drafts
        var y = 0.0
        let requestedByID = Dictionary(uniqueKeysWithValues: resolved.compactMap { paragraph in
            paragraph.sourceID.map { ($0, paragraph.text) }
        })
        for index in indices {
            let entryID = edited[index].id
            guard let replacement = requestedByID[entryID] else { continue }
            guard edited[index].isEditable || edited[index].text == replacement else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            let replaced = HWPTextRunEditing.replacingText(in: edited[index], with: replacement)
            let measured = HWPFlowLayout.measure(replaced, width: target.contentWidthPoints,
                startY: y, pageHeight: target.contentHeightPoints, minimumHeight: 0)
            edited[index] = replaced.withLayout(lines: measured)
            y = measured.last.map { $0.verticalPositionPoints + $0.lineHeightPoints } ?? y + 14
        }
        let serialized = try source.serialized(edited)
        let changed = try await Task.detached(priority: .userInitiated) {
            let base = try HWPTableStructureDocument.load(serialized)
            let originalOrder = target.entries.map(\.id)
            let requestedOrder = resolved.compactMap(\.sourceID)
            let data = originalOrder == requestedOrder && resolved.count == target.entries.count
                ? serialized
                : try HWPTextBoxStructureWriter.apply(resolved, target: target, to: base)
            return try HWPTableStructureDocument.load(data)
        }.value
        guard let changedOwner = changed.blocks.first(where: { $0.id == target.ownerID }),
              let changedObject = changedOwner.canvasObjects.first(where: { $0.id == target.objectID }),
              let changedTarget = Self.target(owner: changedOwner, object: changedObject, blocks: changed.blocks),
              changedTarget.entries.map(\.text) == resolved.map(\.text),
              changedTarget.internalObjectCount == target.internalObjectCount,
              changedTarget.internalTableCount == target.internalTableCount else {
            throw HWPDocumentEditingError.cannotSave
        }
        return .init(document: changed, focusedID: changedTarget.entries[0].id)
    }
}
