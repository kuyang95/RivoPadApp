import SwiftUI
import WebKit
import XCTest
@testable import shortcuts_example

/// A real ShoppingSearchView hosted in a test-only window; no user preferences or documents are changed.
@MainActor
final class ShoppingSearchIntegrationTests: XCTestCase {
    private var window: UIWindow?
    private weak var previousWindow: UIWindow?

    override func tearDown() {
        window?.isHidden = true; window?.rootViewController = nil; window = nil
        previousWindow?.makeKeyAndVisible()
    }

    func testLocalScreenBridgeAndAccessibleControls() async throws {
        let web = try await show()
        try await wait(web, "typeof window.RivoShopping==='object'")
        let mode = try await web.evaluateJavaScript("window.RivoShopping.snapshot().mode") as? String
        XCTAssertEqual(mode, "retailer-direct-v1")
        let obsolete = try await web.evaluateJavaScript("/다나와|에누리/.test(document.getElementById('source-options').textContent)") as? Bool
        XCTAssertEqual(obsolete, false)
        for raw in ["https://www.enuri.com/detail.jsp?modelno=100786235", "https://search.danawa.com/", "file:///etc/passwd", "https://www.lotteon.com/login"] {
            XCTAssertFalse(ShoppingSource.safeOpen(URL(string: raw)!))
        }
        XCTAssertTrue(ShoppingSource.safeOpen(URL(string: "https://www.lotteon.com/p/product/LO2727839278")!))
        XCTAssertTrue(ShoppingSource.safeOpen(URL(string: "https://www.hmall.com/md/pda/itemPtc?slitmCd=2254581570")!))
        XCTAssertEqual(ShoppingSource.auction.upgradeSearch(URL(string: "http://m.auction.co.kr/n/search?keyword=test")!)?.absoluteString, "https://m.auction.co.kr/n/search?keyword=test")
        XCTAssertNil(ShoppingSource.auction.upgradeSearch(URL(string: "http://evil.example/n/search")!))
        _ = try await web.evaluateJavaScript("document.getElementById('theme').click();document.getElementById('text-size').click();document.getElementById('text-size').click();true")
        let overflow = try await web.evaluateJavaScript("document.documentElement.scrollWidth>innerWidth") as? Bool
        XCTAssertEqual(overflow, false)
        try await capture(web, name: "ipad-direct-home-large-text.png")
    }

    func testDirectRetailerSearchBudgetAndComparison() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RIVO_SHOPPING_LIVE_TEST"] == "1", "Explicit live retailer check")
        let web = try await show()
        try await wait(web, "typeof window.RivoShopping==='object'")
        _ = try await web.evaluateJavaScript("document.querySelector('input[value=ssg]').checked=true;document.getElementById('query').value='무선 헤드폰';document.getElementById('search-form').requestSubmit();true")
        try await wait(web, "window.RivoShopping.snapshot().count>1", timeout: 50)
        try await wait(web, "!window.RivoShopping.snapshot().busy", timeout: 185)
        let rawValue = try await web.evaluateJavaScript("JSON.stringify(window.RivoShopping.snapshot())") as? String
        let raw = try XCTUnwrap(rawValue)
        try Data(raw.utf8).write(to: output().appendingPathComponent("ipad-direct-search.json"))
        let value = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        XCTAssertEqual(value["mode"] as? String, "retailer-direct-v1")
        let sources = try XCTUnwrap(value["sources"] as? [String: [String: Any]])
        XCTAssertNil(sources["danawa"]); XCTAssertNil(sources["enuri"])
        for source in ["lotteon", "hmall", "eleven", "gsshop", "ohou", "hns"] {
            XCTAssertEqual(sources[source]?["state"] as? String, "ready", "Retailer unavailable: \(source)")
            XCTAssertGreaterThan(sources[source]?["count"] as? Int ?? 0, 0)
            let priced = try await web.evaluateJavaScript("window.RivoShopping.snapshot().products.some(p=>p.source==='\(source)'&&p.price>0)") as? Bool
            XCTAssertEqual(priced, true)
        }
        let direct = try await web.evaluateJavaScript("window.RivoShopping.snapshot().products.every(p=>['lotteon','hmall','eleven','gsshop','cj','ohou','himart','hns','auction','gmarket','ssg'].includes(p.source)&&!p.url.includes('danawa')&&!p.url.includes('enuri'))") as? Bool
        XCTAssertEqual(direct, true)
        _ = try await web.evaluateJavaScript("document.getElementById('results-section').scrollIntoView({block:'start'});true")
        try await capture(web, name: "ipad-direct-products.png")
        _ = try await web.evaluateJavaScript("document.getElementById('max').value='500000';document.getElementById('max').dispatchEvent(new Event('input',{bubbles:true}));true")
        for source in ["lotteon", "hmall"] {
            let added = try await web.evaluateJavaScript("""
                (() => {
                    const item = window.RivoShopping.snapshot().products.find(p =>
                        p.source === '\(source)' && p.availability !== 'out' && p.price !== null && p.price <= 500000);
                    if (!item) return false;
                    const within = document.getElementById('within');
                    within.value = item.title;
                    within.dispatchEvent(new Event('input'));
                    const card = [...document.querySelectorAll('.product-card')].find(card => card.dataset.key === item.key);
                    if (!card) return false;
                    card.querySelector('.card-compare').click();
                    return true;
                })()
                """) as? Bool
            XCTAssertEqual(added, true)
        }
        _ = try await web.evaluateJavaScript("document.getElementById('show-compare').click();true")
        let compared = try await web.evaluateJavaScript("document.querySelectorAll('#compare-content .compare-item').length") as? Int
        XCTAssertEqual(compared, 2)
        try await capture(web, name: "ipad-direct-comparison.png")
        _ = try await web.evaluateJavaScript("document.getElementById('close-compare').click();window.RivoShopping.environment({fontScale:2.5,voice:true});true")
        let overflow = try await web.evaluateJavaScript("document.documentElement.scrollWidth>innerWidth") as? Bool
        XCTAssertEqual(overflow, false)
        let accessible = try await web.evaluateJavaScript("Array.from(document.querySelectorAll('button')).filter(n=>n.getClientRects().length).every(n=>(n.getAttribute('aria-label')||n.textContent.trim())&&n.getBoundingClientRect().height>=48)") as? Bool
        XCTAssertEqual(accessible, true)
        try await capture(web, name: "ipad-direct-large-text.png")
    }

    private func output() throws -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("shopping-validation", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func show() async throws -> WKWebView {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: ShoppingSearchView().environment(\.colorScheme, .dark))
        self.window = window; window.makeKeyAndVisible()
        func find(_ view: UIView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        for _ in 0..<60 {
            if let web = window.rootViewController.flatMap({ find($0.view) }) { return web }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NSError(domain: "ShoppingTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Shopping view was not created"])
    }
    private func wait(_ web: WKWebView, _ expression: String, timeout: TimeInterval = 15) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? await web.evaluateJavaScript(expression)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTFail("Shopping condition timed out: \(expression)")
        throw NSError(domain: "ShoppingTest", code: 2)
    }
    private func capture(_ web: WKWebView, name: String) async throws {
        try await Task.sleep(for: .milliseconds(500))
        let config = WKSnapshotConfiguration(); config.afterScreenUpdates = true
        let image = try await web.takeSnapshot(configuration: config)
        if let data = image.pngData() { try data.write(to: output().appendingPathComponent(name)) }
    }
}
