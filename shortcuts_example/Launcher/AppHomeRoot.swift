import SwiftUI

nonisolated enum AppLauncherMode: String, CaseIterable {
    case standard, widgets
    static let storageKey = "home.launcher.v1"
    static let mediaKey = "home.media.visible.v1"
    var title: String { self == .standard ? "기존 홈" : "위젯 런처" }
}

struct AppHomeRoot: View {
    @AppStorage(AppLauncherMode.storageKey) private var mode = AppLauncherMode.standard.rawValue
    var body: some View {
        Group {
            if AppLauncherMode(rawValue: mode) == .widgets { RatioLauncherView() }
            else { HomeView() }
        }
        // The launcher has no HomeView, so the file and text-source requests are handled here for both homes.
        .modifier(HomeImportRequestPresenter())
    }
}
