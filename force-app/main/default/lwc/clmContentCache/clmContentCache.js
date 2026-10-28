import getPdfBase64ForPlayer from '@salesforce/apex/ClmPdfViewerController.getPdfBase64ForPlayer';
import getContentChunk from '@salesforce/apex/ClmContentDownloadService.getContentChunk';
import resolveContentDocumentId from '@salesforce/apex/ClmPdfViewerController.resolveContentDocumentId';
import {
    getAsset,
    hashUrl,
    putAsset
} from 'c/clmOfflineStore';
import { installHtmlPackage, isHtmlPackageReady } from 'c/clmHtmlPackage';
import { renderPdfPagesToBlobs, shouldPreferPdfMainThread } from 'c/clmPdfProcessor';

export const APEX_DOWNLOAD_MAX_BYTES = 4500000;

const DIRECT_DOWNLOAD_API_VERSION = 'v62.0';

async function toOwnedUint8Array(value) {
    if (!value) {
        return null;
    }
    if (value instanceof Blob) {
        return new Uint8Array(await value.arrayBuffer());
    }
    if (value instanceof Uint8Array) {
        return value.slice();
    }
    if (value instanceof ArrayBuffer) {
        return new Uint8Array(value.slice(0));
    }
    if (ArrayBuffer.isView(value)) {
        return new Uint8Array(value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength));
    }
    return new Uint8Array(value);
}

function base64ToUint8Array(base64) {
    const raw = window.atob(base64);
    const bytes = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i += 1) {
        bytes[i] = raw.charCodeAt(i);
    }
    return bytes;
}

async function fetchBytesFromUrl(url, credentials = 'same-origin') {
    const response = await fetch(url, { credentials });
    if (!response.ok) {
        throw new Error(`Unable to load asset (HTTP ${response.status}).`);
    }
    return response.arrayBuffer();
}

export function exceedsApexDownloadLimit(contentSize) {
    return contentSize != null && Number(contentSize) > APEX_DOWNLOAD_MAX_BYTES;
}

/**
 * Per-page preview served inline by an <img>. Shepherd download URLs redirect to
 * file.force.com, which has no Access-Control-Allow-Origin, so they cannot be fetch()'d
 * from Lightning. Image loads are not CORS-gated.
 * THUMB720BY480 is only generated for page 0, so every later slide would show slide 1.
 * JPGZ is the per-page JPEG rendition (much smaller than SVGZ for image-heavy decks).
 * operationContext=CHATTER makes Salesforce generate that page instead of ignoring
 * the page index.
 * pageNumber is 1-based. Rendition page index is 0-based.
 */
export function buildPdfPageRenditionUrl(contentVersionId, pageNumber, contentDocumentId) {
    const versionId = String(contentVersionId || '').trim();
    if (!/^068/i.test(versionId)) {
        return null;
    }
    const page = pageNumber != null ? Number(pageNumber) : 1;
    const pageIndex = !page || Number.isNaN(page) || page < 1 ? 0 : page - 1;
    const params = new URLSearchParams({
        rendition: 'JPGZ',
        versionId,
        page: String(pageIndex),
        zoom: '200',
        operationContext: 'CHATTER'
    });
    const documentId = String(contentDocumentId || '').trim();
    if (/^069/i.test(documentId)) {
        params.set('contentId', documentId);
    }
    return `/sfc/servlet.shepherd/version/renditionDownload?${params.toString()}`;
}

export function buildNativeContentUrl(contentDocumentId, publicContentUrl, pageNumber) {
    const base =
        (publicContentUrl && String(publicContentUrl).trim()) ||
        (contentDocumentId
            ? `/sfc/servlet.shepherd/document/download/${encodeURIComponent(contentDocumentId)}`
            : null);
    if (!base) {
        return null;
    }
    const page = pageNumber != null ? Number(pageNumber) : null;
    if (!page || Number.isNaN(page) || page < 1) {
        return base;
    }
    const withoutHash = base.split('#')[0];
    return `${withoutHash}#page=${page}`;
}

