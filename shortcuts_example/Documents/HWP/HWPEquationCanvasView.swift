import SwiftUI
import UIKit

struct HWPEquationCanvasView: View {
    let equation: HWPDocumentEquation

    var body: some View {
        Canvas { context, size in
            let node = HWPEquationParser.parse(equation.script)
            let fontSize = max(8, equation.fontSizePoints)
            let layout = HWPFormulaLayoutEngine.layout(node, fontSize: fontSize)
            let scale = min(
                1,
                size.width / max(layout.size.width, 1),
                size.height / max(layout.size.height, 1)
            )
            let origin = CGPoint(
                x: max(0, (size.width - layout.size.width * scale) / 2),
                y: max(0, (size.height - layout.size.height * scale) / 2)
            )
            context.translateBy(x: origin.x, y: origin.y)
            context.scaleBy(x: scale, y: scale)
            let color = equationColor(equation.colorRGB)
            for glyph in layout.glyphs {
                context.draw(
                    Text(glyph.text)
                        .font(.system(size: glyph.fontSize, design: .serif))
                        .foregroundStyle(color),
                    at: glyph.origin,
                    anchor: .topLeading
                )
            }
            for rule in layout.rules {
                var path = Path()
                path.move(to: rule.start)
                path.addLine(to: rule.end)
                context.stroke(
                    path,
                    with: .color(color),
                    lineWidth: max(0.7, rule.width)
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("수식 \(equation.script)")
    }
}

private func equationColor(_ rgb: UInt32) -> Color {
    Color(
        red: Double((rgb >> 16) & 0xFF) / 255,
        green: Double((rgb >> 8) & 0xFF) / 255,
        blue: Double(rgb & 0xFF) / 255
    )
}

private indirect enum HWPFormulaNode {
    case row([HWPFormulaNode])
    case text(String)
    case fraction(HWPFormulaNode, HWPFormulaNode)
    case root(HWPFormulaNode)
    case scripts(base: HWPFormulaNode, superscript: HWPFormulaNode?, subscript: HWPFormulaNode?)
    case matrix([[HWPFormulaNode]], leftDelimiter: String, rightDelimiter: String)
}

private enum HWPEquationParser {
    private enum Token: Equatable {
        case word(String)
        case symbol(Character)
    }

    static func parse(_ script: String) -> HWPFormulaNode {
        var parser = Parser(tokens: tokenize(script))
        return parser.parseRow(until: [])
    }

    private static func tokenize(_ input: String) -> [Token] {
        var result: [Token] = []
        var word = ""
        func flush() {
            guard !word.isEmpty else { return }
            result.append(.word(word))
            word = ""
        }
        for character in input {
            if character.isWhitespace {
                flush()
            } else if "{}()[]^_&#,~".contains(character) {
                flush()
                result.append(.symbol(character))
            } else if "+-=<>/|!;:".contains(character) {
                flush()
                result.append(.symbol(character))
            } else {
                word.append(character)
            }
        }
        flush()
        return result
    }

    private struct Parser {
        var tokens: [Token]
        var index = 0

        mutating func parseRow(until terminators: Set<Character>) -> HWPFormulaNode {
            var nodes: [HWPFormulaNode] = []
            while index < tokens.count {
                if case .symbol(let symbol) = tokens[index], terminators.contains(symbol) {
                    break
                }
                if case .word(let word) = tokens[index], word.lowercased() == "over" {
                    index += 1
                    let denominator = parseRow(until: terminators)
                    return .fraction(collapse(nodes), denominator)
                }
                var node = parseAtom()
                var superscript: HWPFormulaNode?
                var subscriptNode: HWPFormulaNode?
                while index < tokens.count {
                    guard case .symbol(let marker) = tokens[index],
                          marker == "^" || marker == "_" else { break }
                    index += 1
                    let script = parseAtom()
                    if marker == "^" { superscript = script }
                    else { subscriptNode = script }
                }
                if superscript != nil || subscriptNode != nil {
                    node = .scripts(
                        base: node,
                        superscript: superscript,
                        subscript: subscriptNode
                    )
                }
                nodes.append(node)
            }
            return collapse(nodes)
        }

        private mutating func parseAtom() -> HWPFormulaNode {
            guard index < tokens.count else { return .text("") }
            let token = tokens[index]
            index += 1
            switch token {
            case .symbol("{"):
                let result = parseRow(until: ["}"])
                consume("}")
                return result
            case .symbol("("):
                let result = parseRow(until: [")"])
                consume(")")
                return .row([.text("("), result, .text(")")])
            case .symbol("["):
                let result = parseRow(until: ["]"])
                consume("]")
                return .row([.text("["), result, .text("]")])
            case .symbol(let symbol):
                if symbol == "~" { return .text(" ") }
                return .text(String(symbol))
            case .word(let rawWord):
                let word = rawWord.lowercased()
                if word == "sqrt" || word == "root" {
                    return .root(parseAtom())
                }
                if word == "matrix" || word == "bmatrix"
                    || word == "pmatrix" || word == "cases"
                    || word == "pile" {
                    let delimiters: (String, String)
                    switch word {
                    case "bmatrix": delimiters = ("[", "]")
                    case "pmatrix": delimiters = ("(", ")")
                    case "cases": delimiters = ("{", "")
                    default: delimiters = ("", "")
                    }
                    return parseMatrix(
                        leftDelimiter: delimiters.0,
                        rightDelimiter: delimiters.1
                    )
                }
                return .text(symbol(for: word) ?? rawWord)
            }
        }

        private mutating func parseMatrix(
            leftDelimiter: String,
            rightDelimiter: String
        ) -> HWPFormulaNode {
            guard index < tokens.count, tokens[index] == .symbol("{") else {
                return .text("□")
            }
            index += 1
            var rows: [[HWPFormulaNode]] = [[]]
            while index < tokens.count {
                let cell = parseRow(until: ["&", "#", "}"])
                rows[rows.count - 1].append(cell)
                guard index < tokens.count else { break }
                if tokens[index] == .symbol("&") {
                    index += 1
                } else if tokens[index] == .symbol("#") {
                    index += 1
                    rows.append([])
                } else if tokens[index] == .symbol("}") {
                    index += 1
                    break
                }
            }
            return .matrix(
                rows.filter { !$0.isEmpty },
                leftDelimiter: leftDelimiter,
                rightDelimiter: rightDelimiter
            )
        }

        private mutating func consume(_ symbol: Character) {
            if index < tokens.count, tokens[index] == .symbol(symbol) { index += 1 }
        }

        private func collapse(_ nodes: [HWPFormulaNode]) -> HWPFormulaNode {
            if nodes.count == 1 { return nodes[0] }
            return .row(nodes)
        }

        private func symbol(for word: String) -> String? {
            let symbols: [String: String] = [
                "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ",
                "epsilon": "ε", "theta": "θ", "lambda": "λ", "mu": "μ",
                "pi": "π", "rho": "ρ", "sigma": "σ", "phi": "φ",
                "omega": "ω", "sum": "∑", "prod": "∏", "int": "∫",
                "infty": "∞", "inf": "∞", "partial": "∂", "nabla": "∇",
                "times": "×", "div": "÷", "cdot": "·", "pm": "±",
                "leq": "≤", "geq": "≥", "neq": "≠", "approx": "≈",
                "rightarrow": "→", "leftarrow": "←", "leftrightarrow": "↔",
                "therefore": "∴", "because": "∵",
            ]
            return symbols[word]
        }
    }
}

private struct HWPFormulaGlyph {
    let text: String
    let origin: CGPoint
    let fontSize: CGFloat
}

private struct HWPFormulaRule {
    let start: CGPoint
    let end: CGPoint
    let width: CGFloat
}

private struct HWPFormulaLayout {
    let size: CGSize
    let glyphs: [HWPFormulaGlyph]
    let rules: [HWPFormulaRule]

    func offsetBy(x: CGFloat, y: CGFloat) -> HWPFormulaLayout {
        HWPFormulaLayout(
            size: size,
            glyphs: glyphs.map {
                HWPFormulaGlyph(
                    text: $0.text,
                    origin: CGPoint(x: $0.origin.x + x, y: $0.origin.y + y),
                    fontSize: $0.fontSize
                )
            },
            rules: rules.map {
                HWPFormulaRule(
                    start: CGPoint(x: $0.start.x + x, y: $0.start.y + y),
                    end: CGPoint(x: $0.end.x + x, y: $0.end.y + y),
                    width: $0.width
                )
            }
        )
    }
}

private enum HWPFormulaLayoutEngine {
    static func layout(_ node: HWPFormulaNode, fontSize: CGFloat) -> HWPFormulaLayout {
        switch node {
        case .text(let text):
            let font = UIFont.systemFont(ofSize: fontSize)
            let size = (text as NSString).size(withAttributes: [.font: font])
            return HWPFormulaLayout(
                size: CGSize(width: max(size.width, 1), height: max(size.height, fontSize * 1.15)),
                glyphs: [HWPFormulaGlyph(text: text, origin: .zero, fontSize: fontSize)],
                rules: []
            )
        case .row(let nodes):
            let children = nodes.map { layout($0, fontSize: fontSize) }
            let height = children.map(\.size.height).max() ?? fontSize
            var x: CGFloat = 0
            var glyphs: [HWPFormulaGlyph] = []
            var rules: [HWPFormulaRule] = []
            for child in children {
                let placed = child.offsetBy(x: x, y: (height - child.size.height) / 2)
                glyphs += placed.glyphs
                rules += placed.rules
                x += child.size.width + fontSize * 0.06
            }
            return HWPFormulaLayout(
                size: CGSize(width: max(1, x), height: height),
                glyphs: glyphs,
                rules: rules
            )
        case .fraction(let numerator, let denominator):
            let childSize = fontSize * 0.82
            let top = layout(numerator, fontSize: childSize)
            let bottom = layout(denominator, fontSize: childSize)
            let width = max(top.size.width, bottom.size.width) + fontSize * 0.35
            let gap = fontSize * 0.18
            let topPlaced = top.offsetBy(x: (width - top.size.width) / 2, y: 0)
            let lineY = top.size.height + gap
            let bottomPlaced = bottom.offsetBy(
                x: (width - bottom.size.width) / 2,
                y: lineY + gap
            )
            return HWPFormulaLayout(
                size: CGSize(
                    width: width,
                    height: lineY + gap + bottom.size.height
                ),
                glyphs: topPlaced.glyphs + bottomPlaced.glyphs,
                rules: topPlaced.rules + bottomPlaced.rules + [
                    HWPFormulaRule(
                        start: CGPoint(x: 0, y: lineY),
                        end: CGPoint(x: width, y: lineY),
                        width: max(0.8, fontSize * 0.06)
                    ),
                ]
            )
        case .root(let radicand):
            let child = layout(radicand, fontSize: fontSize * 0.92)
            let root = layout(.text("√"), fontSize: fontSize * 1.18)
            let x = root.size.width * 0.8
            let placed = child.offsetBy(x: x, y: fontSize * 0.18)
            return HWPFormulaLayout(
                size: CGSize(
                    width: x + child.size.width,
                    height: max(root.size.height, placed.size.height + fontSize * 0.18)
                ),
                glyphs: root.glyphs + placed.glyphs,
                rules: placed.rules + [
                    HWPFormulaRule(
                        start: CGPoint(x: x - 1, y: fontSize * 0.14),
                        end: CGPoint(x: x + child.size.width, y: fontSize * 0.14),
                        width: max(0.7, fontSize * 0.05)
                    ),
                ]
            )
        case .scripts(let base, let superscript, let subscriptNode):
            let baseLayout = layout(base, fontSize: fontSize)
            let scriptSize = fontSize * 0.64
            let sup = superscript.map { layout($0, fontSize: scriptSize) }
            let sub = subscriptNode.map { layout($0, fontSize: scriptSize) }
            let topHeight = sup?.size.height ?? 0
            let baseY = max(0, topHeight * 0.68)
            let scriptX = baseLayout.size.width + fontSize * 0.04
            var glyphs = baseLayout.offsetBy(x: 0, y: baseY).glyphs
            var rules = baseLayout.offsetBy(x: 0, y: baseY).rules
            var width = baseLayout.size.width
            var height = baseY + baseLayout.size.height
            if let sup {
                let placed = sup.offsetBy(x: scriptX, y: 0)
                glyphs += placed.glyphs
                rules += placed.rules
                width = max(width, scriptX + sup.size.width)
            }
            if let sub {
                let placed = sub.offsetBy(
                    x: scriptX,
                    y: baseY + baseLayout.size.height * 0.62
                )
                glyphs += placed.glyphs
                rules += placed.rules
                width = max(width, scriptX + sub.size.width)
                height = max(height, baseY + baseLayout.size.height * 0.62 + sub.size.height)
            }
            return HWPFormulaLayout(
                size: CGSize(width: width, height: height),
                glyphs: glyphs,
                rules: rules
            )
        case .matrix(let rows, let leftDelimiter, let rightDelimiter):
            guard !rows.isEmpty else { return layout(.text("□"), fontSize: fontSize) }
            let columnCount = rows.map(\.count).max() ?? 1
            let cells = rows.map { row in
                row.map { layout($0, fontSize: fontSize * 0.82) }
            }
            let widths = (0..<columnCount).map { column in
                cells.compactMap { $0.indices.contains(column) ? $0[column].size.width : nil }.max() ?? fontSize
            }
            let heights = cells.map { $0.map(\.size.height).max() ?? fontSize }
            let gap = fontSize * 0.45
            var glyphs: [HWPFormulaGlyph] = []
            var rules: [HWPFormulaRule] = []
            var y = gap * 0.5
            for rowIndex in rows.indices {
                var x = gap
                for column in 0..<columnCount where cells[rowIndex].indices.contains(column) {
                    let cell = cells[rowIndex][column]
                    let placed = cell.offsetBy(
                        x: x + (widths[column] - cell.size.width) / 2,
                        y: y + (heights[rowIndex] - cell.size.height) / 2
                    )
                    glyphs += placed.glyphs
                    rules += placed.rules
                    x += widths[column] + gap
                }
                y += heights[rowIndex] + gap * 0.45
            }
            let width = widths.reduce(0, +) + gap * CGFloat(columnCount + 1)
            let height = y
            var delimiters: [HWPFormulaGlyph] = []
            if !leftDelimiter.isEmpty {
                delimiters.append(
                    HWPFormulaGlyph(
                        text: leftDelimiter,
                        origin: CGPoint(x: 0, y: height * 0.12),
                        fontSize: height * 0.7
                    )
                )
            }
            if !rightDelimiter.isEmpty {
                delimiters.append(
                    HWPFormulaGlyph(
                        text: rightDelimiter,
                        origin: CGPoint(x: width - gap * 0.7, y: height * 0.12),
                        fontSize: height * 0.7
                    )
                )
            }
            return HWPFormulaLayout(
                size: CGSize(width: width, height: height),
                glyphs: delimiters + glyphs,
                rules: rules
            )
        }
    }
}
