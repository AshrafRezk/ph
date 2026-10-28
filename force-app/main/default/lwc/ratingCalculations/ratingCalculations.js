const CLASSIFICATION_MAP = {
    A1: 'A',
    A2: 'A',
    B1: 'A',
    A3: 'B',
    B2: 'B',
    C1: 'B',
    B3: 'C',
    C2: 'C',
    C3: 'C'
};

export function matrixRating(potential, penetration) {
    if (!potential || !penetration) {
        return '';
    }
    return `${potential}${penetration}`.toUpperCase();
}

export function matrixRatingDisplay(potential, penetration) {
    const matrix = matrixRating(potential, penetration);
    return matrix ? matrix.toLowerCase() : '';
}

export function classification(matrix) {
    if (!matrix) {
        return '';
    }
    return CLASSIFICATION_MAP[String(matrix).toUpperCase()] || '';
}

export function classificationDisplay(potential, penetration) {
    const matrix = matrixRating(potential, penetration);
    if (!matrix) {
        return '';
    }
    const bucket = classification(matrix);
    if (!bucket) {
        return '';
    }
    return `${bucket} · ${matrix.toLowerCase()}`;
}

export function productMatrixRating(adoption, loyalty) {
    if (!adoption || !loyalty) {
        return '';
    }
    return `${adoption}${loyalty}`.toUpperCase();
}

export function productMatrixRatingDisplay(adoption, loyalty) {
    const matrix = productMatrixRating(adoption, loyalty);
    return matrix ? matrix.toLowerCase() : '';
}

const DONUT_COLORS = {
    low: '#ea001e',
    mid: '#ffb75d',
    high: '#2e844a'
};

const DONUT_FILL_CAP = {
    low: 33,
    mid: 66,
    high: 100
};

const DONUT_RING_MAX = 10;

export function numberDonutVisual(value) {
    const numericValue = Number(value);
    if (Number.isNaN(numericValue) || numericValue <= 0) {
        return {
            percent: 8,
            color: DONUT_COLORS.low,
            valueColor: DONUT_COLORS.low
        };
    }

    let tier;
    if (numericValue <= 3) {
        tier = 'low';
    } else if (numericValue <= 7) {
        tier = 'mid';
    } else {
        tier = 'high';
    }

    const fillCap = DONUT_FILL_CAP[tier];
    const rawPercent = (numericValue / DONUT_RING_MAX) * 100;
    const percent = Math.min(fillCap, Math.max(12, rawPercent));

    return {
        percent,
        color: DONUT_COLORS[tier],
        valueColor: DONUT_COLORS[tier]
    };
}

export function applyProductCalculatedValues(values) {
    const next = { ...values };
    const adoption = next.Adoption__c ?? next.adoption__c;
    const loyalty = next.Loyalty__c ?? next.loyalty__c;
    const matrix = productMatrixRating(adoption, loyalty);
    if (matrix) {
        const matrixDisplay = matrix.toLowerCase();
        next.Product_Matrix_Rating__c = matrixDisplay;
        next.product_matrix_rating__c = matrixDisplay;
    }
    return next;
}

function isExplicitBoolean(value) {
    return value === true || value === false || value === 'true' || value === 'false';
}

function isTruthyFlag(value) {
    return value === true || value === 'true';
}

function hasMeaningfulText(value) {
    return value != null && String(value).trim().length > 0;
}

export function applyCalculatedValues(fields, values, accountVariant = 'HCP') {
    const next = { ...values };
    const potential = next.Potential__c ?? next.potential__c;
    const penetration = next.Penetration__c ?? next.penetration__c;
    const matrix = matrixRating(potential, penetration);
    if (matrix) {
        const matrixDisplay = matrix.toLowerCase();
        next.Matrix_Rating__c = matrixDisplay;
        next.matrix_rating__c = matrixDisplay;
    }
    const bucket = classification(matrix);
    if (bucket) {
        next.Classification__c = bucket;
        next.classification__c = bucket;
    }

    const kolReason = next.KOL_In_What__c ?? next.kol_in_what__c;
    const kolProfile = next.KOL_Profile__c ?? next.kol_profile__c;
    const usesHcpKol = isExplicitBoolean(next.Is_KOL__c) || hasMeaningfulText(kolReason);
    const usesHcoKol = isExplicitBoolean(next.Has_KOLs__c) || hasMeaningfulText(kolProfile);

    // Shared HCO/Pharmacy layouts use Is KOL. Only run the org "Has KOLs" model when
    // those fields are present and Is KOL is not being edited/displayed.
    if (usesHcoKol && !usesHcpKol) {
        const hasKols = isTruthyFlag(next.Has_KOLs__c);
        const hasKolsExplicitlyOff = next.Has_KOLs__c === false || next.Has_KOLs__c === 'false';

        if (hasKolsExplicitlyOff) {
            next.KOL_Profile__c = '';
            next.kol_profile__c = '';
        } else if (kolProfile) {
            next.Has_KOLs__c = true;
        } else if (!hasKols) {
            next.KOL_Profile__c = '';
            next.kol_profile__c = '';
        }

        next.Is_KOL__c = false;
        next.KOL_In_What__c = '';
    } else {
        const isKol = isTruthyFlag(next.Is_KOL__c);
        const isKolExplicitlyOff = next.Is_KOL__c === false || next.Is_KOL__c === 'false';

        if (isKolExplicitlyOff) {
            next.KOL_In_What__c = '';
            next.kol_in_what__c = '';
        } else if (kolReason) {
            next.Is_KOL__c = true;
        } else if (!isKol) {
            next.KOL_In_What__c = '';
            next.kol_in_what__c = '';
        }

        if (!usesHcoKol) {
            next.Has_KOLs__c = false;
            next.KOL_Profile__c = '';
        }
    }

    if (accountVariant === 'Pharmacy') {
        next.Is_Speaker__c = false;
    }

    return applyProductCalculatedValues(next);
}