import XCTest
@testable import shortcuts_example

final class LauncherUtilityTests: XCTestCase {
    func testUtilitySizesStayUsableAndKeepColorWithoutChangingToShortcuts() {
        let weather = RatioHomeItem(id: "widget:weather", name: "날씨", textOnly: true, columns: 1, rows: 1, colorKey: "mint").normalized
        XCTAssertTrue(weather.isUtility)
        XCTAssertFalse(weather.textOnly)
        XCTAssertEqual(weather.columns, 2)
        XCTAssertEqual(weather.rows, 3)
        XCTAssertEqual(weather.colorKey, "mint")
        let timer = RatioHomeItem(id: "widget:timer", name: "타이머", columns: 1, rows: 1).normalized
        XCTAssertEqual(timer.columns, 4)
        XCTAssertEqual(timer.rows, 3)
        XCTAssertFalse(timer.isFullPage)
        XCTAssertEqual(ratioItemRows([weather, timer]).map { $0.map(\.id) }, [[weather.id], [timer.id]])
    }
    func testCountdownRoundsUpAndNeverBecomesNegative() {
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(launcherRemainingSeconds(deadline: now.addingTimeInterval(1.01), now: now), 2)
        XCTAssertEqual(launcherRemainingSeconds(deadline: now.addingTimeInterval(-1), now: now), 0)
    }
    func testPastAlarmMovesToTomorrowAndRespectsLocalCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 15, minute: 30)))
        let next = try XCTUnwrap(launcherNextAlarm(hour: 15, minute: 20, now: now, calendar: calendar))
        let date = calendar.dateComponents([.day, .hour, .minute], from: next)
        XCTAssertEqual(date.day, 23)
        XCTAssertEqual(date.hour, 15)
        XCTAssertEqual(date.minute, 20)
    }
    func testPausedTimerAndWeatherConfigurationSurviveCoding() throws {
        let state = LauncherTimerState(deadline: nil, remaining: 125, minutes: 10, alarm: false)
        let decoded = try JSONDecoder().decode(LauncherTimerState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.remaining, 125)
        XCTAssertEqual(decoded.minutes, 10)
        let city = LauncherWeatherCity(name: "서울", latitude: 37.566, longitude: 126.978)
        XCTAssertEqual(city, try JSONDecoder().decode(LauncherWeatherCity.self, from: JSONEncoder().encode(city)))
        XCTAssertEqual(LauncherWeatherAPI.description(61), "비")
        XCTAssertEqual(LauncherWeatherAPI.description(95), "뇌우")
    }
}
