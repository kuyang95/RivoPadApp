#if DEBUG
import XCTest
import WebKit
import SwiftUI
@testable import shortcuts_example

@MainActor
final class AccessibleGooglePageTests: XCTestCase {
    private func page(_ html: String, url: String) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(
            source: AccessibleGooglePage.bootstrap(enabled: true), injectionTime: .atDocumentStart,
            forMainFrameOnly: false, in: .world(name: "GoogleSimpleTests")))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: configuration)
        web.loadHTMLString(html, baseURL: URL(string: url))
        try await wait(web, "document.readyState === 'complete'")
        return web
    }
    private func wait(_ web: WKWebView, _ condition: String) async throws {
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript(condition)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Google simplification condition timed out: \(condition)")
    }
    func testHomeShowsOnlySearchAndFavorites() async throws {
        let web = try await page(Self.home, url: "https://www.google.com/")
        try await wait(web, "document.documentElement.getAttribute('data-rivo-google-simple') === 'home'")
        let valid = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('chrome')).display === 'none' && document.querySelectorAll('#rivo-google-search nav a').length === 4 && document.querySelector('#rivo-google-search form').action === 'https://www.google.com/search'")
        XCTAssertEqual(valid as? Bool, true)
    }
    func testResultsKeepLiveAIAndFiveSitesAndRestore() async throws {
        let web = try await page(Self.results, url: "https://www.google.com/search?q=hello")
        try await wait(web, "document.querySelectorAll('#rivo-google-results li').length === 5")
        let valid = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('ai')).display !== 'none' && getComputedStyle(document.getElementById('tads')).display === 'none' && !document.querySelector('#rivo-google-results a[href*=ad]')")
        XCTAssertEqual(valid as? Bool, true)
        _ = try await web.evaluateJavaScript("document.getElementById('expand').click(); document.querySelector('#rivo-google-search input').value='edited query'")
        try await wait(web, "document.getElementById('ai').textContent.includes('추가 요약')")
        _ = try await web.evaluateJavaScript("window.__rivoGoogleSimple.set({enabled:false})", in: nil, contentWorld: .world(name: "GoogleSimpleTests"))
        let restored = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('chrome')).display !== 'none' && !document.getElementById('rivo-google-results')")
        XCTAssertEqual(restored as? Bool, true)
    }
    func testVerificationAndOtherHostsAreNeverHidden() async throws {
        for url in ["https://www.google.com/sorry/index", "https://www.google.com.evil.example/search?q=test"] {
            let web = try await page(Self.results, url: url)
            let untouched = try await web.evaluateJavaScript("!document.documentElement.hasAttribute('data-rivo-google-simple')")
            XCTAssertEqual(untouched as? Bool, true)
        }
        let web = try await page(Self.results + "<div role='dialog' aria-modal='true'>동의</div>", url: "https://www.google.com/search?q=test")
        let untouched = try await web.evaluateJavaScript("!document.documentElement.hasAttribute('data-rivo-google-simple')")
        XCTAssertEqual(untouched as? Bool, true)
    }
    func testBasicGoogleMarkupKeepsAIAndRedirectedSiteLinks() async throws {
        let html = Self.basic
        let web = try await page(html, url: "https://www.google.com/search?q=test")
        try await wait(web, "document.querySelectorAll('#rivo-google-results li').length === 5 && !!document.querySelector('[data-rivo-google-ai]')")
        let safeLink = try await web.evaluateJavaScript("document.querySelector('#rivo-google-results a').href")
        XCTAssertEqual(safeLink as? String, "https://www.google.com/url?q=CAESopaqueSignedToken&sa=U")
        let host = try await web.evaluateJavaScript("document.querySelector('#rivo-google-results small').textContent")
        XCTAssertEqual(host as? String, "site1.example")
    }
    func testDynamicAIAndResultsAreReflected() async throws {
        let web = try await page(Self.results.replacingOccurrences(of: "AI 개요", with: "기타"), url: "https://www.google.com/search?q=test")
        try await wait(web, "document.querySelectorAll('#rivo-google-results li').length === 5")
        _ = try await web.evaluateJavaScript("document.querySelector('#ai h2').textContent='AI 개요'; document.querySelector('#rso h3').textContent='바뀐 제목'")
        try await wait(web, "document.getElementById('ai').hasAttribute('data-rivo-google-ai') && document.querySelector('#rivo-google-results strong').textContent === '바뀐 제목'")
    }
    func testGoogleLivePreview() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RIVO_CAPTURE_GOOGLE_SIMPLE"] == "1", "Opt-in live Google capture")
        let browser = AccessibleWebBrowserModel()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: AccessibleWebBrowserView(browser: browser))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { browser.shutdown(); window.isHidden = true; window.rootViewController = nil }
        browser.navigate("https://www.google.com")
        try await waitLive(browser.webView, "document.documentElement.getAttribute('data-rivo-google-simple')==='home'")
        try await Task.sleep(for: .milliseconds(500))
        capture(host, "google-simple-home-ipad")
        _ = try await browser.webView.evaluateJavaScript("document.querySelector('#rivo-google-search input').value='무지개는 왜 생기나요'; document.querySelector('#rivo-google-search form').requestSubmit()")
        try await Task.sleep(for: .seconds(3))
        let diagnostic = try await browser.webView.evaluateJavaScript("""
        JSON.stringify({url:location.href, ids:Array.from(document.querySelectorAll('[id]')).map(e=>e.id).slice(0,80), aiHTML:document.getElementById('st-card')?.parentElement.outerHTML.slice(0,18000), headings:Array.from(document.querySelectorAll('h1,h2,h3,[role=heading]')).slice(0,20).map(e=>({html:e.outerHTML.slice(0,600),parent:e.parentElement.outerHTML.slice(0,2200)})), aiTitles:Array.from(document.querySelectorAll('div,span')).filter(e=>e.childElementCount===0&&e.textContent.trim()==='AI 개요').map(e=>Array.from((function*(n){for(let i=0;n&&i<5;i++,n=n.parentElement)yield n;})(e)).map(n=>n.outerHTML.slice(0,14000))), links:Array.from(document.querySelectorAll('a[href]')).slice(0,60).map(e=>({href:e.getAttribute('href'),text:e.textContent.slice(0,180),html:e.outerHTML.slice(0,1200),parents:Array.from((function*(n){for(let i=0;n&&i<4;i++,n=n.parentElement)yield n;})(e)).map(n=>({tag:n.tagName,cls:n.className,id:n.id,role:n.getAttribute('role')}))}))})
        """) as? String ?? ""
        let detail = XCTAttachment(string: diagnostic); detail.name = "google-dom-diagnostic"; detail.lifetime = .keepAlways; add(detail)
        try await waitLive(browser.webView, "document.querySelectorAll('#rivo-google-results li').length>0")
        try await Task.sleep(for: .seconds(3))
        capture(host, "google-simple-results-ipad")
        try await geometry(browser.webView, name: "before-zoom")
        let normalWidth = try await browser.webView.evaluateJavaScript("innerWidth") as? Double ?? 0
        browser.setZoom(175); browser.palette = .dark; browser.applyAppearance()
        try await Task.sleep(for: .seconds(1))
        capture(host, "google-simple-results-ink-175-ipad")
        try await geometry(browser.webView, name: "after-zoom")
        let enlargedWidth = try await browser.webView.evaluateJavaScript("innerWidth") as? Double ?? 0
        XCTAssertLessThan(enlargedWidth, normalWidth * 0.9, "Live Google page zoom must reflow rather than auto-fit back to its original size")
        let fits = try await browser.webView.evaluateJavaScript("['#rivo-google-search input','#rivo-google-search button','#rivo-google-results'].every(selector=>{const r=document.querySelector(selector).getBoundingClientRect();return r.left>=0 && r.right<=innerWidth+1})") as? Bool
        XCTAssertEqual(fits, true, "Simplified Google must keep its search controls inside the enlarged viewport")
    }
    private func geometry(_ web: WKWebView, name: String) async throws {
        let value = try await web.evaluateJavaScript("JSON.stringify({innerWidth:innerWidth,scrollWidth:document.documentElement.scrollWidth,bodyWidth:document.body.clientWidth,scale:visualViewport.scale,screen:screen.width,viewport:document.querySelector('meta[name=viewport]')?.content})") as? String ?? ""
        let attachment = XCTAttachment(string: value + " pageZoom=\(web.pageZoom) scrollZoom=\(web.scrollView.zoomScale)")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func waitLive(_ web: WKWebView, _ condition: String) async throws {
        for _ in 0..<600 {
            if (try? await web.evaluateJavaScript(condition)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Live Google did not show the expected simplified view: \(condition)")
    }
    private func capture(_ host: UIViewController, _ name: String) {
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
    private static let basic = #"""
    <!doctype html><html><head><meta name="viewport" content="width=device-width"></head><body><header id="chrome"><button>프로필</button><button>더보기</button></header><div id="main"><div id="st-card" style="display:none">모든 언어</div><div id="ai" class="Gx5Zad"><div><span>AI 개요</span></div><p>구글이 제공한 실제 요약입니다.</p><a href="https://source.example">요약 출처</a><button id="expand" onclick="this.parentElement.appendChild(Object.assign(document.createElement('p'),{textContent:'추가 요약'}))">더보기</button></div><div id="tads"><a href="https://ad.example"><h3>광고</h3></a></div><div id="basic-results"><article><a href="/url?q=CAESopaqueSignedToken&amp;sa=U"><div><h3>사이트 1</h3></div><div class="XR4uSe">site1.example › article</div></a><button>검색결과에 관한 정보</button></article><article><a href="https://site2.example/article"><h3>사이트 2</h3></a><button>검색결과에 관한 정보</button></article><article><a href="https://site3.example/article"><h3>사이트 3</h3></a><button>검색결과에 관한 정보</button></article><article><a href="https://site4.example/article"><h3>사이트 4</h3></a><button>검색결과에 관한 정보</button></article><article><a href="https://site5.example/article"><h3>사이트 5</h3></a><button>검색결과에 관한 정보</button></article><article><a href="https://site6.example/article"><h3>사이트 6</h3></a><button>검색결과에 관한 정보</button></article><article><a href="https://site7.example/article"><h3>사이트 7</h3></a><button>검색결과에 관한 정보</button></article></div></div></body></html>
    """#
    private static let home = #"""
    <!doctype html><html><head><meta name="viewport" content="width=device-width"></head><body><header id="chrome"><img alt="Google"><button>프로필</button><button>더보기</button></header><form action="/search"><input name="q"></form><footer>정보</footer></body></html>
    """#
    private static let results = #"""
    <!doctype html><html><head><meta name="viewport" content="width=device-width"></head><body><header id="chrome"><button>프로필</button><button>더보기</button></header><div id="rcnt"><section id="ai"><h2>AI 개요</h2><p>구글이 제공한 실제 요약입니다.</p><a href="https://source.example">요약 출처</a><button id="expand" onclick="this.parentElement.appendChild(Object.assign(document.createElement('p'),{textContent:'추가 요약'}))">더보기</button></section><div id="tads"><a href="https://ad.example"><h3>광고</h3></a></div><div id="rso"><article><a href="https://site1.example/article"><h3>사이트 1</h3></a><button>검색결과에 관한 정보</button></article><article><a href="https://site2.example/article"><h3>사이트 2</h3></a><button>검색결과에 관한 정보</button></article><article><a href="https://site3.example/article"><h3>사이트 3</h3></a><button>검색결과에 관한 정보</button></article><article><a href="https://site4.example/article"><h3>사이트 4</h3></a><button>검색결과에 관한 정보</button></article><article><a href="https://site5.example/article"><h3>사이트 5</h3></a><button>검색결과에 관한 정보</button></article><article><a href="https://site6.example/article"><h3>사이트 6</h3></a><button>검색결과에 관한 정보</button></article><article><a href="https://site7.example/article"><h3>사이트 7</h3></a><button>검색결과에 관한 정보</button></article></div></div></body></html>
    """#
}
#endif
