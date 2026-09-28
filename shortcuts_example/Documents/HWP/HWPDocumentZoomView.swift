import SwiftUI
import UIKit

struct HWPDocumentZoomView<Content: View>: UIViewControllerRepresentable {
    let contentSize: CGSize
    let scrollRequest: HWPDocumentScrollRequest?
    let zoomRequest: HWPDocumentZoomRequest?
    let onViewport: (CGRect) -> Void
    let onZoom: (CGFloat) -> Void
    @ViewBuilder let content: (CGRect, CGFloat) -> Content

    func makeUIViewController(context: Context) -> HWPDocumentZoomController {
        HWPDocumentZoomController(contentSize: contentSize)
    }

    func updateUIViewController(_ controller: HWPDocumentZoomController, context: Context) {
        controller.onViewport = onViewport
        controller.onZoom = onZoom
        controller.update(contentSize: contentSize, scrollRequest: scrollRequest,
            zoomRequest: zoomRequest) { rect, scale in
                AnyView(content(rect, scale).environment(\.self, context.environment))
            }
    }
}

/// Keeps the same zoom target and input view mounted throughout a pinch.
@MainActor
final class HWPDocumentZoomController: UIViewController, UIScrollViewDelegate {
    let scrollView = UIScrollView()
    private let paperView = UIView()
    private let host = UIHostingController(rootView: AnyView(Color.clear))
    private var documentSize: CGSize
    private var makeContent: (CGRect, CGFloat) -> AnyView = { _, _ in AnyView(Color.clear) }
    private var renderedRect = CGRect.null
    private var renderScale: CGFloat = 1
    private var lastScrollID: UUID?
    private var lastZoomID: UUID?
    private var pendingScroll: HWPDocumentScrollRequest?
    private var pendingZoom: HWPDocumentZoomRequest?
    private var fittingWidth = true
    private var previousBounds = CGRect.zero
    private var updating = false
    private var reportRevision = 0
    private var shouldRevealCaret = false
    var onViewport: ((CGRect) -> Void)?
    var onZoom: ((CGFloat) -> Void)?

    init(contentSize: CGSize) {
        documentSize = contentSize
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scrollView.backgroundColor = .clear
        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.25
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.keyboardDismissMode = .none
        scrollView.accessibilityIdentifier = "hwp-document-scroll"
        view.addSubview(scrollView)
        scrollView.addSubview(paperView)
        addChild(host)
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        paperView.addSubview(host.view)
        host.didMove(toParent: self)
        resizeDocument()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let oldVisible = visibleRect
        let changed = previousBounds.size != view.bounds.size
        updating = true
        scrollView.frame = view.bounds
        if changed, view.bounds.width > 0 {
            if fittingWidth { setScale(fitScale) }
            if previousBounds.width > 0 {
                // Preserve the leading visible paper position when a keyboard
                // changes height, and the center when the width changes.
                let widthChanged = previousBounds.width != view.bounds.width
                setOffset(CGPoint(
                    x: widthChanged ? oldVisible.midX * scrollView.zoomScale - view.bounds.width / 2
                        : scrollView.contentOffset.x,
                    y: oldVisible.minY * scrollView.zoomScale))
            }
        }
        previousBounds = view.bounds
        centerPaper()
        applyRequests()
        updating = false
        refresh(force: changed)
        reportViewport()
    }

    func update(contentSize: CGSize, scrollRequest: HWPDocumentScrollRequest?,
                zoomRequest: HWPDocumentZoomRequest?,
                content: @escaping (CGRect, CGFloat) -> AnyView) {
        loadViewIfNeeded()
        updating = true
        makeContent = content
        if documentSize != contentSize {
            documentSize = contentSize
            resizeDocument()
        }
        pendingScroll = scrollRequest
        pendingZoom = zoomRequest
        applyRequests()
        updating = false
        refresh(force: true)
        reportViewport()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { paperView }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !updating else { return }
        refresh()
        reportViewport()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard !updating else { return }
        centerPaper()
        refresh()
        reportViewport()
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        if !updating { fittingWidth = false }
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        guard !updating else { return }
        renderScale = max(1, scale)
        refresh(force: true)
        revealCaret()
        reportViewport()
    }

    private var fitScale: CGFloat {
        min(1, max(scrollView.minimumZoomScale, scrollView.bounds.width / max(1, documentSize.width)))
    }

