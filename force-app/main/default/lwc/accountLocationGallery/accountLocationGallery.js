import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LEAFLET from '@salesforce/resourceUrl/leaflet';
import getLocationMedia from '@salesforce/apex/AccountMapsPlacesService.getLocationMedia';
import enrichAccount from '@salesforce/apex/AccountMapsPlacesService.enrichAccount';
import {
    ensureLeaflet,
    addNeighbourMapTileLayer,
    createAccountCenterPinIcon,
    styleNeighbourMapPin
} from 'c/plannerMapPins';

const MAP_ZOOM = 16;

export default class AccountLocationGallery extends LightningElement {
    @api recordId;

    isBusy = false;
    errorMessage;
    wiredMedia;
    mapInstance;
    mapMarker;
    mapRenderToken = 0;
    lastPlottedKey;

    @wire(getLocationMedia, { accountId: '$recordId' })
    wiredGetMedia(result) {
        this.wiredMedia = result;
        if (result.error) {
            this.errorMessage = this.reduceError(result.error);
            this.destroyMap();
            return;
        }
        this.errorMessage = undefined;
        this.scheduleMapRender();
    }

    renderedCallback() {
        if (this.hasMap) {
            this.scheduleMapRender();
        }
    }

    disconnectedCallback() {
        this.destroyMap();
    }

    get media() {
        return this.wiredMedia?.data;
    }

    get isLoading() {
        return !this.wiredMedia || (this.wiredMedia.data === undefined && !this.wiredMedia.error);
    }

    get mapsPhone() {
        return this.media?.mapsPhone;
    }

    get mapsPhoneHref() {
        return this.mapsPhone ? `tel:${this.mapsPhone}` : null;
    }

    get addressLine() {
        return this.media?.addressLine;
    }

    get message() {
        return this.media?.message;
    }

    get streetViewUrl() {
        return this.media?.streetViewUrl;
    }

    get photoUrls() {
        return this.media?.photoUrls || [];
    }

    get mapCenter() {
        const lat = Number(this.media?.latitude);
        const lng = Number(this.media?.longitude);
        if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
            return null;
        }
        if (Math.abs(lat) > 90 || Math.abs(lng) > 180) {
            return null;
        }
        return { lat, lng };
    }

    get hasMap() {
        return this.mapCenter != null;
    }

    get showGeoEmpty() {
        return !this.isLoading && !this.hasMap;
    }

    scheduleMapRender() {
        if (!this.hasMap) {
            this.destroyMap();
            return;
        }
        window.requestAnimationFrame(() => {
            window.requestAnimationFrame(() => {
                this.renderMap();
            });
        });
    }

    async renderMap() {
        const center = this.mapCenter;
        if (!center) {
            return;
        }

        const plotKey = `${center.lat},${center.lng}`;
        const container = this.template.querySelector('.map-container');
        if (!container) {
            return;
        }
        if (this.mapInstance && this.lastPlottedKey === plotKey) {
            const existingCanvas = container.querySelector('.map-canvas');
            if (existingCanvas && this.mapInstance.getContainer() === existingCanvas) {
                this.mapInstance.invalidateSize();
                return;
            }
        }

        const renderToken = ++this.mapRenderToken;
        await ensureLeaflet(this, LEAFLET);
        if (renderToken !== this.mapRenderToken) {
            return;
        }

        this.destroyMap();
        container.innerHTML = '';
        const mapDiv = document.createElement('div');
        mapDiv.className = 'map-canvas';
        container.appendChild(mapDiv);

        const leaflet = window.L;
        this.mapInstance = leaflet.map(mapDiv, {
            zoomControl: true,
            attributionControl: false,
            center: [center.lat, center.lng],
            zoom: MAP_ZOOM,
            minZoom: 6,
            maxZoom: 19,
            worldCopyJump: false
        });
        addNeighbourMapTileLayer(this.mapInstance, leaflet);

        const marker = leaflet.marker([center.lat, center.lng], {
            icon: createAccountCenterPinIcon(leaflet),
            zIndexOffset: 600
        });
        marker.addTo(this.mapInstance);
        styleNeighbourMapPin(marker);
        const popupBits = [
            `<strong>${this.escapeHtml(this.media?.accountName || 'Account')}</strong>`
        ];
        if (this.addressLine) {
            popupBits.push(this.escapeHtml(this.addressLine));
        }
        marker.bindPopup(popupBits.join('<br/>'));
        this.mapMarker = marker;
        this.lastPlottedKey = plotKey;

        this.mapInstance.invalidateSize();
        window.setTimeout(() => {
            if (this.mapInstance) {
                this.mapInstance.invalidateSize();
                this.mapInstance.setView([center.lat, center.lng], MAP_ZOOM, { animate: false });
            }
        }, 120);
    }

    destroyMap() {
        this.lastPlottedKey = undefined;
        this.mapMarker = null;
        if (this.mapInstance) {
            this.mapInstance.remove();
            this.mapInstance = null;
        }
    }

    async handleEnrich() {
        if (!this.recordId || this.isBusy) {
            return;
        }
        this.isBusy = true;
        try {
            const result = await enrichAccount({ accountId: this.recordId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: result?.status || 'Maps enrichment',
                    message: result?.phone
                        ? `Maps phone: ${result.phone}`
                        : result?.message || 'No phone found',
                    variant: result?.phone ? 'success' : 'info'
                })
            );
            await refreshApex(this.wiredMedia);
        } catch (e) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Maps enrichment failed',
                    message: this.reduceError(e),
                    variant: 'error'
                })
            );
        } finally {
            this.isBusy = false;
        }
    }

    escapeHtml(value) {
        return String(value || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    reduceError(error) {
        if (!error) {
            return 'Unknown error';
        }
        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (typeof error.body?.message === 'string') {
            return error.body.message;
        }
        return error.message || 'Unknown error';
    }
}