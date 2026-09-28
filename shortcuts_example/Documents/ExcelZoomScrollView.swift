import SwiftUI
import UIKit

/// UIKit owns pan and pinch in stable document coordinates. The grid redraws
/// at its final text size after zooming, without resizing the zoom target.
struct ExcelZoomScrollView<Content: View>: UIViewControllerRepresentable {
    let contentSize: CGSize
    @Binding var zoomScale: CGFloat
    let zoomRange: ClosedRange<CGFloat>
    var onTap: ((CGPoint) -> Void)? = nil
    var onRangeDrag: ((CGPoint, CGPoint) -> Void)? = nil
    var revealRect: CGRect? = nil
    var frozenSize: CGSize = .zero
    var selectedDrawing: ExcelDrawingHitRegion? = nil
    var drawingContains: ((CGPoint) -> Bool)? = nil
    var onDrawingDrag: ((String, CGRect?, Bool) -> Void)? = nil
    @ViewBuilder var content: (CGRect, CGFloat) -> Content

    func makeUIViewController(context: Context) -> ExcelZoomScrollController<AnyView> {
        ExcelZoomScrollController(
            contentSize: contentSize,
            zoomRange: zoomRange,
            content: { rect, renderScale in
                AnyView(content(rect, renderScale).environment(\.self, context.environment))
            }
        )
    }

    func updateUIViewController(
        _ controller: ExcelZoomScrollController<AnyView>,
        context: Context
    ) {
        controller.onTap = onTap
        controller.onRangeDrag = onRangeDrag
        controller.selectedDrawing = selectedDrawing
        controller.drawingContains = drawingContains
        controller.onDrawingDrag = onDrawingDrag
        controller.update(contentSize: contentSize, zoomScale: zoomScale, frozenSize: frozenSize) { rect, renderScale in
            AnyView(content(rect, renderScale).environment(\.self, context.environment))
        }
        controller.onZoomEnd = { zoomScale = $0 }
        controller.requestReveal(revealRect)
    }
}

