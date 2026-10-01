import SwiftUI
import UIKit

/// Android `CameraControls.kt` 의 조작부 치수. `wide`(≥600dp)는 iPad, `compact`(높이 < 560)는 폰 가로.
struct VisionCraftCameraControlMetrics: Equatable {
    let isWide: Bool
    let isCompact: Bool

    init(bounds: CGSize) {
        isWide = bounds.width >= 600
        isCompact = bounds.height < 560
    }

    var tileWidth: CGFloat { isWide ? 96 : 76 }
    var tileMinHeight: CGFloat { isCompact ? 52 : (isWide ? 80 : 68) }
    var shutterSize: CGFloat { isCompact ? 80 : (isWide ? 124 : 100) }
    var gap: CGFloat { isCompact ? 8 : 14 }
    var horizontalInset: CGFloat { isWide ? 14 : 10 }
    /// 폰 가로처럼 높이가 모자라면 아이콘을 빼고 글자만 남긴다(설정 타일은 늘 아이콘을 보인다).
    var showsTileIcons: Bool { !isCompact }
}

/// Android `VcCamControl`: 모서리 16, 1.5pt 흰 테두리, #171717 면, 아이콘 28 + 라벨(16 SemiBold) + 상태(14 Medium).
/// 켬 상태는 #FFA05C 면 + #2B1200 글자, 상태 글자는 Bold. `isToggle` 이면 스크린리더에 스위치처럼 값과 함께 읽힌다.
/// `isOutlineHighlighted` 는 접힌 설정 타일처럼 "안에 켜진 것이 있다"를 3pt 주황 테두리로 알린다.
final class VisionCraftCameraControlTile: UIControl {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let stateLabel = UILabel()
    private let stack = UIStackView()
    var layoutWidth: CGFloat = 76 {
        didSet { invalidateIntrinsicContentSize() }
    }
    var minimumHeight: CGFloat = 68 {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: CGSize {
        let labelSize = CGSize(width: max(layoutWidth - 12, 1), height: .greatestFiniteMagnitude)
        let titleHeight = titleLabel.sizeThatFits(labelSize).height
        let stateHeight = stateLabel.isHidden ? 0 : stateLabel.sizeThatFits(labelSize).height
        let iconHeight: CGFloat = showsIcon ? 30 : 0 // 28pt icon + 2pt gap
        let contentHeight = iconHeight + titleHeight + (stateLabel.isHidden ? 0 : stateHeight + 2) + 16
        return CGSize(width: layoutWidth, height: max(minimumHeight, ceil(contentHeight)))
    }

    private static let surface = UIColor(VisionCraftCameraUI.surface)
    private static let pressedSurface = UIColor(VisionCraftCameraUI.pressed)
    private static let outline = UIColor(VisionCraftCameraUI.outline)
    private static let text = UIColor(VisionCraftCameraUI.text)
    private static let secondaryText = UIColor(VisionCraftCameraUI.secondaryText)
    private static let on = UIColor(VisionCraftCameraUI.on)
    private static let onText = UIColor(VisionCraftCameraUI.onText)

    var title: String = "" {
        didSet {
            titleLabel.text = title
            invalidateIntrinsicContentSize()
            refreshAccessibility()
        }
    }

    var stateText: String? {
        didSet {
            stateLabel.text = stateText
            stateLabel.isHidden = stateText == nil
            invalidateIntrinsicContentSize()
            refreshAccessibility()
        }
    }

    var systemImage: String = "" {
        didSet { updateIcon() }
    }

    /// nil 이면 일반 버튼, 값이 있으면 켜고 끄는 스위치.
    var isOn: Bool? {
        didSet {
            refreshColors()
            refreshAccessibility()
        }
    }

    var isOutlineHighlighted = false {
        didSet { refreshColors() }
    }

    var showsIcon = true {
        didSet {
            iconView.isHidden = !showsIcon
            invalidateIntrinsicContentSize()
        }
    }

    /// 스크린리더 전용 라벨·상태. 없으면 화면 글자(제목, 상태)를 그대로 읽는다.
    var accessibilityOverrideLabel: String? {
        didSet { refreshAccessibility() }
    }

    var accessibilityStateText: String? {
        didSet { refreshAccessibility() }
    }

    override var isHighlighted: Bool {
        didSet { refreshColors() }
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.45 }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        isAccessibilityElement = true
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (tile: VisionCraftCameraControlTile, _: UITraitCollection) in
            tile.invalidateIntrinsicContentSize()
        }

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = Self.text
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isAccessibilityElement = false

        titleLabel.font = UIFontMetrics(forTextStyle: .callout)
            .scaledFont(for: .systemFont(ofSize: 16, weight: .semibold))
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Self.text
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        titleLabel.isAccessibilityElement = false

