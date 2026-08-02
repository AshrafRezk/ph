public with sharing class TimeOffRequestTOTRecalc {
    public class RecalcTOTRequest {
        @InvocableVariable(required=true label='Time Off Request Id')
        public Id timeOffRequestId;
    }

    @InvocableMethod(label='Recalc Time Card TOT for Time-Off Request' description='After a time-off request is approved or changed, updates TOT_Days__c and TOT_Days_Excluding_Weekends__c on affected day entries.')
    public static void recalcTOTForTimeOffRequest(List<RecalcTOTRequest> requests) {
        if (requests == null || requests.isEmpty()) return;
        Id reqId = requests[0].timeOffRequestId;
        if (reqId == null) return;
        List<Time_Off_Request__c> reqs = [
            SELECT Id, CreatedById, OwnerId, Start_Date_Time__c, End_Date_Time__c
            FROM Time_Off_Request__c
            WHERE Id = :reqId
            LIMIT 1
        ];
        if (reqs.isEmpty()) return;
        Time_Off_Request__c req = reqs[0];
        Id employeeId = req.OwnerId != null ? req.OwnerId : req.CreatedById;
        if (employeeId == null || req.Start_Date_Time__c == null || req.End_Date_Time__c == null) return;
        Date startDate = req.Start_Date_Time__c.date();
        Date endDate = req.End_Date_Time__c.date();
        if (startDate > endDate) return;
        EmployeeTimeCardFlowHelper.recalcTOTForEmployeeAndRange(employeeId, startDate, endDate);
    }
}