import Foundation
import XCTest

@testable import shortcuts_example

final class CloudAITokenBudgetStoreTests:
    XCTestCase
{
    private final class DateBox:
        @unchecked Sendable
    {
        var value: Date

        init(_ value: Date) {
            self.value = value
        }
    }

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var calendar: Calendar!
    private var dateBox: DateBox!

    override func setUpWithError() throws {
        suiteName =
            "CloudAITokenBudgetStoreTests."
            + UUID().uuidString
        defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName)
        )
        defaults.removePersistentDomain(
            forName: suiteName
        )
        calendar = Calendar(
            identifier: .gregorian
        )
        calendar.timeZone = try XCTUnwrap(
            TimeZone(secondsFromGMT: 0)
        )
        dateBox = DateBox(
            Date(
                timeIntervalSince1970:
                    1_700_000_000
            )
        )
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(
            forName: suiteName
        )
        dateBox = nil
        calendar = nil
        defaults = nil
        suiteName = nil
    }

    func testStartsWithOneMillionTokens()
        async
    {
        let store = makeStore()

        let available = await store
            .availableTokens()
        XCTAssertEqual(available, 1_000_000)
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.usedTokens, 0)
        XCTAssertEqual(
            snapshot.remainingTokens,
            1_000_000
        )
    }

    func testCommitChargesActualTokensAndPersists()
        async throws
    {
        let store = makeStore()
        let reservation = try await store
            .reserve(
                inputTokens: 60_000,
                maximumOutputTokens: 4_096
            )

        let snapshot = await store.commit(
            reservation,
            actualTokens: 60_500
        )

        XCTAssertEqual(
            snapshot.usedTokens,
            60_500
        )
        let available = await store
            .availableTokens()
        XCTAssertEqual(available, 939_500)

        let restored = makeStore()
        let restoredSnapshot = await restored
            .snapshot()
        XCTAssertEqual(
            restoredSnapshot,
            snapshot
        )
    }

    func testReservationsPreventConcurrentOverspend()
        async throws
    {
        let store = makeStore()
        let first = try await store.reserve(
            inputTokens: 600_000,
            maximumOutputTokens: 0
        )

        do {
            _ = try await store.reserve(
                inputTokens: 400_001,
                maximumOutputTokens: 0
            )
            XCTFail("한도를 넘는 예약이 승인됨")
        } catch let error as
            CloudAITokenBudgetError {
            XCTAssertEqual(
                error,
                .dailyLimitExceeded(
                    remainingTokens: 400_000,
                    requiredTokens: 400_001
                )
            )
        }

        await store.cancel(first)
        let available = await store
            .availableTokens()
        XCTAssertEqual(available, 1_000_000)
    }

    func testMissingUsageMetadataChargesReservation()
        async throws
    {
        let store = makeStore()
        let reservation = try await store
            .reserve(
                inputTokens: 10_000,
                maximumOutputTokens: 2_000
            )

        let snapshot = await store.commit(
            reservation,
            actualTokens: nil
        )

        XCTAssertEqual(
            snapshot.usedTokens,
            12_000
        )
    }

    func testZeroUsageMetadataChargesReservation()
        async throws
    {
        let store = makeStore()
        let reservation = try await store
            .reserve(
                inputTokens: 8_000,
                maximumOutputTokens: 1_000
            )

        let snapshot = await store.commit(
            reservation,
            actualTokens: 0
        )

        XCTAssertEqual(
            snapshot.usedTokens,
            9_000
        )
    }

    func testNewLocalDayRestoresFullBudget()
        async throws
    {
        let store = makeStore()
        let reservation = try await store
            .reserve(
                inputTokens: 100_000,
                maximumOutputTokens: 0
            )
        _ = await store.commit(
            reservation,
            actualTokens: 100_000
        )

        dateBox.value = dateBox.value
            .addingTimeInterval(86_400)

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.usedTokens, 0)
        XCTAssertEqual(
            snapshot.remainingTokens,
            1_000_000
        )
    }

    #if DEBUG || WORD_AI_LIVE_EVAL || WORD_AI_LIVE_SMOKE
    func testRefillForTestingRestoresBudgetAndClearsReservations()
        async throws
    {
        let store = makeStore()
        let committed = try await store.reserve(
            inputTokens: 250_000,
            maximumOutputTokens: 0
        )
        _ = await store.commit(
            committed,
            actualTokens: 200_000
        )
        _ = try await store.reserve(
            inputTokens: 300_000,
            maximumOutputTokens: 0
        )

        let snapshot = await store
            .refillForTesting()

        XCTAssertEqual(snapshot.usedTokens, 0)
        XCTAssertEqual(
            snapshot.remainingTokens,
            1_000_000
        )
        let available = await store
            .availableTokens()
        XCTAssertEqual(available, 1_000_000)

        let restored = makeStore()
        let restoredSnapshot = await restored
            .snapshot()
        XCTAssertEqual(
            restoredSnapshot.usedTokens,
            0
        )
    }
    #endif

    private func makeStore()
        -> CloudAITokenBudgetStore
    {
        let dateBox = dateBox!
        return CloudAITokenBudgetStore(
            defaults: defaults,
            calendar: calendar,
            now: {
                dateBox.value
            }
        )
    }
}
