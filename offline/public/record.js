import { sfCacheGet, idbPayload, idbSet } from './sfRestCache.js';
import { accountThemeFor } from './accountTypeTheme.js';

const SF_INSTANCE =
  (typeof globalThis !== 'undefined' && globalThis.PLANNER_SF_INSTANCE) ||
  (typeof localStorage !== 'undefined' && localStorage.getItem('zeta.pwa.sfInstanceUrl')) ||
  '';
const API_TOKEN =
  (typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN) ||
  (typeof localStorage !== 'undefined' && localStorage.getItem('zeta.pwa.sfAccessToken')) ||
  '';
const REST_BASE = SF_INSTANCE;
const PREFIX_CACHE_KEY = 'zeta.pwa.sobjectPrefixes';

const DEFAULT_API_VERSION = 'v62.0';
let apiVersion = DEFAULT_API_VERSION;

const describeCache = {};
let prefixMap = null;
let currentRecord = null;
let currentObject = null;
let currentDescribe = null;
let currentMode = 'flat'; // 'layout' when rendered from UI API page layout
let currentGroups = null;

function el(id) { return document.getElementById(id); }

function recordCacheKey(object, id) {
    return `entity:record:v1:${String(object || '').toLowerCase()}.${id}`;
}

function recordUiIdbKey(object, id) {
    return `entity:recordUi:v1:${String(object || '').toLowerCase()}.${id}`;
}

function describeCacheKey(object) {
    return `entity:describe:v1:${String(object || '').trim()}`;
}

async function writeIdbCache(key, data) {
    await idbSet(key, data);
}

async function readIdbCache(key) {
    return idbPayload(key);
}

function writeCache(key, data) {
    try {
        localStorage.setItem(key, JSON.stringify({
            fetchedAt: Date.now(),
            payload: data
        }));
    } catch (_err) { /* storage full */ }
}

function readCache(key) {
    try {
        const raw = localStorage.getItem(key);
        if (!raw) return null;
        return JSON.parse(raw);
    } catch (_err) { /* corrupt or unavailable */ }
    return null;
}

function setVisible(id, show) {
    const node = el(id);
    if (node) node.style.display = show ? '' : 'none';
}

function showError(msg) {
    const bar = el('record-error');
    if (!bar) return;
    if (msg) { bar.textContent = msg; bar.style.display = 'block'; }
    else { bar.style.display = 'none'; }
}

function showLoading(show) {
    setVisible('record-loading', show);
}

async function sfFetch(path, options = {}) {
    return sfCacheGet(path, { apiVersion, fresh: options.fresh === true });
}

async function getPrefixMap() {
    if (prefixMap) return prefixMap;
    try {
        const raw = localStorage.getItem(PREFIX_CACHE_KEY);
        if (raw) {
            prefixMap = JSON.parse(raw);
            return prefixMap;
        }
    } catch (_err) { /* no cache */ }

    const data = await sfFetch('/sobjects');
    const map = {};
    for (const so of data.sobjects || []) {
        if (so.keyPrefix) map[so.keyPrefix] = so.name;
    }
    prefixMap = map;
    try { localStorage.setItem(PREFIX_CACHE_KEY, JSON.stringify(map)); } catch (_err) { /* storage full */ }
    return map;
}

async function resolveObject(recordId) {
    const prefix = String(recordId).slice(0, 3).toUpperCase();
    const map = await getPrefixMap();
    return map[prefix] || null;
}

async function getDescribe(object) {
    const key = String(object).toLowerCase();
    if (describeCache[key]) return describeCache[key];
    const fromIdb = await readIdbCache(describeCacheKey(object));
    if (fromIdb) {
        describeCache[key] = fromIdb;
        return describeCache[key];
    }
    const fromStorage = readCache(`pwa_cache_record_desc.${key}`);
    if (fromStorage && fromStorage.payload) {
        describeCache[key] = fromStorage.payload;
        await writeIdbCache(describeCacheKey(object), fromStorage.payload);
        return describeCache[key];
    }
    const desc = await sfFetch(`/sobjects/${encodeURIComponent(object)}/describe`);
    describeCache[key] = desc;
    await writeIdbCache(describeCacheKey(object), desc);
    writeCache(`pwa_cache_record_desc.${key}`, desc);
    return desc;
}

function legacyRecordUiCacheKey(object, id) {
    return `pwa_cache_record_ui.${String(object || '').toLowerCase()}.${id}`;
}

// Salesforce UI API: returns record values + page layout (sections/rows in
// layout order) + field metadata in one call. Layout order mirrors what the
// user sees in Salesforce; displayValue is already formatted by the platform.
async function getRecordUi(id) {
    return sfFetch(
        `/ui-api/record-ui/${encodeURIComponent(id)}?layoutTypes=Full&modes=View`
    );
}

