import XCTest
@testable import shortcuts_example

final class LocalModelPolicyTests: XCTestCase {
    func testAdvertisedMemoryAllowsForSystemReservation() {
        XCTAssertEqual(DeviceCapabilityProfiler.memoryTier(physicalMemory: 7_700_000_000), .standard)
        XCTAssertEqual(DeviceCapabilityProfiler.memoryTier(physicalMemory: 11_700_000_000), .balanced)
        XCTAssertEqual(DeviceCapabilityProfiler.memoryTier(physicalMemory: 15_700_000_000), .expanded)
        XCTAssertEqual(LoadedModel.preferredTextModel(for: .standard), .qwen35_4b_4bit)
        XCTAssertEqual(LoadedModel.preferredTextModel(for: .balanced), .qwen35_9b_4bit)
    }

    func testTwelveGBPolicyLeavesRoomForApplication() {
        let policy = LocalInferencePolicy.make(from: snapshot(available: 9 * gibibyte))
        XCTAssertEqual(policy.mlxMemoryLimitBytes, Int(7 * gibibyte))
        XCTAssertEqual(policy.textMaxKVSize, 4_096)
        XCTAssertEqual(policy.kvBits, 4)
    }

    func testPolicyRespectsCurrentProcessBudget() {
        let policy = LocalInferencePolicy.make(from: snapshot(available: 6 * gibibyte))
        XCTAssertEqual(policy.mlxMemoryLimitBytes, Int(6 * gibibyte - 1_610_612_736))
    }

    private let gibibyte: UInt64 = 1_073_741_824

    private func snapshot(available: UInt64) -> DeviceCapabilitySnapshot {
        .init(
            memoryTier: .balanced, physicalMemoryBytes: 12 * gibibyte,
            availableAppMemoryBytes: available,
            metalRecommendedWorkingSetBytes: 8 * gibibyte,
            availableStorageBytes: nil, thermalLevel: .nominal,
            isLowPowerModeEnabled: false
        )
    }
}
