import approveAccountSubmission from '@salesforce/apex/AccountsTabController.approveAccountSubmission';
import getPendingAccountApprovals from '@salesforce/apex/AccountsTabController.getPendingAccountApprovals';
import isAccountApprovalManager from '@salesforce/apex/AccountsTabController.isAccountApprovalManager';
import rejectAccountSubmission from '@salesforce/apex/AccountsTabController.rejectAccountSubmission';
import { accountThemeFor, accountThemeStyle } from 'c/accountTypeTheme';
import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { isFieldFeatureEnabled, loadFieldFeatures } from 'c/fieldFeatureFlags';

export default class AccountApprovalQueue extends LightningElement {
    wiredResult;
    isManager = false;
    rows = [];
    rejectionReasonByAccountId = {};
    selectedById = {};
    showRejectModal = false;
    showListModal = false;
    showDuplicateModal = false;
    duplicateAccountId;
    rejectTargetIds = [];
    rejectCompanionIds = [];
    rejectReasonMissing = false;
    isSaving = false;
    saveStatus = '';
    isPrevDisabled = true;
    isNextDisabled = true;
    carouselMeasured = false;
    _presetRejectReason = '';
    _rejectFocused = false;
    featureEnabled = true;

    connectedCallback() {
        void loadFieldFeatures().then(() => {
            this.featureEnabled = isFieldFeatureEnabled('home.accountsNurturing');
        });
        this._onResize = () => this.syncCarouselEdges();
        this._onKeydown = (event) => {
            if (event.key !== 'Escape' || this.isSaving) {
                return;
            }
            if (this.showRejectModal) {
                this.showRejectModal = false;
                return;
            }
            if (this.showDuplicateModal) {
                this.showDuplicateModal = false;
                this.duplicateAccountId = null;
                return;
            }
            if (this.showListModal) {
                this.showListModal = false;
            }
        };
        window.addEventListener('resize', this._onResize);
        window.addEventListener('keydown', this._onKeydown);
    }

    disconnectedCallback() {
        window.removeEventListener('resize', this._onResize);
        window.removeEventListener('keydown', this._onKeydown);
    }

    renderedCallback() {
        this.syncCarouselEdges();
        this.syncRejectField();
        this.syncReasonFields();
    }

    @wire(isAccountApprovalManager)
    wiredManager(result) {
        this.isManager = result.data === true;
    }

    @wire(getPendingAccountApprovals)
    wiredApprovals(result) {
        this.wiredResult = result;
        if (result.data) {
            this.rows = result.data.map((row) => ({
                ...row,
                submittedLabel: row.submittedDate
                    ? new Date(row.submittedDate).toLocaleString([], {
                          month: 'short',
                          day: 'numeric',
                          hour: '2-digit',
                          minute: '2-digit'
                      })
                    : '—'
            }));
            const liveIds = new Set(this.rows.map((row) => row.accountId));
            const nextSelected = {};
            Object.keys(this.selectedById).forEach((accountId) => {
                if (liveIds.has(accountId)) {
                    nextSelected[accountId] = true;
                }
            });
            this.selectedById = nextSelected;
        } else if (result.error) {
            this.rows = [];
            this.selectedById = {};
        }
    }

    get showQueue() {
        return this.featureEnabled === true && (this.isManager === true || this.rows.length > 0);
    }

    get actionableRows() {
        return this.rows.filter((row) => row.canAct === true && row.createdByMe !== true);
    }

    get mineRows() {
        return this.rows.filter((row) => row.createdByMe === true);
    }

    get hasMine() {
        return this.mineRows.length > 0;
    }

    get canAct() {
        return this.actionableRows.length > 0;
    }

    get sfeOnly() {
        return this.canAct && this.actionableRows.every((row) => row.reviewStep === 'SFE');
    }

    get showNeedYouCount() {
        return this.actionableRows.length > 0;
    }

