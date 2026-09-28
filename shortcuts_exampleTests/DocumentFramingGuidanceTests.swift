import XCTest

@testable import shortcuts_example

final class DocumentFramingGuidanceTests: XCTestCase {
    func testPartialPagesPointTowardEachClippedEdge() throws {
        let examples: [(Range<Int>, Range<Int>, DocumentFramingGuidance)] = [
            (0 ..< 30, 20 ..< 80, .moveLeft),
            (34 ..< 64, 20 ..< 80, .moveRight),
            (16 ..< 48, 0 ..< 60, .moveUp),
            (16 ..< 48, 36 ..< 96, .moveDown),
        ]
        for (xRange, yRange, direction) in examples {
            let image = try pageImage(x: xRange, y: yRange)
            XCTAssertEqual(PartialDocumentFramingGuidance.evaluate(image), direction)
        }
    }

    func testPartialGuidanceIgnoresCenteredDarkSaturatedAndTinyRegions() throws {
        let images = try [
            pageImage(x: 10 ..< 54, y: 12 ..< 84),
            pageImage(x: 0 ..< 30, y: 20 ..< 80, color: (100, 100, 100)),
            pageImage(x: 0 ..< 30, y: 20 ..< 80, color: (255, 255, 0)),
            pageImage(x: 0 ..< 3, y: 20 ..< 30),
        ]
        for image in images {
            XCTAssertNil(PartialDocumentFramingGuidance.evaluate(image))
        }
    }

    func testLargestPageCandidateWinsOverSmallerEdgeRegion() throws {
        var image = try pageImage(x: 14 ..< 58, y: 12 ..< 84)
        paint(&image, x: 0 ..< 7, y: 25 ..< 60, color: (230, 230, 230))
        XCTAssertNil(PartialDocumentFramingGuidance.evaluate(image))
    }

    func testPartialGuidanceWorksWithBoundedCameraQualitySample() throws {
        let original = try pageImage(x: 0 ..< 30, y: 20 ..< 80)
        let qualitySample = AndroidScannerImageMath.resizeBilinear(
            original, width: 96, height: 64
        )
        XCTAssertEqual(PartialDocumentFramingGuidance.evaluate(qualitySample), .moveLeft)
    }

    func testPartialPageDirectionsRotateWithIPadOrientation() throws {
        let image = try pageImage(x: 0 ..< 30, y: 20 ..< 80)
        let rawDirection = try XCTUnwrap(PartialDocumentFramingGuidance.evaluate(image))
        let expected: [(Int, DocumentFramingGuidance)] = [
            (0, .moveLeft), (90, .moveUp),
            (180, .moveRight), (270, .moveDown),
        ]
        for (rotation, direction) in expected {
            XCTAssertEqual(
                ScannerViewportTransform.displayGuidance(
                    for: rawDirection, rotationDegrees: rotation
                ),
                direction
            )
        }
    }

    func testRepeatedFramesDoNotRepeatOrInterruptSpeech() {
        var policy = DocumentGuidanceSpeechPolicy()
        XCTAssertEqual(policy.update(.moveLeft, at: 0, isSpeaking: false), [.speak(.moveLeft)])
        XCTAssertEqual(policy.update(.moveLeft, at: 0.1, isSpeaking: true), [])
        XCTAssertEqual(policy.update(.moveLeft, at: 5.99, isSpeaking: false), [])
        XCTAssertEqual(policy.update(.moveLeft, at: 6, isSpeaking: true), [])
        XCTAssertEqual(policy.update(.moveLeft, at: 7, isSpeaking: false), [.speak(.moveLeft)])
        XCTAssertEqual(policy.update(.moveLeft, at: 7.1, isSpeaking: false), [])
    }

    func testDirectionChangeStopsOldSpeechAndWaitsForStableNewDirection() {
        var policy = DocumentGuidanceSpeechPolicy()
        _ = policy.update(.moveLeft, at: 0, isSpeaking: false)
        XCTAssertEqual(policy.update(.moveRight, at: 0.5, isSpeaking: true), [.stop])
        XCTAssertEqual(policy.update(.moveRight, at: 1.4, isSpeaking: false), [])
        XCTAssertEqual(policy.update(.moveRight, at: 1.5, isSpeaking: false), [.speak(.moveRight)])
    }

