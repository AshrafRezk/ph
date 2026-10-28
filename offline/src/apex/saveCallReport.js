import { getVisitPayload, putVisitPayload } from 'c/clmOfflineStore';
import { queueOfflineAction } from 'c/clmOfflineSync';

function formatDurationLabel(startDateTime, endDateTime) {
    if (!startDateTime || !endDateTime) {
        return null;
    }
    const minutes = Math.round((new Date(endDateTime) - new Date(startDateTime)) / 60000);
    if (!Number.isFinite(minutes) || minutes < 0) {
        return null;
    }
    if (minutes < 60) {
        return `${minutes} min`;
    }
    const hours = Math.floor(minutes / 60);
    const remainder = minutes % 60;
    return remainder === 0 ? `${hours} hr` : `${hours} hr ${remainder} min`;
}

// Offline stand-in for VisitCallReportController.saveCallReport (Aura-only, no
// REST write endpoint). Every save is optimistic + queued to the offline outbox
// so it syncs when a sync endpoint is available; returns the merged payload the
// shell re-renders from. Matches the component's own offline-mode behaviour so
// online/offline saves are consistent.
export default async function saveCallReport(params) {
    const request = JSON.parse((params && params.requestJson) || '{}');
    // Server accepts a Completed report on a past visit day only when it was captured
    // on that day, so stamp the device capture time before the save is queued.
    if (!request.capturedAt) {
        request.capturedAt = new Date().toISOString();
    }
    const requestJson = JSON.stringify(request);
    const visitId = request.visitId;
    const prev = (visitId && (await getVisitPayload(visitId))) || {};
    const teamMembers = prev.teamMembers || [];
    const companion = teamMembers.find((member) => member.userId === request.doubleVisitWithId);
    const isDoubleVisit = request.isDoubleVisit === true;
    const priorStatus = prev.visit?.status || prev.visit?.Status__c;
    const priorType = prev.visit?.visitType || prev.visit?.Visit_Type__c;
    const completingAsUnplanned =
        request.status === 'Completed' && priorStatus !== 'Scheduled';
    const didNotMeetHcp = request.didNotMeetHcp === true;
    const startDateTime = request.startDateTime || prev.visit?.startDateTime || null;
    const endDateTime = request.endDateTime || prev.visit?.endDateTime || null;
    const payload = {
        visit: {
            ...(prev.visit || {}),
            id: visitId,
            status: request.status,
            startDateTime,
            endDateTime,
            durationLabel: formatDurationLabel(startDateTime, endDateTime),
            visitType: completingAsUnplanned ? 'Unplanned' : priorType,
            visitObjective: request.visitObjective,
            visitNotes: request.visitNotes,
            clmPresentation: request.clmPresentation || null,
            nextVisitDate: request.nextVisitDate || null,
            cancellationReason: request.cancellationReason || null,
            didNotMeetHcp,
            metInsteadType: didNotMeetHcp ? request.metInsteadType || null : null,
            metInsteadName: didNotMeetHcp ? request.metInsteadName || null : null,
            isDoubleVisit,
            doubleVisitWithId: isDoubleVisit ? request.doubleVisitWithId || null : null,
            doubleVisitWithName: isDoubleVisit
                ? companion?.name || prev.visit?.doubleVisitWithName || null
                : null
        },
        attendees: request.attendees || [],
        products: request.products || [],
        samples: request.samples || [],
        teamMembers: prev.teamMembers || [],
        clmSessions: prev.clmSessions || []
    };

    if (visitId) {
        await putVisitPayload(visitId, payload);
        await queueOfflineAction({
            actionType: 'SAVE_CALL_REPORT',
            visitId,
            clientActionKey: `save_call_${visitId}`,
            callReportJson: requestJson
        });
    }
    return payload;
}