// Flatten a UI API layout (Full/View) into ordered sections of field items.
function extractLayoutGroups(recordUi, id) {
    const record = recordUi?.records?.[id];
    if (!record) return null;
    const object = record.apiName;
    const objInfo = recordUi.objectInfos?.[object] || { fields: {} };
    const layoutsForObj = recordUi.layouts?.[object] || {};
    const rtId = record.recordTypeId || Object.keys(layoutsForObj)[0];
    const layout = layoutsForObj?.[rtId]?.Full?.View;
    if (!layout || !Array.isArray(layout.sections)) return null;

    const groups = [];
    for (const section of layout.sections) {
        const items = [];
        for (const row of section.layoutRows || []) {
            for (const item of row.layoutItems || []) {
                for (const comp of item.layoutComponents || []) {
                    if (comp.componentType !== 'Field' || !comp.apiName) continue;
                    const apiName = comp.apiName;
                    // Person Account Name compound children are shown as separate
                    // "Account Name" rows — collapse to one readable display.
                    if (apiName === 'Salutation' || apiName === 'FirstName' || apiName === 'MiddleName' || apiName === 'LastName' || apiName === 'Suffix') {
                        continue;
                    }
                    if (!Object.prototype.hasOwnProperty.call(record.fields, apiName)) continue;
                    const objField = objInfo.fields?.[apiName];
                    let cell = record.fields[apiName];
                    // For lookups, the id field's displayValue is null; the
                    // related record's name lives on the relationship field
                    // (CreatedById -> CreatedBy, Brick_702__c -> Brick_702__r).
                    if (objField?.dataType === 'Reference' && (cell?.displayValue == null)) {
                        const relName = apiName.endsWith('__c')
                            ? apiName.slice(0, -3) + '__r'
                            : (apiName.endsWith('Id') ? apiName.slice(0, -2) : null);
                        const relCell = relName ? record.fields[relName] : null;
                        if (relCell && relCell.displayValue != null) {
                            cell = { value: cell.value, displayValue: relCell.displayValue };
                        }
                    }
                    let label = item.label || objField?.label || apiName;
                    if (apiName === 'Name' && object === 'Account') {
                        label = 'Account Name';
                    } else if (apiName === 'Name' && object === 'Time_Off_Request__c') {
                        label = 'Request Number';
                    } else if (apiName === 'Name' && /Account Name/i.test(label) && object !== 'Account') {
                        label = 'Name';
                    }
                    items.push({
                        apiName,
                        label,
                        cell,
                        dataType: objField?.dataType
                    });
                }
            }
        }
        if (items.length) {
            groups.push({ heading: section.useHeading ? section.heading : '', items });
        }
    }
    return { object, objectLabel: objInfo.label || object, record, groups };
}

function formatUiValue(dataType, cell) {
    if (!cell) return '—';
    const val = cell.value;
    const disp = cell.displayValue;
    if (val == null && disp == null) return '—';
    switch (dataType) {
        case 'Boolean':
            return val ? 'Yes' : 'No';
        case 'Reference': {
            // displayValue is the related record's name; link opens it in-app.
            const text = disp || String(val);
            return formatLink(recordHref(val), text, true);
        }
        case 'Url':
            return formatLink(String(val), disp || String(val));
        case 'Email':
            return formatLink(`mailto:${val}`, disp || String(val));
        case 'Address':
        case 'Location':
            return formatCompound(val);
        default:
            if (disp != null && disp !== '') return String(disp);
            if (val != null && typeof val === 'object') {
                if (val.firstName || val.lastName || val.salutation || val.middleName) {
                    return [val.salutation, val.firstName, val.middleName, val.lastName, val.suffix]
                        .filter((part) => part != null && String(part).trim() !== '')
                        .join(' ')
                        .trim() || '—';
                }
                return formatCompound(val);
            }
            return val != null ? String(val) : '—';
    }
}

function buildFieldInfo(describe) {
    const map = {};
    for (const f of describe.fields || []) {
        map[f.name.toLowerCase()] = f;
    }
    return map;
}

function pickTitle(record) {
    if (record.Name) return record.Name;
    if (record.FirstName || record.LastName) {
        return `${record.FirstName || ''} ${record.LastName || ''}`.trim();
    }
    if (record.Label) return record.Label;
    if (record.Title) return record.Title;
    if (record.Subject) return record.Subject;
    return record.Id;
}

function formatCompound(value) {
    if (value == null) return '—';
    if (typeof value !== 'object') return String(value);
    const parts = [];
    for (const key of ['street', 'city', 'state', 'postalCode', 'country']) {
        if (value[key] != null && value[key] !== '') parts.push(value[key]);
    }
    return parts.length ? parts.join(' · ') : '—';
}

function formatLink(href, text, sameTab) {
    const anchor = document.createElement('a');
    anchor.href = href;
    if (!sameTab) {
        anchor.target = '_blank';
        anchor.rel = 'noopener noreferrer';
    }
    anchor.className = 'record-link';
    anchor.textContent = text;
    return anchor;
}

// In-app record page for a related record (relative so it works on localhost
// and under a deploy subpath), instead of opening Salesforce.
function recordHref(id) {
    return `record.html?recordId=${encodeURIComponent(id)}`;
}

function formatValue(field, value, refName) {
    if (value == null || value === '') return '—';
    const type = field?.type;

    switch (type) {
        case 'boolean':
            return value ? 'Yes' : 'No';
        case 'datetime':
            return new Date(value).toLocaleString();
        case 'date':
            return String(value);
        case 'reference': {
            const source = String(value);
            // Prefer the related record's name; fall back to the id.
            const text = refName || source;
            return formatLink(recordHref(source), text, true);
        }
        case 'address':
            return formatCompound(value);
        case 'url':
            return formatLink(String(value), String(value));
        case 'currency':
        case 'double':
        case 'percent': {
            const num = Number(value);
            return Number.isFinite(num) ? num.toLocaleString(undefined, { maximumFractionDigits: 2 }) : String(value);
        }
        default: {
            if (typeof value === 'object') return JSON.stringify(value);
            return String(value);
        }
    }
}

// Resolve lookup ids to their record Names in one query per target object, and
// stash them on the record under the field's relationshipName so renderTable
// (and the in-app link) can show the name.
async function attachReferenceNames(record, describe) {
    const byObject = new Map(); // object -> Set(ids)
    const fieldByName = {};
    for (const f of describe.fields || []) {
        if (f.type !== 'reference' || !f.relationshipName) continue;
        const id = record[f.name];
        if (!id || typeof id !== 'string') continue;
        if (record[f.relationshipName]) continue; // already present
        const target = (f.referenceTo || []).find(Boolean)
            || (prefixMap ? prefixMap[id.slice(0, 3)] : null);
        if (!target) continue;
        fieldByName[f.name] = f;
        if (!byObject.has(target)) byObject.set(target, new Set());
        byObject.get(target).add(id);
    }
    if (!byObject.size) return;

    const nameById = {};
    await Promise.all(
        Array.from(byObject.entries()).map(async ([obj, ids]) => {
            const idList = Array.from(ids).map((v) => `'${v}'`).join(',');
            try {
                const res = await sfFetch(
                    `/query?q=${encodeURIComponent(`SELECT Id, Name FROM ${obj} WHERE Id IN (${idList})`)}`
                );
                for (const r of res.records || []) {
                    if (r.Id) nameById[r.Id] = r.Name;
                }
            } catch (_err) {
                // Object may not have a Name field — leave those as ids.
            }
        })
    );

    for (const f of Object.values(fieldByName)) {
        const id = record[f.name];
        if (nameById[id]) {
            record[f.relationshipName] = { Name: nameById[id] };
        }
    }
}

