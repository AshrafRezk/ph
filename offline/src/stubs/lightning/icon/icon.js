import { LightningElement, api } from 'lwc';

const GLYPHS = {
    add: '＋',
    new: '＋',
    close: '✕',
    clear: '✕',
    refresh: '↻',
    sync: '↻',
    event: '📅',
    date_input: '📅',
    checkin: '📍',
    location: '📍',
    preview: '👁',
    search: '🔍',
    edit: '✎',
    delete: '🗑',
    settings: '⚙',
    filter: '☰',
    filterList: '☰',
    user: '👤',
    people: '👥',
    home: '⌂',
    world: '🌐',
    chevronleft: '◀',
    chevronright: '▶',
    left: '◀',
    right: '▶',
    down: '▾',
    up: '▴',
    more: '⋯',
    info: 'ℹ',
    warning: '!',
    error: '✕',
    success: '✓',
    check: '✓'
};

function glyphFor(iconName) {
    if (!iconName) return '';
    const key = String(iconName).split(':').pop() || '';
    const normalized = key.replace(/[^a-z0-9]/gi, '').toLowerCase();
    if (GLYPHS[key]) return GLYPHS[key];
    if (GLYPHS[normalized]) return GLYPHS[normalized];
    for (const [token, glyph] of Object.entries(GLYPHS)) {
        if (normalized.includes(token.toLowerCase())) return glyph;
    }
    return '•';
}

export default class Icon extends LightningElement {
    @api iconName = '';
    @api alternativeText = '';
    @api size = 'medium';
    @api variant = '';
    @api title = '';

    get glyph() {
        return glyphFor(this.iconName);
    }

    get computedClass() {
        return `slds-icon_container slds-icon-${this.size}`;
    }
}
