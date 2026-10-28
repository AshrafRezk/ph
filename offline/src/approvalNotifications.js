import { plannerApiFetch, isOffline } from './apex/restHelper.js';
import { showToast } from './toastManager.js';
import { closeUserMenu, switchWorkingTerritory } from './userMenu.js';

const POLL_MS = 45000;
const NOTIFICATIONS_PATH = '/services/data/v62.0/connect/notifications?size=25';
const OPEN_TOT_APPROVAL_KEY = 'zeta.pwa.openTotApproval';

let wired = false;
let pollTimer = null;
let rows = [];
let unseenTotal = 0;
let opening = false;

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

function formatWhen(value) {
    if (!value) return '';
    try {
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return '';
        return date.toLocaleString(undefined, {
            month: 'short',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        });
    } catch {
        return '';
    }
}

function notificationList(data) {
    if (Array.isArray(data)) return data;
    if (Array.isArray(data?.notifications)) return data.notifications;
    if (Array.isArray(data?.items)) return data.items;
    return [];
}

function isUnseen(row) {
    if (row?.seen === false) return true;
    if (row?.seen === true) return false;
    return row?.read === false;
}

function notificationId(row) {
    return String(row?.id || row?.notificationId || '');
}

function notificationTitle(row) {
    return row?.messageTitle || row?.title || 'Notification';
}

function notificationBody(row) {
    return row?.messageBody || row?.body || '';
}

function notificationWhen(row) {
    return row?.mostRecentActivityDate || row?.lastModified || row?.createdDate || '';
}

function targetIdOf(row) {
    const target = String(row?.target || row?.targetId || '');
    if (/^[a-zA-Z0-9]{15,18}$/.test(target)) return target;
    const url = String(row?.url || '');
    const match = url.match(/\/([a-zA-Z0-9]{15,18})(?:\/|$)/);
    return match ? match[1] : '';
}

