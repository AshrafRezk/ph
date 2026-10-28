import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTerritoryTree from '@salesforce/apex/TerritoryManagementController.getTerritoryTree';
import getProductLines from '@salesforce/apex/TerritoryManagementController.getProductLines';
import getProductsForLine from '@salesforce/apex/TerritoryManagementController.getProductsForLine';
import searchAssignableProducts from '@salesforce/apex/TerritoryManagementController.searchAssignableProducts';
import setProductLineAssignment from '@salesforce/apex/TerritoryManagementController.setProductLineAssignment';
import setProductEffectiveFrom from '@salesforce/apex/TerritoryManagementController.setProductEffectiveFrom';
import clearProductLineAssignment from '@salesforce/apex/TerritoryManagementController.clearProductLineAssignment';
import removeProductsFromLine from '@salesforce/apex/TerritoryManagementController.removeProductsFromLine';
import mirrorAllPromotedLines from '@salesforce/apex/TerritoryManagementController.mirrorAllPromotedLines';
import getParentOptions from '@salesforce/apex/TerritoryManagementController.getParentOptions';
import getAssignableUsers from '@salesforce/apex/TerritoryManagementController.getAssignableUsers';
import queryManagedUsers from '@salesforce/apex/TerritoryManagementController.queryManagedUsersJson';
import mirrorLineProducts from '@salesforce/apex/TerritoryManagementController.mirrorLineProducts';
import assignUserToTerritory from '@salesforce/apex/TerritoryManagementController.assignUserToTerritory';
import clearTerritoryAssignments from '@salesforce/apex/TerritoryManagementController.clearTerritoryAssignments';
import saveTerritory from '@salesforce/apex/TerritoryManagementController.saveTerritoryJson';
import createProductLine from '@salesforce/apex/TerritoryManagementController.createProductLine';
import deleteTerritory from '@salesforce/apex/TerritoryManagementController.deleteTerritory';
import createPharmaUser from '@salesforce/apex/TerritoryManagementController.createPharmaUser';
import syncDefaultLineProductAlignments from '@salesforce/apex/TerritoryManagementController.syncDefaultLineProductAlignments';
import getUserEditDetails from '@salesforce/apex/UserEditorController.getUserEditDetails';
import saveUserDetails from '@salesforce/apex/UserEditorController.saveUserDetails';
import promoteUser from '@salesforce/apex/SeatChangeService.promoteUser';
import previewOrganogramUpload from '@salesforce/apex/SeatChangeService.previewOrganogramUpload';
import applyOrganogramUpload from '@salesforce/apex/SeatChangeService.applyOrganogramUpload';
import getScheduledChanges from '@salesforce/apex/SeatChangeService.getScheduledChanges';
import cancelScheduledChange from '@salesforce/apex/SeatChangeService.cancelScheduledChange';
import setOneTimePasswords from '@salesforce/apex/TerritoryManagementController.setOneTimePasswords';
import setUsersActive from '@salesforce/apex/TerritoryManagementController.setUsersActive';
import applyRealignedSalesLines from '@salesforce/apex/CommercialLineAssignmentService.applyRealignedSalesLines';
import previewAsUser from '@salesforce/apex/TerritoryPreviewService.previewAsUser';
import startFieldSession from '@salesforce/apex/FieldLoginAsController.startFieldSession';
import clearPreview from '@salesforce/apex/TerritoryPreviewService.clearPreview';
import seatMarketingOnOrganogram from '@salesforce/apex/BrandManagerSeatService.seatMarketingOnOrganogram';
import getBrickRows from '@salesforce/apex/OrganogramBrickExport.getBrickRows';
import ORGANOGRAM_SOURCE from '@salesforce/resourceUrl/ZetaOrganogramTerritories';

const THERAPY_AREA_OPTIONS = [
    { label: 'Diabetes', value: 'Diabetes' },
    { label: 'CHC', value: 'CHC' },
    { label: 'Cardiovascular', value: 'Cardiovascular' },
    { label: 'Gastroenterology', value: 'Gastroenterology' }
];

const ROLE_OPTIONS = [
    { label: 'Medical Rep (mr)', value: 'mr' },
    { label: 'Trainer (trainer)', value: 'trainer' },
    { label: 'District Manager (dm)', value: 'dm' },
    { label: 'Area Manager (am)', value: 'am' },
    { label: 'Brand Manager (brand)', value: 'brand' },
    { label: 'National Sales Manager (nsm)', value: 'nsm' },
    { label: 'Business Unit Manager (bum)', value: 'bum' }
];

/** RoleInTerritory2 values for territory assignment (pick one when testing manager approvals). */
const TERRITORY_ASSIGN_ROLE_OPTIONS = [
    { label: 'Medical Rep', value: 'Medical Rep' },
    { label: 'Trainer (account approver for demo)', value: 'Trainer' },
    { label: 'District Manager', value: 'District Manager' },
    { label: 'Area Manager', value: 'Area Manager' },
    { label: 'Region Manager', value: 'Region Manager' },
    { label: 'Line Manager', value: 'Line Manager' },
    { label: 'National Sales Manager', value: 'National Sales Manager' },
    { label: 'Business Unit Manager', value: 'Business Unit Manager' },
    { label: 'Brand Manager', value: 'Brand Manager' },
    { label: 'Group Brand Lead', value: 'Group Brand Lead' }
];

/** Title of a seat nobody holds, by organogram level. Matches SeatChangeService.defaultTitle. */
const DEFAULT_SEAT_TITLE = {
    'Head Office': 'Head Office',
    'Business Unit': 'Business Unit Manager',
    Line: 'National Sales Manager',
    District: 'District Manager',
    Position: 'Medical Rep',
    MR: 'Medical Rep',
    'Marketing Seat': 'Brand Manager'
};

/** Same wording as the server refusal (TerritoryManagementController.requireManageUsers). */
const MANAGE_USERS_REFUSAL = 'You need the Manage Users permission to change user logins.';

const USERS_EXPORT_HEADER = [
    'Name',
    'Username',
    'Email',
    'Title',
    'Business Unit',
    'Line',
    'Territory',
    'Profile',
    'Status',
    'Hire Date',
    'Resignation Date',
    'Last Work Day'
];

/**
 * Saves a CSV in the browser. The link is attached to the page before the click and the object
 * URL is released a moment later: a detached link revoked straight away often downloads nothing.
 */
