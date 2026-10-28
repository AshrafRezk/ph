import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProductCatalogTree from '@salesforce/apex/ProductCatalogAdminController.getProductCatalogTree';
import getTerritoryTreeForProduct from '@salesforce/apex/ProductCatalogAdminController.getTerritoryTreeForProduct';
import saveProductTerritoryAlignments from '@salesforce/apex/ProductCatalogAdminController.saveProductTerritoryAlignments';
import getEditorOptions from '@salesforce/apex/ProductEditorController.getEditorOptions';
import getProduct from '@salesforce/apex/ProductEditorController.getProduct';
import saveProduct from '@salesforce/apex/ProductEditorController.saveProduct';

const PARENT_TYPES = {
    Brand: [],
    Detail: ['Brand'],
    Sample: ['Brand', 'Detail'],
    'Brand Reminder': ['Brand', 'Detail']
};
const NUMBER_FIELDS = new Set(['boxQuantity', 'publicPrice']);
const CHECKBOX_FIELDS = new Set(['showInHcpApp', 'isActive']);

function blankDraft() {
    return { productType: 'Detail', isActive: true, showInHcpApp: false };
}

export default class ProductTerritoryManager extends NavigationMixin(LightningElement) {
    productRoots = [];
    territoryRoots = [];
    productFlatRows = [];
    territoryFlatRows = [];
    productExpandedKeys = new Set();
    territoryExpandedIds = new Set();
    // While a search is active, rows open by default along the path to each match.
    // These sets hold the rows the user has flipped from that default; they reset when the search changes.
    productSearchToggledKeys = new Set();
    territorySearchToggledIds = new Set();
    selectedProductId;
    selectedProductLabel = '';
    selectedTerritoryIds = new Set();
    productSearchTerm = '';
    territorySearchTerm = '';
    cascadeToChildren = true;
    isLoadingTerritories = false;
    isSaving = false;
    hasUnsavedChanges = false;
    wiredCatalogResult;
    showEditor = false;
    isEditorLoading = false;
    isEditorSaving = false;
    editorOptions;
    draft = blankDraft();

    @wire(getProductCatalogTree)
    wiredProducts(result) {
        this.wiredCatalogResult = result;
        const { data, error } = result;
        if (data) {
            this.productRoots = data;
            this.initializeProductExpanded();
            this.rebuildProductRows();
        } else if (error) {
            this.productRoots = [];
            this.productFlatRows = [];
            this.toast('Product catalog error', this.reduceError(error), 'error');
        }
    }

    get hasProducts() {
        return this.productFlatRows.length > 0;
    }

    get hasTerritories() {
        return this.territoryFlatRows.length > 0;
    }

    get hasProductSearch() {
        return Boolean((this.productSearchTerm || '').trim());
    }

    get hasTerritorySearch() {
        return Boolean((this.territorySearchTerm || '').trim());
    }

    get showTerritoryPane() {
        return Boolean(this.selectedProductId);
    }

    get territoryPaneTitle() {
        return this.selectedProductLabel
            ? `Territory Distribution — ${this.selectedProductLabel}`
            : 'Territory Distribution';
    }

    get isViewProductDisabled() {
        return !this.selectedProductId;
    }

    get isSaveDisabled() {
        return !this.selectedProductId || this.isSaving || !this.hasUnsavedChanges;
    }

    get selectedAlignmentCount() {
        return this.selectedTerritoryIds.size;
    }

    initializeProductExpanded() {
        if (this.productExpandedKeys.size > 0) {
            return;
        }
        for (const root of this.productRoots) {
            this.productExpandedKeys.add(root.key);
        }
        this.productExpandedKeys = new Set(this.productExpandedKeys);
    }

    initializeTerritoryExpanded() {
        this.territoryExpandedIds = new Set();
        for (const root of this.territoryRoots) {
            this.territoryExpandedIds.add(String(root.id));
            if (root.children) {
                for (const child of root.children) {
                    this.territoryExpandedIds.add(String(child.id));
                }
            }
        }
    }

    rebuildProductRows() {
        const term = (this.productSearchTerm || '').trim().toLowerCase();
        const rows = [];
        for (const root of this.productRoots) {
            this.flattenProductNode(root, 0, rows, term);
        }
        this.productFlatRows = rows;
    }

    nodeMatchesSearch(node, term) {
        if (!term) {
            return true;
        }
        return (
            (node.label || '').toLowerCase().includes(term) ||
            (node.productCode || '').toLowerCase().includes(term) ||
            (node.externalId || '').toLowerCase().includes(term) ||
            (node.productType || '').toLowerCase().includes(term) ||
            (node.salesLine || '').toLowerCase().includes(term) ||
            (node.therapyArea || '').toLowerCase().includes(term)
        );
    }

