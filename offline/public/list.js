import {
    sfCacheGet,
    idbPayload,
    idbSet,
    listPageKey,
    describeEntityKey,
    listViewsEntityKey
} from './sfRestCache.js';

const SF_INSTANCE =
    (typeof globalThis !== 'undefined' && globalThis.PLANNER_SF_INSTANCE) ||
    (typeof localStorage !== 'undefined' && localStorage.getItem('zeta.pwa.sfInstanceUrl')) ||
    '';
const API_TOKEN =
    (typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN) ||
    (typeof localStorage !== 'undefined' && localStorage.getItem('zeta.pwa.sfAccessToken')) ||
    '';
const REST_BASE = SF_INSTANCE;
const DEFAULT_API_VERSION = 'v62.0';
const KANBAN_FIELDS = ['StageName', 'Status', 'Type', 'Rating', 'Priority', 'Industry'];
const DATE_FIELDS = ['ActivityDate', 'StartDateTime', 'Due_Date__c', 'CloseDate', 'CreatedDate'];
const PAGE_SIZE = 25;
// Cached pages written before lookup names replaced id columns are ignored.
const LIST_PAGE_LAYOUT = 2;

let apiVersion = DEFAULT_API_VERSION;
const describeCache = {};
let currentObject = null;
let currentRecords = [];
let currentFields = [];
let currentDescribe = null;
let columnLabels = {};
let titleField = 'Name';
let kanbanField = null;
let dateField = null;
let currentView = 'table';
let searchTerm = '';
let sortField = null;
let sortDir = 'asc';
let currentPage = 1;
let listViews = [];
let currentListViewId = null;
let pinnedListViewIds = [];
let skipKanbanPickerOnce = false;
let nextRecordsUrl = null;
let remoteTotalSize = null;
let loadingMore = false;

function el(id) {
    return document.getElementById(id);
}

function setVisible(id, show) {
    const node = el(id);
    if (node) node.style.display = show ? '' : 'none';
}

function showError(msg) {
    const bar = el('list-error');
    if (!bar) return;
    if (msg) {
        bar.textContent = msg;
        bar.style.display = 'block';
    } else {
        bar.style.display = 'none';
    }
}

function showLoading(show) {
    setVisible('list-loading', show);
}

function readCache(key) {
    try {
        const raw = localStorage.getItem(key);
        if (!raw) return null;
        return JSON.parse(raw);
    } catch (_err) {
        return null;
    }
}

function calendarFieldKey(object) {
    return `zeta.pwa.calendarField.${object || ''}`;
}

function kanbanFieldKey(object) {
    return `zeta.pwa.kanbanField.${object || ''}`;
}

function pinnedListViewsKey(object) {
    return `zeta.pwa.pinnedListViews.${object || ''}`;
}

function lastListViewKey(object) {
    return `zeta.pwa.lastListView.${object || ''}`;
}

function sortKey(object) {
    return `zeta.pwa.listSort.${object || ''}`;
}

function readPinnedListViews(object) {
    try {
        const raw = localStorage.getItem(pinnedListViewsKey(object));
        const parsed = raw ? JSON.parse(raw) : [];
        return Array.isArray(parsed) ? parsed.map(String) : [];
    } catch (_err) {
        return [];
    }
}

function writePinnedListViews(object, ids) {
    try {
        localStorage.setItem(pinnedListViewsKey(object), JSON.stringify(ids || []));
    } catch (_err) {
        /* ignore */
    }
}

function picklistFieldsFromDescribe(describe) {
    return (describe.fields || []).filter(
        (field) => field.type === 'picklist' && field.queryable !== false
    );
}

function restoreKanbanField(describe, object) {
    try {
        const saved = localStorage.getItem(kanbanFieldKey(object));
        const savedField = saved && fieldByName(describe, saved);
        if (savedField && savedField.type === 'picklist') return saved;
    } catch (_err) {
        /* ignore */
    }
    return pickKanbanField(describe);
}

function restoreSort(object) {
    try {
        const raw = localStorage.getItem(sortKey(object));
        if (!raw) {
            sortField = null;
            sortDir = 'asc';
            return;
        }
        const parsed = JSON.parse(raw);
        sortField = parsed.field || null;
        sortDir = parsed.dir === 'desc' ? 'desc' : 'asc';
    } catch (_err) {
        sortField = null;
        sortDir = 'asc';
    }
}

function persistSort() {
    if (!currentObject) return;
    try {
        if (!sortField) {
            localStorage.removeItem(sortKey(currentObject));
            return;
        }
        localStorage.setItem(sortKey(currentObject), JSON.stringify({ field: sortField, dir: sortDir }));
    } catch (_err) {
        /* ignore */
    }
}

