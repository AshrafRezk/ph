import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCsvTemplate from '@salesforce/apex/PharmacySalesDataAdminController.getCsvTemplate';
import previewSalesDataCsv from '@salesforce/apex/PharmacySalesDataAdminController.previewSalesDataCsv';
import importSalesDataCsv from '@salesforce/apex/PharmacySalesDataAdminController.importSalesDataCsv';
import getWithdrawalRows from '@salesforce/apex/PharmacySalesDataAdminController.getWithdrawalRows';
import getImportBatches from '@salesforce/apex/PharmacySalesDataAdminController.getImportBatches';
import deleteWithdrawalRows from '@salesforce/apex/PharmacySalesDataAdminController.deleteWithdrawalRows';
import seedDemoData from '@salesforce/apex/PharmacySalesDataAdminController.seedDemoData';
import seedDigestionExample from '@salesforce/apex/PharmacySalesDataAdminController.seedDigestionExample';
import getDigestionExample from '@salesforce/apex/PharmacySalesDataAdminController.getDigestionExample';
import getEditorState from '@salesforce/apex/SalesSobAdminController.getEditorState';
import saveDefaultSob from '@salesforce/apex/SalesSobAdminController.saveDefaultSob';
import saveItemSob from '@salesforce/apex/SalesSobAdminController.saveItemSob';
import clearItemSob from '@salesforce/apex/SalesSobAdminController.clearItemSob';
import searchProducts from '@salesforce/apex/SalesSobAdminController.searchProducts';

const TABS = [
    { id: 'import', label: 'Import' },
    { id: 'viewer', label: 'Viewer' },
    { id: 'sob', label: 'Item SOB' },
    { id: 'digestion', label: 'Digestion example' }
];

const DIGESTION_STEPS = [
    '1. Doctor class this month versus last month (absolute movement)',
    '2. Affiliated pharmacies on the brick',
    '3. Distributor quantity on each pharmacy (subtype + brick)',
    '4. Item ceiling: keep up to the cap; excess moves to bulk',
    '5. Pharmacies marked “Does not enter the ceiling” keep the full quantity',
    '6. Bulk share = average of actual and target contribution × bulk quantity',
    '7. Effective target = buffer when shortage is off; attained when shortage is on'
];

export default class PharmacySalesDataAdmin extends LightningElement {
    @track activeTab = 'import';
    @track csvContent = '';
    @track fileName = '';
    @track previewRows = [];
    @track importResult;
    @track isImporting = false;
    @track isPreviewing = false;
    @track viewerRows = [];
    @track batchRows = [];
    @track selectedViewerRows = [];
    @track sobState;
    @track productOptions = [];
    @track selectedProductId = '';
    @track itemPercent = '';
    @track defaultPercent = '';
    @track digestionExample = {
        seeded: false,
        message: 'No digestion example yet. Press Load example.',
        pharmacies: [],
        steps: DIGESTION_STEPS
    };
    @track digestionBusy = false;

    viewerColumns = [
        { label: 'Month', fieldName: 'reportMonth', type: 'text' },
        { label: 'Source', fieldName: 'dataSource', type: 'text' },
        { label: 'Pharmacy', fieldName: 'pharmacyName', type: 'text' },
        { label: 'Brick', fieldName: 'brickName', type: 'text' },
        { label: 'Product', fieldName: 'productName', type: 'text' },
        { label: 'Qty', fieldName: 'quantity', type: 'number' },
        { label: 'Revenue', fieldName: 'revenue', type: 'currency', typeAttributes: { currencyCode: 'EGP' } }
    ];

    batchColumns = [
        { label: 'File', fieldName: 'fileName', type: 'text' },
        { label: 'Inserted', fieldName: 'rowsInserted', type: 'number' },
        { label: 'Updated', fieldName: 'rowsUpdated', type: 'number' },
        { label: 'Failed', fieldName: 'rowsFailed', type: 'number' }
    ];

    get tabs() {
        return TABS.map((tab) => ({
            ...tab,
            className: `tab-btn${this.activeTab === tab.id ? ' tab-btn--active' : ''}`
        }));
    }

