/**
 * Re-runs Employee_time_tracking_Activity_Counts for every day entry
 * (refreshes planned/unplanned visit counts and time-off fields).
 *
 * Usage:
 *   Database.executeBatch(new EmployeeTimeCardActCountsBackfillBatch(), 25);
 */
public with sharing class EmployeeTimeCardActCountsBackfillBatch implements Database.Batchable<SObject> {

    @TestVisible
    private static final String FLOW_API_NAME = 'Employee_time_tracking_Activity_Counts';

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Date__c != NULL
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }
        for (SObject so : scope) {
            runActivityCountsFlow(so.Id);
        }
    }

    public void finish(Database.BatchableContext bc) {
    }

    public static void runActivityCountsFlow(Id dayCardId) {
        if (dayCardId == null) {
            return;
        }
        Map<String, Object> inputs = new Map<String, Object>();
        inputs.put('DAYCARDID', String.valueOf(dayCardId));
        Flow.Interview interview = Flow.Interview.createInterview(FLOW_API_NAME, inputs);
        interview.start();
    }
}