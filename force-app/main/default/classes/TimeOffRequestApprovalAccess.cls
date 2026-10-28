/**
 * Manager TOT approval access (private OWD bypass for creator's manager).
 */
public without sharing class TimeOffRequestApprovalAccess {
    public static List<TimeOffRequestController.ApprovalRow> getPendingApprovals(Id managerId) {
        if (managerId == null) {
            return new List<TimeOffRequestController.ApprovalRow>();
        }
        String submittedStage = TimeOffRequestService.STAGE_SUBMITTED;
        List<Time_Off_Request__c> candidates = [
            SELECT
                Id,
                Name,
                Type__c,
                Span_Type__c,
                Start_Date_Time__c,
                End_Date_Time__c,
                Stage__c,
                CreatedById
            FROM Time_Off_Request__c
            WHERE Stage__c = :submittedStage
            ORDER BY Start_Date_Time__c ASC
            LIMIT 200
        ];
        if (candidates.isEmpty()) {
            return new List<TimeOffRequestController.ApprovalRow>();
        }

        Set<Id> creatorIds = new Set<Id>();
        for (Time_Off_Request__c request : candidates) {
            if (request.CreatedById != null) {
                creatorIds.add(request.CreatedById);
            }
        }
        Map<Id, User> creatorsById = new Map<Id, User>(
            [
                SELECT Id, Name, ManagerId
                FROM User
                WHERE Id IN :creatorIds
            ]
        );

        List<TimeOffRequestController.ApprovalRow> rows = new List<TimeOffRequestController.ApprovalRow>();
        for (Time_Off_Request__c request : candidates) {
            User creator = creatorsById.get(request.CreatedById);
            if (creator == null || creator.ManagerId != managerId) {
                continue;
            }
            TimeOffRequestController.ApprovalRow row = new TimeOffRequestController.ApprovalRow();
            row.requestId = request.Id;
            row.requestName = request.Name;
            row.repName = creator.Name;
            row.typeLabel = request.Type__c;
            row.spanType = request.Span_Type__c;
            row.startDateTime = request.Start_Date_Time__c;
            row.endDateTime = request.End_Date_Time__c;
            row.stage = request.Stage__c;
            rows.add(row);
        }
        return rows;
    }

    public static void approveRequest(Id requestId, Id managerId) {
        Time_Off_Request__c request = loadForManager(requestId, managerId);
        if (request.Stage__c != TimeOffRequestService.STAGE_SUBMITTED) {
            throw new AuraHandledException('Only submitted requests can be approved.');
        }
        request.Stage__c = TimeOffRequestService.STAGE_APPROVED;
        request.Closure_Date__c = Date.today();
        try {
            update request;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }

    public static void rejectRequest(Id requestId, Id managerId, String rejectionReason) {
        if (String.isBlank(rejectionReason)) {
            throw new AuraHandledException('Rejection reason is required.');
        }
        Time_Off_Request__c request = loadForManager(requestId, managerId);
        if (request.Stage__c != TimeOffRequestService.STAGE_SUBMITTED) {
            throw new AuraHandledException('Only submitted requests can be rejected.');
        }
        request.Stage__c = TimeOffRequestService.STAGE_REJECTED;
        request.Rejection_Reason__c = rejectionReason.trim();
        request.Closure_Date__c = Date.today();
        try {
            update request;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }

    private static Time_Off_Request__c loadForManager(Id requestId, Id managerId) {
        if (requestId == null) {
            throw new AuraHandledException('Request Id is required.');
        }
        List<Time_Off_Request__c> requests = [
            SELECT Id, Stage__c, CreatedById
            FROM Time_Off_Request__c
            WHERE Id = :requestId
            LIMIT 1
        ];
        if (requests.isEmpty()) {
            throw new AuraHandledException('Request not found.');
        }
        Time_Off_Request__c request = requests[0];
        User creator = [
            SELECT Id, ManagerId
            FROM User
            WHERE Id = :request.CreatedById
            LIMIT 1
        ];
        Boolean canApprove = creator.ManagerId == managerId
            || (managerId == UserInfo.getUserId() && FieldPlannerController.canApprovePlannerFor(creator.Id));
        if (!canApprove) {
            throw new AuraHandledException('Only the creator\'s manager can approve or reject.');
        }
        return request;
    }
}