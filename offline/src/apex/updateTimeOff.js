import { plannerApiFetch } from './restHelper.js';

const API_VERSION = 'v62.0';

function salesforceDateTime(value) {
    if (!value) {
        return null;
    }
    const date = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(date.getTime())) {
        return null;
    }
    return date.toISOString();
}

export default async function updateTimeOff(params = {}) {
    if (params.typeValue || params.spanType) {
        const hours = params.spanType === 'Hours';
        const body = {
            Type__c: params.typeValue,
            Span_Type__c: params.spanType,
            Start_Date_Time__c: salesforceDateTime(params.startDateTime),
            End_Date_Time__c: salesforceDateTime(params.endDateTime),
            Comments__c: params.comments || null
        };
        if (hours) {
            body.Span_Duration_Select__c = String(params.durationHours);
            body.Span_Duration__c = Number(params.durationHours);
        } else {
            body.Span_Duration_Select__c = null;
            body.Span_Duration__c = 1;
        }
        await plannerApiFetch(
            `/services/data/${API_VERSION}/sobjects/Time_Off_Request__c/${params.timeOffId}`,
            { method: 'PATCH', body: JSON.stringify(body) }
        );
        return { id: params.timeOffId };
    }
    return plannerApiFetch('/services/apexrest/planner/assist/v1/time-off/update', {
        method: 'POST',
        body: JSON.stringify({
            timeOffId: params.timeOffId,
            endDateTime: params.endDateTime
        })
    });
}
