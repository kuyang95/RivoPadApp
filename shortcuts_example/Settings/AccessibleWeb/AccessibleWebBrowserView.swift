#if DEBUG
import SwiftUI
import WebKit

@MainActor
struct AccessibleWebBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var browser: AccessibleWebBrowserModel
    @State private var address = "https://www.naver.com"
    @FocusState private var addressFocused: Bool

    init() {
        _browser = StateObject(wrappedValue: AccessibleWebBrowserModel())
    }

    init(browser: AccessibleWebBrowserModel) {
        _browser = StateObject(wrappedValue: browser)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                VisionCraftScreenTitleRow(title: "접근성 웹", onBack: { dismiss() }) {
                    VisionCraftIconButton(systemImage: "safari", label: "Safari에서 열기") {
                        if let url = browser.webView.url, AccessibleWebAddress.isWebURL(url) { openURL(url) }
                    }
                    .disabled(browser.webView.url == nil)
                }

                HStack(spacing: 8) {
                    TextField("주소 또는 네이버 검색어", text: $address)
                        .visionCraftAndroidText(16)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.webSearch)
                        .submitLabel(.go)
                        .focused($addressFocused)
                        .onSubmit(navigate)
                        .padding(.horizontal, 12)
                        .frame(minHeight: VisionCraftUI.minTouchTarget)
                        .background(VisionCraftUI.surfaceVariant, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VisionCraftUI.outline, lineWidth: 1))
                        .accessibilityLabel("주소 또는 네이버 검색어")
                    VisionCraftIconButton(systemImage: "arrow.right", label: "주소로 이동 또는 검색", action: navigate)
                }

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        VisionCraftIconButton(systemImage: "chevron.left", label: "이전 웹페이지") { browser.goBack() }
                            .disabled(!browser.canGoBack)
                        VisionCraftIconButton(systemImage: "chevron.right", label: "다음 웹페이지") { browser.webView.goForward() }
                            .disabled(!browser.canGoForward)
                        VisionCraftIconButton(
                            systemImage: browser.isLoading ? "xmark" : "arrow.clockwise",
                            label: browser.isLoading ? "페이지 로딩 중지" : "새로고침"
                        ) { browser.reloadOrStop() }
                        if browser.hasPopup {
                            VisionCraftIconButton(systemImage: "xmark.rectangle", label: "새 창 닫고 이전 창으로") { browser.closePopup() }
                        }
                        Button(browser.appearanceEnabled ? "색상 통일 켜짐" : "원본 보기") {
                            browser.appearanceEnabled.toggle()
                            browser.applyAppearance()
                        }
                        .buttonStyle(VisionCraftAndroidButtonStyle())
                        .accessibilityValue(browser.appearanceEnabled ? "켬" : "끔")
                        .accessibilityHint("사진을 유지하면서 웹 색상 통일을 켜거나 끕니다.")

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
                        } label: {
                            Label(browser.palette.title, systemImage: "circle.lefthalf.filled")
                        }
                        .buttonStyle(VisionCraftAndroidButtonStyle())
                        .accessibilityLabel("웹 색 조합")
                        .accessibilityValue(browser.palette.title)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            if let message = browser.errorMessage {
                HStack(alignment: .top) {
                    Text(message)
                        .visionCraftAndroidText(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VisionCraftIconButton(systemImage: "xmark", label: "안내 닫기") { browser.errorMessage = nil }
                }
                .padding(.horizontal, 24)
                .accessibilityElement(children: .contain)
            }
            if browser.isLoading {
                ProgressView(value: browser.progress)
                    .accessibilityLabel("웹페이지 로딩")
            }

            AccessibleWebSurface(webView: browser.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("실험 기능 · 사진·영상·도표는 원본 유지 · 로그인은 이 화면을 닫으면 초기화됩니다.")
                .visionCraftAndroidText(12, relativeTo: .caption)
                .foregroundStyle(VisionCraftUI.secondaryText)
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
        }
        .background(VisionCraftUI.background.ignoresSafeArea())
        .foregroundStyle(VisionCraftUI.primaryText)
        .tint(VisionCraftUI.primary)
        .toolbar(.hidden, for: .navigationBar)
        .visionCraftHandlesBackNavigation()
        .accessibilityAction(.escape) { dismiss() }
        .onChange(of: browser.currentAddress) { _, value in
            if !addressFocused { address = value }
        }
        .onDisappear { browser.shutdown() }
    }

    private func navigate() {
        addressFocused = false
        browser.navigate(address)
    }
}

private struct AccessibleWebSurface: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ container: UIView, context: Context) {
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
#endif