const SYSTEM_FIELD_NAMES = new Set([
    'Id',
    'CreatedById',
    'CreatedBy',
    'CreatedDate',
    'LastModifiedById',
    'LastModifiedBy',
    'LastModifiedDate',
    'SystemModstamp',
    'LastViewedDate',
    'LastReferencedDate',
    'IsDeleted',
    'RecordTypeId',
    'OwnerId',
    'Owner'
]);

const TOT_PRIMARY_FIELDS = new Set([
    'Type__c',
    'Start_Date_Time__c',
    'Start_Date__c',
    'Span_Type__c',
    'Span_Duration__c',
    'Span_Duration_Select__c',
    'Comments__c',
    'OwnerId',
    'Owner',
    'Stage__c',
    'Full_Day__c',
    'End_Date_Time__c',
    'End_Date__c',
    'Working_Day_Equivalent__c'
]);

const SPECIALTY_FIELD_RE = /^(Specialty_\d+__c|Primary_Specialty__c|Specialty__c)$/i;
const BILLING_FIELD_RE =
    /^(BillingStreet|BillingCity|BillingState|BillingPostalCode|BillingCountry|BillingAddress|BillingLatitude|BillingLongitude|BillingGeocodeAccuracy)$/;

function uiFieldValue(record, name) {
    return record?.fields?.[name]?.value;
}

function uiFieldDisplay(record, name) {
    const cell = record?.fields?.[name];
    if (!cell) return '';
    if (cell.displayValue != null && cell.displayValue !== '') return String(cell.displayValue);
    if (cell.value == null || cell.value === '') return '';
    if (typeof cell.value === 'object') return formatCompound(cell.value);
    return String(cell.value);
}

function itemText(item) {
    const formatted = formatUiValue(item.dataType, item.cell);
    return formatted instanceof Node
        ? formatted.textContent
        : String(formatted == null ? '' : formatted);
}

function isEmptyValue(text) {
    return !text || text === '—' || text === 'null';
}

function postToShell(payload) {
    if (window.parent && window.parent !== window) {
        window.parent.postMessage(payload, '*');
        return;
    }
    if (window.top && window.top !== window) {
        window.top.postMessage(payload, '*');
    }
}

function setSyncLine(text) {
    const node = el('record-sync');
    if (node) node.textContent = text || '';
}

function applyRecordTheme(theme) {
    const header = document.querySelector('.osr-record-header');
    if (!header) return;
    const themed = theme && theme.kind && theme.kind !== 'account';
    header.classList.toggle('is-themed', Boolean(themed));
    if (!themed) {
        ['--account-theme', '--account-theme-ink', '--account-theme-soft', '--account-theme-border', '--account-theme-kicker'].forEach(
            (name) => header.style.removeProperty(name)
        );
        return;
    }
    header.style.setProperty('--account-theme', theme.color);
    header.style.setProperty('--account-theme-ink', theme.ink);
    header.style.setProperty('--account-theme-soft', theme.soft);
    header.style.setProperty('--account-theme-border', theme.border);
    header.style.setProperty('--account-theme-kicker', theme.kind === 'hco' ? '#8a6200' : theme.color);
}

function paintIdentity({ kicker, title, subtitle, contact, status, avatar, avatarKind, theme }) {
    const objectBadge = el('record-object-badge');
    if (objectBadge) objectBadge.textContent = kicker || '';
    const titleEl = el('record-title');
    if (titleEl) titleEl.textContent = title || '—';
    const subtitleEl = el('record-subtitle');
    if (subtitleEl) {
        subtitleEl.textContent = subtitle || '';
        subtitleEl.hidden = !subtitle;
    }
    const contactEl = el('record-contact');
    if (contactEl) {
        contactEl.textContent = '';
        (contact || []).filter(Boolean).forEach((part) => {
            const span = document.createElement('span');
            span.textContent = part;
            contactEl.appendChild(span);
        });
        contactEl.hidden = !(contact || []).filter(Boolean).length;
    }
    const statusEl = el('record-status-pill');
    if (statusEl) {
        if (status) {
            statusEl.hidden = false;
            statusEl.textContent = status;
        } else {
            statusEl.hidden = true;
        }
    }
    applyRecordTheme(theme);
    const iconEl = el('record-icon');
    if (iconEl) {
        const glyphUrl = theme?.iconUrl || '';
        iconEl.classList.toggle('is-calendar', avatarKind === 'calendar');
        iconEl.classList.toggle('is-glyph', avatarKind === 'calendar' || avatarKind === 'glyph' || Boolean(glyphUrl));
        if (glyphUrl) {
            iconEl.innerHTML = `<img src="${glyphUrl}" alt="" />`;
        } else if (avatarKind === 'calendar') {
            iconEl.innerHTML =
                '<svg viewBox="0 0 52 52" width="22" height="22" aria-hidden="true" focusable="false"><path fill="currentColor" d="M18 8a2 2 0 0 1 2 2v2h12V10a2 2 0 1 1 4 0v2h2a4 4 0 0 1 4 4v24a4 4 0 0 1-4 4H14a4 4 0 0 1-4-4V16a4 4 0 0 1 4-4h2V10a2 2 0 0 1 2-2zm20 16H14v16h24V24zM14 16v4h24v-4H14z"/></svg>';
        } else {
            iconEl.textContent = avatar || (title || '?').trim().charAt(0).toUpperCase();
        }
    }
    const chromeTitle = title || 'Record';
    const navTitle = document.querySelector('.nav-title');
    if (navTitle) navTitle.textContent = chromeTitle;
    postToShell({ type: 'osr-record-title', title: chromeTitle, kicker });
}

