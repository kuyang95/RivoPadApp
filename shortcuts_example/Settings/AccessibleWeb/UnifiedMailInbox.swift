import SwiftUI

struct MailInboxKey: Hashable {
    let accountID: String
    let folder: MailFolder
}

@MainActor
struct UnifiedMailInbox: View {
    @ObservedObject var browser: AccessibleWebBrowserModel
    @ObservedObject private var googleConnection = GoogleWebSession.shared
    let embedded: Bool
    let onClose: () -> Void
    let dialogColorScheme: ColorScheme
    @Binding var accountID: String?
    @Binding var folder: MailFolder
    @Binding var scrollID: String?
    private enum Selection { case account, folder, compose }
    @State private var selection: Selection?
    @Binding var searchOpen: Bool
    @Binding var search: String
    @State private var refresh = 0
    @Binding var results: [MailInboxKey: MailInboxResult]
    @State private var loading = false

    private var colors: RatioExperience { AccessibleWebTheme.colors }
    private var accounts: [MailAccount] { browser.mailAccounts }
    private var visibleAccounts: [MailAccount] { accounts.filter { accountID == nil || $0.id == accountID } }
    private var selectedAccount: MailAccount? {
        accounts.first { $0.id == accountID } ?? (accounts.count == 1 ? accounts.first : nil)
    }
    private var availableFolders: [MailFolder] {
        let supported = visibleAccounts.filter(\.hasInbox)
        return MailFolder.allCases.filter { option in !supported.isEmpty && supported.allSatisfy { $0.supports(option) } }
    }
    private var supportsFolders: Bool { !availableFolders.isEmpty }
    private func result(for account: MailAccount) -> MailInboxResult? { results[MailInboxKey(accountID: account.id, folder: folder)] }
    private var updatedAt: Date? {
        visibleAccounts.compactMap { account -> Date? in
            if case .loaded(_, let fetched) = result(for: account) { return fetched }
            return nil
        }.min()
    }

    private var messages: [MailInboxItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return visibleAccounts.flatMap { account -> [MailInboxItem] in
            if case .loaded(let messages, _) = result(for: account) { return messages }
            return []
        }.filter {
            query.isEmpty || $0.subject.localizedCaseInsensitiveContains(query) || $0.sender.localizedCaseInsensitiveContains(query)
        }.enumerated().sorted {
            $0.element.received == $1.element.received ? $0.offset < $1.offset : $0.element.received > $1.element.received
        }.map(\.element)
    }

