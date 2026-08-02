import { LightningElement, api, track } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import PDFJS from '@salesforce/resourceUrl/pdfjs';
import { openPdfDocument, withTimeout } from 'c/clmPdfProcessor';
import { getPdfBytes, getSlideBlob, createObjectUrl } from 'c/clmContentCache';
import { getManifestEntry, putLocalSession } from 'c/clmOfflineStore';
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
const PDF_CANVAS_MAX_RETRIES = 30;
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
    @track showMessageOverlay = false;
    @track overlayMessages = [];
    @track isSavingMessageResponse = false;
    @track resolvedSlideUrl;
    @track isOfflineSession = false;

    timerId;
    slideImageLoadTimerId;
    visibilityHandler;
    preloadedUrls = new Set();
    objectUrls = new Set();
    pdfCanvasRetryCount = 0;
    pdfSlideReady = false;
    pdfJsReady = false;
    pdfDoc = null;
    pdfLoading = false;
    pdfRenderTask = null;
    pdfLoadScheduled = false;
    pendingNavigation = null;
    messageResponses = [];
    capturedMessageNames = new Set();
    clientSessionKey;

    connectedCallback() {
        this.visibilityHandler = () => {
            if (document.hidden) {
                this.pauseTracking();
            }
        };
        document.addEventListener('visibilitychange', this.visibilityHandler);
        this.bootstrapSession();
    }

    disconnectedCallback() {
        this.clearTimer();
        this.clearSlideImageLoadTimer();
        this.cancelPdfRender();
        this.revokeObjectUrls();
        document.removeEventListener('visibilitychange', this.visibilityHandler);
    }

    renderedCallback() {
        if (this.showPdfViewer && !this.pdfLoadError) {
            this.schedulePdfWork();
        }
    }

    async bootstrapSession() {
        this.isSessionLoading = true;
        this.pdfLoadError = null;
        try {
            if (this.adHoc) {
                if (isOfflineMode()) {
                    this.session = await this.bootstrapOfflineAdHocSession();
                    this.isOfflineSession = true;
                } else {
                    this.session = await startAdHocPresentation({ presentationId: this.presentationId });
                    this.visitId = this.session.visitId;
                }
            } else if (isOfflineMode()) {
                this.session = await this.bootstrapOfflineSession();
                this.isOfflineSession = true;
            } else {
                this.session = await startSession({
                    visitId: this.visitId,
                    presentationId: this.presentationId
                });
            }
            this.currentIndex = 0;
            await this.loadExistingMessageResponses();
            await this.resetSlideReadyState();
            this.preloadAdjacentSlides();
            this.resumeTracking();
        } catch (error) {
            this.showToast('Unable to start presentation', this.reduceError(error), 'error');
            this.dispatchClose();
        } finally {
            this.isSessionLoading = false;
            if (this.needsPdfRendering) {
                this.pdfSlideReady = false;
                this.schedulePdfWork();
            }
        }
    }

    async bootstrapOfflineSession() {
        const manifest = await getManifestEntry(this.presentationId);
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
        const manifest = await getManifestEntry(this.presentationId);
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

    get slideCounterLabel() {
        if (this.isSessionLoading) {
            return 'Loading…';
        }
        if (!this.sequences.length) {
            return '0 of 0';
        }
        return `${this.currentIndex + 1} of ${this.sequences.length}`;
    }

    get currentSlideUrl() {
        if (this.slideImageLoadFailed) {
            return null;
        }
        return this.resolvedSlideUrl;
    }

    get showPdfViewer() {
        if (this.isSessionLoading || this.currentSlideUrl || this.pdfLoadError) {
            return false;
        }
        return this.needsPdfRendering && !!this.currentSequence;
    }

    get showPlaceholder() {
        return (
            !this.isSessionLoading &&
            !!this.currentSequence &&
            !this.currentSlideUrl &&
            !this.showPdfViewer &&
            !this.pdfLoadError
        );
    }

    get showStageSpinner() {
        return (
            !this.pdfLoadError &&
            (this.isSessionLoading ||
                (this.currentSlideUrl && !this.slideImageReady) ||
                (this.showPdfViewer && !this.pdfSlideReady))
        );
    }

    get stageLoadingLabel() {
        if (this.isSessionLoading) {
            return 'Starting presentation…';
        }
        if (this.pdfLoadingStatus) {
            return this.pdfLoadingStatus;
        }
        if (this.showPdfViewer) {
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
        return this.sequences.map((seq, index) => ({
            key: seq.id,
            label: seq.sequenceName,
            pageLabel: `P${seq.pageNumber || index + 1}`,
            url: seq.thumbnailUrl || seq.slideImageUrl,
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
        this.slideImageLoadTimerId = window.setTimeout(() => {
            this.slideImageLoadTimerId = null;
            if (!this.slideImageReady && !this.slideImageLoadFailed) {
                this.handleSlideImageError();
            }
        }, SLIDE_IMAGE_LOAD_TIMEOUT_MS);
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
        const downloadUrl = `/sfc/servlet.shepherd/document/download/${encodeURIComponent(contentDocumentId)}`;
        const response = await fetch(downloadUrl, { credentials: 'same-origin' });
        if (!response.ok) {
            throw new Error(`Unable to load presentation (HTTP ${response.status}).`);
        }
        return new Uint8Array(await response.arrayBuffer());
    }

    async loadPdfBytes(contentDocumentId) {
        const cached = await getPdfBytes(contentDocumentId, navigator.onLine);
        if (cached) {
            return cached;
        }
        try {
            return await this.fetchPdfBytesFromServlet(contentDocumentId);
        } catch (fetchError) {
            const base64 = await getPdfBase64ForPlayer({ contentDocumentId });
            if (!base64) {
                throw fetchError;
            }
            return this.base64ToUint8Array(base64);
        }
    }

    async loadPdfDocument() {
        if (this.pdfDoc || this.pdfLoading || !this.session?.contentDocumentId) {
            return;
        }
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
            this.pdfLoadingStatus = 'Downloading presentation…';
            const bytes = await withTimeout(
                this.loadPdfBytes(this.session.contentDocumentId),
                PDF_LOAD_TIMEOUT_MS,
                'Timed out loading presentation file.'
            );
            this.pdfLoadingStatus = 'Preparing slides…';
            this.pdfDoc = await openPdfDocument(pdfjsLib, bytes, {
                timeoutMs: PDF_RENDER_TIMEOUT_MS,
                timeoutMessage: 'Timed out reading presentation file.',
                preferMainThread: false
            });
            this.pdfLoadingStatus = 'Rendering slide…';
            await this.renderCurrentPdfPage();
        } catch (error) {
            this.pdfLoadError = this.reduceError(error);
            this.pdfSlideReady = true;
            this.showToast('Slide load failed', this.pdfLoadError, 'error');
        } finally {
            this.pdfLoading = false;
            this.pdfLoadingStatus = null;
        }
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
        const pageNumber = this.currentSequence?.pageNumber || this.currentIndex + 1;
        const safePage = Math.min(Math.max(pageNumber, 1), this.pdfDoc.numPages);
        try {
            this.cancelPdfRender();
            const pdfPage = await this.pdfDoc.getPage(safePage);
            const viewport = pdfPage.getViewport({ scale: 1.5 });
            const context = canvas.getContext('2d');
            canvas.width = viewport.width;
            canvas.height = viewport.height;
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

    handleRetryPdfLoad() {
        this.pdfLoadError = null;
        this.pdfSlideReady = false;
        this.pdfDoc = null;
        this.pdfLoadingStatus = null;
        this.pdfCanvasRetryCount = 0;
        this.schedulePdfWork();
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
                const blob = await getSlideBlob(url, navigator.onLine);
                if (blob) {
                    const objectUrl = createObjectUrl(blob);
                    if (objectUrl) {
                        this.objectUrls.add(objectUrl);
                    }
                }
            } catch (error) {
                const img = new Image();
                img.src = url;
            }
        }
    }

    revokeObjectUrls() {
        this.objectUrls.forEach((url) => URL.revokeObjectURL(url));
        this.objectUrls.clear();
    }

    async resolveCurrentSlideUrl() {
        this.revokeObjectUrls();
        const seq = this.currentSequence;
        const url = seq?.slideImageUrl || seq?.thumbnailUrl;
        if (!url) {
            this.resolvedSlideUrl = null;
            return;
        }
        try {
            const blob = await getSlideBlob(url, navigator.onLine);
            if (blob) {
                const objectUrl = createObjectUrl(blob);
                this.objectUrls.add(objectUrl);
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
        if (serverSessionId && navigator.onLine) {
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
        if (serverSessionId && navigator.onLine) {
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
            if (serverSessionId && navigator.onLine) {
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
                if (serverSessionId && navigator.onLine) {
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
