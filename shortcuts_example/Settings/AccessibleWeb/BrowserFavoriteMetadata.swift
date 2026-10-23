#if DEBUG
import Foundation
import CoreFoundation
import UIKit
import ImageIO

private final class FavoriteMetadataRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.flatMap { BrowserFavoriteMetadata.secureURL($0.absoluteString) } == nil ? nil : request)
    }
}
struct BrowserFavoriteMetadata {
    var name: String
    var icon: String?
    static func secureURL(_ value: String, relativeTo base: URL? = nil) -> URL? {
        guard let url = URL(string: value, relativeTo: base)?.absoluteURL,
              url.scheme?.lowercased() == "https", url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
        return url
    }
    private static func matches(_ pattern: String, in value: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { match in
            (0..<match.numberOfRanges).map { index in Range(match.range(at: index), in: value).map { String(value[$0]) } ?? "" }
        }
    }
    private static func text(_ value: String) -> String {
        var result = value
        let entities = ["&amp;": "&", "&quot;": "\"", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]
        for match in matches("&#(x[0-9a-f]+|[0-9]+);", in: result) {
            let number = match[1].lowercased()
            if let value = UInt32(number.hasPrefix("x") ? String(number.dropFirst()) : number, radix: number.hasPrefix("x") ? 16 : 10), let scalar = UnicodeScalar(value) {
                result = result.replacingOccurrences(of: match[0], with: String(scalar))
            }
        }
        for (key, value) in entities { result = result.replacingOccurrences(of: key, with: value) }
        return result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func read(_ url: URL, limit: Int, session: URLSession, deadline: Date) async throws -> (URL, Data, String?) {
        try Task.checkCancellation()
        guard deadline.timeIntervalSinceNow > 0 else { throw URLError(.timedOut) }
        var request = URLRequest(url: url)
        request.timeoutInterval = min(8, max(0.1, deadline.timeIntervalSinceNow))
        request.setValue("Mozilla/5.0 RivoBrowser/1.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let finalURL = response.url, secureURL(finalURL.absoluteString) != nil else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit { break }
            if data.count % 8192 == 0 { try Task.checkCancellation(); if deadline.timeIntervalSinceNow <= 0 { throw URLError(.timedOut) } }
        }
        return (finalURL, data, response.textEncodingName)
    }
    static func fetch(_ url: URL) async -> BrowserFavoriteMetadata {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 12
        let session = URLSession(configuration: configuration, delegate: FavoriteMetadataRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let deadline = Date().addingTimeInterval(12)
        var result = BrowserFavoriteMetadata(name: (url.host ?? url.absoluteString).replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression))
        var base = url
        var candidates: [(Int, URL)] = []
        if let (resolved, data, charset) = try? await read(url, limit: 262144, session: session, deadline: deadline) {
            base = resolved
            var encoding = String.Encoding.utf8
            if let charset {
                let cf = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
                if cf != kCFStringEncodingInvalidId { encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf)) }
            }
            let html = String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)
            var meta: [String: String] = [:]
            for tag in matches("<(meta|link)\\b[^>]*>", in: html) {
                var attributes: [String: String] = [:]
                for attr in matches(#"([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#, in: tag[0]) {
                    attributes[attr[1].lowercased()] = text(attr.dropFirst(2).first { !$0.isEmpty } ?? "")
                }
                if tag[1].lowercased() == "meta" {
                    if let key = attributes["property"] ?? attributes["name"], let value = attributes["content"], meta[key.lowercased()] == nil { meta[key.lowercased()] = value }
                } else {
                    let rel = (attributes["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
                    if rel.contains(where: { ["icon", "apple-touch-icon", "apple-touch-icon-precomposed"].contains($0) }),
                       let href = attributes["href"], let iconURL = secureURL(href, relativeTo: base) {
                        candidates.append((rel.contains(where: { $0.hasPrefix("apple-touch") }) ? 0 : 1, iconURL))
                    }
                }
            }
            let title = matches("<title\\b[^>]*>([\\s\\S]*?)</title>", in: html).first.map { text($0[1]) }
            if let name = [meta["og:site_name"], meta["application-name"], meta["og:title"], title].compactMap({ $0 }).first(where: {
                !$0.isEmpty && $0.range(of: "access denied|just a moment|captcha|robot check|접근.*차단", options: [.regularExpression, .caseInsensitive]) == nil
            }) { result.name = String(name.prefix(60)) }
        }
        if let fallback = secureURL("/favicon.ico", relativeTo: base) { candidates.append((2, fallback)) }
        var seen: Set<URL> = []
        let urls = candidates.sorted { $0.0 < $1.0 }.compactMap { seen.insert($0.1).inserted ? $0.1 : nil }.prefix(3)
        for iconURL in urls {
            guard !Task.isCancelled, deadline.timeIntervalSinceNow > 0 else { break }
            guard let (_, data, _) = try? await read(iconURL, limit: 524288, session: session, deadline: deadline), data.count <= 524288,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 96, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
                  let png = UIImage(cgImage: image).pngData() else { continue }
            result.icon = "data:image/png;base64," + png.base64EncodedString()
            break
        }
        return result
    }
}
#endif
