import UIKit

/// Runs a document save started on leaving a screen or on going to the background inside a
/// UIKit background task, so iPadOS lets the write finish after the app leaves the screen.
/// The task ends when the save returns, or when the system says time is up.
@MainActor
final class DocumentBackgroundSave {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    private init() {}

    /// Starts `work` at once; returns its task for callers that wait on the result.
    @discardableResult
    static func run<Result: Sendable>(
        named name: String,
        _ work: @escaping @MainActor () async -> Result
    ) -> Task<Result, Never> {
        let assertion = DocumentBackgroundSave()
        assertion.identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
            MainActor.assumeIsolated { assertion.end() }
        }
        return Task { @MainActor in
            let result = await work()
            assertion.end()
            return result
        }
    }

    private func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