function renderActions(actions) {
    const host = el('record-actions');
    if (!host) return;
    host.innerHTML = '';
    (actions || []).forEach((action) => {
        if (action.href) {
            const link = document.createElement('a');
            link.className = `osr-action${action.primary ? ' osr-action-primary' : ''}`;
            link.href = action.href;
            link.textContent = action.label;
            host.appendChild(link);
            return;
        }
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = `osr-action${action.primary ? ' osr-action-primary' : action.more ? ' osr-action-more' : ''}`;
        btn.textContent = action.label;
        if (action.onClick) btn.addEventListener('click', action.onClick);
        host.appendChild(btn);
    });
}

function buildAddressFromRecord(record) {
    const street = uiFieldDisplay(record, 'BillingStreet') || record.BillingStreet;
    const city = uiFieldDisplay(record, 'BillingCity') || record.BillingCity;
    const postal = uiFieldDisplay(record, 'BillingPostalCode') || record.BillingPostalCode;
    const country = uiFieldDisplay(record, 'BillingCountry') || record.BillingCountry;
    const lines = [];
    if (street) lines.push(String(street));
    const cityLine = [city, postal].filter(Boolean).join(' ');
    if (cityLine && country) lines.push(`${cityLine}, ${country}`);
    else if (cityLine || country) lines.push([cityLine, country].filter(Boolean).join(', '));
    return lines;
}

function collectSpecialties(items, record) {
    const values = [];
    const seen = new Set();
    const push = (value) => {
        const text = String(value || '').trim();
        if (!text || seen.has(text.toLowerCase())) return;
        seen.add(text.toLowerCase());
        values.push(text);
    };
    (items || []).forEach((item) => {
        if (SPECIALTY_FIELD_RE.test(item.apiName)) push(itemText(item));
    });
    ['Specialty_1__c', 'Specialty_2__c', 'Specialty_3__c', 'Specialty_4__c', 'Primary_Specialty__c'].forEach((name) => {
        push(uiFieldDisplay(record, name) || record[name]);
    });
    return values.filter((value) => !isEmptyValue(value));
}

function appendField(grid, label, valueNode) {
    const item = document.createElement('div');
    item.className = 'osr-field';
    const labelEl = document.createElement('div');
    labelEl.className = 'osr-field-label';
    labelEl.textContent = label;
    const valueEl = document.createElement('div');
    valueEl.className = 'osr-field-value';
    if (valueNode instanceof Node) valueEl.appendChild(valueNode);
    else valueEl.textContent = valueNode;
    item.appendChild(labelEl);
    item.appendChild(valueEl);
    grid.appendChild(item);
}

function createSection(title) {
    const section = document.createElement('section');
    section.className = 'osr-section';
    if (title) {
        const head = document.createElement('div');
        head.className = 'osr-section-head';
        const heading = document.createElement('h2');
        heading.className = 'osr-section-title';
        heading.textContent = title;
        head.appendChild(heading);
        section.appendChild(head);
    }
    const card = document.createElement('div');
    card.className = 'osr-card';
    section.appendChild(card);
    return { section, card };
}

function formatFriendlyDateTime(value) {
    if (!value) return '';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return String(value);
    return date.toLocaleString(undefined, {
        weekday: 'short',
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit'
    });
}

const TOT_PATH_GUIDANCE = {
    Draft: 'This request is still a draft. Submit it so your manager can approve it.',
    'Submitted for Approval':
        'This request is with the manager. Wait for a decision before changing the dates.',
    Approved: 'This request is approved. The dates and type shown here are what was agreed.',
    Rejected: 'This request was not approved. Correct it with your manager and submit again.'
};

function hideApprovalPath() {
    const host = el('record-path');
    if (!host) return;
    host.hidden = true;
    host.innerHTML = '';
}

function renderApprovalPath(stage) {
    const host = el('record-path');
    if (!host) return;
    const current = stage === 'Scheduled' ? 'Approved' : stage || 'Draft';
    const rejected = current === 'Rejected';
    const steps = rejected
        ? [
              { value: 'Draft', label: 'Draft' },
              { value: 'Submitted for Approval', label: 'Submitted' },
              { value: 'Rejected', label: 'Rejected' }
          ]
        : [
              { value: 'Draft', label: 'Draft' },
              { value: 'Submitted for Approval', label: 'Submitted' },
              { value: 'Approved', label: 'Approved' }
          ];
    const currentIndex = Math.max(0, steps.findIndex((step) => step.value === current));
    host.innerHTML = '';
    const list = document.createElement('ol');
    list.className = 'osr-path-track';
    list.setAttribute('aria-label', 'Approval path');
    steps.forEach((step, index) => {
        const item = document.createElement('li');
        let state = 'incomplete';
        if (index < currentIndex) state = 'is-complete';
        else if (index === currentIndex) state = rejected ? 'is-rejected' : 'is-current';
        item.className = `osr-path-step ${state === 'incomplete' ? '' : state}`.trim();
        if (index === currentIndex) item.setAttribute('aria-current', 'step');
        item.textContent = step.label;
        list.appendChild(item);
    });
    const guidance = document.createElement('p');
    guidance.className = 'osr-path-guidance';
    guidance.textContent = TOT_PATH_GUIDANCE[current] || TOT_PATH_GUIDANCE.Draft;
    host.append(list, guidance);
    host.hidden = false;
}

function formatTotSpan(record) {
    const spanType = uiFieldDisplay(record, 'Span_Type__c');
    const duration =
        uiFieldDisplay(record, 'Span_Duration_Select__c') ||
        uiFieldDisplay(record, 'Span_Duration__c') ||
        uiFieldDisplay(record, 'Working_Day_Equivalent__c');
    if (duration && spanType) {
        const unit = /hour/i.test(spanType) ? (Number(duration) === 1 ? 'hour' : 'hours') : /day/i.test(spanType) ? (Number(duration) === 1 ? 'day' : 'days') : '';
        return unit ? `${duration} ${unit}` : `${duration} · ${spanType}`;
    }
    return duration || spanType || '';
}

