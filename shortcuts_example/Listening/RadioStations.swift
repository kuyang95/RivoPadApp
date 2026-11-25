import Foundation

/// A stable broadcast identity; temporary CDN signatures are never stored here.
nonisolated private struct RadioStation: Decodable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let resolver: String
    let url: String
    let alternates: [String]
    let aliases: [String]
    let legacyNames: [String]
    let frequencies: [String]?
    let artworkURL: String?

    var item: ListeningItem {
        let labels = (frequencies ?? []).map { value in
            value.contains(".") ? "FM \(value)" : "AM \(value)"
        }
        return ListeningItem(id: id, title: title, subtitle: ([subtitle] + labels).joined(separator: " · "), url: url, kind: "radio", artworkURL: artworkURL)
    }
}

nonisolated enum RadioStations {
    private struct Registry: Decodable { let schemaVersion: Int; let stations: [RadioStation] }
    private static let stations: [RadioStation] = {
        guard let url = Bundle.main.url(forResource: "radio_stations", withExtension: "json"),
              let data = try? Data(contentsOf: url), let registry = try? JSONDecoder().decode(Registry.self, from: data),
              registry.schemaVersion == 1 else { return [] }
        return registry.stations
    }()
    private static let byID = Dictionary(uniqueKeysWithValues: stations.map { ($0.id, $0) })
    private static let insecureHosts: Set<String> = Set(stations.flatMap { [$0.url] + $0.alternates }.compactMap {
        guard let url = URL(string: $0), url.scheme == "http" else { return nil }
        return url.host
    })
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "ko_KR"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
    // Keep decimal points in frequencies so 107.7 never matches a different number.
    private static let frequencyPattern = try! NSRegularExpression(
        pattern: #"(?<![a-z0-9.])(?:(fm|am)\s*)?([0-9]{2,4}(?:\.[0-9]+)?)(?:\s*(mhz|khz))?(?![a-z0-9.])"#
    )

    static func search(_ query: String) throws -> [ListeningItem] {
        guard !stations.isEmpty else { throw URLError(.cannotDecodeContentData) }
        let input = query.precomposedStringWithCompatibilityMapping.lowercased()
        let range = NSRange(input.startIndex..., in: input)
        let frequencyTerms = frequencyPattern.matches(in: input, range: range).compactMap { match -> (Double, String, String)? in
            func group(_ index: Int) -> String {
                Range(match.range(at: index), in: input).map { String(input[$0]) } ?? ""
            }
            guard let value = Double(group(2)) else { return nil }
            return (value, group(1), group(3))
        }
        let text = frequencyPattern.stringByReplacingMatches(in: input, range: range, withTemplate: " ")
        let terms = text.split(whereSeparator: \.isWhitespace).map { normalized(String($0)) }.filter { !$0.isEmpty }
        return stations.filter { station in
            let target = normalized(([station.title, station.subtitle] + station.aliases).joined(separator: " "))
            return terms.allSatisfy { target.contains($0) } && frequencyTerms.allSatisfy { value, band, unit in
                (station.frequencies ?? []).contains { frequency in
                    let fm = frequency.contains(".")
                    return Double(frequency) == value
                        && (band.isEmpty || band == (fm ? "fm" : "am"))
                        && (unit.isEmpty || unit == (fm ? "mhz" : "khz"))
                }
            }
        }.map(\.item)
    }
    static func canonical(_ item: ListeningItem) -> ListeningItem {
        guard item.kind == "radio" else { return item }
        if let station = byID[item.id] { return station.item }
        let name = normalized(item.title)
        return stations.first { $0.legacyNames.contains { normalized($0) == name } }?.item ?? item
    }
    static func adjacent(_ item: ListeningItem, direction: Int) -> ListeningItem? {
        guard let station = byID[canonical(item).id] else { return nil }
        let region = station.subtitle.components(separatedBy: " · ").first
        func frequency(_ station: RadioStation) -> Double {
            let values = station.frequencies ?? []
            return values.filter { $0.contains(".") }.compactMap(Double.init).min()
                ?? values.compactMap(Double.init).min().map { 1000 + $0 } ?? .greatestFiniteMagnitude
        }
        let rows = stations.filter { $0.subtitle.components(separatedBy: " · ").first == region }.sorted {
            let a = frequency($0), b = frequency($1)
            return a == b ? $0.id < $1.id : a < b
        }
        guard rows.count > 1, let index = rows.firstIndex(where: { $0.id == station.id }) else { return nil }
        return rows[(index + direction + rows.count) % rows.count].item
    }
    static func playbackURL(_ value: String) -> URL? {
        guard let url = URL(string: value), let host = url.host, url.user == nil, url.password == nil,
              url.scheme == "https" || (url.scheme == "http" && insecureHosts.contains(host)) else { return nil }
        return url
    }
    static func resolve(_ original: ListeningItem) async throws -> URL {
        let item = canonical(original)
        guard item.kind == "radio" else {
            guard let url = ListeningCatalog.webURL(item.url) else { throw URLError(.badURL) }
            return url
        }
        guard let station = byID[item.id] else {
            // Keep pre-registry favorites usable, without reintroducing the old directory as the main list.
            if UUID(uuidString: item.id) != nil,
               let endpoint = URL(string: "https://de1.api.radio-browser.info/json/stations/byuuid/\(item.id)"),
               let rows = try? JSONSerialization.jsonObject(with: await ListeningCatalog.data(endpoint)) as? [[String: Any]],
               let value = rows.first?["url"] as? String, let url = ListeningCatalog.webURL(value) { return url }
            guard let url = ListeningCatalog.webURL(item.url) else { throw URLError(.badURL) }
            return url
        }
        try Task.checkCancellation()
        switch station.resolver {
        case "kbs":
            let data = try await metadata(station.url)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = root["channel_item"] as? [[String: Any]],
                  let row = rows.first(where: { ["radio", "local"].contains($0["media_type"] as? String ?? "") }),
                  let value = row["service_url"] as? String, let url = playbackURL(value) else { throw URLError(.cannotParseResponse) }
            return url
        case "plain":
            let data = try await metadata(station.url)
            guard let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = playbackURL(value) else { throw URLError(.cannotParseResponse) }
            return url
        case "ebs":
            do {
                let data = try await metadata(station.url)
                let html = String(decoding: data, as: UTF8.self)
                let pattern = #"src:\s*'(https://liveotu\.ebs\.co\.kr/[^']+)'"#
                if let match = try NSRegularExpression(pattern: pattern).firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                   let range = Range(match.range(at: 1), in: html),
                   let url = playbackURL(String(html[range]).replacingOccurrences(of: "&amp;", with: "&")) { return url }
            } catch { if Task.isCancelled { throw CancellationError() } }
            return try await direct(station.alternates)
        case "busan":
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
            formatter.dateFormat = "yyMMdd"
            let letters = Array("qhsagbjcpd")
            let stamp = formatter.string(from: Date()).compactMap { $0.wholeNumberValue }.map { String(letters[$0]) }.joined()
            guard let url = playbackURL(station.url.replacingOccurrences(of: "{date}", with: stamp)) else { throw URLError(.badURL) }
            return url
        case "afn":
            do {
                let data = try await metadata(station.url)
                let xml = String(decoding: data, as: UTF8.self)
                let regex = try NSRegularExpression(pattern: "<ip>([a-zA-Z0-9.-]+)</ip>")
                let hosts = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { match -> String? in
                    guard let range = Range(match.range(at: 1), in: xml) else { return nil }
                    let host = String(xml[range])
                    return host.hasSuffix(".live.streamtheworld.com") ? host : nil
                }
                let channel = URLComponents(string: station.url)?.queryItems?.first(where: { $0.name == "station" })?.value ?? ""
                if let host = hosts.last, channel.hasPrefix("AFNP_"), let url = playbackURL("https://\(host)/\(channel)AAC.aac") { return url }
            } catch { if Task.isCancelled { throw CancellationError() } }
            return try await direct(station.alternates)
        default: return try await direct([station.url] + station.alternates)
        }
    }
    private static func metadata(_ value: String) async throws -> Data {
        guard let url = ListeningCatalog.webURL(value) else { throw URLError(.badURL) }
        return try await ListeningCatalog.data(url)
    }
    private static func direct(_ candidates: [String]) async throws -> URL {
        var failure: Error = URLError(.badURL)
        for candidate in candidates {
            try Task.checkCancellation()
            guard let url = playbackURL(candidate) else { continue }
            // Only bounded HTTPS playlists are probed; continuous streams are left to the player.
            if url.scheme == "https", url.path.lowercased().hasSuffix(".m3u8") {
                do {
                    let bytes = try await ListeningCatalog.data(url)
                    guard String(decoding: bytes.prefix(32), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") else { throw URLError(.cannotParseResponse) }
                    return url
                } catch { if Task.isCancelled { throw CancellationError() }; failure = error }
            } else { return url }
        }
        throw failure
    }
}
