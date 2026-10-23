#if DEBUG
import SwiftUI
import Combine
import UserNotifications

struct LauncherWeatherCity: Codable, Equatable, Identifiable {
    var name: String
    var latitude: Double
    var longitude: Double
    var id: String { "\(latitude),\(longitude)" }
}
struct LauncherWeatherSnapshot: Codable {
    var city: LauncherWeatherCity
    var temperature: Double
    var feels: Double
    var low: Double
    var high: Double
    var code: Int
    var fetched: Date
}
struct LauncherTimerState: Codable {
    var deadline: Date?
    var remaining: TimeInterval = 0
    var minutes = 5
    var alarm = false
    var hour: Int?
    var minute: Int?
}
enum LauncherWeatherRefreshPolicy {
    static let interval: TimeInterval = 30 * 60
    static let retry: TimeInterval = 5 * 60
    static let stale: TimeInterval = 6 * 60 * 60
}
enum LauncherWeatherAPI {
    private struct Forecast: Decodable {
        struct Current: Decodable { var temperature_2m: Double; var apparent_temperature: Double; var weather_code: Int }
        struct Daily: Decodable { var temperature_2m_min: [Double]; var temperature_2m_max: [Double] }
        var current: Current; var daily: Daily
    }
    private static func get<T: Decodable>(_ type: T.Type, url: URL) async throws -> T {
        var request = URLRequest(url: url); request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(type, from: data)
    }
    static func forecast(_ city: LauncherWeatherCity) async throws -> LauncherWeatherSnapshot {
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [.init(name: "latitude", value: String(city.latitude)), .init(name: "longitude", value: String(city.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code"), .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "forecast_days", value: "1"), .init(name: "timezone", value: "auto")]
        let result = try await get(Forecast.self, url: url.url!)
        guard let low = result.daily.temperature_2m_min.first, let high = result.daily.temperature_2m_max.first else { throw URLError(.cannotParseResponse) }
        return LauncherWeatherSnapshot(city: city, temperature: result.current.temperature_2m, feels: result.current.apparent_temperature, low: low, high: high, code: result.current.weather_code, fetched: .now)
    }
    static func description(_ code: Int) -> String {
        switch code {
        case 0: return "맑음"
        case 1...3: return "구름"
        case 45, 48: return "안개"
        case 51...67, 80...82: return "비"
        case 71...77, 85, 86: return "눈"
        case 95...99: return "뇌우"
        default: return "날씨"
        }
    }
}
func launcherRemainingSeconds(deadline: Date, now: Date) -> Int { Int(ceil(max(0, deadline.timeIntervalSince(now)))) }
func launcherNextAlarm(hour: Int, minute: Int, now: Date, calendar: Calendar = .current) -> Date? {
    calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute, second: 0), matchingPolicy: .nextTime)
}

@MainActor
final class LauncherUtilityStore: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = LauncherUtilityStore()
    static let alertID = "ratio.launcher.timer"
    @Published var city: LauncherWeatherCity?
    @Published var weather: LauncherWeatherSnapshot?
    @Published var weatherLoading = false
    @Published var weatherError = ""
    @Published var timer: LauncherTimerState
    @Published var timerBusy = false
    @Published var timerNotice = ""
    private var timerGeneration = 0
    private var weatherGeneration = 0
    private var weatherRetryAt: Date?
    private let defaults = UserDefaults.standard
    private let weatherLocation = LauncherWeatherLocation()
    override init() {
        city = nil
        weather = nil
        timer = defaults.data(forKey: "ratio.utility.timer.v1").flatMap { try? JSONDecoder().decode(LauncherTimerState.self, from: $0) } ?? LauncherTimerState()
        super.init()
        if weather?.city != city { weather = nil }
        if UNUserNotificationCenter.current().delegate == nil { UNUserNotificationCenter.current().delegate = self }
    }
    var weatherPermissionDenied: Bool { weatherLocation.denied }
    func cancelWeatherLocation() { weatherLocation.cancel() }
    var nextWeatherRefresh: TimeInterval {
        if weatherLoading { return 1 }
        let delay: TimeInterval
        if let retry = weatherRetryAt { delay = max(1, min(LauncherWeatherRefreshPolicy.retry, retry.timeIntervalSinceNow)) }
        else if weatherError.isEmpty, let weather {
            delay = max(1, min(LauncherWeatherRefreshPolicy.interval, weather.fetched.addingTimeInterval(LauncherWeatherRefreshPolicy.interval).timeIntervalSinceNow))
        } else { delay = LauncherWeatherRefreshPolicy.retry }
        if let weather {
            return min(delay, max(1, weather.fetched.addingTimeInterval(LauncherWeatherRefreshPolicy.stale).timeIntervalSinceNow))
        }
        return delay
    }
    func refreshWeather(force: Bool = false) async {
        guard !weatherLoading else { return }
        if weatherLocation.denied {
            city = nil; weather = nil; weatherRetryAt = .now.addingTimeInterval(LauncherWeatherRefreshPolicy.retry)
            weatherError = "현재 위치의 날씨를 보려면 위치 권한을 허용해 주세요."
            return
        }
        if let value = weather, !(0..<LauncherWeatherRefreshPolicy.stale).contains(Date.now.timeIntervalSince(value.fetched)) { weather = nil; city = nil }
        if weather == nil, weatherLocation.authorized,
           let cache = defaults.data(forKey: "ratio.utility.weather.locationCache.v1").flatMap({ try? JSONDecoder().decode(LauncherWeatherSnapshot.self, from: $0) }),
           (0..<LauncherWeatherRefreshPolicy.stale).contains(Date.now.timeIntervalSince(cache.fetched)) { weather = cache; city = cache.city }
        if !force {
            if let retry = weatherRetryAt, retry > .now { return }
            if weatherError.isEmpty, let weather, (0..<LauncherWeatherRefreshPolicy.interval).contains(Date.now.timeIntervalSince(weather.fetched)) { return }
        }
        weatherGeneration += 1; let generation = weatherGeneration
        weatherLoading = true; weatherError = ""
        defer { if weatherGeneration == generation { weatherLoading = false } }
        do {
            let selected = try await weatherLocation.current()
            try Task.checkCancellation()
            let result = try await LauncherWeatherAPI.forecast(selected)
            try Task.checkCancellation()
            guard generation == weatherGeneration else { return }
            city = selected; weather = result; weatherRetryAt = nil
            defaults.set(try? JSONEncoder().encode(result), forKey: "ratio.utility.weather.locationCache.v1")
            defaults.removeObject(forKey: "ratio.utility.weather.city.v1")
            defaults.removeObject(forKey: "ratio.utility.weather.cache.v1")
        } catch is CancellationError { }
        catch LauncherWeatherLocation.Failure.permission {
            city = nil; weather = nil
            weatherError = "현재 위치의 날씨를 보려면 위치 권한을 허용해 주세요."
            weatherRetryAt = .now.addingTimeInterval(LauncherWeatherRefreshPolicy.retry)
        }
        catch LauncherWeatherLocation.Failure.unavailable {
            weatherError = "현재 위치를 확인하지 못했습니다. 위치 서비스를 켠 뒤 다시 시도해 주세요."
            weatherRetryAt = .now.addingTimeInterval(LauncherWeatherRefreshPolicy.retry)
        }
        catch {
            if !Task.isCancelled && generation == weatherGeneration {
                weatherError = "날씨를 불러오지 못했습니다. 다시 시도해 주세요."
                weatherRetryAt = .now.addingTimeInterval(LauncherWeatherRefreshPolicy.retry)
            }
        }
    }
    private func saveTimer() { defaults.set(try? JSONEncoder().encode(timer), forKey: "ratio.utility.timer.v1") }
    func cancelTimer(remaining: TimeInterval = 0) {
        timerGeneration += 1
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.alertID])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.alertID])
        timer.deadline = nil; timer.remaining = remaining; saveTimer()
    }
    func setMinutes(_ minutes: Int) {
        cancelTimer(); timer.minutes = min(180, max(1, minutes)); saveTimer()
    }
    func setAlarmMode(_ alarm: Bool) { cancelTimer(); timer.alarm = alarm; saveTimer() }
    func configureTimer(minutes: Int, alarm: Bool, hour: Int, minute: Int) {
        cancelTimer(); timer.minutes = min(180, max(1, minutes)); timer.alarm = alarm
        timer.hour = hour; timer.minute = minute; saveTimer()
    }
    func startTimer(until deadline: Date) async {
        guard !timerBusy, deadline > .now else { return }
        timerBusy = true; timerNotice = ""; timerGeneration += 1; let generation = timerGeneration
        defer { timerBusy = false }
        let center = UNUserNotificationCenter.current()
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]), generation == timerGeneration else {
                timerNotice = "알림을 허용한 뒤 다시 시작해 주세요."; return
            }
            let content = UNMutableNotificationContent()
            content.title = "시간이 됐어요"; content.body = "설정한 시간이 되었습니다."; content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)
            try await center.add(UNNotificationRequest(identifier: Self.alertID, content: content, trigger: trigger))
            guard generation == timerGeneration else { center.removePendingNotificationRequests(withIdentifiers: [Self.alertID]); return }
            timer.deadline = deadline; timer.remaining = 0; saveTimer()
        } catch { timerNotice = "알림을 예약하지 못했습니다. 다시 시도해 주세요." }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

