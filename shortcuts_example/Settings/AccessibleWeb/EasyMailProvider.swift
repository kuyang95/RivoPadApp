import Foundation

struct EasyMailProvider: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let home: String
    let domains: Set<String>
    let authHosts: Set<String>
    let selector: String
    static let appearanceHosts: Set<String> = ["mail.naver.com", "m.mail.naver.com", "mail.daum.net", "m.mail.daum.net", "mail.kakao.com", "m.mail.kakao.com", "mail.nate.com", "m.mail.nate.com", "mail2.nate.com", "mail3.nate.com", "mail4.nate.com", "mail.google.com", "outlook.live.com", "outlook.office.com", "outlook.office365.com", "www.icloud.com", "mail.yahoo.com"]
    static let all: [EasyMailProvider] = [
        .init(id: "naver",name: "NAVER",home: "https://mail.naver.com/",domains: ["naver.com"],authHosts: ["nid.naver.com"],selector: ""),
        .init(id: "daum",name: "Daum · Hanmail",home: "https://mail.daum.net/",domains: ["daum.net","hanmail.net"],authHosts: ["accounts.kakao.com","logins.daum.net"],selector: ""),
        .init(id: "kakao",name: String(localized: "카카오메일"),home: "https://mail.kakao.com/",domains: ["kakao.com"],authHosts: ["accounts.kakao.com"],selector: "input[name=loginId]"),
        .init(id: "nate",name: "Nate",home: "https://mail.nate.com/",domains: ["nate.com","empal.com"],authHosts: ["xo.nate.com","home.mail.nate.com"],selector: "input[name=\"ID\"],input[name=\"id\"],#ID,#nateId"),
        .init(id: "gmail",name: "Gmail",home: "https://mail.google.com/",domains: ["gmail.com","googlemail.com"],authHosts: ["accounts.google.com"],selector: "#identifierId"),
        .init(id: "outlook",name: "Outlook",home: "https://outlook.live.com/mail/",domains: ["outlook.com","hotmail.com","live.com","msn.com","outlook.kr","hotmail.co.kr"],authHosts: ["login.live.com","login.microsoftonline.com"],selector: "input[name=\"loginfmt\"]"),
        .init(id: "icloud",name: "iCloud Mail",home: "https://www.icloud.com/mail/",domains: ["icloud.com","me.com","mac.com"],authHosts: ["idmsa.apple.com","account.apple.com"],selector: "#account_name_text_field"),
        .init(id: "yahoo",name: "Yahoo Mail",home: "https://mail.yahoo.com/",domains: ["yahoo.com","ymail.com","rocketmail.com","yahoo.co.uk","yahoo.fr","yahoo.de","yahoo.ca","yahoo.com.au"],authHosts: ["login.yahoo.com"],selector: "#login-username"),
    ]
    static func forAddress(_ address: String) -> Self? {
        guard let domain = address.split(separator: "@").last?.lowercased() else { return nil }
        return all.first { $0.domains.contains(domain) }
    }
    static func customURL(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = text.contains("://") ? text : "https://" + text
        guard let url = URL(string: value), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.port == nil, !value.contains(where: \.isWhitespace) else { return nil }
        return url.absoluteString
    }
    var nativeInboxHosts: Set<String> {
        switch id {
        case "naver": ["mail.naver.com", "m.mail.naver.com"]
        case "daum": ["mail.daum.net", "m.mail.daum.net"]
        case "kakao": ["mail.kakao.com", "m.mail.kakao.com"]
        case "nate": ["mail.nate.com", "m.mail.nate.com", "mail2.nate.com", "mail3.nate.com", "mail4.nate.com"]
        default: []
        }
    }
    func nativeIdentifier(_ address: String) -> String? {
        guard !nativeInboxHosts.isEmpty, !address.isEmpty else { return nil }
        if id == "naver", let separator = address.lastIndex(of: "@"),
           address[address.index(after: separator)...].lowercased() == "naver.com" {
            return String(address[..<separator])
        }
        return address
    }

    func hintScript(address: String, url: URL?) -> String {
        guard !selector.isEmpty, !address.isEmpty, let url, url.scheme == "https", url.user == nil,
              let host = url.host, authHosts.contains(host) else { return "" }
        func json<T: Encodable>(_ value: T) -> String { String(data: try! JSONEncoder().encode(value), encoding: .utf8)! }
        return EasyMailPage.hintTemplate.replacingOccurrences(of: "HOSTS", with: json(Array(authHosts)))
            .replacingOccurrences(of: "SELECTOR", with: json(selector)).replacingOccurrences(of: "ADDRESS", with: json(address))
    }
}
