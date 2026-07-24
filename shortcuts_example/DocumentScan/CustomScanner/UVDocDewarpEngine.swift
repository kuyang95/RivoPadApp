import CoreImage
import Foundation

nonisolated enum UVDocGridError: Error, Equatable, Sendable {
    case invalidDimensions(height: Int, width: Int)
    case invalidValueCount(expected: Int, actual: Int)
    case nonFiniteCoordinate
}

nonisolated enum UVDocGridDecoder {
    static func decode(_ tensor: ScannerFloatTensor) throws -> UVDocGrid {
        let expectedShape =
            ScannerModelDescriptor.curvedPageDewarper.outputShape
        guard tensor.shape == expectedShape else {
            throw ScannerModelError.outputShapeMismatch(
                expected: expectedShape,
                actual: tensor.shape
            )
        }

        let height = expectedShape[2]
        let width = expectedShape[3]
        let channelStride = height * width
        var interleaved = [Float](
            repeating: 0,
            count: channelStride * 2
        )

        for y in 0 ..< height {
            for x in 0 ..< width {
                let sourceIndex = y * width + x
                let destinationIndex = sourceIndex * 2
                interleaved[destinationIndex] =
                    tensor.values[sourceIndex]
                interleaved[destinationIndex + 1] =
                    tensor.values[channelStride + sourceIndex]
            }
        }

        return UVDocGrid(
            values: interleaved,
            height: height,
            width: width
        )
    }
}

