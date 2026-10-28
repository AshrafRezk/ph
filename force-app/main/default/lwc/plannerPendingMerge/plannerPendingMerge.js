/**
 * Pure overlay of the offline outbox onto a planner week.
 * Client keys look like visit_<uuid> / tot_<uuid> / meeting_<uuid> and are not Salesforce ids.
 */

const SALESFORCE_ID = /^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/;

export function isSalesforceId(value) {
    return SALESFORCE_ID.test(String(value || '').trim());
}

export function salesforceIdOrNull(value) {
    const raw = String(value || '').trim();
    return isSalesforceId(raw) ? raw : null;
}

export function parseActionPayload(raw) {
    if (!raw) {
        return {};
    }
    if (typeof raw === 'object') {
        return raw;
    }
    try {
        return JSON.parse(raw);
    } catch (_err) {
        return {};
    }
}

function labelWithoutOfflinePlaceholder(accountName, visitObjective) {
    const account = String(accountName || '').trim();
    if (account && !/^offline visit$/i.test(account)) {
        return account;
    }
    const objective = String(visitObjective || '').trim();
    if (objective && !/^offline visit$/i.test(objective)) {
        return objective;
    }
    return 'Visit';
}

function asVisitDto(id, payload, existing = {}) {
    return {
        ...existing,
        id,
        name: labelWithoutOfflinePlaceholder(existing.name || payload.accountName, payload.visitObjective),
        accountId: payload.accountId || existing.accountId || null,
        accountName: labelWithoutOfflinePlaceholder(
            payload.accountName || existing.accountName,
            payload.visitObjective
        ),
        status: payload.status || existing.status || 'Draft',
        visitType: payload.visitType || existing.visitType,
        startDateTime: payload.startDateTime || existing.startDateTime,
        endDateTime: payload.endDateTime || existing.endDateTime,
        visitObjective: payload.visitObjective || existing.visitObjective,
        zetaProjectId: payload.zetaProjectId || existing.zetaProjectId,
        cancellationReason: payload.cancellationReason || existing.cancellationReason,
        clientVisitKey: payload.clientVisitKey || existing.clientVisitKey || id
    };
}

function visitIdFromAction(row, payload) {
    return String(payload?.visitId || row.visitId || row.clientVisitKey || '');
}

function idsToDrop(row, payload) {
    return [payload?.visitId, row.visitId, row.clientVisitKey, payload?.clientVisitKey].filter(Boolean).map(String);
}

function totEndFromBody(body) {
    if (body.endDateTime) {
        return body.endDateTime;
    }
    const start = body.startDateTime;
    if (!start) {
        return start;
    }
    if (body.spanType === 'Full_Day') {
        const dayEnd = new Date(start);
        if (Number.isNaN(dayEnd.getTime())) {
            return start;
        }
        dayEnd.setHours(17, 0, 0, 0);
        return dayEnd.toISOString();
    }
    const hours = Number(body.durationHours || 2);
    const end = new Date(new Date(start).getTime() + hours * 3600 * 1000);
    return Number.isNaN(end.getTime()) ? start : end.toISOString();
}

function totDto(id, body, existing = {}) {
    return {
        ...existing,
        id,
        name: body.typeValue || existing.name,
        typeLabel: body.typeValue || existing.typeLabel,
        typeValue: body.typeValue || existing.typeValue,
        startDateTime: body.startDateTime || existing.startDateTime,
        endDateTime: totEndFromBody({ ...existing, ...body }),
        spanType: body.spanType || existing.spanType,
        stage: body.stage || existing.stage || 'Draft',
        durationHours: body.durationHours || existing.durationHours,
        comments: body.comments ?? existing.comments
    };
}

function meetingDto(id, body, existing = {}) {
    const title = body.title || existing.title || existing.name || 'Meeting';
    return {
        ...existing,
        id,
        name: title,
        title,
        status: body.status || existing.status || 'Draft',
        startDateTime: body.startDateTime || existing.startDateTime,
        endDateTime: body.endDateTime || existing.endDateTime,
        recordTypeDeveloperName: body.recordTypeDeveloperName || existing.recordTypeDeveloperName,
        recordTypeLabel: body.recordTypeLabel || existing.recordTypeLabel,
        pharmaProjectId: body.pharmaProjectId || existing.pharmaProjectId || null
    };
}

