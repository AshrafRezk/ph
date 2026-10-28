import { accountThemeFor } from './accountTypeTheme.js';

const REST_BASE = (typeof globalThis !== 'undefined' && globalThis.PLANNER_REST_BASE) || '';
const API_TOKEN = (typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN) || '';
const SF_INSTANCE = (typeof globalThis !== 'undefined' && globalThis.PLANNER_SF_INSTANCE) || '';

const PAGE_SIZE = 10;
const MAP_PAGE_SIZE = 50;
const RISK_COLORS = { High: '#ba0517', Med: '#fe9339', Low: '#2e844a' };
const TYPE_COLORS = { pharmacy: '#176935', hco: '#e0a800', hcp: '#3f7de5', account: '#3f7de5' };
const SEARCH_DEBOUNCE_MS = 350;
const SCOPE_BOTH = 'both';
const SCOPE_IN = 'in';
const SCOPE_OUT = 'out';
const SORT_BY_NAME = 'name';
const SORT_BY_SCORE = 'agentforceScore';
const SORT_BY_CLASS = 'classification';
const SORT_DIR_DESC = 'desc';

let state = {
    rows: [],
    viewMode: 'list',
    scope: SCOPE_BOTH,
    searchTerm: '',
    recordType: 'All',
    classification: 'All',
    sortBy: SORT_BY_SCORE,
    sortDirection: SORT_DIR_DESC,
    currentPage: 1,
    totalCount: 0,
    inPlanCount: 0,
    outPlanCount: 0,
    behindPaceCount: 0,
    recordTypeCounts: [],
    isLoading: false,
    errorMessage: '',
    hasCachedData: false,
    syncStatus: 'idle',
    mapEligibleCount: 0,
    mapRows: [],
    mapCurrentPage: 1,
    selectedAccountId: null,
    collections: []
};

let searchDebounce = null;

function getCacheKey() {
    return `accounts.${state.scope}.${state.searchTerm}.${state.recordType}.${state.classification}.${state.sortBy}.${state.sortDirection}.${state.currentPage}`;
}

function getMapCacheKey() {
    return `accounts.map.${state.scope}.${state.searchTerm}.${state.recordType}.${state.classification}.${state.sortBy}.${state.sortDirection}.${state.mapCurrentPage}`;
}

function el(id) { return document.getElementById(id); }

function showSyncChip(status, label) {
    const chip = el('sync-chip');
    if (!chip) return;
    if (status === 'idle') { chip.style.display = 'none'; return; }
    chip.style.display = 'inline-flex';
    chip.className = `sync-chip sync-chip-${status}`;
    chip.textContent = label;
}

function showError(msg) {
    const bar = el('error-banner');
    if (!bar) return;
    if (msg) { bar.textContent = msg; bar.style.display = 'block'; }
    else { bar.style.display = 'none'; }
}

async function readCache(key) {
    try {
        const raw = localStorage.getItem('pwa_cache_' + key);
        if (raw) return JSON.parse(raw);
    } catch (_) { /* no cache */ }
    return null;
}

async function writeCache(key, data) {
    try {
        localStorage.setItem('pwa_cache_' + key, JSON.stringify(data));
    } catch (_) { /* storage full */ }
}

async function fetchAccounts(params, isMap = false) {
    const path = '/services/apexrest/planner/v1/accounts-tab/page';
    const body = {
        scope: params.scope,
        searchTerm: params.searchTerm || null,
        recordTypeDeveloperName: params.recordType !== 'All' ? params.recordType : null,
        classification: params.classification !== 'All' ? params.classification : null,
        sortBy: params.sortBy,
        sortDirection: params.sortDirection,
        offset: (params.page - 1) * (isMap ? MAP_PAGE_SIZE : PAGE_SIZE),
        pageSize: isMap ? MAP_PAGE_SIZE : PAGE_SIZE,
        monthStart: null,
        contextUserId: null,
        accountIds: null
    };
    const headers = { 'Content-Type': 'application/json', 'Accept': 'application/json' };
    if (API_TOKEN) headers['Authorization'] = `Bearer ${API_TOKEN}`;
    const url = REST_BASE ? `${REST_BASE.replace(/\/$/, '')}${path}` : path;
    const resp = await fetch(url, { method: 'POST', headers, body: JSON.stringify(body) });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    return resp.json();
}

