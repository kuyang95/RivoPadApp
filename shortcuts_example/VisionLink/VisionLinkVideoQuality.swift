import Foundation

nonisolated struct VisionLinkVideoQuality: Equatable, Sendable {
    let width: Int
    let height: Int
    let framesPerSecond: Double?
    let bitrateKbps: Double?
    var isStalled: Bool { framesPerSecond == 0 || bitrateKbps == 0 }
}

/// RTP counters are cumulative and timestamps are microseconds.
nonisolated struct VisionLinkVideoQualityMeter {
    private var streamID: String?
    private var timestamp: Double?
    private var bytes: Double?
    private var frames: Double?

    mutating func sample(
        id: String, timestampUs: Double, width: Int, height: Int,
        bytesReceived: Double?, framesDecoded: Double?, fps: Double?
    ) -> VisionLinkVideoQuality? {
        let sameStream = streamID == id
        let elapsed = sameStream ? timestamp.map { (timestampUs - $0) / 1_000_000 } : nil
        var bitrate: Double?
        var measuredFPS: Double?
        if let elapsed, elapsed > 0 {
            if let bytesReceived, let bytes, bytesReceived >= bytes {
                bitrate = (bytesReceived - bytes) * 8 / elapsed / 1000
            }
            if let framesDecoded, let frames, framesDecoded >= frames {
                measuredFPS = (framesDecoded - frames) / elapsed
            }
        }
        streamID = id
        timestamp = timestampUs
        bytes = bytesReceived
        frames = framesDecoded
        guard width > 0, height > 0, let bitrate, bitrate >= 0 else { return nil }
        let frameRate = measuredFPS ?? fps
        return VisionLinkVideoQuality(
            width: width, height: height,
            framesPerSecond: frameRate.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil },
            bitrateKbps: bitrate
        )
    }
}

/// Cover the picture only; decoding and recovery must continue behind the cover.
nonisolated struct VisionLinkVideoDisplayGate {
    private(set) var isBlocked = false
    private var candidateSince: Double?
    private var previousTime: Double?

    mutating func observe(_ quality: VisionLinkVideoQuality?, at time: Double) -> Bool {
        // A background interval or missing samples cannot count as stable recovery.
        if let previousTime, time < previousTime || time - previousTime > 5 {
            candidateSince = nil
        }
        previousTime = time
        let sufficient = quality.map {
            min($0.width, $0.height) >= 720 && ($0.framesPerSecond ?? 0) >= 24 && !$0.isStalled
        } ?? false
        let needsChange = isBlocked ? sufficient : !sufficient
        guard needsChange else { candidateSince = nil; return isBlocked }
        if candidateSince == nil { candidateSince = time }
        if time - (candidateSince ?? time) >= (isBlocked ? 4 : 8) {
            isBlocked.toggle()
            candidateSince = nil
        }
        return isBlocked
    }

    mutating func reset() { self = Self() }
}
