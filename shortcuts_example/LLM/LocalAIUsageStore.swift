import Combine
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

nonisolated struct LocalAIUsageSnapshot:
    Codable,
    Equatable,
    Sendable
{
    static let schemaVersion = 1

    let schemaVersion: Int
    let dayIdentifier: String
    let completedRequests: Int
    let failedRequests: Int
    let cancelledRequests: Int
    let generatedCharacters: Int
    let inferenceSeconds: Double
    let updatedAt: Date

    var totalRequests: Int {
        completedRequests
            + failedRequests
            + cancelledRequests
    }

    static func empty(
        dayIdentifier: String,
        date: Date
    ) -> LocalAIUsageSnapshot {
        LocalAIUsageSnapshot(
            schemaVersion: schemaVersion,
            dayIdentifier: dayIdentifier,
            completedRequests: 0,
            failedRequests: 0,
            cancelledRequests: 0,
            generatedCharacters: 0,
            inferenceSeconds: 0,
            updatedAt: date
        )
    }
}

@MainActor
final class LocalAIUsageStore:
    ObservableObject
{
    enum Result: Equatable {
        case completed
        case failed
        case cancelled
    }

    static let shared =
        LocalAIUsageStore()

    static let suiteName =
        "group.com.rivo.shortcuts.example"
    static let snapshotKey =
        "localAI.usage.today.v1"
    static let widgetKind =
        "LocalAIUsageWidget"

    @Published private(set)
    var snapshot: LocalAIUsageSnapshot

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private let reloadsWidget: Bool

    init(
        defaults: UserDefaults? = nil,
        calendar: Calendar =
            .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init,
        reloadsWidget: Bool = true
    ) {
        self.defaults =
            defaults
            ?? UserDefaults(
                suiteName:
                    Self.suiteName
            )
            ?? .standard
        self.calendar = calendar
        self.now = now
        self.reloadsWidget =
            reloadsWidget
        let date = now()
        snapshot =
            Self.load(
                defaults:
                    self.defaults,
                date: date,
                calendar: calendar
            )
    }

    func refresh() {
        let date = now()
        let current =
            Self.load(
                defaults: defaults,
                date: date,
                calendar: calendar
            )
        guard current != snapshot else {
            return
        }
        snapshot = current
    }

    func record(
        _ result: Result,
        generatedCharacters: Int,
        duration: TimeInterval
    ) {
        let date = now()
        let base =
            Self.load(
                defaults: defaults,
                date: date,
                calendar: calendar
            )
        let safeCharacters =
            min(
                max(0, generatedCharacters),
                10_000_000
            )
        let safeDuration =
            min(
                max(0, duration),
                21_600
            )

        let completed =
            result == .completed
            ? increment(
                base.completedRequests
            )
            : base.completedRequests
        let failed =
            result == .failed
            ? increment(
                base.failedRequests
            )
            : base.failedRequests
        let cancelled =
            result == .cancelled
            ? increment(
                base.cancelledRequests
            )
            : base.cancelledRequests

        snapshot =
            LocalAIUsageSnapshot(
                schemaVersion:
                    LocalAIUsageSnapshot
                    .schemaVersion,
                dayIdentifier:
                    base.dayIdentifier,
                completedRequests:
                    completed,
                failedRequests: failed,
                cancelledRequests:
                    cancelled,
                generatedCharacters:
                    cappedAdd(
                        base.generatedCharacters,
                        safeCharacters
                    ),
                inferenceSeconds:
                    min(
                        base.inferenceSeconds
                            + safeDuration,
                        86_400
                    ),
                updatedAt: date
            )
        save()
    }

    static func dayIdentifier(
        for date: Date,
        calendar: Calendar
    ) -> String {
        let components =
            calendar.dateComponents(
                [
                    .year,
                    .month,
                    .day,
                ],
                from: date
            )
        return String(
            format:
                "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func load(
        defaults: UserDefaults,
        date: Date,
        calendar: Calendar
    ) -> LocalAIUsageSnapshot {
        let today =
            dayIdentifier(
                for: date,
                calendar: calendar
            )
        guard let data =
                defaults.data(
                    forKey:
                        snapshotKey
                )
        else {
            return .empty(
                dayIdentifier: today,
                date: date
            )
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy =
            .iso8601
        guard let restored =
                try? decoder.decode(
                    LocalAIUsageSnapshot.self,
                    from: data
                ),
              restored.schemaVersion
                == LocalAIUsageSnapshot
                .schemaVersion,
              restored.dayIdentifier
                == today,
              restored.completedRequests
                >= 0,
              restored.failedRequests >= 0,
              restored.cancelledRequests
                >= 0,
              restored.completedRequests
                <= 1_000_000,
              restored.failedRequests
                <= 1_000_000,
              restored.cancelledRequests
                <= 1_000_000,
              restored.generatedCharacters
                >= 0,
              restored.generatedCharacters
                <= 1_000_000_000,
              restored.inferenceSeconds
                .isFinite,
              restored.inferenceSeconds
                >= 0,
              restored.inferenceSeconds
                <= 86_400 else {
            return .empty(
                dayIdentifier: today,
                date: date
            )
        }
        return restored
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy =
            .iso8601
        guard let data =
                try? encoder.encode(
                    snapshot
                ) else {
            return
        }
        defaults.set(
            data,
            forKey:
                Self.snapshotKey
        )
        guard reloadsWidget else {
            return
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared
            .reloadTimelines(
                ofKind:
                    Self.widgetKind
            )
        #endif
    }

    private func increment(
        _ value: Int
    ) -> Int {
        min(value, 999_999) + 1
    }

    private func cappedAdd(
        _ lhs: Int,
        _ rhs: Int
    ) -> Int {
        let maximum = 1_000_000_000
        guard lhs < maximum else {
            return maximum
        }
        return min(
            maximum,
            lhs + min(
                rhs,
                maximum - lhs
            )
        )
    }
}