/**
 * Streams raw file bytes for decks too large to return through Apex (heap).
 * Uses the standard REST VersionData endpoint, which returns binary and honors
 * an OAuth bearer token (offline PWA / Capacitor). In native Lightning the
 * relative URL is generally unreachable, so callers fall back to an error.
 */
function isLightningUiHost() {
    if (typeof window === 'undefined' || !window.location?.hostname) {
        return false;
    }
    const host = window.location.hostname.toLowerCase();
    return host.includes('lightning.force.com');
}

function clearStaleOfflineAuthOnLightning() {
    if (!isLightningUiHost() || typeof globalThis === 'undefined') {
        return;
    }
    try {
        delete globalThis.PLANNER_ACCESS_TOKEN;
        delete globalThis.PLANNER_REST_BASE;
    } catch (error) {
        globalThis.PLANNER_ACCESS_TOKEN = undefined;
        globalThis.PLANNER_REST_BASE = undefined;
    }
}

function shouldUseRestContentDownload() {
    clearStaleOfflineAuthOnLightning();
    if (typeof globalThis === 'undefined' || !globalThis.PLANNER_ACCESS_TOKEN) {
        return false;
    }
    // Lightning UI sessions cannot stream VersionData via REST; use Apex or Files servlet.
    if (isLightningUiHost()) {
        return false;
    }
    return true;
}

function isSalesforceContentVersionId(id) {
    return /^068/i.test(String(id || '').trim());
}

function isSalesforceContentDocumentId(id) {
    return /^069/i.test(String(id || '').trim());
}

function buildLightningDocumentDownloadUrl(contentDocumentId) {
    const docId = String(contentDocumentId || '').trim();
    if (!docId || !isSalesforceContentDocumentId(docId)) {
        return null;
    }
    const origin =
        typeof window !== 'undefined' && window.location?.origin
            ? window.location.origin
            : '';
    const path = `/sfc/servlet.shepherd/document/download/${encodeURIComponent(docId)}`;
    return origin ? `${origin}${path}` : path;
}

function buildShepherdDownloadUrls(contentDocumentId, contentVersionId) {
    const onLightning = isLightningUiHost();
    const urls = [];
    const docId = String(contentDocumentId || '').trim();
    const versionId = String(contentVersionId || '').trim();

    if (docId && isSalesforceContentDocumentId(docId)) {
        urls.push(
            onLightning
                ? buildLightningDocumentDownloadUrl(docId)
                : `/sfc/servlet.shepherd/document/download/${encodeURIComponent(docId)}`
        );
    }

    // version/download is served from file.force.com — unusable from Lightning fetch (CORS).
    if (onLightning) {
        return urls;
    }

    if (versionId && isSalesforceContentVersionId(versionId)) {
        urls.push(`/sfc/servlet.shepherd/version/download/${encodeURIComponent(versionId)}`);
    }
    if (docId && isSalesforceContentVersionId(docId)) {
        urls.push(`/sfc/servlet.shepherd/version/download/${encodeURIComponent(docId)}`);
    }
    return urls;
}

async function ensureContentDocumentId(contentDocumentId, contentVersionId) {
    const docId = String(contentDocumentId || '').trim();
    if (isSalesforceContentDocumentId(docId)) {
        return docId;
    }
    const versionLookup = isSalesforceContentVersionId(docId)
        ? docId
        : String(contentVersionId || '').trim();
    if (!versionLookup) {
        throw new Error('Presentation file is missing a content document id.');
    }
    const resolved = await resolveContentDocumentId({ salesforceFileId: versionLookup });
    if (!resolved || !isSalesforceContentDocumentId(resolved)) {
        throw new Error('Presentation file not found or not accessible.');
    }
    return String(resolved).trim();
}

function parseSalesforceApiError(bodyText) {
    const trimmed = String(bodyText || '').trim();
    if (!trimmed.startsWith('[') && !trimmed.startsWith('{')) {
        return null;
    }
    try {
        const payload = JSON.parse(trimmed);
        const first = Array.isArray(payload) ? payload[0] : payload;
        return first?.errorCode || first?.message || null;
    } catch (error) {
        return null;
    }
}

