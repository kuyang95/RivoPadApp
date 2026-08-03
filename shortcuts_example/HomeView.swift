import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var rivoRemoteManager: RivoRemoteManager
    @ObservedObject private var localAIUsage = LocalAIUsageStore.shared

    @State private var isFileImporterPresented = false
    @State private var fileImportError: String?

    var body: some View {
        ZStack {
            VisionCraftUI.background
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    VisionCraftSectionHeader(title: "빠른 실행")

                    VisionCraftPrimaryActionPanel(
                        icon: "doc.text.magnifyingglass",
                        title: "AI와 문서 보기",
                        description: aiPanelDescription,
                        primaryTitle: "새 대화",
                        secondaryTitle: "대화 기록",
                        onPrimary: {
                            appRouter.route = .localChat(conversationID: nil)
                        },
                        onSecondary: {
                            appRouter.route = .chatHistory
                        }
                    )

                    sectionSpacer
                    VisionCraftSectionHeader(title: "읽기와 문서")
                    VisionCraftActionList(items: readingActions)

                    sectionSpacer
                    VisionCraftSectionHeader(title: "카메라와 연결")
                    VisionCraftActionList(items: cameraAndConnectionActions)

                    sectionSpacer
                    VisionCraftSectionHeader(title: "설정과 도움말")
                    VisionCraftActionList(items: settingsActions)
                }
                .padding(.horizontal, VisionCraftUI.horizontalPadding)
                .padding(.top, 24)
                .padding(.bottom, 36)
                .frame(maxWidth: VisionCraftUI.contentWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .visionCraftNavigationScreen()
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: VisionCraftFileTypes.openable,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .alert(
            "파일을 열 수 없습니다",
            isPresented: Binding(
                get: { fileImportError != nil },
                set: { isPresented in
                    if !isPresented {
                        fileImportError = nil
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {
                fileImportError = nil
            }
        } message: {
            Text(fileImportError ?? "")
        }
        .onChange(of: appRouter.fileImportRequestID) { oldValue, newValue in
            guard newValue != oldValue else {
                return
            }
            isFileImporterPresented = true
        }
        .onAppear {
            localAIUsage.refresh()
        }
    }

    private var sectionSpacer: some View {
        Color.clear
            .frame(height: VisionCraftUI.sectionSpacing)
            .accessibilityHidden(true)
    }

    private var readingActions: [VisionCraftActionItem] {
        [
            VisionCraftActionItem(
                id: "scanner",
                icon: "doc.viewfinder",
                title: "문서 스캔",
                description: "문서 한 장을 촬영해 텍스트로 이어갑니다.",
                action: { appRouter.route = .documentScanning }
            ),
            VisionCraftActionItem(
                id: "live-text",
                icon: "text.viewfinder",
                title: "실시간 텍스트 읽기",
                description: "카메라 앞 글자를 자동으로 읽습니다.",
                action: { appRouter.route = .liveTextReader }
            ),
            VisionCraftActionItem(
                id: "reader",
                icon: "book.closed",
                title: "데이지/EPUB 플레이어",
                description: "EPUB/DAISY 도서를 이어 읽습니다.",
                action: { appRouter.route = .readerLibrary }
            ),
            VisionCraftActionItem(
                id: "vision-link",
                icon: "desktopcomputer",
                title: "스마트폰과 연동",
                description: "원격 카메라를 사용하거나 스마트폰 파일을 받아옵니다.",
                action: { appRouter.route = .visionLink }
            ),
            VisionCraftActionItem(
                id: "files",
                icon: "folder",
                title: "파일과 문서",
                description: "기기 안의 문서를 열거나 허용한 폴더에서 검색합니다.",
                action: { appRouter.route = .documentLibrary }
            ),
        ]
    }

    private var cameraAndConnectionActions: [VisionCraftActionItem] {
        [
            VisionCraftActionItem(
                id: "magnifier",
                icon: "plus.magnifyingglass",
                title: "카메라 돋보기",
                description: "확대, 토치, 색상 필터로 가까운 대상을 봅니다.",
                action: { appRouter.route = .magnifier }
            ),
            VisionCraftActionItem(
                id: "describe-image",
                icon: "sparkles",
                title: "이미지 설명",
                description: "사진을 촬영하고 M4 로컬 AI가 보이는 장면을 설명합니다.",
                action: { appRouter.route = .imageDescriptionCamera }
            ),
            VisionCraftActionItem(
                id: "remote",
                icon: "dot.radiowaves.left.and.right",
                title: "Rivo 리모컨",
                description: rivoDescription,
                accent: rivoStatusColor,
                action: { appRouter.route = .rivoRemote }
            ),
        ]
    }

    private var settingsActions: [VisionCraftActionItem] {
        [
            VisionCraftActionItem(
                id: "settings",
                icon: "gearshape",
                title: "설정",
                description: "음성, 스캐너, 문서와 독서 기본 설정을 엽니다.",
                action: { appRouter.route = .settings }
            ),
            VisionCraftActionItem(
                id: "help",
                icon: "questionmark.circle",
                title: "도움말과 변경 내역",
                description: "VisionCraft 사용 설명서와 업데이트 기록을 봅니다.",
                action: { appRouter.route = .help }
            ),
        ]
    }

    private var aiPanelDescription: String {
        let base = AppLocalization.string(
            "문서, 클립보드, 사진을 첨부할 수 있는 새 채팅을 시작하거나 이전 대화를 엽니다."
        )
        let usage = localAIUsage.snapshot
        guard usage.totalRequests > 0 else {
            return base
        }

        let activity = AppLocalization.format(
            "오늘 %ld회 완료 · %@",
            usage.completedRequests,
            localAIUsageDuration(usage.inferenceSeconds)
        )
        return "\(base) \(activity)"
    }

    private var rivoDescription: String {
        AppLocalization.format(
            "연결 상태: %@",
            rivoHomeStatusTitle
        )
    }

    private var rivoHomeStatusTitle: String {
        switch rivoRemoteManager.state {
        case .inactive:
            return AppLocalization.string("연결 안 됨")
        default:
            return rivoRemoteManager.state.title
        }
    }

    private var rivoStatusColor: Color {
        switch rivoRemoteManager.state {
        case .ready:
            return VisionCraftUI.success
        case .permissionDenied,
             .unsupported,
             .bluetoothOff,
             .failed:
            return .red
        case .preparing,
             .scanning,
             .connecting,
             .discovering:
            return VisionCraftUI.warning
        case .inactive,
             .disconnected:
            return VisionCraftUI.primary
        }
    }

    private func localAIUsageDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return AppLocalization.format(
                "%ld초 처리",
                Int(seconds.rounded())
            )
        }
        return AppLocalization.format(
            "%ld분 처리",
            Int((seconds / 60).rounded())
        )
    }

    private func handleFileImport(
        _ result: Result<[URL], Error>
    ) {
        Task {
            do {
                guard let sourceURL = try result.get().first else {
                    return
                }
                appRouter.route = try await LocalFileOpening.route(
                    for: sourceURL
                )
            } catch {
                fileImportError = error.localizedDescription
            }
        }
    }
}
