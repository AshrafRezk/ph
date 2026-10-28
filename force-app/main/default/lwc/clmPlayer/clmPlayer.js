import { LightningElement, api, track } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import PDFJS from '@salesforce/resourceUrl/pdfjs';
import JSZIP from '@salesforce/resourceUrl/jszip';
import {
    fitPdfPageToCanvas,
    openPdfDocument,
    shouldPreferPdfMainThread,
    withTimeout
} from 'c/clmPdfProcessor';
import {
    getPdfBytes,
    getSlideBlob,
    createObjectUrl,
    downloadContentBytes,
    getWarmedPageBlob,
    buildNativeContentUrl,
    buildPdfPageRenditionUrl,
    APEX_DOWNLOAD_MAX_BYTES
} from 'c/clmContentCache';
import {
    getHtmlPackageLayout,
    htmlPackagePlayUrl,
    inspectInstalledHtmlPackage,
    installHtmlPackage,
    isHtmlPackageReady,
    showHypeScene,
    waitForClmPackageSw
} from 'c/clmHtmlPackage';
import { getAllManifestEntries, getManifestEntry, putLocalSession } from 'c/clmOfflineStore';
import { isOfflineMode, queueOfflineAction } from 'c/clmOfflineSync';
import getPdfBase64ForPlayer from '@salesforce/apex/ClmPdfViewerController.getPdfBase64ForPlayer';
import startSession from '@salesforce/apex/ClmMetricsController.startSession';
import startAdHocPresentation from '@salesforce/apex/ClmMetricsController.startAdHocPresentation';
import logSlideEvent from '@salesforce/apex/ClmMetricsController.logSlideEvent';
import completeSession from '@salesforce/apex/ClmMetricsController.completeSession';
import cancelSession from '@salesforce/apex/ClmMetricsController.cancelSession';
import saveMessageResponses from '@salesforce/apex/ClmMetricsController.saveMessageResponses';
import getSessionMessageResponses from '@salesforce/apex/ClmMetricsController.getSessionMessageResponses';

const PDF_LOAD_TIMEOUT_MS = 90000;
const PDF_RENDER_TIMEOUT_MS = 60000;
const PDF_INIT_TIMEOUT_MS = 30000;
const SLIDE_IMAGE_LOAD_TIMEOUT_MS = 15000;
const RENDITION_IMAGE_LOAD_TIMEOUT_MS = 60000;
const PDF_CANVAS_MAX_RETRIES = 30;
// Decks over the Apex heap ceiling can't be byte-fetched in Lightning.
// Shepherd redirects to file.force.com, which never returns CORS headers, so
// fetch() is blocked. Those decks render from the per-page rendition <img>
// instead (image loads are not CORS-gated).
// document/download iframes are disabled: that URL sends
// Content-Disposition: attachment and triggers a file download.
const LIGHTNING_LARGE_PDF_IFRAME = false;
const STAGE_PREFS_KEY = 'zeta.pwa.clm.stage';
const ASPECT_CYCLE = ['16/9', '4/3', '16/10', 'auto'];
const ASPECT_LABELS = { '16/9': '16:9', '4/3': '4:3', '16/10': '16:10', auto: 'Auto' };
const ASPECT_CSS = { '16/9': '16 / 9', '4/3': '4 / 3', '16/10': '16 / 10' };
const ASPECT_RATIO = { '16/9': 16 / 9, '4/3': 4 / 3, '16/10': 16 / 10 };
const STAGE_BOX_MAX_WIDTH = 1152;
const STAGE_RESIZE_DEBOUNCE_MS = 150;
const SENTIMENTS = [
    { emoji: '😊', label: 'Happy', value: 'Positive' },
    { emoji: '😐', label: 'Neutral', value: 'Neutral' },
    { emoji: '☹️', label: 'Sad', value: 'Negative' }
];

function createClientSessionKey() {
    if (window.crypto?.randomUUID) {
        return window.crypto.randomUUID();
    }
    return `clm_${Date.now()}_${Math.random().toString(36).slice(2)}`;
}

export default class ClmPlayer extends LightningElement {
    @api visitId;
    @api presentationId;
    @api presentationName;
    @api adHoc = false;

    @track session;
    @track currentIndex = 0;
    @track isSessionLoading = true;
    @track slideImageReady = false;
    @track slideImageLoadFailed = false;
    @track trackingPaused = false;
    @track dwellAccumulator = 0;
    @track pdfLoadError;
    @track pdfLoadingStatus;
    @track htmlFrameUrl;
    @track htmlLoadError;
    @track htmlLoadingStatus;
    @track htmlSlideReady = false;
    @track pdfNativeFrameReady = false;
    @track pdfNativeFallback = false;
    @track showMessageOverlay = false;
    @track overlayMessages = [];
    @track isSavingMessageResponse = false;
    @track resolvedSlideUrl;
    @track isOfflineSession = false;
    @track chromeCollapsed = false;
    @track trayTab = 'pages';
    @track ratingsOn = false;
    @track personalizedOn = true;
    @track filterMandatory = false;
    @track aspectPreset = '16/9';
    @track fitMode = 'contain';
    @track stageZoom = 1;
    @track libraryItems = [];
    @track pagePreviewUrls = {};
    // Content box of .stage-viewport, kept current by a ResizeObserver.
    @track stageAvail = null;

    // Authored size of the HTML deck. The iframe renders at this size and is
    // scaled down to fit, because the decks use fixed-pixel layouts.
    htmlNativeSize = null;
    stageResizeObserver;
    stageResizeTimerId;

    _activePresentationId;
    paintedFromCache = false;
    slideObjectUrls = new Set();
    previewObjectUrls = new Set();

    timerId;
    slideImageLoadTimerId;
    visibilityHandler;
    preloadedUrls = new Set();
    pdfCanvasRetryCount = 0;
    pdfUsingRendition = false;
    pdfSlideReady = false;
    pdfJsReady = false;
    pdfDoc = null;
    pdfLoading = false;
    pdfRenderTask = null;
    pdfLoadScheduled = false;
    htmlPackageReady = false;
    htmlPackageLoading = false;
    jsZipReady = false;
    hypeSceneTimerId;
    pendingNavigation = null;
    messageResponses = [];
    capturedMessageNames = new Set();
    clientSessionKey;
    // Bumped on every presentation switch so late async work from the previous
    // deck cannot overwrite loading/error state of the new one.
    _loadToken = 0;

    connectedCallback() {
        this._activePresentationId = this.presentationId;
        this.loadStagePrefs();
        this.visibilityHandler = () => {
            if (document.hidden) {
                this.pauseTracking();
            }
        };
        document.addEventListener('visibilitychange', this.visibilityHandler);
        this.bootstrapSession();
        this.loadLibraryCards();
    }

    disconnectedCallback() {
        this.clearTimer();
        this.clearSlideImageLoadTimer();
        this.cancelPdfRender();
        this.clearHypeSceneTimer();
        this.revokeObjectUrls();
        document.removeEventListener('visibilitychange', this.visibilityHandler);
        if (this.stageResizeObserver) {
            this.stageResizeObserver.disconnect();
            this.stageResizeObserver = null;
        }
        window.clearTimeout(this.stageResizeTimerId);
    }

    renderedCallback() {
        if (this.showPdfViewer && !this.pdfLoadError) {
            this.schedulePdfWork();
        }
        if (this.needsHtmlRendering && !this.htmlFrameUrl && !this.htmlLoadError) {
            this.scheduleHtmlWork();
        }
        this.bindHtmlFrame();
        this.observeStageViewport();
        const layoutKey = `${this.aspectPreset}|${this.fitMode}|${this.stageZoom}|${this.chromeCollapsed}`;
        if (this.showPdfViewer && this.pdfDoc && this._lastStageLayout && layoutKey !== this._lastStageLayout) {
            this.pdfSlideReady = false;
            this.schedulePdfWork();
        }
        this._lastStageLayout = layoutKey;
    }

