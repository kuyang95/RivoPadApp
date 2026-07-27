import CoreGraphics
import Darwin
import Foundation
import os

/// Numeric-only diagnostics for physical-device scanner validation.
///
/// Enable with `-ScannerDiagnostics 1` or `SCANNER_DIAGNOSTICS=1`.
/// No image data, recognized text, document points, or device identifiers are
/// persisted or emitted.
nonisolated final class ScannerDiagnostics: @unchecked Sendable {
    private struct InferenceBenchmarkResult: Sendable {
        let requestedBackend: ScannerInferenceBackend
        let activeBackend: ScannerInferenceBackend
        let loadMilliseconds: Double
        let samples: [Double]
        let output: [Float]
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier
            ?? "com.rivo.shortcuts-example",
        category: "scanner.performance"
    )
    private let lock = NSLock()
    private var liveInferenceMilliseconds: [Double] = []
    private var livePreprocessingMilliseconds: [Double] = []
    private var liveDetectionCount = 0

    let isEnabled: Bool

    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] =
            ProcessInfo.processInfo.environment
    ) {
        isEnabled = Self.isRequested(
            arguments: arguments,
            environment: environment
        )
    }

    func logEnvironment() {
        guard isEnabled else {
            return
        }
        let processInfo = ProcessInfo.processInfo
        let snapshot = Self.resourceSnapshot()
        emit(
            "environment os=\(processInfo.operatingSystemVersionString) "
                + "physicalMB=\(Self.megabytes(processInfo.physicalMemory)) "
                + Self.resourceDescription(snapshot)
        )
    }

    func logCamera(
        formatWidth: Int32,
        formatHeight: Int32,
        fieldOfView: Float,
        zoomFactor: CGFloat
    ) {
        guard isEnabled else {
            return
        }
        emit(
            "camera format=\(formatWidth)x\(formatHeight) "
                + "fov=\(Self.decimal(Double(fieldOfView), digits: 2)) "
                + "zoom=\(Self.decimal(Double(zoomFactor), digits: 2))"
        )
    }

    func logDuration(
        _ stage: String,
        milliseconds: Double,
        ticket: UUID? = nil,
        details: String = ""
    ) {
        guard isEnabled else {
            return
        }
        let ticketText = ticket.map {
            " ticket=\($0.uuidString.prefix(8))"
        } ?? ""
        let detailsText = details.isEmpty ? "" : " \(details)"
        emit(
            "duration stage=\(stage)"
                + ticketText
                + " ms=\(Self.decimal(milliseconds, digits: 2))"
                + detailsText
        )
    }

    func recordLiveInference(
        milliseconds: Double,
        preprocessingMilliseconds: Double,
        preprocessingBackend: UVDocWarpBackend,
        inferenceBackend: ScannerInferenceBackend,
        detected: Bool
    ) {
        guard isEnabled else {
            return
        }
        lock.lock()
        liveInferenceMilliseconds.append(milliseconds)
        livePreprocessingMilliseconds.append(preprocessingMilliseconds)
        if detected {
            liveDetectionCount += 1
        }
        let shouldReport = liveInferenceMilliseconds.count >= 30
        let samples = shouldReport ? liveInferenceMilliseconds : []
        let preprocessingSamples = shouldReport
            ? livePreprocessingMilliseconds
            : []
        let detectionCount = shouldReport ? liveDetectionCount : 0
        if shouldReport {
            liveInferenceMilliseconds.removeAll(keepingCapacity: true)
            livePreprocessingMilliseconds.removeAll(keepingCapacity: true)
            liveDetectionCount = 0
        }
        lock.unlock()

        guard shouldReport else {
            return
        }
        let sorted = samples.sorted()
        let sortedPreprocessing = preprocessingSamples.sorted()
        let sortedTotals = zip(samples, preprocessingSamples)
            .map { $0.0 + $0.1 }
            .sorted()
        let p50 = Self.percentile(0.50, in: sorted)
        let p95 = Self.percentile(0.95, in: sorted)
        let preprocessingP50 = Self.percentile(
            0.50,
            in: sortedPreprocessing
        )
        let preprocessingP95 = Self.percentile(
            0.95,
            in: sortedPreprocessing
        )
        let totalP50 = Self.percentile(0.50, in: sortedTotals)
        let totalP95 = Self.percentile(0.95, in: sortedTotals)
        let detectionRate = Double(detectionCount)
            / Double(max(samples.count, 1)) * 100
        emit(
            "liveLCNet samples=\(samples.count) "
                + "preprocessBackend=\(preprocessingBackend.rawValue) "
                + "inferenceBackend=\(inferenceBackend.rawValue) "
                + "p50ms=\(Self.decimal(p50, digits: 2)) "
                + "p95ms=\(Self.decimal(p95, digits: 2)) "
                + "preprocessP50ms="
                + Self.decimal(preprocessingP50, digits: 2)
                + " preprocessP95ms="
                + Self.decimal(preprocessingP95, digits: 2)
                + " totalP50ms="
                + Self.decimal(totalP50, digits: 2)
                + " totalP95ms="
                + Self.decimal(totalP95, digits: 2)
                + " detectionRatePct="
                + Self.decimal(detectionRate, digits: 1)
        )
    }

    func runUVDocBackendBenchmark() async {
        guard isEnabled,
              Self.isUVDocBenchmarkRequested() else {
            return
        }

        emit("uvdocBenchmark started warmups=2 samples=8")
        var cpuReference: [Float]?
        for requestedBackend in [
            ScannerInferenceBackend.cpuParity,
            .coreML
        ] {
            do {
                let result = try await Self.benchmarkUVDoc(
                    requestedBackend: requestedBackend,
                    warmupCount: 2,
                    sampleCount: 8
                )
                let sorted = result.samples.sorted()
                let maximumReferenceDifference: Float
                if let cpuReference {
                    maximumReferenceDifference = zip(
                        cpuReference,
                        result.output
                    ).reduce(Float.zero) { difference, pair in
                        max(difference, abs(pair.0 - pair.1))
                    }
                } else {
                    cpuReference = result.output
                    maximumReferenceDifference = 0
                }
                emit(
                    "uvdocBenchmark requested="
                        + "\(result.requestedBackend.rawValue) "
                        + "active=\(result.activeBackend.rawValue) "
                        + "loadMs="
                        + Self.decimal(
                            result.loadMilliseconds,
                            digits: 2
                        )
                        + " p50ms="
                        + Self.decimal(
                            Self.percentile(0.50, in: sorted),
                            digits: 2
                        )
                        + " p95ms="
                        + Self.decimal(
                            Self.percentile(0.95, in: sorted),
                            digits: 2
                        )
                        + " maxCPUReferenceDifference="
                        + Self.decimal(
                            Double(maximumReferenceDifference),
                            digits: 6
                        )
                )
            } catch {
                emit(
                    "uvdocBenchmark requested="
                        + "\(requestedBackend.rawValue) failed=true "
                        + "error=\(error.localizedDescription)"
                )
            }
        }
        emit("uvdocBenchmark finished")
    }

    func logResource(_ stage: String, ticket: UUID? = nil) {
        guard isEnabled else {
            return
        }
        let ticketText = ticket.map {
            " ticket=\($0.uuidString.prefix(8))"
        } ?? ""
        emit(
            "resource stage=\(stage)"
                + ticketText
                + " "
                + Self.resourceDescription(Self.resourceSnapshot())
        )
    }

    func beginProcessing(ticket: UUID) -> ScannerResourceSampler? {
        guard isEnabled else {
            return nil
        }
        return ScannerResourceSampler(
            diagnostics: self,
            ticket: ticket
        )
    }

    func trace(ticket: UUID) -> ScannerProcessingTrace? {
        guard isEnabled else {
            return nil
        }
        return ScannerProcessingTrace(
            diagnostics: self,
            ticket: ticket
        )
    }

    func logFOV(
        _ comparison: ScannerFOVComparison,
        liveTransform: ScannerViewportTransform,
        stillTransform: ScannerViewportTransform,
        ticket: UUID
    ) {
        guard isEnabled else {
            return
        }
        let liveCrop = Self.rectDescription(liveTransform.rawCropRect)
        let stillCrop = Self.rectDescription(stillTransform.rawCropRect)
        emit(
            "fov ticket=\(ticket.uuidString.prefix(8)) "
                + "liveRaw=\(liveTransform.rawWidth)x"
                + "\(liveTransform.rawHeight) "
                + "liveCrop=\(liveCrop) "
                + "stillRaw=\(stillTransform.rawWidth)x"
                + "\(stillTransform.rawHeight) "
                + "stillCrop=\(stillCrop) "
                + "meanCornerPct="
                + Self.decimal(
                    comparison.meanCornerErrorPercentOfPreviewDiagonal,
                    digits: 3
                )
                + " maxCornerPct="
                + Self.decimal(
                    comparison.maximumCornerErrorPercentOfPreviewDiagonal,
                    digits: 3
                )
                + " centroidPct="
                + Self.decimal(
                    comparison.centroidDriftPercentOfPreviewDiagonal,
                    digits: 3
                )
                + " scaleX="
                + Self.decimal(comparison.boundingBoxScaleX, digits: 4)
                + " scaleY="
                + Self.decimal(comparison.boundingBoxScaleY, digits: 4)
        )
    }

    func logEvent(_ event: String, details: String = "") {
        guard isEnabled else {
            return
        }
        emit(event + (details.isEmpty ? "" : " \(details)"))
    }

    fileprivate func logProcessingSummary(
        ticket: UUID,
        outcome: String,
        elapsedMilliseconds: Double,
        baseline: ScannerResourceSnapshot,
        peakFootprintBytes: UInt64,
        minimumAvailableBytes: UInt64,
        maximumThermalRank: Int
    ) {
        let footprintDelta = peakFootprintBytes > baseline.footprintBytes
            ? peakFootprintBytes - baseline.footprintBytes
            : 0
        emit(
            "processingSummary ticket=\(ticket.uuidString.prefix(8)) "
                + "outcome=\(outcome) "
                + "elapsedMs="
                + Self.decimal(elapsedMilliseconds, digits: 2)
                + " baselineMB=\(Self.megabytes(baseline.footprintBytes)) "
                + "peakMB=\(Self.megabytes(peakFootprintBytes)) "
                + "deltaMB=\(Self.megabytes(footprintDelta)) "
                + "minDirtyLimitRemainingMB="
                + "\(Self.megabytes(minimumAvailableBytes)) "
                + "maxThermal=\(Self.thermalName(maximumThermalRank))"
        )
    }

    fileprivate func logStageSummary(
        stage: String,
        ticket: UUID,
        outcome: String,
        elapsedMilliseconds: Double,
        baseline: ScannerResourceSnapshot,
        final: ScannerResourceSnapshot,
        details: String
    ) {
        let detailsText = details.isEmpty ? "" : " \(details)"
        let deltaMegabytes = Self.signedMegabytesDelta(
            from: baseline.footprintBytes,
            to: final.footprintBytes
        )
        emit(
            "stageSummary stage=\(stage) "
                + "ticket=\(ticket.uuidString.prefix(8)) "
                + "outcome=\(outcome) "
                + "elapsedMs="
                + Self.decimal(elapsedMilliseconds, digits: 2)
                + " startMB=\(Self.megabytes(baseline.footprintBytes)) "
                + "endMB=\(Self.megabytes(final.footprintBytes)) "
                + "deltaMB=\(deltaMegabytes) "
                + "dirtyLimitRemainingMB="
                + "\(Self.megabytes(final.availableBytes)) "
                + "thermal=\(Self.thermalName(final.thermalRank)) "
                + "lowPower=\(final.lowPowerModeEnabled)"
                + detailsText
        )
    }

    static func milliseconds(since start: TimeInterval) -> Double {
        (ProcessInfo.processInfo.systemUptime - start) * 1_000
    }

    static func resourceSnapshot() -> ScannerResourceSnapshot {
        let processInfo = ProcessInfo.processInfo
        return ScannerResourceSnapshot(
            footprintBytes: physicalFootprintBytes(),
            availableBytes: UInt64(os_proc_available_memory()),
            thermalRank: thermalRank(processInfo.thermalState),
            lowPowerModeEnabled: processInfo.isLowPowerModeEnabled
        )
    }

    private func emit(_ message: String) {
        logger.notice("[ScannerDiagnostics] \(message, privacy: .public)")
        print("[ScannerDiagnostics] \(message)")
    }

    static func isRequested(
        arguments: [String],
        environment: [String: String]
    ) -> Bool {
        if environment["SCANNER_DIAGNOSTICS"] == "1" {
            return true
        }
        if arguments.contains("--scanner-diagnostics") {
            return true
        }
        guard let index = arguments.firstIndex(of: "-ScannerDiagnostics"),
              arguments.indices.contains(index + 1) else {
            return false
        }
        return arguments[index + 1] != "0"
    }

    static func isUVDocBenchmarkRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] =
            ProcessInfo.processInfo.environment
    ) -> Bool {
        if environment["SCANNER_BENCHMARK_UVDOC"] == "1" {
            return true
        }
        if arguments.contains("--scanner-benchmark-uvdoc") {
            return true
        }
        guard let index = arguments.firstIndex(
            of: "-ScannerBenchmarkUVDoc"
        ),
        arguments.indices.contains(index + 1) else {
            return false
        }
        return arguments[index + 1] != "0"
    }

    private static func benchmarkUVDoc(
        requestedBackend: ScannerInferenceBackend,
        warmupCount: Int,
        sampleCount: Int
    ) async throws -> InferenceBenchmarkResult {
        let loadStartedAt = ProcessInfo.processInfo.systemUptime
        let session = try ScannerONNXSession(
            descriptor: .curvedPageDewarper,
            backend: requestedBackend
        )
        let loadMilliseconds = milliseconds(since: loadStartedAt)
        let descriptor = ScannerModelDescriptor.curvedPageDewarper
        let input = ScannerFloatTensor(
            values: [Float](
                repeating: 0,
                count: descriptor.inputShape.reduce(1, *)
            ),
            shape: descriptor.inputShape
        )

        for _ in 0 ..< warmupCount {
            _ = try await session.run(input)
        }

        var samples: [Double] = []
        samples.reserveCapacity(sampleCount)
        var output: [Float] = []
        for _ in 0 ..< sampleCount {
            let startedAt = ProcessInfo.processInfo.systemUptime
            let result = try await session.run(input)
            samples.append(milliseconds(since: startedAt))
            output = result.values
        }
        return InferenceBenchmarkResult(
            requestedBackend: requestedBackend,
            activeBackend: session.activeBackend,
            loadMilliseconds: loadMilliseconds,
            samples: samples,
            output: output
        )
    }

    private static func physicalFootprintBytes() -> UInt64 {
        var information = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size
                / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }
        return result == KERN_SUCCESS
            ? UInt64(information.phys_footprint)
            : 0
    }

    private static func percentile(
        _ percentile: Double,
        in sortedValues: [Double]
    ) -> Double {
        guard !sortedValues.isEmpty else {
            return 0
        }
        let index = Int(
            (Double(sortedValues.count - 1) * percentile).rounded()
        )
        return sortedValues[min(max(index, 0), sortedValues.count - 1)]
    }

    private static func thermalRank(
        _ state: ProcessInfo.ThermalState
    ) -> Int {
        switch state {
        case .nominal:
            return 0
        case .fair:
            return 1
        case .serious:
            return 2
        case .critical:
            return 3
        @unknown default:
            return 4
        }
    }

    fileprivate static func thermalName(_ rank: Int) -> String {
        switch rank {
        case 0:
            return "nominal"
        case 1:
            return "fair"
        case 2:
            return "serious"
        case 3:
            return "critical"
        default:
            return "unknown"
        }
    }

    private static func resourceDescription(
        _ snapshot: ScannerResourceSnapshot
    ) -> String {
        "footprintMB=\(megabytes(snapshot.footprintBytes)) "
            + "dirtyLimitRemainingMB="
            + "\(megabytes(snapshot.availableBytes)) "
            + "thermal=\(thermalName(snapshot.thermalRank)) "
            + "lowPower=\(snapshot.lowPowerModeEnabled)"
    }

    private static func rectDescription(
        _ rect: ScannerPixelRect
    ) -> String {
        "(\(rect.x),\(rect.y),\(rect.width),\(rect.height))"
    }

    private static func megabytes(_ bytes: UInt64) -> UInt64 {
        bytes / 1_048_576
    }

    private static func signedMegabytesDelta(
        from start: UInt64,
        to end: UInt64
    ) -> Int64 {
        if end >= start {
            return Int64((end - start) / 1_048_576)
        }
        return -Int64((start - end) / 1_048_576)
    }

    private static func decimal(
        _ value: Double,
        digits: Int
    ) -> String {
        String(
            format: "%.\(digits)f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }
}

nonisolated struct ScannerResourceSnapshot: Equatable, Sendable {
    let footprintBytes: UInt64
    let availableBytes: UInt64
    let thermalRank: Int
    let lowPowerModeEnabled: Bool
}

nonisolated struct ScannerProcessingTrace: Sendable {
    private let diagnostics: ScannerDiagnostics
    let ticket: UUID

    fileprivate init(
        diagnostics: ScannerDiagnostics,
        ticket: UUID
    ) {
        self.diagnostics = diagnostics
        self.ticket = ticket
    }

    func beginStage(_ stage: String) -> ScannerStageSampler {
        ScannerStageSampler(
            diagnostics: diagnostics,
            ticket: ticket,
            stage: stage
        )
    }
}

nonisolated final class ScannerStageSampler: @unchecked Sendable {
    private let diagnostics: ScannerDiagnostics
    private let ticket: UUID
    private let stage: String
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private let baseline = ScannerDiagnostics.resourceSnapshot()
    private let lock = NSLock()
    private var finished = false

    fileprivate init(
        diagnostics: ScannerDiagnostics,
        ticket: UUID,
        stage: String
    ) {
        self.diagnostics = diagnostics
        self.ticket = ticket
        self.stage = stage
    }

    func finish(
        outcome: String = "success",
        details: String = ""
    ) {
        let finalSnapshot = ScannerDiagnostics.resourceSnapshot()
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()

        diagnostics.logStageSummary(
            stage: stage,
            ticket: ticket,
            outcome: outcome,
            elapsedMilliseconds:
                ScannerDiagnostics.milliseconds(since: startedAt),
            baseline: baseline,
            final: finalSnapshot,
            details: details
        )
    }
}

nonisolated final class ScannerResourceSampler: @unchecked Sendable {
    private let diagnostics: ScannerDiagnostics
    private let ticket: UUID
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private let baseline: ScannerResourceSnapshot
    private let lock = NSLock()
    private let timer: DispatchSourceTimer
    private var peakFootprintBytes: UInt64
    private var minimumAvailableBytes: UInt64
    private var maximumThermalRank: Int
    private var finished = false

    init(diagnostics: ScannerDiagnostics, ticket: UUID) {
        let initialSnapshot = ScannerDiagnostics.resourceSnapshot()
        self.diagnostics = diagnostics
        self.ticket = ticket
        baseline = initialSnapshot
        peakFootprintBytes = initialSnapshot.footprintBytes
        minimumAvailableBytes = initialSnapshot.availableBytes
        maximumThermalRank = initialSnapshot.thermalRank

        let queue = DispatchQueue(
            label: "net.rivo.scanner.resource-sampler",
            qos: .utility
        )
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now(),
            repeating: .milliseconds(100),
            leeway: .milliseconds(20)
        )
        timer.setEventHandler { [weak self] in
            self?.sample()
        }
        timer.resume()
    }

    func finish(outcome: String) {
        let finalSnapshot = ScannerDiagnostics.resourceSnapshot()
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        peakFootprintBytes = max(
            peakFootprintBytes,
            finalSnapshot.footprintBytes
        )
        minimumAvailableBytes = min(
            minimumAvailableBytes,
            finalSnapshot.availableBytes
        )
        maximumThermalRank = max(
            maximumThermalRank,
            finalSnapshot.thermalRank
        )
        let peak = peakFootprintBytes
        let minimumAvailable = minimumAvailableBytes
        let maximumThermal = maximumThermalRank
        lock.unlock()

        timer.setEventHandler {}
        timer.cancel()
        diagnostics.logProcessingSummary(
            ticket: ticket,
            outcome: outcome,
            elapsedMilliseconds:
                ScannerDiagnostics.milliseconds(since: startedAt),
            baseline: baseline,
            peakFootprintBytes: peak,
            minimumAvailableBytes: minimumAvailable,
            maximumThermalRank: maximumThermal
        )
    }

    private func sample() {
        let snapshot = ScannerDiagnostics.resourceSnapshot()
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        peakFootprintBytes = max(
            peakFootprintBytes,
            snapshot.footprintBytes
        )
        minimumAvailableBytes = min(
            minimumAvailableBytes,
            snapshot.availableBytes
        )
        maximumThermalRank = max(
            maximumThermalRank,
            snapshot.thermalRank
        )
        lock.unlock()
    }
}

