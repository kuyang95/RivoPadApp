import Foundation

enum EasyMailPage {
    static let storeIdentifier = UUID(uuidString: "B3A4C84E-C53A-4E41-8B6F-F89CF68370E1")!
    static let source = #"""
(() => {
  'use strict';
  if (window.top !== window || location.protocol !== 'https:') return;
  const host = location.hostname.toLowerCase();
  const domains = ['mail.naver.com','m.mail.naver.com','mail.daum.net','m.mail.daum.net','mail.kakao.com','m.mail.kakao.com','mail.nate.com','m.mail.nate.com','mail2.nate.com','mail3.nate.com','mail4.nate.com','mail.google.com','outlook.live.com','outlook.office.com','outlook.office365.com','www.icloud.com','mail.yahoo.com'];
  if (!domains.includes(host)) return;
  const naverInbox = (host === 'mail.naver.com' || host === 'm.mail.naver.com') && !location.port;
  const theme = window.__rivoWebTheme;
  const layout = '.wrap:has(.contents_area > .mail_list_wrap > .mail_list)';
  const inbox = `html[data-rivo-easy-mail] ${layout}`;
  const inboxStyle = naverInbox && theme ? `
    ${inbox} {
      --rivo-inbox-heading: ${theme.text};
      --rivo-inbox-background: ${theme.bg};
      --rivo-inbox-surface: ${theme.surface};
      --rivo-inbox-accent: ${theme.link};
      --rivo-inbox-action: ${theme.primary};
      background-color:var(--rivo-inbox-background)!important;
    }
    html[data-rivo-easy-mail][data-rivo-launcher-widget] ${layout} {
      background-color:transparent!important;
    }
    ${inbox} .main_header {
      background-color:var(--rivo-inbox-background)!important;
      border-bottom:1px solid color-mix(in srgb,var(--rivo-inbox-heading) 20%,transparent);
    }
    ${inbox} .main_header .menu_title {
      font-size:clamp(20px,5.5vw,26px)!important;
      font-weight:700!important;
    }
    ${inbox} .main_header :is(.button_svg_search,.button_lnb) { min-width:44px; }
    ${inbox} .contents_header .smart_tab_area,
    ${inbox} .mail_list_wrap > .mail_list {
      box-sizing:border-box;
      width:100%;
      max-width:760px;
      margin-inline:auto;
      padding-inline:clamp(10px,3vw,24px);
    }
    ${inbox} .mail_list > .mail_item {
      box-sizing:border-box;
      margin-block:8px;
      border:1px solid color-mix(in srgb,var(--rivo-inbox-heading) 22%,transparent)!important;
      border-radius:16px;
      background-color:var(--rivo-inbox-surface)!important;
    }
    ${inbox} .mail_list > .mail_item:focus-within {
      border-color:var(--rivo-inbox-accent)!important;
    }
    ${inbox} .mail_list .mail_title_link {
      color:var(--rivo-inbox-heading)!important;
      -webkit-text-fill-color:var(--rivo-inbox-heading)!important;
      font-size:clamp(17px,4.5vw,20px)!important;
      line-height:1.35!important;
    }
    ${inbox} .mail_list .button_sender { font-size:15px!important; }
    ${inbox} .mail_list .mail_date { font-size:13px!important; }
    ${inbox} .contents_area .button_mail_write {
      background-color:var(--rivo-inbox-action)!important;
      border:1px solid var(--rivo-inbox-heading)!important;
      border-radius:50%;
    }
    ${inbox} :is(a,button,input,[tabindex]):focus-visible {
      outline:3px solid var(--rivo-inbox-accent)!important;
      outline-offset:2px!important;
    }
  ` : '';
  const detailLayout = '.wrap.sub_page:has(.contents_area.is_read .mail_view_inner)';
  const detail = `html[data-rivo-easy-mail] ${detailLayout}`;
  const actions = `${detail}[data-rivo-mail-actions]`;
  const detailStyle = naverInbox && theme ? `
    ${detail}[data-rivo-web-base][data-rivo-web-surface] {
      background-color:${theme.bg}!important;
    }
    html[data-rivo-easy-mail][data-rivo-launcher-widget] ${detailLayout} {
      background-color:transparent!important;
    }
    ${detail} > header {
      top:auto!important;
      bottom:0!important;
    }
    ${detail} > .container {
      padding-top:0!important;
      padding-bottom:60px!important;
    }
    ${detail} > header .sub_header {
      box-sizing:border-box;
      padding-inline:16px!important;
      background-color:${theme.surface}!important;
      border-top:1px solid color-mix(in srgb,${theme.text} 25%,transparent);
    }
    ${detail} > header .sub_header .button_wrap { margin-inline-start:auto!important; }
    ${detail} > header .sub_header .button_back { display:none!important; }
    ${detail} .button_view_top { bottom:68px!important; }
    ${detail} .mail_view_header,
    ${detail} .mail_view_body {
      box-sizing:border-box;
      width:min(100%, 760px);
      margin-inline:auto!important;
      padding-inline:clamp(14px,5%,24px)!important;
    }
    ${detail} .mail_view_header {
      padding-block:16px!important;
      border-bottom:1px solid color-mix(in srgb,${theme.text} 30%,transparent);
    }
    ${detail} .mail_view_header .mail_title {
      margin-bottom:12px!important;
      font-size:24px!important;
      line-height:1.38!important;
      font-weight:700!important;
      white-space:normal!important;
      overflow-wrap:anywhere;
    }
    ${detail} .mail_option {
      display:grid!important;
      gap:6px!important;
      padding:0!important;
    }
    ${detail} .mail_option > :is(.button_svg_fold,.button_svg_unfold) { display:none!important; }
    ${detail} .mail_option_item {
      display:grid!important;
      grid-template-columns:4.25em minmax(0,1fr);
      align-items:start;
      column-gap:10px;
      height:auto!important;
      min-height:0!important;
      margin:0!important;
      padding:0!important;
      font-size:13px!important;
    }
    ${detail} .mail_option_item .title_area {
      width:auto!important;
      min-width:0!important;
      padding:6px 0 0!important;
      line-height:1.5!important;
    }
    ${detail} .mail_option_item .option_title {
      display:block!important;
      margin:0!important;
      padding:0!important;
      font-size:13px!important;
      line-height:1.5!important;
      font-weight:400!important;
      opacity:.8;
    }
    ${detail} .mail_option_item .option_area {
      display:flex!important;
      flex-wrap:wrap;
      align-items:flex-start;
      gap:0 8px;
      width:auto!important;
      min-width:0!important;
      height:auto!important;
      margin:0!important;
      padding:0!important;
    }
    ${detail} .mail_option .button_user {
      max-width:100%;
      min-height:var(--rivo-mail-control-min,44px)!important;
      margin:0!important;
      padding:4px 0!important;
      background:transparent!important;
      border:0!important;
      font-size:14px!important;
      line-height:1.45!important;
      white-space:normal!important;
      overflow-wrap:anywhere;
      text-align:start;
    }
    ${detail} .mail_option_item.sender .button_user {
      font-size:16px!important;
      font-weight:600!important;
    }
    ${detail} .mail_view_header .info_area {
      margin-top:10px!important;
      padding:0!important;
    }
    ${detail} .mail_view_header .info_area .date {
      flex:1 1 180px;
      min-width:0;
      padding:0!important;
      font-size:14px!important;
      line-height:1.5!important;
      overflow-wrap:anywhere;
    }
    ${actions} .mail_view_header .info_area {
      display:flex!important;
      flex-wrap:wrap;
      align-items:center;
      gap:4px 12px;
    }
    ${actions} .mail_view_header .info_area > .button_group {
      display:none!important;
    }
    ${actions} > .container { padding-bottom:0!important; }
    ${actions} .button_view_top { bottom:8px!important; }
    ${actions} > header {
      top:0!important;
      bottom:auto!important;
      pointer-events:none!important;
      background:transparent!important;
      box-shadow:none!important;
      border:0!important;
    }
    ${actions} > header .sub_header {
      background:transparent!important;
      box-shadow:none!important;
      border:0!important;
    }
    ${actions} > header .button_task_wrap > .button_task {
      visibility:hidden!important;
    }
    ${actions} > header .button_task_wrap > :not(.button_task) {
      pointer-events:auto;
    }
    ${actions} .rivo-mail-actions-toggle {
      box-sizing:border-box;
      flex:0 0 auto;
      margin-inline-start:auto!important;
      padding:4px 8px!important;
      border:0!important;
      border-radius:8px!important;
      background:transparent!important;
      color:__RIVO_MAIL_ACTION_FILL__!important;
      -webkit-text-fill-color:__RIVO_MAIL_ACTION_FILL__!important;
      min-height:var(--rivo-mail-control-min,44px)!important;
      min-width:56px!important;
      white-space:normal!important;
      font-size:14px!important;
      line-height:1.5!important;
      font-weight:600!important;
      cursor:pointer;
    }
    ${detail} .mail_view_body > :is(.spam_warning,.button_fit_contents_wrap) {
      margin-inline:0!important;
    }
    ${detail} .mail_view_body > .spam_warning {
      border-radius:12px;
      border:1px solid color-mix(in srgb,#ff948e 60%,transparent);
      background-color:color-mix(in srgb,#ff948e 18%,${theme.surface})!important;
    }
    ${detail} .mail_view_contents {
      padding:18px 0!important;
    }
    ${detail} .mail_view_contents_inner {
      font-size:17px;
      overflow-wrap:anywhere;
    }
    ${detail} .mail_view_contents_inner p[data-rivo-mail-plain-paragraph],
    ${detail} .mail_view_contents_inner [data-rivo-mail-layout-surface] {
      background-color:transparent!important;
    }
    ${detail} .mail_view_pagination { display:none!important; }
  ` : '';
  window.__rivoMailHost = true;
  if (window.__rivoEasyMailInstalled) return;
  window.__rivoEasyMailInstalled = true;
  let style, enabled = true;
  const opensReader = naverInbox && theme && /^\/v2\/read\/\d+\/\d+\/?$/.test(location.pathname);
  const preparingReader = 'data-rivo-mail-reader-preparing';
  let readerDeadline;
  const showReader = () => {
    clearTimeout(readerDeadline);
    document.documentElement?.removeAttribute(preparingReader);
  };
  const layoutSurface = 'data-rivo-mail-layout-surface';
  const neutralBackground = value => {
    if (!value) return false;
    const color = document.createElement('span').style;
    color.color = value;
    if (['white','black','gray','grey','silver','gainsboro','whitesmoke','darkgray','darkgrey','lightgray','lightgrey'].includes(color.color)) return true;
    const rgb = color.color.match(/^rgba?\(([^)]+)\)$/)?.[1].split(',').map(Number);
    return !!rgb && rgb.length >= 3 && (rgb.length < 4 || rgb[3] >= .95) &&
      Math.max(...rgb.slice(0,3)) - Math.min(...rgb.slice(0,3)) <= 12;
  };
  const syncMailLayoutSurfaces = () => {
    const body = document.querySelector(`${detailLayout} .mail_view_contents_inner`);
    if (!enabled || !body) return;
    const bodyWidth = body.getBoundingClientRect().width;
    if (!bodyWidth) return;
    body.querySelectorAll('table,td,div').forEach(element => {
      const table = element.tagName === 'TABLE' ? element : element.closest('table');
      const singleColumn = element.tagName === 'TABLE'
        ? element.rows.length > 0 && [...element.rows].every(row => row.cells.length === 1)
        : element.tagName === 'TD' ? element.parentElement.cells?.length === 1 : element.childElementCount === 1;
      const decoration = getComputedStyle(element);
      const background = element.style.backgroundColor || element.getAttribute('bgcolor');
      const layout = singleColumn && neutralBackground(background) &&
        !element.closest('[role=table],[role=grid],blockquote,[role=note],[role=alert]') &&
        !(table && (table.caption || [...table.rows].some(row => [...row.cells].some(cell => cell.tagName === 'TH')))) && decoration.backgroundImage === 'none' &&
        decoration.boxShadow === 'none' && element.getBoundingClientRect().width >= bodyWidth * .85 &&
        [decoration.borderTopWidth,decoration.borderRightWidth,decoration.borderBottomWidth,decoration.borderLeftWidth]
          .every(width => parseFloat(width) === 0);
      element.toggleAttribute(layoutSurface, layout);
    });
  };
  const plainParagraph = 'data-rivo-mail-plain-paragraph';
  const hasPlainWhiteBackground = (paragraph) => {
    const color = paragraph.style.backgroundColor.replace(/\s/g, '').toLowerCase();
    if (!['white', 'rgb(255,255,255)', 'rgba(255,255,255,1)'].includes(color)) return false;
    if (paragraph.closest('table, [role=table], [role=grid], blockquote, [role=note], [role=alert]') ||
        paragraph.querySelector('img, picture, svg, video, canvas, table') ||
        (paragraph.style.backgroundImage && paragraph.style.backgroundImage !== 'none')) return false;
    const paint = getComputedStyle(paragraph);
    return paint.backgroundImage === 'none' && paint.boxShadow === 'none' &&
      [paint.borderTopWidth, paint.borderRightWidth, paint.borderBottomWidth, paint.borderLeftWidth]
        .every(width => parseFloat(width) === 0);
  };
  const syncMailParagraphs = () => {
    if (!enabled || !location.pathname.startsWith('/v2/read/')) return;
    syncMailLayoutSurfaces();
    document.querySelectorAll(`${detailLayout} .mail_view_contents_inner p:is([style],[${plainParagraph}])`)
      .forEach(paragraph => paragraph.toggleAttribute(plainParagraph, hasPlainWhiteBackground(paragraph)));
  };
  let readActions;
  const clearReadActions = () => {
    readActions?.page.removeAttribute('data-rivo-mail-actions');
    readActions?.page.style.removeProperty('--rivo-mail-control-min');
    readActions?.toggle.remove();
    readActions = undefined;
  };
  const syncReadActions = () => {
    const page = enabled && location.pathname.startsWith('/v2/read/') ? document.querySelector(detailLayout) : null;
    const group = page?.querySelector(':scope > header .sub_header .button_wrap:has(.svg_etc)');
    const info = page?.querySelector('.mail_view_header .info_area:has(.toggle_bookmark_wrap)');
    const bookmark = info?.querySelector('input.toggle_bookmark');
    if (!group || !bookmark) {
      clearReadActions();
      return;
    }
    // Keep a 44px visual touch target; text still follows the user's page zoom.
    let zoom = page.currentCSSZoom;
    if (!Number.isFinite(zoom) || zoom <= 0) {
      zoom = 1;
      for (let node = page; node; node = node.parentElement) zoom *= parseFloat(getComputedStyle(node).zoom) || 1;
    }
    const controlMin = `${44 / zoom}px`;
    if (page.style.getPropertyValue('--rivo-mail-control-min') !== controlMin) {
      page.style.setProperty('--rivo-mail-control-min', controlMin);
    }
    if (readActions?.page === page && readActions.group === group && readActions.bookmark === bookmark &&
        readActions.address === location.href && readActions.toggle.parentNode === info) return;
    clearReadActions();
    page.style.setProperty('--rivo-mail-control-min', controlMin);
    const language = (navigator.language || document.documentElement.lang).split('-')[0].toLowerCase();
    const toggle = document.createElement('button');
    toggle.type = 'button';
    toggle.className = 'rivo-mail-actions-toggle';
    toggle.textContent = {en:'Actions',ja:'操作'}[language] || '작업';
    toggle.setAttribute('aria-haspopup', 'dialog');
    const state = {page, group, bookmark, toggle, address:location.href, ticket:null};
    toggle.addEventListener('click', event => {
      if (!event.isTrusted || readActions !== state) return;
      state.ticket = crypto.randomUUID();
      location.href = 'rivo-browser://mail-actions';
    });
    info.append(toggle);
    page.setAttribute('data-rivo-mail-actions', '');
    readActions = state;
  };
  if (naverInbox && theme) {
    const selectors = {reply:'.svg_reply', read:'.svg_read, .svg_unread', delete:'.svg_delete', more:'.svg_etc'};
    const actionButton = (state, id) => {
      if (id === 'favorite' || id === 'unfavorite') {
        return state.bookmark.checked === (id === 'unfavorite') ? state.bookmark : null;
      }
      return Object.hasOwn(selectors, id) ? state.group.querySelector(selectors[id]) : null;
    };
    window.__rivoMailActions = {
      snapshot() {
        syncReadActions();
        const state = readActions;
        if (!state?.ticket) return null;
        const ids = [...Object.keys(selectors), state.bookmark.checked ? 'unfavorite' : 'favorite'];
        return {ticket:state.ticket, ids:ids.filter(id => {
          const button = actionButton(state, id);
          return button && !button.disabled;
        })};
      },
      finish(ticket, id) {
        syncReadActions();
        const state = readActions;
        if (!state || state.ticket !== ticket) return;
        state.ticket = null;
        const button = actionButton(state, id);
        // Return keyboard focus to the trigger before the provider opens its own UI.
        state.toggle.focus({preventScroll:true});
        if (button && !button.disabled) button.click();
      }
    };
  }
  window.__rivoMailAppearance = {set(value) {
    enabled = value;
    if (style) style.disabled = !enabled;
    if (!enabled) showReader();
    if (naverInbox && theme) {
      syncReadActions();
      syncMailParagraphs();
    }
    window.__rivoAccessibleWeb?.set({enabled,palette:'dark'});
  }};
  const install = () => {
    if (!document.documentElement) return;
    document.documentElement.setAttribute('data-rivo-easy-mail','');
    if (opensReader && enabled && document.readyState === 'loading') {
      document.documentElement.setAttribute(preparingReader, '');
      // A changed layout or an error must still be visible and usable.
      readerDeadline = setTimeout(showReader, 4000);
    }
    style = document.createElement('style');
    style.disabled = !enabled;
    style.textContent = `
      html[data-rivo-easy-mail] { color-scheme: dark; }
      html[data-rivo-easy-mail] body { font-size:18px; line-height:1.6; }
      html[data-rivo-easy-mail] :is(input:not([type=checkbox]):not([type=radio]),textarea,select) { font-size:max(1rem,18px)!important; line-height:1.5!important; }
      html[data-rivo-easy-mail] :is(button,[role=button]) { min-height:44px; }
      html[data-rivo-easy-mail] :is(a,button,input,textarea,select,[tabindex]):focus-visible { outline:3px solid #ffda80!important; outline-offset:3px!important; }
      html[data-rivo-easy-mail] :is([role=main],main) :is([role=row],[role=listitem]) { min-height:56px; }
      html[data-rivo-easy-mail] :is(p,[role=article]) { line-height:1.7; }
      @media(prefers-reduced-motion:reduce) { html[data-rivo-easy-mail] * { scroll-behavior:auto!important; animation-duration:.01ms!important; transition-duration:.01ms!important; } }
      ${inboxStyle}
      ${detailStyle}
      ${opensReader ? `
        html[data-rivo-easy-mail][${preparingReader}] { background:${theme.bg}!important; }
        html[data-rivo-easy-mail][data-rivo-launcher-widget][${preparingReader}] { background:transparent!important; }
        html[data-rivo-easy-mail][${preparingReader}] body {
          visibility:hidden!important;
          opacity:0!important;
        }
      ` : ''}
    `;
    (document.head || document.documentElement).append(style);
    if (naverInbox && theme) {
      const syncReader = () => {
        syncReadActions();
        syncMailParagraphs();
        if (!document.documentElement.hasAttribute(preparingReader)) return;
        const page = document.querySelector(detailLayout);
        const title = page?.querySelector('.mail_view_header .mail_title');
        const contents = page?.querySelector('.mail_view_contents_inner');
        if (title && contents?.hasChildNodes()) {
          window.__rivoAccessibleWeb?.flushPending?.();
          showReader();
        }
      };
      let frame;
      new MutationObserver(records => {
        const preparing = document.documentElement.hasAttribute(preparingReader);
        if (frame || !records.some(record => preparing || record.type === 'childList' ||
          record.target === document.documentElement || record.target === document.body || record.target.matches('.mail_view_contents_inner :is(p,table,td,div)'))) return;
        frame = requestAnimationFrame(() => {
          frame = undefined;
          syncReader();
        });
      }).observe(document.documentElement, {childList:true,subtree:true,attributes:true,
        attributeFilter:opensReader ? ['style','bgcolor','class'] : ['style','bgcolor']});
      syncReader();
      window.addEventListener('resize', () => { syncReadActions(); syncMailLayoutSurfaces(); });
    }
  };
  if (document.documentElement) install();
  else if (opensReader) {
    const rootObserver = new MutationObserver(() => {
      if (!document.documentElement) return;
      rootObserver.disconnect();
      install();
    });
    rootObserver.observe(document, {childList:true});
  } else document.addEventListener('DOMContentLoaded', install, {once:true});
})();
"""#
    static let officialForm = #"""
