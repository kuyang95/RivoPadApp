import Foundation
import WebKit

struct MailAccount: Identifiable, Equatable {
    let id: String
    let provider: EasyMailProvider
    let address: String
    var storeIdentifier: UUID {
        provider.id == "gmail" ? EasyYouTubePage.storeIdentifier : (UUID(uuidString: id) ?? EasyMailPage.storeIdentifier)
    }
    var hasInbox: Bool { provider.id == "naver" || (provider.id == "gmail" && !address.isEmpty) }
    func supports(_ folder: MailFolder) -> Bool { hasInbox && (provider.id != "gmail" || folder.gmailRoute != nil) }
    var label: String { address.isEmpty ? provider.name : address }
    var headerLabel: String {
        let identity = provider.id == "naver" && address.lowercased().hasSuffix("@naver.com")
            ? String(address.dropLast("@naver.com".count)) : address
        return [provider.name, identity].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

enum MailFolder: String, CaseIterable, Identifiable {
    case inbox = "0", all = "-1", sent = "1", promotions = "10", billing = "7", social = "9", cafe = "8"
    var id: Self { self }
    var gmailRoute: String? {
        switch self {
        case .inbox: "inbox"
        case .all: "all"
        case .sent: "sent"
        case .promotions: "category/promotions"
        case .social: "category/social"
        case .billing, .cafe: nil
        }
    }
    var title: String {
        switch self {
        case .inbox: String(localized: "받은메일함")
        case .all: String(localized: "전체메일")
        case .sent: String(localized: "보낸메일함")
        case .promotions: String(localized: "프로모션")
        case .billing: String(localized: "청구·결제")
        case .social: String(localized: "SNS")
        case .cafe: String(localized: "카페")
        }
    }
}

@MainActor
enum MailAccounts {
    static func all() -> [MailAccount] {
        let defaults = UserDefaults.standard
        if let saved = defaults.array(forKey: "easyMail.accounts") as? [[String: String]] {
            return saved.compactMap { entry in
                guard let id = entry["id"], id == "legacy" || UUID(uuidString: id) != nil else { return nil }
                let provider = EasyMailProvider.all.first { $0.id == entry["provider"] }
                    ?? entry["home"].flatMap(EasyMailProvider.customURL).map {
                        EasyMailProvider(id: "custom", name: String(localized: "다른 메일"), home: $0, domains: [], authHosts: [], selector: "")
                    }
                guard let provider else { return nil }
                let address = entry["address"] ?? ""
                guard provider.id != "gmail" || !address.isEmpty else { return nil }
                return MailAccount(id: id, provider: provider, address: address)
            }
        }
        guard let provider = EasyMailProvider.all.first(where: { $0.id == defaults.string(forKey: "easyMail.provider") })
        else { return [] }
        let address = defaults.string(forKey: "easyMail.address") ?? defaults.string(forKey: "easyMail.naverAddress") ?? ""
        guard provider.id != "gmail" || !address.isEmpty else { return [] }
        return [MailAccount(id: "legacy", provider: provider, address: address)]
    }

    static func account(_ provider: EasyMailProvider, address: String) -> MailAccount {
        if provider.id == "gmail", address.isEmpty { return MailAccount(id: "google-session", provider: provider, address: "") }
        let accounts = all()
        if let account = accounts.first(where: {
            $0.provider.id == provider.id && $0.provider.home == provider.home &&
                $0.address.caseInsensitiveCompare(address) == .orderedSame
        }) { return account }
        let account = MailAccount(id: UUID().uuidString, provider: provider, address: address)
        UserDefaults.standard.set((accounts + [account]).map {
            ["id": $0.id, "provider": $0.provider.id, "address": $0.address, "home": $0.provider.home]
        }, forKey: "easyMail.accounts")
        return account
    }
}

struct MailInboxItem: Identifiable {
    let account: MailAccount
    let url: String
    let subject: String
    let sender: String
    let time: String
    let received: Date
    var id: String { "\(account.id):\(url)" }
}

enum MailInboxResult {
    case loaded([MailInboxItem], fetched: Date), signIn, unavailable
}

@MainActor
enum MailInboxReader {
    static func read(_ account: MailAccount, folder: MailFolder) async -> MailInboxResult {
        guard account.supports(folder) else { return .unavailable }
        let gmail = account.provider.id == "gmail"
        var gmailURL = URLComponents(string: "https://mail.google.com/mail/")!
        gmailURL.queryItems = [URLQueryItem(name: "authuser", value: account.address)]
        gmailURL.fragment = folder.gmailRoute
        guard let home = gmail ? gmailURL.url : URL(string: "https://mail.naver.com/v2/folders/\(folder.rawValue)") else { return .unavailable }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = gmail ? GoogleWebSession.store : WKWebsiteDataStore(forIdentifier: account.storeIdentifier)
        configuration.defaultWebpagePreferences.preferredContentMode = gmail ? .desktop : .mobile
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: gmail ? 1200 : 450, height: gmail ? 1600 : 800), configuration: configuration)
        defer { view.stopLoading() }
        view.load(URLRequest(url: home))
        let script = gmail ? gmailSnapshot.replacingOccurrences(of: "RIVO_FOLDER", with: jsonLiteral(folder.gmailRoute ?? ""))
            .replacingOccurrences(of: "RIVO_ADDRESS", with: jsonLiteral(account.address)) : snapshot
        for _ in 0..<36 {
            do { try await Task.sleep(for: .milliseconds(350)) }
            catch { return .unavailable }
            guard let url = view.url, url.scheme == "https", let host = url.host, url.user == nil, url.password == nil, url.port == nil || url.port == 443, !view.isLoading else { continue }
            if account.provider.authHosts.contains(host) { return .signIn }
            guard (gmail ? ["mail.google.com"] : Array(account.provider.nativeInboxHosts)).contains(host) else { continue }
            if let raw = (try? await view.evaluateJavaScript(script)) as? String,
               let items = decode(raw, account: account, folder: folder) {
                if gmail { GoogleWebSession.shared.update(youtube: false, value: true) }
                return .loaded(items, fetched: Date())
            }
        }
        return .unavailable
    }

