import { resolveAccountPinKind } from 'c/plannerMapPins';
import { isPlannedVisitType } from 'c/visitStatusUtils';

// Workload period (AM/PM) is derived from the visit account's record type via the
// admin-configurable Workload_Period_Mapping metadata. Default mirrors the BRD:
// HCP -> AM, HCO -> PM. Record-type-specific overrides take precedence over kind.
const DEFAULT_PERIOD_BY_KIND = { HCP: 'AM', HCO: 'PM' };
let periodByKind = { ...DEFAULT_PERIOD_BY_KIND };
let periodByRecordType = {};

function normPeriod(value) {
    return String(value || '').trim().toUpperCase() === 'PM' ? 'PM' : 'AM';
}

/** Apply resolved mapping rows: [{ accountKind, recordTypeDeveloperName, period }]. */
export function setWorkloadPeriodMap(rows) {
    const byKind = {};
    const byRt = {};
    (rows || []).forEach((r) => {
        const period = normPeriod(r.period);
        if (r.recordTypeDeveloperName) {
            byRt[r.recordTypeDeveloperName] = period;
        } else if (r.accountKind) {
            byKind[String(r.accountKind).toUpperCase()] = period;
        }
    });
    periodByKind = { ...DEFAULT_PERIOD_BY_KIND, ...byKind };
    periodByRecordType = byRt;
}

export function resolveWorkloadPeriod(recordTypeDeveloperName, recordTypeName) {
    if (recordTypeDeveloperName && periodByRecordType[recordTypeDeveloperName]) {
        return periodByRecordType[recordTypeDeveloperName];
    }
    const kind = String(resolveAccountPinKind(recordTypeDeveloperName, recordTypeName) || 'hcp').toUpperCase();
    return periodByKind[kind] || 'AM';
}

function visitRecordTypeDev(v) {
    return v.accountRecordTypeDeveloperName || v.recordTypeDeveloperName || null;
}
function visitRecordTypeName(v) {
    return v.accountRecordTypeName || v.recordTypeName || null;
}
function visitType(v) {
    return v.visitType || v.type || v.Visit_Type__c;
}

/** Count a visit list split by Planned/Unplanned and AM/PM workload period. */
export function countVisitWorkload(visits) {
    const c = {
        total: 0,
        planned: 0,
        unplanned: 0,
        am: 0,
        pm: 0,
        plannedAM: 0,
        plannedPM: 0,
        unplannedAM: 0,
        unplannedPM: 0
    };
    (visits || []).forEach((v) => {
        if (!v) return;
        const planned = isPlannedVisitType(visitType(v));
        const period = resolveWorkloadPeriod(visitRecordTypeDev(v), visitRecordTypeName(v));
        c.total += 1;
        if (planned) c.planned += 1; else c.unplanned += 1;
        if (period === 'PM') {
            c.pm += 1;
            if (planned) c.plannedPM += 1; else c.unplannedPM += 1;
        } else {
            c.am += 1;
            if (planned) c.plannedAM += 1; else c.unplannedAM += 1;
        }
    });
    return c;
}