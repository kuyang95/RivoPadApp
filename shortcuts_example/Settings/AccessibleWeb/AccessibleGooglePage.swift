#if DEBUG
import Foundation

/// Google-only presentation; the original live AI section keeps citations and expansion.
enum AccessibleGooglePage {
    static func bootstrap(enabled: Bool, appearanceEnabled: Bool = true, palette: AccessibleWebPalette = .dark) -> String {
        let language = AppLanguage.current().localizationCode ?? Locale.current.language.languageCode?.identifier ?? "ko"
        let supportedLanguage = ["ko", "en", "ja"].contains(language) ? language : "ko"
        return source + "\nwindow.__rivoGoogleSimple?.set({enabled: \(enabled), language: '\(supportedLanguage)', appearanceEnabled: \(appearanceEnabled), palette: '\(palette.rawValue)', nativePageZoom: true, favorites: (location.protocol === 'https:' && /^(www\\.)?google\\.(com|co\\.kr)$/i.test(location.hostname) && ['', '/', '/webhp'].includes(location.pathname) ? \(BrowserFavorites.json) : [])});"
    }

    static let source = #"""
// Shared verbatim by iPad WKContentWorld and Android WebView. No native bridge.
(() => {
  if (window.top !== window || window.__rivoGoogleSimple) return;
  const googleHost = /^(www\.)?google\.(com|co\.kr)$/i.test(location.hostname);
  if (!googleHost) return;
  const strings = {
    ko: {search:'검색', voice:'음성 검색', invalid:'검색어나 올바른 웹 주소를 입력해 주세요.', go:'검색', favorites:'즐겨찾기', sites:'사이트 검색 결과', loading:'검색 결과를 불러오는 중입니다.', empty:'표시할 사이트가 없습니다.', original:'구글 원본 보기', addFavorite:'즐겨찾기 추가', add:'추가', naver:'네이버', daum:'다음', youtube:'유튜브', wiki:'위키백과'},
    en: {search:'Search', voice:'Voice search', invalid:'Enter a search or a valid web address.', go:'Search', favorites:'Favorites', sites:'Website results', loading:'Loading search results.', empty:'No websites to show.', original:'Show original Google page', addFavorite:'Add favorite', add:'Add', naver:'Naver', daum:'Daum', youtube:'YouTube', wiki:'Wikipedia'},
    ja: {addFavorite:'お気に入りを追加', add:'追加', search:'検索', voice:'音声検索', invalid:'検索語または正しいウェブアドレスを入力してください。', go:'検索', favorites:'お気に入り', sites:'サイトの検索結果', loading:'検索結果を読み込んでいます。', empty:'表示できるサイトがありません。', original:'Googleの元のページを表示', naver:'Naver', daum:'Daum', youtube:'YouTube', wiki:'ウィキペディア'}
  };
  let config = {enabled:true, language:'ko', appearanceEnabled:true, palette:'dark', nativePageZoom:false, favorites:[]};
  const palettes = {
    dark: {bg:'#202124', surface:'#292A2D', text:'#F1F3F4', edge:'#9AA0A6', link:'#F1F3F4', scheme:'dark'},
    light: {bg:'#FFFFFF', surface:'#F0F2F5', text:'#283546', edge:'#536176', link:'#704000', scheme:'light'}
  };
  let header, results, style, input, status, list, timer, fallbackTimer;
  let signature = '', currentRoute = '', ai = null;
  let viewport = null, originalViewport = null, createdViewport = false;
  let keep = new Set(), paths = new Set(), sourceMarks = new Map(), sourceAccessibility = new Map();
  const own = '[data-rivo-google-ui]';
  const css = `
    html[data-rivo-google-simple] {overflow-x:auto!important;}
    html[data-rivo-google-simple] body {overflow-x:visible!important;}
    html[data-rivo-google-simple] body {display:block!important; margin:0!important; padding:20px!important; min-width:0!important; width:auto!important; max-width:100%!important; box-sizing:border-box!important;}
    html[data-rivo-google-simple] body *:not([data-rivo-google-path]):not([data-rivo-google-keep]):not([data-rivo-google-keep] *) {display:none!important;}
    html[data-rivo-google-simple] [data-rivo-google-keep] {contain:inline-size; min-width:0!important; box-sizing:border-box!important;}
    html[data-rivo-google-simple] [data-rivo-google-path] {display:contents!important;}
    html[data-rivo-google-simple] [data-rivo-google-ai] {display:block!important; position:relative!important; width:100%!important; overflow-x:auto!important; overflow-wrap:anywhere!important; max-width:760px!important; margin:0 auto 24px!important; float:none!important;}
    html[data-rivo-google-simple] [data-rivo-google-ai] {font:20px/1.65 system-ui,sans-serif!important;}
    html[data-rivo-google-simple] [data-rivo-google-ai] :is(div,span,p,li) {font-size:inherit!important; line-height:inherit!important;}
    html[data-rivo-google-simple] [data-rivo-google-ui] {display:block!important; width:100%!important; max-width:760px!important; margin:0 auto!important; font:20px/1.65 system-ui,sans-serif!important; text-align:start!important;}
    html[data-rivo-google-simple] [data-rivo-google-ui] * {box-sizing:border-box!important; font-family:inherit!important;}
    html[data-rivo-google-simple] [data-rivo-google-ui] form {display:flex!important; gap:12px!important; margin:12px 0 28px!important; flex-wrap:wrap!important;}
    html[data-rivo-google-simple] [data-rivo-google-ui] input {flex:1 1 180px!important; width:0!important; min-width:120px!important; min-height:56px!important; border:1px solid currentColor!important; border-radius:16px!important; padding:12px 16px!important; font-size:20px!important; line-height:1.5!important;}
    html[data-rivo-google-simple] [data-rivo-google-ui] button {min-width:64px!important; min-height:56px!important; padding:12px 20px!important; border:1px solid currentColor!important; border-radius:16px!important; font-size:20px!important; cursor:pointer!important;}
    html[data-rivo-google-simple] [data-rivo-google-ui] h2 {font-size:20px!important; line-height:1.5!important; margin:0 0 12px!important; font-weight:600!important;}
    html[data-rivo-google-simple] [data-rivo-google-ui] nav {display:grid!important; grid-template-columns:repeat(auto-fit,minmax(130px,1fr))!important; gap:12px!important;}
    html[data-rivo-google-simple] [data-rivo-google-ui] nav a {display:flex!important; align-items:center!important; justify-content:center!important; min-height:64px!important; padding:16px!important; border:1px solid currentColor!important; border-radius:16px!important; text-decoration:none!important;}
    html[data-rivo-google-simple] [data-rivo-google-ui] ol {list-style:none!important; margin:0!important; padding:0!important;}
    html[data-rivo-google-simple] [data-rivo-google-ui] li {margin:0 0 16px!important; padding:0!important;}
    html[data-rivo-google-simple] [data-rivo-google-ui] li a {display:block!important; min-height:64px!important; padding:18px!important; border:1px solid currentColor!important; border-radius:16px!important; text-decoration:none!important; overflow-wrap:anywhere!important;}
    html[data-rivo-google-simple] [data-rivo-google-ui] strong {display:block!important; font-size:22px!important; line-height:1.5!important;}
    html[data-rivo-google-simple] [data-rivo-google-ui] small {display:block!important; font-size:16px!important; line-height:1.5!important; margin-top:6px!important;}
    html[data-rivo-google-simple] [data-rivo-google-ui] :focus-visible {outline:3px solid currentColor!important; outline-offset:3px!important;}
    html[data-rivo-google-simple] [data-rivo-google-ui] [hidden] {display:none!important;}
    html[data-rivo-google-simple] [data-rivo-google-ai] {inset:auto!important;transform:none!important;translate:none!important;padding:0!important;overflow:visible!important;}
    html[data-rivo-google-simple] [data-rivo-google-ai] [data-rivo-google-source-path] {position:static!important;inset:auto!important;transform:none!important;translate:none!important;width:100%!important;min-width:0!important;max-width:100%!important;max-height:none!important;margin-inline:0!important;overflow:visible!important;}
    html[data-rivo-google-simple] [data-rivo-google-ai] [data-rivo-google-sources] {display:grid!important;grid-template-columns:repeat(auto-fit,minmax(min(100%,260px),1fr))!important;gap:14px!important;padding:8px 0!important;width:100%!important;max-width:100%!important;overflow:visible!important;scroll-snap-type:none!important;transform:none!important;translate:none!important;}
    html[data-rivo-google-simple] [data-rivo-google-ai] [data-rivo-google-source] {display:block!important;box-sizing:border-box!important;position:static!important;inset:auto!important;transform:none!important;translate:none!important;float:none!important;flex:none!important;width:auto!important;min-width:0!important;max-width:100%!important;height:auto!important;max-height:none!important;margin:0!important;padding:14px!important;border:0!important;border-radius:14px!important;overflow:visible!important;white-space:normal!important;font-size:18px!important;line-height:1.55!important;}
    html[data-rivo-google-simple] [data-rivo-google-ai] [data-rivo-google-source] :is(div,span,a,p) {position:static!important;inset:auto!important;transform:none!important;translate:none!important;min-width:0!important;max-width:100%!important;margin-inline:0!important;white-space:normal!important;overflow-wrap:anywhere!important;text-overflow:clip!important;-webkit-line-clamp:unset!important;}
    html[data-rivo-google-simple] [data-rivo-google-ai] [data-rivo-google-source] a {display:block!important;min-height:48px!important;text-decoration:none!important;}
    html[data-rivo-google-simple] [data-rivo-google-ai] [data-rivo-google-source] [data-rivo-google-source-frame] {display:block!important;position:relative!important;box-sizing:border-box!important;width:100%!important;min-width:0!important;max-width:100%!important;height:auto!important;margin:0!important;padding:0!important;border:0!important;overflow:visible!important;}
    html[data-rivo-google-simple] [data-rivo-google-ai] [data-rivo-google-source] [data-rivo-google-source-overlay] {display:block!important;position:absolute!important;inset:0!important;width:100%!important;height:100%!important;min-height:0!important;z-index:1!important;border-radius:14px!important;}
    html[data-rivo-google-simple] [data-rivo-google-ai] [data-rivo-google-source-nav] {display:none!important;}
    html[data-rivo-google-simple] #rivo-google-results ol {display:block!important;margin:0!important;padding:0!important;}
    html[data-rivo-google-simple] #rivo-google-results li {display:block!important;min-width:0!important;margin:0!important;padding:0!important;}
    html[data-rivo-google-simple] #rivo-google-results li:not(:last-child)::after {content:''!important;display:block!important;height:1px!important;opacity:.28!important;}
    html[data-rivo-google-simple] #rivo-google-results .result-link {display:block!important;min-height:64px!important;padding:22px 2px 24px!important;border:0!important;border-radius:0!important;text-decoration:none!important;overflow-wrap:anywhere!important;}
    html[data-rivo-google-simple] #rivo-google-results .result-host {display:block!important;margin:0 0 5px!important;font-size:16px!important;line-height:1.5!important;opacity:.82!important;}
    html[data-rivo-google-simple] #rivo-google-results .result-title {display:block!important;margin:0!important;font-size:23px!important;font-weight:650!important;line-height:1.5!important;}
    html[data-rivo-google-simple] #rivo-google-results .result-snippet {display:block!important;margin:9px 0 0!important;font-size:18px!important;line-height:1.7!important;opacity:.92!important;}
    html[data-rivo-google-simple] #rivo-google-results .result-link [hidden] {display:none!important;}
    @media(hover:hover){html[data-rivo-google-simple] #rivo-google-results .result-link:hover .result-title {text-decoration:underline!important;text-underline-offset:4px!important;}}

    html[data-rivo-google-simple] #rivo-google-search form {align-items:center!important;gap:8px!important;flex-wrap:nowrap!important;padding:8px 0!important;border-bottom:1.5px solid currentColor!important;margin:0 0 32px!important;}
    html[data-rivo-google-simple] #rivo-google-search input {width:0!important;flex:1!important;min-width:0!important;min-height:64px!important;padding:12px 6px!important;border:0!important;border-radius:0!important;font-size:23px!important;}
    html[data-rivo-google-simple] #rivo-google-search :is(button,.voice-search) {display:flex!important;flex:none!important;align-items:center!important;justify-content:center!important;width:56px!important;height:56px!important;min-width:56px!important;min-height:56px!important;padding:12px!important;border:0!important;border-radius:50%!important;text-decoration:none!important;}
    html[data-rivo-google-simple] #rivo-google-search svg {display:block!important;width:28px!important;height:28px!important;flex:none!important;}
    html[data-rivo-google-simple] #rivo-google-search [hidden] {display:none!important;}
    html[data-rivo-google-simple="home"] #rivo-google-search {min-height:calc(var(--rivo-home-height,100dvh) - 40px)!important;display:flex!important;flex-direction:column!important;justify-content:center!important;padding:32px 0!important;}
    html[data-rivo-google-simple] #rivo-google-search nav {display:grid!important;grid-template-columns:repeat(4,minmax(0,1fr))!important;gap:12px!important;max-width:none!important;margin:0!important;}
    html[data-rivo-google-simple] #rivo-google-search .favorite {position:relative!important;display:flex!important;flex-direction:column!important;align-items:center!important;justify-content:flex-start!important;gap:12px!important;width:112px!important;max-width:100%!important;min-width:0!important;min-height:136px!important;padding:16px 8px!important;border:0!important;border-radius:20px!important;text-align:center!important;transition:transform .18s ease,background-color .18s ease!important;}
    html[data-rivo-google-simple] #rivo-google-search .favorite-mark {display:grid!important;place-items:center!important;width:72px!important;height:72px!important;border-radius:24px!important;font-size:30px!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.25),0 8px 20px rgba(0,0,0,.08)!important;font-weight:800!important;line-height:1!important;}
    html[data-rivo-google-simple] #rivo-google-search .favorite-name {display:block!important;width:100%!important;text-align:center!important;font-size:18px!important;font-weight:600!important;line-height:1.5!important;overflow-wrap:anywhere!important;}
    html[data-rivo-google-simple] #rivo-google-search .favorite-host {display:block!important;font-size:13px!important;line-height:1.5!important;opacity:.75!important;overflow-wrap:anywhere!important;}
    html[data-rivo-google-simple] #rivo-google-search .favorite-arrow {position:absolute!important;top:18px!important;right:18px!important;opacity:.5!important;font-size:22px!important;}
    html[data-rivo-google-simple] #rivo-google-search .favorite-mark svg {width:48px!important;height:48px!important;}
    html[data-rivo-google-simple] #rivo-google-search .favorite-mark img {display:block!important;width:48px!important;height:48px!important;object-fit:contain!important;border-radius:10px!important;}
    html[data-rivo-google-simple] #rivo-google-search .favorite-mark[data-site="naver"] {background-color:#03A95C!important;}
    html[data-rivo-google-simple] #rivo-google-search .favorite-mark[data-site="daum"] {background-color:#F0F4FF!important;}
    html[data-rivo-google-simple] #rivo-google-search .favorite-mark[data-site="youtube"] {background-color:#FFF0F0!important;}
    html[data-rivo-google-simple] #rivo-google-search .favorite-mark[data-site="wiki"] {background-color:#F2F1EB!important;}
    html[data-rivo-google-simple] #rivo-google-search .favorite-mark[data-site="wiki"] * {color:#303640!important;-webkit-text-fill-color:#303640!important;}
    html[data-rivo-google-simple] #rivo-google-search .favorite:focus-visible {outline:3px solid currentColor!important;outline-offset:3px!important;}
    @media(hover:hover){html[data-rivo-google-simple] #rivo-google-search .favorite:hover {transform:translateY(-3px)!important;}}
    @media(max-width:480px){html[data-rivo-google-simple] #rivo-google-search nav {grid-template-columns:repeat(2,minmax(0,1fr))!important;}}
    @media(prefers-reduced-motion:reduce){html[data-rivo-google-simple] #rivo-google-search .favorite {transition:none!important;transform:none!important;}}
    html[data-rivo-google-simple] #rivo-google-search .browser-brand {display:block!important;font-size:clamp(38px,6vw,56px)!important;font-weight:600!important;line-height:1.2!important;letter-spacing:-2px!important;margin:0 auto 30px!important;text-align:center!important;}
    html[data-rivo-google-simple] #rivo-google-search .browser-brand-dot {display:inline-block!important;width:8px!important;height:8px!important;margin-left:7px!important;border-radius:50%!important;background-color:currentColor!important;vertical-align:baseline!important;opacity:.75!important;}
    html[data-rivo-google-simple] #rivo-google-search nav {width:100%!important;justify-items:start!important;}
    html[data-rivo-google-simple] #rivo-google-search .favorite-mark[data-site="custom"] {background-color:#E6EF87!important;}
    html[data-rivo-google-simple] #rivo-google-search .favorite-mark[data-site="custom"] * {color:#15233A!important;-webkit-text-fill-color:#15233A!important;}
    html[data-rivo-google-simple] #rivo-google-search .favorite-add .favorite-mark {border:1.5px dashed currentColor!important;background:transparent!important;box-shadow:none!important;}
    html[data-rivo-google-simple] #rivo-google-search .favorite-add svg {width:30px!important;height:30px!important;}
    @media(max-width:360px){html[data-rivo-google-simple] #rivo-google-search :is(button,.voice-search){width:48px!important;height:48px!important;min-width:48px!important;min-height:48px!important;}html[data-rivo-google-simple] #rivo-google-search form{gap:2px!important;}}
    html[data-rivo-google-simple] #rivo-google-search form{gap:4px!important;min-height:88px!important;padding:6px 6px 6px 20px!important;border:1px solid rgba(245,243,233,.7)!important;border-radius:32px!important;}
    html[data-rivo-google-simple] #rivo-google-search input{min-height:64px!important;padding:12px 0!important;font-size:20px!important;}
    html[data-rivo-google-simple] #rivo-google-search input::-webkit-search-cancel-button{display:none!important;-webkit-appearance:none!important;appearance:none!important;}
    /* The rounded form owns the input focus ring. */
    html[data-rivo-google-simple] #rivo-google-search input:is(:focus,:focus-visible){outline:none!important;box-shadow:none!important;}
    html[data-rivo-google-simple] #rivo-google-search button{width:52px!important;height:52px!important;min-width:52px!important;min-height:52px!important;padding:0!important;border:1px solid currentColor!important;}
    html[data-rivo-google-simple] #rivo-google-search .voice-search{width:56px!important;height:56px!important;min-width:56px!important;min-height:56px!important;padding:0!important;}
    html[data-rivo-google-simple] #rivo-google-search button:disabled{opacity:.5!important;}
  `;
  function viewportWidthCSS() {
    if (!config.nativePageZoom) return '';
    // WebKit can retain Google's original containing-block width after pageZoom.
    // Constrain this Google-only layout to the new visible CSS viewport.
    const width = Math.max(1, Math.round(window.innerWidth));
    return `html[data-rivo-google-simple],html[data-rivo-google-simple] body {width:${width}px!important; max-width:${width}px!important; min-width:0!important;}`;
  }
  function theme() {
    const p = config.appearanceEnabled ? (palettes[config.palette] || palettes.dark) : palettes.light;
    return `
      html[data-rivo-google-simple][data-rivo-google-simple][data-rivo-google-simple] body {background:${p.bg}!important; color:${p.text}!important;}
      html[data-rivo-google-simple] [data-rivo-google-ai], html[data-rivo-google-simple] [data-rivo-google-ai] *:not(img):not(svg):not(path):not(video):not(canvas) {color:${p.text}!important; -webkit-text-fill-color:${p.text}!important; background:transparent!important; box-shadow:none!important;}
      html[data-rivo-google-simple] [data-rivo-google-ai] :is(a,button) {color:${p.link}!important; -webkit-text-fill-color:${p.link}!important;}
      html[data-rivo-google-simple] [data-rivo-google-ai] button {background-color:${p.surface}!important; border-color:${p.edge}!important;}
      html[data-rivo-google-simple] :is(#rivo-google-search,#rivo-google-results), html[data-rivo-google-simple] :is(#rivo-google-search,#rivo-google-results) * {background-color:transparent!important; color:${p.text}!important; -webkit-text-fill-color:${p.text}!important; border-color:${p.edge}!important; box-shadow:none!important;}
      html[data-rivo-google-simple] :is(#rivo-google-search,#rivo-google-results) :is(input,a) {background-color:${p.surface}!important;}
      html[data-rivo-google-simple] :is(#rivo-google-search,#rivo-google-results) a, html[data-rivo-google-simple] :is(#rivo-google-search,#rivo-google-results) a strong {color:${p.link}!important; -webkit-text-fill-color:${p.link}!important;}
      html[data-rivo-google-simple] #rivo-google-search button {background-color:${p.link}!important; color:${p.surface}!important; -webkit-text-fill-color:${p.surface}!important; border-color:${p.link}!important;}
      html[data-rivo-google-simple] #rivo-google-search input,html[data-rivo-google-simple] #rivo-google-search .voice-search {background-color:transparent!important;color:${p.text}!important;-webkit-text-fill-color:${p.text}!important;}
      html[data-rivo-google-simple] #rivo-google-search button * {color:${p.bg}!important;-webkit-text-fill-color:${p.bg}!important;}
      html[data-rivo-google-simple] #rivo-google-search button[type="submit"] :is(svg,svg *) {stroke:${p.bg}!important;}
      html[data-rivo-google-simple] #rivo-google-search .favorite-mark * {color:${p.link}!important;-webkit-text-fill-color:${p.link}!important;}
      html[data-rivo-google-simple] #rivo-google-search .favorite {background-color:transparent!important;color:${p.text}!important;-webkit-text-fill-color:${p.text}!important;}
      html[data-rivo-google-simple] #rivo-google-search .favorite-mark {background-color:${p.bg}!important;color:${p.link}!important;-webkit-text-fill-color:${p.link}!important;}
      html[data-rivo-google-simple] #rivo-google-search form{background-color:${config.appearanceEnabled&&config.palette==='home'?'rgba(16,16,16,.75)':p.surface}!important;color:${p.text}!important;border-color:${config.appearanceEnabled&&config.palette==='home'?'rgba(245,243,233,.7)':p.edge}!important;}
      html[data-rivo-google-simple] #rivo-google-search input,html[data-rivo-google-simple] #rivo-google-search .voice-search,html[data-rivo-google-simple] #rivo-google-search .voice-search *{color:${p.text}!important;-webkit-text-fill-color:${p.text}!important;}
      html[data-rivo-google-simple] #rivo-google-search input::placeholder{color:${p.text}!important;opacity:1!important;}
      html[data-rivo-google-simple] #rivo-google-search button{border-color:${p.text}!important;}
      html[data-rivo-google-simple] #rivo-google-search form:focus-within{border-color:${p.text}!important;box-shadow:inset 0 0 0 1px ${p.text}!important;}
      html[data-rivo-google-simple] [data-rivo-google-ai] [data-rivo-google-source] {background-color:${config.palette==='contrast'?'transparent':'rgba(128,128,128,.08)'}!important;box-shadow:none!important;}
      html[data-rivo-google-simple] [data-rivo-google-ai] [data-rivo-google-source] :is(a,a *,strong) {color:${p.text}!important;-webkit-text-fill-color:${p.text}!important;background:transparent!important;}
      html[data-rivo-google-simple] [data-rivo-google-ai] :is(a,button):focus-visible {outline:3px solid ${p.link}!important;outline-offset:3px!important;}
      html[data-rivo-google-simple] #rivo-google-results .result-link,html[data-rivo-google-simple] #rivo-google-results .result-link * {background:transparent!important;color:${p.text}!important;-webkit-text-fill-color:${p.text}!important;box-shadow:none!important;}
      html[data-rivo-google-simple] #rivo-google-results li:not(:last-child)::after {background:${p.edge}!important;}

    `;
  }
  const text = () => strings[config.language] || strings.ko;
  function node(tag, content) {
    const element = document.createElement(tag);
    if (content) element.textContent = content;
    return element;
  }
  function destination(value) {
    try {
      let url = new URL(value, location.href);
      if (url.origin === location.origin && ['/url', '/goto'].includes(url.pathname)) {
        const target = url.searchParams.get('q') || url.searchParams.get('url') || '';
        if (/^https?:\/\//i.test(target)) url = new URL(target);
        // Google also signs opaque destination tokens. Preserve that original
        // HTTPS redirect instead of treating its token as a destination URL.
        else return /^[A-Za-z0-9_+=/-]+$/.test(target) ? url : null;
      }
      if (!['https:', 'http:'].includes(url.protocol)) return null;
      if (/^(.*\.)?google\.(com|co\.kr)$/i.test(url.hostname) && url.pathname !== '/translate') return null;
      return url;
    } catch (_) { return null; }
  }
  function route() {
    const url = new URL(location.href);
    if (url.pathname === '/' || url.pathname === '/webhp') return 'home';
    if (url.pathname === '/search' && !url.searchParams.has('tbm') && (!url.searchParams.has('udm') || url.searchParams.get('udm') === '14')) return 'results';
    return '';
  }
  function blocked() {
    // Never cover verification, consent, or an active Google dialog.
    const candidates = [...document.querySelectorAll('#captcha-form, #recaptcha, form[action*="consent.google"], [role="dialog"][aria-modal="true"]')];
    if (!candidates.length) return false;
    // Google preloads hidden feedback dialogs. Measure their original layout,
    // since our simple-view stylesheet hides unrelated page elements itself.
    const root = document.documentElement;
    const mode = root.getAttribute('data-rivo-google-simple');
    if (mode) root.removeAttribute('data-rivo-google-simple');
    const visible = candidates.some(element => !element.closest('[hidden], [aria-hidden="true"]') && element.getClientRects().length > 0 && getComputedStyle(element).visibility !== 'hidden');
    if (mode) root.setAttribute('data-rivo-google-simple', mode);
    return visible;
  }
  function resetMarks(nextKeep) {
    const nextPaths = new Set();
    nextKeep.forEach(element => {
      for (let parent = element.parentElement; parent && parent !== document.body; parent = parent.parentElement) nextPaths.add(parent);
    });
    keep.forEach(element => { if (!nextKeep.has(element)) element.removeAttribute('data-rivo-google-keep'); });
    paths.forEach(element => { if (!nextPaths.has(element)) element.removeAttribute('data-rivo-google-path'); });
    nextKeep.forEach(element => { if (!keep.has(element)) element.setAttribute('data-rivo-google-keep', ''); });
    nextPaths.forEach(element => { if (!paths.has(element)) element.setAttribute('data-rivo-google-path', ''); });
    keep = nextKeep; paths = nextPaths;
  }
  function setViewport() {
    if (!viewport) {
      viewport = document.querySelector('meta[name="viewport"]');
      createdViewport = !viewport;
      if (!viewport) { viewport = node('meta'); viewport.name = 'viewport'; (document.head || document.documentElement).append(viewport); }
      originalViewport = viewport.getAttribute('content');
    }
    // Google's basic response omits an initial scale on some devices, causing
    // WebKit's automatic fit-to-width to cancel native pageZoom. Explicit scale
    // matches ordinary responsive pages; pinch zoom remains available.
    if (viewport.content !== 'width=device-width,initial-scale=1') viewport.content = 'width=device-width,initial-scale=1';
  }
  function restore() {
    if (viewport) {
      if (createdViewport) viewport.remove();
      else if (originalViewport === null) viewport.removeAttribute('content');
      else viewport.setAttribute('content', originalViewport);
      viewport = null; originalViewport = null; createdViewport = false;
    }
    document.documentElement?.removeAttribute('data-rivo-google-simple');
    resetMarks(new Set());
    header?.remove(); results?.remove();
    clearSourceMarks();
    if (ai) ai.removeAttribute('data-rivo-google-ai');
    ai = null; header = null; results = null; signature = ''; currentRoute = '';
    clearTimeout(fallbackTimer);
  }
  function makeHeader(kind) {
    const s = text();
    header = node('section'); header.id = 'rivo-google-search'; header.setAttribute('data-rivo-google-ui', '');
    const form = node('form'); form.method = 'get'; form.action = '/search'; form.setAttribute('role', 'search');
    input = node('input'); input.type = 'search'; input.name = 'q'; input.placeholder = s.search; input.setAttribute('aria-label', s.search);
    input.value = new URL(location.href).searchParams.get('q') || '';
    input.autocomplete = 'off';
    const icon=(paths)=>{
      const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');
      for(const [key,value]of Object.entries({viewBox:'0 0 24 24',fill:'none',stroke:'currentColor','stroke-width':'1.8','stroke-linecap':'round','stroke-linejoin':'round','aria-hidden':'true',focusable:'false'}))svg.setAttribute(key,value);
      for(const d of paths){const path=document.createElementNS(svg.namespaceURI,'path');path.setAttribute('d',d);svg.appendChild(path);}return svg;
    };
    const submit=node('button');submit.type='submit';submit.setAttribute('aria-label',s.go);submit.appendChild(icon(['M12 19V5','M5 12l7-7 7 7']));submit.hidden=input.value.length===0;submit.disabled=!input.value.trim();
    input.addEventListener('input',()=>{submit.hidden=input.value.length===0;submit.disabled=!input.value.trim();});
    const voice=node('a');voice.href='rivo-browser://voice';voice.className='voice-search';voice.setAttribute('role','button');voice.setAttribute('aria-label',s.voice);voice.appendChild(icon(['M9 5a3 3 0 0 1 6 0v7a3 3 0 0 1-6 0z','M5 10v2a7 7 0 0 0 14 0v-2','M12 19v3','M8 22h8']));
    voice.addEventListener('keydown',event=>{if(event.key===' '){event.preventDefault();voice.click();}});
    const error=node('p');error.setAttribute('role','status');error.hidden=true;
    form.addEventListener('submit',event=>{
      event.preventDefault();const value=input.value.trim();if(!value)return;
      let destination;
      try{
        const hostWithPort=/^(?:localhost|[^/\s:]+\.[^/\s:]+):[0-9]+(?:[/?#]|$)/.test(value);
        if(/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(value)&&!hostWithPort){destination=new URL(value);if(!['https:','http:'].includes(destination.protocol))throw new Error();}
        else if(!/\s/.test(value)&&(value.includes('.')||hostWithPort))destination=new URL('https://'+value);
        else {destination=new URL('/search',location.origin);destination.searchParams.set('q',value);}
        if(!destination.hostname)throw new Error();if(destination.protocol==='http:')destination.protocol='https:';
        location.assign(destination.href);
      }catch(_){error.textContent=s.invalid;error.hidden=false;}
    });
    if(kind==='home'){
      const brand=node('h1','Browser');brand.className='browser-brand';
      const dot=node('span');dot.className='browser-brand-dot';dot.setAttribute('aria-hidden','true');brand.appendChild(dot);header.appendChild(brand);
      header.style.setProperty('--rivo-home-height',`${Math.round(window.visualViewport?.height||window.innerHeight)}px`);
    }
    form.append(input,submit,voice);header.append(form,error);
    if(kind==='home'){
      const heading=node('h2',s.favorites);heading.id='rivo-google-favorites-title';
      const nav=node('nav');nav.setAttribute('aria-labelledby',heading.id);
      [[s.naver,'https://www.naver.com','N'],[s.daum,'https://www.daum.net','D'],[s.youtube,'https://www.youtube.com','play'],[s.wiki,`https://${config.language==='ja'?'ja':config.language==='en'?'en':'ko'}.wikipedia.org`,'W']].concat((config.favorites||[]).filter(item=>typeof item?.name==='string'&&/^https:\/\//.test(item?.url||'')).slice(0,24).map(item=>[item.name,item.url,'custom',item.icon])).forEach(([label,href,glyph,siteIcon])=>{
        const link=node('a');link.href=href;link.className='favorite';link.setAttribute('aria-label',label);
        const mark=node('span');mark.className='favorite-mark';mark.setAttribute('aria-hidden','true');mark.setAttribute('data-rivo-web-preserve','');
        const site={N:'naver',D:'daum',play:'youtube',W:'wiki'}[glyph]||'custom';mark.setAttribute('data-site',site);
        const art=document.createElementNS('http://www.w3.org/2000/svg','svg');art.setAttribute('viewBox','0 0 48 48');art.setAttribute('aria-hidden','true');art.setAttribute('focusable','false');
        const part=(tag,attrs)=>{const shape=document.createElementNS(art.namespaceURI,tag);for(const [key,value]of Object.entries(attrs))shape.setAttribute(key,value);art.appendChild(shape);return shape;};
        if(site==='naver')part('path',{d:'M9 10h9l12 17V10h9v28h-9L18 21v17H9z',fill:'#FFFFFF'});
        if(site==='daum'){
          part('path',{d:'M10 9h12a15 15 0 0 1 0 30H10V9zm8 8v14h4a7 7 0 0 0 0-14h-4z',fill:'#397AF2','fill-rule':'evenodd'});
          part('circle',{cx:'35',cy:'12',r:'6',fill:'#FFBA63'});part('circle',{cx:'12',cy:'35',r:'4',fill:'#FF827B'});
        }
        if(site==='youtube'){
          part('rect',{x:'4',y:'10',width:'40',height:'28',rx:'9',fill:'#F04C55'});
          part('path',{d:'M21 17l12 7-12 7z',fill:'#FFFFFF'});
        }
        if(site==='wiki'){
          part('circle',{cx:'24',cy:'24',r:'19',fill:'none',stroke:'#A8ACB3','stroke-width':'1.4'});
          part('path',{d:'M6 17h36M6 31h36M24 5c-11 10-11 28 0 38M24 5c11 10 11 28 0 38',fill:'none',stroke:'#C3C7CD','stroke-width':'1.2'});
          const letter=part('text',{x:'24',y:'34','text-anchor':'middle','font-family':'Georgia,serif','font-size':'29','font-weight':'600',fill:'#303640'});letter.textContent='W';
        }
        if(site==='custom'){const letter=part('text',{x:'24',y:'34','text-anchor':'middle','font-size':'29','font-weight':'650',fill:'#15233A'});letter.textContent=Array.from(label.trim())[0]?.toUpperCase()||'•';}
        mark.appendChild(art);
        if(site==='custom'&&typeof siteIcon==='string'&&siteIcon.length<100000&&/^data:image\/png;base64,[A-Za-z0-9+/]+=*$/.test(siteIcon)){
          const image=node('img');image.alt='';image.setAttribute('aria-hidden','true');image.setAttribute('data-rivo-web-preserve','');
          image.style.setProperty('display','none','important');
          image.onload=()=>{image.style.setProperty('display','block','important');art.hidden=true;art.style.setProperty('display','none','important');};
          image.onerror=()=>{image.remove();art.hidden=false;art.style.removeProperty('display');};
          image.src=siteIcon;mark.appendChild(image);
        }
        const name=node('span',label);name.className='favorite-name';name.setAttribute('aria-hidden','true');
        const host=node('span',new URL(href).hostname.replace(/^www\./,''));host.className='favorite-host';host.setAttribute('aria-hidden','true');
        const arrow=node('span','↗');arrow.className='favorite-arrow';arrow.setAttribute('aria-hidden','true');
        link.append(mark,name);nav.append(link);
      });
      const add=node('a');add.className='favorite favorite-add';add.href='rivo-browser://add-favorite';add.setAttribute('aria-label',s.addFavorite);add.setAttribute('role','button');add.addEventListener('keydown',event=>{if(event.key===' '){event.preventDefault();add.click();}});
      const mark=node('span');mark.className='favorite-mark';mark.setAttribute('aria-hidden','true');mark.appendChild(icon(['M12 5v14','M5 12h14']));
      const label=node('span',s.add);label.className='favorite-name';label.setAttribute('aria-hidden','true');add.append(mark,label);nav.appendChild(add);
      header.append(heading,nav);
    }
    document.body.prepend(header);
    if (kind === 'results') {
      results = node('section'); results.id = 'rivo-google-results'; results.setAttribute('data-rivo-google-ui', '');
      const heading = node('h2', s.sites);
      status = node('p', s.loading); status.setAttribute('role', 'status');
      list = node('ol'); list.setAttribute('aria-label', s.sites);
      results.append(heading, status, list); document.body.append(results);
    }
  }
  function findAI() {
    const headings = document.querySelectorAll('h2, [role="heading"], #main span');
    const heading = Array.from(headings).find(element => /^(AI 개요|AI 요약|AI Overview|AI による概要|AIによる概要)$/i.test(element.textContent.trim()));
    if (!heading) return null;
    // Keep the live section, including its citations and expand button. Never
    // label an ordinary snippet as AI or invent a summary when Google omits it.
    const basic = heading.closest('.Gx5Zad, .CKgc1d');
    if (basic) return basic;
    const section = heading.closest('section, [data-scope-id="turn"]');
    if (section && section !== document.body && !section.querySelector('#rso')) {
      return section.closest('section') || section;
    }
    return null;
  }

  function clearSourceMarks() {
    sourceMarks.forEach((names, element) => names.forEach(name => element.removeAttribute(name)));
    sourceMarks.clear();
    sourceAccessibility.forEach((attributes,element)=>attributes.forEach((value,name)=>{
      if(value===null)element.removeAttribute(name);else element.setAttribute(name,value);
    }));
    sourceAccessibility.clear();
  }
  function formatSources(section) {
    if (!section) { clearSourceMarks(); return; }
    const next = new Map(), regions = new Set();
    const mark = (element, name) => { if (!next.has(element)) next.set(element,new Set()); next.get(element).add(name); };
    const external = element => [...element.querySelectorAll('a[href]')].map(link => ({link,url:destination(link.getAttribute('href'))}))
      .filter(({link,url}) => url && !link.closest('sup,button,[role="button"]') && ((link.textContent.trim()||link.getAttribute('aria-label')||'').length > 4 || link.querySelector('img,h3,h4,[role="heading"]')));
    const isCard = element => {
      const content=element.textContent.trim();
      if(element.matches('a[href]')&&destination(element.getAttribute('href')))return (content||element.getAttribute('aria-label')||'').trim().length>4;
      const links=external(element);
      // Google often places an empty, named link over a sibling title/image.
      // Such list items are cards even though the anchor has no text children.
      if(element.matches('[role="listitem"],g-inner-card,[data-src-id]'))return links.length>0;
      return links.some(({link})=>link.querySelector('img,h3,h4,[role="heading"]') || link.textContent.trim().length>=Math.max(5,content.length*.5));
    };
    section.querySelectorAll('g-scrolling-carousel,[role="list"],[aria-roledescription="carousel"]').forEach(element => {
      if (external(element).length && (element.matches('g-scrolling-carousel,[aria-roledescription="carousel"]') || [...element.children].filter(isCard).length>=2)) regions.add(element);
    });
    external(section).forEach(({link}) => {
      for (let parent=link.parentElement,depth=0;parent&&parent!==section&&depth<7;parent=parent.parentElement,depth++) {
        const children=[...parent.children].filter(child=>isCard(child) || (child.matches('a[href]')&&destination(child.getAttribute('href'))));
        const targets=new Set(children.flatMap(child=>child.matches('a[href]')?[destination(child.getAttribute('href'))?.href]:external(child).map(item=>item.url.href)).filter(Boolean));
        const layout=getComputedStyle(parent);
        if(!parent.matches('[role="listitem"],g-inner-card')&&children.length>=2&&targets.size>=2&&(/flex|grid/.test(layout.display)||/auto|scroll|hidden|clip/.test(layout.overflowX)||children.length===parent.children.length)) regions.add(parent);
      }
    });
    // Pick the actual row of cards rather than an outer carousel/summary wrapper.
    const rows=[...regions].filter(region=>![...regions].some(other=>other!==region&&region.contains(other)));
    rows.forEach(region=>{
      mark(region,'data-rivo-google-sources');
      for(let parent=region;parent&&parent!==section;parent=parent.parentElement)mark(parent,'data-rivo-google-source-path');
      [...region.children].forEach(child=>{
        if(external(child).length||(child.matches('a[href]')&&destination(child.getAttribute('href')))){
          mark(child,'data-rivo-google-source');
          external(child).forEach(({link})=>{
            if(!link.textContent.trim()&&link.getAttribute('aria-label')&&getComputedStyle(link).position==='absolute'){
              mark(link,'data-rivo-google-source-overlay');
              // Release fixed-width card shells without moving/replacing live links.
              for(let frame=link.parentElement;frame&&frame!==child;frame=frame.parentElement)mark(frame,'data-rivo-google-source-frame');
            }
          });
        }
        else if(child.matches('button,[role="button"]')&&/next|previous|이전|다음|前|次/i.test(child.getAttribute('aria-label')||child.textContent))mark(child,'data-rivo-google-source-nav');
      });
      if(region.scrollLeft)region.scrollLeft=0;
    });
    sourceMarks.forEach((names,element)=>names.forEach(name=>{if(!next.get(element)?.has(name))element.removeAttribute(name);}));
    next.forEach((names,element)=>names.forEach(name=>{if(!element.hasAttribute(name))element.setAttribute(name,'');}));
    sourceMarks=next;
    const cards=[...next].filter(([,names])=>names.has('data-rivo-google-source')).map(([element])=>element);
    // Carousel-only hidden/focus flags no longer apply once every card is in the visible grid.
    const retain=new Set();
    const expose=element=>{
      retain.add(element);
      const restore=sourceAccessibility.get(element)||new Map();
      for(const name of ['aria-hidden','inert','tabindex']){
        const value=element.getAttribute(name);
        if((name==='aria-hidden'&&value==='true')||(name==='inert'&&value!==null)||(name==='tabindex'&&element.matches('a[href]')&&value==='-1')){
          if(!restore.has(name))restore.set(name,value);
          element.removeAttribute(name);
        }
      }
      if(restore.size)sourceAccessibility.set(element,restore);
    };
    cards.forEach(card=>{
      expose(card);
      card.querySelectorAll('a[href],[aria-hidden="true"],[inert]').forEach(element=>{
        if(!element.closest('[role="dialog"],[role="menu"],button')&&(element.matches('a[href]')||element.querySelector('a[href]')))expose(element);
      });
    });
    sourceAccessibility.forEach((attributes,element)=>{
      if(retain.has(element)||cards.some(card=>card.contains(element)))return;
      attributes.forEach((value,name)=>{if(value===null)element.removeAttribute(name);else element.setAttribute(name,value);});
      sourceAccessibility.delete(element);
    });
  }
  function resultSnippet(heading, anchor, root, title, host) {
    const blocks=[];
    for(let block=anchor.parentElement,depth=0;block&&block!==root&&depth<7;block=block.parentElement,depth++) {
      if(block.closest('[data-rivo-google-ai]')||block.querySelector('[data-rivo-google-ai]'))break;
      if(block.querySelectorAll('h3,[role="heading"][aria-level="3"]').length>1)break;
      if(depth<3||block.matches('article,.MjjYud,.Gx5Zad,.tF2Cxc,.g'))blocks.push(block);
      if(!heading.matches('h3,[role="heading"]')&&depth>=2)break;
    }
    const excluded='a,button,[role="button"],h1,h2,h3,h4,h5,h6,[role="heading"],cite,script,style,nav,[hidden],[aria-hidden="true"]';
    const normalize=value=>(value||'').replace(/\s+/g,' ').trim();
    const usable=(value,minimum=8)=>{
      const text=normalize(value);
      return text.length>=minimum&&text!==title&&text!==host&&!/^(Translate this page|이 페이지 번역|검색결과에 관한 정보|このページを訳す)$/i.test(text)?text:'';
    };
    const selectors=['[data-sncf]','.VwiC3b','.aCOpRe','.BNeawe.s3v9rd','.IsZvec','.st','[data-content-feature="1"]'];
    for(const block of blocks) {
      for(const selector of selectors)for(const element of block.querySelectorAll(selector)) {
        if(anchor.contains(element)||element.contains(heading)||element.closest(excluded))continue;
        const text=usable(element.textContent);if(text)return text.slice(0,420);
      }
    }
    // Basic Google responses have few stable classes. Read only text from the bounded result.
    for(const block of blocks) {
      const fragments=[],walker=document.createTreeWalker(block,NodeFilter.SHOW_TEXT);
      while(walker.nextNode()) {
        const parent=walker.currentNode.parentElement;
        if(!parent||parent.closest(excluded)||anchor.contains(parent))continue;
        const text=normalize(walker.currentNode.textContent);
        if(text&&text!==title&&text!==host&&!/^(이 페이지 번역|검색결과에 관한 정보|Translate this page|このページを訳す)$/i.test(text))fragments.push(text);
      }
      const text=usable(fragments.join(' '),20);if(text)return text.slice(0,420);
    }
    return '';
  }
  function updateSites(sites) {
    const remaining=new Map([...list.children].map(item=>[item.dataset.resultHref,item]));
    sites.forEach((site,index)=>{
      let item=remaining.get(site.href);
      if(!item){
        item=node('li');item.dataset.resultHref=site.href;
        const link=node('a');link.className='result-link';
        const host=node('small');host.className='result-host';
        const title=node('strong');title.className='result-title';
        const snippet=node('p');snippet.className='result-snippet';
        link.append(host,title,snippet);item.append(link);
      }
      remaining.delete(site.href);
      const link=item.firstElementChild;link.href=site.href;
      for(const [selector,value]of[['.result-host',site.host],['.result-title',site.title],['.result-snippet',site.snippet]]){
        const element=item.querySelector(selector);if(element.textContent!==value)element.textContent=value;element.hidden=!value;
      }
      if(list.children[index]!==item)list.insertBefore(item,list.children[index]||null);
    });
    remaining.forEach(item=>item.remove());
  }
  function collectSites() {
    const root = document.querySelector('#rso') || document.querySelector('#search') || document.querySelector('#main') || document.body;
    if (!root) return [];
    const seen = new Set(), sites = [];
    const headings = root.querySelectorAll('h3, [role="heading"][aria-level="3"]');
    // Google's basic WebView response uses ordinary title links rather than h3.
    const candidates = headings.length ? headings : root.querySelectorAll('a[href]');
    for (const heading of candidates) {
      if (heading.closest('[data-rivo-google-ui], [data-rivo-google-ai], #tads, #bottomads, [data-text-ad], [data-ad-slot], [data-ad-client], header, footer, nav')) continue;
      const anchor = heading.closest('a[href]') || heading.querySelector('a[href]');
      const url = anchor && destination(anchor.getAttribute('href'));
      const title = heading.textContent.trim();
      if (!url || !title || seen.has(url.href)) continue;
      const redirect = url.origin === location.origin && ['/url', '/goto'].includes(url.pathname);
      const siteLabel = anchor.querySelector('cite, .XR4uSe')?.textContent || anchor.textContent.replace(title, '');
      const shownHost = siteLabel.match(/(?:https?:\/\/)?((?:[a-z0-9-]+\.)+[a-z]{2,})(?:[\s/›]|$)/i)?.[1];
      const host = redirect ? (shownHost || '') : url.hostname.replace(/^www\./, '');
      const snippet=resultSnippet(heading,anchor,root,title,host);
      seen.add(url.href); sites.push({title, href:url.href, host, snippet});
      if (sites.length === 5) break;
    }
    return sites;
  }
  function refresh() {
    timer = null;
    if (!document.body) return;
    const kind = route();
    if (!config.enabled || !kind || blocked()) { restore(); return; }
    // Don't mask unexpected home/consent variants with a fabricated homepage.
    if (kind === 'home' && !document.querySelector('form input[name="q"], form textarea[name="q"]')) { restore(); return; }
    if (!style?.isConnected) { style = node('style'); (document.head || document.documentElement).append(style); }
    const styled = css + theme() + viewportWidthCSS();
    if (style.textContent !== styled) style.textContent = styled;
    const pageURL = new URL(location.href);
    const pageKey = kind + ':' + (pageURL.searchParams.get('q') || '') + ':' + (pageURL.searchParams.get('start') || '0');
    if (currentRoute !== pageKey || !header?.isConnected) {
      restore(); currentRoute = pageKey; makeHeader(kind);
      if (kind === 'results') fallbackTimer = setTimeout(() => {
        // Unknown result markup must remain usable rather than showing a blank list.
        if (!list?.children.length) { config.enabled = false; restore(); }
      }, 12000);
    }
    setViewport();
    const nextAI = kind === 'results' ? findAI() : null;
    if (ai !== nextAI) {
      ai?.removeAttribute('data-rivo-google-ai'); ai = nextAI;
      ai?.setAttribute('data-rivo-google-ai', '');
    }
    if (kind === 'results') {
      const sites = collectSites(), nextSignature = JSON.stringify(sites);
      if (nextSignature !== signature) {
        signature = nextSignature;
        updateSites(sites);
        status.hidden = sites.length > 0;
      }
    }
    // Google can append its AI/main container after our document-start UI.
    // Keep the website list after the live AI section in visual and reading order.
    if (results && document.body.lastElementChild !== results) document.body.append(results);
    resetMarks(new Set([header, ...(results ? [results] : []), ...(ai ? [ai] : [])]));
    document.documentElement.setAttribute('data-rivo-google-simple', kind);
    formatSources(ai);
  }
  function schedule() { if (!timer) timer = setTimeout(refresh, 120); }
  window.__rivoGoogleSimple = {
    set(value) {
      const previousLanguage = config.language;
      const previousFavorites = JSON.stringify(config.favorites||[]);
      const draft = input?.value;
      config = {...config, ...value};
      const favoritesChanged=previousFavorites!==JSON.stringify(config.favorites||[]);
      if (previousLanguage !== config.language || favoritesChanged) restore();
      refresh();
      if(favoritesChanged&&input&&draft!=null){input.value=draft;input.dispatchEvent(new Event('input',{bubbles:true}));}
    }
  };
  const observer = new MutationObserver(records => {
    if (records.some(record => !record.target.closest?.(`${own}, style`) &&
      (record.type === 'attributes' || record.type === 'characterData' || Array.from(record.addedNodes).concat(Array.from(record.removedNodes)).some(n => n !== header && n !== results && n !== style)))) schedule();
  });
  observer.observe(document, {subtree:true, childList:true, characterData:true, attributes:true, attributeFilter:['aria-modal','role']});
  document.addEventListener('DOMContentLoaded', refresh, {once:true});
  window.addEventListener('resize',()=>{if(header)header.style.setProperty('--rivo-home-height',`${Math.round(window.visualViewport?.height||window.innerHeight)}px`);schedule();});
  window.addEventListener('pageshow', schedule); window.addEventListener('popstate', schedule);
  refresh();
})();
"""#
}
#endif