async function fetchMapPoints(params) {
    const path = '/services/apexrest/planner/v1/accounts-tab/map-points';
    const body = {
        scope: params.scope,
        searchTerm: params.searchTerm || null,
        recordTypeDeveloperName: params.recordType !== 'All' ? params.recordType : null,
        classification: params.classification !== 'All' ? params.classification : null,
        sortBy: params.sortBy,
        sortDirection: params.sortDirection,
        offset: (params.page - 1) * MAP_PAGE_SIZE,
        pageSize: MAP_PAGE_SIZE,
        monthStart: null,
        contextUserId: null,
        accountIds: null
    };
    const headers = { 'Content-Type': 'application/json', 'Accept': 'application/json' };
    if (API_TOKEN) headers['Authorization'] = `Bearer ${API_TOKEN}`;
    const url = REST_BASE ? `${REST_BASE.replace(/\/$/, '')}${path}` : path;
    const resp = await fetch(url, { method: 'POST', headers, body: JSON.stringify(body) });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    return resp.json();
}

async function loadPage() {
    state.isLoading = true;
    showError('');
    state.rows = [];
    renderList();

    const cacheKey = getCacheKey();
    const cached = await readCache(cacheKey);
    if (cached) {
        applyPageData(cached);
        state.hasCachedData = true;
        state.syncStatus = 'cached';
        showSyncChip('cached', 'Cached');
    }

    if (!navigator.onLine) {
        state.isLoading = false;
        if (!state.hasCachedData) showError('You are offline. Connect to load accounts.');
        state.syncStatus = 'offline';
        showSyncChip('offline', 'Offline');
        return;
    }

    state.syncStatus = 'updating';
    showSyncChip('updating', 'Updating…');
    try {
        const result = await fetchAccounts({
            scope: state.scope,
            searchTerm: state.searchTerm,
            recordType: state.recordType,
            classification: state.classification,
            sortBy: state.sortBy,
            sortDirection: state.sortDirection,
            page: state.currentPage
        });
        state.rows = (result?.rows || []).map(r => mapRow(r));
        state.totalCount = result?.totalCount || 0;
        state.inPlanCount = result?.inPlanCount || 0;
        state.outPlanCount = result?.outPlanCount || 0;
        state.behindPaceCount = result?.behindPaceCount || 0;
        state.recordTypeCounts = result?.recordTypeCounts || [];
        state.mapEligibleCount = result?.mapEligibleCount || 0;
        state.currentPage = result?.currentPage || state.currentPage;
        await writeCache(cacheKey, { rows: state.rows, totalCount: state.totalCount, inPlanCount: state.inPlanCount, outPlanCount: state.outPlanCount, behindPaceCount: state.behindPaceCount, recordTypeCounts: state.recordTypeCounts, mapEligibleCount: state.mapEligibleCount });
        state.hasCachedData = true;
        state.errorMessage = '';
        state.syncStatus = 'idle';
        showSyncChip('cached', 'Cached');
    } catch (err) {
        if (!state.hasCachedData) {
            showError(err?.message || 'Unable to load accounts.');
            state.syncStatus = 'offline';
            showSyncChip('offline', 'Offline');
        }
    }
    state.isLoading = false;
    renderSummary();
    renderList();
    renderPagination();
}

async function loadMapPage() {
    state.isLoading = true;
    showError('');
    state.mapRows = [];
    renderMapList();

    if (!navigator.onLine) {
        state.isLoading = false;
        if (!state.hasCachedData) showError('You are offline.');
        return;
    }

    try {
        const [pageResult, mapResult] = await Promise.all([
            fetchAccounts({ scope: state.scope, searchTerm: state.searchTerm, recordType: state.recordType, classification: state.classification, sortBy: state.sortBy, sortDirection: state.sortDirection, page: 1 }, false),
            fetchMapPoints({ scope: state.scope, searchTerm: state.searchTerm, recordType: state.recordType, classification: state.classification, sortBy: state.sortBy, sortDirection: state.sortDirection, page: state.mapCurrentPage })
        ]);
        state.totalCount = pageResult?.totalCount || 0;
        state.inPlanCount = pageResult?.inPlanCount || 0;
        state.outPlanCount = pageResult?.outPlanCount || 0;
        state.behindPaceCount = pageResult?.behindPaceCount || 0;
        state.recordTypeCounts = pageResult?.recordTypeCounts || [];
        state.mapEligibleCount = mapResult?.mapEligibleCount || 0;
        state.mapRows = (mapResult?.rows || []).map(r => mapRow(r));
        state.syncStatus = 'idle';
        showSyncChip('cached', 'Cached');
    } catch (err) {
        if (!state.hasCachedData) showError(err?.message || 'Unable to load accounts.');
        state.syncStatus = 'offline';
    }
    state.isLoading = false;
    renderSummary();
    renderMapList();
    renderMapPagination();
    drawAccountMap();
}

