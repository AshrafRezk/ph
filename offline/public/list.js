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

let apiVersion = DEFAULT_API_VERSION;
const describeCache = {};
let currentObject = null;
let currentRecords = [];
let currentFields = [];
let currentDescribe = null;
let titleField = 'Name';
let kanbanField = null;
let dateField = null;
let currentView = 'table';

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

function absoluteSfUrl(path) {
    const base = String(REST_BASE).replace(/\/$/, '');
    if (!path) return base;
    if (/^https?:\/\//i.test(path)) return path;
    if (path.startsWith('/services/')) return `${base}${path}`;
    const suffix = path.startsWith('/') ? path : `/${path}`;
    return `${base}/services/data/${apiVersion}${suffix}`;
}

async function sfFetch(path) {
    if (!API_TOKEN) {
        throw new Error('Not signed in. Open the app, sign in with Salesforce, then try again.');
    }
    const url = absoluteSfUrl(path);
    try {
        const proxied = await fetch('/.netlify/functions/sf-api', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
            body: JSON.stringify({
                url,
                method: 'GET',
                authorization: `Bearer ${API_TOKEN}`
            })
        });
        if (proxied.ok) return proxied.json();
        if (proxied.status === 401) {
            throw new Error('Session expired. Sign in again in the main app.');
        }
    } catch (err) {
        if (err && err.message && err.message.includes('Session expired')) throw err;
    }
    const resp = await fetch(url, {
        method: 'GET',
        headers: {
            Accept: 'application/json',
            Authorization: `Bearer ${API_TOKEN}`
        }
    });
    if (resp.status === 401) {
        throw new Error('Session expired. Sign in again in the main app.');
    }
    if (!resp.ok) {
        let detail = `HTTP ${resp.status}`;
        try {
            const err = await resp.json();
            const first = Array.isArray(err) ? err[0] : err;
            detail = first?.message || detail;
        } catch (_err) {
            /* keep status */
        }
        throw new Error(detail);
    }
    return resp.json();
}

async function getDescribe(object) {
    const key = String(object).toLowerCase();
    if (describeCache[key]) return describeCache[key];
    const fromStorage = readCache(`pwa_cache_record_desc.${key}`);
    if (fromStorage && fromStorage.payload) {
        describeCache[key] = fromStorage.payload;
    } else {
        const desc = await sfFetch(`/sobjects/${encodeURIComponent(object)}/describe`);
        describeCache[key] = desc;
        try {
            localStorage.setItem(
                `pwa_cache_record_desc.${key}`,
                JSON.stringify({ savedAt: Date.now(), payload: desc })
            );
        } catch (_err) {
            /* ignore */
        }
    }
    return describeCache[key];
}