    get isImportTab() {
        return this.activeTab === 'import';
    }

    get isViewerTab() {
        return this.activeTab === 'viewer';
    }

    get isSobTab() {
        return this.activeTab === 'sob';
    }

    get isDigestionTab() {
        return this.activeTab === 'digestion';
    }

    get hasDigestionExample() {
        return this.digestionExample?.seeded === true;
    }

    get digestionPharmacies() {
        return this.digestionExample?.pharmacies || [];
    }

    get digestionSteps() {
        return (this.digestionExample?.steps || []).map((label, index) => ({
            key: `step-${index}`,
            label
        }));
    }

    get canEditSob() {
        return this.sobState?.canEdit === true;
    }

    get sobNote() {
        return this.sobState?.note || '';
    }

    get sobItems() {
        return this.sobState?.items || [];
    }

    get hasPreview() {
        return this.previewRows.length > 0;
    }

    get hasImportResult() {
        return Boolean(this.importResult);
    }

    connectedCallback() {
        this.loadViewerData();
        this.loadSob();
        this.loadDigestionExample();
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tabId;
        if (this.activeTab === 'viewer') {
            this.loadViewerData();
        }
        if (this.activeTab === 'sob') {
            this.loadSob();
        }
        if (this.activeTab === 'digestion') {
            this.loadDigestionExample();
        }
    }

    async handleDownloadTemplate() {
        try {
            const template = await getCsvTemplate();
            this.downloadTextFile('pharmacy_sales_template.csv', template);
        } catch (error) {
            this.toast('Template error', this.reduceError(error), 'error');
        }
    }

    async handleFileChange(event) {
        const file = event.target.files?.[0];
        if (!file) {
            return;
        }
        this.fileName = file.name;
        try {
            // LWS blocks File MIME types like text/csv. Read bytes, then decode as UTF-8.
            this.csvContent = await this.readFileAsText(file);
            await this.runPreview();
        } catch (error) {
            this.toast('File read error', this.reduceError(error), 'error');
        }
    }

    async readFileAsText(file) {
        const buffer = await file.arrayBuffer();
        return new TextDecoder('utf-8').decode(buffer);
    }

    async runPreview() {
        if (!this.csvContent) {
            return;
        }
        this.isPreviewing = true;
        try {
            const result = await previewSalesDataCsv({ csvContent: this.csvContent });
            this.previewRows = result.previewRows || [];
            this.importResult = null;
        } catch (error) {
            this.toast('Preview error', this.reduceError(error), 'error');
        } finally {
            this.isPreviewing = false;
        }
    }

    async handleImport() {
        if (!this.csvContent) {
            this.toast('Import', 'Choose a CSV file first.', 'warning');
            return;
        }
        this.isImporting = true;
        try {
            this.importResult = await importSalesDataCsv({
                csvContent: this.csvContent,
                fileName: this.fileName
            });
            this.toast(
                'Import complete',
                `${this.importResult.rowsInserted} inserted, ${this.importResult.rowsUpdated} updated, ${this.importResult.rowsFailed} failed.`,
                this.importResult.rowsFailed > 0 ? 'warning' : 'success'
            );
            await this.loadViewerData();
        } catch (error) {
            this.toast('Import error', this.reduceError(error), 'error');
        } finally {
            this.isImporting = false;
        }
    }

    async loadViewerData() {
        try {
            this.viewerRows = await getWithdrawalRows({
                startMonth: null,
                endMonth: null,
                dataSource: 'All',
                brickId: null,
                rowLimit: 200
            });
            this.batchRows = await getImportBatches({ rowLimit: 20 });
        } catch (error) {
            this.toast('Viewer error', this.reduceError(error), 'error');
        }
    }

    handleViewerSelection(event) {
        this.selectedViewerRows = event.detail.selectedRows.map((row) => row.recordId);
    }