function mapRow(row) {
    const target = row.targetVisits;
    const actual = row.actualVisits || 0;
    const planned = row.plannedVisits || 0;
    return {
        ...row,
        reachPercentDisplay: row.reachPercent != null ? `${Math.round(Number(row.reachPercent))}%` : '—',
        callPlanLabel: target != null ? `${actual}/${target}` : '—',
        paceStatusLabel: row.paceStatusLabel || '—',
        agentforceScoreDisplay: row.agentforceScore != null ? Number(row.agentforceScore).toFixed(1) : '—',
        riskDotClass: `risk-dot-${(row.agentforceRisk || 'Low').toLowerCase()}`
    };
}

function applyPageData(data) {
    state.rows = (data.rows || []).map(r => mapRow(r));
    state.totalCount = data.totalCount || 0;
    state.inPlanCount = data.inPlanCount || 0;
    state.outPlanCount = data.outPlanCount || 0;
    state.behindPaceCount = data.behindPaceCount || 0;
    state.recordTypeCounts = data.recordTypeCounts || [];
    state.mapEligibleCount = data.mapEligibleCount || 0;
}

function renderSummary() {
    const ids = ['total-count', 'in-plan-count', 'out-plan-count', 'behind-count'];
    const vals = [state.totalCount, state.inPlanCount, state.outPlanCount, state.behindPaceCount];
    ids.forEach((id, i) => { const e = el(id); if (e) e.textContent = vals[i]; });
}

function navigateToAccount(accountId) {
    if (accountId) {
        // Open the generic UI API record view (page-layout order), same as every
        // other object. See record.js.
        window.location.href = `/record.html?object=Account&recordId=${encodeURIComponent(accountId)}`;
    }
}

function typeGlyph(theme) {
    return theme?.iconUrl
        ? `<img class="account-type-glyph" src="${theme.iconUrl}" alt="" />`
        : '';
}

function renderList() {
    const list = el('account-list');
    if (!list) return;
    if (state.rows.length === 0 && !state.isLoading) {
        list.innerHTML = '<p class="empty-state">No accounts match the current filters.</p>';
        return;
    }
    list.innerHTML = state.rows.map(r => {
        const theme = accountThemeFor(r.recordTypeDeveloperName, r.recordTypeName);
        const typeLabel = theme.kind === 'account' ? (r.recordTypeName || '') : theme.label;
        return `
        <div class="account-row" data-id="${r.accountId || ''}" style="border-left-color:${theme.color}" onclick="navigateToAccount('${r.accountId || ''}')">
            <div class="account-row-top">
                ${typeGlyph(theme)}
                <span class="account-name">${escHtml(r.accountName)}</span>
                <span class="account-classification">${escHtml(r.classification || '—')}</span>
            </div>
            <div class="account-row-sub">
                <span>${escHtml(typeLabel)}</span>
                <span>${escHtml(r.city || '')}</span>
                <span>${r.callPlanLabel}</span>
                <span class="${r.riskDotClass}"></span>
            </div>
        </div>
    `;
    }).join('');
}