    async bootstrapSession() {
        const loadToken = this._loadToken;
        this.isSessionLoading = true;
        this.paintedFromCache = false;
        this.pdfLoadError = null;
        this.htmlLoadError = null;
        const isStale = () => loadToken !== this._loadToken;
        try {
            const cachedManifest = await getManifestEntry(this.activePresentationId);
            if (isStale()) {
                return;
            }
            if (cachedManifest?.contentDocumentId) {
                await this.paintFromManifest(cachedManifest);
                if (isStale()) {
                    return;
                }
            }

            if (this.adHoc) {
                if (isOfflineMode()) {
                    if (!this.session) {
                        this.session = await this.bootstrapOfflineAdHocSession();
                    } else {
                        await this.persistOfflineStart(this.session);
                    }
                    this.isOfflineSession = true;
                } else {
                    try {
                        const serverSession = await startAdHocPresentation({
                            presentationId: this.activePresentationId
                        });
                        if (isStale()) {
                            return;
                        }
                        this.visitId = serverSession.visitId;
                        this.bindServerSession(serverSession);
                    } catch (error) {
                        if (!this.session) {
                            this.session = await this.bootstrapOfflineAdHocSession();
                        } else {
                            await this.persistOfflineStart(this.session);
                        }
                        this.isOfflineSession = true;
                    }
                }
            } else if (isOfflineMode()) {
                if (!this.session) {
                    this.session = await this.bootstrapOfflineSession();
                } else {
                    await this.persistOfflineStart(this.session);
                }
                this.isOfflineSession = true;
            } else {
                try {
                    const serverSession = await startSession({
                        visitId: this.visitId,
                        presentationId: this.activePresentationId
                    });
                    if (isStale()) {
                        return;
                    }
                    this.bindServerSession(serverSession);
                } catch (error) {
                    if (!this.session) {
                        this.session = await this.bootstrapOfflineSession();
                    } else {
                        await this.persistOfflineStart(this.session);
                    }
                    this.isOfflineSession = true;
                }
            }
            if (isStale()) {
                return;
            }
            if (!this.paintedFromCache) {
                this.currentIndex = 0;
                await this.mergeManifestContentHints();
                await this.loadExistingMessageResponses();
                await this.resetSlideReadyState();
                if (isStale()) {
                    return;
                }
                this.preloadAdjacentSlides();
                this.resumeTracking();
            } else {
                await this.mergeManifestContentHints();
                await this.loadExistingMessageResponses();
                await this.hydratePagePreviews();
            }
        } catch (error) {
            if (isStale()) {
                return;
            }
            this.showToast('Unable to start presentation', this.reduceError(error), 'error');
            this.dispatchClose();
        } finally {
            // A newer switchPresentation owns loading state once the token moves.
            if (!isStale()) {
                this.isSessionLoading = false;
                if (this.needsPdfRendering && !this.currentSlideUrl) {
                    this.pdfSlideReady = false;
                    this.schedulePdfWork();
                }
                if (this.needsHtmlRendering) {
                    this.scheduleHtmlWork();
                }
            }
        }
    }

    get activePresentationId() {
        return this._activePresentationId || this.presentationId;
    }

    sessionFromManifest(manifest) {
        if (!this.clientSessionKey) {
            this.clientSessionKey = createClientSessionKey();
        }
        return {
            id: this.clientSessionKey,
            clientSessionKey: this.clientSessionKey,
            visitId: this.visitId,
            presentationId: manifest.presentationId || manifest.id,
            presentationName: manifest.name || this.presentationName,
            formatType: manifest.formatType,
            contentDocumentId: manifest.contentDocumentId,
            contentVersionId: manifest.contentVersionId,
            contentSize: manifest.contentSize,
            htmlEntryPoint:
                manifest.htmlEntryPoint ||
                (manifest.sequences || []).find((seq) => seq.htmlEntryPoint)?.htmlEntryPoint,
            status: 'Active',
            productName: manifest.productName,
            productImageUrl: manifest.imageUrl,
            slideCount: manifest.slideCount,
            sequences: manifest.sequences || [],
            trackingPaused: false
        };
    }

    async paintFromManifest(manifest) {
        this.session = this.sessionFromManifest(manifest);
        this.presentationName = this.session.presentationName || this.presentationName;
        this.currentIndex = 0;
        await this.hydrateCachedSlideFast();
        await this.hydratePagePreviews();
        if (this.currentSlideUrl || this.htmlPackageReady) {
            this.paintedFromCache = true;
            this.isSessionLoading = false;
            this.slideImageReady = !!this.currentSlideUrl;
            this.resumeTracking();
        }
        if (this.needsHtmlRendering) {
            await this.resolveCurrentHtmlFrame();
        }
    }

    bindServerSession(serverSession) {
        const index = this.currentIndex;
        const previous = this.session || {};
        this.session = {
            ...serverSession,
            contentVersionId: serverSession.contentVersionId || previous.contentVersionId,
            contentSize: serverSession.contentSize || previous.contentSize,
            contentDocumentId: serverSession.contentDocumentId || previous.contentDocumentId,
            formatType: serverSession.formatType || previous.formatType,
            htmlEntryPoint: serverSession.htmlEntryPoint || previous.htmlEntryPoint,
            sequences:
                serverSession.sequences && serverSession.sequences.length
                    ? serverSession.sequences
                    : previous.sequences || []
        };
        this.currentIndex = index;
        this.isOfflineSession = false;
        this.presentationName = this.session.presentationName || this.presentationName;
    }

    async persistOfflineStart(session) {
        await putLocalSession({
            clientSessionKey: this.clientSessionKey,
            visitId: this.visitId,
            presentationId: session.presentationId,
            session,
            messageResponses: []
        });
        await queueOfflineAction({
            actionType: 'START_SESSION',
            clientSessionKey: this.clientSessionKey,
            visitId: this.visitId,
            presentationId: session.presentationId,
            startedAtIso: new Date().toISOString()
        });
    }

    loadStagePrefs() {
        try {
            const raw = window.localStorage?.getItem(STAGE_PREFS_KEY);
            if (!raw) {
                return;
            }
            const prefs = JSON.parse(raw);
            if (ASPECT_CYCLE.includes(prefs.aspect)) {
                this.aspectPreset = prefs.aspect;
            }
            if (prefs.fit === 'cover' || prefs.fit === 'contain') {
                this.fitMode = prefs.fit;
            }
            const zoom = Number(prefs.zoom);
            if (Number.isFinite(zoom) && zoom >= 0.5 && zoom <= 2) {
                this.stageZoom = zoom;
            }
            this.personalizedOn = prefs.personalized !== false;
            this.ratingsOn = prefs.ratingsOn === true;
        } catch (error) {
            /* keep defaults */
        }
    }

    persistStagePrefs() {
        try {
            window.localStorage?.setItem(
                STAGE_PREFS_KEY,
                JSON.stringify({
                    aspect: this.aspectPreset,
                    fit: this.fitMode,
                    zoom: this.stageZoom,
                    personalized: this.personalizedOn,
                    ratingsOn: this.ratingsOn
                })
            );
        } catch (error) {
            /* ignore quota */
        }
    }

    async hydrateCachedSlideFast() {
        if (this.needsPdfRendering) {
            await this.resolveCurrentSlideUrl();
            if (this.resolvedSlideUrl) {
                this.slideImageReady = true;
                this.pdfSlideReady = true;
            }
            return;
        }
        if (this.needsHtmlRendering) {
            const entry = this.currentHtmlEntry();
            if (await isHtmlPackageReady(this.session.contentDocumentId, entry)) {
                this.htmlPackageReady = true;
            }
        }
    }

    async hydratePagePreviews() {
        this.revokePreviewObjectUrls();
        const docId = this.session?.contentDocumentId;
        if (!docId || !this.needsPdfRendering) {
            return;
        }
        const next = {};
        for (let index = 0; index < this.sequences.length; index += 1) {
            const seq = this.sequences[index];
            const page = this.pdfPageNumber(index);
            try {
                const blob = await getWarmedPageBlob(docId, page);
                if (blob) {
                    const url = createObjectUrl(blob);
                    this.previewObjectUrls.add(url);
                    next[seq.id] = url;
                    continue;
                }
            } catch (error) {
                /* skip missing pages */
            }
            const rendition = buildPdfPageRenditionUrl(
                this.session?.contentVersionId,
                page,
                docId
            );
            if (rendition) {
                next[seq.id] = rendition;
            }
        }
        this.pagePreviewUrls = next;
    }

    async loadLibraryCards() {
        try {
            const entries = await getAllManifestEntries();
            const activeId = this.activePresentationId;
            this.libraryItems = (entries || [])
                .filter((entry) => entry?.presentationId || entry?.id)
                .map((entry) => {
                    const id = entry.presentationId || entry.id;
                    return {
                        key: id,
                        id,
                        name: entry.name || 'Presentation',
                        imageUrl: entry.imageUrl || entry.productImageUrl,
                        formatLabel: entry.formatType || 'CLM',
                        className: id === activeId ? 'thumb thumb-active' : 'thumb'
                    };
                });
        } catch (error) {
            this.libraryItems = [];
        }
    }

    toggleChrome() {
        this.chromeCollapsed = !this.chromeCollapsed;
    }

    showPagesTray() {
        this.trayTab = 'pages';
        this.chromeCollapsed = false;
    }

