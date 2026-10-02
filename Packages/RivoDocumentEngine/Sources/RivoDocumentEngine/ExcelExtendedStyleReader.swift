import Foundation

public nonisolated enum ExcelExtendedStyleReader {
    public static func applying(_ data: Data, to styles: [ExcelCellStyle]) throws -> [ExcelCellStyle] {
        let root = try ExcelEditingXML.parse(data)
        let fonts = root.child("fonts")?.elements("font") ?? []
        let borders = root.child("borders")?.elements("border") ?? []
        let xfs = root.child("cellXfs")?.elements("xf") ?? []
        return styles.enumerated().map { index, original in
            guard xfs.indices.contains(index) else { return original }
            var style = original
            let xf = xfs[index]
            let fontIndex = Int(xf.attributes["fontId"] ?? "") ?? 0
            if fonts.indices.contains(fontIndex) {
                let font = fonts[fontIndex]
                style.fontName = font.child("name")?.attributes["val"]
                style.fontSize = font.child("sz")?.attributes["val"].flatMap(Double.init)
                style.fontARGB = font.child("color")?.attributes["rgb"]
                style.isItalic = font.child("i").map { $0.attributes["val"] != "0" } ?? false
                style.isUnderlined = font.child("u").map { $0.attributes["val"] != "none" } ?? false
            }
            style.wrapText = xf.child("alignment")?.attributes["wrapText"] == "1"
            style.verticalAlignment = xf.child("alignment")?.attributes["vertical"]
            let borderIndex = Int(xf.attributes["borderId"] ?? "") ?? 0
            if borders.indices.contains(borderIndex) {
                for edge in borders[borderIndex].children where ["top", "bottom", "left", "right"].contains(edge.localName) && edge.attributes["style"] != nil && edge.attributes["style"] != "none" {
                    style.borderEdges[edge.localName] = edge.child("color")?.attributes["rgb"] ?? "FF808080"
                }
            }
            return style
        }
    }
}
