import SwiftUI

struct MailInboxKey: Hashable, Sendable {
    let accountID: String
    let folder: MailFolder
    let logoutVersion: Int

    @MainActor init(account: MailAccount, folder: MailFolder) {
        self.accountID = account.id
        self.folder = folder
        self.logoutVersion = MailWebLogout.shared.version(account.storeIdentifier)
    }
}

@MainActor
struct UnifiedMailInbox: View {
    @ObservedObject var browser: AccessibleWebBrowserModel
    @ObservedObject private var logout = MailWebLogout.shared
    let embedded: Bool
    let onClose: () -> Void
    let dialogColorScheme: ColorScheme
    let contentActive: Bool
    @Binding var accountID: String?
    @Binding var folder: MailFolder
    @Binding var scrollID: String?
    private enum Selection {
        case account, folder, compose, manageAccounts, chooseLogoutAccount
        case confirmLogout(MailAccount)
    }
    @State private var selection: Selection?
    @Binding var searchOpen: Bool
    @Binding var search: String
    @State private var refresh = 0
    @State private var completedRefresh = 0
    @State private var loading = false
    @State private var moreRequest = 0
    @State private var handledMore = 0
    @State private var loadingMore = false
    @State private var moreFailed = false

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
    private var isActive: Bool { contentActive && browser.youtubeContentActive && logout.storeInProgress == nil }
    private var results: [MailInboxKey: MailInboxResult] { browser.mailInboxResults }
    private func result(for account: MailAccount) -> MailInboxResult? { results[MailInboxKey(account: account, folder: folder)] }
    private var updatedAt: Date? {
        visibleAccounts.compactMap { account -> Date? in
            if case .loaded(_, let fetched, _) = result(for: account) { return fetched }
            return nil
        }.min()
    }

    private var hasMore: Bool {
        visibleAccounts.contains { account in
            if case .loaded(_, _, let next) = result(for: account) { return next != nil }
            return false
        }
    }

    private var messages: [MailInboxItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return visibleAccounts.flatMap { account -> [MailInboxItem] in
            if case .loaded(let messages, _, _) = result(for: account) { return messages }
            return []
        }.filter {
            query.isEmpty || $0.subject.localizedCaseInsensitiveContains(query) || $0.sender.localizedCaseInsensitiveContains(query)
        }.enumerated().sorted {
            $0.element.received == $1.element.received ? $0.offset < $1.offset : $0.element.received > $1.element.received
        }.map(\.element)
    }