nonisolated struct ScannerFOVComparison: Equatable, Sendable {
    let meanCornerErrorPercentOfPreviewDiagonal: Double
    let maximumCornerErrorPercentOfPreviewDiagonal: Double
    let centroidDriftPercentOfPreviewDiagonal: Double
    let boundingBoxScaleX: Double
    let boundingBoxScaleY: Double

    static func compare(
        liveQuad: DocumentQuad,
        liveTransform: ScannerViewportTransform,
        stillQuad: DocumentQuad,
        stillTransform: ScannerViewportTransform
    ) -> Self {
        let livePoints = liveQuad.points.map {
            liveTransform.previewPoint(for: $0)
        }
        let stillPoints = stillQuad.points.map {
            stillTransform.previewPoint(for: $0)
        }
        let errors = zip(livePoints, stillPoints).map {
            hypot(Double($0.x - $1.x), Double($0.y - $1.y))
        }
        let previewDiagonal = max(
            hypot(
                liveTransform.previewWidth,
                liveTransform.previewHeight
            ),
            0.000_001
        )
        let liveCentroid = centroid(of: livePoints)
        let stillCentroid = centroid(of: stillPoints)
        let centroidDistance = hypot(
            Double(liveCentroid.x - stillCentroid.x),
            Double(liveCentroid.y - stillCentroid.y)
        )
        let liveBounds = bounds(of: livePoints)
        let stillBounds = bounds(of: stillPoints)

        return Self(
            meanCornerErrorPercentOfPreviewDiagonal:
                (errors.reduce(0, +) / Double(max(errors.count, 1)))
                / previewDiagonal * 100,
            maximumCornerErrorPercentOfPreviewDiagonal:
                (errors.max() ?? 0) / previewDiagonal * 100,
            centroidDriftPercentOfPreviewDiagonal:
                centroidDistance / previewDiagonal * 100,
            boundingBoxScaleX:
                Double(stillBounds.width)
                / max(Double(liveBounds.width), 0.000_001),
            boundingBoxScaleY:
                Double(stillBounds.height)
                / max(Double(liveBounds.height), 0.000_001)
        )
    }

    private static func centroid(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else {
            return .zero
        }
        let sum = points.reduce(CGPoint.zero) {
            CGPoint(x: $0.x + $1.x, y: $0.y + $1.y)
        }
        return CGPoint(
            x: sum.x / CGFloat(points.count),
            y: sum.y / CGFloat(points.count)
        )
    }

    private static func bounds(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else {
            return .zero
        }
        var minimumX = first.x
        var maximumX = first.x
        var minimumY = first.y
        var maximumY = first.y
        for point in points.dropFirst() {
            minimumX = min(minimumX, point.x)
            maximumX = max(maximumX, point.x)
            minimumY = min(minimumY, point.y)
            maximumY = max(maximumY, point.y)
        }
        return CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
    }
}
