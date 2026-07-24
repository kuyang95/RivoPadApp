import Foundation

nonisolated struct ScannerLetterboxTransform: Equatable, Sendable {
    let originalWidth: Int
    let originalHeight: Int
    let scaledWidth: Int
    let scaledHeight: Int
    let padX: Int
    let padY: Int
    let canvasSize: Int
}

nonisolated struct ScannerPreparedTensor: Equatable, Sendable {
    let values: [Float]
    let shape: [Int]
    let letterbox: ScannerLetterboxTransform?
}

/// Pixel operations whose coordinate and rounding rules are deliberately kept
/// independent from Core Image so Android/iOS parity can be tested directly.
nonisolated enum AndroidScannerImageMath {
    static func letterboxedRGBTensor(
        from image: ScannerRGBAImage,
        size: Int
    ) -> ScannerPreparedTensor {
        let scale = Float(size) / Float(max(image.width, image.height))
        let scaledWidth = max(Int(Float(image.width) * scale), 1)
        let scaledHeight = max(Int(Float(image.height) * scale), 1)
        let padX = (size - scaledWidth) / 2
        let padY = (size - scaledHeight) / 2
        let resized = resizeBilinear(
            image,
            width: scaledWidth,
            height: scaledHeight
        )

        let planeSize = size * size
        var tensor = [Float](repeating: 0, count: planeSize * 3)

        for y in 0 ..< scaledHeight {
            let destinationY = y + padY
            for x in 0 ..< scaledWidth {
                let destinationX = x + padX
                let sourceOffset = resized.byteOffset(x: x, y: y)
                let destinationIndex = destinationY * size + destinationX
                tensor[destinationIndex] =
                    Float(resized.bytes[sourceOffset]) / 255
                tensor[planeSize + destinationIndex] =
                    Float(resized.bytes[sourceOffset + 1]) / 255
                tensor[(planeSize * 2) + destinationIndex] =
                    Float(resized.bytes[sourceOffset + 2]) / 255
            }
        }

        return ScannerPreparedTensor(
            values: tensor,
            shape: [1, 3, size, size],
            letterbox: ScannerLetterboxTransform(
                originalWidth: image.width,
                originalHeight: image.height,
                scaledWidth: scaledWidth,
                scaledHeight: scaledHeight,
                padX: padX,
                padY: padY,
                canvasSize: size
            )
        )
    }

    static func stretchedRGBTensor(
        from image: ScannerRGBAImage,
        width: Int,
        height: Int
    ) -> ScannerPreparedTensor {
        let resized = resizeBilinear(image, width: width, height: height)
        let planeSize = width * height
        var tensor = [Float](repeating: 0, count: planeSize * 3)

        for index in 0 ..< planeSize {
            let sourceOffset = index * 4
            tensor[index] = Float(resized.bytes[sourceOffset]) / 255
            tensor[planeSize + index] =
                Float(resized.bytes[sourceOffset + 1]) / 255
            tensor[(planeSize * 2) + index] =
                Float(resized.bytes[sourceOffset + 2]) / 255
        }

        return ScannerPreparedTensor(
            values: tensor,
            shape: [1, 3, height, width],
            letterbox: nil
        )
    }

    /// Half-pixel-center bilinear resize with edge replication. The output is
    /// quantized back to RGBA8 before `/255`, matching Android Bitmap's
    /// `createScaledBitmap(..., filter = true)` data path.
    static func resizeBilinear(
        _ source: ScannerRGBAImage,
        width destinationWidth: Int,
        height destinationHeight: Int
    ) -> ScannerRGBAImage {
        precondition(destinationWidth > 0 && destinationHeight > 0)

        if source.width == destinationWidth,
           source.height == destinationHeight {
            return source
        }

        let sourceMaxX = Float(source.width - 1)
        let sourceMaxY = Float(source.height - 1)
        let xScale = Float(source.width) / Float(destinationWidth)
        let yScale = Float(source.height) / Float(destinationHeight)
        var output = [UInt8](
            repeating: 0,
            count: destinationWidth * destinationHeight * 4
        )

        for destinationY in 0 ..< destinationHeight {
            let mappedY = min(
                max(
                    (Float(destinationY) + 0.5) * yScale - 0.5,
                    0
                ),
                sourceMaxY
            )
            let y0 = Int(mappedY)
            let y1 = min(y0 + 1, source.height - 1)
            let yWeight = mappedY - Float(y0)

            for destinationX in 0 ..< destinationWidth {
                let mappedX = min(
                    max(
                        (Float(destinationX) + 0.5) * xScale - 0.5,
                        0
                    ),
                    sourceMaxX
                )
                let x0 = Int(mappedX)
                let x1 = min(x0 + 1, source.width - 1)
                let xWeight = mappedX - Float(x0)

                let topLeft = source.byteOffset(x: x0, y: y0)
                let topRight = source.byteOffset(x: x1, y: y0)
                let bottomLeft = source.byteOffset(x: x0, y: y1)
                let bottomRight = source.byteOffset(x: x1, y: y1)
                let destinationOffset =
                    ((destinationY * destinationWidth) + destinationX) * 4

                let weight00 = (1 - xWeight) * (1 - yWeight)
                let weight01 = xWeight * (1 - yWeight)
                let weight10 = (1 - xWeight) * yWeight
                let weight11 = xWeight * yWeight

                for channel in 0 ..< 4 {
                    let value =
                        weight00 * Float(source.bytes[topLeft + channel])
                        + weight01 * Float(source.bytes[topRight + channel])
                        + weight10 * Float(source.bytes[bottomLeft + channel])
                        + weight11 * Float(source.bytes[bottomRight + channel])
                    output[destinationOffset + channel] = UInt8(
                        clamping: Int(value.rounded())
                    )
                }
            }
        }

        // Dimensions and byte count are constructed together above.
        return try! ScannerRGBAImage(
            width: destinationWidth,
            height: destinationHeight,
            bytes: output
        )
    }

    static func normalizedLongEdge(
        _ image: ScannerRGBAImage,
        maximum: Int
    ) -> ScannerRGBAImage {
        let longEdge = max(image.width, image.height)
        guard longEdge > maximum else {
            return image
        }

        let scale = Float(maximum) / Float(longEdge)
        let width = max(Int(Float(image.width) * scale), 1)
        let height = max(Int(Float(image.height) * scale), 1)
        return resizeBilinear(image, width: width, height: height)
    }

    static func rotatedClockwise(
        _ image: ScannerRGBAImage,
        degrees: Int
    ) -> ScannerRGBAImage {
        let normalizedDegrees = ((degrees % 360) + 360) % 360
        guard normalizedDegrees != 0 else {
            return image
        }
        precondition(
            normalizedDegrees == 90
                || normalizedDegrees == 180
                || normalizedDegrees == 270
        )

        let destinationWidth = normalizedDegrees == 180
            ? image.width
            : image.height
        let destinationHeight = normalizedDegrees == 180
            ? image.height
            : image.width
        var output = [UInt8](
            repeating: 0,
            count: destinationWidth * destinationHeight * 4
        )

        for sourceY in 0 ..< image.height {
            for sourceX in 0 ..< image.width {
                let destinationX: Int
                let destinationY: Int
                switch normalizedDegrees {
                case 90:
                    destinationX = image.height - 1 - sourceY
                    destinationY = sourceX
                case 180:
                    destinationX = image.width - 1 - sourceX
                    destinationY = image.height - 1 - sourceY
                default:
                    destinationX = sourceY
                    destinationY = image.width - 1 - sourceX
                }

                let sourceOffset = image.byteOffset(
                    x: sourceX,
                    y: sourceY
                )
                let destinationOffset = (
                    destinationY * destinationWidth + destinationX
                ) * 4
                output[destinationOffset ..< destinationOffset + 4] =
                    image.bytes[sourceOffset ..< sourceOffset + 4]
            }
        }

        return try! ScannerRGBAImage(
            width: destinationWidth,
            height: destinationHeight,
            bytes: output
        )
    }
}
