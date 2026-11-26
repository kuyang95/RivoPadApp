import SwiftUI
import WebKit

@MainActor
struct EasyMailBrowserView: View {
    @ObservedObject var browser: AccessibleWebBrowserModel
    let embedded: Bool
    let onClose: () -> Void
    let dialogColorScheme: ColorScheme
    let showsInboxBackButton: Bool
    let contentActive: Bool
    @Environment(\.openURL) private var openURL
    @State private var address = ""
    @State private var retryProvider: EasyMailProvider?
    @State private var custom = ""
    @State private var showCustom = false
    @State private var message: LocalizedStringKey?
    @State private var inboxAccountID: String?
    @State private var inboxFolder = MailFolder.inbox
    @State private var inboxSearchOpen = false
    @State private var inboxSearch = ""
    @State private var inboxScrollID: String?
    @FocusState private var editing: Bool
    private var theme: RatioExperience { AccessibleWebTheme.colors }

    var body: some View {
        VStack(spacing: 0) {
            if browser.mailInbox {
                UnifiedMailInbox(browser: browser, embedded: embedded, onClose: onClose, dialogColorScheme: dialogColorScheme,
                                 contentActive: contentActive, accountID: $inboxAccountID, folder: $inboxFolder,
                                 scrollID: $inboxScrollID, searchOpen: $inboxSearchOpen, search: $inboxSearch)
            } else if browser.mailStart {
                if browser.mailDirectConnection { NaverConnectedMailView(browser: browser, onBack: back) }
                else if browser.mailPasswordRequired {
                    NativeMailPasswordView(browser: browser) {
                        retryProvider = browser.mailProvider
                        address = browser.mailAddressHint
                        browser.showMailStart()
                    }
                }
                else { start }
            }
            else {
                if !browser.mailAuthenticating, let error = browser.errorMessage {
                    VStack(alignment: .leading) {
                        Text(error).visionCraftAndroidText(17)
                        Button("새로고침") { browser.webView.reload() }.frame(minHeight: 48)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
                }
                ZStack {
                    let webAvailable = contentActive && !browser.mailLoginHidesWeb && !browser.naverMailBlocksInput && browser.mailReaderActions == nil
                    AccessibleWebSurface(webView: browser.webView, interactionAvailable: webAvailable)
                        .opacity(browser.mailLoginHidesWeb ? 0 : 1)
                        .allowsHitTesting(webAvailable)
                        .accessibilityHidden(!webAvailable)
                        .overlay(alignment: .top) {
                            if browser.isLoading && !browser.mailLoginHidesWeb {
                                ProgressView().progressViewStyle(.linear).tint(theme.accent)
                                    .frame(height: 2).accessibilityLabel("불러오는 중")
                            }
                        }
                    if browser.mailLoginHidesWeb {
                        NativeMailLoadingView(onCancel: browser.cancelMailLogin)
                    } else if browser.naverMailBlocksInput {
                        ZStack {
                            Color.black.opacity(0.32).accessibilityHidden(true)
                            Text("메일을 여는 중").visionCraftAndroidText(20)
                                .padding(.horizontal, 24).padding(.vertical, 16)
                                .background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if browser.mailInbox ? showsInboxBackButton : !(browser.mailStart && browser.mailDirectConnection) {
                HStack {
                    VisionCraftBackButton(tint: theme.text, action: back)
                    Spacer(minLength: 0)
                    if !embedded && !browser.mailInbox && !browser.mailStart && !browser.mailLoginHidesWeb {
                        Button("닫기", action: onClose).frame(minHeight: 52)
                    }
                }
                .padding(.horizontal, embedded ? 0 : 16)
            }
        }
        .foregroundStyle(theme.text).tint(theme.accent)
        .background((embedded ? Color.clear : theme.background).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: editing) { _, value in browser.mailEntryEditing = value }
        .onDisappear { browser.mailEntryEditing = false }
        .visionCraftHandlesBackNavigation()
        .accessibilityAction(.escape, back)
        .accessibilityHidden(browser.mailReaderActions != nil)
        .overlay {
            if let dialog = browser.mailReaderActions {
                VisionCraftSelectionDialog(
                    title: "메일 작업",
                    options: dialog.options.map { VisionCraftSelectionOption(id: $0.rawValue, title: $0.title) },
                    selectedID: "",
                    onSelect: { browser.finishMailReaderActions(MailReaderAction(rawValue: $0.id)) },
                    onDismiss: { browser.finishMailReaderActions() },
                    compactDismiss: true
                ).environment(\.colorScheme, dialogColorScheme)
            }
        }
    }


    private var start: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        entryHeader
                        if browser.mailChoosingProvider { providerSelection }
                        else {
                            addressEntry
                            if browser.mailProvider?.id == "naver", NaverMailCredentialStore.exists {
                                Button("네이버 받은편지함", action: browser.showNaverConnection)
                                    .visionCraftAndroidText(17).padding(.top, 12).frame(minHeight: 52)
                            }
                        }
                        if !embedded {
                            Button("닫기", action: onClose)
                                .visionCraftAndroidText(17).padding(.top, 18).frame(minHeight: 52)
                        }
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 28).padding(.vertical, 40)
                .frame(minHeight: geometry.size.height, alignment: browser.mailChoosingProvider ? .top : .center)
            }
            .scrollDismissesKeyboard(.interactively)
            .id(browser.mailChoosingProvider)
        }
        .onChange(of: browser.mailChoosingProvider) { _, _ in message = nil; showCustom = false; editing = false }
    }

    private var entryHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !browser.mailChoosingProvider {
                Image(systemName: "envelope")
                    .font(.system(size: 40, weight: .regular)).foregroundStyle(theme.text.opacity(0.8))
                    .accessibilityHidden(true).padding(.bottom, 26)
            }
            Text(browser.mailChoosingProvider ? LocalizedStringKey("메일 서비스를\n선택해 주세요") : LocalizedStringKey("이메일 주소를\n입력해 주세요"))
                .visionCraftAndroidText(36, weight: .medium, relativeTo: .largeTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, browser.mailChoosingProvider ? 16 : 36)
        }
    }

    private var addressEntry: some View {
        VStack(alignment: .leading, spacing: 0) {
            entryField("이메일 주소", placeholder: "name@example.com", text: $address, email: true, submit: proceed)
                .onChange(of: address) { _, _ in message = nil }
            entryError
            continueButton("계속", fill: theme.magnifier, ink: theme.text, border: theme.text, action: proceed)
                .padding(.top, 18)
        }
    }

    private var providerSelection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: trimmed).visionCraftAndroidText(18)
                .foregroundStyle(theme.text.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 26)
            ForEach(EasyMailProvider.all) { provider in
                providerRow(Text(verbatim: provider.name)) { open(provider) }
            }
            providerRow(Text("다른 메일")) { showCustom.toggle(); message = nil }
            if showCustom {
                entryField("메일 사이트 주소", placeholder: "https://", text: $custom, email: false, submit: openCustom)
                    .padding(.top, 20).onChange(of: custom) { _, _ in message = nil }
                entryError
                continueButton("열기", fill: theme.accent, action: openCustom).padding(.top, 16)
            }
        }
    }

    private func entryField(_ label: LocalizedStringKey, placeholder: String, text: Binding<String>, email: Bool,
                            submit: @escaping () -> Void) -> some View {
        TextField(text: text, prompt: Text(verbatim: placeholder).foregroundStyle(theme.text.opacity(0.65))) { Text(label) }
            .visionCraftAndroidText(22)
            .textContentType(email ? .emailAddress : .URL).keyboardType(email ? .emailAddress : .URL)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .focused($editing).submitLabel(.go).onSubmit(submit)
            .padding(.horizontal, 20).padding(.vertical, 19).frame(minHeight: 76)
            .background(.white.opacity(editing ? 0.08 : 0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(message != nil ? Color(red: 1, green: 180/255, blue: 171/255) : editing ? theme.accent : theme.text.opacity(0.5), lineWidth: editing ? 2 : 1))
            .accessibilityLabel(Text(label))
    }

    @ViewBuilder private var entryError: some View {
        if let message {
            Text(message).visionCraftAndroidText(17)
                .foregroundStyle(Color(red: 1, green: 180/255, blue: 171/255))
                .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
        }
    }

    private func continueButton(
        _ title: LocalizedStringKey, fill: Color, ink: Color = VisionCraftUI.fixedColor(0x101010),
        border: Color = .clear, action: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return Button(action: action) {
            HStack(spacing: 16) {
                Text(title).visionCraftAndroidText(22, weight: .semibold)
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.system(size: 24)).accessibilityHidden(true)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 24).padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(border, lineWidth: 1).allowsHitTesting(false))
            .contentShape(shape)
        }.buttonStyle(.plain)
    }

    private func providerRow(_ title: Text, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 16) {
                    title.visionCraftAndroidText(21)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 20)).foregroundStyle(theme.text.opacity(0.7)).accessibilityHidden(true)
                }
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                .padding(.horizontal, 4).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Rectangle().fill(theme.text.opacity(0.2)).frame(height: 1).accessibilityHidden(true)
        }
    }

    private func openCustom() {
        guard let url = EasyMailProvider.customURL(custom) else { message = "메일 사이트의 https 주소를 확인해 주세요"; return }
        open(.init(id: "custom", name: String(localized: "다른 메일"), home: url, domains: [], authHosts: [], selector: ""))
    }
    private var trimmed: String { address.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func validAddress(_ value: String) -> Bool {
        value.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
    private func proceed() {
        guard validAddress(trimmed) else { message = "이메일 주소를 확인해 주세요"; return }
        guard let provider = retryProvider ?? EasyMailProvider.forAddress(trimmed) else { editing = false; message = nil; browser.mailChoosingProvider = true; return }
        open(provider)
    }
    private func open(_ provider: EasyMailProvider) {
        guard validAddress(trimmed) else { message = "이메일 주소를 확인해 주세요"; return }
        editing = false; message = nil; retryProvider = nil; browser.openMail(provider, address: trimmed)
    }
    private func back() {
        browser.handleBack(onExhausted: onClose)
    }
}
