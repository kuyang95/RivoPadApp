import Foundation
import CoreText

nonisolated enum HWPListKind: String, Hashable, Sendable { case bullet, number }

/// A native paragraph heading, never a prefix inserted into the user's text.
nonisolated struct HWPParagraphList: Hashable, Sendable {
    var kind: HWPListKind
    var definitionID: String
    var level = 0
    var format: String
    var start = 1
    var ordinal = 1
    var isSimple = true
    var inheritedMarker: HWPDocumentListMarker?

    func matches(_ other: Self) -> Bool {
        kind == other.kind && level == other.level && format == other.format && start == other.start
    }

    func marker(in block: HWPDocumentBlock) -> HWPDocumentListMarker? {
        if let inheritedMarker { return inheritedMarker }
        guard isSimple else { return nil }
        var run = HWPDocumentFormatting.runs(in: block)[0]
        run.text = kind == .bullet ? format : format.replacingOccurrences(of: "^1", with: String(ordinal))
        run.isUnderlined = false
        run.isStruckThrough = false
        let size = run.fontSizePoints ?? 10
        let font = CTFontCreateWithName((run.fontName ?? "Helvetica") as CFString, size, nil)
        let text = NSAttributedString(string: run.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let width = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text), nil, nil, nil)
        return HWPDocumentListMarker(run: run, reservedWidthPoints: max(size * 1.5, width + size * 0.5))
    }
}

nonisolated enum HWPListFormatting {
    static func supports(_ block: HWPDocumentBlock) -> Bool {
        block.isEditable && block.region.kind == .body && block.layoutContainerID == nil
            && block.images.isEmpty && block.canvasObjects.isEmpty
    }

    static func style(_ kind: HWPListKind, for block: HWPDocumentBlock,
                      in blocks: [HWPDocumentBlock], restart: Bool = false) -> HWPParagraphList {
        if !restart, let index = blocks.firstIndex(where: { $0.id == block.id }), index > 0 {
            let previous = blocks[index - 1]
            if context(previous) == context(block), let list = previous.presentation.list,
               list.kind == kind, list.isSimple, list.level == 0 {
                var next = list
                next.ordinal += 1
                return next
            }
        }
        return HWPParagraphList(kind: kind, definitionID: "new-\(UUID().uuidString)",
            format: kind == .bullet ? "•" : "^1.")
    }

    static func context(_ block: HWPDocumentBlock) -> String {
        let cell = block.tableLocation.map { "\($0.table):\($0.row):\($0.column)" } ?? "body"
        return "\(block.sectionPath):\(block.region.kind.rawValue):\(block.region.ordinal ?? 0):\(block.layoutContainerID ?? cell)"
    }

    /// Counters belong to a definition within a section/cell. Plain paragraphs
    /// do not consume a number; explicit new definitions start a separate list.
    static func renumbering(_ blocks: [HWPDocumentBlock]) -> [HWPDocumentBlock] {
        var counters: [String: Int] = [:]
        return blocks.map { block in
            guard var list = block.presentation.list else { return block }
            if list.kind == .number, list.isSimple {
                let key = "\(context(block)):\(list.definitionID):\(list.level)"
                list.ordinal = (counters[key].map { $0 + 1 }) ?? max(1, list.start)
                counters[key] = list.ordinal
            }
            var style = block.presentation
            style.list = list
            let marker = list.marker(in: block)
            let lines = block.lineLayouts.enumerated().map { index, line in
                var copy = line
                if list.isSimple { copy.listMarker = marker; copy.showsListMarker = index == 0 }
                return copy
            }
            return block.withPresentation(style, lines: lines)
        }
    }
}

extension HWPDocumentBlock {
    nonisolated func withPresentation(_ style: HWPDocumentBlockPresentation,
                                     lines: [HWPDocumentLineLayout]? = nil) -> HWPDocumentBlock {
        HWPDocumentBlock(id: id, sectionPath: sectionPath, paragraphIndex: paragraphIndex,
            text: text, tableLocation: tableLocation, isEditable: isEditable, presentation: style,
            region: region, images: images, lineLayouts: lines ?? lineLayouts,
            canvasObjects: canvasObjects, layoutContainerID: layoutContainerID,
            sourceParagraphID: sourceParagraphID, keepsParagraphBoundary: keepsParagraphBoundary)
    }
}

