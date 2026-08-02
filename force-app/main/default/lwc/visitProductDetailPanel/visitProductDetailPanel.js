import { LightningElement, api, wire } from 'lwc';
import getTerritoryProducts from '@salesforce/apex/VisitCallReportController.getTerritoryProducts';

const TOPIC_OPTIONS = [
    { label: 'Efficacy', value: 'Efficacy' },
    { label: 'Indication', value: 'Indication' },
    { label: 'Safety', value: 'Safety' },
    { label: 'Side Effects', value: 'Side Effects' },
    { label: 'Usage', value: 'Usage' }
];

const SENTIMENT_OPTIONS = [
    { label: 'Negative', value: 'Negative' },
    { label: 'Neutral', value: 'Neutral' },
    { label: 'Positive', value: 'Positive' }
];

const DETAIL_TYPE_OPTIONS = [
    { label: 'Detail', value: 'Detail' },
    { label: 'Reprint', value: 'Reprint' },
    { label: 'Reminder', value: 'Reminder' }
];

export default class VisitProductDetailPanel extends LightningElement {
    @api visitId;
    @api products = [];
    @api disabled = false;

    territoryProducts = [];

    detailTypeOptions = DETAIL_TYPE_OPTIONS;
    sentimentOptions = SENTIMENT_OPTIONS;

    @wire(getTerritoryProducts, { visitId: '$visitId' })
    wiredProducts({ data }) {
        if (data) {
            this.territoryProducts = data;
        }
    }

    get sidebarProducts() {
        const selectedIds = new Set((this.products || []).map((row) => row.productId));
        return (this.territoryProducts || []).map((row) => ({
            productId: row.productId,
            productName: row.productName,
            imageUrl: row.imageUrl,
            label: this.formatProductLabel(row),
            checked: selectedIds.has(row.productId)
        }));
    }

    get displayProducts() {
        return (this.products || []).map((row, index) => {
            const topicRows = TOPIC_OPTIONS.map((topic) => {
                const msgIndex = (row.messages || []).findIndex((msg) => msg.topic === topic.value);
                const msg = msgIndex >= 0 ? row.messages[msgIndex] : null;
                return {
                    key: `${row.productId}-${topic.value}`,
                    topic: topic.value,
                    label: topic.label,
                    selected: msgIndex >= 0,
                    sentiment: msg?.sentiment || 'Neutral',
                    response: msg?.response || '',
                    messageIndex: msgIndex
                };
            });
            return {
                ...row,
                key: row.id || `product-${row.productId}-${index}`,
                orderLabel: `#${row.displayOrder || index + 1}`,
                canMoveUp: index > 0,
                canMoveDown: index < (this.products || []).length - 1,
                moveUpDisabled: index === 0 || this.disabled,
                moveDownDisabled: index >= (this.products || []).length - 1 || this.disabled,
                topicRows
            };
        });
    }

    get hasProducts() {
        return this.displayProducts.length > 0;
    }

    get hasSidebarProducts() {
        return this.sidebarProducts.length > 0;
    }

    formatProductLabel(row) {
        const parts = [row.productName];
        if (row.adoption) {
            parts.push(`Adoption: ${row.adoption}`);
        }
        if (row.loyalty) {
            parts.push(`Loyalty: ${row.loyalty}`);
        }
        if (row.productMatrixRating) {
            parts.push(`Matrix: ${row.productMatrixRating}`);
        }
        if (row.targetVisitFrequency != null) {
            parts.push(`Freq: ${row.targetVisitFrequency}`);
        }
        return parts.join(' · ');
    }

    handleSidebarToggle(event) {
        if (this.disabled) {
            return;
        }
        const productId = event.target.dataset.productId;
        const checked = event.target.checked;
        if (checked) {
            this.addProductById(productId);
        } else {
            this.removeProductById(productId);
        }
    }

    addProductById(productId) {
        if (!productId || (this.products || []).some((row) => row.productId === productId)) {
            return;
        }
        const territoryRow = (this.territoryProducts || []).find((row) => row.productId === productId);
        const next = [
            ...(this.products || []),
            {
                productId,
                productName: territoryRow?.productName,
                imageUrl: territoryRow?.imageUrl,
                displayOrder: (this.products || []).length + 1,
                detailType: 'Detail',
                notes: '',
                messages: []
            }
        ];
        this.emitChange(this.normalizeOrder(next));
    }

    removeProductById(productId) {
        const next = (this.products || []).filter((row) => row.productId !== productId);
        this.emitChange(this.normalizeOrder(next));
    }

    handleRemoveProduct(event) {
        this.removeProductById(event.currentTarget.dataset.id);
    }

    handleMoveProduct(event) {
        if (this.disabled) {
            return;
        }
        const productId = event.currentTarget.dataset.id;
        const direction = event.currentTarget.dataset.direction;
        const list = [...(this.products || [])];
        const index = list.findIndex((row) => row.productId === productId);
        if (index < 0) {
            return;
        }
        const swapIndex = direction === 'up' ? index - 1 : index + 1;
        if (swapIndex < 0 || swapIndex >= list.length) {
            return;
        }
        [list[index], list[swapIndex]] = [list[swapIndex], list[index]];
        this.emitChange(this.normalizeOrder(list));
    }

    normalizeOrder(products) {
        return products.map((row, index) => ({
            ...row,
            displayOrder: index + 1
        }));
    }

    handleDetailChange(event) {
        const productId = event.target.dataset.productId;
        const field = event.target.dataset.field;
        const value = event.detail.value;
        const next = (this.products || []).map((row) =>
            row.productId === productId ? { ...row, [field]: value } : row
        );
        this.emitChange(next);
    }

    handleTopicToggle(event) {
        const productId = event.target.dataset.productId;
        const topic = event.target.dataset.topic;
        const checked = event.target.checked;
        const next = (this.products || []).map((row) => {
            if (row.productId !== productId) {
                return row;
            }
            let messages = [...(row.messages || [])];
            const existingIndex = messages.findIndex((msg) => msg.topic === topic);
            if (checked && existingIndex < 0) {
                messages.push({ topic, sentiment: 'Neutral', response: '' });
            } else if (!checked && existingIndex >= 0) {
                messages = messages.filter((msg) => msg.topic !== topic);
            }
            return { ...row, messages };
        });
        this.emitChange(next);
    }

    handleSentimentChange(event) {
        const productId = event.currentTarget.dataset.productId;
        const topic = event.currentTarget.dataset.topic;
        const sentiment = event.currentTarget.dataset.sentiment;
        const next = (this.products || []).map((row) => {
            if (row.productId !== productId) {
                return row;
            }
            const messages = (row.messages || []).map((msg) =>
                msg.topic === topic ? { ...msg, sentiment } : msg
            );
            return { ...row, messages };
        });
        this.emitChange(next);
    }

    handleResponseChange(event) {
        const productId = event.target.dataset.productId;
        const topic = event.target.dataset.topic;
        const value = event.detail.value;
        const next = (this.products || []).map((row) => {
            if (row.productId !== productId) {
                return row;
            }
            const messages = (row.messages || []).map((msg) =>
                msg.topic === topic ? { ...msg, response: value } : msg
            );
            return { ...row, messages };
        });
        this.emitChange(next);
    }

    emitChange(products) {
        this.dispatchEvent(
            new CustomEvent('productschange', {
                detail: { products },
                bubbles: true,
                composed: true
            })
        );
    }
}
