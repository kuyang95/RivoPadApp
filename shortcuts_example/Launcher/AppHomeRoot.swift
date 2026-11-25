import SwiftUI

nonisolated enum AppLauncherMode: String, CaseIterable {
    case standard, widgets
    case category = "list" // Preserve the selection saved by the previous launcher build.
    static let storageKey = "home.launcher.v1"
    static let mediaKey = "home.media.visible.v1"
    var title: String {
        switch self {
        case .standard: "기존 홈"
        case .widgets: "Ratio"
        case .category: "카테고리형"
        }
    }
}

struct AppHomeRoot: View {
    @AppStorage(AppLauncherMode.storageKey) private var mode = AppLauncherMode.standard.rawValue
    var body: some View {
        Group {
            let selection = AppLauncherMode(rawValue: mode) ?? .standard
            if selection == .standard { HomeView() }
            else { RatioLauncherView(categoryStyle: selection == .category).id(selection) }
        }
        // The launcher has no HomeView, so the file and text-source requests are handled here for both homes.
        .modifier(HomeImportRequestPresenter())
    }
}