(() => {
  'use strict';
  if (window.top !== window || location.protocol !== 'https:' || location.port || window.__rivoOfficialMailForm) return;
  const host = location.hostname, path = location.pathname;
  const naver = host === 'nid.naver.com' && path === '/nidlogin.login';
  const kakao = host === 'accounts.kakao.com' && (path === '/login' || path.startsWith('/login/'));
  const nate = (host === 'xo.nate.com' && path.toLowerCase() === '/mnate/login.sk') ||
    (host === 'home.mail.nate.com' && path === '/login/login.html');
  if (!naver && !kakao && !nate) return;

  const selector = naver ? 'form#frmNIDLogin input#loginStay[name="nvlong"]' :
    kakao ? 'input[name="staySignedIn"]' : 'form:is(#nate_login,#f_login) input#keeplogin[name="keeplogin"]';
  const preference = 'rivo.mail.keep-signed-in';
  const theme = window.__rivoWebTheme;
  let applied = false, frame = 0, enhanced = true, style;
  function sync() {
    frame = 0;
    const stay = document.querySelector(selector);
    const form = stay?.form || (kakao ? document.querySelector('form:has(input[type=password])') : null);
    if (!form?.querySelector('input[type=password]')) {
      document.documentElement?.removeAttribute('data-rivo-mail-provider-login');
      return;
    }

    if (!applied && stay?.type === 'checkbox' && !stay.disabled && document.readyState === 'complete') {
      applied = true;
      let choice;
      try { choice = localStorage.getItem(preference); } catch {}
      const wanted = choice === null || choice === undefined ? true : choice === 'on';
      // NAVER links the two options in its form. Preserve active IP protection.
      const protectedSignIn = naver && document.getElementById('switchIP')?.checked;
      if (stay.checked !== wanted && !(wanted && protectedSignIn)) stay.click();
    }

    if (!naver && !style) {
      style = document.createElement('style');
      style.textContent = `
        html[data-rivo-mail-provider-login],
        html[data-rivo-mail-provider-login] body {
          background:transparent!important; color:${theme?.text || '#F8F5EC'}!important;
        }
        html[data-rivo-mail-provider-login] :is(main,.wrap,.content,.cont_login,.area_login,.wrap_login,.box_login) {
          box-sizing:border-box; background:transparent!important;
        }
        html[data-rivo-mail-provider-login="kakao"] :is(.cont_login,.area_login,.wrap_login,.box_login),
        html[data-rivo-mail-provider-login="nate-mobile"] :is(.wrap,.content) {
          width:100%!important; min-width:0!important; height:auto!important;
        }
        html[data-rivo-mail-provider-login="kakao"] .cont_login,
        html[data-rivo-mail-provider-login="nate-mobile"] .content {
          max-width:568px!important; margin-inline:auto!important; padding-inline:clamp(12px,4vw,24px)!important;
        }
        html[data-rivo-mail-provider-login="kakao"] .box_login {border:0!important;padding-inline:0!important;}
        html[data-rivo-mail-provider-login="kakao"] :is(.wrap_inp,.item_tf)::after {border:0!important;background:none!important;}
        html[data-rivo-mail-provider-login="kakao"] .logo_kakao {
          width:auto!important; height:auto!important; background:none!important;
          color:${theme?.text || '#F8F5EC'}!important; font-size:28px!important; line-height:1.3!important;
        }
        html[data-rivo-mail-provider-login="nate-mobile"] .adBox {display:none!important;}
        html[data-rivo-mail-provider-login] :is(a,label,.txt_check,.desc_login,.txt_info,.txt_sub) {
          color:${theme?.text || '#F8F5EC'}!important;
        }
        form[data-rivo-official-mail-form] :is(input[type=text],input[type=email],input[type=tel],input[type=password]) {
          box-sizing:border-box!important; min-height:64px!important; padding-inline:16px!important;
          border:1px solid ${theme?.edge || '#7F93AB'}!important; border-radius:22px!important;
          background:rgba(255,255,255,.08)!important; color:${theme?.text || '#F8F5EC'}!important;
          font-size:max(18px,1em)!important;
        }
        form[data-rivo-official-mail-form] input::placeholder {color:#D7DDE2!important;}
        html[data-rivo-mail-provider-login="nate-mobile"] :is(.idBox,.pwBox,.cBox),
        html[data-rivo-mail-provider-login="kakao"] :is(.wrap_inp,.item_tf) {border:0!important; background:transparent!important;}
        html[data-rivo-mail-provider-login="nate-mobile"] .appLoginBtn a,
        html[data-rivo-mail-provider-login="nate-mobile"] .snsLoginBtn a {color:inherit!important;}
        form[data-rivo-official-mail-form] :is(button[type=submit],input[type=submit],.btn_g.highlight,.btn_login) {
          min-height:68px!important; border:1px solid ${theme?.text || '#F8F5EC'}!important; border-radius:22px!important;
          background:${theme?.primary || '#255B4B'}!important; color:${theme?.text || '#F8F5EC'}!important;
          font-size:21px!important; font-weight:650!important;
        }
        html[data-rivo-mail-provider-login] :is(a,button,input,label):focus-visible {
          outline:3px solid ${theme?.link || '#E6EF87'}!important; outline-offset:2px;
        }
        form[data-rivo-official-mail-form] :is(label[for="keeplogin"],label[for="staySignedIn"]) {font-size:16px;}
      `;
      (document.head || document.documentElement).append(style);
    }
    if (!naver) form.toggleAttribute('data-rivo-official-mail-form', enhanced);
    if (!naver) {
      const page = kakao ? 'kakao' : host === 'xo.nate.com' ? 'nate-mobile' : 'nate';
      if (enhanced) document.documentElement.setAttribute('data-rivo-mail-provider-login', page);
      else document.documentElement.removeAttribute('data-rivo-mail-provider-login');
    }
  }
  function schedule() { if (!frame) frame = requestAnimationFrame(sync); }
  document.addEventListener('change', event => {
    const stay = event.target;
    if (!event.isTrusted || !stay?.matches?.(selector) || stay.type !== 'checkbox') return;
    try { localStorage.setItem(preference, stay.checked ? 'on' : 'off'); } catch {}
  });
  window.__rivoOfficialMailForm = { setEnhanced(value) { enhanced = !!value; schedule(); } };
  new MutationObserver(schedule).observe(document, {childList:true, subtree:true});
  window.addEventListener('load', schedule, {once:true});
  sync();
})();
"""#

    static let hintTemplate = #"""
(() => {
  'use strict';
  if (window.top !== window || location.protocol !== 'https:' || !HOSTS.includes(location.hostname)) return;
  const address = ADDRESS, selector = SELECTOR;
  if (window.__rivoMailHintInstalled) return;
  window.__rivoMailHintInstalled = true;
  let observer, timer;
  const finish = () => { observer?.disconnect(); clearTimeout(timer); };
  const fill = () => {
    const field = document.querySelector(selector);
    if (!(field instanceof HTMLInputElement) || !['text','email',''].includes(field.type) || field.disabled || field.readOnly || !field.getClientRects().length) return;
    if (!field.value) {
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(field,address);
      field.dispatchEvent(new Event('input',{bubbles:true}));
      field.dispatchEvent(new Event('change',{bubbles:true}));
    }
    finish(); return true;
  };
  if (!fill()) {
    observer = new MutationObserver(fill);
    observer.observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['style','class','hidden','type']});
    timer = setTimeout(finish,120000);
  }
})();
"""#
}