function fieldByName(describe, name) {
    return (describe.fields || []).find((field) => field.name === name);
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

function pickDateField(describe) {
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

function openRecord(id, object) {
    if (!id) return;
    if (object === 'Visit__c' && window.parent && window.parent !== window) {
        window.parent.postMessage({ type: 'open-visit-call', recordId: id }, '*');
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

async function runQuery(object) {
    const describe = await getDescribe(object);
    titleField = pickTitleField(describe);
    kanbanField = pickKanbanField(describe);
    dateField = pickDateField(describe);
    const displayFields = pickDisplayFields(describe);
    const selectFields = ['Id', ...displayFields];
    if (kanbanField && !selectFields.includes(kanbanField)) selectFields.push(kanbanField);
    if (dateField && !selectFields.includes(dateField)) selectFields.push(dateField);

    const soql = `SELECT ${selectFields.join(', ')} FROM ${object} LIMIT 200`;
    const data = await sfFetch(`/query?q=${encodeURIComponent(soql)}`);
    const records = [...(data.records || [])];
    let next = data.nextRecordsUrl;
    const seen = new Set(records.map((row) => row.Id));
    while (next && records.length < 1000) {
        const nxt = await sfFetch(next);
        for (const row of nxt.records || []) {
            if (row.Id && seen.has(row.Id)) continue;
            if (row.Id) seen.add(row.Id);
            records.push(row);
        }
        next = nxt.nextRecordsUrl;
    }

    currentObject = object;
    currentRecords = records;
    currentFields = displayFields;
    currentDescribe = describe;
    renderCurrentView();
    setVisible('list-result', true);
    showError('');
    return records.length;
}

function renderCurrentView() {
    const stage = el('list-stage');
    if (!stage) return;
    stage.innerHTML = '';
    document.querySelectorAll('.list-view-btn').forEach((btn) => {
        btn.classList.toggle('is-active', btn.dataset.view === currentView);
    });
    if (currentView === 'kanban') renderKanban(stage);
    else if (currentView === 'calendar') renderCalendar(stage);
    else if (currentView === 'cards') renderCards(stage);
    else renderTable(stage);
}

function renderTable(stage) {
    const wrap = document.createElement('div');
    wrap.className = 'list-table-wrap';
    const table = document.createElement('table');
    table.className = 'list-table';
    const thead = document.createElement('thead');
    const headRow = document.createElement('tr');
    currentFields.forEach((name) => {
        const th = document.createElement('th');
        const info = fieldByName(currentDescribe, name);
        th.textContent = (info && info.label) || name;
        headRow.appendChild(th);
    });
    thead.appendChild(headRow);
    const tbody = document.createElement('tbody');
    if (!currentRecords.length) {
        const empty = document.createElement('tr');
        const td = document.createElement('td');
        td.colSpan = currentFields.length;
        td.className = 'list-empty';
        td.textContent = 'No records returned.';
        empty.appendChild(td);
        tbody.appendChild(empty);
    } else {
        currentRecords.forEach((record) => {
            const tr = document.createElement('tr');
            tr.className = 'list-row';
            bindRecordOpener(tr, record);
            currentFields.forEach((name) => {
                const td = document.createElement('td');
                td.className = 'list-cell';
                const info = fieldByName(currentDescribe, name);
                if (name === titleField) {
                    const link = document.createElement('a');
                    link.className = 'list-link';
                    link.href = '#';
                    link.textContent = titleValue(record);
                    bindRecordOpener(link, record);
                    td.appendChild(link);
                } else {
                    td.textContent = formatCell(info, record[name]);
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

function renderCards(stage) {
    const grid = document.createElement('div');
    grid.className = 'list-card-grid';
    if (!currentRecords.length) {
        grid.innerHTML = '<p class="list-empty">No records returned.</p>';
        stage.appendChild(grid);
        return;
    }
    const subtitleFields = currentFields.filter((name) => name !== titleField).slice(0, 3);
    currentRecords.forEach((record) => {
        const card = document.createElement('button');
        card.type = 'button';
        card.className = 'list-card';
        bindRecordOpener(card, record);
        const title = document.createElement('h3');
        title.textContent = titleValue(record);
        card.appendChild(title);
        subtitleFields.forEach((name) => {
            const info = fieldByName(currentDescribe, name);
            const line = document.createElement('p');
            line.className = 'list-card-meta';
            line.textContent = `${(info && info.label) || name}: ${formatCell(info, record[name])}`;
            card.appendChild(line);
        });
        grid.appendChild(card);
    });
    stage.appendChild(grid);
}

function renderKanban(stage) {
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
    currentRecords.forEach((record) => {
        const key = record[kanbanField] || '—';
        if (!buckets.has(key)) buckets.set(key, []);
        buckets.get(key).push(record);
    });
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
            card.textContent = titleValue(record);
            bindRecordOpener(card, record);
            col.appendChild(card);
        });
        board.appendChild(col);
    });
    stage.appendChild(board);
}

function renderCalendar(stage) {
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
    currentRecords.forEach((record) => {
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

function setupViewButtons() {
    document.querySelectorAll('.list-view-btn').forEach((btn) => {
        btn.addEventListener('click', () => {
            currentView = btn.dataset.view || 'table';
            try {
                localStorage.setItem(`zeta.pwa.listView.${currentObject || ''}`, currentView);
            } catch (_err) {
                /* ignore */
            }
            renderCurrentView();
        });
    });
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
    const params = new URLSearchParams(window.location.search);
    const object = params.get('object');
    if (!object) {
        showError('No object specified.');
        return;
    }
    currentView = localStorage.getItem(`zeta.pwa.listView.${object}`) || 'table';
    showLoading(true);
    try {
        await runQuery(object);
    } catch (err) {
        showError(err?.message || 'Query failed.');
    } finally {
        showLoading(false);
    }
}

document.addEventListener('DOMContentLoaded', init);
