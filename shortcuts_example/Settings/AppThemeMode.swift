import SwiftUI

nonisolated enum AppThemeMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    static let preferenceKey = "settings.appTheme.v1"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "시스템 설정에 따름"
        case .light: "라이트"
        case .dark: "다크"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
