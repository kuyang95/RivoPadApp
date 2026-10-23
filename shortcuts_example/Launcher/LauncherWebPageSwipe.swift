import UIKit
import WebKit

/// Native recognition also receives touches inside cross-origin video/web frames.
@MainActor
final class LauncherWebPageSwipe: NSObject, UIGestureRecognizerDelegate {
    private weak var webView: WKWebView?
    private let turn: (Int) -> Void
    private let drag: (CGFloat) -> Void
    private let end: (Bool) -> Bool
    private var dragging = false
    private var generation = 0
    private(set) var eligible = false
    let pan = UIPanGestureRecognizer()

    init(webView: WKWebView, drag: @escaping (CGFloat) -> Void = { _ in },
         end: @escaping (Bool) -> Bool = { _ in false }, turn: @escaping (Int) -> Void) {
        self.webView = webView
        self.turn = turn; self.drag = drag; self.end = end
        super.init()
        pan.name = "rivo-launcher-page-swipe"
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        pan.delegate = self
        pan.addTarget(self, action: #selector(handlePan))
        webView.addGestureRecognizer(pan)
        webView.scrollView.panGestureRecognizer.require(toFail: pan)
    }

    func prepare(at point: CGPoint) {
        guard let webView else { return }
        generation += 1
        let token = generation
        eligible = false
        let x = min(1, max(0, point.x / max(1, webView.bounds.width)))
        let y = min(1, max(0, point.y / max(1, webView.bounds.height)))
        // Only geometric eligibility is returned, never form values or frame contents.
        webView.evaluateJavaScript("window.__rivoLauncherCanPageAt?.(\(x),\(y))===true") { [weak self] result, _ in
            guard let self, self.generation == token else { return }
            self.eligible = result as? Bool == true
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let webView else { return false }
        prepare(at: touch.location(in: webView))
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let velocity = pan.velocity(in: webView)
        return eligible && abs(velocity.x) > abs(velocity.y) * 1.5
    }

    func update(translation: CGPoint) {
        guard eligible else { return }
        dragging = true
        drag(translation.x)
    }

    func finish(translation: CGPoint, cancelled: Bool = false) {
        defer { generation += 1; eligible = false; dragging = false }
        if dragging, end(cancelled || !eligible) { return }
        guard let webView, eligible, !cancelled,
              abs(translation.x) > abs(translation.y) * 1.5,
              abs(translation.x) >= max(64, webView.bounds.width * 0.15) else { return }
        turn(translation.x < 0 ? 1 : -1)
    }

    @objc private func handlePan() {
        // A moving WebView is not a stable coordinate space for a drag.
        let translation = pan.translation(in: webView?.window)
        if pan.state == .began || pan.state == .changed { update(translation: translation) }
        else if pan.state == .ended { finish(translation: translation) }
        else if pan.state == .cancelled || pan.state == .failed { finish(translation: translation, cancelled: true) }
    }

}