async function readDownloadPayload(response) {
    const buffer = await response.arrayBuffer();
    if (!buffer.byteLength) {
        return buffer;
    }
    const preview = new TextDecoder().decode(buffer.slice(0, Math.min(buffer.byteLength, 512)));
    const apiError = parseSalesforceApiError(preview);
    if (apiError === 'INVALID_SESSION_ID') {
        if (isLightningUiHost()) {
            throw new Error(
                'Presentation download failed because the browser called the REST API instead of Files. Hard-refresh CLM Presentations (Cmd+Shift+R) and try again.'
            );
        }
        throw new Error('Your Salesforce session expired. Refresh the page and sign in again.');
    }
    if (apiError) {
        throw new Error(`Unable to download presentation content (${apiError}).`);
    }
    return buffer;
}

function isLikelyCorsFetchFailure(error) {
    const message = String(error?.message || error || '').toLowerCase();
    return (
        error instanceof TypeError ||
        message.includes('cors') ||
        message.includes('failed to fetch') ||
        message.includes('networkerror')
    );
}

function isSalesforceFileUrl(url) {
    const value = String(url || '').toLowerCase();
    return value.includes('/sfc/servlet.shepherd/') || value.includes('file.force.com');
}

const SHEPHERD_RANGE_CHUNK_BYTES = 2 * 1024 * 1024;

function mergeByteParts(parts) {
    const merged = new Uint8Array(parts.reduce((sum, part) => sum + part.byteLength, 0));
    let offset = 0;
    parts.forEach((part) => {
        merged.set(part, offset);
        offset += part.byteLength;
    });
    return merged.buffer;
}

async function downloadViaShepherdRange(url, expectedSize) {
    const parts = [];
    let start = 0;
    let totalBytes = expectedSize != null ? Number(expectedSize) : null;

    while (true) {
        const end = start + SHEPHERD_RANGE_CHUNK_BYTES - 1;
        // eslint-disable-next-line no-await-in-loop
        // Non-Lightning clients only. Lightning must not fetch this URL:
        // shepherd 302s to file.force.com, and that host never sends CORS headers.
        const response = await fetch(url, {
            credentials: 'same-origin',
            redirect: 'follow',
            headers: { Range: `bytes=${start}-${end}` }
        });

        if (response.status === 301 || response.status === 302) {
            throw new Error('Presentation download redirected to Files CDN (CORS blocked).');
        }

        if (response.status === 416) {
            break;
        }

        if (!response.ok && response.status !== 206) {
            throw new Error(`Unable to download presentation content (HTTP ${response.status}).`);
        }

        const contentRange = response.headers.get('Content-Range');
        if (contentRange && totalBytes == null) {
            const match = contentRange.match(/\/(\d+)\s*$/);
            if (match) {
                totalBytes = parseInt(match[1], 10);
            }
        }

        const buffer = await readDownloadPayload(response);
        if (!buffer.byteLength) {
            break;
        }
        parts.push(new Uint8Array(buffer));
        start += buffer.byteLength;

        if (response.status === 200 || buffer.byteLength < SHEPHERD_RANGE_CHUNK_BYTES) {
            break;
        }
        if (totalBytes != null && start >= totalBytes) {
            break;
        }
        if (parts.length > 512) {
            throw new Error('Presentation file exceeded the maximum download size.');
        }
    }

    if (!parts.length) {
        throw new Error('Unable to download presentation content.');
    }
    const merged = mergeByteParts(parts);
    if (totalBytes != null && merged.byteLength !== totalBytes) {
        throw new Error('Presentation download was incomplete. Try again.');
    }
    return merged;
}

