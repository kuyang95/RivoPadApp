import Foundation

enum ReaderViewportWindow {
    static let source = #"""
// Retain lightweight block shells and markup; discard distant rendered descendants.
(() => {
  if (window.__rivoReaderWindow) return;
  const records = [], ids = new Map();
  let active = true, accessible = false, enabled = false, pending = false;
  const atomic = 'p,h1,h2,h3,h4,h5,h6,ul,ol,table,blockquote,pre,figure';
  function restore(record) {
    if (record.html === null) return false;
    record.node.innerHTML = record.html;
    record.html = null;
    if (record.style === null) record.node.removeAttribute('style'); else record.node.setAttribute('style', record.style);
    if (record.aria === null) record.node.removeAttribute('aria-hidden'); else record.node.setAttribute('aria-hidden', record.aria);
    record.node.removeAttribute('data-rivo-window-empty');
    return true;
  }
  function ensure(id) {
    const record = ids.get(id);
    if (record && restore(record)) document.dispatchEvent(new Event('rivo-reader-window-changed'));
  }
  function register(node) {
    if (node.querySelector('style,script,link,form,iframe') || node.matches('script,style,link,iframe,form,input,button,audio,video') || node.closest('svg,table,ul,ol,figure,pre,blockquote')) return;
    const record = {node, html:null, style:null, aria:null};
    records.push(record);
    if (node.id) ids.set(node.id, record);
    node.querySelectorAll('[id]').forEach(child => ids.set(child.id, record));
    node.querySelectorAll('img').forEach(img => { img.loading = 'lazy'; img.decoding = 'async'; });
  }
  function collect(parent) {
    [...parent.children].forEach(node => {
      if (node.matches(atomic) && !node.querySelector('style,script,link,form,iframe')) { // Preserve lists/tables/figures as indivisible layout blocks.
        if (!node.closest('table table,ul ul,ol ol')) {
          const record = {node, html:null, style:null, aria:null};
          records.push(record);
          if (node.id) ids.set(node.id, record);
          node.querySelectorAll('[id]').forEach(child => ids.set(child.id, record));
          node.querySelectorAll('img').forEach(img => { img.loading = 'lazy'; img.decoding = 'async'; });
        }
      } else if (node.matches('main,article,section,div') && node.children.length && ![...node.childNodes].some(n => n.nodeType === 3 && n.textContent.trim())) collect(node);
      else register(node);
    });
  }
  function pinned(record) {
    const node = record.node;
    return node.contains(document.activeElement) || node.matches('.active-segment,.rivo-reader-position') ||
      !!node.querySelector('.active-segment,.tts-word-highlight,.rivo-reader-position') ||
      !!(window.getSelection()?.anchorNode && node.contains(window.getSelection().anchorNode));
  }
  function update() {
    pending = false;
    if (!enabled || accessible) return;
    const height = Math.max(window.innerHeight, 1);
    // Read geometry together before changing any DOM.
    const geometry = records.map(record => ({record, rect:record.node.getBoundingClientRect()}));
    const anchor = geometry.find(item => item.rect.bottom > 0 && item.rect.top < height);
    let changed = false;
    geometry.forEach(({record,rect}) => {
      if (rect.bottom >= -2 * height && rect.top <= 3 * height || pinned(record)) changed = restore(record) || changed;
      else if (record.html === null && rect.height > 0 && record.node.childNodes.length) {
        record.style = record.node.getAttribute('style');
        record.aria = record.node.getAttribute('aria-hidden');
        record.html = record.node.innerHTML;
        record.node.replaceChildren();
        record.node.style.setProperty('box-sizing','border-box','important');
        ['height','min-height','max-height'].forEach(name => record.node.style.setProperty(name, rect.height + 'px','important'));
        record.node.style.setProperty('overflow','hidden','important');
        record.node.setAttribute('aria-hidden','true');
        record.node.setAttribute('data-rivo-window-empty','');
        changed = true;
      }
    });
    if (changed) {
      if (anchor) {
        const delta = anchor.record.node.getBoundingClientRect().top - anchor.rect.top;
        if (Math.abs(delta) > .5) window.scrollBy(0,delta);
      }
      document.dispatchEvent(new Event('rivo-reader-window-changed'));
    }
  }
  function schedule() {
    if (!enabled || accessible || pending) return;
    pending = true;
    requestAnimationFrame(update);
  }
  window.__rivoReaderWindow = {
    configure(value, screenReader) {
      enabled = !!value; accessible = !!screenReader;
      if (!records.length && enabled) collect(document.querySelector('.reader-content') || document.body);
      if (!enabled || accessible) {
        let restored = false;
        records.forEach(record => { restored = restore(record) || restored; });
        if (restored) document.dispatchEvent(new Event('rivo-reader-window-changed'));
      } else schedule();
    },
    ensure,
    setActive(value) {
      if (active === !!value) return;
      active = !!value;
      if (!active) {
        // The same WebView and scroll offset survive a home-page turn.
        update();
      } else {
        schedule();
      }
    },
    restoreAll() { records.forEach(restore); }
  };
  addEventListener('scroll',schedule,{passive:true});
  addEventListener('resize',() => { records.forEach(restore); schedule(); });
  document.addEventListener('focusin', event => { if (event.target.id) ensure(event.target.id); schedule(); });
  document.addEventListener('load',schedule,true);
})();

"""#
}
