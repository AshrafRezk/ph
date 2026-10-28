// Meetings module Apex stand-ins. Every call goes through the MeetingMobileRestService
// Apex REST class, which runs the same @AuraEnabled method the LWC uses in Lightning.
// Reads keep a copy on the device for offline use. Door scans, attendance, walk-in guests
// and WhatsApp "sent" marks are queued when there is no signal (see ../meetingOutbox.js);
// anything else needs a connection.
import { isOfflineMode } from 'c/clmOfflineSync';
import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch, isOffline, isNetworkError } from './restHelper.js';
import { idbGet, idbSet } from '../views/tabCache.js';
import { queueMeetingChange, pendingMeetingChanges } from '../meetingOutbox.js';

const BASE = '/services/apexrest/meetings/m1/';
const TIMEOUT_MS = 35000;
const NEEDS_CONNECTION = 'This needs a connection. Try again when you are back online.';
const TOKEN_PREFIX = 'ZM1';
const STEP_MS = 60 * 1000;
const GRACE_STEPS = 1;

// The workspace the user has open; attendance and "sent" changes belong to it.
let openMeetingId = null;

function offline() {
    return isOffline() || isOfflineMode();
}

function unreachable(error) {
    return isNetworkError(error) || /could not reach salesforce/i.test(String((error && error.message) || ''));
}

function cacheKey(method, params) {
    const id = params && params.meetingId;
    return `meetings:${method}${id ? ':' + id : ''}`;
}

function packKey(meetingId) {
    return `meetings:pack:${meetingId}`;
}

async function readStored(key) {
    const wrap = await idbGet(key);
    return wrap && wrap.payload !== undefined ? wrap.payload : wrap;
}

async function call(method, params) {
    const response = await plannerApiFetch(`${BASE}call`, {
        method: 'POST',
        body: JSON.stringify({ method, params: params || {} }),
        timeoutMs: TIMEOUT_MS
    });
    return response ? response.result : null;
}

// ---------------------------------------------------------------- reads

export function meetingRead(method) {
    return makeDualApex(async (params) => {
        const key = cacheKey(method, params);
        if (method === 'getWorkspace' && params && params.meetingId) {
            openMeetingId = params.meetingId;
        }
        if (!offline()) {
            try {
                const data = await call(method, params);
                await idbSet(key, data);
                if (method === 'getWorkspace') {
                    void savePack(data);
                }
                return withPending(method, data);
            } catch (error) {
                if (!unreachable(error)) {
                    throw error;
                }
            }
        }
        const cached = await readStored(key);
        if (cached == null) {
            throw new Error('Not saved on this device yet. Open it once while online to use it offline.');
        }
        return withPending(method, cached);
    });
}

/** Shows changes still waiting to sync on top of the saved workspace. */
async function withPending(method, data) {
    if (method !== 'getWorkspace' || !data || !data.meeting) {
        return data;
    }
    const pending = await pendingMeetingChanges(data.meeting.id);
    if (!pending.length) {
        return data;
    }
    let ws = { ...data, members: [...(data.members || [])], invitations: [...(data.invitations || [])] };
    pending.forEach((item) => {
        ws = applyChange(ws, item);
    });
    return ws;
}

function applyChange(ws, item) {
    const p = item.payload || {};
    if (item.type === 'SET_ATTENDANCE') {
        ws.members = ws.members.map((m) => (m.id === p.memberId ? { ...m, attendance: p.attendance } : m));
    } else if (item.type === 'ADD_GUEST') {
        if (!ws.invitations.some((i) => i.id === item.clientKey)) {
            ws.invitations.push({
                id: item.clientKey,
                guestName: p.guestName,
                phone: p.phone,
                email: p.email,
                status: 'Waiting to sync',
                pending: true,
                active: true,
                scans: 0
            });
        }
    } else if (item.type === 'MARK_SENT') {
        ws.invitations = ws.invitations.map((i) =>
            i.id === p.invitationId && i.status === 'Not Sent' ? { ...i, status: 'Sent', sentAt: new Date(item.queuedAt).toISOString() } : i
        );
    } else if (item.type === 'SCAN' && p.invitationId) {
        ws.invitations = ws.invitations.map((i) =>
            i.id === p.invitationId ? { ...i, status: 'Checked In', checkedInAt: new Date(p.scannedAt).toISOString() } : i
        );
    }
    return ws;
}

// ---------------------------------------------------------------- writes

export function meetingWrite(method) {
    return makeDualApex(async (params) => {
        if (offline()) {
            throw new Error(NEEDS_CONNECTION);
        }
        try {
            return await call(method, params);
        } catch (error) {
            throw unreachable(error) ? new Error(NEEDS_CONNECTION) : error;
        }
    });
}

const QUEUE_WHEN_OFFLINE = {
    setAttendance: async (params) => {
        await queueMeetingChange('SET_ATTENDANCE', { memberId: params.memberId, attendance: params.attendance }, openMeetingId);
        return { queued: true };
    },
    addGuestInvitation: async (params) => {
        const meetingId = params.meetingId;
        await queueMeetingChange(
            'ADD_GUEST',
            { meetingId, guestName: params.guestName, phone: params.phone || null, email: params.email || null },
            meetingId
        );
        const cached = await readStored(cacheKey('getWorkspace', { meetingId }));
        return cached ? withPending('getWorkspace', cached) : { queued: true };
    },
    markInvitationSent: async (params) => {
        await queueMeetingChange('MARK_SENT', { invitationId: params.invitationId, phone: params.phone || null }, openMeetingId);
        const cached = openMeetingId ? await readStored(cacheKey('getWorkspace', { meetingId: openMeetingId })) : null;
        const row = cached && (cached.invitations || []).find((i) => i.id === params.invitationId);
        return row ? { ...row, status: 'Sent', sentAt: new Date().toISOString() } : { queued: true };
    }
};

