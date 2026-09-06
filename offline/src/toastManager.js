let toastContainerEl = null;
let listenerBound = false;
let lastToastKey = '';
let lastToastAt = 0;

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

    let iconSymbol = 'i';
    if (variant === 'success') iconSymbol = '✓';
    else if (variant === 'error') iconSymbol = '✕';
    else if (variant === 'warning') iconSymbol = '!';

    toastItem.innerHTML = `
        <span class="toast-icon" aria-hidden="true">${iconSymbol}</span>
        <div class="toast-content">
            ${title ? `<div class="toast-title">${escapeHtml(title)}</div>` : ''}
            ${message ? `<div class="toast-message">${escapeHtml(message)}</div>` : ''}
        </div>
        <button type="button" class="toast-close" title="Close notification" aria-label="Close">×</button>
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
