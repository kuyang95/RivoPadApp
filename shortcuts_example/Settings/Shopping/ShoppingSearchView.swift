#if DEBUG
import SwiftUI
import WebKit
import Combine

struct ShoppingSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var model = ShoppingBrowserModel()

    var body: some View {
        ShoppingWebContainer(model: model)
            .background(VisionCraftUI.background)
            .toolbar(.hidden, for: .navigationBar)
            .visionCraftHandlesBackNavigation()
            .accessibilityAction(.escape) { model.back { dismiss() } }
            .overlay(alignment: .bottom) {
                if model.listening {
                    VStack(spacing: 12) {
                        Text("찾으실 상품을 말씀해 주세요.")
                        Button("음성 입력 마치기") { STTManager.shared.finishRecording() }
                            .buttonStyle(VisionCraftAndroidButtonStyle())
                    }
                    .padding(20).background(VisionCraftUI.surface, in: RoundedRectangle(cornerRadius: 16))
                    .padding(16).accessibilityElement(children: .contain)
                }
            }
            .fullScreenCover(item: $model.originalPage) { page in
                AccessibleWebBrowserView(initialQuery: page.url.absoluteString)
            }
            .onAppear { let close = dismiss; model.onClose = { close() }; model.updateEnvironment(dark: colorScheme == .dark) }
            .onChange(of: colorScheme) { _, value in model.updateEnvironment(dark: value == .dark) }
            .onChange(of: dynamicTypeSize) { _, _ in model.updateEnvironment(dark: colorScheme == .dark) }
            .onChange(of: scenePhase) { _, value in if value == .background { model.suspend() } }
            .onDisappear { model.suspend() }
    }
}

private struct ShoppingOriginalPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct ShoppingWebContainer: UIViewRepresentable {
    let model: ShoppingBrowserModel
    func makeUIView(context: Context) -> UIView { model.container }
    func updateUIView(_ uiView: UIView, context: Context) {}
    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        // Explicit lifetime is owned by ShoppingBrowserModel, including covered browser pages.
    }
}

@MainActor
private final class ShoppingBrowserModel: NSObject, ObservableObject, WKNavigationDelegate {
    let container = UIView()
    let webView: WKWebView
    private let workers = UIView()
    private let workerStore = WKWebsiteDataStore.nonPersistent()
    private let proxy: ShoppingMessageProxy
    private var localHome: URL?
    private var tempFolder: URL?
    private var requestID = ""
    private var tasks: [Task<Void, Never>] = []
    private var voiceTask: Task<Void, Never>?
    private var ownsRecording = false
    private var dark = false
    private var closed = false
    var onClose: (() -> Void)?
    @Published var originalPage: ShoppingOriginalPage?
    @Published var listening = false

