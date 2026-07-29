import SwiftUI

struct MagnifierView: UIViewControllerRepresentable {
    let mode: MagnifierCameraMode

    @EnvironmentObject private var appRouter: AppRouter
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
        return controller
    }

    func updateUIViewController(
        _ uiViewController: MagnifierViewController,
        context: Context
    ) {}
}
