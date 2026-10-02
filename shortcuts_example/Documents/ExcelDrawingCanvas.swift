import RivoDocumentEngine
import SwiftUI
import UIKit
import Charts

struct ExcelDrawingCanvasItem: Identifiable {
    let id: String
    let name: String
    let anchor: ExcelDrawingAnchor
    let order: Int
    let image: ExcelSheetImage?
    let chart: ExcelSheetChart?
}

struct ExcelDrawingCanvasObject: View {
    let item: ExcelDrawingCanvasItem
    let workbook: ExcelWorkbook
    let size: CGSize
    let renderScale: CGFloat
    let zoomScale: CGFloat
    let selected: Bool
    let editable: Bool
    let onSelect: () -> Void
    let onSettings: () -> Void
    let onNudge: (CGPoint, Bool) -> Void

    var body: some View {
        ZStack {
            if let image = item.image {
                ExcelDrawingImagePreview(image: image)
            } else if let chart = item.chart {
                ExcelDrawingChartPreview(chart: chart, data: ExcelDrawingChartData(chart: chart, workbook: workbook))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .scaleEffect(renderScale, anchor: .topLeading)
        .frame(width: size.width * renderScale, height: size.height * renderScale, alignment: .topLeading)
        .overlay {
            if selected {
                Rectangle().strokeBorder(VisionCraftUI.primary, lineWidth: 2 * renderScale / zoomScale)
                if editable {
                    ForEach(0 ..< 4, id: \.self) { index in
                        let point = ExcelDrawingDragMode.allCases[index + 1].corner(in: CGRect(origin: .zero, size: size))!
                        Circle().fill(.background).overlay(Circle().stroke(VisionCraftUI.primary, lineWidth: 2))
                            .frame(width: 12 * renderScale / zoomScale, height: 12 * renderScale / zoomScale)
                            .position(x: point.x * renderScale, y: point.y * renderScale)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityValue(item.image?.alternativeText ?? item.chart?.kind.title ?? AppLocalization.string("이미지"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("두 번 탭하면 선택합니다. 선택한 개체를 끌어 이동하거나 모서리로 크기를 바꿀 수 있습니다.")
        .accessibilityAction { onSelect() }
        .accessibilityAction(named: "개체 설정") { onSettings() }
        .accessibilityActions {
            if editable {
                Button("위로 이동") { onNudge(CGPoint(x: 0, y: -20), false) }
                Button("아래로 이동") { onNudge(CGPoint(x: 0, y: 20), false) }
                Button("왼쪽으로 이동") { onNudge(CGPoint(x: -20, y: 0), false) }
                Button("오른쪽으로 이동") { onNudge(CGPoint(x: 20, y: 0), false) }
                Button("개체 크게") { onNudge(CGPoint(x: 20, y: 20), true) }
                Button("개체 작게") { onNudge(CGPoint(x: -20, y: -20), true) }
            }
        }
    }
}

private struct ExcelDrawingImagePreview: View {
    let image: ExcelSheetImage
    @State private var decoded: UIImage?
    var body: some View {
        Group {
            if let decoded { Image(uiImage: decoded).resizable() }
            else { ContentUnavailableView("이미지 미리보기 없음", systemImage: "photo", description: Text(image.name)) }
        }
        .onAppear { decoded = UIImage(data: image.data) }
        .onChange(of: image.data) { _, data in decoded = UIImage(data: data) }
    }
}

private struct ExcelDrawingChartPreview: View {
    let chart: ExcelSheetChart
    let data: ExcelDrawingChartData
    var body: some View {
        VStack(spacing: 8) {
            Text(chart.title).font(.headline).lineLimit(2)
            if !data.supported {
                Image(systemName: "chart.bar.xaxis").font(.largeTitle).foregroundStyle(.secondary)
                Text("이 차트는 미리보기를 지원하지 않습니다. 위치와 크기는 바꿀 수 있습니다.").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else if data.series.allSatisfy({ $0.points.isEmpty }) {
                Text("표시할 숫자 데이터가 없습니다.").font(.caption).foregroundStyle(.secondary)
            } else if chart.kind == .pie || chart.kind == .doughnut {
                Chart(data.series.first?.points.filter { $0.value > 0 } ?? []) { point in
                    SectorMark(angle: .value("값", point.value), innerRadius: .ratio(chart.kind == .doughnut ? 0.55 : 0))
                        .foregroundStyle(by: .value("항목", point.category))
                }
            } else {
                Chart {
                    ForEach(data.series) { series in
                        ForEach(series.points) { point in
                            marks(point, series: series)
                        }
                    }
                }
                .chartXAxis {
                    if chart.kind == .bar || chart.kind == .scatter { AxisMarks() }
                    else { AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel { if let index = value.as(Int.self), let point = data.series.first?.points.first(where: { $0.id == index }) { Text(point.category).lineLimit(1) } }
                    } }
                }
                .chartYAxis {
                    if chart.kind != .bar { AxisMarks() }
                    else { AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel { if let index = value.as(Int.self), let point = data.series.first?.points.first(where: { $0.id == index }) { Text(point.category).lineLimit(1) } }
                    } }
                }
            }
        }
        .padding(12)
        .background(.background)
        .overlay(Rectangle().stroke(.quaternary))
    }
    @ChartContentBuilder
    private func marks(_ point: ExcelDrawingChartData.Point, series: ExcelDrawingChartData.Series) -> some ChartContent {
        switch chart.kind {
        case .column:
            BarMark(x: .value("항목", point.id), y: .value("값", point.value)).foregroundStyle(by: .value("계열", series.name)).position(by: .value("계열", series.name))
        case .bar:
            BarMark(x: .value("값", point.value), y: .value("항목", point.id)).foregroundStyle(by: .value("계열", series.name)).position(by: .value("계열", series.name))
        case .area:
            AreaMark(x: .value("항목", point.id), y: .value("값", point.value), stacking: .unstacked).foregroundStyle(by: .value("계열", series.name))
        case .scatter:
            PointMark(x: .value("X", point.x), y: .value("Y", point.value)).foregroundStyle(by: .value("계열", series.name))
        default:
            LineMark(x: .value("항목", point.id), y: .value("값", point.value)).foregroundStyle(by: .value("계열", series.name))
        }
    }
}
