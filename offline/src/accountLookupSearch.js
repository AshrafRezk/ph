// Local cognitive account lookup for the offline field app.
// Attested spellings come from the bundled romanizer index.
// Unknown tokens fall through to grapheme transliteration.
// This module never calls Yamli, Almaany, or Google.

const LATIN_TO_ARABIC = {
    kh: '\u062E',
    sh: '\u0634',
    ch: '\u0634',
    gh: '\u063A',
    th: '\u062B',
    dh: '\u0630',
    ph: '\u0641',
    b: '\u0628',
    t: '\u062A',
    j: '\u062C',
    g: '\u062C',
    h: '\u0647',
    d: '\u062F',
    r: '\u0631',
    z: '\u0632',
    s: '\u0633',
    f: '\u0641',
    q: '\u0642',
    k: '\u0643',
    l: '\u0644',
    m: '\u0645',
    n: '\u0646',
    w: '\u0648',
    y: '\u064A',
    x: '\u0643\u0633'
};

const ARABIC_TO_LATIN = {
    '\u0627': 'a',
    '\u0628': 'b',
    '\u062A': 't',
    '\u062B': 'th',
    '\u062C': 'g',
    '\u062D': 'h',
    '\u062E': 'kh',
    '\u062F': 'd',
    '\u0630': 'dh',
    '\u0631': 'r',
    '\u0632': 'z',
    '\u0633': 's',
    '\u0634': 'sh',
    '\u0635': 's',
    '\u0636': 'd',
    '\u0637': 't',
    '\u0638': 'z',
    '\u0639': '',
    '\u063A': 'gh',
    '\u0641': 'f',
    '\u0642': 'q',
    '\u0643': 'k',
    '\u0644': 'l',
    '\u0645': 'm',
    '\u0646': 'n',
    '\u0647': 'h',
    '\u0648': 'w',
    '\u064A': 'y',
    '\u0649': 'y'
};

export function foldToken(raw) {
    if (!raw) return '';
    let text = String(raw).normalize('NFKC').toLowerCase();
    text = text.replace(/[\u0640\u064B-\u065F\u0670\u06D6-\u06ED]/g, '');
    text = text
        .replace(/[\u0622\u0623\u0625\u0671]/g, '\u0627')
        .replace(/\u0629/g, '\u0647')
        .replace(/\u0649/g, '\u064A')
        .replace(/\u0626/g, '\u064A')
        .replace(/\u0624/g, '\u0648');
    return text.replace(/\s+/g, ' ').trim();
}

export function iconForRecordType(developerName) {
    switch (developerName) {
        case 'PersonAccount':
        case 'SDO_PersonAccounts':
        case 'Medical_Professional_HCP':
            return 'standard:person_account';
        case 'Pharmacy':
            return 'standard:household';
        case 'Business_Contact':
            return 'standard:contact';
        default:
            return 'standard:account';
    }
}

function compact(value) {
    return foldToken(value).replace(/ /g, '');
}

function containsArabic(value) {
    return /[\u0600-\u06FF]/.test(String(value || ''));
}