    override init() {
        proxy = ShoppingMessageProxy()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.userContentController.add(proxy, name: "shopping")
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        proxy.owner = self
        container.backgroundColor = UIColor(VisionCraftUI.background)
        workers.isUserInteractionEnabled = false
        workers.accessibilityElementsHidden = true
        workers.isAccessibilityElement = false
        for child in [workers, webView] {
            container.addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                child.topAnchor.constraint(equalTo: container.topAnchor), child.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                child.leadingAnchor.constraint(equalTo: container.leadingAnchor), child.trailingAnchor.constraint(equalTo: container.trailingAnchor)
            ])
        }
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = UIColor(VisionCraftUI.background)
        webView.isInspectable = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("rivo-shopping-ui-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            tempFolder = folder
            for (name, content) in ShoppingWebAssets.files { try content.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8) }
            let home = folder.appendingPathComponent("shopping.html")
            localHome = home
            webView.loadFileURL(home, allowingReadAccessTo: folder)
        } catch {
            webView.loadHTMLString("<html lang='ko'><meta name='viewport' content='width=device-width'><body><h1>쇼핑 화면을 열지 못했습니다.</h1><p>개발 화면으로 돌아가 다시 열어 주세요.</p></body></html>", baseURL: nil)
        }
    }

    deinit {
        for task in tasks { task.cancel() }
        voiceTask?.cancel()
        if let tempFolder { try? FileManager.default.removeItem(at: tempFolder) }
    }

    func receive(_ message: WKScriptMessage) {
        guard !closed, message.frameInfo.isMainFrame, let localHome,
              message.frameInfo.request.url?.isFileURL == true,
              message.frameInfo.request.url?.standardizedFileURL.path == localHome.standardizedFileURL.path,
              let raw = message.body as? String, raw.utf8.count < 8000,
              let data = raw.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = value["action"] as? String else { return }
        switch action {
        case "ready": updateEnvironment(dark: dark)
        case "search":
            guard let id = value["requestId"] as? String, id.range(of: "^[a-z0-9-]{6,60}$", options: .regularExpression) != nil,
                  let input = value["query"] as? String, let names = value["sources"] as? [String] else { return }
            let query = String(input.prefix(100)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return }
            let sources = ShoppingSource.allCases.filter { names.contains($0.rawValue) }
            guard !sources.isEmpty else { return }
            search(id: id, query: query, sources: sources)
        case "cancel": cancelSearch()
        case "open":
            guard let raw = value["url"] as? String, let url = URL(string: raw), ShoppingSource.safeOpen(url) else { return }
            originalPage = ShoppingOriginalPage(url: url)
        case "close": onClose?()
        case "voice": listen()
        default: break
        }
    }

    private func search(id: String, query: String, sources: [ShoppingSource]) {
        cancelSearch(); requestID = id
        tasks.append(Task { [weak self] in
            for source in sources.filter(\.usesPublishedHTML) {
                guard let self, !Task.isCancelled, self.requestID == id else { return }
                self.event(id, source, "loading")
                do {
                    let html = try await ShoppingRetailerHTML.load(source, query: query)
                    try Task.checkCancellation()
                    guard self.requestID == id else { return }
                    self.call("receive", ["requestId": id, "source": source.rawValue, "format": "retailer-html", "html": html])
                } catch {
                    guard !Task.isCancelled, self.requestID == id else { return }
                    self.event(id, source, "unavailable", "판매처 검색 정보를 읽지 못했습니다. 판매처 검색 페이지를 열 수 있습니다.")
                }
            }
        })
        tasks.append(Task { [weak self] in
            for source in sources.filter({ !$0.usesPublishedHTML }) {
                guard let self, !Task.isCancelled, self.requestID == id else { return }
                self.event(id, source, "loading")
                let reader = ShoppingPageReader(source: source, container: self.workers, store: self.workerStore)
                do {
                    let result = try await reader.read(query) { [weak self] result in
                        guard let self, self.requestID == id else { return }
                        var value = result; value["requestId"] = id; value["source"] = source.rawValue; value["state"] = "partial"
                        self.call("receive", value)
                    }
                    try Task.checkCancellation()
                    guard self.requestID == id else { return }
                    var value = result; value["requestId"] = id; value["source"] = source.rawValue
                    self.call("receive", value)
                } catch {
                    guard !Task.isCancelled else { return }
                    self.event(id, source, "unavailable", "사이트에서 상품 정보를 읽지 못했습니다. 원래 사이트에서 검색할 수 있습니다.")
                }
            }
        })
    }

    private func event(_ id: String, _ source: ShoppingSource, _ state: String, _ message: String = "") {
        guard requestID == id else { return }
        call("receive", ["requestId": id, "source": source.rawValue, "state": state, "message": message])
    }
    private func cancelSearch() { requestID = ""; for task in tasks { task.cancel() }; tasks.removeAll() }
    func suspend() {
        webView.evaluateJavaScript("window.RivoShopping?.suspend()", completionHandler: nil)
        cancelSearch(); cancelVoice()
    }
    func updateEnvironment(dark: Bool) {
        self.dark = dark
        let scale = max(1, min(2.5, UIFontMetrics.default.scaledValue(for: 20) / 20))
        call("environment", ["theme": dark ? "dark" : "light", "fontScale": scale, "voice": true])
    }
    func back(onExhausted: @escaping () -> Void) {
        webView.evaluateJavaScript("window.RivoShopping?.back() || false") { result, _ in if result as? Bool != true { onExhausted() } }
    }
    private func call(_ method: String, _ value: [String: Any]) {
        guard !closed, let data = try? JSONSerialization.data(withJSONObject: value), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.RivoShopping?.\(method)(\(json))", completionHandler: nil)
    }
    private func nativeMessage(_ message: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: [message]), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.RivoShopping?.nativeMessage(\(json)[0])", completionHandler: nil)
    }
    private func listen() {
        guard voiceTask == nil else { return }
        guard !STTManager.shared.isRecording else { nativeMessage("다른 화면에서 음성 입력 중입니다."); return }
        voiceTask = Task { [weak self] in
            guard let self else { return }
            defer { self.listening = false; self.ownsRecording = false; self.voiceTask = nil }
            do {
                let stream = try await STTManager.shared.startRecording()
                self.ownsRecording = true
                if Task.isCancelled { STTManager.shared.cancelRecording(); return }
                self.listening = true
                var last = ""
                for await value in stream { if Task.isCancelled { break }; last = value }
                guard !Task.isCancelled else { return }
                if last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self.nativeMessage(STTManager.shared.lastFailure?.message ?? "음성이 들리지 않았습니다. 다시 입력해 주세요.") }
                else {
                    let data = try JSONSerialization.data(withJSONObject: [String(last.prefix(100))])
                    if let json = String(data: data, encoding: .utf8) { self.webView.evaluateJavaScript("window.RivoShopping?.voiceResult(\(json)[0])", completionHandler: nil) }
                }
            } catch { if !Task.isCancelled { self.nativeMessage("음성 입력을 사용할 수 없습니다. 검색어를 직접 입력해 주세요.") } }
        }
    }
    private func cancelVoice() { voiceTask?.cancel();if ownsRecording { STTManager.shared.cancelRecording() };ownsRecording = false;listening = false }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let localHome else { decisionHandler(.cancel); return }
        decisionHandler(url.isFileURL && url.standardizedFileURL.path == localHome.standardizedFileURL.path ? .allow : .cancel)
    }
}

@MainActor
private final class ShoppingMessageProxy: NSObject, WKScriptMessageHandler {
    weak var owner: ShoppingBrowserModel?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { owner?.receive(message) }
}
#endif
