import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

// DM team target list (TeamTargetListRestService → TeamTargetListController). Always fresh: it is edited in place.
export default makeDualApex(async (params = {}) => {
    const query = new URLSearchParams();
    if (params.repId) {
        query.set('repId', params.repId);
    }
    if (params.quarter) {
        query.set('quarter', params.quarter);
    }
    const qs = query.toString() ? `?${query.toString()}` : '';
    return plannerApiFetch(`/services/apexrest/team-targets/v1/list${qs}`, { fresh: true });
});
