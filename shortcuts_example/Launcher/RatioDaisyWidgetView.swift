#if DEBUG
import SwiftUI

/// Keep the reader inside the widget without nesting the app's navigation stack.
struct RatioDaisyWidgetView: View {
    var active = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var bookURL: URL?
    @State private var seen = false
    @State private var readerReleased = false
    @State private var playing = false
    @State private var resumeWithoutAutoplay = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if bookURL != nil {
                    VisionCraftIconButton(systemImage: "chevron.left", label: "서재로 돌아가기", tint: VisionCraftUI.primaryText) {
                        bookURL = nil
                    }
                }
                Text("데이지 플레이어").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
            }.padding(.horizontal, 8)
            if let bookURL, !readerReleased || (active && scenePhase == .active) {
                EPUBReaderView(fileURL: bookURL, embedded: true, active: active, allowAutoplay: !resumeWithoutAutoplay,
                               onPlaybackStateChanged: { playing = $0 })
                    .id(bookURL)
                    .accessibilityAction(.escape) { self.bookURL = nil }
            } else if bookURL == nil && (seen || active) {
                ReaderLibraryView(embedded: true, onOpenBook: { bookURL = $0 })
            }
        }
        .onAppear { if active { seen = true } }
        .onChange(of: active) { _, value in if value { seen = true; readerReleased = false } }
        .onChange(of: scenePhase) { _, phase in if phase == .active && active { readerReleased = false } }
        .onChange(of: bookURL) { _, _ in readerReleased = false; playing = false; resumeWithoutAutoplay = false }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            if (!active || scenePhase != .active) && !playing { resumeWithoutAutoplay = true; readerReleased = true }
        }
        .foregroundStyle(VisionCraftUI.primaryText)
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
    }
}
#endif
