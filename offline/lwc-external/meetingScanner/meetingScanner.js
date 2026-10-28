import { LightningElement, api } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { getBarcodeScanner } from 'lightning/mobileCapabilities';
import JSQR from '@salesforce/resourceUrl/MeetingJsQR';
import scanAttendee from '@salesforce/apex/MeetingLifecycleController.scanAttendee';

const SAME_CODE_PAUSE_MS = 2500;
const RESULT_MS = 1800;
const FRAME_INTERVAL_MS = 120;
const DECODE_WIDTH = 520;

const TONES = {
    checked_in: 'ok',
    already: 'warn',
    closed: 'warn',
    inactive: 'warn',
    expired: 'bad',
    invalid: 'bad',
    other_meeting: 'bad'
};

export default class MeetingScanner extends LightningElement {
    @api meetingId;
    @api meetingTitle;
    @api checkedInCount = 0;
    @api invitedCount = 0;

    mode = 'starting';
    cameraError;
    result;
    recent = [];
    busy = false;
    changed = false;
    _checked = 0;
    _invited = 0;

    _stream;
    _timer;
    _detector;
    _jsQr;
    _lastText;
    _lastAt = 0;
    _native;
    _closed = false;
    _resultTimer;

    connectedCallback() {
        this._closed = false;
        this._checked = this.checkedInCount || 0;
        this._invited = this.invitedCount || 0;
        let native = null;
        try {
            native = getBarcodeScanner();
        } catch (e) {
            native = null;
        }
        if (native && native.isAvailable()) {
            this._native = native;
            this.mode = 'native';
        } else {
            this.mode = 'camera';
        }
    }

    renderedCallback() {
        if (this._started) {
            return;
        }
        this._started = true;
        if (this.mode === 'native') {
            this.scanNative();
        } else {
            this.startCamera();
        }
    }

    disconnectedCallback() {
        this._closed = true;
        this.stopCamera();
        clearTimeout(this._resultTimer);
        if (this._native) {
            try {
                this._native.endCapture();
            } catch (e) {
                // already closed
            }
        }
    }

    // ---------------------------------------------------------------- getters

    get isNative() {
        return this.mode === 'native';
    }
    get isCamera() {
        return this.mode === 'camera';
    }
    get counterText() {
        return `${this._checked || 0} / ${this._invited || 0}`;
    }
    get hasResult() {
        return !!this.result;
    }
    get resultCls() {
        return `result result_${this.result ? this.result.tone : 'ok'}`;
    }
    get isOk() {
        return this.result && this.result.tone === 'ok';
    }
    get isWarn() {
        return this.result && this.result.tone === 'warn';
    }
    get hasRecent() {
        return this.recent.length > 0;
    }
    get viewfinderCls() {
        return `viewfinder ${this.busy ? 'viewfinder_busy' : ''} ${this.result ? 'viewfinder_' + this.result.tone : ''}`;
    }

    // ---------------------------------------------------------------- camera (browser)