    private struct RefreshKey: Equatable {
        let accounts: [MailAccount]
        let revision: Int
        let refresh: Int
        let active: Bool
        let folder: MailFolder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { selection = .account } label: {
                    headerControl(selectedAccount?.headerLabel ?? String(localized: "모든 계정"), fontSize: 18)
                }.buttonStyle(.plain).layoutPriority(-1)
                Button { selection = .folder } label: {
                    headerControl(supportsFolders ? folder.title : String(localized: "메일함"), fontSize: 17)
                }.buttonStyle(.plain).disabled(!supportsFolders).opacity(supportsFolders ? 1 : 0.55)
                Button {
                    searchOpen.toggle()
                    if !searchOpen { search = "" }
                } label: {
                    Image(systemName: "magnifyingglass").font(.title3)
                        .frame(minWidth: 48, minHeight: 48).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("메일 검색").disabled(!supportsFolders)
                Spacer(minLength: 0)
            }.padding(.top, 4).padding(.bottom, 8)
            if searchOpen {
                TextField("메일 검색", text: $search).visionCraftAndroidText(18)
                    .padding(12).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.bottom, 8)
            }
            if supportsFolders {
                WidgetRefreshRow(updatedAt: updatedAt, ink: colors.text, busy: loading,
                                 enabled: browser.youtubeContentActive, refreshLabel: "메일 새로고침") {
                    scrollID = nil
                    refresh += 1
                }
            } else {
                divider
            }
            if loading { ProgressView().progressViewStyle(.linear).tint(colors.accent) }
            if !accounts.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleAccounts) { account in
                            if let status = status(for: account) {
                                Button { browser.openMailAccount(account) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(verbatim: account.label).visionCraftAndroidText(18)
                                        Text(status).visionCraftAndroidText(15).foregroundStyle(colors.accent)
                                    }.frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                divider
                            }
                        }
                        ForEach(messages) { item in
                            row(item)
                                .id(item.id)
                            divider
                        }
                        if !loading && messages.isEmpty && visibleAccounts.allSatisfy({ status(for: $0) == nil }) {
                            Text("표시할 메일이 없어요.").visionCraftAndroidText(18).padding(.vertical, 22)
                        }
                    }.scrollTargetLayout()
                }.scrollPosition(id: $scrollID)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: RefreshKey(accounts: visibleAccounts, revision: browser.mailInboxRevision, refresh: refresh,
                             active: browser.youtubeContentActive, folder: folder)) { await load() }
        .onChange(of: availableFolders) { _, options in
            if !options.isEmpty && !options.contains(folder) { folder = .inbox }
        }
        .onChange(of: folder) { _, _ in scrollID = nil }
        .accessibilityHidden(selection != nil)
        .overlay {
            switch selection {
            case .folder:
                VisionCraftSelectionDialog(
                    title: "메일함",
                    options: availableFolders.map { VisionCraftSelectionOption(id: $0.rawValue, title: $0.title) },
                    selectedID: folder.rawValue,
                    onSelect: {
                        if let selected = MailFolder(rawValue: $0.id) { folder = selected }
                        selection = nil
                    },
                    onDismiss: { selection = nil },
                    markSelected: true,
                    compactDismiss: true
                ).environment(\.colorScheme, dialogColorScheme)
            case .account:
                VisionCraftSelectionDialog(
                    title: "계정",
                    options: accountOptions,
                    selectedID: accountID ?? "all",
                    onSelect: selectAccountOption,
                    onDismiss: { selection = nil },
                    markSelected: true,
                    compactDismiss: true
                ).environment(\.colorScheme, dialogColorScheme)
            case .compose:
                VisionCraftSelectionDialog(
                    title: "메일 작성",
                    options: accounts.map { VisionCraftSelectionOption(id: $0.id, title: $0.headerLabel) },
                    selectedID: "",
                    onSelect: { option in
                        selection = nil
                        if let account = accounts.first(where: { $0.id == option.id }) {
                            browser.openMailAccount(account, compose: true)
                        }
                    },
                    onDismiss: { selection = nil },
                    compactDismiss: true
                ).environment(\.colorScheme, dialogColorScheme)
            case nil:
                EmptyView()
            }
        }
    }

    private var accountOptions: [VisionCraftSelectionOption] {
        var options = [VisionCraftSelectionOption(id: "all", title: String(localized: "모든 계정"))]
        options += accounts.map { VisionCraftSelectionOption(id: $0.id, title: $0.headerLabel) }
        options.append(VisionCraftSelectionOption(id: "google-gmail",
            title: AppLocalization.string(googleConnection.gmailSignedIn == false ? "Gmail 로그인" : "Gmail 열기")))
        if !accounts.isEmpty { options.append(VisionCraftSelectionOption(id: "compose", title: String(localized: "메일 작성"))) }
        if !embedded { options.append(VisionCraftSelectionOption(id: "exit", title: String(localized: "메일 닫기"))) }
        options.append(VisionCraftSelectionOption(id: "add", title: String(localized: "계정 추가")))
        return options
    }

    private func selectAccountOption(_ option: VisionCraftSelectionOption) {
        selection = nil
        switch option.id {
        case "google-gmail": browser.connectSharedGoogleLogin()
        case "add": browser.showMailStart()
        case "compose": selection = .compose
        case "exit": onClose()
        default:
            accountID = option.id == "all" ? nil : option.id
            folder = .inbox
            scrollID = nil
        }
    }

    private var divider: some View { Rectangle().fill(colors.text.opacity(0.2)).frame(height: 1).accessibilityHidden(true) }

    private func headerControl(_ title: String, fontSize: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: title).visionCraftAndroidText(fontSize, weight: .semibold)
                .lineLimit(1).truncationMode(.tail)
            Image(systemName: "chevron.down").font(.footnote).accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(colors.text.opacity(0.55)).allowsHitTesting(false) }
        .accessibilityLabel(Text(verbatim: title))
    }

    private func status(for account: MailAccount) -> LocalizedStringKey? {
        if !account.hasInbox { return "웹메일 열기" }
        switch result(for: account) {
        case .signIn: return "다시 로그인"
        case .unavailable: return "목록을 불러오지 못했어요. 웹메일 열기"
        default: return nil
        }
    }

    private func row(_ item: MailInboxItem) -> some View {
        let subject = item.subject.isEmpty ? String(localized: "제목 없음") : item.subject
        let metadata = [item.sender, item.time].filter { !$0.isEmpty }.joined(separator: " · ")
        let announcement = [subject, metadata]
            .filter { !$0.isEmpty }.joined(separator: ", ")
        return Button { browser.openMailAccount(item.account, target: item.url) } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: subject)
                    .visionCraftAndroidText(21, weight: .medium).lineLimit(2)
                Text(verbatim: metadata).visionCraftAndroidText(15).foregroundStyle(colors.text.opacity(0.78)).lineLimit(1)
            }.frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                .padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(Text(verbatim: announcement))
    }

    private func load() async {
        guard browser.youtubeContentActive else { return }
        let supported = visibleAccounts.filter { $0.supports(folder) }
        let requestedFolder = folder
        results = results.filter { key, _ in accounts.contains { $0.id == key.accountID } }
        loading = !supported.isEmpty
        defer { if !Task.isCancelled { loading = false } }
        for account in supported {
            let key = MailInboxKey(accountID: account.id, folder: requestedFolder)
            let result = await MailInboxReader.read(account, folder: requestedFolder)
            guard !Task.isCancelled else { return }
            if case .unavailable = result, case .loaded = results[key] { continue }
            results[key] = result
        }
    }
}
