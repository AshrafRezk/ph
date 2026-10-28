import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getStoreCheck from '@salesforce/apex/FieldVisitWorkflowController.getStoreCheck';
import saveStoreCheck from '@salesforce/apex/FieldVisitWorkflowController.saveStoreCheck';
import saveStoreCheckPhoto from '@salesforce/apex/FieldVisitWorkflowController.saveStoreCheckPhoto';
import deleteStoreCheckPhoto from '@salesforce/apex/FieldVisitWorkflowController.deleteStoreCheckPhoto';

let lineSeq = 0;
const MAX_PHOTO_EDGE = 1600;

export default class VisitStoreCheckPanel extends LightningElement {
    @api visitId;
    @api disabled = false;

    isLoading = true;
    isUploadingPhoto = false;
    errorMessage;
    notes = '';
    productOptions = [];
    @track lines = [];
    @track photos = [];
    draftProductId = '';
    draftFacings = 1;
    draftAvailable = true;

    connectedCallback() {
        this.load();
    }

    renderedCallback() {
        const camera = this.template.querySelector('input[data-role="camera"]');
        if (camera && camera.getAttribute('capture') !== 'environment') {
            camera.setAttribute('capture', 'environment');
        }
    }

    get hasLines() {
        return (this.lines || []).length > 0;
    }

    get hasPhotos() {
        return (this.photos || []).length > 0;
    }

    get addDisabled() {
        return this.disabled || !this.draftProductId;
    }

    get photoDisabled() {
        return this.disabled || this.isUploadingPhoto;
    }

    async load() {
        if (!this.visitId) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const payload = await getStoreCheck({ visitId: this.visitId });
            this.applyPayload(payload);
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load store check.';
        } finally {
            this.isLoading = false;
        }
    }

    applyPayload(payload) {
        this.productOptions = (payload?.productOptions || []).map((row) => ({
            label: row.label || row.productName,
            value: row.value || row.productId
        }));
        this.notes = payload?.notes || '';
        this.lines = (payload?.lines || []).map((line) => this.toLine(line));
        this.photos = (payload?.photos || []).map((photo, index) => ({
            key: photo.contentDocumentId || `photo-${index}`,
            contentDocumentId: photo.contentDocumentId,
            contentVersionId: photo.contentVersionId,
            title: photo.title || 'Store check photo',
            previewUrl: photo.previewUrl
        }));
    }

    toLine(line) {
        lineSeq += 1;
        const productName =
            line.productName ||
            this.productOptions.find((option) => option.value === line.productId)?.label ||
            'Product';
        const available = line.available !== false;
        return {
            key: line.id || `new-${lineSeq}`,
            productId: line.productId,
            productName,
            available,
            facings: line.facings || 0,
            summary: `${available ? 'Available' : 'Not available'} · ${line.facings || 0} facings`
        };
    }

    handleDraftProduct(event) {
        this.draftProductId = event.detail.value;
    }
    handleDraftFacings(event) {
        this.draftFacings = Number(event.detail.value || 0);
    }
    handleDraftAvailable(event) {
        this.draftAvailable = event.detail.checked === true;
    }
    handleNotes(event) {
        this.notes = event.detail.value;
    }

    openCamera() {
        this.template.querySelector('input[data-role="camera"]')?.click();
    }

    openLibrary() {
        this.template.querySelector('input[data-role="library"]')?.click();
    }

    async handlePhotoSelected(event) {
        const file = event.target.files?.[0];
        event.target.value = '';
        if (!file || this.disabled) {
            return;
        }
        this.isUploadingPhoto = true;
        this.errorMessage = undefined;
        try {
            const prepared = await preparePhoto(file);
            const payload = await saveStoreCheckPhoto({
                visitId: this.visitId,
                fileName: prepared.fileName,
                base64Data: prepared.base64Data
            });
            this.applyPayload(payload);
            this.dispatchEvent(new ShowToastEvent({ title: 'Photo saved', variant: 'success' }));
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to save photo.';
        } finally {
            this.isUploadingPhoto = false;
        }
    }

    async handleRemovePhoto(event) {
        const contentDocumentId = event.currentTarget.dataset.id;
        if (!contentDocumentId || this.disabled) {
            return;
        }
        this.isUploadingPhoto = true;
        try {
            const payload = await deleteStoreCheckPhoto({
                visitId: this.visitId,
                contentDocumentId
            });
            this.applyPayload(payload);
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to remove photo.';
        } finally {
            this.isUploadingPhoto = false;
        }
    }

    handleAddLine() {
        const option = this.productOptions.find((row) => row.value === this.draftProductId);
        this.lines = [
            ...this.lines,
            this.toLine({
                productId: this.draftProductId,
                productName: option?.label,
                available: this.draftAvailable,
                facings: this.draftFacings
            })
        ];
        this.draftProductId = '';
    }

    handleRemove(event) {
        const key = event.currentTarget.dataset.key;
        this.lines = this.lines.filter((line) => line.key !== key);
    }

    async handleSave() {
        try {
            const payload = await saveStoreCheck({
                visitId: this.visitId,
                notes: this.notes,
                lines: this.lines.map((line) => ({
                    productId: line.productId,
                    available: line.available,
                    facings: line.facings
                }))
            });
            this.applyPayload(payload);
            this.dispatchEvent(new ShowToastEvent({ title: 'Store check saved', variant: 'success' }));
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to save store check',
                    message: error?.body?.message || error?.message,
                    variant: 'error'
                })
            );
        }
    }
}

async function preparePhoto(file) {
    const compressed = await compressImage(file);
    const blob = compressed || file;
    const base64Data = await blobToBase64(blob);
    const fileName = compressed ? toJpegName(file.name) : file.name || 'store-check.jpg';
    return { base64Data, fileName };
}

function toJpegName(name) {
    const base = String(name || 'store-check').replace(/\.[^.]+$/, '');
    return `${base || 'store-check'}.jpg`;
}

function blobToBase64(blob) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => {
            const result = String(reader.result || '');
            const comma = result.indexOf(',');
            resolve(comma >= 0 ? result.slice(comma + 1) : result);
        };
        reader.onerror = () => reject(reader.error || new Error('Could not read the photo.'));
        reader.readAsDataURL(blob);
    });
}

function compressImage(file) {
    return new Promise((resolve) => {
        const url = URL.createObjectURL(file);
        const image = new Image();
        image.onload = () => {
            URL.revokeObjectURL(url);
            const scale = Math.min(1, MAX_PHOTO_EDGE / Math.max(image.width, image.height));
            const width = Math.max(1, Math.round(image.width * scale));
            const height = Math.max(1, Math.round(image.height * scale));
            const canvas = document.createElement('canvas');
            canvas.width = width;
            canvas.height = height;
            const context = canvas.getContext('2d');
            if (!context) {
                resolve(null);
                return;
            }
            context.drawImage(image, 0, 0, width, height);
            canvas.toBlob(
                (blob) => resolve(blob),
                'image/jpeg',
                0.72
            );
        };
        image.onerror = () => {
            URL.revokeObjectURL(url);
            resolve(null);
        };
        image.src = url;
    });
}
