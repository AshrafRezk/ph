import { plannerApiFetch } from './restHelper.js';
import { createScopeTracker } from './_territoryScope.js';

let inflight = null;
let inflightKey = '';
const nextScope = createScopeTracker();

export async function loadHomeDashboard(params = {}) {
    const qs = new URLSearchParams();
    if (params?.contextUserId) {
        qs.set('contextUserId', params.contextUserId);
    }
    // Several Home cards share one dashboard call; `territoryScope` keeps one saved copy per working
    // territory (the server ignores it), and the first call after a switch waits on the network.
    const { scope, fresh } = nextScope();
    qs.set('territoryScope', scope);
    const suffix = `?${qs.toString()}`;
    const key = suffix;
    if (inflight && inflightKey === key) {
        return inflight;
    }
    inflightKey = key;
    inflight = plannerApiFetch(`/services/apexrest/planner/v1/home/dashboard${suffix}`, { fresh }).finally(() => {
        inflight = null;
    });
    return inflight;
}