function absoluteSfUrl(path) {
    const base = String(REST_BASE).replace(/\/$/, '');
    if (!path) return base;
    if (/^https?:\/\//i.test(path)) return path;
    if (path.startsWith('/services/')) return `${base}${path}`;
    const suffix = path.startsWith('/') ? path : `/${path}`;
    return `${base}/services/data/${apiVersion}${suffix}`;
}

async function sfFetch(path, options = {}) {
    return sfCacheGet(path, { apiVersion, fresh: options.fresh === true });
}

async function persistListPage() {
    if (!currentObject) return;
    await idbSet(listPageKey(currentObject, currentListViewId), {
        objectApiName: currentObject,
        listViewId: currentListViewId,
        fields: currentFields,
        labels: columnLabels,
        layout: LIST_PAGE_LAYOUT,
        records: currentRecords,
        nextRecordsUrl,
        totalSize: remoteTotalSize != null ? remoteTotalSize : currentRecords.length,
        savedAt: Date.now()
    });
}

async function getDescribe(object) {
    const key = String(object).toLowerCase();
    if (describeCache[key]) return describeCache[key];
    const fromIdb = await idbPayload(describeEntityKey(object));
    if (fromIdb) {
        describeCache[key] = fromIdb;
        return fromIdb;
    }
    const fromStorage = readCache(`pwa_cache_record_desc.${key}`);
    if (fromStorage && fromStorage.payload) {
        describeCache[key] = fromStorage.payload;
        await idbSet(describeEntityKey(object), fromStorage.payload);
        return describeCache[key];
    }
    const desc = await sfFetch(`/sobjects/${encodeURIComponent(object)}/describe`);
    describeCache[key] = desc;
    await idbSet(describeEntityKey(object), desc);
    try {
        localStorage.setItem(
            `pwa_cache_record_desc.${key}`,
            JSON.stringify({ savedAt: Date.now(), payload: desc })
        );
    } catch (_err) {
        /* ignore */
    }
    return describeCache[key];
}

function fieldByName(describe, name) {
    return (describe.fields || []).find((field) => field.name === name);
}

function valueAt(record, path) {
    if (!record) return undefined;
    if (Object.prototype.hasOwnProperty.call(record, path) || !String(path).includes('.')) return record[path];
    return String(path)
        .split('.')
        .reduce((obj, key) => (obj == null ? undefined : obj[key]), record);
}

function fieldInfo(name) {
    const direct = currentDescribe && fieldByName(currentDescribe, name);
    if (direct) return direct;
    if (!String(name).includes('.')) return null;
    const rel = String(name).split('.')[0];
    const ref = (currentDescribe?.fields || []).find((field) => field.relationshipName === rel);
    const label = columnLabels[name] || (ref ? String(ref.label || rel).replace(/ ID$/, '') : rel);
    return { name, type: 'string', label };
}

/** Record ids are never useful to read; lookups show the related record's name instead. */
function readableFields(describe, fields) {
    const out = [];
    (fields || []).forEach((name) => {
        const info = describe && fieldByName(describe, name);
        if (name === 'Id' || info?.type === 'id') return;
        let resolved = name;
        if (info && info.type === 'reference') {
            if (!info.relationshipName) return;
            resolved = `${info.relationshipName}.Name`;
        }
        if (!out.includes(resolved)) out.push(resolved);
    });
    return out;
}

function pickTitleField(describe) {
    const named = (describe.fields || []).find((field) => field.nameField);
    if (named) return named.name;
    if (fieldByName(describe, 'Name')) return 'Name';
    const auto = (describe.fields || []).find((field) => field.autoNumber);
    if (auto) return auto.name;
    return 'Id';
}

function pickKanbanField(describe) {
    for (const name of KANBAN_FIELDS) {
        const field = fieldByName(describe, name);
        if (field && field.type === 'picklist') return name;
    }
    const pick = (describe.fields || []).find(
        (field) => field.type === 'picklist' && !field.restrictedPicklist && field.updateable
    );
    return pick ? pick.name : null;
}

function dateFieldsFromDescribe(describe) {
    return (describe.fields || []).filter(
        (field) =>
            (field.type === 'date' || field.type === 'datetime') &&
            field.queryable !== false
    );
}

function pickDateField(describe, object) {
    try {
        const saved = localStorage.getItem(calendarFieldKey(object));
        const savedField = saved && fieldByName(describe, saved);
        if (savedField && (savedField.type === 'date' || savedField.type === 'datetime')) {
            return saved;
        }
    } catch (_err) {
        /* ignore */
    }
    for (const name of DATE_FIELDS) {
        const field = fieldByName(describe, name);
        if (field && (field.type === 'date' || field.type === 'datetime')) return name;
    }
    const date = (describe.fields || []).find(
        (field) => field.type === 'date' || field.type === 'datetime'
    );
    return date ? date.name : null;
}

function pickDisplayFields(describe) {
    const title = pickTitleField(describe);
    const extras = ['Type', 'Status', 'StageName', 'Rating', 'Industry', 'CreatedDate', 'LastModifiedDate'];
    const fields = [title];
    extras.forEach((name) => {
        if (name !== title && fieldByName(describe, name) && !fields.includes(name)) {
            fields.push(name);
        }
    });
    if (!fields.includes('CreatedDate') && fieldByName(describe, 'CreatedDate')) {
        fields.push('CreatedDate');
    }
    return fields;
}

function titleValue(record) {
    const value = record[titleField];
    if (value != null && value !== '') return String(value);
    return record.Name || record.Id || 'Untitled';
}

function formatCell(field, value) {
    if (value == null || value === '') return '—';
    const type = field?.type;
    switch (type) {
        case 'boolean':
            return value ? 'Yes' : 'No';
        case 'datetime': {
            const d = new Date(value);
            return Number.isNaN(d.getTime()) ? String(value) : d.toLocaleString();
        }
        case 'date':
            return String(value);
        case 'currency':
        case 'double':
        case 'percent': {
            const n = Number(value);
            return Number.isFinite(n) ? n.toLocaleString(undefined, { maximumFractionDigits: 2 }) : String(value);
        }
        default:
            return typeof value === 'object' ? JSON.stringify(value) : String(value);
    }
}

function compareValues(fieldName, a, b) {
    const info = fieldInfo(fieldName);
    const av = a == null || a === '' ? null : a;
    const bv = b == null || b === '' ? null : b;
    if (av == null && bv == null) return 0;
    if (av == null) return 1;
    if (bv == null) return -1;
    const type = info?.type;
    if (type === 'date' || type === 'datetime') {
        return new Date(av).getTime() - new Date(bv).getTime();
    }
    if (type === 'currency' || type === 'double' || type === 'int' || type === 'percent' || type === 'long') {
        return Number(av) - Number(bv);
    }
    if (type === 'boolean') {
        return (av ? 1 : 0) - (bv ? 1 : 0);
    }
    return String(av).localeCompare(String(bv), undefined, { numeric: true, sensitivity: 'base' });
}

function recordMatchesSearch(record, query) {
    if (!query) return true;
    const fields = currentFields.length ? currentFields : Object.keys(record);
    for (const name of fields) {
        const info = fieldInfo(name);
        const raw = valueAt(record, name);
        const formatted = formatCell(info, raw);
        if (formatted && formatted !== '—' && formatted.toLowerCase().includes(query)) return true;
        if (raw != null && String(raw).toLowerCase().includes(query)) return true;
    }
    return String(record.Id || '')
        .toLowerCase()
        .includes(query);
}

function visibleRecords() {
    const query = searchTerm.trim().toLowerCase();
    let rows = currentRecords;
    if (query) {
        rows = rows.filter((record) => recordMatchesSearch(record, query));
    }
    if (sortField) {
        const dir = sortDir === 'desc' ? -1 : 1;
        rows = [...rows].sort(
            (a, b) => compareValues(sortField, valueAt(a, sortField), valueAt(b, sortField)) * dir
        );
    }
    return rows;
}

function totalPagesFor(count) {
    return Math.max(1, Math.ceil(count / PAGE_SIZE));
}

function pagedRecords(rows) {
    const pages = totalPagesFor(rows.length);
    if (currentPage > pages) currentPage = pages;
    if (currentPage < 1) currentPage = 1;
    const start = (currentPage - 1) * PAGE_SIZE;
    return rows.slice(start, start + PAGE_SIZE);
}

function usesPagination() {
    return currentView === 'table' || currentView === 'cards';
}

function updateCountAndPager(rows) {
    const count = el('list-count');
    const pager = el('list-pagination');
    const label = el('list-page-label');
    const prev = el('list-page-prev');
    const next = el('list-page-next');
    const total = currentRecords.length;
    const shown = rows.length;
    const query = searchTerm.trim();
    const moreHint = nextRecordsUrl ? '+' : '';
    let text = '';
    if (!total) {
        text = 'No records.';
    } else if (query) {
        text = `${shown} matching of ${total}${moreHint}`;
    } else if (remoteTotalSize != null && remoteTotalSize > total) {
        text = `${total} loaded of ${remoteTotalSize}`;
    } else {
        text = `${total}${moreHint} record${total === 1 && !moreHint ? '' : 's'}`;
    }
    if (currentView === 'calendar' && dateField) {
        const info = fieldByName(currentDescribe, dateField);
        text += ` · calendar by ${(info && info.label) || dateField}`;
    }
    if (count) count.textContent = text;

    const paginate = usesPagination() && shown > 0;
    if (pager) pager.hidden = !paginate;
    if (!paginate) return;
    const pages = totalPagesFor(shown);
    const start = (currentPage - 1) * PAGE_SIZE + 1;
    const end = Math.min(currentPage * PAGE_SIZE, shown);
    if (label) label.textContent = `${start}–${end} of ${shown}${moreHint} · Page ${currentPage} of ${pages}${nextRecordsUrl ? '+' : ''}`;
    if (prev) prev.disabled = currentPage <= 1;
    if (next) next.disabled = currentPage >= pages && !nextRecordsUrl;
}

function openRecord(id, object) {
    if (!id) return;
    const isVisit = object === 'Visit__c' || object === 'Visit' || currentObject === 'Visit__c';
    if (isVisit) {
        const payload = { type: 'open-visit-call', recordId: id };
        if (window.parent && window.parent !== window) {
            window.parent.postMessage(payload, '*');
            return;
        }
        if (window.top && window.top !== window) {
            window.top.postMessage(payload, '*');
            return;
        }
        window.dispatchEvent(new CustomEvent('zeta-navigate-record', {
            detail: { recordId: id, objectApiName: 'Visit__c', actionName: 'view' }
        }));
        return;
    }
    if (window.parent && window.parent !== window) {
        window.parent.postMessage(
            { type: 'open-record-modal', recordId: id, objectApiName: object || currentObject },
            '*'
        );
        return;
    }
    window.location.href = `/record.html?embed=1&recordId=${encodeURIComponent(id)}&object=${encodeURIComponent(object || '')}`;
}

function bindRecordOpener(node, record) {
    node.addEventListener('click', (event) => {
        event.preventDefault();
        event.stopPropagation();
        openRecord(record.Id, currentObject);
    });
}

async function fetchListViews(object) {
    const cached = await idbPayload(listViewsEntityKey(object));
    if (Array.isArray(cached) && cached.length) {
        listViews = cached
            .filter((row) => row && (row.id || row.Id) && (row.label || row.Label))
            .map((row) => ({
                id: String(row.id || row.Id),
                label: row.label || row.Label,
                developerName: row.developerName || row.label || row.Label,
                soqlCompatible: row.soqlCompatible !== false
            }));
        // Refresh in background via cache-first helper.
        sfFetch(`/sobjects/${encodeURIComponent(object)}/listviews`)
            .then(async (data) => {
                const rows = Array.isArray(data?.listviews) ? data.listviews : [];
                const mapped = rows
                    .filter((row) => row && row.id && row.label)
                    .map((row) => ({
                        id: String(row.id),
                        label: row.label,
                        developerName: row.developerName || row.label,
                        soqlCompatible: row.soqlCompatible !== false
                    }));
                if (mapped.length) {
                    await idbSet(listViewsEntityKey(object), mapped);
                    listViews = mapped;
                    renderListViewSelect();
                }
            })
            .catch(() => {});
        return listViews;
    }
    try {
        const data = await sfFetch(`/sobjects/${encodeURIComponent(object)}/listviews`);
        const rows = Array.isArray(data?.listviews) ? data.listviews : [];
        const mapped = rows
            .filter((row) => row && row.id && row.label)
            .map((row) => ({
                id: String(row.id),
                label: row.label,
                developerName: row.developerName || row.label,
                soqlCompatible: row.soqlCompatible !== false
            }));
        await idbSet(listViewsEntityKey(object), mapped);
        return mapped;
    } catch (err) {
        console.warn('[List] listviews failed', err);
        return [];
    }
}

function flattenListViewRows(rows) {
    return (rows || []).map((row) => {
        if (row && row.columns) {
            const flat = { Id: row.id || row.Id };
            (row.columns || []).forEach((col) => {
                const key = col.fieldNameOrPath || col.fieldApiName;
                if (key) flat[key] = col.value;
            });
            return flat.Id ? flat : row;
        }
        return row;
    });
}

function applyLoadedPage(object, describe, displayFields, records, nextUrl, totalSize) {
    currentObject = object;
    currentRecords = records;
    currentFields = readableFields(describe, displayFields);
    currentDescribe = describe;
    nextRecordsUrl = nextUrl || null;
    remoteTotalSize = totalSize != null ? totalSize : records.length;
    currentPage = 1;
    restoreSort(object);
    if (sortField && !currentFields.includes(sortField)) sortField = null;
    renderListViewSelect();
    renderKanbanFieldSelect();
    renderCurrentView();
    setVisible('list-result', true);
    showError('');
    void persistListPage();
    return records.length;
}

async function loadListViewResults(object, listViewId) {
    const describe = await getDescribe(object);
    titleField = pickTitleField(describe);
    kanbanField = restoreKanbanField(describe, object);
    dateField = pickDateField(describe, object);

    let records = [];
    let displayFields = pickDisplayFields(describe);
    nextRecordsUrl = null;
    remoteTotalSize = null;

    // Paint from IndexedDB immediately when available.
    const cachedPage = await idbPayload(listPageKey(object, listViewId || null));
    columnLabels = {};
    if (
        cachedPage &&
        cachedPage.layout === LIST_PAGE_LAYOUT &&
        Array.isArray(cachedPage.records) &&
        cachedPage.records.length
    ) {
        columnLabels = cachedPage.labels || {};
        displayFields = Array.isArray(cachedPage.fields) && cachedPage.fields.length
            ? cachedPage.fields
            : displayFields;
        applyLoadedPage(
            object,
            describe,
            displayFields,
            cachedPage.records,
            cachedPage.nextRecordsUrl || null,
            cachedPage.totalSize
        );
        // Quiet background refresh of first page only.
        void refreshFirstPageQuiet(object, listViewId, describe, displayFields);
        return cachedPage.records.length;
    }

    if (listViewId) {
        try {
            const desc = await sfFetch(
                `/sobjects/${encodeURIComponent(object)}/listviews/${encodeURIComponent(listViewId)}/describe`
            );
            const cols = [];
            (Array.isArray(desc?.columns) ? desc.columns : []).forEach((c) => {
                const name = c && !c.hidden && (c.fieldNameOrPath || c.fieldApiName || c.name);
                if (!name) return;
                cols.push(name);
                if (c.label) columnLabels[name] = c.label;
            });
            const readable = readableFields(describe, cols);
            if (readable.length) displayFields = readable.slice(0, 8);
            const results = await sfFetch(
                `/sobjects/${encodeURIComponent(object)}/listviews/${encodeURIComponent(listViewId)}/results?limit=${PAGE_SIZE}`
            );
            records = flattenListViewRows(Array.isArray(results?.records) ? results.records : []);
            remoteTotalSize = results?.size != null ? results.size : records.length;
            nextRecordsUrl = null;
            if (records.length >= PAGE_SIZE) {
                // List-view API has no nextRecordsUrl; further pages use SOQL offset.
                nextRecordsUrl = `__offset__:${PAGE_SIZE}`;
            }
        } catch (err) {
            console.warn('[List] list view results failed; falling back to SOQL', err);
            listViewId = null;
            currentListViewId = null;
        }
    }

    if (!listViewId) {
        const selectFields = ['Id', ...displayFields];
        if (kanbanField && !selectFields.includes(kanbanField)) selectFields.push(kanbanField);
        dateFieldsFromDescribe(describe).forEach((field) => {
            if (!selectFields.includes(field.name)) selectFields.push(field.name);
        });
        const unique = [...new Set(selectFields)];
        const soql = `SELECT ${unique.join(', ')} FROM ${object} LIMIT ${PAGE_SIZE}`;
        const data = await sfFetch(`/query?q=${encodeURIComponent(soql)}`);
        records = [...(data.records || [])];
        nextRecordsUrl = data.nextRecordsUrl || null;
        remoteTotalSize = data.totalSize != null ? data.totalSize : records.length;
    } else if (kanbanField) {
        const missing = records.some((r) => r && r[kanbanField] === undefined);
        if (missing && records.length && records[0].Id) {
            try {
                const ids = records
                    .map((r) => r.Id)
                    .filter(Boolean)
                    .slice(0, PAGE_SIZE)
                    .map((id) => `'${String(id).replace(/'/g, "\\'")}'`)
                    .join(',');
                if (ids) {
                    const enrich = await sfFetch(
                        `/query?q=${encodeURIComponent(
                            `SELECT Id, ${kanbanField} FROM ${object} WHERE Id IN (${ids})`
                        )}`
                    );
                    const byId = new Map((enrich.records || []).map((r) => [r.Id, r]));
                    records = records.map((r) => {
                        const extra = byId.get(r.Id);
                        return extra ? { ...r, [kanbanField]: extra[kanbanField] } : r;
                    });
                }
            } catch (_err) {
                /* ignore enrich failures */
            }
        }
    }

    return applyLoadedPage(object, describe, displayFields, records, nextRecordsUrl, remoteTotalSize);
}

async function refreshFirstPageQuiet(object, listViewId, describe, displayFields) {
    try {
        let records = [];
        let nextUrl = null;
        let totalSize = null;
        const fields = readableFields(describe, displayFields);
        if (listViewId) {
            const results = await sfFetch(
                `/sobjects/${encodeURIComponent(object)}/listviews/${encodeURIComponent(listViewId)}/results?limit=${PAGE_SIZE}`,
                { fresh: true }
            );
            records = flattenListViewRows(Array.isArray(results?.records) ? results.records : []);
            totalSize = results?.size != null ? results.size : records.length;
            nextUrl = records.length >= PAGE_SIZE ? `__offset__:${PAGE_SIZE}` : null;
        } else {
            const selectFields = ['Id', ...fields];
            if (kanbanField && !selectFields.includes(kanbanField)) selectFields.push(kanbanField);
            const unique = [...new Set(selectFields)];
            const soql = `SELECT ${unique.join(', ')} FROM ${object} LIMIT ${PAGE_SIZE}`;
            const data = await sfFetch(`/query?q=${encodeURIComponent(soql)}`, { fresh: true });
            records = [...(data.records || [])];
            nextUrl = data.nextRecordsUrl || null;
            totalSize = data.totalSize != null ? data.totalSize : records.length;
        }
        if (!records.length) return;
        // Merge: keep already-loaded extra pages if still same object/view.
        if (currentObject === object && currentListViewId === listViewId && currentRecords.length > records.length) {
            const byId = new Map(records.map((r) => [r.Id, r]));
            currentRecords = currentRecords.map((r) => byId.get(r.Id) || r);
            const seen = new Set(currentRecords.map((r) => r.Id));
            records.forEach((r) => {
                if (r.Id && !seen.has(r.Id)) currentRecords.unshift(r);
            });
        } else if (currentObject === object && currentListViewId === listViewId) {
            currentRecords = records;
            nextRecordsUrl = nextUrl;
            remoteTotalSize = totalSize;
            renderCurrentView();
        }
        await persistListPage();
    } catch (_err) {
        /* keep cached paint */
    }
}

async function fetchNextRemotePage() {
    if (loadingMore || !nextRecordsUrl || !currentObject) return false;
    loadingMore = true;
    try {
        let rows = [];
        if (String(nextRecordsUrl).startsWith('__offset__:')) {
            const offset = Number(String(nextRecordsUrl).slice('__offset__:'.length)) || currentRecords.length;
            const selectFields = ['Id', ...currentFields];
            if (kanbanField && !selectFields.includes(kanbanField)) selectFields.push(kanbanField);
            const unique = [...new Set(selectFields)];
            const soql = `SELECT ${unique.join(', ')} FROM ${currentObject} LIMIT ${PAGE_SIZE} OFFSET ${offset}`;
            const data = await sfFetch(`/query?q=${encodeURIComponent(soql)}`, { fresh: true });
            rows = [...(data.records || [])];
            nextRecordsUrl = rows.length >= PAGE_SIZE ? `__offset__:${offset + rows.length}` : null;
            if (data.totalSize != null) remoteTotalSize = data.totalSize;
        } else {
            const data = await sfFetch(nextRecordsUrl, { fresh: true });
            rows = [...(data.records || [])];
            nextRecordsUrl = data.nextRecordsUrl || null;
            if (data.totalSize != null) remoteTotalSize = data.totalSize;
        }
        if (!rows.length) {
            nextRecordsUrl = null;
            return false;
        }
        const seen = new Set(currentRecords.map((r) => r.Id));
        rows.forEach((row) => {
            if (row.Id && seen.has(row.Id)) return;
            if (row.Id) seen.add(row.Id);
            currentRecords.push(row);
        });
        await persistListPage();
        return true;
    } catch (err) {
        console.warn('[List] next page failed', err);
        return false;
    } finally {
        loadingMore = false;
    }
}

async function runQuery(object) {
    pinnedListViewIds = readPinnedListViews(object);
    listViews = await fetchListViews(object);
    let preferred = null;
    try {
        preferred = localStorage.getItem(lastListViewKey(object));
    } catch (_err) {
        preferred = null;
    }
    if (preferred && listViews.some((v) => v.id === preferred)) {
        currentListViewId = preferred;
    } else if (pinnedListViewIds.length) {
        const pinnedHit = listViews.find((v) => pinnedListViewIds.includes(v.id));
        currentListViewId = pinnedHit ? pinnedHit.id : null;
    } else {
        currentListViewId = null;
    }
    return loadListViewResults(object, currentListViewId);
}

function sortListViewsForUi(views, pinnedIds) {
    const pinned = new Set(pinnedIds || []);
    return [...(views || [])].sort((a, b) => {
        const ap = pinned.has(a.id) ? 0 : 1;
        const bp = pinned.has(b.id) ? 0 : 1;
        if (ap !== bp) return ap - bp;
        return String(a.label || '').localeCompare(String(b.label || ''));
    });
}

function renderListViewSelect() {
    const select = el('list-sf-view');
    const pinBtn = el('list-pin-view');
    if (!select) return;
    const ordered = sortListViewsForUi(listViews, pinnedListViewIds);
    select.innerHTML = '';
    const allOpt = document.createElement('option');
    allOpt.value = '';
    allOpt.textContent = 'All records (recent)';
    select.appendChild(allOpt);
    ordered.forEach((view) => {
        const option = document.createElement('option');
        option.value = view.id;
        const pinned = pinnedListViewIds.includes(view.id);
        option.textContent = pinned ? `★ ${view.label}` : view.label;
        select.appendChild(option);
    });
    select.value = currentListViewId || '';
    if (pinBtn) {
        const isPinned = currentListViewId && pinnedListViewIds.includes(currentListViewId);
        pinBtn.textContent = isPinned ? '★' : '☆';
        pinBtn.setAttribute('aria-pressed', isPinned ? 'true' : 'false');
        pinBtn.disabled = !currentListViewId;
        pinBtn.classList.toggle('is-pinned', !!isPinned);
        pinBtn.title = isPinned ? 'Unpin this list view' : 'Pin / favourite this list view';
    }
}

function renderKanbanFieldSelect() {
    const wrap = el('list-kanban-field-wrap');
    const select = el('list-kanban-field');
    if (!wrap || !select || !currentDescribe) return;
    const fields = picklistFieldsFromDescribe(currentDescribe);
    select.innerHTML = '';
    fields.forEach((field) => {
        const option = document.createElement('option');
        option.value = field.name;
        option.textContent = field.label || field.name;
        select.appendChild(option);
    });
    if (kanbanField && fields.some((f) => f.name === kanbanField)) {
        select.value = kanbanField;
    } else if (fields[0]) {
        select.value = fields[0].name;
        kanbanField = fields[0].name;
    }
    wrap.hidden = currentView !== 'kanban' || !fields.length;
}

function recordsForView() {
    const rows = visibleRecords();
    if (usesPagination()) {
        const pages = totalPagesFor(Math.max(rows.length, 1));
        if (currentPage > pages) currentPage = pages;
        if (currentPage < 1) currentPage = 1;
    }
    updateCountAndPager(rows);
    return usesPagination() ? pagedRecords(rows) : rows;
}

function renderCurrentView() {
    const stage = el('list-stage');
    if (!stage) return;
    stage.innerHTML = '';
    document.querySelectorAll('.list-view-btn').forEach((btn) => {
        btn.classList.toggle('is-active', btn.dataset.view === currentView);
    });
    const rows = recordsForView();
    if (currentView === 'kanban') renderKanban(stage, rows);
    else if (currentView === 'calendar') renderCalendar(stage, rows);
    else if (currentView === 'cards') renderCards(stage, rows);
    else renderTable(stage, rows);
}

function toggleSort(fieldName) {
    if (sortField === fieldName) {
        sortDir = sortDir === 'asc' ? 'desc' : 'asc';
    } else {
        sortField = fieldName;
        sortDir = 'asc';
    }
    currentPage = 1;
    persistSort();
    renderCurrentView();
}

function renderTable(stage, records) {
    const wrap = document.createElement('div');
    wrap.className = 'list-table-wrap';
    const table = document.createElement('table');
    table.className = 'list-table';
    const thead = document.createElement('thead');
    const headRow = document.createElement('tr');
    currentFields.forEach((name) => {
        const th = document.createElement('th');
        const info = fieldInfo(name);
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'list-sort-btn';
        if (sortField === name) {
            btn.classList.add(sortDir === 'desc' ? 'is-desc' : 'is-asc');
            btn.setAttribute('aria-sort', sortDir === 'desc' ? 'descending' : 'ascending');
        } else {
            btn.setAttribute('aria-sort', 'none');
        }
        const label = document.createElement('span');
        label.textContent = (info && info.label) || name;
        btn.appendChild(label);
        const mark = document.createElement('span');
        mark.className = 'list-sort-mark';
        mark.setAttribute('aria-hidden', 'true');
        mark.textContent = sortField === name ? (sortDir === 'desc' ? '↓' : '↑') : '↕';
        btn.appendChild(mark);
        btn.addEventListener('click', (event) => {
            event.preventDefault();
            event.stopPropagation();
            toggleSort(name);
        });
        th.appendChild(btn);
        headRow.appendChild(th);
    });
    thead.appendChild(headRow);
    const tbody = document.createElement('tbody');
    if (!records.length) {
        const empty = document.createElement('tr');
        const td = document.createElement('td');
        td.colSpan = currentFields.length;
        td.className = 'list-empty';
        td.textContent = searchTerm.trim() ? 'No records match this search.' : 'No records returned.';
        empty.appendChild(td);
        tbody.appendChild(empty);
    } else {
        records.forEach((record) => {
            const tr = document.createElement('tr');
            tr.className = 'list-row';
            bindRecordOpener(tr, record);
            currentFields.forEach((name) => {
                const td = document.createElement('td');
                td.className = 'list-cell';
                const info = fieldInfo(name);
                if (name === titleField) {
                    const link = document.createElement('a');
                    link.className = 'list-link';
                    link.href = '#';
                    link.textContent = titleValue(record);
                    bindRecordOpener(link, record);
                    td.appendChild(link);
                } else {
                    td.textContent = formatCell(info, valueAt(record, name));
                }
                tr.appendChild(td);
            });
            tbody.appendChild(tr);
        });
    }
    table.appendChild(thead);
    table.appendChild(tbody);
    wrap.appendChild(table);
    stage.appendChild(wrap);
}

function renderCards(stage, records) {
    const grid = document.createElement('div');
    grid.className = 'list-card-grid';
    if (!records.length) {
        grid.innerHTML = `<p class="list-empty">${searchTerm.trim() ? 'No records match this search.' : 'No records returned.'}</p>`;
        stage.appendChild(grid);
        return;
    }
    const subtitleFields = currentFields.filter((name) => name !== titleField).slice(0, 3);
    records.forEach((record) => {
        const card = document.createElement('button');
        card.type = 'button';
        card.className = 'list-card';
        bindRecordOpener(card, record);
        const title = document.createElement('h3');
        title.textContent = titleValue(record);
        card.appendChild(title);
        subtitleFields.forEach((name) => card.appendChild(metaLine(record, name)));
        grid.appendChild(card);
    });
    stage.appendChild(grid);
}

function metaLine(record, name) {
    const info = fieldInfo(name);
    const line = document.createElement('p');
    line.className = 'list-card-meta';
    const label = document.createElement('span');
    label.className = 'list-card-meta-label';
    label.textContent = `${(info && info.label) || name}: `;
    line.appendChild(label);
    line.appendChild(document.createTextNode(formatCell(info, valueAt(record, name))));
    return line;
}

function renderKanban(stage, records) {
    const field = kanbanField && fieldByName(currentDescribe, kanbanField);
    if (!field) {
        stage.innerHTML = '<p class="list-empty">No grouping picklist is available for a Kanban view.</p>';
        return;
    }
    const values = (field.picklistValues || [])
        .filter((entry) => entry.active !== false)
        .map((entry) => entry.value);
    const buckets = new Map();
    values.forEach((value) => buckets.set(value, []));
    buckets.set('—', []);
    records.forEach((record) => {
        const key = record[kanbanField] || '—';
        if (!buckets.has(key)) buckets.set(key, []);
        buckets.get(key).push(record);
    });
    const detailFields = currentFields.filter((name) => name !== titleField && name !== kanbanField).slice(0, 5);
    const board = document.createElement('div');
    board.className = 'list-kanban';
    buckets.forEach((rows, key) => {
        if (!rows.length && key === '—') return;
        const col = document.createElement('section');
        col.className = 'list-kanban-col';
        const heading = document.createElement('h3');
        heading.textContent = `${key} (${rows.length})`;
        col.appendChild(heading);
        rows.forEach((record) => {
            const card = document.createElement('button');
            card.type = 'button';
            card.className = 'list-kanban-card';
            const title = document.createElement('span');
            title.className = 'list-kanban-title';
            title.textContent = titleValue(record);
            card.appendChild(title);
            detailFields.forEach((name) => {
                const value = valueAt(record, name);
                if (value == null || value === '') return;
                card.appendChild(metaLine(record, name));
            });
            bindRecordOpener(card, record);
            col.appendChild(card);
        });
        board.appendChild(col);
    });
    stage.appendChild(board);
}

function renderCalendar(stage, records) {
    const field = dateField && fieldByName(currentDescribe, dateField);
    if (!field) {
        stage.innerHTML = '<p class="list-empty">No date field is available for a calendar view.</p>';
        return;
    }
    const now = new Date();
    const year = now.getFullYear();
    const month = now.getMonth();
    const first = new Date(year, month, 1);
    const startWeekday = first.getDay();
    const daysInMonth = new Date(year, month + 1, 0).getDate();
    const byDay = new Map();
    records.forEach((record) => {
        const raw = record[dateField];
        if (!raw) return;
        const d = new Date(raw);
        if (Number.isNaN(d.getTime()) || d.getMonth() !== month || d.getFullYear() !== year) return;
        const day = d.getDate();
        if (!byDay.has(day)) byDay.set(day, []);
        byDay.get(day).push(record);
    });
    const wrap = document.createElement('div');
    wrap.className = 'list-calendar';
    const heading = document.createElement('h3');
    heading.className = 'list-calendar-title';
    heading.textContent = now.toLocaleString(undefined, { month: 'long', year: 'numeric' });
    wrap.appendChild(heading);
    const grid = document.createElement('div');
    grid.className = 'list-calendar-grid';
    ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].forEach((label) => {
        const cell = document.createElement('div');
        cell.className = 'list-calendar-dow';
        cell.textContent = label;
        grid.appendChild(cell);
    });
    for (let i = 0; i < startWeekday; i += 1) {
        const pad = document.createElement('div');
        pad.className = 'list-calendar-day is-pad';
        grid.appendChild(pad);
    }
    for (let day = 1; day <= daysInMonth; day += 1) {
        const cell = document.createElement('div');
        cell.className = 'list-calendar-day';
        const num = document.createElement('span');
        num.className = 'list-calendar-num';
        num.textContent = String(day);
        cell.appendChild(num);
        (byDay.get(day) || []).forEach((record) => {
            const btn = document.createElement('button');
            btn.type = 'button';
            btn.className = 'list-calendar-item';
            btn.textContent = titleValue(record);
            bindRecordOpener(btn, record);
            cell.appendChild(btn);
        });
        grid.appendChild(cell);
    }
    wrap.appendChild(grid);
    stage.appendChild(wrap);
}

