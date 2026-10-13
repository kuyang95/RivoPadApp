import XCTest
@testable import shortcuts_example

final class VisionLinkCompatibilityTests: XCTestCase {
    private func peer(_ changes: [String: Any] = [:]) -> VisionLinkCompatibility? {
        VisionLinkCompatibility(message: ["protocol": 1, "role": "camera",
            "features": Array(VisionLinkCompatibility.features), "video": ["maxHeight": 1080, "maxFps": 30]]
            .merging(changes) { _, new in new })
    }
    func testFirstReleaseSupportsCameraAndZoom() throws {
        let c = try XCTUnwrap(peer())
        XCTAssertTrue(c.cameraAvailable)
        XCTAssertTrue(c.permits("camera-zoom-state"))
        XCTAssertTrue(c.common.contains("camera-orientation.v1"))
        XCTAssertEqual(c.maxHeight, 1080)
        XCTAssertEqual(c.maxFps, 30)
    }
    func testHypothetical4KPeerIsCappedAtLocalFHD() throws {
        let c = try XCTUnwrap(peer(["video": ["maxHeight": 2160, "maxFps": 60]]))
        XCTAssertEqual(c.maxHeight, 1080)
        XCTAssertEqual(c.maxFps, 30)
    }
    func testOptionalZoomAbsenceDoesNotBlock720pCamera() throws {
        let c = try XCTUnwrap(peer(["features": ["core.v1", "camera.v1", "future.v99"],
                                   "video": ["maxHeight": 720, "maxFps": 24]]))
        XCTAssertTrue(c.cameraAvailable)
        XCTAssertEqual(c.maxHeight, 720)
        XCTAssertEqual(c.maxFps, 24)
        XCTAssertFalse(c.permits("camera-zoom-state"))
        XCTAssertFalse(c.common.contains("camera-orientation.v1"))
        XCTAssertFalse(c.permits("future-action"))
        XCTAssertFalse(c.permits("clipboard-text"))
    }
    func testInsufficientVideoPreservesText() throws {
        for video in [["maxHeight": 640, "maxFps": 30], ["maxHeight": 1080, "maxFps": 23]] {
            let c = try XCTUnwrap(peer(["video": video]))
            XCTAssertFalse(c.cameraAvailable)
            XCTAssertFalse(c.permits("camera-share-state"))
            XCTAssertTrue(c.permits("clipboard-text"))
        }
    }
    func testMalformedAndIncompatibleContractsAreRejected() {
        for value: Any in [NSNull(), 2, true, "1", 1.5] { XCTAssertNil(peer(["protocol": value])) }
        XCTAssertNil(peer(["role": "receiver"]))
        XCTAssertNil(peer(["features": ["camera.v1"]]))
        XCTAssertNil(peer(["features": ["core.v1", 1]]))
        for value: Any in [-1, true, 720.5, Double.nan, Double.infinity, 16385, "1080"] {
            XCTAssertNil(peer(["video": ["maxHeight": value, "maxFps": 30]]))
        }
    }
    func testIntegralJSONNumbersAreAccepted() { XCTAssertNotNil(peer(["protocol": 1.0, "video": ["maxHeight": 1080.0, "maxFps": 30.0]])) }
}
