import CoreImage
import Foundation

nonisolated struct AndroidDocumentColorParameters: Equatable, Sendable {
    let blackPoint: Int
    let whitePoint: Int
    let redScale: Float
    let greenScale: Float
    let blueScale: Float
    let gamma: Double
    let saturationBoost: Float

    var toneRange: Float {
        Float(max(whitePoint - blackPoint, 1))
    }
}

nonisolated struct AndroidDocumentColorPerformance: Equatable, Sendable {
    let backend: UVDocWarpBackend
    let statisticsMilliseconds: Double
    let applyMilliseconds: Double
}

nonisolated enum AndroidDocumentColorMath {
    private static let maximumStatisticsSamples = 120_000
    private static let minimumToneRange = 48
    private static let documentGamma = 0.82
    private static let saturationBoost: Float = 1.08

    static func enhance(_ source: ScannerRGBAImage) -> ScannerRGBAImage {
        enhance(source, parameters: parameters(for: source))
    }

    static func enhance(
        _ source: ScannerRGBAImage,
        parameters: AndroidDocumentColorParameters
    ) -> ScannerRGBAImage {
        var result = source

        for pixelIndex in 0 ..< source.width * source.height {
            let offset = pixelIndex * 4
            var red = Float(source.bytes[offset]) * parameters.redScale
            var green =
                Float(source.bytes[offset + 1]) * parameters.greenScale
            var blue =
                Float(source.bytes[offset + 2]) * parameters.blueScale

            let balancedLuminance = max(
                luminance(red: red, green: green, blue: blue),
                1
            )
            let normalized = min(
                max(
                    (
                        balancedLuminance
                        - Float(parameters.blackPoint)
                    ) / parameters.toneRange,
                    0
                ),
                1
            )
            let toned = Float(
                pow(Double(normalized), parameters.gamma)
            )
            let targetLuminance = toned * 255
            let luminanceScale = targetLuminance / balancedLuminance

            red *= luminanceScale
            green *= luminanceScale
            blue *= luminanceScale

            red = targetLuminance
                + (red - targetLuminance) * parameters.saturationBoost
            green = targetLuminance
                + (green - targetLuminance) * parameters.saturationBoost
            blue = targetLuminance
                + (blue - targetLuminance) * parameters.saturationBoost

            let chroma = max(red, green, blue) - min(red, green, blue)
            let paperWhitening =
                smoothStep(edge0: 0.68, edge1: 0.96, value: toned)
                * (
                    1
                    - min(max(chroma / 110, 0), 0.75)
                )
                * 0.58
            red += (255 - red) * paperWhitening
            green += (255 - green) * paperWhitening
            blue += (255 - blue) * paperWhitening

            let textDarkening =
                min(max((0.36 - toned) / 0.36, 0), 1) * 0.12
            red *= 1 - textDarkening
            green *= 1 - textDarkening
            blue *= 1 - textDarkening

            result.bytes[offset] = roundedByte(red)
            result.bytes[offset + 1] = roundedByte(green)
            result.bytes[offset + 2] = roundedByte(blue)
            result.bytes[offset + 3] = source.bytes[offset + 3]
        }

        return result
    }

    static func parameters(
        for image: ScannerRGBAImage
    ) -> AndroidDocumentColorParameters {
        computeStatistics(image)
    }

    private static func computeStatistics(
        _ image: ScannerRGBAImage
    ) -> AndroidDocumentColorParameters {
        let pixelCount = image.width * image.height
        let sampleStep = max(pixelCount / maximumStatisticsSamples, 1)
        var rawHistogram = [Int](repeating: 0, count: 256)
        var sampleCount = 0
        var pixelIndex = 0

        while pixelIndex < pixelCount {
            let offset = pixelIndex * 4
            let value = luminance(
                red: Float(image.bytes[offset]),
                green: Float(image.bytes[offset + 1]),
                blue: Float(image.bytes[offset + 2])
            )
            rawHistogram[roundedHistogramIndex(value)] += 1
            sampleCount += 1
            pixelIndex += sampleStep
        }

        guard sampleCount > 0 else {
            return AndroidDocumentColorParameters(
                blackPoint: 0,
                whitePoint: 255,
                redScale: 1,
                greenScale: 1,
                blueScale: 1,
                gamma: documentGamma,
                saturationBoost: saturationBoost
            )
        }

        let brightThreshold = percentile(
            rawHistogram,
            sampleCount: sampleCount,
            ratio: 0.80
        )
        var brightCount = 0
        var brightRed: Int64 = 0
        var brightGreen: Int64 = 0
        var brightBlue: Int64 = 0
        pixelIndex = 0

        while pixelIndex < pixelCount {
            let offset = pixelIndex * 4
            let red = Int(image.bytes[offset])
            let green = Int(image.bytes[offset + 1])
            let blue = Int(image.bytes[offset + 2])
            let value = luminance(
                red: Float(red),
                green: Float(green),
                blue: Float(blue)
            )
            if roundedHistogramIndex(value) >= brightThreshold {
                brightRed += Int64(red)
                brightGreen += Int64(green)
                brightBlue += Int64(blue)
                brightCount += 1
            }
            pixelIndex += sampleStep
        }

        let redScale: Float
        let greenScale: Float
        let blueScale: Float
        if brightCount > 0 {
            let averageRed = Float(brightRed) / Float(brightCount)
            let averageGreen = Float(brightGreen) / Float(brightCount)
            let averageBlue = Float(brightBlue) / Float(brightCount)
            let target =
                (averageRed + averageGreen + averageBlue) / 3
            redScale = channelScale(target: target, value: averageRed)
            greenScale = channelScale(target: target, value: averageGreen)
            blueScale = channelScale(target: target, value: averageBlue)
        } else {
            redScale = 1
            greenScale = 1
            blueScale = 1
        }

        var balancedHistogram = [Int](repeating: 0, count: 256)
        pixelIndex = 0
        while pixelIndex < pixelCount {
            let offset = pixelIndex * 4
            let value = luminance(
                red: Float(image.bytes[offset]) * redScale,
                green: Float(image.bytes[offset + 1]) * greenScale,
                blue: Float(image.bytes[offset + 2]) * blueScale
            )
            balancedHistogram[roundedHistogramIndex(value)] += 1
            pixelIndex += sampleStep
        }

        var blackPoint = percentile(
            balancedHistogram,
            sampleCount: sampleCount,
            ratio: 0.01
        )
        var whitePoint = percentile(
            balancedHistogram,
            sampleCount: sampleCount,
            ratio: 0.985
        )
        if whitePoint - blackPoint < minimumToneRange {
            let middle = (blackPoint + whitePoint) / 2
            blackPoint = max(middle - minimumToneRange / 2, 0)
            whitePoint = min(middle + minimumToneRange / 2, 255)
        }

        return AndroidDocumentColorParameters(
            blackPoint: blackPoint,
            whitePoint: whitePoint,
            redScale: redScale,
            greenScale: greenScale,
            blueScale: blueScale,
            gamma: documentGamma,
            saturationBoost: saturationBoost
        )
    }

    private static func percentile(
        _ histogram: [Int],
        sampleCount: Int,
        ratio: Float
    ) -> Int {
        let target = min(
            max(Int((Float(sampleCount) * ratio).rounded()), 0),
            sampleCount - 1
        )
        var cumulative = 0
        for index in histogram.indices {
            cumulative += histogram[index]
            if cumulative > target {
                return index
            }
        }
        return 255
    }

    private static func channelScale(
        target: Float,
        value: Float
    ) -> Float {
        guard value > 1 else {
            return 1
        }
        return min(max(target / value, 0.82), 1.22)
    }

    private static func luminance(
        red: Float,
        green: Float,
        blue: Float
    ) -> Float {
        0.299 * red + 0.587 * green + 0.114 * blue
    }

    private static func smoothStep(
        edge0: Float,
        edge1: Float,
        value: Float
    ) -> Float {
        let amount = min(
            max((value - edge0) / (edge1 - edge0), 0),
            1
        )
        return amount * amount * (3 - 2 * amount)
    }

    private static func roundedHistogramIndex(_ value: Float) -> Int {
        min(max(Int(value.rounded()), 0), 255)
    }

    private static func roundedByte(_ value: Float) -> UInt8 {
        UInt8(clamping: Int(value.rounded()))
    }
}