        stateLabel.font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: .systemFont(ofSize: 14, weight: .medium))
        stateLabel.adjustsFontForContentSizeCategory = true
        stateLabel.textColor = Self.secondaryText
        stateLabel.textAlignment = .center
        stateLabel.numberOfLines = 1
        stateLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        stateLabel.isHidden = true
        stateLabel.isAccessibilityElement = false

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentCompressionResistancePriority(.required, for: .vertical)
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(stateLabel)
        addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
        ])
        refreshColors()
    }

    private func updateIcon() {
        iconView.image = UIImage(
            systemName: systemImage,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        )
    }

    private func refreshColors() {
        let on = isOn == true
        let textColor = on ? Self.onText : Self.text
        iconView.tintColor = textColor
        titleLabel.textColor = textColor
        stateLabel.textColor = on ? Self.onText : Self.secondaryText
        stateLabel.font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: .systemFont(ofSize: 14, weight: on ? .bold : .medium))
        invalidateIntrinsicContentSize()
        backgroundColor = on
            ? Self.on
            : (isHighlighted ? Self.pressedSurface : Self.surface)
        layer.borderWidth = isOutlineHighlighted ? 3 : 1.5
        layer.borderColor = (on || isOutlineHighlighted) ? Self.on.cgColor : Self.outline.cgColor
    }

    private func refreshAccessibility() {
        if isOn != nil {
            // Android: toggleable(role = Switch) + stateDescription("켬/끔").
            accessibilityLabel = accessibilityOverrideLabel ?? title
            accessibilityValue = stateText
            accessibilityTraits = [.button, .toggleButton]
        } else {
            if let accessibilityOverrideLabel {
                accessibilityLabel = accessibilityOverrideLabel
            } else if let stateText {
                accessibilityLabel = "\(title), \(stateText)"
            } else {
                accessibilityLabel = title
            }
            accessibilityValue = accessibilityStateText
            accessibilityTraits = .button
        }
    }
}

/// Android `VcCamShutter`: 흰 원 / 3pt 틈 / #171717 링 / 4pt 틈 / 채움. 안에 "촬영" 글자.
/// 이미지 분석·AI 질문 모드는 주황(#FFA05C) 채움 + #2B1200 글자. 누르면 #D0D0D0.
final class VisionCraftCameraShutterButton: UIControl {
    private let ringView = UIView()
    private let fillView = UIView()
    private let label = UILabel()

    private static let ring = UIColor(VisionCraftCameraUI.shutterRing)
    private static let pressed = UIColor(VisionCraftCameraUI.shutterPressed)
    private static let on = UIColor(VisionCraftCameraUI.on)
    private static let onText = UIColor(VisionCraftCameraUI.onText)

    var title: String = "" {
        didSet { label.text = title }
    }

    /// 이미지 분석·AI 질문 촬영처럼 강조색으로 그릴지.
    var isSpecial = false {
        didSet { refreshColors() }
    }

    override var isHighlighted: Bool {
        didSet { refreshColors() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .white
        isAccessibilityElement = true
        accessibilityTraits = .button

        ringView.backgroundColor = Self.ring
        ringView.isUserInteractionEnabled = false
        ringView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ringView)

        fillView.isUserInteractionEnabled = false
        fillView.translatesAutoresizingMaskIntoConstraints = false
        ringView.addSubview(fillView)

        label.font = UIFontMetrics(forTextStyle: .callout)
            .scaledFont(for: .systemFont(ofSize: 16, weight: .bold))
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.numberOfLines = 2
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.isAccessibilityElement = false
        label.translatesAutoresizingMaskIntoConstraints = false
        fillView.addSubview(label)

        NSLayoutConstraint.activate([
            ringView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            ringView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            ringView.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            ringView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            fillView.leadingAnchor.constraint(equalTo: ringView.leadingAnchor, constant: 4),
            fillView.trailingAnchor.constraint(equalTo: ringView.trailingAnchor, constant: -4),
            fillView.topAnchor.constraint(equalTo: ringView.topAnchor, constant: 4),
            fillView.bottomAnchor.constraint(equalTo: ringView.bottomAnchor, constant: -4),
            label.centerXAnchor.constraint(equalTo: fillView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: fillView.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: fillView.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: fillView.trailingAnchor, constant: -4),
        ])
        refreshColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        layer.masksToBounds = true
        ringView.layer.cornerRadius = max(0, bounds.width - 6) / 2
        ringView.layer.masksToBounds = true
        fillView.layer.cornerRadius = max(0, bounds.width - 14) / 2
        fillView.layer.masksToBounds = true
    }

    private func refreshColors() {
        if isSpecial {
            fillView.backgroundColor = Self.on
            label.textColor = Self.onText
        } else {
            fillView.backgroundColor = isHighlighted ? Self.pressed : .white
            label.textColor = Self.ring
        }
    }
}

/// 안쪽 여백이 있는 라벨. 카메라 위 안내 띠(VcCamStatusOverlay)에 쓴다.
final class VisionCraftPaddedLabel: UILabel {
    var contentInsets = UIEdgeInsets(top: 12, left: 18, bottom: 12, right: 18)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + contentInsets.left + contentInsets.right,
            height: size.height + contentInsets.top + contentInsets.bottom
        )
    }

    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let inset = bounds.inset(by: contentInsets)
        let rect = super.textRect(forBounds: inset, limitedToNumberOfLines: numberOfLines)
        return rect.inset(by: UIEdgeInsets(
            top: -contentInsets.top,
            left: -contentInsets.left,
            bottom: -contentInsets.bottom,
            right: -contentInsets.right
        ))
    }
}
