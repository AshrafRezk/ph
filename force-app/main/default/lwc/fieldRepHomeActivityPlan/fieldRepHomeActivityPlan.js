import { LightningElement } from 'lwc';
import getHomeMetrics from '@salesforce/apex/FieldRepHomeController.getHomeMetrics';
import { loadFieldFeatures } from 'c/fieldFeatureFlags';

export default class FieldRepHomeActivityPlan extends LightningElement {
    featureEnabled = false;
    featureReady = false;
    errorMessage;
    visitCoveragePercent = 0;
    customerCoveragePercent = 0;
    actualVisitsTotal = 0;
    targetVisitsTotal = 0;
    remainingCalls = 0;

    connectedCallback() {
        this.init();
    }

    get showWidget() {
        return this.featureReady && this.featureEnabled;
    }

    get coverageLabel() {
        return `${Math.round(this.visitCoveragePercent || 0)}%`;
    }

    get customerCoverageLabel() {
        return `${Math.round(this.customerCoveragePercent || 0)}%`;
    }

    get actualTargetLabel() {
        return `${Math.round(this.actualVisitsTotal || 0)} / ${Math.round(this.targetVisitsTotal || 0)}`;
    }

    get remainingLabel() {
        return String(Math.round(this.remainingCalls || 0));
    }

    async init() {
        const features = await loadFieldFeatures();
        this.featureEnabled = features.activityPlan !== false;
        this.featureReady = true;
        if (!this.featureEnabled) {
            return;
        }
        try {
            const metrics = await getHomeMetrics({ contextUserId: null });
            this.visitCoveragePercent = metrics?.visitCoveragePercent || 0;
            this.customerCoveragePercent = metrics?.customerCoveragePercent || 0;
            this.actualVisitsTotal = metrics?.actualVisitsTotal || 0;
            this.targetVisitsTotal = metrics?.targetVisitsTotal || 0;
            this.remainingCalls = metrics?.remainingCalls || 0;
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load activity plan.';
        }
    }
}