    showPresentationsTray() {
        this.trayTab = 'presentations';
        this.chromeCollapsed = false;
        this.loadLibraryCards();
    }

    toggleMandatoryFilter() {
        this.filterMandatory = !this.filterMandatory;
    }

    toggleRatings() {
        this.ratingsOn = !this.ratingsOn;
        this.persistStagePrefs();
    }

    togglePersonalized() {
        this.personalizedOn = !this.personalizedOn;
        this.persistStagePrefs();
    }

    cycleFitMode() {
        this.fitMode = this.fitMode === 'contain' ? 'cover' : 'contain';
        this.persistStagePrefs();
    }

    cycleAspect() {
        const index = ASPECT_CYCLE.indexOf(this.aspectPreset);
        this.aspectPreset = ASPECT_CYCLE[(index + 1) % ASPECT_CYCLE.length];
        this.persistStagePrefs();
    }

    zoomIn() {
        this.stageZoom = Math.min(2, Math.round((this.stageZoom + 0.1) * 10) / 10);
        this.persistStagePrefs();
    }

    zoomOut() {
        this.stageZoom = Math.max(0.5, Math.round((this.stageZoom - 0.1) * 10) / 10);
        this.persistStagePrefs();
    }

    resetZoom() {
        this.stageZoom = 1;
        this.persistStagePrefs();
    }

    async handleLibrarySelect(event) {
        const presentationId = event.currentTarget.dataset.id;
        const presentationName = event.currentTarget.dataset.name;
        if (!presentationId || presentationId === this.activePresentationId) {
            this.trayTab = 'pages';
            return;
        }
        this.requestNavigation(() => {
            this.switchPresentation(presentationId, presentationName);
        });
    }

    resetPresentationLoadState() {
        this._loadToken += 1;
        this.cancelPdfRender();
        this.clearSlideImageLoadTimer();
        this.clearHypeSceneTimer();
        this.session = null;
        this.clientSessionKey = null;
        this.isOfflineSession = false;
        this.isSessionLoading = true;
        this.paintedFromCache = false;
        this.pdfDoc = null;
        this.pdfLoading = false;
        this.pdfLoadScheduled = false;
        this.pdfLoadingStatus = null;
        this.pdfLoadError = null;
        this.pdfSlideReady = false;
        this.pdfUsingRendition = false;
        this.pdfCanvasRetryCount = 0;
        this.pdfNativeFrameReady = false;
        this.pdfNativeFallback = false;
        this.slideImageReady = false;
        this.slideImageLoadFailed = false;
        this.htmlPackageReady = false;
        this.htmlPackageLoading = false;
        this.htmlFrameUrl = null;
        this.htmlNativeSize = null;
        this.htmlLoadError = null;
        this.htmlLoadingStatus = null;
        this.htmlSlideReady = false;
        this.resolvedSlideUrl = null;
        this.pagePreviewUrls = {};
        this.preloadedUrls = new Set();
        this.pendingNavigation = null;
        this.messageResponses = [];
        this.capturedMessageNames = new Set();
        this.showMessageOverlay = false;
        this.currentIndex = 0;
        this.revokeObjectUrls();
    }

    async switchPresentation(presentationId, presentationName) {
        this.flushDwell(false);
        this.clearTimer();
        try {
            if (this.session?.id) {
                const serverSessionId = this.getServerSessionId();
                if (serverSessionId && navigator.onLine && !isOfflineMode()) {
                    await cancelSession({ sessionId: serverSessionId });
                } else {
                    await queueOfflineAction({
                        actionType: 'CANCEL_SESSION',
                        clientSessionKey: this.getSessionKey()
                    });
                }
            }
        } catch (error) {
            /* switching decks should still proceed */
        }
        this._activePresentationId = presentationId;
        this.presentationName = presentationName;
        // Clear loading/error flags and invalidate in-flight work from the old deck.
        this.resetPresentationLoadState();
        this.trayTab = 'pages';
        this.dispatchEvent(
            new CustomEvent('switchpresentation', {
                detail: { presentationId, presentationName }
            })
        );
        await this.bootstrapSession();
        this.loadLibraryCards();
    }

    async mergeManifestContentHints() {
        if (!this.session || !this.activePresentationId) {
            return;
        }
        try {
            const manifest = await getManifestEntry(this.activePresentationId);
            if (!manifest) {
                return;
            }
            this.session = {
                ...this.session,
                contentVersionId: this.session.contentVersionId || manifest.contentVersionId,
                contentSize: this.session.contentSize || manifest.contentSize,
                contentDocumentId: this.session.contentDocumentId || manifest.contentDocumentId,
                formatType: this.session.formatType || manifest.formatType,
                htmlEntryPoint: this.session.htmlEntryPoint || manifest.htmlEntryPoint,
                sequences:
                    this.session.sequences && this.session.sequences.length
                        ? this.session.sequences
                        : manifest.sequences || []
            };
        } catch (error) {
            /* manifest hints are optional when the session payload is complete */
        }
    }

    async bootstrapOfflineSession() {
        const manifest = await getManifestEntry(this.activePresentationId);
        if (!manifest) {
            throw new Error('Presentation is not cached. Open Field Home while online first.');
        }
        this.clientSessionKey = createClientSessionKey();
        const session = {
            id: this.clientSessionKey,
            clientSessionKey: this.clientSessionKey,
            visitId: this.visitId,
            presentationId: manifest.presentationId || manifest.id,
            presentationName: manifest.name || this.presentationName,
            formatType: manifest.formatType,
            contentDocumentId: manifest.contentDocumentId,
            contentVersionId: manifest.contentVersionId,
            contentSize: manifest.contentSize,
            status: 'Active',
            productName: manifest.productName,
            productImageUrl: manifest.imageUrl,
            slideCount: manifest.slideCount,
            sequences: manifest.sequences || [],
            trackingPaused: false
        };
        await putLocalSession({
            clientSessionKey: this.clientSessionKey,
            visitId: this.visitId,
            presentationId: session.presentationId,
            session,
            messageResponses: []
        });
        await queueOfflineAction({
            actionType: 'START_SESSION',
            clientSessionKey: this.clientSessionKey,
            visitId: this.visitId,
            presentationId: session.presentationId,
            startedAtIso: new Date().toISOString()
        });
        return session;
    }

    async bootstrapOfflineAdHocSession() {
        const manifest = await getManifestEntry(this.activePresentationId);
        if (!manifest) {
            throw new Error('Presentation is not cached. Open Field Home while online first.');
        }
        this.clientSessionKey = createClientSessionKey();
        const clientVisitKey = createClientSessionKey();
        this.visitId = clientVisitKey;
        const session = {
            id: this.clientSessionKey,
            clientSessionKey: this.clientSessionKey,
            clientVisitKey,
            visitId: clientVisitKey,
            presentationId: manifest.presentationId || manifest.id,
            presentationName: manifest.name || this.presentationName,
            formatType: manifest.formatType,
            contentDocumentId: manifest.contentDocumentId,
            contentVersionId: manifest.contentVersionId,
            contentSize: manifest.contentSize,
            status: 'Active',
            productName: manifest.productName,
            productImageUrl: manifest.imageUrl,
            slideCount: manifest.slideCount,
            sequences: manifest.sequences || [],
            trackingPaused: false
        };
        await putLocalSession({
            clientSessionKey: this.clientSessionKey,
            visitId: clientVisitKey,
            presentationId: session.presentationId,
            session,
            messageResponses: []
        });
        await queueOfflineAction({
            actionType: 'START_ADHOC_SESSION',
            clientSessionKey: this.clientSessionKey,
            clientVisitKey,
            presentationId: session.presentationId,
            startedAtIso: new Date().toISOString()
        });
        return session;
    }

    getSessionKey() {
        return this.session?.serverSessionId || this.session?.clientSessionKey || this.session?.id;
    }

    getServerSessionId() {
        if (this.session?.serverSessionId) {
            return this.session.serverSessionId;
        }
        const id = String(this.session?.id || '');
        if (id && id !== this.clientSessionKey && /^[a-zA-Z0-9]{15}$|^[a-zA-Z0-9]{18}$/.test(id)) {
            return id;
        }
        return null;
    }

    async loadExistingMessageResponses() {
        const serverSessionId = this.getServerSessionId();
        if (!serverSessionId) {
            const local = this.session?.messageResponses;
            if (local?.length) {
                this.applyMessageResponses(local);
            }
            return;
        }
        try {
            const rows = await getSessionMessageResponses({ sessionId: serverSessionId });
            this.applyMessageResponses(rows || []);
        } catch (error) {
            if (!isOfflineMode()) {
                this.showToast('Message sync warning', this.reduceError(error), 'warning');
            }
        }
    }

