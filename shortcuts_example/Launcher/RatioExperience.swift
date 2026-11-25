import SwiftUI
import UIKit

/// Shared launcher appearance on every home page; widget colors remain user controlled.
struct RatioExperience {
    var background: Color { VisionCraftUI.fixedColor(0x101C2D) }
    var darkHomeBackground: Color { VisionCraftUI.fixedColor(0x181A1B) }
    var lightBackground: Color { VisionCraftUI.fixedColor(0xEAE7E0) }
    var surface: Color { VisionCraftUI.fixedColor(0x23272B) }
    var lightTallSurface: Color { VisionCraftUI.fixedColor(0xF3EEE4) }
    var text: Color { VisionCraftUI.fixedColor(0xF8F5EC) }
    var accent: Color { VisionCraftUI.fixedColor(0xD8B36B) }
    var outline: Color { VisionCraftUI.fixedColor(0x777E84) }
    var ink: Color { VisionCraftUI.fixedColor(0x172126) }
    var magnifier: Color { VisionCraftUI.fixedColor(0x255B4B) }
    var timer: Color { VisionCraftUI.fixedColor(0x303831) }
    var timerButton: Color { VisionCraftUI.fixedColor(0xDFEEE0) }
    var timerButtonInk: Color { VisionCraftUI.fixedColor(0x17261E) }
    var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 2, style: .circular) }
    func searchFill(colorKey: String?) -> Color {
        (ratioPalette.first { $0.id == colorKey } ?? ratioSandSwatch).color
    }

    func readableHomeText(_ color: Color?, light: Bool) -> Color {
        guard let color else { return light ? ink : text }
        guard light else { return color }
        func luminance(_ color: Color) -> CGFloat {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            func linear(_ value: CGFloat) -> CGFloat {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
        return (luminance(lightBackground) + 0.05) / (luminance(color) + 0.05) >= 4.5 ? color : ink
    }

    func shortcutColors(id: String, selected: Color?, lightTall: Bool = false) -> (fill: Color, ink: Color) {
        if let selected { return (selected, ink) }
        switch id {
        case "magnifier": return (magnifier, text)
        case "chat": return (accent, ink)
        default: return lightTall ? (lightTallSurface, ink) : (surface, text)
        }
    }
}
