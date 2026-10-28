import { plannerApiFetch } from './restHelper.js';

const API_VERSION = 'v62.0';

function isSalesforceId(value) {
    return /^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/.test(String(value || ''));
}

export default async function deleteTimeOff(params = {}) {
    const timeOffId = params.timeOffId;
    if (!isSalesforceId(timeOffId)) {
        return { ok: true };
    }
    await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/Time_Off_Request__c/${timeOffId}`, {
        method: 'DELETE'
    });
    return { ok: true };
}
