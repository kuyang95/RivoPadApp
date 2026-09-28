import Foundation

nonisolated struct CloudAITokenBudgetSnapshot:
    Codable,
    Equatable,
    Sendable
{
    static let schemaVersion = 1

    let schemaVersion: Int
    let dayIdentifier: String
    let usedTokens: Int
    let updatedAt: Date

    var remainingTokens: Int {
        max(
            0,
            CloudAITokenBudgetStore.dailyLimit
                - usedTokens
        )
    }
}

nonisolated struct CloudAITokenReservation:
    Equatable,
    Sendable
{
    fileprivate let id: UUID
    let reservedTokens: Int
}

nonisolated enum CloudAITokenBudgetError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case dailyLimitExceeded(
        remainingTokens: Int,
        requiredTokens: Int
    )

    var errorDescription: String? {
        switch self {
        case .dailyLimitExceeded:
            return AppLocalization.string(
                "오늘의 클라우드 AI 100만 토큰을 모두 사용했습니다. 내일 다시 이용해 주세요."
            )
        }
    }
}

/// Word, Excel, OCR, 이미지 설명과 웹 검색이 함께 사용하는 일일 Gemini 예산이다.
///
/// 요청 전에 입력 토큰과 최대 출력 토큰을 예약하므로 동시에 여러 요청이 시작돼도
/// 일일 한도를 넘어 승인되지 않는다. 성공 후에는 예약량 대신 Gemini 응답의 실제
/// `totalTokenCount`를 저장하고, 실패하거나 취소되면 예약을 반환한다.
actor CloudAITokenBudgetStore {
    static let shared =
        CloudAITokenBudgetStore()

    static let dailyLimit = 1_000_000
    static let suiteName =
        "group.net.rivo.visioncraft"
    static let snapshotKey =
        "cloudAI.tokenBudget.today.v1"

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var storedSnapshot:
        CloudAITokenBudgetSnapshot
    private var reservations = [UUID: Int]()

    init(
        defaults: UserDefaults? = nil,
        calendar: Calendar =
            .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date =
            Date.init
    ) {
        self.defaults =
            defaults
            ?? UserDefaults(
                suiteName: Self.suiteName
            )
            ?? .standard
        self.calendar = calendar
        self.now = now

        let date = now()
        storedSnapshot = Self.load(
            defaults: self.defaults,
            date: date,
            calendar: calendar
        )
    }

    func snapshot()
        -> CloudAITokenBudgetSnapshot
    {
        refreshForCurrentDay()
        return storedSnapshot
    }

    func availableTokens() -> Int {
        refreshForCurrentDay()
        return max(
            0,
            storedSnapshot.remainingTokens
                - reservations.values.reduce(
                    0,
                    +
                )
        )
    }

    func reserve(
        inputTokens: Int,
        maximumOutputTokens: Int
    ) throws -> CloudAITokenReservation {
        refreshForCurrentDay()

        let requiredTokens = Self.cappedAdd(
            max(0, inputTokens),
            max(0, maximumOutputTokens),
            maximum: Self.dailyLimit
                + 1
        )
        let available = max(
            0,
            storedSnapshot.remainingTokens
                - reservations.values.reduce(
                    0,
                    +
                )
        )
        guard requiredTokens > 0,
              requiredTokens <= available else {
            throw CloudAITokenBudgetError
                .dailyLimitExceeded(
                    remainingTokens: available,
                    requiredTokens:
                        requiredTokens
                )
        }

        let id = UUID()
        reservations[id] = requiredTokens
        return CloudAITokenReservation(
            id: id,
            reservedTokens: requiredTokens
        )
    }

    @discardableResult
    func commit(
        _ reservation:
            CloudAITokenReservation,
        actualTokens: Int?
    ) -> CloudAITokenBudgetSnapshot {
        refreshForCurrentDay()
        guard let reserved =
                reservations.removeValue(
                    forKey: reservation.id
                ) else {
            return storedSnapshot
        }

        // 사용량 메타데이터가 누락되면 사용량을 0으로 만들지 않고 예약량을 차감한다.
        let reportedTokens =
            actualTokens ?? 0
        let chargedTokens = min(
            Self.dailyLimit,
            reportedTokens > 0
                ? reportedTokens
                : reserved
        )
        storedSnapshot =
            CloudAITokenBudgetSnapshot(
                schemaVersion:
                    CloudAITokenBudgetSnapshot
                    .schemaVersion,
                dayIdentifier:
                    storedSnapshot
                    .dayIdentifier,
                usedTokens: min(
                    Self.dailyLimit,
                    Self.cappedAdd(
                        storedSnapshot
                            .usedTokens,
                        chargedTokens,
                        maximum:
                            Self.dailyLimit
                    )
                ),
                updatedAt: now()
            )
        save()
        return storedSnapshot
    }

    func cancel(
        _ reservation:
            CloudAITokenReservation
    ) {
        refreshForCurrentDay()
        reservations.removeValue(
            forKey: reservation.id
        )
    }

    #if DEBUG || WORD_AI_LIVE_EVAL || WORD_AI_LIVE_SMOKE
    /// Explicitly refills the app-local token budget for an opt-in live test.
    ///
    /// This does not reset Gemini provider quotas or billing. Keeping the API
    /// behind test-only compilation conditions prevents the shipping app from
    /// bypassing its daily safety budget.
    @discardableResult
    func refillForTesting()
        -> CloudAITokenBudgetSnapshot
    {
        let date = now()
        storedSnapshot = Self.emptySnapshot(
            date: date,
            calendar: calendar
        )
        reservations.removeAll()
        save()
        return storedSnapshot
    }
    #endif

    private func refreshForCurrentDay() {
        let date = now()
        let identifier = Self.dayIdentifier(
            for: date,
            calendar: calendar
        )
        guard storedSnapshot.dayIdentifier
                != identifier else {
            return
        }

        storedSnapshot = Self.emptySnapshot(
            date: date,
            calendar: calendar
        )
        reservations.removeAll()
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(
            storedSnapshot
        ) else {
            return
        }
        defaults.set(
            data,
            forKey: Self.snapshotKey
        )
    }

    private static func load(
        defaults: UserDefaults,
        date: Date,
        calendar: Calendar
    ) -> CloudAITokenBudgetSnapshot {
        guard let data = defaults.data(
                  forKey: snapshotKey
              ) else {
            return emptySnapshot(
                date: date,
                calendar: calendar
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(
                  CloudAITokenBudgetSnapshot.self,
                  from: data
              ),
              snapshot.schemaVersion
                == CloudAITokenBudgetSnapshot
                .schemaVersion,
              snapshot.dayIdentifier
                == dayIdentifier(
                    for: date,
                    calendar: calendar
                ),
              snapshot.usedTokens >= 0,
              snapshot.usedTokens <= dailyLimit
        else {
            return emptySnapshot(
                date: date,
                calendar: calendar
            )
        }
        return snapshot
    }

    private static func emptySnapshot(
        date: Date,
        calendar: Calendar
    ) -> CloudAITokenBudgetSnapshot {
        CloudAITokenBudgetSnapshot(
            schemaVersion:
                CloudAITokenBudgetSnapshot
                .schemaVersion,
            dayIdentifier: dayIdentifier(
                for: date,
                calendar: calendar
            ),
            usedTokens: 0,
            updatedAt: date
        )
    }

    static func dayIdentifier(
        for date: Date,
        calendar: Calendar
    ) -> String {
        let components = calendar
            .dateComponents(
                [.year, .month, .day],
                from: date
            )
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func cappedAdd(
        _ lhs: Int,
        _ rhs: Int,
        maximum: Int
    ) -> Int {
        guard lhs < maximum,
              rhs < maximum else {
            return maximum
        }
        return min(
            maximum,
            lhs + rhs
        )
    }
}