async function downloadBytesFromShepherd(contentDocumentId, contentVersionId, expectedSize) {
    if (isLightningUiHost()) {
        const error = new Error(
            'Salesforce Files cannot be read with fetch inside Lightning. The download redirects to file.force.com, which does not allow cross-origin reads.'
        );
        error.code = 'CORS_BLOCKED';
        throw error;
    }
    let resolvedDocumentId = contentDocumentId;
    if (isLightningUiHost()) {
        resolvedDocumentId = await ensureContentDocumentId(contentDocumentId, contentVersionId);
    }
    const urls = buildShepherdDownloadUrls(resolvedDocumentId, contentVersionId);
    if (!urls.length) {
        throw new Error('Presentation file is missing a downloadable content id.');
    }

    let lastError = null;
    for (const url of urls) {
        try {
            if (isLightningUiHost() || exceedsApexDownloadLimit(expectedSize)) {
                return await downloadViaShepherdRange(url, expectedSize);
            }
            const response = await fetch(url, { credentials: 'same-origin', redirect: 'follow' });
            if (response.status === 301 || response.status === 302) {
                return downloadViaShepherdRange(url, expectedSize);
            }
            if (!response.ok) {
                throw new Error(`Unable to download presentation content (HTTP ${response.status}).`);
            }
            return await readDownloadPayload(response);
        } catch (error) {
            lastError = error;
            if (isLikelyCorsFetchFailure(error)) {
                try {
                    return await downloadViaShepherdRange(url, expectedSize);
                } catch (rangeError) {
                    lastError = rangeError;
                }
            }
        }
    }
    throw lastError || new Error('Unable to download presentation content.');
}

const CONTENT_BRIDGE_TIMEOUT_MS = 300000;

function resolveContentBridgeOrigins() {
    if (typeof window === 'undefined' || !window.location?.hostname) {
        return [];
    }
    const host = window.location.hostname.toLowerCase();
    const origins = [];
    if (host.endsWith('.lightning.force.com')) {
        const prefix = host.replace('.lightning.force.com', '');
        origins.push(`https://${prefix}--c.vf.force.com`);
        origins.push(`https://${prefix}.my.salesforce.com`);
    } else if (host.endsWith('.vf.force.com') || host.endsWith('.my.salesforce.com')) {
        origins.push(window.location.origin);
    } else if (window.location.origin) {
        origins.push(window.location.origin);
    }
    return [...new Set(origins.filter(Boolean))];
}

function buildContentBridgeUrl(contentDocumentId, contentVersionId, requestId, origin) {
    const params = new URLSearchParams({
        docId: contentDocumentId || '',
        versionId: contentVersionId || '',
        requestId: requestId || contentDocumentId || `bridge_${Date.now()}`
    });
    const base = origin || resolveContentBridgeOrigins()[0] || window.location.origin;
    return `${base}/apex/ClmContentBridge?${params.toString()}`;
}