function renderMapList() {
    const list = el('map-account-list');
    if (!list) return;
    const geocoded = state.mapEligibleCount || 0;
    const countEl = el('map-count');
    if (countEl) {
        if (!geocoded) {
            countEl.textContent = 'None located';
        } else if (geocoded <= MAP_PAGE_SIZE) {
            countEl.textContent = `${geocoded} located`;
        } else {
            const start = (state.mapCurrentPage - 1) * MAP_PAGE_SIZE + 1;
            const end = Math.min(state.mapCurrentPage * MAP_PAGE_SIZE, geocoded);
            countEl.textContent = `${start}–${end} of ${geocoded}`;
        }
    }
    const empty = el('map-empty');
    if (empty) empty.hidden = state.isLoading || state.mapRows.length > 0;
    if (state.mapRows.length === 0 && !state.isLoading) {
        list.innerHTML = '<li class="map-empty">No accounts with a location match these filters.</li>';
        return;
    }
    if (state.isLoading && state.mapRows.length === 0) {
        list.innerHTML = '<li class="map-empty">Loading accounts…</li>';
        return;
    }
    list.innerHTML = state.mapRows.map(r => {
        const theme = accountThemeFor(r.recordTypeDeveloperName, r.recordTypeName);
        const pinKind = theme.kind === 'account' ? 'hcp' : theme.kind;
        const typeLabel = theme.kind === 'account' ? (r.recordTypeName || 'Account') : theme.label;
        const risk = r.agentforceRisk || 'Low';
        const riskKey = String(risk).toLowerCase();
        const selected = r.accountId === state.selectedAccountId;
        const subtitle = [r.accountSubtype || typeLabel, r.city].filter(Boolean).join(' · ') || '—';
        const visits = r.targetVisits != null ? `Visits ${r.callPlanLabel}` : 'No visit target';
        return `
        <li class="map-account-item${selected ? ' map-account-item-selected' : ''}" role="option" aria-selected="${selected ? 'true' : 'false'}">
            <button type="button" class="map-account-select" data-select="${escHtml(r.accountId || '')}">
                <span class="map-account-avatar map-account-avatar-${pinKind}">
                    ${typeGlyph(theme)}
                    <span class="risk-dot-${riskKey}" title="${escHtml(risk)} pace"></span>
                </span>
                <span class="map-account-copy">
                    <span class="map-account-item-top">
                        <span class="map-account-name">${escHtml(r.accountName)}</span>
                        <span class="map-account-class">${escHtml(r.classification || '—')}</span>
                    </span>
                    <span class="map-account-subtitle">${escHtml(subtitle)}</span>
                    <span class="map-account-meta">
                        <span class="map-risk-chip map-risk-chip-${riskKey}">${escHtml(risk)} pace</span>
                        <span>${escHtml(visits)}</span>
                    </span>
                </span>
            </button>
            <button type="button" class="map-account-open" data-open="${escHtml(r.accountId || '')}">Open</button>
        </li>
    `;
    }).join('');
}

function renderPagination() {
    const totalPages = Math.max(1, Math.ceil(state.totalCount / PAGE_SIZE));
    const nav = el('pagination');
    if (!nav) return;
    nav.style.display = totalPages > 1 ? 'flex' : 'none';
    const label = el('page-label');
    if (label) label.textContent = `Page ${state.currentPage} of ${totalPages}`;
    const prev = el('btn-prev');
    const next = el('btn-next');
    if (prev) prev.disabled = state.currentPage <= 1;
    if (next) next.disabled = state.currentPage >= totalPages;
}

function renderMapPagination() {
    const totalPages = Math.max(1, Math.ceil((state.mapEligibleCount || 0) / MAP_PAGE_SIZE));
    const nav = el('map-pagination');
    if (!nav) return;
    nav.classList.toggle('is-visible', totalPages > 1);
    const label = el('map-page-label');
    if (label) label.textContent = `Page ${state.mapCurrentPage} of ${totalPages}`;
    const prev = el('btn-map-prev');
    const next = el('btn-map-next');
    if (prev) prev.disabled = state.mapCurrentPage <= 1 || state.isLoading;
    if (next) next.disabled = state.mapCurrentPage >= totalPages || state.isLoading;
}

let mapInstance = null;
let mapResizeObserver = null;
const markersByAccountId = {};

function leafletNs() {
    return window.leaflet || window.L || null;
}

function pinKindFor(row) {
    const theme = accountThemeFor(row.recordTypeDeveloperName, row.recordTypeName);
    return theme.kind === 'account' ? 'hcp' : theme.kind;
}

