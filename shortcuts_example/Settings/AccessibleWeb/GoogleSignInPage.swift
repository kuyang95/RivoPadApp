import Foundation

enum GoogleSignInPage {
    static let source = #"""
// Official Google sign-in presentation shared by YouTube and Mail. No credential bridge.
// Keep Google's own controls and submission handlers; only simplify known login steps.
(() => {
  'use strict';
  if (window.top !== window || location.hostname !== 'accounts.google.com' || window.__rivoGoogleLoginInstalled) return;
  window.__rivoGoogleLoginInstalled = true;
  const loginTheme = window.__rivoWebTheme || {bg:'#101C2D',surface:'#1C2D43',text:'#F5F3E9',edge:'#7F93AB',link:'#E6EF87'};
  const css = `
    html[data-rivo-google-login-preparing] body { visibility:hidden!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) [role="progressbar"] { position:fixed!important;left:0!important;top:0!important;right:auto!important;bottom:auto!important;transform:none!important;width:var(--rivo-google-login-width,100%)!important;max-width:none!important;height:var(--rivo-google-login-stroke,2px)!important;margin:0!important;border-radius:0!important;overflow:hidden!important;transition:none!important;z-index:2147483600!important;pointer-events:none!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) body { display:flex!important;flex-direction:column!important;align-items:center!important;justify-content:center!important;min-height:var(--rivo-google-login-height,100vh)!important;margin:0!important;box-sizing:border-box!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) body > iframe[width="0"][height="0"] { border:0!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) .X9monf { flex:0 0 auto!important;width:100%!important;max-width:624px!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) main > .zIgDIc { text-align:center!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) main > .zIgDIc > c-wiz { display:flex!important;justify-content:center!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) #headingText,
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) #headingSubtext { text-align:center!important }
    html[data-rivo-google-login] [data-rivo-login-secondary],
    html[data-rivo-google-login] footer,
    html[data-rivo-google-login] button[jsname="Cuz2Ue"],
    html[data-rivo-google-login] .RDsYTb,
    html[data-rivo-google-login] [jsname="FIbd0b"] { display:none!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) main { display:flex!important;flex-direction:column!important;align-items:stretch!important;gap:28px!important;width:100%!important;max-width:560px!important;margin:0 auto!important;box-sizing:border-box!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) main > .zIgDIc,
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) main > .UXFQgc { width:100%!important;flex-basis:auto!important;max-width:none!important;padding:0!important;margin:0!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) .qWK5J,
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) .xKcayf { width:100%!important;min-width:0!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) .O1Slxf { width:100%!important;min-width:0!important;justify-content:flex-end!important;margin-top:0!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) .TcuCfd { padding:32px 24px!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) main > .JYXaTc { width:100%!important;margin:0!important;padding:0!important;align-self:stretch!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) .O1Slxf { flex-direction:row!important }
    html[data-rivo-google-login] .FO2vFd:has([jsname="FIbd0b"]) { display:none!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) .TNTaPb,
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) #identifierNext,
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) #passwordNext { width:100%!important;margin:0!important;padding:0!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) #identifierNext > div,
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) #passwordNext > div,
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) #identifierNext button,
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) #passwordNext button { width:100%!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) #headingText { font-size:32px!important;line-height:1.3!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) #identifierId,
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) input[name="Passwd"] { font-size:22px!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) #identifierNext button,
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) #passwordNext button { min-height:64px!important;min-width:144px!important;font-size:22px!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) :is(input,button):focus-visible { outline:3px solid #0b57d0!important;outline-offset:4px!important }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) {height:auto!important;min-height:0!important;}
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) body {width:var(--rivo-google-login-width,100%)!important;height:auto!important;padding:16px!important;}
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) [data-rivo-login-container] {width:100%!important;max-width:624px!important;min-width:0!important;height:auto!important;min-height:0!important;box-sizing:border-box!important;padding:0!important;margin:0!important;}
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) main {max-width:560px!important;min-width:0!important;padding:24px!important;}
    html[data-rivo-google-step-changing] main {min-height:var(--rivo-google-step-min-height,0px)!important;}
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) {
      color-scheme:dark!important;
      --gm3-sys-color-on-surface:${loginTheme.text};--gm3-sys-color-on-surface-variant:${loginTheme.text};
      --gm3-sys-color-primary:${loginTheme.link};--gm3-sys-color-on-primary:${loginTheme.bg};
      --gm3-sys-color-surface:transparent;--gm3-sys-color-surface-container:transparent;--gm3-sys-color-outline:${loginTheme.edge};
    }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]),html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) body,
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) [data-rivo-login-container],html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) main,
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) main > :is(.zIgDIc,.UXFQgc,.JYXaTc) {
      background:transparent!important;border:0!important;box-shadow:none!important;
    }
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) main {font-family:system-ui,-apple-system,sans-serif!important;color:${loginTheme.text}!important;}
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) :is(#headingText,#headingSubtext,#headingSubtext *,label,.AxOyFc,.i9lrp) {color:${loginTheme.text}!important;-webkit-text-fill-color:${loginTheme.text}!important;}
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) input {background:transparent!important;color:${loginTheme.text}!important;-webkit-text-fill-color:${loginTheme.text}!important;caret-color:${loginTheme.link}!important;}
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) input::placeholder {color:${loginTheme.edge}!important;opacity:1!important;}
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) :is(#identifierNext,#passwordNext) button {background:${loginTheme.link}!important;color:${loginTheme.bg}!important;border:0!important;border-radius:16px!important;}
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) :is(#identifierNext,#passwordNext) button * {color:inherit!important;-webkit-text-fill-color:inherit!important;}
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) :is(input,button):focus-visible {outline-color:${loginTheme.link}!important;}
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) .rFrNMe {background:${loginTheme.surface}!important;border-radius:16px!important;}
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) .AxOyFc {background:${loginTheme.surface}!important;border-radius:4px!important;}
    /* Google's own focus outline remains; avoid a second outline on the inner input. */
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) input:focus-visible {outline:none!important;}
    html[data-rivo-google-login="password"] .Ahygpe {background:${loginTheme.surface}!important;color:${loginTheme.text}!important;border-color:${loginTheme.edge}!important;max-width:100%!important;}
    html[data-rivo-google-login="password"] .qdOxv-fmcmS-yrriRe {background:${loginTheme.surface}!important;border-radius:16px!important;}
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) {--gm3-sys-color-error:#FFB4AB;}
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) .o6cuMc {color:#FFB4AB!important;}
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) :is(.r7fnGb,[data-rivo-login-scroll-cue]) {display:none!important;}
    /* Keep Google's busy hit shield, but remove its white translucent paint. */
    html:is([data-rivo-google-login],[data-rivo-google-verification],[data-rivo-google-account-chooser]) .ZQxJQe {background:transparent!important;}
    html[data-rivo-google-login="password"] .FO2vFd button {color:${loginTheme.text}!important;background:${loginTheme.surface}!important;border:1px solid ${loginTheme.edge}!important;border-radius:16px!important;min-height:56px!important;padding:12px 20px!important;}
    html[data-rivo-google-login="password"] .FO2vFd button * {color:inherit!important;-webkit-text-fill-color:inherit!important;}
    html[data-rivo-google-verification] .O1Slxf {flex-direction:column!important;gap:12px!important;align-items:stretch!important;}
    html[data-rivo-google-verification] :is(.FO2vFd,.TNTaPb),
    html[data-rivo-google-verification] :is(.FO2vFd,.TNTaPb) button {width:100%!important;}
    html[data-rivo-google-verification] .Ahygpe {background:${loginTheme.surface}!important;color:${loginTheme.text}!important;border-color:${loginTheme.edge}!important;max-width:100%!important;}
    html[data-rivo-google-verification] main :is(div,span,p,li,label,a) {color:inherit!important;}
    html[data-rivo-google-verification] main a {color:${loginTheme.link}!important;}
    html[data-rivo-google-verification] main :is(button,[role="button"]):not(.Ahygpe) {background:${loginTheme.surface}!important;color:${loginTheme.text}!important;border:1px solid ${loginTheme.edge}!important;border-radius:16px!important;min-height:56px!important;padding:12px 20px!important;box-sizing:border-box!important;max-width:100%!important;white-space:normal!important;}
    html[data-rivo-google-verification] .TNTaPb button {background:${loginTheme.link}!important;color:${loginTheme.bg}!important;border:0!important;}
    html[data-rivo-google-verification] main :is(button,[role="button"]) * {color:inherit!important;-webkit-text-fill-color:inherit!important;}
    html[data-rivo-google-verification] input:not([type="checkbox"]):not([type="radio"]),
    html[data-rivo-google-verification] .qdOxv-fmcmS-yrriRe {background:${loginTheme.surface}!important;border-radius:16px!important;font-size:22px!important;}
    html[data-rivo-google-verification] main :is([role="alert"],.o6cuMc),
    html[data-rivo-google-verification] main :is([role="alert"],.o6cuMc) * {color:#FFB4AB!important;}
    html[data-rivo-google-verification] footer {color:${loginTheme.text}!important;}
    html[data-rivo-google-verification] footer :is(a,button,select) {color:${loginTheme.text}!important;background:${loginTheme.surface}!important;}
html[data-rivo-google-verification] footer,
html[data-rivo-google-verification] [data-rivo-verification-secondary] {display:none!important;}
html[data-rivo-google-verification] main {gap:14px!important;padding:16px!important;}
html[data-rivo-google-verification] main > .zIgDIc {display:flex!important;flex-direction:column!important;gap:8px!important;}
html[data-rivo-google-verification] .zIgDIc :is(.ObDc3,#headingText,#headingSubtext,.SOeSgb) {margin:0!important;padding:0!important;}
html[data-rivo-google-verification] .zIgDIc .a19L2 {width:28px!important;height:28px!important;}
html[data-rivo-google-verification] #headingText {font-size:26px!important;line-height:1.25!important;}
html[data-rivo-google-verification] #headingSubtext {font-size:14px!important;line-height:1.4!important;}
html[data-rivo-google-verification] .Ahygpe {min-height:36px!important;font-size:16px!important;padding:2px 8px!important;}
html[data-rivo-google-verification] .Ahygpe svg {width:24px!important;height:24px!important;}
html[data-rivo-google-verification] .Ahygpe .IxcUte {line-height:1.5!important;}
html[data-rivo-google-verification] main .UXFQgc {font-size:16px!important;line-height:1.45!important;}
html[data-rivo-google-verification] main :is(.S1zJGd,.FO2vFd,.O1Slxf,.yTaH4c,.Em2Ord,.vYeFie,.dMNVAe) {margin:0!important;padding:0!important;min-height:0!important;}
html[data-rivo-google-verification] .dMNVAe > .dMNVAe {margin-top:8px!important;}
html[data-rivo-google-verification] .x9zgF {font-size:20px!important;line-height:1.35!important;margin:0 0 8px!important;}
html[data-rivo-google-verification] .gyrWGe {margin-top:8px!important;}
html[data-rivo-google-verification] main > .JYXaTc {display:flex!important;flex-direction:column!important;gap:10px!important;}
html[data-rivo-google-verification] main :is(.S1zJGd,.XjS9D,.FO2vFd,.TNTaPb),
html[data-rivo-google-verification] .JYXaTc [data-is-touch-wrapper] {width:100%!important;}
html[data-rivo-google-verification] .JYXaTc [data-is-touch-wrapper] {display:block!important;height:auto!important;min-height:0!important;}
html[data-rivo-google-verification] main :is(button,[role="button"]):not(.Ahygpe) {min-height:44px!important;padding:8px 12px!important;font-size:16px!important;line-height:1.4!important;margin:0!important;}
html[data-rivo-google-verification] .JYXaTc button {width:100%!important;}
html[data-rivo-google-verification="dp"] .UFQPDd {display:none!important;}
html[data-rivo-google-verification] body {padding:12px!important;}
html[data-rivo-google-verification] main {gap:10px!important;padding:12px!important;}
html[data-rivo-google-verification="dp"] figure:has(.UFQPDd) {display:none!important;}
html[data-rivo-google-verification] main > .JYXaTc button {display:flex!important;justify-content:center!important;width:100%!important;}
html[data-rivo-google-verification] main > .JYXaTc .XjS9D > div {width:100%!important;min-width:0!important;flex:1!important;}

    /* Keep the original account links, including switching and removing saved accounts. */
    html:is([data-rivo-google-login],[data-rivo-google-account-chooser]) main {gap:20px!important;}
    html[data-rivo-google-account-chooser] main :is(div,span,p,li,label,a) {color:inherit!important;-webkit-text-fill-color:inherit!important;}
    html:is([data-rivo-google-login],[data-rivo-google-account-chooser]) main > .zIgDIc {display:flex!important;flex-direction:column!important;align-items:center!important;gap:14px!important;}
    html:is([data-rivo-google-login],[data-rivo-google-account-chooser]) .zIgDIc :is(.ObDc3,#headingText,#headingSubtext,.SOeSgb) {margin:0!important;padding:0!important;}
    html:is([data-rivo-google-login],[data-rivo-google-account-chooser]) .zIgDIc .ObDc3 {display:flex!important;flex-direction:column!important;align-items:center!important;gap:14px!important;width:100%!important;}
    html:is([data-rivo-google-login],[data-rivo-google-account-chooser]) .zIgDIc .a19L2 {width:32px!important;height:32px!important;padding:0!important;box-sizing:border-box!important;}
    html[data-rivo-google-account-chooser] main .Dl08I {list-style:none!important;width:100%!important;margin:0!important;padding:0!important;}
    html[data-rivo-google-account-chooser] main .Dl08I > li {width:100%!important;margin:0!important;padding:0!important;border-color:${loginTheme.edge}!important;}
    html[data-rivo-google-account-chooser] main .VV3oRb[role="link"] {display:block!important;position:relative!important;width:100%!important;max-width:100%!important;min-height:64px!important;box-sizing:border-box!important;margin:0!important;padding:16px 0!important;background:transparent!important;white-space:normal!important;font-size:20px!important;line-height:1.45!important;}
    html[data-rivo-google-account-chooser] main .VV3oRb[role="link"]:focus-visible {outline:3px solid ${loginTheme.link}!important;outline-offset:3px!important;}
    html[data-rivo-google-account-chooser] main :is(.lPxAeb,.LbOduc) {width:100%!important;max-width:100%!important;min-width:0!important;margin:0!important;padding:0!important;}
    html[data-rivo-google-account-chooser] main .LbOduc {gap:14px!important;}
    html[data-rivo-google-account-chooser] main .DOLDDf {flex:1!important;min-width:0!important;}
    html[data-rivo-google-account-chooser] main .DOLDDf > :not(.yAlK0b) {font-size:20px!important;line-height:1.45!important;}
    html[data-rivo-google-account-chooser] main .yAlK0b {font-size:16px!important;line-height:1.5!important;white-space:normal!important;overflow-wrap:anywhere!important;opacity:.8!important;}
    html[data-rivo-google-account-chooser] main .CvsT4e {font-size:18px!important;line-height:1.5!important;}
    html[data-rivo-google-account-chooser] main .VV3oRb :is(img,svg) {width:32px!important;height:32px!important;flex-shrink:0!important;}
    html[data-rivo-google-account-chooser] main > .JYXaTc {height:auto!important;min-height:0!important;margin:0!important;padding:0!important;}
    html[data-rivo-google-account-chooser] main > .JYXaTc:empty {display:none!important;}
    html[data-rivo-google-account-chooser] footer {display:none!important;}
    html[data-rivo-google-login="expired"] main {gap:28px!important;}
    html[data-rivo-google-login="expired"] :is(#headingText,#headingSubtext) {white-space:normal!important;overflow-wrap:anywhere!important;word-break:keep-all!important;}
    html[data-rivo-google-login="expired"] #headingText:focus {outline:none!important;}
    html[data-rivo-google-login="expired"] #headingSubtext {font-size:20px!important;line-height:1.6!important;}
    html[data-rivo-google-login="expired"] main > .UXFQgc:has(> .qWK5J:only-child > .xKcayf:only-child > .AcKKx:only-child:empty) {display:none!important;}
    html[data-rivo-google-login="expired"] main > .JYXaTc,
    html[data-rivo-google-login="expired"] .JYXaTc :is(.O1Slxf,.TNTaPb,.XjS9D,.VfPpkd-dgl2Hf-ppHlrf-sM5MNb) {display:block!important;width:100%!important;height:auto!important;min-height:0!important;box-sizing:border-box!important;margin:0!important;padding:0!important;}
    html[data-rivo-google-login="expired"] [data-rivo-expired-retry] {display:flex!important;align-items:center!important;justify-content:center!important;width:100%!important;min-height:64px!important;height:auto!important;box-sizing:border-box!important;margin:0!important;padding:16px 24px!important;border:0!important;border-radius:16px!important;background:${loginTheme.link}!important;color:${loginTheme.bg}!important;font-size:22px!important;line-height:1.4!important;white-space:normal!important;overflow-wrap:anywhere!important;overflow:hidden!important;-webkit-tap-highlight-color:transparent!important;transition:opacity 120ms ease-out!important;}
    html[data-rivo-google-login="expired"] [data-rivo-expired-retry] * {color:inherit!important;-webkit-text-fill-color:inherit!important;}
    html[data-rivo-google-login="expired"] [data-rivo-expired-retry] :is(.VfPpkd-Jh9lGc,.VfPpkd-J1Ukfc-LhBDec,.VfPpkd-RLmnJb) {display:none!important;}
    html[data-rivo-google-login="expired"] [data-rivo-expired-retry][data-rivo-pressed] {opacity:.78!important;}
    html[data-rivo-google-login="expired"] [data-rivo-expired-retry]:focus-visible {outline:3px solid ${loginTheme.link}!important;outline-offset:4px!important;}
    html[data-rivo-google-login="expired"] .HwUrwe {position:absolute!important;width:1px!important;height:1px!important;margin:-1px!important;overflow:hidden!important;clip-path:inset(50%)!important;}
    @media(prefers-reduced-motion:reduce) {html[data-rivo-google-login="expired"] [data-rivo-expired-retry] {transition:none!important;}}
  `;
  let waitingForDOM = document.readyState === 'loading';
  const pathMode = () => /\/(?:v3\/signin|signin\/v2)\/identifier\/?$/.test(location.pathname) ? 'identifier'
    : /\/(?:v3\/signin|signin\/v2)\/challenge\/pwd\/?$/.test(location.pathname) ? 'password' : null;
  const verificationPath = () => /^\/(?:v3\/signin|signin\/v2)\/challenge\/(?!pwd(?:\/|$))[^/]+\/?$/.test(location.pathname);
  const accountChooserPath = () => /^(?:\/(?:v3\/signin|signin\/v2)\/accountchooser|\/AccountChooser)\/?$/i.test(location.pathname);
  const expiredPath = () => /^\/info\/sessionexpired\/?$/.test(location.pathname);
  const sizeViewport = () => {
    const zoom = parseFloat(getComputedStyle(document.documentElement).zoom) || 1;
    const viewport = window.visualViewport;
    const stroke = `${2 / zoom}px`;
    if (document.documentElement.style.getPropertyValue('--rivo-google-login-stroke') !== stroke)
      document.documentElement.style.setProperty('--rivo-google-login-stroke', stroke);
    for (const [name, value] of [['height',(viewport?.height || window.innerHeight) / zoom],['width',(viewport?.width || window.innerWidth) / zoom]]) {
      const pixels = `${Math.max(1, value)}px`;
      if (document.documentElement.style.getPropertyValue(`--rivo-google-login-${name}`) !== pixels)
        document.documentElement.style.setProperty(`--rivo-google-login-${name}`, pixels);
    }
  };
  const visible = element => !!element && element.getClientRects().length > 0 && getComputedStyle(element).visibility !== 'hidden';
  const expiredText = new Map(), expiredButtons = new WeakSet();
  let expiredFocus = null;
  const restoreExpired = () => {
    for (const [node, saved] of expiredText) {
      if (node.isConnected && node.textContent === saved.applied) node.textContent = saved.original;
    }
    expiredText.clear();
    if (expiredFocus) {
      if (expiredFocus.tabindex === null) expiredFocus.node.removeAttribute('tabindex');
      else expiredFocus.node.setAttribute('tabindex', expiredFocus.tabindex);
      expiredFocus = null;
    }
    document.querySelectorAll('[data-rivo-expired-retry]').forEach(button => {
      button.removeAttribute('data-rivo-expired-retry');button.removeAttribute('data-rivo-pressed');
    });
  };
  const presentExpired = (heading, subtitle, retry, label) => {
    const language = (document.documentElement.lang || navigator.language || 'en').toLowerCase();
    const copy = language.startsWith('ko')
      ? ['다시 로그인해 주세요', '시간이 지나 이전 로그인 화면을 사용할 수 없어요.', '다시 로그인']
      : language.startsWith('ja')
        ? ['もう一度ログインしてください', '時間が経過したため、このログイン画面は使えません。', 'もう一度ログイン']
        : ['Start sign-in again', 'This sign-in screen has expired. Please try again.', 'Sign in again'];
    for (const [node, text] of [[heading.querySelector('span') || heading, copy[0]], [subtitle.querySelector('span') || subtitle, copy[1]], [label, copy[2]]]) {
      if (!expiredText.has(node)) expiredText.set(node, {original:node.textContent, applied:text});
      else expiredText.get(node).applied = text;
      if (node.textContent !== text) node.textContent = text;
    }
    retry.setAttribute('data-rivo-expired-retry', '');
    if (!expiredButtons.has(retry)) {
      expiredButtons.add(retry);
      const release = () => retry.removeAttribute('data-rivo-pressed');
      retry.addEventListener('pointerdown', event => {if (event.isPrimary && event.button === 0) retry.setAttribute('data-rivo-pressed', '');});
      for (const event of ['pointerup','pointercancel','pointerleave','lostpointercapture','blur']) retry.addEventListener(event, release);
      retry.addEventListener('keydown', event => {if (event.key === ' ' || event.key === 'Enter') retry.setAttribute('data-rivo-pressed', '');});
      retry.addEventListener('keyup', release);
    }
    if (expiredFocus?.node !== heading) {
      expiredFocus = {node:heading, tabindex:heading.getAttribute('tabindex')};
      heading.setAttribute('tabindex', '-1');
      requestAnimationFrame(() => {
        if (heading.isConnected && document.visibilityState === 'visible' && document.documentElement.getAttribute('data-rivo-google-login') === 'expired')
          heading.focus({preventScroll:true});
      });
    }
  };
  let previousStep = null, previousHeight = 0, releaseFrame = 0;
  const stabilizeStepHeight = (basicForm, chooserReady, themed) => {
    const root = document.documentElement, main = document.querySelector('main');
    const step = pathMode() || (accountChooserPath() ? 'chooser' : null);
    if (!themed || !step || !main) {
      root.removeAttribute('data-rivo-google-step-changing');previousStep = null;previousHeight = 0;
      cancelAnimationFrame(releaseFrame);return;
    }
    if (previousStep && step !== previousStep && previousHeight > 0) {
      root.style.setProperty('--rivo-google-step-min-height', `${previousHeight}px`);
      root.setAttribute('data-rivo-google-step-changing', '');
    }
    previousStep = step;
    const measure = () => main.getBoundingClientRect().height / (parseFloat(getComputedStyle(root).zoom) || 1);
    if (!root.hasAttribute('data-rivo-google-step-changing')) previousHeight = measure();
    else if (basicForm || chooserReady) {
      cancelAnimationFrame(releaseFrame);
      releaseFrame = requestAnimationFrame(() => {
        releaseFrame = requestAnimationFrame(() => {
          if (step !== previousStep) return;
          root.removeAttribute('data-rivo-google-step-changing');previousHeight = measure();
        });
      });
    }
  };
  // Complete only Google's sliding step track, preserving its own cleanup handlers.
  // Never cancel input/focus, progress, challenge or dialog animations.
  const finishStepSlide = () => {
    if (!document.documentElement.matches('[data-rivo-google-login="identifier"],[data-rivo-google-login="password"],[data-rivo-google-account-chooser]')) return;
    for (const animation of document.getAnimations()) {
      if (animation.playState !== 'running' || !animation.effect?.target?.matches?.('main .qWK5J') ||
          !animation.effect.getKeyframes().some(frame => frame.transform?.includes('translate'))) continue;
      try { animation.finish(); } catch (_) { /* An unfinished/unbounded effect keeps its original behavior. */ }
    }
  };
  const update = () => {
    let style = document.getElementById('rivo-google-login-style');
    if (!style) {
      style = document.createElement('style');style.id = 'rivo-google-login-style';style.textContent = css;
      (document.head || document.documentElement).appendChild(style);
    }
    if (waitingForDOM) {
      const mode = pathMode() || (expiredPath() ? 'expired' : null);
      if (mode) {
        sizeViewport();
        document.documentElement.setAttribute('data-rivo-google-login', mode);
        document.documentElement.setAttribute('data-rivo-google-login-preparing', '');
      }
      if (accountChooserPath()) {
        sizeViewport();
        document.documentElement.setAttribute('data-rivo-google-account-chooser', '');
        document.documentElement.setAttribute('data-rivo-google-login-preparing', '');
      }
      return;
    }
    document.documentElement.removeAttribute('data-rivo-google-login-preparing');
    const identifier = pathMode() === 'identifier' && document.getElementById('identifierId') && document.getElementById('identifierNext');
    const password = pathMode() === 'password' && document.querySelector('input[name="Passwd"]') && document.getElementById('passwordNext');
    const extraCheck = [...document.querySelectorAll('[role="dialog"],[role="alertdialog"],#ca,iframe[src*="recaptcha"]')].some(visible);
    const expiredHeading = document.querySelector('main #headingText');
    const expiredSubtitle = document.querySelector('main #headingSubtext');
    const expiredRetry = document.querySelector('main > .JYXaTc button[jsname="LgbsSe"]');
    const expiredLabel = expiredRetry?.querySelector('[jsname="V67aGc"]');
    const expired = !extraCheck && expiredPath() && expiredHeading && expiredSubtitle && expiredRetry && expiredLabel && !document.querySelector('main input,main textarea,main select');
    if (expired) presentExpired(expiredHeading, expiredSubtitle, expiredRetry, expiredLabel);
    else restoreExpired();
    const basicForm = document.querySelector('main #headingText') && (identifier ? 'identifier' : password ? 'password' : null);
    // Recognition uses structure only; never read account identifiers or credential values.
    const chooserReady = accountChooserPath() && !!document.querySelector('main #headingText') &&
      (!!document.querySelector('main [data-identifier][role="link"],main [data-authuser][role="link"],main ul.Dl08I [role="link"]') ||
        (document.documentElement.hasAttribute('data-rivo-google-account-chooser') && !!document.querySelector('[aria-busy="true"]')));
    // Google changes the SPA route before replacing the old step's DOM. Keep the
    // recognized presentation through that gap, including when aria-busy clears early.
    // Unknown routes and visible security dialogs still restore Google's original UI.
    const knownStep = !!pathMode() || accountChooserPath();
    const chooser = !extraCheck && (chooserReady || (!basicForm && knownStep && document.documentElement.hasAttribute('data-rivo-google-account-chooser')));
    const busyMode = knownStep && !chooser ? document.documentElement.getAttribute('data-rivo-google-login') : null;
    const mode = !extraCheck ? (expired ? 'expired' : basicForm || busyMode) : null;
    if (chooser) document.documentElement.setAttribute('data-rivo-google-account-chooser', '');
    else document.documentElement.removeAttribute('data-rivo-google-account-chooser');
    // Challenge pages keep every instruction, method choice, input and original handler.
    const verification = !extraCheck && verificationPath() && !!document.querySelector('main #headingText');
    if (verification) document.documentElement.setAttribute('data-rivo-google-verification', location.pathname.split('/').filter(Boolean).at(-1));
    else document.documentElement.removeAttribute('data-rivo-google-verification');
    if (verification) {
      for (const button of document.querySelectorAll('main button')) {
        if (/^(Google 메시지 자세히 알아보기|Learn more about Google prompts|Google からのメッセージの詳細)$/i.test(button.textContent.trim())) {
          button.setAttribute('data-rivo-verification-secondary', '');
          for (const node of [...button.parentElement.childNodes]) {
            if (node.nodeType === Node.TEXT_NODE && /도움이 필요하세요|Need help|ヘルプ/i.test(node.textContent)) {
              const span = document.createElement('span');
              span.setAttribute('data-rivo-verification-secondary', '');
              node.replaceWith(span);span.appendChild(node);
            }
          }
        }
      }
    }
    document.querySelectorAll('[data-rivo-login-container]').forEach(element => element.removeAttribute('data-rivo-login-container'));
    if (mode || verification || chooser) {
      for (let container = document.querySelector('main')?.parentElement; container && container !== document.body; container = container.parentElement)
        container.setAttribute('data-rivo-login-container', '');
      for (const button of document.querySelectorAll('button[aria-label]')) {
        if (/^(아래로 스크롤|Scroll down|下にスクロール)$/i.test(button.getAttribute('aria-label').trim()))
          button.closest('.r7fnGb')?.setAttribute('data-rivo-login-scroll-cue', '');
      }
      if (mode) for (const link of document.querySelectorAll('button,a,[role="button"]')) {
        if (/^(비밀번호를 잊으셨나요\??|Forgot password\??|パスワードをお忘れの場合)$/i.test(link.textContent.trim()))
          link.setAttribute('data-rivo-login-secondary', '');
      }
      sizeViewport();
    }
    if (mode) document.documentElement.setAttribute('data-rivo-google-login', mode);
    else document.documentElement.removeAttribute('data-rivo-google-login');
    stabilizeStepHeight(basicForm, chooserReady, mode || chooser);
    finishStepSlide();
    if (mode || chooser) requestAnimationFrame(finishStepSlide);
  };
  let scheduled = false;
  const schedule = () => { if (!scheduled) { scheduled = true;queueMicrotask(() => { scheduled = false;update(); }); } };
  let started = false;
  let rootObserver;
  const start = () => {
    if (started || !document.documentElement) return;
    started = true;
    rootObserver?.disconnect();
    update();
    if (waitingForDOM) {
      const finish = () => { waitingForDOM = false;clearTimeout(timeout);update(); };
      const timeout = setTimeout(finish, 10000);
      document.addEventListener('DOMContentLoaded', finish, {once:true});
    }
    new MutationObserver(schedule).observe(document.documentElement, {subtree:true,childList:true,attributes:true,attributeFilter:['hidden','aria-hidden','aria-busy','type','class','style']});
    window.addEventListener('popstate', schedule);
    window.addEventListener('hashchange', schedule);
    window.addEventListener('resize', schedule);
    window.visualViewport?.addEventListener('resize', schedule);
    window.addEventListener('rivo-page-zoom', schedule);
  };
  // Document-start scripts can run before <html> exists. Apply before its first paint.
  if (document.documentElement) start();
  else {
    rootObserver = new MutationObserver(start);
    rootObserver.observe(document, {childList:true});
  }
})();
"""#
}