/** Saved on the device when there is no signal, sent later by the meeting outbox. */
export function meetingQueuedWrite(method) {
    const queue = QUEUE_WHEN_OFFLINE[method];
    return makeDualApex(async (params) => {
        if (offline()) {
            return queue(params);
        }
        try {
            return await call(method, params);
        } catch (error) {
            if (unreachable(error)) {
                return queue(params);
            }
            throw error;
        }
    });
}

// ---------------------------------------------------------------- door check-in

/** Keeps the meeting's guest keys on the device while check-in is open, so the door works without signal. */
async function savePack(ws) {
    const meetingId = ws && ws.meeting && ws.meeting.id;
    if (!meetingId || !ws.actions || !ws.actions.canScan) {
        return;
    }
    try {
        const pack = await plannerApiFetch(`${BASE}pack?meetingId=${encodeURIComponent(meetingId)}`, {
            fresh: true,
            timeoutMs: TIMEOUT_MS
        });
        if (pack && Array.isArray(pack.guests)) {
            await idbSet(packKey(meetingId), { ...pack, skewMs: Number(pack.serverNow || Date.now()) - Date.now() });
        }
    } catch (_err) {
        // Outside the check-in window there is no pack; online scanning still works.
    }
}

function scanResult(outcome, title, message, guest, pack) {
    const guests = (pack && pack.guests) || [];
    return {
        outcome,
        ok: outcome === 'checked_in',
        title,
        message,
        invitationId: guest ? guest.invitationId : null,
        guestName: guest ? guest.guestName : null,
        checkedInAt: guest ? guest.checkedInAt : null,
        invitedCount: guests.filter((g) => g.active).length,
        checkedInCount: guests.filter((g) => g.status === 'Checked In').length
    };
}

async function tokenMac(secret, code, step) {
    const enc = new TextEncoder();
    const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, enc.encode(`${code}:${step}`)));
    return Array.from(mac, (b) => b.toString(16).padStart(2, '0')).join('').slice(0, 16);
}

function formatTime(iso) {
    return new Date(iso).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

/** Same checks as MeetingInvitationService.scan, against the pack saved on this device. */
export async function scanOffline(meetingId, payload) {
    const pack = await readStored(packKey(meetingId));
    if (!pack) {
        return scanResult(
            'closed',
            'Check-in not saved on this device',
            'Open this meeting once while online during the check-in window, then you can scan without signal.',
            null,
            null
        );
    }
    const now = Date.now() + (pack.skewMs || 0);
    const parts = String(payload || '').trim().split(':');
    if (parts.length !== 4 || parts[0] !== TOKEN_PREFIX || !/^\d+$/.test(parts[2]) || parts[1].length > 16) {
        return scanResult('invalid', 'Not a Zeta invitation', 'This QR is not a meeting check-in code. Ask the guest to open their invitation link.', null, pack);
    }
    const guest = pack.guests.find((g) => g.code === parts[1]);
    if (!guest || !guest.secret) {
        return scanResult('invalid', 'Unknown invitation', 'This code is not on this meeting’s guest list.', null, pack);
    }
    const step = Number(parts[2]);
    if ((await tokenMac(guest.secret, guest.code, step)) !== parts[3].toLowerCase()) {
        return scanResult('invalid', 'Code not genuine', 'This QR was altered or copied. Ask the guest to open their invitation link.', guest, pack);
    }
    if (guest.active !== true) {
        return scanResult('inactive', 'Invitation turned off', 'The organizer turned this invitation off.', guest, pack);
    }
    if (guest.status === 'Checked In') {
        return scanResult('already', 'Already checked in', `${guest.guestName} checked in at ${formatTime(guest.checkedInAt)}.`, guest, pack);
    }
    if (Math.abs(Math.floor(now / STEP_MS) - step) > GRACE_STEPS) {
        return scanResult('expired', 'Code expired', 'This looks like a screenshot. Ask the guest to show the live code on their phone.', guest, pack);
    }
    if (pack.status === 'Cancelled' || now < Date.parse(pack.opens) || now > Date.parse(pack.closes)) {
        return scanResult('closed', 'Check-in is not open', 'Check-in opens 12 hours before the meeting and closes 6 hours after it ends.', guest, pack);
    }
    await queueMeetingChange('SCAN', { meetingId, payload: String(payload).trim(), scannedAt: now, invitationId: guest.invitationId }, meetingId);
    const checkedInAt = new Date(now).toISOString();
    const guests = pack.guests.map((g) => (g.invitationId === guest.invitationId ? { ...g, status: 'Checked In', checkedInAt } : g));
    const updated = { ...pack, guests };
    await idbSet(packKey(meetingId), updated);
    return scanResult(
        'checked_in',
        `Welcome, ${guest.guestName}`,
        'Saved offline, will sync when you are back online.',
        { ...guest, checkedInAt },
        updated
    );
}

export const scanAttendee = makeDualApex(async (params) => {
    const { meetingId, payload } = params || {};
    if (offline()) {
        return scanOffline(meetingId, payload);
    }
    let result;
    try {
        result = await call('scanAttendee', { meetingId, payload });
    } catch (error) {
        if (unreachable(error)) {
            return scanOffline(meetingId, payload);
        }
        throw error;
    }
    if (result && result.ok && result.invitationId) {
        const pack = await readStored(packKey(meetingId));
        if (pack) {
            const guests = pack.guests.map((g) =>
                g.invitationId === result.invitationId ? { ...g, status: 'Checked In', checkedInAt: result.checkedInAt } : g
            );
            await idbSet(packKey(meetingId), { ...pack, guests });
        }
    }
    return result;
});