    async startCamera() {
        this.cameraError = null;
        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
            this.cameraError = 'This browser cannot open the camera. Use the Salesforce mobile app or Chrome on your phone.';
            return;
        }
        try {
            this._stream = await navigator.mediaDevices.getUserMedia({
                audio: false,
                video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } }
            });
        } catch (e) {
            this.cameraError =
                e && e.name === 'NotAllowedError'
                    ? 'Camera access was blocked. Allow the camera for this site and try again.'
                    : 'No camera was found on this device.';
            return;
        }
        if (this._closed) {
            this.stopCamera();
            return;
        }
        const video = this.template.querySelector('video');
        video.srcObject = this._stream;
        video.setAttribute('playsinline', '');
        video.muted = true;
        try {
            await video.play();
        } catch (e) {
            // autoplay is allowed for muted video; ignore transient play() rejections
        }
        await this.prepareDecoder();
        this._timer = setInterval(() => this.decodeFrame(), FRAME_INTERVAL_MS);
    }

    async prepareDecoder() {
        if (typeof window.BarcodeDetector === 'function') {
            try {
                const formats = await window.BarcodeDetector.getSupportedFormats();
                if (formats.includes('qr_code')) {
                    this._detector = new window.BarcodeDetector({ formats: ['qr_code'] });
                    return;
                }
            } catch (e) {
                this._detector = null;
            }
        }
        try {
            await loadScript(this, JSQR);
            this._jsQr = window.jsQR;
        } catch (e) {
            this.cameraError = 'The QR reader could not load. Check the connection and try again.';
        }
    }

    stopCamera() {
        clearInterval(this._timer);
        this._timer = null;
        if (this._stream) {
            this._stream.getTracks().forEach((t) => t.stop());
            this._stream = null;
        }
    }

    async decodeFrame() {
        if (this.busy || this._decoding) {
            return;
        }
        const video = this.template.querySelector('video');
        if (!video || video.readyState < 2 || !video.videoWidth) {
            return;
        }
        this._decoding = true;
        try {
            let text = null;
            if (this._detector) {
                const codes = await this._detector.detect(video);
                text = codes && codes.length ? codes[0].rawValue : null;
            } else if (this._jsQr) {
                const canvas = this.template.querySelector('canvas.decode');
                const scale = Math.min(1, DECODE_WIDTH / video.videoWidth);
                const w = Math.round(video.videoWidth * scale);
                const h = Math.round(video.videoHeight * scale);
                canvas.width = w;
                canvas.height = h;
                const ctx = canvas.getContext('2d', { willReadFrequently: true });
                ctx.drawImage(video, 0, 0, w, h);
                const image = ctx.getImageData(0, 0, w, h);
                const found = this._jsQr(image.data, w, h, { inversionAttempts: 'dontInvert' });
                text = found ? found.data : null;
            }
            if (text) {
                await this.handleText(text);
            }
        } catch (e) {
            // a dropped frame is harmless; the next tick tries again
        } finally {
            this._decoding = false;
        }
    }

    // ---------------------------------------------------------------- native scanner (Salesforce mobile app)

    scanNative() {
        if (this._closed || !this._native) {
            return;
        }
        const scanner = this._native;
        scanner
            .beginCapture({
                barcodeTypes: [scanner.barcodeTypes.QR],
                instructionText: 'Point at the guest’s live QR code',
                successText: 'Checking…',
                showSuccessCheckMark: false,
                vibrateOnSuccess: true
            })
            .then((barcode) => {
                scanner.endCapture();
                return this.handleText(barcode && barcode.value, true);
            })
            .catch((error) => {
                scanner.endCapture();
                if (error && error.code === 'USER_DISMISSED') {
                    this.close();
                } else if (!this._closed) {
                    this.cameraError = (error && error.message) || 'The scanner closed unexpectedly.';
                }
            });
    }

    handleScanNext() {
        this.result = null;
        this.cameraError = null;
        if (this.isNative) {
            this.scanNative();
        }
    }

    // ---------------------------------------------------------------- verification

    async handleText(text, fromNative) {
        if (!text) {
            return;
        }
        const now = Date.now();
        if (!fromNative && text === this._lastText && now - this._lastAt < SAME_CODE_PAUSE_MS) {
            return;
        }
        this._lastText = text;
        this._lastAt = now;
        this.busy = true;
        let outcome;
        try {
            outcome = await scanAttendee({ meetingId: this.meetingId, payload: text });
        } catch (e) {
            outcome = {
                outcome: 'invalid',
                ok: false,
                title: 'Could not check in',
                message: (e && e.body && e.body.message) || 'Check the connection and scan again.'
            };
        }
        this.busy = false;
        this.showResult(outcome, fromNative);
    }

    showResult(outcome, fromNative) {
        const tone = TONES[outcome.outcome] || 'bad';
        if (typeof outcome.checkedInCount === 'number') {
            this._checked = outcome.checkedInCount;
            this._invited = outcome.invitedCount;
        }
        this.result = { ...outcome, tone };
        this.feedback(tone);
        if (outcome.ok) {
            this.changed = true;
            this.recent = [
                {
                    key: `${outcome.invitationId}-${Date.now()}`,
                    name: outcome.guestName,
                    initials: initials(outcome.guestName),
                    time: new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })
                },
                ...this.recent
            ].slice(0, 8);
            this.dispatchEvent(new CustomEvent('checkin', { detail: { invitationId: outcome.invitationId } }));
        }
        clearTimeout(this._resultTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._resultTimer = setTimeout(() => {
            if (fromNative) {
                this.handleScanNext();
            } else {
                this.result = null;
            }
        }, fromNative ? RESULT_MS + 400 : RESULT_MS);
    }

    feedback(tone) {
        try {
            if (navigator.vibrate) {
                navigator.vibrate(tone === 'ok' ? 80 : [60, 60, 60]);
            }
        } catch (e) {
            // vibration is optional
        }
        try {
            const Ctx = window.AudioContext || window.webkitAudioContext;
            if (!Ctx) {
                return;
            }
            this._audio = this._audio || new Ctx();
            const osc = this._audio.createOscillator();
            const gain = this._audio.createGain();
            osc.frequency.value = tone === 'ok' ? 880 : 220;
            gain.gain.value = 0.08;
            osc.connect(gain);
            gain.connect(this._audio.destination);
            osc.start();
            osc.stop(this._audio.currentTime + (tone === 'ok' ? 0.12 : 0.3));
        } catch (e) {
            // sound is optional
        }
    }

    handleRetryCamera() {
        if (this.isNative) {
            this.handleScanNext();
        } else {
            this.stopCamera();
            this.startCamera();
        }
    }

    close() {
        this._closed = true;
        this.stopCamera();
        this.dispatchEvent(new CustomEvent('close', { detail: { changed: this.changed } }));
    }

    handleClose() {
        this.close();
    }
}

function initials(name) {
    return String(name || '?')
        .split(/\s+/)
        .filter((p) => p && !/^(dr|dr\.)$/i.test(p))
        .slice(0, 2)
        .map((p) => p[0].toUpperCase())
        .join('');
}
