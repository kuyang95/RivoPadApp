import Foundation

/// Presentation and user-initiated original controls only; no native content bridge.
enum EasyAIPage {
    static func bootstrap(enabled: Bool, palette: AccessibleWebPalette) -> String {
        let language = AppLanguage.current().localizationCode ?? "ko"
        let supported = ["ko", "en", "ja"].contains(language) ? language : "ko"
        return source + "\nwindow.__rivoEasyAI?.set({enabled: \(enabled), palette: '\(palette.rawValue)', language: '\(supported)'});"
    }

    static let source = #"""
// Same source in EasyAIPage.swift. Original editors, messages and service actions stay in place.
(() => {
  'use strict';
  if (window !== window.top || location.protocol !== 'https:' || !['chatgpt.com','auth.openai.com','auth0.openai.com'].includes(location.hostname) || window.__rivoEasyAI) return;
  if (location.hostname !== 'chatgpt.com') {
    // Official authentication fields stay original; only their presentation changes.
    let loginStyle, loginConfig = {enabled:true,palette:'dark'};
    const mountLogin = () => {
      if (!document.documentElement) return;
      const known = !!document.querySelector('form input:is([type="email"],[type="password"],[autocomplete="username"],[autocomplete="one-time-code"])');
      document.documentElement.toggleAttribute('data-rivo-ai-login', loginConfig.enabled && known);
      if (!known || !loginConfig.enabled) { loginStyle?.remove(); loginStyle = null; return; }
      if (!loginStyle) { loginStyle = document.createElement('style'); document.documentElement.appendChild(loginStyle); }
      const p = loginConfig.palette === 'light' ? {bg:'#FFFFFF',surface:'#F0F2F5',text:'#283546',edge:'#536176',link:'#704000'} : window.__rivoWebTheme;
      if (!p) return;
      const css = `html[data-rivo-ai-login] {background:${p.bg}!important;}
        html[data-rivo-ai-login] form {box-sizing:border-box!important;width:100%!important;max-width:560px!important;margin-inline:auto!important;padding:24px!important;}
        html[data-rivo-ai-login] :is(h1,h2) {font-size:30px!important;line-height:1.5!important;}
        html[data-rivo-ai-login] form :is(label,p,a) {font-size:20px!important;line-height:1.7!important;}
        html[data-rivo-ai-login] form input:not([type="checkbox"]):not([type="radio"]) {box-sizing:border-box!important;min-height:64px!important;width:100%!important;font-size:24px!important;background:${p.surface}!important;color:${p.text}!important;}
        html[data-rivo-ai-login] form button {min-height:64px!important;font-size:22px!important;white-space:normal!important;}
        html[data-rivo-ai-login] form :is(input,button,a):focus-visible {outline:3px solid ${p.link}!important;outline-offset:3px!important;}`;
      if (loginStyle.textContent !== css) loginStyle.textContent = css;
    };
    window.__rivoEasyAI = {set(next) { loginConfig = {...loginConfig,...next}; mountLogin(); }};
    new MutationObserver(records => { if(records.some(record => record.target !== loginStyle && [...record.addedNodes].some(node => node.nodeType === Node.ELEMENT_NODE && node !== loginStyle))) mountLogin(); }).observe(document,{subtree:true,childList:true});
    document.addEventListener('DOMContentLoaded',mountLogin,{once:true});
    return;
  }
  const translations = {
    ko: {more:'더보기', platforms:'다른 AI 플랫폼', newChat:'새 대화', history:'대화 목록', account:'계정·설정', login:'로그인', back:'대화로 돌아가기', help:'궁금한 내용을 아래 질문칸에 입력하세요.', attach:'첨부', send:'보내기', stop:'답변 중지', missing:'이 기능을 지금 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.'},
    en: {more:'More', platforms:'Other AI platforms', newChat:'New chat', history:'Chat list', account:'Account', login:'Log in', back:'Back to chat', help:'Type your question in the box below.', attach:'Attach', send:'Send', stop:'Stop', missing:'This control is currently unavailable. Please try again shortly.'},
    ja: {more:'その他', platforms:'他のAIプラットフォーム', newChat:'新しい会話', history:'会話一覧', account:'アカウント', login:'ログイン', back:'会話に戻る', help:'下の入力欄に質問を入力してください。', attach:'添付', send:'送信', stop:'回答を停止', missing:'現在この操作は利用できません。しばらくしてからもう一度お試しください。'}
  };
  const patterns = {
    newChat:/^(?:新しいチャット|新しい会話|새 (?:채팅|대화)|New chat)$/i,
    openSidebar:/^(?:사이드바 (?:보기|열기)|Open sidebar|Show sidebar|サイドバーを(?:開く|表示))$/i,
    closeSidebar:/^(?:사이드바 닫기|Close sidebar|Hide sidebar|サイドバーを閉じる)$/i,
    account:/^(?:프로필 메뉴 열기|Open profile menu|Account menu|プロフィールメニューを開く|로그인|Log in|Sign in|ログイン)$/i,
    attach:/^(?:파일 등 추가|파일 첨부|Add (?:photos|files|attachments).*|Attach.*|ファイル.*追加|添付.*)$/i,
    send:/^(?:보내기|질문 보내기|메시지 보내기|Send(?: prompt| message)?|送信.*)$/i,
    stop:/^(?:중지|답변 중지|응답 중지|생성 중지|Stop(?: generating| streaming| response)?|生成を停止.*|回答を停止.*)$/i,
    voice:/^(?:음성 기능 시작|음성 모드(?: 시작)?|Start voice(?: mode| chat)?|Use voice(?: mode)?|音声モード(?:を開始)?|音声機能を開始)$/i,
    dictation:/^(?:받아쓰기 (?:시작|중지)|음성 입력|(?:Start|Stop) dictation|Dictate|音声入力|ディクテーション(?:を)?(?:開始|停止))$/i
  };
  let config = {enabled:true, palette:'dark', language:'ko'};
  let style, toolbar, status, moreButton, menuPanel, help, moreOpen = false, main, composer, composerFooter, sidebar, closeButton, observer, resizeObserver, timer, historyTimer, pendingHistory = false, historyOpen = false, closingServiceSidebar = false, dismissingPromotion = null;
  const marked = new Map();
  const originalInert = new Map();
  const actionButtons = {};
  const presentationVariables = new Map();
  const editorHeights = new Map();
  const text = () => translations[config.language] || translations.ko;
  const own = node => node instanceof Element && !!node.closest('[data-rivo-ai-ui]');
  const label = node => node.getAttribute('aria-label') || node.textContent?.trim() || '';
  const available = node => !!node && !node.disabled && node.getAttribute('aria-disabled') !== 'true';
  const visible = node => !!node && node.getClientRects().length > 0 && getComputedStyle(node).visibility !== 'hidden';
  function mark(node, attribute, value = '') {
    if (!node) return;
    if (!marked.has(node)) marked.set(node, new Map());
    const attributes = marked.get(node);
    if (!attributes.has(attribute)) attributes.set(attribute, node.getAttribute(attribute));
    if (node.getAttribute(attribute) !== value) node.setAttribute(attribute, value);
  }
  function unmark(node, attribute) {
    const attributes = marked.get(node);
    if (!attributes?.has(attribute)) return;
    const value = attributes.get(attribute);
    if (value === null) node.removeAttribute(attribute); else node.setAttribute(attribute, value);
    attributes.delete(attribute);
  }
  function inert(node, enabled) {
    if (!node) return;
    if (!originalInert.has(node)) originalInert.set(node, node.inert);
    node.inert = enabled || originalInert.get(node);
  }
  function originals() {
    return [...document.querySelectorAll('button,[role="button"],a[href]')].filter(node => !own(node));
  }
  function findAction(name, scope = document) {
    const ids = {newChat:'create-new-chat-button', openSidebar:'open-sidebar-button', attach:'composer-button-plus', send:'send-button', stop:'stop-button'};
    const exact = ids[name] && scope.querySelector(`[data-testid="${ids[name]}"]`);
    if (exact && !own(exact)) return exact;
    const matches = originals().filter(node => scope.contains(node) && patterns[name]?.test(label(node)));
    return matches.find(visible) || matches[0] || null;
  }
  function element(tag, value, className) {
    const node = document.createElement(tag);
    if (value) node.textContent = value;
    if (className) node.className = className;
    return node;
  }
  function variable(name, value) {
    const root = document.documentElement;
    if (!presentationVariables.has(name)) presentationVariables.set(name, [root.style.getPropertyValue(name),root.style.getPropertyPriority(name)]);
    if (root.style.getPropertyValue(name) !== value) root.style.setProperty(name, value);
  }
  function fitEditor(editor) {
    if (!editor || !config.enabled) return;
    const scale = document.documentElement.currentCSSZoom || parseFloat(getComputedStyle(document.documentElement).zoom) || 1;
    const minimum = Math.max(48, Math.ceil(48 / scale));
    const maximum = Math.max(minimum, Math.min(120, Math.floor((window.visualViewport?.height || innerHeight) / scale * .20)));
    variable('--rivo-ai-control-height', `${minimum}px`);
    variable('--rivo-ai-editor-max-height', `${maximum}px`);
    if (editor.tagName !== 'TEXTAREA') return;
    const name = '--rivo-ai-input-height';
    if (!editorHeights.has(editor)) editorHeights.set(editor, [editor.style.getPropertyValue(name),editor.style.getPropertyPriority(name)]);
    // Layout metrics only: keep the provider's editor, value and React events.
    editor.style.setProperty(name, '0px');
    editor.style.setProperty(name, `${Math.min(maximum, Math.max(minimum, editor.scrollHeight))}px`);
  }
  function resizeLayout() {
    if (!config.enabled || !document.documentElement.hasAttribute('data-rivo-easy-ai')) return;
    fitEditor(document.querySelector('[data-rivo-ai-editor]'));
    measure();
  }
  function measure() {
    if (!toolbar?.isConnected) return;
    toolbar.toggleAttribute('data-rivo-ai-empty-toolbar', !!help?.hidden && !status?.textContent);
    const scale = document.documentElement.currentCSSZoom || parseFloat(getComputedStyle(document.documentElement).zoom) || 1;
    document.documentElement.toggleAttribute('data-rivo-ai-short', (window.visualViewport?.height || innerHeight) / scale < 450);
    document.documentElement.toggleAttribute('data-rivo-ai-compact', (window.visualViewport?.height || innerHeight) / scale < 600);
    variable('--rivo-ai-toolbar-height', `${Math.ceil(toolbar.getBoundingClientRect().height / scale)}px`);
    variable('--rivo-ai-viewport-width', `${Math.floor((window.visualViewport?.width || innerWidth) / scale)}px`);
    if (composerFooter) variable('--rivo-ai-composer-height', `${Math.ceil(composerFooter.getBoundingClientRect().height / scale)}px`);
    variable('--rivo-ai-viewport-height', `${Math.floor((window.visualViewport?.height || innerHeight) / scale)}px`);
  }
  function setMore(open, focus = true) {
    moreOpen = open && !!menuPanel?.isConnected;
    if (menuPanel) menuPanel.hidden = !moreOpen;
    if (!moreOpen) setPlatforms(false);
    moreButton?.setAttribute('aria-expanded', String(moreOpen));
    if (focus) {
      if (moreOpen) [...menuPanel.querySelectorAll('button')].find(node => !node.hidden && available(node))?.focus();
      else moreButton?.focus();
    }
  }
  function setPlatforms(open) {
    const button = actionButtons.platforms;
    if (!button) return;
    button.setAttribute('aria-expanded', String(open));
    const choices = menuPanel.querySelectorAll('[data-rivo-ai-platform]');
    for (const choice of choices) choice.hidden = !open;
    if (open) choices[0]?.focus();
  }
  function closeMoreLevel() {
    const button = actionButtons.platforms;
    if (button?.getAttribute('aria-expanded') === 'true') {
      setPlatforms(false);
      button.focus();
    } else setMore(false);
  }
  function setHistory(open) {
    if (open) setMore(false, false);
    historyOpen = open && !!sidebar;
    document.documentElement.toggleAttribute('data-rivo-ai-history', historyOpen);
    inert(main, historyOpen);
    if (composer && !main.contains(composer)) inert(composerFooter || composer, historyOpen);
    inert(toolbar, historyOpen);
    if (sidebar) {
      if (!originalInert.has(sidebar)) originalInert.set(sidebar, sidebar.inert);
      sidebar.inert = historyOpen ? false : originalInert.get(sidebar);
      mark(sidebar, 'role', historyOpen ? 'dialog' : marked.get(sidebar)?.get('role') || 'complementary');
      mark(sidebar, 'aria-label', text().history);
      mark(sidebar, 'aria-modal', historyOpen ? 'true' : 'false');
    }
    actionButtons.history?.setAttribute('aria-expanded', String(historyOpen));
    if (historyOpen) closeButton?.focus();
    else moreButton?.focus();
  }
  function activate(name) {
    if (name === 'history') {
      if (sidebar) { setHistory(true); return; }
      pendingHistory = true;
      const open = findAction('openSidebar');
      if (open && available(open)) open.click();
      schedule();
      if (sidebar) { pendingHistory = false; setHistory(true); }
      else {
        clearTimeout(historyTimer);
        historyTimer = setTimeout(() => {
          if (pendingHistory && status) { pendingHistory = false; status.textContent = text().missing; }
        }, 2000);
      }
      return;
    }
    const target = findAction(name);
    if (name === 'account' && sidebar?.contains(target) && !/^(?:로그인|Log in|Sign in|ログイン)$/i.test(label(target))) setHistory(true);
    if (!available(target)) { status.textContent = text().missing; return; }
    if (name === 'newChat') setHistory(false);
    // User-initiated activation of the service's original React control.
    target.click();
  }
  function buildToolbar() {
    if (toolbar?.isConnected) return;
    toolbar = element('section', '', 'rivo-ai-toolbar');
    toolbar.setAttribute('data-rivo-ai-ui', '');
    toolbar.setAttribute('data-rivo-web-preserve', '');
    help = element('p', text().help, 'rivo-ai-help');
    moreButton = element('button', '⋯', 'rivo-ai-more');
    moreButton.type = 'button';
    moreButton.setAttribute('data-rivo-ai-ui', '');
    moreButton.setAttribute('data-rivo-web-preserve', '');
    moreButton.setAttribute('aria-label', text().more);
    moreButton.setAttribute('title', text().more);
    moreButton.setAttribute('aria-haspopup', 'menu');
    moreButton.setAttribute('aria-expanded', 'false');
    moreButton.setAttribute('aria-controls', 'rivo-ai-more-menu');
    moreButton.addEventListener('click', event => { event.stopPropagation(); setMore(!moreOpen); });
    moreButton.addEventListener('keydown', event => {
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') { event.preventDefault(); setMore(true); }
    });
    menuPanel = element('div', '', 'rivo-ai-menu');
    menuPanel.id = 'rivo-ai-more-menu';
    menuPanel.hidden = true;
    menuPanel.setAttribute('role', 'menu');
    menuPanel.setAttribute('aria-label', text().more);
    for (const name of ['account','newChat','history']) {
      const button = element('button', text()[name]);
      button.type = 'button';
      button.setAttribute('role', 'menuitem');
      button.addEventListener('click', () => { setMore(false); activate(name); });
      if (name === 'history') { button.setAttribute('aria-haspopup', 'dialog'); button.setAttribute('aria-expanded', 'false'); }
      actionButtons[name] = button;
      menuPanel.appendChild(button);
    }
    const platforms = element('button', text().platforms);
    platforms.type = 'button';
    platforms.setAttribute('role', 'menuitem');
    platforms.setAttribute('aria-expanded', 'false');
    platforms.addEventListener('click', () => setPlatforms(platforms.getAttribute('aria-expanded') !== 'true'));
    actionButtons.platforms = platforms;
    menuPanel.appendChild(platforms);
    for (const [name, url] of [
      ['Claude', 'https://claude.ai/'],
      ['Gemini', 'https://gemini.google.com/'],
      ['GPT', 'https://chatgpt.com/']
    ]) {
      const choice = element('button', name);
      choice.type = 'button';
      choice.hidden = true;
      choice.setAttribute('role', 'menuitem');
      choice.setAttribute('data-rivo-ai-platform', '');
      if (location.origin === new URL(url).origin) choice.setAttribute('aria-current', 'true');
      choice.addEventListener('click', () => {
        setMore(false);
        if (location.origin !== new URL(url).origin) location.assign(url);
      });
      menuPanel.appendChild(choice);
    }
    status = element('p', '', 'rivo-ai-status');
    status.setAttribute('role', 'status');
    toolbar.append(help, menuPanel, status);
    document.body.appendChild(toolbar);
    resizeObserver = new ResizeObserver(measure);
    resizeObserver.observe(toolbar);
    measure();
  }
  function stylesheet() {
    const theme = window.__rivoWebTheme || {bg:'#181A1B',surface:'#23272B',text:'#F8F5EC',edge:'#777E84',link:'#D8B36B'};
    const p = config.palette === 'light' ? {bg:'#FFFFFF',surface:'#F0F2F5',text:'#283546',edge:'#536176',link:'#704000'} : theme;
    const panel = /^#[0-9a-f]{6}$/i.test(p.surface) ? `${p.surface}CC` : p.surface;
    const root = 'html[data-rivo-easy-ai]';
    return `
      ${root} { --rivo-ai-bg:${p.bg}; --rivo-ai-surface:${p.surface}; --rivo-ai-text:${p.text}; --rivo-ai-edge:${p.edge}; --rivo-ai-accent:${p.link}; --rivo-ai-toolbar-height:160px;
        --main-surface-primary:transparent; --sidebar-surface-primary:${p.surface}; --message-surface:${p.surface};
        --bg-primary:transparent; --bg-secondary:${p.surface}; --color-surface:transparent; --color-surface-secondary:${p.surface}; --color-text:${p.text}; --color-text-secondary:${p.text};
        background:transparent!important; color:${p.text}!important; }
      ${root} body, ${root} [data-rivo-ai-canvas] { background:transparent!important; box-shadow:none!important; }
      ${root}::before, ${root}::after, ${root} body::before, ${root} body::after,
      ${root} [data-rivo-ai-canvas]::before, ${root} [data-rivo-ai-canvas]::after { background:transparent!important; box-shadow:none!important; border-color:transparent!important; }
      ${root} [data-rivo-ai-composer-shell] { padding:0!important; margin:0!important; row-gap:0!important; }
      ${root} [data-rivo-ai-main] { box-sizing:border-box!important; padding-top:calc(var(--rivo-ai-toolbar-height) + 12px)!important; min-width:0!important; border:0!important; }
      ${root} [data-rivo-ai-main] > header, ${root} [data-rivo-ai-site-header] { position:relative!important; inset:auto!important; min-height:56px!important; height:auto!important; flex-wrap:wrap!important; background:transparent!important; }
      ${root} [data-rivo-ai-site-header] button { font-size:20px!important; min-height:56px!important; min-width:56px!important; }
      ${root} [data-rivo-ai-site-header] { font-size:22px!important; }
      ${root} [data-rivo-ai-site-header] button { border-radius:14px!important; }
      ${root} [data-rivo-ai-guest-header] { display:none!important; }
      ${root} [data-rivo-ai-secondary-nav], ${root} [data-rivo-ai-dictation] { display:none!important; }
      ${root} .rivo-ai-toolbar { width:var(--rivo-ai-viewport-width,100%)!important; box-sizing:border-box!important; position:fixed!important; inset:0 0 auto!important; z-index:40!important; display:grid!important; grid-template-columns:minmax(0,1fr) auto!important; align-items:center!important; gap:12px!important; padding:16px 24px!important; background:transparent!important; color:${p.text}!important; }
      ${root} .rivo-ai-help { grid-column:1!important; grid-row:1!important; margin:0!important; font:400 18px/1.6 system-ui!important; }
      ${root} .rivo-ai-toolbar button, ${root} .rivo-ai-close { box-sizing:border-box!important; min-width:0!important; min-height:64px!important; padding:12px!important; border:1px solid ${p.edge}!important; border-radius:16px!important; background:${p.surface}!important; color:${p.text}!important; -webkit-text-fill-color:${p.text}!important; font:600 22px/1.4 system-ui!important; white-space:normal!important; cursor:pointer; }
      ${root} .rivo-ai-toolbar[data-rivo-ai-empty-toolbar] { padding:0!important; min-height:0!important; }
      ${root} .rivo-ai-more { box-sizing:border-box!important; position:relative!important; inset:auto!important; flex:0 0 auto!important; width:var(--rivo-ai-control-height,48px)!important; min-width:var(--rivo-ai-control-height,48px)!important; height:var(--rivo-ai-control-height,48px)!important; min-height:var(--rivo-ai-control-height,48px)!important; margin:0!important; padding:0!important; border:1px solid ${p.edge}!important; border-radius:50%!important; background:transparent!important; color:${p.text}!important; -webkit-text-fill-color:${p.text}!important; font:600 28px/1 system-ui!important; cursor:pointer; }
      ${root} .rivo-ai-more::before, ${root} .rivo-ai-more::after { display:none!important; }
      ${root} .rivo-ai-menu { position:fixed!important; inset:auto 16px calc(var(--rivo-ai-composer-height,120px) + 8px) auto!important; width:min(280px,calc(var(--rivo-ai-viewport-width) - 32px))!important; max-height:calc(var(--rivo-ai-viewport-height) - var(--rivo-ai-toolbar-height) - var(--rivo-ai-composer-height,120px) - 16px)!important; overflow:auto!important; box-sizing:border-box!important; display:flex!important; flex-direction:column!important; gap:8px!important; padding:8px!important; background:${p.surface}!important; border:1px solid ${p.edge}!important; border-radius:16px!important; box-shadow:0 8px 24px #0005!important; }
      ${root} .rivo-ai-menu button { width:100%!important; text-align:start!important; border:0!important; border-radius:12px!important; background:transparent!important; }
      ${root} .rivo-ai-toolbar [hidden], ${root} [data-empty-composer-help],
      ${root} [data-trending-slot]:has([data-empty-composer-help]):not(:has(button:not([data-empty-composer-help]),a[href],input,textarea)) { display:none!important; }
      ${root} .rivo-ai-toolbar button:disabled { opacity:.45!important; cursor:default; }
      ${root} .rivo-ai-status { grid-column:1 / -1!important; margin:0!important; font-size:18px!important; line-height:1.5!important; }
      ${root} .rivo-ai-status:empty { display:none!important; }
      ${root} [data-rivo-ai-editor] { box-sizing:border-box!important; font:400 24px/1.45 system-ui!important; min-height:var(--rivo-ai-control-height,48px)!important; border:0!important; max-height:var(--rivo-ai-editor-max-height,120px)!important; padding:4px 0!important; overflow-y:auto!important; caret-color:${p.link}!important; color:${p.text}!important; -webkit-text-fill-color:${p.text}!important; }
      ${root} [data-rivo-ai-editor] :is(p,span) { font-size:inherit!important; line-height:inherit!important; }
      ${root} [data-rivo-ai-composer] { padding:8px!important; margin:0!important; min-height:0!important; height:auto!important; border:1px solid ${p.edge}!important; border-radius:16px!important; background:${panel}!important; box-shadow:none!important; }
      ${root} [data-rivo-ai-control] { box-sizing:border-box!important; aspect-ratio:auto!important; width:auto!important; min-width:72px!important; min-height:var(--rivo-ai-control-height,48px)!important; height:auto!important; padding:8px!important; display:inline-flex!important; gap:6px!important; align-items:center!important; justify-content:center!important; border-radius:14px!important; font:600 18px/1.4 system-ui!important; }
      ${root} [data-rivo-ai-control]::before { display:none!important; }
      ${root} [data-rivo-ai-control]::after { content:attr(data-rivo-ai-label)!important; position:static!important; background:none!important; font:inherit!important; color:inherit!important; -webkit-text-fill-color:inherit!important; }
      ${root} :is([data-rivo-ai-control="attach"],[data-rivo-ai-wave]) { box-sizing:border-box!important; width:var(--rivo-ai-control-height,48px)!important; min-width:var(--rivo-ai-control-height,48px)!important; height:var(--rivo-ai-control-height,48px)!important; min-height:var(--rivo-ai-control-height,48px)!important; margin:0!important; padding:8px!important; border:1px solid ${p.edge}!important; border-radius:50%!important; background:transparent!important; color:${p.text}!important; display:inline-flex!important; align-items:center!important; justify-content:center!important; }
      ${root} [data-rivo-ai-control="attach"] { font-size:0!important; }
      ${root} :is([data-rivo-ai-control="attach"],[data-rivo-ai-wave])::before, ${root} :is([data-rivo-ai-control="attach"],[data-rivo-ai-wave])::after { display:none!important; }
      ${root} :is([data-rivo-ai-control="attach"],[data-rivo-ai-wave]) svg { width:24px!important; height:24px!important; flex:none!important; }
      ${root} [data-rivo-ai-control="send"], ${root} [data-rivo-ai-control="stop"] { margin:0!important; margin-inline-start:8px!important; background:${p.link}!important; color:${p.bg}!important; -webkit-text-fill-color:${p.bg}!important; }
      ${root} :is([data-rivo-ai-control="send"],[data-rivo-ai-control="stop"]) :is(svg,[data-rivo-web-icon-fill]) { color:${p.bg}!important; fill:${p.bg}!important; }
      ${root} :is([data-rivo-ai-control="send"],[data-rivo-ai-control="stop"]) [data-rivo-web-icon-stroke] { stroke:${p.bg}!important; }
      ${root} :is([data-message-author-role],[data-assistant-markdown],[data-user-message-bubble],main article .markdown,main article .prose) { font-size:24px!important; line-height:1.85!important; overflow-wrap:anywhere; }
      ${root} :is([data-message-author-role],[data-assistant-markdown],[data-user-message-bubble],main article .markdown,main article .prose) :is(p,li,blockquote) { font-size:inherit!important; line-height:inherit!important; }
      ${root} :is([data-message-author-role="user"],[data-user-message-bubble]) { padding:18px!important; border-radius:18px!important; background:${p.surface}!important; }
      ${root} [data-rivo-ai-sidebar] { display:none!important; }
      ${root}[data-rivo-ai-history] [data-rivo-ai-sidebar] { transform:none!important; translate:none!important; visibility:visible!important; pointer-events:auto!important; position:fixed!important; inset:0!important; z-index:60!important; display:flex!important; flex-direction:column!important; width:var(--rivo-ai-viewport-width,100%)!important; max-width:none!important; min-width:0!important; height:var(--rivo-ai-viewport-height,100dvh)!important; background:${p.bg}!important; overflow-y:auto!important; padding:20px!important; box-sizing:border-box!important; }
      ${root}[data-rivo-ai-history] [data-rivo-ai-sidebar] :is(nav,[role="navigation"]) { width:100%!important; max-width:none!important; }
      ${root}[data-rivo-ai-history] [data-rivo-ai-sidebar] :is(button,a[href]) { min-height:64px!important; height:auto!important; font-size:22px!important; line-height:1.6!important; white-space:normal!important; padding-block:12px!important; }
      ${root}[data-rivo-ai-history] [data-rivo-ai-sidebar] nav > :is(button,a[href]) { border:0!important; border-bottom:1px solid ${p.edge}!important; border-radius:0!important; text-decoration:none!important; text-align:start!important; padding:16px 12px!important; }
      ${root}[data-rivo-ai-history] .rivo-ai-close { position:sticky!important; top:0!important; z-index:2!important; flex:none!important; width:100%!important; margin-bottom:20px!important; }
      ${root} :is([role="menu"],[role="dialog"]) { background-color:${p.surface}!important; color:${p.text}!important; }
      ${root} :is([role="menuitem"],[role="menu"] button,[role="dialog"] button) { min-height:56px!important; height:auto!important; font-size:20px!important; line-height:1.6!important; white-space:normal!important; }
      ${root} :is(button,a[href],textarea,[contenteditable="true"]):focus-visible { outline:3px solid ${p.link}!important; outline-offset:3px!important; }
      ${root}[data-rivo-ai-mobile] body { width:var(--rivo-ai-viewport-width)!important; height:var(--rivo-ai-viewport-height)!important; overflow:hidden!important; }
      ${root}[data-rivo-ai-mobile] :is([data-rivo-ai-canvas],[data-rivo-ai-mobile-path]) { box-sizing:border-box!important; min-width:0!important; max-width:100%!important; width:100%!important; height:auto!important; min-height:0!important; background-color:transparent!important; }
      ${root}[data-rivo-ai-mobile] [data-rivo-ai-main] { position:fixed!important; top:var(--rivo-ai-toolbar-height)!important; left:0!important; width:var(--rivo-ai-viewport-width)!important; height:calc(var(--rivo-ai-viewport-height) - var(--rivo-ai-toolbar-height) - var(--rivo-ai-composer-height,120px))!important; padding:16px!important; overflow:auto!important; }
      ${root}[data-rivo-ai-mobile] [data-rivo-ai-main] > * { max-width:100%!important; min-width:0!important; }
      ${root}[data-rivo-ai-mobile] [data-rivo-ai-footer] > span[aria-hidden="true"]:empty { display:none!important; }
      ${root}[data-rivo-ai-mobile] [data-rivo-ai-footer] { transform:none!important; position:fixed!important; inset:auto auto 0 0!important; width:var(--rivo-ai-viewport-width)!important; max-height:60%!important; overflow:auto!important; padding:4px 12px!important; background:transparent!important; z-index:30!important; }
      ${root} [data-rivo-ai-legal] { display:none!important; }
      ${root} :is([data-octane-recurring-login-banner],[data-octane-product-card]) { display:none!important; }
      ${root}[data-rivo-ai-mobile] [data-rivo-ai-composer] { background:${panel}!important; display:flex!important; flex-wrap:wrap!important; gap:4px 8px!important; }
      ${root}[data-rivo-ai-mobile] [data-rivo-ai-input-row] { flex:1 0 100%!important; position:relative!important; grid-area:auto!important; }
      ${root}[data-rivo-ai-mobile] [data-rivo-ai-editor] { order:-1!important; resize:none!important; min-height:var(--rivo-ai-control-height,48px)!important; }
      ${root}[data-rivo-ai-mobile] textarea[data-rivo-ai-editor] { height:var(--rivo-ai-input-height,48px)!important; }
      ${root}[data-rivo-ai-mobile] [data-rivo-ai-control-wrap] { display:contents!important; }
      ${root}[data-rivo-ai-mobile] :is([data-rivo-ai-control],[data-rivo-ai-wave]) { position:relative!important; inset:auto!important; flex:0 0 auto!important; }
      ${root}[data-rivo-ai-mobile] .rivo-ai-more { margin-inline-start:auto!important; }
      ${root}[data-rivo-ai-mobile] [data-rivo-ai-attach-menu] { position:fixed!important; inset:auto 12px calc(var(--rivo-ai-composer-height,120px) + 8px) auto!important; transform:none!important; max-width:calc(var(--rivo-ai-viewport-width) - 24px)!important; max-height:calc(var(--rivo-ai-viewport-height) - var(--rivo-ai-composer-height,120px) - var(--rivo-ai-toolbar-height) - 16px)!important; overflow:auto!important; box-sizing:border-box!important; background:${p.surface}!important; border:1px solid ${p.edge}!important; border-radius:16px!important; z-index:45!important; }
      ${root}[data-rivo-ai-mobile] [data-rivo-ai-attach-menu] nav { background:transparent!important; border:0!important; box-shadow:none!important; }
      ${root}[data-rivo-ai-mobile] [data-rivo-ai-attach-menu]::before, ${root}[data-rivo-ai-mobile] [data-rivo-ai-attach-menu]::after,
      ${root}[data-rivo-ai-mobile] [data-rivo-ai-attach-menu] nav::before, ${root}[data-rivo-ai-mobile] [data-rivo-ai-attach-menu] nav::after { display:none!important; }
      ${root}[data-rivo-ai-mobile] [data-rivo-ai-attach-menu] button { min-height:48px!important; font-size:20px!important; color:${p.text}!important; background:transparent!important; }
      ${root}[data-rivo-ai-mobile] [data-rivo-ai-attach-menu] button * { color:${p.text}!important; -webkit-text-fill-color:${p.text}!important; background-color:transparent!important; }
      ${root}[data-rivo-ai-mobile] :is(#mobile-auth-dialog,#mobile-new-chat-dialog)[open] { inset:0!important; margin:0!important; width:var(--rivo-ai-viewport-width)!important; height:var(--rivo-ai-viewport-height)!important; max-height:var(--rivo-ai-viewport-height)!important; overflow:auto!important; transform:none!important; }
      ${root}[data-rivo-ai-short] [data-rivo-ai-footer] { max-height:calc(var(--rivo-ai-viewport-height) - var(--rivo-ai-toolbar-height) - 12px)!important; }
      ${root}[data-rivo-ai-compact] .rivo-ai-toolbar:not([data-rivo-ai-empty-toolbar]) { padding-top:8px!important; padding-bottom:8px!important; }
      ${root}[data-rivo-ai-compact] .rivo-ai-menu button { min-height:52px!important; font-size:20px!important; }
      @media(max-width:480px) { ${root} .rivo-ai-toolbar { padding-inline:16px!important; } ${root} .rivo-ai-menu { right:16px!important; width:min(280px,calc(100% - 32px))!important; } }
      @media(prefers-reduced-motion:reduce) { ${root} * { scroll-behavior:auto!important; } }
    `;
  }
  function restore() {
    setMore(false, false);
    pendingHistory = false;
    clearTimeout(historyTimer);
    if (historyOpen) setHistory(false);
    for (const [node, attributes] of marked) for (const [attribute, value] of attributes) {
      if (value === null) node.removeAttribute(attribute); else node.setAttribute(attribute, value);
    }
    marked.clear();
    for (const [node, value] of originalInert) node.inert = value;
    originalInert.clear();
    for (const [name,[value,priority]] of presentationVariables) {
      if (value) document.documentElement.style.setProperty(name,value,priority);
      else document.documentElement.style.removeProperty(name);
    }
    presentationVariables.clear();
    for (const [editor,[value,priority]] of editorHeights) {
      if (value) editor.style.setProperty('--rivo-ai-input-height', value, priority);
      else editor.style.removeProperty('--rivo-ai-input-height');
    }
    editorHeights.clear();
    resizeObserver?.disconnect();
    document.documentElement.removeAttribute('data-rivo-easy-ai');
    document.documentElement.removeAttribute('data-rivo-ai-history');
    document.documentElement.removeAttribute('data-rivo-ai-mobile');
    document.documentElement.removeAttribute('data-rivo-ai-compact');
    document.documentElement.removeAttribute('data-rivo-ai-short');
    toolbar?.remove(); moreButton?.remove(); closeButton?.remove(); style?.remove();
    toolbar = closeButton = style = moreButton = menuPanel = help = null;
  }
  function dismissPromotions() {
    if (!config.enabled || !document.documentElement.hasAttribute('data-rivo-easy-ai')) return;
    const sheet = document.querySelector('#beacon-content-sheet[open]');
    if (!sheet) { dismissingPromotion = null; return; }
    if (sheet === dismissingPromotion) return;
    const stayOnWeb = [...sheet.querySelectorAll('button')].find(node =>
      /^(?:웹에서 계속하기|Continue (?:on|in) (?:the )?(?:web|browser)|Stay on (?:the )?web|(?:ウェブ|Web|ブラウザ|ブラウザー)で(?:続ける|続行))$/i.test(label(node)));
    // Use the provider's explicit web alternative so its modal/inert state closes too.
    if (available(stayOnWeb)) { dismissingPromotion = sheet; stayOnWeb.click(); }
  }
  function refresh() {
    timer = undefined;
    for (const node of marked.keys()) if (!node.isConnected) { resizeObserver?.unobserve(node); marked.delete(node); originalInert.delete(node); editorHeights.delete(node); }
    if (!config.enabled || /^\/(?:auth|api|backend-api)(?:\/|$)/.test(location.pathname)) { if (marked.size) restore(); return; }
    main = document.querySelector('main,[role="main"]');
    const editor = [...document.querySelectorAll('#prompt-textarea,#mobile-composer-prompt,main [role="textbox"][contenteditable="true"],main textarea')].find(visible);
    // Unknown or verification pages remain usable. Never hide a page while waiting.
    if (!main || !editor) { if (marked.size) restore(); return; }
    if (!document.body) return;
    if (!style) { style = element('style'); style.id = 'rivo-easy-ai-style'; style.textContent = stylesheet(); document.documentElement.appendChild(style); }
    document.documentElement.setAttribute('data-rivo-easy-ai', '');
    dismissPromotions();
    buildToolbar();
    mark(main, 'data-rivo-ai-main');
    mark(editor, 'data-rivo-ai-editor');
    const form = editor.closest('form') || editor.closest('[data-type="unified-composer"]');
    composer = form;
    const mobile = editor.id === 'mobile-composer-prompt';
    document.documentElement.toggleAttribute('data-rivo-ai-mobile', mobile);
    const nextFooter = mobile ? editor.closest('footer') : null;
    if (composerFooter && composerFooter !== nextFooter) resizeObserver?.unobserve(composerFooter);
    composerFooter = nextFooter;
    if (mobile) {
      mark(composerFooter, 'data-rivo-ai-footer');
      if (composerFooter) resizeObserver?.observe(composerFooter);
      for (let node = editor; node && node !== document.body; node = node.parentElement) {
        mark(node, 'data-rivo-ai-mobile-path');
        if (node === form) continue;
        if (form?.contains(node) && getComputedStyle(node).display !== 'contents') mark(node, 'data-rivo-ai-input-row');
      }
    }
    if (mobile) {
      for (const header of document.querySelectorAll('header')) {
        if (header.closest('dialog,[role="dialog"],aside') || main.contains(header)) continue;
        const account = findAction('account', header);
        if (account && /^(?:로그인|Log in|Sign in|ログイン)$/i.test(label(account))) mark(header, 'data-rivo-ai-guest-header');
        else unmark(header, 'data-rivo-ai-guest-header');
      }
    }
    for (const legal of document.querySelectorAll('[data-privacy-positioner]')) {
      // Keep the hidden notice marked on later refreshes; visibility is false by design.
      if (!main.contains(legal) && !legal.closest('dialog,[role="dialog"]')) mark(legal, 'data-rivo-ai-legal');
      else unmark(legal, 'data-rivo-ai-legal');
    }
    mark(form, 'data-rivo-ai-composer');
    for (let node = form?.parentElement; node && node !== document.body; node = node.parentElement) {
      mark(node, 'data-rivo-ai-canvas');
      if (composerFooter && node !== composerFooter && composerFooter.contains(node)) mark(node, 'data-rivo-ai-composer-shell');
    }
    fitEditor(editor);
    for (const name of ['attach','send','stop']) {
      const node = form && findAction(name, form);
      if (node) {
        mark(node, 'data-rivo-ai-control', name); mark(node, 'data-rivo-ai-label', text()[name]);
        if (mobile) for (let parent = node.parentElement; parent && parent !== form && !parent.contains(editor); parent = parent.parentElement) mark(parent, 'data-rivo-ai-control-wrap');
        if (name === 'attach' && moreButton.nextElementSibling !== node) node.before(moreButton);
        if (mobile && name === 'attach') for (const nav of node.parentElement.querySelectorAll('nav')) {
          for (let popup = nav; popup && popup !== node.parentElement; popup = popup.parentElement) {
            if (getComputedStyle(popup).position === 'fixed') { mark(popup, 'data-rivo-ai-attach-menu'); break; }
          }
        }
      }
    }
    const voice = form && findAction('voice', form);
    if (voice) {
      mark(voice, 'data-rivo-ai-wave');
      if (mobile) for (let parent = voice.parentElement; parent && parent !== form && !parent.contains(editor); parent = parent.parentElement) mark(parent, 'data-rivo-ai-control-wrap');
    }
    // Keep the provider's separate waveform voice-chat control; hide dictation only.
    for (const node of originals().filter(node => form?.contains(node))) {
      if (patterns.dictation.test(label(node))) mark(node, 'data-rivo-ai-dictation');
      else unmark(node, 'data-rivo-ai-dictation');
    }
    for (let node = main; node && node !== document.body; node = node.parentElement) mark(node, 'data-rivo-ai-canvas');
    const header = main.querySelector('header');
    mark(header, 'data-rivo-ai-site-header');
    if (header) for (const node of header.querySelectorAll('button')) {
      if (patterns.openSidebar.test(label(node))) mark(node, 'data-rivo-ai-secondary-nav');
    }
    const nextSidebar = document.querySelector('aside,[data-testid="sidebar"]') ||
      [...document.querySelectorAll('nav[aria-label],[role="navigation"],[role="dialog"]')].find(node =>
        !own(node) && !main.contains(node) &&
        (node.querySelector('a[href*="/c/"]') || /chat history|채팅 기록|会話履歴/i.test(node.getAttribute('aria-label') || '')));
    if (sidebar !== nextSidebar) { if (historyOpen) setHistory(false); sidebar = nextSidebar; }
    if (sidebar) {
      // A persisted original drawer can keep the original main/footer inert even
      // when our presentation hides it. Close it through the service's handler.
      const serviceOpen = findAction('openSidebar')?.getAttribute('aria-expanded') === 'true';
      if (!serviceOpen) closingServiceSidebar = false;
      if (!historyOpen && serviceOpen && !closingServiceSidebar && !document.querySelector('dialog[open]')) {
        const close = findAction('closeSidebar');
        if (available(close)) { closingServiceSidebar = true; close.click(); }
      }
      mark(sidebar, 'data-rivo-ai-sidebar');
      if (!closeButton || !sidebar.contains(closeButton)) {
        closeButton = element('button', text().back, 'rivo-ai-close');
        closeButton.type = 'button'; closeButton.setAttribute('data-rivo-ai-ui', '');
        closeButton.addEventListener('click', () => setHistory(false));
        sidebar.prepend(closeButton);
      }
      if (pendingHistory) { pendingHistory = false; clearTimeout(historyTimer); setHistory(true); }
    }
    // Guest conversations can stay on /, so the transcript determines this state.
    const hasConversation = !!main.querySelector('[data-message-author-role="user"],[data-message-author-role="assistant"],[data-message-role="user"],[data-message-role="assistant"],[data-user-message-bubble],[data-assistant-markdown]');
    actionButtons.newChat.hidden = !hasConversation;
    help.hidden = hasConversation;
    measure();
    if (actionButtons.platforms.textContent !== text().platforms) actionButtons.platforms.textContent = text().platforms;
    for (const name of ['newChat','history','account']) {
      const target = name === 'history' ? sidebar || findAction('openSidebar') : findAction(name);
      actionButtons[name].disabled = name === 'history' ? !target : !available(target);
      const title = name === 'account' && target && /^(?:로그인|Log in|Sign in|ログイン)$/i.test(label(target)) ? text().login : text()[name];
      if (actionButtons[name].textContent !== title) actionButtons[name].textContent = title;
    }
  }
  function schedule() { if (!timer && config.enabled) timer = setTimeout(refresh, 120); }
  window.__rivoEasyAI = {back() {
    if (moreOpen) { closeMoreLevel(); return true; }
    const dialog = [...document.querySelectorAll('dialog[open]')].filter(visible).at(-1);
    if (dialog) {
      const close = [...dialog.querySelectorAll('button')].find(node => visible(node) && /^(?:닫기|취소|Close|Cancel|閉じる|キャンセル)$/i.test(label(node)));
      if (close) { close.click(); return true; }
      if (typeof dialog.requestClose === 'function') { dialog.requestClose(); return true; }
    }
    if (!historyOpen) return false;
    setHistory(false);
    return true;
  }, set(next) {
    if (!next || typeof next.enabled !== 'boolean') return;
    config = {...config, ...next};
    if (!config.enabled) restore();
    else { if (style) style.textContent = stylesheet(); refresh(); if (style) style.textContent = stylesheet(); }
  }};
  observer = new MutationObserver(records => {
    if (records.some(record => !own(record.target) && record.target !== style &&
        (record.type === 'attributes' || [...record.addedNodes,...record.removedNodes].some(node => node.nodeType === Node.ELEMENT_NODE && !own(node))))) schedule();
  });
  observer.observe(document, {subtree:true,childList:true,attributes:true,attributeFilter:['open','class','id','role','aria-label','disabled','aria-expanded','data-message-role','data-message-author-role']});
  document.addEventListener('toggle', event => {
    if (event.target.id === 'beacon-content-sheet' && event.newState === 'open') dismissPromotions();
  }, true);
  document.addEventListener('click', event => {
    if (historyOpen && !own(event.target) && event.target.closest('a[href*="/c/"]')) setHistory(false);
  }, true);
  document.addEventListener('pointerdown', event => {
    if (moreOpen && !menuPanel.contains(event.target) && !moreButton.contains(event.target)) setMore(false, false);
  }, true);
  document.addEventListener('focusin', event => {
    if (moreOpen && !menuPanel.contains(event.target) && !moreButton.contains(event.target)) setMore(false, false);
  }, true);
  document.addEventListener('keydown', event => {
    if (moreOpen && event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); closeMoreLevel(); return; }
    if (moreOpen && menuPanel.contains(event.target) && ['ArrowDown','ArrowUp','Home','End'].includes(event.key)) {
      event.preventDefault();
      const items = [...menuPanel.querySelectorAll('button')].filter(node => !node.hidden && available(node));
      if (!items.length) return;
      const index = items.indexOf(document.activeElement);
      const next = event.key === 'Home' ? 0 : event.key === 'End' ? items.length - 1 : (index + (event.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length;
      items[next].focus(); return;
    }
    if (historyOpen && event.key === 'Escape' && ![...document.querySelectorAll('[role="menu"]')].some(visible)) { event.preventDefault(); setHistory(false); }
    if (historyOpen && event.key === 'Tab' && sidebar) {
      const focusable = [...sidebar.querySelectorAll('button,a[href],input,[tabindex="0"]')].filter(node => available(node) && visible(node));
      const first = focusable[0], last = focusable.at(-1);
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
    }
  }, true);
  document.addEventListener('input', event => {
    if (!config.enabled || !document.documentElement.hasAttribute('data-rivo-easy-ai')) return;
    const editor = event.target instanceof Element && event.target.closest('[data-rivo-ai-editor]');
    if (editor) { fitEditor(editor); measure(); }
  }, true);
  document.addEventListener('DOMContentLoaded', schedule, {once:true});
  window.addEventListener('pageshow', schedule);
  window.addEventListener('resize', resizeLayout);
  window.addEventListener('rivo-page-zoom', resizeLayout);
  window.visualViewport?.addEventListener('resize', resizeLayout);
})();
"""#
}
