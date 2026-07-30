import UIKit

/// Keeps the existing SwiftUI bridge stable while routing every scan through
/// Rivo's local AVFoundation + LCNet + UVDoc implementation.
final class DocumentScannerViewController: UIViewController {
    var allowsAutomaticStart = true {
        didSet {
            scanner.allowsAutomaticStart =
                allowsAutomaticStart
        }
    }

    var automaticCaptureEnabled = true {
        didSet {
            scanner.automaticCaptureEnabled =
                automaticCaptureEnabled
        }
    }

    var curvedPageCorrectionEnabled = true {
        didSet {
            scanner.curvedPageCorrectionEnabled =
                curvedPageCorrectionEnabled
        }
    }

    var onScanCompleted: ((UIImage) -> Void)? {
        didSet {
            scanner.onScanCompleted = onScanCompleted
        }
    }

    var onCancel: (() -> Void)? {
        didSet {
            scanner.onCancel = onCancel
        }
    }

    private lazy var scanner: LocalDocumentScannerViewController = {
        let controller = LocalDocumentScannerViewController()
        controller.onScanCompleted = onScanCompleted
        controller.onCancel = onCancel
        return controller
    }()
    private var lastRemoteEventID: UInt64 = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        scanner.allowsAutomaticStart =
            allowsAutomaticStart
        scanner.automaticCaptureEnabled =
            automaticCaptureEnabled
        scanner.curvedPageCorrectionEnabled =
            curvedPageCorrectionEnabled
        addChild(scanner)
        scanner.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanner.view)
        NSLayoutConstraint.activate([
            scanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scanner.view.topAnchor.constraint(equalTo: view.topAnchor),
            scanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        scanner.didMove(toParent: self)
    }

    func synchronizeRemoteEventCursor(
        to eventID: UInt64?
    ) {
        lastRemoteEventID = eventID ?? 0
    }

    func performRemoteAction(
        _ action: RivoDocumentScannerRemoteAction,
        eventID: UInt64
    ) {
        guard eventID != lastRemoteEventID else {
            return
        }
        lastRemoteEventID = eventID
        scanner.performRemoteAction(action)
    }

    func resumeAfterReview() {
        scanner.resumeAfterReview()
    }

    func acceptPageAndContinue(
        capturedPageCount: Int
    ) {
        scanner.acceptPageAndContinue(
            capturedPageCount:
                capturedPageCount
        )
    }

    func finishReview(
        capturedPageCount: Int
    ) {
        scanner.finishReview(
            capturedPageCount:
                capturedPageCount
        )
    }

    func startNewPageSession() {
        scanner.startNewPageSession()
    }
}
