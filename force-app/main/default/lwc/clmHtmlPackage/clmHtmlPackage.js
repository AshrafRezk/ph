export const CLM_PKG_CACHE = 'clm-pkg-v1';
export const CLM_PKG_PREFIX = '/clm-pkg/';

const blobPackages = new Map();

export function normalizeZipPath(path) {
    return String(path || '')
        .replace(/\\/g, '/')
        .replace(/^\.\//, '')
        .replace(/^\/+/, '');
}

export function guessMimeType(path) {
    const lower = String(path || '').toLowerCase();
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
    if (lower.endsWith('.js') || lower.endsWith('.mjs')) return 'application/javascript';
    if (lower.endsWith('.css')) return 'text/css';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.woff2')) return 'font/woff2';
    if (lower.endsWith('.woff')) return 'font/woff';
    if (lower.endsWith('.ttf')) return 'font/ttf';
    if (lower.endsWith('.otf')) return 'font/otf';
    if (lower.endsWith('.json')) return 'application/json';
    return 'application/octet-stream';
}

export function htmlPackageEntryUrl(contentDocumentId, zipPath) {
    const normalized = normalizeZipPath(zipPath);
    if (!contentDocumentId || !normalized) {
        return null;
    }
    const parts = [contentDocumentId, ...normalized.split('/')].map((part) => encodeURIComponent(part));
    return `${CLM_PKG_PREFIX}${parts.join('/')}`;
}

function isNativeShell() {
    try {
        if (typeof window !== 'undefined' && window.Capacitor) {
            return true;
        }
        const host = typeof location !== 'undefined' ? location.hostname : '';
        const port = typeof location !== 'undefined' ? location.port : '';
        const ua = typeof navigator !== 'undefined' ? navigator.userAgent || '' : '';
        return host === 'localhost' && !port && /android/i.test(ua);
    } catch (error) {
        return false;
    }
}

export function canServeClmPackagesViaSw() {
    try {
        if (isNativeShell()) {
            return false;
        }
        return !!(typeof navigator !== 'undefined' && navigator.serviceWorker?.controller);
    } catch (error) {
        return false;
    }
}

export async function isHtmlPackageReady(contentDocumentId, zipPath) {
    if (!contentDocumentId || typeof caches === 'undefined') {
        return blobPackages.has(contentDocumentId);
    }
    if (blobPackages.has(contentDocumentId)) {
        return true;
    }
    try {
        const cache = await caches.open(CLM_PKG_CACHE);
        if (zipPath) {
            const href =
                (typeof location !== 'undefined' ? location.origin : '') +
                htmlPackageEntryUrl(contentDocumentId, zipPath);
            const hit = await cache.match(href, { ignoreSearch: true });
            return !!hit;
        }
        const keys = await cache.keys();
        const needle = `${CLM_PKG_PREFIX}${encodeURIComponent(contentDocumentId)}/`;
        return keys.some((request) => String(request.url || '').includes(needle));
    } catch (error) {
        return blobPackages.has(contentDocumentId);
    }
}

export async function waitForClmPackageSw(timeoutMs = 4000) {
    if (isNativeShell()) {
        return false;
    }
    if (typeof navigator === 'undefined' || !navigator.serviceWorker) {
        return false;
    }
    try {
        const ready = navigator.serviceWorker.ready;
        if (!ready) {
            return !!navigator.serviceWorker.controller;
        }
        await Promise.race([
            ready,
            new Promise((resolve) => {
                window.setTimeout(resolve, timeoutMs);
            })
        ]);
        return !!(navigator.serviceWorker.controller || (await navigator.serviceWorker.getRegistration()));
    } catch (error) {
        return false;
    }
}

function zipDir(path) {
    const parts = normalizeZipPath(path).split('/').filter(Boolean);
    parts.pop();
    return parts.join('/');
}

function safeDecodeUri(value) {
    const text = String(value || '');
    if (!text.includes('%')) {
        return text;
    }
    try {
        return decodeURIComponent(text);
    } catch (error) {
        return text;
    }
}

function resolveZipRef(fromPath, ref) {
    // Hype exports spaces as %20 (Dozova%20Man.hyperesources/...). The zip entry
    // keeps the real space, so decode before joining or the script/image never matches.
    const raw = safeDecodeUri(
        String(ref || '')
            .trim()
            .replace(/\\/g, '/')
            .split('#')[0]
            .split('?')[0]
    );
    if (!raw || /^(https?:|data:|blob:|javascript:|mailto:)/i.test(raw)) {
        return null;
    }
    if (raw.startsWith('/')) {
        return normalizeZipPath(raw);
    }
    const base = zipDir(fromPath).split('/').filter(Boolean);
    for (const part of raw.split('/')) {
        if (!part || part === '.') {
            continue;
        }
        if (part === '..') {
            base.pop();
        } else {
            base.push(part);
        }
    }
    return base.join('/');
}

function lookupPackageUrl(urlByPath, zipPath) {
    if (!zipPath || !urlByPath) {
        return null;
    }
    const direct = urlByPath.get(zipPath);
    if (direct) {
        return direct;
    }
    const decoded = safeDecodeUri(zipPath);
    if (decoded !== zipPath) {
        return urlByPath.get(decoded) || null;
    }
    return null;
}

function decodeText(data) {
    if (typeof data === 'string') {
        return data;
    }
    return new TextDecoder('utf-8').decode(data);
}

function isZipBuffer(buffer) {
    const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer || []);
    return bytes.length >= 4 && bytes[0] === 0x50 && bytes[1] === 0x4b;
}

