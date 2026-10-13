#if DEBUG
import SwiftUI

/// Keep this screen and every entry point inside DEBUG compilation guards.
struct DebugDevelopmentView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VisionCraftScreenTitleRow(
                title: "개발 화면",
                onBack: { dismiss() }
            )
            .padding(.horizontal, 24)
            .padding(.top, 12)

            Form {
                Section {
                    LabeledContent("빌드 환경", value: "Debug")
                    LabeledContent("앱 버전", value: bundleValue("CFBundleShortVersionString"))
                    LabeledContent("빌드 번호", value: bundleValue("CFBundleVersion"))
                } header: {
                    Text("빌드 정보")
                } footer: {
                    Text("이 화면과 설정의 진입 항목은 Debug 빌드에만 포함됩니다.")
                }

                Section {
                    NavigationLink {
                        AccessibleWebBrowserView()
                    } label: {
                        Label("접근성 웹", systemImage: "globe")
                    }
                    .accessibilityHint("사진을 유지하고 웹 색상을 통일하는 브라우저를 엽니다.")

                    NavigationLink {
                        HWPReferenceComparisonView()
                            .visionCraftRouteBackButton()
                            .toolbar(.visible, for: .navigationBar)
                    } label: {
                        Label("HWP 비교 테스트", systemImage: "rectangle.split.2x1")
                    }
                } header: {
                    Text("개발 도구")
                } footer: {
                    Text("개발 중인 기능과 테스트 도구를 이 화면에 추가합니다.")
                }
            }
            .environment(\.defaultMinListRowHeight, VisionCraftUI.minTouchTarget)
            .visionCraftListScreen()
        }
        .background(VisionCraftUI.background.ignoresSafeArea())
        .tint(VisionCraftUI.primary)
        .toolbar(.hidden, for: .navigationBar)
        .visionCraftHandlesBackNavigation()
        .accessibilityAction(.escape) { dismiss() }
    }

    private func bundleValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "—"
    }
}
#endif
