import Foundation
import Metal

nonisolated enum UVDocWarpBackend: String, Equatable, Sendable {
    case metal
    case cpu
}

nonisolated enum UVDocMetalWarpError: Error, Equatable, Sendable {
    case metalUnavailable
    case commandQueueUnavailable
    case defaultLibraryUnavailable
    case kernelUnavailable(name: String)
    case pipelineCreationFailed(description: String)
    case dimensionsExceedMetalLimits
    case bufferTooLarge(byteCount: Int, maximum: Int)
    case bufferAllocationFailed(label: String)
    case commandBufferUnavailable
    case commandEncoderUnavailable
    case executionFailed(description: String)
}

extension UVDocMetalWarpError: LocalizedError {
    nonisolated var errorDescription: String? {
        switch self {
        case .metalUnavailable:
            return "Metal is unavailable on this device."
        case .commandQueueUnavailable:
            return "The UVDoc Metal command queue could not be created."
        case .defaultLibraryUnavailable:
            return "The app's default Metal library is unavailable."
        case let .kernelUnavailable(name):
            return "The UVDoc Metal kernel '\(name)' is unavailable."
        case let .pipelineCreationFailed(description):
            return "The UVDoc Metal pipeline could not be created: \(description)"
        case .dimensionsExceedMetalLimits:
            return "The UVDoc image dimensions exceed Metal's UInt32 limits."
        case let .bufferTooLarge(byteCount, maximum):
            return "A \(byteCount)-byte UVDoc buffer exceeds Metal's \(maximum)-byte limit."
        case let .bufferAllocationFailed(label):
            return "The UVDoc Metal \(label) buffer could not be allocated."
        case .commandBufferUnavailable:
            return "A UVDoc Metal command buffer could not be created."
        case .commandEncoderUnavailable:
            return "A UVDoc Metal compute encoder could not be created."
        case let .executionFailed(description):
            return "UVDoc Metal execution failed: \(description)"
        }
    }
}