function closeCalendarFieldPicker() {
    const picker = el('calendar-field-picker');
    if (picker) picker.hidden = true;
}

function closeKanbanFieldPicker() {
    const picker = el('kanban-field-picker');
    if (picker) picker.hidden = true;
}

function openCalendarFieldPicker() {
    const fields = dateFieldsFromDescribe(currentDescribe);
    if (!fields.length) {
        dateField = null;
        currentView = 'calendar';
        try {
            localStorage.setItem(`zeta.pwa.listView.${currentObject || ''}`, currentView);
        } catch (_err) {
            /* ignore */
        }
        closeCalendarFieldPicker();
        renderKanbanFieldSelect();
        renderCurrentView();
        return;
    }
    const select = el('calendar-field-select');
    const picker = el('calendar-field-picker');
    if (!select || !picker) return;
    select.innerHTML = '';
    fields.forEach((field) => {
        const option = document.createElement('option');
        option.value = field.name;
        option.textContent = `${field.label} (${field.name})`;
        select.appendChild(option);
    });
    const preferred = dateField && fields.some((field) => field.name === dateField) ? dateField : fields[0].name;
    select.value = preferred;
    picker.hidden = false;
    select.focus();
}

function openKanbanFieldPicker() {
    const fields = picklistFieldsFromDescribe(currentDescribe);
    if (!fields.length) {
        kanbanField = null;
        currentView = 'kanban';
        try {
            localStorage.setItem(`zeta.pwa.listView.${currentObject || ''}`, currentView);
        } catch (_err) {
            /* ignore */
        }
        closeKanbanFieldPicker();
        renderKanbanFieldSelect();
        renderCurrentView();
        return;
    }
    if (skipKanbanPickerOnce || (kanbanField && fields.some((f) => f.name === kanbanField))) {
        skipKanbanPickerOnce = false;
        currentView = 'kanban';
        try {
            localStorage.setItem(`zeta.pwa.listView.${currentObject || ''}`, currentView);
        } catch (_err) {
            /* ignore */
        }
        closeKanbanFieldPicker();
        renderKanbanFieldSelect();
        renderCurrentView();
        return;
    }
    const select = el('kanban-field-select');
    const picker = el('kanban-field-picker');
    if (!select || !picker) return;
    select.innerHTML = '';
    fields.forEach((field) => {
        const option = document.createElement('option');
        option.value = field.name;
        option.textContent = `${field.label} (${field.name})`;
        select.appendChild(option);
    });
    const preferred =
        kanbanField && fields.some((field) => field.name === kanbanField)
            ? kanbanField
            : fields[0].name;
    select.value = preferred;
    picker.hidden = false;
    select.focus();
}

