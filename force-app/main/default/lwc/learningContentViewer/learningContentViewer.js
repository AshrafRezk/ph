import { LightningElement, api } from 'lwc';

// BRD §5.6: the next video stays locked until this share of the current one is watched.
const VIDEO_UNLOCK_PERCENT = 85;

const YT_HOSTS = ['youtube.com', 'youtube-nocookie.com'];

export default class LearningContentViewer extends LightningElement {
    @api materialType;
    @api materialUrl;
    @api description;
    @api title;
    @api initialWatchPercent = 0;

    maxWatchPercent = 0;
    elapsedSeconds = 0;
    _lastTickAt;
    _pollTimer;
    _heartbeatTimer;
    _messageHandler;
    _ytReady = false;
    _videoBound = false;
    _playerId;
    _ytDuration = 0;

    connectedCallback() {
        this.maxWatchPercent = Number(this.initialWatchPercent) || 0;
        this._playerId = `yt-${Math.random().toString(36).slice(2, 10)}`;
        this._messageHandler = (event) => this.handleYouTubeMessage(event);
        window.addEventListener('message', this._messageHandler);
        this._lastTickAt = Date.now();
        this._heartbeatTimer = window.setInterval(() => this.flushHeartbeat(), 15000);
        if (this.maxWatchPercent >= VIDEO_UNLOCK_PERCENT) {
            this.dispatchProgress(true, 0);
        }
    }

    renderedCallback() {
        this.bindHtml5Video();
        if (this.isYouTube && !this._ytReady) {
            const iframe = this.template.querySelector('iframe[data-yt]');
            if (iframe?.contentWindow) {
                this._ytReady = true;
                this.postToYouTube(iframe, { event: 'listening', id: this._playerId });
                this._pollTimer = window.setInterval(() => this.pollYouTube(iframe), 1000);
            }
        }
    }

    disconnectedCallback() {
        this.flushHeartbeat(this.maxWatchPercent >= VIDEO_UNLOCK_PERCENT);
        window.removeEventListener('message', this._messageHandler);
        if (this._pollTimer) {
            window.clearInterval(this._pollTimer);
        }
        if (this._heartbeatTimer) {
            window.clearInterval(this._heartbeatTimer);
        }
        const video = this.template.querySelector('video');
        if (video && this._onTimeUpdate) {
            video.removeEventListener('timeupdate', this._onTimeUpdate);
            video.removeEventListener('ended', this._onEnded);
        }
    }

    bindHtml5Video() {
        if (this._videoBound || !this.isHtml5Video) {
            return;
        }
        const video = this.template.querySelector('video');
        if (!video) {
            return;
        }
        this._videoBound = true;
        this._onTimeUpdate = (event) => this.handleVideoTimeUpdate(event);
        this._onEnded = (event) => this.handleVideoEnded(event);
        video.addEventListener('timeupdate', this._onTimeUpdate);
        video.addEventListener('ended', this._onEnded);
    }

    get isYouTube() {
        return !!this.youtubeVideoId;
    }

    get youtubeVideoId() {
        const url = this.materialUrl || '';
        const watchMatch = url.match(/[?&]v=([^&]+)/);
        if (watchMatch) {
            return watchMatch[1];
        }
        const shortMatch = url.match(/youtu\.be\/([^?&]+)/);
        if (shortMatch) {
            return shortMatch[1];
        }
        const embedMatch = url.match(/youtube\.com\/embed\/([^?&]+)/);
        if (embedMatch) {
            return embedMatch[1];
        }
        return null;
    }

    get youtubeEmbedUrl() {
        if (!this.youtubeVideoId) {
            return null;
        }
        const origin = encodeURIComponent(window.location.origin);
        return `https://www.youtube.com/embed/${this.youtubeVideoId}?enablejsapi=1&origin=${origin}&rel=0`;
    }

    get hasUrl() {
        return !!this.materialUrl;
    }

    get hasDescription() {
        return !!(this.description && String(this.description).trim());
    }

    get showEmptyState() {
        return !this.hasUrl && !this.hasDescription && !this.isPdf;
    }

    get isPdf() {
        if (this.materialType === 'PDF') {
            return true;
        }
        if (!this.materialUrl) {
            return false;
        }
        return this.materialUrl.toLowerCase().includes('.pdf');
    }

    get isHtml5Video() {
        if (this.isYouTube || this.isPdf || !this.materialUrl) {
            return false;
        }
        if (this.materialType === 'Video') {
            return true;
        }
        const url = (this.materialUrl || '').toLowerCase();
        return (
            url.includes('.mp4') ||
            url.includes('.webm') ||
            url.includes('.mov') ||
            url.includes('contentdownloadurl') ||
            url.includes('/sfc/dist/version/download') ||
            url.includes('file.force.com')
        );
    }

    get showExternalLink() {
        return this.hasUrl && !this.isYouTube && !this.isHtml5Video && !this.isPdf;
    }

