export function escapeHtml(str) {
    return String(str ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

export function initials(name) {
    const parts = String(name || '?')
        .trim()
        .split(/\s+/)
        .filter(Boolean);
    if (!parts.length) return '?';
    const first = parts[0][0] || '?';
    const last = parts.length > 1 ? parts[parts.length - 1][0] : '';
    return `${first}${last}`.toUpperCase();
}

export function formatRelative(value) {
    if (!value) return '';
    const date = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    const sec = Math.round((Date.now() - date.getTime()) / 1000);
    if (sec < 45) return 'just now';
    if (sec < 3600) return `${Math.max(1, Math.floor(sec / 60))}m ago`;
    if (sec < 86400) return `${Math.floor(sec / 3600)}h ago`;
    if (sec < 604800) return `${Math.floor(sec / 86400)}d ago`;
    return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
}

export function formatSynced(savedAt) {
    if (!savedAt) return '';
    return `Last synced ${formatRelative(savedAt)}`;
}

export function isNetworkError(error) {
    const message = String((error && error.message) || error || '').toLowerCase();
    return (
        message.includes('network') ||
        message.includes('failed to fetch') ||
        message.includes('offline') ||
        message.includes('abort') ||
        message.includes('cors')
    );
}

export function errorMessage(error) {
    return String((error && error.message) || error || 'Something went wrong.');
}