/// HWP 5.0 NUMBERING records use seven 12-byte heads followed by a UTF-16
/// format for each head, then the starting counters (Hancom format §4.2.8).
nonisolated enum HWPListBinary {
    struct Level { let property: UInt32; let format: String; var start = 1 }
    static func levels(_ data: Data) -> [Level] {
        var result: [Level] = [], offset = 0
        for _ in 0..<7 {
            guard offset + 14 <= data.count,
                  let property = try? data.hwpWriterUInt32(at: offset) else { return [] }
            let length = Int(data[offset + 12]) | Int(data[offset + 13]) << 8
            guard length <= 1_000, offset + 14 + length * 2 <= data.count else { return [] }
            let text = String(data: data.subdata(in: (offset + 14)..<(offset + 14 + length * 2)), encoding: .utf16LittleEndian) ?? ""
            result.append(Level(property: property, format: text))
            offset += 14 + length * 2
        }
        if offset + 2 <= data.count {
            let initial = max(1, Int(data[offset]) | Int(data[offset + 1]) << 8)
            offset += 2
            for index in result.indices {
                result[index].start = initial
                if offset + 4 <= data.count, let start = try? data.hwpWriterUInt32(at: offset) {
                    result[index].start = max(1, min(Int(start), 65_535)); offset += 4
                }
            }
        }
        return result
    }

    static func definition(_ list: HWPParagraphList) throws -> Data {
        guard list.isSimple, list.level == 0, (1...65_535).contains(list.start) else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        var data = Data()
        func head() {
            data.hwpWriterAppendUInt32(12) // instance width + automatic hanging indent
            data.hwpWriterAppendUInt16(0)
            data.hwpWriterAppendUInt16(50) // half a character between marker and text
            data.hwpWriterAppendUInt32(UInt32.max) // inherit paragraph character style
        }
        if list.kind == .bullet {
            guard list.format.utf16.count == 1, let character = list.format.utf16.first else {
                throw HWPDocumentEditingError.unsupportedEdit
            }
            head(); data.hwpWriterAppendUInt16(character)
            data.append(0) // text bullet, not an image
        } else {
            for level in 1...7 {
                head()
                let format = "^\(level)."
                data.hwpWriterAppendUInt16(UInt16(format.utf16.count))
                for unit in format.utf16 { data.hwpWriterAppendUInt16(unit) }
            }
            data.hwpWriterAppendUInt16(UInt16(list.start))
            for _ in 0..<7 { data.hwpWriterAppendUInt32(UInt32(list.start)) }
        }
        return data
    }
}

nonisolated enum HWPListXML {
    static func definition(_ list: HWPParagraphList, id: Int, prefix: String) -> String {
        func head(_ level: Int, text: String) -> String {
            "<\(prefix)paraHead start=\"\(list.start)\" level=\"\(level)\" align=\"LEFT\" useInstWidth=\"1\" autoIndent=\"1\" widthAdjust=\"0\" textOffsetType=\"PERCENT\" textOffset=\"50\" numFormat=\"DIGIT\" charPrIDRef=\"4294967295\" checkable=\"0\">\(text)</\(prefix)paraHead>"
        }
        if list.kind == .number {
            return "<\(prefix)numbering id=\"\(id)\" start=\"\(list.start)\">"
                + (1...7).map { head($0, text: "^\($0).") }.joined() + "</\(prefix)numbering>"
        }
        return "<\(prefix)bullet id=\"\(id)\" char=\"\(HWPFormattingXML.escaped(list.format))\" checkedChar=\"\(HWPFormattingXML.escaped(list.format))\" useImage=\"0\">"
            + head(0, text: "").replacingOccurrences(of: " start=\"\(list.start)\"", with: "") + "</\(prefix)bullet>"
    }

    static func appending(_ definition: String, kind: HWPListKind, to header: String,
                          prefix: String, count: Int) throws -> String {
        let name = kind == .number ? "numberings" : "bullets"
        if !(try HWPFormattingXML.elements(header, name: name)).isEmpty {
            return try HWPFormattingXML.appendToGroup(header, name: name, additions: definition, count: count)
        }
        let xml = "<\(prefix)\(name) itemCnt=\"\(count)\">\(definition)</\(prefix)\(name)>"
        // The OWPML refList orders numberings/bullets before paragraph styles.
        let next = kind == .number ? ["bullets", "paraproperties", "styles"] : ["paraproperties", "styles"]
        for name in next {
            if let anchor = try HWPFormattingXML.elements(header, name: name).first {
                return (header as NSString).replacingCharacters(in: NSRange(location: anchor.range.location, length: 0), with: xml)
            }
        }
        guard let refs = try HWPFormattingXML.elements(header, name: "reflist").first else {
            throw HWPDocumentEditingError.unsupportedEdit
        }
        return (header as NSString).replacingCharacters(in: refs.range, with: try HWPFormattingXML.append(xml, to: refs.xml))
    }
}