    buildProductMetaLine(node) {
        return [
            node.productType || 'No type',
            node.salesLine,
            node.externalId,
            node.therapyArea,
            node.isActive === false ? 'Inactive' : null
        ]
            .filter(Boolean)
            .join(' · ');
    }

    /**
     * Adds the node (and its visible descendants) to rows.
     * A search keeps a row when it matches, when a descendant matches, or when an ancestor matched,
     * so searching a brand still lets you open it and see all its details and samples.
     * Returns true when this node or a descendant matches the search.
     */
    flattenProductNode(node, depth, rows, term, ancestorMatched = false) {
        const matches = Boolean(term) && this.nodeMatchesSearch(node, term);
        const childRows = [];
        let descendantMatches = false;
        for (const child of node.children || []) {
            if (this.flattenProductNode(child, depth + 1, childRows, term, ancestorMatched || matches)) {
                descendantMatches = true;
            }
        }
        const onMatchPath = matches || descendantMatches;
        if (term && !onMatchPath && !ancestorMatched) {
            return false;
        }

        const hasChildren = Boolean(node.children && node.children.length > 0);
        const expanded = term
            ? onMatchPath !== this.productSearchToggledKeys.has(node.key)
            : this.productExpandedKeys.has(node.key);
        const isSelected = node.productId === this.selectedProductId;
        const isInactive = node.isActive === false;
        rows.push({
            key: node.key,
            rowKey: node.key,
            label: node.label,
            nodeType: node.nodeType,
            productId: node.productId,
            therapyArea: node.therapyArea,
            productCode: node.productCode,
            externalId: node.externalId,
            productType: node.productType,
            salesLine: node.salesLine,
            isInactive,
            imageUrl: node.imageUrl,
            metaLine: this.buildProductMetaLine(node),
            depth,
            depthStyle: `padding-left: ${depth * 1.25}rem`,
            hasChildren,
            expanded,
            chevronIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
            isSelected,
            rowClass: ['tree-row', isSelected ? 'tree-row--selected' : '', isInactive ? 'tree-row--inactive' : '']
                .filter(Boolean)
                .join(' ')
        });

        if (expanded) {
            rows.push(...childRows);
        }
        return onMatchPath;
    }

    rebuildTerritoryRows() {
        const term = (this.territorySearchTerm || '').trim().toLowerCase();
        const rows = [];
        for (const root of this.territoryRoots) {
            this.flattenTerritoryNode(root, 0, rows, term);
        }
        this.territoryFlatRows = rows;
    }

    /**
     * Same search rules as the product tree: a matching line keeps all its districts and positions,
     * and the expand arrow still opens and closes rows while a search is active.
     */
    flattenTerritoryNode(node, depth, rows, term, ancestorMatched = false) {
        const nameMatches = Boolean(term) && (node.name || '').toLowerCase().includes(term);
        const childRows = [];
        let descendantMatches = false;
        for (const child of node.children || []) {
            if (this.flattenTerritoryNode(child, depth + 1, childRows, term, ancestorMatched || nameMatches)) {
                descendantMatches = true;
            }
        }
        const onMatchPath = nameMatches || descendantMatches;
        if (term && !onMatchPath && !ancestorMatched) {
            return false;
        }

        const nodeId = String(node.id);
        const expanded = term
            ? onMatchPath !== this.territorySearchToggledIds.has(nodeId)
            : this.territoryExpandedIds.has(nodeId);
        const checked = this.selectedTerritoryIds.has(String(node.id));
        rows.push({
            key: node.id,
            id: node.id,
            name: node.name,
            depth,
            depthStyle: `padding-left: ${depth * 1.25}rem`,
            hasChildren: node.hasChildren,
            expanded,
            chevronIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
            checked,
            checkboxLabel: node.name
        });

        if (expanded) {
            rows.push(...childRows);
        }
        return onMatchPath;
    }

    handleProductSearch(event) {
        this.productSearchTerm = event.target.value || '';
        this.productSearchToggledKeys = new Set();
        this.rebuildProductRows();
    }

    handleTerritorySearch(event) {
        this.territorySearchTerm = event.target.value || '';
        this.territorySearchToggledIds = new Set();
        this.rebuildTerritoryRows();
    }

    toggleKey(set, key) {
        const next = new Set(set);
        if (next.has(key)) {
            next.delete(key);
        } else {
            next.add(key);
        }
        return next;
    }

