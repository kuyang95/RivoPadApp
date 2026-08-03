import SwiftUI

struct CameraToolsView: View {
    @EnvironmentObject private var appRouter: AppRouter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VisionCraftSectionHeader(title: "카메라 도구")
                VisionCraftActionList(items: actions)
            }
            .padding(.horizontal, VisionCraftUI.horizontalPadding)
            .padding(.top, 24)
            .padding(.bottom, 36)
            .frame(maxWidth: VisionCraftUI.contentWidth)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("카메라")
        .visionCraftNavigationScreen()
    }

    private var actions: [VisionCraftActionItem] {
        [
            VisionCraftActionItem(
                id: "magnifier",
                icon: "plus.magnifyingglass",
                title: "카메라 돋보기",
                description: "확대, 토치, 색상 필터로 가까운 대상을 봅니다.",
                action: { appRouter.route = .magnifier }
            ),
            VisionCraftActionItem(
                id: "live-text",
                icon: "text.viewfinder",
                title: "실시간 텍스트 읽기",
                description: "카메라에 보이는 글자를 찾아 자동으로 읽습니다.",
                action: { appRouter.route = .liveTextReader }
            ),
            VisionCraftActionItem(
                id: "image-description",
                icon: "sparkles",
                title: "이미지 설명",
                description: "사진을 촬영하고 M4 로컬 AI가 보이는 장면을 설명합니다.",
                action: { appRouter.route = .imageDescriptionCamera }
            ),
            VisionCraftActionItem(
                id: "scanner",
                icon: "doc.viewfinder",
                title: "문서 스캔",
                description: "문서 모서리를 찾고 촬영해 텍스트를 읽습니다.",
                action: { appRouter.route = .documentScanning }
            ),
        ]
    }
}
