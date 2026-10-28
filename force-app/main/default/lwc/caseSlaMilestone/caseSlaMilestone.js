import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import getSlaMilestone from '@salesforce/apex/CaseSlaController.getSlaMilestone';
import CASE_IS_CLOSED from '@salesforce/schema/Case.IsClosed';
import CASE_STAGE_START from '@salesforce/schema/Case.Stage_Start_Time__c';
import CASE_STAGE_DUE from '@salesforce/schema/Case.Stage_Due__c';

const CASE_FIELDS = [CASE_IS_CLOSED, CASE_STAGE_START, CASE_STAGE_DUE];

function formatDuration(totalMinutes) {
    const minutes = Math.max(0, Math.floor(totalMinutes));
    const hours = Math.floor(minutes / 60);
    const remainder = minutes % 60;
    if (hours > 0) {
        return `${hours}h ${remainder}m`;
    }
    return `${remainder}m`;
}

function buildLocalView(stageStart, stageDue, isClosed) {
    if (!stageStart) {
        return {
            statusLabel: 'NOT STARTED',
            statusVariant: 'base',
            elapsedLabel: '—',
            dueInLabel: '—',
            isClosed: false
        };
    }

    const now = Date.now();
    const startMs = new Date(stageStart).getTime();
    const elapsedMinutes = Math.max(0, Math.floor((now - startMs) / 60000));
    const elapsedLabel = `Elapsed: ${formatDuration(elapsedMinutes)}`;

    if (isClosed) {
        return {
            statusLabel: 'COMPLETED',
            statusVariant: 'base',
            elapsedLabel,
            dueInLabel: null,
            isClosed: true
        };
    }

    if (!stageDue) {
        return {
            statusLabel: 'ON TRACK',
            statusVariant: 'success',
            elapsedLabel,
            dueInLabel: '—',
            isClosed: false
        };
    }

    const dueMs = new Date(stageDue).getTime();
    const dueInMinutes = Math.floor((dueMs - now) / 60000);
    const totalMinutes = Math.max(1, Math.floor((dueMs - startMs) / 60000));

    if (dueInMinutes < 0) {
        return {
            statusLabel: 'VIOLATED',
            statusVariant: 'error',
            elapsedLabel,
            dueInLabel: `Overdue by: ${formatDuration(Math.abs(dueInMinutes))}`,
            isClosed: false
        };
    }

    const atRisk = dueInMinutes <= totalMinutes * 0.2;
    return {
        statusLabel: atRisk ? 'AT RISK' : 'ON TRACK',
        statusVariant: atRisk ? 'warning' : 'success',
        elapsedLabel,
        dueInLabel: `Due in: ${formatDuration(dueInMinutes)}`,
        isClosed: false
    };
}

export default class CaseSlaMilestone extends LightningElement {
    @api recordId;

    milestone;
    wiredMilestoneResult;
    timerId;

    @wire(getRecord, { recordId: '$recordId', fields: CASE_FIELDS })
    wiredCase;

    @wire(getSlaMilestone, { caseId: '$recordId' })
    wiredMilestone(result) {
        this.wiredMilestoneResult = result;
        if (result.data) {
            this.milestone = result.data;
        } else if (result.error) {
            this.milestone = undefined;
        }
    }

    connectedCallback() {
        this.timerId = window.setInterval(() => {
            this.refreshLocalMilestone();
        }, 60000);
    }

    disconnectedCallback() {
        if (this.timerId) {
            window.clearInterval(this.timerId);
        }
    }

    refreshLocalMilestone() {
        const stageStart = getFieldValue(this.wiredCase.data, CASE_STAGE_START);
        const stageDue = getFieldValue(this.wiredCase.data, CASE_STAGE_DUE);
        const isClosed = getFieldValue(this.wiredCase.data, CASE_IS_CLOSED);
        if (stageStart) {
            this.milestone = buildLocalView(stageStart, stageDue, isClosed);
        } else if (this.wiredMilestoneResult) {
            refreshApex(this.wiredMilestoneResult);
        }
    }

    get hasMilestone() {
        return !!this.milestone;
    }

    get cardClass() {
        const variant = this.milestone?.statusVariant || 'base';
        return `sla-card sla-card-${variant}`;
    }

    get showDueIn() {
        return this.milestone?.dueInLabel && !this.milestone?.isClosed;
    }
}