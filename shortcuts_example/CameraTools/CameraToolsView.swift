import SwiftUI

struct CameraToolsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                NavigationLink(value: AppRoute.magnifier) {
                    cameraToolCard(
                        title: "카메라 돋보기",
                        description:
                            "확대, 토치, 색상 필터로 가까운 대상을 봅니다.",
                        systemImage: "plus.magnifyingglass",
                        color: .indigo
                    )
                }
                .accessibilityHint(
                    "실시간 카메라 돋보기를 엽니다."
                )

                NavigationLink(value: AppRoute.liveTextReader) {
                    cameraToolCard(
                        title: "실시간 텍스트 읽기",
                        description:
                            "카메라에 보이는 글자를 찾아 자동으로 읽습니다.",
                        systemImage: "text.viewfinder",
                        color: .blue
                    )
                }
                .accessibilityHint(
                    "카메라 실시간 OCR과 자동 음성 읽기를 시작합니다."
                )

                NavigationLink(
                    value:
                        AppRoute
                        .imageDescriptionCamera
                ) {
                    cameraToolCard(
                        title: "이미지 설명",
                        description:
                            "사진을 촬영하고 M4 로컬 AI가 보이는 장면을 설명합니다.",
                        systemImage: "sparkles",
                        color: .purple
                    )
                }
                .accessibilityHint(
                    "카메라로 촬영한 이미지를 기기 안에서 분석합니다."
                )

                NavigationLink(value: AppRoute.documentScanning) {
                    cameraToolCard(
                        title: "문서 스캔",
                        description:
                            "문서 모서리를 찾고 촬영해 텍스트를 읽습니다.",
                        systemImage: "doc.viewfinder",
                        color: .black
                    )
                }
                .accessibilityHint(
                    "VisionCraft 방식의 문서 스캐너를 엽니다."
                )
            }
            .padding(32)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("카메라")
    }

    private func cameraToolCard(
        title: String,
        description: String,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack(spacing: 24) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .semibold))
                .frame(width: 72)

            VStack(alignment: .leading, spacing: 8) {
                Text(
                    AppLocalization.string(
                        title
                    )
                )
                    .font(.system(size: 30, weight: .bold))
                Text(
                    AppLocalization.string(
                        description
                    )
                )
                    .font(.title3)
                    .multilineTextAlignment(.leading)
                    .opacity(0.9)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.title2.bold())
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(color)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
        )
    }
}
