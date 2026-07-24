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
    private let varianceThreshold: Double
    private var samples: [Sample] = []
    private var sensorAvailable = false

    init(
        sampleWindowSeconds: Double = 0.32,
        updatesPerSecond: Double = 50,
        varianceThreshold: Double = 0.5
    ) {
        capacity = max(
            Int((sampleWindowSeconds * updatesPerSecond).rounded()),
            1
        )
        updateInterval = 1 / max(updatesPerSecond, 1)
        self.varianceThreshold = varianceThreshold
    }

    func start() {
        manager.stopDeviceMotionUpdates()
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        sensorAvailable = manager.isDeviceMotionAvailable
        let available = sensorAvailable
        lock.unlock()
        guard available else {
            return
        }

        manager.deviceMotionUpdateInterval = updateInterval
        manager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: queue
        ) { [weak self] motion, _ in
            guard let self, let acceleration = motion?.userAcceleration else {
                return
            }
            let metersPerSecondSquared = 9.80665
            self.append(
                Sample(
                    x: acceleration.x * metersPerSecondSquared,
                    y: acceleration.y * metersPerSecondSquared,
                    z: acceleration.z * metersPerSecondSquared
                )
            )
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func isStill() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard sensorAvailable else {
            return true
        }
        guard samples.count >= capacity else {
            return false
        }
        return axisVariance(\.x)
            + axisVariance(\.y)
            + axisVariance(\.z) < varianceThreshold
    }

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

    private func append(_ sample: Sample) {
        lock.lock()
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
        lock.unlock()
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
