import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public nonisolated enum HWPInlineParagraphGeometry {
    public static func sourceID(_ id: String) -> String {
        ["-table-row-continuation-normalized", "-table-content-page-fragment-", "-table-page-fragment-", "-page-fragment-"]
            .reduce(id) { $0.components(separatedBy: $1)[0] }
    }
    public static func rawLength(_ text: String) -> Int { text.utf16.count + text.filter { $0 == "\t" }.count * 7 }

    public static func textOffset(in text: String, raw: Int) -> Int {
        var rawPosition = 0, position = 0
        for unit in text.utf16 {
            if rawPosition >= raw { break }
            rawPosition += unit == 9 ? 8 : 1
            position += 1
        }
        return position
    }

    public static func surfaceID(for block: HWPDocumentBlock, caret: Int) -> String {
        var page = 0, selectedPage = 0
        var previousY = block.lineLayouts.first?.verticalPositionPoints ?? 0
        for (index, line) in block.lineLayouts.enumerated() {
            if index > 0, line.startsPage || line.verticalPositionPoints + 0.5 < previousY { page += 1 }
            if textOffset(in: block.text, raw: line.startCharacter) <= caret { selectedPage = page }
            previousY = line.verticalPositionPoints
        }
        return page > 0 && selectedPage > 0 ? "\(block.id)-page-fragment-\(selectedPage)" : block.id
    }

    public static func rect(block: HWPDocumentBlock, width: Double, fallbackY: Double) -> CGRect {
        let lines = block.lineLayouts
        let left = lines.map { max(0, $0.columnStartPoints) + $0.textInsetPoints }.min()
            ?? max(0, block.presentation.leftMarginPoints)
        let top = lines.map(\.verticalPositionPoints).min() ?? fallbackY
        let right = lines.map { max(0, $0.columnStartPoints) + $0.widthPoints }.max() ?? width
        let size = block.presentation.textRuns.compactMap(\.fontSizePoints).max() ?? 12
        let bottom = lines.map {
            $0.verticalPositionPoints + max($0.lineHeightPoints, $0.textHeightPoints, size, 16)
        }.max() ?? (top + size * 1.5)
        return CGRect(x: left, y: max(0, top), width: max(1, min(width, right) - left),
                      height: max(16, bottom - top))
    }
}
