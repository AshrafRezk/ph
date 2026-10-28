import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getVisitConsentContext from '@salesforce/apex/VisitConsentController.getVisitConsentContext';
import captureVisitConsent from '@salesforce/apex/VisitConsentController.captureVisitConsent';

function formatDateTime(value) {
    if (!value) {
        return '—';
    }
    return new Date(value).toLocaleString([], {
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
    });
}

export default class VisitConsentModal extends LightningElement {
    @api visitId;

    context;
    isLoading = true;
    isSubmitting = false;
    errorMessage;
    selectedChannel;
    selectedConsentType;
    selectedStatus = 'Granted';
    notes = '';
    hasSignature = false;
    drawing = false;
    canvas;
    ctx;

    connectedCallback() {
        this.loadContext();
    }

    renderedCallback() {
        if (this.showCaptureForm) {
            this.bindCanvas();
        }
    }

    get visitName() {
        return this.context?.visitName || '—';
    }

    get accountName() {
        return this.context?.accountName || '—';
    }

    get isLocked() {
        return this.context?.isLocked === true;
    }

    get channelOptions() {
        return this.context?.channelOptions || [];
    }

    get consentTypeOptions() {
        return this.context?.consentTypeOptions || [];
    }

    get statusOptions() {
        return this.context?.statusOptions || [];
    }

    get existingConsents() {
        return (this.context?.existingConsents || []).map((row) => ({
            ...row,
            capturedLabel: formatDateTime(row.capturedAt)
        }));
    }

    get hasExistingConsents() {
        return this.existingConsents.length > 0;
    }

    get showCaptureForm() {
        return !this.isLoading && !this.isLocked && !this.errorMessage;
    }

    get submitDisabled() {
        return (
            this.isLoading ||
            this.isSubmitting ||
            this.isLocked ||
            !this.selectedChannel ||
            !this.selectedConsentType ||
            !this.selectedStatus ||
            (this.selectedStatus === 'Granted' && !this.hasSignature)
        );
    }

    get signatureStateLabel() {
        return this.hasSignature ? 'Signature captured' : 'Sign in the box above';
    }

    async loadContext() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            if (!this.visitId) {
                throw { body: { message: 'Visit Id is required.' } };
            }
            const context = await getVisitConsentContext({ visitId: this.visitId });
            this.context = context;
            this.selectedChannel = this.selectedChannel || context?.channelOptions?.[0]?.value;
            this.selectedConsentType = this.selectedConsentType || context?.consentTypeOptions?.[0]?.value;
            this.selectedStatus = this.selectedStatus || context?.statusOptions?.[0]?.value || 'Granted';
        } catch (error) {
            this.context = undefined;
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load consent form.';
        } finally {
            this.isLoading = false;
        }
    }

    bindCanvas() {
        const wrap = this.template.querySelector('.signature-pad-wrap');
        if (!wrap) {
            return;
        }
        if (this.canvas && wrap.contains(this.canvas)) {
            return;
        }
        wrap.replaceChildren();
        const canvas = document.createElement('canvas');
        canvas.className = 'signature-pad';
        wrap.appendChild(canvas);
        this.canvas = canvas;
        const ratio = window.devicePixelRatio || 1;
        const width = wrap.clientWidth || 360;
        const height = 140;
        canvas.width = width * ratio;
        canvas.height = height * ratio;
        canvas.style.width = `${width}px`;
        canvas.style.height = `${height}px`;
        this.ctx = canvas.getContext('2d');
        this.ctx.scale(ratio, ratio);
        this.ctx.strokeStyle = '#032d60';
        this.ctx.lineWidth = 2;
        this.ctx.lineCap = 'round';
        canvas.addEventListener('pointerdown', (event) => this.startDraw(event));
        canvas.addEventListener('pointermove', (event) => this.moveDraw(event));
        canvas.addEventListener('pointerup', () => this.endDraw());
        canvas.addEventListener('pointerleave', () => this.endDraw());
    }

    pointFromEvent(event) {
        const rect = this.canvas.getBoundingClientRect();
        return {
            x: event.clientX - rect.left,
            y: event.clientY - rect.top
        };
    }

    startDraw(event) {
        if (!this.ctx) {
            return;
        }
        this.drawing = true;
        const point = this.pointFromEvent(event);
        this.ctx.beginPath();
        this.ctx.moveTo(point.x, point.y);
        this.canvas.setPointerCapture?.(event.pointerId);
    }

    moveDraw(event) {
        if (!this.drawing || !this.ctx) {
            return;
        }
        const point = this.pointFromEvent(event);
        this.ctx.lineTo(point.x, point.y);
        this.ctx.stroke();
        this.hasSignature = true;
    }

    endDraw() {
        this.drawing = false;
    }

    handleClearSignature() {
        if (!this.ctx || !this.canvas) {
            this.hasSignature = false;
            return;
        }
        this.ctx.save();
        this.ctx.setTransform(1, 0, 0, 1, 0, 0);
        this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
        this.ctx.restore();
        this.hasSignature = false;
    }

    handleChannelChange(event) {
        this.selectedChannel = event.detail.value;
    }

    handleConsentTypeChange(event) {
        this.selectedConsentType = event.detail.value;
    }

    handleStatusChange(event) {
        this.selectedStatus = event.detail.value;
    }

    handleNotesChange(event) {
        this.notes = event.detail.value;
    }

    async handleSubmit() {
        this.isSubmitting = true;
        try {
            const signatureData =
                this.hasSignature && this.canvas ? this.canvas.toDataURL('image/png') : null;
            const result = await captureVisitConsent({
                request: {
                    visitId: this.visitId,
                    accountId: this.context?.accountId,
                    channel: this.selectedChannel,
                    consentType: this.selectedConsentType,
                    status: this.selectedStatus,
                    signatureData,
                    notes: this.notes
                }
            });
            this.dispatchEvent(
                new CustomEvent('consentcaptured', {
                    detail: { consentId: result.consentId, name: result.name }
                })
            );
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Consent captured',
                    message: `${result.name} was saved for this visit.`,
                    variant: 'success'
                })
            );
            this.notes = '';
            this.handleClearSignature();
            await this.loadContext();
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Consent failed',
                    message: error?.body?.message || error?.message || 'Unable to save consent.',
                    variant: 'error'
                })
            );
        } finally {
            this.isSubmitting = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}