nonisolated enum UVDocGridSampler {
    /// Exact two-stage bilinear remap used by VisionCraft Android:
    /// align-corners grid upsample, `[-1, 1]` to source pixels, then a
    /// BORDER_REPLICATE source sample. Channel interpolation truncates.
    static func warp(
        _ source: ScannerRGBAImage,
        with grid: UVDocGrid,
        outputWidth: Int? = nil,
        outputHeight: Int? = nil
    ) throws -> ScannerRGBAImage {
        let width = outputWidth ?? source.width
        let height = outputHeight ?? source.height
        guard width > 0, height > 0, grid.width >= 2, grid.height >= 2 else {
            throw UVDocGridError.invalidDimensions(
                height: grid.height,
                width: grid.width
            )
        }

        let expectedValueCount = grid.width * grid.height * 2
        guard grid.values.count == expectedValueCount else {
            throw UVDocGridError.invalidValueCount(
                expected: expectedValueCount,
                actual: grid.values.count
            )
        }

        let gridYScale = height > 1
            ? Float(grid.height - 1) / Float(height - 1)
            : 0
        let gridXScale = width > 1
            ? Float(grid.width - 1) / Float(width - 1)
            : 0
        let sourceXMaximum = Float(source.width - 1)
        let sourceYMaximum = Float(source.height - 1)
        var output = [UInt8](repeating: 0, count: width * height * 4)

        for outputY in 0 ..< height {
            let gridY = Float(outputY) * gridYScale
            let gridY0 = min(max(Int(gridY), 0), grid.height - 2)
            let gridY1 = gridY0 + 1
            let fractionY = min(max(gridY - Float(gridY0), 0), 1)
            let gridY0Row = gridY0 * grid.width
            let gridY1Row = gridY1 * grid.width
            let outputRow = outputY * width

            for outputX in 0 ..< width {
                let gridX = Float(outputX) * gridXScale
                let gridX0 = min(max(Int(gridX), 0), grid.width - 2)
                let gridX1 = gridX0 + 1
                let fractionX = min(max(gridX - Float(gridX0), 0), 1)

                let index00 = (gridY0Row + gridX0) * 2
                let index01 = (gridY0Row + gridX1) * 2
                let index10 = (gridY1Row + gridX0) * 2
                let index11 = (gridY1Row + gridX1) * 2
                let weight00 = (1 - fractionX) * (1 - fractionY)
                let weight01 = fractionX * (1 - fractionY)
                let weight10 = (1 - fractionX) * fractionY
                let weight11 = fractionX * fractionY

                let normalizedSourceX =
                    weight00 * grid.values[index00]
                    + weight01 * grid.values[index01]
                    + weight10 * grid.values[index10]
                    + weight11 * grid.values[index11]
                let normalizedSourceY =
                    weight00 * grid.values[index00 + 1]
                    + weight01 * grid.values[index01 + 1]
                    + weight10 * grid.values[index10 + 1]
                    + weight11 * grid.values[index11 + 1]
                guard normalizedSourceX.isFinite,
                      normalizedSourceY.isFinite else {
                    throw UVDocGridError.nonFiniteCoordinate
                }

                let sourceX = min(
                    max(
                        (normalizedSourceX + 1) * 0.5 * sourceXMaximum,
                        0
                    ),
                    sourceXMaximum
                )
                let sourceY = min(
                    max(
                        (normalizedSourceY + 1) * 0.5 * sourceYMaximum,
                        0
                    ),
                    sourceYMaximum
                )
                let sourceX0 = Int(sourceX)
                let sourceY0 = Int(sourceY)
                let sourceX1 = sourceX0 < source.width - 1
                    ? sourceX0 + 1
                    : sourceX0
                let sourceY1 = sourceY0 < source.height - 1
                    ? sourceY0 + 1
                    : sourceY0
                let sourceFractionX = sourceX - Float(sourceX0)
                let sourceFractionY = sourceY - Float(sourceY0)

                let source00 = source.byteOffset(
                    x: sourceX0,
                    y: sourceY0
                )
                let source01 = source.byteOffset(
                    x: sourceX1,
                    y: sourceY0
                )
                let source10 = source.byteOffset(
                    x: sourceX0,
                    y: sourceY1
                )
                let source11 = source.byteOffset(
                    x: sourceX1,
                    y: sourceY1
                )
                let sourceWeight00 =
                    (1 - sourceFractionX) * (1 - sourceFractionY)
                let sourceWeight01 =
                    sourceFractionX * (1 - sourceFractionY)
                let sourceWeight10 =
                    (1 - sourceFractionX) * sourceFractionY
                let sourceWeight11 =
                    sourceFractionX * sourceFractionY
                let outputOffset = (outputRow + outputX) * 4

                for channel in 0 ..< 4 {
                    let value =
                        sourceWeight00
                        * Float(source.bytes[source00 + channel])
                        + sourceWeight01
                        * Float(source.bytes[source01 + channel])
                        + sourceWeight10
                        * Float(source.bytes[source10 + channel])
                        + sourceWeight11
                        * Float(source.bytes[source11 + channel])
                    output[outputOffset + channel] = UInt8(
                        clamping: Int(value)
                    )
                }
            }
        }

        return try ScannerRGBAImage(
            width: width,
            height: height,
            bytes: output
        )
    }
}

actor UVDocDewarpEngine: CurvedDocumentDewarping {
    nonisolated let backend: ScannerInferenceBackend

    private let session: ScannerONNXSession
    private let imageBridge = ScannerCIImageBridge()

    init(
        bundle: Bundle = .main,
        backend: ScannerInferenceBackend = .coreML
    ) throws {
        let session = try ScannerONNXSession(
            descriptor: .curvedPageDewarper,
            bundle: bundle,
            backend: backend
        )
        self.backend = session.activeBackend
        self.session = session
    }

    init(
        modelURL: URL,
        backend: ScannerInferenceBackend = .coreML
    ) throws {
        let session = try ScannerONNXSession(
            descriptor: .curvedPageDewarper,
            modelURL: modelURL,
            backend: backend
        )
        self.backend = session.activeBackend
        self.session = session
    }

    func dewarp(_ image: CIImage) async throws -> CIImage {
        let source = try imageBridge.rgbaImage(from: image)
        let prepared = AndroidScannerImageMath.stretchedRGBTensor(
            from: source,
            width: 496,
            height: 720
        )
        let output = try await session.run(
            ScannerFloatTensor(
                values: prepared.values,
                shape: prepared.shape
            )
        )
        let grid = try UVDocGridDecoder.decode(output)
        let dewarped = try UVDocGridSampler.warp(source, with: grid)
        return imageBridge.ciImage(from: dewarped)
    }
}