function objectApiNameOf(row) {
    const url = String(row?.url || '');
    const match = url.match(/\/lightning\/r\/([^/]+)\//);
    return match ? decodeURIComponent(match[1]) : '';
}

function isTimeOffNotification(row) {
    const type = String(row?.type || '').toLowerCase();
    const url = String(row?.url || '');
    const title = `${notificationTitle(row)} ${notificationBody(row)}`.toLowerCase();
    return (
        type.includes('time_off') ||
        url.includes('Time_Off_Request__c') ||
        objectApiNameOf(row) === 'Time_Off_Request__c' ||
        title.includes('time off')
    );
}

function setPanelOpen(open) {
    const panel = $('approval-inbox-panel');
    if (!panel) return;
    panel.hidden = !open;
    if (open) {
        closeUserMenu();
        panel.removeAttribute('hidden');
        panel.classList.add('is-open');
        if (rows.length) renderInbox();
        void loadNotifications({ renderLoading: rows.length === 0 }).then(() => markVisibleSeen());
    } else {
        panel.setAttribute('hidden', '');
        panel.classList.remove('is-open');
    }
}

function paintBadge() {
    const count = unseenTotal;
    const label = count === 0 ? 'Notifications' : `${count} notification${count === 1 ? '' : 's'}`;
    document.querySelectorAll('[data-approval-bell]').forEach((btn) => {
        btn.setAttribute('title', 'Notifications');
        btn.setAttribute('aria-label', label);
        btn.classList.toggle('has-unread', count > 0);
    });
    document.querySelectorAll('[data-approval-badge]').forEach((badge) => {
        badge.hidden = count === 0;
        badge.textContent = count > 99 ? '99+' : String(count);
    });
}

function renderInbox() {
    const list = $('approval-inbox-list');
    const empty = $('approval-inbox-empty');
    const subtitle = $('approval-inbox-subtitle');
    if (!list) return;

    if (subtitle) {
        subtitle.textContent =
            rows.length === 0
                ? 'Alerts from Salesforce appear here.'
                : `${rows.length} notification${rows.length === 1 ? '' : 's'}.`;
    }

    if (!rows.length) {
        list.innerHTML = '';
        if (empty) {
            empty.hidden = false;
            empty.textContent = 'No notifications.';
        }
        return;
    }
    if (empty) empty.hidden = true;
    list.innerHTML = rows
        .map((row) => {
            const id = escapeHtml(notificationId(row));
            const title = escapeHtml(notificationTitle(row));
            const body = escapeHtml(notificationBody(row));
            const when = escapeHtml(formatWhen(notificationWhen(row)));
            const unread = isUnseen(row) || row.read === false;
            return `
                <li>
                    <button type="button" class="notification-row${unread ? ' is-unread' : ''}" data-notification-id="${id}">
                        <span class="notification-unread-dot" aria-hidden="true"></span>
                        <span class="notification-row-copy">
                            <span class="notification-row-title">${title}</span>
                            ${body ? `<span class="notification-row-body">${body}</span>` : ''}
                            ${when ? `<span class="notification-row-when">${when}</span>` : ''}
                        </span>
                    </button>
                </li>
            `;
        })
        .join('');
}

async function loadNotifications({ renderLoading = false } = {}) {
    const list = $('approval-inbox-list');
    if (isOffline()) {
        paintBadge();
        return;
    }
    if (renderLoading && list && !rows.length) {
        list.innerHTML = '<li class="approval-loading">Loading notifications…</li>';
        const empty = $('approval-inbox-empty');
        if (empty) empty.hidden = true;
    }
    try {
        const data = await plannerApiFetch(NOTIFICATIONS_PATH, { method: 'GET', fresh: true });
        rows = notificationList(data);
        const reported = Number(data?.unseenCount);
        unseenTotal = Number.isFinite(reported) ? reported : rows.filter((row) => isUnseen(row)).length;
    } catch (error) {
        console.warn('[Notifications] load failed', error);
        if (renderLoading && list) {
            list.innerHTML =
                '<li class="approval-loading">Could not load notifications. Try again when you are online.</li>';
        }
        paintBadge();
        return;
    }
    paintBadge();
    const panel = $('approval-inbox-panel');
    if (panel && !panel.hidden) {
        renderInbox();
    }
}

async function patchNotification(id, body) {
    if (!id) return;
    await plannerApiFetch(`/services/data/v62.0/connect/notifications/${encodeURIComponent(id)}`, {
        method: 'PATCH',
        fresh: true,
        body: JSON.stringify(body)
    });
}

async function markVisibleSeen() {
    const unseen = rows.filter((row) => isUnseen(row) && notificationId(row));
    if (!unseen.length) return;
    await Promise.all(
        unseen.map(async (row) => {
            try {
                await patchNotification(notificationId(row), { seen: 'true' });
                row.seen = true;
            } catch (error) {
                console.warn('[Notifications] mark seen failed', error);
            }
        })
    );
    unseenTotal = Math.max(0, unseenTotal - unseen.filter((row) => row.seen === true).length);
    paintBadge();
    const panel = $('approval-inbox-panel');
    if (panel && !panel.hidden) renderInbox();
}

async function markRead(row) {
    const id = notificationId(row);
    if (!id || row.read === true) return;
    const wasUnseen = isUnseen(row);
    try {
        await patchNotification(id, { read: 'true', seen: 'true' });
    } catch (error) {
        console.warn('[Notifications] mark read failed', error);
    }
    row.read = true;
    row.seen = true;
    if (wasUnseen) unseenTotal = Math.max(0, unseenTotal - 1);
    paintBadge();
}

function rememberTotApproval(target) {
    const payload = {
        timeOffId: target?.timeOffId || '',
        userId: target?.userId || '',
        startDateTime: target?.startDateTime || '',
        territoryId: target?.territoryId || '',
        territoryName: target?.territoryName || ''
    };
    try {
        sessionStorage.setItem(OPEN_TOT_APPROVAL_KEY, JSON.stringify(payload));
    } catch (_error) {
        /* ignore */
    }
    return payload;
}

function salesforceId(value) {
    const id = String(value || '');
    return /^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/.test(id) ? id : '';
}

async function queryRecords(soql) {
    const data = await plannerApiFetch(`/services/data/v62.0/query?q=${encodeURIComponent(soql)}`, {
        method: 'GET',
        fresh: true
    });
    return Array.isArray(data?.records) ? data.records : [];
}

async function loadTimeOffTargetFromQuery(timeOffId) {
    const id = salesforceId(timeOffId);
    if (!id) {
        throw new Error('Time off request not found.');
    }
    const rows = await queryRecords(
        `SELECT Id, Type__c, Stage__c, Start_Date_Time__c, CreatedById, CreatedBy.Name FROM Time_Off_Request__c WHERE Id = '${id}' LIMIT 1`
    );
    const row = rows[0];
    if (!row) {
        throw new Error('Time off request not found.');
    }
    let territoryId = '';
    let territoryName = '';
    const userId = salesforceId(row.CreatedById);
    if (userId) {
        try {
            const assignments = await queryRecords(
                `SELECT Territory2Id, Territory2.Name FROM UserTerritory2Association WHERE UserId = '${userId}' ORDER BY Territory2.Name LIMIT 5`
            );
            const assignment = assignments[0];
            if (assignment) {
                territoryId = assignment.Territory2Id || '';
                territoryName = assignment.Territory2?.Name || '';
            }
        } catch (error) {
            console.warn('[Notifications] rep territory lookup failed', error);
        }
    }
    return {
        timeOffId: row.Id,
        userId: row.CreatedById || '',
        userName: row.CreatedBy?.Name || '',
        startDateTime: row.Start_Date_Time__c || '',
        territoryId,
        territoryName,
        stage: row.Stage__c || '',
        typeLabel: row.Type__c || ''
    };
}

async function openTimeOffTarget(timeOffId) {
    let target;
    try {
        target = await plannerApiFetch(
            `/services/apexrest/planner/v1/time-off/approval-target?timeOffId=${encodeURIComponent(timeOffId)}`,
            { method: 'GET', fresh: true }
        );
    } catch (error) {
        console.warn('[Notifications] approval-target route unavailable', error);
        target = await loadTimeOffTargetFromQuery(timeOffId);
    }
    const payload = rememberTotApproval(target);
    if (payload.territoryId) {
        try {
            await switchWorkingTerritory(payload.territoryId, payload.territoryName);
        } catch (error) {
            console.warn('[Notifications] territory switch failed', error);
        }
    }
    window.dispatchEvent(
        new CustomEvent('zeta-navigate-tab', { detail: { apiName: 'Field_Rep_Planner' } })
    );
    window.dispatchEvent(new CustomEvent('zeta-open-tot-approval', { detail: payload }));
}

function openRecord(row) {
    const recordId = targetIdOf(row);
    if (!recordId) return;
    window.dispatchEvent(
        new CustomEvent('zeta-navigate-record', {
            detail: {
                recordId,
                objectApiName: objectApiNameOf(row)
            }
        })
    );
}

async function openNotification(row) {
    if (!row || opening) return;
    opening = true;
    try {
        await markRead(row);
        setPanelOpen(false);
        const targetId = targetIdOf(row);
        if (isTimeOffNotification(row) && targetId) {
            await openTimeOffTarget(targetId);
            return;
        }
        openRecord(row);
    } catch (error) {
        showToast({
            title: 'Notification',
            message: error?.message || 'Could not open this notification.',
            variant: 'error'
        });
    } finally {
        opening = false;
        renderInbox();
    }
}

function onPanelClick(event) {
    const target = event.target;
    if (!(target instanceof Element)) return;
    if (target.closest('[data-approval-close]')) {
        setPanelOpen(false);
        return;
    }
    const button = target.closest('[data-notification-id]');
    const id = button?.getAttribute('data-notification-id');
    if (!id) return;
    const row = rows.find((item) => notificationId(item) === id);
    if (row) void openNotification(row);
}

function startPolling() {
    stopPolling();
    void loadNotifications();
    pollTimer = window.setInterval(() => {
        if (document.visibilityState === 'hidden') return;
        void loadNotifications();
    }, POLL_MS);
}

function stopPolling() {
    if (pollTimer) {
        window.clearInterval(pollTimer);
        pollTimer = null;
    }
}

export function closeApprovalInbox() {
    setPanelOpen(false);
}

/** Open the Salesforce notification list (used by push tap routing). */
export function openApprovalInbox() {
    setPanelOpen(true);
}

export function refreshApprovalInbox() {
    return loadNotifications();
}

export async function openNotificationFromPush(payload = {}) {
    const hay = `${payload.type || ''} ${payload.title || ''} ${payload.body || ''}`.toLowerCase();
    const targetId = payload.targetId || '';
    if (targetId && (hay.includes('time off') || hay.includes('time_off'))) {
        try {
            await openTimeOffTarget(targetId);
            return;
        } catch (error) {
            console.warn('[Notifications] push time-off open failed', error);
        }
    }
    setPanelOpen(true);
}

export function initApprovalInbox() {
    if (wired) {
        startPolling();
        return;
    }
    wired = true;

    document.querySelectorAll('[data-approval-bell]').forEach((btn) => {
        btn.addEventListener('click', () => {
            const panel = $('approval-inbox-panel');
            const isClosed = !panel || panel.hidden;
            setPanelOpen(isClosed);
        });
    });
    $('approval-inbox-panel')?.addEventListener('click', onPanelClick);
    document.querySelectorAll('[data-user-avatar]').forEach((btn) => {
        btn.addEventListener('click', () => setPanelOpen(false));
    });
    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') setPanelOpen(false);
    });
    document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible') {
            void loadNotifications();
        }
    });

    startPolling();
}

export function teardownApprovalInbox() {
    stopPolling();
    rows = [];
    unseenTotal = 0;
    opening = false;
    setPanelOpen(false);
    paintBadge();
}
