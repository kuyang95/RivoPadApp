import SwiftUI
import SwiftMail

@MainActor
struct NaverConnectedMailView: View {
    @ObservedObject var browser: AccessibleWebBrowserModel
    let onBack: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var address = ""
    @State private var appPassword = ""
    @State private var linked = NaverMailCredentialStore.exists
    @State private var items: [NaverMailItem]?
    @State private var selected: NaverMailItem?
    @State private var messageBody: String?
    @State private var failure: LocalizedStringKey?
    @State private var task: Task<Void, Never>?
    private enum Field: Hashable { case address, password }
    @FocusState private var editing: Field?
    private var colors: RatioExperience { AccessibleWebTheme.colors }
    private var validAddress: Bool {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"^[A-Za-z0-9._%+-]+@naver\.com$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(linked ? "네이버 받은편지함" : "네이버 메일 연결")
                    .visionCraftAndroidText(30, weight: .semibold, relativeTo: .title)
                    .accessibilityAddTraits(.isHeader)
                if !address.isEmpty { Text(verbatim: address).visionCraftAndroidText(17) }
                if linked { action("웹메일 열기", perform: browser.showNaverWebMail).disabled(task != nil) }
                if task != nil {
                    ProgressView("메일을 여는 중").tint(colors.accent)
                }
                if let failure { Text(failure).visionCraftAndroidText(17).foregroundStyle(colors.accent) }
                if !linked {
                    setup
                } else if let selected {
                    Text(selected.subject ?? String(localized: "제목 없음"))
                        .visionCraftAndroidText(24, weight: .semibold).accessibilityAddTraits(.isHeader)
                    if let messageBody { Text(verbatim: messageBody).visionCraftAndroidText(18).textSelection(.enabled) }
                } else {
                    inbox
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.vertical, 36)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VisionCraftBackButton(tint: colors.text, action: back)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(colors.text)
        .onAppear {
            address = browser.mailAddressHint
            restoreIfActive()
        }
        .onChange(of: browser.youtubeContentActive) { _, _ in restoreIfActive() }
        .onChange(of: scenePhase) { _, _ in restoreIfActive() }
        .onChange(of: editing) { _, value in browser.mailEntryEditing = value != nil }
        .onDisappear { cancel(); browser.mailEntryEditing = false }
        .accessibilityAction(.escape, back)
    }

    private func back() {
        if selected != nil { backToInbox() } else { onBack() }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("네이버에서 IMAP을 켜고 앱 전용 비밀번호를 발급해 주세요. 연결하면 다음부터 바로 메일을 볼 수 있어요.")
                .visionCraftAndroidText(18)
            if browser.mailAddressHint.isEmpty {
                TextField("이메일 주소", text: $address)
                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().focused($editing, equals: .address)
                    .padding(16).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            }
            SecureField("앱 전용 비밀번호", text: $appPassword)
                .textContentType(.password).textInputAutocapitalization(.never)
                .autocorrectionDisabled().focused($editing, equals: .password).privacySensitive()
                .visionCraftAndroidText(20).padding(16)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            Button(action: connect) {
                Text("메일 연결").visionCraftAndroidText(20, weight: .semibold)
                    .foregroundStyle(VisionCraftUI.fixedColor(0x101010))
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(colors.accent, in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain).disabled(!validAddress || appPassword.isEmpty || task != nil)
            action("네이버 연결 방법") {
                openURL(URL(string: "https://help.naver.com/service/30029/contents/21351")!)
            }
            action("웹메일 열기", perform: browser.showNaverWebMail).disabled(task != nil)
        }
    }

    private var inbox: some View {
        VStack(alignment: .leading, spacing: 10) {
            action("새로고침", perform: loadInbox).disabled(task != nil)
            if let items {
                if items.isEmpty { Text("받은 메일이 없어요.").visionCraftAndroidText(18) }
                ForEach(items) { item in
                    Button { open(item) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.subject ?? String(localized: "제목 없음")).visionCraftAndroidText(20, weight: .medium)
                            if let sender = item.sender { Text(verbatim: sender).visionCraftAndroidText(16) }
                        }.frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(task != nil)
                    Divider()
                }
            }
            action("이 기기에서 연결 해제", perform: disconnect).disabled(task != nil)
        }
    }

    private func action(_ title: LocalizedStringKey, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).visionCraftAndroidText(17).frame(minHeight: 52)
        }.buttonStyle(.plain)
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        guard task == nil else { return }
        failure = nil
        task = Task {
            defer { task = nil }
            do {
                try await work()
            } catch is CancellationError {
                return
            } catch let error as IMAPError {
                guard !Task.isCancelled else { return }
                switch error {
                case .loginFailed, .authFailed:
                    failure = "네이버에서 연결을 승인하지 않았어요. IMAP 설정과 앱 전용 비밀번호를 확인해 주세요."
                default:
                    failure = "메일을 불러오지 못했어요. 잠시 후 다시 시도해 주세요."
                }
            } catch {
                if !Task.isCancelled { failure = "메일을 불러오지 못했어요. 잠시 후 다시 시도해 주세요." }
            }
        }
    }

    private func restoreIfActive() {
        guard browser.youtubeContentActive && scenePhase == .active else { cancel(); return }
        if linked && items == nil && failure == nil { loadInbox() }
    }

    private func loadInbox() {
        run {
            guard let credential = try NaverMailCredentialStore.read() else {
                linked = false
                items = nil
                return
            }
            if !address.isEmpty && address.caseInsensitiveCompare(credential.address) != .orderedSame {
                linked = false
                return
            }
            address = credential.address
            let loaded = try await NaverMailbox.inbox(credential)
            try Task.checkCancellation()
            items = loaded
            linked = true
        }
    }

    private func connect() {
        guard validAddress, !appPassword.isEmpty, task == nil else { return }
        let credential = NaverMailCredential(
            address: address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), appPassword: appPassword)
        appPassword = ""
        editing = nil
        run {
            let loaded = try await NaverMailbox.inbox(credential)
            try Task.checkCancellation()
            try NaverMailCredentialStore.save(credential)
            browser.rememberNaverMailLink()
            address = credential.address
            items = loaded
            linked = true
        }
    }

    private func open(_ item: NaverMailItem) {
        selected = item
        messageBody = nil
        run {
            guard let credential = try NaverMailCredentialStore.read() else {
                linked = false
                backToInbox()
                return
            }
            guard address.caseInsensitiveCompare(credential.address) == .orderedSame else {
                throw CancellationError()
            }
            let text = try await NaverMailbox.body(credential, item: item)
            try Task.checkCancellation()
            if let text { messageBody = text } else { failure = "이 메일은 웹메일에서 열어 주세요." }
        }
    }

    private func disconnect() {
        do {
            try NaverMailCredentialStore.remove()
            linked = false
            items = nil
            failure = nil
        } catch {
            failure = "메일을 불러오지 못했어요. 잠시 후 다시 시도해 주세요."
        }
    }

    private func backToInbox() {
        task?.cancel()
        selected = nil
        messageBody = nil
        failure = nil
    }

    private func cancel() {
        task?.cancel()
        appPassword = ""
        editing = nil
    }
}
