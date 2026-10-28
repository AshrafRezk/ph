const listeners = new Set();
let current = null;
let serialized = '';

export function publishAnalyticsSnapshot(snapshot) {
    const next = snapshot ? JSON.stringify(snapshot) : '';
    if (next === serialized) return;
    serialized = next;
    current = snapshot || null;
    listeners.forEach((listener) => {
        try {
            listener(current);
        } catch (_err) {
            /* a listener must not block the page */
        }
    });
}

export function readAnalyticsSnapshot() {
    return current;
}

export function onAnalyticsSnapshot(listener) {
    listeners.add(listener);
    return () => listeners.delete(listener);
}

export function snapshotForPanel(panel, snapshot) {
    if (!snapshot) return null;
    if (panel === 'view-reports' && (snapshot.kind === 'report' || snapshot.kind === 'report-list')) return snapshot;
    if (panel === 'view-dashboards' && (snapshot.kind === 'dashboard' || snapshot.kind === 'dashboard-list')) return snapshot;
    return null;
}
