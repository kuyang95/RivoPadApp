import Foundation

enum LauncherWebAppearance {
    static let source = #"""
// Only installed in launcher widget sessions; standalone browsers keep their page canvas.
window.__rivoLauncherEmbedded = true;
(() => {
  const apply = () => {
    if (!document.documentElement) return;
    document.documentElement.setAttribute('data-rivo-launcher-widget', '');
    if (document.getElementById('rivo-launcher-canvas')) return;
    const style = document.createElement('style');
    style.id = 'rivo-launcher-canvas';
    // Original view restores the site's canvas as well as its foreground colours.
    // Simplified YouTube owns its own dark presentation and stays transparent.
    const canvasMode = window.__rivoLauncherBrowser ? '[data-rivo-web-enabled][data-rivo-web-palette="dark"]' : '';
    style.textContent = `html[data-rivo-launcher-widget][data-rivo-launcher-widget][data-rivo-launcher-widget]${canvasMode},
      html[data-rivo-launcher-widget][data-rivo-launcher-widget][data-rivo-launcher-widget]${canvasMode} body,
      html[data-rivo-launcher-widget][data-rivo-launcher-widget][data-rivo-launcher-widget]${canvasMode} [data-rivo-web-canvas]:not([data-rivo-web-mask]) {
        background-color:transparent!important;
      }
      html[data-rivo-launcher-widget]:has(> [data-rivo-you-tube-home]) body[inert] {
        visibility:hidden!important;
      }
      html[data-rivo-launcher-widget]:has(> [data-rivo-official-player]) > [data-rivo-you-tube-home] {
        visibility:hidden!important;
      }`;
    document.documentElement.appendChild(style);
  };
  apply();
  if (!document.documentElement) document.addEventListener('DOMContentLoaded', apply, {once:true});
})();

// Only hit geometry is returned to the native recognizer; page content stays in the WebView.
(() => {
  if(window!==window.top)return;
  window.__rivoLauncherCanPageAt=(fractionX,fractionY)=>{
    if(!window.__rivoLauncherBrowser && !document.querySelector('[data-rivo-you-tube-home],[data-rivo-official-player]'))return false;
    const viewport=window.visualViewport;
    const x=(viewport?.offsetLeft||0)+fractionX*(viewport?.width||innerWidth);
    const y=(viewport?.offsetTop||0)+fractionY*(viewport?.height||innerHeight);
    let target=document.elementFromPoint(x,y);
    while(target?.shadowRoot){const child=target.shadowRoot.elementFromPoint(x,y);if(!child||child===target)break;target=child;}
    const simpleHome=window.__rivoLauncherBrowser && document.documentElement.getAttribute('data-rivo-google-simple')==='home';
    // The authored Google home has no horizontal content scrollers. Its favorite
    // grid and the empty viewport below it belong to launcher paging as well.
    if(!target)return simpleHome;
    if(target.closest('input,select,textarea,[contenteditable]:not([contenteditable="false"])'))return false;
    if(simpleHome)return true;
    if (window.__rivoLauncherBrowser) {
      // Navigation controls own their gestures even before async site code has
      // measured a tab track. Home paging remains available on the body/dots.
      if (target.closest('nav,header,[role="navigation"],[role="tablist"],[role="slider"]')) return false;
      const page = document.scrollingElement;
      if (page && page.scrollWidth > page.clientWidth + 2) return false;
      for (let node = target; node; node = node.parentElement || node.getRootNode()?.host) {
        const paint = getComputedStyle(node);
        if (paint.touchAction === 'none') return false;
        if (node.scrollWidth > node.clientWidth + 2) {
          if (/auto|scroll/.test(paint.overflowX)) return false;
          // Scripted carousels can clip a translated track instead of exposing
          // a native scroller. Their deliberate horizontal gesture stays on the web.
          if (/hidden|clip/.test(paint.overflowX) && (/pan-y/.test(paint.touchAction) ||
              [...node.children].some(child => getComputedStyle(child).transform !== 'none' ||
                (child.scrollWidth > node.clientWidth + 2 && child.children.length > 1)))) return false;
        }
      }
    }
    if(target.tagName==='IFRAME' && document.querySelector('[data-rivo-official-player]')){
      const bounds=target.getBoundingClientRect();
      // The official player's top controls and bottom seek bar keep their own drags.
      if(y<bounds.top+56 || y>bounds.bottom-72)return false;
    }
    return true;
  };
})();

// Browser and simplified YouTube surfaces page the launcher; vertical pans remain web scrolling.
(() => {
  if (window !== window.top || window.__rivoLauncherNativeSwipe || window.__rivoLauncherPageSwipe) return;
  window.__rivoLauncherPageSwipe = true;
  let drag = null, suppressClickUntil = 0;
  document.addEventListener('touchstart', event => {
    drag = null;
    if (event.touches.length !== 1) return;
    const path = event.composedPath();
    if (!window.__rivoLauncherBrowser && !path.some(node => node.matches?.('[data-rivo-you-tube-home],[data-rivo-official-player]'))) return;
    if (path.some(node => node.matches?.('input,select,textarea,iframe,[contenteditable="true"]'))) return;
    const point = event.touches[0];
    if (window.__rivoLauncherBrowser && !window.__rivoLauncherCanPageAt?.(point.clientX / innerWidth, point.clientY / innerHeight)) return;
    drag = {x:point.clientX,y:point.clientY,dx:0,axis:null};
  }, {passive:true});
  document.addEventListener('touchmove', event => {
    if (!drag) return;
    if (event.touches.length !== 1) { drag = null; return; }
    const point = event.touches[0], dx = point.clientX-drag.x, dy = point.clientY-drag.y;
    if (!drag.axis && Math.max(Math.abs(dx),Math.abs(dy)) >= 12) {
      // Ambiguous and predominantly vertical gestures belong to web scrolling.
      drag.axis = Math.abs(dx) > Math.abs(dy)*1.5 ? 'horizontal' : 'vertical';
    }
    if (drag.axis === 'horizontal') {
      if (!event.cancelable) { drag = null; return; }
      event.preventDefault();
      drag.dx = dx;
    }
  }, {passive:false});
  document.addEventListener('touchend', event => {
    const finished = drag; drag = null;
    if (!finished || event.touches.length || finished.axis !== 'horizontal') return;
    suppressClickUntil = performance.now()+500;
    if (Math.abs(finished.dx) < Math.max(64,(window.visualViewport?.width||innerWidth)*.15)) return;
    location.href = 'rivo-launcher://page/' + (finished.dx < 0 ? 'next' : 'previous');
  }, {passive:true});
  document.addEventListener('touchcancel', () => { drag = null; }, {passive:true});
  document.addEventListener('click', event => {
    if (performance.now() < suppressClickUntil) { event.preventDefault(); event.stopImmediatePropagation(); }
  }, true);
})();

// Preserve authored layout. Overflow can be an intentional carousel, sprite or
// fixed control, so it must not trigger structural rewrites of arbitrary pages.
// iPad uses this bridge for layout zoom; Android has its shared page-zoom script.
(() => {
  if (!window.__rivoLauncherBrowser || window.__rivoLauncherReflow) return;
  let requestedZoom = null;
  const apply = () => {
    if (requestedZoom === null || !document.documentElement) return;
    document.documentElement.style.setProperty('zoom', String(requestedZoom), 'important');
  };
  window.__rivoLauncherReflow = {setZoom(scale) {
    if (!Number.isFinite(scale)) return;
    requestedZoom = Math.min(3, Math.max(.75, scale));
    apply();
  }};
  if (!document.documentElement) {
    const observer = new MutationObserver(() => {
      if (document.documentElement) { observer.disconnect(); apply(); }
    });
    observer.observe(document, {childList:true});
  }
})();
"""#
}
