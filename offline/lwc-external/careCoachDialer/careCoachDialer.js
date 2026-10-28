import { LightningElement, api } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import JSSIP_URL from '@salesforce/resourceUrl/JsSIP';
import getDialerConfig from '@salesforce/apex/CareCoachTelephonyController.getDialerConfig';
import previewInsight from '@salesforce/apex/CareCoachCallAnalysisService.preview';
import { reduceError } from 'c/careCoachUtils';

const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];
const KEY_LETTERS = { 2: 'ABC', 3: 'DEF', 4: 'GHI', 5: 'JKL', 6: 'MNO', 7: 'PQRS', 8: 'TUV', 9: 'WXYZ', 0: '+' };
const CONNECT_TIMEOUT_MS = 12000;
const MIME_CANDIDATES = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4;codecs=mp4a.40.2', 'audio/mp4'];
const ICE_SERVERS = [{ urls: ['stun:stun.l.google.com:19302'] }];
const SLICE_MS = 9000;

const SAMPLES = {
    rash: {
        file: 'ar-eg-side-effect.mp3',
        lines: [
            { at: 0, speaker: 'Coach', text: 'ألو يا أستاذ، أنا من برنامج إربيتوكس. عامل إيه من آخر جرعة؟' },
            { at: 7440, speaker: 'Patient', text: 'والله فيه طفح خفيف على وشي من بعد الجلسة، ومش مريحني.' },
            { at: 13032, speaker: 'Coach', text: 'ده عرض معروف مع إربيتوكس. رطب بشرتك مرتين في اليوم، وابعد عن الشمس. لو الطفح زاد أو فيه ضيق تنفس، كلمني فوراً وهبلّغ الطبيب.' },
            { at: 27096, speaker: 'Patient', text: 'حاضر. دلوقتي خفيف، بس هتابع وأكلمك لو زاد.' }
        ]
    },
    dose: {
        file: 'ar-eg-adherence.mp3',
        lines: [
            { at: 0, speaker: 'Coach', text: 'ألو، أنا كوتش البرنامج. حابة أسأل: الجرعات ماشية مظبوط؟' },
            { at: 7752, speaker: 'Patient', text: 'بصراحة نسيت جرعة أول امبارح، وبعديها رجعت أخد في الميعاد.' },
            { at: 13968, speaker: 'Coach', text: 'ولا يهمك، متزودش الجرعة. ظبط منبّه على الموبايل قبل الميعاد بنص ساعة، وهكلمك الأسبوع الجاي نتطمن.' },
            { at: 25008, speaker: 'Patient', text: 'ماشي، هظبط المنبّه. شكراً.' }
        ]
    }
};

function sampleSrc(file) {
    const host = window.location.hostname || '';
    if (host === 'localhost' || host.endsWith('salesforceoffline.com')) {
        return `/media/calls/${file}`;
    }
    return `https://www.salesforceoffline.com/media/calls/${file}`;
}

function pad(n) {
    return String(n).padStart(2, '0');
}

function blobToBase64(blob) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(String(reader.result).split(',')[1] || '');
        reader.onerror = () => reject(reader.error);
        reader.readAsDataURL(blob);
    });
}

function extensionFor(mime) {
    return mime && mime.includes('mp4') ? 'm4a' : 'webm';
}

/**
 * Merges per-speaker Whisper segments into "Coach: ..." / "Patient: ..." lines ordered by time.
 */
export function mergeSegments(tracks) {
    const all = [];
    tracks.forEach(({ speaker, segments }) => {
        (segments || []).forEach((s) => {
            const text = String(s.text || '').trim();
            if (text) all.push({ speaker, start: Number(s.start) || 0, text });
        });
    });
    all.sort((a, b) => a.start - b.start);
    const lines = [];
    all.forEach((s) => {
        const last = lines[lines.length - 1];
        if (last && last.speaker === s.speaker) last.text += ` ${s.text}`;
        else lines.push({ speaker: s.speaker, text: s.text });
    });
    return lines.map((l) => `${l.speaker}: ${l.text}`).join('\n');
}

export default class CareCoachDialer extends LightningElement {
    @api patientName;
    @api phone;
    @api callId;

