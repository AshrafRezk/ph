// Working territory from the switcher (userMenu writes it before announcing a switch).
// Added to GET paths the server scopes by territory, so the offline cache keeps
// one copy per territory and a switch never paints the previous territory's numbers.
const TERRITORY_CACHE_KEY = 'zeta.pwa.sfTerritoryContext';

export function territoryScopeKey() {
    try {
        const raw = window.localStorage.getItem(TERRITORY_CACHE_KEY);
        const context = raw ? JSON.parse(raw) : null;
        if (!context || context.usingAllAssigned !== false) {
            return 'all';
        }
        return context.selectedTerritoryId || 'all';
    } catch {
        return 'all';
    }
}

// One per GET stub: after a territory switch is announced (or the territory key changes),
// the next call waits on the network instead of painting a saved copy. The saved key can
// already match the new territory when it was out of step with Salesforce.
export function createScopeTracker() {
    let lastScope;
    let switched = false;
    try {
        window.addEventListener('pharma-territory-context', () => {
            switched = true;
        });
    } catch {
        /* no window (tests) */
    }
    return () => {
        const scope = territoryScopeKey();
        const fresh = switched || (lastScope !== undefined && lastScope !== scope);
        switched = false;
        lastScope = scope;
        return { scope, fresh };
    };
}
