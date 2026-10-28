public with sharing class TimeOffRequestController {
    public class TimeOffRequestRow {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String typeLabel;
        @AuraEnabled
        public String spanType;
        @AuraEnabled
        public DateTime startDate;
        @AuraEnabled
        public DateTime endDate;
        @AuraEnabled
        public Decimal workingDays;
        @AuraEnabled
        public String stage;
    }

    public class ApprovalRow {
        @AuraEnabled
        public Id requestId;
        @AuraEnabled
        public String requestName;
        @AuraEnabled
        public String repName;
        @AuraEnabled
        public String typeLabel;
        @AuraEnabled
        public String spanType;
        @AuraEnabled
        public DateTime startDateTime;
        @AuraEnabled
        public DateTime endDateTime;
        @AuraEnabled
        public String stage;
    }

    @AuraEnabled(cacheable=true)
    public static List<TimeOffRequestRow> getMyRequests(Integer limitSize) {
        Integer safeLimit = limitSize == null || limitSize < 1 ? 10 : Math.min(limitSize, 50);
        List<TimeOffRequestRow> rows = new List<TimeOffRequestRow>();
        for (Time_Off_Request__c request : [
            SELECT
                Id,
                Name,
                Type__c,
                Span_Type__c,
                Start_Date_Time__c,
                End_Date_Time__c,
                Span_Duration__c,
                Stage__c
            FROM Time_Off_Request__c
            WHERE CreatedById = :UserInfo.getUserId()
            WITH USER_MODE
            ORDER BY Start_Date_Time__c DESC NULLS LAST
            LIMIT :safeLimit
        ]) {
            TimeOffRequestRow row = new TimeOffRequestRow();
            row.id = request.Id;
            row.name = request.Name;
            row.typeLabel = request.Type__c;
            row.spanType = request.Span_Type__c;
            row.startDate = request.Start_Date_Time__c;
            row.endDate = request.End_Date_Time__c;
            row.workingDays = workingDayEquivalent(request);
            row.stage = request.Stage__c;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<ApprovalRow> getPendingApprovals() {
        return TimeOffRequestApprovalAccess.getPendingApprovals(UserInfo.getUserId());
    }

    @AuraEnabled
    public static void approveRequest(Id requestId) {
        TimeOffRequestApprovalAccess.approveRequest(requestId, UserInfo.getUserId());
    }

    @AuraEnabled
    public static void rejectRequest(Id requestId, String rejectionReason) {
        TimeOffRequestApprovalAccess.rejectRequest(requestId, UserInfo.getUserId(), rejectionReason);
    }

    @AuraEnabled
    public static void recallRequest(Id requestId) {
        if (requestId == null) {
            throw new AuraHandledException('Request Id is required.');
        }
        Time_Off_Request__c request = [
            SELECT Id, Stage__c, CreatedById
            FROM Time_Off_Request__c
            WHERE Id = :requestId
            WITH USER_MODE
            LIMIT 1
        ];
        if (request.CreatedById != UserInfo.getUserId()) {
            throw new AuraHandledException('Only the creator can recall a request.');
        }
        if (request.Stage__c != TimeOffRequestService.STAGE_SUBMITTED) {
            throw new AuraHandledException('Only submitted requests can be recalled.');
        }
        request.Stage__c = TimeOffRequestService.STAGE_DRAFT;
        try {
            update as user request;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }

    /**
     * Creates TOT with Half Day / multi-day support without relying on FieldPlannerController.
     */
    @AuraEnabled
    public static TimeOffRequestRow createTimeOff(
        String typeValue,
        String spanType,
        String durationValue,
        DateTime startDateTime,
        String comments,
        String stage
    ) {
        if (String.isBlank(typeValue)) {
            throw new AuraHandledException('Select a time off type.');
        }
        if (!TimeOffTypeCatalog.isKnownType(typeValue)) {
            throw new AuraHandledException('Select a valid time off type.');
        }
        if (String.isBlank(spanType)) {
            throw new AuraHandledException('Select half day, full day, partial hours, or days.');
        }
        if (startDateTime == null) {
            throw new AuraHandledException('Start date/time is required.');
        }

        Time_Off_Request__c request = new Time_Off_Request__c();
        request.Type__c = typeValue;
        request.Span_Type__c = spanType;
        request.Start_Date_Time__c = startDateTime;
        request.Comments__c = comments;
        request.Stage__c = String.isBlank(stage) ? TimeOffRequestService.STAGE_DRAFT : stage;

        if (spanType == 'Hours') {
            if (String.isBlank(durationValue)) {
                throw new AuraHandledException('Select duration for partial time off.');
            }
            request.Span_Duration_Select__c = durationValue;
        } else if (spanType == 'Days') {
            if (String.isBlank(durationValue)) {
                throw new AuraHandledException('Select duration in days for multi-day time off.');
            }
            request.Span_Duration__c = Decimal.valueOf(durationValue);
        }

        TimeOffRequestService.applyComputedFields(request);
        try {
            insert as user request;
        } catch (DmlException e) {
            AuraHandledException ex = new AuraHandledException(e.getDmlMessage(0));
            ex.setMessage(e.getDmlMessage(0));
            throw ex;
        }

        Time_Off_Request__c saved = [
            SELECT
                Id,
                Name,
                Type__c,
                Span_Type__c,
                Start_Date_Time__c,
                End_Date_Time__c,
                Span_Duration__c,
                Stage__c
            FROM Time_Off_Request__c
            WHERE Id = :request.Id
            WITH USER_MODE
            LIMIT 1
        ];
        TimeOffRequestRow row = new TimeOffRequestRow();
        row.id = saved.Id;
        row.name = saved.Name;
        row.typeLabel = saved.Type__c;
        row.spanType = saved.Span_Type__c;
        row.startDate = saved.Start_Date_Time__c;
        row.endDate = saved.End_Date_Time__c;
        row.workingDays = workingDayEquivalent(saved);
        row.stage = saved.Stage__c;
        return row;
    }

    private static Decimal workingDayEquivalent(Time_Off_Request__c request) {
        if (request == null || String.isBlank(request.Span_Type__c)) {
            return null;
        }
        if (request.Span_Type__c == 'Hours' && request.Span_Duration__c != null) {
            return request.Span_Duration__c / 8;
        }
        if (request.Span_Type__c == 'Half_Day') {
            return 0.5;
        }
        return request.Span_Duration__c;
    }
}