import { LightningElement, track } from 'lwc';
import getMyScorecard from '@salesforce/apex/FieldRepKpiController.getMyScorecard';

export default class FieldRepKpiDashboard extends LightningElement {
    @track scorecard;
    loading = true;
    error;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        this.error = null;
        try {
            const data = await getMyScorecard();
            this.scorecard = {
                ...data,
                cards: (data.cards || []).map((c) => ({
                    ...c,
                    key: c.key,
                    cardClass: `kpi-card status-${c.status || 'pending'}`,
                    actualLabel:
                        c.actual == null ? '—' : `${Number(c.actual).toFixed(1)}%`,
                    targetLabel: c.target == null ? '' : `Target ${Number(c.target).toFixed(1)}%`
                }))
            };
        } catch (e) {
            this.error = (e && e.body && e.body.message) || e.message || 'Failed to load KPIs';
        } finally {
            this.loading = false;
        }
    }

    get periodLabel() {
        return this.scorecard && this.scorecard.periodLabel;
    }

    handleRefresh() {
        this.load();
    }
}
