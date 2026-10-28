import { LightningElement, track, wire } from 'lwc';
import { MessageContext } from 'lightning/messageService';
import getActiveMessages from '@salesforce/apex/HomeOfficeMessageController.getActiveMessages';
import {
    subscribeTerritoryContext,
    unsubscribeTerritoryContext
} from 'c/territoryContextClient';
import { isFieldFeatureEnabled, loadFieldFeatures } from 'c/fieldFeatureFlags';

const ROTATE_MS = 6000;

export default class HomeOfficeMessages extends LightningElement {
    @track messages = [];
    @track isLoading = true;
    @track activeIndex = 0;
    featureEnabled = true;

    _rotateTimer = null;
    _messageContext;
    territoryContextSubscription;

    @wire(MessageContext)
    wiredMessageContext(value) {
        this._messageContext = value;
        this.subscribeTerritoryContext();
    }

    connectedCallback() {
        this.subscribeTerritoryContext();
        void this.bootstrap();
    }

    async bootstrap() {
        await loadFieldFeatures();
        this.featureEnabled = isFieldFeatureEnabled('home.officeMessages');
        if (this.featureEnabled) {
            this.loadMessages();
        } else {
            this.isLoading = false;
        }
    }

    disconnectedCallback() {
        this.stopRotation();
        unsubscribeTerritoryContext(this.territoryContextSubscription);
        this.territoryContextSubscription = undefined;
    }

    subscribeTerritoryContext() {
        if (this.territoryContextSubscription || !this._messageContext) {
            return;
        }
        this.territoryContextSubscription = subscribeTerritoryContext(this._messageContext, () => {
            void this.loadMessages();
        });
    }

    get hasMessages() {
        return this.messageRows.length > 0;
    }

    get messageRows() {
        const total = (this.messages || []).length;
        return (this.messages || []).map((message, index) => ({
            ...message,
            index,
            isActive: index === this.activeIndex,
            cardClass: message.isHighPriority ? 'ho-message ho-message-high' : 'ho-message',
            dotClass: index === this.activeIndex ? 'ho-dot ho-dot-active' : 'ho-dot',
            dotLabel: `Message ${index + 1} of ${total}`
        }));
    }

    get showDots() {
        return this.messageRows.length > 1;
    }

    get trackStyle() {
        return `transform: translateX(-${this.activeIndex * 100}%);`;
    }

    async loadMessages() {
        this.isLoading = true;
        this.stopRotation();
        try {
            this.messages = await getActiveMessages({ limitSize: 6 });
            this.activeIndex = 0;
            if (this.messages.length > 1) {
                this.startRotation();
            }
        } catch (e) {
            this.messages = [];
        } finally {
            this.isLoading = false;
        }
    }

    startRotation() {
        this.stopRotation();
        this._rotateTimer = setInterval(() => {
            this.advance();
        }, ROTATE_MS);
    }

    stopRotation() {
        if (this._rotateTimer) {
            clearInterval(this._rotateTimer);
            this._rotateTimer = null;
        }
    }

    advance() {
        const count = this.messages.length;
        if (count <= 1) {
            return;
        }
        this.activeIndex = (this.activeIndex + 1) % count;
    }

    handleDotClick(event) {
        const index = Number.parseInt(event.currentTarget.dataset.index, 10);
        if (Number.isNaN(index)) {
            return;
        }
        this.activeIndex = index;
        if (this.messages.length > 1) {
            this.startRotation();
        }
    }

    handleCarouselMouseEnter() {
        this.stopRotation();
    }

    handleCarouselMouseLeave() {
        if (this.messages.length > 1) {
            this.startRotation();
        }
    }
}