    get needYouLabel() {
        const count = this.actionableRows.length;
        return count === 1 ? '1 needs you' : `${count} need you`;
    }

    get mineSummary() {
        const counts = new Map();
        this.mineRows.forEach((row) => {
            const label = row.stageLabel || 'Draft';
            counts.set(label, (counts.get(label) || 0) + 1);
        });
        const statuses = [...counts.entries()].map(([label, count]) => `${count} ${label}`).join(' · ');
        const created = this.mineRows.length === 1 ? '1 you created' : `${this.mineRows.length} you created`;
        return statuses ? `${created} · ${statuses}` : created;
    }

    get queueSubtitle() {
        if (this.sfeOnly && this.hasMine) {
            return 'Approve or reject new accounts waiting on SFE for your lines. Yours are listed with their status.';
        }
        if (this.sfeOnly) {
            return 'Approve or reject new accounts waiting on SFE for your lines.';
        }
        if (this.canAct && this.hasMine) {
            return 'Approve or reject new accounts from your team. Yours are listed with their status.';
        }
        if (this.canAct) {
            return 'Approve or reject new accounts submitted by medical reps in your territory.';
        }
        if (this.hasMine) {
            return 'Accounts you created, and where each one stands.';
        }
        return 'Pending approval. Your manager reviews these before you can use them.';
    }

