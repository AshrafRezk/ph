import { plannerApiFetch } from './apex/restHelper';
import { isOfflineMode } from 'c/clmOfflineSync';
import {
    getStoredTerritoryContext,
    publishTerritoryContextChanged
} from 'c/territoryContextClient';

const PROFILE_CACHE_KEY = 'zeta.pwa.sfUserProfile';
const TERRITORY_CACHE_KEY = 'zeta.pwa.sfTerritoryContext';

let callbacks = {
    onSwitchApp: () => {},
    onLogout: () => {},
    getIdentity: () => ({}),
    saveIdentity: () => {}
};

let profileCache = null;
let territoryCache = null;
let expandedIds = new Set();
let searchTerm = '';
let isSavingTerritory = false;
let wired = false;

function $(id) {
    return document.getElementById(id);
}

function escapeHtml(value) {
    return String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function initialsFromName(name) {
    const parts = String(name || '')
        .trim()
        .split(/\s+/)
        .filter(Boolean);
    if (!parts.length) return '?';
    if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
    return `${parts[0][0] || ''}${parts[parts.length - 1][0] || ''}`.toUpperCase();
}

function displayNameFromProfile(profile, identity) {
    const first = (profile?.firstName || identity?.firstName || '').trim();
    const last = (profile?.lastName || identity?.lastName || '').trim();
    if (first || last) return `${first} ${last}`.trim();
    return (profile?.name || identity?.name || identity?.username || 'User').trim();
}

function photoUrlFromProfile(profile, identity) {
    const raw =
        profile?.photoUrl ||
        profile?.mediumPhotoUrl ||
        profile?.smallPhotoUrl ||
        identity?.picture ||
        '';
    return String(raw || '').trim();
}

function withCacheBust(url) {
    if (!url) return '';
    const sep = url.includes('?') ? '&' : '?';
    return `${url}${sep}_ts=${Date.now()}`;
}

function readCachedProfile() {
    try {
        const raw = window.localStorage.getItem(PROFILE_CACHE_KEY);
        return raw ? JSON.parse(raw) : null;
    } catch {
        return null;
    }
}

function writeCachedProfile(profile) {
    profileCache = profile;
    try {
        if (profile) {
            window.localStorage.setItem(PROFILE_CACHE_KEY, JSON.stringify(profile));
        } else {
            window.localStorage.removeItem(PROFILE_CACHE_KEY);
        }
    } catch {
        /* ignore */
    }
}

function readCachedTerritory() {
    try {
        const raw = window.localStorage.getItem(TERRITORY_CACHE_KEY);
        if (raw) return JSON.parse(raw);
    } catch {
        /* ignore */
    }
    return getStoredTerritoryContext();
}

function writeCachedTerritory(context) {
    territoryCache = context;
    try {
        if (context) {
            window.localStorage.setItem(TERRITORY_CACHE_KEY, JSON.stringify(context));
        } else {
            window.localStorage.removeItem(TERRITORY_CACHE_KEY);
        }
    } catch {
        /* ignore */
    }
}

function formatDateTime(value) {
    if (!value) return 'ù';
    try {
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return String(value);
        return date.toLocaleString(undefined, {
            year: 'numeric',
            month: 'short',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        });
    } catch {
        return String(value);
    }
}

function setSheetOpen(open) {
    const sheet = $('user-menu-sheet');
    if (!sheet) return;
    sheet.hidden = !open;
    if (open) {
        sheet.removeAttribute('hidden');
        sheet.classList.add('is-open');
        renderMenuHeader();
    } else {
        sheet.setAttribute('hidden', '');
        sheet.classList.remove('is-open');
    }
}

function setTerritoryPanelOpen(open) {
    const panel = $('territory-switcher-panel');
    if (!panel) return;
    panel.hidden = !open;
    if (open) {
        panel.removeAttribute('hidden');
        panel.classList.add('is-open');
        void renderTerritoryPanel();
    } else {
        panel.setAttribute('hidden', '');
        panel.classList.remove('is-open');
    }
}

function setProfilePanelOpen(open) {
    const panel = $('user-profile-panel');
    if (!panel) return;
    panel.hidden = !open;
    if (open) {
        panel.removeAttribute('hidden');
        panel.classList.add('is-open');
        void renderProfilePanel();
    } else {
        panel.setAttribute('hidden', '');
        panel.classList.remove('is-open');
    }
}

function closeAllOverlays() {
    setSheetOpen(false);
    setTerritoryPanelOpen(false);
    setProfilePanelOpen(false);
}

export function paintUserAvatars() {
    const identity = callbacks.getIdentity() || {};
    const profile = profileCache || readCachedProfile();
    const name = displayNameFromProfile(profile, identity);
    const photo = photoUrlFromProfile(profile, identity);
    const initials = initialsFromName(name);
    const territoryName =
        territoryCache?.selectedTerritoryName ||
        readCachedTerritory()?.territoryName ||
        readCachedTerritory()?.selectedTerritoryName ||
        'All assigned territories';

    document.querySelectorAll('[data-user-avatar]').forEach((btn) => {
        const img = btn.querySelector('.user-avatar-img');
        const fallback = btn.querySelector('.user-avatar-fallback');
        btn.title = name;
        btn.setAttribute('aria-label', `Account menu for ${name}`);
        if (img) {
            if (photo) {
                img.hidden = false;
                img.alt = name;
                if (img.dataset.src !== photo) {
                    img.dataset.src = photo;
                    img.src = photo;
                }
                img.onerror = () => {
                    img.hidden = true;
                    if (fallback) {
                        fallback.hidden = false;
                        fallback.textContent = initials;
                    }
                };
                if (fallback) fallback.hidden = true;
            } else {
                img.hidden = true;
                if (fallback) {
                    fallback.hidden = false;
                    fallback.textContent = initials;
                }
            }
        } else if (fallback) {
            fallback.hidden = false;
            fallback.textContent = initials;
        }
    });

    const label = $('user-menu-territory-label');
    if (label) label.textContent = territoryName;
}

function renderMenuHeader() {
    const identity = callbacks.getIdentity() || {};
    const profile = profileCache || readCachedProfile();
    const name = displayNameFromProfile(profile, identity);
    const email = profile?.email || identity?.username || '';
    const photo = photoUrlFromProfile(profile, identity);
    const initials = initialsFromName(name);
    const nameEl = $('user-menu-name');
    const emailEl = $('user-menu-email');
    const img = $('user-menu-header-img');
    const fallback = $('user-menu-header-fallback');
    if (nameEl) nameEl.textContent = name;
    if (emailEl) emailEl.textContent = email;
    if (img) {
        if (photo) {
            img.hidden = false;
            img.src = photo;
            img.alt = name;
            if (fallback) fallback.hidden = true;
        } else {
            img.hidden = true;
            if (fallback) {
                fallback.hidden = false;
                fallback.textContent = initials;
            }
        }
    }
    paintUserAvatars();
}

function flattenTree(nodes, depth, forceExpanded, rows) {
    if (!Array.isArray(nodes)) return;
    for (const node of nodes) {
        const expanded = forceExpanded === true ? true : expandedIds.has(node.id);
        rows.push({
            id: node.id,
            name: node.name,
            level: node.level || '',
            hasChildren: node.hasChildren === true,
            depth,
            expanded,
            selected: node.id === territoryCache?.selectedTerritoryId
        });
        if (expanded && node.children?.length) {
            flattenTree(node.children, depth + 1, forceExpanded, rows);
        }
    }
}

function filteredTerritoryRows() {
    const term = (searchTerm || '').trim().toLowerCase();
    const rows = [];
    const roots = territoryCache?.tree || [];
    flattenTree(roots, 0, !!term, rows);
    if (!term) return rows;
    return rows.filter(
        (row) =>
            (row.name || '').toLowerCase().includes(term) ||
            (row.level || '').toLowerCase().includes(term)
    );
}

function ensureExpandedDefaults() {
    if (expandedIds.size > 0) return;
    for (const root of territoryCache?.tree || []) {
        expandedIds.add(root.id);
        for (const child of root.children || []) {
            expandedIds.add(child.id);
        }
    }
}

async function loadTerritoryContext({ force = false } = {}) {
    if (!force && territoryCache?.tree) return territoryCache;
    if (isOfflineMode()) {
        territoryCache = readCachedTerritory() || territoryCache;
        return territoryCache;
    }
    try {
        const context = await plannerApiFetch('/services/apexrest/planner/v1/territory-context');
        territoryCache = context;
        writeCachedTerritory(context);
        publishTerritoryContextChanged(null, {
            territoryId: context.selectedTerritoryId || '',
            territoryName: context.selectedTerritoryName || 'All assigned territories',
            usingAllAssigned: context.usingAllAssigned !== false
        });
        paintUserAvatars();
        return context;
    } catch (error) {
        console.warn('[UserMenu] territory context load failed', error);
        territoryCache = readCachedTerritory() || territoryCache;
        return territoryCache;
    }
}

async function loadUserProfile({ force = false } = {}) {
    if (!force && profileCache) return profileCache;
    if (isOfflineMode()) {
        profileCache = readCachedProfile() || profileCache;
        return profileCache;
    }
    try {
        const profile = await plannerApiFetch('/services/apexrest/planner/v1/me');
        writeCachedProfile(profile);
        callbacks.saveIdentity({
            name: displayNameFromProfile(profile, callbacks.getIdentity()),
            username: profile.username || profile.email,
            userId: profile.id,
            picture: profile.photoUrl || profile.mediumPhotoUrl || profile.smallPhotoUrl,
            firstName: profile.firstName,
            lastName: profile.lastName
        });
        paintUserAvatars();
        return profile;
    } catch (error) {
        console.warn('[UserMenu] profile load failed', error);
        profileCache = readCachedProfile() || profileCache;
        return profileCache;
    }
}

function renderTerritoryPanel() {
    const list = $('territory-tree-list');
    const current = $('territory-current-name');
    const status = $('territory-status-label');
    const offlineNote = $('territory-offline-note');
    const errorEl = $('territory-error');
    if (!list) return;

    ensureExpandedDefaults();
    const usingAll = territoryCache?.usingAllAssigned !== false;
    const selectedName = territoryCache?.selectedTerritoryName || 'All assigned territories';
    if (current) current.textContent = selectedName;
    if (status) {
        status.textContent = !territoryCache?.hasAssignment
            ? 'No territory assignment'
            : usingAll
              ? 'All assigned'
              : territoryCache?.selectedLevel || 'Territory';
    }
    if (offlineNote) offlineNote.hidden = !isOfflineMode();
    if (errorEl) errorEl.textContent = '';

    const rows = filteredTerritoryRows();
    const disabled = isOfflineMode() || isSavingTerritory;
    const parts = [
        `<li class="tree-row${usingAll ? ' tree-row--selected' : ''}">
            <button class="select-btn" type="button" data-territory-all ${disabled ? 'disabled' : ''}>
                All assigned territories
            </button>
        </li>`
    ];
    for (const row of rows) {
        const pad = `padding-left: ${row.depth * 0.75}rem`;
        parts.push(`
            <li class="tree-row${row.selected ? ' tree-row--selected' : ''}">
                <div class="row-inner" style="${pad}">
                    ${
                        row.hasChildren
                            ? `<button class="toggle-btn" type="button" data-toggle-id="${escapeHtml(row.id)}" title="Expand or collapse">${row.expanded ? '?' : '?'}</button>`
                            : '<span class="toggle-spacer"></span>'
                    }
                    <button class="select-btn" type="button" data-territory-id="${escapeHtml(row.id)}" data-territory-name="${escapeHtml(row.name)}" ${disabled ? 'disabled' : ''}>
                        <span class="row-name">${escapeHtml(row.name)}</span>
                        <span class="row-level">${escapeHtml(row.level)}</span>
                    </button>
                </div>
            </li>
        `);
    }
    if (!territoryCache?.hasAssignment) {
        parts.push('<li class="empty">You are not assigned to a territory yet.</li>');
    }
    list.innerHTML = parts.join('');
}

function profileField(label, value) {
    return `
        <div class="profile-field">
            <dt>${escapeHtml(label)}</dt>
            <dd>${escapeHtml(value || 'ù')}</dd>
        </div>
    `;
}

async function renderProfilePanel() {
    const body = $('user-profile-body');
    if (!body) return;
    body.innerHTML = '<p class="profile-loading">Loading profileù</p>';
    const profile = (await loadUserProfile({ force: !isOfflineMode() })) || {};
    const identity = callbacks.getIdentity() || {};
    const name = displayNameFromProfile(profile, identity);
    const photo = photoUrlFromProfile(profile, identity);
    const initials = initialsFromName(name);

    body.innerHTML = `
        <div class="profile-hero">
            <div class="profile-photo-wrap">
                ${
                    photo
                        ? `<img id="profile-photo-img" class="profile-photo" src="${escapeHtml(photo)}" alt="${escapeHtml(name)}" />`
                        : `<span class="profile-photo-fallback">${escapeHtml(initials)}</span>`
                }
                <button id="profile-change-photo-btn" class="profile-change-photo" type="button" ${isOfflineMode() ? 'disabled' : ''}>
                    Change photo
                </button>
                <input id="profile-photo-input" type="file" accept="image/*" hidden />
            </div>
            <div>
                <h2 class="profile-name">${escapeHtml(name)}</h2>
                <p class="profile-sub">${escapeHtml(profile.profileName || '')}</p>
            </div>
        </div>
        <dl class="profile-grid">
            ${profileField('Email', profile.email)}
            ${profileField('Username', profile.username)}
            ${profileField('Title', profile.title)}
            ${profileField('Phone', profile.phone || profile.mobilePhone)}
            ${profileField('Manager', profile.managerName)}
            ${profileField('Role in territory', profile.roleInTerritory)}
            ${profileField('Working territory', profile.territoryName)}
            ${profileField('Last login', formatDateTime(profile.lastLoginDate))}
        </dl>
        <p id="profile-photo-status" class="profile-status" hidden></p>
    `;

    const changeBtn = $('profile-change-photo-btn');
    const input = $('profile-photo-input');
    changeBtn?.addEventListener('click', () => input?.click());
    input?.addEventListener('change', () => {
        const file = input.files && input.files[0];
        if (file) void uploadProfilePhoto(file);
        input.value = '';
    });
}

function readFileAsDataUrl(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(String(reader.result || ''));
        reader.onerror = () => reject(reader.error || new Error('Could not read photo'));
        reader.readAsDataURL(file);
    });
}

