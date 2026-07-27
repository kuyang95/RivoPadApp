import CoreImage
import Metal
import CoreVideo
import XCTest

@testable import shortcuts_example

final class ScannerRegressionTests: XCTestCase {
    func testScannerDiagnosticsRequireExplicitOptIn() {
        XCTAssertFalse(
            ScannerDiagnostics.isRequested(
                arguments: ["VisionCraft"],
                environment: [:]
            )
        )
        XCTAssertTrue(
            ScannerDiagnostics.isRequested(
                arguments: ["VisionCraft"],
                environment: ["SCANNER_DIAGNOSTICS": "1"]
            )
        )
        XCTAssertTrue(
            ScannerDiagnostics.isRequested(
                arguments: ["VisionCraft", "--scanner-diagnostics"],
                environment: [:]
            )
        )
        XCTAssertFalse(
            ScannerDiagnostics.isRequested(
                arguments: [
                    "VisionCraft",
                    "-ScannerDiagnostics",
                    "0"
                ],
                environment: [:]
            )
        )
        XCTAssertTrue(
            ScannerDiagnostics.isRequested(
                arguments: [
                    "VisionCraft",
                    "-ScannerDiagnostics",
                    "1"
                ],
                environment: [:]
            )
        )
    }

    func testScannerProcessingTraceRequiresEnabledDiagnostics() {
        let ticket = UUID()
        let disabled = ScannerDiagnostics(
            arguments: ["VisionCraft"],
            environment: [:]
        )
        XCTAssertNil(disabled.trace(ticket: ticket))

        let enabled = ScannerDiagnostics(
            arguments: [
                "VisionCraft",
                "-ScannerDiagnostics",
                "1"
            ],
            environment: [:]
        )
        XCTAssertEqual(enabled.trace(ticket: ticket)?.ticket, ticket)
    }

    func testUVDocBenchmarkRequiresExplicitOptIn() {
        XCTAssertFalse(
            ScannerDiagnostics.isUVDocBenchmarkRequested(
                arguments: ["VisionCraft"],
                environment: [:]
            )
        )
        XCTAssertTrue(
            ScannerDiagnostics.isUVDocBenchmarkRequested(
                arguments: [
                    "VisionCraft",
                    "-ScannerBenchmarkUVDoc",
                    "1"
                ],
                environment: [:]
            )
        )
        XCTAssertFalse(
            ScannerDiagnostics.isUVDocBenchmarkRequested(
                arguments: [
                    "VisionCraft",
                    "-ScannerBenchmarkUVDoc",
                    "0"
                ],
                environment: [:]
            )
        )
        XCTAssertTrue(
            ScannerDiagnostics.isUVDocBenchmarkRequested(
                arguments: ["VisionCraft"],
                environment: ["SCANNER_BENCHMARK_UVDOC": "1"]
            )
        )
    }

    func testDirectScannerLaunchArgumentsDoNotAffectHostedTests() {
        XCTAssertTrue(
            shortcuts_exampleApp.shouldOpenScanner(
                arguments: [
                    "VisionCraft",
                    "-ScannerOpenScanner",
                    "1"
                ],
                environment: [:]
            )
        )
        XCTAssertTrue(
            shortcuts_exampleApp.shouldOpenScanner(
                arguments: ["VisionCraft", "--scanner-open-scanner"],
                environment: [:]
            )
        )
        XCTAssertFalse(
            shortcuts_exampleApp.shouldOpenScanner(
                arguments: [
                    "VisionCraft",
                    "-ScannerOpenScanner",
                    "1"
                ],
                environment: [
                    "XCTestConfigurationFilePath": "/tmp/tests.xctest"
                ]
            )
        )
    }

    func testMotionGateFallsOpenWhenSamplesNeverArrive() {
        XCTAssertFalse(
            ScannerMotionMonitor.shouldFallOpen(
                sampleCount: 0,
                requiredSampleCount: 16,
                elapsed: 0.99,
                timeout: 1
            )
        )
        XCTAssertTrue(
            ScannerMotionMonitor.shouldFallOpen(
                sampleCount: 0,
                requiredSampleCount: 16,
                elapsed: 1,
                timeout: 1
            )
        )
        XCTAssertFalse(
            ScannerMotionMonitor.shouldFallOpen(
                sampleCount: 16,
                requiredSampleCount: 16,
                elapsed: 5,
                timeout: 1
            )
        )
    }

