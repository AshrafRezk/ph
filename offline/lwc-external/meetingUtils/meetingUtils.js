const MAX_UPLOAD_BYTES = 3.5 * 1024 * 1024;

export const STAGES = [
    { value: 'all', label: 'All' },
    { value: 'draft', label: 'Drafts' },
    { value: 'waiting', label: 'In approval' },
    { value: 'ready', label: 'Ready to run' },
    { value: 'cost', label: 'Cost & payment' },
    { value: 'closed', label: 'Closed' }
];

const STATUS_LABELS = {
    PendingApproval: 'Pending approval',
    'Pending GPM Approval': 'Pending GPM',
    'Pending NLM Approval': 'Pending NLM',
    Concluded: 'Held'
};

const TONES = {
    Draft: 'neutral',
    PendingApproval: 'warn',
    'Pending GPM Approval': 'warn',
    'Pending NLM Approval': 'warn',
    Approved: 'ok',
    Concluded: 'info',
    Incomplete: 'warn',
    Closed: 'muted',
    Cancelled: 'muted',
    Rejected: 'bad',
    'Not Submitted': 'neutral',
    'In Approval': 'warn',
    'Fully Approved': 'ok',
    'Not Started': 'neutral',
    'Actual Cost Entered': 'warn',
    'In Accounting': 'info',
    'Returned to Business': 'bad',
    'Partial Paid': 'warn',
    Paid: 'ok',
    Waiting: 'neutral',
    Pending: 'warn',
    Skipped: 'muted',
    'Not Sent': 'neutral',
    Sent: 'info',
    Confirmed: 'ok',
    'Checked In': 'ok',
    Invited: 'neutral',
    Accepted: 'ok',
    Declined: 'bad',
    Attended: 'ok',
    'Did Not Attend': 'bad'
};

export function statusLabel(value) {
    return STATUS_LABELS[value] || value || '';
}

export function pillClass(value) {
    return `mx-pill mx-pill_${TONES[value] || 'neutral'}`;
}

export function money(value, currencyCode = 'EGP') {
    if (value === null || value === undefined || value === '') {
        return '—';
    }
    const number = Number(value);
    if (!Number.isFinite(number)) {
        return '—';
    }
    return `${number.toLocaleString(undefined, { minimumFractionDigits: 0, maximumFractionDigits: 2 })} ${currencyCode}`;
}

export function dateLabel(value) {
    if (!value) {
        return '';
    }
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
        return '';
    }
    return date.toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
}

export function timeLabel(value) {
    if (!value) {
        return '';
    }
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
        return '';
    }
    return date.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
}

export function dateTimeLabel(value) {
    if (!value) {
        return '';
    }
    return `${dateLabel(value)} · ${timeLabel(value)}`;
}

export function dayParts(value) {
    if (!value) {
        return { day: '—', month: '' };
    }
    const date = new Date(value);
    return {
        day: String(date.getDate()),
        month: date.toLocaleDateString(undefined, { month: 'short' }).toUpperCase()
    };
}

export function relativeLabel(value) {
    if (!value) {
        return '';
    }
    const diffMs = Date.now() - new Date(value).getTime();
    const hours = Math.round(diffMs / 3600000);
    if (hours < 1) {
        return 'just now';
    }
    if (hours < 24) {
        return `${hours}h ago`;
    }
    const days = Math.round(hours / 24);
    return `${days}d ago`;
}

export function toLocalInput(value) {
    if (!value) {
        return '';
    }
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
        return '';
    }
    const pad = (n) => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(
        date.getMinutes()
    )}`;
}

export function fromLocalInput(value) {
    if (!value) {
        return null;
    }
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

export function initials(name) {
    if (!name) {
        return '?';
    }
    const parts = String(name).trim().split(/\s+/);
    return ((parts[0] || '')[0] || '').concat((parts.length > 1 ? parts[parts.length - 1][0] : '') || '').toUpperCase();
}

export function errorMessage(error) {
    if (!error) {
        return 'Something went wrong.';
    }
    if (typeof error === 'string') {
        return error;
    }
    if (Array.isArray(error.body)) {
        return error.body.map((item) => item.message).join(', ');
    }
    if (error.body && error.body.message) {
        return error.body.message;
    }
    if (error.body && error.body.pageErrors && error.body.pageErrors.length) {
        return error.body.pageErrors[0].message;
    }
    return error.message || 'Something went wrong.';
}

export function isQueued(result) {
    return !!(result && result.queued === true);
}

export function readFileAsBase64(file) {
    return new Promise((resolve, reject) => {
        if (!file) {
            resolve(null);
            return;
        }
        if (file.size > MAX_UPLOAD_BYTES) {
            reject(new Error('The file is larger than 3.5 MB. Upload a smaller scan or PDF.'));
            return;
        }
        const reader = new FileReader();
        reader.onload = () => {
            const text = String(reader.result || '');
            resolve({ fileName: file.name, base64: text.slice(text.indexOf(',') + 1) });
        };
        reader.onerror = () => reject(new Error('Could not read the file.'));
        reader.readAsDataURL(file);
    });
}