async function downloadBytesViaContentBridge(contentDocumentId, contentVersionId) {
    if (typeof document === 'undefined' || typeof window === 'undefined') {
        throw new Error('Content bridge unavailable in this client.');
    }
    const requestId = `bridge_${contentDocumentId}_${Date.now()}`;
    const bridgeOrigins = resolveContentBridgeOrigins();
    if (!bridgeOrigins.length) {
        return Promise.reject(new Error('Content bridge unavailable in this client.'));
    }
    return new Promise((resolve, reject) => {
        const base64Parts = [];
        let iframe = null;
        let timer = null;
        let originIndex = 0;
        let settled = false;

        const cleanup = () => {
            if (timer) {
                window.clearTimeout(timer);
                timer = null;
            }
            window.removeEventListener('message', onMessage);
            if (iframe?.parentNode) {
                iframe.parentNode.removeChild(iframe);
            }
            iframe = null;
        };

        const fail = (error) => {
            if (settled) {
                return;
            }
            settled = true;
            cleanup();
            reject(error);
        };

        const succeed = (buffer) => {
            if (settled) {
                return;
            }
            settled = true;
            cleanup();
            resolve(buffer);
        };

        const loadNextBridgeFrame = () => {
            if (originIndex >= bridgeOrigins.length) {
                fail(new Error('Unable to open CLM content bridge.'));
                return;
            }
            const origin = bridgeOrigins[originIndex];
            originIndex += 1;
            if (iframe?.parentNode) {
                iframe.parentNode.removeChild(iframe);
            }
            iframe = document.createElement('iframe');
            iframe.setAttribute('aria-hidden', 'true');
            iframe.setAttribute('tabindex', '-1');
            iframe.setAttribute('sandbox', 'allow-scripts allow-same-origin');
            iframe.style.cssText =
                'position:fixed;width:0;height:0;border:0;opacity:0;pointer-events:none';
            iframe.src = buildContentBridgeUrl(
                contentDocumentId,
                contentVersionId,
                requestId,
                origin
            );
            iframe.addEventListener('error', () => {
                if (!settled && !base64Parts.length) {
                    loadNextBridgeFrame();
                }
            });
            document.body.appendChild(iframe);
        };

        const onMessage = (event) => {
            const data = event.data;
            if (!data || data.requestId !== requestId) {
                return;
            }
            if (data.type === 'clm-content-chunk-b64' && data.base64) {
                const index = data.index != null ? Number(data.index) : base64Parts.length;
                base64Parts[index] = data.base64;
                return;
            }
            if (data.type === 'clm-content-chunk' && data.bytes) {
                const index = data.index != null ? Number(data.index) : base64Parts.length;
                const bytes =
                    data.bytes instanceof Uint8Array ? data.bytes : new Uint8Array(data.bytes);
                let binary = '';
                bytes.forEach((byte) => {
                    binary += String.fromCharCode(byte);
                });
                base64Parts[index] = window.btoa(binary);
                return;
            }
            if (data.type === 'clm-content-end') {
                try {
                    const ordered = [];
                    for (let i = 0; i < base64Parts.length; i += 1) {
                        if (base64Parts[i]) {
                            ordered.push(base64Parts[i]);
                        }
                    }
                    if (!ordered.length) {
                        throw new Error('Unable to download presentation content.');
                    }
                    const merged = mergeByteParts(ordered.map((part) => base64ToUint8Array(part)));
                    succeed(merged.buffer);
                } catch (error) {
                    fail(error);
                }
                return;
            }
            if (data.type === 'clm-content-error') {
                fail(new Error(data.message || 'Unable to download presentation file.'));
            }
        };

        window.addEventListener('message', onMessage);
        timer = window.setTimeout(() => {
            fail(new Error('Timed out loading presentation file.'));
        }, CONTENT_BRIDGE_TIMEOUT_MS);

        loadNextBridgeFrame();
    });
}

async function downloadBytesViaApexChunks(contentDocumentId, contentSize) {
    const parts = [];
    let offset = 0;
    let totalSize = contentSize != null ? Number(contentSize) : null;

    while (true) {
        // eslint-disable-next-line no-await-in-loop
        const chunk = await getContentChunk({
            contentDocumentId,
            byteOffset: offset
        });
        if (chunk?.totalSize != null) {
            totalSize = Number(chunk.totalSize);
        }
        if (chunk?.base64Data) {
            parts.push(base64ToUint8Array(chunk.base64Data));
        }
        const read = Number(chunk?.bytesRead) || 0;
        offset += read;
        if (chunk?.done || read === 0) {
            break;
        }
        if (totalSize != null && offset >= totalSize) {
            break;
        }
        if (parts.length > 512) {
            throw new Error('Presentation file exceeded the maximum download size.');
        }
    }

    if (!parts.length) {
        throw new Error('Unable to download presentation content.');
    }
    const merged = mergeByteParts(parts);
    if (totalSize != null && merged.byteLength !== totalSize) {
        throw new Error('Presentation download was incomplete. Try again.');
    }
    return merged;
}

async function downloadVersionDataDirect(contentVersionId) {
    if (!contentVersionId) {
        throw new Error('Presentation file is missing a content version.');
    }
    if (!shouldUseRestContentDownload()) {
        throw new Error('REST content download is not available in this client.');
    }
    const token =
        typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN
            ? String(globalThis.PLANNER_ACCESS_TOKEN).trim()
            : '';
    if (!token) {
        throw new Error('OAuth token required for REST content download.');
    }
    const restBase = (typeof globalThis !== 'undefined' && globalThis.PLANNER_REST_BASE) || '';
    const url = `${String(restBase).replace(/\/$/, '')}/services/data/${DIRECT_DOWNLOAD_API_VERSION}/sobjects/ContentVersion/${encodeURIComponent(contentVersionId)}/VersionData`;
    const response = await fetch(url, {
        method: 'GET',
        credentials: 'omit',
        headers: {
            Accept: 'application/octet-stream',
            Authorization: `Bearer ${token}`
        }
    });
    if (!response.ok) {
        throw new Error(`Unable to download presentation content (HTTP ${response.status}).`);
    }
    return response.arrayBuffer();
}

