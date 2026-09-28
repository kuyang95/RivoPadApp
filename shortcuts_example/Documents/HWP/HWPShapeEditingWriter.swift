import Foundation
import CoreGraphics

nonisolated enum HWPShapeEditingWriter {
    typealias Record = HWP5DocumentRewriter.Record

    static func insert(_ request: HWPShapeEditing.Request, into source: HWPTableStructureDocument,
                       ownerIndex: Int) throws -> Data {
        guard request.isValid, source.blocks.indices.contains(ownerIndex) else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        let owner = source.blocks[ownerIndex]
        guard HWPImageEditing.supportsInsertion(in: owner),
              owner.tableLocation != nil || owner.text.isEmpty else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        switch source {
        case .hwpx(let package): return try insertHWPX(request, package: package, owner: owner)
        case .hwp(_, let data): return try insertHWP(request, data: data, owner: owner)
        }
    }

    static func apply(_ action: HWPShapeEditing.Action, target: HWPShapeEditing.Target,
                      to source: HWPTableStructureDocument, ownerIndex: Int) throws -> Data {
        guard source.blocks.indices.contains(ownerIndex), source.blocks[ownerIndex].id == target.ownerID else {
            throw HWPDocumentEditingError.staleDocument
        }
        switch source {
        case .hwpx(let package): return try editHWPX(action, target: target, package: package, owner: source.blocks[ownerIndex])
        case .hwp(_, let data): return try editHWP(action, target: target, data: data, owner: source.blocks[ownerIndex])
        }
    }

    static func group(_ request: HWPShapeEditing.GroupRequest,
                      in source: HWPTableStructureDocument, ownerIndex: Int) throws -> Data {
        guard request.isValid, source.blocks.indices.contains(ownerIndex),
              source.blocks[ownerIndex].id == request.ownerID else {
            throw HWPDocumentEditingError.staleDocument
        }
        switch source {
        case .hwpx(let package):
            return try groupHWPX(request, package: package, owner: source.blocks[ownerIndex])
        case .hwp(_, let data):
            return try groupHWP(request, data: data, owner: source.blocks[ownerIndex])
        }
    }

    static func batch(_ request: HWPShapeEditing.BatchRequest,
                      in source: HWPTableStructureDocument, ownerIndex: Int) throws -> Data {
        guard request.isValid, source.blocks.indices.contains(ownerIndex),
              source.blocks[ownerIndex].id == request.ownerID else {
            throw HWPDocumentEditingError.staleDocument
        }
        switch source {
        case .hwpx(let package):
            return try batchHWPX(request, package: package, owner: source.blocks[ownerIndex])
        case .hwp(_, let data):
            return try batchHWP(request, data: data, owner: source.blocks[ownerIndex])
        }
    }

    private static func unit(_ value: Double) -> String { String(Int((value * 100).rounded())) }
    private static func raw(_ value: Double) -> UInt32 { UInt32(bitPattern: Int32((value * 100).rounded())) }
    private static func color(_ value: UInt32) -> String { String(format: "#%06X", value & 0xFF_FFFF) }
    private static func colorReference(_ value: UInt32) -> UInt32 {
        ((value & 0xFF_0000) >> 16) | (value & 0x00_FF00) | ((value & 0x0000_FF) << 16)
    }
    private static func styleName(_ value: Int) -> String {
        switch value {
        case 0: "NONE"; case 2: "DASH"; case 3: "DOT"; case 4: "DASH_DOT"
        case 5: "DASH_DOT_DOT"; case 6: "LONG_DASH"; default: "SOLID"
        }
    }

    private static func nextObjectID(_ package: HWPXDocumentPackage) throws -> UInt32 {
        var maximum: UInt32 = 0
        for section in package.sections {
            for token in try HWPXParagraphXMLPatcher.tagTokens(in: section.xml) where !token.isClosing {
                let opening = (section.xml as NSString).substring(with: token.range)
                maximum = max(maximum, UInt32(try HWPFormattingXML.attribute(opening, "id") ?? "0") ?? 0)
            }
        }
        guard maximum < UInt32.max else { throw HWPDocumentEditingError.limitExceeded }
        return maximum + 1
    }

    private static func xmlName(_ kind: HWPShapeEditing.Kind) -> String {
        switch kind {
        case .rectangle: "rect"
        case .connector: "connectline"
        default: kind.rawValue
        }
    }
    private static func xmlElementName(_ kind: HWPShapeEditing.Kind) -> String {
        kind == .connector ? "connectLine" : xmlName(kind)
    }
    private static func pathPoints(_ kind: HWPShapeEditing.Kind, width: Double, height: Double,
                                   points: [HWPShapeEditing.PathPoint]? = nil) -> [HWPDocumentPoint] {
        let normalized = points.flatMap { $0.isEmpty ? nil : $0 } ?? kind.defaultPathPoints
        return normalized.map { HWPDocumentPoint(x: $0.x * width, y: $0.y * height) }
    }
    private static func pointXML(_ points: [HWPDocumentPoint], prefix: String, name: String = "pt") -> String {
        points.map { "<\(prefix)\(name) x=\"\(unit($0.x))\" y=\"\(unit($0.y))\"/>" }.joined()
    }
    private static func arrowName(_ value: Int) -> String {
        switch value {
        case 1: "ARROW"; case 2: "SPEAR"; case 3: "CONCAVE_ARROW"
        case 4: "EMPTY_DIAMOND"; case 5: "EMPTY_CIRCLE"; case 6: "EMPTY_BOX"
        default: "NORMAL"
        }
    }
    private static func referenceName(_ value: HWPDocumentLayoutReference) -> String {
        switch value { case .paper: "PAPER"; case .page: "PAGE"; case .column: "COLUMN"; default: "PARA" }
    }
    private static func alignmentName(_ value: HWPDocumentRelativeAlignment, horizontal: Bool) -> String {
        switch value {
        case .center: "CENTER"
        case .end: horizontal ? "RIGHT" : "BOTTOM"
        case .inside: "INSIDE"
        case .outside: "OUTSIDE"
        default: horizontal ? "LEFT" : "TOP"
        }
    }
    private static func wrapName(_ value: HWPDocumentObjectWrap) -> String {
        switch value {
        case .topAndBottom: "TOP_AND_BOTTOM"; case .behindText: "BEHIND_TEXT"
        case .inFrontOfText: "IN_FRONT_OF_TEXT"; case .tight: "TIGHT"
        case .through: "THROUGH"; default: "SQUARE"
        }
    }

    private static func insertHWPX(_ request: HWPShapeEditing.Request, package: HWPXDocumentPackage,
                                   owner: HWPDocumentBlock) throws -> Data {
        guard let section = package.sections.first(where: { $0.path == owner.sectionPath }),
              let paragraphIndex = section.blocks.firstIndex(where: { $0.id == owner.id }) else {
            throw HWPDocumentEditingError.staleDocument
        }
        let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: section.xml)
        guard ranges.indices.contains(paragraphIndex) else { throw HWPDocumentEditingError.staleDocument }
        let paragraph = (section.xml as NSString).substring(with: ranges[paragraphIndex])
        let prefix = try HWPFormattingXML.prefix(paragraph)
        guard let run = try HWPFormattingXML.elements(paragraph, name: "run").first else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        let width = unit(request.widthPoints), height = unit(request.heightPoints)
        let id = try nextObjectID(package)
        guard request.textBoxText == nil || id < UInt32.max else { throw HWPDocumentEditingError.limitExceeded }
        let name = xmlElementName(request.kind)
        let points: String
        switch request.kind {
        case .rectangle:
            points = "<\(prefix)pt0 x=\"0\" y=\"0\"/><\(prefix)pt1 x=\"\(width)\" y=\"0\"/><\(prefix)pt2 x=\"\(width)\" y=\"\(height)\"/><\(prefix)pt3 x=\"0\" y=\"\(height)\"/>"
        case .polygon:
            points = pointXML(pathPoints(.polygon, width: request.widthPoints, height: request.heightPoints),
                prefix: prefix)
        case .connector:
            let values = pathPoints(.connector, width: request.widthPoints, height: request.heightPoints)
            let controls = pointXML(Array(values.dropFirst().dropLast()), prefix: prefix, name: "point")
            points = "<\(prefix)startPt x=\"\(unit(values.first?.x ?? 0))\" y=\"\(unit(values.first?.y ?? 0))\" subjectIDRef=\"0\" subjectIdx=\"0\"/><\(prefix)endPt x=\"\(unit(values.last?.x ?? request.widthPoints))\" y=\"\(unit(values.last?.y ?? request.heightPoints))\" subjectIDRef=\"0\" subjectIdx=\"0\"/><\(prefix)controlPoints>\(controls)</\(prefix)controlPoints>"
        case .ellipse, .line: points = ""
        }
        let fill = request.kind == .line || request.kind == .connector ? "" : "<\(prefix)fillBrush><\(prefix)winBrush faceColor=\"#DCE9FF\" hatchColor=\"#DCE9FF\" alpha=\"0\"/></\(prefix)fillBrush>"
        let textBox: String
        if let text = request.textBoxText {
            let paraID = HWPFormattingXML.escaped(try HWPFormattingXML.attribute(paragraph, "paraPrIDRef") ?? "0")
            let styleID = HWPFormattingXML.escaped(try HWPFormattingXML.attribute(paragraph, "styleIDRef") ?? "0")
            let charID = HWPFormattingXML.escaped(try HWPFormattingXML.attribute(run.xml, "charPrIDRef") ?? "0")
            let encoded = HWPXParagraphXMLPatcher.encodedTextContent(text, prefix: prefix)
            textBox = "<\(prefix)subList id=\"\" textDirection=\"HORIZONTAL\" lineWrap=\"BREAK\" vertAlign=\"TOP\" linkListIDRef=\"0\" linkListNextIDRef=\"0\" textWidth=\"\(width)\" textHeight=\"\(height)\" hasTextRef=\"0\" hasNumRef=\"0\"><\(prefix)p id=\"\(id + 1)\" paraPrIDRef=\"\(paraID)\" styleIDRef=\"\(styleID)\" pageBreak=\"0\" columnBreak=\"0\" merged=\"0\"><\(prefix)run charPrIDRef=\"\(charID)\"><\(prefix)t xml:space=\"preserve\">\(encoded)</\(prefix)t></\(prefix)run></\(prefix)p></\(prefix)subList>"
        } else { textBox = "" }
        let connectorType = request.kind == .connector ? " type=\"STROKE_ONEWAY\"" : ""
        let endArrow = request.kind == .connector ? " tailStyle=\"ARROW\" tailfill=\"1\" tailSz=\"MEDIUM_MEDIUM\"" : ""
        let shape = "<\(prefix)\(name) id=\"\(id)\" zOrder=\"0\" numberingType=\"\(name.uppercased())\" textWrap=\"TOP_AND_BOTTOM\" textFlow=\"BOTH_SIDES\" lock=\"0\" dropcapstyle=\"None\"\(request.kind == .rectangle ? " ratio=\"0\"" : "")\(connectorType)><\(prefix)sz width=\"\(width)\" widthRelTo=\"ABSOLUTE\" height=\"\(height)\" heightRelTo=\"ABSOLUTE\" protect=\"0\"/><\(prefix)pos treatAsChar=\"1\" affectLSpacing=\"0\" flowWithText=\"1\" allowOverlap=\"1\" holdAnchorAndSO=\"0\" vertRelTo=\"PARA\" horzRelTo=\"PARA\" vertAlign=\"TOP\" horzAlign=\"LEFT\" vertOffset=\"0\" horzOffset=\"0\"/><\(prefix)outMargin left=\"0\" right=\"0\" top=\"0\" bottom=\"0\"/><\(prefix)lineShape color=\"#1F5EA8\" width=\"75\" style=\"SOLID\"\(endArrow)/>\(fill)\(points)\(textBox)<\(prefix)shapeComment>VisionCraft \(request.textBoxText == nil ? request.kind.title : "글상자")</\(prefix)shapeComment></\(prefix)\(name)>"
        let updatedParagraph: String
        if owner.tableLocation != nil {
            updatedParagraph = try HWPObjectInsertionSupport.insertingXMLObject(shape,
                caret: request.selection.caret, owner: owner, paragraph: paragraph)
        } else {
            let updatedRun = try HWPFormattingXML.append(shape, to: run.xml)
            updatedParagraph = (paragraph as NSString).replacingCharacters(in: run.range,
                with: updatedRun)
        }
        let sectionXML = (section.xml as NSString).replacingCharacters(in: ranges[paragraphIndex], with: updatedParagraph)
        return try HWPXEditingArchive(data: package.sourceData).repack(replacing: [section.path: Data(sectionXML.utf8)])
    }

    private static func groupHWPX(_ request: HWPShapeEditing.GroupRequest,
                                  package: HWPXDocumentPackage,
                                  owner: HWPDocumentBlock) throws -> Data {
        guard let section = package.sections.first(where: { $0.path == owner.sectionPath }),
              let paragraphIndex = section.blocks.firstIndex(where: { $0.id == owner.id }) else {
            throw HWPDocumentEditingError.staleDocument
        }
        let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: section.xml)
        guard ranges.indices.contains(paragraphIndex) else { throw HWPDocumentEditingError.staleDocument }
        let paragraph = (section.xml as NSString).substring(with: ranges[paragraphIndex])
        let selectedIndices = request.objectIDs.compactMap { id in
            owner.canvasObjects.firstIndex(where: { $0.id == id })
        }.sorted()
        guard selectedIndices.count == request.objectIDs.count else {
            throw HWPDocumentEditingError.staleDocument
        }
        var selected: [(index: Int, object: HWPDocumentCanvasObject,
                        element: HWPFormattingXML.Element)] = []
        for objectIndex in selectedIndices {
            let object = owner.canvasObjects[objectIndex]
            guard case .shape(let shape) = object.content,
                  let kind = HWPShapeEditing.target(owner: owner, object: object)?.kind else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            let sameKindBefore = owner.canvasObjects[..<objectIndex].reduce(0) { count, candidate in
                guard case .shape(let candidateShape) = candidate.content else { return count }
                return matches(candidateShape.geometry, kind: kind) ? count + 1 : count
            }
            let elements = try HWPFormattingXML.elements(paragraph, name: xmlName(kind))
            guard elements.indices.contains(sameKindBefore), matches(shape.geometry, kind: kind) else {
                throw HWPDocumentEditingError.staleDocument
            }
            selected.append((objectIndex, object, elements[sameKindBefore]))
        }
        guard let first = selected.first else { throw HWPDocumentEditingError.unsupportedEdit }
        let bounds = selected.dropFirst().reduce(CGRect(x: first.object.placement.xPoints,
            y: first.object.placement.yPoints, width: first.object.placement.widthPoints,
            height: first.object.placement.heightPoints)) { value, item in
            value.union(CGRect(x: item.object.placement.xPoints, y: item.object.placement.yPoints,
                width: item.object.placement.widthPoints, height: item.object.placement.heightPoints))
        }
        guard bounds.width > 0, bounds.height > 0 else { throw HWPDocumentEditingError.unsupportedEdit }
        let prefix = try HWPFormattingXML.prefix(first.element.xml)
        let children = try selected.map { item -> String in
            var result = item.element.xml
            var position = try HWPFormattingXML.elements(result, name: "pos").first?.xml
                ?? "<\(prefix)pos/>"
            position = try HWPFormattingXML.setAttribute(position, "treatAsChar", "0")
            position = try HWPFormattingXML.setAttribute(position, "horzOffset",
                unit(item.object.placement.xPoints - bounds.minX))
            position = try HWPFormattingXML.setAttribute(position, "vertOffset",
                unit(item.object.placement.yPoints - bounds.minY))
            position = try HWPFormattingXML.setAttribute(position, "horzRelTo", "PARA")
            position = try HWPFormattingXML.setAttribute(position, "vertRelTo", "PARA")
            result = try HWPFormattingXML.replaceOrAppend(result, name: "pos", replacement: position)
            return result
        }.joined()
        let id = try nextObjectID(package)
        let firstPlacement = first.object.placement
        let group = "<\(prefix)container id=\"\(id)\" zOrder=\"\(selected.map { $0.object.placement.zOrder }.min() ?? 0)\" numberingType=\"CONTAINER\" textWrap=\"\(wrapName(firstPlacement.wrap))\" textFlow=\"BOTH_SIDES\" lock=\"0\" dropcapstyle=\"None\"><\(prefix)sz width=\"\(unit(bounds.width))\" widthRelTo=\"ABSOLUTE\" height=\"\(unit(bounds.height))\" heightRelTo=\"ABSOLUTE\" protect=\"0\"/><\(prefix)pos treatAsChar=\"\(firstPlacement.isInline ? 1 : 0)\" affectLSpacing=\"0\" flowWithText=\"1\" allowOverlap=\"1\" holdAnchorAndSO=\"0\" vertRelTo=\"\(referenceName(firstPlacement.verticalReference))\" horzRelTo=\"\(referenceName(firstPlacement.horizontalReference))\" vertAlign=\"\(alignmentName(firstPlacement.verticalAlignment, horizontal: false))\" horzAlign=\"\(alignmentName(firstPlacement.horizontalAlignment, horizontal: true))\" vertOffset=\"\(unit(bounds.minY))\" horzOffset=\"\(unit(bounds.minX))\"/><\(prefix)outMargin left=\"\(unit(firstPlacement.marginLeftPoints))\" right=\"\(unit(firstPlacement.marginRightPoints))\" top=\"\(unit(firstPlacement.marginTopPoints))\" bottom=\"\(unit(firstPlacement.marginBottomPoints))\"/>\(children)</\(prefix)container>"
        var updated = paragraph
        for item in selected.sorted(by: { $0.element.range.location > $1.element.range.location }) {
            let replacement = item.element.range.location == first.element.range.location ? group : ""
            updated = (updated as NSString).replacingCharacters(in: item.element.range, with: replacement)
        }
        let sectionXML = (section.xml as NSString).replacingCharacters(in: ranges[paragraphIndex], with: updated)
        return try HWPXEditingArchive(data: package.sourceData).repack(
            replacing: [section.path: Data(sectionXML.utf8)])
    }

    private static func batchHWPX(_ request: HWPShapeEditing.BatchRequest,
                                  package: HWPXDocumentPackage,
                                  owner: HWPDocumentBlock) throws -> Data {
        guard let section = package.sections.first(where: { $0.path == owner.sectionPath }),
              let paragraphIndex = section.blocks.firstIndex(where: { $0.id == owner.id }) else {
            throw HWPDocumentEditingError.staleDocument
        }
        let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: section.xml)
        guard ranges.indices.contains(paragraphIndex) else {
            throw HWPDocumentEditingError.staleDocument
        }
        let paragraph = (section.xml as NSString).substring(with: ranges[paragraphIndex])
        let selectedIndices = request.objectIDs.compactMap { id in
            owner.canvasObjects.firstIndex(where: { $0.id == id })
        }.sorted()
        guard selectedIndices.count == request.objectIDs.count else {
            throw HWPDocumentEditingError.staleDocument
        }
        var selected: [(object: HWPDocumentCanvasObject,
                        element: HWPFormattingXML.Element)] = []
        for objectIndex in selectedIndices {
            let object = owner.canvasObjects[objectIndex]
            guard case .shape(let shape) = object.content,
                  let kind = HWPShapeEditing.target(owner: owner, object: object)?.kind else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            let sameKindBefore = owner.canvasObjects[..<objectIndex].reduce(0) { count, candidate in
                guard case .shape(let candidateShape) = candidate.content else { return count }
                return matches(candidateShape.geometry, kind: kind) ? count + 1 : count
            }
            let elements = try HWPFormattingXML.elements(paragraph, name: xmlName(kind))
            guard elements.indices.contains(sameKindBefore), matches(shape.geometry, kind: kind) else {
                throw HWPDocumentEditingError.staleDocument
            }
            selected.append((object, elements[sameKindBefore]))
        }
        guard !selected.isEmpty else { throw HWPDocumentEditingError.unsupportedEdit }
        let updated: String
        switch request.action {
        case .delete:
            updated = selected.sorted { $0.element.range.location > $1.element.range.location }
                .reduce(paragraph) { value, item in
                    (value as NSString).replacingCharacters(in: item.element.range, with: "")
                }
        case .duplicate:
            var nextID = try nextObjectID(package)
            let highestZ = owner.canvasObjects.map(\.placement.zOrder).max() ?? 0
            let clones = try selected.enumerated().map { offset, item -> String in
                var clone = try remappingElementIDs(item.element.xml, nextID: &nextID)
                let prefix = try HWPFormattingXML.prefix(clone)
                var position = try HWPFormattingXML.elements(clone, name: "pos").first?.xml
                    ?? "<\(prefix)pos/>"
                let rawX = Double(try HWPFormattingXML.attribute(position, "horzOffset") ?? "0") ?? 0
                let rawY = Double(try HWPFormattingXML.attribute(position, "vertOffset") ?? "0") ?? 0
                position = try HWPFormattingXML.setAttribute(position, "horzOffset",
                    String(Int(rawX.rounded()) + 1_200))
                position = try HWPFormattingXML.setAttribute(position, "vertOffset",
                    String(Int(rawY.rounded()) + 1_200))
                clone = try HWPFormattingXML.replaceOrAppend(clone, name: "pos", replacement: position)
                return try HWPFormattingXML.setAttribute(clone, "zOrder", String(highestZ + offset + 1))
            }.joined()
            let insertion = selected.map { NSMaxRange($0.element.range) }.max() ?? paragraph.utf16.count
            updated = (paragraph as NSString).replacingCharacters(
                in: NSRange(location: insertion, length: 0), with: clones)
        }
        let sectionXML = (section.xml as NSString).replacingCharacters(in: ranges[paragraphIndex],
            with: updated)
        guard sectionXML.utf8.count <= HWPXTextExtractor.maximumEntryBytes else {
            throw HWPDocumentEditingError.limitExceeded
        }
        return try HWPXEditingArchive(data: package.sourceData).repack(
            replacing: [section.path: Data(sectionXML.utf8)])
    }

    private static func remappingElementIDs(_ xml: String, nextID: inout UInt32) throws -> String {
        var replacements: [(range: NSRange, value: String)] = []
        for token in try HWPXParagraphXMLPatcher.tagTokens(in: xml) where !token.isClosing {
            let opening = (xml as NSString).substring(with: token.range)
            guard try HWPFormattingXML.attribute(opening, "id") != nil else { continue }
            guard nextID < UInt32.max else { throw HWPDocumentEditingError.limitExceeded }
            replacements.append((token.range,
                try HWPFormattingXML.setAttribute(opening, "id", String(nextID))))
            nextID += 1
        }
        return replacements.sorted { $0.range.location > $1.range.location }.reduce(xml) { value, item in
            (value as NSString).replacingCharacters(in: item.range, with: item.value)
        }
    }

    private static func editHWPX(_ action: HWPShapeEditing.Action, target: HWPShapeEditing.Target,
                                 package: HWPXDocumentPackage, owner: HWPDocumentBlock) throws -> Data {
        guard let section = package.sections.first(where: { $0.path == owner.sectionPath }),
              let paragraphIndex = section.blocks.firstIndex(where: { $0.id == owner.id }),
              let objectIndex = owner.canvasObjects.firstIndex(where: { $0.id == target.objectID }) else {
            throw HWPDocumentEditingError.staleDocument
        }
        let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: section.xml)
        guard ranges.indices.contains(paragraphIndex) else { throw HWPDocumentEditingError.staleDocument }
        let paragraph = (section.xml as NSString).substring(with: ranges[paragraphIndex])
        if case .ungroup = action {
            let updatedParagraph = try ungroupHWPX(target: target, owner: owner,
                objectIndex: objectIndex, paragraph: paragraph)
            let sectionXML = (section.xml as NSString).replacingCharacters(in: ranges[paragraphIndex],
                with: updatedParagraph)
            return try HWPXEditingArchive(data: package.sourceData).repack(
                replacing: [section.path: Data(sectionXML.utf8)])
        }
        guard let targetKind = target.kind else { throw HWPDocumentEditingError.unsupportedEdit }
        let outerElement: HWPFormattingXML.Element?
        let element: HWPFormattingXML.Element
        if let childIndex = target.groupChildIndex {
            guard case .group(let shapes) = owner.canvasObjects[objectIndex].content,
                  shapes.indices.contains(childIndex) else {
                throw HWPDocumentEditingError.staleDocument
            }
            let groupBefore = owner.canvasObjects[..<objectIndex].filter {
                if case .group = $0.content { return true }
                return false
            }.count
            let groups = try HWPFormattingXML.elements(paragraph, name: "container")
            guard groups.indices.contains(groupBefore) else { throw HWPDocumentEditingError.staleDocument }
            let group = groups[groupBefore]
            let sameKindBefore = shapes[..<childIndex].filter {
                matches($0.geometry, kind: targetKind)
            }.count
            let children = try HWPFormattingXML.elements(group.xml, name: xmlName(targetKind))
            guard children.indices.contains(sameKindBefore) else {
                throw HWPDocumentEditingError.staleDocument
            }
            outerElement = group
            element = children[sameKindBefore]
        } else {
            let sameKindBefore = owner.canvasObjects[..<objectIndex].reduce(0) { count, object in
                guard case .shape(let shape) = object.content else { return count }
                return matches(shape.geometry, kind: targetKind) ? count + 1 : count
            }
            let elements = try HWPFormattingXML.elements(paragraph, name: xmlName(targetKind))
            guard elements.indices.contains(sameKindBefore) else {
                throw HWPDocumentEditingError.staleDocument
            }
            outerElement = nil
            element = elements[sameKindBefore]
        }
        let replacement: String
        switch action {
        case .delete:
            if let childIndex = target.groupChildIndex, target.groupChildCount == 2,
               let outerTarget = HWPShapeEditing.target(owner: owner,
                   object: owner.canvasObjects[objectIndex]) {
                let updatedParagraph = try ungroupHWPX(target: outerTarget, owner: owner,
                    objectIndex: objectIndex, paragraph: paragraph,
                    keeping: Set([childIndex == 0 ? 1 : 0]))
                let sectionXML = (section.xml as NSString).replacingCharacters(
                    in: ranges[paragraphIndex], with: updatedParagraph)
                return try HWPXEditingArchive(data: package.sourceData).repack(
                    replacing: [section.path: Data(sectionXML.utf8)])
            }
            replacement = ""
        case .moveGroupChild(let offset):
            guard target.isGroupChild, let outerElement,
                  let childIndex = target.groupChildIndex else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            let childElements = try groupShapeElements(outerElement.xml)
            let destination = childIndex + offset
            guard childElements.indices.contains(childIndex), childElements.indices.contains(destination),
                  childElements.count == target.groupChildCount else {
                throw HWPDocumentEditingError.staleDocument
            }
            var reordered = childElements
            reordered.swapAt(childIndex, destination)
            let span = NSRange(location: childElements[0].range.location,
                length: NSMaxRange(childElements[childElements.count - 1].range)
                    - childElements[0].range.location)
            let group = (outerElement.xml as NSString).replacingCharacters(in: span,
                with: reordered.map(\.xml).joined())
            let updatedParagraph = (paragraph as NSString).replacingCharacters(in: outerElement.range,
                with: group)
            let sectionXML = (section.xml as NSString).replacingCharacters(in: ranges[paragraphIndex],
                with: updatedParagraph)
            return try HWPXEditingArchive(data: package.sourceData).repack(
                replacing: [section.path: Data(sectionXML.utf8)])
        case .update(let layout):
            guard layout.isValid else { throw HWPDocumentEditingError.limitExceeded }
            let prefix = try HWPFormattingXML.prefix(element.xml)
            var size = try HWPFormattingXML.elements(element.xml, name: "sz").first?.xml ?? "<\(prefix)sz/>"
            size = try HWPFormattingXML.setAttribute(size, "width", unit(layout.widthPoints))
            size = try HWPFormattingXML.setAttribute(size, "height", unit(layout.heightPoints))
            var result = try HWPFormattingXML.replaceOrAppend(element.xml, name: "sz", replacement: size)
            var position = try HWPFormattingXML.elements(result, name: "pos").first?.xml ?? "<\(prefix)pos/>"
            let previousRawX = Double(try HWPFormattingXML.attribute(position, "horzOffset") ?? "0")
                .map { $0 / 100 } ?? target.xPoints
            let previousRawY = Double(try HWPFormattingXML.attribute(position, "vertOffset") ?? "0")
                .map { $0 / 100 } ?? target.yPoints
            let storedX = target.isGroupChild ? layout.xPoints
                : (layout.isInline ? previousRawX + layout.xPoints - target.xPoints : layout.xPoints)
            let storedY = target.isGroupChild ? layout.yPoints
                : (layout.isInline ? previousRawY + layout.yPoints - target.yPoints : layout.yPoints)
            position = try HWPFormattingXML.setAttribute(position, "horzOffset", unit(storedX))
            position = try HWPFormattingXML.setAttribute(position, "vertOffset", unit(storedY))
            if !target.isGroupChild {
                position = try HWPFormattingXML.setAttribute(position, "treatAsChar", layout.isInline ? "1" : "0")
                position = try HWPFormattingXML.setAttribute(position, "horzRelTo", referenceName(layout.horizontalReference))
                position = try HWPFormattingXML.setAttribute(position, "vertRelTo", referenceName(layout.verticalReference))
                position = try HWPFormattingXML.setAttribute(position, "horzAlign",
                    alignmentName(layout.horizontalAlignment, horizontal: true))
                position = try HWPFormattingXML.setAttribute(position, "vertAlign",
                    alignmentName(layout.verticalAlignment, horizontal: false))
            }
            result = try HWPFormattingXML.replaceOrAppend(result, name: "pos", replacement: position)
            if !target.isGroupChild {
                var margin = try HWPFormattingXML.elements(result, name: "outmargin").first?.xml ?? "<\(prefix)outMargin/>"
                margin = try HWPFormattingXML.setAttribute(margin, "left", unit(layout.marginLeftPoints))
                margin = try HWPFormattingXML.setAttribute(margin, "right", unit(layout.marginRightPoints))
                margin = try HWPFormattingXML.setAttribute(margin, "top", unit(layout.marginTopPoints))
                margin = try HWPFormattingXML.setAttribute(margin, "bottom", unit(layout.marginBottomPoints))
                result = try HWPFormattingXML.replaceOrAppend(result, name: "outmargin", replacement: margin)
            }
            var flip = try HWPFormattingXML.elements(result, name: "flip").first?.xml
                ?? "<\(prefix)flip/>"
            flip = try HWPFormattingXML.setAttribute(flip, "horizontal",
                layout.flipHorizontal ? "1" : "0")
            flip = try HWPFormattingXML.setAttribute(flip, "vertical",
                layout.flipVertical ? "1" : "0")
            result = try HWPFormattingXML.replaceOrAppend(result, name: "flip", replacement: flip)
            let rotation = "<\(prefix)rotationInfo angle=\"\(layout.rotationDegrees)\" centerX=\"\(unit(layout.widthPoints / 2))\" centerY=\"\(unit(layout.heightPoints / 2))\"/>"
            result = try HWPFormattingXML.replaceOrAppend(result, name: "rotationinfo", replacement: rotation)
            var line = try HWPFormattingXML.elements(result, name: "lineshape").first?.xml ?? "<\(prefix)lineShape/>"
            line = try HWPFormattingXML.setAttribute(line, "color", color(layout.strokeColorRGB))
            line = try HWPFormattingXML.setAttribute(line, "width", unit(layout.strokeWidthPoints))
            line = try HWPFormattingXML.setAttribute(line, "style", styleName(layout.strokeStyle))
            line = try HWPFormattingXML.setAttribute(line, "headStyle", arrowName(layout.startArrow))
            line = try HWPFormattingXML.setAttribute(line, "tailStyle", arrowName(layout.endArrow))
            line = try HWPFormattingXML.setAttribute(line, "headfill", layout.startArrow == 0 ? "0" : "1")
            line = try HWPFormattingXML.setAttribute(line, "tailfill", layout.endArrow == 0 ? "0" : "1")
            result = try HWPFormattingXML.replaceOrAppend(result, name: "lineshape", replacement: line)
            let fill = layout.fillColorRGB.map {
                "<\(prefix)fillBrush><\(prefix)winBrush faceColor=\"\(color($0))\" hatchColor=\"\(color($0))\" alpha=\"0\"/></\(prefix)fillBrush>"
            } ?? ""
            result = try replaceOrRemove(result, name: "fillbrush", replacement: fill)
            let shadow = layout.shadow.map {
                let alpha = Int(((1 - $0.opacity) * 255).rounded())
                return "<\(prefix)shadow type=\"DROP\" color=\"\(color($0.colorRGB))\" offsetX=\"\(unit($0.offsetX))\" offsetY=\"\(unit($0.offsetY))\" alpha=\"\(alpha)\"/>"
            } ?? ""
            result = try replaceOrRemove(result, name: "shadow", replacement: shadow)
            if !target.isGroupChild {
                result = try HWPFormattingXML.setAttribute(result, "textWrap", wrapName(layout.wrap))
            }
            if targetKind == .polygon {
                result = try replacingPolygonPoints(in: result, prefix: prefix,
                    points: pathPoints(.polygon, width: layout.widthPoints, height: layout.heightPoints,
                        points: layout.pathPoints))
            } else if targetKind == .connector {
                result = try replacingConnectorPoints(in: result, prefix: prefix,
                    points: pathPoints(.connector, width: layout.widthPoints, height: layout.heightPoints,
                        points: layout.pathPoints))
                let connectorType = layout.startArrow != 0 && layout.endArrow != 0 ? "STROKE_BOTH"
                    : (layout.startArrow != 0 || layout.endArrow != 0 ? "STROKE_ONEWAY" : "STROKE_NOARROW")
                result = try HWPFormattingXML.setAttribute(result, "type", connectorType)
            }
            replacement = target.isGroupChild ? result
                : try HWPFormattingXML.setAttribute(result, "zOrder", String(layout.zOrder))
        case .ungroup:
            throw HWPDocumentEditingError.unsupportedEdit
        }
        let updatedParagraph: String
        if let outerElement {
            let group = (outerElement.xml as NSString).replacingCharacters(in: element.range,
                with: replacement)
            updatedParagraph = (paragraph as NSString).replacingCharacters(in: outerElement.range,
                with: group)
        } else {
            updatedParagraph = (paragraph as NSString).replacingCharacters(in: element.range,
                with: replacement)
        }
        let sectionXML = (section.xml as NSString).replacingCharacters(in: ranges[paragraphIndex], with: updatedParagraph)
        return try HWPXEditingArchive(data: package.sourceData).repack(replacing: [section.path: Data(sectionXML.utf8)])
    }

    private static func groupShapeElements(_ xml: String) throws -> [HWPFormattingXML.Element] {
        try [HWPShapeEditing.Kind.rectangle, .ellipse, .line, .polygon, .connector]
            .flatMap { try HWPFormattingXML.elements(xml, name: xmlName($0)) }
            .sorted { $0.range.location < $1.range.location }
    }

    private static func ungroupHWPX(target: HWPShapeEditing.Target, owner: HWPDocumentBlock,
                                    objectIndex: Int, paragraph: String,
                                    keeping: Set<Int>? = nil) throws -> String {
        guard target.isGroup, case .group(let shapes) = owner.canvasObjects[objectIndex].content,
              !shapes.isEmpty else { throw HWPDocumentEditingError.unsupportedEdit }
        let groupBefore = owner.canvasObjects[..<objectIndex].filter {
            if case .group = $0.content { return true }
            return false
        }.count
        let groups = try HWPFormattingXML.elements(paragraph, name: "container")
        guard groups.indices.contains(groupBefore) else { throw HWPDocumentEditingError.staleDocument }
        let group = groups[groupBefore]
        let elements = try groupShapeElements(group.xml)
        guard elements.count == shapes.count else { throw HWPDocumentEditingError.unsupportedEdit }
        let frames = shapes.compactMap(\.localFrame)
        guard frames.count == shapes.count, let first = frames.first else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        let bounds = frames.dropFirst().reduce(first) { $0.union($1) }
        guard bounds.width > 0, bounds.height > 0 else { throw HWPDocumentEditingError.unsupportedEdit }
        let scaleX = target.widthPoints / Double(bounds.width)
        let scaleY = target.heightPoints / Double(bounds.height)
        let replacements = try zip(zip(elements, shapes), frames).enumerated().compactMap { index, value -> String? in
            if let keeping, !keeping.contains(index) { return nil }
            let ((element, shape), frame) = value
            let prefix = try HWPFormattingXML.prefix(element.xml)
            let width = Double(frame.width) * scaleX
            let height = Double(frame.height) * scaleY
            var size = try HWPFormattingXML.elements(element.xml, name: "sz").first?.xml
                ?? "<\(prefix)sz/>"
            size = try HWPFormattingXML.setAttribute(size, "width", unit(width))
            size = try HWPFormattingXML.setAttribute(size, "height", unit(height))
            var result = try HWPFormattingXML.replaceOrAppend(element.xml, name: "sz", replacement: size)
            var position = try HWPFormattingXML.elements(result, name: "pos").first?.xml
                ?? "<\(prefix)pos/>"
            let x = target.xPoints + (Double(frame.minX) - Double(bounds.minX)) * scaleX
            let y = target.yPoints + (Double(frame.minY) - Double(bounds.minY)) * scaleY
            position = try HWPFormattingXML.setAttribute(position, "treatAsChar", "0")
            position = try HWPFormattingXML.setAttribute(position, "horzOffset", unit(x))
            position = try HWPFormattingXML.setAttribute(position, "vertOffset", unit(y))
            position = try HWPFormattingXML.setAttribute(position, "horzRelTo",
                referenceName(target.horizontalReference))
            position = try HWPFormattingXML.setAttribute(position, "vertRelTo",
                referenceName(target.verticalReference))
            position = try HWPFormattingXML.setAttribute(position, "horzAlign", "LEFT")
            position = try HWPFormattingXML.setAttribute(position, "vertAlign", "TOP")
            result = try HWPFormattingXML.replaceOrAppend(result, name: "pos", replacement: position)
            let rotation = (target.rotationDegrees + shape.rotationDegrees)
                .truncatingRemainder(dividingBy: 360)
            let rotationXML = "<\(prefix)rotationInfo angle=\"\(rotation)\" centerX=\"\(unit(width / 2))\" centerY=\"\(unit(height / 2))\"/>"
            result = try HWPFormattingXML.replaceOrAppend(result, name: "rotationinfo",
                replacement: rotationXML)
            result = try HWPFormattingXML.setAttribute(result, "zOrder", String(target.zOrder + index))
            result = try HWPFormattingXML.setAttribute(result, "textWrap", wrapName(target.wrap))
            return result
        }
        return (paragraph as NSString).replacingCharacters(in: group.range,
            with: replacements.joined())
    }

    private static func replaceOrRemove(_ xml: String, name: String, replacement: String) throws -> String {
        if let element = try HWPFormattingXML.elements(xml, name: name).first {
            return (xml as NSString).replacingCharacters(in: element.range, with: replacement)
        }
        return replacement.isEmpty ? xml : try HWPFormattingXML.append(replacement, to: xml)
    }

    private static func replacingPolygonPoints(in xml: String, prefix: String,
                                               points: [HWPDocumentPoint]) throws -> String {
        let elements = try HWPFormattingXML.elements(xml, name: "pt")
        let replacement = pointXML(points, prefix: prefix)
        guard let first = elements.first, let last = elements.last else {
            return try HWPFormattingXML.append(replacement, to: xml)
        }
        let range = NSRange(location: first.range.location,
            length: NSMaxRange(last.range) - first.range.location)
        return (xml as NSString).replacingCharacters(in: range, with: replacement)
    }

    private static func replacingConnectorPoints(in xml: String, prefix: String,
                                                 points: [HWPDocumentPoint]) throws -> String {
        guard points.count >= 2 else { throw HWPDocumentEditingError.limitExceeded }
        var result = xml
        var start = try HWPFormattingXML.elements(result, name: "startpt").first?.xml
            ?? "<\(prefix)startPt subjectIDRef=\"0\" subjectIdx=\"0\"/>"
        start = try HWPFormattingXML.setAttribute(start, "x", unit(points[0].x))
        start = try HWPFormattingXML.setAttribute(start, "y", unit(points[0].y))
        result = try HWPFormattingXML.replaceOrAppend(result, name: "startpt", replacement: start)
        var end = try HWPFormattingXML.elements(result, name: "endpt").first?.xml
            ?? "<\(prefix)endPt subjectIDRef=\"0\" subjectIdx=\"0\"/>"
        end = try HWPFormattingXML.setAttribute(end, "x", unit(points.last?.x ?? 0))
        end = try HWPFormattingXML.setAttribute(end, "y", unit(points.last?.y ?? 0))
        result = try HWPFormattingXML.replaceOrAppend(result, name: "endpt", replacement: end)
        let controls = pointXML(Array(points.dropFirst().dropLast()), prefix: prefix, name: "point")
        let container = "<\(prefix)controlPoints>\(controls)</\(prefix)controlPoints>"
        return try replaceOrRemove(result, name: "controlpoints", replacement: container)
    }

    private static func matches(_ geometry: HWPDocumentShapeGeometry, kind: HWPShapeEditing.Kind) -> Bool {
        switch (geometry, kind) {
        case (.rectangle, .rectangle), (.ellipse, .ellipse), (.line, .line),
             (.polygon, .polygon), (.curve, .connector): true
        default: false
        }
    }

    private static func expanded(_ data: Data, compressed: Bool) throws -> Data {
        try compressed ? HWP5TextExtractor.inflateRawDeflate(data,
            maximumBytes: HWP5TextExtractor.maximumSectionBytes) : data
    }

    private static func encoded(_ records: [Record], compressed: Bool) throws -> Data {
        let bytes = records.reduce(into: Data()) { $0.append($1.serialized()) }
        guard bytes.count <= HWP5TextExtractor.maximumSectionBytes else { throw HWPDocumentEditingError.limitExceeded }
        return try compressed ? HWP5DocumentRewriter.rawDeflate(bytes) : bytes
    }

    private static func sectionRecords(_ container: OLECompoundFile, compressed: Bool,
                                       owner: HWPDocumentBlock) throws -> (String, [Record], Int) {
        let paths = container.streamNames.filter { $0.hasPrefix("bodytext/section") }
            .sorted { (HWPPageSetup.sectionIndex($0) ?? 0) < (HWPPageSetup.sectionIndex($1) ?? 0) }
        var ordinal = 0
        for path in paths {
            let records = try HWP5DocumentRewriter.parseRecords(expanded(container.stream(named: path), compressed: compressed))
            for (index, record) in records.enumerated() where record.tag == 0x42 {
                if ordinal == owner.paragraphIndex && path == owner.sectionPath.lowercased() { return (path, records, index) }
                ordinal += 1
            }
        }
        throw HWPDocumentEditingError.staleDocument
    }

    private static func componentID(_ kind: HWPShapeEditing.Kind) -> UInt32 {
        switch kind {
        case .rectangle: 0x2472_6563
        case .ellipse: 0x2465_6C6C
        case .line: 0x246C_696E
        case .polygon: 0x2470_6F6C
        case .connector: 0x2463_7572
        }
    }

    private static func geometryRecord(_ kind: HWPShapeEditing.Kind, width: UInt32, height: UInt32,
                                       path: [HWPShapeEditing.PathPoint]? = nil,
                                       level: UInt32 = 3) -> Record {
        var payload = Data()
        switch kind {
        case .line:
            payload.hwpWriterAppendUInt32(0); payload.hwpWriterAppendUInt32(0)
            payload.hwpWriterAppendUInt32(width); payload.hwpWriterAppendUInt32(height)
            return .init(tag: 0x4E, level: level, payload: payload)
        case .rectangle:
            payload.append(0)
            for (x, y) in [(UInt32(0), UInt32(0)), (width, UInt32(0)), (width, height), (UInt32(0), height)] {
                payload.hwpWriterAppendUInt32(x); payload.hwpWriterAppendUInt32(y)
            }
            return .init(tag: 0x4F, level: level, payload: payload)
        case .ellipse:
            payload.hwpWriterAppendUInt32(0)
            for (x, y) in [(width / 2, height / 2), (width, height / 2), (width / 2, height)] {
                payload.hwpWriterAppendUInt32(x); payload.hwpWriterAppendUInt32(y)
            }
            return .init(tag: 0x50, level: level, payload: payload)
        case .polygon, .connector:
            let values = pathPoints(kind, width: Double(width) / 100, height: Double(height) / 100,
                points: path).map { (raw($0.x), raw($0.y)) }
            payload.hwpWriterAppendUInt16(UInt16(values.count))
            for value in values { payload.hwpWriterAppendUInt32(value.0) }
            for value in values { payload.hwpWriterAppendUInt32(value.1) }
            if kind == .connector { payload.append(Data(repeating: 0, count: max(values.count - 1, 0))) }
            return .init(tag: kind == .polygon ? 0x52 : 0x53, level: level, payload: payload)
        }
    }

    private static func insertHWP(_ request: HWPShapeEditing.Request, data: Data,
                                  owner: HWPDocumentBlock) throws -> Data {
        let container = try OLECompoundFile(data: data)
        let flags = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36)
        guard flags & 0x6796 == 0 else { throw HWPDocumentEditingError.protectedDocument }
        let compressed = flags & 1 != 0
        let (path, initial, start) = try sectionRecords(container, compressed: compressed, owner: owner)
        var records = initial
        let ownerLevel = records[start].level
        let childLevel = ownerLevel + 1
        var end = records.indices.dropFirst(start + 1).first {
            records[$0].level <= ownerLevel
        } ?? records.endIndex
        var owned = start..<end
        guard owned.allSatisfy({ [0x42, 0x43, 0x44, 0x45].contains(records[$0].tag) }),
              records[start].payload.count >= 22 else { throw HWPDocumentEditingError.unsupportedEdit }
        end = try HWPObjectInsertionSupport.insertAnchor(0x6773_6F20,
            caret: request.selection.caret, records: &records, header: start, end: end)
        owned = start..<end

        let width = raw(request.widthPoints), height = raw(request.heightPoints)
        var nextInstance: UInt32 = 1
        for record in records where record.payload.count >= 40 && record.tag == 0x47 {
            nextInstance = max(nextInstance, try record.payload.hwpWriterUInt32(at: 36) &+ 1)
        }
        var control = Data(repeating: 0, count: 46)
        control.hwpWriterSetUInt32(0x6773_6F20, at: 0)
        control.hwpWriterSetUInt32(1 | (2 << 3) | (3 << 8) | (1 << 21), at: 4)
        control.hwpWriterSetUInt32(width, at: 16); control.hwpWriterSetUInt32(height, at: 20)
        control.hwpWriterSetUInt32(nextInstance, at: 36)
        let comment = Array("VisionCraft \(request.kind.title)".utf16)
        control.hwpWriterSetUInt16(UInt16(comment.count), at: 44)
        for value in comment { control.hwpWriterAppendUInt16(value) }
        var component = Data(repeating: 0, count: 46)
        component.hwpWriterSetUInt32(componentID(request.kind), at: 0)
        component.hwpWriterSetUInt16(1, at: 14)
        for offset in [16, 24] { component.hwpWriterSetUInt32(width, at: offset) }
        for offset in [20, 28] { component.hwpWriterSetUInt32(height, at: offset) }
        component.hwpWriterSetUInt32(width / 2, at: 38); component.hwpWriterSetUInt32(height / 2, at: 42)
        component = try styledComponent(component, width: width, height: height,
            rotationDegrees: 0, flipHorizontal: false, flipVertical: false,
            strokeColorRGB: 0x1F5EA8, strokeWidthPoints: 0.75,
            strokeStyle: 1,
            fillColorRGB: request.kind == .line || request.kind == .connector ? nil : 0xDCE9FF,
            shadow: nil, startArrow: 0, endArrow: request.kind == .connector ? 1 : 0)
        var inserted: [Record] = [.init(tag: 0x47, level: childLevel, payload: control),
                                  .init(tag: 0x4C, level: childLevel + 1, payload: component),
                                  geometryRecord(request.kind, width: width, height: height,
                                    level: childLevel + 2)]
        if let text = request.textBoxText {
            guard nextInstance < UInt32.max else { throw HWPDocumentEditingError.limitExceeded }
            inserted += try textBoxRecords(text: text, records: records, ownerRange: owned,
                paragraphID: nextInstance + 1, level: childLevel + 1)
        }
        records.insert(contentsOf: inserted, at: end)
        return try container.serialized(replacing: [path: encoded(records, compressed: compressed)])
    }

    private static func textBoxRecords(text: String, records: [Record], ownerRange: Range<Int>,
                                       paragraphID: UInt32, level: UInt32 = 2) throws -> [Record] {
        guard let headerIndex = ownerRange.first(where: { records[$0].tag == 0x42 }),
              records[headerIndex].payload.count >= 22 else { throw HWPDocumentEditingError.unsupportedEdit }
        var textData = Data()
        for unit in text.utf16 {
            if unit == 9 { for value in [UInt16](arrayLiteral: 9, 0, 0, 0, 0, 0, 0, 9) { textData.hwpWriterAppendUInt16(value) } }
            else if unit == 10 { textData.hwpWriterAppendUInt16(10) }
            else if unit < 32 { throw HWPDocumentEditingError.unsupportedEdit }
            else { textData.hwpWriterAppendUInt16(unit) }
        }
        textData.hwpWriterAppendUInt16(13)
        var header = records[headerIndex].payload
        header.hwpWriterSetUInt32(0x8000_0000 | UInt32(textData.count / 2), at: 0)
        var mask: UInt32 = 0
        if text.contains("\t") { mask |= 1 << 9 }
        if text.contains("\n") { mask |= 1 << 10 }
        header.hwpWriterSetUInt32(mask, at: 4)
        header[11] = 0
        header.hwpWriterSetUInt16(1, at: 12); header.hwpWriterSetUInt16(0, at: 14)
        header.hwpWriterSetUInt16(0, at: 16); header.hwpWriterSetUInt32(paragraphID, at: 18)
        var character = Data(); character.hwpWriterAppendUInt32(0)
        let charShape = ownerRange.first(where: { records[$0].tag == 0x44 && records[$0].payload.count >= 8 })
            .flatMap { try? records[$0].payload.hwpWriterUInt32(at: 4) } ?? 0
        character.hwpWriterAppendUInt32(charShape)
        var list = Data(); list.hwpWriterAppendUInt16(1); list.hwpWriterAppendUInt16(0)
        list.hwpWriterAppendUInt32(0)
        for _ in 0..<4 { list.hwpWriterAppendUInt16(600) }
        return [.init(tag: 0x48, level: level, payload: list),
                .init(tag: 0x42, level: level, payload: header),
                .init(tag: 0x43, level: level + 1, payload: textData),
                .init(tag: 0x44, level: level + 1, payload: character)]
    }

    private static let objectControlIDs: Set<UInt32> = [
        0x2470_6963, 0x6773_6F20, 0x6571_6564, 0x246C_696E, 0x2472_6563,
        0x2465_6C6C, 0x2461_7263, 0x2470_6F6C, 0x2463_7572, 0x246F_6C65, 0x2463_6F6E
    ]

    private static func batchHWP(_ request: HWPShapeEditing.BatchRequest, data: Data,
                                 owner: HWPDocumentBlock) throws -> Data {
        let container = try OLECompoundFile(data: data)
        let flags = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36)
        guard flags & 0x6796 == 0 else { throw HWPDocumentEditingError.protectedDocument }
        let compressed = flags & 1 != 0
        let (path, initial, ownerRecord) = try sectionRecords(container,
            compressed: compressed, owner: owner)
        var records = initial
        let ownerLevel = records[ownerRecord].level
        let childLevel = ownerLevel + 1
        func objectControls(_ values: [Record], _ end: Int) -> [Int] {
            (ownerRecord + 1..<end).filter { index in
                guard values[index].tag == 0x47, values[index].level == childLevel,
                      values[index].payload.count >= 40,
                      let identifier = try? values[index].payload.hwpWriterUInt32(at: 0) else {
                    return false
                }
                return objectControlIDs.contains(identifier)
            }
        }
        let initialEnd = records.indices.dropFirst(ownerRecord + 1).first {
            records[$0].level <= ownerLevel
        } ?? records.endIndex
        let initialControls = objectControls(records, initialEnd)
        let selectedObjectIndices = request.objectIDs.compactMap { id in
            owner.canvasObjects.firstIndex(where: { $0.id == id })
        }.sorted()
        guard selectedObjectIndices.count == request.objectIDs.count,
              selectedObjectIndices.allSatisfy({ initialControls.indices.contains($0) }),
              selectedObjectIndices.allSatisfy({ index in
                  if case .shape = owner.canvasObjects[index].content { return true }
                  return false
              }) else { throw HWPDocumentEditingError.unsupportedEdit }

        switch request.action {
        case .delete:
            for objectIndex in selectedObjectIndices.reversed() {
                let ownerEnd = records.indices.dropFirst(ownerRecord + 1).first {
                    records[$0].level <= ownerLevel
                } ?? records.endIndex
                let controls = objectControls(records, ownerEnd)
                guard controls.indices.contains(objectIndex) else {
                    throw HWPDocumentEditingError.staleDocument
                }
                let controlIndex = controls[objectIndex]
                let controlEnd = records.indices.dropFirst(controlIndex + 1).first {
                    records[$0].level <= records[controlIndex].level
                } ?? records.endIndex
                try removeAnchorAndControl(records: &records, ownerRecord: ownerRecord,
                    ownerEnd: ownerEnd, controls: controls, objectIndex: objectIndex,
                    controlIndex: controlIndex, controlEnd: controlEnd)
            }
        case .duplicate:
            let selectedControls = selectedObjectIndices.map { initialControls[$0] }
            let ranges = selectedControls.map { control -> Range<Int> in
                let end = records.indices.dropFirst(control + 1).first {
                    records[$0].level <= records[control].level
                } ?? records.endIndex
                return control..<end
            }
            var nextInstance: UInt32 = 1
            var nextParagraphID: UInt32 = 1
            for record in records {
                if record.tag == 0x47, record.payload.count >= 40 {
                    let value = try record.payload.hwpWriterUInt32(at: 36)
                    guard value < UInt32.max else { throw HWPDocumentEditingError.limitExceeded }
                    nextInstance = max(nextInstance, value + 1)
                }
                if record.tag == 0x42, record.payload.count >= 22 {
                    let value = try record.payload.hwpWriterUInt32(at: 18)
                    guard value < UInt32.max else { throw HWPDocumentEditingError.limitExceeded }
                    nextParagraphID = max(nextParagraphID, value + 1)
                }
            }
            let highestZ = owner.canvasObjects.map(\.placement.zOrder).max() ?? 0
            var identifiers: [UInt32] = []
            var clones: [Record] = []
            for (selectionOffset, range) in ranges.enumerated() {
                for (recordOffset, sourceIndex) in range.enumerated() {
                    var record = records[sourceIndex]
                    if record.tag == 0x47, record.payload.count >= 40 {
                        guard nextInstance < UInt32.max else {
                            throw HWPDocumentEditingError.limitExceeded
                        }
                        record.payload.hwpWriterSetUInt32(nextInstance, at: 36)
                        nextInstance += 1
                    }
                    if record.tag == 0x42, record.payload.count >= 22 {
                        guard nextParagraphID < UInt32.max else {
                            throw HWPDocumentEditingError.limitExceeded
                        }
                        record.payload.hwpWriterSetUInt32(nextParagraphID, at: 18)
                        nextParagraphID += 1
                    }
                    if recordOffset == 0 {
                        guard record.tag == 0x47, record.payload.count >= 40 else {
                            throw HWPDocumentEditingError.unsupportedEdit
                        }
                        let x = Int32(bitPattern: try record.payload.hwpWriterUInt32(at: 12))
                        let y = Int32(bitPattern: try record.payload.hwpWriterUInt32(at: 8))
                        guard x <= Int32.max - 1_200, y <= Int32.max - 1_200 else {
                            throw HWPDocumentEditingError.limitExceeded
                        }
                        record.payload.hwpWriterSetUInt32(UInt32(bitPattern: x + 1_200), at: 12)
                        record.payload.hwpWriterSetUInt32(UInt32(bitPattern: y + 1_200), at: 8)
                        record.payload.hwpWriterSetUInt32(
                            UInt32(bitPattern: Int32(highestZ + selectionOffset + 1)), at: 24)
                        identifiers.append(try record.payload.hwpWriterUInt32(at: 0))
                    }
                    clones.append(record)
                }
            }
            try addObjectAnchors(records: &records, ownerRecord: ownerRecord,
                ownerEnd: initialEnd, identifiers: identifiers)
            records.insert(contentsOf: clones, at: initialEnd)
        }
        return try container.serialized(replacing: [path: encoded(records, compressed: compressed)])
    }

    private static func groupHWP(_ request: HWPShapeEditing.GroupRequest, data: Data,
                                 owner: HWPDocumentBlock) throws -> Data {
        let container = try OLECompoundFile(data: data)
        let flags = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36)
        guard flags & 0x6796 == 0 else { throw HWPDocumentEditingError.protectedDocument }
        let compressed = flags & 1 != 0
        let (path, initial, ownerRecord) = try sectionRecords(container, compressed: compressed, owner: owner)
        var records = initial
        let ownerLevel = records[ownerRecord].level
        let childLevel = ownerLevel + 1
        let ownerEnd = records.indices.dropFirst(ownerRecord + 1).first {
            records[$0].level <= ownerLevel
        }
            ?? records.endIndex
        let controls = (ownerRecord + 1..<ownerEnd).filter { index in
            guard records[index].tag == 0x47, records[index].level == childLevel,
                  records[index].payload.count >= 40,
                  let identifier = try? records[index].payload.hwpWriterUInt32(at: 0) else { return false }
            return objectControlIDs.contains(identifier)
        }
        let selectedObjectIndices = request.objectIDs.compactMap { id in
            owner.canvasObjects.firstIndex(where: { $0.id == id })
        }.sorted()
        guard selectedObjectIndices.count == request.objectIDs.count,
              selectedObjectIndices.allSatisfy({ controls.indices.contains($0) }) else {
            throw HWPDocumentEditingError.staleDocument
        }
        let selectedObjects = selectedObjectIndices.map { owner.canvasObjects[$0] }
        guard selectedObjects.allSatisfy({ object in
            if case .shape = object.content { return true }
            return false
        }), let firstObject = selectedObjects.first else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        let selectedControls = selectedObjectIndices.map { controls[$0] }
        let ranges = selectedControls.map { control -> Range<Int> in
            let end = records.indices.dropFirst(control + 1).first {
                records[$0].level <= records[control].level
            } ?? records.endIndex
            return control..<end
        }
        let firstFrame = CGRect(x: firstObject.placement.xPoints, y: firstObject.placement.yPoints,
            width: firstObject.placement.widthPoints, height: firstObject.placement.heightPoints)
        let bounds = selectedObjects.dropFirst().reduce(firstFrame) { value, object in
            value.union(CGRect(x: object.placement.xPoints, y: object.placement.yPoints,
                width: object.placement.widthPoints, height: object.placement.heightPoints))
        }
        guard bounds.width > 0, bounds.height > 0 else { throw HWPDocumentEditingError.unsupportedEdit }
        let groupID: UInt32 = 0x6773_6F20
        let componentID: UInt32 = 0x2463_6F6E
        var control = records[selectedControls[0]].payload
        control.hwpWriterSetUInt32(groupID, at: 0)
        control.hwpWriterSetUInt32(raw(bounds.minY), at: 8)
        control.hwpWriterSetUInt32(raw(bounds.minX), at: 12)
        control.hwpWriterSetUInt32(raw(bounds.width), at: 16)
        control.hwpWriterSetUInt32(raw(bounds.height), at: 20)
        control.hwpWriterSetUInt32(UInt32(bitPattern: Int32(selectedObjects.map(\.placement.zOrder).min() ?? 0)), at: 24)

        var childRecords: [[Record]] = []
        var memberIDs: [Data] = []
        var outerSource: Data?
        for (offset, range) in ranges.enumerated() {
            guard let componentIndex = range.dropFirst().first(where: { records[$0].tag == 0x4C }),
                  records[componentIndex].payload.count >= 46 else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            var component = records[componentIndex].payload
            let shift = try shapeComponentHeaderShift(component)
            guard component.count >= 46 + shift else { throw HWPDocumentEditingError.unsupportedEdit }
            if outerSource == nil { outerSource = component }
            memberIDs.append(component.subdata(in: 0..<4))
            component.hwpWriterSetUInt32(raw(selectedObjects[offset].placement.xPoints - bounds.minX), at: 4 + shift)
            component.hwpWriterSetUInt32(raw(selectedObjects[offset].placement.yPoints - bounds.minY), at: 8 + shift)
            component.hwpWriterSetUInt16(1, at: 12 + shift)
            let width = raw(selectedObjects[offset].placement.widthPoints)
            let height = raw(selectedObjects[offset].placement.heightPoints)
            for position in [16, 24] { component.hwpWriterSetUInt32(width, at: position + shift) }
            for position in [20, 28] { component.hwpWriterSetUInt32(height, at: position + shift) }
            component.hwpWriterSetUInt32(width / 2, at: 38 + shift)
            component.hwpWriterSetUInt32(height / 2, at: 42 + shift)
            var bundle: [Record] = [.init(tag: 0x4C,
                level: records[componentIndex].level + 1, payload: component)]
            for index in (componentIndex + 1)..<range.upperBound {
                bundle.append(.init(tag: records[index].tag,
                    level: records[index].level + 1, payload: records[index].payload))
            }
            childRecords.append(bundle)
        }
        guard var outer = outerSource else { throw HWPDocumentEditingError.unsupportedEdit }
        let outerShift = try shapeComponentHeaderShift(outer)
        outer.hwpWriterSetUInt32(componentID, at: 0)
        outer.hwpWriterSetUInt32(0, at: 4 + outerShift)
        outer.hwpWriterSetUInt32(0, at: 8 + outerShift)
        outer.hwpWriterSetUInt16(0, at: 12 + outerShift)
        outer.hwpWriterSetUInt16(0, at: 36 + outerShift)
        let groupWidth = raw(bounds.width), groupHeight = raw(bounds.height)
        for position in [16, 24] { outer.hwpWriterSetUInt32(groupWidth, at: position + outerShift) }
        for position in [20, 28] { outer.hwpWriterSetUInt32(groupHeight, at: position + outerShift) }
        outer.hwpWriterSetUInt32(groupWidth / 2, at: 38 + outerShift)
        outer.hwpWriterSetUInt32(groupHeight / 2, at: 42 + outerShift)
        outer.hwpWriterAppendUInt16(UInt16(memberIDs.count))
        memberIDs.forEach { outer.append($0) }
        outer.append(Data(repeating: 0, count: 4))
        let grouped: [Record] = [.init(tag: 0x47, level: childLevel, payload: control),
            .init(tag: 0x4C, level: childLevel + 1, payload: outer)]
            + childRecords.flatMap { $0 }

        try replaceObjectAnchorsForGroup(records: &records, ownerRecord: ownerRecord,
            ownerEnd: ownerEnd, controls: controls, selectedObjectIndices: selectedObjectIndices,
            groupID: groupID)
        let selectedRecordIndices = Set(ranges.flatMap { Array($0) })
        let insertion = selectedControls[0]
        var rebuilt: [Record] = []
        rebuilt.reserveCapacity(records.count - selectedRecordIndices.count + grouped.count)
        for index in records.indices {
            if index == insertion { rebuilt.append(contentsOf: grouped) }
            if !selectedRecordIndices.contains(index) { rebuilt.append(records[index]) }
        }
        return try container.serialized(replacing: [path: encoded(rebuilt, compressed: compressed)])
    }

    private static func replaceObjectAnchorsForGroup(records: inout [Record], ownerRecord: Int,
                                                     ownerEnd: Int, controls: [Int],
                                                     selectedObjectIndices: [Int],
                                                     groupID: UInt32) throws {
        let childLevel = records[ownerRecord].level + 1
        let direct = (ownerRecord + 1..<ownerEnd).filter {
            records[$0].level == childLevel
        }
        guard let textIndex = direct.first(where: { records[$0].tag == 0x43 }),
              records[ownerRecord].payload.count >= 22 else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        var keys: Set<String> = []
        for objectIndex in selectedObjectIndices {
            let identifier = try records[controls[objectIndex]].payload.hwpWriterUInt32(at: 0)
            let occurrence = controls[..<objectIndex].filter {
                (try? records[$0].payload.hwpWriterUInt32(at: 0)) == identifier
            }.count
            keys.insert("\(identifier)-\(occurrence)")
        }
        var bytes = records[textIndex].payload
        var cursor = 0
        var occurrences: [UInt32: Int] = [:]
        var selectedRanges: [Range<Int>] = []
        while cursor < bytes.count / 2 {
            let code = try bytes.hwpWriterUInt16(at: cursor * 2)
            let size = code >= 1 && code <= 23 && code != 10 && code != 13 ? 8 : 1
            guard cursor + size <= bytes.count / 2 else { throw HWPDocumentEditingError.invalidDocument }
            if code == 11 {
                let identifier = try bytes.hwpWriterUInt32(at: cursor * 2 + 2)
                let occurrence = occurrences[identifier, default: 0]
                if keys.contains("\(identifier)-\(occurrence)") {
                    selectedRanges.append(cursor * 2..<(cursor + 8) * 2)
                }
                occurrences[identifier] = occurrence + 1
            }
            cursor += size
        }
        guard selectedRanges.count == selectedObjectIndices.count,
              let insertion = selectedRanges.map(\.lowerBound).min() else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        for range in selectedRanges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            bytes.removeSubrange(range)
        }
        var anchor = Data()
        anchor.hwpWriterAppendUInt16(11); anchor.hwpWriterAppendUInt32(groupID)
        anchor.append(Data(repeating: 0, count: 8)); anchor.hwpWriterAppendUInt16(11)
        bytes.insert(contentsOf: anchor, at: insertion)
        records[textIndex].payload = bytes
        let last = try records[ownerRecord].payload.hwpWriterUInt32(at: 0) & 0x8000_0000
        records[ownerRecord].payload.hwpWriterSetUInt32(last | UInt32(bytes.count / 2), at: 0)
        records[ownerRecord].payload.hwpWriterSetUInt32(
            try records[ownerRecord].payload.hwpWriterUInt32(at: 4) | (1 << 11), at: 4)
    }

    private static func editHWP(_ action: HWPShapeEditing.Action, target: HWPShapeEditing.Target,
                                data: Data, owner: HWPDocumentBlock) throws -> Data {
        let container = try OLECompoundFile(data: data)
        let flags = try container.stream(named: "FileHeader").hwpWriterUInt32(at: 36)
        guard flags & 0x6796 == 0 else { throw HWPDocumentEditingError.protectedDocument }
        let compressed = flags & 1 != 0
        let (path, initial, ownerRecord) = try sectionRecords(container, compressed: compressed, owner: owner)
        var records = initial
        guard let objectIndex = owner.canvasObjects.firstIndex(where: { $0.id == target.objectID }) else {
            throw HWPDocumentEditingError.staleDocument
        }
        let ownerLevel = records[ownerRecord].level
        let childLevel = ownerLevel + 1
        let ownerEnd = records.indices.dropFirst(ownerRecord + 1).first {
            records[$0].level <= ownerLevel
        } ?? records.endIndex
        let controls = (ownerRecord + 1..<ownerEnd).filter { index in
            guard records[index].tag == 0x47, records[index].level == childLevel,
                  records[index].payload.count >= 4,
                  let identifier = try? records[index].payload.hwpWriterUInt32(at: 0) else { return false }
            return objectControlIDs.contains(identifier)
        }
        guard controls.indices.contains(objectIndex) else { throw HWPDocumentEditingError.staleDocument }
        let controlIndex = controls[objectIndex]
        let end = records.indices.dropFirst(controlIndex + 1).first { records[$0].level <= records[controlIndex].level } ?? records.endIndex
        let geometryIndices = records.indices[controlIndex..<end].filter {
            [0x4E, 0x4F, 0x50, 0x52, 0x53].contains(records[$0].tag)
        }
        let geometryIndex = target.groupChildIndex.flatMap {
            geometryIndices.indices.contains($0) ? geometryIndices[$0] : nil
        } ?? geometryIndices.first
        if target.kind != nil, geometryIndex == nil { throw HWPDocumentEditingError.unsupportedEdit }
        switch action {
        case .moveGroupChild(let offset):
            guard let childIndex = target.groupChildIndex,
                  case .group(let shapes) = owner.canvasObjects[objectIndex].content else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            let bundles = try hwpGroupChildBundles(records: records, controlIndex: controlIndex,
                controlEnd: end, expectedCount: shapes.count)
            let destination = childIndex + offset
            guard bundles.indices.contains(childIndex), bundles.indices.contains(destination),
                  let groupComponent = records.indices[controlIndex..<bundles[0].lowerBound]
                    .last(where: { records[$0].tag == 0x4C }) else {
                throw HWPDocumentEditingError.staleDocument
            }
            let members = try hwpGroupMemberIDs(records[groupComponent].payload,
                expectedCount: shapes.count)
            var reorderedMembers = members.ids
            reorderedMembers.swapAt(childIndex, destination)
            records[groupComponent].payload = hwpGroupPayload(records[groupComponent].payload,
                memberStart: members.start, ids: reorderedMembers, suffix: members.suffix)
            var reordered = bundles.map { Array(records[$0]) }
            reordered.swapAt(childIndex, destination)
            records.replaceSubrange(bundles[0].lowerBound..<bundles[bundles.count - 1].upperBound,
                with: reordered.flatMap { $0 })
            return try container.serialized(replacing: [path: encoded(records, compressed: compressed)])
        case .ungroup:
            guard target.isGroup, case .group(let shapes) = owner.canvasObjects[objectIndex].content else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            let bundles = try hwpGroupChildBundles(records: records, controlIndex: controlIndex,
                controlEnd: end, expectedCount: shapes.count)
            let replacements = try ungroupedHWPRecords(records: records, controlIndex: controlIndex,
                bundles: bundles, shapes: shapes, target: target)
            try addObjectAnchors(records: &records, ownerRecord: ownerRecord, ownerEnd: ownerEnd,
                identifier: try records[controlIndex].payload.hwpWriterUInt32(at: 0),
                count: max(replacements.filter {
                    $0.tag == 0x47 && $0.level == childLevel
                }.count - 1, 0))
            records.replaceSubrange(controlIndex..<end, with: replacements)
            return try container.serialized(replacing: [path: encoded(records, compressed: compressed)])
        case .update(let layout):
            guard layout.isValid, records[controlIndex].payload.count >= 28 else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            let width = raw(layout.widthPoints), height = raw(layout.heightPoints)
            if target.isGroupChild {
                guard let kind = target.kind, let geometryIndex,
                      let component = records.indices[controlIndex...geometryIndex].last(where: {
                          records[$0].tag == 0x4C
                      }), records[component].payload.count >= 46 else {
                    throw HWPDocumentEditingError.unsupportedEdit
                }
                let shift = try shapeComponentHeaderShift(records[component].payload)
                guard records[component].payload.count >= 46 + shift else {
                    throw HWPDocumentEditingError.unsupportedEdit
                }
                records[component].payload.hwpWriterSetUInt32(raw(layout.xPoints), at: 4 + shift)
                records[component].payload.hwpWriterSetUInt32(raw(layout.yPoints), at: 8 + shift)
                for offset in [16, 24] {
                    records[component].payload.hwpWriterSetUInt32(width, at: offset + shift)
                }
                for offset in [20, 28] {
                    records[component].payload.hwpWriterSetUInt32(height, at: offset + shift)
                }
                records[component].payload = try styledComponent(records[component].payload,
                    width: width, height: height, rotationDegrees: layout.rotationDegrees,
                    flipHorizontal: layout.flipHorizontal, flipVertical: layout.flipVertical,
                    strokeColorRGB: layout.strokeColorRGB,
                    strokeWidthPoints: layout.strokeWidthPoints, strokeStyle: layout.strokeStyle,
                    fillColorRGB: layout.fillColorRGB, shadow: layout.shadow,
                    startArrow: layout.startArrow, endArrow: layout.endArrow)
                let geometry = geometryRecord(kind, width: width, height: height,
                    path: layout.pathPoints)
                records[geometryIndex] = Record(tag: geometry.tag,
                    level: records[geometryIndex].level, payload: geometry.payload)
                return try container.serialized(replacing: [path: encoded(records, compressed: compressed)])
            }
            records[controlIndex].payload.hwpWriterSetUInt32(raw(layout.yPoints), at: 8)
            records[controlIndex].payload.hwpWriterSetUInt32(raw(layout.xPoints), at: 12)
            records[controlIndex].payload.hwpWriterSetUInt32(width, at: 16)
            records[controlIndex].payload.hwpWriterSetUInt32(height, at: 20)
            records[controlIndex].payload.hwpWriterSetUInt32(UInt32(bitPattern: Int32(layout.zOrder)), at: 24)
            try updatePlacement(&records[controlIndex].payload, layout: layout)
            guard let component = records.indices[controlIndex..<end].first(where: { records[$0].tag == 0x4C }),
                  records[component].payload.count >= 46 else { throw HWPDocumentEditingError.unsupportedEdit }
            let componentShift = try shapeComponentHeaderShift(records[component].payload)
            guard records[component].payload.count >= 46 + componentShift else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            for offset in [16, 24] { records[component].payload.hwpWriterSetUInt32(width, at: offset + componentShift) }
            for offset in [20, 28] { records[component].payload.hwpWriterSetUInt32(height, at: offset + componentShift) }
            records[component].payload.hwpWriterSetUInt32(width / 2, at: 38 + componentShift)
            records[component].payload.hwpWriterSetUInt32(height / 2, at: 42 + componentShift)
            if let kind = target.kind, let geometryIndex {
                records[component].payload = try styledComponent(records[component].payload,
                    width: width, height: height, rotationDegrees: layout.rotationDegrees,
                    flipHorizontal: layout.flipHorizontal, flipVertical: layout.flipVertical,
                    strokeColorRGB: layout.strokeColorRGB, strokeWidthPoints: layout.strokeWidthPoints,
                    strokeStyle: layout.strokeStyle, fillColorRGB: layout.fillColorRGB, shadow: layout.shadow,
                    startArrow: layout.startArrow, endArrow: layout.endArrow)
                let geometry = geometryRecord(kind, width: width, height: height,
                    path: layout.pathPoints)
                records[geometryIndex] = Record(tag: geometry.tag,
                    level: records[geometryIndex].level, payload: geometry.payload)
            } else {
                let flipFlags: UInt32 = (layout.flipHorizontal ? 1 : 0)
                    | (layout.flipVertical ? 2 : 0)
                records[component].payload.hwpWriterSetUInt32(flipFlags,
                    at: 32 + componentShift)
                records[component].payload.hwpWriterSetUInt16(UInt16(layout.rotationDegrees.rounded()),
                    at: 36 + componentShift)
            }
        case .delete:
            if let childIndex = target.groupChildIndex,
               case .group(let shapes) = owner.canvasObjects[objectIndex].content {
                let bundles = try hwpGroupChildBundles(records: records, controlIndex: controlIndex,
                    controlEnd: end, expectedCount: shapes.count)
                guard bundles.indices.contains(childIndex), shapes.count > 1,
                      let groupComponent = records.indices[controlIndex..<bundles[0].lowerBound]
                        .last(where: { records[$0].tag == 0x4C }) else {
                    throw HWPDocumentEditingError.unsupportedEdit
                }
                if shapes.count == 2 {
                    let remainingIndex = childIndex == 0 ? 1 : 0
                    guard let outerTarget = HWPShapeEditing.target(owner: owner,
                        object: owner.canvasObjects[objectIndex]) else {
                        throw HWPDocumentEditingError.unsupportedEdit
                    }
                    let replacements = try ungroupedHWPRecords(records: records,
                        controlIndex: controlIndex, bundles: [bundles[remainingIndex]],
                        shapes: [shapes[remainingIndex]], target: outerTarget,
                        originalBoundsShapes: shapes)
                    records.replaceSubrange(controlIndex..<end, with: replacements)
                    return try container.serialized(replacing: [path: encoded(records,
                        compressed: compressed)])
                }
                let members = try hwpGroupMemberIDs(records[groupComponent].payload,
                    expectedCount: shapes.count)
                var ids = members.ids
                ids.remove(at: childIndex)
                records[groupComponent].payload = hwpGroupPayload(records[groupComponent].payload,
                    memberStart: members.start, ids: ids, suffix: members.suffix)
                records.removeSubrange(bundles[childIndex])
                return try container.serialized(replacing: [path: encoded(records, compressed: compressed)])
            }
            try removeAnchorAndControl(records: &records, ownerRecord: ownerRecord, ownerEnd: ownerEnd,
                controls: controls, objectIndex: objectIndex, controlIndex: controlIndex, controlEnd: end)
        }
        return try container.serialized(replacing: [path: encoded(records, compressed: compressed)])
    }

    private static func hwpGroupChildBundles(records: [Record], controlIndex: Int,
                                             controlEnd: Int, expectedCount: Int) throws -> [Range<Int>] {
        let geometries = records.indices[controlIndex..<controlEnd].filter {
            [0x4E, 0x4F, 0x50, 0x52, 0x53].contains(records[$0].tag)
        }
        guard geometries.count == expectedCount else { throw HWPDocumentEditingError.unsupportedEdit }
        let components = try geometries.map { geometry -> Int in
            guard let component = records.indices[controlIndex...geometry].last(where: {
                records[$0].tag == 0x4C && records[$0].level + 1 == records[geometry].level
            }) else { throw HWPDocumentEditingError.unsupportedEdit }
            return component
        }
        guard Set(components).count == expectedCount else { throw HWPDocumentEditingError.unsupportedEdit }
        return components.enumerated().map { index, start in
            start..<(index + 1 < components.count ? components[index + 1] : controlEnd)
        }
    }

    private static func hwpGroupMemberIDs(_ payload: Data, expectedCount: Int) throws
        -> (start: Int, ids: [Data], suffix: Data) {
        let minimum = max(payload.count - 2 - expectedCount * 4 - 8, 0)
        let maximum = payload.count - 2 - expectedCount * 4
        guard maximum >= minimum,
              let start = stride(from: maximum, through: minimum, by: -2).first(where: {
                  (try? payload.hwpWriterUInt16(at: $0)) == UInt16(expectedCount)
              }) else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        let ids = (0..<expectedCount).map { index in
            payload.subdata(in: start + 2 + index * 4..<start + 6 + index * 4)
        }
        let suffixStart = start + 2 + expectedCount * 4
        return (start, ids, payload.subdata(in: suffixStart..<payload.count))
    }

    private static func hwpGroupPayload(_ payload: Data, memberStart: Int, ids: [Data],
                                        suffix: Data) -> Data {
        var result = Data(payload.prefix(memberStart))
        result.hwpWriterAppendUInt16(UInt16(ids.count))
        ids.forEach { result.append($0) }
        result.append(suffix)
        return result
    }

    private static func ungroupedHWPRecords(records: [Record], controlIndex: Int,
                                            bundles: [Range<Int>], shapes: [HWPDocumentShape],
                                            target: HWPShapeEditing.Target,
                                            originalBoundsShapes: [HWPDocumentShape]? = nil) throws -> [Record] {
        let frames = shapes.compactMap(\.localFrame)
        let boundsFrames = (originalBoundsShapes ?? shapes).compactMap(\.localFrame)
        guard frames.count == shapes.count, let first = frames.first,
              boundsFrames.count == (originalBoundsShapes ?? shapes).count,
              records[controlIndex].payload.count >= 40 else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        let bounds = boundsFrames.dropFirst().reduce(boundsFrames.first ?? first) { $0.union($1) }
        guard bounds.width > 0, bounds.height > 0 else { throw HWPDocumentEditingError.unsupportedEdit }
        let scaleX = target.widthPoints / Double(bounds.width)
        let scaleY = target.heightPoints / Double(bounds.height)
        var nextInstance: UInt32 = 1
        for record in records where record.tag == 0x47 && record.payload.count >= 40 {
            nextInstance = max(nextInstance, try record.payload.hwpWriterUInt32(at: 36) &+ 1)
        }
        var result: [Record] = []
        for index in shapes.indices {
            let frame = frames[index]
            let width = raw(Double(frame.width) * scaleX)
            let height = raw(Double(frame.height) * scaleY)
            let x = raw(target.xPoints + (Double(frame.minX) - Double(bounds.minX)) * scaleX)
            let y = raw(target.yPoints + (Double(frame.minY) - Double(bounds.minY)) * scaleY)
            var control = records[controlIndex].payload
            control.hwpWriterSetUInt32(y, at: 8)
            control.hwpWriterSetUInt32(x, at: 12)
            control.hwpWriterSetUInt32(width, at: 16)
            control.hwpWriterSetUInt32(height, at: 20)
            control.hwpWriterSetUInt32(UInt32(bitPattern: Int32(target.zOrder + index)), at: 24)
            control.hwpWriterSetUInt32(nextInstance &+ UInt32(index), at: 36)
            result.append(.init(tag: 0x47,
                level: records[controlIndex].level, payload: control))
            for (bundleOffset, sourceIndex) in bundles[index].enumerated() {
                var payload = records[sourceIndex].payload
                if bundleOffset == 0, records[sourceIndex].tag == 0x4C {
                    let shift = try shapeComponentHeaderShift(payload)
                    guard payload.count >= 46 + shift else {
                        throw HWPDocumentEditingError.unsupportedEdit
                    }
                    payload.hwpWriterSetUInt32(0, at: 4 + shift)
                    payload.hwpWriterSetUInt32(0, at: 8 + shift)
                    for offset in [16, 24] { payload.hwpWriterSetUInt32(width, at: offset + shift) }
                    for offset in [20, 28] { payload.hwpWriterSetUInt32(height, at: offset + shift) }
                    let rotation = (target.rotationDegrees + shapes[index].rotationDegrees)
                        .truncatingRemainder(dividingBy: 360)
                    payload.hwpWriterSetUInt16(UInt16(rotation.rounded()), at: 36 + shift)
                    payload.hwpWriterSetUInt32(width / 2, at: 38 + shift)
                    payload.hwpWriterSetUInt32(height / 2, at: 42 + shift)
                }
                result.append(.init(tag: records[sourceIndex].tag,
                    level: max(records[sourceIndex].level - 1,
                        records[controlIndex].level + 1), payload: payload))
            }
        }
        return result
    }

    private static func addObjectAnchors(records: inout [Record], ownerRecord: Int, ownerEnd: Int,
                                         identifier: UInt32, count: Int) throws {
        guard count > 0 else { return }
        try addObjectAnchors(records: &records, ownerRecord: ownerRecord, ownerEnd: ownerEnd,
            identifiers: Array(repeating: identifier, count: count))
    }

    private static func addObjectAnchors(records: inout [Record], ownerRecord: Int, ownerEnd: Int,
                                         identifiers: [UInt32]) throws {
        guard !identifiers.isEmpty else { return }
        let childLevel = records[ownerRecord].level + 1
        let direct = (ownerRecord + 1..<ownerEnd).filter {
            records[$0].level == childLevel
        }
        guard let textIndex = direct.first(where: { records[$0].tag == 0x43 }),
              records[ownerRecord].payload.count >= 22 else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        var anchors = Data()
        for identifier in identifiers {
            anchors.hwpWriterAppendUInt16(11)
            anchors.hwpWriterAppendUInt32(identifier)
            anchors.append(Data(repeating: 0, count: 8))
            anchors.hwpWriterAppendUInt16(11)
        }
        var bytes = records[textIndex].payload
        let insertion = max(bytes.count - 2, 0)
        bytes.insert(contentsOf: anchors, at: insertion)
        records[textIndex].payload = bytes
        let last = try records[ownerRecord].payload.hwpWriterUInt32(at: 0) & 0x8000_0000
        records[ownerRecord].payload.hwpWriterSetUInt32(last | UInt32(bytes.count / 2), at: 0)
        records[ownerRecord].payload.hwpWriterSetUInt32(
            try records[ownerRecord].payload.hwpWriterUInt32(at: 4) | (1 << 11), at: 4)
    }

    private static func updatePlacement(_ payload: inout Data, layout: HWPShapeEditing.Layout) throws {
        guard payload.count >= 36 else { throw HWPDocumentEditingError.unsupportedEdit }
        var property = try payload.hwpWriterUInt32(at: 4)
        let mask: UInt32 = 1 | (0x3 << 3) | (0x7 << 5) | (0x3 << 8) | (0x7 << 10) | (0x7 << 21)
        property &= ~mask
        if layout.isInline { property |= 1 }
        func horizontal(_ value: HWPDocumentLayoutReference) -> UInt32 {
            switch value { case .paper: 0; case .page: 1; case .column: 2; default: 3 }
        }
        func vertical(_ value: HWPDocumentLayoutReference) -> UInt32 {
            switch value { case .paper: 0; case .page: 1; default: 2 }
        }
        func wrap(_ value: HWPDocumentObjectWrap) -> UInt32 {
            switch value { case .topAndBottom: 1; case .behindText: 2; case .inFrontOfText: 3; default: 0 }
        }
        property |= vertical(layout.verticalReference) << 3
        property |= UInt32(layout.verticalAlignment.rawValue & 0x7) << 5
        property |= horizontal(layout.horizontalReference) << 8
        property |= UInt32(layout.horizontalAlignment.rawValue & 0x7) << 10
        property |= wrap(layout.wrap) << 21
        payload.hwpWriterSetUInt32(property, at: 4)
        for (offset, value) in zip([28, 30, 32, 34], [layout.marginLeftPoints,
                layout.marginRightPoints, layout.marginTopPoints, layout.marginBottomPoints]) {
            payload.hwpWriterSetUInt16(UInt16((value * 100).rounded()), at: offset)
        }
    }

    private static func styledComponent(_ source: Data, width: UInt32, height: UInt32,
                                        rotationDegrees: Double,
                                        flipHorizontal: Bool, flipVertical: Bool,
                                        strokeColorRGB: UInt32,
                                        strokeWidthPoints: Double, strokeStyle: Int,
                                        fillColorRGB: UInt32?, shadow: HWPShapeEditing.Shadow?,
                                        startArrow: Int = 0, endArrow: Int = 0) throws -> Data {
        guard source.count >= 46 else { throw HWPDocumentEditingError.unsupportedEdit }
        var base = source
        let shift = try shapeComponentHeaderShift(base)
        let headerLength = 46 + shift
        guard base.count >= headerLength else { throw HWPDocumentEditingError.unsupportedEdit }
        let flipFlags: UInt32 = (flipHorizontal ? 1 : 0) | (flipVertical ? 2 : 0)
        base.hwpWriterSetUInt32(flipFlags, at: 32 + shift)
        base.hwpWriterSetUInt16(UInt16(rotationDegrees.rounded()), at: 36 + shift)
        base.hwpWriterSetUInt32(width / 2, at: 38 + shift)
        base.hwpWriterSetUInt32(height / 2, at: 42 + shift)
        let lineStart: Int
        if base.count == headerLength {
            base.hwpWriterAppendUInt16(0)
            base.append(Data(repeating: 0, count: 48))
            lineStart = 96 + shift
        } else {
            guard base.count >= headerLength + 2 else { throw HWPDocumentEditingError.unsupportedEdit }
            let matrixCount = Int(try base.hwpWriterUInt16(at: 46 + shift))
            lineStart = 96 + shift + matrixCount * 96
            guard lineStart <= base.count else { throw HWPDocumentEditingError.unsupportedEdit }
            base = Data(base.prefix(lineStart))
        }
        base.hwpWriterAppendUInt32(colorReference(strokeColorRGB))
        base.hwpWriterAppendUInt32(raw(strokeWidthPoints))
        let lineProperty = UInt32(strokeStyle & 0x3F)
            | UInt32(startArrow & 0x3F) << 10 | UInt32(endArrow & 0x3F) << 16
        base.hwpWriterAppendUInt32(lineProperty)
        base.append(0)
        if let fillColorRGB {
            base.hwpWriterAppendUInt32(1)
            base.hwpWriterAppendUInt32(colorReference(fillColorRGB))
            base.hwpWriterAppendUInt32(colorReference(fillColorRGB))
            base.hwpWriterAppendUInt32(0)
            base.hwpWriterAppendUInt32(0)
            base.append(0)
        } else {
            base.hwpWriterAppendUInt32(0)
            base.hwpWriterAppendUInt32(0)
        }
        base.hwpWriterAppendUInt32(shadow == nil ? 0 : 4)
        base.hwpWriterAppendUInt32(colorReference(shadow?.colorRGB ?? 0))
        base.hwpWriterAppendUInt32(raw(shadow?.offsetX ?? 0))
        base.hwpWriterAppendUInt32(raw(shadow?.offsetY ?? 0))
        base.hwpWriterAppendUInt32(0)
        base.append(0)
        base.append(UInt8(((1 - (shadow?.opacity ?? 1)) * 255).rounded()))
        return base
    }

    private static func shapeComponentHeaderShift(_ payload: Data) throws -> Int {
        guard payload.count >= 8 else { throw HWPDocumentEditingError.unsupportedEdit }
        return try payload.hwpWriterUInt32(at: 0) == payload.hwpWriterUInt32(at: 4) ? 4 : 0
    }

    private static func removeAnchorAndControl(records: inout [Record], ownerRecord: Int, ownerEnd: Int,
                                               controls: [Int], objectIndex: Int,
                                               controlIndex: Int, controlEnd: Int) throws {
        let childLevel = records[ownerRecord].level + 1
        let direct = (ownerRecord + 1..<ownerEnd).filter {
            records[$0].level == childLevel
        }
        guard let textIndex = direct.first(where: { records[$0].tag == 0x43 }),
              records[ownerRecord].payload.count >= 22 else { throw HWPDocumentEditingError.unsupportedEdit }
        var bytes = records[textIndex].payload
        let identifier = try records[controlIndex].payload.hwpWriterUInt32(at: 0)
        let sameBefore = controls.prefix(objectIndex).filter {
            (try? records[$0].payload.hwpWriterUInt32(at: 0)) == identifier
        }.count
        var cursor = 0, matching = 0, anchor: Int?
        while cursor < bytes.count / 2 {
            let code = try bytes.hwpWriterUInt16(at: cursor * 2)
            let size = code >= 1 && code <= 23 && code != 10 && code != 13 ? 8 : 1
            guard cursor + size <= bytes.count / 2 else { throw HWPDocumentEditingError.invalidDocument }
            if code == 11, try bytes.hwpWriterUInt32(at: cursor * 2 + 2) == identifier {
                if matching == sameBefore { anchor = cursor; break }
                matching += 1
            }
            cursor += size
        }
        guard let anchor else { throw HWPDocumentEditingError.unsupportedEdit }
        bytes.removeSubrange(anchor * 2..<(anchor + 8) * 2)
        records[textIndex].payload = bytes
        let last = try records[ownerRecord].payload.hwpWriterUInt32(at: 0) & 0x8000_0000
        records[ownerRecord].payload.hwpWriterSetUInt32(last | UInt32(bytes.count / 2), at: 0)
        var mask: UInt32 = 0, position = 0
        while position < bytes.count / 2 {
            let code = try bytes.hwpWriterUInt16(at: position * 2)
            let size = code >= 1 && code <= 23 && code != 10 && code != 13 ? 8 : 1
            if code > 0 && code < 32 && code != 13 { mask |= 1 << UInt32(code) }
            position += size
        }
        records[ownerRecord].payload.hwpWriterSetUInt32(mask, at: 4)
        func mapped(_ value: UInt32) -> UInt32 {
            value <= UInt32(anchor) ? value : value < UInt32(anchor + 8) ? UInt32(anchor) : value - 8
        }
        for index in direct where records[index].tag == 0x44 || records[index].tag == 0x45 {
            let stride = records[index].tag == 0x44 ? 8 : 36
            guard records[index].payload.count.isMultiple(of: stride) else { throw HWPDocumentEditingError.invalidDocument }
            var entries: [Data] = []
            for offset in Swift.stride(from: 0, to: records[index].payload.count, by: stride) {
                var entry = records[index].payload.subdata(in: offset..<(offset + stride))
                entry.hwpWriterSetUInt32(mapped(try entry.hwpWriterUInt32(at: 0)), at: 0)
                if records[index].tag == 0x44, let old = entries.last,
                   try old.hwpWriterUInt32(at: 0) == entry.hwpWriterUInt32(at: 0) { entries.removeLast() }
                entries.append(entry)
            }
            records[index].payload = entries.reduce(into: Data()) { $0.append($1) }
            records[ownerRecord].payload.hwpWriterSetUInt16(UInt16(entries.count), at: stride == 8 ? 12 : 16)
        }
        records.removeSubrange(controlIndex..<controlEnd)
    }
}
