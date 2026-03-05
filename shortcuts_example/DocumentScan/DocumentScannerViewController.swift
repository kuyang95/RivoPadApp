import UIKit
import VisionKit

final class DocumentScannerViewController: UIViewController, VNDocumentCameraViewControllerDelegate {

    // MARK: - State
    
    private var hasLaunchedScanner = false
    private var didPrewarm = false

    // MARK: - Loading Overlay UI
    
    private let loadingOverlay: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        view.alpha = 0
        return view
    }()
    
    private let loadingLabel: UILabel = {
        let label = UILabel()
        label.text = "스캐너 준비중..."
        label.textColor = .white
        label.font = .boldSystemFont(ofSize: 22)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupLoadingOverlay()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // ✅ VisionKit prewarm 한 번만
        if !didPrewarm {
            didPrewarm = true
            prewarmVisionKitOnce()
        }

        // ✅ 스캐너 자동 실행 한 번만
        guard !hasLaunchedScanner else { return }
        hasLaunchedScanner = true

        showLoadingOverlay()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.hideLoadingOverlay()
            self.startScan()
        }
    }

    // MARK: - Loading Overlay Setup

    private func setupLoadingOverlay() {
        loadingOverlay.frame = view.bounds
        loadingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        view.addSubview(loadingOverlay)
        loadingOverlay.addSubview(loadingLabel)
        loadingOverlay.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            loadingLabel.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            loadingLabel.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor, constant: -20),
            
            activityIndicator.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: loadingLabel.bottomAnchor, constant: 16)
        ])
    }

    private func showLoadingOverlay() {
        activityIndicator.startAnimating()
        UIView.animate(withDuration: 0.25) {
            self.loadingOverlay.alpha = 1
        }
    }

    private func hideLoadingOverlay() {
        UIView.animate(withDuration: 0.25) {
            self.loadingOverlay.alpha = 0
        }
    }

    // MARK: - VisionKit Prewarm

    private func prewarmVisionKitOnce() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard VNDocumentCameraViewController.isSupported else { return }
            _ = VNDocumentCameraViewController()
            print("VisionKit prewarm done")
        }
    }

    // MARK: - Start Scan

    @objc private func startScan() {
        print("스캐너 시작 호출")

        guard VNDocumentCameraViewController.isSupported else {
            let alert = UIAlertController(
                title: "지원되지 않음",
                message: "이 기기에서는 문서 스캐너를 사용할 수 없어요.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "확인", style: .default))
            present(alert, animated: true)
            return
        }

        let scanner = VNDocumentCameraViewController()
        scanner.delegate = self

        present(scanner, animated: true)
    }

    // MARK: - VNDocumentCameraViewControllerDelegate

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {
        controller.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            guard scan.pageCount > 0 else { return }

            let scannedImage = scan.imageOfPage(at: 0)
            let vc = OCRResultViewController(image: scannedImage)
            self.navigationController?.pushViewController(vc, animated: true)
        }
    }

    func documentCameraViewControllerDidCancel(
        _ controller: VNDocumentCameraViewController
    ) {
        controller.dismiss(animated: true)
        
        // 🔥 원하면 재실행 허용
        // hasLaunchedScanner = false
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFailWithError error: Error
    ) {
        controller.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            
            let alert = UIAlertController(
                title: "스캔 실패",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "확인", style: .default))
            self.present(alert, animated: true)
        }
    }
}
