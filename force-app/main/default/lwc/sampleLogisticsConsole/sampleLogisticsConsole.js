import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getBootstrap from '@salesforce/apex/SampleSupplyChainController.getBootstrap';
import submitRequest from '@salesforce/apex/SampleSupplyChainController.submitRequest';
import cancelRequest from '@salesforce/apex/SampleSupplyChainController.cancelRequest';
import allocateRequest from '@salesforce/apex/SampleSupplyChainController.allocateRequest';
import transfer from '@salesforce/apex/SampleSupplyChainController.transfer';
import returnToSupply from '@salesforce/apex/SampleSupplyChainController.returnToSupply';

const EMPTY_ALLOCATE = {
    requestId: '',
    requestLabel: '',
    remaining: 0,
    repUserId: '',
    lotNumber: '',
    expiryDate: '',
    quantity: null,
    notes: ''
};

export default class SampleLogisticsConsole extends LightningElement {
    @track products = [];
    @track reps = [];
    @track requests = [];
    @track inventory = [];
    isLoading = false;
    isSaving = false;
    errorMessage = '';

    requestProductId = '';
    requestQuantity = 10;
    requestTargetRepId = '';
    requestNotes = '';

    showAllocate = false;
    allocateForm = { ...EMPTY_ALLOCATE };

    showMove = false;
    moveMode = 'transfer';
    moveInventoryId = '';
    moveLabel = '';
    moveMax = 0;
    moveRepId = '';
    moveQuantity = null;
    moveNotes = '';

    connectedCallback() {
        this.refresh();
    }

    get hasProducts() {
        return (this.products || []).length > 0;
    }

    get hasRequests() {
        return (this.requests || []).length > 0;
    }

    get hasInventory() {
        return (this.inventory || []).length > 0;
    }

    get isBusy() {
        return this.isLoading || this.isSaving;
    }

    get isSubmitDisabled() {
        return this.isBusy || !this.requestProductId || !this.requestQuantity;
    }

    get todayIso() {
        const d = new Date();
        const pad = (n) => String(n).padStart(2, '0');
        return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
    }

    get isAllocateDisabled() {
        const qty = Number(this.allocateForm.quantity);
        const remaining = Number(this.allocateForm.remaining);
        return (
            this.isBusy ||
            !this.allocateForm.repUserId ||
            !this.allocateForm.lotNumber ||
            !this.allocateForm.expiryDate ||
            this.allocateForm.expiryDate < this.todayIso || // never allocate an expired lot
            !Number.isInteger(qty) ||
            qty < 1 ||
            (remaining > 0 && qty > remaining)
        );
    }

    get isMoveDisabled() {
        const qty = Number(this.moveQuantity);
        if (this.isBusy || !Number.isInteger(qty) || qty < 1 || (this.moveMax > 0 && qty > this.moveMax)) {
            return true;
        }
        return this.moveMode === 'transfer' && !this.moveRepId;
    }

    get moveTitle() {
        return this.moveMode === 'return' ? 'Return to supply chain' : 'Transfer lot';
    }

    get moveSubmitLabel() {
        return this.moveMode === 'return' ? 'Return' : 'Transfer';
    }

    get showMoveRep() {
        return this.moveMode === 'transfer';
    }

    async refresh() {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const data = await getBootstrap();
            this.products = data?.products || [];
            this.reps = data?.reps || [];
            this.requests = (data?.requests || []).map((row) => this.mapRequest(row));
            this.inventory = (data?.inventory || []).map((row) => this.mapInventory(row));
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    mapRequest(row) {
        const remaining = Number(row.quantityRemaining || 0);
        return {
            ...row,
            remaining,
            requestedLabel: `${row.quantityAllocated || 0} / ${row.quantityRequested || 0}`,
            submittedLabel: this.formatDate(row.submittedDate),
            statusClass: this.statusClass(row.status),
            rowClass: row.canAllocate ? 'data-row' : 'data-row data-row--muted'
        };
    }

    mapInventory(row) {
        return {
            ...row,
            expiryLabel: this.formatDate(row.expiryDate),
            rowClass: row.expired ? 'data-row data-row--expired' : 'data-row'
        };
    }

    statusClass(status) {
        if (status === 'Allocated') {
            return 'status-pill status-pill--done';
        }
        if (status === 'Partially Allocated') {
            return 'status-pill status-pill--partial';
        }
        if (status === 'Cancelled') {
            return 'status-pill status-pill--cancel';
        }
        return 'status-pill status-pill--open';
    }

    formatDate(value) {
        if (!value) {
            return '—';
        }
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) {
            return String(value);
        }
        return date.toLocaleDateString();
    }

