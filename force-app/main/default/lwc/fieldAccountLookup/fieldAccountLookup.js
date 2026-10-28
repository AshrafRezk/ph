import { LightningElement, api } from 'lwc';
import searchAccounts from '@salesforce/apex/FieldAccountSearch.search';

let lookupSeq = 0;

export default class FieldAccountLookup extends LightningElement {
    @api label = 'Account';
    @api placeholder = 'Search a name in Arabic or English';
    @api accountId;
    @api accountName;
    @api iconName;
    @api recordTypeLabel;
    @api suggestions;
    @api required = false;
    @api invalid = false;
    @api locked = false;

    query = '';
    menuOpen = false;
    isSearching = false;
    searchFailed = false;
    results = [];
    activeIndex = 0;
    inputId = 'fal-input';
    labelId = 'fal-label';
    listId = 'fal-list';
    _searchToken = 0;
    _popoverReady = false;

    constructor() {
        super();
        lookupSeq += 1;
        this.inputId = `fal-input-${lookupSeq}`;
        this.labelId = `fal-label-${lookupSeq}`;
        this.listId = `fal-list-${lookupSeq}`;
    }

    handleWindowPointer = (event) => {
        if (!this.menuOpen) {
            return;
        }
        const path = event.composedPath ? event.composedPath() : [];
        if (path.includes(this.template.host)) {
            return;
        }
        this.closeMenu();
    };

    positionMenu = () => {
        if (this.menuOpen) {
            this.placeMenu(this.template.querySelector('[data-menu]'));
        }
    };

    connectedCallback() {
        window.addEventListener('pointerdown', this.handleWindowPointer, true);
        window.addEventListener('resize', this.positionMenu);
        window.addEventListener('scroll', this.positionMenu, true);
        window.visualViewport?.addEventListener('resize', this.positionMenu);
        window.visualViewport?.addEventListener('scroll', this.positionMenu);
    }

    disconnectedCallback() {
        window.removeEventListener('pointerdown', this.handleWindowPointer, true);
        window.removeEventListener('resize', this.positionMenu);
        window.removeEventListener('scroll', this.positionMenu, true);
        window.visualViewport?.removeEventListener('resize', this.positionMenu);
        window.visualViewport?.removeEventListener('scroll', this.positionMenu);
        window.clearTimeout(this._timer);
        this.closePopover();
    }

    renderedCallback() {
        this.syncMenu();
        if (this._focusAfterClear && !this.hasSelection) {
            this._focusAfterClear = false;
            this.focus();
        }
    }

    @api
    focus() {
        const input = this.template.querySelector('.lookup-input');
        if (!input) {
            return false;
        }
        input.focus();
        return true;
    }

    get hasSelection() {
        return Boolean(this.accountId);
    }

    get showClear() {
        return this.locked !== true;
    }

    get hasQuery() {
        return this.query.trim().length > 0;
    }

    get selectedIcon() {
        return this.iconName || 'standard:account';
    }

    get selectedTheme() {
        return `mark ${themeFor(this.selectedIcon)}`;
    }

    get controlClass() {
        return `control${this.invalid ? ' is-invalid' : ''}`;
    }

    get selectedControlClass() {
        return 'control is-selected';
    }

    get menuClass() {
        return `menu${this.menuOpen ? ' is-open' : ''}`;
    }

    get menuTitle() {
        return this.query.trim().length >= 2 ? 'Accounts' : 'Recent';
    }

    get menuRows() {
        const source = this.query.trim().length >= 2 ? this.results : this.recentRows;
        return source.map((row, index) => ({
            ...row,
            optionId: `${this.listId}-${index}`,
            className: `menu-row${index === this.activeIndex ? ' is-active' : ''}`,
            selected: index === this.activeIndex ? 'true' : 'false',
            theme: `mark ${themeFor(row.iconName)}`
        }));
    }

    get showEmpty() {
        return !this.isSearching && !this.searchFailed && this.query.trim().length >= 2 && this.menuRows.length === 0;
    }

    get statusMessage() {
        if (this.isSearching && this.menuRows.length === 0) {
            return 'Searching…';
        }
        if (this.searchFailed) {
            return "Couldn't search just now. Try again.";
        }
        if (this.showEmpty) {
            return 'No accounts match. Try another spelling.';
        }
        return '';
    }

    get liveStatus() {
        if (!this.menuOpen) {
            return '';
        }
        if (this.isSearching) {
            return 'Searching';
        }
        if (this.statusMessage) {
            return this.statusMessage;
        }
        const count = this.menuRows.length;
        return count === 1 ? '1 account' : `${count} accounts`;
    }

