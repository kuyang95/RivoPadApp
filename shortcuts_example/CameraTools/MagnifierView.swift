import SwiftUI

struct MagnifierView: UIViewControllerRepresentable {
    @EnvironmentObject private var appRouter: AppRouter
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(
        context: Context
    ) -> MagnifierViewController {
        let controller = MagnifierViewController()
        controller.onClose = {
            dismiss()
        }
        controller.onCapture = { image in
            appRouter.route = .OCRResult(image: image)
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: MagnifierViewController,
        context: Context
    ) {}
}
