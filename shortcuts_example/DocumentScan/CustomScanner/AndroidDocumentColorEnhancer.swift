import CoreImage
import Dispatch
import Foundation

/// White balance scales estimated from the bright (paper) pixels.
nonisolated struct AndroidDocumentWhiteBalance: Equatable, Sendable {
    let red: Float
    let green: Float
    let blue: Float

    static let neutral = AndroidDocumentWhiteBalance(
        red: 1,
        green: 1,
        blue: 1
    )
}

nonisolated struct AndroidDocumentEnhancePhase: Equatable, Sendable {
    let name: String
    let milliseconds: Double
}

/// Wall time of every pipeline phase, mirroring Android's `Profiler` hook.
nonisolated struct AndroidDocumentEnhanceProfile: Equatable, Sendable {
    private(set) var phases: [AndroidDocumentEnhancePhase] = []
    private var startedAt = ProcessInfo.processInfo.systemUptime

    init() {}

    mutating func finish(_ name: String) {
        let now = ProcessInfo.processInfo.systemUptime
        phases.append(
            AndroidDocumentEnhancePhase(
                name: name,
                milliseconds: (now - startedAt) * 1_000
            )
        )
        startedAt = now
    }

    func milliseconds(of name: String) -> Double {
        phases.first { $0.name == name }?.milliseconds ?? 0
    }

    var totalMilliseconds: Double {
        phases.reduce(0) { $0 + $1.milliseconds }
    }

    var summary: String {
        phases
            .map { "\($0.name)=" + String(format: "%.1f", $0.milliseconds) }
            .joined(separator: " ")
    }
}

nonisolated struct AndroidDocumentColorPerformance: Equatable, Sendable {
    let backend: UVDocWarpBackend
    let statisticsMilliseconds: Double
    let applyMilliseconds: Double
    let phaseSummary: String
}

