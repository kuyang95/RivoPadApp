import Foundation
import Metal

nonisolated enum AndroidMetalImageError: Error, Equatable, Sendable {
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

/// GPU equivalents of the scanner's Android-compatible perspective, resize,
/// color, and tensor-preparation loops. Image boundaries remain top-left
/// row-major RGBA8; model preprocessing emits the existing NCHW Float layout.
nonisolated final class AndroidMetalImageSampler: @unchecked Sendable {
    private struct ResizeUniforms {
        let sourceWidth: UInt32
        let sourceHeight: UInt32
        let outputWidth: UInt32
        let outputHeight: UInt32
    }

    private struct PerspectiveUniforms {
        let sourceWidth: UInt32
        let sourceHeight: UInt32
        let outputWidth: UInt32
        let outputHeight: UInt32
        let a: Float
        let b: Float
        let c: Float
        let d: Float
        let e: Float
        let f: Float
        let g: Float
        let h: Float
    }

    private struct ColorUniforms {
        let sourceWidth: UInt32
        let sourceHeight: UInt32
        let outputWidth: UInt32
        let outputHeight: UInt32
        let blackPoint: Float
        let toneRange: Float
        let redScale: Float
        let greenScale: Float
        let blueScale: Float
        let gamma: Float
        let saturationBoost: Float
    }

    private struct Homography {
        let a: Float
        let b: Float
        let c: Float
        let d: Float
        let e: Float
        let f: Float
        let g: Float
        let h: Float

        init(orderedCorners: [ScannerPixelPoint]) throws {
            guard orderedCorners.count == 4 else {
                throw ScannerPerspectiveError.invalidQuad
            }
            let topLeft = orderedCorners[0]
            let topRight = orderedCorners[1]
            let bottomRight = orderedCorners[2]
            let bottomLeft = orderedCorners[3]
            let deltaX1 = topRight.x - bottomRight.x
            let deltaX2 = bottomLeft.x - bottomRight.x
            let deltaX3 =
                topLeft.x - topRight.x + bottomRight.x - bottomLeft.x
            let deltaY1 = topRight.y - bottomRight.y
            let deltaY2 = bottomLeft.y - bottomRight.y
            let deltaY3 =
                topLeft.y - topRight.y + bottomRight.y - bottomLeft.y

            let g: Float
            let h: Float
            if abs(deltaX3) < 0.000_001,
               abs(deltaY3) < 0.000_001 {
                g = 0
                h = 0
            } else {
                let denominator = deltaX1 * deltaY2 - deltaX2 * deltaY1
                guard abs(denominator) >= 0.000_001 else {
                    throw ScannerPerspectiveError.singularTransform
                }
                g = (deltaX3 * deltaY2 - deltaX2 * deltaY3)
                    / denominator
                h = (deltaX1 * deltaY3 - deltaX3 * deltaY1)
                    / denominator
            }

            a = topRight.x - topLeft.x + g * topRight.x
            b = bottomLeft.x - topLeft.x + h * bottomLeft.x
            c = topLeft.x
            d = topRight.y - topLeft.y + g * topRight.y
            e = bottomLeft.y - topLeft.y + h * bottomLeft.y
            f = topLeft.y
            self.g = g
            self.h = h
        }
    }

    private static let resizeKernelName =
        "androidResizeBilinearRGBA8"
    private static let perspectiveKernelName =
        "androidPerspectiveWarpRGBA8"
    private static let colorKernelName =
        "androidDocumentColorEnhanceRGBA8"
    private static let stretchedTensorKernelName =
        "androidStretchedRGBTensorNCHW"

    private let device: any MTLDevice
    private let commandQueue: any MTLCommandQueue
    private let resizePipeline: any MTLComputePipelineState
    private let perspectivePipeline: any MTLComputePipelineState
    private let colorPipeline: any MTLComputePipelineState
    private let stretchedTensorPipeline: any MTLComputePipelineState

    init(
        device requestedDevice: (any MTLDevice)? = nil,
        library requestedLibrary: (any MTLLibrary)? = nil
    ) throws {
        guard let device = requestedDevice ?? MTLCreateSystemDefaultDevice() else {
            throw AndroidMetalImageError.metalUnavailable
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw AndroidMetalImageError.commandQueueUnavailable
        }
        guard let library = requestedLibrary ?? device.makeDefaultLibrary() else {
            throw AndroidMetalImageError.defaultLibraryUnavailable
        }
        let resizePipeline = try Self.makePipeline(
            named: Self.resizeKernelName,
            device: device,
            library: library
        )
        let perspectivePipeline = try Self.makePipeline(
            named: Self.perspectiveKernelName,
            device: device,
            library: library
        )
        let colorPipeline = try Self.makePipeline(
            named: Self.colorKernelName,
            device: device,
            library: library
        )
        let stretchedTensorPipeline = try Self.makePipeline(
            named: Self.stretchedTensorKernelName,
            device: device,
            library: library
        )

        self.device = device
        self.commandQueue = commandQueue
        self.resizePipeline = resizePipeline
        self.perspectivePipeline = perspectivePipeline
        self.colorPipeline = colorPipeline
        self.stretchedTensorPipeline = stretchedTensorPipeline
    }

    func resizeBilinear(
        _ source: ScannerRGBAImage,
        width: Int,
        height: Int
    ) throws -> ScannerRGBAImage {
        if source.width == width, source.height == height {
            return source
        }
        var uniforms = try ResizeUniforms(
            sourceWidth: checkedDimension(source.width),
            sourceHeight: checkedDimension(source.height),
            outputWidth: checkedDimension(width),
            outputHeight: checkedDimension(height)
        )
        return try execute(
            source,
            outputWidth: width,
            outputHeight: height,
            pipeline: resizePipeline,
            uniforms: &uniforms
        )
    }

    func normalizedLongEdge(
        _ source: ScannerRGBAImage,
        maximum: Int
    ) throws -> ScannerRGBAImage {
        let longEdge = max(source.width, source.height)
        guard longEdge > maximum else {
            return source
        }
        let scale = Float(maximum) / Float(longEdge)
        return try resizeBilinear(
            source,
            width: max(Int(Float(source.width) * scale), 1),
            height: max(Int(Float(source.height) * scale), 1)
        )
    }

    func perspectiveWarp(
        _ source: ScannerRGBAImage,
        orderedCorners: [ScannerPixelPoint],
        outputSize: ScannerPixelSize
    ) throws -> ScannerRGBAImage {
        guard outputSize.width > 0, outputSize.height > 0 else {
            throw ScannerPerspectiveError.invalidQuad
        }
        let homography = try Homography(
            orderedCorners: orderedCorners
        )
        var uniforms = try PerspectiveUniforms(
            sourceWidth: checkedDimension(source.width),
            sourceHeight: checkedDimension(source.height),
            outputWidth: checkedDimension(outputSize.width),
            outputHeight: checkedDimension(outputSize.height),
            a: homography.a,
            b: homography.b,
            c: homography.c,
            d: homography.d,
            e: homography.e,
            f: homography.f,
            g: homography.g,
            h: homography.h
        )
        return try execute(
            source,
            outputWidth: outputSize.width,
            outputHeight: outputSize.height,
            pipeline: perspectivePipeline,
            uniforms: &uniforms
        )
    }

    func enhanceDocument(
        _ source: ScannerRGBAImage,
        parameters: AndroidDocumentColorParameters
    ) throws -> ScannerRGBAImage {
        var uniforms = try ColorUniforms(
            sourceWidth: checkedDimension(source.width),
            sourceHeight: checkedDimension(source.height),
            outputWidth: checkedDimension(source.width),
            outputHeight: checkedDimension(source.height),
            blackPoint: Float(parameters.blackPoint),
            toneRange: parameters.toneRange,
            redScale: parameters.redScale,
            greenScale: parameters.greenScale,
            blueScale: parameters.blueScale,
            gamma: Float(parameters.gamma),
            saturationBoost: parameters.saturationBoost
        )
        return try execute(
            source,
            outputWidth: source.width,
            outputHeight: source.height,
            pipeline: colorPipeline,
            uniforms: &uniforms
        )
    }

    /// Combines Android's quantized bilinear resize and RGB-to-NCHW
    /// conversion in one GPU dispatch, avoiding an intermediate RGBA image.
    func stretchedRGBTensor(
        _ source: ScannerRGBAImage,
        width: Int,
        height: Int
    ) throws -> ScannerPreparedTensor {
        let (pixelCount, pixelCountOverflow) =
            width.multipliedReportingOverflow(by: height)
        let (valueCount, valueCountOverflow) =
            pixelCount.multipliedReportingOverflow(by: 3)
        let (outputByteCount, outputByteCountOverflow) =
            valueCount.multipliedReportingOverflow(
                by: MemoryLayout<Float>.stride
            )
        guard !pixelCountOverflow,
              !valueCountOverflow,
              !outputByteCountOverflow else {
            throw AndroidMetalImageError.dimensionsExceedMetalLimits
        }

        var uniforms = try ResizeUniforms(
            sourceWidth: checkedDimension(source.width),
            sourceHeight: checkedDimension(source.height),
            outputWidth: checkedDimension(width),
            outputHeight: checkedDimension(height)
        )
        let outputBuffer = try executeBuffer(
            source,
            outputWidth: width,
            outputHeight: height,
            outputByteCount: outputByteCount,
            pipeline: stretchedTensorPipeline,
            uniforms: &uniforms
        )
        let outputPointer = outputBuffer.contents()
            .assumingMemoryBound(to: Float.self)
        let values = Array(
            UnsafeBufferPointer(
                start: outputPointer,
                count: valueCount
            )
        )
        return ScannerPreparedTensor(
            values: values,
            shape: [1, 3, height, width],
            letterbox: nil
        )
    }

    private func execute<Uniforms>(
        _ source: ScannerRGBAImage,
        outputWidth: Int,
        outputHeight: Int,
        pipeline: any MTLComputePipelineState,
        uniforms: inout Uniforms
    ) throws -> ScannerRGBAImage {
        let (pixelCount, pixelCountOverflow) =
            outputWidth.multipliedReportingOverflow(by: outputHeight)
        let (outputByteCount, outputByteCountOverflow) =
            pixelCount.multipliedReportingOverflow(by: 4)
        guard !pixelCountOverflow, !outputByteCountOverflow else {
            throw AndroidMetalImageError.dimensionsExceedMetalLimits
        }
        let outputBuffer = try executeBuffer(
            source,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            outputByteCount: outputByteCount,
            pipeline: pipeline,
            uniforms: &uniforms
        )
        let outputPointer = outputBuffer.contents()
            .assumingMemoryBound(to: UInt8.self)
        let bytes = Array(
            UnsafeBufferPointer(
                start: outputPointer,
                count: outputByteCount
            )
        )
        return try ScannerRGBAImage(
            width: outputWidth,
            height: outputHeight,
            bytes: bytes
        )
    }

    private func executeBuffer<Uniforms>(
        _ source: ScannerRGBAImage,
        outputWidth: Int,
        outputHeight: Int,
        outputByteCount: Int,
        pipeline: any MTLComputePipelineState,
        uniforms: inout Uniforms
    ) throws -> any MTLBuffer {
        try validateBufferLength(source.bytes.count)
        try validateBufferLength(outputByteCount)

        var sourceBuffer: (any MTLBuffer)? =
            try source.bytes.withUnsafeBytes { storage in
                guard let baseAddress = storage.baseAddress,
                      let buffer = device.makeBuffer(
                          bytes: baseAddress,
                          length: storage.count,
                          options: .storageModeShared
                      ) else {
                    throw AndroidMetalImageError.bufferAllocationFailed(
                        label: "source"
                    )
                }
                return buffer
            }
        guard let outputBuffer = device.makeBuffer(
            length: outputByteCount,
            options: .storageModeShared
        ) else {
            throw AndroidMetalImageError.bufferAllocationFailed(
                label: "output"
            )
        }
        do {
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                throw AndroidMetalImageError.commandBufferUnavailable
            }
            guard let encoder =
                commandBuffer.makeComputeCommandEncoder() else {
                throw AndroidMetalImageError.commandEncoderUnavailable
            }

            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(sourceBuffer, offset: 0, index: 0)
            encoder.setBuffer(outputBuffer, offset: 0, index: 1)
            encoder.setBytes(
                &uniforms,
                length: MemoryLayout<Uniforms>.stride,
                index: 2
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
                MTLSize(
                    width: outputWidth,
                    height: outputHeight,
                    depth: 1
                ),
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
                throw AndroidMetalImageError.executionFailed(
                    description: commandBuffer.error?.localizedDescription
                        ?? "command status \(commandBuffer.status.rawValue)"
                )
            }
        }
        // The command buffer no longer needs its copied input. Releasing it
        // before materializing the output array lowers full-page peak memory.
        sourceBuffer = nil
        return outputBuffer
    }

    private func checkedDimension(_ value: Int) throws -> UInt32 {
        guard value > 0, value <= Int(UInt32.max) else {
            throw AndroidMetalImageError.dimensionsExceedMetalLimits
        }
        return UInt32(value)
    }

    private func validateBufferLength(_ byteCount: Int) throws {
        guard byteCount <= device.maxBufferLength else {
            throw AndroidMetalImageError.bufferTooLarge(
                byteCount: byteCount,
                maximum: device.maxBufferLength
            )
        }
    }

    private static func makePipeline(
        named name: String,
        device: any MTLDevice,
        library: any MTLLibrary
    ) throws -> any MTLComputePipelineState {
        guard let function = library.makeFunction(name: name) else {
            throw AndroidMetalImageError.kernelUnavailable(name: name)
        }
        do {
            return try device.makeComputePipelineState(function: function)
        } catch {
            throw AndroidMetalImageError.pipelineCreationFailed(
                description: error.localizedDescription
            )
        }
    }
}
