import Foundation

/// Bounded DrawingML chart-cache reader. It never follows relationships or
/// executes embedded OLE; only the values already cached in the chart XML are
/// exposed to the renderer.
nonisolated enum HWPChartOOXMLParser {
    struct Result: Sendable {
        let kind: HWPDocumentChartKind
        let title: String?
        let categories: [String]
        let series: [HWPDocumentChartSeries]
    }

    static func parse(_ data: Data) throws -> Result {
        guard data.count <= 4 * 1_024 * 1_024 else {
            throw ChatAttachmentError.hwpLimitExceeded
        }
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            throw ChatAttachmentError.invalidHWP
        }
        return delegate.result
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        private struct SeriesBuilder {
            var name = ""
            var values: [Int: Double] = [:]
            var categories: [Int: String] = [:]
            var colorRGB: UInt32?
        }

        private var stack: [String] = []
        private var text = ""
        private var kind: HWPDocumentChartKind = .unknown
        private var titleParts: [String] = []
        private var series: [SeriesBuilder] = []
        private var activeSeries: SeriesBuilder?
        private var pointIndex = 0

        var result: Result {
            let builders = series + (activeSeries.map { [$0] } ?? [])
            let categorySource = builders.first(where: {
                !$0.categories.isEmpty
            })?.categories ?? [:]
            let categoryCount = max(
                categorySource.keys.max().map { $0 + 1 } ?? 0,
                builders.map { ($0.values.keys.max() ?? -1) + 1 }.max() ?? 0
            )
            let categories = (0..<min(categoryCount, 4_096)).map {
                categorySource[$0] ?? String($0 + 1)
            }
            let outputSeries = builders.prefix(128).enumerated().map { index, item in
                let maximumIndex = min(item.values.keys.max() ?? -1, 4_095)
                let values = maximumIndex >= 0
                    ? (0...maximumIndex).map { item.values[$0] ?? 0 }
                    : []
                return HWPDocumentChartSeries(
                    id: "hwp-chart-series-\(index)",
                    name: item.name.isEmpty ? "계열 \(index + 1)" : item.name,
                    values: values,
                    colorRGB: item.colorRGB
                )
            }
            let title = titleParts
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Result(
                kind: kind,
                title: title.isEmpty ? nil : title,
                categories: categories,
                series: outputSeries
            )
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = Self.localName(qName ?? elementName).lowercased()
            stack.append(name)
            text = ""
            switch name {
            case "barchart", "bar3dchart":
                kind = .bar
            case "linechart", "line3dchart":
                kind = .line
            case "piechart", "pie3dchart", "doughnutchart":
                kind = .pie
            case "areachart", "area3dchart":
                kind = .area
            case "scatterchart", "bubblechart":
                kind = .scatter
            case "radarchart":
                kind = .radar
            case "ser":
                if let activeSeries { series.append(activeSeries) }
                activeSeries = SeriesBuilder()
            case "pt":
                let raw = Self.attribute(attributeDict, named: "idx") ?? "0"
                pointIndex = min(max(Int(raw) ?? 0, 0), 4_095)
            case "srgbclr":
                guard activeSeries != nil,
                      let raw = Self.attribute(attributeDict, named: "val"),
                      raw.count == 6,
                      let color = UInt32(raw, radix: 16) else { break }
                activeSeries?.colorRGB = color
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let name = Self.localName(qName ?? elementName).lowercased()
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if name == "v" || name == "t" {
                if activeSeries != nil {
                    if stack.contains("cat") || stack.contains("xval") {
                        if !value.isEmpty {
                            activeSeries?.categories[pointIndex] = value
                        }
                    } else if stack.contains("val")
                                || stack.contains("yval")
                                || stack.contains("bubbleSize".lowercased()) {
                        if let number = Double(value), number.isFinite {
                            activeSeries?.values[pointIndex] = number
                        }
                    } else if stack.contains("tx"), !value.isEmpty {
                        activeSeries?.name = value
                    }
                } else if stack.contains("title"), !value.isEmpty {
                    titleParts.append(value)
                }
            } else if name == "ser", let completed = activeSeries {
                series.append(completed)
                activeSeries = nil
            }
            if !stack.isEmpty { stack.removeLast() }
            text = ""
        }

        private static func localName(_ name: String) -> String {
            String(name.split(separator: ":").last ?? Substring(name))
        }

        private static func attribute(
            _ attributes: [String: String],
            named name: String
        ) -> String? {
            attributes.first {
                localName($0.key).caseInsensitiveCompare(name) == .orderedSame
            }?.value
        }
    }
}
