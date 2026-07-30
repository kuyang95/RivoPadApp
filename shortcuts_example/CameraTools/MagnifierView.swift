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
        if mode == .magnifier {
            controller.onCapture = { image in
                appRouter.route = .OCRResult(image: image)
            }
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
