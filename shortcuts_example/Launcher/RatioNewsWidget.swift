import SwiftUI
import Foundation
import CoreFoundation
import Combine
import UIKit

private nonisolated enum NewsCategory: String, CaseIterable, Sendable {
    case latest = "sokbo", society, economy, culture, politics, world, technology, health, sports, entertainment
    static var topics: [Self] { allCases.filter { $0 != .latest } }
    var title: String { switch self {
        case .latest: "최신"; case .society: "사회"; case .economy: "경제"; case .culture: "문화"
        case .politics: "정치"; case .world: "국제"; case .technology: "IT·과학"; case .health: "건강"
        case .sports: "스포츠"; case .entertainment: "연예"
    } }
}
// Generated from docs/news_publishers.json by tools/generate_news_sources.py.
private nonisolated enum NewsSource: String, CaseIterable, Codable, Sendable {
    case newsis, sbs, khan, donga, etoday, ohmy, kmib, straight, itdonga, bloter, etnews, zdnet, kormedi, techm, greenpostkorea, koscaj, e2news, todayenergy, housingherald, ebn, newscape, mt, metroseoul, viva100, seoulfn, asiae, chosun_biz, joseilbo, newsprime, labortoday, lawtimes, veritas_a, hangyo, newsfc, kbanker, fins, insjournal, ftoday, insnews, aflnews, ikpnews, mbn, tvchosun, sportschosun, tenasia, rapportian, doctorsnews, docdocdoc, pharmnews, hitnews, nocutnews, dailynk, mediaus, mediatoday, sisaweek, sisajournal, polinews, pressian, journalist, motorgraph, autoherald, seoul, segye, chosun, kado, idomin, daejonilbo, incheonilbo, jnilbo, jjan, jejunews, cctoday, ihalla, yna
    var title: String { switch self {
        case .newsis: "뉴시스"
        case .sbs: "SBS"
        case .khan: "경향신문"
        case .donga: "동아일보"
        case .etoday: "이투데이"
        case .ohmy: "오마이뉴스"
        case .kmib: "국민일보"
        case .straight: "스트레이트뉴스"
        case .itdonga: "IT동아"
        case .bloter: "블로터"
        case .etnews: "전자신문"
        case .zdnet: "지디넷코리아"
        case .kormedi: "코메디닷컴"
        case .techm: "테크M"
        case .greenpostkorea: "그린포스트코리아"
        case .koscaj: "대한전문건설신문"
        case .e2news: "이투뉴스"
        case .todayenergy: "투데이에너지"
        case .housingherald: "하우징헤럴드"
        case .ebn: "EBN"
        case .newscape: "뉴스케이프"
        case .mt: "머니투데이"
        case .metroseoul: "메트로"
        case .viva100: "브릿지경제"
        case .seoulfn: "서울파이낸스"
        case .asiae: "아시아경제"
        case .chosun_biz: "조선비즈"
        case .joseilbo: "조세일보"
        case .newsprime: "프라임경제"
        case .labortoday: "매일노동뉴스"
        case .lawtimes: "법률신문"
        case .veritas_a: "베리타스알파"
        case .hangyo: "한국교육신문"
        case .newsfc: "금융소비자뉴스"
        case .kbanker: "대한금융신문"
        case .fins: "보험매일"
        case .insjournal: "보험저널"
        case .ftoday: "파이낸셜투데이"
        case .insnews: "한국보험신문"
        case .aflnews: "농수축산신문"
        case .ikpnews: "한국농정신문"
        case .mbn: "MBN"
        case .tvchosun: "TV조선"
        case .sportschosun: "스포츠조선"
        case .tenasia: "텐아시아"
        case .rapportian: "라포르시안"
        case .doctorsnews: "의협신문"
        case .docdocdoc: "청년의사"
        case .pharmnews: "팜뉴스"
        case .hitnews: "히트뉴스"
        case .nocutnews: "노컷뉴스"
        case .dailynk: "데일리NK"
        case .mediaus: "미디어스"
        case .mediatoday: "미디어오늘"
        case .sisaweek: "시사위크"
        case .sisajournal: "시사저널"
        case .polinews: "폴리뉴스"
        case .pressian: "프레시안"
        case .journalist: "한국기자협회"
        case .motorgraph: "모터그래프"
        case .autoherald: "오토헤럴드"
        case .seoul: "서울신문"
        case .segye: "세계일보"
        case .chosun: "조선일보"
        case .kado: "강원도민일보"
        case .idomin: "경남도민일보"
        case .daejonilbo: "대전일보"
        case .incheonilbo: "인천일보"
        case .jnilbo: "전남일보"
        case .jjan: "전북일보"
        case .jejunews: "제주일보"
        case .cctoday: "충청투데이"
        case .ihalla: "한라일보"
        case .yna: "연합뉴스"
    } }
    private var domains: [String] { switch self {
        case .newsis: ["newsis.com"]
        case .sbs: ["sbs.co.kr"]
        case .khan: ["khan.co.kr"]
        case .donga: ["donga.com"]
        case .etoday: ["etoday.co.kr"]
        case .ohmy: ["ohmynews.com"]
        case .kmib: ["kmib.co.kr"]
        case .straight: ["straightnews.co.kr"]
        case .itdonga: ["donga.com"]
        case .bloter: ["bloter.net"]
        case .etnews: ["etnews.com"]
        case .zdnet: ["zdnet.co.kr"]
        case .kormedi: ["kormedi.com"]
        case .techm: ["techm.kr"]
        case .greenpostkorea: ["greenpostkorea.co.kr"]
        case .koscaj: ["koscaj.com"]
        case .e2news: ["e2news.com"]
        case .todayenergy: ["todayenergy.kr"]
        case .housingherald: ["housingherald.co.kr"]
        case .ebn: ["ebn.co.kr"]
        case .newscape: ["newscape.co.kr"]
        case .mt: ["mt.co.kr"]
        case .metroseoul: ["metroseoul.co.kr"]
        case .viva100: ["viva100.com"]
        case .seoulfn: ["seoulfn.com"]
        case .asiae: ["asiae.co.kr"]
        case .chosun_biz: ["chosun.com"]
        case .joseilbo: ["joseilbo.com"]
        case .newsprime: ["newsprime.co.kr"]
        case .labortoday: ["labortoday.co.kr"]
        case .lawtimes: ["lawtimes.co.kr"]
        case .veritas_a: ["veritas-a.com"]
        case .hangyo: ["hangyo.com"]
        case .newsfc: ["newsfc.co.kr"]
        case .kbanker: ["kbanker.co.kr"]
        case .fins: ["fins.co.kr"]
        case .insjournal: ["insjournal.co.kr"]
        case .ftoday: ["ftoday.co.kr"]
        case .insnews: ["insnews.co.kr"]
        case .aflnews: ["aflnews.co.kr"]
        case .ikpnews: ["ikpnews.net"]
        case .mbn: ["mbn.co.kr"]
        case .tvchosun: ["tvchosun.com"]
        case .sportschosun: ["sportschosun.com"]
        case .tenasia: ["tenasia.co.kr"]
        case .rapportian: ["rapportian.com"]
        case .doctorsnews: ["doctorsnews.co.kr"]
        case .docdocdoc: ["docdocdoc.co.kr"]
        case .pharmnews: ["pharmnews.com"]
        case .hitnews: ["hitnews.co.kr"]
        case .nocutnews: ["nocutnews.co.kr"]
        case .dailynk: ["dailynk.com"]
        case .mediaus: ["mediaus.co.kr"]
        case .mediatoday: ["mediatoday.co.kr"]
        case .sisaweek: ["sisaweek.com"]
        case .sisajournal: ["sisajournal.com"]
        case .polinews: ["polinews.co.kr"]
        case .pressian: ["pressian.com"]
        case .journalist: ["journalist.or.kr"]
        case .motorgraph: ["motorgraph.com"]
        case .autoherald: ["autoherald.co.kr"]
        case .seoul: ["seoul.co.kr"]
        case .segye: ["segye.com"]
        case .chosun: ["chosun.com"]
        case .kado: ["kado.net"]
        case .idomin: ["idomin.com"]
        case .daejonilbo: ["daejonilbo.com"]
        case .incheonilbo: ["incheonilbo.com"]
        case .jnilbo: ["jnilbo.com"]
        case .jjan: ["jjan.kr"]
        case .jejunews: ["jejunews.com"]
        case .cctoday: ["cctoday.co.kr"]
        case .ihalla: ["ihalla.com"]
        case .yna: ["yna.co.kr"]
    } }
    private var feeds: [String: String] { switch self {
        case .newsis: ["sokbo": "https://www.newsis.com/RSS/sokbo.xml", "society": "https://www.newsis.com/RSS/society.xml", "economy": "https://www.newsis.com/RSS/economy.xml", "culture": "https://www.newsis.com/RSS/culture.xml", "politics": "https://www.newsis.com/RSS/politics.xml", "world": "https://www.newsis.com/RSS/international.xml", "technology": "https://www.newsis.com/RSS/health.xml", "sports": "https://www.newsis.com/RSS/sports.xml", "entertainment": "https://www.newsis.com/RSS/entertain.xml"]
        case .sbs: ["sokbo": "https://news.sbs.co.kr/news/newsflashRssFeed.do?plink=RSSREADER", "society": "https://news.sbs.co.kr/news/SectionRssFeed.do?sectionId=03&plink=RSSREADER", "economy": "https://news.sbs.co.kr/news/SectionRssFeed.do?sectionId=02&plink=RSSREADER", "culture": "https://news.sbs.co.kr/news/SectionRssFeed.do?sectionId=08&plink=RSSREADER", "politics": "https://news.sbs.co.kr/news/SectionRssFeed.do?sectionId=01&plink=RSSREADER", "world": "https://news.sbs.co.kr/news/SectionRssFeed.do?sectionId=07&plink=RSSREADER", "sports": "https://news.sbs.co.kr/news/SectionRssFeed.do?sectionId=09&plink=RSSREADER", "entertainment": "https://news.sbs.co.kr/news/SectionRssFeed.do?sectionId=14&plink=RSSREADER"]
        case .khan: ["sokbo": "https://www.khan.co.kr/rss/rssdata/total_news.xml", "society": "https://www.khan.co.kr/rss/rssdata/society_news.xml", "economy": "https://www.khan.co.kr/rss/rssdata/economy_news.xml", "culture": "https://www.khan.co.kr/rss/rssdata/culture_news.xml"]
        case .donga: ["sokbo": "https://rss.donga.com/total.xml", "society": "https://rss.donga.com/national.xml", "economy": "https://rss.donga.com/economy.xml", "culture": "https://rss.donga.com/culture.xml", "politics": "https://rss.donga.com/politics.xml", "world": "https://rss.donga.com/international.xml", "health": "https://rss.donga.com/health.xml", "sports": "https://rss.donga.com/sports.xml", "technology": "https://rss.donga.com/science.xml"]
        case .etoday: ["sokbo": "https://rss.etoday.co.kr/eto/etoday_news_all.xml", "society": "https://rss.etoday.co.kr/eto/society_news.xml", "economy": "https://rss.etoday.co.kr/eto/economy_news.xml", "culture": "https://rss.etoday.co.kr/eto/culture-life_news.xml"]
        case .ohmy: ["sokbo": "https://rss.ohmynews.com/rss/ohmynews.xml", "society": "https://rss.ohmynews.com/rss/society.xml", "economy": "https://rss.ohmynews.com/rss/economy.xml", "culture": "https://rss.ohmynews.com/rss/culture.xml"]
        case .kmib: ["sokbo": "https://www.kmib.co.kr/rss/data/kmibRssAll.xml", "society": "https://www.kmib.co.kr/rss/data/kmibSocRss.xml", "economy": "https://www.kmib.co.kr/rss/data/kmibEcoRss.xml", "culture": "https://www.kmib.co.kr/rss/data/kmibLifeRss.xml"]
        case .straight: ["sokbo": "https://www.straightnews.co.kr/rss/allArticle.xml", "society": "https://www.straightnews.co.kr/rss/S1N15.xml", "economy": "https://www.straightnews.co.kr/rss/S1N14.xml", "culture": "https://www.straightnews.co.kr/rss/S1N17.xml"]
        case .itdonga: ["sokbo": "https://it.donga.com/feeds/rss/"]
        case .bloter: ["sokbo": "https://cdn.bloter.net/rss/gns_allArticle.xml"]
        case .etnews: ["sokbo": "https://rss.etnews.com/Section901.xml"]
        case .zdnet: ["sokbo": "https://feeds.feedburner.com/zdkorea"]
        case .kormedi: ["sokbo": "https://kormedi.com/feed/"]
        case .techm: ["sokbo": "https://www.techm.kr/rss/allArticle.xml"]
        case .greenpostkorea: ["sokbo": "https://www.greenpostkorea.co.kr/rss/allArticle.xml"]
        case .koscaj: ["sokbo": "https://www.koscaj.com/rss/allArticle.xml"]
        case .e2news: ["sokbo": "https://www.e2news.com/rss/allArticle.xml"]
        case .todayenergy: ["sokbo": "https://www.todayenergy.kr/rss/allArticle.xml"]
        case .housingherald: ["sokbo": "https://www.housingherald.co.kr/rss/allArticle.xml"]
        case .ebn: ["sokbo": "https://cdn.ebn.co.kr/rss/gns_allArticle.xml"]
        case .newscape: ["sokbo": "https://www.newscape.co.kr/rss/allArticle.xml"]
        case .mt: ["sokbo": "https://rss.mt.co.kr/mt_news.xml"]
        case .metroseoul: ["sokbo": "https://www.metroseoul.co.kr/news/rss"]
        case .viva100: ["sokbo": "https://www.viva100.com/rssAll.xml"]
        case .seoulfn: ["sokbo": "https://cdn.seoulfn.com/rss/gn_rss_allArticle.xml"]
        case .asiae: ["sokbo": "https://view.asiae.co.kr/rss/all.htm"]
        case .chosun_biz: ["sokbo": "https://biz.chosun.com/arc/outboundfeeds/rss/?outputType=xml"]
        case .joseilbo: ["sokbo": "https://www.joseilbo.com/Contents/rss/rss_total.php"]
        case .newsprime: ["sokbo": "https://www.newsprime.co.kr/data/rss/news.xml"]
        case .labortoday: ["sokbo": "https://www.labortoday.co.kr/rss/allArticle.xml"]
        case .lawtimes: ["sokbo": "https://cdn.lawtimes.co.kr/rss/gn_rss_allArticle.xml"]
        case .veritas_a: ["sokbo": "https://www.veritas-a.com/rss/allArticle.xml"]
        case .hangyo: ["sokbo": "https://www.hangyo.com/data/rss/news.xml"]
        case .newsfc: ["sokbo": "https://www.newsfc.co.kr/rss/allArticle.xml"]
        case .kbanker: ["sokbo": "https://www.kbanker.co.kr/rss/allArticle.xml"]
        case .fins: ["sokbo": "https://www.fins.co.kr/rss/allArticle.xml"]
        case .insjournal: ["sokbo": "https://www.insjournal.co.kr/rss/allArticle.xml"]
        case .ftoday: ["sokbo": "https://www.ftoday.co.kr/rss/allArticle.xml"]
        case .insnews: ["sokbo": "https://www.insnews.co.kr/rss/allArticle.xml"]
        case .aflnews: ["sokbo": "https://www.aflnews.co.kr/rss/allArticle.xml"]
        case .ikpnews: ["sokbo": "https://www.ikpnews.net/rss/allArticle.xml"]
        case .mbn: ["sokbo": "https://www.mbn.co.kr/rss/politics/"]
        case .tvchosun: ["sokbo": "https://news.tvchosun.com/site/data/rss/rss.xml"]
        case .sportschosun: ["sokbo": "https://www.sportschosun.com/rss/index_all.htm"]
        case .tenasia: ["sokbo": "https://www.tenasia.co.kr/rss/music/"]
        case .rapportian: ["sokbo": "https://www.rapportian.com/rss/allArticle.xml"]
        case .doctorsnews: ["sokbo": "https://www.doctorsnews.co.kr/rss/allArticle.xml"]
        case .docdocdoc: ["sokbo": "https://www.docdocdoc.co.kr/rss/allArticle.xml"]
        case .pharmnews: ["sokbo": "https://www.pharmnews.com/rss/allArticle.xml"]
        case .hitnews: ["sokbo": "https://www.hitnews.co.kr/rss/allArticle.xml"]
        case .nocutnews: ["sokbo": "https://rss.nocutnews.co.kr/news/news.xml"]
        case .dailynk: ["sokbo": "https://www.dailynk.com/feed/"]
        case .mediaus: ["sokbo": "https://www.mediaus.co.kr/rss/allArticle.xml"]
        case .mediatoday: ["sokbo": "https://www.mediatoday.co.kr/rss/allArticle.xml"]
        case .sisaweek: ["sokbo": "https://www.sisaweek.com/rss/allArticle.xml"]
        case .sisajournal: ["sokbo": "https://www.sisajournal.com/rss/allArticle.xml"]
        case .polinews: ["sokbo": "https://www.polinews.co.kr/rss/allArticle.xml"]
        case .pressian: ["sokbo": "https://www.pressian.com/api/v3/site/rss/news"]
        case .journalist: ["sokbo": "https://www.journalist.or.kr/data/rss/news.xml"]
        case .motorgraph: ["sokbo": "https://www.motorgraph.com/rss/allArticle.xml"]
        case .autoherald: ["sokbo": "https://www.autoherald.co.kr/rss/allArticle.xml"]
        case .seoul: ["sokbo": "https://www.seoul.co.kr/xml/rss/google_plan.xml"]
        case .segye: ["sokbo": "https://www.segye.com/Articles/RSSList/segye_recent.xml"]
        case .chosun: ["sokbo": "https://www.chosun.com/arc/outboundfeeds/rss/?outputType=xml"]
        case .kado: ["sokbo": "https://www.kado.net/rss/allArticle.xml"]
        case .idomin: ["sokbo": "https://www.idomin.com/rss/allArticle.xml"]
        case .daejonilbo: ["sokbo": "https://www.daejonilbo.com/rss/allArticle.xml"]
        case .incheonilbo: ["sokbo": "https://www.incheonilbo.com/rss/allArticle.xml"]
        case .jnilbo: ["sokbo": "https://cdn.jnilbo.com/rss/gn_rss_allArticle.xml"]
        case .jjan: ["sokbo": "https://www.jjan.kr/news/rssAll"]
        case .jejunews: ["sokbo": "https://www.jejunews.com/rss/allArticle.xml"]
        case .cctoday: ["sokbo": "https://www.cctoday.co.kr/rss/allArticle.xml"]
        case .ihalla: ["sokbo": "https://www.ihalla.com/rss.php?section=73"]
        case .yna: ["sokbo": "https://www.yna.co.kr/rss/news.xml"]
    } }
    func accepts(_ value: String) -> Bool {
        guard let url = URL(string: value), url.scheme == "https", url.user == nil, let host = url.host?.lowercased() else { return false }
        return domains.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
    func articleURL(_ value: String) -> String? {
        guard var url = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "&amp;", with: "&")) else { return nil }
        if url.scheme == "http" { url.scheme = "https" }
        guard let candidate = url.string, accepts(candidate) else { return nil }
        return candidate
    }
    func feed(_ category: NewsCategory) -> URL? { feeds[category.rawValue].flatMap { URL(string: $0) } }
    static func available(_ category: NewsCategory) -> [NewsSource] { allCases.filter { $0.feed(category) != nil } }
}
private nonisolated struct NewsArticle: Codable, Equatable, Identifiable, Sendable {
    var title: String
    var url: String
    var summary: String
    var published: Date?
    var source: NewsSource
    var id: String { url }
}
private nonisolated struct NewsSnapshot: Codable, Sendable {
    var items: [NewsArticle]
    var fetched: Date
    var sourceFetched: [String: Date]
    var partial: Bool
}

