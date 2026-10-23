#if DEBUG
import XCTest
import WebKit
import SwiftUI
@testable import shortcuts_example

@MainActor
final class AccessibleWebBrowserTests: XCTestCase {
    func testAddressesAndSearchTerms() throws {
        XCTAssertEqual(AccessibleWebAddress.resolve("  naver.com  ")?.absoluteString, "https://naver.com")
        XCTAssertEqual(AccessibleWebAddress.resolve("example.com:8443/shop")?.host, "example.com")
        XCTAssertEqual(AccessibleWebAddress.resolve("https://example.com/cart?q=1")?.path, "/cart")
        let search = try XCTUnwrap(AccessibleWebAddress.resolve("빨간 신발 & 가방"))
        XCTAssertEqual(search.host, "www.google.com")
        XCTAssertEqual(URLComponents(url: search, resolvingAgainstBaseURL: false)?.queryItems?.first?.name, "q")
        XCTAssertEqual(URLComponents(url: search, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "빨간 신발 & 가방")
        for unsafe in ["javascript:alert(1)", "data:text/html,hello", "file:///etc/hosts", "intent://shop", "tel:123", "   "] {
            XCTAssertNil(AccessibleWebAddress.resolve(unsafe), unsafe)
        }
    }

    func testThemePreservesMediaAndRestoresOriginalWithoutLosingFormValues() async throws {
        let web = try await fixture()
        let result = try await values(web)
        XCTAssertEqual(result["body"], "rgb(32, 33, 36)")
        XCTAssertEqual(result["text"], "rgb(241, 243, 244)")
        XCTAssertEqual(result["button"], "rgb(41, 42, 45)")
        XCTAssertEqual(result["link"], "rgb(241, 243, 244)")
        XCTAssertEqual(result["svg"], "rgb(255, 0, 0)")
        XCTAssertEqual(result["swatch"], "rgb(0, 128, 0)")
        XCTAssertTrue(result["photo"]?.contains("data:image") == true)
        XCTAssertTrue(result["backgroundPhoto"]?.contains("data:image") == true)
        XCTAssertEqual(result["gradient"], "none")
        XCTAssertEqual(result["mask"], "rgb(241, 243, 244)")
        XCTAssertEqual(result["indicator"], "rgb(187, 198, 215)")

        _ = try await web.evaluateJavaScript("document.querySelector('input').value = '선택한 상품';")
        try await setAppearance(web, enabled: false)
        let original = try await values(web)
        XCTAssertEqual(original["body"], "rgb(255, 192, 203)")
        XCTAssertEqual(original["button"], "rgb(255, 0, 0)")
        XCTAssertEqual(original["text"], "rgb(0, 0, 255)")
        let inputValue = try await web.evaluateJavaScript("document.querySelector('input').value") as? String
        XCTAssertEqual(inputValue, "선택한 상품")
    }

    func testPhotoOverlaysAndLinkLayoutMatchOriginal() async throws {
        let web = try await fixture()
        let script = """
        JSON.stringify({
          hidden:getComputedStyle(document.getElementById('hiddenLabel')).webkitTextFillColor,
                before:getComputedStyle(document.getElementById('card'),'::before').backgroundColor,
          after:getComputedStyle(document.getElementById('card'),'::after').backgroundImage,
          overlay:getComputedStyle(document.getElementById('overlay')).backgroundColor,
          border:getComputedStyle(document.getElementById('card')).borderTopColor,
          link:getComputedStyle(document.getElementById('plainLink')).textDecorationLine,
          imageSet:getComputedStyle(document.getElementById('imageSet')).backgroundImage,
          stencil:getComputedStyle(document.getElementById('stencil')).backgroundImage,
          geometry:[...document.querySelectorAll('#text,#button,input,#photo,#backgroundPhoto,#gradient,svg,#swatch,#card,#card img,#plainLink')].map(e=>{
            const r=e.getBoundingClientRect();return [r.x,r.y,r.width,r.height];})
        })
        """
        let themed = try await web.evaluateJavaScript(script) as? String
        let overlay = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('card'),'::before').backgroundColor") as? String
        XCTAssertEqual(overlay, "rgba(0, 0, 0, 0.03)")
        let decoration = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('plainLink')).textDecorationLine") as? String
        XCTAssertEqual(decoration, "none")
        try await setAppearance(web, enabled: false)
        let original = try await web.evaluateJavaScript(script) as? String
        XCTAssertEqual(themed, original, "Photo overlays, image sources and layout must match the original")
    }

    func testOriginalColoursDetermineGraphicTreatment() async throws {
        let web = try await fixture()
        _ = try await web.evaluateJavaScript("""
            (() => {
              const png = (draw,width=32,height=32) => {
                const c=document.createElement('canvas');c.width=width;c.height=height;
                draw(c.getContext('2d'));return c.toDataURL();
              };
              const shape=(c,colour,x=0)=>{c.strokeStyle=colour;c.lineWidth=4;c.strokeRect(x+6,6,20,20);};
              const neutral=png(c=>shape(c,'#333333'));
              const coloured=png(c=>shape(c,'#e03020'));
              const opaque=png(c=>{c.fillStyle='#fff';c.fillRect(0,0,32,32);shape(c,'#333333');});
              const textured=png(c=>{for(let x=4;x<28;x++){c.fillStyle='rgb('+x*8+','+x*8+','+x*8+')';c.fillRect(x,4,1,24);}});
              const sheet=png(c=>{shape(c,'#333333');shape(c,'#e03020',32);},64,32);
              window.replacementGraphic=coloured;
              document.body.insertAdjacentHTML('beforeend', `
                <style>
                  .sample{display:inline-block;width:32px;height:32px}
                  #four::before{content:'';display:inline-block;width:32px;height:32px;background:url('${neutral}') no-repeat}
                  #five,#six{background-image:url('${sheet}');background-size:64px 32px;background-repeat:no-repeat}
                  #six{background-position:-32px 0px}
                </style>
                <button aria-label="임의 동작"><svg id="one" width="32" height="32" fill="none"><path id="oneStroke" stroke="#333333" d="M2 2L28 28"/></svg></button>
                <button><img id="two" class="sample" src="${neutral}"></button>
                <button><img id="three" class="sample" src="${coloured}"></button>
                <button id="four"></button>
                <button><span id="five" class="sample"><span style="position:absolute;width:1px;height:1px;overflow:hidden">임의 동작</span></span></button>
                <button><span id="six" class="sample"></span></button>
                <button><img id="seven" class="sample" src="${opaque}"></button>
                <button><img id="eight" class="sample" src="${textured}"></button>
                <a href="#"><svg id="nine" class="logo" width="32" height="32"><path id="nineStroke" stroke="#333333" d="M2 2L28 28" fill="none"/></svg></a>
                <button><svg id="ten" width="32" height="32" fill="none"><path id="tenStroke" stroke="#e03020" d="M2 2L28 28"/></svg></button>
                <button><svg id="eleven" width="32" height="32"><rect width="32" height="32" fill="#333333"/></svg></button>
              `);
              return true;
            })()
            """)
        try await wait(web, for: "document.getElementById('two').getAttribute('data-rivo-web-ui-icon') === 'image' && document.getElementById('five').hasAttribute('data-rivo-web-ui-icon') && document.getElementById('four').hasAttribute('data-rivo-web-before-ui-icon')")
        let actual = try await web.evaluateJavaScript("""
            (() => {
              const style = (id,pseudo) => getComputedStyle(document.getElementById(id),pseudo);
              return JSON.stringify({
                stroke:style('oneStroke').stroke, hollow:style('one').fill,
                raster:style('two').filter !== 'none', coloured:style('three').filter,
                pseudo:style('four','::before').filter !== 'none',
                sprite:style('five').filter !== 'none', colouredCrop:style('six').filter,
                opaque:style('seven').filter, textured:style('eight').filter,
                logo:style('nineStroke').stroke, colourSVG:style('tenStroke').stroke,
                opaqueSVG:document.getElementById('eleven').hasAttribute('data-rivo-web-ui-icon')
              });
            })()
            """) as? String
        XCTAssertEqual(actual, #"{"stroke":"rgb(241, 243, 244)","hollow":"none","raster":true,"coloured":"none","pseudo":true,"sprite":true,"colouredCrop":"none","opaque":"none","textured":"none","logo":"rgb(51, 51, 51)","colourSVG":"rgb(224, 48, 32)","opaqueSVG":false}"#)
        try await setAppearance(web, enabled: true, palette: .light)
        try await wait(web, for: "getComputedStyle(document.getElementById('oneStroke')).stroke === 'rgb(40, 53, 70)'")
        _ = try await web.evaluateJavaScript("document.getElementById('two').src=window.replacementGraphic; true;")
        try await wait(web, for: "getComputedStyle(document.getElementById('two')).filter === 'none'")
        try await setAppearance(web, enabled: false)
        let original = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('oneStroke')).stroke") as? String
        XCTAssertEqual(original, "rgb(51, 51, 51)")
        let sprite = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('five')).filter") as? String
        XCTAssertEqual(sprite, "none")
    }

    func testDynamicContentAndPaletteChange() async throws {
        let web = try await fixture()
        _ = try await web.evaluateJavaScript("""
            const card = document.createElement('div');
            card.id = 'dynamic'; card.style.backgroundColor = 'orange'; card.textContent = '새 검색 결과';
            document.body.appendChild(card); true;
            """)
        try await wait(web, for: "document.getElementById('dynamic').hasAttribute('data-rivo-web-surface')")
        let dynamicColor = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('dynamic')).backgroundColor") as? String
        XCTAssertEqual(dynamicColor, "rgb(41, 42, 45)")
        try await setAppearance(web, enabled: true, palette: .light)
        let light = try await values(web)
        XCTAssertEqual(light["body"], "rgb(255, 255, 255)")
        try await setAppearance(web, enabled: true, palette: .dark)
        let contrast = try await values(web)
        XCTAssertEqual(contrast["text"], "rgb(241, 243, 244)")
        try await setAppearance(web, enabled: false)
        let originalColor = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('dynamic')).backgroundColor") as? String
        XCTAssertEqual(originalColor, "rgb(255, 165, 0)")
    }

    func testPageZoomPreservesFixedFieldsAndHostPreferences() async throws {
        let browser = AccessibleWebBrowserModel()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: AccessibleWebBrowserView(browser: browser))
        window.makeKeyAndVisible()
        defer { browser.shutdown(); window.isHidden = true; window.rootViewController = nil }
        let web = browser.webView
        let html = """
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{margin:0}header{height:48px;display:flex;align-items:center;justify-content:flex-end}
        button{font:14px/18px sans-serif;height:40px;box-sizing:border-box;margin:4px 16px;padding:10px 12px}
        textarea{font:16px/24px sans-serif;height:24px;padding:0;border:0;overflow:hidden;display:block}</style>
        <header><button id="login">로그인</button></header><textarea id="search">검색어 유지</textarea>
        """
        func load(_ host: String) async throws {
            web.stopLoading()
            web.loadHTMLString(html, baseURL: URL(string: "https://\(host)/page"))
            try await wait(web, for: "location.hostname==='\(host)' && document.readyState==='complete' && !!document.getElementById('search')")
            try await Task.sleep(for: .milliseconds(150))
        }
        try await load("zoom-one.test")
        browser.setZoom(100)
        try await Task.sleep(for: .milliseconds(100))
        let normalViewportResult = try await web.evaluateJavaScript("window.innerWidth")
        let normalViewport = try XCTUnwrap(normalViewportResult as? Double)
        browser.setZoom(170)
        try await Task.sleep(for: .milliseconds(100))
        let enlargedViewportResult = try await web.evaluateJavaScript("window.innerWidth")
        let enlargedViewport = try XCTUnwrap(enlargedViewportResult as? Double)
        XCTAssertLessThan(enlargedViewport, normalViewport * 0.9, "Page zoom must reflow the viewport, not merely update a stored value")
        XCTAssertEqual(web.pageZoom, 1.7, accuracy: 0.001)
        let fits = try await web.evaluateJavaScript("document.getElementById('search').scrollHeight<=document.getElementById('search').clientHeight+1 && document.getElementById('login').getBoundingClientRect().top>=0") as? Bool
        XCTAssertEqual(fits, true)
        browser.appearanceEnabled = false
        browser.applyAppearance()
        XCTAssertEqual(web.pageZoom, 1.7, accuracy: 0.001)
        let input = try await web.evaluateJavaScript("document.getElementById('search').value") as? String
        XCTAssertEqual(input, "검색어 유지")
        browser.setZoom(150)
        try await load("zoom-two.test")
        XCTAssertEqual(web.pageZoom, CGFloat(browser.defaultZoomPercent) / 100, accuracy: 0.001)
        try await load("zoom-one.test")
        XCTAssertEqual(browser.zoomPercent, 150)
        XCTAssertEqual(web.pageZoom, 1.5, accuracy: 0.001)
        browser.resetZoom()
        XCTAssertEqual(web.pageZoom, CGFloat(browser.defaultZoomPercent) / 100, accuracy: 0.001)
        browser.setZoom(100)
        XCTAssertEqual(web.pageZoom, 1, accuracy: 0.001)
    }

    func testGooglePageZoomPreview() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RIVO_CAPTURE_GOOGLE_ZOOM"] == "1", "Opt-in live-site capture")
        let browser = AccessibleWebBrowserModel()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: AccessibleWebBrowserView(browser: browser))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { browser.shutdown(); window.isHidden = true; window.rootViewController = nil }
        browser.navigate("https://www.google.com/search?q=알리바바+완+2.2")
        try await wait(browser.webView, for: "location.hostname.includes('google') && document.readyState==='complete' && !!document.querySelector('textarea,input[name=q]')", attempts: 600)
        browser.setZoom(170)
        try await Task.sleep(for: .seconds(2))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let folder = URL.documentsDirectory.appendingPathComponent("AccessibleWebPreview", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try image.pngData()?.write(to: folder.appendingPathComponent("google-pagezoom-ipad.png"))
        let attachment = XCTAttachment(image: image)
        attachment.name = "구글 페이지 확대 170% 실제 iPad"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNaverModePreview() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RIVO_CAPTURE_NAVER"] == "1", "Opt-in live-site capture")
        let browser = AccessibleWebBrowserModel()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: AccessibleWebBrowserView(browser: browser))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { browser.shutdown(); window.isHidden = true; window.rootViewController = nil }
        browser.navigate("https://www.naver.com")
        try await wait(browser.webView, for: "location.hostname.endsWith('naver.com') && document.readyState==='complete' && document.body.innerText.length>100", attempts: 600)
        try await Task.sleep(for: .seconds(2)) // Let live-site feeds and image requests settle before capture.
        for palette in [AccessibleWebPalette.light, .dark] {
            browser.palette = palette
            browser.applyAppearance()
            try await wait(browser.webView, for: "getComputedStyle(document.documentElement).filter==='\("none")'")
            _ = try await browser.webView.evaluateJavaScript("document.activeElement?.blur(); window.scrollTo(0,0); true;")
            try await Task.sleep(for: .milliseconds(500))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let folder = URL.documentsDirectory.appendingPathComponent("AccessibleWebPreview", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try image.pngData()?.write(to: folder.appendingPathComponent("naver-\(palette.rawValue)-ipad.png"))
            let attachment = XCTAttachment(image: image)
            attachment.name = "네이버 \(palette.title) 실제 iPad 화면"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testBrowserScreenAndPopupSession() async throws {
        let browser = AccessibleWebBrowserModel()
        browser.webView.stopLoading()
        browser.webView.loadHTMLString(Self.html, baseURL: URL(string: "https://fixture.invalid"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: AccessibleWebBrowserView(browser: browser))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            browser.shutdown()
            window.isHidden = true
            window.rootViewController = nil
        }
        let parent = browser.webView
        try await wait(parent, for: "document.readyState === 'complete' && !!document.getElementById('button')")
        try await Task.sleep(for: .milliseconds(500))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "접근성 웹 iPad 화면"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Permit the scripted test click; production still requires a user gesture.
        parent.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        _ = try await parent.evaluateJavaScript("window.open('about:blank', '_blank'); true;")
        for _ in 0..<40 {
            if browser.hasPopup { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(browser.hasPopup)
        XCTAssertFalse(browser.webView === parent)
        let hasOpener = try await browser.webView.evaluateJavaScript("window.opener !== null") as? Bool
        XCTAssertEqual(hasOpener, true)
        browser.appearanceEnabled = false
        browser.applyAppearance()
        browser.closePopup()
        XCTAssertTrue(browser.webView === parent)
        XCTAssertFalse(browser.hasPopup)
        try await wait(parent, for: "!document.documentElement.hasAttribute('data-rivo-web-enabled')")
    }

    private func setAppearance(_ web: WKWebView, enabled: Bool, palette: AccessibleWebPalette = .dark) async throws {
        _ = try await web.evaluateJavaScript(
            "window.__rivoAccessibleWeb.set(\(AccessibleWebAppearance.configuration(enabled: enabled, palette: palette)));",
            in: nil, contentWorld: .world(name: "AccessibleWebTests")
        )
    }

    private func fixture() async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(
            source: AccessibleWebAppearance.bootstrap(enabled: true, palette: .dark),
            injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .world(name: "AccessibleWebTests")
        ))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: configuration)
        web.loadHTMLString(Self.html, baseURL: URL(string: "https://fixture.invalid"))
        try await wait(web, for: "document.readyState === 'complete' && !!document.querySelector('[data-rivo-web-stylesheet]') && document.documentElement.hasAttribute('data-rivo-web-enabled')")
        return web
    }

    private func wait(_ web: WKWebView, for expression: String, attempts: Int = 100) async throws {
        for _ in 0..<attempts {
            if (try? await web.evaluateJavaScript(expression)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("WebKit fixture timed out: \(expression)")
    }

    private func values(_ web: WKWebView) async throws -> [String: String] {
        try await web.evaluateJavaScript("""
          (() => {
            const css = (id, property) => getComputedStyle(document.getElementById(id))[property];
            return {body:getComputedStyle(document.body).backgroundColor, text:css('text','color'),
              button:css('button','backgroundColor'),link:css('link','color'),svg:css('drawing','fill'),
              swatch:css('swatch','backgroundColor'),photo:document.getElementById('photo').src,
              backgroundPhoto:css('backgroundPhoto','backgroundImage'),gradient:css('gradient','backgroundImage'),
              mask:css('mask','backgroundColor'),indicator:getComputedStyle(document.getElementById('indicator'),'::before').backgroundColor};
          })()
          """) as? [String: String] ?? [:]
    }

    private static let html = #"""
    <!doctype html><html><head><meta name="viewport" content="width=device-width">
    <style>body{background:pink}p{color:blue}button{background:red;color:white}
    #backgroundPhoto{width:80px;height:60px;background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg'/%3E")}
    #card{position:relative;width:160px;height:100px;border:4px solid transparent}
    #card img{width:160px;height:100px;display:block}
    #card::before{content:'';position:absolute;inset:0;background:rgba(0,0,0,.03);z-index:1}
    #card::after{content:'';position:absolute;inset:0;background:linear-gradient(transparent,rgba(0,0,0,.5));z-index:2}
    #overlay{position:absolute;inset:0;background:rgba(0,0,0,.1)}
    #hiddenLabel{color:transparent;background-image:url("data:image/svg+xml,%3Csvg/%3E")}
          #plainLink{text-decoration:none;display:inline-block}
    #imageSet{background-image:image-set(url("data:image/svg+xml,%3Csvg/%3E") 1x)}
    #stencil{background-image:linear-gradient(red,blue)}
    #stencil::before{content:'';background-image:url("data:image/svg+xml,%3Csvg/%3E")}
    #gradient{background:linear-gradient(red,blue)}
    #mask{width:24px;height:24px;background:red;mask-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg'/%3E")}
    #indicator::before{content:'';display:inline-block;width:12px;height:12px;background:red}</style></head><body>
    <p id="text">사진은 원래 색으로, 글자는 읽기 편하게</p>
    <a id="link" href="https://example.com">상품 상세</a><button id="button">장바구니</button><input placeholder="검색">
    <img id="photo" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg'/%3E" alt="상품 사진">
    <div id="backgroundPhoto"></div><div id="gradient">색이 있는 카드</div>
    <svg width="80" height="80"><rect id="drawing" fill="red" width="80" height="80"/></svg>
    <button id="swatch" class="color-swatch" style="background:green">초록</button>
    <div id="card"><img alt="사진" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='100'/%3E"><div id="overlay"></div></div>
    <a id="plainLink" href="#card">사진 상세 보기<span id="hiddenLabel">아이콘 설명</span></a><div id="imageSet"></div><span id="stencil"></span>
    <span id="mask"></span><span id="indicator">선택 표시</span>
    </body></html>
    """#
}
#endif