function renderIdentityFromUi(uiGroups, id) {
    const record = uiGroups.record;
    const object = uiGroups.object;
    const rtName = record.recordTypeInfo?.name || '';
    const name =
        uiFieldDisplay(record, 'Name') ||
        `${uiFieldValue(record, 'FirstName') || ''} ${uiFieldValue(record, 'LastName') || ''}`.trim() ||
        id;
    const subtype =
        uiFieldDisplay(record, 'Subtype__c') ||
        uiFieldDisplay(record, 'Professional_Designation__c') ||
        (/person|hcp|doctor/i.test(rtName) ? 'Doctor' : rtName);
    const specialty = uiFieldDisplay(record, 'Specialty_1__c') || uiFieldDisplay(record, 'Primary_Specialty__c');
    const tier = uiFieldDisplay(record, 'Classification__c') || uiFieldDisplay(record, 'Tier__c');
    const phone =
        uiFieldDisplay(record, 'Phone') ||
        uiFieldDisplay(record, 'PersonMobilePhone') ||
        uiFieldDisplay(record, 'Maps_Phone_Number__c');
    const email = uiFieldDisplay(record, 'PersonEmail') || uiFieldDisplay(record, 'Email') || uiFieldDisplay(record, 'Maps_Email__c');
    const address = buildAddressFromRecord(record);
    const typeValue = uiFieldDisplay(record, 'Type__c');
    const stage =
        uiFieldDisplay(record, 'Account_Stage__c') ||
        uiFieldDisplay(record, 'Stage__c') ||
        uiFieldDisplay(record, 'Status__c') ||
        uiFieldDisplay(record, 'Status');
    const startRaw = uiFieldValue(record, 'Start_Date_Time__c') || uiFieldValue(record, 'Start_Date__c');
    const startDisplay =
        formatFriendlyDateTime(startRaw) ||
        uiFieldDisplay(record, 'Start_Date_Time__c') ||
        uiFieldDisplay(record, 'Start_Date__c');

    if (object === 'Account') {
        hideApprovalPath();
        const rtDev =
            record.recordTypeInfo?.developerName ||
            record.fields?.RecordType?.value?.fields?.DeveloperName?.value ||
            '';
        const theme = accountThemeFor(rtDev, rtName);
        const kicker =
            [theme.kind === 'account' ? subtype : theme.label, specialty, tier && `Tier ${tier}`]
                .filter(Boolean)
                .join(' · ') || 'Account';
        paintIdentity({
            kicker,
            title: name,
            subtitle: '',
            contact: [address.length ? address.join(', ') : '', email].filter(Boolean),
            status: stage || undefined,
            avatar: (name || '?').trim().charAt(0).toUpperCase(),
            theme
        });
        const mapsQuery = encodeURIComponent(address.join(', ') || name);
        const actions = [
            {
                label: 'Start Visit',
                primary: true,
                onClick: () => {
                    postToShell({
                        type: 'zeta-navigate-tab',
                        apiName: 'Field_Rep_Planner',
                        accountId: id,
                        accountName: name
                    });
                    postToShell({ type: 'close-record-modal' });
                }
            },
            {
                label: 'Request',
                onClick: () => {
                    postToShell({
                        type: 'zeta-open-field-request',
                        accountId: id,
                        accountName: name
                    });
                }
            },
            {
                label: 'Order',
                onClick: () => {
                    postToShell({
                        type: 'zeta-open-field-order',
                        accountId: id,
                        accountName: name,
                        source: 'Account'
                    });
                }
            },
            phone ? { label: 'Call', href: `tel:${phone}` } : null,
            address.length ? { label: 'Directions', href: `https://maps.google.com/?q=${mapsQuery}` } : null
        ].filter(Boolean);
        renderActions(actions);
        if (document.body.classList.contains('record-embed')) {
            document.body.classList.add('hide-embedded-identity');
            postToShell({
                type: 'osr-account-identity',
                recordId: id,
                kicker,
                title: name,
                contact: [address.length ? address.join(', ') : '', email].filter(Boolean),
                status: stage || '',
                avatar: (name || '?').trim().charAt(0).toUpperCase(),
                theme: theme
                    ? {
                          kind: theme.kind,
                          color: theme.color,
                          ink: theme.ink,
                          soft: theme.soft,
                          border: theme.border,
                          iconUrl: theme.iconUrl || ''
                      }
                    : null,
                actions: actions.map((action) => ({
                    label: action.label,
                    href: action.href || '',
                    primary: Boolean(action.primary),
                    navigate:
                        action.label === 'Start Visit'
                            ? 'visit'
                            : action.label === 'Request'
                              ? 'request'
                              : ''
                }))
            });
        }
        return;
    }

    if (object === 'Time_Off_Request__c') {
        const span = formatTotSpan(record);
        paintIdentity({
            kicker: ['Time Off', name].filter(Boolean).join(' · '),
            title: typeValue || 'Time Off',
            subtitle: [startDisplay, span].filter(Boolean).join(' · '),
            contact: [],
            status: stage || 'Draft',
            avatarKind: 'calendar'
        });
        renderActions([]);
        renderApprovalPath(stage || 'Draft');
        return;
    }

    hideApprovalPath();
    paintIdentity({
        kicker: [uiGroups.objectLabel, rtName].filter(Boolean).join(' · '),
        title: typeValue || name,
        subtitle: startDisplay || '',
        contact: [],
        status: stage,
        avatar: (name || uiGroups.objectLabel || object || '?').trim().charAt(0).toUpperCase()
    });
    renderActions([]);
}

function renderRecord(record, object, describe) {
    currentMode = 'flat';
    currentGroups = null;
    currentRecord = record;
    currentObject = object;
    currentDescribe = describe;
    setVisible('record-sections', false);
    setVisible('record-table-wrap', true);
    paintIdentity({
        kicker: describe.label || object,
        title: pickTitle(record),
        subtitle: '',
        contact: [],
        status: record.Status__c || record.Stage__c || record.Status,
        avatar: (describe.label || object || '?').trim().charAt(0).toUpperCase()
    });
    renderActions([]);
    if (object === 'Time_Off_Request__c') {
        renderApprovalPath(record.Stage__c || 'Draft');
    } else {
        hideApprovalPath();
    }
    renderTable(buildFieldInfo(describe), record, describe, '');
    showError('');
    setVisible('record-result', true);
    setSyncLine('Showing record fields');
    void loadActivity(record.Id, object);
}

