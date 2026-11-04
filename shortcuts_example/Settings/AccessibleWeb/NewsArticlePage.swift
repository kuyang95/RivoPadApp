import Foundation

enum NewsArticlePage {
    static var source: String { "(()=>{\nwindow.__rivoNewsNativeLoading=true;\n" + NewsReadability.source + "\n" + controller + "\n})();" }
    static let loadingHTML = #"""
<!doctype html><html lang="ko"><head><meta name="viewport" content="width=device-width, initial-scale=1"><style>html,body{margin:0;width:100%;height:100%;background:#202124;overflow:hidden}</style></head><body><style>
      *{box-sizing:border-box;-webkit-text-size-adjust:100%;text-size-adjust:100%}
      .stage{position:absolute;inset:0;display:grid;place-items:center;padding:24px;overflow:auto;font:400 24px/1.6 system-ui,-apple-system,sans-serif;color:#F1F3F4}
      .card{width:100%;max-width:520px;padding:36px;border:0;border-radius:28px;background:linear-gradient(145deg,#2C2E32,#26282B);box-shadow:0 20px 64px #0003;animation:arrive .55s cubic-bezier(.22,1,.36,1) both}
      .brand{display:flex;align-items:center;gap:12px;margin-bottom:32px;font-size:18px;font-weight:600;color:#BDC5D0;letter-spacing:.04em}
      .icon{display:grid;place-items:center;width:44px;height:44px;border-radius:14px;background:#E6EF8714;color:#E6EF87}
      svg{width:26px;height:26px}
      .preview{margin-bottom:32px;animation:breathe 1.8s ease-in-out infinite}
      .line{height:12px;margin-top:14px;background:#464A50;border-radius:6px}
      .headline{height:20px;width:92%;margin-top:0;background:#60656D}.headline.short{width:67%;margin-top:14px}
      .meta{width:30%;height:9px;margin:22px 0 32px;background:#3D4147}
      .line.last{width:76%}
      .status{display:flex;align-items:center;gap:14px;padding-top:24px;border-top:1px solid #41444A;font-size:24px;line-height:1.5;font-weight:500;letter-spacing:-.02em}
      .spinner{width:20px;height:20px;flex:none;border:2px solid #E6EF8733;border-top-color:#E6EF87;border-radius:50%;animation:turn 1.1s linear infinite}
      @keyframes turn{to{transform:rotate(360deg)}}@keyframes breathe{50%{opacity:.5}}@keyframes arrive{from{opacity:0;transform:translateY(20px)}to{opacity:1;transform:translateY(0)}}
      @media(max-width:480px){.card{padding:28px;border-radius:24px}.status{font-size:22px}}
      @media(prefers-reduced-motion:reduce){.card,.preview,.spinner{animation:none}}
    </style><div class="stage"><section class="card" role="status" aria-live="polite" aria-label="기사를 불러오는 중">
      <div class="brand" aria-hidden="true"><span class="icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 7h8M8 11h8M8 15h3M8 18h8M14 15h2"/></svg></span>뉴스</div>
      <div class="preview" aria-hidden="true"><div class="line headline"></div><div class="line headline short"></div><div class="line meta"></div><div class="line"></div><div class="line"></div><div class="line last"></div></div>
      <div class="status" aria-hidden="true"><span class="spinner"></span>기사를 불러오는 중</div>
    </section></div></body></html>
"""#
    static let controller = #"""
// Rivo unified news reader. Only the current, accessible DOM is extracted locally.
(() => {
  if (window.top !== window || window.__rivoNewsArticle) return;
  let enabled = true, host, observer, queued = false, expired = false, mounted = false, attempts = 0;
  let originalViewports = null, readerViewport = null, loader;
  const reveal = () => {document.documentElement?.removeAttribute('data-rivo-news-preparing');loader?.remove();loader=null;};
  const deadline = setTimeout(() => {expired = true;reveal();},8000);
  const chromeCSS = `html[data-rivo-news-preparing]{zoom:1!important;background:#202124!important;color-scheme:dark!important}
    html[data-rivo-news-preparing] body{opacity:0!important;pointer-events:none!important}
    html[data-rivo-news-unified]{zoom:1!important;-webkit-text-size-adjust:100%!important;text-size-adjust:100%!important;width:auto!important;min-width:0!important;height:auto!important;margin:0!important;padding:0!important;overflow-x:hidden!important;background:#202124!important}
    html[data-rivo-news-unified] body{display:none!important}`;
  const showLoading = () => {
    if(loader||!enabled||expired||mounted)return;
    loader=document.createElement('div');loader.id='rivo-news-loading';
    loader.style.cssText='all:initial!important;position:fixed!important;inset:0!important;display:block!important;z-index:2147483647!important;background:#202124!important;';
    const shadow=loader.attachShadow({mode:'closed'});
    shadow.innerHTML=`<style>
      *{box-sizing:border-box;-webkit-text-size-adjust:100%;text-size-adjust:100%}
      .stage{position:absolute;inset:0;display:grid;place-items:center;padding:24px;overflow:auto;font:400 24px/1.6 system-ui,-apple-system,sans-serif;color:#F1F3F4}
      .card{width:100%;max-width:520px;padding:36px;border:0;border-radius:28px;background:linear-gradient(145deg,#2C2E32,#26282B);box-shadow:0 20px 64px #0003;animation:arrive .55s cubic-bezier(.22,1,.36,1) both}
      .brand{display:flex;align-items:center;gap:12px;margin-bottom:32px;font-size:18px;font-weight:600;color:#BDC5D0;letter-spacing:.04em}
      .icon{display:grid;place-items:center;width:44px;height:44px;border-radius:14px;background:#E6EF8714;color:#E6EF87}
      svg{width:26px;height:26px}
      .preview{margin-bottom:32px;animation:breathe 1.8s ease-in-out infinite}
      .line{height:12px;margin-top:14px;background:#464A50;border-radius:6px}
      .headline{height:20px;width:92%;margin-top:0;background:#60656D}.headline.short{width:67%;margin-top:14px}
      .meta{width:30%;height:9px;margin:22px 0 32px;background:#3D4147}
      .line.last{width:76%}
      .status{display:flex;align-items:center;gap:14px;padding-top:24px;border-top:1px solid #41444A;font-size:24px;line-height:1.5;font-weight:500;letter-spacing:-.02em}
      .spinner{width:20px;height:20px;flex:none;border:2px solid #E6EF8733;border-top-color:#E6EF87;border-radius:50%;animation:turn 1.1s linear infinite}
      @keyframes turn{to{transform:rotate(360deg)}}@keyframes breathe{50%{opacity:.5}}@keyframes arrive{from{opacity:0;transform:translateY(20px)}to{opacity:1;transform:translateY(0)}}
      @media(max-width:480px){.card{padding:28px;border-radius:24px}.status{font-size:22px}}
      @media(prefers-reduced-motion:reduce){.card,.preview,.spinner{animation:none}}
    </style><div class="stage"><section class="card" role="status" aria-live="polite" aria-label="기사를 불러오는 중">
      <div class="brand" aria-hidden="true"><span class="icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 7h8M8 11h8M8 15h3M8 18h8M14 15h2"/></svg></span>뉴스</div>
      <div class="preview" aria-hidden="true"><div class="line headline"></div><div class="line headline short"></div><div class="line meta"></div><div class="line"></div><div class="line"></div><div class="line last"></div></div>
      <div class="status" aria-hidden="true"><span class="spinner"></span>기사를 불러오는 중</div>
    </section></div>`;
    if(window.__rivoNewsNativeLoading){const style=document.createElement('style');style.textContent='.card{animation:none}';shadow.appendChild(style);}
    document.documentElement.appendChild(loader);
  };
  const css = `:host{all:initial;display:block;color:#F1F3F4;background:#202124;font-family:system-ui,-apple-system,sans-serif}
    *{box-sizing:border-box;-webkit-text-size-adjust:100%;text-size-adjust:100%}main{font-family:system-ui,-apple-system,sans-serif;font-style:normal;font-weight:400;text-align:left;max-width:900px;margin:0 auto;padding:clamp(24px,4vw,48px);overflow-wrap:anywhere}
    header{margin:0 0 32px}h1{font-size:34px;line-height:1.4;font-weight:700;margin:14px 0 20px;word-break:keep-all}
    .source,.meta,figcaption{font-size:18px;line-height:1.6;color:#BDC5D0}.meta{display:flex;flex-wrap:wrap;gap:8px 20px}
    article{font-size:26px;line-height:1.8;word-break:normal}p{margin:0 0 1.15em}h2{font-size:30px;line-height:1.5;margin:1.5em 0 .7em}h3,h4{font-size:28px;line-height:1.5}
    figure{margin:28px 0}img,video,iframe{display:block;max-width:100%;margin:24px auto;border:0}img{height:auto;border-radius:8px}iframe{width:100%;aspect-ratio:16/9}
    figcaption{margin:10px 0 28px}a{color:#E6EF87;text-underline-offset:4px}a:focus-visible{outline:3px solid #E6EF87;outline-offset:4px}
    blockquote{margin:24px 0;padding:8px 20px;border-left:4px solid #7F93AB}ul,ol{padding-left:1.5em}li{margin-bottom:.6em}
    table{display:block;max-width:100%;overflow:auto;border-collapse:collapse;font-size:24px}td,th{padding:12px;border:1px solid #7F93AB}pre{white-space:pre-wrap;font-size:24px}
    footer{margin:40px 0 0;padding-top:20px;border-top:1px solid #536176;font-size:18px;line-height:1.6}
    @media(max-width:480px){main{padding:24px}h1{font-size:34px}}
  `;
  const url = value => {if(!value?.trim())return null;try{const u=new URL(value,location.href);return /^https?:$/.test(u.protocol)?u.href:null}catch{return null}};
  const visible = e => e.getClientRects().length && e.getBoundingClientRect().bottom>0 && e.getBoundingClientRect().top<innerHeight && getComputedStyle(e).opacity!=='0' && !(e.tagName==='IFRAME'&&/[?&]size=invisible(?:&|$)/.test(e.getAttribute('src')||'')) && getComputedStyle(e).display!=='none' && getComputedStyle(e).visibility!=='hidden';
  const gate = () => [...document.querySelectorAll('dialog[open],[role="dialog"],[aria-modal="true"],[class*="paywall"],[id*="paywall"],iframe[src*="recaptcha"]')].some(visible);
  const allowed = new Set('P DIV SECTION ARTICLE H2 H3 H4 UL OL LI BLOCKQUOTE STRONG EM B I U S A BR HR FIGURE FIGCAPTION PICTURE IMG VIDEO SOURCE TABLE THEAD TBODY TR TD TH PRE CODE SUP SUB SPAN IFRAME'.split(' '));
  const adToken = /(?:^|[\s_-])(?:ad|ads|advert|advertisement|banner|sponsor|related|recommend|share|social|subscribe|copyright|reporter|byline)(?:$|[\s_-])|con_area_ad|FloatB_|광고|관련기사/i;
  const clean = (node, doc) => {
    if(node.nodeType===Node.TEXT_NODE)return doc.createTextNode(node.textContent);
    if(node.nodeType!==Node.ELEMENT_NODE||!allowed.has(node.tagName))return null;
    if(adToken.test((node.id||'')+' '+(node.getAttribute('class')||'')))return null;
    const tag=node.tagName;
    if(tag==='IFRAME'){
      const src=url(node.getAttribute('src'));if(!src||!/(^|\.)(youtube(?:-nocookie)?\.com|player\.vimeo\.com)$/.test(new URL(src).hostname))return null;
      const e=doc.createElement('iframe');e.src=src;e.title=node.title||'기사 동영상';e.loading='lazy';e.allowFullscreen=true;return e;
    }
    const caption=/caption|photo_desc|img_desc/i.test(node.getAttribute('class')||'');
    const e=doc.createElement(caption?'figcaption':['DIV','SECTION','ARTICLE'].includes(tag)?'div':tag.toLowerCase());
    if(tag==='IMG'){
      const src=url(node.getAttribute('data-src')||node.getAttribute('data-original')||node.getAttribute('data-lazy-src')||node.getAttribute('src'));
      if(!src||/logo|icon|banner|tracking|pixel|\/reporter\/|\/profile\/|staff_img|\/byline\/|font_?size|btn_|ico_/i.test(src)||(+node.getAttribute('width')>0&&+node.getAttribute('width')<100))return null;
      e.src=src;e.alt=node.getAttribute('alt')||'';e.loading='lazy';e.decoding='async';return e;
    }
    if(tag==='A'){const href=url(node.getAttribute('href'));if(href)e.href=href;}
    if(tag==='VIDEO'){const src=url(node.getAttribute('src'));if(src)e.src=src;e.controls=true;e.preload='metadata';}
    if(tag==='SOURCE'){
      const src=url(node.getAttribute('src'));if(!src)return null;
      e.src=src;const type=node.getAttribute('type');if(type)e.type=type;return e;
    }
    for(const child of node.childNodes){const c=clean(child,doc);if(c)e.appendChild(c);}
    if(tag==='VIDEO')return e.hasAttribute('src')||e.querySelector('source')?e:null;
    if(!e.textContent.trim()&&!e.querySelector('img,video,iframe')&&!['BR','HR'].includes(tag))return null;
    return e;
  };
  const restore = () => {if(readerViewport){readerViewport.remove();readerViewport=null;}if(originalViewports){for(const [meta,content] of originalViewports)meta.setAttribute('content',content);originalViewports=null;}document.documentElement.removeAttribute('data-rivo-news-unified');if(host)host.remove();host=null;mounted=false;reveal();};
  const render = () => {
    queued=false;if(!document.body)return;
    if(!enabled){restore();return;}
    if(mounted){
      document.documentElement.removeAttribute('data-rivo-news-unified');
      const blocked=gate();
      document.documentElement.setAttribute('data-rivo-news-unified','');
      if(blocked)restore();
      return;
    }
    if(gate()){window.__rivoNewsArticleStatus="gate";reveal();return;}
    if(document.body.querySelectorAll('*').length>40000){window.__rivoNewsArticleStatus="oversize";reveal();return;}
    let result, explicit, minLength=300;
    try{
      const copy=document.cloneNode(true);
      explicit=document.querySelector('[itemprop="articleBody"],#articleBody,#articleBodyContents,#article-view-content-div,#newsct_article,#dic_area,#pnlContent');
      if(!explicit&&/(^|\.)tvchosun\.com$/.test(location.hostname))explicit=document.querySelector('article .contents > .text-box')||document.querySelector('article');
      if(explicit&&visible(explicit)&&explicit.textContent.trim().length>=20){copy.body.replaceChildren(explicit.cloneNode(true));minLength=/(^|\.)tvchosun\.com$/.test(location.hostname)?20:120;}
      copy.querySelectorAll('script,style,noscript,button,input,select,textarea,.vjs-control-bar,.vjs-modal-dialog,nav,aside,[role="navigation"],[class*="related"],[class*="recommend"],.con_area_ad1,.FloatB_NSS,iframe[src*="ads.mtgroup.kr"],iframe[src*="ad.reople.co.kr"],iframe[src*="authanalysis.com"]').forEach(e=>e.remove());
      for(const h of copy.querySelectorAll('h2,h3,h4')){
        if(/^(이시간.*뉴스|관련.*기사|추천.*기사|많이.*뉴스|인기.*뉴스)$/.test(h.textContent.replace(/\s/g,''))){const block=h.closest('div,section,aside');if(block&&block.textContent.length<2000)block.remove();}
      }
      for(const a of copy.querySelectorAll('a'))if(/구글.*선호.*추가|^구독하기$|글자.*(크게|작게)|기자구독/.test(a.textContent.trim()))a.remove();
      result=new Readability(copy,{disableJSONLD:true,charThreshold:minLength,maxElemsToParse:40000}).parse();
    }catch{window.__rivoNewsArticleStatus="extract_error";reveal();return;}
    if((!result||result.length<minLength)&&explicit&&visible(explicit)&&explicit.querySelector('img')){
      result={title:document.querySelector('meta[property="og:title"]')?.content||document.title,content:explicit.innerHTML,length:explicit.textContent.length};
    }
    if(!result||result.length<minLength){window.__rivoNewsArticleStatus="short_extraction";if(expired)reveal();return;}
    const parsed=new DOMParser().parseFromString(result.content,'text/html');
    const body=document.createElement('article');
    for(const child of parsed.body.childNodes){const c=clean(child,document);if(c)body.appendChild(c);}
    if(!body.querySelector('img')){const lead=url(document.querySelector('meta[property="og:image"]')?.content);if(lead&&!/logo|icon|default|banner/i.test(lead)&&[...document.images].some(i=>{const original=url(i.getAttribute('data-src')||i.getAttribute('src'));return original&&new URL(original).pathname.split('/').pop()===new URL(lead).pathname.split('/').pop()&&i.getBoundingClientRect().width>=160&&!i.closest('header,nav,footer')})){const figure=document.createElement('figure'),img=document.createElement('img');img.src=lead;img.alt='';img.decoding='async';img.addEventListener('error',()=>figure.remove(),{once:true});figure.appendChild(img);body.prepend(figure);}}
    if(body.textContent.trim().length<minLength&&!body.querySelector('img')){window.__rivoNewsArticleStatus="short_clean";if(expired)reveal();return;}
    host=document.createElement('div');host.id='rivo-news-unified';
    host.style.cssText='all:initial!important;display:block!important;position:relative!important;width:100%!important;min-width:0!important;background:#202124!important;color:#F1F3F4!important;';
    const shadow=host.attachShadow({mode:'open'}),style=document.createElement('style');style.textContent=css;shadow.appendChild(style);
    const main=document.createElement('main'),header=document.createElement('header'),source=document.createElement('div');source.className='source';
    const publishers={"newsis.com": "뉴시스", "sbs.co.kr": "SBS", "khan.co.kr": "경향신문", "donga.com": "동아일보", "etoday.co.kr": "이투데이", "ohmynews.com": "오마이뉴스", "kmib.co.kr": "국민일보", "straightnews.co.kr": "스트레이트뉴스", "bloter.net": "블로터", "etnews.com": "전자신문", "zdnet.co.kr": "지디넷코리아", "kormedi.com": "코메디닷컴", "techm.kr": "테크M", "greenpostkorea.co.kr": "그린포스트코리아", "koscaj.com": "대한전문건설신문", "e2news.com": "이투뉴스", "todayenergy.kr": "투데이에너지", "housingherald.co.kr": "하우징헤럴드", "ebn.co.kr": "EBN", "newscape.co.kr": "뉴스케이프", "mt.co.kr": "머니투데이", "metroseoul.co.kr": "메트로", "viva100.com": "브릿지경제", "seoulfn.com": "서울파이낸스", "asiae.co.kr": "아시아경제", "chosun.com": "조선비즈", "joseilbo.com": "조세일보", "newsprime.co.kr": "프라임경제", "labortoday.co.kr": "매일노동뉴스", "lawtimes.co.kr": "법률신문", "veritas-a.com": "베리타스알파", "hangyo.com": "한국교육신문", "newsfc.co.kr": "금융소비자뉴스", "kbanker.co.kr": "대한금융신문", "fins.co.kr": "보험매일", "insjournal.co.kr": "보험저널", "ftoday.co.kr": "파이낸셜투데이", "insnews.co.kr": "한국보험신문", "aflnews.co.kr": "농수축산신문", "ikpnews.net": "한국농정신문", "mbn.co.kr": "MBN", "tvchosun.com": "TV조선", "sportschosun.com": "스포츠조선", "tenasia.co.kr": "텐아시아", "rapportian.com": "라포르시안", "doctorsnews.co.kr": "의협신문", "docdocdoc.co.kr": "청년의사", "pharmnews.com": "팜뉴스", "hitnews.co.kr": "히트뉴스", "nocutnews.co.kr": "노컷뉴스", "dailynk.com": "데일리NK", "mediaus.co.kr": "미디어스", "mediatoday.co.kr": "미디어오늘", "sisaweek.com": "시사위크", "sisajournal.com": "시사저널", "polinews.co.kr": "폴리뉴스", "pressian.com": "프레시안", "journalist.or.kr": "한국기자협회", "motorgraph.com": "모터그래프", "autoherald.co.kr": "오토헤럴드", "seoul.co.kr": "서울신문", "segye.com": "세계일보", "kado.net": "강원도민일보", "idomin.com": "경남도민일보", "daejonilbo.com": "대전일보", "incheonilbo.com": "인천일보", "jnilbo.com": "전남일보", "jjan.kr": "전북일보", "jejunews.com": "제주일보", "cctoday.co.kr": "충청투데이", "ihalla.com": "한라일보", "yna.co.kr": "연합뉴스", "it.donga.com": "IT동아"};
    const registered=Object.entries(publishers).sort((a,b)=>b[0].length-a[0].length).find(([d])=>location.hostname===d||location.hostname.endsWith('.'+d))?.[1];
    source.textContent=registered||document.querySelector('meta[property="og:site_name"]')?.content||location.hostname.replace(/^www\./,'');
    const h1=document.createElement('h1');h1.textContent=result.title||document.title;header.append(source,h1);
    const meta=document.createElement('div');meta.className='meta';
    if(result.byline){const byline=document.createElement('span');byline.textContent=result.byline.slice(0,160);meta.appendChild(byline);}
    const date=document.querySelector('meta[property="article:published_time"],meta[name="pubdate"],meta[itemprop="datePublished"]')?.content||document.querySelector('time[datetime]')?.getAttribute('datetime');
    if(date&&!isNaN(Date.parse(date))){const time=document.createElement('time');time.dateTime=date;time.textContent=new Date(date).toLocaleString('ko-KR');meta.appendChild(time);}
    header.appendChild(meta);const footer=document.createElement('footer'),link=document.createElement('a');link.href=location.href;link.textContent='기사 원문';
    link.addEventListener('click',e=>{e.preventDefault();enabled=false;restore();});footer.appendChild(link);
    main.append(header,body,footer);shadow.appendChild(main);document.documentElement.appendChild(host);
    originalViewports=[...document.querySelectorAll('meta[name="viewport"]')].map(meta=>[meta,meta.getAttribute('content')||'']);
    for(const [meta] of originalViewports)meta.content='width=device-width, initial-scale=1';
    if(!originalViewports.length){readerViewport=document.createElement('meta');readerViewport.name='viewport';readerViewport.content='width=device-width, initial-scale=1';(document.head||document.documentElement).appendChild(readerViewport);}
    document.documentElement.setAttribute('data-rivo-news-unified','');mounted=true;clearTimeout(deadline);reveal();
    window.__rivoNewsArticleResult={title:result.title,length:body.textContent.length,paragraphs:body.querySelectorAll('p').length,images:body.querySelectorAll('img').length};
  };
  const schedule = () => {if(queued||document.readyState==='loading')return;queued=true;setTimeout(render,120);};
  window.__rivoNewsArticle={set(value){enabled=!!value;if(!enabled)restore();else schedule();}};
  const start=()=>{
    if(!document.documentElement)return;
    if(!document.getElementById('rivo-news-article-style')){const s=document.createElement('style');s.id='rivo-news-article-style';s.textContent=chromeCSS;document.documentElement.appendChild(s);if(enabled&&!expired){document.documentElement.setAttribute('data-rivo-news-preparing','');showLoading();}}
    if(!document.body||observer)return;
    rootObserver?.disconnect();observer=new MutationObserver(schedule);observer.observe(document.body,{subtree:true,childList:true});
    // Wait for the parser's complete article to avoid publishing a partial paragraph.
    if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>{render();schedule();},{once:true});else render();
    window.addEventListener('load',schedule,{once:true});
  };
  let rootObserver;start();if(!observer){rootObserver=new MutationObserver(start);rootObserver.observe(document,{childList:true,subtree:true});}
})();
"""#
}
