import SwiftUI

nonisolated enum RatioMediaKind: String, CaseIterable, Hashable {
    case daisy, listening, mail, browser, youTube = "youtube", news

    var title: String {
        switch self {
        case .daisy: "도서 읽기"
        case .listening: "listen.title"
        case .mail: "이메일"
        case .browser: "브라우저"
        case .youTube: "유튜브"
        case .news: "뉴스"
        }
    }
}

struct RatioWidgetWallpaper: View {
    let dark: Bool

    var body: some View {
        GeometryReader { geometry in
            Image(dark ? "RatioForestMist" : "RatioBlueMist")
                .resizable().scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(1.06).blur(radius: 10).clipped()
                .overlay(Color.black.opacity(dark ? 0.60 : 0.08))
                .overlay(LinearGradient(colors: [.clear, .black.opacity(dark ? 0.25 : 0.10)],
                                        startPoint: .top, endPoint: .bottom))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@MainActor
struct RatioMediaWidgetScreen: View {
    let kind: RatioMediaKind
    let widgetNavigation: CategoryWidgetNavigation?
    var active = true
    var preview = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var appColorScheme
    @StateObject private var web: RatioBrowserWidgetSession
    @State private var article: String?
    @State private var listeningBackRequest = 0

    init(kind: RatioMediaKind, widgetNavigation: CategoryWidgetNavigation? = nil,
         active: Bool = true, preview: Bool = false) {
        self.kind = kind
        self.widgetNavigation = widgetNavigation
        self.active = active
        self.preview = preview
        _web = StateObject(wrappedValue: RatioBrowserWidgetSession(easyYouTube: kind == .youTube, easyMail: kind == .mail))
    }

    var body: some View {
        ZStack {
            RatioExperience().background.ignoresSafeArea()
            RatioWidgetWallpaper(dark: usesDarkWallpaper)
            VStack(spacing: 0) {
                if showsBackButton {
                    let style = RatioExperience()
                    VisionCraftBackButton(tint: usesDarkWallpaper ? style.text : style.ink, action: goBack)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                mediaContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .modifier(CategoryWidgetPageSwipe(navigation: widgetNavigation, enabled: usesNativePaging))
            .padding(.horizontal, 16)
            .padding(.top, 24)
        }
        .overlay {
            if let widgetNavigation {
                HStack(spacing: 0) {
                    pageSwipeGutter(widgetNavigation)
                    Spacer(minLength: 0)
                    pageSwipeGutter(widgetNavigation)
                }
            }
        }
        .modifier(CategoryWidgetPageActions(navigation: widgetNavigation))
        .environment(\.colorScheme, kind == .mail ? appColorScheme : .dark)
        .toolbar(.hidden, for: .navigationBar)
        .visionCraftHandlesBackNavigation()
        .accessibilityAction(.escape, goBack)
        .navigationDestination(item: $article) { url in
            AccessibleWebBrowserView(initialQuery: url, newsArticle: true)
        }
        .onDisappear { if !web.expanded { web.shutdown() } }
    }

    private var usesDarkWallpaper: Bool {
        kind != .browser || (web.browser?.palette ?? .dark) == .dark
    }

    private var showsBackButton: Bool {
        guard widgetNavigation == nil else { return false }
        switch kind {
        case .browser, .youTube, .news: return true
        case .mail: return web.browser == nil
        case .daisy, .listening: return false
        }
    }

    private var usesNativePaging: Bool {
        if kind == .daisy || kind == .listening || kind == .news { return true }
        guard kind == .mail, let browser = web.browser else { return false }
        return (browser.mailInbox || browser.mailStart || browser.mailLoginHidesWeb)
            && !browser.mailEntryEditing
    }

    private func pageSwipeGutter(_ navigation: CategoryWidgetNavigation) -> some View {
        Color.clear
            .frame(width: 16)
            .contentShape(Rectangle())
            .modifier(CategoryWidgetPageSwipe(navigation: navigation))
            .onLongPressGesture(perform: navigation.onEdit)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var mediaContent: some View {
        switch kind {
        case .daisy:
            RatioDaisyWidgetView(active: active, showsLibraryBackButton: widgetNavigation == nil, onExit: close)
        case .listening:
            RatioListeningWidgetView(active: active, backRequest: listeningBackRequest,
                                     showsPlayerBackButton: widgetNavigation == nil, onExit: close)
        case .news:
            RatioNewsWidget(active: active && article == nil) { article = $0 }
        case .browser, .mail, .youTube:
            RatioBrowserWidgetView(session: web, active: active, preview: preview, onClose: close,
                                   showsMailInboxBackButton: widgetNavigation == nil,
                                   onPageTurn: { widgetNavigation?.onTurn($0) },
                                   onPageDrag: widgetNavigation?.onDrag,
                                   onPageDragEnd: widgetNavigation?.onDragEnd)
        }
    }

    private func close() {
        if let widgetNavigation { widgetNavigation.onTurn(-widgetNavigation.index) }
        else { dismiss() }
    }

    private func goBack() {
        if kind == .listening { listeningBackRequest += 1 }
        else if let browser = web.browser { browser.handleBack(onExhausted: close) }
        else { close() }
    }
}
