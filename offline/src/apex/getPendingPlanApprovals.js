import { plannerApiFetch } from './restHelper.js';
import { makeDualApex } from './_wireAdapter.js';

// Visit plan approval queue uses this as a @wire adapter. A plain async function
// is not constructable, and the thrown error aborts the KPI dashboard render
// before the loading spinner is removed.
async function loadPendingPlanApprovals() {
    const data = await plannerApiFetch('/services/apexrest/planner/v1/visits/pending-approvals', {
        method: 'GET',
        fresh: true
    });
    if (Array.isArray(data)) {
        return data;
    }
    if (data && Array.isArray(data.rows)) {
        return data.rows;
    }
    return [];
}

export default makeDualApex(loadPendingPlanApprovals);
