import XCTest
@testable import shortcuts_example

final class VisionLinkVideoQualityTests: XCTestCase {
    func testMeasuredOutputUsesByteAndFrameDeltas() throws {
        var meter = VisionLinkVideoQualityMeter()
        _ = meter.sample(id: "a", timestampUs: 1_000_000, width: 640, height: 360,
            bytesReceived: 100_000, framesDecoded: 30, fps: nil)
        let result = try XCTUnwrap(meter.sample(id: "a", timestampUs: 3_000_000,
            width: 640, height: 360, bytesReceived: 300_000, framesDecoded: 78, fps: nil))
        XCTAssertEqual(try XCTUnwrap(result.bitrateKbps), 800, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(result.framesPerSecond), 24, accuracy: 0.01)
        XCTAssertEqual(result.height, 360)
    }
    func testFullHDFramesRemainVisibleAtActualResolution() throws {
        var meter = VisionLinkVideoQualityMeter()
        _ = meter.sample(id: "full-hd", timestampUs: 1_000_000, width: 1920,
            height: 1080, bytesReceived: 100_000, framesDecoded: 30, fps: 30)
        let result = try XCTUnwrap(meter.sample(id: "full-hd", timestampUs: 3_000_000,
            width: 1920, height: 1080, bytesReceived: 1_350_000, framesDecoded: 90, fps: 30))
        XCTAssertEqual(result.width, 1920)
        XCTAssertEqual(result.height, 1080)
        XCTAssertEqual(try XCTUnwrap(result.bitrateKbps), 5000, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(result.framesPerSecond), 30, accuracy: 0.01)
    }

    func testFrozenVideoReportsStalledRatherThanMeasuring() throws {
        var meter = VisionLinkVideoQualityMeter()
        _ = meter.sample(id: "a", timestampUs: 1_000_000, width: 1280, height: 720,
            bytesReceived: 100_000, framesDecoded: 30, fps: 30)
        let result = try XCTUnwrap(meter.sample(id: "a", timestampUs: 3_000_000, width: 1280,
            height: 720, bytesReceived: 100_000, framesDecoded: 30, fps: 30))
        XCTAssertTrue(result.isStalled)
        XCTAssertEqual(result.framesPerSecond, 0)
    }
    func testNewStreamDoesNotReusePreviousCounters() throws {
        var meter = VisionLinkVideoQualityMeter()
        _ = meter.sample(id: "a", timestampUs: 1_000_000, width: 1280, height: 720,
            bytesReceived: 900_000, framesDecoded: 300, fps: 30)
        XCTAssertNil(meter.sample(id: "b", timestampUs: 3_000_000,
            width: 640, height: 360, bytesReceived: 100, framesDecoded: 1, fps: nil))
    }

    private func quality(_ edge: Int = 720, _ fps: Double = 24) -> VisionLinkVideoQuality {
        VisionLinkVideoQuality(width: edge, height: edge * 16 / 9, framesPerSecond: fps, bitrateKbps: 100)
    }
    func testDisplayGateBlocksSustainedLowResolutionAtEightSeconds() {
        var gate = VisionLinkVideoDisplayGate()
        for second in stride(from: 0.0, through: 6, by: 2) {
            XCTAssertFalse(gate.observe(quality(540, 30), at: second))
        }
        XCTAssertTrue(gate.observe(quality(540, 30), at: 8))
    }
    func testDisplayGateAcceptsPortrait720AndExactly24FpsAtLowBitrate() {
        var gate = VisionLinkVideoDisplayGate()
        for second in stride(from: 0.0, through: 20, by: 2) {
            XCTAssertFalse(gate.observe(quality(), at: second))
        }
    }
    func testDisplayGateBlocksLowFpsEvenAt1080() {
        var gate = VisionLinkVideoDisplayGate()
        for second in stride(from: 0.0, through: 8, by: 2) {
            _ = gate.observe(quality(1080, 23.9), at: second)
        }
        XCTAssertTrue(gate.isBlocked)
        XCTAssertTrue(gate.observe(quality(1080, 30), at: 10))
        XCTAssertTrue(gate.observe(quality(1080, 30), at: 12))
        XCTAssertFalse(gate.observe(quality(1080, 30), at: 14))
    }
    func testDisplayGateTransientDipAndInterruptedRecovery() {
        var gate = VisionLinkVideoDisplayGate()
        for second in stride(from: 0.0, through: 6, by: 2) { _ = gate.observe(quality(360), at: second) }
        XCTAssertFalse(gate.observe(quality(), at: 8))
        for second in stride(from: 10.0, through: 18, by: 2) { _ = gate.observe(quality(360), at: second) }
        XCTAssertTrue(gate.observe(quality(), at: 20))
        XCTAssertTrue(gate.observe(quality(360), at: 22))
        XCTAssertTrue(gate.observe(quality(), at: 24))
        XCTAssertTrue(gate.observe(quality(), at: 26))
        XCTAssertFalse(gate.observe(quality(), at: 28))
    }
    func testDisplayGateUnknownOutputAndMissingSamplesCannotRestore() {
        var gate = VisionLinkVideoDisplayGate()
        for second in stride(from: 0.0, through: 8, by: 2) { _ = gate.observe(nil, at: second) }
        XCTAssertTrue(gate.isBlocked)
        XCTAssertTrue(gate.observe(quality(), at: 10))
        XCTAssertTrue(gate.observe(quality(), at: 30))
        XCTAssertTrue(gate.observe(quality(), at: 32))
        XCTAssertFalse(gate.observe(quality(), at: 34))
        gate.reset()
        XCTAssertFalse(gate.isBlocked)
        XCTAssertFalse(gate.observe(quality(360), at: 36))
    }
}
