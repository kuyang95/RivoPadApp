import Foundation
import XCTest

@testable import shortcuts_example

final class RivoWidgetStatusStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName =
            "RivoWidgetStatusStoreTests."
            + UUID().uuidString
        defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName)
        )
        defaults.removePersistentDomain(
            forName: suiteName
        )
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(
            forName: suiteName
        )
        defaults = nil
        suiteName = nil
    }

    func testMapsConnectionStatesWithoutClaimingLiveData()
    {
        let date = Date(
            timeIntervalSince1970: 123
        )

        let connected =
            RivoWidgetStatusStore.snapshot(
                for: .ready("Rivo Three"),
                updatedAt: date
            )
        XCTAssertEqual(
            connected.kind,
            .connected
        )
        XCTAssertEqual(
            connected.deviceName,
            "Rivo Three"
        )
        XCTAssertEqual(
            connected.updatedAt,
            date
        )

        XCTAssertEqual(
            RivoWidgetStatusStore.snapshot(
                for: .scanning
            ).kind,
            .connecting
        )
        XCTAssertEqual(
            RivoWidgetStatusStore.snapshot(
                for: .bluetoothOff
            ).kind,
            .unavailable
        )
        XCTAssertEqual(
            RivoWidgetStatusStore.snapshot(
                for: .disconnected
            ).kind,
            .notConnected
        )
        XCTAssertEqual(
            RivoWidgetStatusStore.snapshot(
                for: .failed("실패")
            ).kind,
            .failed
        )
    }

    func testSnapshotRoundTripsThroughSharedDefaults()
    {
        let date = Date(
            timeIntervalSince1970: 456
        )
        RivoWidgetStatusStore.save(
            state: .connecting("Rivo Mini"),
            updatedAt: date,
            defaults: defaults,
            reloadWidget: false
        )

        let restored =
            RivoWidgetStatusStore.load(
                defaults: defaults
            )

        XCTAssertEqual(
            restored?.kind,
            .connecting
        )
        XCTAssertEqual(
            restored?.deviceName,
            "Rivo Mini"
        )
        XCTAssertEqual(
            restored?.updatedAt,
            date
        )
    }
}
