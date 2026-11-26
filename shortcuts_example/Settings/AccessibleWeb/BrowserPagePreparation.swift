enum BrowserPagePreparation {
    static func bootstrap(appearanceEnabled: Bool, simpleGoogleEnabled: Bool, palette: AccessibleWebPalette, embedded: Bool) -> String {
        source + "({appearanceEnabled:\(appearanceEnabled),simpleGoogleEnabled:\(simpleGoogleEnabled),palette:'\(palette.rawValue)',embedded:\(embedded)});"
    }

    private static let source = #"""
(({appearanceEnabled, simpleGoogleEnabled, palette, embedded}) => {
  if (window !== window.top || document.readyState !== 'loading' || document.contentType !== 'text/html' ||
      !/^https?:$/.test(location.protocol) || window.__rivoBrowserPreparation) return;
  const googlePage = location.protocol === 'https:' && /^(www\.)?google\.(com|co\.kr)$/i.test(location.hostname) &&
    ['/', '/webhp', '/search'].includes(location.pathname);
  if (!appearanceEnabled && !(simpleGoogleEnabled && googlePage)) return;

  const style = document.createElement('style');
  const canvas = embedded ? 'transparent' : palette === 'dark' ? '#202124' : '#FFFFFF';
  style.textContent = `
    :root { background: ${canvas} !important; }
    :root > body { opacity: 0 !important; visibility: hidden !important; transition: none !important; }
  `;
  const mount = () => {
    if (!document.documentElement) return;
    observer.disconnect();
    document.documentElement.append(style);
  };
  const observer = new MutationObserver(mount);
  let finished = false;
  const finish = () => {
    if (finished) return;
    finished = true;
    clearTimeout(deadline);
    observer.disconnect();
    document.removeEventListener('DOMContentLoaded', finish);
    window.__rivoBrowserPreparation = null;
    // Restore authored styles before measuring. Paint happens after both passes.
    style.remove();
    try { window.__rivoGoogleSimple?.refresh(); }
    finally { window.__rivoAccessibleWeb?.refreshInitialPaint(); }
  };
  const deadline = setTimeout(finish, 1200);
  window.__rivoBrowserPreparation = {finish};
  document.addEventListener('DOMContentLoaded', finish, {once:true});
  if (document.documentElement) mount();
  else observer.observe(document, {childList:true});
})
"""#
}
