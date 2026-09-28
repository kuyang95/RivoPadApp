import Foundation

nonisolated struct ExcelDrawingChartData {
    struct Point: Identifiable {
        let id: Int
        let category: String
        let x: Double
        let value: Double
    }
    struct Series: Identifiable {
        let id: Int
        let name: String
        let points: [Point]
    }
    let series: [Series]
    let supported: Bool

    init(chart: ExcelSheetChart, workbook: ExcelWorkbook) {
        func cells(_ reference: String, defaultSheet: String) -> [String]? {
            let parts = reference.split(separator: "!", omittingEmptySubsequences: false)
            guard parts.count <= 2, !reference.contains("["), !reference.contains("]") else { return nil }
            var sheetName = parts.count == 2 ? String(parts[0]) : defaultSheet
            if sheetName.hasPrefix("'"), sheetName.hasSuffix("'") { sheetName = String(sheetName.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
            guard let range = ExcelCellRange(String(parts.last ?? "")), range.cellCount <= 2000,
                  range.start.row == range.end.row || range.start.column == range.end.column,
                  let sheet = workbook.sheets.first(where: { $0.name.caseInsensitiveCompare(sheetName) == .orderedSame }), !sheet.didTruncate else { return nil }
            return range.addresses.map { sheet.cells[$0]?.rawValue ?? "" }
        }
        func values(_ node: ExcelEditingXML.Node?) -> [String]? {
            guard let node else { return nil }
            if let formula = node.descendants("f").first {
                // A resolvable local source wins over caches, including blank cells.
                if let result = cells(formula.text, defaultSheet: chart.sheetName) { return result }
                return nil
            }
            let points = node.descendants("pt")
            let count = min(2000, (points.compactMap { Int($0.attributes["idx"] ?? "") }.max() ?? -1) + 1)
            guard count > 0 else { return nil }
            var result = Array(repeating: "", count: count)
            for point in points {
                if let i = Int(point.attributes["idx"] ?? ""), result.indices.contains(i) { result[i] = point.child("v")?.text ?? "" }
            }
            return result
        }
        func number(_ value: String) -> Double? {
            guard let number = Double(value), number.isFinite else { return nil }
            return number
        }
        if let xml = chart.originalChartXML {
            guard let root = try? ExcelEditingXML.parse(Data(xml.utf8)), let plot = root.descendants("plotArea").first else { series = []; supported = false; return }
            let groups = plot.children.filter { $0.localName.hasSuffix("Chart") }
            guard groups.count == 1, let group = groups.first,
                  ["barChart", "lineChart", "areaChart", "pieChart", "doughnutChart", "scatterChart"].contains(group.localName),
                  !group.descendants("grouping").contains(where: { ["stacked", "percentStacked"].contains($0.attributes["val"] ?? "") }) else { series = []; supported = false; return }
            var result: [Series] = []
            for (index, ser) in group.elements("ser").enumerated() {
                guard let ys = values(ser.child("val") ?? ser.child("yVal")) else { series = []; supported = false; return }
                let cats = values(ser.child("cat") ?? ser.child("xVal"))
                if chart.kind == .scatter && cats == nil { series = []; supported = false; return }
                let name = values(ser.child("tx"))?.first ?? ser.child("tx")?.child("v")?.text ?? AppLocalization.format("계열 %lld", index + 1)
                let points = ys.enumerated().compactMap { i, value -> Point? in
                    guard let y = number(value) else { return nil }
                    let category = cats.flatMap { $0.indices.contains(i) ? $0[i] : nil } ?? String(i + 1)
                    guard chart.kind != .scatter || number(category) != nil else { return nil }
                    return Point(id: i, category: category, x: chart.kind == .scatter ? number(category)! : Double(i), value: y)
                }
                result.append(Series(id: index, name: name, points: points))
            }
            series = result; supported = !result.isEmpty
        } else {
            guard chart.kind != .unsupported, chart.kind != .radar, let range = chart.sourceRange, range.cellCount <= 2000,
                  let sheet = workbook.sheets.first(where: { $0.name == chart.sheetName }), !sheet.didTruncate,
                  range.end.row > range.start.row else { series = []; supported = false; return }
            let hasCategory = range.end.column > range.start.column
            let first = hasCategory ? range.start.column + 1 : range.start.column
            let last = chart.kind == .pie || chart.kind == .doughnut ? first : range.end.column
            series = (first ... last).enumerated().map { index, column in
                let name = sheet.cells[.init(row: range.start.row, column: column)]?.displayValue ?? AppLocalization.format("계열 %lld", index + 1)
                let points = ((range.start.row + 1) ... range.end.row).enumerated().compactMap { i, row -> Point? in
                    guard let y = number(sheet.cells[.init(row: row, column: column)]?.rawValue ?? "") else { return nil }
                    let category = hasCategory ? (sheet.cells[.init(row: row, column: range.start.column)]?.displayValue ?? "") : String(i + 1)
                    let x = chart.kind == .scatter ? (hasCategory ? number(sheet.cells[.init(row: row, column: range.start.column)]?.rawValue ?? "") : y) : Double(i)
                    guard let x else { return nil }
                    return Point(id: i, category: category, x: x, value: y)
                }
                return Series(id: index, name: name, points: points)
            }
            supported = true
        }
    }
}
