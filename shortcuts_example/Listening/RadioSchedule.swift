import Foundation

nonisolated struct RadioProgram: Identifiable, Sendable {
    let title: String
    let start: Date
    let end: Date
    var artworkURL: String? = nil
    var id: String { "\(start.timeIntervalSince1970):\(title)" }
    func isCurrent(_ now: Date) -> Bool { start <= now && now < end }
    var timeRange: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = RadioSchedule.zone; f.dateFormat = "HH:mm"
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }
}

/// Broadcast schedules describe wall-clock programming, never a seekable audio buffer.
nonisolated enum RadioSchedule {
    static let zone = TimeZone(identifier: "Asia/Seoul")!
    private static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = zone; return c }
    static func supports(_ item: ListeningItem) -> Bool {
        let parts = item.id.split(separator: ":")
        return item.kind == "radio" && parts.count == 4 && parts[2] == "national" && ["kbs", "mbc", "sbs"].contains(String(parts[1]))
    }
    static func window(_ rows: [RadioProgram], now: Date) -> [RadioProgram] {
        let index = rows.firstIndex(where: { $0.end > now }) ?? rows.count
        return Array(rows[max(0, index - 1)..<min(rows.count, index + 3)])
    }
    static func load(_ item: ListeningItem, now: Date = Date()) async throws -> [RadioProgram] {
        guard supports(item) else { return [] }
        let parts = item.id.split(separator: ":"); let provider = String(parts[1]); let channel = String(parts[3])
        let day = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: day)!
        func dateString(_ d: Date) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone; f.dateFormat = "yyyyMMdd"; return f.string(from: d) }
        var result: [RadioProgram] = []
        if provider == "kbs" {
            guard let code = ["1radio":"21", "2radio":"22", "3radio":"23", "1fm":"24", "2fm":"25", "hanminjok":"26"][channel] else { return [] }
            let endpoint = "https://static.api.kbs.co.kr/mediafactory/v1/schedule/weekly?local_station_code=00&channel_code=\(code)&program_planned_date_from=\(dateString(yesterday))&program_planned_date_to=\(dateString(day))"
            let root = try JSONSerialization.jsonObject(with: await ListeningCatalog.data(URL(string: endpoint)!)) as? [[String: Any]] ?? []
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone; f.dateFormat = "yyyyMMdd"
            for group in root {
                for row in group["schedules"] as? [[String: Any]] ?? [] {
                    guard let date = row["program_planned_date"] as? String, let base = f.date(from: date),
                          let start = row["program_planned_start_time"] as? String, let end = row["program_planned_end_time"] as? String,
                          let title = row["programming_table_title"] as? String ?? row["program_title"] as? String,
                          let program = program(title, start: String(start.prefix(4)), end: String(end.prefix(4)), day: base, artwork: row["image_w"] as? String) else { continue }
                    result.append(program)
                }
            }
        } else if provider == "mbc" {
            guard let code = ["sfm":"STFM", "fm4u":"FM4U", "chm":"CHAM"][channel] else { return [] }
            let root = try JSONSerialization.jsonObject(with: await ListeningCatalog.data(URL(string: "https://miniapi.imbc.com/Schedule/schedulelist")!)) as? [[String: Any]] ?? []
            let weekdays = ["일", "월", "화", "수", "목", "금", "토"]
            for base in [yesterday, day] {
                let weekday = weekdays[calendar.component(.weekday, from: base) - 1]
                for row in root where row["Channel"] as? String == code && row["LiveDays"] as? String == weekday {
                    if let title = row["ProgramTitle"] as? String, let start = row["StartTime"] as? String, let end = row["EndTime"] as? String,
                       let p = program(title, start: start, end: end, day: base, artwork: row["MiniAppPicture"] as? String ?? row["Picture"] as? String) { result.append(p) }
                }
            }
        } else {
            guard let code = ["powerfm":"power", "lovefm":"love", "dmb":"dmb"][channel] else { return [] }
            let root = try JSONSerialization.jsonObject(with: await ListeningCatalog.data(URL(string: "https://static.apis.sbs.co.kr/radio-api/gorealra/1.0/main/section/common")!)) as? [String: Any] ?? [:]
            let groups = root["schedule"] as? [String: Any] ?? [:]
            for row in groups[code] as? [[String: Any]] ?? [] {
                guard let title = row["title"] as? String, let start = row["start_time"] as? String, let end = row["end_time"] as? String else { continue }
                var base = day
                // The official on-air flag disambiguates a programme spanning midnight.
                if row["onair_flag"] as? String == "Y", let a = minutes(start), let b = minutes(end), b < a,
                   calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now) < b { base = yesterday }
                if let p = program(title, start: start, end: end, day: base, artwork: (row["onair"] as? [String: Any])?["image"] as? String) { result.append(p) }
            }
        }
        try Task.checkCancellation()
        var ids = Set<String>()
        let rows = result.filter { ids.insert($0.id).inserted }.sorted { $0.start < $1.start }
        return provider == "kbs" ? coalesced(rows) : rows
    }
    // KBS splits a single programme into half-hour slots in its official feed.
    static func coalesced(_ rows: [RadioProgram]) -> [RadioProgram] {
        var result: [RadioProgram] = []
        for row in rows {
            if let previous = result.last, previous.title == row.title, previous.artworkURL == row.artworkURL,
               previous.end == row.start, row.end.timeIntervalSince(previous.start) <= 86_400 {
                result[result.count - 1] = RadioProgram(title: previous.title, start: previous.start, end: row.end, artworkURL: previous.artworkURL)
            } else {
                result.append(row)
            }
        }
        return result
    }
    private static func minutes(_ value: String) -> Int? {
        let chunks = value.split(separator: ":").map(String.init)
        let hours: Int?; let mins: Int?
        if chunks.count == 2 { hours = Int(chunks[0]); mins = Int(chunks[1]) }
        else if value.count == 4 { hours = Int(value.prefix(2)); mins = Int(value.suffix(2)) }
        else { return nil }
        guard let h = hours, let m = mins, (0...47).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }
    private static func program(_ title: String, start: String, end: String, day: Date, artwork: String? = nil) -> RadioProgram? {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let a = minutes(start), let b = minutes(end) else { return nil }
        let last = b <= a ? b + 1440 : b
        guard last - a <= 1440 else { return nil }
        return RadioProgram(title: title, start: day.addingTimeInterval(Double(a * 60)), end: day.addingTimeInterval(Double(last * 60)), artworkURL: artwork.flatMap { ListeningCatalog.webURL($0)?.absoluteString })
    }
}
