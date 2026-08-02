import { LightningElement } from 'lwc';
import upsertSnapshot from '@salesforce/apex/RepLocationService.upsertSnapshot';
import setSharingEnabled from '@salesforce/apex/RepLocationService.setSharingEnabled';
import { watchPosition, clearWatch, haversineKm } from 'c/plannerMapUtils';

const UPLOAD_INTERVAL_MS = 90000;
const MIN_MOVE_KM = 0.1;

export default class RepLocationPublisher extends LightningElement {
    lastUploadedAt = 0;
    lastUploadedPosition;
    permissionDenied = false;
    visibilityHandler;
    watchId;

    connectedCallback() {
        this.visibilityHandler = () => {
            if (document.hidden) {
                this.pauseTracking();
            } else if (!this.permissionDenied) {
                this.startTracking();
            }
        };
        document.addEventListener('visibilitychange', this.visibilityHandler);
        this.startTracking();
    }

    disconnectedCallback() {
        document.removeEventListener('visibilitychange', this.visibilityHandler);
        this.pauseTracking();
    }

    startTracking() {
        if (this.permissionDenied || document.hidden || this.watchId != null) {
            return;
        }
        this.watchId = watchPosition(
            (position) => this.handlePositionUpdate(position),
            (error) => this.handlePositionError(error)
        );
    }

    pauseTracking() {
        clearWatch(this.watchId);
        this.watchId = null;
    }

    handlePositionError(error) {
        const message = error?.message || '';
        if (message.toLowerCase().includes('denied')) {
            this.permissionDenied = true;
            this.pauseTracking();
            setSharingEnabled({ isSharing: false }).catch(() => {
                // Best effort when permission is denied.
            });
        }
    }

    async handlePositionUpdate(position) {
        if (!position || this.permissionDenied) {
            return;
        }
        const now = Date.now();
        const movedEnough =
            !this.lastUploadedPosition ||
            haversineKm(
                this.lastUploadedPosition.latitude,
                this.lastUploadedPosition.longitude,
                position.latitude,
                position.longitude
            ) >= MIN_MOVE_KM;
        const intervalElapsed = now - this.lastUploadedAt >= UPLOAD_INTERVAL_MS;

        if (!movedEnough && !intervalElapsed) {
            return;
        }

        try {
            await upsertSnapshot({
                latitude: position.latitude,
                longitude: position.longitude,
                accuracyMeters: position.accuracy
            });
            this.lastUploadedAt = now;
            this.lastUploadedPosition = {
                latitude: position.latitude,
                longitude: position.longitude
            };
        } catch (error) {
            // eslint-disable-next-line no-console
            console.warn('Rep location upload failed', error);
        }
    }
}
