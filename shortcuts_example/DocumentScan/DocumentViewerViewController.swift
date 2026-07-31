//
//  DocumentViewerViewController.swift
//  shortcuts_example
//
//  Created by meee on 2/4/26.
//

import UIKit

final class DocumentViewerViewController: UIViewController {

    private let image: UIImage
    private let sentenceBoxes: [SentenceBox]

    private let imageView = UIImageView()
    private let overlayLayer = CALayer()

    private let leftButton = UIButton(type: .system)
    private let rightButton = UIButton(type: .system)

    private var boxLayers: [CAShapeLayer] = []
    private var currentIndex: Int = 0 {
        didSet { updateSelectionUIAndAccessibility() }
    }

    // 접근성 요소 캐시
    private var accessibilityItems: [UIAccessibilityElement] = []

    init(image: UIImage, sentenceBoxes: [SentenceBox]) {
        self.image = image
        self.sentenceBoxes = sentenceBoxes
        super.init(nibName: nil, bundle: nil)
        title = AppLocalization.string(
            "문서 보기"
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        setupUI()
        buildAccessibilityElements()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        rebuildOverlays()            // 레이아웃 변하면 박스 위치도 재계산
        updateAccessibilityFrames()  // 접근성 프레임도 재계산
    }

    private func setupUI() {
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        imageView.layer.addSublayer(overlayLayer)

        view.addSubview(imageView)

        // 하단 버튼
        var leftConfig = UIButton.Configuration.filled()
        leftConfig.title =
            AppLocalization.string("왼쪽")
        leftButton.configuration = leftConfig

        var rightConfig = UIButton.Configuration.filled()
        rightConfig.title =
            AppLocalization.string("오른쪽")
        rightButton.configuration = rightConfig

        leftButton.addTarget(self, action: #selector(goLeft), for: .touchUpInside)
        rightButton.addTarget(self, action: #selector(goRight), for: .touchUpInside)

        let buttonStack = UIStackView(arrangedSubviews: [leftButton, rightButton])
        buttonStack.axis = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually

        view.addSubview(buttonStack)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),

            buttonStack.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 12),
            buttonStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            buttonStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            buttonStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            buttonStack.heightAnchor.constraint(equalToConstant: 52),
        ])

        // overlayLayer는 imageView bounds 기반
        overlayLayer.frame = imageView.bounds

        // 이 화면은 “접근성 컨테이너”로 동작
        view.isAccessibilityElement = false
    }

    // MARK: - Box overlay

    private func rebuildOverlays() {
        overlayLayer.frame = imageView.bounds
        overlayLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        boxLayers.removeAll()

        for (i, sb) in sentenceBoxes.enumerated() {
            let rect = rectInImageView(fromNormalized: sb.boundingBoxNormalized)
            let path = UIBezierPath(rect: rect)

            let layer = CAShapeLayer()
            layer.path = path.cgPath
            layer.fillColor = UIColor.clear.cgColor
            layer.strokeColor = (i == currentIndex ? UIColor.systemBlue : UIColor.systemYellow).cgColor
            layer.lineWidth = (i == currentIndex ? 3 : 1)

            overlayLayer.addSublayer(layer)
            boxLayers.append(layer)
        }
    }

    private func updateSelectionUIAndAccessibility() {
        guard !sentenceBoxes.isEmpty else { return }
        currentIndex = max(0, min(currentIndex, sentenceBoxes.count - 1))

        // 박스 스타일 업데이트
        for (i, layer) in boxLayers.enumerated() {
            layer.strokeColor = (i == currentIndex ? UIColor.systemBlue : UIColor.systemYellow).cgColor
            layer.lineWidth = (i == currentIndex ? 3 : 1)
        }

        // VoiceOver 포커스 이동
        if currentIndex < accessibilityItems.count {
            UIAccessibility.post(notification: .layoutChanged, argument: accessibilityItems[currentIndex])
        }
    }

    // MARK: - Buttons

    @objc private func goLeft() {
        guard !sentenceBoxes.isEmpty else { return }
        currentIndex = max(0, currentIndex - 1)
    }

    @objc private func goRight() {
        guard !sentenceBoxes.isEmpty else { return }
        currentIndex = min(sentenceBoxes.count - 1, currentIndex + 1)
    }

    // MARK: - Accessibility container

    override var accessibilityElements: [Any]? {
        get { accessibilityItems }
        set { /* ignore */ }
    }

    private func buildAccessibilityElements() {
        accessibilityItems = sentenceBoxes.map { sb in
            let el = UIAccessibilityElement(accessibilityContainer: view)
            el.accessibilityLabel = sb.text
            el.accessibilityTraits = [.staticText]
            return el
        }
        updateAccessibilityFrames()
    }

    private func updateAccessibilityFrames() {
        guard !sentenceBoxes.isEmpty else { return }
        for (i, sb) in sentenceBoxes.enumerated() {
            let rectInImageView = rectInImageView(fromNormalized: sb.boundingBoxNormalized)
            let rectInView = imageView.convert(rectInImageView, to: view)
            if i < accessibilityItems.count {
                accessibilityItems[i].accessibilityFrameInContainerSpace = rectInView
            }
        }
    }

    // MARK: - Coordinate conversion (Vision normalized -> imageView rect)

    private func rectInImageView(fromNormalized n: CGRect) -> CGRect {
        // Vision normalized bbox: origin bottom-left
        // UIImage pixel space: origin top-left
        let imgSize = image.size

        let rectInImage = CGRect(
            x: n.minX * imgSize.width,
            y: (1.0 - n.maxY) * imgSize.height,
            width: n.width * imgSize.width,
            height: n.height * imgSize.height
        )

        // Convert image-space rect -> imageView-space rect (aspectFit)
        let ivBounds = imageView.bounds
        guard imgSize.width > 0, imgSize.height > 0, ivBounds.width > 0, ivBounds.height > 0 else {
            return .zero
        }

        let scale = min(ivBounds.width / imgSize.width, ivBounds.height / imgSize.height)
        let scaledSize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
        let xOffset = (ivBounds.width - scaledSize.width) / 2.0
        let yOffset = (ivBounds.height - scaledSize.height) / 2.0

        return CGRect(
            x: rectInImage.minX * scale + xOffset,
            y: rectInImage.minY * scale + yOffset,
            width: rectInImage.width * scale,
            height: rectInImage.height * scale
        )
    }
}