@MainActor
final class ExcelZoomScrollController<Content: View>: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let scrollView = UIScrollView()
    private let zoomContentView = UIView()
    private let host: UIHostingController<Content>
    private var makeContent: (CGRect, CGFloat) -> Content
    private var documentSize: CGSize
    private var renderedRect: CGRect?
    private var lastRequestedScale: CGFloat = 1
    private var renderZoomScale: CGFloat = 1
    private var renderedScale: CGFloat = 0
    private var isUpdating = false
    private var lastRevealRect: CGRect?
    private var pendingRevealRect: CGRect?
    var onZoomEnd: ((CGFloat) -> Void)?
    var onTap: ((CGPoint) -> Void)?
    var onRangeDrag: ((CGPoint, CGPoint) -> Void)?
    var selectedDrawing: ExcelDrawingHitRegion?
    var drawingContains: ((CGPoint) -> Bool)?
    var onDrawingDrag: ((String, CGRect?, Bool) -> Void)?
    private var drawingDrag: (region: ExcelDrawingHitRegion, mode: ExcelDrawingDragMode, start: CGPoint)?
    private weak var drawingPanGesture: UIPanGestureRecognizer?
    private var rangeStart: CGPoint?
    private var frozenSize = CGSize.zero
    private var isAdjustingFrozenInsets = false
    private let frozenRowLine = UIView()
    private let frozenColumnLine = UIView()

    private final class FrozenSurface {
        let clip = UIView()
        let host: UIHostingController<Content>
        var renderedRect: CGRect?
        var renderedScale: CGFloat = 0
        init(content: Content) { host = UIHostingController(rootView: content) }
    }
    private var frozenSurfaces: [ExcelFrozenViewport.Part: FrozenSurface] = [:]
    private var viewport: ExcelFrozenViewport {
        ExcelFrozenViewport(documentSize: documentSize, viewportSize: scrollView.bounds.size, frozenSize: frozenSize,
                            scale: max(0.01, scrollView.zoomScale), offset: scrollView.contentOffset)
    }

    init(
        contentSize: CGSize,
        zoomRange: ClosedRange<CGFloat>,
        content: @escaping (CGRect, CGFloat) -> Content
    ) {
        documentSize = contentSize
        makeContent = content
        host = UIHostingController(rootView: content(.zero, 1))
        super.init(nibName: nil, bundle: nil)
        scrollView.minimumZoomScale = zoomRange.lowerBound
        scrollView.maximumZoomScale = zoomRange.upperBound
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scrollView.backgroundColor = .clear
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bouncesZoom = false
        // One native tap selects a cell; pans and two-finger pinches win first.
        // SwiftUI cell buttons otherwise compete with the scroll view's pinch.
        let tap = UITapGestureRecognizer(target: self, action: #selector(selectCell(_:)))
        tap.require(toFail: scrollView.panGestureRecognizer)
        if let pinch = scrollView.pinchGestureRecognizer {
            tap.require(toFail: pinch)
        }
        scrollView.addGestureRecognizer(tap)
        let rangeDrag = UILongPressGestureRecognizer(target: self, action: #selector(selectRange(_:)))
        rangeDrag.minimumPressDuration = 0.35
        rangeDrag.numberOfTouchesRequired = 1
        rangeDrag.allowableMovement = 12
        rangeDrag.delegate = self
        scrollView.addGestureRecognizer(rangeDrag)
        scrollView.panGestureRecognizer.require(toFail: rangeDrag)
        tap.require(toFail: rangeDrag)
        let drawingPan = UIPanGestureRecognizer(target: self, action: #selector(manipulateDrawing(_:)))
        drawingPan.maximumNumberOfTouches = 1
        drawingPan.delegate = self
        drawingPanGesture = drawingPan
        scrollView.addGestureRecognizer(drawingPan)
        scrollView.panGestureRecognizer.require(toFail: drawingPan)
        rangeDrag.require(toFail: drawingPan)
        tap.require(toFail: drawingPan)
        view.addSubview(scrollView)
        scrollView.addSubview(zoomContentView)
        addChild(host)
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        zoomContentView.addSubview(host.view)
        host.didMove(toParent: self)
        for line in [frozenRowLine, frozenColumnLine] {
            line.backgroundColor = .separator
            line.isUserInteractionEnabled = false
            line.accessibilityElementsHidden = true
            scrollView.addSubview(line)
        }
        resizeDocument()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
        configureFrozenInsets()
        applyPendingReveal()
        refreshVisibleContent()
    }

    func update(
        contentSize: CGSize,
        zoomScale: CGFloat,
        frozenSize requestedFrozenSize: CGSize = .zero,
        content: @escaping (CGRect, CGFloat) -> Content
    ) {
        isUpdating = true
        defer { isUpdating = false }
        loadViewIfNeeded()
        makeContent = content
        if documentSize != contentSize {
            documentSize = contentSize
            resizeDocument()
        }
        let nextFrozenSize = CGSize(width: min(max(0, requestedFrozenSize.width), documentSize.width), height: min(max(0, requestedFrozenSize.height), documentSize.height))
        if frozenSize != nextFrozenSize {
            frozenSize = nextFrozenSize
            renderedRect = nil
            lastRevealRect = nil
        }

        // A selection or editor update during a pinch must not restore the
        // previous SwiftUI scale. Only a new control request changes native zoom.
        if zoomScale.isFinite, abs(zoomScale - lastRequestedScale) > 0.0001 {
            let scale = min(max(zoomScale, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
            lastRequestedScale = scale
            renderZoomScale = max(1, scale)
            let visible = scrollView.convert(scrollView.bounds, to: zoomContentView)
            scrollView.setZoomScale(scale, animated: false)
            if scrollView.bounds.width > 0, scrollView.bounds.height > 0 {
                // Control buttons adjust the center once, synchronously.
                // Pinch updates never enter this path.
                scrollView.setContentOffset(CGPoint(
                    x: min(max(0, visible.midX * scale - scrollView.bounds.width / 2),
                           max(0, scrollView.contentSize.width - scrollView.bounds.width)),
                    y: min(max(0, visible.midY * scale - scrollView.bounds.height / 2),
                           max(0, scrollView.contentSize.height - scrollView.bounds.height))
                ), animated: false)
            }
        }
        configureFrozenInsets()
        refreshVisibleContent(force: true)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        zoomContentView
    }

    func requestReveal(_ rect: CGRect?) {
        guard rect != lastRevealRect else { return }
        lastRevealRect = rect
        pendingRevealRect = rect
        applyPendingReveal()
    }

    private func applyPendingReveal() {
        guard let rect = pendingRevealRect,
              scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
        pendingRevealRect = nil
        scrollView.setContentOffset(viewport.revealing(rect), animated: false)
    }

    @objc private func selectCell(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        onTap?(viewport.documentPoint(at: gesture.location(in: view)))
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let point = viewport.documentPoint(at: touch.location(in: view))
        if gesture === drawingPanGesture {
            guard let region = selectedDrawing, onDrawingDrag != nil else { return false }
            return ExcelDrawingDragMode.hit(point, rect: region.rect, radius: 22 / viewport.scale) != nil
        }
        if gesture is UILongPressGestureRecognizer { return drawingContains?(point) != true }
        return true
    }

    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        if let pan = gesture as? UIPanGestureRecognizer, pan === drawingPanGesture {
            guard let region = selectedDrawing, onDrawingDrag != nil else { return false }
            let translation = pan.translation(in: view), location = pan.location(in: view)
            let start = viewport.documentPoint(at: CGPoint(x: location.x - translation.x, y: location.y - translation.y))
            guard let mode = ExcelDrawingDragMode.hit(start, rect: region.rect, radius: 22 / viewport.scale) else { return false }
            drawingDrag = (region, mode, start)
            return true
        }
        if gesture is UILongPressGestureRecognizer {
            return drawingContains?(viewport.documentPoint(at: gesture.location(in: view))) != true
        }
        return true
    }

    @objc private func manipulateDrawing(_ gesture: UIPanGestureRecognizer) {
        guard let drag = drawingDrag else { return }
        if gesture.state == .cancelled || gesture.state == .failed || selectedDrawing?.id != drag.region.id {
            onDrawingDrag?(drag.region.id, nil, true)
            drawingDrag = nil
            return
        }
        guard gesture.state == .began || gesture.state == .changed || gesture.state == .ended else { return }
        let location = gesture.location(in: view)
        if gesture.state == .changed {
            var offset = scrollView.contentOffset
            let insets = viewport.insets
            if location.x >= insets.width, location.x < insets.width + 24 { offset.x -= 12 }
            if location.x > view.bounds.width - 24 { offset.x += 12 }
            if location.y >= insets.height, location.y < insets.height + 24 { offset.y -= 12 }
            if location.y > view.bounds.height - 24 { offset.y += 12 }
            scrollView.setContentOffset(viewport.clamped(offset), animated: false)
        }
        let current = viewport.documentPoint(at: location)
        let next = drag.mode.applying(CGPoint(x: current.x - drag.start.x, y: current.y - drag.start.y), to: drag.region.rect, within: drag.region.bounds)
        let ended = gesture.state == .ended
        if ended { drawingDrag = nil }
        onDrawingDrag?(drag.region.id, next, ended)
    }

    @objc private func selectRange(_ gesture: UILongPressGestureRecognizer) {
        guard onRangeDrag != nil else { return }
        switch gesture.state {
        case .began:
            rangeStart = viewport.documentPoint(at: gesture.location(in: view))
        case .changed:
            let point = gesture.location(in: view)
            let step: CGFloat = 18
            var offset = scrollView.contentOffset
            if point.y >= viewport.insets.height, point.y < viewport.insets.height + 36 { offset.y -= step }
            if point.y > view.bounds.height - 36 { offset.y += step }
            if point.x >= viewport.insets.width, point.x < viewport.insets.width + 36 { offset.x -= step }
            if point.x > view.bounds.width - 36 { offset.x += step }
            scrollView.setContentOffset(viewport.clamped(offset), animated: false)
        case .ended, .cancelled, .failed:
            if let start = rangeStart { onRangeDrag?(start, viewport.documentPoint(at: gesture.location(in: view))) }
            rangeStart = nil
            return
        default: return
        }
        if let start = rangeStart { onRangeDrag?(start, viewport.documentPoint(at: gesture.location(in: view))) }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        refreshVisibleContent()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        configureFrozenInsets()
        refreshVisibleContent()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        guard !isUpdating else { return }
        lastRequestedScale = scale
        renderZoomScale = max(1, scale)
        refreshVisibleContent(force: true)
        onZoomEnd?(scale)
    }

    private func resizeDocument() {
        let scale = scrollView.zoomScale
        zoomContentView.bounds = CGRect(origin: .zero, size: documentSize)
        zoomContentView.center = CGPoint(
            x: documentSize.width * scale / 2,
            y: documentSize.height * scale / 2
        )
        resizeHostedContent()
        scrollView.contentSize = CGSize(
            width: documentSize.width * scale,
            height: documentSize.height * scale
        )
        renderedRect = nil
    }

    private func refreshVisibleContent(force: Bool = false) {
        guard isViewLoaded, scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
        refreshFrozenContent(force: force)
        let bounds = CGRect(origin: .zero, size: documentSize)
        let visible = viewport.bodyRect.intersection(bounds)
        guard !visible.isNull else { return }
        if !force, let renderedRect, renderedRect.contains(visible), renderedScale == renderZoomScale { return }

        // Keep nearby rows mounted, without constructing all 400 x 40 cells.
        // Their absolute positions and the zoom target's bounds never change
        // as rows enter or leave the viewport.
        let rect = viewport.buffered(visible)
        guard !rect.isNull, !rect.isEmpty else { return }
        renderedRect = rect
        renderedScale = renderZoomScale
        UIView.performWithoutAnimation {
            host.rootView = makeContent(rect, renderZoomScale)
            resizeHostedContent()
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }
    }

    private func configureFrozenInsets() {
        guard !isAdjustingFrozenInsets, scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
        isAdjustingFrozenInsets = true
        defer { isAdjustingFrozenInsets = false }
        let minimum = viewport.minimumOffset
        let insets = UIEdgeInsets(top: -minimum.y, left: -minimum.x, bottom: 0, right: 0)
        if scrollView.contentInset != insets { scrollView.contentInset = insets }
        let offset = viewport.clamped(scrollView.contentOffset)
        if offset != scrollView.contentOffset { scrollView.setContentOffset(offset, animated: false) }
    }

    private func refreshFrozenContent(force: Bool) {
        let layout = viewport
        for part in ExcelFrozenViewport.Part.allCases {
            let frame = layout.frame(for: part)
            let visible = layout.visibleRect(for: part).intersection(layout.domain(for: part))
            guard frame.width > 0, frame.height > 0, !visible.isEmpty, !visible.isNull else {
                frozenSurfaces[part]?.clip.isHidden = true
                continue
            }
            let surface: FrozenSurface
            if let existing = frozenSurfaces[part] { surface = existing }
            else {
                surface = FrozenSurface(content: makeContent(visible, renderZoomScale))
                surface.clip.clipsToBounds = true
                surface.clip.backgroundColor = .systemBackground
                scrollView.addSubview(surface.clip)
                addChild(surface.host)
                surface.host.safeAreaRegions = []
                surface.host.view.backgroundColor = .clear
                surface.clip.addSubview(surface.host.view)
                surface.host.didMove(toParent: self)
                frozenSurfaces[part] = surface
            }
            surface.clip.isHidden = false
            surface.clip.frame = frame.offsetBy(dx: scrollView.contentOffset.x, dy: scrollView.contentOffset.y)
            if force || surface.renderedRect?.contains(visible) != true || surface.renderedScale != renderZoomScale {
                let buffered = layout.buffered(visible, part: part)
                surface.host.rootView = makeContent(buffered, renderZoomScale)
                surface.renderedRect = buffered; surface.renderedScale = renderZoomScale
            }
            surface.host.view.bounds = CGRect(x: 0, y: 0, width: documentSize.width * renderZoomScale, height: documentSize.height * renderZoomScale)
            surface.host.view.transform = CGAffineTransform(scaleX: layout.scale / renderZoomScale, y: layout.scale / renderZoomScale)
            let sourceOrigin = layout.visibleRect(for: part).origin
            surface.host.view.center = CGPoint(x: (documentSize.width / 2 - sourceOrigin.x) * layout.scale, y: (documentSize.height / 2 - sourceOrigin.y) * layout.scale)
        }
        let offset = scrollView.contentOffset, insets = layout.insets
        frozenRowLine.isHidden = insets.height == 0
        frozenColumnLine.isHidden = insets.width == 0
        frozenRowLine.frame = CGRect(x: offset.x, y: offset.y + insets.height - 0.5, width: scrollView.bounds.width, height: 1)
        frozenColumnLine.frame = CGRect(x: offset.x + insets.width - 0.5, y: offset.y, width: 1, height: scrollView.bounds.height)
        scrollView.bringSubviewToFront(frozenRowLine)
        scrollView.bringSubviewToFront(frozenColumnLine)
    }

    private func resizeHostedContent() {
        // Draw text at its final point size, then map the hosted view back to
        // document coordinates. UIKit's zoom target and offsets stay unchanged.
        // The larger fonts are rasterized at the screen's native resolution.
        host.view.bounds = CGRect(
            x: 0, y: 0,
            width: documentSize.width * renderZoomScale,
            height: documentSize.height * renderZoomScale
        )
        host.view.transform = CGAffineTransform(scaleX: 1 / renderZoomScale, y: 1 / renderZoomScale)
        host.view.center = CGPoint(x: documentSize.width / 2, y: documentSize.height / 2)
    }
}
