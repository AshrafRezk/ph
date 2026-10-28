/**
 * Demo fixture: executing a visit (visit shell tabs, CLM player, samples, store check,
 * pharmacy order) plus the CLM Presentations hub and the Class Engine tab.
 * All records are built from demoSeed.js and kept in memory for the session so writes
 * show up on the next read. CLM decks are generated here: HTML decks as a stored ZIP of
 * self-contained slides, the PDF deck as a small text PDF, both served as base64.
 */
import {
    DEMO_ACCOUNTS,
    DEMO_CLM_DECKS,
    DEMO_MANAGER_ID,
    DEMO_PRODUCTS,
    DEMO_TERRITORY,
    DEMO_USER_ID,
    addDays,
    demoVisits,
    todayIso
} from '../demoSeed.js';

const DEMO_DM_TERRITORY_ID = '0MIDEMO00000000002';
const REP_NAME = 'Demo Field Rep';
const SLIDE_W = 1024;
const SLIDE_H = 576;
const DEMO_FOOTER = 'Fictional product for app demonstration only';

// ---------------------------------------------------------------- ids + helpers

let dynamicCounter = 0;

function seedId(prefix, n) {
    return `${prefix}DEMO${String(n).padStart(11, '0')}`;
}

/** New 18-char alphanumeric id (the CLM player only accepts [a-zA-Z0-9]{18} session ids). */
function newId(prefix) {
    dynamicCounter += 1;
    return `${prefix}DEMON${String(dynamicCounter).padStart(10, '0')}`;
}

function clone(value) {
    return value == null ? value : JSON.parse(JSON.stringify(value));
}

