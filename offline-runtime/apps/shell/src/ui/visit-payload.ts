/** Pharma Visit__c field mapping (org uses Start_Date__c / End_Date__c, not StartDateTime__c). */

export const VISIT_TYPE_DEFAULT = 'Planned (Automatically)';
export const VISIT_STATUS_DRAFT = 'Draft';

export function visitStartIso(record: Record<string, unknown>): string | undefined {
  const raw =
    record.Start_Date__c ??
    record.StartDateTime__c ??
    record.Visit_Date__c ??
    record.Planned_Date__c;
  if (raw == null || raw === '') return undefined;
  const s = String(raw);
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return `${s}T09:00:00.000Z`;
  return s;
}

export function visitEndIso(record: Record<string, unknown>, start?: Date): string | undefined {
  const raw = record.End_Date__c ?? record.EndDateTime__c;
  if (raw != null && raw !== '') return String(raw);
  if (start && !Number.isNaN(start.getTime())) {
    return new Date(start.getTime() + 60 * 60 * 1000).toISOString();
  }
  return undefined;
}

/** Build a Visit__c SQLite / outbox payload with org-correct datetime fields. */
export function buildVisitPayload(
  base: Record<string, unknown>,
  opts: {
    start: Date;
    end: Date;
    assignedToUserId?: string | null;
    status?: string;
  }
): Record<string, unknown> {
  const startIso = opts.start.toISOString();
  const endIso = opts.end.toISOString();
  const payload: Record<string, unknown> = { ...base };
  delete payload.StartDateTime__c;
  delete payload.EndDateTime__c;
  delete payload.Planned_Date__c;
  delete payload.Name;
  payload.Start_Date__c = startIso;
  payload.End_Date__c = endIso;
  payload.Visit_Date__c = startIso;
  payload.Status__c = opts.status ?? payload.Status__c ?? VISIT_STATUS_DRAFT;
  payload.Visit_Type__c = payload.Visit_Type__c ?? VISIT_TYPE_DEFAULT;
  if (opts.assignedToUserId) {
    payload.Assigned_To__c = opts.assignedToUserId;
  }
  return payload;
}

/** Shift visit datetimes on an existing record (+1 day for postpone). */
export function shiftVisitPayload(
  existing: Record<string, unknown>,
  visitId: string,
  shiftDays: number,
  assignedToUserId?: string | null
): Record<string, unknown> {
  const startRaw = visitStartIso(existing);
  const start = startRaw ? new Date(startRaw) : new Date();
  if (Number.isNaN(start.getTime())) {
    return { ...existing, Id: visitId };
  }
  start.setDate(start.getDate() + shiftDays);
  const endRaw = visitEndIso(existing, start);
  const end = endRaw ? new Date(endRaw) : new Date(start.getTime() + 60 * 60 * 1000);
  if (!Number.isNaN(end.getTime())) {
    end.setDate(end.getDate() + shiftDays);
  }
  return buildVisitPayload(
    { ...existing, Id: visitId },
    { start, end: Number.isNaN(end.getTime()) ? new Date(start.getTime() + 60 * 60 * 1000) : end, assignedToUserId }
  );
}