function applyCalendarField() {
    const select = el('calendar-field-select');
    const chosen = select && select.value;
    if (!chosen) return;
    dateField = chosen;
    try {
        localStorage.setItem(calendarFieldKey(currentObject), chosen);
        localStorage.setItem(`zeta.pwa.listView.${currentObject || ''}`, 'calendar');
    } catch (_err) {
        /* ignore */
    }
    currentView = 'calendar';
    closeCalendarFieldPicker();
    renderKanbanFieldSelect();
    renderCurrentView();
}

function applyKanbanField() {
    const select = el('kanban-field-select');
    const chosen = select && select.value;
    if (!chosen) return;
    kanbanField = chosen;
    try {
        localStorage.setItem(kanbanFieldKey(currentObject), chosen);
        localStorage.setItem(`zeta.pwa.listView.${currentObject || ''}`, 'kanban');
    } catch (_err) {
        /* ignore */
    }
    currentView = 'kanban';
    closeKanbanFieldPicker();
    renderKanbanFieldSelect();
    renderCurrentView();
}

function setView(nextView) {
    if (nextView === 'calendar') {
        openCalendarFieldPicker();
        return;
    }
    if (nextView === 'kanban') {
        openKanbanFieldPicker();
        return;
    }
    currentView = nextView || 'table';
    currentPage = 1;
    try {
        localStorage.setItem(`zeta.pwa.listView.${currentObject || ''}`, currentView);
    } catch (_err) {
        /* ignore */
    }
    renderKanbanFieldSelect();
    renderCurrentView();
}