    applyMessageResponses(rows) {
        this.messageResponses = (rows || []).map((row, index) => ({
            productName: row.productName,
            messageName: row.messageName,
            sentiment: row.sentiment,
            sortOrder: row.sortOrder || index + 1
        }));
        this.capturedMessageNames = new Set(
            this.messageResponses
                .map((row) => (row.messageName || '').trim().toUpperCase())
                .filter(Boolean)
        );
    }

    get sequences() {
        return this.session?.sequences || [];
    }

    get currentSequence() {
        return this.sequences[this.currentIndex] || null;
    }

    get needsPdfRendering() {
        return this.session?.formatType === 'PDF' && !!this.session?.contentDocumentId;
    }

    get needsHtmlRendering() {
        const format = String(this.session?.formatType || '').toUpperCase();
        return (format === 'HTML' || format === 'ZIP') && !!this.session?.contentDocumentId;
    }

    get slideCounterLabel() {
        if (this.isSessionLoading && !this.paintedFromCache) {
            return 'Loading…';
        }
        if (!this.sequences.length) {
            return '0 of 0 Pages';
        }
        return `${this.currentIndex + 1} of ${this.sequences.length} Pages`;
    }

    get playerClass() {
        return this.chromeCollapsed ? 'clm-player chrome-collapsed' : 'clm-player';
    }

    get isPagesTab() {
        return this.trayTab !== 'presentations';
    }

    get isPresentationsTab() {
        return this.trayTab === 'presentations';
    }

    get pagesTabClass() {
        return this.isPagesTab ? 'is-active' : '';
    }

    get presentationsTabClass() {
        return this.isPresentationsTab ? 'is-active' : '';
    }

    get filterButtonClass() {
        return this.filterMandatory ? 'round-btn filter-on' : 'round-btn';
    }

    get ratingsSwitchClass() {
        return this.ratingsOn ? 'ratings-switch ratings-on' : 'ratings-switch';
    }

    get personalizedSwitchClass() {
        return 'personalized-switch';
    }

    get chromeToggleIcon() {
        return this.chromeCollapsed ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get trackingDockClass() {
        return this.trackingPaused ? 'dock-btn dock-btn-paused' : 'dock-btn dock-btn-light';
    }

    get fitModeLabel() {
        return this.fitMode === 'cover' ? 'Cover' : 'Fit';
    }

    get aspectLabel() {
        return ASPECT_LABELS[this.aspectPreset] || '16:9';
    }

    get zoomLabel() {
        return `${Math.round(this.stageZoom * 100)}%`;
    }

    get stageBoxClass() {
        // HTML decks fill the stage; the iframe inside is scaled to its native size.
        const aspect =
            this.aspectPreset === 'auto' || this.needsHtmlRendering ? 'stage-box-auto' : 'stage-box-fixed';
        const fit = this.fitMode === 'cover' ? 'stage-box-cover' : 'stage-box-contain';
        return `stage-box ${aspect} ${fit}`;
    }

    get slideImageClass() {
        return this.showStageSpinner ? 'slide-image slide-image-hidden' : 'slide-image';
    }

    get pdfCanvasClass() {
        return this.showStageSpinner ? 'slide-pdf-canvas slide-pdf-canvas-hidden' : 'slide-pdf-canvas';
    }

    get stageBoxStyle() {
        const zoom = `transform:scale(${this.stageZoom});transform-origin:center center;`;
        if (this.aspectPreset === 'auto' || this.needsHtmlRendering) {
            return zoom;
        }
        // CSS aspect-ratio with max-height:100% keeps the full width and only
        // shrinks the height on short screens, so the box loses its ratio.
        // Size it in px to the largest box of this ratio that fits.
        const avail = this.stageAvail;
        if (avail) {
            const ratio = ASPECT_RATIO[this.aspectPreset] || 16 / 9;
            const width = Math.max(1, Math.min(avail.width, STAGE_BOX_MAX_WIDTH, avail.height * ratio));
            const height = width / ratio;
            return `width:${Math.floor(width)}px;height:${Math.floor(height)}px;min-height:0;${zoom}`;
        }
        const ratio = ASPECT_CSS[this.aspectPreset] || '16 / 9';
        return `aspect-ratio:${ratio};width:min(100%,72rem);max-height:100%;height:auto;${zoom}`;
    }

    get currentSlideUrl() {
        if (this.slideImageLoadFailed) {
            return null;
        }
        return this.resolvedSlideUrl;
    }

    get onLightningHost() {
        const host = (typeof window !== 'undefined' && window.location?.hostname) || '';
        return host.toLowerCase().includes('lightning.force.com');
    }

    get pdfExceedsApexLimit() {
        const size = Number(this.session?.contentSize);
        return Number.isFinite(size) && size > APEX_DOWNLOAD_MAX_BYTES;
    }

    get usePdfNativeFrame() {
        return (
            LIGHTNING_LARGE_PDF_IFRAME &&
            this.needsPdfRendering &&
            this.onLightningHost &&
            (this.pdfExceedsApexLimit || this.pdfNativeFallback)
        );
    }

    get pdfNativeFrameUrl() {
        if (!this.usePdfNativeFrame || !this.session?.contentDocumentId) {
            return null;
        }
        const page = this.pdfPageNumber(this.currentIndex);
        return buildNativeContentUrl(
            this.session.contentDocumentId,
            this.session.publicContentUrl,
            page
        );
    }

    get showPdfNativeFrame() {
        if (this.currentSlideUrl) {
            return false;
        }
        return this.usePdfNativeFrame && !!this.currentSequence && !!this.pdfNativeFrameUrl;
    }

    get showPdfViewer() {
        if (this.currentSlideUrl || this.pdfLoadError || this.usePdfNativeFrame) {
            return false;
        }
        return this.needsPdfRendering && !!this.currentSequence;
    }

    get showHtmlViewer() {
        if (this.currentSlideUrl || this.htmlLoadError) {
            return false;
        }
        return this.needsHtmlRendering && !!this.currentSequence && !!this.htmlFrameUrl;
    }

    get showPlaceholder() {
        return (
            !this.isSessionLoading &&
            !!this.currentSequence &&
            !this.currentSlideUrl &&
            !this.showPdfViewer &&
            !this.showHtmlViewer &&
            !this.showPdfNativeFrame &&
            !this.pdfLoadError &&
            !this.htmlLoadError
        );
    }

    get showStageSpinner() {
        return (
            !this.pdfLoadError &&
            !this.htmlLoadError &&
            (this.isSessionLoading ||
                (this.currentSlideUrl && !this.slideImageReady) ||
                (this.showPdfViewer && !this.pdfSlideReady) ||
                (this.showPdfNativeFrame && !this.pdfNativeFrameReady) ||
                (this.needsHtmlRendering && !this.htmlSlideReady))
        );
    }

    get stageLoadingLabel() {
        if (this.isSessionLoading) {
            return 'Starting presentation…';
        }
        if (this.htmlLoadingStatus) {
            return this.htmlLoadingStatus;
        }
        if (this.pdfLoadingStatus) {
            return this.pdfLoadingStatus;
        }
        if (this.showPdfViewer || this.needsHtmlRendering) {
            return 'Loading slide…';
        }
        return 'Loading slide…';
    }

    get showPauseOverlay() {
        return this.trackingPaused && !this.showMessageOverlay;
    }

    get showOfflineBanner() {
        return this.isOfflineSession || isOfflineMode();
    }

    get trackingToggleLabel() {
        return this.trackingPaused ? 'Resume Tracking' : 'Pause Tracking';
    }

    get trackingIconName() {
        return this.trackingPaused ? 'utility:play' : 'utility:pause';
    }

    get thumbnailItems() {
        return this.sequences
            .map((seq, index) => ({ seq, index }))
            .filter(({ seq }) => {
                if (this.filterMandatory && !seq.isMandatory) {
                    return false;
                }
                return true;
            })
            .map(({ seq, index }) => ({
                key: seq.id,
                label: seq.sequenceName,
                pageLabel: `P${seq.pageNumber || index + 1}`,
                url: this.pagePreviewUrls[seq.id] || seq.thumbnailUrl || seq.slideImageUrl,
                className: index === this.currentIndex ? 'thumb thumb-active' : 'thumb',
                isActive: index === this.currentIndex,
                index
            }));
    }

    get canGoBack() {
        return this.currentIndex > 0;
    }

    get canGoForward() {
        return this.currentIndex < this.sequences.length - 1;
    }

    get isPreviousDisabled() {
        return this.isSessionLoading || this.showMessageOverlay || !this.canGoBack;
    }

    get isNextDisabled() {
        return this.isSessionLoading || this.showMessageOverlay || !this.canGoForward;
    }

    get isCompleteDisabled() {
        return this.isSessionLoading || this.showMessageOverlay || !this.session?.id;
    }

    get overlayProductName() {
        const seq = this.currentSequence;
        return (
            this.session?.productName ||
            this.parseDelimitedValues(seq?.productNames)[0] ||
            this.presentationName
        );
    }

    get isMessageOverlaySaveDisabled() {
        return (
            this.isSavingMessageResponse ||
            !this.overlayMessages.length ||
            !this.overlayMessages.every((message) => !!message.sentiment)
        );
    }

    get sentimentOptions() {
        return SENTIMENTS;
    }

    get hasSlideMessages() {
        return this.parseDelimitedValues(this.currentSequence?.messageNames).length > 0;
    }

    get uncapturedMessageCount() {
        return this.getUncapturedMessagesForCurrentSlide().length;
    }

    get slideMessageButtonLabel() {
        if (!this.hasSlideMessages) {
            return '';
        }
        if (this.uncapturedMessageCount > 0) {
            return this.uncapturedMessageCount === 1
                ? 'Capture Message'
                : `Capture ${this.uncapturedMessageCount} Messages`;
        }
        return 'Message Captured';
    }

    get slideMessageButtonClass() {
        return this.uncapturedMessageCount > 0
            ? 'slide-message-btn slide-message-btn-pending'
            : 'slide-message-btn slide-message-btn-done';
    }

    get overlayMessagesWithOptions() {
        return (this.overlayMessages || []).map((message) => ({
            ...message,
            options: SENTIMENTS.map((option) => ({
                ...option,
                key: `${message.key}_${option.value}`,
                className:
                    message.sentiment === option.value
                        ? 'message-sentiment-btn message-sentiment-btn-selected'
                        : 'message-sentiment-btn'
            }))
        }));
    }

    handleSlideImageLoad() {
        this.clearSlideImageLoadTimer();
        this.slideImageReady = true;
    }

    handleSlideImageError() {
        this.clearSlideImageLoadTimer();
        this.slideImageLoadFailed = true;
        this.slideImageReady = true;
        if (this.pdfUsingRendition) {
            // No server-side previews endpoint exists, so when the page rendition
            // fails the only fix is a smaller deck.
            this.pdfLoadError = this.pdfExceedsApexLimit
                ? this.largeDeckMessage()
                : 'Unable to load this slide from Salesforce Files.';
            this.pdfSlideReady = true;
            return;
        }
        if (this.needsPdfRendering) {
            this.pdfSlideReady = false;
            this.schedulePdfWork();
        }
    }

    clearSlideImageLoadTimer() {
        if (this.slideImageLoadTimerId) {
            window.clearTimeout(this.slideImageLoadTimerId);
            this.slideImageLoadTimerId = null;
        }
    }

    startSlideImageLoadTimer() {
        this.clearSlideImageLoadTimer();
        if (!this.currentSlideUrl) {
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        const timeoutMs = this.pdfUsingRendition
            ? RENDITION_IMAGE_LOAD_TIMEOUT_MS
            : SLIDE_IMAGE_LOAD_TIMEOUT_MS;
        this.slideImageLoadTimerId = window.setTimeout(() => {
            this.slideImageLoadTimerId = null;
            if (!this.slideImageReady && !this.slideImageLoadFailed) {
                this.handleSlideImageError();
            }
        }, timeoutMs);
    }

    schedulePdfWork() {
        if (this.pdfLoadScheduled || !this.showPdfViewer) {
            return;
        }
        this.pdfLoadScheduled = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            this.pdfLoadScheduled = false;
            this.ensurePdfRendered();
        });
    }