async function downloadBytesFromNetwork(contentDocumentId, contentSize, options = {}) {
    if (!contentDocumentId) {
        throw new Error('Presentation file is missing.');
    }

    const onLightning = isLightningUiHost();
    const isLarge = exceedsApexDownloadLimit(contentSize);
    const canStream = !!options.contentVersionId;
    const useRest = shouldUseRestContentDownload();

    clearStaleOfflineAuthOnLightning();

    // file.force.com does not send Access-Control-Allow-Origin. Range requests still
    // redirect there, so fetch() from Lightning always fails CORS. Stay on Apex.
    if (onLightning) {
        if (isLarge) {
            try {
                return await downloadBytesViaContentBridge(
                    contentDocumentId,
                    options.contentVersionId
                );
            } catch (bridgeError) {
                try {
                    return await downloadBytesViaApexChunks(contentDocumentId, contentSize);
                } catch (chunkError) {
                    throw bridgeError;
                }
            }
        }
        const base64 = await getPdfBase64ForPlayer({ contentDocumentId });
        if (!base64) {
            throw new Error('Unable to download presentation content.');
        }
        return base64ToUint8Array(base64).buffer;
    }

    if (useRest && canStream && (isLarge || contentSize == null)) {
        try {
            return await downloadVersionDataDirect(options.contentVersionId);
        } catch (streamError) {
            if (isLarge) {
                throw streamError;
            }
        }
    }

    try {
        const base64 = await getPdfBase64ForPlayer({ contentDocumentId });
        if (!base64) {
            throw new Error('Unable to download presentation content.');
        }
        return base64ToUint8Array(base64).buffer;
    } catch (apexError) {
        const apexMessage = apexError?.body?.message || apexError?.message || '';
        const isLargeFile =
            apexError?.code === 'LARGE_FILE' || /too large|FILE_TOO_LARGE/i.test(apexMessage);

        if (!onLightning && useRest && canStream) {
            try {
                return await downloadVersionDataDirect(options.contentVersionId);
            } catch (streamError) {
                if (isLargeFile) {
                    throw streamError;
                }
            }
        }

        try {
            return await downloadBytesFromShepherd(
                contentDocumentId,
                options.contentVersionId,
                contentSize
            );
        } catch (shepherdError) {
            if (isLargeFile || onLightning) {
                throw shepherdError;
            }
        }

        const error = new Error(apexMessage || 'Unable to download presentation content.');
        if (isLargeFile) {
            error.code = 'LARGE_FILE';
        }
        throw error;
    }
}

export async function getPdfBytes(contentDocumentId, fetchNetwork = true, options = {}) {
    if (!contentDocumentId) {
        return null;
    }
    const { contentSize } = options;
    const assetKey = `pdf_${contentDocumentId}`;
    const cached = await getAsset(assetKey);
    if (cached?.blob) {
        try {
            const cachedBytes = await toOwnedUint8Array(cached.blob);
            if (cachedBytes?.byteLength) {
                return cachedBytes;
            }
        } catch (cacheError) {
            // Detached or corrupt cache — fall through to network.
        }
    }
    // Note: navigator.onLine is unreliable in Capacitor WebView
    // Always try to fetch - let network failures be handled gracefully
    if (!fetchNetwork) {
        return null;
    }
    const buffer = await downloadBytesFromNetwork(contentDocumentId, contentSize, options);
    const bytes = await toOwnedUint8Array(buffer);
    try {
        await putAsset(assetKey, bytes.slice().buffer, { contentDocumentId, type: 'pdf' });
    } catch (cacheError) {
        // Caching is best-effort; the player can still open the in-memory copy.
    }
    return bytes;
}

