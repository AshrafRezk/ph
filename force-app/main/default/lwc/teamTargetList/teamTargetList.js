import { LightningElement, api } from 'lwc';
import LightningConfirm from 'lightning/confirm';
import getTeamTargets from '@salesforce/apex/TeamTargetListController.getTeamTargets';
import setFrequency from '@salesforce/apex/TeamTargetListController.setFrequency';
import removeFromTargetList from '@salesforce/apex/TeamTargetListController.removeFromTargetList';
import proposeForTargetList from '@salesforce/apex/TeamTargetListController.proposeForTargetList';

function formatNumber(value) {
    return new Intl.NumberFormat('en-US', { maximumFractionDigits: 1 }).format(Number(value || 0));
}

function reduceError(error) {
    return error?.body?.message || error?.message || 'Something went wrong.';
}

/**
 * Manager view of one rep's target list in Class Engine (QA B3-01..B3-04): set a doctor's visits
 * for each month of the quarter (current and later months) within the line's deviation limit per
 * month, take doctors off the list within the quarterly limit, and propose doctors the rep visited
 * outside the list. Class is shown, never edited.
 */
export default class TeamTargetList extends LightningElement {
    /** Rep to open first; the server falls back to the first rep on the team. */
    @api repId;
    /** Quarter to show, e.g. "Q4-2026"; the server falls back to the current quarter. */
    @api quarter;
    data;
    error;
    isLoading = true;
    busyId;
    searchTerm = '';

    connectedCallback() {
        this.load(this.repId || null);
    }

    async load(repId) {
        this.isLoading = true;
        try {
            this.apply(await getTeamTargets({ repId, quarter: this.data?.quarter || this.quarter || null }));
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.isLoading = false;
        }
    }

    apply(data) {
        this.data = data;
        this.error = undefined;
    }

    async run(id, action) {
        this.busyId = id;
        this.error = undefined;
        const quarter = this.data?.quarter;
        try {
            const result = await action();
            this.apply(result);
            // Remove and propose answer with the current quarter; stay on the one being viewed.
            if (quarter && result?.quarter && result.quarter !== quarter) {
                this.data = { ...this.data, quarter };
                await this.load(result.repId);
            }
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.busyId = undefined;
        }
    }

    handleRepChange(event) {
        this.searchTerm = '';
        this.load(event.detail.value);
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    handleStep(event) {
        const { id, month, step } = event.currentTarget.dataset;
        const row = (this.data?.rows || []).find((r) => r.atfId === id);
        const cell = (row?.months || []).find((c) => c.monthStart === month);
        if (!cell || !cell.editable) {
            return;
        }
        const next = Number(cell.frequency || 0) + Number(step);
        if (next < 0) {
            return;
        }
        this.run(id, () =>
            setFrequency({ atfId: id, frequency: next, monthStart: month, quarter: this.data?.quarter || null })
        );
    }

    async handleRemove(event) {
        const { id, name } = event.currentTarget.dataset;
        const ok = await LightningConfirm.open({
            message: `Take ${name} off ${this.data?.repName}'s target list? The class stays as it is, and the removal is logged for SFE.`,
            label: 'Remove from target list',
            theme: 'warning'
        });
        if (ok) {
            this.run(id, () => removeFromTargetList({ atfId: id }));
        }
    }

    handlePropose(event) {
        const { id } = event.currentTarget.dataset;
        this.run(id, () => proposeForTargetList({ repId: this.data?.repId, accountId: id }));
    }

    // ----- view

    get hasData() {
        return Boolean(this.data);
    }

    get repOptions() {
        return this.data?.reps || [];
    }

    get hasReps() {
        return this.repOptions.length > 0;
    }

    get months() {
        return this.data?.months || [];
    }

    /** One chip per month: planned visits, change from before the managers' changes, the limit. */
    get monthChips() {
        const limit = Number(this.data?.frequencyPct || 10);
        return this.months.map((m) => {
            const d = Number(m.deviationPct || 0);
            const sign = d > 0 ? '+' : '';
            const changed = Number(m.currentTotal) !== Number(m.baselineTotal);
            const change = changed ? ` · ${sign}${formatNumber(d)}% from ${formatNumber(m.baselineTotal)}` : '';
            let cls = 'ttl-chip';
            if (!m.editable) {
                cls = 'ttl-chip ttl-chip--muted';
            } else if (Math.abs(d) > limit * 0.8) {
                cls = 'ttl-chip ttl-chip--warn';
            }
            return {
                key: m.monthStart,
                label: `${m.label}: ${formatNumber(m.currentTotal)} visits${change}${m.editable ? '' : ' · closed'}`,
                cls
            };
        });
    }

    get limitLabel() {
        return `Limit ±${formatNumber(this.data?.frequencyPct)}% a month`;
    }

    get removalSummary() {
        return `Removed this quarter ${this.data?.removedThisQuarter || 0} of ${this.data?.removalLimit || 0} allowed (${formatNumber(
            this.data?.removalPct
        )}% of the list)`;
    }

    get removalChipClass() {
        return (this.data?.removedThisQuarter || 0) >= (this.data?.removalLimit || 0) ? 'ttl-chip ttl-chip--warn' : 'ttl-chip';
    }

    get lineLabel() {
        return this.data?.lineName ? `Line rule: ${this.data.lineName}` : 'Org rule';
    }

    get rows() {
        const term = this.searchTerm.trim().toLowerCase();
        return (this.data?.rows || [])
            .filter((r) => !term || `${r.accountName} ${r.specialty || ''}`.toLowerCase().includes(term))
            .map((r) => {
                const busy = this.busyId === r.atfId;
                return {
                    ...r,
                    busy,
                    cells: (r.months || []).map((c) => {
                        const changed = Number(c.frequency) !== Number(c.baseline);
                        return {
                            ...c,
                            key: `${r.atfId}-${c.monthStart}`,
                            frequencyLabel: formatNumber(c.frequency),
                            baselineLabel: changed ? `was ${formatNumber(c.baseline)}` : '',
                            minusDisabled: busy || Number(c.frequency) <= 0
                        };
                    })
                };
            });
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get listCountLabel() {
        const shown = this.rows.length;
        const total = this.data?.listSize || 0;
        return shown === total ? `${total} accounts` : `${shown} of ${total} accounts`;
    }

    get outOfTarget() {
        return (this.data?.outOfTarget || []).map((r) => ({
            ...r,
            canPropose: !r.proposalStatus,
            statusLabel: r.proposalStatus || '',
            busy: this.busyId === r.accountId
        }));
    }

    get hasOutOfTarget() {
        return this.outOfTarget.length > 0;
    }
}
