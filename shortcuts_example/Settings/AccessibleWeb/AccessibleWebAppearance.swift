#if DEBUG
import Foundation

enum AccessibleWebPalette: String, CaseIterable, Identifiable {
    case dark, light, contrast

    var id: String { rawValue }
    var title: String {
        switch self {
        case .dark: "어둡게"
        case .light: "밝게"
        case .contrast: "고대비"
        }
    }
}

/// No page text, credentials, or images cross a native JavaScript bridge.
/// This script runs in a separate WKContentWorld and only changes presentation.
enum AccessibleWebAppearance {
    static func configuration(enabled: Bool, palette: AccessibleWebPalette) -> String {
        "{enabled: \(enabled), palette: '\(palette.rawValue)'}"
    }

    static func bootstrap(enabled: Bool, palette: AccessibleWebPalette) -> String {
        source + "\nwindow.__rivoAccessibleWeb.set(\(configuration(enabled: enabled, palette: palette)));"
    }

    static let source = #"""
    (() => {
      if (window.__rivoAccessibleWeb) return;
      const palettes = {
        dark: {bg:'#000000', surface:'#171717', text:'#F0F4FA', edge:'#BBC6D7', link:'#FFD166', scheme:'dark'},
        light: {bg:'#FFFFFF', surface:'#F0F2F5', text:'#283546', edge:'#536176', link:'#704000', scheme:'light'},
        contrast: {bg:'#000000', surface:'#000000', text:'#FFFF00', edge:'#FFFF00', link:'#FFFFFF', scheme:'dark'}
      };
      const preserved = 'img,picture,video,canvas,svg,math,iframe,object,embed,input[type="image"],input[type="color"],[role="img"],[data-rivo-web-preserve]';
      const skipped = 'script,style,link,meta,head,title,noscript,template';
      const controls = 'button,input,select,textarea,[role="button"],[role="combobox"],[role="textbox"],summary';
      let config = {enabled: true, palette: 'dark'};
      let style;
      let timer;
      const pending = new Set();
      // Preserve content whose colour is information. This is intentionally
      // conservative: media stays original unless a small graphic is identified as a UI control.
      // Translucent paint often sits over a photograph. Never turn it opaque.
      function alpha(colour) {
        if (colour === 'transparent') return 0;
        const commaAlpha = colour.match(/^rgba\([^)]*,\s*([\d.]+)\s*\)$/);
        const slashAlpha = colour.match(/\/\s*([\d.]+)(%)?\s*\)$/);
        if (commaAlpha) return Number(commaAlpha[1]);
        if (slashAlpha) return Number(slashAlpha[1]) / (slashAlpha[2] ? 100 : 1);
        return 1;
      }
      function isOpaque(colour) { return alpha(colour) >= 1; }
      function transparentText(paint) {
        return alpha(paint.color) === 0 || alpha(paint.webkitTextFillColor || paint.color) === 0;
      }
      function decorativeGradient(image, overMedia) {
        return !overMedia && /gradient\(/i.test(image) && !/url\(|image-set\(/i.test(image);
      }
      function isBaseSurface(colour) {
        const channels = colour.match(/^rgba?\(\s*([\d.]+)[, ]+([\d.]+)[, ]+([\d.]+)/);
        if (!channels) return false;
        const rgb = channels.slice(1).map(Number), low = Math.min(...rgb), high = Math.max(...rgb);
        return high - low <= 24 && (high <= 32 || (low >= 180 && low < 248));
      }
      function classifyBorders(element, paint, prefix) {
        for (const side of ['top','right','bottom','left']) {
          element.toggleAttribute(prefix + 'border-' + side,
            !(prefix === 'data-rivo-web-' && element.matches(controls) && paint.appearance !== 'none') &&
            parseFloat(paint.getPropertyValue('border-' + side + '-width')) > 0 &&
            isOpaque(paint.getPropertyValue('border-' + side + '-color')));
        }
      }
      const iconControl = 'button,a[href],[role="button"],[role="link"],summary';
      // These are preservation hints only; names never qualify a graphic for recolouring.
      const originalToken = /(?:^|[\s_/.:-])(?:logo|brand|avatar|photo|thumbnail|thumb|product|goods|swatch|colorchip|colourchip|map|chart|rating)(?:$|[\s_/.:-])|로고|브랜드|상품|사진|별점/;
      function identityOf(element) {
        return ['id','class','alt','aria-label','title'].map(name => element.getAttribute(name) || '').join(' ')
          .replace(/([a-z])([A-Z])/g, '$1 $2').toLowerCase();
      }
      function smallGraphic(width, height) {
        return width >= 4 && height >= 4 && width <= 64 && height <= 64;
      }
      function hiddenIconLabel(element, paint) {
        if (transparentText(paint) || parseFloat(paint.fontSize) === 0 || parseFloat(paint.textIndent) < -100) return true;
        return [...element.childNodes].every(node => {
          if (node.nodeType === Node.TEXT_NODE) return !node.textContent.trim();
          if (!(node instanceof Element) || !node.textContent.trim()) return true;
          const rect = node.getBoundingClientRect(), p = getComputedStyle(node);
          return (rect.width <= 2 && rect.height <= 2) || p.display === 'none' || p.visibility === 'hidden' || transparentText(p);
        });
      }
      function neutralPaint(colour) {
        const m = colour.match(/^rgba?\(\s*([\d.]+)[, ]+([\d.]+)[, ]+([\d.]+)/);
        if (!m || alpha(colour) < 1) return null;
        const rgb = m.slice(1).map(Number);
        return Math.max(...rgb) - Math.min(...rgb) <= 20 ? (rgb[0] + rgb[1] + rgb[2]) / 3 : null;
      }
      const imageCache = new Map();
      const regionCache = new Map();
      const imageQueue = [];
      let activeImages = 0;
      let cachedPixels = 0;
      function drainImages() {
        while (activeImages < 4 && imageQueue.length) {
          const entry = imageQueue.shift();
          activeImages++;
          const image = new Image();
          let finished = false;
          const finish = success => {
            if (finished) return;
            finished = true;
            clearTimeout(timeout);
            image.onload = image.onerror = null;
            const pixels = image.naturalWidth * image.naturalHeight;
            entry.state = success && pixels > 0 && pixels <= 8000000 && cachedPixels + pixels <= 32000000 ? 'ready' : 'unreadable';
            if (entry.state === 'ready') { entry.image = image; cachedPixels += pixels; }
            activeImages--;
            for (const target of entry.targets) if (target.isConnected) schedule(target);
            entry.targets.clear();
            drainImages();
          };
          const timeout = setTimeout(() => finish(false), 8000);
          image.onload = () => finish(true);
          image.onerror = () => finish(false);
          // Read only what the image server permits. No native proxy or credential bridge.
          image.crossOrigin = 'anonymous';
          image.src = entry.url;
        }
      }
      function readableImage(url, target) {
        let entry = imageCache.get(url);
        if (!entry) {
          if (imageCache.size >= 64 || !/^(https?:|data:image\/|blob:)/i.test(url)) return null;
          entry = {url, state:'loading', targets:new Set()};
          imageCache.set(url, entry);
          imageQueue.push(entry);
        }
        if (entry.state === 'loading') entry.targets.add(target);
        drainImages();
        return entry.state === 'ready' ? entry.image : null;
      }
      function singleImage(value) {
        const match = value.match(/^url\((?:"([^"]*)"|'([^']*)'|([^)]*))\)$/);
        if (!match) return null;
        try { return new URL(match[1] ?? match[2] ?? match[3], document.baseURI).href; } catch (_) { return null; }
      }
      function backgroundRect(image, width, height, paint) {
        let w = image.naturalWidth, h = image.naturalHeight;
        const sizes = paint.backgroundSize.split(/\s+/);
        const length = (value, total) => value.endsWith('%') ? parseFloat(value) * total / 100 :
          /^(?:\d*\.)?\d+px$/.test(value) ? parseFloat(value) : null;
        if (sizes[0] === 'cover' || sizes[0] === 'contain') {
          const ratio = (sizes[0] === 'cover' ? Math.max : Math.min)(width / w, height / h);
          w *= ratio; h *= ratio;
        } else {
          const x = length(sizes[0], width), y = length(sizes[1] || 'auto', height);
          if (x !== null && y !== null) { w = x; h = y; }
          else if (x !== null) { h *= x / w; w = x; }
          else if (y !== null) { w *= y / h; h = y; }
          else if (sizes.some(s => s !== 'auto')) return null;
        }
        const position = (value, space) => value.endsWith('%') ? parseFloat(value) * space / 100 :
          /^-?[\d.]+px$/.test(value) ? parseFloat(value) : null;
        const x = position(paint.backgroundPositionX, width - w), y = position(paint.backgroundPositionY, height - h);
        if (x === null || y === null || w <= 0 || h <= 0) return null;
        // Repeated, layered and ambiguous background layouts stay original.
        if (paint.backgroundRepeat !== 'no-repeat' && (x > 0 || y > 0 || x + w < width || y + h < height)) return null;
        return [x,y,w,h];
      }
      function monochromePixels(image, width, height, rect) {
        const key = [image.src,width,height,...rect].join('|');
        if (regionCache.has(key)) return regionCache.get(key);
        let result = false;
        try {
          const canvas = document.createElement('canvas');
          canvas.width = canvas.height = 64;
          const context = canvas.getContext('2d', {willReadFrequently:true});
          context.drawImage(image, rect[0] * 64 / width, rect[1] * 64 / height, rect[2] * 64 / width, rect[3] * 64 / height);
          const pixels = context.getImageData(0,0,64,64).data;
          let clear = 0, solid = 0, coloured = 0, total = 0, square = 0;
          for (let i = 0; i < pixels.length; i += 4) {
            const r=pixels[i], g=pixels[i+1], b=pixels[i+2], a=pixels[i+3];
            if (a <= 16) { clear++; continue; }
            if (Math.max(r,g,b) - Math.min(r,g,b) > 20) coloured++;
            if (a >= 240) {
              const level = (r+g+b) / 3;
              solid++; total += level; square += level * level;
            }
          }
          // A flat neutral silhouette on transparency, not merely a greyscale photo.
          const mean = total / solid, variance = square / solid - mean * mean;
          result = clear >= 819 && clear <= 3891 && solid >= 24 && coloured <= 2 && variance <= 36;
        } catch (_) {
          // A tainted canvas/CORS failure never implies that this is an icon.
        }
        if (regionCache.size < 512) regionCache.set(key, result);
        return result;
      }
      function rasterGraphic(element, paint, width, height, source, background) {
        if (!source || !smallGraphic(width,height) || alpha(paint.backgroundColor) !== 0 || paint.filter !== 'none') return false;
        const image = readableImage(source, element);
        if (!image) return false;
        const rect = background ? backgroundRect(image,width,height,paint) : [0,0,width,height];
        return rect !== null && monochromePixels(image,width,height,rect);
      }
      function classifyIcon(element) {
        for (const suffix of ['ui-icon','before-ui-icon','after-ui-icon','icon-fill','icon-stroke']) {
          element.removeAttribute('data-rivo-web-' + suffix);
        }
        if (element.closest('[data-rivo-web-preserve],picture,video,canvas,math')) return;
        const svg = element.closest('svg');
        if (svg && svg !== element) {
          if (!svg.hasAttribute('data-rivo-web-ui-icon')) return;
          const paint = getComputedStyle(element);
          element.toggleAttribute('data-rivo-web-icon-fill', neutralPaint(paint.fill) !== null);
          element.toggleAttribute('data-rivo-web-icon-stroke', neutralPaint(paint.stroke) !== null);
          return;
        }
        // Structure/size limit the inspection area; names do not select an icon kind.
        const control = element.closest(iconControl);
        if (!control) return;
        let ancestor = element;
        while (ancestor) {
          if (originalToken.test(identityOf(ancestor))) return;
          if (ancestor === control) break;
          ancestor = ancestor.parentElement;
        }
        const paint = getComputedStyle(element), rect = element.getBoundingClientRect();
        if (element.matches('svg') && smallGraphic(rect.width,rect.height)) {
          if (alpha(paint.backgroundColor) !== 0) return;
          const viewport = element.viewBox.baseVal;
          const viewWidth = viewport.width || element.width.baseVal.value;
          const viewHeight = viewport.height || element.height.baseVal.value;
          const levels = [];
          for (const part of element.querySelectorAll('*')) {
            if (part.matches('image,foreignObject,linearGradient,radialGradient,pattern,mask,filter,use')) return;
            if (!part.matches('path,rect,circle,ellipse,line,polyline,polygon,text')) continue;
            const p = getComputedStyle(part);
            if (part.matches('rect') && p.fill !== 'none' && alpha(p.fill) > 0) {
              const box = part.getBBox();
              if (box.x <= viewport.x && box.y <= viewport.y && box.width >= viewWidth && box.height >= viewHeight) return;
            }
            for (const colour of [p.fill,p.stroke]) {
              if (colour === 'none' || alpha(colour) === 0) continue;
              const level = neutralPaint(colour);
              if (level === null) return;
              levels.push(level);
            }
          }
          if (!levels.length || Math.max(...levels) - Math.min(...levels) > 20 || paint.filter !== 'none') return;
          element.setAttribute('data-rivo-web-ui-icon', 'svg');
          element.toggleAttribute('data-rivo-web-icon-fill', neutralPaint(paint.fill) !== null);
          element.toggleAttribute('data-rivo-web-icon-stroke', neutralPaint(paint.stroke) !== null);
        } else if (element.matches('img')) {
          if (rasterGraphic(element,paint,rect.width,rect.height,element.currentSrc || element.src,false)) {
            element.setAttribute('data-rivo-web-ui-icon', 'image');
          }
        } else if (!element.querySelector('img,svg,video,canvas') && hiddenIconLabel(element,paint) &&
                   rasterGraphic(element,paint,rect.width,rect.height,singleImage(paint.backgroundImage),true)) {
          element.setAttribute('data-rivo-web-ui-icon', 'image');
        }
        if (element.matches('img,svg') || element.closest(preserved)) return;
        for (const name of ['before','after']) {
          const p = getComputedStyle(element,'::' + name);
          const background = singleImage(p.backgroundImage), content = singleImage(p.content);
          element.toggleAttribute('data-rivo-web-' + name + '-ui-icon',
            !/gradient\(/.test(paint.backgroundImage) && !element.querySelector('img,picture,video,canvas') &&
            rasterGraphic(element,p,parseFloat(p.width),parseFloat(p.height),background || content,!!background));
        }
      }
      function classify(element) {
        if (!(element instanceof Element) || element.matches(skipped)) return;
        const identity = [element.id, element.getAttribute('class') || '', element.getAttribute('data-testid') || ''].join(' ');
        if (/(?:^|[\s_-])(?:swatch|colorchip|colourchip|color-chip|color-swatch|color_swatch|colour-swatch|color-picker|color_picker|map|chart)(?:$|[\s_-])/i.test(identity)) {
          element.setAttribute('data-rivo-web-preserve', '');
        }
        classifyIcon(element);
        if (element.closest(preserved)) return;
        const original = getComputedStyle(element);
        element.toggleAttribute('data-rivo-web-surface', isOpaque(original.backgroundColor));
        // Native WebKit fields change intrinsic size when background-color is authored.
        element.toggleAttribute('data-rivo-web-native-field', original.appearance !== 'none' &&
          element.matches('input:not([type=checkbox]):not([type=radio]):not([type=range]):not([type=button]):not([type=submit]):not([type=reset]),textarea,select'));
        element.toggleAttribute('data-rivo-web-transparent-text', transparentText(original));
        element.toggleAttribute('data-rivo-web-base', isBaseSurface(original.backgroundColor));
        classifyBorders(element, original, 'data-rivo-web-');
        element.toggleAttribute('data-rivo-web-image', /url\(/i.test(original.backgroundImage));
        const decorations = [['::before', 'before'], ['::after', 'after']].map(([pseudo, name]) =>
          [getComputedStyle(element, pseudo), name]);
        // A gradient can supply the colour behind an image stencil (e.g. a logo).
        const overMedia = original.backgroundClip === 'text' || original.webkitBackgroundClip === 'text' || /url\(|image-set\(/i.test(original.backgroundImage + original.maskImage) ||
          decorations.some(([paint]) => /url\(|image-set\(/i.test(paint.backgroundImage + paint.content + paint.maskImage)) ||
          !!element.querySelector('img,picture,video,canvas');
        element.toggleAttribute('data-rivo-web-gradient', decorativeGradient(original.backgroundImage, overMedia));
        element.toggleAttribute('data-rivo-web-mask', /url\(/i.test(original.maskImage || original.webkitMaskImage || ''));
        for (const [decoration, name] of decorations) {
          element.toggleAttribute('data-rivo-web-' + name + '-transparent-text', transparentText(decoration));
          classifyBorders(element, decoration, 'data-rivo-web-' + name + '-');
          element.toggleAttribute('data-rivo-web-' + name + '-image', /url\(/i.test(decoration.backgroundImage + decoration.content));
          element.toggleAttribute('data-rivo-web-' + name + '-mask', /url\(/i.test(decoration.maskImage || decoration.webkitMaskImage || ''));
          element.toggleAttribute('data-rivo-web-' + name + '-surface', isOpaque(decoration.backgroundColor));
          element.toggleAttribute('data-rivo-web-' + name + '-base', isBaseSurface(decoration.backgroundColor));
          element.toggleAttribute('data-rivo-web-' + name + '-gradient', decorativeGradient(decoration.backgroundImage, overMedia));
          const smallMarker = parseFloat(decoration.width) <= 32 && parseFloat(decoration.height) <= 32;
          element.toggleAttribute('data-rivo-web-' + name + '-marker', smallMarker);
        }
      }
      function scan(root) {
        classify(root);
        root.querySelectorAll('*').forEach(classify);
      }
      function scanPending() {
        timer = undefined;
        if (!style || !config.enabled) return;
        // Read authored styles, not our override. Restoring the sheet in the
        // same task avoids a repaint of the original colours between scans.
        style.disabled = true;
        for (const root of pending) if (root.isConnected) scan(root);
        pending.clear();
        style.disabled = false;
      }
      function schedule(root) {
        if (!(root instanceof Element) || root === style || root.matches(skipped)) return;
        if (pending.has(document.documentElement)) return;
        pending.add(root.closest(iconControl) || root);
        if (pending.size > 80) { pending.clear(); pending.add(document.documentElement); }
        if (!timer && config.enabled) timer = setTimeout(scanPending, 80);
      }
      function css() {
        const p = palettes[config.palette];
        const icon = 'html[data-rivo-web-enabled]';
        // Only the isolated graphic is filtered, never the button or its descendants.
        const iconFilter = config.palette === 'light' ? 'brightness(0) invert(0.2)' :
          config.palette === 'contrast' ? 'brightness(0) invert(1) sepia(1) saturate(10000%)' : 'brightness(0) invert(1)';
        const normal = `:not(:where(${preserved},${preserved.split(',').map(s => s + ' *').join(',')}))`;
        const all = `html[data-rivo-web-enabled] *${normal}`;
        const interactive = `html[data-rivo-web-enabled] :is(${controls})${normal}`;
        const borders = ['top','right','bottom','left'].map(side => `
          ${all}[data-rivo-web-border-${side}] { border-${side}-color:${p.edge}!important; }
          ${all}[data-rivo-web-before-border-${side}]::before, ${all}[data-rivo-web-after-border-${side}]::after { border-${side}-color:${p.edge}!important; }
        `).join('');
        return `
          ${borders}
          ${icon} [data-rivo-web-ui-icon="svg"] { color:${p.text}!important; }
          ${icon} [data-rivo-web-icon-fill] { fill:${p.text}!important; }
          ${icon} [data-rivo-web-icon-stroke] { stroke:${p.text}!important; }
          ${icon} [data-rivo-web-ui-icon="image"], ${icon} [data-rivo-web-before-ui-icon]::before, ${icon} [data-rivo-web-after-ui-icon]::after { filter:${iconFilter}!important; }
          html[data-rivo-web-enabled] { background-color:${p.bg}!important; color:${p.text}!important; }
          ${all}:not([data-rivo-web-transparent-text]) { color:${p.text}!important; -webkit-text-fill-color:${p.text}!important; }
          ${all}[data-rivo-web-transparent-text] { color:transparent!important; -webkit-text-fill-color:transparent!important; }
          ${all}[data-rivo-web-before-transparent-text]::before, ${all}[data-rivo-web-after-transparent-text]::after { color:transparent!important; -webkit-text-fill-color:transparent!important; }
          ${all}[data-rivo-web-gradient] { background-image:none!important; }
          ${all}[data-rivo-web-surface]:not(:where([data-rivo-web-native-field])) { background-color:${p.surface}!important; }
          ${all}[data-rivo-web-surface][data-rivo-web-base]:not(:where([data-rivo-web-native-field])) { background-color:${p.bg}!important; }
          ${all}[data-rivo-web-surface][data-rivo-web-native-field] { box-shadow:inset 0 0 0 1000px ${p.surface}!important; }
          ${all}[data-rivo-web-mask][data-rivo-web-mask] { background-color:${p.text}!important; }
          html[data-rivo-web-enabled] body${normal}, html[data-rivo-web-enabled] body[data-rivo-web-surface]${normal} { background-color:${p.bg}!important; }
          ${all}:not([data-rivo-web-before-transparent-text])::before, ${all}:not([data-rivo-web-after-transparent-text])::after { color:${p.text}!important; -webkit-text-fill-color:${p.text}!important; }
          ${all}[data-rivo-web-before-gradient]::before, ${all}[data-rivo-web-after-gradient]::after { background-image:none!important; }
          ${all}[data-rivo-web-before-surface]:not([data-rivo-web-before-image])::before, ${all}[data-rivo-web-after-surface]:not([data-rivo-web-after-image])::after { background-color:${p.surface}!important; }
          ${all}[data-rivo-web-before-surface][data-rivo-web-before-base]:not([data-rivo-web-before-image])::before, ${all}[data-rivo-web-after-surface][data-rivo-web-after-base]:not([data-rivo-web-after-image])::after { background-color:${p.bg}!important; }
          ${all}[data-rivo-web-before-surface][data-rivo-web-before-marker]:not([data-rivo-web-before-image])::before, ${all}[data-rivo-web-after-surface][data-rivo-web-after-marker]:not([data-rivo-web-after-image])::after { background-color:${p.edge}!important; }
          ${all}[data-rivo-web-before-mask]::before, ${all}[data-rivo-web-after-mask]::after { background-color:${p.text}!important; }
          ${interactive} { accent-color:${p.link}!important; }
          html[data-rivo-web-enabled] :is(a[href],[role="link"])${normal}:not([data-rivo-web-transparent-text]), html[data-rivo-web-enabled] :is(a[href],[role="link"]) *${normal}:not([data-rivo-web-transparent-text]) { color:${p.link}!important; -webkit-text-fill-color:${p.link}!important; }
          ${all}::placeholder { color:${p.edge}!important; -webkit-text-fill-color:${p.edge}!important; opacity:1!important; }
          ${all}:focus-visible { outline:3px solid ${p.link}!important; outline-offset:2px!important; }
          ${all}::selection { background:${p.text}!important; color:${p.bg}!important; -webkit-text-fill-color:${p.bg}!important; }
        `;
      }
      function broadcast() {
        document.querySelectorAll('iframe,frame').forEach(frame => {
          try { frame.contentWindow.postMessage({rivoAccessibleWeb: config}, '*'); } catch (_) {}
        });
      }
      function mount() {
        if (!document.documentElement) return;
        if (!style) {
          style = document.createElement('style');
          style.setAttribute('data-rivo-web-stylesheet', '');
        }
        if (!style.isConnected) document.documentElement.appendChild(style);
        style.disabled = true;
        if (config.enabled) scan(document.documentElement);
        style.textContent = css();
        document.documentElement.toggleAttribute('data-rivo-web-enabled', config.enabled);
        style.disabled = !config.enabled;
        pending.clear();
        broadcast();
      }
      function set(next) {
        if (!next || typeof next.enabled !== 'boolean' || !Object.hasOwn(palettes, next.palette)) return;
        config = {enabled:next.enabled, palette:next.palette};
        mount();
      }
      window.__rivoAccessibleWeb = {set};
      // Only presentation enums are passed to child frames; never page contents.
      window.addEventListener('message', event => {
        if (window !== window.top && event.source === window.parent && event.data?.rivoAccessibleWeb) set(event.data.rivoAccessibleWeb);
      });
      const observer = new MutationObserver(records => {
        if (!document.documentElement) return;
        if (!style || !style.isConnected) { mount(); return; }
        for (const record of records) {
          if (record.target === style) continue;
          if (record.type === 'attributes') schedule(record.target);
          else record.addedNodes.forEach(schedule);
        }
      });
      observer.observe(document, {subtree:true, childList:true, attributes:true, attributeFilter:['class','style','role','type','src','srcset','sizes','alt','aria-label','title','id','fill','stroke']});
      document.addEventListener('DOMContentLoaded', mount, {once:true});
      window.addEventListener('pageshow', mount);
      window.addEventListener('resize', () => schedule(document.documentElement));
      document.addEventListener('load', event => {
        if (event.target instanceof HTMLIFrameElement) broadcast();
        else if (event.target instanceof HTMLImageElement) schedule(event.target);
      }, true);
    })();
    """#
}
#endif
