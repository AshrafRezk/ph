// Meeting changes made without signal (door scans, attendance, walk-in guests,
// WhatsApp "sent" marks). They are kept in IndexedDB and replayed through
// POST /meetings/m1/outbox, which runs each item on its own and is safe to repeat.
import { idbGet, idbSet } from './views/tabCache.js';
import { plannerApiFetch, isOffline } from './apex/restHelper.js';
import { showToast } from './toastManager.js';

const KEY = 'meetings:outbox';
const OUTBOX_PATH = '/services/apexrest/meetings/m1/outbox';
export const MEETING_OUTBOX_EVENT = 'zeta-meeting-outbox';

let draining = null;

async function readItems() {
    const wrap = await idbGet(KEY);
    const items = wrap && wrap.payload !== undefined ? wrap.payload : wrap;
    return Array.isArray(items) ? items : [];
}

async function writeItems(items) {
    await idbSet(KEY, items);
    try {
        window.dispatchEvent(new CustomEvent(MEETING_OUTBOX_EVENT, { detail: { pending: items.length } }));
    } catch (_err) {
        /* ignore */
    }
}

export async function queueMeetingChange(type, payload, meetingId) {
    const items = await readItems();
    const clientKey = `${type}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    items.push({ clientKey, type, payload, meetingId: meetingId || null, queuedAt: Date.now() });
    await writeItems(items);
    return clientKey;
}

export async function pendingMeetingChanges(meetingId) {
    const items = await readItems();
    return meetingId ? items.filter((item) => item.meetingId === meetingId) : items;
}

async function send() {
    const items = await readItems();
    if (!items.length) {
        return { synced: 0, failed: [] };
    }
    const response = await plannerApiFetch(OUTBOX_PATH, {
        method: 'POST',
        body: JSON.stringify({
            items: items.map(({ clientKey, type, payload }) => ({ clientKey, type, payload }))
        }),
        timeoutMs: 60000
    });
    const results = (response && response.results) || [];
    const done = new Set(results.map((r) => r.clientKey));
    const scans = new Set(items.filter((item) => item.type === 'SCAN').map((item) => item.clientKey));
    const failed = results
        .map((r) => {
            const scan = r.ok && scans.has(r.clientKey) && r.result;
            if (scan && scan.outcome !== 'checked_in' && scan.outcome !== 'already') {
                return { ...r, ok: false, message: `${scan.guestName || 'A guest'}: ${scan.title}. ${scan.message}` };
            }
            return r;
        })
        .filter((r) => !r.ok);
    // Items queued while the batch was in flight stay for the next drain.
    const remaining = (await readItems()).filter((item) => !done.has(item.clientKey));
    await writeItems(remaining);
    return { synced: results.length - failed.length, failed };
}

/** Sends queued meeting changes. A rejected item is dropped and reported; a network failure keeps everything. */
export function drainMeetingOutbox() {
    if (draining) {
        return draining;
    }
    if (isOffline()) {
        return Promise.resolve({ synced: 0, failed: [] });
    }
    draining = send()
        .then((outcome) => {
            if (outcome.synced) {
                try {
                    window.dispatchEvent(new CustomEvent(MEETING_OUTBOX_EVENT, { detail: { synced: outcome.synced } }));
                } catch (_err) {
                    /* ignore */
                }
                showToast({
                    title: 'Meeting changes synced',
                    message: `${outcome.synced} change${outcome.synced === 1 ? '' : 's'} made offline reached Salesforce.`,
                    variant: 'success'
                });
            }
            if (outcome.failed.length) {
                showToast({
                    title: 'Some meeting changes were not saved',
                    message: outcome.failed.map((f) => f.message).join(' '),
                    variant: 'warning',
                    mode: 'sticky'
                });
            }
            return outcome;
        })
        .catch(() => ({ synced: 0, failed: [] }))
        .finally(() => {
            draining = null;
        });
    return draining;
}
