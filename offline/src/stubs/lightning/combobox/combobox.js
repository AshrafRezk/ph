import { LightningElement, api } from 'lwc';

const MENU_CLASS = 'osr-combobox-menu';

export default class Combobox extends LightningElement {
    @api label = '';
    @api value = '';
    @api placeholder = '';
    @api options = [];
    @api disabled = false;
    @api required = false;
    @api name = '';
    @api variant = 'standard';

    open = false;
    _menuEl;
    _onDocPointer;
    _onReposition;

    get showLabel() {
        return this.variant !== 'label-hidden' && !!this.label;
    }

    get ariaExpanded() {
        return this.open ? 'true' : 'false';
    }

    get displayValue() {
        const match = this.currentOption;
        if (match) {
            return match.label == null || match.label === '' ? this.currentValue : String(match.label);
        }
        return this.placeholder || 'Select…';
    }

    get currentValue() {
        return this.value == null ? '' : String(this.value);
    }

    get currentOption() {
        return (this.options || []).find((row) => String(row?.value) === this.currentValue);
    }

    get selectedImage() {
        return this.currentOption?.imageUrl || '';
    }

    get selectedMark() {
        if (this.selectedImage || !this.currentOption?.iconName) {
            return '';
        }
        return `slds-combobox__mark ${markClass(this.currentOption.iconName)}`;
    }

    handleKeydown(event) {
        if (event.key === 'Escape' && this.open) {
            event.preventDefault();
            event.stopPropagation();
            this.closeMenu();
        }
    }

    connectedCallback() {
        this._onDocPointer = (event) => {
            if (!this.open) {
                return;
            }
            const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
            const host = this.template && this.template.host;
            if (path.includes(this) || path.includes(host) || path.includes(this._menuEl)) {
                return;
            }
            this.closeMenu();
        };
        this._onKeydown = (event) => {
            if (event.key === 'Escape' && this.open) {
                this.closeMenu();
            }
        };
        this._onReposition = () => {
            if (this.open) {
                this.positionMenu();
            }
        };
        document.addEventListener('mousedown', this._onDocPointer, true);
        document.addEventListener('keydown', this._onKeydown);
        window.addEventListener('resize', this._onReposition);
        window.addEventListener('scroll', this._onReposition, true);
    }

    disconnectedCallback() {
        document.removeEventListener('mousedown', this._onDocPointer, true);
        document.removeEventListener('keydown', this._onKeydown);
        window.removeEventListener('resize', this._onReposition);
        window.removeEventListener('scroll', this._onReposition, true);
        this.removeMenu();
    }

    handleToggle(event) {
        event.preventDefault();
        event.stopPropagation();
        if (this.disabled) {
            return;
        }
        if (this.open) {
            this.closeMenu();
            return;
        }
        this.openMenu();
    }

    openMenu() {
        this.open = true;
        this.renderMenu();
        requestAnimationFrame(() => this.positionMenu());
    }

    closeMenu() {
        this.open = false;
        this.removeMenu();
    }

    renderMenu() {
        this.removeMenu();
        const menu = document.createElement('div');
        menu.className = MENU_CLASS;
        menu.setAttribute('role', 'listbox');
        const current = this.currentValue;
        const options = Array.isArray(this.options) ? this.options : [];
        const seen = new Set();
        options.forEach((row) => {
            const value = row?.value == null ? '' : String(row.value);
            if (seen.has(value)) {
                return;
            }
            seen.add(value);
            const btn = document.createElement('button');
            btn.type = 'button';
            btn.className = 'osr-combobox-option' + (value === current ? ' is-selected' : '');
            btn.setAttribute('role', 'option');
            btn.dataset.value = value;
            if (row?.imageUrl) {
                const img = document.createElement('img');
                img.className = 'osr-combobox-thumb';
                img.alt = '';
                img.src = row.imageUrl;
                btn.appendChild(img);
            } else if (row?.iconName) {
                const mark = document.createElement('span');
                mark.className = `osr-combobox-mark ${markClass(row.iconName)}`;
                mark.setAttribute('aria-hidden', 'true');
                btn.appendChild(mark);
            }
            const copy = document.createElement('span');
            copy.className = 'osr-combobox-copy';
            const name = document.createElement('span');
            name.className = 'osr-combobox-name';
            name.textContent = row?.label == null || row.label === '' ? value : String(row.label);
            copy.appendChild(name);
            if (row?.hint || row?.subtitle) {
                const hint = document.createElement('span');
                hint.className = 'osr-combobox-hint';
                hint.textContent = row.hint || row.subtitle;
                copy.appendChild(hint);
            }
            btn.appendChild(copy);
            btn.addEventListener('mousedown', (event) => event.preventDefault());
            btn.addEventListener('click', (event) => {
                event.preventDefault();
                event.stopPropagation();
                this.selectValue(value);
            });
            menu.appendChild(btn);
        });
        if (!menu.childElementCount) {
            const empty = document.createElement('div');
            empty.className = 'osr-combobox-empty';
            empty.textContent = 'No options';
            menu.appendChild(empty);
        }
        document.body.appendChild(menu);
        this._menuEl = menu;
    }

    positionMenu() {
        const menu = this._menuEl;
        const trigger = this.template.querySelector('.slds-combobox__input');
        if (!menu || !trigger) {
            return;
        }
        const rect = trigger.getBoundingClientRect();
        const vw = window.innerWidth;
        const vh = window.innerHeight;
        const width = Math.min(Math.max(rect.width, 11 * 16), vw - 16);
        let left = rect.left;
        if (left + width > vw - 8) {
            left = Math.max(8, vw - width - 8);
        }
        if (left < 8) {
            left = 8;
        }
        const spaceBelow = vh - rect.bottom - 12;
        const spaceAbove = rect.top - 12;
        const openUp = spaceBelow < 140 && spaceAbove > spaceBelow;
        const maxHeight = Math.min(280, openUp ? spaceAbove : spaceBelow);
        const top = openUp ? Math.max(8, rect.top - maxHeight - 4) : rect.bottom + 4;
        menu.style.position = 'fixed';
        menu.style.zIndex = '16000';
        menu.style.left = `${Math.round(left)}px`;
        menu.style.top = `${Math.round(top)}px`;
        menu.style.width = `${Math.round(width)}px`;
        menu.style.maxHeight = `${Math.max(120, Math.round(maxHeight))}px`;
    }

    selectValue(next) {
        this.value = next;
        this.closeMenu();
        this.dispatchEvent(
            new CustomEvent('change', {
                detail: { value: next }
            })
        );
    }

    removeMenu() {
        if (this._menuEl && this._menuEl.parentNode) {
            this._menuEl.parentNode.removeChild(this._menuEl);
        }
        this._menuEl = null;
    }
}

function markClass(iconName) {
    const name = String(iconName || '');
    if (name.includes('medication') || name.includes('sample')) {
        return 'mark-sample';
    }
    if (name.includes('article') || name.includes('detail')) {
        return 'mark-detail';
    }
    if (name.includes('reward') || name.includes('reminder')) {
        return 'mark-reminder';
    }
    return 'mark-product';
}