function buildPinIcon(L, row) {
    const kind = pinKindFor(row);
    const theme = accountThemeFor(row.recordTypeDeveloperName, row.recordTypeName);
    const border = TYPE_COLORS[kind] || TYPE_COLORS.hcp;
    const risk = RISK_COLORS[row.agentforceRisk] || RISK_COLORS.Low;
    const selected = row.accountId === state.selectedAccountId;
    const glyph = theme.iconUrl
        ? `<img src="${theme.iconUrl}" alt="" style="width:16px;height:16px;object-fit:contain;display:block;" />`
        : '';
    const halo = selected
        ? `0 0 0 4px ${border}33, 0 6px 14px rgba(3,45,96,0.35)`
        : '0 2px 6px rgba(3,45,96,0.28)';
    const scale = selected ? 'transform:scale(1.12);' : '';
    return L.divIcon({
        className: 'acct-map-pin',
        html:
            `<div style="position:relative;width:34px;height:34px;border-radius:50%;background:#fff;border:2.5px solid ${border};box-shadow:${halo};display:flex;align-items:center;justify-content:center;${scale}" title="${escHtml(row.accountName || '')}">` +
            glyph +
            `<span style="position:absolute;right:-2px;bottom:-2px;width:11px;height:11px;border-radius:50%;background:${risk};border:2px solid #fff;box-sizing:border-box;"></span>` +
            '</div>',
        iconSize: [34, 34],
        iconAnchor: [17, 17],
        popupAnchor: [0, -18]
    });
}

function buildPopupHtml(row) {
    const theme = accountThemeFor(row.recordTypeDeveloperName, row.recordTypeName);
    const typeLabel = theme.kind === 'account' ? (row.recordTypeName || 'Account') : theme.label;
    const place = [row.accountSubtype || typeLabel, row.city].filter(Boolean).join(' · ') || '—';
    const plan = row.planCycleLabel === 'In' ? 'In plan' : row.planCycleLabel === 'Out' ? 'Out of plan' : '';
    const risk = row.agentforceRisk || 'Low';
    const riskColor = RISK_COLORS[risk] || RISK_COLORS.Low;
    const visits = row.targetVisits != null
        ? `${row.actualVisits || 0}/${row.targetVisits}`
        : `${row.actualVisits || 0} (no target)`;
    const score = row.agentforceScore != null ? Number(row.agentforceScore).toFixed(1) : '—';
    return `<div class="acct-popup">
        <div class="acct-popup-name">${escHtml(row.accountName || 'Account')}</div>
        <div class="acct-popup-place">${escHtml(place)}</div>
        <div class="acct-popup-row">
            <span class="acct-popup-chip">${escHtml(row.classification || '—')}</span>
            <span class="acct-popup-risk" style="color:${riskColor}">${escHtml(risk)} pace</span>
        </div>
        <div class="acct-popup-meta">${escHtml(plan)}<br/>Visits ${escHtml(visits)} · ${escHtml(row.paceStatusLabel || '—')}<br/>Score ${escHtml(score)}</div>
        <button type="button" class="acct-popup-open" data-open="${escHtml(row.accountId || '')}">Open account</button>
    </div>`;
}

function clearMapMarkers() {
    Object.keys(markersByAccountId).forEach((id) => {
        if (mapInstance) mapInstance.removeLayer(markersByAccountId[id]);
        delete markersByAccountId[id];
    });
}

function applyPinSelection() {
    const L = leafletNs();
    if (!L) return;
    Object.keys(markersByAccountId).forEach((id) => {
        const row = state.mapRows.find((item) => item.accountId === id);
        if (row) markersByAccountId[id].setIcon(buildPinIcon(L, row));
    });
}

function ensureAccountMap() {
    const L = leafletNs();
    const container = el('accounts-map');
    if (!L || !container) return null;
    if (mapInstance && container.contains(mapInstance.getContainer())) {
        return mapInstance;
    }
    if (mapInstance) {
        mapInstance.remove();
        mapInstance = null;
    }
    container.innerHTML = '';
    mapInstance = L.map(container, { zoomControl: true, scrollWheelZoom: true });
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 19,
        attribution: '&copy; OpenStreetMap'
    }).addTo(mapInstance);
    if (mapInstance.attributionControl) {
        mapInstance.attributionControl.setPrefix(false);
    }
    if (typeof ResizeObserver !== 'undefined' && !mapResizeObserver) {
        mapResizeObserver = new ResizeObserver(() => mapInstance?.invalidateSize());
        mapResizeObserver.observe(container);
    }
    mapInstance.on('popupopen', (event) => {
        const button = event.popup?.getElement()?.querySelector('.acct-popup-open');
        if (!button || button.dataset.bound === '1') return;
        button.dataset.bound = '1';
        button.addEventListener('click', () => navigateToAccount(button.dataset.open));
    });
    return mapInstance;
}

