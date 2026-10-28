import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getStoreCheckPhotos from '@salesforce/apex/VisitPharmacyController.getStoreCheckPhotos';
import tagStoreCheckPhotos from '@salesforce/apex/VisitPharmacyController.tagStoreCheckPhotos';
import deleteStoreCheckPhoto from '@salesforce/apex/VisitPharmacyController.deleteStoreCheckPhoto';

export default class VisitStoreCheckGallery extends LightningElement {
    @api visitId;
    @api disabled = false;

    photos = [];
    isLoading = false;
    isBusy = false;

    connectedCallback() {
        this.refreshPhotos();
    }

    get hasPhotos() {
        return (this.photos || []).length > 0;
    }

    get uploadDisabled() {
        return this.disabled || this.isBusy || !this.visitId;
    }

    async refreshPhotos() {
        if (!this.visitId) {
            return;
        }
        this.isLoading = true;
        try {
            this.photos = await getStoreCheckPhotos({ visitId: this.visitId });
        } catch (error) {
            this.showToast('Store Check', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleUploadFinished(event) {
        const uploaded = event.detail.files || [];
        const documentIds = uploaded
            .map((file) => file.documentId)
            .filter(Boolean);
        if (!documentIds.length) {
            return;
        }
        this.isBusy = true;
        try {
            this.photos = await tagStoreCheckPhotos({
                visitId: this.visitId,
                contentDocumentIds: documentIds
            });
            this.showToast('Store Check', 'Photo saved to this visit.', 'success');
        } catch (error) {
            this.showToast('Store Check', this.reduceError(error), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    async handleDelete(event) {
        const contentDocumentId = event.currentTarget.dataset.documentId;
        if (!contentDocumentId || this.disabled) {
            return;
        }
        this.isBusy = true;
        try {
            this.photos = await deleteStoreCheckPhoto({
                visitId: this.visitId,
                contentDocumentId
            });
            this.showToast('Store Check', 'Photo removed.', 'success');
        } catch (error) {
            this.showToast('Store Check', this.reduceError(error), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}