import { makeDualApex } from './_wireAdapter.js';
import { loadHomeDashboard } from './homeDashboard.js';

const EMPTY = {
    visitCoveragePercent: 0,
    customerCoveragePercent: 0,
    rfPercentTotal: 0,
    actualVisitsTotal: 0,
    targetVisitsTotal: 0,
    plannedVisitsTotal: 0,
    remainingCalls: 0,
    amAttainmentPercent: 0,
    amActualVisits: 0,
    amTargetVisits: 0,
    amPlannedVisits: 0,
    pmAttainmentPercent: 0,
    pmActualVisits: 0,
    pmTargetVisits: 0,
    pmPlannedVisits: 0,
    targetCallRate: null,
    targetAmCallRate: null,
    targetPmCallRate: null,
    actualCallRate: null,
    actualAmCallRate: null,
    actualPmCallRate: null,
    byClassification: []
};

export default makeDualApex(async (params) => {
    const dash = await loadHomeDashboard(params || {});
    return dash?.metrics || { ...EMPTY };
});
