import SwiftUI
import Combine

@MainActor
final class RatioBrowserWidgetSession: ObservableObject {
    @Published var browser: AccessibleWebBrowserModel?
    @Published var expanded = false
    private var appearanceObservation: AnyCancellable?
    private var mailObservation: AnyCancellable?
    let easyYouTube: Bool
    let easyMail: Bool
    init(easyYouTube: Bool = false, easyMail: Bool = false) { self.easyYouTube = easyYouTube; self.easyMail = easyMail }
    func start() {
        guard browser == nil else { return }
        let model = AccessibleWebBrowserModel(easyYouTube: easyYouTube, embedded: true, easyMail: easyMail)
        browser = model
        if easyMail {
            mailObservation = model.$mailStart
                .combineLatest(model.$mailEntryEditing, model.$mailProvider, model.$mailAuthenticating)
                .combineLatest(model.$mailInbox)
                .sink { [weak self] _ in self?.objectWillChange.send() }
        }
        appearanceObservation = model.$palette.removeDuplicates().sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
    func pause() { browser?.pauseMedia() }
    func shutdown() { mailObservation = nil; appearanceObservation = nil; browser?.shutdown(); browser = nil; expanded = false }
}

@MainActor
struct RatioBrowserWidgetView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var session: RatioBrowserWidgetSession
    var active = true
    var preview = false
    var onClose: () -> Void = {}
    var showsMailInboxBackButton = false
    var onPageTurn: (Int) -> Void = { _ in }
    var onPageDrag: ((CGFloat) -> Void)? = nil
    // A missing completion handler lets the native swipe use onPageTurn.
    var onPageDragEnd: ((Bool) -> Void)? = nil
    var body: some View {
        Group {
            if let browser = session.browser, !session.expanded {
                AccessibleWebBrowserView(browser: browser, embedded: true, ownsSession: false,
                    showsMailInboxBackButton: showsMailInboxBackButton,
                    onClose: { browser.resetExitRequest(); onClose() })
            } else if session.easyYouTube && active && !session.expanded {
                EasyYouTubeCheckingAccountView()
            } else { Color.clear }
        }
        .task(id: active) {
            if active {
                session.start(); session.browser?.setContentActive(scenePhase == .active); session.browser?.onLauncherPageTurn = onPageTurn
                session.browser?.onLauncherPageDrag = onPageDrag; session.browser?.onLauncherPageDragEnd = onPageDragEnd
            }
            else {
                session.browser?.onLauncherPageTurn = nil; session.browser?.onLauncherPageDrag = nil
                session.browser?.onLauncherPageDragEnd = nil; session.pause()
            }
        }
        .task(id: preview) { if preview { session.start(); if !active { session.browser?.setContentActive(false) } } }
        .onChange(of: scenePhase) { _, phase in session.browser?.setContentActive(active && phase == .active) }
        .onDisappear {
            session.browser?.onLauncherPageTurn = nil; session.browser?.onLauncherPageDrag = nil
            session.browser?.onLauncherPageDragEnd = nil; session.pause()
        }
        .fullScreenCover(isPresented: $session.expanded) {
            if let browser = session.browser {
                AccessibleWebBrowserView(browser: browser, ownsSession: false,
                    onClose: { session.expanded = false })
            }
        }
    }
}