actor AndroidDocumentColorEnhancer: DocumentImageEnhancing {
    private let imageBridge = ScannerCIImageBridge()
    private let metalSampler: AndroidMetalImageSampler?
    private(set) var lastPerformance: AndroidDocumentColorPerformance?

    init(preferMetal: Bool = true) {
        metalSampler = preferMetal
            ? try? AndroidMetalImageSampler()
            : nil
        lastPerformance = nil
    }

    init(metalSampler: AndroidMetalImageSampler?) {
        self.metalSampler = metalSampler
        lastPerformance = nil
    }

    func enhance(_ image: CIImage) async throws -> CIImage {
        let source = try imageBridge.rgbaImage(from: image)
        return imageBridge.ciImage(from: enhancePixels(source))
    }

    func enhancePixels(
        _ source: ScannerRGBAImage
    ) -> ScannerRGBAImage {
        var startedAt = ProcessInfo.processInfo.systemUptime
        let parameters = AndroidDocumentColorMath.parameters(for: source)
        let statisticsMilliseconds =
            ScannerDiagnostics.milliseconds(since: startedAt)

        startedAt = ProcessInfo.processInfo.systemUptime
        let enhanced: ScannerRGBAImage
        let backend: UVDocWarpBackend
        if let metalSampler {
            do {
                enhanced = try metalSampler.enhanceDocument(
                    source,
                    parameters: parameters
                )
                backend = .metal
            } catch {
                enhanced = AndroidDocumentColorMath.enhance(
                    source,
                    parameters: parameters
                )
                backend = .cpu
            }
        } else {
            enhanced = AndroidDocumentColorMath.enhance(
                source,
                parameters: parameters
            )
            backend = .cpu
        }
        lastPerformance = AndroidDocumentColorPerformance(
            backend: backend,
            statisticsMilliseconds: statisticsMilliseconds,
            applyMilliseconds:
                ScannerDiagnostics.milliseconds(since: startedAt)
        )
        return enhanced
    }
}
