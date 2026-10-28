import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const CACHE_KEY = 'zeta.pwa.fieldFeatures.v1';

const DEFAULTS = {
    'home.officeMessages': true,
    'home.beInTheKnow': true,
    'home.accountsNurturing': true,
    'home.yourPerformance': true,
    'home.todayPlan': true,
    'home.nextBestCustomer': true,
    'home.reports': true,
    'metric.visit': true,
    'metric.customer': true,
    'metric.rf': true,
    'metric.remaining': true,
    'metric.am': true,
    'metric.pm': true,
    'planner.mapRoute': true,
    'planner.copyPrevious': true,
    'planner.addMeeting': true,
    'planner.timeOff': true,
    meetingExpenses: true,
    agentforce: true,
    classEngine: true,
    'requests.enabled': true,
    'requests.medical': true,
    'requests.type.device': true,
    'requests.type.material': true,
    'requests.type.followUp': true,
    'requests.type.other': true,
    'hcp.products': true,
    'hcp.news': true,
    'hcp.home': true,
    'hcp.events': true,
    'hcp.requests': true,
    nextBestCustomer: true
};

function readCache() {
    try {
        const raw = localStorage.getItem(CACHE_KEY);
        return raw ? { ...DEFAULTS, ...JSON.parse(raw) } : { ...DEFAULTS };
    } catch (_err) {
        return { ...DEFAULTS };
    }
}

function writeCache(map) {
    try {
        localStorage.setItem(CACHE_KEY, JSON.stringify(map));
    } catch (_err) {
        // ignore quota
    }
}

async function loadEnabledFeatureMap() {
    try {
        const soql =
            'SELECT Feature_Key__c, Is_Enabled__c FROM Field_App_Feature__c WHERE Feature_Key__c != null';
        const data = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(soql)}`
        );
        const map = { ...DEFAULTS };
        for (const row of data?.records || []) {
            if (row.Feature_Key__c) {
                map[row.Feature_Key__c] = row.Is_Enabled__c === true;
            }
        }
        if (map['home.nextBestCustomer'] !== undefined) {
            map.nextBestCustomer = map['home.nextBestCustomer'] === true;
        }
        writeCache(map);
        return map;
    } catch (_err) {
        return readCache();
    }
}

export { readCache as readCachedFieldFeatures };
export default makeDualApex(loadEnabledFeatureMap);
