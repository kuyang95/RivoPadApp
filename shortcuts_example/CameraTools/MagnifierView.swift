import SwiftUI

struct MagnifierView: UIViewControllerRepresentable {
    let mode: MagnifierCameraMode

    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var remoteControl:
        RivoScreenRemoteControlCenter
    @Environment(\.dismiss) private var dismiss

    init(mode: MagnifierCameraMode = .magnifier) {
        self.mode = mode
    }

    func makeUIViewController(
        context: Context
    ) -> MagnifierViewController {
        let controller = MagnifierViewController(mode: mode)
        controller.onClose = {
            dismiss()
        }
        controller.onOpenDocumentScan = {
            appRouter.route = .documentScanning
        }
        controller.onOpenLiveTextReader = {
            appRouter.route = .liveTextReader
        }
        controller.onDescribeImage = { image in
            appRouter.route = .capturedImageAnalysis(
                image: image,
                question: LocalImageDescriptionPrompt.defaultQuestion(
                    language: AppLanguage.current()
                )
            )
        }
        switch mode {
        case .magnifier:
            controller.onCapture = { image in
                appRouter.route = .OCRResult(image: image)
            }
        case .imageDescription:
            controller.onCapture = controller.onDescribeImage
        case .liveTextReader:
            break
        }
        controller.synchronizeRemoteEventCursor(
            to: remoteControl.latestEvent?.id
        )
        return controller
    }

    func updateUIViewController(
        _ uiViewController: MagnifierViewController,
        context: Context
    ) {
        guard let event = remoteControl.latestEvent,
              case .magnifier(let action) =
                event.action else {
            return
        }
        uiViewController.performRemoteAction(
            action,
            eventID: event.id
        )
    }
}

struct CameraMoreOptionsDialog: View {
    let onDocumentScan: () -> Void
    let onLiveTextReader: () -> Void
    let onImageDescription: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VisionCraftDialogCard(
            title: "더보기",
            cancelTitle: "닫기",
            onDismiss: onDismiss
        ) {
            ScrollView {
                VStack(spacing: 10) {
                    VisionCraftDialogOptionRow(
                        title: "문서 스캔",
                        systemImage: "doc.viewfinder",
                        isPrimary: true,
                        action: onDocumentScan
                    )
                    VisionCraftDialogOptionRow(
                        title: "실시간 문자 읽기",
                        systemImage: "text.viewfinder",
                        action: onLiveTextReader
                    )
                    VisionCraftDialogOptionRow(
                        title: "이미지 설명",
                        systemImage: "sparkles",
                        action: onImageDescription
                    )
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityAction(.escape, onDismiss)
    }
}

/// 안드로이드 VisionCraft `describeImage` 의 사용자 프롬프트와 같은 문구.
/// 분량 기준만 4문장 이하로 둔다.
nonisolated enum LocalImageDescriptionPrompt {
    static func defaultQuestion(
        language: AppLanguage
    ) -> String {
        """
        이미지에 보이는 내용을 \(language.localAIResponseLanguageName)로 4문장 이하로 짧게 설명해 줘.
        """
    }
}
