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
let searchTerm = '';
let sortField = null;
let sortDir = 'asc';
let currentPage = 1;

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

function sortKey(object) {
    return `zeta.pwa.listSort.${object || ''}`;
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
    const info = fieldByName(currentDescribe, fieldName);
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
        const info = fieldByName(currentDescribe, name);
        const formatted = formatCell(info, record[name]);
        if (formatted && formatted !== '—' && formatted.toLowerCase().includes(query)) return true;
        const raw = record[name];
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
            (a, b) => compareValues(sortField, a[sortField], b[sortField]) * dir
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
    let text = '';
    if (!total) {
        text = 'No records.';
    } else if (query) {
        text = `${shown} matching of ${total}`;
    } else {
        text = `${total} record${total === 1 ? '' : 's'}`;
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
    if (label) label.textContent = `${start}–${end} of ${shown} · Page ${currentPage} of ${pages}`;
    if (prev) prev.disabled = currentPage <= 1;
    if (next) next.disabled = currentPage >= pages;
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
    dateField = pickDateField(describe, object);
    const displayFields = pickDisplayFields(describe);
    const selectFields = ['Id', ...displayFields];
    if (kanbanField && !selectFields.includes(kanbanField)) selectFields.push(kanbanField);
    dateFieldsFromDescribe(describe).forEach((field) => {
        if (!selectFields.includes(field.name)) selectFields.push(field.name);
    });

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
    currentPage = 1;
    restoreSort(object);
    renderCurrentView();
    setVisible('list-result', true);
    showError('');
    return records.length;
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
        const info = fieldByName(currentDescribe, name);
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
    renderCurrentView();
}

function setView(nextView) {
    if (nextView === 'calendar') {
        openCalendarFieldPicker();
        return;
    }
    currentView = nextView || 'table';
    currentPage = 1;
    try {
        localStorage.setItem(`zeta.pwa.listView.${currentObject || ''}`, currentView);
    } catch (_err) {
        /* ignore */
    }
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
        next.addEventListener('click', () => {
            const rows = visibleRecords();
            if (currentPage < totalPagesFor(rows.length)) {
                currentPage += 1;
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
    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' && picker && !picker.hidden) {
            closeCalendarFieldPicker();
        }
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
    setupSearchAndPager();
    setupCalendarPicker();
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
        if (currentView === 'calendar' && !dateField) {
            openCalendarFieldPicker();
        }
    } catch (err) {
        showError(err?.message || 'Query failed.');
    } finally {
        showLoading(false);
    }
}

document.addEventListener('DOMContentLoaded', init);
