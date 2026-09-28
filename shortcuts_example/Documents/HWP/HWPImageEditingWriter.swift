import Foundation
import CoreGraphics

nonisolated enum HWPImageEditingWriter {
    typealias Record = HWP5DocumentRewriter.Record

    static func insert(_ request: HWPImageEditing.Request, into source: HWPTableStructureDocument,
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

    static func apply(_ action: HWPImageEditing.Action, target: HWPImageEditing.Target,
                      to source: HWPTableStructureDocument, ownerIndex: Int) throws -> Data {
        guard source.blocks.indices.contains(ownerIndex), source.blocks[ownerIndex].id == target.ownerID else {
            throw HWPDocumentEditingError.staleDocument
        }
        switch source {
        case .hwpx(let package): return try editHWPX(action, target: target, package: package, owner: source.blocks[ownerIndex])
        case .hwp(_, let data): return try editHWP(action, target: target, data: data, owner: source.blocks[ownerIndex])
        }
    }

    private static func unit(_ value: Double) -> String { String(Int((value * 100).rounded())) }
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
        case .topAndBottom: "TOP_AND_BOTTOM"
        case .behindText: "BEHIND_TEXT"
        case .inFrontOfText: "IN_FRONT_OF_TEXT"
        case .tight: "TIGHT"
        case .through: "THROUGH"
        default: "SQUARE"
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

    private static func insertHWPX(_ request: HWPImageEditing.Request, package: HWPXDocumentPackage,
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
        let archive = try HWPXEditingArchive(data: package.sourceData)
        guard archive.contains("Contents/content.hpf") else { throw HWPDocumentEditingError.unsupportedEdit }
        var packageXML = String(decoding: try archive.data(at: "Contents/content.hpf"), as: UTF8.self)
        let existingItems = try HWPFormattingXML.elements(packageXML, name: "item")
        var number = 1
        let identifiers = Set(try existingItems.compactMap { try HWPFormattingXML.attribute($0.xml, "id") })
        while identifiers.contains("image\(number)") || archive.contains("BinData/image\(number).\(request.image.fileExtension)") {
            number += 1
            guard number < 100_000 else { throw HWPDocumentEditingError.limitExceeded }
        }
        let identifier = "image\(number)"
        let assetPath = "BinData/\(identifier).\(request.image.fileExtension)"
        guard let manifest = try HWPFormattingXML.elements(packageXML, name: "manifest").first else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        let manifestPrefix = try HWPFormattingXML.prefix(manifest.xml)
        let item = "<\(manifestPrefix)item id=\"\(identifier)\" href=\"../\(assetPath)\" media-type=\"\(request.image.mediaType)\"/>"
        let updatedManifest = try HWPFormattingXML.append(item, to: manifest.xml)
        packageXML = (packageXML as NSString).replacingCharacters(in: manifest.range, with: updatedManifest)

        let objectID = try nextObjectID(package)
        let width = unit(request.widthPoints), height = unit(request.heightPoints)
        let pic = "<\(prefix)pic id=\"\(objectID)\" zOrder=\"0\" numberingType=\"PICTURE\" textWrap=\"TOP_AND_BOTTOM\" textFlow=\"BOTH_SIDES\" lock=\"0\" dropcapstyle=\"None\"><\(prefix)sz width=\"\(width)\" widthRelTo=\"ABSOLUTE\" height=\"\(height)\" heightRelTo=\"ABSOLUTE\" protect=\"0\"/><\(prefix)pos treatAsChar=\"1\" affectLSpacing=\"0\" flowWithText=\"1\" allowOverlap=\"0\" holdAnchorAndSO=\"0\" vertRelTo=\"PARA\" horzRelTo=\"PARA\" vertAlign=\"TOP\" horzAlign=\"LEFT\" vertOffset=\"0\" horzOffset=\"0\"/><\(prefix)outMargin left=\"0\" right=\"0\" top=\"0\" bottom=\"0\"/><\(prefix)img binaryItemIDRef=\"\(identifier)\" bright=\"0\" contrast=\"0\" effect=\"REAL_PIC\" alpha=\"0\"/><\(prefix)imgClip left=\"0\" top=\"0\" right=\"\(request.image.pixelWidth)\" bottom=\"\(request.image.pixelHeight)\"/><\(prefix)imgDim dimwidth=\"\(request.image.pixelWidth)\" dimheight=\"\(request.image.pixelHeight)\"/><\(prefix)shapeComment>VisionCraft 그림</\(prefix)shapeComment></\(prefix)pic>"
        let updatedParagraph: String
        if owner.tableLocation != nil {
            updatedParagraph = try HWPObjectInsertionSupport.insertingXMLObject(pic,
                caret: request.selection.caret, owner: owner, paragraph: paragraph)
        } else {
            let updatedRun = try HWPFormattingXML.append(pic, to: run.xml)
            updatedParagraph = (paragraph as NSString).replacingCharacters(in: run.range,
                with: updatedRun)
        }
        let sectionXML = (section.xml as NSString).replacingCharacters(in: ranges[paragraphIndex], with: updatedParagraph)
        var replacements = [section.path: Data(sectionXML.utf8), "Contents/content.hpf": Data(packageXML.utf8),
                            assetPath: request.image.data]
        if archive.contains("META-INF/manifest.xml") {
            var xml = String(decoding: try archive.data(at: "META-INF/manifest.xml"), as: UTF8.self)
            if let root = try HWPFormattingXML.elements(xml, name: "manifest").first {
                let childPrefix = (try HWPXParagraphXMLPatcher.tagTokens(in: root.xml).first(where: { $0.localName == "file-entry" }))
                    .map { $0.qualifiedName.contains(":") ? String($0.qualifiedName.prefix { $0 != ":" }) + ":" : "" } ?? ""
                let entry = "<\(childPrefix)file-entry full-path=\"\(assetPath)\" media-type=\"\(request.image.mediaType)\"/>"
                let changed = try HWPFormattingXML.append(entry, to: root.xml)
                xml = (xml as NSString).replacingCharacters(in: root.range, with: changed)
                replacements["META-INF/manifest.xml"] = Data(xml.utf8)
            }
        }
        return try archive.repack(replacing: replacements)
    }

    private static func editHWPX(_ action: HWPImageEditing.Action, target: HWPImageEditing.Target,
                                 package: HWPXDocumentPackage, owner: HWPDocumentBlock) throws -> Data {
        guard let section = package.sections.first(where: { $0.path == owner.sectionPath }),
              let paragraphIndex = section.blocks.firstIndex(where: { $0.id == owner.id }),
              let objectIndex = owner.canvasObjects.firstIndex(where: { $0.id == target.objectID }) else {
            throw HWPDocumentEditingError.staleDocument
        }
        let pictureIndex = owner.canvasObjects[..<objectIndex].reduce(0) { count, object in
            if case .image = object.content { return count + 1 }; return count
        }
        let ranges = try HWPXParagraphXMLPatcher.paragraphRanges(in: section.xml)
        guard ranges.indices.contains(paragraphIndex) else { throw HWPDocumentEditingError.staleDocument }
        let paragraph = (section.xml as NSString).substring(with: ranges[paragraphIndex])
        let pictures = try HWPFormattingXML.elements(paragraph, name: "pic")
        guard pictures.indices.contains(pictureIndex) else { throw HWPDocumentEditingError.staleDocument }
        let picture = pictures[pictureIndex]
        let replacement: String
        switch action {
        case .delete:
            replacement = ""
        case .resize(let dimensions), .crop(_, let dimensions), .update(_, let dimensions, _, _):
            guard dimensions.isValid else { throw HWPDocumentEditingError.limitExceeded }
            let prefix = try HWPFormattingXML.prefix(picture.xml)
            var size = try HWPFormattingXML.elements(picture.xml, name: "sz").first?.xml ?? "<\(prefix)sz/>"
            size = try HWPFormattingXML.setAttribute(size, "width", unit(dimensions.widthPoints))
            size = try HWPFormattingXML.setAttribute(size, "height", unit(dimensions.heightPoints))
            var changed = try HWPFormattingXML.replaceOrAppend(picture.xml, name: "sz", replacement: size)
            let crop: HWPImageEditing.Crop? = switch action {
            case .crop(let value, _), .update(let value, _, _, _): value
            default: nil
            }
            if let crop {
                let dimension = try HWPFormattingXML.elements(changed, name: "imgdim").first
                let width = try dimension.flatMap { try HWPFormattingXML.attribute($0.xml, "dimwidth") }
                    .flatMap(Double.init) ?? Double(target.sourcePixelWidth)
                let height = try dimension.flatMap { try HWPFormattingXML.attribute($0.xml, "dimheight") }
                    .flatMap(Double.init) ?? Double(target.sourcePixelHeight)
                guard width > 0, height > 0 else { throw HWPDocumentEditingError.unsupportedEdit }
                var clip = try HWPFormattingXML.elements(changed, name: "imgclip").first?.xml
                    ?? "<\(prefix)imgClip/>"
                clip = try HWPFormattingXML.setAttribute(clip, "left", String(Int((crop.rect.minX * width).rounded())))
                clip = try HWPFormattingXML.setAttribute(clip, "top", String(Int((crop.rect.minY * height).rounded())))
                clip = try HWPFormattingXML.setAttribute(clip, "right", String(Int((crop.rect.maxX * width).rounded())))
                clip = try HWPFormattingXML.setAttribute(clip, "bottom", String(Int((crop.rect.maxY * height).rounded())))
                changed = try HWPFormattingXML.replaceOrAppend(changed, name: "imgclip", replacement: clip)
                if dimension == nil {
                    let imageDimension = "<\(prefix)imgDim dimwidth=\"\(Int(width))\" dimheight=\"\(Int(height))\"/>"
                    changed = try HWPFormattingXML.replaceOrAppend(changed, name: "imgdim",
                        replacement: imageDimension)
                }
            }
            if case .update(_, _, let presentation, let appearance) = action {
                guard presentation.isValid, appearance.isValid else {
                    throw HWPDocumentEditingError.limitExceeded
                }
                var position = try HWPFormattingXML.elements(changed, name: "pos").first?.xml
                    ?? "<\(prefix)pos/>"
                let previousRawX = Double(try HWPFormattingXML.attribute(position, "horzOffset") ?? "0")
                    .map { $0 / 100 } ?? target.xPoints
                let previousRawY = Double(try HWPFormattingXML.attribute(position, "vertOffset") ?? "0")
                    .map { $0 / 100 } ?? target.yPoints
                let storedX = presentation.isInline
                    ? previousRawX + presentation.xPoints - target.xPoints : presentation.xPoints
                let storedY = presentation.isInline
                    ? previousRawY + presentation.yPoints - target.yPoints : presentation.yPoints
                position = try HWPFormattingXML.setAttribute(position, "horzOffset", unit(storedX))
                position = try HWPFormattingXML.setAttribute(position, "vertOffset", unit(storedY))
                position = try HWPFormattingXML.setAttribute(position, "treatAsChar",
                    presentation.isInline ? "1" : "0")
                position = try HWPFormattingXML.setAttribute(position, "horzRelTo",
                    referenceName(presentation.horizontalReference))
                position = try HWPFormattingXML.setAttribute(position, "vertRelTo",
                    referenceName(presentation.verticalReference))
                position = try HWPFormattingXML.setAttribute(position, "horzAlign",
                    alignmentName(presentation.horizontalAlignment, horizontal: true))
                position = try HWPFormattingXML.setAttribute(position, "vertAlign",
                    alignmentName(presentation.verticalAlignment, horizontal: false))
                changed = try HWPFormattingXML.replaceOrAppend(changed, name: "pos", replacement: position)
                var margin = try HWPFormattingXML.elements(changed, name: "outmargin").first?.xml
                    ?? "<\(prefix)outMargin/>"
                margin = try HWPFormattingXML.setAttribute(margin, "left", unit(presentation.marginLeftPoints))
                margin = try HWPFormattingXML.setAttribute(margin, "right", unit(presentation.marginRightPoints))
                margin = try HWPFormattingXML.setAttribute(margin, "top", unit(presentation.marginTopPoints))
                margin = try HWPFormattingXML.setAttribute(margin, "bottom", unit(presentation.marginBottomPoints))
                changed = try HWPFormattingXML.replaceOrAppend(changed, name: "outmargin", replacement: margin)
                var flip = try HWPFormattingXML.elements(changed, name: "flip").first?.xml
                    ?? "<\(prefix)flip/>"
                flip = try HWPFormattingXML.setAttribute(flip, "horizontal",
                    presentation.flipHorizontal ? "1" : "0")
                flip = try HWPFormattingXML.setAttribute(flip, "vertical",
                    presentation.flipVertical ? "1" : "0")
                changed = try HWPFormattingXML.replaceOrAppend(changed, name: "flip", replacement: flip)
                let rotation = "<\(prefix)rotationInfo angle=\"\(presentation.rotationDegrees)\" centerX=\"\(unit(dimensions.widthPoints / 2))\" centerY=\"\(unit(dimensions.heightPoints / 2))\"/>"
                changed = try HWPFormattingXML.replaceOrAppend(changed, name: "rotationinfo", replacement: rotation)
                changed = try HWPFormattingXML.setAttribute(changed, "textWrap", wrapName(presentation.wrap))
                changed = try HWPFormattingXML.setAttribute(changed, "zOrder", String(presentation.zOrder))
                var image = try HWPFormattingXML.elements(changed, name: "img").first?.xml
                    ?? "<\(prefix)img/>"
                image = try HWPFormattingXML.setAttribute(image, "bright", String(appearance.brightness))
                image = try HWPFormattingXML.setAttribute(image, "contrast", String(appearance.contrast))
                image = try HWPFormattingXML.setAttribute(image, "effect", appearance.effect.hwpXName)
                image = try HWPFormattingXML.setAttribute(image, "alpha",
                    String(Int((Double(appearance.transparencyPercent) * 255 / 100).rounded())))
                changed = try HWPFormattingXML.replaceOrAppend(changed, name: "img", replacement: image)
                let stroke = appearance.borderStroke
                let line = "<\(prefix)lineShape color=\"\(color(stroke?.colorRGB ?? 0))\" width=\"\(unit(stroke?.widthPoints ?? 0.75))\" style=\"\(styleName(stroke?.style ?? 0))\"/>"
                if try HWPFormattingXML.elements(changed, name: "lineshape").isEmpty,
                   let imageElement = try HWPFormattingXML.elements(changed, name: "img").first {
                    changed = (changed as NSString).replacingCharacters(in: imageElement.range,
                        with: line + imageElement.xml)
                } else {
                    changed = try HWPFormattingXML.replaceOrAppend(changed, name: "lineshape", replacement: line)
                }
            }
            replacement = changed
        }
        let updatedParagraph = (paragraph as NSString).replacingCharacters(in: picture.range, with: replacement)
        let sectionXML = (section.xml as NSString).replacingCharacters(in: ranges[paragraphIndex], with: updatedParagraph)
        return try HWPXEditingArchive(data: package.sourceData).repack(replacing: [section.path: Data(sectionXML.utf8)])
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

    private static func insertHWP(_ request: HWPImageEditing.Request, data: Data,
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
        let owned = start..<end
        guard owned.allSatisfy({ [0x42, 0x43, 0x44, 0x45].contains(records[$0].tag) }),
              records[start].payload.count >= 22 else { throw HWPDocumentEditingError.unsupportedEdit }
        var info = try HWP5DocumentRewriter.parseRecords(expanded(container.stream(named: "DocInfo"), compressed: compressed))
        guard let mapping = info.firstIndex(where: { $0.tag == 0x11 }), info[mapping].payload.count >= 4 else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        let descriptors = info.filter { $0.tag == 0x12 }
        guard descriptors.count < Int(UInt16.max) - 1 else { throw HWPDocumentEditingError.limitExceeded }
        let binaryID = descriptors.count + 1
        let maximumStream = try descriptors.compactMap { record -> Int? in
            guard record.payload.count >= 4, (try record.payload.hwpWriterUInt16(at: 0) & 0x0F) != 0 else { return nil }
            return Int(try record.payload.hwpWriterUInt16(at: 2))
        }.max() ?? 0
        guard maximumStream < Int(UInt16.max) else { throw HWPDocumentEditingError.limitExceeded }
        let streamID = maximumStream + 1
        var descriptor = Data(); descriptor.hwpWriterAppendUInt16(0x21); descriptor.hwpWriterAppendUInt16(UInt16(streamID))
        let extensionUnits = Array(request.image.fileExtension.utf16)
        descriptor.hwpWriterAppendUInt16(UInt16(extensionUnits.count))
        for value in extensionUnits { descriptor.hwpWriterAppendUInt16(value) }
        info.insert(.init(tag: 0x12, level: 0, payload: descriptor),
            at: info.firstIndex(where: { $0.tag > 0x12 }) ?? info.endIndex)
        let oldCount = try info[mapping].payload.hwpWriterUInt32(at: 0)
        guard oldCount < UInt32.max else { throw HWPDocumentEditingError.limitExceeded }
        info[mapping].payload.hwpWriterSetUInt32(oldCount + 1, at: 0)

        end = try HWPObjectInsertionSupport.insertAnchor(0x6773_6F20,
            caret: request.selection.caret, records: &records, header: start, end: end)

        let width = UInt32((request.widthPoints * 100).rounded())
        let height = UInt32((request.heightPoints * 100).rounded())
        var nextInstance: UInt32 = 1
        for record in records where record.payload.count >= 40 && record.tag == 0x47 {
            nextInstance = max(nextInstance, try record.payload.hwpWriterUInt32(at: 36) &+ 1)
        }
        var control = Data(repeating: 0, count: 46)
        control.hwpWriterSetUInt32(0x6773_6F20, at: 0)
        control.hwpWriterSetUInt32(1 | (2 << 3) | (3 << 8) | (1 << 21), at: 4)
        control.hwpWriterSetUInt32(width, at: 16); control.hwpWriterSetUInt32(height, at: 20)
        control.hwpWriterSetUInt32(nextInstance, at: 36)
        let comment = Array("VisionCraft 그림".utf16)
        control.hwpWriterSetUInt16(UInt16(comment.count), at: 44)
        for value in comment { control.hwpWriterAppendUInt16(value) }
        var component = Data(repeating: 0, count: 46)
        component.hwpWriterSetUInt32(0x2470_6963, at: 0)
        component.hwpWriterSetUInt16(1, at: 14)
        for offset in [16, 24] { component.hwpWriterSetUInt32(width, at: offset) }
        for offset in [20, 28] { component.hwpWriterSetUInt32(height, at: offset) }
        component.hwpWriterSetUInt32(width / 2, at: 38); component.hwpWriterSetUInt32(height / 2, at: 42)
        let nativeWidth = UInt32(request.image.pixelWidth * 75), nativeHeight = UInt32(request.image.pixelHeight * 75)
        var picture = Data(repeating: 0, count: 78)
        picture.hwpWriterSetUInt32(UInt32.max, at: 0)
        for (offset, value) in [(12, UInt32(0)), (16, UInt32(0)), (20, nativeWidth), (24, UInt32(0)),
                                (28, nativeWidth), (32, nativeHeight), (36, UInt32(0)), (40, nativeHeight),
                                (44, UInt32(0)), (48, UInt32(0)), (52, nativeWidth), (56, nativeHeight)] {
            picture.hwpWriterSetUInt32(value, at: offset)
        }
        picture.hwpWriterSetUInt16(UInt16(binaryID), at: 71)
        picture.hwpWriterSetUInt32(nextInstance, at: 74)
        records.insert(contentsOf: [.init(tag: 0x47, level: childLevel, payload: control),
                                    .init(tag: 0x4C, level: childLevel + 1, payload: component),
                                    .init(tag: 0x55, level: childLevel + 2, payload: picture)], at: end)
        let stream = String(format: "BinData/BIN%04d.%@", streamID, request.image.fileExtension)
        return try container.serialized(replacing: [path: encoded(records, compressed: compressed),
            "DocInfo": encoded(info, compressed: compressed)], adding: [stream: request.image.data])
    }

    private static let objectControlIDs: Set<UInt32> = [
        0x2470_6963, 0x6773_6F20, 0x6571_6564, 0x246C_696E, 0x2472_6563,
        0x2465_6C6C, 0x2461_7263, 0x2470_6F6C, 0x2463_7572, 0x246F_6C65, 0x2463_6F6E
    ]

    private static func editHWP(_ action: HWPImageEditing.Action, target: HWPImageEditing.Target,
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
        guard records[controlIndex..<end].contains(where: { $0.tag == 0x55 }) else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        switch action {
        case .resize(let dimensions), .crop(_, let dimensions), .update(_, let dimensions, _, _):
            guard dimensions.isValid, records[controlIndex].payload.count >= 24 else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            let width = UInt32((dimensions.widthPoints * 100).rounded())
            let height = UInt32((dimensions.heightPoints * 100).rounded())
            records[controlIndex].payload.hwpWriterSetUInt32(width, at: 16)
            records[controlIndex].payload.hwpWriterSetUInt32(height, at: 20)
            guard let component = records.indices[controlIndex..<end].first(where: { records[$0].tag == 0x4C }),
                  records[component].payload.count >= 46 else { throw HWPDocumentEditingError.unsupportedEdit }
            let componentShift = try componentHeaderShift(records[component].payload)
            guard records[component].payload.count >= 46 + componentShift else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            for offset in [16, 24] {
                records[component].payload.hwpWriterSetUInt32(width, at: offset + componentShift)
            }
            for offset in [20, 28] {
                records[component].payload.hwpWriterSetUInt32(height, at: offset + componentShift)
            }
            records[component].payload.hwpWriterSetUInt32(width / 2, at: 38 + componentShift)
            records[component].payload.hwpWriterSetUInt32(height / 2, at: 42 + componentShift)
            let crop: HWPImageEditing.Crop? = switch action {
            case .crop(let value, _), .update(let value, _, _, _): value
            default: nil
            }
            if let crop {
                guard let picture = records.indices[controlIndex..<end].first(where: { records[$0].tag == 0x55 }),
                      records[picture].payload.count >= 60 else {
                    throw HWPDocumentEditingError.unsupportedEdit
                }
                let sourceX = [12, 20, 28, 36].compactMap {
                    try? Int32(bitPattern: records[picture].payload.hwpWriterUInt32(at: $0))
                }
                let sourceY = [16, 24, 32, 40].compactMap {
                    try? Int32(bitPattern: records[picture].payload.hwpWriterUInt32(at: $0))
                }
                guard let minX = sourceX.min(), let maxX = sourceX.max(),
                      let minY = sourceY.min(), let maxY = sourceY.max(),
                      maxX > minX, maxY > minY else {
                    throw HWPDocumentEditingError.unsupportedEdit
                }
                let sourceWidth = Double(maxX - minX), sourceHeight = Double(maxY - minY)
                func coordinate(_ origin: Int32, _ length: Double, _ fraction: Double) -> Int32 {
                    Int32((Double(origin) + length * fraction).rounded())
                }
                records[picture].payload.hwpWriterSetUInt32(UInt32(bitPattern: coordinate(minX, sourceWidth, crop.rect.minX)), at: 44)
                records[picture].payload.hwpWriterSetUInt32(UInt32(bitPattern: coordinate(minY, sourceHeight, crop.rect.minY)), at: 48)
                records[picture].payload.hwpWriterSetUInt32(UInt32(bitPattern: coordinate(minX, sourceWidth, crop.rect.maxX)), at: 52)
                records[picture].payload.hwpWriterSetUInt32(UInt32(bitPattern: coordinate(minY, sourceHeight, crop.rect.maxY)), at: 56)
            }
            if case .update(_, _, let presentation, let appearance) = action {
                guard presentation.isValid, appearance.isValid else {
                    throw HWPDocumentEditingError.limitExceeded
                }
                records[controlIndex].payload.hwpWriterSetUInt32(
                    UInt32(bitPattern: Int32(presentation.zOrder)), at: 24)
                records[controlIndex].payload.hwpWriterSetUInt32(
                    UInt32(bitPattern: Int32((presentation.yPoints * 100).rounded())), at: 8)
                records[controlIndex].payload.hwpWriterSetUInt32(
                    UInt32(bitPattern: Int32((presentation.xPoints * 100).rounded())), at: 12)
                try updatePlacement(&records[controlIndex].payload, presentation: presentation)
                let flipFlags: UInt32 = (presentation.flipHorizontal ? 1 : 0)
                    | (presentation.flipVertical ? 2 : 0)
                records[component].payload.hwpWriterSetUInt32(flipFlags, at: 32 + componentShift)
                records[component].payload.hwpWriterSetUInt16(
                    UInt16(presentation.rotationDegrees.rounded()), at: 36 + componentShift)
                records[component].payload.hwpWriterSetUInt32(width / 2, at: 38 + componentShift)
                records[component].payload.hwpWriterSetUInt32(height / 2, at: 42 + componentShift)
                guard let picture = records.indices[controlIndex..<end].first(where: {
                    records[$0].tag == 0x55
                }), records[picture].payload.count >= 73 else {
                    throw HWPDocumentEditingError.unsupportedEdit
                }
                if records[picture].payload.count < 78 {
                    records[picture].payload.append(Data(repeating: 0,
                        count: 78 - records[picture].payload.count))
                    if records[controlIndex].payload.count >= 40 {
                        records[picture].payload.hwpWriterSetUInt32(
                            try records[controlIndex].payload.hwpWriterUInt32(at: 36), at: 74)
                    }
                }
                if let stroke = appearance.borderStroke {
                    records[picture].payload.hwpWriterSetUInt32(colorReference(stroke.colorRGB), at: 0)
                    records[picture].payload.hwpWriterSetUInt32(
                        UInt32(bitPattern: Int32((stroke.widthPoints * 100).rounded())), at: 4)
                    let oldProperty = try records[picture].payload.hwpWriterUInt32(at: 8)
                    records[picture].payload.hwpWriterSetUInt32(
                        (oldProperty & ~UInt32(0x3F)) | UInt32(stroke.style & 0x3F), at: 8)
                } else {
                    records[picture].payload.hwpWriterSetUInt32(UInt32.max, at: 0)
                    records[picture].payload.hwpWriterSetUInt32(0, at: 4)
                    let oldProperty = try records[picture].payload.hwpWriterUInt32(at: 8)
                    records[picture].payload.hwpWriterSetUInt32(oldProperty & ~UInt32(0x3F), at: 8)
                }
                records[picture].payload[68] = UInt8(bitPattern: Int8(appearance.brightness))
                records[picture].payload[69] = UInt8(bitPattern: Int8(appearance.contrast))
                records[picture].payload[70] = UInt8(appearance.effect.rawValue)
            }
        case .delete:
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
            records.removeSubrange(controlIndex..<end)
        }
        return try container.serialized(replacing: [path: encoded(records, compressed: compressed)])
    }

    private static func componentHeaderShift(_ payload: Data) throws -> Int {
        guard payload.count >= 46 else { throw HWPDocumentEditingError.unsupportedEdit }
        return try payload.hwpWriterUInt32(at: 0) == payload.hwpWriterUInt32(at: 4) ? 4 : 0
    }

    private static func updatePlacement(_ payload: inout Data,
                                        presentation: HWPImageEditing.Presentation) throws {
        guard payload.count >= 36 else { throw HWPDocumentEditingError.unsupportedEdit }
        var property = try payload.hwpWriterUInt32(at: 4)
        let mask: UInt32 = 1 | (0x3 << 3) | (0x7 << 5) | (0x3 << 8) | (0x7 << 10) | (0x7 << 21)
        property &= ~mask
        if presentation.isInline { property |= 1 }
        func horizontal(_ value: HWPDocumentLayoutReference) -> UInt32 {
            switch value { case .paper: 0; case .page: 1; case .column: 2; default: 3 }
        }
        func vertical(_ value: HWPDocumentLayoutReference) -> UInt32 {
            switch value { case .paper: 0; case .page: 1; default: 2 }
        }
        func wrap(_ value: HWPDocumentObjectWrap) -> UInt32 {
            switch value { case .topAndBottom: 1; case .behindText: 2; case .inFrontOfText: 3; default: 0 }
        }
        property |= vertical(presentation.verticalReference) << 3
        property |= UInt32(presentation.verticalAlignment.rawValue & 0x7) << 5
        property |= horizontal(presentation.horizontalReference) << 8
        property |= UInt32(presentation.horizontalAlignment.rawValue & 0x7) << 10
        property |= wrap(presentation.wrap) << 21
        payload.hwpWriterSetUInt32(property, at: 4)
        for (offset, value) in zip([28, 30, 32, 34], [presentation.marginLeftPoints,
                presentation.marginRightPoints, presentation.marginTopPoints,
                presentation.marginBottomPoints]) {
            payload.hwpWriterSetUInt16(UInt16((value * 100).rounded()), at: offset)
        }
    }
}

nonisolated enum HWPObjectInsertionSupport {
    typealias Record = HWP5DocumentRewriter.Record

    static func insertingXMLObject(_ object: String, caret: Int,
                                   owner: HWPDocumentBlock, paragraph: String) throws -> String {
        let marker = "\u{F8FF}\u{F8FC}\u{F8FB}"
        guard !paragraph.contains(marker), caret >= 0,
              caret <= owner.text.utf16.count else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        let marked = (owner.text as NSString).replacingCharacters(
            in: NSRange(location: caret, length: 0), with: marker)
        let edited = HWPTextRunEditing.replacingText(in: owner, with: marked)
        var result = try HWPXParagraphXMLPatcher.apply(originalXML: paragraph,
            originalBlocks: [owner], editedBlocks: [edited])
        guard let markerRange = result.range(of: marker) else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        let prefix = try HWPFormattingXML.prefix(result)
        let insertion = "</\(prefix)t>\(object)<\(prefix)t xml:space=\"preserve\">"
        result = (result as NSString).replacingCharacters(
            in: NSRange(markerRange, in: result), with: insertion)
        return result
    }

    static func insertAnchor(_ identifier: UInt32, caret: Int,
                             records: inout [Record], header: Int, end: Int) throws -> Int {
        let childLevel = records[header].level + 1
        let anchor: [UInt16] = [11, UInt16(identifier & 0xFFFF), UInt16(identifier >> 16),
                                0, 0, 0, 0, 11]
        var paragraphEnd = end
        let textIndex: Int
        if let existing = records.indices[header..<end].first(where: {
            records[$0].tag == 0x43 && records[$0].level == childLevel
        }) {
            textIndex = existing
        } else {
            let count = try records[header].payload.hwpWriterUInt32(at: 0) & 0x7FFF_FFFF
            guard caret == 0, count <= 1 else { throw HWPDocumentEditingError.unsupportedEdit }
            records.insert(.init(tag: 0x43, level: childLevel,
                payload: data(anchor + [13])), at: header + 1)
            paragraphEnd += 1
            try repairOwner(records: &records, header: header, end: paragraphEnd,
                insertedAt: nil)
            return paragraphEnd
        }

        var textUnits = try units(records[textIndex].payload)
        if textUnits.isEmpty { textUnits.append(13) }
        let raw = try rawPosition(textUnits, visible: caret)
        textUnits.insert(contentsOf: anchor, at: raw)
        records[textIndex].payload = data(textUnits)
        try repairOwner(records: &records, header: header, end: paragraphEnd,
            insertedAt: raw)
        return paragraphEnd
    }

    private static func repairOwner(records: inout [Record], header: Int, end: Int,
                                    insertedAt: Int?) throws {
        let childLevel = records[header].level + 1
        guard let text = records.indices[header..<min(end, records.count)].first(where: {
            records[$0].tag == 0x43 && records[$0].level == childLevel
        }) else { throw HWPDocumentEditingError.unsupportedEdit }
        let textUnits = try units(records[text].payload)
        var head = records[header].payload
        let high = try head.hwpWriterUInt32(at: 0) & 0x8000_0000
        head.hwpWriterSetUInt32(high | UInt32(textUnits.count), at: 0)
        var mask: UInt32 = 0
        var cursor = 0
        while cursor < textUnits.count {
            let code = textUnits[cursor]
            let size = controlSize(code)
            guard cursor + size <= textUnits.count else {
                throw HWPDocumentEditingError.invalidDocument
            }
            if code > 0 && code < 32 && code != 13 { mask |= 1 << UInt32(code) }
            cursor += size
        }
        head.hwpWriterSetUInt32(mask, at: 4)

        for index in records.indices[header..<min(end, records.count)]
            where records[index].level == childLevel && records[index].tag == 0x44 {
            guard records[index].payload.count.isMultiple(of: 8) else {
                throw HWPDocumentEditingError.invalidDocument
            }
            var payload = records[index].payload
            if let insertedAt {
                for offset in stride(from: 0, to: payload.count, by: 8) {
                    let position = Int(try payload.hwpWriterUInt32(at: offset))
                    if position > insertedAt {
                        payload.hwpWriterSetUInt32(UInt32(position + 8), at: offset)
                    }
                }
            }
            records[index].payload = payload
            head.hwpWriterSetUInt16(UInt16(payload.count / 8), at: 12)
        }
        for index in records.indices[header..<min(end, records.count)]
            where records[index].level == childLevel && records[index].tag == 0x45 {
            guard records[index].payload.count.isMultiple(of: 36) else {
                throw HWPDocumentEditingError.invalidDocument
            }
            var payload = records[index].payload
            if let insertedAt {
                for offset in stride(from: 0, to: payload.count, by: 36) {
                    let position = Int(try payload.hwpWriterUInt32(at: offset))
                    if position > insertedAt {
                        payload.hwpWriterSetUInt32(UInt32(position + 8), at: offset)
                    }
                }
            }
            records[index].payload = payload
        }
        records[header].payload = head
    }

    private static func rawPosition(_ units: [UInt16], visible target: Int) throws -> Int {
        var raw = 0
        var visible = 0
        while raw < units.count {
            if visible == target { return raw }
            let code = units[raw]
            let size = controlSize(code)
            guard raw + size <= units.count else {
                throw HWPDocumentEditingError.invalidDocument
            }
            if code > 31 || [9, 10, 24, 30, 31].contains(code) { visible += 1 }
            raw += size
        }
        guard visible == target else { throw HWPDocumentEditingError.staleDocument }
        return raw
    }

    private static func controlSize(_ code: UInt16) -> Int {
        (1...23).contains(code) && code != 10 && code != 13 ? 8 : 1
    }

    private static func units(_ payload: Data) throws -> [UInt16] {
        guard payload.count.isMultiple(of: 2) else {
            throw HWPDocumentEditingError.invalidDocument
        }
        return stride(from: 0, to: payload.count, by: 2).map {
            UInt16(payload[$0]) | UInt16(payload[$0 + 1]) << 8
        }
    }

    private static func data(_ units: [UInt16]) -> Data {
        var result = Data()
        for unit in units { result.hwpWriterAppendUInt16(unit) }
        return result
    }
}
