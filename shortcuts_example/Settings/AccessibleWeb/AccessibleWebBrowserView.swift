import SwiftUI
import WebKit

@MainActor
struct AccessibleWebBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var browser: AccessibleWebBrowserModel
    @State private var address = "https://www.google.com"
    @FocusState private var addressFocused: Bool
    @State private var listening = false
    @State private var ownsRecording = false
    @State private var speechTask: Task<Void, Never>?
    private var embedded = false
    private var contentActive = true
    private var ownsSession = true
    private var showsMailInboxBackButton = false
    private var onExpand: (() -> Void)?
    private var onClose: (() -> Void)?

    init(initialQuery: String? = nil, easyYouTube: Bool = false, newsArticle: Bool = false, easyMail: Bool = false, aiWeb: Bool = false) {
        _browser = StateObject(wrappedValue: AccessibleWebBrowserModel(easyYouTube: easyYouTube, newsArticle: newsArticle,
            easyMail: easyMail, aiWeb: aiWeb, initialQuery: initialQuery))
        _address = State(initialValue: initialQuery ?? "https://www.google.com")
    }

    init(browser: AccessibleWebBrowserModel, embedded: Bool = false, ownsSession: Bool = true,
         contentActive: Bool = true, showsMailInboxBackButton: Bool = false,
         onExpand: (() -> Void)? = nil, onClose: (() -> Void)? = nil) {
        _browser = StateObject(wrappedValue: browser)
        _address = State(initialValue: browser.currentAddress)
        self.embedded = embedded; self.ownsSession = ownsSession
        self.contentActive = contentActive
        self.showsMailInboxBackButton = showsMailInboxBackButton
        self.onExpand = onExpand; self.onClose = onClose
    }

    var body: some View {
        Group {
            if browser.aiWeb {
                EasyAIBrowserView(browser: browser, onClose: close)
            } else if browser.easyMail {
                EasyMailBrowserView(browser: browser, embedded: embedded, onClose: close, dialogColorScheme: colorScheme,
                                    showsInboxBackButton: !embedded || showsMailInboxBackButton, contentActive: contentActive)
            } else { webBody }
        }
        .onDisappear { if (browser.easyMail || browser.aiWeb) && ownsSession { browser.shutdown() } }
        .onChange(of: scenePhase) { _, phase in if (browser.easyMail || browser.aiWeb) && ownsSession { browser.setContentActive(phase == .active) } }
    }
    private var webBody: some View {
        let preparingYouTube = embedded && browser.easyYouTube && !browser.youtubeReady && !browser.youtubePlaybackLoading
        let preparingArticle = browser.newsArticle && browser.newsAwaitingDocument && browser.errorMessage == nil
        let webAvailable = contentActive && !preparingYouTube && !preparingArticle
        return VStack(spacing: 0) {
            if !browser.easyYouTube && !isBrowserHome && !browser.newsArticle {
            HStack(spacing: 0) {
                if !embedded {
                    VisionCraftIconButton(systemImage: "chevron.left", label: browser.aiWeb ? "뒤로" : "접근성 웹 닫기", tint: chromeAccent) {
                        if browser.aiWeb { browser.handleBack(onExhausted: close) } else { close() }
                    }
                }
                if browser.aiWeb {
                    Text("AI · ChatGPT").visionCraftAndroidText(20, weight: .semibold)
                        .foregroundStyle(chromeText).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
                } else {
                    TextField("검색 또는 주소", text: Binding(
                        get: { addressFocused ? address : BrowserAddressDisplay.text(browser.currentAddress) },
                        set: { address = $0 }
                    ))
                        .visionCraftAndroidText(16)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.webSearch)
                        .submitLabel(.go)
                        .focused($addressFocused)
                        .onSubmit(navigate)
                        .onChange(of: addressFocused) { _, focused in
                            if focused { address = browser.currentAddress }
                        }
                        .padding(.leading, 12)
                        .padding(.trailing, addressFocused ? 0 : 12)
                        .frame(minHeight: VisionCraftUI.minTouchTarget)
                        .padding(.trailing, addressFocused ? 48 : 0)
                        .overlay(alignment: .trailing) {
                            if addressFocused {
                                VisionCraftIconButton(systemImage: "arrow.right", label: "주소로 이동 또는 검색", tint: chromeAccent, action: navigate)
                            }
                        }
                        .background(chromeSurface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(addressFocused ? chromeAccent : chromeBorder, lineWidth: addressFocused ? 2 : 1))
                        .accessibilityLabel("검색 또는 주소")
                }
                VisionCraftIconButton(
                    systemImage: browser.appearanceEnabled ? "circle.lefthalf.filled" : "circle",
                    label: "색상 통일", tint: chromeAccent
                ) {
                    browser.appearanceEnabled.toggle()
                    browser.applyAppearance()
                }
                .accessibilityValue(browser.appearanceEnabled ? "켬" : "끔, 원본 보기")
                .accessibilityHint("페이지 배치와 입력값을 유지하면서 웹 색상 통일을 켜거나 끕니다.")

                Menu {
                    ForEach(AccessibleWebPalette.allCases) { palette in
                        Button {
                            browser.palette = palette
                            browser.appearanceEnabled = true
                            browser.applyAppearance()
                        } label: {
                            if palette == browser.palette {
                                Label(palette.title, systemImage: "checkmark")
                            } else { Text(palette.title) }
                        }
                    }
                } label: { toolbarImage(paletteIcon) }
                .accessibilityLabel("웹 색 조합")
                .accessibilityValue(browser.palette.title)

                Menu {
                    if !browser.aiWeb {
                        Button { browser.navigate("https://www.google.com") } label: { Label("브라우저 홈", systemImage: "house") }
                        if !browser.easyYouTube {
                            Toggle("광고 차단", isOn: Binding(get: { browser.adBlockEnabled }, set: { browser.setAdBlockEnabled($0) }))
                        }
                        Toggle("구글 간단히 보기", isOn: $browser.simpleGoogleEnabled)
                            .onChange(of: browser.simpleGoogleEnabled) { _, _ in browser.applyAppearance() }
                    } else {
                        Button { browser.navigate("https://chatgpt.com/") } label: { Label("ChatGPT", systemImage: "bubble.left.and.bubble.right") }
                    }
                    Section("페이지 확대 · \(browser.zoomPercent)%") {
                        Button { browser.changeZoom(increase: false) } label: { Label("페이지 축소", systemImage: "minus.magnifyingglass") }
                            .disabled(browser.zoomPercent <= 75)
                        Button { browser.changeZoom(increase: true) } label: { Label("페이지 확대", systemImage: "plus.magnifyingglass") }
                            .disabled(browser.zoomPercent >= 300)
                        Button("페이지 확대 100%") { browser.setZoom(100) }
                        Button("기기 글자 크기에 맞춤 (\(browser.defaultZoomPercent)%)") { browser.resetZoom() }
                    }
                    Button { browser.goBack() } label: { Label("이전 웹페이지", systemImage: "chevron.left") }
                        .disabled(!browser.canGoBack)
                    Button { browser.webView.goForward() } label: { Label("다음 웹페이지", systemImage: "chevron.right") }
                        .disabled(!browser.canGoForward)
                    Button { browser.reloadOrStop() } label: {
                        Label(browser.isLoading ? "페이지 로딩 중지" : "새로고침", systemImage: browser.isLoading ? "xmark" : "arrow.clockwise")
                    }
                    if browser.hasPopup {
                        Button { browser.closePopup() } label: { Label("새 창 닫고 이전 창으로", systemImage: "xmark.rectangle") }
                    }
                    Button {
                        if let url = browser.webView.url, AccessibleWebAddress.isWebURL(url) { openURL(url) }
                    } label: { Label("Safari에서 열기", systemImage: "safari") }
                        .disabled(browser.webView.url == nil)
                } label: { toolbarImage("ellipsis") }
                .accessibilityLabel(Text(AppLocalization.string(browser.aiWeb ? "AI 도구 더보기" : "웹 도구 더보기")))
                if let onExpand {
                    VisionCraftIconButton(systemImage: "arrow.up.left.and.arrow.down.right", label: "브라우저 전체화면", tint: chromeAccent, action: onExpand)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)

            }

            if let message = browser.errorMessage {
                HStack(alignment: .top) {
                    Text(message)
                        .visionCraftAndroidText(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if embedded && browser.easyYouTube && !browser.youtubeReady {
                        VisionCraftIconButton(systemImage: "arrow.clockwise", label: "새로고침") { browser.reloadOrStop() }
                    } else {
                        VisionCraftIconButton(systemImage: "xmark", label: "안내 닫기") { browser.errorMessage = nil }
                    }
                }
                .padding(.horizontal, 24)
                .accessibilityElement(children: .contain)
            }

            AccessibleWebSurface(webView: browser.webView, interactionAvailable: webAvailable)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(preparingYouTube ? 0 : 1)
                .allowsHitTesting(webAvailable)
                .accessibilityHidden(!webAvailable)
                .overlay(alignment: .top) {
                    if !browser.easyYouTube && !browser.newsArticle && browser.isLoading && browser.errorMessage == nil {
                        ProgressView(value: Optional<Double>.none)
                            .progressViewStyle(.linear)
                            .tint(chromeAccent)
                            .frame(height: 2)
                            .clipped()
                            .allowsHitTesting(false)
                            .accessibilityLabel("웹페이지 로딩")
                    }
                }
                .overlay {
                    if preparingYouTube && browser.errorMessage == nil {
                        EasyYouTubeCheckingAccountView()
                    }
                    if preparingArticle {
                        NewsArticleLoadingSurface()
                    }
                    if browser.easyYouTube && browser.errorMessage == nil && (!embedded || browser.youtubeReady || browser.youtubePlaybackLoading) &&
                        (browser.youtubePlaybackLoading || (browser.isLoading && !["m.youtube.com","www.youtube.com","youtube.com"].contains(browser.webView.url?.host ?? ""))) {
                        ProgressView(value: browser.youtubePlaybackLoading ? nil : browser.progress)
                            .progressViewStyle(.linear)
                            .tint(chromeAccent)
                            .frame(height: 2)
                            .clipped()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .allowsHitTesting(false)
                            .accessibilityLabel("웹페이지 로딩")
                    }
                }

        }
        .overlay(alignment: .bottom) {
            if listening {
                HStack(spacing: 16) {
                    Text("말씀해 주세요.")
                    Button("음성 검색 중지") { STTManager.shared.finishRecording() }
                }
                .padding(20).background(chromeSurface, in: RoundedRectangle(cornerRadius: 16)).padding(16)
                .accessibilityElement(children: .contain)
            }
        }
        .sheet(isPresented: $browser.favoriteAddRequested) { BrowserAddFavoriteView(save: browser.addFavorite) }
        .background((embedded ? Color.clear : chromeBackground).ignoresSafeArea())
        .foregroundStyle(chromeText)
        .tint(chromeAccent)
        .environment(\.colorScheme, browser.easyYouTube || browser.palette == .dark ? .dark : .light)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(!embedded)
        .persistentSystemOverlays(embedded ? .automatic : .hidden)
        .ignoresSafeArea(.container, edges: embedded ? [] : .bottom)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !embedded && (browser.newsArticle || browser.easyYouTube || isBrowserHome) {
                VisionCraftBackButton(tint: chromeAccent) {
                    if browser.newsArticle || browser.easyYouTube {
                        browser.handleBack(onExhausted: close)
                    } else {
                        close()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(chromeBackground)
            }
        }
        .visionCraftHandlesBackNavigation()
        .accessibilityAction(.escape) { browser.handleBack(onExhausted: close) }
        .onChange(of: browser.currentAddress) { _, value in
            if !addressFocused { address = value }
            if listening { stopVoiceSearch() }
        }
        .onChange(of: browser.exitRequested) { _, requested in if requested { close() } }
        .onChange(of: browser.voiceSearchRequested) { _, requested in
            if requested { browser.voiceSearchRequested = false; listen() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { stopVoiceSearch() }
            if ownsSession { browser.setContentActive(phase == .active) }
        }
        .onDisappear { stopVoiceSearch(); if ownsSession { browser.shutdown() } }
    }

    private func close() { if let onClose { onClose() } else { dismiss() } }

    private var isBrowserHome: Bool { !browser.aiWeb && !browser.easyYouTube && browser.simpleGoogleEnabled && !browser.hasPopup && AccessibleWebAddress.isGoogleHome(browser.currentAddress) }
    private func stopVoiceSearch() {
        speechTask?.cancel(); speechTask = nil
        if ownsRecording { STTManager.shared.cancelRecording(); ownsRecording = false }
        listening = false
    }
    private func listen() {
        guard !listening else { return }
        guard !STTManager.shared.isRecording else { browser.errorMessage = "다른 음성 입력을 마친 뒤 다시 시도해 주세요."; return }
        addressFocused = false; listening = true; browser.errorMessage = nil
        let origin = browser.currentAddress
        speechTask = Task {
            do {
                let stream = try await STTManager.shared.startRecording(requiresOnDeviceRecognition: true)
                ownsRecording = true
                try Task.checkCancellation()
                for await text in stream {
                    try Task.checkCancellation()
                    guard browser.currentAddress == origin else { stopVoiceSearch(); return }
                    listening = false; ownsRecording = false; speechTask = nil
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { browser.performVoiceSearch(text) }
                    return
                }
                if !Task.isCancelled { browser.errorMessage = STTManager.shared.consumeLastFailure()?.message ?? "음성을 인식하지 못했습니다. 다시 시도해 주세요." }
            } catch is CancellationError { }
            catch { if !Task.isCancelled { browser.errorMessage = "음성을 인식하지 못했습니다. 다시 시도해 주세요." } }
            if ownsRecording { STTManager.shared.cancelRecording() }
            listening = false; ownsRecording = false; speechTask = nil
        }
    }

    private var theme: RatioExperience { AccessibleWebTheme.colors }
    private var dark: Bool { browser.palette == .dark }
    private var chromeAccent: Color { browser.easyYouTube ? theme.accent : dark ? chromeText : Color(uiColor: UIColor(hex: 0x704000)) }
    private var chromeBackground: Color { browser.easyYouTube ? theme.background : dark ? Color(uiColor: UIColor(hex: 0x202124)) : .white }
    private var chromeSurface: Color { browser.easyYouTube ? theme.surface : Color(uiColor: UIColor(hex: dark ? 0x292A2D : 0xF0F2F5)) }
    private var chromeText: Color { browser.easyYouTube ? theme.text : Color(uiColor: UIColor(hex: dark ? 0xF1F3F4 : 0x283546)) }
    private var chromeBorder: Color { browser.easyYouTube ? theme.outline : Color(uiColor: UIColor(hex: dark ? 0x9AA0A6 : 0x536176)) }
    private var paletteIcon: String { dark ? "moon" : "sun.max" }

    private func toolbarImage(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 26))
            .foregroundStyle(chromeAccent)
            .frame(width: 52, height: 52)
            .contentShape(Rectangle())
    }

    private func navigate() {
        addressFocused = false
        browser.navigate(address)
    }
}

struct EasyYouTubeCheckingAccountView: View {
    var body: some View {
        let ink = AccessibleWebTheme.colors.text
        VStack(spacing: 24) {
            ProgressView()
                .controlSize(.large)
                .tint(ink)
                .accessibilityHidden(true)
            Text(AppLocalization.string(EasyYouTubePage.checkingAccountTitle))
                .visionCraftAndroidText(28, weight: .semibold, relativeTo: .title)
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AccessibleWebSurface: UIViewRepresentable {
    let webView: WKWebView
    var interactionAvailable = true

    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ container: UIView, context: Context) {
        container.isUserInteractionEnabled = interactionAvailable
        container.accessibilityElementsHidden = !interactionAvailable
        webView.accessibilityElementsHidden = !interactionAvailable
        guard webView.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
    }
}

private struct NewsArticleLoadingSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.isOpaque = false
        view.backgroundColor = UIColor(hex: 0x202124)
        view.scrollView.backgroundColor = UIColor(hex: 0x202124)
        view.scrollView.isScrollEnabled = false
        view.loadHTMLString(NewsArticlePage.loadingHTML, baseURL: nil)
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) { uiView.stopLoading() }
}
