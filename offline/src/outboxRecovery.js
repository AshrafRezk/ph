// Offline outbox recovery + visibility for the PWA shell.
//
//  * getOutboxStats()            pending / failed / dead counts straight from IndexedDB
//  * requeueDeadActions()        give `dead` actions (5 failed retries) a fresh set and drain
//  * requeueDeadAfterServerUpdate()  one-time revive per OUTBOX_SERVER_REVISION (server learned new actions)
//  * wireOutboxStatusChip()      small "N unsynced" chip; tap to retry dead actions
//
// `c/clmOfflineStore` only exposes pending/failed rows (dead rows are filtered out), so this module
// reads the same IndexedDB store directly. It never creates the database.

import { drainQueue, isOfflineMode, registerOfflineListener } from 'c/clmOfflineSync';
import {
    OUTBOX_REVISION_KEY,
    OUTBOX_SERVER_REVISION,
    describeOutbox,
    reviveDeadRow,
    summarizeOutboxRows
} from './outboxStats.js';

const DB_NAME = 'pharmaClmOffline';
const STORE = 'actionQueue';
const CHIP_ID = 'outbox-status-chip';
const REFRESH_MS = 30 * 1000;

function openExistingDb() {
    return new Promise((resolve) => {
        if (typeof indexedDB === 'undefined') {
            resolve(null);
            return;
        }
        let request;
        try {
            request = indexedDB.open(DB_NAME);
        } catch (_err) {
            resolve(null);
            return;
        }
        request.onupgradeneeded = () => {
            // Database did not exist yet: nothing is queued. Do not create it from here.
            request.transaction.abort();
        };
        request.onsuccess = () => {
            const db = request.result;
            if (!db.objectStoreNames.contains(STORE)) {
                db.close();
                resolve(null);
                return;
            }
            resolve(db);
        };
        request.onerror = () => resolve(null);
        request.onblocked = () => resolve(null);
    });
}

async function readAllRows() {
    const db = await openExistingDb();
    if (!db) {
        return [];
    }
    try {
        return await new Promise((resolve) => {
            const req = db.transaction(STORE, 'readonly').objectStore(STORE).getAll();
            req.onsuccess = () => resolve(Array.isArray(req.result) ? req.result : []);
            req.onerror = () => resolve([]);
        });
    } finally {
        db.close();
    }
}

export async function getOutboxStats() {
    return summarizeOutboxRows(await readAllRows());
}

export async function requeueDeadActions({ drain = true } = {}) {
    const db = await openExistingDb();
    if (!db) {
        return 0;
    }
    let revived = 0;
    try {
        revived = await new Promise((resolve) => {
            const tx = db.transaction(STORE, 'readwrite');
            const store = tx.objectStore(STORE);
            let count = 0;
            const cursorReq = store.openCursor();
            cursorReq.onsuccess = () => {
                const cursor = cursorReq.result;
                if (!cursor) {
                    return;
                }
                if (cursor.value?.status === 'dead') {
                    cursor.update(reviveDeadRow(cursor.value));
                    count += 1;
                }
                cursor.continue();
            };
            tx.oncomplete = () => resolve(count);
            tx.onerror = () => resolve(count);
            tx.onabort = () => resolve(count);
        });
    } finally {
        db.close();
    }
    if (revived && drain && !isOfflineMode()) {
        try {
            await drainQueue();
        } catch (_err) {
            /* stays queued; background sync retries */
        }
    }
    return revived;
}

export async function requeueDeadAfterServerUpdate() {
    let seen = null;
    try {
        seen = localStorage.getItem(OUTBOX_REVISION_KEY);
    } catch (_err) {
        return 0;
    }
    if (seen === OUTBOX_SERVER_REVISION) {
        return 0;
    }
    const revived = await requeueDeadActions({ drain: true });
    try {
        localStorage.setItem(OUTBOX_REVISION_KEY, OUTBOX_SERVER_REVISION);
    } catch (_err) {
        /* ignore */
    }
    return revived;
}

let chipWired = false;

export function wireOutboxStatusChip() {
    if (chipWired || typeof document === 'undefined') {
        return;
    }
    chipWired = true;
    let chip = document.getElementById(CHIP_ID);
    if (!chip) {
        chip = document.createElement('button');
        chip.type = 'button';
        chip.id = CHIP_ID;
        chip.className = 'outbox-status-chip';
        chip.hidden = true;
        chip.setAttribute('aria-live', 'polite');
        document.body.appendChild(chip);
    }
    let busy = false;
    const refresh = async () => {
        try {
            const summary = await getOutboxStats();
            const text = describeOutbox(summary);
            chip.hidden = !text;
            chip.textContent = text;
            chip.classList.toggle('outbox-status-chip--attention', summary.dead > 0);
        } catch (_err) {
            chip.hidden = true;
        }
    };
    chip.addEventListener('click', async () => {
        if (busy) {
            return;
        }
        busy = true;
        try {
            const revived = await requeueDeadActions({ drain: false });
            if (!isOfflineMode()) {
                await drainQueue().catch(() => null);
            } else if (!revived) {
                /* offline: nothing more to do until reconnect */
            }
        } finally {
            busy = false;
            void refresh();
        }
    });
    registerOfflineListener(() => {
        void refresh();
    });
    window.addEventListener('online', () => void refresh());
    window.setInterval(() => void refresh(), REFRESH_MS);
    void refresh();
}