    state = 'loading';
    config;
    error;
    number = '';
    consent = false;
    callLanguage = 'ar';
    muted = false;
    held = false;
    showKeypad = false;
    elapsed = 0;
    answered = false;
    progressText = '';
    lastOutcome;

    ua;
    session;
    localStream;
    remoteStream;
    audioCtx;
    recorders = [];
    timer;
    wakeLock;
    startedAt;
    endCause;
    liveLines = [];
    insight;
    insightPending = false;
    captureError;
    stopping = false;
    sliceStop;
    fullRecorder;
    fullChunks = [];
    micStream;
    sampleTimers = [];
    hearingText = '';
    modelStatus = '';
    whisperReady = false;
    speechRec;

    connectedCallback() {
        this.number = this.phone || '';
        this.init();
        this.prepareOnDeviceTranscription();
    }

    disconnectedCallback() {
        this.teardown();
    }

    async init() {
        try {
            const [config] = await Promise.all([getDialerConfig(), loadScript(this, JSSIP_URL)]);
            this.config = config;
            this.state = config && config.enabled && config.sipConfigured && window.JsSIP ? 'ready' : 'unavailable';
        } catch (e) {
            this.error = reduceError(e);
            this.state = 'unavailable';
        }
    }

    // ---------------------------------------------------------------- view state

