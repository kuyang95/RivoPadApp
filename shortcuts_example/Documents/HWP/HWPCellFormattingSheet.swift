import SwiftUI

struct HWPCellFormattingSheet: View {
    @State private var format: HWPCellFormat
    @State private var widthMM: Double
    @State private var borderColor: UInt32
    let onApply: (HWPCellFormat) -> Void
    @Environment(\.dismiss) private var dismiss

    init(cell: HWPDocumentTableLocation, onApply: @escaping (HWPCellFormat) -> Void) {
        let value = HWPCellFormat(cell)
        _format = State(initialValue: value)
        let line = cell.boxStyle?.firstVisibleBorder
        _widthMM = State(initialValue: line.map { ($0.widthPoints * 25.4 / 72 * 10_000).rounded() / 10_000 } ?? 0.3)
        _borderColor = State(initialValue: line?.colorRGB ?? 0)
        self.onApply = onApply
    }

    private let colors: [(String, UInt32)] = [
        ("흰색", 0xFFFFFF), ("노랑", 0xFFF2CC), ("초록", 0xE2F0D9), ("파랑", 0xDDEBF7),
        ("분홍", 0xFCE4D6), ("보라", 0xE4DFEC), ("회색", 0xD9D9D9),
        ("검정", 0), ("빨강", 0xCC0000), ("파랑", 0x0066CC)
    ]
    private var line: HWPDocumentBorderLine { .init(kind: 1, widthPoints: widthMM * 72 / 25.4, colorRGB: borderColor) }
    private var alignment: Alignment { format.vertical == .center ? .center : format.vertical == .end ? .bottom : .top }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("가나다 ABC")
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: alignment).padding(12)
                        .background(color(format.box.backgroundColorRGB ?? 0xFFFFFF))
                        .overlay(alignment: .leading) { border(format.box.left).frame(width: max(1, format.box.left.widthPoints * 2)) }
                        .overlay(alignment: .trailing) { border(format.box.right).frame(width: max(1, format.box.right.widthPoints * 2)) }
                        .overlay(alignment: .top) { border(format.box.top).frame(height: max(1, format.box.top.widthPoints * 2)) }
                        .overlay(alignment: .bottom) { border(format.box.bottom).frame(height: max(1, format.box.bottom.widthPoints * 2)) }
                        .accessibilityLabel("셀 서식 미리보기")
                }
                Section("세로 정렬") {
                    Picker("세로 정렬", selection: $format.vertical) {
                        Text("위").tag(HWPDocumentRelativeAlignment.start)
                        Text("가운데").tag(HWPDocumentRelativeAlignment.center)
                        Text("아래").tag(HWPDocumentRelativeAlignment.end)
                    }.pickerStyle(.segmented).accessibilityIdentifier("hwp-cell-vertical")
                }
                Section("채우기") {
                    Button("채우기 없음") { format.setFill(nil) }
                        .accessibilityIdentifier("hwp-cell-fill-none")
                    palette(selected: format.box.backgroundColorRGB, id: "fill") { format.setFill($0) }
                }
                Section("테두리") {
                    HStack {
                        Button("모두") { for side in 0..<4 { format.setBorder(side, line: line) } }
                            .accessibilityIdentifier("hwp-cell-border-all")
                        Spacer()
                        Button("없음") { for side in 0..<4 { format.setBorder(side, line: .init()) } }
                            .accessibilityIdentifier("hwp-cell-border-none")
                    }.buttonStyle(.borderless)
                    HStack {
                        ForEach(Array(["왼쪽", "오른쪽", "위쪽", "아래쪽"].enumerated()), id: \.offset) { side, title in
                            Button {
                                format.setBorder(side, line: format.borders[side].isVisible ? .init() : line)
                            } label: {
                                Text(AppLocalization.string(title)).frame(maxWidth: .infinity, minHeight: 40)
                                    .background(format.borders[side].isVisible ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.borderless)
                                .accessibilityIdentifier("hwp-cell-border-\(side)")
                                .accessibilityValue(AppLocalization.string(format.borders[side].isVisible ? "켜짐" : "꺼짐"))
                        }
                    }
                    Picker("선 굵기", selection: $widthMM) {
                        ForEach(Array(Set(HWPCellFormatting.widthsMM + [widthMM])).sorted(), id: \.self) { value in
                            Text(String(format: "%g mm", value)).tag(value)
                        }
                    }.accessibilityIdentifier("hwp-cell-border-width")
                        .onChange(of: widthMM) { _, _ in updateVisibleBorders() }
                    Text("선 색상")
                    palette(selected: borderColor, id: "border-color") { borderColor = $0; updateVisibleBorders() }
                }
            }
            .accessibilityIdentifier("hwp-cell-form")
            .navigationTitle("셀 서식")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") { onApply(format) }.accessibilityIdentifier("hwp-cell-apply")
                }
            }
        }
        .presentationSizing(.page)
    }

    private func updateVisibleBorders() {
        for side in 0..<4 where format.borders[side].isVisible {
            format.setBorder(side, line: .init(kind: format.borders[side].kind, widthPoints: line.widthPoints, colorRGB: borderColor))
        }
    }

    private func palette(selected: UInt32?, id: String, action: @escaping (UInt32) -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 44)), count: 5), spacing: 8) {
            ForEach(colors, id: \.1) { name, rgb in
                Button { action(rgb) } label: {
                    RoundedRectangle(cornerRadius: 8).fill(color(rgb))
                        .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)) }
                        .overlay { if selected == rgb { Image(systemName: "checkmark").foregroundStyle(rgb == 0 || rgb == 0xCC0000 || rgb == 0x0066CC ? .white : .black) } }
                        .frame(height: 48)
                }.buttonStyle(.borderless)
                    .accessibilityLabel(AppLocalization.string(name))
                    .accessibilityIdentifier("hwp-cell-\(id)-\(rgb)")
            }
        }
    }

    private func border(_ line: HWPDocumentBorderLine) -> some View {
        Rectangle().fill(line.isVisible ? color(line.colorRGB) : .clear)
    }
    private func color(_ rgb: UInt32) -> Color {
        Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}
