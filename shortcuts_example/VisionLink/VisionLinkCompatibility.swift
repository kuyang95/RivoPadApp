import Foundation
import CoreFoundation

/// Contract 1. App version strings are diagnostic, never used as capability checks.
nonisolated struct VisionLinkCompatibility: Equatable, Sendable {
    static let updateMessage = "VisionLink 호환 규격을 확인할 수 없습니다. 송신앱과 수신앱을 모두 업데이트한 뒤 다시 연결해주세요."
    static let features: Set<String> = ["core.v1", "camera.v1", "camera-orientation.v1", "camera-zoom.v1", "file.v1", "text.v1", "remote-actions.v1", "media-recovery.v1"]
    let common: Set<String>
    let maxHeight: Int
    let maxFps: Int
    var cameraAvailable: Bool { common.contains("camera.v1") && maxHeight >= 720 && maxFps >= 24 }
    init?(message: [String: Any]) {
        func integer(_ raw: Any?, maximum: Int) -> Int? {
            guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
            let d = n.doubleValue
            guard d.isFinite, d >= 0, d <= Double(maximum), d.rounded(.down) == d else { return nil }
            return Int(d)
        }
        guard integer(message["protocol"], maximum: 1000) == 1, message["role"] as? String == "camera",
              let values = message["features"] as? [String], values.count <= 64,
              values.allSatisfy({ $0.count <= 80 }), values.contains("core.v1"),
              let video = message["video"] as? [String: Any],
              let height = integer(video["maxHeight"], maximum: 16384),
              let fps = integer(video["maxFps"], maximum: 240) else { return nil }
        common = Self.features.intersection(values)
        maxHeight = min(1080, height)
        maxFps = min(30, fps)
    }
    static func hello(requestID: String) -> Data {
        let message: [String: Any] = ["type": "visionlink-hello", "requestId": requestID,
            "protocol": 1, "role": "receiver", "features": features.sorted(),
            "video": ["maxHeight": 1080, "maxFps": 30],
            "app": ["id": Bundle.main.bundleIdentifier ?? "net.rivo.visioncraft",
                    "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                    "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"]]
        return (try? JSONSerialization.data(withJSONObject: message)) ?? Data()
    }
    static func feature(for type: String) -> String? {
        if type.hasPrefix("camera-zoom-") { return "camera-zoom.v1" }
        if type == "camera-share-state" { return "camera.v1" }
        if type == "media-recovery-request" { return "media-recovery.v1" }
        if type.hasPrefix("file-") { return "file.v1" }
        if type.hasPrefix("clipboard-") { return "text.v1" }
        if type.hasPrefix("feature-") || type.hasPrefix("chat-") || type.hasPrefix("live-reading-") { return "remote-actions.v1" }
        if type == "data-ping" || type == "data-pong" { return "core.v1" }
        return nil
    }
    func permits(_ type: String) -> Bool {
        guard let feature = Self.feature(for: type), common.contains(feature) else { return false }
        return feature != "camera.v1" || cameraAvailable
    }
}
