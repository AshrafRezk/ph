const PDF_LOAD_TIMEOUT_MS = 90000;
const PDF_PAGE_TIMEOUT_MS = 60000;

export function withTimeout(promise, timeoutMs, message) {
    return new Promise((resolve, reject) => {
        const timer = window.setTimeout(() => {
            reject(new Error(message));
        }, timeoutMs);
        Promise.resolve(promise)
            .then((value) => {
                window.clearTimeout(timer);
                resolve(value);
            })
            .catch((error) => {
                window.clearTimeout(timer);
                reject(error);
            });
    });
}

export function countPdfPagesFromBuffer(arrayBuffer) {
    try {
        const text = new TextDecoder('latin1').decode(new Uint8Array(arrayBuffer));
        const pageMatches = text.match(/\/Type\s*\/Page(?!s)/g);
        if (pageMatches && pageMatches.length > 0) {
            return pageMatches.length;
        }
        let maxCount = 0;
        const countMatches = text.matchAll(/\/Count\s+(\d+)/g);
        for (const match of countMatches) {
            const value = Number(match[1]);
            if (value > maxCount) {
                maxCount = value;
            }
        }
        return maxCount > 0 ? maxCount : 1;
    } catch (e) {
        return 1;
    }
}

export function readFileAsBase64(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => {
            const result = reader.result || '';
            resolve(String(result).split(',')[1] || '');
        };
        reader.onerror = () => reject(reader.error);
        reader.readAsDataURL(file);
    });
}

export function shouldPreferPdfMainThread() {
    try {
        if (typeof window === 'undefined') {
            return false;
        }
        if (window.Capacitor) {
            return true;
        }
        const ua = navigator.userAgent || '';
        if (/iPad|iPhone|Android/i.test(ua)) {
            return true;
        }
        if (navigator.platform === 'MacIntel' && (navigator.maxTouchPoints || 0) > 1) {
            return true;
        }
        if (window.matchMedia && window.matchMedia('(pointer: coarse)').matches) {
            return true;
        }
    } catch (error) {
        return false;
    }
    return false;
}

export function fitPdfPageToCanvas(page, canvas) {
    const container = canvas?.parentElement;
    const cssWidth = Math.max(container?.clientWidth || window.innerWidth || 1024, 280);
    const cssHeight = Math.max(container?.clientHeight || window.innerHeight || 768, 200);
    const unscaled = page.getViewport({ scale: 1 });
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    let scale = Math.min(cssWidth / unscaled.width, cssHeight / unscaled.height);
    if (!Number.isFinite(scale) || scale <= 0) {
        scale = 1;
    }
    scale *= dpr;
    const maxPixels = 16 * 1024 * 1024;
    const pixels = unscaled.width * scale * unscaled.height * scale;
    if (pixels > maxPixels) {
        scale = Math.sqrt(maxPixels / (unscaled.width * unscaled.height));
    }
    const viewport = page.getViewport({ scale });
    canvas.width = Math.floor(viewport.width);
    canvas.height = Math.floor(viewport.height);
    canvas.style.width = `${Math.floor(viewport.width / dpr)}px`;
    canvas.style.height = `${Math.floor(viewport.height / dpr)}px`;
    return viewport;
}

export async function openPdfDocument(pdfjsLib, bytes, options = {}) {
    const timeoutMs = options.timeoutMs || PDF_LOAD_TIMEOUT_MS;
    const timeoutMessage = options.timeoutMessage || 'Timed out loading PDF.';
    const preferMainThread = options.preferMainThread === true;

    const loadWithWorker = () =>
        withTimeout(pdfjsLib.getDocument({ data: bytes }).promise, timeoutMs, timeoutMessage);

    const loadOnMainThread = () =>
        withTimeout(
            pdfjsLib.getDocument({ data: bytes, disableWorker: true }).promise,
            timeoutMs,
            `${timeoutMessage} (main thread).`
        );

    if (preferMainThread) {
        try {
            return await loadOnMainThread();
        } catch (mainThreadError) {
            return loadWithWorker();
        }
    }

    try {
        return await loadWithWorker();
    } catch (workerError) {
        return loadOnMainThread();
    }
}

