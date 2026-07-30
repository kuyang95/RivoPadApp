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
        switch mode {
        case .magnifier:
            controller.onCapture = { image in
                appRouter.route = .OCRResult(image: image)
            }
        case .imageDescription:
            controller.onCapture = { image in
                appRouter.route = .capturedImageAnalysis(
                    image: image,
                    question:
                        "사진에 보이는 장면과 물체, 글자, 사람의 행동을 한국어로 자세히 설명해 줘. 확실히 보이지 않는 내용은 추측하지 마."
                )
            }
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
