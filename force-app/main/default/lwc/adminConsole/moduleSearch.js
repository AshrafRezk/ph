/**
 * Search helpers for the Admin Console module gallery.
 * Pure functions so they can be unit tested without mounting the console.
 *
 * Matching rules:
 *  - case-insensitive, Arabic letters normalised (alef forms, taa marbuta, alef maqsura, diacritics)
 *  - every word typed must match the start of some word in the card (title, description, group label, keywords)
 *  - simple English plurals are folded ("samples" finds "Sample Logistics")
 */

const ARABIC_DIACRITICS = /[ً-ْٰـ]/g;

export function normalize(value) {
    return (value || '')
        .toString()
        .toLowerCase()
        .replace(ARABIC_DIACRITICS, '')
        .replace(/[أإآ]/g, 'ا')
        .replace(/ة/g, 'ه')
        .replace(/ى/g, 'ي');
}

function stem(word) {
    if (word.length > 3 && /^[a-z]+$/.test(word)) {
        if (word.endsWith('ies')) {
            return word.slice(0, -3) + 'y';
        }
        if (/(ches|shes|sses|xes)$/.test(word)) {
            return word.slice(0, -2);
        }
        if (word.endsWith('s') && !word.endsWith('ss')) {
            return word.slice(0, -1);
        }
    }
    return word;
}

export function tokenize(value) {
    return normalize(value)
        .split(/[^a-z0-9%؀-ۿ]+/)
        .filter(Boolean)
        .map(stem);
}

export function buildSearchTokens(card, groupLabel) {
    return tokenize([card.title, card.description, groupLabel, card.titleAr, ...(card.keywords || [])].join(' '));
}

export function matchesQuery(searchTokens, query) {
    const wanted = tokenize(query);
    if (!wanted.length) {
        return true;
    }
    return wanted.every((w) => searchTokens.some((t) => t.startsWith(w)));
}
