import ImageIO
import UIKit

/// Adjusts the launcher copy of an icon while keeping its artwork and alpha.
nonisolated enum RatioIconTone {
    private struct Anchor {
        var hue: Double
        var target: Double
        var saturation: Double
        var lightness: Double

        init(_ hue: Double, _ target: Double, _ saturation: Double, _ lightness: Double) {
            self.hue = hue
            self.target = target
            self.saturation = saturation
            self.lightness = lightness
        }
    }

    private static let anchors = [
        Anchor(0, 9, 0.66, -0.052), Anchor(22, 23, 0.66, -0.025),
        Anchor(52, 44, 0.69, 0.045), Anchor(82, 78, 0.62, 0.025),
        Anchor(120, 137, 0.61, 0.01), Anchor(153, 151, 0.61, 0.055),
        Anchor(185, 183, 0.57, 0.04), Anchor(215, 209, 0.58, 0.035),
        Anchor(253, 249, 0.58, 0.045), Anchor(296, 296, 0.59, 0.03),
        Anchor(334, 340, 0.63, -0.018), Anchor(360, 369, 0.66, -0.052)
    ]

    static func image(_ data: Data) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 192
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4, space: colorSpace,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))

        for offset in stride(from: 0, to: context.bytesPerRow * image.height, by: 4) {
            let alpha = Double(pixels[offset + 3])
            guard alpha > 0 else { continue }
            let (red, green, blue) = grade(Double(pixels[offset]) / alpha,
                                           Double(pixels[offset + 1]) / alpha,
                                           Double(pixels[offset + 2]) / alpha)
            pixels[offset] = premultiplied(red, alpha)
            pixels[offset + 1] = premultiplied(green, alpha)
            pixels[offset + 2] = premultiplied(blue, alpha)
        }

        return context.makeImage().map { UIImage(cgImage: $0) }
    }

    private static func grade(_ red: Double, _ green: Double, _ blue: Double) -> (Double, Double, Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2
        var hue = 0.0
        if delta > 0 {
            if maximum == red { hue = (green - blue) / delta }
            else if maximum == green { hue = 2 + (blue - red) / delta }
            else { hue = 4 + (red - green) / delta }
        }
        hue = (hue * 60 + 360).truncatingRemainder(dividingBy: 360)
        let saturation = delta > 0 ? delta / (1 - abs(2 * lightness - 1)) : 0
        let upper = anchors.firstIndex { $0.hue > hue } ?? (anchors.count - 1)
        let left = anchors[upper - 1]
        let right = anchors[upper]
        let weight = (hue - left.hue) / (right.hue - left.hue)
        let influence = min(1, saturation * 2.2)
        let target = mix(left.target, right.target, weight)
        let adjustedHue = (hue + (target - hue) * influence).truncatingRemainder(dividingBy: 360)
        let adjustedSaturation = saturation * (1 - (1 - mix(left.saturation, right.saturation, weight)) * influence)
        let adjustedLightness = min(1, max(0, lightness + mix(left.lightness, right.lightness, weight) * influence))
        let chroma = (1 - abs(2 * adjustedLightness - 1)) * adjustedSaturation
        let middle = chroma * (1 - abs((adjustedHue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let channels: (Double, Double, Double)
        switch Int(adjustedHue / 60) {
        case 0: channels = (chroma, middle, 0)
        case 1: channels = (middle, chroma, 0)
        case 2: channels = (0, chroma, middle)
        case 3: channels = (0, middle, chroma)
        case 4: channels = (middle, 0, chroma)
        default: channels = (chroma, 0, middle)
        }
        let offset = adjustedLightness - chroma / 2
        let warmth = (1 - influence) * max(0, (lightness - 0.6) / 0.4) / 255
        return (channels.0 + offset - 8 * warmth, channels.1 + offset - 12 * warmth, channels.2 + offset - 20 * warmth)
    }

    private static func mix(_ a: Double, _ b: Double, _ weight: Double) -> Double { a + (b - a) * weight }

    private static func premultiplied(_ channel: Double, _ alpha: Double) -> UInt8 {
        UInt8((min(1, max(0, channel)) * alpha).rounded())
    }
}
