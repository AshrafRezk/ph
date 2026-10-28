/**
 * Shared TOT compute / overlap / visit-conflict helpers.
 * Replaces missing before-save flow logic for end datetime, duration, and Overlap__c.
 */
public with sharing class TimeOffRequestService {
    public static final String STAGE_DRAFT = 'Draft';
    public static final String STAGE_SUBMITTED = 'Submitted for Approval';
    public static final String STAGE_APPROVED = 'Approved';
    public static final String STAGE_REJECTED = 'Rejected';

    private static final Set<String> BLOCKING_STAGES = new Set<String>{
        STAGE_SUBMITTED,
        STAGE_APPROVED
    };

    public static void applyComputedFields(List<Time_Off_Request__c> records) {
        if (records == null || records.isEmpty()) {
            return;
        }
        for (Time_Off_Request__c request : records) {
            applyComputedFields(request);
        }
    }

    public static void applyComputedFields(Time_Off_Request__c request) {
        if (request == null || request.Start_Date_Time__c == null || String.isBlank(request.Span_Type__c)) {
            return;
        }

        if (request.Span_Type__c == 'Hours') {
            Decimal hours = resolveDurationNumber(request);
            if (hours == null) {
                return;
            }
            request.Span_Duration__c = hours;
            if (String.isBlank(request.Span_Duration_Select__c)) {
                request.Span_Duration_Select__c = String.valueOf(hours.intValue());
            }
            request.End_Date_Time__c = request.Start_Date_Time__c.addSeconds(Integer.valueOf(hours * 3600));
            return;
        }

        if (request.Span_Type__c == 'Half_Day') {
            Date day = request.Start_Date_Time__c.date();
            request.Start_Date_Time__c = DateTime.newInstance(day, Time.newInstance(9, 0, 0, 0));
            request.End_Date_Time__c = DateTime.newInstance(day, Time.newInstance(13, 0, 0, 0));
            request.Span_Duration__c = 0.5;
            request.Span_Duration_Select__c = null;
            return;
        }

        if (request.Span_Type__c == 'Full_Day') {
            Date day = request.Start_Date_Time__c.date();
            request.Start_Date_Time__c = DateTime.newInstance(day, Time.newInstance(9, 0, 0, 0));
            request.End_Date_Time__c = DateTime.newInstance(day, Time.newInstance(17, 0, 0, 0));
            request.Span_Duration__c = 1;
            request.Span_Duration_Select__c = null;
            return;
        }

        if (request.Span_Type__c == 'Days') {
            Decimal days = resolveDurationNumber(request);
            if (days == null || days < 1) {
                return;
            }
            Integer dayCount = days.intValue();
            Date startDay = request.Start_Date_Time__c.date();
            if (!WorkingCalendarUtil.isWorkingDay(startDay)) {
                String message =
                    'Multi-day time off must start on a working day (Saturday through Wednesday).';
                if (Trigger.isExecuting) {
                    request.addError(message);
                } else {
                    throw new AuraHandledException(message);
                }
                return;
            }
            Date endDay = endWorkingDayInclusive(startDay, dayCount);
            request.Start_Date_Time__c = DateTime.newInstance(startDay, Time.newInstance(9, 0, 0, 0));
            request.End_Date_Time__c = DateTime.newInstance(endDay, Time.newInstance(17, 0, 0, 0));
            request.Span_Duration__c = dayCount;
            // Org dependent-picklist may only allow Span_Duration_Select under Hours.
        }
    }

    public static void evaluateOverlaps(List<Time_Off_Request__c> records) {
        if (records == null || records.isEmpty()) {
            return;
        }

        Set<Id> ownerIds = new Set<Id>();
        DateTime rangeStart;
        DateTime rangeEnd;
        for (Time_Off_Request__c request : records) {
            Id ownerId = resolveOwnerUserId(request);
            if (ownerId != null) {
                ownerIds.add(ownerId);
            }
            if (request.Start_Date_Time__c != null) {
                rangeStart = rangeStart == null || request.Start_Date_Time__c < rangeStart
                    ? request.Start_Date_Time__c
                    : rangeStart;
            }
            if (request.End_Date_Time__c != null) {
                rangeEnd = rangeEnd == null || request.End_Date_Time__c > rangeEnd
                    ? request.End_Date_Time__c
                    : rangeEnd;
            }
        }
        if (ownerIds.isEmpty() || rangeStart == null || rangeEnd == null) {
            for (Time_Off_Request__c request : records) {
                request.Overlap__c = false;
            }
            return;
        }

        Map<Id, List<Time_Off_Request__c>> existingByOwner = new Map<Id, List<Time_Off_Request__c>>();
        for (Time_Off_Request__c existing : [
            SELECT Id, CreatedById, OwnerId, Stage__c, Start_Date_Time__c, End_Date_Time__c
            FROM Time_Off_Request__c
            WHERE
                (CreatedById IN :ownerIds OR OwnerId IN :ownerIds)
                AND Stage__c IN :BLOCKING_STAGES
                AND Start_Date_Time__c < :rangeEnd
                AND End_Date_Time__c > :rangeStart
            WITH SYSTEM_MODE
        ]) {
            for (Id ownerId : new Set<Id>{ existing.CreatedById, existing.OwnerId }) {
                if (ownerId == null || !ownerIds.contains(ownerId)) {
                    continue;
                }
                if (!existingByOwner.containsKey(ownerId)) {
                    existingByOwner.put(ownerId, new List<Time_Off_Request__c>());
                }
                existingByOwner.get(ownerId).add(existing);
            }
        }

        for (Time_Off_Request__c request : records) {
            request.Overlap__c = false;
            if (
                request.Start_Date_Time__c == null ||
                request.End_Date_Time__c == null ||
                !BLOCKING_STAGES.contains(request.Stage__c)
            ) {
                continue;
            }
            Id ownerId = resolveOwnerUserId(request);
            List<Time_Off_Request__c> candidates = existingByOwner.get(ownerId);
            if (candidates == null) {
                continue;
            }
            for (Time_Off_Request__c existing : candidates) {
                if (existing.Id != null && existing.Id == request.Id) {
                    continue;
                }
                if (
                    existing.Start_Date_Time__c < request.End_Date_Time__c &&
                    existing.End_Date_Time__c > request.Start_Date_Time__c
                ) {
                    request.Overlap__c = true;
                    break;
                }
            }
        }
    }

    public static void assertVisitConflicts(List<Time_Off_Request__c> records) {
        if (records == null || records.isEmpty()) {
            return;
        }
        for (Time_Off_Request__c request : records) {
            if (
                request.Start_Date_Time__c == null ||
                request.End_Date_Time__c == null ||
                !BLOCKING_STAGES.contains(request.Stage__c)
            ) {
                continue;
            }
            if (!TimeOffTypeCatalog.blocksVisits(request.Type__c)) {
                continue;
            }
            Id ownerId = resolveOwnerUserId(request);
            String conflictMessage = findVisitConflictMessage(
                ownerId,
                request.Start_Date_Time__c,
                request.End_Date_Time__c
            );
            if (String.isNotBlank(conflictMessage)) {
                request.addError(conflictMessage);
            }
        }
    }

    private static String findVisitConflictMessage(
        Id assignedToUserId,
        DateTime startDateTime,
        DateTime endDateTime
    ) {
        if (assignedToUserId == null || startDateTime == null || endDateTime == null) {
            return null;
        }
        List<Visit__c> overlaps = [
            SELECT Id, Name, Status__c
            FROM Visit__c
            WHERE
                Assigned_To__c = :assignedToUserId
                AND Status__c NOT IN ('Cancelled')
                AND Start_Date__c < :endDateTime
                AND End_Date__c > :startDateTime
            WITH USER_MODE
            LIMIT 1
        ];
        if (overlaps.isEmpty()) {
            return null;
        }
        Visit__c overlap = overlaps[0];
        return 'This time overlaps with visit ' + overlap.Name + ' (' + overlap.Status__c + ').';
    }

    public static Id resolveOwnerUserId(Time_Off_Request__c request) {
        if (request == null) {
            return null;
        }
        if (request.CreatedById != null) {
            return request.CreatedById;
        }
        if (request.OwnerId != null && String.valueOf(request.OwnerId).startsWith('005')) {
            return request.OwnerId;
        }
        return UserInfo.getUserId();
    }

    private static Decimal resolveDurationNumber(Time_Off_Request__c request) {
        if (request.Span_Duration__c != null) {
            return request.Span_Duration__c;
        }
        if (String.isBlank(request.Span_Duration_Select__c)) {
            return null;
        }
        try {
            return Decimal.valueOf(request.Span_Duration_Select__c);
        } catch (Exception ex) {
            return null;
        }
    }

    private static Date endWorkingDayInclusive(Date startDate, Integer workingDayCount) {
        if (startDate == null || workingDayCount == null || workingDayCount <= 1) {
            return startDate;
        }
        return WorkingCalendarUtil.addWorkingDays(startDate, workingDayCount - 1);
    }
}