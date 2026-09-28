import Foundation
import CoreGraphics
import ImageIO

/// The product-facing HWP 5.x reader. It deliberately owns only the subset
/// that RivoPad can render without executing scripts or embedded objects.
/// Unknown records stay outside the display model and lower the reported
/// fidelity instead of being interpreted as text.
nonisolated enum HWP5DocumentFidelity: Hashable, Sendable {
    case structured
    case simplified
    case textOnly
}

nonisolated struct HWP5StructuredDocument: Hashable, Sendable {
    let blocks: [HWPDocumentBlock]
    let pageLayouts: [HWPDocumentPageLayout]
    let fontCount: Int
    let characterShapeCount: Int
    let paragraphShapeCount: Int
    let styleCount: Int
    let tableCount: Int
    let tableCellCount: Int
    let imageCount: Int
    let headerCount: Int
    let footerCount: Int
    let footnoteCount: Int
    let endnoteCount: Int
    let shapeCount: Int
    let equationCount: Int
    let chartCount: Int
    let complexControlCount: Int
    let allowsEditing: Bool
    let fidelity: HWP5DocumentFidelity

    var plainText: String {
        blocks.map(\.text).joined(separator: "\n")
    }
}

nonisolated enum HWP5StructuredDocumentParser {
    private static let maximumRecords = 200_000
    private static let maximumRecordLevel = 64

    private enum Tag {
        static let idMappings: UInt32 = 0x11
        static let binaryData: UInt32 = 0x12
        static let faceName: UInt32 = 0x13
        static let borderFill: UInt32 = 0x14
        static let charShape: UInt32 = 0x15
        static let bullet: UInt32 = 0x18
        static let paraShape: UInt32 = 0x19
        static let style: UInt32 = 0x1A

        static let paraHeader: UInt32 = 0x42
        static let paraText: UInt32 = 0x43
        static let paraCharShape: UInt32 = 0x44
        static let paraLineSegment: UInt32 = 0x45
        static let paraRangeTag: UInt32 = 0x46
        static let controlHeader: UInt32 = 0x47
        static let listHeader: UInt32 = 0x48
        static let pageDefinition: UInt32 = 0x49
        static let footnoteShape: UInt32 = 0x4A
        static let pageBorderFill: UInt32 = 0x4B
        static let shapeComponent: UInt32 = 0x4C
        static let table: UInt32 = 0x4D
        static let line: UInt32 = 0x4E
        static let rectangle: UInt32 = 0x4F
        static let ellipse: UInt32 = 0x50
        static let arc: UInt32 = 0x51
        static let polygon: UInt32 = 0x52
        static let curve: UInt32 = 0x53
        static let ole: UInt32 = 0x54
        static let picture: UInt32 = 0x55
        static let container: UInt32 = 0x56
        static let equation: UInt32 = 0x58
        static let chartData: UInt32 = 0x61
    }

    private static let tableControlID: UInt32 = 0x7462_6C20 // "tbl "
    private static let sectionControlID: UInt32 = 0x7365_6364 // "secd"
    private static let headerControlID: UInt32 = 0x6865_6164 // "head"
    private static let footerControlID: UInt32 = 0x666F_6F74 // "foot"
    private static let footnoteControlID: UInt32 = 0x666E_2020 // "fn  "
    private static let endnoteControlID: UInt32 = 0x656E_2020 // "en  "
    private static let pictureControlID: UInt32 = 0x2470_6963 // "$pic"
    private static let genericShapeControlID: UInt32 = 0x6773_6F20 // "gso "
    private static let columnControlID: UInt32 = 0x636F_6C64 // "cold"
    private static let pageNumberControlID: UInt32 = 0x7067_6E70 // "pgnp"
    private static let equationControlID: UInt32 = 0x6571_6564 // "eqed"
    private static let lineControlID: UInt32 = 0x246C_696E // "$lin"
    private static let rectangleControlID: UInt32 = 0x2472_6563 // "$rec"
    private static let ellipseControlID: UInt32 = 0x2465_6C6C // "$ell"
    private static let arcControlID: UInt32 = 0x2461_7263 // "$arc"
    private static let polygonControlID: UInt32 = 0x2470_6F6C // "$pol"
    private static let curveControlID: UInt32 = 0x2463_7572 // "$cur"
    private static let oleControlID: UInt32 = 0x246F_6C65 // "$ole"
    private static let containerControlID: UInt32 = 0x2463_6F6E // "$con"
    private static let hyperlinkControlID: UInt32 = 0x2568_6C6B // "%hlk"

    static func parse(from data: Data) throws -> HWP5StructuredDocument {
        let source = try Source(data: data)
        let docInfo = try parseDocInfo(source)

        var blocks: [HWPDocumentBlock] = []
        var pageLayouts: [HWPDocumentPageLayout] = []
        var paragraphOrdinal = 0
        var sawParagraphHeader = false
        var complexControlCount = 0
        var tableCount = 0
        var tableCellCount = 0
        var imageCount = 0
        var headerCount = 0
        var footerCount = 0
        var footnoteCount = 0
        var endnoteCount = 0
        var shapeCount = 0
        var equationCount = 0
        var chartCount = 0
        var expandedByteCount = 0
        var recordCount = 0
        // Canvas objects whose owner paragraph was already finished when a
        // later record (shape geometry, picture, placement) arrived. Text
        // boxes store their inner paragraphs before the RECTANGLE record,
        // so the owner is no longer the current builder at that point.
        var objectOverrides: [String: HWPDocumentCanvasObject] = [:]
        var blockBuilders: [String: ParagraphBuilder] = [:]

        for section in source.sections {
            let stored: Data
            do {
                stored = try source.container.stream(named: section.name)
            } catch OLECompoundFileError.limitExceeded {
                throw ChatAttachmentError.hwpLimitExceeded
            } catch {
                throw ChatAttachmentError.invalidHWP
            }
            let body = try expanded(
                stored,
                isCompressed: source.isCompressed
            )
            expandedByteCount += body.count
            guard expandedByteCount <= HWP5TextExtractor.maximumExpandedBytes else {
                throw ChatAttachmentError.hwpLimitExceeded
            }
            let records = try BinaryRecord.records(in: body)
            recordCount += records.count
            guard recordCount <= maximumRecords else {
                throw ChatAttachmentError.hwpLimitExceeded
            }
            var paragraph: ParagraphBuilder?
            var tableStack: [TableContext] = []
            var listContainers: [ListContainer] = []
            var objectStack: [ObjectContext] = []
            var layout = SectionLayoutBuilder(sectionIndex: section.index)
            var objectOrdinal = 0
            // Finished paragraphs by record level. A paragraph that owns a
            // nested table is finished as soon as the first cell paragraph
            // starts, but a second control in the same paragraph (for
            // example two tables anchored to one line) still arrives after
            // all of the cell paragraphs. Its owner is the last paragraph
            // one level above the control, not the current cell paragraph.
            var finishedParagraphsByLevel: [Int: ParagraphBuilder] = [:]
            var finishedParagraphIndicesByLevel: [Int: Int] = [:]
            var tableControlOrdinals: [Int: Int] = [:]

            func controlOwner(at controlLevel: Int) -> ParagraphBuilder? {
                let ownerLevel = controlLevel - 1
                if let current = paragraph, current.level == ownerLevel {
                    return current
                }
                return finishedParagraphsByLevel[ownerLevel] ?? paragraph
            }

            func updateObject(
                _ context: ObjectContext,
                _ transform: (HWPDocumentCanvasObject) -> HWPDocumentCanvasObject
            ) {
                if var current = paragraph,
                   current.canvasObjects.indices.contains(context.objectIndex),
                   current.canvasObjects[context.objectIndex].id == context.objectID {
                    current.canvasObjects[context.objectIndex] =
                        transform(current.canvasObjects[context.objectIndex])
                    paragraph = current
                    return
                }
                let base = objectOverrides[context.objectID]
                    ?? blocks.reversed().lazy.compactMap { block in
                        block.canvasObjects.first { $0.id == context.objectID }
                    }.first
                guard let base else { return }
                objectOverrides[context.objectID] = transform(base)
            }

            func finishParagraph() throws {
                guard let current = paragraph else { return }
                finishedParagraphsByLevel[current.level] = current
                finishedParagraphIndicesByLevel[current.level] = blocks.count
                let block = try current.makeBlock(
                    sectionIndex: section.index,
                    paragraphOrdinal: paragraphOrdinal,
                    docInfo: docInfo,
                    allowsEditing: source.allowsEditing
                )
                blocks.append(block)
                blockBuilders[block.id] = current
                paragraphOrdinal += 1
                guard blocks.count <= HWPXDocumentPackage.maximumBlocks else {
                    throw ChatAttachmentError.hwpLimitExceeded
                }
                paragraph = nil
            }

            for record in records {
                while let table = tableStack.last,
                      record.level <= table.controlLevel {
                    tableStack.removeLast()
                }
                while let container = listContainers.last,
                      record.level <= container.controlLevel {
                    listContainers.removeLast()
                }
                while let object = objectStack.last,
                      record.level <= object.controlLevel {
                    objectStack.removeLast()
                }
                if let current = paragraph, current.hasHeader, !current.hasTextRecord,
                   record.tag != Tag.paraHeader,
                   (record.level > current.level || [Tag.paraCharShape, Tag.paraLineSegment].contains(record.tag)),
                   (record.level != current.level + 1
                    || ![Tag.paraText, Tag.paraCharShape, Tag.paraLineSegment].contains(record.tag)) {
                    paragraph?.hasUnsupportedInsertionRecords = true
                }
                switch record.tag {
                case Tag.paraHeader:
                    try finishParagraph()
                    tableControlOrdinals[record.level] = 0
                    let activeContainer = activeListContainer(
                        for: record.level,
                        containers: listContainers
                    )
                    paragraph = try ParagraphBuilder(
                        headerPayload: record.payload,
                        tableLocation: nextTableLocation(
                            for: record.level,
                            stack: &tableStack,
                            docInfo: docInfo,
                            afterControlLevel: activeContainer?.controlLevel
                        ),
                        region: activeContainer?.region ?? .body,
                        layoutContainerID: activeContainer?.layoutContainerID
                    )
                    paragraph?.level = record.level
                    paragraph?.precedingParagraphEndPoints = finishedParagraphsByLevel[record.level]?
                        .lineLayouts.last.map { $0.verticalPositionPoints + $0.lineHeightPoints + $0.lineSpacingPoints }
                    sawParagraphHeader = true
                case Tag.paraText:
                    if paragraph == nil {
                        paragraph = ParagraphBuilder()
                    }
                    try paragraph?.installText(record.payload)
                case Tag.paraCharShape:
                    if paragraph == nil {
                        paragraph = ParagraphBuilder()
                    }
                    try paragraph?.installCharacterShapes(record.payload)
                case Tag.paraLineSegment:
                    if paragraph == nil {
                        paragraph = ParagraphBuilder()
                    }
                    try paragraph?.installLineLayouts(record.payload)
                case Tag.paraRangeTag:
                    // Range tags can carry bookmarks, hyperlinks, comments,
                    // and other position-based semantics. Until those ranges
                    // can be rewritten together with the text, keep only this
                    // paragraph read-only instead of blocking the whole HWP.
                    paragraph?.containsPositionedMetadata = true
                case Tag.controlHeader:
                    let identifier = try controlID(record.payload)
                    // Replacing this owner's visible text would also remove
                    // its control anchor. The owner may already be finished
                    // when another control follows a nested table's cells.
                    if identifier != hyperlinkControlID, var owner = paragraph, owner.level == record.level - 1 {
                        owner.containsComplexControl = true
                        paragraph = owner
                    } else if identifier != hyperlinkControlID,
                              var owner = finishedParagraphsByLevel[record.level - 1],
                              let index = finishedParagraphIndicesByLevel[record.level - 1] {
                        owner.containsComplexControl = true
                        finishedParagraphsByLevel[record.level - 1] = owner
                        blocks[index] = try owner.makeBlock(sectionIndex: section.index,
                            paragraphOrdinal: blocks[index].paragraphIndex,
                            docInfo: docInfo, allowsEditing: source.allowsEditing)
                        blockBuilders[blocks[index].id] = owner
                    }
                    switch identifier {
                    case hyperlinkControlID:
                        var owner = controlOwner(at: record.level) ?? ParagraphBuilder()
                        if let target = hyperlinkTarget(record.payload) { owner.hyperlinkTargets.append(target) }
                        if paragraph?.level == record.level - 1 { paragraph = owner }
                        else if let blockIndex = finishedParagraphIndicesByLevel[record.level - 1] {
                            finishedParagraphsByLevel[record.level - 1] = owner
                            blocks[blockIndex] = try owner.makeBlock(sectionIndex: section.index,
                                paragraphOrdinal: blocks[blockIndex].paragraphIndex, docInfo: docInfo,
                                allowsEditing: source.allowsEditing)
                            blockBuilders[blocks[blockIndex].id] = owner
                        }
                    case tableControlID:
                        let owner = controlOwner(at: record.level)
                        let placement = CommonObjectInfo(record.payload).placement
                        let ordinal = tableControlOrdinals[record.level - 1, default: 0]
                        tableControlOrdinals[record.level - 1] = ordinal + 1
                        tableStack.append(
                            TableContext(
                                tableIndex: tableCount,
                                controlLevel: record.level,
                                placement: placement,
                                anchor: owner?.tableAnchor(controlOrdinal: ordinal, docInfo: docInfo, placement: placement),
                                parent: owner?.tableLocation.map {
                                    HWPDocumentTableParentLocation(
                                        table: $0.table,
                                        row: $0.row,
                                        column: $0.column
                                    )
                                }
                            )
                        )
                        tableCount += 1
                    case sectionControlID:
                        layout.installSectionProperty(record.payload)
                        listContainers.append(
                            ListContainer(
                                controlLevel: record.level,
                                region: HWPDocumentRegion(kind: .background)
                            )
                        )
                    case columnControlID:
                        layout.installColumnDefinition(record.payload)
                    case pageNumberControlID:
                        layout.installPageNumber(record.payload)
                    case headerControlID:
                        listContainers.append(
                            ListContainer(
                                controlLevel: record.level,
                                region: HWPDocumentRegion(
                                    kind: .header,
                                    scope: headerFooterScope(record.payload)
                                )
                            )
                        )
                        headerCount += 1
                    case footerControlID:
                        listContainers.append(
                            ListContainer(
                                controlLevel: record.level,
                                region: HWPDocumentRegion(
                                    kind: .footer,
                                    scope: headerFooterScope(record.payload)
                                )
                            )
                        )
                        footerCount += 1
                    case footnoteControlID:
                        listContainers.append(
                            ListContainer(
                                controlLevel: record.level,
                                region: HWPDocumentRegion(
                                    kind: .footnote,
                                    ordinal: footnoteCount
                                )
                            )
                        )
                        footnoteCount += 1
                    case endnoteControlID:
                        listContainers.append(
                            ListContainer(
                                controlLevel: record.level,
                                region: HWPDocumentRegion(
                                    kind: .endnote,
                                    ordinal: endnoteCount
                                )
                            )
                        )
                        endnoteCount += 1
                    case pictureControlID,
                         genericShapeControlID,
                         equationControlID,
                         lineControlID,
                         rectangleControlID,
                         ellipseControlID,
                         arcControlID,
                         polygonControlID,
                         curveControlID,
                         oleControlID,
                        containerControlID:
                        var owner = controlOwner(at: record.level) ?? ParagraphBuilder()
                        let info = CommonObjectInfo(record.payload)
                        var placement = info.placement
                        placement.sourceCharacterPosition = owner.controlPositions(identifier: identifier)
                            .dropFirst(owner.canvasObjects.count).first
                        let objectID = "hwp-section-\(section.index)-object-\(objectOrdinal)"
                        objectOrdinal += 1
                        let repeatsOnEveryPage = owner.region.kind == .background
                        let objectIndex = owner.appendCanvasObject(
                            HWPDocumentCanvasObject(
                                id: objectID,
                                placement: placement,
                                content: .unsupported(info.description ?? "한글 문서 개체"),
                                description: info.description,
                                repeatsOnEveryPage: repeatsOnEveryPage
                            )
                        )
                        owner.containsComplexControl = true
                        if paragraph?.level == record.level - 1 {
                            paragraph = owner
                        } else if let blockIndex = finishedParagraphIndicesByLevel[record.level - 1] {
                            finishedParagraphsByLevel[record.level - 1] = owner
                            blocks[blockIndex] = try owner.makeBlock(sectionIndex: section.index,
                                paragraphOrdinal: blocks[blockIndex].paragraphIndex, docInfo: docInfo,
                                allowsEditing: source.allowsEditing)
                            blockBuilders[blocks[blockIndex].id] = owner
                        } else {
                            paragraph = owner
                        }
                        objectStack.append(
                            ObjectContext(
                                controlLevel: record.level,
                                info: info,
                                objectIndex: objectIndex,
                                objectID: objectID,
                                controlID: identifier
                            )
                        )
                        complexControlCount += 1
                        paragraph?.containsComplexControl = true
                    default:
                        complexControlCount += 1
                        paragraph?.containsComplexControl = true
                    }
                case Tag.table:
                    guard !tableStack.isEmpty,
                          record.level == tableStack[tableStack.count - 1]
                            .controlLevel + 1 else {
                        break
                    }
                    tableStack[tableStack.count - 1].property =
                        try TableProperty(payload: record.payload)
                case Tag.listHeader:
                    var tableCellMatch: (index: Int, cell: TableCell)?
                    for index in tableStack.indices.reversed()
                    where record.level > tableStack[index].controlLevel {
                        if let cell = try TableCell(
                            payload: record.payload,
                            table: tableStack[index].property
                        ) {
                            tableCellMatch = (index, cell)
                            break
                        }
                    }
                    if let tableCellMatch {
                        // A few legacy writers keep the nested table's record
                        // depth for the following outer-cell LIST_HEADER. Its
                        // row/column is outside the completed child table but
                        // valid in an ancestor. Discard that completed suffix
                        // once the ancestor match proves ownership.
                        if tableCellMatch.index + 1 < tableStack.count {
                            tableStack.removeSubrange(
                                (tableCellMatch.index + 1)..<tableStack.count
                            )
                        }
                        tableStack[tableCellMatch.index].activeCell =
                            tableCellMatch.cell
                        tableStack[tableCellMatch.index].cellHeaderLevel = record.level
                        tableCellCount += 1
                        guard tableCellCount <= HWPXDocumentPackage.maximumBlocks else {
                            throw ChatAttachmentError.hwpLimitExceeded
                        }
                    } else if let index = listContainers.lastIndex(where: {
                        record.level == $0.controlLevel + 1
                    }) {
                        listContainers[index].listHeaderLevel = record.level
                    } else if let object = objectStack.last,
                              record.level > object.controlLevel {
                        listContainers.append(
                            ListContainer(
                                controlLevel: object.controlLevel,
                                region: paragraph?.region ?? .body,
                                listHeaderLevel: record.level,
                                layoutContainerID: object.objectID
                            )
                        )
                        let textLayout: HWPDocumentTextContainerLayout?
                        if record.payload.count >= 16 {
                            var reader = DataReader(record.payload)
                            try reader.seek(to: 4)
                            let flags = try reader.readUInt32()
                            textLayout = HWPDocumentTextContainerLayout(
                                left: Double(try reader.readUInt16()) / 100,
                                right: Double(try reader.readUInt16()) / 100,
                                top: Double(try reader.readUInt16()) / 100,
                                bottom: Double(try reader.readUInt16()) / 100,
                                verticalAlignment: HWPDocumentRelativeAlignment(rawValue: Int((flags >> 5) & 3)) ?? .start,
                                localFrame: record.level > object.controlLevel + 2
                                    ? object.component.map { CGRect(x: $0.localXPoints, y: $0.localYPoints,
                                        width: $0.widthPoints, height: $0.heightPoints) }
                                    : nil
                            )
                        } else { textLayout = nil }
                        updateObject(object) { $0.replacing(textContainerID: object.objectID, layout: textLayout) }
                    }
                case Tag.pageDefinition:
                    layout.installPageDefinition(try PageDefinition(record.payload))
                case Tag.footnoteShape:
                    layout.installNoteStyle(try NoteStyle(record.payload))
                case Tag.pageBorderFill:
                    layout.installPageBorder(
                        try PageBorderFill(record.payload),
                        docInfo: docInfo
                    )
                case Tag.shapeComponent:
                    if let index = objectStack.indices.last,
                       record.level > objectStack[index].controlLevel {
                        if let component = try? ShapeComponentInfo(record.payload) {
                            objectStack[index].component = component
                            let placement = component.applying(
                                to: objectStack[index].info.placement,
                                preservesOuterSize: component.controlID == oleControlID
                            )
                            // Descendant components describe a group's children.
                            // Their last rectangle must not resize the enclosing group.
                            if record.level == objectStack[index].controlLevel + 1 {
                                updateObject(objectStack[index]) {
                                    var updated = placement
                                    updated.sourceCharacterPosition = $0.placement.sourceCharacterPosition
                                    var result = $0.replacing(placement: updated)
                                    if component.controlID == containerControlID,
                                       component.initialWidthPoints > 0,
                                       component.initialHeightPoints > 0 {
                                        result = result.replacing(groupCoordinateFrame: CGRect(
                                            x: 0, y: 0,
                                            width: component.initialWidthPoints,
                                            height: component.initialHeightPoints))
                                    }
                                    return result
                                }
                            }
                            if component.controlID == pictureControlID {
                                objectStack[index].isPicture = true
                            }
                        } else if record.payload.count >= 4,
                                  (UInt32(record.payload[0])
                                    | UInt32(record.payload[1]) << 8
                                    | UInt32(record.payload[2]) << 16
                                    | UInt32(record.payload[3]) << 24)
                                    == pictureControlID {
                            // Older producers may emit only the component control ID.
                            // The parent common-object record already carries the usable
                            // placement, so keep it instead of rejecting the document.
                            objectStack[index].isPicture = true
                        }
                    }
                case Tag.line, Tag.rectangle, Tag.ellipse, Tag.arc,
                     Tag.polygon, Tag.curve, Tag.container:
                    guard let index = objectStack.indices.last,
                          record.level > objectStack[index].controlLevel else { break }
                    let shape = try makeShape(
                        tag: record.tag,
                        payload: record.payload,
                        component: objectStack[index].component
                    )
                    updateObject(objectStack[index]) { $0.appendingShape(shape) }
                    if !objectStack[index].didResolveContent {
                        objectStack[index].didResolveContent = true
                        complexControlCount = max(0, complexControlCount - 1)
                        shapeCount += 1
                    }
                case Tag.picture:
                    guard let index = objectStack.indices.last,
                          record.level > objectStack[index].controlLevel,
                          let image = try makeImage(
                              picturePayload: record.payload,
                              common: objectStack[index].info,
                              docInfo: docInfo,
                              ordinal: imageCount
                          ) else {
                        break
                    }
                    objectStack[index].isPicture = true
                    if !objectStack[index].didResolvePicture {
                        objectStack[index].didResolvePicture = true
                        complexControlCount = max(0, complexControlCount - 1)
                    }
                    paragraph?.images.append(image)
                    updateObject(objectStack[index]) { $0.replacing(content: .image(image)) }
                    imageCount += 1
                case Tag.equation:
                    guard let index = objectStack.indices.last,
                          record.level > objectStack[index].controlLevel else { break }
                    let equation = try EquationProperty(record.payload).value
                    updateObject(objectStack[index]) { $0.replacing(content: .equation(equation)) }
                    if !objectStack[index].didResolveContent {
                        objectStack[index].didResolveContent = true
                        complexControlCount = max(0, complexControlCount - 1)
                        equationCount += 1
                    }
                case Tag.ole:
                    guard let index = objectStack.indices.last,
                          record.level > objectStack[index].controlLevel else { break }
                    let property = try OLEProperty(record.payload)
                    if let chart = try makeChart(
                        property: property,
                        placement: objectStack[index].info.placement,
                        docInfo: docInfo,
                        ordinal: chartCount
                    ) {
                        updateObject(objectStack[index]) { $0.replacing(content: .chart(chart)) }
                        if !objectStack[index].didResolveContent {
                            objectStack[index].didResolveContent = true
                            complexControlCount = max(0, complexControlCount - 1)
                            chartCount += 1
                        }
                    }
                case Tag.chartData:
                    // The two-byte record announces a chart. Rendering data is
                    // extracted from the bounded OLE/OOXML payload above.
                    break
                default:
                    break
                }
            }
            try finishParagraph()
            pageLayouts.append(layout.makeLayout())
        }

        if !objectOverrides.isEmpty {
            blocks = blocks.map { block in
                guard block.canvasObjects.contains(where: { objectOverrides[$0.id] != nil }) else {
                    return block
                }
                return HWPDocumentBlock(
                    id: block.id,
                    sectionPath: block.sectionPath,
                    paragraphIndex: block.paragraphIndex,
                    text: block.text,
                    tableLocation: block.tableLocation,
                    isEditable: block.isEditable,
                    presentation: block.presentation,
                    region: block.region,
                    images: block.images,
                    lineLayouts: block.lineLayouts,
                    canvasObjects: block.canvasObjects.map { objectOverrides[$0.id] ?? $0 },
                    layoutContainerID: block.layoutContainerID
                )
            }
        }

        // All child records have arrived now. Lay out the owner's inline
        // control slots with the final object sizes and keep the text intact.
        blocks = try blocks.map { block in
            guard !block.canvasObjects.isEmpty, var builder = blockBuilders[block.id] else { return block }
            builder.canvasObjects = block.canvasObjects
            let sectionIndex = Int(block.sectionPath.components(separatedBy: "Section").last ?? "0") ?? 0
            return try builder.makeBlock(sectionIndex: sectionIndex, paragraphOrdinal: block.paragraphIndex,
                docInfo: docInfo, allowsEditing: source.allowsEditing)
        }

        // A valid blank paragraph or an empty table is still a document. The
        // viewer must retain its paper and table geometry without requiring text.
        guard !blocks.isEmpty else {
            throw ChatAttachmentError.documentHasNoText
        }

        let fidelity: HWP5DocumentFidelity
        if !sawParagraphHeader || docInfo.characterShapes.isEmpty {
            fidelity = .textOnly
        } else if complexControlCount > 0 || tableCount > 0 {
            fidelity = .simplified
        } else {
            fidelity = .structured
        }
        return HWP5StructuredDocument(
            blocks: HWPListFormatting.renumbering(blocks),
            pageLayouts: pageLayouts,
            fontCount: docInfo.faceNames.count,
            characterShapeCount: docInfo.characterShapes.count,
            paragraphShapeCount: docInfo.paragraphShapes.count,
            styleCount: docInfo.styles.count,
            tableCount: tableCount,
            tableCellCount: tableCellCount,
            imageCount: imageCount,
            headerCount: headerCount,
            footerCount: footerCount,
            footnoteCount: footnoteCount,
            endnoteCount: endnoteCount,
            shapeCount: shapeCount,
            equationCount: equationCount,
            chartCount: chartCount,
            complexControlCount: complexControlCount,
            allowsEditing: source.allowsEditing,
            fidelity: fidelity
        )
    }

    private static func parseDocInfo(_ source: Source) throws -> DocumentInfo {
        guard source.container.containsStream(named: "DocInfo") else {
            return DocumentInfo()
        }
        let stored: Data
        do {
            stored = try source.container.stream(named: "DocInfo")
        } catch OLECompoundFileError.limitExceeded {
            throw ChatAttachmentError.hwpLimitExceeded
        } catch {
            throw ChatAttachmentError.invalidHWP
        }
        let body = try expanded(stored, isCompressed: source.isCompressed)
        let records = try BinaryRecord.records(in: body)
        var result = DocumentInfo()

        for record in records {
            switch record.tag {
            case Tag.idMappings:
                result.mappingCounts = try mappingCounts(record.payload)
            case Tag.binaryData:
                result.binaryDescriptors.append(
                    try BinaryDataDescriptor(record.payload)
                )
            case Tag.faceName:
                result.faceNames.append(try FontFace(payload: record.payload))
            case Tag.borderFill:
                result.borderFills.append(try BorderFill(record.payload))
            case Tag.charShape:
                result.characterShapes.append(
                    try CharacterShape(payload: record.payload)
                )
            case 0x17:
                result.numberings.append(HWPListBinary.levels(record.payload))
            case Tag.bullet:
                result.bullets.append(try BulletDefinition(record.payload))
            case Tag.paraShape:
                result.paragraphShapes.append(
                    try ParagraphShape(payload: record.payload)
                )
            case Tag.style:
                result.styles.append(try DocumentStyle(payload: record.payload))
            default:
                break
            }
        }
        try result.loadEmbeddedImages(from: source)
        return result
    }

    private static func mappingCounts(_ payload: Data) throws -> [Int] {
        guard payload.count >= 14 * 4 else {
            throw ChatAttachmentError.invalidHWP
        }
        var reader = DataReader(payload)
        var result: [Int] = []
        let count = min(18, payload.count / 4)
        result.reserveCapacity(count)
        for _ in 0..<count {
            let value = try reader.readInt32()
            guard value >= 0, value <= 100_000 else {
                throw ChatAttachmentError.invalidHWP
            }
            result.append(Int(value))
        }
        return result
    }

    private static func expanded(
        _ data: Data,
        isCompressed: Bool
    ) throws -> Data {
        if !isCompressed { return data }
        return try HWP5TextExtractor.inflateRawDeflate(
            data,
            maximumBytes: HWP5TextExtractor.maximumSectionBytes
        )
    }

    private static func controlID(_ payload: Data) throws -> UInt32 {
        guard payload.count >= 4 else {
            throw ChatAttachmentError.invalidHWP
        }
        var reader = DataReader(payload)
        return try reader.readUInt32()
    }

    private static func hyperlinkTarget(_ payload: Data) -> String? {
        guard payload.count >= 11 else { return nil }
        let count = Int(payload[9]) | Int(payload[10]) << 8
        let end = 11 + count * 2
        guard count > 0, end <= payload.count,
              let command = String(data: payload.subdata(in: 11..<end), encoding: .utf16LittleEndian) else { return nil }
        var result = "", escaped = false
        for character in command {
            if escaped { result.append(character); escaped = false }
            else if character == "\\" { escaped = true }
            else if character == ";" { break }
            else { result.append(character) }
        }
        return result.isEmpty ? nil : result
    }

    private static func nextTableLocation(
        for paragraphLevel: Int,
        stack: inout [TableContext],
        docInfo: DocumentInfo,
        afterControlLevel: Int?
    ) -> HWPDocumentTableLocation? {
        guard !stack.isEmpty else { return nil }
        let index = stack.count - 1
        // A text box can be anchored inside a table cell. Paragraphs in that
        // text box belong to the object's own list container, not to the
        // surrounding table. A table created inside the text box has a deeper
        // control level and remains eligible here.
        if let afterControlLevel,
           stack[index].controlLevel <= afterControlLevel {
            return nil
        }
        guard let cell = stack[index].activeCell,
              paragraphLevel >= stack[index].cellHeaderLevel else {
            return nil
        }
        let location = HWPDocumentTableLocation(
            table: stack[index].tableIndex,
            row: cell.row,
            column: cell.column,
            paragraph: cell.paragraphOrdinal,
            rowSpan: cell.rowSpan,
            columnSpan: cell.columnSpan,
            boxStyle: docInfo.boxStyle(for: cell.borderFillID),
            cellWidthPoints: cell.widthPoints,
            cellHeightPoints: cell.heightPoints,
            cellMarginLeftPoints: cell.marginLeftPoints,
            cellMarginRightPoints: cell.marginRightPoints,
            cellMarginTopPoints: cell.marginTopPoints,
            cellMarginBottomPoints: cell.marginBottomPoints,
            cellVerticalAlignment: cell.verticalAlignment,
            tablePageBoundaryMode: stack[index].property?.pageBoundaryMode ?? 0,
            repeatsHeaderRow: stack[index].property?.repeatsHeaderRow ?? false,
            tablePlacement: stack[index].placement,
            tableAnchor: stack[index].anchor,
            parent: stack[index].parent,
            backgroundZones: stack[index].property?.backgroundZones(docInfo: docInfo) ?? []
        )
        stack[index].activeCell?.paragraphOrdinal += 1
        return location
    }

    private struct TableContext {
        let tableIndex: Int
        let controlLevel: Int
        let placement: HWPDocumentObjectPlacement
        let anchor: HWPDocumentTableAnchor?
        let parent: HWPDocumentTableParentLocation?
        var property: TableProperty?
        var activeCell: TableCell?
        var cellHeaderLevel = Int.max
    }

    private struct TableProperty {
        struct Zone {
            let startColumn: Int, startRow: Int, endColumn: Int, endRow: Int
            let borderFillID: Int
        }
        let rowCount: Int
        let columnCount: Int
        let borderFillID: Int?
        let pageBoundaryMode: Int
        let repeatsHeaderRow: Bool
        let margins: [Double]
        let zones: [Zone]

        init(payload: Data) throws {
            guard payload.count >= 8 else {
                throw ChatAttachmentError.invalidHWP
            }
            var reader = DataReader(payload)
            let property = try reader.readUInt32()
            pageBoundaryMode = Int(property & 0x03)
            repeatsHeaderRow = property & 0x04 != 0
            rowCount = Int(try reader.readUInt16())
            columnCount = Int(try reader.readUInt16())
            guard rowCount > 0, columnCount > 0 else {
                throw ChatAttachmentError.invalidHWP
            }
            guard rowCount <= 512,
                  columnCount <= 512,
                  rowCount * columnCount <= HWPXDocumentPackage.maximumBlocks else {
                throw ChatAttachmentError.hwpLimitExceeded
            }
            let borderOffset = 18 + rowCount * 2
            if payload.count >= 18 {
                try reader.seek(to: 10)
                margins = try (0..<4).map { _ in Double(try reader.readUInt16()) / 100 }
            } else {
                margins = []
            }
            var parsedZones: [Zone] = []
            if payload.count >= borderOffset + 2 {
                try reader.seek(to: borderOffset)
                borderFillID = Int(try reader.readUInt16())
                if reader.remainingBytes >= 2 {
                    let count = Int(try reader.readUInt16())
                    guard count <= 4096, reader.remainingBytes >= count * 10 else {
                        throw ChatAttachmentError.invalidHWP
                    }
                    for _ in 0..<count {
                        let a = Int(try reader.readUInt16()), b = Int(try reader.readUInt16())
                        let c = Int(try reader.readUInt16()), d = Int(try reader.readUInt16())
                        let fill = Int(try reader.readUInt16())
                        // Some writers store row/column pairs in the opposite
                        // order. Accept that variant only when grid bounds prove it.
                        if a <= c, c < columnCount, b <= d, d < rowCount {
                            parsedZones.append(Zone(startColumn: a, startRow: b, endColumn: c, endRow: d, borderFillID: fill))
                        } else if a <= c, c < rowCount, b <= d, d < columnCount {
                            parsedZones.append(Zone(startColumn: b, startRow: a, endColumn: d, endRow: c, borderFillID: fill))
                        }
                    }
                }
            } else {
                borderFillID = nil
            }
            zones = parsedZones
        }

        func backgroundZones(docInfo: DocumentInfo) -> [HWPDocumentTableBackgroundZone] {
            zones.compactMap { zone in
                guard let style = docInfo.boxStyle(for: zone.borderFillID) else { return nil }
                return HWPDocumentTableBackgroundZone(
                    startRow: zone.startRow, startColumn: zone.startColumn,
                    endRow: zone.endRow, endColumn: zone.endColumn, style: style
                )
            }
        }
    }

    private struct TableCell {
        private struct Candidate {
            let row: Int
            let column: Int
            let rowSpan: Int
            let columnSpan: Int
            let borderFillID: Int
            let widthPoints: Double
            let heightPoints: Double
            let marginLeftPoints: Double
            let marginRightPoints: Double
            let marginTopPoints: Double
            let marginBottomPoints: Double
        }

        let row: Int
        let column: Int
        let rowSpan: Int
        let columnSpan: Int
        let borderFillID: Int
        let widthPoints: Double
        let heightPoints: Double
        let marginLeftPoints: Double
        let marginRightPoints: Double
        let marginTopPoints: Double
        let marginBottomPoints: Double
        let verticalAlignment: HWPDocumentRelativeAlignment
        var paragraphOrdinal = 0

        init?(payload: Data, table: TableProperty?) throws {
            // HWPTAG_LIST_HEADER is exactly six bytes. The 26-byte table-cell
            // property follows it immediately (HWP 5.0 tables 65, 79, 80).
            // Some Hancom/Windows producers insert a two-byte extension after
            // the list header. Parse the published form first, then accept
            // the extension only when its complete cell geometry is valid.
            // A 34-byte payload is the common legacy-writer variant: the
            // extra WORD sits between LIST_HEADER and the cell property. In
            // that case offset 6 can still look superficially valid (for
            // example a 2.82pt-tall cell), so prefer the complete extended
            // layout and retain the published offset as a fallback.
            let offsets = payload.count >= 34 ? [8, 6] : [6]
            let candidates = offsets.compactMap { offset in
                (try? Self.candidate(
                    payload: payload,
                    offset: offset,
                    table: table
                )).map { (offset: offset, cell: $0) }
            }
            guard let (cellOffset, candidate) = candidates.first else {
                return nil
            }
            // In the extended layout the list property sits after the
            // paragraph count and a reserved WORD (pyhwp/hwplib read it at
            // offset 4). Reading it at offset 2 there lands on that reserved
            // WORD and always yields "top" vertical alignment.
            var listReader = DataReader(payload)
            try listReader.seek(to: cellOffset == 8 ? 4 : 2)
            let listProperty = try listReader.readUInt32()
            switch (listProperty >> 5) & 0x03 {
            case 1: verticalAlignment = .center
            case 2: verticalAlignment = .end
            default: verticalAlignment = .start
            }
            row = candidate.row
            column = candidate.column
            rowSpan = candidate.rowSpan
            columnSpan = candidate.columnSpan
            borderFillID = candidate.borderFillID
            widthPoints = candidate.widthPoints
            heightPoints = candidate.heightPoints
            let usesOwnMargins = listProperty & (1 << 16) != 0 || table?.margins.count != 4
            marginLeftPoints = usesOwnMargins ? candidate.marginLeftPoints : table!.margins[0]
            marginRightPoints = usesOwnMargins ? candidate.marginRightPoints : table!.margins[1]
            marginTopPoints = usesOwnMargins ? candidate.marginTopPoints : table!.margins[2]
            marginBottomPoints = usesOwnMargins ? candidate.marginBottomPoints : table!.margins[3]
        }

        private static func candidate(
            payload: Data,
            offset: Int,
            table: TableProperty?
        ) throws -> Candidate {
            guard payload.count >= offset + 26 else {
                throw ChatAttachmentError.invalidHWP
            }
            var reader = DataReader(payload)
            try reader.seek(to: offset)
            let column = Int(try reader.readUInt16())
            let row = Int(try reader.readUInt16())
            let columnSpan = Int(try reader.readUInt16())
            let rowSpan = Int(try reader.readUInt16())
            let rawWidth = try reader.readUInt32()
            let rawHeight = try reader.readUInt32()
            let marginLeft = try reader.readUInt16()
            let marginRight = try reader.readUInt16()
            let marginTop = try reader.readUInt16()
            let marginBottom = try reader.readUInt16()
            let parsedBorderFillID = Int(try reader.readUInt16())

            guard columnSpan > 0,
                  rowSpan > 0,
                  rowSpan <= 512,
                  columnSpan <= 512,
                  rawWidth > 0,
                  rawWidth <= 400_000,
                  rawHeight <= 400_000 else {
                throw ChatAttachmentError.invalidHWP
            }
            if let table {
                guard row < table.rowCount,
                      column < table.columnCount,
                      row + rowSpan <= table.rowCount,
                      column + columnSpan <= table.columnCount else {
                    throw ChatAttachmentError.invalidHWP
                }
            }
            return Candidate(
                row: row,
                column: column,
                rowSpan: rowSpan,
                columnSpan: columnSpan,
                borderFillID: parsedBorderFillID != 0
                    ? parsedBorderFillID
                    : (table?.borderFillID ?? 0),
                widthPoints: Double(rawWidth) / 100,
                heightPoints: Double(rawHeight) / 100,
                marginLeftPoints: Double(marginLeft) / 100,
                marginRightPoints: Double(marginRight) / 100,
                marginTopPoints: Double(marginTop) / 100,
                marginBottomPoints: Double(marginBottom) / 100
            )
        }
    }

    private struct ListContainer {
        let controlLevel: Int
        let region: HWPDocumentRegion
        var listHeaderLevel = Int.max
        var layoutContainerID: String?
    }

    private struct CommonObjectInfo {
        let placement: HWPDocumentObjectPlacement
        let description: String?

        init(_ payload: Data) {
            var parsedX = 0.0
            var parsedY = 0.0
            var parsedWidth = 0.0
            var parsedHeight = 0.0
            var parsedProperty: UInt32 = 0
            var parsedZOrder = 0
            var margins = [Double](repeating: 0, count: 4)
            var parsedDescription: String?
            if payload.count >= 24 {
                var reader = DataReader(payload)
                do {
                    try reader.seek(to: 4)
                    parsedProperty = try reader.readUInt32()
                    parsedY = Self.signedPoints(try reader.readInt32())
                    parsedX = Self.signedPoints(try reader.readInt32())
                    parsedWidth = Self.points(try reader.readInt32())
                    parsedHeight = Self.points(try reader.readInt32())
                    if payload.count >= 36 {
                        parsedZOrder = Int(try reader.readInt32())
                        margins.removeAll(keepingCapacity: true)
                        for _ in 0..<4 {
                            margins.append(
                                Self.points(Int32(try reader.readUInt16()))
                            )
                        }
                    }
                    if payload.count >= 46 {
                        try reader.seek(to: 44)
                        let length = Int(try reader.readUInt16())
                        if length <= reader.remainingBytes / 2 {
                            let bytes = try reader.readData(count: length * 2)
                            parsedDescription = String(
                                data: bytes,
                                encoding: .utf16LittleEndian
                            )
                        }
                    }
                } catch {
                    parsedX = 0
                    parsedY = 0
                    parsedWidth = 0
                    parsedHeight = 0
                    parsedProperty = 0
                    parsedZOrder = 0
                    margins = [0, 0, 0, 0]
                    parsedDescription = nil
                }
            }
            let verticalRaw = Int((parsedProperty >> 3) & 0x03)
            let verticalAlignmentRaw = Int((parsedProperty >> 5) & 0x07)
            let horizontalRaw = Int((parsedProperty >> 8) & 0x03)
            let horizontalAlignmentRaw = Int((parsedProperty >> 10) & 0x07)
            let wrapRaw = Int((parsedProperty >> 21) & 0x07)
            placement = HWPDocumentObjectPlacement(
                xPoints: parsedX,
                yPoints: parsedY,
                widthPoints: parsedWidth > 0 ? parsedWidth : 120,
                heightPoints: parsedHeight > 0 ? parsedHeight : 60,
                zOrder: parsedZOrder,
                isInline: parsedProperty & 1 != 0,
                horizontalReference: Self.horizontalReference(horizontalRaw),
                verticalReference: Self.verticalReference(verticalRaw),
                horizontalAlignment: Self.alignment(horizontalAlignmentRaw),
                verticalAlignment: Self.alignment(verticalAlignmentRaw),
                wrap: [HWPDocumentObjectWrap.square, .topAndBottom, .behindText, .inFrontOfText]
                    .indices.contains(wrapRaw) ? [.square, .topAndBottom, .behindText, .inFrontOfText][wrapRaw] : .square,
                marginLeftPoints: margins[0],
                marginRightPoints: margins[1],
                marginTopPoints: margins[2],
                marginBottomPoints: margins[3]
            )
            description = parsedDescription
        }

        private static func points(_ raw: Int32) -> Double {
            min(max(abs(Double(raw)) / 100, 0), 4_000)
        }

        private static func signedPoints(_ raw: Int32) -> Double {
            min(max(Double(raw) / 100, -4_000), 4_000)
        }

        private static func horizontalReference(
            _ raw: Int
        ) -> HWPDocumentLayoutReference {
            switch raw {
            case 0: return .paper
            case 1: return .page
            case 2: return .column
            case 3: return .paragraph
            default: return .paragraph
            }
        }

        private static func verticalReference(
            _ raw: Int
        ) -> HWPDocumentLayoutReference {
            switch raw {
            case 0: return .paper
            case 1: return .page
            case 2: return .paragraph
            default: return .paragraph
            }
        }

        private static func alignment(_ raw: Int) -> HWPDocumentRelativeAlignment {
            HWPDocumentRelativeAlignment(rawValue: min(max(raw, 0), 4)) ?? .start
        }
    }

    private struct ObjectContext {
        let controlLevel: Int
        let info: CommonObjectInfo
        let objectIndex: Int
        let objectID: String
        let controlID: UInt32
        var component: ShapeComponentInfo?
        var isPicture = false
        var didResolvePicture = false
        var didResolveContent = false
    }

    private struct ShapeComponentInfo {
        let controlID: UInt32
        let localXPoints: Double
        let localYPoints: Double
        let initialWidthPoints: Double
        let initialHeightPoints: Double
        let widthPoints: Double
        let heightPoints: Double
        let flipHorizontal: Bool
        let flipVertical: Bool
        let rotationDegrees: Double
        let stroke: HWPDocumentStroke
        let fill: HWPDocumentFill
        let shadow: HWPDocumentShapeShadow?

        init(_ payload: Data) throws {
            guard payload.count >= 46 else {
                throw ChatAttachmentError.invalidHWP
            }
            var reader = DataReader(payload)
            let firstID = try reader.readUInt32()
            let repeatedID = UInt32(payload[4])
                | UInt32(payload[5]) << 8
                | UInt32(payload[6]) << 16
                | UInt32(payload[7]) << 24
            let hasRepeatedID = firstID == repeatedID
            if hasRepeatedID {
                controlID = try reader.readUInt32()
            } else {
                controlID = firstID
            }
            localXPoints = Self.signedPoints(try reader.readInt32())
            localYPoints = Self.signedPoints(try reader.readInt32())
            _ = try reader.readUInt16() // group depth
            _ = try reader.readUInt16() // local version
            initialWidthPoints = min(Double(try reader.readUInt32()) / 100, 4_000)
            initialHeightPoints = min(Double(try reader.readUInt32()) / 100, 4_000)
            widthPoints = min(abs(Double(try reader.readInt32())) / 100, 4_000)
            heightPoints = min(abs(Double(try reader.readInt32())) / 100, 4_000)
            let flipFlags = try reader.readUInt32()
            flipHorizontal = flipFlags & 1 != 0
            flipVertical = flipFlags & 2 != 0
            rotationDegrees = Double(try reader.readUInt16())
            _ = try reader.readInt32() // rotation center x
            _ = try reader.readInt32() // rotation center y

            var parsedStroke = HWPDocumentStroke()
            var parsedFill = HWPDocumentFill.none
            var parsedShadow: HWPDocumentShapeShadow?
            if reader.remainingBytes >= 2 {
                let matrixCount = Int(try reader.readUInt16())
                guard matrixCount <= 32 else {
                    throw ChatAttachmentError.hwpLimitExceeded
                }
                let matrixBytes = 48 + matrixCount * 96
                if reader.remainingBytes >= matrixBytes {
                    _ = try reader.readData(count: matrixBytes)
                    if reader.remainingBytes >= 13 {
                        let color = rgb(
                            fromColorReference: try reader.readUInt32()
                        ) ?? 0
                        let thickness = abs(Double(try reader.readInt32())) / 100
                        let property = try reader.readUInt32()
                        _ = try reader.readUInt8() // outline position
                        parsedStroke = HWPDocumentStroke(
                            colorRGB: color,
                            widthPoints: max(thickness, 0.1),
                            style: Int(property & 0x3F),
                            startArrow: Int((property >> 10) & 0x3F),
                            endArrow: Int((property >> 16) & 0x3F)
                        )
                        if reader.remainingBytes >= 4 {
                            let fillType = try reader.readUInt32()
                            if fillType & 1 != 0, reader.remainingBytes >= 12 {
                                let background = rgb(
                                    fromColorReference: try reader.readUInt32()
                                )
                                let patternColor = rgb(
                                    fromColorReference: try reader.readUInt32()
                                )
                                let pattern = Int(try reader.readInt32())
                                parsedFill = HWPDocumentFill(
                                    colorRGB: background,
                                    patternColorRGB: patternColor,
                                    pattern: pattern
                                )
                            }
                            // For a plain color/no-fill shape, skip the
                            // length-prefixed fill extension and alpha byte.
                            // Other fill payloads must be decoded before the
                            // shadow can be located; never guess at the tail.
                            if fillType == 0 || fillType == 1,
                               reader.remainingBytes >= 4 {
                                let extraBytes = Int(try reader.readUInt32())
                                let alphaBytes = fillType == 1 ? 1 : 0
                                if extraBytes <= reader.remainingBytes - alphaBytes {
                                    _ = try reader.readData(count: extraBytes + alphaBytes)
                                    if reader.remainingBytes >= 22 {
                                        let kind = Int(try reader.readUInt32())
                                        let color = rgb(fromColorReference: try reader.readUInt32()) ?? 0
                                        let x = Double(try reader.readInt32()) / 100
                                        let y = Double(try reader.readInt32()) / 100
                                        _ = try reader.readUInt32() // instance ID
                                        _ = try reader.readUInt8()
                                        let transparency = try reader.readUInt8()
                                        if (1...4).contains(kind), abs(x) <= 100, abs(y) <= 100 {
                                            parsedShadow = HWPDocumentShapeShadow(kind: kind, colorRGB: color,
                                                offsetX: x, offsetY: y, opacity: 1 - Double(transparency) / 255)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            stroke = parsedStroke
            fill = parsedFill
            shadow = parsedShadow
        }

        func applying(
            to placement: HWPDocumentObjectPlacement,
            preservesOuterSize: Bool = false
        ) -> HWPDocumentObjectPlacement {
            HWPDocumentObjectPlacement(
                xPoints: placement.xPoints,
                yPoints: placement.yPoints,
                widthPoints: !preservesOuterSize && widthPoints > 0
                    ? widthPoints
                    : placement.widthPoints,
                heightPoints: !preservesOuterSize && (heightPoints > 0 || controlID == lineControlID)
                    ? max(heightPoints, 1)
                    : placement.heightPoints,
                zOrder: placement.zOrder,
                rotationDegrees: rotationDegrees,
                flipHorizontal: flipHorizontal,
                flipVertical: flipVertical,
                isInline: placement.isInline,
                horizontalReference: placement.horizontalReference,
                verticalReference: placement.verticalReference,
                horizontalAlignment: placement.horizontalAlignment,
                verticalAlignment: placement.verticalAlignment,
                wrap: placement.wrap,
                marginLeftPoints: placement.marginLeftPoints,
                marginRightPoints: placement.marginRightPoints,
                marginTopPoints: placement.marginTopPoints,
                marginBottomPoints: placement.marginBottomPoints,
                inlineOriginIsResolved: placement.inlineOriginIsResolved
            )
        }

        private static func points(_ raw: UInt32) -> Double {
            min(max(Double(raw) / 100, 0), 4_000)
        }

        private static func signedPoints(_ raw: Int32) -> Double {
            min(max(Double(raw) / 100, -4_000), 4_000)
        }
    }

    private struct EquationProperty {
        let value: HWPDocumentEquation

        init(_ payload: Data) throws {
            guard payload.count >= 16 else {
                throw ChatAttachmentError.invalidHWP
            }
            var reader = DataReader(payload)
            _ = try reader.readUInt32()
            let scriptLength = Int(try reader.readUInt16())
            guard scriptLength <= 32_768,
                  scriptLength <= reader.remainingBytes / 2 else {
                throw ChatAttachmentError.hwpLimitExceeded
            }
            let scriptData = try reader.readData(count: scriptLength * 2)
            let script = String(
                data: scriptData,
                encoding: .utf16LittleEndian
            ) ?? ""
            let fontSize = Double(try reader.readInt32()) / 100
            let color = rgb(fromColorReference: try reader.readUInt32()) ?? 0
            let baseline = Double(try reader.readInt16())
            var fontName: String?
            if reader.remainingBytes >= 2 {
                _ = try? reader.readUTF16String() // equation engine version
            }
            if reader.remainingBytes >= 2 {
                fontName = try? reader.readUTF16String()
            }
            value = HWPDocumentEquation(
                script: HanyangPUANormalizer.normalize(script),
                fontSizePoints: fontSize,
                colorRGB: color,
                baselinePercent: baseline,
                fontName: fontName
            )
        }
    }

    private struct OLEProperty {
        let property: UInt16
        let binaryID: Int

        init(_ payload: Data) throws {
            guard payload.count >= 12 else {
                throw ChatAttachmentError.invalidHWP
            }
            var reader = DataReader(payload)
            property = try reader.readUInt16()
            _ = try reader.readInt32()
            _ = try reader.readInt32()
            let compactBinaryID = Int(try reader.readUInt16())
            if compactBinaryID > 0 {
                binaryID = compactBinaryID
            } else if payload.count >= 14 {
                // Hancom 2020 writes the OLE property as UINT32 even though
                // the 5.0 specification documents UINT16. In that variant
                // both extents and the BinData ID are shifted by two bytes.
                try reader.seek(to: 12)
                binaryID = Int(try reader.readUInt16())
            } else {
                binaryID = compactBinaryID
            }
        }
    }

    private static func activeListContainer(
        for paragraphLevel: Int,
        containers: [ListContainer]
    ) -> ListContainer? {
        containers.last(where: {
            $0.listHeaderLevel != Int.max
                && paragraphLevel >= $0.listHeaderLevel
        })
    }

    private static func headerFooterScope(
        _ payload: Data
    ) -> HWPDocumentHeaderFooterScope {
        guard payload.count >= 8 else { return .bothPages }
        let property = UInt32(payload[4])
            | UInt32(payload[5]) << 8
            | UInt32(payload[6]) << 16
            | UInt32(payload[7]) << 24
        switch property & 0x03 {
        case 1:
            return .evenPages
        case 2:
            return .oddPages
        default:
            return .bothPages
        }
    }

    private static func makeImage(
        picturePayload: Data,
        common: CommonObjectInfo,
        docInfo: DocumentInfo,
        ordinal: Int
    ) throws -> HWPDocumentImage? {
        guard picturePayload.count >= 73 else {
            throw ChatAttachmentError.invalidHWP
        }
        var reader = DataReader(picturePayload)
        let borderColorReference = try reader.readUInt32()
        let borderColor = rgb(
            fromColorReference: borderColorReference
        ) ?? 0
        let rawBorderWidth = try reader.readInt32()
        let borderWidth = min(
            max(abs(Double(rawBorderWidth)) / 100, 0.25),
            32
        )
        let borderProperty = try reader.readUInt32()
        var corners: [(x: Int32, y: Int32)] = []
        for index in 0..<4 {
            try reader.seek(to: 12 + index * 8)
            let x = try reader.readInt32()
            corners.append((x, try reader.readInt32()))
        }
        try reader.seek(to: 44)
        let cropLeft = try reader.readInt32()
        let cropTop = try reader.readInt32()
        let cropRight = try reader.readInt32()
        let cropBottom = try reader.readInt32()
        try reader.seek(to: 71)
        let binaryID = Int(try reader.readUInt16())
        let brightness = Int(Int8(bitPattern: picturePayload[68]))
        let contrast = Int(Int8(bitPattern: picturePayload[69]))
        let effect = HWPDocumentImageEffect(rawValue: Int(picturePayload[70])) ?? .original
        guard let binary = docInfo.embeddedImages[binaryID] else { return nil }

        var width = common.placement.widthPoints
        var height = common.placement.heightPoints
        if width <= 0 || height <= 0 {
            if let minX = corners.map(\.x).min(),
               let maxX = corners.map(\.x).max(),
               let minY = corners.map(\.y).min(),
               let maxY = corners.map(\.y).max() {
                width = min(max(abs(Double(maxX) - Double(minX)) / 100, 1), 2_000)
                height = min(max(abs(Double(maxY) - Double(minY)) / 100, 1), 2_000)
            }
        }
        if width <= 0 { width = 240 }
        if height <= 0 { height = 180 }
        let sourceMinX = corners.map(\.x).min() ?? 0
        let sourceMaxX = corners.map(\.x).max() ?? 0
        let sourceMinY = corners.map(\.y).min() ?? 0
        let sourceMaxY = corners.map(\.y).max() ?? 0
        var sourceWidth = Double(sourceMaxX) - Double(sourceMinX)
        var sourceHeight = Double(sourceMaxY) - Double(sourceMinY)
        // Replacing a bitmap in Hancom can retain the old shape rectangle.
        // Its crop limits still describe the new bitmap in 96dpi HWP units.
        // Recognize a full-bitmap crop against the actual payload, rather
        // than magnifying the corner of the smaller replacement image.
        if let source = CGImageSourceCreateWithData(binary.data as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let pixelWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
           let pixelHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber {
            let nativeWidth = pixelWidth.doubleValue * 75
            let nativeHeight = pixelHeight.doubleValue * 75
            if cropLeft == 0, cropTop == 0,
               abs(Double(cropRight) - nativeWidth) <= 75,
               abs(Double(cropBottom) - nativeHeight) <= 75,
               abs(sourceWidth - nativeWidth) > 150 {
                sourceWidth = Double(cropRight)
                sourceHeight = Double(cropBottom)
            }
        }
        let cropRect: CGRect?
        if cropRight > cropLeft,
           cropBottom > cropTop,
           sourceWidth > 0,
           sourceHeight > 0 {
            cropRect = CGRect(
                x: (Double(cropLeft) - Double(sourceMinX)) / sourceWidth,
                y: (Double(cropTop) - Double(sourceMinY)) / sourceHeight,
                width: Double(cropRight - cropLeft) / sourceWidth,
                height: Double(cropBottom - cropTop) / sourceHeight
            )
        } else {
            cropRect = nil
        }
        return HWPDocumentImage(
            id: "hwp-image-\(binaryID)-\(ordinal)",
            binaryID: binaryID,
            data: binary.data,
            widthPoints: width,
            heightPoints: height,
            description: common.description,
            cropRect: cropRect,
            borderStroke: rawBorderWidth == 0
                || borderColorReference == UInt32.max
                ? nil
                : HWPDocumentStroke(
                    colorRGB: borderColor,
                    widthPoints: borderWidth,
                    style: Int(borderProperty & 0x3F),
                    startArrow: 0,
                    endArrow: 0
            ),
            brightness: brightness,
            contrast: contrast,
            effect: effect,
            transparencyPercent: 0,
            supportsTransparency: false
        )
    }

    private static func makeShape(
        tag: UInt32,
        payload: Data,
        component: ShapeComponentInfo?
    ) throws -> HWPDocumentShape {
        let stroke = component?.stroke ?? HWPDocumentStroke()
        let fill = component?.fill ?? .none
        var reader = DataReader(payload)
        let geometry: HWPDocumentShapeGeometry
        switch tag {
        case Tag.line:
            guard payload.count >= 16 else {
                throw ChatAttachmentError.invalidHWP
            }
            geometry = .line(
                start: try point(reader: &reader),
                end: try point(reader: &reader)
            )
        case Tag.rectangle:
            guard payload.count >= 33 else {
                geometry = .rectangle(cornerRadiusPercent: 0, points: [])
                break
            }
            let radius = min(max(Double(try reader.readUInt8()), 0), 100)
            // Each corner is an (x, y) pair in HWPUNIT, not separate axes.
            var corners: [HWPDocumentPoint] = []
            for _ in 0..<4 { corners.append(try point(reader: &reader)) }
            geometry = .rectangle(
                cornerRadiusPercent: radius,
                points: corners
            )
        case Tag.ellipse:
            guard payload.count >= 28 else {
                throw ChatAttachmentError.invalidHWP
            }
            _ = try reader.readUInt32()
            geometry = .ellipse(
                center: try point(reader: &reader),
                axis1: try point(reader: &reader),
                axis2: try point(reader: &reader)
            )
        case Tag.arc:
            guard payload.count >= 25 else {
                throw ChatAttachmentError.invalidHWP
            }
            let property: UInt32
            if payload.count >= 28 {
                property = try reader.readUInt32()
            } else {
                property = UInt32(try reader.readUInt8())
            }
            geometry = .arc(
                center: try point(reader: &reader),
                axis1: try point(reader: &reader),
                axis2: try point(reader: &reader),
                kind: Int((property >> 2) & 0xFF)
            )
        case Tag.polygon, Tag.curve:
            guard payload.count >= 2 else {
                throw ChatAttachmentError.invalidHWP
            }
            let count = Int(try reader.readInt16())
            guard count >= 2, count <= 4_096 else {
                throw ChatAttachmentError.invalidHWP
            }
            let compactCoordinates = try coordinateArrays(
                payload: payload,
                count: count,
                offset: 2,
                segmentByteCount: tag == Tag.curve ? count - 1 : 0
            )
            let extendedCoordinates = try? coordinateArrays(
                payload: payload,
                count: count,
                offset: 4,
                segmentByteCount: tag == Tag.curve ? count - 1 : 0
            )
            let coordinates: ShapeCoordinateArrays
            if let extendedCoordinates,
               extendedCoordinates.maximumMagnitude
                < compactCoordinates.maximumMagnitude {
                // Several modern writers serialize the documented INT16
                // point count as UINT32. Pick the bounded coordinate stream
                // instead of interpreting the two padding bytes as X data.
                coordinates = extendedCoordinates
            } else {
                coordinates = compactCoordinates
            }
            let xs = coordinates.xs
            let ys = coordinates.ys
            let points = zip(xs, ys).map { point(x: $0.0, y: $0.1) }
            if tag == Tag.polygon {
                geometry = .polygon(points: points)
            } else {
                try reader.seek(to: coordinates.endOffset)
                var curved: [Bool] = []
                curved.reserveCapacity(max(0, count - 1))
                for _ in 0..<max(0, count - 1) {
                    curved.append(
                        reader.remainingBytes > 0
                            ? try reader.readUInt8() != 0
                            : false
                    )
                }
                geometry = .curve(points: points, curvedSegments: curved)
            }
        case Tag.container:
            geometry = .container
        default:
            geometry = .unknown
        }
        return HWPDocumentShape(
            geometry: geometry,
            stroke: stroke,
            fill: fill,
            localFrame: component.map {
                CGRect(
                    x: $0.localXPoints,
                    y: $0.localYPoints,
                    width: max($0.widthPoints, 1),
                    height: max($0.heightPoints, 1)
                )
            },
            rotationDegrees: component?.rotationDegrees ?? 0,
            flipHorizontal: component?.flipHorizontal ?? false,
            flipVertical: component?.flipVertical ?? false,
            shadow: component?.shadow
        )
    }

    private struct ShapeCoordinateArrays {
        let xs: [Int32]
        let ys: [Int32]
        let endOffset: Int
        let maximumMagnitude: Int64
    }

    private static func coordinateArrays(
        payload: Data,
        count: Int,
        offset: Int,
        segmentByteCount: Int
    ) throws -> ShapeCoordinateArrays {
        let endOffset = offset + count * 8
        guard offset >= 0,
              count >= 0,
              endOffset <= payload.count,
              endOffset + segmentByteCount <= payload.count else {
            throw ChatAttachmentError.invalidHWP
        }
        var reader = DataReader(payload)
        try reader.seek(to: offset)
        var xs: [Int32] = []
        var ys: [Int32] = []
        xs.reserveCapacity(count)
        ys.reserveCapacity(count)
        for _ in 0..<count { xs.append(try reader.readInt32()) }
        for _ in 0..<count { ys.append(try reader.readInt32()) }
        let maximumMagnitude = (xs + ys).reduce(Int64(0)) { maximum, value in
            max(maximum, abs(Int64(value)))
        }
        return ShapeCoordinateArrays(
            xs: xs,
            ys: ys,
            endOffset: endOffset,
            maximumMagnitude: maximumMagnitude
        )
    }

    private static func point(
        reader: inout DataReader
    ) throws -> HWPDocumentPoint {
        point(x: try reader.readInt32(), y: try reader.readInt32())
    }

    private static func point(x: Int32, y: Int32) -> HWPDocumentPoint {
        HWPDocumentPoint(x: Double(x) / 100, y: Double(y) / 100)
    }

    private static func makeChart(
        property: OLEProperty,
        placement: HWPDocumentObjectPlacement,
        docInfo: DocumentInfo,
        ordinal: Int
    ) throws -> HWPDocumentChart? {
        guard let binary = docInfo.embeddedBinaries[property.binaryID] else {
            return nil
        }
        let signature: [UInt8] = [
            0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1,
        ]
        guard binary.data.count >= signature.count else { return nil }
        let searchLimit = min(64, max(0, binary.data.count - signature.count))
        let offset = (0...searchLimit).first { candidate in
            Array(binary.data[candidate..<(candidate + signature.count)]) == signature
        }
        guard let offset else { return nil }
        let containerData = Data(binary.data.dropFirst(offset))
        let container: OLECompoundFile
        do {
            container = try OLECompoundFile(
                data: containerData,
                limits: .init(
                    maximumFileBytes: HWP5TextExtractor.maximumSectionBytes,
                    maximumDirectoryEntries: 512,
                    maximumStreamBytes: HWP5TextExtractor.maximumSectionBytes,
                    maximumChainSectors: 32_768
                )
            )
        } catch {
            return nil
        }
        var preview: HWPDocumentImage?
        var previewMetafile: HWPDocumentMetafile?
        for name in container.streamNames where name.contains("olepres") {
            guard let stream = try? container.stream(named: name),
                  let content = olePresentationContent(stream) else { continue }
            switch content {
            case .image(let data):
                preview = HWPDocumentImage(
                    id: "hwp-chart-preview-\(property.binaryID)-\(ordinal)",
                    binaryID: property.binaryID,
                    data: data,
                    widthPoints: placement.widthPoints,
                    heightPoints: placement.heightPoints,
                    description: "차트 미리보기"
                )
            case .windowsMetafile(let data, let width, let height):
                previewMetafile = HWPDocumentMetafile(
                    data: data,
                    widthLogical: width,
                    heightLogical: height
                )
            }
            if preview != nil || previewMetafile != nil { break }
        }
        guard let xmlName = container.streamNames.first(where: {
            $0.hasSuffix("ooxmlchartcontents")
        }), let xml = try? container.stream(named: xmlName) else {
            guard preview != nil || previewMetafile != nil else { return nil }
            return HWPDocumentChart(
                kind: .unknown,
                title: "포함된 차트",
                categories: [],
                series: [],
                previewImage: preview,
                previewMetafile: previewMetafile
            )
        }
        let parsed = try HWPChartOOXMLParser.parse(xml)
        return HWPDocumentChart(
            kind: parsed.kind,
            title: parsed.title,
            categories: parsed.categories,
            series: parsed.series,
            previewImage: preview,
            previewMetafile: previewMetafile
        )
    }

    private enum OLEPresentationContent {
        case image(Data)
        case windowsMetafile(Data, width: Int, height: Int)
    }

    /// Extracts a renderable preview from an MS-OLEDS OLEPresentationStream.
    /// CF_DIB payloads lack the 14-byte BMP wrapper; CF_METAFILEPICT payloads
    /// contain a standard WMF stream that is played by our local renderer.
    private static func olePresentationContent(
        _ stream: Data
    ) -> OLEPresentationContent? {
        if DocumentInfo.isSupportedImage(stream) { return .image(stream) }

        func uint32(at offset: Int) -> UInt32? {
            guard offset >= 0, offset + 4 <= stream.count else { return nil }
            return UInt32(stream[offset])
                | UInt32(stream[offset + 1]) << 8
                | UInt32(stream[offset + 2]) << 16
                | UInt32(stream[offset + 3]) << 24
        }

        guard let markerOrLength = uint32(at: 0) else { return nil }
        var cursor: Int
        let clipboardFormat: UInt32?
        if markerOrLength == UInt32.max {
            clipboardFormat = uint32(at: 4)
            cursor = 8
        } else {
            let length = Int(markerOrLength)
            guard length > 0, length <= 4_096, 4 + length <= stream.count else {
                return nil
            }
            clipboardFormat = nil
            cursor = 4 + length
        }
        guard let targetDeviceSize = uint32(at: cursor),
              targetDeviceSize >= 4,
              targetDeviceSize <= 1_048_576 else { return nil }
        cursor += Int(targetDeviceSize)
        // Aspect, Lindex, Advf, Reserved1, Width, Height.
        guard cursor + 28 <= stream.count,
              let rawWidth = uint32(at: cursor + 16),
              let rawHeight = uint32(at: cursor + 20),
              let size = uint32(at: cursor + 24) else { return nil }
        let dataStart = cursor + 28
        let dataLength = Int(size)
        guard dataLength >= 0,
              dataLength <= HWP5TextExtractor.maximumSectionBytes,
              dataStart + dataLength <= stream.count else { return nil }
        let payload = Data(stream[dataStart..<(dataStart + dataLength)])
        if DocumentInfo.isSupportedImage(payload) { return .image(payload) }
        switch clipboardFormat {
        case 0x0000_0008: // CF_DIB
            return bitmapFile(fromDIB: payload).map(OLEPresentationContent.image)
        case 0x0000_0003: // CF_METAFILEPICT
            guard payload.count >= 18,
                  payload[0] == 1 || payload[0] == 2,
                  payload[2] == 9 else { return nil }
            return .windowsMetafile(
                payload,
                width: max(1, Int(rawWidth)),
                height: max(1, Int(rawHeight))
            )
        default:
            return nil
        }
    }

    private static func bitmapFile(fromDIB dib: Data) -> Data? {
        func uint16(at offset: Int) -> UInt16? {
            guard offset >= 0, offset + 2 <= dib.count else { return nil }
            return UInt16(dib[offset]) | UInt16(dib[offset + 1]) << 8
        }
        func uint32(at offset: Int) -> UInt32? {
            guard offset >= 0, offset + 4 <= dib.count else { return nil }
            return UInt32(dib[offset])
                | UInt32(dib[offset + 1]) << 8
                | UInt32(dib[offset + 2]) << 16
                | UInt32(dib[offset + 3]) << 24
        }
        func appendUInt32(_ value: UInt32, to data: inout Data) {
            data.append(UInt8(value & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8((value >> 16) & 0xFF))
            data.append(UInt8((value >> 24) & 0xFF))
        }

        guard let headerSizeValue = uint32(at: 0),
              headerSizeValue >= 12,
              headerSizeValue <= UInt32(dib.count),
              dib.count <= Int(UInt32.max) - 14 else { return nil }
        let headerSize = Int(headerSizeValue)
        let paletteBytes: Int
        let maskBytes: Int
        if headerSize == 12 {
            guard let bitCount = uint16(at: 10), bitCount <= 32 else { return nil }
            paletteBytes = bitCount <= 8 ? (1 << Int(bitCount)) * 3 : 0
            maskBytes = 0
        } else {
            guard headerSize >= 40,
                  let bitCount = uint16(at: 14),
                  let compression = uint32(at: 16),
                  let colorsUsed = uint32(at: 32),
                  bitCount <= 64 else { return nil }
            let paletteCount = colorsUsed > 0
                ? Int(colorsUsed)
                : (bitCount <= 8 ? 1 << Int(bitCount) : 0)
            guard paletteCount <= 65_536 else { return nil }
            paletteBytes = paletteCount * 4
            maskBytes = headerSize == 40 && (compression == 3 || compression == 6)
                ? (compression == 6 ? 16 : 12)
                : 0
        }
        let pixelOffset = 14 + headerSize + maskBytes + paletteBytes
        guard pixelOffset <= 14 + dib.count else { return nil }

        var result = Data([0x42, 0x4D])
        appendUInt32(UInt32(14 + dib.count), to: &result)
        result.append(contentsOf: [0, 0, 0, 0])
        appendUInt32(UInt32(pixelOffset), to: &result)
        result.append(dib)
        return result
    }

    private struct PageDefinition {
        let widthPoints: Double
        let heightPoints: Double
        let leftMarginPoints: Double
        let rightMarginPoints: Double
        let topMarginPoints: Double
        let bottomMarginPoints: Double
        let headerMarginPoints: Double
        let footerMarginPoints: Double
        let gutterPoints: Double
        let isLandscape: Bool

        init(_ payload: Data) throws {
            guard payload.count >= 40 else { throw ChatAttachmentError.invalidHWP }
            var reader = DataReader(payload)
            let storedWidthPoints = Self.points(try reader.readInt32())
            let storedHeightPoints = Self.points(try reader.readInt32())
            leftMarginPoints = Self.points(try reader.readInt32())
            rightMarginPoints = Self.points(try reader.readInt32())
            topMarginPoints = Self.points(try reader.readInt32())
            bottomMarginPoints = Self.points(try reader.readInt32())
            headerMarginPoints = Self.points(try reader.readInt32())
            footerMarginPoints = Self.points(try reader.readInt32())
            gutterPoints = Self.points(try reader.readInt32())
            isLandscape = try reader.readUInt32() & 1 != 0
            // PAGE_DEF keeps the paper's narrow/wide dimensions in the first
            // two fields and stores the visible orientation independently in
            // bit 0. Real Hancom files therefore keep A4 as 595x842 even for
            // a landscape section. Present the effective canvas dimensions to
            // pagination and rendering while retaining the declared margins.
            widthPoints = isLandscape ? storedHeightPoints : storedWidthPoints
            heightPoints = isLandscape ? storedWidthPoints : storedHeightPoints
            guard widthPoints >= 72, heightPoints >= 72 else {
                throw ChatAttachmentError.invalidHWP
            }
        }

        private static func points(_ raw: Int32) -> Double {
            min(max(Double(raw) / 100, 0), 2_000)
        }
    }

    private struct PageBorderFill {
        let borderFillID: Int

        init(_ payload: Data) throws {
            guard payload.count >= 14 else { throw ChatAttachmentError.invalidHWP }
            var reader = DataReader(payload)
            try reader.seek(to: 12)
            borderFillID = Int(try reader.readUInt16())
        }
    }

    private struct NoteStyle {
        let value: HWPDocumentNoteStyle

        init(_ payload: Data) throws {
            guard payload.count >= 26 else { throw ChatAttachmentError.invalidHWP }
            var reader = DataReader(payload)
            _ = try reader.readUInt32()
            _ = try reader.readData(count: 6)
            let startingNumber = Int(try reader.readUInt16())
            let separatorLength = Self.points(try reader.readInt16())
            let marginTop = Self.points(try reader.readInt16())
            let marginBottom = Self.points(try reader.readInt16())
            let noteSpacing = Self.points(try reader.readInt16())
            let type = try reader.readUInt8()
            let thickness = try reader.readUInt8()
            let color = rgb(fromColorReference: try reader.readUInt32()) ?? 0
            value = HWPDocumentNoteStyle(
                startingNumber: max(1, startingNumber),
                separatorLengthPoints: separatorLength,
                separatorMarginTopPoints: marginTop,
                separatorMarginBottomPoints: marginBottom,
                noteSpacingPoints: noteSpacing,
                separator: HWPDocumentBorderLine(
                    kind: type,
                    widthPoints: borderWidthPoints(thickness),
                    colorRGB: color
                )
            )
        }

        private static func points(_ raw: Int16) -> Double {
            min(max(Double(raw) / 100, 0), 360)
        }
    }

    private struct SectionLayoutBuilder {
        let sectionIndex: Int
        var pageDefinition: PageDefinition?
        var sectionProperty: UInt32 = 0
        var pageStyle: HWPDocumentBoxStyle?
        var noteStyles: [HWPDocumentNoteStyle] = []
        var columnDefinition: ColumnDefinition?
        var pageNumberStyle: HWPDocumentPageNumberStyle?
        var pageNumberStart: Int?
        var resolvedPageNumberStyle: HWPDocumentPageNumberStyle? {
            pageNumberStyle.map { .init(position: $0.position, sideCharacter: $0.sideCharacter, startsAt: pageNumberStart) }
        }

        mutating func installPageNumber(_ payload: Data) {
            guard payload.count >= 16 else { return }
            var reader = DataReader(payload)
            try? reader.seek(to: 4)
            guard let flags = try? reader.readUInt32() else { return }
            let positions = ["NONE", "TOP_LEFT", "TOP_CENTER", "TOP_RIGHT", "BOTTOM_LEFT", "BOTTOM_CENTER", "BOTTOM_RIGHT"]
            let position = Int((flags >> 8) & 15)
            // Other numbering formats and facing-page positions need their
            // own formatting rules; do not display an incorrect decimal label.
            guard (1...6).contains(position), flags & 0xFF == 0 else { return }
            try? reader.seek(to: 14)
            let dash = (try? reader.readUInt16()) ?? 0
            pageNumberStyle = HWPDocumentPageNumberStyle(
                position: positions[position],
                sideCharacter: dash == 0 ? "" : String(decoding: [dash], as: UTF16.self),
                startsAt: nil
            )
        }

        mutating func installSectionProperty(_ payload: Data) {
            guard payload.count >= 8 else { return }
            if payload.count >= 22 {
                let start = Int(payload[20]) | Int(payload[21]) << 8
                pageNumberStart = start > 0 ? start : nil
            }
            sectionProperty = UInt32(payload[4])
                | UInt32(payload[5]) << 8
                | UInt32(payload[6]) << 16
                | UInt32(payload[7]) << 24
        }

        mutating func installPageDefinition(_ definition: PageDefinition) {
            pageDefinition = definition
        }

        mutating func installColumnDefinition(_ payload: Data) {
            guard let parsed = try? ColumnDefinition(payload),
                  parsed.count > (columnDefinition?.count ?? 0) else { return }
            columnDefinition = parsed
        }

        mutating func installNoteStyle(_ style: NoteStyle) {
            if noteStyles.count < 2 { noteStyles.append(style.value) }
        }

        mutating func installPageBorder(
            _ border: PageBorderFill,
            docInfo: DocumentInfo
        ) {
            if pageStyle == nil {
                pageStyle = docInfo.boxStyle(for: border.borderFillID)
            }
        }

        func makeLayout() -> HWPDocumentPageLayout {
            let fallback = HWPDocumentPageLayout.standard(sectionIndex: sectionIndex)
            guard let pageDefinition else {
                return HWPDocumentPageLayout(
                    sectionIndex: sectionIndex,
                    widthPoints: fallback.widthPoints,
                    heightPoints: fallback.heightPoints,
                    leftMarginPoints: fallback.leftMarginPoints,
                    rightMarginPoints: fallback.rightMarginPoints,
                    topMarginPoints: fallback.topMarginPoints,
                    bottomMarginPoints: fallback.bottomMarginPoints,
                    headerMarginPoints: fallback.headerMarginPoints,
                    footerMarginPoints: fallback.footerMarginPoints,
                    gutterPoints: fallback.gutterPoints,
                    isLandscape: fallback.isLandscape,
                    hidesHeader: sectionProperty & 1 != 0,
                    hidesFooter: sectionProperty & 2 != 0,
                    hidesBackground: sectionProperty & 4 != 0,
                    hidesPageBorder: sectionProperty & 8 != 0,
                    hidesPageBackground: sectionProperty & 16 != 0,
                    pageBorderFirstPageOnly: sectionProperty & (1 << 8) != 0,
                    pageBackgroundFirstPageOnly: sectionProperty & (1 << 9) != 0,
                    pageStyle: pageStyle,
                    footnoteStyle: noteStyles.first,
                    endnoteStyle: noteStyles.count > 1 ? noteStyles[1] : nil,
                    columnLayout: makeColumns(for: fallback),
                    pageNumberStyle: resolvedPageNumberStyle, pageNumberStart: pageNumberStart
                )
            }
            return HWPDocumentPageLayout(
                sectionIndex: sectionIndex,
                widthPoints: pageDefinition.widthPoints,
                heightPoints: pageDefinition.heightPoints,
                leftMarginPoints: pageDefinition.leftMarginPoints,
                rightMarginPoints: pageDefinition.rightMarginPoints,
                topMarginPoints: pageDefinition.topMarginPoints,
                bottomMarginPoints: pageDefinition.bottomMarginPoints,
                headerMarginPoints: pageDefinition.headerMarginPoints,
                footerMarginPoints: pageDefinition.footerMarginPoints,
                gutterPoints: pageDefinition.gutterPoints,
                isLandscape: pageDefinition.isLandscape,
                hidesHeader: sectionProperty & 1 != 0,
                hidesFooter: sectionProperty & 2 != 0,
                hidesBackground: sectionProperty & 4 != 0,
                hidesPageBorder: sectionProperty & 8 != 0,
                hidesPageBackground: sectionProperty & 16 != 0,
                pageBorderFirstPageOnly: sectionProperty & (1 << 8) != 0,
                pageBackgroundFirstPageOnly: sectionProperty & (1 << 9) != 0,
                pageStyle: pageStyle,
                footnoteStyle: noteStyles.first,
                endnoteStyle: noteStyles.count > 1 ? noteStyles[1] : nil,
                columnLayout: makeColumns(
                    pageWidth: pageDefinition.widthPoints,
                    leftMargin: pageDefinition.leftMarginPoints,
                    rightMargin: pageDefinition.rightMarginPoints
                ),
                pageNumberStyle: resolvedPageNumberStyle, pageNumberStart: pageNumberStart
            )
        }

        private func makeColumns(
            for layout: HWPDocumentPageLayout
        ) -> HWPDocumentColumnLayout {
            makeColumns(
                pageWidth: layout.widthPoints,
                leftMargin: layout.leftMarginPoints,
                rightMargin: layout.rightMarginPoints
            )
        }

        private func makeColumns(
            pageWidth: Double,
            leftMargin: Double,
            rightMargin: Double
        ) -> HWPDocumentColumnLayout {
            guard let definition = columnDefinition,
                  definition.count > 1 else { return .single }
            let contentWidth = max(1, pageWidth - leftMargin - rightMargin)
            let gap = min(
                max(definition.gapPoints, 0),
                contentWidth / Double(definition.count)
            )
            let available = max(
                1,
                contentWidth - gap * Double(definition.count - 1)
            )
            let widths: [Double]
            if definition.widths.count == definition.count,
               definition.widths.reduce(0, +) > 0 {
                let total = definition.widths.reduce(0, +)
                widths = definition.widths.map { available * $0 / total }
            } else {
                widths = Array(
                    repeating: available / Double(definition.count),
                    count: definition.count
                )
            }
            var x = 0.0
            let columns = widths.map { width in
                defer { x += width + gap }
                return HWPDocumentColumn(xPoints: x, widthPoints: width)
            }
            return HWPDocumentColumnLayout(
                columns: columns,
                gapPoints: gap,
                separator: definition.separator
            )
        }
    }

    private struct ColumnDefinition {
        let count: Int
        let gapPoints: Double
        let widths: [Double]
        let separator: HWPDocumentBorderLine?

        init(_ payload: Data) throws {
            guard payload.count >= 8 else {
                throw ChatAttachmentError.invalidHWP
            }
            var reader = DataReader(payload)
            try reader.seek(to: 4)
            let lowProperty = try reader.readUInt16()
            count = Int((lowProperty >> 2) & 0xFF)
            guard (1...255).contains(count) else {
                throw ChatAttachmentError.invalidHWP
            }
            gapPoints = Double(try reader.readUInt16()) / 100
            let equalWidths = lowProperty & (1 << 12) != 0
            var parsedWidths: [Double] = []
            if !equalWidths, count > 1 {
                if reader.remainingBytes >= count * 2 + 8 {
                    for _ in 0..<count {
                        parsedWidths.append(
                            Double(try reader.readUInt16()) / 100
                        )
                    }
                }
            }
            widths = parsedWidths
            if reader.remainingBytes >= 8 {
                _ = try reader.readUInt16()
                let kind = try reader.readUInt8()
                let thickness = try reader.readUInt8()
                let color = rgb(fromColorReference: try reader.readUInt32()) ?? 0
                separator = kind == 0 && thickness == 0
                    ? nil
                    : HWPDocumentBorderLine(
                        kind: kind,
                        widthPoints: borderWidthPoints(thickness),
                        colorRGB: color
                    )
            } else {
                separator = nil
            }
        }
    }

    private struct Source {
        let container: OLECompoundFile
        let isCompressed: Bool
        let allowsEditing: Bool
        let sections: [(index: Int, name: String)]

        init(data: Data) throws {
            guard data.count <= HWP5TextExtractor.maximumDocumentBytes else {
                throw ChatAttachmentError.fileTooLarge(
                    maximumMegabytes:
                        HWP5TextExtractor.maximumDocumentBytes / 1_024 / 1_024
                )
            }
            do {
                container = try OLECompoundFile(
                    data: data,
                    limits: .init(
                        maximumFileBytes: HWP5TextExtractor.maximumDocumentBytes,
                        maximumDirectoryEntries: 4_096,
                        maximumStreamBytes: HWP5TextExtractor.maximumSectionBytes,
                        maximumChainSectors: 65_536
                    )
                )
            } catch OLECompoundFileError.limitExceeded {
                throw ChatAttachmentError.hwpLimitExceeded
            } catch {
                throw ChatAttachmentError.invalidHWP
            }

            let header: Data
            do {
                header = try container.stream(named: "FileHeader")
            } catch {
                throw ChatAttachmentError.invalidHWP
            }
            guard header.count >= 48,
                  String(data: header.prefix(17), encoding: .ascii)
                    == "HWP Document File" else {
                throw ChatAttachmentError.invalidHWP
            }
            var reader = DataReader(header)
            try reader.seek(to: 32)
            let version = try reader.readUInt32()
            guard version >> 24 == 5 else {
                throw ChatAttachmentError.unsupportedHWPVersion
            }
            let properties = try reader.readUInt32()
            let unsupportedSecurityFlags: UInt32 =
                (1 << 1)
                | (1 << 2)
                | (1 << 4)
                | (1 << 8)
                | (1 << 10)
                | (1 << 13)
            guard properties & unsupportedSecurityFlags == 0 else {
                throw ChatAttachmentError.encryptedHWP
            }
            isCompressed = properties & 0x01 != 0
            let integritySensitiveFlags: UInt32 =
                (1 << 7)  // electronic signature
                | (1 << 9) // signature reserve
                | (1 << 14) // tracked changes
            allowsEditing = properties & integritySensitiveFlags == 0

            let prefix = "bodytext/section"
            sections = container.streamNames.compactMap { name in
                guard name.hasPrefix(prefix) else { return nil }
                let suffix = name.dropFirst(prefix.count)
                guard !suffix.isEmpty,
                      suffix.allSatisfy(\.isNumber),
                      let index = Int(suffix) else { return nil }
                return (index, name)
            }.sorted { $0.index < $1.index }
            guard !sections.isEmpty else {
                throw ChatAttachmentError.invalidHWP
            }
            guard sections.count <= HWP5TextExtractor.maximumSections else {
                throw ChatAttachmentError.hwpLimitExceeded
            }
        }
    }

    private struct BinaryRecord {
        let tag: UInt32
        let level: Int
        let payload: Data

        static func records(in data: Data) throws -> [BinaryRecord] {
            var reader = DataReader(data)
            var result: [BinaryRecord] = []
            result.reserveCapacity(min(2_048, data.count / 8))

            while reader.remainingBytes > 0 {
                guard reader.remainingBytes >= 4 else {
                    throw ChatAttachmentError.invalidHWP
                }
                let header = try reader.readUInt32()
                let tag = header & 0x03FF
                let level = Int((header >> 10) & 0x03FF)
                guard level <= maximumRecordLevel else {
                    throw ChatAttachmentError.hwpLimitExceeded
                }
                var size = Int(header >> 20)
                if size == 0x0FFF {
                    size = Int(try reader.readUInt32())
                }
                guard size >= 0,
                      size <= HWP5TextExtractor.maximumSectionBytes,
                      size <= reader.remainingBytes else {
                    throw ChatAttachmentError.invalidHWP
                }
                result.append(
                    BinaryRecord(
                        tag: tag,
                        level: level,
                        payload: try reader.readData(count: size)
                    )
                )
                guard result.count <= maximumRecords else {
                    throw ChatAttachmentError.hwpLimitExceeded
                }
            }
            return result
        }
    }

    private struct BinaryDataDescriptor {
        let type: Int
        let compression: Int
        let streamID: Int?
        let extensionName: String?

        init(_ payload: Data) throws {
            var reader = DataReader(payload)
            let property = try reader.readUInt16()
            type = Int(property & 0x0F)
            compression = Int((property >> 4) & 0x03)
            guard (0...2).contains(type), compression <= 2 else {
                throw ChatAttachmentError.invalidHWP
            }
            if type == 0 {
                _ = try reader.readUTF16String()
                _ = try reader.readUTF16String()
                streamID = nil
                extensionName = nil
            } else {
                streamID = Int(try reader.readUInt16())
                extensionName = try reader.readUTF16String()
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    .lowercased()
            }
        }
    }

    private struct EmbeddedBinary {
        let data: Data
        let extensionName: String
    }

    private struct BorderFill {
        let boxStyle: HWPDocumentBoxStyle
        let imageBinaryID: Int?
        let imageFillMode: Int?

        init(_ payload: Data) throws {
            guard payload.count >= 32 else { throw ChatAttachmentError.invalidHWP }
            var reader = DataReader(payload)
            _ = try reader.readUInt16()
            // Each side is stored as one 6-byte group: line kind (1),
            // thickness index (1), COLORREF (4), in the order left, right,
            // top, bottom, followed by the diagonal group. Reading the four
            // kinds first would take the top/bottom kinds from the left
            // side's color bytes and drop every horizontal cell border.
            let lines = try (0..<4).map { _ -> HWPDocumentBorderLine in
                let kind = try reader.readUInt8()
                let thickness = try reader.readUInt8()
                let color = rgb(fromColorReference: try reader.readUInt32()) ?? 0
                return HWPDocumentBorderLine(
                    kind: kind,
                    widthPoints: borderWidthPoints(thickness),
                    colorRGB: color
                )
            }
            _ = try reader.readUInt8() // diagonal kind
            _ = try reader.readUInt8() // diagonal thickness
            _ = try reader.readUInt32() // diagonal color

            var backgroundColor: UInt32?
            var parsedImageBinaryID: Int?
            var parsedImageFillMode: Int?
            if reader.remainingBytes >= 4 {
                let fillType = try reader.readUInt32()
                if fillType & 1 != 0, reader.remainingBytes >= 12 {
                    backgroundColor = rgb(
                        fromColorReference: try reader.readUInt32()
                    )
                    _ = try reader.readUInt32()
                    _ = try reader.readInt32()
                }
                if fillType & 4 != 0, reader.remainingBytes >= 12 {
                    _ = try reader.readInt16() // gradient type
                    _ = try reader.readInt16() // angle
                    _ = try reader.readInt16() // center x
                    _ = try reader.readInt16() // center y
                    _ = try reader.readInt16() // spread
                    let colorCount = Int(try reader.readInt16())
                    guard colorCount >= 0, colorCount <= 256 else {
                        throw ChatAttachmentError.hwpLimitExceeded
                    }
                    if colorCount > 2 {
                        _ = try reader.readData(count: colorCount * 4)
                    }
                    _ = try reader.readData(count: colorCount * 4)
                }
                if fillType & 2 != 0, reader.remainingBytes >= 6 {
                    parsedImageFillMode = Int(try reader.readUInt8())
                    _ = try reader.readUInt8() // brightness
                    _ = try reader.readUInt8() // contrast
                    _ = try reader.readUInt8() // effect
                    parsedImageBinaryID = Int(try reader.readUInt16())
                }
            }
            boxStyle = HWPDocumentBoxStyle(
                left: lines[0],
                right: lines[1],
                top: lines[2],
                bottom: lines[3],
                backgroundColorRGB: backgroundColor
            )
            imageBinaryID = parsedImageBinaryID
            imageFillMode = parsedImageFillMode
        }
    }

    private struct DocumentInfo {
        var mappingCounts: [Int] = []
        var binaryDescriptors: [BinaryDataDescriptor] = []
        var embeddedBinaries: [Int: EmbeddedBinary] = [:]
        var embeddedImages: [Int: EmbeddedBinary] = [:]
        var faceNames: [FontFace] = []
        var borderFills: [BorderFill] = []
        var characterShapes: [CharacterShape] = []
        var numberings: [[HWPListBinary.Level]] = []
        var bullets: [BulletDefinition] = []
        var paragraphShapes: [ParagraphShape] = []
        var styles: [DocumentStyle] = []

        mutating func loadEmbeddedImages(from source: Source) throws {
            var expandedTotal = 0
            for (index, descriptor) in binaryDescriptors.enumerated() {
                guard descriptor.type != 0,
                      let streamID = descriptor.streamID else { continue }
                let prefix = String(format: "bindata/bin%04d", streamID)
                guard let name = source.container.streamNames.first(where: {
                    $0.hasPrefix(prefix)
                }) else { continue }
                let stored: Data
                do {
                    stored = try source.container.stream(named: name)
                } catch OLECompoundFileError.limitExceeded {
                    throw ChatAttachmentError.hwpLimitExceeded
                } catch {
                    throw ChatAttachmentError.invalidHWP
                }

                let shouldInflate = descriptor.compression == 1
                    || (descriptor.compression == 0 && source.isCompressed)
                let content: Data
                if shouldInflate {
                    do {
                        content = try HWP5TextExtractor.inflateRawDeflate(
                            stored,
                            maximumBytes: HWP5TextExtractor.maximumSectionBytes
                        )
                    } catch {
                        content = stored
                    }
                } else {
                    content = stored
                }
                expandedTotal += content.count
                guard expandedTotal <= HWP5TextExtractor.maximumExpandedBytes else {
                    throw ChatAttachmentError.hwpLimitExceeded
                }
                let binary = EmbeddedBinary(
                    data: content,
                    extensionName: descriptor.extensionName ?? "image"
                )
                embeddedBinaries[index + 1] = binary
                if Self.isSupportedImage(content) {
                    embeddedImages[index + 1] = binary
                }
            }
        }

        static func isSupportedImage(_ data: Data) -> Bool {
            if data.count >= 8,
               Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10] {
                return true
            }
            if data.count >= 3,
               data[0] == 0xFF, data[1] == 0xD8, data[2] == 0xFF {
                return true
            }
            if data.count >= 6,
               let signature = String(data: data.prefix(6), encoding: .ascii),
               signature == "GIF87a" || signature == "GIF89a" {
                return true
            }
            if data.count >= 2, data[0] == 0x42, data[1] == 0x4D {
                return true
            }
            if data.count >= 4,
               (Array(data.prefix(4)) == [0x49, 0x49, 0x2A, 0x00]
                    || Array(data.prefix(4)) == [0x4D, 0x4D, 0x00, 0x2A]) {
                return true
            }
            if data.count >= 4,
               Array(data.prefix(4)) == [0x00, 0x00, 0x01, 0x00] {
                return true
            }
            if data.count >= 12,
               String(data: data.prefix(4), encoding: .ascii) == "RIFF",
               String(data: data.subdata(in: 8..<12), encoding: .ascii) == "WEBP" {
                return true
            }
            return false
        }

        func boxStyle(for identifier: Int) -> HWPDocumentBoxStyle? {
            guard identifier > 0,
                  borderFills.indices.contains(identifier - 1) else { return nil }
            let borderFill = borderFills[identifier - 1]
            guard let binaryID = borderFill.imageBinaryID,
                  let binary = embeddedImages[binaryID] else {
                return borderFill.boxStyle
            }
            let style = borderFill.boxStyle
            return HWPDocumentBoxStyle(
                left: style.left,
                right: style.right,
                top: style.top,
                bottom: style.bottom,
                backgroundColorRGB: style.backgroundColorRGB,
                backgroundImage: HWPDocumentImage(
                    id: "hwp-background-\(identifier)-\(binaryID)",
                    binaryID: binaryID,
                    data: binary.data,
                    widthPoints: 1,
                    heightPoints: 1,
                    description: "한글 문서 배경 그림"
                ),
                backgroundImageFillMode: borderFill.imageFillMode
            )
        }

        func fontFace(faceID: Int, language: Int) -> FontFace? {
            guard faceID >= 0 else { return nil }
            let language = min(max(language, 0), 6)
            let index: Int
            if mappingCounts.count >= 8 {
                let base = (0..<language).reduce(0) { partial, item in
                    partial + mappingCounts[item + 1]
                }
                guard faceID < mappingCounts[language + 1] else { return nil }
                index = base + faceID
            } else {
                index = faceID
            }
            guard faceNames.indices.contains(index) else { return nil }
            return faceNames[index]
        }

        func fontName(faceID: Int, language: Int) -> String? {
            fontFace(faceID: faceID, language: language)?.name
        }
    }

    private static func borderWidthPoints(_ index: UInt8) -> Double {
        let millimeters = [
            0.1, 0.12, 0.15, 0.2, 0.25, 0.3, 0.4, 0.5,
            0.6, 0.7, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0,
        ]
        let value = millimeters.indices.contains(Int(index))
            ? millimeters[Int(index)]
            : millimeters[0]
        return value * 72 / 25.4
    }

    private static func rgb(fromColorReference value: UInt32) -> UInt32? {
        if value == UInt32.max { return nil }
        let red = value & 0xFF
        let green = (value >> 8) & 0xFF
        let blue = (value >> 16) & 0xFF
        return red << 16 | green << 8 | blue
    }

    private struct FontFace {
        let name: String
        let alternateName: String?
        let baseName: String?
        let signature: HWPDocumentFontSignature?

        init(payload: Data) throws {
            var reader = DataReader(payload)
            let property = try reader.readUInt8()
            name = try reader.readUTF16String()
            var parsedAlternateName: String?
            if property & 0x80 != 0 {
                _ = try reader.readUInt8()
                parsedAlternateName = try reader.readUTF16String()
            }
            var parsedSignature: HWPDocumentFontSignature?
            if property & 0x40 != 0 {
                parsedSignature = HWPDocumentFontSignature(
                    bytes: Array(try reader.readData(count: 10))
                )
            }
            var parsedBaseName: String?
            if property & 0x20 != 0 {
                parsedBaseName = try reader.readUTF16String()
            }
            alternateName = parsedAlternateName?.isEmpty == false
                ? parsedAlternateName
                : nil
            baseName = parsedBaseName?.isEmpty == false ? parsedBaseName : nil
            signature = parsedSignature
            guard !name.isEmpty else {
                throw ChatAttachmentError.invalidHWP
            }
        }
    }

    private struct CharacterShape {
        let faceIDs: [Int]
        let widthRatios: [Int]
        let letterSpacings: [Int]
        let relativeSizes: [Int]
        let characterPositions: [Int]
        let baseSizePoints: Double
        let property: UInt32
        let textColorRGB: UInt32?
        let backgroundColorRGB: UInt32?

        init(payload: Data) throws {
            guard payload.count >= 56 else {
                throw ChatAttachmentError.invalidHWP
            }
            var reader = DataReader(payload)
            var parsedFaceIDs: [Int] = []
            for _ in 0..<7 {
                parsedFaceIDs.append(Int(try reader.readUInt16()))
            }
            widthRatios = try (0..<7).map { _ in
                Int(try reader.readUInt8())
            }
            letterSpacings = try (0..<7).map { _ in
                Int(try reader.readInt8())
            }
            relativeSizes = try (0..<7).map { _ in
                Int(try reader.readUInt8())
            }
            characterPositions = try (0..<7).map { _ in
                Int(try reader.readInt8())
            }
            let height = try reader.readInt32()
            let parsedProperty = try reader.readUInt32()
            _ = try reader.readData(count: 2) // shadow offsets
            let color = try reader.readUInt32()

            faceIDs = parsedFaceIDs
            baseSizePoints = Self.clamp(Double(height) / 100, minimum: 4, maximum: 144)
            property = parsedProperty
            textColorRGB = Self.rgb(fromColorReference: color)
            if payload.count >= 64 {
                try reader.seek(to: 60)
                backgroundColorRGB = Self.rgb(fromColorReference: try reader.readUInt32())
            } else { backgroundColorRGB = nil }
        }

        func textRun(
            text: String,
            language: Int,
            docInfo: DocumentInfo
        ) -> HWPDocumentTextRun {
            let language = min(max(language, 0), 6)
            let relative = relativeSizes.indices.contains(language)
                ? relativeSizes[language]
                : 100
            let size = Self.clamp(
                baseSizePoints * Double(relative) / 100,
                minimum: 4,
                maximum: 144
            )
            let faceID = faceIDs.indices.contains(language) ? faceIDs[language] : 0
            let face = docInfo.fontFace(faceID: faceID, language: language)
            let underlineKind = (property >> 2) & 0x03
            let strikeLineCount = (property >> 18) & 0x07
            let strikeLineShape = (property >> 26) & 0x0F
            return HWPDocumentTextRun(
                text: text.replacingOccurrences(of: "\u{F09E}", with: "·"),
                fontName: face?.name,
                alternateFontName: face?.alternateName,
                baseFontName: face?.baseName,
                fontSignature: face?.signature,
                fontSizePoints: size,
                fontWidthPercent: Double(
                    widthRatios.indices.contains(language)
                        ? widthRatios[language]
                        : 100
                ),
                letterSpacingPercent: Double(
                    letterSpacings.indices.contains(language)
                        ? letterSpacings[language]
                        : 0
                ),
                baselinePositionPercent: Double(
                    characterPositions.indices.contains(language)
                        ? characterPositions[language]
                        : 0
                ),
                textColorRGB: textColorRGB,
                backgroundColorRGB: backgroundColorRGB,
                isBold: property & (1 << 1) != 0,
                isItalic: property & 1 != 0,
                // The published HWP 5.x format defines underline kinds 0, 1,
                // and 3. Value 2 occurs in later 5.1 files as a reserved
                // sentinel and must not be painted as an underline.
                isUnderlined: underlineKind == 1 || underlineKind == 3,
                // A non-zero strike count can coexist with line-shape 15
                // (NONE). Treat that combination as disabled.
                isStruckThrough: strikeLineCount != 0 && strikeLineShape != 15,
                isSuperscript: property & (1 << 15) != 0,
                isSubscript: property & (1 << 16) != 0,
                spaceWidthPoints: !text.isEmpty && text.allSatisfy({ $0 == " " })
                    && property & (1 << 25) == 0 ? size / 2 : nil
            )
        }

        private static func rgb(fromColorReference value: UInt32) -> UInt32? {
            if value == UInt32.max { return nil }
            let red = value & 0xFF
            let green = (value >> 8) & 0xFF
            let blue = (value >> 16) & 0xFF
            return red << 16 | green << 8 | blue
        }

        private static func clamp(
            _ value: Double,
            minimum: Double,
            maximum: Double
        ) -> Double {
            min(max(value, minimum), maximum)
        }
    }

    private struct BulletDefinition {
        let property: UInt32
        let widthAdjustment: Double
        let gap: Double
        let characterShapeID: Int
        let character: UInt16
        let isImage: Bool

        init(_ payload: Data) throws {
            var reader = DataReader(payload)
            property = try reader.readUInt32()
            widthAdjustment = Double(try reader.readInt16()) / 100
            gap = Double(try reader.readUInt16())
            characterShapeID = Int(try reader.readInt32())
            character = try reader.readUInt16()
            isImage = try reader.remainingBytes > 0 ? reader.readUInt8() != 0 : false
        }

        func marker(defaultShapeID: Int, docInfo: DocumentInfo) -> HWPDocumentListMarker? {
            guard !isImage, character != 0 else { return nil }
            let shapeID = characterShapeID >= 0 ? characterShapeID : defaultShapeID
            guard docInfo.characterShapes.indices.contains(shapeID) else { return nil }
            let shape = docInfo.characterShapes[shapeID]
            let sourceText = String(decoding: [character], as: UTF16.self)
            let sourceRun = shape.textRun(text: sourceText, language: 5, docInfo: docInfo)
            // HWP's default circle retains Wingdings' private-use code even
            // when the bullet character style names a Korean text face.
            let isWingdingsCircle = character == 0xF06C
            let run = isWingdingsCircle
                ? shape.textRun(text: "●", language: 5, docInfo: docInfo) : sourceRun
            let size = run.fontSizePoints ?? 10
            let glyphWidth = size * (character == 45 ? 0.5 : 1)
            let separation = property & (1 << 4) == 0 ? size * gap / 100 : gap / 100
            return HWPDocumentListMarker(run: run,
                reservedWidthPoints: max(0, glyphWidth + widthAdjustment + separation),
                isLegacyCircle: isWingdingsCircle)
        }
    }

    private struct ParagraphShape {
        let alignment: HWPParagraphAlignment
        let baselineAlignment: HWPDocumentLineBaselineAlignment
        let leftMarginPoints: Double
        let rightMarginPoints: Double
        let firstLineIndentPoints: Double
        let spacingBeforePoints: Double
        let spacingAfterPoints: Double
        let lineSpacingPercent: Double?
        let pageBreakBefore: Bool
        let outlineLevel: Int?
        let bulletID: Int?
        let numberingID: Int?
        let listLevel: Int
        let borderFillID: Int
        let borderOffsets: [Double]

        init(payload: Data) throws {
            guard payload.count >= 42 else {
                throw ChatAttachmentError.invalidHWP
            }
            var reader = DataReader(payload)
            let property = try reader.readUInt32()
            baselineAlignment = HWPDocumentLineBaselineAlignment(rawValue: Int((property >> 20) & 3)) ?? .font
            // PARA_SHAPE distances are stored at twice the HWPUNIT scale.
            // The cached line's column start already includes the left margin.
            leftMarginPoints = Self.points(try reader.readInt32())
            rightMarginPoints = Self.points(try reader.readInt32())
            firstLineIndentPoints = Self.points(try reader.readInt32())
            spacingBeforePoints = Self.points(try reader.readInt32())
            spacingAfterPoints = Self.points(try reader.readInt32())

            let spacingKind: UInt32
            let spacingValue: UInt32
            if payload.count >= 54 {
                var spacingReader = DataReader(payload)
                try spacingReader.seek(to: 46)
                spacingKind = try spacingReader.readUInt32() & 31
                spacingValue = try spacingReader.readUInt32()
            } else {
                spacingKind = property & 3
                var spacingReader = DataReader(payload)
                try spacingReader.seek(to: 24)
                spacingValue = try spacingReader.readUInt32()
            }
            lineSpacingPercent = spacingKind == 0 && spacingValue > 0 ? Double(spacingValue) : nil

            switch (property >> 2) & 0x07 {
            case 0:
                alignment = .justified
            case 2:
                alignment = .trailing
            case 3:
                alignment = .centered
            case 4, 5:
                alignment = .distributed
            default:
                alignment = .leading
            }
            pageBreakBefore = property & (1 << 19) != 0
            let headKind = Int((property >> 23) & 0x03)
            outlineLevel = headKind == 1 ? Int((property >> 25) & 0x07) : nil
            try reader.seek(to: 30)
            let listID = Int(try reader.readUInt16())
            bulletID = headKind == 3 && listID > 0 ? listID : nil
            numberingID = headKind == 2 && listID > 0 ? listID : nil
            listLevel = Int((property >> 25) & 7)
            borderFillID = Int(try reader.readUInt16())
            borderOffsets = try (0..<4).map { _ in Double(try reader.readUInt16()) / 100 }
        }

        private static func points(_ raw: Int32) -> Double {
            min(max(Double(raw) / 200, -720), 720)
        }
    }

    private struct DocumentStyle {
        let localName: String
        let englishName: String
        let kind: Int
        let paragraphShapeID: Int
        let characterShapeID: Int

        init(payload: Data) throws {
            var reader = DataReader(payload)
            localName = try reader.readUTF16String()
            englishName = try reader.readUTF16String()
            kind = Int(try reader.readUInt8() & 0x07)
            _ = try reader.readUInt8() // next style
            _ = try reader.readInt16() // language
            paragraphShapeID = Int(try reader.readUInt16())
            characterShapeID = Int(try reader.readUInt16())
        }

        var displayName: String? {
            if !localName.isEmpty { return localName }
            if !englishName.isEmpty { return englishName }
            return nil
        }
    }

    private struct ParagraphHeader {
        var characterCount = 0
        var controlMask: UInt32 = 0
        var paragraphShapeID = 0
        var styleID = 0
        var breakFlags: UInt8 = 0
        var expectedCharacterShapeCount = 0
        var expectedRangeTagCount = 0

        init() {}

        init(payload: Data) throws {
            guard payload.count >= 22 else {
                throw ChatAttachmentError.invalidHWP
            }
            var reader = DataReader(payload)
            characterCount = Int(try reader.readUInt32() & 0x7FFF_FFFF)
            controlMask = try reader.readUInt32()
            paragraphShapeID = Int(try reader.readUInt16())
            styleID = Int(try reader.readUInt8())
            breakFlags = try reader.readUInt8()
            expectedCharacterShapeCount = Int(try reader.readUInt16())
            expectedRangeTagCount = Int(try reader.readUInt16())
        }
    }

    private struct CharacterShapeChange {
        let position: Int
        let shapeID: Int
    }

    private struct RawLineLayout {
        let startCharacter: Int
        let verticalPositionPoints: Double
        let lineHeightPoints: Double
        let textHeightPoints: Double
        let baselinePoints: Double
        let lineSpacingPoints: Double
        let columnStartPoints: Double
        let widthPoints: Double
        let flags: UInt32

        init(reader: inout DataReader) throws {
            startCharacter = Int(try reader.readUInt32())
            verticalPositionPoints = Self.points(try reader.readInt32())
            lineHeightPoints = Self.positivePoints(try reader.readInt32())
            textHeightPoints = Self.positivePoints(try reader.readInt32())
            baselinePoints = Self.positivePoints(try reader.readInt32())
            lineSpacingPoints = Self.points(try reader.readInt32())
            columnStartPoints = Self.points(try reader.readInt32())
            widthPoints = Self.positivePoints(try reader.readInt32())
            flags = try reader.readUInt32()
        }

        private static func points(_ raw: Int32) -> Double {
            min(max(Double(raw) / 100, -4_000), 4_000)
        }

        private static func positivePoints(_ raw: Int32) -> Double {
            min(max(abs(Double(raw)) / 100, 0), 4_000)
        }
    }

    private struct ParagraphBuilder {
        var header = ParagraphHeader()
        var hasHeader = false
        var hasTextRecord = false
        var hasUnsupportedInsertionRecords = false
        /// Record level of this paragraph's PARA_HEADER. Controls that
        /// belong to the paragraph are stored one level deeper.
        var level = 0
        var textUnits: [UInt16] = []
        var characterShapes: [CharacterShapeChange] = []
        var containsComplexControl = false
        var containsPositionedMetadata = false
        var hyperlinkTargets: [String] = []
        var tableLocation: HWPDocumentTableLocation?
        var region: HWPDocumentRegion = .body
        var images: [HWPDocumentImage] = []
        var lineLayouts: [RawLineLayout] = []
        var canvasObjects: [HWPDocumentCanvasObject] = []
        var layoutContainerID: String?
        var precedingParagraphEndPoints: Double?

        func controlPositions(identifier targetIdentifier: UInt32) -> [Int] {
            // One paragraph can own several inline tables on different cached
            // lines. Locate the matching table control in the raw UTF-16 text.
            var positions: [Int] = []
            var cursor = 0
            while cursor < textUnits.count {
                let code = textUnits[cursor]
                if code == 11, cursor + 7 < textUnits.count {
                    let identifier = UInt32(textUnits[cursor + 1]) | UInt32(textUnits[cursor + 2]) << 16
                    if identifier == targetIdentifier { positions.append(cursor) }
                }
                cursor += (code >= 1 && code <= 23 && code != 10 && code != 13) ? 8 : 1
            }
            return positions
        }

        func tableAnchor(controlOrdinal: Int, docInfo: DocumentInfo,
                         placement: HWPDocumentObjectPlacement) -> HWPDocumentTableAnchor? {
            let positions = controlPositions(identifier: tableControlID)
            let position = positions.indices.contains(controlOrdinal) ? positions[controlOrdinal] : 0
            guard let line = lineLayouts.last(where: { $0.startCharacter <= position }) ?? lineLayouts.first else { return nil }
            let paragraphShape = docInfo.paragraphShapes.indices.contains(header.paragraphShapeID)
                ? docInfo.paragraphShapes[header.paragraphShapeID] : nil
            var verticalPosition = line.verticalPositionPoints
                - (placement.isInline ? 0 : paragraphShape?.spacingBeforePoints ?? 0)
            // A block-wrapped floating table can push its owner's first text
            // line below itself. Recover the paragraph start only when the
            // cached displacement matches the complete exclusion height.
            if !placement.isInline, placement.wrap == .topAndBottom,
               let preceding = precedingParagraphEndPoints,
               line.startCharacter == lineLayouts.first?.startCharacter {
                let exclusion = placement.yPoints + placement.heightPoints
                    + placement.marginTopPoints + placement.marginBottomPoints
                if abs(verticalPosition - preceding - exclusion) < 2 {
                    verticalPosition -= exclusion
                }
            }
            return HWPDocumentTableAnchor(
                columnStartPoints: line.columnStartPoints,
                verticalPositionPoints: verticalPosition,
                widthPoints: line.widthPoints,
                lineHeightPoints: line.lineHeightPoints,
                paragraphAlignment: docInfo.paragraphShapes.indices.contains(header.paragraphShapeID)
                    ? docInfo.paragraphShapes[header.paragraphShapeID].alignment : .leading
            )
        }

        init() {}

        init(
            headerPayload: Data,
            tableLocation: HWPDocumentTableLocation? = nil,
            region: HWPDocumentRegion = .body,
            layoutContainerID: String? = nil
        ) throws {
            header = try ParagraphHeader(payload: headerPayload)
            hasHeader = true
            self.tableLocation = tableLocation
            self.region = region
            self.layoutContainerID = layoutContainerID
        }

        mutating func installText(_ payload: Data) throws {
            guard !hasTextRecord, payload.count.isMultiple(of: 2) else {
                throw ChatAttachmentError.invalidHWP
            }
            hasTextRecord = true
            var reader = DataReader(payload)
            while reader.remainingBytes > 0 {
                textUnits.append(try reader.readUInt16())
            }
        }

        mutating func installCharacterShapes(_ payload: Data) throws {
            guard characterShapes.isEmpty,
                  payload.count.isMultiple(of: 8) else {
                throw ChatAttachmentError.invalidHWP
            }
            var reader = DataReader(payload)
            var lastPosition = -1
            while reader.remainingBytes > 0 {
                let position = Int(try reader.readUInt32())
                let shapeID = Int(try reader.readUInt32())
                guard position >= 0,
                      position >= lastPosition,
                      position <= textUnits.count else {
                    throw ChatAttachmentError.invalidHWP
                }
                characterShapes.append(
                    CharacterShapeChange(position: position, shapeID: shapeID)
                )
                lastPosition = position
            }
            if header.expectedCharacterShapeCount > 0,
               header.expectedCharacterShapeCount != characterShapes.count {
                throw ChatAttachmentError.invalidHWP
            }
        }

        mutating func installLineLayouts(_ payload: Data) throws {
            guard lineLayouts.isEmpty,
                  payload.count.isMultiple(of: 36),
                  payload.count / 36 <= 4_096 else {
                throw ChatAttachmentError.invalidHWP
            }
            var reader = DataReader(payload)
            var previousStart = -1
            while reader.remainingBytes > 0 {
                let layout = try RawLineLayout(reader: &reader)
                // Empty HWP paragraphs may omit PARA_TEXT entirely while the
                // header still counts the terminal paragraph mark. Their
                // cached line segments legitimately use positions 0 and 1.
                let declaredCharacterCount = max(
                    textUnits.count,
                    header.characterCount
                )
                guard layout.startCharacter >= previousStart,
                      layout.startCharacter <= declaredCharacterCount else {
                    throw ChatAttachmentError.invalidHWP
                }
                lineLayouts.append(layout)
                previousStart = layout.startCharacter
            }
        }

        mutating func appendCanvasObject(
            _ object: HWPDocumentCanvasObject
        ) -> Int {
            canvasObjects.append(object)
            return canvasObjects.count - 1
        }

        mutating func installContent(
            _ content: HWPDocumentCanvasContent,
            at index: Int
        ) {
            guard canvasObjects.indices.contains(index) else { return }
            let old = canvasObjects[index]
            canvasObjects[index] = HWPDocumentCanvasObject(
                id: old.id,
                placement: old.placement,
                content: content,
                description: old.description,
                textContainerID: old.textContainerID,
                repeatsOnEveryPage: old.repeatsOnEveryPage,
                textContainerLayout: old.textContainerLayout,
                groupCoordinateFrame: old.groupCoordinateFrame
            )
        }

        mutating func appendShape(
            _ shape: HWPDocumentShape,
            at index: Int
        ) {
            guard canvasObjects.indices.contains(index) else { return }
            switch canvasObjects[index].content {
            case .shape(let existing):
                installContent(.group([existing, shape]), at: index)
            case .group(let existing):
                installContent(.group(existing + [shape]), at: index)
            default:
                installContent(.shape(shape), at: index)
            }
        }

        mutating func installPlacement(
            _ placement: HWPDocumentObjectPlacement,
            at index: Int
        ) {
            guard canvasObjects.indices.contains(index) else { return }
            let old = canvasObjects[index]
            canvasObjects[index] = HWPDocumentCanvasObject(
                id: old.id,
                placement: placement,
                content: old.content,
                description: old.description,
                textContainerID: old.textContainerID,
                repeatsOnEveryPage: old.repeatsOnEveryPage,
                textContainerLayout: old.textContainerLayout,
                groupCoordinateFrame: old.groupCoordinateFrame
            )
        }

        mutating func installTextContainerID(_ identifier: String, at index: Int) {
            guard canvasObjects.indices.contains(index) else { return }
            let old = canvasObjects[index]
            canvasObjects[index] = HWPDocumentCanvasObject(
                id: old.id,
                placement: old.placement,
                content: old.content,
                description: old.description,
                textContainerID: identifier,
                repeatsOnEveryPage: old.repeatsOnEveryPage,
                textContainerLayout: old.textContainerLayout,
                groupCoordinateFrame: old.groupCoordinateFrame
            )
        }

        func makeBlock(
            sectionIndex: Int,
            paragraphOrdinal: Int,
            docInfo: DocumentInfo,
            allowsEditing: Bool
        ) throws -> HWPDocumentBlock {
            let style = docInfo.styles.indices.contains(header.styleID)
                ? docInfo.styles[header.styleID]
                : nil
            let paragraphShapeID = docInfo.paragraphShapes.indices.contains(
                header.paragraphShapeID
            ) ? header.paragraphShapeID : (style?.paragraphShapeID ?? -1)
            let paragraphShape = docInfo.paragraphShapes.indices.contains(
                paragraphShapeID
            ) ? docInfo.paragraphShapes[paragraphShapeID] : nil
            let defaultCharacterShapeID = style?.characterShapeID ?? 0
            let listMarker = paragraphShape?.bulletID.flatMap { id -> HWPDocumentListMarker? in
                guard docInfo.bullets.indices.contains(id - 1) else { return nil }
                return docInfo.bullets[id - 1].marker(
                    defaultShapeID: characterShapes.first?.shapeID ?? defaultCharacterShapeID,
                    docInfo: docInfo)
            }
            let decoded = try TextDecoder.decode(
                textUnits,
                shapeChanges: characterShapes,
                defaultShapeID: defaultCharacterShapeID,
                docInfo: docInfo
            )
            // Empty paragraphs still have a typing style at UTF-16 position
            // zero. Retain it so the first insertion uses the document's font
            // and size in both the editor preview and the saved HWP.
            var textRuns = applyingHyperlinks(to: decoded.runs)
            let typingShapeID = characterShapes.last(where: { $0.position == 0 })?.shapeID
                ?? defaultCharacterShapeID
            if textRuns.isEmpty, docInfo.characterShapes.indices.contains(typingShapeID) {
                textRuns = [docInfo.characterShapes[typingShapeID]
                    .textRun(text: "", language: 0, docInfo: docInfo)]
            }
            let canInsertMissingText = !hasTextRecord && hasHeader
                && !hasUnsupportedInsertionRecords
                && header.characterCount <= 1 && header.controlMask == 0
                && header.expectedCharacterShapeCount == 1
                && characterShapes.count == 1 && characterShapes[0].position == 0
                && docInfo.characterShapes.indices.contains(typingShapeID)
            var list: HWPParagraphList?
            if let shape = paragraphShape, let id = shape.bulletID {
                list = HWPParagraphList(kind: .bullet, definitionID: String(id), level: shape.listLevel,
                    format: listMarker?.run.text ?? "", isSimple: shape.listLevel == 0 && listMarker != nil,
                    inheritedMarker: listMarker)
            } else if let shape = paragraphShape, let id = shape.numberingID {
                let levels = docInfo.numberings.indices.contains(id - 1) ? docInfo.numberings[id - 1] : []
                let level = levels.indices.contains(shape.listLevel) ? levels[shape.listLevel] : nil
                list = HWPParagraphList(kind: .number, definitionID: String(id), level: shape.listLevel,
                    format: level?.format ?? "", start: level?.start ?? 1,
                    isSimple: shape.listLevel == 0 && level?.format == "^1." && ((level?.property ?? 0) >> 5 & 15) == 0)
            }
            let presentation = HWPDocumentBlockPresentation(
                styleName: style?.displayName,
                alignment: paragraphShape?.alignment ?? .leading,
                outlineLevel: paragraphShape?.outlineLevel
                    ?? Self.inferredOutlineLevel(style?.displayName),
                leftMarginPoints: paragraphShape?.leftMarginPoints ?? 0,
                rightMarginPoints: paragraphShape?.rightMarginPoints ?? 0,
                firstLineIndentPoints: paragraphShape?.firstLineIndentPoints ?? 0,
                spacingBeforePoints: paragraphShape?.spacingBeforePoints ?? 0,
                spacingAfterPoints: paragraphShape?.spacingAfterPoints ?? 0,
                pageBreakBefore: paragraphShape?.pageBreakBefore == true
                    || header.breakFlags & 0x04 != 0,
                textRuns: textRuns,
                paragraphBorder: paragraphShape.flatMap { shape in
                    guard let style = docInfo.boxStyle(for: shape.borderFillID),
                          style.firstVisibleBorder != nil || style.backgroundColorRGB != nil else { return nil }
                    return HWPDocumentParagraphBorder(style: style,
                        left: shape.borderOffsets[0], right: shape.borderOffsets[1],
                        top: shape.borderOffsets[2], bottom: shape.borderOffsets[3])
                }, lineSpacingPercent: paragraphShape?.lineSpacingPercent, list: list
            )
            let positionedLines = try lineLayouts.enumerated().map { index, layout in
                let end = index + 1 < lineLayouts.count
                    ? lineLayouts[index + 1].startCharacter
                    : textUnits.count
                let line = try TextDecoder.decodeRange(
                    textUnits,
                    range: layout.startCharacter..<max(layout.startCharacter, end),
                    shapeChanges: characterShapes,
                    defaultShapeID: defaultCharacterShapeID,
                    docInfo: docInfo,
                    inlineWidths: inlineWidths
                )
                return HWPDocumentLineLayout(
                    id: "hwp-section-\(sectionIndex)-paragraph-\(paragraphOrdinal)-line-\(index)",
                    startCharacter: layout.startCharacter,
                    verticalPositionPoints: layout.verticalPositionPoints,
                    lineHeightPoints: layout.lineHeightPoints,
                    textHeightPoints: layout.textHeightPoints,
                    baselinePoints: layout.baselinePoints,
                    lineSpacingPoints: layout.lineSpacingPoints,
                    columnStartPoints: layout.columnStartPoints,
                    widthPoints: layout.widthPoints,
                    flags: layout.flags,
                    text: line.text.trimmingCharacters(in: .newlines),
                    textRuns: line.runs,
                    baselineAlignment: paragraphShape?.baselineAlignment ?? .font,
                    textInsetPoints: (index == 0
                        ? max(paragraphShape?.firstLineIndentPoints ?? 0, 0)
                        : max(-(paragraphShape?.firstLineIndentPoints ?? 0), 0)),
                    listMarker: listMarker,
                    showsListMarker: index == 0,
                    endsParagraph: index == lineLayouts.count - 1
                        || (end > 0 && textUnits.indices.contains(end - 1) && textUnits[end - 1] == 10)
                )
            }
            return HWPDocumentBlock(
                id: "hwp-section-\(sectionIndex)-paragraph-\(paragraphOrdinal)",
                sectionPath: "BodyText/Section\(sectionIndex)",
                paragraphIndex: paragraphOrdinal,
                text: decoded.text,
                tableLocation: tableLocation,
                isEditable: allowsEditing
                    && (!textUnits.isEmpty || canInsertMissingText)
                    && TextDecoder.canReplaceText(textUnits)
                    && !containsComplexControl
                    && !containsPositionedMetadata
                    && header.expectedRangeTagCount == 0,
                presentation: presentation,
                region: region,
                images: images,
                lineLayouts: positionedLines,
                canvasObjects: try canvasObjects.map { object in
                    guard object.placement.isInline,
                          let position = object.placement.sourceCharacterPosition,
                          let line = lineLayouts.last(where: { $0.startCharacter <= position }) else { return object }
                    let prefix = try TextDecoder.decodeRange(textUnits, range: line.startCharacter..<position,
                        shapeChanges: characterShapes, defaultShapeID: defaultCharacterShapeID,
                        docInfo: docInfo, inlineWidths: inlineWidths)
                    var placement = object.placement
                    placement.inlineLeadingPoints = prefix.runs.reduce(0) { total, run in
                        if let width = run.tabWidthPoints { return total + width }
                        let size = run.fontSizePoints ?? 12
                        return total + run.text.reduce(0) { sum, char in
                            sum + (char == " " ? run.spaceWidthPoints ?? size / 2 : size)
                                * run.fontWidthPercent / 100 * (1 + run.letterSpacingPercent / 100)
                        }
                    }
                    return object.replacing(placement: placement)
                },
                layoutContainerID: layoutContainerID
            )
        }

        private static func inferredOutlineLevel(_ styleName: String?) -> Int? {
            guard let styleName = styleName?.lowercased() else { return nil }
            let names = ["제목", "개요", "heading", "outline"]
            guard names.contains(where: styleName.contains) else { return nil }
            if let digit = styleName.reversed().first(where: { $0.isNumber }),
               let level = digit.wholeNumberValue {
                return min(max(level - 1, 0), 6)
            }
            return 0
        }

        private func applyingHyperlinks(to runs: [HWPDocumentTextRun]) -> [HWPDocumentTextRun] {
            var ranges: [(NSRange, String)] = [], stack: [(Int, String)] = []
            var raw = 0, visible = 0, targetIndex = 0
            while raw < textUnits.count {
                let code = textUnits[raw]
                if code == 3, raw + 7 < textUnits.count {
                    let target = hyperlinkTargets.indices.contains(targetIndex) ? hyperlinkTargets[targetIndex] : ""
                    targetIndex += 1; stack.append((visible, target)); raw += 8
                } else if code == 4, raw + 7 < textUnits.count {
                    if let start = stack.popLast(), !start.1.isEmpty, visible > start.0 {
                        ranges.append((NSRange(location: start.0, length: visible - start.0), start.1))
                    }
                    raw += 8
                } else if code == 9, raw + 7 < textUnits.count {
                    raw += 8; visible += 1
                } else if code == 13 { raw += 1 }
                else if (1...23).contains(code) { raw += min(8, textUnits.count - raw) }
                else { raw += 1; visible += 1 }
            }
            guard !ranges.isEmpty else { return runs }
            var output: [HWPDocumentTextRun] = [], offset = 0
            for run in runs {
                let source = run.text as NSString, runRange = NSRange(location: offset, length: source.length)
                offset += source.length
                var cuts = Set([0, source.length])
                for range in ranges {
                    let overlap = NSIntersectionRange(runRange, range.0)
                    if overlap.length > 0 {
                        cuts.insert(overlap.location - runRange.location)
                        cuts.insert(NSMaxRange(overlap) - runRange.location)
                    }
                }
                let sorted = cuts.sorted()
                for index in 0..<(sorted.count - 1) where sorted[index] < sorted[index + 1] {
                    let local = NSRange(location: sorted[index], length: sorted[index + 1] - sorted[index])
                    var piece = run.withText(source.substring(with: local))
                    let absolute = runRange.location + local.location
                    piece.hyperlink = ranges.last(where: { absolute >= $0.0.location && absolute < NSMaxRange($0.0) })?.1
                    output.append(piece)
                }
            }
            return output
        }

        private var inlineWidths: [Int: Double] {
            Dictionary(canvasObjects.compactMap { object in
                guard object.placement.isInline, let position = object.placement.sourceCharacterPosition else { return nil }
                return (position, object.placement.widthPoints
                    + object.placement.marginLeftPoints + object.placement.marginRightPoints)
            }, uniquingKeysWith: { first, _ in first })
        }
    }

    private enum TextDecoder {
        /// Only these controls can be reproduced by the text writer. A
        /// visually empty table/field anchor is not an empty input field.
        static func canReplaceText(_ units: [UInt16]) -> Bool {
            var index = 0
            while index < units.count {
                switch units[index] {
                case 3, 4:
                    guard index + 7 < units.count else { return false }
                    index += 8
                case 9:
                    guard index + 7 < units.count, units[index + 7] == 9 else { return false }
                    index += 8
                case 10, 13, 32...UInt16.max:
                    index += 1
                default:
                    return false
                }
            }
            return true
        }

        private struct Fragment {
            let rawPosition: Int
            let text: String
            var tabWidthPoints: Double? = nil
        }

        static func decode(
            _ units: [UInt16],
            shapeChanges: [CharacterShapeChange],
            defaultShapeID: Int,
            docInfo: DocumentInfo,
            inlineWidths: [Int: Double] = [:]
        ) throws -> (text: String, runs: [HWPDocumentTextRun]) {
            let fragments = try fragments(units, shapeChanges: shapeChanges, inlineWidths: inlineWidths)
            var text = ""
            var runs: [HWPDocumentTextRun] = []
            var shapeIndex = 0
            var activeShapeID = defaultShapeID

            for fragment in fragments {
                while shapeIndex < shapeChanges.count,
                      shapeChanges[shapeIndex].position <= fragment.rawPosition {
                    activeShapeID = shapeChanges[shapeIndex].shapeID
                    shapeIndex += 1
                }
                text += fragment.text
                guard !fragment.text.isEmpty else { continue }
                let shape = docInfo.characterShapes.indices.contains(activeShapeID)
                    ? docInfo.characterShapes[activeShapeID]
                    : nil
                if let width = fragment.tabWidthPoints {
                    runs.append(HWPDocumentTextRun(text: "\t",
                        fontSizePoints: shape?.baseSizePoints, tabWidthPoints: width))
                    continue
                }
                appendScriptRuns(
                    fragment.text,
                    shape: shape,
                    docInfo: docInfo,
                    output: &runs
                )
            }
            return (text, runs)
        }

        static func decodeRange(
            _ units: [UInt16],
            range: Range<Int>,
            shapeChanges: [CharacterShapeChange],
            defaultShapeID: Int,
            docInfo: DocumentInfo,
            inlineWidths: [Int: Double] = [:]
        ) throws -> (text: String, runs: [HWPDocumentTextRun]) {
            let lower = min(max(range.lowerBound, 0), units.count)
            let upper = min(max(range.upperBound, lower), units.count)
            guard lower < upper else { return ("", []) }
            let activeShapeID = shapeChanges.last(where: {
                $0.position <= lower
            })?.shapeID ?? defaultShapeID
            var adjusted: [CharacterShapeChange] = [
                CharacterShapeChange(position: 0, shapeID: activeShapeID),
            ]
            adjusted.append(contentsOf: shapeChanges.compactMap { change in
                guard change.position > lower, change.position < upper else {
                    return nil
                }
                return CharacterShapeChange(
                    position: change.position - lower,
                    shapeID: change.shapeID
                )
            })
            return try decode(
                Array(units[lower..<upper]),
                shapeChanges: adjusted,
                defaultShapeID: activeShapeID,
                docInfo: docInfo,
                inlineWidths: Dictionary(inlineWidths.compactMap { position, width in
                    (lower..<upper).contains(position) ? (position - lower, width) : nil
                }, uniquingKeysWith: { first, _ in first })
            )
        }

        private static func fragments(
            _ units: [UInt16],
            shapeChanges: [CharacterShapeChange],
            inlineWidths: [Int: Double]
        ) throws -> [Fragment] {
            let boundaries = Set(shapeChanges.map(\.position))
            var result: [Fragment] = []
            var index = 0
            while index < units.count {
                let code = units[index]
                if code > 31 {
                    let start = index
                    index += 1
                    while index < units.count,
                          units[index] > 31,
                          !boundaries.contains(index) {
                        index += 1
                    }
                    result.append(
                        Fragment(
                            rawPosition: start,
                            text: HanyangPUANormalizer.normalize(
                                String(
                                    decoding: units[start..<index],
                                    as: UTF16.self
                                )
                            )
                        )
                    )
                    continue
                }

                let output: String
                let consumed: Int
                switch code {
                case 9:
                    output = "\t"
                    consumed = 8
                case 10:
                    output = "\n"
                    consumed = 1
                case 13:
                    output = ""
                    consumed = 1
                case 24:
                    output = "-"
                    consumed = 1
                case 30, 31:
                    output = " "
                    consumed = 1
                case 1...8, 11...23:
                    output = ""
                    consumed = 8
                default:
                    output = ""
                    consumed = 1
                }
                guard index + consumed <= units.count else {
                    throw ChatAttachmentError.invalidHWP
                }
                result.append(Fragment(rawPosition: index, text: output))
                if code == 9 {
                    let width = UInt32(units[index + 1]) | UInt32(units[index + 2]) << 16
                    result[result.count - 1].tabWidthPoints = min(Double(width) / 100, 4_000)
                } else if let width = inlineWidths[index] {
                    result[result.count - 1] = Fragment(rawPosition: index, text: "\t", tabWidthPoints: width)
                }
                index += consumed
            }
            return result
        }

        private static func appendScriptRuns(
            _ text: String,
            shape: CharacterShape?,
            docInfo: DocumentInfo,
            output: inout [HWPDocumentTextRun]
        ) {
            var buffered = ""
            var language: Int?

            func flush() {
                guard !buffered.isEmpty else { return }
                let run = shape?.textRun(
                    text: buffered,
                    language: language == 7 ? 1 : language ?? 0,
                    docInfo: docInfo
                ) ?? HWPDocumentTextRun(text: buffered)
                append(run, to: &output)
                buffered = ""
            }

            for character in text {
                let nextLanguage = character == " " ? 7 : languageIndex(for: character)
                if let language, language != nextLanguage {
                    flush()
                }
                language = nextLanguage
                buffered.append(character)
            }
            flush()
        }

        private static func append(
            _ run: HWPDocumentTextRun,
            to output: inout [HWPDocumentTextRun]
        ) {
            if let last = output.last,
               last.hasSamePresentation(as: run) {
                output[output.count - 1] = HWPDocumentTextRun(
                    text: last.text + run.text,
                    fontName: last.fontName,
                    alternateFontName: last.alternateFontName,
                    baseFontName: last.baseFontName,
                    fontSignature: last.fontSignature,
                    fontSizePoints: last.fontSizePoints,
                    fontWidthPercent: last.fontWidthPercent,
                    letterSpacingPercent: last.letterSpacingPercent,
                    baselinePositionPercent: last.baselinePositionPercent,
                    textColorRGB: last.textColorRGB,
                    backgroundColorRGB: last.backgroundColorRGB,
                    isBold: last.isBold,
                    isItalic: last.isItalic,
                    isUnderlined: last.isUnderlined,
                    isStruckThrough: last.isStruckThrough,
                    isSuperscript: last.isSuperscript,
                    isSubscript: last.isSubscript,
                    hyperlink: last.hyperlink,
                    spaceWidthPoints: last.spaceWidthPoints,
                    tabWidthPoints: last.tabWidthPoints
                )
            } else {
                output.append(run)
            }
        }

        private static func languageIndex(for character: Character) -> Int {
            guard let value = character.unicodeScalars.first?.value else { return 4 }
            switch value {
            case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF:
                return 0
            case 0x0000...0x024F:
                return 1
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                return 2
            case 0x3040...0x30FF, 0x31F0...0x31FF:
                return 3
            case 0x2000...0x2BFF:
                return 5
            default:
                return 4
            }
        }
    }

    private struct DataReader {
        let data: Data
        var offset = 0

        init(_ data: Data) {
            self.data = data
        }

        var remainingBytes: Int { data.count - offset }

        mutating func seek(to newOffset: Int) throws {
            guard newOffset >= 0, newOffset <= data.count else {
                throw ChatAttachmentError.invalidHWP
            }
            offset = newOffset
        }

        mutating func readUInt8() throws -> UInt8 {
            guard remainingBytes >= 1 else { throw ChatAttachmentError.invalidHWP }
            defer { offset += 1 }
            return data[offset]
        }

        mutating func readInt8() throws -> Int8 {
            Int8(bitPattern: try readUInt8())
        }

        mutating func readUInt16() throws -> UInt16 {
            guard remainingBytes >= 2 else { throw ChatAttachmentError.invalidHWP }
            defer { offset += 2 }
            return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
        }

        mutating func readInt16() throws -> Int16 {
            Int16(bitPattern: try readUInt16())
        }

        mutating func readUInt32() throws -> UInt32 {
            guard remainingBytes >= 4 else { throw ChatAttachmentError.invalidHWP }
            defer { offset += 4 }
            return UInt32(data[offset])
                | UInt32(data[offset + 1]) << 8
                | UInt32(data[offset + 2]) << 16
                | UInt32(data[offset + 3]) << 24
        }

        mutating func readInt32() throws -> Int32 {
            Int32(bitPattern: try readUInt32())
        }

        mutating func readData(count: Int) throws -> Data {
            guard count >= 0, count <= remainingBytes else {
                throw ChatAttachmentError.invalidHWP
            }
            defer { offset += count }
            return data.subdata(in: offset..<(offset + count))
        }

        mutating func readUTF16String() throws -> String {
            let length = Int(try readUInt16())
            guard length <= remainingBytes / 2 else {
                throw ChatAttachmentError.invalidHWP
            }
            let bytes = try readData(count: length * 2)
            var units: [UInt16] = []
            units.reserveCapacity(length)
            var nested = DataReader(bytes)
            while nested.remainingBytes > 0 {
                units.append(try nested.readUInt16())
            }
            return String(decoding: units, as: UTF16.self)
        }
    }
}

private extension HWPDocumentTextRun {
    nonisolated func hasSamePresentation(as other: HWPDocumentTextRun) -> Bool {
        fontName == other.fontName
            && alternateFontName == other.alternateFontName
            && baseFontName == other.baseFontName
            && fontSignature == other.fontSignature
            && fontSizePoints == other.fontSizePoints
            && fontWidthPercent == other.fontWidthPercent
            && letterSpacingPercent == other.letterSpacingPercent
            && baselinePositionPercent == other.baselinePositionPercent
            && textColorRGB == other.textColorRGB
            && isBold == other.isBold
            && isItalic == other.isItalic
            && isUnderlined == other.isUnderlined
            && isStruckThrough == other.isStruckThrough
            && isSuperscript == other.isSuperscript
            && isSubscript == other.isSubscript
            && hyperlink == other.hyperlink
            && spaceWidthPoints == other.spaceWidthPoints
            && tabWidthPoints == other.tabWidthPoints
            && backgroundColorRGB == other.backgroundColorRGB
    }
}


private extension HWPDocumentCanvasObject {
    nonisolated func replacing(groupCoordinateFrame: CGRect) -> HWPDocumentCanvasObject {
        HWPDocumentCanvasObject(
            id: id, placement: placement, content: content, description: description,
            textContainerID: textContainerID, repeatsOnEveryPage: repeatsOnEveryPage,
            textContainerLayout: textContainerLayout,
            groupCoordinateFrame: groupCoordinateFrame)
    }

    nonisolated func replacing(placement: HWPDocumentObjectPlacement) -> HWPDocumentCanvasObject {
        HWPDocumentCanvasObject(
            id: id,
            placement: placement,
            content: content,
            description: description,
            textContainerID: textContainerID,
            repeatsOnEveryPage: repeatsOnEveryPage,
            textContainerLayout: textContainerLayout,
            groupCoordinateFrame: groupCoordinateFrame
        )
    }

    nonisolated func replacing(content: HWPDocumentCanvasContent) -> HWPDocumentCanvasObject {
        HWPDocumentCanvasObject(
            id: id,
            placement: placement,
            content: content,
            description: description,
            textContainerID: textContainerID,
            repeatsOnEveryPage: repeatsOnEveryPage,
            textContainerLayout: textContainerLayout,
            groupCoordinateFrame: groupCoordinateFrame
        )
    }

    nonisolated func replacing(textContainerID: String, layout: HWPDocumentTextContainerLayout?) -> HWPDocumentCanvasObject {
        HWPDocumentCanvasObject(
            id: id,
            placement: placement,
            content: content,
            description: description,
            textContainerID: textContainerID,
            repeatsOnEveryPage: repeatsOnEveryPage,
            textContainerLayout: layout,
            groupCoordinateFrame: groupCoordinateFrame
        )
    }

    nonisolated func appendingShape(_ shape: HWPDocumentShape) -> HWPDocumentCanvasObject {
        switch content {
        case .shape(let existing):
            return replacing(content: .group([existing, shape]))
        case .group(let existing):
            return replacing(content: .group(existing + [shape]))
        default:
            return replacing(content: .shape(shape))
        }
    }
}