function localIso(dateTime) {
    const d = new Date(dateTime);
    return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

function sameId(a, b) {
    const left = String(a ?? '');
    const right = String(b ?? '');
    if (left === right) return true;
    // 15-char ids match their 18-char form; two 18-char ids must match exactly.
    const short = left.length === 15 || right.length === 15;
    return short && left.length >= 15 && right.length >= 15 && left.slice(0, 15) === right.slice(0, 15);
}

const BRAND_COLORS = {
    Cardiora: '#c8364f',
    Lipovia: '#2f6fc4',
    Glucoset: '#16906b'
};

function brandColor(brand) {
    return BRAND_COLORS[brand] || '#5b6b84';
}

function svgDataUrl(svg) {
    return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
}

function xmlEscape(text) {
    return String(text || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function strengthOf(name) {
    const match = /(\d+\s*mg)/i.exec(name || '');
    return match ? match[1] : '';
}

/** Small brand tile used as Product_Image_URL__c. */
function productImage(product) {
    const initials = product.brand.slice(0, 2).toUpperCase();
    const sub = product.type === 'Sample' ? 'SAMPLE' : strengthOf(product.name);
    return svgDataUrl(
        '<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120" viewBox="0 0 120 120">' +
            `<rect width="120" height="120" rx="24" fill="${brandColor(product.brand)}"/>` +
            '<text x="60" y="66" font-family="Arial,Helvetica,sans-serif" font-size="34" font-weight="700" ' +
            `fill="#fff" text-anchor="middle">${initials}</text>` +
            '<text x="60" y="94" font-family="Arial,Helvetica,sans-serif" font-size="14" fill="#fff" ' +
            `text-anchor="middle" opacity="0.9">${xmlEscape(sub)}</text></svg>`
    );
}

const RECORD_TYPES = {
    HCP: { DeveloperName: 'Medical_Professional_HCP', Name: 'HCP' },
    Clinic: { DeveloperName: 'Institution_HCO', Name: 'Clinic' },
    Hospital: { DeveloperName: 'Institution_HCO', Name: 'Hospital' },
    Pharmacy: { DeveloperName: 'Pharmacy', Name: 'Pharmacy' }
};

function recordTypeOf(account) {
    return RECORD_TYPES[account.kind] || RECORD_TYPES.HCP;
}

function productById(id) {
    return DEMO_PRODUCTS.find((p) => sameId(p.id, id)) || null;
}

function accountSeed(id) {
    return DEMO_ACCOUNTS.find((a) => sameId(a.id, id)) || null;
}

// ---------------------------------------------------------------- CLM deck content

const DECK_SLIDES = {
    [DEMO_CLM_DECKS[0].id]: [
        ['Meet Cardiora', 'A fictional once-daily blood pressure brand', 'Available as 10 mg and 20 mg tablets'],
        ['Why control matters', 'Most patients need several visits to reach goal', 'Simple regimens help patients stay on track'],
        ['Simple dosing', 'One tablet each morning, with or without food', 'Start at 10 mg and step up to 20 mg if needed'],
        ['Patient profile', 'Adults with newly diagnosed hypertension', 'Patients who prefer a once-daily routine'],
        ['Support materials', 'Patient diary cards and reminder leaflets', 'Starter sample packs available on request'],
        ['Summary', 'Once daily, two strengths, simple titration', 'Ask about starter samples today']
    ],
    [DEMO_CLM_DECKS[1].id]: [
        ['Meet Lipovia', 'A fictional once-daily lipid-lowering brand', 'Lipovia 40 mg tablets'],
        ['Know the target', 'Agree an LDL goal with each patient', 'Recheck lipids at the next follow-up'],
        ['Easy to start', 'One tablet in the evening', 'Review tolerability at follow-up'],
        ['Staying on therapy', 'Explain why long-term use matters', 'Use reminder tools to support adherence'],
        ['Summary', 'Set the goal, start simply, follow up', 'Leave-behind material available']
    ],
    [DEMO_CLM_DECKS[2].id]: [
        ['Meet Glucoset XR', 'A fictional extended-release brand', 'Glucoset XR 500 mg tablets'],
        ['Once-daily dosing', 'Taken with the evening meal', 'Extended release for a simple routine'],
        ['Starting a patient', 'Begin with one tablet daily', 'Review at the next scheduled visit'],
        ['Summary', 'A simple once-daily routine', 'Patient leaflets available on request']
    ]
};

const MESSAGE_SLIDE_INDEX = 1;
const SLIDE_MESSAGES = 'EFFICACY;DOSING';

function deckInfo(deck, index) {
    const product = productById(deck.productId) || DEMO_PRODUCTS[0];
    return {
        ...deck,
        index,
        product,
        color: brandColor(product.brand),
        contentDocumentId: seedId('069', index + 1),
        slidesContent: (DECK_SLIDES[deck.id] || []).slice(0, deck.slides)
    };
}

const DECKS = DEMO_CLM_DECKS.map(deckInfo);

function deckById(id) {
    return DECKS.find((d) => sameId(d.id, id)) || null;
}

function deckByDocumentId(docId) {
    return DECKS.find((d) => sameId(d.contentDocumentId, docId)) || null;
}

function slideThumbnail(deck, slide, n) {
    return svgDataUrl(
        '<svg xmlns="http://www.w3.org/2000/svg" width="320" height="180" viewBox="0 0 320 180">' +
            '<rect width="320" height="180" fill="#f5f7fb"/>' +
            `<rect width="320" height="34" fill="${deck.color}"/>` +
            '<text x="14" y="22" font-family="Arial,Helvetica,sans-serif" font-size="12" fill="#fff">' +
            `${xmlEscape(deck.product.brand)} · ${n}/${deck.slides}</text>` +
            '<text x="14" y="84" font-family="Arial,Helvetica,sans-serif" font-size="20" font-weight="700" ' +
            `fill="#1b2333">${xmlEscape(slide[0])}</text>` +
            `<rect x="14" y="106" width="8" height="8" fill="${deck.color}"/>` +
            `<rect x="14" y="128" width="8" height="8" fill="${deck.color}"/>` +
            '<rect x="30" y="106" width="200" height="8" rx="4" fill="#c9d1de"/>' +
            '<rect x="30" y="128" width="160" height="8" rx="4" fill="#c9d1de"/></svg>'
    );
}

function sequenceId(deck, n) {
    return `a0B${'DEMO'}${String(deck.index + 1)}${String(n).padStart(10, '0')}`;
}

function deckSequences(deck) {
    return deck.slidesContent.map((slide, i) => ({
        id: sequenceId(deck, i + 1),
        sequenceOrder: i + 1,
        sequenceName: slide[0],
        fileName: deck.format === 'PDF' ? null : `slide${i + 1}.html`,
        productNames: deck.product.name,
        messageNames: i === MESSAGE_SLIDE_INDEX ? SLIDE_MESSAGES : null,
        isMandatory: i === 0,
        thumbnailUrl: slideThumbnail(deck, slide, i + 1),
        slideImageUrl: null,
        pageNumber: i + 1,
        htmlEntryPoint: deck.format === 'PDF' ? null : `slide${i + 1}.html`
    }));
}

function htmlSlide(deck, slide, n) {
    const [headline, b1, b2] = slide;
    return `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=${SLIDE_W}, height=${SLIDE_H}">
<title>${xmlEscape(headline)}</title>
<style>
html,body{margin:0;width:${SLIDE_W}px;height:${SLIDE_H}px;overflow:hidden;font-family:Arial,Helvetica,sans-serif;color:#1b2333}
/* The CLM player injects a fit style (transparent, centred, max 100%); fill the frame instead. */
.slide{position:fixed;inset:0;max-width:none!important;max-height:none!important;overflow:hidden;background:#f5f7fb}
.band{height:14vh;background:${deck.color};color:#fff;display:flex;align-items:center;justify-content:space-between;padding:0 4.7vw;font-size:2.2vw;font-weight:700}
.band span{font-weight:400;font-size:1.75vw;opacity:.9}
h1{font-size:4.3vw;margin:12.5vh 4.7vw 6vh}
ul{list-style:none;margin:0 4.7vw;padding:0}
li{font-size:2.75vw;margin:0 0 3.8vh;padding-left:3.3vw;position:relative}
li:before{content:"";position:absolute;left:0;top:1vw;width:1.4vw;height:1.4vw;border-radius:.3vw;background:${deck.color}}
.foot{position:absolute;left:4.7vw;right:4.7vw;bottom:4vh;font-size:1.4vw;color:#6b778c;display:flex;justify-content:space-between}
</style></head>
<body><div class="slide"><div class="band">${xmlEscape(deck.name)}<span>${n} / ${deck.slides}</span></div>
<h1>${xmlEscape(headline)}</h1>
<ul><li>${xmlEscape(b1)}</li><li>${xmlEscape(b2)}</li></ul>
<div class="foot"><span>${DEMO_FOOTER}</span><span>Demo Pharma</span></div>
</div></body></html>`;
}

// ---------------------------------------------------------------- ZIP + PDF builders

let crcTable = null;

function crc32(bytes) {
    if (!crcTable) {
        crcTable = new Uint32Array(256);
        for (let n = 0; n < 256; n += 1) {
            let c = n;
            for (let k = 0; k < 8; k += 1) {
                c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
            }
            crcTable[n] = c >>> 0;
        }
    }
    let crc = 0xffffffff;
    for (let i = 0; i < bytes.length; i += 1) {
        crc = crcTable[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8);
    }
    return (crc ^ 0xffffffff) >>> 0;
}

function concatBytes(parts) {
    const total = parts.reduce((sum, p) => sum + p.length, 0);
    const out = new Uint8Array(total);
    let offset = 0;
    parts.forEach((p) => {
        out.set(p, offset);
        offset += p.length;
    });
    return out;
}

function le(size, value) {
    const out = new Uint8Array(size);
    for (let i = 0; i < size; i += 1) {
        out[i] = (value >>> (8 * i)) & 0xff;
    }
    return out;
}

/** Uncompressed (stored) ZIP, enough for JSZip.loadAsync. */
function buildZip(files) {
    const enc = new TextEncoder();
    const locals = [];
    const centrals = [];
    let offset = 0;
    files.forEach(({ name, text }) => {
        const nameBytes = enc.encode(name);
        const data = enc.encode(text);
        const crc = crc32(data);
        const common = [le(2, 20), le(2, 0), le(2, 0), le(2, 0), le(2, 0x21), le(4, crc), le(4, data.length), le(4, data.length), le(2, nameBytes.length), le(2, 0)];
        const local = concatBytes([le(4, 0x04034b50), ...common, nameBytes, data]);
        centrals.push(
            concatBytes([le(4, 0x02014b50), le(2, 20), ...common, le(2, 0), le(2, 0), le(2, 0), le(4, 0), le(4, offset), nameBytes])
        );
        locals.push(local);
        offset += local.length;
    });
    const central = concatBytes(centrals);
    const end = concatBytes([
        le(4, 0x06054b50), le(2, 0), le(2, 0), le(2, files.length), le(2, files.length),
        le(4, central.length), le(4, offset), le(2, 0)
    ]);
    return concatBytes([...locals, central, end]);
}

function pdfText(text) {
    return String(text || '')
        .replace(/[^\x20-\x7e]/g, '-')
        .replace(/\\/g, '\\\\')
        .replace(/\(/g, '\\(')
        .replace(/\)/g, '\\)');
}

function rgb(hex) {
    const n = parseInt(hex.slice(1), 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((v) => (v / 255).toFixed(3)).join(' ');
}

/** Minimal text PDF (Helvetica, one page per slide) that pdf.js renders. */
function buildPdf(deck) {
    const color = rgb(deck.color);
    const objects = [];
    const pageIds = [];
    const fontRegular = 3;
    const fontBold = 4;
    objects[fontRegular] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>';
    objects[fontBold] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>';
    let next = 5;
    deck.slidesContent.forEach((slide, i) => {
        const [headline, b1, b2] = slide;
        const stream = [
            '0.961 0.969 0.984 rg 0 0 1024 576 re f',
            `${color} rg 0 496 1024 80 re f`,
            `BT /F2 22 Tf 1 1 1 rg 48 528 Td (${pdfText(deck.name)}) Tj ET`,
            `BT /F1 18 Tf 1 1 1 rg 920 528 Td (${i + 1} / ${deck.slides}) Tj ET`,
            `BT /F2 42 Tf 0.106 0.137 0.2 rg 48 400 Td (${pdfText(headline)}) Tj ET`,
            `${color} rg 50 322 14 14 re f`,
            `BT /F1 28 Tf 0.106 0.137 0.2 rg 84 320 Td (${pdfText(b1)}) Tj ET`,
            `${color} rg 50 270 14 14 re f`,
            `BT /F1 28 Tf 0.106 0.137 0.2 rg 84 268 Td (${pdfText(b2)}) Tj ET`,
            `BT /F1 14 Tf 0.42 0.467 0.549 rg 48 28 Td (${pdfText(DEMO_FOOTER)}) Tj ET`
        ].join('\n');
        const contentId = next;
        const pageId = next + 1;
        next += 2;
        objects[contentId] = `<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`;
        objects[pageId] =
            `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${SLIDE_W} ${SLIDE_H}] ` +
            `/Resources << /Font << /F1 ${fontRegular} 0 R /F2 ${fontBold} 0 R >> >> /Contents ${contentId} 0 R >>`;
        pageIds.push(pageId);
    });
    objects[1] = '<< /Type /Catalog /Pages 2 0 R >>';
    objects[2] = `<< /Type /Pages /Kids [${pageIds.map((id) => `${id} 0 R`).join(' ')}] /Count ${pageIds.length} >>`;
    let out = '%PDF-1.4\n';
    const offsets = [];
    for (let id = 1; id < objects.length; id += 1) {
        offsets[id] = out.length;
        out += `${id} 0 obj\n${objects[id]}\nendobj\n`;
    }
    const xrefAt = out.length;
    out += `xref\n0 ${objects.length}\n0000000000 65535 f \n`;
    for (let id = 1; id < objects.length; id += 1) {
        out += `${String(offsets[id]).padStart(10, '0')} 00000 n \n`;
    }
    out += `trailer\n<< /Size ${objects.length} /Root 1 0 R >>\nstartxref\n${xrefAt}\n%%EOF\n`;
    return new TextEncoder().encode(out);
}

function toBase64(bytes) {
    if (typeof btoa === 'function') {
        let binary = '';
        for (let i = 0; i < bytes.length; i += 0x8000) {
            binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
        }
        return btoa(binary);
    }
    return globalThis.Buffer.from(bytes).toString('base64');
}

const deckContentCache = new Map();

function deckBase64(deck) {
    if (!deckContentCache.has(deck.id)) {
        const bytes =
            deck.format === 'PDF'
                ? buildPdf(deck)
                : buildZip(
                      deck.slidesContent.map((slide, i) => ({
                          name: `slide${i + 1}.html`,
                          text: htmlSlide(deck, slide, i + 1)
                      }))
                  );
        deckContentCache.set(deck.id, toBase64(bytes));
    }
    return deckContentCache.get(deck.id);
}

// ---------------------------------------------------------------- in-memory tables

let db = null;

function productRecord(p) {
    const parent = p.type === 'Sample' ? DEMO_PRODUCTS.find((x) => x.brand === p.brand && x.type !== 'Sample') : null;
    return {
        attributes: { type: 'Product2' },
        Id: p.id,
        Name: p.name,
        ProductCode: p.code,
        IsActive: true,
        Product_Type__c: p.type,
        Primary_Brand__c: p.brand,
        Parent_Product__c: parent ? parent.id : null,
        Parent_Product__r: parent ? { Name: parent.name } : null,
        Strength__c: strengthOf(p.name) || null,
        Form__c: 'Tablet',
        Product_Image_URL__c: productImage(p)
    };
}

function productRef(p) {
    const rec = productRecord(p);
    return {
        Name: rec.Name,
        Product_Image_URL__c: rec.Product_Image_URL__c,
        Product_Type__c: rec.Product_Type__c,
        Parent_Product__c: rec.Parent_Product__c,
        Parent_Product__r: rec.Parent_Product__r,
        Primary_Brand__c: rec.Primary_Brand__c
    };
}

function accountRecord(a, i) {
    return {
        attributes: { type: 'Account' },
        Id: a.id,
        Name: a.name,
        RecordType: { ...recordTypeOf(a) },
        Specialty_1__c: a.specialty,
        BillingCity: a.city,
        BillingLatitude: a.lat,
        BillingLongitude: a.lng,
        Phone: a.phone,
        LastModifiedDate: localIso(`${addDays(todayIso(), -i)}T09:00:00`)
    };
}

function accountRef(a) {
    return {
        Name: a.name,
        BillingCity: a.city,
        Specialty_1__c: a.specialty,
        BillingLatitude: a.lat,
        BillingLongitude: a.lng,
        RecordType: { ...recordTypeOf(a) }
    };
}

function objectiveFor(account) {
    if (account.kind === 'Pharmacy') return 'Check Cardiora and Lipovia stock and agree a reorder';
    if (account.kind === 'Hospital') return 'Introduce the Lipovia formulary pack to the cardiology team';
    return `Present ${DEMO_PRODUCTS[0].brand} dosing and ${DEMO_PRODUCTS[2].brand} LDL targets`;
}

const SAMPLE_PRODUCT = DEMO_PRODUCTS.find((p) => p.type === 'Sample');

function buildDb() {
    const t = {
        Account: DEMO_ACCOUNTS.map(accountRecord),
        Product2: DEMO_PRODUCTS.map(productRecord),
        Visit__c: [],
        Visit_Attendee__c: [],
        Visit_Product_Detail__c: [],
        Visit_Product_Message__c: [],
        Visit_Sample__c: [],
        Sample_Inventory__c: [],
        Account_Territory_Product_Fields__c: [],
        Account_Affiliation__c: [],
        CLM_Presentation__c: [],
        CLM_Sequence__c: [],
        CLM_Presentation_Session__c: [],
        Store_Check__c: [],
        Store_Check_Line__c: [],
        ContentDocumentLink: [],
        Visit_Order__c: [],
        Visit_Order_Line__c: [],
        Territory2: [],
        UserTerritory2Association: []
    };

    t.Territory2.push(
        {
            attributes: { type: 'Territory2' },
            Id: DEMO_TERRITORY.id,
            Name: DEMO_TERRITORY.name,
            External_ID__c: 'TERR_POS_DEMO_CARDIO_1',
            Territory_Type__c: 'Position',
            ParentTerritory2Id: DEMO_DM_TERRITORY_ID
        },
        {
            attributes: { type: 'Territory2' },
            Id: DEMO_DM_TERRITORY_ID,
            Name: DEMO_TERRITORY.district,
            External_ID__c: 'TERR_DM_DEMO_CAIRO',
            Territory_Type__c: 'District',
            ParentTerritory2Id: null
        }
    );
    t.UserTerritory2Association.push(
        {
            attributes: { type: 'UserTerritory2Association' },
            Id: seedId('0R0', 1),
            UserId: DEMO_USER_ID,
            User: { Name: REP_NAME, IsActive: true },
            RoleInTerritory2: 'Medical Rep',
            Territory2Id: DEMO_TERRITORY.id,
            Territory2: { Name: DEMO_TERRITORY.name }
        },
        {
            attributes: { type: 'UserTerritory2Association' },
            Id: seedId('0R0', 2),
            UserId: DEMO_MANAGER_ID,
            User: { Name: DEMO_TERRITORY.managerName, IsActive: true },
            RoleInTerritory2: 'District Manager',
            Territory2Id: DEMO_DM_TERRITORY_ID,
            Territory2: { Name: DEMO_TERRITORY.district }
        }
    );

    const adoption = ['Adopter', 'Trialist', 'Aware', 'Adopter'];
    const loyalty = ['High', 'Medium', 'Low'];
    DEMO_ACCOUNTS.forEach((a, i) => {
        DEMO_PRODUCTS.filter((p) => p.type !== 'Sample').forEach((p, j) => {
            t.Account_Territory_Product_Fields__c.push({
                attributes: { type: 'Account_Territory_Product_Fields__c' },
                Id: seedId('a0A', i * 10 + j + 1),
                Account__c: a.id,
                Product2_Id__c: p.id,
                Is_Active__c: true,
                Adoption__c: adoption[(i + j) % adoption.length],
                Loyalty__c: loyalty[(i + 2 * j) % loyalty.length],
                Product_Matrix_Rating__c: `${a.classCode}${(j % 3) + 1}`,
                Target_Visit_Frequency__c: a.frequency,
                Rx_Per_Week__c: 2 + ((i * 3 + j * 5) % 9)
            });
        });
    });

    const lots = [
        { lot: 'DEMO-L2401', qty: 40, months: 8 },
        { lot: 'DEMO-L2402', qty: 25, months: 14 }
    ];
    lots.forEach((l, i) => {
        t.Sample_Inventory__c.push({
            attributes: { type: 'Sample_Inventory__c' },
            Id: seedId('a0I', i + 1),
            Owner_User__c: DEMO_USER_ID,
            Product2__c: SAMPLE_PRODUCT.id,
            Product2__r: productRef(SAMPLE_PRODUCT),
            Lot_Number__c: l.lot,
            Quantity_On_Hand__c: l.qty,
            Expiry_Date__c: addDays(todayIso(), l.months * 30)
        });
    });

    const affiliations = [
        [3, 11, 'Works At', 'Consultant', 'Strong'],
        [6, 11, 'Works At', 'Consultant', 'Strong'],
        [2, 11, 'Works At', 'Specialist', 'Medium'],
        [1, 8, 'Works At', 'Consultant', 'Strong'],
        [9, 1, 'Nearby Pharmacy', 'Prescriber', 'Medium'],
        [9, 4, 'Nearby Pharmacy', 'Prescriber', 'Weak'],
        [10, 3, 'Nearby Pharmacy', 'Prescriber', 'Medium'],
        [3, 7, 'Refers To', 'Referrer', 'Weak']
    ];
    affiliations.forEach(([from, to, type, role, strength], i) => {
        const primary = DEMO_ACCOUNTS[from - 1];
        const related = DEMO_ACCOUNTS[to - 1];
        t.Account_Affiliation__c.push({
            attributes: { type: 'Account_Affiliation__c' },
            Id: seedId('a0F', i + 1),
            Primary_Account__c: primary.id,
            Related_Account__c: related.id,
            Primary_Account__r: { Name: primary.name, RecordType: { Name: recordTypeOf(primary).Name } },
            Related_Account__r: { Name: related.name, RecordType: { Name: recordTypeOf(related).Name } },
            Affiliation_Type__c: type,
            Role__c: role,
            Strength__c: strength,
            Description__c: `${primary.name} - ${type.toLowerCase()} - ${related.name}`,
            Is_Active__c: true,
            Outside_Territory__c: false
        });
    });

    DECKS.forEach((deck) => {
        t.CLM_Presentation__c.push({
            attributes: { type: 'CLM_Presentation__c' },
            Id: deck.id,
            Name: deck.name,
            Status__c: 'Available',
            Format__c: deck.format,
            Product__c: deck.product.id,
            Product__r: { Name: deck.product.name, Product_Image_URL__c: productImage(deck.product) },
            Slide_Count__c: deck.slides,
            Tags__c: `${deck.product.brand};Demo`,
            Content_Document_Id__c: deck.contentDocumentId
        });
        deckSequences(deck).forEach((seq) => {
            t.CLM_Sequence__c.push({
                attributes: { type: 'CLM_Sequence__c' },
                Id: seq.id,
                CLM_Presentation__c: deck.id,
                Sequence_Order__c: seq.sequenceOrder,
                Sequence_Name__c: seq.sequenceName,
                Page_Number__c: seq.pageNumber,
                HTML_Entry_Point__c: seq.htmlEntryPoint
            });
        });
    });

    demoVisits().forEach((v, i) => {
        const account = v.account;
        const completed = v.status === 'Completed';
        const start = localIso(v.start);
        t.Visit__c.push({
            attributes: { type: 'Visit__c' },
            Id: v.id,
            Name: v.name,
            Status__c: completed ? 'Completed' : 'Scheduled',
            Visit_Type__c: 'Planned (Manager)',
            Start_Date__c: start,
            End_Date__c: localIso(v.end),
            Visit_Objective__c: objectiveFor(account),
            Visit_Notes__c: completed ? 'Good discussion. Follow up on starter samples at the next visit.' : null,
            Products_Discussed__c: completed ? v.productIds.map((id) => productById(id)?.name).join('; ') : null,
            CLM_Presentation__c: null,
            Next_Visit_Date__c: completed ? addDays(v.date, 14) : null,
            Cancellation_Reason__c: null,
            Is_Double_Visit__c: false,
            Double_Visit_With__c: null,
            Double_Visit_With__r: null,
            Coaching_Event__c: null,
            Account__c: account.id,
            Account__r: accountRef(account),
            Assigned_To__c: DEMO_USER_ID,
            Assigned_To__r: {
                Name: REP_NAME,
                ManagerId: DEMO_MANAGER_ID,
                Manager: { Name: DEMO_TERRITORY.managerName }
            },
            CreatedDate: start
        });
        const attendeeId = seedId('a0T', i + 1);
        t.Visit_Attendee__c.push({
            attributes: { type: 'Visit_Attendee__c' },
            Id: attendeeId,
            Visit__c: v.id,
            Account__c: account.id,
            Account__r: { Name: account.name, Specialty_1__c: account.specialty, RecordType: { ...recordTypeOf(account) } },
            CreatedDate: start
        });
        v.productIds.forEach((pid, j) => {
            const p = productById(pid);
            t.Visit_Product_Detail__c.push({
                attributes: { type: 'Visit_Product_Detail__c' },
                Id: seedId('a0P', (i + 1) * 10 + j),
                Visit__c: v.id,
                Product2__c: p.id,
                Product2__r: productRef(p),
                Display_Order__c: j + 1,
                Detail_Type__c: 'Detail',
                Notes__c: '',
                CreatedDate: start
            });
        });
        if (completed && account.kind !== 'Pharmacy') {
            t.Visit_Sample__c.push({
                attributes: { type: 'Visit_Sample__c' },
                Id: seedId('a0S', i + 1),
                Visit__c: v.id,
                Product2__c: SAMPLE_PRODUCT.id,
                Product2__r: productRef(SAMPLE_PRODUCT),
                Visit_Attendee__c: attendeeId,
                Visit_Attendee__r: { Account__r: { Name: account.name } },
                Quantity__c: 2,
                Lot_Number__c: lots[0].lot,
                Sample_Inventory__c: seedId('a0I', 1),
                CreatedDate: start
            });
        }
        if (completed) {
            const deck = DECKS[i % 2];
            const ended = new Date(new Date(start).getTime() + 6 * 60000).toISOString();
            t.CLM_Presentation_Session__c.push(
                sessionRecord({
                    id: seedId('a0E', i + 1),
                    deck,
                    visitId: v.id,
                    status: 'Completed',
                    startedAt: start,
                    endedAt: ended,
                    dwell: Object.fromEntries(deckSequences(deck).map((s) => [s.id, 40]))
                })
            );
        }
        if (completed && account.kind === 'Pharmacy') {
            const checkId = seedId('a0K', i + 1);
            t.Store_Check__c.push({
                attributes: { type: 'Store_Check__c' },
                Id: checkId,
                Visit__c: v.id,
                Account__c: account.id,
                Notes__c: 'Cardiora shelf well stocked; Lipovia low on facings.',
                CreatedDate: start
            });
            [[0, true, 4], [2, true, 1], [3, false, 0]].forEach(([pi, available, facings], j) => {
                const p = DEMO_PRODUCTS[pi];
                t.Store_Check_Line__c.push({
                    attributes: { type: 'Store_Check_Line__c' },
                    Id: seedId('a0L', (i + 1) * 10 + j),
                    Store_Check__c: checkId,
                    Product__c: p.id,
                    Product__r: { Name: p.name },
                    Available__c: available,
                    Facings__c: facings,
                    CreatedDate: start
                });
            });
            const orderId = seedId('a0O', i + 1);
            t.Visit_Order__c.push({
                attributes: { type: 'Visit_Order__c' },
                Id: orderId,
                Name: `ORD-DEMO-${String(i + 1).padStart(4, '0')}`,
                Visit__c: v.id,
                Status__c: 'Submitted',
                Notes__c: 'Deliver before the weekend.',
                CreatedDate: start
            });
            [[0, 24], [2, 12]].forEach(([pi, qty], j) => {
                const p = DEMO_PRODUCTS[pi];
                t.Visit_Order_Line__c.push({
                    attributes: { type: 'Visit_Order_Line__c' },
                    Id: seedId('a0R', (i + 1) * 10 + j),
                    Visit_Order__c: orderId,
                    Product2__c: p.id,
                    Product2__r: { Name: p.name },
                    Quantity__c: qty,
                    Notes__c: null,
                    Display_Order__c: j + 1,
                    CreatedDate: start
                });
            });
        }
    });
    return t;
}

function tables() {
    if (!db) db = buildDb();
    return db;
}

function findRow(object, id) {
    return (tables()[object] || []).find((row) => sameId(row.Id, id)) || null;
}

// ---------------------------------------------------------------- tiny SOQL evaluator

const ANY = Symbol('any');

function tokenize(text) {
    const tokens = [];
    const re = /\s*(?:'((?:\\.|[^'\\])*)'|(!=|<>|<=|>=|=|<|>)|([(),])|([A-Za-z0-9_.:+\-]+))/gy;
    let match;
    while (re.lastIndex < text.length && (match = re.exec(text))) {
        if (match[1] !== undefined) tokens.push({ type: 'str', value: match[1].replace(/\\(.)/g, '$1') });
        else if (match[2]) tokens.push({ type: 'op', value: match[2] === '<>' ? '!=' : match[2] });
        else if (match[3]) tokens.push({ type: match[3] });
        else if (match[4]) tokens.push({ type: 'word', value: match[4] });
        if (!match[0].length) break;
    }
    return tokens;
}

function literal(token) {
    if (!token) return ANY;
    if (token.type === 'str') return token.value;
    const word = token.value;
    const upper = word.toUpperCase();
    if (upper === 'NULL') return null;
    if (upper === 'TRUE') return true;
    if (upper === 'FALSE') return false;
    if (/^-?\d+(\.\d+)?$/.test(word)) return Number(word);
    if (/^\d{4}-\d{2}-\d{2}/.test(word)) return word;
    return ANY;
}

function parseWhere(text) {
    const tokens = tokenize(text);
    let pos = 0;
    const peekWord = (w) => tokens[pos]?.type === 'word' && tokens[pos].value.toUpperCase() === w;

    function parseValue() {
        if (tokens[pos]?.type === '(') {
            pos += 1;
            const list = [];
            while (pos < tokens.length && tokens[pos].type !== ')') {
                if (tokens[pos].type !== ',') list.push(literal(tokens[pos]));
                pos += 1;
            }
            pos += 1;
            return list;
        }
        const value = literal(tokens[pos]);
        pos += 1;
        return value;
    }

    function parseComparison() {
        const field = tokens[pos]?.value;
        pos += 1;
        let op;
        if (tokens[pos]?.type === 'op') {
            op = tokens[pos].value;
            pos += 1;
        } else if (peekWord('NOT') && tokens[pos + 1]?.value?.toUpperCase() === 'IN') {
            op = 'NOT IN';
            pos += 2;
        } else if (tokens[pos]?.type === 'word') {
            op = tokens[pos].value.toUpperCase();
            pos += 1;
        }
        const value = parseValue();
        return (row) => compare(row, field, op, value);
    }

    function parseFactor() {
        if (peekWord('NOT')) {
            pos += 1;
            const inner = parseFactor();
            return (row) => !inner(row);
        }
        if (tokens[pos]?.type === '(') {
            pos += 1;
            const inner = parseOr();
            pos += 1;
            return inner;
        }
        return parseComparison();
    }

    function parseAnd() {
        const parts = [parseFactor()];
        while (peekWord('AND')) {
            pos += 1;
            parts.push(parseFactor());
        }
        return (row) => parts.every((fn) => fn(row));
    }

    function parseOr() {
        const parts = [parseAnd()];
        while (peekWord('OR')) {
            pos += 1;
            parts.push(parseAnd());
        }
        return (row) => parts.some((fn) => fn(row));
    }

    return parseOr();
}

function getPath(row, path) {
    return String(path || '')
        .split('.')
        .reduce((value, key) => (value == null ? value : value[key]), row);
}

function equalValues(a, b) {
    if (a == null || b == null) return a == null && b == null;
    if (typeof a === 'boolean' || typeof b === 'boolean') return String(a).toLowerCase() === String(b).toLowerCase();
    if (typeof a === 'number' || typeof b === 'number') return Number(a) === Number(b);
    return sameId(a, b) || String(a).toLowerCase() === String(b).toLowerCase();
}

function orderValues(a, b) {
    if (typeof a === 'number' && typeof b === 'number') return a - b;
    const da = Date.parse(a);
    const dbv = Date.parse(b);
    if (!Number.isNaN(da) && !Number.isNaN(dbv) && /\d{4}-\d{2}-\d{2}/.test(String(a))) return da - dbv;
    return String(a).localeCompare(String(b));
}

/** Fields the fixture does not model pass the filter, so unknown conditions never hide data. */
function compare(row, field, op, value) {
    if (value === ANY) return true;
    const actual = getPath(row, field);
    if (actual === undefined) return true;
    switch (op) {
        case '=':
            return equalValues(actual, value);
        case '!=':
            return !equalValues(actual, value);
        case 'IN':
            return Array.isArray(value) && value.some((v) => v === ANY || equalValues(actual, v));
        case 'NOT IN':
            return !(Array.isArray(value) && value.some((v) => equalValues(actual, v)));
        case 'LIKE': {
            const pattern = String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/%/g, '.*').replace(/_/g, '.');
            return new RegExp(`^${pattern}$`, 'i').test(String(actual ?? ''));
        }
        case '<':
        case '>':
        case '<=':
        case '>=': {
            if (actual == null || value == null) return false;
            const diff = orderValues(actual, value);
            return op === '<' ? diff < 0 : op === '>' ? diff > 0 : op === '<=' ? diff <= 0 : diff >= 0;
        }
        default:
            return true;
    }
}

function clauseAfter(soql, keyword, stops) {
    const re = new RegExp(`\\b${keyword}\\b([\\s\\S]*?)(?=\\b(?:${stops.join('|')})\\b|$)`, 'i');
    const match = re.exec(soql);
    return match ? match[1].trim() : '';
}

/** Applies WHERE, ORDER BY, LIMIT and OFFSET of a simple SOQL string to rows. */
function runSoql(rows, soql) {
    const text = String(soql || '').replace(/\s+/g, ' ');
    let out = rows.slice();
    const where = clauseAfter(text, 'WHERE', ['ORDER BY', 'LIMIT', 'OFFSET', 'GROUP BY']);
    if (where) {
        try {
            const predicate = parseWhere(where);
            out = out.filter((row) => predicate(row));
        } catch (_err) {
            /* unparseable filter: keep all rows */
        }
    }
    const orderBy = clauseAfter(text, 'ORDER BY', ['LIMIT', 'OFFSET']);
    if (orderBy) {
        const keys = orderBy.split(',').map((part) => {
            const bits = part.trim().split(/\s+/);
            return { field: bits[0], desc: /\bDESC\b/i.test(part) };
        });
        out.sort((a, b) => {
            for (const key of keys) {
                const va = getPath(a, key.field);
                const vb = getPath(b, key.field);
                if (va == null && vb == null) continue;
                if (va == null) return 1;
                if (vb == null) return -1;
                const diff = orderValues(va, vb);
                if (diff) return key.desc ? -diff : diff;
            }
            return 0;
        });
    }
    const offset = Number((/\bOFFSET (\d+)/i.exec(text) || [])[1] || 0);
    const limitMatch = /\bLIMIT (\d+)/i.exec(text);
    out = out.slice(offset, limitMatch ? offset + Number(limitMatch[1]) : undefined);
    return clone(out);
}

// ---------------------------------------------------------------- CLM sessions

const clientSessionMap = new Map();

function sessionRecord({ id, deck, visitId, status, startedAt, endedAt = null, dwell = {} }) {
    return {
        attributes: { type: 'CLM_Presentation_Session__c' },
        Id: id,
        Name: `CLM-${id.slice(-6)}`,
        Status__c: status,
        Started_At__c: startedAt,
        Ended_At__c: endedAt,
        Visit__c: visitId || null,
        CLM_Presentation__c: deck.id,
        CLM_Presentation__r: { Id: deck.id, Name: deck.name, Slide_Count__c: deck.slides },
        Total_Duration_Seconds__c: Object.values(dwell).reduce((sum, s) => sum + Number(s || 0), 0),
        Slides_Presented_Count__c: Object.keys(dwell).length,
        _dwell: dwell,
        _responses: []
    };
}

/** Mirrors ClmMobileRestService.sessionSummaryToMap. */
function sessionSummary(row) {
    const deck = deckById(row.CLM_Presentation__c) || DECKS[0];
    const sequences = deckSequences(deck);
    const dwell = row._dwell || {};
    return {
        id: row.Id,
        visitId: row.Visit__c,
        name: row.Name,
        presentationId: deck.id,
        presentationName: deck.name,
        formatType: deck.format,
        contentDocumentId: deck.contentDocumentId,
        contentVersionId: null,
        publicContentUrl: null,
        contentSize: null,
        status: row.Status__c,
        startedAt: row.Started_At__c,
        endedAt: row.Ended_At__c,
        totalDurationSeconds: row.Total_Duration_Seconds__c,
        slidesPresentedCount: row.Slides_Presented_Count__c,
        slideCount: deck.slides,
        trackingPaused: false,
        productName: deck.product.name,
        productImageUrl: productImage(deck.product),
        nativeWidth: SLIDE_W,
        nativeHeight: SLIDE_H,
        sequences,
        metrics: sequences.map((seq) => ({
            sequenceId: seq.id,
            sequenceOrder: seq.sequenceOrder,
            sequenceName: seq.sequenceName,
            dwellTimeSeconds: dwell[seq.id] || 0,
            wasPresented: dwell[seq.id] != null,
            thumbnailUrl: seq.thumbnailUrl
        }))
    };
}

function startSession(visitId, presentationId) {
    const deck = deckById(presentationId) || DECKS[0];
    const row = sessionRecord({
        id: newId('a0E'),
        deck,
        visitId,
        status: 'Active',
        startedAt: new Date().toISOString()
    });
    tables().CLM_Presentation_Session__c.push(row);
    return row;
}

function sessionFor(id) {
    const mapped = clientSessionMap.get(id);
    return findRow('CLM_Presentation_Session__c', mapped || id);
}

function logSlide(row, sequenceId, seconds) {
    if (!row || !sequenceId) return;
    row._dwell[sequenceId] = (row._dwell[sequenceId] || 0) + Math.max(0, Number(seconds) || 0);
    row.Slides_Presented_Count__c = Object.keys(row._dwell).length;
    row.Total_Duration_Seconds__c = Math.round(Object.values(row._dwell).reduce((s, v) => s + v, 0));
}

function completeSession(row, status = 'Completed') {
    if (!row) return;
    row.Status__c = status;
    row.Ended_At__c = new Date().toISOString();
    if (!row.Slides_Presented_Count__c && status === 'Completed') row.Slides_Presented_Count__c = 1;
}

function saveResponses(row, responses) {
    if (!row) return;
    (Array.isArray(responses) ? responses : []).forEach((r, i) => {
        const existing = row._responses.findIndex((x) => x.messageName === r.messageName);
        const entry = {
            productName: r.productName || null,
            messageName: r.messageName,
            sentiment: r.sentiment,
            sortOrder: r.sortOrder ?? i + 1
        };
        if (existing >= 0) row._responses[existing] = entry;
        else row._responses.push(entry);
    });
}

function handleClm(path, method, body) {
    const sub = path.replace(/^\/services\/apexrest\/clm\/v1\/?/, '');
    if (method === 'GET') {
        if (sub === 'presentations') {
            return DECKS.map((d) => ({
                id: d.id,
                name: d.name,
                status: 'Available',
                formatType: d.format,
                productName: d.product.name,
                imageUrl: productImage(d.product),
                slideCount: d.slides,
                tags: `${d.product.brand};Demo`
            }));
        }
        const visitMatch = /^visits\/([^/]+)\/sessions$/.exec(sub);
        if (visitMatch) {
            return tables()
                .CLM_Presentation_Session__c.filter((row) => sameId(row.Visit__c, visitMatch[1]))
                .sort((a, b) => String(b.Started_At__c).localeCompare(String(a.Started_At__c)))
                .map(sessionSummary);
        }
        const sessionMatch = /^sessions\/([^/]+)$/.exec(sub);
        if (sessionMatch) {
            const row = sessionFor(sessionMatch[1]);
            return row ? sessionSummary(row) : {};
        }
        return undefined;
    }
    const b = body && typeof body === 'object' ? body : {};
    switch (sub) {
        case 'sessions/start':
            return sessionSummary(startSession(b.visitId, b.presentationId));
        case 'sessions/start-ad-hoc':
            return sessionSummary(startSession(null, b.presentationId));
        case 'sessions/slide-event':
            logSlide(sessionFor(b.sessionId), b.sequenceId, b.dwellSeconds);
            return { ok: true };
        case 'sessions/complete': {
            const row = sessionFor(b.sessionId);
            completeSession(row);
            return row ? sessionSummary(row) : {};
        }
        case 'sessions/cancel':
            completeSession(sessionFor(b.sessionId), 'Cancelled');
            return { ok: true };
        case 'sessions/message-responses':
            saveResponses(sessionFor(b.sessionId), b.responses);
            return { ok: true };
        case 'sessions/message-responses/fetch':
            return clone(sessionFor(b.sessionId)?._responses || []);
        case 'pdf-base64': {
            const deck = deckByDocumentId(b.contentDocumentId);
            return deck ? { base64: deckBase64(deck) } : undefined;
        }
        default:
            return undefined;
    }
}

// ---------------------------------------------------------------- call report saves (outbox)

function toIsoOrNull(value) {
    if (!value) return null;
    return localIso(value);
}

function replaceChildren(object, visitId, rows) {
    const t = tables();
    t[object] = t[object].filter((row) => !sameId(row.Visit__c, visitId)).concat(rows);
}

/** Applies a VisitCallReportController save request (callReportJson) to the in-memory visit. */
export function applyCallReport(request) {
    const visit = findRow('Visit__c', request?.visitId);
    if (!visit) return null;
    const now = new Date().toISOString();
    if (request.status) {
        if (request.status === 'Completed' && visit.Status__c !== 'Scheduled' && visit.Status__c !== 'Completed') {
            visit.Visit_Type__c = 'Unplanned';
        }
        visit.Status__c = request.status;
    }
    visit.Visit_Objective__c = request.visitObjective ?? visit.Visit_Objective__c;
    visit.Visit_Notes__c = request.visitNotes ?? visit.Visit_Notes__c;
    visit.Next_Visit_Date__c = request.nextVisitDate || null;
    visit.Cancellation_Reason__c = request.cancellationReason || null;
    visit.CLM_Presentation__c = request.clmPresentation || visit.CLM_Presentation__c;
    visit.Is_Double_Visit__c = request.isDoubleVisit === true;
    visit.Double_Visit_With__c = request.isDoubleVisit ? request.doubleVisitWithId || null : null;
    const companion = tables().UserTerritory2Association.find((row) => sameId(row.UserId, visit.Double_Visit_With__c));
    visit.Double_Visit_With__r = visit.Double_Visit_With__c ? { Name: companion?.User?.Name || null } : null;
    visit.Start_Date__c = toIsoOrNull(request.startDateTime) || visit.Start_Date__c;
    visit.End_Date__c = toIsoOrNull(request.endDateTime) || visit.End_Date__c;

    if (Array.isArray(request.attendees)) {
        replaceChildren(
            'Visit_Attendee__c',
            visit.Id,
            request.attendees.map((a) => {
                const seed = accountSeed(a.accountId);
                return {
                    attributes: { type: 'Visit_Attendee__c' },
                    Id: a.id && String(a.id).length >= 15 ? a.id : newId('a0T'),
                    Visit__c: visit.Id,
                    Account__c: a.accountId,
                    Account__r: {
                        Name: a.accountName || seed?.name || null,
                        Specialty_1__c: a.specialty || seed?.specialty || null,
                        RecordType: seed ? { ...recordTypeOf(seed) } : null
                    },
                    CreatedDate: now
                };
            })
        );
    }
    if (Array.isArray(request.products)) {
        const messages = [];
        const details = request.products
            .filter((p) => p?.productId)
            .map((p, i) => {
                const seed = productById(p.productId);
                const id = newId('a0P');
                (p.messages || []).forEach((m) => {
                    messages.push({
                        attributes: { type: 'Visit_Product_Message__c' },
                        Id: newId('a0M'),
                        Visit__c: visit.Id,
                        Visit_Product_Detail__c: id,
                        Topic__c: m.topic,
                        Sentiment__c: m.sentiment,
                        Response__c: m.response || null,
                        CreatedDate: now
                    });
                });
                return {
                    attributes: { type: 'Visit_Product_Detail__c' },
                    Id: id,
                    Visit__c: visit.Id,
                    Product2__c: p.productId,
                    Product2__r: seed ? productRef(seed) : { Name: p.productName || null },
                    Display_Order__c: p.displayOrder || i + 1,
                    Detail_Type__c: p.detailType || 'Detail',
                    Notes__c: p.notes || '',
                    CreatedDate: now
                };
            });
        replaceChildren('Visit_Product_Detail__c', visit.Id, details);
        replaceChildren('Visit_Product_Message__c', visit.Id, messages);
        visit.Products_Discussed__c = details.map((d) => d.Product2__r?.Name).filter(Boolean).join('; ') || null;
    }
    if (Array.isArray(request.samples)) {
        replaceChildren(
            'Visit_Sample__c',
            visit.Id,
            request.samples
                .filter((s) => s?.productId)
                .map((s) => {
                    const seed = productById(s.productId);
                    const attendee = findRow('Visit_Attendee__c', s.visitAttendeeId);
                    return {
                        attributes: { type: 'Visit_Sample__c' },
                        Id: newId('a0S'),
                        Visit__c: visit.Id,
                        Product2__c: s.productId,
                        Product2__r: seed ? productRef(seed) : { Name: s.productName || null },
                        Visit_Attendee__c: s.visitAttendeeId || null,
                        Visit_Attendee__r: attendee ? { Account__r: { Name: attendee.Account__r?.Name } } : null,
                        Quantity__c: Number(s.quantity) || 0,
                        Lot_Number__c: s.lotNumber || null,
                        Sample_Inventory__c: s.sampleInventoryId || null,
                        CreatedDate: now
                    };
                })
        );
    }
    return visit;
}

/** /planner/v1/outbox: applies call reports and CLM actions queued by the shell and player. */
function handleOutbox(body) {
    const actions = Array.isArray(body?.actions) ? body.actions : [];
    const sessionIdByClientKey = {};
    actions.forEach((action) => {
        try {
            switch (action?.actionType) {
                case 'SAVE_CALL_REPORT':
                    applyCallReport(JSON.parse(action.callReportJson || '{}'));
                    break;
                case 'START_SESSION': {
                    const row = startSession(action.visitId, action.presentationId);
                    if (action.clientSessionKey) {
                        clientSessionMap.set(action.clientSessionKey, row.Id);
                        sessionIdByClientKey[action.clientSessionKey] = row.Id;
                    }
                    break;
                }
                case 'LOG_SLIDE_EVENT':
                    logSlide(sessionFor(action.clientSessionKey), action.sequenceId, action.dwellSeconds);
                    break;
                case 'SAVE_MESSAGE_RESPONSES':
                    saveResponses(sessionFor(action.clientSessionKey), JSON.parse(action.responsesJson || '[]'));
                    break;
                case 'COMPLETE_SESSION':
                    completeSession(sessionFor(action.clientSessionKey));
                    break;
                case 'CANCEL_SESSION':
                    completeSession(sessionFor(action.clientSessionKey), 'Cancelled');
                    break;
                default:
                    break;
            }
        } catch (_err) {
            /* demo outbox never fails an action */
        }
    });
    return {
        failedClientKeys: [],
        errorMessages: actions.map(() => null),
        visitIdByClientKey: {},
        sessionIdByClientKey,
        coachingIdByClientKey: {}
    };
}

// ---------------------------------------------------------------- sObject REST writes

const WRITABLE = new Set([
    'Store_Check__c',
    'Store_Check_Line__c',
    'Visit_Order__c',
    'Visit_Order_Line__c',
    'Visit__c',
    'ContentVersion'
]);

function decorate(object, record) {
    if (object === 'Store_Check_Line__c' && record.Product__c) {
        record.Product__r = { Name: productById(record.Product__c)?.name || null };
    }
    if (object === 'Visit_Order_Line__c' && record.Product2__c) {
        record.Product2__r = { Name: productById(record.Product2__c)?.name || null };
    }
    if (object === 'Visit_Order__c' && !record.Name) {
        record.Name = `ORD-DEMO-${record.Id.slice(-4)}`;
    }
    return record;
}

function createRecord(object, fields) {
    const t = tables();
    if (object === 'ContentVersion') {
        const versionId = newId('068');
        if (fields.FirstPublishLocationId) {
            const fileName = String(fields.PathOnClient || 'photo.jpg');
            t.ContentDocumentLink.push({
                attributes: { type: 'ContentDocumentLink' },
                Id: newId('06A'),
                ContentDocumentId: newId('069'),
                LinkedEntityId: fields.FirstPublishLocationId,
                ContentDocument: {
                    Title: fields.Title || 'Store check photo',
                    FileExtension: (fileName.split('.').pop() || 'jpg').toLowerCase(),
                    LatestPublishedVersionId: versionId
                },
                SystemModstamp: new Date().toISOString()
            });
        }
        return versionId;
    }
    const prefix = { Store_Check__c: 'a0K', Store_Check_Line__c: 'a0L', Visit_Order__c: 'a0O', Visit_Order_Line__c: 'a0R' }[object] || 'a0X';
    const record = decorate(object, {
        attributes: { type: object },
        Id: newId(prefix),
        ...fields,
        CreatedDate: new Date().toISOString()
    });
    t[object].push(record);
    return record.Id;
}

/** DELETE never reaches fixtures, so a header PATCH (always followed by fresh lines) resets lines. */
function updateRecord(object, id, fields) {
    const t = tables();
    const row = findRow(object, id);
    if (!row) return;
    Object.assign(row, fields);
    decorate(object, row);
    if (object === 'Store_Check__c') {
        t.Store_Check_Line__c = t.Store_Check_Line__c.filter((line) => !sameId(line.Store_Check__c, id));
    }
    if (object === 'Visit_Order__c') {
        t.Visit_Order_Line__c = t.Visit_Order_Line__c.filter((line) => !sameId(line.Visit_Order__c, id));
    }
}

function handleSObject(path, method, body) {
    const match = /^\/services\/data\/v[\d.]+\/sobjects\/([A-Za-z0-9_]+)(?:\/([A-Za-z0-9]+))?\/?$/.exec(path);
    if (!match) return undefined;
    const [, object, id] = match;
    const fields = body && typeof body === 'object' ? body : {};
    if (method === 'GET' && id && tables()[object]) {
        const row = findRow(object, id);
        return row ? clone(row) : undefined;
    }
    if (!WRITABLE.has(object)) return undefined;
    if (method === 'POST' && !id && object !== 'Visit__c') {
        return { id: createRecord(object, fields), success: true, errors: [] };
    }
    if (method === 'PATCH' && id) {
        updateRecord(object, id, fields);
        return undefined;
    }
    return undefined;
}

// ---------------------------------------------------------------- Class Engine

const CLASS_TARGETS = [
    { id: 'ce-class-a', classCode: 'A', targetMonthlyVisits: 4, listPercentage: 30 },
    { id: 'ce-class-b', classCode: 'B', targetMonthlyVisits: 2, listPercentage: 40 },
    { id: 'ce-class-c', classCode: 'C', targetMonthlyVisits: 1, listPercentage: 30 }
];
const PROMO_WEIGHTS = [35, 15, 30, 20];
const SPECIALTY_FOCUS = [
    ['Cardiology', 45],
    ['Internal Medicine', 25],
    ['Endocrinology', 15],
    ['Pharmacy', 10],
    ['General Practice', 5]
];
const DAILY_VISIT_RATE = 8;

const ceState = { cycles: new Map(), ratings: new Map() };

function currentQuarter() {
    const now = new Date();
    return `Q${Math.floor(now.getMonth() / 3) + 1}-${now.getFullYear()}`;
}

function promoProducts() {
    return DEMO_PRODUCTS.filter((p) => p.type !== 'Sample').map((p, j) => ({
        p,
        weight: PROMO_WEIGHTS[j] ?? 10
    }));
}

function ratingFor(accountIndex, productIndex, accountId, productId) {
    const key = `${accountId}|${productId}`;
    if (!ceState.ratings.has(key)) {
        const potential = 20 + ((accountIndex * 37 + productIndex * 17) % 60);
        const share = 0.2 + ((accountIndex * 13 + productIndex * 7) % 60) / 100;
        const salesPotential = 30 + ((accountIndex * 23 + productIndex * 11) % 70);
        ceState.ratings.set(key, {
            rxPotential: potential,
            rxPenetration: Math.round(potential * share),
            salesPotential,
            salesPenetration: Math.round(salesPotential * (0.15 + ((accountIndex + productIndex * 3) % 50) / 100))
        });
    }
    return ceState.ratings.get(key);
}

function cycleFor(quarter) {
    if (!ceState.cycles.has(quarter)) {
        const n = ceState.cycles.size + 1;
        ceState.cycles.set(quarter, {
            id: seedId('a0Y', n),
            quarter,
            status: 'Draft',
            chosen: new Map(),
            classes: null
        });
    }
    return ceState.cycles.get(quarter);
}

function rankClasses(scores) {
    const ranked = scores.slice().sort((a, b) => b.score - a.score);
    const out = new Map();
    const aCut = Math.round(ranked.length * 0.3);
    const bCut = aCut + Math.round(ranked.length * 0.4);
    ranked.forEach((row, i) => out.set(row.accountId, i < aCut ? 'A' : i < bCut ? 'B' : 'C'));
    return out;
}

function classifyCycle(cycle) {
    const rx = [];
    const sales = [];
    DEMO_ACCOUNTS.forEach((a, i) => {
        let rxScore = 0;
        let salesScore = 0;
        promoProducts().forEach(({ p, weight }, j) => {
            const r = ratingFor(i, j, a.id, p.id);
            rxScore += (weight / 100) * (Number(r.rxPenetration) || 0);
            salesScore += (weight / 100) * (Number(r.salesPenetration) || 0);
        });
        rx.push({ accountId: a.id, score: rxScore });
        sales.push({ accountId: a.id, score: salesScore });
    });
    const rxClasses = rankClasses(rx);
    const salesClasses = rankClasses(sales);
    cycle.classes = new Map(DEMO_ACCOUNTS.map((a) => [a.id, { rx: rxClasses.get(a.id), sales: salesClasses.get(a.id) }]));
}

function quarterMonths(quarter) {
    const match = /^Q([1-4])-(\d{4})$/.exec(quarter) || [];
    const q = Number(match[1] || 1);
    const year = Number(match[2] || new Date().getFullYear());
    return [0, 1, 2].map((k) => {
        const month = (q - 1) * 3 + k;
        const start = new Date(year, month, 1);
        const days = new Date(year, month + 1, 0).getDate();
        let working = 0;
        for (let d = 1; d <= days; d += 1) {
            const day = new Date(year, month, d).getDay();
            if (day !== 4 && day !== 5) working += 1;
        }
        const holidayDays = k === 1 ? 1 : 0;
        const leaveDays = k === 2 ? 1 : 0;
        return {
            monthStart: `${start.getFullYear()}-${String(start.getMonth() + 1).padStart(2, '0')}-01`,
            workingDays: working - holidayDays - leaveDays,
            holidayDays,
            leaveDays,
            capacityVisits: (working - holidayDays - leaveDays) * DAILY_VISIT_RATE,
            plannedVisits: 0
        };
    });
}

/** ClassEngineController page DTO, shaped from classEngineTab.js reads. */
function classEnginePage(quarterParam) {
    const quarter = /^Q[1-4]-\d{4}$/.test(quarterParam || '') ? quarterParam : currentQuarter();
    const cycle = cycleFor(quarter);
    const promo = promoProducts();
    const accounts = DEMO_ACCOUNTS.map((a, i) => {
        const classes = cycle.classes?.get(a.id);
        const rxClass = classes ? classes.rx : a.classCode;
        const chosenClass = cycle.chosen.get(a.id) || rxClass;
        const target = CLASS_TARGETS.find((c) => c.classCode === chosenClass) || CLASS_TARGETS[2];
        const rt = recordTypeOf(a);
        return {
            id: a.id,
            accountId: a.id,
            accountName: a.name,
            specialty: a.specialty,
            recordTypeDeveloperName: rt.DeveloperName,
            recordTypeName: rt.Name,
            rxClass,
            salesClass: classes ? classes.sales : null,
            chosenClass,
            gridFrequency: target.targetMonthlyVisits,
            monthFrequency: a.frequency,
            products: promo.map(({ p, weight }, j) => ({
                product2Id: p.id,
                productName: p.name,
                imageUrl: productImage(p),
                weightPercentage: weight,
                ...ratingFor(i, j, a.id, p.id)
            }))
        };
    });
    const planned = accounts.reduce((sum, row) => sum + (Number(row.monthFrequency) || 0), 0);
    return {
        territoryId: DEMO_TERRITORY.id,
        territoryName: DEMO_TERRITORY.name,
        lineTerritoryName: `${DEMO_TERRITORY.line} LINE`,
        employeeId: DEMO_USER_ID,
        employeeName: REP_NAME,
        viewerMode: 'rep',
        dailyVisitRate: DAILY_VISIT_RATE,
        cycle: {
            id: cycle.id,
            quarter,
            status: cycle.status,
            employeeId: DEMO_USER_ID,
            employeeName: REP_NAME,
            territoryId: DEMO_TERRITORY.id
        },
        reviewTerritories: [
            {
                territoryId: DEMO_TERRITORY.id,
                name: DEMO_TERRITORY.name,
                employeeId: DEMO_USER_ID,
                employeeName: 'You',
                assigned: true,
                pendingCount: 0,
                pendingQuarters: []
            }
        ],
        pendingCycles: [],
        months: quarterMonths(quarter).map((m) => ({ ...m, plannedVisits: planned })),
        classOptions: CLASS_TARGETS.map((c) => ({ label: c.classCode, value: c.classCode })),
        promoGrid: {
            lineName: `${DEMO_TERRITORY.line} promo grid · ${quarter}`,
            productWeights: promo.map(({ p, weight }) => ({
                id: `pw-${p.id}`,
                product2Id: p.id,
                productName: p.name,
                imageUrl: productImage(p),
                weightPercentage: weight
            })),
            specialtyFocus: SPECIALTY_FOCUS.map(([label, pct], i) => ({
                id: `sf-${i + 1}`,
                specialty: label,
                specialtyLabel: label,
                listPercentage: pct
            })),
            specialtyFocusTotal: SPECIALTY_FOCUS.reduce((s, [, pct]) => s + pct, 0),
            classTargeting: CLASS_TARGETS.map((c) => ({ ...c })),
            classTargetingTotal: CLASS_TARGETS.reduce((s, c) => s + c.listPercentage, 0)
        },
        accounts
    };
}

function cycleById(id) {
    return [...ceState.cycles.values()].find((c) => c.id === id) || null;
}

function applyChosen(cycle, updates) {
    (Array.isArray(updates) ? updates : []).forEach((u) => {
        const value = u?.overrideClass || u?.chosenClass;
        if (u?.accountId && value) cycle.chosen.set(u.accountId, value);
    });
}

function handleClassEngine(path, params, method, body) {
    const sub = path.replace(/^\/services\/apexrest\/class-engine\/v1\/?/, '');
    const b = body && typeof body === 'object' ? body : {};
    if (method === 'GET') {
        return sub === 'page' || sub === '' ? classEnginePage(params?.get('quarter')) : undefined;
    }
    switch (sub) {
        case 'classify': {
            const quarter = b.quarter || currentQuarter();
            classifyCycle(cycleFor(quarter));
            return classEnginePage(quarter);
        }
        case 'save-ratings': {
            const i = DEMO_ACCOUNTS.findIndex((a) => sameId(a.id, b.accountId));
            const j = promoProducts().findIndex(({ p }) => sameId(p.id, b.product2Id));
            if (i >= 0 && j >= 0) {
                const r = ratingFor(i, j, DEMO_ACCOUNTS[i].id, promoProducts()[j].p.id);
                if (b.potential !== undefined) r.rxPotential = b.potential;
                if (b.penetration !== undefined) r.rxPenetration = b.penetration;
            }
            return { ok: true };
        }
        case 'save-chosen': {
            const cycle = cycleById(b.cycleId);
            if (!cycle) return classEnginePage(currentQuarter());
            applyChosen(cycle, b.updates);
            return classEnginePage(cycle.quarter);
        }
        case 'submit':
        case 'approve':
        case 'reject': {
            const cycle = cycleById(b.cycleId) || cycleFor(b.quarter || currentQuarter());
            if (sub === 'approve') applyChosen(cycle, b.managerOverrides);
            cycle.status = { submit: 'Submitted', approve: 'Approved', reject: 'Rejected' }[sub];
            return classEnginePage(cycle.quarter);
        }
        default:
            return undefined;
    }
}

// ---------------------------------------------------------------- exports

/** JSON body for this request, or undefined if not handled. path has no query string. */
export function handle(path, params, method, body) {
    const verb = String(method || 'GET').toUpperCase();
    if (path.startsWith('/services/apexrest/clm/v1')) {
        return handleClm(path, verb, body);
    }
    if (path.startsWith('/services/apexrest/class-engine/v1')) {
        return handleClassEngine(path, params, verb, body);
    }
    if (path === '/services/apexrest/planner/v1/outbox' && verb === 'POST') {
        return handleOutbox(body);
    }
    if (path.includes('/sobjects/')) {
        return handleSObject(path, verb, body);
    }
    return undefined;
}

const ACCOUNT_QUERY = /\bFROM\s+Account\s+(WHERE\s+(Id\s*(=|IN\b)|Name\s+LIKE)|ORDER BY\s+LastModifiedDate)/i;

/** Array of SOQL records for this object, or undefined if not handled. */
export function query(objectApiName, soql) {
    const t = tables();
    switch (objectApiName) {
        case 'Account':
            return ACCOUNT_QUERY.test(soql) ? runSoql(t.Account, soql) : undefined;
        case 'ContentVersion':
            // No version rows: a contentVersionId would make the CLM cache stream VersionData
            // (binary, which the demo router cannot answer) instead of the pdf-base64 path.
            return [];
        case 'Case':
            return /\bVisit__c\s*=/.test(soql) ? [] : undefined;
        default:
            return t[objectApiName] ? runSoql(t[objectApiName], soql) : undefined;
    }
}