    private struct RefreshKey: Equatable {
        let accounts: [MailAccount]
        let keys: [MailInboxKey]
        let refresh: Int
        let moreRequest: Int
        let active: Bool
        let folder: MailFolder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    headerSelectors
                    headerActions
                    Spacer(minLength: 0)
                }
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        headerSelectors
                        Spacer(minLength: 0)
                    }
                    headerActions
                }
            }.padding(.top, 4).padding(.bottom, 8)
            if searchOpen {
                TextField("메일 검색", text: $search).visionCraftAndroidText(18)
                    .padding(12).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.bottom, 8)
            }
            if supportsFolders {
                WidgetRefreshRow(updatedAt: updatedAt, ink: colors.text, busy: loading,
                                 enabled: isActive && !loadingMore, refreshLabel: "메일 새로고침") {
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
                        if !loading && messages.isEmpty && visibleAccounts.allSatisfy({ account in
                            if case .loaded = result(for: account) { return true }
                            return false
                        }) {
                            Text("표시할 메일이 없어요.").visionCraftAndroidText(18).padding(.vertical, 22)
                        }
                        if hasMore { moreFooter }
                    }.scrollTargetLayout()
                }.scrollPosition(id: $scrollID)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: RefreshKey(accounts: visibleAccounts, keys: visibleAccounts.map { MailInboxKey(account: $0, folder: folder) },
                             refresh: refresh, moreRequest: moreRequest, active: isActive, folder: folder)) {
            await load()
        }
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
                        if let selected = MailFolder(rawValue: $0.id), selected != folder {
                            completedRefresh = refresh
                            folder = selected
                        }
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
            case .manageAccounts:
                VisionCraftSelectionDialog(
                    title: "계정 관리",
                    options: [
                        VisionCraftSelectionOption(id: "add", title: AppLocalization.string("계정 추가"), enabled: logout.storeInProgress == nil),
                        VisionCraftSelectionOption(id: "logout", title: AppLocalization.string("로그아웃"),
                                                   enabled: !accounts.isEmpty && logout.storeInProgress == nil)
                    ],
                    selectedID: "",
                    onSelect: { option in
                        if option.id == "add" {
                            selection = nil
                            browser.showMailStart()
                        } else if accounts.count == 1, let account = accounts.first {
                            selection = .confirmLogout(account)
                        } else { selection = .chooseLogoutAccount }
                    },
                    onDismiss: { selection = nil },
                    compactDismiss: true
                ).environment(\.colorScheme, dialogColorScheme)
            case .chooseLogoutAccount:
                VisionCraftSelectionDialog(
                    title: "로그아웃할 계정",
                    options: accounts.map { VisionCraftSelectionOption(id: $0.id, title: $0.headerLabel, accessibilityLabel: $0.label) },
                    selectedID: "",
                    onSelect: { option in
                        if let account = accounts.first(where: { $0.id == option.id }) {
                            selection = .confirmLogout(account)
                        }
                    },
                    onDismiss: { selection = nil },
                    dismissTitle: "취소",
                    compactDismiss: true
                ).environment(\.colorScheme, dialogColorScheme)
            case .confirmLogout(let account):
                logoutConfirmation(account).environment(\.colorScheme, dialogColorScheme)
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
        options.append(VisionCraftSelectionOption(id: "manage", title: AppLocalization.string("계정 관리")))
        if !embedded { options.append(VisionCraftSelectionOption(id: "exit", title: String(localized: "메일 닫기"))) }
        return options
    }

    private func selectAccountOption(_ option: VisionCraftSelectionOption) {
        selection = nil
        switch option.id {
        case "manage": selection = .manageAccounts
        case "exit": onClose()
        default:
            let selectedID = option.id == "all" ? nil : option.id
            if accountID != selectedID || folder != .inbox { completedRefresh = refresh }
            accountID = selectedID
            folder = .inbox
            scrollID = nil
        }
    }

    private func logoutConfirmation(_ account: MailAccount) -> some View {
        let busy = logout.storeInProgress != nil
        let message = AppLocalization.format(account.provider.id == "gmail"
            ? "%@에서 로그아웃할까요? 리보에 연결된 다른 Gmail 계정과 유튜브도 함께 로그아웃돼요."
            : "%@에서 로그아웃할까요?", account.label)
        var notices = [VisionCraftSelectionNotice(text: message)]
        if busy { notices.append(VisionCraftSelectionNotice(text: AppLocalization.string("로그아웃 중…"))) }
        return VisionCraftSelectionDialog(
            title: "로그아웃 확인",
            options: [VisionCraftSelectionOption(id: "logout", title: AppLocalization.string("로그아웃"), enabled: !busy)],
            selectedID: "",
            onSelect: { _ in
                Task { @MainActor in
                    await logout.signOut(account)
                    selection = nil
                }
            },
            onDismiss: { if logout.storeInProgress == nil { selection = nil } },
            notices: notices,
            dismissTitle: "취소",
            compactDismiss: true
        )
    }

    private var divider: some View { Rectangle().fill(colors.text.opacity(0.2)).frame(height: 1).accessibilityHidden(true) }

    @ViewBuilder private var headerSelectors: some View {
        Button { selection = .account } label: {
            headerControl(selectedAccount?.headerLabel ?? String(localized: "모든 계정"), fontSize: 18)
        }.buttonStyle(.plain).layoutPriority(-1)
        Button { selection = .folder } label: {
            headerControl(supportsFolders ? folder.title : String(localized: "메일함"), fontSize: 17)
        }.buttonStyle(.plain).disabled(!supportsFolders).opacity(supportsFolders ? 1 : 0.55)
    }

    private var headerActions: some View {
        let shape = RoundedRectangle(cornerRadius: 16)
        let canCompose = !accounts.isEmpty && logout.storeInProgress == nil
        return HStack(spacing: 0) {
            Button {
                searchOpen.toggle()
                if !searchOpen { search = "" }
            } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 22))
                    .frame(width: 48, height: 56).contentShape(Rectangle())
                    .background(searchOpen ? colors.text.opacity(0.12) : .clear)
            }.buttonStyle(.plain).accessibilityLabel("메일 검색")
                .accessibilityAddTraits(searchOpen ? .isSelected : [])
                .disabled(!supportsFolders).opacity(supportsFolders ? 1 : 0.45)
            Rectangle().fill(colors.text.opacity(0.35)).frame(width: 1, height: 24).accessibilityHidden(true)
            Button { selection = .compose } label: {
                Image(systemName: "pencil").font(.system(size: 22))
                    .frame(width: 48, height: 56).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("메일 작성")
                .disabled(!canCompose).opacity(canCompose ? 1 : 0.45)
        }
        .fixedSize()
        .clipShape(shape)
        .overlay(shape.strokeBorder(colors.text.opacity(0.55)).allowsHitTesting(false))
    }

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

    private var moreFooter: some View {
        let shape = RoundedRectangle(cornerRadius: 16)
        return VStack(alignment: .leading, spacing: 8) {
            if moreFailed {
                Text("메일을 더 불러오지 못했어요. 다시 시도해 주세요.").visionCraftAndroidText(16)
            }
            Button { moreRequest += 1 } label: {
                Text(loadingMore ? "메일 더 불러오는 중" : "메일 더 불러오기")
                    .visionCraftAndroidText(18, weight: .semibold)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(shape)
                    .overlay { shape.strokeBorder(colors.text.opacity(0.55)).allowsHitTesting(false) }
            }
            .buttonStyle(.plain)
            .disabled(!isActive || loading || loadingMore)
        }.padding(.vertical, 16)
    }

    private struct Request: Sendable {
        let account: MailAccount
        let key: MailInboxKey
        let after: String?
    }

    private func load() async {
        guard !Task.isCancelled else { return }
        let requestedMore = moreRequest != handledMore
        handledMore = moreRequest
        loading = false
        loadingMore = false
        moreFailed = false
        guard isActive, !supportsFolders || availableFolders.contains(folder) else { return }
        let requestedFolder = folder
        let requestedRefresh = refresh
        let registered = Dictionary(accounts.map { ($0.id, $0.storeIdentifier) }, uniquingKeysWith: { first, _ in first })
        let current = results.filter { key, _ in
            guard let identifier = registered[key.accountID] else { return false }
            return key.logoutVersion == logout.version(identifier)
        }
        if current.count != results.count { browser.mailInboxResults = current }
        let requested = visibleAccounts.filter { $0.supports(requestedFolder) }
            .map { ($0, MailInboxKey(account: $0, folder: requestedFolder)) }
        let firstPages = requested.filter { requestedRefresh != completedRefresh || results[$0.1] == nil }
        let more = requestedMore && firstPages.isEmpty
        let pending: [Request]
        if more {
            pending = requested.compactMap { account, key in
                guard case .loaded(_, _, let next?) = results[key] else { return nil }
                return Request(account: account, key: key, after: next)
            }
        } else {
            pending = firstPages.map { Request(account: $0.0, key: $0.1, after: nil) }
        }
        guard !pending.isEmpty else { return }
        loading = !more
        loadingMore = more
        defer {
            if !Task.isCancelled {
                loading = false
                loadingMore = false
            }
        }
        // Keep the accounts that share one web data store in order.
        let batches = Dictionary(grouping: pending) { $0.account.storeIdentifier }
        let fetch: @Sendable ([Request]) async -> [MailInboxKey: MailInboxResult] = { batch in
            var loaded: [MailInboxKey: MailInboxResult] = [:]
            for request in batch {
                guard !Task.isCancelled else { break }
                loaded[request.key] = await MailInboxReader.read(request.account, folder: requestedFolder, after: request.after)
            }
            return loaded
        }
        let loaded = await withTaskGroup(of: [MailInboxKey: MailInboxResult].self) { group in
            var queue = batches.values.makeIterator()
            for _ in 0..<2 {
                if let batch = queue.next() { _ = group.addTaskUnlessCancelled { await fetch(batch) } }
            }
            var results: [MailInboxKey: MailInboxResult] = [:]
            while let batch = await group.next() {
                results.merge(batch) { _, latest in latest }
                if let next = queue.next() { _ = group.addTaskUnlessCancelled { await fetch(next) } }
            }
            return results
        }
        guard !Task.isCancelled, browser.mailInbox, isActive else { return }
        var updates: [MailInboxKey: MailInboxResult] = [:]
        for (key, result) in loaded {
            if more {
                guard case .loaded(let existing, let fetched, _) = results[key],
                      case .loaded(let additional, _, let next) = result else {
                    moreFailed = true
                    continue
                }
                var seen = Set(existing.map(\.id))
                updates[key] = .loaded(existing + additional.filter { seen.insert($0.id).inserted }, fetched: fetched, next: next)
            } else {
                if case .unavailable = result, case .loaded = results[key] { continue }
                updates[key] = result
            }
        }
        if !updates.isEmpty { browser.mailInboxResults.merge(updates) { _, latest in latest } }
        if !more { completedRefresh = requestedRefresh }
    }
}
