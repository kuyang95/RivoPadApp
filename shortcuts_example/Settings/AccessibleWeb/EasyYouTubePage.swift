import Foundation

/// Runs in the page world to use the official YouTube IFrame API; never exposes native data.
enum EasyYouTubePage {
    static let home = "https://m.youtube.com/"
    static let closeURL = "rivo-easy-youtube://close"
    static let storeIdentifier = UUID(uuidString: "6492E698-D7FC-4721-9F45-A2EC60B94889")!
    static let source = #"""
// Debug Easy YouTube: shared by Android and iPad. No native data/credential bridge.
// Keep Google's own controls and submission handlers; only simplify known login steps.
(() => {
  'use strict';
  if (window.top !== window || location.hostname !== 'accounts.google.com' || window.__rivoGoogleLoginInstalled) return;
  window.__rivoGoogleLoginInstalled = true;
  const css = `
    html[data-rivo-google-login-preparing] body { visibility:hidden!important }
    html[data-rivo-google-login] [role="progressbar"] { position:fixed!important;left:50%!important;top:calc(var(--rivo-google-login-height,100vh) / 2)!important;right:auto!important;bottom:auto!important;transform:translate(-50%,-50%)!important;width:240px!important;max-width:70vw!important;margin:0!important;z-index:2147483600!important;pointer-events:none!important }
    html[data-rivo-google-login] body { display:flex!important;flex-direction:column!important;align-items:center!important;justify-content:center!important;min-height:var(--rivo-google-login-height,100vh)!important;margin:0!important;box-sizing:border-box!important }
    html[data-rivo-google-login] body > iframe[width="0"][height="0"] { border:0!important }
    html[data-rivo-google-login] .X9monf { flex:0 0 auto!important;width:100%!important;max-width:624px!important }
    html[data-rivo-google-login] main > .zIgDIc { text-align:center!important }
    html[data-rivo-google-login] main > .zIgDIc > c-wiz { display:flex!important;justify-content:center!important }
    html[data-rivo-google-login] #headingText,
    html[data-rivo-google-login] #headingSubtext { text-align:center!important }
    html[data-rivo-google-login] [data-rivo-login-secondary],
    html[data-rivo-google-login] footer,
    html[data-rivo-google-login] button[jsname="Cuz2Ue"],
    html[data-rivo-google-login] .RDsYTb,
    html[data-rivo-google-login] [jsname="FIbd0b"] { display:none!important }
    html[data-rivo-google-login] main { display:flex!important;flex-direction:column!important;align-items:stretch!important;gap:28px!important;width:100%!important;max-width:560px!important;margin:0 auto!important;box-sizing:border-box!important }
    html[data-rivo-google-login] main > .zIgDIc,
    html[data-rivo-google-login] main > .UXFQgc { width:100%!important;flex-basis:auto!important;max-width:none!important;padding:0!important;margin:0!important }
    html[data-rivo-google-login] .qWK5J,
    html[data-rivo-google-login] .xKcayf { width:100%!important;min-width:0!important }
    html[data-rivo-google-login] .O1Slxf { width:100%!important;min-width:0!important;justify-content:flex-end!important;margin-top:0!important }
    html[data-rivo-google-login] .TcuCfd { padding:32px 24px!important }
    html[data-rivo-google-login] main > .JYXaTc { width:100%!important;margin:0!important;padding:0!important;align-self:stretch!important }
    html[data-rivo-google-login] .O1Slxf { flex-direction:row!important }
    html[data-rivo-google-login] .FO2vFd:has([jsname="FIbd0b"]) { display:none!important }
    html[data-rivo-google-login] .TNTaPb,
    html[data-rivo-google-login] #identifierNext,
    html[data-rivo-google-login] #passwordNext { width:100%!important;margin:0!important;padding:0!important }
    html[data-rivo-google-login] #identifierNext > div,
    html[data-rivo-google-login] #passwordNext > div,
    html[data-rivo-google-login] #identifierNext button,
    html[data-rivo-google-login] #passwordNext button { width:100%!important }
    html[data-rivo-google-login] #headingText { font-size:32px!important;line-height:1.3!important }
    html[data-rivo-google-login] #identifierId,
    html[data-rivo-google-login] input[name="Passwd"] { font-size:22px!important }
    html[data-rivo-google-login] #identifierNext button,
    html[data-rivo-google-login] #passwordNext button { min-height:64px!important;min-width:144px!important;font-size:22px!important }
    html[data-rivo-google-login] :is(input,button):focus-visible { outline:3px solid #0b57d0!important;outline-offset:4px!important }
  `;
  let waitingForDOM = document.readyState === 'loading';
  const pathMode = () => /\/(?:v3\/signin|signin\/v2)\/identifier\/?$/.test(location.pathname) ? 'identifier'
    : /\/(?:v3\/signin|signin\/v2)\/challenge\/pwd\/?$/.test(location.pathname) ? 'password' : null;
  const sizeViewport = () => {
    const height = Math.max(1, Math.round(window.visualViewport?.height || window.innerHeight)) + 'px';
    if (document.documentElement.style.getPropertyValue('--rivo-google-login-height') !== height)
      document.documentElement.style.setProperty('--rivo-google-login-height', height);
  };
  const visible = element => !!element && element.getClientRects().length > 0 && getComputedStyle(element).visibility !== 'hidden';
  const update = () => {
    let style = document.getElementById('rivo-google-login-style');
    if (!style) {
      style = document.createElement('style');style.id = 'rivo-google-login-style';style.textContent = css;
      (document.head || document.documentElement).appendChild(style);
    }
    if (waitingForDOM) {
      const mode = pathMode();
      if (mode) {
        sizeViewport();
        document.documentElement.setAttribute('data-rivo-google-login', mode);
        document.documentElement.setAttribute('data-rivo-google-login-preparing', '');
      }
      return;
    }
    document.documentElement.removeAttribute('data-rivo-google-login-preparing');
    const identifier = pathMode() === 'identifier' && visible(document.getElementById('identifierId')) && document.getElementById('identifierNext');
    const password = pathMode() === 'password' && visible(document.querySelector('input[name="Passwd"]')) && document.getElementById('passwordNext');
    const extraCheck = [...document.querySelectorAll('[role="dialog"],[role="alertdialog"],#ca,iframe[src*="recaptcha"]')].some(visible);
    const mode = !extraCheck && document.querySelector('main #headingText') ? (identifier ? 'identifier' : password ? 'password' : null) : null;
    if (mode) {
      for (const link of document.querySelectorAll('button,a,[role="button"]')) {
        if (/^(비밀번호를 잊으셨나요\??|Forgot password\??|パスワードをお忘れの場合)$/i.test(link.textContent.trim()))
          link.setAttribute('data-rivo-login-secondary', '');
      }
      sizeViewport();
      document.documentElement.setAttribute('data-rivo-google-login', mode);
    }
    else document.documentElement.removeAttribute('data-rivo-google-login');
  };
  let scheduled = false;
  const schedule = () => { if (!scheduled) { scheduled = true;queueMicrotask(() => { scheduled = false;update(); }); } };
  const start = () => {
    if (!document.documentElement) { document.addEventListener('readystatechange', start, {once:true});return; }
    update();
    if (waitingForDOM) {
      const finish = () => { waitingForDOM = false;clearTimeout(timeout);update(); };
      const timeout = setTimeout(finish, 10000);
      document.addEventListener('DOMContentLoaded', finish, {once:true});
    }
    new MutationObserver(schedule).observe(document.documentElement, {subtree:true,childList:true,attributes:true,attributeFilter:['hidden','aria-hidden','type','class','style']});
    window.addEventListener('popstate', schedule);
    window.addEventListener('hashchange', schedule);
    window.addEventListener('resize', schedule);
    window.visualViewport?.addEventListener('resize', schedule);
  };
  start();
})();
(() => {
  'use strict';
  if(window.top!==window || !['m.youtube.com','www.youtube.com','youtube.com'].includes(location.hostname) || (location.pathname.startsWith('/embed/')||location.pathname==='/signin'))return;
  if(window.__rivoEasyYouTubeInstalled)return;
  window.__rivoEasyYouTubeInstalled=true;
  const install=()=>{
  const rivoTheme=window.__rivoWebTheme||{bg:'#101C2D',surface:'#1C2D43',text:'#F5F3E9',edge:'#7F93AB',link:'#E6EF87',scheme:'dark'};
  const themeCSS=`--bg:${rivoTheme.bg};--surface:${rivoTheme.surface};--text:${rivoTheme.text};--muted:${rivoTheme.text};--accent:${rivoTheme.link};--soft:${rivoTheme.surface};--border:${rivoTheme.edge};--on-accent:${rivoTheme.bg}`;

(() => {
  'use strict';
  // Development prototype. Playback uses the public YouTube IFrame Player API.
  // No media extraction, credentials, cookies, or resolver service are used here.
  window.__rivoOfficialPlayer?.close();
  const element = (tag, attrs = {}, children = []) => {
    const node = document.createElement(tag);
    for (const [name, value] of Object.entries(attrs)) node.setAttribute(name, String(value));
    for (const child of children) node.appendChild(typeof child === 'string' ? document.createTextNode(child) : child);
    return node;
  };
  let closeCurrent = null, activePlayer = null, changeShort = null, prepareShort = null;
  const originalAction = fn => { const old=document.body.inert;document.body.inert=false;try{return fn();}finally{document.body.inert=old;} };
  const channelURL = value => {
    try { const u=new URL(value,location.href);if(!['m.youtube.com','www.youtube.com','youtube.com'].includes(u.hostname))return null;
      const base=u.pathname.match(/^\/(?:@[^/]+|channel\/[^/]+|c\/[^/]+|user\/[^/]+)/)?.[0];return base?`https://m.youtube.com${base}/videos`:null;
    } catch(_){return null;}
  };
  const commentThreads = () => [...document.querySelectorAll('ytm-comment-thread-renderer,ytd-comment-thread-renderer,yt-comment-thread-view-model')];
  const openComments = () => {
    const button=[...document.querySelectorAll('yt-video-metadata-carousel-view-model[role="button"],button[aria-label],[role="button"][aria-label]')]
      .find(e=>/댓글|comments/i.test(e.getAttribute('aria-label')||'')&&!/추가|작성|답글|reply|add/i.test(e.getAttribute('aria-label')||''));
    if(button){originalAction(()=>button.click());return true;}return false;
  };
  const moreComments = () => {
    const last=commentThreads().at(-1);
    if(!last){openComments();return;}
    let scroller=last.parentElement;
    while(scroller&&!(scroller.scrollHeight>scroller.clientHeight+20&&/auto|scroll/.test(getComputedStyle(scroller).overflowY)))scroller=scroller.parentElement;
    originalAction(()=>{
      if(scroller)scroller.scrollTop=scroller.scrollHeight;
      else window.scrollTo({top:document.documentElement.scrollHeight,behavior:'instant'});
    });
  };
  const avatarURL = value => {
    try {const url=new URL(value,location.href);return url.protocol==='https:' && /(^|\.)(ggpht\.com|googleusercontent\.com|ytimg\.com)$/.test(url.hostname)?url.href:null;}catch(_){return null;}
  };
  // Total counts come from YouTube headers or the current watch page's public data.
  const commentCountText=value=>{
    if(typeof value==='number')value=String(value);
    if(typeof value!=='string')return '';
    const count=value.replace(/[\u00a0\u202f]/g,' ').match(/(?:^|[^\d])([0-9]+(?:[,.][0-9]+)*(?: [0-9]{3})*(?:\s*[천만억万億KMBkmb])?)/)?.[1];
    return count?`${count.trim()}개`:'';
  };
  const youtubeText=value=>typeof value==='string'?value:typeof value==='number'?String(value):value?.simpleText||value?.content||(value?.runs||[]).map(run=>run.text||'').join('');
  let countDataSource=null,countDataVideo='',countDataValue='',countDataReadAt=0;
  const readPageCommentCount=()=>{
    const source=window.ytInitialData,video=new URLSearchParams(location.search).get('v')||'';
    if(!source||!video)return '';
    if(source===countDataSource&&video===countDataVideo&&(countDataValue||Date.now()-countDataReadAt<2000))return countDataValue;
    countDataSource=source;countDataVideo=video;countDataValue='';countDataReadAt=Date.now();
    try{
      if(typeof source==='string'&&source.length>2000000)return '';
      const data=typeof source==='string'?JSON.parse(source):source;
      const sourceVideo=data?.currentVideoEndpoint?.watchEndpoint?.videoId;
      if(sourceVideo&&sourceVideo!==video)return '';
      // Current mobile watch pages publish the total in the comments panel header.
      for(const entry of data.engagementPanels||[]){
        const panel=entry.engagementPanelSectionListRenderer;
        if(!panel||!/comments/i.test(panel.panelIdentifier||panel.identifier?.tag||''))continue;
        const header=panel.header?.engagementPanelTitleHeaderRenderer;
        const count=commentCountText(youtubeText(header?.contextualInfo||header?.subtitle));
        if(count)return countDataValue=count;
      }
      // The collapsed carousel also contains the total before comments are opened.
      // Inspect only public content renderers, never response context or account data.
      const stack=[data.contents],seen=new WeakSet();let visited=0;
      while(stack.length&&visited++<5000){
        const node=stack.pop();if(!node||typeof node!=='object'||seen.has(node))continue;seen.add(node);
        const title=node.carouselTitleViewModel;
        const header=node.commentsHeaderRenderer||node.commentsEntryPointHeaderRenderer||node.commentsHeaderViewModel;
        let count='';
        if(title&&(title.teaserType==='WATCH_UI_TEASER_TYPE_COMMENT'||/댓글|comments?|コメント/i.test(youtubeText(title.title))))count=commentCountText(youtubeText(title.subtitle));
        if(!count&&header)count=commentCountText(youtubeText(header.countText||header.commentCount||header.commentsCount));
        if(count)return countDataValue=count;
        for(const value of Object.values(node))if(value&&typeof value==='object')stack.push(value);
      }
    }catch(_){/* Keep trying the rendered header while the watch data is arriving. */}
    return '';
  };
  const readTotalCommentCount = () => {
    const headers=document.querySelectorAll('ytd-comments-header-renderer #count,ytm-comments-header-renderer .comment-count,ytm-comments-header-renderer .comment-section-header-count,ytm-comments-header-renderer .comment-section-header-text,ytm-comments-header-renderer h2,ytm-comments-header-renderer,ytm-comments-entry-point-header-renderer,.ytCommentsHeaderViewModelTitle,.ytmCommentsHeaderRendererCommentCount');
    const labels=[...headers].map(node=>node.textContent||'');
    for(const node of document.querySelectorAll('yt-carousel-title-view-model,ytm-carousel-title-view-model,ytm-engagement-panel-title-header-renderer,ytd-engagement-panel-title-header-renderer')){
      if(/댓글|comments?|コメント/i.test(node.textContent||''))labels.push(node.textContent||'');
    }
    for(const node of document.querySelectorAll('yt-video-metadata-carousel-view-model[aria-label],button[aria-label],[role="button"][aria-label]')) {
      const label=node.getAttribute('aria-label')||'';
      if(/댓글|comments?|コメント/i.test(label)&&!/답글|reply|replies|작성|추가|write|add/i.test(label))labels.push(label);
    }
    for(const label of labels){const count=commentCountText(label);if(count)return count;}
    return readPageCommentCount();
  };
  const readDetails = () => {
    const owner=document.querySelector('a.slim-video-owner-icon,ytm-slim-owner-renderer a[href],ytm-video-owner-renderer a[href],#owner #channel-name a,[class*="ChannelBar"] a[href]');
    const nameNode=document.querySelector('.slim-owner-channel-name,.slim-video-owner-name,ytm-slim-owner-renderer .channel-name,#owner #channel-name,[class*="ChannelBar"] [class*="ChannelName"]');
    const label=(nameNode?.textContent||owner?.textContent||owner?.getAttribute('aria-label')||'').trim();
    const channelName=label.replace(/[,，]\s*(?:구독자|[\d.,만천MKB ]+\s*subscribers?|チャンネル登録者).*$/i,'').trim();
    const avatar=owner?.querySelector('img')||document.querySelector('ytm-slim-owner-renderer img,ytm-video-owner-renderer img,#owner #avatar img,[class*="ChannelBar"] img');
    const channelAvatar=avatar?[avatar.currentSrc,avatar.getAttribute('src'),avatar.getAttribute('data-thumb')].map(value=>value?avatarURL(value):null).find(Boolean):null;
    const comments=commentThreads().map(thread=>({
      author:(thread.querySelector('.YtmCommentRendererTitle,#author-text,.ytCommentViewModelAuthorText,.comment-header a')?.textContent||'').trim(),
      text:(thread.querySelector('.YtmCommentRendererText,#content-text,.ytCommentViewModelTextContent,.comment-content')?.textContent||'').trim()
    })).filter(c=>c.text);
    const scope=document.querySelector('ytm-comments-header-renderer,ytd-comments,ytm-engagement-panel');
    const disabled=/댓글.*(?:사용 중지|사용할 수 없)|comments are turned off|コメント.*無効/i.test(scope?.querySelector('ytm-message-renderer,ytd-message-renderer,[class*=disabled]')?.textContent||'');
    return {channelName,channelURL:channelURL(owner?.getAttribute('href')),channelAvatar,comments,disabled,totalCommentCount:readTotalCommentCount()};
  };
  window.__rivoOfficialPlayer = {
    close() { closeCurrent?.(); },
    pause() { activePlayer?.pauseVideo?.(); },
    prepareShortTransition() { prepareShort?.(); },
    state() {
      if (!activePlayer) return null;
      return {state:activePlayer.getPlayerState?.(),time:activePlayer.getCurrentTime?.(),duration:activePlayer.getDuration?.(),rate:activePlayer.getPlaybackRate?.()};
    },
    open({videoId,title,startSeconds=0,short=false,autoplay=false,onChannel,onPrevious,onNext}) {
      if(!/^[\w-]{11}$/.test(videoId||''))throw new Error('올바른 영상 ID가 필요해요.');
      if(typeof window.YT?.Player!=='function')throw new Error('플레이어를 준비하고 있어요.');
      if(short&&changeShort?.({videoId,title,startSeconds,autoplay}))return 'Rivo official Shorts updated';
      closeCurrent?.();
      document.querySelectorAll('video,audio').forEach(media=>media.pause());
      const previousInert=document.body.inert,previousFocus=document.activeElement;
      const host=element('div',{'data-rivo-official-player':'','data-video-id':videoId});
      Object.assign(host.style,{position:'fixed',inset:'0',zIndex:'2147483600'});
      if(short){host.style.opacity='0';host.style.pointerEvents='none';host.inert=true;}
      const root=host.attachShadow({mode:'open'});
      root.appendChild(element('style',{},[`
        :host{color-scheme:dark;${themeCSS};display:block;background:var(--bg);color:var(--text);font:17px/1.5 system-ui,-apple-system,sans-serif}

        ${window.__rivoLauncherEmbedded?':host{background:transparent}':''}
        *{box-sizing:border-box}[hidden]{display:none!important}main{height:100%;overflow:auto;overscroll-behavior:contain;-webkit-overflow-scrolling:touch;padding:12px;display:flex;flex-direction:column;gap:14px;max-width:1400px;margin:auto}main>*{flex-shrink:0}h1{font-size:22px;line-height:1.45;margin:0;overflow-wrap:anywhere}h2{font-size:22px;margin:8px 0}p{margin:0;color:var(--muted)}
        button,select{font:inherit;min-height:56px;padding:12px 18px;border:1px solid var(--border);border-radius:16px;background:var(--surface);color:var(--text)}button{cursor:pointer}button:disabled,select:disabled{opacity:.55}button:focus-visible,select:focus-visible,input:focus-visible{outline:3px solid var(--accent);outline-offset:3px}
        .screen{width:100%;aspect-ratio:16/9;min-height:200px;background:#000;overflow:hidden;border-radius:16px;position:relative;flex:none}.screen.portrait{width:440px;max-width:100%;aspect-ratio:9/16;min-height:360px;align-self:center}.screen iframe{position:absolute;inset:0;width:100%;height:100%;border:0;display:block}.timeline{display:grid;grid-template-columns:minmax(0,1fr) auto;align-items:center;column-gap:12px;row-gap:0}.time{grid-column:1/-1;font-size:16px;font-variant-numeric:tabular-nums;color:var(--muted)}.timeline input{width:100%;min-height:48px;min-width:0;margin:0;accent-color:var(--text)}.short-actions{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px;width:100%;max-width:720px;align-self:center}.short-actions button{min-width:0;border:0;background:var(--surface);overflow-wrap:anywhere}.short-actions[data-loading]{visibility:hidden;pointer-events:none}.screen.portrait{border:0;box-shadow:none}main:focus{outline:none}#speed{min-width:72px;min-height:56px;padding:8px;border:0;border-radius:8px;background:transparent;font-size:21px;font-weight:600;cursor:pointer}#channel{display:flex;align-items:center;gap:14px;width:100%;min-height:80px;padding:10px 0 16px;border:0;border-radius:0;background:transparent;text-align:start;overflow-wrap:anywhere}.channel-copy{display:flex;flex:1;min-width:0;flex-direction:column;gap:4px}.channel-name{font-size:23px;font-weight:700;line-height:1.4}.channel-hint{font-size:14px;font-weight:450;line-height:1.5;color:var(--muted)}.channel-arrow{flex:none;font-size:32px;font-weight:400;color:var(--muted)}.channel-avatar{width:52px;height:52px;flex:none;object-fit:cover;border:0;border-radius:50%}.comment-section{display:grid;gap:22px;margin-top:18px}.comment-heading{display:flex;align-items:baseline;gap:12px;flex-wrap:wrap}.comment-heading h2{margin:0;font-size:18px;font-weight:650}.comment-heading #comment-status{margin:0;font-size:14px}.comments{display:grid;gap:30px}.comment{display:flex;flex-direction:column;gap:10px;padding:0;background:transparent;border:0;border-radius:0;overflow-wrap:anywhere}.comment-author{display:flex;align-items:baseline;gap:8px;color:var(--muted);font-size:14px;line-height:1.5}.comment strong{font-size:14px;font-weight:500}.comment p{margin:0;color:var(--text);white-space:pre-wrap;font-size:20px;line-height:1.7}#status:empty{display:none}#comment-status{min-height:1.5em}#more-comments{align-self:flex-start;justify-self:start;min-height:56px;padding:8px 0;border:0;border-radius:0;background:transparent;font-weight:650;text-decoration:underline;text-underline-offset:5px}

      `]));
      const main=element('main',{role:'dialog','aria-modal':'true','aria-labelledby':'official-title',tabindex:'-1'});
      const screen=element('div',{class:short?'screen portrait':'screen'}),target=element('div');screen.appendChild(target);
      const heading=element('h1',{id:'official-title'},[title||'YouTube 동영상']);
      heading.hidden=short;if(short){main.removeAttribute('aria-labelledby');main.setAttribute('aria-label','YouTube 쇼츠');}
      const time=element('span',{id:'time',class:'time'},['0:00 / 0:00']);
      const seek=element('input',{id:'seek',type:'range',min:0,max:1,value:0,step:1,disabled:'','aria-label':'재생 위치'});
      const speed=element('select',{id:'speed',disabled:'','aria-label':'재생속도'});speed.appendChild(element('option',{value:1,'aria-label':'1배'},['1×']));
      const status=element('p',{id:'status',role:'status','aria-live':'polite'},['영상을 준비하고 있어요…']);
      const avatar=element('img',{class:'channel-avatar',alt:'','aria-hidden':'true',hidden:'',width:52,height:52});
      avatar.onerror=()=>{avatar.hidden=true;};
      const channelName=element('span',{class:'channel-name'},['채널을 불러오는 중…']);
      const channelHint=element('span',{class:'channel-hint',hidden:''},['채널 영상 보기']);
      const channelArrow=element('span',{class:'channel-arrow','aria-hidden':'true',hidden:''},['›']);
      const channel=element('button',{id:'channel',disabled:''},[avatar,element('span',{class:'channel-copy'},[channelName,channelHint]),channelArrow]);
      const comments=element('div',{id:'comments',class:'comments'});
      const commentStatus=element('p',{id:'comment-status',role:'status','aria-live':'polite'},['댓글을 불러오는 중…']);
      const more=element('button',{id:'more-comments',hidden:''},['댓글 더 보기']);
      const timeline=element('div',{class:'timeline'},[seek,speed,time]);timeline.hidden=short;status.hidden=short;
      main.append(screen,heading,timeline,status);
      let previousButton,nextButton,shortActions;
      if(short){
        previousButton=element('button',{id:'short-previous'},['이전']);nextButton=element('button',{id:'short-next'},['다음']);
        previousButton.onclick=()=>onPrevious?.();nextButton.onclick=()=>onNext?.();
        shortActions=element('div',{class:'short-actions','data-loading':'','aria-hidden':'true'},[previousButton,nextButton]);shortActions.inert=true;
        main.appendChild(shortActions);
      }else main.append(channel,element('section',{class:'comment-section','aria-labelledby':'comments-heading'},[
        element('div',{class:'comment-heading'},[element('h2',{id:'comments-heading'},['댓글']),commentStatus]),comments,more]));
      root.appendChild(main);document.body.inert=true;document.documentElement.appendChild(host);
      let player=null,ready=false,closed=false,seeking=false,timer=null,shown=3,totalCommentCount='',openedComments=false,commentsRequestAt=0,commentsRequestCount=0,startedAt=Date.now(),presented=!short,shortSwitching=false;
      const present=()=>{
        if(closed||presented)return;presented=true;host.inert=false;host.style.pointerEvents='';host.style.opacity='1';
        if(!matchMedia('(prefers-reduced-motion: reduce)').matches)host.animate([{opacity:0},{opacity:1}],{duration:180,easing:'ease-out'});
        window.dispatchEvent(new Event('rivo-official-player-presented'));main.focus({preventScroll:true});
      };
      const commentCache=new Map();let details={},endedShortID='';
      let captionDefaultsDone=false,captionModuleSeen=false,captionDefaultChanges=0,captionInitialRequested=false,changingCaptionDefaults=false,captionDeadline=Infinity,captionPlaybackStarted=false;
      const applyDefaultCaptionsOff=target=>{
        if(closed||!ready||captionDefaultsDone||changingCaptionDefaults||Date.now()>captionDeadline||captionDefaultChanges>=4)return;
        // cc_load_policy alone follows account preferences. Module operations are
        // exposed dynamically by the iframe API; never inspect the remote frame DOM.
        try{
          const modules=target.getOptions?.()||[];
          const loaded=modules.includes('captions')||modules.includes('cc');
          if(captionModuleSeen&&!loaded){captionDefaultsDone=true;return;}
          if(!loaded&&captionInitialRequested)return;
          if(loaded)captionModuleSeen=true;
          captionInitialRequested=true;changingCaptionDefaults=true;captionDefaultChanges++;
          for(const module of ['captions','cc']){
            const options=target.getOptions?.(module)||[];
            if(options.includes('track'))target.setOption?.(module,'track',{});
            target.unloadModule?.(module);
          }
        }catch(_){/* Module support varies between official player versions. */}
        finally{changingCaptionDefaults=false;}
      };
      const resizePlayer=()=>{
        if(closed)return;
        const style=getComputedStyle(main),gap=parseFloat(style.rowGap)||14;
        const horizontal=(parseFloat(style.paddingLeft)||0)+(parseFloat(style.paddingRight)||0);
        const vertical=(parseFloat(style.paddingTop)||0)+(parseFloat(style.paddingBottom)||0);
        // Fit the official iframe inside both dimensions of the actual widget viewport.
        const height=Math.min(main.clientHeight||innerHeight,window.visualViewport?.height||innerHeight);
        const controls=short?(shortActions?.offsetHeight||56)+gap:heading.offsetHeight+timeline.offsetHeight+gap*2;
        const ratio=short?9/16:16/9;
        const width=Math.max(1,Math.floor(Math.min(Math.max(1,main.clientWidth-horizontal),Math.max(1,height-vertical-controls)*ratio)));
        const next=`${width}px`;
        screen.style.minHeight='0';screen.style.alignSelf='center';
        if(screen.style.width!==next)screen.style.width=next;
      };
      const resizeObserver=window.ResizeObserver?new ResizeObserver(resizePlayer):null;
      [main,heading,timeline,shortActions].filter(Boolean).forEach(node=>resizeObserver?.observe(node));
      window.addEventListener('resize',resizePlayer);window.visualViewport?.addEventListener('resize',resizePlayer);resizePlayer();
      const updateShortState=state=>{
        if(!shortActions)return;
        const loaded=ready&&!shortSwitching&&[0,1,2,5].includes(state);
        shortActions.toggleAttribute('data-loading',!loaded);shortActions.inert=!loaded;
        if(loaded)shortActions.removeAttribute('aria-hidden');else shortActions.setAttribute('aria-hidden','true');
      };
      if(short){
        prepareShort=()=>{shortSwitching=true;updateShortState(null);player?.pauseVideo?.();};
        changeShort=next=>{
          if(closed||!ready)return false;
          captionDefaultsDone=false;captionModuleSeen=false;captionDefaultChanges=0;captionInitialRequested=false;captionDeadline=Infinity;captionPlaybackStarted=false;
          shortSwitching=true;updateShortState(null);host.setAttribute('data-video-id',next.videoId);
          player.getIframe().title=next.title||'YouTube 쇼츠';
          player.loadVideoById({videoId:next.videoId,startSeconds:Math.max(0,next.startSeconds||0)});
          return true;
        };
      }
      const clock=value=>{const n=Number.isFinite(value)?Math.floor(Math.max(0,value)):0;return n>=3600?`${Math.floor(n/3600)}:${String(Math.floor(n/60)%60).padStart(2,'0')}:${String(n%60).padStart(2,'0')}`:`${Math.floor(n/60)}:${String(n%60).padStart(2,'0')}`;};
      const say=(text,error=false)=>{if(status.textContent!==text)status.textContent=text;status.hidden=short&&!error;};
      const updateDetails=()=>{
        if(closed)return;
        if(short){
          for(const [next,b]of[[false,previousButton],[true,nextButton]]){const native=[...document.querySelectorAll('button[aria-label]')].find(e=>new RegExp(next?'다음 동영상|Next video':'이전 동영상|Previous video','i').test(e.getAttribute('aria-label')));b.disabled=!native||native.disabled;}
          return;
        }
        details=readDetails();
        if(details.channelName&&details.channelURL){channel.disabled=false;channelHint.hidden=false;channelArrow.hidden=false;channel.setAttribute('aria-label',`${details.channelName}, 채널 영상 보기`);if(channelName.textContent!==details.channelName)channelName.textContent=details.channelName;}
        if(details.channelAvatar){if(avatar.getAttribute('src')!==details.channelAvatar){avatar.hidden=false;avatar.src=details.channelAvatar;}}
        else {avatar.hidden=true;avatar.removeAttribute('src');}
        for(const c of details.comments){const key=c.author+'\n'+c.text;commentCache.set(key,c);}
        const visible=[...commentCache.values()].slice(0,shown);
        for(let i=comments.children.length;i<visible.length;i++){const c=visible[i];comments.appendChild(element('article',{class:'comment'},[
          element('p',{},[c.text]),element('footer',{class:'comment-author'},[element('span',{'aria-hidden':'true'},['—']),element('strong',{},[c.author||'YouTube 사용자'])])]));}
        if(details.totalCommentCount)totalCommentCount=details.totalCommentCount;
        const message=details.disabled?'이 영상은 댓글을 사용할 수 없어요.':totalCommentCount|| (visible.length?'':Date.now()-startedAt>15000?'댓글을 아직 불러오지 못했어요. 댓글 다시 불러오기로 다시 시도해 주세요.':'댓글을 불러오는 중…');
        if(commentStatus.textContent!==message)commentStatus.textContent=message;
        if(commentsRequestAt&&(commentCache.size>commentsRequestCount||Date.now()-commentsRequestAt>15000))commentsRequestAt=0;
        const retryComments=!visible.length&&!details.disabled&&totalCommentCount!=='0개'&&Date.now()-startedAt>15000;
        more.hidden=details.disabled||!!commentsRequestAt||(!visible.length&&!retryComments);
        more.textContent=retryComments?'댓글 다시 불러오기':'댓글 더 보기';
        comments.setAttribute('aria-busy',String(!!commentsRequestAt||!visible.length&&!details.disabled&&!retryComments&&totalCommentCount!=='0개'));
        if(!openedComments&&!commentCache.size&&!details.disabled)openedComments=openComments();
      };
      channel.onclick=()=>{if(details.channelURL){close();onChannel?.(details.channelURL);}};
      more.onclick=()=>{
        if(!commentCache.size){startedAt=Date.now();openedComments=openComments();shown=3;}
        else {shown+=5;if(commentCache.size<shown){commentsRequestAt=Date.now();commentsRequestCount=commentCache.size;moreComments();}}
        updateDetails();
      };
      const update=()=>{
        if(closed)return;updateDetails();if(!ready)return;
        const current=player.getCurrentTime(),duration=player.getDuration();time.textContent=`${clock(current)} / ${clock(duration)}`;
        seek.max=Math.max(1,Number.isFinite(duration)?duration:0);seek.disabled=!(duration>0);if(!seeking)seek.value=current;seek.setAttribute('aria-valuetext',time.textContent);speed.value=String(player.getPlaybackRate());
      };
      const close=()=>{if(closed)return;closed=true;clearInterval(timer);resizeObserver?.disconnect();window.removeEventListener('resize',resizePlayer);window.visualViewport?.removeEventListener('resize',resizePlayer);player?.destroy();if(activePlayer===player)activePlayer=null;host.remove();document.body.inert=previousInert;window.dispatchEvent(new Event('rivo-official-player-closed'));if(previousFocus?.isConnected)previousFocus.focus({preventScroll:true});closeCurrent=null;changeShort=null;prepareShort=null;};
      closeCurrent=close;
      seek.oninput=()=>{seeking=true;};seek.onchange=()=>{seeking=false;player.seekTo(Math.max(0,Math.min(Number(seek.value),player.getDuration())),true);};
      speed.onchange=()=>player.setPlaybackRate(Number(speed.value));
      root.addEventListener('keydown',event=>{
        if(event.key==='Escape'){event.preventDefault();window.__rivoYouTubePrototype?.back?.()||close();}
        if(event.key==='Tab'){
          const items=[...root.querySelectorAll('button,input,select,iframe')].filter(e=>!e.disabled&&!e.closest('[hidden],[inert]'));
          if(event.shiftKey&&root.activeElement===items[0]){event.preventDefault();items.at(-1)?.focus();}
          else if(!event.shiftKey&&root.activeElement===items.at(-1)){event.preventDefault();items[0]?.focus();}
        }
      });
      try{
        player=new YT.Player(target,{width:'100%',height:'100%',videoId,
          playerVars:{autoplay:autoplay?1:0,controls:1,start:Number.isFinite(startSeconds)?Math.floor(Math.max(0,startSeconds)):0,playsinline:1,enablejsapi:1,origin:location.origin,hl:'ko',cc_load_policy:0},
          events:{
            onReady:event=>{if(closed){event.target.destroy();return;}ready=true;activePlayer=event.target;applyDefaultCaptionsOff(event.target);speed.disabled=false;
              speed.replaceChildren(...event.target.getAvailablePlaybackRates().map(rate=>element('option',{value:rate,'aria-label':`${rate}배`},[`${rate}×`])));
              const frame=event.target.getIframe();frame.title=title||'YouTube 동영상';frame.setAttribute('allow','autoplay; encrypted-media; picture-in-picture; fullscreen');frame.removeAttribute('aria-hidden');frame.setAttribute('tabindex','0');
              if(autoplay)event.target.playVideo?.();present();updateShortState(event.target.getPlayerState?.());say('');update();},
            onStateChange:event=>{if(closed)return;
              if(event.data===0&&short&&!shortSwitching){
                const finishedID=host.getAttribute('data-video-id');
                if(endedShortID!==finishedID){endedShortID=finishedID;if(onNext?.()===true)return;}
              }
              if([1,5].includes(event.data))shortSwitching=false;
              if(event.data===1){endedShortID='';if(!captionPlaybackStarted){captionPlaybackStarted=true;captionDeadline=Date.now()+8000;}applyDefaultCaptionsOff(event.target||player);}updateShortState(event.data);const labels={0:'',1:'',2:'일시정지',3:'영상 준비 중'};say(labels[event.data]||'');update();},
            onApiChange:event=>{applyDefaultCaptionsOff(event.target||player);},
            onPlaybackRateChange:event=>{if(!closed)speed.value=String(event.data);},
            onAutoplayBlocked:()=>{if(!closed){shortSwitching=false;present();updateShortState(player.getPlayerState?.());say('동영상을 눌러 재생해 주세요.');}},
            onError:event=>{if(closed)return;present();updateShortState(null);speed.disabled=true;seek.disabled=true;say(`영상을 재생할 수 없어요. 오류 ${event.data}. 이전 화면에서 다른 영상을 선택해 주세요.`,true);}
          }});
        timer=setInterval(update,500);updateDetails();
      }catch(error){close();throw error;}
      if(!short)main.focus({preventScroll:true});return 'Rivo official player opened';
    }
  };
  return 'Rivo official player ready';
})();

// Development adapter: reads the signed-in YouTube DOM; playback uses the official iframe API.
// No media extraction, credential access, private API requests, or local resolver.
(() => {
  'use strict';
  if (!['m.youtube.com','www.youtube.com','youtube.com'].includes(location.hostname)) throw new Error('YouTube page required');
  if (!window.__rivoOfficialPlayer) throw new Error('Install official-player.js first');
  window.__rivoYouTubePrototype?.uninstall();
  const make=(tag,attrs={},text='')=>{const e=document.createElement(tag);for(const [k,v] of Object.entries(attrs))e.setAttribute(k,v);if(text)e.textContent=text;return e;};
  let host=null, root=null, previousInert=false, previousFocus=null, selection=null;
  let section='home', signature='', pending=null, timer=null, searchDraft='', lastRoute='', accountState=null;
  let feedRoute='', feedItems=new Map(),loadStarted=Date.now(),morePending=null,feedRefreshing=false;
  const feedCacheKey='rivo.youtube.feed.v1',feedIdleLimit=30*60*1000;
  const readFeedCache=()=>{try{const value=JSON.parse(sessionStorage.getItem(feedCacheKey)||'null');return value&&Array.isArray(value.routes)&&Number.isFinite(value.lastSeen)?value:null;}catch(_){return null;}};
  let feedCache=readFeedCache()||{routes:[],lastSeen:Date.now()},feedRestored=false,restoreFeedScroll=null,lastFeedTouch=0,feedCacheInvalidated=false;
  let contentActive=window.__rivoYouTubeContentActive!==false;
  if(Date.now()-feedCache.lastSeen>feedIdleLimit||Date.now()<feedCache.lastSeen)feedCache={routes:[],lastSeen:Date.now()};
  const writeFeedCache=()=>{try{sessionStorage.setItem(feedCacheKey,JSON.stringify(feedCache));}catch(_){}};
  const saveFeed=()=>{
    if(!root||!feedItems.size||!feedRoute||feedRefreshing||feedCacheInvalidated||feedCache.needsRefresh||location.pathname+location.search!==feedRoute||/^\/(?:watch|shorts)(?:[/?]|$)/.test(feedRoute)||restoreFeedScroll!==null)return;
    const entry={route:feedRoute,section,scroll:root.querySelector('main')?.scrollTop||0,items:[...feedItems.values()].slice(0,120)};
    feedCache.routes=feedCache.routes.filter(value=>value.route!==feedRoute).concat(entry).slice(-4);writeFeedCache();
  };
  const touchFeed=()=>{
    if(contentActive&&document.visibilityState!=='hidden'&&Date.now()-lastFeedTouch>15000){feedCache.lastSeen=Date.now();lastFeedTouch=Date.now();writeFeedCache();}
  };
  const activateFeed=(active,{native=true}={})=>{
    if(!active){saveFeed();if(contentActive){feedCache.lastSeen=Date.now();writeFeedCache();}}
    else {
      const latest=readFeedCache();
      if(latest)feedCache=latest;
      if(Date.now()-feedCache.lastSeen>feedIdleLimit){feedCache={routes:[],lastSeen:Date.now(),needsRefresh:true};feedRestored=false;writeFeedCache();}
    }
    contentActive=active;if(native)window.__rivoYouTubeContentActive=active;
    if(active)touchFeed();
  };
  const feedVisibility=()=>activateFeed(document.visibilityState!=='hidden'&&window.__rivoYouTubeContentActive!==false,{native:false});
  const feedPageHide=()=>{saveFeed();if(contentActive){feedCache.lastSeen=Date.now();writeFeedCache();}};
  const feedPageShow=()=>{if(window.__rivoYouTubeContentActive!==false)activateFeed(true,{native:false});};
  document.addEventListener('visibilitychange',feedVisibility);
  window.addEventListener('pagehide',feedPageHide);window.addEventListener('pageshow',feedPageShow);
  const restoreCachedFeed=key=>{
    const cached=feedCache.routes.find(value=>value.route===key&&Array.isArray(value.items));
    if(!cached)return false;
    feedItems=new Map(cached.items.filter(value=>/^[\w-]{11}$/.test(value?.id||'')&&typeof value.title==='string').slice(0,120).map(value=>[value.id,value]));
    if(!feedItems.size)return false;
    restoreFeedScroll=Math.max(0,Number(cached.scroll)||0);feedRestored=true;return true;
  };
  const restoreListScroll=()=>{
    if(restoreFeedScroll===null)return;
    const scroll=restoreFeedScroll,key=feedRoute;
    requestAnimationFrame(()=>{if(root&&feedRoute===key){root.querySelector('main').scrollTop=scroll;restoreFeedScroll=null;}});
  };
  const durationValue=text=>{const value=(text||'').trim();return /^(?:\d{1,3}:)?\d{1,3}:[0-5]\d$/.test(value)?value:'';};
  const spokenDuration=value=>{const parts=value.split(':').map(Number);return parts.length===3?`${parts[0]}시간 ${parts[1]}분 ${parts[2]}초`:`${parts[0]}분 ${parts[1]}초`;};
  const intentKey='rivo.youtube.playback.v1';
  const readIntent=()=>{try{const value=JSON.parse(sessionStorage.getItem(intentKey)||'null');return value&&Date.now()-value.createdAt>=0&&Date.now()-value.createdAt<120000&&['watch','shorts'].includes(value.kind)?value:null;}catch(_){return null;}};
  let playbackIntent=readIntent(),autoShorts=playbackIntent?.kind==='shorts',lastOpenedVideo='',shortTransitionFrom=null;
  const rememberIntent=value=>{playbackIntent={...value,createdAt:Date.now()};try{sessionStorage.setItem(intentKey,JSON.stringify(playbackIntent));}catch(_){}};
  const clearIntent=()=>{playbackIntent=null;try{sessionStorage.removeItem(intentKey);}catch(_){}};
  const currentVideoID=()=>location.pathname.startsWith('/shorts/')?location.pathname.split('/')[2]:location.pathname==='/watch'?new URLSearchParams(location.search).get('v'):null;
  const moveShort=next=>{const button=nativeShortButton(next);if(button&&!button.disabled&&button.getAttribute('aria-disabled')!=='true'){rememberIntent({kind:'shorts'});autoShorts=true;startPending('shorts');originalAction(()=>button.click());return true;}return false;};
  const openPlayback=()=>{
    const id=currentVideoID(),short=location.pathname.startsWith('/shorts/');
    if(!/^[\w-]{11}$/.test(id||'')||id===lastOpenedVideo||typeof window.YT?.Player!=='function'||(short&&(!autoShorts||id===shortTransitionFrom)))return;
    lastOpenedVideo=id;shortTransitionFrom=null;
    const title=(playbackIntent?.id===id?playbackIntent.title:null)||document.querySelector('h1,h2')?.textContent.trim()||(short?'쇼츠 영상':'YouTube 동영상');
    const autoplay=short?autoShorts:playbackIntent?.kind==='watch'&&playbackIntent.id===id;
    if(!short)clearIntent();
    try{if(!short)host.inert=true;window.__rivoOfficialPlayer.open({videoId:id,title,short,autoplay,
      onChannel:url=>{clearIntent();autoShorts=false;location.assign(url);},onPrevious:()=>moveShort(false),onNext:()=>moveShort(true)});if(!short)host.inert=true;}
    catch(error){lastOpenedVideo='';host.inert=false;say(error.message);}
  };
  const labels={home:'내 추천',subscriptions:'구독 영상',shorts:'쇼츠',search:'검색',channel:'채널 영상'};
  const sectionForURL=()=>/^\/(?:@|channel\/|c\/|user\/)/.test(location.pathname)?'channel':location.pathname.startsWith('/feed/subscriptions')?'subscriptions':location.pathname.startsWith('/shorts')?'shorts':location.pathname==='/results'?'search':'home';
  const routeKey=()=>location.pathname+location.search;
  const $=id=>root.getElementById(id);
  const say=text=>{if($('status').textContent!==text)$('status').textContent=text;};
  const updateFeedRefresh=()=>{
    const button=$('feed-refresh');if(!button)return;
    button.hidden=section!=='home';
    button.disabled=feedRefreshing||accountState!=='signed-in'||!!pending||$('grid').getAttribute('aria-busy')==='true';
  };
  const reloadHomeFeed=()=>{
    const button=$('feed-refresh');if(button.disabled)return;
    feedCache.routes=feedCache.routes.filter(value=>value.route.split('?')[0]!=='/');feedCache.lastSeen=Date.now();writeFeedCache();feedRestored=false;
    feedRefreshing=true;button.disabled=true;button.setAttribute('aria-busy','true');
    clearIntent();morePending=null;signature='';loading(true);say('영상 목록을 새로고침하고 있어요');
    // Reload the source feed, rather than repainting cards from the old DOM/cache.
    if(location.pathname==='/'&&!location.search)location.reload();else location.assign('/');
  };
  const loading=(active,{append=false}={})=>{
    const stage=$('feed-stage'),loader=$('loading');
    if(append){if(loader.nextSibling!==$('more'))$('more').before(loader);}
    else if(loader.parentNode!==stage||stage.firstChild!==loader)stage.prepend(loader);
    stage.toggleAttribute('data-loading',active&&!append&&section!=='shorts');
    $('loading').classList.toggle('append',append);
    $('loading').hidden=!active||section==='shorts';
    if(section!=='shorts')$('grid').hidden=(active&&!append)||!$('empty-subscriptions').hidden;
    $('grid').setAttribute('aria-busy',String(active));$('more').hidden=active||section==='shorts'||!$('empty-subscriptions').hidden;
    updateFeedRefresh();
    if(active){const text=append?'영상을 더 불러오고 있어요':'영상을 불러오고 있어요';if($('loading-label').textContent!==text)$('loading-label').textContent=text;say('');}
  };
  const originalAction=fn=>{const old=document.body.inert;document.body.inert=false;try{return fn();}finally{document.body.inert=old;}};
  const pauseOriginal=()=>{for(const v of document.body.querySelectorAll('video,audio'))if(!v.paused)v.pause();};
  const snapshot=()=>{
    // Shorts have one full player and never a second thumbnail/card view.
    if(sectionForURL()==='shorts')return [];
    const seen=new Set(),items=[];
    for(const anchor of document.querySelectorAll('a[href*="watch?v="]')){
      const url=new URL(anchor.getAttribute('href'),location.href),id=url.searchParams.get('v');
      if(!['m.youtube.com','www.youtube.com','youtube.com'].includes(url.hostname)||!/^[\w-]{11}$/.test(id||'')||seen.has(id))continue;
      const card=anchor.closest('ytm-rich-item-renderer,ytm-video-with-context-renderer,ytm-media-item,ytd-rich-item-renderer,ytd-video-renderer');
      if(!card||card.closest('[hidden],[aria-hidden="true"]'))continue;
      const title=(card.querySelector('h3,h4,.media-item-headline,#video-title')?.textContent||[...card.querySelectorAll('a[href*="watch?v="]')].map(a=>a.textContent.trim()).sort((a,b)=>b.length-a.length)[0]||'').trim();
      if(!title)continue;
      let imageURL=`https://i.ytimg.com/vi/${id}/hqdefault.jpg`;const image=card.querySelector('img');
      try{const u=new URL(image?.currentSrc||image?.getAttribute('src')||'',location.href);if(u.protocol==='https:'&&u.hostname.endsWith('.ytimg.com'))imageURL=u.href;}catch(_){}
      const duration=[...card.querySelectorAll('ytm-thumbnail-overlay-time-status-renderer,ytd-thumbnail-overlay-time-status-renderer,.badge-shape-wiz__text,.yt-badge-shape__text,.ytBadgeShapeText,yt-thumbnail-badge-view-model,[class*=BadgeShape][class*=Text],.thumbnail-overlay-time-status')].map(e=>durationValue(e.textContent)).find(Boolean)||'';
      const metadata=[...card.querySelectorAll('.ytContentMetadataViewModelMetadataText,.media-item-byline,#metadata-line')].map(e=>e.textContent.trim()).filter(Boolean);
      const lines=(metadata.length?metadata.join('\n'):(card.innerText||'')).split('\n').map(s=>s.trim()).filter(s=>s&&!/^[·•⋅.\s]+$/.test(s)&&s!==title&&!durationValue(s)&&s!=='Shorts'&&s!=='믹스 재생목록');
      seen.add(id);items.push({id,title,imageURL,duration,meta:lines.filter(s=>!title.includes(s)).slice(-3).join(' · ')});
      if(items.length>=60)break;
    }
    return items;
  };
  const nativeTab=name=>[...document.querySelectorAll('ytm-pivot-bar-item-renderer')].find(e=>name==='Shorts'?/^(Shorts|쇼츠|ショート)$/i.test(e.textContent.trim()):e.textContent.trim()===name)?.querySelector('[role="tab"],a[href]');
  const emptySubscriptions=()=>sectionForURL()==='subscriptions' && [...document.querySelectorAll('ytm-background-promo-renderer,ytd-background-promo-renderer,ytm-message-renderer,ytd-message-renderer,ytm-item-section-renderer')].some(e=>!e.querySelector('ytm-video-with-context-renderer,ytm-rich-item-renderer,ytd-video-renderer,ytd-rich-item-renderer')&&/마음에 드는 채널을 구독|구독.*영상.*없|아직 구독한 채널|subscribe to.*channels|haven.t subscribed|no (?:new )?(?:videos|subscriptions)|チャンネルに登録して|登録チャンネル.*(?:ありません|ない)/i.test(e.textContent));
  const nativeShortButton=next=>[...document.querySelectorAll('button[aria-label]')].find(b=>new RegExp(next?'다음 동영상|Next video':'이전 동영상|Previous video','i').test(b.getAttribute('aria-label')));
  const setSection=(next,{focus=false}={})=>{
    section=next;root.querySelector('main').setAttribute('aria-label',`쉬운 유튜브 ${labels[next]}`);
    for(const b of root.querySelectorAll('[data-section]')){if(b.dataset.section===next)b.setAttribute('aria-current','page');else b.removeAttribute('aria-current');}
    $('heading').textContent=labels[next];
    // Keep the outgoing shell in place until the official Shorts frame is ready.
    if(next!=='shorts'){
      $('search-form').hidden=false;root.querySelector('nav').hidden=false;
      root.querySelector('header').hidden=!!window.__rivoLauncherEmbedded;
      $('grid').hidden=false;$('status').hidden=false;$('empty-subscriptions').hidden=true;$('more').hidden=true;
    }
    if(focus&&next!=='shorts'){root.querySelector('main').scrollTop=0;(next==='search'?$('query'):$('heading')).focus({preventScroll:true});}
  };
  const playerPresented=()=>{if(host){host.setAttribute('data-player-presented','');host.inert=true;}};
  window.addEventListener('rivo-official-player-presented',playerPresented);
  const playerClosed=()=>{if(host){host.removeAttribute('data-player-presented');host.inert=false;if(selection?.isConnected)selection.focus({preventScroll:true});}};
  window.addEventListener('rivo-official-player-closed',playerClosed);
  const closeHome=()=>{
    if(timer)clearInterval(timer);timer=null;
    if(!host)return;
    window.__rivoOfficialPlayer.close();host.remove();host=null;root=null;document.body.inert=previousInert;
    if(previousFocus?.isConnected)previousFocus.focus({preventScroll:true});
  };
  const startPending=target=>{
    saveFeed();
    if(target==='shorts'){shortTransitionFrom=currentVideoID();lastOpenedVideo='';}
    if(target==='shorts')window.__rivoOfficialPlayer.prepareShortTransition();
    else {window.__rivoOfficialPlayer.close();host.inert=false;}
    morePending=null;loadStarted=Date.now();pending={section:target,since:Date.now(),before:snapshot().map(x=>x.id).join(',')};signature='';
    setSection(target);if(target!=='shorts')$('grid').replaceChildren();$('grid').setAttribute('aria-busy','true');loading(target!=='shorts');
  };
  const navigate=target=>{
    if(accountState!=='signed-in')return;
    if(target==='shorts'){rememberIntent({kind:'shorts'});autoShorts=true;lastOpenedVideo='';}
    if(target==='search'){$('query').focus({preventScroll:true});return;}
    if(sectionForURL()===target&&!pending){setSection(target,{focus:true});signature='';refresh();return;}
    const names={home:'홈',subscriptions:'구독',shorts:'Shorts'};
    const native=nativeTab(names[target]);
    const fallback=[...document.querySelectorAll('a[href]')].find(a=>target==='shorts'?/^\/shorts(?:\/|$)/.test(a.getAttribute('href')||''):a.getAttribute('href')==={home:'/',subscriptions:'/feed/subscriptions'}[target]);
    startPending(target);
    if(native||fallback) {
      originalAction(()=>(native||fallback).click());
      // Public navigation remains available when a site's hidden menu handler changes.
      setTimeout(()=>{if(host&&pending?.section===target&&sectionForURL()!==target)location.assign({home:'/',subscriptions:'/feed/subscriptions',shorts:'/shorts'}[target]);},800);
    } else location.assign({home:'/',subscriptions:'/feed/subscriptions',shorts:'/shorts'}[target]);
  };
  const play=(item,button)=>{
    if(accountState!=='signed-in')return;
    selection=button;saveFeed();feedRestored=true;
    if(item.short){rememberIntent({kind:'shorts',id:item.id,title:item.title});autoShorts=true;lastOpenedVideo='';openPlayback();return;}
    rememberIntent({kind:'watch',id:item.id,title:item.title});
    if(currentVideoID()===item.id){lastOpenedVideo='';openPlayback();return;}
    location.assign('/watch?v='+item.id);
  };
  const render=(items,{empty=false}={})=>{
    const grid=$('grid');
    const firstPaint=!grid.children.length&&items.length>0;
    const existing=new Map([...grid.querySelectorAll('.card')].map(button=>[button.dataset.videoId,button]));
    grid.hidden=empty||section==='shorts';$('empty-subscriptions').hidden=!empty;$('status').hidden=empty||section==='shorts'||(section==='home'&&items.length>0);grid.setAttribute('aria-busy','false');updateFeedRefresh();
    for(const [index,item] of items.entries()){
      let button=existing.get(item.id);
      if(!button){
        button=make('button',{'class':'card','data-video-id':item.id});
        const image=make('img',{alt:'',loading:index<4?'eager':'lazy',decoding:'async'});
        image.onerror=()=>{const fallback=`https://i.ytimg.com/vi/${item.id}/hqdefault.jpg`;if(image.getAttribute('src')!==fallback)image.src=fallback;};
        button.appendChild(image);
        image.setAttribute('aria-hidden','true');
        const copy=make('span',{'class':'copy','aria-hidden':'true'});
        copy.appendChild(make('span',{'class':'title'}));copy.appendChild(make('span',{'class':'meta'}));copy.appendChild(make('span',{'class':'duration'}));
        button.appendChild(copy);grid.appendChild(button);
      }
      existing.delete(item.id);
      const info=(item.meta||'').split(/\s*[·•⋅]\s*/).filter(Boolean);
      const ageIndex=info.findLastIndex(text=>/\d[\d.,]*\s*(?:(?:초|분|시간|일|주|개월|달|년)\s*전|(?:seconds?|minutes?|hours?|days?|weeks?|months?|years?)\s+ago|(?:秒|分|時間|日|週間|か月|ヶ月|年)\s*前)/i.test(text));
      const age=ageIndex<0?'':info.splice(ageIndex,1)[0],meta=info.join(' · ');
      button.setAttribute('aria-label',[item.title,meta,age,item.duration?'길이 '+spokenDuration(item.duration):''].filter(Boolean).join(', '));
      const image=button.querySelector('img');
      if(image.getAttribute('src')!==item.imageURL)image.src=item.imageURL;
      if(button.querySelector('.title').textContent!==item.title)button.querySelector('.title').textContent=item.title;
      if(button.querySelector('.meta').textContent!==meta)button.querySelector('.meta').textContent=meta;
      const duration=button.querySelector('.duration'),summary=[age,item.duration?`길이 ${item.duration}`:''].filter(Boolean).join(' · ');
      if(duration.textContent!==summary)duration.textContent=summary;duration.hidden=!summary;
      button.onclick=()=>play(item,button);
    }
    existing.forEach(button=>button.remove());
    if(firstPaint&&!matchMedia('(prefers-reduced-motion: reduce)').matches)grid.animate([{opacity:0},{opacity:1}],{duration:180,easing:'ease-out'});
    const query=new URLSearchParams(location.search).get('search_query');
    say(empty||section==='shorts'||section==='home'&&items.length?'':items.length?(section==='search'?`‘${query||searchDraft}’ 검색 결과 ${items.length}개`:`지금 불러온 ${section==='subscriptions'?'구독 영상':section==='channel'?'채널 영상':'추천'} ${items.length}개`):'영상을 찾지 못했어요. 잠시 후 다시 시도해 주세요.');
  };
  const refreshAccount=()=>{
    const link=[...document.querySelectorAll('a[href]')].find(a=>{try{const u=new URL(a.href);return (u.hostname==='accounts.google.com'&&(u.pathname.includes('ServiceLogin')||u.pathname.includes('signin')))||(['m.youtube.com','www.youtube.com','youtube.com'].includes(u.hostname)&&u.pathname==='/signin');}catch(_){return false;}});
    const button=[...document.querySelectorAll('button,[role="button"]')].find(b=>/^(로그인|Sign in|ログイン)$/i.test((b.textContent||b.getAttribute('aria-label')||'').trim()));
    const loggedIn=window.ytcfg?.get?.('LOGGED_IN');
    const next=loggedIn===true?'signed-in':(loggedIn===false||link||button)?'signed-out':'pending';
    const previous=accountState;accountState=next;
    const signedIn=next==='signed-in';
    $('content').hidden=next==='signed-out';$('sign-in-gate').hidden=next!=='signed-out';
    for(const button of root.querySelectorAll('nav button'))button.disabled=!signedIn;
    $('query').disabled=!signedIn;$('search-submit').hidden=$('query').value.length===0;$('search-submit').disabled=!signedIn||!!pending||!$('query').value.trim();$('search-voice').setAttribute('aria-disabled',String(!signedIn));$('search-voice').tabIndex=signedIn?0:-1;
    if(next==='pending')loading(true);
    const message=next==='pending'?'유튜브를 준비하고 있어요':'유튜브를 이용하기 위해 로그인해 주세요';
    if($('sign-in-title').textContent!==message)$('sign-in-title').textContent=message;
    $('sign-in').hidden=next==='pending';
    $('sign-in').onclick=()=>{location.href=link?.href||'https://m.youtube.com/signin';};
    if(previous!==next){
      if(signedIn){signature='';setSection(sectionForURL(),{focus:true});}
      else{
        window.__rivoOfficialPlayer.close();host.inert=false;pending=null;signature='';feedRoute='';feedItems.clear();$('grid').replaceChildren();
        if(next==='signed-out'){feedCache={routes:[],lastSeen:Date.now()};writeFeedCache();$('sign-in-title').focus({preventScroll:true});}
      }
    }
    return signedIn;
  };
  const refresh=()=>{
    if(!host)return;touchFeed();pauseOriginal();if(!refreshAccount())return;openPlayback();
    // The watch page's recommendations must never replace the list behind the player.
    if(location.pathname==='/watch')return;
    if(contentActive&&feedCache.needsRefresh&&sectionForURL()!=='shorts'){
      feedCache.needsRefresh=false;feedCache.routes=[];feedCacheInvalidated=true;writeFeedCache();location.reload();return;
    }
    const current=sectionForURL(),key=routeKey(),items=snapshot(),ids=items.map(i=>i.id).join(',');
    if(pending){
      if(pending.waitTab){
        const name={home:'홈',subscriptions:'구독',shorts:'Shorts'}[pending.waitTab],tab=nativeTab(name);
        if(tab){delete pending.waitTab;originalAction(()=>tab.click());return;}
      }
      if(Date.now()-pending.since>12000){pending=null;loading(false);$('more').hidden=true;$('status').hidden=false;say('불러오기가 오래 걸려요. 메뉴를 다시 눌러 주세요.');return;}
      const shortReady=current==='shorts'&&/^[\w-]{11}$/.test(currentVideoID()||'')&&currentVideoID()!==shortTransitionFrom;
      if(current!==pending.section||(!items.length&&!emptySubscriptions()&&!shortReady)||Date.now()-pending.since<350)return;
      if(items.length&&ids===pending.before&&Date.now()-pending.since<1800)return;
      pending=null;setSection(current,{focus:true});
    }else if(key!==lastRoute){setSection(current);signature='';}
    lastRoute=key;
    if(current!==section)return;
    if(current==='shorts'){
      loading(false);
      if(!document.querySelector('[data-rivo-official-player]')&&Date.now()-loadStarted>12000){say('쇼츠를 아직 불러오지 못했어요. 뒤로가기로 홈에 돌아가 다시 열어 주세요.');$('status').hidden=false;}
      return;
    }
    // YouTube virtualizes and lazy-loads the hidden original feed. Keep the visible
    // cards stable while source nodes unload; discard the cache on actual navigation.
    if(feedRoute!==key){saveFeed();feedRoute=key;feedItems.clear();feedRestored=false;restoreFeedScroll=null;loadStarted=Date.now();morePending=null;restoreCachedFeed(key);}
    const confirmedEmpty=!feedRestored&&current==='subscriptions'&&emptySubscriptions();
    if(confirmedEmpty)feedItems.clear();
    for(const item of confirmedEmpty||feedRestored&&!morePending?[]:items){
      const previous=feedItems.get(item.id);
      feedItems.set(item.id,{...item,imageURL:item.imageURL||previous?.imageURL,meta:item.meta||previous?.meta||'',duration:item.duration||previous?.duration||''});
    }
    while(feedItems.size>120)feedItems.delete(feedItems.keys().next().value);
    const visible=[...feedItems.values()];
    const next=key+'|'+confirmedEmpty+'|'+visible.map(i=>i.id+':'+i.title+':'+i.imageURL+':'+i.meta+':'+i.duration).join('|');
    if(next!==signature){signature=next;render(visible,{empty:confirmedEmpty});saveFeed();restoreListScroll();}
    const initial=!visible.length&&!confirmedEmpty&&Date.now()-loadStarted<12000;
    const moreLoading=morePending&&visible.map(item=>item.id).join(',')===morePending.ids&&Date.now()-morePending.since<12000;
    if(morePending&&!moreLoading){morePending=null;}
    loading(initial||!!moreLoading,{append:visible.length>0});
    if(!initial&&!visible.length&&!confirmedEmpty){$('more').textContent='다시 불러오기';say('영상을 아직 불러오지 못했어요. 다시 시도해 주세요.');}
    else $('more').textContent='영상 더 불러오기';
  };
  const show=()=>{
    if(host)return;
    signature='';pending=null;accountState=null;
    previousInert=document.body.inert;previousFocus=document.activeElement;
    host=make('div',{'data-rivo-you-tube-home':''});Object.assign(host.style,{position:'fixed',inset:'0',zIndex:'2147483500'});root=host.attachShadow({mode:'open'});
    root.appendChild(make('style',{},`
      :host{color-scheme:light;--bg:#f5f3ee;--surface:#fff;--text:#252b28;--muted:#4c5d54;--accent:#17644e;--soft:#e3eee6;--border:#69786f;display:block;background:var(--bg);color:var(--text);font:17px/1.5 system-ui,-apple-system,sans-serif}
      @media(prefers-color-scheme:dark){:host{color-scheme:dark;--bg:#101714;--surface:#1b2821;--text:#f1f5f2;--muted:#bccdc2;--accent:#a8dec0;--soft:#293e33;--border:#9bafa2}}*{box-sizing:border-box}[hidden]{display:none!important}
      ${window.__rivoLauncherEmbedded ? ':host{color-scheme:dark;--bg:#101714;--surface:#1b2821;--text:#f1f5f2;--muted:#bccdc2;--accent:#a8dec0;--on-accent:#11251a;--soft:#293e33;--border:#9bafa2;background:transparent}' : ''}
      main{height:100%;overflow:auto;overflow-anchor:none;padding:20px;scrollbar-gutter:stable;overscroll-behavior:contain;touch-action:pan-y pinch-zoom;-webkit-overflow-scrolling:touch}header{display:grid;grid-template-columns:54px 1fr auto;align-items:center;text-align:center;margin-bottom:18px}.exit{padding:8px;font-size:26px}.brand{font-size:14px;color:var(--muted)}h1{font-size:29px;margin:0;line-height:1.4}
      button,input{font:inherit;min-height:54px;padding:12px 18px;border:1px solid var(--border);border-radius:16px;color:var(--text);background:var(--surface)}button{cursor:pointer}button:disabled{opacity:.5;cursor:default}button:focus-visible,input:focus-visible,h1:focus-visible{outline:3px solid var(--accent);outline-offset:4px}
      nav{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;max-width:900px;margin:0 auto 20px}nav button{display:flex;align-items:center;justify-content:center;gap:10px;font-weight:650}nav button[aria-current]{background:var(--accent);color:var(--bg);border-color:var(--accent)}svg{width:23px;height:23px;flex:none}nav button:not([aria-current]):hover{background:var(--soft)}
      form{display:flex;gap:12px;align-items:center;max-width:900px;margin:0 auto 20px}label{font-weight:650}.sr-only{position:absolute;width:1px;height:1px;padding:0;overflow:hidden;clip-path:inset(50%);white-space:nowrap}input{flex:1;min-width:0}form button{background:var(--accent);color:var(--bg);font-weight:650}
      #search-form{display:flex;align-items:center;flex-wrap:nowrap;gap:4px;min-height:88px;padding:6px 6px 6px 20px;border:1px solid rgba(245,243,233,.7);border-radius:32px;background:rgba(16,16,16,.75);color:${rivoTheme.text};}
      #search-form:focus-within{border-color:${rivoTheme.text};box-shadow:inset 0 0 0 1px ${rivoTheme.text};}
      #query{flex:1;min-width:0;min-height:64px;padding:12px 0;border:0;border-radius:0;background:transparent;color:${rivoTheme.text};font-size:20px;outline:none;}
      #query::placeholder{color:${rivoTheme.text};opacity:1;}
      #query::-webkit-search-cancel-button{display:none;-webkit-appearance:none;appearance:none;}
      #search-form button,#search-form .voice-search{display:flex;flex:none;align-items:center;justify-content:center;padding:0;text-decoration:none;}
      #search-form button{width:52px;height:52px;min-width:52px;min-height:52px;border:1px solid ${rivoTheme.text};border-radius:50%;background:${rivoTheme.link};color:${rivoTheme.bg};}
      #search-form .voice-search{width:56px;height:56px;min-width:56px;min-height:56px;border:0;background:transparent;color:${rivoTheme.text};border-radius:50%;}
      #search-form svg{width:28px;height:28px;}#search-form [aria-disabled="true"]{opacity:.5;pointer-events:none;}
      #search-form .voice-search:focus-visible{outline:3px solid ${rivoTheme.link};outline-offset:3px;}
      .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,270px),1fr));gap:22px;max-width:1300px;margin:auto}.card{color-scheme:light;--surface:#d1d5db;--text:#252b28;--muted:#4c5d54;--accent:#17644e;--border:#69786f;text-align:start;padding:0;overflow:hidden;display:flex;flex-direction:column;align-items:stretch;border-radius:20px;min-width:0;background:var(--surface);color:var(--text);border-color:var(--border)}.card img{display:block;flex:none;width:100%;min-height:1px;aspect-ratio:16/9;object-fit:cover;background:#171717}.copy{min-height:174px;padding:16px;display:flex;flex-direction:column;gap:8px;flex:1}.title{min-height:2.9em;font-size:20px;font-weight:650;line-height:1.45;overflow-wrap:anywhere}.duration{font-size:16px;font-variant-numeric:tabular-nums;color:var(--text)}.meta{min-height:1.5em;font-size:15px;color:var(--muted);overflow-wrap:anywhere}.status{max-width:1300px;margin:0 auto 18px;color:var(--muted);min-height:30px}.more{display:block;margin:24px auto}#feed-refresh{display:block;width:fit-content;max-width:100%;min-height:56px;margin:0 0 18px max(0px,calc((100% - 1300px)/2));padding:8px 0;text-align:start;border:0;border-radius:0;background:transparent;font-size:18px;text-decoration:underline;text-underline-offset:5px;appearance:none;-webkit-appearance:none;-webkit-tap-highlight-color:transparent}#feed-refresh:is(:hover,:active,:focus){background:transparent!important;box-shadow:none}
      :host{transition:opacity 180ms ease-out}:host([data-player-presented]){opacity:0;pointer-events:none}
      .feed-stage{position:relative}.feed-stage[data-loading]{min-height:clamp(180px,36vh,360px)}
      .loading{position:absolute;inset:0;z-index:1;pointer-events:none;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:10px;min-height:180px;margin:0 auto;color:var(--text);text-align:center}
      #loading-label{font-size:17px;font-weight:500;line-height:1.6;letter-spacing:.02em;color:var(--muted)}
      .loading-mark{position:relative;display:block;flex:none;width:144px;height:80px;color:#405a7a}
      @media(prefers-color-scheme:dark){.loading-mark{color:${rivoTheme.link}}}
      ${window.__rivoLauncherEmbedded ? `.loading-mark{color:${rivoTheme.link}}` : ''}
      .loading-mark::before{content:'';position:absolute;inset:8px 0;background:radial-gradient(ellipse at center,currentColor,transparent 68%);opacity:.12}
      .loading-mark svg{position:relative;display:block;width:100%;height:100%;overflow:hidden;mask-image:linear-gradient(to right,transparent,#000 18%,#000 82%,transparent);-webkit-mask-image:linear-gradient(to right,transparent,#000 18%,#000 82%,transparent)}
      .loading-ribbon{fill:none;stroke:currentColor;stroke-width:2.6;stroke-linecap:round;animation:rivo-wave 3.6s linear infinite}
      .loading-mark g:nth-child(2) .loading-ribbon{stroke-width:2;opacity:.55;animation-duration:4.8s;animation-direction:reverse}
      .loading-mark g:nth-child(3) .loading-ribbon{stroke-width:1.4;opacity:.3;animation-duration:6s;animation-delay:-1.5s}
      @keyframes rivo-wave{from{transform:translateX(0)}to{transform:translateX(-144px)}}
      .loading.append{position:static;min-height:96px;margin:8px auto 24px;flex-direction:row;gap:12px;pointer-events:auto}.loading.append .loading-mark{width:80px;height:48px}
      .loading[hidden] .loading-ribbon{animation:none}
      @media(prefers-reduced-motion:reduce){:host{transition:none}.loading-ribbon{animation:none}}
      @media(forced-colors:active){.loading-ribbon{stroke:CanvasText}.loading-mark::before{display:none}.loading-mark svg{mask-image:none;-webkit-mask-image:none}}
      .empty-subscriptions{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:18px;min-height:280px;max-width:560px;margin:24px auto;padding:48px 24px;text-align:center}.empty-icon{display:grid;place-items:center;width:96px;height:96px;border-radius:50%;background:var(--soft);color:var(--accent)}.empty-icon svg{width:64px;height:64px}.empty-subscriptions h2{margin:0;font-size:clamp(24px,2.8vw,30px);line-height:1.45;text-wrap:balance;word-break:keep-all}.empty-subscriptions p{margin:0;max-width:24em;color:var(--muted);font-size:19px;line-height:1.7;word-break:keep-all}
      #sign-in-gate{${themeCSS};color:var(--text);background:${window.__rivoLauncherEmbedded?'transparent':'var(--bg)'}}
      .sign-in-gate{position:relative;isolation:isolate;display:grid;place-items:center;min-height:100%;padding:32px 24px;text-align:center;scrollbar-gutter:auto}
      .sign-in-art{position:absolute;z-index:-1;left:50%;top:50%;transform:translate(-50%,-50%);width:76%;max-width:720px;height:86%;max-height:720px;object-fit:contain;opacity:.17;pointer-events:none;user-select:none}
      .sign-in-copy{position:relative;width:min(100%,660px);padding:40px 20px;display:flex;align-items:center;flex-direction:column;gap:32px}
      .sign-in-copy h1{font-size:clamp(28px,3.2vw,40px);line-height:1.5;font-weight:700;max-width:18em;text-wrap:balance;word-break:keep-all;text-shadow:0 1px 14px var(--bg)}
      .sign-in-copy h1:focus{outline:none}
      #sign-in{width:min(100%,320px);min-height:64px;font-size:21px;font-weight:700;background:var(--accent);color:var(--bg);border-color:var(--accent)}
      @media(prefers-color-scheme:dark){.sign-in-art{opacity:.22}}
      @media(max-height:420px){.sign-in-copy{padding:16px;gap:20px}.sign-in-copy h1{font-size:26px}#sign-in{min-height:56px}}
      @media(max-width:540px){main{padding:12px}nav{gap:7px}nav button{flex-direction:column;gap:4px;padding:10px 6px}.grid{gap:16px}h1{font-size:25px}form{flex-wrap:wrap}form label{width:100%}.title{font-size:20px}}
    `));
    const main=make('main',{id:'content',hidden:''}),header=make('header');
    header.hidden=!!window.__rivoLauncherEmbedded;
    const exit=make('button',{'class':'exit','aria-label':'쉬운 유튜브 닫기'},'←');exit.onclick=()=>{location.href='rivo-easy-youtube://close';};header.appendChild(exit);
    const title=make('div');title.appendChild(make('div',{'class':'brand'},'쉬운 유튜브'));title.appendChild(make('h1',{id:'heading',tabindex:'-1'}));header.appendChild(title);
    main.appendChild(header);
    const nav=make('nav',{'aria-label':'유튜브 메뉴'});
    const icons={home:['M3 11 12 3l9 8','M5 10v11h5v-7h4v7h5V10'],subscriptions:['M4 8h16v13H4z','M7 4h10','M10 12l5 3-5 3z'],shorts:['M15 3 5 9v5l4 1-3 3 3 3 10-6v-5l-4-1 3-3z','M10 9v6l5-3z'],search:['M20 20l-5-5','M17 10a7 7 0 1 1-14 0 7 7 0 0 1 14 0']};
    for(const [key,text]of[['home','홈'],['subscriptions','구독'],['shorts','쇼츠']]){
      const b=make('button',{'data-section':key});const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');for(const [k,v]of Object.entries({viewBox:'0 0 24 24',fill:'none',stroke:'currentColor','stroke-width':'1.8','stroke-linecap':'round','stroke-linejoin':'round','aria-hidden':'true',focusable:'false'}))svg.setAttribute(k,v);
      for(const d of icons[key]){const path=document.createElementNS(svg.namespaceURI,'path');path.setAttribute('d',d);svg.appendChild(path);}b.append(svg,document.createTextNode(text));b.onclick=()=>navigate(key);nav.appendChild(b);
    }main.appendChild(nav);
    const form=make('form',{id:'search-form',role:'search'});
    form.appendChild(make('label',{for:'query',class:'sr-only'},'영상 검색'));
    const queryInput=make('input',{id:'query',type:'search',placeholder:'검색',autocomplete:'off',maxlength:'200'});
    const searchIcon=paths=>{const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');for(const[k,v]of Object.entries({viewBox:'0 0 24 24',fill:'none',stroke:'currentColor','stroke-width':'1.8','stroke-linecap':'round','stroke-linejoin':'round','aria-hidden':'true',focusable:'false'}))svg.setAttribute(k,v);for(const d of paths){const path=document.createElementNS(svg.namespaceURI,'path');path.setAttribute('d',d);svg.appendChild(path);}return svg;};
    const send=make('button',{id:'search-submit',type:'submit','aria-label':'검색어 전송',hidden:''});send.appendChild(searchIcon(['M12 19V5','M5 12l7-7 7 7']));
    const voice=make('a',{id:'search-voice',href:'rivo-browser://voice',class:'voice-search',role:'button','aria-label':'음성 검색'});voice.appendChild(searchIcon(['M9 5a3 3 0 0 1 6 0v7a3 3 0 0 1-6 0z','M5 10v2a7 7 0 0 0 14 0v-2','M12 19v3','M8 22h8']));
    voice.addEventListener('keydown',event=>{if(event.key===' '){event.preventDefault();voice.click();}});
    queryInput.addEventListener('input',()=>{send.hidden=queryInput.value.length===0;send.disabled=accountState!=='signed-in'||!!pending||!queryInput.value.trim();});
    form.append(queryInput,send,voice);
    form.onsubmit=event=>{
      event.preventDefault();if(accountState!=='signed-in')return;const query=$('query').value.trim();if(!query){say('검색어를 입력해 주세요.');$('query').focus();return;}
      const nativeForm=document.querySelector('form[action="/results"]'),input=nativeForm?.querySelector('input[name="search_query"]');
      searchDraft=query;startPending('search');
      if(input)originalAction(()=>{input.value=query;input.dispatchEvent(new Event('input',{bubbles:true}));nativeForm.requestSubmit();});
      else location.assign('/results?search_query='+encodeURIComponent(query));
    };main.insertBefore(form,nav);
    const loader=make('div',{id:'loading',class:'loading',role:'status','aria-live':'polite',hidden:''});const mark=make('span',{class:'loading-mark','aria-hidden':'true'});
    const waves=document.createElementNS('http://www.w3.org/2000/svg','svg');waves.setAttribute('viewBox','0 0 144 72');waves.setAttribute('focusable','false');
    // One complete 144-unit wave repeats across both ends, so looping stays seamless.
    const wavePath='M-144 36 C-120 6 -96 6 -72 36 S-24 66 0 36 S48 6 72 36 S120 66 144 36 S192 6 216 36 S264 66 288 36 S336 6 360 36 S408 66 432 36';
    for(let i=0;i<3;i++){
      const layer=document.createElementNS(waves.namespaceURI,'g');layer.setAttribute('transform',`translate(0,${(i-1)*5})`);
      const ribbon=document.createElementNS(waves.namespaceURI,'path');ribbon.setAttribute('class','loading-ribbon');ribbon.setAttribute('d',wavePath);layer.appendChild(ribbon);waves.appendChild(layer);
    }
    mark.appendChild(waves);
    loader.append(mark,make('span',{id:'loading-label'},'영상을 불러오고 있어요'));main.appendChild(loader);
    const feedRefresh=make('button',{id:'feed-refresh',type:'button',hidden:''},'영상 목록 새로고침');feedRefresh.onclick=reloadHomeFeed;main.appendChild(feedRefresh);
    main.appendChild(make('p',{id:'status','class':'status',role:'status','aria-live':'polite'}));
    const feed=make('div',{id:'feed-stage',class:'feed-stage'});feed.append(loader,make('div',{id:'grid',class:'grid','aria-busy':'false'}));main.appendChild(feed);
    const empty=make('section',{id:'empty-subscriptions',class:'empty-subscriptions',role:'status','aria-live':'polite','aria-atomic':'true',hidden:''});
    const decoration=make('div',{class:'empty-icon','aria-hidden':'true'}),art=document.createElementNS('http://www.w3.org/2000/svg','svg');
    for(const [key,value]of Object.entries({viewBox:'0 0 64 64',fill:'none',stroke:'currentColor','stroke-width':'2.5','stroke-linecap':'round','stroke-linejoin':'round',focusable:'false'}))art.setAttribute(key,value);
    for(const d of ['M21 12h22','M16 20h32','M12 29h40v25H12z','M28 35l12 7-12 7z']){const path=document.createElementNS(art.namespaceURI,'path');path.setAttribute('d',d);art.appendChild(path);}
    decoration.appendChild(art);empty.append(decoration,make('h2',{},'아직 구독 영상이 없어요'),make('p',{},'좋아하는 채널의 새 영상을 여기에서 만나보세요.'));main.appendChild(empty);
    const more=make('button',{id:'more','class':'more'},'영상 더 불러오기');more.onclick=()=>{if(!feedItems.size){location.reload();return;}morePending={since:Date.now(),ids:[...feedItems.keys()].join(',')};loading(true,{append:true});originalAction(()=>window.scrollTo({top:document.documentElement.scrollHeight,behavior:'instant'}));signature='';};main.appendChild(more);
    const gate=make('main',{id:'sign-in-gate','class':'sign-in-gate','aria-labelledby':'sign-in-title'});
    gate.appendChild(make('img',{'class':'sign-in-art',src:'data:image/webp;base64,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eFLeFLeFLeFLeFLeFLeFLeEyoqcAzlEn5MbQKjrMe33TMtjTbi2U88/7i7sDrVUlAMET9N7sfcU/hUt3jmumquTruLSZWoovJkD5CK7cUm1JN/z3v92JL8jAoF6v0bcGfNU2+yTrLmJlDQF2PUDYBueke+lzQ4nl/tBNrggtd9O3j9Rj5BnP9lb6CF36lHuFcbB8bB8bB8bB8bB8bB8bB8bB8bB8bB8bB8at3fj9QqD18ftt1iHSDqp3/BofqFE+J6vO9/pdWiQ/eJeFiBVUuiT/845rSqR8aMAI3jrChRnU/AD42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D42D3IAA/v9fxgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAATv+vhxP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',alt:'','aria-hidden':'true',draggable:'false'}));
    const copy=make('div',{'class':'sign-in-copy'});
    copy.appendChild(make('h1',{id:'sign-in-title',tabindex:'-1'},'유튜브를 준비하고 있어요'));
    copy.appendChild(make('button',{id:'sign-in',hidden:''},'로그인'));
    gate.appendChild(copy);root.append(main,gate);document.documentElement.appendChild(host);document.body.inert=true;
    root.addEventListener('keydown',event=>{
      if(event.key==='Escape'){event.preventDefault();if(!back())location.href='rivo-easy-youtube://close';}
      if(event.key==='Tab'){const list=[...root.querySelectorAll('button,input')].filter(e=>!e.disabled&&!e.closest('[hidden]'));const first=list[0],last=list.at(-1);if(event.shiftKey&&root.activeElement===first){event.preventDefault();last?.focus();}else if(!event.shiftKey&&root.activeElement===last){event.preventDefault();first?.focus();}}
    });
    $('query').value=new URLSearchParams(location.search).get('search_query')||'';
    lastRoute=routeKey();setSection(sectionForURL());refresh();timer=setInterval(refresh,500);
  };
  const back = () => {
    // Shorts always exit to YouTube home, including before the player is ready.
    if(sectionForURL()==='shorts'||section==='shorts'||pending?.section==='shorts'){
      autoShorts=false;shortTransitionFrom=null;lastOpenedVideo='';clearIntent();
      startPending('home');location.replace('/');return true;
    }
    if(document.querySelector('[data-rivo-official-player]')){
      const watch=location.pathname==='/watch';window.__rivoOfficialPlayer?.close();clearIntent();
      if(watch){if(history.length>1)history.back();else location.replace(feedCache.routes.at(-1)?.route||'/');}
      return true;
    }
    if(host&&root.activeElement===$('query')){$('query').blur();return true;}
    return false;
  };
  window.__rivoYouTubePrototype={show,navigate,back,setActive:activateFeed,state:()=>({section,path:location.pathname,pending:pending?.section||null,count:root?.querySelectorAll('.card').length||0}),uninstall(){saveFeed();document.removeEventListener('visibilitychange',feedVisibility);window.removeEventListener('pagehide',feedPageHide);window.removeEventListener('pageshow',feedPageShow);closeHome();window.removeEventListener('rivo-official-player-closed',playerClosed);window.removeEventListener('rivo-official-player-presented',playerPresented);delete window.__rivoYouTubePrototype;}};
  show();return 'RIVO_YOUTUBE_NAVIGATION_READY';
})();

    // The official API creates and controls the unmodified official iframe.
    if(typeof window.YT?.Player!=='function'){
      const apiURL='https://www.youtube.com/iframe_api';
      const api=document.createElement('script');
      try{
        // A named policy accepts exactly the official script URL; no default policy or HTML sink.
        try { api.src=apiURL; }
        catch (_) {
          const policy=window.trustedTypes?.createPolicy('rivo-easy-youtube-api',{createScriptURL:value=>{if(value!==apiURL)throw new TypeError('Unexpected API URL');return value;}});
          if(!policy)throw new TypeError('Official API URL is not allowed');
          api.src=policy.createScriptURL(apiURL);
        }
        api.onerror=()=>{const r=document.querySelector('[data-rivo-you-tube-home]')?.shadowRoot;const s=r?.getElementById('status');if(s)s.textContent='공식 플레이어를 준비하지 못했어요. 다시 열어 주세요.';};
        document.head.appendChild(api);
      }catch(_){const s=document.querySelector('[data-rivo-you-tube-home]')?.shadowRoot.getElementById('status');if(s)s.textContent='공식 플레이어를 준비하지 못했어요. 다시 열어 주세요.';}
    }
  };
  if(document.body)install();
  else {
    const ready=new MutationObserver(()=>{if(document.body){ready.disconnect();install();}});
    ready.observe(document,{childList:true,subtree:true});
    document.addEventListener('DOMContentLoaded',()=>{ready.disconnect();if(!document.querySelector('[data-rivo-you-tube-home]'))install();},{once:true});
  }
})();
"""#
}
