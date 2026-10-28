import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import startScan from '@salesforce/apex/DoctorSpecialtyMergeService.startScan';
import getLatestRun from '@salesforce/apex/DoctorSpecialtyMergeService.getLatestRun';
import listPairs from '@salesforce/apex/DoctorSpecialtyMergeService.listPairs';
import comparePair from '@salesforce/apex/DoctorSpecialtyMergeService.comparePair';
import mergePair from '@salesforce/apex/DoctorSpecialtyMergeService.mergePair';
import dismissPairs from '@salesforce/apex/DoctorSpecialtyMergeService.dismissPairs';
import getRunStatus from '@salesforce/apex/AccountQualityReviewService.getRunStatus';

const SCORE_OPTIONS = [
    { label: 'Very likely (70+)', value: '70' },
    { label: 'Likely and up (50+)', value: '50' },
    { label: 'All candidates (30+)', value: '30' }
];

// Admin Console > Account data quality > Doctor specialty merger.
export default class DoctorSpecialtyMerger extends LightningElement {
    @track pairs = [];
    @track runStatus = null;
    @track manualPair = null;
    minScore = '50';
    showClosed = false;
    codeA = '';
    codeB = '';
    isBusy = false;
    progressMessage = '';
    pollTimer;

    get scoreOptions() {
        return SCORE_OPTIONS;
    }

    get hasPairs() {
        return this.pairs.length > 0;
    }

    get isRunActive() {
        const status = this.runStatus?.status;
        return status === 'Queued' || status === 'Running';
    }

    get runSummary() {
        if (!this.runStatus || this.runStatus.status === 'None') {
            return 'No scan yet.';
        }
        const parts = [
            `Last scan: ${this.runStatus.status}`,
            `${this.runStatus.accountsScanned || 0} doctors checked`,
            `${this.runStatus.proposalCount || 0} possible duplicates`
        ];
        if (this.runStatus.errorMessage) {
            parts.push(this.runStatus.errorMessage);
        }
        return parts.join(' · ');
    }

    get pairCards() {
        return this.pairs.map((pair) => this.decorate(pair));
    }

    get manualCard() {
        return this.manualPair ? this.decorate(this.manualPair) : null;
    }

