import CoreMotion
import Foundation

/// Core Motion equivalent of Android's TYPE_LINEAR_ACCELERATION gate.
/// `CMDeviceMotion.userAcceleration` is reported in g, so samples are converted
/// to m/s² before applying Android's sum-of-axis variance threshold.
nonisolated final class ScannerMotionMonitor: @unchecked Sendable {
    private struct Sample {
        let x: Double
        let y: Double
        let z: Double
    }

    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "net.rivo.scanner.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()
    private let lock = NSLock()
    private let capacity: Int
    private let updateInterval: TimeInterval
    private let sampleStartupTimeout: TimeInterval
    private let varianceThreshold: Double
    private var samples: [Sample] = []
    private var sensorAvailable = false
    private var startedAt: TimeInterval?
    private var sessionGeneration: UInt64 = 0

    init(
        sampleWindowSeconds: Double = 0.32,
        updatesPerSecond: Double = 50,
        varianceThreshold: Double = 0.5,
        sampleStartupTimeout: TimeInterval? = nil
    ) {
        capacity = max(
            Int((sampleWindowSeconds * updatesPerSecond).rounded()),
            1
        )
        updateInterval = 1 / max(updatesPerSecond, 1)
        self.sampleStartupTimeout = max(
            sampleStartupTimeout ?? max(sampleWindowSeconds * 3, 1),
            0
        )
        self.varianceThreshold = varianceThreshold
    }

    @MainActor
    func start() {
        manager.stopDeviceMotionUpdates()
        lock.lock()
        sessionGeneration &+= 1
        let generation = sessionGeneration
        samples.removeAll(keepingCapacity: true)
        sensorAvailable = manager.isDeviceMotionAvailable
        startedAt = ProcessInfo.processInfo.systemUptime
        let available = sensorAvailable
        lock.unlock()
        guard available else {
            return
        }

        manager.deviceMotionUpdateInterval = updateInterval
        manager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: queue
        ) { [weak self] motion, error in
            guard let self else {
                return
            }
            if error != nil {
                self.markSensorUnavailable(generation: generation)
                return
            }
            guard let acceleration = motion?.userAcceleration else {
                return
            }
            let metersPerSecondSquared = 9.80665
            self.append(
                Sample(
                    x: acceleration.x * metersPerSecondSquared,
                    y: acceleration.y * metersPerSecondSquared,
                    z: acceleration.z * metersPerSecondSquared
                ),
                generation: generation
            )
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        lock.lock()
        sessionGeneration &+= 1
        samples.removeAll(keepingCapacity: true)
        sensorAvailable = false
        startedAt = nil
        lock.unlock()
    }

    @MainActor
    func isStill() -> Bool {
        lock.lock()
        guard sensorAvailable else {
            lock.unlock()
            return true
        }
        guard samples.count >= capacity else {
            let elapsed = startedAt.map {
                ProcessInfo.processInfo.systemUptime - $0
            } ?? sampleStartupTimeout
            if Self.shouldFallOpen(
                sampleCount: samples.count,
                requiredSampleCount: capacity,
                elapsed: elapsed,
                timeout: sampleStartupTimeout
            ) {
                sensorAvailable = false
                lock.unlock()
                manager.stopDeviceMotionUpdates()
                return true
            }
            lock.unlock()
            return false
        }
        let still = axisVariance(\.x)
            + axisVariance(\.y)
            + axisVariance(\.z) < varianceThreshold
        lock.unlock()
        return still
    }

    @MainActor
    func variance() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard sensorAvailable, samples.count >= capacity else {
            return nil
        }
        return axisVariance(\.x)
            + axisVariance(\.y)
            + axisVariance(\.z)
    }

    private func append(_ sample: Sample, generation: UInt64) {
        lock.lock()
        guard generation == sessionGeneration, sensorAvailable else {
            lock.unlock()
            return
        }
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
        lock.unlock()
    }

    private func markSensorUnavailable(generation: UInt64) {
        lock.lock()
        guard generation == sessionGeneration else {
            lock.unlock()
            return
        }
        sensorAvailable = false
        lock.unlock()
        Task { @MainActor [weak self] in
            self?.stopUpdatesIfInactive(generation: generation)
        }
    }

    @MainActor
    private func stopUpdatesIfInactive(generation: UInt64) {
        lock.lock()
        let shouldStop =
            generation == sessionGeneration && !sensorAvailable
        lock.unlock()
        if shouldStop {
            manager.stopDeviceMotionUpdates()
        }
    }

    static func shouldFallOpen(
        sampleCount: Int,
        requiredSampleCount: Int,
        elapsed: TimeInterval,
        timeout: TimeInterval
    ) -> Bool {
        sampleCount < requiredSampleCount && elapsed >= timeout
    }

    private func axisVariance(
        _ keyPath: KeyPath<Sample, Double>
    ) -> Double {
        guard !samples.isEmpty else {
            return 0
        }
        let mean = samples.reduce(0) {
            $0 + $1[keyPath: keyPath]
        } / Double(samples.count)
        return samples.reduce(0) {
            let delta = $1[keyPath: keyPath] - mean
            return $0 + delta * delta
        } / Double(samples.count)
    }
}