    handleProductToggle(event) {
        const nodeKey = String(event.currentTarget.dataset.key);
        if (this.hasProductSearch) {
            this.productSearchToggledKeys = this.toggleKey(this.productSearchToggledKeys, nodeKey);
        } else {
            this.productExpandedKeys = this.toggleKey(this.productExpandedKeys, nodeKey);
        }
        this.rebuildProductRows();
    }

    // Opens the product record in a new browser tab so the Products Manager stays open where it was.
    async handleViewProduct() {
        if (!this.selectedProductId) {
            return;
        }
        const pageRef = {
            type: 'standard__recordPage',
            attributes: {
                recordId: this.selectedProductId,
                objectApiName: 'Product2',
                actionName: 'view'
            }
        };
        let opened = null;
        try {
            const url = await this[NavigationMixin.GenerateUrl](pageRef);
            if (url) {
                opened = window.open(url, '_blank');
            }
        } catch {
            opened = null;
        }
        if (!opened) {
            // Pop-up blocked or no URL: fall back to opening the record in this tab.
            this[NavigationMixin.Navigate](pageRef);
        }
    }

    async handleProductSelect(event) {
        const productId = event.currentTarget.dataset.id;
        const productLabel = event.currentTarget.dataset.label;
        if (!productId || productId === this.selectedProductId) {
            return;
        }
        if (this.hasUnsavedChanges) {
            const confirmed = window.confirm('You have unsaved territory changes. Discard them and switch product?');
            if (!confirmed) {
                return;
            }
        }
        this.selectedProductId = productId;
        this.selectedProductLabel = productLabel;
        this.hasUnsavedChanges = false;
        this.rebuildProductRows();
        await this.loadTerritoryTree();
    }

    async loadTerritoryTree() {
        if (!this.selectedProductId) {
            this.territoryRoots = [];
            this.territoryFlatRows = [];
            this.selectedTerritoryIds = new Set();
            return;
        }
        this.isLoadingTerritories = true;
        try {
            const tree = await getTerritoryTreeForProduct({ productId: this.selectedProductId });
            this.territoryRoots = tree || [];
            this.selectedTerritoryIds = this.collectAlignedIds(this.territoryRoots);
            this.initializeTerritoryExpanded();
            this.rebuildTerritoryRows();
        } catch (error) {
            this.territoryRoots = [];
            this.territoryFlatRows = [];
            this.toast('Territory load failed', this.reduceError(error), 'error');
        } finally {
            this.isLoadingTerritories = false;
        }
    }

    collectAlignedIds(nodes) {
        const ids = new Set();
        const walk = (nodeList) => {
            for (const node of nodeList || []) {
                if (node.aligned) {
                    ids.add(String(node.id));
                }
                walk(node.children);
            }
        };
        walk(nodes);
        return ids;
    }

    findTerritoryNode(nodes, territoryId) {
        for (const node of nodes || []) {
            if (String(node.id) === String(territoryId)) {
                return node;
            }
            const match = this.findTerritoryNode(node.children, territoryId);
            if (match) {
                return match;
            }
        }
        return null;
    }

    collectDescendantIds(node) {
        const ids = [];
        const walk = (current) => {
            if (!current) {
                return;
            }
            ids.push(String(current.id));
            for (const child of current.children || []) {
                walk(child);
            }
        };
        walk(node);
        return ids;
    }

    handleTerritoryExpand(event) {
        const territoryId = String(event.currentTarget.dataset.id);
        if (this.hasTerritorySearch) {
            this.territorySearchToggledIds = this.toggleKey(this.territorySearchToggledIds, territoryId);
        } else {
            this.territoryExpandedIds = this.toggleKey(this.territoryExpandedIds, territoryId);
        }
        this.rebuildTerritoryRows();
    }

    handleCascadeToggle(event) {
        this.cascadeToChildren = event.target.checked;
    }

    handleTerritoryCheck(event) {
        const territoryId = event.target.dataset.id;
        const checked = event.target.checked;
        const node = this.findTerritoryNode(this.territoryRoots, territoryId);
        const targetIds = this.cascadeToChildren && node
            ? this.collectDescendantIds(node)
            : [String(territoryId)];

        const next = new Set(this.selectedTerritoryIds);
        for (const id of targetIds) {
            if (checked) {
                next.add(id);
            } else {
                next.delete(id);
            }
        }
        this.selectedTerritoryIds = next;
        this.hasUnsavedChanges = true;
        this.rebuildTerritoryRows();
    }

