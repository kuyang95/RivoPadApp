import Foundation
import XCTest

@testable import shortcuts_example

@MainActor
final class LocalAIUsageStoreTests:
    XCTestCase
{
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var calendar: Calendar!
    private var now: Date!

    override func setUpWithError()
        throws
    {
        suiteName =
            "LocalAIUsageStoreTests."
            + UUID().uuidString
        defaults =
            try XCTUnwrap(
                UserDefaults(
                    suiteName: suiteName
                )
            )
        defaults.removePersistentDomain(
            forName: suiteName
        )
        calendar =
            Calendar(
                identifier: .gregorian
            )
        calendar.timeZone =
            try XCTUnwrap(
                TimeZone(
                    secondsFromGMT: 0
                )
            )
        now = Date(
            timeIntervalSince1970:
                1_700_000_000
        )
    }

    override func tearDownWithError()
        throws
    {
        defaults.removePersistentDomain(
            forName: suiteName
        )
        defaults = nil
        suiteName = nil
        calendar = nil
        now = nil
    }

    func testRecordsPersistsAndRestoresAllResults()
    {
        let store = makeStore()

        store.record(
            .completed,
            generatedCharacters: 120,
            duration: 2.5
        )
        store.record(
            .failed,
            generatedCharacters: 10,
            duration: 1
        )
        store.record(
            .cancelled,
            generatedCharacters: 20,
            duration: 0.5
        )

        XCTAssertEqual(
            store.snapshot
                .completedRequests,
            1
        )
        XCTAssertEqual(
            store.snapshot.failedRequests,
            1
        )
        XCTAssertEqual(
            store.snapshot
                .cancelledRequests,
            1
        )
        XCTAssertEqual(
            store.snapshot.totalRequests,
            3
        )
        XCTAssertEqual(
            store.snapshot
                .generatedCharacters,
            150
        )
        XCTAssertEqual(
            store.snapshot
                .inferenceSeconds,
            4,
            accuracy: 0.001
        )

        let restored = makeStore()
        XCTAssertEqual(
            restored.snapshot,
            store.snapshot
        )
    }

    func testNewLocalDayStartsAtZero()
    {
        let store = makeStore()
        store.record(
            .completed,
            generatedCharacters: 5,
            duration: 1
        )

        now = now.addingTimeInterval(
            86_400
        )
        store.refresh()

        XCTAssertEqual(
            store.snapshot.totalRequests,
            0
        )
        XCTAssertEqual(
            store.snapshot
                .generatedCharacters,
            0
        )
        XCTAssertEqual(
            store.snapshot.dayIdentifier,
            LocalAIUsageStore
                .dayIdentifier(
                    for: now,
                    calendar: calendar
                )
        )
    }

    func testNegativeAndHugeMeasurementsAreBounded()
    {
        let store = makeStore()
        store.record(
            .completed,
            generatedCharacters: -10,
            duration: -5
        )
        XCTAssertEqual(
            store.snapshot
                .generatedCharacters,
            0
        )
        XCTAssertEqual(
            store.snapshot
                .inferenceSeconds,
            0
        )

        store.record(
            .completed,
            generatedCharacters:
                Int.max,
            duration:
                .greatestFiniteMagnitude
        )
        XCTAssertEqual(
            store.snapshot
                .generatedCharacters,
            10_000_000
        )
        XCTAssertEqual(
            store.snapshot
                .inferenceSeconds,
            21_600,
            accuracy: 0.001
        )
    }

    func testCorruptStoredSnapshotFallsBackToToday()
    {
        defaults.set(
            Data("invalid".utf8),
            forKey:
                LocalAIUsageStore
                .snapshotKey
        )
        let store = makeStore()

        XCTAssertEqual(
            store.snapshot.totalRequests,
            0
        )
        XCTAssertEqual(
            store.snapshot.dayIdentifier,
            LocalAIUsageStore
                .dayIdentifier(
                    for: now,
                    calendar: calendar
                )
        )
    }

    func testExcessiveStoredSnapshotFallsBackToToday()
        throws
    {
        let invalid =
            LocalAIUsageSnapshot(
                schemaVersion:
                    LocalAIUsageSnapshot
                    .schemaVersion,
                dayIdentifier:
                    LocalAIUsageStore
                    .dayIdentifier(
                        for: now,
                        calendar: calendar
                    ),
                completedRequests:
                    1_000_001,
                failedRequests: 0,
                cancelledRequests: 0,
                generatedCharacters: 0,
                inferenceSeconds: 0,
                updatedAt: now
            )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy =
            .iso8601
        defaults.set(
            try encoder.encode(invalid),
            forKey:
                LocalAIUsageStore
                .snapshotKey
        )

        let store = makeStore()

        XCTAssertEqual(
            store.snapshot.totalRequests,
            0
        )
    }

    private func makeStore()
        -> LocalAIUsageStore
    {
        LocalAIUsageStore(
            defaults: defaults,
            calendar: calendar,
            now: { [unowned self] in
                self.now
            },
            reloadsWidget: false
        )
    }
}
