let toastContainerEl = null;
let listenerBound = false;
let lastToastKey = '';
let lastToastAt = 0;

const CLOSE_ICON =
    '<svg class="toast-close-icon" viewBox="0 0 24 24" width="16" height="16" aria-hidden="true" focusable="false"><path fill="currentColor" d="M6.4 5.2 5.2 6.4 10.8 12l-5.6 5.6 1.2 1.2L12 13.2l5.6 5.6 1.2-1.2L13.2 12l5.6-5.6-1.2-1.2L12 10.8 6.4 5.2z"/></svg>';

function iconForVariant(variant) {
    if (variant === 'success') {
        return '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false"><path fill="currentColor" d="M9.3 16.3 5.2 12.2l1.4-1.4 2.7 2.7 8.1-8.1 1.4 1.4z"/></svg>';
    }
    if (variant === 'error') {
        return '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false"><path fill="currentColor" d="M12 3.5 3.5 20.5h17L12 3.5zm0 5.2 1.1 6.1h-2.2L12 8.7zm0 8.3c-.6 0-1.1-.5-1.1-1.1S11.4 14.8 12 14.8s1.1.5 1.1 1.1-.5 1.1-1.1 1.1z"/></svg>';
    }
    if (variant === 'warning') {
        return '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false"><path fill="currentColor" d="M12 3.5 3.5 20.5h17L12 3.5zm1 13.2h-2v-2h2v2zm0-3.5h-2V9.2h2v3.99z"/></svg>';
    }
    return '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false"><path fill="currentColor" d="M12 3.2A8.8 8.8 0 1 0 20.8 12 8.81 8.81 0 0 0 12 3.2zm.9 12.7h-1.8v-1.8h1.8zm0-3.4h-1.8V8.1h1.8z"/></svg>';
}

function ensureToastContainer() {
    if (toastContainerEl && document.body.contains(toastContainerEl)) {
        return toastContainerEl;
    }
    toastContainerEl = document.createElement('div');
    toastContainerEl.id = 'toast-container';
    toastContainerEl.className = 'toast-container';
    document.body.appendChild(toastContainerEl);
    return toastContainerEl;
}

function escapeHtml(str) {
    if (!str) return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

export function showToast({ title = '', message = '', variant = 'info', mode = 'dismissible', duration }) {
    if (typeof document === 'undefined') return;
    // Never overlay the Welcome / login card.
    if (
        document.body?.classList?.contains('screen-login') ||
        document.body?.dataset?.screen === 'login'
    ) {
        return;
    }

    // Collapse identical toasts fired within a short window (e.g. duplicate
    // drop handlers, dual listeners, or parallel component errors).
    const key = `${variant}|${title}|${message}`;
    const now = Date.now();
    if (key === lastToastKey && now - lastToastAt < 2000) {
        return;
    }
    lastToastKey = key;
    lastToastAt = now;

    const container = ensureToastContainer();

    const toastItem = document.createElement('div');
    const variantClass = `toast-${variant || 'info'}`;
    toastItem.className = `toast-item ${variantClass}`;

    toastItem.innerHTML = `
        <span class="toast-icon" aria-hidden="true">${iconForVariant(variant)}</span>
        <div class="toast-content">
            ${title ? `<div class="toast-title">${escapeHtml(title)}</div>` : ''}
            ${message ? `<div class="toast-message">${escapeHtml(message)}</div>` : ''}
        </div>
        <button type="button" class="toast-close" title="Close" aria-label="Close">${CLOSE_ICON}</button>
    `;

    const closeBtn = toastItem.querySelector('.toast-close');
    const dismiss = () => {
        if (toastItem.classList.contains('toast-hiding')) return;
        toastItem.classList.add('toast-hiding');
        setTimeout(() => {
            if (toastItem.parentNode) {
                toastItem.parentNode.removeChild(toastItem);
            }
        }, 250);
    };

    if (closeBtn) {
        closeBtn.addEventListener('click', dismiss);
    }
    container.appendChild(toastItem);

    if (mode !== 'sticky') {
        const timeoutMs = duration || (variant === 'error' ? 7000 : 4000);
        setTimeout(dismiss, timeoutMs);
    }
}

export function setupToastListener() {
    if (typeof window === 'undefined' || listenerBound) return;
    listenerBound = true;

    const handleToastEvent = (event) => {
        const detail = event.detail || {};
        if (detail.title || detail.message) {
            showToast(detail);
        }
    };

    // One listener only. composed events reach window; listening on both
    // window + document was showing every toast 2–3 times.
    window.addEventListener('lightning__showtoast', handleToastEvent);
}
