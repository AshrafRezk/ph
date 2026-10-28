/**
 * HCP class display must always be letter+number (A1–C3).
 * Bare A/B/C from Classification__c is suppressed until a matrix code exists.
 */
export function normalizeLetterNumberClass(raw) {
    if (raw == null || raw === '') {
        return null;
    }
    const key = String(raw).trim().toUpperCase();
    if (/^[ABC][123]$/.test(key)) {
        return key;
    }
    return null;
}

export function displayClass(...candidates) {
    for (const value of candidates) {
        const normalized = normalizeLetterNumberClass(value);
        if (normalized) {
            return normalized;
        }
    }
    return null;
}

export function normalizeAccountClassFields(account) {
    if (!account || typeof account !== 'object') {
        return account;
    }
    const classification = displayClass(
        account.matrixRating,
        account.matrix_rating,
        account.hcpClassification,
        account.hcp_classification,
        account.classification
    );
    return {
        ...account,
        classification: classification || null
    };
}

export function normalizeAccountsTabRow(row) {
    if (!row || typeof row !== 'object') {
        return row;
    }
    const classification = displayClass(row.matrixRating, row.classification);
    return {
        ...row,
        classification: classification || null,
        classificationDisplay: classification || '—'
    };
}

export function filterLetterNumberOptions(options) {
    const list = Array.isArray(options) ? options : [];
    const seen = new Set();
    const out = [];
    for (const option of list) {
        const value = normalizeLetterNumberClass(option?.value ?? option?.label ?? option);
        if (!value || seen.has(value)) {
            continue;
        }
        seen.add(value);
        out.push({
            ...(typeof option === 'object' && option ? option : {}),
            label: value,
            value
        });
    }
    out.sort((a, b) => String(a.value).localeCompare(String(b.value)));
    return out;
}
