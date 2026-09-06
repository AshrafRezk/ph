export class ShowToastEvent extends CustomEvent {
    constructor(detail = {}) {
        const payload = {
            title: detail.title || '',
            message: detail.message || '',
            variant: detail.variant || 'info',
            mode: detail.mode || 'dismissible',
            messageData: detail.messageData
        };
        // Single event only — toastManager listens once. Do not re-dispatch on
        // window here; that previously tripled every notification.
        super('lightning__showtoast', {
            bubbles: true,
            composed: true,
            detail: payload
        });
    }
}