function downloadCsv(filename, text) {
    // Lightning Web Security rejects text/csv and MIME parameters, so the file goes out as
    // text/plain with a .csv name; the BOM keeps Arabic names readable in Excel.
    const blob = new Blob(['\uFEFF' + text], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    link.style.display = 'none';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

const MARKETING_TITLES = new Set(['Brand Manager', 'Group Brand Lead']);

/** People who hold a Brand Manager / Group Brand Lead box (Level = Marketing Seat). */
function marketingSeatHolderIds(rows) {
    const ids = new Set();
    for (const row of rows) {
        if (row.level === 'Marketing Seat') {
            for (const holder of row.holders || []) {
                if (holder.userId) {
                    ids.add(holder.userId);
                }
            }
        }
    }
    return ids;
}

/** The Line / BU seat that only gives a Marketing Seat holder visibility of that team. */
function isMarketingAccessSeat(row, holder, marketingHolderIds) {
    return (
        (row.level === 'Line' || row.level === 'Business Unit') &&
        MARKETING_TITLES.has(holder.title) &&
        marketingHolderIds.has(holder.userId)
    );
}

const ORGANOGRAM_HEADER = [
    'Territory Id',
    'Territory External Id',
    'Parent External Id',
    'Business Unit',
    'Line',
    'Level',
    'Territory',
    'Title',
    'Holder User Id',
    'Holder',
    'Holder Username',
    'Employee Code',
    'Effective Date',
    'Remove'
];

/** Upload columns, keyed by the header with spaces and punctuation removed. */
const UPLOAD_COLUMNS = {
    territoryid: 'territoryId',
    territoryexternalid: 'territoryExternalId',
    externalid: 'territoryExternalId',
    territory: 'territoryName',
    territoryname: 'territoryName',
    parentexternalid: 'parentExternalId',
    parentterritoryexternalid: 'parentExternalId',
    level: 'level',
    title: 'title',
    titleinseat: 'title',
    role: 'title',
    holderuserid: 'holderUserId',
    userid: 'holderUserId',
    holder: 'holder',
    assigneduser: 'holder',
    holderusername: 'holderUsername',
    username: 'holderUsername',
    employeecode: 'employeeCode',
    employeenumber: 'employeeCode',
    effectivedate: 'effectiveDate',
    remove: 'remove',
    delete: 'remove'
};

/** Same columns as the Details sheet of Zeta's Total Organogram workbook on the Drive. */
const TOTAL_ORGANOGRAM_HEADER = [
    '702 Bricks',
    'Line',
    'Share',
    'Territory ID',
    'Position',
    'BUM',
    'BUM ID',
    'BUM Hiring Date',
    'NSM',
    'NSM ID',
    'NSM Hiring Date',
    'ASM',
    'ASM ID',
    'ASM Hiring Date',
    'District Manager',
    'DM ID',
    'DM Hiring Date',
    '70 Bricks',
    '148 Bricks',
    'Medical Rep',
    'Search',
    'MedRep ID',
    'MedRep Date',
    'Area',
    'Area ID',
    'District',
    'Dis ID',
    'Territory',
    'Ter ID'
];

const UPLOAD_PREVIEW_LIMIT = 300;

function todayIso() {
    const now = new Date();
    const pad = (value) => String(value).padStart(2, '0');
    return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

/** RFC 4180 CSV (quotes, doubled quotes, CRLF). Excel in some locales saves with ";" instead of ",". */
function parseCsv(text) {
    const source = String(text || '').replace(/^\uFEFF/, '');
    const firstLine = source.split(/\r?\n/, 1)[0] || '';
    const delimiter = (firstLine.match(/;/g) || []).length > (firstLine.match(/,/g) || []).length ? ';' : ',';
    const rows = [];
    let row = [];
    let cell = '';
    let quoted = false;
    for (let i = 0; i < source.length; i++) {
        const ch = source[i];
        if (quoted) {
            if (ch === '"' && source[i + 1] === '"') {
                cell += '"';
                i++;
            } else if (ch === '"') {
                quoted = false;
            } else {
                cell += ch;
            }
        } else if (ch === '"') {
            quoted = true;
        } else if (ch === delimiter) {
            row.push(cell);
            cell = '';
        } else if (ch === '\n' || ch === '\r') {
            if (ch === '\r' && source[i + 1] === '\n') {
                i++;
            }
            row.push(cell);
            rows.push(row);
            row = [];
            cell = '';
        } else {
            cell += ch;
        }
    }
    if (cell !== '' || row.length) {
        row.push(cell);
        rows.push(row);
    }
    return rows.filter((cells) => cells.some((value) => String(value).trim() !== ''));
}

/** Turns CSV rows into upload rows. Returns { rows, missing } where missing lists required columns not found. */
function toUploadRows(csvRows) {
    if (!csvRows.length) {
        return { rows: [], missing: ['Territory External Id'] };
    }
    const columns = csvRows[0].map((header) => UPLOAD_COLUMNS[String(header).toLowerCase().replace(/[^a-z]/g, '')]);
    if (!columns.includes('territoryExternalId') && !columns.includes('territoryId')) {
        return { rows: [], missing: ['Territory External Id'] };
    }
    const rows = [];
    for (let i = 1; i < csvRows.length; i++) {
        const row = { rowNumber: i + 1 };
        columns.forEach((field, index) => {
            if (field && !row[field]) {
                row[field] = String(csvRows[i][index] || '').trim();
            }
        });
        rows.push(row);
    }
    return { rows, missing: [] };
}

const LEVEL_OPTIONS = [
    { label: 'Business Unit', value: 'Business Unit' },
    { label: 'Line (Product Line)', value: 'Line' },
    { label: 'District', value: 'District' },
    { label: 'Position (Medical Rep)', value: 'Position' }
];

const PRODUCT_TYPE_FILTERS = [
    { label: 'All types', value: 'All' },
    { label: 'Brand', value: 'Brand' },
    { label: 'Detail', value: 'Detail' },
    { label: 'Sample', value: 'Sample' },
    { label: 'Brand Reminder', value: 'Brand Reminder' }
];

const ASSIGN_MODE_OPTIONS = [
    { label: 'Primary Sales Line', value: 'primary' },
    { label: 'Mirror Line', value: 'mirror' }
];

const USER_PAGE_SIZE_OPTIONS = [
    { label: '25', value: '25' },
    { label: '50', value: '50' },
    { label: '100', value: '100' }
];

function formatIsoDate(value) {
    if (!value) {
        return '';
    }
    const match = String(value).match(/\d{4}-\d{2}-\d{2}/);
    return match ? match[0] : String(value);
}

function cleanList(value) {
    return String(value || '')
        .split(',')
        .map((part) => part.trim())
        .filter((part) => part && part.toLowerCase() !== 'sales');
}

function decorateManagedUser(user, selectedIds) {
    const selected = selectedIds.has(user.id);
    const username = user.username || '';
    const email = user.email || '';
    const hireDateLabel = formatIsoDate(user.hireDate);
    const resignationDateLabel = formatIsoDate(user.resignationDate);
    const lastWorkDayLabel = formatIsoDate(user.lastWorkDay);
    const businessUnitLabel = cleanList(user.businessUnit).join(', ');
    return {
        ...user,
        lineName: user.lineName || '',
        territoryName: user.territoryName || '',
        lineLabel: user.lineName || '—',
        territoryLabel: user.territoryName || '—',
        businessUnitLabel,
        email,
        username,
        showUsername: Boolean(username) && username.toLowerCase() !== email.toLowerCase(),
        titleLabel: user.title || '—',
        profileName: user.profileName || '',
        hireDateLabel,
        resignationDateLabel,
        lastWorkDayLabel,
        hasHireDate: Boolean(hireDateLabel),
        hasResignationDate: Boolean(resignationDateLabel),
        hasLastWorkDay: Boolean(lastWorkDayLabel),
        noDates: !hireDateLabel && !resignationDateLabel && !lastWorkDayLabel,
        selectLabel: `Select ${user.name || 'user'}`,
        selected,
        rowClass: selected ? 'user-row is-selected' : 'user-row',
        statusLabel: user.isActive ? 'Active' : 'Inactive',
        statusClass: user.isActive ? 'badge badge-assigned' : 'badge badge-vacant',
        activateLabel: user.isActive ? 'Deactivate' : 'Activate'
    };
}

function passwordMeetsPolicy(password) {
    return password.length >= 8 && /[A-Za-z]/.test(password) && /\d/.test(password);
}

// One-off go-live actions. Kept behind a collapsed Maintenance section with an in-page confirmation.
const MAINTENANCE_ACTIONS = [
    {
        key: 'applyLines',
        label: 'Apply October line assignments',
        title: 'Re-applies the October realigned sales lines to every territory',
        warning: 'This re-applies the October realignment to every territory and overwrites any line changes made since.',
        handler: 'handleApplyLines'
    },
    {
        key: 'applyMirrors',
        label: 'Apply CHC / GIT / CVM mirrors',
        title: 'Sets Mirror_Line after Zeta confirms pack list; safe to re-run',
        warning: 'This rewrites the CHC_Sales, GIT-SALES and CVM-I/II mirror products from their source lines.',
        handler: 'handleApplyStandardMirrors'
    },
    {
        key: 'seatBrandManagers',
        label: 'Seat Brand Managers / Group Brand Leads',
        title: 'Places Brand Managers on Line and Group Brand Leads on BU',
        warning: 'This re-seats every Brand Manager on their line and every Group Brand Lead on their BU in the organogram.',
        handler: 'handleSeatBrandManagers'
    }
];

export default class TerritoryManagementConsole extends NavigationMixin(LightningElement) {
    /**
     * Add Product Line, Add Territory / Add Child, Create User and Delete territory call Apex
     * that always refuses (those changes are made in Setup). Hidden until that Apex is built.
     */
    setupOnlyActionsEnabled = false;

    activeTab = 'lines';
    maintenanceActions = MAINTENANCE_ACTIONS;
    showMaintenance = false;
    pendingMaintenanceKey = null;

    lineRows = [];
    treeRoots = [];
    flatRows = [];
    allTerritoryRows = [];
    assignUserRows = [];
    userRows = [];
    parentOptions = [];
    selectedUserIds = new Set();

    wiredTreeResult;
    wiredLinesResult;
    wiredAssignUsersResult;
    wiredManagedUsersResult;
    /** From the Users page: false for managers, who cannot change logins. */
    canManageUsers = true;
    /** True when the Users list is limited to the caller's own team. */
    usersTeamScoped = false;
    isExportingUsers = false;
    isExportingBricks = false;
    brickExportProgress = '';
    expandedIds = new Set();

    isSaving = false;
    showAssignModal = false;
    showTerritoryModal = false;
    showLineModal = false;
    showUserModal = false;
    showEditProfileModal = false;
    showPasswordModal = false;
    showFieldLoginAsModal = false;
    fieldLoginAsUserId;
    fieldLoginAsName = '';
    fieldLoginAsReason = '';
    fieldLoginAsUrl = '';
    showManageProductsModal = false;

    assignTerritoryId;
    assignTerritoryName;
    selectedUserId;
    assignTerritoryRole = 'Trainer';
    assignUserSearchTerm = '';
    userSearchTerm = '';
    includeInactiveUsers = true;
    showTraining = false;
    territoryNameFilter = '';
    territoryLineFilter = 'All';
    territoryBuFilter = 'All';
    userLineFilter = 'All';
    userTitleFilter = 'All';
    userTerritoryFilter = '';
    userBuFilter = 'All';
    userActiveFilter = 'All';
    userPageNumber = 1;
    userPageSize = 25;
    usersLoaded = false;
    resultsStale = false;
    userTotalCount = 0;
    userActiveCount = 0;
    userInactiveCount = 0;
    userHasMore = false;
    userTitleOptionList = [];
    userLineOptionList = [];
    userBuOptionList = [];
    isLoadingUsers = false;
    selectedProductIds = new Set();
    lineBuFilter = 'All';
    isApplyingLines = false;
    isMirroringLines = false;
    passwordTargetIds = [];
    generatedPassword = '';

    manageLineId;
    manageLineName = '';
    lineProductRows = [];
    lineProductTypeFilter = 'All';
    lineProductSearchTerm = '';
    isLoadingLineProducts = false;
    assignProductSearchTerm = '';
    assignProductCandidates = [];
    assignProductId;
    assignMode = 'primary';
    isSearchingAssignable = false;

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

    draftProfile = {
        userId: null,
        firstName: '',
        lastName: '',
        email: '',
        username: '',
        title: '',
        department: '',
        division: '',
        employeeNumber: '',
        mobilePhone: '',
        phone: '',
        managerId: '',
        hireDate: null,
        resignationDate: null,
        lastWorkDay: null
    };

    editDetails = null;
    isLoadingEditDetails = false;
    managerSearchTerm = '';
    managerCandidates = [];
    promotion = {
        open: false,
        searchTerm: '',
        territoryExternalId: '',
        role: '',
        newTitle: '',
        titleTouched: false,
        effectiveDate: '',
        releaseOtherSeats: true,
        replaceSameRole: true
    };

    showUploadModal = false;
    showUploadHelp = false;
    uploadFileName = '';
    uploadRows = [];
    uploadPreview = null;
    uploadReleaseOther = false;
    isUploadBusy = false;
    uploadError = '';

    showScheduledModal = false;
    scheduledChanges = [];

    draftPassword = {
        password: '',
        confirmPassword: ''
    };

    therapyAreaOptions = THERAPY_AREA_OPTIONS;
    roleOptions = ROLE_OPTIONS;
    territoryAssignRoleOptions = TERRITORY_ASSIGN_ROLE_OPTIONS;
    levelOptions = LEVEL_OPTIONS;
    productTypeFilterOptions = PRODUCT_TYPE_FILTERS;
    assignModeOptions = ASSIGN_MODE_OPTIONS;

    @wire(getProductLines)
    wiredLines(result) {
        this.wiredLinesResult = result;
        this.lineRows = (result.data || []).map((line) => {
            const typeBits = [];
            if (line.brandCount) {
                typeBits.push(`${line.brandCount} brands`);
            }
            if (line.detailCount) {
                typeBits.push(`${line.detailCount} details`);
            }
            if (line.sampleCount) {
                typeBits.push(`${line.sampleCount} samples`);
            }
            if (line.reminderCount) {
                typeBits.push(`${line.reminderCount} reminders`);
            }
            return {
                ...line,
                therapyLabel: line.therapyArea || 'No sales unit',
                typeBreakdown: typeBits.length ? typeBits.join(' · ') : 'No products linked',
                cardClass: 'line-card'
            };
        });
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

    @wire(getAssignableUsers, { searchTerm: '$assignUserSearchTerm' })
    wiredAssignableUsers(result) {
        this.wiredAssignUsersResult = result;
        this.assignUserRows = result.data || [];
    }

    connectedCallback() {
        this.loadManagedUsers();
        this.loadScheduledChanges();
    }

    disconnectedCallback() {
        window.clearTimeout(this._userSearchTimer);
    }

    /**
     * Filter changes go through here: one reload after the user stops clicking, never one per click.
     * A delay of 0 loads immediately (Enter, clear, pick a dropdown). Typing waits out the delay.
     * loadManagedUsers also drops any response that is not from the latest request.
     */
    scheduleUserReload(delay = 250) {
        window.clearTimeout(this._userSearchTimer);
        this._userSearchTimer = null;
        if (!delay) {
            this.loadManagedUsers();
            return;
        }
        this._userSearchTimer = window.setTimeout(() => this.loadManagedUsers(), delay);
    }

    async loadManagedUsers() {
        // Sequence guard: a slow earlier response must never overwrite the rows of a newer filter.
        this._userLoadSeq = (this._userLoadSeq || 0) + 1;
        const seq = this._userLoadSeq;
        this.isLoadingUsers = true;
        try {
            const requestedTerm = (this.userSearchTerm || '').trim();
            const requestedPage = this.userPageNumber;
            const page = await queryManagedUsers({
                requestJson: JSON.stringify({
                    searchTerm: requestedTerm,
                    includeInactive: this.includeInactiveUsers === true,
                    titleFilter: this.userTitleFilter,
                    lineFilter: this.userLineFilter,
                    territoryFilter: (this.userTerritoryFilter || '').trim(),
                    businessUnitFilter: this.userBuFilter,
                    activeFilter: this.userActiveFilter,
                    pageNumber: requestedPage,
                    pageSize: this.userPageSize
                })
            });
            if (seq !== this._userLoadSeq) {
                return;
            }
            // A slower call from before this search text was typed must not put the full list back.
            if ((page?.appliedSearchTerm || '') !== requestedTerm) {
                return;
            }
            const selected = this.selectedUserIds;
            this.userRows = (page?.users || []).map((user) => decorateManagedUser(user, selected));
            this.userTotalCount = page?.totalCount || 0;
            this.userActiveCount = page?.activeCount || 0;
            this.userInactiveCount = page?.inactiveCount || 0;
            this.userHasMore =
                page?.hasMore === true ||
                (page?.pageNumber || 1) < Math.ceil((page?.totalCount || 0) / (page?.pageSize || this.userPageSize || 25));
            if (page?.pageNumber) {
                this.userPageNumber = page.pageNumber;
            }
            this.resultsStale = false;
            // While a title is selected keep every title seen so far, even from an older server build
            // that only returned the selected one.
            const serverTitles = page?.titleOptions || [];
            this.userTitleOptionList =
                this.userTitleFilter && this.userTitleFilter !== 'All'
                    ? [...new Set([...(this.userTitleOptionList || []), ...serverTitles])]
                    : serverTitles;
            this.userLineOptionList = page?.lineOptions || [];
            this.userBuOptionList = page?.businessUnitOptions || [];
            this.canManageUsers = page?.canManageUsers !== false;
            this.usersTeamScoped = page?.teamScoped === true;
        } catch (error) {
            if (seq !== this._userLoadSeq) {
                return;
            }
            this.userRows = [];
            this.toast('Users', error?.body?.message || error.message, 'error');
        } finally {
            if (seq === this._userLoadSeq) {
                this.isLoadingUsers = false;
                this.usersLoaded = true;
            }
        }
    }

    @wire(getParentOptions, { childLevel: '$draftTerritory.level' })
    wiredParentOptions({ data }) {
        this.parentOptions = (data || []).map((option) => ({
            label: option.label,
            value: option.id
        }));
    }

    get visibleLineRows() {
        const bu = this.lineBuFilter || 'All';
        return this.lineRows.filter((line) => {
            if (!this.showTraining && this.isTrainingExternal(line.externalId)) {
                return false;
            }
            if (bu !== 'All' && (line.businessUnitName || '') !== bu) {
                return false;
            }
            return true;
        });
    }

    get lineBuOptions() {
        const names = new Set();
        for (const line of this.lineRows || []) {
            if (line.businessUnitName) {
                names.add(line.businessUnitName);
            }
        }
        return [{ label: 'All BUs', value: 'All' }].concat(
            [...names].sort().map((name) => ({ label: name, value: name }))
        );
    }

    get territoryBuOptions() {
        const names = new Set();
        for (const row of this.allTerritoryRows || []) {
            if (row.level === 'Business Unit' && (this.showTraining || !row.training)) {
                names.add(row.name);
            }
        }
        return [{ label: 'All BUs', value: 'All' }].concat(
            [...names].sort().map((name) => ({ label: name, value: name }))
        );
    }

    get userCountSummary() {
        if (!this.usersLoaded || this.resultsStale) {
            return 'Loading users…';
        }
        const total = this.userTotalCount || 0;
        const term = (this.userSearchTerm || '').trim();
        let lead = `${total} ${total === 1 ? 'user' : 'users'}`;
        if (term) {
            lead = `${total} match for "${term}"`;
        } else if (this.hasUserFilters) {
            lead = `${total} match`;
        }
        return `${lead} · ${this.userActiveCount} active · ${this.userInactiveCount} inactive`;
    }

    get hasUserFilters() {
        return Boolean(
            (this.userSearchTerm || '').trim() ||
            (this.userTerritoryFilter || '').trim() ||
            (this.userLineFilter && this.userLineFilter !== 'All') ||
            (this.userTitleFilter && this.userTitleFilter !== 'All') ||
            (this.userBuFilter && this.userBuFilter !== 'All') ||
            (this.userActiveFilter && this.userActiveFilter !== 'All')
        );
    }

    get userPageSizeOptions() {
        return USER_PAGE_SIZE_OPTIONS;
    }

    get userPageSizeValue() {
        return String(this.userPageSize);
    }

    get userPageCount() {
        const size = this.userPageSize || 25;
        const total = this.userTotalCount || 0;
        return Math.max(1, Math.ceil(total / size));
    }

    get userRangeLabel() {
        const total = this.userTotalCount || 0;
        if (!this.usersLoaded) {
            return '';
        }
        if (!total || !this.userRows.length) {
            return `Showing 0 of ${total}`;
        }
        const start = (this.userPageNumber - 1) * this.userPageSize + 1;
        const end = start + this.userRows.length - 1;
        return `Showing ${start}–${end} of ${total}`;
    }

    get isUserPrevDisabled() {
        return this.isLoadingUsers || this.resultsStale || this.userPageNumber <= 1;
    }

    get isUserNextDisabled() {
        return (
            this.isLoadingUsers ||
            this.resultsStale ||
            !this.userTotalCount ||
            this.userPageNumber >= this.userPageCount
        );
    }

    get showUserUpdating() {
        return this.usersLoaded && this.isLoadingUsers;
    }

    get showUserEmpty() {
        return this.usersLoaded && !this.isLoadingUsers && this.userRows.length === 0;
    }

    get userListClass() {
        return this.isLoadingUsers ? 'user-list is-loading' : 'user-list';
    }

    get selectedProductCount() {
        return this.selectedProductIds.size;
    }

    get hasSelectedProducts() {
        return this.selectedProductIds.size > 0;
    }

    get userActiveFilterOptions() {
        return [
            { label: 'All statuses', value: 'All' },
            { label: 'Active only', value: 'active' },
            { label: 'Inactive only', value: 'inactive' }
        ];
    }

    get hasLineRows() {
        return this.visibleLineRows.length > 0;
    }

    get filteredLineProductRows() {
        const type = this.lineProductTypeFilter;
        const term = (this.lineProductSearchTerm || '').trim().toLowerCase();
        const selected = this.selectedProductIds;
        return (this.lineProductRows || [])
            .filter((row) => (type === 'All' ? true : row.productType === type))
            .filter((row) => {
                if (!term) {
                    return true;
                }
                return (
                    (row.name || '').toLowerCase().includes(term) ||
                    (row.productCode || '').toLowerCase().includes(term) ||
                    (row.primaryBrand || '').toLowerCase().includes(term)
                );
            })
            .map((row) => ({
                ...row,
                selected: selected.has(row.id),
                activeLabel: row.isActive ? 'Active' : 'Inactive',
                activeClass: row.isActive ? 'badge badge-assigned' : 'badge badge-vacant',
                linkLabel: row.matchedViaMirror ? 'Mirror' : 'Primary'
            }));
    }

    get isAllProductsSelected() {
        const rows = this.filteredLineProductRows;
        return rows.length > 0 && rows.every((row) => this.selectedProductIds.has(row.id));
    }

    get hasFilteredLineProducts() {
        return this.filteredLineProductRows.length > 0;
    }

    get manageProductsTitle() {
        return this.manageLineName
            ? `Manage Products — ${this.manageLineName}`
            : 'Manage Products';
    }

    get assignProductOptions() {
        return (this.assignProductCandidates || []).map((product) => ({
            label: `${product.name}${product.productCode ? ` (${product.productCode})` : ''} · ${product.productType || 'Product'}`,
            value: product.id
        }));
    }

    get isAssignProductDisabled() {
        return this.isSaving || !this.assignProductId || !this.manageLineId;
    }

    get hasRows() {
        return this.flatRows.length > 0;
    }

    get hasUsers() {
        return this.userRows.length > 0;
    }

    get selectedUserCount() {
        return this.selectedUserIds.size;
    }

    get hasSelectedUsers() {
        return this.selectedUserIds.size > 0;
    }

    get isAllUsersSelected() {
        const visible = this.visibleUserRows;
        return visible.length > 0 && visible.every((user) => this.selectedUserIds.has(user.id));
    }

    get passwordModalTitle() {
        const count = this.passwordTargetIds.length;
        return count > 1 ? `Set One-Time Password (${count} users)` : 'Set One-Time Password';
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

    get isPasswordSaveDisabled() {
        const password = (this.draftPassword.password || '').trim();
        const confirm = (this.draftPassword.confirmPassword || '').trim();
        if (this.isSaving || this.passwordTargetIds.length === 0) {
            return true;
        }
        if (!password) {
            return false;
        }
        return password !== confirm || password.length < 8;
    }

    get territoryModalTitle() {
        return this.draftTerritory.recordId ? 'Edit Territory' : 'Add Territory';
    }

    get assignUserOptions() {
        return this.assignUserRows.map((user) => ({
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
            this.flattenNode(root, 0, rows, '', false);
        }
        this.allTerritoryRows = rows;
        const byId = new Map(rows.map((row) => [row.id, row]));
        const nameTerm = (this.territoryNameFilter || '').trim().toLowerCase();
        const lineFilter = this.territoryLineFilter || 'All';
        const buFilter = this.territoryBuFilter || 'All';
        const filtering = Boolean(nameTerm) || lineFilter !== 'All' || buFilter !== 'All';
        if (!filtering) {
            this.flatRows = rows.filter(
                (row) => (this.showTraining || !row.training) && this.ancestorsExpanded(row, byId)
            );
            return;
        }
        const matched = new Set();
        for (const row of rows) {
            if (row.training && !this.showTraining) {
                continue;
            }
            const haystack = [row.name, row.externalId, row.holderLabel, row.lineName, row.businessUnitName]
                .join(' ')
                .toLowerCase();
            const nameOk = !nameTerm || haystack.includes(nameTerm);
            const lineOk = lineFilter === 'All' || row.lineName === lineFilter;
            const buOk = buFilter === 'All' || row.businessUnitName === buFilter;
            if (nameOk && lineOk && buOk) {
                let cursor = row;
                while (cursor) {
                    matched.add(cursor.id);
                    cursor = cursor.parentId ? byId.get(cursor.parentId) : null;
                }
            }
        }
        this.flatRows = rows.filter((row) => matched.has(row.id));
    }

    ancestorsExpanded(row, byId) {
        let parent = row.parentId ? byId.get(row.parentId) : null;
        while (parent) {
            if (!this.expandedIds.has(parent.id)) {
                return false;
            }
            parent = parent.parentId ? byId.get(parent.parentId) : null;
        }
        return true;
    }

    flattenNode(node, depth, rows, lineName, underTraining) {
        const training = underTraining || this.isTrainingExternal(node.externalId);
        const nextLine = node.level === 'Line' ? node.name : lineName;
        const expanded = this.expandedIds.has(node.id);
        const vacantDmCount = Number(node.vacantDmSeatCount) || 0;
        // Title column shows the seat's title; Assigned User shows only who holds that title,
        // e.g. Cluster → Business Unit Manager → Ahmed Shoukry. People below are a grey count.
        const defaultTitle = DEFAULT_SEAT_TITLE[node.level] || node.level;
        const holders = (node.assignments || []).map((assignment, index) => ({
            key: assignment.associationId || `${node.id}-${index}`,
            title: assignment.role || assignment.userTitle || defaultTitle,
            name: assignment.userName,
            userId: assignment.userId,
            username: assignment.userLogin || '',
            employeeNumber: assignment.employeeNumber || ''
        }));
        const seatVacant = holders.length === 0;
        const ownIds = new Set(holders.map((holder) => holder.userId));
        const belowCount = Math.max(0, (Number(node.descendantUserCount) || 0) - ownIds.size);
        const belowBits = [];
        if (belowCount > 0 && node.level !== 'Position') {
            belowBits.push(`${belowCount} ${belowCount === 1 ? 'person' : 'people'} below`);
        }
        if (vacantDmCount > 0 && (node.level === 'Line' || node.level === 'Business Unit')) {
            belowBits.push(`${vacantDmCount} vacant DM seat${vacantDmCount === 1 ? '' : 's'}`);
        }
        rows.push({
            key: node.id,
            id: node.id,
            parentId: node.parentId,
            name: node.name,
            externalId: node.externalId,
            level: node.level,
            lineName: nextLine,
            businessUnitName: node.businessUnitName || '',
            callRate: node.callRate == null ? '' : String(node.callRate),
            amCallRate: node.amCallRate == null ? '' : String(node.amCallRate),
            pmCallRate: node.pmCallRate == null ? '' : String(node.pmCallRate),
            training,
            depth,
            depthStyle: `padding-left: ${depth * 1.25}rem`,
            hasChildren: node.hasChildren,
            expanded,
            chevronIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
            holders,
            defaultTitle,
            seatVacant,
            levelLabel: `${node.externalId || ''} · ${node.level}`,
            belowLabel: belowBits.join(' · '),
            holderLabel: seatVacant
                ? 'Vacant'
                : holders.map((holder) => `${holder.title} — ${holder.name}`).join(', '),
            isVacant: seatVacant,
            vacantClass: seatVacant ? 'badge badge-vacant' : 'badge badge-assigned',
            vacantLabel: seatVacant ? 'Vacant' : 'Assigned',
            vacantDmSeatCount: vacantDmCount,
            canEdit: node.canEdit,
            canDelete: node.canDelete,
            canAddChild: node.canAddChild,
            canDeleteNow: node.canDelete && this.setupOnlyActionsEnabled,
            canAddChildNow: node.canAddChild && this.setupOnlyActionsEnabled
        });

        if (node.children) {
            for (const child of node.children) {
                this.flattenNode(child, depth + 1, rows, nextLine, training);
            }
        }
    }

    isTrainingExternal(externalId) {
        return (externalId || '').toUpperCase().includes('TRAINING');
    }

    get territoryLineOptions() {
        const names = new Set();
        for (const row of this.allTerritoryRows || []) {
            if (row.level === 'Line' && (this.showTraining || !row.training)) {
                names.add(row.name);
            }
        }
        return [{ label: 'All lines', value: 'All' }].concat(
            [...names].sort().map((name) => ({ label: name, value: name }))
        );
    }

    get visibleUserRows() {
        return this.userRows;
    }

    get userLineOptions() {
        return this.distinctOptions(this.userLineOptionList, 'All lines');
    }

    get userTitleOptions() {
        return this.distinctOptions(this.userTitleOptionList, 'All titles');
    }

    get userBuOptions() {
        return this.distinctOptions(this.userBuOptionList, 'All BUs');
    }

    distinctOptions(values, allLabel) {
        const names = [...new Set(values.filter((value) => value))].sort();
        return [{ label: allLabel, value: 'All' }].concat(names.map((name) => ({ label: name, value: name })));
    }

    splitLabels(value) {
        return (value || '')
            .split(',')
            .map((part) => part.trim())
            .filter((part) => part);
    }

    handleShowTraining(event) {
        this.showTraining = event.target.checked;
        this.rebuildFlatRows();
    }

    handleTerritoryNameFilter(event) {
        this.territoryNameFilter = event.target.value || '';
        this.rebuildFlatRows();
    }

    handleTerritoryLineFilter(event) {
        this.territoryLineFilter = event.detail.value;
        this.rebuildFlatRows();
    }

    handleTerritoryBuFilter(event) {
        this.territoryBuFilter = event.detail.value;
        this.rebuildFlatRows();
    }

    handleLineBuFilter(event) {
        this.lineBuFilter = event.detail.value;
    }

    markUsersStale() {
        this.resultsStale = true;
    }

    handleUserLineFilter(event) {
        this.userLineFilter = event.detail.value;
        this.userPageNumber = 1;
        this.markUsersStale();
        this.scheduleUserReload();
    }

    handleUserTitleFilter(event) {
        this.userTitleFilter = event.detail.value;
        this.userPageNumber = 1;
        this.markUsersStale();
        this.scheduleUserReload();
    }

    handleUserTerritoryInput(event) {
        this.userTerritoryFilter = event.target.value || '';
        this.userPageNumber = 1;
        this.markUsersStale();
        this.scheduleUserReload(300);
    }

    handleUserTerritoryCommit(event) {
        this.userTerritoryFilter = event.target.value || '';
        this.userPageNumber = 1;
        this.markUsersStale();
        this.scheduleUserReload(0);
    }

    handleUserBuFilter(event) {
        this.userBuFilter = event.detail.value;
        this.userPageNumber = 1;
        this.markUsersStale();
        this.scheduleUserReload();
    }

    handleUserActiveFilter(event) {
        this.userActiveFilter = event.detail.value;
        this.userPageNumber = 1;
        this.markUsersStale();
        this.scheduleUserReload();
    }

    handleUserSearchInput(event) {
        this.userSearchTerm = event.target.value || '';
        this.userPageNumber = 1;
        this.markUsersStale();
        this.scheduleUserReload(300);
    }

    handleUserSearchCommit(event) {
        this.userSearchTerm = event.target.value || '';
        this.userPageNumber = 1;
        this.markUsersStale();
        this.scheduleUserReload(0);
    }

    handleClearUserFilters() {
        this.userSearchTerm = '';
        this.userTerritoryFilter = '';
        this.userLineFilter = 'All';
        this.userTitleFilter = 'All';
        this.userBuFilter = 'All';
        this.userActiveFilter = 'All';
        this.userPageNumber = 1;
        this.markUsersStale();
        this.scheduleUserReload(0);
    }

    handleUserPageSize(event) {
        const size = parseInt(event.detail.value, 10);
        if (!size || size === this.userPageSize) {
            return;
        }
        this.userPageSize = size;
        this.userPageNumber = 1;
        this.loadManagedUsers();
    }

    handleUserPrevPage() {
        if (this.userPageNumber <= 1 || this.isLoadingUsers) {
            return;
        }
        this.userPageNumber -= 1;
        this.loadManagedUsers();
    }

    handleUserNextPage() {
        if (this.isUserNextDisabled) {
            return;
        }
        this.userPageNumber += 1;
        this.loadManagedUsers();
    }

    handleDownloadOrganogram() {
        const nameTerm = (this.territoryNameFilter || '').trim().toLowerCase();
        const filtering =
            Boolean(nameTerm) ||
            (this.territoryLineFilter || 'All') !== 'All' ||
            (this.territoryBuFilter || 'All') !== 'All';
        const source = filtering ? this.flatRows : this.allTerritoryRows || [];
        const rows = source.filter((row) => this.showTraining || !row.training);
        // One line per seat holder (a vacant seat gets one line with no holder), so the same file
        // can be edited and uploaded back with Upload organogram. The Salesforce Ids let the upload
        // find the exact territory and person even after names change.
        const externalById = new Map((this.allTerritoryRows || []).map((row) => [row.id, row.externalId]));
        const marketingHolderIds = marketingSeatHolderIds(this.allTerritoryRows || []);
        const lines = [ORGANOGRAM_HEADER.join(',')];
        for (const row of rows) {
            const base = [
                row.id,
                row.externalId,
                externalById.get(row.parentId) || '',
                row.businessUnitName,
                row.lineName,
                row.level,
                row.name
            ];
            // A Brand Manager / Group Brand Lead also sits on the Line / BU so they see that team; that
            // access seat is not an organogram position, so they appear once, on their Marketing Seat.
            const holders = row.holders.filter((holder) => !isMarketingAccessSeat(row, holder, marketingHolderIds));
            const seats = holders.length
                ? holders
                : [{ title: row.defaultTitle, userId: '', name: '', username: '', employeeNumber: '' }];
            for (const seat of seats) {
                lines.push(
                    [...base, seat.title, seat.userId, seat.name, seat.username, seat.employeeNumber, '', '']
                        .map((value) => this.csvCell(value))
                        .join(',')
                );
            }
        }
        // downloadCsv adds the BOM so Excel opens Arabic names and dashes correctly.
        try {
            downloadCsv(`zeta-organogram-${todayIso()}.csv`, lines.join('\r\n'));
            this.toast('Organogram downloaded', `${lines.length - 1} rows saved.`, 'success');
        } catch (error) {
            this.toast('Download failed', this.errorMessage(error), 'error');
        }
    }

    get brickExportLabel() {
        return this.isExportingBricks ? `Preparing… ${this.brickExportProgress}` : 'Download full organogram (bricks)';
    }

    /**
     * The Drive "Total Organogram" layout: one row per 702-brick per position with the manager chain.
     * Follows the BU and Line filters; one server call per line keeps each call small.
     */
    async handleDownloadBrickOrganogram() {
        if (this.isExportingBricks) {
            return;
        }
        const lineFilter = this.territoryLineFilter || 'All';
        const buFilter = this.territoryBuFilter || 'All';
        const lines = (this.allTerritoryRows || []).filter(
            (row) =>
                row.level === 'Line' &&
                !row.training &&
                (lineFilter === 'All' || row.name === lineFilter) &&
                (buFilter === 'All' || row.businessUnitName === buFilter)
        );
        if (!lines.length) {
            this.toast('Nothing to download', 'No sales line matches the current filters.', 'warning');
            return;
        }
        this.isExportingBricks = true;
        try {
            const territoryCodes = await this.loadTerritoryCodes();
            const out = [TOTAL_ORGANOGRAM_HEADER.join(',')];
            for (let i = 0; i < lines.length; i++) {
                this.brickExportProgress = `${i + 1} of ${lines.length} lines`;
                // eslint-disable-next-line no-await-in-loop
                const rows = await getBrickRows({ lineId: lines[i].id });
                for (const row of rows || []) {
                    out.push(this.brickCsvLine(row, territoryCodes));
                }
            }
            downloadCsv(`zeta-total-organogram-${todayIso()}.csv`, out.join('\r\n'));
            this.toast('Full organogram downloaded', `${out.length - 1} rows saved.`, 'success');
        } catch (error) {
            this.toast('Download failed', this.errorMessage(error), 'error');
        } finally {
            this.isExportingBricks = false;
            this.brickExportProgress = '';
        }
    }

    /** Numeric Territory ID per position from the organogram workbook (kept in a static resource). */
    async loadTerritoryCodes() {
        const codes = new Map();
        try {
            const response = await fetch(ORGANOGRAM_SOURCE);
            const source = await response.json();
            for (const position of source.positions || []) {
                if (position.externalId && position.territoryId != null) {
                    codes.set(position.externalId, position.territoryId);
                }
            }
        } catch {
            // The column stays empty; the rest of the export does not depend on it.
        }
        return codes;
    }

    brickCsvLine(row, territoryCodes) {
        const person = (who) => [who?.name || '', who?.employeeNumber || '', who?.hireDate || ''];
        return [
            row.brick702,
            row.line,
            row.share,
            territoryCodes.get(row.positionExternalId),
            row.positionName,
            ...person(row.bum),
            ...person(row.nsm),
            ...person(row.asm),
            ...person(row.dm),
            row.brick70,
            row.brick148,
            row.rep?.name,
            `${row.line || ''}${row.brick702 || ''}`,
            row.rep?.employeeNumber,
            row.rep?.hireDate,
            '',
            '',
            row.districtName,
            '',
            '',
            ''
        ]
            .map((value) => this.csvCell(value))
            .join(',');
    }

    /** Every user matching the current Users filters (all pages), as a CSV. */
    async handleDownloadUsers() {
        if (this.isExportingUsers) {
            return;
        }
        this.isExportingUsers = true;
        try {
            const pageSize = 500;
            const all = [];
            for (let pageNumber = 1; pageNumber <= 50; pageNumber++) {
                // eslint-disable-next-line no-await-in-loop
                const page = await queryManagedUsers({
                    requestJson: JSON.stringify({
                        searchTerm: (this.userSearchTerm || '').trim(),
                        includeInactive: this.includeInactiveUsers === true,
                        titleFilter: this.userTitleFilter,
                        lineFilter: this.userLineFilter,
                        territoryFilter: (this.userTerritoryFilter || '').trim(),
                        businessUnitFilter: this.userBuFilter,
                        activeFilter: this.userActiveFilter,
                        pageNumber,
                        pageSize
                    })
                });
                const users = page?.users || [];
                all.push(...users);
                if (!page?.hasMore || !users.length || (page.pageNumber || pageNumber) < pageNumber) {
                    break;
                }
            }
            const lines = [USERS_EXPORT_HEADER.join(',')];
            for (const user of all) {
                lines.push(
                    [
                        user.name,
                        user.username,
                        user.email,
                        user.title,
                        user.businessUnit,
                        user.lineName,
                        user.territoryName,
                        user.profileName,
                        user.isActive ? 'Active' : 'Inactive',
                        user.hireDate,
                        user.resignationDate,
                        user.lastWorkDay
                    ]
                        .map((value) => this.csvCell(value))
                        .join(',')
                );
            }
            downloadCsv(`zeta-users-${todayIso()}.csv`, lines.join('\r\n'));
            this.toast('Users downloaded', `${all.length} users saved.`, 'success');
        } catch (error) {
            this.toast('Download failed', this.errorMessage(error), 'error');
        } finally {
            this.isExportingUsers = false;
        }
    }

    // ---------------------------------------------------------------- organogram upload

    handleOpenUpload() {
        this.uploadFileName = '';
        this.uploadRows = [];
        this.uploadPreview = null;
        this.uploadReleaseOther = false;
        this.uploadError = '';
        this.showUploadModal = true;
    }

    handleOpenUploadHelp() {
        this.showUploadHelp = true;
    }

    handleCloseUploadHelp() {
        this.showUploadHelp = false;
    }

    handleCloseUpload() {
        this.showUploadModal = false;
        this.uploadRows = [];
        this.uploadPreview = null;
    }

    handleUploadFile(event) {
        const file = event.target.files && event.target.files[0];
        if (!file) {
            return;
        }
        this.uploadFileName = file.name;
        this.uploadPreview = null;
        this.uploadError = '';
        // LWS blocks reading text/csv files as text, so read the bytes and decode them as UTF-8.
        file.arrayBuffer()
            .then((buffer) => {
                const text = new TextDecoder('utf-8').decode(buffer);
                const parsed = toUploadRows(parseCsv(text));
                if (parsed.missing.length) {
                    this.uploadRows = [];
                    this.uploadError = `The file needs a "${parsed.missing.join('", "')}" column. Download the organogram to get the template.`;
                    return;
                }
                if (!parsed.rows.length) {
                    this.uploadRows = [];
                    this.uploadError = 'The file has a header but no rows.';
                    return;
                }
                this.uploadRows = parsed.rows;
                this.runUploadPreview();
            })
            .catch(() => {
                this.uploadError = 'The file could not be read.';
            });
    }

    handleUploadReleaseOther(event) {
        this.uploadReleaseOther = event.target.checked;
        if (this.uploadRows.length) {
            this.runUploadPreview();
        }
    }

    async runUploadPreview() {
        this.isUploadBusy = true;
        try {
            this.uploadPreview = await previewOrganogramUpload({
                rowsJson: JSON.stringify(this.uploadRows),
                releaseOtherSeats: this.uploadReleaseOther
            });
        } catch (error) {
            this.uploadPreview = null;
            this.uploadError = this.errorMessage(error);
        } finally {
            this.isUploadBusy = false;
        }
    }

    get uploadPreviewLines() {
        return (this.uploadPreview?.lines || []).slice(0, UPLOAD_PREVIEW_LIMIT).map((line) => ({
            ...line,
            rowClass: line.action === 'Error' ? 'preview-error' : '',
            actionClass:
                line.action === 'Error'
                    ? 'badge badge-vacant'
                    : line.action === 'Remove' || line.action === 'Remove position'
                      ? 'badge badge-warning'
                      : 'badge badge-assigned'
        }));
    }

    get uploadPreviewTruncated() {
        const total = (this.uploadPreview?.lines || []).length;
        return total > UPLOAD_PREVIEW_LIMIT ? `Showing the first ${UPLOAD_PREVIEW_LIMIT} of ${total} lines.` : '';
    }

    get uploadChangeCount() {
        const preview = this.uploadPreview;
        return preview
            ? preview.assignCount +
                  preview.removeCount +
                  preview.roleChangeCount +
                  (preview.createCount || 0) +
                  (preview.renameCount || 0) +
                  (preview.moveCount || 0) +
                  (preview.deletePositionCount || 0)
            : 0;
    }

    get uploadSummary() {
        const p = this.uploadPreview;
        if (!p) {
            return '';
        }
        const bits = [
            `${p.rowCount} rows · ${p.seatCount} seats`,
            `${p.assignCount} to assign`,
            `${p.roleChangeCount} title changes`,
            `${p.removeCount} to remove`,
            `${p.unchangedCount} unchanged`
        ];
        const structure = [
            [p.createCount, 'new positions'],
            [p.renameCount, 'renamed'],
            [p.moveCount, 'moved'],
            [p.deletePositionCount, 'positions removed']
        ].filter(([count]) => count);
        for (const [count, label] of structure) {
            bits.push(`${count} ${label}`);
        }
        if (p.scheduledCount) {
            bits.push(`${p.scheduledCount} scheduled for a later date`);
        }
        if (p.errorCount) {
            bits.push(`${p.errorCount} errors (skipped)`);
        }
        return bits.join(' · ');
    }

    get isUploadApplyDisabled() {
        return this.isUploadBusy || !this.uploadPreview || this.uploadChangeCount === 0;
    }

    get uploadApplyLabel() {
        const count = this.uploadChangeCount;
        return count ? `Apply ${count} change${count === 1 ? '' : 's'}` : 'Nothing to apply';
    }

    async handleApplyUpload() {
        this.isUploadBusy = true;
        try {
            const result = await applyOrganogramUpload({
                rowsJson: JSON.stringify(this.uploadRows),
                releaseOtherSeats: this.uploadReleaseOther
            });
            this.showUploadModal = false;
            await this.refreshAll();
            this.toast(
                'Organogram uploaded',
                this.submitSummary(result),
                result.failed ? 'warning' : 'success'
            );
        } catch (error) {
            this.toast('Upload failed', this.errorMessage(error), 'error');
        } finally {
            this.isUploadBusy = false;
        }
    }

    submitSummary(result) {
        const bits = [`${result.applied || 0} applied now`];
        if (result.scheduled) {
            bits.push(`${result.scheduled} scheduled`);
        }
        if (result.failed) {
            bits.push(`${result.failed} failed`);
        }
        const detail = (result.messages || []).slice(0, 3).join(' ');
        return `${bits.join(', ')}.${detail ? ` ${detail}` : ''}`;
    }

    // ---------------------------------------------------------------- scheduled changes

    async loadScheduledChanges() {
        try {
            const rows = await getScheduledChanges({ userId: null });
            this.scheduledChanges = (rows || []).map((row) => ({
                ...row,
                actionLabel: row.action === 'Remove' ? 'Leaves' : 'Takes',
                effectiveLabel: formatIsoDate(row.effectiveDate)
            }));
        } catch {
            this.scheduledChanges = [];
        }
    }

    get scheduledButtonLabel() {
        const count = this.scheduledChanges.length;
        return count ? `Scheduled changes (${count})` : 'Scheduled changes';
    }

    get hasScheduledChanges() {
        return this.scheduledChanges.length > 0;
    }

    handleOpenScheduled() {
        this.showScheduledModal = true;
        this.loadScheduledChanges();
    }

    handleCloseScheduled() {
        this.showScheduledModal = false;
    }

    async handleCancelScheduled(event) {
        const changeId = event.currentTarget.dataset.id;
        if (!window.confirm('Cancel this scheduled change? Nothing will happen on its date.')) {
            return;
        }
        try {
            await cancelScheduledChange({ changeId });
            await this.loadScheduledChanges();
            if (this.showEditProfileModal && this.draftProfile.userId) {
                await this.loadEditDetails(this.draftProfile.userId);
            }
            this.toast('Change cancelled', 'The scheduled change was cancelled.', 'success');
        } catch (error) {
            this.toast('Cancel failed', this.errorMessage(error), 'error');
        }
    }

    csvCell(value) {
        const text = value == null ? '' : String(value);
        if (/[",\n]/.test(text)) {
            return `"${text.replace(/"/g, '""')}"`;
        }
        return text;
    }

    get maintenanceToggleLabel() {
        return this.showMaintenance ? 'Hide maintenance (one-off setup)' : 'Maintenance (one-off setup)';
    }

    get maintenanceToggleIcon() {
        return this.showMaintenance ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get maintenanceExpandedText() {
        return String(this.showMaintenance);
    }

    get maintenanceBusy() {
        return this.isApplyingLines || this.isMirroringLines || this.isSaving;
    }

    get pendingMaintenance() {
        return MAINTENANCE_ACTIONS.find((action) => action.key === this.pendingMaintenanceKey) || null;
    }

    handleToggleMaintenance() {
        this.showMaintenance = !this.showMaintenance;
        this.pendingMaintenanceKey = null;
    }

    handleMaintenanceRequest(event) {
        this.pendingMaintenanceKey = event.currentTarget.dataset.key;
    }

    handleMaintenanceCancel() {
        this.pendingMaintenanceKey = null;
    }

    async handleMaintenanceConfirm() {
        const action = this.pendingMaintenance;
        this.pendingMaintenanceKey = null;
        if (action) {
            await this[action.handler]();
        }
    }

    async handleApplyLines() {
        this.isApplyingLines = true;
        try {
            const result = await applyRealignedSalesLines();
            this.toast('Line assignments updated', result?.message || 'Product lines updated.', 'success');
            await refreshApex(this.wiredLinesResult);
        } catch (error) {
            this.toast('Could not update lines', error?.body?.message || error.message, 'error');
        } finally {
            this.isApplyingLines = false;
        }
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
        this.assignTerritoryRole = 'Trainer';
        this.assignUserSearchTerm = '';
        this.showAssignModal = true;
    }

    handleAssignRoleChange(event) {
        this.assignTerritoryRole = event.detail.value || 'Medical Rep';
    }

    handleAssignUserSearch(event) {
        this.assignUserSearchTerm = event.target.value || '';
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
            const role = this.assignTerritoryRole || 'Medical Rep';
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

    async handleManageLineProducts(event) {
        const lineId = event.currentTarget.dataset.id;
        const line = this.lineRows.find((row) => row.id === lineId);
        if (!line) {
            return;
        }
        this.manageLineId = line.id;
        this.manageLineName = line.name;
        this.lineProductTypeFilter = 'All';
        this.lineProductSearchTerm = '';
        this.assignProductSearchTerm = '';
        this.assignProductCandidates = [];
        this.assignProductId = null;
        this.assignMode = 'primary';
        this.showManageProductsModal = true;
        await this.reloadLineProducts();
    }

    handleCloseManageProductsModal() {
        this.showManageProductsModal = false;
        this.manageLineId = null;
        this.manageLineName = '';
        this.lineProductRows = [];
        this.assignProductCandidates = [];
        this.assignProductId = null;
    }

    handleLineProductTypeFilter(event) {
        this.lineProductTypeFilter = event.detail.value;
    }

    handleLineProductSearch(event) {
        this.lineProductSearchTerm = event.target.value || '';
    }

    handleAssignProductSearch(event) {
        this.assignProductSearchTerm = event.target.value || '';
    }

    handleAssignProductSelect(event) {
        this.assignProductId = event.detail.value;
    }

    handleAssignModeChange(event) {
        this.assignMode = event.detail.value;
    }

    async reloadLineProducts() {
        if (!this.manageLineId) {
            return;
        }
        this.isLoadingLineProducts = true;
        try {
            const rows = await getProductsForLine({ lineTerritoryId: this.manageLineId });
            this.lineProductRows = rows || [];
        } catch (error) {
            this.lineProductRows = [];
            this.toast('Load failed', this.errorMessage(error), 'error');
        } finally {
            this.isLoadingLineProducts = false;
        }
    }

    async handleSearchAssignableProducts() {
        if (!this.manageLineId) {
            return;
        }
        this.isSearchingAssignable = true;
        try {
            const rows = await searchAssignableProducts({
                lineTerritoryId: this.manageLineId,
                searchTerm: this.assignProductSearchTerm
            });
            this.assignProductCandidates = rows || [];
            this.assignProductId = null;
            if (!this.assignProductCandidates.length) {
                this.toast('No products', 'No matching products available to assign.', 'info');
            }
        } catch (error) {
            this.assignProductCandidates = [];
            this.toast('Search failed', this.errorMessage(error), 'error');
        } finally {
            this.isSearchingAssignable = false;
        }
    }

    async handleProductEffectiveFrom(event) {
        const productId = event.target.dataset.id;
        const alignmentId = event.target.dataset.alignment || null;
        const effectiveFrom = event.target.value || null;
        if (!productId || !this.manageLineId) {
            return;
        }
        this.isSaving = true;
        try {
            await setProductEffectiveFrom({
                alignmentId,
                productId,
                lineTerritoryId: this.manageLineId,
                effectiveFrom
            });
            await this.reloadLineProducts();
            this.toast('Saved', 'Product activation date updated for this line.', 'success');
        } catch (error) {
            this.toast('Save failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleAssignProductToLine() {
        if (!this.assignProductId || !this.manageLineId) {
            return;
        }
        this.isSaving = true;
        try {
            await setProductLineAssignment({
                productId: this.assignProductId,
                lineTerritoryId: this.manageLineId,
                asMirror: this.assignMode === 'mirror'
            });
            this.assignProductId = null;
            this.assignProductCandidates = [];
            await this.reloadLineProducts();
            await refreshApex(this.wiredLinesResult);
            this.toast('Product linked', 'Product was assigned to this line.', 'success');
        } catch (error) {
            this.toast('Assign failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleRemoveProductFromLine(event) {
        const productId = event.currentTarget.dataset.id;
        const productName = event.currentTarget.dataset.name;
        if (!window.confirm(`Remove ${productName} from ${this.manageLineName}?`)) {
            return;
        }
        this.isSaving = true;
        try {
            await clearProductLineAssignment({
                productId,
                lineTerritoryId: this.manageLineId
            });
            this.selectedProductIds.delete(productId);
            this.selectedProductIds = new Set(this.selectedProductIds);
            await this.reloadLineProducts();
            await refreshApex(this.wiredLinesResult);
            this.toast('Product removed', `${productName} was unlinked from this line.`, 'success');
        } catch (error) {
            this.toast('Remove failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleToggleProductSelection(event) {
        const productId = event.currentTarget.dataset.id;
        if (event.target.checked) {
            this.selectedProductIds.add(productId);
        } else {
            this.selectedProductIds.delete(productId);
        }
        this.selectedProductIds = new Set(this.selectedProductIds);
    }

    handleSelectAllProducts(event) {
        if (event.target.checked) {
            this.selectedProductIds = new Set(this.filteredLineProductRows.map((row) => row.id));
        } else {
            this.selectedProductIds = new Set();
        }
    }

    async handleBulkRemoveProducts() {
        const ids = [...this.selectedProductIds];
        if (!ids.length) {
            return;
        }
        if (!window.confirm(`Remove ${ids.length} product(s) from ${this.manageLineName}?`)) {
            return;
        }
        this.isSaving = true;
        try {
            const result = await removeProductsFromLine({
                productIds: ids,
                lineTerritoryId: this.manageLineId
            });
            const failedRows = (result.rows || []).filter((row) => !row.success);
            // keep only the failed products selected so the user can retry or inspect them
            this.selectedProductIds = new Set(failedRows.map((row) => row.productId));
            await this.reloadLineProducts();
            await refreshApex(this.wiredLinesResult);
            if (failedRows.length) {
                const detail = failedRows
                    .slice(0, 5)
                    .map((row) => `${row.productName || row.productId}: ${row.message}`)
                    .join(' | ');
                const more = failedRows.length > 5 ? ` (+${failedRows.length - 5} more)` : '';
                this.toast(
                    'Some products were not removed',
                    `${result.removed} removed, ${failedRows.length} failed. ${detail}${more}`,
                    result.removed ? 'warning' : 'error'
                );
            } else {
                this.toast(
                    'Products removed',
                    `${result.removed} product(s) unlinked from this line.`,
                    'success'
                );
            }
        } catch (error) {
            this.toast('Bulk remove failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleSeatBrandManagers() {
        this.isSaving = true;
        try {
            const result = await seatMarketingOnOrganogram();
            await this.refreshAll();
            this.toast(
                'Brand Managers seated',
                (result?.messages && result.messages[0]) || 'Marketing seats updated.',
                'success'
            );
        } catch (error) {
            this.toast('Seat failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleApplyStandardMirrors() {
        this.isMirroringLines = true;
        try {
            // CHC_Sales mirrors every promoted line; CVM-I/II mirror from CHC directly.
            const chcAll = await mirrorAllPromotedLines({ mirrorLineName: 'CHC_Sales' });
            const chc = chcAll.updated;
            const git = await mirrorLineProducts({ sourceLineName: 'GIT-I', mirrorLineName: 'GIT-SALES' });
            const git2 = await mirrorLineProducts({ sourceLineName: 'GIT-II', mirrorLineName: 'GIT-SALES' });
            const git3 = await mirrorLineProducts({ sourceLineName: 'GIT-III', mirrorLineName: 'GIT-SALES' });
            const cvm1 = await mirrorLineProducts({
                sourceLineName: 'CHC',
                mirrorLineName: 'CVM-I'
            });
            const cvm2 = await mirrorLineProducts({
                sourceLineName: 'CHC',
                mirrorLineName: 'CVM-II'
            });
            await refreshApex(this.wiredLinesResult);
            this.toast(
                'Mirrors applied',
                `All lines→CHC_Sales ${chc}${chcAll.failed ? ` (${chcAll.failed} failed)` : ''}; GIT→GIT-SALES ${git + git2 + git3}; CHC→CVM ${cvm1 + cvm2}.`,
                'success'
            );
        } catch (error) {
            this.toast('Mirror failed', this.errorMessage(error), 'error');
        } finally {
            this.isMirroringLines = false;
        }
    }

    handleAddTerritory() {
        this.draftTerritory = {
            recordId: null,
            name: '',
            externalId: '',
            parentId: null,
            level: 'District',
            callRate: null,
            amCallRate: null,
            pmCallRate: null
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
            level: row.level,
            callRate: row.callRate === '' || row.callRate == null ? null : Number(row.callRate),
            amCallRate: row.amCallRate === '' || row.amCallRate == null ? null : Number(row.amCallRate),
            pmCallRate: row.pmCallRate === '' || row.pmCallRate == null ? null : Number(row.pmCallRate)
        };
        this.showTerritoryModal = true;
    }

    handleAddChildTerritory(event) {
        const row = this.flatRows.find((item) => item.id === event.currentTarget.dataset.id);
        if (!row) {
            return;
        }
        const childLevel =
            row.level === 'Head Office'
                ? 'Business Unit'
                : row.level === 'Business Unit'
                  ? 'Line'
                  : row.level === 'Line'
                    ? 'District'
                    : 'Position';
        this.draftTerritory = {
            recordId: null,
            name: '',
            externalId: '',
            parentId: row.id,
            level: childLevel,
            callRate: null,
            amCallRate: null,
            pmCallRate: null
        };
        this.showTerritoryModal = true;
    }

    handleTerritoryFieldChange(event) {
        const field = event.target.dataset.field;
        let value = event.detail.value;
        if (field === 'callRate' || field === 'amCallRate' || field === 'pmCallRate') {
            value = value === '' || value == null ? null : Number(value);
        }
        this.draftTerritory = {
            ...this.draftTerritory,
            [field]: value
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

    handleProfileFieldChange(event) {
        const field = event.target.dataset.field;
        this.draftProfile = {
            ...this.draftProfile,
            [field]: event.detail.value
        };
    }

    handlePasswordFieldChange(event) {
        const field = event.target.dataset.field;
        this.draftPassword = {
            ...this.draftPassword,
            [field]: event.detail.value
        };
        this.generatedPassword = '';
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

    handleSelectAllUsers(event) {
        const checked = event.target.checked;
        const next = new Set(this.selectedUserIds);
        for (const user of this.visibleUserRows) {
            if (checked) {
                next.add(user.id);
            } else {
                next.delete(user.id);
            }
        }
        this.selectedUserIds = next;
        this.syncUserSelectionFlags();
    }

    handleToggleUserSelection(event) {
        const userId = event.currentTarget.dataset.id;
        if (event.target.checked) {
            this.selectedUserIds.add(userId);
        } else {
            this.selectedUserIds.delete(userId);
        }
        this.selectedUserIds = new Set(this.selectedUserIds);
        this.syncUserSelectionFlags();
    }

    syncUserSelectionFlags() {
        const selectedIds = this.selectedUserIds;
        this.userRows = this.userRows.map((user) => decorateManagedUser(user, selectedIds));
    }

    handleUserMenuSelect(event) {
        const userId = event.currentTarget.dataset.id;
        const action = event.detail.value;
        const source = { currentTarget: { dataset: { id: userId } } };
        if (action === 'fieldLoginAs') {
            this.openFieldLoginAs(userId, event.currentTarget.dataset.name);
            return;
        }
        if (action === 'otp') {
            this.handleOpenPasswordForUser(source);
            return;
        }
        if (action === 'preview') {
            this.handlePreviewAsUser(source);
            return;
        }
        if (action === 'active') {
            this.handleToggleUserActive(source);
            return;
        }
        if (action === 'view') {
            this.handleViewUserRecord(source);
        }
    }

    openFieldLoginAs(userId, userName) {
        this.fieldLoginAsUserId = userId;
        this.fieldLoginAsName = userName || 'this user';
        this.fieldLoginAsReason = '';
        this.fieldLoginAsUrl = '';
        this.showFieldLoginAsModal = true;
    }

    get isFieldLoginAsDisabled() {
        return this.isSaving || !this.fieldLoginAsReason || !this.fieldLoginAsReason.trim();
    }

    handleFieldLoginAsReason(event) {
        this.fieldLoginAsReason = event.target.value;
    }

    async handleStartFieldLoginAs() {
        this.isSaving = true;
        try {
            const result = await startFieldSession({
                userId: this.fieldLoginAsUserId,
                reason: this.fieldLoginAsReason
            });
            this.fieldLoginAsName = result?.userName || this.fieldLoginAsName;
            if (result?.error) {
                this.toast('Field app session failed', result.error, 'error');
                return;
            }
            this.fieldLoginAsUrl = result?.fieldAppUrl || '';
        } catch (error) {
            this.toast('Field app session failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleFieldLoginAsOpened() {
        // The link carries a live token; drop it once it has been used.
        window.setTimeout(() => this.handleCloseFieldLoginAs(), 0);
    }

    handleCloseFieldLoginAs() {
        this.showFieldLoginAsModal = false;
        this.fieldLoginAsUrl = '';
        this.fieldLoginAsReason = '';
        this.fieldLoginAsUserId = null;
    }

    async handlePreviewAsUser(event) {
        const userId = event.currentTarget.dataset.id;
        this.isSaving = true;
        try {
            const result = await previewAsUser({ userId });
            this.toast(
                'Territory preview',
                result?.message ||
                    'Preview context set. Use Salesforce Login As for full impersonation; OTP only resets passwords.',
                'success'
            );
        } catch (error) {
            this.toast('Preview failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleClearTerritoryPreview() {
        try {
            await clearPreview();
            this.toast('Preview cleared', 'Territory preview context cleared.', 'success');
        } catch (error) {
            this.toast('Clear failed', this.errorMessage(error), 'error');
        }
    }

    async handleEditProfile(event) {
        const user = this.userRows.find((row) => row.id === event.currentTarget.dataset.id);
        if (!user) {
            return;
        }
        this.draftProfile = {
            userId: user.id,
            name: user.name,
            firstName: user.firstName || '',
            lastName: user.lastName || '',
            email: user.email || '',
            username: user.username || '',
            title: user.title || '',
            department: '',
            division: '',
            employeeNumber: '',
            mobilePhone: '',
            phone: '',
            managerId: '',
            hireDate: null,
            resignationDate: null,
            lastWorkDay: null
        };
        this.editDetails = null;
        this.managerSearchTerm = '';
        this.managerCandidates = [];
        this.resetPromotion(false);
        this.showEditProfileModal = true;
        await this.loadEditDetails(user.id);
    }

    async loadEditDetails(userId) {
        this.isLoadingEditDetails = true;
        try {
            const details = await getUserEditDetails({ userId });
            if (!details || this.draftProfile.userId !== userId) {
                return;
            }
            this.editDetails = details;
            this.draftProfile = {
                ...this.draftProfile,
                name: details.name,
                firstName: details.firstName || '',
                lastName: details.lastName || '',
                email: details.email || '',
                username: details.username || '',
                title: details.title || '',
                department: details.department || '',
                division: details.division || '',
                employeeNumber: details.employeeNumber || '',
                mobilePhone: details.mobilePhone || '',
                phone: details.phone || '',
                managerId: details.managerId || '',
                hireDate: formatIsoDate(details.hireDate) || null,
                resignationDate: formatIsoDate(details.resignationDate) || null,
                lastWorkDay: formatIsoDate(details.lastWorkDay) || null
            };
            if (details.managerId) {
                this.managerCandidates = [{ id: details.managerId, label: details.managerName || details.managerId }];
            }
        } catch (error) {
            this.toast('Could not load user', this.errorMessage(error), 'error');
        } finally {
            this.isLoadingEditDetails = false;
        }
    }

    get editModalTitle() {
        return this.draftProfile.name ? `Edit User — ${this.draftProfile.name}` : 'Edit User';
    }

    get editDateFields() {
        return this.editDetails?.dateFields || ['Hire_Date__c'];
    }

    get hasResignationField() {
        return this.editDateFields.includes('Resignation_Date__c');
    }

    get hasLastWorkDayField() {
        return this.editDateFields.includes('Last_Work_Day__c');
    }

    get editSeats() {
        return (this.editDetails?.seats || []).map((seat) => ({
            ...seat,
            key: seat.territoryId,
            roleLabel: seat.role || DEFAULT_SEAT_TITLE[seat.territoryType] || '—'
        }));
    }

    get hasEditSeats() {
        return this.editSeats.length > 0;
    }

    get editScheduled() {
        return (this.editDetails?.scheduled || []).map((row) => ({
            ...row,
            text: `${formatIsoDate(row.effectiveDate)}: ${row.action === 'Remove' ? 'leaves' : 'takes'} ${row.territoryName}${
                row.role ? ` as ${row.role}` : ''
            }${row.newTitle ? `; job title becomes ${row.newTitle}` : ''}`
        }));
    }

    get hasEditScheduled() {
        return this.editScheduled.length > 0;
    }

    get editHistory() {
        return (this.editDetails?.history || []).slice(0, 5).map((row) => ({
            ...row,
            text: `${formatIsoDate(row.effectiveDate)} · ${row.status}: ${row.action === 'Remove' ? 'left' : 'took'} ${
                row.territoryName
            }${row.role ? ` as ${row.role}` : ''}${row.message ? ` (${row.message})` : ''}`
        }));
    }

    get hasEditHistory() {
        return this.editHistory.length > 0;
    }

    get managerOptions() {
        const options = [{ label: '— No manager —', value: '' }];
        const seen = new Set(['']);
        for (const candidate of this.managerCandidates) {
            if (!seen.has(candidate.id) && candidate.id !== this.draftProfile.userId) {
                seen.add(candidate.id);
                options.push({ label: candidate.label, value: candidate.id });
            }
        }
        return options;
    }

    handleManagerSearch(event) {
        this.managerSearchTerm = event.target.value || '';
        window.clearTimeout(this._managerSearchTimer);
        const term = this.managerSearchTerm.trim();
        if (term.length < 2) {
            return;
        }
        this._managerSearchTimer = window.setTimeout(async () => {
            try {
                const rows = await getAssignableUsers({ searchTerm: term });
                const current = this.managerCandidates.filter((c) => c.id === this.draftProfile.managerId);
                this.managerCandidates = current.concat(
                    (rows || []).slice(0, 50).map((row) => ({
                        id: row.id,
                        label: [row.name, row.title, row.territoryName].filter(Boolean).join(' · ')
                    }))
                );
            } catch (error) {
                this.toast('Manager search failed', this.errorMessage(error), 'error');
            }
        }, 300);
    }

    handleCloseEditProfileModal() {
        this.showEditProfileModal = false;
        this.editDetails = null;
        this.resetPromotion(false);
    }

    get isProfileSaveDisabled() {
        return (
            this.isSaving ||
            this.isLoadingEditDetails ||
            !this.draftProfile.userId ||
            !this.draftProfile.lastName ||
            !this.draftProfile.email ||
            !this.draftProfile.username ||
            (this.promotion.open && !this.promotion.territoryExternalId)
        );
    }

    get profileSaveLabel() {
        if (!this.promotion.open) {
            return 'Save';
        }
        const effective = this.promotion.effectiveDate;
        return effective && effective > todayIso() ? 'Save and schedule move' : 'Save and move now';
    }

    // ---------------------------------------------------------------- promotion / transfer

    resetPromotion(open) {
        this.promotion = {
            open,
            searchTerm: '',
            territoryExternalId: '',
            role: '',
            newTitle: '',
            titleTouched: false,
            effectiveDate: todayIso(),
            releaseOtherSeats: true,
            replaceSameRole: true
        };
    }

    handleTogglePromotion() {
        this.resetPromotion(!this.promotion.open);
    }

    get promotionToggleLabel() {
        return this.promotion.open ? 'Cancel promotion / move' : 'Promote or move to another position…';
    }

    get promotionTarget() {
        const ext = this.promotion.territoryExternalId;
        return ext ? (this.allTerritoryRows || []).find((row) => row.externalId === ext) || null : null;
    }

    get promotionTerritoryOptions() {
        const term = (this.promotion.searchTerm || '').trim().toLowerCase();
        const options = [];
        const target = this.promotionTarget;
        if (target) {
            options.push({ label: this.positionLabel(target), value: target.externalId });
        }
        for (const row of this.allTerritoryRows || []) {
            if (options.length >= 60) {
                break;
            }
            if (row.training || !row.externalId || row.level === 'Head Office' || (target && row.id === target.id)) {
                continue;
            }
            const hay = `${row.name} ${row.externalId} ${row.lineName} ${row.businessUnitName} ${row.holderLabel}`.toLowerCase();
            if (term && !term.split(/\s+/).every((token) => hay.includes(token))) {
                continue;
            }
            options.push({ label: this.positionLabel(row), value: row.externalId });
        }
        return options;
    }

    positionLabel(row) {
        const where = [row.level, row.lineName && row.lineName !== row.name ? row.lineName : row.businessUnitName]
            .filter(Boolean)
            .join(' · ');
        const who = row.seatVacant ? 'Vacant' : row.holders.map((holder) => holder.name).join(', ');
        return `${row.name} — ${where} — ${who}`;
    }

    get promotionPlaceholder() {
        return (this.promotion.searchTerm || '').trim()
            ? 'Pick from the matches'
            : 'Type above to search, or pick';
    }

    get promotionRoleOptions() {
        const options = [...TERRITORY_ASSIGN_ROLE_OPTIONS];
        const role = this.promotion.role;
        if (role && !options.some((option) => option.value === role)) {
            options.push({ label: role, value: role });
        }
        return options;
    }

    /** People who already hold the chosen title on the chosen seat. */
    get promotionDisplaced() {
        const target = this.promotionTarget;
        const role = (this.promotion.role || '').toLowerCase();
        if (!target) {
            return [];
        }
        return target.holders.filter(
            (holder) => holder.userId !== this.draftProfile.userId && (holder.title || '').toLowerCase() === role
        );
    }

    get hasPromotionDisplaced() {
        return this.promotionDisplaced.length > 0;
    }

    get promotionReplaceLabel() {
        const names = this.promotionDisplaced.map((holder) => holder.name).join(', ');
        return `Remove ${names} from this seat (they hold the same title)`;
    }

    get promotionReleasable() {
        const ext = this.promotion.territoryExternalId;
        return this.editSeats.filter(
            (seat) =>
                seat.externalId !== ext &&
                (seat.externalId || '').startsWith('TERR_') &&
                !(seat.externalId || '').includes('TRAINING')
        );
    }

    get hasPromotionReleasable() {
        return this.promotionReleasable.length > 0;
    }

    get promotionReleaseLabel() {
        const names = this.promotionReleasable.map((seat) => `${seat.territoryName} (${seat.roleLabel})`).join(', ');
        return `Leave current seat${this.promotionReleasable.length === 1 ? '' : 's'}: ${names}`;
    }

    get promotionSummary() {
        const target = this.promotionTarget;
        if (!target) {
            return '';
        }
        const p = this.promotion;
        const name = this.draftProfile.name || 'This person';
        const when = p.effectiveDate && p.effectiveDate > todayIso() ? `On ${p.effectiveDate}` : 'Now';
        const parts = [`${when}: ${name} takes ${target.name} as ${p.role || target.defaultTitle}`];
        if (p.releaseOtherSeats && this.hasPromotionReleasable) {
            parts.push(`and leaves ${this.promotionReleasable.map((seat) => seat.territoryName).join(', ')}`);
        }
        let text = parts.join(' ');
        if (p.newTitle && p.newTitle !== this.draftProfile.title) {
            text += `. Job title becomes ${p.newTitle}`;
        }
        if (p.replaceSameRole && this.hasPromotionDisplaced) {
            text += `. ${this.promotionDisplaced.map((holder) => holder.name).join(', ')} leaves the seat`;
        }
        if (when !== 'Now') {
            text += '. Until then nothing changes; the move is listed under Scheduled changes.';
        }
        return `${text}.`;
    }

    handlePromotionSearch(event) {
        this.promotion = { ...this.promotion, searchTerm: event.target.value || '' };
    }

    handlePromotionTerritory(event) {
        const ext = event.detail.value;
        const row = (this.allTerritoryRows || []).find((item) => item.externalId === ext);
        const role = row ? row.defaultTitle : this.promotion.role;
        this.promotion = {
            ...this.promotion,
            territoryExternalId: ext,
            role,
            newTitle: this.promotion.titleTouched ? this.promotion.newTitle : role
        };
    }

    handlePromotionField(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.detail.value;
        const next = { ...this.promotion, [field]: value };
        if (field === 'newTitle') {
            next.titleTouched = true;
        }
        if (field === 'role' && !this.promotion.titleTouched) {
            next.newTitle = value;
        }
        this.promotion = next;
    }

    async handleSaveProfile() {
        this.isSaving = true;
        const userId = this.draftProfile.userId;
        try {
            await saveUserDetails({ formJson: JSON.stringify(this.draftProfile) });
            let message = 'User details were saved.';
            let variant = 'success';
            if (this.promotion.open && this.promotion.territoryExternalId) {
                const p = this.promotion;
                const result = await promoteUser({
                    requestJson: JSON.stringify({
                        userId,
                        territoryExternalId: p.territoryExternalId,
                        role: p.role,
                        newTitle: p.newTitle && p.newTitle !== this.draftProfile.title ? p.newTitle : null,
                        effectiveDate: p.effectiveDate,
                        releaseOtherSeats: p.releaseOtherSeats && this.hasPromotionReleasable,
                        replaceSameRole: p.replaceSameRole && this.hasPromotionDisplaced
                    })
                });
                if (result.failed) {
                    variant = 'warning';
                    message = `Details saved, but the move failed. ${(result.messages || []).join(' ')}`;
                } else if (result.scheduled) {
                    message = `Details saved. The move is scheduled for ${p.effectiveDate}.`;
                } else {
                    message = 'Details saved and the move is done.';
                }
            }
            this.showEditProfileModal = false;
            this.resetPromotion(false);
            await this.refreshAll();
            await this.loadScheduledChanges();
            this.toast('User updated', message, variant);
        } catch (error) {
            this.toast('Update failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleOpenPasswordForUser(event) {
        this.openPasswordModal([event.currentTarget.dataset.id]);
    }

    handleOpenPasswordForSelected() {
        if (!this.hasSelectedUsers) {
            this.toast('No users selected', 'Select one or more users first.', 'warning');
            return;
        }
        this.openPasswordModal([...this.selectedUserIds]);
    }

    openPasswordModal(userIds) {
        // Managers cannot set passwords. Refuse up front instead of showing a generated OTP
        // that the server would then reject.
        if (this.canManageUsers === false) {
            this.toast('Not allowed', MANAGE_USERS_REFUSAL, 'error');
            return;
        }
        this.passwordTargetIds = userIds;
        this.draftPassword = { password: '', confirmPassword: '' };
        this.generatedPassword = '';
        this.showPasswordModal = true;
    }

    handleClosePasswordModal() {
        this.showPasswordModal = false;
        this.passwordTargetIds = [];
        this.generatedPassword = '';
    }

    handleGeneratePassword() {
        const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
        const digits = '23456789';
        const alphabet = letters + digits;
        let randomPart = '';
        while (randomPart.length < 9) {
            randomPart += alphabet.charAt(Math.floor(Math.random() * alphabet.length));
        }
        randomPart += digits.charAt(Math.floor(Math.random() * digits.length));
        const password = `Zeta!${randomPart}`;
        this.draftPassword = {
            password,
            confirmPassword: password
        };
        this.generatedPassword = password;
    }

    async handleSavePasswords() {
        const password = (this.draftPassword.password || '').trim();
        const confirm = (this.draftPassword.confirmPassword || '').trim();
        if (password && password !== confirm) {
            this.toast('Password mismatch', 'Password and confirmation must match.', 'error');
            return;
        }
        if (password && !passwordMeetsPolicy(password)) {
            this.toast(
                'Password too weak',
                'Use at least 8 characters, with letters and numbers.',
                'error'
            );
            return;
        }
        this.isSaving = true;
        try {
            const result = await setOneTimePasswords({
                userIds: this.passwordTargetIds,
                password: password || null
            });
            if (result.successCount) {
                this.generatedPassword = result.passwordUsed;
                this.draftPassword = {
                    password: result.passwordUsed,
                    confirmPassword: result.passwordUsed
                };
                await this.loadManagedUsers();
            }
            const messages = (result.messages || []).filter(Boolean);
            const summary = messages.length
                ? messages.slice(0, 3).join(' ')
                : `${result.successCount || 0} updated`;
            const problem = result.failureCount || result.emailFailureCount;
            this.toast(
                result.successCount ? 'One-time password set' : 'Password was not set',
                summary,
                result.successCount ? (problem ? 'warning' : 'success') : 'error'
            );
        } catch (error) {
            this.toast('Password reset failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleToggleUserActive(event) {
        const userId = event.currentTarget.dataset.id;
        const user = this.userRows.find((row) => row.id === userId);
        if (!user) {
            return;
        }
        const nextActive = !user.isActive;
        if (!nextActive && user.isSystemAdmin) {
            this.toast('Not allowed', 'System Administrators cannot be deactivated here.', 'warning');
            return;
        }
        const verb = nextActive ? 'activate' : 'deactivate';
        if (!window.confirm(`${verb[0].toUpperCase()}${verb.slice(1)} ${user.name}?`)) {
            return;
        }
        await this.applyUserActiveStatus([userId], nextActive);
    }

    async handleBulkActivate() {
        if (!this.hasSelectedUsers) {
            this.toast('No users selected', 'Select one or more users first.', 'warning');
            return;
        }
        await this.applyUserActiveStatus([...this.selectedUserIds], true);
    }

    async handleBulkDeactivate() {
        if (!this.hasSelectedUsers) {
            this.toast('No users selected', 'Select one or more users first.', 'warning');
            return;
        }
        if (
            !window.confirm(
                `Deactivate ${this.selectedUserCount} selected user(s)? System Admins will be skipped.`
            )
        ) {
            return;
        }
        await this.applyUserActiveStatus([...this.selectedUserIds], false);
    }

    async applyUserActiveStatus(userIds, isActive) {
        this.isSaving = true;
        try {
            const result = await setUsersActive({ userIds, isActive });
            await refreshApex(this.wiredManagedUsersResult);
            await refreshApex(this.wiredAssignUsersResult);
            const summary =
                `${result.successCount} updated` +
                (result.skippedCount ? `, ${result.skippedCount} skipped` : '') +
                (result.failureCount ? `, ${result.failureCount} failed` : '');
            this.toast(
                isActive ? 'Users activated' : 'Users deactivated',
                summary,
                result.failureCount ? 'warning' : 'success'
            );
        } catch (error) {
            this.toast('Status update failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleViewUserRecord(event) {
        const userId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: userId,
                objectApiName: 'User',
                actionName: 'view'
            }
        });
    }

    async handleSaveTerritory() {
        this.isSaving = true;
        try {
            // Sent as JSON: passed as an object, Aura left the Apex form fields empty.
            await saveTerritory({ formJson: JSON.stringify(this.draftTerritory) });
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
            await refreshApex(this.wiredManagedUsersResult);
            await refreshApex(this.wiredAssignUsersResult);
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
        await refreshApex(this.wiredAssignUsersResult);
        await this.loadManagedUsers();
        this.rebuildFlatRows();
    }

    errorMessage(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}