    get openLabel() {
        if (this.isPdf) {
            return 'Open PDF';
        }
        if (this.materialType === 'Video') {
            return 'Open video';
        }
        return 'Open content';
    }

    get watchLabel() {
        const pct = Math.round(this.maxWatchPercent);
        if (pct >= VIDEO_UNLOCK_PERCENT) {
            return `${pct}% watched · Next unlocked`;
        }
        return `${pct}% watched · watch ${VIDEO_UNLOCK_PERCENT}% to unlock Next`;
    }

    get showWatchProgress() {
        return this.isYouTube || this.isHtml5Video;
    }

    handleVideoTimeUpdate(event) {
        const video = event.target;
        if (!video || !video.duration || video.duration <= 0) {
            this.accumulateElapsed();
            return;
        }
        const pct = (video.currentTime / video.duration) * 100;
        this.updateWatchPercent(pct);
        this.accumulateElapsed();
    }

    handleVideoEnded() {
        this.updateWatchPercent(100);
        this.accumulateElapsed();
        this.flushHeartbeat(true);
    }

    pollYouTube(iframe) {
        if (!iframe?.contentWindow) {
            return;
        }
        this.postToYouTube(iframe, {
            event: 'command',
            func: 'getCurrentTime',
            args: [],
            id: this._playerId
        });
        this.postToYouTube(iframe, {
            event: 'command',
            func: 'getDuration',
            args: [],
            id: this._playerId
        });
        this.accumulateElapsed();
    }

    isYouTubeOrigin(origin) {
        const value = origin || '';
        return YT_HOSTS.some((host) => value.indexOf(host) !== -1);
    }

    handleYouTubeMessage(event) {
        if (!this.isYouTubeOrigin(event?.origin)) {
            return;
        }
        let data = event.data;
        if (typeof data === 'string') {
            try {
                data = JSON.parse(data);
            } catch (e) {
                return;
            }
        }
        if (!data || typeof data !== 'object') {
            return;
        }

        if (data.event === 'onReady' || data.event === 'initialDelivery') {
            const iframe = this.template.querySelector('iframe[data-yt]');
            if (iframe) {
                this.postToYouTube(iframe, {
                    event: 'command',
                    func: 'addEventListener',
                    args: ['onStateChange'],
                    id: this._playerId
                });
            }
        }

        const stateFromEvent =
            data.event === 'onStateChange'
                ? typeof data.info === 'number'
                    ? data.info
                    : data.info?.playerState
                : null;
        if (stateFromEvent === 0) {
            this.updateWatchPercent(100);
            this.flushHeartbeat(true);
            return;
        }

        const info = data.info;
        if (info && typeof info === 'object') {
            if (typeof info.duration === 'number' && info.duration > 0) {
                this._ytDuration = info.duration;
            }
            if (typeof info.currentTime === 'number') {
                const duration =
                    typeof info.duration === 'number' && info.duration > 0
                        ? info.duration
                        : this._ytDuration;
                if (duration > 0) {
                    this.updateWatchPercent((info.currentTime / duration) * 100);
                }
            }
            if (info.playerState === 0) {
                this.updateWatchPercent(100);
                this.flushHeartbeat(true);
            }
        }
    }

    postToYouTube(iframe, payload) {
        try {
            iframe.contentWindow.postMessage(JSON.stringify(payload), '*');
        } catch (e) {
            // Cross-frame messaging can fail before iframe is ready.
        }
    }

    updateWatchPercent(pct) {
        const next = Math.min(100, Math.max(0, Number(pct) || 0));
        if (next > this.maxWatchPercent) {
            this.maxWatchPercent = next;
            this.dispatchProgress(next >= VIDEO_UNLOCK_PERCENT);
        }
    }

    accumulateElapsed() {
        const now = Date.now();
        if (this._lastTickAt) {
            const delta = (now - this._lastTickAt) / 1000;
            if (delta > 0 && delta < 30) {
                this.elapsedSeconds += delta;
            }
        }
        this._lastTickAt = now;
    }

    flushHeartbeat(forceComplete = false) {
        this.accumulateElapsed();
        const seconds = Math.floor(this.elapsedSeconds);
        if (seconds <= 0 && !forceComplete) {
            return;
        }
        this.elapsedSeconds = this.elapsedSeconds - seconds;
        this.dispatchProgress(forceComplete, seconds);
    }

    dispatchProgress(forceComplete, secondsSpent = 0) {
        this.dispatchEvent(
            new CustomEvent('watchprogress', {
                bubbles: true,
                composed: true,
                detail: {
                    watchPercent: this.maxWatchPercent,
                    secondsSpent,
                    unlocked: this.maxWatchPercent >= VIDEO_UNLOCK_PERCENT || forceComplete === true,
                    forceComplete: forceComplete === true
                }
            })
        );
    }
}