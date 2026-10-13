import RivoDocumentEngine
import SwiftUI
import UIKit

/// Paints an HWP equation from the engine's layout (`HWPEquationLayout`, shared with Android):
/// glyphs in the serif face anchored at their line box's top-left, then the rules, in the
/// equation colour.
struct HWPEquationCanvasView: View {
    let equation: HWPDocumentEquation

    var body: some View {
        Canvas { context, size in
            let formula = HWPEquationLayout.formula(
                script: equation.script,
                fontSize: equation.fontSizePoints,
                width: size.width,
                height: size.height,
                measure: Self.measure
            )
            guard formula.scale > 0 else { return }
            // The engine hands back fitted coordinates. Draw them at the unscaled font size in a
            // scaled context so the system font picks the same optical size as the layout's.
            let origin = CGPoint(
                x: max(0, (size.width - formula.width) / 2),
                y: max(0, (size.height - formula.height) / 2)
            )
            let scale = formula.scale
            context.translateBy(x: origin.x, y: origin.y)
            context.scaleBy(x: scale, y: scale)
            let color = hwpEquationColor(equation.colorRGB)
            for glyph in formula.glyphs {
                context.draw(
                    Text(glyph.text)
                        .font(.system(size: glyph.size / scale, design: .serif))
                        .foregroundStyle(color),
                    at: CGPoint(x: (glyph.x - origin.x) / scale, y: (glyph.y - origin.y) / scale),
                    anchor: .topLeading
                )
            }
            for rule in formula.rules {
                var path = Path()
                path.move(to: CGPoint(x: (rule.from.x - origin.x) / scale, y: (rule.from.y - origin.y) / scale))
                path.addLine(to: CGPoint(x: (rule.to.x - origin.x) / scale, y: (rule.to.y - origin.y) / scale))
                context.stroke(path, with: .color(color), lineWidth: rule.width / scale)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("수식 \(equation.script)")
    }

    /// Formula text widths, measured with the system face the layout assumes.
    static func measure(_ text: String, _ size: Double) -> Double {
        (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size)]).width
    }
}

private func hwpEquationColor(_ rgb: UInt32) -> Color {
    Color(
        red: Double((rgb >> 16) & 0xFF) / 255,
        green: Double((rgb >> 8) & 0xFF) / 255,
        blue: Double(rgb & 0xFF) / 255
    )
}