    get isLoading() {
        return this.state === 'loading';
    }
    get isUnavailable() {
        return this.state === 'unavailable';
    }
    get isReady() {
        return this.state === 'ready' || this.state === 'failed';
    }
    get isActive() {
        return this.state === 'connecting' || this.state === 'ringing' || this.state === 'incall';
    }
    get isInCall() {
        return this.state === 'incall';
    }
    get isTranscribing() {
        return this.state === 'transcribing';
    }
    get transcribingLabel() {
        return this.stopping ? 'Saving the recording…' : 'Transcribing both sides of the call…';
    }
    get isCoaching() {
        return this.state === 'recording' || this.state === 'sample';
    }
    get showDemo() {
        return this.isReady || this.isUnavailable;
    }
    get coachingTitle() {
        return this.state === 'sample' ? 'Sample call' : 'Recording the room';
    }
    get coachingHint() {
        return this.state === 'sample'
            ? 'Playing an Egyptian Arabic call. The transcript and the coaching card update as they speak.'
            : 'The other phone stays on speaker. This tablet records the room. Words appear as they are spoken, and Whisper transcribes Arabic — including Egyptian colloquial — here in the browser.';
    }
    get deviceRecordHelp() {
        return 'Call from the other phone and leave it on speaker. This tablet records the conversation and transcribes it on the device: live Egyptian Arabic (ar-EG), with open-source Whisper in the browser. No paid transcription API.';
    }
    get hasInsight() {
        return !!this.insight;
    }
    get sentimentClass() {
        const s = (this.insight && this.insight.sentiment) || '';
        if (s === 'Positive') return 'pill pill_pos';
        if (s === 'Negative') return 'pill pill_neg';
        return 'pill';
    }
    get isFailed() {
        return this.state === 'failed';
    }
    get showDialPad() {
        return this.isReady || (this.isInCall && this.showKeypad);
    }
    get telHref() {
        return `tel:${this.cleanNumber}`;
    }
    get cleanNumber() {
        let n = String(this.number || '').replace(/[^\d+*#]/g, '');
        if (n.startsWith('00')) n = `+${n.slice(2)}`;
        return n;
    }
    get callDisabled() {
        return !this.cleanNumber;
    }
    get statusLabel() {
        switch (this.state) {
            case 'connecting':
                return 'Connecting…';
            case 'ringing':
                return this.progressText || 'Ringing…';
            case 'incall':
                return this.held ? 'On hold' : this.timerLabel;
            case 'recording':
            case 'sample':
                return this.timerLabel;
            case 'transcribing':
                return 'Transcribing the call…';
            case 'failed':
                return this.endCause || 'Call failed';
            default:
                return '';
        }
    }
    get timerLabel() {
        return `${pad(Math.floor(this.elapsed / 60))}:${pad(this.elapsed % 60)}`;
    }
    get isRecording() {
        return this.state === 'recording' || this.state === 'sample' || (this.isInCall && this.recorders.length > 0);
    }
    get noLines() {
        return !this.liveLines.length;
    }
    get waitingForSpeech() {
        return !this.liveLines.length && !this.hearingText;
    }
    get containerClass() {
        return this.isCoaching ? 'slds-modal__container dialer-container is-wide' : 'slds-modal__container dialer-container';
    }
    get transcriptionAvailable() {
        return this.config && this.config.transcriptionConfigured;
    }
    get consentHelp() {
        if (!this.transcriptionAvailable) {
            return 'The call is recorded on this device. Transcription is not configured, so no transcript will be produced.';
        }
        return this.callLanguage === 'ar'
            ? 'Recorded on this device and transcribed with OpenAI gpt-4o-transcribe. Egyptian Arabic is kept in العامية, not rewritten into formal Arabic.'
            : 'Recorded on this device and transcribed with OpenAI gpt-4o-transcribe.';
    }
    get arabicLangClass() {
        return this.callLanguage === 'ar' ? 'is-active' : '';
    }
    get englishLangClass() {
        return this.callLanguage === 'en' ? 'is-active' : '';
    }
    handleLanguage(event) {
        this.callLanguage = event.currentTarget.dataset.lang === 'en' ? 'en' : 'ar';
    }
    get keys() {
        return KEYS.map((k) => ({ key: k, letters: KEY_LETTERS[k] || '' }));
    }
    get muteVariant() {
        return this.muted ? 'ctl ctl_on' : 'ctl';
    }
    get holdVariant() {
        return this.held ? 'ctl ctl_on' : 'ctl';
    }
    get keypadVariant() {
        return this.showKeypad ? 'ctl ctl_on' : 'ctl';
    }
    get muteLabel() {
        return this.muted ? 'Unmute' : 'Mute';
    }
    get holdLabel() {
        return this.held ? 'Resume' : 'Hold';
    }

    // ---------------------------------------------------------------- input

    handleNumber(event) {
        this.number = event.detail.value;
    }

    handleConsent(event) {
        this.consent = event.detail.checked === true || event.target.checked === true;
    }

    handleKey(event) {
        const key = event.currentTarget.dataset.key;
        if (this.isInCall && this.session) {
            try {
                this.session.sendDTMF(key);
            } catch (e) {
                // DTMF is best effort; some trunks only accept RFC 2833 after media is up.
            }
            return;
        }
        this.number = `${this.number || ''}${key}`;
    }

    handleBackspace() {
        this.number = String(this.number || '').slice(0, -1);
    }

    toggleKeypad() {
        this.showKeypad = !this.showKeypad;
    }

    toggleMute() {
        if (!this.session) return;
        if (this.muted) this.session.unmute({ audio: true });
        else this.session.mute({ audio: true });
        this.muted = !this.muted;
    }

    toggleHold() {
        if (!this.session) return;
        if (this.held) this.session.unhold();
        else this.session.hold();
        this.held = !this.held;
    }

    handleClose() {
        if (this.isActive) return;
        this.teardown();
        this.dispatchEvent(new CustomEvent('close'));
    }

    // ---------------------------------------------------------------- call

    async startCall() {
        if (this.callDisabled) return;
        this.error = undefined;
        this.endCause = undefined;
        this.answered = false;
        this.elapsed = 0;
        this.state = 'connecting';
        try {
            this.localStream = await navigator.mediaDevices.getUserMedia({
                audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true },
                video: false
            });
            await this.connectUa();
            const cfg = this.config;
            const eventHandlers = {
                peerconnection: (e) => {
                    e.peerconnection.addEventListener('track', (ev) => this.onRemoteTrack(ev));
                },
                progress: () => {
                    this.state = 'ringing';
                    this.progressText = 'Ringing…';
                },
                accepted: () => this.onAnswered(),
                confirmed: () => this.onAnswered(),
                ended: (e) => this.finishCall(e && e.cause),
                failed: (e) => this.finishCall(e && e.cause, true)
            };
            this.session = this.ua.call(`sip:${this.cleanNumber}@${cfg.domain}`, {
                eventHandlers,
                mediaStream: this.localStream,
                pcConfig: { iceServers: ICE_SERVERS },
                rtcOfferConstraints: { offerToReceiveAudio: true, offerToReceiveVideo: false },
                fromDisplayName: cfg.callerId || undefined
            });
        } catch (e) {
            this.error = e && e.name === 'NotAllowedError' ? 'Microphone access was blocked. Allow the microphone to place calls.' : reduceError(e);
            this.endCause = 'Could not start the call';
            this.teardown();
            this.state = 'failed';
        }
    }

    connectUa() {
        const JsSIP = window.JsSIP;
        const cfg = this.config;
        return new Promise((resolve, reject) => {
            const socket = new JsSIP.WebSocketInterface(cfg.wssUrl);
            const ua = new JsSIP.UA({
                sockets: [socket],
                uri: `sip:${cfg.username}@${cfg.domain}`,
                authorization_user: cfg.username,
                password: cfg.password,
                display_name: cfg.callerId || undefined,
                register: false,
                session_timers: false,
                user_agent: 'ZetaCareCoach/1.0'
            });
            const timeout = setTimeout(() => reject(new Error('Could not reach the phone service. Check the connection and try again.')), CONNECT_TIMEOUT_MS);
            ua.on('connected', () => {
                clearTimeout(timeout);
                resolve();
            });
            ua.on('disconnected', () => {
                if (!this.session) {
                    clearTimeout(timeout);
                    reject(new Error('The phone service refused the connection.'));
                }
            });
            this.ua = ua;
            ua.start();
        });
    }

    onRemoteTrack(event) {
        const stream = (event.streams && event.streams[0]) || new MediaStream([event.track]);
        this.remoteStream = stream;
        const audio = this.template.querySelector('audio.remote');
        if (audio) {
            audio.srcObject = stream;
            const played = audio.play();
            if (played && played.catch) played.catch(() => {});
        }
        if (this.answered) this.startRecording();
    }

    onAnswered() {
        if (this.answered) return;
        this.answered = true;
        this.state = 'incall';
        this.startedAt = Date.now();
        this.timer = setInterval(() => {
            this.elapsed = Math.round((Date.now() - this.startedAt) / 1000);
        }, 1000);
        if (!this.remoteStream && this.session && this.session.connection) {
            const tracks = this.session.connection
                .getReceivers()
                .map((r) => r.track)
                .filter((t) => t && t.kind === 'audio');
            if (tracks.length) this.onRemoteTrack({ track: tracks[0], streams: [new MediaStream(tracks)] });
        }
        this.startRecording();
        this.keepAwake();
    }

    async keepAwake() {
        try {
            if (navigator.wakeLock && navigator.wakeLock.request) {
                this.wakeLock = await navigator.wakeLock.request('screen');
            }
        } catch (e) {
            this.wakeLock = undefined;
        }
    }

    hangUp() {
        if (this.session) {
            try {
                this.session.terminate();
                return;
            } catch (e) {
                // Session already ended.
            }
        }
        this.finishCall('Canceled');
    }

    // ---------------------------------------------------------------- recording

    startRecording() {
        if (!this.consent || this.recorders.length || !this.localStream || !this.remoteStream || typeof window.MediaRecorder === 'undefined') {
            return;
        }
        const mimeType = MIME_CANDIDATES.find((t) => window.MediaRecorder.isTypeSupported && window.MediaRecorder.isTypeSupported(t)) || '';
        const make = (speaker, stream, bits) => {
            const chunks = [];
            const recorder = new window.MediaRecorder(stream, mimeType ? { mimeType, audioBitsPerSecond: bits } : { audioBitsPerSecond: bits });
            recorder.ondataavailable = (e) => {
                if (e.data && e.data.size) chunks.push(e.data);
            };
            recorder.start(1000);
            return { speaker, recorder, chunks, mimeType: recorder.mimeType || mimeType };
        };
        try {
            const Ctx = window.AudioContext || window.webkitAudioContext;
            this.audioCtx = new Ctx();
            const dest = this.audioCtx.createMediaStreamDestination();
            this.audioCtx.createMediaStreamSource(this.localStream).connect(dest);
            this.audioCtx.createMediaStreamSource(this.remoteStream).connect(dest);
            this.recorders = [
                make('Coach', this.localStream, 24000),
                make('Patient', this.remoteStream, 24000),
                make('Mixed', dest.stream, 24000)
            ];
        } catch (e) {
            this.recorders = [];
        }
    }

    stopRecording() {
        const recs = this.recorders;
        this.recorders = [];
        return Promise.all(
            recs.map(
                (r) =>
                    new Promise((resolve) => {
                        const done = () => resolve({ speaker: r.speaker, blob: new Blob(r.chunks, { type: (r.mimeType || 'audio/webm').split(';')[0] }) });
                        if (r.recorder.state === 'inactive') {
                            done();
                            return;
                        }
                        r.recorder.onstop = done;
                        try {
                            r.recorder.stop();
                        } catch (e) {
                            done();
                        }
                    })
            )
        );
    }

    // ---------------------------------------------------------------- finish

    async finishCall(cause, failed) {
        if (this.state === 'transcribing' || this.state === 'ending') return;
        const wasAnswered = this.answered;
        const durationSeconds = wasAnswered ? Math.round((Date.now() - this.startedAt) / 1000) : 0;
        this.state = 'ending';
        clearInterval(this.timer);
        const recordings = await this.stopRecording();
        this.teardown();

        if (!wasAnswered) {
            this.endCause = failed ? this.describeFailure(cause) : 'Call ended';
            this.state = 'failed';
            this.lastOutcome = { status: this.outcomeFor(cause), durationSeconds: 0 };
            return;
        }

        let transcript = '';
        let transcriptError;
        const coach = recordings.find((r) => r.speaker === 'Coach');
        const patient = recordings.find((r) => r.speaker === 'Patient');
        const mixed = recordings.find((r) => r.speaker === 'Mixed');
        if (this.consent && this.transcriptionAvailable && coach && patient && (coach.blob.size || patient.blob.size)) {
            this.state = 'transcribing';
            try {
                const results = await Promise.all([this.transcribe(coach), this.transcribe(patient)]);
                transcript = mergeSegments(results);
            } catch (e) {
                transcriptError = reduceError(e);
            }
        }
        let recording = null;
        if (this.consent && mixed && mixed.blob.size) {
            recording = {
                fileName: `Call with ${this.patientName || 'patient'} ${new Date().toISOString().slice(0, 16).replace('T', ' ')}.${extensionFor(mixed.blob.type)}`,
                mimeType: mixed.blob.type,
                base64: await blobToBase64(mixed.blob)
            };
        }
        this.state = 'done';
        this.dispatchEvent(
            new CustomEvent('callcomplete', {
                detail: {
                    status: 'Reached',
                    durationSeconds,
                    durationMinutes: Math.max(1, Math.round(durationSeconds / 60)),
                    transcript,
                    transcriptError,
                    consent: this.consent,
                    language: this.callLanguage === 'ar' ? 'Arabic (Egypt)' : 'English',
                    recording,
                    recordingUrl: null
                }
            })
        );
    }

    async transcribe(track) {
        if (!track.blob.size) return { speaker: track.speaker, segments: [] };
        const res = await fetch(this.config.transcribeEndpoint, {
            method: 'POST',
            headers: {
                'Content-Type': track.blob.type || 'audio/webm',
                'X-Care-Coach-Ticket': this.config.transcribeTicket,
                'X-Speaker': track.speaker,
                'X-Language': this.callLanguage
            },
            body: track.blob
        });
        const body = await res.json().catch(() => ({}));
        if (!res.ok) throw new Error(body.error || `Transcription failed (${res.status})`);
        return { speaker: track.speaker, segments: body.segments || [] };
    }

    // ---------------------------------------------------------------- live demo

    async startLiveCapture() {
        this.captureError = undefined;
        this.liveLines = [];
        this.insight = undefined;
        this.stopping = false;
        this.consent = true;
        try {
            this.micStream = await navigator.mediaDevices.getUserMedia({ audio: true });
        } catch (e) {
            this.captureError = 'Allow the microphone so this tablet can record the call.';
            return;
        }
        this.state = 'recording';
        this.startedAt = Date.now();
        this.elapsed = 0;
        this.timer = setInterval(() => {
            this.elapsed = Math.round((Date.now() - this.startedAt) / 1000);
        }, 1000);
        this.fullChunks = [];
        this.sliceStream = this.micStream;
        try {
            this.audioCtx = new AudioContext();
            const source = this.audioCtx.createMediaStreamSource(this.micStream);
            const dest = this.audioCtx.createMediaStreamDestination();
            source.connect(dest);
            this.sliceStream = dest.stream;
        } catch (e) {
            this.sliceStream = this.micStream;
        }
        const mimeType = MIME_CANDIDATES.find((t) => window.MediaRecorder.isTypeSupported && window.MediaRecorder.isTypeSupported(t)) || '';
        try {
            this.fullRecorder = new window.MediaRecorder(this.micStream, mimeType ? { mimeType } : undefined);
            this.fullRecorder.ondataavailable = (e) => {
                if (e.data && e.data.size) this.fullChunks.push(e.data);
            };
            this.fullRecorder.start();
        } catch (e) {
            this.captureError = 'This device cannot record audio.';
            this.stopMic();
            this.state = this.config && this.config.sipConfigured ? 'ready' : 'unavailable';
            return;
        }
        this.startHearing();
        this.keepAwake();
        this.captureLoop();
    }

    prepareOnDeviceTranscription() {
        if (typeof window.careCoachPrepareTranscriber !== 'function') return;
        this.modelStatus = 'Preparing Whisper on this tablet…';
        window.careCoachPrepareTranscriber((message) => {
            this.modelStatus = message;
        }).catch(() => {
            this.modelStatus = 'Whisper could not download. Live Egyptian Arabic recognition still runs while you record.';
        });
    }

    startHearing() {
        const SpeechRec = window.SpeechRecognition || window.webkitSpeechRecognition;
        if (!SpeechRec) return;
        const rec = new SpeechRec();
        rec.lang = this.callLanguage === 'en' ? 'en-US' : 'ar-EG';
        rec.continuous = true;
        rec.interimResults = true;
        rec.onresult = (event) => {
            let interim = '';
            for (let i = event.resultIndex; i < event.results.length; i += 1) {
                const text = (event.results[i][0].transcript || '').trim();
                if (!text) continue;
                if (event.results[i].isFinal) {
                    if (!this.whisperReady) this.addHeardLine(text, 'speech');
                } else {
                    interim += `${text} `;
                }
            }
            this.hearingText = interim.trim();
            if (this.hearingText) this.refreshInsight();
        };
        rec.onend = () => {
            if (this.state === 'recording' && !this.stopping) {
                try {
                    rec.start();
                } catch (e) {
                    // The recognizer can already be running.
                }
            }
        };
        try {
            rec.start();
            this.speechRec = rec;
        } catch (e) {
            this.speechRec = undefined;
        }
    }

    addHeardLine(text, source) {
        const clean = String(text || '').replace(/\s+/g, ' ').trim();
        if (!clean) return;
        if (source === 'whisper' && !this.whisperReady) {
            this.whisperReady = true;
            this.liveLines = this.liveLines.filter((line) => line.source !== 'speech');
        }
        const already = this.liveLines.some((line) => line.text === clean);
        if (already) return;
        this.liveLines = [
            ...this.liveLines,
            { key: `${source}-${Date.now()}-${this.liveLines.length}`, speaker: 'Heard', text: clean, who: 'line line_patient', source }
        ];
        this.hearingText = '';
        this.refreshInsight();
    }

    async captureLoop() {
        while (this.state === 'recording' && !this.stopping) {
            const slice = await this.recordSlice(SLICE_MS);
            if (!slice || !slice.size || this.stopping) {
                if (!slice) this.captureError = 'Live transcription is not available on this browser. The recording is still saved when you stop.';
                break;
            }
            try {
                const text = await this.transcribeSlice(slice);
                if (text) this.addHeardLine(text, 'whisper');
            } catch (e) {
                this.captureError = reduceError(e);
            }
        }
    }

    async transcribeSlice(blob) {
        if (typeof window.careCoachTranscribe === 'function') {
            return window.careCoachTranscribe(blob, this.callLanguage);
        }
        const result = await this.transcribe({ speaker: 'Heard', blob });
        return (result.segments || []).map((segment) => segment.text).join(' ').trim();
    }

    recordSlice(ms) {
        return new Promise((resolve) => {
            let rec;
            try {
                const mimeType = MIME_CANDIDATES.find((t) => window.MediaRecorder.isTypeSupported && window.MediaRecorder.isTypeSupported(t)) || '';
                rec = new window.MediaRecorder(this.sliceStream || this.micStream, mimeType ? { mimeType } : undefined);
            } catch (e) {
                resolve(null);
                return;
            }
            const chunks = [];
            rec.ondataavailable = (e) => {
                if (e.data && e.data.size) chunks.push(e.data);
            };
            rec.onstop = () => resolve(new Blob(chunks, { type: rec.mimeType || 'audio/webm' }));
            rec.start();
            const timer = setTimeout(() => {
                if (rec.state !== 'inactive') rec.stop();
            }, ms);
            this.sliceStop = () => {
                clearTimeout(timer);
                if (rec.state !== 'inactive') rec.stop();
            };
        });
    }

    async stopLiveCapture() {
        if (this.stopping) return;
        this.stopping = true;
        if (this.sliceStop) this.sliceStop();
        this.state = 'transcribing';
        const recording = await this.finishMicRecording();
        const transcript = this.liveLines.map((l) => `${l.speaker}: ${l.text}`).join('\n');
        this.emitComplete({ transcript, recording, recordingUrl: null });
    }

    finishMicRecording() {
        const rec = this.fullRecorder;
        this.fullRecorder = undefined;
        if (!rec) {
            this.stopMic();
            return Promise.resolve(null);
        }
        return new Promise((resolve) => {
            rec.onstop = async () => {
                const blob = new Blob(this.fullChunks, { type: rec.mimeType || 'audio/webm' });
                this.stopMic();
                if (!blob.size) {
                    resolve(null);
                    return;
                }
                resolve({
                    fileName: `Live call ${new Date().toISOString().slice(0, 16).replace('T', ' ')}.${extensionFor(blob.type)}`,
                    mimeType: blob.type,
                    base64: await blobToBase64(blob)
                });
            };
            if (rec.state !== 'inactive') rec.stop();
            else rec.onstop();
        });
    }

    stopMic() {
        clearInterval(this.timer);
        this.hearingText = '';
        if (this.speechRec) {
            try {
                this.speechRec.onend = null;
                this.speechRec.stop();
            } catch (e) {
                // Already stopped.
            }
            this.speechRec = undefined;
        }
        if (this.micStream) {
            this.micStream.getTracks().forEach((t) => t.stop());
            this.micStream = undefined;
        }
        if (this.wakeLock) {
            this.wakeLock.release().catch(() => {});
            this.wakeLock = undefined;
        }
    }

    playSample(event) {
        const sample = SAMPLES[event.currentTarget.dataset.sample] || SAMPLES.rash;
        this.clearSampleTimers();
        this.liveLines = [];
        this.insight = undefined;
        this.captureError = undefined;
        this.consent = true;
        this.callLanguage = 'ar';
        this.state = 'sample';
        this.startedAt = Date.now();
        this.elapsed = 0;
        clearInterval(this.timer);
        this.timer = setInterval(() => {
            this.elapsed = Math.round((Date.now() - this.startedAt) / 1000);
        }, 1000);
        const audio = this.template.querySelector('audio.sample');
        if (audio) {
            audio.src = sampleSrc(sample.file);
            const played = audio.play();
            if (played && played.catch) played.catch(() => {});
            audio.onended = () => this.finishSample(sample);
        }
        this.sampleTimers = sample.lines.map((line, index) =>
            setTimeout(() => {
                if (this.state !== 'sample') return;
                this.liveLines = [...this.liveLines, { key: `s-${index}`, speaker: line.speaker, text: line.text, who: line.speaker === 'Coach' ? 'line line_coach' : 'line line_patient' }];
                this.refreshInsight();
            }, line.at)
        );
        this.sampleFile = sample.file;
        this.sampleDef = sample;
    }

    finishSample(sample) {
        if (this.state !== 'sample') return;
        this.clearSampleTimers();
        clearInterval(this.timer);
        const def = sample || this.sampleDef;
        const lines = (def && def.lines) || [];
        const transcript = lines.map((l) => `${l.speaker}: ${l.text}`).join('\n');
        const file = (def && def.file) || this.sampleFile;
        this.emitComplete({
            transcript,
            recording: null,
            recordingUrl: file ? `https://www.salesforceoffline.com/media/calls/${file}` : null
        });
    }

    stopSample() {
        const audio = this.template.querySelector('audio.sample');
        if (audio) {
            audio.onended = null;
            audio.pause();
        }
        this.finishSample(this.sampleDef);
    }

    clearSampleTimers() {
        (this.sampleTimers || []).forEach((id) => clearTimeout(id));
        this.sampleTimers = [];
    }

    async refreshInsight() {
        const spoken = this.liveLines.map((line) => `Heard: ${line.text}`);
        if (this.hearingText) spoken.push(`Heard: ${this.hearingText}`);
        const transcript = spoken.join('\n');
        if (!transcript) return;
        this.insightPending = true;
        try {
            this.insight = await previewInsight({ transcript });
        } catch (e) {
            this.captureError = reduceError(e);
        } finally {
            this.insightPending = false;
        }
    }

    emitComplete({ transcript, recording, recordingUrl }) {
        const durationSeconds = this.startedAt ? Math.round((Date.now() - this.startedAt) / 1000) : this.elapsed;
        clearInterval(this.timer);
        this.state = 'done';
        this.dispatchEvent(
            new CustomEvent('callcomplete', {
                detail: {
                    status: 'Reached',
                    durationSeconds,
                    durationMinutes: Math.max(1, Math.round(durationSeconds / 60)),
                    transcript: transcript || '',
                    transcriptError: this.captureError && !transcript ? this.captureError : undefined,
                    consent: true,
                    language: this.callLanguage === 'ar' ? 'Arabic (Egypt)' : 'English',
                    recording,
                    recordingUrl: recordingUrl || null
                }
            })
        );
    }

    describeFailure(cause) {
        switch (cause) {
            case 'Busy':
                return 'The line is busy';
            case 'Unavailable':
            case 'Not Found':
                return 'The number is unavailable';
            case 'No Answer':
            case 'Request Timeout':
                return 'No answer';
            case 'Rejected':
                return 'The call was declined';
            case 'Authentication Error':
                return 'The phone service rejected the SIP credentials';
            case 'Canceled':
                return 'Call cancelled';
            case 'User Denied Media Access':
                return 'Microphone access was blocked';
            default:
                return cause ? `Call failed (${cause})` : 'Call failed';
        }
    }

    outcomeFor(cause) {
        return cause === 'Unavailable' || cause === 'Not Found' ? 'Unreached (Switched Off)' : 'Unreached (No Answer)';
    }

    get canLogUnreached() {
        return this.isFailed && this.lastOutcome;
    }

    logUnreached() {
        this.dispatchEvent(
            new CustomEvent('callcomplete', {
                detail: { status: this.lastOutcome.status, durationSeconds: 0, durationMinutes: null, transcript: '', consent: false, recording: null }
            })
        );
    }

    stopCoaching() {
        if (this.state === 'sample') this.stopSample();
        else this.stopLiveCapture();
    }

    teardown() {
        this.stopping = true;
        if (this.sliceStop) this.sliceStop();
        this.clearSampleTimers();
        const sample = this.template && this.template.querySelector('audio.sample');
        if (sample) {
            sample.onended = null;
            sample.pause();
        }
        if (this.fullRecorder && this.fullRecorder.state !== 'inactive') {
            try {
                this.fullRecorder.stop();
            } catch (e) {
                // Already stopped.
            }
        }
        if (this.micStream) {
            this.micStream.getTracks().forEach((t) => t.stop());
            this.micStream = undefined;
        }
        clearInterval(this.timer);
        if (this.wakeLock) {
            this.wakeLock.release().catch(() => {});
            this.wakeLock = undefined;
        }
        if (this.localStream) this.localStream.getTracks().forEach((t) => t.stop());
        this.localStream = undefined;
        this.remoteStream = undefined;
        if (this.audioCtx) {
            this.audioCtx.close().catch(() => {});
            this.audioCtx = undefined;
        }
        if (this.ua) {
            try {
                this.ua.stop();
            } catch (e) {
                // Already stopped.
            }
            this.ua = undefined;
        }
        this.session = undefined;
        this.muted = false;
        this.held = false;
        this.showKeypad = false;
    }
}