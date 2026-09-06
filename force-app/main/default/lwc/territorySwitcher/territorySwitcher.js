import { LightningElement, track, wire } from 'lwc';
import { MessageContext } from 'lightning/messageService';
import { refreshApex } from '@salesforce/apex';
import { publishTerritoryContextChanged } from 'c/territoryContextClient';
import getContext from '@salesforce/apex/TerritorySwitcherController.getContext';
import setSelectedTerritory from '@salesforce/apex/TerritorySwitcherController.setSelectedTerritory';

export default class TerritorySwitcher extends LightningElement {
    @wire(MessageContext)
    messageContext;

    @track treeRoots = [];
    @track flatRows = [];

    wiredContextResult;
    expandedIds = new Set();
    searchTerm = '';
    selectedTerritoryId;
    selectedTerritoryName = 'All assigned territories';
    selectedLevel = '';
    usingAllAssigned = true;
    hasAssignment = false;
    isSaving = false;
    errorMessage;

    @wire(getContext)
    wiredContext(result) {
        this.wiredContextResult = result;
        if (result.data) {
            this.applyContext(result.data);
            this.errorMessage = '';
        } else if (result.error) {
            this.errorMessage = this.reduceError(result.error);
        }
    }

    get statusLabel() {
        if (!this.hasAssignment) {
            return 'No territory assignment';
        }
        return this.usingAllAssigned ? 'All assigned' : this.selectedLevel || 'Territory';
    }

    get hasRows() {
        return this.filteredRows.length > 0;
    }

    get filteredRows() {
        const term = (this.searchTerm || '').trim().toLowerCase();
        if (!term) {
            return this.flatRows;
        }
        const rows = [];
        for (const root of this.treeRoots) {
            this.flattenNode(root, 0, rows, true);
        }
        return rows.filter(
            (row) =>
                (row.name || '').toLowerCase().includes(term) ||
                (row.level || '').toLowerCase().includes(term)
        );
    }

    get allRowClass() {
        return this.usingAllAssigned ? 'tree-row tree-row--selected' : 'tree-row';
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    handleToggle(event) {
        event.stopPropagation();
        const territoryId = event.currentTarget.dataset.id;
        if (this.expandedIds.has(territoryId)) {
            this.expandedIds.delete(territoryId);
        } else {
            this.expandedIds.add(territoryId);
        }
        this.expandedIds = new Set(this.expandedIds);
        this.rebuildFlatRows();
    }

    async handleSelectAll() {
        await this.selectTerritory(null, 'All assigned territories');
    }

    async handleSelect(event) {
        const territoryId = event.currentTarget.dataset.id;
        const territoryName = event.currentTarget.dataset.name;
        await this.selectTerritory(territoryId, territoryName);
    }

    async selectTerritory(territoryId, territoryName) {
        if (this.isSaving) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = '';
        try {
            const context = await setSelectedTerritory({ territoryId });
            this.applyContext(context);
            publishTerritoryContextChanged(this.messageContext, {
                territoryId: territoryId || '',
                territoryName: territoryName || context.selectedTerritoryName,
                usingAllAssigned: context.usingAllAssigned === true
            });
            if (this.wiredContextResult) {
                await refreshApex(this.wiredContextResult);
            }
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    applyContext(data) {
        this.hasAssignment = data.hasAssignment === true;
        this.usingAllAssigned = data.usingAllAssigned !== false;
        this.selectedTerritoryId = data.selectedTerritoryId;
        this.selectedTerritoryName = data.selectedTerritoryName || 'All assigned territories';
        this.selectedLevel = data.selectedLevel || '';
        this.treeRoots = data.tree || [];
        this.initializeExpanded();
        this.rebuildFlatRows();
    }

    initializeExpanded() {
        if (this.expandedIds.size > 0) {
            return;
        }
        for (const root of this.treeRoots) {
            this.expandedIds.add(root.id);
            if (root.children) {
                for (const child of root.children) {
                    this.expandedIds.add(child.id);
                }
            }
        }
        this.expandedIds = new Set(this.expandedIds);
    }

    rebuildFlatRows() {
        const rows = [];
        for (const root of this.treeRoots) {
            this.flattenNode(root, 0, rows);
        }
        this.flatRows = rows;
    }

    flattenNode(node, depth, rows, forceExpanded) {
        const expanded = forceExpanded === true ? true : this.expandedIds.has(node.id);
        const isSelected = node.id === this.selectedTerritoryId;
        rows.push({
            id: node.id,
            name: node.name,
            level: node.level || '',
            hasChildren: node.hasChildren === true,
            depth,
            depthStyle: `padding-left: ${depth * 0.75}rem`,
            expanded,
            chevronIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
            isSelected,
            rowClass: isSelected ? 'tree-row tree-row--selected' : 'tree-row'
        });
        if (expanded && node.children) {
            for (const child of node.children) {
                this.flattenNode(child, depth + 1, rows, forceExpanded);
            }
        }
    }

    reduceError(error) {
        if (!error) {
            return 'Unknown error';
        }
        if (Array.isArray(error.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        if (error.body && typeof error.body.message === 'string') {
            return error.body.message;
        }
        return error.message || 'Unknown error';
    }
}
