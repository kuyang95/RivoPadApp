import SwiftUI

@main struct ExcelZoomQAApp: App {
    var body: some Scene { WindowGroup { ZoomDocument() } }
}

private struct ZoomDocument: View {
    @State private var zoom: CGFloat = 1
    @State private var selected = "none"
    private let documentSize = CGSize(width: 4_800, height: 17_600)

    var body: some View {
        VStack(spacing: 0) {
            Text(String(format: "%.3f", zoom)).accessibilityIdentifier("zoom-result")
            Text(selected).accessibilityIdentifier("selection-result")
            ExcelZoomScrollView(
                contentSize: documentSize, zoomScale: $zoom, zoomRange: 0.5 ... 3,
                onTap: { point in selected = "R\(Int(point.y / 44))C\(Int(point.x / 120))" }
            ) { rect, scale in
                ZStack(alignment: .topLeading) {
                    ForEach((0 ..< 400).filter { CGFloat($0 + 1) * 44 >= rect.minY && CGFloat($0) * 44 <= rect.maxY }, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0 ..< 40, id: \.self) { column in
                                cell(row: row, column: column, scale: scale)
                            }
                        }
                        .offset(y: CGFloat(row) * 44 * scale)
                    }
                }
                .frame(width: documentSize.width * scale, height: documentSize.height * scale, alignment: .topLeading)
            }
        }
    }

    private func cell(row: Int, column: Int, scale: CGFloat) -> some View {
        let name = "R\(row)C\(column)"
        return Text(name)
            .font(.system(size: 16 * scale))
            .foregroundStyle(.black)
            .frame(width: 120 * scale, height: 44 * scale)
            .background(selected == name ? Color.blue.opacity(0.2) : Color.white)
            .border(.gray, width: 0.5 * scale)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { selected = name }
    }
}