private struct UtilityButton: View {
    var title: String
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).visionCraftAndroidText(18).fontWeight(selected ? .bold : .regular).underline(selected).padding(.horizontal, 12).frame(minWidth: 48, minHeight: 52)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.55), lineWidth: 1)) }.accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
struct RatioUtilityWidget: View {
    var widget: RatioHomeItem
    var active: Bool
    var height: CGFloat? = nil
    var onEdit: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var store = LauncherUtilityStore.shared
    @State private var showsSettings = false
    @State private var showsWeatherDetails = false
    @State private var weatherRefreshRequest = 0
    @State private var handledWeatherRefresh = 0
    @State private var draftMinutes = 5
    @State private var draftAlarm = false
    @State private var draftTime = Date()
    private var ink: Color { widget.colorKey == nil ? RatioExperience().text : RatioExperience().ink }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if widget.isWeather { weatherContent } else { timerContent }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }.foregroundStyle(ink).tint(ink).buttonStyle(.plain)
            .background(ratioPalette.first { $0.id == widget.colorKey }?.color ?? RatioExperience().surface, in: RoundedRectangle(cornerRadius: 8))
            .onLongPressGesture(perform: onEdit)
            .accessibilityAction(named: "위젯 설정") { onEdit() }
            .sheet(isPresented: $showsSettings) { timerSettings }
            .sheet(isPresented: $showsWeatherDetails) { weatherDetails }
            .onDisappear { if widget.isWeather { store.cancelWeatherLocation() } }
            .task(id: "\(active && scenePhase == .active):\(weatherRefreshRequest)") {
                guard widget.isWeather else { return }
                guard active, scenePhase == .active else { store.cancelWeatherLocation(); return }
                var force = weatherRefreshRequest != handledWeatherRefresh
                handledWeatherRefresh = weatherRefreshRequest
                while !Task.isCancelled {
                    await store.refreshWeather(force: force)
                    force = false
                    do { try await Task.sleep(for: .seconds(store.nextWeatherRefresh)) } catch { return }
                }
            }
    }
    private var weatherContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.city?.name ?? "날씨").visionCraftAndroidText(20).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                if let weather = store.weather {
                    Button { showsWeatherDetails = true } label: {
                        HStack(spacing: 8) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text("\(Int(weather.temperature.rounded()))°").visionCraftAndroidText(56).fixedSize()
                            }
                            LauncherWeatherArtwork(code: weather.code).frame(width: 64, height: 64)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.accessibilityHint("날씨 상세 정보 열기")
                }
                if store.weatherLoading && store.weather == nil { Text("날씨 불러오는 중").visionCraftAndroidText(20).fixedSize(horizontal: false, vertical: true) }
                if !store.weatherError.isEmpty {
                    Text(store.weatherError).visionCraftAndroidText(16).fixedSize(horizontal: false, vertical: true)
                    if store.weather == nil, let url = URL(string: UIApplication.openSettingsURLString) { Link("위치 권한 설정", destination: url).frame(minHeight: 52) }
                }
            }
            Spacer(minLength: 8)
            HStack(alignment: .bottom, spacing: 8) {
                if let weather = store.weather {
                    Button { showsWeatherDetails = true } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(LauncherWeatherAPI.description(weather.code)).visionCraftAndroidText(22).fixedSize(horizontal: false, vertical: true)
                            Text("\(weather.fetched.formatted(date: .omitted, time: .shortened)) 갱신").visionCraftAndroidText(16).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.accessibilityHint("날씨 상세 정보 열기")
                } else { Spacer(minLength: 0) }
                timerControl("arrow.clockwise", label: "날씨 새로고침") { weatherRefreshRequest += 1 }
                    .disabled(store.weatherLoading || store.weatherPermissionDenied || !active || scenePhase != .active)
            }
        }.frame(minHeight: max(0, (height ?? CGFloat(widget.rows * 100 - 12)) - 24), alignment: .topLeading)
    }
    private var weatherDetails: some View {
        NavigationStack {
            ScrollView {
                if let weather = store.weather {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("체감 \(Int(weather.feels.rounded()))°").visionCraftAndroidText(20)
                        Text("최저 \(Int(weather.low.rounded()))° / 최고 \(Int(weather.high.rounded()))°").visionCraftAndroidText(20)
                        Text("\(weather.fetched.formatted(date: .omitted, time: .shortened)) 갱신 · Open-Meteo").visionCraftAndroidText(16)
                    }.padding(24)
                }
            }.navigationTitle(store.city?.name ?? "날씨")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { showsWeatherDetails = false } } }
        }.presentationDetents([.medium, .large])
            .tint(RatioExperience().text).foregroundStyle(RatioExperience().text).preferredColorScheme(.dark)
    }
    private var timerContent: some View {
        TimelineView(.periodic(from: .now, by: active && scenePhase == .active ? 1 : 60)) { timeline in
            let running = (store.timer.deadline ?? .distantPast) > timeline.date
            let seconds = store.timer.deadline.map { launcherRemainingSeconds(deadline: $0, now: timeline.date) } ?? Int(ceil(store.timer.remaining > 0 ? store.timer.remaining : Double(store.timer.minutes * 60)))
            let hour = store.timer.hour ?? Calendar.current.component(.hour, from: store.timer.deadline ?? .now)
            let minute = store.timer.minute ?? Calendar.current.component(.minute, from: store.timer.deadline ?? .now)
            let value = store.timer.alarm ? String(format: "%02d:%02d", hour, minute) : String(format: "%02d:%02d", seconds / 60, seconds % 60)
            VStack(alignment: .leading, spacing: 6) {
                if store.timer.deadline != nil && !running { Text("시간이 됐어요").visionCraftAndroidText(16).fixedSize(horizontal: false, vertical: true) }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(value).visionCraftAndroidText(72).monospacedDigit().fixedSize()
                }.accessibilityLabel(store.timer.alarm ? "알람, \(value)" : "\(seconds / 60)분 \(seconds % 60)초 남음")
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    timerControl(running ? "pause.fill" : "play.fill", label: running ? "일시정지" : "재생") {
                        if running { store.cancelTimer(remaining: store.timer.alarm ? 0 : max(0, store.timer.deadline?.timeIntervalSinceNow ?? 0)) }
                        else if store.timer.alarm {
                            if let next = launcherNextAlarm(hour: hour, minute: minute, now: .now) { Task { await store.startTimer(until: next) } }
                        } else {
                            let duration = store.timer.remaining > 0 ? store.timer.remaining : Double(store.timer.minutes * 60)
                            Task { await store.startTimer(until: .now.addingTimeInterval(duration)) }
                        }
                    }
                    timerControl("gearshape.fill", label: "시간 설정") {
                        draftMinutes = store.timer.minutes; draftAlarm = store.timer.alarm
                        draftTime = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
                        showsSettings = true
                    }
                }.disabled(store.timerBusy)
                if !store.timerNotice.isEmpty {
                    Text(store.timerNotice).visionCraftAndroidText(16).fixedSize(horizontal: false, vertical: true)
                    if let url = URL(string: UIApplication.openSettingsURLString) { Link("알림 설정", destination: url).frame(minHeight: 52) }
                }
            }.frame(minHeight: max(0, (height ?? CGFloat(widget.rows * 88 + (widget.rows - 1) * 12)) - 24), alignment: .topLeading)
        }
    }
    private func timerControl(_ image: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image).font(.system(size: 28)).frame(width: 56, height: 56)
                .background(ink.opacity(0.12), in: Circle())
        }.accessibilityLabel(label)
    }
    private var timerSettings: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("종류", selection: $draftAlarm) { Text("타이머").tag(false); Text("알람").tag(true) }.pickerStyle(.segmented)
                    if draftAlarm {
                        DatePicker("알람 시각", selection: $draftTime, displayedComponents: .hourAndMinute).datePickerStyle(.wheel)
                    } else {
                        Text("\(draftMinutes)분").visionCraftAndroidText(32)
                        Stepper("시간 설정", value: $draftMinutes, in: 1...180).frame(minHeight: 56)
                        ViewThatFits(in: .horizontal) {
                            HStack { presets }
                            VStack(alignment: .leading) { presets }
                        }
                    }
                }.padding(24)
            }.navigationTitle("시간 설정")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소") { showsSettings = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("적용") {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: draftTime)
                        store.configureTimer(minutes: draftMinutes, alarm: draftAlarm, hour: parts.hour ?? 0, minute: parts.minute ?? 0)
                        showsSettings = false
                    } }
                }
        }.presentationDetents([.medium, .large])
            .tint(RatioExperience().text).foregroundStyle(RatioExperience().text).preferredColorScheme(.dark)
    }
    private var presets: some View {
        ForEach([5, 10, 25], id: \.self) { minutes in UtilityButton(title: "\(minutes)분", selected: draftMinutes == minutes) { draftMinutes = minutes } }
    }
}
#endif
