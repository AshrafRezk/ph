import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMaterialSummaries from '@salesforce/apex/LearningAdminController.getMaterialSummaries';
import getAssignments from '@salesforce/apex/LearningAdminController.getAssignments';
import createMaterial from '@salesforce/apex/LearningAdminController.createMaterial';
import updateMaterial from '@salesforce/apex/LearningAdminController.updateMaterial';
import assignToUser from '@salesforce/apex/LearningAdminController.assignToUser';
import getTerritoryTreeForMaterial from '@salesforce/apex/LearningAdminController.getTerritoryTreeForMaterial';
import saveTerritoryAlignments from '@salesforce/apex/LearningAdminController.saveTerritoryAlignments';
import getBusinessUnitFilterOptions from '@salesforce/apex/LearningAdminController.getBusinessUnitFilterOptions';
import finalizeMaterialFileUpload from '@salesforce/apex/LearningAdminController.finalizeMaterialFileUpload';

const CHILD_TYPE_OPTIONS = [
    { label: 'Video', value: 'Video' },
    { label: 'PDF', value: 'PDF' },
    { label: 'Lesson', value: 'Lesson' },
    { label: 'Quiz', value: 'Quiz' }
];

export default class LearningModuleManager extends NavigationMixin(LightningElement) {
    searchTerm = '';
    typeFilter = 'All';
    activeFilter = 'All';
    buTerritoryFilter = 'All';
    buTerritoryOptions = [{ label: 'All Territories', value: 'All' }];
    materials = [];
    wiredResult;
    expandedIds = new Set();
    selectedParentId;
    selectedChildId;

    @track editTitle = '';
    @track editDescription = '';
    @track editActive = true;
    @track editDuration;
    @track editMaterialType = 'Course';
    @track editMaterialUrl = '';
    @track assignees = [];
    assigneesLoading = false;
    assignUserId;

    availableFrom = null;
    availableUntil = null;

    territoryRoots = [];
    territoryFlatRows = [];
    territoryExpandedIds = new Set();
    selectedTerritoryIds = new Set();
    territorySearchTerm = '';
    cascadeToChildren = true;
    isLoadingTerritories = false;
    hasUnsavedTerritoryChanges = false;

    showNewModal = false;
    isSaving = false;
    isUploading = false;
    newTitle = '';
    newType = 'Course';

    typeOptions = [
        { label: 'All', value: 'All' },
        { label: 'Course', value: 'Course' },
        { label: 'Video', value: 'Video' },
        { label: 'PDF', value: 'PDF' },
        { label: 'Lesson', value: 'Lesson' },
        { label: 'Quiz', value: 'Quiz' }
    ];

    activeOptions = [
        { label: 'All', value: 'All' },
        { label: 'Active', value: 'Active' },
        { label: 'Inactive', value: 'Inactive' }
    ];

    newTypeOptions = this.typeOptions.filter((o) => o.value !== 'All');
    childTypeOptions = CHILD_TYPE_OPTIONS;

    @wire(getBusinessUnitFilterOptions)
    wiredBuOptions({ data, error }) {
        if (data) {
            this.buTerritoryOptions = data.map((opt) => ({
                label: opt.label,
                value: opt.value
            }));
        } else if (error) {
            this.buTerritoryOptions = [{ label: 'All Territories', value: 'All' }];
        }
    }

    @wire(getMaterialSummaries, {
        searchTerm: '$searchTerm',
        typeFilter: '$typeFilter',
        activeFilter: '$activeFilter',
        buTerritoryFilter: '$buTerritoryFilter'
    })
    wiredMaterials(result) {
        this.wiredResult = result;
        if (result.data) {
            this.materials = result.data.map((row) => {
                const durationLabel = row.duration != null ? `${row.duration} min` : '-';
                return {
                    ...row,
                    activeLabel: row.isActive ? 'Active' : 'Inactive',
                    durationLabel,
                    metaLabel: [row.materialType, row.isActive ? 'Active' : 'Inactive', durationLabel]
                        .filter(Boolean)
                        .join(' | ')
                };
            });
            this.syncSelectionAfterRefresh();
        } else {
            this.materials = [];
        }
    }

    syncSelectionAfterRefresh() {
        if (this.selectedChildId) {
            const child = this.materials.find((m) => m.id === this.selectedChildId);
            if (!child) {
                this.selectedChildId = null;
            } else {
                this.applyEditFields(child);
                return;
            }
        }
        if (this.selectedParentId) {
            const parent = this.materials.find((m) => m.id === this.selectedParentId);
            if (!parent) {
                this.selectedParentId = null;
                this.assignees = [];
                this.resetTerritoryState();
            } else {
                this.applyEditFields(parent);
                this.loadAssignees(this.selectedParentId);
                this.loadTerritoryTree(this.selectedParentId);
            }
        }
    }