function renderRecordFromUi(uiGroups, id) {
    currentMode = 'layout';
    currentGroups = uiGroups.groups;
    currentRecord = uiGroups.record;
    currentObject = uiGroups.object;
    currentDescribe = null;
    const idBadge = el('record-id-badge');
    if (idBadge) {
        idBadge.textContent = id;
        idBadge.title = id;
    }
    renderIdentityFromUi(uiGroups, id);
    renderGroups(uiGroups.groups, '');
    showError('');
    setVisible('record-result', true);
    setSyncLine(navigator.onLine === false ? 'Offline · showing saved record' : 'Synced just now');
    void loadActivity(id, uiGroups.object);
}

function renderGroups(groups, filter) {
    const host = el('record-sections');
    const extraHost = el('record-all-details');
    const showAllBtn = el('record-show-all');
    setVisible('record-table-wrap', false);
    setVisible('record-sections', true);
    host.innerHTML = '';
    if (extraHost) extraHost.innerHTML = '';
    const q = String(filter || '').trim().toLowerCase();
    const record = currentRecord;
    const allItems = [];
    (groups || []).forEach((group) => {
        (group.items || []).forEach((item) => allItems.push(item));
    });

    const consumed = new Set();
    const specialties = collectSpecialties(allItems, record);
    const addressLines = buildAddressFromRecord(record);
    if (specialties.length) {
        allItems.forEach((item) => {
            if (SPECIALTY_FIELD_RE.test(item.apiName)) consumed.add(item.apiName);
        });
        const { section, card } = createSection('Specialties');
        const chips = document.createElement('div');
        chips.className = 'osr-chips';
        specialties.forEach((value) => {
            const chip = document.createElement('span');
            chip.className = 'osr-chip';
            chip.textContent = value;
            chips.appendChild(chip);
        });
        card.appendChild(chips);
        host.appendChild(section);
    }
    if (addressLines.length) {
        allItems.forEach((item) => {
            if (BILLING_FIELD_RE.test(item.apiName)) consumed.add(item.apiName);
        });
        const { section, card } = createSection('Address');
        const block = document.createElement('div');
        block.className = 'osr-address';
        addressLines.forEach((line) => {
            const row = document.createElement('div');
            row.textContent = line;
            block.appendChild(row);
        });
        const actions = document.createElement('div');
        actions.className = 'osr-address-actions';
        const maps = document.createElement('a');
        maps.className = 'osr-link';
        maps.href = `https://maps.google.com/?q=${encodeURIComponent(addressLines.join(', '))}`;
        maps.target = '_blank';
        maps.rel = 'noopener noreferrer';
        maps.textContent = 'Directions';
        const copy = document.createElement('button');
        copy.type = 'button';
        copy.className = 'osr-link';
        copy.style.background = 'transparent';
        copy.style.border = '0';
        copy.textContent = 'Copy';
        copy.addEventListener('click', () => navigator.clipboard?.writeText(addressLines.join('\n')));
        actions.append(maps, copy);
        block.appendChild(actions);
        card.appendChild(block);
        host.appendChild(section);
    }

    const primaryHeadings = new Set(['HCP Information', 'Information', 'Details', 'General', 'Time Off', 'Overview']);
    // Owner is useful on TOT primary view even though it is otherwise a system field.
    const allowOwner = currentObject === 'Time_Off_Request__c';
    const systemExtras = [];
    let primaryCount = 0;
    for (const group of groups || []) {
        const matching = [];
        for (const it of group.items || []) {
            if (it.apiName === 'Name' && currentObject !== 'Account') continue;
            if (consumed.has(it.apiName)) continue;
            if (BILLING_FIELD_RE.test(it.apiName) || SPECIALTY_FIELD_RE.test(it.apiName)) continue;
            const text = itemText(it);
            if (isEmptyValue(text)) continue;
            if (q && !`${it.label} ${it.apiName} ${text}`.toLowerCase().includes(q)) continue;
            const isSystem =
                SYSTEM_FIELD_NAMES.has(it.apiName) &&
                !(allowOwner && (it.apiName === 'OwnerId' || it.apiName === 'Owner'));
            if (isSystem) {
                systemExtras.push(it);
                continue;
            }
            matching.push(it);
        }
        if (!matching.length) continue;
        const totPrimary = matching.filter((it) => TOT_PRIMARY_FIELDS.has(it.apiName));
        const totExtra = matching.filter((it) => !TOT_PRIMARY_FIELDS.has(it.apiName));
        const useTotSplit = currentObject === 'Time_Off_Request__c' && !q;
        const primaryItems = useTotSplit ? (totPrimary.length ? totPrimary : matching) : matching;
        const extraItems = useTotSplit && totPrimary.length ? totExtra : [];
        const isPrimary =
            !group.heading ||
            primaryHeadings.has(group.heading) ||
            primaryCount === 0 ||
            currentObject === 'Time_Off_Request__c';
        const { section, card } = createSection(group.heading || (isPrimary ? 'Overview' : 'More'));
        const grid = document.createElement('div');
        grid.className = 'osr-field-grid';
        primaryItems.forEach((it) => {
            appendField(
                grid,
                it.label === 'Account Name' && currentObject !== 'Account' ? 'Name' : it.label,
                formatUiValue(it.dataType, it.cell)
            );
            primaryCount += 1;
        });
        card.appendChild(grid);
        if (isPrimary || q) host.appendChild(section);
        else if (extraHost) extraHost.appendChild(section);
        if (extraItems.length && extraHost) {
            const extra = createSection(group.heading ? `${group.heading} · more` : 'More');
            const extraGrid = document.createElement('div');
            extraGrid.className = 'osr-field-grid';
            extraItems.forEach((it) => appendField(extraGrid, it.label, formatUiValue(it.dataType, it.cell)));
            extra.card.appendChild(extraGrid);
            extraHost.appendChild(extra.section);
        }
    }

    if (systemExtras.length && extraHost && !q) {
        const seen = new Set();
        const unique = systemExtras.filter((it) => {
            if (seen.has(it.apiName)) return false;
            seen.add(it.apiName);
            return true;
        });
        const system = createSection('System details');
        const grid = document.createElement('div');
        grid.className = 'osr-field-grid';
        unique.forEach((it) => appendField(grid, it.label, formatUiValue(it.dataType, it.cell)));
        system.card.appendChild(grid);
        extraHost.appendChild(system.section);
    }

    if (showAllBtn && extraHost) {
        const hasExtra = extraHost.children.length > 0 && !q;
        showAllBtn.hidden = !hasExtra;
        extraHost.hidden = true;
        showAllBtn.onclick = () => {
            extraHost.hidden = !extraHost.hidden;
            showAllBtn.textContent = extraHost.hidden ? 'Show all details' : 'Hide extra details';
        };
    }

    if (!host.children.length) {
        const empty = document.createElement('div');
        empty.className = 'record-empty osr-card';
        empty.textContent = q ? 'No fields match the filter.' : 'No fields on this layout.';
        host.appendChild(empty);
    }
}

