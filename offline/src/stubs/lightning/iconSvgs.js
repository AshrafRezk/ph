/**
 * Tiny SLDS-like utility SVGs for offline lightning-icon / buttonIcon stubs.
 * Returns inline SVG markup (no emoji, no placeholder dots).
 */

const NS = 'http://www.w3.org/2000/svg';

function svg(paths, viewBox = '0 0 52 52') {
    return `<svg xmlns="${NS}" viewBox="${viewBox}" width="1em" height="1em" fill="currentColor" aria-hidden="true" focusable="false">${paths}</svg>`;
}

const ICONS = {
    add: svg('<path d="M26 8a2 2 0 0 1 2 2v14h14a2 2 0 1 1 0 4H28v14a2 2 0 1 1-4 0V28H10a2 2 0 1 1 0-4h14V10a2 2 0 0 1 2-2z"/>'),
    new: null, // alias add
    close: svg('<path d="M14.1 12.3a2 2 0 0 1 2.8 0L26 21.4l9.1-9.1a2 2 0 1 1 2.8 2.8L28.8 24.2l9.1 9.1a2 2 0 1 1-2.8 2.8L26 27l-9.1 9.1a2 2 0 1 1-2.8-2.8l9.1-9.1-9.1-9.1a2 2 0 0 1 0-2.8z"/>'),
    clear: null,
    refresh: svg('<path d="M42 26a16 16 0 1 1-4.7-11.3 2 2 0 1 1-2.8 2.8A12 12 0 1 0 38 26h-4.5a1.5 1.5 0 0 1-1.1-2.5l6-6.5a1.5 1.5 0 0 1 2.2 0l6 6.5A1.5 1.5 0 0 1 45.5 26H42z"/>'),
    sync: null,
    search: svg('<path d="M23 10a13 13 0 0 1 10.3 20.9l7.4 7.4a2 2 0 0 1-2.8 2.8l-7.4-7.4A13 13 0 1 1 23 10zm0 4a9 9 0 1 0 0 18 9 9 0 0 0 0-18z"/>'),
    download: svg('<path d="M26 8a2 2 0 0 1 2 2v18.2l5.6-5.6a2 2 0 1 1 2.8 2.8l-9 9a2 2 0 0 1-2.8 0l-9-9a2 2 0 1 1 2.8-2.8L24 28.2V10a2 2 0 0 1 2-2zM12 38a2 2 0 0 1 2-2h24a2 2 0 1 1 0 4H14a2 2 0 0 1-2-2z"/>'),
    upload: svg('<path d="M26 44a2 2 0 0 1-2-2V23.8l-5.6 5.6a2 2 0 1 1-2.8-2.8l9-9a2 2 0 0 1 2.8 0l9 9a2 2 0 1 1-2.8 2.8L28 23.8V42a2 2 0 0 1-2 2zM12 12a2 2 0 0 1 2-2h24a2 2 0 1 1 0 4H14a2 2 0 0 1-2-2z"/>'),
    filterlist: svg('<path d="M8 12a2 2 0 0 1 2-2h32a2 2 0 0 1 1.6 3.2L30 30.5V40a2 2 0 0 1-1.1 1.8l-6 3A2 2 0 0 1 20 43V30.5L8.4 13.2A2 2 0 0 1 8 12zm5.5 2L22 26.8V40.2l4-2V26.8L38.5 14H13.5z"/>'),
    filter: null,
    rows: null,
    list: svg('<path d="M12 14a2 2 0 0 1 2-2h24a2 2 0 1 1 0 4H14a2 2 0 0 1-2-2zm0 12a2 2 0 0 1 2-2h24a2 2 0 1 1 0 4H14a2 2 0 0 1-2-2zm0 12a2 2 0 0 1 2-2h24a2 2 0 1 1 0 4H14a2 2 0 0 1-2-2z"/>'),
    event: svg('<path d="M18 8a2 2 0 0 1 2 2v2h12V10a2 2 0 1 1 4 0v2h2a4 4 0 0 1 4 4v24a4 4 0 0 1-4 4H14a4 4 0 0 1-4-4V16a4 4 0 0 1 4-4h2V10a2 2 0 0 1 2-2zm20 16H14v16h24V24zM14 16v4h24v-4H14z"/>'),
    date_input: null,
    checkin: svg('<path d="M26 6c8.3 0 15 6.7 15 15 0 10.5-12.2 22.4-13.4 23.5a2 2 0 0 1-2.8 0C23.2 43.4 11 31.5 11 21c0-8.3 6.7-15 15-15zm0 4a11 11 0 0 0-11 11c0 6.8 7.2 15.4 11 19.2 3.8-3.8 11-12.4 11-19.2A11 11 0 0 0 26 10zm0 6a5 5 0 1 1 0 10 5 5 0 0 1 0-10z"/>'),
    location: null,
    chevronleft: svg('<path d="M30.7 12.3a2 2 0 0 1 0 2.8L21.8 24l8.9 8.9a2 2 0 1 1-2.8 2.8l-10.3-10.3a2 2 0 0 1 0-2.8L27.9 12.3a2 2 0 0 1 2.8 0z"/>'),
    chevronright: svg('<path d="M21.3 12.3a2 2 0 0 1 2.8 0l10.3 10.3a2 2 0 0 1 0 2.8L24.1 35.7a2 2 0 1 1-2.8-2.8l8.9-8.9-8.9-8.9a2 2 0 0 1 0-2.8z"/>'),
    left: null,
    right: null,
    chevrondown: svg('<path d="M12.3 21.3a2 2 0 0 1 2.8 0L26 32.2l10.9-10.9a2 2 0 1 1 2.8 2.8L27.4 36.4a2 2 0 0 1-2.8 0L12.3 24.1a2 2 0 0 1 0-2.8z"/>'),
    chevronup: svg('<path d="M12.3 30.7a2 2 0 0 1 0-2.8L24.6 15.6a2 2 0 0 1 2.8 0l13.4 13.4a2 2 0 1 1-2.8 2.8L26 19.8 15.1 30.7a2 2 0 0 1-2.8 0z"/>'),
    down: null,
    up: null,
    edit: svg('<path d="M35.6 8.4a4 4 0 0 1 5.7 5.7L19.4 36l-7.1 1.8a2 2 0 0 1-2.4-2.4L11.7 28.3 35.6 8.4zM34 13.3 14.9 32.4l-.7 2.7 2.7-.7L36.9 15.2l-2.9-1.9z"/>'),
    delete: svg('<path d="M20 10a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v2h8a2 2 0 1 1 0 4h-2.1l-1.6 24.1A4 4 0 0 1 32.3 44H19.7a4 4 0 0 1-4-3.9L14.1 16H12a2 2 0 1 1 0-4h8v-2zm2 2v2h8v-2h-8zm-5.9 4 1.5 22.1h16.8L35.9 16H16.1z"/>'),
    trash: null,
    settings: svg('<path d="M26 18a8 8 0 1 1 0 16 8 8 0 0 1 0-16zm0 4a4 4 0 1 0 0 8 4 4 0 0 0 0-8zm1.2-14h-2.4l-.5 4.1a12 12 0 0 0-2.9 1.2l-3.5-2.2-1.7 1.7 2.2 3.5a12 12 0 0 0-1.2 2.9L12 24.8v2.4l4.1.5c.3 1 .7 2 1.2 2.9l-2.2 3.5 1.7 1.7 3.5-2.2c.9.5 1.9.9 2.9 1.2l.5 4.1h2.4l.5-4.1a12 12 0 0 0 2.9-1.2l3.5 2.2 1.7-1.7-2.2-3.5c.5-.9.9-1.9 1.2-2.9l4.1-.5v-2.4l-4.1-.5a12 12 0 0 0-1.2-2.9l2.2-3.5-1.7-1.7-3.5 2.2a12 12 0 0 0-2.9-1.2L27.2 8z"/>'),
    preview: svg('<path d="M26 14c10.5 0 19.2 6.6 22.5 12A24.6 24.6 0 0 1 26 38C15.5 38 6.8 31.4 3.5 26A24.6 24.6 0 0 1 26 14zm0 4a8 8 0 1 0 0 16 8 8 0 0 0 0-16zm0 4a4 4 0 1 1 0 8 4 4 0 0 1 0-8z"/>'),
    more: svg('<circle cx="12" cy="26" r="3.5"/><circle cx="26" cy="26" r="3.5"/><circle cx="40" cy="26" r="3.5"/>'),
    threedots: null,
    overflow: null,
    info: svg('<path d="M26 8a18 18 0 1 1 0 36 18 18 0 0 1 0-36zm0 4a14 14 0 1 0 0 28 14 14 0 0 0 0-28zm-2 8h4v2h-1v10h-2V22h-1v-2zm2 14a1.8 1.8 0 1 1 0-3.6 1.8 1.8 0 0 1 0 3.6z"/>'),
    warning: svg('<path d="M26 8c1.2 0 2.3.7 2.8 1.8l16.5 30.5A3 3 0 0 1 42.5 44H9.5a3 3 0 0 1-2.8-4.2L23.2 9.8A3 3 0 0 1 26 8zm0 10a2 2 0 0 0-2 2v10a2 2 0 1 0 4 0V20a2 2 0 0 0-2-2zm0 18a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z"/>'),
    error: null,
    success: svg('<path d="M26 8a18 18 0 1 1 0 36 18 18 0 0 1 0-36zm8.7 11.3a2 2 0 0 0-2.8 0L23 28.2l-3.9-3.9a2 2 0 1 0-2.8 2.8l5.3 5.3a2 2 0 0 0 2.8 0l10.3-10.3a2 2 0 0 0 0-2.8z"/>'),
    check: null,
    save: svg('<path d="M14 8h20l8 8v24a4 4 0 0 1-4 4H14a4 4 0 0 1-4-4V12a4 4 0 0 1 4-4zm2 4v12h16V12H16zm18 20H14v8h20v-8z"/>'),
    copy: svg('<path d="M18 10h18a4 4 0 0 1 4 4v18h-4V14H18V10zm-6 8h18a4 4 0 0 1 4 4v18a4 4 0 0 1-4 4H12a4 4 0 0 1-4-4V22a4 4 0 0 1 4-4zm2 4v16h14V22H14z"/>'),
    email: svg('<path d="M10 14h32a4 4 0 0 1 4 4v16a4 4 0 0 1-4 4H10a4 4 0 0 1-4-4V18a4 4 0 0 1 4-4zm16 12.2L10.8 18H41.2L26 26.2zm0 4.6 16-8.4V34H10V22.4l16 8.4z"/>'),
    call: svg('<path d="M18.5 10.2a3 3 0 0 1 3.3 1.1l3.2 4.5a3 3 0 0 1-.5 4l-2.2 1.8a1 1 0 0 0-.2 1.2c1.4 2.8 3.6 5 6.4 6.4a1 1 0 0 0 1.2-.2l1.8-2.2a3 3 0 0 1 4-.5l4.5 3.2a3 3 0 0 1 1.1 3.3l-1.2 4.2A4 4 0 0 1 36 40C22.2 40 12 29.8 12 16a4 4 0 0 1 2.5-3.7l4-1.1z"/>'),
    sms: svg('<path d="M10 12h32a4 4 0 0 1 4 4v16a4 4 0 0 1-4 4H22l-8 8v-8h-4a4 4 0 0 1-4-4V16a4 4 0 0 1 4-4z"/>'),
    chat: null,
    clock: svg('<path d="M26 8a18 18 0 1 1 0 36 18 18 0 0 1 0-36zm2 9a2 2 0 0 0-4 0v9c0 .5.2 1 .6 1.4l6 6a2 2 0 1 0 2.8-2.8L28 25.2V17z"/>'),
    money: svg('<path d="M26 8c10 0 18 8 18 18s-8 18-18 18S8 36 8 26 16 8 26 8zm0 6c-1.7 0-3 .9-3 2h-4c0-3.5 3.1-6 7-6s7 2.5 7 6c0 2.4-1.5 3.9-4.2 5.1L26 22.5c-1.8.8-2.8 1.4-2.8 2.5 0 1.1 1.3 2 3 2s3-.9 3-2h4c0 3.5-3.1 6-7 6s-7-2.5-7-6c0-2.6 1.7-4.2 4.5-5.4L26 18.3c1.6-.7 2.5-1.3 2.5-2.3 0-1.1-1.3-2-2.5-2z"/>'),
    bid: null,
    home: svg('<path d="M26 8.5 44 24v18a2 2 0 0 1-2 2H32V32H20v12H10a2 2 0 0 1-2-2V24L26 8.5z"/>'),
    world: svg('<path d="M26 8a18 18 0 1 1 0 36 18 18 0 0 1 0-36zm0 4c-2.2 0-4.3 3.5-5.2 8.5h10.4C30.3 15.5 28.2 12 26 12zm-9.4 2.6A14 14 0 0 0 12.1 24h7.1c.3-4.2 1.3-7.9 2.8-10.4l-5.4 1zm18.8 0 5.4-1A14 14 0 0 1 39.9 24h-7.1c-.3-4.2-1.3-7.9-2.8-10.4zM12.1 28a14 14 0 0 0 4.5 9.4l5.4-1c-1.5-2.5-2.5-6.2-2.8-10.4h-7.1zm15.8 0c.3 4.2 1.3 7.9 2.8 10.4l5.4 1A14 14 0 0 0 39.9 28h-7.1zM20.8 39.5C21.7 44.5 23.8 48 26 48s4.3-3.5 5.2-8.5H20.8z"/>'),
    link: svg('<path d="M18 22a8 8 0 0 1 8-8h6a2 2 0 1 1 0 4h-6a4 4 0 0 0 0 8h6a2 2 0 1 1 0 4h-6a8 8 0 0 1-8-8zm8-2a2 2 0 1 1 0 4h8a2 2 0 1 1 0-4h-8zm8 6a8 8 0 0 1-8 8h-6a2 2 0 1 1 0-4h6a4 4 0 1 0 0-8h-6a2 2 0 1 1 0-4h6a8 8 0 0 1 8 8z"/>'),
    user: svg('<path d="M26 8a10 10 0 1 1 0 20 10 10 0 0 1 0-20zm0 24c9.4 0 17 5.4 17 12v2H9v-2c0-6.6 7.6-12 17-12z"/>'),
    people: svg('<path d="M18 10a8 8 0 1 1 0 16 8 8 0 0 1 0-16zm16 2a7 7 0 1 1 0 14 7 7 0 0 1 0-14zM18 30c8.3 0 15 4.5 15 10v2H3v-2c0-5.5 6.7-10 15-10zm18 2c6.6 0 12 3.6 12 8v2H36v-2c0-3.1-1.7-5.8-4.4-7.5 1.4-.3 2.9-.5 4.4-.5z"/>'),
    table: svg('<path d="M10 12h32a2 2 0 0 1 2 2v24a2 2 0 0 1-2 2H10a2 2 0 0 1-2-2V14a2 2 0 0 1 2-2zm2 8v6h12v-6H12zm16 0v6h12v-6H28zM12 30v6h12v-6H12zm16 0v6h12v-6H28z"/>'),
    tile: null,
    chart: svg('<path d="M12 12h4v28h-4V12zm10 10h4v18h-4V22zm10-6h4v24h-4V16zm10 12h4v12h-4V28z"/>'),
    dashboard: null,
    map: svg('<path d="M8 12.5 20 8l12 6 12-4.5V39.5L32 44l-12-6-12 4.5V12.5zm4 3.2v22.6l8-3V12.7l-8 3zm12 20.4 8 4V18.7l-8-4v21.4zm12-17.2v22.8l8-3V15.9l-8 3z"/>')
};