    get listSubtitle() {
        if (this.sfeOnly) {
            return 'Review accounts waiting on SFE for your lines. Approving moves them to FI validation; rejecting sends them back to the DM.';
        }
        if (this.canAct && this.hasMine) {
            return 'Approve or reject team submissions. Accounts you created are listed with their status.';
        }
        if (this.canAct) {
            return 'Review every pending submission, edit a reason on the row, then approve or reject one or many.';
        }
        if (this.hasMine) {
            return 'These are accounts you created. Each one shows its current status.';
        }
        return 'These accounts are pending approval. Your manager will approve or reject them.';
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get pendingLabel() {
        return this.rows.length === 1 ? '1 pending' : `${this.rows.length} pending`;
    }

    get showCarouselNav() {
        return this.hasRows && this.carouselMeasured && !(this.isPrevDisabled && this.isNextDisabled);
    }

    get carouselWrapClass() {
        const classes = ['carousel-wrap'];
        if (this.carouselMeasured && !this.isPrevDisabled) {
            classes.push('has-prev');
        }
        if (this.carouselMeasured && !this.isNextDisabled) {
            classes.push('has-next');
        }
        return classes.join(' ');
    }

    get displayRows() {
        return this.rows.map((row) => {
            const specialty = row.specialty || '';
            const city = row.city || '';
            const theme = accountThemeFor(row.recordTypeDeveloperName, row.recordTypeName);
            const placeLine = [city, row.repName].filter(Boolean).join(' · ');
            const showActions = row.canAct === true && row.createdByMe !== true;
            return {
                ...row,
                showActions,
                statusClass: this.statusClassFor(row.stageLabel),
                typeIconUrl: theme.iconUrl,
                typeLabel: theme.label,
                typeInitial: (theme.label || 'A').slice(0, 1),
                themeStyle: accountThemeStyle(theme),
                specialtyLine: specialty || theme.label,
                tileMeta: placeLine || theme.label,
                listRep: row.repName || '—',
                listSpecialty: specialty || '—',
                listCity: city || '—',
                selected: this.selectedById[row.accountId] === true,
                tooltip: [row.accountName, [row.repName, specialty, city, row.submittedLabel].filter(Boolean).join(' · ')]
                    .filter(Boolean)
                    .join(' — '),
                approveLabel: `Approve ${row.accountName}`,
                rejectLabel: `Reject ${row.accountName}`,
                selectLabel: `Select ${row.accountName}`,
                reasonLabel: `Rejection reason for ${row.accountName}`
            };
        });
    }

    get selectedAccountIds() {
        return this.actionableRows
            .filter((row) => this.selectedById[row.accountId])
            .map((row) => row.accountId);
    }

    get selectedCount() {
        return this.selectedAccountIds.length;
    }

    get hasSelection() {
        return this.selectedCount > 0;
    }

    get allSelected() {
        const actionable = this.actionableRows;
        return actionable.length > 0 && actionable.every((row) => this.selectedById[row.accountId]);
    }

    get selectionLabel() {
        if (!this.selectedCount) {
            return 'None selected';
        }
        return this.selectedCount === 1 ? '1 selected' : `${this.selectedCount} selected`;
    }

    get massDisabled() {
        return this.isSaving || !this.hasSelection;
    }

    get massApproveLabel() {
        return this.selectedCount ? `Approve selected (${this.selectedCount})` : 'Approve selected';
    }

    get massRejectLabel() {
        return this.selectedCount ? `Reject selected (${this.selectedCount})` : 'Reject selected';
    }

    get massApproveTitle() {
        return this.hasSelection ? 'Approve the checked accounts' : 'Select at least one account';
    }

    get massRejectTitle() {
        return this.hasSelection ? 'Reject the checked accounts' : 'Select at least one account';
    }

    get rejectSingleName() {
        if (this.rejectTargetIds.length !== 1 || this.rejectCompanionIds.length) {
            return '';
        }
        const row = this.rows.find((item) => item.accountId === this.rejectTargetIds[0]);
        return row?.accountName || '';
    }

    get rejectContextLine() {
        if (!this.rejectSingleName) {
            return '';
        }
        const row = this.rows.find((item) => item.accountId === this.rejectTargetIds[0]);
        if (!row) {
            return '';
        }
        return [row.repName, row.specialty, row.city, row.submittedLabel].filter(Boolean).join(' · ');
    }

    get rejectBulkHelp() {
        const missing = this.rejectTargetIds.length;
        const ready = this.rejectCompanionIds.length;
        if (!missing || (missing === 1 && !ready)) {
            return '';
        }
        const missingLabel = missing === 1 ? '1 selected account' : `${missing} selected accounts`;
        if (ready) {
            const readyLabel = ready === 1 ? '1 account keeps the reason already on its row.' : `${ready} accounts keep the reason already on their row.`;
            return `This reason is used for ${missingLabel} that do not have one yet. ${readyLabel}`;
        }
        return `This reason is used for ${missingLabel}.`;
    }

    syncCarouselEdges() {
        const scroller = this.template.querySelector('[data-carousel]');
        if (!scroller) {
            return;
        }
        const atStart = scroller.scrollLeft <= 1;
        const atEnd = scroller.scrollLeft + scroller.clientWidth >= scroller.scrollWidth - 2;
        if (
            this.carouselMeasured &&
            this.isPrevDisabled === atStart &&
            this.isNextDisabled === atEnd
        ) {
            return;
        }
        this.carouselMeasured = true;
        this.isPrevDisabled = atStart;
        this.isNextDisabled = atEnd;
    }

    syncReasonFields() {
        const active = this.template.activeElement;
        this.template.querySelectorAll('.reason-field').forEach((field) => {
            if (field === active) {
                return;
            }
            const next = this.rejectionReasonByAccountId[field.dataset.accountId] || '';
            if (field.value !== next) {
                field.value = next;
            }
        });
    }

    syncRejectField() {
        if (!this.showRejectModal) {
            this._rejectFocused = false;
            return;
        }
        if (this._rejectFocused) {
            return;
        }
        const field = this.template.querySelector('[data-reject-reason]');
        if (!field) {
            return;
        }
        field.value = this._presetRejectReason || '';
        this._presetRejectReason = '';
        field.focus();
        this._rejectFocused = true;
    }

    handleCarouselScroll() {
        this.syncCarouselEdges();
    }

    handlePrevious() {
        this.scrollCarousel(-1);
    }

    handleNext() {
        this.scrollCarousel(1);
    }

    scrollCarousel(direction) {
        const scroller = this.template.querySelector('[data-carousel]');
        if (!scroller) {
            return;
        }
        const tile = scroller.querySelector('.tile');
        const gap = parseFloat(window.getComputedStyle(scroller).columnGap || window.getComputedStyle(scroller).gap) || 0;
        const step = tile ? tile.getBoundingClientRect().width + gap : scroller.clientWidth;
        const visible = Math.max(1, Math.floor((scroller.clientWidth + gap) / step));
        scroller.scrollBy({ left: direction * visible * step });
    }

    handleOpenDuplicate(event) {
        event.stopPropagation();
        const accountId = event.currentTarget.dataset.accountId;
        if (!accountId) {
            return;
        }
        this.duplicateAccountId = accountId;
        this.showDuplicateModal = true;
    }

    handleCloseDuplicate() {
        if (this.isSaving) {
            return;
        }
        this.showDuplicateModal = false;
        this.duplicateAccountId = null;
    }

    handleDuplicateChange() {
        if (this.wiredResult) {
            refreshApex(this.wiredResult);
        }
    }

    handleOpenList() {
        this.showListModal = true;
    }

    handleCloseList() {
        if (this.isSaving) {
            return;
        }
        this.showListModal = false;
    }

    handleCloseRejectModal() {
        if (this.isSaving) {
            return;
        }
        this.showRejectModal = false;
        this.rejectReasonMissing = false;
    }

    stopModalClick(event) {
        event.stopPropagation();
    }

    handleToggleAll(event) {
        const next = {};
        if (event.target.checked) {
            this.actionableRows.forEach((row) => {
                next[row.accountId] = true;
            });
        }
        this.selectedById = next;
    }

    handleToggleRow(event) {
        const accountId = event.target.dataset.accountId;
        const next = { ...this.selectedById };
        if (event.target.checked) {
            next[accountId] = true;
        } else {
            delete next[accountId];
        }
        this.selectedById = next;
    }

    handleRejectionInput(event) {
        const accountId = event.target.dataset.accountId;
        if (!accountId) {
            return;
        }
        this.rejectionReasonByAccountId[accountId] = event.target.value;
    }

    handleRejectReasonInput() {
        if (this.rejectReasonMissing) {
            this.rejectReasonMissing = false;
        }
    }

    async handleApprove(event) {
        const accountId = event.currentTarget.dataset.accountId;
        if (!accountId || this.isSaving) {
            return;
        }
        await this.commitApprove([accountId]);
    }

    async handleMassApprove() {
        const accountIds = this.selectedAccountIds;
        if (!accountIds.length || this.isSaving) {
            return;
        }
        await this.commitApprove(accountIds);
    }

    handleReject(event) {
        const accountId = event.currentTarget.dataset.accountId;
        if (!accountId || this.isSaving) {
            return;
        }
        this.openRejectModal([accountId]);
    }

    handleMassReject() {
        const accountIds = this.selectedAccountIds;
        if (!accountIds.length || this.isSaving) {
            return;
        }
        const missing = [];
        const ready = [];
        accountIds.forEach((accountId) => {
            const reason = (this.rejectionReasonByAccountId[accountId] || '').trim();
            if (reason) {
                ready.push(accountId);
            } else {
                missing.push(accountId);
            }
        });
        if (!missing.length) {
            this.commitReject(
                ready.map((accountId) => ({
                    accountId,
                    rejectionReason: this.rejectionReasonByAccountId[accountId].trim()
                }))
            );
            return;
        }
        this.openRejectModal(missing, ready);
    }

    openRejectModal(targetIds, companionIds = []) {
        this.rejectTargetIds = [...targetIds];
        this.rejectCompanionIds = [...companionIds];
        this.rejectReasonMissing = false;
        this._rejectFocused = false;
        this._presetRejectReason =
            targetIds.length === 1 ? this.rejectionReasonByAccountId[targetIds[0]] || '' : '';
        this.showRejectModal = true;
    }

    handleConfirmReject() {
        const field = this.template.querySelector('[data-reject-reason]');
        const reason = (field?.value || '').trim();
        if (!reason) {
            this.rejectReasonMissing = true;
            field?.focus();
            return;
        }
        const jobs = this.rejectTargetIds.map((accountId) => ({
            accountId,
            rejectionReason: reason
        }));
        this.rejectCompanionIds.forEach((accountId) => {
            const rowReason = (this.rejectionReasonByAccountId[accountId] || '').trim();
            jobs.push({
                accountId,
                rejectionReason: rowReason || reason
            });
        });
        this.commitReject(jobs);
    }

    reviewStepOf(accountIds) {
        const steps = new Set(
            this.rows
                .filter((row) => accountIds.includes(row.accountId))
                .map((row) => row.reviewStep || 'DM')
        );
        return steps.size === 1 ? [...steps][0] : 'MIXED';
    }

    async commitApprove(accountIds) {
        const ids = [...accountIds];
        const step = this.reviewStepOf(ids);
        this.isSaving = true;
        let done = 0;
        try {
            for (const accountId of ids) {
                this.saveStatus = ids.length > 1 ? `Approving ${done + 1} of ${ids.length}` : '';
                // eslint-disable-next-line no-await-in-loop
                await approveAccountSubmission({ accountId });
                done += 1;
                this.dropRow(accountId);
            }
            if (step === 'SFE') {
                this.showToast(
                    'Sent to FI validation',
                    done === 1
                        ? 'You approved this account. It moves on to FI validation.'
                        : `${done} accounts moved on to FI validation.`,
                    'success'
                );
            } else if (step === 'MIXED') {
                this.showToast('Approved', `${done} accounts moved to their next step.`, 'success');
            } else {
                this.showToast(
                    'Sent to SFE',
                    done === 1
                        ? 'You approved this account. It is waiting on SFE.'
                        : `${done} accounts are waiting on SFE.`,
                    'success'
                );
            }
        } catch (error) {
            this.showToast('Approve failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
            this.saveStatus = '';
            await refreshApex(this.wiredResult);
        }
    }

    async commitReject(jobs) {
        const queue = [...jobs];
        const step = this.reviewStepOf(queue.map((job) => job.accountId));
        this.isSaving = true;
        let done = 0;
        try {
            for (const job of queue) {
                this.saveStatus = queue.length > 1 ? `Rejecting ${done + 1} of ${queue.length}` : '';
                // eslint-disable-next-line no-await-in-loop
                await rejectAccountSubmission({
                    accountId: job.accountId,
                    rejectionReason: job.rejectionReason
                });
                done += 1;
                this.dropRow(job.accountId);
            }
            this.showRejectModal = false;
            this.rejectReasonMissing = false;
            if (step === 'SFE') {
                this.showToast(
                    'Sent back to DM',
                    done === 1
                        ? 'Account sent back to the DM with your reason.'
                        : `${done} accounts sent back to the DM with your reason.`,
                    'success'
                );
            } else if (step === 'MIXED') {
                this.showToast('Rejected', `${done} accounts sent back one step.`, 'success');
            } else {
                this.showToast(
                    'Rejected',
                    done === 1
                        ? 'Account returned to Draft for the rep.'
                        : `${done} accounts returned to Draft for the rep.`,
                    'success'
                );
            }
        } catch (error) {
            this.showToast('Reject failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
            this.saveStatus = '';
            await refreshApex(this.wiredResult);
        }
    }

    dropRow(accountId) {
        delete this.rejectionReasonByAccountId[accountId];
        if (this.selectedById[accountId]) {
            const next = { ...this.selectedById };
            delete next[accountId];
            this.selectedById = next;
        }
        this.rows = this.rows.filter((row) => row.accountId !== accountId);
    }

    statusClassFor(stageLabel) {
        const key = (stageLabel || 'Draft')
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, '-')
            .replace(/^-|-$/g, '');
        return `pending-pill status-${key}`;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}