function compressImage(file, maxEdge = 720, quality = 0.82) {
    return new Promise(async (resolve, reject) => {
        try {
            const dataUrl = await readFileAsDataUrl(file);
            const img = new Image();
            img.onload = () => {
                const scale = Math.min(1, maxEdge / Math.max(img.width, img.height));
                const width = Math.max(1, Math.round(img.width * scale));
                const height = Math.max(1, Math.round(img.height * scale));
                const canvas = document.createElement('canvas');
                canvas.width = width;
                canvas.height = height;
                const ctx = canvas.getContext('2d');
                ctx.drawImage(img, 0, 0, width, height);
                const contentType = 'image/jpeg';
                const compressed = canvas.toDataURL(contentType, quality);
                resolve({
                    fileName: (file.name || 'profile.jpg').replace(/\.\w+$/, '.jpg'),
                    contentType,
                    base64Data: compressed
                });
            };
            img.onerror = () => reject(new Error('Could not load image'));
            img.src = dataUrl;
        } catch (error) {
            reject(error);
        }
    });
}

async function uploadProfilePhoto(file) {
    const status = $('profile-photo-status');
    if (isOfflineMode()) {
        if (status) {
            status.hidden = false;
            status.textContent = 'Connect to change your photo.';
        }
        return;
    }
    if (status) {
        status.hidden = false;
        status.textContent = 'Uploading photoù';
    }
    try {
        const payload = await compressImage(file);
        const profile = await plannerApiFetch('/services/apexrest/planner/v1/me/photo', {
            method: 'POST',
            body: JSON.stringify(payload)
        });
        if (profile?.photoUrl) {
            profile.photoUrl = withCacheBust(profile.photoUrl);
        }
        if (profile?.mediumPhotoUrl) {
            profile.mediumPhotoUrl = withCacheBust(profile.mediumPhotoUrl);
        }
        writeCachedProfile(profile);
        callbacks.saveIdentity({
            name: displayNameFromProfile(profile, callbacks.getIdentity()),
            username: profile.username || profile.email,
            userId: profile.id,
            picture: profile.photoUrl || profile.mediumPhotoUrl || profile.smallPhotoUrl,
            firstName: profile.firstName,
            lastName: profile.lastName
        });
        paintUserAvatars();
        await renderProfilePanel();
        if (status) {
            status.hidden = false;
            status.textContent = 'Photo updated.';
        }
    } catch (error) {
        console.error('[UserMenu] photo upload failed', error);
        if (status) {
            status.hidden = false;
            status.textContent = error?.message || 'Could not update photo.';
        }
    }
}

