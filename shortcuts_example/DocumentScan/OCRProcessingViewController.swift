//
//  OCRProcessingViewController.swift
//  shortcuts_example
//
//  Created by meee on 2/4/26.
//

import UIKit
import Combine

final class OCRProcessingViewController: UIViewController {

    private let image: UIImage
    private var isProcessing = false

    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let statusLabel: UILabel = {
        let l = UILabel()
        l.text = AppLocalization.string(
            "OCR 처리 중..."
        )
        l.textAlignment = .center
        l.numberOfLines = 2
        l.textColor = .secondaryLabel
        return l
    }()

    init(image: UIImage) {
        self.image = image
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = AppLocalization.string(
            "처리(B)"
        )
        view.backgroundColor = .systemBackground

        setupUI()
        runOCR()
    }

    private func setupUI() {
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black.withAlphaComponent(0.03)
        imageView.layer.cornerRadius = 12
        imageView.clipsToBounds = true

        [imageView, spinner, statusLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            imageView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            imageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.55),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 20),

            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])

        spinner.startAnimating()
    }

    private func runOCR() {
        guard !isProcessing else { return }
        isProcessing = true

        DocumentTextExtractor().extractSentenceBoxes(from: image) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.spinner.stopAnimating()
                self.isProcessing = false

                // ✅ 사용자가 이미 뒤로 갔으면 push하지 않게 방지
                guard self.view.window != nil else { return }

                switch result {
                case .success(let boxes):
                    let viewer = DocumentViewerViewController(image: self.image, sentenceBoxes: boxes)
                    self.navigationController?.pushViewController(viewer, animated: true)

                case .failure(let error):
                    self.statusLabel.text =
                        AppLocalization.format(
                            "OCR 실패: %@",
                            error.localizedDescription
                        )
                    let alert = UIAlertController(
                        title: AppLocalization.string(
                            "처리 실패"
                        ),
                        message:
                            error.localizedDescription,
                        preferredStyle: .alert
                    )
                    alert.addAction(
                        UIAlertAction(
                            title: AppLocalization.string(
                                "확인"
                            ),
                            style: .default
                        )
                    )
                    alert.addAction(
                        UIAlertAction(
                            title: AppLocalization.string(
                                "재시도"
                            ),
                            style: .default
                        ) { [weak self] _ in
                            guard let self else {
                                return
                            }
                            self.spinner
                                .startAnimating()
                            self.statusLabel.text =
                                AppLocalization.string(
                                    "OCR 처리 중..."
                                )
                            self.runOCR()
                        }
                    )
                    self.present(alert, animated: true)
                }
            }
        }
    }
}
