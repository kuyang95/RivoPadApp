#if DEBUG
import SwiftUI
import UIKit

enum AccessibleWebTheme {
    static var colors: RatioExperience { RatioExperience() }
    private static func hex(_ color: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
    static var script: String {
        let theme = colors
        return "window.__rivoWebTheme = {bg:'\(hex(theme.background))',surface:'\(hex(theme.surface))',text:'\(hex(theme.text))',edge:'\(hex(theme.outline))',link:'\(hex(theme.accent))',scheme:'dark'};\n"
    }
}
#endif