async function selectTerritory(territoryId, territoryName) {
    if (isSavingTerritory || isOfflineMode()) return;
    isSavingTerritory = true;
    const errorEl = $('territory-error');
    if (errorEl) errorEl.textContent = '';
    try {
        const context = await plannerApiFetch('/services/apexrest/planner/v1/territory-context', {
            method: 'POST',
            body: JSON.stringify({ territoryId: territoryId || null })
        });
        territoryCache = context;
        writeCachedTerritory(context);
        publishTerritoryContextChanged(null, {
            territoryId: territoryId || '',
            territoryName: territoryName || context.selectedTerritoryName,
            usingAllAssigned: context.usingAllAssigned === true
        });
        paintUserAvatars();
        renderTerritoryPanel();
        setTerritoryPanelOpen(false);
        setSheetOpen(false);
    } catch (error) {
        console.error('[UserMenu] territory switch failed', error);
        if (errorEl) errorEl.textContent = error?.message || 'Could not switch territory.';
        renderTerritoryPanel();
    } finally {
        isSavingTerritory = false;
    }
}

function onSheetClick(event) {
    const target = event.target;
    if (!(target instanceof Element)) return;
    if (target.closest('[data-user-menu-close]')) {
        setSheetOpen(false);
        return;
    }
    if (target.closest('#user-menu-open-profile') || target.closest('#user-menu-header-btn')) {
        setSheetOpen(false);
        setProfilePanelOpen(true);
        return;
    }
    if (target.closest('#user-menu-territory-btn')) {
        setSheetOpen(false);
        setTerritoryPanelOpen(true);
        return;
    }
    if (target.closest('#user-menu-switch-app-btn')) {
        setSheetOpen(false);
        callbacks.onSwitchApp();
        return;
    }
    if (target.closest('#user-menu-logout-btn')) {
        setSheetOpen(false);
        callbacks.onLogout();
    }
}