    private var visibleRect: CGRect {
        scrollView.convert(scrollView.bounds, to: paperView)
    }

    private func applyRequests() {
        guard scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
        if let request = pendingZoom, request.id != lastZoomID {
            lastZoomID = request.id
            shouldRevealCaret = true
            let visible = visibleRect
            fittingWidth = request.scale == nil
            setScale(request.scale ?? fitScale)
            centerPaper()
            setOffset(CGPoint(x: visible.midX * scrollView.zoomScale - scrollView.bounds.width / 2,
                y: visible.midY * scrollView.zoomScale - scrollView.bounds.height / 2))
        }
        if let request = pendingScroll, request.id != lastScrollID {
            lastScrollID = request.id
            let scale = scrollView.zoomScale
            setOffset(CGPoint(
                x: request.rect.midX * scale - scrollView.bounds.width / 2,
                y: request.alignsPageTop ? max(0, request.rect.minY - 20) * scale
                    : request.rect.midY * scale - scrollView.bounds.height / 2))
        }
    }

    private func setScale(_ scale: CGFloat) {
        guard scale.isFinite else { return }
        scrollView.setZoomScale(min(max(scale, scrollView.minimumZoomScale), scrollView.maximumZoomScale), animated: false)
        renderScale = max(1, scrollView.zoomScale)
    }

    private func setOffset(_ point: CGPoint) {
        let inset = scrollView.contentInset
        scrollView.setContentOffset(CGPoint(
            x: min(max(-inset.left, point.x), max(-inset.left, scrollView.contentSize.width - scrollView.bounds.width + inset.right)),
            y: min(max(0, point.y), max(0, scrollView.contentSize.height - scrollView.bounds.height))), animated: false)
    }

    private func centerPaper() {
        let x = max(0, (scrollView.bounds.width - documentSize.width * scrollView.zoomScale) / 2)
        let inset = UIEdgeInsets(top: 0, left: x, bottom: 0, right: x)
        if scrollView.contentInset != inset { scrollView.contentInset = inset }
    }

    private func resizeDocument() {
        paperView.bounds = CGRect(origin: .zero, size: documentSize)
        paperView.center = CGPoint(x: documentSize.width * scrollView.zoomScale / 2,
            y: documentSize.height * scrollView.zoomScale / 2)
        scrollView.contentSize = CGSize(width: documentSize.width * scrollView.zoomScale,
            height: documentSize.height * scrollView.zoomScale)
        centerPaper()
        renderedRect = .null
    }

    private func refresh(force: Bool = false) {
        guard !updating, scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
        let visible = visibleRect.intersection(CGRect(origin: .zero, size: documentSize))
        guard !visible.isNull, force || !renderedRect.contains(visible) else { return }
        renderedRect = visible.insetBy(dx: 0, dy: -max(visible.height, 200))
        UIView.performWithoutAnimation {
            host.rootView = makeContent(renderedRect, renderScale)
            host.view.bounds = CGRect(x: 0, y: 0,
                width: documentSize.width * renderScale, height: documentSize.height * renderScale)
            host.view.transform = CGAffineTransform(scaleX: 1 / renderScale, y: 1 / renderScale)
            host.view.center = CGPoint(x: documentSize.width / 2, y: documentSize.height / 2)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }
        if shouldRevealCaret {
            shouldRevealCaret = false
            revealCaret()
        }
    }

    private func revealCaret() {
        func focusedInput(in view: UIView) -> UITextView? {
            if let input = view as? UITextView, input.isFirstResponder { return input }
            for child in view.subviews {
                if let input = focusedInput(in: child) { return input }
            }
            return nil
        }
        guard let input = focusedInput(in: host.view), let selection = input.selectedTextRange else { return }
        let caret = input.caretRect(for: selection.end)
        scrollView.scrollRectToVisible(input.convert(caret, to: scrollView)
            .insetBy(dx: -16, dy: -24), animated: false)
    }

    private func reportViewport() {
        guard scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
        let rect = visibleRect
        let scale = scrollView.zoomScale
        let reportZoom = !scrollView.isZooming
        reportRevision += 1
        let revision = reportRevision
        // Delegate calls can occur inside a SwiftUI update. Publish afterwards,
        // discarding old scroll reports when several updates arrive together.
        Task { @MainActor [weak self] in
            guard let self, self.reportRevision == revision else { return }
            self.onViewport?(rect)
            if reportZoom { self.onZoom?(scale) }
        }
    }
}