    async handleDeleteSelected() {
        if (!this.selectedViewerRows.length) {
            this.toast('Delete', 'Select rows to delete.', 'warning');
            return;
        }
        try {
            await deleteWithdrawalRows({ recordIds: this.selectedViewerRows });
            this.selectedViewerRows = [];
            await this.loadViewerData();
            this.toast('Deleted', 'Selected withdrawal rows removed.', 'success');
        } catch (error) {
            this.toast('Delete error', this.reduceError(error), 'error');
        }
    }

    async handleSeedDemo() {
        try {
            const result = await seedDemoData();
            this.toast('Demo seed', result.message, 'success');
            await this.loadViewerData();
        } catch (error) {
            this.toast('Seed error', this.reduceError(error), 'error');
        }
    }

    async loadDigestionExample() {
        try {
            this.digestionExample = await getDigestionExample();
        } catch (error) {
            this.toast('Digestion example', this.reduceError(error), 'error');
        }
    }

    async handleLoadDigestionExample() {
        this.digestionBusy = true;
        try {
            this.digestionExample = await seedDigestionExample();
            this.toast('Digestion example', this.digestionExample?.message || 'Loaded.', 'success');
            await this.loadViewerData();
        } catch (error) {
            this.toast('Digestion example', this.reduceError(error), 'error');
        } finally {
            this.digestionBusy = false;
        }
    }

    async loadSob() {
        try {
            this.sobState = await getEditorState();
            this.defaultPercent = this.sobState?.defaultPercent == null ? '' : String(this.sobState.defaultPercent);
            if (!this.productOptions.length) {
                this.productOptions = (await searchProducts({ term: '' })).map((product) => ({
                    label: product.productCode ? `${product.productName} (${product.productCode})` : product.productName,
                    value: product.productId
                }));
            }
        } catch (error) {
            this.toast('SOB', this.reduceError(error), 'error');
        }
    }

    handleDefaultPercentChange(event) {
        this.defaultPercent = event.detail.value;
    }

    handleItemPercentChange(event) {
        this.itemPercent = event.detail.value;
    }

    handleProductChange(event) {
        this.selectedProductId = event.detail.value;
    }

    async handleProductSearch(event) {
        const term = event.detail.value || '';
        try {
            this.productOptions = (await searchProducts({ term })).map((product) => ({
                label: product.productCode ? `${product.productName} (${product.productCode})` : product.productName,
                value: product.productId
            }));
        } catch (error) {
            this.toast('Products', this.reduceError(error), 'error');
        }
    }

    async handleSaveDefault() {
        try {
            this.sobState = await saveDefaultSob({ percent: Number(this.defaultPercent) });
            this.toast('SOB saved', 'Module default share of business updated.', 'success');
        } catch (error) {
            this.toast('SOB', this.reduceError(error), 'error');
        }
    }

    async handleSaveItem() {
        try {
            this.sobState = await saveItemSob({
                productId: this.selectedProductId,
                percent: Number(this.itemPercent)
            });
            this.toast('Item SOB saved', 'This product now uses its own share of business.', 'success');
        } catch (error) {
            this.toast('Item SOB', this.reduceError(error), 'error');
        }
    }

    async handleClearItem(event) {
        try {
            this.sobState = await clearItemSob({ productId: event.currentTarget.dataset.productId });
            this.toast('Item SOB cleared', 'This product falls back to the module default.', 'success');
        } catch (error) {
            this.toast('Item SOB', this.reduceError(error), 'error');
        }
    }

    handleDownloadErrorLog() {
        if (!this.importResult?.errorLog) {
            return;
        }
        this.downloadTextFile('import_errors.txt', this.importResult.errorLog);
    }

    downloadTextFile(fileName, content) {
        // LWS rejects MIME parameters (e.g. charset=utf-8) and non-allowlisted types like text/csv.
        const blob = new Blob([content == null ? '' : String(content)], { type: 'text/plain' });
        const url = URL.createObjectURL(blob);
        const anchor = document.createElement('a');
        anchor.href = url;
        anchor.download = fileName;
        anchor.click();
        URL.revokeObjectURL(url);
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unknown error';
    }
}