async function loadActivity(recordId, object) {
    const aside = el('record-activity');
    const list = el('record-activity-list');
    const tabs = el('record-tabs');
    if (!aside || !list || !recordId) return;
    list.innerHTML = '';
    const items = [];
    try {
        if (object === 'Account') {
            hideApprovalPath();
            const visits = await sfFetch(
                `/query?q=${encodeURIComponent(
                    `SELECT Id, Name, Status__c, Start_Date__c FROM Visit__c WHERE Account__c = '${recordId}' ORDER BY Start_Date__c DESC NULLS LAST LIMIT 8`
                )}`
            );
            (visits.records || []).forEach((row) => {
                items.push({
                    title: row.Name || 'Visit',
                    meta: [row.Status__c, row.Start_Date__c ? new Date(row.Start_Date__c).toLocaleString() : '']
                        .filter(Boolean)
                        .join(' · '),
                    id: row.Id,
                    object: 'Visit__c'
                });
            });
        }
        const tasks = await sfFetch(
            `/query?q=${encodeURIComponent(
                `SELECT Id, Subject, Status, ActivityDate FROM Task WHERE WhatId = '${recordId}' ORDER BY ActivityDate DESC NULLS LAST LIMIT 8`
            )}`
        );
        (tasks.records || []).forEach((row) => {
            items.push({
                title: row.Subject || 'Task',
                meta: [row.Status, row.ActivityDate].filter(Boolean).join(' · ')
            });
        });
    } catch (_err) {
        /* activity is optional offline */
    }
    if (!items.length) {
        aside.hidden = true;
        if (tabs) tabs.hidden = true;
        return;
    }
    aside.hidden = false;
    items.slice(0, 10).forEach((item) => {
        const row = document.createElement('div');
        row.className = 'osr-activity-item';
        row.innerHTML = `<span class="osr-activity-dot"></span><div><div class="osr-activity-title"></div><div class="osr-activity-meta"></div></div>`;
        row.querySelector('.osr-activity-title').textContent = item.title;
        row.querySelector('.osr-activity-meta').textContent = item.meta || '';
        if (item.id) {
            row.style.cursor = 'pointer';
            row.addEventListener('click', () => {
                window.location.href = recordHref(item.id);
            });
        }
        list.appendChild(row);
    });
    if (tabs && window.matchMedia('(max-width: 56rem)').matches) {
        tabs.hidden = false;
        tabs.querySelectorAll('.osr-tab').forEach((btn) => {
            btn.onclick = () => {
                tabs.querySelectorAll('.osr-tab').forEach((node) => node.classList.toggle('is-active', node === btn));
                const showActivity = btn.dataset.tab === 'activity';
                el('record-sections').hidden = showActivity;
                aside.hidden = !showActivity;
            };
        });
    }
}

function renderTable(fieldInfo, record, describe, filter) {
    const tbody = el('record-tbody');
    tbody.innerHTML = '';
    const q = String(filter || '').trim().toLowerCase();

    let count = 0;
    for (const f of describe.fields || []) {
        if (!Object.prototype.hasOwnProperty.call(record, f.name)) continue;
        const value = record[f.name];
        const label = String(f.label || f.name);
        if (q && !label.toLowerCase().includes(q) && !f.name.toLowerCase().includes(q)) continue;
        if (String(value).toLowerCase().includes(q) || label.toLowerCase().includes(q)) { /* keep */ }

        const tr = document.createElement('tr');
        tr.className = 'record-row';

        const tdLabel = document.createElement('td');
        tdLabel.className = 'record-cell record-cell-label';
        const labelStrong = document.createElement('span');
        labelStrong.textContent = label;
        tdLabel.appendChild(labelStrong);
        const apiName = document.createElement('span');
        apiName.className = 'record-api-name';
        apiName.textContent = f.name;
        tdLabel.appendChild(apiName);
        tr.appendChild(tdLabel);

        const tdValue = document.createElement('td');
        tdValue.className = 'record-cell record-cell-value';
        // For lookups, surface the related record's Name (when the SOQL fetched
        // the relationship, e.g. Account__r.Name) instead of the raw id.
        let refName;
        if (f.type === 'reference' && f.relationshipName) {
            const rel = record[f.relationshipName];
            if (rel && typeof rel === 'object') {
                refName = rel.Name || rel.Label || rel.Title || rel.Subject;
            }
        }
        const formatted = formatValue(fieldInfo[f.name.toLowerCase()], value, refName);
        if (formatted instanceof Node) {
            tdValue.appendChild(formatted);
        } else {
            tdValue.textContent = formatted;
        }
        tr.appendChild(tdValue);

        tbody.appendChild(tr);
        count += 1;
    }

    if (count === 0) {
        const tr = document.createElement('tr');
        const td = document.createElement('td');
        td.colSpan = 2;
        td.className = 'record-empty';
        td.textContent = q ? 'No fields match the filter.' : 'No fields returned for this record.';
        tr.appendChild(td);
        tbody.appendChild(tr);
    }
}

