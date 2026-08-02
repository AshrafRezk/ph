public with sharing class TimeOffRequestTOTRecalcByRange {
    public class RecalcTOTByRangeRequest {
        @InvocableVariable(required=true label='User Id')
        public Id userId;
        @InvocableVariable(required=true label='Start Date Time')
        public DateTime startDateTime;
        @InvocableVariable(required=true label='End Date Time')
        public DateTime endDateTime;
    }

    @InvocableMethod(label='Recalc Time Card TOT for Date Range' description='Recalculates TOT day entries for a user and date range (e.g. after a time-off request is deleted).')
    public static void recalcTOTForDateRange(List<RecalcTOTByRangeRequest> requests) {
        if (requests == null || requests.isEmpty()) return;
        RecalcTOTByRangeRequest r = requests[0];
        if (r.userId == null || r.startDateTime == null || r.endDateTime == null) return;
        Date startDate = r.startDateTime.date();
        Date endDate = r.endDateTime.date();
        if (startDate > endDate) return;
        EmployeeTimeCardFlowHelper.recalcTOTForEmployeeAndRange(r.userId, startDate, endDate);
    }
}