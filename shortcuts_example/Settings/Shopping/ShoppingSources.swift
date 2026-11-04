#if DEBUG
import Foundation

nonisolated enum ShoppingSource: String, CaseIterable, Sendable {
    case lotteon, hmall, eleven, gsshop, cj, ohou, himart, hns, auction, gmarket, ssg

    var usesPublishedHTML: Bool { [.lotteon, .gsshop, .ohou, .hns].contains(self) }

    func searchURL(_ query: String) -> URL {
        let base: String
        let key: String
        switch self {
        case .lotteon: base = "https://www.lotteon.com/csearch/search/search?render=search&platform=pc&mallId=1&sort=ranking"; key = "q"
        case .hmall: base = "https://www.hmall.com/md/pde/search?gnbSearchYn=Y&requestPath=w&tab=all&searchType=normal"; key = "searchTerm"
        case .gsshop: base = "https://m.gsshop.com/search/searchSect.gs"; key = "tq"
        case .cj: base = "https://display.cjonstyle.com/p/search/searchAllList?searchType=ALL"; key = "k"
        case .ohou: base = "https://ohou.se/productions/feed"; key = "query"
        case .himart: base = "https://www.e-himart.co.kr/app/search/nativeTotalSearch?stonType=PC"; key = "query"
        case .hns: base = "https://www.hnsmall.com/search/search.do?search_type=%EC%A7%81%EC%A0%91%20%EC%9E%85%EB%A0%A5"; key = "query_top"
        case .ssg: base = "https://www.ssg.com/search.ssg"; key = "query"
        case .gmarket: base = "https://www.gmarket.co.kr/n/search"; key = "keyword"
        case .auction: base = "https://www.auction.co.kr/n/search"; key = "keyword"
        case .eleven: base = "https://search.11st.co.kr/pc/total-search"; key = "kwd"
        }
        var parts = URLComponents(string: base)!
        parts.queryItems = (parts.queryItems ?? []) + [URLQueryItem(name: key, value: query)]
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url!
    }

    func allows(_ url: URL) -> Bool {
        let hosts: Set<String>
        switch self {
        case .lotteon: hosts = ["www.lotteon.com"]
        case .hmall: hosts = ["www.hmall.com"]
        case .gsshop: hosts = ["m.gsshop.com"]
        case .cj: hosts = ["display.cjonstyle.com"]
        case .ohou: hosts = ["ohou.se"]
        case .himart: hosts = ["www.e-himart.co.kr", "m.e-himart.co.kr"]
        case .hns: hosts = ["www.hnsmall.com"]
        case .ssg: hosts = ["www.ssg.com", "m.ssg.com"]
        case .gmarket: hosts = ["www.gmarket.co.kr", "m.gmarket.co.kr", "browse.gmarket.co.kr"]
        case .auction: hosts = ["www.auction.co.kr", "m.auction.co.kr", "browse.auction.co.kr"]
        case .eleven: hosts = ["search.11st.co.kr", "www.11st.co.kr", "m.11st.co.kr"]
        }
        return Self.secure(url) && hosts.contains(url.host?.lowercased() ?? "")
            && (self != .ssg || url.path == "/search.ssg")
            && (self != .cj || url.path == "/p/search/searchAllList")
            && (self != .himart || url.path == "/app/search/nativeTotalSearch")
    }
    private static func secure(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }
    func upgradeSearch(_ url: URL) -> URL? {
        guard self == .auction, url.scheme == "http", url.user == nil, url.password == nil, url.port == nil || url.port == 80, url.path == "/n/search",
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = "https"; parts.port = nil
        guard let target = parts.url, allows(target) else { return nil }
        return target
    }
    static func safeOpen(_ url: URL) -> Bool {
        guard url.absoluteString.count <= 1500, secure(url), let host = url.host?.lowercased() else { return false }
        if host == "www.lotteon.com" {
            return url.path == "/csearch/search/search" || url.path.range(of: "^/(p|m)/product/L[OE][0-9]{8,16}/?$", options: .regularExpression) != nil
        }
        if host == "www.hmall.com" {
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "slitmCd" }?.value ?? ""
            return url.path == "/md/pde/search" || (url.path == "/md/pda/itemPtc" && id.range(of: "^[0-9]{3,20}$", options: .regularExpression) != nil)
        }
        if host == "m.gsshop.com" || host == "www.ssg.com" {
            let isGS = host == "m.gsshop.com"
            if url.path == (isGS ? "/search/searchSect.gs" : "/search.ssg") { return true }
            guard url.path == (isGS ? "/prd/prd.gs" : "/item/itemView.ssg") else { return false }
            let key = isGS ? "prdid" : "itemId"
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == key }?.value ?? ""
            return id.range(of: "^[0-9]{3,20}$", options: .regularExpression) != nil
        }
        if host == "display.cjonstyle.com" {
            return url.path == "/p/search/searchAllList" ||
                url.path.range(of: "^/p/item/[0-9]{3,20}$", options: .regularExpression) != nil
        }
        if host == "ohou.se" { return url.path == "/productions/feed" }
        if host == "store.ohou.se" { return url.path.range(of: "^/goods/[0-9]{3,20}$", options: .regularExpression) != nil }
        if host == "www.e-himart.co.kr" || host == "www.hnsmall.com" {
            let isHimart = host == "www.e-himart.co.kr"
            if url.path == (isHimart ? "/app/search/nativeTotalSearch" : "/search/search.do") { return true }
            guard url.path == (isHimart ? "/app/goods/goodsDetail" : "/display/goods.do") else { return false }
            let key = isHimart ? "goodsNo" : "goods_code"
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == key }?.value ?? ""
            return id.range(of: "^[0-9]{3,20}$", options: .regularExpression) != nil
        }
        return ["gmarket.co.kr", "auction.co.kr", "11st.co.kr"].contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
nonisolated struct ShoppingPageError: Error, Sendable {}

nonisolated enum ShoppingRetailerHTML {
    @concurrent static func load(_ source: ShoppingSource, query: String) async throws -> String {
        let url = source.searchURL(query)
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 18; config.timeoutIntervalForResource = 22
        let session = URLSession(configuration: config, delegate: ShoppingRetailerRedirect(source: source, path: url.path), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let (bytes, response) = try await session.bytes(for: request)
        let limit = 4 * 1024 * 1024
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), response.expectedContentLength <= limit else { throw ShoppingPageError() }
        var data = Data()
        for try await byte in bytes { guard data.count < limit else { throw ShoppingPageError() }; data.append(byte) }
        try Task.checkCancellation()
        guard let html = String(data: data, encoding: .utf8) else { throw ShoppingPageError() }
        return html
    }
}
nonisolated private final class ShoppingRetailerRedirect: NSObject, URLSessionTaskDelegate {
    private let source: ShoppingSource
    private let path: String

    init(source: ShoppingSource, path: String) {
        self.source = source
        self.path = path
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let allowed = request.url.map { source.allows($0) && $0.path == path } == true
        completionHandler(allowed ? request : nil)
    }
}
#endif