    get accordionGroups() {
        const byId = new Map(this.materials.map((m) => [m.id, m]));
        const childrenByParent = new Map();

        for (const row of this.materials) {
            if (row.parentMaterialId) {
                if (!childrenByParent.has(row.parentMaterialId)) {
                    childrenByParent.set(row.parentMaterialId, []);
                }
                childrenByParent.get(row.parentMaterialId).push(row);
            }
        }

        const roots = this.materials.filter((row) => row.materialType === 'Course');
        const usedChildIds = new Set();
        const groups = roots.map((parent) => {
            const children = childrenByParent.get(parent.id) || [];
            children.forEach((c) => usedChildIds.add(c.id));
            return this.toGroup(parent, children);
        });

        for (const row of this.materials) {
            if (row.materialType === 'Course' || usedChildIds.has(row.id)) {
                continue;
            }
            if (!row.parentMaterialId || !byId.has(row.parentMaterialId)) {
                groups.push(this.toGroup(row, []));
            }
        }
        return groups;
    }

    toGroup(parent, children) {
        const expanded = this.expandedIds.has(parent.id);
        const selected = this.selectedParentId === parent.id && !this.selectedChildId;
        return {
            ...parent,
            children: children.map((c) => ({
                ...c,
                iconName: this.iconForType(c.materialType),
                childClass: `child-row${this.selectedChildId === c.id ? ' is-selected' : ''}`,
                metaLabel: [c.materialType, c.activeLabel, c.durationLabel].join(' | ')
            })),
            childCountLabel: `${children.length} item${children.length === 1 ? '' : 's'}`,
            assignmentLabel: `${parent.assignmentCount || 0} assigned`,
            parentMetaLabel: [
                parent.materialType,
                parent.activeLabel,
                `${children.length} item${children.length === 1 ? '' : 's'}`,
                `${parent.assignmentCount || 0} assigned`
            ].join(' | '),
            expanded,
            selected,
            groupClass: `accordion-item${selected ? ' is-selected' : ''}${expanded ? ' is-expanded' : ''}`,
            chevronIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
            iconName: this.iconForType(parent.materialType),
            hasChildren: children.length > 0
        };
    }

    get hasGroups() {
        return this.accordionGroups.length > 0;
    }

    get selectedParent() {
        return this.selectedParentId
            ? this.materials.find((m) => m.id === this.selectedParentId) || null
            : null;
    }

    get selectedChild() {
        return this.selectedChildId
            ? this.materials.find((m) => m.id === this.selectedChildId) || null
            : null;
    }

    get selectedItem() {
        return this.selectedChild || this.selectedParent;
    }

    get hasSelection() {
        return !!this.selectedItem;
    }

    get isEditingChild() {
        return !!this.selectedChild;
    }

    get isEditingParent() {
        return !!this.selectedParent && !this.selectedChild;
    }

    get isQuizSelected() {
        return this.selectedItem?.materialType === 'Quiz';
    }

    get showUrlField() {
        const type = this.editMaterialType || this.selectedItem?.materialType;
        return type === 'Video' || type === 'PDF' || type === 'Lesson';
    }

    get showFileUpload() {
        return this.showUrlField && !!this.selectedItem?.id;
    }

    get selectedMaterialId() {
        return this.selectedItem?.id || null;
    }

    get fileUploadAccept() {
        const type = this.editMaterialType || this.selectedItem?.materialType;
        if (type === 'Video') {
            return '.mp4,.webm,.mov,.m4v,video/*';
        }
        if (type === 'PDF') {
            return '.pdf';
        }
        return '.mp4,.webm,.mov,.m4v,.pdf,video/*,application/pdf';
    }

    get uploadLabel() {
        const type = this.editMaterialType || this.selectedItem?.materialType;
        if (type === 'Video') {
            return 'Upload video to Salesforce Files';
        }
        if (type === 'PDF') {
            return 'Upload PDF to Salesforce Files';
        }
        return 'Upload file to Salesforce Files';
    }

    get showTypePicker() {
        return this.isEditingChild;
    }

    get detailHeading() {
        if (this.isEditingChild) {
            return 'Edit child material';
        }
        if (this.isEditingParent) {
            return 'Edit parent course';
        }
        return 'Edit material';
    }

