import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTerritoryTree from '@salesforce/apex/TerritoryManagementController.getTerritoryTree';
import getProductLines from '@salesforce/apex/TerritoryManagementController.getProductLines';
import getParentOptions from '@salesforce/apex/TerritoryManagementController.getParentOptions';
import getAssignableUsers from '@salesforce/apex/TerritoryManagementController.getAssignableUsers';
import assignUserToTerritory from '@salesforce/apex/TerritoryManagementController.assignUserToTerritory';
import clearTerritoryAssignments from '@salesforce/apex/TerritoryManagementController.clearTerritoryAssignments';
import resolveAssignmentRole from '@salesforce/apex/TerritoryManagementController.resolveAssignmentRole';
import saveTerritory from '@salesforce/apex/TerritoryManagementController.saveTerritory';
import createProductLine from '@salesforce/apex/TerritoryManagementController.createProductLine';
import deleteTerritory from '@salesforce/apex/TerritoryManagementController.deleteTerritory';
import createPharmaUser from '@salesforce/apex/TerritoryManagementController.createPharmaUser';
import syncDefaultLineProductAlignments from '@salesforce/apex/TerritoryManagementController.syncDefaultLineProductAlignments';

const THERAPY_AREA_OPTIONS = [
    { label: 'Diabetes', value: 'Diabetes' },
    { label: 'CHC', value: 'CHC' },
    { label: 'Cardiovascular', value: 'Cardiovascular' },
    { label: 'Gastroenterology', value: 'Gastroenterology' }
];

const ROLE_OPTIONS = [
    { label: 'Medical Rep (mr)', value: 'mr' },
    { label: 'District Manager (dm)', value: 'dm' }
];

const LEVEL_OPTIONS = [
    { label: 'Line (Product Line)', value: 'Line' },
    { label: 'District', value: 'District' },
    { label: 'Medical Rep Territory', value: 'MR' }
];

export default class TerritoryManagementConsole extends LightningElement {
    activeTab = 'lines';

    lineRows = [];
    treeRoots = [];
    flatRows = [];
    userRows = [];
    parentOptions = [];

    wiredTreeResult;
    wiredLinesResult;
    wiredUsersResult;
    expandedIds = new Set();

    isSaving = false;
    showAssignModal = false;
    showTerritoryModal = false;
    showLineModal = false;
    showUserModal = false;

    assignTerritoryId;
    assignTerritoryName;
    selectedUserId;
    userSearchTerm = '';

    draftTerritory = {
        recordId: null,
        name: '',
        externalId: '',
        parentId: null,
        level: 'District'
    };

    draftLine = {
        name: '',
        code: '',
        therapyArea: 'Diabetes'
    };

    draftUser = {
        firstName: '',
        lastName: '',
        teamCode: '',
        roleKey: 'mr',
        territoryId: null
    };

    therapyAreaOptions = THERAPY_AREA_OPTIONS;
    roleOptions = ROLE_OPTIONS;
    levelOptions = LEVEL_OPTIONS;

    @wire(getProductLines)
    wiredLines(result) {
        this.wiredLinesResult = result;
        this.lineRows = (result.data || []).map((line) => ({
            ...line,
            therapyLabel: line.therapyArea || 'Unmapped',
            cardClass: 'line-card'
        }));
    }

    @wire(getTerritoryTree)
    wiredTree(result) {
        this.wiredTreeResult = result;
        if (result.data) {
            this.treeRoots = result.data;
            this.initializeExpanded();
            this.rebuildFlatRows();
        } else {
            this.treeRoots = [];
            this.flatRows = [];
        }
    }

    @wire(getAssignableUsers, { searchTerm: '$userSearchTerm' })
    wiredAssignableUsers(result) {
        this.wiredUsersResult = result;
        this.userRows = result.data || [];
    }

    @wire(getParentOptions, { childLevel: '$draftTerritory.level' })
    wiredParentOptions({ data }) {
        this.parentOptions = (data || []).map((option) => ({
            label: option.label,
            value: option.id
        }));
    }

    get hasLineRows() {
        return this.lineRows.length > 0;
    }

    get hasRows() {
        return this.flatRows.length > 0;
    }

    get hasUsers() {
        return this.userRows.length > 0;
    }

    get isAssignDisabled() {
        return this.isSaving || !this.selectedUserId;
    }

    get isTerritorySaveDisabled() {
        return this.isSaving || !this.draftTerritory.name || (!this.draftTerritory.recordId && !this.draftTerritory.externalId);
    }

