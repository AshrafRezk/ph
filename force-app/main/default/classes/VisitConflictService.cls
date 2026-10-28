public with sharing class VisitConflictService {
    /**
     * Time off the planner shows on the calendar (draft, submitted, approved) blocks visits in that slot.
     * Same stages and owner match as FieldPlannerController.queryTimeOff.
     */
    private static final List<String> BLOCKING_TOT_STAGES = new List<String>{
        'Draft',
        'Submitted for Approval',
        'Approved'
    };

    public static void assertNoConflicts(
        Id assignedToUserId,
        DateTime startDateTime,
        DateTime endDateTime,
        Id excludeVisitId
    ) {
        assertNoConflicts(assignedToUserId, startDateTime, endDateTime, excludeVisitId, false);
    }

    public static void assertNoConflicts(
        Id assignedToUserId,
        DateTime startDateTime,
        DateTime endDateTime,
        Id excludeVisitId,
        Boolean acknowledgeWarnings
    ) {
        if (assignedToUserId == null || startDateTime == null || endDateTime == null) {
            return;
        }
        WorkingCalendarUtil.setAcknowledgeWarnings(acknowledgeWarnings);
        try {
            WorkingCalendarUtil.assertWorkingDayForUser(startDateTime, assignedToUserId);
            assertNoTotConflict(assignedToUserId, startDateTime, endDateTime, acknowledgeWarnings);
            assertNoVisitConflict(assignedToUserId, startDateTime, endDateTime, excludeVisitId, acknowledgeWarnings);
            assertNoMeetingConflict(assignedToUserId, startDateTime, endDateTime, acknowledgeWarnings);
        } finally {
            WorkingCalendarUtil.setAcknowledgeWarnings(false);
        }
    }

    /**
     * Overlap checks for many visits in two queries. Working-day rules stay with the caller.
     * Map values are the same messages assertNoConflicts throws (Block only).
     */
    public static Map<Id, String> findConflictMessages(List<Visit__c> candidates) {
        Map<Id, String> messages = new Map<Id, String>();
        if (candidates == null || candidates.isEmpty()) {
            return messages;
        }

        Set<Id> userIds = new Set<Id>();
        DateTime rangeStart;
        DateTime rangeEnd;
        List<Visit__c> scoped = new List<Visit__c>();
        for (Visit__c candidate : candidates) {
            if (
                candidate == null ||
                candidate.Id == null ||
                candidate.Assigned_To__c == null ||
                candidate.Start_Date__c == null ||
                candidate.End_Date__c == null
            ) {
                continue;
            }
            scoped.add(candidate);
            userIds.add(candidate.Assigned_To__c);
            if (rangeStart == null || candidate.Start_Date__c < rangeStart) {
                rangeStart = candidate.Start_Date__c;
            }
            if (rangeEnd == null || candidate.End_Date__c > rangeEnd) {
                rangeEnd = candidate.End_Date__c;
            }
        }
        if (scoped.isEmpty()) {
            return messages;
        }

        List<Time_Off_Request__c> blocks = [
            SELECT Id, Name, Type__c, Stage__c, CreatedById, OwnerId, Start_Date_Time__c, End_Date_Time__c
            FROM Time_Off_Request__c
            WHERE
                (CreatedById IN :userIds OR OwnerId IN :userIds)
                AND Stage__c IN :BLOCKING_TOT_STAGES
                AND Start_Date_Time__c < :rangeEnd
                AND End_Date_Time__c > :rangeStart
            WITH USER_MODE
        ];
        List<Visit__c> overlaps = [
            SELECT Id, Name, Status__c, Assigned_To__c, Start_Date__c, End_Date__c
            FROM Visit__c
            WHERE
                Assigned_To__c IN :userIds
                AND Status__c NOT IN ('Cancelled')
                AND Start_Date__c < :rangeEnd
                AND End_Date__c > :rangeStart
            WITH USER_MODE
        ];

        for (Visit__c candidate : scoped) {
            String message = firstConflictMessage(candidate, blocks, overlaps);
            if (message != null) {
                messages.put(candidate.Id, message);
            }
        }
        return messages;
    }

    private static String firstConflictMessage(
        Visit__c candidate,
        List<Time_Off_Request__c> blocks,
        List<Visit__c> overlaps
    ) {
        // Overlap policies come from the assigned rep's Planner Rules, not the running user's.
        Id repId = candidate.Assigned_To__c;
        if (PlannerRulesService.policyForUser('Visit_Tot', repId) != PlannerRulesService.ALLOW) {
            for (Time_Off_Request__c block : blocks) {
                if (block.CreatedById != candidate.Assigned_To__c && block.OwnerId != candidate.Assigned_To__c) {
                    continue;
                }
                if (rangesOverlap(
                    block.Start_Date_Time__c,
                    block.End_Date_Time__c,
                    candidate.Start_Date__c,
                    candidate.End_Date__c
                )) {
                    if (PlannerRulesService.policyForUser('Visit_Tot', repId) == PlannerRulesService.BLOCK) {
                        return totConflictMessage(block);
                    }
                }
            }
        }
        if (PlannerRulesService.policyForUser('Visit_Visit', repId) != PlannerRulesService.ALLOW) {
            for (Visit__c overlap : overlaps) {
                if (overlap.Id == candidate.Id || overlap.Assigned_To__c != candidate.Assigned_To__c) {
                    continue;
                }
                if (rangesOverlap(
                    overlap.Start_Date__c,
                    overlap.End_Date__c,
                    candidate.Start_Date__c,
                    candidate.End_Date__c
                )) {
                    if (PlannerRulesService.policyForUser('Visit_Visit', repId) == PlannerRulesService.BLOCK) {
                        return visitConflictMessage(overlap);
                    }
                }
            }
        }
        return null;
    }

    private static Boolean rangesOverlap(
        DateTime startA,
        DateTime endA,
        DateTime startB,
        DateTime endB
    ) {
        return startA != null && endA != null && startB != null && endB != null
            && startA < endB && endA > startB;
    }

    private static String totConflictMessage(Time_Off_Request__c block) {
        String typeLabel = String.isBlank(block.Type__c) ? 'Time off' : block.Type__c;
        return 'This time overlaps with ' +
            typeLabel +
            ' (' +
            block.Stage__c +
            '). Choose another slot or adjust time off first.';
    }

    private static String visitConflictMessage(Visit__c overlap) {
        return 'This time overlaps with visit ' +
            overlap.Name +
            ' (' +
            overlap.Status__c +
            ').';
    }

    private static String meetingConflictMessage(Meeting__c meeting) {
        String label = String.isBlank(meeting.Name) ? 'a meeting' : meeting.Name;
        return 'This time overlaps with ' + label + '.';
    }

    private static void assertNoTotConflict(
        Id assignedToUserId,
        DateTime startDateTime,
        DateTime endDateTime,
        Boolean acknowledgeWarnings
    ) {
        if (PlannerRulesService.policyForUser('Visit_Tot', assignedToUserId) == PlannerRulesService.ALLOW) {
            return;
        }
        List<Time_Off_Request__c> blocks = [
            SELECT Id, Name, Type__c, Stage__c, Start_Date_Time__c, End_Date_Time__c
            FROM Time_Off_Request__c
            WHERE
                (CreatedById = :assignedToUserId OR OwnerId = :assignedToUserId)
                AND Stage__c IN :BLOCKING_TOT_STAGES
                AND Start_Date_Time__c < :endDateTime
                AND End_Date_Time__c > :startDateTime
            WITH USER_MODE
            LIMIT 1
        ];
        if (!blocks.isEmpty()) {
            PlannerRulesService.enforceForUser('Visit_Tot', totConflictMessage(blocks[0]), acknowledgeWarnings, assignedToUserId);
        }
    }

    private static void assertNoVisitConflict(
        Id assignedToUserId,
        DateTime startDateTime,
        DateTime endDateTime,
        Id excludeVisitId,
        Boolean acknowledgeWarnings
    ) {
        if (PlannerRulesService.policyForUser('Visit_Visit', assignedToUserId) == PlannerRulesService.ALLOW) {
            return;
        }
        List<Visit__c> overlaps = [
            SELECT Id, Name, Status__c, Start_Date__c, End_Date__c
            FROM Visit__c
            WHERE
                Assigned_To__c = :assignedToUserId
                AND Status__c NOT IN ('Cancelled')
                AND Start_Date__c < :endDateTime
                AND End_Date__c > :startDateTime
                AND Id != :excludeVisitId
            WITH USER_MODE
            LIMIT 1
        ];
        if (!overlaps.isEmpty()) {
            PlannerRulesService.enforceForUser('Visit_Visit', visitConflictMessage(overlaps[0]), acknowledgeWarnings, assignedToUserId);
        }
    }

    private static void assertNoMeetingConflict(
        Id assignedToUserId,
        DateTime startDateTime,
        DateTime endDateTime,
        Boolean acknowledgeWarnings
    ) {
        if (PlannerRulesService.policyForUser('Visit_Meeting', assignedToUserId) == PlannerRulesService.ALLOW) {
            return;
        }
        try {
            List<Meeting__c> meetings = [
                SELECT Id, Name, Start_Date_Time__c, End_Date_Time__c
                FROM Meeting__c
                WHERE
                    OwnerId = :assignedToUserId
                    AND Status__c NOT IN ('Cancelled', 'Closed')
                    AND Start_Date_Time__c < :endDateTime
                    AND End_Date_Time__c > :startDateTime
                WITH USER_MODE
                LIMIT 1
            ];
            if (!meetings.isEmpty()) {
                PlannerRulesService.enforceForUser(
                    'Visit_Meeting',
                    meetingConflictMessage(meetings[0]),
                    acknowledgeWarnings,
                    assignedToUserId
                );
            }
        } catch (Exception e) {
            // Meeting End_Date_Time may be missing in some orgs; skip soft.
        }
    }
}
