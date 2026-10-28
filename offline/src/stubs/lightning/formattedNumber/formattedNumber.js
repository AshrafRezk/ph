import { LightningElement, api } from 'lwc';

export default class FormattedNumber extends LightningElement {
    @api value;
    @api formatStyle = 'decimal';
    @api currencyCode = 'USD';
    @api minimumFractionDigits;
    @api maximumFractionDigits;

    get displayValue() {
        if (this.value === null || this.value === undefined || this.value === '') return '';
        const n = Number(this.value);
        if (!Number.isFinite(n)) return String(this.value);
        const opts = { style: this.formatStyle || 'decimal' };
        if (opts.style === 'currency') opts.currency = this.currencyCode || 'USD';
        if (this.minimumFractionDigits !== undefined) opts.minimumFractionDigits = Number(this.minimumFractionDigits);
        if (this.maximumFractionDigits !== undefined) opts.maximumFractionDigits = Number(this.maximumFractionDigits);
        try {
            return new Intl.NumberFormat(undefined, opts).format(opts.style === 'percent' && n > 1 ? n / 100 : n);
        } catch (_e) {
            return String(n);
        }
    }
}
