#if DEBUG
import SwiftUI

/// Local vector artwork shared in appearance with the Android weather widget.
struct LauncherWeatherArtwork: View {
    var code: Int
    var body: some View {
        Canvas { original, size in
            var context = original
            context.scaleBy(x: size.width / 96, y: size.height / 96)
            func color(_ rgb: UInt32) -> Color { VisionCraftUI.fixedColor(rgb) }
            func line(_ from: CGPoint, _ to: CGPoint, _ rgb: UInt32, _ width: CGFloat) {
                var path = Path(); path.move(to: from); path.addLine(to: to)
                context.stroke(path, with: .color(color(rgb)), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            context.fill(Path(ellipseIn: CGRect(x: 17, y: 79, width: 65, height: 8)), with: .color(color(0x12243B).opacity(0.10)))
            if code <= 3 {
                let center = code == 0 ? CGPoint(x: 48, y: 43) : CGPoint(x: 34, y: 31)
                context.fill(Path(ellipseIn: CGRect(x: center.x-25, y: center.y-25, width: 50, height: 50)), with: .color(color(0xFFE5A6)))
                context.fill(Path(ellipseIn: CGRect(x: center.x-19, y: center.y-19, width: 38, height: 38)), with: .color(color(0xFFC75F)))
                for index in 0..<8 {
                    let a = Double(index) * .pi / 4
                    line(CGPoint(x: center.x + cos(a)*29, y: center.y + sin(a)*29), CGPoint(x: center.x + cos(a)*33, y: center.y + sin(a)*33), 0xFFD67C, 3.5)
                }
            }
            if code != 0 {
                var cloud = Path(); cloud.move(to: CGPoint(x: 24, y: 67))
                cloud.addCurve(to: CGPoint(x: 27, y: 43), control1: CGPoint(x: 8, y: 67), control2: CGPoint(x: 9, y: 43))
                cloud.addCurve(to: CGPoint(x: 69, y: 40), control1: CGPoint(x: 29, y: 20), control2: CGPoint(x: 63, y: 18))
                cloud.addCurve(to: CGPoint(x: 75, y: 67), control1: CGPoint(x: 91, y: 39), control2: CGPoint(x: 94, y: 67)); cloud.closeSubpath()
                context.fill(cloud, with: .color(color(0xF2F6FF)))
                context.stroke(cloud, with: .color(color(0xB5CBE0)), lineWidth: 2.5)
                var shade = Path(); shade.move(to: CGPoint(x: 22, y: 60)); shade.addCurve(to: CGPoint(x: 80, y: 59), control1: CGPoint(x: 38, y: 65), control2: CGPoint(x: 66, y: 65))
                context.stroke(shade, with: .color(color(0xD8E6F4)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            if (51...67).contains(code) || (80...82).contains(code) {
                for x in [31.0, 49, 67] { line(CGPoint(x: x, y: 74), CGPoint(x: x-4, y: 83), 0x80BDEB, 4) }
            }
            if (71...77).contains(code) || (85...86).contains(code) {
                for x in [31.0, 50, 69] { line(CGPoint(x: x-4, y: 78), CGPoint(x: x+4, y: 78), 0xA5D9EE, 2.5); line(CGPoint(x: x, y: 74), CGPoint(x: x, y: 82), 0xA5D9EE, 2.5) }
            }
            if (95...99).contains(code) {
                var bolt = Path(); bolt.move(to: CGPoint(x: 49, y: 66))
                for point in [CGPoint(x:38,y:79),CGPoint(x:47,y:79),CGPoint(x:43,y:91),CGPoint(x:60,y:74),CGPoint(x:51,y:74),CGPoint(x:57,y:66)] { bolt.addLine(to: point) }; bolt.closeSubpath()
                context.fill(bolt, with: .color(color(0xFFCD68)))
            }
            if code == 45 || code == 48 {
                for i in 0...2 { line(CGPoint(x: 24+i*4, y: 74+i*6), CGPoint(x: 73-i*4, y: 74+i*6), 0xB7CFDA, 3) }
            }
        }.accessibilityHidden(true)
    }
}
#endif
