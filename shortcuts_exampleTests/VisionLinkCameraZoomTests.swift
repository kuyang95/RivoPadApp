import XCTest
@testable import shortcuts_example

final class VisionLinkCameraZoomTests: XCTestCase {
    private func message(_ overrides: [String: Any] = [:]) -> [String: Any] {
        ["type": "camera-zoom-state", "sessionId": "camera-session", "value": 2.37,
         "min": 1.0, "max": 4.0, "supported": true, "revision": 3, "error": false]
            .merging(overrides) { _, new in new }
    }

    func testConfirmedZoomUsesCameraRange() throws {
        let zoom = try XCTUnwrap(VisionLinkCameraZoom(message: message()))
        XCTAssertEqual(zoom.value, 2.37)
        XCTAssertEqual(zoom.clamped(100), 4)
        XCTAssertEqual(zoom.clamped(-5), 1)
        XCTAssertNil(zoom.clamped(.nan))
    }

    func testInvalidWireValuesAreIgnored() {
        for invalid in [message(["value": Double.nan]), message(["value": true]),
                        message(["value": 5]), message(["min": 0]), message(["max": 0.5]),
                        message(["sessionId": ""]), message(["revision": -1]), message(["revision": 1.5])] {
            XCTAssertNil(VisionLinkCameraZoom(message: invalid))
        }
    }

    func testUnsupportedCameraHasNoZoomAction() throws {
        let zoom = try XCTUnwrap(VisionLinkCameraZoom(message: message([
            "value": 1, "max": 1, "supported": false])))
        XCTAssertFalse(zoom.supported)
        XCTAssertNil(zoom.clamped(2))
    }

    func testDataChannelRoutesConfirmedZoomAndIgnoresMalformedZoom() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let receiver = VisionLinkDataReceiver(destinationDirectory: directory, partialDirectory: directory.appendingPathComponent("partial"))
        let data = try JSONSerialization.data(withJSONObject: message())
        let actions = await receiver.receive(.control(data))
        let zoom = try XCTUnwrap(VisionLinkCameraZoom(message: message()))
        XCTAssertEqual(actions, [.event(.cameraZoomChanged(zoom))])
        let invalid = try JSONSerialization.data(withJSONObject: message(["value": true]))
        let ignored = await receiver.receive(.control(invalid))
        XCTAssertTrue(ignored.isEmpty)
    }
}