    get hasAssignees() {
        return this.assignees.length > 0;
    }

    get assigneeRows() {
        return this.assignees.map((row) => ({
            ...row,
            progressLabel: `${Math.round(row.progress || 0)}%`,
            scoreLabel: row.score == null ? '-' : `${row.score}%`
        }));
    }

    get hasTerritories() {
        return this.territoryFlatRows.length > 0;
    }

    get selectedAlignmentCount() {
        return this.selectedTerritoryIds.size;
    }

    get isNewDisabled() {
        return this.isSaving || !this.newTitle?.trim();
    }

    get isAssignDisabled() {
        return this.isSaving || !this.assignUserId || !this.selectedParentId;
    }

    get isTerritorySaveDisabled() {
        return this.isSaving || !this.selectedParentId || !this.hasUnsavedTerritoryChanges;
    }

    get isSaveDisabled() {
        return this.isSaving || !this.editTitle?.trim();
    }

    iconForType(type) {
        switch (type) {
            case 'Course':
                return 'utility:education';
            case 'Video':
                return 'utility:video';
            case 'PDF':
                return 'utility:file';
            case 'Quiz':
                return 'utility:question';
            case 'Lesson':
                return 'utility:knowledge_base';
            default:
                return 'utility:knowledge_base';
        }
    }