    get isLineSaveDisabled() {
        return this.isSaving || !this.draftLine.name || !this.draftLine.code;
    }

    get isUserSaveDisabled() {
        return (
            this.isSaving ||
            !this.draftUser.firstName ||
            !this.draftUser.lastName ||
            !this.draftUser.teamCode ||
            !this.draftUser.roleKey
        );
    }

    get territoryModalTitle() {
        return this.draftTerritory.recordId ? 'Edit Territory' : 'Add Territory';
    }

    get assignUserOptions() {
        return this.userRows.map((user) => ({
            label: user.label || `${user.name} (${user.username})`,
            value: user.id
        }));
    }

    get userTerritoryOptions() {
        return this.flatRows.map((row) => ({
            label: `${row.name} (${row.level})`,
            value: row.id
        }));
    }

    handleTabChange(event) {
        this.activeTab = event.target.value;
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

    flattenNode(node, depth, rows) {
        const expanded = this.expandedIds.has(node.id);
        rows.push({
            key: node.id,
            id: node.id,
            name: node.name,
            externalId: node.externalId,
            level: node.level,
            depth,
            depthStyle: `padding-left: ${depth * 1.25}rem`,
            hasChildren: node.hasChildren,
            expanded,
            chevronIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
            assignmentLabel: this.formatAssignments(node),
            isVacant: node.isVacant,
            vacantClass: node.isVacant ? 'badge badge-vacant' : 'badge badge-assigned',
            vacantLabel: node.isVacant ? 'Vacant' : 'Assigned',
            canEdit: node.canEdit,
            canDelete: node.canDelete,
            canAddChild: node.canAddChild
        });

        if (expanded && node.children) {
            for (const child of node.children) {
                this.flattenNode(child, depth + 1, rows);
            }
        }
    }

    formatAssignments(node) {
        if (!node.assignments || node.assignments.length === 0) {
            return 'Vacant';
        }
        return node.assignments
            .map((assignment) => {
                const role = assignment.role ? ` (${assignment.role})` : '';
                return `${assignment.userName}${role}`;
            })
            .join(', ');
    }

    handleToggle(event) {
        const territoryId = event.currentTarget.dataset.id;
        if (this.expandedIds.has(territoryId)) {
            this.expandedIds.delete(territoryId);
        } else {
            this.expandedIds.add(territoryId);
        }
        this.expandedIds = new Set(this.expandedIds);
        this.rebuildFlatRows();
    }

    handleAssign(event) {
        this.assignTerritoryId = event.currentTarget.dataset.id;
        this.assignTerritoryName = event.currentTarget.dataset.name;
        this.selectedUserId = null;
        this.userSearchTerm = '';
        this.showAssignModal = true;
    }

    handleUserSearch(event) {
        this.userSearchTerm = event.target.value || '';
    }

    handleUserSelect(event) {
        this.selectedUserId = event.detail.value;
    }

    handleCloseAssign() {
        this.showAssignModal = false;
        this.assignTerritoryId = null;
        this.assignTerritoryName = null;
        this.selectedUserId = null;
    }

    async handleConfirmAssign() {
        if (!this.assignTerritoryId || !this.selectedUserId) {
            return;
        }
        this.isSaving = true;
        try {
            const role = await resolveAssignmentRole({ userId: this.selectedUserId });
            await assignUserToTerritory({
                territoryId: this.assignTerritoryId,
                userId: this.selectedUserId,
                role
            });
            this.showAssignModal = false;
            await this.refreshAll();
            this.toast('User assigned', 'Territory assignment updated.', 'success');
        } catch (error) {
            this.toast('Assign failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleMakeVacant(event) {
        const territoryId = event.currentTarget.dataset.id;
        const territoryName = event.currentTarget.dataset.name;
        const confirmed = window.confirm(`Remove all user assignments from ${territoryName}?`);
        if (!confirmed) {
            return;
        }
        try {
            await clearTerritoryAssignments({ territoryId });
            await this.refreshAll();
            this.toast('Territory vacant', 'All assignments were removed.', 'success');
        } catch (error) {
            this.toast('Update failed', this.errorMessage(error), 'error');
        }
    }

    handleAddLine() {
        this.draftLine = { name: '', code: '', therapyArea: 'Diabetes' };
        this.showLineModal = true;
    }

    handleEditLine(event) {
        const lineId = event.currentTarget.dataset.id;
        const line = this.lineRows.find((row) => row.id === lineId);
        if (!line) {
            return;
        }
        this.draftTerritory = {
            recordId: line.id,
            name: line.name,
            externalId: line.externalId,
            parentId: null,
            level: 'Line'
        };
        this.showTerritoryModal = true;
    }

    handleAddTerritory() {
        this.draftTerritory = {
            recordId: null,
            name: '',
            externalId: '',
            parentId: null,
            level: 'District'
        };
        this.showTerritoryModal = true;
    }

    handleEditTerritory(event) {
        const row = this.flatRows.find((item) => item.id === event.currentTarget.dataset.id);
        if (!row) {
            return;
        }
        this.draftTerritory = {
            recordId: row.id,
            name: row.name,
            externalId: row.externalId,
            parentId: null,
            level: row.level
        };
        this.showTerritoryModal = true;
    }

    handleAddChildTerritory(event) {
        const row = this.flatRows.find((item) => item.id === event.currentTarget.dataset.id);
        if (!row) {
            return;
        }
        const childLevel = row.level === 'Head Office' ? 'Line' : row.level === 'Line' ? 'District' : 'MR';
        this.draftTerritory = {
            recordId: null,
            name: '',
            externalId: '',
            parentId: row.id,
            level: childLevel
        };
        this.showTerritoryModal = true;
    }

    handleTerritoryFieldChange(event) {
        const field = event.target.dataset.field;
        this.draftTerritory = {
            ...this.draftTerritory,
            [field]: event.detail.value
        };
    }

    handleLineFieldChange(event) {
        const field = event.target.dataset.field;
        this.draftLine = {
            ...this.draftLine,
            [field]: event.detail.value
        };
    }

    handleUserFieldChange(event) {
        const field = event.target.dataset.field;
        this.draftUser = {
            ...this.draftUser,
            [field]: event.detail.value
        };
    }

    handleCloseTerritoryModal() {
        this.showTerritoryModal = false;
    }

    handleCloseLineModal() {
        this.showLineModal = false;
    }

    handleOpenUserModal() {
        this.draftUser = {
            firstName: '',
            lastName: '',
            teamCode: '',
            roleKey: 'mr',
            territoryId: null
        };
        this.showUserModal = true;
    }

    handleCloseUserModal() {
        this.showUserModal = false;
    }

    async handleSaveTerritory() {
        this.isSaving = true;
        try {
            await saveTerritory({ form: this.draftTerritory });
            this.showTerritoryModal = false;
            await this.refreshAll();
            this.toast('Territory saved', 'Territory details were updated.', 'success');
        } catch (error) {
            this.toast('Save failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleSaveLine() {
        this.isSaving = true;
        try {
            await createProductLine({
                name: this.draftLine.name,
                code: this.draftLine.code,
                therapyArea: this.draftLine.therapyArea
            });
            if (this.draftLine.therapyArea) {
                await syncDefaultLineProductAlignments();
            }
            this.showLineModal = false;
            await this.refreshAll();
            this.toast('Line created', 'Product line and default district/MR territories were created.', 'success');
        } catch (error) {
            this.toast('Create failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleSaveUser() {
        this.isSaving = true;
        try {
            const result = await createPharmaUser({
                firstName: this.draftUser.firstName,
                lastName: this.draftUser.lastName,
                teamCode: this.draftUser.teamCode,
                roleKey: this.draftUser.roleKey,
                territoryId: this.draftUser.territoryId,
                roleInTerritory: null
            });
            this.showUserModal = false;
            await refreshApex(this.wiredUsersResult);
            await refreshApex(this.wiredTreeResult);
            this.toast('User created', result.message, 'success');
        } catch (error) {
            this.toast('Create failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleDeleteTerritory(event) {
        const territoryId = event.currentTarget.dataset.id;
        const territoryName = event.currentTarget.dataset.name;
        const confirmed = window.confirm(`Delete territory ${territoryName}? This cannot be undone.`);
        if (!confirmed) {
            return;
        }
        try {
            await deleteTerritory({ territoryId });
            await this.refreshAll();
            this.toast('Territory deleted', `${territoryName} was removed.`, 'success');
        } catch (error) {
            this.toast('Delete failed', this.errorMessage(error), 'error');
        }
    }

    async refreshAll() {
        await refreshApex(this.wiredTreeResult);
        await refreshApex(this.wiredLinesResult);
        await refreshApex(this.wiredUsersResult);
        this.rebuildFlatRows();
    }

    errorMessage(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