    get expanded() {
        return this.menuOpen ? 'true' : 'false';
    }

    get activeDescendant() {
        if (!this.menuOpen) {
            return null;
        }
        const row = this.menuRows[this.activeIndex];
        return row ? row.optionId : null;
    }

    get recentRows() {
        const term = foldLoose(this.query);
        return normalizeRows(this.suggestions)
            .filter((row) => !term || foldLoose(row.accountName).includes(term))
            .slice(0, 8);
    }

    handleFocus() {
        this.openMenu();
    }

    handleInput(event) {
        this.query = event.target.value || '';
        this.activeIndex = 0;
        this.searchFailed = false;
        this.openMenu();
        this.debounceSearch();
    }

    handleKeydown(event) {
        const rows = this.menuRows;
        if (event.key === 'ArrowDown') {
            event.preventDefault();
            this.openMenu();
            this.activeIndex = rows.length ? (this.activeIndex + 1) % rows.length : 0;
            return;
        }
        if (event.key === 'ArrowUp') {
            event.preventDefault();
            this.openMenu();
            this.activeIndex = rows.length ? (this.activeIndex - 1 + rows.length) % rows.length : 0;
            return;
        }
        if (event.key === 'Home') {
            event.preventDefault();
            this.openMenu();
            this.activeIndex = 0;
            return;
        }
        if (event.key === 'End') {
            event.preventDefault();
            this.openMenu();
            this.activeIndex = rows.length ? rows.length - 1 : 0;
            return;
        }
        if (event.key === 'Enter') {
            event.preventDefault();
            const row = rows[this.activeIndex];
            if (row && this.menuOpen) {
                this.commit(row);
            }
            return;
        }
        if (event.key === 'Escape' && this.menuOpen) {
            event.preventDefault();
            event.stopPropagation();
            this.closeMenu();
        }
    }

    handleClear() {
        this._focusAfterClear = true;
        this.query = '';
        this.results = [];
        this.searchFailed = false;
        this.closeMenu();
        this.dispatchChange({
            accountId: null,
            accountName: null,
            visitId: null,
            recordTypeLabel: null,
            iconName: null
        });
    }

    handleClearQuery(event) {
        event.preventDefault();
        this.query = '';
        this.results = [];
        this.searchFailed = false;
        this.isSearching = false;
        this.activeIndex = 0;
        window.clearTimeout(this._timer);
        this.openMenu();
        this.focus();
    }

    handleMenuMouseDown(event) {
        event.preventDefault();
    }

    handlePick(event) {
        const accountId = event.currentTarget.dataset.accountId;
        const row = this.menuRows.find((item) => item.accountId === accountId);
        if (row) {
            this.commit(row);
        }
    }

    openMenu() {
        if (this.hasSelection) {
            return;
        }
        const hasQuery = this.query.trim().length >= 2;
        if (!hasQuery && this.recentRows.length === 0) {
            this.menuOpen = false;
            return;
        }
        this.menuOpen = true;
    }

    closeMenu() {
        this.menuOpen = false;
    }

    syncMenu() {
        const menu = this.template.querySelector('[data-menu]');
        if (!menu) {
            return;
        }
        if (this.menuOpen) {
            this.openPopover(menu);
            this.placeMenu(menu);
            this.revealActive(menu);
            return;
        }
        this.closePopover(menu);
    }

    openPopover(menu) {
        if (typeof menu.showPopover !== 'function') {
            return;
        }
        if (this._popoverFailed) {
            return;
        }
        if (!this._popoverReady) {
            menu.setAttribute('popover', 'manual');
            this._popoverReady = true;
        }
        if (!menu.matches(':popover-open')) {
            try {
                menu.showPopover();
            } catch (_error) {
                this._popoverFailed = true;
                this._popoverReady = false;
                menu.removeAttribute('popover');
            }
        }
    }

    closePopover(menu = this.template?.querySelector('[data-menu]')) {
        if (!menu || typeof menu.hidePopover !== 'function') {
            return;
        }
        if (menu.matches(':popover-open')) {
            menu.hidePopover();
        }
    }