function setupViewButtons() {
    document.querySelectorAll('.list-view-btn').forEach((btn) => {
        btn.addEventListener('click', () => {
            setView(btn.dataset.view || 'table');
        });
    });
}

function setupSearchAndPager() {
    const search = el('list-search');
    if (search) {
        search.addEventListener('input', () => {
            searchTerm = search.value;
            currentPage = 1;
            renderCurrentView();
        });
    }
    const prev = el('list-page-prev');
    const next = el('list-page-next');
    if (prev) {
        prev.addEventListener('click', () => {
            if (currentPage > 1) {
                currentPage -= 1;
                renderCurrentView();
            }
        });
    }
    if (next) {
        next.addEventListener('click', async () => {
            const rows = visibleRecords();
            const pages = totalPagesFor(rows.length);
            if (currentPage < pages) {
                currentPage += 1;
                renderCurrentView();
                return;
            }
            if (nextRecordsUrl) {
                next.disabled = true;
                const loaded = await fetchNextRemotePage();
                if (loaded) {
                    currentPage += 1;
                }
                renderCurrentView();
            }
        });
    }
}

function setupCalendarPicker() {
    const picker = el('calendar-field-picker');
    const cancel = el('calendar-field-cancel');
    const apply = el('calendar-field-apply');
    if (cancel) cancel.addEventListener('click', closeCalendarFieldPicker);
    if (apply) apply.addEventListener('click', applyCalendarField);
    if (picker) {
        picker.addEventListener('click', (event) => {
            if (event.target === picker) closeCalendarFieldPicker();
        });
    }
}