    handleRequestField(event) {
        const field = event.target.dataset.field;
        const value = event.detail?.value ?? event.target.value;
        if (field === 'product') {
            this.requestProductId = value;
        } else if (field === 'quantity') {
            this.requestQuantity = value ? Number(value) : null;
        } else if (field === 'rep') {
            this.requestTargetRepId = value;
        } else if (field === 'notes') {
            this.requestNotes = value;
        }
    }

    async handleSubmitRequest() {
        this.isSaving = true;
        this.errorMessage = '';
        try {
            await submitRequest({
                product2Id: this.requestProductId,
                quantity: this.requestQuantity,
                targetRepUserId: this.requestTargetRepId || null,
                notes: this.requestNotes
            });
            this.requestNotes = '';
            this.toast('Request submitted', 'Supply Chain can now allocate lots to reps.', 'success');
            await this.refresh();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    async handleCancelRequest(event) {
        const requestId = event.currentTarget.dataset.id;
        this.isSaving = true;
        try {
            await cancelRequest({ requestId });
            this.toast('Request cancelled', '', 'success');
            await this.refresh();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    openAllocate(event) {
        const requestId = event.currentTarget.dataset.id;
        const request = this.requests.find((row) => row.id === requestId);
        if (!request) {
            return;
        }
        this.allocateForm = {
            requestId: request.id,
            requestLabel: `${request.name} · ${request.productName} · ${request.remaining} remaining`,
            remaining: request.remaining,
            repUserId: request.targetRepId || '',
            lotNumber: '',
            expiryDate: '',
            quantity: request.remaining,
            notes: ''
        };
        this.showAllocate = true;
    }

    closeAllocate() {
        this.showAllocate = false;
        this.allocateForm = { ...EMPTY_ALLOCATE };
    }

    handleAllocateField(event) {
        const field = event.target.dataset.field;
        const value = event.detail?.value ?? event.target.value;
        this.allocateForm = { ...this.allocateForm, [field]: value };
    }

    async handleAllocateSave() {
        this.isSaving = true;
        this.errorMessage = '';
        try {
            await allocateRequest({
                requestId: this.allocateForm.requestId,
                repUserId: this.allocateForm.repUserId,
                lotNumber: this.allocateForm.lotNumber,
                expiryDate: this.allocateForm.expiryDate,
                quantity: Number(this.allocateForm.quantity),
                notes: this.allocateForm.notes
            });
            this.closeAllocate();
            this.toast('Allocated', 'Rep inventory updated by product, lot, and expiry.', 'success');
            await this.refresh();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
            this.toast('Could not save', this.errorMessage, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    openTransfer(event) {
        this.openMove(event.currentTarget.dataset.id, 'transfer');
    }

    openReturn(event) {
        this.openMove(event.currentTarget.dataset.id, 'return');
    }

    openMove(inventoryId, mode) {
        const row = this.inventory.find((item) => item.inventoryId === inventoryId);
        if (!row) {
            return;
        }
        this.moveMode = mode;
        this.moveInventoryId = row.inventoryId;
        this.moveLabel = `${row.productName} · Lot ${row.lotNumber} · ${row.ownerUserName} (${row.quantityOnHand} on hand)`;
        this.moveMax = row.quantityOnHand;
        this.moveRepId = '';
        this.moveQuantity = row.quantityOnHand;
        this.moveNotes = '';
        this.showMove = true;
    }

    closeMove() {
        this.showMove = false;
        this.moveInventoryId = '';
    }

    handleMoveField(event) {
        const field = event.target.dataset.field;
        const value = event.detail?.value ?? event.target.value;
        if (field === 'rep') {
            this.moveRepId = value;
        } else if (field === 'quantity') {
            this.moveQuantity = value ? Number(value) : null;
        } else if (field === 'notes') {
            this.moveNotes = value;
        }
    }

    async handleMoveSave() {
        this.isSaving = true;
        this.errorMessage = '';
        try {
            if (this.moveMode === 'return') {
                await returnToSupply({
                    inventoryId: this.moveInventoryId,
                    quantity: Number(this.moveQuantity),
                    notes: this.moveNotes
                });
                this.toast('Returned', 'Quantity returned to supply chain.', 'success');
            } else {
                await transfer({
                    fromInventoryId: this.moveInventoryId,
                    toRepUserId: this.moveRepId,
                    quantity: Number(this.moveQuantity),
                    notes: this.moveNotes
                });
                this.toast('Transferred', 'Lot moved between reps.', 'success');
            }
            this.closeMove();
            await this.refresh();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
            this.toast('Could not save', this.errorMessage, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (!error) {
            return 'Something went wrong.';
        }
        if (Array.isArray(error.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        if (error.body?.message) {
            return error.body.message;
        }
        return error.message || 'Something went wrong.';
    }
}