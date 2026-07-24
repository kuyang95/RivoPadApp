import Foundation
import Metal
import os

enum DeviceMemoryTier: String, Sendable {
    case standard
    case expanded
}

enum DeviceThermalLevel: String, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unknown
}

struct DeviceCapabilitySnapshot: Sendable {
    let memoryTier: DeviceMemoryTier
    let physicalMemoryBytes: UInt64
    let availableAppMemoryBytes: UInt64
    let metalRecommendedWorkingSetBytes: UInt64?
    let availableStorageBytes: UInt64?
    let thermalLevel: DeviceThermalLevel
    let isLowPowerModeEnabled: Bool
}

struct LocalInferencePolicy: Sendable {
    let memoryTier: DeviceMemoryTier
    let mlxMemoryLimitBytes: Int
    let mlxCacheLimitBytes: Int
    let textMaxTokens: Int
    let visionMaxTokens: Int
    let textMaxKVSize: Int
    let visionMaxKVSize: Int
    let kvBits: Int
    let kvGroupSize: Int
    let quantizedKVStart: Int

    static func make(from capabilities: DeviceCapabilitySnapshot) -> Self {
        let gibibyte = UInt64(1_073_741_824)

        let tierLimit: UInt64
        let reserve: UInt64
        let textMaxTokens: Int
        let textMaxKVSize: Int

        switch capabilities.memoryTier {
        case .standard:
            tierLimit = 5 * gibibyte
            reserve = 1 * gibibyte
            textMaxTokens = 768
            textMaxKVSize = 4_096

        case .expanded:
            tierLimit = 8 * gibibyte
            reserve = 1_610_612_736 // 1.5 GiB
            textMaxTokens = 1_024
            textMaxKVSize = 8_192
        }

        let appBudget: UInt64
        if capabilities.availableAppMemoryBytes == 0 {
            appBudget = tierLimit
        } else if capabilities.availableAppMemoryBytes > reserve {
            appBudget = capabilities.availableAppMemoryBytes - reserve
        } else {
            appBudget = max(capabilities.availableAppMemoryBytes / 2, gibibyte)
        }

        // MLX defaults to 1.5× Metal's recommendation. Keep that upper bound,
        // while also respecting the process's current advisory memory budget.
        let metalBudget = capabilities.metalRecommendedWorkingSetBytes
            .map { $0 + ($0 / 2) }
            ?? tierLimit

        let memoryLimit = min(tierLimit, min(appBudget, metalBudget))

        return .init(
            memoryTier: capabilities.memoryTier,
            mlxMemoryLimitBytes: Int(max(memoryLimit, gibibyte)),
            mlxCacheLimitBytes: 20 * 1_024 * 1_024,
            textMaxTokens: textMaxTokens,
            visionMaxTokens: 512,
            textMaxKVSize: textMaxKVSize,
            visionMaxKVSize: 4_096,
            kvBits: 4,
            kvGroupSize: 64,
            quantizedKVStart: 512
        )
    }
}

enum DeviceCapabilityProfiler {
    static func snapshot() -> DeviceCapabilitySnapshot {
        let processInfo = ProcessInfo.processInfo
        let physicalMemory = processInfo.physicalMemory

        // iPad Pro M4 has 8 GB and 16 GB variants. Using a threshold instead
        // of a model-name table also handles future devices conservatively.
        let expandedThreshold = UInt64(12) * 1_073_741_824
        let memoryTier: DeviceMemoryTier =
            physicalMemory >= expandedThreshold ? .expanded : .standard

        let availableMemory = UInt64(os_proc_available_memory())
        let metalWorkingSet = MTLCreateSystemDefaultDevice()?
            .recommendedMaxWorkingSetSize

        let storageURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let storageValues = try? storageURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        let availableStorage = storageValues?
            .volumeAvailableCapacityForImportantUsage
            .flatMap { $0 > 0 ? UInt64($0) : nil }

        return .init(
            memoryTier: memoryTier,
            physicalMemoryBytes: physicalMemory,
            availableAppMemoryBytes: availableMemory,
            metalRecommendedWorkingSetBytes: metalWorkingSet,
            availableStorageBytes: availableStorage,
            thermalLevel: thermalLevel(from: processInfo.thermalState),
            isLowPowerModeEnabled: processInfo.isLowPowerModeEnabled
        )
    }

    private static func thermalLevel(
        from state: ProcessInfo.ThermalState
    ) -> DeviceThermalLevel {
        switch state {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .unknown
        }
    }
}
