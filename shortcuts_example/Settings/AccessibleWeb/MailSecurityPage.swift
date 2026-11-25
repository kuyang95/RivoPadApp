import Foundation

enum MailSecurityPage {
    static let source = #"""
// Presentation only. Keep NAVER's challenge, audio, inputs and submit handlers intact.
(() => {
  'use strict';
  if (window.top !== window || location.protocol !== 'https:' || location.hostname !== 'nid.naver.com' || !['/nidlogin.login','/nidlogin.rcaptcha'].includes(location.pathname)) return;
  if (window.__rivoMailSecurity) return;
  const theme = window.__rivoWebTheme || {text:'#F5F3E9',link:'#E6EF87'};
  const lang = (document.documentElement?.lang || navigator.language || 'ko').toLowerCase();
  const words = lang.startsWith('ja') ? {title:'セキュリティ確認',listen:'認証コードを聞く',replay:'もう一度聞く',answer:'認証コード'} :
    lang.startsWith('en') ? {title:'Security check',listen:'Play verification code',replay:'Play code again',answer:'Verification code'} :
    {title:'보안 확인',listen:'인증번호 듣기',replay:'다시 듣기',answer:'인증번호'};
  let enabled = true, active = false, frame = 0, sheet, title, moved;
  const attributes = new Map();
  const root = () => document.documentElement;
  const visible = n => {const b=n.getBoundingClientRect(),s=getComputedStyle(n);return b.width>2&&b.height>2&&s.display!=='none'&&s.visibility!=='hidden';};
  function mark(node, name, value) {
    if (!attributes.has(node)) attributes.set(node,new Map());
    const saved=attributes.get(node);
    if (!saved.has(name)) saved.set(name,{before:node.getAttribute(name),after:value});
    if(node.getAttribute(name)!==value)node.setAttribute(name,value);
  }
  function deactivate() {
    root()?.removeAttribute('data-rivo-mail-security');
    root()?.removeAttribute('data-rivo-mail-security-audio');
    root()?.style.removeProperty('--rivo-mail-security-width');root()?.style.removeProperty('--rivo-mail-security-height');
    title?.remove(); title=null;
    for(const [node,saved] of attributes)for(const [name,state] of saved)if(node.getAttribute(name)===state.after){if(state.before===null)node.removeAttribute(name);else node.setAttribute(name,state.before);}
    attributes.clear();
    if(moved){if(moved.parent.isConnected&&moved.node.isConnected)moved.parent.insertBefore(moved.node,moved.next?.parentNode===moved.parent?moved.next:null);moved=null;}
    active=false;
  }
  function geometry() {
    const zoom=parseFloat(getComputedStyle(root()).zoom)||1;
    for(const [name,value] of [['width',(window.visualViewport?.width||innerWidth)/zoom],['height',(window.visualViewport?.height||innerHeight)/zoom]]){
      const key=`--rivo-mail-security-${name}`,next=`${Math.round(value*100)/100}px`;
      if(root().style.getPropertyValue(key)!==next)root().style.setProperty(key,next);
    }
  }
  function mount() {
    if(sheet?.isConnected)return;
    sheet=document.createElement('style');sheet.setAttribute('data-rivo-mail-security-style','');
    sheet.textContent=`
      html[data-rivo-mail-security] {background:transparent!important;color-scheme:dark;}
      html[data-rivo-mail-security] body {box-sizing:border-box!important;width:var(--rivo-mail-security-width,100%)!important;min-width:0!important;min-height:var(--rivo-mail-security-height,100vh)!important;height:auto!important;margin:0!important;background:transparent!important;color:${theme.text}!important;}
      html[data-rivo-mail-security] :is(.wrap,.container,.content,.content_wrap,form.form) {box-sizing:border-box!important;position:static!important;width:100%!important;min-width:0!important;max-width:none!important;height:auto!important;min-height:0!important;margin:0!important;padding:0!important;background:transparent!important;}
      html[data-rivo-mail-security] main.inner {box-sizing:border-box!important;width:100%!important;min-width:0!important;max-width:568px!important;margin:0 auto!important;padding:32px 24px!important;}
      html[data-rivo-mail-security] :is(.header,.u_skip,.top_wrap) {display:none!important;}
      html[data-rivo-mail-security] [data-rivo-mail-security-title] {margin:0 0 24px!important;color:${theme.text}!important;font-size:30px!important;line-height:1.5!important;font-weight:600!important;text-align:center;overflow-wrap:anywhere;}
      html[data-rivo-mail-security] :is(.captcha_wrap,.captcha_inner,.captcha_form,.captcha_voice,.btn_form,.btn_login_dual,.dual_item) {box-sizing:border-box!important;position:static!important;width:100%!important;min-width:0!important;max-width:100%!important;height:auto!important;margin:0!important;padding:0!important;background:transparent!important;}
      html[data-rivo-mail-security] :is(.captcha_image,.top_tip,.captcha_text,#rcapt .captcha_form,#swap_captcha) {display:none!important;}
      html[data-rivo-mail-security]:not([data-rivo-mail-security-audio]) .btn_form {display:none!important;}
      html[data-rivo-mail-security] .captcha_form {display:flex!important;flex-direction:column!important;align-items:stretch!important;}
      html[data-rivo-mail-security] #chptcha {box-sizing:border-box!important;flex:none!important;position:static!important;width:100%!important;min-width:0!important;max-width:100%!important;min-height:76px!important;height:auto!important;margin:0!important;padding:18px!important;border:1px solid #b2b4ae!important;border-radius:22px!important;background:rgba(255,255,255,.06)!important;color:${theme.text}!important;-webkit-text-fill-color:${theme.text}!important;caret-color:${theme.link}!important;font-size:22px!important;line-height:1.5!important;}
      html[data-rivo-mail-security] #chptcha::placeholder {color:${theme.text}!important;opacity:.75!important;}
      html[data-rivo-mail-security] :is(#voice,#play_audio) {
        box-sizing:border-box!important;display:grid!important;place-items:center;position:relative!important;
        width:min(112px,100%)!important;height:auto!important;min-height:0!important;aspect-ratio:1;
        margin:0 auto 12px!important;padding:0!important;border:0!important;border-radius:50%!important;
        background:${theme.link}!important;color:#101010!important;
      }
      html[data-rivo-mail-security] :is(#voice,#play_audio)::before {
        content:''!important;position:static!important;display:block!important;
        width:36%!important;height:36%!important;margin:0 0 0 7%!important;
        background:#101010!important;clip-path:polygon(0 0,100% 50%,0 100%);
        transform:none!important;
      }
      html[data-rivo-mail-security] :is(#voice,#play_audio)::after {display:none!important;}
      html[data-rivo-mail-security][data-rivo-mail-security-audio] #voice {display:none!important;}
      html[data-rivo-mail-security] .captcha_voice {display:flex!important;flex-direction:column!important;align-items:center!important;margin:0 0 14px!important;}
      html[data-rivo-mail-security] .captcha_voice a {display:inline-flex!important;align-items:center;min-height:48px;color:${theme.text}!important;font-size:16px!important;line-height:1.5!important;}
      html[data-rivo-mail-security] .captcha_voice a::before {display:none!important;}
      html[data-rivo-mail-security] .captcha_message {margin:16px 0!important;color:#FFB4AB!important;}
      html[data-rivo-mail-security] .captcha_message * {color:inherit!important;font-size:inherit!important;line-height:inherit!important;}
      html[data-rivo-mail-security] .btn_form {margin:24px 0 0!important;}
      html[data-rivo-mail-security] .btn_login_dual {list-style:none!important;}
      html[data-rivo-mail-security] .btn_done {box-sizing:border-box!important;width:100%!important;min-width:0!important;min-height:68px!important;height:auto!important;margin:0!important;padding:18px 24px!important;border:0!important;border-radius:22px!important;background:${theme.link}!important;color:#101010!important;font-size:22px!important;line-height:1.5!important;}
      html[data-rivo-mail-security] .btn_done * {color:inherit!important;-webkit-text-fill-color:inherit!important;font-size:inherit!important;line-height:inherit!important;}
      html[data-rivo-mail-security] .footer {box-sizing:border-box!important;position:static!important;display:block!important;width:100%!important;max-width:568px!important;margin:0 auto!important;padding:0 24px 24px!important;color:${theme.text}!important;}
      html[data-rivo-mail-security] .footer_list {display:flex!important;flex-wrap:wrap;justify-content:center;gap:12px;padding:0!important;margin:0!important;}
      html[data-rivo-mail-security] .footer :is(a,span) {color:${theme.text}!important;font-size:14px!important;line-height:1.5!important;}
      html[data-rivo-mail-security] .footer a {display:inline-flex;align-items:center;min-height:48px;}
      html[data-rivo-mail-security] :is(button,input,a):focus-visible {outline:3px solid ${theme.link}!important;outline-offset:3px!important;}
      html[data-rivo-mail-security] [data-rivo-mail-security-title]:focus {outline:none!important;}
      @media(prefers-reduced-motion:reduce) {html[data-rivo-mail-security] * {transition:none!important;animation:none!important;scroll-behavior:auto!important;}}
    `;
    root().append(sheet);
  }
  function sync() {
    frame=0;if(!root())return;
    if(location.protocol!=='https:'||location.hostname!=='nid.naver.com'||!['/nidlogin.login','/nidlogin.rcaptcha'].includes(location.pathname)){if(active)deactivate();return;}
    const form=document.getElementById('frmNIDLogin'),image=document.getElementById('rcapt'),sound=document.getElementById('rcapt_sound');
    const voice=document.getElementById('voice'),play=document.getElementById('play_audio'),swap=document.getElementById('swap_captcha');
    const answer=document.getElementById('captcha'),spoken=document.getElementById('chptcha'),confirm=document.getElementById('log.login');
    let action;try{action=new URL(form?.action)}catch{}
    const known=form?.method.toLowerCase()==='post'&&action?.origin===location.origin&&action.pathname==='/nidlogin.rcaptcha'&&image&&sound&&voice?.tagName==='BUTTON'&&play?.tagName==='BUTTON'&&swap?.tagName==='BUTTON'&&confirm?.tagName==='BUTTON'&&[answer,spoken].every(n=>n instanceof HTMLInputElement&&n.type==='text'&&n.form===form)&&[image,sound,voice,play,swap,confirm].every(n=>form.contains(n));
    const unknown=[...document.querySelectorAll('dialog,[role=dialog],iframe,input:not([type=hidden]):not(#captcha):not(#chptcha)')].some(visible);
    if(!enabled||!known||unknown){if(active)deactivate();return;}
    for(const node of attributes.keys())if(!node.isConnected)attributes.delete(node);
    if(moved && moved.node!==voice) { deactivate(); }
    mount();geometry();root().setAttribute('data-rivo-mail-security','');
    if(!title?.isConnected){
      title=document.createElement('h1');title.setAttribute('data-rivo-mail-security-title','');title.tabIndex=-1;title.textContent=words.title;
      form.before(title);
    }
    // Keep the provider's audio control in its original mode panel.
    if(!moved){moved={node:voice,parent:voice.parentNode,next:voice.nextSibling};image.parentNode.insertBefore(voice,image);}
    mark(voice,'aria-label',words.listen);
    mark(play,'aria-label',words.replay);
    mark(spoken,'aria-label',words.answer);
    mark(spoken,'placeholder',words.answer);
    root().toggleAttribute('data-rivo-mail-security-audio', visible(spoken));
    for(const error of form.querySelectorAll('.captcha_message'))if(!error.hasAttribute('role'))mark(error,'role','alert');
    if(!active){active=true;window.scrollTo(0,0);if(![answer,spoken].includes(document.activeElement))title.focus({preventScroll:true});}
  }
  function schedule(){if(!frame)frame=requestAnimationFrame(sync);}
  window.__rivoMailSecurity={set(value){enabled=!!value;schedule();}};
  new MutationObserver(schedule).observe(document,{childList:true,subtree:true,attributes:true,attributeFilter:['class','style','hidden','type','aria-hidden']});
  document.addEventListener('DOMContentLoaded',schedule);window.addEventListener('pageshow',schedule);
  window.addEventListener('resize',schedule);window.addEventListener('rivo-page-zoom',schedule);window.visualViewport?.addEventListener('resize',schedule);
  schedule();
})();
"""#
}
