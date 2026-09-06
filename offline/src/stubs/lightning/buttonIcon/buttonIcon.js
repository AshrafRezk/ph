import { LightningElement, api } from 'lwc';

const GLYPHS = {
    preview: '👁',
    search: '🔍',
    event: '📅',
    date_input: '📅',
    checkin: '📍',
    location: '📍',
    add: '+',
    new: '+',
    close: '✕',
    clear: '✕',
    edit: '✎',
    delete: '🗑',
    trash: '🗑',
    refresh: '↻',
    sync: '↻',
    settings: '⚙',
    filter: '☰',
    filterList: '☰',
    rows: '☰',
    list: '☰',
    tile: '▦',
    table: '▦',
    chart: '📊',
    dashboard: '📊',
    user: '👤',
    people: '👥',
    home: '⌂',
    world: '🌐',
    link: '🔗',
    download: '⬇',
    upload: '⬆',
    chevronleft: '◀',
    chevronright: '▶',
    left: '◀',
    right: '▶',
    down: '▾',
    up: '▴',
    chevrondown: '▾',
    chevronup: '▴',
    more: '⋯',
    threedots: '⋯',
    overflow: '⋯',
    info: 'ℹ',
    warning: '!',
    error: '✕',
    success: '✓',
    check: '✓',
    save: '💾',
    copy: '⧉',
    email: '✉',
    call: '☎',
    sms: '💬',
    chat: '💬',
    clock: '🕒',
    money: '💰',
    bid: '💰'
};

function glyphFor(iconName) {
    if (!iconName) return '•';
    const key = String(iconName).split(':').pop() || '';
    const normalized = key.replace(/[^a-z0-9]/gi, '').toLowerCase();
    if (GLYPHS[key]) return GLYPHS[key];
    if (GLYPHS[normalized]) return GLYPHS[normalized];
    for (const [token, glyph] of Object.entries(GLYPHS)) {
        if (normalized.includes(token.toLowerCase())) return glyph;
    }
    return '•';
}

export default class ButtonIcon extends LightningElement {
    @api iconName = '';
    @api alternativeText = '';
    @api title = '';
    @api variant = 'border';
    @api size = 'medium';
    @api disabled = false;

    get glyph() {
        return glyphFor(this.iconName);
    }

    get computedClass() {
        const parts = ['slds-button', 'slds-button_icon'];
        if (this.variant === 'border' || this.variant === 'border-filled') {
            parts.push('slds-button_icon-border');
        }
        if (this.variant === 'bare') {
            parts.push('slds-button_icon-bare');
        }
        if (this.size === 'small') {
            parts.push('slds-button_icon-small');
        }
        return parts.join(' ');
    }
}