// Resolve aliases
ICONS.new = ICONS.add;
ICONS.clear = ICONS.close;
ICONS.sync = ICONS.refresh;
ICONS.filter = ICONS.filterlist;
ICONS.rows = ICONS.list;
ICONS.date_input = ICONS.event;
ICONS.location = ICONS.checkin;
ICONS.left = ICONS.chevronleft;
ICONS.right = ICONS.chevronright;
ICONS.down = ICONS.chevrondown;
ICONS.up = ICONS.chevronup;
ICONS.trash = ICONS.delete;
ICONS.threedots = ICONS.more;
ICONS.overflow = ICONS.more;
ICONS.error = ICONS.close;
ICONS.check = ICONS.success;
ICONS.chat = ICONS.sms;
ICONS.bid = ICONS.money;
ICONS.tile = ICONS.table;
ICONS.dashboard = ICONS.chart;

const FALLBACK = svg(
    '<rect x="18" y="18" width="16" height="16" rx="3" fill="none" stroke="currentColor" stroke-width="3"/>'
);

export function normalizeIconKey(iconName) {
    if (!iconName) return '';
    const key = String(iconName).split(':').pop() || '';
    return key.replace(/[^a-z0-9]/gi, '').toLowerCase();
}

export function svgForIcon(iconName) {
    const normalized = normalizeIconKey(iconName);
    if (!normalized) return FALLBACK;
    if (ICONS[normalized]) return ICONS[normalized];
    for (const [token, markup] of Object.entries(ICONS)) {
        if (normalized.includes(token)) return markup;
    }
    return FALLBACK;
}