export async function downloadContentBytes(contentDocumentId, fetchNetwork = true, options = {}) {
    const bytes = await getPdfBytes(contentDocumentId, fetchNetwork, options);
    if (!bytes) {
        throw new Error('Unable to download presentation content.');
    }
    return bytes.slice().buffer;
}

export function clmPageAssetKey(contentDocumentId, pageNumber) {
    return `clm-page_${contentDocumentId}_${pageNumber}`;
}

export async function getWarmedPageBlob(contentDocumentId, pageNumber) {
    if (!contentDocumentId || pageNumber == null) {
        return null;
    }
    const cached = await getAsset(clmPageAssetKey(contentDocumentId, pageNumber));
    if (!cached?.blob) {
        return null;
    }
    return cached.blob instanceof Blob
        ? cached.blob
        : new Blob([cached.blob], { type: cached.mimeType || 'image/jpeg' });
}

export async function hasWarmedFirstPage(contentDocumentId) {
    const blob = await getWarmedPageBlob(contentDocumentId, 1);
    return !!blob;
}

function firstHtmlEntry(manifestEntry) {
    return (
        manifestEntry?.htmlEntryPoint ||
        manifestEntry?.sequences?.find((sequence) => sequence?.htmlEntryPoint)?.htmlEntryPoint ||
        'index.html'
    );
}

export async function presentationNeedsWarm(manifestEntry) {
    if (!manifestEntry?.contentDocumentId) {
        return false;
    }
    const format = String(manifestEntry.formatType || '').toUpperCase();
    if (format === 'HTML' || format === 'ZIP') {
        const ready = await isHtmlPackageReady(manifestEntry.contentDocumentId, firstHtmlEntry(manifestEntry));
        return !ready;
    }
    if (format === 'PDF') {
        return !(await hasWarmedFirstPage(manifestEntry.contentDocumentId));
    }
    return false;
}

async function loadVendorScript(src) {
    if (typeof document === 'undefined') {
        return;
    }
    const existing = document.querySelector(`script[src="${src}"]`);
    if (existing) {
        if (existing.dataset.loaded === 'true' || existing.getAttribute('data-loaded') === 'true') {
            return;
        }
        await new Promise((resolve, reject) => {
            existing.addEventListener('load', resolve, { once: true });
            existing.addEventListener('error', () => reject(new Error(`Failed to load ${src}`)), {
                once: true
            });
        });
        return;
    }
    await new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = src;
        script.async = true;
        script.onload = () => {
            script.dataset.loaded = 'true';
            resolve();
        };
        script.onerror = () => reject(new Error(`Failed to load ${src}`));
        document.head.appendChild(script);
    });
}

async function ensurePdfJsForWarm() {
    if (window.pdfjsLib) {
        if (window.pdfjsLib.GlobalWorkerOptions && !window.pdfjsLib.GlobalWorkerOptions.workerSrc) {
            window.pdfjsLib.GlobalWorkerOptions.workerSrc = '/vendor/pdfjs/pdf.worker.min.js';
        }
        return window.pdfjsLib;
    }
    await loadVendorScript('/vendor/pdfjs/pdf.min.js');
    if (!window.pdfjsLib) {
        throw new Error('PDF library unavailable for slide warming.');
    }
    window.pdfjsLib.GlobalWorkerOptions.workerSrc = '/vendor/pdfjs/pdf.worker.min.js';
    return window.pdfjsLib;
}

async function ensureJsZipForWarm() {
    if (window.JSZip) {
        return window.JSZip;
    }
    await loadVendorScript('/vendor/jszip/jszip.min.js');
    if (!window.JSZip) {
        throw new Error('Unzip library unavailable for HTML warming.');
    }
    return window.JSZip;
}

let warmLock = Promise.resolve();

function withWarmLock(run) {
    const next = warmLock.then(run, run);
    warmLock = next.catch(() => undefined);
    return next;
}

