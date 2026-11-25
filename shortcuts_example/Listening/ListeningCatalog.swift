import Foundation

nonisolated struct ListeningChapter: Codable, Equatable, Sendable {
    let title: String
    let start: Double
}

nonisolated struct ListeningItem: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let url: String
    let kind: String
    var artworkURL: String? = nil
    var feedURL: String? = nil
    var chapters: [ListeningChapter]? = nil
    var chaptersURL: String? = nil
}

nonisolated enum ListeningCatalog {
    static func webURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme?.lowercased() == "https",
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func audioURL(_ value: String) -> String? {
        if webURL(value) != nil { return value }
        guard var parts = URLComponents(string: value), parts.scheme?.lowercased() == "http",
              parts.host?.lowercased() == "podcastdown.sbs.co.kr", parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 80 else { return nil }
        parts.scheme = "https"; parts.host = "podcastdown.sbs.co.kr"; parts.port = nil
        return parts.url?.absoluteString
    }

    @concurrent static func data(_ url: URL, session: URLSession = .shared, allowPrefix: Bool = false) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("RivoListening/1.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        defer { if allowPrefix { bytes.task.cancel() } }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let finalURL = response.url, webURL(finalURL.absoluteString) != nil else { throw URLError(.badServerResponse) }
        var result = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            if result.count >= 4 * 1024 * 1024 {
                if allowPrefix { break }
                throw URLError(.dataLengthExceedsMaximum)
            }
            result.append(byte)
        }
        return result
    }

    @concurrent static func popularPodcasts() async throws -> [ListeningItem] {
        let chart = try JSONSerialization.jsonObject(with: await data(URL(string: "https://itunes.apple.com/kr/rss/toppodcasts/limit=10/json")!)) as? [String: Any]
        guard let feed = chart?["feed"] as? [String: Any], let entries = feed["entry"] as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        let ids = entries.compactMap { entry -> String? in
            let id = entry["id"] as? [String: Any]
            let attributes = id?["attributes"] as? [String: Any]
            return attributes?["im:id"] as? String
        }
        guard !ids.isEmpty else { return [] }
        try Task.checkCancellation()
        var parts = URLComponents(string: "https://itunes.apple.com/lookup")!
        parts.queryItems = [URLQueryItem(name: "id", value: ids.joined(separator: ",")),
                            URLQueryItem(name: "entity", value: "podcast"), URLQueryItem(name: "country", value: "KR")]
        let root = try JSONSerialization.jsonObject(with: await data(parts.url!)) as? [String: Any]
        guard let rows = root?["results"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        // Lookup order is not guaranteed; retain the chart order after filtering unsupported feeds.
        return podcastItems(ids.compactMap { id in rows.first { ($0["collectionId"] as? NSNumber)?.stringValue == id } })
    }

    @concurrent static func podcasts(_ query: String) async throws -> [ListeningItem] {
        if let url = webURL(query) {
            // A direct RSS feed works without a directory account.
            let parser = ListeningFeedParser()
            let xml = try await data(url, allowPrefix: true)
            _ = try parser.read(xml)
            return [ListeningItem(id: url.absoluteString, title: parser.channelTitle.isEmpty ? url.host! : parser.channelTitle,
                                  subtitle: url.host!, url: url.absoluteString, kind: "podcast", artworkURL: parser.channelArtwork)]
        }
        var parts = URLComponents(string: "https://itunes.apple.com/search")!
        parts.queryItems = [URLQueryItem(name: "term", value: query), URLQueryItem(name: "entity", value: "podcast"),
                            URLQueryItem(name: "country", value: "KR"), URLQueryItem(name: "limit", value: "40")]
        let root = try JSONSerialization.jsonObject(with: await data(parts.url!)) as? [String: Any]
        return podcastItems(root?["results"] as? [[String: Any]] ?? [])
    }

    private static func podcastItems(_ rows: [[String: Any]]) -> [ListeningItem] {
        var urls = Set<String>()
        return rows.compactMap { row in
            guard let url = row["feedUrl"] as? String, webURL(url) != nil, urls.insert(url).inserted,
                  let title = row["collectionName"] as? String else { return nil }
            return ListeningItem(id: url, title: title, subtitle: row["artistName"] as? String ?? "", url: url, kind: "podcast",
                                 artworkURL: row["artworkUrl600"] as? String ?? row["artworkUrl100"] as? String)
        }
    }

    @concurrent static func episodes(_ show: ListeningItem) async throws -> (show: ListeningItem, episodes: [ListeningItem]) {
        guard let url = webURL(show.url) else { throw URLError(.badURL) }
        let parser = ListeningFeedParser()
        let items = try parser.read(await data(url, allowPrefix: true))
        var updated = show
        updated.artworkURL = show.artworkURL ?? parser.channelArtwork
        let episodes = items.map {
            ListeningItem(id: $0.id, title: $0.title, subtitle: show.title, url: $0.url, kind: "episode",
                          artworkURL: $0.artworkURL ?? show.artworkURL, feedURL: show.url, chapters: $0.chapters, chaptersURL: $0.chaptersURL)
        }
        return (updated, episodes)
    }
    @concurrent static func chapters(_ item: ListeningItem) async throws -> [ListeningChapter] {
        guard let value = item.chaptersURL, let url = webURL(value) else { return [] }
        let root = try JSONSerialization.jsonObject(with: await data(url)) as? [String: Any]
        guard let rows = root?["chapters"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        var times = Set<Double>()
        return rows.compactMap { row -> ListeningChapter? in
            guard let start = (row["startTime"] as? NSNumber)?.doubleValue, start.isFinite, start >= 0, times.insert(start).inserted else { return nil }
            return ListeningChapter(title: row["title"] as? String ?? "", start: start)
        }.sorted { $0.start < $1.start }.prefix(200).map { $0 }
    }
}

/// RSS text is displayed as text; external entities and HTML are never loaded.
nonisolated final class ListeningFeedParser: NSObject, XMLParserDelegate {
    private var items: [ListeningItem] = []
    private var insideItem = false
    private var field = ""
    private var path: [String] = []
    private var title = ""
    private var enclosure = ""
    private var artwork: String?
    private var chapters: [ListeningChapter] = []
    private var chaptersURL: String?
    private var namespaces = ["psc": "http://podlove.org/simple-chapters", "podcast": "https://podcastindex.org/namespace/1.0"]
    private var channelImageText = ""
    private var reachedEpisodeLimit = false
    private(set) var channelTitle = ""
    private(set) var channelArtwork: String?
    func read(_ data: Data) throws -> [ListeningItem] {
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        guard parser.parse() || reachedEpisodeLimit else { throw parser.parserError ?? URLError(.cannotParseResponse) }
        if channelArtwork == nil, let url = ListeningCatalog.webURL(channelImageText.trimmingCharacters(in: .whitespacesAndNewlines)) { channelArtwork = url.absoluteString }
        return items.map { item in var copy = item; copy.artworkURL = item.artworkURL ?? channelArtwork; return copy }
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        field = name.lowercased()
        path.append(field)
        for (key, value) in attributes where key.hasPrefix("xmlns:") { namespaces[String(key.dropFirst(6)).lowercased()] = value }
        if field == "item" { insideItem = true; title = ""; enclosure = ""; artwork = nil; chapters = []; chaptersURL = nil }
        if field == "itunes:image", let value = attributes["href"], ListeningCatalog.webURL(value) != nil {
            if insideItem { artwork = value } else { channelArtwork = value }
        }
        if insideItem, matches(field, namespace: "http://podlove.org/simple-chapters", local: "chapter"),
           let value = attributes["start"], let start = Self.chapterTime(value), chapters.count < 200 {
            chapters.append(ListeningChapter(title: attributes["title"] ?? "", start: start))
        }
        if insideItem, matches(field, namespace: "https://podcastindex.org/namespace/1.0", local: "chapters"),
           ["application/json+chapters", "application/json"].contains(attributes["type"] ?? ""),
           let value = attributes["url"], ListeningCatalog.webURL(value) != nil { chaptersURL = value }
        if insideItem && field == "enclosure", let value = attributes["url"], let secure = ListeningCatalog.audioURL(value),
           attributes["type"]?.hasPrefix("audio/") != false { enclosure = secure }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if field == "title" {
            if insideItem { title += string } else if path.suffix(2) == ["channel", "title"] { channelTitle += string }
        }
        if !insideItem, path.suffix(3) == ["channel", "image", "url"] {
            channelImageText += string
        }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) { self.parser(parser, foundCharacters: text) }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name.lowercased() == "item" {
            if !enclosure.isEmpty, !items.contains(where: { $0.url == enclosure }), items.count < 100 {
                items.append(ListeningItem(id: enclosure, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                           subtitle: "", url: enclosure, kind: "episode", artworkURL: artwork,
                                           chapters: chapters.sorted { $0.start < $1.start }, chaptersURL: chaptersURL))
            }
            insideItem = false
            if items.count >= 100 { reachedEpisodeLimit = true; parser.abortParsing() }
        }
        if !path.isEmpty { path.removeLast() }
        field = path.last ?? ""
    }
    private static func chapterTime(_ value: String) -> Double? {
        let parts = value.split(separator: ":").compactMap { Double($0) }
        guard (1...3).contains(parts.count), parts.count == value.split(separator: ":").count,
              parts.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        let result = parts.reduce(0) { $0 * 60 + $1 }
        return result.isFinite ? result : nil
    }
    private func matches(_ field: String, namespace: String, local: String) -> Bool {
        let parts = field.split(separator: ":", maxSplits: 1).map(String.init)
        return parts.count == 2 && namespaces[parts[0]] == namespace && parts[1] == local
    }
}
