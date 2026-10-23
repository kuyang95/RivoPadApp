#if DEBUG
import WebKit

/// Bundled browser-only rules. No remote list downloads or browsing-data service.
@MainActor
enum BrowserAdBlocker {
    static let identifier = "rivo-browser-ads-v2"
    private static var compiled: WKContentRuleList?
    private static var preparing = false
    private static var waiting: [(WKContentRuleList?) -> Void] = []
    static func prepare(_ completion: @escaping (WKContentRuleList?) -> Void) {
        if let compiled { completion(compiled); return }
        waiting.append(completion)
        guard !preparing else { return }
        preparing = true
        WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: identifier) { rule, _ in
            Task { @MainActor in
                if let rule { finish(rule); return }
                WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: encodedRules) { rule, _ in
                    Task { @MainActor in finish(rule) }
                }
            }
        }
    }
    private static func finish(_ rule: WKContentRuleList?) {
        compiled = rule; preparing = false
        let callbacks = waiting; waiting.removeAll()
        callbacks.forEach { $0(rule) }
    }
    static func script(enabled: Bool) -> String { "window.__rivoAdBlockingEnabled=\(enabled);\n" + source }
    private static let encodedRules = #"""
[{"trigger":{"url-filter":"^https?://([^/]+\\.)?googlesyndication\\.com([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?doubleclick\\.net([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?googletagservices\\.com([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?googleadservices\\.com([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?adservice\\.google\\.com([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?adnxs\\.com([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?criteo\\.com([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?criteo\\.net([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?adop\\.cc([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?mobon\\.net([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?pubmatic\\.com([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?rubiconproject\\.com([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?casalemedia\\.com([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?adform\\.net([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?taboola\\.com([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?outbrain\\.com([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?dable\\.io([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?digitalcamp\\.co\\.kr([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?send\\.mci1\\.co\\.kr([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?adfit\\.kakao\\.com([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?ad\\.daum\\.net([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?ads\\.daum\\.net([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?naverads\\.net([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?veta\\.naver\\.com([/:]|$)","resource-type":["script","style-sheet","image","font","media","raw","svg-document"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]+\\.)?kidshankook\\.kr/adManager/","resource-type":["script","style-sheet","image","raw"],"unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"block"}},{"trigger":{"url-filter":".*","unless-domain":["youtube.com","*.youtube.com","youtube-nocookie.com","*.youtube-nocookie.com","accounts.google.com","*.accounts.google.com","recaptcha.net","*.recaptcha.net"]},"action":{"type":"css-display-none","selector":".ad-template,ins.adsbygoogle,ins.adsbyaiinad,.adsbykakao,[data-ad-slot],[data-ad-client],[data-google-query-id],[id^=google_ads_iframe],[id^=div-gpt-ad],.ad-container,.ad-banner,.advertisement,[id^=dablewidget_],.OUTBRAIN,#taboola-below-article-thumbnails,#tads,#bottomads,[data-text-ad],[data-ad-unit],[data-ad-unit-id],[data-ad-placement],[data-ad-format],.ad-slot,.ad-unit,.adsbyadop,[aria-label=\"Advertisement\"],[aria-label=\"advertisement\"],[aria-label=\"광고\"]"}}]
"""#
    private static let source = #"""
