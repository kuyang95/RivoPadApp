#if DEBUG
import XCTest
import WebKit
@testable import shortcuts_example

@MainActor
final class EasyYouTubeTests: XCTestCase {
    func testLauncherWebCanvasesAreTransparentAndYouTubeHeaderIsHidden() async throws {
        for easyYouTube in [false, true] {
            let browser = AccessibleWebBrowserModel(easyYouTube: easyYouTube, embedded: true)
            let web = browser.webView
            web.stopLoading()
            web.loadHTMLString("""
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><script>window.ytcfg={get:key=>key==='LOGGED_IN'?true:undefined};</script></head>
            <body style="background:white"><ytm-video-with-context-renderer><a href="/watch?v=dQw4w9WgXcQ"><h3>테스트 영상</h3></a></ytm-video-with-context-renderer></body></html>
            """, baseURL: URL(string: easyYouTube ? EasyYouTubePage.home : "https://example.com"))
            for _ in 0..<120 {
                let ready = try? await web.evaluateJavaScript(easyYouTube
                    ? "!!document.querySelector('[data-rivo-you-tube-home]')?.shadowRoot.querySelector('.card')"
                    : "!!document.getElementById('rivo-launcher-canvas') && document.readyState==='complete'")
                if ready as? Bool == true { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertFalse(web.isOpaque)
            let body = try await web.evaluateJavaScript("getComputedStyle(document.body).backgroundColor") as? String
            XCTAssertEqual(body, "rgba(0, 0, 0, 0)")
            if easyYouTube {
                let underlying = try await web.evaluateJavaScript("getComputedStyle(document.body).visibility") as? String
                XCTAssertEqual(underlying, "hidden", "The original YouTube page must not show through the transparent widget")
                let surface = try await web.evaluateJavaScript("""
                (()=>{const host=document.querySelector('[data-rivo-you-tube-home]');return getComputedStyle(host).backgroundColor==='rgba(0, 0, 0, 0)' && host.shadowRoot.querySelector('header').hidden;})()
                """) as? Bool
                XCTAssertEqual(surface, true)
                let art = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('[data-rivo-you-tube-home]').shadowRoot.querySelector('.sign-in-art')).display") as? String
                XCTAssertNotEqual(art, "none", "The YouTube artwork remains visible while the widget canvas is transparent")
                let playerLayer = try await web.evaluateJavaScript("""
                (()=>{const home=document.querySelector('[data-rivo-you-tube-home]'),player=document.createElement('div');player.setAttribute('data-rivo-official-player','');document.documentElement.appendChild(player);const hidden=getComputedStyle(home).visibility==='hidden';player.remove();return hidden && getComputedStyle(home).visibility==='visible';})()
                """) as? Bool
                XCTAssertEqual(playerLayer, true, "The player must show wallpaper instead of the video list behind it")
            }
            browser.shutdown()
        }
    }

    func testEmbeddedFeedRetainsThumbnailsAndScrollAndUsesHiddenNativeTabs() async throws {
        let browser = AccessibleWebBrowserModel(easyYouTube: true, embedded: true)
        defer { browser.shutdown() }
        let web = browser.webView
        web.frame = CGRect(x: 0, y: 0, width: 900, height: 700)
        web.stopLoading()
        web.loadHTMLString(Self.feedHTML.replacingOccurrences(of: "i<16", with: "i<0"), baseURL: URL(string: EasyYouTubePage.home))
        try await waitForLogin(web, expression: """
        (()=>{const r=document.querySelector('[data-rivo-you-tube-home]')?.shadowRoot;return r && !r.getElementById('loading').hidden && !r.getElementById('skeleton').hidden && r.querySelectorAll('.skeleton-card').length===6 && r.getElementById('more').hidden;})()
        """)
        web.loadHTMLString(Self.feedHTML, baseURL: URL(string: EasyYouTubePage.home))
        try await waitForLogin(web, expression: "document.querySelector('[data-rivo-you-tube-home]')?.shadowRoot.querySelectorAll('.card').length===16")
        let prepared = try await web.evaluateJavaScript("""
        (()=>{const r=document.querySelector('[data-rivo-you-tube-home]').shadowRoot;
        if(r.querySelector('.duration').textContent!=='2일 전 · 길이 1:02:03'||r.querySelector('.meta').textContent!=='리보 채널 · 조회수 1.2만회'||!r.querySelector('.card').getAttribute('aria-label').includes('1시간 2분 3초')||r.querySelector('.copy').getAttribute('aria-hidden')!=='true')return false;window.rivoFirstCard=r.querySelector('.card');window.rivoFirstImage=r.querySelector('.card img');r.getElementById('content').scrollTop=200;
        return getComputedStyle(document.body).visibility==='hidden' && !r.querySelector('.play') && [...r.querySelectorAll('.card img')].every(i=>i.src.includes('/hqdefault.jpg'));})()
        """) as? Bool
        XCTAssertEqual(prepared, true)
        let loading = try await web.evaluateJavaScript("""
        (()=>{const r=document.querySelector('[data-rivo-you-tube-home]').shadowRoot;r.getElementById('more').click();return r.getElementById('more').hidden && !r.getElementById('loading').hidden && r.getElementById('skeleton').hidden && r.querySelectorAll('.card').length===16;})()
        """) as? Bool
        XCTAssertEqual(loading,true)
        _ = try await web.evaluateJavaScript("document.querySelectorAll('ytm-video-with-context-renderer').forEach(e=>e.remove());true")
        try await Task.sleep(for: .milliseconds(1100))
        let stable = try await web.evaluateJavaScript("""
        (()=>{const r=document.querySelector('[data-rivo-you-tube-home]').shadowRoot;return r.querySelectorAll('.card').length===16
        && r.querySelector('.card')===window.rivoFirstCard && r.querySelector('.card img')===window.rivoFirstImage && r.getElementById('content').scrollTop>=190;})()
        """) as? Bool
        XCTAssertEqual(stable, true)
        _ = try await web.evaluateJavaScript(#"const c=document.createElement('ytm-video-with-context-renderer');c.innerHTML='<a href="/watch?v=dQw4w9WgXcQ"><h3>추천 영상</h3></a>';document.body.appendChild(c);window.__rivoYouTubePrototype.navigate('subscriptions');true"#)
        try await waitForLogin(web, expression: "location.pathname==='/feed/subscriptions' && window.__rivoYouTubePrototype.state().pending===null && document.querySelector('[data-rivo-you-tube-home]').shadowRoot.querySelector('.title')?.textContent==='구독 영상'")
        _ = try await web.evaluateJavaScript("history.pushState({},'', '/shorts/dQw4w9WgXcQ');window.__rivoYouTubePrototype.navigate('shorts');true")
        try await waitForLogin(web, expression: "location.pathname==='/shorts/dQw4w9WgXcQ' && window.__rivoYouTubePrototype.state().pending===null && window.__rivoYouTubePrototype.state().count===0")
        _ = try await web.evaluateJavaScript("document.querySelector('h1').remove();const next=document.createElement('button');next.setAttribute('aria-label','다음 동영상');next.onclick=()=>history.pushState({},'', '/shorts/dQw4w9WgXcR');document.body.appendChild(next);true")
        try await waitForLogin(web, expression: "!document.querySelector('[data-rivo-official-player]')?.shadowRoot.getElementById('short-next').disabled")
        _ = try await web.evaluateJavaScript("document.querySelector('[data-rivo-official-player]')?.shadowRoot.getElementById('short-next').click();true")
        try await waitForLogin(web, expression: "location.pathname==='/shorts/dQw4w9WgXcR' && window.__rivoYouTubePrototype.state().pending===null")
    }

    func testEmbeddedYouTubeSwipeUsesNativePageCallbackAndKeepsVerticalAndRangeGestures() async throws {
        let browser = AccessibleWebBrowserModel(easyYouTube: true, embedded: true)
        defer { browser.shutdown() }
        let web = browser.webView
        web.frame = CGRect(x: 0, y: 0, width: 900, height: 1000)
        web.stopLoading()
        web.loadHTMLString(Self.feedHTML, baseURL: URL(string: EasyYouTubePage.home))
        try await waitForLogin(web, expression: "!!document.querySelector('[data-rivo-you-tube-home]')?.shadowRoot.querySelector('.card')")
        var turns: [Int] = []
        browser.onLauncherPageTurn = { turns.append($0) }
        let swipe = try XCTUnwrap(browser.launcherSwipe(for: web))
        XCTAssertTrue(web.gestureRecognizers?.contains(swipe.pan) == true)
        XCTAssertFalse(web.allowsBackForwardNavigationGestures)
        func prepare() async throws {
            swipe.prepare(at: CGPoint(x:450,y:450))
            for _ in 0..<40 { if swipe.eligible { return }; try await Task.sleep(for:.milliseconds(25)) }
            XCTFail("Native page swipe did not receive its geometric hit test")
        }
        try await prepare();swipe.finish(translation:CGPoint(x:300,y:400))
        try await prepare();swipe.finish(translation:CGPoint(x:30,y:0))
        try await prepare();swipe.finish(translation:CGPoint(x:-300,y:0),cancelled:true)
        XCTAssertEqual(turns, [])
        _ = try await web.evaluateJavaScript("const r=document.querySelector('[data-rivo-you-tube-home]').shadowRoot;const input=document.createElement('input');input.type='range';input.style='position:fixed;left:0;top:40%;width:100%;height:100px;z-index:99999';r.append(input);window.testRange=input;true")
        swipe.prepare(at:CGPoint(x:450,y:450))
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertFalse(swipe.eligible)
        swipe.finish(translation:CGPoint(x:-300,y:0))
        XCTAssertEqual(turns, [])
        _ = try await web.evaluateJavaScript("window.testRange.remove();window.__rivoOfficialPlayer.open({videoId:'dQw4w9WgXcQ',short:true});true")
        try await waitForLogin(web, expression:"!!document.querySelector('[data-rivo-official-player]')?.shadowRoot.querySelector('iframe')")
        let frameGuard = try await web.evaluateJavaScript("""
        (()=>{const r=document.querySelector('[data-rivo-official-player]').shadowRoot,f=r.querySelector('iframe').getBoundingClientRect();return window.__rivoLauncherCanPageAt((f.left+f.width/2)/innerWidth,(f.top+f.height/2)/innerHeight) && !window.__rivoLauncherCanPageAt((f.left+f.width/2)/innerWidth,(f.bottom-20)/innerHeight)})()
        """) as? Bool
        XCTAssertEqual(frameGuard,true)
        try await prepare();swipe.finish(translation:CGPoint(x:-300,y:0))
        try await prepare();swipe.finish(translation:CGPoint(x:300,y:0))
        var progress:[CGFloat]=[],endings:[Bool]=[]
        browser.onLauncherPageDrag={progress.append($0)}
        browser.onLauncherPageDragEnd={endings.append($0)}
        try await prepare();swipe.update(translation:CGPoint(x:-120,y:0))
        XCTAssertEqual(progress,[-120]);XCTAssertEqual(turns,[1,-1])
        swipe.finish(translation:CGPoint(x:-120,y:0),cancelled:true)
        XCTAssertEqual(endings,[true]);XCTAssertEqual(turns,[1,-1])
        XCTAssertEqual(turns, [1,-1])
        XCTAssertEqual(web.url?.host, "m.youtube.com", "Page requests must be cancelled before web navigation")
    }

    func testBrowserWidgetReflowsWideContentAndPagesAtLargeText() async throws {
        let browser=AccessibleWebBrowserModel(easyYouTube:false,embedded:true)
        defer { browser.shutdown() }
        let web=browser.webView
        web.frame=CGRect(x:0,y:0,width:600,height:900)
        web.stopLoading()
        web.loadHTMLString(Self.wideBrowserHTML,baseURL:URL(string:"https://example.test/"))
        try await waitForLogin(web,expression:"document.querySelectorAll('#wide [data-rivo-fit-label]').length===6")
        browser.setZoom(100)
        try await Task.sleep(for:.milliseconds(150))
        _ = try await web.evaluateJavaScript("const sample=document.createElement('span');sample.id='font-sample';sample.style='font-size:22px;display:inline-block';sample.textContent='가';document.getElementById('article').prepend(sample);true")
        let initialTextHeight=try await web.evaluateJavaScript("document.getElementById('font-sample').getBoundingClientRect().height") as! Double
        browser.setZoom(150)
        try await Task.sleep(for:.milliseconds(200))
        let fits=try await web.evaluateJavaScript("""
        (()=>{const width=document.documentElement.clientWidth;
        return [...document.querySelectorAll('#article,#photo,#code,.grid,.rail,#wide,td')].every(e=>e.getBoundingClientRect().right<=width+2) &&
          [...document.querySelectorAll('#article,#photo,#code,.grid,.rail,#wide,td')].every(e=>e.scrollWidth<=e.clientWidth+2) &&
          document.querySelectorAll('#wide td').length===6 &&
          document.getElementById('field').value==='유지할 입력값' && document.getElementById('photo').naturalWidth===1600;})()
        """) as? Bool
        let diagnostics=try await web.evaluateJavaScript("JSON.stringify({flag:window.__rivoLauncherBrowser,fit:window.__rivoLauncherReflow,styles:document.querySelectorAll('[data-rivo-browser-fit-style]').length,labels:document.querySelectorAll('[data-rivo-fit-label]').length,width:document.documentElement.clientWidth,scroll:document.documentElement.scrollWidth,font:getComputedStyle(document.body).fontSize,photo:document.getElementById('photo').naturalWidth,value:document.getElementById('field').value,nodes:[...document.querySelectorAll('#article,#photo,#code,.grid,.rail,#wide,td')].map(e=>[e.id||e.className,e.clientWidth,e.scrollWidth,e.getBoundingClientRect().right])})")
        XCTAssertEqual(fits,true,"\(diagnostics), native content: \(web.scrollView.contentSize), bounds: \(web.bounds)")
        XCTAssertLessThanOrEqual(web.scrollView.contentSize.width,web.bounds.width+2)
        let enlargedTextHeight=try await web.evaluateJavaScript("document.getElementById('font-sample').getBoundingClientRect().height") as! Double
        XCTAssertGreaterThan(enlargedTextHeight,initialTextHeight*1.4,"Default: \(browser.defaultZoomPercent), initial: \(initialTextHeight), enlarged: \(enlargedTextHeight)")
        XCTAssertEqual(web.pageZoom,1)
        XCTAssertEqual(browser.zoomPercent,150)
        let layoutZoom=try await web.evaluateJavaScript("parseFloat(getComputedStyle(document.documentElement).zoom)") as? Double
        XCTAssertEqual(layoutZoom,1.5)
        _ = try await web.evaluateJavaScript("document.getElementById('action').click();const p=document.createElement('div');p.style='width:1900px;white-space:nowrap';p.textContent='늦게 나타난 내용 '.repeat(50);document.getElementById('article').appendChild(p);true")
        try await waitForLogin(web,expression:"document.documentElement.scrollWidth<=document.documentElement.clientWidth+2")
        let dynamic=try await web.evaluateJavaScript("document.getElementById('article').getBoundingClientRect().right<=document.documentElement.clientWidth+2 && document.getElementById('action').textContent==='눌렀어요'") as? Bool
        XCTAssertEqual(dynamic,true)
        var turns:[Int]=[]
        browser.onLauncherPageTurn={turns.append($0)}
        let swipe=try XCTUnwrap(browser.launcherSwipe(for:web))
        XCTAssertFalse(web.allowsBackForwardNavigationGestures)
        func prepare() async throws {
            swipe.prepare(at:CGPoint(x:450,y:450))
            for _ in 0..<40 { if swipe.eligible { return };try await Task.sleep(for:.milliseconds(25)) }
            XCTFail("Browser page swipe did not receive its geometric hit test")
        }
        try await prepare();swipe.finish(translation:CGPoint(x:-150,y:300))
        XCTAssertEqual(turns,[])
        try await prepare();swipe.finish(translation:CGPoint(x:-250,y:0))
        try await prepare();swipe.finish(translation:CGPoint(x:250,y:0))
        XCTAssertEqual(turns,[1,-1])
        XCTAssertEqual(web.url?.host,"example.test")
    }
    private static let wideBrowserHTML = #"""
    <!doctype html><html><head><meta name="viewport" content="width=1400"><style>
    body{min-width:1400px;font-size:22px}article{width:1400px}td,th{border:1px solid;padding:12px} .grid{display:grid;grid-template-columns:600px 600px 600px}.rail{display:flex;overflow-x:auto;white-space:nowrap}.rail>div{flex:0 0 600px}.box{padding:20px}pre{width:1800px;white-space:pre} </style></head><body>
    <article id="article"><h1>넓은 페이지</h1><p>긴 본문과 이미지, 표, 가로 목록을 화면 안에 표시합니다.</p>
    <img id="photo" width="1600" height="800" alt="확인 그림" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='1600' height='800'%3E%3Crect width='1600' height='800' fill='steelblue'/%3E%3C/svg%3E">
    <pre id="code">long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_long_code_line_</pre><div class="grid"><div class="box">첫 항목</div><div class="box">두 번째 항목</div><div class="box">세 번째 항목</div></div>
    <div class="rail"><div class="box">가로 목록 하나</div><div class="box">가로 목록 둘</div><div class="box">가로 목록 셋</div></div>
    <table id="wide" style="min-width:1800px"><thead><tr><th scope="col">항목 1</th><th scope="col">항목 2</th><th scope="col">항목 3</th><th scope="col">항목 4</th><th scope="col">항목 5</th><th scope="col">항목 6</th></tr></thead><tbody><tr><td>내용 1 자세한 설명</td><td>내용 2 자세한 설명</td><td>내용 3 자세한 설명</td><td>내용 4 자세한 설명</td><td>내용 5 자세한 설명</td><td>내용 6 자세한 설명</td></tr></tbody></table>
    <button id="action" onclick="this.textContent='눌렀어요'">동작 확인</button><input id="field" value="유지할 입력값">
    <p id="end">마지막 내용까지 모두 표시합니다.</p></article></body></html>
    """#

    private static let feedHTML = #"""
    <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><script>window.ytcfg={get:key=>key==='LOGGED_IN'?true:undefined};window.YT={Player:function(target,options){window.rivoPlayerOptions=options;window.rivoPlayerEvents=options.events;const f=document.createElement('iframe');f.id='test-official-player';target.replaceWith(f);let rate=1,state=5;this.getIframe=()=>f;this.destroy=()=>f.remove();this.getCurrentTime=()=>5;this.getDuration=()=>60;this.getPlayerState=()=>state;this.getPlaybackRate=()=>rate;this.getAvailablePlaybackRates=()=>[.5,1,1.5,2];this.setPlaybackRate=value=>{rate=value;window.rivoPlaybackRate=value};this.seekTo=value=>window.rivoSeek=value;this.pauseVideo=()=>{state=2};this.playVideo=()=>{state=1;window.rivoPlayRequested=true};setTimeout(()=>options.events.onReady({target:this}),0);}};</script></head><body>
    <h1>원본 쇼츠 제목</h1>
    <ytm-pivot-bar-item-renderer><button role="tab" onclick="history.pushState({},'', '/');document.querySelector('h3').textContent='추천 영상'">홈</button></ytm-pivot-bar-item-renderer>
    <ytm-pivot-bar-item-renderer><button role="tab" onclick="history.pushState({},'', '/feed/subscriptions');document.querySelector('h3').textContent='구독 영상'">구독</button></ytm-pivot-bar-item-renderer>
    <ytm-pivot-bar-item-renderer><button role="tab" onclick="history.pushState({},'', '/shorts/dQw4w9WgXcQ')">Shorts</button></ytm-pivot-bar-item-renderer>
    <script>for(let i=0;i<16;i++){const card=document.createElement('ytm-video-with-context-renderer');const a=document.createElement('a');a.href='/watch?v=dQw4w9WgXc'+i.toString(16);const title=document.createElement('h3');title.textContent='추천 영상 '+i;a.appendChild(title);card.appendChild(a);const duration=document.createElement('span');duration.className='ytBadgeShapeText';duration.textContent=i===0?'1:02:03':'12:34';card.appendChild(duration);const meta=document.createElement('span');meta.className='ytContentMetadataViewModelMetadataText';meta.textContent='리보 채널 · 조회수 1.2만회 · 2일 전';card.appendChild(meta);card.appendChild(document.createElement('img'));document.body.appendChild(card);}</script>
    </body></html>
    """#

    func testPortraitAutoplayChannelCommentsAndSimpleControls() async throws {
        let browser = AccessibleWebBrowserModel(easyYouTube: true, embedded: true)
        defer { browser.shutdown() }
        let web = browser.webView
        web.frame = CGRect(x: 0, y: 0, width: 900, height: 1000)
        web.stopLoading()
        web.loadHTMLString(Self.watchHTML, baseURL: URL(string: EasyYouTubePage.home))
        try await waitForLogin(web, expression: "!!window.__rivoYouTubePrototype && document.readyState==='complete'")
        _ = try await web.evaluateJavaScript("history.pushState({},'', '/shorts/dQw4w9WgXcQ');window.__rivoYouTubePrototype.navigate('shorts');true")
        try await waitForLogin(web, expression: "window.rivoPlayRequested===true && !!document.querySelector('[data-rivo-official-player]')")
        let simplified = try await web.evaluateJavaScript("""
        (()=>{const r=document.querySelector('[data-rivo-official-player]').shadowRoot,screen=r.querySelector('.screen').getBoundingClientRect();
        return screen.width>=200 && screen.height>=360 && screen.height>screen.width*1.5 && ['close','back','play','forward','captions','native-access'].every(id=>!r.getElementById(id))
        && !r.textContent.includes('시험판') && r.getElementById('speed').selectedOptions[0].textContent==='1×'
        && window.rivoPlayerOptions.playerVars.autoplay===1 && window.rivoPlayerOptions.playerVars.controls===1 && window.rivoPlayerOptions.playerVars.cc_load_policy===0
        && !r.getElementById('channel') && !r.querySelector('.comment') && r.querySelectorAll('.short-actions button').length===2;})()
        """) as? Bool
        XCTAssertEqual(simplified, true)
        let fullShort = try await web.evaluateJavaScript("""
        (()=>{const r=document.querySelector('[data-rivo-official-player]').shadowRoot,s=r.querySelector('.screen').getBoundingClientRect(),m=r.querySelector('main').getBoundingClientRect();return r.getElementById('official-title').hidden && r.querySelector('.timeline').hidden && r.getElementById('status').hidden && Math.abs(s.height-Math.min(m.height-24-r.querySelector('.short-actions').offsetHeight-14,(m.width-24)*16/9))<3 && s.top>=m.top+11;})()
        """) as? Bool
        XCTAssertEqual(fullShort,true)
        _ = try await web.evaluateJavaScript("window.__rivoOfficialPlayer.open({videoId:'dQw4w9WgXcQ',title:'일반 영상'});true")
        try await waitForLogin(web, expression: "document.querySelector('[data-rivo-official-player]')?.shadowRoot.getElementById('speed')?.disabled===false")
        _ = try await web.evaluateJavaScript("window.rivoPlayerEvents.onStateChange({data:0});true")
        let cleanPresentation = try await web.evaluateJavaScript("""
        (()=>{const r=document.querySelector('[data-rivo-official-player]').shadowRoot,c=r.getElementById('channel'),a=c.querySelector('img'),speed=r.getElementById('speed'),seek=r.getElementById('seek'),comment=r.querySelector('.comment');
         const s=speed.getBoundingClientRect(),p=seek.getBoundingClientRect();
         return a.getAttribute('src')==='https://yt3.ggpht.com/rivo-avatar' && a.alt==='' && a.getAttribute('aria-hidden')==='true'
         && getComputedStyle(c).borderTopWidth==='0px' && getComputedStyle(c).backgroundColor==='rgba(0, 0, 0, 0)'
         && speed.closest('.timeline') && s.left>=p.right && Math.abs(s.top+s.height/2-p.top-p.height/2)<4
         && getComputedStyle(comment).borderTopWidth==='0px' && getComputedStyle(comment).backgroundColor==='rgba(0, 0, 0, 0)'
         && getComputedStyle(r.getElementById('more-comments')).borderTopWidth==='0px' && r.getElementById('status').textContent==='';})()
        """) as? Bool
        XCTAssertEqual(cleanPresentation,true)
        _ = try await web.evaluateJavaScript("const r=document.querySelector('[data-rivo-official-player]').shadowRoot;r.getElementById('more-comments').click();r.getElementById('speed').value='1.5';r.getElementById('speed').dispatchEvent(new Event('change'));r.getElementById('seek').value=25;r.getElementById('seek').dispatchEvent(new Event('change'));true")
        let more = try await web.evaluateJavaScript("document.querySelector('[data-rivo-official-player]').shadowRoot.querySelectorAll('.comment').length===8 && window.rivoPlaybackRate===1.5 && window.rivoSeek===25") as? Bool
        XCTAssertEqual(more, true)
        _ = try await web.evaluateJavaScript("window.__rivoOfficialPlayer.open({videoId:'dQw4w9WgXcQ',onChannel:url=>window.rivoChannelTarget=url});document.querySelector('[data-rivo-official-player]').shadowRoot.getElementById('channel').click();true")
        let channel = try await web.evaluateJavaScript("window.rivoChannelTarget") as? String
        XCTAssertEqual(channel, "https://m.youtube.com/@rivo/videos")
    }

    private static let watchHTML = #"""
    <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><script>window.ytcfg={get:key=>key==='LOGGED_IN'?true:undefined};window.YT={Player:function(target,options){window.rivoPlayerOptions=options;window.rivoPlayerEvents=options.events;const f=document.createElement('iframe');f.id='test-official-player';target.replaceWith(f);let rate=1,state=5;this.getIframe=()=>f;this.destroy=()=>f.remove();this.getCurrentTime=()=>5;this.getDuration=()=>60;this.getPlayerState=()=>state;this.getPlaybackRate=()=>rate;this.getAvailablePlaybackRates=()=>[.5,1,1.5,2];this.setPlaybackRate=value=>{rate=value;window.rivoPlaybackRate=value};this.seekTo=value=>window.rivoSeek=value;this.pauseVideo=()=>{state=2};this.playVideo=()=>{state=1;window.rivoPlayRequested=true};setTimeout(()=>options.events.onReady({target:this}),0);}};</script></head><body><h1>테스트 영상</h1><a class="slim-video-owner-icon" href="/@rivo" aria-label="리보 채널, 구독자 123명. 채널로 이동합니다."><img src="https://yt3.ggpht.com/rivo-avatar" alt=""></a><ytm-video-with-context-renderer><a href="/watch?v=dQw4w9WgXcQ" onclick="event.preventDefault();history.pushState({},'',this.getAttribute('href'))"><h3>테스트 영상</h3></a></ytm-video-with-context-renderer><script>for(let i=0;i<12;i++){const thread=document.createElement('ytm-comment-thread-renderer');const author=document.createElement('span');author.className='YtmCommentRendererTitle';author.textContent='작성자 '+i;const text=document.createElement('p');text.className='YtmCommentRendererText';text.textContent='실제 DOM 댓글 '+i;thread.append(author,text);document.body.append(thread);}</script></body></html>
    """#

    func testGoogleLoginKeepsNativeFormAndRestoresAdditionalVerification() async throws {
        let browser = AccessibleWebBrowserModel(easyYouTube: true)
        defer { browser.shutdown() }
        let web = browser.webView
        web.stopLoading()
        web.loadHTMLString(Self.googleLoginHTML, baseURL: URL(string: "https://accounts.google.com/v3/signin/identifier"))
        try await waitForLogin(web, expression: "document.documentElement.getAttribute('data-rivo-google-login')==='identifier' && !document.documentElement.hasAttribute('data-rivo-google-login-preparing') && document.readyState==='complete'")
        let beforePaint = try await web.evaluateJavaScript("window.rivoLoginBeforePaint.pending && window.rivoLoginBeforePaint.hidden && window.rivoLoginBeforePaint.centered") as? Bool
        XCTAssertEqual(beforePaint, true, "Initial parser output must stay hidden until centered")
        let form = try await web.evaluateJavaScript("""
        (()=>{const hidden=s=>getComputedStyle(document.querySelector(s)).display==='none';
        return ['footer','[jsname="Cuz2Ue"]','.RDsYTb','[jsname="FIbd0b"]'].every(hidden)
            && document.getElementById('identifierId')===window.originalLoginInput
            && document.getElementById('identifierId').autocomplete==='username'
            && document.getElementById('next').getBoundingClientRect().height>=64;})()
        """) as? Bool
        XCTAssertEqual(form, true)
        _ = try await web.evaluateJavaScript("document.getElementById('next').click();true")
        let error = try await web.evaluateJavaScript("document.getElementById('error').textContent==='입력을 확인하세요.' && getComputedStyle(document.getElementById('error')).display!=='none'") as? Bool
        XCTAssertEqual(error, true)
        _ = try await web.evaluateJavaScript("document.getElementById('ca').style.display='block';true")
        try await waitForLogin(web, expression: "!document.documentElement.hasAttribute('data-rivo-google-login') && getComputedStyle(document.querySelector('footer')).display!=='none'")
        _ = try await web.evaluateJavaScript("document.getElementById('ca').style.display='none';history.pushState({},'', '/v3/signin/challenge/pwd');const field=document.getElementById('identifierId');field.type='password';field.name='Passwd';document.getElementById('identifierNext').id='passwordNext';true")
        try await waitForLogin(web, expression: "document.documentElement.getAttribute('data-rivo-google-login')==='password'")
        _ = try await web.evaluateJavaScript("history.pushState({},'', '/v3/signin/challenge/totp');document.body.appendChild(document.createElement('span'));true")
        try await waitForLogin(web, expression: "!document.documentElement.hasAttribute('data-rivo-google-login') && getComputedStyle(document.querySelector('footer')).display!=='none'")
    }

    func testGoogleLoginAdapterDoesNotChangeUnrelatedHostsOrConsent() async throws {
        let browser = AccessibleWebBrowserModel(easyYouTube: true)
        defer { browser.shutdown() }
        for address in ["https://example.com/v3/signin/identifier", "https://accounts.google.com/signin/oauth/consent"] {
            let web = browser.webView
            web.stopLoading()
            web.loadHTMLString(Self.googleLoginHTML, baseURL: URL(string: address))
            try await waitForLogin(web, expression: "document.readyState==='complete' && location.href==='\(address)' && !!document.querySelector('footer')")
            let original = try await web.evaluateJavaScript("!document.documentElement.hasAttribute('data-rivo-google-login') && getComputedStyle(document.querySelector('footer')).display!=='none'") as? Bool
            XCTAssertEqual(original, true)
        }
    }

    func testPasswordDocumentPreservesAutofillAndShowPassword() async throws {
        let browser = AccessibleWebBrowserModel(easyYouTube: true)
        defer { browser.shutdown() }
        let web = browser.webView
        web.stopLoading()
        web.loadHTMLString(Self.googlePasswordHTML, baseURL: URL(string: "https://accounts.google.com/v3/signin/challenge/pwd"))
        try await waitForLogin(web, expression: "document.readyState==='complete' && document.documentElement.getAttribute('data-rivo-google-login')==='password' && !document.documentElement.hasAttribute('data-rivo-google-login-preparing')")
        let form = try await web.evaluateJavaScript("""
        (()=>{const field=document.getElementById('passwordId');return window.rivoLoginBeforePaint.hidden
            && getComputedStyle(document.body).justifyContent==='center'
            && field===window.originalLoginInput && field.autocomplete==='current-password'
            && field.type==='password' && getComputedStyle(document.getElementById('forgot')).display==='none'
            && document.getElementById('next').getBoundingClientRect().height>=64;})()
        """) as? Bool
        XCTAssertEqual(form, true)
        _ = try await web.evaluateJavaScript("document.getElementById('show-password').click();true")
        let shown = try await web.evaluateJavaScript("document.getElementById('passwordId').type==='text'") as? Bool
        XCTAssertEqual(shown, true)
        _ = try await web.evaluateJavaScript("document.getElementById('next').click();true")
        let error = try await web.evaluateJavaScript("document.getElementById('error').textContent==='입력을 확인하세요.'") as? Bool
        XCTAssertEqual(error, true)
    }

    func testYouTubeBackClosesLocalSearchThenTraversesWebHistory() async throws {
        let browser = AccessibleWebBrowserModel(easyYouTube: true)
        defer { browser.shutdown() }
        let web = browser.webView
        web.stopLoading()
        web.loadHTMLString("<html><head><script>window.ytcfg={get:()=>true}</script></head><body></body></html>", baseURL: URL(string: EasyYouTubePage.home))
        try await waitForLogin(web, expression: "!!window.__rivoYouTubePrototype")
        _ = try await web.evaluateJavaScript("window.__rivoYouTubePrototype.navigate('search');true")
        var exhausted = false
        browser.handleBack { exhausted = true }
        try await waitForLogin(web, expression: "window.__rivoYouTubePrototype.state().section==='home'")
        XCTAssertFalse(exhausted)
        // loadHTMLString does not commit a normal back-forward item in WKWebView.
        // Local data pages give the native history fallback two committed entries.
        web.navigationDelegate = nil
        web.load(URLRequest(url: URL(string: "data:text/html,First")!))
        try await waitForLogin(web, expression: "document.readyState==='complete' && document.body.textContent==='First'")
        web.load(URLRequest(url: URL(string: "data:text/html,Second")!))
        try await waitForLogin(web, expression: "document.readyState==='complete' && document.body.textContent==='Second'")
        for _ in 0..<120 {
            if web.canGoBack { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(web.canGoBack)
        browser.handleBack { exhausted = true }
        try await waitForLogin(web, expression: "document.readyState==='complete' && document.body.textContent==='First'")
        XCTAssertFalse(exhausted)
    }

    private func waitForLogin(_ web: WKWebView, expression: String) async throws {
        for _ in 0..<120 {
            if (try? await web.evaluateJavaScript(expression)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Google login did not reach its expected presentation: \(expression)")
    }

    private static let googlePasswordHTML = #"""
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><script>window.rivoLoginBeforePaint={pending:document.documentElement.hasAttribute('data-rivo-google-login-preparing'),hidden:getComputedStyle(document.body).visibility==='hidden',centered:getComputedStyle(document.body).justifyContent==='center'};</script>
<main><div class="zIgDIc"><h1 id="headingText">로그인</h1></div><div class="UXFQgc"><div class="qWK5J"><div class="xKcayf">
<label for="passwordId">비밀번호</label><input id="passwordId" name="Passwd" type="password" autocomplete="current-password">
<button id="forgot">비밀번호를 잊으셨나요?</button><div class="RDsYTb">내 컴퓨터가 아닌가요? 게스트 모드를 사용하세요.</div>
<label><input id="show-password" type="checkbox" onclick="document.getElementById('passwordId').type=this.checked?'text':'password'">비밀번호 표시</label><div id="error" role="alert"></div><input id="ca" style="display:none" aria-label="보안 문자">
</div></div></div><div class="JYXaTc"><div class="O1Slxf"><div class="TNTaPb"><div id="passwordNext"><div><button id="next" onclick="document.getElementById('error').textContent='입력을 확인하세요.'">다음</button></div></div></div><div class="FO2vFd"><div jsname="FIbd0b"><button>계정 만들기</button></div></div></div></div></main>
<footer><select aria-label="언어"><option>한국어</option></select><a href="#">도움말</a><a href="#">개인정보처리방침</a><a href="#">약관</a></footer>
<script>window.originalLoginInput=document.getElementById('passwordId');</script>
</body></html>
"""#

    private static let googleLoginHTML = #"""
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><script>window.rivoLoginBeforePaint={pending:document.documentElement.hasAttribute('data-rivo-google-login-preparing'),hidden:getComputedStyle(document.body).visibility==='hidden',centered:getComputedStyle(document.body).justifyContent==='center'};</script>
<main><div class="zIgDIc"><h1 id="headingText">로그인</h1></div><div class="UXFQgc"><div class="qWK5J"><div class="xKcayf">
<label for="identifierId">이메일 또는 휴대전화</label><input id="identifierId" name="identifier" autocomplete="username">
<button jsname="Cuz2Ue">이메일을 잊으셨나요?</button><div class="RDsYTb">내 컴퓨터가 아닌가요? 게스트 모드를 사용하세요.</div>
<div id="error" role="alert"></div><input id="ca" style="display:none" aria-label="보안 문자">
</div></div></div><div class="JYXaTc"><div class="O1Slxf"><div class="TNTaPb"><div id="identifierNext"><div><button id="next" onclick="document.getElementById('error').textContent='입력을 확인하세요.'">다음</button></div></div></div><div class="FO2vFd"><div jsname="FIbd0b"><button>계정 만들기</button></div></div></div></div></main>
<footer><select aria-label="언어"><option>한국어</option></select><a href="#">도움말</a><a href="#">개인정보처리방침</a><a href="#">약관</a></footer>
<script>window.originalLoginInput=document.getElementById('identifierId');</script>
</body></html>
"""#

    func testDedicatedStoreAndPageWorldInstallation() async throws {
        let browser = AccessibleWebBrowserModel(easyYouTube: true)
        defer { browser.shutdown() }
        XCTAssertTrue(browser.webView.configuration.websiteDataStore.isPersistent)
        let web = browser.webView
        web.stopLoading()
        web.loadHTMLString("""
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><script>window.ytcfg={get:key=>key==='LOGGED_IN'?true:undefined};</script></head>
        <body><ytm-video-with-context-renderer><a href="/watch?v=dQw4w9WgXcQ"><h3>테스트 영상</h3></a></ytm-video-with-context-renderer></body></html>
        """, baseURL: URL(string: EasyYouTubePage.home))
        for _ in 0..<120 {
            if (try? await web.evaluateJavaScript("!!document.querySelector('[data-rivo-you-tube-home]')?.shadowRoot.querySelector('.card')")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let installed = try await web.evaluateJavaScript("""
        (()=>{const r=document.querySelector('[data-rivo-you-tube-home]')?.shadowRoot;
        return !!r && r.querySelectorAll('nav button').length===3 && !r.getElementById('theme') && !r.getElementById('original');})()
        """) as? Bool
        XCTAssertEqual(installed, true)
        XCTAssertTrue(browser.easyYouTube)
        let generic = AccessibleWebBrowserModel()
        defer { generic.shutdown() }
        XCTAssertFalse(generic.webView.configuration.websiteDataStore.isPersistent)
    }
}
#endif