    async ensurePdfRendered() {
        if (!this.showPdfViewer || this.pdfLoadError) {
            return;
        }
        if (!this.pdfDoc && !this.pdfLoading) {
            await this.loadPdfDocument();
            return;
        }
        if (this.pdfDoc && !this.pdfSlideReady && !this.pdfLoading) {
            await this.renderCurrentPdfPage();
        }
    }

    async ensurePdfJs() {
        if (this.pdfJsReady) {
            return window.pdfjsLib;
        }
        await loadScript(this, `${PDFJS}/pdf.min.js`);
        window.pdfjsLib.GlobalWorkerOptions.workerSrc = `${PDFJS}/pdf.worker.min.js`;
        this.pdfJsReady = true;
        return window.pdfjsLib;
    }

    base64ToUint8Array(base64) {
        const raw = window.atob(base64);
        const bytes = new Uint8Array(raw.length);
        for (let i = 0; i < raw.length; i += 1) {
            bytes[i] = raw.charCodeAt(i);
        }
        return bytes;
    }

    async fetchPdfBytesFromServlet(contentDocumentId) {
        // Shepherd downloads redirect to file.force.com; fetch() hits CORS in Lightning.
        // clmContentCache routes Lightning downloads through Apex instead.
        throw new Error('Use clmContentCache download helpers in Lightning.');
    }

    async loadPdfBytes(contentDocumentId) {
        const hints = this.contentDownloadHints();
        const cached = await getPdfBytes(contentDocumentId, false, hints);
        if (cached) {
            return cached;
        }
        try {
            const base64 = await getPdfBase64ForPlayer({ contentDocumentId });
            if (base64) {
                return this.base64ToUint8Array(base64);
            }
        } catch (apexError) {
            // Large decks cannot be fetched in Lightning: shepherd redirects to
            // file.force.com, which does not send CORS headers.
        }
        const fromNetwork = await getPdfBytes(contentDocumentId, true, hints);
        if (fromNetwork) {
            return fromNetwork;
        }
        throw new Error('Unable to load presentation file.');
    }

    contentDownloadHints() {
        return {
            contentSize: this.session?.contentSize,
            contentVersionId: this.session?.contentVersionId
        };
    }

    async loadPdfDocument() {
        if (this.pdfDoc || this.pdfLoading || !this.session?.contentDocumentId) {
            return;
        }
        const loadToken = this._loadToken;
        const isStale = () => loadToken !== this._loadToken;
        this.pdfLoading = true;
        this.pdfSlideReady = false;
        this.pdfLoadError = null;
        this.pdfLoadingStatus = 'Initializing viewer…';
        try {
            const pdfjsLib = await withTimeout(
                this.ensurePdfJs(),
                PDF_INIT_TIMEOUT_MS,
                'PDF viewer failed to initialize.'
            );
            if (isStale()) {
                return;
            }
            this.pdfLoadingStatus = 'Downloading presentation…';
            const bytes = await withTimeout(
                this.loadPdfBytes(this.session.contentDocumentId),
                PDF_LOAD_TIMEOUT_MS,
                'Timed out loading presentation file.'
            );
            if (isStale()) {
                return;
            }
            this.pdfLoadingStatus = 'Preparing slides…';
            const doc = await openPdfDocument(pdfjsLib, bytes, {
                timeoutMs: PDF_RENDER_TIMEOUT_MS,
                timeoutMessage: 'Timed out reading presentation file.',
                preferMainThread: shouldPreferPdfMainThread()
            });
            if (isStale()) {
                return;
            }
            this.pdfDoc = doc;
            this.pdfLoadingStatus = 'Rendering slide…';
            await this.renderCurrentPdfPage();
        } catch (error) {
            if (isStale()) {
                return;
            }
            // Byte fetch cannot follow the file.force.com redirect. Show the
            // Salesforce page rendition in <img> instead of calling fetch().
            if (this.onLightningHost && !this.pdfDoc && this.useLightningPdfRendition()) {
                return;
            }
            this.pdfLoadError = this.friendlyPdfLoadError(error);
            this.pdfSlideReady = true;
            this.showToast('Slide load failed', this.pdfLoadError, 'error');
        } finally {
            if (!isStale()) {
                this.pdfLoading = false;
                this.pdfLoadingStatus = null;
            }
        }
    }

    isLargeFileError(error) {
        const message = error?.body?.message || error?.message || '';
        return (
            error?.code === 'LARGE_FILE' ||
            this.pdfExceedsApexLimit ||
            /too large|FILE_TOO_LARGE|Failed to fetch|NetworkError|CORS/i.test(message)
        );
    }

    largeDeckMessage() {
        const size = Number(this.session?.contentSize);
        const sizeText =
            Number.isFinite(size) && size > 0 ? ` (${(size / 1048576).toFixed(1)} MB)` : '';
        return (
            `This presentation file is too large to open here${sizeText}. ` +
            'Slide previews are not available for this deck yet. ' +
            'Ask marketing to re-export a compressed PDF (under about 4 MB) and re-upload it.'
        );
    }

