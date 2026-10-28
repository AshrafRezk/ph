import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { accountThemeFor, accountThemeStyle } from 'c/accountTypeTheme';

const FIELDS = ['Account.Name', 'Account.RecordType.DeveloperName', 'Account.RecordType.Name'];

export default class AccountTypeBanner extends LightningElement {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    account;

    get theme() {
        const data = this.account.data;
        const developerName = data?.fields?.RecordType?.value?.fields?.DeveloperName?.value || '';
        const recordTypeName =
            data?.recordTypeInfo?.name ||
            data?.fields?.RecordType?.displayValue ||
            data?.fields?.RecordType?.value?.fields?.Name?.value ||
            '';
        return accountThemeFor(developerName, recordTypeName);
    }

    get showBanner() {
        return Boolean(this.account.data) && this.theme.kind !== 'account';
    }

    get bannerClass() {
        return `account-type-banner theme-${this.theme.kind}`;
    }

    get bannerStyle() {
        return accountThemeStyle(this.theme);
    }

    get iconUrl() {
        return this.theme.iconUrl;
    }

    get typeLabel() {
        return this.theme.label;
    }

    get accountName() {
        return this.account.data?.fields?.Name?.value || '';
    }
}