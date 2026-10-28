// Offline copy of the UNICEF arabic-name-romanizer index.
// The file is part of the app shell, so spelling lookup does not call Yamli or Google.

let indexPromise;

function foldToken(raw) {
    if (!raw) return '';
    let text = String(raw).normalize('NFKC').toLowerCase();
    text = text.replace(/[\u0640\u064B-\u065F\u0670\u06D6-\u06ED]/g, '');
    text = text
        .replace(/[\u0622\u0623\u0625\u0671]/g, '\u0627')
        .replace(/\u0629/g, '\u0647')
        .replace(/\u0649/g, '\u064A')
        .replace(/[\u0626]/g, '\u064A')
        .replace(/[\u0624]/g, '\u0648');
    return text.replace(/\s+/g, ' ').trim();
}

export function prepareNameRomanizer() {
    if (!indexPromise) {
        indexPromise = fetch('/name-romanizer.json')
            .then((response) => (response.ok ? response.json() : {}))
            .catch(() => ({}));
    }
    return indexPromise;
}

function phoneticAliases(folded) {
    if (!folded || /[\u0600-\u06FF]/.test(folded)) return [];
    const decoded = folded
        .replace(/3'|'+3/g, 'gh')
        .replace(/7'/g, 'kh')
        .replace(/6'/g, 'z')
        .replace(/9'/g, 'd')
        .replace(/5/g, 'kh')
        .replace(/7/g, 'h')
        .replace(/6/g, 't')
        .replace(/8/g, 'q')
        .replace(/9/g, 's')
        .replace(/[23]/g, '');
    const collapsed = decoded.replace(/([a-z])\1+/g, '$1');
    const out = [];
    if (decoded !== folded) out.push(decoded);
    if (collapsed !== folded) out.push(collapsed);
    if (collapsed !== decoded && collapsed.length >= 4 && 'aeiou'.includes(collapsed[0])) {
        out.push(collapsed.slice(1));
    }
    return out;
}

export async function nameVariants(token) {
    const index = await prepareNameRomanizer();
    const folded = foldToken(token);
    const compact = folded.replace(/ /g, '');
    const direct = index[folded] || index[compact];
    if (direct) return direct;
    for (const alias of phoneticAliases(folded)) {
        const hit = index[alias] || index[alias.replace(/ /g, '')];
        if (hit) return hit;
    }
    return [];
}