/// Reuses immutable Metal state while allocating per-warp buffers.
///
/// The implementation is thread-safe because command buffers, encoders, and
/// data buffers are local to each invocation. The queue and pipeline are
/// explicitly documented by Metal as supporting concurrent command encoding.
nonisolated final class UVDocMetalGridSampler: @unchecked Sendable {
    private struct Uniforms {
        let sourceWidth: UInt32
        let sourceHeight: UInt32
        let outputWidth: UInt32
        let outputHeight: UInt32
        let gridWidth: UInt32
        let gridHeight: UInt32
        let padding0: UInt32 = 0
        let padding1: UInt32 = 0
    }

    private static let kernelName = "uvdocGridWarpRGBA8"

    private let device: any MTLDevice
    private let commandQueue: any MTLCommandQueue
    private let pipeline: any MTLComputePipelineState

    init(
        device requestedDevice: (any MTLDevice)? = nil,
        library requestedLibrary: (any MTLLibrary)? = nil
    ) throws {
        guard let device = requestedDevice ?? MTLCreateSystemDefaultDevice() else {
            throw UVDocMetalWarpError.metalUnavailable
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw UVDocMetalWarpError.commandQueueUnavailable
        }
        guard let library = requestedLibrary ?? device.makeDefaultLibrary() else {
            throw UVDocMetalWarpError.defaultLibraryUnavailable
        }
        guard let function = library.makeFunction(name: Self.kernelName) else {
            throw UVDocMetalWarpError.kernelUnavailable(
                name: Self.kernelName
            )
        }

        let pipeline: any MTLComputePipelineState
        do {
            pipeline = try device.makeComputePipelineState(
                function: function
            )
        } catch {
            throw UVDocMetalWarpError.pipelineCreationFailed(
                description: error.localizedDescription
            )
        }

        self.device = device
        self.commandQueue = commandQueue
        self.pipeline = pipeline
    }

    /// Matches `UVDocGridSampler.warp` but dispatches one GPU thread per output
    /// pixel. The synchronous boundary is intentional: it guarantees shared
    /// buffer contents are complete before they are copied into the value type.
    func warp(
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
        guard grid.values.allSatisfy(\.isFinite) else {
            throw UVDocGridError.nonFiniteCoordinate
        }
        let maximumDimension = Int(UInt32.max)
        guard source.width <= maximumDimension,
              source.height <= maximumDimension,
              width <= maximumDimension,
              height <= maximumDimension,
              grid.width <= maximumDimension,
              grid.height <= maximumDimension else {
            throw UVDocMetalWarpError.dimensionsExceedMetalLimits
        }

        let (pixelCount, pixelCountOverflow) =
            width.multipliedReportingOverflow(by: height)
        let (outputByteCount, byteCountOverflow) =
            pixelCount.multipliedReportingOverflow(by: 4)
        guard !pixelCountOverflow, !byteCountOverflow else {
            throw UVDocMetalWarpError.dimensionsExceedMetalLimits
        }

        try validateBufferLength(source.bytes.count)
        let (gridByteCount, gridByteCountOverflow) =
            grid.values.count.multipliedReportingOverflow(
                by: MemoryLayout<Float>.size
            )
        guard !gridByteCountOverflow else {
            throw UVDocMetalWarpError.dimensionsExceedMetalLimits
        }
        try validateBufferLength(gridByteCount)
        try validateBufferLength(outputByteCount)

        var sourceBuffer: (any MTLBuffer)? =
            try source.bytes.withUnsafeBytes { storage in
                guard let baseAddress = storage.baseAddress,
                      let buffer = device.makeBuffer(
                          bytes: baseAddress,
                          length: storage.count,
                          options: .storageModeShared
                      ) else {
                    throw UVDocMetalWarpError.bufferAllocationFailed(
                        label: "source"
                    )
                }
                buffer.label = "UVDoc source RGBA8"
                return buffer
            }
        var gridBuffer: (any MTLBuffer)? =
            try grid.values.withUnsafeBytes { storage in
                guard let baseAddress = storage.baseAddress,
                      let buffer = device.makeBuffer(
                          bytes: baseAddress,
                          length: storage.count,
                          options: .storageModeShared
                      ) else {
                    throw UVDocMetalWarpError.bufferAllocationFailed(
                        label: "grid"
                    )
                }
                buffer.label = "UVDoc normalized grid"
                return buffer
            }
        guard let outputBuffer = device.makeBuffer(
            length: outputByteCount,
            options: .storageModeShared
        ) else {
            throw UVDocMetalWarpError.bufferAllocationFailed(label: "output")
        }
        outputBuffer.label = "UVDoc output RGBA8"

        var uniforms = Uniforms(
            sourceWidth: UInt32(source.width),
            sourceHeight: UInt32(source.height),
            outputWidth: UInt32(width),
            outputHeight: UInt32(height),
            gridWidth: UInt32(grid.width),
            gridHeight: UInt32(grid.height)
        )
        do {
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                throw UVDocMetalWarpError.commandBufferUnavailable
            }
            commandBuffer.label = "UVDoc grid warp"
            guard let encoder =
                commandBuffer.makeComputeCommandEncoder() else {
                throw UVDocMetalWarpError.commandEncoderUnavailable
            }
            encoder.label = "UVDoc RGBA8 grid warp"
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(sourceBuffer, offset: 0, index: 0)
            encoder.setBuffer(gridBuffer, offset: 0, index: 1)
            encoder.setBuffer(outputBuffer, offset: 0, index: 2)
            encoder.setBytes(
                &uniforms,
                length: MemoryLayout<Uniforms>.stride,
                index: 3
            )
            let threadWidth = pipeline.threadExecutionWidth
            let threadHeight = max(
                1,
                min(
                    8,
                    pipeline.maxTotalThreadsPerThreadgroup / threadWidth
                )
            )
            encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(
                    width: threadWidth,
                    height: threadHeight,
                    depth: 1
                )
            )
            encoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()

            guard commandBuffer.status == .completed else {
                throw UVDocMetalWarpError.executionFailed(
                    description: commandBuffer.error?.localizedDescription
                        ?? "command status \(commandBuffer.status.rawValue)"
                )
            }
        }
        sourceBuffer = nil
        gridBuffer = nil
        let outputPointer = outputBuffer.contents()
            .assumingMemoryBound(to: UInt8.self)
        let output = Array(
            UnsafeBufferPointer(
                start: outputPointer,
                count: outputByteCount
            )
        )
        return try ScannerRGBAImage(
            width: width,
            height: height,
            bytes: output
        )
    }

    private func validateBufferLength(_ byteCount: Int) throws {
        guard byteCount <= device.maxBufferLength else {
            throw UVDocMetalWarpError.bufferTooLarge(
                byteCount: byteCount,
                maximum: device.maxBufferLength
            )
        }
    }
}
