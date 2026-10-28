public with sharing class TimeOffRequestTriggerHandler {
    public static void beforeInsert(List<Time_Off_Request__c> newRecords) {
        TimeOffRequestService.applyComputedFields(newRecords);
        TimeOffRequestService.evaluateOverlaps(newRecords);
        TimeOffRequestService.assertVisitConflicts(newRecords);
    }

    public static void beforeUpdate(
        List<Time_Off_Request__c> newRecords,
        Map<Id, Time_Off_Request__c> oldMap
    ) {
        TimeOffRequestService.applyComputedFields(newRecords);
        TimeOffRequestService.evaluateOverlaps(newRecords);
        TimeOffRequestService.assertVisitConflicts(newRecords);
    }

    public static void afterInsert(List<Time_Off_Request__c> newRecords) {
        recalcApproved(newRecords, null);
        enqueueMendixSync(newRecords, null);
    }

    public static void afterUpdate(
        List<Time_Off_Request__c> newRecords,
        Map<Id, Time_Off_Request__c> oldMap
    ) {
        recalcApproved(newRecords, oldMap);
        enqueueMendixSync(newRecords, oldMap);
    }

    private static void recalcApproved(
        List<Time_Off_Request__c> newRecords,
        Map<Id, Time_Off_Request__c> oldMap
    ) {
        // Recalc is handled by TimeOffRequestTOTRecalc flow + org EmployeeTimeCardFlowHelper.
        // Keep trigger free of EmployeeTimeCardFlowHelper coupling (org/local drift).
    }

    private static void enqueueMendixSync(
        List<Time_Off_Request__c> newRecords,
        Map<Id, Time_Off_Request__c> oldMap
    ) {
        Set<Id> toSync = new Set<Id>();
        for (Time_Off_Request__c request : newRecords) {
            Time_Off_Request__c prior = oldMap == null ? null : oldMap.get(request.Id);
            Boolean submittedNow =
                request.Stage__c == TimeOffRequestService.STAGE_SUBMITTED &&
                (prior == null || prior.Stage__c != TimeOffRequestService.STAGE_SUBMITTED);
            if (submittedNow) {
                toSync.add(request.Id);
            }
        }
        if (!toSync.isEmpty()) {
            MendixSyncService.enqueueTimeOffOutbound(toSync);
        }
    }
}