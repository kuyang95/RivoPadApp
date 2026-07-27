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

        let (gridPointCount, gridPointCountOverflow) =
            grid.width.multipliedReportingOverflow(by: grid.height)
        let (expectedValueCount, gridValueCountOverflow) =
            gridPointCount.multipliedReportingOverflow(by: 2)
        guard !gridPointCountOverflow, !gridValueCountOverflow else {
            throw UVDocGridError.invalidDimensions(
                height: grid.height,
                width: grid.width
            )
        }
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
        let (pixelCount, pixelCountOverflow) =
            width.multipliedReportingOverflow(by: height)
        let (outputByteCount, outputByteCountOverflow) =
            pixelCount.multipliedReportingOverflow(by: 4)
        guard !pixelCountOverflow, !outputByteCountOverflow else {
            throw UVDocGridError.invalidDimensions(
                height: height,
                width: width
            )
        }
        var output = [UInt8](repeating: 0, count: outputByteCount)

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
                let gridTopX = fma(
                    grid.values[index01] - grid.values[index00],
                    fractionX,
                    grid.values[index00]
                )
                let gridBottomX = fma(
                    grid.values[index11] - grid.values[index10],
                    fractionX,
                    grid.values[index10]
                )
                let normalizedSourceX = fma(
                    gridBottomX - gridTopX,
                    fractionY,
                    gridTopX
                )
                let gridTopY = fma(
                    grid.values[index01 + 1] - grid.values[index00 + 1],
                    fractionX,
                    grid.values[index00 + 1]
                )
                let gridBottomY = fma(
                    grid.values[index11 + 1] - grid.values[index10 + 1],
                    fractionX,
                    grid.values[index10 + 1]
                )
                let normalizedSourceY = fma(
                    gridBottomY - gridTopY,
                    fractionY,
                    gridTopY
                )
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
                let outputOffset = (outputRow + outputX) * 4

                for channel in 0 ..< 4 {
                    let topLeft = Float(source.bytes[source00 + channel])
                    let top = fma(
                        Float(source.bytes[source01 + channel]) - topLeft,
                        sourceFractionX,
                        topLeft
                    )
                    let bottomLeft = Float(
                        source.bytes[source10 + channel]
                    )
                    let bottom = fma(
                        Float(source.bytes[source11 + channel])
                            - bottomLeft,
                        sourceFractionX,
                        bottomLeft
                    )
                    let value = fma(
                        bottom - top,
                        sourceFractionY,
                        top
                    )
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

actor UVDocDewarpEngine: TraceableCurvedDocumentDewarping {
    nonisolated let backend: ScannerInferenceBackend
    nonisolated let preferredWarpBackend: UVDocWarpBackend

    private let session: ScannerONNXSession
    private let imageBridge = ScannerCIImageBridge()
    private let metalSampler: UVDocMetalGridSampler?
    private(set) var lastWarpBackend: UVDocWarpBackend?
    private(set) var lastMetalWarpErrorDescription: String?

    init(
        bundle: Bundle = .main,
        backend: ScannerInferenceBackend = .coreML,
        preferMetalWarp: Bool = true
    ) throws {
        let session = try ScannerONNXSession(
            descriptor: .curvedPageDewarper,
            bundle: bundle,
            backend: backend
        )
        let metalState = Self.makeMetalSampler(
            whenEnabled: preferMetalWarp
        )
        self.backend = session.activeBackend
        self.preferredWarpBackend = metalState.sampler == nil
            ? .cpu
            : .metal
        self.session = session
        self.metalSampler = metalState.sampler
        self.lastWarpBackend = nil
        self.lastMetalWarpErrorDescription = metalState.errorDescription
    }

    init(
        modelURL: URL,
        backend: ScannerInferenceBackend = .coreML,
        preferMetalWarp: Bool = true
    ) throws {
        let session = try ScannerONNXSession(
            descriptor: .curvedPageDewarper,
            modelURL: modelURL,
            backend: backend
        )
        let metalState = Self.makeMetalSampler(
            whenEnabled: preferMetalWarp
        )
        self.backend = session.activeBackend
        self.preferredWarpBackend = metalState.sampler == nil
            ? .cpu
            : .metal
        self.session = session
        self.metalSampler = metalState.sampler
        self.lastWarpBackend = nil
        self.lastMetalWarpErrorDescription = metalState.errorDescription
    }

    func dewarp(_ image: CIImage) async throws -> CIImage {
        try await dewarp(image, trace: nil)
    }

    func dewarp(
        _ image: CIImage,
        trace: ScannerProcessingTrace?
    ) async throws -> CIImage {
        let sourceStage = trace?.beginStage("uvdocSourceRasterize")
        let source: ScannerRGBAImage
        do {
            source = try imageBridge.rgbaImage(from: image)
            sourceStage?.finish(
                details: "output=\(source.width)x\(source.height)"
            )
        } catch {
            sourceStage?.finish(
                outcome: error is CancellationError
                    ? "cancelled"
                    : "failure"
            )
            throw error
        }

        let preprocessStage = trace?.beginStage("uvdocPreprocess")
        let prepared = AndroidScannerImageMath.stretchedRGBTensor(
            from: source,
            width: 496,
            height: 720
        )
        preprocessStage?.finish(
            details: "input=\(source.width)x\(source.height) "
                + "output=496x720"
        )

        let inferenceStage = trace?.beginStage("uvdocInference")
        let output: ScannerFloatTensor
        do {
            output = try await session.run(
                ScannerFloatTensor(
                    values: prepared.values,
                    shape: prepared.shape
                )
            )
            inferenceStage?.finish(
                details: "backend=\(backend.rawValue) "
                    + "elements=\(output.values.count)"
            )
        } catch {
            inferenceStage?.finish(
                outcome: error is CancellationError
                    ? "cancelled"
                    : "failure",
                details: "backend=\(backend.rawValue)"
            )
            throw error
        }

        let decodeStage = trace?.beginStage("uvdocGridDecode")
        let grid: UVDocGrid
        do {
            grid = try UVDocGridDecoder.decode(output)
            decodeStage?.finish(
                details: "output=\(grid.width)x\(grid.height)"
            )
        } catch {
            decodeStage?.finish(
                outcome: error is CancellationError
                    ? "cancelled"
                    : "failure"
            )
            throw error
        }

        let dewarped: ScannerRGBAImage
        if let metalSampler {
            let metalWarpStage = trace?.beginStage("uvdocMetalWarp")
            do {
                dewarped = try metalSampler.warp(source, with: grid)
                lastWarpBackend = .metal
                lastMetalWarpErrorDescription = nil
                metalWarpStage?.finish(
                    details: "input=\(source.width)x\(source.height) "
                        + "output=\(dewarped.width)x\(dewarped.height)"
                )
            } catch {
                metalWarpStage?.finish(
                    outcome: error is CancellationError
                        ? "cancelled"
                        : "failure",
                    details: "fallback=cpu"
                )
                lastMetalWarpErrorDescription = error.localizedDescription
                let cpuWarpStage = trace?.beginStage("uvdocCPUWarp")
                do {
                    dewarped = try UVDocGridSampler.warp(
                        source,
                        with: grid
                    )
                    cpuWarpStage?.finish(
                        details: "input=\(source.width)x\(source.height) "
                            + "output=\(dewarped.width)x"
                            + "\(dewarped.height) fallback=true"
                    )
                } catch {
                    cpuWarpStage?.finish(
                        outcome: error is CancellationError
                            ? "cancelled"
                            : "failure",
                        details: "fallback=true"
                    )
                    throw error
                }
                lastWarpBackend = .cpu
            }
        } else {
            let cpuWarpStage = trace?.beginStage("uvdocCPUWarp")
            do {
                dewarped = try UVDocGridSampler.warp(source, with: grid)
                cpuWarpStage?.finish(
                    details: "input=\(source.width)x\(source.height) "
                        + "output=\(dewarped.width)x\(dewarped.height) "
                        + "fallback=false"
                )
            } catch {
                cpuWarpStage?.finish(
                    outcome: error is CancellationError
                        ? "cancelled"
                        : "failure",
                    details: "fallback=false"
                )
                throw error
            }
            lastWarpBackend = .cpu
        }

        let outputBridgeStage = trace?.beginStage("uvdocOutputBridge")
        let result = imageBridge.ciImage(from: dewarped)
        outputBridgeStage?.finish(
            details: "output=\(dewarped.width)x\(dewarped.height)"
        )
        return result
    }

    private static func makeMetalSampler(
        whenEnabled isEnabled: Bool
    ) -> (
        sampler: UVDocMetalGridSampler?,
        errorDescription: String?
    ) {
        guard isEnabled else {
            return (nil, nil)
        }

        do {
            return (try UVDocMetalGridSampler(), nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }
}