async function warmPdfPages(contentDocumentId, bytes) {
    if (!contentDocumentId || !bytes) {
        return;
    }
    if (await hasWarmedFirstPage(contentDocumentId)) {
        return;
    }
    const pdfjsLib = await ensurePdfJsForWarm();
    const pages = await renderPdfPagesToBlobs(pdfjsLib, bytes, {
        preferMainThread: shouldPreferPdfMainThread(),
        maxWidth: 1600,
        quality: 0.82
    });
    for (const page of pages) {
        if (!page?.blob) {
            continue;
        }
        await putAsset(clmPageAssetKey(contentDocumentId, page.pageNumber), page.blob, {
            contentDocumentId,
            type: 'clm-page',
            mimeType: 'image/jpeg',
            pageNumber: page.pageNumber
        });
    }
}

async function warmHtmlPackage(contentDocumentId, bytes, zipPath) {
    if (!contentDocumentId || !bytes) {
        return;
    }
    if (await isHtmlPackageReady(contentDocumentId, zipPath)) {
        return;
    }
    const JSZipLib = await ensureJsZipForWarm();
    await installHtmlPackage(contentDocumentId, bytes, JSZipLib);
}

export async function getSlideBlob(url, fetchNetwork = true) {
    if (!url) {
        return null;
    }
    const assetKey = hashUrl(url);
    const cached = await getAsset(assetKey);
    if (cached?.blob) {
        return cached.blob instanceof Blob ? cached.blob : new Blob([cached.blob]);
    }
    // Note: navigator.onLine is unreliable in Capacitor WebView
    // Always try to fetch - let network failures be handled gracefully
    if (!fetchNetwork) {
        return null;
    }
    // Shepherd and file.force.com URLs redirect off Lightning and fail CORS when fetched.
    // Callers should use the URL as an <img> src instead.
    if (isLightningUiHost() && isSalesforceFileUrl(url)) {
        return null;
    }
    try {
        const buffer = await fetchBytesFromUrl(url);
        const blob = new Blob([buffer]);
        await putAsset(assetKey, blob, { url, type: 'slide' });
        return blob;
    } catch (error) {
        return null;
    }
}

export async function prefetchPresentationAssets(manifestEntry, onProgress) {
    if (!manifestEntry) {
        return;
    }
    const tasks = [];
    const format = String(manifestEntry.formatType || '').toUpperCase();
    const isPackage = format === 'PDF' || format === 'HTML' || format === 'ZIP';
    const skipLightningByteDownload =
        isLightningUiHost() && exceedsApexDownloadLimit(manifestEntry.contentSize);
    if (manifestEntry.contentDocumentId && isPackage && !skipLightningByteDownload) {
        tasks.push({
            label: manifestEntry.name,
            run: async () => {
                const bytes = await getPdfBytes(manifestEntry.contentDocumentId, true, {
                    contentSize: manifestEntry.contentSize,
                    contentVersionId: manifestEntry.contentVersionId
                });
                await withWarmLock(async () => {
                    if (format === 'PDF') {
                        await warmPdfPages(manifestEntry.contentDocumentId, bytes);
                    } else {
                        await warmHtmlPackage(
                            manifestEntry.contentDocumentId,
                            bytes,
                            firstHtmlEntry(manifestEntry)
                        );
                    }
                });
            }
        });
    }
    (manifestEntry.sequences || []).forEach((sequence) => {
        const url = sequence.slideImageUrl || sequence.thumbnailUrl;
        if (url) {
            tasks.push({
                label: sequence.sequenceName || url,
                run: () => getSlideBlob(url, true)
            });
        }
    });

    let completed = 0;
    for (const task of tasks) {
        try {
            await task.run();
        } catch (error) {
            // Continue prefetching remaining assets.
            // eslint-disable-next-line no-console
            console.warn('CLM prefetch failed', task.label, error);
        }
        completed += 1;
        if (onProgress) {
            onProgress({ completed, total: tasks.length, presentationName: manifestEntry.name });
        }
    }
}

export function createObjectUrl(blob) {
    if (!blob) {
        return null;
    }
    return URL.createObjectURL(blob instanceof Blob ? blob : new Blob([blob]));
}