    friendlyPdfLoadError(error) {
        if (this.isLargeFileError(error) && this.onLightningHost) {
            return this.largeDeckMessage();
        }
        return this.reduceError(error);
    }

    cancelPdfRender() {
        if (this.pdfRenderTask) {
            this.pdfRenderTask.cancel();
            this.pdfRenderTask = null;
        }
    }

    async renderCurrentPdfPage() {
        if (!this.pdfDoc) {
            return;
        }
        const canvas = this.template.querySelector('.slide-pdf-canvas');
        if (!canvas) {
            this.pdfCanvasRetryCount += 1;
            if (this.pdfCanvasRetryCount >= PDF_CANVAS_MAX_RETRIES) {
                this.pdfLoadError = 'Unable to render slide. Please retry.';
                this.pdfSlideReady = true;
                return;
            }
            this.schedulePdfWork();
            return;
        }
        this.pdfCanvasRetryCount = 0;
        const pageNumber = this.pdfPageNumber(this.currentIndex);
        const safePage = Math.min(Math.max(pageNumber, 1), this.pdfDoc.numPages);
        try {
            this.cancelPdfRender();
            const pdfPage = await this.pdfDoc.getPage(safePage);
            const viewport = fitPdfPageToCanvas(pdfPage, canvas);
            const context = canvas.getContext('2d', { alpha: false });
            this.pdfRenderTask = pdfPage.render({ canvasContext: context, viewport });
            await withTimeout(
                this.pdfRenderTask.promise,
                PDF_RENDER_TIMEOUT_MS,
                'Timed out rendering slide.'
            );
            this.pdfSlideReady = true;
            this.pdfLoadError = null;
        } catch (error) {
            if (error?.name !== 'RenderingCancelledException') {
                this.pdfLoadError = this.reduceError(error);
                this.pdfSlideReady = true;
                this.showToast('Slide load failed', this.pdfLoadError, 'error');
            }
        } finally {
            this.pdfRenderTask = null;
        }
    }

    handlePdfNativeFrameLoad() {
        this.pdfNativeFrameReady = true;
    }

    handleRetryPdfLoad() {
        this.pdfLoadError = null;
        this.pdfSlideReady = false;
        this.pdfDoc = null;
        this.pdfLoadingStatus = null;
        this.pdfCanvasRetryCount = 0;
        this.pdfUsingRendition = false;
        this.resolvedSlideUrl = null;
        this.slideImageLoadFailed = false;
        this.schedulePdfWork();
    }

    handleRetryHtmlLoad() {
        this.htmlLoadError = null;
        this.htmlLoadingStatus = null;
        this.htmlSlideReady = false;
        this.htmlFrameUrl = null;
        this.htmlPackageReady = false;
        this.scheduleHtmlWork();
    }

    async preloadAdjacentSlides() {
        const indices = [this.currentIndex, this.currentIndex + 1, this.currentIndex - 1];
        for (const index of indices) {
            const seq = this.sequences[index];
            const url = seq?.slideImageUrl || seq?.thumbnailUrl;
            if (!url || this.preloadedUrls.has(url)) {
                continue;
            }
            this.preloadedUrls.add(url);
            try {
                const blob = await getSlideBlob(url, true);
                if (blob) {
                    const objectUrl = createObjectUrl(blob);
                    if (objectUrl) {
                        this.slideObjectUrls.add(objectUrl);
                    }
                }
            } catch (error) {
                const img = new Image();
                img.src = url;
            }
        }
    }

    revokeSlideObjectUrls() {
        this.slideObjectUrls.forEach((url) => URL.revokeObjectURL(url));
        this.slideObjectUrls.clear();
    }

    revokePreviewObjectUrls() {
        this.previewObjectUrls.forEach((url) => URL.revokeObjectURL(url));
        this.previewObjectUrls.clear();
    }

    revokeObjectUrls() {
        this.revokeSlideObjectUrls();
        this.revokePreviewObjectUrls();
    }

    pdfPageNumber(index = this.currentIndex) {
        const sequences = this.sequences;
        const explicit = Number(sequences[index]?.pageNumber);
        const assigned = sequences
            .map((sequence) => Number(sequence?.pageNumber))
            .filter((value) => value > 0);
        if (explicit > 0 && new Set(assigned).size === sequences.length) {
            return explicit;
        }
        return index + 1;
    }

    lightningPdfRenditionUrl() {
        return buildPdfPageRenditionUrl(
            this.session?.contentVersionId,
            this.pdfPageNumber(this.currentIndex),
            this.session?.contentDocumentId
        );
    }

    useLightningPdfRendition() {
        const rendition = this.lightningPdfRenditionUrl();
        if (!rendition) {
            return false;
        }
        this.pdfUsingRendition = true;
        this.slideImageLoadFailed = false;
        this.slideImageReady = false;
        this.resolvedSlideUrl = rendition;
        this.pdfLoadError = null;
        this.pdfSlideReady = true;
        this.startSlideImageLoadTimer();
        return true;
    }

    async resolveCurrentSlideUrl() {
        this.revokeSlideObjectUrls();
        if (this.needsPdfRendering) {
            const page = this.pdfPageNumber(this.currentIndex);
            try {
                const blob = await getWarmedPageBlob(this.session.contentDocumentId, page);
                if (blob) {
                    const objectUrl = createObjectUrl(blob);
                    this.slideObjectUrls.add(objectUrl);
                    this.pdfUsingRendition = false;
                    this.resolvedSlideUrl = objectUrl;
                    return;
                }
            } catch (error) {
                /* fall through to live PDF render or rendition */
            }
            if (this.onLightningHost && this.pdfExceedsApexLimit) {
                const rendition = this.lightningPdfRenditionUrl();
                if (rendition) {
                    this.pdfUsingRendition = true;
                    this.resolvedSlideUrl = rendition;
                    return;
                }
            }
            this.pdfUsingRendition = false;
            this.resolvedSlideUrl = null;
            return;
        }
        this.pdfUsingRendition = false;
        if (this.needsHtmlRendering) {
            this.resolvedSlideUrl = null;
            return;
        }
        const seq = this.currentSequence;
        const url = seq?.slideImageUrl || seq?.thumbnailUrl;
        if (!url) {
            this.resolvedSlideUrl = null;
            return;
        }
        try {
            const blob = await getSlideBlob(url, true);
            if (blob) {
                const objectUrl = createObjectUrl(blob);
                this.slideObjectUrls.add(objectUrl);
                this.resolvedSlideUrl = objectUrl;
                return;
            }
        } catch (error) {
            // Fall back to direct URL below.
        }
        this.resolvedSlideUrl = url;
    }

    async resetSlideReadyState() {
        this.clearSlideImageLoadTimer();
        this.slideImageLoadFailed = false;
        this.pdfLoadError = null;
        await this.resolveCurrentSlideUrl();
        this.slideImageReady = !this.currentSlideUrl;
        if (this.currentSlideUrl) {
            this.startSlideImageLoadTimer();
        }
        if (this.showPdfViewer && this.pdfDoc) {
            this.pdfSlideReady = false;
        } else if (!this.showPdfViewer) {
            this.pdfSlideReady = true;
        } else {
            this.pdfSlideReady = false;
        }
        if (this.needsHtmlRendering) {
            await this.resolveCurrentHtmlFrame();
        }
    }

