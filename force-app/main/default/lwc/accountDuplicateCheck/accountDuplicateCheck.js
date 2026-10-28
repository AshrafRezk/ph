import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import findAccountDuplicates from '@salesforce/apex/AccountDuplicateCheckService.findAccountDuplicates';
import reportAccountDuplicate from '@salesforce/apex/AccountDuplicateCheckService.reportAccountDuplicate';
import mergeAccountDuplicates from '@salesforce/apex/AccountDuplicateCheckService.mergeAccountDuplicates';

export default class AccountDuplicateCheck extends NavigationMixin(LightningElement) {
    @api recordId;

    wiredResult;
    result;
    errorMessage;
    isLoading = true;
    isSaving = false;
    pendingAction;

    @wire(findAccountDuplicates, { accountId: '$recordId' })
    wiredDuplicates(result) {
        this.wiredResult = result;
        this.isLoading = false;
        if (result.error) {
            this.result = null;
            this.errorMessage = this.messageFrom(result.error);
            return;
        }
        this.errorMessage = null;
        this.result = result.data || null;
    }

    get sourceType() {
        return this.result?.recordTypeName || '—';
    }

    get hasRecord() {
        return Boolean(this.recordId);
    }

    get showEmpty() {
        return !this.isLoading && !this.errorMessage && this.result && !this.result.hasMatches;
    }

    get matches() {
        return (this.result?.matches || []).map((match) => ({
            ...match,
            meterStyle: `width: ${match.percent || 0}%`,
            meterClass: `meter-fill ${this.toneClass(match.percent)}`,
            badgeClass: `possibility-badge ${this.toneClass(match.percent)}`,
            factors: (match.factors || []).map((factor) => ({
                ...factor,
                chipClass: `factor-chip ${factor.percent >= 70 ? 'factor-strong' : 'factor-weak'}`,
                text: `${factor.label} ${factor.percent}%`
            })),
            typeLine: match.recordTypeName || 'Account',
            reportLabel: `Report as duplicate of ${match.accountName}`,
            mergeLabel: `Merge with ${match.accountName}`
        }));
    }

    get headlineClass() {
        return `headline ${this.toneClass(this.result?.highestPercent)}`;
    }

    get showConfirm() {
        return Boolean(this.pendingAction);
    }

    get confirmTitle() {
        return this.pendingAction?.kind === 'merge' ? 'Merge accounts' : 'Report duplicate';
    }

    get confirmBody() {
        if (!this.pendingAction) {
            return '';
        }
        if (this.pendingAction.kind === 'merge') {
            return `Merge these accounts and keep ${this.pendingAction.keepName}. Related records move to that account. The other account is deleted.`;
        }
        return `Report ${this.result?.accountName || 'this account'} as a duplicate of ${this.pendingAction.matchName}. It will be marked Duplicate and linked to that record.`;
    }

    get confirmButtonLabel() {
        return this.pendingAction?.kind === 'merge' ? 'Merge' : 'Report';
    }

    toneClass(percent) {
        const value = Number(percent) || 0;
        if (value >= 85) return 'tone-high';
        if (value >= 70) return 'tone-likely';
        if (value >= 50) return 'tone-possible';
        return 'tone-weak';
    }

    handleOpenMatch(event) {
        const accountId = event.currentTarget.dataset.id;
        if (!accountId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: accountId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }

    handleReport(event) {
        const accountId = event.currentTarget.dataset.id;
        const match = this.matchById(accountId);
        if (!match || !this.result?.canReport) {
            return;
        }
        this.pendingAction = {
            kind: 'report',
            matchId: accountId,
            matchName: match.accountName
        };
    }

    handleMerge(event) {
        const accountId = event.currentTarget.dataset.id;
        const keep = event.currentTarget.dataset.keep;
        const match = this.matchById(accountId);
        if (!match || !this.result?.canMerge) {
            return;
        }
        const keepCurrent = keep !== 'match';
        this.pendingAction = {
            kind: 'merge',
            matchId: accountId,
            matchName: match.accountName,
            survivorId: keepCurrent ? this.recordId : accountId,
            duplicateId: keepCurrent ? accountId : this.recordId,
            keepName: keepCurrent ? this.result.accountName : match.accountName
        };
    }

    handleCancelConfirm() {
        if (this.isSaving) {
            return;
        }
        this.pendingAction = null;
    }

    stopConfirmClick(event) {
        event.stopPropagation();
    }

    async handleConfirm() {
        const action = this.pendingAction;
        if (!action || this.isSaving) {
            return;
        }
        this.isSaving = true;
        try {
            const outcome =
                action.kind === 'merge'
                    ? await mergeAccountDuplicates({
                          survivorId: action.survivorId,
                          duplicateId: action.duplicateId
                      })
                    : await reportAccountDuplicate({
                          accountId: this.recordId,
                          duplicateOfId: action.matchId
                      });
            this.toast(action.kind === 'merge' ? 'Accounts merged' : 'Duplicate reported', outcome?.message, 'success');
            this.pendingAction = null;
            this.dispatchEvent(new CustomEvent('duplicatechange'));
            if (outcome?.sourceRemoved && outcome.survivorId && outcome.survivorId !== this.recordId) {
                this.handleOpenMatch({ currentTarget: { dataset: { id: outcome.survivorId } } });
            }
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.toast('Duplicate check failed', this.messageFrom(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    matchById(accountId) {
        return (this.result?.matches || []).find((match) => match.accountId === accountId);
    }

    messageFrom(error) {
        return error?.body?.message || error?.message || 'Unable to check duplicates.';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}