/**
 * @param {object} payload week snapshot from cache or Salesforce
 * @param {Array} pending outbox rows, oldest first
 */
export function applyPendingActions(payload = {}, pending = []) {
    const visits = new Map((payload.visits || []).map((visit) => [String(visit.id), { ...visit }]));
    const timeOffBlocks = (payload.timeOffBlocks || payload.timeOff || []).map((block) => ({ ...block }));
    const meetings = (payload.meetings || []).map((meeting) => ({ ...meeting }));
    const deletedVisits = new Set();
    const deletedTots = new Set();
    const deletedMeetings = new Set();

    const dropVisit = (id) => {
        if (!id) {
            return;
        }
        const key = String(id);
        deletedVisits.add(key);
        visits.delete(key);
    };

    for (const row of pending || []) {
        const type = String(row.actionType || '');
        const body = parseActionPayload(row.payloadJson);
        if (type === 'DELETE_VISIT') {
            idsToDrop(row, body).forEach(dropVisit);
        } else if (type === 'UPSERT_VISIT') {
            const id = visitIdFromAction(row, body);
            if (!id || deletedVisits.has(id)) {
                continue;
            }
            visits.set(id, asVisitDto(id, { ...body, clientVisitKey: row.clientVisitKey || id }, visits.get(id) || {}));
        } else if (type === 'SUBMIT_VISIT') {
            const id = visitIdFromAction(row, body);
            if (!id || deletedVisits.has(id) || !visits.has(id)) {
                continue;
            }
            visits.set(id, { ...visits.get(id), status: 'Submitted' });
        } else if (type === 'RESCHEDULE_VISITS') {
            const ids = body.visitIds || [];
            const starts = body.startDateTimes || [];
            const ends = body.endDateTimes || [];
            ids.forEach((id, idx) => {
                const key = String(id);
                if (deletedVisits.has(key) || !visits.has(key)) {
                    return;
                }
                visits.set(key, {
                    ...visits.get(key),
                    startDateTime: starts[idx] || visits.get(key).startDateTime,
                    endDateTime: ends[idx] || visits.get(key).endDateTime
                });
            });
        } else if (type === 'DELETE_TIME_OFF') {
            const id = String(body.timeOffId || row.clientActionKey || '');
            if (id) {
                deletedTots.add(id);
            }
        } else if (type === 'CREATE_TIME_OFF' || type === 'UPDATE_TIME_OFF') {
            const id = String(body.timeOffId || row.clientActionKey || row.id || '');
            if (!id || deletedTots.has(id)) {
                continue;
            }
            const index = timeOffBlocks.findIndex((block) => String(block.id) === id);
            const next = totDto(id, body, index >= 0 ? timeOffBlocks[index] : {});
            if (index >= 0) {
                timeOffBlocks[index] = next;
            } else if (type === 'CREATE_TIME_OFF') {
                timeOffBlocks.push(next);
            }
        } else if (type === 'DELETE_MEETING') {
            const id = String(body.meetingId || row.clientActionKey || '');
            if (id) {
                deletedMeetings.add(id);
            }
        } else if (type === 'CREATE_MEETING' || type === 'UPDATE_MEETING') {
            const id = String(body.meetingId || row.clientActionKey || '');
            if (!id || deletedMeetings.has(id)) {
                continue;
            }
            const index = meetings.findIndex((meeting) => String(meeting.id) === id);
            const next = meetingDto(id, body, index >= 0 ? meetings[index] : {});
            if (index >= 0) {
                meetings[index] = next;
            } else if (type === 'CREATE_MEETING') {
                meetings.push(next);
            }
        }
    }

    return {
        ...payload,
        visits: Array.from(visits.values()).filter((visit) => !deletedVisits.has(String(visit.id))),
        timeOffBlocks: timeOffBlocks.filter((block) => !deletedTots.has(String(block.id))),
        timeOff: timeOffBlocks.filter((block) => !deletedTots.has(String(block.id))),
        meetings: meetings.filter((meeting) => !deletedMeetings.has(String(meeting.id)))
    };
}