    private struct Payload: Decodable {
        struct Row: Decodable {
            let path: String
            let subject: String
            let sender: String
            let time: String
            let received: Double?
        }
        let origin: String
        let folder: String
        let items: [Row]
    }

    private static func decode(_ raw: String, account: MailAccount, folder: MailFolder) -> [MailInboxItem]? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(raw.utf8)) else { return nil }
        let gmail = account.provider.id == "gmail"
        if gmail {
            guard payload.origin == "https://mail.google.com", payload.folder == folder.gmailRoute else { return nil }
        } else {
            guard payload.folder == folder.rawValue,
                  ["https://mail.naver.com", "https://m.mail.naver.com"].contains(payload.origin) else { return nil }
        }
        return payload.items.prefix(30).compactMap { row in
            if gmail {
                guard let url = URLComponents(string: payload.origin + row.path),
                      url.path.range(of: #"^/mail/u/[0-9]+/$"#, options: .regularExpression) != nil,
                      url.queryItems?.first(where: { $0.name == "authuser" })?.value == account.address,
                      url.queryItems?.first(where: { $0.name == "view" })?.value == "pt",
                      url.queryItems?.first(where: { $0.name == "ui" })?.value == "2",
                      url.queryItems?.first(where: { $0.name == "search" })?.value == "all",
                      let thread = url.queryItems?.first(where: { $0.name == "th" })?.value,
                      thread.range(of: "^[a-fA-F0-9]{10,32}$", options: .regularExpression) != nil,
                      url.fragment == nil else { return nil }
            } else {
                guard row.path.range(of: #"^/v2/read/[0-9]+/[0-9]+/?$"#, options: .regularExpression) != nil else { return nil }
            }
            return MailInboxItem(account: account, url: payload.origin + row.path,
                subject: String(row.subject.prefix(500)), sender: String(row.sender.prefix(500)),
                time: String(row.time.prefix(80)), received: gmail ? Date(timeIntervalSince1970: max(0, row.received ?? 0) / 1000) : received(row.time))
        }
    }

    private static func received(_ value: String) -> Date {
        let numbers = value.split(whereSeparator: { !$0.isASCII || !$0.isNumber }).compactMap { Int($0) }
        let calendar = Calendar.current
        let now = Date()
        if value.contains(":"), numbers.count >= 2 {
            let hour = numbers[0]
            let adjusted = value.contains("오후") || value.localizedCaseInsensitiveContains("PM") ? hour % 12 + 12
                : value.contains("오전") || value.localizedCaseInsensitiveContains("AM") ? hour % 12 : hour
            return calendar.date(bySettingHour: adjusted, minute: numbers[1], second: 0, of: now) ?? .distantPast
        }
        guard numbers.count >= 2 else { return .distantPast }
        let explicitYear = numbers.count >= 3 && numbers[0] > 31
        let month = numbers[explicitYear ? 1 : 0]
        let day = numbers[explicitYear ? 2 : 1]
        guard (1...12).contains(month), (1...31).contains(day) else { return .distantPast }
        let year = explicitYear ? (numbers[0] < 100 ? 2000 + numbers[0] : numbers[0])
            : calendar.component(.year, from: now) - (month > calendar.component(.month, from: now) ? 1 : 0)
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    private static func jsonLiteral(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private static let gmailSnapshot = #"""
(() => {
  'use strict';
  if (window.top !== window || location.origin !== 'https://mail.google.com' || !/^\/mail\/u\/\d+\/$/.test(location.pathname)) return null;
  const expected = RIVO_ADDRESS.toLowerCase();
  const route = RIVO_FOLDER;
  if (!expected || location.hash.slice(1) !== route) return null;
  // Read only the current Google account control, never account chooser contents.
  const controls = [...document.querySelectorAll('a[href*="accounts.google.com"][aria-label],a[href*="/SignOutOptions"][aria-label]')];
  const current = controls.flatMap(node => (node.getAttribute('aria-label') || '').match(/[A-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi) || []);
  if (!current.some(address => address.toLowerCase() === expected)) return null;
  const main = document.querySelector('[role="main"]');
  if (!main) return null;
  const text = node => (node?.textContent || '').trim().slice(0,500);
  const rows = [...main.querySelectorAll('tr.zA')].filter(row => row.getClientRects().length);
  const timestamp = value => {
    const parsed = Date.parse(value);
    if (Number.isFinite(parsed)) return parsed;
    const date = value.match(/(\d{4})[년./-]\s*(\d{1,2})[월./-]\s*(\d{1,2})/);
    if (!date) return 0;
    const clock = value.match(/(오전|오후|AM|PM)?\s*(\d{1,2}):(\d{2})/i);
    let hour = clock ? Number(clock[2]) : 0;
    if (clock?.[1]) hour = hour % 12 + (/오후|PM/i.test(clock[1]) ? 12 : 0);
    return new Date(Number(date[1]),Number(date[2])-1,Number(date[3]),hour,clock ? Number(clock[3]) : 0).getTime();
  };
  const items = rows.slice(0,30).flatMap(row => {
    const legacy = row.getAttribute('data-legacy-thread-id') || row.querySelector('[data-legacy-thread-id]')?.getAttribute('data-legacy-thread-id') || '';
    const subject = row.querySelector('.bog');
    const sender = row.querySelector('.yW');
    const date = row.querySelector('.xW [title]');
    if (!/^[a-f0-9]{10,32}$/i.test(legacy) || !subject || !sender || !date) return [];
    return [{path:location.pathname + '?authuser=' + encodeURIComponent(RIVO_ADDRESS) + '&ui=2&view=pt&search=all&th=' + legacy,
      subject:text(subject),sender:text(sender),time:text(date).slice(0,80),received:timestamp(date.getAttribute('title') || '')}];
  });
  // An unknown/new DOM must not turn into an apparently empty mailbox.
  if (rows.length && items.length !== Math.min(30,rows.length)) return null;
  if (!rows.length && ![...main.querySelectorAll('.TC')].some(node => node.getClientRects().length && text(node))) return null;
  return JSON.stringify({origin:location.origin,folder:route,items});
})()
"""#

    private static let snapshot = #"""
(() => {
  if (window.top !== window || !['https://mail.naver.com','https://m.mail.naver.com'].includes(location.origin)) return null;
  if (!/^\/v2\/folders\/-?\d+(?:\/|$)/.test(location.pathname)) return null;
  const list = document.querySelector('.contents_area .mail_list_wrap > .mail_list');
  if (!list) return null;
  const text = node => (node?.textContent || '').trim().slice(0,500);
  const sender = node => {
    if (!node) return '';
    const label = node.cloneNode(true);
    label.querySelectorAll('.blind,[aria-hidden="true"]').forEach(child => child.remove());
    return text(label);
  };
  const items = [...list.querySelectorAll(':scope > .mail_item')].slice(0,30).flatMap(row => {
    const link = row.querySelector('.mail_title_link[href]');
    if (!link || link.origin !== location.origin || !/^\/v2\/read\/\d+\/\d+\/?$/.test(link.pathname)) return [];
    return [{
      path: link.pathname,
      subject: text(link.querySelector('.text')),
      sender: sender(row.querySelector('.mail_sender .button_sender')),
      time: text(row.querySelector('.mail_sender .mail_date')),
    }];
  });
  if (!items.length && !document.querySelector('.mail_list_wrap .no_mail,.contents_area .empty')) return null;
  return JSON.stringify({origin:location.origin,folder:location.pathname.split('/')[3],items});
})()
"""#
}