function drawAccountMap() {
    if (state.viewMode !== 'map') return;
    const map = ensureAccountMap();
    const L = leafletNs();
    if (!map || !L) return;
    clearMapMarkers();
    const bounds = [];
    state.mapRows.forEach((row) => {
        if (row.latitude == null || row.longitude == null) return;
        const latLng = [Number(row.latitude), Number(row.longitude)];
        bounds.push(latLng);
        const marker = L.marker(latLng, { icon: buildPinIcon(L, row), riseOnHover: true })
            .addTo(map)
            .bindPopup(buildPopupHtml(row), { autoPanPadding: [24, 24] });
        marker.on('click', () => {
            state.selectedAccountId = row.accountId;
            applyPinSelection();
            renderMapList();
        });
        markersByAccountId[row.accountId] = marker;
    });
    if (bounds.length === 1) map.setView(bounds[0], 14);
    else if (bounds.length) map.fitBounds(bounds, { padding: [48, 48], maxZoom: 14 });
    else map.setView([30.0444, 31.2357], 6);
    setTimeout(() => map.invalidateSize(), 80);
}

function selectMapAccount(accountId) {
    if (!accountId) return;
    state.selectedAccountId = accountId;
    renderMapList();
    applyPinSelection();
    const row = state.mapRows.find((item) => item.accountId === accountId);
    const marker = markersByAccountId[accountId];
    if (row && mapInstance && row.latitude != null && row.longitude != null) {
        mapInstance.flyTo([Number(row.latitude), Number(row.longitude)], 15, { duration: 0.6 });
    }
    if (marker) setTimeout(() => marker.openPopup(), 350);
    const card = document.querySelector(`[data-select="${CSS.escape(accountId)}"]`);
    card?.closest('.map-account-item')?.scrollIntoView({ block: 'nearest' });
}

function escHtml(str) {
    if (!str) return '';
    const div = document.createElement('div');
    div.textContent = String(str);
    return div.innerHTML;
}

function debounce(fn, ms) {
    return function(...args) {
        clearTimeout(searchDebounce);
        searchDebounce = setTimeout(() => fn.apply(this, args), ms);
    };
}

function init() {
    const searchInput = el('search-input');
    if (searchInput) {
        searchInput.addEventListener('input', debounce(() => {
            state.searchTerm = searchInput.value;
            state.currentPage = 1;
            loadPage();
        }, SEARCH_DEBOUNCE_MS));
    }

    const refreshBtn = el('btn-refresh');
    if (refreshBtn) refreshBtn.addEventListener('click', () => loadPage());

    const toggleBtn = el('btn-toggle-view');
    if (toggleBtn) {
        toggleBtn.addEventListener('click', () => {
            state.viewMode = state.viewMode === 'list' ? 'map' : 'list';
            toggleBtn.textContent = state.viewMode === 'list' ? 'Map' : 'List';
            el('list-view').hidden = state.viewMode !== 'list';
            el('map-view').classList.toggle('is-active', state.viewMode === 'map');
            if (state.viewMode === 'map') loadMapPage();
        });
    }

    const prevBtn = el('btn-prev');
    if (prevBtn) prevBtn.addEventListener('click', () => { if (state.currentPage > 1) { state.currentPage--; loadPage(); } });

    const nextBtn = el('btn-next');
    if (nextBtn) nextBtn.addEventListener('click', () => { const tp = Math.ceil(state.totalCount / PAGE_SIZE); if (state.currentPage < tp) { state.currentPage++; loadPage(); } });

    const mapPrevBtn = el('btn-map-prev');
    if (mapPrevBtn) mapPrevBtn.addEventListener('click', () => { if (state.mapCurrentPage > 1) { state.mapCurrentPage--; loadMapPage(); } });

    const mapNextBtn = el('btn-map-next');
    if (mapNextBtn) mapNextBtn.addEventListener('click', () => { const tp = Math.ceil(state.mapEligibleCount / MAP_PAGE_SIZE); if (state.mapCurrentPage < tp) { state.mapCurrentPage++; loadMapPage(); } });

    const mapList = el('map-account-list');
    if (mapList) {
        mapList.addEventListener('click', (event) => {
            const open = event.target.closest('[data-open]');
            if (open) {
                navigateToAccount(open.dataset.open);
                return;
            }
            const select = event.target.closest('[data-select]');
            if (select) selectMapAccount(select.dataset.select);
        });
    }

    loadPage();

    window.addEventListener('online', () => { loadPage(); loadMapPage(); });
    window.addEventListener('offline', () => { showSyncChip('offline', 'Offline'); showError('You are offline.'); });
}

document.addEventListener('DOMContentLoaded', init);