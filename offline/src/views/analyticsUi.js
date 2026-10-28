import { escapeHtml } from './viewUtils.js';

export const ICONS = {
    back: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M12.5 4.5 7 10l5.5 5.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    refresh: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M16 10a6 6 0 1 1-1.8-4.3M16 3.5v3.5h-3.5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    edit: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M13.5 3.5l3 3L7 16H4v-3z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/></svg>',
    download: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M10 3v9m0 0-3.5-3.5M10 12l3.5-3.5M4 15.5h12" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    plus: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M10 4v12M4 10h12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
    close: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M5 5l10 10M15 5 5 15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
    up: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M5 12.5 10 7.5l5 5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    down: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M5 7.5 10 12.5l5-5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    undo: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M7.5 5 4 8.5 7.5 12M4 8.5h7.5a4.5 4.5 0 0 1 0 9H9" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    redo: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M12.5 5 16 8.5 12.5 12M16 8.5H8.5a4.5 4.5 0 0 0 0 9H11" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    filter: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M3.5 4.5h13l-5 6v5l-3 1.5v-6.5z" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/></svg>',
    grip: '<svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="7.5" cy="5" r="1.4"/><circle cx="12.5" cy="5" r="1.4"/><circle cx="7.5" cy="10" r="1.4"/><circle cx="12.5" cy="10" r="1.4"/><circle cx="7.5" cy="15" r="1.4"/><circle cx="12.5" cy="15" r="1.4"/></svg>',
    chart: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M4 16V9m4 7V5m4 11v-5m4 5V7" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></svg>',
    report: '<svg viewBox="0 0 20 20" aria-hidden="true"><rect x="4" y="3" width="12" height="14" rx="2" fill="none" stroke="currentColor" stroke-width="1.7"/><path d="M7 13v-2m3 2V8m3 5v-3" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>',
    dashboard: '<svg viewBox="0 0 20 20" aria-hidden="true"><rect x="3" y="3" width="6" height="8" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.7"/><rect x="11" y="3" width="6" height="5" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.7"/><rect x="11" y="10" width="6" height="7" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.7"/><rect x="3" y="13" width="6" height="4" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.7"/></svg>',
    folder: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M3 6a1.5 1.5 0 0 1 1.5-1.5h3.2l1.6 1.8h6.2A1.5 1.5 0 0 1 17 7.8v6.7a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 3 14.5z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg>',
    search: '<svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="9" cy="9" r="5" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="m13 13 3.5 3.5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
    more: '<svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="5" cy="10" r="1.6"/><circle cx="10" cy="10" r="1.6"/><circle cx="15" cy="10" r="1.6"/></svg>',
    open: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M11 4h5v5M16 4l-7 7M14 12v3.5a1 1 0 0 1-1 1H4.5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1H8" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    resize: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M16 9v7H9M16 16 10 10" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>'
};

export function iconBtn(icon, label, attrs = '', cls = '') {
    return `<button type="button" class="an-icon-btn ${cls}" aria-label="${escapeHtml(label)}" title="${escapeHtml(label)}" ${attrs}>${ICONS[icon] || ''}</button>`;
}

let toastTimer = null;

export function toast(message, tone = 'success') {
    let el = document.querySelector('.an-toast');
    if (!el) {
        el = document.createElement('div');
        el.className = 'an-toast';
        el.setAttribute('role', 'status');
        document.body.appendChild(el);
    }
    el.dataset.tone = tone;
    el.textContent = message;
    el.classList.add('is-on');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove('is-on'), 3200);
}

/**
 * Minimal modal. `body` is HTML; `actions` are { id, label, primary?, danger? }.
 * Resolves with { action, form } where form is a FormData-like plain object.
 */
export function openModal({ title, body, actions = [], wide = false, onMount }) {
    return new Promise((resolve) => {
        const overlay = document.createElement('div');
        overlay.className = 'an-modal-overlay';
        overlay.innerHTML = `
            <div class="an-modal${wide ? ' an-modal--wide' : ''}" role="dialog" aria-modal="true" aria-label="${escapeHtml(title)}">
                <header class="an-modal-head"><h2>${escapeHtml(title)}</h2>${iconBtn('close', 'Close', 'data-modal-action="cancel"')}</header>
                <form class="an-modal-body" novalidate>${body}</form>
                <footer class="an-modal-foot">${actions
                    .map(
                        (action) =>
                            `<button type="button" class="an-btn${action.primary ? ' an-btn--primary' : ''}${action.danger ? ' an-btn--danger' : ''}" data-modal-action="${escapeHtml(action.id)}">${escapeHtml(action.label)}</button>`
                    )
                    .join('')}</footer>
            </div>`;
        const form = overlay.querySelector('form');
        const collect = () => {
            const out = {};
            new FormData(form).forEach((value, key) => {
                out[key] = value;
            });
            return out;
        };
        const close = (action) => {
            overlay.classList.remove('is-on');
            document.removeEventListener('keydown', onKey);
            setTimeout(() => overlay.remove(), 160);
            resolve({ action, form: collect(), root: overlay });
        };
        const onKey = (event) => {
            if (event.key === 'Escape') close('cancel');
        };
        overlay.addEventListener('click', (event) => {
            if (event.target === overlay) {
                close('cancel');
                return;
            }
            const btn = event.target.closest('[data-modal-action]');
            if (btn && !btn.disabled) close(btn.dataset.modalAction);
        });
        form.addEventListener('submit', (event) => {
            event.preventDefault();
            const primary = actions.find((a) => a.primary);
            if (primary) close(primary.id);
        });
        document.addEventListener('keydown', onKey);
        document.body.appendChild(overlay);
        requestAnimationFrame(() => overlay.classList.add('is-on'));
        if (onMount) onMount(overlay, close);
        const first = overlay.querySelector('input, select, textarea');
        if (first) setTimeout(() => first.focus(), 60);
    });
}

export function confirmModal(title, message, confirmLabel = 'Discard', danger = true) {
    return openModal({
        title,
        body: `<p class="an-modal-text">${escapeHtml(message)}</p>`,
        actions: [
            { id: 'cancel', label: 'Cancel' },
            { id: 'ok', label: confirmLabel, primary: !danger, danger }
        ]
    }).then((res) => res.action === 'ok');
}

export function downloadText(filename, text, mime = 'text/csv') {
    const blob = new Blob([`\ufeff${text}`], { type: `${mime};charset=utf-8` });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function safeFileName(name) {
    return String(name || 'report').replace(/[^\w\- ]+/g, '').trim().replace(/\s+/g, '_') || 'report';
}

export function formatAsOf(value) {
    if (!value) return '';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    return date.toLocaleString(undefined, {
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit'
    });
}