async function loadRecord(recordId, objectName) {
    const id = String(recordId || '').trim();
    if (!id) {
        showError('Enter a record ID.');
        setVisible('record-result', false);
        return;
    }

    if (!/^[a-zA-Z0-9]{15,18}$/.test(id)) {
        showError('That does not look like a Salesforce record ID.');
        setVisible('record-result', false);
        return;
    }

    let object = String(objectName || '').trim();
    if (!object) {
        showLoading(true);
        showError('');
        setVisible('record-result', false);
        try {
            object = await resolveObject(id);
        } catch (err) {
            showLoading(false);
            showError(err?.message || 'Unable to detect the object for this ID.');
            return;
        }
        if (!object) {
            showLoading(false);
            showError('Could not auto-detect the object for this record ID. Enter the object API name (e.g. Account) manually.');
            return;
        }
    }

    showLoading(true);
    showError('');
    const cacheKey = recordCacheKey(object, id);
    const uiCacheKey = recordUiIdbKey(object, id);
    const cachedUi = (await readIdbCache(uiCacheKey)) || (() => {
        const legacy = readCache(legacyRecordUiCacheKey(object, id));
        return legacy && legacy.payload ? legacy.payload : null;
    })();
    const cached = (await readIdbCache(cacheKey)) || (() => {
        const legacy = readCache(`pwa_cache_record.${String(object || '').toLowerCase()}.${id}`);
        return legacy && legacy.payload ? legacy.payload : null;
    })();

    // Prefer the cached page-layout view while the network request runs.
    let paintedFromCache = false;
    if (cachedUi) {
        try {
            const groups = extractLayoutGroups(cachedUi, id);
            if (groups) {
                renderRecordFromUi(groups, id);
                paintedFromCache = true;
                showLoading(false);
            }
        } catch (_e) { /* fall through */ }
    } else if (cached && cached.record) {
        try {
            const cachedDesc =
                (await readIdbCache(describeCacheKey(object))) ||
                (readCache(`pwa_cache_record_desc.${String(object).toLowerCase()}`) || {}).payload;
            renderRecord(
                cached.record,
                object,
                cachedDesc || { label: object, fields: [] }
            );
            paintedFromCache = true;
            showLoading(false);
        } catch (_renderErr) { /* fall through to network */ }
    }

    // Primary path: UI API page layout (order/sections mirror Salesforce).
    try {
        const recordUi = await sfFetch(
            `/ui-api/record-ui/${encodeURIComponent(id)}?layoutTypes=Full&modes=View`,
            { fresh: true }
        );
        const groups = extractLayoutGroups(recordUi, id);
        if (!groups) throw new Error('No page layout returned for this record.');
        await writeIdbCache(uiCacheKey, recordUi);
        writeCache(legacyRecordUiCacheKey(object, id), recordUi);
        renderRecordFromUi(groups, id);
        showError('');
        return;
    } catch (layoutErr) {
        // Fallback: raw sObject describe dump (all accessible fields).
        try {
            const [record, describe] = await Promise.all([
                sfFetch(`/sobjects/${encodeURIComponent(object)}/${encodeURIComponent(id)}`, {
                    fresh: true
                }),
                getDescribe(object)
            ]);
            // The sObject row returns lookup ids only; resolve their names so
            // reference fields show the related record name, not the raw id.
            await attachReferenceNames(record, describe);
            await writeIdbCache(cacheKey, { record, object });
            writeCache(`pwa_cache_record.${String(object || '').toLowerCase()}.${id}`, { record, object });
            renderRecord(record, object, describe);
            showError('');
        } catch (err) {
            if (paintedFromCache) {
                showError(`Showing cached copy — ${err?.message || 'network unavailable.'}`);
            } else {
                showError(err?.message || layoutErr?.message || 'Unable to load the record.');
            }
        }
    } finally {
        showLoading(false);
    }
}

function setupFilter() {
    const filter = el('record-filter');
    if (!filter) return;
    filter.addEventListener('input', () => {
        if (currentMode === 'layout' && currentGroups) {
            renderGroups(currentGroups, filter.value);
        } else if (currentRecord && currentDescribe) {
            renderTable(buildFieldInfo(currentDescribe), currentRecord, currentDescribe, filter.value);
        }
    });
}

function setupForm() {
    const form = el('record-form');
    const idInput = el('record-id');
    const objectInput = el('record-object');
    if (!form || !idInput) return;
    form.addEventListener('submit', (event) => {
        event.preventDefault();
        loadRecord(idInput.value, objectInput.value);
    });
}

function setupQueryParams() {
    const params = new URLSearchParams(window.location.search);
    const version = params.get('apiVersion');
    if (version && /^v\d+\.\d+$/.test(version)) {
        apiVersion = version;
        const versionBadge = el('record-version');
        if (versionBadge) versionBadge.textContent = version;
    }
    const recordId = params.get('recordId');
    const object = params.get('object');
    if (recordId && (object === 'Visit__c' || object === 'Visit')) {
        const payload = { type: 'open-visit-call', recordId };
        if (window.parent && window.parent !== window) {
            window.parent.postMessage(payload, '*');
            return;
        }
        if (window.top && window.top !== window) {
            window.top.postMessage(payload, '*');
            return;
        }
        if (window.opener && !window.opener.closed) {
            window.opener.postMessage(payload, '*');
            window.close();
            return;
        }
        return;
    }
    if (recordId) {
        const idInput = el('record-id');
        const objectInput = el('record-object');
        if (idInput) idInput.value = recordId;
        if (objectInput && object) objectInput.value = object;
        loadRecord(recordId, object);
    }
}

function init() {
    const backBtn = el('btn-back');
    const embed = new URLSearchParams(window.location.search).get('embed') === '1';
    if (embed) {
        document.body.classList.add('record-embed');
    }
    if (backBtn) {
        backBtn.addEventListener('click', () => {
            if (embed && window.parent && window.parent !== window) {
                window.parent.postMessage({ type: 'close-record-modal' }, '*');
                return;
            }
            window.location.href = '/';
        });
    }
    setupForm();
    setupFilter();
    setupQueryParams();
}

document.addEventListener('DOMContentLoaded', init);