    func testJitterResetsPendingDirectionInsteadOfSpeakingStaleInstruction() {
        var policy = DocumentGuidanceSpeechPolicy()
        _ = policy.update(.moveLeft, at: 0, isSpeaking: false)
        _ = policy.update(.moveRight, at: 0.5, isSpeaking: true)
        XCTAssertEqual(policy.update(.moveUp, at: 1, isSpeaking: false), [.stop])
        XCTAssertEqual(policy.update(.moveUp, at: 1.5, isSpeaking: false), [])
        XCTAssertEqual(policy.update(.moveUp, at: 2, isSpeaking: false), [.speak(.moveUp)])
    }

    func testClearingGuidanceCancelsPendingSpeechAndResetsRepeatInterval() {
        var policy = DocumentGuidanceSpeechPolicy()
        _ = policy.update(.moveLeft, at: 0, isSpeaking: false)
        _ = policy.update(.moveRight, at: 0.5, isSpeaking: true)
        XCTAssertEqual(policy.update(nil, at: 0.6, isSpeaking: false), [.stop])
        XCTAssertNil(policy.currentGuidance)
        XCTAssertEqual(policy.update(nil, at: 3, isSpeaking: false), [])
        XCTAssertEqual(policy.update(.moveRight, at: 3.1, isSpeaking: false), [.speak(.moveRight)])
    }

    func testPartialPageGuidesWithoutPermittingAutomaticCapture() {
        var machine = DocumentScannerStateMachine()
        _ = machine.handle(.start)
        _ = machine.handle(.cameraReady)
        let partialPage = CaptureGateSnapshot(
            detection: nil, framingGuidance: .moveLeft,
            cornersStable: true, deviceStill: true,
            sharpEnough: true, focusReady: true
        )
        XCTAssertFalse(partialPage.allGatesPass)
        for _ in 0 ..< 20 {
            XCTAssertEqual(
                machine.handle(.frameEvaluated(partialPage)),
                [.clearDetectionOverlay, .updateGuidance(.moveLeft)]
            )
        }
        XCTAssertEqual(machine.state, .guiding(.moveLeft))
        let effects = machine.handle(.manualCaptureRequested)
        guard case .lockingFocus(let ticket) = machine.state else {
            return XCTFail("Manual capture must remain available for partial pages")
        }
        XCTAssertEqual(effects, [.stopGuidance, .lockFocus(ticket: ticket)])
    }

    func testLosingPartialPageStopsGuidanceAndClearsOverlay() {
        var machine = DocumentScannerStateMachine()
        _ = machine.handle(.start)
        _ = machine.handle(.cameraReady)
        _ = machine.handle(.frameEvaluated(CaptureGateSnapshot(
            detection: nil, framingGuidance: .moveDown,
            cornersStable: false, deviceStill: true,
            sharpEnough: false, focusReady: true
        )))
        XCTAssertEqual(
            machine.handle(.frameEvaluated(CaptureGateSnapshot(
                detection: nil, framingGuidance: nil,
                cornersStable: false, deviceStill: true,
                sharpEnough: false, focusReady: true
            ))),
            [.stopGuidance, .clearDetectionOverlay]
        )
        XCTAssertEqual(machine.state, .searching)
    }

    private func pageImage(
        x: Range<Int>, y: Range<Int>,
        color: (UInt8, UInt8, UInt8) = (230, 230, 230)
    ) throws -> ScannerRGBAImage {
        var image = try ScannerRGBAImage(
            width: 64, height: 96,
            bytes: [UInt8](repeating: 0, count: 64 * 96 * 4)
        )
        paint(&image, x: x, y: y, color: color)
        return image
    }

    private func paint(
        _ image: inout ScannerRGBAImage,
        x: Range<Int>, y: Range<Int>,
        color: (UInt8, UInt8, UInt8)
    ) {
        for row in y {
            for column in x {
                let offset = image.byteOffset(x: column, y: row)
                image.bytes[offset] = color.0
                image.bytes[offset + 1] = color.1
                image.bytes[offset + 2] = color.2
                image.bytes[offset + 3] = 255
            }
        }
    }
}
