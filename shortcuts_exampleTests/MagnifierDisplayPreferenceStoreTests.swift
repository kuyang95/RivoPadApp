import Foundation
import XCTest

@testable import shortcuts_example

@MainActor
final class MagnifierDisplayPreferenceStoreTests:
    XCTestCase
{
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName =
            "MagnifierDisplayPreferenceStoreTests."
            + UUID().uuidString
        defaults = UserDefaults(
            suiteName: suiteName
        )
    }

    override func tearDown() {
        defaults.removePersistentDomain(
            forName: suiteName
        )
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testNoSavedValuesPreserveCurrentAdjustment() {
        let store =
            MagnifierDisplayPreferenceStore(
                defaults: defaults
            )
        var current =
            MagnifierDisplayAdjustment.defaultValue
        current.brightness = 0.3
        current.threshold = 0.7

        XCTAssertEqual(
            store.load(applyingTo: current),
            current
        )
    }

    func testAndroidCameraValuesRestoreAcrossInstances() {
        let writer =
            MagnifierDisplayPreferenceStore(
                defaults: defaults
            )
        let saved =
            MagnifierDisplayAdjustment(
                colorIndex: 7,
                threshold: 0.63,
                isInverted: true,
                brightness: 0.4
            )
        writer.saveColor(from: saved)
        writer.saveThreshold(from: saved)
        writer.saveInversion(from: saved)

        let reader =
            MagnifierDisplayPreferenceStore(
                defaults: defaults
            )
        let restored = reader.load(
            applyingTo: .defaultValue
        )

        XCTAssertEqual(restored.colorIndex, 7)
        XCTAssertEqual(restored.threshold, 0.63)
        XCTAssertTrue(restored.isInverted)
        XCTAssertEqual(restored.brightness, 0)
    }

    func testOriginalColorDoesNotEraseLastSavedColor() {
        let store =
            MagnifierDisplayPreferenceStore(
                defaults: defaults
            )
        let colored =
            MagnifierDisplayAdjustment(
                colorIndex: 4,
                threshold: 0.5,
                isInverted: false,
                brightness: 0
            )
        store.saveColor(from: colored)
        store.saveColor(
            from: .defaultValue
        )

        XCTAssertEqual(
            store.load(
                applyingTo: .defaultValue
            ).colorIndex,
            4
        )
    }

    func testStoredValuesAreClampedAndResettable() {
        defaults.set(
            999,
            forKey:
                "camera.display.colorIndex.v1"
        )
        defaults.set(
            9.0,
            forKey:
                "camera.display.threshold.v1"
        )
        defaults.set(
            true,
            forKey:
                "camera.display.colorInverted.v1"
        )
        let store =
            MagnifierDisplayPreferenceStore(
                defaults: defaults
            )

        let restored = store.load(
            applyingTo: .defaultValue,
            colorCount: 3
        )
        XCTAssertEqual(restored.colorIndex, 2)
        XCTAssertEqual(restored.threshold, 1.05)
        XCTAssertTrue(restored.isInverted)

        store.reset()
        XCTAssertEqual(
            store.load(
                applyingTo: .defaultValue
            ),
            .defaultValue
        )
    }
}
