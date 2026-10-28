const MODE_KEY = 'careCoach.viewMode';
const SCOPE_KEY = 'careCoach.scope';
const MODE_EVENT = 'carecoachmodechange';
const SCOPE_EVENT = 'carecoachscopechange';

export const STATUS_META = {
    Ongoing: { color: '#2e844a', tint: '#ebf7ee', short: 'Ongoing', icon: 'utility:check' },
    Pending: { color: '#dd7a01', tint: '#fef1e0', short: 'Pending', icon: 'utility:clock' },
    'Dropped (Switched)': { color: '#7f56d9', tint: '#f2edfc', short: 'Switched', icon: 'utility:change_record_type' },
    'Dropped (Stopped)': { color: '#ba0517', tint: '#fdeceb', short: 'Stopped', icon: 'utility:ban' },
    'Unknown (Failed calls)': { color: '#706e6b', tint: '#f3f2f2', short: 'Unknown', icon: 'utility:question' }
};

export const CALL_STATUS_COLORS = {
    Reached: '#032d60',
    'Unreached (No Answer)': '#1b96ff',
    'Unreached (Switched Off)': '#0b827c',
    'Call back': '#90d0fe',
    New: '#e4c86a',
    Planned: '#8a6fd1'
};

export const PRODUCT_COLORS = ['#0f7c8c', '#503291', '#e2a31b', '#d5367e', '#2dbecd', '#6b8e23'];

export function statusStyle(status) {
    const meta = STATUS_META[status] || STATUS_META['Unknown (Failed calls)'];
    return `--status-color:${meta.color};--status-tint:${meta.tint};`;
}

export function riskClass(risk) {
    const r = (risk || '').toLowerCase();
    if (r.startsWith('high')) return 'cc-risk cc-risk_high';
    if (r.startsWith('medium')) return 'cc-risk cc-risk_medium';
    if (r.startsWith('low')) return 'cc-risk cc-risk_low';
    return 'cc-risk';
}

export function sentimentClass(sentiment) {
    switch (sentiment) {
        case 'Positive':
            return 'cc-pill cc-pill_positive';
        case 'Negative':
            return 'cc-pill cc-pill_negative';
        case 'Mixed':
            return 'cc-pill cc-pill_warning';
        default:
            return 'cc-pill';
    }
}

const dateFmt = new Intl.DateTimeFormat(undefined, { day: '2-digit', month: 'short', year: 'numeric' });
const dateTimeFmt = new Intl.DateTimeFormat(undefined, {
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit'
});
const timeFmt = new Intl.DateTimeFormat(undefined, { hour: '2-digit', minute: '2-digit' });

export function formatDate(value) {
    if (!value) return '';
    const d = typeof value === 'string' && value.length === 10 ? new Date(`${value}T00:00:00`) : new Date(value);
    return Number.isNaN(d.getTime()) ? '' : dateFmt.format(d);
}

export function formatDateTime(value) {
    if (!value) return '';
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? '' : dateTimeFmt.format(d);
}

export function formatTime(value) {
    if (!value) return '';
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? '' : timeFmt.format(d);
}

export function formatRelative(value) {
    if (!value) return 'Never';
    const d = new Date(value);
    const diffDays = Math.round((Date.now() - d.getTime()) / 86400000);
    if (diffDays === 0) return 'Today';
    if (diffDays === 1) return 'Yesterday';
    if (diffDays === -1) return 'Tomorrow';
    if (diffDays > 1 && diffDays < 30) return `${diffDays} days ago`;
    if (diffDays < -1 && diffDays > -30) return `In ${-diffDays} days`;
    return formatDate(value);
}

export function toIsoDate(d) {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
}

export function reduceError(error) {
    if (!error) return 'Unknown error';
    if (Array.isArray(error.body)) return error.body.map((e) => e.message).join(', ');
    if (error.body && error.body.message) return error.body.message;
    if (error.body && error.body.pageErrors && error.body.pageErrors.length) return error.body.pageErrors[0].message;
    return error.message || String(error);
}

/** PSP users can preview the pharma-company view; the server always enforces masking. */
export function getStoredMode() {
    try {
        return window.sessionStorage.getItem(MODE_KEY) === 'company' ? 'company' : 'psp';
    } catch (e) {
        return 'psp';
    }
}

export function storeMode(mode) {
    try {
        window.sessionStorage.setItem(MODE_KEY, mode);
    } catch (e) {
        // storage unavailable (e.g. private mode); the toggle still works for this page
    }
    window.dispatchEvent(new CustomEvent(MODE_EVENT, { detail: mode }));
}

export function onModeChange(handler) {
    const listener = (evt) => handler(evt.detail);
    window.addEventListener(MODE_EVENT, listener);
    return () => window.removeEventListener(MODE_EVENT, listener);
}

export function getStoredScope(fallback) {
    try {
        return window.sessionStorage.getItem(SCOPE_KEY) || fallback;
    } catch (e) {
        return fallback;
    }
}

export function storeScope(scope) {
    try {
        window.sessionStorage.setItem(SCOPE_KEY, scope);
    } catch (e) {
        // ignore
    }
    window.dispatchEvent(new CustomEvent(SCOPE_EVENT, { detail: scope }));
}

export function initialsAvatar(name) {
    if (!name) return '?';
    const clean = name.split('·')[0].replace(/\./g, ' ').trim();
    const parts = clean.split(/\s+/).filter(Boolean);
    return parts.slice(0, 2).map((p) => p.charAt(0).toUpperCase()).join('');
}