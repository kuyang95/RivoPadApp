import Foundation
import CoreFoundation

/// Confirmed zoom of the sender camera, shared by all controls.
nonisolated struct VisionLinkCameraZoom: Equatable, Sendable {
    let sessionID: String
    let value: Double
    let minimum: Double
    let maximum: Double
    let supported: Bool
    let revision: Int
    let hasError: Bool

    init?(message: [String: Any]) {
        guard let sessionID = message["sessionId"] as? String,
              !sessionID.isEmpty, sessionID.utf8.count <= 256,
              let value = Self.number(message["value"]),
              let minimum = Self.number(message["min"]),
              let maximum = Self.number(message["max"]),
              value.isFinite, minimum.isFinite, maximum.isFinite,
              minimum >= 1, maximum >= minimum, value >= minimum, value <= maximum,
              let supported = message["supported"] as? Bool,
              let revisionNumber = Self.number(message["revision"]),
              revisionNumber >= 0, revisionNumber < Double(Int.max),
              revisionNumber.rounded(.down) == revisionNumber else { return nil }
        self.sessionID = sessionID
        self.value = value
        self.minimum = minimum
        self.maximum = maximum
        self.supported = supported && maximum > minimum
        self.revision = Int(revisionNumber)
        self.hasError = message["error"] as? Bool ?? false
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }

    func clamped(_ value: Double) -> Double? {
        guard supported, value.isFinite else { return nil }
        return min(maximum, max(minimum, value))
    }
}
