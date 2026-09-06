import { LightningElement, api } from 'lwc';

export default class FormattedDateTime extends LightningElement {
    @api value;
    @api year = '';
    @api month = '';
    @api day = '';
    @api weekday = '';
    @api hour = '';
    @api minute = '';
    @api second = '';
    @api timeZone = '';
    @api timeZoneName = '';
    @api hour12;

    get displayValue() {
        if (this.value == null || this.value === '') return '';
        try {
            const date = this.value instanceof Date ? this.value : new Date(this.value);
            if (Number.isNaN(date.getTime())) return String(this.value);
            const opts = {};
            if (this.year) opts.year = this.year;
            if (this.month) opts.month = this.month;
            if (this.day) opts.day = this.day;
            if (this.weekday) opts.weekday = this.weekday;
            if (this.hour) opts.hour = this.hour;
            if (this.minute) opts.minute = this.minute;
            if (this.second) opts.second = this.second;
            if (this.timeZone) opts.timeZone = this.timeZone;
            if (this.timeZoneName) opts.timeZoneName = this.timeZoneName;
            if (this.hour12 !== undefined && this.hour12 !== null && this.hour12 !== '') {
                opts.hour12 = this.hour12 === true || this.hour12 === 'true';
            }
            if (Object.keys(opts).length === 0) {
                return date.toLocaleDateString();
            }
            return new Intl.DateTimeFormat(undefined, opts).format(date);
        } catch (_e) {
            return String(this.value);
        }
    }
}