/// Parses only RSS metadata, caps summaries, and rejects document/entity declarations.
private nonisolated final class NewsRSSParser: NSObject, XMLParserDelegate {
    var items: [NewsArticle] = []
    private var fields: [String: String]?
    private var field: String?
    private var buffer = ""
    static let maxPerSource = 15
    static let maxItems = 1200
    static let maxCandidates = 30
    static let maxConcurrent = 3
    private let dates: [DateFormatter] = ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss z", "yyyy-MM-dd HH:mm:ss"].map { pattern in
        let value = DateFormatter(); value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = TimeZone(identifier: "Asia/Seoul"); value.dateFormat = pattern; value.isLenient = false; return value
    }
    private let source: NewsSource
    private let iso = ISO8601DateFormatter()
    private let isoFractional: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return value
    }()
    private func publishedDate(_ value: String) -> Date? {
        let text = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: ",\\s*", with: ", ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return iso.date(from: text) ?? isoFractional.date(from: text) ?? dates.lazy.compactMap { $0.date(from: text) }.first
    }
    init(source: NewsSource) { self.source = source; super.init() }
    static func clean(_ value: String) -> String {
        var text = String(value.prefix(12_000))
        let entities = ["amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">", "nbsp": " ",
            "ndash": "–", "mdash": "—", "hellip": "…", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "middot": "·", "copy": "©"]
        let pattern = try? NSRegularExpression(pattern: "&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|[a-zA-Z]+);")
        for _ in 0..<6 {
            let previous = text
            // Strip active blocks before tags, decode entities, then strip again on the next pass.
            text = text.replacingOccurrences(of: "(?is)<(script|style)\\b[^>]*>.*?</\\1\\s*>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "(?is)<\\s*/?\\s*[a-z!][^>]*(?:>|$)", with: " ", options: .regularExpression)
            if let pattern {
                let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
                for match in matches.reversed() {
                    guard let range = Range(match.range(at: 1), in: text), let full = Range(match.range, in: text) else { continue }
                    let key = String(text[range])
                    var replacement = entities[key]
                    if key.hasPrefix("#") {
                        let hex = key.lowercased().hasPrefix("#x")
                        if let code = UInt32(key.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10), let scalar = UnicodeScalar(code) {
                            replacement = String(scalar)
                        }
                    }
                    if let replacement { text.replaceSubrange(full, with: replacement) }
                }
            }
            if text == previous { break }
        }
        return text.replacingOccurrences(of: "(?is)<\\s*/?\\s*[a-z!][^>]*(?:>|$)", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\u{FFFC}", with: " ")
            .replacingOccurrences(of: "[\\s\\u00a0]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if element == "item" { fields = [:] }
        else if fields != nil && ["title", "link", "guid", "description", "pubDate", "dc:date"].contains(element) { field = element; buffer = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if field != nil && buffer.count < 12_000 { buffer += String(string.prefix(12_000 - buffer.count)) } }
    func parser(_ parser: XMLParser, foundCDATA block: Data) { if let text = String(data: block, encoding: .utf8) { self.parser(parser, foundCharacters: text) } }
    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if field == element { fields?[element] = buffer; field = nil; buffer = "" }
        if element == "item", let values = fields {
            let title = String(Self.clean(values["title"] ?? "").prefix(240))
            let guid = (values["guid"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let url = source.articleURL(guid) ?? source.articleURL(values["link"] ?? "") ?? ""
            var summary = Self.clean(values["description"] ?? "")
            for marker in ["◎", "ⓒ", "©"] { summary = String(summary.components(separatedBy: marker).first ?? "") }
            summary = summary.replacingOccurrences(of: "^\\[[^]]+\\]\\s*.{0,60}?기자\\s*=\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            if summary == title || summary.hasPrefix("후속기사가 이어집니다") { summary = "" }
            if summary.count > 160 { summary = String(summary.prefix(160)) + "…" }
            let published = publishedDate(values["pubDate"] ?? "") ?? publishedDate(values["dc:date"] ?? "")
            if !title.isEmpty && source.accepts(url) {
                items.append(NewsArticle(title: title, url: url, summary: summary, published: published.map { min($0, .now) }, source: source))
            }
            fields = nil
        }
    }
    static func parse(_ data: Data, source: NewsSource) throws -> [NewsArticle] {
        let scan = String(decoding: data, as: UTF8.self)
        guard !scan.contains("<!DOCTYPE"), !scan.contains("<!ENTITY") else { throw URLError(.cannotParseResponse) }
        var payload = data
        let header = String(scan.prefix(200)).lowercased()
        if header.contains("euc-kr") || header.contains("ks_c_5601") || header.contains("windows-949") {
            let encoding = CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding("euc-kr" as CFString))
            guard let text = String(data: data, encoding: String.Encoding(rawValue: encoding)) else { throw URLError(.cannotDecodeContentData) }
            payload = Data(text.replacingOccurrences(of: "encoding=[\"'][^\"']+[\"']", with: "encoding=\"utf-8\"", options: .regularExpression).utf8)
        }
        let delegate = NewsRSSParser(source: source), parser = XMLParser(data: payload)
        parser.delegate = delegate; parser.shouldResolveExternalEntities = false
        guard parser.parse(), !delegate.items.isEmpty else { throw URLError(.cannotParseResponse) }
        var urls = Set<String>()
        return Array(delegate.items.sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
            .filter { urls.insert($0.url).inserted }.prefix(maxCandidates))
    }
    private static func titleKey(_ title: String) -> String {
        title.replacingOccurrences(of: "\\[[^]]{1,20}\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[\\s\\p{P}\\p{S}]+", with: "", options: .regularExpression).lowercased()
    }
    private struct TitleSignature {
        var text: String
        var numbers: [String]
        var pairs: Set<String>
    }
    private static let numberPattern = try! NSRegularExpression(pattern: "\\d+")
    private static func signature(_ title: String) -> TitleSignature {
        let text = titleKey(title)
        let numbers = numberPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
        let chars = Array(text)
        let pairs = Set(zip(chars, chars.dropFirst()).map { String($0.0) + String($0.1) })
        return TitleSignature(text: text, numbers: numbers, pairs: pairs)
    }
    private static func duplicates(_ a: NewsArticle, _ b: NewsArticle, keys: [String: TitleSignature]) -> Bool {
        if a.url == b.url { return true }
        guard let x = keys[a.url], let y = keys[b.url] else { return false }
        if x.text == y.text { return true }
        guard min(x.text.count, y.text.count) >= 16, let first = a.published, let second = b.published,
              abs(first.timeIntervalSince(second)) <= 6 * 60 * 60, x.numbers == y.numbers,
              Double(min(x.text.count, y.text.count)) / Double(max(x.text.count, y.text.count)) >= 0.85 else { return false }
        let common = x.pairs.reduce(0) { $0 + (y.pairs.contains($1) ? 1 : 0) }
        return 2 * Double(common) / Double(x.pairs.count + y.pairs.count) >= 0.90
    }
    static func merge(_ articles: [NewsArticle]) -> [NewsArticle] {
        let sorted = articles.sorted {
            if $0.published != $1.published { return ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
            if $0.source != $1.source { return $0.source.rawValue < $1.source.rawValue }
            return $0.url < $1.url
        }
        var result: [NewsArticle] = [], counts: [NewsSource: Int] = [:]
        var keys: [String: TitleSignature] = [:]
        for article in articles { keys[article.url] = signature(article.title) }
        var titles = Set<String>(), urls = Set<String>(), near: [[String]: [NewsArticle]] = [:]
        for article in sorted where counts[article.source, default: 0] < maxPerSource {
            guard let key = keys[article.url] else { continue }
            if urls.contains(article.url) || titles.contains(key.text) || near[key.numbers, default: []].contains(where: { duplicates($0, article, keys: keys) }) { continue }
            result.append(article); counts[article.source, default: 0] += 1
            urls.insert(article.url); titles.insert(key.text); near[key.numbers, default: []].append(article)
            if result.count == maxItems { break }
        }
        return result
    }
    static func fetch(_ source: NewsSource, category: NewsCategory) async throws -> [NewsArticle] {
        guard let url = source.feed(category) else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12; request.setValue("application/rss+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        var data = Data()
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        for try await byte in bytes {
            try Task.checkCancellation()
            if ContinuousClock.now > deadline { throw URLError(.timedOut) }
            if data.count >= 2 * 1024 * 1024 { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        let payload = data
        let task = Task.detached(priority: .utility) { try parse(payload, source: source) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

}

@MainActor
private final class LauncherNewsStore: ObservableObject {
    static let shared = LauncherNewsStore()
    static let interval: TimeInterval = 2 * 60 * 60
    static let retry: TimeInterval = 5 * 60
    static let maxAge: TimeInterval = 24 * 60 * 60
    @Published var topics: Set<NewsCategory> = {
        guard let saved = UserDefaults.standard.stringArray(forKey: "ratio.news.selected.topics.v1") else { return [.society, .economy, .culture] }
        return Set(NewsCategory.topics.filter { saved.contains($0.rawValue) })
    }()
    var topicList: [NewsCategory] { NewsCategory.topics.filter { topics.contains($0) } }
    func selectTopics(_ values: Set<NewsCategory>) {
        topics = values.subtracting([.latest])
        UserDefaults.standard.set(topicList.map(\.rawValue), forKey: "ratio.news.selected.topics.v1")
        snapshots[.latest] = nil; pending[.latest] = nil; errors.remove(.latest)
        Task { await rebuildLatest(force: true) }
        LauncherNewsRefresh.topicsChanged()
    }
    @Published var snapshots: [NewsCategory: NewsSnapshot] = [:]
    @Published var pending: [NewsCategory: NewsSnapshot] = [:]
    @Published var loading: Set<NewsCategory> = []
    @Published var errors: Set<NewsCategory> = []
    private var fetched: [NewsCategory: Date] = [:]
    private var retries: [NewsCategory: Date] = [:]
    private var intervals: [NewsCategory: TimeInterval] = [:]
    private var readers: Set<NewsCategory> = []
    private var aggregateRevision = 0
    func beginReading(_ category: NewsCategory) { readers.insert(category) }
    func endReadingSession() {
        readers.removeAll()
        for category in NewsCategory.allCases { apply(category) }
    }
    private func usable(_ value: NewsSnapshot?) -> NewsSnapshot? {
        guard let old = value, (0..<Self.maxAge).contains(Date.now.timeIntervalSince(old.fetched)) else { return nil }
        let times = old.sourceFetched.filter { (0..<Self.maxAge).contains(Date.now.timeIntervalSince($0.value)) }
        let items = old.items.filter { times[$0.source.rawValue] != nil }
        return items.isEmpty ? nil : NewsSnapshot(items: items, fetched: old.fetched,
            sourceFetched: times, partial: old.partial || times.count < old.sourceFetched.count)
    }
    func apply(_ category: NewsCategory) { if let next = pending.removeValue(forKey: category) { snapshots[category] = usable(next) } }
    func delay(_ category: NewsCategory) -> TimeInterval {
        if category == .latest { return topicList.map { delay($0) }.min() ?? Self.interval }
        if loading.contains(category) { return 1 }
        if let retry = retries[category] { return max(1, min(Self.retry, retry.timeIntervalSinceNow)) }
        let interval = intervals[category] ?? (snapshots[category]?.partial == true ? Self.retry : Self.interval)
        return max(1, min(interval, (fetched[category] ?? .distantPast).addingTimeInterval(interval).timeIntervalSinceNow))
    }
    init() {
        UserDefaults.standard.removeObject(forKey: "ratio.news.cache.sokbo.v4")
        for category in topicList { restore(category) }
        Task { await rebuildLatest(force: true) }
    }
    private func rebuildLatest(force: Bool = false) async {
        aggregateRevision += 1
        let revision = aggregateRevision
        let selected = topics
        let values = topicList.compactMap { usable(pending[$0] ?? snapshots[$0]) }
        guard !values.isEmpty else { snapshots[.latest] = nil; pending[.latest] = nil; return }
        let payload = values.flatMap(\.items)
        let articles = await Task.detached(priority: .utility) { NewsRSSParser.merge(payload) }.value
        guard !Task.isCancelled, topics == selected, revision == aggregateRevision else { return }
        var times: [String: Date] = [:]
        for value in values { for (source, date) in value.sourceFetched { times[source] = max(times[source] ?? .distantPast, date) } }
        let next = NewsSnapshot(items: articles, fetched: values.map(\.fetched).min() ?? .now,
            sourceFetched: times, partial: values.count < selected.count || values.contains { $0.partial })
        if force || snapshots[.latest] == nil || !readers.contains(.latest) { snapshots[.latest] = next; pending[.latest] = nil }
        else if snapshots[.latest]?.items != articles { pending[.latest] = next }
        else { snapshots[.latest] = next; pending[.latest] = nil }
        fetched[.latest] = next.fetched; intervals[.latest] = next.partial ? Self.retry : Self.interval
    }
    private func restore(_ category: NewsCategory) {
        guard topics.contains(category) else { return }
        let key = "ratio.news.cache.\(category.rawValue).v5"
        UserDefaults.standard.removeObject(forKey: "ratio.news.cache.\(category.rawValue).v3")
        UserDefaults.standard.removeObject(forKey: "ratio.news.cache.\(category.rawValue).v2")
        UserDefaults.standard.removeObject(forKey: "ratio.news.cache.\(category.rawValue).v1")
        if let old = snapshots[category], !(0..<Self.maxAge).contains(Date.now.timeIntervalSince(old.fetched)) { snapshots[category] = nil; pending[category] = nil; fetched[category] = nil }
        if snapshots[category] == nil, let data = UserDefaults.standard.data(forKey: key) ?? UserDefaults.standard.data(forKey: "ratio.news.cache.\(category.rawValue).v4"),
           let cache = try? JSONDecoder().decode(NewsSnapshot.self, from: data), cache.items.count <= NewsRSSParser.maxItems,
           cache.items.allSatisfy({ $0.source.accepts($0.url) }), (0..<Self.maxAge).contains(Date.now.timeIntervalSince(cache.fetched)) {
            let allowed = Set(NewsSource.available(category))
            var cleaned = cache
            cleaned.items = cache.items.filter { allowed.contains($0.source) }.compactMap { article in
                var value = article
                value.title = String(NewsRSSParser.clean(value.title).prefix(240))
                value.summary = String(NewsRSSParser.clean(value.summary).prefix(161))
                return value.title.isEmpty ? nil : value
            }
            snapshots[category] = cleaned; fetched[category] = cleaned.fetched; intervals[category] = cleaned.partial ? Self.retry : Self.interval
        }
        snapshots[category] = usable(snapshots[category])
        pending[category] = usable(pending[category])
    }
    private func checkpoint(_ category: NewsCategory, feeds: [(NewsSource, [NewsArticle]?, Date?)],
        cache: NewsSnapshot?, expected: Int, force: Bool, final: Bool) async -> NewsSnapshot? {
        guard topics.contains(category) else { return nil }
        let successes = feeds.filter { $0.1 != nil }
        guard !successes.isEmpty else { return nil }
        var times = cache?.sourceFetched ?? [:]
        var sources = Dictionary(grouping: cache?.items ?? [], by: \.source)
        for (source, items, date) in successes {
            times[source.rawValue] = date ?? .now; sources[source] = items ?? []
        }
        let payload = sources.values.flatMap { $0 }
        let articles = await Task.detached(priority: .utility) { NewsRSSParser.merge(payload) }.value
        guard !Task.isCancelled, topics.contains(category), !articles.isEmpty else { return nil }
        let next = NewsSnapshot(items: articles, fetched: .now, sourceFetched: times, partial: successes.count < expected)
        guard let data = try? JSONEncoder().encode(next) else { return nil }
        UserDefaults.standard.set(data, forKey: "ratio.news.cache.\(category.rawValue).v5")
        UserDefaults.standard.removeObject(forKey: "ratio.news.cache.\(category.rawValue).v4")
        if snapshots[category] == nil || !readers.contains(category) || (force && final) { snapshots[category] = next; pending[category] = nil }
        else if snapshots[category]?.items != articles { pending[category] = next }
        else { snapshots[category] = next; pending[category] = nil }
        fetched[category] = next.fetched; intervals[category] = next.partial ? Self.retry : Self.interval
        await rebuildLatest()
        return next
    }
    func refresh(_ category: NewsCategory, force: Bool, revalidate: Bool = false) async {
        if category == .latest {
            for topic in topicList {
                guard !Task.isCancelled else { return }
                if topics.contains(topic) { await refresh(topic, force: force, revalidate: revalidate) }
            }
            await rebuildLatest(force: force)
            if snapshots[.latest] == nil && !topics.isEmpty { errors.insert(.latest) } else { errors.remove(.latest) }
            return
        }
        guard topics.contains(category), !loading.contains(category) else { return }
        // Foreground and scheduled refresh share one three-request budget.
        while !loading.isEmpty {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            if Task.isCancelled || loading.contains(category) { return }
        }
        guard topics.contains(category), !Task.isCancelled else { return }
        restore(category)
        if !force && !revalidate {
            if let retry = retries[category], retry > .now { return }
            if !errors.contains(category), snapshots[category] != nil, let time = fetched[category], (0..<(intervals[category] ?? Self.interval)).contains(Date.now.timeIntervalSince(time)) { return }
        }
        loading.insert(category); errors.remove(category)
        defer { loading.remove(category) }
        do {
            let cache = usable(pending[category] ?? snapshots[category])
            let available = NewsSource.available(category).sorted {
                (cache?.sourceFetched[$0.rawValue] ?? .distantPast) < (cache?.sourceFetched[$1.rawValue] ?? .distantPast)
            }
            let interval = Self.interval
            let mustFetch = force || revalidate
            let fetch: @Sendable (NewsSource) async -> (NewsSource, [NewsArticle]?, Date?) = { source in
                if !mustFetch, let previous = cache?.sourceFetched[source.rawValue], (0..<interval).contains(Date.now.timeIntervalSince(previous)) {
                    return (source, cache?.items.filter { $0.source == source }, previous)
                }
                let items = try? await NewsRSSParser.fetch(source, category: category)
                return (source, items, items == nil ? nil : .now)
            }
            let feeds = await withTaskGroup(of: (NewsSource, [NewsArticle]?, Date?).self) { group in
                var sources = available.makeIterator()
                for _ in 0..<NewsRSSParser.maxConcurrent {
                    if let source = sources.next() { group.addTask { await fetch(source) } }
                }
                var result: [(NewsSource, [NewsArticle]?, Date?)] = []
                var published = false
                while let feed = await group.next() {
                    result.append(feed)
                    if (!published && cache == nil && result.contains(where: { $0.1 != nil })) || result.count.isMultiple(of: 12) {
                        if await checkpoint(category, feeds: result, cache: cache, expected: available.count, force: force, final: false) != nil { published = true }
                    }
                    if !Task.isCancelled, topics.contains(category), let source = sources.next() { group.addTask { await fetch(source) } }
                }
                return result
            }
            try Task.checkCancellation()
            guard await checkpoint(category, feeds: feeds, cache: cache, expected: available.count, force: force, final: true) != nil else { throw URLError(.cannotLoadFromNetwork) }
            retries[category] = nil

        } catch {
            if !Task.isCancelled { errors.insert(category); retries[category] = .now.addingTimeInterval(Self.retry) }
        }
    }
}

@MainActor
enum LauncherNewsRefresh {
    private static var warm: Task<Void, Never>?
    private static var generation = UUID()
    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: LauncherNewsBackgroundTasks.enabledKey)
        if enabled {
            LauncherNewsBackgroundTasks.schedule()
            applicationActive(UIApplication.shared.applicationState == .active)
        } else {
            applicationActive(false)
            LauncherNewsBackgroundTasks.cancel()
        }
    }
    static func prefetch(revalidate: Bool = false) async -> Bool {
        guard UserDefaults.standard.bool(forKey: LauncherNewsBackgroundTasks.enabledKey) else { return true }
        for category in LauncherNewsStore.shared.topicList {
            if Task.isCancelled { return false }
            if !UserDefaults.standard.bool(forKey: LauncherNewsBackgroundTasks.enabledKey) { return true }
            await LauncherNewsStore.shared.refresh(category, force: false, revalidate: revalidate)
        }
        return LauncherNewsStore.shared.topics.isEmpty || LauncherNewsStore.shared.topicList.contains { LauncherNewsStore.shared.snapshots[$0] != nil }
    }
    static func topicsChanged() {
        applicationActive(false)
        applicationActive(UIApplication.shared.applicationState == .active)
    }
    static func endReadingSession() {
        if UserDefaults.standard.bool(forKey: LauncherNewsBackgroundTasks.enabledKey) { LauncherNewsStore.shared.endReadingSession() }
    }
    static func applicationActive(_ active: Bool) {
        guard active, UserDefaults.standard.bool(forKey: LauncherNewsBackgroundTasks.enabledKey) else {
            generation = UUID(); warm?.cancel(); warm = nil; return
        }
        guard warm == nil else { return }
        let token = UUID(); generation = token
        warm = Task {
            defer { if generation == token { warm = nil } }
            while !Task.isCancelled {
                _ = await prefetch()
                do { try await Task.sleep(for: .seconds(LauncherNewsStore.interval)) } catch { return }
            }
        }
    }
}

struct RatioNewsWidget: View {
    var active: Bool
    var onArticle: (String) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var store = LauncherNewsStore.shared
    @State private var category = NewsCategory.latest
    @State private var settings = false
    @State private var draft: Set<NewsCategory> = []
    @State private var request = 0
    @State private var handled = 0
    @State private var scrollRequest = 0
    @State private var now = Date()
    private var enabled: Bool { active && scenePhase == .active }
    private let style = RatioExperience()
    private var busy: Bool { store.loading.contains(category) || (category == .latest && !store.loading.intersection(store.topics).isEmpty) }
    private var controls: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
            ForEach([NewsCategory.latest] + store.topicList, id: \.self) { value in
                Button { category = value; scrollRequest += 1 } label: {
                    Text(value.title).visionCraftAndroidText(20, weight: .semibold)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(category == value ? style.background : style.text)
                        .background(category == value ? style.accent : style.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                }.accessibilityAddTraits(category == value ? [.isSelected] : [])
            }
            Button { draft = store.topics; settings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 28)).frame(width: 56, height: 56)
                    .background(style.surface.opacity(0.7), in: Circle())
            }.accessibilityLabel("뉴스 분야 설정")
            Button { request += 1 } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 28)).frame(width: 56, height: 56)
                    .background(style.surface.opacity(0.7), in: Circle())
            }.accessibilityLabel("뉴스 새로고침").disabled(!enabled || store.topics.isEmpty || busy)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            controls
            if store.pending[category] != nil {
                Button("새 뉴스가 있어요 · 보기") { store.apply(category); scrollRequest += 1 }
                    .visionCraftAndroidText(20).foregroundStyle(style.accent).frame(minHeight: 56)
            }
            if store.errors.contains(category) {
                Text(store.snapshots[category] == nil ? "뉴스를 불러오지 못했어요. 새로고침으로 다시 시도해 주세요." : "갱신하지 못했어요. 이전 뉴스와 갱신 시각을 표시합니다.")
                    .visionCraftAndroidText(18).fixedSize(horizontal: false, vertical: true)
            }
            if let snapshot = store.snapshots[category] {
                Text("여러 언론사 · \(snapshot.fetched.formatted(date: .omitted, time: .shortened)) 갱신").visionCraftAndroidText(16)
                if snapshot.partial && !busy {
                    Text("일부 언론사의 갱신이 늦어지고 있어요. 받아온 뉴스와 이전 기사를 표시합니다.")
                        .visionCraftAndroidText(16).foregroundStyle(style.text.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            Color.clear.frame(height: 1).id("newsTop").accessibilityHidden(true)
                            ForEach(snapshot.items) { article in
                                articleRow(article)
                                if article.id != snapshot.items.last?.id {
                                    Rectangle().fill(style.outline.opacity(0.28)).frame(height: 1).accessibilityHidden(true)
                                }
                            }
                        }.padding(.bottom, 16)
                    }.onChange(of: scrollRequest) { _, _ in proxy.scrollTo("newsTop", anchor: .top) }
                }
            } else {
                VStack(spacing: 10) {
                    if enabled && !store.topics.isEmpty && !store.errors.contains(category) { NewsLoadingWave() }
                    Text(store.topics.isEmpty ? "관심 있는 뉴스 분야를 선택해 주세요." : !store.errors.contains(category) ? "뉴스를 불러오는 중이에요" : "새로고침을 눌러 뉴스를 받아보세요").visionCraftAndroidText(20)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.padding(20).foregroundStyle(style.text).buttonStyle(.plain).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task(id: "\(enabled):\(category.rawValue):\(request):\(store.topicList.map(\.rawValue).joined(separator: ","))") {
                guard enabled, !store.topics.isEmpty else { return }
                store.beginReading(category)
                var force = request != handled; handled = request
                while !Task.isCancelled {
                    await store.refresh(category, force: force)
                    if force && !store.errors.contains(category) { scrollRequest += 1 }
                    force = false
                    do { try await Task.sleep(for: .seconds(store.delay(category))) } catch { return }
                }
            }
            .task(id: enabled) {
                guard enabled else { return }
                while !Task.isCancelled { now = .now; do { try await Task.sleep(for: .seconds(60)) } catch { return } }
            }
            .sheet(isPresented: $settings) { topicSettings }
    }
    private var topicSettings: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(NewsCategory.topics, id: \.self) { topic in
                        Toggle(topic.title, isOn: Binding(get: { draft.contains(topic) }, set: { checked in
                            if checked { draft.insert(topic) } else { draft.remove(topic) }
                        })).visionCraftAndroidText(20).frame(minHeight: 56)
                    }
                } header: { Text("선택한 분야만 최신 뉴스와 자동 업데이트에 포함해요.") }
            }.navigationTitle("뉴스 분야 설정")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소") { settings = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("저장") {
                        category = .latest; store.selectTopics(draft); scrollRequest += 1; settings = false
                    } }
                }
        }
    }
    private func articleRow(_ article: NewsArticle) -> some View {
        let relative = article.published.map { RelativeDateTimeFormatter().localizedString(for: min($0, now), relativeTo: now) } ?? "발행 시각 미제공"
        return Button { onArticle(article.url) } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text(article.title).visionCraftAndroidText(23, weight: .semibold).foregroundStyle(style.text)
                if !article.summary.isEmpty { Text(article.summary).visionCraftAndroidText(18).foregroundStyle(style.text.opacity(0.92)) }
                Text("\(article.source.title) · \(relative)").visionCraftAndroidText(16).foregroundStyle(style.text.opacity(0.75))
            }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2).padding(.top, 22).padding(.bottom, 24).contentShape(Rectangle())
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("\(article.title). \(article.summary) \(article.source.title), \(relative)")
            .accessibilityHint("기사 원문 열기")
    }
}
private struct NewsLoadingWave: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 2 * .pi / 3.6
                for line in 0..<3 {
                    var path = Path()
                    for step in 0...100 {
                        let x = size.width * CGFloat(step) / 100
                        let y = size.height / 2 + CGFloat(sin(Double(step) / 100 * 2 * .pi + phase + Double(line) * 0.8)) * size.height * CGFloat(0.1 + Double(line) * 0.035)
                        if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(path, with: .color(RatioExperience().accent.opacity(1 - Double(line) * 0.25)), lineWidth: 1.5)
                }
            }
        }.frame(width: 144, height: 80).accessibilityHidden(true)
    }
}
