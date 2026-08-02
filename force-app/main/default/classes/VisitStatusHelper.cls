public with sharing class VisitStatusHelper {
    public class RepairResult {
        @AuraEnabled public Integer futureCompletedReset;
        @AuraEnabled public Integer cancelledReasonFilled;
        @AuraEnabled public String message;

        public RepairResult() {
            futureCompletedReset = 0;
            cancelledReasonFilled = 0;
        }
    }

    public static Date visitDay(DateTime startDateTime) {
        return startDateTime == null ? null : startDateTime.date();
    }

    public static Boolean isFutureVisitDay(DateTime startDateTime) {
        Date day = visitDay(startDateTime);
        return day != null && day > Date.today();
    }

    public static void validateStatusChange(String status, DateTime startDateTime, String cancellationReason) {
        if (String.isBlank(status)) {
            return;
        }
        if ('Cancelled' == status && String.isBlank(cancellationReason)) {
            throw new AuraHandledException('Cancellation reason is required when cancelling a visit.');
        }
        if ('Completed' == status && isFutureVisitDay(startDateTime)) {
            throw new AuraHandledException('A visit cannot be marked Completed before its scheduled date.');
        }
    }

    /**
     * Demo seed helper: past visits may be Completed or Cancelled; today/future stay open.
     */
    public static String resolveDemoStatus(Date visitDay, Integer slotIndex) {
        Integer slot = slotIndex == null ? 0 : slotIndex;
        if (visitDay == null) {
            return 'Draft';
        }
        if (visitDay > Date.today()) {
            return Math.mod(slot, 3) == 0 ? 'Draft' : 'Scheduled';
        }
        if (visitDay == Date.today()) {
            return 'Scheduled';
        }
        return Math.mod(slot, 7) == 0 ? 'Cancelled' : 'Completed';
    }

    public static String defaultCancellationReason() {
        return 'HCP unavailable — visit rescheduled.';
    }

    public static void applyCancelledReason(Visit__c visit) {
        if (visit != null && visit.Status__c == 'Cancelled' && String.isBlank(visit.Cancellation_Reason__c)) {
            visit.Cancellation_Reason__c = defaultCancellationReason();
        }
    }

    /**
     * Repairs org data: future-dated Completed visits become Scheduled;
     * Cancelled visits missing a reason get a default reason.
     */
    public static RepairResult repairInvalidVisitStatuses() {
        RepairResult result = new RepairResult();
        DateTime nextDayStart = DateTime.newInstance(Date.today().addDays(1), Time.newInstance(0, 0, 0, 0));

        List<Visit__c> futureCompleted = [
            SELECT Id, Status__c, Start_Date__c
            FROM Visit__c
            WHERE Status__c = 'Completed' AND Start_Date__c >= :nextDayStart
            WITH SYSTEM_MODE
            LIMIT 10000
        ];
        for (Visit__c visit : futureCompleted) {
            visit.Status__c = 'Scheduled';
            visit.Cancellation_Reason__c = null;
        }
        if (!futureCompleted.isEmpty()) {
            update as system futureCompleted;
            result.futureCompletedReset = futureCompleted.size();
        }

        List<Visit__c> cancelledVisits = [
            SELECT Id, Status__c, Cancellation_Reason__c
            FROM Visit__c
            WHERE Status__c = 'Cancelled'
            WITH SYSTEM_MODE
            LIMIT 10000
        ];
        List<Visit__c> cancelledMissingReason = new List<Visit__c>();
        for (Visit__c visit : cancelledVisits) {
            if (String.isBlank(visit.Cancellation_Reason__c)) {
                visit.Cancellation_Reason__c = defaultCancellationReason();
                cancelledMissingReason.add(visit);
            }
        }
        if (!cancelledMissingReason.isEmpty()) {
            update as system cancelledMissingReason;
            result.cancelledReasonFilled = cancelledMissingReason.size();
        }

        result.message = 'Reset ' + result.futureCompletedReset +
            ' future Completed visit(s) and filled ' + result.cancelledReasonFilled +
            ' missing cancellation reason(s).';
        return result;
    }
}
