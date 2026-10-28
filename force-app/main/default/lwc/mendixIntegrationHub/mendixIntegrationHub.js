import { LightningElement, wire } from 'lwc';
import getRecentSyncLogs from '@salesforce/apex/MendixSyncService.getRecentSyncLogs';
import getIntegrationStatus from '@salesforce/apex/MendixSyncService.getIntegrationStatus';
import exportSyncCsv from '@salesforce/apex/MendixSyncService.exportSyncCsv';
import MENDIX_LOGO from '@salesforce/resourceUrl/Mendix_Logo';

export default class MendixIntegrationHub extends LightningElement {
    mendixLogoUrl = MENDIX_LOGO;
    statusMessage = 'Loading Mendix integration status…';
    logs = [];
    error;

    get hasLogs() {
        return Array.isArray(this.logs) && this.logs.length > 0;
    }

    @wire(getIntegrationStatus)
    wiredStatus({ data, error }) {
        if (data) this.statusMessage = data;
        if (error) this.error = error.body?.message;
    }

    @wire(getRecentSyncLogs)
    wiredLogs({ data, error }) {
        if (data) this.logs = data;
        if (error) this.error = error.body?.message;
    }

    async handleExport() {
        try {
            const csv = await exportSyncCsv();
            const link = document.createElement('a');
            link.href = 'data:text/plain,' + encodeURIComponent(csv || '');
            link.download = 'mendix-sync-export.csv';
            link.click();
        } catch (error) {
            this.error = error?.body?.message || 'Export failed.';
        }
    }
}