function setupKanbanPicker() {
    const picker = el('kanban-field-picker');
    const cancel = el('kanban-field-cancel');
    const apply = el('kanban-field-apply');
    const toolbarSelect = el('list-kanban-field');
    if (cancel) cancel.addEventListener('click', closeKanbanFieldPicker);
    if (apply) apply.addEventListener('click', applyKanbanField);
    if (picker) {
        picker.addEventListener('click', (event) => {
            if (event.target === picker) closeKanbanFieldPicker();
        });
    }
    if (toolbarSelect) {
        toolbarSelect.addEventListener('change', () => {
            const chosen = toolbarSelect.value;
            if (!chosen) return;
            kanbanField = chosen;
            try {
                localStorage.setItem(kanbanFieldKey(currentObject), chosen);
            } catch (_err) {
                /* ignore */
            }
            renderCurrentView();
        });
    }
}

function setupListViewControls() {
    const select = el('list-sf-view');
    const pinBtn = el('list-pin-view');
    if (select) {
        select.addEventListener('change', async () => {
            currentListViewId = select.value || null;
            try {
                if (currentListViewId) {
                    localStorage.setItem(lastListViewKey(currentObject), currentListViewId);
                } else {
                    localStorage.removeItem(lastListViewKey(currentObject));
                }
            } catch (_err) {
                /* ignore */
            }
            showLoading(true);
            try {
                await loadListViewResults(currentObject, currentListViewId);
            } catch (err) {
                showError(err?.message || 'Could not load list view.');
            } finally {
                showLoading(false);
            }
        });
    }
    if (pinBtn) {
        pinBtn.addEventListener('click', () => {
            if (!currentListViewId) return;
            if (pinnedListViewIds.includes(currentListViewId)) {
                pinnedListViewIds = pinnedListViewIds.filter((id) => id !== currentListViewId);
            } else {
                pinnedListViewIds = [currentListViewId, ...pinnedListViewIds.filter((id) => id !== currentListViewId)];
            }
            writePinnedListViews(currentObject, pinnedListViewIds);
            renderListViewSelect();
        });
    }
}