    func testFOVComparisonProjectsEachRasterIntoPreviewSpace() throws {
        let configuration = ScannerViewportConfiguration(
            previewWidth: 1_000,
            previewHeight: 700,
            previewRotationDegrees: 0,
            generation: 1
        )
        let liveTransform = try XCTUnwrap(
            ScannerViewportTransform(
                rawWidth: 1_000,
                rawHeight: 700,
                configuration: configuration
            )
        )
        let stillTransform = try XCTUnwrap(
            ScannerViewportTransform(
                rawWidth: 4_000,
                rawHeight: 2_800,
                configuration: configuration
            )
        )
        let liveQuad = DocumentQuad(
            topLeft: NormalizedPoint(x: 0.2, y: 0.2),
            topRight: NormalizedPoint(x: 0.8, y: 0.2),
            bottomRight: NormalizedPoint(x: 0.8, y: 0.8),
            bottomLeft: NormalizedPoint(x: 0.2, y: 0.8)
        )
        let equal = ScannerFOVComparison.compare(
            liveQuad: liveQuad,
            liveTransform: liveTransform,
            stillQuad: liveQuad,
            stillTransform: stillTransform
        )
        XCTAssertEqual(
            equal.meanCornerErrorPercentOfPreviewDiagonal,
            0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            equal.maximumCornerErrorPercentOfPreviewDiagonal,
            0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(equal.boundingBoxScaleX, 1, accuracy: 0.000_001)
        XCTAssertEqual(equal.boundingBoxScaleY, 1, accuracy: 0.000_001)

        let shiftedQuad = DocumentQuad(
            topLeft: NormalizedPoint(x: 0.25, y: 0.2),
            topRight: NormalizedPoint(x: 0.85, y: 0.2),
            bottomRight: NormalizedPoint(x: 0.85, y: 0.8),
            bottomLeft: NormalizedPoint(x: 0.25, y: 0.8)
        )
        let shifted = ScannerFOVComparison.compare(
            liveQuad: liveQuad,
            liveTransform: liveTransform,
            stillQuad: shiftedQuad,
            stillTransform: stillTransform
        )
        let expectedPercent = 50 / hypot(1_000.0, 700.0) * 100
        XCTAssertEqual(
            shifted.meanCornerErrorPercentOfPreviewDiagonal,
            expectedPercent,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            shifted.centroidDriftPercentOfPreviewDiagonal,
            expectedPercent,
            accuracy: 0.000_001
        )
        XCTAssertEqual(shifted.boundingBoxScaleX, 1, accuracy: 0.000_001)
        XCTAssertEqual(shifted.boundingBoxScaleY, 1, accuracy: 0.000_001)
    }

    func testDocumentQuadAreaAndCaptureGates() {
        let quad = DocumentQuad(
            topLeft: NormalizedPoint(x: 0.1, y: 0.2),
            topRight: NormalizedPoint(x: 0.9, y: 0.2),
            bottomRight: NormalizedPoint(x: 0.9, y: 0.7),
            bottomLeft: NormalizedPoint(x: 0.1, y: 0.7)
        )
        XCTAssertEqual(quad.normalizedArea, 0.4, accuracy: 0.000_001)
        XCTAssertTrue(quad.isInsideUnitSquare)

        let passing = passingGates(quad: quad)
        XCTAssertTrue(passing.allGatesPass)

        let guided = CaptureGateSnapshot(
            detection: passing.detection,
            framingGuidance: .moveCloser,
            cornersStable: true,
            deviceStill: true,
            sharpEnough: true,
            focusReady: true
        )
        XCTAssertFalse(guided.allGatesPass)
    }

    func testAutomaticCaptureRequiresConsecutivePassingFrames() {
        var machine = DocumentScannerStateMachine()
        XCTAssertEqual(machine.handle(.start), [.requestCameraAccess])
        XCTAssertEqual(machine.state, .preparingCamera)
        XCTAssertEqual(machine.handle(.cameraReady), [.startCamera])
        XCTAssertEqual(machine.state, .searching)

        let gates = passingGates()
        XCTAssertEqual(
            machine.handle(.frameEvaluated(gates)),
            [.stopGuidance]
        )
        XCTAssertEqual(machine.state, .stabilizing(passedGateFrames: 1))

        XCTAssertEqual(
            machine.handle(.frameEvaluated(gates)),
            [.stopGuidance]
        )
        XCTAssertEqual(machine.state, .stabilizing(passedGateFrames: 2))

        let effects = machine.handle(.frameEvaluated(gates))
        guard case .lockingFocus(let ticket) = machine.state else {
            return XCTFail("Third consecutive passing frame must lock focus")
        }
        XCTAssertEqual(effects, [.stopGuidance, .lockFocus(ticket: ticket)])

        XCTAssertEqual(machine.handle(.focusLocked(ticket: UUID())), [])
        XCTAssertEqual(machine.state, .lockingFocus(ticket: ticket))
        XCTAssertEqual(
            machine.handle(.focusLocked(ticket: ticket)),
            [.capturePhoto(ticket: ticket)]
        )
        XCTAssertEqual(machine.state, .capturing(ticket: ticket))
    }

    func testGuidanceBreaksTheConsecutiveGateSequence() {
        var machine = DocumentScannerStateMachine()
        _ = machine.handle(.start)
        _ = machine.handle(.cameraReady)

        XCTAssertEqual(
            machine.handle(.frameEvaluated(passingGates())),
            [.stopGuidance]
        )
        XCTAssertEqual(machine.state, .stabilizing(passedGateFrames: 1))

        let guided = CaptureGateSnapshot(
            detection: passingGates().detection,
            framingGuidance: .moveLeft,
            cornersStable: true,
            deviceStill: true,
            sharpEnough: true,
            focusReady: true
        )
        XCTAssertEqual(
            machine.handle(.frameEvaluated(guided)),
            [.updateGuidance(.moveLeft)]
        )
        XCTAssertEqual(machine.state, .guiding(.moveLeft))

        XCTAssertEqual(
            machine.handle(.frameEvaluated(passingGates())),
            [.stopGuidance]
        )
        XCTAssertEqual(machine.state, .stabilizing(passedGateFrames: 1))
    }

    func testReviewingCanResumeTheLocalCamera() {
        var machine = DocumentScannerStateMachine()
        _ = machine.handle(.start)
        _ = machine.handle(.cameraReady)
        _ = machine.handle(.manualCaptureRequested)
        guard case .lockingFocus(let ticket) = machine.state else {
            return XCTFail("Manual capture must lock focus")
        }
        _ = machine.handle(.focusLocked(ticket: ticket))
        _ = machine.handle(.photoCaptured(ticket: ticket))
        _ = machine.handle(
            .processingSucceeded(ticket: ticket, pageID: UUID())
        )

        XCTAssertEqual(
            machine.handle(.resumeScanning),
            [.startCamera, .clearDetectionOverlay]
        )
        XCTAssertEqual(machine.state, .searching)
    }

    func testClockwiseRotationUsesTopLeftRowMajorCoordinates() throws {
        let source = try redChannelImage(
            width: 2,
            height: 3,
            values: [
                1, 2,
                3, 4,
                5, 6
            ]
        )

        let rotated = AndroidScannerImageMath.rotatedClockwise(
            source,
            degrees: 90
        )

        XCTAssertEqual(rotated.width, 3)
        XCTAssertEqual(rotated.height, 2)
        XCTAssertEqual(redChannelValues(in: rotated), [
            5, 3, 1,
            6, 4, 2
        ])
    }

    func testLetterboxUsesBlackRowsAndNCHWRGBChannelOrder() throws {
        let source = try ScannerRGBAImage(
            width: 2,
            height: 1,
            bytes: [
                255, 0, 64, 255,
                0, 128, 255, 255
            ]
        )

        let prepared = AndroidScannerImageMath.letterboxedRGBTensor(
            from: source,
            size: 4
        )

        XCTAssertEqual(prepared.shape, [1, 3, 4, 4])
        XCTAssertEqual(
            prepared.letterbox,
            ScannerLetterboxTransform(
                originalWidth: 2,
                originalHeight: 1,
                scaledWidth: 4,
                scaledHeight: 2,
                padX: 0,
                padY: 1,
                canvasSize: 4
            )
        )

        let planeSize = 16
        for channel in 0 ..< 3 {
            let planeOffset = channel * planeSize
            XCTAssertEqual(
                Array(prepared.values[planeOffset ..< planeOffset + 4]),
                [0, 0, 0, 0]
            )
            XCTAssertEqual(
                Array(
                    prepared.values[
                        planeOffset + 12 ..< planeOffset + planeSize
                    ]
                ),
                [0, 0, 0, 0]
            )
        }

        XCTAssertEqual(prepared.values[4], 1, accuracy: 0.000_001)
        XCTAssertEqual(prepared.values[planeSize + 4], 0, accuracy: 0.000_001)
        XCTAssertEqual(
            prepared.values[(planeSize * 2) + 4],
            64.0 / 255.0,
            accuracy: 0.000_001
        )
    }

    func testLCNetLetterboxPlanPreservesFloatTruncationBoundary() {
        XCTAssertEqual(
            AndroidScannerImageMath.letterboxTransform(
                sourceWidth: 3_024,
                sourceHeight: 3_024,
                size: 256
            ),
            ScannerLetterboxTransform(
                originalWidth: 3_024,
                originalHeight: 3_024,
                scaledWidth: 255,
                scaledHeight: 255,
                padX: 0,
                padY: 0,
                canvasSize: 256
            )
        )
        XCTAssertEqual(
            AndroidScannerImageMath.letterboxTransform(
                sourceWidth: 2_268,
                sourceHeight: 3_024,
                size: 256
            ),
            ScannerLetterboxTransform(
                originalWidth: 2_268,
                originalHeight: 3_024,
                scaledWidth: 192,
                scaledHeight: 255,
                padX: 32,
                padY: 0,
                canvasSize: 256
            )
        )
    }

    func testCoreImageRasterizationKeepsVisualTopRowFirst() throws {
        let top = CIImage(
            color: CIColor(red: 1, green: 0, blue: 0, alpha: 1)
        ).cropped(to: CGRect(x: 10, y: 21, width: 2, height: 1))
        let bottom = CIImage(
            color: CIColor(red: 0, green: 0, blue: 1, alpha: 1)
        ).cropped(to: CGRect(x: 10, y: 20, width: 2, height: 1))
        let image = top.composited(over: bottom)

        let raster = try ScannerCIImageBridge(
            context: CIContext(options: [.useSoftwareRenderer: true])
        ).rgbaImage(from: image)

        XCTAssertEqual(raster.width, 2)
        XCTAssertEqual(raster.height, 2)
        XCTAssertEqual(raster.bytes, [
            255, 0, 0, 255,
            255, 0, 0, 255,
            0, 0, 255, 255,
            0, 0, 255, 255
        ])
    }

    func testCoreImageTopLeftCropMatchesPixelCrop() throws {
        let source = try patternedImage(width: 11, height: 8)
        let cropRect = ScannerPixelRect(
            x: 2,
            y: 1,
            width: 6,
            height: 5
        )
        let expected = try source.cropped(to: cropRect)
        let bridge = ScannerCIImageBridge()
        let cropped = try bridge.rgbaImage(
            from: bridge.ciImage(from: source),
            topLeftCropRect: cropRect
        )

        XCTAssertEqual(cropped, expected)
    }

    func testPaddedBGRAPixelBufferCropProducesTopLeftRGBA() throws {
        var optionalPixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferBytesPerRowAlignmentKey as String: 64
        ] as CFDictionary
        XCTAssertEqual(
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                3,
                3,
                kCVPixelFormatType_32BGRA,
                attributes,
                &optionalPixelBuffer
            ),
            kCVReturnSuccess
        )
        let pixelBuffer = try XCTUnwrap(optionalPixelBuffer)
        XCTAssertGreaterThan(CVPixelBufferGetBytesPerRow(pixelBuffer), 12)
        XCTAssertEqual(
            CVPixelBufferLockBaseAddress(pixelBuffer, []),
            kCVReturnSuccess
        )
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            return XCTFail("Pixel buffer must expose writable storage")
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let storage = baseAddress.assumingMemoryBound(to: UInt8.self)
        for y in 0 ..< 3 {
            for x in 0 ..< 3 {
                let offset = y * bytesPerRow + x * 4
                let seed = UInt8(y * 10 + x)
                storage[offset] = seed
                storage[offset + 1] = seed + 40
                storage[offset + 2] = seed + 80
                storage[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        let cropped = try ScannerRGBAImage.readingBGRA(
            pixelBuffer,
            cropRect: ScannerPixelRect(x: 1, y: 1, width: 2, height: 2)
        )

        XCTAssertEqual(cropped.width, 2)
        XCTAssertEqual(cropped.height, 2)
        XCTAssertEqual(cropped.bytes, [
            91, 51, 11, 255,
            92, 52, 12, 255,
            101, 61, 21, 255,
            102, 62, 22, 255
        ])

        let full = try ScannerRGBAImage.readingBGRA(pixelBuffer)
        let directFullResize = try ScannerRGBAImage.readingBGRA(
            pixelBuffer,
            cropRect: ScannerPixelRect(
                x: 0,
                y: 0,
                width: 3,
                height: 3
            ),
            outputWidth: 2,
            outputHeight: 2
        )
        XCTAssertEqual(
            directFullResize,
            AndroidScannerImageMath.resizeBilinear(
                full,
                width: 2,
                height: 2
            )
        )

        let tallCropRect = ScannerPixelRect(
            x: 1,
            y: 0,
            width: 2,
            height: 3
        )
        let expectedTallCrop = AndroidScannerImageMath.resizeBilinear(
            try full.cropped(to: tallCropRect),
            width: 1,
            height: 2
        )
        XCTAssertEqual(
            try ScannerRGBAImage.readingBGRA(
                pixelBuffer,
                cropRect: tallCropRect,
                outputWidth: 1,
                outputHeight: 2
            ),
            expectedTallCrop
        )
        XCTAssertEqual(
            try ScannerRGBAImage.readingBGRA(
                pixelBuffer,
                cropRect: tallCropRect,
                maximumLongEdge: 2
            ),
            expectedTallCrop
        )

        let referenceCrop = try full.cropped(to: tallCropRect)
        let referenceTensor = AndroidScannerImageMath
            .letterboxedRGBTensor(from: referenceCrop, size: 4)
        let letterbox = AndroidScannerImageMath.letterboxTransform(
            sourceWidth: tallCropRect.width,
            sourceHeight: tallCropRect.height,
            size: 4
        )
        let directModelImage = try ScannerRGBAImage.readingBGRA(
            pixelBuffer,
            cropRect: tallCropRect,
            outputWidth: letterbox.scaledWidth,
            outputHeight: letterbox.scaledHeight
        )
        XCTAssertEqual(
            AndroidScannerImageMath.letterboxedRGBTensor(
                fromResized: directModelImage,
                letterbox: letterbox
            ),
            referenceTensor
        )
    }

    func testMetalCameraPreparationMatchesPaddedBGRAReference() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this test destination")
        }
        var optionalPixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferBytesPerRowAlignmentKey as String: 64,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: NSDictionary()
        ] as CFDictionary
        XCTAssertEqual(
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                5,
                4,
                kCVPixelFormatType_32BGRA,
                attributes,
                &optionalPixelBuffer
            ),
            kCVReturnSuccess
        )
        let pixelBuffer = try XCTUnwrap(optionalPixelBuffer)
        XCTAssertGreaterThan(CVPixelBufferGetBytesPerRow(pixelBuffer), 20)
        XCTAssertEqual(
            CVPixelBufferLockBaseAddress(pixelBuffer, []),
            kCVReturnSuccess
        )
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            return XCTFail("Pixel buffer must expose writable storage")
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let storage = baseAddress.assumingMemoryBound(to: UInt8.self)
        for y in 0 ..< 4 {
            for x in 0 ..< 5 {
                let offset = y * bytesPerRow + x * 4
                storage[offset] = UInt8((x * 11 + y * 17) % 256)
                storage[offset + 1] =
                    UInt8((x * 31 + y * 7 + 13) % 256)
                storage[offset + 2] =
                    UInt8((x * 19 + y * 23 + 29) % 256)
                storage[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        let cropRect = ScannerPixelRect(
            x: 1,
            y: 1,
            width: 3,
            height: 2
        )
        let letterbox = AndroidScannerImageMath.letterboxTransform(
            sourceWidth: cropRect.width,
            sourceHeight: cropRect.height,
            size: 7
        )
        let detectorImage = try ScannerRGBAImage.readingBGRA(
            pixelBuffer,
            cropRect: cropRect,
            outputWidth: letterbox.scaledWidth,
            outputHeight: letterbox.scaledHeight
        )
        let cpuTensor = AndroidScannerImageMath.letterboxedRGBTensor(
            fromResized: detectorImage,
            letterbox: letterbox
        )
        let cpuSharpness = try ScannerRGBAImage.readingBGRA(
            pixelBuffer,
            cropRect: cropRect,
            outputWidth: 4,
            outputHeight: 3
        )
        let metal = try AndroidMetalImageSampler().prepareLiveFrame(
            pixelBuffer,
            cropRect: cropRect,
            letterbox: letterbox,
            sharpnessWidth: 4,
            sharpnessHeight: 3
        )

        XCTAssertEqual(metal.modelInput.shape, cpuTensor.shape)
        XCTAssertEqual(metal.modelInput.letterbox, letterbox)
        let maximumTensorDifference = zip(
            metal.modelInput.values,
            cpuTensor.values
        ).reduce(Float.zero) { current, values in
            max(current, abs(values.0 - values.1))
        }
        XCTAssertLessThanOrEqual(
            maximumTensorDifference,
            (1.0 / 255.0) + Float.ulpOfOne
        )
        XCTAssertEqual(
            metal.sharpnessSample.width,
            cpuSharpness.width
        )
        XCTAssertEqual(
            metal.sharpnessSample.height,
            cpuSharpness.height
        )
        XCTAssertLessThanOrEqual(
            maximumChannelDifference(
                metal.sharpnessSample.bytes,
                cpuSharpness.bytes
            ),
            1
        )
    }

    func testCaptureGateRequiresSevenStableFramesAndRejectsJitter() {
        var evaluator = DocumentCaptureGateEvaluator()
        let stableDetection = DocumentDetection(
            quad: DocumentQuad(
                topLeft: NormalizedPoint(x: 0.1, y: 0.1),
                topRight: NormalizedPoint(x: 0.9, y: 0.1),
                bottomRight: NormalizedPoint(x: 0.9, y: 0.9),
                bottomLeft: NormalizedPoint(x: 0.1, y: 0.9)
            ),
            confidence: 0.99
        )

        for frame in 1 ... 7 {
            let snapshot = evaluator.evaluate(
                detection: stableDetection,
                imageWidth: 1_000,
                imageHeight: 1_000,
                sharpness: 100,
                deviceStill: true,
                focusReady: true
            )
            XCTAssertEqual(snapshot.cornersStable, frame == 7)
            XCTAssertEqual(snapshot.allGatesPass, frame == 7)
        }

        let jitteredDetection = DocumentDetection(
            quad: DocumentQuad(
                topLeft: NormalizedPoint(x: 0.2, y: 0.1),
                topRight: stableDetection.quad.topRight,
                bottomRight: stableDetection.quad.bottomRight,
                bottomLeft: stableDetection.quad.bottomLeft
            ),
            confidence: 0.99
        )
        let jittered = evaluator.evaluate(
            detection: jitteredDetection,
            imageWidth: 1_000,
            imageHeight: 1_000,
            sharpness: 100,
            deviceStill: true,
            focusReady: true
        )
        XCTAssertFalse(jittered.cornersStable)
        XCTAssertFalse(jittered.allGatesPass)
    }

    func testRotatedAspectFillViewportUsesRawSensorTopLeftCoordinates() throws {
        let configuration = ScannerViewportConfiguration(
            previewWidth: 200,
            previewHeight: 200,
            previewRotationDegrees: 90,
            generation: 1
        )
        let transform = try XCTUnwrap(
            ScannerViewportTransform(
                rawWidth: 400,
                rawHeight: 300,
                configuration: configuration
            )
        )

        XCTAssertEqual(
            transform.rawCropRect,
            ScannerPixelRect(x: 50, y: 0, width: 300, height: 300)
        )
        let rawCropTopLeft = transform.previewPoint(
            for: NormalizedPoint(x: 0, y: 0)
        )
        let rawCropTopRight = transform.previewPoint(
            for: NormalizedPoint(x: 1, y: 0)
        )
        XCTAssertEqual(rawCropTopLeft.x, 200, accuracy: 0.001)
        XCTAssertEqual(rawCropTopLeft.y, 0, accuracy: 0.001)
        XCTAssertEqual(rawCropTopRight.x, 200, accuracy: 0.001)
        XCTAssertEqual(rawCropTopRight.y, 200, accuracy: 0.001)
    }

    func testAspectFillViewportAcrossAllCardinalRotations() throws {
        struct Fixture {
            let rotation: Int
            let previewWidth: Double
            let previewHeight: Double
            let expectedTopLeft: CGPoint
        }
        let fixtures = [
            Fixture(
                rotation: 0,
                previewWidth: 200,
                previewHeight: 300,
                expectedTopLeft: CGPoint(x: 0, y: 0)
            ),
            Fixture(
                rotation: 90,
                previewWidth: 300,
                previewHeight: 200,
                expectedTopLeft: CGPoint(x: 300, y: 0)
            ),
            Fixture(
                rotation: 180,
                previewWidth: 200,
                previewHeight: 300,
                expectedTopLeft: CGPoint(x: 200, y: 300)
            ),
            Fixture(
                rotation: 270,
                previewWidth: 300,
                previewHeight: 200,
                expectedTopLeft: CGPoint(x: 0, y: 200)
            )
        ]

        for fixture in fixtures {
            let transform = try XCTUnwrap(
                ScannerViewportTransform(
                    rawWidth: 400,
                    rawHeight: 300,
                    configuration: ScannerViewportConfiguration(
                        previewWidth: fixture.previewWidth,
                        previewHeight: fixture.previewHeight,
                        previewRotationDegrees: fixture.rotation,
                        generation: 1
                    )
                )
            )
            XCTAssertEqual(
                transform.rawCropRect,
                ScannerPixelRect(x: 100, y: 0, width: 200, height: 300),
                "rotation \(fixture.rotation)"
            )
            let topLeft = transform.previewPoint(
                for: NormalizedPoint(x: 0, y: 0)
            )
            XCTAssertEqual(
                topLeft.x,
                fixture.expectedTopLeft.x,
                accuracy: 0.001,
                "rotation \(fixture.rotation)"
            )
            XCTAssertEqual(
                topLeft.y,
                fixture.expectedTopLeft.y,
                accuracy: 0.001,
                "rotation \(fixture.rotation)"
            )
        }
    }

    func testFrameAdmissionDropsBusyFramesAndInvalidatesRotations() throws {
        let admission = ScannerFrameAdmissionController(framesPerSecond: 10)
        admission.update(
            previewWidth: 1_000,
            previewHeight: 700,
            rotationDegrees: 0
        )

        let first = try XCTUnwrap(admission.beginFrame(timestamp: 1))
        XCTAssertNil(admission.beginFrame(timestamp: 1.2))
        XCTAssertTrue(admission.isCurrent(generation: first.generation))

        admission.update(
            previewWidth: 1_000,
            previewHeight: 700,
            rotationDegrees: 90
        )
        XCTAssertFalse(admission.isCurrent(generation: first.generation))

        admission.finishFrame()
        XCTAssertNil(admission.beginFrame(timestamp: 1.05))
        let rotated = try XCTUnwrap(admission.beginFrame(timestamp: 1.2))
        XCTAssertEqual(rotated.previewRotationDegrees, 90)
        admission.finishFrame()
    }

    func testSensorGuidanceRotatesIntoPreviewCoordinates() {
        XCTAssertEqual(
            ScannerViewportTransform.displayGuidance(
                for: .moveLeft,
                rotationDegrees: 90
            ),
            .moveUp
        )
        XCTAssertEqual(
            ScannerViewportTransform.displayGuidance(
                for: .moveUp,
                rotationDegrees: 180
            ),
            .moveDown
        )
        XCTAssertEqual(
            ScannerViewportTransform.displayGuidance(
                for: .moveRight,
                rotationDegrees: 270
            ),
            .moveUp
        )
        XCTAssertEqual(
            ScannerViewportTransform.displayGuidance(
                for: .moveCloser,
                rotationDegrees: 270
            ),
            .moveCloser
        )
    }

    func testMetalUVDocWarpMatchesCPUReference() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this test destination")
        }
        var sourceBytes: [UInt8] = []
        for pixel in 0 ..< 12 {
            sourceBytes.append(contentsOf: [
                UInt8(pixel * 17),
                UInt8(255 - pixel * 13),
                UInt8(pixel * 7),
                255
            ])
        }
        let source = try ScannerRGBAImage(
            width: 4,
            height: 3,
            bytes: sourceBytes
        )
        let identityGrid = UVDocGrid(
            values: [
                -1, -1,
                 1, -1,
                -1,  1,
                 1,  1
            ],
            height: 2,
            width: 2
        )

        let cpu = try UVDocGridSampler.warp(
            source,
            with: identityGrid,
            outputWidth: 7,
            outputHeight: 5
        )
        let metal = try UVDocMetalGridSampler().warp(
            source,
            with: identityGrid,
            outputWidth: 7,
            outputHeight: 5
        )
        XCTAssertEqual(metal, cpu)

        let nonlinearBorderGrid = UVDocGrid(
            values: [
                -1.25, -1.20,  0.00, -1.05,  1.20, -0.90,
                -1.10,  0.10,  0.20, -0.15,  1.15,  0.20,
                -0.85,  1.25, -0.10,  1.05,  1.30,  1.20
            ],
            height: 3,
            width: 3
        )
        let nonlinearCPU = try UVDocGridSampler.warp(
            source,
            with: nonlinearBorderGrid,
            outputWidth: 19,
            outputHeight: 15
        )
        let nonlinearMetal = try UVDocMetalGridSampler().warp(
            source,
            with: nonlinearBorderGrid,
            outputWidth: 19,
            outputHeight: 15
        )
        XCTAssertEqual(nonlinearMetal, nonlinearCPU)
    }

    func testMetalResizeMatchesAndroidCPUReference() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this test destination")
        }
        let source = try patternedImage(width: 13, height: 9)
        let cpu = AndroidScannerImageMath.resizeBilinear(
            source,
            width: 19,
            height: 14
        )
        let metal = try AndroidMetalImageSampler().resizeBilinear(
            source,
            width: 19,
            height: 14
        )

        XCTAssertEqual(metal.width, cpu.width)
        XCTAssertEqual(metal.height, cpu.height)
        XCTAssertLessThanOrEqual(
            maximumChannelDifference(metal.bytes, cpu.bytes),
            1
        )
    }

    func testMetalCardinalRotationsMatchAndroidCPUReference() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this test destination")
        }
        let source = try patternedImage(width: 13, height: 9)
        let sampler = try AndroidMetalImageSampler()

        for degrees in [0, 90, 180, 270] {
            let cpu = AndroidScannerImageMath.rotatedClockwise(
                source,
                degrees: degrees
            )
            let metal = try sampler.rotatedClockwise(
                source,
                degrees: degrees
            )

            XCTAssertEqual(metal, cpu, "rotation \(degrees)")
        }
    }

    func testMetalStretchedTensorMatchesAndroidCPUReference() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this test destination")
        }
        let source = try patternedImage(width: 37, height: 29)
        let cpu = AndroidScannerImageMath.stretchedRGBTensor(
            from: source,
            width: 53,
            height: 41
        )
        let metal = try AndroidMetalImageSampler().stretchedRGBTensor(
            source,
            width: 53,
            height: 41
        )

        XCTAssertEqual(metal.shape, cpu.shape)
        XCTAssertNil(metal.letterbox)
        XCTAssertEqual(metal.values.count, cpu.values.count)
        let maximumDifference = zip(metal.values, cpu.values)
            .reduce(Float.zero) { current, values in
                max(current, abs(values.0 - values.1))
            }
        XCTAssertLessThanOrEqual(
            maximumDifference,
            (1.0 / 255.0) + Float.ulpOfOne
        )
    }

    func testMetalDocumentColorMatchesAndroidCPUReference() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this test destination")
        }
        let source = try patternedImage(width: 37, height: 29)
        let parameters = AndroidDocumentColorMath.parameters(for: source)
        let cpu = AndroidDocumentColorMath.enhance(
            source,
            parameters: parameters
        )
        let metal = try AndroidMetalImageSampler().enhanceDocument(
            source,
            parameters: parameters
        )

        XCTAssertEqual(metal.width, cpu.width)
        XCTAssertEqual(metal.height, cpu.height)
        XCTAssertLessThanOrEqual(
            maximumChannelDifference(metal.bytes, cpu.bytes),
            1
        )
    }

    func testMetalPerspectiveMatchesAndroidCPUReference() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this test destination")
        }
        let source = try patternedImage(width: 16, height: 12)
        let corners = [
            ScannerPixelPoint(x: 1.2, y: 1.1),
            ScannerPixelPoint(x: 14.5, y: 0.7),
            ScannerPixelPoint(x: 13.8, y: 10.6),
            ScannerPixelPoint(x: 0.6, y: 10.2)
        ]
        let outputSize = ScannerPixelSize(width: 21, height: 17)
        let cpu = try AndroidPerspectiveMath.warp(
            source,
            orderedCorners: corners,
            outputSize: outputSize
        )
        let metal = try AndroidMetalImageSampler().perspectiveWarp(
            source,
            orderedCorners: corners,
            outputSize: outputSize
        )

        XCTAssertEqual(metal.width, cpu.width)
        XCTAssertEqual(metal.height, cpu.height)
        XCTAssertLessThanOrEqual(
            maximumChannelDifference(metal.bytes, cpu.bytes),
            1
        )
    }

    func testPixelNativePerspectiveMatchesCIImageAdapter() async throws {
        let source = try patternedImage(width: 16, height: 12)
        let quad = DocumentQuad(
            topLeft: NormalizedPoint(x: 0.08, y: 0.12),
            topRight: NormalizedPoint(x: 0.92, y: 0.08),
            bottomRight: NormalizedPoint(x: 0.88, y: 0.91),
            bottomLeft: NormalizedPoint(x: 0.11, y: 0.86)
        )
        let corrector = AndroidPerspectiveCorrector(
            metalSampler: nil
        )
        let pixelNative = try await corrector.correctPixels(
            source,
            using: quad
        )
        let bridge = ScannerCIImageBridge()
        let adapted = try await corrector.correct(
            bridge.ciImage(from: source),
            using: quad
        )
        let adaptedPixels = try bridge.rgbaImage(from: adapted)

        XCTAssertEqual(pixelNative, adaptedPixels)
    }

    private func passingGates(
        quad: DocumentQuad = DocumentQuad(
            topLeft: NormalizedPoint(x: 0.1, y: 0.1),
            topRight: NormalizedPoint(x: 0.9, y: 0.1),
            bottomRight: NormalizedPoint(x: 0.9, y: 0.9),
            bottomLeft: NormalizedPoint(x: 0.1, y: 0.9)
        )
    ) -> CaptureGateSnapshot {
        CaptureGateSnapshot(
            detection: DocumentDetection(quad: quad, confidence: 0.95),
            framingGuidance: nil,
            cornersStable: true,
            deviceStill: true,
            sharpEnough: true,
            focusReady: true
        )
    }

    private func redChannelImage(
        width: Int,
        height: Int,
        values: [UInt8]
    ) throws -> ScannerRGBAImage {
        XCTAssertEqual(values.count, width * height)
        return try ScannerRGBAImage(
            width: width,
            height: height,
            bytes: values.flatMap { [$0, 0, 0, 255] }
        )
    }

    private func redChannelValues(in image: ScannerRGBAImage) -> [UInt8] {
        stride(from: 0, to: image.bytes.count, by: 4).map {
            image.bytes[$0]
        }
    }

    private func patternedImage(
        width: Int,
        height: Int
    ) throws -> ScannerRGBAImage {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                bytes.append(UInt8((x * 19 + y * 7) % 256))
                bytes.append(UInt8((x * 5 + y * 23 + 31) % 256))
                bytes.append(UInt8((x * 29 + y * 3 + 17) % 256))
                bytes.append(255)
            }
        }
        return try ScannerRGBAImage(
            width: width,
            height: height,
            bytes: bytes
        )
    }

    private func maximumChannelDifference(
        _ first: [UInt8],
        _ second: [UInt8]
    ) -> Int {
        XCTAssertEqual(first.count, second.count)
        return zip(first, second).reduce(0) { maximum, values in
            max(maximum, abs(Int(values.0) - Int(values.1)))
        }
    }
}