(() => {
  if(window.__rivoAdBlock){window.__rivoAdBlock.set(window.__rivoAdBlockingEnabled!==false);return;}
  if(!/^https?:$/.test(location.protocol))return;
  const rules={"version":2,"hosts":["googlesyndication.com","doubleclick.net","googletagservices.com","googleadservices.com","adservice.google.com","adnxs.com","criteo.com","criteo.net","adop.cc","mobon.net","pubmatic.com","rubiconproject.com","casalemedia.com","adform.net","taboola.com","outbrain.com","dable.io","digitalcamp.co.kr","send.mci1.co.kr","adfit.kakao.com","ad.daum.net","ads.daum.net","naverads.net","veta.naver.com"],"exemptHosts":["youtube.com","youtube-nocookie.com","accounts.google.com","recaptcha.net"],"paths":[{"host":"kidshankook.kr","prefix":"/adManager/"}],"selectors":[".ad-template","ins.adsbygoogle","ins.adsbyaiinad",".adsbykakao","[data-ad-slot]","[data-ad-client]","[data-google-query-id]","[id^=google_ads_iframe]","[id^=div-gpt-ad]",".ad-container",".ad-banner",".advertisement","[id^=dablewidget_]",".OUTBRAIN","#taboola-below-article-thumbnails","#tads","#bottomads","[data-text-ad]","[data-ad-unit]","[data-ad-unit-id]","[data-ad-placement]","[data-ad-format]",".ad-slot",".ad-unit",".adsbyadop","[aria-label=\"Advertisement\"]","[aria-label=\"advertisement\"]","[aria-label=\"광고\"]"]};
  const matches=(host,list)=>list.some(value=>host===value||host.endsWith('.'+value));
  if(matches(location.hostname,rules.exemptHosts))return;
  const selector=rules.selectors.join(',');
  let enabled=false,style=null,observer=null,scheduled=false;
  const roots=new Set(),hidden=new Map();
  const blockedURL=value=>{
    try {
      const url=new URL(value,location.href);
      return /^https?:$/.test(url.protocol) && (matches(url.hostname,rules.hosts) ||
        rules.paths.some(rule=>matches(url.hostname,[rule.host])&&url.pathname.startsWith(rule.prefix)));
    } catch(_) { return false; }
  };
  const restore=node=>{
    const previous=hidden.get(node);
    if(!previous)return;
    // Do not overwrite an inline display value the site changed in the meantime.
    if(node.style.getPropertyValue('display')==='none'&&node.style.getPropertyPriority('display')==='important') {
      if(previous.value)node.style.setProperty('display',previous.value,previous.priority);
      else node.style.removeProperty('display');
    }
    node.removeAttribute('data-rivo-ad-blocked');hidden.delete(node);
  };
  const update=node=>{
    const ad=node.matches(selector)||(node.matches('iframe[src]')&&blockedURL(node.getAttribute('src')));
    if(!ad){restore(node);return;}
    if(!hidden.has(node))hidden.set(node,{value:node.style.getPropertyValue('display'),priority:node.style.getPropertyPriority('display')});
    node.setAttribute('data-rivo-ad-blocked','');
    // Inline display also works on documents that reject injected style elements.
    node.style.setProperty('display','none','important');
  };
  const scan=root=>{
    if(root.nodeType!==1)return;
    update(root);
    root.querySelectorAll(selector+',iframe[src],[data-rivo-ad-blocked]').forEach(update);
  };
  const schedule=root=>{
    if(!enabled)return;
    roots.add(root);
    if(roots.size>64){roots.clear();roots.add(document.documentElement);}
    if(scheduled)return;scheduled=true;
    requestAnimationFrame(()=>{
      scheduled=false;
      if(enabled){
        for(const node of hidden.keys())if(!node.isConnected)restore(node);
        for(const node of roots)if(node?.isConnected)scan(node);
      }
      roots.clear();
    });
  };
  const set=value=>{
    enabled=!!value;
    if(!document.documentElement){document.addEventListener('DOMContentLoaded',()=>set(enabled),{once:true});return;}
    if(!style){style=document.createElement('style');style.setAttribute('data-rivo-ad-style','');}
    if(!style.isConnected)document.documentElement.appendChild(style);
    style.textContent=enabled?selector+',[data-rivo-ad-blocked]{display:none!important;}':'';
    observer?.disconnect();roots.clear();
    if(!enabled){for(const node of hidden.keys())restore(node);return;}
    scan(document.documentElement);
    observer=new MutationObserver(records=>{
      for(const record of records){
        if(record.type==='attributes')schedule(record.target);
        else {for(const node of record.addedNodes)if(node.nodeType===1)schedule(node);if(record.removedNodes.length)schedule(null);}
      }
    });
    observer.observe(document.documentElement,{childList:true,subtree:true,attributes:true,
      attributeFilter:['src','class','id','aria-label','data-ad-slot','data-ad-client','data-google-query-id','data-ad-unit','data-ad-unit-id','data-ad-placement','data-ad-format']});
  };
  window.__rivoAdBlock={set};set(window.__rivoAdBlockingEnabled!==false);
})();
"""#
}
#endif
