import getEnabledFeatureMap from '@salesforce/apex/FieldAppFeatureController.getEnabledFeatureMap';

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
    'requests.type.sample': true,
    'requests.type.device': true,
    'requests.type.material': true,
    'requests.type.followUp': true,
    'requests.type.other': true,
    'hcp.products': true,
    'hcp.news': true,
    'hcp.home': true,
    'hcp.events': true,
    'hcp.requests': true,
    consent: true,
    medicalInquiry: true,
    samples: true,
    clm: true,
    coaching: true,
    whatsapp: false,
    surveys: true,
    storeCheck: true,
    orders: true,
    fieldEmail: true,
    remoteVisit: true,
    voiceNotes: true,
    dcr: true,
    activityPlan: true,
    nextBestCustomer: true
};

let cached = { ...DEFAULTS };
let loadPromise;

export function isFieldFeatureEnabled(key) {
    if (!key) {
        return true;
    }
    if (cached[key] === undefined) {
        return true;
    }
    return cached[key] === true;
}

export async function loadFieldFeatures() {
    if (loadPromise) {
        return loadPromise;
    }
    loadPromise = getEnabledFeatureMap()
        .then((data) => {
            cached = { ...DEFAULTS, ...(data || {}) };
            if (cached['home.nextBestCustomer'] !== undefined) {
                cached.nextBestCustomer = cached['home.nextBestCustomer'] === true;
            }
            return cached;
        })
        .catch(() => {
            cached = { ...DEFAULTS };
            return cached;
        })
        .finally(() => {
            loadPromise = null;
        });
    return loadPromise;
}

export function getFieldFeatureSnapshot() {
    return { ...cached };
}

export function resetFieldFeatureCache() {
    cached = { ...DEFAULTS };
    loadPromise = null;
}
