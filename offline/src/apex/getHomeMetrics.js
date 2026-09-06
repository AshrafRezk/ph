// Offline stub for FieldRepHomeController.getHomeMetrics — empty shape so the
// home KPI rings render zeros instead of throwing on null.
import { makeDualApex } from './_wireAdapter.js';

const EMPTY = {
    visitCoveragePercent: 0,
    customerCoveragePercent: 0,
    rfPercentTotal: 0,
    actualVisitsTotal: 0,
    targetVisitsTotal: 0,
    plannedVisitsTotal: 0,
    remainingCalls: 0,
    byClassification: []
};

export default makeDualApex(async () => ({ ...EMPTY }));