function onTerritoryClick(event) {
    const target = event.target;
    if (!(target instanceof Element)) return;
    if (target.closest('[data-territory-close]')) {
        setTerritoryPanelOpen(false);
        setSheetOpen(true);
        return;
    }
    const toggle = target.closest('[data-toggle-id]');
    if (toggle) {
        const id = toggle.getAttribute('data-toggle-id');
        if (expandedIds.has(id)) expandedIds.delete(id);
        else expandedIds.add(id);
        expandedIds = new Set(expandedIds);
        renderTerritoryPanel();
        return;
    }
    if (target.closest('[data-territory-all]')) {
        void selectTerritory(null, 'All assigned territories');
        return;
    }
    const select = target.closest('[data-territory-id]');
    if (select) {
        void selectTerritory(
            select.getAttribute('data-territory-id'),
            select.getAttribute('data-territory-name')
        );
    }
}

function onProfileClick(event) {
    const target = event.target;
    if (!(target instanceof Element)) return;
    if (target.closest('[data-profile-close]')) {
        setProfilePanelOpen(false);
        setSheetOpen(true);
    }
}

function onSearchInput(event) {
    searchTerm = event.target?.value || '';
    renderTerritoryPanel();
}

export function initUserMenu(options = {}) {
    callbacks = { ...callbacks, ...options };
    profileCache = readCachedProfile();
    territoryCache = readCachedTerritory();
    paintUserAvatars();

    if (wired) return;
    wired = true;

    document.querySelectorAll('[data-user-avatar]').forEach((btn) => {
        btn.addEventListener('click', () => {
            const sheet = $('user-menu-sheet');
            const isClosed = !sheet || sheet.hidden;
            if (isClosed) {
                setProfilePanelOpen(false);
                setTerritoryPanelOpen(false);
                setSheetOpen(true);
                void loadUserProfile();
                void loadTerritoryContext();
            } else {
                setSheetOpen(false);
            }
        });
    });

    $('user-menu-sheet')?.addEventListener('click', onSheetClick);
    $('territory-switcher-panel')?.addEventListener('click', onTerritoryClick);
    $('user-profile-panel')?.addEventListener('click', onProfileClick);
    $('territory-search')?.addEventListener('input', onSearchInput);

    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') closeAllOverlays();
    });
}

export async function refreshUserChrome() {
    await Promise.all([loadUserProfile({ force: true }), loadTerritoryContext({ force: true })]);
    paintUserAvatars();
}

export function clearUserMenuCache() {
    profileCache = null;
    territoryCache = null;
    writeCachedProfile(null);
    writeCachedTerritory(null);
    paintUserAvatars();
}

export function closeUserMenu() {
    closeAllOverlays();
}