function phoneticAliases(folded) {
    if (!folded || containsArabic(folded)) return [];
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

function familyFor(index, token) {
    const folded = foldToken(token);
    const key = compact(token);
    const direct = index[folded] || index[key];
    if (direct) return direct;
    for (const alias of phoneticAliases(folded)) {
        const hit = index[alias] || index[alias.replace(/ /g, '')];
        if (hit) return hit;
    }
    return [];
}

function tokenize(term) {
    return foldToken(term).split(' ').filter(Boolean);
}

function compoundStem(tokens) {
    if (!tokens || tokens.length < 2) return '';
    const first = tokens[0].replace(/ /g, '');
    const abd =
        first === 'abd' ||
        first === 'abdel' ||
        first === 'abdul' ||
        first === 'abdur' ||
        first === '\u0639\u0628\u062F' ||
        first.startsWith('abdel') ||
        first.startsWith('abdul') ||
        first.startsWith('\u0639\u0628\u062F');
    const el = first === 'el' || first === 'al' || first === '\u0627\u0644';
    if (!abd && !el) return '';
    return tokens
        .slice(0, 4)
        .map((token) => token.replace(/ /g, ''))
        .join('');
}

function latinToArabic(token) {
    const stem = compact(token).replace(/[^a-z0-9]/g, '');
    if (stem.length < 3 || containsArabic(stem)) return '';
    let out = '';
    let i = 0;
    while (i < stem.length) {
        const two = stem.slice(i, i + 2);
        const one = stem.slice(i, i + 1);
        if (LATIN_TO_ARABIC[two]) {
            out += LATIN_TO_ARABIC[two];
            i += 2;
            continue;
        }
        if ('aeiou'.includes(one)) {
            i += 1;
            continue;
        }
        out += LATIN_TO_ARABIC[one] || '';
        i += 1;
    }
    return out.length >= 3 ? out : '';
}

function arabicToLatin(token) {
    const stem = compact(token);
    if (!containsArabic(stem)) return '';
    let out = '';
    for (const ch of stem) {
        if (ARABIC_TO_LATIN[ch] != null) out += ARABIC_TO_LATIN[ch];
    }
    return out.length >= 3 ? out : '';
}

export function graphemeVariants(token) {
    const arabic = latinToArabic(token);
    const latin = arabicToLatin(token);
    return [arabic, latin].filter((value) => value && value.length >= 3);
}

function addNeedle(needles, seen, value) {
    const trimmed = String(value || '').trim();
    if (trimmed.length < 3 || needles.length >= 12) return;
    const key = compact(trimmed);
    if (!key || seen.has(key)) return;
    seen.add(key);
    needles.push(trimmed);
}

function pickVariants(values, add) {
    let arabic = 0;
    let latin = 0;
    for (const value of values || []) {
        if (!value || String(value).trim().length < 3) continue;
        const isArabic = containsArabic(value);
        if (isArabic && arabic >= 2) continue;
        if (!isArabic && latin >= 2) continue;
        add(value);
        if (isArabic) arabic += 1;
        else latin += 1;
    }
}

function prefixFamilies(index, stem, add, maxFamilies) {
    if (!stem || stem.length < 4) return 0;
    const matches = [];
    for (const key of Object.keys(index)) {
        const keyCompact = compact(key);
        if (keyCompact.length < 4) continue;
        if (
            keyCompact.startsWith(stem) ||
            (stem.startsWith(keyCompact) && keyCompact.length + 1 >= stem.length)
        ) {
            matches.push({ key, keyCompact, values: index[key] || [] });
        }
    }
    matches.sort(
        (left, right) =>
            Math.abs(left.keyCompact.length - stem.length) -
            Math.abs(right.keyCompact.length - stem.length)
    );
    let count = 0;
    for (const match of matches) {
        if (count >= maxFamilies) break;
        pickVariants(match.values, add);
        add(match.key);
        count += 1;
    }
    return count;
}

export function lookupNeedles(index, term, phoneticOnly = false) {
    const source = index || {};
    const tokens = tokenize(term);
    const stem = compoundStem(tokens);
    const needles = [];
    const seen = new Set();
    const add = (value) => addNeedle(needles, seen, value);
    if (phoneticOnly) {
        for (const variant of graphemeVariants(term)) add(variant);
        if (stem) {
            for (const variant of graphemeVariants(stem)) add(variant);
        }
        for (const token of tokens) {
            if (token.length >= 3) {
                for (const variant of graphemeVariants(token)) add(variant);
            }
        }
        add(term);
        return needles;
    }
    if (stem && stem.length >= 4 && prefixFamilies(source, stem, add, 4) > 0) {
        add(term);
        return needles;
    }
    const significant = tokens.filter((token) => token.length >= 3);
    const pool = significant.length ? significant : [foldToken(term)].filter((token) => token.length >= 3);
    for (const token of pool) {
        const family = familyFor(source, token);
        if (family.length) {
            pickVariants(family, add);
            if (pool.length === 1) prefixFamilies(source, compact(token), add, 3);
        } else if (!prefixFamilies(source, compact(token), add, 3)) {
            for (const variant of graphemeVariants(token)) add(variant);
            add(token);
        }
    }
    add(term);
    return needles;
}

export function scoreCandidate(query, name, needles) {
    const foldedName = foldToken(name);
    const foldedQuery = foldToken(query).replace(/ /g, '');
    const foldedCompact = foldedName.replace(/ /g, '');
    let score = 0;
    if (foldedQuery && (foldedCompact.includes(foldedQuery) || foldedQuery.includes(foldedCompact))) {
        score = 92;
    }
    for (const needle of needles || []) {
        const foldedNeedle = foldToken(needle);
        if (foldedNeedle.length >= 4 && foldedName.includes(foldedNeedle)) {
            score = Math.max(score, 80 + Math.min(15, foldedNeedle.length));
        }
    }
    return score;
}

export function toHit(row, reason = 'Search') {
    const developerName = row?.RecordType?.DeveloperName || row?.recordTypeDeveloperName || null;
    return {
        accountId: row.accountId || row.Id,
        accountName: row.accountName || row.Name,
        visitId: row.visitId || null,
        visitLabel: row.visitLabel || null,
        reason: row.reason || reason,
        recordTypeLabel: row?.RecordType?.Name || row.recordTypeLabel || null,
        recordTypeDeveloperName: developerName,
        iconName: row.iconName || iconForRecordType(developerName)
    };
}
