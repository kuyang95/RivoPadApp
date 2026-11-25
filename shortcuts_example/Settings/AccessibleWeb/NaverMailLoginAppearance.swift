enum NaverMailLoginAppearance {
    static let source = #"""
// Style NAVER's visible form without changing how the page signs in.
(() => {
  'use strict';
  if (window !== window.top || location.origin !== 'https://nid.naver.com' ||
      location.pathname !== '/nidlogin.login' || window.__rivoNaverMailLogin) return;
  const theme = window.__rivoWebTheme;
  if (!theme) return;
  const scope = 'html[data-rivo-naver-mail-login]';
  const sheet = document.createElement('style');
  sheet.textContent = `
    ${scope}, ${scope} body {
      background:transparent!important;
      color:${theme.text}!important;
      color-scheme:dark;
    }
    ${scope} body,
    ${scope} :where(.wrap,.container,main.inner,.content,.content_wrap,form#frmNIDLogin) {
      box-sizing:border-box!important;
      width:100%!important; min-width:0!important; max-width:none!important;
      height:auto!important; min-height:0!important;
      margin:0!important; padding:0!important;
      background:transparent!important;
    }
    ${scope} main.inner {
      display:flex!important; flex-direction:column!important; justify-content:center!important;
      max-width:560px!important; min-height:var(--rivo-naver-login-height,100vh)!important;
      margin-inline:auto!important; padding:28px clamp(12px,5%,28px)!important;
    }
    ${scope} .header {
      box-sizing:border-box!important; width:100%!important; min-width:0!important;
      height:auto!important; margin:0 0 18px!important; padding:0!important;
    }
    ${scope} .header_inner {
      display:flex!important; justify-content:center!important; align-items:center!important;
      width:100%!important; min-width:0!important; padding:0!important;
    }
    ${scope} :is(.napp_auto_login,.napp_auto_bottom_area,.banner_wrap,.footer_copyright) {
      display:none!important;
    }
    ${scope} .form_list {
      display:flex!important; flex-direction:column!important; gap:14px;
      margin:0!important; padding:0!important; border:0!important; list-style:none;
    }
    ${scope} :is(.form_id,.form_pw) {
      box-sizing:border-box; width:100%!important; margin:0!important; padding:0!important;
      border:0!important;
    }
    ${scope} .form_data {
      box-sizing:border-box!important; width:100%!important; min-height:70px;
      height:auto!important; padding:8px 12px!important; border:1px solid ${theme.edge}!important;
      border-radius:18px!important; background:rgba(255,255,255,.06)!important;
    }
    ${scope} .form_data::before, ${scope} .form_data::after { display:none!important; }
    ${scope} .form_data:focus-within { border-color:${theme.link}!important; }
    ${scope} .input_label {
      position:static!important; display:block!important; width:auto!important; height:auto!important;
      margin:0!important; color:${theme.text}!important; font-size:15px!important;
      line-height:1.4!important; opacity:1!important; transform:none!important;
      clip:auto!important; clip-path:none!important; white-space:normal!important;
    }
    ${scope} .input_wrap {
      position:static!important; display:flex!important; align-items:center!important;
      width:100%!important; min-width:0!important; padding:0!important; border:0!important;
    }
    ${scope} :is(#id,#pw) {
      position:static!important; box-sizing:border-box!important; flex:1 1 0;
      width:0!important; min-width:0!important; min-height:38px; height:auto!important;
      margin:0!important; padding:2px 0!important; border:0!important;
      background:transparent!important; color:${theme.text}!important;
      caret-color:${theme.link}; font-size:19px!important; line-height:1.45!important;
    }
    ${scope} .btn_input {
      position:static!important; flex:0 0 auto; width:auto!important; height:auto!important;
      transform:none!important;
    }
    ${scope} .btn_input button { min-width:44px; min-height:44px; margin:0!important; }
    ${scope} .btn_form {
      width:100%!important; min-width:0!important; margin:16px 0 0!important; padding:0!important;
    }
    ${scope} .btn_login_dual { width:100%!important; margin:0!important; padding:0!important; }
    ${scope} .btn_login_dual .dual_item { flex:1 1 0; min-width:0!important; }
    ${scope} :is(#loginBtn_row,#loginBtn_column) {
      box-sizing:border-box!important; width:100%!important; min-height:60px; height:auto!important;
      padding:12px 16px!important; border:1px solid ${theme.text}!important; border-radius:18px!important;
      background:${theme.primary}!important; color:${theme.text}!important;
      font-size:20px!important; font-weight:700!important; line-height:1.4!important;
    }
    ${scope} :is(#loginBtn_row,#loginBtn_column) .text {
      color:inherit!important; font:inherit!important;
    }
    ${scope} :is(.find_wrap,.footer,.footer_list) {
      box-sizing:border-box!important; width:100%!important; min-width:0!important;
      height:auto!important; flex-wrap:wrap!important; justify-content:center!important;
    }
    ${scope} .find_wrap { margin-top:12px!important; padding:0!important; }
    ${scope} .footer { position:static!important; margin:8px 0 0!important; padding:0!important; }
    ${scope} :is(.find_wrap,.footer) a {
      display:inline-flex!important; align-items:center; min-height:44px;
      color:${theme.text}!important; font-size:14px!important;
    }
    ${scope} .find_wrap .find_text { color:${theme.text}!important; }
    ${scope} .find_wrap .find_text.green { color:${theme.link}!important; }
    ${scope} :is(.form_message,.form_message *) { white-space:normal!important; overflow-wrap:anywhere; }
    ${scope} .form_message.error { color:#FFB4AB!important; }
    ${scope} :is(a,button,input):focus-visible {
      outline:2px solid ${theme.link}!important; outline-offset:2px!important;
    }
  `;

  let enabled = true;
  let frame = 0;
  function sync() {
    frame = 0;
    const root = document.documentElement;
    if (!root) return;
    const form = document.getElementById('frmNIDLogin');
    const known = form?.method === 'post' && form.action === 'https://nid.naver.com/nidlogin.login' &&
      form.querySelector('.form_list .form_id input#id[autocomplete=username]') &&
      form.querySelector('.form_list .form_pw input#pw[autocomplete=current-password]') &&
      form.querySelector('#loginBtn_row,#loginBtn_column');
    const challenge = [...document.querySelectorAll('dialog,[role=dialog],iframe[src*=captcha i],#captcha,#chptcha,input[autocomplete=one-time-code]')]
      .some(element => element.getClientRects().length && getComputedStyle(element).visibility === 'visible');
    const active = enabled && !!known && !challenge;
    root.toggleAttribute('data-rivo-naver-mail-login', active);
    if (!active) {
      root.style.removeProperty('--rivo-naver-login-height');
      return;
    }
    if (!sheet.isConnected) (document.head || root).append(sheet);
    const zoom = parseFloat(getComputedStyle(root).zoom) || 1;
    const height = Math.round((window.visualViewport?.height || innerHeight) / zoom) + 'px';
    if (root.style.getPropertyValue('--rivo-naver-login-height') !== height) {
      root.style.setProperty('--rivo-naver-login-height', height);
    }
  }

  function schedule() {
    if (!frame) frame = requestAnimationFrame(sync);
  }

  window.__rivoNaverMailLogin = {set(value) { enabled = !!value; schedule(); }};
  new MutationObserver(schedule).observe(document, {
    subtree:true, childList:true, attributes:true,
    attributeFilter:['action','class','hidden','open','style','aria-hidden'],
  });
  window.addEventListener('pageshow', schedule);
  window.addEventListener('resize', schedule);
  window.addEventListener('rivo-page-zoom', schedule);
  window.visualViewport?.addEventListener('resize', schedule);
  schedule();
})();
"""#
}
