import SwiftUI
import WebKit

@MainActor
struct EasyAIBrowserView: View {
    @ObservedObject var browser: AccessibleWebBrowserModel
    let onClose: () -> Void
    private var theme: RatioExperience { AccessibleWebTheme.colors }

    var body: some View {
        ZStack {
            RatioWidgetWallpaper(dark: browser.palette == .dark)
            VStack(spacing: 0) {
                if let message = browser.errorMessage {
                    Text(message).visionCraftAndroidText(18).foregroundStyle(theme.text).padding(20)
                }
                AccessibleWebSurface(webView: browser.webView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) {
                        if browser.isLoading {
                            ProgressView(value: browser.progress).tint(theme.accent)
                                .frame(height: 2).clipped().accessibilityLabel("ChatGPT")
                        }
                    }
                    .overlay {
                        if browser.isLoading && browser.progress < 0.2 && browser.errorMessage == nil {
                            VStack(spacing: 20) {
                                ProgressView().tint(theme.text)
                                Text(AppLocalization.string("AI를 준비하고 있어요")).visionCraftAndroidText(24).foregroundStyle(theme.text)
                            }
                            .padding(24)
                        }
                    }
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
        .statusBarHidden()
        .visionCraftHandlesBackNavigation()
        .accessibilityAction(.escape) { browser.handleBack(onExhausted: onClose) }
    }
}
