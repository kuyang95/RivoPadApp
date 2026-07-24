import CoreImage
import Metal
import CoreVideo
import XCTest

@testable import shortcuts_example

final class ScannerRegressionTests: XCTestCase {
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
}