    toIsoDate(value) {
        if (!value) {
            return null;
        }
        if (typeof value === 'string') {
            return value;
        }
        const year = value.getFullYear();
        const month = String(value.getMonth() + 1).padStart(2, '0');
        const day = String(value.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    applyEditFields(item) {
        this.editTitle = item.title || '';
        this.editDescription = item.description || '';
        this.editActive = item.isActive === true;
        this.editDuration = item.duration;
        this.editMaterialType = item.materialType || 'Course';
        this.editMaterialUrl = item.materialUrl || '';
        this.availableFrom = this.toIsoDate(item.effectiveStartDate);
        this.availableUntil = this.toIsoDate(item.effectiveEndDate);
    }

    resetTerritoryState() {
        this.territoryRoots = [];
        this.territoryFlatRows = [];
        this.territoryExpandedIds = new Set();
        this.selectedTerritoryIds = new Set();
        this.territorySearchTerm = '';
        this.hasUnsavedTerritoryChanges = false;
        this.availableFrom = null;
        this.availableUntil = null;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    handleTypeFilter(event) {
        this.typeFilter = event.detail.value;
    }

    handleActiveFilter(event) {
        this.activeFilter = event.detail.value;
    }

    handleBuTerritoryFilter(event) {
        this.buTerritoryFilter = event.detail.value || 'All';
        this.rebuildTerritoryRows();
    }

    handleAvailableFrom(event) {
        this.availableFrom = event.target.value || null;
    }

    handleAvailableUntil(event) {
        this.availableUntil = event.target.value || null;
    }

    handleToggleExpand(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        const next = new Set(this.expandedIds);
        if (next.has(id)) {
            next.delete(id);
        } else {
            next.add(id);
        }
        this.expandedIds = next;
    }

    handleSelectParent(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedParentId = id;
        this.selectedChildId = null;
        const parent = this.materials.find((m) => m.id === id);
        if (!parent) {
            return;
        }
        this.applyEditFields(parent);
        this.assignUserId = null;
        const next = new Set(this.expandedIds);
        next.add(id);
        this.expandedIds = next;
        this.loadAssignees(id);
        this.loadTerritoryTree(id);
    }

    handleSelectChild(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        const child = this.materials.find((m) => m.id === id);
        if (!child) {
            return;
        }
        this.selectedChildId = id;
        this.selectedParentId = child.parentMaterialId || this.selectedParentId;
        this.applyEditFields(child);
        if (this.selectedParentId) {
            const next = new Set(this.expandedIds);
            next.add(this.selectedParentId);
            this.expandedIds = next;
            this.loadAssignees(this.selectedParentId);
        }
    }

    async loadAssignees(materialId) {
        this.assigneesLoading = true;
        try {
            this.assignees = await getAssignments({ materialId });
        } catch (error) {
            this.assignees = [];
            this.toast('Unable to load assignees', this.errorMessage(error), 'error');
        } finally {
            this.assigneesLoading = false;
        }
    }

    async loadTerritoryTree(materialId) {
        if (!materialId) {
            this.resetTerritoryState();
            return;
        }
        this.isLoadingTerritories = true;
        this.hasUnsavedTerritoryChanges = false;
        try {
            const tree = await getTerritoryTreeForMaterial({ materialId });
            this.territoryRoots = tree || [];
            this.selectedTerritoryIds = this.collectAlignedIds(this.territoryRoots);
            this.initializeTerritoryExpanded();
            this.rebuildTerritoryRows();
        } catch (error) {
            this.territoryRoots = [];
            this.territoryFlatRows = [];
            this.selectedTerritoryIds = new Set();
            this.toast('Territory load failed', this.errorMessage(error), 'error');
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

    initializeTerritoryExpanded() {
        this.territoryExpandedIds = new Set();
        for (const root of this.territoryRoots) {
            this.territoryExpandedIds.add(root.id);
            if (root.children) {
                for (const child of root.children) {
                    this.territoryExpandedIds.add(child.id);
                }
            }
        }
    }

    rebuildTerritoryRows() {
        const term = (this.territorySearchTerm || '').trim().toLowerCase();
        const rows = [];
        const roots = this.getVisibleTerritoryRoots();
        for (const root of roots) {
            this.flattenTerritoryNode(root, 0, rows, term);
        }
        this.territoryFlatRows = rows;
    }

    getVisibleTerritoryRoots() {
        if (!this.buTerritoryFilter || this.buTerritoryFilter === 'All') {
            return this.territoryRoots || [];
        }
        const match = this.findTerritoryNode(this.territoryRoots, this.buTerritoryFilter);
        if (match) {
            return [match];
        }
        // Fallback: keep full tree if the selected BU isn't present in this material tree.
        return this.territoryRoots || [];
    }

    flattenTerritoryNode(node, depth, rows, term) {
        const nameMatches = !term || (node.name || '').toLowerCase().includes(term);
        const childRows = [];
        if (node.children) {
            for (const child of node.children) {
                this.flattenTerritoryNode(child, depth + 1, childRows, term);
            }
        }
        if (!nameMatches && childRows.length === 0) {
            return;
        }

        const expanded = term ? true : this.territoryExpandedIds.has(node.id);
        const checked = this.selectedTerritoryIds.has(String(node.id));
        rows.push({
            key: node.id,
            rowKey: `${node.id}-${checked ? '1' : '0'}-${expanded ? 'e' : 'c'}`,
            id: node.id,
            name: node.name,
            depth,
            depthStyle: `padding-left: ${depth * 1.25}rem`,
            hasChildren: node.hasChildren,
            expanded,
            chevronIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
            checked,
            checkboxLabel: node.name,
            rowClass: checked ? 'tree-row tree-row--assigned' : 'tree-row'
        });

        if (expanded) {
            rows.push(...childRows);
        }
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

    handleTerritorySearch(event) {
        this.territorySearchTerm = event.target.value || '';
        this.rebuildTerritoryRows();
    }

    handleTerritoryExpand(event) {
        const territoryId = event.currentTarget.dataset.id;
        if (this.territoryExpandedIds.has(territoryId)) {
            this.territoryExpandedIds.delete(territoryId);
        } else {
            this.territoryExpandedIds.add(territoryId);
        }
        this.territoryExpandedIds = new Set(this.territoryExpandedIds);
        this.rebuildTerritoryRows();
    }

    handleCascadeToggle(event) {
        this.cascadeToChildren = event.target.checked;
    }

    handleTerritoryCheck(event) {
        const territoryId = event.target.dataset.id;
        const checked = event.target.checked;
        const node = this.findTerritoryNode(this.territoryRoots, territoryId);
        const targetIds =
            this.cascadeToChildren && node
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
        this.hasUnsavedTerritoryChanges = true;
        this.rebuildTerritoryRows();
    }

    async handleSaveTerritoryAlignment() {
        if (!this.selectedParentId) {
            return;
        }
        this.isSaving = true;
        try {
            const result = await saveTerritoryAlignments({
                materialId: this.selectedParentId,
                territoryIds: Array.from(this.selectedTerritoryIds)
            });
            this.hasUnsavedTerritoryChanges = false;
            await refreshApex(this.wiredResult);
            await this.loadAssignees(this.selectedParentId);
            await this.loadTerritoryTree(this.selectedParentId);
            this.toast(
                'Alignment saved',
                `${result.territoryCount} territor${result.territoryCount === 1 ? 'y' : 'ies'}, ${result.userCount} user(s)${
                    result.removedInstanceCount
                        ? `, removed ${result.removedInstanceCount} instance(s)`
                        : ''
                }.`,
                'success'
            );
        } catch (error) {
            this.toast('Save failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleEditTitle(event) {
        this.editTitle = event.target.value;
    }

    handleEditDescription(event) {
        this.editDescription = event.target.value;
    }

    handleEditActive(event) {
        this.editActive = event.target.checked;
    }

    handleEditDuration(event) {
        const value = event.target.value;
        this.editDuration = value === '' || value == null ? null : Number(value);
    }

    handleEditMaterialType(event) {
        this.editMaterialType = event.detail.value;
    }

    handleEditMaterialUrl(event) {
        this.editMaterialUrl = event.target.value;
    }

    async handleFileUploadFinished(event) {
        const files = event.detail?.files || [];
        const uploaded = files[0];
        const materialId = this.selectedItem?.id;
        if (!uploaded?.documentId || !materialId) {
            return;
        }
        this.isUploading = true;
        try {
            const result = await finalizeMaterialFileUpload({
                materialId,
                contentDocumentId: uploaded.documentId
            });
            this.editMaterialUrl = result.materialUrl || '';
            await refreshApex(this.wiredResult);
            this.toast('Uploaded', 'File saved and content URL filled automatically.', 'success');
        } catch (error) {
            this.toast('Upload finalize failed', this.errorMessage(error), 'error');
        } finally {
            this.isUploading = false;
        }
    }

    async handleSaveItem() {
        const item = this.selectedItem;
        if (!item || !this.editTitle?.trim()) {
            return;
        }
        this.isSaving = true;
        try {
            await updateMaterial({
                materialId: item.id,
                title: this.editTitle.trim(),
                description: this.editDescription,
                active: this.editActive,
                duration: this.editDuration,
                materialType: this.editMaterialType,
                materialUrl: this.editMaterialUrl,
                startDate: this.isEditingParent ? this.availableFrom || null : null,
                endDate: this.isEditingParent ? this.availableUntil || null : null
            });
            await refreshApex(this.wiredResult);
            this.toast('Saved', 'Material updated.', 'success');
        } catch (error) {
            this.toast('Save failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleOpenRecord() {
        const item = this.selectedItem;
        if (item) {
            this.navigateToMaterial(item.id);
        }
    }

    handleAssignUser(event) {
        this.assignUserId = event.detail.recordId;
    }

    async handleAssign() {
        if (!this.assignUserId || !this.selectedParentId) {
            return;
        }
        this.isSaving = true;
        try {
            const result = await assignToUser({
                userId: this.assignUserId,
                materialId: this.selectedParentId
            });
            this.assignUserId = null;
            const picker = this.template.querySelector('lightning-record-picker');
            if (picker) {
                picker.clearSelection();
            }
            await refreshApex(this.wiredResult);
            await this.loadAssignees(this.selectedParentId);
            this.toast(
                'Assigned',
                `Created/ensured ${result.instanceCount} learning instance(s).`,
                'success'
            );
        } catch (error) {
            this.toast('Assign failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleNew() {
        this.newTitle = '';
        this.newType = 'Course';
        this.showNewModal = true;
    }

    handleNewTitle(event) {
        this.newTitle = event.target.value;
    }

    handleNewType(event) {
        this.newType = event.detail.value;
    }

    handleCloseNew() {
        this.showNewModal = false;
    }

    async handleCreate() {
        const title = this.newTitle?.trim();
        if (!title) {
            return;
        }
        this.isSaving = true;
        try {
            const parentId =
                this.newType === 'Course' ? null : this.selectedParentId || null;
            const materialId = await createMaterial({
                title,
                materialType: this.newType,
                parentMaterialId: parentId,
                active: true
            });
            this.showNewModal = false;
            await refreshApex(this.wiredResult);
            if (this.newType === 'Course') {
                this.selectedParentId = materialId;
                this.selectedChildId = null;
                this.loadAssignees(materialId);
                this.loadTerritoryTree(materialId);
            } else {
                this.selectedChildId = materialId;
                if (parentId) {
                    this.selectedParentId = parentId;
                }
            }
            // Load the new item's own values so Save does not write the previous item's fields onto it.
            if (this.selectedItem) {
                this.applyEditFields(this.selectedItem);
            }
            this.toast('Material created', 'Ready to edit.', 'success');
        } catch (error) {
            this.toast('Create failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    navigateToMaterial(id) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: id,
                objectApiName: 'Learning_Material__c',
                actionName: 'view'
            }
        });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errorMessage(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}