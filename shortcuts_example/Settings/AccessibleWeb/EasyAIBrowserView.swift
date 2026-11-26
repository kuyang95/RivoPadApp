import SwiftUI
import WebKit

enum EasyAIPlatform: String, CaseIterable, Identifiable {
    case claude, gemini, gpt

    var id: Self { self }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .gemini: "Gemini"
        case .gpt: "GPT"
        }
    }

    var address: String {
        switch self {
        case .claude: "https://claude.ai/"
        case .gemini: "https://gemini.google.com/"
        case .gpt: "https://chatgpt.com/"
        }
    }
}

@MainActor
struct EasyAIBrowserView: View {
    @ObservedObject var browser: AccessibleWebBrowserModel
    @State private var revealedView: ObjectIdentifier?
    let onClose: () -> Void
    private var theme: RatioExperience { AccessibleWebTheme.colors }

    private var preparing: Bool { !browser.showsAIHome && revealedView != ObjectIdentifier(browser.webView) && browser.errorMessage == nil }

    var body: some View {
        ZStack {
            RatioWidgetWallpaper(dark: browser.showsAIHome || browser.palette == .dark)
            if browser.showsAIHome {
                EasyAIHomeView(onSelect: browser.openAIPlatform)
            } else {
                webContent
            }
        }
        .background(theme.background.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarLeading) {
                    VisionCraftBackButton(tint: theme.text) { browser.handleBack(onExhausted: onClose) }
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) {
                    VisionCraftBackButton(tint: theme.text) { browser.handleBack(onExhausted: onClose) }
                }
            }
        }
        .task(id: browser.aiPlatform.map { _ in ObjectIdentifier(browser.webView) }) {
            let view = browser.webView
            guard browser.aiPlatform != nil, revealedView != ObjectIdentifier(view) else { return }
            let deadline = ContinuousClock.now + .seconds(8)
            while !Task.isCancelled && browser.errorMessage == nil && ContinuousClock.now < deadline {
                if await browser.aiInitialPageReady(in: view) { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            if !Task.isCancelled { revealedView = ObjectIdentifier(view) }
        }
        .statusBarHidden()
        .visionCraftHandlesBackNavigation()
        .accessibilityAction(.escape) { browser.handleBack(onExhausted: onClose) }
    }

    private var webContent: some View {
        VStack(spacing: 0) {
            if let message = browser.errorMessage {
                Text(message).visionCraftAndroidText(18).foregroundStyle(theme.text).padding(20)
            }
            ZStack {
                AccessibleWebSurface(webView: browser.webView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(preparing ? 0 : 1)
                    .accessibilityHidden(preparing)
                    .allowsHitTesting(!preparing)
                if preparing {
                    VStack(spacing: 20) {
                        ProgressView().tint(theme.accent).accessibilityHidden(true)
                        Text(AppLocalization.string("AI를 준비하고 있어요"))
                            .visionCraftAndroidText(24)
                            .foregroundStyle(theme.text)
                    }
                    .padding(24)
                }
            }
        }
    }
}


private struct EasyAIHomeView: View {
    let onSelect: (EasyAIPlatform) -> Void

    private let text = VisionCraftUI.fixedColor(0xF4F5EF)
    private let accent = VisionCraftUI.fixedColor(0xCCE7D3)
    private let ink = VisionCraftUI.fixedColor(0x14271E)

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(spacing: 24) {
                    Text(AppLocalization.string("사용할 AI를 선택하세요."))
                        .visionCraftAndroidText(26, weight: .medium, relativeTo: .title2)
                        .foregroundStyle(text)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 12) {
                        ForEach(EasyAIPlatform.allCases, content: platformCard)
                    }
                }
                .frame(maxWidth: 520)
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: viewport.size.height)
            }
        }
    }

    private func platformCard(_ platform: EasyAIPlatform) -> some View {
        let shape = RoundedRectangle(cornerRadius: 23, style: .continuous)
        let brand = platformBrandColor(platform)
        return Button {
            onSelect(platform)
        } label: {
            HStack(spacing: 18) {
                Image("AIPlatform" + platform.title)
                    .resizable()
                    .renderingMode(platform == .gemini ? .original : .template)
                    .scaledToFit()
                    .foregroundStyle(brand)
                    .opacity(0.90)
                    .frame(width: 44, height: 44)
                    .frame(width: 48)
                    .accessibilityHidden(true)
                Text(platform.title)
                    .visionCraftAndroidText(22, weight: .semibold)
                    .foregroundStyle(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.forward")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ink)
                    .frame(width: 44, height: 44)
                    .background(accent, in: Circle())
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(minHeight: 88)
            .background(
                LinearGradient(stops: [.init(color: brand.opacity(0.24), location: 0),
                                       .init(color: .white.opacity(0.09), location: 0.32),
                                       .init(color: .white.opacity(0.045), location: 1)],
                               startPoint: .leading, endPoint: .trailing),
                in: shape
            )
            .overlay(shape.strokeBorder(.white.opacity(0.24)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .multilineTextAlignment(.leading)
    }

    private func platformBrandColor(_ platform: EasyAIPlatform) -> Color {
        switch platform {
        case .claude: VisionCraftUI.fixedColor(0xD97757)
        case .gemini: VisionCraftUI.fixedColor(0x7AA7FA)
        case .gpt: VisionCraftUI.fixedColor(0xF4F5EF)
        }
    }
}