export async function renderPdfSlideImages(pdfjsLib, arrayBuffer, pageCount, options = {}) {
    if (!pdfjsLib?.getDocument) {
        throw new Error('PDF library is not available.');
    }

    const bytes = arrayBuffer instanceof Uint8Array ? arrayBuffer : new Uint8Array(arrayBuffer);
    const onProgress = typeof options.onProgress === 'function' ? options.onProgress : null;
    const pdf = await openPdfDocument(pdfjsLib, bytes, {
        timeoutMessage: 'Timed out loading PDF for preview.'
    });
    const images = [];
    const total = Math.min(pageCount || pdf.numPages, pdf.numPages);

    for (let pageNum = 1; pageNum <= total; pageNum += 1) {
        if (onProgress) {
            onProgress(pageNum, total);
        }

        let renderTask = null;
        try {
            const page = await withTimeout(
                pdf.getPage(pageNum),
                PDF_PAGE_TIMEOUT_MS,
                `Timed out loading page ${pageNum}.`
            );
            const viewport = page.getViewport({ scale: 1.5 });
            const canvas = document.createElement('canvas');
            canvas.width = viewport.width;
            canvas.height = viewport.height;
            const context = canvas.getContext('2d');
            renderTask = page.render({ canvasContext: context, viewport });
            await withTimeout(
                renderTask.promise,
                PDF_PAGE_TIMEOUT_MS,
                `Timed out rendering page ${pageNum}.`
            );
            const base64Png = canvas.toDataURL('image/png').split(',')[1];
            images.push({
                pageNumber: pageNum,
                base64Png,
                fileName: `slide-${pageNum}.png`
            });
        } catch (pageError) {
            if (renderTask?.cancel) {
                try {
                    renderTask.cancel();
                } catch (cancelError) {
                    // Ignore cancellation errors for failed pages.
                }
            }
        } finally {
            renderTask = null;
        }
    }

    return images;
}

/**
 * Renders every PDF page to a JPEG blob for instant PWA playback.
 * Used during Field Home prefetch so the player can paint from IndexedDB
 * instead of running PDF.js when a rep opens the deck.
 */
export async function renderPdfPagesToBlobs(pdfjsLib, arrayBuffer, options = {}) {
    if (!pdfjsLib?.getDocument) {
        throw new Error('PDF library is not available.');
    }

    const bytes = arrayBuffer instanceof Uint8Array ? arrayBuffer : new Uint8Array(arrayBuffer);
    const onProgress = typeof options.onProgress === 'function' ? options.onProgress : null;
    const maxWidth = Number(options.maxWidth) > 0 ? Number(options.maxWidth) : 1600;
    const quality = Number(options.quality) > 0 ? Number(options.quality) : 0.82;
    const preferMainThread =
        options.preferMainThread === true ||
        (options.preferMainThread !== false && shouldPreferPdfMainThread());

    const pdf = await openPdfDocument(pdfjsLib, bytes, {
        timeoutMessage: 'Timed out warming PDF pages.',
        preferMainThread
    });
    const blobs = [];
    const total = pdf.numPages;
    const onlyPages = Array.isArray(options.pageNumbers)
        ? new Set(options.pageNumbers.map((page) => Number(page)))
        : null;

    for (let pageNum = 1; pageNum <= total; pageNum += 1) {
        if (onlyPages && !onlyPages.has(pageNum)) {
            continue;
        }
        if (onProgress) {
            onProgress(pageNum, total);
        }

        let renderTask = null;
        try {
            const page = await withTimeout(
                pdf.getPage(pageNum),
                PDF_PAGE_TIMEOUT_MS,
                `Timed out loading page ${pageNum}.`
            );
            const unscaled = page.getViewport({ scale: 1 });
            let scale = maxWidth / unscaled.width;
            if (!Number.isFinite(scale) || scale <= 0) {
                scale = 1;
            }
            const maxPixels = 8 * 1024 * 1024;
            const pixels = unscaled.width * scale * unscaled.height * scale;
            if (pixels > maxPixels) {
                scale = Math.sqrt(maxPixels / (unscaled.width * unscaled.height));
            }
            const viewport = page.getViewport({ scale });
            const canvas = document.createElement('canvas');
            canvas.width = Math.floor(viewport.width);
            canvas.height = Math.floor(viewport.height);
            const context = canvas.getContext('2d', { alpha: false });
            renderTask = page.render({ canvasContext: context, viewport });
            await withTimeout(
                renderTask.promise,
                PDF_PAGE_TIMEOUT_MS,
                `Timed out rendering page ${pageNum}.`
            );
            const blob = await new Promise((resolve) => {
                canvas.toBlob((next) => resolve(next), 'image/jpeg', quality);
            });
            if (blob) {
                blobs.push({
                    pageNumber: pageNum,
                    blob,
                    width: canvas.width,
                    height: canvas.height
                });
            }
            canvas.width = 0;
            canvas.height = 0;
        } catch (pageError) {
            if (renderTask?.cancel) {
                try {
                    renderTask.cancel();
                } catch (cancelError) {
                    // Ignore cancellation errors for failed pages.
                }
            }
        } finally {
            renderTask = null;
        }
    }

    return blobs;
}