    async handleSave() {
        if (!this.selectedProductId) {
            return;
        }
        this.isSaving = true;
        try {
            const territoryIds = Array.from(this.selectedTerritoryIds);
            await saveProductTerritoryAlignments({
                productId: this.selectedProductId,
                territoryIds
            });
            this.hasUnsavedChanges = false;
            await this.loadTerritoryTree();
            this.toast(
                'Alignment saved',
                `${territoryIds.length} territor${territoryIds.length === 1 ? 'y' : 'ies'} aligned to ${this.selectedProductLabel}.`,
                'success'
            );
        } catch (error) {
            this.toast('Save failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    get isEditing() {
        return Boolean(this.draft.id);
    }

    get editorTitle() {
        return this.isEditing ? `Edit product — ${this.draft.name || ''}` : 'New product';
    }

    get productTypeOptions() {
        return this.editorOptions?.productTypes || [];
    }

    get salesLineOptions() {
        return [{ label: 'None', value: '' }, ...(this.editorOptions?.salesLines || [])];
    }

    get reminderKindOptions() {
        return this.editorOptions?.reminderKinds || [];
    }

    get allowedParentTypes() {
        return PARENT_TYPES[this.draft.productType] || [];
    }

    get needsParent() {
        return this.allowedParentTypes.length > 0;
    }

    get parentLabel() {
        return `Belongs to (${this.allowedParentTypes.join(' or ')})`;
    }

    get parentOptions() {
        const allowed = new Set(this.allowedParentTypes);
        return (this.editorOptions?.parents || [])
            .filter((o) => allowed.has(o.productType) && o.value !== this.draft.id)
            .map((o) => ({ label: `${o.label} · ${o.productType}`, value: o.value }));
    }

    get showPackFields() {
        return this.draft.productType === 'Detail' || this.draft.productType === 'Sample';
    }

    get isReminder() {
        return this.draft.productType === 'Brand Reminder';
    }

    get isEditorSaveDisabled() {
        const d = this.draft;
        return (
            this.isEditorSaving ||
            this.isEditorLoading ||
            !d.name ||
            !d.productType ||
            (!this.isEditing && !d.productCode) ||
            (this.needsParent && !d.parentId)
        );
    }

    async loadEditorOptions() {
        this.editorOptions = await getEditorOptions();
    }

    async handleNewProduct() {
        this.draft = blankDraft();
        this.showEditor = true;
        this.isEditorLoading = true;
        try {
            await this.loadEditorOptions();
        } catch (error) {
            this.showEditor = false;
            this.toast('Product form error', this.reduceError(error), 'error');
        } finally {
            this.isEditorLoading = false;
        }
    }

    async handleEditProduct() {
        if (!this.selectedProductId) {
            return;
        }
        this.showEditor = true;
        this.isEditorLoading = true;
        try {
            const [product] = await Promise.all([
                getProduct({ productId: this.selectedProductId }),
                this.loadEditorOptions()
            ]);
            this.draft = { ...product };
        } catch (error) {
            this.showEditor = false;
            this.toast('Product load failed', this.reduceError(error), 'error');
        } finally {
            this.isEditorLoading = false;
        }
    }

    handleDraftChange(event) {
        const field = event.target.dataset.field;
        let value = CHECKBOX_FIELDS.has(field) ? event.target.checked : event.detail.value;
        if (NUMBER_FIELDS.has(field)) {
            value = value === '' || value == null ? null : Number(value);
        }
        const next = { ...this.draft, [field]: value };
        if (field === 'productType' && !(PARENT_TYPES[value] || []).length) {
            next.parentId = null;
        }
        this.draft = next;
    }

    handleCloseEditor() {
        this.showEditor = false;
    }

    async handleSaveProduct() {
        this.isEditorSaving = true;
        const wasNew = !this.isEditing;
        try {
            const productId = await saveProduct({ form: { ...this.draft, salesLine: this.draft.salesLine || null } });
            this.showEditor = false;
            await refreshApex(this.wiredCatalogResult);
            this.selectedProductId = productId;
            this.selectedProductLabel = this.draft.name;
            this.hasUnsavedChanges = false;
            this.rebuildProductRows();
            await this.loadTerritoryTree();
            this.toast(
                wasNew ? 'Product created' : 'Product saved',
                wasNew
                    ? `${this.draft.name} is in the catalog. Tick its territories on the right, then Save Alignment.`
                    : `${this.draft.name} was updated.`,
                'success'
            );
        } catch (error) {
            this.toast('Product not saved', this.reduceError(error), 'error');
        } finally {
            this.isEditorSaving = false;
        }
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unknown error';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}