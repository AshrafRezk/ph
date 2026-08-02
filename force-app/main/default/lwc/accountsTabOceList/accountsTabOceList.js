import { LightningElement, api } from 'lwc';

import { resolveAccountPinKind } from 'c/plannerMapPins';

const RISK_DOT_CLASS = {
    High: 'risk-dot-high',
    Med: 'risk-dot-med',
    Low: 'risk-dot-low'
};

const CLASSIFICATION_VARIANT = {
    A: 'success',
    B: 'warning',
    C: 'lightest'
};

export default class AccountsTabOceList extends LightningElement {
    @api rows = [];
    @api isLoading = false;
    @api sortBy;
    @api sortDirection;

    get displayRows() {
        return (this.rows || []).map((row) => {
            const pinKind = resolveAccountPinKind(
                row.recordTypeDeveloperName,
                row.recordTypeName
            );
            return {
                ...row,
                pinKind,
                typeIconName: pinKind === 'hco' ? 'standard:account' : 'standard:contact',
                pinLabel: pinKind === 'hco' ? 'HCO' : 'HCP',
                typeIconClass:
                    pinKind === 'hco' ? 'account-type-icon-hco' : 'account-type-icon-hcp',
                riskDotClass: RISK_DOT_CLASS[row.agentforceRisk] || RISK_DOT_CLASS.Low,
                classificationVariant:
                    CLASSIFICATION_VARIANT[row.classification] || 'inverse',
                targetLabel: row.inPlanCycle ? 'Yes' : 'No',
                targetBadgeClass: row.inPlanCycle ? 'target-yes' : 'target-no',
                callPlanLabel: row.inPlanCycle && row.targetVisits != null
                    ? `${row.actualVisits || 0}/${row.targetVisits}`
                    : '—',
                plannedPlanLabel: row.inPlanCycle && row.targetVisits != null
                    ? `Planned ${row.plannedVisits || 0}/${row.targetVisits}`
                    : '—',
                hasLastCall: row.lastVisitDate != null,
                hasNextCall: row.nextVisitDate != null,
                specialtyDisplay: row.specialty || '—'
            };
        });
    }

    get sortDirectionIcon() {
        return this.sortDirection === 'asc' ? 'utility:arrowup' : 'utility:arrowdown';
    }

    get sortDirectionLabel() {
        return this.sortDirection === 'asc' ? 'ascending' : 'descending';
    }

    handleRowAction(event) {
        const accountId = event.currentTarget.dataset.id;
        const action = event.detail.value;
        this.dispatchEvent(
            new CustomEvent('rowaction', {
                detail: { accountId, action },
                bubbles: true,
                composed: true
            })
        );
    }

    handleAccountClick(event) {
        event.preventDefault();
        const accountId = event.currentTarget.dataset.id;
        this.dispatchEvent(
            new CustomEvent('rowaction', {
                detail: { accountId, action: 'view' },
                bubbles: true,
                composed: true
            })
        );
    }

    handleSortToggle() {
        this.dispatchEvent(new CustomEvent('sorttoggle'));
    }
}