/// Model-free document image enhancement ("scan look").
///
/// The whole pipeline runs on plain pixel arrays so it can be unit-tested
/// without a camera or a GPU:
///
///  1. Global white balance from the bright (paper) pixels.
///  2. Local background estimation: luminance → downscale → morphological
///     closing (fills text and thin lines) → box blur. The result is the
///     estimated paper brightness at every point, shadows and vignetting
///     included.
///  3. Flattening: luminance is divided by the local background so paper
///     lands on ``paperTarget`` everywhere. Gain is clamped and the
///     background is floored at a fraction of the global paper level, so
///     large dark areas (photos, filled graphics) are brightened moderately
///     instead of washed out.
///  4. Unsharp mask on the flattened luminance, with a small threshold so
///     flat paper noise is not amplified.
///  5. Tone: black-point stretch, chroma-aware paper whitening, mild ink
///     darkening and a mild saturation boost. Everything is applied as a
///     per-pixel luminance scale so hue is preserved.
///
/// Finger/shadow-object removal and curved-page dewarp stay with UVDoc; this
/// is the cheap, offline win for review, save and OCR.
nonisolated enum AndroidDocumentColorMath {
    private static let maximumStatisticsSamples = 120_000

    /// Long side of the downscaled map used for background estimation.
    static let backgroundMapLongSide = 300

    /// Closing radius on the small map. 5 px at ~1/8 scale ≈ 80 px at full
    /// resolution — covers body text, bold headings and rules so they are
    /// not mistaken for paper shading.
    static let backgroundCloseRadius = 5
    static let backgroundBlurRadius = 6
    static let backgroundBlurPasses = 2

    /// Luminance the estimated paper is mapped to after flattening.
    static let paperTarget: Float = 246

    /// The background estimate never drops below this × global paper level.
    /// This is the shadow-vs-dark-object trade-off: a large uniformly dark
    /// area is indistinguishable from a deep shadow, so anything darker than
    /// this fraction of the paper is treated as an object and brightened only
    /// up to ``gainMaximum``. 0.7 keeps black panels (and white-on-black text)
    /// readable while still fully removing shadows up to ~30% darkening.
    static let backgroundFloorRatio: Float = 0.7
    static let gainMinimum: Float = 0.78
    static let gainMaximum: Float = 2.0

    static let sharpenRadius = 2
    static let sharpenAmount: Float = 0.65
    static let sharpenThreshold = 6

    static let blackPointMaximum = 48
    static let saturationBoost: Float = 1.10
    static let paperWhitenStrength: Float = 0.9
    static let inkDarkenStrength: Float = 0.15

    // MARK: - Entry points

    static func enhance(_ source: ScannerRGBAImage) -> ScannerRGBAImage {
        var profile = AndroidDocumentEnhanceProfile()
        return enhance(source, profile: &profile)
    }

    static func enhance(
        _ source: ScannerRGBAImage,
        profile: inout AndroidDocumentEnhanceProfile
    ) -> ScannerRGBAImage {
        var image = source
        let width = image.width
        let height = image.height
        let pixelCount = width * height
        guard pixelCount > 0 else {
            return image
        }

        let balance = whiteBalance(image.bytes, pixelCount: pixelCount)
        profile.finish("whiteBalance")

        var luminanceMap = [UInt8](repeating: 0, count: pixelCount)
        image.bytes.withUnsafeBufferPointer { pixels in
            luminanceMap.withUnsafeMutableBufferPointer { output in
                parallelRows(height) { firstRow, lastRow in
                    for index in (firstRow * width) ..< (lastRow * width) {
                        let offset = index * 4
                        output[index] = roundedByte(
                            luminance(
                                red: Float(pixels[offset]) * balance.red,
                                green: Float(pixels[offset + 1])
                                    * balance.green,
                                blue: Float(pixels[offset + 2])
                                    * balance.blue
                            )
                        )
                    }
                }
            }
        }
        profile.finish("luminance")

        let background = estimateBackground(
            luminanceMap,
            width: width,
            height: height
        )
        profile.finish("background")

        var flattened = [UInt8](repeating: 0, count: pixelCount)
        flatten(
            luminanceMap,
            into: &flattened,
            width: width,
            height: height,
            background: background
        )
        profile.finish("flatten")

        unsharpMask(&flattened, width: width, height: height)
        profile.finish("unsharp")

        applyTone(
            to: &image,
            flattened: flattened,
            balance: balance,
            width: width,
            height: height
        )
        profile.finish("tone")

        return image
    }

    /// Runs the pipeline on a small synthetic page so the hot loops are
    /// resident and the allocator is warm before the first real capture.
    /// Call it off the main actor while the camera preview is starting.
    static func warmUp() {
        let width = 320
        let height = 360
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let stroke = y >= 40
                    && y < height - 40
                    && (y - 40) % 24 < 3
                    && x >= 30
                    && x < width - 30
                let value = stroke
                    ? 35
                    : 150 + (80 * x) / width + ((x * 7 + y * 13) % 11)
                let offset = ((y * width) + x) * 4
                bytes[offset] = UInt8(clamping: value)
                bytes[offset + 1] = UInt8(clamping: value)
                bytes[offset + 2] = UInt8(clamping: value)
            }
        }
        guard let image = try? ScannerRGBAImage(
            width: width,
            height: height,
            bytes: bytes
        ) else {
            return
        }
        for _ in 0 ..< 2 {
            _ = enhance(image)
        }
    }

    // MARK: - Parallel row bands

    /// Runs `block` over row bands in parallel. Bands are small and claimed
    /// dynamically by `concurrentPerform`, so the performance cores simply
    /// take more bands and an efficiency core never holds up the pass.
    static func parallelRows(
        _ height: Int,
        _ block: (_ firstRow: Int, _ lastRow: Int) -> Void
    ) {
        guard height > 0 else {
            return
        }
        let workers = min(
            max(ProcessInfo.processInfo.activeProcessorCount, 1),
            8
        )
        let bandRows = max(4, height / (workers * 12))
        let bands = (height + bandRows - 1) / bandRows
        guard workers > 1, bands > 1 else {
            block(0, height)
            return
        }
        withoutActuallyEscaping(block) { escapableBlock in
            DispatchQueue.concurrentPerform(iterations: bands) { band in
                let firstRow = band * bandRows
                escapableBlock(firstRow, min(firstRow + bandRows, height))
            }
        }
    }

    // MARK: - White balance

    static func whiteBalance(
        _ bytes: [UInt8],
        pixelCount: Int
    ) -> AndroidDocumentWhiteBalance {
        guard pixelCount > 0 else {
            return .neutral
        }
        let step = max(pixelCount / maximumStatisticsSamples, 1)
        var histogram = [Int](repeating: 0, count: 256)
        var sampleCount = 0
        var pixelIndex = 0
        while pixelIndex < pixelCount {
            let offset = pixelIndex * 4
            histogram[
                roundedIndex(
                    luminance(
                        red: Float(bytes[offset]),
                        green: Float(bytes[offset + 1]),
                        blue: Float(bytes[offset + 2])
                    )
                )
            ] += 1
            sampleCount += 1
            pixelIndex += step
        }
        guard sampleCount > 0 else {
            return .neutral
        }

        let brightThreshold = percentile(
            histogram,
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
            let red = Int(bytes[offset])
            let green = Int(bytes[offset + 1])
            let blue = Int(bytes[offset + 2])
            let value = roundedIndex(
                luminance(
                    red: Float(red),
                    green: Float(green),
                    blue: Float(blue)
                )
            )
            if value >= brightThreshold {
                brightRed += Int64(red)
                brightGreen += Int64(green)
                brightBlue += Int64(blue)
                brightCount += 1
            }
            pixelIndex += step
        }
        guard brightCount > 0 else {
            return .neutral
        }

        let averageRed = Float(brightRed) / Float(brightCount)
        let averageGreen = Float(brightGreen) / Float(brightCount)
        let averageBlue = Float(brightBlue) / Float(brightCount)
        let target = (averageRed + averageGreen + averageBlue) / 3
        return AndroidDocumentWhiteBalance(
            red: channelScale(target: target, value: averageRed),
            green: channelScale(target: target, value: averageGreen),
            blue: channelScale(target: target, value: averageBlue)
        )
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

    // MARK: - Background estimation

    nonisolated struct BackgroundMap: Equatable, Sendable {
        var values: [Float]
        let width: Int
        let height: Int
        let scale: Int
        let floor: Float
    }

    static func estimateBackground(
        _ luminanceMap: [UInt8],
        width: Int,
        height: Int
    ) -> BackgroundMap {
        let scale = max(
            Int(
                (Float(max(width, height))
                    / Float(backgroundMapLongSide)).rounded(.up)
            ),
            1
        )
        let mapWidth = (width + scale - 1) / scale
        let mapHeight = (height + scale - 1) / scale
        var small = [Float](repeating: 0, count: mapWidth * mapHeight)

        luminanceMap.withUnsafeBufferPointer { source in
            small.withUnsafeMutableBufferPointer { output in
                parallelRows(mapHeight) { firstRow, lastRow in
                    for mapY in firstRow ..< lastRow {
                        let y0 = mapY * scale
                        let y1 = min(y0 + scale, height)
                        for mapX in 0 ..< mapWidth {
                            let x0 = mapX * scale
                            let x1 = min(x0 + scale, width)
                            var sum = 0
                            var count = 0
                            for y in y0 ..< y1 {
                                let row = y * width
                                for x in x0 ..< x1 {
                                    sum += Int(source[row + x])
                                    count += 1
                                }
                            }
                            output[mapY * mapWidth + mapX] =
                                Float(sum) / Float(max(count, 1))
                        }
                    }
                }
            }
        }

        // Morphological closing (dilate → erode) removes dark features
        // smaller than the window: text, rules, table borders.
        var temporary = [Float](repeating: 0, count: mapWidth * mapHeight)
        var scratch = [Float](repeating: 0, count: mapWidth * mapHeight)
        separableExtreme(
            small,
            into: &temporary,
            scratch: &scratch,
            width: mapWidth,
            height: mapHeight,
            radius: backgroundCloseRadius,
            useMaximum: true
        )
        separableExtreme(
            temporary,
            into: &small,
            scratch: &scratch,
            width: mapWidth,
            height: mapHeight,
            radius: backgroundCloseRadius,
            useMaximum: false
        )

        for _ in 0 ..< backgroundBlurPasses {
            boxBlur(
                &small,
                temporary: &temporary,
                width: mapWidth,
                height: mapHeight,
                radius: backgroundBlurRadius
            )
        }

        let paperLevel = percentile(of: small, ratio: 0.75)
        return BackgroundMap(
            values: small,
            width: mapWidth,
            height: mapHeight,
            scale: scale,
            floor: paperLevel * backgroundFloorRatio
        )
    }

    static func separableExtreme(
        _ source: [Float],
        into destination: inout [Float],
        scratch: inout [Float],
        width: Int,
        height: Int,
        radius: Int,
        useMaximum: Bool
    ) {
        source.withUnsafeBufferPointer { input in
            scratch.withUnsafeMutableBufferPointer { middle in
                for y in 0 ..< height {
                    let row = y * width
                    for x in 0 ..< width {
                        var value = input[row + x]
                        for k in max(0, x - radius)
                            ... min(width - 1, x + radius) {
                            let candidate = input[row + k]
                            if useMaximum
                                ? candidate > value
                                : candidate < value {
                                value = candidate
                            }
                        }
                        middle[row + x] = value
                    }
                }
            }
        }
        scratch.withUnsafeBufferPointer { middle in
            destination.withUnsafeMutableBufferPointer { output in
                for y in 0 ..< height {
                    let row = y * width
                    for x in 0 ..< width {
                        var value = middle[row + x]
                        for k in max(0, y - radius)
                            ... min(height - 1, y + radius) {
                            let candidate = middle[k * width + x]
                            if useMaximum
                                ? candidate > value
                                : candidate < value {
                                value = candidate
                            }
                        }
                        output[row + x] = value
                    }
                }
            }
        }
    }

    /// Box blur of `map` in place (through `temporary`) with clamped edges.
    static func boxBlur(
        _ map: inout [Float],
        temporary: inout [Float],
        width: Int,
        height: Int,
        radius: Int
    ) {
        map.withUnsafeMutableBufferPointer { values in
            temporary.withUnsafeMutableBufferPointer { scratch in
                for y in 0 ..< height {
                    let row = y * width
                    for x in 0 ..< width {
                        var sum: Float = 0
                        var count = 0
                        for k in max(0, x - radius)
                            ... min(width - 1, x + radius) {
                            sum += values[row + k]
                            count += 1
                        }
                        scratch[row + x] = sum / Float(count)
                    }
                }
                for y in 0 ..< height {
                    let row = y * width
                    for x in 0 ..< width {
                        var sum: Float = 0
                        var count = 0
                        for k in max(0, y - radius)
                            ... min(height - 1, y + radius) {
                            sum += scratch[k * width + x]
                            count += 1
                        }
                        values[row + x] = sum / Float(count)
                    }
                }
            }
        }
    }

    // MARK: - Flattening

    static func flatten(
        _ luminanceMap: [UInt8],
        into output: inout [UInt8],
        width: Int,
        height: Int,
        background: BackgroundMap
    ) {
        let scale = Float(background.scale)
        let mapWidth = background.width
        let mapHeight = background.height

        var leftIndex = [Int](repeating: 0, count: width)
        var rightIndex = [Int](repeating: 0, count: width)
        var horizontalWeight = [Float](repeating: 0, count: width)
        for x in 0 ..< width {
            let mapped = min(
                max((Float(x) + 0.5) / scale - 0.5, 0),
                Float(mapWidth - 1)
            )
            let index = min(max(Int(mapped), 0), mapWidth - 1)
            leftIndex[x] = index
            rightIndex[x] = min(index + 1, mapWidth - 1)
            horizontalWeight[x] = mapped - Float(index)
        }

        let floorValue = background.floor
        luminanceMap.withUnsafeBufferPointer { source in
        background.values.withUnsafeBufferPointer { map in
        leftIndex.withUnsafeBufferPointer { left in
        rightIndex.withUnsafeBufferPointer { right in
        horizontalWeight.withUnsafeBufferPointer { weightX in
        output.withUnsafeMutableBufferPointer { destination in
            parallelRows(height) { firstRow, lastRow in
                for y in firstRow ..< lastRow {
                    let mappedY = min(
                        max((Float(y) + 0.5) / scale - 0.5, 0),
                        Float(mapHeight - 1)
                    )
                    let topIndex = min(max(Int(mappedY), 0), mapHeight - 1)
                    let bottomIndex = min(topIndex + 1, mapHeight - 1)
                    let weightY = mappedY - Float(topIndex)
                    let topRow = topIndex * mapWidth
                    let bottomRow = bottomIndex * mapWidth
                    let outputRow = y * width
                    for x in 0 ..< width {
                        let weight = weightX[x]
                        let top = map[topRow + left[x]] * (1 - weight)
                            + map[topRow + right[x]] * weight
                        let bottom = map[bottomRow + left[x]] * (1 - weight)
                            + map[bottomRow + right[x]] * weight
                        let estimate = max(
                            max(top * (1 - weightY) + bottom * weightY,
                                floorValue),
                            1
                        )
                        let gain = min(
                            max(paperTarget / estimate, gainMinimum),
                            gainMaximum
                        )
                        destination[outputRow + x] = roundedByte(
                            Float(source[outputRow + x]) * gain
                        )
                    }
                }
            }
        }
        }
        }
        }
        }
        }
    }

    // MARK: - Sharpening

    static func unsharpMask(
        _ map: inout [UInt8],
        width: Int,
        height: Int
    ) {
        let count = width * height
        guard count > 0 else {
            return
        }
        var blurred = [UInt8](repeating: 0, count: count)
        var doubleBlurred = [UInt8](repeating: 0, count: count)
        var temporary = [UInt8](repeating: 0, count: count)
        // Two box passes ≈ Gaussian.
        boxBlurBytes(
            map,
            into: &blurred,
            temporary: &temporary,
            width: width,
            height: height,
            radius: sharpenRadius
        )
        boxBlurBytes(
            blurred,
            into: &doubleBlurred,
            temporary: &temporary,
            width: width,
            height: height,
            radius: sharpenRadius
        )

        map.withUnsafeMutableBufferPointer { values in
            doubleBlurred.withUnsafeBufferPointer { blur in
                parallelRows(height) { firstRow, lastRow in
                    for index in (firstRow * width) ..< (lastRow * width) {
                        let value = Int(values[index])
                        let difference = value - Int(blur[index])
                        if difference > sharpenThreshold
                            || difference < -sharpenThreshold {
                            values[index] = roundedByte(
                                Float(value)
                                    + sharpenAmount * Float(difference)
                            )
                        }
                    }
                }
            }
        }
    }

    /// Separable box blur with clamped edges and running sums. `source` and
    /// `destination` must be distinct; `temporary` must be distinct from both.
    static func boxBlurBytes(
        _ source: [UInt8],
        into destination: inout [UInt8],
        temporary: inout [UInt8],
        width: Int,
        height: Int,
        radius: Int
    ) {
        let window = 2 * radius + 1
        let half = window / 2

        source.withUnsafeBufferPointer { input in
            temporary.withUnsafeMutableBufferPointer { scratch in
                parallelRows(height) { firstRow, lastRow in
                    for y in firstRow ..< lastRow {
                        let row = y * width
                        var sum = 0
                        for k in -radius ... radius {
                            sum += Int(
                                input[row + min(max(k, 0), width - 1)]
                            )
                        }
                        for x in 0 ..< width {
                            scratch[row + x] = UInt8(
                                clamping: (sum + half) / window
                            )
                            let added = row + min(x + radius + 1, width - 1)
                            let removed = row + max(x - radius, 0)
                            sum += Int(input[added]) - Int(input[removed])
                        }
                    }
                }
            }
        }

        // Vertical pass over column bands, each with its own running sums.
        temporary.withUnsafeBufferPointer { scratch in
            destination.withUnsafeMutableBufferPointer { output in
                parallelRows(width) { firstColumn, lastColumn in
                    let bandWidth = lastColumn - firstColumn
                    guard bandWidth > 0 else {
                        return
                    }
                    var columnSums = [Int](repeating: 0, count: bandWidth)
                    for k in -radius ... radius {
                        let row = min(max(k, 0), height - 1) * width
                        for x in 0 ..< bandWidth {
                            columnSums[x] += Int(
                                scratch[row + firstColumn + x]
                            )
                        }
                    }
                    for y in 0 ..< height {
                        let outputRow = y * width + firstColumn
                        for x in 0 ..< bandWidth {
                            output[outputRow + x] = UInt8(
                                clamping: (columnSums[x] + half) / window
                            )
                        }
                        let addedRow =
                            min(y + radius + 1, height - 1) * width
                            + firstColumn
                        let removedRow =
                            max(y - radius, 0) * width + firstColumn
                        for x in 0 ..< bandWidth {
                            columnSums[x] += Int(scratch[addedRow + x])
                                - Int(scratch[removedRow + x])
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tone

    private static func applyTone(
        to image: inout ScannerRGBAImage,
        flattened: [UInt8],
        balance: AndroidDocumentWhiteBalance,
        width: Int,
        height: Int
    ) {
        let pixelCount = width * height
        let blackPoint = min(
            percentile(of: flattened, count: pixelCount, ratio: 0.01),
            blackPointMaximum
        )
        let range = Float(255 - blackPoint)

        var targetLuminance = [Float](repeating: 0, count: 256)
        var whiten = [Float](repeating: 0, count: 256)
        var inkKeep = [Float](repeating: 0, count: 256)
        for value in 0 ... 255 {
            let normalized = min(
                max((Float(value) - Float(blackPoint)) / range, 0),
                1
            )
            targetLuminance[value] = normalized * 255
            whiten[value] = smoothStep(
                edge0: 0.84,
                edge1: 0.97,
                value: normalized
            ) * paperWhitenStrength
            inkKeep[value] = 1
                - min(max((0.4 - normalized) / 0.4, 0), 1)
                * inkDarkenStrength
        }

        image.bytes.withUnsafeMutableBufferPointer { pixels in
        flattened.withUnsafeBufferPointer { flat in
        targetLuminance.withUnsafeBufferPointer { targetLUT in
        whiten.withUnsafeBufferPointer { whitenLUT in
        inkKeep.withUnsafeBufferPointer { inkKeepLUT in
            parallelRows(height) { firstRow, lastRow in
                for index in (firstRow * width) ..< (lastRow * width) {
                    let offset = index * 4
                    var red = Float(pixels[offset]) * balance.red
                    var green = Float(pixels[offset + 1]) * balance.green
                    var blue = Float(pixels[offset + 2]) * balance.blue

                    let sourceLuminance = max(
                        luminance(red: red, green: green, blue: blue),
                        1
                    )
                    let flatValue = Int(flat[index])
                    let target = targetLUT[flatValue]
                    let luminanceScale = target / sourceLuminance
                    red *= luminanceScale
                    green *= luminanceScale
                    blue *= luminanceScale

                    red = target + (red - target) * saturationBoost
                    green = target + (green - target) * saturationBoost
                    blue = target + (blue - target) * saturationBoost

                    let chroma = max(max(red, green), blue)
                        - min(min(red, green), blue)
                    let paperWhiten = whitenLUT[flatValue]
                        * (1 - min(max(chroma / 110, 0), 0.75))
                    red += (255 - red) * paperWhiten
                    green += (255 - green) * paperWhiten
                    blue += (255 - blue) * paperWhiten

                    let keep = inkKeepLUT[flatValue]
                    pixels[offset] = roundedByte(red * keep)
                    pixels[offset + 1] = roundedByte(green * keep)
                    pixels[offset + 2] = roundedByte(blue * keep)
                }
            }
        }
        }
        }
        }
        }
    }

    // MARK: - Helpers

    static func luminance(red: Float, green: Float, blue: Float) -> Float {
        0.299 * red + 0.587 * green + 0.114 * blue
    }

    private static func percentile(
        _ histogram: [Int],
        sampleCount: Int,
        ratio: Float
    ) -> Int {
        let target = min(
            max(Int((Float(sampleCount) * ratio).rounded()), 0),
            max(sampleCount - 1, 0)
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

    static func percentile(
        of map: [UInt8],
        count: Int,
        ratio: Float
    ) -> Int {
        guard count > 0 else {
            return 0
        }
        let step = max(count / maximumStatisticsSamples, 1)
        var histogram = [Int](repeating: 0, count: 256)
        var sampleCount = 0
        var index = 0
        while index < count {
            histogram[Int(map[index])] += 1
            sampleCount += 1
            index += step
        }
        guard sampleCount > 0 else {
            return 0
        }
        return percentile(
            histogram,
            sampleCount: sampleCount,
            ratio: ratio
        )
    }

    static func percentile(of values: [Float], ratio: Float) -> Float {
        guard !values.isEmpty else {
            return 255
        }
        let sorted = values.sorted()
        let index = min(
            max(Int(Float(sorted.count) * ratio), 0),
            sorted.count - 1
        )
        return sorted[index]
    }

    static func smoothStep(
        edge0: Float,
        edge1: Float,
        value: Float
    ) -> Float {
        let amount = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return amount * amount * (3 - 2 * amount)
    }

    private static func roundedIndex(_ value: Float) -> Int {
        min(max(Int(value.rounded()), 0), 255)
    }

    private static func roundedByte(_ value: Float) -> UInt8 {
        UInt8(clamping: Int(value.rounded()))
    }
}

actor AndroidDocumentColorEnhancer: DocumentImageEnhancing {
    private let imageBridge = ScannerCIImageBridge()
    private(set) var lastPerformance: AndroidDocumentColorPerformance?

    init() {
        lastPerformance = nil
    }

    func enhance(_ image: CIImage) async throws -> CIImage {
        let source = try imageBridge.rgbaImage(from: image)
        return imageBridge.ciImage(from: enhancePixels(source))
    }

    func enhancePixels(
        _ source: ScannerRGBAImage
    ) -> ScannerRGBAImage {
        var profile = AndroidDocumentEnhanceProfile()
        let enhanced = AndroidDocumentColorMath.enhance(
            source,
            profile: &profile
        )
        let statistics = profile.milliseconds(of: "whiteBalance")
            + profile.milliseconds(of: "luminance")
            + profile.milliseconds(of: "background")
        lastPerformance = AndroidDocumentColorPerformance(
            backend: .cpu,
            statisticsMilliseconds: statistics,
            applyMilliseconds: profile.totalMilliseconds - statistics,
            phaseSummary: profile.summary
        )
        return enhanced
    }

    /// Runs the pipeline once on a synthetic page so the first real capture
    /// does not pay for cold code paths and allocator growth.
    func warmUp() {
        AndroidDocumentColorMath.warmUp()
    }
}
