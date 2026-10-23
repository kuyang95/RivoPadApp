#if DEBUG
import SwiftUI

/// Shared launcher appearance on every home page; widget colors remain user controlled.
struct RatioExperience {
    var background: Color { VisionCraftUI.fixedColor(0x101C2D) }
    var surface: Color { VisionCraftUI.fixedColor(0x1C2D43) }
    var text: Color { VisionCraftUI.fixedColor(0xF5F3E9) }
    var accent: Color { VisionCraftUI.fixedColor(0xE6EF87) }
    var outline: Color { VisionCraftUI.fixedColor(0x7F93AB) }
    var ink: Color { VisionCraftUI.fixedColor(0x101010) }
    var corner: CGFloat { 8 }
}
#endif