    scheduleHtmlWork() {
        if (!this.needsHtmlRendering || this.htmlPackageLoading) {
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            this.ensureHtmlPackageLoaded()
                .then(() => this.resolveCurrentHtmlFrame())
                .catch((error) => {
                    this.htmlLoadError = this.reduceError(error);
                    this.htmlLoadingStatus = null;
                    this.showToast('HTML load failed', this.htmlLoadError, 'error');
                });
        }, 0);
    }

    async ensureJsZipReady() {
        if (this.jsZipReady && window.JSZip) {
            return window.JSZip;
        }
        const base = JSZIP;
        const candidates = String(base).endsWith('.js')
            ? [base]
            : [`${base}/jszip.min.js`, base];
        let lastError;
        for (const src of candidates) {
            try {
                await loadScript(this, src);
                if (window.JSZip) {
                    break;
                }
            } catch (error) {
                lastError = error;
            }
        }
        if (!window.JSZip) {
            throw lastError || new Error('Unable to load HTML unzip library.');
        }
        this.jsZipReady = true;
        return window.JSZip;
    }

    ensureHtmlPackageLoaded() {
        if (this.htmlPackageReady || !this.session?.contentDocumentId) {
            return Promise.resolve();
        }
        if (!this._htmlPackagePromise) {
            this._htmlPackagePromise = this.loadHtmlPackage().finally(() => {
                this._htmlPackagePromise = null;
            });
        }
        return this._htmlPackagePromise;
    }

    async loadHtmlPackage() {
        this.htmlPackageLoading = true;
        this.htmlLoadError = null;
        this.htmlLoadingStatus = 'Opening cached slides…';
        try {
            await waitForClmPackageSw();
            const entry = this.currentHtmlEntry();
            if (await isHtmlPackageReady(this.session.contentDocumentId, entry)) {
                try {
                    await htmlPackagePlayUrl(this.session.contentDocumentId, entry);
                    this.htmlPackageReady = true;
                    this.htmlLoadingStatus = null;
                    return;
                } catch (cacheError) {
                    // A cache flag without readable files still has to download the zip.
                }
            }
            const JSZipLib = await this.ensureJsZipReady();
            const htmlLarge =
                Number(this.session?.contentSize) > APEX_DOWNLOAD_MAX_BYTES;
            this.htmlLoadingStatus = htmlLarge
                ? 'Downloading presentation (this may take a minute)…'
                : 'Unpacking slides…';
            const bytes = await downloadContentBytes(
                this.session.contentDocumentId,
                true,
                this.contentDownloadHints()
            );
            await installHtmlPackage(this.session.contentDocumentId, bytes, JSZipLib);
            this.htmlPackageReady = true;
            this.htmlLoadingStatus = null;
        } finally {
            this.htmlPackageLoading = false;
        }
    }

    currentHtmlEntry() {
        return (
            this.currentSequence?.htmlEntryPoint ||
            this.session?.htmlEntryPoint ||
            this.sequences.find((seq) => seq.htmlEntryPoint)?.htmlEntryPoint ||
            'index.html'
        );
    }

    async resolveCurrentHtmlFrame() {
        if (!this.needsHtmlRendering) {
            this.htmlFrameUrl = null;
            this.htmlSlideReady = true;
            return;
        }
        try {
            await this.ensureHtmlPackageLoaded();
            await this.loadHtmlNativeSize();
            const entry = this.currentHtmlEntry();
            // Blob URL, not /clm-pkg/. A relative path on lightning.force.com
            // loads Lightning inside the frame and dies on /lightning/404.
            const nextUrl = await htmlPackagePlayUrl(this.session.contentDocumentId, entry);
            if (!nextUrl) {
                throw new Error('HTML entry point is missing on this slide.');
            }
            if (this.htmlFrameUrl === nextUrl) {
                this.htmlSlideReady = true;
                this.htmlLoadError = null;
                this.scheduleHypeSceneSync();
                return;
            }
            this.htmlSlideReady = false;
            this.htmlFrameUrl = nextUrl;
            this.htmlLoadError = null;
        } catch (error) {
            this.htmlFrameUrl = null;
            this.htmlSlideReady = true;
            this.htmlLoadError = this.reduceError(error);
        } finally {
            this.htmlLoadingStatus = null;
        }
    }

    handleHtmlFrameLoad() {
        this.htmlSlideReady = true;
        this.htmlLoadError = null;
        this.fitHtmlFrame();
        this.scheduleHypeSceneSync();
    }

    async loadHtmlNativeSize() {
        if (this.htmlNativeSize) {
            return;
        }
        const docId = this.session?.contentDocumentId;
        try {
            const layout = getHtmlPackageLayout(docId) || (await inspectInstalledHtmlPackage(docId));
            const width = Number(layout?.width);
            const height = Number(layout?.height);
            if (width >= 200 && height >= 200) {
                this.htmlNativeSize = { width, height };
            }
        } catch (error) {
            // Without a native size the frame just fills the stage.
        }
    }

    // Render the deck at its authored size and scale it to fit the stage,
    // centred. Filling the stage instead crops fixed-size decks.
    fitHtmlFrame(frame) {
        const iframe = frame || this.htmlFrameElement();
        const host = iframe?.parentElement;
        const size = this.htmlNativeSize;
        if (!iframe || !host || !size) {
            return;
        }
        const hostWidth = host.clientWidth;
        const hostHeight = host.clientHeight;
        if (!hostWidth || !hostHeight) {
            return;
        }
        const scale = Math.min(hostWidth / size.width, hostHeight / size.height);
        const left = (hostWidth - size.width * scale) / 2;
        const top = (hostHeight - size.height * scale) / 2;
        iframe.style.cssText =
            `inset:auto;left:${left}px;top:${top}px;` +
            `width:${size.width}px;height:${size.height}px;` +
            `transform:scale(${scale});transform-origin:0 0;`;
    }

    observeStageViewport() {
        if (this.stageResizeObserver || typeof ResizeObserver === 'undefined') {
            return;
        }
        const viewport = this.template.querySelector('.stage-viewport');
        if (!viewport) {
            return;
        }
        this.stageResizeObserver = new ResizeObserver(() => this.handleStageResize(viewport));
        this.stageResizeObserver.observe(viewport);
        this.handleStageResize(viewport);
    }

    handleStageResize(viewport) {
        const styles = window.getComputedStyle(viewport);
        const width =
            viewport.clientWidth - parseFloat(styles.paddingLeft) - parseFloat(styles.paddingRight);
        const height =
            viewport.clientHeight - parseFloat(styles.paddingTop) - parseFloat(styles.paddingBottom);
        if (width <= 0 || height <= 0) {
            return;
        }
        const previous = this.stageAvail;
        if (previous && Math.abs(previous.width - width) < 1 && Math.abs(previous.height - height) < 1) {
            return;
        }
        this.stageAvail = { width, height };
        // Rotation, window resize and the tray opening all change the stage
        // after a slide was drawn; redraw so nothing stays clipped.
        window.clearTimeout(this.stageResizeTimerId);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.stageResizeTimerId = window.setTimeout(() => {
            this.fitHtmlFrame();
            if (this.showPdfViewer && this.pdfDoc && this.pdfSlideReady && !this.pdfLoadError) {
                this.renderCurrentPdfPage();
            }
        }, STAGE_RESIZE_DEBOUNCE_MS);
    }

    htmlFrameElement() {
        return this.template.querySelector('.slide-html-host iframe.slide-html-frame');
    }

    bindHtmlFrame() {
        if (!this.showHtmlViewer || !this.htmlFrameUrl) {
            return;
        }
        const host = this.template.querySelector('.slide-html-host');
        if (!host) {
            return;
        }
        let iframe = host.querySelector('iframe.slide-html-frame');
        if (!iframe) {
            iframe = document.createElement('iframe');
            iframe.className = 'slide-html-frame';
            iframe.title = this.currentSequence?.sequenceName || 'HTML presentation';
            iframe.setAttribute('sandbox', 'allow-scripts allow-same-origin allow-popups allow-forms');
            iframe.addEventListener('load', () => this.handleHtmlFrameLoad());
            host.appendChild(iframe);
        }
        if (iframe.getAttribute('src') !== this.htmlFrameUrl) {
            iframe.src = this.htmlFrameUrl;
        }
        this.fitHtmlFrame(iframe);
    }

    scheduleHypeSceneSync() {
        this.clearHypeSceneTimer();
        this.tryShowHypeScene(0);
    }

    tryShowHypeScene(attempt) {
        const sceneName = this.currentSequence?.sequenceName;
        if (!this.needsHtmlRendering || !sceneName) {
            return;
        }
        const iframe = this.htmlFrameElement();
        if (showHypeScene(iframe, sceneName)) {
            return;
        }
        if (attempt >= 40) {
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.hypeSceneTimerId = window.setTimeout(() => {
            this.tryShowHypeScene(attempt + 1);
        }, 100);
    }

    clearHypeSceneTimer() {
        if (this.hypeSceneTimerId) {
            window.clearTimeout(this.hypeSceneTimerId);
            this.hypeSceneTimerId = null;
        }
    }

    parseDelimitedValues(value) {
        return String(value || '')
            .split(/[;,]/)
            .map((item) => item.trim())
            .filter(Boolean);
    }

    getUncapturedMessagesForCurrentSlide() {
        return this.parseDelimitedValues(this.currentSequence?.messageNames).filter(
            (messageName) => !this.capturedMessageNames.has(messageName.toUpperCase())
        );
    }

    initializeMessageOverlay(messageNames) {
        this.overlayMessages = messageNames.map((messageName, index) => ({
            key: `${messageName}_${index}`,
            messageName,
            sentiment: null
        }));
        this.showMessageOverlay = true;
    }

    handleOpenMessageCapture() {
        const uncapturedMessages = this.getUncapturedMessagesForCurrentSlide();
        if (!uncapturedMessages.length) {
            this.showToast('Messages captured', 'All messages on this slide are already saved.', 'info');
            return;
        }
        this.pendingNavigation = null;
        this.initializeMessageOverlay(uncapturedMessages);
    }

    requestNavigation(applyNavigation) {
        const uncapturedMessages = this.getUncapturedMessagesForCurrentSlide();
        if (uncapturedMessages.length > 0) {
            this.pendingNavigation = applyNavigation;
            this.initializeMessageOverlay(uncapturedMessages);
            return;
        }
        applyNavigation();
    }

    handleOverlaySentimentChange(event) {
        const messageName = event.currentTarget.dataset.name;
        const sentiment = event.currentTarget.dataset.sentiment;
        this.overlayMessages = this.overlayMessages.map((message) =>
            message.messageName === messageName ? { ...message, sentiment } : message
        );
    }

    async persistMessageResponses() {
        const serverSessionId = this.getServerSessionId();
        if (serverSessionId && navigator.onLine && !isOfflineMode()) {
            await saveMessageResponses({
                sessionId: serverSessionId,
                responses: this.messageResponses
            });
            return;
        }
        await queueOfflineAction({
            actionType: 'SAVE_MESSAGE_RESPONSES',
            clientSessionKey: this.getSessionKey(),
            responsesJson: JSON.stringify(this.messageResponses)
        });
        this.session = {
            ...this.session,
            messageResponses: [...this.messageResponses]
        };
    }

    async handleMessageOverlaySave() {
        if (this.isMessageOverlaySaveDisabled || !this.session?.id) {
            return;
        }
        const productName = this.overlayProductName;
        const newResponses = this.overlayMessages.map((message, index) => ({
            productName,
            messageName: message.messageName,
            sentiment: message.sentiment,
            sortOrder: this.messageResponses.length + index + 1
        }));

        const mergedByName = new Map(
            this.messageResponses.map((row) => [row.messageName.toUpperCase(), row])
        );
        newResponses.forEach((row) => {
            mergedByName.set(row.messageName.toUpperCase(), row);
        });
        this.messageResponses = Array.from(mergedByName.values()).map((row, index) => ({
            ...row,
            sortOrder: index + 1
        }));

        this.isSavingMessageResponse = true;
        try {
            await this.persistMessageResponses();
            newResponses.forEach((row) => {
                this.capturedMessageNames.add(row.messageName.toUpperCase());
            });
            this.showMessageOverlay = false;
            this.overlayMessages = [];
            const continueNavigation = this.pendingNavigation;
            this.pendingNavigation = null;
            if (continueNavigation) {
                continueNavigation();
            }
        } catch (error) {
            this.showToast('Message save failed', this.reduceError(error), 'error');
        } finally {
            this.isSavingMessageResponse = false;
        }
    }

    handleMessageOverlayCancel() {
        this.showMessageOverlay = false;
        this.overlayMessages = [];
        this.pendingNavigation = null;
    }

    pauseTracking() {
        if (this.trackingPaused) {
            return;
        }
        this.flushDwell(true);
        this.trackingPaused = true;
        this.clearTimer();
    }

    resumeTracking() {
        this.trackingPaused = false;
        this.dwellAccumulator = 0;
        this.clearTimer();
        this.timerId = window.setInterval(() => {
            if (!this.trackingPaused) {
                this.dwellAccumulator += 1;
            }
        }, 1000);
    }

    toggleTracking() {
        if (this.trackingPaused) {
            this.resumeTracking();
        } else {
            this.pauseTracking();
        }
    }

    async sendSlideEvent(sequenceId, dwellSeconds, paused) {
        const serverSessionId = this.getServerSessionId();
        if (serverSessionId && navigator.onLine && !isOfflineMode()) {
            await logSlideEvent({
                sessionId: serverSessionId,
                sequenceId,
                dwellSeconds,
                trackingPaused: paused
            });
            return;
        }
        await queueOfflineAction({
            actionType: 'LOG_SLIDE_EVENT',
            clientSessionKey: this.getSessionKey(),
            sequenceId,
            dwellSeconds,
            trackingPaused: paused
        });
    }

    flushDwell(paused = false) {
        const seq = this.currentSequence;
        if (!seq || !this.session?.id || this.dwellAccumulator <= 0) {
            if (paused && this.session?.id) {
                this.sendSlideEvent(seq?.id, 0, true).catch(() => {
                    /* ignore pause sync errors */
                });
            }
            return;
        }
        const seconds = this.dwellAccumulator;
        this.dwellAccumulator = 0;
        this.sendSlideEvent(seq.id, seconds, paused).catch((error) => {
            this.showToast('Metric sync failed', this.reduceError(error), 'error');
        });
    }

    handlePrevious() {
        if (!this.canGoBack) {
            return;
        }
        this.requestNavigation(() => {
            this.flushDwell(false);
            this.currentIndex -= 1;
            this.resetSlideReadyState();
            this.preloadAdjacentSlides();
            this.resumeTracking();
            this.schedulePdfWork();
            this.scheduleHtmlWork();
        });
    }

    handleNext() {
        if (!this.canGoForward) {
            return;
        }
        const current = this.currentSequence;
        if (current?.isMandatory && this.dwellAccumulator < 1) {
            this.showToast('Mandatory slide', 'Spend time on this slide before continuing.', 'warning');
            return;
        }
        this.requestNavigation(() => {
            this.flushDwell(false);
            this.currentIndex += 1;
            this.resetSlideReadyState();
            this.preloadAdjacentSlides();
            this.resumeTracking();
            this.schedulePdfWork();
            this.scheduleHtmlWork();
        });
    }

    handleThumbClick(event) {
        const index = Number(event.currentTarget.dataset.index);
        if (Number.isNaN(index) || index === this.currentIndex) {
            return;
        }
        const current = this.currentSequence;
        if (index > this.currentIndex && current?.isMandatory && this.dwellAccumulator < 1) {
            this.showToast('Mandatory slide', 'Spend time on this slide before continuing.', 'warning');
            return;
        }
        this.requestNavigation(() => {
            this.flushDwell(false);
            this.currentIndex = index;
            this.resetSlideReadyState();
            this.preloadAdjacentSlides();
            this.resumeTracking();
            this.schedulePdfWork();
            this.scheduleHtmlWork();
        });
    }

    handleComplete() {
        this.requestNavigation(() => {
            this.completePresentation();
        });
    }

    async completePresentation() {
        await this.flushDwellAndWait(false);
        this.clearTimer();
        try {
            const serverSessionId = this.getServerSessionId();
            if (serverSessionId && navigator.onLine && !isOfflineMode()) {
                this.session = await completeSession({ sessionId: serverSessionId });
            } else {
                await queueOfflineAction({
                    actionType: 'COMPLETE_SESSION',
                    clientSessionKey: this.getSessionKey(),
                    endedAtIso: new Date().toISOString(),
                    slidesPresentedCount: this.session?.slidesPresentedCount,
                    totalDurationSeconds: this.session?.totalDurationSeconds
                });
                this.session = { ...this.session, status: 'Completed' };
            }
            this.dispatchEvent(new CustomEvent('sessioncomplete', { detail: { session: this.session } }));
            this.showToast('Presentation complete', this.presentationName, 'success');
            this.dispatchClose();
        } catch (error) {
            this.showToast('Complete failed', this.reduceError(error), 'error');
        }
    }

    async handleCancel() {
        this.clearTimer();
        try {
            if (this.session?.id) {
                const serverSessionId = this.getServerSessionId();
                if (serverSessionId && navigator.onLine && !isOfflineMode()) {
                    await cancelSession({ sessionId: serverSessionId });
                } else {
                    await queueOfflineAction({
                        actionType: 'CANCEL_SESSION',
                        clientSessionKey: this.getSessionKey()
                    });
                }
            }
        } catch (error) {
            this.showToast('Cancel failed', this.reduceError(error), 'warning');
        }
        this.dispatchClose();
    }

    async flushDwellAndWait(paused = false) {
        const seq = this.currentSequence;
        if (!seq || !this.session?.id || this.dwellAccumulator <= 0) {
            if (paused && this.session?.id) {
                try {
                    await this.sendSlideEvent(seq?.id, 0, true);
                } catch (e) {
                    /* ignore pause sync errors */
                }
            }
            return;
        }
        const seconds = this.dwellAccumulator;
        this.dwellAccumulator = 0;
        try {
            await this.sendSlideEvent(seq.id, seconds, paused);
        } catch (error) {
            this.showToast('Metric sync failed', this.reduceError(error), 'error');
        }
    }

    dispatchClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    clearTimer() {
        if (this.timerId) {
            window.clearInterval(this.timerId);
            this.timerId = null;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}