function setupQueryParams() {
    const params = new URLSearchParams(window.location.search);
    const version = params.get('apiVersion');
    if (version && /^v\d+\.\d+$/.test(version)) {
        apiVersion = version;
    }
}

async function init() {
    setupQueryParams();
    setupViewButtons();
    setupSearchAndPager();
    setupCalendarPicker();
    setupKanbanPicker();
    setupListViewControls();
    document.addEventListener('keydown', (event) => {
        if (event.key !== 'Escape') return;
        closeCalendarFieldPicker();
        closeKanbanFieldPicker();
    });
    const params = new URLSearchParams(window.location.search);
    const object = params.get('object');
    if (!object) {
        showError('No object specified.');
        return;
    }
    currentView = localStorage.getItem(`zeta.pwa.listView.${object}`) || 'table';
    if (currentView === 'kanban') skipKanbanPickerOnce = true;
    showLoading(true);
    try {
        await runQuery(object);
        if (currentView === 'calendar' && !dateField) {
            openCalendarFieldPicker();
        } else if (currentView === 'kanban' && !kanbanField) {
            openKanbanFieldPicker();
        }
    } catch (err) {
        showError(err?.message || 'Query failed.');
    } finally {
        showLoading(false);
    }
}

document.addEventListener('DOMContentLoaded', init);