    connectedCallback() {
        this.refresh();
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    decorate(pair) {
        const key = pair.proposalId || `manual-${pair.left?.id}-${pair.right?.id}`;
        const survivorId = pair.survivorId || pair.suggestedSurvivorId;
        const card = (doctor, side) =>
            doctor
                ? {
                      ...doctor,
                      side,
                      url: `/lightning/r/Account/${doctor.id}/view`,
                      isKept: doctor.id === survivorId,
                      boxClass: `doctor${doctor.id === survivorId ? ' doctor--kept' : ''}`,
                      keepLabel: doctor.id === survivorId ? 'Kept record' : 'Merged into the kept record',
                      specialtyText: (doctor.specialties || []).join(', ') || '—',
                      hasWorkplaces: (doctor.workplaces || []).length > 0,
                      hasLines: (doctor.lines || []).length > 0,
                      workplaceItems: (doctor.workplaces || []).map((w, i) => ({ key: `${key}-${side}-w${i}`, text: w })),
                      lineItems: (doctor.lines || []).map((l, i) => ({ key: `${key}-${side}-l${i}`, text: l }))
                  }
                : null;
        const isOpen = pair.status === 'Pending' || pair.status === 'Failed';
        return {
            ...pair,
            key,
            radioName: `${key}-keep`,
            survivorId,
            leftCard: card(pair.left, 'left'),
            rightCard: card(pair.right, 'right'),
            badgeClass: `badge ${pair.score >= 70 ? 'badge--very' : pair.score >= 50 ? 'badge--likely' : 'badge--possible'}`,
            factorItems: (pair.factors || []).map((f, i) => ({
                key: `${key}-f${i}`,
                text: `${f.label} ${f.points > 0 ? '+' : ''}${f.points}`,
                className: `factor${f.points < 0 ? ' factor--minus' : ''}`
            })),
            mergedSpecialtyText: (pair.mergedSpecialties || []).join(', '),
            isOpen,
            isComplete: !!(pair.left && pair.right),
            statusText: pair.status === 'Applied' ? 'Merged' : pair.status
        };
    }

    handleScoreChange(event) {
        this.minScore = event.detail.value;
        this.loadPairs();
    }

    handleShowClosed(event) {
        this.showClosed = event.target.checked;
        this.loadPairs();
    }

    handleCodeA(event) {
        this.codeA = event.target.value;
    }

    handleCodeB(event) {
        this.codeB = event.target.value;
    }

    handleKeepChange(event) {
        const key = event.target.dataset.key;
        const survivorId = event.target.value;
        if (this.manualPair && key.startsWith('manual-')) {
            this.manualPair = { ...this.manualPair, survivorId };
            return;
        }
        this.pairs = this.pairs.map((p) => (p.proposalId === key ? { ...p, survivorId } : p));
    }

    async handleScan() {
        if (this.isRunActive) {
            this.startPolling(this.runStatus.runId);
            return;
        }
        this.isBusy = true;
        this.progressMessage = 'Starting scan…';
        try {
            this.runStatus = await startScan();
            this.startPolling(this.runStatus.runId);
        } catch (error) {
            this.toast('Scan failed', this.errorMessage(error), 'error');
            this.isBusy = false;
        }
    }

    async handleCompare() {
        if (!this.codeA || !this.codeB) {
            this.toast('Enter two codes', 'Type both doctor codes, for example 59087 and DOC-61021.', 'warning');
            return;
        }
        this.isBusy = true;
        try {
            this.manualPair = await comparePair({ first: this.codeA, second: this.codeB });
        } catch (error) {
            this.manualPair = null;
            this.toast('Compare failed', this.errorMessage(error), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    async handleMerge(event) {
        const key = event.currentTarget.dataset.key;
        const isManual = key.startsWith('manual-');
        const pair = isManual ? this.manualPair : this.pairs.find((p) => p.proposalId === key);
        if (!pair) {
            return;
        }
        const survivorId = pair.survivorId || pair.suggestedSurvivorId;
        const kept = pair.left.id === survivorId ? pair.left : pair.right;
        const other = kept === pair.left ? pair.right : pair.left;
        // eslint-disable-next-line no-alert
        const ok = window.confirm(
            `Merge ${other.name} (${other.code}) into ${kept.name} (${kept.code})?\n\n` +
                'Visits, clinics, pharmacies, lines and empty fields move to the kept record. ' +
                'The other record is removed and its code is kept on the doctor.'
        );
        if (!ok) {
            return;
        }
        this.isBusy = true;
        try {
            const result = await mergePair({
                proposalId: isManual ? null : pair.proposalId,
                survivorId,
                otherId: other.id
            });
            const extras = [];
            if (result.filledFields?.length) {
                extras.push(`filled: ${result.filledFields.join(', ')}`);
            }
            if (result.combinedTargetRows) {
                extras.push(`${result.combinedTargetRows} same-line target row(s) combined`);
            }
            this.toast('Doctors merged', `${result.message} ${extras.join(' · ')}`, 'success');
            if (isManual) {
                this.manualPair = null;
            }
            await this.loadPairs();
        } catch (error) {
            this.toast('Merge failed', this.errorMessage(error), 'error');
            await this.loadPairs();
        } finally {
            this.isBusy = false;
        }
    }

    async handleDismiss(event) {
        const key = event.currentTarget.dataset.key;
        if (key.startsWith('manual-')) {
            this.manualPair = null;
            return;
        }
        this.isBusy = true;
        try {
            await dismissPairs({ proposalIds: [key] });
            this.pairs = this.pairs.filter((p) => p.proposalId !== key);
            this.toast('Kept apart', 'These two stay as separate doctors.', 'success');
        } catch (error) {
            this.toast('Dismiss failed', this.errorMessage(error), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    async refresh() {
        this.isBusy = true;
        try {
            this.runStatus = await getLatestRun();
            if (this.isRunActive) {
                this.startPolling(this.runStatus.runId);
                return;
            }
            await this.loadPairs();
        } catch (error) {
            this.toast('Load failed', this.errorMessage(error), 'error');
        } finally {
            if (!this.isRunActive) {
                this.isBusy = false;
            }
        }
    }

    async loadPairs() {
        if (!this.runStatus?.runId) {
            this.pairs = [];
            return;
        }
        const rows = await listPairs({
            runId: this.runStatus.runId,
            minScore: parseInt(this.minScore, 10),
            includeClosed: this.showClosed
        });
        this.pairs = (rows || []).map((row) => ({ ...row, survivorId: row.suggestedSurvivorId }));
    }

    startPolling(runId) {
        this.stopPolling();
        this.isBusy = true;
        this.progressMessage = 'Scanning doctors…';
        this.pollTimer = setInterval(() => this.pollOnce(runId), 3000);
        this.pollOnce(runId);
    }

    stopPolling() {
        if (this.pollTimer) {
            clearInterval(this.pollTimer);
            this.pollTimer = null;
        }
    }

    async pollOnce(runId) {
        try {
            this.runStatus = await getRunStatus({ runId });
            const done = this.runStatus.jobItemsProcessed || 0;
            const total = this.runStatus.totalJobItems || 0;
            this.progressMessage = `Scanning doctors… ${done}/${total || '?'}`;
            if (this.runStatus.status === 'Ready' || this.runStatus.status === 'Failed') {
                this.stopPolling();
                this.isBusy = false;
                this.progressMessage = '';
                await this.loadPairs();
            }
        } catch (error) {
            this.stopPolling();
            this.isBusy = false;
            this.toast('Status failed', this.errorMessage(error), 'error');
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errorMessage(error) {
        return error?.body?.message || error?.message || 'Unexpected error.';
    }
}
