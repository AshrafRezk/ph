/**
 * Shared logic for list-view bulk approve/reject of Time_Off_Request__c.
 * Invocable entry points: {@link TimeOffRequestBulkApprove}, {@link TimeOffRequestBulkReject}.
 */
public with sharing class TimeOffRequestBulkApproval {

    public class Result {
        public Integer processedCount;
        public Integer skippedCount;
        public String message;
    }

    public static List<String> mergeIdInputs(List<String> recordIds, String recordId) {
        List<String> effective = new List<String>();
        if (recordIds != null) {
            for (String s : recordIds) {
                if (String.isNotBlank(s)) {
                    effective.add(s);
                }
            }
        }
        if (String.isNotBlank(recordId)) {
            effective.add(recordId.trim());
        }
        return effective;
    }

    public static Result runApprove(List<String> rawIds) {
        Result summary = baseResult();
        if (rawIds == null || rawIds.isEmpty()) {
            summary.message = 'No records selected.';
            return summary;
        }
        Set<Id> idSet = parseIds(rawIds);
        if (idSet.isEmpty()) {
            summary.message = 'No valid record Ids.';
            return summary;
        }
        String me = UserInfo.getUserId();
        List<Time_Off_Request__c> rows = [
            SELECT Id, Stage__c, CreatedBy.ManagerId
            FROM Time_Off_Request__c
            WHERE Id IN :idSet
        ];
        List<Time_Off_Request__c> toUpdate = new List<Time_Off_Request__c>();
        for (Time_Off_Request__c r : rows) {
            if (isEligible(me, r)) {
                toUpdate.add(new Time_Off_Request__c(Id = r.Id, Stage__c = 'Approved'));
            } else {
                summary.skippedCount++;
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
            summary.processedCount = toUpdate.size();
        }
        summary.message = buildMessage('Approved', summary.processedCount, summary.skippedCount);
        return summary;
    }

    public static Result runReject(List<String> rawIds, String rejectionReason) {
        Result summary = baseResult();
        if (rawIds == null || rawIds.isEmpty()) {
            summary.message = 'No records selected.';
            return summary;
        }
        if (String.isBlank(rejectionReason)) {
            summary.message = 'Rejection reason is required.';
            summary.skippedCount = rawIds.size();
            return summary;
        }
        Set<Id> idSet = parseIds(rawIds);
        if (idSet.isEmpty()) {
            summary.message = 'No valid record Ids.';
            return summary;
        }
        String me = UserInfo.getUserId();
        List<Time_Off_Request__c> rows = [
            SELECT Id, Stage__c, CreatedBy.ManagerId
            FROM Time_Off_Request__c
            WHERE Id IN :idSet
        ];
        List<Time_Off_Request__c> toUpdate = new List<Time_Off_Request__c>();
        String trimmedReason = rejectionReason.trim();
        for (Time_Off_Request__c r : rows) {
            if (isEligible(me, r)) {
                toUpdate.add(
                    new Time_Off_Request__c(
                        Id = r.Id,
                        Stage__c = 'Rejected',
                        Rejection_Reason__c = trimmedReason
                    )
                );
            } else {
                summary.skippedCount++;
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
            summary.processedCount = toUpdate.size();
        }
        summary.message = buildMessage('Rejected', summary.processedCount, summary.skippedCount);
        return summary;
    }

    private static Result baseResult() {
        Result r = new Result();
        r.processedCount = 0;
        r.skippedCount = 0;
        return r;
    }

    private static Set<Id> parseIds(List<String> rawIds) {
        Set<Id> idSet = new Set<Id>();
        for (String s : rawIds) {
            if (String.isBlank(s)) {
                continue;
            }
            try {
                idSet.add((Id) s.trim());
            } catch (Exception e) {
                // skip invalid
            }
        }
        return idSet;
    }

    private static Boolean isEligible(String runningUserId, Time_Off_Request__c r) {
        if (r.Stage__c != 'Submitted for Approval') {
            return false;
        }
        if (r.CreatedBy.ManagerId == null) {
            return false;
        }
        return String.valueOf(runningUserId).equalsIgnoreCase(String.valueOf(r.CreatedBy.ManagerId));
    }

    private static String buildMessage(String verb, Integer processed, Integer skipped) {
        return verb + ' ' + processed + ' request(s). Skipped ' + skipped
            + ' (wrong stage, not the creator\'s manager, or no manager on file).';
    }
}