    placeMenu(menu) {
        const anchor = this.template.querySelector('.control');
        if (!menu || !anchor) {
            return;
        }
        const rect = anchor.getBoundingClientRect();
        const viewport = window.visualViewport;
        const viewHeight = viewport?.height || window.innerHeight;
        const viewTop = viewport?.offsetTop || 0;
        const viewLeft = viewport?.offsetLeft || 0;
        const viewWidth = viewport?.width || window.innerWidth;
        const gap = 6;
        const margin = 8;
        const spaceBelow = viewTop + viewHeight - rect.bottom - gap - margin;
        const spaceAbove = rect.top - viewTop - gap - margin;
        const openUp = spaceBelow < 180 && spaceAbove > spaceBelow;
        menu.classList.toggle('is-up', openUp);
        const maxHeight = Math.max(96, Math.min(352, openUp ? spaceAbove : spaceBelow));
        const width = Math.min(Math.max(rect.width, 260), viewWidth - margin * 2);
        let left = rect.left;
        if (left + width > viewLeft + viewWidth - margin) {
            left = viewLeft + viewWidth - margin - width;
        }
        if (left < viewLeft + margin) {
            left = viewLeft + margin;
        }
        menu.style.width = `${width}px`;
        menu.style.maxHeight = `${maxHeight}px`;
        menu.style.left = `${left}px`;
        menu.style.right = 'auto';
        if (openUp) {
            const bottom = window.innerHeight - rect.top + gap;
            menu.style.top = 'auto';
            menu.style.bottom = `${bottom}px`;
        } else {
            menu.style.bottom = 'auto';
            menu.style.top = `${rect.bottom + gap}px`;
        }
    }

    revealActive(menu) {
        const active = menu.querySelector('.menu-row.is-active');
        if (!active) {
            return;
        }
        const top = active.offsetTop;
        const bottom = top + active.offsetHeight;
        if (top < menu.scrollTop) {
            menu.scrollTop = top;
        } else if (bottom > menu.scrollTop + menu.clientHeight) {
            menu.scrollTop = bottom - menu.clientHeight;
        }
    }

    debounceSearch() {
        window.clearTimeout(this._timer);
        const term = this.query.trim();
        if (term.length < 2) {
            this.isSearching = false;
            this.searchFailed = false;
            this.results = [];
            return;
        }
        this._timer = window.setTimeout(() => {
            this.runSearch(term);
        }, 200);
    }

    async runSearch(term) {
        const token = (this._searchToken += 1);
        this.isSearching = true;
        this.searchFailed = false;
        this.results = [];
        try {
            const rows = await searchAccounts({ term });
            if (token !== this._searchToken || this.query.trim() !== term) {
                return;
            }
            this.results = normalizeRows(rows);
            this.activeIndex = 0;
            this.openMenu();
        } catch (_error) {
            if (token !== this._searchToken) {
                return;
            }
            this.results = [];
            this.searchFailed = true;
            this.menuOpen = true;
        } finally {
            if (token === this._searchToken) {
                this.isSearching = false;
            }
        }
    }

    commit(row) {
        this.query = '';
        this.results = [];
        this.searchFailed = false;
        this.closeMenu();
        this.dispatchChange(row);
    }

    dispatchChange(row) {
        this.dispatchEvent(
            new CustomEvent('change', {
                detail: {
                    accountId: row.accountId || null,
                    accountName: row.accountName || null,
                    visitId: row.visitId || null,
                    recordTypeLabel: row.recordTypeLabel || null,
                    iconName: row.iconName || null
                }
            })
        );
    }
}

function themeFor(iconName) {
    const name = String(iconName || '');
    if (name.includes('household') || name.includes('store')) {
        return 'mark-pharmacy';
    }
    if (name.includes('person')) {
        return 'mark-hcp';
    }
    if (name.includes('contact')) {
        return 'mark-contact';
    }
    return 'mark-hco';
}

function foldLoose(value) {
    return String(value || '')
        .normalize('NFKC')
        .toLowerCase()
        .replace(/\s+/g, ' ')
        .trim();
}

function normalizeRows(rows) {
    const seen = new Set();
    const out = [];
    for (const row of rows || []) {
        const accountId = row.accountId || row.value;
        const accountName = row.accountName || row.label;
        if (!accountId || !accountName || seen.has(accountId)) {
            continue;
        }
        seen.add(accountId);
        const recordTypeLabel = row.recordTypeLabel || '';
        const reason = row.reason && row.reason !== 'Search' ? row.reason : '';
        out.push({
            accountId,
            accountName,
            visitId: row.visitId || null,
            recordTypeLabel,
            iconName: row.iconName || 'standard:account',
            meta: [recordTypeLabel, reason].filter(Boolean).join(' · ')
        });
    }
    return out;
}
