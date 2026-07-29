import XCTest

@testable import shortcuts_example

final class MagnifierZoomPolicyTests: XCTestCase {
    func testZoomIsClampedToDeviceRange() {
        XCTAssertEqual(
            MagnifierZoomPolicy.clamped(
                0.5,
                deviceMinimum: 1,
                deviceMaximum: 8
            ),
            1
        )
        XCTAssertEqual(
            MagnifierZoomPolicy.clamped(
                4,
                deviceMinimum: 1,
                deviceMaximum: 8
            ),
            4
        )
        XCTAssertEqual(
            MagnifierZoomPolicy.clamped(
                12,
                deviceMinimum: 1,
                deviceMaximum: 8
            ),
            8
        )
    }

    func testProductLimitCapsLargeDeviceZoom() {
        XCTAssertEqual(
            MagnifierZoomPolicy.clamped(
                15,
                deviceMinimum: 1,
                deviceMaximum: 30
            ),
            MagnifierZoomPolicy.productMaximum
        )
    }
}
