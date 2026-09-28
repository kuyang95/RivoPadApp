import SwiftUI
import UIKit

struct ExcelDocumentLoadingView: View {
    var message = AppLocalization.string("엑셀 파일을 여는 중…")

    var body: some View {
        ProgressView {
            Text(message)
        }
        .progressViewStyle(ExcelDocumentProgressStyle())
    }
}

private struct ExcelDocumentProgressStyle: ProgressViewStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 16) {
            ExcelLoadingCells(isAnimating: !reduceMotion && scenePhase == .active)
            .frame(width: 76, height: 64)
            .accessibilityHidden(true)

            configuration.label
                .font(.subheadline.weight(.medium))
                .foregroundStyle(VisionCraftUI.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct ExcelLoadingCells: UIViewRepresentable {
    let isAnimating: Bool

    func makeUIView(context: Context) -> ExcelLoadingCellsView {
        ExcelLoadingCellsView()
    }

    func updateUIView(_ view: ExcelLoadingCellsView, context: Context) {
        view.setAnimating(isAnimating)
    }

    static func dismantleUIView(_ view: ExcelLoadingCellsView, coordinator: ()) {
        view.setAnimating(false)
    }
}

/// Core Animation runs these committed layer animations in the render server.
/// A TimelineView needs the main thread for every frame and freezes while the
/// first document layout is being prepared, even when parsing runs off-thread.
private final class ExcelLoadingCellsView: UIView {
    private let cells = (0 ..< 9).map { _ in CALayer() }
    private let fills = (0 ..< 9).map { _ in CAGradientLayer() }
    private var isAnimating = false
    private let duration = 2.4
    private let animationKey = "documentLoadingPulse"

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        for (cell, fill) in zip(cells, fills) {
            cell.bounds = CGRect(x: 0, y: 0, width: 18, height: 13)
            cell.cornerRadius = 3
            cell.shadowRadius = 3
            cell.shadowOffset = CGSize(width: 0, height: 2)
            fill.frame = cell.bounds
            fill.cornerRadius = 3
            fill.startPoint = CGPoint(x: 0, y: 0)
            fill.endPoint = CGPoint(x: 1, y: 1)
            cell.addSublayer(fill)
            layer.addSublayer(cell)
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (view: ExcelLoadingCellsView, _: UITraitCollection) in
            view.updateColors()
        }
        updateColors()
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, cell) in cells.enumerated() {
            cell.position = CGPoint(
                x: (bounds.width - 64) / 2 + 9 + CGFloat(index % 3) * 23,
                y: (bounds.height - 49) / 2 + 6.5 + CGFloat(index / 3) * 18
            )
        }
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAnimations()
    }

    func setAnimating(_ enabled: Bool) {
        isAnimating = enabled
        updateAnimations()
    }

    private func updateColors() {
        let primary = UIColor(VisionCraftUI.primary).resolvedColor(with: traitCollection)
        let success = UIColor(VisionCraftUI.success).resolvedColor(with: traitCollection)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (cell, fill) in zip(cells, fills) {
            cell.backgroundColor = primary.withAlphaComponent(0.12).cgColor
            cell.shadowColor = primary.cgColor
            fill.colors = [primary.cgColor, success.cgColor]
        }
        CATransaction.commit()
    }

    private func updateAnimations() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let beginTime = CACurrentMediaTime()
        for index in cells.indices {
            let cell = cells[index]
            let fill = fills[index]
            let delay = Double(index / 3 + index % 3) * 0.13
            guard isAnimating, window != nil else {
                cell.removeAnimation(forKey: animationKey)
                fill.removeAnimation(forKey: animationKey)
                let value = illumination(phase: 0.6 / duration - delay)
                cell.transform = transform(illumination: value)
                cell.shadowOpacity = Float(value * 0.16)
                fill.opacity = Float(0.22 + value * 0.78)
                continue
            }
            // SwiftUI status updates must not restart an in-flight pulse.
            guard cell.animation(forKey: animationKey) == nil else { continue }
            let values = (0 ... 60).map { illumination(phase: Double($0) / 60 - delay) }
            let movement = CAKeyframeAnimation(keyPath: "transform")
            movement.duration = duration
            movement.values = values.map { NSValue(caTransform3D: transform(illumination: $0)) }
            let shadow = CAKeyframeAnimation(keyPath: "shadowOpacity")
            shadow.duration = duration
            shadow.values = values.map { $0 * 0.16 }
            let group = CAAnimationGroup()
            group.animations = [movement, shadow]
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = values.map { 0.22 + $0 * 0.78 }
            for animation in [group, opacity] {
                animation.duration = duration
                animation.beginTime = beginTime
                animation.repeatCount = .infinity
            }
            cell.add(group, forKey: animationKey)
            fill.add(opacity, forKey: animationKey)
        }
    }

    private func illumination(phase: Double) -> Double {
        pow((cos(phase * 2 * .pi) + 1) / 2, 3)
    }

    private func transform(illumination: Double) -> CATransform3D {
        let scale = 0.88 + illumination * 0.12
        return CATransform3DScale(
            CATransform3DMakeTranslation(0, -illumination * 3, 0), scale, scale, 1
        )
    }
}

#Preview("Excel loading") {
    ExcelDocumentLoadingView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisionCraftUI.background)
}

#Preview("Excel loading · Dark") {
    ExcelDocumentLoadingView()
        .preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisionCraftUI.background)
}
