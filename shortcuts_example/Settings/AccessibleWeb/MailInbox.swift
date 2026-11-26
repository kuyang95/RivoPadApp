import Foundation
import WebKit

struct MailAccount: Identifiable, Equatable, Sendable {
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

enum MailFolder: String, CaseIterable, Identifiable, Sendable {
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

struct MailInboxItem: Identifiable, Sendable {
    let account: MailAccount
    let url: String
    let subject: String
    let sender: String
    let time: String
    let received: Date
    var id: String { "\(account.id):\(url)" }
}

enum MailInboxResult: Sendable {
    case loaded([MailInboxItem], fetched: Date, next: String?), signIn, unavailable
}

@MainActor
enum MailInboxReader {
    static func read(_ account: MailAccount, folder: MailFolder, after: String? = nil) async -> MailInboxResult {
        let identifier = account.storeIdentifier
        let logout = MailWebLogout.shared
        guard account.supports(folder), logout.storeInProgress != identifier else { return .unavailable }
        let version = logout.version(identifier)
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
        let snapshot = gmail ? gmailSnapshot : naverSnapshot
        let expectedFolder = jsonLiteral(gmail ? (folder.gmailRoute ?? "") : folder.rawValue)
        let address = jsonLiteral(account.address)
        let anchor = jsonLiteral(after ?? "")
        var waiting = ""
        var reached = false
        var advancedAt = 0
        for poll in 0..<(after == nil ? 36 : 60) {
            do { try await Task.sleep(for: .milliseconds(350)) }
            catch { return .unavailable }
            guard let url = view.url, url.scheme == "https", let host = url.host, url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { continue }
            if !view.isLoading, account.provider.authHosts.contains(host) { return .signIn }
            let expectedHost = gmail ? host == "mail.google.com" : account.provider.nativeInboxHosts.contains(host)
            guard expectedHost, gmail || !view.isLoading else { continue }
            // The Gmail snapshot verifies the account, folder and rows. Other resources can still be loading.
            let script = """
            (() => {
              const RIVO_FOLDER = \(expectedFolder);
              const RIVO_ADDRESS = \(address);
              const RIVO_ANCHOR = \(anchor);
              const RIVO_WAITING = \(jsonLiteral(waiting));
              const RIVO_REACHED = \(reached);
              const RIVO_SETTLED = \(poll - advancedAt >= 9);
              \(pagination)
              return (\(snapshot));
            })()
            """
            guard let raw = (try? await view.evaluateJavaScript(script)) as? String,
                  let payload = try? JSONDecoder().decode(Payload.self, from: Data(raw.utf8)) else { continue }
            // Advancing the provider can synchronously change its URL. Only snapshots must match the sampled URL.
            if after != nil, let marker = payload.waiting {
                waiting = marker
                reached = payload.reached == true
                advancedAt = poll
                continue
            }
            guard view.url == url, let result = decode(payload, account: account, folder: folder) else { continue }
            guard !Task.isCancelled, logout.storeInProgress != identifier, logout.version(identifier) == version else { return .unavailable }
            if gmail { GoogleWebSession.shared.update(youtube: false, value: true) }
            return result
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
        let origin: String?
        let folder: String?
        let items: [Row]?
        let more: Bool?
        let waiting: String?
        let reached: Bool?
    }

    private static func decode(_ payload: Payload, account: MailAccount, folder: MailFolder) -> MailInboxResult? {
        guard let origin = payload.origin, let rows = payload.items else { return nil }
        let gmail = account.provider.id == "gmail"
        if gmail {
            guard origin == "https://mail.google.com", payload.folder == folder.gmailRoute else { return nil }
        } else {
            guard payload.folder == folder.rawValue,
                  ["https://mail.naver.com", "https://m.mail.naver.com"].contains(origin) else { return nil }
        }
        let items: [MailInboxItem] = rows.prefix(30).compactMap { row in
            if gmail {
                guard let url = URLComponents(string: origin + row.path),
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
            return MailInboxItem(account: account, url: origin + row.path,
                subject: String(row.subject.prefix(500)), sender: String(row.sender.prefix(500)),
                time: String(row.time.prefix(80)), received: gmail ? Date(timeIntervalSince1970: max(0, row.received ?? 0) / 1000) : received(row.time))
        }
        guard items.count == rows.count else { return nil }
        return .loaded(items, fetched: Date(), next: payload.more == true ? rows.last?.path : nil)
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
  const currentRoute = location.hash.slice(1);
  if (!expected || (currentRoute !== route &&
      (!RIVO_ANCHOR || !currentRoute.startsWith(route + '/') || !/^p[0-9]+$/.test(currentRoute.slice(route.length + 1))))) return null;
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
  const path = row => {
    if (!row) return null;
    const legacy = row.getAttribute('data-legacy-thread-id') || row.querySelector('[data-legacy-thread-id]')?.getAttribute('data-legacy-thread-id') || '';
    if (!/^[a-f0-9]{10,32}$/i.test(legacy)) return null;
    return location.pathname + '?authuser=' + encodeURIComponent(RIVO_ADDRESS) + '&ui=2&view=pt&search=all&th=' + legacy;
  };
  const read = row => {
    const url = path(row);
    const subject = row.querySelector('.bog');
    const sender = row.querySelector('.yW');
    const date = row.querySelector('.xW [title]');
    if (!url || !subject || !sender || !date) return null;
    return {path:url, subject:text(subject), sender:text(sender), time:text(date).slice(0,80),
      received:timestamp(date.getAttribute('title') || '')};
  };
  // An unknown/new DOM must not turn into an apparently empty mailbox.
  if (!rows.length && ![...main.querySelectorAll('.TC')].some(node => node.getClientRects().length && text(node))) return null;
  const older = [...document.querySelectorAll('.amD[role="button"],[role="button"][data-tooltip],[role="button"][aria-label],button[aria-label]')]
    .find(node => node.getClientRects().length && !node.closest('tr.zA') &&
      (node.matches('.amD[role="button"]') ||
        [node.getAttribute('data-tooltip'), node.getAttribute('aria-label')]
          .some(label => /^(?:older(?: (?:messages|conversations))?|이전(?: 메일)?|오래된 메일|古い(?:メール)?)(?:\s*\([^)]*\))?$/i.test(label?.trim() || ''))));
  return page(rows, path, read, route, older);
})()
"""#

    private static let naverSnapshot = #"""
(() => {
  if (window.top !== window || !['https://mail.naver.com','https://m.mail.naver.com'].includes(location.origin)) return null;
  if (!/^\/v2\/folders\/-?\d+(?:\/|$)/.test(location.pathname)) return null;
  const folder = location.pathname.split('/')[3];
  if (folder !== RIVO_FOLDER) return null;
  const list = document.querySelector('.contents_area .mail_list_wrap > .mail_list');
  if (!list) return null;
  const text = node => (node?.textContent || '').trim().slice(0,500);
  const sender = node => {
    if (!node) return '';
    const label = node.cloneNode(true);
    label.querySelectorAll('.blind,[aria-hidden="true"]').forEach(child => child.remove());
    return text(label);
  };
  const rows = [...list.querySelectorAll(':scope > .mail_item')];
  const path = row => {
    const link = row?.querySelector('.mail_title_link[href]');
    return link && link.origin === location.origin && /^\/v2\/read\/\d+\/\d+\/?$/.test(link.pathname)
      ? link.pathname : null;
  };
  const read = row => ({
    path: path(row),
    subject: text(row.querySelector('.mail_title_link .text')),
    sender: sender(row.querySelector('.mail_sender .button_sender')),
    time: text(row.querySelector('.mail_sender .mail_date')),
  });
  const available = rows.filter(path);
  if (!available.length && !document.querySelector('.mail_list_wrap .no_mail,.contents_area .empty')) return null;
  const wrap = list.parentElement;
  const next = [...wrap.parentElement.querySelectorAll('button,a[href],[role="button"]')].find(node =>
    !node.closest('.mail_item') && node.getClientRects().length &&
    (!node.matches('a[href]') || (node.origin === location.origin && node.pathname === location.pathname)) &&
    !!(list.compareDocumentPosition(node) & Node.DOCUMENT_POSITION_FOLLOWING) &&
    [node.getAttribute('aria-label'), node.getAttribute('title'), text(node)].some(label =>
      /^(?:목록\s*더\s*보기|메일\s*더\s*보기|더\s*보기|다음\s*페이지|(?:load|show) more(?: (?:mail|messages))?|more|next page|もっと見る|さらに表示|次のページ)$/i.test(label?.trim() || '')));
  const last = available.at(-1);
  const scroll = last ? () => last.scrollIntoView({block:'end'}) : null;
  const scrollMayLoadMore = !next && !!last &&
    (available.length >= 30 || last.getBoundingClientRect().bottom > window.innerHeight);
  return page(available, path, read, folder, next, scroll, scrollMayLoadMore);
})()
"""#

    private static let pagination = #"""
function page(rows, path, read, folder, next, scrollToEnd, scrollMayLoadMore = false) {
  const anchor = RIVO_ANCHOR;
  const waiting = RIVO_WAITING;
  const reached = RIVO_REACHED;
  const marker = JSON.stringify([rows.length, path(rows[0]), path(rows.at(-1))]);
  const anchorIndex = anchor ? rows.findIndex(row => path(row) === anchor) : -1;
  const publish = (items, more) => JSON.stringify({origin: location.origin, folder, items, more});
  const enabled = next && !next.disabled && next.getAttribute('aria-disabled') !== 'true';
  if (waiting === marker) {
    // In scroll mode there may be no button or page count to signal the end.
    if (scrollToEnd && !next && RIVO_SETTLED && reached) return publish([], false);
    return null;
  }

  const afterAnchor = !anchor || anchorIndex >= 0 || reached;
  if (afterAnchor) {
    const remaining = rows.slice(anchorIndex + 1);
    const items = remaining.slice(0, 30).map(read);
    if (items.some(item => !item)) return null;
    if (!anchor || items.length) {
      return publish(items, items.length > 0 && (remaining.length > items.length || !!enabled || scrollMayLoadMore));
    }
  }
  if (enabled) next.click();
  else if (scrollToEnd && !next) scrollToEnd();
  else return afterAnchor ? publish([], false) : null;
  return JSON.stringify({waiting: marker, reached: afterAnchor});
}
"""#
}
