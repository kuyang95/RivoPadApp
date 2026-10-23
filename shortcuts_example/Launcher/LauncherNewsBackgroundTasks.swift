import Foundation
@preconcurrency import BackgroundTasks

/// Registered in every build because the permitted identifier is present in Info.plist.
@MainActor
enum LauncherNewsBackgroundTasks {
    nonisolated static let enabledKey = "ratio.news.background.enabled"
    nonisolated private static let identifier = "me.rivo.launcher.news.refresh"
    private static var registered = false
    static func register() {
        guard !registered else { return }
        registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            let operation = Task { @MainActor in
                schedule()
                let success = await LauncherNewsRefresh.prefetch(revalidate: true)
                return success && !Task.isCancelled
            }
            task.expirationHandler = { operation.cancel() }
            Task { task.setTaskCompleted(success: await operation.value) }
        }
    }
    static func schedule() {
        guard registered, UserDefaults.standard.bool(forKey: enabledKey) else { return }
        BGTaskScheduler.shared.getPendingTaskRequests { requests in
            guard !requests.contains(where: { $0.identifier == identifier }) else { return }
            Task { @MainActor in
                guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
                let request = BGProcessingTaskRequest(identifier: identifier)
                request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60 * 60)
                request.requiresNetworkConnectivity = true
                request.requiresExternalPower = false
                do { try BGTaskScheduler.shared.submit(request) }
                catch { NSLog("News background refresh could not be scheduled: %@", String(describing: error)) }
            }
        }
    }
    static func cancel() { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier) }
}