function pickHtmlEntry(files) {
    const htmlFiles = (files || []).filter((file) => {
        const path = String(file.path || '').toLowerCase();
        return path.endsWith('.html') || path.endsWith('.htm');
    });
    if (!htmlFiles.length) {
        return null;
    }
    const scored = htmlFiles.map((file) => {
        const path = String(file.path || '');
        const lower = path.toLowerCase();
        const text = file.text || decodeText(file.data);
        let score = 0;
        if (/(hype_container|hyperesources|hype_document)/i.test(text)) {
            score += 50;
        }
        if (/(^|\/)index\.html?$/.test(lower)) {
            score += 20;
        }
        if (!path.includes('/')) {
            score += 10;
        }
        return { file, path, text, score };
    });
    scored.sort((a, b) => b.score - a.score);
    return scored[0];
}

function parseHypeScenes(text) {
    const names = [];
    const seen = new Set();
    const pattern = /\{n:"([^"]+)",o:"/g;
    let match = pattern.exec(text || '');
    while (match) {
        const name = match[1];
        if (name && !/^master$/i.test(name) && !seen.has(name)) {
            seen.add(name);
            names.push(name);
        }
        match = pattern.exec(text);
    }
    return names;
}

function parseNativeSize(htmlText, extraTexts) {
    let width = 0;
    let height = 0;
    const viewport = String(htmlText || '').match(
        /<meta[^>]*name=["']viewport["'][^>]*content=["']([^"']+)["']/i
    );
    const content = viewport ? viewport[1] : '';
    const vw = content.match(/width\s*=\s*(\d+)/i);
    const vh = content.match(/height\s*=\s*(\d+)/i);
    if (vw) {
        width = Number(vw[1]);
    }
    if (vh) {
        height = Number(vh[1]);
    }
    const blob = [htmlText, ...(extraTexts || [])].join('\n');
    // Hype scene size. Newer Hype exports put other keys between Y and Z
    // ("Y:1024,L:[],Z:768"), so allow a short gap and skip tiny values.
    const yzPattern = /\bY:(\d+)[^{}]{0,40}?\bZ:(\d+)/g;
    let yz = yzPattern.exec(blob);
    while (yz && (Number(yz[1]) < 200 || Number(yz[2]) < 200)) {
        yz = yzPattern.exec(blob);
    }
    if (yz) {
        width = Number(yz[1]) || width;
        height = Number(yz[2]) || height;
    }
    const pxPair = blob.match(/width\s*:\s*(\d+)px[\s\S]{0,80}height\s*:\s*(\d+)px/i);
    if ((!width || !height) && pxPair) {
        width = width || Number(pxPair[1]);
        height = height || Number(pxPair[2]);
    }
    if (width >= 200 && !height) {
        height = Math.round((width * 9) / 16);
    }
    if (height >= 200 && !width) {
        width = Math.round((height * 16) / 9);
    }
    return {
        width: width >= 200 ? width : 1920,
        height: height >= 200 ? height : 1080
    };
}

export function inspectClmHtmlFiles(files) {
    const list = files || [];
    const html = pickHtmlEntry(list);
    const scriptTexts = list
        .filter((file) => /hype_generated_script|\.js$/i.test(file.path || ''))
        .map((file) => file.text || decodeText(file.data));
    const htmlText = html?.text || (html ? decodeText(html.data) : '');
    const size = parseNativeSize(htmlText, scriptTexts);
    const entryPoint = html?.path || 'index.html';
    const hypeScenes = parseHypeScenes([htmlText, ...scriptTexts].join('\n'));
    if (hypeScenes.length) {
        return {
            width: size.width,
            height: size.height,
            entryPoint,
            scenes: hypeScenes,
            entries: hypeScenes.map(() => entryPoint)
        };
    }
    const multiPage = list
        .filter((file) => /message_name\d+\/index\.html?$/i.test(String(file.path || '')))
        .sort((left, right) => {
            const leftNum = Number((String(left.path).match(/message_name(\d+)/i) || [])[1] || 0);
            const rightNum = Number((String(right.path).match(/message_name(\d+)/i) || [])[1] || 0);
            return leftNum - rightNum;
        });
    if (multiPage.length > 1) {
        return {
            width: size.width,
            height: size.height,
            entryPoint: multiPage[0].path,
            scenes: multiPage.map((file, index) => {
                const num = (String(file.path).match(/message_name(\d+)/i) || [])[1];
                return num ? `Slide ${num}` : `Slide ${index + 1}`;
            }),
            entries: multiPage.map((file) => file.path)
        };
    }
    const swiperCount = (htmlText.match(/swiper-slide/gi) || []).length;
    if (swiperCount > 1) {
        const scenes = Array.from({ length: swiperCount }, (_, index) => `Slide ${index + 1}`);
        return {
            width: size.width,
            height: size.height,
            entryPoint,
            scenes,
            entries: scenes.map(() => entryPoint)
        };
    }
    return {
        width: size.width,
        height: size.height,
        entryPoint,
        scenes: [],
        entries: []
    };
}

export async function inspectClmHtmlBuffer(arrayBuffer, JSZipLib) {
    const bytes = arrayBuffer instanceof Uint8Array ? arrayBuffer : new Uint8Array(arrayBuffer || []);
    if (!isZipBuffer(bytes)) {
        return inspectClmHtmlFiles([
            { path: 'index.html', data: bytes, mime: 'text/html' }
        ]);
    }
    const Zip = JSZipLib || (typeof window !== 'undefined' ? window.JSZip : null);
    if (!Zip) {
        throw new Error('Unable to inspect HTML package without JSZip.');
    }
    const zip = await Zip.loadAsync(bytes);
    const files = [];
    const names = Object.keys(zip.files);
    for (const name of names) {
        const file = zip.files[name];
        if (!file || file.dir) {
            continue;
        }
        const normalized = normalizeZipPath(name);
        if (
            !normalized ||
            normalized.includes('__MACOSX') ||
            normalized.split('/').pop().startsWith('.')
        ) {
            continue;
        }
        const mime = guessMimeType(normalized);
        if (mime !== 'text/html' && mime !== 'application/javascript' && mime !== 'text/css') {
            continue;
        }
        const data = await file.async('uint8array');
        files.push({ path: normalized, data, mime });
    }
    return inspectClmHtmlFiles(files);
}

const packageLayouts = new Map();

export function getHtmlPackageLayout(contentDocumentId) {
    return packageLayouts.get(contentDocumentId) || null;
}

export async function inspectInstalledHtmlPackage(contentDocumentId) {
    if (packageLayouts.has(contentDocumentId)) {
        return packageLayouts.get(contentDocumentId);
    }
    const files = await filesFromCache(contentDocumentId);
    if (!files.length) {
        return null;
    }
    const layout = inspectClmHtmlFiles(files);
    packageLayouts.set(contentDocumentId, layout);
    return layout;
}

function rewriteCssUrls(css, fromPath, urlByPath) {
    return String(css).replace(/url\(\s*(['"]?)([^'")]+)\1\s*\)/gi, (all, quote, value) => {
        const resolved = resolveZipRef(fromPath, value);
        const mapped = lookupPackageUrl(urlByPath, resolved);
        if (!mapped) {
            return all;
        }
        return `url(${quote}${mapped}${quote})`;
    });
}

function rewriteHtmlRefs(html, fromPath, urlByPath) {
    const withAttrs = String(html).replace(
        /\b(src|href|poster)\s*=\s*(["'])([^"']+)\2/gi,
        (all, attr, quote, value) => {
            if (attr.toLowerCase() === 'href' && value.trim().startsWith('#')) {
                return all;
            }
            const resolved = resolveZipRef(fromPath, value);
            const mapped = lookupPackageUrl(urlByPath, resolved);
            if (!mapped) {
                return all;
            }
            return `${attr}=${quote}${mapped}${quote}`;
        }
    );
    return rewriteCssUrls(withAttrs, fromPath, urlByPath);
}

function buildRuntimeShim(urlByPath, basePath) {
    const files = {};
    urlByPath.forEach((url, path) => {
        files[path] = url;
    });
    return `<script data-clm-fs="1">(function(){
window.HYPE_eventListeners=window.HYPE_eventListeners||[];
window.HYPE_eventListeners.push({type:'HypeSceneLoad',callback:function(hypeDocument){
  try{
    var name=hypeDocument&&hypeDocument.currentSceneName&&hypeDocument.currentSceneName();
    if(name&&window.parent&&window.parent!==window){
      window.parent.postMessage({type:'clm-hype-scene',scene:name},'*');
    }
  }catch(e){}
}});
var files=${JSON.stringify(files)};
var base=${JSON.stringify(zipDir(basePath))};
function join(dir, ref){
  ref=String(ref||'').split('#')[0].split('?')[0].replace(/\\\\/g,'/');
  if(!ref||/^(https?:|data:|blob:|javascript:|mailto:)/i.test(ref)) return null;
  var parts=dir?dir.split('/').filter(Boolean):[];
  var bits=ref.replace(/^\\.\\//,'').split('/');
  if(ref.charAt(0)==='/'){parts=[];bits=ref.replace(/^\\/+/,'').split('/');}
  for(var i=0;i<bits.length;i++){
    var p=bits[i];
    if(!p||p==='.') continue;
    if(p==='..') parts.pop();
    else parts.push(p);
  }
  return parts.join('/');
}
function remap(u){
  if(!u) return u;
  var s=String(u);
  if(/^(blob:|data:|javascript:)/i.test(s)) return s;
  if(files[s]) return files[s];
  var key=join(base,s);
  if(key&&files[key]) return files[key];
  try{
    var dec=decodeURIComponent(key||s);
    if(files[dec]) return files[dec];
  }catch(e){}
  var name=(key||s).split('/').pop();
  var match=null, count=0;
  for(var k in files){
    if(k===name||k.slice(-name.length-1)==='/'+name){match=files[k];count++;}
  }
  return count===1?match:s;
}
function patchProto(proto, prop){
  var desc=null, obj=proto;
  while(obj&&!desc){
    desc=Object.getOwnPropertyDescriptor(obj, prop);
    obj=Object.getPrototypeOf(obj);
  }
  if(!desc||!desc.set) return;
  Object.defineProperty(proto, prop, {
    configurable:true,
    enumerable:desc.enumerable,
    get:desc.get,
    set:function(v){desc.set.call(this, remap(v));}
  });
}
function remapCss(value){
  return String(value==null?'':value).replace(/url\\(\\s*(['"]?)([^'")]+)\\1\\s*\\)/gi, function(all, q, u){
    var mapped=remap(u);
    return mapped===u?all:'url('+q+mapped+q+')';
  });
}
try{
  var origSetProperty=CSSStyleDeclaration.prototype.setProperty;
  CSSStyleDeclaration.prototype.setProperty=function(prop, value, priority){
    if(typeof value==='string' && value.indexOf('url(')!==-1) value=remapCss(value);
    return origSetProperty.call(this, prop, value, priority);
  };
  ['background','backgroundImage','cssText'].forEach(function(prop){
    var desc=Object.getOwnPropertyDescriptor(CSSStyleDeclaration.prototype, prop);
    if(!desc||!desc.set) return;
    Object.defineProperty(CSSStyleDeclaration.prototype, prop, {
      configurable:true,
      enumerable:desc.enumerable,
      get:desc.get,
      set:function(v){ desc.set.call(this, typeof v==='string'?remapCss(v):v); }
    });
  });
}catch(e){}
function sweepStyles(root){
  var nodes=[];
  try{ nodes=(root||document).querySelectorAll('[style*="url("]'); }catch(e){ return; }
  for(var i=0;i<nodes.length;i++){
    var raw=nodes[i].getAttribute('style')||'';
    if(raw.indexOf('blob:')!==-1 && raw.indexOf('url("')===-1 && raw.indexOf("url('")===-1) continue;
    var next=remapCss(raw);
    if(next!==raw) nodes[i].setAttribute('style', next);
  }
}
try{
  var styleObs=new MutationObserver(function(){ sweepStyles(document); });
  styleObs.observe(document.documentElement||document,{subtree:true,attributes:true,attributeFilter:['style']});
}catch(e){}
sweepStyles(document);
window.addEventListener('load', function(){ sweepStyles(document); });
setTimeout(function(){ sweepStyles(document); }, 0);
setTimeout(function(){ sweepStyles(document); }, 400);
window.HYPE_eventListeners.push({type:'HypeSceneLoad',callback:function(){ sweepStyles(document); }});
try{
  patchProto(HTMLImageElement.prototype,'src');
  patchProto(HTMLScriptElement.prototype,'src');
  patchProto(HTMLSourceElement.prototype,'src');
  patchProto(HTMLMediaElement.prototype,'src');
  patchProto(HTMLIFrameElement.prototype,'src');
  patchProto(HTMLLinkElement.prototype,'href');
}catch(e){}
try{
  var origSet=Element.prototype.setAttribute;
  Element.prototype.setAttribute=function(name, value){
    var n=String(name||'').toLowerCase();
    if((n==='src'||n==='href'||n==='poster')&&value!=null){
      value=remap(value);
    } else if(n==='style'&&value!=null){
      value=remapCss(value);
    }
    return origSet.call(this, name, value);
  };
}catch(e){}
var origFetch=window.fetch;
if(origFetch){
  window.fetch=function(input, init){
    if(typeof input==='string') input=remap(input);
    else if(input&&input.url) input=new Request(remap(input.url), input);
    return origFetch.call(this, input, init);
  };
}
var origOpen=XMLHttpRequest.prototype.open;
XMLHttpRequest.prototype.open=function(method, url){
  arguments[1]=remap(url);
  return origOpen.apply(this, arguments);
};
})();</script>`;
}

function injectShim(html, shim) {
    if (/data-clm-fs=/.test(html)) {
        return html;
    }
    if (/<head[^>]*>/i.test(html)) {
        return html.replace(/<head[^>]*>/i, (match) => `${match}${shim}`);
    }
    if (/<html[^>]*>/i.test(html)) {
        return html.replace(/<html[^>]*>/i, (match) => `${match}<head>${shim}</head>`);
    }
    return `${shim}${html}`;
}

function revokePackage(pkg) {
    if (!pkg?.urls) {
        return;
    }
    pkg.urls.forEach((url) => {
        try {
            URL.revokeObjectURL(url);
        } catch (error) {
            /* ignore */
        }
    });
}

function materializeBlobPackage(contentDocumentId, files) {
    revokePackage(blobPackages.get(contentDocumentId));
    const urlByPath = new Map();
    const extraUrls = [];

    const binary = files.filter((file) => file.mime !== 'text/html' && file.mime !== 'text/css');
    const cssFiles = files.filter((file) => file.mime === 'text/css');
    const htmlFiles = files.filter((file) => file.mime === 'text/html');

    binary.forEach((file) => {
        const blob = new Blob([file.data], { type: file.mime || 'application/octet-stream' });
        const url = URL.createObjectURL(blob);
        urlByPath.set(file.path, url);
        extraUrls.push(url);
    });

    cssFiles.forEach((file) => {
        const rewritten = rewriteCssUrls(decodeText(file.data), file.path, urlByPath);
        const blob = new Blob([rewritten], { type: 'text/css;charset=utf-8' });
        const url = URL.createObjectURL(blob);
        urlByPath.set(file.path, url);
        extraUrls.push(url);
    });

    htmlFiles.forEach((file) => {
        const shim = buildRuntimeShim(urlByPath, file.path);
        const rewritten = injectShim(rewriteHtmlRefs(decodeText(file.data), file.path, urlByPath), shim);
        const blob = new Blob([rewritten], { type: 'text/html;charset=utf-8' });
        const url = URL.createObjectURL(blob);
        urlByPath.set(file.path, url);
        extraUrls.push(url);
    });

    blobPackages.set(contentDocumentId, { urls: urlByPath, extraUrls });
    return urlByPath;
}

function packagePathFromRequest(request, contentDocumentId) {
    try {
        const url = new URL(request.url);
        const prefix = `${CLM_PKG_PREFIX}${encodeURIComponent(contentDocumentId)}/`;
        let rest = url.pathname;
        const idx = rest.indexOf(prefix);
        if (idx >= 0) {
            rest = rest.slice(idx + prefix.length);
        }
        return rest
            .split('/')
            .filter(Boolean)
            .map((part) => decodeURIComponent(part))
            .join('/');
    } catch (error) {
        return '';
    }
}

async function filesFromCache(contentDocumentId) {
    if (typeof caches === 'undefined') {
        return [];
    }
    const cache = await caches.open(CLM_PKG_CACHE);
    const keys = await cache.keys();
    const needle = `${CLM_PKG_PREFIX}${encodeURIComponent(contentDocumentId)}/`;
    const files = [];
    for (const request of keys) {
        if (!String(request.url || '').includes(needle)) {
            continue;
        }
        const response = await cache.match(request);
        if (!response) {
            continue;
        }
        const path = packagePathFromRequest(request, contentDocumentId);
        if (!path) {
            continue;
        }
        files.push({
            path,
            data: new Uint8Array(await response.arrayBuffer()),
            mime: response.headers.get('Content-Type') || guessMimeType(path)
        });
    }
    return files;
}

async function ensureBlobPackage(contentDocumentId) {
    if (blobPackages.has(contentDocumentId)) {
        return blobPackages.get(contentDocumentId).urls;
    }
    const files = await filesFromCache(contentDocumentId);
    if (!files.length) {
        throw new Error('HTML presentation files are not cached on this device.');
    }
    return materializeBlobPackage(contentDocumentId, files);
}

export async function htmlPackagePlayUrl(contentDocumentId, zipPath) {
    if (!contentDocumentId) {
        throw new Error('HTML entry point is missing on this slide.');
    }
    const layout = getHtmlPackageLayout(contentDocumentId) || (await inspectInstalledHtmlPackage(contentDocumentId));
    const candidates = [zipPath, layout?.entryPoint, 'index.html'].map(normalizeZipPath).filter(Boolean);
    const unique = [...new Set(candidates)];

    const resolveFromMap = (urls) => {
        for (const candidate of unique) {
            const direct = urls.get(candidate);
            if (direct) {
                return direct;
            }
            const lower = candidate.toLowerCase();
            for (const [path, url] of urls.entries()) {
                if (path.toLowerCase() === lower || path.toLowerCase().endsWith(`/${lower}`)) {
                    return url;
                }
            }
        }
        for (const [path, url] of urls.entries()) {
            if (/\.html?$/i.test(path)) {
                return url;
            }
        }
        return null;
    };

    // Always play from blob: URLs. Serving /clm-pkg/* through the service worker
    // breaks on Netlify (SPA fallback returns index.html) and on the APK (SW is
    // unregistered; Capacitor then serves the shell for unknown paths). Sandboxed
    // iframes also skip SW interception for Hype/CSS/JS subresources.
    const urls = await ensureBlobPackage(contentDocumentId);
    const resolved = resolveFromMap(urls);
    if (!resolved) {
        throw new Error('HTML entry point is missing on this slide.');
    }
    return resolved;
}

export async function installHtmlPackage(contentDocumentId, zipBytes, JSZip) {
    if (!contentDocumentId) {
        throw new Error('HTML package is missing a content document.');
    }
    if (!JSZip) {
        throw new Error('HTML unzip library is unavailable.');
    }
    const zip = await JSZip.loadAsync(zipBytes);
    const cache = typeof caches !== 'undefined' ? await caches.open(CLM_PKG_CACHE) : null;
    const origin = typeof location !== 'undefined' ? location.origin : '';
    const names = Object.keys(zip.files).filter((name) => !zip.files[name].dir);
    const installed = [];
    const files = [];

    for (const name of names) {
        const normalized = normalizeZipPath(name);
        if (
            !normalized ||
            normalized.includes('__MACOSX') ||
            normalized.split('/').pop().startsWith('.')
        ) {
            continue;
        }
        const data = await zip.file(name).async('uint8array');
        const mime = guessMimeType(normalized);
        files.push({ path: normalized, data, mime });
        if (cache && origin) {
            const href = origin + htmlPackageEntryUrl(contentDocumentId, normalized);
            await cache.put(
                href,
                new Response(data, {
                    headers: {
                        'Content-Type': mime,
                        'Cache-Control': 'public, max-age=31536000, immutable'
                    }
                })
            );
        }
        installed.push(normalized);
    }

    if (!installed.length) {
        throw new Error('HTML package did not contain any files.');
    }
    packageLayouts.set(contentDocumentId, inspectClmHtmlFiles(files));
    materializeBlobPackage(contentDocumentId, files);
    return installed;
}

export function htmlPackageImageUrls(contentDocumentId) {
    const pack = blobPackages.get(contentDocumentId);
    if (!pack?.urls) {
        return [];
    }
    const images = [];
    for (const [path, url] of pack.urls.entries()) {
        const base = path.split('/').pop().toLowerCase();
        if (
            /\.(png|jpe?g|webp)$/i.test(base) &&
            !/(blank|icon|sprite|logo|cursor|button|btn|menu|close|home|next|prev|pie\.htc)/i.test(base)
        ) {
            images.push({ path, url });
        }
    }
    images.sort((left, right) => left.path.localeCompare(right.path, undefined, { numeric: true }));
    return images.map((image) => image.url);
}

export function fitHtmlPresentation(iframe) {
    const doc = iframe?.contentDocument;
    const win = iframe?.contentWindow;
    if (!doc || !win) {
        return false;
    }
    const styleId = 'clm-fit-style';
    if (!doc.getElementById(styleId)) {
        const style = doc.createElement('style');
        style.id = styleId;
        style.textContent =
            'html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:transparent;}' +
            'body{display:grid;place-items:center;}' +
            'body>*{max-width:100%;max-height:100%;}';
        (doc.head || doc.documentElement).appendChild(style);
    }
    return true;
}

export function bindHypeSceneListener(iframe, onScene) {
    const win = iframe?.contentWindow;
    if (!win || win.__clmHypeBound) {
        return false;
    }
    win.__clmHypeBound = true;
    win.HYPE_eventListeners = win.HYPE_eventListeners || [];
    win.HYPE_eventListeners.push({
        type: 'HypeSceneLoad',
        callback(hypeDocument) {
            fitHtmlPresentation(iframe);
            try {
                const name = hypeDocument?.currentSceneName?.();
                if (name && !/^master$/i.test(name) && typeof onScene === 'function') {
                    onScene(name);
                }
            } catch (error) {
                /* ignore */
            }
        }
    });
    if (!win.__clmFitResize) {
        win.__clmFitResize = () => fitHtmlPresentation(iframe);
        win.addEventListener('resize', win.__clmFitResize);
    }
    return true;
}

export function currentHypeSceneName(iframe) {
    try {
        const docs = iframe?.contentWindow?.HYPE?.documents;
        if (!docs) {
            return null;
        }
        const doc = docs[Object.keys(docs)[0]];
        return typeof doc?.currentSceneName === 'function' ? doc.currentSceneName() : null;
    } catch (error) {
        return null;
    }
}

export function showPackageSlide(iframe, index) {
    try {
        const win = iframe?.contentWindow;
        const doc = win?.document;
        if (!win || !doc) {
            return false;
        }
        const host = doc.querySelector('.swiper');
        const swiper = host?.swiper || win.swiper;
        if (!swiper || typeof swiper.slideTo !== 'function') {
            return false;
        }
        const current = Number.isInteger(swiper.realIndex) ? swiper.realIndex : swiper.activeIndex;
        if (current !== index) {
            swiper.slideTo(index, 0);
        }
        return true;
    } catch (error) {
        return false;
    }
}

export function bindPackageSlideListener(iframe, onIndex) {
    try {
        const win = iframe?.contentWindow;
        const doc = win?.document;
        if (!win || !doc || win.__clmSlideBound || typeof onIndex !== 'function') {
            return false;
        }
        const host = doc.querySelector('.swiper');
        const swiper = host?.swiper || win.swiper;
        if (!swiper || typeof swiper.on !== 'function') {
            return false;
        }
        win.__clmSlideBound = true;
        swiper.on('slideChange', () => {
            const next = Number.isInteger(swiper.realIndex) ? swiper.realIndex : swiper.activeIndex;
            if (Number.isInteger(next)) {
                onIndex(next);
            }
        });
        return true;
    } catch (error) {
        return false;
    }
}

export function showHypeScene(iframe, sceneNameOrNames) {
    const candidates = (Array.isArray(sceneNameOrNames) ? sceneNameOrNames : [sceneNameOrNames])
        .map((name) => String(name || '').trim())
        .filter(Boolean);
    if (!iframe?.contentWindow) {
        return false;
    }
    try {
        fitHtmlPresentation(iframe);
        const docs = iframe.contentWindow.HYPE?.documents;
        if (!docs) {
            return false;
        }
        const doc = docs[Object.keys(docs)[0]];
        if (typeof doc?.showSceneNamed !== 'function') {
            return fitHtmlPresentation(iframe);
        }
        const available = typeof doc.sceneNames === 'function' ? doc.sceneNames() || [] : [];
        const lower = available.map((name) => String(name).toLowerCase());
        let match = null;
        for (const candidate of candidates) {
            const index = lower.indexOf(candidate.toLowerCase());
            if (index >= 0) {
                match = available[index];
                break;
            }
        }
        if (!match) {
            return true;
        }
        const current = typeof doc.currentSceneName === 'function' ? doc.currentSceneName() : '';
        if (current !== match) {
            doc.showSceneNamed(match);
        }
        fitHtmlPresentation(iframe);
        return true;
    } catch (error) {
        return false;
    }
}
